from __future__ import annotations

import hashlib
import re
import uuid
from typing import Any


MARKED_ID_PREFIX = "object_marked_"
_CANONICAL_MARKED_ID_RE = re.compile(r"^object_marked_([0-9a-z]{8,})$")
_HEX8_RE = re.compile(r"^[0-9a-f]{8}$")


class MarkedIDPolicyError(ValueError):
    """Raised when marked-object identity policy cannot be applied deterministically."""


def _sha8(payload: str) -> str:
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()[:8]


def _normalize_text(value: Any, default: str) -> str:
    text = str(value if value is not None else default).strip().lower()
    return text or default


def _stable_order_key(row: dict[str, Any], *, original_index: int) -> tuple[int, str, str, str, int]:
    ordinal = row.get("source_marker_ordinal")
    if isinstance(ordinal, int):
        ordinal_value = ordinal
    elif isinstance(ordinal, str) and ordinal.strip().isdigit():
        ordinal_value = int(ordinal.strip())
    else:
        ordinal_value = 10**9

    marker_origin_key = str(row.get("marker_origin_key") or "").strip()
    if ordinal_value == 10**9 and not marker_origin_key:
        raise MarkedIDPolicyError("marker_identity_order_unstable")

    return (
        ordinal_value,
        _normalize_text(row.get("normalized_name"), "-"),
        _normalize_text(row.get("type"), "generic"),
        marker_origin_key,
        original_index,
    )


def _stable_index_map(rows: list[dict[str, Any]]) -> dict[int, int]:
    indexed = list(enumerate(rows))
    ordered = sorted(indexed, key=lambda item: _stable_order_key(item[1], original_index=item[0]))
    return {original_index: rank for rank, (original_index, _) in enumerate(ordered, start=1)}


def _canonical_shortid_from_existing_id(existing_id: Any) -> str | None:
    text = str(existing_id or "").strip().lower()
    match = _CANONICAL_MARKED_ID_RE.fullmatch(text)
    if not match:
        return None
    candidate = match.group(1)[:8]
    if not _HEX8_RE.fullmatch(candidate):
        return None
    return candidate


def _uuid_shortid(marker_uuid: Any) -> str | None:
    if marker_uuid is None:
        return None
    try:
        parsed = marker_uuid if isinstance(marker_uuid, uuid.UUID) else uuid.UUID(str(marker_uuid))
    except (ValueError, TypeError, AttributeError):
        return None
    return parsed.hex[:8].lower()


def _identity_key(row: dict[str, Any], *, stable_marker_index: int) -> str:
    normalized_name = _normalize_text(row.get("normalized_name"), "-")
    object_type = _normalize_text(row.get("type"), "generic")
    return f"{normalized_name}|{object_type}|{stable_marker_index}"


def resolve_marked_object_rows(marked_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Resolve deterministic object_marked_* ids with fallback and collision policy.

    Input row fields used by this resolver:
    - existing_id (optional)
    - marker_uuid (optional)
    - normalized_name (required for non-uuid fallback)
    - type (required for non-uuid fallback)
    - source_marker_ordinal (optional)
    - marker_origin_key (required when source_marker_ordinal is absent)
    """

    if not marked_rows:
        return []

    stable_index_by_row = _stable_index_map(marked_rows)
    used_shortids: set[str] = set()
    resolved: list[dict[str, Any]] = []

    for row_index, row in enumerate(marked_rows):
        stable_marker_index = stable_index_by_row[row_index]
        marker_identity_key = _identity_key(row, stable_marker_index=stable_marker_index)

        shortid = _canonical_shortid_from_existing_id(row.get("existing_id"))
        if shortid is None:
            shortid = _uuid_shortid(row.get("marker_uuid"))
        if shortid is None:
            shortid = _sha8(marker_identity_key)

        if shortid in used_shortids:
            collision_index = 1
            while True:
                collision_shortid = _sha8(f"{marker_identity_key}|{collision_index}")
                if collision_shortid not in used_shortids:
                    shortid = collision_shortid
                    break
                collision_index += 1

        used_shortids.add(shortid)
        resolved.append(
            {
                **row,
                "stable_marker_index": stable_marker_index,
                "marker_identity_key": marker_identity_key,
                "resolved_id": f"{MARKED_ID_PREFIX}{shortid}",
            }
        )

    return resolved
