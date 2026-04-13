from __future__ import annotations

import unittest

from augmentation.morphology import apply_morphology_or_surface_transform


class TestMorphology(unittest.TestCase):
    def setUp(self) -> None:
        self.graph_constraints = {
            "ordinal_bindings": {"first": "actor_1", "second": "actor_2"},
            "marked_objects": [
                {
                    "id": "object_marked_ab12",
                    "canonical_name": "комп",
                    "allowed_aliases": ["комп", "компа", "компу"],
                },
                {
                    "id": "object_marked_cd34",
                    "canonical_name": "ноутбук",
                    "allowed_aliases": ["ноутбук", "ноутбука", "ноутбуку"],
                },
            ],
            "must_keep_lemmas": ["курить"],
            "same_type_marker_conflict": False,
        }

    def test_case_genitive_transform_preserves_anchor(self) -> None:
        result = apply_morphology_or_surface_transform(
            "Два актера стоят у комп и первый начинает курить.",
            "morph.marked_object.case_genitive",
            self.graph_constraints,
        )
        self.assertIsNotNone(result)
        updated, metadata = result or ("", {})
        self.assertIn("у компа", updated)
        self.assertEqual(metadata["transform_id"], "morph.marked_object.case_genitive")

    def test_case_dative_transform_requires_whitelisted_form(self) -> None:
        result = apply_morphology_or_surface_transform(
            "Два актера идут к комп и первый начинает курить.",
            "morph.marked_object.case_dative",
            self.graph_constraints,
        )
        self.assertIsNotNone(result)
        updated, _ = result or ("", {})
        self.assertIn("к компу", updated)

    def test_actor_yo_transform_changes_surface_only(self) -> None:
        result = apply_morphology_or_surface_transform(
            "Первый актер идет к компу.",
            "orthography.actor_yo",
            self.graph_constraints,
        )
        self.assertIsNotNone(result)
        updated, _ = result or ("", {})
        self.assertIn("актёр", updated.lower())

    def test_ordinal_wrap_requires_real_bindings(self) -> None:
        constraints = dict(self.graph_constraints)
        constraints["ordinal_bindings"] = {}
        result = apply_morphology_or_surface_transform(
            "Первый идет к компу.",
            "ordinal.wrap_actor_head",
            constraints,
        )
        self.assertIsNone(result)
