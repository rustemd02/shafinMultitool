#!/usr/bin/env python3
"""Validate the closed DATA-001 release-label contract and its fixtures.

JSON Schema owns structure and scalar ranges.  This small companion validator
owns cross-record facts that Draft 2020-12 cannot express (issue-head
coverage, references, rectangle containment, and before/after evidence).
"""

from __future__ import annotations

import argparse
import copy
import json
import math
import sys
from collections import Counter
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator


HERE = Path(__file__).resolve().parent
DEFAULT_SCHEMA = HERE / "camera_release_label_v1.schema.json"
DEFAULT_VALID = HERE / "fixtures" / "camera_release_label_v1.valid.json"
DEFAULT_INVALID = HERE / "fixtures" / "camera_release_label_v1.invalid.json"

RELEASE_ISSUE_IDS = frozenset(
    {
        "subject_too_close_to_edge",
        "subject_not_prominent_enough",
        "background_competes_with_subject",
        "insufficient_look_space",
        "backlight_hides_subject",
        "scene_has_no_clear_focus",
        "frame_visually_overloaded",
        "horizon_distracts",
        "motion_blur",
        "defocus",
        "overexposure",
        "underexposure",
        "noise",
        "occlusion",
        "lens_smudge",
    }
)

IDENTITY_MISMATCH_REASONS = frozenset(
    {
        "frame_identity_missing",
        "subject_identity_mismatch",
        "scene_mismatch",
        "geometry_mismatch",
        "target_missing",
    }
)

TARGET_ACTIONS = frozenset(
    {
        "rotate_subject_toward_light",
        "move_subject_left",
        "move_subject_right",
        "move_subject_away_from_background",
        "move_object_left",
        "move_object_right",
        "move_object_forward",
        "move_object_back",
        "remove_distracting_object",
        "reposition_prop_for_balance",
    }
)


def load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def schema_errors(validator: Draft202012Validator, record: Any) -> list[str]:
    errors = sorted(validator.iter_errors(record), key=lambda error: list(error.path))
    return [f"schema {'.'.join(map(str, error.path)) or '<root>'}: {error.message}" for error in errors]


