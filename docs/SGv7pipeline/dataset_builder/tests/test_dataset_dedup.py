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


def _accepted_row(cir: dict[str, object], *, source_text: str) -> dict[str, object]:
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


class TestDatasetDedup(unittest.TestCase):
    def test_conflicting_duplicate_sample_id_fails_fast(self) -> None:
        cir = generate_pattern_record("toward_each_other", graph_seed=111, source_variant_key="base")
        accepted = [
            _accepted_row(cir, source_text="2 актера идут навстречу."),
            _accepted_row(cir, source_text="2 актера быстро идут навстречу."),
        ]
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            _write_jsonl(tmp_path / "cir.jsonl", [cir])
            _write_jsonl(tmp_path / "accepted.jsonl", accepted)
            request = DatasetBuildRequest(
                accepted_jsonl=tmp_path / "accepted.jsonl",
                cir_jsonl=tmp_path / "cir.jsonl",
                output_dir=tmp_path / "out",
                seed=1,
            )
            with self.assertRaises(DatasetBuildError):
                build_dataset(request)
