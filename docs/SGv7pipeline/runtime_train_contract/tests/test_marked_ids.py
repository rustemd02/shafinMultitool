from __future__ import annotations

from pathlib import Path
import sys
import unittest

DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from runtime_train_contract.marked_ids import MarkedIDPolicyError, resolve_marked_object_rows


class TestMarkedIDPolicy(unittest.TestCase):
    def test_uuid_shortid_is_lowercase(self) -> None:
        rows = [
            {
                "marker_uuid": "A0B1C2D3-0011-2233-4455-66778899AABB",
                "normalized_name": "ноутбук",
                "type": "generic",
                "source_marker_ordinal": 1,
            }
        ]
        resolved = resolve_marked_object_rows(rows)
        self.assertEqual(resolved[0]["resolved_id"], "object_marked_a0b1c2d3")

    def test_non_uuid_fallback_is_deterministic(self) -> None:
        rows = [
            {
                "normalized_name": "левый стул",
                "type": "chair",
                "source_marker_ordinal": 1,
            },
            {
                "normalized_name": "правый стул",
                "type": "chair",
                "source_marker_ordinal": 2,
            },
        ]
        first = resolve_marked_object_rows(rows)
        second = resolve_marked_object_rows(rows)
        self.assertEqual([row["resolved_id"] for row in first], [row["resolved_id"] for row in second])

    def test_collision_resolution_uses_rehash(self) -> None:
        rows = [
            {
                "existing_id": "object_marked_deadbeef",
                "normalized_name": "левый стул",
                "type": "chair",
                "source_marker_ordinal": 1,
            },
            {
                "existing_id": "object_marked_deadbeef",
                "normalized_name": "правый стул",
                "type": "chair",
                "source_marker_ordinal": 2,
            },
        ]
        resolved = resolve_marked_object_rows(rows)
        resolved_ids = [row["resolved_id"] for row in resolved]
        self.assertEqual(resolved_ids[0], "object_marked_deadbeef")
        self.assertNotEqual(resolved_ids[1], "object_marked_deadbeef")
        self.assertNotEqual(resolved_ids[0], resolved_ids[1])

    def test_unstable_order_without_ordinal_and_origin_fails(self) -> None:
        rows = [
            {
                "existing_id": "",
                "normalized_name": "стул",
                "type": "chair",
                "source_marker_ordinal": None,
                "marker_origin_key": None,
            }
        ]
        with self.assertRaises(MarkedIDPolicyError) as ctx:
            resolve_marked_object_rows(rows)
        self.assertEqual(str(ctx.exception), "marker_identity_order_unstable")


if __name__ == "__main__":
    unittest.main()
