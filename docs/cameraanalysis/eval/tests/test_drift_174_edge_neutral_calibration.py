from __future__ import annotations

import hashlib
import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[4]
BASELINE = Path(__file__).resolve().parents[1] / "camera-baseline-v0" / "drift-174"
CALIBRATED = (
    Path(__file__).resolve().parents[1]
    / "camera-baseline-v0"
    / "drift-174-calibrated-edge-neutral"
)
LABELS = (
    REPO_ROOT
    / "shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1/camera_full_labels.jsonl"
)
BASELINE_ROWS = BASELINE / "m4-001-fullruntime-174-drift-r1.jsonl"
CALIBRATED_ROWS = CALIBRATED / "m4-001-fullruntime-174-drift-r1-edge-neutral.jsonl"


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _rows_by_record(path: Path) -> dict[str, dict[str, dict]]:
    grouped: dict[str, dict[str, dict]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        row = json.loads(line)
        grouped.setdefault(row["record_id"], {})[row.get("mode")] = row
    return grouped


def _labels() -> dict[str, dict]:
    return {
        json.loads(line)["record_id"]: json.loads(line)
        for line in LABELS.read_text(encoding="utf-8").splitlines()
        if line.strip()
    }


def test_calibration_lane_artifacts_exist_and_are_pinned() -> None:
    manifest = json.loads((CALIBRATED / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["artifacts"], "calibration manifest must pin artifacts"
    for artifact in manifest["artifacts"]:
        path = REPO_ROOT / artifact["path"]
        assert path.is_file(), artifact["path"]
        assert _sha256(path) == artifact["sha256"], artifact["path"]
        assert path.stat().st_size == artifact["bytes"], artifact["path"]


def test_comparison_numbers_match_the_committed_row_files() -> None:
    comparison = json.loads((CALIBRATED / "ab-comparison.json").read_text(encoding="utf-8"))
    baseline = _rows_by_record(BASELINE_ROWS)
    calibrated = _rows_by_record(CALIBRATED_ROWS)
    labels = _labels()

    changed_rows = 0
    non_object_changes = 0
    recovered: list[str] = []
    newly_overcorrected: list[str] = []
    new_false_keep: list[str] = []
    for record_id, label in labels.items():
        for mode in ("live", "pause"):
            before = set(baseline[record_id][mode].get("semantic_actions") or [])
            after = set(calibrated[record_id][mode].get("semantic_actions") or [])
            if before == after:
                continue
            changed_rows += 1
            before_kind = baseline[record_id][mode].get("debug_semantic_labels", {}).get(
                "primary_subject_kind"
            )
            after_kind = calibrated[record_id][mode].get("debug_semantic_labels", {}).get(
                "primary_subject_kind"
            )
            if before_kind != "object" and after_kind != "object":
                non_object_changes += 1

        before_pause = set(baseline[record_id]["pause"].get("semantic_actions") or [])
        after_pause = set(calibrated[record_id]["pause"].get("semantic_actions") or [])
        before_corrective = before_pause - {"keep_current_setup"}
        after_corrective = after_pause - {"keep_current_setup"}
        if label["quality_label"] == "good":
            if before_corrective and not after_corrective:
                recovered.append(record_id)
            if after_corrective and not before_corrective:
                newly_overcorrected.append(record_id)
        elif "keep_current_setup" not in before_pause and "keep_current_setup" in after_pause:
            new_false_keep.append(record_id)

    invariants = comparison["mechanism_invariants"]
    assert invariants["live_and_pause_rows_with_changed_actions"] == changed_rows
    assert invariants["changed_rows_where_neither_side_is_object_primary"] == non_object_changes
    assert invariants["good_frames_that_stopped_receiving_corrective_advice"] == len(recovered)
    assert invariants["good_frames_that_newly_receive_corrective_advice"] == len(newly_overcorrected)
    assert invariants["non_good_frames_that_newly_keep"] == len(new_false_keep)


def test_calibration_metric_deltas_match_scored_artifacts() -> None:
    comparison = json.loads((CALIBRATED / "ab-comparison.json").read_text(encoding="utf-8"))
    baseline_metrics = json.loads((BASELINE / "scored/set_metrics.json").read_text(encoding="utf-8"))[
        "set_metrics"
    ]
    calibrated_metrics = json.loads(
        (CALIBRATED / "scored/set_metrics.json").read_text(encoding="utf-8")
    )["set_metrics"]
    assert comparison["still_replay_metrics"]["baseline"] == baseline_metrics
    assert comparison["still_replay_metrics"]["calibrated"] == calibrated_metrics
    for name, delta in comparison["still_replay_metrics"]["delta"].items():
        assert delta == round(calibrated_metrics[name] - baseline_metrics[name], 6), name


def test_changed_rows_are_confined_to_object_primaries() -> None:
    comparison = json.loads((CALIBRATED / "ab-comparison.json").read_text(encoding="utf-8"))
    assert comparison["mechanism_invariants"]["changed_rows_where_neither_side_is_object_primary"] == 0
    assert comparison["mechanism_invariants"]["good_frames_that_newly_receive_corrective_advice"] == 0


def test_control_run_records_both_phases_and_the_new_failure() -> None:
    comparison = json.loads((CALIBRATED / "ab-comparison.json").read_text(encoding="utf-8"))
    run = comparison["control_run"]
    assert run["phase_a"]["baseline"] == run["phase_a"]["calibrated"]
    assert run["phase_b"]["baseline"] == "177 / 138 passed / 39 failed"
    assert run["phase_b"]["calibrated"] == "177 / 140 passed / 37 failed"
    assert run["newly_failing_with_calibration"] == [
        "testStillImageReplaySuppressesFalseKeepForBadTechnicalFrames"
    ]
    assert len(run["fixed_by_calibration"]) == 3
