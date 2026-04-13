from __future__ import annotations

import unittest

from augmentation.noise import apply_noise_transform


class TestNoise(unittest.TestCase):
    def test_drop_final_punctuation(self) -> None:
        result = apply_noise_transform("Первый идет к компу.", "noise.drop_final_punctuation")
        self.assertIsNotNone(result)
        updated, _ = result or ("", {})
        self.assertEqual(updated, "Первый идет к компу")

    def test_double_space_preserves_words(self) -> None:
        result = apply_noise_transform("Первый идет к компу", "noise.double_space")
        self.assertIsNotNone(result)
        updated, _ = result or ("", {})
        self.assertIn("  ", updated)
