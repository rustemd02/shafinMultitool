#!/usr/bin/env python3
"""Build one genuinely self-contained CameraCoach visual audit HTML from PRIVATE restored data.

This tool must run in the user's own private cloud runtime. It never reads
transport keys, uploads, calls a model, or makes network requests. The output
HTML contains real source images and annotations; treat the resulting file as
private even if all source scenes are procedural.
"""
from __future__ import annotations
import argparse
import base64
import collections
import hashlib
import io
import json
from pathlib import Path
from PIL import Image, ImageOps

EXPECTED_ROWS = 4889
EXPECTED_SOURCE = {"v19": 3353, "v20": 1536}
EXPECTED_SPLITS = {"train": 3144, "validation": 680, "test": 1065}
PRIORITIES = ["recommend", "keep", "abstain", "ask"]
SPLITS = ["test", "validation", "train"]

def fnv32(s: str) -> int:
    h = 2166136261
    for ch in s:
        h ^= ord(ch)
        h = h * 16777619 & 0xFFFFFFFF
    return h

def load_jsonl(path: Path) -> list[dict]:
    with path.open("r", encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]

def source(r: dict) -> str:
    return r["provenance"]["native_source"]

def scene(r: dict) -> str:
    if source(r) == "v20":
        return r["provenance"]["native_record_id"].split(":")[0]
    return r["origin_group"]

def pick_source(records: list[dict], src: str, quota: int) -> list[dict]:
    groups = collections.defaultdict(list)
    for r in records:
        if source(r) == src:
            groups[r["origin_group"]].append(r)
    entries = sorted(groups.items(), key=lambda item: fnv32(item[0] + "v22"))
    selected, taken = [], set()
    for dec in PRIORITIES:
        for spl in SPLITS:
            target = max(1, round(quota / 16))
            count = 0
            for group, rows in entries:
                if count >= target or len(selected) >= quota:
                    break
                if group in taken:
                    continue
                candidates = sorted(
                    (r for r in rows if r["targets"]["decision"] == dec and r["split"] == spl),
                    key=lambda r: fnv32(r["record_id"]),
                )
                if candidates:
                    selected.append(candidates[0])
                    taken.add(group)
                    count += 1
    for group, rows in entries:
        if len(selected) >= quota:
            break
        if group in taken:
            continue
        desired = PRIORITIES[fnv32(group) % len(PRIORITIES)]
        chosen = min(rows, key=lambda r: (r["targets"]["decision"] != desired, fnv32(r["record_id"])))
        selected.append(chosen)
        taken.add(group)
    return selected

def pick(records: list[dict], n: int) -> list[dict]:
    v20_groups = len(set(r["origin_group"] for r in records if source(r) == "v20"))
    target20 = min(v20_groups, round(n * 0.6))
    selected = pick_source(records, "v20", target20)
    selected.extend(pick_source(records, "v19", n - len(selected)))
    selected.sort(key=lambda r: fnv32(r["record_id"] + "case"))
    if len(selected) != n:
        raise ValueError(f"Only {len(selected)} scenes selected; expected {n}")
    if len({r["origin_group"] for r in selected}) != len(selected):
        raise ValueError("Selected cases share an origin group")
    return selected

def get_path(root: Path, rel: str) -> Path:
    path = (root / rel).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError(f"Unsafe media path: {rel}")
    return path

def convert_media(path: Path, longer_side: int, quality: int) -> str:
    with Image.open(path) as im:
        out = ImageOps.exif_transpose(im).convert("RGB")
        out.thumbnail((longer_side, longer_side), Image.Resampling.LANCZOS)
        buffer = io.BytesIO()
        out.save(buffer, format="JPEG", quality=quality, optimize=True, subsampling=0)
    return "data:image/jpeg;base64," + base64.b64encode(buffer.getvalue()).decode("ascii")

