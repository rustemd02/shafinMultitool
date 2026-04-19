from __future__ import annotations

import os
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Iterable

from cir_contract.contracts import validate_record
from cir_contract.contracts.cir_types import CIRRecord

from .config import Paraphraser, SourceGenerationRequest, SourceGenerationResult, StyleBucket, VariantPlanItem
from .filters import (
    dedup_normalization_key,
    evaluate_candidate_text,
    normalize_persisted_source_text,
    scrub_technical_identifier_literals,
)
from .metadata import build_accept_record, build_reject_record
from .prompt_builder import (
    build_source_prompt,
    extract_required_surface_anchors,
    summarize_graph_for_source_prompt,
)
from .style_policy import STYLE_RETRY_BUDGETS, planned_style_buckets
from .writer import read_jsonl, write_jsonl


class SourceGenerationError(RuntimeError):
    pass


_LOW_VARIANCE_PATTERN_MAX_VARIANTS = {
    "dialogue_only": 1,
    "toward_each_other": 1,
}

_SURFACE_PREFIXES = ("у ", "около ", "рядом с ", "мимо ", "возле ")
_GENITIVE_ENDINGS = ("а", "я", "ы", "и")
_INSTRUMENTAL_ENDINGS = ("ом", "ем", "ой", "ою", "ею", "ью", "ами", "ями")


def _best_anchor_phrase(candidates: tuple[str, ...] | list[str]) -> str | None:
    normalized = [item.strip() for item in candidates if isinstance(item, str) and item.strip()]
    if not normalized:
        return None

    for alias in normalized:
        if alias.lower().startswith(_SURFACE_PREFIXES):
            return alias

    for alias in normalized:
        last_word = alias.split()[-1].lower()
        if last_word.endswith(_GENITIVE_ENDINGS):
            return f"у {alias}"

    for alias in normalized:
        last_word = alias.split()[-1].lower()
        if last_word.endswith(_INSTRUMENTAL_ENDINGS):
            return f"рядом с {alias}"

    return f"у {normalized[0]}"


class OpenAIParaphraser:
    def __init__(self, *, model_name: str) -> None:
        self.model_name = model_name
        try:
            from openai import OpenAI
        except ImportError as exc:
            raise SourceGenerationError("openai package is required for paraphraser_backend=openai") from exc

        kwargs: dict[str, object] = {}
        api_key = os.environ.get("OPENAI_API_KEY")
        if api_key:
            kwargs["api_key"] = api_key
        base_url = os.environ.get("OPENAI_BASE_URL")
        if base_url:
            kwargs["base_url"] = base_url
        self._client = OpenAI(**kwargs)

    def generate(self, *, plan_item: VariantPlanItem, system_prompt: str, user_prompt: str) -> str:
        response = self._client.chat.completions.create(
            model=self.model_name,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
        )
        return (response.choices[0].message.content or "").strip()


class HeuristicParaphraser:
    _colloquial_replacements = (
        ("идут навстречу друг другу", "идут друг к другу"),
        ("проходят мимо", "идут мимо"),
        ("останавливаются", "тормозят"),
        ("подходит к", "идёт к"),
        ("остаётся у", "стоит у"),
        ("рабочий компьютер", "комп"),
        ("компьютер", "комп"),
        ("телевизор", "телик"),
    )

    _short_replacements = (
        ("2 актёра", "два актёра"),
        ("идут навстречу друг другу", "идут навстречу"),
        ("после этого", "потом"),
    )

    def generate(self, *, plan_item: VariantPlanItem, system_prompt: str, user_prompt: str) -> str:
        template = plan_item.canonical_source_template or str(plan_item.prompt_payload["graph_summary"])
        text = template
        if plan_item.style_bucket == "colloquial":
            for source, target in self._colloquial_replacements:
                text = text.replace(source, target)
        elif plan_item.style_bucket == "user_short":
            for source, target in self._short_replacements:
                text = text.replace(source, target)
            text = text.replace(", ", ", ")
            text = text.rstrip(".")

        # Keep at least one Russian marker alias visible for track-4 cheap checks.
        if plan_item.required_aliases and not any(alias.lower() in text.lower() for alias in plan_item.required_aliases):
            anchor_phrase = _best_anchor_phrase(plan_item.required_aliases)
            if anchor_phrase is not None:
                text = f"{text.rstrip('.')} {anchor_phrase}."
        if plan_item.required_disambiguation_cues and not any(
            cue.lower() in text.lower() for cue in plan_item.required_disambiguation_cues
        ):
            cue_phrase = _best_anchor_phrase(plan_item.required_disambiguation_cues)
            if cue_phrase is not None and cue_phrase.lower() not in text.lower():
                text = f"{text.rstrip('.')} Второй остаётся {cue_phrase}."
        if plan_item.required_ordinal_tokens and not all(
            token.lower() in text.lower() for token in plan_item.required_ordinal_tokens
        ):
            prefix = ", ".join(token.capitalize() for token in plan_item.required_ordinal_tokens)
            text = f"{prefix}: {text[0].lower() + text[1:]}" if text else prefix

        text = scrub_technical_identifier_literals(text)
        return normalize_persisted_source_text(text)


