from __future__ import annotations

import re
from pathlib import Path
from typing import Any
import unicodedata


_SPACE_RE = re.compile(r"\s+", flags=re.UNICODE)
_EDGE_RE = re.compile(r"^[\s\.,;:!?\"'`~()\[\]{}<>«»„“”‘’]+|[\s\.,;:!?\"'`~()\[\]{}<>«»„“”‘’]+$")

_MOVEMENT_CUES = {"идут", "подходят", "двигаются"}
_STOP_CUES = {"останавливаются", "останавливается", "стоп"}
_PASS_BY_CUES = {"проходят мимо", "проходит мимо"}
_SEQUENCE_CUES = {"затем", "после этого", "потом"}
_ACTION_START_CUES = {"начинает", "начинают"}

_ACTION_HINTS = {
    "идет",
    "идут",
    "подходит",
    "подходят",
    "останавливается",
    "останавливаются",
    "проходит",
    "проходят",
    "бежит",
    "бегут",
    "говорит",
    "говорят",
    "начинает",
    "начинают",
}


def default_unsupported_lemmas_path() -> Path:
    return Path(__file__).resolve().parent / "contracts" / "unsupported_action_lemmas_v1.txt"


def load_unsupported_action_lemmas(path: Path | None = None) -> set[str]:
    target = path or default_unsupported_lemmas_path()
    values: set[str] = set()
    with target.open("r", encoding="utf-8") as fh:
        for line in fh:
            payload = line.strip().lower()
            if not payload or payload.startswith("#"):
                continue
            values.add(payload)
    return values


def normalize_source_text(text: str) -> str:
    value = unicodedata.normalize("NFC", text).lower().replace("ё", "е")
    value = _EDGE_RE.sub("", value)
    value = _SPACE_RE.sub(" ", value).strip()
    return value


def _contains_any(source: str, variants: set[str]) -> bool:
    return any(variant in source for variant in variants)


def _marker_name(marker: dict[str, Any]) -> str:
    for key in ("name", "name_normalized", "source_name"):
        value = marker.get(key)
        if isinstance(value, str) and value.strip():
            return normalize_source_text(value)
    return ""


def compute_source_expectations(
    *,
    source: str,
    marked_objects: list[dict[str, Any]],
    unsupported_action_lemmas: set[str],
) -> dict[str, Any]:
    normalized = normalize_source_text(source)

    phase_hits = 0
    if _contains_any(normalized, _MOVEMENT_CUES):
        phase_hits += 1
    if _contains_any(normalized, _STOP_CUES):
        phase_hits += 1
    if _contains_any(normalized, _PASS_BY_CUES):
        phase_hits += 1
    if _contains_any(normalized, _SEQUENCE_CUES):
        phase_hits += 1
    if _contains_any(normalized, _ACTION_START_CUES):
        phase_hits += 1

    expected_multi_beat = phase_hits >= 2

    matched_markers = 0
    for marker in marked_objects:
        marker_name = _marker_name(marker)
        if not marker_name:
            continue
        if marker_name in normalized:
            matched_markers += 1
            continue
        # Simple lemma-like fallback: shared 4-char stem.
        if len(marker_name) >= 4 and marker_name[:4] in normalized:
            matched_markers += 1

    detected_action_cues = sum(1 for hint in _ACTION_HINTS if hint in normalized)
    expected_action_intents = max(1, detected_action_cues)
    expected_marked_object_mentions = matched_markers
    unsupported_action_present = any(lemma in normalized for lemma in unsupported_action_lemmas)

    return {
        "expectation_contract_version": "runtime_source_expectations_v1",
        "normalized_source": normalized,
        "expected_multi_beat": expected_multi_beat,
        "expected_marked_object_mentions": expected_marked_object_mentions,
        "expected_action_intents": expected_action_intents,
        "unsupported_action_present": unsupported_action_present,
    }

