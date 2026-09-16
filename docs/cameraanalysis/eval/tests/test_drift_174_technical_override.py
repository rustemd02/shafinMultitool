from __future__ import annotations

import hashlib
import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[4]
BASELINE_DIR = Path(__file__).resolve().parents[1] / "camera-baseline-v0"
LANE = BASELINE_DIR / "drift-174-technical-override"
EDGE_NEUTRAL_ROWS = (
    BASELINE_DIR / "drift-174-calibrated-edge-neutral" / "m4-001-fullruntime-174-drift-r1-edge-neutral.jsonl"
)
OVERRIDE_ROWS = LANE / "m4-001-fullruntime-174-drift-r1-technical-override.jsonl"
LABELS = (
    REPO_ROOT
    / "shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1/camera_full_labels.jsonl"
)


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


def test_lane_artifacts_exist_and_are_pinned() -> None:
    manifest = json.loads((LANE / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["artifacts"], "technical-override manifest must pin artifacts"
    for artifact in manifest["artifacts"]:
        path = REPO_ROOT / artifact["path"]
        assert path.is_file(), artifact["path"]
        assert _sha256(path) == artifact["sha256"], artifact["path"]
        assert path.stat().st_size == artifact["bytes"], artifact["path"]


def test_change_is_confined_to_non_good_frames() -> None:
    comparison = json.loads((LANE / "ab-comparison.json").read_text(encoding="utf-8"))
    edge = _rows_by_record(EDGE_NEUTRAL_ROWS)
    override = _rows_by_record(OVERRIDE_ROWS)
    labels = _labels()

    changed = 0
    changed_on_good = 0
    newly_corrected_good = 0
    for record_id, label in labels.items():
        for mode in ("live", "pause"):
            before = set(edge[record_id][mode].get("semantic_actions") or [])
            after = set(override[record_id][mode].get("semantic_actions") or [])
            if before == after:
                continue
            changed += 1
            if label["quality_label"] == "good":
                changed_on_good += 1
        before_pause = set(edge[record_id]["pause"].get("semantic_actions") or [])
        after_pause = set(override[record_id]["pause"].get("semantic_actions") or [])
        if (
            label["quality_label"] == "good"
            and after_pause - {"keep_current_setup"}
            and not before_pause - {"keep_current_setup"}
        ):
            newly_corrected_good += 1

    invariants = comparison["mechanism_invariants"]
    assert invariants["live_and_pause_rows_with_changed_actions_vs_edge_neutral"] == changed
    assert invariants["changed_rows_on_good_labelled_frames"] == changed_on_good
    assert invariants["good_frames_that_newly_receive_corrective_advice"] == newly_corrected_good
    assert changed_on_good == 0
    assert newly_corrected_good == 0


def test_metrics_match_scored_artifacts_and_improve_without_preservation_cost() -> None:
    comparison = json.loads((LANE / "ab-comparison.json").read_text(encoding="utf-8"))
    metrics = comparison["still_replay_metrics"]
    edge = metrics["edge_neutral"]
    override = metrics["technical_override"]
    assert metrics["edge_neutral"] == json.loads(
        (BASELINE_DIR / "drift-174-calibrated-edge-neutral/scored/set_metrics.json").read_text(
            encoding="utf-8"
        )
    )["set_metrics"]
    assert metrics["technical_override"] == json.loads(
        (LANE / "scored/set_metrics.json").read_text(encoding="utf-8")
    )["set_metrics"]
    assert override["expected_action_hit_rate"] > edge["expected_action_hit_rate"]
    assert override["forbidden_action_violation_rate"] < edge["forbidden_action_violation_rate"]
    assert override["pass_rate"] > edge["pass_rate"]
    assert override["good_frame_preservation_rate"] == edge["good_frame_preservation_rate"]
    assert override["positive_confirmation_rate"] == edge["positive_confirmation_rate"]


def test_control_run_records_the_delta() -> None:
    comparison = json.loads((LANE / "ab-comparison.json").read_text(encoding="utf-8"))
    run = comparison["control_run"]
    assert run["phase_a"]["edge_neutral"] == run["phase_a"]["technical_override"]
    assert run["phase_b"]["technical_override"] == "177 / 142 passed / 35 failed"
    assert run["phase_b"]["edge_neutral"] == "177 / 140 passed / 37 failed"
    assert run["newly_failing_vs_edge_neutral"] == []
    assert len(run["fixed_vs_edge_neutral"]) == 2
