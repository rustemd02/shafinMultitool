"""Paid scheduling and revision regressions on generated data; no live API."""
from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
import sys
import threading

import pytest
from PIL import Image

ANNOTATION_DIR = Path(__file__).resolve().parents[1] / "camera_annotation"
sys.path.insert(0, str(ANNOTATION_DIR))
import language_review as module


def interpretation():
    return dict(verdict=dict(value="unknown", evidence=""), issues=[], actions=[],
        intent=dict(value="unknown", evidence=""), subject=dict(description="", evidence=""),
        temporal=dict(value="not_stated", evidence=""), spatial_requests=[], unmapped=[], question=None)


def queue(folder):
    result = []
    for index in range(3):
        image = folder / f"generated-{index}.png"
        Image.new("RGB", (20, 16), (30 + index, 80, 120)).save(image)
        result.append(dict(record_id=f"record-{index}", kind="photo", media_path=str(image),
            media_sha256=module.sha256_file(image), title="Generated regression only", source={}, **module.FLAGS))
    return result


@pytest.fixture
def review(tmp_path, monkeypatch):
    calls = []
    def respond(path, key="", payload=None):
        assert path == "chat/completions"
        calls.append(payload)
        return dict(choices=[dict(message=dict(content=json.dumps(interpretation())))], usage={})
    monkeypatch.setattr(module, "command_api", respond)
    value = module.Review(tmp_path, queue(tmp_path), "generated-regression-only", 100)
    value.key = "fixture-provider-only"
    value.fixture_calls = calls
    try:
        yield value
    finally:
        value.close()
        assert not value.worker.is_alive()


def visual(review, *, confirmed=False):
    rid = "record-0"
    cache_key = review.cache_key(rid)
    fields = dict(record_id=rid, job_id="visual-" + cache_key[:32], cache_key=cache_key,
        media_sha256=review.items[rid]["media_sha256"], media_kind="photo")
    review.event("visual_dispatch", provider="command-code", **fields)
    review.request_count += 1
    review.event("visual_proposal", interpretation=interpretation(), **fields)
    if confirmed:
        review.confirm_visual(dict(record_id=rid, job_id=fields["job_id"]))
    return fields


@pytest.mark.parametrize("usage", ["malformed", [1], 7, True])
def test_malformed_optional_usage_cannot_kill_the_visual_worker(review, monkeypatch, usage):
    calls = []
    def respond(path, key="", payload=None):
        calls.append(payload)
        return dict(choices=[dict(message=dict(content=json.dumps(interpretation())))], usage=usage)
    monkeypatch.setattr(module, "command_api", respond)
    review.prefetch(["record-0", "record-1"])
    with review.condition:
        finished = review.condition.wait_for(lambda: not review.pending and review.inflight is None, timeout=2)
    assert finished and review.worker.is_alive()
    assert len(calls) == review.request_count == 2
    assert review.billing_unknown is False
    for rid in ["record-0", "record-1"]:
        assert review.visual_status(rid)["status"] == "ready"
        assert review.visual_event(rid)["usage"] == {}


def test_malformed_error_envelope_does_not_crash_error_reporting(review, monkeypatch):
    def respond(path, key="", payload=None):
        return dict(usage="malformed", choices=[])
    monkeypatch.setattr(module, "command_api", respond)
    review.prefetch(["record-0"])
    with review.condition:
        assert review.condition.wait_for(lambda: not review.pending and review.inflight is None, timeout=2)
    assert review.worker.is_alive()
    assert review.visual_status("record-0")["status"] == "error"
    assert review.visual_event("record-0")["usage"] == {}
    assert review.request_count == 1


@pytest.mark.parametrize("state", ["visual_error", "error"])
def test_restart_preserves_explicit_ambiguous_paid_value_error(review, state):
    fields = dict(record_id="record-0", provider="command-code")
    if state == "visual_error":
        fields.update(job_id="fixture-ambiguous-job", cache_key=review.cache_key("record-0"))
        dispatch = "visual_dispatch"
    else:
        fields.update(review_id="fixture-ambiguous-review")
        dispatch = "dispatch"
    review.event(dispatch, paid=True, **fields)
    review.event(state, error="ValueError", billing_unknown=True, **fields)
    review.close()
    original = review.journal.read_bytes()
    reopened = module.Review(review.folder, list(review.items.values()), review.annotator, 100)
    try:
        reopened.key = "fixture-provider-only"
        assert reopened.billing_unknown is True
        assert reopened.request_count == 1
        assert reopened.prefetch(["record-1"])["reason"] == "billing_unknown"
        assert reopened.journal.read_bytes() == original
    finally:
        reopened.close()