def check_sha(root: Path, rel: str, expected: str) -> None:
    p = get_path(root, rel)
    if not p.is_file():
        raise FileNotFoundError(p)
    digest = hashlib.sha256()
    with p.open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    if digest.hexdigest() != expected:
        raise ValueError(f"Media SHA-256 mismatch: {rel}")

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", required=True, type=Path, help="Restored cc21-unified-actions directory")
    parser.add_argument("--template", type=Path, default=Path(__file__).with_name("CameraCoach_Quality_Audit.html"))
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--count", type=int, default=180)
    parser.add_argument("--jpeg-quality", type=int, default=68)
    parser.add_argument("--image-max-side", type=int, default=440)
    parser.add_argument("--contrasts", type=int, default=30, help="Additional same-scene cases for comparison, not primary sampled origins")
    args = parser.parse_args()
    if not 1 <= args.count <= 300:
        parser.error("--count must be between 1 and 300")
    if not 35 <= args.jpeg_quality <= 90:
        parser.error("--jpeg-quality must be between 35 and 90")
    if not 150 <= args.image_max_side <= 1200:
        parser.error("--image-max-side must be between 150 and 1200")

    root = args.dataset.resolve()
    raw_path = root / "records.jsonl"
    verifier_path = root / "verifier_sequences.jsonl"
    if not raw_path.is_file() or not verifier_path.is_file():
        raise ValueError("Dataset must contain records.jsonl and verifier_sequences.jsonl")
    all_rows = load_jsonl(raw_path)
    src_counts = collections.Counter(source(r) for r in all_rows)
    split_counts = collections.Counter(r["split"] for r in all_rows)
    if len(all_rows) != EXPECTED_ROWS or dict(src_counts) != EXPECTED_SOURCE or dict(split_counts) != EXPECTED_SPLITS:
        raise ValueError(f"Unexpected corpus: {len(all_rows)} rows, {dict(src_counts)}, {dict(split_counts)}")
    selected = pick(all_rows, args.count)
    ids = {r["record_id"] for r in selected}
    primary_origin_groups = {r["origin_group"] for r in selected}

    by_group = collections.defaultdict(list)
    for row in all_rows:
        by_group[row["origin_group"]].append(row)
    additions = []
    for r in selected:
        if len(additions) >= args.contrasts:
            break
        alternatives = [
            q for q in by_group[r["origin_group"]]
            if q["record_id"] != r["record_id"] and
            (q["targets"]["chosen_index"] != r["targets"]["chosen_index"] or
             q["targets"]["decision"] != r["targets"]["decision"])
        ]
        if not alternatives:
            alternatives = [q for q in by_group[r["origin_group"]] if q["record_id"] != r["record_id"]]
        if alternatives:
            alt = min(alternatives, key=lambda q: fnv32(q["record_id"]))
            if alt["record_id"] not in ids:
                additions.append(alt)
                ids.add(alt["record_id"])

    embedded_records = selected + additions
    wanted_scenes = {scene(r) for r in embedded_records if source(r) == "v20"}
    all_verifiers = load_jsonl(verifier_path)
    verifiers = [v for v in all_verifiers if v["scene_id"] in wanted_scenes]
    expected_paths = {}

    for r in embedded_records:
        history = r["observations"]["history"]
        if len(history) != 3:
            raise ValueError("Nonstandard input history in " + r["record_id"])
        for entry in history:
            existing = expected_paths.setdefault(entry["path"], entry["sha256"])
            if existing != entry["sha256"]:
                raise ValueError("Conflicting original image hashes")
    for v in verifiers:
        # All alternatives are included as outcomes, but only t=1s images
        # are needed in the interactive visual inspector.
        for entry in v.get("after_media", []):
            if abs(float(entry["t_s"]) - 1.0) > .01:
                continue
            existing = expected_paths.setdefault(entry["path"], entry["sha256"])
            if existing != entry["sha256"]:
                raise ValueError("Conflicting outcome image hashes")

    previews = {}
    for i, (rel, sha) in enumerate(sorted(expected_paths.items()), 1):
        check_sha(root, rel, sha)
        previews[rel] = convert_media(get_path(root, rel), args.image_max_side, args.jpeg_quality)
        if i % 200 == 0:
            print(f"Validated and encoded {i}/{len(expected_paths)} actual images", flush=True)

    # Do not let untrusted source JSON terminate this script tag.
    source_digest = hashlib.sha256(raw_path.read_bytes()).hexdigest()
    payload = {
        "schema": "cc22.embedded-review.v1",
        "dataset_id": "cc21-unified-sha256-" + source_digest,
        "source_total_records": EXPECTED_ROWS,
        "source_split_counts": dict(split_counts),
        "source_counts": dict(src_counts),
        "sample_ids": [r["record_id"] for r in selected],
        "records": embedded_records,
        "verifier_sequences": verifiers,
        "images": previews,
        "missing_media": [],
        "contains_original_native_fullres": False,
        "human_quality_reviews": 0,
        "sample_unique_origins": len(primary_origin_groups),
        "public_distribution_authorized": False,
    }
    serialized = json.dumps(payload, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
    serialized = serialized.replace("<", "\\u003c").replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")
    template = args.template.read_text(encoding="utf-8")
    marker = '<script>\n"use strict";'
    if template.count(marker) != 1 or "function bootstrapEmbedded()" not in template:
        raise ValueError("Template lacks the embedded-data boot sequence")
    html = template.replace(
        marker,
        '<script id="embedded-data" type="application/json">' + serialized + "</script>\n" + marker,
    )
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(html, encoding="utf-8")
    report = {
        "schema": "cc22.private_embedded_html_report.v1",
        "dataset_record_count": len(all_rows),
        "sample_cases": len(selected),
        "sample_unique_origin_groups": len(primary_origin_groups),
        "additional_same_scene_contrasts": len(additions),
        "embedded_verifier_sequences": len(verifiers),
        "verified_source_images": len(previews),
        "html_bytes": args.out.stat().st_size,
        "html_sha256": hashlib.sha256(args.out.read_bytes()).hexdigest(),
        "encrypted_delivery_part_count": 0,
        "new_training_rows": 0,
        "new_human_labels": 0,
        "model_calls": 0,
        "browser_review_required": True,
        "contains_private_key": False,
        "not_public_distribution_eligible": True,
    }
    report_path = args.out.with_suffix(".receipt.json")
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("CAMERACOACH_HTML_AUDIT_READY " + json.dumps(report, ensure_ascii=False), flush=True)

if __name__ == "__main__":
    main()
