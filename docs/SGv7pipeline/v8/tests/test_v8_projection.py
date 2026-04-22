from __future__ import annotations

import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
EXAMPLES = ROOT / "cir_contract" / "contracts" / "examples"
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from cir_contract.contracts.cir_serializer import serialize_to_scenescript
from v8.compiler import (
    INVALID_SPATIAL_RELATION_SKIPPED_NOTE,
    TARGETLESS_ACTION_DOWNGRADED_NOTE,
    compile_scene_plan_ir,
    compile_scene_plan_ir_with_notes,
)
from v8.eval import summarize_plan_slice_metrics
from v8.projection import cir_to_scene_plan_ir


def _load(name: str) -> dict:
    return json.loads((EXAMPLES / name).read_text(encoding="utf-8"))


def _normalize(payload: dict) -> dict:
    normalized = dict(payload)
    normalized["beats"] = [
        {
            "actions": [
                {k: v for k, v in action.items() if k != "id"}
                for action in beat.get("actions", [])
            ]
        }
        for beat in payload.get("beats", [])
    ]
    return normalized


class V8ProjectionTests(unittest.TestCase):
    def test_projection_preserves_marked_ids(self) -> None:
        record = _load("ex3_same_type_two_marked_objects.json")
        plan = cir_to_scene_plan_ir(record)
        self.assertEqual(plan["objects"][0]["ref"], "object_marked_1111aaaa")
        self.assertEqual(plan["objects"][1]["ref"], "object_marked_2222bbbb")
        self.assertEqual(plan["referenceBindings"]["markedObjectIDs"], [
            "object_marked_1111aaaa",
            "object_marked_2222bbbb",
        ])

    def test_compile_projected_plan_matches_runtime_shape(self) -> None:
        record = _load("ex2_pass_by_object_then_second_runs.json")
        plan = cir_to_scene_plan_ir(record)
        compiled = compile_scene_plan_ir(plan, original_description="demo")
        expected = serialize_to_scenescript(record, original_description="demo")
        self.assertEqual(_normalize(compiled), _normalize(expected))

    def test_plan_slice_metrics(self) -> None:
        rows = [
            {"plan_parse_ok": True, "plan_reference_binding_pass": True, "plan_beat_integrity_pass": False},
            {"plan_parse_ok": False, "plan_reference_binding_pass": True, "plan_beat_integrity_pass": True},
        ]
        metrics = summarize_plan_slice_metrics(rows)
        self.assertEqual(metrics["plan_parse_rate"], 0.5)
        self.assertEqual(metrics["plan_reference_binding_accuracy"], 1.0)
        self.assertEqual(metrics["plan_beat_integrity_accuracy"], 0.5)

    def test_compile_downgrades_required_targetless_actions(self) -> None:
        plan = {
            "actors": [{"ref": "first", "type": "human"}],
            "objects": [],
            "beats": [
                {
                    "ref": "beat_1",
                    "actions": [
                        {
                            "actorRef": "first",
                            "type": "approach",
                            # targetRef intentionally missing
                        }
                    ],
                }
            ],
            "spatialRelations": [],
            "referenceBindings": {"actorBindings": {"first": "actor_1"}, "markedObjectIDs": []},
        }
        compiled, notes = compile_scene_plan_ir_with_notes(plan, original_description="demo")
        action = compiled["beats"][0]["actions"][0]
        self.assertEqual(action["type"], "stand")
        self.assertNotIn("target", action)
        self.assertIn(TARGETLESS_ACTION_DOWNGRADED_NOTE, notes)

    def test_compile_skips_invalid_spatial_relations(self) -> None:
        plan = {
            "actors": [{"ref": "first", "type": "human"}],
            "objects": [{"ref": "object_slot_1", "type": "table", "relativePosition": "center"}],
            "beats": [
                {
                    "ref": "beat_1",
                    "actions": [
                        {
                            "actorRef": "first",
                            "type": "stand",
                        }
                    ],
                }
            ],
            "spatialRelations": [
                {
                    "ref": "rel_1",
                    "subjectRef": "object_slot_1",
                    "relation": "inside",
                    "objectRef": "holding_object_1",
                }
            ],
            "referenceBindings": {"actorBindings": {"first": "actor_1"}, "markedObjectIDs": []},
        }
        compiled, notes = compile_scene_plan_ir_with_notes(plan, original_description="demo")
        self.assertEqual(compiled["spatialRelations"], [])
        self.assertIn(INVALID_SPATIAL_RELATION_SKIPPED_NOTE, notes)


if __name__ == "__main__":
    unittest.main()