def _prompt_payload_for(record: CIRRecord) -> dict[str, object]:
    return summarize_graph_for_source_prompt(record)


def _variant_cap_for_record(record: CIRRecord, request: SourceGenerationRequest) -> int | None:
    base_limit = request.max_variants_per_graph
    if base_limit is None:
        base_limit = 3

    pattern_name = str(record.get("pattern_name", ""))
    tags = {str(item) for item in record.get("semantic_tags", [])}
    beat_count = len(record.get("scene_graph", {}).get("beats", []))

    if pattern_name in _LOW_VARIANCE_PATTERN_MAX_VARIANTS:
        return min(base_limit, _LOW_VARIANCE_PATTERN_MAX_VARIANTS[pattern_name])

    if beat_count <= 1 and not (tags & {"marked_object", "same_type_markers", "ordinal_reference", "described_action"}):
        return min(base_limit, 1)

    if (
        beat_count <= 2
        and str(record.get("difficulty_bucket", "")) == "core"
        and not (tags & {"same_type_markers", "described_action"})
    ):
        return min(base_limit, 2)

    return base_limit


def build_variant_plan(request: SourceGenerationRequest) -> list[VariantPlanItem]:
    raw_records = read_jsonl(request.input_jsonl)
    records: list[CIRRecord] = []
    for raw in raw_records:
        record = raw  # runtime-validated below
        validate_record(record)
        if request.difficulty_bucket is not None and record["difficulty_bucket"] != request.difficulty_bucket:
            continue
        records.append(record)
    if request.max_graphs is not None:
        records = records[: request.max_graphs]

    plan_items: list[VariantPlanItem] = []
    for record in records:
        payload = _prompt_payload_for(record)
        anchors = extract_required_surface_anchors(record)
        canonical_source_template = str(payload["canonical_source_template"])
        variant_cap = _variant_cap_for_record(record, request)
        for ordinal, style_bucket in enumerate(planned_style_buckets(max_variants_per_graph=variant_cap)):
            plan_items.append(
                VariantPlanItem(
                    record=record,
                    sample_id=record["sample_id"],
                    graph_id=record["sample_id"],
                    pattern_name=record["pattern_name"],
                    difficulty_bucket=record["difficulty_bucket"],
                    graph_seed=record["graph_seed"],
                    style_bucket=style_bucket,
                    variant_ordinal=ordinal,
                    prompt_payload=payload,
                    required_aliases=anchors["required_aliases"],
                    required_ordinal_tokens=anchors["required_ordinal_tokens"],
                    required_disambiguation_cues=anchors["required_disambiguation_cues"],
                    canonical_source_template=canonical_source_template,
                    prompt_template_version=request.prompt_template_version,
                    source_policy_version=request.policy_version,
                    model_name=request.model_name,
                    seed=request.seed,
                )
            )
    return plan_items


def _default_paraphraser(request: SourceGenerationRequest) -> Paraphraser:
    if request.paraphraser_backend == "heuristic":
        return HeuristicParaphraser()
    return OpenAIParaphraser(model_name=request.model_name)


