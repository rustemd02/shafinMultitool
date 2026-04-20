from __future__ import annotations

import importlib.util
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
MODULE_PATH = ROOT / "experiments" / "sc_benchmark" / "generate_predictions_from_endpoint.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("generate_predictions_from_endpoint", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load module: {MODULE_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TestPredictionExportHelpers(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mod = _load_module()

    def test_think_and_markdown_are_removed_before_parse(self) -> None:
        payload = {"actors": [], "objects": [], "beats": [], "spatialRelations": [], "originalDescription": "ok"}
        text = "<think>draft</think>\n```json\n" + json.dumps(payload, ensure_ascii=False) + "\n```"
        parsed = self.mod._first_json_object(text, strip_think_tags=True)
        self.assertEqual(parsed, payload)

    def test_legacy_beats_are_canonicalized(self) -> None:
        script = {
            "actors": [{"id": "actor_1"}],
            "objects": [{"id": "object_1"}],
            "beats": [
                {
                    "id": "beat_1",
                    "type": "pick_up",
                    "actorId": "actor_1",
                    "target": "object_1",
                }
            ],
            "spatialRelations": [],
            "originalDescription": "x",
        }
        repaired, changed = self.mod._canonicalize_legacy_beats(script)
        self.assertTrue(changed)
        self.assertIn("actions", repaired["beats"][0])
        self.assertEqual(repaired["beats"][0]["actions"][0]["type"], "pick_up")
        self.assertEqual(repaired["beats"][0]["actions"][0]["target"], "object_1")

    def test_schema_validation_fails_for_unknown_target(self) -> None:
        script = {
            "actors": [{"id": "actor_1"}],
            "objects": [{"id": "object_1"}],
            "beats": [
                {
                    "id": "beat_1",
                    "actions": [{"id": "a1", "actorId": "actor_1", "type": "approach", "target": "object_404"}],
                }
            ],
            "spatialRelations": [],
            "originalDescription": "x",
        }
        self.assertFalse(self.mod._schema_valid(script))

    def test_detects_actions_empty(self) -> None:
        script = {
            "actors": [{"id": "actor_1"}],
            "objects": [],
            "beats": [{"id": "beat_1", "actions": []}],
            "spatialRelations": [],
            "originalDescription": "x",
        }
        self.assertTrue(self.mod._has_pred_actions_empty(script))


if __name__ == "__main__":
    unittest.main()

