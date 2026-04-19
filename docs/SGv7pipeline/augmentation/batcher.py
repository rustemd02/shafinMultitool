from __future__ import annotations

import random
from collections import defaultdict

from .catalog import NOISE_TRANSFORM_IDS, RISKY_TRANSFORM_IDS, TRANSFORM_SPECS, default_max_augmented_variants_per_parent, priority_for
from .config import AugmentationRequest, AugmentationResult, TransformPlanItem
from .metadata import build_accept_record, build_reject_record
from .morphology import apply_morphology_or_surface_transform
from .noise import apply_noise_transform
from .slots import has_complete_graph_constraints
from .validate import dedup_normalization_key, validate_augmented_record
from .writer import read_jsonl, write_jsonl


class AugmentationError(RuntimeError):
    pass


def _applicable_transform_ids(record: dict[str, object], *, enable_risky: bool) -> list[str]:
    text = str(record.get("source_text", ""))
    graph_constraints = record.get("graph_constraints", {})
    applicable: list[str] = []
    for transform_id in TRANSFORM_SPECS:
        if not enable_risky and transform_id in RISKY_TRANSFORM_IDS:
            continue
        if transform_id in NOISE_TRANSFORM_IDS:
            result = apply_noise_transform(text, transform_id)
        else:
            result = apply_morphology_or_surface_transform(text, transform_id, graph_constraints)
        if result is not None:
            applicable.append(transform_id)
    return applicable


def _compatible_noise_transform(record: dict[str, object], primary_transform_id: str) -> str | None:
    if primary_transform_id in NOISE_TRANSFORM_IDS:
        return None
    text = str(record.get("source_text", ""))
    for transform_id in (
        "noise.drop_final_punctuation",
        "noise.no_space_after_comma",
        "noise.drop_optional_comma",
        "noise.double_space",
    ):
        if apply_noise_transform(text, transform_id) is not None:
            return transform_id
    return None


def _recipe_candidates(record: dict[str, object], request: AugmentationRequest) -> list[tuple[str, tuple[str, ...], tuple[str, ...]]]:
    applicable = _applicable_transform_ids(record, enable_risky=request.enable_risky)
    difficulty_bucket = str(record["difficulty_bucket"])
    candidates: list[tuple[str, tuple[str, ...], tuple[str, ...]]] = []
    for transform_id in applicable:
        spec = TRANSFORM_SPECS[transform_id]
        risk_flags = ("risky_transform_requested",) if spec.safety_level == "risky" else ()
        noise_companion = _compatible_noise_transform(record, transform_id)
        transform_ids = (transform_id,) if noise_companion is None else (transform_id, noise_companion)
        candidates.append((f"recipe.{transform_id}", transform_ids, risk_flags))
    for transform_id in applicable:
        if transform_id in NOISE_TRANSFORM_IDS:
            candidates.append((f"recipe.{transform_id}", (transform_id,), ()))

    def sort_key(item: tuple[str, tuple[str, ...], tuple[str, ...]]) -> tuple[int, str]:
        transform_id = item[1][0]
        return priority_for(transform_id, difficulty_bucket=difficulty_bucket), item[0]

    grouped: dict[int, list[tuple[str, tuple[str, ...], tuple[str, ...]]]] = defaultdict(list)
    for item in candidates:
        grouped[sort_key(item)[0]].append(item)

    rng = random.Random(f"{request.seed}:{record.get('variant_id')}:{difficulty_bucket}")
    ordered: list[tuple[str, tuple[str, ...], tuple[str, ...]]] = []
    for priority in sorted(grouped):
        group = sorted(grouped[priority], key=lambda item: item[0])
        if len(group) > 1:
            rng.shuffle(group)
        ordered.extend(group)

    deduped: list[tuple[str, tuple[str, ...], tuple[str, ...]]] = []
    seen_signatures: set[tuple[str, ...]] = set()
    for recipe_id, transform_ids, risk_flags in ordered:
        if transform_ids in seen_signatures:
            continue
        seen_signatures.add(transform_ids)
        deduped.append((recipe_id, transform_ids, risk_flags))
    return deduped


def build_transform_plan(record: dict[str, object], request: AugmentationRequest) -> list[TransformPlanItem]:
    if record.get("generation_pass") != "base_paraphrase":
        return []
    if not has_complete_graph_constraints(record):
        return []

    difficulty_bucket = str(record["difficulty_bucket"])
    same_type_conflict = bool(record["graph_constraints"].get("same_type_marker_conflict"))
    max_variants = request.max_augmented_variants_per_parent
    if max_variants is None:
        max_variants = default_max_augmented_variants_per_parent(difficulty_bucket, enable_risky=request.enable_risky)

    candidates = _recipe_candidates(record, request)
    plan_items: list[TransformPlanItem] = []
    used_categories: set[str] = set()
    risky_count = 0
    for recipe_id, transform_ids, risk_flags in candidates:
        primary_spec = TRANSFORM_SPECS[transform_ids[0]]
        category = primary_spec.category
        if difficulty_bucket == "core" and primary_spec.safety_level == "risky":
            continue
        if difficulty_bucket == "core" and category in used_categories:
            continue
        if difficulty_bucket == "hard" and primary_spec.safety_level == "safe" and category in used_categories:
            continue
        if primary_spec.safety_level == "risky":
            if same_type_conflict:
                continue
            if not request.enable_risky or risky_count >= 1:
                continue
            risky_count += 1
        plan_items.append(
            TransformPlanItem(
                parent_record=record,
                parent_variant_id=str(record["variant_id"]),
                sample_id=str(record["sample_id"]),
                graph_id=str(record.get("graph_id", record["sample_id"])),
                difficulty_bucket=difficulty_bucket,  # type: ignore[arg-type]
                style_bucket=str(record["style_bucket"]),
                recipe_id=recipe_id,
                transform_ids=transform_ids,
                variant_ordinal=len(plan_items),
                risk_flags=risk_flags,
                policy_version=request.policy_version,
                seed=request.seed,
            )
        )
        used_categories.add(category)
        if len(plan_items) >= max_variants:
            break
    return plan_items


