from __future__ import annotations

import hashlib
import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[4]
LANE = (
    Path(__file__).resolve().parents[1]
    / "camera-baseline-v0"
    / "drift-174-occlusion-routing"
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


def test_population_and_gain_numbers_match_the_row_files() -> None:
    report = json.loads((LANE / "occlusion-routing.json").read_text(encoding="utf-8"))
    rows = _rows()
    labels = _labels()
    occlusion = [
        record_id
        for record_id in labels
        if "avoid_occlusion" in (rows[record_id]["pause"].get("future_actions") or [])
    ]
    silent = [r for r in occlusion if not (rows[r]["pause"].get("semantic_actions") or [])]
    candidates = [r for r in occlusion if _feature(rows, r, "technical_dominant_count") > 0]
    wants_step_back = [
        r for r in candidates if "step_back" in (labels[r]["expected_semantic_actions"] or [])
    ]
    already = [r for r in candidates if "step_back" in _merged(rows, r)]
    forbidden = [r for r in candidates if "step_back" in (labels[r]["forbidden_actions"] or [])]

    population = report["population"]
    assert population["pause_rows_with_occlusion"] == len(occlusion)
    assert population["of_which_silent"] == len(silent)
    assert population["occlusion_plus_a_dominant_defect"] == len(candidates)
    assert population["candidate_rows"] == sorted(candidates)
    assert population["label_expects_step_back"] == sorted(wants_step_back)
    assert population["already_emits_step_back"] == sorted(already)
    assert population["step_back_is_forbidden"] == sorted(forbidden)
    assert population["net_gain_rows"] == sorted(set(wants_step_back) - set(already))
    assert population["candidate_good_labelled"] == []


def test_candidate_rule_halves_match_the_row_files() -> None:
    report = json.loads((LANE / "occlusion-routing.json").read_text(encoding="utf-8"))
    rows = _rows()
    labels = _labels()
    ids = sorted(labels)
    half_a = {r for i, r in enumerate(ids) if i % 2 == 0}
    half_b = {r for i, r in enumerate(ids) if i % 2 == 1}
    occlusion = [
        r for r in labels if "avoid_occlusion" in (rows[r]["pause"].get("future_actions") or [])
    ]

    def wants_framing(r: str) -> bool:
        return bool({"step_back", "step_closer"} & set(labels[r]["expected_semantic_actions"] or []))

    def has_framing(r: str) -> bool:
        return bool({"step_back", "step_closer"} & _merged(rows, r))

    rules = {entry["rule"]: entry for entry in report["candidate_rules"]}
    blanket = rules["occlusion detected -> emit semantic step_back"]
    gain = [r for r in occlusion if wants_framing(r) and not has_framing(r)]
    risk = [
        r
        for r in occlusion
        if labels[r]["quality_label"] == "good" and not (_merged(rows, r) - {"keep_current_setup"})
    ]
    assert blanket["selected"] == len(occlusion)
    assert blanket["gain_derivation"] == sum(1 for r in gain if r in half_a)
    assert blanket["risk_derivation"] == sum(1 for r in risk if r in half_a)
    assert blanket["gain_validation"] == sum(1 for r in gain if r in half_b)
    assert blanket["risk_validation"] == sum(1 for r in risk if r in half_b)

    gated = rules["occlusion detected AND a dominant technical defect present -> emit semantic step_back"]
    candidates = [r for r in occlusion if _feature(rows, r, "technical_dominant_count") > 0]
    gated_gain = [r for r in candidates if wants_framing(r) and not has_framing(r)]
    gated_risk = [
        r
        for r in candidates
        if labels[r]["quality_label"] == "good" and not (_merged(rows, r) - {"keep_current_setup"})
    ]
    assert gated["selected"] == len(candidates)
    assert gated["gain_derivation"] == sum(1 for r in gated_gain if r in half_a)
    assert gated["risk_derivation"] == sum(1 for r in gated_risk if r in half_a)
    assert gated["gain_validation"] == sum(1 for r in gated_gain if r in half_b)
    assert gated["risk_validation"] == sum(1 for r in gated_risk if r in half_b)


def test_decision_stays_negative() -> None:
    report = json.loads((LANE / "occlusion-routing.json").read_text(encoding="utf-8"))
    assert report["decision"]["applied"] is False
    assert "net-negative" in report["decision"]["arithmetic"]
    assert report["source_change"] == "none"
    assert "returns [] for every other type" in report["mechanism"]["finding"]


def test_manifest_pins_the_artifact() -> None:
    manifest = json.loads((LANE / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["artifacts"]
    for artifact in manifest["artifacts"]:
        path = REPO_ROOT / artifact["path"]
        assert path.is_file(), artifact["path"]
        assert hashlib.sha256(path.read_bytes()).hexdigest() == artifact["sha256"]
        assert path.stat().st_size == artifact["bytes"]
