from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
import sys

DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from pattern_library import generate_pattern_record

from dataset_builder.config import DatasetBuildRequest
from dataset_builder.ingest import build_cir_indices, normalized_source_hash_v1
from dataset_builder.preference import build_preference_pairs


def _write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")


def _request(tmp_path: Path) -> DatasetBuildRequest:
    return DatasetBuildRequest(
        accepted_jsonl=tmp_path / "accepted.jsonl",
        cir_jsonl=tmp_path / "cir.jsonl",
        output_dir=tmp_path / "out",
        seed=42,
        contract_version="sg_v7_contract_v1",
    )


class TestPreferenceBuilder(unittest.TestCase):
    def test_runtime_candidate_without_deterministic_join_is_quarantined(self) -> None:
        cir = generate_pattern_record("toward_each_other", graph_seed=11, source_variant_key="base")
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            _write_jsonl(tmp_path / "cir.jsonl", [cir])
            request = _request(tmp_path)
            cir_index = build_cir_indices(request.cir_jsonl, contract_version=request.contract_version)

            raw_candidates = [
                {
                    "failure_id": "rtf-001",
                    "source": "тест",
                    "raw_llm_output": {"actors": []},
                    "corrected_target_json": {"actors": [{"id": "actor_1"}]},
                    "correction_tier": "tier_c_reviewed_merge",
                    "contract_version": "sg_v7_contract_v1",
                    "family_anchor": {
                        "anchor_type": "runtime_failure_id",
                        "anchor_value": "rtf-001",
                    },
                }
            ]
            result = build_preference_pairs(
                request,
                raw_candidates=raw_candidates,
                cir_index=cir_index,
                heldout_sft_family_ids=set(),
            )
            self.assertFalse(result.splitable_records)
            self.assertEqual(len(result.quarantined_records), 1)
            self.assertEqual(result.quarantined_records[0]["reason"], "missing_deterministic_canonical_family_join")

    def test_resolved_runtime_pair_persists_family_proof_and_normalized_source_hash(self) -> None:
        cir = generate_pattern_record("toward_each_other", graph_seed=12, source_variant_key="base")
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            _write_jsonl(tmp_path / "cir.jsonl", [cir])
            request = _request(tmp_path)
            cir_index = build_cir_indices(request.cir_jsonl, contract_version=request.contract_version)
            raw_candidates = [
                {
                    "failure_id": "rtf-002",
                    "sample_id": cir["sample_id"],
                    "source": "2 актёра идут навстречу друг другу.",
                    "raw_llm_output": {"actors": []},
                    "corrected_target_json": {"actors": [{"id": "actor_1"}]},
                    "correction_tier": "tier_c_reviewed_merge",
                    "contract_version": "sg_v7_contract_v1",
                }
            ]
            result = build_preference_pairs(
                request,
                raw_candidates=raw_candidates,
                cir_index=cir_index,
                heldout_sft_family_ids=set(),
            )
            self.assertEqual(len(result.splitable_records), 1)
            metadata = result.splitable_records[0]["packaging_metadata"]
            self.assertTrue(str(metadata["normalized_source_hash"]).startswith("nsh_"))
            self.assertEqual(metadata["family_resolution_proof"]["proof_status"], "resolved")
            self.assertEqual(metadata["split_family_id"], metadata["graph_family_key"])

    def test_preference_source_text_is_sanitized_from_meta_markers(self) -> None:
        cir = generate_pattern_record("toward_each_other", graph_seed=13, source_variant_key="base")
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            _write_jsonl(tmp_path / "cir.jsonl", [cir])
            request = _request(tmp_path)
            cir_index = build_cir_indices(request.cir_jsonl, contract_version=request.contract_version)
            raw_candidates = [
                {
                    "eval_case_id": "off-001",
                    "sample_id": cir["sample_id"],
                    "source_text": (
                        "Первый и второй актёр идут навстречу друг другу, "
                        "после чего второй начинает бежать — pass_by_then_role_shift, beat_count=3."
                    ),
                    "bad_json": {"actors": []},
                    "good_json": {"actors": [{"id": "actor_1"}]},
                    "correction_tier": "tier_b_deterministic_canonical",
                    "contract_version": "sg_v7_contract_v1",
                }
            ]
            result = build_preference_pairs(
                request,
                raw_candidates=raw_candidates,
                cir_index=cir_index,
                heldout_sft_family_ids=set(),
            )
            self.assertEqual(len(result.splitable_records), 1)
            source_text = str(result.splitable_records[0]["source_text"])
            self.assertNotIn("pass_by_then_role_shift", source_text)
            self.assertNotIn("beat_count", source_text)

    def test_preference_json_original_description_is_aligned_with_sanitized_source(self) -> None:
        cir = generate_pattern_record("pick_up_then_put_down_object", graph_seed=15, source_variant_key="base")
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            _write_jsonl(tmp_path / "cir.jsonl", [cir])
            request = _request(tmp_path)
            cir_index = build_cir_indices(request.cir_jsonl, contract_version=request.contract_version)
            raw_candidates = [
                {
                    "failure_id": "rtf-004",
                    "sample_id": cir["sample_id"],
                    "source": "Первый актёр сначала берёт бейдж, а потом кладёт бейдж на стул",
                    "raw_llm_output": {"actors": [], "originalDescription": "stale_bad"},
                    "corrected_target_json": {"actors": [{"id": "actor_1"}], "originalDescription": "stale_good"},
                    "correction_tier": "tier_c_reviewed_merge",
                    "contract_version": "sg_v7_contract_v1",
                }
            ]
            result = build_preference_pairs(
                request,
                raw_candidates=raw_candidates,
                cir_index=cir_index,
                heldout_sft_family_ids=set(),
            )
            self.assertEqual(len(result.splitable_records), 1)
            row = result.splitable_records[0]
            self.assertEqual(row["chosen_json"]["originalDescription"], row["source_text"])
            self.assertEqual(row["rejected_json"]["originalDescription"], row["source_text"])

    def test_preference_candidate_overlapping_heldout_normalized_hash_is_quarantined(self) -> None:
        cir = generate_pattern_record("toward_each_other", graph_seed=14, source_variant_key="base")
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            _write_jsonl(tmp_path / "cir.jsonl", [cir])
            request = _request(tmp_path)
            cir_index = build_cir_indices(request.cir_jsonl, contract_version=request.contract_version)
            source_text = "2 актёра идут навстречу друг другу."
            raw_candidates = [
                {
                    "failure_id": "rtf-003",
                    "sample_id": cir["sample_id"],
                    "source": source_text,
                    "raw_llm_output": {"actors": []},
                    "corrected_target_json": {"actors": [{"id": "actor_1"}]},
                    "correction_tier": "tier_c_reviewed_merge",
                    "contract_version": "sg_v7_contract_v1",
                }
            ]
            heldout_hashes = {normalized_source_hash_v1(source_text)}
            result = build_preference_pairs(
                request,
                raw_candidates=raw_candidates,
                cir_index=cir_index,
                heldout_sft_family_ids=set(),
                heldout_sft_normalized_source_hashes=heldout_hashes,
            )
            self.assertFalse(result.splitable_records)
            self.assertEqual(len(result.quarantined_records), 1)
            self.assertEqual(
                result.quarantined_records[0]["reason"],
                "overlaps_sft_heldout_normalized_source_hash",
            )
