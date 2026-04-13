from __future__ import annotations

import unittest

from augmentation.slots import build_surface_anchor_snapshot, find_marked_object_mentions, find_ordinal_slots


class TestSlots(unittest.TestCase):
    def test_marked_object_and_ordinal_slots_are_detected(self) -> None:
        graph_constraints = {
            "ordinal_bindings": {"first": "actor_1", "second": "actor_2"},
            "marked_objects": [
                {
                    "id": "object_marked_ab12",
                    "canonical_name": "комп",
                    "allowed_aliases": ["комп", "компа", "компу"],
                }
            ],
            "must_keep_lemmas": ["курить"],
            "same_type_marker_conflict": False,
        }
        text = "Два актера идут к компу, после этого первый начинает курить."
        mentions = find_marked_object_mentions(text, graph_constraints)
        self.assertEqual(mentions[0]["matched_text"].lower(), "компу")
        ordinals = find_ordinal_slots(text)
        self.assertEqual(ordinals[0].text.lower(), "первый")
        snapshot = build_surface_anchor_snapshot(text, graph_constraints)
        self.assertIn("первый", snapshot["ordinal_mentions"])
