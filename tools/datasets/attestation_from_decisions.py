#!/usr/bin/env python3
"""Turn short owner answers into a rights attestation and an attribution map.

The owner fills a small decisions file (``camera-owner-decisions-v1``, see
``docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-release/owner-decision-form.md``)
instead of hand-editing the 27-field attestation. This converter is the bridge.

Fail-closed rules:

* This tool never makes or defaults a rights decision. Every ``decision``,
  ``scope``, ``permissions``, ``people`` and ``basis`` value must come from the
  owner's file. Empty, ``null``, ``<...>`` or ``PENDING`` are "not decided" and
  cause a refusal (exit 1); nothing is written.
* Unambiguous facts about the license (license id/url, attribution requirement,
  the publisher-published Big Buck Bunny attribution string, publisher pages)
  may be filled from ``cinematic-license-facts.draft.json`` **with provenance**,
  because they are facts, not decisions. Author text is never inferred.
* The composed attestation must pass ``validate_rights_attestation.py`` before
  anything is written.
* ``--append-manifest`` is opt-in. Without it the tool prints the exact next
  command and writes no rights manifest; with it, only an already-admitted
  corpus is appended to the (JSONL) rights manifest, never overwritten.
* AVA / AADB / EVA can never be admitted, production/redistribution-allowed, or
  released here.

Exit codes:
  0  decisions were complete; attestation + attribution map written
  1  a decision is missing/placeholder, inconsistent, or barred (nothing written)
  2  the decisions file is missing or unparseable

No network access.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
import shlex
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]

DECISIONS_SCHEMA_ID = "camera-owner-decisions-v1"
ATTESTATION_SCHEMA_ID = "camera-rights-attestation-v1"
ATTESTATION_VERSION = "v1.0.0"
ATTRIBUTION_MAP_SCHEMA_ID = "camera-attribution-map-v1"
ATTRIBUTION_MAP_VERSION = "v1.0.0"

DEFAULT_FACTS = REPO_ROOT / "datasets/camera-coach/v1/cinematic-license-facts.draft.json"
DEFAULT_RIGHTS_MANIFEST = REPO_ROOT / "datasets/camera-coach/v1/rights-manifest.jsonl"

# Copied from the existing catalog/requirements drafts (build_split_groups.py
# uses the same defaults). These are corpus names, not a rights decision; the
# owner may override them under "corpus" in the decisions file.
DEFAULT_CORPUS_ID = "cinematic"
DEFAULT_SOURCE_ID = "cinematic"

DECISION_VALUES = ("admit", "quarantine", "reject")
SCOPE_VALUES = ("train+eval", "train+eval+release")
BASIS_TYPES = (
    "owner_authorship",
    "license",
    "public_domain",
    "written_permission",
    "synthetic_lineage",
    "other",
)

BARRED_PRODUCTION_TOKENS = ("ava", "aadb", "eva")
_BARRED = re.compile(r"(?:^|[^a-z])(" + "|".join(BARRED_PRODUCTION_TOKENS) + r")(?:[^a-z]|$)")

# Anything here means "the owner has not decided"; never treated as consent.
PENDING_SENTINELS = {
    "",
    "pending",
    "tbd",
    "todo",
    "unknown",
    "n/a",
    "na",
    "null",
    "none",
    "-",
}
_PLACEHOLDER = re.compile(r"<[^>]*>")


class Refusal(Exception):
    """A fail-closed refusal carrying every reason (exit 1)."""

    def __init__(self, problems: list[str]):
        self.problems = list(problems)
        super().__init__("; ".join(self.problems))


# --------------------------------------------------------------------------- #
# small helpers                                                               #
# --------------------------------------------------------------------------- #


def _load_module(name: str, filename: str):
    path = Path(__file__).resolve().parent / filename
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def is_filled(value: Any) -> bool:
    """False for empty / None / placeholder strings; True for explicit bools."""
    if value is None:
        return False
    if isinstance(value, bool):
        return True
    if isinstance(value, str):
        stripped = value.strip()
        if not stripped:
            return False
        if stripped.lower() in PENDING_SENTINELS:
            return False
        return _PLACEHOLDER.search(stripped) is None
    if isinstance(value, (list, tuple, dict)):
        return len(value) > 0
    return True


def _as_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def _join_unique(values) -> str:
    out: list[str] = []
    for value in values:
        if is_filled(value) and value not in out:
            out.append(str(value))
    return "; ".join(out)


def _barred_tokens(texts) -> list[str]:
    found: set[str] = set()
    for text in texts:
        for match in _BARRED.finditer(str(text or "").lower()):
            found.add(match.group(1))
    return sorted(found)


def _load_facts(path: Path) -> tuple[dict[str, Any], list[str]]:
    """Return (facts, notes). Missing/unreadable facts are not fatal by itself."""
    if not path.exists():
        return {}, [f"facts file not found, no fact fallback available: {path}"]
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, ValueError, OSError) as exc:
        return {}, [f"cannot read facts file {path}: {exc}"]
    if not isinstance(data, dict):
        return {}, [f"facts file is not a JSON object: {path}"]
    return data, []


# --------------------------------------------------------------------------- #
# completeness of the owner's answers                                         #
# --------------------------------------------------------------------------- #


def collect_problems(data: dict[str, Any], manifest_films: set[str] | None) -> list[str]:
    """List every missing/invalid owner decision. Empty list means complete."""
    problems: list[str] = []

    attester = _as_dict(data.get("attester"))
    for field, description in (
        ("attester_id", "who asserts this decision"),
        ("attester_name", "name"),
        ("attester_role", "role (e.g. dataset-owner)"),
    ):
        if not is_filled(attester.get(field)):
            problems.append(f"unfilled owner decision 'attester.{field}' ({description})")

    if not is_filled(data.get("attested_at")):
        problems.append("unfilled owner decision 'attested_at' (ISO-8601 date)")

    subsets = data.get("subsets")
    if not isinstance(subsets, dict) or not subsets:
        problems.append("unfilled owner decision 'subsets' (one block per film/subset)")
        subsets = {}

    for key in sorted(subsets):
        raw = subsets[key]
        prefix = f"subsets.{key}"
        if not isinstance(raw, dict):
            problems.append(f"unfilled owner decision '{prefix}' (must be an object)")
            continue

        decision = raw.get("decision")
        if not is_filled(decision):
            problems.append(
                f"unfilled owner decision '{prefix}.decision' (admit|quarantine|reject)"
            )
            continue
        if decision not in DECISION_VALUES:
            problems.append(
                f"invalid owner decision '{prefix}.decision'={decision!r}; "
                f"must be one of {list(DECISION_VALUES)}"
            )
            continue

        basis = _as_dict(raw.get("basis"))
        if not is_filled(basis.get("basis_type")):
            problems.append(
                f"unfilled owner decision '{prefix}.basis.basis_type' "
                f"(one of {list(BASIS_TYPES)})"
            )
        elif basis.get("basis_type") not in BASIS_TYPES:
            problems.append(
                f"invalid owner decision '{prefix}.basis.basis_type'="
                f"{basis.get('basis_type')!r}; must be one of {list(BASIS_TYPES)}"
            )
        if not is_filled(basis.get("basis_reference")):
            problems.append(f"unfilled owner decision '{prefix}.basis.basis_reference'")

        if decision != "admit":
            continue

        scope = raw.get("scope")
        if not is_filled(scope):
            problems.append(
                f"unfilled owner decision '{prefix}.scope' (train+eval|train+eval+release)"
            )
        elif scope not in SCOPE_VALUES:
            problems.append(
                f"invalid owner decision '{prefix}.scope'={scope!r}; "
                f"must be one of {list(SCOPE_VALUES)}"
            )

        permissions = _as_dict(raw.get("permissions"))
        for field in ("production_allowed", "redistribution_allowed"):
            if not isinstance(permissions.get(field), bool):
                problems.append(
                    f"unfilled owner decision '{prefix}.permissions.{field}' (true/false)"
                )
        if "derived_media_allowed" in permissions and not isinstance(
            permissions.get("derived_media_allowed"), bool
        ):
            problems.append(
                f"invalid owner decision '{prefix}.permissions.derived_media_allowed' "
                "(true/false)"
            )

        people = _as_dict(raw.get("people"))
        for field in ("people_present", "consent_obtained"):
            if not isinstance(people.get(field), bool):
                problems.append(
                    f"unfilled owner decision '{prefix}.people.{field}' (true/false)"
                )
        if not is_filled(people.get("consent_reference")):
            problems.append(
                f"unfilled owner decision '{prefix}.people.consent_reference' "
                "(reference or 'not_applicable')"
            )

        # A grant of production rights or a release scope must be linked to a basis.
        if scope == "train+eval+release" or permissions.get("production_allowed") is True:
            if not is_filled(basis.get("basis_url")) and not is_filled(basis.get("basis_sha256")):
                problems.append(
                    f"{prefix}: scope={scope!r} / production_allowed=true requires a linked "
                    "basis: set basis.basis_url or basis.basis_sha256"
                )

    attribution_map = _as_dict(data.get("attribution_map"))
    entries = attribution_map.get("entries")
    if not isinstance(entries, list) or not entries:
        problems.append(
            "unfilled owner decision 'attribution_map.entries' (owner-provided per-film "
            "attribution; author text is never inferred)"
        )

    if manifest_films:
        for key in sorted(manifest_films):
            if key not in subsets:
                problems.append(
                    f"unfilled owner decision 'subsets.{key}.decision' "
                    "(film present in the manifest has no decision)"
                )
        for key in sorted(subsets):
            raw = subsets.get(key)
            if (
                isinstance(raw, dict)
                and raw.get("decision") == "admit"
                and key not in manifest_films
            ):
                problems.append(
                    f"'{key}' is admitted but not present in the manifest; refusing to "
                    "attest frames that are not there"
                )

    return problems


# --------------------------------------------------------------------------- #
# compose the two artifacts                                                   #
# --------------------------------------------------------------------------- #


def build_outputs(
    data: dict[str, Any],
    args: argparse.Namespace,
    manifest_sha256: str | None,
    facts: dict[str, Any],
    fact_notes: list[str],
) -> tuple[dict[str, Any], dict[str, Any], list[str]]:
    """Build (attestation, attribution_map, warnings). Raises Refusal on any gap."""
    warnings = list(fact_notes)
    fields_from_facts: list[str] = []
    subsets = data["subsets"]
    keys = sorted(subsets)
    admitted_keys = [key for key in keys if subsets[key]["decision"] == "admit"]
    if admitted_keys and len(admitted_keys) != len(keys):
        warnings.append(
            "mixed decisions: the attestation and the rights record are corpus-wide, so the "
            "corpus is admitted as a whole; non-admitted subsets stay in subset_decisions and "
            "the per-film attribution/notice gates still block them downstream"
        )
    entries_in = [e for e in data["attribution_map"]["entries"] if isinstance(e, dict)]
    raw_entries: dict[str, dict[str, Any]] = {}
    for entry in entries_in:
        key = str(entry.get("film_key") or "").strip().lower().replace(" ", "_")
        if key:
            raw_entries[key] = entry

    # --- AVA / AADB / EVA can never be cleared ----------------------------- #
    haystack = [
        (_as_dict(data.get("corpus")).get(field))
        for field in ("corpus_id", "source_id", "source_path")
    ]
    haystack.extend(keys)
    haystack.extend(entry.get("film_key") for entry in entries_in)
    tokens = _barred_tokens(haystack)
    if tokens and admitted_keys:
        raise Refusal(
            [
                f"corpus matches research-only source(s) {tokens}: AVA/AADB/EVA may never be "
                "admitted, production_allowed, redistribution_allowed, or released "
                "(D01/D05 audit)"
            ]
        )
    if tokens:
        warnings.append(
            f"research-only source tokens {tokens} present but no grant is claimed "
            "(quarantine/reject only)"
        )
    for key in keys:
        if subsets[key]["decision"] == "admit":
            continue
        permissions = _as_dict(subsets[key].get("permissions"))
        if permissions.get("production_allowed") is True or (
            permissions.get("redistribution_allowed") is True
        ):
            raise Refusal(
                [f"'{key}' claims production/redistribution permission but its decision is "
                 f"{subsets[key]['decision']!r}; only an admitted subset may grant permissions"]
            )

    # --- corpus identity and manifest hash --------------------------------- #
    corpus_in = _as_dict(data.get("corpus"))
    corpus_id = corpus_in.get("corpus_id") or DEFAULT_CORPUS_ID
    source_id = corpus_in.get("source_id") or DEFAULT_SOURCE_ID
    source_path = corpus_in.get("source_path") or ""
    manifest_sha = manifest_sha256 or corpus_in.get("manifest_sha256")
    if not is_filled(manifest_sha):
        raise Refusal(
            [
                "corpus.manifest_sha256 is unavailable: pass --manifest <file> or set "
                "'corpus.manifest_sha256' in the decisions file"
            ]
        )

    # --- license facts (facts may fill; decisions may override) ------------ #
    license_in = _as_dict(data.get("license"))
    facts_license = _as_dict(facts.get("license"))
    license_id = license_in.get("license_id")
    if not is_filled(license_id):
        license_id = facts_license.get("id")
        fields_from_facts.append("license.license_id")
    license_url = license_in.get("license_url")
    if not is_filled(license_url):
        license_url = facts_license.get("url")
        fields_from_facts.append("license.license_url")
    license_name = license_in.get("license_name") or license_id or ""
    attribution_required = license_in.get("attribution_required")
    if not isinstance(attribution_required, bool):
        attribution_required = bool(facts_license.get("attribution_required"))
        fields_from_facts.append("license.attribution_required")
    if not is_filled(license_id) or not is_filled(license_url):
        raise Refusal(
            [
                "license facts unavailable: set license.license_id / license.license_url in "
                "the decisions file or provide the facts file with --facts"
            ]
        )

    # --- attribution map (author is always owner-provided) ----------------- #
    facts_by_film = {
        film.get("film"): film
        for film in (facts.get("films") or [])
        if isinstance(film, dict)
    }
    map_entries: list[dict[str, Any]] = []
    for key in keys:
        subset = subsets[key]
        is_admitted = subset["decision"] == "admit"
        raw_entry = raw_entries.get(key, {})

        author = raw_entry.get("author")
        if is_admitted and not is_filled(author):
            raise Refusal(
                [
                    f"admitted film '{key}': the attribution map has no owner-provided "
                    "'author'; refusing to infer it from the title or license"
                ]
            )

        film_fact = facts_by_film.get(key) or {}
        attribution_string = raw_entry.get("attribution_string")
        attribution_provenance = "owner-provided"
        if not is_filled(attribution_string):
            if is_filled(film_fact.get("attribution_string")):
                attribution_string = film_fact.get("attribution_string")
                attribution_provenance = (
                    f"facts:{args.facts} "
                    f"({film_fact.get('attribution_string_provenance') or 'publisher page'})"
                )
                fields_from_facts.append(f"attribution_string[{key}]")
        if (
            is_admitted
            and subset.get("scope") == "train+eval+release"
            and not is_filled(attribution_string)
        ):
            raise Refusal(
                [
                    f"admitted film '{key}' is in release scope but attribution_string is "
                    "empty; the credit line must be owner-provided (facts publish none)"
                ]
            )

        license_url_entry = raw_entry.get("license_url")
        if not is_filled(license_url_entry):
            license_url_entry = license_url
        source_url = raw_entry.get("source_url")
        if not is_filled(source_url):
            source_url = film_fact.get("publisher_page") or ""
            if is_filled(source_url):
                fields_from_facts.append(f"source_url[{key}]")
        title = raw_entry.get("title") or film_fact.get("film") or key

        map_entries.append(
            {
                "film_key": key,
                "title": title,
                "author": author if is_filled(author) else "",
                "author_url": raw_entry.get("author_url", ""),
                "license_id": raw_entry.get("license_id") or license_id,
                "license_url": license_url_entry,
                "attribution_string": attribution_string or "",
                "source_url": source_url,
                "_attribution_string_provenance": attribution_provenance,
            }
        )

    # --- corpus-level composition over admitted subsets -------------------- #
    if admitted_keys:
        permissions = [_as_dict(subsets[key].get("permissions")) for key in admitted_keys]
        production_allowed = all(p.get("production_allowed") is True for p in permissions)
        redistribution_allowed = all(
            p.get("redistribution_allowed") is True for p in permissions
        )
        derived_allowed: bool | None = None
        if all("derived_media_allowed" in p for p in permissions):
            derived_allowed = all(p.get("derived_media_allowed") is True for p in permissions)

        scopes = [subsets[key].get("scope") for key in admitted_keys]
        decision_scope = (
            "train+eval+release"
            if all(scope == "train+eval+release" for scope in scopes)
            else "train+eval"
        )
        if decision_scope != "train+eval+release" and any(
            scope == "train+eval+release" for scope in scopes
        ):
            warnings.append(
                "some admitted subsets allow release but not all: the corpus-level scope is "
                "'train+eval', so no release is claimed for the whole corpus "
                "(conservative intersection, never a wider grant)"
            )

        people_present = any(
            _as_dict(subsets[key].get("people")).get("people_present") is True
            for key in admitted_keys
        )
        consent_obtained = all(
            _as_dict(subsets[key].get("people")).get("consent_obtained") is True
            for key in admitted_keys
            if _as_dict(subsets[key].get("people")).get("people_present") is True
        )
        consent_reference = _join_unique(
            _as_dict(subsets[key].get("people")).get("consent_reference")
            for key in admitted_keys
        )

        basis_types = {subsets[key]["basis"].get("basis_type") for key in admitted_keys}
        if len(basis_types) != 1:
            raise Refusal(
                [
                    "admitted subsets declare different basis_type values; a single-corpus "
                    "attestation needs one basis type (make them identical or split the corpus)"
                ]
            )
        basis_values = [subsets[key]["basis"] for key in admitted_keys]
        decision_admitted = True
        decision_value = "admit"
    else:
        production_allowed = False
        redistribution_allowed = False
        derived_allowed = None
        decision_scope = "none"
        decision_admitted = False
        decision_value = (
            "reject"
            if all(subsets[key]["decision"] == "reject" for key in keys)
            else "quarantine"
        )
        people_present = any(
            _as_dict(subsets[key].get("people")).get("people_present") is True for key in keys
        )
        consent_obtained = all(
            _as_dict(subsets[key].get("people")).get("consent_obtained") is True
            for key in keys
            if _as_dict(subsets[key].get("people")).get("people_present") is True
        )
        consent_reference = _join_unique(
            _as_dict(subsets[key].get("people")).get("consent_reference") for key in keys
        )
        basis_values = [subsets[key]["basis"] for key in keys]
        warnings.append(
            "no subset is admitted: the attestation records quarantine/reject only and grants "
            "nothing"
        )

    basis_type = (basis_values[0].get("basis_type") if basis_values else "") or ""
    basis_reference = _join_unique(b.get("basis_reference") for b in basis_values)
    basis_url = next((b.get("basis_url") for b in basis_values if is_filled(b.get("basis_url"))), "")
    basis_sha256 = next(
        (b.get("basis_sha256") for b in basis_values if is_filled(b.get("basis_sha256"))), ""
    )

    attestation: dict[str, Any] = {
        "attestation_schema_id": ATTESTATION_SCHEMA_ID,
        "attestation_version": ATTESTATION_VERSION,
        "attester": {
            "attester_id": data["attester"].get("attester_id"),
            "attester_name": data["attester"].get("attester_name"),
            "attester_role": data["attester"].get("attester_role"),
            "attester_contact": data["attester"].get("attester_contact", ""),
        },
        "attested_at": data.get("attested_at"),
        "corpus": {
            "corpus_id": corpus_id,
            "source_id": source_id,
            "source_path": source_path,
            "manifest_sha256": manifest_sha,
        },
        "license": {
            "license_id": license_id,
            "license_name": license_name,
            "license_url": license_url,
            "attribution_required": attribution_required,
        },
        "permissions": {
            "production_allowed": production_allowed,
            "redistribution_allowed": redistribution_allowed,
        },
        "people": {
            "people_present": people_present,
            "consent_obtained": consent_obtained,
            "consent_reference": consent_reference,
        },
        "basis": {
            "basis_type": basis_type,
            "basis_reference": basis_reference,
            "basis_url": basis_url,
            "basis_sha256": basis_sha256,
        },
        "attribution": {
            "attribution_map_ref": str(Path(args.attribution_map_out).resolve()),
            "per_film": [],
        },
        "decision": {
            "admitted": decision_admitted,
            "decision": decision_value,
            "decision_scope": decision_scope,
        },
        # Audit trail beyond the attestation schema; ignored by the validator.
        "_decisions_source": str(Path(args.decisions).resolve()),
        "_facts_source": str(args.facts),
        "_facts_note": facts.get("not_legal_advice", ""),
        "_provenance": {"fields_from_facts": sorted(set(fields_from_facts))},
        "subset_decisions": {
            key: {
                "decision": subsets[key].get("decision"),
                "scope": subsets[key].get("scope"),
                "permissions": _as_dict(subsets[key].get("permissions")),
                "people": _as_dict(subsets[key].get("people")),
                "basis": _as_dict(subsets[key].get("basis")),
                "admitted_for_corpus": key in admitted_keys,
            }
            for key in keys
        },
    }
    if derived_allowed is not None:
        attestation["permissions"]["derived_media_allowed"] = derived_allowed

    attribution_map = {
        "attribution_map_schema_id": ATTRIBUTION_MAP_SCHEMA_ID,
        "attribution_map_version": ATTRIBUTION_MAP_VERSION,
        "provided_by": (
            data["attribution_map"].get("provided_by")
            or data["attester"].get("attester_name")
            or ""
        ),
        "entries": map_entries,
        "_facts_source": str(args.facts),
        "_facts_provenance": sorted(
            {field for field in fields_from_facts if field.startswith(("attribution_string", "source_url"))}
        ),
    }
    return attestation, attribution_map, warnings


# --------------------------------------------------------------------------- #
# CLI                                                                         #
# --------------------------------------------------------------------------- #


def parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--decisions", type=Path, help="owner answers (camera-owner-decisions-v1)")
    parser.add_argument("--attestation-out", type=Path, help="where to write the attestation")
    parser.add_argument(
        "--attribution-map-out", type=Path, help="where to write the attribution map"
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        help="optional source manifest.jsonl: used for manifest_sha256 and film coverage",
    )
    parser.add_argument("--facts", type=Path, default=DEFAULT_FACTS)
    parser.add_argument(
        "--append-manifest",
        action="store_true",
        help="append an admitted record to the rights manifest (off by default)",
    )
    parser.add_argument("--rights-manifest", type=Path, default=DEFAULT_RIGHTS_MANIFEST)
    return parser.parse_args(argv)


def _next_command(args: argparse.Namespace) -> str:
    parts = [
        "python3",
        str(Path(__file__).resolve()),
        "--decisions",
        str(Path(args.decisions).resolve()),
        "--attestation-out",
        str(Path(args.attestation_out).resolve()),
        "--attribution-map-out",
        str(Path(args.attribution_map_out).resolve()),
    ]
    if args.manifest is not None:
        parts += ["--manifest", str(Path(args.manifest).resolve())]
    if args.facts != DEFAULT_FACTS:
        parts += ["--facts", str(Path(args.facts).resolve())]
    if args.rights_manifest != DEFAULT_RIGHTS_MANIFEST:
        parts += ["--rights-manifest", str(Path(args.rights_manifest).resolve())]
    parts.append("--append-manifest")
    return " ".join(shlex.quote(p) for p in parts)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    if args.decisions is None:
        print("REFUSED (exit 2): --decisions is required.", file=sys.stderr)
        return 2
    if args.attestation_out is None or args.attribution_map_out is None:
        print(
            "REFUSED (exit 2): --attestation-out and --attribution-map-out are required.",
            file=sys.stderr,
        )
        return 2
    if not args.decisions.exists():
        print(f"REFUSED (exit 2): decisions file not found: {args.decisions}", file=sys.stderr)
        return 2
    try:
        data = json.loads(args.decisions.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, ValueError, OSError) as exc:
        print(f"REFUSED (exit 2): cannot parse decisions file: {exc}", file=sys.stderr)
        return 2
    if not isinstance(data, dict):
        print("REFUSED (exit 2): decisions root must be a JSON object.", file=sys.stderr)
        return 2

    # Manifest (optional) gives the true hash and the film set to cover.
    manifest_sha256: str | None = None
    manifest_films: set[str] | None = None
    if args.manifest is not None:
        if not args.manifest.exists():
            print(f"REFUSED (exit 2): manifest not found: {args.manifest}", file=sys.stderr)
            return 2
        manifest_sha256 = sha256_file(args.manifest)
        emitter = _load_module("cc_emit_for_decisions", "emit_attribution_notices.py")
        rows = emitter.load_jsonl(args.manifest)
        if not rows:
            print(f"REFUSED (exit 1): manifest is empty: {args.manifest}", file=sys.stderr)
            return 1
        manifest_films = set(emitter.group_by_film(rows))

    facts, fact_notes = _load_facts(args.facts)

    problems = collect_problems(data, manifest_films)
    if problems:
        print(
            f"REFUSED: owner decisions are incomplete ({len(problems)} problem(s)); "
            "nothing written:",
            file=sys.stderr,
        )
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    try:
        attestation, attribution_map, warnings = build_outputs(
            data, args, manifest_sha256, facts, fact_notes
        )
    except Refusal as refusal:
        print(
            f"REFUSED: decisions cannot form an admissible attestation "
            f"({len(refusal.problems)} problem(s)); nothing written:",
            file=sys.stderr,
        )
        for problem in refusal.problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    # Final gate: the composed attestation must pass the existing validator.
    validator = _load_module("cc_validate_for_decisions", "validate_rights_attestation.py")
    errors = validator.validate(attestation)
    if errors:
        print(
            f"REFUSED: composed attestation failed validate_rights_attestation "
            f"({len(errors)} problem(s)); nothing written:",
            file=sys.stderr,
        )
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    if args.append_manifest and not attestation["decision"]["admitted"]:
        print(
            "REFUSED: --append-manifest was requested but no subset is admitted; "
            "nothing written.",
            file=sys.stderr,
        )
        return 1

    # All gates passed: write.
    args.attestation_out.parent.mkdir(parents=True, exist_ok=True)
    args.attribution_map_out.parent.mkdir(parents=True, exist_ok=True)
    args.attestation_out.write_text(
        json.dumps(attestation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    args.attribution_map_out.write_text(
        json.dumps(attribution_map, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    attestation_sha = sha256_file(args.attestation_out)

    print("OK: assembled a complete owner attestation and attribution map")
    print(
        "  decision: "
        f"{attestation['decision']['decision']} "
        f"scope={attestation['decision']['decision_scope']} "
        f"admitted={attestation['decision']['admitted']}"
    )
    print(
        "  permissions: "
        f"production_allowed={attestation['permissions']['production_allowed']} "
        f"redistribution_allowed={attestation['permissions']['redistribution_allowed']}"
    )
    for warning in warnings:
        print(f"  note: {warning}")
    print(f"  wrote: {args.attestation_out} sha256={attestation_sha}")
    print(
        f"  wrote: {args.attribution_map_out} sha256={sha256_file(args.attribution_map_out)}"
    )
    if fields := attestation.get("_provenance", {}).get("fields_from_facts"):
        print("  facts used (not decisions): " + ", ".join(fields))

    if not args.append_manifest:
        print("  rights manifest NOT modified (no --append-manifest).")
        print("  exact next command:")
        print(f"    {_next_command(args)}")
        return 0

    record = {
        "manifest_type": "rights",
        "schema_id": "camera-rights-manifest-v1",
        "record_id": f"rights-{attestation['corpus']['corpus_id']}-{attestation['attested_at']}",
        "corpus_id": attestation["corpus"]["corpus_id"],
        "source_id": attestation["corpus"]["source_id"],
        "admitted": True,
        "admitted_by": attestation["attester"]["attester_id"],
        "attested_at": attestation["attested_at"],
        "decision_scope": attestation["decision"]["decision_scope"],
        "attestation_sha256": attestation_sha,
        "attribution_map_ref": attestation["attribution"]["attribution_map_ref"],
        "basis_reference": attestation["basis"]["basis_reference"],
    }
    # Carry the owner's per-film decisions into the admission record: without them a
    # consumer only knows "the corpus is admitted" and cannot tell that a particular
    # film was quarantined, which is how quarantined frames could reach a split.
    subset_decisions = {
        key: {"decision": block.get("decision"), "scope": block.get("scope")}
        for key, block in sorted((attestation.get("subset_decisions") or {}).items())
    }
    if subset_decisions:
        record["subset_decisions"] = subset_decisions
    args.rights_manifest.parent.mkdir(parents=True, exist_ok=True)
    with args.rights_manifest.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
    print(f"  appended admitted record to: {args.rights_manifest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
