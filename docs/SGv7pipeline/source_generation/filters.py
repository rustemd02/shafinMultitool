from __future__ import annotations

import re

from .config import VariantPlanItem
from .style_policy import STYLE_LENGTH_LIMITS


_CYRILLIC_RE = re.compile(r"[А-Яа-яЁё]")
_JSON_LIKE_RE = re.compile(r"^\s*[\{\[]")
_BULLETED_RE = re.compile(r"^\s*[-*]\s+", re.MULTILINE)
_ACTOR_ID_LITERAL_RE = re.compile(r"\bactor_[0-9]+\b", flags=re.IGNORECASE)
_OBJECT_ID_LITERAL_RE = re.compile(r"\bobject_[0-9]+\b", flags=re.IGNORECASE)
_MARKED_OBJECT_ID_LITERAL_RE = re.compile(r"\bobject_marked_[0-9a-z]+\b", flags=re.IGNORECASE)
_ACTION_ID_LITERAL_RE = re.compile(r"\baction_[0-9]+\b", flags=re.IGNORECASE)
_MIXED_SCRIPT_TOKEN_RE = re.compile(r"\b(?=\w*[A-Za-z])(?=\w*[А-Яа-яЁё])[A-Za-zА-Яа-яЁё]+\b")

_META_LANGUAGE_PATTERNS: tuple[tuple[re.Pattern[str], str], ...] = (
    (re.compile(r"\bput_down_target\s*:", flags=re.IGNORECASE), "contains_put_down_target_marker"),
    (re.compile(r"\bholding_object_preserved\b", flags=re.IGNORECASE), "contains_holding_object_marker"),
    (re.compile(r"\bhandoff_object\s*:", flags=re.IGNORECASE), "contains_handoff_object_marker"),
    (re.compile(r"\bpickup_target\s*:", flags=re.IGNORECASE), "contains_pickup_target_marker"),
    (re.compile(r"\binside_relation\b", flags=re.IGNORECASE), "contains_inside_relation_marker"),
    (re.compile(r"\bopen_before_pick_up\b", flags=re.IGNORECASE), "contains_open_before_pick_up_marker"),
    (re.compile(r"\bdual_motion\b", flags=re.IGNORECASE), "contains_dual_motion_marker"),
    (re.compile(r"\bsymmetric_toward_each_other\b", flags=re.IGNORECASE), "contains_symmetry_marker"),
    (re.compile(r"\bdirection_toward_each_other\b", flags=re.IGNORECASE), "contains_direction_marker"),
    (re.compile(r"\bpass_by_then_role_shift\b", flags=re.IGNORECASE), "contains_role_shift_marker"),
    (re.compile(r"\bstop_near_then_role_shift\b", flags=re.IGNORECASE), "contains_role_shift_marker"),
    (re.compile(r"\bstop_phase_before_run\b", flags=re.IGNORECASE), "contains_stop_phase_marker"),
    (re.compile(r"\bmarked_object_grounding\b", flags=re.IGNORECASE), "contains_grounding_marker"),
    (re.compile(r"\bthree_beat_chronology\b", flags=re.IGNORECASE), "contains_three_beat_marker"),
    (re.compile(r"\bfirst_actor_described_action\b", flags=re.IGNORECASE), "contains_described_action_marker"),
    (re.compile(r"\bthird_actor_described_action\b", flags=re.IGNORECASE), "contains_described_action_marker"),
    (re.compile(r"\bsecond_actor_runs\b", flags=re.IGNORECASE), "contains_second_actor_runs_marker"),
    (re.compile(r"\bexact_marker_identity\b", flags=re.IGNORECASE), "contains_exact_marker_identity_marker"),
    (re.compile(r"\brecoverability\b", flags=re.IGNORECASE), "contains_recoverability_marker"),
    (re.compile(r"\brole_shift\b", flags=re.IGNORECASE), "contains_role_shift_marker"),
    (re.compile(r"\bfinal_beat\b", flags=re.IGNORECASE), "contains_final_beat_marker"),
    (re.compile(r"\bbeat_count\s*=\s*\d+\b", flags=re.IGNORECASE), "contains_beat_count_marker"),
    (re.compile(r"\bmust_ground_object\b", flags=re.IGNORECASE), "contains_must_ground_object_marker"),
    (re.compile(r"\bcanonical\b", flags=re.IGNORECASE), "contains_canonical_marker"),
    (re.compile(r"\bpass_by\b", flags=re.IGNORECASE), "contains_pass_by_token"),
    (re.compile(r"\bpick_up\b", flags=re.IGNORECASE), "contains_pick_up_token"),
    (re.compile(r"\bput_down\b", flags=re.IGNORECASE), "contains_put_down_token"),
    (re.compile(r"\bquickly\b", flags=re.IGNORECASE), "contains_english_motion_modifier"),
    (re.compile(r"\bslowly\b", flags=re.IGNORECASE), "contains_english_motion_modifier"),
    (re.compile(r"\bcarefully\b", flags=re.IGNORECASE), "contains_english_motion_modifier"),
)

