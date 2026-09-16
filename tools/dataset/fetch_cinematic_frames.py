#!/usr/bin/env python3
"""Harvest cinematic frames (video screengrabs) for the Camera Coach corpus.

Why this exists: the app coaches cinematic shooting, so its training and
annotation frames must look like film/video frames, not stock photos of
flowers. This lane takes freely-licensed films, extracts frames with the
native AVFoundation tool, drops near-duplicate frames from the same shot, and
writes a provenance-carrying manifest.

Sources are limited to licences that allow research/demo use:
  * Blender Open Movies — CC-BY (Tears of Steel, Big Buck Bunny, Sintel, ...)
  * archive.org public-domain features (opt-in via --source)

Data lands OUTSIDE the repository; nothing here is redistributed.

Usage:
    python3 tools/dataset/fetch_cinematic_frames.py \
        --out "$HOME/Documents/XCode/setos-backend/local-data/SETOS/Datasets/camera-coach/research/cinematic" \
        --source tears_of_steel --interval 3 --max 260
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

SOURCE_REGISTRY: dict[str, dict] = {
    "tears_of_steel": {
        "title": "Tears of Steel (Blender Open Movie)",
        "url": "https://download.blender.org/demo/movies/ToS/tears_of_steel_720p.mov",
        "license": "CC-BY 3.0 (Blender Foundation)",
        "filename": "tears_of_steel_720p.mov",
        "origin": "download.blender.org",
    },
    "big_buck_bunny": {
        "title": "Big Buck Bunny (Blender Open Movie)",
        "url": "https://download.blender.org/demo/movies/BBB/bbb_sunflower_1080p_30fps_normal.mp4.zip",
        "license": "CC-BY 3.0 (Blender Foundation)",
        "filename": "bbb_sunflower_1080p_30fps_normal.mp4.zip",
        "origin": "download.blender.org",
        "unzip": True,
    },
    "sintel": {
        "title": "Sintel (Blender Open Movie)",
        "url": "https://download.blender.org/demo/movies/sintel-hd.avi.zip",
        "license": "CC-BY 3.0 (Blender Foundation)",
        "filename": "sintel-hd.avi.zip",
        "origin": "download.blender.org",
        "unzip": True,
    },
    "tos_teaser": {
        "title": "Tears of Steel — teaser (Blender Open Movie)",
        "url": "https://download.blender.org/demo/movies/tears-of-steel_teaser.mp4.zip",
        "license": "CC-BY 3.0 (Blender Foundation)",
        "filename": "tears-of-steel_teaser.mp4.zip",
        "origin": "download.blender.org",
        "unzip": True,
    },
    "mancandy": {
        "title": "Mancandy (Blender short)",
        "url": "https://download.blender.org/demo/movies/mancandy_lscm.mov",
        "license": "CC-BY (Blender Foundation)",
        "filename": "mancandy_lscm.mov",
        "origin": "download.blender.org",
    },
    "elephants_dream": {
        "title": "Elephants Dream (Blender Open Movie)",
        "url": "https://download.blender.org/ED/ED_HD.avi",
        "license": "CC-BY 2.5 (Blender Foundation)",
        "filename": "ED_HD.avi",
        "origin": "download.blender.org",
    },
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(command: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(command, capture_output=True, text=True, **kwargs)


def ensure_source(source: dict, sources_dir: Path) -> Path | None:
    """Download (once) and unpack if needed; returns the playable video path."""
    target = sources_dir / source["filename"]
    if not target.exists():
        print(f"[download] {source['title']} → {target.name}")
        result = run(["curl", "-sL", "--max-time", "3000", "-o", str(target), source["url"]])
        if result.returncode != 0 or not target.exists():
            print(f"[fail] download failed for {source['title']}: {result.stderr[:200]}")
            return None
    if source.get("unzip"):
        mp4 = target.with_suffix("")  # .zip → .mp4
        if not mp4.exists():
            result = run(["unzip", "-o", "-q", str(target), "-d", str(sources_dir)])
            if result.returncode != 0:
                print(f"[fail] unzip failed: {result.stderr[:200]}")
                return None
        return mp4 if mp4.exists() else None
    return target


def average_hash(path: Path, size: int = 8) -> int | None:
    try:
        from PIL import Image
    except ImportError:
        return None
    try:
        with Image.open(path) as image:
            small = image.convert("L").resize((size, size))
            pixels = list(small.getdata())
    except Exception:
        return None
    mean = sum(pixels) / len(pixels)
    bits = 0
    for index, value in enumerate(pixels):
        if value >= mean:
            bits |= 1 << index
    return bits


def hamming(left: int, right: int) -> int:
    return bin(left ^ right).count("1")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--source", action="append", required=True,
                        choices=sorted(SOURCE_REGISTRY))
    parser.add_argument("--interval", type=float, default=3.0)
    parser.add_argument("--max", type=int, default=260, help="кадров на фильм")
    parser.add_argument("--dedupe-distance", type=int, default=4,
                        help="порог Хэмминга для отсева почти одинаковых кадров")
    parser.add_argument("--extractor", type=Path, default=Path("/tmp/extract_frames"))
    args = parser.parse_args(argv)

    if not args.extractor.exists():
        print("нет собранного извлекателя; соберите:\n"
              "  swiftc -O tools/dataset/extract_video_frames.swift -o /tmp/extract_frames")
        return 1

    sources_dir = args.out / "sources"
    sources_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = args.out / "manifest.jsonl"
    existing_ids: set[str] = set()
    if manifest_path.exists():
        for line in manifest_path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                existing_ids.add(json.loads(line)["record_id"])

    total_added = 0
    for key in args.source:
        source = SOURCE_REGISTRY[key]
        video = ensure_source(source, sources_dir)
        if video is None or not video.exists():
            continue
        frames_dir = args.out / "frames" / key
        frames_dir.mkdir(parents=True, exist_ok=True)
        print(f"[extract] {source['title']} (интервал {args.interval}s, максимум {args.max})")
        result = run([
            str(args.extractor), "--input", str(video), "--out", str(frames_dir),
            "--interval", str(args.interval), "--max", str(args.max), "--long-side", "1280",
        ])
        if result.returncode != 0:
            print(f"[fail] extractor: {result.stderr[:300]}")
            continue
        print("  " + (result.stdout or "").strip()[:160])

        frame_manifest = frames_dir / "frames.jsonl"
        if not frame_manifest.exists():
            continue
        kept: list[dict] = []
        last_hash: int | None = None
        for line in frame_manifest.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            frame = json.loads(line)
            path = frames_dir / frame["frame"]
            record_id = f"cine__{key}__{frame['frame'].replace('.jpg', '')}"
            if record_id in existing_ids:
                continue
            digest = average_hash(path)
            if digest is not None and last_hash is not None and hamming(digest, last_hash) <= args.dedupe_distance:
                path.unlink(missing_ok=True)   # same shot, previous frame already kept
                continue
            last_hash = digest
            kept.append({
                "record_id": record_id,
                "image_path": str(path),
                "image_sha256": sha256_file(path),
                "timestamp_s": frame["timestamp_s"],
                "mean_luma": frame["mean_luma"],
                "stddev": frame["stddev"],
                "provenance": {
                    "source": "cinematic",
                    "title": source["title"],
                    "license": source["license"],
                    "origin": source["origin"],
                    "origin_url": source["url"],
                    "timestamp_s": frame["timestamp_s"],
                    "kind": "video_screengrab",
                },
            })
        with manifest_path.open("a", encoding="utf-8") as handle:
            for record in kept:
                handle.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
        existing_ids.update(record["record_id"] for record in kept)
        total_added += len(kept)
        print(f"[ok] {source['title']}: +{len(kept)} кадров (всего {len(existing_ids)})")

    receipt = {
        "sources": args.source,
        "added_now": total_added,
        "total_frames": len(existing_ids),
        "interval_s": args.interval,
        "manifest": str(manifest_path),
        "manifest_sha256": sha256_file(manifest_path) if manifest_path.exists() else None,
        "license_note": "CC-BY Blender open movies; research/demo use, attribution required, no redistribution",
    }
    (args.out / "receipt.json").write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + "\n",
                                           encoding="utf-8")
    print(json.dumps(receipt, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
