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
from runtime_feedback import ExportEvalCasesRequest, export_real_runtime_eval_cases


def _write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")


class TestRuntimeFeedbackExport(unittest.TestCase):
    def test_export_real_runtime_eval_cases_and_quarantine(self) -> None:
        cir = generate_pattern_record("toward_each_other_then_stop_near_marked_object", graph_seed=401, source_variant_key="base")
        exportable = {
            "failure_id": "rtf-exportable",
            "contract_version": "sg_v7_contract_v1",
            "source": "2 актёра идут навстречу друг другу, останавливаются у компа",
            "marked_objects": [{"id": "object_marked_ab12", "name": "комп", "type": "generic"}],
            "family_anchor": {"anchor_type": "sample_id", "anchor_value": cir["sample_id"]},
            "review_status": "approved",
            "correction_tier": "tier_c_reviewed_merge",
            "gold_source": "reviewed_merge",
            "final_script_source": "merged",
            "corrected_target_json": {"actors": [{"id": "actor_1"}], "objects": [], "beats": []},
            "rule_based_reference_json": {"actors": [{"id": "actor_1"}], "objects": [], "beats": []},
            "runtime_policy_inputs": {
                "rule_confidence": 0.6,
                "rule_object_count": 1,
                "rule_action_count": 2,
                "rule_has_dangling_targets": False,
                "rule_matched_marked_object_count": 1,
                "mentioned_marked_object_ids": ["object_marked_ab12"],
            },
            "eval_bridge_ready": True,
            "eval_bridge_block_reason": "",
        }
        blocked = {
            "failure_id": "rtf-blocked",
            "review_status": "pending",
            "eval_bridge_ready": False,
            "eval_bridge_block_reason": "review_not_approved",
        }

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            runtime_failures = tmp / "runtime_failures.jsonl"
            cir_jsonl = tmp / "cir.jsonl"
            _write_jsonl(runtime_failures, [exportable, blocked])
            _write_jsonl(cir_jsonl, [cir])

            result = export_real_runtime_eval_cases(
                ExportEvalCasesRequest(
                    runtime_failures_jsonl=runtime_failures,
                    cir_jsonl=cir_jsonl,
                    output_eval_cases_jsonl=tmp / "eval_cases.jsonl",
                    output_quarantine_jsonl=tmp / "quarantine.jsonl",
                    output_manifest_json=tmp / "manifest.json",
                )
            )
            self.assertEqual(result.manifest["exported_eval_case_count"], 1)
            self.assertEqual(result.manifest["quarantined_count"], 1)
            self.assertEqual(result.eval_cases[0]["eval_set"], "real_runtime")
            self.assertEqual(result.eval_cases[0]["provenance"]["runtime_failure_id"], "rtf-exportable")
            self.assertEqual(result.eval_cases[0]["difficulty_bucket"], str(cir["difficulty_bucket"]))
            self.assertTrue(bool(result.eval_cases[0]["graph_family_key"]))