_SURFACE_NOISE_PATTERNS: tuple[tuple[re.Pattern[str], str], ...] = (
    (
        re.compile(
            r"\bпервый\s+акт[её]р\s+и\s+второй\s+акт[её]ры\b",
            flags=re.IGNORECASE,
        ),
        "actor_plural_mismatch",
    ),
    (
        re.compile(
            r"\b(?:первый|второй|третий)\s+акт[её]р\s*:\s*[А-ЯЁA-Z][^:\n]{0,40}\s*:",
            flags=re.IGNORECASE,
        ),
        "duplicate_speaker_label",
    ),
    (
        re.compile(r"\b(затем|потом|после\s+этого)\s+\1\b", flags=re.IGNORECASE),
        "repeated_connector",
    ),
    (
        re.compile(
            r"\b(?:первый|второй|третий)\s+акт[её]р\s+начина(?:ет|ется)\s+бег",
            flags=re.IGNORECASE,
        ),
        "broken_action_surface",
    ),
    (
        _MIXED_SCRIPT_TOKEN_RE,
        "mixed_script_token",
    ),
    (
        re.compile(r"\bякорн\w*\s+объект\w*\b", flags=re.IGNORECASE),
        "abstract_anchor_placeholder",
    ),
    (
        re.compile(r"\bобъект-ориентир\w*\b", flags=re.IGNORECASE),
        "abstract_anchor_placeholder",
    ),
    (
        re.compile(
            r"\b(?:первый|второй|третий)\s+(?!акт[её]р\b)[А-ЯЁ][а-яё]+\s+"
            r"(?:подходит|ид[её]т|направляется|бер[её]т|клад[её]т|оста[её]тся|смотрит|входит|проходит|начинает)\b",
            flags=re.IGNORECASE,
        ),
        "awkward_ordinal_name_surface",
    ),
    (
        re.compile(r"\bколоны\b", flags=re.IGNORECASE),
        "spelling_colony_typo",
    ),
    (
        re.compile(
            r"\bнужн(?:ый|ое|ую|ого|ому|ым|ом)\s+(?:предмет|объект|место)\b",
            flags=re.IGNORECASE,
        ),
        "abstract_placeholder_surface",
    ),
)

