from __future__ import annotations

import re

from .slots import find_actor_head_slots, find_connector_slots, find_marked_object_mentions, find_ordinal_slots

_NOUN_CASES = {
    "стул": ("стул", "стула", "стулу", "стулом"),
    "стол": ("стол", "стола", "столу", "столом"),
    "ноутбук": ("ноутбук", "ноутбука", "ноутбуку", "ноутбуком"),
    "ноут": ("ноут", "ноута", "ноуту", "ноутом"),
    "комп": ("комп", "компа", "компу", "компом"),
    "компьютер": ("компьютер", "компьютера", "компьютеру", "компьютером"),
}

_YO_REPLACEMENTS = {
    "актер": "актёр",
    "актера": "актёра",
    "еще": "ещё",
}

_REMOVE_YO_REPLACEMENTS = {value: key for key, value in _YO_REPLACEMENTS.items()}
_ORDINAL_NUMERIC = {"первый": "1-й", "второй": "2-й", "третий": "3-й"}


def _replace_once(text: str, start: int, end: int, replacement: str) -> str:
    return text[:start] + replacement + text[end:]


def _preserve_case(template: str, replacement: str) -> str:
    if template.isupper():
        return replacement.upper()
    if template[:1].isupper():
        return replacement.capitalize()
    return replacement


def _form_for_case(canonical_name: str, case_name: str) -> str | None:
    normalized = canonical_name.lower().strip()
    if normalized.startswith("левый "):
        noun = normalized.split(" ", 1)[1]
        if noun in _NOUN_CASES:
            index = 1 if case_name == "genitive" else 2
            prefix = "левого" if case_name == "genitive" else "левому"
            return f"{prefix} {_NOUN_CASES[noun][index]}"
    if normalized.startswith("правый "):
        noun = normalized.split(" ", 1)[1]
        if noun in _NOUN_CASES:
            index = 1 if case_name == "genitive" else 2
            prefix = "правого" if case_name == "genitive" else "правому"
            return f"{prefix} {_NOUN_CASES[noun][index]}"
    if normalized in _NOUN_CASES:
        index = 1 if case_name == "genitive" else 2
        return _NOUN_CASES[normalized][index]
    return None


def _replace_marked_object_case(
    text: str,
    graph_constraints: dict[str, object],
    *,
    prepositions: tuple[str, ...],
    case_name: str,
    transform_id: str,
) -> tuple[str, dict[str, object]] | None:
    lowered = text.lower()
    for mention in find_marked_object_mentions(text, graph_constraints):
        prefix_start = max(0, mention["start"] - 16)
        prefix = lowered[prefix_start:mention["start"]]
        if not any(prefix.endswith(f"{prep} ") for prep in prepositions):
            continue
        replacement = _form_for_case(str(mention["canonical_name"]), case_name)
        if not replacement:
            continue
        if replacement not in mention["allowed_aliases"]:
            continue
        if mention["matched_text"].lower() == replacement:
            continue
        rendered = _preserve_case(str(mention["matched_text"]), replacement)
        return (
            _replace_once(text, mention["start"], mention["end"], rendered),
            {
                "transform_id": transform_id,
                "class": "marked_object_morphology",
                "safety_level": "safe",
                "slot_type": "marked_object_anchor",
                "slot_index": mention["start"],
                "before": mention["matched_text"],
                "after": rendered,
            },
        )
    return None