def _iter_batches(plan_items: list[VariantPlanItem], batch_size: int) -> Iterable[list[VariantPlanItem]]:
    if batch_size <= 0:
        batch_size = len(plan_items) or 1
    grouped: dict[StyleBucket, list[VariantPlanItem]] = defaultdict(list)
    for item in plan_items:
        grouped[item.style_bucket].append(item)
    for bucket in ("clean", "colloquial", "user_short"):
        items = grouped.get(bucket, [])
        for start in range(0, len(items), batch_size):
            yield items[start:start + batch_size]


def _generate_single_plan_item(
    plan_item: VariantPlanItem,
    *,
    paraphraser: Paraphraser,
    fallback_paraphraser: Paraphraser | None,
    existing_keys: set[str],
) -> tuple[dict[str, object] | None, list[dict[str, object]]]:
    local_reject_records: list[dict[str, object]] = []
    accepted_record: dict[str, object] | None = None
    last_reject_reason = ""

    for attempt_index in range(STYLE_RETRY_BUDGETS[plan_item.style_bucket]):
        system_prompt, user_prompt = build_source_prompt(
            plan_item,
            previous_reject_reason=last_reject_reason or None,
        )
        candidate = paraphraser.generate(
            plan_item=plan_item,
            system_prompt=system_prompt,
            user_prompt=user_prompt,
        )
        reasons = evaluate_candidate_text(
            candidate,
            plan_item,
            existing_keys=existing_keys,
        )
        if reasons:
            last_reject_reason = reasons[0]
            local_reject_records.append(
                build_reject_record(
                    plan_item,
                    candidate_text=candidate,
                    reject_reason=";".join(reasons),
                    attempt_index=attempt_index,
                )
            )
            continue

        accepted_record = build_accept_record(plan_item, candidate)
        return accepted_record, local_reject_records

    if plan_item.style_bucket == "clean" and fallback_paraphraser is not None:
        fallback_candidate = fallback_paraphraser.generate(
            plan_item=plan_item,
            system_prompt="",
            user_prompt="",
        )
        fallback_reasons = evaluate_candidate_text(
            fallback_candidate,
            plan_item,
            existing_keys=existing_keys,
        )
        if fallback_reasons:
            local_reject_records.append(
                build_reject_record(
                    plan_item,
                    candidate_text=fallback_candidate,
                    reject_reason=";".join(fallback_reasons),
                    attempt_index=STYLE_RETRY_BUDGETS[plan_item.style_bucket],
                    reject_stage="clean_fallback_reject",
                )
            )
        else:
            accepted_record = build_accept_record(plan_item, fallback_candidate)
            accepted_record["acceptance"]["clean_fallback_used"] = True
            accepted_record["acceptance"]["fallback_backend"] = "heuristic"
            return accepted_record, local_reject_records

    if plan_item.style_bucket == "clean":
        local_reject_records.append(
            build_reject_record(
                plan_item,
                candidate_text="",
                reject_reason=f"required_clean_variant_generation_failed:{last_reject_reason or 'no_accepted_candidate'}",
                attempt_index=STYLE_RETRY_BUDGETS[plan_item.style_bucket] + (1 if fallback_paraphraser is not None else 0),
                reject_stage="clean_required_unmet",
            )
        )
        return None, local_reject_records
    return None, local_reject_records


