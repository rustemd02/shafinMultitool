from __future__ import annotations

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
EXAMPLES = ROOT / "cir_contract" / "contracts" / "examples"
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from v8.datasets import (
    build_critic_rank_rows,
    build_plan_preference_rows,
    build_plan_sft_rows,
    build_subtask_sft_rows,
)


def _load(name: str) -> dict:
    return json.loads((EXAMPLES / name).read_text(encoding="utf-8"))


def _simple_gold_script() -> dict:
    return {
        "actors": [
            {"id": "actor_1", "type": "human", "name": "Егор"},
            {"id": "actor_2", "type": "human", "name": "Макс"},
        ],
        "objects": [],
        "beats": [
            {
                "id": "beat_1",
                "actions": [
                    {
                        "id": "action_1",
                        "actorId": "actor_1",
                        "type": "talk",
                        "target": "actor_2",
                        "resultingPose": "standing",
                        "dialogue": "Я уже отправил архив.",
                    },
                    {
                        "id": "action_2",
                        "actorId": "actor_2",
                        "type": "talk",
                        "target": "actor_1",
                        "resultingPose": "standing",
                        "dialogue": "Тогда посмотри архив.",
                    },
                ],
            }
        ],
        "spatialRelations": [],
        "originalDescription": "Егор: Я уже отправил архив. Макс: Тогда посмотри архив.",
    }


