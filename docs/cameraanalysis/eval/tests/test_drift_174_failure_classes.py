from __future__ import annotations

import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[4]
LANE = (
    Path(__file__).resolve().parents[1]
    / "camera-baseline-v0"
    / "drift-174-failure-classes"
)
INSTRUMENTED_ROWS = (
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
    for line in INSTRUMENTED_ROWS.read_text(encoding="utf-8").splitlines():
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


def _merged_actions(rows: dict[str, dict[str, dict]], record_id: str) -> set[str]:
    actions: set[str] = set()
    for row in rows[record_id].values():
        actions |= set(row.get("semantic_actions") or [])
    return actions


def test_class_counts_match_the_row_files() -> None:
    report = json.loads((LANE / "failure-class-decomposition.json").read_text(encoding="utf-8"))
    rows = _rows()
    labels = _labels()
    classes = report["classes"]

    keep_missed = [
        record_id
        for record_id, label in labels.items()
        if "keep_current_setup" in (label["expected_semantic_actions"] or [])
        and "keep_current_setup" not in _merged_actions(rows, record_id)
    ]
    background_missed = [
        record_id
        for record_id, label in labels.items()
        if {"simplify_background", "remove_distracting_object"}
        & set(label["expected_semantic_actions"] or [])
        and not {"simplify_background", "remove_distracting_object"}
        & _merged_actions(rows, record_id)
    ]
    assert classes["keep_expected_but_corrected"]["records"] == len(keep_missed)
    assert sorted(keep_missed) == sorted(classes["keep_expected_but_corrected"]["record_ids"])
    assert classes["background_correction_expected_but_absent"]["records"] == len(background_missed)
    assert sorted(background_missed) == sorted(
        classes["background_correction_expected_but_absent"]["record_ids"]
    )


def test_rejected_gate_populations_match_the_row_files() -> None:
    report = json.loads((LANE / "failure-class-decomposition.json").read_text(encoding="utf-8"))
    gate = report["candidate_gate_rejected"]
    rows = _rows()
    labels = _labels()

    def verdict(record_id: str) -> str | None:
        return rows[record_id]["pause"].get("debug_semantic_labels", {}).get("verdict")

    def dominant(record_id: str) -> float:
        return (
            rows[record_id]["pause"]
            .get("debug_numeric_features", {})
            .get("technical_dominant_count")
            or 0
        )

    gain = [
        record_id
        for record_id, label in labels.items()
        if verdict(record_id) == "good"
        and label["quality_label"] == "good"
        and _merged_actions(rows, record_id) - {"keep_current_setup"}
    ]
    loss = [
        record_id
        for record_id, label in labels.items()
        if verdict(record_id) == "good"
        and label["quality_label"] != "good"
        and _merged_actions(rows, record_id) - {"keep_current_setup"}
    ]
    assert gate["gain_records"] == len(gain)
    assert sorted(gain) == sorted(gate["gain_record_ids"])
    assert gate["loss_records"] == len(loss)
    assert gate["loss_records_on_the_dominant_technical_card_path"] == sum(
        1 for record_id in loss if dominant(record_id) > 0
    )
    assert gate["gain_records"] < gate["loss_records"], "the gate must be net-negative by the record"


def test_action_coverage_numbers_match_the_row_files() -> None:
    report = json.loads((LANE / "failure-class-decomposition.json").read_text(encoding="utf-8"))
    coverage = report["action_coverage"]
    rows = _rows()
    labels = _labels()
    emitted: dict[str, int] = {}
    for record_id in rows:
        for row in rows[record_id].values():
            for action in row.get("semantic_actions") or []:
                emitted[action] = emitted.get(action, 0) + 1
    expected: dict[str, int] = {}
    for label in labels.values():
        for action in label["expected_semantic_actions"] or []:
            expected[action] = expected.get(action, 0) + 1
    for action in (
        "step_closer",
        "step_back",
        "simplify_background",
        "remove_distracting_object",
        "add_front_fill_light",
        "keep_current_setup",
    ):
        assert coverage[action]["emitted"] == emitted.get(action, 0), action
        assert coverage[action]["expected"] == expected.get(action, 0), action
    assert coverage["step_closer"]["expected"] == 9
    assert coverage["remove_distracting_object"]["expected"] == 13


def test_report_records_the_suite_state_and_scope() -> None:
    report = json.loads((LANE / "failure-class-decomposition.json").read_text(encoding="utf-8"))
    assert report["suite_state"]["phase_b"] == "177 / 142 passed / 35 failed"
    assert report["candidate_gate_rejected"]["verdict"].startswith("Rejected:")
    assert "coverage- and signal-limited" in report["conclusion"]
