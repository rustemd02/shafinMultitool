#!/usr/bin/env python3
"""DATA-015 acquisition harvester (owner-delegated approval 2026-09-27).

Downloads the four named coverage-gap quotas from policy-clean Openverse
results (license allowlist CC0/PDM/CC-BY/CC-BY-SA, per-item license gate:
license + creator + landing page must all be present, verbatim recording),
writes per-item rights records and SHA-256s into backend local-data.

Everything is recorded verbatim from the API; no license, author or date is
ever invented. Items failing the gate are skipped and counted.

Usage:
  python3 tools/dataset/acquire_openverse_gaps.py --root \
      /Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS
"""

from __future__ import annotations

import argparse
import hashlib
import json
import ssl
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

API = "https://api.openverse.org/v1/images/"
ALLOWED_LICENSES = {"cc0", "pdm", "by", "by-sa"}
USER_AGENT = "SETOS-data015-acquisition/1.0 (research-only, per-item license gate)"

# The python.org runtime does not load a CA store by default; use certifi's
# explicitly so TLS verification stays ON (never bypassed).
import certifi  # noqa: E402

SSL_CONTEXT = ssl.create_default_context(cafile=certifi.where())

GAPS = [
    {
        "gap_id": "GAP-A-occlusion",
        "family": "openverse-occlusion-20260927",
        "quota": 40,
        "queries": [
            ("occluded person", {}),
            ("person behind object", {}),
            ("photobomb", {}),
            ("blocked view foreground", {}),
        ],
    },
    {
        "gap_id": "GAP-B-groups-as-hero",
        "family": "openverse-group-hero-20260927",
        "quota": 40,
        "queries": [
            ("group portrait", {}),
            ("family photograph", {}),
            ("team photo", {}),
            ("class photo", {}),
        ],
    },
    {
        "gap_id": "GAP-C-dirty-lens-focus-miss-organic",
        "family": "openverse-organic-technical-20260927",
        "quota": 40,
        "queries": [
            ("out of focus photograph", {}),
            ("blurred photo", {}),
            ("lens flare", {}),
            ("motion blur photograph", {}),
        ],
    },
    {
        "gap_id": "GAP-D-formats-9x16-1x1-title-safe",
        "family": "openverse-format-aspects-20260927",
        "quota": 25,
        "queries": [
            ("street photography", {"aspect_ratio": "tall"}),
            ("portrait", {"aspect_ratio": "tall"}),
            ("still life", {"aspect_ratio": "square"}),
            ("architecture", {"aspect_ratio": "square"}),
        ],
    },
]

CANDIDATE_BY_SOURCE = {
    "flickr": {"GAP-A-occlusion": "A2-flickr-commons-foreground-blockers",
               "GAP-B-groups-as-hero": "B2-flickr-commons-group-portraits"},
    "wikimedia": {"GAP-A-occlusion": "A1-commons-photobomb-occlusion",
                  "GAP-B-groups-as-hero": "B1-commons-group-photographs",
                  "GAP-C-dirty-lens-focus-miss-organic": "C1-commons-technical-defect-search",
                  "GAP-D-formats-9x16-1x1-title-safe": "D2-commons-dimension-filtered"},
}


def candidate_id_for(gap_id: str, source: str) -> str:
    return CANDIDATE_BY_SOURCE.get(source, {}).get(gap_id, "D1-openverse-aspect-filtered")


def fetch_json(url: str) -> dict:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60, context=SSL_CONTEXT) as response:
        return json.loads(response.read().decode("utf-8"))


def fetch_bytes(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120, context=SSL_CONTEXT) as response:
        return response.read()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    datasets = args.root / "Datasets/camera-coach/research"
    summary = {"created": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
               "tool": "tools/dataset/acquire_openverse_gaps.py",
               "policy": {"allowed_licenses": sorted(ALLOWED_LICENSES),
                          "per_item_license_gate": True},
               "gaps": []}
    seen_ids: set[str] = set()
    seen_sha: set[str] = set()

    for gap in GAPS:
        family_dir = datasets / gap["family"]
        family_dir.mkdir(parents=True, exist_ok=True)
        items_path = family_dir / "items.jsonl"
        records = []
        skipped = {"license": 0, "missing_fields": 0, "duplicate": 0, "download": 0}
        for query, extra in gap["queries"]:
            if len(records) >= gap["quota"]:
                break
            params = {"q": query, "license": ",".join(sorted(ALLOWED_LICENSES)),
                      "page_size": 20, "mature": "false"}
            params.update(extra)
            url = API + "?" + urllib.parse.urlencode(params)
            try:
                payload = fetch_json(url)
            except Exception as exc:  # network honesty: record, do not fake
                print(f"[{gap['gap_id']}] query {query!r} failed: {exc}")
                continue
            for result in payload.get("results", []):
                if len(records) >= gap["quota"]:
                    break
                item_id = str(result.get("id") or "")
                license_name = str(result.get("license") or "").lower()
                creator = str(result.get("creator") or "").strip()
                landing = str(result.get("foreign_landing_url") or "").strip()
                file_url = str(result.get("url") or "").strip()
                if license_name not in ALLOWED_LICENSES:
                    skipped["license"] += 1
                    continue
                if not creator or not landing or not file_url:
                    skipped["missing_fields"] += 1
                    continue
                if item_id in seen_ids:
                    skipped["duplicate"] += 1
                    continue
                try:
                    blob = fetch_bytes(file_url)
                except Exception as exc:
                    print(f"[{gap['gap_id']}] download failed {file_url}: {exc}")
                    skipped["download"] += 1
                    continue
                digest = hashlib.sha256(blob).hexdigest()
                if digest in seen_sha:
                    skipped["duplicate"] += 1
                    continue
                suffix = ".jpg"
                for ext in (".png", ".jpeg", ".webp", ".gif"):
                    if file_url.lower().split("?")[0].endswith(ext):
                        suffix = ext
                        break
                name = f"{gap['gap_id']}__{item_id[:8]}__{digest[:12]}{suffix}"
                (family_dir / name).write_bytes(blob)
                record = {
                    "gap_id": gap["gap_id"],
                    "candidate_id": candidate_id_for(gap["gap_id"], str(result.get("source") or "")),
                    "item_id": item_id,
                    "title": result.get("title"),
                    "creator": creator,
                    "license": result.get("license"),
                    "license_version": result.get("license_version"),
                    "license_url": result.get("license_url"),
                    "source": result.get("source"),
                    "foreign_landing_url": landing,
                    "file_url": file_url,
                    "width": result.get("width"),
                    "height": result.get("height"),
                    "fetched_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "sha256": digest,
                    "bytes": len(blob),
                    "file_name": name,
                    "rights_tier_expected": "R2/R3-family (per-item license recorded verbatim)",
                    "label_tier_at_ingest": "silver_raw",
                }
                records.append(record)
                seen_ids.add(item_id)
                seen_sha.add(digest)
            time.sleep(1.0)  # polite pacing
        with items_path.open("w", encoding="utf-8") as handle:
            for record in records:
                handle.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
        summary["gaps"].append({
            "gap_id": gap["gap_id"],
            "family": gap["family"],
            "quota": gap["quota"],
            "acquired": len(records),
            "skipped": skipped,
            "items_path": str(items_path),
        })
        print(f"{gap['gap_id']}: acquired {len(records)}/{gap['quota']} (skipped {skipped})")

    out = datasets / "acquisition-receipt-20260927.json"
    out.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("receipt:", out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