class OrderedManualPaidSlot:
    """Make an obsolete request resume first, independently of thread scheduling."""
    def __init__(self):
        self.lock = threading.Lock()
        self.old_waiting = threading.Event()
        self.new_waiting = threading.Event()
        self.old_permit = threading.Event()
        self.new_permit = threading.Event()

    def acquire(self, *args, **kwargs):
        old = threading.current_thread().name == "fixture-old-manual"
        waiting = self.old_waiting if old else self.new_waiting
        permit = self.old_permit if old else self.new_permit
        waiting.set()
        if not permit.wait(5):
            raise AssertionError("Fixture did not release the paid slot")
        return self.lock.acquire(timeout=5)

    def release(self):
        self.lock.release()


@pytest.mark.parametrize("newer_kind", ["raw", "draft"])
@pytest.mark.parametrize("stage", ["waiting_paid_lock", "during_media_parts"])
def test_obsolete_manual_revision_never_dispatches_after_newer_intent(review, monkeypatch, stage, newer_kind):
    slot = OrderedManualPaidSlot()
    monkeypatch.setattr(review, "paid_lock", slot)
    preparation_entered = threading.Event()
    preparation_release = threading.Event()
    original_parts = review.media_parts

    def prepare(rid):
        if stage == "during_media_parts" and threading.current_thread().name == "fixture-old-manual":
            assert slot.lock.locked(), "Preparation must run after acquiring paid_lock"
            preparation_entered.set()
            if not preparation_release.wait(5):
                raise AssertionError("Fixture preparation was not released")
        return original_parts(rid)

    monkeypatch.setattr(review, "media_parts", prepare)
    old = dict(record_id="record-0", text="Generated obsolete manual opinion",
        request_id="fixture-obsolete-manual", viewed_at_s=None)
    new = dict(record_id="record-0", text="Generated current manual opinion",
        request_id="fixture-current-manual", viewed_at_s=None)
    responses = {}
    failures = []

    def interpret(label, request):
        try:
            responses[label] = review.interpret(request, paid=True)
        except BaseException as exc:
            failures.append((label, type(exc).__name__, str(exc)))

    older = threading.Thread(target=interpret, args=("old", old), name="fixture-old-manual")
    newer = None
    try:
        if stage == "during_media_parts":
            slot.old_permit.set()
        older.start()
        if stage == "waiting_paid_lock":
            assert slot.old_waiting.wait(3)
        else:
            assert preparation_entered.wait(3)
        assert [event["state"] for event in review.events] == ["draft"]

        if newer_kind == "raw":
            responses["new"] = review.interpret(new, paid=False)
        else:
            newer = threading.Thread(target=interpret, args=("new", new), name="fixture-new-manual")
            newer.start()
            assert slot.new_waiting.wait(3), "The current draft must persist before the old request resumes"
        assert review.events[-1]["review_id"] == new["request_id"]
        assert review.fixture_calls == []

        slot.old_permit.set()
        preparation_release.set()
        older.join(timeout=5)
        assert not older.is_alive()
        assert not failures
        assert responses["old"].get("error") and responses["old"].get("draft_saved") is True
        assert review.fixture_calls == [], "Obsolete text reached the provider"
        assert review.request_count == 0
        assert not any(event["state"] == "dispatch" and event.get("review_id") == old["request_id"]
            for event in review.events)

        slot.new_permit.set()
        if newer:
            newer.join(timeout=5)
            assert not newer.is_alive()
        assert not failures
        expected_requests = 1 if newer_kind == "draft" else 0
        assert len(review.fixture_calls) == review.request_count == expected_requests
        if newer_kind == "draft":
            assert responses["new"]["review_id"] == new["request_id"]
            assert "interpretation" in responses["new"]
            human_review = json.loads(review.fixture_calls[0]["messages"][1]["content"][0]["text"])["human_review"]
            assert human_review == new["text"]
            dispatches = [event for event in module.rows(review.journal) if event["state"] == "dispatch"]
            assert len(dispatches) == 1 and dispatches[0]["review_id"] == new["request_id"]
        else:
            assert responses["new"] == dict(saved=True)
        latest = next(item for item in review.snapshot()["items"] if item["record_id"] == "record-0")
        assert latest["raw_text"] == new["text"] and latest["review_id"] == new["request_id"]
        assert review.billing_unknown is False
    finally:
        slot.old_permit.set()
        slot.new_permit.set()
        preparation_release.set()
        older.join(timeout=5)
        if newer:
            newer.join(timeout=5)
        assert not older.is_alive() and (newer is None or not newer.is_alive())



