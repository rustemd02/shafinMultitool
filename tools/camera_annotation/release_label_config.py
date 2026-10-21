#!/usr/bin/env python3
"""Pure conversion-config builder for the DATA-005 release-label export.

The GUI (annotate_gui.py) collects release-contract elicitations that the v1
review record does not carry — per-issue severity/confidence/evidence and the
target facts (entity_ref/identity_status/kind/role/movability). This module
turns that GUI state into the conversion config accepted by
``release_label_adapter.py convert --config`` and refuses (without writing or
invoking anything) when a required elicitation is missing: the release
contract has no legal default for any of these fields, so a missing answer is
a refusal, never a fabricated number.

Everything here is pure and tkinter-free so it is unit-testable headlessly:
the GUI only reads widgets into plain dicts/lists and calls
``build_conversion_config``.

Conventions (kept honest, no invention):

- ``release_record_id`` is derived as ``cam-release-`` + the v1 record id,
  sanitized to the contract pattern ``^cam-release-[a-z0-9][a-z0-9._-]*$``;
  the derivation is a naming rule the annotator sees in the export dialog,
  not new evidence.
- ``source_family_id`` / ``frame_id`` derive from the queue record
  (provenance source / record id) — stable identity naming, editable in the
  GUI before export.
- ``captured_at`` is NOT guessed: it comes from the record when the record
  carries one, otherwise the annotator types it. EXIF timestamps carry no
  timezone and movie frames carry none at all, so auto-deriving a
  ``…Z``-suffixed capture time would fabricate provenance.
- Exports from this tool are always ``origin=human_review``,
  ``human_gold=false``, ``release_admissible=false``; adjudication is a
  separate human step (DATA-009/DATA-011) and never a GUI default.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[2]
CONTRACTS = REPO / "ml" / "camera_coach" / "contracts"

RELEASE_RECORD_ID_PREFIX = "cam-release-"
RELEASE_RECORD_ID_PATTERN = re.compile(r"^cam-release-[a-z0-9][a-z0-9._-]*$")
STABLE_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]*$")
CAPTURED_AT_PATTERN = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")


def _schema_enums() -> dict[str, list[str]]:
    schema = json.loads((CONTRACTS / "camera_release_label_v1.schema.json").read_text(encoding="utf-8"))
    defs = schema["$defs"]
    return {
        "identity_status": list(defs["target"]["properties"]["identity_status"]["enum"]),
        "kind": list(defs["target"]["properties"]["kind"]["enum"]),
        "role": list(defs["target"]["properties"]["role"]["enum"]),
        "movability_status": list(defs["movability"]["properties"]["status"]["enum"]),
        "movability_permission": list(defs["movability"]["properties"]["permission"]["enum"]),
        "abstention_reasons": list(defs["abstention"]["properties"]["reasons"]["items"]["enum"]),
    }


_ENUMS = _schema_enums()
IDENTITY_STATUSES: tuple[str, ...] = tuple(_ENUMS["identity_status"])
TARGET_KINDS: tuple[str, ...] = tuple(_ENUMS["kind"])
TARGET_ROLES: tuple[str, ...] = tuple(_ENUMS["role"])
MOVABILITY_STATUSES: tuple[str, ...] = tuple(_ENUMS["movability_status"])
MOVABILITY_PERMISSIONS: tuple[str, ...] = tuple(_ENUMS["movability_permission"])
ABSTENTION_REASONS: tuple[str, ...] = tuple(_ENUMS["abstention_reasons"])


class ReleaseConfigError(ValueError):
    """A required release elicitation is missing or out of contract; no export."""


def sanitize_release_record_id(record_id: str) -> str:
    """cam-release-<sanitized record id>, matching the contract recordID pattern."""
    raw = str(record_id or "").strip().lower()
    cleaned = re.sub(r"[^a-z0-9._-]+", "-", raw).strip("-.")
    if not cleaned or not re.match(r"[a-z0-9]", cleaned[0]):
        raise ReleaseConfigError(
            f"не могу построить release_record_id из record_id {record_id!r}: "
            "после санитизации нет ни одного допустимого символа"
        )
    candidate = RELEASE_RECORD_ID_PREFIX + cleaned
    if not RELEASE_RECORD_ID_PATTERN.match(candidate):
        raise ReleaseConfigError(
            f"release_record_id {candidate!r} не соответствует паттерну контракта "
            f"{RELEASE_RECORD_ID_PATTERN.pattern}"
        )
    return candidate


def sanitize_stable_id(value: Any, field: str) -> str:
    """Sanitize to the contract stableID pattern ^[A-Za-z0-9][A-Za-z0-9._:-]*$."""
    raw = str(value or "").strip()
    cleaned = re.sub(r"[^A-Za-z0-9._:-]+", "-", raw)
    cleaned = re.sub(r"-{2,}", "-", cleaned).strip("-")
    if not cleaned or not STABLE_ID_PATTERN.match(cleaned):
        raise ReleaseConfigError(
            f"{field}: {value!r} не превращается в допустимый stable id "
            f"({STABLE_ID_PATTERN.pattern}); заполни поле вручную"
        )
    return cleaned


def parse_unit_interval(value: Any, field: str) -> float:
    """Parse a severity/confidence answer; blank or out-of-range is a refusal."""
    if isinstance(value, str):
        text = value.strip().replace(",", ".")
        if not text:
            raise ReleaseConfigError(f"{field}: обязательное поле (контракт запрещает выдумывать значение)")
        try:
            number = float(text)
        except ValueError as exc:
            raise ReleaseConfigError(f"{field}: {value!r} не число от 0 до 1") from exc
    elif isinstance(value, (int, float)) and not isinstance(value, bool):
        number = float(value)
    else:
        raise ReleaseConfigError(f"{field}: обязательное поле (контракт запрещает выдумывать значение)")
    if not 0.0 <= number <= 1.0:
        raise ReleaseConfigError(f"{field}: {number} вне диапазона 0..1")
    return round(number, 4)


def _parse_rect(value: Any, field: str) -> list[float] | None:
    if value is None:
        return None
    if not isinstance(value, (list, tuple)) or len(value) != 4:
        raise ReleaseConfigError(f"{field}: rect должен быть [x, y, w, h]")
    try:
        numbers = [float(v) for v in value]
    except (TypeError, ValueError) as exc:
        raise ReleaseConfigError(f"{field}: rect должен быть [x, y, w, h]") from exc
    x, y, w, h = numbers
    if not (0.0 <= x <= 1.0 and 0.0 <= y <= 1.0 and 0.0 < w <= 1.0 and 0.0 < h <= 1.0
            and x + w <= 1.0001 and y + h <= 1.0001):
        raise ReleaseConfigError(f"{field}: rect должен быть нормализованным прямоугольником внутри кадра")
    return [round(v, 4) for v in numbers]


def derive_source_fields(record: dict) -> dict[str, str]:
    """source_family_id / frame_id / captured_at as far as the record proves them.

    captured_at stays empty when the record does not carry it: the GUI field
    stays editable and the export refuses until a human supplies the value.
    """
    provenance = record.get("provenance") or {}
    source = str(provenance.get("source") or "").strip()
    if not source:
        raw_id = str(record.get("record_id") or "")
        source = raw_id.split("__", 1)[0] if "__" in raw_id else ""
    record_id = str(record.get("record_id") or "")
    return {
        "source_family_id": source,
        "frame_id": record_id,
        "captured_at": str(record.get("captured_at") or "").strip(),
    }


def _resolve_captured_at(review: dict, override: Any) -> str:
    text = str(override or "").strip() or str(review.get("captured_at") or "").strip()
    if not text:
        raise ReleaseConfigError(
            "captured_at: в записи нет времени съёмки — впусти его вручную "
            "(формат 2026-09-22T12:00:00Z); контракт не позволяет его выдумать"
        )
    if not CAPTURED_AT_PATTERN.match(text):
        raise ReleaseConfigError(f"captured_at: {text!r} не совпадает с форматом YYYY-MM-DDTHH:MM:SSZ")
    return text


def _resolve_target(target: dict) -> dict:
    if not isinstance(target, dict):
        raise ReleaseConfigError("target: обязательный блок (identity/kind/role/movability)")
    entity_ref = sanitize_stable_id(target.get("entity_ref"), "target.entity_ref")
    for field, allowed in (
        ("identity_status", IDENTITY_STATUSES),
        ("kind", TARGET_KINDS),
        ("role", TARGET_ROLES),
        ("movability_status", MOVABILITY_STATUSES),
        ("movability_permission", MOVABILITY_PERMISSIONS),
    ):
        value = str(target.get(field) or "").strip()
        if value not in allowed:
            raise ReleaseConfigError(f"target.{field}: выбери одно из {list(allowed)} (получено {value!r})")
    rect = _parse_rect(target.get("rect"), "target.rect")
    return {
        "entity_ref": entity_ref,
        "identity_status": target["identity_status"],
        "kind": target["kind"],
        "role": target["role"],
        "rect": rect,
        "movability": {
            "status": target["movability_status"],
            "permission": target["movability_permission"],
        },
    }


def _resolve_issue_evidence(review: dict, issue_evidence: dict) -> dict[str, dict]:
    resolved: dict[str, dict] = {}
    present = list(review.get("issues") or [])
    for head in present:
        raw = (issue_evidence or {}).get(head)
        if not isinstance(raw, dict):
            raise ReleaseConfigError(
                f"issue {head!r} отмечен, но нет элиситации: severity/confidence/evidence-ref обязательны"
            )
        severity = parse_unit_interval(raw.get("severity"), f"issue {head!r}.severity")
        confidence = parse_unit_interval(raw.get("confidence"), f"issue {head!r}.confidence")
        refs_raw = raw.get("evidence_refs") or raw.get("evidence_ref")
        refs = [
            sanitize_stable_id(ref, f"issue {head!r}.evidence_ref")
            for ref in ([refs_raw] if isinstance(refs_raw, str) else list(refs_raw or []))
            if str(ref or "").strip()
        ]
        if not refs:
            raise ReleaseConfigError(
                f"issue {head!r}: нужен хотя бы один evidence-ref "
                "(например record_id или record_id.region0)"
            )
        entry: dict[str, Any] = {"severity": severity, "confidence": confidence, "evidence_refs": refs}
        rect = _parse_rect(raw.get("rect"), f"issue {head!r}.rect")
        if rect is not None:
            entry["rect"] = rect
        resolved[head] = entry
    extra = sorted(set(issue_evidence or {}) - set(present))
    if extra:
        raise ReleaseConfigError(f"issue_evidence содержит неотмеченные issues: {extra}")
    return resolved


def build_conversion_config(
    review: dict,
    *,
    issue_evidence: dict[str, dict] | None = None,
    target: dict,
    review_ids: list[str] | str | None = None,
    corrective_action_id: str | None = None,
    abstention_reason: str | None = None,
    captured_at: str | None = None,
    source_family_id: str | None = None,
    frame_id: str | None = None,
    release_record_id: str | None = None,
) -> dict:
    """Build the ``convert --config`` payload for one human v1 review record.

    Raises ReleaseConfigError (before anything is written or invoked) whenever
    a contract-required elicitation is missing, so the GUI can show the reason
    and stay at zero side effects.
    """
    from annotation_labels import KEEP_ACTION, validate_label

    errors = validate_label(review)
    if errors:
        raise ReleaseConfigError(f"запись v1 не проходит валидацию: {errors}")
    if not str(review.get("notes") or "").strip():
        # The export envelope stores the raw opinion beside the structured
        # label (adapter rule); this builder sends only review.notes, so an
        # empty note would fail at the adapter — refuse here with the fix.
        raise ReleaseConfigError(
            "raw_opinion: конверт хранит твоё мнение рядом со structured label — "
            "запиши его в «Своими словами» перед экспортом"
        )

    unsure = bool(review.get("unsure"))
    improvement_needed = review.get("improvement_needed")

    abstention_reasons: list[str] = []
    if unsure:
        reason = str(abstention_reason or "").strip()
        if reason not in ABSTENTION_REASONS:
            raise ReleaseConfigError(
                f"abstention_reasons: выбери явную причину воздержания из {list(ABSTENTION_REASONS)}"
            )
        abstention_reasons = [reason]
    elif improvement_needed is True:
        corrective = [a for a in review.get("actions") or [] if a != KEEP_ACTION]
        if corrective_action_id is None:
            if len(corrective) != 1:
                raise ReleaseConfigError(
                    "corrective_action_id: выбери одно corrective-действие для экспорта; "
                    f"в записи несколько: {corrective}"
                )
            corrective_action_id = corrective[0]
        elif corrective_action_id not in corrective:
            raise ReleaseConfigError(
                f"corrective_action_id {corrective_action_id!r} не входит в corrective-действия записи {corrective}"
            )

    record_id = str(review.get("record_id") or "")
    derived = derive_source_fields(review)
    family = sanitize_stable_id(source_family_id or derived["source_family_id"], "source_family_id")
    frame = sanitize_stable_id(frame_id or derived["frame_id"], "frame_id")

    ids_raw = review_ids if review_ids is not None else record_id
    if isinstance(ids_raw, str):
        ids_raw = [ids_raw]
    ids = [
        sanitize_stable_id(rid, "review_ids")
        for rid in ids_raw
        if str(rid or "").strip()
    ]
    if not ids:
        raise ReleaseConfigError("review_ids: нужен хотя бы один id review-записи (provenance-требование схемы)")

    config: dict[str, Any] = {
        "release_record_id": sanitize_release_record_id(release_record_id or record_id),
        "source_family_id": family,
        "frame_id": frame,
        "captured_at": _resolve_captured_at(review, captured_at),
        "target": _resolve_target(target),
        "review_ids": ids,
        # This tool exports live human review only; adjudication/gold/admission
        # are explicit downstream human steps, never a GUI default.
        "origin": "human_review",
        "human_gold": False,
        "release_admissible": False,
    }
    if not unsure:
        resolved_evidence = _resolve_issue_evidence(review, issue_evidence or {})
        if resolved_evidence:
            config["issue_evidence"] = resolved_evidence
    if corrective_action_id is not None and not unsure:
        config["corrective_action_id"] = corrective_action_id
    if abstention_reasons:
        config["abstention_reasons"] = abstention_reasons
    return config
