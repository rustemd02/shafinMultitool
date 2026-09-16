#!/usr/bin/env python3
"""Build a deterministic, research-only EVA silver manifest.

The input is an already acquired EVA data root.  This tool never downloads or
copies media.  It projects EVA's filtered preference/quality votes into robust
image-level reference metadata for auxiliary aesthetic/composition work; the
projection is not a Camera Coach action label and is not release-cleared.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import statistics
import stat
import sys
import tempfile
from typing import Any, Mapping, Sequence


ROOT = Path(__file__).resolve().parents[2]
SOURCE_ID = "eva_official"
SOURCE_REPOSITORY = "https://github.com/kang-gnak/eva-dataset"
SOURCE_COMMIT = "fb40a9f1abe4be96b69229aaac3d0838a2e1d31c"
SOURCE_MANIFEST_PATH = ROOT / "datasets/camera-coach/v1/sources/eva-fb40a9f1.json"
SCHEMA_ID = "camera-eva-silver-v1"
SCHEMA_VERSION = "1.0.0"
SILVER_MANIFEST = "silver-manifest.jsonl"
SILVER_RECEIPT = "receipts/eva-silver-receipt.json"
VOTE_FIELDS = ("score", "difficulty", "visual", "composition", "quality", "semantic")
VOTE_HEADER = (
    "image_id",
    "user_id",
    *VOTE_FIELDS,
    "vote_time",
    "1",
    "2",
    "3",
    "4",
)
CATEGORY_HEADER = ("image_id", "sort")
VALUE_RANGES = {
    "score": (0.0, 10.0),
    "difficulty": (1.0, 4.0),
    "visual": (1.0, 4.0),
    "composition": (1.0, 4.0),
    "quality": (1.0, 4.0),
    "semantic": (1.0, 4.0),
}
ID_RE = re.compile(r"^[^/\\\x00\r\n]+$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
SHA1_RE = re.compile(r"^[0-9a-f]{40}$")
MAD_CONFLICT_THRESHOLD = 0.25
STD_CONFLICT_THRESHOLD = 0.20


class EVASilverError(ValueError):
    """A fail-closed, user-facing source or manifest error."""


def _json_line(value: Any) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    )


def _reject_nonfinite(value: str) -> Any:
    raise EVASilverError(f"non-finite JSON number is not allowed: {value}")


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"), parse_constant=_reject_nonfinite)
    except EVASilverError:
        raise
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise EVASilverError(f"cannot read JSON: {path.name}") from exc


def _sha256_file(path: Path) -> str:
    try:
        info = path.lstat()
    except OSError as exc:
        raise EVASilverError(f"cannot inspect file: {path}") from exc
    if not stat.S_ISREG(info.st_mode):
        raise EVASilverError(f"not a regular file: {path}")
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            while chunk := stream.read(1024 * 1024):
                digest.update(chunk)
    except OSError as exc:
        raise EVASilverError(f"cannot read file: {path}") from exc
    return digest.hexdigest()


def _git_blob_sha1(path: Path) -> tuple[int, str]:
    """Return the size and Git blob SHA-1 for a pinned upstream object."""

    try:
        info = path.lstat()
    except OSError as exc:
        raise EVASilverError(f"cannot inspect file: {path}") from exc
    if not stat.S_ISREG(info.st_mode):
        raise EVASilverError(f"not a regular file: {path}")
    digest = hashlib.sha1(f"blob {info.st_size}\0".encode("ascii"))
    try:
        with path.open("rb") as stream:
            while chunk := stream.read(1024 * 1024):
                digest.update(chunk)
    except OSError as exc:
        raise EVASilverError(f"cannot read file: {path}") from exc
    return info.st_size, digest.hexdigest()


def _assert_no_symlink_components(path: Path) -> None:
    """Reject a path whose existing components contain a symlink."""

    absolute = Path(os.path.abspath(path))
    current = Path(absolute.anchor)
    for part in absolute.parts[1:]:
        current /= part
        try:
            info = current.lstat()
        except FileNotFoundError:
            break
        except OSError as exc:
            raise EVASilverError(f"cannot inspect path component: {current}") from exc
        if stat.S_ISLNK(info.st_mode):
            raise EVASilverError(f"path uses a symlink: {current}")


def _external_root(value: Path) -> Path:
    candidate = Path(value).expanduser()
    _assert_no_symlink_components(candidate)
    root = Path(os.path.abspath(candidate))
    repository = ROOT.resolve()
    try:
        resolved = root.resolve(strict=True)
    except OSError as exc:
        raise EVASilverError("data root must be an existing directory") from exc
    if resolved != root:
        raise EVASilverError("data root must not resolve through a symlink")
    if not root.is_dir():
        raise EVASilverError("data root must be a directory")
    if root == repository or repository in root.parents or root in repository.parents:
        raise EVASilverError("data root must be outside the repository and its ancestors")
    return root


def _safe_relative(root: Path, value: Any, *, label: str) -> tuple[Path, str]:
    if not isinstance(value, str) or not value or "\x00" in value:
        raise EVASilverError(f"{label} must be a non-empty relative path")
    normalized = value.replace("\\", "/")
    path = PurePosixPath(normalized)
    parts = path.parts
    if path.is_absolute() or not parts or any(part in ("", ".", "..") for part in parts):
        raise EVASilverError(f"{label} is not a safe relative path")
    if ":" in parts[0]:
        raise EVASilverError(f"{label} has a drive prefix")
    current = root
    for part in parts:
        current /= part
        try:
            info = current.lstat()
        except FileNotFoundError:
            continue
        except OSError as exc:
            raise EVASilverError(f"cannot inspect {label}") from exc
        if stat.S_ISLNK(info.st_mode):
            raise EVASilverError(f"{label} uses a symlink")
    candidate = root.joinpath(*parts)
    resolved = candidate.resolve(strict=False)
    if resolved != candidate:
        raise EVASilverError(f"{label} escapes data root")
    try:
        resolved.relative_to(root)
    except ValueError as exc:
        raise EVASilverError(f"{label} is outside data root") from exc
    return candidate, PurePosixPath(*parts).as_posix()


def _fixed_file(root: Path, relative: str) -> Path:
    path, _ = _safe_relative(root, relative, label=relative)
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise EVASilverError(f"{relative} is not a regular file")
    if not path.is_file():
        raise EVASilverError(f"required file is missing: {relative}")
    return path


def _load_pinned_metadata_specs(path: Path = SOURCE_MANIFEST_PATH) -> dict[str, dict[str, Any]]:
    """Read the committed source manifest's exact metadata pins."""

    try:
        _assert_no_symlink_components(path)
        if not path.is_file() or path.is_symlink():
            raise EVASilverError("pinned EVA source manifest is missing")
    except EVASilverError:
        raise
    except OSError as exc:
        raise EVASilverError("cannot inspect pinned EVA source manifest") from exc
    manifest = _read_json(path)
    if not isinstance(manifest, dict) or manifest.get("schema_id") != "camera-research-source-manifest-v1":
        raise EVASilverError("pinned EVA source manifest has an unexpected schema")
    if manifest.get("source_id") != SOURCE_ID or manifest.get("intake_tier") != "research_only":
        raise EVASilverError("pinned EVA source manifest has an unexpected source")
    authority = manifest.get("authority")
    if (
        not isinstance(authority, dict)
        or authority.get("repository") != SOURCE_REPOSITORY
        or authority.get("commit") != SOURCE_COMMIT
    ):
        raise EVASilverError("pinned EVA source manifest authority does not match EVA")
    metadata = manifest.get("metadata")
    if not isinstance(metadata, list):
        raise EVASilverError("pinned EVA source manifest metadata is not a list")
    specs: dict[str, dict[str, Any]] = {}
    for index, entry in enumerate(metadata, 1):
        if not isinstance(entry, dict):
            raise EVASilverError(f"pinned EVA metadata entry {index} is not an object")
        relative = entry.get("path")
        if not isinstance(relative, str) or not relative or relative in specs:
            raise EVASilverError(f"pinned EVA metadata entry {index} has an invalid or duplicate path")
        size = entry.get("size_bytes")
        blob_sha1 = entry.get("git_blob_sha1")
        if not isinstance(size, int) or isinstance(size, bool) or size < 1:
            raise EVASilverError(f"pinned EVA metadata entry {index} has an invalid size")
        if not isinstance(blob_sha1, str) or not SHA1_RE.fullmatch(blob_sha1):
            raise EVASilverError(f"pinned EVA metadata entry {index} has an invalid Git blob SHA-1")
        specs[relative] = {"path": relative, "size_bytes": size, "git_blob_sha1": blob_sha1}
    required = {"data/votes_filtered.csv", "data/image_content_category.csv"}
    missing = sorted(required - set(specs))
    if missing:
        raise EVASilverError(f"pinned EVA metadata is missing: {missing[0]}")
    return {relative: specs[relative] for relative in sorted(required)}


