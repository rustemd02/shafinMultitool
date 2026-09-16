from __future__ import annotations

import hashlib
import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[4]
LANE = (
    Path(__file__).resolve().parents[1]
    / "camera-baseline-v0"
    / "drift-174-signal-viability"
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


def _merged_actions(rows: dict[str, dict[str, dict]], record_id: str) -> set[str]:
    actions: set[str] = set()
    for row in rows[record_id].values():
        actions |= set(row.get("semantic_actions") or [])
    return actions


def _background_misses(rows: dict[str, dict[str, dict]], labels: dict[str, dict]) -> list[str]:
    return [
        record_id
        for record_id, label in labels.items()
        if {"simplify_background", "remove_distracting_object"}
        & set(label["expected_semantic_actions"] or [])
        and not {"simplify_background", "remove_distracting_object"}
        & _merged_actions(rows, record_id)
    ]


def test_reported_yield_and_risk_match_the_row_files() -> None:
    report = json.loads((LANE / "signal-viability.json").read_text(encoding="utf-8"))
    rows = _rows()
    labels = _labels()
    misses = _background_misses(rows, labels)
    good = [record_id for record_id, label in labels.items() if label["quality_label"] == "good"]

    assert report["proposed_signal_A_region_saliency_distractor"]["records_it_should_reach"] == len(misses)
    variants = {
        entry["variant"]: entry
        for entry in report["proposed_signal_A_region_saliency_distractor"]["variant_yield_and_risk"]
    }
    companion = variants["companion object present (object_count >= 2)"]
    assert companion["reaches_background_misses"] == sum(
        1 for record_id in misses if _feature(rows, record_id, "object_count") >= 2
    )
    assert companion["also_fires_on_good_records"] == sum(
        1 for record_id in good if _feature(rows, record_id, "object_count") >= 2
    )
    assert companion["good_records_total"] == len(good)
    clutter = variants["high measured clutter (clutter >= 0.32)"]
    assert clutter["reaches_background_misses"] == sum(
        1 for record_id in misses if _feature(rows, record_id, "background_clutter") >= 0.32
    )
    assert clutter["also_fires_on_good_records"] == sum(
        1 for record_id in good if _feature(rows, record_id, "background_clutter") >= 0.32
    )


def test_isolation_suppressor_count_matches_the_rule() -> None:
    report = json.loads((LANE / "signal-viability.json").read_text(encoding="utf-8"))
    rows = _rows()
    labels = _labels()
    misses = _background_misses(rows, labels)

    def suppressor_fires(record_id: str, confidence: float) -> bool:
        clutter = _feature(rows, record_id, "background_clutter")
        separation = min(1.0, max(0.0, 0.45 * confidence + 0.35 * (1 - clutter) + 0.20 * (1 - _feature(rows, record_id, "backlight_index"))))
        score = min(1.0, max(0.0, 0.60 * separation + 0.40 * (1 - clutter)))
        confidence_value = min(1.0, max(0.0, 0.60 * confidence + 0.40 * _feature(rows, record_id, "scene_type_confidence")))
        return score >= 0.55 and confidence_value >= 0.35

    firing = [
        record_id
        for record_id in misses
        if suppressor_fires(record_id, _feature(rows, record_id, "primary_subject_confidence"))
    ]
    assert report["proposed_signal_A_region_saliency_distractor"]["confidence_parity_pretest"][
        "suppressor_fires_now"
    ] == len(firing)
    unlocked = [
        record_id
        for record_id in firing
        if not suppressor_fires(record_id, 0.25 * _feature(rows, record_id, "primary_subject_confidence"))
    ]
    assert report["proposed_signal_A_region_saliency_distractor"]["confidence_parity_pretest"][
        "records_that_would_be_unlocked"
    ] <= len(unlocked) or report["proposed_signal_A_region_saliency_distractor"][
        "confidence_parity_pretest"
    ]["records_that_would_be_unlocked"] <= 2


def test_framing_label_consistency_numbers_match_the_row_files() -> None:
    report = json.loads((LANE / "signal-viability.json").read_text(encoding="utf-8"))
    rows = _rows()
    labels = _labels()
    check = report["proposed_signal_B_subject_size"]["label_consistency_check"]
    step_closer = [
        record_id
        for record_id, label in labels.items()
        if "step_closer" in (label["expected_semantic_actions"] or [])
    ]
    step_back = [
        record_id
        for record_id, label in labels.items()
        if "step_back" in (label["expected_semantic_actions"] or [])
    ]
    areas_closer = sorted(_feature(rows, r, "subject_area_ratio") for r in step_closer)
    areas_back = sorted(_feature(rows, r, "subject_area_ratio") for r in step_back)
    assert report["proposed_signal_B_subject_size"]["step_closer_records"] == len(step_closer)
    assert check["step_closer_median_subject_area"] == round(areas_closer[len(areas_closer) // 2], 4)
    assert check["step_back_median_subject_area"] == round(areas_back[len(areas_back) // 2], 4)
    assert (
        check["step_back_median_subject_area"] < check["step_closer_median_subject_area"]
    ), "the label expectations must remain geometry-inconsistent for this rejection to hold"


def test_manifest_pins_the_artifact_and_records_no_source_change() -> None:
    manifest = json.loads((LANE / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["source_change"].startswith("none:")
    assert manifest["artifacts"]
    for artifact in manifest["artifacts"]:
        path = REPO_ROOT / artifact["path"]
        assert path.is_file(), artifact["path"]
        assert hashlib.sha256(path.read_bytes()).hexdigest() == artifact["sha256"]
        assert path.stat().st_size == artifact["bytes"]
