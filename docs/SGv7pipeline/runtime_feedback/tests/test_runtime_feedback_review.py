from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
import sys

DOCS_ROOT = Path(__file__).resolve().parents[2]
if str(DOCS_ROOT) not in sys.path:
    sys.path.insert(0, str(DOCS_ROOT))

from runtime_feedback import ReviewAndPromoteRequest, RuntimeFeedbackError, review_and_promote_runtime_feedback


def _write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")


class TestRuntimeFeedbackReview(unittest.TestCase):
    def test_review_promotes_approved_tier_b_case(self) -> None:
        row = {
            "failure_id": "rtf_000001",
            "source": "2 актера подходят к столу",
            "privacy_status": "clear",
            "review_status": "pending",
            "correction_tier": "",
            "gold_source": "pending_review",
            "corrected_target_json": None,
            "rule_based_reference_json": {"actors": [{"id": "actor_1"}], "beats": []},
            "runtime_policy_inputs": {
                "rule_confidence": 0.5,
                "rule_object_count": 1,
                "rule_action_count": 1,
                "rule_has_dangling_targets": False,
                "rule_matched_marked_object_count": 0,
                "mentioned_marked_object_ids": [],
            },
            "family_resolution_proof": {"proof_status": "resolved"},
            "train_eligibility": "review_only",
        }
        decision = {
            "failure_id": "rtf_000001",
            "review_status": "approved",
            "correction_tier": "tier_b_deterministic_canonical",
            "gold_source": "deterministic_canonicalizer",
            "corrected_target_json": {"actors": [{"id": "actor_1"}], "objects": [], "beats": []},
        }
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            in_rows = tmp / "runtime_failures.jsonl"
            decisions = tmp / "review_decisions.jsonl"
            _write_jsonl(in_rows, [row])
            _write_jsonl(decisions, [decision])

            result = review_and_promote_runtime_feedback(
                ReviewAndPromoteRequest(
                    runtime_failures_jsonl=in_rows,
                    review_decisions_jsonl=decisions,
                    output_runtime_failures_jsonl=tmp / "updated_runtime_failures.jsonl",
                    output_promoted_jsonl=tmp / "promoted.jsonl",
                    output_manifest_json=tmp / "manifest.json",
                )
            )
            self.assertEqual(result.manifest["promoted_count"], 1)
            self.assertEqual(result.runtime_failures[0]["train_eligibility"], "direct_sft")
            self.assertTrue(result.runtime_failures[0]["eval_bridge_ready"])

    def test_review_rejects_invalid_approved_tier_d(self) -> None:
        row = {
            "failure_id": "rtf_000002",
            "privacy_status": "clear",
            "review_status": "pending",
            "correction_tier": "",
            "gold_source": "pending_review",
            "corrected_target_json": None,
            "rule_based_reference_json": {"actors": [{"id": "actor_1"}], "beats": []},
            "runtime_policy_inputs": {
                "rule_confidence": 0.5,
                "rule_object_count": 1,
                "rule_action_count": 1,
                "rule_has_dangling_targets": False,
                "rule_matched_marked_object_count": 0,
                "mentioned_marked_object_ids": [],
            },
            "family_resolution_proof": {"proof_status": "resolved"},
            "train_eligibility": "review_only",
        }
        decision = {
            "failure_id": "rtf_000002",
            "review_status": "approved",
            "correction_tier": "tier_d_auto_repair_only",
            "gold_source": "auto_repair_only",
            "corrected_target_json": {"actors": [{"id": "actor_1"}], "objects": [], "beats": []},
        }
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            in_rows = tmp / "runtime_failures.jsonl"
            decisions = tmp / "review_decisions.jsonl"
            _write_jsonl(in_rows, [row])
            _write_jsonl(decisions, [decision])
            with self.assertRaises(RuntimeFeedbackError):
                review_and_promote_runtime_feedback(
                    ReviewAndPromoteRequest(
                        runtime_failures_jsonl=in_rows,
                        review_decisions_jsonl=decisions,
                        output_runtime_failures_jsonl=tmp / "updated_runtime_failures.jsonl",
                        output_promoted_jsonl=tmp / "promoted.jsonl",
                        output_manifest_json=tmp / "manifest.json",
                    )
                )

