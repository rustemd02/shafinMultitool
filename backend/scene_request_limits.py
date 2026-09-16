#!/usr/bin/env python3
"""Fail-closed admission for the Scene create-job request."""

from __future__ import annotations

import hashlib
import json
import math
import re
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path
from typing import Any


MAX_TEXT_BYTES = 64 * 1024
OPENAPI_SCHEMA_PATH = Path(__file__).with_name("openapi-scene-v1.yaml")

_INVALID_PAYLOAD = "payload contains invalid JSON values"
_SCHEMA_UNAVAILABLE = "request schema unavailable"
_SCHEMA_MISMATCH = "payload does not match request schema"
_TEXT_TOO_LARGE = f"script_text exceeds {MAX_TEXT_BYTES} UTF-8 bytes"
_HASH_MISMATCH = "request_hash does not match canonical payload"
_ANSWER_EMPTY = "answer carries neither selected_option_id nor free_text"


@dataclass(frozen=True)
class RequestValidation:
    accepted: bool
    reasons: tuple[str, ...] = field(default_factory=tuple)


@lru_cache(maxsize=4)
def _load_validator(schema_path: str, component_name: str = "CreateJobRequest") -> Any:
    """Load a frozen request schema component into a local Draft 2020-12 root."""
    import jsonschema
    import yaml
    from referencing import Registry, Resource

    document = yaml.safe_load(Path(schema_path).read_text(encoding="utf-8"))
    if not isinstance(document, dict):
        raise ValueError("invalid OpenAPI document")
    components = document.get("components")
    if not isinstance(components, dict):
        raise ValueError("missing components")
    schemas = components.get("schemas")
    if not isinstance(schemas, dict):
        raise ValueError("missing schemas")
    request_schema = schemas.get(component_name)
    if not isinstance(request_schema, dict):
        raise ValueError("missing request schema")

    # Validate the actual request component and every local component before
    # wrapping them. The OpenAPI document is not itself JSON Schema.
    for schema in schemas.values():
        if not isinstance(schema, dict):
            raise ValueError("invalid component schema")
        jsonschema.Draft202012Validator.check_schema(schema)

    # Keep the actual request component and its local
    # #/components/schemas references in a small Draft 2020-12 root.
    root = {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://set-os.local/schemas/scene-request-admission.json",
        "$ref": f"#/components/schemas/{component_name}",
        "components": {"schemas": schemas},
    }
    jsonschema.Draft202012Validator.check_schema(root)
    registry = Registry().with_resource(root["$id"], Resource.from_contents(root))
    resolver = registry.resolver(root["$id"])
    pending = [root]
    seen: set[int] = set()
    while pending:
        node = pending.pop()
        if id(node) in seen:
            continue
        seen.add(id(node))
        if isinstance(node, dict):
            if "$ref" in node:
                resolver.lookup(node["$ref"])
            pending.extend(node.values())
        elif isinstance(node, list):
            pending.extend(node)
    return jsonschema.Draft202012Validator(
        root,
        format_checker=jsonschema.FormatChecker(),
        registry=registry,
    )


def _validator() -> Any | None:
    try:
        return _load_validator(str(Path(OPENAPI_SCHEMA_PATH)))
    except Exception:
        return None


def _clarification_validator() -> Any | None:
    try:
        return _load_validator(
            str(Path(OPENAPI_SCHEMA_PATH)), component_name="ClarificationAnswer"
        )
    except Exception:
        return None


def _is_json_value(value: Any, active: set[int] | None = None) -> bool:
    """Reject Python values that cannot be represented by JSON safely."""
    if value is None or type(value) is bool:
        return True
    if type(value) is int:
        return True
    if type(value) is float:
        return math.isfinite(value)
    if type(value) is str:
        return not any(0xD800 <= ord(char) <= 0xDFFF for char in value)
    if type(value) not in (list, dict):
        return False

    active = set() if active is None else active
    identity = id(value)
    if identity in active:
        return False
    active.add(identity)
    try:
        if type(value) is list:
            return all(_is_json_value(item, active) for item in value)
        return all(
            type(key) is str
            and _is_json_value(key, active)
            and _is_json_value(item, active)
            for key, item in value.items()
        )
    finally:
        active.remove(identity)


def validate_scene_request(payload: Any) -> RequestValidation:
    """Validate a decoded create-job request body. Never raises."""
    try:
        if not isinstance(payload, dict) or not _is_json_value(payload):
            return RequestValidation(False, (_INVALID_PAYLOAD,))

        validator = _validator()
        if validator is None:
            return RequestValidation(False, (_SCHEMA_UNAVAILABLE,))
        if not validator.is_valid(payload):
            return RequestValidation(False, (_SCHEMA_MISMATCH,))

        previous_job_id = payload.get("previous_job_id")
        if previous_job_id is not None:
            pattern = validator.schema["components"]["schemas"]["JobId"]["pattern"]
            if re.fullmatch(pattern, previous_job_id) is None:
                return RequestValidation(False, (_SCHEMA_MISMATCH,))

        script_text = payload["script_text"]
        if len(script_text.encode("utf-8")) > MAX_TEXT_BYTES:
            return RequestValidation(False, (_TEXT_TOO_LARGE,))

        digest = hashlib.sha256(
            canonical_request_json(payload).encode("utf-8")
        ).hexdigest()
        if digest != payload["request_hash"]:
            return RequestValidation(False, (_HASH_MISMATCH,))
        return RequestValidation(True)
    except Exception:
        return RequestValidation(False, (_INVALID_PAYLOAD,))


def canonical_request_json(payload: dict) -> str:
    """Canonical JSON with only the top-level request hash removed."""
    projection = dict(payload)
    projection.pop("request_hash", None)
    return json.dumps(projection, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def validate_clarification_answer(payload: Any) -> RequestValidation:
    """Validate a decoded clarification-answer body. Never raises.

    The answer re-queues a job and its free_text/selected_option_id feed the
    provider retry, so admission mirrors the create-job fail-closed posture:
    schema-conformance against the frozen ClarificationAnswer component plus
    one semantic rule the JSON schema cannot express — an answer that carries
    neither a selected option nor free text would re-run the job with no new
    information and loop the clarification epoch.
    """
    try:
        if not isinstance(payload, dict) or not _is_json_value(payload):
            return RequestValidation(False, (_INVALID_PAYLOAD,))

        validator = _clarification_validator()
        if validator is None:
            return RequestValidation(False, (_SCHEMA_UNAVAILABLE,))
        if not validator.is_valid(payload):
            return RequestValidation(False, (_SCHEMA_MISMATCH,))

        has_option = isinstance(payload.get("selected_option_id"), str)
        has_free_text = isinstance(payload.get("free_text"), str)
        if not has_option and not has_free_text:
            return RequestValidation(False, (_ANSWER_EMPTY,))
        return RequestValidation(True)
    except Exception:
        return RequestValidation(False, (_INVALID_PAYLOAD,))
