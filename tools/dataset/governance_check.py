#!/usr/bin/env python3
"""Stdlib-only M3-001 dataset release-manifest and hash check."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = ROOT / "datasets/schemas/dataset-version-v1.schema.json"
FIXTURE_PATH = ROOT / "datasets/schemas/fixtures/dataset-version-v1.valid.json"
COMPONENTS = (
    "data",
    "label_schema",
    "split",
    "rights_manifest",
    "feature_schema",
    "evaluator",
    "model_candidate",
)
TOP_LEVEL_KEYS = {
    "schema_id",
    "dataset_id",
    "dataset_version",
    *COMPONENTS,
    "rights_status",
    "unresolved_rights_count",
    "unresolved_annotator_disagreement_count",
    "cross_split_leak_count",
    "quota_inflation_count",
    "non_independent_derivative_count",
    "storage",
    "access_control",
    "retention",
    "release",
}
IDENTITY_KEYS = {"id", "version", "sha256"}
STORAGE_KEYS = {
    "addressing",
    "hash_algorithm",
    "raw_data_location",
    "rights_uncleared_location",
}
ACCESS_KEYS = {"policy_id", "reader_roles", "writer_roles"}
RETENTION_KEYS = {
    "policy_id",
    "raw_data_days",
    "derived_data_days",
    "release_manifest",
    "deletion_requires_new_version",
}
RELEASE_KEYS = {
    "status",
    "hash_algorithm",
    "canonicalization",
    "created_at",
    "manifest_sha256",
}
ROLE_VALUES = {
    "dataset-owner",
    "annotator",
    "adjudicator",
    "ml-trainer",
    "ml-evaluator",
    "release-owner",
}
ZERO_REQUIRED_COUNTS = (
    "unresolved_rights_count",
    "unresolved_annotator_disagreement_count",
    "cross_split_leak_count",
    "quota_inflation_count",
    "non_independent_derivative_count",
)
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
ID_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
VERSION_RE = re.compile(r"^v[0-9]+\.[0-9]+\.[0-9]+$")
DATE_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")


def _read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


def canonical_bytes(manifest: dict[str, Any]) -> bytes:
    """Return the v1 canonical bytes, excluding the self-referential digest."""

    payload = copy.deepcopy(manifest)
    release = payload.get("release")
    if isinstance(release, dict):
        release.pop("manifest_sha256", None)
    return json.dumps(
        payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def manifest_sha256(manifest: dict[str, Any]) -> str:
    return hashlib.sha256(canonical_bytes(manifest)).hexdigest()


def validate_schema_declaration(schema: dict[str, Any]) -> list[str]:
    required = set(schema.get("required", []))
    expected = {
        "data",
        "label_schema",
        "split",
        "rights_manifest",
        "feature_schema",
        "evaluator",
        "model_candidate",
        "rights_status",
        "unresolved_rights_count",
        "release",
    }
    missing = sorted(expected - required)
    return [f"schema missing required field: {field}" for field in missing]


def _validate_identity(name: str, value: Any) -> list[str]:
    if not isinstance(value, dict):
        return [f"{name} must be an object"]
    errors: list[str] = []
    unknown = sorted(set(value) - IDENTITY_KEYS)
    errors.extend(f"{name} has unknown field: {field}" for field in unknown)
    for field in sorted(IDENTITY_KEYS - set(value)):
        errors.append(f"{name} missing field: {field}")
    if not isinstance(value.get("id"), str) or not ID_RE.fullmatch(value.get("id", "")):
        errors.append(f"{name}.id must be a lowercase identifier")
    if not isinstance(value.get("version"), str) or not VERSION_RE.fullmatch(value.get("version", "")):
        errors.append(f"{name}.version must use vMAJOR.MINOR.PATCH")
    if not isinstance(value.get("sha256"), str) or not SHA256_RE.fullmatch(value.get("sha256", "")):
        errors.append(f"{name}.sha256 must be lowercase SHA-256")
    return errors


def validate_manifest(manifest: dict[str, Any]) -> list[str]:
    required = {
        "schema_id",
        "dataset_id",
        "dataset_version",
        *COMPONENTS,
        "rights_status",
        "unresolved_rights_count",
        "unresolved_annotator_disagreement_count",
        "cross_split_leak_count",
        "quota_inflation_count",
        "non_independent_derivative_count",
        "storage",
        "access_control",
        "retention",
        "release",
    }
    errors = [f"manifest missing field: {field}" for field in sorted(required - set(manifest))]
    errors.extend(
        f"manifest has unknown field: {field}"
        for field in sorted(set(manifest) - TOP_LEVEL_KEYS)
    )
    if manifest.get("schema_id") != "dataset-version-v1":
        errors.append("schema_id must be dataset-version-v1")
    if not isinstance(manifest.get("dataset_id"), str) or not ID_RE.fullmatch(manifest.get("dataset_id", "")):
        errors.append("dataset_id must be a lowercase identifier")
    if not isinstance(manifest.get("dataset_version"), str) or not VERSION_RE.fullmatch(manifest.get("dataset_version", "")):
        errors.append("dataset_version must use vMAJOR.MINOR.PATCH")

    for component in COMPONENTS:
        errors.extend(_validate_identity(component, manifest.get(component)))

    if manifest.get("rights_status") != "approved":
        errors.append("rights_status must be approved")
    for field in ZERO_REQUIRED_COUNTS:
        count = manifest.get(field)
        if not isinstance(count, int) or isinstance(count, bool) or count < 0:
            errors.append(f"{field} must be a non-negative integer")
        elif count != 0:
            errors.append(f"{field} must be zero")

    storage = manifest.get("storage")
    if not isinstance(storage, dict):
        errors.append("storage must be an object")
    else:
        errors.extend(
            f"storage has unknown field: {field}"
            for field in sorted(set(storage) - STORAGE_KEYS)
        )
        expected_storage = {
            "addressing": "content-addressed",
            "hash_algorithm": "sha256",
            "raw_data_location": "outside_git",
            "rights_uncleared_location": "outside_git",
        }
        for field, expected in expected_storage.items():
            if storage.get(field) != expected:
                errors.append(f"storage.{field} must be {expected}")

    access = manifest.get("access_control")
    if not isinstance(access, dict):
        errors.append("access_control must be an object")
    else:
        errors.extend(
            f"access_control has unknown field: {field}"
            for field in sorted(set(access) - ACCESS_KEYS)
        )
        if not isinstance(access.get("policy_id"), str) or not ID_RE.fullmatch(access.get("policy_id", "")):
            errors.append("access_control.policy_id must be a lowercase identifier")
        for field in ("reader_roles", "writer_roles"):
            roles = access.get(field)
            if (
                not isinstance(roles, list)
                or not roles
                or any(not isinstance(role, str) or role not in ROLE_VALUES for role in roles)
                or len(set(roles)) != len(roles)
            ):
                errors.append(
                    f"access_control.{field} must be a non-empty unique list of known roles"
                )

    retention = manifest.get("retention")
    if not isinstance(retention, dict):
        errors.append("retention must be an object")
    else:
        errors.extend(
            f"retention has unknown field: {field}"
            for field in sorted(set(retention) - RETENTION_KEYS)
        )
        if not isinstance(retention.get("policy_id"), str) or not ID_RE.fullmatch(retention.get("policy_id", "")):
            errors.append("retention.policy_id must be a lowercase identifier")
        for field in ("raw_data_days", "derived_data_days"):
            if not isinstance(retention.get(field), int) or isinstance(retention.get(field), bool) or retention[field] < 1:
                errors.append(f"retention.{field} must be a positive integer")
        if retention.get("release_manifest") != "permanent":
            errors.append("retention.release_manifest must be permanent")
        if retention.get("deletion_requires_new_version") is not True:
            errors.append("retention.deletion_requires_new_version must be true")

    release = manifest.get("release")
    if not isinstance(release, dict):
        errors.append("release must be an object")
    else:
        errors.extend(
            f"release has unknown field: {field}"
            for field in sorted(set(release) - RELEASE_KEYS)
        )
        if release.get("status") != "frozen":
            errors.append("release.status must be frozen")
        if release.get("hash_algorithm") != "sha256":
            errors.append("release.hash_algorithm must be sha256")
        if release.get("canonicalization") != "json-sort-keys-utf8-no-whitespace-v1":
            errors.append("release.canonicalization must be json-sort-keys-utf8-no-whitespace-v1")
        if not isinstance(release.get("created_at"), str) or not DATE_RE.fullmatch(release.get("created_at", "")):
            errors.append("release.created_at must be UTC RFC3339 seconds")
        declared = release.get("manifest_sha256")
        if not isinstance(declared, str) or not SHA256_RE.fullmatch(declared):
            errors.append("release.manifest_sha256 must be lowercase SHA-256")
        elif declared != manifest_sha256(manifest):
            errors.append("release.manifest_sha256 does not match canonical manifest")
    return errors


def check_manifest(path: Path) -> list[str]:
    try:
        schema = _read_json(SCHEMA_PATH)
        manifest = _read_json(path)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        return [str(exc)]
    return validate_schema_declaration(schema) + validate_manifest(manifest)


def self_test() -> None:
    schema = _read_json(SCHEMA_PATH)
    fixture = _read_json(FIXTURE_PATH)
    assert validate_schema_declaration(schema) == []
    assert validate_manifest(fixture) == []
    digest = manifest_sha256(fixture)
    assert fixture["release"]["manifest_sha256"] == digest

    round_trip = json.loads(json.dumps(fixture, ensure_ascii=False, sort_keys=True))
    assert manifest_sha256(round_trip) == digest

    missing_rights = copy.deepcopy(fixture)
    del missing_rights["rights_status"]
    assert any("rights_status" in error for error in validate_manifest(missing_rights))

    unknown_rights = copy.deepcopy(fixture)
    unknown_rights["rights_status"] = "unknown"
    assert any("rights_status" in error for error in validate_manifest(unknown_rights))

    stale_hash = copy.deepcopy(fixture)
    stale_hash["dataset_version"] = "v1.0.1"
    assert any("manifest_sha256" in error for error in validate_manifest(stale_hash))

    missing_component = copy.deepcopy(fixture)
    del missing_component["model_candidate"]
    assert any("model_candidate" in error for error in validate_manifest(missing_component))

    unknown_field = copy.deepcopy(fixture)
    unknown_field["release"]["unreviewed_note"] = "must be rejected"
    assert any("unknown field" in error for error in validate_manifest(unknown_field))

    unknown_role = copy.deepcopy(fixture)
    unknown_role["access_control"]["reader_roles"] = ["unknown-role"]
    assert any("known roles" in error for error in validate_manifest(unknown_role))

    disagreement = copy.deepcopy(fixture)
    disagreement["unresolved_annotator_disagreement_count"] = 1
    assert any(
        "unresolved_annotator_disagreement_count" in error
        for error in validate_manifest(disagreement)
    )

    cross_split_leak = copy.deepcopy(fixture)
    cross_split_leak["cross_split_leak_count"] = 1
    assert any(
        "cross_split_leak_count" in error
        for error in validate_manifest(cross_split_leak)
    )

    quota_inflation = copy.deepcopy(fixture)
    quota_inflation["quota_inflation_count"] = 1
    assert any(
        "quota_inflation_count" in error
        for error in validate_manifest(quota_inflation)
    )

    derivative_inflation = copy.deepcopy(fixture)
    derivative_inflation["non_independent_derivative_count"] = 1
    assert any(
        "non_independent_derivative_count" in error
        for error in validate_manifest(derivative_inflation)
    )

    print(f"PASS M3-001 self-test fixture_sha256={digest}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=FIXTURE_PATH)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)
    if args.self_test:
        self_test()
        return 0
    errors = check_manifest(args.manifest)
    if errors:
        for error in errors:
            print(f"FAIL {error}", file=sys.stderr)
        return 1
    manifest = _read_json(args.manifest)
    print(f"PASS {args.manifest} manifest_sha256={manifest_sha256(manifest)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
