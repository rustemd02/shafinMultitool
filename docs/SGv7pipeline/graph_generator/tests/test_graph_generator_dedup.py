from __future__ import annotations

import copy
import unittest
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from graph_generator import DedupIndex, dedup_group_key, graph_fingerprint, normalize_record_for_graph_fingerprint
from pattern_library import generate_pattern_record


class TestGraphGeneratorDedup(unittest.TestCase):
    def test_same_type_marked_ids_normalize_to_same_fingerprint(self) -> None:
        left = generate_pattern_record(
            "same_type_two_marked_objects",
            graph_seed=991,
            source_variant_key="same_type_marker_stress",
        )
        right = copy.deepcopy(left)

        left_ids = [obj["id"] for obj in left["scene_graph"]["objects"]]
        right_ids = [obj["id"] for obj in right["scene_graph"]["objects"]]
        remap = {right_ids[0]: "object_marked_fakeaaaa", right_ids[1]: "object_marked_fakebbbb"}

        for obj in right["scene_graph"]["objects"]:
            obj["id"] = remap[obj["id"]]
            obj["marker_binding"]["marker_short_id"] = obj["id"].removeprefix("object_marked_")

        for beat in right["scene_graph"]["beats"]:
            for action in beat["actions"]:
                if action.get("target_id") in remap:
                    action["target_id"] = remap[action["target_id"]]
                if action.get("holding_object") in remap:
                    action["holding_object"] = remap[action["holding_object"]]

        for relation in right["scene_graph"]["spatial_relations"]:
            if relation["subject"] in remap:
                relation["subject"] = remap[relation["subject"]]
            if relation["object"] in remap:
                relation["object"] = remap[relation["object"]]

        right["scene_graph"]["reference_bindings"]["marked_object_ids"] = [
            remap[object_id] for object_id in right["scene_graph"]["reference_bindings"]["marked_object_ids"]
        ]
        right["scene_graph"]["reference_bindings"]["alias_to_object_id"] = {
            alias: remap[object_id]
            for alias, object_id in right["scene_graph"]["reference_bindings"]["alias_to_object_id"].items()
        }

        self.assertEqual(graph_fingerprint(left), graph_fingerprint(right))

    def test_different_graphs_do_not_collapse(self) -> None:
        left = generate_pattern_record(
            "toward_each_other_then_pass_by_object_then_second_runs",
            graph_seed=801,
            source_variant_key="base",
        )
        right = generate_pattern_record(
            "stop_near_marked_object_then_first_described_action",
            graph_seed=10421,
            source_variant_key="base",
        )
        self.assertNotEqual(graph_fingerprint(left), graph_fingerprint(right))

    def test_dedup_index_rejects_second_duplicate(self) -> None:
        record = generate_pattern_record("dialogue_only", graph_seed=1000, source_variant_key="base")
        duplicate = copy.deepcopy(record)
        index = DedupIndex()
        self.assertTrue(index.add(record))
        self.assertFalse(index.add(duplicate))

    def test_dedup_group_key_is_stable(self) -> None:
        record = generate_pattern_record("dialogue_then_small_action", graph_seed=77, source_variant_key="dialogue_mix")
        self.assertEqual(dedup_group_key(record), dedup_group_key(copy.deepcopy(record)))

    def test_normalized_fingerprint_payload_uses_slot_ids(self) -> None:
        record = generate_pattern_record(
            "same_type_two_marked_objects",
            graph_seed=991,
            source_variant_key="same_type_marker_stress",
        )
        normalized = normalize_record_for_graph_fingerprint(record)
        marked_ids = [obj["id"] for obj in normalized["objects"] if obj["marker_binding"]["kind"] == "marked"]
        self.assertEqual(marked_ids, ["object_marked_SLOT1", "object_marked_SLOT2"])

