from __future__ import annotations

from copy import deepcopy
from typing import Any

from .config import ReviewAndPromoteRequest, ReviewAndPromoteResult, RuntimeFeedbackError
from .io import read_jsonl, write_json, write_jsonl


def _as_dict(value: object) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    return {}


def _compute_train_eligibility(row: dict[str, Any]) -> str:
    privacy_status = str(row.get("privacy_status", "clear"))
    status = str(row.get("review_status", "pending"))
    tier = str(row.get("correction_tier", ""))
    if privacy_status == "blocked":
        return "reject_only"
    if status == "pending":
        return "review_only"
    if status == "quarantined":
        return "review_only"
    if status == "rejected":
        return "reject_only"
    if status != "approved":
        return "reject_only"
    if tier in {"tier_a_human_gold", "tier_b_deterministic_canonical"}:
        return "direct_sft"
    if tier == "tier_c_reviewed_merge":
        return "hard_or_preference_only"
    return "reject_only"


def _compute_eval_bridge(row: dict[str, Any]) -> tuple[bool, str]:
    if str(row.get("privacy_status", "")) not in {"clear", "redacted"}:
        return False, "privacy_not_exportable"
    if str(row.get("review_status", "")) != "approved":
        return False, "review_not_approved"
    if str(row.get("correction_tier", "")) not in {
        "tier_a_human_gold",
        "tier_b_deterministic_canonical",
        "tier_c_reviewed_merge",
    }:
        return False, "tier_not_allowed_for_eval_gold"
    if not isinstance(row.get("corrected_target_json"), dict):
        return False, "missing_corrected_target_json"
    if not isinstance(row.get("rule_based_reference_json"), dict):
        return False, "missing_rule_based_reference_json"
    if not isinstance(row.get("runtime_policy_inputs"), dict):
        return False, "missing_runtime_policy_inputs"
    return True, ""


def _validate_state_machine(row: dict[str, Any]) -> None:
    status = str(row.get("review_status", ""))
    tier = str(row.get("correction_tier", ""))
    gold_source = str(row.get("gold_source", ""))
    eligibility = str(row.get("train_eligibility", ""))
    corrected = row.get("corrected_target_json")

    allowed_statuses = {"pending", "approved", "rejected", "quarantined"}
    if status not in allowed_statuses:
        raise RuntimeFeedbackError(f"invalid review_status={status!r} for failure_id={row.get('failure_id')!r}")

    if status == "approved":
        if gold_source == "pending_review":
            raise RuntimeFeedbackError("approved row cannot keep gold_source=pending_review")
        if not isinstance(corrected, dict):
            raise RuntimeFeedbackError("approved row requires corrected_target_json object")
        if tier == "tier_d_auto_repair_only":
            raise RuntimeFeedbackError("approved row cannot keep tier_d_auto_repair_only")
        if eligibility == "review_only":
            raise RuntimeFeedbackError("approved row cannot keep train_eligibility=review_only")
    if status in {"rejected", "quarantined"} and eligibility == "direct_sft":
        raise RuntimeFeedbackError("rejected/quarantined row cannot keep train_eligibility=direct_sft")


def review_and_promote_runtime_feedback(request: ReviewAndPromoteRequest) -> ReviewAndPromoteResult:
    rows = read_jsonl(request.runtime_failures_jsonl)
    decisions = read_jsonl(request.review_decisions_jsonl)
    decision_by_failure_id: dict[str, dict[str, Any]] = {}
    for item in decisions:
        failure_id = str(item.get("failure_id", "")).strip()
        if not failure_id:
            raise RuntimeFeedbackError("review decision missing failure_id")
        if failure_id in decision_by_failure_id:
            raise RuntimeFeedbackError(f"duplicate review decision for failure_id={failure_id!r}")
        decision_by_failure_id[failure_id] = item

    updated: list[dict[str, Any]] = []
    promoted: list[dict[str, Any]] = []
    reviewed_count = 0
    for row in rows:
        current = deepcopy(row)
        failure_id = str(current.get("failure_id", "")).strip()
        decision = decision_by_failure_id.get(failure_id)
        if decision is not None:
            reviewed_count += 1
            for key in ("review_status", "correction_tier", "gold_source", "review_notes", "corrected_target_json"):
                if key in decision:
                    current[key] = decision[key]

        current["train_eligibility"] = _compute_train_eligibility(current)
        eval_ready, block_reason = _compute_eval_bridge(current)
        current["eval_bridge_ready"] = eval_ready
        current["eval_bridge_block_reason"] = block_reason
        _validate_state_machine(current)

        proof = _as_dict(current.get("family_resolution_proof"))
        proof_status = str(proof.get("proof_status", ""))
        can_promote = (
            str(current.get("review_status", "")) == "approved"
            and str(current.get("train_eligibility", "")) in {"direct_sft", "hard_or_preference_only"}
            and proof_status == "resolved"
            and str(current.get("privacy_status", "")) != "blocked"
            and isinstance(current.get("corrected_target_json"), dict)
        )
        if can_promote:
            promoted.append(deepcopy(current))
        updated.append(current)

    manifest = {
        "runtime_feedback_review_version": "runtime_feedback_review_v1",
        "input_runtime_failure_count": len(rows),
        "review_decision_count": len(decisions),
        "applied_review_decisions": reviewed_count,
        "promoted_count": len(promoted),
        "approved_count": sum(1 for row in updated if str(row.get("review_status", "")) == "approved"),
        "pending_count": sum(1 for row in updated if str(row.get("review_status", "")) == "pending"),
    }

    write_jsonl(updated, request.output_runtime_failures_jsonl)
    write_jsonl(promoted, request.output_promoted_jsonl)
    write_json(manifest, request.output_manifest_json)

    return ReviewAndPromoteResult(
        runtime_failures=deepcopy(updated),
        promoted=deepcopy(promoted),
        manifest=deepcopy(manifest),
    )

