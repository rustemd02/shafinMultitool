from __future__ import annotations

import hashlib
import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[4]
LANE = (
    Path(__file__).resolve().parents[1]
    / "camera-baseline-v0"
    / "drift-174-framing-isolation-review"
)
ROWS = (
    Path(__file__).resolve().parents[1]
    / "camera-baseline-v0"
    / "drift-174-probe-instrumentation"
    / "m4-001-fullruntime-174-drift-r1-probe-instrumented.jsonl"
)
LABELS = (
    REPO_ROOT
    / "shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1/camera_full_labels.jsonl"
)


def _rows() -> dict[str, dict[str, dict]]:
    grouped: dict[str, dict[str, dict]] = {}
    for line in ROWS.read_text(encoding="utf-8").splitlines():
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


def _feature(rows: dict[str, dict[str, dict]], record_id: str, key: str) -> float:
    return rows[record_id]["pause"]["debug_numeric_features"].get(key) or 0.0


def _merged(rows: dict[str, dict[str, dict]], record_id: str) -> set[str]:
    actions: set[str] = set()
    for row in rows[record_id].values():
        actions |= set(row.get("semantic_actions") or [])
    return actions


def test_framing_review_numbers_match_the_row_files() -> None:
    report = json.loads((LANE / "framing-isolation-review.json").read_text(encoding="utf-8"))
    rows = _rows()
    labels = _labels()
    step_back = {
        entry["record_id"]: entry
        for entry in report["part_1_framing_label_review"]["records"]
        if entry["expected"] == "step_back"
    }
    step_closer = {
        entry["record_id"]: entry
        for entry in report["part_1_framing_label_review"]["records"]
        if entry["expected"] == "step_closer"
    }
    assert report["part_1_framing_label_review"]["step_back"]["records"] == len(step_back)
    assert report["part_1_framing_label_review"]["step_closer"]["records"] == len(step_closer)
    label_occlusion = sum(1 for entry in step_back.values() if "avoid_occlusion" in entry["label_future_actions"])
    pipeline_occlusion = sum(
        1 for entry in step_back.values() if "avoid_occlusion" in entry["pipeline_future_actions"]
    )
    assert report["part_1_framing_label_review"]["step_back"]["records"] == len(step_back)
    assert f"{label_occlusion} of {len(step_back)}" in report["part_1_framing_label_review"]["step_back"]["label_intent"]
    assert f"{pipeline_occlusion} of {len(step_back)}" in report["part_1_framing_label_review"]["step_back"]["pipeline_side"]
    lane_occlusion = [
        record_id
        for record_id in labels
        if "avoid_occlusion" in (rows[record_id]["pause"].get("future_actions") or [])
    ]
    lane_without_semantic = [
        record_id for record_id in lane_occlusion if not (rows[record_id]["pause"].get("semantic_actions") or [])
    ]
    context = report["part_1_framing_label_review"]["step_back"]["lane_context"]
    assert context["rows_with_avoid_occlusion_in_future"] == len(lane_occlusion)
    assert context["of_which_without_any_semantic_action"] == len(lane_without_semantic)
    assert report["part_1_framing_label_review"]["step_closer"]["stated_small_subject_records"] == [
        "ca_img_096",
        "ca_img_212",
        "ca_img_220",
        "ca_img_228",
        "ca_img_236",
    ]


def test_heldout_split_grid_matches_the_row_files() -> None:
    report = json.loads((LANE / "framing-isolation-review.json").read_text(encoding="utf-8"))
    rows = _rows()
    labels = _labels()
    ids = sorted(labels)
    half_a = [record_id for index, record_id in enumerate(ids) if index % 2 == 0]
    half_b = [record_id for index, record_id in enumerate(ids) if index % 2 == 1]

    def wants_background(record_id: str) -> bool:
        return bool(
            {"simplify_background", "remove_distracting_object"}
            & set(labels[record_id]["expected_semantic_actions"] or [])
        )

    def has_background(record_id: str) -> bool:
        return bool(
            {"simplify_background", "remove_distracting_object"} & _merged(rows, record_id)
        )

    def missing_background(record_id: str) -> bool:
        return wants_background(record_id) and not has_background(record_id)

    for entry in report["part_2_isolation_rule_heldout_decision"]["grid"]:
        threshold = entry["clutter_threshold"]
        assert entry["derivation_half"]["true_positives"] == sum(
            1
            for record_id in half_a
            if missing_background(record_id) and _feature(rows, record_id, "background_clutter") >= threshold
        )
        assert entry["derivation_half"]["false_positives_on_good_records"] == sum(
            1
            for record_id in half_a
            if labels[record_id]["quality_label"] == "good"
            and _feature(rows, record_id, "background_clutter") >= threshold
        )
        assert entry["validation_half"]["true_positives"] == sum(
            1
            for record_id in half_b
            if missing_background(record_id) and _feature(rows, record_id, "background_clutter") >= threshold
        )
        assert entry["validation_half"]["false_positives_on_good_records"] == sum(
            1
            for record_id in half_b
            if labels[record_id]["quality_label"] == "good"
            and _feature(rows, record_id, "background_clutter") >= threshold
        )


def test_heldout_decision_stays_negative() -> None:
    report = json.loads((LANE / "framing-isolation-review.json").read_text(encoding="utf-8"))
    grid = report["part_2_isolation_rule_heldout_decision"]["grid"]
    viable = [
        entry
        for entry in grid
        if entry["derivation_half"]["false_positives_on_good_records"] <= 2
    ]
    assert not viable, "if a threshold now keeps false positives at or below 2, the negative decision must be revisited"
    assert report["part_2_isolation_rule_heldout_decision"]["decision"].startswith("Rejected")
    assert report["source_change"] == "none"


def test_manifest_pins_the_artifact() -> None:
    manifest = json.loads((LANE / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["artifacts"]
    for artifact in manifest["artifacts"]:
        path = REPO_ROOT / artifact["path"]
        assert path.is_file(), artifact["path"]
        assert hashlib.sha256(path.read_bytes()).hexdigest() == artifact["sha256"]
        assert path.stat().st_size == artifact["bytes"]