def video_item(folder):
    photos = queue(folder)
    movie = folder / "generated-video.fixture"
    movie.write_bytes(b"not a real movie; no video decoder is invoked by this test")
    return dict(record_id="video-fixture", kind="video", media_path=str(movie),
        media_sha256=module.sha256_file(movie), title="Generated video frame contract", source={},
        visual_frames=[dict(path=p["media_path"], sha256=p["media_sha256"], timestamp_s=index)
                       for index, p in enumerate(photos)], **module.FLAGS)


@pytest.mark.parametrize("change", ["sha256", "order", "timestamp"])
def test_video_cache_binds_ordered_actual_frame_inputs(tmp_path, change):
    item = video_item(tmp_path)
    first = module.Review(tmp_path, [item], "generated-cache-only", 100)
    try:
        original_key = first.cache_key(item["record_id"])
        first.event("visual_proposal", record_id=item["record_id"], job_id="fixture-cached-video",
            cache_key=original_key, interpretation=interpretation(), media_kind="video")
    finally:
        first.close()
    revised = deepcopy(item)
    if change == "sha256": revised["visual_frames"][1]["sha256"] = "f" * 64
    elif change == "order": revised["visual_frames"].reverse()
    else: revised["visual_frames"][1]["timestamp_s"] = 1.5
    reopened = module.Review(tmp_path, [revised], "generated-cache-only", 100)
    try:
        assert reopened.cache_key(item["record_id"]) != original_key
        assert reopened.visual_event(item["record_id"]) is None
    finally:
        reopened.close()


def test_video_cache_ignores_local_path_relocation(tmp_path):
    item = video_item(tmp_path)
    value = module.Review(tmp_path, [item], "generated-cache-only", 100)
    try:
        original = value.cache_key(item["record_id"])
        item["media_path"] = str(tmp_path / "relocated-video.fixture")
        for index, frame in enumerate(item["visual_frames"]):
            frame["path"] = str(tmp_path / f"relocated-frame-{index}.png")
        assert value.cache_key(item["record_id"]) == original
    finally:
        value.close()


def test_manual_correction_is_durable_before_waiting_for_the_paid_slot(review, monkeypatch):
    request = visual(review)
    draft_written = threading.Event()
    event = review.event
    def observed_event(state, **fields):
        value = event(state, **fields)
        if state == "draft": draft_written.set()
        return value
    monkeypatch.setattr(review, "event", observed_event)
    result = []
    review.paid_lock.acquire()
    worker = threading.Thread(target=lambda: result.append(review.interpret(dict(
        record_id="record-0", text="Generated pending correction", request_id="fixture-correction-request", viewed_at_s=None))))
    worker.start()
    try:
        assert draft_written.wait(0.5), "Manual intent was held only in a waiting HTTP thread"
        persisted = module.rows(review.journal)
        assert persisted[-1]["state"] == "draft" and persisted[-1]["raw_text"] == "Generated pending correction"
        assert review.fixture_calls == []
        with pytest.raises(ValueError, match="более новое мнение"):
            review.confirm_visual(dict(record_id="record-0", job_id=request["job_id"]))
    finally:
        review.paid_lock.release()
        worker.join(timeout=3)
    assert not worker.is_alive() and len(result) == 1
    assert len(review.fixture_calls) == 1


def test_save_raw_does_not_wait_for_paid_analysis(review):
    finished = threading.Event()
    result = []
    def save():
        result.append(review.interpret(dict(record_id="record-0", text="Generated raw opinion",
            request_id="fixture-raw-request", viewed_at_s=None), paid=False))
        finished.set()
    review.paid_lock.acquire()
    worker = threading.Thread(target=save)
    worker.start()
    try:
        assert finished.wait(0.5), "Unpaid durable text was blocked behind the provider"
        assert result == [dict(saved=True)]
        assert module.rows(review.journal)[-1]["state"] == "raw"
        assert review.fixture_calls == []
    finally:
        review.paid_lock.release()
        worker.join(timeout=3)
    assert not worker.is_alive()


