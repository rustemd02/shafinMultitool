#!/usr/bin/env python3
"""Acquire the official AADB release into an external, research-only root.

This adapter is deliberately fail-closed.  The repository commit and Drive
file IDs are fixed below and are also recorded in ``aadb-v1.json``.  A
bootstrap computes archive pins but never extracts or admits media; ``--fetch``
will not run until every exact archive size and SHA-256 is present in that
tracked source specification.  Raw media, upstream labels, and archives stay
outside Git.
"""

from __future__ import annotations

import argparse
import csv
import contextlib
import filecmp
import hashlib
import io
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import tarfile
import urllib.parse
import zipfile
import zlib
from typing import Any, Callable, Iterable, Mapping, Sequence


ROOT = Path(__file__).resolve().parents[2]
INTAKE_SCRIPT = ROOT / "tools" / "dataset" / "camera_source_intake.py"
SPEC_PATH = ROOT / "datasets" / "camera-coach" / "v1" / "sources" / "aadb-v1.json"
SOURCE_ID = "aadb_official"
SOURCE_REPOSITORY = "https://github.com/aimerykong/deepImageAestheticsAnalysis"
SOURCE_COMMIT = "a962a1d8c313cdbec97e51381187ffbaac469b28"
GITHUB_RAW = f"https://raw.githubusercontent.com/aimerykong/deepImageAestheticsAnalysis/{SOURCE_COMMIT}"

TRAIN_FILE_ID = "1Viswtzb77vqqaaICAQz9iuZ8OEYCu6-_"
TEST_FILE_ID = "115qnIQ-9pl5Vt06RyFue3b6DabakATmJ"
LABEL_FILE_ID = "0BxeylfSgpk1MZ0hWWkoxb2hMU3c"
WARP256_FILE_ID = "0BxeylfSgpk1MU2RsVXo3bEJWM2c"

ARCHIVE_URLS = {
    "train": f"https://drive.usercontent.google.com/download?id={TRAIN_FILE_ID}&export=download&confirm=t",
    "test": f"https://drive.usercontent.google.com/download?id={TEST_FILE_ID}&export=download&confirm=t",
    "labels": f"https://drive.usercontent.google.com/download?id={LABEL_FILE_ID}&export=download&confirm=t",
    "warp256": f"https://drive.usercontent.google.com/download?id={WARP256_FILE_ID}&export=download&confirm=t&resourcekey=0-ld4H3VhRKKiSUOklGnF1Uw",
}
ARCHIVE_NAMES = {
    "train": "datasetImages_originalSize.zip",
    "test": "AADB_newtest_originalSize.zip",
    "labels": "imgListFiles_label.zip",
}
ARCHIVE_FILE_IDS = {
    "train": TRAIN_FILE_ID,
    "test": TEST_FILE_ID,
    "labels": LABEL_FILE_ID,
}
METADATA_PINS = {
    "AADBinfo.mat": (179433, "307e6b84666f3901ac7c56d3fc058859634517cc8f11acc0db8865ab22d4b567"),
    "AADBstatistics.m": (2062, "3a3efab0e712f26c836127c286206ab5e4d5b238cd16134b81dd103bbef63f40"),
    "README.md": (2782, "17ead50a334644fd9ae4a8da46fa8116ab106726e7b4d8dc59793d102625e099"),
}
WARP256_SIZE = 138076608
WARP256_SHA256 = "a31adc66fd47396cabcb581e66fa3e72b38814d6957b22bc3e2edab9e77126d2"
COMPACT_MATCHED_IMAGES = 9458
COMPACT_EXCLUDED_LEGACY_EXTRAS = 500

ATTRIBUTE_SPECS: tuple[tuple[str, str], ...] = (
    ("interesting_content", "Content"),
    ("object_emphasis", "Object"),
    ("lighting", "Light"),
    ("color_harmony", "ColorHarmony"),
    ("vivid_color", "VividColor"),
    ("shallow_dof", "DoF"),
    ("motion_blur", "MotionBlur"),
    ("rule_of_thirds", "RuleOfThirds"),
    ("balancing_element", "BalacingElements"),  # spelling in the release
    ("repetition", "Repetition"),
    ("symmetry", "Symmetry"),
)
ATTRIBUTE_NAMES = {source_name for _, source_name in ATTRIBUTE_SPECS}
IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png"}
LABEL_SUFFIXES = {".txt", ".csv", ".mat", ".m"}
RAW_MANIFEST_FIELDS = ["image_id", "path"]
MAX_DOWNLOAD_ATTEMPTS = 12
MAX_ARCHIVE_MEMBERS = 200_000
MAX_MEMBER_BYTES = 4_000_000_000
MAX_ARCHIVE_BYTES = 8_000_000_000
MAX_COMPRESSION_RATIO = 1_000
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
TEST_SCORE_PREFIX = re.compile(r"^\d\.\d{3}_")
ALLOWED_HOSTS = {"drive.usercontent.google.com", "drive.google.com", "raw.githubusercontent.com"}
HTML_PREFIXES = (b"<!doctype", b"<html", b"<head", b"<body", b"<?xml")


class AADBError(ValueError):
    """User-facing fail-closed acquisition error."""


