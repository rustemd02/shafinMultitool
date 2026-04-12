from __future__ import annotations

import unittest
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from cir_contract.contracts.cir_validator import load_schema, validate_record
from pattern_library import PATTERN_REGISTRY, enumerate_pattern_records, generate_pattern_record, list_pattern_names


class TestPatternLibrary(unittest.TestCase):
    def setUp(self) -> None:
        self.schema = load_schema()

    def test_registry_contains_expected_patterns(self) -> None:
        self.assertEqual(
            list_pattern_names(),
            [
                "dialogue_only",
                "dialogue_then_put_down_object",
                "dialogue_then_small_action",
                "enter_then_put_down_object",
                "open_then_pick_up_object",
                "ordinal_first_second",
                "pick_up_then_put_down_object",
                "same_type_two_marked_objects",
                "stop_near_marked_object_then_first_described_action",
                "toward_each_other",
                "toward_each_other_then_pass_by_marked_object",
                "toward_each_other_then_pass_by_object_then_second_runs",
                "toward_each_other_then_stop_near_marked_object",
                "unsupported_action_described_action",
            ],
        )

    def test_base_example_for_each_pattern_is_valid_cir(self) -> None:
        for pattern_name, spec in sorted(PATTERN_REGISTRY.items()):
            with self.subTest(pattern_name=pattern_name):
                record = generate_pattern_record(
                    pattern_name,
                    graph_seed=10_000 + len(pattern_name),
                    source_variant_key=spec.allowed_source_variant_keys[0],
                )
                validate_record(record, schema=self.schema)

    def test_seedable_enumeration_is_stable(self) -> None:
        left = enumerate_pattern_records(seed=20260412)
        right = enumerate_pattern_records(seed=20260412)
        self.assertEqual(
            [record["sample_id"] for record in left],
            [record["sample_id"] for record in right],
        )

    def test_bucket_filter_returns_only_requested_bucket(self) -> None:
        records = enumerate_pattern_records(seed=42, difficulty_bucket="hard")
        self.assertTrue(records)
        self.assertTrue(all(record["difficulty_bucket"] == "hard" for record in records))
        self.assertEqual(len(records), 18)

    def test_same_type_pattern_uses_two_distinct_marked_ids(self) -> None:
        record = generate_pattern_record(
            "same_type_two_marked_objects",
            graph_seed=991,
            source_variant_key="same_type_marker_stress",
        )
        objects = record["scene_graph"]["objects"]
        self.assertEqual(len(objects), 2)
        self.assertEqual(len({obj["type"] for obj in objects}), 1)
        self.assertIn(objects[0]["type"], {"chair", "table"})
        self.assertEqual(len({obj["id"] for obj in objects}), 2)

    def test_same_type_pattern_anchors_second_actor_to_opposite_marker(self) -> None:
        record = generate_pattern_record(
            "same_type_two_marked_objects",
            graph_seed=100,
            source_variant_key="same_type_marker_stress",
        )
        objects = record["scene_graph"]["objects"]
        target_id = record["scene_graph"]["beats"][0]["actions"][0]["target_id"]
        opposite_id = next(obj["id"] for obj in objects if obj["id"] != target_id)
        relations = {
            (relation["subject"], relation["relation"], relation["object"])
            for relation in record["scene_graph"]["spatial_relations"]
        }
        self.assertIn(("actor_1", "near", target_id), relations)
        self.assertIn(("actor_2", "near", opposite_id), relations)

    def test_same_type_pattern_table_text_matches_table_objects(self) -> None:
        found_table_case = False
        for seed in range(100, 140):
            record = generate_pattern_record(
                "same_type_two_marked_objects",
                graph_seed=seed,
                source_variant_key="same_type_marker_stress",
            )
            marker_types = {obj["type"] for obj in record["scene_graph"]["objects"]}
            if marker_types == {"table"}:
                found_table_case = True
                template = record["internal_metadata"]["canonical_source_template"]
                self.assertIn("столу", template)
                self.assertIn("стола", template)
                self.assertNotIn("стул", template)
                break
        self.assertTrue(found_table_case)

    def test_unsupported_action_pattern_stays_single_actor(self) -> None:
        record = generate_pattern_record(
            "unsupported_action_described_action",
            graph_seed=5150,
            source_variant_key="base",
        )
        self.assertEqual(record["budgets"]["actor_count"], 1)
        self.assertEqual(record["scene_graph"]["reference_bindings"]["ordinal_map"], {"first": "actor_1"})
        described = record["scene_graph"]["beats"][0]["actions"][0]
        self.assertEqual(described["type"], "described_action")

    def test_role_shift_pattern_ends_with_actor_2_run(self) -> None:
        record = generate_pattern_record(
            "toward_each_other_then_pass_by_object_then_second_runs",
            graph_seed=801,
            source_variant_key="base",
        )
        final_action = record["scene_graph"]["beats"][-1]["actions"][0]
        self.assertEqual(final_action["actor_id"], "actor_2")
        self.assertEqual(final_action["type"], "run")

    def test_default_enumeration_matches_weighted_distribution(self) -> None:
        records = enumerate_pattern_records(seed=7)
        self.assertEqual(len(records), 100)

        bucket_counts = {"core": 0, "hard": 0}
        pattern_counts: dict[str, int] = {}
        for record in records:
            bucket_counts[record["difficulty_bucket"]] += 1
            pattern_counts[record["pattern_name"]] = pattern_counts.get(record["pattern_name"], 0) + 1

        self.assertEqual(bucket_counts, {"core": 82, "hard": 18})
        self.assertEqual(
            pattern_counts,
            {
                "dialogue_only": 8,
                "dialogue_then_put_down_object": 5,
                "dialogue_then_small_action": 8,
                "enter_then_put_down_object": 4,
                "open_then_pick_up_object": 5,
                "ordinal_first_second": 10,
                "pick_up_then_put_down_object": 6,
                "same_type_two_marked_objects": 4,
                "stop_near_marked_object_then_first_described_action": 7,
                "toward_each_other": 9,
                "toward_each_other_then_pass_by_marked_object": 8,
                "toward_each_other_then_pass_by_object_then_second_runs": 7,
                "toward_each_other_then_stop_near_marked_object": 10,
                "unsupported_action_described_action": 9,
            },
        )

    def test_new_open_then_pick_up_pattern_has_expected_order(self) -> None:
        record = generate_pattern_record(
            "open_then_pick_up_object",
            graph_seed=1001,
            source_variant_key="base",
        )
        beats = record["scene_graph"]["beats"]
        self.assertEqual([beat["phase"] for beat in beats], ["open_object", "pickup_object"])
        self.assertEqual(beats[0]["actions"][0]["type"], "open")
        self.assertEqual(beats[1]["actions"][0]["type"], "pick_up")

    def test_new_pick_up_then_put_down_pattern_has_holding_object(self) -> None:
        record = generate_pattern_record(
            "pick_up_then_put_down_object",
            graph_seed=1002,
            source_variant_key="base",
        )
        final_action = record["scene_graph"]["beats"][1]["actions"][0]
        self.assertEqual(final_action["type"], "put_down")
        self.assertIn("holding_object", final_action)

    def test_dialogue_then_put_down_text_matches_holding_object(self) -> None:
        expected_by_token = {
            "папк": "folder",
            "кружк": "cup",
            "пакет": "bag",
        }
        for seed in range(100, 140):
            record = generate_pattern_record(
                "dialogue_then_put_down_object",
                graph_seed=seed,
                source_variant_key="base",
            )
            dialogue = record["scene_graph"]["beats"][0]["actions"][0]["dialogue"]
            put_down = record["scene_graph"]["beats"][1]["actions"][0]
            object_by_id = {obj["id"]: obj["name"] for obj in record["scene_graph"]["objects"]}
            held_name = object_by_id[put_down["holding_object"]]
            for token, expected_name in expected_by_token.items():
                if token in dialogue:
                    self.assertEqual(held_name, expected_name)
                    break

    def test_ordinal_first_second_actions_match_template_contract(self) -> None:
        for seed in range(100, 120):
            record = generate_pattern_record(
                "ordinal_first_second",
                graph_seed=seed,
                source_variant_key="base",
            )
            actions = record["scene_graph"]["beats"][0]["actions"]
            self.assertEqual(actions[0]["type"], "approach")
            self.assertEqual(actions[1]["type"], "look_at")

    def test_unsupported_action_text_matches_object(self) -> None:
        expected_by_token = {
            "двер": "дверь",
            "стол": "стол",
            "шкаф": "шкаф",
        }
        for seed in range(100, 150):
            record = generate_pattern_record(
                "unsupported_action_described_action",
                graph_seed=seed,
                source_variant_key="base",
            )
            text = record["scene_graph"]["beats"][0]["actions"][0]["described_action"]["canonical_text"]
            obj_name = record["scene_graph"]["objects"][0]["name"]
            for token, expected_name in expected_by_token.items():
                if token in text:
                    self.assertEqual(obj_name, expected_name)
                    break

    def test_morphology_stress_keeps_canonical_marker_source_name(self) -> None:
        record = generate_pattern_record(
            "toward_each_other_then_stop_near_marked_object",
            graph_seed=1201,
            source_variant_key="morphology_stress",
        )
        source_name = record["scene_graph"]["objects"][0]["marker_binding"]["source_name"]
        self.assertIn(source_name, {"laptop", "notebook", "pc"})

    def test_stress_variant_changes_scene_graph_payload(self) -> None:
        base = generate_pattern_record(
            "toward_each_other_then_stop_near_marked_object",
            graph_seed=1201,
            source_variant_key="base",
        )
        stress = generate_pattern_record(
            "toward_each_other_then_stop_near_marked_object",
            graph_seed=1201,
            source_variant_key="morphology_stress",
        )
        self.assertNotEqual(
            base["scene_graph"]["reference_bindings"]["alias_to_object_id"],
            stress["scene_graph"]["reference_bindings"]["alias_to_object_id"],
        )
        self.assertNotEqual(base["scene_graph"]["must_preserve"], stress["scene_graph"]["must_preserve"])

    def test_graph_seed_changes_non_id_content(self) -> None:
        signatures = set()
        for seed in (101, 202, 303, 404):
            record = generate_pattern_record(
                "dialogue_only",
                graph_seed=seed,
                source_variant_key="base",
            )
            beat = record["scene_graph"]["beats"][0]
            signatures.add(tuple(action["dialogue"] for action in beat["actions"]))
        self.assertGreaterEqual(len(signatures), 2)


if __name__ == "__main__":
    unittest.main()
