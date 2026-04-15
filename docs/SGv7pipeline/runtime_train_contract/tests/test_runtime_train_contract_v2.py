from __future__ import annotations

import json
from pathlib import Path
import sys
import unittest
from typing import Any

DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from cir_contract.contracts import serialize_to_scenescript
from runtime_train_contract.drift_checks import (
    DriftCheckError,
    marked_id_collision_resolution_check,
    null_forbidden_check,
    optional_present_canonicalization_check,
)

FIXTURES_PATH = (
    DOCS_ROOT / "runtime_train_contract" / "fixtures" / "runtime_train_contract_fixtures_v2.jsonl"
)


def _load_fixture_rows(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        rows.append(json.loads(stripped))
    return rows


def _contains_forbidden_key(payload: Any, forbidden: set[str]) -> bool:
    if isinstance(payload, dict):
        for key, value in payload.items():
            if key in forbidden:
                return True
            if _contains_forbidden_key(value, forbidden):
                return True
    if isinstance(payload, list):
        for value in payload:
            if _contains_forbidden_key(value, forbidden):
                return True
    return False


def _build_optional_policy_cir_record(*, present: bool) -> dict[str, Any]:
    action_type = "approach" if present else "stand"
    action_payload: dict[str, Any] = {
        "id": "action_1",
        "actor_id": "actor_1",
        "type": action_type,
        "target_id": "object_1" if present else None,
        "direction": "to_target" if present else None,
        "modifier": "quickly" if present else None,
        "resulting_pose": "walking" if present else "standing",
        "holding_object": None,
        "dialogue": None,
    }
    return {
        "runtime_projection": {
            "top_level_optional_policy": "omit_all",
            "beat_optional_policy": "preserve_if_present_else_omit",
            "described_action_source_text_policy": "canonical_text_to_sourceText",
        },
        "scene_graph": {
            "actors": [{"id": "actor_1", "type": "human", "name": None}],
            "objects": [
                {
                    "id": "object_1",
                    "type": "generic",
                    "name": "ноутбук" if present else None,
                    "relative_position": "unknown",
                    "marker_binding": {"kind": "unmarked"},
                }
            ],
            "beats": [{"id": "beat_1", "actions": [{"semantics": {"chronology_rank": 1}, **action_payload}]}],
            "spatial_relations": [],
            "reference_bindings": {"marked_object_ids": [], "alias_to_object_id": {}},
            "must_preserve": [],
        },
    }


class TestRuntimeTrainContractV2Fixtures(unittest.TestCase):
    def test_fixture_set_contains_required_v2_cases(self) -> None:
        rows = _load_fixture_rows(FIXTURES_PATH)
        fixture_ids = {str(row.get("fixture_id", "")) for row in rows}
        self.assertIn("marked_id_collision_resolution_v2", fixture_ids)
        self.assertIn("optional_field_omission_v2", fixture_ids)
        self.assertIn("optional_field_present_v2", fixture_ids)
        self.assertIn("null_forbidden_v2", fixture_ids)

    def test_generation_target_scope_excludes_camera_and_min_duration(self) -> None:
        rows = _load_fixture_rows(FIXTURES_PATH)
        for row in rows:
            generation_target = row.get("generation_target_json", {})
            self.assertFalse(
                _contains_forbidden_key(generation_target, {"camera", "minDuration"}),
                msg=f"fixture_id={row.get('fixture_id')} contains camera/minDuration drift",
            )

    def test_optional_policy_has_omit_and_present_branches(self) -> None:
        rows = _load_fixture_rows(FIXTURES_PATH)
        by_id = {str(row["fixture_id"]): row for row in rows}

        omission_actions = (
            by_id["optional_field_omission_v2"]["generation_target_json"]["beats"][0]["actions"][0]
        )
        present_actions = (
            by_id["optional_field_present_v2"]["generation_target_json"]["beats"][0]["actions"][0]
        )
        omission_object = by_id["optional_field_omission_v2"]["generation_target_json"]["objects"][0]
        present_object = by_id["optional_field_present_v2"]["generation_target_json"]["objects"][0]

        self.assertNotIn("target", omission_actions)
        self.assertNotIn("direction", omission_actions)
        self.assertNotIn("modifier", omission_actions)
        self.assertNotIn("name", omission_object)

        self.assertIn("target", present_actions)
        self.assertIn("direction", present_actions)
        self.assertIn("modifier", present_actions)
        self.assertIn("name", present_object)

    def test_marked_id_collision_resolution_check_executes_policy(self) -> None:
        rows = _load_fixture_rows(FIXTURES_PATH)
        by_id = {str(row["fixture_id"]): row for row in rows}
        collision_fixture = by_id["marked_id_collision_resolution_v2"]
        policy_rows = collision_fixture.get("marked_id_policy_input_rows")
        self.assertIsInstance(policy_rows, list)

        resolved_ids = marked_id_collision_resolution_check(
            marked_rows=policy_rows,  # type: ignore[arg-type]
            expected_resolved_ids=collision_fixture["expected_marked_ids"],
        )
        generation_ids = [
            obj["id"]
            for obj in collision_fixture["generation_target_json"]["objects"]
            if str(obj.get("id", "")).startswith("object_marked_")
        ]
        runtime_ids = [
            obj["id"]
            for obj in collision_fixture["runtime_envelope_json"]["objects"]
            if str(obj.get("id", "")).startswith("object_marked_")
        ]
        self.assertEqual(resolved_ids, generation_ids)
        self.assertEqual(resolved_ids, runtime_ids)

    def test_null_forbidden_check_is_executable(self) -> None:
        rows = _load_fixture_rows(FIXTURES_PATH)
        by_id = {str(row["fixture_id"]): row for row in rows}

        negative_payload = by_id["null_forbidden_v2"]["negative_generation_target_json"]
        with self.assertRaises(DriftCheckError):
            null_forbidden_check(negative_payload)

        for row in rows:
            null_forbidden_check(row["generation_target_json"])

    def test_optional_present_canonicalization_on_real_serializer(self) -> None:
        omitted_payload = serialize_to_scenescript(
            _build_optional_policy_cir_record(present=False),
            original_description="Актер стоит.",
        )
        present_payload = serialize_to_scenescript(
            _build_optional_policy_cir_record(present=True),
            original_description="Актер быстро подходит к ноутбуку.",
        )

        omission_action = omitted_payload["beats"][0]["actions"][0]
        omission_object = omitted_payload["objects"][0]
        present_action = present_payload["beats"][0]["actions"][0]
        present_object = present_payload["objects"][0]

        optional_present_canonicalization_check(
            omission_action=omission_action,
            omission_object=omission_object,
            present_action=present_action,
            present_object=present_object,
        )
        null_forbidden_check(omitted_payload)
        null_forbidden_check(present_payload)


if __name__ == "__main__":
    unittest.main()
