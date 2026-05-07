from __future__ import annotations

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from v8.eval_artifacts import build_v8_eval_artifacts


def _gold_script() -> dict:
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
        "objects": [],
        "spatialRelations": [],
        "originalDescription": "Егор: Я уже отправил архив. Макс: Тогда посмотри архив.",
    }


def _plan_ir() -> dict:
    return {
        "actors": [
            {"ref": "first", "type": "human", "name": "Егор"},
            {"ref": "second", "type": "human", "name": "Макс"},
        ],
        "objects": [],
        "beats": [
            {
                "ref": "beat_1",
                "actions": [
                    {
                        "actorRef": "first",
                        "type": "talk",
                        "targetRef": "second",
                        "resultingPose": "standing",
                        "dialogue": "Я уже отправил архив.",
                    },
                    {
                        "actorRef": "second",
                        "type": "talk",
                        "targetRef": "first",
                        "resultingPose": "standing",
                        "dialogue": "Тогда посмотри архив.",
                    },
                ],
            }
        ],
        "spatialRelations": [],
        "referenceBindings": {
            "actorBindings": {"first": "actor_1", "second": "actor_2"},
            "markedObjectIDs": [],
            "aliasToObjectRef": {},
        },
    }


class V8EvalArtifactsTests(unittest.TestCase):
    def test_build_v8_eval_artifacts_compiles_predictions(self) -> None:
        eval_cases = [
            {
                "eval_case_id": "case-1",
                "sample_id": "dialogue_only__base__s1__hash1",
                "eval_set": "synthetic_heldout",
                "source_text": "Егор: Я уже отправил архив. Макс: Тогда посмотри архив.",
                "gold_target_json": _gold_script(),
                "marked_objects": [],
                "eval_expectations": {
                    "expected_ordinal_bindings": {"first": "actor_1", "second": "actor_2"},
                },
            }
        ]
        predictions = [
            {
                "eval_case_id": "case-1",
                "predicted_plan_ir": _plan_ir(),
            }
        ]
        plan_rows, compiled_rows = build_v8_eval_artifacts(eval_case_rows=eval_cases, prediction_rows=predictions)
        self.assertEqual(len(plan_rows), 1)
        self.assertTrue(plan_rows[0]["plan_parse_ok"])
        self.assertTrue(plan_rows[0]["plan_reference_binding_pass"])
        self.assertTrue(plan_rows[0]["plan_beat_integrity_pass"])
        self.assertTrue(plan_rows[0]["plan_compile_ok"])
        self.assertIsInstance(compiled_rows[0]["predicted_script"], dict)
        self.assertIsInstance(compiled_rows[0]["model_only_predicted_script"], dict)
        self.assertIsInstance(compiled_rows[0]["end_to_end_predicted_script"], dict)

    def test_build_v8_eval_artifacts_propagates_compile_notes_to_reason_codes(self) -> None:
        eval_cases = [
            {
                "eval_case_id": "case-2",
                "sample_id": "s2",
                "eval_set": "synthetic_heldout",
                "source_text": "Человек подходит.",
                "gold_target_json": _gold_script(),
                "marked_objects": [],
                "eval_expectations": {"expected_ordinal_bindings": {"first": "actor_1"}},
            }
        ]
        predictions = [
            {
                "eval_case_id": "case-2",
                "predicted_plan_ir": {
                    "actors": [{"ref": "first", "type": "human"}],
                    "objects": [],
                    "beats": [{"ref": "beat_1", "actions": [{"actorRef": "first", "type": "approach"}]}],
                    "spatialRelations": [],
                    "referenceBindings": {"actorBindings": {"first": "actor_1"}, "markedObjectIDs": []},
                },
                "slice_reason_codes": ["legacy_input_reason"],
            }
        ]
        plan_rows, compiled_rows = build_v8_eval_artifacts(eval_case_rows=eval_cases, prediction_rows=predictions)
        self.assertEqual(len(plan_rows), 1)
        self.assertTrue(plan_rows[0]["plan_compile_ok"])
        self.assertIn("v8.targetless_action_downgraded", plan_rows[0]["compile_notes"])
        self.assertIn("legacy_input_reason", compiled_rows[0]["slice_reason_codes"])
        self.assertIn("v8.targetless_action_downgraded", compiled_rows[0]["slice_reason_codes"])


if __name__ == "__main__":
    unittest.main()
