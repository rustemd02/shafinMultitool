from __future__ import annotations

import unittest
from pathlib import Path
import sys

DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from source_generation.style_policy import planned_style_buckets


class TestStylePolicy(unittest.TestCase):
    def test_track4_only_uses_three_base_buckets(self) -> None:
        self.assertEqual(planned_style_buckets(), ["clean", "colloquial", "user_short"])
        self.assertEqual(planned_style_buckets(max_variants_per_graph=2), ["clean", "colloquial"])

