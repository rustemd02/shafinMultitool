from __future__ import annotations

from typing import Any

from .marked_ids import resolve_marked_object_rows


class DriftCheckError(ValueError):
    """Raised when a runtime/train drift gate fails."""


def _iter_paths(payload: Any, *, prefix: str = "$"):
    if isinstance(payload, dict):
        for key, value in payload.items():
            yield from _iter_paths(value, prefix=f"{prefix}.{key}")
        return
    if isinstance(payload, list):
        for index, value in enumerate(payload):
            yield from _iter_paths(value, prefix=f"{prefix}[{index}]")
        return
    yield prefix, payload


def null_forbidden_check(payload: Any) -> None:
    null_paths = [path for path, value in _iter_paths(payload) if value is None]
    if null_paths:
        example = ", ".join(null_paths[:5])
        raise DriftCheckError(f"null_forbidden_check_failed: {example}")


def optional_present_canonicalization_check(
    *,
    omission_action: dict[str, Any],
    omission_object: dict[str, Any],
    present_action: dict[str, Any],
    present_object: dict[str, Any],
) -> None:
    omitted_action_fields = ("target", "direction", "modifier")
    omitted_object_fields = ("name",)
    for field in omitted_action_fields:
        if field in omission_action:
            raise DriftCheckError(f"optional_omit_failed: action field `{field}` must be omitted")
    for field in omitted_object_fields:
        if field in omission_object:
            raise DriftCheckError(f"optional_omit_failed: object field `{field}` must be omitted")

    present_action_fields = ("target", "direction", "modifier")
    present_object_fields = ("name",)
    for field in present_action_fields:
        if field not in present_action:
            raise DriftCheckError(f"optional_present_failed: action field `{field}` is required")
        if present_action[field] is None:
            raise DriftCheckError(f"optional_present_failed: action field `{field}` cannot be null")
    for field in present_object_fields:
        if field not in present_object:
            raise DriftCheckError(f"optional_present_failed: object field `{field}` is required")
        if present_object[field] is None:
            raise DriftCheckError(f"optional_present_failed: object field `{field}` cannot be null")


def marked_id_collision_resolution_check(
    *,
    marked_rows: list[dict[str, Any]],
    expected_resolved_ids: list[str] | None = None,
) -> list[str]:
    first = [row["resolved_id"] for row in resolve_marked_object_rows(marked_rows)]
    second = [row["resolved_id"] for row in resolve_marked_object_rows(marked_rows)]

    if first != second:
        raise DriftCheckError("marked_id_collision_resolution_check_failed: nondeterministic_resolution")

    if len(first) != len(set(first)):
        raise DriftCheckError("marked_id_collision_resolution_check_failed: duplicate_resolved_ids")

    if expected_resolved_ids is not None and first != expected_resolved_ids:
        raise DriftCheckError(
            "marked_id_collision_resolution_check_failed: expected_mismatch "
            f"expected={expected_resolved_ids} actual={first}"
        )
    return first
