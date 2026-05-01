from __future__ import annotations

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from v9.projection import cir_to_v9_event_table, cir_to_v9_slot_catalog
from v9.verifier import verify_and_repair_event_table


def _sample_record() -> dict:
    return {
        "scene_graph": {
            "actors": [
                {"id": "actor_1", "type": "human", "labels": {"ordinal": "first"}},
                {"id": "actor_2", "type": "human", "labels": {"ordinal": "second"}},
            ],
            "objects": [
                {"id": "object_marked_abcd1234", "type": "generic", "relative_position": "center", "name": "компьютер"},
            ],
            "beats": [
                {
                    "id": "beat_1",
                    "phase": "toward_each_other",
                    "actions": [
                        {"actor_id": "actor_1", "type": "walk", "target_id": "actor_2"},
                        {"actor_id": "actor_2", "type": "walk", "target_id": "actor_1"},
                    ],
                },
                {
                    "id": "beat_2",
                    "phase": "stop_near_object",
                    "actions": [
                        {"actor_id": "actor_1", "type": "stop", "target_id": "object_marked_abcd1234"},
                    ],
                },
            ],
            "spatial_relations": [],
        }
    }


class V9ProjectionTests(unittest.TestCase):
    def test_slot_catalog_and_event_projection(self) -> None:
        record = _sample_record()
        slot_catalog = cir_to_v9_slot_catalog(record)
        event_table = cir_to_v9_event_table(record, slot_catalog)

        self.assertEqual(slot_catalog["contractVersion"], "sg_v9_slot_catalog_v1")
        self.assertEqual(event_table["contractVersion"], "sg_v9_event_table_v1")
        self.assertEqual(len(slot_catalog["actorSlots"]), 2)
        self.assertEqual(len(slot_catalog["objectSlots"]), 1)
        self.assertEqual(len(slot_catalog["beatSlots"]), 2)
        self.assertEqual(len(event_table["rows"]), 3)

    def test_verifier_repairs_missing_target(self) -> None:
        record = _sample_record()
        slot_catalog = cir_to_v9_slot_catalog(record)
        event_table = cir_to_v9_event_table(record, slot_catalog)
        event_table["rows"][-1].pop("targetSlot", None)

        repaired, issues, reason_codes = verify_and_repair_event_table(slot_catalog, event_table)
        self.assertTrue(any(issue["code"] == "target_required_missing" for issue in issues))
        self.assertIn("v9.targetless_event_repaired", reason_codes)
        self.assertEqual(repaired["rows"][-1]["actionType"], "stand")


if __name__ == "__main__":
    unittest.main()
