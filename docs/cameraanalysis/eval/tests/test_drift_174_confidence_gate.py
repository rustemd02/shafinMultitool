from __future__ import annotations

import hashlib
import json
from pathlib import Path

from semantic_output_schema import (
    _merge_record_outputs,
    score_semantic_candidate_outputs,
)
from semantic_label_adapter import (
    load_semantic_label_records,
    normalize_semantic_label_cases,
)


REPO_ROOT = Path(__file__).resolve().parents[4]
LANE = (
    Path(__file__).resolve().parents[1]
    / "camera-baseline-v0"
    / "drift-174-confidence-gate"
)
ROWS = (
    Path(__file__).resolve().parents[1]
    / "camera-baseline-v0"
    / "drift-174-technical-override"
    / "m4-001-fullruntime-174-drift-r1-technical-override.jsonl"
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


def _cases() -> list[dict]:
    return normalize_semantic_label_cases(load_semantic_label_records(LABELS))


def _pause_confidence(rows: dict[str, dict[str, dict]], record_id: str) -> float:
    return float(rows[record_id]["pause"]["confidence"])


def _merged(rows: dict[str, dict[str, dict]], record_id: str) -> set[str]:
    actions: set[str] = set()
    for row in rows[record_id].values():
        actions |= set(row.get("semantic_actions") or [])
    return actions


def _gated_report(
    rows: dict[str, dict[str, dict]], cases: list[dict], threshold: float
) -> dict:
    merged = []
    for record_id in sorted(rows):
        ordered = []
        for mode in ("live", "pause"):
            row = dict(rows[record_id][mode])
            if mode == "pause" and float(row["confidence"]) < threshold:
                row["semantic_actions"] = []
            ordered.append(row)
        merged.append(_merge_record_outputs(ordered))
    return score_semantic_candidate_outputs(cases, merged)


def test_separation_numbers_match_the_row_files() -> None:
    report = json.loads((LANE / "confidence-gate.json").read_text(encoding="utf-8"))
    rows = _rows()
    labels = {
        json.loads(line)["record_id"]: json.loads(line)
        for line in LABELS.read_text(encoding="utf-8").splitlines()
        if line.strip()
    }
    good = sorted(r for r in labels if labels[r]["quality_label"] == "good")
    corrected = [r for r in good if (_merged(rows, r) - {"keep_current_setup"})]
    kept = [r for r in good if _merged(rows, r) == {"keep_current_setup"}]
    silent = [r for r in good if not _merged(rows, r)]

    separation = report["separation"]
    assert separation["good_frames"] == len(good) == 81
    assert separation["corrected_good_frames"] == len(corrected) == 13
    assert separation["kept_good_frames"] == len(kept) == 65
    assert separation["silent_good_frames"] == sorted(silent)
    assert separation["corrected_good_confidences"] == {
        r: round(_pause_confidence(rows, r), 3) for r in sorted(corrected)
    }
    # The core separation finding: corrected good frames are NOT lower
    # confidence than kept good frames, so no threshold isolates them.
    assert separation["corrected_good_conf_range"][0] >= separation[
        "kept_good_conf_range"
    ][0]


def test_sweep_reproduces_through_the_canonical_scorer() -> None:
    report = json.loads((LANE / "confidence-gate.json").read_text(encoding="utf-8"))
    rows = _rows()
    cases = _cases()
    ungated = _gated_report(rows, cases, 0.0)
    assert f"{ungated['set_metrics']['pass_rate']:.6f}" == "0.534483"
    assert f"{ungated['set_metrics']['good_frame_preservation_rate']:.6f}" == "0.839506"

    for threshold, entry in report["sweep"].items():
        scored = _gated_report(rows, cases, float(threshold))
        assert f"{scored['set_metrics']['pass_rate']:.6f}" == f"{entry['pass_rate']:.6f}", threshold
        assert (
            f"{scored['set_metrics']['good_frame_preservation_rate']:.6f}"
            == f"{entry['preservation']:.6f}"
        ), threshold
        assert (
            f"{scored['set_metrics']['forbidden_action_violation_rate']:.6f}"
            == f"{entry['forbidden_rate']:.6f}"
        ), threshold

    # No threshold may beat the ungated pass count.
    best = max(
        round(entry["pass_rate"] * 174) for entry in report["sweep"].values()
    )
    assert best <= 92


def test_decision_stays_negative() -> None:
    report = json.loads((LANE / "confidence-gate.json").read_text(encoding="utf-8"))
    assert report["decision"]["applied"] is False
    assert "No threshold raises pass_rate" in report["decision"]["arithmetic"]
    assert report["source_change"] == "none"
    assert "does not separate" in report["separation"]["finding"]


def test_manifest_pins_the_artifact() -> None:
    manifest = json.loads((LANE / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["artifacts"]
    for artifact in manifest["artifacts"]:
        path = REPO_ROOT / artifact["path"]
        assert path.is_file(), artifact["path"]
        assert hashlib.sha256(path.read_bytes()).hexdigest() == artifact["sha256"]
        assert path.stat().st_size == artifact["bytes"]
