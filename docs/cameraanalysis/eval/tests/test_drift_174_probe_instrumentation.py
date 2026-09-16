from __future__ import annotations

import hashlib
import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[4]
LANE = Path(__file__).resolve().parents[1] / "camera-baseline-v0" / "drift-174-probe-instrumentation"
INSTRUMENTED_ROWS = LANE / "m4-001-fullruntime-174-drift-r1-probe-instrumented.jsonl"
OVERRIDE_ROWS = (
    Path(__file__).resolve().parents[1]
    / "camera-baseline-v0"
    / "drift-174-technical-override"
    / "m4-001-fullruntime-174-drift-r1-technical-override.jsonl"
)
HISTORICAL_ROWS = (
    REPO_ROOT
    / "docs/cameraanalysis/eval/out_semantic_real_runtime_v2_regen_bad_v1/candidate_outputs_raw.jsonl"
)
LABELS = (
    REPO_ROOT
    / "shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1/camera_full_labels.jsonl"
)
NEW_KEYS = {
    "technical_issue_count",
    "technical_dominant_count",
    "technical_max_severity",
    "technical_max_confidence",
}


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _rows(path: Path) -> dict[tuple[str, str], dict]:
    out: dict[tuple[str, str], dict] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        row = json.loads(line)
        out[(row["record_id"], row.get("mode"))] = row
    return out


def _labels() -> dict[str, dict]:
    return {
        json.loads(line)["record_id"]: json.loads(line)
        for line in LABELS.read_text(encoding="utf-8").splitlines()
        if line.strip()
    }


def _feature(rows: dict[tuple[str, str], dict], record_id: str, key: str) -> float:
    return rows[(record_id, "pause")]["debug_numeric_features"].get(key) or 0.0


def test_instrumentation_is_behaviour_neutral() -> None:
    instrumented = _rows(INSTRUMENTED_ROWS)
    override = _rows(OVERRIDE_ROWS)
    assert set(instrumented) == set(override)
    assert len(instrumented) == 348
    for key, before in override.items():
        after = dict(instrumented[key])
        before = dict(before)
        before_features = dict(before.get("debug_numeric_features", {}))
        after_features = dict(after.get("debug_numeric_features", {}))
        added = set(after_features) - set(before_features)
        assert added <= NEW_KEYS, (key, added)
        for name in NEW_KEYS:
            before_features.pop(name, None)
            after_features.pop(name, None)
        before["debug_numeric_features"] = before_features
        after["debug_numeric_features"] = after_features
        assert before == after, key


def test_probe_dominance_numbers_match_instrumented_rows() -> None:
    analysis = json.loads((LANE / "probe-dominance-analysis.json").read_text(encoding="utf-8"))
    rows = _rows(INSTRUMENTED_ROWS)
    labels = _labels()
    for quality, expected in analysis["per_class"].items():
        ids = [record_id for record_id in labels if labels[record_id]["quality_label"] == quality]
        assert expected["records"] == len(ids)
        assert expected["records_with_any_probe_issue"] == sum(
            1 for record_id in ids if _feature(rows, record_id, "technical_issue_count") > 0
        )
        assert expected["records_with_dominant_probe_issue"] == sum(
            1 for record_id in ids if _feature(rows, record_id, "technical_dominant_count") > 0
        )
    for entry in analysis["bar_lowering_cost"]:
        for quality in ("good", "mixed", "bad"):
            ids = [record_id for record_id in labels if labels[record_id]["quality_label"] == quality]
            expected = sum(
                1
                for record_id in ids
                if max(
                    _feature(rows, record_id, "technical_max_severity"),
                    _feature(rows, record_id, "technical_max_confidence"),
                )
                >= entry["bar"]
            )
            assert entry[quality] == expected, (entry["bar"], quality)


def test_trigger_validation_is_documented() -> None:
    analysis = json.loads((LANE / "probe-dominance-analysis.json").read_text(encoding="utf-8"))
    good = analysis["per_class"]["good"]
    bad = analysis["per_class"]["bad"]
    assert good["records_with_dominant_probe_issue"] == 9
    assert bad["records_with_dominant_probe_issue"] == 44
    assert good["records_with_any_probe_issue"] == 63
    assert bad["records_with_any_probe_issue"] == 69
    assert "9/81 good versus 44/79 bad" in analysis["trigger_validation"]


def test_parity_analysis_matches_row_files() -> None:
    parity = json.loads((LANE / "parity-analysis.json").read_text(encoding="utf-8"))
    instrumented = _rows(INSTRUMENTED_ROWS)
    historical = _rows(HISTORICAL_ROWS)
    labels = _labels()
    assert parity["object_count"]["records_with_different_count"] == sum(
        1
        for record_id in labels
        if _feature(historical, record_id, "object_count")
        != _feature(instrumented, record_id, "object_count")
    )
    assert parity["person_count_differences"] == 0
    assert parity["aesthetic_score_identical_records"] == sum(
        1
        for record_id in labels
        if _feature(historical, record_id, "aesthetic_score")
        == _feature(instrumented, record_id, "aesthetic_score")
    )
    assert "connected-component" in parity["cause"]


def test_manifest_artifacts_are_pinned() -> None:
    manifest = json.loads((LANE / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["artifacts"]
    for artifact in manifest["artifacts"]:
        path = REPO_ROOT / artifact["path"]
        assert path.is_file(), artifact["path"]
        assert _sha256(path) == artifact["sha256"], artifact["path"]
        assert path.stat().st_size == artifact["bytes"], artifact["path"]
