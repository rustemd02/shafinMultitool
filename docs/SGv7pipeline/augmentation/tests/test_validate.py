from __future__ import annotations

import unittest

from augmentation.validate import validate_augmented_record


class TestValidate(unittest.TestCase):
    def test_missing_graph_constraints_is_rejected(self) -> None:
        reasons = validate_augmented_record(
            {
                "generation_pass": "augmentation",
                "source_text": "Первый идет к компу",
                "transform_chain": [{"transform_id": "noise.double_space"}],
            }
        )
        self.assertIn("missing_graph_constraints_contract", reasons)

    def test_missing_critical_action_lemma_is_rejected(self) -> None:
        record = {
            "generation_pass": "augmentation",
            "source_text": "Первый идет к компу",
            "graph_constraints": {
                "ordinal_bindings": {"first": "actor_1"},
                "marked_objects": [
                    {
                        "id": "object_marked_ab12",
                        "canonical_name": "комп",
                        "allowed_aliases": ["комп", "компа", "компу"],
                    }
                ],
                "must_keep_lemmas": ["курить"],
                "same_type_marker_conflict": False,
            },
            "transform_chain": [
                {
                    "transform_id": "noise.drop_final_punctuation",
                    "class": "punctuation_noise",
                    "safety_level": "safe",
                    "slot_type": "sentence_tail",
                    "slot_index": 0,
                    "before": ".",
                    "after": "",
                }
            ],
            "risk_flags": [],
        }
        reasons = validate_augmented_record(record)
        self.assertIn("critical_action_lemma_lost", reasons)

    def test_same_type_generic_mention_is_rejected(self) -> None:
        record = {
            "generation_pass": "augmentation",
            "source_text": "Первый подходит к стулу.",
            "graph_constraints": {
                "ordinal_bindings": {"first": "actor_1"},
                "marked_objects": [
                    {
                        "id": "object_marked_1111aaaa",
                        "canonical_name": "левый стул",
                        "allowed_aliases": ["стул", "стула", "стулу", "левый стул", "левого стула"],
                    },
                    {
                        "id": "object_marked_2222bbbb",
                        "canonical_name": "правый стул",
                        "allowed_aliases": ["стул", "стула", "стулу", "правый стул", "правого стула", "тот стул"],
                    },
                ],
                "must_keep_lemmas": [],
                "same_type_marker_conflict": True,
                "target_object_id": "object_marked_2222bbbb",
                "required_disambiguation_cues": ["правый стул", "правого стула", "тот стул"],
            },
            "transform_chain": [
                {
                    "transform_id": "noise.drop_final_punctuation",
                    "class": "punctuation_noise",
                    "safety_level": "safe",
                    "slot_type": "sentence_tail",
                    "slot_index": 25,
                    "before": ".",
                    "after": "",
                }
            ],
            "risk_flags": [],
        }
        reasons = validate_augmented_record(record)
        self.assertIn("same_type_marker_disambiguation_lost", reasons)
