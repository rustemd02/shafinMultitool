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
    return {
        "sample_id": plan_item.sample_id,
        "parent_variant_id": plan_item.parent_variant_id,
        "variant_id": f"{plan_item.parent_variant_id}-aug-{plan_item.variant_ordinal + 1:02d}",
        "graph_id": plan_item.graph_id,
        "difficulty_bucket": plan_item.difficulty_bucket,
        "style_bucket": plan_item.style_bucket,
        "source_text": normalized,
        "generation_pass": "augmentation",
        "augmentation_policy_version": plan_item.policy_version,
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
