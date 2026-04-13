from __future__ import annotations

from .config import VariantPlanItem
from .filters import normalize_persisted_source_text


def build_accept_record(plan_item: VariantPlanItem, source_text: str) -> dict[str, object]:
    normalized = normalize_persisted_source_text(source_text)
    return {
        "sample_id": plan_item.sample_id,
        "variant_id": f"{plan_item.sample_id}-{plan_item.style_bucket}-{plan_item.variant_ordinal:02d}",
        "graph_id": plan_item.graph_id,
        "pattern_name": plan_item.pattern_name,
        "difficulty_bucket": plan_item.difficulty_bucket,
        "style_bucket": plan_item.style_bucket,
        "source_text": normalized,
        "model_name": plan_item.model_name,
        "prompt_template_version": plan_item.prompt_template_version,
        "source_policy_version": plan_item.source_policy_version,
        "generation_pass": "base_paraphrase",
        "attempt_index": 0,
        "seed": plan_item.seed,
        "acceptance": {
            "lexical_checks_passed": True,
            "needs_semantic_critic": True,
        },
    }


def build_reject_record(
    plan_item: VariantPlanItem,
    *,
    candidate_text: str,
    reject_reason: str,
    attempt_index: int,
    reject_stage: str = "lexical_or_format_reject",
) -> dict[str, object]:
    return {
        "sample_id": plan_item.sample_id,
        "graph_id": plan_item.graph_id,
        "pattern_name": plan_item.pattern_name,
        "difficulty_bucket": plan_item.difficulty_bucket,
        "style_bucket": plan_item.style_bucket,
        "model_name": plan_item.model_name,
        "prompt_template_version": plan_item.prompt_template_version,
        "source_policy_version": plan_item.source_policy_version,
        "generation_pass": "base_paraphrase",
        "attempt_index": attempt_index,
        "reject_stage": reject_stage,
        "reject_reason": reject_reason,
        "candidate_text": candidate_text,
        "seed": plan_item.seed,
    }
