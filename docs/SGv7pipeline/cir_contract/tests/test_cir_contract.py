from __future__ import annotations

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
REPO_ROOT = ROOT.parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from cir_contract.contracts.cir_serializer import expected_sample_id, serialize_to_scenescript
from cir_contract.contracts.cir_validator import CIRValidationError, load_schema, validate_record
from generate_dataset_v7 import build_scene_script

EXAMPLES_DIR = ROOT / "cir_contract" / "contracts" / "examples"


class TestCIRContract(unittest.TestCase):
    def setUp(self) -> None:
        self.schema = load_schema()

    def _load(self, name: str) -> dict:
        path = EXAMPLES_DIR / name
        with path.open("r", encoding="utf-8") as fh:
            return json.load(fh)

    def _make_put_down_payload(self) -> dict:
        payload = self._load("ex4_dialogue_then_small_action.json")
        payload["scene_graph"]["objects"] = [
            {
                "id": "object_1",
                "type": "generic",
                "name": "folder",
                "relative_position": "center",
                "marker_binding": {"kind": "unmarked"},
            },
            {
                "id": "object_2",
                "type": "table",
                "name": "стол",
                "relative_position": "center",
                "marker_binding": {"kind": "unmarked"},
            },
        ]
        payload["scene_graph"]["beats"][1]["phase"] = "putdown_object"
        payload["scene_graph"]["beats"][1]["actions"][0]["type"] = "put_down"
        payload["scene_graph"]["beats"][1]["actions"][0]["target_id"] = "object_2"
        payload["scene_graph"]["beats"][1]["actions"][0]["holding_object"] = "object_1"
        payload["budgets"]["object_count"] = 2
        payload["complexity_class"] = "M"
        payload["sample_id"] = expected_sample_id(payload)
        return payload

    def test_all_examples_are_valid(self) -> None:
        for path in sorted(EXAMPLES_DIR.glob("*.json")):
            with self.subTest(example=path.name):
                with path.open("r", encoding="utf-8") as fh:
                    payload = json.load(fh)
                validate_record(payload, schema=self.schema)

    def test_top_level_optional_stubs_are_rejected_for_v1(self) -> None:
        payload = self._load("ex4_dialogue_then_small_action.json")
        payload["scene_graph"]["scene_heading_stub"] = "INT. TEST - DAY"
        with self.assertRaises(CIRValidationError):
            validate_record(payload, schema=self.schema)

    def test_relation_id_prefix_is_enforced(self) -> None:
        payload = self._load("ex1_stop_near_marked_then_first_described.json")
        payload["scene_graph"]["spatial_relations"][0]["id"] = "relation_1"
        with self.assertRaises(CIRValidationError):
            validate_record(payload, schema=self.schema)

    def test_budget_mismatch_is_rejected(self) -> None:
        payload = self._load("ex2_pass_by_object_then_second_runs.json")
        payload["budgets"]["action_count"] = 7
        with self.assertRaises(CIRValidationError):
            validate_record(payload, schema=self.schema)

    def test_sample_id_must_match_structural_hash(self) -> None:
        payload = self._load("ex3_same_type_two_marked_objects.json")
        payload["sample_id"] = "broken__base__s1__deadbeef"
        with self.assertRaises(CIRValidationError):
            validate_record(payload, schema=self.schema)

    def test_serializer_omits_forbidden_runtime_fields(self) -> None:
        payload = self._load("ex4_dialogue_then_small_action.json")
        payload["sample_id"] = expected_sample_id(payload)
        scene_script = serialize_to_scenescript(payload, original_description="A short dialogue.")
        self.assertNotIn("sceneHeading", scene_script)
        self.assertNotIn("locationName", scene_script)
        self.assertNotIn("interiorExterior", scene_script)
        self.assertNotIn("timeOfDay", scene_script)
        self.assertEqual(scene_script["originalDescription"], "A short dialogue.")

    def test_three_actor_ordinal_map_is_valid(self) -> None:
        payload = self._load("ex4_dialogue_then_small_action.json")
        payload["scene_graph"]["actors"].append(
            {
                "id": "actor_3",
                "type": "human",
                "labels": {"ordinal": "third"},
            }
        )
        payload["scene_graph"]["reference_bindings"]["ordinal_map"]["third"] = "actor_3"
        payload["budgets"]["actor_count"] = 3
        payload["complexity_class"] = "L"
        payload["sample_id"] = expected_sample_id(payload)
        validate_record(payload, schema=self.schema)

    def test_put_down_requires_target_and_holding_object(self) -> None:
        payload = self._make_put_down_payload()
        del payload["scene_graph"]["beats"][1]["actions"][0]["target_id"]
        payload["sample_id"] = expected_sample_id(payload)
        with self.assertRaises(CIRValidationError):
            validate_record(payload, schema=self.schema)

    def test_holding_object_must_reference_existing_object(self) -> None:
        payload = self._make_put_down_payload()
        payload["scene_graph"]["beats"][1]["actions"][0]["holding_object"] = "object_999"
        payload["sample_id"] = expected_sample_id(payload)
        with self.assertRaises(CIRValidationError):
            validate_record(payload, schema=self.schema)

    def test_generate_dataset_v7_fails_on_sample_id_drift(self) -> None:
        payload = self._load("ex1_stop_near_marked_then_first_described.json")
        payload["sample_id"] = "broken__base__s1__deadbeef"
        with self.assertRaises(CIRValidationError):
            build_scene_script(payload, original_description="Broken sample id.")


if __name__ == "__main__":
    unittest.main()
