from __future__ import annotations

from dataclasses import replace

from cir_contract.contracts.cir_types import CIRRecord
from pattern_library import generate_pattern_record

from .config import BuildResult, GraphBuildRequest, PlanItem
from .dedup import DedupIndex
from .manifest import build_manifest
from .planner import choose_variant_for_slot, derive_graph_seed, plan_graph_records, resolve_specs
from .validate import GraphGeneratorValidationError, bucket_policy_for, validate_graph_record
from .writer import stable_sort_records, write_jsonl, write_manifest


class GraphBuildError(RuntimeError):
    pass


def materialize_plan_item(plan_item: PlanItem) -> CIRRecord:
    return generate_pattern_record(
        plan_item.pattern_name,
        graph_seed=plan_item.graph_seed,
        source_variant_key=plan_item.source_variant_key,
    )


def _replacement_plan_item(
    request: GraphBuildRequest,
    item: PlanItem,
    *,
    attempt_index: int,
    pattern_name: str,
    source_variant_key: str,
) -> PlanItem:
    return replace(
        item,
        pattern_name=pattern_name,
        source_variant_key=source_variant_key,
        attempt_index=attempt_index,
        graph_seed=derive_graph_seed(
            request,
            difficulty_bucket=item.difficulty_bucket,
            pattern_name=pattern_name,
            source_variant_key=source_variant_key,
            ordinal=item.ordinal,
            attempt_index=attempt_index,
        ),
    )


def build_graph_records(request: GraphBuildRequest) -> BuildResult:
    planned_items = plan_graph_records(request)
    available_specs = resolve_specs(request)
    specs_by_name = {spec.pattern_name: spec for spec in available_specs}
    specs_by_bucket: dict[str, list] = {}
    for spec in available_specs:
        specs_by_bucket.setdefault(spec.difficulty_bucket, []).append(spec)
    for bucket in specs_by_bucket:
        specs_by_bucket[bucket] = sorted(
            specs_by_bucket[bucket],
            key=lambda spec: (-spec.default_share, spec.pattern_name),
        )
    dedup_index = DedupIndex()
    emitted: list[CIRRecord] = []
    duplicate_drop_count = 0
    refill_attempt_count = 0
    rejected_by_budget = 0
    rejected_by_duplicate = 0

    for planned_item in planned_items:
        policy = bucket_policy_for(planned_item.difficulty_bucket)
        accepted = False
        original_spec = specs_by_name[planned_item.pattern_name]
        if request.pattern_names is not None:
            candidate_specs = [original_spec]
        else:
            bucket_specs = specs_by_bucket.get(planned_item.difficulty_bucket, [])
            candidate_specs = [original_spec] + [
                spec for spec in bucket_specs if spec.pattern_name != planned_item.pattern_name
            ]

        exhausted_patterns: list[str] = []
        for pattern_candidate_index, pattern_spec in enumerate(candidate_specs):
            exhausted_current_pattern = True
            for attempt_index in range(0, request.refill_budget + 1):
                if pattern_candidate_index == 0:
                    source_variant_key = planned_item.source_variant_key
                else:
                    source_variant_key = choose_variant_for_slot(
                        pattern_spec,
                        request,
                        ordinal=planned_item.ordinal + pattern_candidate_index,
                    )
                current_item = _replacement_plan_item(
                    request,
                    planned_item,
                    attempt_index=attempt_index,
                    pattern_name=pattern_spec.pattern_name,
                    source_variant_key=source_variant_key,
                )
                if attempt_index > 0 or pattern_candidate_index > 0:
                    refill_attempt_count += 1

                record = materialize_plan_item(current_item)
                try:
                    validate_graph_record(record, policy)
                except GraphGeneratorValidationError as exc:
                    rejected_by_budget += 1
                    if attempt_index >= request.refill_budget:
                        exhausted_patterns.append(f"{pattern_spec.pattern_name}(invalid:{exc})")
                        exhausted_current_pattern = True
                    continue

                if not dedup_index.add(record):
                    duplicate_drop_count += 1
                    rejected_by_duplicate += 1
                    if request.fail_on_duplicates:
                        raise GraphBuildError(f"Duplicate graph detected for sample_id={record['sample_id']}")
                    if attempt_index >= request.refill_budget:
                        exhausted_patterns.append(f"{pattern_spec.pattern_name}(duplicates)")
                        exhausted_current_pattern = True
                    continue

                emitted.append(record)
                accepted = True
                exhausted_current_pattern = False
                break

            if accepted:
                break
            if not exhausted_current_pattern:
                break

        if not accepted:
            raise GraphBuildError(
                "Plan item could not be materialized after trying patterns: "
                f"requested={planned_item.pattern_name}, "
                f"attempted={', '.join(exhausted_patterns) if exhausted_patterns else planned_item.pattern_name}"
            )

    emitted = stable_sort_records(emitted)
    write_jsonl(emitted, request.output_jsonl)

    manifest = build_manifest(
        request=request,
        records=emitted,
        duplicate_drop_count=duplicate_drop_count,
        refill_attempt_count=refill_attempt_count,
        rejected_by_budget=rejected_by_budget,
        rejected_by_duplicate=rejected_by_duplicate,
    )
    if request.output_manifest is not None:
        write_manifest(manifest, request.output_manifest)

    return BuildResult(records=emitted, manifest=manifest)