def _verify_pinned_metadata(root: Path, specs: Mapping[str, Mapping[str, Any]]) -> dict[str, dict[str, Any]]:
    """Verify source files against the exact size and Git blob pins."""

    verified: dict[str, dict[str, Any]] = {}
    for relative in ("data/votes_filtered.csv", "data/image_content_category.csv"):
        spec = specs.get(relative)
        if not isinstance(spec, Mapping):
            raise EVASilverError(f"no pinned metadata specification for {relative}")
        path = _fixed_file(root, relative)
        size, blob_sha1 = _git_blob_sha1(path)
        if size != spec.get("size_bytes") or blob_sha1 != spec.get("git_blob_sha1"):
            raise EVASilverError(f"metadata does not match pinned EVA object: {relative}")
        verified[relative] = {"path": relative, "size_bytes": size, "git_blob_sha1": blob_sha1}
    return verified


def _jsonl_rows(path: Path, *, label: str) -> list[dict[str, Any]]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as exc:
        raise EVASilverError(f"cannot read {label}") from exc
    if not lines:
        raise EVASilverError(f"{label} is empty")
    rows: list[dict[str, Any]] = []
    for line_number, line in enumerate(lines, 1):
        if not line.strip():
            raise EVASilverError(f"{label} has a blank line at {line_number}")
        try:
            value = json.loads(line, parse_constant=_reject_nonfinite)
        except EVASilverError:
            raise
        except (UnicodeError, json.JSONDecodeError) as exc:
            raise EVASilverError(f"{label} line {line_number} is malformed JSON") from exc
        if not isinstance(value, dict):
            raise EVASilverError(f"{label} line {line_number} must be an object")
        rows.append(value)
    return rows