def test_waiting_visual_yields_to_durable_manual_revision(review, monkeypatch):
    prepared = threading.Event()
    raw_finished = threading.Event()
    original_parts = review.media_parts
    def prepare(rid):
        result = original_parts(rid)
        prepared.set()
        return result
    monkeypatch.setattr(review, "media_parts", prepare)
    result = []
    def raw():
        result.append(review.interpret(dict(record_id="record-0", text="New generated manual opinion",
            request_id="fixture-new-manual-before-dispatch", viewed_at_s=None), paid=False))
        raw_finished.set()
    review.paid_lock.acquire()
    automatic = threading.Thread(target=lambda: review.analyze_visual("record-0"))
    manual = threading.Thread(target=raw)
    automatic.start()
    try:
        assert prepared.wait(1)
        manual.start()
        assert raw_finished.wait(0.5)
    finally:
        review.paid_lock.release()
        automatic.join(timeout=3)
        if manual.ident is not None: manual.join(timeout=3)
    assert not automatic.is_alive() and not manual.is_alive()
    assert result == [dict(saved=True)]
    assert review.fixture_calls == [] and review.request_count == 0
    assert review.visual_event("record-0") is None
    assert review.prefetch(["record-0"])["scheduled"] == 0
    item = next(row for row in review.snapshot()["items"] if row["record_id"] == "record-0")
    assert item["reviewed"] is True and item["raw_text"] == "New generated manual opinion"


@pytest.mark.parametrize("already_confirmed", [False, True])
@pytest.mark.parametrize("newer", ["draft", "visual_confirmed"])
def test_stale_manual_confirmation_cannot_override_newer_revision(review, already_confirmed, newer):
    request_id = "fixture-old-correction"
    text = "Generated older correction"
    fields = review.opinion(dict(record_id="record-0", text=text, request_id=request_id, viewed_at_s=None))
    review.event("draft", **fields)
    review.event("proposal", interpretation=interpretation(), **fields)
    data = dict(record_id="record-0", review_id=request_id, text=text)
    if already_confirmed: assert review.confirm(data) == dict(saved=True)
    if newer == "draft":
        later = review.opinion(dict(record_id="record-0", text="Generated newer correction",
            request_id="fixture-new-correction", viewed_at_s=None))
        review.event("draft", **later)
    else:
        visual(review, confirmed=True)
    previous = review.journal.read_bytes()
    with pytest.raises(ValueError, match="более новое мнение"):
        review.confirm(data)
    assert review.journal.read_bytes() == previous


def test_visual_and_manual_dispatch_share_exact_persisted_100_request_cap(review):
    for index in range(99):
        fields = dict(record_id="old-generated-record", review_id=f"fixture-history-{index}", provider="command-code")
        review.event("dispatch", paid=True, **fields)
        review.event("proposal", interpretation=interpretation(), **fields)
    review.request_count = 99
    start = threading.Barrier(3)
    result = []
    def manual():
        start.wait()
        result.append(review.interpret(dict(record_id="record-1", text="Generated budget correction",
            request_id="fixture-budget-correction", viewed_at_s=None)))
    def automatic():
        start.wait()
        review.analyze_visual("record-0")
    workers = [threading.Thread(target=manual), threading.Thread(target=automatic)]
    for worker in workers: worker.start()
    start.wait()
    for worker in workers: worker.join(timeout=3)
    assert all(not worker.is_alive() for worker in workers)
    assert len(result) == 1 and len(review.fixture_calls) == 1 and review.request_count == 100
    assert sum(e["state"] in {"dispatch", "visual_dispatch"} for e in module.rows(review.journal)) == 100
    review.close()
    reopened = module.Review(review.folder, list(review.items.values()), review.annotator, 100)
    try:
        reopened.key = "fixture-provider-only"
        assert reopened.request_count == 100 and reopened.billing_unknown is False
        assert reopened.prefetch(["record-2"])["reason"] == "limit"
        prior = len(review.fixture_calls)
        assert reopened.interpret(dict(record_id="record-2", text="Generated over-budget correction",
            request_id="fixture-over-budget", viewed_at_s=None))["draft_saved"] is True
        assert len(review.fixture_calls) == prior
        assert all(not event["human_gold"] and not event["release_admissible"] and event["research_only"]
                   for event in reopened.events)
    finally:
        reopened.close()
