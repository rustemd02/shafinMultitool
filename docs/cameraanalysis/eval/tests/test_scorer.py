from __future__ import annotations

import json
from pathlib import Path

from adapters import LegacyBaselineRunner
from scorer import score_case, validate_sequence_contract


def _load_example_cases() -> list[dict]:
    path = Path(__file__).resolve().parents[1] / "example_golden_cases.jsonl"
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def test_legacy_baseline_materializes_proxy_trace() -> None:
    cases = _load_example_cases()
    case = next(item for item in cases if item["eval_case_id"] == "pause-edge-backlight-001")
    output = LegacyBaselineRunner().run_case(case)
    trace_items = output["explainability_trace"]["items"]
    stages = {item["stage"] for item in trace_items}

    assert {"observation", "interpretation", "recommendation"} <= stages
    assert output["critique_report"]["issues"], "baseline should project at least one proxy issue"


def test_fix_type_coverage_not_applicable_for_good_frame_no_change() -> None:
    cases = _load_example_cases()
    case = next(item for item in cases if item["eval_case_id"] == "pause-good-clean-portrait-001")
    output = {
        "critique_report": {
            "verdict": "good",
            "issues": [],
            "strengths": [{"id": "s1", "type": "good_subject_isolation"}],
            "summary": {
                "id": "sum1",
                "shortVerdict": "Good frame",
                "whyGood": "Subject is clear and focus is stable.",
                "whyProblematic": None,
            },
            "fallbackUsed": False,
        },
        "recommendation_plan": {
            "mode": "pause",
            "primaryAction": {
                "id": "a1",
                "actionType": "leave_frame_as_is",
                "linkedIssueIds": [],
            },
            "secondaryActions": [],
            "noChangeRationale": "No changes needed.",
        },
        "explainability_trace": {"items": []},
        "live_hint_projection": {"hintState": "confirm_good_frame", "primaryAction": "leave_frame_as_is"},
    }

    metrics = score_case(case, output)["metrics"]
    assert metrics["fix_type_coverage_rate"] is None


def test_sequence_jitter_ignores_exempt_transitions() -> None:
    case = {
        "eval_case_id": "seq-jitter-test",
        "eval_set": "live_sequence",
        "case_kind": "live_sequence",
        "bucket_tags": ["live_motion_suppression"],
        "sequenceMeta": {
            "stabilityAnchorFrame": 2,
            "stablePrimaryAction": "move_frame_left",
            "maxFramesToStable": 2,
        },
        "sequence": [
            {
                "frameOrdinal": 1,
                "expectedHintState": "visible_action",
                "jitterExempt": False,
                "countsTowardStability": False,
            },
            {
                "frameOrdinal": 2,
                "expectedHintState": "visible_action",
                "jitterExempt": True,
                "countsTowardStability": True,
            },
            {
                "frameOrdinal": 3,
                "expectedHintState": "visible_action",
                "jitterExempt": False,
                "countsTowardStability": True,
            },
        ],
    }
    output = {
        "frame_outputs": [
            {"frameOrdinal": 1, "hintState": "visible_action", "primaryAction": "move_frame_right"},
            {"frameOrdinal": 2, "hintState": "visible_action", "primaryAction": "move_frame_left"},
            {"frameOrdinal": 3, "hintState": "visible_action", "primaryAction": "move_frame_left"},
        ]
    }

    metrics = score_case(case, output)["metrics"]
    assert metrics["hint_jitter_rate"] == 0.0
    assert metrics["frames_to_stable_correct_hint"] == 0.0


def test_validate_sequence_contract_requires_required_metadata() -> None:
    bad_case = {
        "eval_case_id": "bad-seq",
        "case_kind": "live_sequence",
        "sequenceMeta": {"stabilityAnchorFrame": 1, "stablePrimaryAction": "move_frame_left"},
        "sequence": [{"frameOrdinal": 1, "expectedHintState": "visible_action", "jitterExempt": False}],
    }
    try:
        validate_sequence_contract([bad_case])
    except ValueError as exc:
        assert "contract-invalid" in str(exc)
    else:
        raise AssertionError("validate_sequence_contract must fail for missing required sequence metadata")