def semantic_errors(record: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    issues = record.get("issues")
    if not isinstance(issues, list):
        return ["issues must be an array"]

    issue_ids = [item.get("issue_id") for item in issues if isinstance(item, dict)]
    counts = Counter(issue_ids)
    duplicate_ids = sorted(issue_id for issue_id, count in counts.items() if count > 1)
    if duplicate_ids:
        errors.append(f"issues must contain each issue head once; duplicate IDs: {duplicate_ids}")
    missing_ids = sorted(RELEASE_ISSUE_IDS.difference(counts))
    unknown_ids = sorted(set(counts).difference(RELEASE_ISSUE_IDS))
    if missing_ids:
        errors.append(f"issues missing release issue heads: {missing_ids}")
    if unknown_ids:
        errors.append(f"issues contain unknown release issue heads: {unknown_ids}")
    if len(issues) != len(RELEASE_ISSUE_IDS):
        errors.append(f"issues must contain exactly {len(RELEASE_ISSUE_IDS)} issue heads")

    issue_by_id = {
        item.get("issue_id"): item
        for item in issues
        if isinstance(item, dict) and isinstance(item.get("issue_id"), str)
    }
    present_issue_ids = {
        issue_id
        for issue_id, item in issue_by_id.items()
        if item.get("status") == "present"
    }

    action = record.get("action")
    if isinstance(action, dict):
        action_id = action.get("action_id")
        references = action.get("issue_ids")
        if action_id == "keep_current_setup":
            if references:
                errors.append("keep_current_setup cannot reference issue IDs")
        elif isinstance(references, list):
            for issue_id in references:
                if issue_id not in issue_by_id:
                    errors.append(f"action references absent issue head: {issue_id}")
                elif issue_id not in present_issue_ids:
                    errors.append(f"action issue reference is not present: {issue_id}")

    def check_region(region: Any, path: str) -> None:
        if region is None:
            return
        if not isinstance(region, dict):
            return
        values = [region.get(name) for name in ("x", "y", "width", "height")]
        if not all(isinstance(value, (int, float)) and not isinstance(value, bool) for value in values):
            return
        if not all(math.isfinite(float(value)) for value in values):
            errors.append(f"{path} coordinates must be finite")
            return
        if float(region["x"]) + float(region["width"]) > 1:
            errors.append(f"{path} overflows the right unit-square boundary")
        if float(region["y"]) + float(region["height"]) > 1:
            errors.append(f"{path} overflows the bottom unit-square boundary")

    target = record.get("target")
    if isinstance(target, dict):
        check_region(target.get("region"), "target.region")
    for index, issue in enumerate(issues):
        if isinstance(issue, dict):
            check_region(issue.get("region"), f"issues[{index}].region")

    before_after = record.get("before_after")
    if not isinstance(before_after, dict):
        return errors
    status = before_after.get("status")
    before_frame = before_after.get("before_frame_id")
    after_frame = before_after.get("after_frame_id")
    if before_frame is not None and after_frame is not None and before_frame == after_frame:
        errors.append("before_after before_frame_id and after_frame_id must differ")

    if status == "comparable":
        target_ref = before_after.get("target_ref")
        target_entity = target.get("entity_ref") if isinstance(target, dict) else None
        if target_ref != target_entity:
            errors.append("comparable before_after.target_ref must match target.entity_ref")
        metric = before_after.get("metric")
        if isinstance(metric, dict):
            outcome = before_after.get("outcome")
            delta = metric.get("delta")
            deadband = metric.get("deadband")
            if outcome == "improved" and isinstance(delta, (int, float)) and isinstance(deadband, (int, float)):
                if delta <= deadband:
                    errors.append("improved requires delta greater than deadband")
            if outcome == "fixed":
                if metric.get("goal_satisfied") is not True:
                    errors.append("fixed requires goal_satisfied=true")
                predicate = metric.get("objective_predicate")
                if not isinstance(predicate, str) or not predicate.strip():
                    errors.append("fixed requires a non-empty objective_predicate")
            elif metric.get("goal_satisfied") is True:
                errors.append("goal_satisfied=true requires outcome=fixed")
    elif status == "incomparable":
        reason = before_after.get("reason")
        same_target = before_after.get("same_target")
        if reason in IDENTITY_MISMATCH_REASONS and same_target is True:
            errors.append(f"incomparable reason={reason} cannot claim same_target=true")
        if same_target is True:
            target_ref = before_after.get("target_ref")
            target_entity = target.get("entity_ref") if isinstance(target, dict) else None
            if target_ref != target_entity:
                errors.append("same-target incomparable evidence must name target.entity_ref")

    return errors


def validate_record(validator: Draft202012Validator, record: Any) -> list[str]:
    if not isinstance(record, dict):
        return ["record must be an object"]
    return schema_errors(validator, record) + semantic_errors(record)


def apply_case(base_record: dict[str, Any], case: dict[str, Any]) -> dict[str, Any]:
    """Apply the fixture's top-level patch plus optional JSON-pointer-like edits."""
    candidate = copy.deepcopy(base_record)
    candidate.update(copy.deepcopy(case.get("patch", {})))
    for operation in case.get("operations", []):
        path = operation.get("path", [])
        if not path:
            raise ValueError("fixture operation path must not be empty")
        cursor: Any = candidate
        for component in path[:-1]:
            cursor = cursor[component]
        cursor[path[-1]] = copy.deepcopy(operation.get("value"))
    return candidate


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--schema", type=Path, default=DEFAULT_SCHEMA)
    parser.add_argument("--valid", type=Path, default=DEFAULT_VALID)
    parser.add_argument("--invalid", type=Path, default=DEFAULT_INVALID)
    args = parser.parse_args()

    schema = load_json(args.schema)
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema)
    print(f"schema: PASS ({args.schema})")

    valid_record = load_json(args.valid)
    valid_errors = validate_record(validator, valid_record)
    if valid_errors:
        print(f"positive {args.valid.name}: FAIL")
        for error in valid_errors:
            print(f"  - {error}")
        return 1
    print(f"positive {args.valid.name}: PASS")

    negative_fixture = load_json(args.invalid)
    base_record = copy.deepcopy(valid_record)
    rejected = 0
    accepted_boundary = 0
    cases = negative_fixture.get("cases", [])
    for case in cases:
        name = case.get("name", "<unnamed>")
        candidate = apply_case(base_record, case)
        errors = validate_record(validator, candidate)
        expected_result = case.get("expected_result", "reject")
        if expected_result == "accept":
            if errors:
                print(f"boundary {name}: FAIL (expected acceptance)")
                for error in errors:
                    print(f"  - {error}")
                return 1
            accepted_boundary += 1
            print(f"boundary {name}: PASS (accepted)")
        elif not errors:
            print(f"negative {name}: FAIL (accepted unexpectedly)")
            return 1
        else:
            rejected += 1
            print(f"negative {name}: REJECTED")

    print(
        f"DATA-001 VALIDATION PASS: {rejected} named negatives rejected; "
        f"{accepted_boundary} boundary case(s) accepted"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
