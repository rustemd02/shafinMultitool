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

from dataset_builder import DatasetBuildError, DatasetBuildRequest, build_dataset


def _write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")


def _accepted_row(cir: dict[str, object], *, source_text: str = "2 актера идут навстречу.") -> dict[str, object]:
    return {
        "sample_id": cir["sample_id"],
        "graph_id": cir["sample_id"],
        "difficulty_bucket": cir["difficulty_bucket"],
        "source_text": source_text,
        "generation_pass": "base_paraphrase",
        "style_bucket": "clean",
        "correction_tier": "tier_b_deterministic_canonical",
        "validation_status": "accepted",
        "train_eligibility": "direct_sft",
        "contract_version": "sg_v7_contract_v1",
        "validation_report": {
            "validator_stack_version": "sgv7_validator_stack_v1",
            "recoverability_score": 95,
        },
    }


class TestDatasetIngest(unittest.TestCase):
    def test_promotion_sidecar_requires_manual_review_artifact(self) -> None:
        cir = generate_pattern_record("toward_each_other", graph_seed=211, source_variant_key="base")
        accepted = [_accepted_row(cir)]
        promoted = [
            {
                "sample_id": cir["sample_id"],
                "review_decision": "promote_for_hard_sft",
                "reviewer": "human",
                "reviewed_at": "2026-04-13T11:30:00Z",
                "promoted_train_eligibility": "hard_or_preference_only",
            }
        ]
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            _write_jsonl(tmp_path / "cir.jsonl", [cir])
            _write_jsonl(tmp_path / "accepted.jsonl", accepted)
            _write_jsonl(tmp_path / "promoted.jsonl", promoted)
            request = DatasetBuildRequest(
                accepted_jsonl=tmp_path / "accepted.jsonl",
                cir_jsonl=tmp_path / "cir.jsonl",
                output_dir=tmp_path / "out",
                seed=1,
                review_promoted_jsonl=tmp_path / "promoted.jsonl",
            )
            with self.assertRaises(DatasetBuildError):
                build_dataset(request)

    def test_limits_technical_identifier_share_in_sft(self) -> None:
        cir_rows = [
            generate_pattern_record("toward_each_other", graph_seed=311, source_variant_key="base"),
            generate_pattern_record("toward_each_other", graph_seed=312, source_variant_key="base"),
            generate_pattern_record("toward_each_other", graph_seed=313, source_variant_key="base"),
            generate_pattern_record("toward_each_other", graph_seed=314, source_variant_key="base"),
        ]
        accepted = [
            _accepted_row(cir_rows[0], source_text="Первый актер (actor_1) идёт к actor_2."),
            _accepted_row(cir_rows[1], source_text="Они идут навстречу друг другу."),
            _accepted_row(cir_rows[2], source_text="Останавливаются у object_marked_deadbeef."),
            _accepted_row(cir_rows[3], source_text="Первый поворачивается к второму."),
        ]

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            _write_jsonl(tmp_path / "cir.jsonl", cir_rows)
            _write_jsonl(tmp_path / "accepted.jsonl", accepted)
            request = DatasetBuildRequest(
                accepted_jsonl=tmp_path / "accepted.jsonl",
                cir_jsonl=tmp_path / "cir.jsonl",
                output_dir=tmp_path / "out",
                seed=1,
                max_technical_source_share=0.40,
            )
            result = build_dataset(request)

            all_rows = [*result.sft_records["train"], *result.sft_records["val"], *result.sft_records["test"]]
            technical_count = sum(
                1
                for row in all_rows
                if ("actor_" in str(row.get("source_text", "")) or "object_marked_" in str(row.get("source_text", "")))
            )
            self.assertEqual(len(all_rows), 3)
            self.assertEqual(technical_count, 1)
