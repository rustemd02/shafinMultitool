from __future__ import annotations

import os
from collections import defaultdict
from typing import Iterable

from cir_contract.contracts import validate_record
from cir_contract.contracts.cir_types import CIRRecord

from .config import Paraphraser, SourceGenerationRequest, SourceGenerationResult, StyleBucket, VariantPlanItem
from .filters import dedup_normalization_key, evaluate_candidate_text, normalize_persisted_source_text
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
        ("ноутбук", "ноут"),
        ("телевизор", "телик"),
    )

    _short_replacements = (
        ("2 актёра", "два актёра"),
        ("идут навстречу друг другу", "идут навстречу"),
        ("после этого", "потом"),
        ("и ", ""),
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
            text = f"{text.rstrip('.')} у {plan_item.required_aliases[0]}."
        if plan_item.required_disambiguation_cues and not any(
            cue.lower() in text.lower() for cue in plan_item.required_disambiguation_cues
        ):
            cue = plan_item.required_disambiguation_cues[0]
            if cue.lower() not in text.lower():
                text = f"{text.rstrip('.')} Второй остаётся у {cue}."
        if plan_item.required_ordinal_tokens and not all(
            token.lower() in text.lower() for token in plan_item.required_ordinal_tokens
        ):
            prefix = ", ".join(token.capitalize() for token in plan_item.required_ordinal_tokens)
            text = f"{prefix}: {text[0].lower() + text[1:]}" if text else prefix

        return normalize_persisted_source_text(text)


def _prompt_payload_for(record: CIRRecord) -> dict[str, object]:
    return summarize_graph_for_source_prompt(record)


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
        for ordinal, style_bucket in enumerate(planned_style_buckets(max_variants_per_graph=request.max_variants_per_graph)):
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


def generate_source_variants(
    request: SourceGenerationRequest,
    *,
    paraphraser: Paraphraser | None = None,
) -> SourceGenerationResult:
    plan_items = build_variant_plan(request)
    paraphraser = paraphraser or _default_paraphraser(request)

    accepted_records: list[dict[str, object]] = []
    reject_records: list[dict[str, object]] = []
    dedup_keys_by_graph: dict[str, set[str]] = defaultdict(set)
    required_clean_seen: set[str] = set()

    for batch in _iter_batches(plan_items, request.batch_size):
        for plan_item in batch:
            last_reject_reason = ""
            accepted = False
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
                    existing_keys=dedup_keys_by_graph[plan_item.graph_id],
                )
                if reasons:
                    last_reject_reason = reasons[0]
                    reject_records.append(
                        build_reject_record(
                            plan_item,
                            candidate_text=candidate,
                            reject_reason=";".join(reasons),
                            attempt_index=attempt_index,
                        )
                    )
                    continue

                accept_record = build_accept_record(plan_item, candidate)
                accepted_records.append(accept_record)
                dedup_keys_by_graph[plan_item.graph_id].add(dedup_normalization_key(accept_record["source_text"]))
                if plan_item.style_bucket == "clean":
                    required_clean_seen.add(plan_item.graph_id)
                accepted = True
                break

            if not accepted and plan_item.style_bucket == "clean":
                raise SourceGenerationError(
                    f"Required clean variant could not be generated for sample_id={plan_item.sample_id}"
                )

    accepted_records.sort(key=lambda record: (record["difficulty_bucket"], record["pattern_name"], record["sample_id"], record["style_bucket"]))
    reject_records.sort(
        key=lambda record: (record["sample_id"], record["style_bucket"], record["attempt_index"], record["reject_reason"])
    )
    write_jsonl(accepted_records, request.output_jsonl)
    if request.reject_log_jsonl is not None:
        write_jsonl(reject_records, request.reject_log_jsonl)

    expected_clean_graphs = {
        plan_item.graph_id
        for plan_item in plan_items
        if plan_item.style_bucket == "clean"
    }
    if required_clean_seen != expected_clean_graphs:
        missing = sorted(expected_clean_graphs - required_clean_seen)
        raise SourceGenerationError(f"Missing clean variants for graphs: {missing}")

    return SourceGenerationResult(
        accepted_records=accepted_records,
        reject_records=reject_records,
    )
