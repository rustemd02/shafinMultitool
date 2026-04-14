from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
import sys

DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from dataset_builder.config import DatasetBuildRequest
from dataset_builder.ingest import build_cir_indices
from dataset_builder.preference import build_preference_pairs
from pattern_library import generate_pattern_record


def _write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")


class TestRuntimeFeedbackDatasetBridge(unittest.TestCase):
    def test_runtime_failure_row_builds_preference_pair(self) -> None:
        cir = generate_pattern_record("toward_each_other_then_stop_near_marked_object", graph_seed=777, source_variant_key="base")
        runtime_row = {
            "failure_id": "rtf-bridge-1",
            "_preference_origin": "runtime_failure_reviewed_merge",
            "contract_version": "sg_v7_contract_v1",
            "source": "2 актера идут навстречу друг другу, останавливаются у компа",
            "raw_llm_output": {"actors": [{"id": "actor_1"}], "objects": [], "beats": []},
            "corrected_target_json": {"actors": [{"id": "actor_1"}, {"id": "actor_2"}], "objects": [], "beats": []},
            "final_decision": "merge",
            "correction_tier": "tier_c_reviewed_merge",
            "family_anchor": {
                "anchor_type": "sample_id",
                "anchor_value": cir["sample_id"],
            },
        }
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            cir_jsonl = tmp / "cir.jsonl"
            _write_jsonl(cir_jsonl, [cir])
            request = DatasetBuildRequest(
                accepted_jsonl=tmp / "accepted.jsonl",
                cir_jsonl=cir_jsonl,
                output_dir=tmp / "out",
                seed=20260414,
                runtime_failures_jsonl=tmp / "runtime_failures.jsonl",
            )
            _write_jsonl(request.accepted_jsonl, [])
            _write_jsonl(request.runtime_failures_jsonl, [runtime_row])

            cir_index = build_cir_indices(cir_jsonl, contract_version=request.contract_version)
            result = build_preference_pairs(
                request,
                raw_candidates=[runtime_row],
                cir_index=cir_index,
                heldout_sft_family_ids=set(),
            )
            self.assertEqual(len(result.splitable_records), 1)
            metadata = result.splitable_records[0]["packaging_metadata"]
            self.assertTrue(bool(metadata["graph_family_key"]))
            self.assertEqual(metadata["preference_origin"], "runtime_failure_reviewed_merge")
