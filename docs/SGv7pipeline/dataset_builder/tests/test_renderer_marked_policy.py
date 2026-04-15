from __future__ import annotations

from pathlib import Path
import re
import sys
import unittest

DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from dataset_builder.renderer import _format_marked_objects


class TestRendererMarkedPolicy(unittest.TestCase):
    def test_no_marked_objects_uses_v2_none_marker(self) -> None:
        cir_record = {
            "scene_graph": {
                "objects": [
                    {
                        "id": "object_1",
                        "type": "generic",
                        "name": "стол",
                        "marker_binding": {"kind": "unmarked"},
                    }
                ]
            }
        }
        self.assertEqual(_format_marked_objects(cir_record), "- none")

    def test_collision_resolution_keeps_unique_marked_ids(self) -> None:
        cir_record = {
            "scene_graph": {
                "objects": [
                    {
                        "id": "object_marked_DEADBEEF",
                        "type": "chair",
                        "name": "Левый стул",
                        "marker_binding": {"kind": "marked", "source_marker_ordinal": 1},
                    },
                    {
                        "id": "object_marked_DEADBEEF",
                        "type": "chair",
                        "name": "Правый стул",
                        "marker_binding": {"kind": "marked", "source_marker_ordinal": 2},
                    },
                ]
            }
        }

        rendered = _format_marked_objects(cir_record)
        lines = [line for line in rendered.splitlines() if line.startswith("- id=")]
        ids = [re.search(r"id=([^;]+);", line).group(1) for line in lines]  # type: ignore[union-attr]

        self.assertEqual(len(ids), 2)
        self.assertEqual(len(set(ids)), 2)
        self.assertIn("object_marked_deadbeef", ids)
        for line in lines:
            self.assertIn("; aliases=-", line)


if __name__ == "__main__":
    unittest.main()
