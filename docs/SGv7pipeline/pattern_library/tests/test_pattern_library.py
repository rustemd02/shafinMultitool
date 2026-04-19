from __future__ import annotations

import re
import unittest
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from cir_contract.contracts.cir_validator import load_schema, validate_record
from pattern_library import (
    PATTERN_REGISTRY,
    build_failure_coverage_report,
    enumerate_pattern_records,
    generate_pattern_record,
    list_pattern_names,
)
from pattern_library.registry import _inflect_person_name


class TestPatternLibrary(unittest.TestCase):
    def setUp(self) -> None:
        self.schema = load_schema()

    def test_registry_contains_expected_patterns(self) -> None:
        self.assertEqual(
            list_pattern_names(),
            [
                "dialogue_only",
                "dialogue_then_pick_up_object_then_give_to_third_actor",
                "dialogue_then_put_down_object",
                "dialogue_then_small_action",
                "enter_then_put_down_object",
                "first_pick_up_object_then_give_to_third_actor",
                "open_then_pick_up_object",
                "ordinal_first_second",
                "ordinal_first_second_third",
                "pick_up_then_put_down_object",
                "same_type_two_marked_objects",
                "same_type_two_marked_objects_left_right",
                "same_type_two_marked_objects_near_far",
                "second_pick_up_object_then_give_to_third_actor",
                "stop_near_marked_object_then_first_described_action",
                "toward_each_other",
                "toward_each_other_then_pass_by_marked_object",
                "toward_each_other_then_pass_by_marked_object_then_second_runs",
                "toward_each_other_then_pass_by_object_then_second_runs",
                "toward_each_other_then_stop_near_marked_object",
                "toward_each_other_then_stop_near_marked_object_then_second_runs",
                "toward_each_other_then_stop_near_marked_object_then_third_actor_described_action",
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
        self.assertEqual(
            len(records),
            sum(spec.default_share for spec in PATTERN_REGISTRY.values() if spec.difficulty_bucket == "hard"),
        )

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

    def test_same_type_left_right_pattern_keeps_exact_side_bindings(self) -> None:
        record = generate_pattern_record(
            "same_type_two_marked_objects_left_right",
            graph_seed=1301,
            source_variant_key="same_type_marker_stress",
        )
        objects_by_position = {
            obj["relative_position"]: obj for obj in record["scene_graph"]["objects"]
        }
        self.assertEqual(set(objects_by_position), {"left", "right"})

        alias_to_object_id = record["scene_graph"]["reference_bindings"]["alias_to_object_id"]
        self.assertEqual(set(alias_to_object_id.values()), {obj["id"] for obj in objects_by_position.values()})

        left_aliases = {
            alias for alias in alias_to_object_id if "left" in alias.lower() or "лев" in alias.lower()
        }
        right_aliases = {
            alias for alias in alias_to_object_id if "right" in alias.lower() or "прав" in alias.lower()
        }
        self.assertTrue(left_aliases)
        self.assertTrue(right_aliases)
        self.assertTrue(all(alias_to_object_id[alias] == objects_by_position["left"]["id"] for alias in left_aliases))
        self.assertTrue(all(alias_to_object_id[alias] == objects_by_position["right"]["id"] for alias in right_aliases))

    def test_same_type_near_far_pattern_keeps_exact_distance_bindings(self) -> None:
        record = generate_pattern_record(
            "same_type_two_marked_objects_near_far",
            graph_seed=1302,
            source_variant_key="same_type_marker_stress",
        )
        objects_by_position = {
            obj["relative_position"]: obj for obj in record["scene_graph"]["objects"]
        }
        self.assertEqual(set(objects_by_position), {"foreground", "background"})

        alias_to_object_id = record["scene_graph"]["reference_bindings"]["alias_to_object_id"]
        self.assertEqual(set(alias_to_object_id.values()), {obj["id"] for obj in objects_by_position.values()})

        near_aliases = {
            alias for alias in alias_to_object_id if "near" in alias.lower() or "ближ" in alias.lower()
        }
        far_aliases = {
            alias for alias in alias_to_object_id if "far" in alias.lower() or "даль" in alias.lower()
        }
        self.assertTrue(near_aliases)
        self.assertTrue(far_aliases)
        self.assertTrue(
            all(alias_to_object_id[alias] == objects_by_position["foreground"]["id"] for alias in near_aliases)
        )
        self.assertTrue(
            all(alias_to_object_id[alias] == objects_by_position["background"]["id"] for alias in far_aliases)
        )
        self.assertIn("marker_axis:near_far", record["scene_graph"]["must_preserve"])

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

    def test_new_second_runs_patterns_keep_actor_2_run_asymmetry(self) -> None:
        for pattern_name in (
            "toward_each_other_then_pass_by_marked_object_then_second_runs",
            "toward_each_other_then_stop_near_marked_object_then_second_runs",
        ):
            with self.subTest(pattern_name=pattern_name):
                record = generate_pattern_record(
                    pattern_name,
                    graph_seed=1801,
                    source_variant_key="base",
                )
                actions = [
                    action
                    for beat in record["scene_graph"]["beats"]
                    for action in beat["actions"]
                ]
                final_actions = record["scene_graph"]["beats"][-1]["actions"]

                self.assertEqual(len(final_actions), 1)
                self.assertEqual(final_actions[0]["actor_id"], "actor_2")
                self.assertEqual(final_actions[0]["type"], "run")
                self.assertFalse(
                    any(action["actor_id"] == "actor_1" and action["type"] == "run" for action in actions)
                )

    def test_default_enumeration_matches_weighted_distribution(self) -> None:
        records = enumerate_pattern_records(seed=7)
        self.assertEqual(len(records), 100)

        bucket_counts = {"core": 0, "hard": 0}
        pattern_counts: dict[str, int] = {}
        for record in records:
            bucket_counts[record["difficulty_bucket"]] += 1
            pattern_counts[record["pattern_name"]] = pattern_counts.get(record["pattern_name"], 0) + 1

        self.assertEqual(bucket_counts, {"core": 75, "hard": 25})
        self.assertEqual(
            pattern_counts,
            {
                "dialogue_only": 6,
                "dialogue_then_pick_up_object_then_give_to_third_actor": 2,
                "dialogue_then_put_down_object": 6,
                "dialogue_then_small_action": 5,
                "enter_then_put_down_object": 5,
                "first_pick_up_object_then_give_to_third_actor": 2,
                "open_then_pick_up_object": 8,
                "ordinal_first_second": 9,
                "ordinal_first_second_third": 2,
                "pick_up_then_put_down_object": 8,
                "same_type_two_marked_objects": 3,
                "same_type_two_marked_objects_left_right": 3,
                "same_type_two_marked_objects_near_far": 2,
                "second_pick_up_object_then_give_to_third_actor": 2,
                "stop_near_marked_object_then_first_described_action": 2,
                "toward_each_other": 4,
                "toward_each_other_then_pass_by_marked_object": 9,
                "toward_each_other_then_pass_by_marked_object_then_second_runs": 2,
                "toward_each_other_then_pass_by_object_then_second_runs": 2,
                "toward_each_other_then_stop_near_marked_object": 10,
                "toward_each_other_then_stop_near_marked_object_then_second_runs": 2,
                "toward_each_other_then_stop_near_marked_object_then_third_actor_described_action": 1,
                "unsupported_action_described_action": 5,
            },
        )

    def test_non_default_total_records_preserves_remainder_allocation(self) -> None:
        records = enumerate_pattern_records(seed=7, total_records=113)
        self.assertEqual(len(records), 113)

        bucket_counts = {"core": 0, "hard": 0}
        pattern_counts: dict[str, int] = {}
        for record in records:
            bucket_counts[record["difficulty_bucket"]] += 1
            pattern_counts[record["pattern_name"]] = pattern_counts.get(record["pattern_name"], 0) + 1

        self.assertEqual(bucket_counts, {"core": 86, "hard": 27})
        self.assertEqual(
            pattern_counts,
            {
                "dialogue_only": 7,
                "dialogue_then_pick_up_object_then_give_to_third_actor": 2,
                "dialogue_then_put_down_object": 7,
                "dialogue_then_small_action": 6,
                "enter_then_put_down_object": 6,
                "first_pick_up_object_then_give_to_third_actor": 2,
                "open_then_pick_up_object": 9,
                "ordinal_first_second": 10,
                "ordinal_first_second_third": 2,
                "pick_up_then_put_down_object": 9,
                "same_type_two_marked_objects": 4,
                "same_type_two_marked_objects_left_right": 4,
                "same_type_two_marked_objects_near_far": 2,
                "second_pick_up_object_then_give_to_third_actor": 2,
                "stop_near_marked_object_then_first_described_action": 2,
                "toward_each_other": 5,
                "toward_each_other_then_pass_by_marked_object": 10,
                "toward_each_other_then_pass_by_marked_object_then_second_runs": 2,
                "toward_each_other_then_pass_by_object_then_second_runs": 2,
                "toward_each_other_then_stop_near_marked_object": 11,
                "toward_each_other_then_stop_near_marked_object_then_second_runs": 2,
                "toward_each_other_then_stop_near_marked_object_then_third_actor_described_action": 1,
                "unsupported_action_described_action": 6,
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

    def test_dialogue_templates_match_speaker_gender(self) -> None:
        female_names = {"Анна", "Лена", "Нина", "Ира", "Мила", "Света", "Катя", "Юля", "Вика", "Алина", "Таня", "Марина", "Дарья", "Лиза", "Яна", "Соня"}
        for pattern_name in ("dialogue_only", "dialogue_then_small_action"):
            with self.subTest(pattern_name=pattern_name):
                for seed in range(100, 180):
                    record = generate_pattern_record(
                        pattern_name,
                        graph_seed=seed,
                        source_variant_key="base",
                    )
                    first_actor = record["scene_graph"]["actors"][0]
                    first_name = first_actor.get("name")
                    first_line = record["scene_graph"]["beats"][0]["actions"][0]["dialogue"]
                    if first_name in female_names:
                        self.assertNotRegex(first_line, r"\b(?:отправил|переслал|загрузил|подготовил|скинул|приложил)\b")

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
        self.assertIn(
            source_name,
            {
                "pc",
                "workstation",
                "monitor",
                "terminal",
                "screen",
                "panel",
                "rack",
                "cabinet",
                "counter",
                "bench",
                "kiosk",
                "lamp",
                "poster",
                "sign",
                "cart",
                "door",
                "window",
                "wall",
                "pillar",
            },
        )

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

    def test_motion_templates_localize_walk_modifiers(self) -> None:
        found_localized = False
        for seed in range(100, 160):
            record = generate_pattern_record(
                "toward_each_other",
                graph_seed=seed,
                source_variant_key="base",
            )
            template = record["internal_metadata"]["canonical_source_template"]
            self.assertNotRegex(template, r"\b(?:quickly|slowly|carefully)\b")
            if any(token in template for token in ("не спеша", "быстро", "осторожно")):
                found_localized = True
        self.assertTrue(found_localized)

    def test_marked_object_morphology_stress_uses_multiple_surface_families(self) -> None:
        seen_source_names = set()
        for seed in range(600, 680):
            record = generate_pattern_record(
                "toward_each_other_then_stop_near_marked_object",
                graph_seed=seed,
                source_variant_key="morphology_stress",
            )
            seen_source_names.add(record["scene_graph"]["objects"][0]["marker_binding"]["source_name"])
        self.assertGreaterEqual(len(seen_source_names), 8)

    def test_three_beat_motion_templates_include_explicit_sequence_markers(self) -> None:
        target_patterns = (
            "stop_near_marked_object_then_first_described_action",
            "toward_each_other_then_pass_by_object_then_second_runs",
            "toward_each_other_then_stop_near_marked_object_then_second_runs",
            "toward_each_other_then_pass_by_marked_object_then_second_runs",
            "toward_each_other_then_stop_near_marked_object_then_third_actor_described_action",
        )
        for pattern_name in target_patterns:
            with self.subTest(pattern_name=pattern_name):
                record = generate_pattern_record(
                    pattern_name,
                    graph_seed=2408,
                    source_variant_key="base",
                )
                template = record["internal_metadata"]["canonical_source_template"].lower()
                self.assertTrue(
                    any(marker in template for marker in ("сначала", "затем", "после этого", "в конце")),
                    msg=template,
                )

    def test_marked_object_motion_templates_avoid_double_prepositions_and_bad_cases(self) -> None:
        pattern_names = (
            "stop_near_marked_object_then_first_described_action",
            "toward_each_other_then_stop_near_marked_object",
            "toward_each_other_then_pass_by_marked_object",
            "toward_each_other_then_pass_by_object_then_second_runs",
            "toward_each_other_then_stop_near_marked_object_then_second_runs",
            "toward_each_other_then_pass_by_marked_object_then_second_runs",
            "toward_each_other_then_stop_near_marked_object_then_third_actor_described_action",
        )
        banned_patterns = (
            r"\bоколо\s+рядом\s+с\b",
            r"\bу\s+рядом\s+со\b",
            r"\bмимо\s+монитор\b",
            r"\bмимо\s+терминал\b",
            r"\bу\s+рядом\s+с\b",
            r"\bу\s+около\b",
        )
        for pattern_name in pattern_names:
            for variant in PATTERN_REGISTRY[pattern_name].allowed_source_variant_keys:
                with self.subTest(pattern_name=pattern_name, variant=variant):
                    for seed in range(410, 430):
                        record = generate_pattern_record(
                            pattern_name,
                            graph_seed=seed,
                            source_variant_key=variant,
                        )
                        template = record["internal_metadata"]["canonical_source_template"].lower()
                        for banned in banned_patterns:
                            self.assertIsNone(re.search(banned, template))

    def test_open_then_pick_up_registry_template_is_not_mixed_script(self) -> None:
        record = generate_pattern_record(
            "open_then_pick_up_object",
            graph_seed=576329,
            source_variant_key="base",
        )
        template = record["internal_metadata"]["canonical_source_template"]
        self.assertNotIn("кейc", template.lower())
        self.assertNotRegex(template, r"(?=\w*[A-Za-z])(?=\w*[А-Яа-яЁё])")

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

    def test_irregular_person_name_inflection_keeps_pavel_grammatical(self) -> None:
        self.assertEqual(_inflect_person_name("Павел", "accusative"), "Павла")
        self.assertEqual(_inflect_person_name("Павел", "dative"), "Павлу")

    def test_three_actor_ordinal_pattern_binds_all_ordinals(self) -> None:
        record = generate_pattern_record(
            "ordinal_first_second_third",
            graph_seed=2401,
            source_variant_key="base",
        )
        self.assertEqual(record["budgets"]["actor_count"], 3)
        self.assertEqual(
            record["scene_graph"]["reference_bindings"]["ordinal_map"],
            {"first": "actor_1", "second": "actor_2", "third": "actor_3"},
        )
        actions = record["scene_graph"]["beats"][0]["actions"]
        self.assertEqual([action["actor_id"] for action in actions], ["actor_1", "actor_2", "actor_3"])

    def test_three_actor_marked_action_ends_with_actor_3_described_action(self) -> None:
        record = generate_pattern_record(
            "toward_each_other_then_stop_near_marked_object_then_third_actor_described_action",
            graph_seed=2402,
            source_variant_key="base",
        )
        self.assertEqual(record["budgets"]["actor_count"], 3)
        final_action = record["scene_graph"]["beats"][-1]["actions"][0]
        self.assertEqual(final_action["actor_id"], "actor_3")
        self.assertEqual(final_action["type"], "described_action")

    def test_three_actor_handoff_gives_object_to_actor_3(self) -> None:
        record = generate_pattern_record(
            "dialogue_then_pick_up_object_then_give_to_third_actor",
            graph_seed=2403,
            source_variant_key="base",
        )
        self.assertEqual(record["budgets"]["actor_count"], 3)
        final_action = record["scene_graph"]["beats"][-1]["actions"][0]
        self.assertEqual(final_action["type"], "give")
        self.assertEqual(final_action["target_id"], "actor_3")
        self.assertEqual(final_action["holding_object"], "object_1")

    def test_new_three_actor_handoff_patterns_preserve_recipient_binding(self) -> None:
        expected_pickup_actor = {
            "first_pick_up_object_then_give_to_third_actor": "actor_1",
            "second_pick_up_object_then_give_to_third_actor": "actor_2",
        }
        for pattern_name, actor_id in expected_pickup_actor.items():
            with self.subTest(pattern_name=pattern_name):
                record = generate_pattern_record(
                    pattern_name,
                    graph_seed=2404,
                    source_variant_key="base",
                )
                self.assertEqual(record["budgets"]["actor_count"], 3)

                pickup_action = record["scene_graph"]["beats"][-2]["actions"][0]
                give_action = record["scene_graph"]["beats"][-1]["actions"][0]

                self.assertEqual(pickup_action["type"], "pick_up")
                self.assertEqual(pickup_action["actor_id"], actor_id)
                self.assertEqual(give_action["type"], "give")
                self.assertEqual(give_action["actor_id"], actor_id)
                self.assertEqual(give_action["target_id"], "actor_3")
                self.assertEqual(give_action["holding_object"], pickup_action["holding_object"])

    def test_handoff_canonical_templates_use_gendered_object_pronoun(self) -> None:
        target_patterns = (
            "dialogue_then_pick_up_object_then_give_to_third_actor",
            "first_pick_up_object_then_give_to_third_actor",
            "second_pick_up_object_then_give_to_third_actor",
        )
        for pattern_name in target_patterns:
            with self.subTest(pattern_name=pattern_name):
                seen_letter_or_key = False
                for seed in range(2400, 2460):
                    record = generate_pattern_record(
                        pattern_name,
                        graph_seed=seed,
                        source_variant_key=PATTERN_REGISTRY[pattern_name].allowed_source_variant_keys[0],
                    )
                    object_name = record["scene_graph"]["objects"][0]["name"]
                    template = record["internal_metadata"]["canonical_source_template"]
                    if object_name in {"letter", "key"}:
                        seen_letter_or_key = True
                        self.assertIn("передаёт его", template)
                        self.assertNotIn("передаёт её", template)
                        break
                self.assertTrue(seen_letter_or_key)

    def test_failure_coverage_report_has_no_gaps(self) -> None:
        report = build_failure_coverage_report()
        self.assertEqual(report["unknown_patterns"], [])
        self.assertEqual(report["unknown_failures"], [])
        self.assertEqual(report["uncovered_failures"], [])

    def test_failure_coverage_report_has_multi_pattern_ownership_for_weak_zones(self) -> None:
        report = build_failure_coverage_report()
        failures = {
            entry["failure_id"]: set(entry["owning_patterns"])
            for entry in report["failures"]
        }

        self.assertGreaterEqual(len(failures["example_3_multi_beat_role_shift_loss"]), 3)
        self.assertTrue(
            {
                "toward_each_other_then_pass_by_object_then_second_runs",
                "toward_each_other_then_pass_by_marked_object_then_second_runs",
                "toward_each_other_then_stop_near_marked_object_then_second_runs",
            }.issubset(failures["example_3_multi_beat_role_shift_loss"])
        )

        self.assertGreaterEqual(len(failures["example_4_same_type_marker_identity_loss"]), 3)
        self.assertTrue(
            {
                "same_type_two_marked_objects",
                "same_type_two_marked_objects_left_right",
                "same_type_two_marked_objects_near_far",
            }.issubset(failures["example_4_same_type_marker_identity_loss"])
        )

        self.assertGreaterEqual(len(failures["example_7_three_actor_handoff_loss"]), 3)
        self.assertTrue(
            {
                "dialogue_then_pick_up_object_then_give_to_third_actor",
                "first_pick_up_object_then_give_to_third_actor",
                "second_pick_up_object_then_give_to_third_actor",
            }.issubset(failures["example_7_three_actor_handoff_loss"])
        )


if __name__ == "__main__":
    unittest.main()