def _apply_transform_chain(plan_item: TransformPlanItem) -> tuple[str, list[dict[str, object]]] | None:
    text = str(plan_item.parent_record["source_text"])
    graph_constraints = plan_item.parent_record["graph_constraints"]
    chain: list[dict[str, object]] = []
    for transform_id in plan_item.transform_ids:
        if transform_id in NOISE_TRANSFORM_IDS:
            result = apply_noise_transform(text, transform_id)
        else:
            result = apply_morphology_or_surface_transform(text, transform_id, graph_constraints)
        if result is None:
            return None
        text, metadata = result
        chain.append(metadata)
    return text, chain


def generate_augmented_variants(request: AugmentationRequest) -> AugmentationResult:
    raw_records = read_jsonl(request.input_jsonl)
    print(
        "[augmentation] start: "
        f"raw_records={len(raw_records)} bucket={request.difficulty_bucket or 'all'} "
        f"max_augmented={request.max_augmented_variants_per_parent or 'auto'} risky={request.enable_risky}",
        flush=True,
    )
    accepted_records: list[dict[str, object]] = []
    reject_records: list[dict[str, object]] = []
    dedup_keys_by_parent: dict[str, set[str]] = defaultdict(set)
    total_rows = len(raw_records)
    progress_stride = max(1, total_rows // 20) if total_rows else 1

    for row_index, record in enumerate(raw_records, start=1):
        if request.difficulty_bucket is not None and record.get("difficulty_bucket") != request.difficulty_bucket:
            continue
        if record.get("generation_pass") != "base_paraphrase":
            reject_records.append(
                build_reject_record(
                    record,
                    reject_reason="invalid_generation_pass",
                    reject_stage="structural_preconditions",
                    seed=request.seed,
                )
            )
            continue
        if not has_complete_graph_constraints(record):
            reject_records.append(
                build_reject_record(
                    record,
                    reject_reason="missing_graph_constraints_contract",
                    reject_stage="structural_preconditions",
                    seed=request.seed,
                )
            )
            continue

        plan_items = build_transform_plan(record, request)
        if not plan_items:
            reject_records.append(
                build_reject_record(
                    record,
                    reject_reason="no_eligible_recipes",
                    reject_stage="planner",
                    seed=request.seed,
                )
            )
            continue

        for plan_item in plan_items:
            applied = _apply_transform_chain(plan_item)
            if applied is None:
                reject_records.append(
                    build_reject_record(
                        record,
                        reject_reason="transform_not_applicable",
                        reject_stage="apply_transform_chain",
                        seed=request.seed,
                        recipe_id=plan_item.recipe_id,
                    )
                )
                continue
            source_text, transform_chain = applied
            accept_record = build_accept_record(plan_item, source_text=source_text, transform_chain=transform_chain)
            reasons = validate_augmented_record(
                accept_record,
                enable_risky=request.enable_risky,
                existing_keys=dedup_keys_by_parent[plan_item.parent_variant_id],
            )
            if reasons:
                reject_records.append(
                    build_reject_record(
                        record,
                        reject_reason=";".join(reasons),
                        reject_stage="post_augmentation_validation",
                        seed=request.seed,
                        recipe_id=plan_item.recipe_id,
                        candidate_text=source_text,
                        transform_chain=transform_chain,
                    )
                )
                continue
            accepted_records.append(accept_record)
            dedup_keys_by_parent[plan_item.parent_variant_id].add(dedup_normalization_key(accept_record["source_text"]))
        if row_index == total_rows or row_index % progress_stride == 0:
            print(
                f"[augmentation] progress: {row_index}/{total_rows} parent rows processed",
                flush=True,
            )

    accepted_records.sort(key=lambda row: (row["difficulty_bucket"], row["sample_id"], row["variant_id"]))
    reject_records.sort(key=lambda row: (str(row.get("sample_id")), str(row.get("reject_stage")), str(row.get("reject_reason"))))
    write_jsonl(accepted_records, request.output_jsonl)
    if request.reject_log_jsonl is not None:
        write_jsonl(reject_records, request.reject_log_jsonl)
    print(
        f"[augmentation] done: accepted={len(accepted_records)} rejected={len(reject_records)}",
        flush=True,
    )
    return AugmentationResult(accepted_records=accepted_records, reject_records=reject_records)
