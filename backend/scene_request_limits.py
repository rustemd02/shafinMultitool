#!/usr/bin/env python3
"""Request limits/redaction reference validator (M12-004).

Fail-closed reference implementation of the backend request gate: the
accepted Scene payload is limited to UTF-8 screenplay text (<=64 KiB),
locale, marked-object identifiers/names, constraints, and
client/build/schema metadata. Camera frames, audio, contacts, device
advertising IDs, and arbitrary file uploads are rejected.

The Swift client builder (SceneCreateJobRequestBuilder, same task) is
constrained by construction to this allowlist; this module is the
auditable reference the backend must enforce identically.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Any


MAX_TEXT_BYTES = 64 * 1024
MAX_TEXT_CHARS = 4000
MAX_MARKED_OBJECTS = 32
MAX_SCENES = 8
ALLOWED_LOCALES = {"ru", "en"}
ALLOWED_TOP_FIELDS = frozenset({
    "request_id", "client_build", "schema_version", "locale",
    "script_text", "marked_objects", "constraints", "previous_job_id",
    "request_hash", "schema_version_backend", "model_version",
    "prompt_version", "provider_name", "provider_version",
})
ALLOWED_MARKED_FIELDS = frozenset({"canonical_id", "name"})
ALLOWED_CONSTRAINT_FIELDS = frozenset({"maximum_scenes"})
FORBIDDEN_FIELD_HINTS = (
    "frame", "pixel", "image", "photo", "video", "audio", "voice",
    "contact", "addressbook", "idfa", "advertising", "file", "upload",
    "blob", "base64", "gps", "location_history",
)


@dataclass(frozen=True)
class RequestValidation:
    accepted: bool
    reasons: tuple[str, ...] = field(default_factory=tuple)


def _forbidden_hint(name: str) -> bool:
    lowered = name.lower()
    return any(h in lowered for h in FORBIDDEN_FIELD_HINTS)


def validate_scene_request(payload: Any) -> RequestValidation:
    """Validate a decoded create-job request body. Never raises."""
    if not isinstance(payload, dict):
        return RequestValidation(False, ("payload must be an object",))
    unknown = sorted(set(payload) - ALLOWED_TOP_FIELDS)
    if unknown:
        flagged = [f for f in unknown if _forbidden_hint(f)]
        if flagged:
            return RequestValidation(
                False, (f"forbidden media/personal-data fields: {','.join(sorted(flagged))}",)
            )
        return RequestValidation(False, (f"unknown fields: {','.join(unknown)}",))
    for key in payload:
        if _forbidden_hint(key):
            return RequestValidation(False, (f"forbidden field: {key}",))
    text = payload.get("script_text")
    if not isinstance(text, str) or not text:
        return RequestValidation(False, ("script_text must be non-empty text",))
    if len(text) > MAX_TEXT_CHARS:
        return RequestValidation(False, (f"script_text exceeds {MAX_TEXT_CHARS} chars",))
    if len(text.encode("utf-8")) > MAX_TEXT_BYTES:
        return RequestValidation(False, (f"script_text exceeds {MAX_TEXT_BYTES} UTF-8 bytes",))
    if payload.get("locale") not in ALLOWED_LOCALES:
        return RequestValidation(False, ("locale must be ru or en",))
    marked = payload.get("marked_objects", [])
    if not isinstance(marked, list) or len(marked) > MAX_MARKED_OBJECTS:
        return RequestValidation(False, (f"marked_objects must be a list ≤{MAX_MARKED_OBJECTS}",))
    for entry in marked:
        if not isinstance(entry, dict):
            return RequestValidation(False, ("marked_objects entries must be objects",))
        unknown_m = sorted(set(entry) - ALLOWED_MARKED_FIELDS)
        if unknown_m:
            return RequestValidation(False, (f"marked_objects unknown fields: {','.join(unknown_m)}",))
        cid = entry.get("canonical_id")
        if not isinstance(cid, str) or not cid or len(cid) > 128:
            return RequestValidation(False, ("marked_objects canonical_id must be non-empty ≤128",))
    constraints = payload.get("constraints", {})
    if not isinstance(constraints, dict):
        return RequestValidation(False, ("constraints must be an object",))
    unknown_c = sorted(set(constraints) - ALLOWED_CONSTRAINT_FIELDS)
    if unknown_c:
        return RequestValidation(False, (f"constraints unknown fields: {','.join(unknown_c)}",))
    max_scenes = constraints.get("maximum_scenes", 1)
    if not isinstance(max_scenes, int) or not 1 <= max_scenes <= MAX_SCENES:
        return RequestValidation(False, (f"maximum_scenes must be 1…{MAX_SCENES}",))
    req_hash = payload.get("request_hash", "")
    if not isinstance(req_hash, str) or len(req_hash) != 64 or any(
        c not in "0123456789abcdef" for c in req_hash
    ):
        return RequestValidation(False, ("request_hash must be lowercase hex sha256",))
    return RequestValidation(True, ())


def canonical_request_json(payload: dict) -> str:
    """Canonical JSON used for request-hash computation (sorted keys, UTF-8)."""
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
