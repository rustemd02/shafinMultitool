#!/usr/bin/env python3
"""Fail-closed validator for a Camera Coach owner rights attestation.

The owner (and only the owner) decides data rights. This module does not make
that decision for them: it checks that a filled attestation file is complete,
internally consistent, backed by an explicit basis, and does not claim
production/release permission for corpora the audit already classified as
research-only (AVA / AADB / EVA).

Exit codes:
  0  attestation is complete and admissible under these rules
  1  attestation missing, incomplete, inconsistent, or barred

No network access. No writes except when --print-template is used.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

SCHEMA_ID = "camera-rights-attestation-v1"
SCHEMA_VERSION = "v1.0.0"

# Corpora that the D01/D05 audit classified research-only. A rights decision is
# allowed to keep them research-only; it is never allowed to mark them
# production/release admissible.
BARRED_PRODUCTION_TOKENS = ("ava", "aadb", "eva")

# Tokens that mean "the owner has not decided yet". Any of these (or None or an
# empty string/list) is treated as a missing field, never as consent.
PENDING_SENTINELS = {"", "pending", "tbd", "todo", "unknown", "n/a", "na"}

DECISION_VALUES = {"admit", "quarantine", "reject"}
BASIS_TYPES = {
    "owner_authorship",
    "license",
    "public_domain",
    "written_permission",
    "synthetic_lineage",
    "other",
}

_HEX64 = re.compile(r"^[0-9a-f]{64}$")
_ISO = re.compile(r"^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2}))?$")
_BARRED = re.compile(r"(?:^|[^a-z])(" + "|".join(BARRED_PRODUCTION_TOKENS) + r")(?:[^a-z]|$)")

# (dotted path, kind, human description). Every one of these must be filled by
# the owner; nothing is inferred from file presence.
REQUIRED_FIELDS: tuple[tuple[str, str, str], ...] = (
    ("attestation_schema_id", "literal", f"must equal {SCHEMA_ID}"),
    ("attestation_version", "literal", f"must equal {SCHEMA_VERSION}"),
    ("attester.attester_id", "string", "who is making the attestation"),
    ("attester.attester_name", "string", "legal/person name of the attester"),
    ("attester.attester_role", "string", "role, e.g. dataset-owner"),
    ("attested_at", "date", "ISO-8601 date the decision was made"),
    ("corpus.corpus_id", "string", "which corpus this decision covers"),
    ("corpus.source_id", "string", "which source/catalog id it maps to"),
    ("corpus.manifest_sha256", "hex64", "sha256 of the manifest being admitted"),
    ("license.license_id", "string", "license identifier (e.g. CC-BY-3.0)"),
    ("license.license_url", "string", "canonical license URL"),
    ("license.attribution_required", "bool", "does the license require attribution?"),
    ("permissions.production_allowed", "bool", "may this corpus feed production weights?"),
    ("permissions.redistribution_allowed", "bool", "may raw/derived media be redistributed?"),
    ("people.people_present", "bool", "are identifiable people in frame?"),
    ("people.consent_obtained", "bool", "is consent obtained (or not applicable)?"),
    ("people.consent_reference", "string", "reference to consent, or 'not_applicable'"),
    ("basis.basis_type", "enum", "one of: " + ", ".join(sorted(BASIS_TYPES))),
    ("basis.basis_reference", "string", "reference to the legal/ownership basis"),
    ("decision.admitted", "bool", "owner decision: corpus admitted?"),
    ("decision.decision", "enum", "one of: " + ", ".join(sorted(DECISION_VALUES))),
    ("decision.decision_scope", "string", "what the decision covers (train/eval/release)"),
)


def _get(data: dict[str, Any], path: str) -> Any:
    node: Any = data
    for part in path.split("."):
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    return node


def is_filled(value: Any) -> bool:
    """A value is only 'filled' when it is explicit and not a pending sentinel."""
    if value is None:
        return False
    if isinstance(value, bool):
        return True
    if isinstance(value, str):
        return value.strip().lower() not in PENDING_SENTINELS
    if isinstance(value, (list, tuple, dict)):
        return len(value) > 0
    return True


def _barred_sources(data: dict[str, Any]) -> list[str]:
    corpus = _get(data, "corpus") or {}
    if not isinstance(corpus, dict):
        return []
    haystack = " ".join(
        str(corpus.get(key) or "")
        for key in ("corpus_id", "source_id", "source_path", "corpus_name")
    ).lower()
    return sorted({m.group(1) for m in _BARRED.finditer(haystack)})


def validate(data: dict[str, Any]) -> list[str]:
    """Return a list of human-readable errors. Empty list means admissible."""
    errors: list[str] = []

    # Schema identity.
    if _get(data, "attestation_schema_id") != SCHEMA_ID:
        errors.append(
            f"attestation_schema_id must be '{SCHEMA_ID}', got "
            f"{_get(data, 'attestation_schema_id')!r}"
        )
    if _get(data, "attestation_version") != SCHEMA_VERSION:
        errors.append(
            f"attestation_version must be '{SCHEMA_VERSION}', got "
            f"{_get(data, 'attestation_version')!r}"
        )

    # Required fields, by kind.
    for path, kind, description in REQUIRED_FIELDS:
        value = _get(data, path)
        if not is_filled(value):
            errors.append(f"missing/empty required field '{path}' ({description})")
            continue
        if kind == "bool" and not isinstance(value, bool):
            errors.append(f"field '{path}' must be a JSON boolean, got {type(value).__name__}")
        elif kind == "hex64" and not (isinstance(value, str) and _HEX64.match(value)):
            errors.append(f"field '{path}' must be a 64-char lowercase sha256 hex")
        elif kind == "date" and not (isinstance(value, str) and _ISO.match(value)):
            errors.append(f"field '{path}' must be an ISO-8601 date, got {value!r}")
        elif kind == "enum":
            allowed = BASIS_TYPES if path == "basis.basis_type" else DECISION_VALUES
            if value not in allowed:
                errors.append(f"field '{path}' must be one of {sorted(allowed)}, got {value!r}")

    # Basis must be an actual link or hash, not a bare assertion.
    if is_filled(_get(data, "basis.basis_reference")) and not (
        is_filled(_get(data, "basis.basis_url")) or is_filled(_get(data, "basis.basis_sha256"))
    ):
        errors.append(
            "basis.basis_reference is set but neither 'basis.basis_url' nor "
            "'basis.basis_sha256' is provided: admitted needs a linked basis"
        )

    admitted = _get(data, "decision.admitted")
    decision = _get(data, "decision.decision")

    # admitted=true without a linked basis is exactly the hole this check closes.
    if admitted is True and not (
        is_filled(_get(data, "basis.basis_type"))
        and is_filled(_get(data, "basis.basis_reference"))
        and (is_filled(_get(data, "basis.basis_url")) or is_filled(_get(data, "basis.basis_sha256")))
    ):
        errors.append("decision.admitted=true without a complete, linked basis")

    # Decision/admitted consistency.
    if decision == "admit" and admitted is not True:
        errors.append("decision.decision='admit' requires decision.admitted=true")
    if admitted is True and decision != "admit":
        errors.append("decision.admitted=true requires decision.decision='admit'")
    if admitted is False and decision == "admit":
        errors.append("decision.decision='admit' contradicts decision.admitted=false")

    # Attribution: a license that requires attribution needs an owner-provided
    # attribution source, otherwise no author string may be emitted downstream.
    if is_filled(_get(data, "license.attribution_required")) and _get(
        data, "license.attribution_required"
    ) is True and admitted is True:
        attribution = _get(data, "attribution") or {}
        ref = attribution.get("attribution_map_ref") if isinstance(attribution, dict) else None
        per_film = attribution.get("per_film") if isinstance(attribution, dict) else None
        if not (is_filled(ref) or is_filled(per_film)):
            errors.append(
                "license requires attribution and corpus is admitted, but no "
                "attribution source is provided (attribution.attribution_map_ref "
                "or attribution.per_film)"
            )

    # People / consent consistency.
    people_present = _get(data, "people.people_present")
    consent_obtained = _get(data, "people.consent_obtained")
    consent_ref = _get(data, "people.consent_reference")
    if people_present is True:
        if consent_obtained is not True:
            errors.append("people.people_present=true requires people.consent_obtained=true")
        if not is_filled(consent_ref):
            errors.append("people.people_present=true requires a consent reference")
    elif people_present is False:
        if not is_filled(consent_ref):
            errors.append(
                "people.people_present=false still requires people.consent_reference "
                "(use 'not_applicable')"
            )

    # Barred corpora: AVA / AADB / EVA can never be production/release-cleared.
    barred = _barred_sources(data)
    if barred:
        p = "permissions.production_allowed"
        r = "permissions.redistribution_allowed"
        if _get(data, p) is True:
            errors.append(
                f"corpus matches research-only source(s) {barred}: "
                f"{p}=true is forbidden (D01/D05 audit: never production-cleared)"
            )
        if _get(data, r) is True:
            errors.append(
                f"corpus matches research-only source(s) {barred}: "
                f"{r}=true is forbidden (no redistribution rights confirmed)"
            )
        if admitted is True or decision == "admit":
            errors.append(
                f"corpus matches research-only source(s) {barred}: admitting it as "
                "release-clearable contradicts the audit; keep it quarantine/research-only"
            )

    return errors


def missing_summary(data: dict[str, Any]) -> list[str]:
    """Fields the owner still has to fill, for status/refusal messages."""
    missing: list[str] = []
    for path, _kind, description in REQUIRED_FIELDS:
        if not is_filled(_get(data, path)):
            missing.append(f"{path}: {description}")
    return missing


def load_attestation(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError("attestation root must be a JSON object")
    return data


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--attestation", type=Path, help="owner-filled attestation JSON")
    parser.add_argument(
        "--print-missing",
        action="store_true",
        help="on failure, list every unfilled owner field",
    )
    args = parser.parse_args(argv)

    if args.attestation is None:
        print("REFUSED: --attestation is required; no owner decision was provided.", file=sys.stderr)
        return 1
    if not args.attestation.exists():
        print(f"REFUSED: attestation file not found: {args.attestation}", file=sys.stderr)
        return 1

    try:
        data = load_attestation(args.attestation)
    except (json.JSONDecodeError, ValueError) as exc:
        print(f"REFUSED: cannot parse attestation: {exc}", file=sys.stderr)
        return 1

    errors = validate(data)
    if errors:
        print(f"REFUSED: attestation is not admissible ({len(errors)} problem(s)):", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        if args.print_missing:
            missing = missing_summary(data)
            if missing:
                print("Owner must fill:", file=sys.stderr)
                for item in missing:
                    print(f"  - {item}", file=sys.stderr)
        return 1

    print(
        "OK: attestation is complete and admissible "
        f"({data.get('corpus', {}).get('corpus_id')} admitted by "
        f"{data.get('attester', {}).get('attester_id')})."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
