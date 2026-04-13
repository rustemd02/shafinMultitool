from __future__ import annotations

from collections import Counter

from cir_contract.contracts.cir_types import CIRRecord, ObjectNode

from .config import VariantPlanItem
from .filters import normalize_persisted_source_text
from .prompt_builder import (
    _same_type_disambiguation_payload,
    _target_marked_object_id,
    expand_surface_forms,
    localize_described_action,
    localized_object_aliases,
)


def _localized_allowed_aliases(obj: ObjectNode) -> list[str]:
    aliases: set[str] = set()
    for alias in localized_object_aliases(obj):
        aliases.update(form.lower() for form in expand_surface_forms(alias))
    return sorted(aliases)


def _must_keep_lemmas(record: CIRRecord) -> list[str]:
    lemmas: list[str] = []
    seen: set[str] = set()
    for beat in record["scene_graph"]["beats"]:
        for action in beat.get("actions", []):
            if action.get("type") != "described_action":
                continue
            payload = action.get("described_action", {})
            candidates = [
                payload.get("source_lemma_hint"),
                payload.get("canonical_text"),
            ]
            for candidate in candidates:
                if not isinstance(candidate, str) or not candidate.strip():
                    continue
                localized = localize_described_action(candidate).strip().lower()
                if localized and localized not in seen:
                    seen.add(localized)
                    lemmas.append(localized)
                if localized:
                    break
    return lemmas


def build_graph_constraints(record: CIRRecord) -> dict[str, object]:
    marked_objects = [obj for obj in record["scene_graph"]["objects"] if obj["marker_binding"]["kind"] == "marked"]
    counts = Counter(obj["type"] for obj in marked_objects)
    same_type_payload = _same_type_disambiguation_payload(record)
    target_object_id = _target_marked_object_id(record)
    required_disambiguation_cues: list[str] = []
    if same_type_payload is not None:
        for entry in same_type_payload["objects"]:
            if entry["is_target"]:
                required_disambiguation_cues = list(entry["fallback_cues"])
                break
    return {
        "ordinal_bindings": dict(record["scene_graph"]["reference_bindings"].get("ordinal_map", {})),
        "marked_objects": [
            {
                "id": obj["id"],
                "canonical_name": (localized_object_aliases(obj) or [obj["id"]])[0].lower(),
                "allowed_aliases": _localized_allowed_aliases(obj),
            }
            for obj in marked_objects
        ],
        "must_keep_lemmas": _must_keep_lemmas(record),
        "same_type_marker_conflict": any(count >= 2 for count in counts.values()),
        "target_object_id": target_object_id,
        "required_disambiguation_cues": required_disambiguation_cues,
    }


def build_accept_record(plan_item: VariantPlanItem, source_text: str) -> dict[str, object]:
    normalized = normalize_persisted_source_text(source_text)
    return {
        "sample_id": plan_item.sample_id,
        "variant_id": f"{plan_item.sample_id}-{plan_item.style_bucket}-{plan_item.variant_ordinal:02d}",
        "graph_id": plan_item.graph_id,
        "pattern_name": plan_item.pattern_name,
        "difficulty_bucket": plan_item.difficulty_bucket,
        "style_bucket": plan_item.style_bucket,
        "source_text": normalized,
        "model_name": plan_item.model_name,
        "prompt_template_version": plan_item.prompt_template_version,
        "source_policy_version": plan_item.source_policy_version,
        "generation_pass": "base_paraphrase",
        "attempt_index": 0,
        "seed": plan_item.seed,
        "graph_constraints": build_graph_constraints(plan_item.record),
        "acceptance": {
            "lexical_checks_passed": True,
            "needs_semantic_critic": True,
        },
    }


def build_reject_record(
    plan_item: VariantPlanItem,
    *,
    candidate_text: str,
    reject_reason: str,
    attempt_index: int,
    reject_stage: str = "lexical_or_format_reject",
) -> dict[str, object]:
    return {
        "sample_id": plan_item.sample_id,
        "graph_id": plan_item.graph_id,
        "pattern_name": plan_item.pattern_name,
        "difficulty_bucket": plan_item.difficulty_bucket,
        "style_bucket": plan_item.style_bucket,
        "model_name": plan_item.model_name,
        "prompt_template_version": plan_item.prompt_template_version,
        "source_policy_version": plan_item.source_policy_version,
        "generation_pass": "base_paraphrase",
        "attempt_index": attempt_index,
        "reject_stage": reject_stage,
        "reject_reason": reject_reason,
        "candidate_text": candidate_text,
        "seed": plan_item.seed,
    }
