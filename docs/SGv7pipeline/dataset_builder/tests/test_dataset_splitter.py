from __future__ import annotations

from pathlib import Path
import sys
import unittest

DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from dataset_builder.splitter import split_preference_records, split_sft_records


def _sft_row(sample_id: str, family_id: str, *, difficulty_bucket: str = "hard") -> dict[str, object]:
    return {
        "sample_id": sample_id,
        "task_type": "sft",
        "messages": [],
        "target_json": {},
        "critical_eval_tags": [],
        "source_text": sample_id,
        "packaging_metadata": {
            "split": "",
            "task_type": "sft",
            "contract_version": "sg_v7_contract_v1",
            "sample_id": sample_id,
            "graph_hash": sample_id,
            "graph_family_key": family_id,
            "normalized_source_hash": f"nsh_{sample_id}",
            "difficulty_bucket": difficulty_bucket,
            "split_family_id": family_id,
            "correction_tier": "tier_b_deterministic_canonical",
            "source_text_token_count": 1,
            "train_eligibility": "direct_sft",
        },
    }


def _pref_row(pref_id: str, family_id: str) -> dict[str, object]:
    return {
        "preference_id": pref_id,
        "task_type": "preference",
        "messages": [],
        "chosen": "{}",
        "rejected": "{\"a\":1}",
        "chosen_json": {},
        "rejected_json": {"a": 1},
        "source_text": pref_id,
        "packaging_metadata": {
            "split": "",
            "task_type": "preference",
            "contract_version": "sg_v7_contract_v1",
            "preference_id": pref_id,
            "preference_origin": "runtime_failure_reviewed_merge",
            "correction_tier": "tier_c_reviewed_merge",
            "difficulty_bucket": "hard",
            "graph_family_key": family_id,
            "normalized_source_hash": f"nsh_{pref_id}",
            "split_family_id": family_id,
            "family_resolution_proof": {
                "input_anchor_type": "sample_id",
                "input_anchor_value": pref_id,
                "resolution_method": "deterministic_cir_join_v1:sample_id",
                "resolved_graph_family_key": family_id,
                "proof_status": "resolved",
            },
        },
    }


class TestDatasetSplitter(unittest.TestCase):
    def test_same_split_family_id_always_in_one_split(self) -> None:
        records = [
            _sft_row("s1", "gfk_A"),
            _sft_row("s2", "gfk_A"),
            _sft_row("s3", "gfk_B"),
        ]
        splits, _ = split_sft_records(records, ratios=(0.84, 0.08, 0.08))
        family_split = {}
        for split, rows in splits.items():
            for row in rows:
                family = row["packaging_metadata"]["split_family_id"]
                family_split.setdefault(family, split)
                self.assertEqual(family_split[family], split)

    def test_preference_test_non_empty_when_families_at_least_three(self) -> None:
        records = [
            _pref_row("p1", "gfk_1"),
            _pref_row("p2", "gfk_2"),
            _pref_row("p3", "gfk_3"),
        ]
        splits, _, coverage = split_preference_records(records, ratios=(0.85, 0.10, 0.05))
        self.assertEqual(coverage, "ok")
        self.assertGreaterEqual(len(splits["test"]), 1)

    def test_preference_test_undersized_status_for_small_corpus(self) -> None:
        records = [_pref_row("p1", "gfk_1"), _pref_row("p2", "gfk_2")]
        splits, _, coverage = split_preference_records(records, ratios=(0.85, 0.10, 0.05))
        self.assertEqual(coverage, "undersized_preference_corpus")
        self.assertIn("test", splits)
        self.assertGreaterEqual(len(splits["test"]), 1)

    def test_sft_split_keeps_core_and_hard_in_heldout_when_coverage_allows(self) -> None:
        records: list[dict[str, object]] = []
        for idx in range(1, 13):
            records.append(_sft_row(f"core_{idx}", f"core_family_{idx}", difficulty_bucket="core"))
            records.append(_sft_row(f"hard_{idx}", f"hard_family_{idx}", difficulty_bucket="hard"))

        splits, _ = split_sft_records(records, ratios=(0.84, 0.08, 0.08))
        for heldout_split in ("val", "test"):
            buckets = {
                str(row["packaging_metadata"].get("difficulty_bucket", ""))
                for row in splits[heldout_split]
            }
            self.assertIn("core", buckets)
            self.assertIn("hard", buckets)
