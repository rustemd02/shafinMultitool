#!/usr/bin/env python3
"""Validate the release component disposition record.

This gate owns the *status* of the five material provenance blockers that were
previously emitted by ``validate_release_bundle.sh`` as hard-coded rows.  The
record deliberately keeps legal and replacement decisions explicit: technical
repository evidence is not legal approval, and a pending replacement never
turns into an allowed Release payload by accident.

The validator is offline and read-only.  It checks the record shape, the
repository source paths, and (when ``--app`` is supplied) the expected paths in
the exact built app.  A well-formed record always emits one
``KNOWN_BLOCKER_COUNT`` metric; malformed records fail before they can be
treated as release evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path, PurePosixPath
from typing import Any


DEFAULT_RECORD_PATH = (
    Path(__file__).resolve().parents[1]
    / "docs/implementation/provenance/release-component-status.json"
)
EXPECTED_SCHEMA = "set-os-release-component-status"
EXPECTED_SCHEMA_VERSION = 1
DISPOSITIONS = frozenset(
    {
        "KEEP",
        "RETRAIN",
        "REPLACE",
        "REMOVE_AFTER_VERIFIED_REPLACEMENT",
    }
)
SCOPES = frozenset({"CAMERA_ONLY", "SCENE_ONLY"})
LEGAL_STATES = frozenset({"PENDING", "APPROVED", "REJECTED"})
RELEASE_MEMBERSHIP = frozenset({"bundled", "excluded", "deferred"})
REPLACEMENT_STATES = frozenset({"PENDING", "VERIFIED"})
REPLACEMENT_DISPOSITIONS = frozenset(
    {"RETRAIN", "REPLACE", "REMOVE_AFTER_VERIFIED_REPLACEMENT"}
)
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")
ID_RE = re.compile(r"[a-z0-9][a-z0-9.-]*\Z")

EXPECTED_COMPONENTS = {
    "llama-framework",
    "detr-segmentation-model",
    "nima-aesthetic-model",
    "circle-usdz",
    "person-usdz",
}


class ComponentStatusValidationError(ValueError):
    """Raised when the status record cannot be trusted as release evidence."""


def _fail(message: str) -> None:
    raise ComponentStatusValidationError(message)


def _mapping(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        _fail(f"malformed record: {label} must be an object")
    return value


def _list(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        _fail(f"malformed record: {label} must be an array")
    return value


def _required(mapping: dict[str, Any], key: str, label: str) -> Any:
    if key not in mapping:
        _fail(f"malformed record: {label} is missing required field '{key}'")
    return mapping[key]


def _nonempty_string(mapping: dict[str, Any], key: str, label: str) -> str:
    value = _required(mapping, key, label)
    if not isinstance(value, str) or not value.strip():
        _fail(f"malformed record: {label}.{key} must be a non-empty string")
    return value


def _strict_keys(mapping: dict[str, Any], required: set[str], optional: set[str], label: str) -> None:
    missing = sorted(required - mapping.keys())
    if missing:
        _fail(f"malformed record: {label} is missing required field(s): {', '.join(missing)}")
    unknown = sorted(set(mapping) - required - optional)
    if unknown:
        _fail(f"malformed record: {label} contains unknown field(s): {', '.join(unknown)}")


def _safe_relative_path(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        _fail(f"malformed record: {label} must be a non-empty relative path")
    if "\\" in value:
        _fail(f"malformed record: {label} must use POSIX separators")
    path = PurePosixPath(value)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        _fail(f"malformed record: {label} must not escape its root: {value}")
    return path.as_posix()


def _sha256(value: Any, label: str) -> str:
    if not isinstance(value, str) or not SHA256_RE.fullmatch(value):
        _fail(f"malformed record: {label} must be a lowercase SHA-256 digest")
    return value


def _load_json(path: Path, label: str) -> dict[str, Any]:
    if path.is_symlink() or not path.is_file():
        _fail(f"{label} file is missing or is a symlink: {path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        _fail(f"malformed record: cannot read {label} at {path}: {exc}")
    return _mapping(value, label)


def _file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _validate_source(source: dict[str, Any], repo_root: Path) -> None:
    _strict_keys(
        source,
        {"baseline_task", "inventory_path", "inventory_sha256"},
        set(),
        "source",
    )
    if _nonempty_string(source, "baseline_task", "source") != "M0-007":
        _fail("malformed record: source.baseline_task must be M0-007")
    inventory_path = _safe_relative_path(
        _required(source, "inventory_path", "source"), "source.inventory_path"
    )
    inventory_sha256 = _sha256(
        _required(source, "inventory_sha256", "source"), "source.inventory_sha256"
    )
    inventory = repo_root / inventory_path
    if not inventory.is_file() or inventory.is_symlink():
        _fail(f"source inventory is missing or is a symlink: {inventory_path}")
    if _file_digest(inventory) != inventory_sha256:
        _fail(f"source inventory hash mismatch: {inventory_path}")


def _validate_expected(expected: dict[str, Any], label: str) -> dict[str, str | None]:
    _strict_keys(expected, set(), {"source_path", "bundle_path", "manifest_sha256"}, label)
    values: dict[str, str | None] = {
        "source_path": None,
        "bundle_path": None,
        "manifest_sha256": None,
    }
    for key in values:
        if key not in expected or expected[key] is None:
            continue
        if key.endswith("path"):
            values[key] = _safe_relative_path(expected[key], f"{label}.{key}")
        else:
            values[key] = _sha256(expected[key], f"{label}.{key}")
    if not any(values.values()):
        _fail(f"malformed record: {label} must contain a source/bundle path or manifest hash")
    return values


def _validate_replacement(
    value: Any, disposition: str, label: str
) -> dict[str, str] | None:
    if disposition not in REPLACEMENT_DISPOSITIONS:
        if value is not None:
            _fail(f"malformed record: {label} must be null for KEEP")
        return None
    dependency = _mapping(value, label)
    _strict_keys(dependency, {"task", "status", "reason"}, set(), label)
    task = _nonempty_string(dependency, "task", label)
    status = _nonempty_string(dependency, "status", label)
    reason = _nonempty_string(dependency, "reason", label)
    if status not in REPLACEMENT_STATES:
        _fail(f"malformed record: {label}.status is unknown: {status}")
    return {"task": task, "status": status, "reason": reason}


def _validate_release_membership(value: Any, label: str) -> dict[str, str]:
    membership = _mapping(value, label)
    _strict_keys(membership, {"Debug", "Release"}, set(), label)
    result: dict[str, str] = {}
    for configuration in ("Debug", "Release"):
        state = _nonempty_string(membership, configuration, label)
        if state not in RELEASE_MEMBERSHIP:
            _fail(f"malformed record: {label}.{configuration} is unknown: {state}")
        result[configuration] = state
    return result


def _validate_component(
    raw: Any,
    index: int,
    repo_root: Path,
    app_root: Path | None,
) -> tuple[dict[str, Any], str | None]:
    label = f"components[{index}]"
    component = _mapping(raw, label)
    _strict_keys(
        component,
        {
            "id",
            "kind",
            "disposition",
            "scope",
            "owner",
            "reason",
            "expected",
            "legal_state",
            "replacement_dependency",
            "release_config_membership",
        },
        set(),
        label,
    )
    component_id = _nonempty_string(component, "id", label)
    if not ID_RE.fullmatch(component_id):
        _fail(f"malformed record: {label}.id is not a stable lowercase id: {component_id}")
    kind = _nonempty_string(component, "kind", label)
    if kind not in {"framework", "model", "media"}:
        _fail(f"malformed record: {label}.kind is unknown: {kind}")
    disposition = _nonempty_string(component, "disposition", label)
    if disposition not in DISPOSITIONS:
        _fail(f"malformed record: {label}.disposition is unknown: {disposition}")
    scope_values = _list(_required(component, "scope", label), f"{label}.scope")
    if not scope_values:
        _fail(f"malformed record: {label}.scope must not be empty")
    scope: list[str] = []
    for scope_index, raw_scope in enumerate(scope_values):
        if not isinstance(raw_scope, str) or raw_scope not in SCOPES:
            _fail(f"malformed record: {label}.scope[{scope_index}] is unknown")
        if raw_scope in scope:
            _fail(f"malformed record: {label}.scope contains a duplicate value: {raw_scope}")
        scope.append(raw_scope)
    owner = _nonempty_string(component, "owner", label)
    reason = _nonempty_string(component, "reason", label)
    expected = _validate_expected(
        _mapping(_required(component, "expected", label), f"{label}.expected"),
        f"{label}.expected",
    )
    legal_state = _nonempty_string(component, "legal_state", label)
    if legal_state not in LEGAL_STATES:
        _fail(f"malformed record: {label}.legal_state is unknown: {legal_state}")
    replacement = _validate_replacement(
        component["replacement_dependency"], disposition, f"{label}.replacement_dependency"
    )
    membership = _validate_release_membership(
        component["release_config_membership"], f"{label}.release_config_membership"
    )

    source_path = expected["source_path"]
    if source_path is not None:
        source = repo_root / source_path
        if not source.exists() or source.is_symlink():
            _fail(f"component source path is missing or is a symlink: {source_path}")
    bundle_path = expected["bundle_path"]
    if app_root is not None and bundle_path is not None:
        bundle = app_root / bundle_path
        present = bundle.exists() and not bundle.is_symlink()
        if membership["Release"] == "bundled" and not present:
            _fail(f"component bundle path is missing or is a symlink: {bundle_path}")
        if membership["Release"] != "bundled" and present:
            _fail(f"excluded component is present in Release bundle: {bundle_path}")

    blocker: str | None = None
    if membership["Release"] == "bundled":
        if legal_state != "APPROVED":
            blocker = f"legal-state-{legal_state.lower()}"
        elif disposition in REPLACEMENT_DISPOSITIONS and replacement is not None:
            if replacement["status"] != "VERIFIED":
                blocker = f"replacement-{replacement['status'].lower()}"
        elif disposition in REPLACEMENT_DISPOSITIONS:
            _fail(f"malformed record: {label}.replacement_dependency is required")

    normalized = {
        "id": component_id,
        "kind": kind,
        "disposition": disposition,
        "scope": scope,
        "owner": owner,
        "reason": reason,
        "expected": expected,
        "legal_state": legal_state,
        "replacement_dependency": replacement,
        "release_config_membership": membership,
    }
    return normalized, blocker


def _validate_exclusions(value: Any, repo_root: Path) -> None:
    exclusions = _list(value, "explicit_exclusions")
    seen_ids: set[str] = set()
    seen_paths: set[str] = set()
    for index, raw in enumerate(exclusions):
        label = f"explicit_exclusions[{index}]"
        exclusion = _mapping(raw, label)
        _strict_keys(
            exclusion,
            {"id", "kind", "scope", "path", "owner", "reason", "release_config_membership"},
            set(),
            label,
        )
        exclusion_id = _nonempty_string(exclusion, "id", label)
        if not ID_RE.fullmatch(exclusion_id) or exclusion_id in seen_ids:
            _fail(f"malformed record: duplicate or unstable exclusion id: {exclusion_id}")
        seen_ids.add(exclusion_id)
        kind = _nonempty_string(exclusion, "kind", label)
        if kind not in {"font", "asset", "fixture", "benchmark", "model", "dependency"}:
            _fail(f"malformed record: {label}.kind is unknown: {kind}")
        scopes = _list(_required(exclusion, "scope", label), f"{label}.scope")
        if not scopes or any(scope not in SCOPES for scope in scopes):
            _fail(f"malformed record: {label}.scope is empty or unknown")
        path = _safe_relative_path(_required(exclusion, "path", label), f"{label}.path")
        if path in seen_paths:
            _fail(f"malformed record: duplicate exclusion path: {path}")
        seen_paths.add(path)
        if not (repo_root / path).exists():
            _fail(f"explicit exclusion path is missing: {path}")
        _nonempty_string(exclusion, "owner", label)
        _nonempty_string(exclusion, "reason", label)
        membership = _validate_release_membership(
            _required(exclusion, "release_config_membership", label),
            f"{label}.release_config_membership",
        )
        if membership["Release"] not in {"excluded", "deferred"}:
            _fail(f"malformed record: {label} must not mark an exclusion as bundled")


def _validate_record_shape(
    record: dict[str, Any], repo_root: Path, app_root: Path | None
) -> list[tuple[dict[str, Any], str | None]]:
    _strict_keys(
        record,
        {"schema", "schema_version", "source", "components", "explicit_exclusions"},
        {"$schema"},
        "record",
    )
    if _required(record, "schema", "record") != EXPECTED_SCHEMA:
        _fail("malformed record: unsupported schema")
    if _required(record, "schema_version", "record") != EXPECTED_SCHEMA_VERSION:
        _fail("malformed record: unsupported schema_version")
    _validate_source(_mapping(_required(record, "source", "record"), "source"), repo_root)
    components = _list(_required(record, "components", "record"), "components")
    if not components:
        _fail("malformed record: components must not be empty")
    results: list[tuple[dict[str, Any], str | None]] = []
    seen_ids: set[str] = set()
    for index, raw in enumerate(components):
        normalized, blocker = _validate_component(raw, index, repo_root, app_root)
        component_id = normalized["id"]
        if component_id in seen_ids:
            _fail(f"malformed record: duplicate component id: {component_id}")
        seen_ids.add(component_id)
        results.append((normalized, blocker))
    if seen_ids != EXPECTED_COMPONENTS:
        missing = sorted(EXPECTED_COMPONENTS - seen_ids)
        unknown = sorted(seen_ids - EXPECTED_COMPONENTS)
        details = []
        if missing:
            details.append(f"missing={','.join(missing)}")
        if unknown:
            details.append(f"unknown={','.join(unknown)}")
        _fail("malformed record: component coverage mismatch (" + "; ".join(details) + ")")
    _validate_exclusions(_required(record, "explicit_exclusions", "record"), repo_root)
    return results


def validate_record(
    repo_root: Path, record_path: Path = DEFAULT_RECORD_PATH, app_root: Path | None = None
) -> list[dict[str, Any]]:
    """Validate a record and return normalized known blockers.

    The function is intentionally read-only.  A successful return means the
    schema and all referenced paths were valid; an empty list means the
    Release configuration is technically unblocked by this manifest.
    """

    if repo_root.is_symlink():
        _fail(f"repository root is missing or is a symlink: {repo_root}")
    if record_path.is_symlink():
        _fail(f"status record is missing or is a symlink: {record_path}")
    if app_root is not None and app_root.is_symlink():
        _fail(f"app root is missing or is a symlink: {app_root}")
    repo_root = repo_root.resolve()
    record_path = record_path.resolve()
    if not repo_root.is_dir():
        _fail(f"repository root is missing or is a symlink: {repo_root}")
    if app_root is not None:
        app_root = app_root.resolve()
        if not app_root.is_dir():
            _fail(f"app root is missing or is a symlink: {app_root}")
    record = _load_json(record_path, "status record")
    results = _validate_record_shape(record, repo_root, app_root)
    blockers: list[dict[str, Any]] = []
    for component, blocker in results:
        if blocker is None:
            continue
        blockers.append(
            {
                "id": component["id"],
                "component": component["expected"].get("bundle_path") or component["id"],
                "kind": component["kind"],
                "disposition": component["disposition"],
                "scope": component["scope"],
                "legal_state": component["legal_state"],
                "blocker": blocker,
                "reason": component["reason"],
            }
        )
    return sorted(blockers, key=lambda row: row["id"])


def _emit_blockers(blockers: list[dict[str, Any]]) -> None:
    for blocker in blockers:
        print(
            "KNOWN_BLOCKER: "
            f"id={blocker['id']} "
            f"component={blocker['component']} "
            f"kind={blocker['kind']} "
            f"disposition={blocker['disposition']} "
            f"scope={','.join(blocker['scope'])} "
            f"legal_state={blocker['legal_state']} "
            f"blocker={blocker['blocker']}"
        )
    print(f"KNOWN_BLOCKER_COUNT={len(blockers)}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", required=True, type=Path)
    parser.add_argument("--record", type=Path, default=DEFAULT_RECORD_PATH)
    parser.add_argument("--app", type=Path, help="optional exact built Release app to inspect")
    args = parser.parse_args(argv)
    try:
        blockers = validate_record(args.repo_root, args.record, args.app)
    except ComponentStatusValidationError as exc:
        print(f"FAIL COMPONENT STATUS: {exc}", file=sys.stderr)
        return 1
    _emit_blockers(blockers)
    if blockers:
        print(
            f"FAIL COMPONENT STATUS: release blocked by {len(blockers)} known provenance blocker(s)",
            file=sys.stderr,
        )
        return 1
    print("PASS COMPONENT STATUS: no known provenance blockers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
