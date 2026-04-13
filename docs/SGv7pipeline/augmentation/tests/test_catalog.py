from __future__ import annotations

import unittest

from augmentation.catalog import default_max_augmented_variants_per_parent


class TestCatalog(unittest.TestCase):
    def test_bucket_defaults_match_design(self) -> None:
        self.assertEqual(default_max_augmented_variants_per_parent("core", enable_risky=False), 1)
        self.assertEqual(default_max_augmented_variants_per_parent("hard", enable_risky=False), 2)
        self.assertEqual(default_max_augmented_variants_per_parent("hard", enable_risky=True), 3)
