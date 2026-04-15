from __future__ import annotations

from .config import TransformPlanItem
from .slots import build_surface_anchor_snapshot
from .validate import normalize_augmented_source_text


def build_accept_record(
    plan_item: TransformPlanItem,
    *,
    source_text: str,
    transform_chain: list[dict[str, object]],
) -> dict[str, object]:
    normalized = normalize_augmented_source_text(source_text)
    graph_constraints = dict(plan_item.parent_record["graph_constraints"])
    contract_version = str(plan_item.parent_record.get("contract_version", "sg_v7_contract_v1"))
    return {
        "sample_id": plan_item.sample_id,
        "parent_variant_id": plan_item.parent_variant_id,
        "variant_id": f"{plan_item.parent_variant_id}-aug-{plan_item.variant_ordinal + 1:02d}",
        "graph_id": plan_item.graph_id,
        "pattern_name": plan_item.parent_record.get("pattern_name"),
        "contract_version": contract_version,
        "difficulty_bucket": plan_item.difficulty_bucket,
        "style_bucket": plan_item.style_bucket,
        "source_text": normalized,
        "generation_pass": "augmentation",
        "augmentation_policy_version": plan_item.policy_version,
        "model_name": plan_item.parent_record.get("model_name"),
        "prompt_template_version": plan_item.parent_record.get("prompt_template_version"),
        "source_policy_version": plan_item.parent_record.get("source_policy_version"),
        "attempt_index": 0,
        "seed": plan_item.seed,
        "graph_constraints": graph_constraints,
        "transform_chain": transform_chain,
        "risk_flags": list(plan_item.risk_flags),
        "validation": {
            "lexical_invariants_passed": True,
            "needs_semantic_validation": True,
        },
        "surface_anchor_snapshot": build_surface_anchor_snapshot(normalized, graph_constraints),
    }


def build_reject_record(
    parent_record: dict[str, object],
    *,
    reject_reason: str,
    reject_stage: str,
    seed: int,
    recipe_id: str | None = None,
    candidate_text: str | None = None,
    transform_chain: list[dict[str, object]] | None = None,
) -> dict[str, object]:
    return {
        "sample_id": parent_record.get("sample_id"),
        "parent_variant_id": parent_record.get("variant_id"),
        "graph_id": parent_record.get("graph_id", parent_record.get("sample_id")),
        "pattern_name": parent_record.get("pattern_name"),
        "contract_version": parent_record.get("contract_version", "sg_v7_contract_v1"),
        "difficulty_bucket": parent_record.get("difficulty_bucket"),
        "style_bucket": parent_record.get("style_bucket"),
        "generation_pass": "augmentation",
        "recipe_id": recipe_id,
        "reject_stage": reject_stage,
        "reject_reason": reject_reason,
        "candidate_text": candidate_text,
        "transform_chain": transform_chain or [],
        "seed": seed,
    }
