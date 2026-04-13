from __future__ import annotations

import re

from source_generation.prompt_builder import extract_required_surface_anchors


_SEQUENCE_MARKERS = ("затем", "после этого", "потом", "после чего")
_TOWARD_EACH_OTHER_HINTS = ("навстречу", "друг к другу")
_STOP_HINTS = ("останавли", "остановил", "стоп")
_PASS_BY_HINTS = ("проход", "мимо")
_RUN_HINTS = ("беж", "бежать")


def _normalized(text: str) -> str:
    lowered = text.lower().replace("ё", "е")
    lowered = re.sub(r"\s+", " ", lowered)
    return lowered.strip()


def required_anchor_count(sample: dict[str, object], cir_record: dict[str, object]) -> int:
    anchors = extract_required_surface_anchors(cir_record)
    marked_count = 1 if anchors["required_aliases"] else 0
    ordinal_count = len(anchors["required_ordinal_tokens"])
    must_keep_lemma_count = len(sample.get("graph_constraints", {}).get("must_keep_lemmas", []))
    return marked_count + ordinal_count + must_keep_lemma_count


def deterministic_chronology_cue_passed(sample: dict[str, object], cir_record: dict[str, object]) -> bool:
    text = _normalized(str(sample.get("source_text", "")))
    beat_count = int(cir_record["budgets"]["beat_count"])
    if beat_count <= 1:
        return True
    if any(marker in text for marker in _SEQUENCE_MARKERS):
        return True

    phase_hits = 0
    if "toward_each_other" in text or any(hint in text for hint in _TOWARD_EACH_OTHER_HINTS):
        phase_hits += 1
    if any(hint in text for hint in _STOP_HINTS):
        phase_hits += 1
    if any(hint in text for hint in _PASS_BY_HINTS):
        phase_hits += 1
    if any(hint in text for hint in _RUN_HINTS):
        phase_hits += 1
    for lemma in sample.get("graph_constraints", {}).get("must_keep_lemmas", []):
        if isinstance(lemma, str) and lemma.lower() in text:
            phase_hits += 1
            break
    return phase_hits >= min(2, beat_count)


def deterministic_beat_collapse(cir_record: dict[str, object], sample: dict[str, object]) -> bool:
    text = _normalized(str(sample.get("source_text", "")))
    beat_count = int(cir_record["budgets"]["beat_count"])
    if beat_count <= 1:
        return False

    phases = [beat.get("phase") for beat in cir_record.get("scene_graph", {}).get("beats", [])]
    if "stop_near_object" in phases and not any(hint in text for hint in _STOP_HINTS):
        return True
    if "pass_by_object" in phases and not any(hint in text for hint in _PASS_BY_HINTS):
        return True
    has_described_action = any(
        action.get("type") == "described_action"
        for beat in cir_record.get("scene_graph", {}).get("beats", [])
        for action in beat.get("actions", [])
    )
    if has_described_action:
        lemmas = [str(item).lower() for item in sample.get("graph_constraints", {}).get("must_keep_lemmas", [])]
        if lemmas and not any(lemma in text for lemma in lemmas):
            return True

    if not deterministic_chronology_cue_passed(sample, cir_record):
        return True
    return False


def recoverability_overcompressed(sample: dict[str, object], cir_record: dict[str, object]) -> bool:
    source_token_count = len(str(sample.get("source_text", "")).split())
    beat_count = int(cir_record["budgets"]["beat_count"])
    threshold = max(4, beat_count * 3 + required_anchor_count(sample, cir_record))
    return source_token_count < threshold


def compute_recoverability_score(
    sample: dict[str, object],
    cir_record: dict[str, object],
    *,
    critic_result: dict[str, object],
    graph_reasons: list[str],
) -> tuple[int, str]:
    anchors = extract_required_surface_anchors(cir_record)
    graph_constraints = sample.get("graph_constraints", {})
    lowered = _normalized(str(sample.get("source_text", "")))

    anchor_recall_score = 0
    if not anchors["required_aliases"] or any(alias.lower() in lowered for alias in anchors["required_aliases"]):
        anchor_recall_score += 20
    if not anchors["required_ordinal_tokens"] or all(token.lower() in lowered for token in anchors["required_ordinal_tokens"]):
        anchor_recall_score += 10
    if not graph_constraints.get("same_type_marker_conflict") or not {"semantic_same_type_disambiguation_lost", "semantic_exact_marker_id_conflict"} & set(graph_reasons):
        anchor_recall_score += 5

    chronology_score = 0
    if int(cir_record["budgets"]["beat_count"]) == 1 or deterministic_chronology_cue_passed(sample, cir_record):
        chronology_score += 10
    if not deterministic_beat_collapse(cir_record, sample):
        chronology_score += 10
    if bool(critic_result.get("chronology_preserved")):
        chronology_score += 5

    unsupported_action_score = 0
    must_keep_lemmas = [str(item).lower() for item in graph_constraints.get("must_keep_lemmas", [])]
    if not must_keep_lemmas or all(lemma in lowered for lemma in must_keep_lemmas):
        unsupported_action_score += 10
    if bool(critic_result.get("unsupported_action_preserved")):
        unsupported_action_score += 5

    target_integrity_score = 0
    if not {"graph_dangling_target", "graph_missing_actor", "graph_missing_object"} & set(graph_reasons):
        target_integrity_score += 5
    if bool(critic_result.get("object_grounding_preserved")):
        target_integrity_score += 5
    if bool(critic_result.get("ordinal_binding_preserved")) or not anchors["required_ordinal_tokens"]:
        target_integrity_score += 5

    compression_budget_score = 0
    source_token_count = len(str(sample.get("source_text", "")).split())
    difficulty_bucket = str(sample.get("difficulty_bucket", cir_record["difficulty_bucket"]))
    if (difficulty_bucket == "core" and 4 <= source_token_count <= 32) or (
        difficulty_bucket == "hard" and 4 <= source_token_count <= 48
    ):
        compression_budget_score += 5
    if not recoverability_overcompressed(sample, cir_record):
        compression_budget_score += 5

    total = (
        anchor_recall_score
        + chronology_score
        + unsupported_action_score
        + target_integrity_score
        + compression_budget_score
    )
    if total >= 85:
        return total, "high"
    if total >= 65:
        return total, "borderline"
    return total, "low"
