from __future__ import annotations

from collections import Counter
from pathlib import Path

from pattern_library import PATTERN_REGISTRY_VERSION

from .config import GraphBuildRequest
from .dedup import dedup_group_key


def build_manifest(
    *,
    request: GraphBuildRequest,
    records: list[dict],
    duplicate_drop_count: int,
    refill_attempt_count: int,
    rejected_by_budget: int,
    rejected_by_duplicate: int,
) -> dict[str, object]:
    pattern_counts = Counter(record["pattern_name"] for record in records)
    variant_counts = Counter(record["source_variant_key"] for record in records)
    complexity_counts = Counter(record["complexity_class"] for record in records)
    dedup_group_counts = Counter(dedup_group_key(record) for record in records)
    first_record = records[0] if records else None

    return {
        "generator_name": "sg_v7_graph_generator_v1",
        "build_seed": request.seed,
        "difficulty_bucket": request.difficulty_bucket or "mixed",
        "requested_total_records": request.total_records if request.total_records is not None else len(records),
        "emitted_total_records": len(records),
        "duplicate_drop_count": duplicate_drop_count,
        "refill_attempt_count": refill_attempt_count,
        "cir_version": first_record["cir_version"] if first_record else "sg_v7_cir_v1",
        "contract_version": first_record["contract_version"] if first_record else "sg_v7_contract_v1",
        "pattern_registry_version": PATTERN_REGISTRY_VERSION,
        "pattern_counts": dict(sorted(pattern_counts.items())),
        "variant_counts": dict(sorted(variant_counts.items())),
        "complexity_counts": dict(sorted(complexity_counts.items())),
        "dedup_group_counts": dict(sorted(dedup_group_counts.items())),
        "rejected_by_budget": rejected_by_budget,
        "rejected_by_duplicate": rejected_by_duplicate,
        "build_request": {
            "seed": request.seed,
            "difficulty_bucket": request.difficulty_bucket,
            "total_records": request.total_records,
            "pattern_names": request.pattern_names,
            "include_variants": request.include_variants,
            "output_jsonl": str(request.output_jsonl),
            "output_manifest": str(request.output_manifest) if request.output_manifest is not None else None,
            "refill_budget": request.refill_budget,
            "fail_on_duplicates": request.fail_on_duplicates,
        },
    }
