from __future__ import annotations

import re

from .config import VariantPlanItem
from .style_policy import STYLE_LENGTH_LIMITS


_CYRILLIC_RE = re.compile(r"[А-Яа-яЁё]")
_JSON_LIKE_RE = re.compile(r"^\s*[\{\[]")
_BULLETED_RE = re.compile(r"^\s*[-*]\s+", re.MULTILINE)
_ACTOR_ID_LITERAL_RE = re.compile(r"\bactor_[0-9]+\b", flags=re.IGNORECASE)
_MARKED_OBJECT_ID_LITERAL_RE = re.compile(r"\bobject_marked_[0-9a-z]+\b", flags=re.IGNORECASE)


def normalize_persisted_source_text(text: str) -> str:
    value = text.replace("\r", "\n")
    value = " ".join(part for part in value.splitlines() if part.strip())
    value = re.sub(r"\s+", " ", value, flags=re.UNICODE).strip()
    return value


def dedup_normalization_key(text: str) -> str:
    normalized = normalize_persisted_source_text(text).lower().replace("ё", "е")
    return normalized


def technical_literal_reasons(text: str) -> list[str]:
    reasons: list[str] = []
    lowered = normalize_persisted_source_text(text).lower()
    if _ACTOR_ID_LITERAL_RE.search(lowered):
        reasons.append("contains_actor_id_literal")
    if _MARKED_OBJECT_ID_LITERAL_RE.search(lowered):
        reasons.append("contains_marked_object_id_literal")
    return reasons


def has_technical_identifier_literals(text: str) -> bool:
    return bool(technical_literal_reasons(text))


def scrub_technical_identifier_literals(text: str) -> str:
    value = text
    value = re.sub(r"\(\s*actor_[0-9]+\s*\)", "", value, flags=re.IGNORECASE)
    value = re.sub(r"\(\s*object_marked_[0-9a-z]+\s*\)", "", value, flags=re.IGNORECASE)
    value = _ACTOR_ID_LITERAL_RE.sub("", value)
    value = _MARKED_OBJECT_ID_LITERAL_RE.sub("", value)
    value = re.sub(r"\(\s*\)", "", value)
    value = re.sub(r"\s+([,.;:!?])", r"\1", value)
    value = re.sub(r"\s{2,}", " ", value, flags=re.UNICODE)
    return normalize_persisted_source_text(value)


def evaluate_candidate_text(
    candidate: str,
    plan_item: VariantPlanItem,
    *,
    existing_keys: set[str] | None = None,
) -> list[str]:
    reasons: list[str] = []
    normalized = normalize_persisted_source_text(candidate)
    if not normalized:
        reasons.append("empty_or_whitespace")
        return reasons

    if _JSON_LIKE_RE.match(normalized):
        reasons.append("json_like_output")
    if _BULLETED_RE.search(normalized):
        reasons.append("bulleted_output")
    if not _CYRILLIC_RE.search(normalized):
        reasons.append("missing_cyrillic")

    if len(normalized) > STYLE_LENGTH_LIMITS[plan_item.style_bucket]:
        reasons.append("length_exceeds_bucket_budget")

    lowered = normalized.lower()
    reasons.extend(technical_literal_reasons(lowered))

    if plan_item.required_aliases and not any(anchor.lower() in lowered for anchor in plan_item.required_aliases):
        reasons.append("missing_required_alias")

    if plan_item.required_ordinal_tokens and not all(token.lower() in lowered for token in plan_item.required_ordinal_tokens):
        reasons.append("missing_required_ordinal_token")

    if plan_item.required_disambiguation_cues and not any(
        cue.lower() in lowered for cue in plan_item.required_disambiguation_cues
    ):
        reasons.append("missing_required_disambiguation_cue")

    if existing_keys is not None and dedup_normalization_key(normalized) in existing_keys:
        reasons.append("duplicate_variant_text")

    return reasons