def generate_source_variants(
    request: SourceGenerationRequest,
    *,
    paraphraser: Paraphraser | None = None,
) -> SourceGenerationResult:
    plan_items = build_variant_plan(request)
    print(
        "[source_generation] start: "
        f"plan_items={len(plan_items)} backend={request.paraphraser_backend} "
        f"workers={request.paraphraser_workers} batch_size={request.batch_size}",
        flush=True,
    )
    paraphraser = paraphraser or _default_paraphraser(request)
    fallback_paraphraser = (
        HeuristicParaphraser()
        if request.paraphraser_backend == "openai" and request.enable_clean_fallback
        else None
    )

    accepted_records: list[dict[str, object]] = []
    reject_records: list[dict[str, object]] = []
    dedup_keys_by_graph: dict[str, set[str]] = defaultdict(set)
    required_clean_seen: set[str] = set()
    total_items = len(plan_items)
    processed_items = 0
    progress_stride = max(1, total_items // 20) if total_items else 1

    batches = list(_iter_batches(plan_items, request.batch_size))
    for batch_index, batch in enumerate(batches, start=1):
        print(
            f"[source_generation] batch {batch_index}/{len(batches)}: size={len(batch)}",
            flush=True,
        )
        unique_graphs_in_batch = len({item.graph_id for item in batch}) == len(batch)
        use_parallel_openai = (
            request.paraphraser_backend == "openai"
            and request.paraphraser_workers > 1
            and len(batch) > 1
            and unique_graphs_in_batch
        )

        if use_parallel_openai:
            worker_count = min(request.paraphraser_workers, len(batch))
            print(
                f"[source_generation] parallel paraphraser enabled: workers={worker_count}, batch={len(batch)}",
                flush=True,
            )
            with ThreadPoolExecutor(max_workers=worker_count, thread_name_prefix="sgv7-paraphraser") as executor:
                future_to_item = {
                    executor.submit(
                        _generate_single_plan_item,
                        plan_item,
                        paraphraser=paraphraser,
                        fallback_paraphraser=fallback_paraphraser,
                        existing_keys=set(dedup_keys_by_graph[plan_item.graph_id]),
                    ): plan_item
                    for plan_item in batch
                }
                for future in as_completed(future_to_item):
                    plan_item = future_to_item[future]
                    accept_record, local_rejects = future.result()
                    reject_records.extend(local_rejects)
                    if accept_record is not None:
                        accepted_records.append(accept_record)
                        dedup_keys_by_graph[plan_item.graph_id].add(dedup_normalization_key(accept_record["source_text"]))
                        if plan_item.style_bucket == "clean":
                            required_clean_seen.add(plan_item.graph_id)
                    processed_items += 1
                    if processed_items == total_items or processed_items % progress_stride == 0:
                        print(
                            f"[source_generation] progress: {processed_items}/{total_items} plan items processed",
                            flush=True,
                        )
        else:
            for plan_item in batch:
                accept_record, local_rejects = _generate_single_plan_item(
                    plan_item,
                    paraphraser=paraphraser,
                    fallback_paraphraser=fallback_paraphraser,
                    existing_keys=set(dedup_keys_by_graph[plan_item.graph_id]),
                )
                reject_records.extend(local_rejects)
                if accept_record is not None:
                    accepted_records.append(accept_record)
                    dedup_keys_by_graph[plan_item.graph_id].add(dedup_normalization_key(accept_record["source_text"]))
                    if plan_item.style_bucket == "clean":
                        required_clean_seen.add(plan_item.graph_id)
                processed_items += 1
                if processed_items == total_items or processed_items % progress_stride == 0:
                    print(
                        f"[source_generation] progress: {processed_items}/{total_items} plan items processed",
                        flush=True,
                    )

    expected_clean_graphs = {
        plan_item.graph_id
        for plan_item in plan_items
        if plan_item.style_bucket == "clean"
    }
    if required_clean_seen != expected_clean_graphs:
        missing = sorted(expected_clean_graphs - required_clean_seen)
        if missing:
            missing_set = set(missing)
            accepted_before = len(accepted_records)
            accepted_records = [
                record
                for record in accepted_records
                if str(record.get("graph_id", "")) not in missing_set
            ]
            dropped_non_clean = accepted_before - len(accepted_records)
            print(
                "[source_generation] warning: missing required clean variants; "
                f"dropped_graphs={len(missing)} dropped_records={dropped_non_clean}",
                flush=True,
            )

    accepted_records.sort(key=lambda record: (record["difficulty_bucket"], record["pattern_name"], record["sample_id"], record["style_bucket"]))
    reject_records.sort(
        key=lambda record: (record["sample_id"], record["style_bucket"], record["attempt_index"], record["reject_reason"])
    )
    write_jsonl(accepted_records, request.output_jsonl)
    if request.reject_log_jsonl is not None:
        write_jsonl(reject_records, request.reject_log_jsonl)
    print(
        f"[source_generation] done: accepted={len(accepted_records)} rejected={len(reject_records)}",
        flush=True,
    )

    return SourceGenerationResult(
        accepted_records=accepted_records,
        reject_records=reject_records,
    )
