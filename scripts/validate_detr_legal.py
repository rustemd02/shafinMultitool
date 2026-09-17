#!/usr/bin/env python3
"""Verify the reviewed DETR legal record and exact source/bundle notices.

Read-only, offline and independent of legal/product/replacement admission.
"""
import argparse
import hashlib
import json
from pathlib import Path

PROVENANCE_PATH = "docs/implementation/provenance/detr-provenance.json"
PROVENANCE_SHA256 = "46189a3234a80f2a78f3db12fd6d6c8ecb1e344ef455eeb9601478ce1e61ccb0"
NOTICE_PINS = {
    "license": (
        "shafinMultitool/Resources/Legal/DETR-Apache-2.0-LICENSE.txt",
        "DETR-Apache-2.0-LICENSE.txt",
        "b208c52b00a2df2c8f4c3298c34407bf2bfe409968213372251c91fcc737a1a5",
    ),
    "attribution": (
        "shafinMultitool/Resources/Legal/DETR-NOTICE.txt",
        "DETR-NOTICE.txt",
        "f7f0a77cfb7d88e8a83e638d67d7a0e638699a3a7e6f811f1d19d8e317ead29a",
    ),
}


def checked_bytes(root, relative, expected):
    path = root / relative
    if (path.is_symlink() or not path.is_file()
            or not path.resolve().is_relative_to(root.resolve())):
        raise ValueError("DETR legal missing/unsafe file: " + relative)
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != expected:
        raise ValueError("DETR legal SHA256 mismatch: " + relative)
    return data


def validate(repo_root, app_root=None):
    record = json.loads(checked_bytes(repo_root, PROVENANCE_PATH, PROVENANCE_SHA256))
    if record.get("schema") != "setos-detr-source-and-notice-provenance-v1":
        raise ValueError("DETR legal provenance schema mismatch")
    if record.get("component_id") != "detr-segmentation-model":
        raise ValueError("DETR legal component mismatch")
    for field, (source_path, bundle_path, expected) in NOTICE_PINS.items():
        entry = record.get(field, {})
        if any(entry.get(key) != value for key, value in (
            ("source_path", source_path), ("bundle_path", bundle_path), ("sha256", expected)
        )):
            raise ValueError("DETR legal provenance notice mapping mismatch: " + field)
        checked_bytes(repo_root, source_path, expected)
        if app_root is not None:
            checked_bytes(app_root, bundle_path, expected)
    return len(NOTICE_PINS)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", required=True, type=Path)
    parser.add_argument("--app", type=Path)
    args = parser.parse_args()
    try:
        count = validate(args.repo_root, args.app)
    except (OSError, ValueError, TypeError) as error:
        print("FAIL DETR legal provenance: " + str(error))
        return 1
    scope = "source+bundle" if args.app is not None else "source"
    print(f"PASS DETR legal provenance: {scope} notices={count}; admission unchanged")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