class V8DatasetBuilderTests(unittest.TestCase):
    def test_plan_sft_rows_keep_compatible_envelope(self) -> None:
        rows = build_plan_sft_rows([_load("ex2_pass_by_object_then_second_runs.json")])
        self.assertEqual(len(rows), 1)
        row = rows[0]
        self.assertEqual(row["task_type"], "sft")
        self.assertIn("target_plan_ir", row)
        self.assertIn("compiled_target_json", row)
        self.assertEqual(row["messages"][0]["role"], "system")
        self.assertEqual(row["messages"][1]["role"], "user")
        self.assertEqual(row["messages"][2]["role"], "assistant")
        self.assertEqual(row["packaging_metadata"]["v8_task_type"], "plan_sft")
        self.assertEqual(row["packaging_metadata"]["training_target"], "scene_plan_ir")

    def test_subtask_rows_cover_expected_task_types(self) -> None:
        rows = build_subtask_sft_rows([_load("ex3_same_type_two_marked_objects.json")])
        task_types = {row["subtask_type"] for row in rows}
        self.assertEqual(
            task_types,
            {"anchor_extraction", "beat_plan", "target_linking", "ordinal_linking"},
        )
        anchor_row = next(row for row in rows if row["subtask_type"] == "anchor_extraction")
        self.assertTrue(anchor_row["target_json"]["same_type_marker_conflict"])
        self.assertEqual(anchor_row["packaging_metadata"]["v8_task_type"], "subtask_sft")

    def test_plan_preference_rows_use_model_only_predictions(self) -> None:
        eval_case_rows = [
            {
                "eval_case_id": "case-1",
                "sample_id": "dialogue_only__base__s1__hash1",
                "source_text": "Егор: Я уже отправил архив. Макс: Тогда посмотри архив.",
                "difficulty_bucket": "core",
                "eval_set": "synthetic_heldout",
                "graph_family_key": "hash1",
                "gold_target_json": _simple_gold_script(),
                "marked_objects": [],
                "eval_expectations": {
                    "expected_ordinal_bindings": {"first": "actor_1", "second": "actor_2"},
                    "expected_phase_sequence": ["beat01_talk_01", "beat01_talk_02"],
                },
            }
        ]
        candidate_prediction_rows = [
            {
                "eval_case_id": "case-1",
                "model_only_predicted_script": _simple_gold_script(),
                "predicted_script": {
                    **_simple_gold_script(),
                    "beats": [
                        {
                            "id": "beat_1",
                            "actions": [
                                {
                                    "id": "action_1",
                                    "actorId": "actor_1",
                                    "type": "talk",
                                    "target": "actor_2",
                                    "resultingPose": "standing",
                                    "dialogue": "Я уже отправил архив.",
                                }
                            ],
                        }
                    ],
                },
            }
        ]
        baseline_prediction_rows = [
            {
                "eval_case_id": "case-1",
                "model_only_predicted_script": {
                    **_simple_gold_script(),
                    "beats": [
                        {
                            "id": "beat_1",
                            "actions": [
                                {
                                    "id": "action_1",
                                    "actorId": "actor_1",
                                    "type": "talk",
                                    "target": "actor_2",
                                    "resultingPose": "standing",
                                    "dialogue": "Я уже отправил архив.",
                                }
                            ],
                        }
                    ],
                },
            }
        ]
        candidate_case_rows = [
            {
                "eval_case_id": "case-1",
                "case_strict_success": True,
                "json_valid": True,
                "schema_valid": True,
                "metric_flags": {
                    "target_resolution_pass": True,
                    "chronology_phase_pass": True,
                    "action_recall_pass": True,
                    "ordinal_binding_pass": True,
                },
                "metric_values": {
                    "target_resolution_accuracy_case": 1.0,
                    "chronology_phase_accuracy_case": 1.0,
                    "action_recall_case": 1.0,
                },
            }
        ]
        baseline_case_rows = [
            {
                "eval_case_id": "case-1",
                "case_strict_success": False,
                "json_valid": True,
                "schema_valid": True,
                "metric_flags": {
                    "target_resolution_pass": False,
                    "chronology_phase_pass": False,
                    "action_recall_pass": False,
                    "ordinal_binding_pass": True,
                },
                "metric_values": {
                    "target_resolution_accuracy_case": 0.5,
                    "chronology_phase_accuracy_case": 0.0,
                    "action_recall_case": 0.5,
                },
            }
        ]
        paired_case_rows = [{"eval_case_id": "case-1", "winner": "candidate"}]

        rows = build_plan_preference_rows(
            eval_case_rows=eval_case_rows,
            candidate_prediction_rows=candidate_prediction_rows,
            baseline_prediction_rows=baseline_prediction_rows,
            candidate_case_rows=candidate_case_rows,
            baseline_case_rows=baseline_case_rows,
            candidate_model_id="iter2",
            baseline_model_id="v7",
            paired_case_rows=paired_case_rows,
        )
        self.assertEqual(len(rows), 1)
        row = rows[0]
        self.assertEqual(row["packaging_metadata"]["chosen_model_id"], "iter2")
        self.assertEqual(len(row["chosen_plan_ir"]["beats"][0]["actions"]), 2)
        self.assertEqual(len(row["rejected_plan_ir"]["beats"][0]["actions"]), 1)
        self.assertIn("winner_source=pairwise", row["packaging_metadata"]["preference_reason_codes"])

    def test_critic_rank_rows_capture_preferred_side(self) -> None:
        eval_case_rows = [
            {
                "eval_case_id": "case-1",
                "sample_id": "dialogue_only__base__s1__hash1",
                "source_text": "Егор: Я уже отправил архив. Макс: Тогда посмотри архив.",
                "difficulty_bucket": "core",
                "eval_set": "synthetic_heldout",
                "graph_family_key": "hash1",
                "gold_target_json": _simple_gold_script(),
                "marked_objects": [],
                "eval_expectations": {
                    "expected_ordinal_bindings": {"first": "actor_1", "second": "actor_2"},
                    "expected_phase_sequence": ["beat01_talk_01", "beat01_talk_02"],
                },
            }
        ]
        candidate_prediction_rows = [{"eval_case_id": "case-1", "model_only_predicted_script": _simple_gold_script()}]
        baseline_prediction_rows = [
            {
                "eval_case_id": "case-1",
                "model_only_predicted_script": {
                    **_simple_gold_script(),
                    "beats": [
                        {
                            "id": "beat_1",
                            "actions": [
                                {
                                    "id": "action_1",
                                    "actorId": "actor_1",
                                    "type": "talk",
                                    "target": "actor_2",
                                    "resultingPose": "standing",
                                    "dialogue": "Я уже отправил архив.",
                                }
                            ],
                        }
                    ],
                },
            }
        ]
        candidate_case_rows = [{"eval_case_id": "case-1", "case_strict_success": True, "json_valid": True, "schema_valid": True, "metric_flags": {}, "metric_values": {}}]
        baseline_case_rows = [{"eval_case_id": "case-1", "case_strict_success": False, "json_valid": True, "schema_valid": False, "metric_flags": {}, "metric_values": {}}]
        paired_case_rows = [{"eval_case_id": "case-1", "winner": "candidate"}]

        rows = build_critic_rank_rows(
            eval_case_rows=eval_case_rows,
            candidate_prediction_rows=candidate_prediction_rows,
            baseline_prediction_rows=baseline_prediction_rows,
            candidate_case_rows=candidate_case_rows,
            baseline_case_rows=baseline_case_rows,
            candidate_model_id="iter2",
            baseline_model_id="v7",
            paired_case_rows=paired_case_rows,
        )
        self.assertEqual(len(rows), 1)
        row = rows[0]
        self.assertEqual(row["preferred_side"], "candidate_a")
        self.assertEqual(row["packaging_metadata"]["v8_task_type"], "critic_rank")
        self.assertEqual(row["preferred_model_id"], "iter2")


if __name__ == "__main__":
    unittest.main()
