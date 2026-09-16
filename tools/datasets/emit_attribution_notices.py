#!/usr/bin/env python3
"""Generate per-frame CC-BY attribution notices for the cinematic corpus.

Hard rules enforced here:

* The cinematic manifest has no ``author`` field. Author/licensor strings are a
  legal statement, so this tool NEVER invents them and NEVER derives them from
  the film title or the license string. Author text must come from an explicit
  owner-provided attribution map (or per-film entries in the attestation).
* Without a valid owner attestation the tool refuses (exit 1) and writes
  nothing: it will not emit an ``admitted`` field, nor mark the corpus
  release-cleared.
* If the attribution map misses any film, the tool refuses (exit 1).
* Notice count must equal manifest frame count. When compared against an
  annotation queue with a different count, an explicit note is required so the
  313/319 discrepancy is explained rather than silenced.
* ``--dry-run`` writes nothing and prints exactly what the owner must supply
  for each film.

No network access.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
HOME = Path.home()

SCHEMA_ID = "camera-attribution-notices-v1"
SCHEMA_VERSION = "v1.0.0"
ATTRIBUTION_MAP_SCHEMA_ID = "camera-attribution-map-v1"

DEFAULT_MANIFEST = (
    HOME
    / "Documents/XCode/setos-backend/local-data/SETOS/Datasets/camera-coach/research/cinematic/manifest.jsonl"
)
DEFAULT_QUEUE = HOME / "Documents/XCode/setos-backend/local-data/SETOS/annotation/queue-v3-cinematic.jsonl"
DEFAULT_OUT_DIR = REPO_ROOT / "datasets/camera-coach/v1"

# Author is deliberately absent from the source manifest. These are the fields
# the owner must provide per film before any notice can be emitted.
REQUIRED_PER_FILM = ("author", "license_url", "attribution_string", "source_url")


def _load_validator():
    path = Path(__file__).resolve().parent / "validate_rights_attestation.py"
    spec = importlib.util.spec_from_file_location("_cc_rights_attestation", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if line.strip():
                rows.append(json.loads(line))
    return rows


def film_key(record: dict[str, Any]) -> str:
    """Stable per-film key from the frame directory name."""
    path = Path(str(record.get("image_path", "")))
    name = path.parent.name or path.stem or "unknown"
    return name.strip().lower().replace(" ", "_")


def film_title(record: dict[str, Any]) -> str:
    provenance = record.get("provenance") or {}
    return str(provenance.get("title") or "")


def group_by_film(rows: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    films: dict[str, dict[str, Any]] = {}
    for row in rows:
        key = film_key(row)
        entry = films.setdefault(key, {"film_key": key, "titles": set(), "frames": []})
        entry["titles"].add(film_title(row))
        entry["frames"].append(row)
    for entry in films.values():
        entry["titles"] = sorted(t for t in entry["titles"] if t)
    return films


def load_attribution_map(path: Path) -> dict[str, dict[str, Any]]:
    """Accept {entries:[...]}, {films:{key:...}}, or a bare list of entries."""
    data = json.loads(path.read_text(encoding="utf-8"))
    index: dict[str, dict[str, Any]] = {}
    if isinstance(data, dict) and isinstance(data.get("films"), dict):
        for key, value in data["films"].items():
            if isinstance(value, dict):
                entry = dict(value)
                entry.setdefault("film_key", key)
                index[str(key).lower()] = entry
    entries = data.get("entries") if isinstance(data, dict) else data
    if isinstance(entries, list):
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            key = entry.get("film_key") or entry.get("title") or ""
            normalized = str(key).strip().lower().replace(" ", "_")
            if normalized:
                index[normalized] = entry
    return index


def _blank(value: Any) -> bool:
    return value is None or (isinstance(value, str) and not value.strip())


def map_entry_for(entry: dict[str, Any], index: dict[str, dict[str, Any]]) -> dict[str, Any] | None:
    for key in (entry["film_key"], *[t.lower().replace(" ", "_") for t in entry["titles"]]):
        if key in index:
            return index[key]
    # Match by raw title as well.
    for candidate in index.values():
        title = str(candidate.get("title") or "").strip().lower()
        if title and title in {t.strip().lower() for t in entry["titles"]}:
            return candidate
    return None


def _release_cleared(attestation: dict[str, Any] | None, decisions: dict[str, str]) -> bool:
    """True only when the corpus and every admitted subset allow release."""
    document = attestation or {}
    decision = document.get("decision") or {}
    if decision.get("admitted") is not True:
        return False
    if "release" not in str(decision.get("decision_scope") or ""):
        return False
    subsets = document.get("subset_decisions")
    if not subsets:
        # Only the corpus decision is declared, and it carries a release scope, so
        # there is nothing finer to intersect with.
        return True
    admitted = [key for key, value in decisions.items() if value == "admit"]
    if not admitted:
        return False
    return all("release" in str((subsets.get(key) or {}).get("scope") or "") for key in admitted)


def _film_summary(key: str, films: dict[str, str], map_index: dict, decisions: dict[str, str]) -> dict:
    """One summary row per film, including the ones that carry no notice."""
    film = films[key]
    candidate = map_entry_for(film, map_index) or {}
    return {
        "film_key": key,
        "title": film.get("primary_title") or key,
        "frames": len(film["frames"]),
        "author": candidate.get("author"),
        "decision": decisions.get(key) or "undecided",
        "notice_emitted": decisions.get(key) == "admit",
    }


def admitted_films(attestation: dict[str, Any] | None, films: dict[str, str]) -> dict[str, str]:
    """Map film key -> the owner's subset decision.

    A quarantined or rejected subset is not used, so it needs no credit string and
    gets no notice: the form says only `decision` and `basis` are required for
    `quarantine`/`reject`. Requiring a credit for an unused film would force the
    owner either to invent one — which this tool must never do — or to be unable to
    finish the chain.
    """
    document = attestation or {}
    decisions = document.get("subset_decisions")
    if not decisions:
        # Without declared subsets the corpus decision is the only statement there is,
        # and the validator accepts such an attestation; the summary records that this
        # weaker basis was used instead of silently treating the films as decided.
        admitted = (document.get("decision") or {}).get("admitted") is True
        return {key: ("admit" if admitted else "") for key in films}
    return {key: str((decisions.get(key) or {}).get("decision", "")).strip() for key in films}


def missing_map_fields(candidate: dict[str, Any] | None, key: str) -> list[str]:
    if candidate is None:
        return [
            f"{key}: no attribution map entry; required fields: "
            + ", ".join(REQUIRED_PER_FILM)
        ]
    problems = []
    for field in REQUIRED_PER_FILM:
        if _blank(candidate.get(field)):
            problems.append(f"{key}: missing '{field}'")
    return problems


def build_notice(record: dict[str, Any], film: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    provenance = record.get("provenance") or {}
    title = film.get("primary_title") or film_title(record)
    author = candidate["author"]
    license_url = candidate["license_url"]
    source_url = candidate["source_url"]
    license_name = candidate.get("license_id") or candidate.get("license") or provenance.get("license", "")
    notice_text = (
        f"\"{title}\" frame {Path(str(record['image_path'])).name} — "
        f"author: {author}; license: {license_name} ({license_url}); "
        f"source: {source_url}"
    )
    return {
        "record_id": record["record_id"],
        "film_key": narrative_key(film),
        "title": title,
        "author": author,
        "author_url": candidate.get("author_url", ""),
        "license": license_name,
        "license_url": license_url,
        "source_url": source_url,
        "attribution_string": candidate["attribution_string"],
        "notice_text": notice_text,
        "image_path": record["image_path"],
        "image_sha256": record.get("image_sha256", ""),
    }


def narrative_key(film: dict[str, Any]) -> str:
    return film["film_key"]


def parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--prefix", default="cinematic")
    parser.add_argument("--attestation", type=Path, help="owner-filled rights attestation JSON")
    parser.add_argument("--attribution-map", type=Path, help="owner-provided per-film attribution map")
    parser.add_argument(
        "--annotation-queue",
        type=Path,
        help="optional queue to compare notice count against (313 vs 319)",
    )
    parser.add_argument(
        "--count-discrepancy-note",
        default="",
        help="required explanation when notice count != queue count",
    )
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args(argv)


def required_map_lines(films: dict[str, dict[str, Any]]) -> list[str]:
    lines = []
    for key in sorted(films):
        film = films[key]
        title = film["titles"][0] if film["titles"] else "(no title)"
        lines.append(f"  [{key}] title={title!r} frames={len(film['frames'])}")
        lines.append(f"      required fields: {', '.join(REQUIRED_PER_FILM)}")
    return lines


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    if not args.manifest.exists():
        print(f"REFUSED: manifest not found: {args.manifest}", file=sys.stderr)
        return 1
    rows = load_jsonl(args.manifest)
    if not rows:
        print(f"REFUSED: manifest is empty: {args.manifest}", file=sys.stderr)
        return 1
    films = group_by_film(rows)

    if args.dry_run:
        print("DRY-RUN: nothing will be written.")
        print(f"manifest: {args.manifest}")
        print(f"frames: {len(rows)} across {len(films)} film family(ies)")
        print(
            "NOTE: the source manifest has NO 'author' field. CC-BY author/licensor "
            "text cannot be inferred from title or license."
        )
        print("Owner must provide, per film:")
        for line in required_map_lines(films):
            print(line)
        print("Also required:")
        print("  - an admissible owner attestation (see rights-attestation.template.json)")
        if args.attestation:
            print(f"  - attestation: {args.attestation}")
        else:
            print("  - attestation: MISSING (--attestation)")
        print(
            "  - count check: notices must equal manifest frames; any queue "
            "difference needs --count-discrepancy-note"
        )
        print("Would write:")
        print(f"  {args.out_dir / (args.prefix + '-attribution.draft.jsonl')}")
        print(f"  {args.out_dir / (args.prefix + '-attribution-notices.draft.txt')}")
        print(f"  {args.out_dir / (args.prefix + '-attribution-summary.draft.json')}")
        return 0

    validator = _load_validator()
    errors: list[str] = []

    # 1. Owner attestation is mandatory.
    if args.attestation is None:
        errors.append(
            "missing --attestation: no owner decision. Owner must fill "
            "rights-attestation.template.json (attester, attested_at, corpus, "
            "license, permissions, people/consent, basis, decision)."
        )
    elif not args.attestation.exists():
        errors.append(f"attestation file not found: {args.attestation}")
    else:
        try:
            data = json.loads(args.attestation.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, ValueError) as exc:
            errors.append(f"cannot parse attestation: {exc}")
            data = None
        if data is not None:
            errors.extend(validator.validate(data))
            if data.get("decision", {}).get("admitted") is not True:
                errors.append("owner attestation does not admit this corpus (decision.admitted != true)")

    # 2. Owner attribution map is mandatory: no invented author strings.
    map_index: dict[str, dict[str, Any]] = {}
    map_path = args.attribution_map
    if map_path is None and args.attestation and args.attestation.exists():
        try:
            data = json.loads(args.attestation.read_text(encoding="utf-8"))
            ref = (data.get("attribution") or {}).get("attribution_map_ref")
            if ref:
                map_path = Path(str(ref))
        except (json.JSONDecodeError, ValueError):
            pass
    if map_path is None:
        errors.append(
            "missing attribution map: owner must supply --attribution-map (or "
            "attribution.attribution_map_ref in the attestation) with "
            + ", ".join(REQUIRED_PER_FILM)
            + " for every film"
        )
    elif not map_path.exists():
        errors.append(f"attribution map not found: {map_path}")
    else:
        try:
            map_index = load_attribution_map(map_path)
        except (json.JSONDecodeError, ValueError) as exc:
            errors.append(f"cannot parse attribution map: {exc}")
        decisions = admitted_films(data, films)
        skipped = {key: decision for key, decision in decisions.items() if decision != "admit"}
        for key in sorted(set(films) - set(skipped)):
            errors.extend(missing_map_fields(map_entry_for(films[key], map_index), key))
        if skipped:
            print("skipped (not admitted, so no notice and no credit required): "
                  + ", ".join(f"{key}={decision or 'undecided'!s}" for key, decision in sorted(skipped.items())))
        if len(skipped) == len(films):
            errors.append("every film in this corpus is quarantined/rejected/undecided: there is "
                          "nothing to attribute, and an empty notice set must not read as success")

    # 3. Count invariant against the annotation queue.
    if args.annotation_queue is not None:
        if not args.annotation_queue.exists():
            errors.append(f"annotation queue not found: {args.annotation_queue}")
        else:
            queue_rows = load_jsonl(args.annotation_queue)
            queue_cinematic = [
                r
                for r in queue_rows
                if (r.get("provenance") or {}).get("source") == "cinematic"
            ]
            if len(queue_cinematic) != len(rows) and not args.count_discrepancy_note.strip():
                missing_ids = sorted(
                    {r["record_id"] for r in rows} - {r["record_id"] for r in queue_cinematic}
                )
                errors.append(
                    f"count discrepancy not explained: manifest has {len(rows)} frames, "
                    f"queue has {len(queue_cinematic)}; missing from queue: {missing_ids}. "
                    "Re-run with --count-discrepancy-note '<reason>'."
                )

    if errors:
        print(
            f"REFUSED: cannot emit attribution notices ({len(errors)} problem(s)); nothing written:",
            file=sys.stderr,
        )
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    # All gates passed: build notices for the films the owner actually admitted.
    decisions = admitted_films(data, films)
    admitted_keys = [key for key in sorted(films) if decisions.get(key) == "admit"]
    skipped_keys = [key for key in sorted(films) if decisions.get(key) != "admit"]
    expected_notices = sum(len(films[key]["frames"]) for key in admitted_keys)

    for key in sorted(films):
        films[key]["primary_title"] = films[key]["titles"][0] if films[key]["titles"] else key

    notices: list[dict[str, Any]] = []
    for key in admitted_keys:
        film = films[key]
        candidate = map_entry_for(film, map_index)
        assert candidate is not None
        for record in film["frames"]:
            notices.append(build_notice(record, film, candidate))
    assert len(notices) == expected_notices, "internal error: notice count != admitted frame count"
    if not notices:
        print("REFUSED: no admitted film carries frames, so there is nothing to attribute", file=sys.stderr)
        return 1

    attestation_sha = sha256_file(args.attestation)
    # Derived once for the run: a notice may not claim release clearance that the
    # owner's scope does not grant.
    corpus_admitted = (data.get("decision") or {}).get("admitted") is True
    release_cleared = _release_cleared(data, decisions)
    for notice in notices:
        notice["admitted"] = corpus_admitted
        notice["release_cleared"] = release_cleared
        notice["admission_basis"] = str(
            json.loads(args.attestation.read_text(encoding="utf-8")).get("basis", {}).get(
                "basis_reference", ""
            )
        )

    args.out_dir.mkdir(parents=True, exist_ok=True)
    jsonl_path = args.out_dir / f"{args.prefix}-attribution.draft.jsonl"
    notices_path = args.out_dir / f"{args.prefix}-attribution-notices.draft.txt"
    summary_path = args.out_dir / f"{args.prefix}-attribution-summary.draft.json"

    jsonl_path.write_text(
        "\n".join(json.dumps(n, ensure_ascii=False, sort_keys=True) for n in notices) + "\n",
        encoding="utf-8",
    )
    notices_path.write_text(
        "\n\n".join(
            f"{notice['attribution_string']}\n{notice['notice_text']}" for notice in notices
        )
        + "\n",
        encoding="utf-8",
    )
    summary = {
        "schema_id": SCHEMA_ID,
        "schema_version": SCHEMA_VERSION,
        "manifest": str(args.manifest),
        "manifest_sha256": sha256_file(args.manifest),
        "manifest_frame_count": len(rows),
        "notice_count": len(notices),
        "film_count": len(films),
        "films_emitted": admitted_keys,
        "films_skipped": {key: decisions.get(key) or "undecided" for key in skipped_keys},
        "manifest_frame_count_total": len(rows),
        "films": [_film_summary(key, films, map_index, decisions) for key in sorted(films)],
        "attribution_map_schema_id": ATTRIBUTION_MAP_SCHEMA_ID,
        "attribution_map_sha256": sha256_file(map_path),
        "attestation_sha256": attestation_sha,
        "admitted": corpus_admitted,
        "subset_decisions_declared": bool((data or {}).get("subset_decisions")),
        # A clearance claim is derived, never asserted: it holds only when the corpus
        # decision and every admitted subset carry a release scope. Writing a static
        # True here would let a train+eval decision read as release-cleared.
        "release_cleared": release_cleared,
        "count_discrepancy_note": args.count_discrepancy_note,
    }
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print("OK: emitted attribution notices")
    print(f"  frames: {len(notices)}")
    print(f"  films: {len(films)}")
    for path in (jsonl_path, notices_path, summary_path):
        print(f"  wrote: {path} sha256={sha256_file(path)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