_MORPHOLOGY_PATTERNS: tuple[tuple[re.Pattern[str], str], ...] = (
    (re.compile(r"\bрядом\s+с\s+ноутбук\b", flags=re.IGNORECASE), "bad_morphology_noutbuk_case"),
    (re.compile(r"\bмимо\s+ноутбук\b", flags=re.IGNORECASE), "bad_morphology_noutbuk_case"),
    (re.compile(r"\bу\s+ноутбук\b", flags=re.IGNORECASE), "bad_morphology_noutbuk_case"),
    (re.compile(r"\bоколо\s+ноутбук\b", flags=re.IGNORECASE), "bad_morphology_noutbuk_case"),
    (re.compile(r"\bоколо\s+рядом\s+с\b", flags=re.IGNORECASE), "bad_morphology_double_preposition"),
    (re.compile(r"\bк\s+окно\b", flags=re.IGNORECASE), "bad_morphology_object_case"),
    (re.compile(r"\bк\s+терминал\b", flags=re.IGNORECASE), "bad_morphology_object_case"),
    (re.compile(r"\bк\s+лавка\b", flags=re.IGNORECASE), "bad_morphology_object_case"),
    (re.compile(r"\bк\s+стойка\b", flags=re.IGNORECASE), "bad_morphology_object_case"),
    (re.compile(r"\bмимо\s+монитор\b", flags=re.IGNORECASE), "bad_morphology_object_case"),
    (re.compile(r"\bмимо\s+терминал\b", flags=re.IGNORECASE), "bad_morphology_object_case"),
    (re.compile(r"\bоколо\s+рабочий\s+компьютер\b", flags=re.IGNORECASE), "bad_morphology_object_case"),
    (re.compile(r"\bмимо\s+рабочий\s+компьютер\b", flags=re.IGNORECASE), "bad_morphology_object_case"),
    (re.compile(r"\bрядом\s+с\s+рабочий\s+компьютер\b", flags=re.IGNORECASE), "bad_morphology_object_case"),
    (re.compile(r"\bоткрывает\s+коробка\b", flags=re.IGNORECASE), "bad_morphology_object_case"),
    (
        re.compile(r"\b(?:к|у|около|возле|рядом\s+с|мимо)\s+ближний\b", flags=re.IGNORECASE),
        "bad_morphology_near_far_case",
    ),
    (
        re.compile(r"\b(?:к|у|около|возле|рядом\s+с|мимо)\s+дальний\b", flags=re.IGNORECASE),
        "bad_morphology_near_far_case",
    ),
    (re.compile(r"\bу\s+стол\b", flags=re.IGNORECASE), "bad_morphology_object_case"),
)


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
    if _OBJECT_ID_LITERAL_RE.search(lowered):
        reasons.append("contains_object_id_literal")
    if _MARKED_OBJECT_ID_LITERAL_RE.search(lowered):
        reasons.append("contains_marked_object_id_literal")
    if _ACTION_ID_LITERAL_RE.search(lowered):
        reasons.append("contains_action_id_literal")
    return reasons


def has_technical_identifier_literals(text: str) -> bool:
    return bool(technical_literal_reasons(text))


def meta_language_reasons(text: str) -> list[str]:
    lowered = normalize_persisted_source_text(text).lower()
    reasons: list[str] = []
    for pattern, reason in _META_LANGUAGE_PATTERNS:
        if pattern.search(lowered):
            reasons.append(reason)
    return reasons


def surface_noise_reasons(text: str) -> list[str]:
    normalized = normalize_persisted_source_text(text)
    reasons: list[str] = []
    for pattern, reason in _SURFACE_NOISE_PATTERNS:
        if pattern.search(normalized):
            reasons.append(reason)
    return reasons


def morphology_reasons(text: str) -> list[str]:
    lowered = normalize_persisted_source_text(text).lower()
    reasons: list[str] = []
    for pattern, reason in _MORPHOLOGY_PATTERNS:
        if pattern.search(lowered):
            reasons.append(reason)
    return reasons


def disallowed_source_text_reasons(text: str) -> list[str]:
    reasons = []
    reasons.extend(technical_literal_reasons(text))
    reasons.extend(meta_language_reasons(text))
    reasons.extend(surface_noise_reasons(text))
    reasons.extend(morphology_reasons(text))
    return reasons


def scrub_technical_identifier_literals(text: str) -> str:
    value = text
    value = re.sub(r"\(\s*actor_[0-9]+\s*\)", "", value, flags=re.IGNORECASE)
    value = re.sub(r"\(\s*object_[0-9]+\s*\)", "", value, flags=re.IGNORECASE)
    value = re.sub(r"\(\s*object_marked_[0-9a-z]+\s*\)", "", value, flags=re.IGNORECASE)
    value = re.sub(r"\(\s*action_[0-9]+\s*\)", "", value, flags=re.IGNORECASE)
    value = _ACTOR_ID_LITERAL_RE.sub("", value)
    value = _OBJECT_ID_LITERAL_RE.sub("", value)
    value = _MARKED_OBJECT_ID_LITERAL_RE.sub("", value)
    value = _ACTION_ID_LITERAL_RE.sub("", value)
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
    reasons.extend(meta_language_reasons(lowered))
    reasons.extend(surface_noise_reasons(normalized))
    reasons.extend(morphology_reasons(lowered))

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
