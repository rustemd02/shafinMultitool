from __future__ import annotations

import json
import re
from pathlib import Path


def _load_goal_cases() -> list[dict]:
    path = Path(__file__).resolve().parents[1] / "goal_demo_golden_cases.jsonl"
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


def _load_known_action_ids() -> set[str]:
    contracts_path = (
        _repo_root()
        / "shafinMultitool"
        / "Multitool2Module"
        / "Models"
        / "CameraAnalysis"
        / "CameraAnalysisDomainContracts.swift"
    )
    source = contracts_path.read_text(encoding="utf-8")
    return _extract_enum_raw_values(source, "ActionTypeV1") | _extract_enum_raw_values(
        source,
        "SemanticActionType",
    )


def _extract_enum_raw_values(source: str, enum_name: str) -> set[str]:
    match = re.search(rf"enum {enum_name}:.*?\{{(?P<body>.*?)\n\}}", source, re.DOTALL)
    assert match, enum_name
    return set(re.findall(r'case\s+\w+\s*=\s*"([^"]+)"', match.group("body")))


def test_goal_demo_set_has_minimum_curated_coverage() -> None:
    cases = _load_goal_cases()

    assert len(cases) >= 25
    assert len({case["case_id"] for case in cases}) == len(cases)
    buckets = {tag for case in cases for tag in case["bucket_tags"]}
    required = {
        "lighting",
        "composition",
        "good_frame",
        "movie_frame",
        "group",
        "clutter",
        "background_light",
        "empty_frame",
    }
    assert required <= buckets


def test_goal_demo_cases_define_confidence_and_forbidden_tips() -> None:
    for case in _load_goal_cases():
        assert case["case_id"]
        assert case["mode"] in {"live", "pause", "both"}
        assert isinstance(case["scenario"], str) and case["scenario"].strip()
        assert 0.0 <= float(case["minimum_confidence"]) <= 1.0
        assert "forbidden_tips" in case and isinstance(case["forbidden_tips"], list)

        if case["mode"] in {"live", "both"} and case["expected_primary_action"] is not None:
            assert case["expected_live_tip"], case["case_id"]

        if case["mode"] in {"pause", "both"}:
            assert isinstance(case["expected_pause_tips"], list)
            if case["expected_primary_action"] is not None:
                assert case["expected_pause_tips"], case["case_id"]


def test_goal_demo_primary_actions_stay_inside_closed_catalogs() -> None:
    known_action_ids = _load_known_action_ids()
    for case in _load_goal_cases():
        action = case["expected_primary_action"]
        if action is not None:
            assert action in known_action_ids, case["case_id"]
