from __future__ import annotations

import unittest
from pathlib import Path
import sys

DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from validators.provenance import evaluate_provenance, train_eligibility_for


class TestProvenance(unittest.TestCase):
    def test_unknown_tier_is_rejected(self) -> None:
        tier, reject_reasons, review_reasons = evaluate_provenance({"correction_tier": "tier_x"})
        self.assertEqual(tier, "tier_x")
        self.assertIn("provenance_unknown_tier", reject_reasons)
        self.assertEqual(review_reasons, [])

    def test_synthetic_generation_materializes_tier_b(self) -> None:
        tier, reject_reasons, review_reasons = evaluate_provenance({"generation_pass": "base_paraphrase"})
        self.assertEqual(tier, "tier_b_deterministic_canonical")
        self.assertEqual(reject_reasons, [])
        self.assertEqual(review_reasons, [])

    def test_train_eligibility_mapping(self) -> None:
        self.assertEqual(train_eligibility_for("accepted", "tier_b_deterministic_canonical"), "direct_sft")
        self.assertEqual(train_eligibility_for("manual_review", "tier_c_reviewed_merge"), "review_only")
        self.assertEqual(train_eligibility_for("rejected", "tier_a_human_gold"), "reject_only")