def _validate_source_receipt(
    source_receipt_path: Path,
    inventory_digest: str,
) -> dict[str, Any]:
    receipt = _read_json(source_receipt_path)
    if not isinstance(receipt, dict):
        raise EVASilverError("EVA source receipt must be an object")
    expected = {
        "source_id": SOURCE_ID,
        "repository": SOURCE_REPOSITORY,
        "commit": SOURCE_COMMIT,
        "intake_tier": "research_only",
        "human_gold": False,
        "release_admissible": False,
        "underlying_ava_image_rights": "unresolved",
    }
    for key, value in expected.items():
        if receipt.get(key) != value:
            raise EVASilverError(f"source receipt {key} does not match pinned EVA source")
    inventory_receipt = receipt.get("inventory")
    if not isinstance(inventory_receipt, dict) or inventory_receipt.get("path") != "inventory.jsonl":
        raise EVASilverError("source receipt has no inventory attestation")
    digest = inventory_receipt.get("sha256")
    if not isinstance(digest, str) or not SHA256_RE.fullmatch(digest):
        raise EVASilverError("source receipt inventory digest is invalid")
    if digest != inventory_digest:
        raise EVASilverError("inventory digest does not match the source receipt")
    return receipt


def _capture_input_hashes(paths: Mapping[str, tuple[Path, str]]) -> dict[str, dict[str, str]]:
    captured: dict[str, dict[str, str]] = {}
    for key, (path, relative) in paths.items():
        captured[key] = {"path": relative, "sha256": _sha256_file(path)}
    return captured


def _assert_input_hashes_unchanged(
    paths: Mapping[str, tuple[Path, str]],
    captured: Mapping[str, Mapping[str, str]],
) -> None:
    for key, (path, _relative) in paths.items():
        expected = captured.get(key, {}).get("sha256")
        actual = _sha256_file(path)
        if expected != actual:
            raise EVASilverError(f"input changed during build: {key}")


def _validate_output_paths(root: Path, input_paths: Mapping[str, tuple[Path, str]]) -> tuple[Path, Path]:
    """Resolve both fixed outputs through the same lexical path guard."""

    manifest_path, _ = _safe_relative(root, SILVER_MANIFEST, label=SILVER_MANIFEST)
    receipt_path, _ = _safe_relative(root, SILVER_RECEIPT, label=SILVER_RECEIPT)
    if manifest_path == receipt_path:
        raise EVASilverError("silver manifest and receipt outputs must be distinct")
    input_files = {path for path, _relative in input_paths.values()}
    if manifest_path in input_files or receipt_path in input_files:
        raise EVASilverError("silver output collides with an input file")
    return manifest_path, receipt_path


def _validate_identifier(value: Any, *, field: str) -> str:
    if not isinstance(value, str) or not value or not ID_RE.fullmatch(value):
        raise EVASilverError(f"{field} must be a non-empty path-safe identifier")
    return value


def _validate_inventory(root: Path, path: Path) -> dict[str, dict[str, Any]]:
    rows = _jsonl_rows(path, label="inventory.jsonl")
    allowed = {
        "source_id",
        "source_record_id",
        "relative_path",
        "byte_count",
        "sha256",
        "width",
        "height",
        "format",
        "intake_tier",
        "human_gold",
        "release_admissible",
        "upstream_metadata",
    }
    by_id: dict[str, dict[str, Any]] = {}
    paths: set[str] = set()
    for index, row in enumerate(rows, 1):
        unknown = sorted(set(row) - allowed)
        if unknown:
            raise EVASilverError(f"inventory row {index} has unknown fields: {', '.join(unknown)}")
        image_id = _validate_identifier(row.get("source_record_id"), field=f"inventory row {index}.source_record_id")
        if image_id in by_id:
            raise EVASilverError(f"duplicate inventory image_id: {image_id}")
        if row.get("source_id") != SOURCE_ID:
            raise EVASilverError(f"inventory row {index} has an unexpected source_id")
        relative_path_value = row.get("relative_path")
        media_path, relative_path = _safe_relative(root, relative_path_value, label=f"inventory row {index}.relative_path")
        if relative_path in paths:
            raise EVASilverError(f"duplicate inventory relative_path: {relative_path}")
        if not media_path.is_file() or media_path.is_symlink():
            raise EVASilverError(f"inventory image is missing or not regular: {relative_path}")
        digest = row.get("sha256")
        if not isinstance(digest, str) or not SHA256_RE.fullmatch(digest):
            raise EVASilverError(f"inventory row {index}.sha256 is invalid")
        actual_digest = _sha256_file(media_path)
        if actual_digest != digest:
            raise EVASilverError(f"inventory image hash mismatch: {image_id}")
        byte_count = row.get("byte_count")
        if not isinstance(byte_count, int) or isinstance(byte_count, bool) or byte_count < 1:
            raise EVASilverError(f"inventory row {index}.byte_count is invalid")
        if media_path.stat().st_size != byte_count:
            raise EVASilverError(f"inventory image byte count mismatch: {image_id}")
        for field in ("width", "height"):
            value = row.get(field)
            if not isinstance(value, int) or isinstance(value, bool) or value < 1:
                raise EVASilverError(f"inventory row {index}.{field} is invalid")
        if not isinstance(row.get("format"), str) or not row["format"]:
            raise EVASilverError(f"inventory row {index}.format is invalid")
        if row.get("intake_tier") != "research_only" or row.get("human_gold") is not False or row.get("release_admissible") is not False:
            raise EVASilverError(f"inventory row {index} is not immutable research-only metadata")
        upstream = row.get("upstream_metadata")
        if upstream is not None and not isinstance(upstream, dict):
            raise EVASilverError(f"inventory row {index}.upstream_metadata must be an object")
        normalized = dict(row)
        normalized["source_record_id"] = image_id
        normalized["relative_path"] = relative_path
        by_id[image_id] = normalized
        paths.add(relative_path)
    if not by_id:
        raise EVASilverError("inventory contains no images")
    return by_id


