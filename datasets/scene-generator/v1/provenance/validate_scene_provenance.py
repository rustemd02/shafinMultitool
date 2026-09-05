#!/usr/bin/env python3
"""Validate the versioned SET OS Scene Generator provenance manifests (M3-024).

Stdlib-only runner; Draft 2020-12 validation is mandatory when the
`jsonschema` package is installed and the run fails closed when it is not.
Semantic checks enforce the cross-record rules JSON Schema cannot express:

- the first record of each manifest is its header and `record_count` matches;
- record/source identifiers are unique inside a manifest;
- every source entry links to exactly one rights entry by
  `rights_record_id`, and every rights entry back-links to a source entry;
- an approved rights entry requires a lawful basis that is not `unknown`,
  the matching evidence object for its basis, and an admitted status with
  non-high/unknown copyright risk;
- a `copyrighted_screenplay_excerpt` can never be admitted: its rights
  record must be denied/quarantined and the source excluded;
- synthetic lineage parents must resolve to declared source records;
- a production manifest (template_only=false) cannot ship zero records.

Raw text and rights-uncleared material are declared `outside_git` by the
schema itself and never travel inside these manifests.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent
PROVENANCE = ROOT
SCHEMA = PROVENANCE / "scene-provenance-v1.schema.json"
FIXTURES = PROVENANCE / "fixtures"

SOURCE_HEADER_TYPE = "source_manifest"
RIGHTS_HEADER_TYPE = "rights_manifest"


class ProvenanceError(Exception):
    """One deterministic validation failure with a stable message."""


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            stripped = line.strip()
            if not stripped:
                continue
            try:
                records.append(json.loads(stripped))
            except json.JSONDecodeError as error:
                raise ProvenanceError(
                    f"{path.name}:{line_number}: invalid JSON ({error.msg})"
                ) from error
    return records


def validate_against_schema(records: list[dict[str, Any]], path: Path) -> None:
    try:
        from jsonschema import Draft202012Validator
    except ImportError as error:  # pragma: no cover - environment guard
        raise ProvenanceError(
            "jsonschema (Draft 2020-12) is required for provenance validation; "
            "the check fails closed without it"
        ) from error

    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    validator = Draft202012Validator(schema)
    for index, record in enumerate(records):
        errors = sorted(validator.iter_errors(record), key=lambda e: list(e.path))
        if errors:
            location = "/".join(str(part) for part in errors[0].path) or "<root>"
            raise ProvenanceError(
                f"{path.name}: record {index} fails schema at '{location}': "
                f"{errors[0].message}"
            )


def split_header(records: list[dict[str, Any]], expected_type: str, path: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    if not records:
        raise ProvenanceError(f"{path.name}: manifest is empty")
    header = records[0]
    if header.get("manifest_type") != expected_type:
        raise ProvenanceError(
            f"{path.name}: first record must be a {expected_type} header, "
            f"got {header.get('manifest_type')!r}"
        )
    entries = records[1:]
    if header.get("record_count") != len(entries):
        raise ProvenanceError(
            f"{path.name}: header record_count {header.get('record_count')} "
            f"!= {len(entries)} entries"
        )
    if header.get("template_only") and entries:
        raise ProvenanceError(
            f"{path.name}: template_only manifest must not carry entries"
        )
    if not header.get("template_only") and not entries:
        raise ProvenanceError(
            f"{path.name}: production manifest (template_only=false) cannot ship zero records"
        )
    return header, entries


def unique_ids(entries: list[dict[str, Any]], key: str, path: Path) -> dict[str, dict[str, Any]]:
    seen: dict[str, dict[str, Any]] = {}
    for entry in entries:
        value = entry.get(key)
        if value in seen:
            raise ProvenanceError(f"{path.name}: duplicate {key} {value!r}")
        seen[value] = entry
    return seen


EVIDENCE_BY_BASIS = {
    "owner_authored": "author_evidence",
    "licensed": "license_evidence",
    "public_domain": "public_domain_evidence",
    "synthetic": "synthetic_evidence",
}


def cross_check(
    source_header: dict[str, Any],
    source_entries: list[dict[str, Any]],
    rights_header: dict[str, Any],
    rights_entries: list[dict[str, Any]],
) -> None:
    if source_header.get("manifest_sha256") != rights_header.get("manifest_sha256"):
        # The two headers must bind to one shared corpus snapshot so a mixed
        # pair cannot validate as a whole.
        raise ProvenanceError(
            "source and rights manifests bind different corpus snapshots "
            "(manifest_sha256 mismatch)"
        )

    rights_by_id = unique_ids(rights_entries, "rights_record_id", Path("rights-manifest.jsonl"))
    unique_ids(rights_entries, "record_id", Path("rights-manifest.jsonl"))
    source_by_id = unique_ids(source_entries, "source_id", Path("source-manifest.jsonl"))
    unique_ids(source_entries, "record_id", Path("source-manifest.jsonl"))

    for entry in source_entries:
        rights_id = entry.get("rights_record_id")
        rights = rights_by_id.get(rights_id)
        if rights is None:
            raise ProvenanceError(
                f"source entry {entry.get('source_id')!r} links missing "
                f"rights record {rights_id!r}"
            )
        for pair in (
            ("source_id", "source_id"),
            ("content_sha256", "content_sha256"),
            ("source_sha256", "source_sha256"),
        ):
            if entry.get(pair[0]) != rights.get(pair[1]):
                raise ProvenanceError(
                    f"source entry {entry.get('source_id')!r} and rights record "
                    f"{rights_id!r} disagree on {pair[0]}/{pair[1]}"
                )
        if rights.get("source_kind") != entry.get("source_kind"):
            raise ProvenanceError(
                f"source entry {entry.get('source_id')!r} and rights record "
                f"{rights_id!r} disagree on source_kind"
            )

    for rights in rights_entries:
        source_id = rights.get("source_id")
        if source_id not in source_by_id:
            raise ProvenanceError(
                f"rights record {rights.get('rights_record_id')!r} references "
                f"undeclared source {source_id!r}"
            )

        basis = rights.get("lawful_basis")
        status = rights.get("rights_status")
        admission = rights.get("admission_status")
        kind = rights.get("source_kind")

        if kind == "copyrighted_screenplay_excerpt":
            # Fail-closed: a copyrighted screenplay excerpt can never be
            # admitted while its rights are unresolved.
            if status not in ("denied", "quarantined"):
                raise ProvenanceError(
                    f"copyrighted excerpt {source_id!r} has rights_status "
                    f"{status!r}; denied/quarantined required"
                )
            if admission != "excluded":
                raise ProvenanceError(
                    f"copyrighted excerpt {source_id!r} must be excluded, "
                    f"got {admission!r}"
                )

        if status == "approved":
            if basis == "unknown":
                raise ProvenanceError(
                    f"rights record {rights.get('rights_record_id')!r} approves "
                    f"an unknown lawful basis"
                )
            evidence_key = EVIDENCE_BY_BASIS.get(basis)
            if evidence_key is None:
                raise ProvenanceError(
                    f"rights record {rights.get('rights_record_id')!r} has "
                    f"unhandled basis {basis!r}"
                )
            if not rights.get(evidence_key):
                raise ProvenanceError(
                    f"approved rights record {rights.get('rights_record_id')!r} "
                    f"is missing {evidence_key}"
                )
            if admission != "admitted":
                raise ProvenanceError(
                    f"approved rights record {rights.get('rights_record_id')!r} "
                    f"must be admitted, got {admission!r}"
                )
            if rights.get("copyright_risk") in ("high", "unknown"):
                raise ProvenanceError(
                    f"approved rights record {rights.get('rights_record_id')!r} "
                    f"carries {rights.get('copyright_risk')!r} copyright risk"
                )

    declared_ids = set(source_by_id)
    for rights in rights_entries:
        synthetic = rights.get("synthetic_evidence")
        if not synthetic:
            continue
        for parent in synthetic.get("parent_record_ids", []):
            if parent not in declared_ids:
                raise ProvenanceError(
                    f"synthetic rights record {rights.get('rights_record_id')!r} "
                    f"references undeclared lineage parent {parent!r}"
                )


def validate_pair(source_path: Path, rights_path: Path) -> dict[str, Any]:
    source_records = load_jsonl(source_path)
    rights_records = load_jsonl(rights_path)
    validate_against_schema(source_records, source_path)
    validate_against_schema(rights_records, rights_path)
    source_header, source_entries = split_header(source_records, SOURCE_HEADER_TYPE, source_path)
    rights_header, rights_entries = split_header(rights_records, RIGHTS_HEADER_TYPE, rights_path)
    cross_check(source_header, source_entries, rights_header, rights_entries)
    return {
        "source_header": source_header,
        "rights_header": rights_header,
        "source_entries": len(source_entries),
        "rights_entries": len(rights_entries),
    }


def self_test() -> int:
    positive = FIXTURES / "positive-synthetic-pair"
    report = validate_pair(
        positive / "source-manifest.jsonl",
        positive / "rights-manifest.jsonl",
    )
    if report["source_entries"] < 1 or report["rights_entries"] < 1:
        raise ProvenanceError("positive fixture must exercise at least one pair")

    negatives = sorted((FIXTURES / "negative").glob("*.json"))
    if len(negatives) < 5:
        raise ProvenanceError(
            f"expected at least 5 negative fixtures, found {len(negatives)}"
        )

    checked = 0
    for path in negatives:
        payload = json.loads(path.read_text(encoding="utf-8"))
        negative_source = FIXTURES / "negative" / payload["source_manifest"]
        negative_rights = FIXTURES / "negative" / payload["rights_manifest"]
        try:
            validate_pair(negative_source, negative_rights)
        except ProvenanceError as error:
            expected = payload["expected_error_contains"]
            if expected not in str(error):
                raise ProvenanceError(
                    f"{path.name}: failure message {str(error)!r} does not "
                    f"mention {expected!r}"
                ) from error
            checked += 1
        else:
            raise ProvenanceError(f"{path.name}: negative fixture unexpectedly passed")

    print(
        f"scene provenance v1: positive pair OK "
        f"({report['source_entries']} source / {report['rights_entries']} rights), "
        f"{checked} negative fixtures rejected"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="run the built-in positive/negative fixture matrix",
    )
    parser.add_argument("--source", type=Path, help="source manifest to validate")
    parser.add_argument("--rights", type=Path, help="rights manifest to validate")
    args = parser.parse_args()

    try:
        if args.self_test:
            return self_test()
        if not args.source or not args.rights:
            parser.error("--source and --rights are required without --self-test")
        report = validate_pair(args.source, args.rights)
        print(
            f"scene provenance v1: OK ({report['source_entries']} source / "
            f"{report['rights_entries']} rights records)"
        )
        return 0
    except ProvenanceError as error:
        print(f"scene provenance v1: FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
