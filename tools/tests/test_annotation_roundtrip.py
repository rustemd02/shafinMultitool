"""End-to-end check of the owner's annotation path on the real queue.

The GUI cannot run headlessly, so this suite exercises the same code path the GUI
uses (queue record → build_label → append → reload → training_targets) against
the real queue the owner will annotate. It also verifies that the queue's
recorded image hashes still match the files on disk: a stale hash would make
every label record the wrong provenance.

Skipped when the queue has not been built on this machine.
"""

from __future__ import annotations

import hashlib
import json
import random
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
ANNOTATION_DIR = REPO_ROOT / "tools/camera_annotation"
if str(ANNOTATION_DIR) not in sys.path:
    sys.path.insert(0, str(ANNOTATION_DIR))

import annotation_labels as labels  # noqa: E402

QUEUE = Path.home() / "Documents/XCode/setos-backend/local-data/SETOS/annotation/queue-v3-cinematic.jsonl"
SAMPLES = 12

pytestmark = pytest.mark.skipif(not QUEUE.exists(), reason="owner annotation queue not built on this machine")


def _records() -> list[dict]:
    return [json.loads(line) for line in QUEUE.read_text(encoding="utf-8").splitlines() if line.strip()]


def _sample() -> list[dict]:
    records = _records()
    random.seed(20260913)
    return random.sample(records, min(SAMPLES, len(records)))


def test_queue_hashes_still_match_the_files_on_disk():
    """A stale image_sha256 would poison every label recorded from that frame."""
    mismatches = []
    for record in _sample():
        path = Path(record["image_path"])
        assert path.exists(), f"{record['record_id']}: image missing at {path}"
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != record["image_sha256"]:
            mismatches.append(record["record_id"])
    assert not mismatches, f"queue hashes are stale for: {mismatches}"


def test_every_queue_record_carries_its_license_provenance():
    """The owner must see the rights status of what they are annotating."""
    for record in _records():
        provenance = record.get("provenance") or {}
        assert isinstance(provenance, dict)
        assert provenance.get("license"), f"{record['record_id']}: no license in provenance"
        assert provenance.get("source"), f"{record['record_id']}: no source in provenance"
        # `kind` is only present for some sources; when present it must be a string.
        if "kind" in provenance:
            assert isinstance(provenance["kind"], str)


def test_gui_shows_every_real_record_its_source_and_license():
    """The GUI must tell the annotator which rights class the frame belongs to."""
    import importlib.util

    spec = importlib.util.spec_from_file_location("ag_rights", ANNOTATION_DIR / "annotate_gui.py")
    gui = importlib.util.module_from_spec(spec)
    sys.modules["ag_rights"] = gui
    spec.loader.exec_module(gui)
    for record in _records():
        caption = gui.provenance_caption(record)
        assert record["provenance"]["source"] in caption
        assert record["provenance"]["license"][:20] in caption


def test_queue_never_claims_release_admission():
    """Nothing in the queue may present itself as release-ready: admitted corpora are 0."""
    for record in _records():
        blob = json.dumps(record, ensure_ascii=False).lower()
        assert "release_admissible\": true" not in blob
        assert "admitted" not in blob


def test_owner_label_round_trip_from_a_real_queue_record(tmp_path: Path):
    """The path the GUI runs: real record → label → store → reload → targets."""
    record = _sample()[0]
    image = Path(record["image_path"])
    store = tmp_path / "labels-owner.jsonl"
    label = labels.build_label(
        record_id=record["record_id"],
        image_sha256=record["image_sha256"],
        annotator_id="owner",
        beauty="borderline",
        improvement_needed=True,
        issues=["insufficient_look_space"],
        actions=["shift_frame_right"],
        deltas={"delta_x": 0.3},
        unsure=False,
        notes="проверка сквозного пути",
        image_path=str(image),
        provenance=record["provenance"],
        created_at="2026-09-13T00:00:00Z",
    )
    assert labels.append_label(store, label) == 1
    reloaded = labels.load_labels(store)
    assert len(reloaded) == 1 and reloaded[0]["record_id"] == record["record_id"]

    targets = labels.training_targets(reloaded[0])
    # the licence travels with the label so downstream consumers can honour it
    assert "CC-BY" in json.dumps(reloaded[0]["provenance"], ensure_ascii=False) or reloaded[0]["provenance"]["license"]
    # only the expressed direction is supervised
    assert targets["continuous_target_deltas"] == [0.3, None, None, None, None]
    assert targets["target_mask"]["continuous_target_deltas"] == [True, False, False, False, False]
    # the frozen heads are all present and correctly sized
    assert len(targets["issue_logits"]) == len(labels.ISSUES) == 8
    assert len(targets["action_utility_logits"]) == len(labels.ACTIONS) == 26
    assert targets["good_frame_probability"] == 0.5


def test_owner_can_re_annotate_without_losing_earlier_labels(tmp_path: Path):
    """The store is append-only; labelled ids must be resumable across sessions."""
    records = _sample()[:2]
    store = tmp_path / "labels-owner.jsonl"
    for index, record in enumerate(records):
        label = labels.build_label(
            record_id=record["record_id"],
            image_sha256=record["image_sha256"],
            annotator_id="owner",
            beauty="beautiful",
            improvement_needed=False,
            actions=[labels.KEEP_ACTION],
            created_at="2026-09-13T00:00:00Z",
        )
        labels.append_label(store, label)
        assert len(labels.labelled_record_ids(store)) == index + 1
    assert labels.labelled_record_ids(store) == {r["record_id"] for r in records}
