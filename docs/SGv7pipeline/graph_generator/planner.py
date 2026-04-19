from __future__ import annotations

import hashlib
from collections import Counter

from cir_contract.contracts.cir_types import SourceVariantKey
from pattern_library import PATTERN_REGISTRY, PATTERN_REGISTRY_VERSION
from pattern_library.registry import PatternSpec

from .config import GraphBuildRequest, PatternQuota, PlanItem


class GraphPlannerError(ValueError):
    pass


def resolve_specs(request: GraphBuildRequest) -> list[PatternSpec]:
    explicit_pattern_filter = request.pattern_names is not None
    if request.pattern_names:
        missing = sorted(name for name in set(request.pattern_names) if name not in PATTERN_REGISTRY)
        if missing:
            raise GraphPlannerError(f"Unknown pattern_names: {missing}")
        specs = [PATTERN_REGISTRY[name] for name in sorted(set(request.pattern_names))]
    else:
        specs = sorted(PATTERN_REGISTRY.values(), key=lambda item: item.pattern_name)

    if request.difficulty_bucket is not None:
        mismatched = [spec.pattern_name for spec in specs if spec.difficulty_bucket != request.difficulty_bucket]
        if mismatched and explicit_pattern_filter:
            raise GraphPlannerError(
                f"Patterns do not belong to requested difficulty_bucket={request.difficulty_bucket!r}: {mismatched}"
            )
        specs = [spec for spec in specs if spec.difficulty_bucket == request.difficulty_bucket]

    if not specs:
        raise GraphPlannerError("No pattern specs selected for graph build request")
    return specs


def _allocate_counts(specs: list[PatternSpec], total_records: int) -> dict[str, int]:
    total_weight = sum(spec.default_share for spec in specs)
    if total_weight <= 0:
        raise GraphPlannerError("Pattern default_share sum must be positive")

    raw = []
    assigned = 0
    for spec in specs:
        ideal = total_records * spec.default_share / total_weight
        floor = int(ideal)
        assigned += floor
        raw.append((spec.pattern_name, floor, ideal - floor))

    remaining = total_records - assigned
    raw.sort(key=lambda item: (-item[2], item[0]))
    counts = {name: floor for name, floor, _ in raw}
    for name, _, _ in raw[:remaining]:
        counts[name] += 1
    return counts


def plan_pattern_quotas(request: GraphBuildRequest) -> list[PatternQuota]:
    specs = resolve_specs(request)
    total_records = request.total_records if request.total_records is not None else sum(spec.default_share for spec in specs)
    if total_records is None or total_records <= 0:
        raise GraphPlannerError("total_records must be positive")
    counts = _allocate_counts(specs, total_records)
    return [PatternQuota(pattern_name=spec.pattern_name, count=counts[spec.pattern_name]) for spec in specs]


def _allowed_variants(spec: PatternSpec, request: GraphBuildRequest) -> list[SourceVariantKey]:
    allowed = list(spec.allowed_source_variant_keys)
    if request.include_variants is None:
        return allowed
    filtered = [variant for variant in allowed if variant in set(request.include_variants)]
    if not filtered:
        raise GraphPlannerError(
            f"{spec.pattern_name} has no variants compatible with include_variants={request.include_variants}"
        )
    return filtered


def _variant_weight(spec: PatternSpec, variant: SourceVariantKey) -> int:
    semantic_tags = {str(tag) for tag in spec.semantic_tags}
    if variant == "base":
        if "marked_object" in semantic_tags and "morphology_stress" in spec.allowed_source_variant_keys:
            return 45
        if "ordinal_reference" in semantic_tags and "ordinal_stress" in spec.allowed_source_variant_keys:
            return 45
        return 60
    if variant == "ordinal_stress":
        if "ordinal_reference" in semantic_tags:
            return 30
        return 20
    if variant == "morphology_stress":
        if "marked_object" in semantic_tags:
            return 35
        return 20
    if variant == "dialogue_mix":
        return 8
    if variant == "same_type_marker_stress":
        return 100
    raise GraphPlannerError(f"Unsupported SourceVariantKey={variant!r}")


def _hash_digest(*parts: object) -> str:
    payload = "||".join(str(part) for part in parts).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _reduce_graph_seed(digest: str) -> int:
    return int(digest[:12], 16) % 999_900 + 100


def choose_variant_for_slot(spec: PatternSpec, request: GraphBuildRequest, *, ordinal: int) -> SourceVariantKey:
    allowed = _allowed_variants(spec, request)
    if len(allowed) == 1:
        return allowed[0]

    weights = [_variant_weight(spec, variant) for variant in allowed]
    total = sum(weights)
    digest = _hash_digest(
        request.seed,
        PATTERN_REGISTRY_VERSION,
        request.difficulty_bucket or "mixed",
        spec.pattern_name,
        ordinal,
        "variant",
    )
    needle = int(digest[:12], 16) % total
    seen = 0
    for variant, weight in zip(allowed, weights):
        seen += weight
        if needle < seen:
            return variant
    return allowed[-1]


def derive_graph_seed(
    request: GraphBuildRequest,
    *,
    difficulty_bucket: str,
    pattern_name: str,
    source_variant_key: SourceVariantKey,
    ordinal: int,
    attempt_index: int,
) -> int:
    digest = _hash_digest(
        request.seed,
        "sg_v7_contract_v1",
        PATTERN_REGISTRY_VERSION,
        difficulty_bucket,
        pattern_name,
        source_variant_key,
        ordinal,
        attempt_index,
    )
    return _reduce_graph_seed(digest)


def plan_graph_records(request: GraphBuildRequest) -> list[PlanItem]:
    quotas = plan_pattern_quotas(request)
    specs_by_name = {spec.pattern_name: spec for spec in resolve_specs(request)}
    plan_items: list[PlanItem] = []
    ordinal = 0
    for quota in quotas:
        spec = specs_by_name[quota.pattern_name]
        for _ in range(quota.count):
            variant = choose_variant_for_slot(spec, request, ordinal=ordinal)
            graph_seed = derive_graph_seed(
                request,
                difficulty_bucket=spec.difficulty_bucket,
                pattern_name=spec.pattern_name,
                source_variant_key=variant,
                ordinal=ordinal,
                attempt_index=0,
            )
            plan_items.append(
                PlanItem(
                    ordinal=ordinal,
                    pattern_name=spec.pattern_name,
                    difficulty_bucket=spec.difficulty_bucket,
                    source_variant_key=variant,
                    graph_seed=graph_seed,
                    attempt_index=0,
                )
            )
            ordinal += 1
    return plan_items


def summarize_plan(plan_items: list[PlanItem]) -> dict[str, dict[str, int]]:
    pattern_counts = Counter(item.pattern_name for item in plan_items)
    variant_counts = Counter(item.source_variant_key for item in plan_items)
    return {
        "pattern_counts": dict(sorted(pattern_counts.items())),
        "variant_counts": dict(sorted(variant_counts.items())),
    }
