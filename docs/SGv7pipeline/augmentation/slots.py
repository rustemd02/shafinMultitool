from __future__ import annotations

import re
from dataclasses import dataclass


_ORDINAL_RE = re.compile(r"\b(первый|второй|третий)(?:\s+(акт[её]р(?:а)?))?\b", re.IGNORECASE)
_ACTOR_HEAD_RE = re.compile(r"\bакт(е|ё)р(?:а)?\b", re.IGNORECASE)
_CONNECTOR_RE = re.compile(r"\bпосле этого\b", re.IGNORECASE)


@dataclass(frozen=True)
class TextSlot:
    slot_type: str
    start: int
    end: int
    text: str


def has_complete_graph_constraints(record: dict[str, object]) -> bool:
    constraints = record.get("graph_constraints")
    if not isinstance(constraints, dict):
        return False
    marked_objects = constraints.get("marked_objects")
    if not isinstance(marked_objects, list):
        return False
    for obj in marked_objects:
        if not isinstance(obj, dict):
            return False
        if not isinstance(obj.get("id"), str):
            return False
        if not isinstance(obj.get("canonical_name"), str):
            return False
        aliases = obj.get("allowed_aliases")
        if not isinstance(aliases, list) or not all(isinstance(alias, str) for alias in aliases):
            return False
    ordinal_bindings = constraints.get("ordinal_bindings")
    if not isinstance(ordinal_bindings, dict):
        return False
    must_keep_lemmas = constraints.get("must_keep_lemmas")
    if not isinstance(must_keep_lemmas, list) or not all(isinstance(item, str) for item in must_keep_lemmas):
        return False
    return isinstance(constraints.get("same_type_marker_conflict"), bool)


def find_marked_object_mentions(text: str, graph_constraints: dict[str, object]) -> list[dict[str, object]]:
    mentions: list[dict[str, object]] = []
    for obj in graph_constraints.get("marked_objects", []):
        if not isinstance(obj, dict):
            continue
        aliases = sorted(
            {alias for alias in obj.get("allowed_aliases", []) if isinstance(alias, str) and alias},
            key=len,
            reverse=True,
        )
        for alias in aliases:
            pattern = re.compile(rf"(?<!\w){re.escape(alias)}(?!\w)", re.IGNORECASE)
            match = pattern.search(text)
            if match is None:
                continue
            mentions.append(
                {
                    "object_id": obj["id"],
                    "canonical_name": obj["canonical_name"],
                    "matched_text": match.group(0),
                    "alias_group": obj["canonical_name"],
                    "start": match.start(),
                    "end": match.end(),
                    "allowed_aliases": aliases,
                }
            )
            break
    mentions.sort(key=lambda item: (item["start"], item["object_id"]))
    return mentions


def find_ordinal_slots(text: str) -> list[TextSlot]:
    return [
        TextSlot(slot_type="ordinal_anchor", start=match.start(), end=match.end(), text=match.group(0))
        for match in _ORDINAL_RE.finditer(text)
    ]


def find_actor_head_slots(text: str) -> list[TextSlot]:
    return [
        TextSlot(slot_type="actor_head", start=match.start(), end=match.end(), text=match.group(0))
        for match in _ACTOR_HEAD_RE.finditer(text)
    ]


def find_connector_slots(text: str) -> list[TextSlot]:
    return [
        TextSlot(slot_type="connector_slot", start=match.start(), end=match.end(), text=match.group(0))
        for match in _CONNECTOR_RE.finditer(text)
    ]


def build_surface_anchor_snapshot(text: str, graph_constraints: dict[str, object]) -> dict[str, object]:
    mentions = find_marked_object_mentions(text, graph_constraints)
    return {
        "marked_object_mentions": [
            {
                "object_id": mention["object_id"],
                "matched_text": mention["matched_text"],
                "alias_group": mention["alias_group"],
            }
            for mention in mentions
        ],
        "ordinal_mentions": [slot.text.lower() for slot in find_ordinal_slots(text)],
        "critical_action_lemmas": [item.lower() for item in graph_constraints.get("must_keep_lemmas", []) if isinstance(item, str)],
    }
