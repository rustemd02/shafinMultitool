#!/usr/bin/env python3
"""Build the `weight_lineage` block from real provenance, not from prose.

The §5 gate `weight_lineage_release_cleared` decides whether a shipped weight may
be called release-cleared, and the runbook is explicit that credits do not clear
research-only weights for the App Store. The block was hand-written before: a
single free-text `basis` string is enough to pass the gate, and nothing ties the
clearance to an actual rights decision.

This tool derives the block instead:

* every lineage entry comes from a provenance document that must state its own
  data lineage; a document that does not say where its weights came from is
  refused (exit 2) rather than defaulted to "admitted";
* `release_cleared` is true only when the provenance declares
  `release_admissible: true` **and** the rights manifest carries an admitted entry
  covering that corpus with a release scope and a complete, hashed basis;
* the basis is emitted in linked form (`basis`, `basis_reference`, `basis_sha256`)
  so the clearance can be re-checked instead of believed;
* otherwise the entry is emitted with `release_cleared: false` and a basis naming
  exactly which condition failed, which is the truthful result and what makes the
  gate fail.

Exit codes
    0  a lineage block was produced (entries may legitimately be not cleared)
    1  --require-release-cleared was given and some entry is not cleared
    2  an input is missing, unreadable, or a provenance does not state its lineage

Usage
    python3 tools/release/build_weight_lineage.py \\
        --provenance ml/camera_coach/artifacts/*.provenance.json \\
        --rights-manifest datasets/camera-coach/v1/rights-manifest.jsonl \\
        --out lineage.json
"""

from __future__ import annotations

import argparse
import glob
import hashlib
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SHA256 = re.compile(r"^[0-9a-f]{64}$")
NONE_LINEAGE = ("none", "")


class InputError(Exception):
    pass


def _sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _text(mapping: dict, *names: str) -> str | None:
    for name in names:
        value = mapping.get(name)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return None


def state_lineage(provenance: dict, path: Path) -> tuple[str, list[str]]:
    """Return (lineage label, notes). Refuses when the document is silent."""
    notes = []
    raw = _text(provenance, "admitted_data", "training_data", "training_data_lineage", "corpora")
    if raw is None:
        raise InputError(f"{path} does not state where its weights came from "
                         "(no admitted_data/training_data/corpora field): refusing to guess")
    lowered = raw.lower()
    if any(marker in lowered for marker in NONE_LINEAGE) and "blocked" in lowered:
        notes.append(f"provenance declares no admitted data: {raw!r}")
        return "none", notes
    if lowered.startswith("admitted"):
        return raw, notes
    if "research" in lowered:
        return raw, notes
    notes.append(f"unrecognised lineage statement: {raw!r}")
    return raw, notes


def load_rights(path: Path | None) -> tuple[list[dict], dict | None]:
    if path is None:
        return [], None
    if not path.is_file():
        raise InputError(f"rights manifest not found: {path}")
    entries, header = [], None
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError as error:
            raise InputError(f"{path}:{number} is not JSON: {error}") from error
        if not isinstance(record, dict):
            raise InputError(f"{path}:{number} is not an object")
        if record.get("manifest_type") == "rights" and header is None:
            header = record
            continue
        entries.append(record)
    return entries, header


