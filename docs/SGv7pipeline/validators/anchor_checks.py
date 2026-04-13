from __future__ import annotations

import re

from augmentation.slots import build_surface_anchor_snapshot, has_complete_graph_constraints
from source_generation.prompt_builder import extract_required_surface_anchors


_DIALOGUE_LIKE_RE = re.compile(r"(?:^|\s)[А-ЯЁA-Z][А-ЯЁA-Zа-яёa-z]{1,20}:\s*\S")


def validate_anchor_checks(sample: dict[str, object], cir_record: dict[str, object]) -> list[str]:
    reasons: list[str] = []
    if not has_complete_graph_constraints(sample):
        return ["contract_missing_graph_constraints"]

    graph_constraints = sample["graph_constraints"]
    source_text = str(sample.get("source_text", ""))
    lowered = source_text.lower()
    anchors = extract_required_surface_anchors(cir_record)
    snapshot = build_surface_anchor_snapshot(source_text, graph_constraints)

    required_aliases = anchors["required_aliases"]
    if required_aliases and not any(alias.lower() in lowered for alias in required_aliases):
        reasons.append("semantic_marked_object_lost")

    required_ordinal_tokens = anchors["required_ordinal_tokens"]
    if required_ordinal_tokens and not all(token.lower() in lowered for token in required_ordinal_tokens):
        reasons.append("semantic_ordinal_anchor_lost")

    must_keep_lemmas = graph_constraints.get("must_keep_lemmas", [])
    if any(isinstance(lemma, str) and lemma.lower() not in lowered for lemma in must_keep_lemmas):
        reasons.append("semantic_unsupported_action_lost")

    if graph_constraints.get("same_type_marker_conflict"):
        cues = graph_constraints.get("required_disambiguation_cues", [])
        target_object_id = graph_constraints.get("target_object_id")
        cue_set = {str(cue).lower() for cue in cues if isinstance(cue, str)}
        if not cue_set or not isinstance(target_object_id, str):
            reasons.append("semantic_same_type_disambiguation_lost")
        elif not any(cue in lowered for cue in cue_set):
            reasons.append("semantic_same_type_disambiguation_lost")
        else:
            matched_mentions = snapshot["marked_object_mentions"]
            if not any(
                mention["object_id"] == target_object_id and str(mention["matched_text"]).lower() in cue_set
                for mention in matched_mentions
            ):
                reasons.append("semantic_exact_marker_id_conflict")

    has_talk = any(
        action.get("type") == "talk"
        for beat in cir_record.get("scene_graph", {}).get("beats", [])
        for action in beat.get("actions", [])
    )
    if not has_talk and _DIALOGUE_LIKE_RE.search(source_text):
        reasons.append("semantic_invented_dialogue")

    return sorted(set(reasons))
