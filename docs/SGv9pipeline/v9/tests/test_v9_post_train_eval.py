from __future__ import annotations

import argparse
import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "13_run_v9_3_post_train_eval.py"


def load_module():
    spec = importlib.util.spec_from_file_location("run_v9_3_post_train_eval", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load module: {MODULE_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TestV93PostTrainEvalGate(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mod = load_module()

    def args(self) -> argparse.Namespace:
        return argparse.Namespace(
            min_case_strict_success=0.65,
            min_target_resolution=0.99,
            min_chronology_phase=0.985,
            min_action_recall=0.99,
            max_runtime_fallback=0.25,
        )

    def test_acceptance_passes_when_all_goal_thresholds_are_met(self) -> None:
        metrics = {
            "case_strict_success_rate": 0.99,
            "target_resolution_accuracy": 0.991,
            "chronology_phase_accuracy": 0.986,
            "action_recall": 0.995,
            "runtime_fallback_rate": 0.02,
        }

        result = self.mod.evaluate_acceptance(metrics, self.args())

        self.assertTrue(result["pass"])
        self.assertTrue(all(row["pass"] for row in result["checks"]))

    def test_acceptance_fails_for_target_chronology_action_or_fallback_regression(self) -> None:
        metrics = {
            "case_strict_success_rate": 0.97,
            "target_resolution_accuracy": 0.981,
            "chronology_phase_accuracy": 0.969,
            "action_recall": 0.984,
            "runtime_fallback_rate": 0.42,
        }

        result = self.mod.evaluate_acceptance(metrics, self.args())

        self.assertFalse(result["pass"])
        failed = {row["metric"] for row in result["checks"] if not row["pass"]}
        self.assertEqual(
            failed,
            {
                "target_resolution_accuracy",
                "chronology_phase_accuracy",
                "action_recall",
                "runtime_fallback_rate",
            },
        )

    def test_acceptance_fails_closed_when_metric_is_missing(self) -> None:
        result = self.mod.evaluate_acceptance({}, self.args())

        self.assertFalse(result["pass"])
        self.assertTrue(all(row["value"] is None for row in result["checks"]))


if __name__ == "__main__":
    unittest.main()