def clearance(provenance: dict, lineage: str, entries: list[dict], provenance_path: Path,
              rights_path: Path | None) -> dict:
    """Decide the release clearance and the linked basis behind it."""
    if provenance.get("release_admissible") is not True:
        flags = ", ".join(f"{key}={provenance.get(key)!r}" for key in
                          ("status", "tooling_only", "untrained_weights", "not_a_release_candidate")
                          if key in provenance)
        return {"release_cleared": False,
                "basis": f"provenance declares release_admissible="
                         f"{provenance.get('release_admissible')!r} ({flags}); "
                         f"blocked_on={provenance.get('blocked_on')!r}"}

    for entry in entries:
        decision = entry.get("decision") or {}
        if decision.get("admitted") is not True or decision.get("decision") != "admit":
            continue
        scope = str(decision.get("decision_scope") or "")
        if "release" not in scope:
            continue
        entry_lineage = _text(entry, "training_data_lineage") or _text(entry.get("corpus") or {}, "corpus_id")
        if entry_lineage and lineage != "none" and entry_lineage not in lineage and lineage not in entry_lineage:
            continue
        basis = entry.get("basis") or {}
        missing = [key for key in ("basis_type", "basis_reference", "basis_sha256") if not basis.get(key)]
        if missing:
            return {"release_cleared": False,
                    "basis": f"admitted rights entry has an incomplete basis (missing {missing})"}
        if not SHA256.match(str(basis.get("basis_sha256"))):
            return {"release_cleared": False, "basis": "admitted rights entry basis_sha256 is not a sha256"}
        return {"release_cleared": True,
                "basis": f"admitted rights entry with release scope; basis_type={basis['basis_type']!r}, "
                         f"reference={basis['basis_reference']!r}",
                "basis_reference": str(basis["basis_reference"]),
                "basis_sha256": str(basis["basis_sha256"])}

    where = rights_path if rights_path else "<no rights manifest supplied>"
    return {"release_cleared": False,
            "basis": f"no admitted rights entry with a release scope covers lineage {lineage!r} "
                     f"in {where}; provenance={provenance_path.name}"}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--provenance", action="append", required=True,
                        help="a provenance JSON document; repeatable, globs are expanded by the shell")
    parser.add_argument("--rights-manifest", type=Path)
    parser.add_argument("--require-release-cleared", action="store_true")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args(argv)

    paths = []
    for pattern in args.provenance:
        matches = sorted(glob.glob(pattern))
        if not matches:
            print(f"FAIL CLOSED: no provenance matches {pattern!r}", file=sys.stderr)
            return 2
        paths.extend(Path(match) for match in matches)

    try:
        entries, header = load_rights(args.rights_manifest)
    except InputError as error:
        print(f"FAIL CLOSED: {error}", file=sys.stderr)
        return 2

    lineage_entries = []
    try:
        for path in paths:
            provenance = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(provenance, dict):
                raise InputError(f"{path} is not a JSON object")
            lineage, notes = state_lineage(provenance, path)
            artifact = _text(provenance.get("mlpackage") or {}, "path") or path.name
            decision = clearance(provenance, lineage, entries, path, args.rights_manifest)
            entry = {
                "artifact": artifact,
                "sha256": _text(provenance, "weights_sha256") or _sha256_file(path),
                "training_data_lineage": lineage,
                "release_cleared": decision["release_cleared"],
                "basis": decision["basis"],
            }
            entry["basis_reference"] = decision.get("basis_reference", str(path))
            entry["basis_sha256"] = decision.get("basis_sha256", _sha256_file(path))
            entry["provenance"] = {
                "path": str(path), "sha256": _sha256_file(path),
                "candidate_id": provenance.get("candidate_id"),
                "artifact_kind": provenance.get("artifact_kind"),
                "weights_origin": provenance.get("weights_origin"),
                "parameter_count": provenance.get("weight_parameter_count"),
                "notes": notes,
            }
            lineage_entries.append(entry)
    except (InputError, OSError, json.JSONDecodeError) as error:
        print(f"FAIL CLOSED: {error}", file=sys.stderr)
        return 2

    payload = {
        "schema_id": "camera-weight-lineage",
        "schema_version": "1.0.0",
        "rights_manifest": None if args.rights_manifest is None else {
            "path": str(args.rights_manifest), "sha256": _sha256_file(args.rights_manifest),
            "record_count": (header or {}).get("record_count"),
            "template_only": (header or {}).get("template_only"),
            "entries_read": len(entries),
        },
        "weight_lineage": lineage_entries,
    }
    cleared = [entry["artifact"] for entry in lineage_entries if entry["release_cleared"]]
    print(f"LINEAGE artifacts={len(lineage_entries)} release_cleared={len(cleared)}")
    for entry in lineage_entries:
        mark = "CLEARED" if entry["release_cleared"] else "NOT CLEARED"
        print(f"  {mark}: {entry['artifact']} — {entry['basis']}")

    text = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.out is not None:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding="utf-8")
        print(f"WROTE {args.out}")
    else:
        print(text)

    if args.require_release_cleared and len(cleared) != len(lineage_entries):
        print("FAIL: --require-release-cleared was given and some artifact is not release-cleared",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