def _json_line(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def _jsonl_bytes(rows: Iterable[Mapping[str, Any]]) -> bytes:
    return b"".join((_json_line(dict(row)) + "\n").encode("utf-8") for row in rows)


def _sha256_file(path: Path) -> str:
    try:
        info = path.lstat()
    except OSError as exc:
        raise AADBError(f"cannot inspect {path.name}") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise AADBError(f"{path.name} is not a regular file")
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            while chunk := stream.read(1024 * 1024):
                digest.update(chunk)
    except OSError as exc:
        raise AADBError(f"cannot read {path.name}") from exc
    return digest.hexdigest()


def _size_hash(path: Path) -> tuple[int, str]:
    try:
        info = path.lstat()
    except OSError as exc:
        raise AADBError(f"cannot inspect {path.name}") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise AADBError(f"{path.name} is not a regular file")
    return info.st_size, _sha256_file(path)


def _external_root(value: Path, *, create: bool = True) -> Path:
    original = Path(value).expanduser()
    if original.is_symlink():
        raise AADBError("data root must not be a symlink")
    root = original.resolve()
    repository = ROOT.resolve()
    if root == repository or repository in root.parents or root in repository.parents:
        raise AADBError("data root must be outside the repository and its ancestors")
    if create:
        try:
            root.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            raise AADBError("cannot create external data root") from exc
    if root.is_symlink() or not root.is_dir():
        raise AADBError("data root must be a directory")
    return root


def _safe_relative(root: Path, value: str) -> Path:
    if not isinstance(value, str) or not value or "\x00" in value:
        raise AADBError("path must be a non-empty string")
    normalized = value.replace("\\", "/")
    parts = PurePosixPath(normalized).parts
    if not parts or PurePosixPath(normalized).is_absolute() or any(part in ("", ".", "..") for part in parts):
        raise AADBError(f"unsafe path: {value!r}")
    if ":" in parts[0]:
        raise AADBError(f"drive-prefixed path: {value!r}")
    current = root
    for part in parts[:-1]:
        current /= part
        if current.is_symlink():
            raise AADBError("path uses a symlink parent")
    return root.joinpath(*parts)


def _ensure_directory(path: Path) -> Path:
    missing: list[Path] = []
    current = Path(path)
    while True:
        try:
            info = current.lstat()
        except FileNotFoundError:
            missing.append(current)
            if current.parent == current:
                raise AADBError(f"cannot find directory parent: {path}")
            current = current.parent
            continue
        except OSError as exc:
            raise AADBError(f"cannot inspect directory: {path}") from exc
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
            raise AADBError(f"directory path is unsafe: {current}")
        break
    for directory in reversed(missing):
        try:
            directory.mkdir()
            info = directory.lstat()
        except OSError as exc:
            raise AADBError(f"cannot create directory: {directory}") from exc
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
            raise AADBError(f"created directory is unsafe: {directory}")
    return Path(path)


def _fixed_directory(root: Path, relative: str, *, create: bool = False, allow_missing: bool = False) -> Path:
    path = _safe_relative(root, relative)
    if path.is_symlink():
        raise AADBError(f"fixed directory is a symlink: {relative}")
    if not path.exists():
        if create:
            return _ensure_directory(path)
        if allow_missing:
            return path
        raise AADBError(f"fixed directory is missing: {relative}")
    try:
        info = path.lstat()
    except OSError as exc:
        raise AADBError(f"cannot inspect fixed directory: {relative}") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
        raise AADBError(f"fixed directory is not a directory: {relative}")
    return path


def _fixed_file(root: Path, relative: str, *, create_parent: bool = False) -> Path:
    path = _safe_relative(root, relative)
    parent = PurePosixPath(relative.replace("\\", "/")).parent
    if str(parent) not in ("", "."):
        _fixed_directory(root, parent.as_posix(), create=create_parent)
    if path.is_symlink():
        raise AADBError(f"fixed file is a symlink: {relative}")
    if path.exists() and not path.is_file():
        raise AADBError(f"fixed file is not regular: {relative}")
    return path


def _safe_external_file(value: Path) -> Path:
    path = Path(value).expanduser()
    if path.is_symlink():
        raise AADBError("bootstrap pin receipt is a symlink")
    resolved = path.resolve()
    repository = ROOT.resolve()
    if resolved == repository or repository in resolved.parents or resolved in repository.parents:
        raise AADBError("bootstrap pin receipt must be outside the repository")
    current = resolved.parent
    while current != current.parent:
        if current.is_symlink():
            raise AADBError("bootstrap path uses a symlink parent")
        current = current.parent
    if resolved.is_symlink():
        raise AADBError("bootstrap pin receipt is a symlink")
    if resolved.exists() and not resolved.is_file():
        raise AADBError("bootstrap pin receipt is not a regular file")
    _ensure_directory(resolved.parent)
    return resolved


def _atomic_write_bytes(path: Path, payload: bytes) -> None:
    _ensure_directory(path.parent)
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise AADBError(f"refusing unsafe output: {path}")
    temporary: Path | None = None
    try:
        fd, name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
        temporary = Path(name)
        with os.fdopen(fd, "wb") as stream:
            stream.write(payload)
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
    except Exception as exc:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
        if isinstance(exc, AADBError):
            raise
        raise AADBError(f"cannot atomically write {path.name}") from exc


def _atomic_write_jsonl(path: Path, rows: Iterable[Mapping[str, Any]]) -> str:
    payload = _jsonl_bytes(rows)
    _atomic_write_bytes(path, payload)
    return hashlib.sha256(payload).hexdigest()


def _atomic_write_json(path: Path, value: Mapping[str, Any]) -> None:
    _atomic_write_bytes(path, (_json_line(value) + "\n").encode("utf-8"))


def _assert_url(url: str, *, expected: str | None = None) -> None:
    if expected is not None and url != expected:
        raise AADBError("source URL does not match the pinned source specification")
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or parsed.hostname not in ALLOWED_HOSTS or parsed.username or parsed.password:
        raise AADBError(f"unapproved download host or scheme: {url}")
    if parsed.fragment:
        raise AADBError("download URL must not contain a fragment")


def _header_blocks(path: Path) -> list[dict[str, str]]:
    if not path.exists() or path.is_symlink() or not path.is_file():
        return []
    blocks: list[dict[str, str]] = []
    current: dict[str, str] = {}
    try:
        lines = path.read_text(encoding="iso-8859-1").splitlines()
    except OSError:
        return []
    for line in lines:
        if not line.strip():
            if current:
                blocks.append(current)
                current = {}
            continue
        if line.startswith("HTTP/"):
            if current:
                blocks.append(current)
            current = {":status": line}
            continue
        if ":" in line:
            key, value = line.split(":", 1)
            current[key.strip().lower()] = value.strip()
    if current:
        blocks.append(current)
    return blocks


def _response_status(stdout: str) -> tuple[str | None, int | None]:
    effective: str | None = None
    status: int | None = None
    for line in (stdout or "").splitlines():
        if line.startswith("AADB_EFFECTIVE_URL:"):
            effective = line.partition(":")[2].strip()
        elif line.startswith("AADB_STATUS:"):
            try:
                status = int(line.partition(":")[2].strip())
            except ValueError:
                status = None
    return effective, status


def _read_prefix(path: Path, limit: int, *, error: str) -> bytes:
    """Read at most ``limit`` bytes from a verified regular file."""

    if not isinstance(limit, int) or isinstance(limit, bool) or limit < 1:
        raise AADBError(error)
    try:
        info = path.lstat()
    except OSError as exc:
        raise AADBError(error) from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise AADBError(error)
    try:
        with path.open("rb") as stream:
            return stream.read(limit)
    except OSError as exc:
        raise AADBError(error) from exc


def _looks_like_html(path: Path) -> bool:
    prefix = _read_prefix(path, 512, error=f"cannot inspect downloaded payload {path.name}").lstrip().lower()
    return any(prefix.startswith(marker) for marker in HTML_PREFIXES) or b"google sign-in" in prefix


def _payload_kind_ok(path: Path, kind: str) -> None:
    if _looks_like_html(path):
        raise AADBError(f"downloaded {kind} payload is HTML/interstitial, not the archive or file")
    prefix = _read_prefix(path, 8, error=f"cannot read downloaded {kind} payload")
    if kind in {"archive", "image_archive", "label_archive"} and not prefix.startswith(b"PK"):
        raise AADBError(f"downloaded {kind} payload is not a ZIP archive")
    if kind == "mat" and not (prefix.startswith(b"MATLAB") or prefix[:2] == b"\x1f\x8b"):
        raise AADBError("downloaded MAT metadata has an unexpected signature")


def _partial_is_safe(part: Path, expected_size: int | None, max_size: int = MAX_ARCHIVE_BYTES) -> int:
    if part.is_symlink():
        raise AADBError(f"partial download is a symlink: {part.name}")
    if not part.exists():
        return 0
    try:
        info = part.lstat()
    except OSError as exc:
        raise AADBError(f"cannot inspect partial download: {part.name}") from exc
    if not stat.S_ISREG(info.st_mode):
        raise AADBError(f"partial download is not regular: {part.name}")
    if info.st_size > max_size:
        raise AADBError(f"partial download exceeds safety limit: {part.name}")
    if expected_size is not None and info.st_size > expected_size:
        part.unlink()
        return 0
    return info.st_size


def _assert_safe_header_path(path: Path) -> None:
    """Reject a curl header sidecar unless it is an ordinary regular file."""

    try:
        info = path.lstat()
    except FileNotFoundError:
        return
    except OSError as exc:
        raise AADBError(f"cannot inspect response header path: {path.name}") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise AADBError(f"unsafe response header path: {path.name}")


def _download(
    spec: Mapping[str, Any],
    destination: Path,
    runner: Callable[..., Any] = subprocess.run,
    *,
    kind: str = "archive",
) -> Path:
    """Download one pinned or bootstrap asset with offset-preserving retries."""

    url = spec.get("url")
    _assert_url(url if isinstance(url, str) else "")
    _ensure_directory(destination.parent)
    if destination.is_symlink():
        raise AADBError(f"destination is a symlink: {destination.name}")
    expected_size = spec.get("size_bytes")
    if expected_size is not None and (not isinstance(expected_size, int) or isinstance(expected_size, bool) or expected_size < 1):
        raise AADBError(f"invalid expected size for {destination.name}")
    expected_hash = spec.get("sha256")
    if expected_hash is not None and (not isinstance(expected_hash, str) or not SHA256_RE.fullmatch(expected_hash)):
        raise AADBError(f"invalid expected SHA-256 for {destination.name}")
    max_size = spec.get("max_size_bytes", MAX_ARCHIVE_BYTES)
    if not isinstance(max_size, int) or isinstance(max_size, bool) or max_size < 1 or max_size > MAX_ARCHIVE_BYTES:
        raise AADBError(f"invalid maximum size for {destination.name}")
    part = Path(f"{destination}.part")
    header_path = Path(f"{part}.headers")
    # Inspect the sidecar with lstat before any unlink or curl operation.  In
    # particular, Path.exists() misses dangling symlinks and would otherwise
    # let curl follow/replace an attacker-controlled header path.
    _assert_safe_header_path(header_path)

    def complete(path: Path) -> bool:
        if not path.exists() or path.is_symlink() or not path.is_file():
            return False
        size, digest = _size_hash(path)
        if size > max_size:
            return False
        if expected_size is not None and size != expected_size:
            return False
        if expected_hash is not None and digest != expected_hash:
            return False
        _payload_kind_ok(path, kind)
        return True

    if destination.exists():
        if complete(destination):
            return destination
        if destination.is_symlink() or not destination.is_file():
            raise AADBError(f"unsafe existing destination: {destination.name}")
        destination.unlink()
    _partial_is_safe(part, expected_size, max_size)
    if part.exists() and expected_size is not None and expected_hash and part.stat().st_size == expected_size:
        if _sha256_file(part) == expected_hash:
            _payload_kind_ok(part, kind)
            os.replace(part, destination)
            Path(f"{part}.headers").unlink(missing_ok=True)
            return destination
        # A same-sized stale/corrupt partial cannot be resumed safely.
        part.unlink()
    command = [
        "curl", "--fail", "--silent", "--show-error", "--location",
        "--proto", "=https", "--proto-redir", "=https", "--continue-at", "-",
        "--max-filesize", str(MAX_ARCHIVE_BYTES),
        "--dump-header", str(header_path),
        "--write-out", "\\nAADB_EFFECTIVE_URL:%{url_effective}\\nAADB_STATUS:%{http_code}\\n",
        "--output", str(part), url,
    ]
    for attempt in range(MAX_DOWNLOAD_ATTEMPTS):
        offset = _partial_is_safe(part, expected_size, max_size)
        _assert_safe_header_path(header_path)
        try:
            try:
                result = runner(command, check=True, capture_output=True, text=True)
            except TypeError:
                result = runner(command, check=True)
        except (OSError, subprocess.CalledProcessError) as exc:
            if part.exists():
                _partial_is_safe(part, expected_size, max_size)
            if attempt + 1 == MAX_DOWNLOAD_ATTEMPTS:
                raise AADBError(f"curl failed for {url} after {MAX_DOWNLOAD_ATTEMPTS} attempts") from exc
            continue
        stdout = getattr(result, "stdout", "") or ""
        effective, status = _response_status(stdout)
        if effective:
            _assert_url(effective)
        blocks = _header_blocks(header_path)
        response_metadata: dict[str, str | int | None] = {"effective_url": effective, "status": status, "content_type": None, "content_disposition": None}
        if blocks:
            final = blocks[-1]
            content_type = final.get("content-type", "").lower()
            response_metadata["content_type"] = content_type or None
            response_metadata["content_disposition"] = final.get("content-disposition")
            if "text/html" in content_type or "text/plain" in content_type and kind in {"archive", "image_archive", "label_archive"}:
                raise AADBError(f"downloaded {kind} response has an unsafe content type: {content_type}")
        if isinstance(spec, dict):
            spec["_response_metadata"] = response_metadata
        # If a server ignores a resume request and returns 200, never append
        # that body to an existing partial; retry once from byte zero.
        if offset and status == 200:
            part.unlink(missing_ok=True)
            header_path.unlink(missing_ok=True)
            continue
        if complete(part):
            os.replace(part, destination)
            header_path.unlink(missing_ok=True)
            return destination
        if expected_size is not None and expected_hash and part.exists() and part.stat().st_size == expected_size:
            if _sha256_file(part) != expected_hash:
                # A same-sized wrong payload must never be retried by appending
                # at EOF; restart the known partial from byte zero.
                part.unlink()
        _partial_is_safe(part, expected_size, max_size)
        if attempt + 1 == MAX_DOWNLOAD_ATTEMPTS:
            raise AADBError(f"download verification failed for {destination.name}")
    raise AADBError(f"download failed for {destination.name}")


def _member_parts(name: str) -> tuple[str, ...]:
    if not isinstance(name, str) or not name or "\x00" in name:
        raise AADBError("archive member has an unsafe name")
    normalized = name.replace("\\", "/")
    path = PurePosixPath(normalized)
    parts = path.parts
    if path.is_absolute() or not parts or any(part in ("", ".", "..") for part in parts) or ":" in parts[0]:
        raise AADBError(f"archive member escapes staging: {name!r}")
    return parts


def _is_zip_symlink(info: zipfile.ZipInfo) -> bool:
    mode = (info.external_attr >> 16) & 0xFFFF
    return stat.S_ISLNK(mode)


def _inspect_zip(path: Path, *, kind: str) -> list[zipfile.ZipInfo]:
    try:
        with zipfile.ZipFile(path, "r") as archive:
            infos = archive.infolist()
            if len(infos) > MAX_ARCHIVE_MEMBERS:
                raise AADBError("ZIP member-count guard exceeded")
            total = 0
            seen: set[str] = set()
            for info in infos:
                parts = _member_parts(info.filename)
                if _is_zip_symlink(info):
                    raise AADBError(f"ZIP symlink member is not allowed: {info.filename}")
                if info.is_dir():
                    continue
                if info.file_size < 0 or info.file_size > MAX_MEMBER_BYTES:
                    raise AADBError("ZIP member-size guard exceeded")
                if info.compress_size and info.file_size > 1_000_000 and info.file_size / info.compress_size > MAX_COMPRESSION_RATIO:
                    raise AADBError(f"ZIP compression-ratio guard exceeded: {info.filename}")
                total += info.file_size
                if total > MAX_ARCHIVE_BYTES:
                    raise AADBError("ZIP uncompressed-size guard exceeded")
                suffix = Path(parts[-1]).suffix.lower()
                allowed = IMAGE_SUFFIXES if kind == "images" else LABEL_SUFFIXES
                if suffix not in allowed:
                    raise AADBError(f"unexpected {kind} ZIP member: {info.filename}")
                normalized = PurePosixPath(*parts).as_posix()
                if normalized in seen:
                    raise AADBError(f"duplicate ZIP member: {normalized}")
                seen.add(normalized)
            bad = archive.testzip()
            if bad is not None:
                raise AADBError(f"ZIP CRC check failed: {bad}")
            return infos
    except AADBError:
        raise
    except (OSError, zipfile.BadZipFile, RuntimeError) as exc:
        raise AADBError("file is not a valid ZIP archive") from exc


def _strip_prefix(parts: Sequence[str], kind: str) -> tuple[str, ...]:
    prefixes = (
        ("datasetImages_originalSize",),
        ("AADB", "datasetImages_originalSize"),
        ("AADB_newtest_originalSize",),
        ("AADB", "AADB_newtest_originalSize"),
        ("AADB_train_originalSize",),
        ("datasetImages_warp256",),
        ("AADB", "datasetImages_warp256"),
    ) if kind == "images" else (
        ("imgListFiles_label",),
        ("AADB", "imgListFiles_label"),
    )
    for prefix in prefixes:
        if tuple(parts[: len(prefix)]) == prefix:
            parts = parts[len(prefix):]
            break
    if not parts:
        raise AADBError("archive member has no relative output path")
    return tuple(parts)


def _extract_zip(path: Path, stage: Path, *, kind: str) -> list[str]:
    infos = _inspect_zip(path, kind=kind)
    _ensure_directory(stage)
    extracted: list[str] = []
    try:
        with zipfile.ZipFile(path, "r") as archive:
            for info in infos:
                if info.is_dir():
                    continue
                relative = PurePosixPath(*_strip_prefix(_member_parts(info.filename), kind)).as_posix()
                destination = _safe_relative(stage, relative)
                _ensure_directory(destination.parent)
                if destination.exists() or destination.is_symlink():
                    raise AADBError(f"duplicate extracted path: {relative}")
                with archive.open(info, "r") as source, destination.open("xb") as target:
                    copied = 0
                    while chunk := source.read(1024 * 1024):
                        copied += len(chunk)
                        if copied > MAX_MEMBER_BYTES:
                            raise AADBError("extracted member-size guard exceeded")
                        target.write(chunk)
                    target.flush()
                    os.fsync(target.fileno())
                extracted.append(relative)
    except AADBError:
        raise
    except (OSError, zipfile.BadZipFile, RuntimeError) as exc:
        raise AADBError("cannot safely extract ZIP archive") from exc
    return sorted(extracted)


def _inspect_tar(path: Path, *, kind: str) -> list[tarfile.TarInfo]:
    try:
        with tarfile.open(path, "r:*") as archive:
            members = archive.getmembers()
            if len(members) > MAX_ARCHIVE_MEMBERS:
                raise AADBError("TAR member-count guard exceeded")
            total = 0
            seen: set[str] = set()
            for member in members:
                parts = _member_parts(member.name)
                if member.issym() or member.islnk() or not (member.isfile() or member.isdir()):
                    raise AADBError(f"TAR link/device member is not allowed: {member.name}")
                if member.isdir():
                    continue
                if member.size < 0 or member.size > MAX_MEMBER_BYTES:
                    raise AADBError("TAR member-size guard exceeded")
                total += member.size
                if total > MAX_ARCHIVE_BYTES:
                    raise AADBError("TAR uncompressed-size guard exceeded")
                suffix = Path(parts[-1]).suffix.lower()
                allowed = IMAGE_SUFFIXES if kind == "images" else LABEL_SUFFIXES
                if suffix not in allowed:
                    raise AADBError(f"unexpected {kind} TAR member: {member.name}")
                normalized = PurePosixPath(*parts).as_posix()
                if normalized in seen:
                    raise AADBError(f"duplicate TAR member: {normalized}")
                seen.add(normalized)
            return members
    except AADBError:
        raise
    except (OSError, tarfile.TarError) as exc:
        raise AADBError("file is not a valid TAR archive") from exc


def _promote_tree(stage: Path, target: Path) -> None:
    if stage.is_symlink() or not stage.is_dir():
        raise AADBError("extraction staging directory is unsafe")
    if target.is_symlink():
        raise AADBError("destination directory is a symlink")
    if not target.exists():
        _ensure_directory(target.parent)
        os.replace(stage, target)
        return
    if not target.is_dir():
        raise AADBError("destination is not a directory")
    staged_files: list[Path] = []
    for current in stage.rglob("*"):
        if current.is_symlink():
            raise AADBError("extraction staging contains a symlink")
        if current.is_file():
            staged_files.append(current)
        elif not current.is_dir():
            raise AADBError("extraction staging contains a non-regular entry")
    staged_files.sort(key=lambda p: p.as_posix())
    staged_relative = {p.relative_to(stage) for p in staged_files}
    existing_files: set[Path] = set()
    for current in target.rglob("*"):
        if current.is_symlink():
            raise AADBError("destination contains a symlink")
        if current.is_file():
            existing_files.add(current.relative_to(target))
        elif not current.is_dir():
            raise AADBError("destination contains a non-regular entry")
    unexpected = existing_files - staged_relative
    if unexpected:
        raise AADBError(f"unattested existing file in destination: {sorted(unexpected)[0]}")
    for source in staged_files:
        relative = source.relative_to(stage)
        destination = target / relative
        _ensure_directory(destination.parent)
        if destination.exists():
            if destination.is_symlink() or not destination.is_file() or not filecmp.cmp(source, destination, shallow=False):
                raise AADBError(f"conflicting existing file: {relative.as_posix()}")
        else:
            os.replace(source, destination)


def _normalize_name(value: str) -> str:
    normalized = value.replace("\\", "/")
    path = PurePosixPath(normalized)
    if path.is_absolute() or ".." in path.parts or "\x00" in value or not path.parts:
        raise AADBError(f"AADB image reference has an unsafe path: {value!r}")
    text = path.name
    return TEST_SCORE_PREFIX.sub("", text)


def _image_rows(root: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    seen_names: set[tuple[str, str]] = set()
    images_root = _fixed_directory(root, "images")
    for child in images_root.iterdir():
        if child.is_symlink() or not child.is_dir() or child.name not in {"train", "test"}:
            raise AADBError(f"image tree contains an unexpected split: {child.name}")
    for split in ("train", "test"):
        directory = _fixed_directory(root, f"images/{split}")
        for path in sorted(directory.rglob("*"), key=lambda p: p.as_posix()):
            if path.is_symlink():
                raise AADBError(f"image tree contains a symlink: {path}")
            if path.is_dir():
                continue
            if not path.is_file() or path.suffix.lower() not in IMAGE_SUFFIXES:
                raise AADBError(f"image tree contains an unexpected file: {path}")
            name = _normalize_name(path.name)
            key = (split, name)
            if key in seen_names:
                raise AADBError(f"duplicate normalized image name: {split}/{name}")
            seen_names.add(key)
            rows.append({"image_id": f"{split}:{name}", "path": path.relative_to(root).as_posix()})
    if not rows:
        raise AADBError("image tree contains no images")
    return sorted(rows, key=lambda row: row["image_id"])


def _parse_mat_elements(data: bytes, *, endian: str, start: int = 128) -> list[tuple[int, bytes]]:
    elements: list[tuple[int, bytes]] = []
    offset = start
    while offset + 8 <= len(data):
        first, second = struct.unpack_from(endian + "II", data, offset)
        if first == 0 and second == 0:
            break
        # Small data element format packs type and byte count into one uint32.
        if first >> 16 and (first & 0xFFFF) <= 15 and (first >> 16) <= 4:
            dtype, count = first & 0xFFFF, first >> 16
            payload = data[offset + 4:offset + 4 + count]
            offset += 8
        else:
            dtype, count = first, second
            end = offset + 8 + count
            if end > len(data):
                raise AADBError("MAT element exceeds file")
            payload = data[offset + 8:end]
            # MATLAB's miCOMPRESSED top-level elements are commonly packed
            # back-to-back without the usual eight-byte payload padding (the
            # pinned AADBinfo.mat does exactly this). Other v5 elements use
            # the normal alignment rule.
            offset = end if dtype == 15 else end + ((-count) % 8)
        elements.append((dtype, payload))
    return elements


def _mat_scalar_values(dtype: int, payload: bytes, *, endian: str) -> list[Any]:
    formats = {
        1: ("B", 1), 2: ("b", 1), 3: ("h", 2), 4: ("H", 2),
        5: ("i", 4), 6: ("I", 4), 7: ("f", 4), 9: ("d", 8),
    }
    if dtype not in formats:
        return []
    fmt, size = formats[dtype]
    if len(payload) % size:
        raise AADBError("MAT numeric payload is truncated")
    return [item[0] for item in struct.iter_unpack(endian + fmt, payload)]


def _mat_value(payload: bytes, *, endian: str) -> Any:
    elements = _parse_mat_elements(payload, endian=endian, start=0)
    if not elements or elements[0][0] != 6:
        raise AADBError("MAT matrix flags are missing")
    flags = _mat_scalar_values(elements[0][0], elements[0][1], endian=endian)
    if not flags:
        raise AADBError("MAT matrix class is missing")
    matrix_class = int(flags[0]) & 0xFF
    if len(elements) < 4:
        raise AADBError("MAT matrix fields are incomplete")
    if matrix_class == 1:  # cell array
        # Cell payloads are a sequence of miMATRIX elements directly after
        # the name tag.  AADBinfo.mat uses this form (there is no enclosing
        # data tag); accepting only matrix cells avoids silently dropping
        # malformed entries.
        cell_elements = elements[3:]
        return [_mat_value(item_payload, endian=endian) for item_type, item_payload in cell_elements if item_type == 14]
    data_type, data_payload = elements[3]
    if matrix_class == 4:  # character array
        if data_type == 16:  # miUTF8, used by the official AADBinfo.mat
            try:
                return data_payload.decode("utf-8")
            except UnicodeDecodeError as exc:
                raise AADBError("MAT UTF-8 character payload is invalid") from exc
        if data_type == 17:  # miUTF16
            try:
                return data_payload.decode("utf-16-le" if endian == "<" else "utf-16-be")
            except UnicodeDecodeError as exc:
                raise AADBError("MAT UTF-16 character payload is invalid") from exc
        if data_type == 18:  # miUTF32
            try:
                return data_payload.decode("utf-32-le" if endian == "<" else "utf-32-be")
            except UnicodeDecodeError as exc:
                raise AADBError("MAT UTF-32 character payload is invalid") from exc
        values = _mat_scalar_values(data_type, data_payload, endian=endian)
        return "".join(chr(int(value)) for value in values)
    values = _mat_scalar_values(data_type, data_payload, endian=endian)
    if matrix_class in (6, 7, 8, 9, 10, 11, 12, 13):
        return values
    raise AADBError(f"unsupported MAT matrix class: {matrix_class}")


def _read_mat(path: Path) -> dict[str, Any]:
    try:
        data = path.read_bytes()
    except OSError as exc:
        raise AADBError("cannot read AADBinfo.mat") from exc
    if len(data) < 128 or not data.startswith(b"MATLAB"):
        raise AADBError("AADBinfo.mat is not a MATLAB level-5 file")
    endian = "<" if data[126:128] == b"IM" else ">" if data[126:128] == b"MI" else ""
    if not endian:
        raise AADBError("MAT endian marker is invalid")
    result: dict[str, Any] = {}
    for dtype, payload in _parse_mat_elements(data, endian=endian):
        if dtype == 15:
            try:
                payload = zlib.decompress(payload)
            except zlib.error as exc:
                raise AADBError("MAT compressed element is invalid") from exc
            nested = _parse_mat_elements(payload, endian=endian, start=0)
            if not nested or nested[0][0] != 14:
                raise AADBError("MAT compressed payload is not a matrix")
            matrix_payload = nested[0][1]
        elif dtype == 14:
            matrix_payload = payload
        else:
            continue
        fields = _parse_mat_elements(matrix_payload, endian=endian, start=0)
        if len(fields) < 4:
            raise AADBError("MAT matrix is incomplete")
        name_type, name_payload = fields[2]
        if name_type == 1:
            name = name_payload.decode("utf-8", errors="strict")
        elif name_type == 4:
            name = "".join(chr(value) for value in _mat_scalar_values(name_type, name_payload, endian=endian))
        else:
            name = name_payload.decode("latin-1")
        result[name] = _mat_value(matrix_payload, endian=endian)
    required = {"trainNameList", "trainScore", "testNameList", "testScore"}
    if set(result) & required != required:
        raise AADBError("AADBinfo.mat lacks one or more required variables")
    return result


def _as_names(value: Any) -> list[str]:
    if not isinstance(value, list):
        raise AADBError("AADBinfo name list is not a cell array")
    result: list[str] = []
    for item in value:
        if not isinstance(item, str) or not item.strip():
            raise AADBError("AADBinfo contains an invalid image name")
        result.append(_normalize_name(item.strip()))
    return result


def _as_scores(value: Any) -> list[float]:
    if not isinstance(value, list):
        raise AADBError("AADBinfo score list is not numeric")
    result: list[float] = []
    for item in value:
        try:
            number = float(item)
        except (TypeError, ValueError) as exc:
            raise AADBError("AADBinfo contains a non-numeric score") from exc
        if not math.isfinite(number):
            raise AADBError("AADBinfo contains a non-finite score")
        result.append(number)
    return result


def _load_info(path: Path, *, expected_counts: Mapping[str, int] | None = None) -> dict[str, dict[str, float]]:
    values = _read_mat(path)
    output: dict[str, dict[str, float]] = {}
    for split in ("train", "test"):
        names = _as_names(values[f"{split}NameList"])
        scores = _as_scores(values[f"{split}Score"])
        if len(names) != len(scores) or not names:
            raise AADBError(f"AADBinfo {split} names/scores are not linked")
        if expected_counts is not None and len(names) != expected_counts.get(split):
            raise AADBError(f"AADBinfo {split} count differs from the pinned release count")
        mapping: dict[str, float] = {}
        for name, score in zip(names, scores):
            if name in mapping:
                raise AADBError(f"duplicate AADBinfo image name: {split}/{name}")
            mapping[name] = score
        output[split] = mapping
    return output


def _parse_label_file(path: Path) -> dict[str, tuple[float, list[str]]]:
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise AADBError(f"cannot read label file {path.name}") from exc
    rows: dict[str, tuple[float, list[str]]] = {}
    for line_number, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith("%"):
            continue
        if "," in line or "\t" in line:
            cells = next(csv.reader([line], delimiter="," if "," in line else "\t"))
        else:
            cells = line.split()
        cells = [cell.strip().strip('"') for cell in cells]
        if len(cells) < 2:
            raise AADBError(f"malformed label row {path.name}:{line_number}")
        try:
            number = float(cells[1])
        except ValueError as exc:
            # A header is acceptable only when it is unambiguously textual.
            if not rows and cells[0].lower() in {"image", "filename", "name", "image_name"}:
                continue
            raise AADBError(f"non-numeric label row {path.name}:{line_number}") from exc
        if not math.isfinite(number):
            raise AADBError(f"non-finite label row {path.name}:{line_number}")
        name = _normalize_name(cells[0])
        if name in rows:
            raise AADBError(f"duplicate label name in {path.name}: {name}")
        rows[name] = (number, cells[2:])
    if not rows:
        raise AADBError(f"label file is empty: {path.name}")
    return rows


def _label_files(labels_root: Path) -> dict[tuple[str, str], Path]:
    found: dict[tuple[str, str], Path] = {}
    train_pattern = re.compile(r"^imgListTrainRegression_(.+)\.txt$", re.IGNORECASE)
    test_pattern = re.compile(r"^imgListTestNewRegression_(.+)\.txt$", re.IGNORECASE)
    for path in sorted(labels_root.rglob("*"), key=lambda p: p.as_posix()):
        if path.is_symlink():
            raise AADBError("labels tree contains a symlink")
        if not path.is_file():
            continue
        match = train_pattern.match(path.name)
        split = "train"
        if not match:
            match = test_pattern.match(path.name)
            split = "test"
        if not match or match.group(1) not in ATTRIBUTE_NAMES:
            continue
        key = (split, match.group(1))
        if key in found:
            raise AADBError(f"duplicate selected label file: {path.name}")
        found[key] = path
    missing = [(split, name) for split in ("train", "test") for name in sorted(ATTRIBUTE_NAMES) if (split, name) not in found]
    if missing:
        raise AADBError(f"missing selected AADB label files: {missing[0][0]}/{missing[0][1]}")
    return found


def _load_labels(root: Path, info: Mapping[str, Mapping[str, float]]) -> dict[tuple[str, str], dict[str, tuple[float, list[str]]]]:
    files = _label_files(root)
    loaded: dict[tuple[str, str], dict[str, tuple[float, list[str]]]] = {}
    for key, path in files.items():
        labels = _parse_label_file(path)
        expected = set(info[key[0]])
        actual = set(labels)
        if actual != expected:
            missing = sorted(expected - actual)
            unknown = sorted(actual - expected)
            raise AADBError(f"label linkage mismatch {path.name}: missing={missing[:1]} unknown={unknown[:1]}")
        loaded[key] = labels
    return loaded


def _silver_rows(root: Path, *, info_path: Path, labels_root: Path, expected_counts: Mapping[str, int] | None = None) -> list[dict[str, Any]]:
    info = _load_info(info_path, expected_counts=expected_counts)
    rows = _image_rows(root)
    images = {(row["image_id"].split(":", 1)[0], _normalize_name(row["image_id"].split(":", 1)[1])): row for row in rows}
    expected_images = {(split, name) for split in info for name in info[split]}
    if set(images) != expected_images:
        missing = sorted(expected_images - set(images))
        unknown = sorted(set(images) - expected_images)
        raise AADBError(f"media/AADBinfo linkage mismatch: missing={missing[:1]} unknown={unknown[:1]}")
    labels = _load_labels(labels_root, info)
    output: list[dict[str, Any]] = []
    for split in ("train", "test"):
        for name, overall in sorted(info[split].items()):
            key = (split, name)
            if key not in images:
                raise AADBError(f"AADBinfo image is missing from media: {split}/{name}")
            attrs: dict[str, float] = {}
            uncertainty: dict[str, list[str]] = {}
            for canonical, source_name in ATTRIBUTE_SPECS:
                number, extras = labels[(split, source_name)][name]
                attrs[canonical] = number
                if extras:
                    uncertainty[canonical] = extras
            source_image_name = PurePosixPath(images[key]["path"]).name
            row: dict[str, Any] = {
                "source_id": SOURCE_ID,
                "source_record_id": f"{split}:{name}",
                "relative_path": images[key]["path"],
                "split": split,
                "source_image_name": source_image_name,
                "normalized_image_name": name,
                "overall_score": overall,
                "attributes": attrs,
                "attribute_source_names": {canonical: source_name for canonical, source_name in ATTRIBUTE_SPECS},
                "research_only": True,
                "human_gold": False,
                "release_admissible": False,
                "model_redistribution_cleared": False,
                "label_boundary": "auxiliary_aesthetic_attributes_only",
            }
            if uncertainty:
                row["original_rater_or_uncertainty_fields"] = uncertainty
            output.append(row)
    expected_ids = {f"{split}:{name}" for split in info for name in info[split]}
    actual_ids = {row["source_record_id"] for row in output}
    if expected_ids != actual_ids:
        raise AADBError("silver linkage has unknown or missing image references")
    return sorted(output, key=lambda row: row["source_record_id"])


def _run_intake(root: Path, manifest: Path, output: Path) -> None:
    command = [sys.executable, str(INTAKE_SCRIPT), "verify-local", "--source-id", SOURCE_ID, "--data-root", str(root), "--manifest", str(manifest), "--output", str(output)]
    try:
        result = subprocess.run(command, check=True, capture_output=True, text=True)
    except (OSError, subprocess.CalledProcessError) as exc:
        detail = getattr(exc, "stderr", "")
        raise AADBError(f"camera_source_intake verify-local failed: {detail[-400:]}") from exc
    if not result.stdout.startswith("PASS verify-local"):
        raise AADBError("camera_source_intake returned an unexpected result")


def _spec_hash(spec_path: Path = SPEC_PATH) -> str:
    return _sha256_file(spec_path)


def _tool_hash() -> str:
    return _sha256_file(Path(__file__).resolve())


def _validate_spec(spec: Mapping[str, Any], *, fixture: bool = False) -> None:
    if spec.get("schema_id") != "camera-aadb-source-spec-v1" or spec.get("source_id") != SOURCE_ID:
        raise AADBError("AADB source specification identity is invalid")
    authority = spec.get("authority")
    if not isinstance(authority, Mapping) or authority.get("repository") != SOURCE_REPOSITORY or authority.get("commit") != SOURCE_COMMIT:
        raise AADBError("AADB repository commit is not the fixed official pin")
    boundary = spec.get("research_boundary")
    expected_boundary = {
        "research_only": True,
        "human_gold": False,
        "release_admissible": False,
        "model_redistribution_cleared": False,
        "label_boundary": "auxiliary_aesthetic_attributes_only",
    }
    if not isinstance(boundary, Mapping) or any(boundary.get(key) != value for key, value in expected_boundary.items()):
        raise AADBError("AADB research-only boundary is missing or weakened")
    archives = spec.get("archives")
    if not isinstance(archives, list) or len(archives) != 3:
        raise AADBError("AADB source specification archive set is invalid")
    archive_ids: list[str] = []
    for item in archives:
        if not isinstance(item, Mapping):
            raise AADBError("AADB archive entry is invalid")
        archive_id = item.get("id")
        if not isinstance(archive_id, str) or archive_id not in ARCHIVE_URLS:
            raise AADBError(f"AADB archive URL is not pinned: {archive_id}")
        archive_ids.append(archive_id)
        if item.get("url") != ARCHIVE_URLS[archive_id] or item.get("filename") != ARCHIVE_NAMES[archive_id]:
            raise AADBError(f"AADB archive URL is not pinned: {archive_id}")
        _assert_url(item["url"])
        if item.get("file_id") != ARCHIVE_FILE_IDS[archive_id]:
            raise AADBError(f"AADB Drive file ID is not fixed: {archive_id}")
    if set(archive_ids) != {"train", "test", "labels"}:
        raise AADBError("AADB source specification archive set is invalid")
    metadata = spec.get("metadata")
    if not isinstance(metadata, list) or len(metadata) != 3:
        raise AADBError("AADB metadata set is invalid")
    metadata_paths: list[str] = []
    for item in metadata:
        if not isinstance(item, Mapping):
            raise AADBError("AADB metadata entry is invalid")
        metadata_path = item.get("path")
        if not isinstance(metadata_path, str) or metadata_path not in METADATA_PINS or item.get("url") != f"{GITHUB_RAW}/{metadata_path}":
            raise AADBError("AADB metadata URL is not pinned to the official commit")
        metadata_paths.append(metadata_path)
        _assert_url(item["url"])
        expected_size, expected_hash = METADATA_PINS[metadata_path]
        if not fixture and (item.get("size_bytes") != expected_size or item.get("sha256") != expected_hash):
            raise AADBError(f"AADB metadata pin is invalid: {metadata_path}")
    if set(metadata_paths) != {"AADBinfo.mat", "AADBstatistics.m", "README.md"}:
        raise AADBError("AADB metadata set is invalid")
    counts = spec.get("expected_counts")
    if not isinstance(counts, Mapping) or counts.get("train") != 8458 or counts.get("test") != 1000 or counts.get("warp256_reference") != COMPACT_MATCHED_IMAGES + COMPACT_EXCLUDED_LEGACY_EXTRAS:
        if not fixture:
            raise AADBError("AADB expected train/test counts are not pinned")
    references = spec.get("reference_archives")
    if not isinstance(references, list) or len(references) != 1 or not isinstance(references[0], Mapping):
        if not fixture:
            raise AADBError("AADB compact reference archive is missing")
    elif not fixture:
        reference = references[0]
        if (
            reference.get("id") != "warp256"
            or reference.get("filename") != "datasetImages_warp256.zip"
            or reference.get("file_id") != WARP256_FILE_ID
            or reference.get("url") != ARCHIVE_URLS["warp256"]
            or reference.get("size_bytes") != WARP256_SIZE
            or reference.get("sha256") != WARP256_SHA256
            or reference.get("image_count_observed") != COMPACT_MATCHED_IMAGES + COMPACT_EXCLUDED_LEGACY_EXTRAS
        ):
            raise AADBError("AADB compact warp256 archive pin is invalid")
    compact_mode = spec.get("compact_mode")
    if not fixture:
        if not isinstance(compact_mode, Mapping) or compact_mode.get("archive_id") != "warp256" or compact_mode.get("matched_images") != COMPACT_MATCHED_IMAGES or compact_mode.get("excluded_legacy_extras") != COMPACT_EXCLUDED_LEGACY_EXTRAS or compact_mode.get("projection") != "overall_score_only_from_AADBinfo.mat":
            raise AADBError("AADB compact mode is missing or weakened")
        deduplication = compact_mode.get("deduplication") if isinstance(compact_mode, Mapping) else None
        if not isinstance(deduplication, Mapping) or deduplication.get("algorithm") != "sha256_of_source_file_before_camera_source_intake" or deduplication.get("winner_order") != [
            "split (train before test)",
            "source_id",
            "source_record_id",
            "source_image_name",
        ] or deduplication.get("name_binding") != "exact warp256 basename must equal the normalized AADBinfo name; retained winner basename is bound to inventory relative_path":
            raise AADBError("AADB compact deduplication policy is missing or weakened")


def _reference_archive(spec: Mapping[str, Any]) -> Mapping[str, Any]:
    references = spec.get("reference_archives")
    if not isinstance(references, list):
        raise AADBError("AADB compact reference archive is missing")
    matches = [item for item in references if isinstance(item, Mapping) and item.get("id") == "warp256"]
    if len(matches) != 1:
        raise AADBError("AADB compact warp256 reference is ambiguous")
    return matches[0]


def _compact_counts(spec: Mapping[str, Any]) -> tuple[int, int]:
    mode = spec.get("compact_mode")
    if not isinstance(mode, Mapping):
        return COMPACT_MATCHED_IMAGES, COMPACT_EXCLUDED_LEGACY_EXTRAS
    try:
        matched = int(mode.get("matched_images", COMPACT_MATCHED_IMAGES))
        excluded = int(mode.get("excluded_legacy_extras", COMPACT_EXCLUDED_LEGACY_EXTRAS))
    except (TypeError, ValueError) as exc:
        raise AADBError("AADB compact counts are invalid") from exc
    if matched < 1 or excluded < 0:
        raise AADBError("AADB compact counts are invalid")
    return matched, excluded


def _load_spec() -> dict[str, Any]:
    try:
        spec = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise AADBError("cannot load the tracked AADB source specification") from exc
    if not isinstance(spec, dict):
        raise AADBError("AADB source specification must be an object")
    _validate_spec(spec)
    return spec


def _require_pins(spec: Mapping[str, Any]) -> None:
    for item in spec["archives"]:
        size = item.get("size_bytes")
        digest = item.get("sha256")
        if not isinstance(size, int) or isinstance(size, bool) or size < 1 or not isinstance(digest, str) or not SHA256_RE.fullmatch(digest):
            raise AADBError(f"archive {item.get('id')} is not pinned; run --bootstrap-pins and copy its exact size_bytes/sha256 into aadb-v1.json")


def _archive_receipt(path: Path, item: Mapping[str, Any], *, retained: bool) -> dict[str, Any]:
    size, digest = _size_hash(path)
    if item.get("size_bytes") != size or item.get("sha256") != digest:
        raise AADBError(f"archive pin mismatch after download: {item.get('id')}")
    return {
        "id": item["id"], "filename": item["filename"], "file_id": item["file_id"],
        "url": item["url"], "size_bytes": size, "sha256": digest, "retained": retained,
    }


def _metadata_receipt(root: Path, spec: Mapping[str, Any]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    metadata_root = _fixed_directory(root, "metadata")
    expected_paths = {item["path"] for item in spec["metadata"]}
    actual_paths = {path.relative_to(metadata_root).as_posix() for path in metadata_root.rglob("*") if path.is_file() and not path.is_symlink()}
    if actual_paths != expected_paths:
        raise AADBError(f"metadata tree differs from the pinned set: extra={sorted(actual_paths - expected_paths)[:1]} missing={sorted(expected_paths - actual_paths)[:1]}")
    for item in spec["metadata"]:
        path = _fixed_file(root, f"metadata/{item['path']}")
        size, digest = _size_hash(path)
        if size != item.get("size_bytes") or digest != item.get("sha256"):
            raise AADBError(f"metadata pin mismatch: {item['path']}")
        result.append({"path": f"metadata/{item['path']}", "size_bytes": size, "sha256": digest})
    return result


def _labels_receipt(root: Path) -> list[dict[str, Any]]:
    labels = _fixed_directory(root, "labels")
    result: list[dict[str, Any]] = []
    for path in sorted(labels.rglob("*"), key=lambda p: p.as_posix()):
        if path.is_symlink():
            raise AADBError("labels tree contains a symlink")
        if path.is_file():
            size, digest = _size_hash(path)
            result.append({"path": path.relative_to(root).as_posix(), "size_bytes": size, "sha256": digest})
    if not result:
        raise AADBError("labels tree is empty")
    return result


def _write_receipt(root: Path, *, spec: Mapping[str, Any], spec_hash: str, archive_receipts: Sequence[Mapping[str, Any]], rows: Sequence[Mapping[str, Any]], inventory_bytes: bytes, silver_bytes: bytes) -> None:
    raw_path = _fixed_file(root, "raw-manifest.jsonl")
    inventory_path = _fixed_file(root, "inventory.jsonl")
    silver_path = _fixed_file(root, "silver-manifest.jsonl")
    metadata = _metadata_receipt(root, spec)
    labels = _labels_receipt(root)
    silver_hash = hashlib.sha256(silver_bytes).hexdigest()
    receipt = {
        "schema_id": "camera-aadb-ingest-receipt-v1",
        "source_id": SOURCE_ID,
        "repository": SOURCE_REPOSITORY,
        "commit": SOURCE_COMMIT,
        "source_spec_sha256": spec_hash,
        "tool_sha256": _tool_hash(),
        "archives": list(archive_receipts),
        "metadata": metadata,
        "labels": labels,
        "environment": {
            "python": sys.version.split()[0],
            "platform": sys.platform,
            "pillow": _pillow_version(),
            "intake_tool_sha256": _sha256_file(INTAKE_SCRIPT),
        },
        "counts": {
            "train_images": sum(row["image_id"].startswith("train:") for row in rows),
            "test_images": sum(row["image_id"].startswith("test:") for row in rows),
            "images": len(rows),
            "silver_records": len(silver_bytes.splitlines()),
            "selected_label_files": len(labels),
        },
        "outputs": {
            "raw_manifest": {"path": "raw-manifest.jsonl", "sha256": _sha256_file(raw_path), "records": len(rows)},
            "inventory": {"path": "inventory.jsonl", "sha256": _sha256_file(inventory_path), "records": len(rows)},
            "silver_manifest": {"path": "silver-manifest.jsonl", "sha256": _sha256_file(silver_path), "records": len(silver_bytes.splitlines())},
            "image_aggregate": {"sha256": hashlib.sha256(inventory_bytes).hexdigest(), "records": len(rows)},
            "silver_aggregate": {"sha256": silver_hash, "records": len(silver_bytes.splitlines())},
        },
        "boundary": {
            "research_only": True, "human_gold": False, "release_admissible": False,
            "model_redistribution_cleared": False, "label_boundary": "auxiliary_aesthetic_attributes_only",
        },
    }
    _atomic_write_json(_fixed_file(root, "receipts/aadb-source-receipt.json", create_parent=True), receipt)


def _pillow_version() -> str:
    try:
        import PIL
        return str(getattr(PIL, "__version__", "unknown"))
    except ImportError:
        return "unavailable"


def _official_info_smoke() -> bool:
    """Parse a supplied local copy of the immutable official AADBinfo.mat."""

    candidates: list[Path] = []
    supplied = os.environ.get("AADBINFO_MAT")
    if supplied:
        candidates.append(Path(supplied).expanduser())
    candidates.append(Path("/private/tmp/AADBinfo.mat"))
    for path in candidates:
        if not path.exists():
            continue
        size, digest = _size_hash(path)
        expected_size, expected_hash = METADATA_PINS["AADBinfo.mat"]
        if (size, digest) != (expected_size, expected_hash):
            raise AADBError(f"supplied AADBinfo.mat is not the pinned official file: {path}")
        parsed = _load_info(path, expected_counts={"train": 8458, "test": 1000})
        if {split: len(names) for split, names in parsed.items()} != {"train": 8458, "test": 1000}:
            raise AADBError("supplied AADBinfo.mat has unexpected train/test counts")
        return True
    return False


def _build_outputs(root: Path, spec: Mapping[str, Any], *, spec_hash: str, archive_receipts: Sequence[Mapping[str, Any]]) -> None:
    rows = _image_rows(root)
    raw_bytes = _jsonl_bytes(rows)
    raw_path = _fixed_file(root, "raw-manifest.jsonl", create_parent=True)
    _atomic_write_bytes(raw_path, raw_bytes)
    temporary_dir = Path(tempfile.mkdtemp(prefix="aadb-inventory-"))
    temporary_inventory = temporary_dir / "inventory.jsonl"
    try:
        _run_intake(root, raw_path, temporary_inventory)
        inventory_bytes = temporary_inventory.read_bytes()
    finally:
        shutil.rmtree(temporary_dir, ignore_errors=True)
    _atomic_write_bytes(_fixed_file(root, "inventory.jsonl", create_parent=True), inventory_bytes)
    silver_rows = _silver_rows(root, info_path=_fixed_file(root, "metadata/AADBinfo.mat"), labels_root=_fixed_directory(root, "labels"), expected_counts=spec.get("expected_counts"))
    silver_bytes = _jsonl_bytes(silver_rows)
    _atomic_write_bytes(_fixed_file(root, "silver-manifest.jsonl", create_parent=True), silver_bytes)
    _write_receipt(root, spec=spec, spec_hash=spec_hash, archive_receipts=archive_receipts, rows=rows, inventory_bytes=inventory_bytes, silver_bytes=silver_bytes)


def _remove_staging_archives(root: Path) -> None:
    staging = _fixed_directory(root, "staging", allow_missing=True)
    if not staging.exists():
        return
    for path in sorted(staging.rglob("*"), key=lambda p: len(p.parts), reverse=True):
        if path.is_symlink():
            raise AADBError("staging contains a symlink")
        if path.is_file():
            path.unlink()
        elif path.is_dir():
            path.rmdir()
    if staging.exists():
        staging.rmdir()


def _fetch(root_value: Path, *, spec: Mapping[str, Any] | None = None, runner: Callable[..., Any] = subprocess.run, spec_hash: str | None = None) -> int:
    spec = dict(spec or _load_spec())
    _validate_spec(spec, fixture=bool(spec.get("_fixture")))
    _require_pins(spec)
    root = _external_root(root_value)
    for directory in ("images", "images/train", "images/test", "labels", "metadata", "receipts", "staging", "staging/archives", "staging/extract"):
        _fixed_directory(root, directory, create=True)
    spec_hash = spec_hash or _spec_hash()
    archive_receipts: list[dict[str, Any]] = []
    for item in spec["metadata"]:
        destination = _fixed_file(root, f"staging/metadata/{item['path']}", create_parent=True)
        _download(item, destination, runner, kind="mat" if item["path"].endswith(".mat") else "text")
        final = _fixed_file(root, f"metadata/{item['path']}", create_parent=True)
        if final.exists():
            if not filecmp.cmp(destination, final, shallow=False):
                raise AADBError(f"conflicting existing metadata: {item['path']}")
            destination.unlink()
        else:
            os.replace(destination, final)
    for item in spec["archives"]:
        stage_path = _fixed_file(root, f"staging/archives/{item['filename']}", create_parent=True)
        _download(item, stage_path, runner, kind="label_archive" if item["id"] == "labels" else "image_archive")
        archive_receipts.append(_archive_receipt(stage_path, item, retained=False))
        extract_stage = _fixed_directory(root, f"staging/extract/{item['id']}", create=True)
        _extract_zip(stage_path, extract_stage, kind="labels" if item["id"] == "labels" else "images")
        target = _fixed_directory(root, "labels" if item["id"] == "labels" else f"images/{item['id']}", create=True)
        _promote_tree(extract_stage, target)
    _build_outputs(root, spec, spec_hash=spec_hash, archive_receipts=archive_receipts)
    _remove_staging_archives(root)
    print(f"PASS fetch-aadb source_id={SOURCE_ID} records={json.loads((_fixed_file(root, 'receipts/aadb-source-receipt.json')).read_text())['counts']['silver_records']} archives_retained=false")
    return 0


def _reject_archive_under_root(root_value: Path, archive_value: Path) -> None:
    """Reject an input archive that is inside the managed output root.

    Check both lexical and resolved paths.  The lexical check catches a
    symlink located under the output root before the later archive validation
    rejects that symlink; neither check creates the root or writes anything.
    """

    root_path = Path(root_value).expanduser()
    archive_path = Path(archive_value).expanduser()
    try:
        lexical_root = Path(os.path.abspath(os.fspath(root_path)))
        lexical_archive = Path(os.path.abspath(os.fspath(archive_path)))
        resolved_root = lexical_root.resolve()
        resolved_archive = lexical_archive.resolve()
    except (OSError, RuntimeError) as exc:
        raise AADBError("cannot resolve compact output or archive path") from exc
    if lexical_archive == lexical_root or lexical_root in lexical_archive.parents or resolved_archive == resolved_root or resolved_root in resolved_archive.parents:
        raise AADBError("warp256 input archive must be outside the managed output root")


def _validate_warp256_archive(path_value: Path, reference: Mapping[str, Any]) -> Path:
    path = Path(path_value).expanduser()
    if path.is_symlink():
        raise AADBError("warp256 input archive must not be a symlink")
    resolved = path.resolve()
    repository = ROOT.resolve()
    if resolved == repository or repository in resolved.parents:
        raise AADBError("warp256 input archive must be outside the repository")
    if not path.exists() or not path.is_file():
        raise AADBError("warp256 input archive is missing or not regular")
    size, digest = _size_hash(path)
    if size != reference.get("size_bytes") or digest != reference.get("sha256"):
        raise AADBError("warp256 input archive does not match its immutable pin")
    _payload_kind_ok(path, "image_archive")
    return path


def _compact_extract_warp256(
    root: Path,
    archive_path: Path,
    info: Mapping[str, Mapping[str, float]],
    *,
    expected_extras: int,
) -> tuple[int, int, list[dict[str, Any]], list[dict[str, Any]]]:
    """Extract linked warp-256 media and deduplicate it before common intake.

    ``camera_source_intake`` intentionally rejects duplicate content.  AADB's
    linked train/test names can nevertheless point at the same source bytes,
    so compact admission chooses one deterministic winner before invoking the
    common intake.  Legacy names that are absent from AADBinfo remain a
    separate exclusion class and are never content-deduplicated with linked
    records.
    """

    extraction = _fixed_directory(root, "staging/compact-extract", create=True)
    extracted = _extract_zip(archive_path, extraction, kind="images")
    train_names = set(info["train"])
    test_names = set(info["test"])
    seen: set[str] = set()
    excluded = 0
    linked_candidates: list[dict[str, Any]] = []
    split_stages = {
        "train": _fixed_directory(root, "staging/compact/train", create=True),
        "test": _fixed_directory(root, "staging/compact/test", create=True),
    }
    for relative in extracted:
        source = _safe_relative(extraction, relative)
        source_name = PurePosixPath(relative).name
        normalized = _normalize_name(source_name)
        if normalized in seen:
            raise AADBError(f"duplicate warp256 normalized image name: {normalized}")
        seen.add(normalized)
        split = "train" if normalized in train_names else "test" if normalized in test_names else None
        if split is None:
            excluded += 1
            source.unlink()
            continue
        linked_candidates.append({
            "split": split,
            "normalized_image_name": normalized,
            "source_record_id": f"{split}:{normalized}",
            "source_image_name": source_name,
            "overall_score": info[split][normalized],
            "source": source,
            "sha256": _sha256_file(source),
        })
    matched = len(linked_candidates)
    if matched != sum(len(info[split]) for split in ("train", "test")):
        raise AADBError(f"warp256 archive does not link exactly to AADBinfo.mat: matched={matched}")
    if excluded != expected_extras:
        raise AADBError(f"warp256 legacy-extra count mismatch: expected={expected_extras} actual={excluded}")

    by_digest: dict[str, list[dict[str, Any]]] = {}
    for candidate in linked_candidates:
        by_digest.setdefault(candidate["sha256"], []).append(candidate)
    duplicate_exclusions: list[dict[str, Any]] = []
    admitted: list[dict[str, Any]] = []
    split_order = {"train": 0, "test": 1}
    for digest in sorted(by_digest):
        candidates = by_digest[digest]
        winner = min(
            candidates,
            key=lambda candidate: (
                split_order[candidate["split"]],
                SOURCE_ID,
                candidate["source_record_id"],
                candidate["source_image_name"],
            ),
        )
        for candidate in candidates:
            source = candidate["source"]
            if candidate is not winner:
                source.unlink()
                duplicate_exclusions.append({
                    "sha256": digest,
                    "excluded_source_record_id": candidate["source_record_id"],
                    "excluded_split": candidate["split"],
                    "excluded_source_image_name": candidate["source_image_name"],
                    "excluded_overall_score": candidate["overall_score"],
                    "winner_source_record_id": winner["source_record_id"],
                    "winner_split": winner["split"],
                    "winner_source_image_name": winner["source_image_name"],
                    "winner_overall_score": winner["overall_score"],
                    "cross_split": candidate["split"] != winner["split"],
                    "reason": "duplicate_linked_source_content_sha256",
                })
                continue
            destination = _safe_relative(split_stages[candidate["split"]], candidate["source_image_name"])
            _ensure_directory(destination.parent)
            if destination.exists() or destination.is_symlink():
                raise AADBError(f"duplicate compact output name: {candidate['source_image_name']}")
            os.replace(source, destination)
            admitted.append({
                "source_record_id": candidate["source_record_id"],
                "split": candidate["split"],
                "source_image_name": candidate["source_image_name"],
                "sha256": digest,
            })
    duplicate_exclusions.sort(key=lambda item: (item["excluded_source_record_id"], item["sha256"], item["winner_source_record_id"]))
    admitted.sort(key=lambda item: item["source_record_id"])
    _promote_tree(split_stages["train"], _fixed_directory(root, "images/train", create=True))
    _promote_tree(split_stages["test"], _fixed_directory(root, "images/test", create=True))
    return matched, excluded, admitted, duplicate_exclusions


def _compact_silver_rows(
    root: Path,
    info_path: Path,
    *,
    expected_counts: Mapping[str, int] | None = None,
    admitted_ids: set[str] | None = None,
) -> list[dict[str, Any]]:
    info = _load_info(info_path, expected_counts=expected_counts)
    rows = _image_rows(root)
    images = {
        (row["image_id"].split(":", 1)[0], _normalize_name(row["image_id"].split(":", 1)[1])): row
        for row in rows
    }
    full_images = {(split, name) for split in info for name in info[split]}
    if admitted_ids is None:
        admitted_ids = {f"{split}:{name}" for split, name in full_images}
    if not admitted_ids.issubset({f"{split}:{name}" for split, name in full_images}):
        raise AADBError("compact admitted IDs contain an unknown AADBinfo reference")
    expected_images = {
        (source_record_id.split(":", 1)[0], _normalize_name(source_record_id.split(":", 1)[1]))
        for source_record_id in admitted_ids
    }
    if set(images) != expected_images:
        missing = sorted(expected_images - set(images))
        unknown = sorted(set(images) - expected_images)
        raise AADBError(f"compact media/AADBinfo linkage mismatch: missing={missing[:1]} unknown={unknown[:1]}")
    output: list[dict[str, Any]] = []
    for split in ("train", "test"):
        for name, overall in sorted(info[split].items()):
            source_record_id = f"{split}:{name}"
            if source_record_id not in admitted_ids:
                continue
            image = images[(split, name)]
            output.append({
                "source_id": SOURCE_ID,
                "source_record_id": source_record_id,
                "relative_path": image["path"],
                "split": split,
                "source_image_name": PurePosixPath(image["path"]).name,
                "normalized_image_name": name,
                "overall_score": overall,
                "attribute_status": "not_projected_without_official_label_archive",
                "research_only": True,
                "human_gold": False,
                "release_admissible": False,
                "model_redistribution_cleared": False,
                "label_boundary": "auxiliary_aesthetic_attributes_only",
            })
    return sorted(output, key=lambda row: row["source_record_id"])


def _inventory_rows_from_bytes(payload: bytes) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for line_number, line in enumerate(payload.splitlines(), 1):
        try:
            value = json.loads(line)
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise AADBError(f"compact inventory has invalid JSON at line {line_number}") from exc
        if not isinstance(value, dict):
            raise AADBError(f"compact inventory row {line_number} is not an object")
        rows.append(value)
    if not rows:
        raise AADBError("compact inventory is empty")
    return rows


def _assert_unique_inventory_content(payload: bytes) -> list[dict[str, Any]]:
    rows = _inventory_rows_from_bytes(payload)
    seen: dict[str, str] = {}
    for row in rows:
        source_record_id = row.get("source_record_id")
        digest = row.get("sha256")
        if not isinstance(source_record_id, str) or not source_record_id:
            raise AADBError("compact inventory row has no source record ID")
        if not isinstance(digest, str) or not SHA256_RE.fullmatch(digest):
            raise AADBError(f"compact inventory row has an invalid content SHA: {source_record_id}")
        previous = seen.get(digest)
        if previous is not None and previous != source_record_id:
            raise AADBError(f"duplicate compact image content reached inventory: {digest}")
        seen[digest] = source_record_id
    return rows


def _compact_admitted_ids(
    receipt: Mapping[str, Any],
    info: Mapping[str, Mapping[str, float]],
    inventory_rows: Sequence[Mapping[str, Any]],
) -> set[str]:
    """Validate the durable dedupe decisions and derive admitted IDs."""

    full_ids = {f"{split}:{name}" for split in info for name in info[split]}
    deduplication = receipt.get("deduplication")
    if not isinstance(deduplication, Mapping):
        raise AADBError("compact receipt lacks deduplication decisions")
    if deduplication.get("algorithm") != "sha256_of_source_file_before_camera_source_intake" or deduplication.get("winner_order") != [
        "split (train before test)",
        "source_id",
        "source_record_id",
        "source_image_name",
    ] or deduplication.get("name_binding") != "exact warp256 basename must equal the normalized AADBinfo name; retained winner basename is bound to inventory relative_path":
        raise AADBError("compact receipt deduplication policy is invalid")
    exclusions = deduplication.get("duplicate_linked_exclusions")
    if not isinstance(exclusions, list):
        raise AADBError("compact receipt duplicate exclusion list is invalid")
    expected_keys = {
        "sha256",
        "excluded_source_record_id",
        "excluded_split",
        "excluded_source_image_name",
        "excluded_overall_score",
        "winner_source_record_id",
        "winner_split",
        "winner_source_image_name",
        "winner_overall_score",
        "cross_split",
        "reason",
    }
    excluded_ids: set[str] = set()
    winner_ids: set[str] = set()
    inventory_by_id = {row.get("source_record_id"): row for row in inventory_rows}
    split_order = {"train": 0, "test": 1}
    canonical_exclusions: list[Mapping[str, Any]] = []
    for item in exclusions:
        if not isinstance(item, Mapping) or set(item) != expected_keys:
            raise AADBError("compact receipt contains a malformed duplicate exclusion")
        digest = item.get("sha256")
        excluded_id = item.get("excluded_source_record_id")
        excluded_split = item.get("excluded_split")
        excluded_name = item.get("excluded_source_image_name")
        excluded_overall = item.get("excluded_overall_score")
        winner_id = item.get("winner_source_record_id")
        winner_split = item.get("winner_split")
        winner_name = item.get("winner_source_image_name")
        winner_overall = item.get("winner_overall_score")
        if (
            not isinstance(digest, str)
            or not SHA256_RE.fullmatch(digest)
            or not isinstance(excluded_id, str)
            or not isinstance(excluded_split, str)
            or excluded_split not in {"train", "test"}
            or not isinstance(excluded_name, str)
            or isinstance(excluded_overall, bool)
            or not isinstance(excluded_overall, (int, float))
            or not math.isfinite(float(excluded_overall))
            or not isinstance(winner_id, str)
            or not isinstance(winner_split, str)
            or winner_split not in {"train", "test"}
            or not isinstance(winner_name, str)
            or isinstance(winner_overall, bool)
            or not isinstance(winner_overall, (int, float))
            or not math.isfinite(float(winner_overall))
            or not isinstance(item.get("cross_split"), bool)
            or item.get("reason") != "duplicate_linked_source_content_sha256"
        ):
            raise AADBError("compact receipt contains an invalid duplicate exclusion field")
        try:
            excluded_id_split, excluded_id_name = excluded_id.split(":", 1)
            winner_id_split, winner_id_name = winner_id.split(":", 1)
        except ValueError as exc:
            raise AADBError("compact receipt duplicate exclusion ID is invalid") from exc
        if (
            excluded_id_split != excluded_split
            or winner_id_split != winner_split
            or _normalize_name(excluded_name) != excluded_id_name
            or _normalize_name(winner_name) != winner_id_name
            or excluded_name != excluded_id_name
            or winner_name != winner_id_name
            or excluded_id not in full_ids
            or winner_id not in full_ids
            or info[excluded_split].get(excluded_id_name) != excluded_overall
            or info[winner_split].get(winner_id_name) != winner_overall
            or excluded_id == winner_id
            or bool(item["cross_split"]) != (excluded_split != winner_split)
            or (split_order[winner_split], SOURCE_ID, winner_id, winner_name) >= (split_order[excluded_split], SOURCE_ID, excluded_id, excluded_name)
            or excluded_id in excluded_ids
        ):
            raise AADBError("compact receipt duplicate exclusion linkage is invalid")
        winner_row = inventory_by_id.get(winner_id)
        winner_relative_path = winner_row.get("relative_path") if winner_row is not None else None
        if (
            winner_row is None
            or winner_row.get("sha256") != digest
            or not isinstance(winner_relative_path, str)
            or PurePosixPath(winner_relative_path).name != winner_name
        ):
            raise AADBError("compact receipt duplicate winner is absent or has a different content SHA")
        if excluded_id in inventory_by_id:
            raise AADBError("compact receipt duplicate loser reached inventory")
        excluded_ids.add(excluded_id)
        winner_ids.add(winner_id)
        canonical_exclusions.append(item)
    if canonical_exclusions != sorted(canonical_exclusions, key=lambda item: (str(item["excluded_source_record_id"]), str(item["sha256"]), str(item["winner_source_record_id"]))):
        raise AADBError("compact receipt duplicate exclusions are not deterministically ordered")
    if deduplication.get("linked_images") != len(full_ids) or deduplication.get("admitted_images") != len(full_ids) - len(excluded_ids) or deduplication.get("excluded_count") != len(excluded_ids):
        raise AADBError("compact receipt deduplication counts are invalid")
    if deduplication.get("duplicate_group_count") != len({item["sha256"] for item in canonical_exclusions}):
        raise AADBError("compact receipt duplicate-group count is invalid")
    cross_split_count = sum(bool(item["cross_split"]) for item in canonical_exclusions)
    if deduplication.get("cross_split_excluded_count") != cross_split_count:
        raise AADBError("compact receipt cross-split deduplication count is invalid")
    admitted_ids = full_ids - excluded_ids
    inventory_ids = {row.get("source_record_id") for row in inventory_rows}
    if inventory_ids != admitted_ids:
        raise AADBError("compact inventory IDs do not match the receipt deduplication decisions")
    if winner_ids - admitted_ids:
        raise AADBError("compact receipt names a non-admitted duplicate winner")
    return admitted_ids


def _compact_metadata_receipt(root: Path, spec: Mapping[str, Any]) -> list[dict[str, Any]]:
    item = next(item for item in spec["metadata"] if item["path"] == "AADBinfo.mat")
    path = _fixed_file(root, "metadata/AADBinfo.mat")
    size, digest = _size_hash(path)
    if size != item.get("size_bytes") or digest != item.get("sha256"):
        raise AADBError("compact AADBinfo.mat pin mismatch")
    return [{"path": "metadata/AADBinfo.mat", "size_bytes": size, "sha256": digest}]


def _write_compact_receipt(
    root: Path,
    *,
    spec: Mapping[str, Any],
    spec_hash: str,
    reference: Mapping[str, Any],
    matched: int,
    excluded: int,
    admitted: Sequence[Mapping[str, Any]],
    duplicate_exclusions: Sequence[Mapping[str, Any]],
    rows: Sequence[Mapping[str, Any]],
    inventory_bytes: bytes,
    silver_bytes: bytes,
) -> None:
    raw_path = _fixed_file(root, "raw-manifest.jsonl")
    inventory_path = _fixed_file(root, "inventory.jsonl")
    silver_path = _fixed_file(root, "silver-manifest.jsonl")
    receipt = {
        "schema_id": "camera-aadb-compact-receipt-v1",
        "mode": "warp256_overall_score_only",
        "source_id": SOURCE_ID,
        "repository": SOURCE_REPOSITORY,
        "commit": SOURCE_COMMIT,
        "source_spec_sha256": spec_hash,
        "tool_sha256": _tool_hash(),
        "archive": {
            "id": "warp256",
            "filename": reference["filename"],
            "file_id": reference["file_id"],
            "url": reference["url"],
            "size_bytes": reference["size_bytes"],
            "sha256": reference["sha256"],
            "retained": False,
        },
        "metadata": _compact_metadata_receipt(root, spec),
        "environment": {
            "python": sys.version.split()[0],
            "platform": sys.platform,
            "pillow": _pillow_version(),
            "intake_tool_sha256": _sha256_file(INTAKE_SCRIPT),
        },
        "counts": {
            "archive_images": matched + excluded,
            "matched_images": matched,
            "admitted_images": len(admitted),
            "excluded_legacy_extras": excluded,
            "excluded_duplicate_linked_images": len(duplicate_exclusions),
            "duplicate_linked_groups": len({item["sha256"] for item in duplicate_exclusions}),
            "silver_records": len(silver_bytes.splitlines()),
        },
        "exclusion": {
            "count": excluded,
            "reason": "warp256 image names absent from the exact AADBinfo.mat train/test name lists",
            "legacy_extras_are_not_admitted": True,
        },
        "deduplication": {
            "algorithm": "sha256_of_source_file_before_camera_source_intake",
            "winner_order": [
                "split (train before test)",
                "source_id",
                "source_record_id",
                "source_image_name",
            ],
            "name_binding": "exact warp256 basename must equal the normalized AADBinfo name; retained winner basename is bound to inventory relative_path",
            "linked_images": matched,
            "admitted_images": len(admitted),
            "excluded_count": len(duplicate_exclusions),
            "duplicate_group_count": len({item["sha256"] for item in duplicate_exclusions}),
            "cross_split_excluded_count": sum(bool(item.get("cross_split")) for item in duplicate_exclusions),
            "duplicate_linked_exclusions": [dict(item) for item in duplicate_exclusions],
        },
        "outputs": {
            "raw_manifest": {"path": "raw-manifest.jsonl", "sha256": _sha256_file(raw_path), "records": len(rows)},
            "inventory": {"path": "inventory.jsonl", "sha256": _sha256_file(inventory_path), "records": len(rows)},
            "silver_manifest": {"path": "silver-manifest.jsonl", "sha256": _sha256_file(silver_path), "records": len(silver_bytes.splitlines())},
            "image_aggregate": {"sha256": hashlib.sha256(inventory_bytes).hexdigest(), "records": len(rows)},
            "silver_aggregate": {"sha256": hashlib.sha256(silver_bytes).hexdigest(), "records": len(silver_bytes.splitlines())},
        },
        "boundary": {
            "research_only": True,
            "human_gold": False,
            "release_admissible": False,
            "model_redistribution_cleared": False,
            "label_boundary": "auxiliary_aesthetic_attributes_only",
            "overall_score_only": True,
            "attributes_projected": False,
        },
    }
    _atomic_write_json(_fixed_file(root, "receipts/aadb-compact-receipt.json", create_parent=True), receipt)


def _compact_fetch(
    root_value: Path,
    *,
    archive_value: Path | None = None,
    spec: Mapping[str, Any] | None = None,
    runner: Callable[..., Any] = subprocess.run,
    spec_hash: str | None = None,
) -> int:
    spec = dict(spec or _load_spec())
    _validate_spec(spec, fixture=bool(spec.get("_fixture")))
    if archive_value is not None:
        _reject_archive_under_root(root_value, archive_value)
    root = _external_root(root_value)
    reference = _reference_archive(spec)
    _, expected_extras = _compact_counts(spec)
    for directory in ("images", "images/train", "images/test", "metadata", "receipts", "staging", "staging/archives", "staging/compact"):
        _fixed_directory(root, directory, create=True)
    spec_hash = spec_hash or _spec_hash()
    info_item = next(item for item in spec["metadata"] if item["path"] == "AADBinfo.mat")
    info_destination = _fixed_file(root, "staging/metadata/AADBinfo.mat", create_parent=True)
    _download(info_item, info_destination, runner, kind="mat")
    info_final = _fixed_file(root, "metadata/AADBinfo.mat", create_parent=True)
    if info_final.exists():
        if not filecmp.cmp(info_destination, info_final, shallow=False):
            raise AADBError("conflicting existing compact AADBinfo.mat")
        info_destination.unlink()
    else:
        os.replace(info_destination, info_final)
    info = _load_info(info_final, expected_counts=spec.get("expected_counts"))
    if archive_value is not None:
        archive_path = _validate_warp256_archive(archive_value, reference)
    else:
        staged = _fixed_file(root, f"staging/archives/{reference['filename']}", create_parent=True)
        if staged.exists():
            archive_path = _validate_warp256_archive(staged, reference)
        else:
            _download(reference, staged, runner, kind="image_archive")
            archive_path = _validate_warp256_archive(staged, reference)
    matched, excluded, admitted, duplicate_exclusions = _compact_extract_warp256(
        root,
        archive_path,
        info,
        expected_extras=expected_extras,
    )
    rows = _image_rows(root)
    raw_bytes = _jsonl_bytes(rows)
    _atomic_write_bytes(_fixed_file(root, "raw-manifest.jsonl", create_parent=True), raw_bytes)
    temporary_dir = Path(tempfile.mkdtemp(prefix="aadb-compact-inventory-"))
    try:
        temporary_inventory = temporary_dir / "inventory.jsonl"
        _run_intake(root, _fixed_file(root, "raw-manifest.jsonl"), temporary_inventory)
        inventory_bytes = temporary_inventory.read_bytes()
    finally:
        shutil.rmtree(temporary_dir, ignore_errors=True)
    inventory_rows = _assert_unique_inventory_content(inventory_bytes)
    expected_admitted_ids = {item["source_record_id"] for item in admitted}
    if {row.get("source_record_id") for row in inventory_rows} != expected_admitted_ids:
        raise AADBError("compact intake IDs differ from deterministic deduplication winners")
    _atomic_write_bytes(_fixed_file(root, "inventory.jsonl", create_parent=True), inventory_bytes)
    silver_rows = _compact_silver_rows(root, info_final, expected_counts=spec.get("expected_counts"), admitted_ids=expected_admitted_ids)
    silver_bytes = _jsonl_bytes(silver_rows)
    _atomic_write_bytes(_fixed_file(root, "silver-manifest.jsonl", create_parent=True), silver_bytes)
    _write_compact_receipt(root, spec=spec, spec_hash=spec_hash, reference=reference, matched=matched, excluded=excluded, admitted=admitted, duplicate_exclusions=duplicate_exclusions, rows=rows, inventory_bytes=inventory_bytes, silver_bytes=silver_bytes)
    _remove_staging_archives(root)
    print(f"PASS fetch-aadb compact=true source_id={SOURCE_ID} records={len(silver_rows)} admitted_images={len(admitted)} excluded_legacy_extras={excluded} excluded_duplicate_linked={len(duplicate_exclusions)} archives_retained=false")
    return 0


def _compact_verify_local(root_value: Path, *, spec: Mapping[str, Any] | None = None, spec_hash: str | None = None) -> int:
    spec = dict(spec or _load_spec())
    _validate_spec(spec, fixture=bool(spec.get("_fixture")))
    root = _external_root(root_value, create=False)
    receipt_path = _fixed_file(root, "receipts/aadb-compact-receipt.json")
    try:
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise AADBError("compact AADB receipt is unreadable") from exc
    if receipt.get("schema_id") != "camera-aadb-compact-receipt-v1" or receipt.get("mode") != "warp256_overall_score_only" or receipt.get("source_id") != SOURCE_ID or receipt.get("repository") != SOURCE_REPOSITORY or receipt.get("commit") != SOURCE_COMMIT:
        raise AADBError("compact AADB receipt identity is invalid")
    if receipt.get("source_spec_sha256") != (spec_hash or _spec_hash()) or receipt.get("tool_sha256") != _tool_hash():
        raise AADBError("compact AADB receipt is stale for the current source spec or adapter")
    boundary = receipt.get("boundary", {})
    expected_boundary = {
        "research_only": True,
        "human_gold": False,
        "release_admissible": False,
        "model_redistribution_cleared": False,
        "label_boundary": "auxiliary_aesthetic_attributes_only",
        "overall_score_only": True,
        "attributes_projected": False,
    }
    if boundary != expected_boundary:
        raise AADBError("compact AADB receipt research boundary is invalid")
    reference = _reference_archive(spec)
    expected_archive = {"id": "warp256", "filename": reference["filename"], "file_id": reference["file_id"], "url": reference["url"], "size_bytes": reference["size_bytes"], "sha256": reference["sha256"], "retained": False}
    if receipt.get("archive") != expected_archive:
        raise AADBError("compact AADB archive pin differs from the current source specification")
    for path in _all_files(root):
        relative = path.relative_to(root)
        if relative.parts[0] in {"staging", "archives", "labels"}:
            raise AADBError(f"compact corpus retains an unapproved path: {relative.as_posix()}")
        if len(relative.parts) == 1 and relative.name not in {"raw-manifest.jsonl", "inventory.jsonl", "silver-manifest.jsonl"}:
            raise AADBError(f"unexpected compact durable file: {relative.as_posix()}")
        if relative.parts[:1] == ("receipts",) and relative.as_posix() != "receipts/aadb-compact-receipt.json":
            raise AADBError(f"unexpected compact receipt file: {relative.as_posix()}")
    rows = _image_rows(root)
    raw_path = _fixed_file(root, "raw-manifest.jsonl")
    raw_bytes = _jsonl_bytes(rows)
    if raw_path.read_bytes() != raw_bytes:
        raise AADBError("compact raw manifest is not deterministic")
    temporary_dir = Path(tempfile.mkdtemp(prefix="aadb-compact-verify-"))
    try:
        temporary_inventory = temporary_dir / "inventory.jsonl"
        _run_intake(root, raw_path, temporary_inventory)
        inventory_bytes = temporary_inventory.read_bytes()
    finally:
        shutil.rmtree(temporary_dir, ignore_errors=True)
    inventory_path = _fixed_file(root, "inventory.jsonl")
    if inventory_path.read_bytes() != inventory_bytes:
        raise AADBError("compact inventory is not byte-identical to fresh intake")
    inventory_rows = _assert_unique_inventory_content(inventory_bytes)
    info = _load_info(_fixed_file(root, "metadata/AADBinfo.mat"), expected_counts=spec.get("expected_counts"))
    admitted_ids = _compact_admitted_ids(receipt, info, inventory_rows)
    silver_rows = _compact_silver_rows(root, _fixed_file(root, "metadata/AADBinfo.mat"), expected_counts=spec.get("expected_counts"), admitted_ids=admitted_ids)
    silver_bytes = _jsonl_bytes(silver_rows)
    silver_path = _fixed_file(root, "silver-manifest.jsonl")
    if silver_path.read_bytes() != silver_bytes:
        raise AADBError("compact silver manifest is not deterministic")
    expected_matched, expected_extras = _compact_counts(spec)
    expected_counts = {
        "archive_images": expected_matched + expected_extras,
        "matched_images": expected_matched,
        "admitted_images": len(admitted_ids),
        "excluded_legacy_extras": expected_extras,
        "excluded_duplicate_linked_images": expected_matched - len(admitted_ids),
        "duplicate_linked_groups": len({item["sha256"] for item in receipt["deduplication"]["duplicate_linked_exclusions"]}),
        "silver_records": len(silver_rows),
    }
    expected_exclusion = {
        "count": expected_extras,
        "reason": "warp256 image names absent from the exact AADBinfo.mat train/test name lists",
        "legacy_extras_are_not_admitted": True,
    }
    if receipt.get("counts") != expected_counts or receipt.get("exclusion") != expected_exclusion:
        raise AADBError("compact legacy-extra or admitted-image counts are not attested")
    expected_outputs = {
        "raw_manifest": {"path": "raw-manifest.jsonl", "sha256": _sha256_file(raw_path), "records": len(rows)},
        "inventory": {"path": "inventory.jsonl", "sha256": _sha256_file(inventory_path), "records": len(rows)},
        "silver_manifest": {"path": "silver-manifest.jsonl", "sha256": _sha256_file(silver_path), "records": len(silver_rows)},
        "image_aggregate": {"sha256": hashlib.sha256(inventory_bytes).hexdigest(), "records": len(rows)},
        "silver_aggregate": {"sha256": hashlib.sha256(silver_bytes).hexdigest(), "records": len(silver_rows)},
    }
    if receipt.get("outputs") != expected_outputs or receipt.get("metadata") != _compact_metadata_receipt(root, spec):
        raise AADBError("compact receipt hashes do not match durable corpus")
    print(f"PASS verify-local-aadb compact=true source_id={SOURCE_ID} records={len(silver_rows)} admitted_images={len(admitted_ids)} excluded_legacy_extras={expected_counts['excluded_legacy_extras']} excluded_duplicate_linked={expected_counts['excluded_duplicate_linked_images']} read_only=true")
    return 0


def _warp256_reference_smoke() -> bool:
    supplied = os.environ.get("AADB_WARP256_ARCHIVE")
    candidates = [Path(supplied).expanduser()] if supplied else []
    candidates.append(Path("~/Documents/XCode/setos-backend/local-data/SETOS/Datasets/camera-coach/research/aadb/warp256-v1-bootstrap/archives/datasetImages_warp256.zip").expanduser())
    for path in candidates:
        if not path.exists():
            continue
        reference = {"size_bytes": WARP256_SIZE, "sha256": WARP256_SHA256}
        _validate_warp256_archive(path, reference)
        with zipfile.ZipFile(path, "r") as archive:
            infos = archive.infolist()
            image_infos = [info for info in infos if not info.is_dir()]
            if len(image_infos) != COMPACT_MATCHED_IMAGES + COMPACT_EXCLUDED_LEGACY_EXTRAS:
                raise AADBError(f"warp256 reference member count differs: {len(image_infos)}")
            for info in image_infos:
                _member_parts(info.filename)
                if _is_zip_symlink(info) or Path(info.filename).suffix.lower() not in IMAGE_SUFFIXES:
                    raise AADBError("warp256 reference contains an unsafe/non-image member")
        info_path = Path(os.environ.get("AADBINFO_MAT", "/private/tmp/AADBinfo.mat"))
        if info_path.exists():
            info = _load_info(info_path, expected_counts={"train": 8458, "test": 1000})
            normalized = {_normalize_name(info_name) for split in info.values() for info_name in split}
            archive_names = set()
            with zipfile.ZipFile(path, "r") as archive:
                for info_item in archive.infolist():
                    if not info_item.is_dir():
                        archive_names.add(_normalize_name(PurePosixPath(info_item.filename).name))
            if len(archive_names & normalized) != COMPACT_MATCHED_IMAGES or len(archive_names - normalized) != COMPACT_EXCLUDED_LEGACY_EXTRAS:
                raise AADBError("warp256 reference did not produce the pinned 9458/500 name split")
        return True
    return False


def _bootstrap(root_value: Path, proposal_value: Path, *, spec: Mapping[str, Any] | None = None, runner: Callable[..., Any] = subprocess.run) -> int:
    spec = dict(spec or _load_spec())
    _validate_spec(spec, fixture=bool(spec.get("_fixture")))
    root = _external_root(root_value)
    proposal = _safe_external_file(proposal_value)
    _fixed_directory(root, "staging/archives", create=True)
    archive_results: list[dict[str, Any]] = []
    for item in spec["archives"]:
        bootstrap_item = dict(item)
        # The tracked observed lengths are hints only.  Bootstrap must accept
        # the server's actual length and compute a fresh immutable proposal.
        bootstrap_item["size_bytes"] = None
        bootstrap_item["max_size_bytes"] = MAX_ARCHIVE_BYTES
        destination = _fixed_file(root, f"staging/archives/{item['filename']}", create_parent=True)
        _download(bootstrap_item, destination, runner, kind="label_archive" if item["id"] == "labels" else "image_archive")
        _inspect_zip(destination, kind="labels" if item["id"] == "labels" else "images")
        size, digest = _size_hash(destination)
        archive_results.append({
            "id": item["id"], "filename": item["filename"], "file_id": item["file_id"], "url": item["url"],
            "size_bytes": size, "sha256": digest, "verified_archive": True,
            **dict(bootstrap_item.get("_response_metadata", {})),
        })
    proposal_data = {
        "schema_id": "camera-aadb-bootstrap-pin-v1",
        "source_id": SOURCE_ID, "repository": SOURCE_REPOSITORY, "commit": SOURCE_COMMIT,
        "source_spec_sha256": _spec_hash(), "tool_sha256": _tool_hash(), "archives": archive_results,
        "boundary": {"research_only": True, "human_gold": False, "release_admissible": False, "model_redistribution_cleared": False, "label_boundary": "auxiliary_aesthetic_attributes_only"},
        "admission": "proposal_only; copy exact size_bytes and sha256 into the tracked source spec before --fetch",
    }
    _atomic_write_json(proposal, proposal_data)
    print(f"PASS bootstrap-aadb source_id={SOURCE_ID} archives={len(archive_results)} proposal={proposal}")
    return 0


def _all_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for path in sorted(root.rglob("*"), key=lambda p: p.as_posix()):
        if path.is_symlink():
            raise AADBError(f"durable corpus contains a symlink: {path}")
        if path.is_file():
            files.append(path)
    return files


def _verify_local(root_value: Path, *, spec: Mapping[str, Any] | None = None, spec_hash: str | None = None) -> int:
    spec = dict(spec or _load_spec())
    _validate_spec(spec, fixture=bool(spec.get("_fixture")))
    _require_pins(spec)
    root = _external_root(root_value, create=False)
    receipt_path = _fixed_file(root, "receipts/aadb-source-receipt.json")
    try:
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise AADBError("AADB receipt is unreadable") from exc
    if receipt.get("schema_id") != "camera-aadb-ingest-receipt-v1" or receipt.get("source_id") != SOURCE_ID or receipt.get("commit") != SOURCE_COMMIT:
        raise AADBError("AADB receipt identity is invalid")
    if receipt.get("source_spec_sha256") != (spec_hash or _spec_hash()) or receipt.get("tool_sha256") != _tool_hash():
        raise AADBError("AADB receipt is stale for the current source spec or adapter")
    boundary = receipt.get("boundary", {})
    if boundary != {"research_only": True, "human_gold": False, "release_admissible": False, "model_redistribution_cleared": False, "label_boundary": "auxiliary_aesthetic_attributes_only"}:
        raise AADBError("AADB receipt research boundary is invalid")
    expected_archives = [
        {
            "id": item["id"], "filename": item["filename"], "file_id": item["file_id"], "url": item["url"],
            "size_bytes": item["size_bytes"], "sha256": item["sha256"], "retained": False,
        }
        for item in spec["archives"]
    ]
    if receipt.get("archives") != expected_archives:
        raise AADBError("receipt archive pins do not match the current source specification")
    if any(path.relative_to(root).parts[0] in {"staging", "archives"} for path in _all_files(root)):
        raise AADBError("durable corpus retains unapproved archive staging")
    known_files = {"raw-manifest.jsonl", "inventory.jsonl", "silver-manifest.jsonl"}
    known_dirs = {"images", "labels", "metadata", "receipts"}
    for path in _all_files(root):
        relative = path.relative_to(root)
        if len(relative.parts) == 1 and relative.parts[0] not in known_files:
            raise AADBError(f"unexpected durable file: {relative.as_posix()}")
        if relative.parts and relative.parts[0] not in known_dirs and len(relative.parts) > 1:
            raise AADBError(f"unexpected durable path: {relative.as_posix()}")
        if relative.parts[:1] == ("receipts",) and relative.as_posix() != "receipts/aadb-source-receipt.json":
            raise AADBError(f"unexpected receipt file: {relative.as_posix()}")
    rows = _image_rows(root)
    raw_bytes = _jsonl_bytes(rows)
    raw_path = _fixed_file(root, "raw-manifest.jsonl")
    if raw_path.read_bytes() != raw_bytes:
        raise AADBError("raw manifest is not deterministic for the current media")
    temporary_dir = Path(tempfile.mkdtemp(prefix="aadb-verify-"))
    try:
        temporary_inventory = temporary_dir / "inventory.jsonl"
        _run_intake(root, raw_path, temporary_inventory)
        inventory_bytes = temporary_inventory.read_bytes()
    finally:
        shutil.rmtree(temporary_dir, ignore_errors=True)
    inventory_path = _fixed_file(root, "inventory.jsonl")
    if inventory_path.read_bytes() != inventory_bytes:
        raise AADBError("inventory is not byte-identical to a fresh intake")
    silver_rows = _silver_rows(root, info_path=_fixed_file(root, "metadata/AADBinfo.mat"), labels_root=_fixed_directory(root, "labels"), expected_counts=spec.get("expected_counts"))
    silver_bytes = _jsonl_bytes(silver_rows)
    silver_path = _fixed_file(root, "silver-manifest.jsonl")
    if silver_path.read_bytes() != silver_bytes:
        raise AADBError("silver manifest is not deterministic")
    outputs = receipt.get("outputs", {})
    expected_outputs = {
        "raw_manifest": {"path": "raw-manifest.jsonl", "sha256": _sha256_file(raw_path), "records": len(rows)},
        "inventory": {"path": "inventory.jsonl", "sha256": _sha256_file(inventory_path), "records": len(rows)},
        "silver_manifest": {"path": "silver-manifest.jsonl", "sha256": _sha256_file(silver_path), "records": len(silver_rows)},
        "image_aggregate": {"sha256": hashlib.sha256(inventory_bytes).hexdigest(), "records": len(rows)},
        "silver_aggregate": {"sha256": hashlib.sha256(silver_bytes).hexdigest(), "records": len(silver_rows)},
    }
    expected_counts = {
        "train_images": sum(row["image_id"].startswith("train:") for row in rows),
        "test_images": sum(row["image_id"].startswith("test:") for row in rows),
        "images": len(rows),
        "silver_records": len(silver_rows),
        "selected_label_files": len(_labels_receipt(root)),
    }
    if receipt.get("counts") != expected_counts:
        raise AADBError("receipt counts do not match the durable corpus")
    if outputs != expected_outputs:
        raise AADBError("receipt output hashes/counts do not match durable corpus")
    if receipt.get("metadata") != _metadata_receipt(root, spec) or receipt.get("labels") != _labels_receipt(root):
        raise AADBError("receipt metadata or label hashes do not match durable corpus")
    print(f"PASS verify-local-aadb source_id={SOURCE_ID} records={len(silver_rows)} read_only=true")
    return 0


# The following writer is only used by the network-free self-test.  It emits
# the small subset of MAT v5 needed by the reader above and is never used by
# production acquisition.
def _mat_tag(dtype: int, payload: bytes, *, endian: str = "<") -> bytes:
    return struct.pack(endian + "II", dtype, len(payload)) + payload + (b"\x00" * ((-len(payload)) % 8))


def _mat_matrix(name: str, value: Any, *, cell: bool = False, endian: str = "<") -> bytes:
    cls = 1 if cell else 4 if isinstance(value, str) else 6
    flags = struct.pack(endian + "II", cls, 0)
    dims = struct.pack(endian + "II", 1, len(value) if isinstance(value, list) else max(1, len(value)))
    name_bytes = name.encode("utf-8")
    if cell:
        data = b"".join(_mat_matrix("", item, endian=endian) for item in value)
    elif isinstance(value, str):
        data = _mat_tag(16, value.encode("utf-8"), endian=endian)
    else:
        data = _mat_tag(9, struct.pack(endian + f"{len(value)}d", *value), endian=endian)
    body = _mat_tag(6, flags, endian=endian) + _mat_tag(5, dims, endian=endian) + _mat_tag(1, name_bytes, endian=endian) + data
    return _mat_tag(14, body, endian=endian)


def _fixture_mat(names_train: Sequence[str], names_test: Sequence[str]) -> bytes:
    header = b"MATLAB 5.0 MAT-file, Platform: AADB self-test".ljust(116, b" ") + b"\x00" * 8 + struct.pack("<H", 0x0100) + b"IM"
    matrices = (
        _mat_matrix("trainNameList", list(names_train), cell=True),
        _mat_matrix("trainScore", [0.5 + i for i in range(len(names_train))]),
        _mat_matrix("testNameList", list(names_test), cell=True),
        _mat_matrix("testScore", [0.2 + i for i in range(len(names_test))]),
    )
    # miCOMPRESSED elements are intentionally unpadded, matching the pinned
    # official file rather than the more common padded writer convention.
    payload = b"".join(struct.pack("<II", 15, len(compressed)) + compressed for compressed in (zlib.compress(matrix) for matrix in matrices))
    return header + payload


def _self_test() -> None:
    try:
        from PIL import Image
    except ImportError as exc:
        raise AADBError("Pillow is required for the self-test") from exc
    official_smoke = _official_info_smoke()
    warp256_smoke = _warp256_reference_smoke()
    with tempfile.TemporaryDirectory(prefix="fetch-aadb-") as temporary:
        base = Path(temporary)
        root = base / "external"
        root.mkdir()
        image_bytes: dict[str, bytes] = {}
        for name, color in (("train.jpg", (220, 20, 30)), ("test.jpg", (20, 30, 220))):
            output = io.BytesIO()
            Image.new("RGB", (4, 3), color).save(output, format="JPEG")
            image_bytes[name] = output.getvalue()
        archives: dict[str, bytes] = {}
        for archive_id, entries in {
            "train": {"datasetImages_originalSize/train.jpg": image_bytes["train.jpg"]},
            "test": {"AADB/datasetImages_originalSize/test.jpg": image_bytes["test.jpg"]},
        }.items():
            stream = io.BytesIO()
            with zipfile.ZipFile(stream, "w", zipfile.ZIP_STORED) as archive:
                for name, payload in entries.items():
                    archive.writestr(name, payload)
            archives[archive_id] = stream.getvalue()
        label_stream = io.BytesIO()
        with zipfile.ZipFile(label_stream, "w", zipfile.ZIP_STORED) as archive:
            for _, source_name in ATTRIBUTE_SPECS:
                archive.writestr(f"AADB/imgListFiles_label/imgListTrainRegression_{source_name}.txt", "train.jpg 0.25 2 0.1\n")
                archive.writestr(f"AADB/imgListFiles_label/imgListTestNewRegression_{source_name}.txt", "test.jpg 0.75 3 0.2\n")
        archives["labels"] = label_stream.getvalue()
        mat = _fixture_mat(["train.jpg"], ["test.jpg"])
        metadata_payloads = {"AADBinfo.mat": mat, "AADBstatistics.m": b"% self-test\n", "README.md": b"AADB self-test\n"}
        fixture_archives = []
        for archive_id in ("train", "test", "labels"):
            payload = archives[archive_id]
            fixture_archives.append({"id": archive_id, "filename": ARCHIVE_NAMES[archive_id], "file_id": {"train": TRAIN_FILE_ID, "test": TEST_FILE_ID, "labels": LABEL_FILE_ID}[archive_id], "url": ARCHIVE_URLS[archive_id], "size_bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest(), "observed_size_bytes": len(payload)})
        fixture_metadata = [{"path": name, "url": f"{GITHUB_RAW}/{name}", "size_bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest()} for name, payload in metadata_payloads.items()]
        fixture_spec = {"_fixture": True, "schema_id": "camera-aadb-source-spec-v1", "source_id": SOURCE_ID, "authority": {"repository": SOURCE_REPOSITORY, "commit": SOURCE_COMMIT}, "research_boundary": {"research_only": True, "human_gold": False, "release_admissible": False, "model_redistribution_cleared": False, "label_boundary": "auxiliary_aesthetic_attributes_only"}, "archives": fixture_archives, "metadata": fixture_metadata}
        warp_stream = io.BytesIO()
        with zipfile.ZipFile(warp_stream, "w", zipfile.ZIP_STORED) as archive:
            archive.writestr("datasetImages_warp256/train.jpg", image_bytes["train.jpg"])
            # Deliberately link the test name to the train bytes.  Compact
            # admission must choose the train winner and exclude the
            # cross-split test record before camera_source_intake sees it.
            archive.writestr("datasetImages_warp256/test.jpg", image_bytes["train.jpg"])
            archive.writestr("datasetImages_warp256/legacy.jpg", image_bytes["train.jpg"])
        warp_payload = warp_stream.getvalue()
        warp_path = base / "warp256.zip"
        warp_path.write_bytes(warp_payload)
        compact_reference = {
            "id": "warp256",
            "filename": "datasetImages_warp256.zip",
            "file_id": WARP256_FILE_ID,
            "url": ARCHIVE_URLS["warp256"],
            "size_bytes": len(warp_payload),
            "sha256": hashlib.sha256(warp_payload).hexdigest(),
        }
        compact_spec = dict(fixture_spec)
        compact_spec["reference_archives"] = [compact_reference]
        compact_spec["compact_mode"] = {"matched_images": 2, "excluded_legacy_extras": 1}
        payloads = {item["url"]: archives[item["id"]] for item in fixture_archives} | {item["url"]: metadata_payloads[item["path"]] for item in fixture_metadata}
        calls: list[int] = []
        train_attempts = 0

        def fake_runner(command: list[str], *, check: bool, **kwargs: Any) -> subprocess.CompletedProcess[str]:
            nonlocal train_attempts
            url = command[-1]
            output = Path(command[command.index("--output") + 1])
            payload = payloads[url]
            offset = output.stat().st_size if output.exists() else 0
            calls.append(offset)
            if f"id={TRAIN_FILE_ID}" in url and train_attempts == 0:
                train_attempts += 1
                output.write_bytes(payload[: max(1, len(payload) // 2)])
                raise subprocess.CalledProcessError(18, command)
            with output.open("ab") as stream:
                stream.write(payload[offset:])
            header = Path(command[command.index("--dump-header") + 1])
            header.write_text("HTTP/2 200\ncontent-type: application/octet-stream\n\n", encoding="ascii")
            return subprocess.CompletedProcess(command, 0, "", "")

        _fetch(root, spec=fixture_spec, runner=fake_runner, spec_hash="f" * 64)
        assert any(offset > 0 for offset in calls), "self-test did not exercise a resumed range"
        before = {path.relative_to(root).as_posix(): path.read_bytes() for path in _all_files(root)}
        _verify_local(root, spec=fixture_spec, spec_hash="f" * 64)
        after = {path.relative_to(root).as_posix(): path.read_bytes() for path in _all_files(root)}
        assert before == after, "verify-local modified the durable corpus"
        silver = [json.loads(line) for line in (root / "silver-manifest.jsonl").read_text(encoding="utf-8").splitlines()]
        assert len(silver) == 2 and silver[0]["research_only"] is True
        assert set(silver[0]["attributes"]) == {canonical for canonical, _ in ATTRIBUTE_SPECS}
        train_silver = next(row for row in silver if row["split"] == "train")
        assert train_silver["original_rater_or_uncertainty_fields"]["interesting_content"] == ["2", "0.1"]
        forbidden = {"action", "issue", "keep", "good_frame", "risk", "abstention", "locked_holdout"}
        assert not forbidden & {key.lower() for row in silver for key in row}
        signature_path = base / "signature.zip"
        signature_path.write_bytes(b"PK" + b"x" * 1022)
        read_limits: list[int] = []
        original_open = Path.open

        class TrackingReader:
            def __init__(self, stream: Any) -> None:
                self.stream = stream

            def __enter__(self) -> "TrackingReader":
                self.stream.__enter__()
                return self

            def __exit__(self, *args: Any) -> Any:
                return self.stream.__exit__(*args)

            def read(self, size: int = -1) -> bytes:
                read_limits.append(size)
                return self.stream.read(size)

            def __getattr__(self, name: str) -> Any:
                return getattr(self.stream, name)

        def tracking_open(path: Path, *args: Any, **kwargs: Any) -> TrackingReader:
            return TrackingReader(original_open(path, *args, **kwargs))

        Path.open = tracking_open  # type: ignore[method-assign]
        try:
            _payload_kind_ok(signature_path, "archive")
        finally:
            Path.open = original_open  # type: ignore[method-assign]
        assert read_limits == [512, 8], f"signature probes were not bounded: {read_limits}"

        managed_root = base / "managed-output"
        managed_root.mkdir()
        managed_archive = managed_root / "warp256.zip"
        managed_archive.write_bytes(warp_payload)
        managed_before = {path.relative_to(managed_root).as_posix(): path.read_bytes() for path in _all_files(managed_root)}
        try:
            _compact_fetch(managed_root, archive_value=managed_archive, spec=compact_spec, runner=fake_runner, spec_hash="e" * 64)
        except AADBError as exc:
            assert "managed output root" in str(exc)
        else:
            raise AssertionError("archive inside managed output root was accepted")
        managed_after = {path.relative_to(managed_root).as_posix(): path.read_bytes() for path in _all_files(managed_root)}
        assert managed_before == managed_after, "managed output root changed before archive-path rejection"
        compact_root = base / "compact"
        with contextlib.redirect_stdout(io.StringIO()):
            _compact_fetch(compact_root, archive_value=warp_path, spec=compact_spec, runner=fake_runner, spec_hash="e" * 64)
        compact_before = {path.relative_to(compact_root).as_posix(): path.read_bytes() for path in _all_files(compact_root)}
        with contextlib.redirect_stdout(io.StringIO()):
            _compact_verify_local(compact_root, spec=compact_spec, spec_hash="e" * 64)
        compact_after = {path.relative_to(compact_root).as_posix(): path.read_bytes() for path in _all_files(compact_root)}
        assert compact_before == compact_after, "compact verify-local modified the durable corpus"
        compact_silver = [json.loads(line) for line in (compact_root / "silver-manifest.jsonl").read_text(encoding="utf-8").splitlines()]
        assert len(compact_silver) == 1 and all("overall_score" in row and "attributes" not in row for row in compact_silver)
        assert compact_silver[0]["source_record_id"] == "train:train.jpg" and compact_silver[0]["overall_score"] == 0.5
        compact_receipt = json.loads((compact_root / "receipts/aadb-compact-receipt.json").read_text(encoding="utf-8"))
        assert compact_receipt["counts"]["matched_images"] == 2
        assert compact_receipt["counts"]["admitted_images"] == 1
        assert compact_receipt["counts"]["excluded_legacy_extras"] == 1
        assert compact_receipt["counts"]["excluded_duplicate_linked_images"] == 1
        assert compact_receipt["counts"]["duplicate_linked_groups"] == 1
        duplicate_exclusions = compact_receipt["deduplication"]["duplicate_linked_exclusions"]
        assert len(duplicate_exclusions) == 1
        assert duplicate_exclusions[0]["excluded_source_record_id"] == "test:test.jpg"
        assert duplicate_exclusions[0]["winner_source_record_id"] == "train:train.jpg"
        assert duplicate_exclusions[0]["excluded_overall_score"] == 0.2
        assert duplicate_exclusions[0]["winner_overall_score"] == 0.5
        assert duplicate_exclusions[0]["cross_split"] is True
        inventory_rows = [json.loads(line) for line in (compact_root / "inventory.jsonl").read_text(encoding="utf-8").splitlines()]
        assert len({row["sha256"] for row in inventory_rows}) == len(inventory_rows) == 1
        compact_receipt_path = compact_root / "receipts/aadb-compact-receipt.json"
        compact_receipt_bytes = compact_receipt_path.read_bytes()
        for field, value in (("winner_source_image_name", "1.234_train.jpg"), ("excluded_source_image_name", "9.999_test.jpg")):
            tampered_receipt = json.loads(compact_receipt_bytes)
            tampered_receipt["deduplication"]["duplicate_linked_exclusions"][0][field] = value
            compact_receipt_path.write_text(_json_line(tampered_receipt) + "\n", encoding="utf-8")
            try:
                _compact_verify_local(compact_root, spec=compact_spec, spec_hash="e" * 64)
            except AADBError:
                pass
            else:
                raise AssertionError(f"tampered compact {field} receipt was accepted")
        compact_receipt_path.write_bytes(compact_receipt_bytes)
        bootstrap_root = base / "bootstrap"
        proposal = base / "proposed-pin.json"
        with contextlib.redirect_stdout(io.StringIO()):
            _bootstrap(bootstrap_root, proposal, spec=fixture_spec, runner=fake_runner)
        assert proposal.is_file()
        assert all((bootstrap_root / "staging" / "archives" / item["filename"]).is_file() for item in fixture_spec["archives"])
        assert not (bootstrap_root / "images").exists() and not (bootstrap_root / "labels").exists()
        assert len(json.loads(proposal.read_text(encoding="utf-8"))["archives"]) == 3
        wrong_payload = b"X" * len(archives["labels"])
        wrong_spec = {"url": ARCHIVE_URLS["labels"], "size_bytes": len(wrong_payload), "sha256": hashlib.sha256(archives["labels"]).hexdigest()}

        def wrong_runner(command: list[str], *, check: bool, **kwargs: Any) -> subprocess.CompletedProcess[str]:
            output = Path(command[command.index("--output") + 1])
            output.write_bytes(wrong_payload)
            return subprocess.CompletedProcess(command, 0, "", "")

        try:
            _download(wrong_spec, base / "wrong.zip", wrong_runner, kind="archive")
        except AADBError:
            pass
        else:
            raise AssertionError("same-sized wrong hash was accepted")
        bad_zip = base / "bad.zip"
        with zipfile.ZipFile(bad_zip, "w") as archive:
            archive.writestr("../escape.jpg", b"bad")
        try:
            _inspect_zip(bad_zip, kind="images")
        except AADBError:
            pass
        else:
            raise AssertionError("ZIP traversal was accepted")
        bad_html_spec = {"url": ARCHIVE_URLS["labels"], "size_bytes": 4, "sha256": hashlib.sha256(b"PKxx").hexdigest()}
        payloads[bad_html_spec["url"]] = b"<html>interstitial</html>"
        try:
            _download(bad_html_spec, base / "html.zip", fake_runner, kind="archive")
        except AADBError:
            pass
        else:
            raise AssertionError("HTML interstitial was accepted")
        symlink_destination = base / "symlink-header.zip"
        symlink_header = Path(f"{symlink_destination}.part.headers")
        symlink_header.symlink_to(base / "missing-header")
        try:
            _download(fixture_archives[0], symlink_destination, fake_runner, kind="archive")
        except AADBError:
            pass
        else:
            raise AssertionError(".part.headers symlink was accepted")
    print(f"PASS fetch_aadb self-test resume hash archive_traversal annotation_projection compact_mode content_dedupe read_only_verify bounded_signature_reads managed_archive_guard header_symlink_guard official_mat_smoke={str(official_smoke).lower()} warp256_reference_smoke={str(warp256_smoke).lower()}")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", type=Path, help="external managed AADB root")
    parser.add_argument("--bootstrap-pins", type=Path, help="external proposed-pin receipt path")
    parser.add_argument("--compact", action="store_true", help="use pinned warp256 media and AADBinfo.mat; project overall score only")
    parser.add_argument("--warp256-archive", type=Path, help="reuse an existing pinned warp256 ZIP outside the managed output root")
    parser.add_argument("--fetch", action="store_true", help="fetch pinned archives and build the durable corpus")
    parser.add_argument("--verify-local", action="store_true", help="read-only revalidate a durable corpus")
    parser.add_argument("--self-test", action="store_true", help="run network-free local fixtures")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = _parser()
    args = parser.parse_args(argv)
    try:
        actions = sum(bool(value) for value in (args.fetch, args.verify_local, args.self_test, args.bootstrap_pins is not None))
        if actions != 1:
            parser.error("choose exactly one of --bootstrap-pins, --fetch, --verify-local, or --self-test")
        if args.warp256_archive is not None and not (args.compact and args.fetch):
            parser.error("--warp256-archive requires --compact --fetch")
        if args.self_test:
            if args.compact:
                parser.error("--compact is not used with --self-test")
            _self_test()
            return 0
        if args.output_root is None:
            parser.error("--output-root is required for acquisition and verification")
        if args.bootstrap_pins is not None:
            if args.compact:
                parser.error("--compact is not used with --bootstrap-pins")
            return _bootstrap(args.output_root, args.bootstrap_pins)
        if args.fetch:
            if args.compact:
                return _compact_fetch(args.output_root, archive_value=args.warp256_archive)
            return _fetch(args.output_root)
        if args.compact:
            return _compact_verify_local(args.output_root)
        return _verify_local(args.output_root)
    except AADBError as exc:
        print(f"FAIL {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
