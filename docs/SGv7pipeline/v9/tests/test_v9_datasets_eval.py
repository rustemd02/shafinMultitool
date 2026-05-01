from __future__ import annotations

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from v9.datasets import _make_corrupted_event_table, build_v9_event_sft_rows, split_rows
from v9.eval import summarize_event_slice_metrics
from v9.eval_artifacts import build_v9_eval_artifacts
from v9.projection import cir_to_v9_event_table, cir_to_v9_slot_catalog


def _sample_cir_record() -> dict:
    return {
        "sample_id": "sample__family_1",
        "source_variant_text": "первый актер идет ко второму актеру",
        "graph_family_key": "family_1",
        "scene_graph": {
            "actors": [
                {"id": "actor_1", "type": "human", "labels": {"ordinal": "first"}},
                {"id": "actor_2", "type": "human", "labels": {"ordinal": "second"}},
            ],
            "objects": [],
            "beats": [
                {
                    "id": "beat_1",
                    "actions": [
                        {"actor_id": "actor_1", "type": "walk", "target_id": "actor_2"},
                        {"actor_id": "actor_2", "type": "walk", "target_id": "actor_1"},
                    ],
                }
            ],
            "spatial_relations": [],
        },
    }


class V9DatasetEvalTests(unittest.TestCase):
    def test_split_rows_requires_explicit_key(self) -> None:
        rows = [{"sample_id": "a", "packaging_metadata": {}}]
        with self.assertRaises(ValueError):
            split_rows(rows, key_field="split_family_id", val_fraction=0.2, seed=42)

    def test_event_sft_skips_rows_without_source_text(self) -> None:
        record = _sample_cir_record()
        record.pop("source_variant_text", None)
        record.pop("original_description", None)
        record.pop("internal_metadata", None)
        output = build_v9_event_sft_rows([record])
        self.assertEqual(output, [])

    def test_corruption_builder_returns_patch(self) -> None:
        record = _sample_cir_record()
        slot_catalog = cir_to_v9_slot_catalog(record)
        event_table = cir_to_v9_event_table(record, slot_catalog)
        corrupted_pair = _make_corrupted_event_table(event_table, corruption_seed="seed_a")
        self.assertIsNotNone(corrupted_pair)
        corrupted, patch = corrupted_pair or ({}, {})
        self.assertIn("rows", corrupted)
        self.assertTrue(isinstance(patch.get("ops"), list) and len(patch["ops"]) > 0)

    def test_eval_artifacts_reject_duplicate_prediction_ids(self) -> None:
        eval_cases = [{"eval_case_id": "case_1", "source_text": "text"}]
        predictions = [
            {"eval_case_id": "case_1", "predicted_slot_catalog": {}, "predicted_event_table": {}},
            {"eval_case_id": "case_1", "predicted_slot_catalog": {}, "predicted_event_table": {}},
        ]
        with self.assertRaises(ValueError):
            build_v9_eval_artifacts(eval_case_rows=eval_cases, prediction_rows=predictions)

    def test_eval_summary_separates_structural_semantic_and_degradation(self) -> None:
        eval_case = {
            "eval_case_id": "case_1",
            "sample_id": "sample_1",
            "eval_set": "test",
            "source_text": "первый актер подходит ко второму",
            "gold_slot_catalog": {
                "actorSlots": [{"slotId": "actor_1"}, {"slotId": "actor_2"}],
                "objectSlots": [],
                "beatSlots": [{"slotId": "beat_1"}],
                "actionTypes": ["walk", "stand", "approach"],
            },
            "gold_event_table": {
                "rows": [
                    {
                        "rowId": "row_1",
                        "beatSlot": "beat_1",
                        "actorSlot": "actor_1",
                        "actionType": "approach",
                        "targetSlot": "actor_2",
                    }
                ]
            },
        }
        prediction = {
            "eval_case_id": "case_1",
            "predicted_slot_catalog": {
                "actorSlots": [{"slotId": "actor_1"}, {"slotId": "actor_2"}],
                "objectSlots": [],
                "beatSlots": [{"slotId": "beat_1"}],
                "actionTypes": ["walk", "stand", "approach"],
            },
            "predicted_event_table": {
                "rows": [
                    {
                        "rowId": "row_1",
                        "beatSlot": "beat_1",
                        "actorSlot": "actor_1",
                        "actionType": "approach",
                    }
                ]
            },
            "slice_reason_codes": [],
        }
        event_rows, _ = build_v9_eval_artifacts(eval_case_rows=[eval_case], prediction_rows=[prediction])
        self.assertEqual(len(event_rows), 1)
        row = event_rows[0]
        self.assertTrue(row["targetless_event_repaired"])
        self.assertEqual(row["input_event_row_count"], 1)
        self.assertEqual(row["dropped_event_row_count"], 0)
        self.assertEqual(row["semantic_row_total"], 1)
        self.assertEqual(row["semantic_actor_hit_count"], 1)
        self.assertEqual(row["semantic_target_hit_count"], 0)

        summary = summarize_event_slice_metrics(event_rows)
        self.assertIn("structural", summary)
        self.assertIn("semantic", summary)
        self.assertIn("degradation", summary)
        self.assertIn("event_actor_slot_structural_pass_rate", summary["structural"])
        self.assertIn("event_actor_slot_accuracy", summary["semantic"])
        self.assertEqual(summary["degradation"]["targetless_event_repaired_rate"], 1.0)

    def test_eval_summary_is_null_safe_without_gold(self) -> None:
        rows = [
            {
                "event_parse_ok": True,
                "event_schema_valid": True,
                "event_actor_slot_structural_pass": True,
                "event_target_slot_structural_pass": True,
                "event_action_type_structural_pass": True,
                "event_beat_order_structural_pass": True,
                "patch_success": False,
                "compiler_repair_applied": False,
                "semantic_row_total": 0,
                "semantic_actor_hit_count": 0,
                "semantic_target_hit_count": 0,
                "semantic_action_hit_count": 0,
                "semantic_beat_hit_count": 0,
                "targetless_event_repaired": False,
                "unknown_slot_blocked": False,
                "input_event_row_count": 0,
                "dropped_event_row_count": 0,
            }
        ]
        summary = summarize_event_slice_metrics(rows)
        self.assertIsNone(summary["semantic"]["event_actor_slot_accuracy"])
        self.assertIsNone(summary["semantic"]["event_target_slot_accuracy"])
        self.assertEqual(summary["structural"]["event_parse_rate"], 1.0)

    def test_eval_artifacts_derive_semantic_gold_from_scene_script(self) -> None:
        eval_case = {
            "eval_case_id": "case_1",
            "sample_id": "sample_1",
            "source_text": "Егор идет к Максу.",
            "gold_target_json": {
                "actors": [
                    {"id": "actor_1", "name": "Егор", "type": "human"},
                    {"id": "actor_2", "name": "Макс", "type": "human"},
                ],
                "objects": [],
                "beats": [
                    {
                        "id": "beat_1",
                        "actions": [
                            {
                                "id": "action_1",
                                "actorId": "actor_1",
                                "type": "walk",
                                "target": "actor_2",
                            }
                        ],
                    }
                ],
                "spatialRelations": [],
            },
        }
        prediction = {
            "eval_case_id": "case_1",
            "predicted_slot_catalog": {
                "actorSlots": [
                    {"slotId": "actor_slot_1", "ref": "first", "type": "human"},
                    {"slotId": "actor_slot_2", "ref": "second", "type": "human"},
                ],
                "objectSlots": [],
                "beatSlots": [{"slotId": "beat_slot_1", "beatRef": "beat_1"}],
                "actionTypes": ["stand", "walk"],
            },
            "predicted_event_table": {
                "contractVersion": "sg_v9_event_table_v1",
                "rows": [
                    {
                        "rowId": "row_1",
                        "beatSlot": "beat_slot_1",
                        "actorSlot": "actor_slot_1",
                        "actionType": "walk",
                        "targetSlot": "actor_slot_2",
                    }
                ],
            },
        }
        event_rows, _ = build_v9_eval_artifacts(eval_case_rows=[eval_case], prediction_rows=[prediction])
        self.assertEqual(event_rows[0]["semantic_row_total"], 1)
        self.assertEqual(event_rows[0]["semantic_actor_hit_count"], 1)
        self.assertEqual(event_rows[0]["semantic_target_hit_count"], 1)
        self.assertEqual(event_rows[0]["semantic_action_hit_count"], 1)
        self.assertEqual(event_rows[0]["semantic_beat_hit_count"], 1)

    def test_semantic_target_compare_resolves_marked_object_identity(self) -> None:
        eval_case = {
            "eval_case_id": "case_1",
            "sample_id": "sample_1",
            "source_text": "Первый идет к правому объекту.",
            "gold_target_json": {
                "actors": [{"id": "actor_1", "type": "human"}],
                "objects": [
                    {"id": "object_marked_right", "type": "generic", "relativePosition": "right"},
                    {"id": "object_marked_left", "type": "generic", "relativePosition": "left"},
                ],
                "beats": [
                    {
                        "id": "beat_1",
                        "actions": [
                            {"id": "action_1", "actorId": "actor_1", "type": "approach", "target": "object_marked_right"}
                        ],
                    }
                ],
                "spatialRelations": [],
            },
        }
        prediction = {
            "eval_case_id": "case_1",
            "predicted_slot_catalog": {
                "actorSlots": [{"slotId": "actor_slot_1", "ref": "first", "type": "human"}],
                "objectSlots": [
                    {
                        "slotId": "object_slot_1",
                        "ref": "object_marked_left",
                        "markedObjectID": "object_marked_left",
                    },
                    {
                        "slotId": "object_slot_2",
                        "ref": "object_marked_right",
                        "markedObjectID": "object_marked_right",
                    },
                ],
                "beatSlots": [{"slotId": "beat_slot_1", "beatRef": "beat_1"}],
                "actionTypes": ["approach", "stand"],
            },
            "predicted_event_table": {
                "contractVersion": "sg_v9_event_table_v1",
                "rows": [
                    {
                        "rowId": "row_1",
                        "beatSlot": "beat_slot_1",
                        "actorSlot": "actor_slot_1",
                        "actionType": "approach",
                        "targetSlot": "object_slot_2",
                    }
                ],
            },
        }
        event_rows, _ = build_v9_eval_artifacts(eval_case_rows=[eval_case], prediction_rows=[prediction])
        self.assertEqual(event_rows[0]["semantic_target_hit_count"], 1)


if __name__ == "__main__":
    unittest.main()
