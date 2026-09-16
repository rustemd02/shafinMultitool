#!/usr/bin/env python3
"""Group frames by origin family and (only if rights are admitted) emit splits.

Why families: adjacent frames of one clip, derivatives of one original, and
related episodes are not independent samples. A random per-jpg split would put
neighbouring frames of the same shot into different splits and leak the test
set. This tool keeps a whole family in a single split.

Fail-closed behaviour:

* The rights manifest is the admission source of truth. While it is
  ``template_only`` / ``record_count == 0`` / has no admitted record matching
  this corpus, the tool prints the grouping and REFUSES to emit splits (exit 1).
* ``--dry-run`` never writes files, even when rights are admitted.
* AVA / AADB / EVA entries can never admit a split here.

No network access.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import re
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
HOME = Path.home()

SCHEMA_ID = "camera-split-groups-v1"
SCHEMA_VERSION = "v1.0.0"

DEFAULT_MANIFEST = (
    HOME
    / "Documents/XCode/setos-backend/local-data/SETOS/Datasets/camera-coach/research/cinematic/manifest.jsonl"
)
DEFAULT_RIGHTS_MANIFEST = REPO_ROOT / "datasets/camera-coach/v1/rights-manifest.jsonl"
DEFAULT_OUT_DIR = REPO_ROOT / "datasets/camera-coach/v1"
DEFAULT_CORPUS_ID = "cinematic"
DEFAULT_SOURCE_ID = "cinematic"

SPLITS = ("train", "validation", "calibration", "locked")
DEFAULT_RATIOS = {"train": 0.70, "validation": 0.15, "calibration": 0.10, "locked": 0.05}

BARRED_PRODUCTION_TOKENS = ("ava", "aadb", "eva")
_BARRED = re.compile(r"(?:^|[^a-z])(" + "|".join(BARRED_PRODUCTION_TOKENS) + r")(?:[^a-z]|$)")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    rows = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if line.strip():
                rows.append(json.loads(line))
    return rows


def family_of(record: dict[str, Any]) -> tuple[str, str]:
    """Return (family_kind, family_key) for a frame record.

    Priority: explicit derivation/lineage hints, then episode/series grouping,
    then the clip identity (so adjacent frames of one clip share a family),
    then the containing directory as a last resort.
    """
    provenance = record.get("provenance") or {}
    for key in ("derives_from", "original_record_id", "parent_record_id", "source_asset_id"):
        value = provenance.get(key)
        if value:
            return ("derivation", str(value))
    for key in ("episode_id",):
        value = provenance.get(key)
        if value:
            return ("episode", str(value))
    for key in ("series_id", "episode_group"):
        value = provenance.get(key)
        if value:
            return ("series", str(value))
    origin = provenance.get("origin_url") or provenance.get("title")
    if origin:
        label = Path(str(record.get("image_path", ""))).parent.name or provenance.get("title", "")
        return ("clip", f"{label}|{origin}")
    return ("path", str(Path(str(record.get("image_path", ""))).parent))


def group_records(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    groups: dict[tuple[str, str], dict[str, Any]] = {}
    order: list[tuple[str, str]] = []
    for record in rows:
        kind, key = family_of(record)
        identity = (kind, key)
        if identity not in groups:
            label = key.split("|", 1)[0] if kind == "clip" else key
            groups[identity] = {
                "group_id": "grp_" + hashlib.sha256(f"{kind}|{key}".encode()).hexdigest()[:16],
                "family_kind": kind,
                "family_key": key,
                "family_label": label,
                "record_ids": [],
            }
            order.append(identity)
        groups[identity]["record_ids"].append(record["record_id"])
    result = [groups[i] for i in order]
    for group in result:
        group["frame_count"] = len(group["record_ids"])
    return result


def _iter_admission_entries(lines: list[dict[str, Any]]) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    for line in lines:
        if isinstance(line.get("entries"), list):
            for entry in line["entries"]:
                if isinstance(entry, dict):
                    entries.append(entry)
        if "admitted" in line or "corpus_id" in line or "source_id" in line:
            entries.append(line)
    return entries


def _matches(entry: dict[str, Any], corpus: str, source: str) -> bool:
    if entry.get("corpus_id"):
        return entry["corpus_id"] == corpus
    if entry.get("source_id"):
        return entry["source_id"] == source
    if entry.get("source"):
        return entry["source"] == source
    corpora = entry.get("admitted_corpora")
    if isinstance(corpora, list):
        return corpus in corpora
    return False


def check_rights_admission(
    path: Path, corpus: str, source: str
) -> tuple[bool, list[str], list[dict[str, Any]]]:
    """Return (admitted, reasons/missing, matching admitted entries)."""
    if not path.exists():
        return False, [f"rights manifest not found: {path}"], []
    lines = load_jsonl(path)
    if not lines:
        return False, [f"rights manifest is empty: {path}"], []
    entries = _iter_admission_entries(lines)
    admitted = [e for e in entries if e.get("admitted") is True]
    matching = [e for e in admitted if _matches(e, corpus, source)]
    reasons: list[str] = []
    if not admitted:
        reasons.append(
            "rights manifest has no record with admitted=true "
            "(template_only/record_count=0 means the owner has not decided)"
        )
    if admitted and not matching:
        reasons.append(
            f"no admitted record matches corpus_id={corpus!r} / source_id={source!r}"
        )
    # Defense in depth: never admit a barred corpus through this path.
    barred = [e for e in matching if _BARRED.search(json.dumps(e).lower())]
    if barred:
        return False, [f"admitted record matches research-only source tokens: {barred[0]}"], []
    return (bool(matching) and not reasons, reasons, matching)


def largest_remainder(targets: dict[str, float], total: int) -> dict[str, int]:
    raw = {split: targets[split] * total for split in SPLITS}
    floors = {split: int(raw[split]) for split in SPLITS}
    remainder = total - sum(floors.values())
    order = sorted(SPLITS, key=lambda s: (raw[s] - floors[s], s), reverse=True)
    for i in range(remainder):
        floors[order[i % len(order)]] += 1
    return floors


def assign_groups(groups: list[dict[str, Any]], seed: int) -> dict[str, int]:
    """Assign whole groups to splits, keeping every family intact."""
    total = sum(group["frame_count"] for group in groups)
    targets = largest_remainder(DEFAULT_RATIOS, total)
    shuffled = list(groups)
    random.Random(seed).shuffle(shuffled)
    assigned = {split: 0 for split in SPLITS}
    for group in shuffled:
        split = max(SPLITS, key=lambda s: (targets[s] - assigned[s], -assigned[s]))
        group["split"] = split
        assigned[split] += group["frame_count"]
    return targets


def parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--rights-manifest", type=Path, default=DEFAULT_RIGHTS_MANIFEST)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--prefix", default="cinematic")
    parser.add_argument("--corpus-id", default=DEFAULT_CORPUS_ID)
    parser.add_argument("--source-id", default=DEFAULT_SOURCE_ID)
    parser.add_argument("--seed", type=int, default=20260913)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args(argv)


def print_grouping(groups: list[dict[str, Any]]) -> None:
    print(f"grouping: {len(groups)} origin famil(y/ies)")
    for group in groups:
        print(
            f"  {group['group_id']} kind={group['family_kind']} "
            f"label={group['family_label']!r} frames={group['frame_count']} "
            f"records={group['record_ids'][:3]}{'...' if group['frame_count'] > 3 else ''}"
        )


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    if not args.manifest.exists():
        print(f"REFUSED: manifest not found: {args.manifest}", file=sys.stderr)
        return 1
    rows = load_jsonl(args.manifest)
    if not rows:
        print(f"REFUSED: manifest is empty: {args.manifest}", file=sys.stderr)
        return 1

    groups = group_records(rows)
    print_grouping(groups)

    admitted, reasons, matching = check_rights_admission(
        args.rights_manifest, args.corpus_id, args.source_id
    )
    if not admitted:
        print(
            "REFUSED to emit splits: rights manifest is not admitted for this corpus. "
            "Per-jpg random splitting is forbidden because neighbouring frames of one "
            "clip must stay in one split.",
            file=sys.stderr,
        )
        for reason in reasons:
            print(f"  - {reason}", file=sys.stderr)
        print(
            "  - owner must append an admitted rights record or run the attestation "
            "toolkit first; existing templates are not overwritten",
            file=sys.stderr,
        )
        return 1

    # The admission record may carry the owner's per-film decisions. When it does,
    # only admitted families may enter a split: a quarantined film's frames must not
    # reach train just because the corpus as a whole was admitted.
    subset_decisions: dict[str, Any] = {}
    for entry in matching:
        decisions = entry.get("subset_decisions") or {}
        if decisions:
            subset_decisions = decisions
            break
    admission_basis = "subset_decisions" if subset_decisions else "corpus_level"
    excluded_families: list[dict[str, Any]] = []
    if subset_decisions:
        kept = []
        for group in groups:
            label = str(group.get("family_label"))
            decision = str((subset_decisions.get(label) or {}).get("decision") or "")
            if decision == "admit":
                kept.append(group)
            else:
                excluded_families.append({"family_label": label,
                                          "decision": decision or "undecided",
                                          "frames": group["frame_count"]})
        if not kept:
            print("REFUSED to emit splits: no admitted family carries frames "
                  "(every film in the corpus is quarantined/rejected/undecided)",
                  file=sys.stderr)
            return 1
        groups = kept
        print("excluding non-admitted families: "
              + ", ".join(f"{item['family_label']}={item['decision']} "
                          f"({item['frames']} frames)" for item in excluded_families))
    else:
        print("admission basis: corpus-level record (no per-film decisions declared), "
              "so every family in the corpus is grouped")

    target_counts = assign_groups(groups, args.seed)
    print(
        f"rights admitted ({len(matching)} matching record(s)); target frame counts: "
        + ", ".join(f"{s}={target_counts[s]}" for s in SPLITS)
    )
    counts = {split: 0 for split in SPLITS}
    for group in groups:
        counts[group["split"]] += group["frame_count"]

    if args.dry_run:
        print("DRY-RUN: nothing will be written.")
        for group in groups:
            print(f"  {group['group_id']} -> {group['split']} ({group['frame_count']} frames)")
        print("Would write:")
        print(f"  {args.out_dir / (args.prefix + '-split-groups.draft.jsonl')}")
        print(f"  {args.out_dir / (args.prefix + '-splits.draft.json')}")
        return 0

    args.out_dir.mkdir(parents=True, exist_ok=True)
    groups_path = args.out_dir / f"{args.prefix}-split-groups.draft.jsonl"
    splits_path = args.out_dir / f"{args.prefix}-splits.draft.json"

    groups_path.write_text(
        "\n".join(json.dumps(g, ensure_ascii=False, sort_keys=True) for g in groups) + "\n",
        encoding="utf-8",
    )
    families_per_split: dict[str, set[str]] = {split: set() for split in SPLITS}
    for group in groups:
        families_per_split[group["split"]].add(group["group_id"])
    # By construction each group is atomic; assert no family appears twice.
    seen: set[str] = set()
    leak = 0
    for group in groups:
        if group["group_id"] in seen:
            leak += 1
        seen.add(group["group_id"])

    summary = {
        "schema_id": SCHEMA_ID,
        "schema_version": SCHEMA_VERSION,
        "manifest": str(args.manifest),
        "manifest_sha256": sha256_file(args.manifest),
        "rights_manifest": str(args.rights_manifest),
        "rights_manifest_sha256": sha256_file(args.rights_manifest),
        "corpus_id": args.corpus_id,
        "seed": args.seed,
        "ratios": DEFAULT_RATIOS,
        "admission_basis": admission_basis,
        "excluded_families": excluded_families,
        "manifest_frame_count_total": len(rows),
        "group_count": len(groups),
        "frame_count": sum(g["frame_count"] for g in groups),
        "target_frame_counts": target_counts,
        "actual_frame_counts": counts,
        "split_count": len(SPLITS),
        "cross_split_leak_count": leak,
        "admitted_record_ids": [str(e.get("record_id") or e.get("source_id")) for e in matching],
        "groups": [
            {
                "group_id": g["group_id"],
                "family_kind": g["family_kind"],
                "family_label": g["family_label"],
                "frame_count": g["frame_count"],
                "split": g["split"],
            }
            for g in groups
        ],
    }
    splits_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("OK: emitted split groups")
    for path in (groups_path, splits_path):
        print(f"  wrote: {path} sha256={sha256_file(path)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