def _csv_rows(path: Path, *, delimiter: str, expected_header: Sequence[str], encoding: str, label: str) -> list[list[str]]:
    rows: list[list[str]] = []
    try:
        with path.open("r", encoding=encoding, newline="") as stream:
            reader = csv.reader(stream, delimiter=delimiter)
            header = next(reader, None)
            if tuple(header or ()) != tuple(expected_header):
                raise EVASilverError(f"{label} header must be {'/'.join(expected_header)}")
            for line_number, row in enumerate(reader, 2):
                if len(row) != len(expected_header):
                    raise EVASilverError(f"{label} line {line_number} has {len(row)} fields, expected {len(expected_header)}")
                if any(value != value.strip() for value in row):
                    raise EVASilverError(f"{label} line {line_number} has surrounding whitespace")
                rows.append(row)
    except EVASilverError:
        raise
    except (OSError, UnicodeError, csv.Error) as exc:
        raise EVASilverError(f"cannot read {label}") from exc
    if not rows:
        raise EVASilverError(f"{label} contains no data rows")
    return rows


def _parse_categories(path: Path, inventory: Mapping[str, Mapping[str, Any]]) -> dict[str, int]:
    categories: dict[str, int] = {}
    for line_number, row in enumerate(
        _csv_rows(path, delimiter=",", expected_header=CATEGORY_HEADER, encoding="utf-8-sig", label="image_content_category.csv"),
        2,
    ):
        image_id = _validate_identifier(row[0], field=f"category row {line_number}.image_id")
        if image_id in categories:
            raise EVASilverError(f"duplicate category image_id: {image_id}")
        if image_id not in inventory:
            raise EVASilverError(f"category row references an image absent from inventory: {image_id}")
        try:
            category = int(row[1], 10)
        except ValueError as exc:
            raise EVASilverError(f"category row {line_number}.sort must be an integer") from exc
        if category < 1 or category > 6:
            raise EVASilverError(f"category row {line_number}.sort must be in 1..6")
        categories[image_id] = category
    missing = sorted(set(inventory) - set(categories))
    if missing:
        raise EVASilverError(f"inventory images missing content category: {missing[0]}")
    return categories


def _finite_number(text: str, *, field: str, line_number: int) -> float:
    try:
        value = float(text)
    except (TypeError, ValueError) as exc:
        raise EVASilverError(f"votes line {line_number}.{field} is not numeric") from exc
    if not math.isfinite(value):
        raise EVASilverError(f"votes line {line_number}.{field} is not finite")
    return value


