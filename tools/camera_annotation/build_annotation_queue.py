#!/usr/bin/env python3
"""Build an annotation queue for the Camera Coach human-gold store.

Samples frames from the corpora that are already on disk, records per-image
provenance (source, licence, origin) so the label store stays auditable, and
freezes each record with its SHA-256.

Sources and their licences — recorded per record so the queue stays auditable;
none of them is a right to release:
  benchmark  bundled 174-label DeviceBenchmark pack  (project-owned; CC-002 excludes it from Release)
  ava        AVA aesthetics corpus (10%, min50 bins) (research only; not for redistribution)
  aadb       AADB aesthetics + attributes            (research only)

No owner rights decision is recorded for the research corpora. The AVA rights
question is explicitly left undecided in this project
(`docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-release/D01-D05-rights-and-corpora.md`),
and the frozen source catalog states that a research source is never
release-cleared by it (`datasets/camera-coach/v1/research-source-catalog.json`,
`rights_policy.release_rule`). A frame queued from these sources is therefore
annotation input only: it cannot become release-admitted before the owner's
per-asset decision (packet A) and its admission record exist.

Usage:
    python3 tools/camera_annotation/build_annotation_queue.py \
        --output ~/Documents/XCode/setos-backend/local-data/SETOS/annotation/queue-v1.jsonl \
        --per-source benchmark=80 ava=120 aadb=120 --seed 20260913
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
HOME = Path.home()

DEFAULT_SOURCES: dict[str, tuple[Path, str, str]] = {
    "benchmark": (
        REPO / "shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1/images",
        "project-owned benchmark pack (CC-002 excludes it from Release)",
        "repo",
    ),
    "ava": (
        HOME / "Documents/XCode/setos-backend/local-data/SETOS/Datasets/camera-coach/research/ava/legacy-silver-4000/images",
        "AVA aesthetics (research only; not for redistribution)",
        "huggingface:trojblue/AVA-aesthetics-10pct-min50-10bins",
    ),
    "aadb": (
        HOME / "Documents/XCode/setos-backend/local-data/SETOS/Datasets/camera-coach/research/aadb/warp256-v1",
        "AADB aesthetics + attributes (research only)",
        "official AADB distribution",
    ),
}

IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}

# Human aesthetic scores that already exist for some corpora. When a frame
# carries one, the annotator only has to confirm or correct it.
SCORE_INDEXES: dict[str, tuple[Path, str, str]] = {
    # source -> (manifest, score field, scale)
    "ava": (HOME / "Documents/XCode/setos-backend/local-data/SETOS/Datasets/camera-coach/research/ava/legacy-silver-4000/manifest.jsonl",
            "mean_score", "ava"),
    "aadb": (HOME / "Documents/XCode/setos-backend/local-data/SETOS/Datasets/camera-coach/research/aadb/warp256-v1/silver-manifest.jsonl",
             "overall_score", "aadb"),
}


def score_index(source: str) -> dict[str, tuple[float, str]]:
    """Map image stem -> (human score, scale) for corpora that ship ratings."""
    entry = SCORE_INDEXES.get(source)
    if entry is None:
        return {}
    manifest, field, scale = entry
    if not manifest.exists():
        return {}
    index: dict[str, tuple[float, str]] = {}
    for line in manifest.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        row = json.loads(line)
        name = row.get("normalized_image_name") or row.get("path") or row.get("image_id") or ""
        score = row.get(field)
        if name is None or score is None:
            continue
        index[Path(str(name)).stem] = (float(score), scale)
    return index


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def collect(root: Path) -> list[Path]:
    if not root.exists():
        return []
    return sorted(
        path for path in root.rglob("*")
        if path.is_file() and path.suffix.lower() in IMAGE_SUFFIXES
    )


def build_queue(
    *,
    per_source: dict[str, int],
    seed: int,
    sources: dict[str, tuple[Path, str, str]] | None = None,
) -> list[dict]:
    sources = sources or DEFAULT_SOURCES
    rng = random.Random(seed)
    records: list[dict] = []
    for name, count in per_source.items():
        root, licence, origin = sources[name]
        files = collect(root)
        if not files:
            print(f"[skip] {name}: no images under {root}")
            continue
        if count >= len(files):
            chosen = files
        else:
            chosen = sorted(rng.sample(files, count))
        ratings = score_index(name)
        for path in chosen:
            record = {
                "record_id": f"{name}__{path.stem}",
                "image_path": str(path),
                "image_sha256": sha256_file(path),
                "provenance": {"source": name, "license": licence, "origin": origin},
            }
            rating = ratings.get(path.stem)
            if rating is not None:
                record["human_score"], record["score_scale"] = rating
            records.append(record)
        print(f"[ok] {name}: {len(chosen)} of {len(files)} images")
    rng.shuffle(records)
    return records


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--per-source", nargs="*", default=["benchmark=80", "ava=120", "aadb=120"],
                        metavar="NAME=COUNT")
    parser.add_argument("--seed", type=int, default=20260913)
    parser.add_argument("--extra-manifest", action="append", type=Path, default=[],
                        help="готовый манифест в формате очереди (например кино-кадры)")
    args = parser.parse_args(argv)

    per_source: dict[str, int] = {}
    for item in args.per_source:
        name, _, count = item.partition("=")
        if not name or not count.isdigit():
            parser.error(f"--per-source expects NAME=COUNT, got '{item}'")
        if name not in DEFAULT_SOURCES:
            parser.error(f"unknown source '{name}' (known: {sorted(DEFAULT_SOURCES)})")
        per_source[name] = int(count)

    records = build_queue(per_source=per_source, seed=args.seed)
    seen = {r["record_id"] for r in records}
    for manifest in args.extra_manifest:
        if not manifest.exists():
            print(f"[skip] нет манифеста {manifest}")
            continue
        added = 0
        for line in manifest.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            record = json.loads(line)
            if record["record_id"] in seen:
                continue
            seen.add(record["record_id"])
            records.append(record)
            added += 1
        print(f"[ok] {manifest.name}: +{added} записей")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        "\n".join(json.dumps(r, ensure_ascii=False, sort_keys=True) for r in records) + "\n",
        encoding="utf-8",
    )
    print(f"queue: {len(records)} records → {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