def apply_morphology_or_surface_transform(
    text: str,
    transform_id: str,
    graph_constraints: dict[str, object],
) -> tuple[str, dict[str, object]] | None:
    if transform_id == "morph.marked_object.case_genitive":
        return _replace_marked_object_case(
            text,
            graph_constraints,
            prepositions=("у", "около", "возле", "мимо"),
            case_name="genitive",
            transform_id=transform_id,
        )
    if transform_id == "morph.marked_object.case_genitive_noutbuk":
        return _replace_marked_object_case(
            text,
            graph_constraints,
            prepositions=("у", "около", "возле", "мимо"),
            case_name="genitive",
            transform_id=transform_id,
        )
    if transform_id == "morph.marked_object.case_dative":
        return _replace_marked_object_case(
            text,
            graph_constraints,
            prepositions=("к",),
            case_name="dative",
            transform_id=transform_id,
        )
    if transform_id == "orthography.actor_yo":
        for slot in find_actor_head_slots(text):
            replacement = _YO_REPLACEMENTS.get(slot.text.lower())
            if replacement:
                rendered = _preserve_case(slot.text, replacement)
                return (
                    _replace_once(text, slot.start, slot.end, rendered),
                    {
                        "transform_id": transform_id,
                        "class": "orthography_variation",
                        "safety_level": "safe",
                        "slot_type": slot.slot_type,
                        "slot_index": slot.start,
                        "before": slot.text,
                        "after": rendered,
                    },
                )
    if transform_id == "orthography.remove_yo":
        for source, replacement in _REMOVE_YO_REPLACEMENTS.items():
            match = re.search(rf"(?<!\w){re.escape(source)}(?!\w)", text, re.IGNORECASE)
            if match:
                rendered = _preserve_case(match.group(0), replacement)
                return (
                    _replace_once(text, match.start(), match.end(), rendered),
                    {
                        "transform_id": transform_id,
                        "class": "orthography_variation",
                        "safety_level": "safe",
                        "slot_type": "orthography_slot",
                        "slot_index": match.start(),
                        "before": match.group(0),
                        "after": rendered,
                    },
                )
    if transform_id == "ordinal.wrap_actor_head":
        if not graph_constraints.get("ordinal_bindings"):
            return None
        for slot in find_ordinal_slots(text):
            if "актер" in slot.text.lower() or "актёр" in slot.text.lower():
                continue
            replacement = f"{slot.text} актер"
            return (
                _replace_once(text, slot.start, slot.end, replacement),
                {
                    "transform_id": transform_id,
                    "class": "ordinal_surface_stress",
                    "safety_level": "safe",
                    "slot_type": slot.slot_type,
                    "slot_index": slot.start,
                    "before": slot.text,
                    "after": replacement,
                    },
                )
    if transform_id == "ordinal.unwrap_actor_head":
        if not graph_constraints.get("ordinal_bindings"):
            return None
        pattern = re.compile(r"\b(первый|второй|третий)\s+(акт[её]р(?:а)?)\b", re.IGNORECASE)
        match = pattern.search(text)
        if match:
            replacement = match.group(1)
            return (
                _replace_once(text, match.start(), match.end(), replacement),
                {
                    "transform_id": transform_id,
                    "class": "ordinal_surface_stress",
                    "safety_level": "safe",
                    "slot_type": "ordinal_anchor",
                    "slot_index": match.start(),
                    "before": match.group(0),
                    "after": replacement,
                },
            )
    if transform_id == "telegraph.drop_noncritical_connector":
        connectors = find_connector_slots(text)
        if connectors:
            slot = connectors[0]
            replacement = ""
            updated = _replace_once(text, slot.start, slot.end, replacement)
            updated = re.sub(r"\s{2,}", " ", updated).strip()
            return (
                updated,
                {
                    "transform_id": transform_id,
                    "class": "telegraph_shortening",
                    "safety_level": "safe",
                    "slot_type": slot.slot_type,
                    "slot_index": slot.start,
                    "before": slot.text,
                    "after": replacement,
                },
            )
    if transform_id == "lexical.preposition_swap":
        pattern = re.compile(r"\bоколо\b", re.IGNORECASE)
        match = pattern.search(text)
        if match:
            return (
                _replace_once(text, match.start(), match.end(), _preserve_case(match.group(0), "возле")),
                {
                    "transform_id": transform_id,
                    "class": "marked_object_morphology",
                    "safety_level": "risky",
                    "slot_type": "preposition_slot",
                    "slot_index": match.start(),
                    "before": match.group(0),
                    "after": _preserve_case(match.group(0), "возле"),
                },
            )
    if transform_id == "ordinal.numeric_form":
        for slot in find_ordinal_slots(text):
            base = slot.text.split()[0].lower()
            replacement = _ORDINAL_NUMERIC.get(base)
            if replacement:
                rendered = _preserve_case(slot.text.split()[0], replacement)
                updated = _replace_once(text, slot.start, slot.start + len(slot.text.split()[0]), rendered)
                return (
                    updated,
                    {
                        "transform_id": transform_id,
                        "class": "ordinal_surface_stress",
                        "safety_level": "risky",
                        "slot_type": "ordinal_anchor",
                        "slot_index": slot.start,
                        "before": slot.text.split()[0],
                        "after": rendered,
                    },
                )
    if transform_id == "telegraph.drop_subject_repeat":
        pattern = re.compile(r"\b(первый|второй|третий)\s+(акт[её]р(?:а)?)\b(?=\s+\w+)", re.IGNORECASE)
        match = pattern.search(text)
        if match:
            replacement = match.group(1)
            return (
                _replace_once(text, match.start(), match.end(), replacement),
                {
                    "transform_id": transform_id,
                    "class": "telegraph_shortening",
                    "safety_level": "risky",
                    "slot_type": "ordinal_anchor",
                    "slot_index": match.start(),
                    "before": match.group(0),
                    "after": replacement,
                },
            )
    return None
