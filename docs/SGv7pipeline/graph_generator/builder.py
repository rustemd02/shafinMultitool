from __future__ import annotations

from collections import Counter
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


def _candidate_specs_for_slot(
    request: GraphBuildRequest,
    planned_item: PlanItem,
    *,
    original_pattern_name: str,
    specs_by_bucket: dict[str, list],
    target_counts: Counter[str],
    emitted_counts: Counter[str],
) -> list:
    if request.pattern_names is not None:
        return [spec for spec in specs_by_bucket.get(planned_item.difficulty_bucket, []) if spec.pattern_name == original_pattern_name]

    bucket_specs = specs_by_bucket.get(planned_item.difficulty_bucket, [])
    if not bucket_specs:
        return []

    def sort_key(spec) -> tuple[int, int, int, str]:
        target = target_counts.get(spec.pattern_name, 0)
        emitted = emitted_counts.get(spec.pattern_name, 0)
        deficit = target - emitted
        if deficit > 0:
            # Fill under-target patterns first, biggest deficit first.
            return (0, -deficit, emitted, spec.pattern_name)
        # Once over target, spread overflow evenly instead of collapsing into one pattern.
        return (1, emitted - target, emitted, spec.pattern_name)

    ranked = sorted(bucket_specs, key=sort_key)

    # Keep deterministic tie-break behavior while still allowing quota balancing:
    # if original pattern is still under target, prefer it among equally ranked peers.
    target = target_counts.get(original_pattern_name, 0)
    emitted = emitted_counts.get(original_pattern_name, 0)
    if emitted < target:
        for index, spec in enumerate(ranked):
            if spec.pattern_name == original_pattern_name:
                if index > 0:
                    ranked.insert(0, ranked.pop(index))
                break
    return ranked


def build_graph_records(request: GraphBuildRequest) -> BuildResult:
    planned_items = plan_graph_records(request)
    print(
        f"[graph_builder] start: planned_items={len(planned_items)} refill_budget={request.refill_budget} fail_on_duplicates={request.fail_on_duplicates}",
        flush=True,
    )
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
    target_counts: Counter[str] = Counter(item.pattern_name for item in planned_items)
    emitted_counts: Counter[str] = Counter()
    dedup_index = DedupIndex()
    emitted: list[CIRRecord] = []
    duplicate_drop_count = 0
    refill_attempt_count = 0
    rejected_by_budget = 0
    rejected_by_duplicate = 0
    progress_stride = max(1, len(planned_items) // 20) if planned_items else 1

    for planned_index, planned_item in enumerate(planned_items, start=1):
        policy = bucket_policy_for(planned_item.difficulty_bucket)
        accepted = False
        original_spec = specs_by_name[planned_item.pattern_name]
        candidate_specs = _candidate_specs_for_slot(
            request,
            planned_item,
            original_pattern_name=original_spec.pattern_name,
            specs_by_bucket=specs_by_bucket,
            target_counts=target_counts,
            emitted_counts=emitted_counts,
        )
        if not candidate_specs:
            raise GraphBuildError(
                "No candidate specs resolved for slot "
                f"bucket={planned_item.difficulty_bucket} requested={planned_item.pattern_name}"
            )

        exhausted_patterns: list[str] = []
        for pattern_candidate_index, pattern_spec in enumerate(candidate_specs):
            exhausted_current_pattern = True
            for attempt_index in range(0, request.refill_budget + 1):
                if pattern_spec.pattern_name == planned_item.pattern_name:
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
                emitted_counts[record["pattern_name"]] += 1
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
        if planned_index == len(planned_items) or planned_index % progress_stride == 0:
            print(
                f"[graph_builder] progress: {planned_index}/{len(planned_items)} records materialized",
                flush=True,
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
    print(
        "[graph_builder] done: "
        f"records={len(emitted)} duplicate_drops={duplicate_drop_count} refill_attempts={refill_attempt_count} "
        f"rejected_by_budget={rejected_by_budget} rejected_by_duplicate={rejected_by_duplicate}",
        flush=True,
    )

    return BuildResult(records=emitted, manifest=manifest)