def _parse_votes(path: Path, inventory: Mapping[str, Mapping[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    votes: dict[str, list[dict[str, Any]]] = {}
    seen_pairs: set[tuple[str, str]] = set()
    rows = _csv_rows(path, delimiter="=", expected_header=VOTE_HEADER, encoding="utf-8-sig", label="votes_filtered.csv")
    for line_number, row in enumerate(rows, 2):
        image_id = _validate_identifier(row[0], field=f"votes line {line_number}.image_id")
        user_id = _validate_identifier(row[1], field=f"votes line {line_number}.user_id")
        if image_id not in inventory:
            raise EVASilverError(f"vote row references an image absent from inventory: {image_id}")
        pair = (image_id, user_id)
        if pair in seen_pairs:
            raise EVASilverError(f"duplicate vote for image/user pair: {image_id}/{user_id}")
        seen_pairs.add(pair)
        parsed: dict[str, Any] = {"user_id": user_id}
        for index, field in enumerate(VOTE_FIELDS, 2):
            value = _finite_number(row[index], field=field, line_number=line_number)
            low, high = VALUE_RANGES[field]
            if value < low or value > high:
                raise EVASilverError(f"votes line {line_number}.{field} is outside {low}..{high}")
            parsed[field] = value
        vote_time = _finite_number(row[8], field="vote_time", line_number=line_number)
        if vote_time < 0:
            raise EVASilverError(f"votes line {line_number}.vote_time is negative")
        for index, value in enumerate(row[9:], 1):
            if value not in {"0", "1"}:
                raise EVASilverError(f"votes line {line_number}.{index} must be 0 or 1")
        votes.setdefault(image_id, []).append(parsed)
    if not votes:
        raise EVASilverError("votes_filtered.csv contains no usable image rows")
    return votes


def _rounded(value: float) -> float:
    rounded = round(float(value), 6)
    return 0.0 if rounded == 0 else rounded


def _aggregate(values: Sequence[float]) -> dict[str, float]:
    if not values:
        raise EVASilverError("cannot aggregate an empty vote set")
    median = statistics.median(values)
    mad = statistics.median([abs(value - median) for value in values])
    return {
        "mean": _rounded(statistics.fmean(values)),
        "median": _rounded(median),
        "std": _rounded(statistics.pstdev(values)),
        "mad": _rounded(mad),
    }


def _uncertainty(aggregates: Mapping[str, Mapping[str, float]]) -> dict[str, Any]:
    normalized_mad: dict[str, float] = {}
    normalized_std: dict[str, float] = {}
    conflict_dimensions: list[str] = []
    for field in VOTE_FIELDS:
        low, high = VALUE_RANGES[field]
        span = high - low
        mad = aggregates[field]["mad"] / span
        std = aggregates[field]["std"] / span
        normalized_mad[field] = _rounded(mad)
        normalized_std[field] = _rounded(std)
        if mad >= MAD_CONFLICT_THRESHOLD or std >= STD_CONFLICT_THRESHOLD:
            conflict_dimensions.append(field)
    max_mad = max(normalized_mad.values())
    max_std = max(normalized_std.values())
    return {
        "max_normalized_mad": max_mad,
        "max_normalized_std": max_std,
        "conflict": bool(conflict_dimensions),
        "conflict_dimensions": conflict_dimensions,
    }


def _silver_rows(
    inventory: Mapping[str, Mapping[str, Any]],
    categories: Mapping[str, int],
    votes: Mapping[str, Sequence[Mapping[str, Any]]],
) -> tuple[list[dict[str, Any]], dict[str, int]]:
    rows: list[dict[str, Any]] = []
    for image_id in sorted(votes):
        image = inventory.get(image_id)
        if image is None or image_id not in categories:
            raise EVASilverError(f"silver join is missing referential metadata: {image_id}")
        image_votes = votes[image_id]
        if not image_votes:
            raise EVASilverError(f"silver join contains an empty vote set: {image_id}")
        aggregates = {
            field: _aggregate([float(vote[field]) for vote in image_votes])
            for field in VOTE_FIELDS
        }
        unique_voters = {str(vote["user_id"]) for vote in image_votes}
        rows.append(
            {
                "schema_id": SCHEMA_ID,
                "schema_version": SCHEMA_VERSION,
                "dataset_kind": "auxiliary_aesthetic_composition",
                "image_id": image_id,
                "relative_path": image["relative_path"],
                "image_sha256": image["sha256"],
                "provenance": {
                    "source_id": SOURCE_ID,
                    "repository": SOURCE_REPOSITORY,
                    "commit": SOURCE_COMMIT,
                    "source_metadata": "data/votes_filtered.csv+data/image_content_category.csv",
                },
                "content_category": categories[image_id],
                "counts": {
                    "votes": len(image_votes),
                    "unique_voters": len(unique_voters),
                },
                "aggregates": aggregates,
                "uncertainty": _uncertainty(aggregates),
                "label_boundary": "silver_reference_only_not_camera_coach_action_label",
                "intake_tier": "research_only",
                "human_gold": False,
                "release_admissible": False,
            }
        )
    if not rows:
        raise EVASilverError("no image has both a valid category and a valid vote set")
    return rows, {"inventory_records": len(inventory), "silver_records": len(rows), "inventory_without_votes": len(inventory) - len(rows)}


def _atomic_write_text(path: Path, text: str) -> str:
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise EVASilverError(f"output is not a regular file: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary: Path | None = None
    try:
        fd, name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
        temporary = Path(name)
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        try:
            directory_fd = os.open(path.parent, os.O_RDONLY)
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
        except OSError:
            pass
    except (OSError, ValueError) as exc:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
        raise EVASilverError(f"cannot atomically write {path.name}") from exc
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _write_outputs(
    manifest_path: Path,
    receipt_path: Path,
    rows: Sequence[Mapping[str, Any]],
    receipt: Mapping[str, Any],
) -> tuple[str, str]:
    manifest_text = "".join(_json_line(dict(row)) + "\n" for row in rows)
    manifest_digest = _atomic_write_text(manifest_path, manifest_text)
    receipt_payload = dict(receipt)
    output = dict(receipt_payload.get("output", {}))
    output.update({"path": SILVER_MANIFEST, "sha256": manifest_digest, "records": len(rows)})
    receipt_payload["output"] = output
    receipt_text = _json_line(receipt_payload) + "\n"
    receipt_digest = _atomic_write_text(receipt_path, receipt_text)
    return manifest_digest, receipt_digest


def build(data_root: Path, *, source_manifest_path: Path = SOURCE_MANIFEST_PATH) -> tuple[int, str, str]:
    root = _external_root(data_root)
    inventory_path = _fixed_file(root, "inventory.jsonl")
    source_receipt_path = _fixed_file(root, "receipts/eva-source-receipt.json")
    category_path = _fixed_file(root, "data/image_content_category.csv")
    vote_path = _fixed_file(root, "data/votes_filtered.csv")
    input_paths = {
        "source_manifest": (source_manifest_path, "datasets/camera-coach/v1/sources/eva-fb40a9f1.json"),
        "source_receipt": (source_receipt_path, "receipts/eva-source-receipt.json"),
        "inventory": (inventory_path, "inventory.jsonl"),
        "votes_filtered": (vote_path, "data/votes_filtered.csv"),
        "image_content_category": (category_path, "data/image_content_category.csv"),
    }
    manifest_path, receipt_path = _validate_output_paths(root, input_paths)
    captured = _capture_input_hashes(input_paths)
    pinned_specs = _load_pinned_metadata_specs(source_manifest_path)
    verified_pins = _verify_pinned_metadata(root, pinned_specs)
    source_receipt = _validate_source_receipt(source_receipt_path, captured["inventory"]["sha256"])
    inventory = _validate_inventory(root, inventory_path)
    categories = _parse_categories(category_path, inventory)
    votes = _parse_votes(vote_path, inventory)
    rows, coverage = _silver_rows(inventory, categories, votes)
    _assert_input_hashes_unchanged(input_paths, captured)
    category_only = len(set(categories) - set(votes))
    receipt: dict[str, Any] = {
        "schema_id": "camera-eva-silver-receipt-v1",
        "schema_version": SCHEMA_VERSION,
        "source": {
            "source_id": SOURCE_ID,
            "repository": SOURCE_REPOSITORY,
            "commit": SOURCE_COMMIT,
            "source_receipt": "receipts/eva-source-receipt.json",
            "source_manifest": "datasets/camera-coach/v1/sources/eva-fb40a9f1.json",
        },
        "inputs": {
            "source_manifest": captured["source_manifest"],
            "source_receipt": captured["source_receipt"],
            "inventory": {**captured["inventory"], "records": len(inventory)},
            "votes_filtered": {**captured["votes_filtered"], "rows": sum(len(value) for value in votes.values()), "image_ids": len(votes)},
            "image_content_category": {**captured["image_content_category"], "rows": len(categories)},
        },
        "pinned_metadata": {
            relative: {"size_bytes": spec["size_bytes"], "git_blob_sha1": spec["git_blob_sha1"]}
            for relative, spec in verified_pins.items()
        },
        "aggregation": {
            "dimensions": list(VOTE_FIELDS),
            "statistics": ["mean", "median", "std_population", "mad"],
            "mad_definition": "median absolute deviation from the dimension median",
            "normalization": "MAD and population std divided by the documented dimension range",
            "conflict_thresholds": {"normalized_mad": MAD_CONFLICT_THRESHOLD, "normalized_std": STD_CONFLICT_THRESHOLD},
            "upstream_scale": {
                "score": "0=lowest, 10=highest general score",
                "difficulty": "1=very difficult, 2=difficult, 3=easy, 4=very easy",
                "visual": "1=very bad, 2=bad, 3=good, 4=very good",
                "composition": "1=very bad, 2=bad, 3=good, 4=very good",
                "quality": "1=very bad, 2=bad, 3=good, 4=very good",
                "semantic": "1=very bad, 2=bad, 3=good, 4=very good",
            },
        },
        "coverage": {
            **coverage,
            "category_records": len(categories),
            "voted_image_ids": len(votes),
            "category_only_excluded": category_only,
            "unknown_vote_image_rows": 0,
            "unknown_category_image_rows": 0,
        },
        "unknown_upstream_rows": {"policy": "fail_closed", "votes": 0, "categories": 0},
        "colab_export": {
            "format": "jsonl",
            "manifest_path": SILVER_MANIFEST,
            "image_root": ".",
            "join_key": "image_id",
            "image_path_field": "relative_path",
            "label_fields": [f"aggregates.{field}.mean" for field in VOTE_FIELDS] + ["content_category"],
            "upstream_scale": {
                "score": {"min": 0, "max": 10, "meaning": "general score"},
                "difficulty": {"min": 1, "max": 4, "meaning": "1=very difficult; 4=very easy"},
                "attributes": {"min": 1, "max": 4, "meaning": "1=very bad; 4=very good", "fields": ["visual", "composition", "quality", "semantic"]},
            },
            "split": "not_assigned",
            "split_warning": "Do not train/evaluate across shared source or derivative families; this projection does not assign Camera Coach splits.",
        },
        "label_boundary": "research_only_silver_reference_not_camera_coach_action_label",
        "intake_tier": "research_only",
        "human_gold": False,
        "release_admissible": False,
    }
    # Rehash immediately before output and retain the admission hashes in the
    # receipt. A concurrent source mutation must never produce a mixed batch.
    _assert_input_hashes_unchanged(input_paths, captured)
    manifest_digest, receipt_digest = _write_outputs(manifest_path, receipt_path, rows, receipt)
    return len(rows), manifest_digest, receipt_digest


def _fixture_receipt(inventory_digest: str) -> dict[str, Any]:
    return {
        "source_id": SOURCE_ID,
        "repository": SOURCE_REPOSITORY,
        "commit": SOURCE_COMMIT,
        "intake_tier": "research_only",
        "human_gold": False,
        "release_admissible": False,
        "underlying_ava_image_rights": "unresolved",
        "inventory": {"path": "inventory.jsonl", "sha256": inventory_digest},
    }


def _fixture_source_manifest(root: Path, path: Path) -> None:
    metadata: list[dict[str, Any]] = []
    for relative in ("data/votes_filtered.csv", "data/image_content_category.csv"):
        size, blob_sha1 = _git_blob_sha1(root / relative)
        metadata.append({"path": relative, "size_bytes": size, "git_blob_sha1": blob_sha1})
    path.write_text(
        _json_line(
            {
                "schema_id": "camera-research-source-manifest-v1",
                "manifest_version": "1.0.0",
                "source_id": SOURCE_ID,
                "source_kind": "aesthetic_quality_reference",
                "authority": {"repository": SOURCE_REPOSITORY, "commit": SOURCE_COMMIT},
                "intake_tier": "research_only",
                "metadata": metadata,
            }
        )
        + "\n",
        encoding="utf-8",
    )


def _self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="eva-silver-") as temp_dir:
        # macOS exposes /var as a system symlink; hand the validator its
        # canonical temporary path so the test exercises data-root guards
        # rather than the host's conventional alias.
        root = Path(temp_dir).resolve() / "eva"
        images = root / "images"
        data = root / "data"
        receipts = root / "receipts"
        images.mkdir(parents=True)
        data.mkdir()
        receipts.mkdir()
        image_rows: list[dict[str, Any]] = []
        for image_id, payload in (("2", b"two-image"), ("10", b"ten-image"), ("30", b"thirty-image")):
            path = images / f"{image_id}.jpg"
            path.write_bytes(payload)
            image_rows.append(
                {
                    "source_id": SOURCE_ID,
                    "source_record_id": image_id,
                    "relative_path": f"images/{image_id}.jpg",
                    "byte_count": len(payload),
                    "sha256": hashlib.sha256(payload).hexdigest(),
                    "width": 2,
                    "height": 2,
                    "format": "jpeg",
                    "intake_tier": "research_only",
                    "human_gold": False,
                    "release_admissible": False,
                }
            )
        inventory_text = "".join(_json_line(row) + "\n" for row in image_rows)
        (root / "inventory.jsonl").write_text(inventory_text, encoding="utf-8")
        (receipts / "eva-source-receipt.json").write_text(
            _json_line(_fixture_receipt(hashlib.sha256(inventory_text.encode("utf-8")).hexdigest())) + "\n",
            encoding="utf-8",
        )
        (data / "image_content_category.csv").write_text(
            "\ufeffimage_id,sort\n2,5\n10,1\n30,6\n",
            encoding="utf-8",
        )
        (data / "votes_filtered.csv").write_text(
            "=".join(VOTE_HEADER)
            + "\n"
            + "2=u1=8=2=3=4=3=4=1=1=0=0=0\n"
            + "2=u2=4=3=2=2=3=2=2=0=0=1=0\n"
            + "10=u3=6=2=3=3=3=3=3=0=0=0=1\n",
            encoding="utf-8",
        )
        fixture_source_manifest = root / "fixture-source-manifest.json"
        _fixture_source_manifest(root, fixture_source_manifest)
        count, first_digest, _ = build(root, source_manifest_path=fixture_source_manifest)
        assert count == 2
        output = root / SILVER_MANIFEST
        output_text = output.read_text(encoding="utf-8")
        output_rows = [json.loads(line) for line in output_text.splitlines()]
        assert [row["image_id"] for row in output_rows] == ["10", "2"]
        assert output_rows[1]["aggregates"]["score"] == {"mean": 6.0, "median": 6.0, "std": 2.0, "mad": 2.0}
        assert output_rows[1]["uncertainty"]["conflict"] is True
        assert output_rows[0]["counts"] == {"unique_voters": 1, "votes": 1}
        assert all(row["human_gold"] is False and row["release_admissible"] is False for row in output_rows)
        before = output.read_bytes()
        count2, second_digest, _ = build(root, source_manifest_path=fixture_source_manifest)
        assert count2 == count and second_digest == first_digest and output.read_bytes() == before
        assert not list(root.glob(".*.tmp")) and not list(receipts.glob(".*.tmp"))

        # The admission hash fence detects a source mutation before output.
        probe_paths = {"category": (data / "image_content_category.csv", "data/image_content_category.csv")}
        probe_hashes = _capture_input_hashes(probe_paths)
        category_path = data / "image_content_category.csv"
        original_categories = category_path.read_text(encoding="utf-8")
        category_path.write_text(original_categories + "", encoding="utf-8")
        _assert_input_hashes_unchanged(probe_paths, probe_hashes)
        category_path.write_text(original_categories.replace("2,5", "2,4", 1), encoding="utf-8")
        try:
            _assert_input_hashes_unchanged(probe_paths, probe_hashes)
        except EVASilverError as exc:
            assert "changed during build" in str(exc)
        else:
            raise AssertionError("changed input hash was not detected")
        category_path.write_text(original_categories, encoding="utf-8")

        # Unknown upstream references fail closed before replacing the prior output.
        votes_path = data / "votes_filtered.csv"
        original_votes = votes_path.read_text(encoding="utf-8")
        votes_path.write_text(original_votes + "unknown=u9=5=2=2=2=2=2=1=0=0=0=0\n", encoding="utf-8")
        _fixture_source_manifest(root, fixture_source_manifest)
        try:
            build(root, source_manifest_path=fixture_source_manifest)
        except EVASilverError as exc:
            assert "absent from inventory" in str(exc)
        else:
            raise AssertionError("unknown vote image was accepted")
        assert output.read_bytes() == before
        votes_path.write_text(original_votes, encoding="utf-8")
        _fixture_source_manifest(root, fixture_source_manifest)

        # A same-schema, same-sized metadata substitution is rejected by the
        # committed-style Git blob pin before CSV parsing can accept it.
        original_categories = category_path.read_text(encoding="utf-8")
        category_path.write_text(original_categories.replace("2,5", "2,4", 1), encoding="utf-8")
        try:
            build(root, source_manifest_path=fixture_source_manifest)
        except EVASilverError as exc:
            assert "pinned EVA object" in str(exc)
        else:
            raise AssertionError("same-schema substituted category metadata was accepted")
        category_path.write_text(original_categories, encoding="utf-8")

        # A lexical symlink in the media path is rejected even when it resolves in-root.
        linked = images / "linked.jpg"
        linked.symlink_to(images / "2.jpg")
        bad_inventory = list(image_rows)
        bad_inventory.append({**image_rows[0], "source_record_id": "linked", "relative_path": "images/linked.jpg"})
        bad_text = "".join(_json_line(row) + "\n" for row in bad_inventory)
        (root / "inventory.jsonl").write_text(bad_text, encoding="utf-8")
        (receipts / "eva-source-receipt.json").write_text(
            _json_line(_fixture_receipt(hashlib.sha256(bad_text.encode("utf-8")).hexdigest())) + "\n",
            encoding="utf-8",
        )
        try:
            build(root, source_manifest_path=fixture_source_manifest)
        except EVASilverError as exc:
            assert "symlink" in str(exc)
        else:
            raise AssertionError("symlinked media was accepted")

        (root / "inventory.jsonl").write_text(inventory_text, encoding="utf-8")
        (receipts / "eva-source-receipt.json").write_text(
            _json_line(_fixture_receipt(hashlib.sha256(inventory_text.encode("utf-8")).hexdigest())) + "\n",
            encoding="utf-8",
        )

        # Both output targets are guarded before any atomic replacement.
        manifest_sentinel = root.parent / "manifest-sentinel"
        manifest_sentinel.write_text("untouched\n", encoding="utf-8")
        output.unlink()
        output.symlink_to(manifest_sentinel)
        try:
            build(root, source_manifest_path=fixture_source_manifest)
        except EVASilverError as exc:
            assert "symlink" in str(exc)
        else:
            raise AssertionError("symlinked manifest output was accepted")
        assert manifest_sentinel.read_text(encoding="utf-8") == "untouched\n"
        output.unlink()

        # The receipt output shares this fixed directory with the source
        # attestation; a symlink must not redirect a write to an outside
        # sentinel.
        outside_receipts = root.parent / "outside-receipts"
        outside_receipts.mkdir()
        sentinel = outside_receipts / "sentinel"
        sentinel.write_text("untouched\n", encoding="utf-8")
        receipts_real = root / "receipts-real"
        receipts.rename(receipts_real)
        (root / "receipts").symlink_to(outside_receipts, target_is_directory=True)
        try:
            build(root, source_manifest_path=fixture_source_manifest)
        except EVASilverError as exc:
            assert "symlink" in str(exc)
        else:
            raise AssertionError("symlinked receipts directory was accepted")
        assert sentinel.read_text(encoding="utf-8") == "untouched\n"
    print("PASS build_eva_silver self-test deterministic_sort robust_stats uncertainty_conflict category_join unknown_reference_fail_closed symlink_guard receipts_symlink_guard atomic_outputs research_only_boundary")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", help="run the synthetic, network-free self-test")
    parser.add_argument("--data-root", type=Path, help="external EVA data root (no downloads are performed)")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.self_test:
            _self_test()
            return 0
        if args.data_root is None:
            _parser().error("--data-root is required unless --self-test is used")
        records, manifest_digest, receipt_digest = build(args.data_root)
        print(f"PASS build-eva-silver source_id={SOURCE_ID} records={records} manifest_sha256={manifest_digest} receipt_sha256={receipt_digest}")
        return 0
    except EVASilverError as exc:
        print(f"FAIL {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
