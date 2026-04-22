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
from v8.compiler import compile_scene_plan_ir
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


if __name__ == "__main__":
    unittest.main()
