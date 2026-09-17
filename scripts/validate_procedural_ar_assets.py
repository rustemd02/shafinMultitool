#!/usr/bin/env python3
"""Verify the selected authored AR source/notice/USDZ bytes; no legal or device verdict."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import struct
import sys
import zipfile

RECORD = "docs/implementation/provenance/procedural-ar-assets.json"
GENERATOR = "tools/release/generate_ar_assets.py"
NOTICE = "shafinMultitool/Resources/Legal/SETOS-Procedural-AR-Assets-NOTICE.txt"


class ValidationError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ValidationError(message)


def digest(value):
    require(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value), "Malformed SHA-256")
    return value


def read_bounded(root: Path, relative: str, maximum=4*1024*1024):
    require(isinstance(relative, str) and relative and "\\" not in relative, "Invalid relative path")
    path = PurePosixPath(relative)
    require(not path.is_absolute() and str(path) == relative and ".." not in path.parts, "Unsafe relative path")
    target = root.joinpath(*path.parts)
    current = root
    for part in path.parts:
        current = current / part
        require(not current.is_symlink(), "Symlink is not an admitted source: " + relative)
    require(target.is_file(), "Missing file: " + relative)
    size = target.stat().st_size
    require(0 < size <= maximum, "Invalid file size: " + relative)
    return target.read_bytes()


def checked_file(root, relative, expected, size=None):
    data = read_bounded(root, relative)
    require(hashlib.sha256(data).hexdigest() == digest(expected), "SHA mismatch: " + relative)
    if size is not None:
        require(type(size) is int and size > 0 and len(data) == size, "Size mismatch: " + relative)
    return data


def check_package(data, asset):
    member = asset["member"]
    require(isinstance(member, dict), "USD member must be an object")
    require(member.get("path") == asset["name"] + ".usdc", "Unexpected member name")
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            members = archive.infolist()
            require(len(members) == 1, "USDZ must contain exactly one generated layer")
            entry = members[0]
            require(entry.filename == member["path"], "USDZ member differs from record")
            require(entry.compress_type == zipfile.ZIP_STORED and entry.flag_bits == 0, "USDZ must be stored and unencrypted")
            require(entry.file_size == member.get("bytes") and 0 < entry.file_size <= 4*1024*1024, "Invalid member size")
            offset = entry.header_offset
            require(data[offset:offset+4] == b"PK\x03\x04", "Invalid ZIP local header")
            name_bytes, extra_bytes = struct.unpack_from("<HH", data, offset+26)
            require((offset+30+name_bytes+extra_bytes) % 64 == 0, "USDZ member is not 64-byte aligned")
            payload = archive.read(entry)
            require(payload.startswith(b"PXR-USDC"), "USDZ layer is not USDC")
            require(hashlib.sha256(payload).hexdigest() == digest(member.get("sha256")), "USDZ layer SHA mismatch")
    except (zipfile.BadZipFile, RuntimeError, struct.error) as error:
        raise ValidationError("Unreadable USDZ package: " + str(error)) from error


def validate(repo_root: Path, record_path: Path | None = None, app_root: Path | None = None):
    require(repo_root.is_dir() and not repo_root.is_symlink(), "Invalid repository root")
    record_path = record_path or repo_root / RECORD
    require(record_path.is_file() and not record_path.is_symlink(), "Missing provenance record")
    record = json.loads(record_path.read_text(encoding="utf-8"))
    require(isinstance(record, dict) and record.get("schema") == "set-os-procedural-ar-assets" and
            type(record.get("schema_version")) is int and record["schema_version"] == 1, "Unsupported record schema")
    require(record.get("third_party_meshes") is False and record.get("human_authorship_claimed") is False,
            "Authorship/import scope differs from admitted source")
    generator = record["generator"]
    require(generator.get("path") == GENERATOR, "Unexpected generator path")
    checked_file(repo_root, GENERATOR, generator.get("sha256"))
    notice = record["notice"]
    require(notice.get("source_path") == NOTICE and notice.get("bundle_path") == Path(NOTICE).name, "Unexpected notice path")
    checked_file(repo_root, NOTICE, notice.get("sha256"))
    assets = record["assets"]
    require(isinstance(assets, list) and len(assets) == 2, "Exactly Circle and Person are required")
    require(all(isinstance(row, dict) for row in assets), "Malformed asset row")
    require(sorted(row.get("name", "") for row in assets) == ["Circle", "Person"], "Duplicate or missing asset")
    if app_root is not None:
        require(app_root.is_dir() and not app_root.is_symlink(), "Invalid app root")
        checked_file(app_root, notice["bundle_path"], notice["sha256"])
    for asset in assets:
        name = asset["name"]
        require(asset.get("source_path") == "shafinMultitool/Resources/"+name+".usdz" and
                asset.get("bundle_path") == name+".usdz", "Unexpected asset path")
        require(type(asset.get("bytes")) is int and asset["bytes"] > 0, "Missing or invalid asset byte count")
        data = checked_file(repo_root, asset["source_path"], asset.get("sha256"), asset.get("bytes"))
        check_package(data, asset)
        if app_root is not None:
            checked_file(app_root, asset["bundle_path"], asset["sha256"], asset["bytes"])
    return {"assets": len(assets), "source_verified": True, "bundle_verified": app_root is not None,
            "scope": "Exact authored source/notice/package identity; legal, visual and physical AR gates remain separate"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", required=True, type=Path)
    parser.add_argument("--record", type=Path)
    parser.add_argument("--app", type=Path)
    args = parser.parse_args()
    try:
        result = validate(args.repo_root, args.record, args.app)
    except (ValidationError, OSError, ValueError, TypeError, KeyError, AttributeError) as error:
        print("FAIL AR ASSET PROVENANCE: " + str(error), file=sys.stderr)
        return 1
    print("PASS AR ASSET PROVENANCE: " + json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
