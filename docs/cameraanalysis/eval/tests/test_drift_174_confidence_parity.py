from __future__ import annotations

import hashlib
import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[4]
LANE = (
    Path(__file__).resolve().parents[1]
    / "camera-baseline-v0"
    / "drift-174-confidence-parity"
)
ROWS = LANE / "m4-001-fullruntime-174-drift-r1-base-confidence.jsonl"
PREVIOUS_ROWS = (
    Path(__file__).resolve().parents[1]
    / "camera-baseline-v0"
    / "drift-174-probe-instrumentation"
    / "m4-001-fullruntime-174-drift-r1-probe-instrumented.jsonl"
)
LABELS = (
    REPO_ROOT
    / "shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1/camera_full_labels.jsonl"
)
KIND_WEIGHT = {"face": 1.0, "person": 0.92, "group": 0.90, "object": 0.88, "unknown": 0.70}


def _rows(path: Path) -> dict[str, dict[str, dict]]:
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


def _feature(rows: dict[str, dict[str, dict]], record_id: str, key: str) -> float:
    return rows[record_id]["pause"]["debug_numeric_features"].get(key) or 0.0


def _label(rows: dict[str, dict[str, dict]], record_id: str, key: str) -> str:
    return rows[record_id]["pause"]["debug_semantic_labels"].get(key) or ""


def _band(target: str, confidence: float) -> bool:
    if target == "high":
        return confidence >= 0.75
    if target == "medium":
        return 0.45 <= confidence < 0.75
    return confidence < 0.45


def _merged_confidence(rows: dict[str, dict[str, dict]], record_id: str) -> float:
    shown = [m for m in rows[record_id] if rows[record_id][m].get("shown")]
    with_actions = [m for m in shown if rows[record_id][m].get("semantic_actions")]
    pool = with_actions or shown
    values = [float(rows[record_id][m].get("confidence", 0)) for m in pool]
    return max(values) if values else 0.0


def _weighted_confidence(base: float, kind: str, area: float) -> float:
    region_weight = 0.85 if area == 0 else (0.75 if area < 0.02 else 1.0)
    reliability = 0.50 if kind == "object" else max(base, 0.25)
    return min(1.0, base * reliability * KIND_WEIGHT.get(kind, 0.70) * region_weight)


def test_instrumentation_adds_only_the_base_confidence_key() -> None:
    current = _rows(ROWS)
    previous = _rows(PREVIOUS_ROWS)
    assert set(current) == set(previous)
    assert sum(len(modes) for modes in current.values()) == 348
    compared = 0
    for record_id, modes in previous.items():
        for mode, before_row in modes.items():
            after = dict(current[record_id][mode])
            before = dict(before_row)
            before_features = dict(before.get("debug_numeric_features", {}))
            after_features = dict(after.get("debug_numeric_features", {}))
            assert set(after_features) - set(before_features) == {
                "primary_subject_base_confidence"
            }, (record_id, mode)
            before_features.pop("primary_subject_base_confidence", None)
            after_features.pop("primary_subject_base_confidence", None)
            before["debug_numeric_features"] = before_features
            after["debug_numeric_features"] = after_features
            assert before == after, (record_id, mode)
            compared += 1
    assert compared == 348


def test_parity_measurement_matches_the_row_files() -> None:
    report = json.loads((LANE / "confidence-parity.json").read_text(encoding="utf-8"))
    rows = _rows(ROWS)
    labels = _labels()
    keep = lost = gained = 0
    mismatches: dict[str, int] = {
        "target_high_actual_lower": 0,
        "target_medium_actual_higher": 0,
        "target_medium_actual_lower": 0,
        "target_low_actual_higher": 0,
    }
    boundary = {"exactly_0.74": 0, "exactly_0.75": 0}
    for record_id, label in labels.items():
        target = label["confidence_target"]
        current = _merged_confidence(rows, record_id)
        predicted = _weighted_confidence(
            _feature(rows, record_id, "primary_subject_base_confidence"),
            _label(rows, record_id, "primary_subject_kind"),
            _feature(rows, record_id, "subject_area_ratio"),
        )
        current_ok = _band(target, current)
        predicted_ok = _band(target, predicted)
        if current_ok and predicted_ok:
            keep += 1
        elif current_ok and not predicted_ok:
            lost += 1
        elif predicted_ok and not current_ok:
            gained += 1
        if not current_ok:
            if target == "high":
                mismatches["target_high_actual_lower"] += 1
            elif target == "medium":
                mismatches[
                    "target_medium_actual_higher" if current >= 0.75 else "target_medium_actual_lower"
                ] += 1
            else:
                mismatches["target_low_actual_higher"] += 1
            if abs(current - 0.74) < 1e-9:
                boundary["exactly_0.74"] += 1
            if abs(current - 0.75) < 1e-9:
                boundary["exactly_0.75"] += 1

    measurement = report["measurement"]
    assert measurement["band_matches_current"] == keep + lost
    assert measurement["band_matches_if_published_were_historically_weighted"] == keep + gained
    assert measurement["gained"] == gained
    assert measurement["lost"] == lost
    assert report["band_mismatch_decomposition"] == {
        key: value for key, value in mismatches.items() if value
    }
    assert report["boundary_clusters"] == boundary


def test_decision_stays_negative_and_records_the_correction() -> None:
    report = json.loads((LANE / "confidence-parity.json").read_text(encoding="utf-8"))
    assert report["decision"]["applied"] is False
    assert "Rejected" in report["decision"]["verdict"]
    assert report["measurement"]["net"] < -100
    assert "raw publication matches the label bands far better" in report["decision"]["correction"]
    assert report["control_run"]["phase_b"] == "177 / 142 passed / 35 failed"


def test_manifest_pins_the_artifacts() -> None:
    manifest = json.loads((LANE / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["artifacts"]
    for artifact in manifest["artifacts"]:
        path = REPO_ROOT / artifact["path"]
        assert path.is_file(), artifact["path"]
        assert hashlib.sha256(path.read_bytes()).hexdigest() == artifact["sha256"]
        assert path.stat().st_size == artifact["bytes"]
