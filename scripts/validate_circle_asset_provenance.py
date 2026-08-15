#!/usr/bin/env python3
"""Validate the repository-backed technical provenance record for Circle."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any


DEFAULT_RECORD_PATH = (
    Path(__file__).resolve().parents[1]
    / "docs/implementation/provenance/circle-asset-provenance.json"
)
ANNOTATION_SCOPE_MESSAGE = (
    "git_lineage, runtime_consumers and source_project.target_boundary are "
    "human-reviewed shape-only annotations; Git history, source lines and "
    "project.pbxproj membership are not verified"
)
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")
UUID_RE = re.compile(
    r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
    r"[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\Z"
)
COMMIT_RE = re.compile(r"[0-9a-f]{40}\Z")


class ProvenanceValidationError(ValueError):
    """Raised when the record or either Circle asset is not internally valid."""


def _fail(message: str) -> None:
    raise ProvenanceValidationError(message)


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


def _string(mapping: dict[str, Any], key: str, label: str) -> str:
    value = _required(mapping, key, label)
    if not isinstance(value, str) or not value:
        _fail(f"malformed record: {label}.{key} must be a non-empty string")
    return value


def _ascii_string(mapping: dict[str, Any], key: str, label: str) -> str:
    value = _string(mapping, key, label)
    try:
        value.encode("ascii")
    except UnicodeEncodeError:
        _fail(f"malformed record: {label}.{key} must contain ASCII text")
    return value


def _boolean(mapping: dict[str, Any], key: str, label: str) -> bool:
    value = _required(mapping, key, label)
    if not isinstance(value, bool):
        _fail(f"malformed record: {label}.{key} must be a boolean")
    return value


def _integer(mapping: dict[str, Any], key: str, label: str) -> int:
    value = _required(mapping, key, label)
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        _fail(f"malformed record: {label}.{key} must be a non-negative integer")
    return value


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


def _uuid(value: Any, label: str) -> str:
    if not isinstance(value, str) or not UUID_RE.fullmatch(value):
        _fail(f"malformed record: {label} must be a UUID")
    return value


def _member_map(entries: Any, label: str) -> dict[str, dict[str, Any]]:
    members = _list(entries, label)
    result: dict[str, dict[str, Any]] = {}
    for index, raw_entry in enumerate(members):
        entry = _mapping(raw_entry, f"{label}[{index}]")
        path = _safe_relative_path(
            _required(entry, "path", f"{label}[{index}]"),
            f"{label}[{index}].path",
        )
        if path in result:
            _fail(f"malformed record: duplicate {label} path '{path}'")
        result[path] = {
            "path": path,
            "size": _integer(entry, "size", f"{label}[{index}]"),
            "sha256": _sha256(
                _required(entry, "sha256", f"{label}[{index}]"),
                f"{label}[{index}].sha256",
            ),
        }
    if not result:
        _fail(f"malformed record: {label} must not be empty")
    return result


def _load_record(record_path: Path) -> dict[str, Any]:
    try:
        record = json.loads(record_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        _fail(f"malformed record: cannot read JSON at {record_path}: {exc}")
    return _mapping(record, "record")


def _validate_record_shape(record: dict[str, Any]) -> dict[str, Any]:
    if _required(record, "schema", "record") != "circle-asset-provenance":
        _fail("malformed record: unsupported schema")
    if _required(record, "schema_version", "record") != 1:
        _fail("malformed record: unsupported schema_version")
    if _required(record, "asset", "record") != "Circle":
        _fail("malformed record: record.asset must be Circle")

    source = _mapping(_required(record, "source_project", "record"), "source_project")
    source_path = _safe_relative_path(
        _required(source, "path", "source_project"), "source_project.path"
    )
    source_members = _member_map(
        _required(source, "members", "source_project"), "source_project.members"
    )
    source_member_count = _integer(source, "member_count", "source_project")
    source_total_size = _integer(source, "total_size", "source_project")
    if source_member_count != len(source_members):
        _fail("malformed record: source_project.member_count does not match members")

    source_metadata = _mapping(
        _required(source, "metadata", "source_project"), "source_project.metadata"
    )
    project_metadata = _mapping(
        _required(source_metadata, "project_document", "source_project.metadata"),
        "source_project.metadata.project_document",
    )
    project_member = _safe_relative_path(
        _required(project_metadata, "member", "project_document"),
        "project_document.member",
    )
    _string(project_metadata, "format", "project_document")
    _integer(project_metadata, "project_version", "project_document")
    _integer(project_metadata, "scene_version", "project_document")
    _uuid(
        _required(project_metadata, "scene_identifier", "project_document"),
        "project_document.scene_identifier",
    )
    _uuid(
        _required(project_metadata, "object_identifier", "project_document"),
        "project_document.object_identifier",
    )
    _uuid(
        _required(project_metadata, "runtime_identifier", "project_document"),
        "project_document.runtime_identifier",
    )
    primitive_factory = _mapping(
        _required(project_metadata, "primitive_factory", "project_document"),
        "project_document.primitive_factory",
    )
    _string(primitive_factory, "identifier", "project_document.primitive_factory")
    _string(primitive_factory, "version", "project_document.primitive_factory")
    _string(project_metadata, "primitive_type", "project_document")
    _string(project_metadata, "material", "project_document")
    _string(project_metadata, "scene_material", "project_document")
    _string(project_metadata, "title", "project_document")
    version_metadata = _mapping(
        _required(source_metadata, "version_json", "source_project.metadata"),
        "source_project.metadata.version_json",
    )
    version_member = _safe_relative_path(
        _required(version_metadata, "member", "version_json"), "version_json.member"
    )
    _string(version_metadata, "version", "version_json")
    _uuid(
        _required(version_metadata, "library_id", "version_json"),
        "version_json.library_id",
    )
    target_boundary = _mapping(
        _required(source, "target_boundary", "source_project"),
        "source_project.target_boundary",
    )
    _string(target_boundary, "evidence", "source_project.target_boundary")
    _string(
        target_boundary,
        "source_project_target_membership",
        "source_project.target_boundary",
    )
    _boolean(target_boundary, "source_project_tracked", "source_project.target_boundary")
    for member_path, label in (
        (project_member, "project_document.member"),
        (version_member, "version_json.member"),
    ):
        if member_path not in source_members:
            _fail(f"malformed record: {label} is not listed in source_project.members")

    exported = _mapping(
        _required(record, "exported_usdz", "record"), "exported_usdz"
    )
    exported_path = _safe_relative_path(
        _required(exported, "path", "exported_usdz"), "exported_usdz.path"
    )
    exported_members = _member_map(
        _required(exported, "members", "exported_usdz"), "exported_usdz.members"
    )
    exported_member_count = _integer(exported, "member_count", "exported_usdz")
    if exported_member_count != len(exported_members):
        _fail("malformed record: exported_usdz.member_count does not match members")
    exported_size = _integer(exported, "size", "exported_usdz")
    exported_hash = _sha256(
        _required(exported, "sha256", "exported_usdz"), "exported_usdz.sha256"
    )

    export_metadata = _mapping(
        _required(exported, "metadata", "exported_usdz"), "exported_usdz.metadata"
    )
    _ascii_string(export_metadata, "member_format", "exported_usdz.metadata")
    member_identifier = _uuid(
        _required(export_metadata, "member_identifier", "exported_usdz.metadata"),
        "exported_usdz.metadata.member_identifier",
    )
    _ascii_string(
        export_metadata,
        "rcfoundation_metadata_key",
        "exported_usdz.metadata",
    )
    _ascii_string(
        export_metadata,
        "rcfoundation_version",
        "exported_usdz.metadata",
    )

    shared_identifiers = _list(
        _required(record, "shared_identifiers", "record"), "shared_identifiers"
    )
    if not shared_identifiers:
        _fail("malformed record: shared_identifiers must not be empty")
    for index, raw_identifier in enumerate(shared_identifiers):
        identifier = _mapping(raw_identifier, f"shared_identifiers[{index}]")
        _string(identifier, "name", f"shared_identifiers[{index}]")
        _safe_relative_path(
            _required(identifier, "source_member", f"shared_identifiers[{index}]"),
            f"shared_identifiers[{index}].source_member",
        )
        _safe_relative_path(
            _required(identifier, "export_member", f"shared_identifiers[{index}]"),
            f"shared_identifiers[{index}].export_member",
        )
        _uuid(
            _required(identifier, "source_value", f"shared_identifiers[{index}]"),
            f"shared_identifiers[{index}].source_value",
        )
        exported_value = _string(
            identifier, "export_value", f"shared_identifiers[{index}]"
        )
        if not re.fullmatch(r"[0-9A-Fa-f-]{32,36}", exported_value):
            _fail(
                "malformed record: shared identifier export_value must be a UUID "
                "with or without hyphens"
            )
        if _normalize_uuid(identifier["source_value"]) != _normalize_uuid(
            exported_value
        ):
            _fail(
                f"malformed record: shared_identifiers[{index}] source/export values differ"
            )
        if _string(identifier, "normalization", f"shared_identifiers[{index}]") != (
            "uppercase_uuid_without_hyphens"
        ):
            _fail(
                "malformed record: unsupported shared identifier normalization"
            )
        if identifier["source_member"] not in source_members:
            _fail(
                f"malformed record: shared identifier source member is not listed: "
                f"{identifier['source_member']}"
            )
        if identifier["export_member"] not in exported_members:
            _fail(
                f"malformed record: shared identifier export member is not listed: "
                f"{identifier['export_member']}"
            )

    # Git lineage is a human-reviewed annotation. This loop validates shape only;
    # it deliberately does not invoke Git or verify the recorded history.
    lineage = _list(_required(record, "git_lineage", "record"), "git_lineage")
    if not lineage:
        _fail("malformed record: git_lineage must not be empty")
    for index, raw_entry in enumerate(lineage):
        entry = _mapping(raw_entry, f"git_lineage[{index}]")
        commit = _string(entry, "commit", f"git_lineage[{index}]")
        if not COMMIT_RE.fullmatch(commit):
            _fail(f"malformed record: git_lineage[{index}].commit must be full SHA-1")
        paths = _list(
            _required(entry, "paths", f"git_lineage[{index}]"),
            f"git_lineage[{index}].paths",
        )
        if not paths:
            _fail(f"malformed record: git_lineage[{index}].paths must not be empty")
        for path_index, path in enumerate(paths):
            _safe_relative_path(path, f"git_lineage[{index}].paths[{path_index}]")
        _string(entry, "role", f"git_lineage[{index}]")
        _string(entry, "subject", f"git_lineage[{index}]")

    # Runtime consumers are human-reviewed source-line annotations. This loop
    # validates shape only; it does not read or search the Swift sources.
    consumers = _list(
        _required(record, "runtime_consumers", "record"), "runtime_consumers"
    )
    if not consumers:
        _fail("malformed record: runtime_consumers must not be empty")
    for index, raw_consumer in enumerate(consumers):
        consumer = _mapping(raw_consumer, f"runtime_consumers[{index}]")
        _safe_relative_path(
            _required(consumer, "path", f"runtime_consumers[{index}]"),
            f"runtime_consumers[{index}].path",
        )
        _string(consumer, "lines", f"runtime_consumers[{index}]")
        _string(consumer, "evidence", f"runtime_consumers[{index}]")

    annotations = _list(
        _required(record, "human_reviewed_annotations", "record"),
        "human_reviewed_annotations",
    )
    annotation_fields: set[str] = set()
    for index, raw_annotation in enumerate(annotations):
        annotation = _mapping(
            raw_annotation, f"human_reviewed_annotations[{index}]"
        )
        field = _string(annotation, "field", f"human_reviewed_annotations[{index}]")
        if field in annotation_fields:
            _fail(f"malformed record: duplicate human-reviewed annotation '{field}'")
        annotation_fields.add(field)
        if (
            _string(annotation, "status", f"human_reviewed_annotations[{index}]")
            != "human_reviewed"
        ):
            _fail(
                "malformed record: human-reviewed annotation status must be "
                "'human_reviewed'"
            )
        if (
            _string(
                annotation,
                "validator_scope",
                f"human_reviewed_annotations[{index}]",
            )
            != "shape_only"
        ):
            _fail(
                "malformed record: human-reviewed annotation validator_scope must "
                "be 'shape_only'"
            )
        _string(annotation, "evidence_boundary", f"human_reviewed_annotations[{index}]")
    required_annotation_fields = {
        "git_lineage",
        "runtime_consumers",
        "source_project.target_boundary",
    }
    if annotation_fields != required_annotation_fields:
        _fail(
            "malformed record: human_reviewed_annotations must cover exactly "
            "git_lineage, runtime_consumers and source_project.target_boundary"
        )

    claims = _mapping(_required(record, "claims", "record"), "claims")
    expected_claims = {
        "repository_correlation": "verified",
        "deterministic_source_to_export_recipe": "missing",
        "source_to_export_causality": "not_proven",
        "explicit_creator_declaration": "missing",
        "explicit_rights_or_permission_declaration": "missing",
        "legal_release_owner_decision": "blocked",
        "redistribution_approval": "not_claimed",
    }
    for key, expected_value in expected_claims.items():
        if _required(claims, key, "claims") != expected_value:
            _fail(f"malformed record: claims.{key} must be {expected_value!r}")

    return {
        "source_path": source_path,
        "source_members": source_members,
        "source_total_size": source_total_size,
        "project_member": project_member,
        "version_member": version_member,
        "project_metadata": project_metadata,
        "version_metadata": version_metadata,
        "exported_path": exported_path,
        "exported_members": exported_members,
        "exported_size": exported_size,
        "exported_hash": exported_hash,
        "export_metadata": export_metadata,
        "member_identifier": member_identifier,
        "shared_identifiers": shared_identifiers,
    }


def _normalize_uuid(value: str) -> str:
    return value.replace("-", "").upper()


def _digest_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _digest_file(path: Path) -> tuple[int, str]:
    digest = hashlib.sha256()
    size = 0
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                size += len(chunk)
                digest.update(chunk)
    except OSError as exc:
        _fail(f"cannot read asset member {path}: {exc}")
    return size, digest.hexdigest()


def _validate_source_project(root: Path, config: dict[str, Any]) -> dict[str, bytes]:
    source_root = root / config["source_path"]
    if not source_root.is_dir() or source_root.is_symlink():
        _fail(f"missing Circle.rcproject directory: {config['source_path']}")

    actual_paths: dict[str, Path] = {}
    for path in source_root.rglob("*"):
        relative = path.relative_to(source_root).as_posix()
        if path.is_symlink():
            _fail(f"symlink is not a tracked source member: {relative}")
        if path.is_file():
            actual_paths[relative] = path
        elif not path.is_dir():
            _fail(f"unsupported non-file source member: {relative}")

    expected_paths = set(config["source_members"])
    actual_path_set = set(actual_paths)
    missing = sorted(expected_paths - actual_path_set)
    extra = sorted(actual_path_set - expected_paths)
    if missing:
        _fail(f"missing source member: {missing[0]}")
    if extra:
        _fail(f"extra source member: {extra[0]}")

    source_bytes: dict[str, bytes] = {}
    total_size = 0
    for relative, expected in config["source_members"].items():
        path = actual_paths[relative]
        size, digest = _digest_file(path)
        total_size += size
        if size != expected["size"]:
            _fail(
                f"source member size mismatch: {relative} "
                f"(expected {expected['size']}, got {size})"
            )
        if digest != expected["sha256"]:
            _fail(
                f"source member hash mismatch: {relative} "
                f"(expected {expected['sha256']}, got {digest})"
            )
        try:
            source_bytes[relative] = path.read_bytes()
        except OSError as exc:
            _fail(f"cannot read source member {relative}: {exc}")

    if total_size != config["source_total_size"]:
        _fail(
            "source project total size mismatch: "
            f"expected {config['source_total_size']}, got {total_size}"
        )
    return source_bytes


def _json_bytes(value: bytes, label: str) -> Any:
    try:
        return json.loads(value.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        _fail(f"malformed {label}: {exc}")


def _validate_source_metadata(
    source_bytes: dict[str, bytes], config: dict[str, Any]
) -> None:
    project_member = config["project_member"]
    version_member = config["version_member"]
    project = _mapping(
        _json_bytes(source_bytes[project_member], project_member), project_member
    )
    try:
        scene = project["__content"][0]["scenes"][0]
        content = scene["__content"][0]
        children = content["overrides"]["children"]
        expected_object_id = config["project_metadata"]["object_identifier"]
        child = children[expected_object_id]
        arguments = dict(child["overrides"]["arguments"])
        runtime_attributes = dict(child["overrides"]["runtimeAttributes"])
        actual = {
            "project_version": project["__version"],
            "scene_version": scene["__version"],
            "scene_identifier": content["identifier"],
            "object_identifier": expected_object_id,
            "runtime_identifier": runtime_attributes["RuntimeIdentifier"]["value"],
            "primitive_factory": child["overrides"]["factory"],
            "primitive_type": arguments["type"]["value"],
            "material": arguments["material"]["value"],
            "scene_material": content["material"],
            "title": content["title"],
        }
    except (KeyError, IndexError, TypeError, ValueError) as exc:
        _fail(f"source project metadata is not readable: {exc}")

    expected = config["project_metadata"]
    for key, actual_value in actual.items():
        if actual_value != expected[key]:
            _fail(
                f"source project metadata mismatch: {key} "
                f"(expected {expected[key]!r}, got {actual_value!r})"
            )

    version = _mapping(_json_bytes(source_bytes[version_member], version_member), version_member)
    expected_version = config["version_metadata"]
    actual_version = {
        "version": version.get("Version"),
        "library_id": version.get("LibraryID"),
    }
    for key, actual_value in actual_version.items():
        if actual_value != expected_version[key]:
            _fail(
                f"source Version.json metadata mismatch: {key} "
                f"(expected {expected_version[key]!r}, got {actual_value!r})"
            )


def _validate_exported_usdz(
    root: Path, config: dict[str, Any]
) -> tuple[dict[str, bytes], dict[str, zipfile.ZipInfo]]:
    exported_path = root / config["exported_path"]
    if not exported_path.is_file() or exported_path.is_symlink():
        _fail(f"missing Circle.usdz file: {config['exported_path']}")
    size, digest = _digest_file(exported_path)
    if digest != config["exported_hash"]:
        _fail(
            f"exported USDZ hash mismatch: expected {config['exported_hash']}, got {digest}"
        )
    if size != config["exported_size"]:
        _fail(
            f"exported USDZ size mismatch: expected {config['exported_size']}, got {size}"
        )

    try:
        archive = zipfile.ZipFile(exported_path)
    except (OSError, zipfile.BadZipFile) as exc:
        _fail(f"exported USDZ is not a readable ZIP archive: {exc}")

    with archive:
        infos = archive.infolist()
        actual_infos: dict[str, zipfile.ZipInfo] = {}
        for info in infos:
            name = info.filename
            relative = _safe_relative_path(name, "USDZ member name")
            if info.is_dir() or name.endswith("/"):
                _fail(f"extra USDZ member: {relative}")
            if relative in actual_infos:
                _fail(f"duplicate USDZ member: {relative}")
            actual_infos[relative] = info

        expected_paths = set(config["exported_members"])
        actual_path_set = set(actual_infos)
        missing = sorted(expected_paths - actual_path_set)
        extra = sorted(actual_path_set - expected_paths)
        if missing:
            _fail(f"missing USDZ member: {missing[0]}")
        if extra:
            _fail(f"extra USDZ member: {extra[0]}")

        member_bytes: dict[str, bytes] = {}
        for relative, expected in config["exported_members"].items():
            try:
                raw = archive.read(actual_infos[relative])
            except (OSError, KeyError, RuntimeError, zipfile.BadZipFile) as exc:
                _fail(f"cannot read USDZ member {relative}: {exc}")
            digest = _digest_bytes(raw)
            if len(raw) != expected["size"]:
                _fail(
                    f"USDZ member size mismatch: {relative} "
                    f"(expected {expected['size']}, got {len(raw)})"
                )
            if digest != expected["sha256"]:
                _fail(
                    f"USDZ member hash mismatch: {relative} "
                    f"(expected {expected['sha256']}, got {digest})"
                )
            member_bytes[relative] = raw
    return member_bytes, actual_infos


def _validate_export_metadata(
    member_bytes: dict[str, bytes], config: dict[str, Any]
) -> None:
    expected_metadata = config["export_metadata"]
    expected_member = next(iter(config["exported_members"]))
    raw = member_bytes[expected_member]
    magic = expected_metadata["member_format"].encode("ascii")
    if not raw.startswith(magic):
        _fail(
            f"USDZ member format mismatch: expected {expected_metadata['member_format']}"
        )
    member_identifier = expected_metadata["member_identifier"]
    if PurePosixPath(expected_member).stem != member_identifier:
        _fail("malformed record: exported member identifier does not match its path")
    metadata_key = expected_metadata["rcfoundation_metadata_key"].encode("ascii")
    version = expected_metadata["rcfoundation_version"].encode("ascii")
    key_index = raw.find(metadata_key)
    version_index = raw.find(version)
    if key_index < 0 or version_index < key_index:
        _fail(
            "exported USDZ metadata mismatch: missing RCFoundation version metadata"
        )


def _validate_shared_identifiers(
    source_bytes: dict[str, bytes], member_bytes: dict[str, bytes], config: dict[str, Any]
) -> None:
    for index, identifier in enumerate(config["shared_identifiers"]):
        source_member = identifier["source_member"]
        export_member = identifier["export_member"]
        source_value = identifier["source_value"]
        export_value = identifier["export_value"]
        if _normalize_uuid(source_value) != _normalize_uuid(export_value):
            _fail(f"broken shared identifier: values differ at index {index}")
        if source_value.encode("ascii") not in source_bytes[source_member]:
            _fail(
                f"broken shared identifier: source value missing from {source_member}"
            )
        exported_needle = _normalize_uuid(export_value).encode("ascii")
        if exported_needle not in member_bytes[export_member].upper():
            _fail(
                f"broken shared identifier: export value missing from {export_member}"
            )


def validate_record(repo_root: Path, record_path: Path) -> None:
    """Validate recorded bytes and correlation predicates without external IO."""

    record = _load_record(record_path)
    config = _validate_record_shape(record)
    source_bytes = _validate_source_project(repo_root, config)
    _validate_source_metadata(source_bytes, config)
    member_bytes, _ = _validate_exported_usdz(repo_root, config)
    _validate_export_metadata(member_bytes, config)
    _validate_shared_identifiers(source_bytes, member_bytes, config)


def _resolve_record_path(repo_root: Path, value: Path) -> Path:
    if value.is_absolute():
        return value
    return repo_root / value


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Validate Circle repository-correlation evidence."
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="repository root containing shafinMultitool/ (default: script repository)",
    )
    parser.add_argument(
        "--record",
        type=Path,
        default=DEFAULT_RECORD_PATH,
        help="provenance JSON record (default: docs/implementation/provenance/circle-asset-provenance.json)",
    )
    args = parser.parse_args(argv)
    repo_root = args.repo_root.resolve()
    record_path = _resolve_record_path(repo_root, args.record).resolve()
    try:
        validate_record(repo_root, record_path)
    except ProvenanceValidationError as exc:
        print(f"FAIL Circle repository-correlation validation: {exc}", file=sys.stderr)
        return 1
    print(
        "PASS Circle repository correlation verified: recorded source/export bytes, "
        "member sets, metadata predicates and shared UUID correlation verified; "
        "source-to-export causality is not proven. "
        f"{ANNOTATION_SCOPE_MESSAGE}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
