#!/usr/bin/env python3
"""Fetch AVA human aesthetic ratings (image + mean_score + total_votes).

AVA is a human-rated aesthetics corpus: every image carries a mean opinion
score from real annotators and the number of votes. That is exactly the
supervision the Camera Coach beauty head needs, which the /silver/ lanes could
never provide.

Licence posture (owner decision 2026-09-13: thesis/demo/research): AVA is a
research dataset; images are rights-uncleared by upstream. Data is written
OUTSIDE the repository and each run emits a receipt with counts and the
manifest hash. Nothing here may be redistributed.

Usage:
    python3 tools/dataset/fetch_ava_human_ratings.py \
        --out "$HOME/Documents/XCode/setos-backend/local-data/SETOS/Datasets/camera-coach/research/ava/human-rated" \
        --target 20000
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path

DATASET = "trojblue/AVA-aesthetics-10pct-min50-10bins"
PAGE = 100


def _curl_json(url: str, attempts: int = 4) -> dict | None:
    for attempt in range(attempts):
        result = subprocess.run(["curl", "-s", "--max-time", "90", url],
                                capture_output=True, text=True)
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError:
            time.sleep(1.5 * (attempt + 1))
    return None


def fetch_rows(offset: int, split: str = "validation") -> list[dict]:
    url = (f"https://datasets-server.huggingface.co/rows"
           f"?dataset={DATASET.replace('/', '%2F')}&config=default&split={split}"
           f"&offset={offset}&length={PAGE}")
    payload = _curl_json(url)
    if not payload or "rows" not in payload:
        return []
    return payload["rows"]


def download(url: str, destination: Path) -> bool:
    destination.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        ["curl", "-sL", "--max-time", "180", "-o", str(destination), url],
        capture_output=True, text=True,
    )
    if result.returncode != 0 or not destination.exists() or destination.stat().st_size == 0:
        destination.unlink(missing_ok=True)
        return False
    return True


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--target", type=int, default=20000)
    parser.add_argument("--offset", type=int, default=0)
    parser.add_argument("--workers", type=int, default=8, help="параллельных загрузок")
    parser.add_argument("--split", default="validation", choices=["validation", "train"])
    parser.add_argument("--delay", type=float, default=0.25,
                        help="пауза между изображениями, чтобы не долбить сервер")
    args = parser.parse_args(argv)

    images = args.out / "images"
    manifest = args.out / "manifest.jsonl"
    args.out.mkdir(parents=True, exist_ok=True)

    known: set[str] = set()
    if manifest.exists():
        for line in manifest.read_text(encoding="utf-8").splitlines():
            if line.strip():
                known.add(json.loads(line)["image_id"])
    print(f"уже есть: {len(known)} изображений в {manifest}")

    stored = 0
    offset = args.offset
    failures = 0
    from concurrent.futures import ThreadPoolExecutor

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        while stored < args.target:
            rows = fetch_rows(offset, args.split)
            if not rows:
                print(f"строк больше нет на offset={offset}; останов")
                break
            batch: list[tuple[dict, str]] = []
            for row in rows:
                record = row.get("row", {})
                image = record.get("image") or record.get("img") or {}
                url = image.get("src") if isinstance(image, dict) else None
                image_id = str(record.get("image_id") or record.get("id") or "")
                if not url or not image_id or image_id in known:
                    continue
                batch.append((record, url))
            if not batch:
                offset += PAGE
                continue

            results = list(pool.map(
                lambda item: (item[0], item[1], download(item[1], images / f"{str(item[0].get('image_id') or item[0].get('id'))}.jpg")),
                batch,
            ))
            for record, _url, ok in results:
                image_id = str(record.get("image_id") or record.get("id") or "")
                if not ok:
                    failures += 1
                    continue
                destination = images / f"{image_id}.jpg"
                entry = {
                    "image_id": image_id,
                    "path": str(destination),
                    "mean_score": record.get("mean_score"),
                    "total_votes": record.get("total_votes"),
                    "sha256": sha256_file(destination),
                    "source": DATASET,
                    "license": "AVA research dataset; images rights-uncleared upstream",
                }
                with manifest.open("a", encoding="utf-8") as handle:
                    handle.write(json.dumps(entry, ensure_ascii=False, sort_keys=True) + "\n")
                known.add(image_id)
                stored += 1
            offset += PAGE
            print(f"  скачано {stored}/{args.target} (offset={offset}, ошибок {failures})", flush=True)

    receipt = {
        "dataset": DATASET,
        "split": args.split,
        "target": args.target,
        "downloaded_now": stored,
        "total_in_manifest": len(known),
        "failures": failures,
        "manifest": str(manifest),
        "manifest_sha256": sha256_file(manifest) if manifest.exists() else None,
        "license": "AVA research dataset; research/demo use only, no redistribution",
    }
    (args.out / "receipt.json").write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + "\n",
                                           encoding="utf-8")
    print(json.dumps(receipt, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
