from __future__ import annotations

from typing import Any


DOMINANT_PRIORITY = [
    "lost_marked_object",
    "same_type_marker_conflict",
    "ordinal_lost",
    "actor_disappeared",
    "beat_collapse",
    "chronology_rewrite",
    "unsupported_action_lost",
    "action_missing",
    "dangling_target",
    "minimal_valid_json",
    "policy_acceptability_drift",
    "merge_required",
    "repair_semantic_drift",
    "privacy_blocked",
]

_PRIORITY_INDEX = {label: index for index, label in enumerate(DOMINANT_PRIORITY)}


def choose_dominant_label(labels: list[str]) -> str:
    if not labels:
        return "policy_acceptability_drift"
    unique = sorted(set(labels), key=lambda label: _PRIORITY_INDEX.get(label, len(_PRIORITY_INDEX)))
    return unique[0]


def build_taxonomy_labels(
    *,
    event: dict[str, Any],
    low_quality_reason: str | None,
    unsupported_action_present: bool,
) -> list[str]:
    labels: list[str] = []
    selection = event.get("selection")
    decision = ""
    reason = ""
    if isinstance(selection, dict):
        decision = str(selection.get("decision", "")).strip()
        reason = str(selection.get("reason", "")).strip().lower()

    if decision == "merge":
        labels.append("merge_required")
    if "размеч" in reason or "marked" in reason:
        labels.append("lost_marked_object")
    if "ordinal" in reason or "перв" in reason or "втор" in reason or "трет" in reason:
        labels.append("ordinal_lost")
    if "target" in reason and ("без" in reason or "missing" in reason):
        labels.append("dangling_target")
    if "действ" in reason and ("меньше" in reason or "нет" in reason):
        labels.append("action_missing")

    if low_quality_reason in {"lqa_rule_1"}:
        labels.append("action_missing")
        labels.append("minimal_valid_json")
    if low_quality_reason in {"lqa_rule_2"}:
        labels.append("beat_collapse")
    if low_quality_reason in {"lqa_rule_3", "lqa_rule_4"}:
        labels.append("lost_marked_object")
    if low_quality_reason in {"lqa_rule_5"}:
        labels.append("ordinal_lost")
    if low_quality_reason in {"lqa_rule_6"}:
        labels.append("unsupported_action_lost")

    if unsupported_action_present and "unsupported_action_lost" not in labels:
        labels.append("unsupported_action_lost")

    if not labels:
        labels.append("policy_acceptability_drift")
    return sorted(set(labels), key=lambda label: _PRIORITY_INDEX.get(label, len(_PRIORITY_INDEX)))

