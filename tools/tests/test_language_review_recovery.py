"""Annotation recovery on generated media and isolated journals; no live provider."""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest
from PIL import Image

ANNOTATION_DIR = Path(__file__).resolve().parents[1] / "camera_annotation"
if str(ANNOTATION_DIR) not in sys.path:
    sys.path.insert(0, str(ANNOTATION_DIR))

import annotation_labels as labels
import annotate_gui as gui
import language_review as review_module
import review_pipeline


def interpretation():
    return dict(verdict=dict(value="unknown", evidence=""), issues=[], actions=[],
        intent=dict(value="unknown", evidence=""), subject=dict(description="", evidence=""),
        temporal=dict(value="not_stated", evidence=""), spatial_requests=[], unmapped=[], question=None)


@pytest.fixture
def fake_provider(monkeypatch):
    calls = []

    def respond(path, key="", payload=None):
        assert path == "chat/completions"
        calls.append(payload)
        return dict(choices=[dict(message=dict(content=json.dumps(interpretation())))], usage={})

    monkeypatch.setattr(review_module, "command_api", respond)
    return calls


@pytest.fixture
def review(tmp_path, fake_provider):
    queue = []
    for index in range(2):
        path = tmp_path / f"photo-{index}.png"
        Image.new("RGB", (24, 16), (40 + index, 70, 90)).save(path)
        queue.append(dict(record_id=f"photo-{index}", kind="photo", media_path=str(path),
            media_sha256=labels.sha256_file(path), title="Generated test fixture", source={}, **review_module.FLAGS))
    value = review_module.Review(tmp_path, queue, "test-fixture-only", 3)
    value.key = "fake-provider-only"
    try:
        yield value
    finally:
        value.close()
        assert not value.worker.is_alive()


def visual_request(review, *, finish=True):
    rid = "photo-0"
    cache_key = review.cache_key(rid)
    fields = dict(record_id=rid, cache_key=cache_key, job_id="visual-" + cache_key[:32],
        media_sha256=review.items[rid]["media_sha256"], media_kind="photo")
    review.event("visual_dispatch", provider="command-code", paid=True, **fields)
    review.request_count += 1
    if finish:
        review.event("visual_proposal", interpretation=interpretation(), **fields)
    return fields


def manual_revision(review, state="draft", rid="photo-0"):
    return review.event(state, record_id=rid, review_id="fixture-manual-1", raw_text="Fixture correction",
        media_sha256=review.items[rid]["media_sha256"], media_kind="photo", viewed_at_s=None,
        interpretation=interpretation())


@pytest.mark.parametrize("failure", ["missing", "sha_changed", "undecodable"])
def test_local_media_failure_keeps_worker_alive_and_preserves_budget(review, fake_provider, failure):
    item = review.items["photo-0"]
    path = Path(item["media_path"])
    if failure == "missing":
        path.unlink()
    else:
        path.write_bytes(b"generated invalid image")
        if failure == "undecodable":
            item["media_sha256"] = labels.sha256_file(path)

    assert review.prefetch(["photo-0", "photo-1"])["scheduled"] == 2
    with review.condition:
        assert review.condition.wait_for(lambda: not review.pending and review.inflight is None, timeout=5)

    assert review.worker.is_alive()
    assert review.visual_status("photo-0")["status"] == "error"
    assert review.visual_status("photo-1")["status"] == "ready"
    failed_event = review.visual_event("photo-0")
    assert failed_event["paid"] is False and failed_event["pixels_sent"] is False
    assert failed_event["billing_unknown"] is False
    assert review.request_count == len(fake_provider) == 1
    assert review.billing_unknown is False
    assert review.prefetch(["photo-0", "photo-1"])["scheduled"] == 0

    review.close()
    original_journal = review.journal.read_bytes()
    reopened = review_module.Review(review.folder, list(review.items.values()), review.annotator, 3)
    try:
        assert reopened.request_count == 1
        assert reopened.billing_unknown is False
        assert reopened.visual_status("photo-0")["status"] == "error"
        assert reopened.visual_status("photo-1")["status"] == "ready"
        assert reopened.journal.read_bytes() == original_journal
    finally:
        reopened.close()


def test_ambiguous_provider_failure_still_blocks_later_paid_jobs(review, monkeypatch):
    def fail(*args, **kwargs):
        raise RuntimeError("fixture transport interruption")

    monkeypatch.setattr(review_module, "command_api", fail)
    review.prefetch(["photo-0", "photo-1"])
    with review.condition:
        assert review.condition.wait_for(lambda: not review.pending and review.inflight is None, timeout=5)
    assert review.worker.is_alive()
    assert review.request_count == 1
    assert review.billing_unknown is True
    assert review.visual_status("photo-0")["status"] == "error"
    assert review.visual_event("photo-1") is None
    assert review.prefetch(["photo-1"])["reason"] == "billing_unknown"


