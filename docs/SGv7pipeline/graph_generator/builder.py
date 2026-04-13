from __future__ import annotations

from dataclasses import replace

from cir_contract.contracts.cir_types import CIRRecord
from pattern_library import generate_pattern_record

from .config import BuildResult, GraphBuildRequest, PlanItem
from .dedup import DedupIndex
from .manifest import build_manifest
from .planner import derive_graph_seed, plan_graph_records
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


def _replacement_plan_item(request: GraphBuildRequest, item: PlanItem, *, attempt_index: int) -> PlanItem:
    return replace(
        item,
        attempt_index=attempt_index,
        graph_seed=derive_graph_seed(
            request,
            difficulty_bucket=item.difficulty_bucket,
            pattern_name=item.pattern_name,
            source_variant_key=item.source_variant_key,
            ordinal=item.ordinal,
            attempt_index=attempt_index,
        ),
    )


def build_graph_records(request: GraphBuildRequest) -> BuildResult:
    planned_items = plan_graph_records(request)
    dedup_index = DedupIndex()
    emitted: list[CIRRecord] = []
    duplicate_drop_count = 0
    refill_attempt_count = 0
    rejected_by_budget = 0
    rejected_by_duplicate = 0

    for planned_item in planned_items:
        policy = bucket_policy_for(planned_item.difficulty_bucket)
        accepted = False
        for attempt_index in range(0, request.refill_budget + 1):
            current_item = _replacement_plan_item(request, planned_item, attempt_index=attempt_index)
            if attempt_index > 0:
                refill_attempt_count += 1

            record = materialize_plan_item(current_item)
            try:
                validate_graph_record(record, policy)
            except GraphGeneratorValidationError as exc:
                rejected_by_budget += 1
                if attempt_index >= request.refill_budget:
                    raise GraphBuildError(
                        f"Unable to build valid graph after {request.refill_budget + 1} attempts "
                        f"for pattern={planned_item.pattern_name}: {exc}"
                    ) from exc
                continue

            if not dedup_index.add(record):
                duplicate_drop_count += 1
                rejected_by_duplicate += 1
                if request.fail_on_duplicates:
                    raise GraphBuildError(f"Duplicate graph detected for sample_id={record['sample_id']}")
                if attempt_index >= request.refill_budget:
                    raise GraphBuildError(
                        f"Unable to produce unique graph after {request.refill_budget + 1} attempts "
                        f"for pattern={planned_item.pattern_name}"
                    )
                continue

            emitted.append(record)
            accepted = True
            break

        if not accepted:
            raise GraphBuildError(f"Plan item could not be materialized: {planned_item}")

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

