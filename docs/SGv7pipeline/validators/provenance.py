from __future__ import annotations

from .contracts import KNOWN_PROVENANCE_TIERS, materialize_correction_tier
from .taxonomy import PROVENANCE_CODES


def evaluate_provenance(sample: dict[str, object]) -> tuple[str | None, list[str], list[str]]:
    correction_tier = materialize_correction_tier(sample)
    reject_reasons: list[str] = []
    review_reasons: list[str] = []
    if correction_tier is None:
        reject_reasons.append("provenance_missing_tier")
        return None, reject_reasons, review_reasons
    if correction_tier not in KNOWN_PROVENANCE_TIERS:
        reject_reasons.append("provenance_unknown_tier")
        return correction_tier, reject_reasons, review_reasons
    if correction_tier == "tier_c_reviewed_merge":
        review_reasons.append("review_tier_c_reviewed_merge")
    return correction_tier, reject_reasons, review_reasons


def train_eligibility_for(status: str, correction_tier: str | None) -> str:
    if status == "rejected":
        return "reject_only"
    if status == "manual_review":
        return "review_only"
    if correction_tier in {"tier_a_human_gold", "tier_b_deterministic_canonical"}:
        return "direct_sft"
    if correction_tier == "tier_c_reviewed_merge":
        return "hard_or_preference_only"
    if correction_tier == "tier_d_auto_repair_only":
        return "reject_only"
    return "reject_only"
