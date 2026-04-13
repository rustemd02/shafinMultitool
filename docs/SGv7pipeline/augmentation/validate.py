from __future__ import annotations

import re

from .catalog import NOISE_TRANSFORM_IDS, RISKY_TRANSFORM_IDS, TRANSFORM_SPECS
from .slots import build_surface_anchor_snapshot, has_complete_graph_constraints


def normalize_augmented_source_text(text: str) -> str:
    value = text.replace("\r", " ").replace("\n", " ").replace("\t", " ")
    return value.strip()


def dedup_normalization_key(text: str) -> str:
    lowered = normalize_augmented_source_text(text).lower().replace("ё", "е")
    lowered = re.sub(r"\s+", " ", lowered)
    return lowered


def validate_augmented_record(
    record: dict[str, object],
    *,
    enable_risky: bool = False,
    existing_keys: set[str] | None = None,
) -> list[str]:
    reasons: list[str] = []
    source_text = normalize_augmented_source_text(str(record.get("source_text", "")))
    if not source_text:
        reasons.append("empty_or_whitespace")
        return reasons

    if record.get("generation_pass") != "augmentation":
        reasons.append("invalid_generation_pass")
    if not has_complete_graph_constraints(record):
        reasons.append("missing_graph_constraints_contract")
        return reasons

    graph_constraints = record["graph_constraints"]
    transform_chain = record.get("transform_chain")
    if not isinstance(transform_chain, list) or not transform_chain:
        reasons.append("unknown_transform_id")
        return reasons

    transform_ids = []
    for item in transform_chain:
        if not isinstance(item, dict):
            reasons.append("unknown_transform_id")
            continue
        transform_id = item.get("transform_id")
        if not isinstance(transform_id, str) or transform_id not in TRANSFORM_SPECS:
            reasons.append("unknown_transform_id")
            continue
        transform_ids.append(transform_id)

    if reasons:
        return sorted(set(reasons))

    mentions = build_surface_anchor_snapshot(source_text, graph_constraints)
    if graph_constraints["marked_objects"] and not mentions["marked_object_mentions"]:
        reasons.append("missing_marked_object_anchor")
    ordinal_bindings = graph_constraints["ordinal_bindings"]
    if ordinal_bindings and not mentions["ordinal_mentions"]:
        reasons.append("missing_ordinal_anchor")
    lowered = source_text.lower()
    for lemma in graph_constraints["must_keep_lemmas"]:
        if lemma.lower() not in lowered:
            reasons.append("critical_action_lemma_lost")
            break

    if graph_constraints["same_type_marker_conflict"]:
        cues = graph_constraints.get("required_disambiguation_cues", [])
        target_object_id = graph_constraints.get("target_object_id")
        if not isinstance(cues, list) or not all(isinstance(item, str) for item in cues):
            reasons.append("missing_graph_constraints_contract")
            return sorted(set(reasons))
        if not isinstance(target_object_id, str) or not target_object_id:
            reasons.append("missing_graph_constraints_contract")
            return sorted(set(reasons))
        if not any(cue.lower() in lowered for cue in cues):
            reasons.append("same_type_marker_disambiguation_lost")
        elif not any(
            mention["object_id"] == target_object_id and mention["matched_text"].lower() in {cue.lower() for cue in cues}
            for mention in mentions["marked_object_mentions"]
        ):
            reasons.append("same_type_marker_disambiguation_lost")

    risky_ids = [transform_id for transform_id in transform_ids if transform_id in RISKY_TRANSFORM_IDS]
    if risky_ids and not enable_risky:
        reasons.append("risky_transform_without_flag")
    if len(risky_ids) > 1:
        reasons.append("noise_budget_exceeded")

    noise_ids = [transform_id for transform_id in transform_ids if transform_id in NOISE_TRANSFORM_IDS]
    if len(noise_ids) > 1:
        reasons.append("noise_budget_exceeded")

    risk_flags = record.get("risk_flags", [])
    if not isinstance(risk_flags, list):
        reasons.append("invalid_risk_flags_schema")

    if existing_keys is not None and dedup_normalization_key(source_text) in existing_keys:
        reasons.append("duplicate_augmented_text")

    return sorted(set(reasons))