@pytest.mark.parametrize("state", ["draft", "raw", "confirmed"])
def test_stale_tab_cannot_confirm_visual_over_newer_manual_revision(review, state):
    request = visual_request(review)
    manual_revision(review, state)
    original_journal = review.journal.read_bytes()

    with pytest.raises(ValueError, match="более новое мнение"):
        review.confirm_visual(dict(record_id="photo-0", job_id=request["job_id"]))

    assert review.visual_status("photo-0")["status"] == "error"
    assert review.journal.read_bytes() == original_journal
    assert not any(e["state"] == "visual_confirmed" for e in review.events)


def test_slow_visual_response_uses_dispatch_order_for_revision_admission(review):
    request = visual_request(review, finish=False)
    manual_revision(review)
    review.event("visual_proposal", interpretation=interpretation(), **request)
    with pytest.raises(ValueError, match="более новое мнение"):
        review.confirm_visual(dict(record_id="photo-0", job_id=request["job_id"]))


def test_new_manual_draft_reopens_review_after_old_visual_confirmation(review):
    request = visual_request(review)
    assert review.confirm_visual(dict(record_id="photo-0", job_id=request["job_id"])) == dict(saved=True)
    manual_revision(review)

    item = next(i for i in review.snapshot()["items"] if i["record_id"] == "photo-0")
    assert item["reviewed"] is False
    assert item["raw_text"] == "Fixture correction"
    original_journal = review.journal.read_bytes()
    with pytest.raises(ValueError, match="более новое мнение"):
        review.confirm_visual(dict(record_id="photo-0", job_id=request["job_id"]))
    assert review.journal.read_bytes() == original_journal


def test_current_visual_confirmation_is_idempotent_and_remains_research_only(review):
    request = visual_request(review)
    manual_revision(review, rid="photo-1")
    data = dict(record_id="photo-0", job_id=request["job_id"])
    assert review.confirm_visual(data) == dict(saved=True)
    original_journal = review.journal.read_bytes()
    assert review.confirm_visual(data) == dict(saved=True)
    assert review.journal.read_bytes() == original_journal
    event = review.visual_event("photo-0")
    assert event["human_gold"] is False and event["release_admissible"] is False
    assert event["research_only"] is True
    assert event["contract_projection"]["training_ready"] is False


def test_relocated_gui_and_export_readers_preserve_historical_queue_and_hash_checks(tmp_path, monkeypatch):
    canonical = tmp_path / "relocated"
    canonical.mkdir()
    monkeypatch.setattr(labels, "DATA", canonical)
    path = canonical / "frame.png"
    Image.new("RGB", (24, 16), (80, 110, 130)).save(path)
    old_path = labels.LEGACY_DATA / "frame.png"
    row = dict(record_id="fixture-relocated", image_path=str(old_path), image_sha256=labels.sha256_file(path),
        split="train", source_group="generated-test-only", matrix_class="interior", review_mode="blind", provenance={})
    queue = tmp_path / "historical-queue.jsonl"
    queue.write_text(json.dumps(row) + "\n")
    original_bytes = queue.read_bytes()

    loaded = gui.load_queue(queue)
    assert Path(loaded[0]["image_path"]) == path
    assert review_module.local_media_path(old_path) == path
    assert review_pipeline.checked_image(row) == path
    label = labels.build_label(record_id=row["record_id"], image_sha256=row["image_sha256"],
        annotator_id="test-fixture-only", beauty="beautiful", improvement_needed=False,
        actions=["keep_current_setup"], capture_intent="natural", review_mode="blind", matrix_class="interior",
        regions=[dict(role="subject", rect=[.1, .1, .5, .5])])
    target = review_pipeline.training_record(label, row)
    assert target["pixels"]["width"] == 24 and target["pixels"]["height"] == 16
    assert target["targets"]["risk"] is None and target["targets"]["abstention"] is None
    assert queue.read_bytes() == original_bytes and row["image_path"] == str(old_path)

    path.write_bytes(b"changed fixture bytes")
    with pytest.raises(ValueError, match="Image missing or SHA changed"):
        review_pipeline.checked_image(row)
    assert queue.read_bytes() == original_bytes


def test_media_relocation_does_not_rewrite_unrelated_or_current_paths(tmp_path):
    assert labels.local_media_path(tmp_path / "outside.png") == tmp_path / "outside.png"
    current = labels.DATA / "current.png"
    assert labels.local_media_path(current) == current
    similar_prefix = str(labels.LEGACY_DATA) + "-other/frame.png"
    assert labels.local_media_path(similar_prefix) == Path(similar_prefix)
