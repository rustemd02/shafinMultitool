#!/usr/bin/env python3
"""Acquire the pinned EVA research source into an external data root.

The adapter is deliberately source-specific.  It only downloads the fixed
raw.githubusercontent.com objects recorded in the repository manifest.  Raw
media and upstream CSVs never enter Git; the generated JSONL files contain
metadata only and remain research-only.
"""

from __future__ import annotations

import argparse
import filecmp
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile
from typing import Any, Callable, Iterable, Mapping, Sequence


ROOT = Path(__file__).resolve().parents[2]
INTAKE_SCRIPT = ROOT / "tools" / "dataset" / "camera_source_intake.py"
SOURCE_ID = "eva_official"
SOURCE_REPOSITORY = "https://github.com/kang-gnak/eva-dataset"
SOURCE_COMMIT = "fb40a9f1abe4be96b69229aaac3d0838a2e1d31c"
RAW_BASE_URL = f"https://raw.githubusercontent.com/kang-gnak/eva-dataset/{SOURCE_COMMIT}"

# These are source pins, not user-provided URLs.  GitHub's displayed SHA-1 is
# the Git blob SHA-1, so verification includes the ``blob <size>\0`` prefix.
SEGMENT_SPECS: tuple[dict[str, Any], ...] = (
    {
        "name": "EVA_together.zip.001",
        "url": f"{RAW_BASE_URL}/images/EVA_together.zip.001",
        "size_bytes": 103809024,
        "git_blob_sha1": "2354fe49331340243d14d369a32639832bc3a6ab",
    },
    {
        "name": "EVA_together.zip.002",
        "url": f"{RAW_BASE_URL}/images/EVA_together.zip.002",
        "size_bytes": 103809024,
        "git_blob_sha1": "89e06e022c205dec1c7725025a4a1e241a06ecae",
    },
    {
        "name": "EVA_together.zip.003",
        "url": f"{RAW_BASE_URL}/images/EVA_together.zip.003",
        "size_bytes": 103809024,
        "git_blob_sha1": "6cc9ae0898ac294d2eaabbf785d968b7f9d04132",
    },
    {
        "name": "EVA_together.zip.004",
        "url": f"{RAW_BASE_URL}/images/EVA_together.zip.004",
        "size_bytes": 103809024,
        "git_blob_sha1": "1f9462cff532120aedd6460730c729d49ccb741c",
    },
    {
        "name": "EVA_together.zip.005",
        "url": f"{RAW_BASE_URL}/images/EVA_together.zip.005",
        "size_bytes": 103809024,
        "git_blob_sha1": "4b60fdb84bcef614aaa30f8b3d46818ef5efa42a",
    },
    {
        "name": "EVA_together.zip.006",
        "url": f"{RAW_BASE_URL}/images/EVA_together.zip.006",
        "size_bytes": 103809024,
        "git_blob_sha1": "c6aa6ef53537171c49169c9ffb5992e568be2426",
    },
    {
        "name": "EVA_together.zip.007",
        "url": f"{RAW_BASE_URL}/images/EVA_together.zip.007",
        "size_bytes": 72385748,
        "git_blob_sha1": "0a4a3fbbf0f2b6c699766dbfae65b493118ee185",
    },
)

METADATA_SPECS: tuple[dict[str, Any], ...] = (
    {
        "path": "data/image_content_category.csv",
        "url": f"{RAW_BASE_URL}/data/image_content_category.csv",
        "size_bytes": 65017,
        "git_blob_sha1": "ae3c4d0b6a3f392a7a5720d98dca9fa90a61dea2",
    },
    {
        "path": "data/region_index.csv",
        "url": f"{RAW_BASE_URL}/data/region_index.csv",
        "size_bytes": 4067,
        "git_blob_sha1": "787dddb6c1151f2b9a73f3d9d70a91ea264322d4",
    },
    {
        "path": "data/users.csv",
        "url": f"{RAW_BASE_URL}/data/users.csv",
        "size_bytes": 60341,
        "git_blob_sha1": "20092e99959adaf2e4a2ecdfc6a7eb16f083ba5c",
    },
    {
        "path": "data/votes.csv",
        "url": f"{RAW_BASE_URL}/data/votes.csv",
        "size_bytes": 52101842,
        "git_blob_sha1": "35120be0a0a4b8acfdf00dd4148ecd91de8ffcd4",
    },
    {
        "path": "data/votes_filtered.csv",
        "url": f"{RAW_BASE_URL}/data/votes_filtered.csv",
        "size_bytes": 6803205,
        "git_blob_sha1": "2a6ab9249f26603fcb8267abc962ef7c437159b6",
    },
)

DOCUMENT_SPECS: tuple[dict[str, Any], ...] = (
    {
        "path": "readme.md",
        "url": f"{RAW_BASE_URL}/readme.md",
        "size_bytes": 3696,
        "git_blob_sha1": "3901b335f2738630ec9c78e762d98a091b8bc65f",
    },
    {
        "path": "LICENSE",
        "url": f"{RAW_BASE_URL}/LICENSE",
        "size_bytes": 7048,
        "git_blob_sha1": "0e259d42c996742e9e3cba14c677129b2c1b6311",
    },
)

MAX_ZIP_MEMBERS = 100_000
MAX_ZIP_UNCOMPRESSED_BYTES = 2_000_000_000
MAX_DOWNLOAD_ATTEMPTS = 12
IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png"}
RAW_MANIFEST_FIELDS = ["image_id", "path"]


class EVAError(ValueError):
    """Fail-closed, user-facing acquisition error."""


def _json_line(value: Any) -> str:
    return json.dumps(value, allow_nan=False, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _jsonl_bytes(rows: Iterable[Mapping[str, Any]]) -> bytes:
    return b"".join((_json_line(dict(row)) + "\n").encode("utf-8") for row in rows)


def _external_root(value: Path, *, create: bool = True) -> Path:
    root = Path(value).expanduser().resolve()
    repository = ROOT.resolve()
    if root == repository or repository in root.parents or root in repository.parents:
        raise EVAError("data root must be outside the repository and its ancestors")
    if create:
        try:
            root.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            raise EVAError("cannot create external data root") from exc
    if not root.is_dir() or root.is_symlink():
        raise EVAError("data root must be a directory")
    return root


def _safe_relative(root: Path, value: str) -> Path:
    if not isinstance(value, str) or not value or "\x00" in value:
        raise EVAError("asset path must be a non-empty string")
    normalized = value.replace("\\", "/")
    parts = PurePosixPath(normalized).parts
    if not parts or PurePosixPath(normalized).is_absolute() or any(part in ("", ".", "..") for part in parts):
        raise EVAError("asset path is not safe")
    if ":" in parts[0]:
        raise EVAError("asset path has a drive prefix")
    current = root
    for part in parts[:-1]:
        current /= part
        if current.is_symlink():
            raise EVAError("asset path uses a symlink parent")
    return root.joinpath(*parts)


def _ensure_directory(path: Path) -> Path:
    """Create a fixed directory without following any symlink component."""

    path = Path(path)
    missing: list[Path] = []
    current = path
    while True:
        try:
            info = current.lstat()
        except FileNotFoundError:
            missing.append(current)
            parent = current.parent
            if parent == current:
                raise EVAError(f"cannot find parent for directory {path}")
            current = parent
            continue
        except OSError as exc:
            raise EVAError(f"cannot inspect directory {path}") from exc
        if stat.S_ISLNK(info.st_mode):
            raise EVAError(f"directory path uses a symlink: {current}")
        if not stat.S_ISDIR(info.st_mode):
            raise EVAError(f"directory path is not a directory: {current}")
        break
    for directory in reversed(missing):
        try:
            directory.mkdir()
            info = directory.lstat()
        except OSError as exc:
            raise EVAError(f"cannot create directory {directory}") from exc
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
            raise EVAError(f"created directory is not safe: {directory}")
    return path


def _fixed_directory(root: Path, relative: str, *, create: bool = False, allow_missing: bool = False) -> Path:
    path = _safe_relative(root, relative)
    if path.is_symlink():
        raise EVAError(f"fixed directory is a symlink: {relative}")
    if not path.exists():
        if not create and not allow_missing:
            raise EVAError(f"fixed directory is missing: {relative}")
        if create:
            _ensure_directory(path)
        return path
    try:
        info = path.lstat()
    except OSError as exc:
        raise EVAError(f"cannot inspect fixed directory: {relative}") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
        raise EVAError(f"fixed directory is not a regular directory: {relative}")
    return path


def _fixed_file(root: Path, relative: str, *, create_parent: bool = False) -> Path:
    path = _safe_relative(root, relative)
    parent_relative = PurePosixPath(relative.replace("\\", "/")).parent
    if str(parent_relative) not in ("", "."):
        _fixed_directory(root, parent_relative.as_posix(), create=create_parent)
    elif not root.is_dir() or root.is_symlink():
        raise EVAError("data root is not a safe directory")
    if path.is_symlink():
        raise EVAError(f"fixed file is a symlink: {relative}")
    if path.exists() and not path.is_file():
        raise EVAError(f"fixed file is not a regular file: {relative}")
    return path


def _file_size_and_blob_sha1(path: Path) -> tuple[int, str]:
    try:
        info = path.lstat()
    except OSError as exc:
        raise EVAError(f"cannot inspect {path.name}") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise EVAError(f"{path.name} is not a regular file")
    size = info.st_size
    digest = hashlib.sha1(f"blob {size}\0".encode("ascii"))
    try:
        with path.open("rb") as stream:
            while chunk := stream.read(1024 * 1024):
                digest.update(chunk)
    except OSError as exc:
        raise EVAError(f"cannot read {path.name}") from exc
    return size, digest.hexdigest()


def _sha256_file(path: Path) -> str:
    try:
        info = path.lstat()
    except OSError as exc:
        raise EVAError(f"cannot inspect {path.name}") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise EVAError(f"{path.name} is not a regular file")
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            while chunk := stream.read(1024 * 1024):
                digest.update(chunk)
    except OSError as exc:
        raise EVAError(f"cannot read {path.name}") from exc
    return digest.hexdigest()


def _matches_spec(path: Path, spec: Mapping[str, Any]) -> bool:
    try:
        size, digest = _file_size_and_blob_sha1(path)
    except EVAError:
        return False
    return size == spec["size_bytes"] and digest == spec["git_blob_sha1"]


def _assert_fixed_url(url: str) -> None:
    if not isinstance(url, str) or not url.startswith(RAW_BASE_URL + "/"):
        raise EVAError("adapter URL is not an allowlisted pinned raw URL")
    if any(token in url for token in ("?", "#", "..")):
        raise EVAError("adapter URL contains an unsafe component")


def _unlink_known(path: Path) -> None:
    if path.is_symlink():
        raise EVAError(f"refusing to remove symlink {path.name}")
    if path.exists():
        if not path.is_file():
            raise EVAError(f"refusing to remove non-file {path.name}")
        path.unlink()


def _validate_partial_download(part: Path, spec: Mapping[str, Any]) -> None:
    if part.is_symlink():
        raise EVAError(f"refusing symlink partial {part.name}")
    try:
        info = part.lstat()
    except FileNotFoundError:
        return
    except OSError as exc:
        raise EVAError(f"cannot inspect partial download: {part.name}") from exc
    if not stat.S_ISREG(info.st_mode):
        raise EVAError(f"partial download is not a regular file: {part.name}")
    if info.st_size > spec["size_bytes"] or (
        info.st_size == spec["size_bytes"] and not _matches_spec(part, spec)
    ):
        _unlink_known(part)


def _download(spec: Mapping[str, Any], destination: Path, runner: Callable[..., Any] = subprocess.run) -> Path:
    """Download one fixed asset, retaining a resumable ``.part`` on failure."""

    _assert_fixed_url(spec["url"])
    _ensure_directory(destination.parent)
    if destination.is_symlink():
        raise EVAError(f"refusing symlink destination {destination.name}")
    if destination.exists() and _matches_spec(destination, spec):
        return destination
    if destination.exists():
        _unlink_known(destination)

    part = Path(f"{destination}.part")
    if part.is_symlink():
        raise EVAError(f"refusing symlink partial {part.name}")
    if part.exists():
        if not part.is_file():
            raise EVAError(f"partial download is not a regular file: {part.name}")
        if _matches_spec(part, spec):
            os.replace(part, destination)
            return destination
        if part.stat().st_size > spec["size_bytes"] or (
            part.stat().st_size == spec["size_bytes"] and not _matches_spec(part, spec)
        ):
            _unlink_known(part)

    command = [
        "curl",
        "--fail",
        "--location",
        "--proto",
        "=https",
        "--proto-redir",
        "=https",
        "--continue-at",
        "-",
        "--output",
        str(part),
        spec["url"],
    ]
    for attempt in range(MAX_DOWNLOAD_ATTEMPTS):
        try:
            runner(command, check=True)
        except (OSError, subprocess.CalledProcessError) as exc:
            _validate_partial_download(part, spec)
            if _matches_spec(part, spec):
                os.replace(part, destination)
                return destination
            if attempt + 1 < MAX_DOWNLOAD_ATTEMPTS:
                continue
            raise EVAError(f"curl failed for {spec['url'].rsplit('/', 1)[-1]} after {MAX_DOWNLOAD_ATTEMPTS} attempts") from exc
        if _matches_spec(part, spec):
            os.replace(part, destination)
            return destination
        _validate_partial_download(part, spec)
        if attempt + 1 == MAX_DOWNLOAD_ATTEMPTS:
            raise EVAError(f"download verification failed for {spec['url'].rsplit('/', 1)[-1]}")
    raise EVAError(f"download failed for {spec['url'].rsplit('/', 1)[-1]}")


def _segment_path(root: Path, spec: Mapping[str, Any]) -> Path:
    return _fixed_file(root, f"archives/{spec['name']}", create_parent=True)


def _zip_member_parts(name: str) -> tuple[str, ...]:
    if not isinstance(name, str) or not name or "\x00" in name:
        raise EVAError("ZIP member has an unsafe name")
    normalized = name.replace("\\", "/")
    path = PurePosixPath(normalized)
    parts = path.parts
    if path.is_absolute() or not parts or any(part in ("", ".", "..") for part in parts):
        raise EVAError(f"ZIP member escapes staging: {name!r}")
    if ":" in parts[0]:
        raise EVAError(f"ZIP member has a drive prefix: {name!r}")
    return parts


def _is_zip_symlink(info: zipfile.ZipInfo) -> bool:
    mode = (info.external_attr >> 16) & 0xFFFF
    return stat.S_ISLNK(mode)


def _inspect_zip(archive_path: Path) -> list[zipfile.ZipInfo]:
    try:
        with zipfile.ZipFile(archive_path, "r") as archive:
            infos = archive.infolist()
            if len(infos) > MAX_ZIP_MEMBERS:
                raise EVAError("ZIP member-count guard exceeded")
            total = 0
            seen: set[str] = set()
            for info in infos:
                parts = _zip_member_parts(info.filename)
                if _is_zip_symlink(info):
                    raise EVAError(f"ZIP symlink member is not allowed: {info.filename}")
                if not info.is_dir():
                    if info.file_size < 0 or info.file_size > MAX_ZIP_UNCOMPRESSED_BYTES:
                        raise EVAError("ZIP member-size guard exceeded")
                    total += info.file_size
                    if total > MAX_ZIP_UNCOMPRESSED_BYTES:
                        raise EVAError("ZIP uncompressed-size guard exceeded")
                    image_parts = parts[1:] if parts[0] == "EVA_together" else parts
                    if not image_parts or Path(image_parts[-1]).suffix.lower() not in IMAGE_SUFFIXES:
                        raise EVAError(f"unexpected non-image ZIP member: {info.filename}")
                    relative = PurePosixPath(*image_parts).as_posix()
                    if relative in seen:
                        raise EVAError(f"duplicate ZIP image member: {relative}")
                    seen.add(relative)
            try:
                bad_member = archive.testzip()
            except (OSError, RuntimeError, zipfile.BadZipFile) as exc:
                raise EVAError("ZIP integrity check failed") from exc
            if bad_member is not None:
                raise EVAError(f"ZIP CRC check failed: {bad_member}")
            return infos
    except EVAError:
        raise
    except (OSError, zipfile.BadZipFile, RuntimeError) as exc:
        raise EVAError("merged file is not a valid ZIP") from exc


def _concatenate_segments(
    root: Path,
    specs: Sequence[Mapping[str, Any]] = SEGMENT_SPECS,
    runner: Callable[..., Any] = subprocess.run,
) -> tuple[Path, list[Path]]:
    archive_dir = _fixed_directory(root, "archives", create=True)
    segment_paths = [_download(spec, _segment_path(root, spec), runner) for spec in specs]
    merged = archive_dir / "EVA_together.zip"
    expected_size = sum(int(spec["size_bytes"]) for spec in specs)
    if merged.is_symlink():
        raise EVAError("refusing symlink merged ZIP")
    # There is no pinned digest for the merged object.  Even a same-sized,
    # CRC-valid ZIP is untrusted; rebuild it from the verified segments.
    if merged.exists():
        _unlink_known(merged)

    temporary = Path(f"{merged}.part")
    _unlink_known(temporary)
    try:
        with temporary.open("wb") as output:
            for segment in segment_paths:
                with segment.open("rb") as source:
                    shutil.copyfileobj(source, output, length=1024 * 1024)
            output.flush()
            os.fsync(output.fileno())
        if temporary.stat().st_size != expected_size:
            raise EVAError("concatenated ZIP has an unexpected size")
        os.replace(temporary, merged)
        _inspect_zip(merged)
    except EVAError:
        _unlink_known(temporary)
        raise
    except (OSError, zipfile.BadZipFile) as exc:
        _unlink_known(temporary)
        raise EVAError("cannot concatenate or verify EVA ZIP") from exc
    return merged, segment_paths


def _promote_images(stage: Path, target: Path) -> None:
    if target.is_symlink():
        raise EVAError("image destination is a symlink")
    if not target.exists():
        os.replace(stage, target)
        return
    if not target.is_dir():
        raise EVAError("image destination is not a directory")
    # A previous interrupted promotion may leave a partial directory.  Keep
    # equal files and move only absent staged files; conflicting user files or
    # arbitrary pre-existing images are never attested or overwritten.
    staged_files = sorted((path for path in stage.rglob("*") if path.is_file()), key=lambda path: path.as_posix())
    staged_relative = {path.relative_to(stage) for path in staged_files}
    existing_relative: set[Path] = set()
    for existing in target.rglob("*"):
        if existing.is_symlink():
            raise EVAError("image destination contains a symlink")
        if existing.is_file():
            existing_relative.add(existing.relative_to(target))
        elif not existing.is_dir():
            raise EVAError("image destination contains a non-regular entry")
    unexpected = existing_relative - staged_relative
    if unexpected:
        raise EVAError(f"conflicting existing image: {sorted(unexpected)[0].as_posix()}")
    for staged in staged_files:
        relative = staged.relative_to(stage)
        destination = target / relative
        _ensure_directory(destination.parent)
        current = destination.parent
        while current != target:
            if current.is_symlink():
                raise EVAError("image destination contains a symlink parent")
            current = current.parent
        if destination.exists():
            if destination.is_symlink() or not destination.is_file() or not filecmp.cmp(staged, destination, shallow=False):
                raise EVAError(f"conflicting existing image: {relative.as_posix()}")
            staged.unlink()
        else:
            os.replace(staged, destination)
    for directory in sorted((path for path in stage.rglob("*") if path.is_dir()), key=lambda path: len(path.parts), reverse=True):
        directory.rmdir()
    stage.rmdir()


def _extract_images(archive_path: Path, target: Path) -> list[str]:
    infos = _inspect_zip(archive_path)
    _ensure_directory(target.parent)
    if target.is_symlink() or (target.exists() and not target.is_dir()):
        raise EVAError("image destination is not a safe directory")
    stage = target.parent / ".eva-images-staging"
    if stage.is_symlink():
        raise EVAError("image staging path is a symlink")
    if stage.exists():
        if not stage.is_dir():
            raise EVAError("image staging path is not a directory")
        shutil.rmtree(stage)
    _ensure_directory(stage)
    image_ids: list[str] = []
    seen_ids: set[str] = set()
    try:
        with zipfile.ZipFile(archive_path, "r") as archive:
            for info in infos:
                if info.is_dir():
                    continue
                parts = _zip_member_parts(info.filename)
                image_parts = parts[1:] if parts[0] == "EVA_together" else parts
                image_id = Path(image_parts[-1]).stem
                if not image_id or image_id in seen_ids:
                    raise EVAError(f"duplicate or empty EVA image id: {info.filename}")
                relative = PurePosixPath(*image_parts)
                destination = stage.joinpath(*relative.parts)
                destination.parent.mkdir(parents=True, exist_ok=True)
                current = stage
                for part in relative.parts[:-1]:
                    current /= part
                    if current.is_symlink():
                        raise EVAError("ZIP extraction encountered a symlink parent")
                written = 0
                with archive.open(info, "r") as source, destination.open("wb") as output:
                    while chunk := source.read(1024 * 1024):
                        output.write(chunk)
                        written += len(chunk)
                if written != info.file_size:
                    raise EVAError(f"ZIP member size changed while extracting: {info.filename}")
                image_ids.append(image_id)
                seen_ids.add(image_id)
        _promote_images(stage, target)
    except EVAError:
        if stage.exists() and not stage.is_symlink():
            shutil.rmtree(stage)
        raise
    except (OSError, RuntimeError, zipfile.BadZipFile) as exc:
        if stage.exists() and not stage.is_symlink():
            shutil.rmtree(stage)
        raise EVAError("cannot safely extract EVA images") from exc
    return sorted(image_ids)


def _image_rows(root: Path) -> list[dict[str, str]]:
    images = _fixed_directory(root, "images")
    rows: list[dict[str, str]] = []
    seen_ids: set[str] = set()
    for path in sorted(images.rglob("*"), key=lambda value: value.as_posix()):
        if path.is_symlink():
            raise EVAError("images directory contains a symlink")
        if path.is_dir():
            continue
        if not path.is_file() or path.suffix.lower() not in IMAGE_SUFFIXES:
            raise EVAError(f"images directory contains an unexpected file: {path.name}")
        image_id = path.stem
        if not image_id or image_id in seen_ids:
            raise EVAError(f"duplicate image id: {image_id}")
        relative = path.relative_to(root).as_posix()
        rows.append({"image_id": image_id, "path": relative})
        seen_ids.add(image_id)
    if not rows:
        raise EVAError("images directory contains no images")
    rows.sort(key=lambda row: (row["image_id"], row["path"]))
    return rows


def _atomic_write_jsonl(path: Path, rows: Iterable[Mapping[str, Any]]) -> str:
    _ensure_directory(path.parent)
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise EVAError(f"manifest destination is not a regular file: {path.name}")
    temporary: Path | None = None
    try:
        fd, name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
        temporary = Path(name)
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            for row in rows:
                stream.write(_json_line(dict(row)) + "\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    except (OSError, ValueError) as exc:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
        raise EVAError(f"cannot atomically write {path.name}") from exc
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _run_verify_local(root: Path) -> str:
    manifest = _fixed_file(root, "raw-manifest.jsonl")
    if not manifest.is_file():
        raise EVAError("raw manifest is missing")
    output = _fixed_file(root, "inventory.jsonl")
    command = [
        sys.executable,
        str(INTAKE_SCRIPT),
        "verify-local",
        "--source-id",
        SOURCE_ID,
        "--data-root",
        str(root),
        "--manifest",
        str(manifest),
        "--output",
        str(output),
    ]
    result = subprocess.run(command, cwd=str(ROOT), capture_output=True, text=True, check=False)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "verify-local failed").strip().splitlines()[-1]
        raise EVAError(detail)
    if result.stdout.strip():
        print(result.stdout.strip())
    return output.read_text(encoding="utf-8")


def _receipt_allows_reuse(root: Path) -> bool:
    """Allow archive-free reuse only for a matching, content-attested batch."""

    try:
        images = _fixed_directory(root, "images", allow_missing=True)
        receipt_path = _fixed_file(root, "receipts/eva-source-receipt.json")
        raw_path = _fixed_file(root, "raw-manifest.jsonl")
        inventory_path = _fixed_file(root, "inventory.jsonl")
        if not images.is_dir() or not raw_path.is_file() or not inventory_path.is_file() or not receipt_path.is_file():
            return False
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        if not isinstance(receipt, dict):
            return False
        if receipt.get("source_id") != SOURCE_ID or receipt.get("commit") != SOURCE_COMMIT:
            return False
        raw_receipt = receipt.get("raw_manifest")
        inventory_receipt = receipt.get("inventory")
        if not isinstance(raw_receipt, dict) or not isinstance(inventory_receipt, dict):
            return False
        if raw_receipt.get("path") != "raw-manifest.jsonl" or raw_receipt.get("fields") != RAW_MANIFEST_FIELDS:
            return False
        if inventory_receipt.get("path") != "inventory.jsonl":
            return False
        raw_sha256 = raw_receipt.get("sha256")
        inventory_sha256 = inventory_receipt.get("sha256")
        if (
            not isinstance(raw_sha256, str)
            or len(raw_sha256) != 64
            or raw_sha256 != raw_sha256.lower()
            or not isinstance(inventory_sha256, str)
            or len(inventory_sha256) != 64
            or inventory_sha256 != inventory_sha256.lower()
        ):
            return False
        if _sha256_file(raw_path) != raw_sha256 or _sha256_file(inventory_path) != inventory_sha256:
            return False
        rows = _image_rows(root)
        if raw_path.read_bytes() != _jsonl_bytes(rows):
            return False
        _run_verify_local(root)
        return _sha256_file(inventory_path) == inventory_sha256
    except (EVAError, OSError, UnicodeError, json.JSONDecodeError, TypeError):
        return False


def _verified_segment_paths(root: Path) -> list[Path]:
    """Return all pinned segments only when the complete set is verified."""

    archive_dir = _fixed_directory(root, "archives", allow_missing=True)
    if not archive_dir.is_dir():
        return []
    paths: list[Path] = []
    for spec in SEGMENT_SPECS:
        path = _fixed_file(root, f"archives/{spec['name']}")
        if not path.exists() or not _matches_spec(path, spec):
            return []
        paths.append(path)
    return paths


def _cleanup_archives(root: Path, merged: Path | None, segment_paths: Sequence[Path], keep_archives: bool) -> None:
    if merged is not None or segment_paths:
        _fixed_directory(root, "archives")
    if merged is not None and merged.exists():
        _unlink_known(merged)
    if not keep_archives:
        for segment in segment_paths:
            if segment.exists():
                _unlink_known(segment)


def _write_receipt(root: Path, *, rows: Sequence[Mapping[str, Any]], archives_retained: bool) -> None:
    receipts_dir = _fixed_directory(root, "receipts", create=True)
    raw_manifest = _fixed_file(root, "raw-manifest.jsonl")
    inventory = _fixed_file(root, "inventory.jsonl")
    receipt_path = _fixed_file(root, "receipts/eva-source-receipt.json", create_parent=True)
    receipt = {
        "source_id": SOURCE_ID,
        "repository": SOURCE_REPOSITORY,
        "commit": SOURCE_COMMIT,
        "intake_tier": "research_only",
        "human_gold": False,
        "release_admissible": False,
        "underlying_ava_image_rights": "unresolved",
        "repository_license": "CC0-1.0; this does not resolve underlying AVA image rights",
        "raw_manifest": {
            "path": "raw-manifest.jsonl",
            "sha256": _sha256_file(raw_manifest),
            "records": len(rows),
            "fields": list(RAW_MANIFEST_FIELDS),
        },
        "inventory": {
            "path": "inventory.jsonl",
            "sha256": _sha256_file(inventory),
        },
        "archives_retained": archives_retained,
        "votes_preserved_without_action_labels": ["data/votes.csv", "data/votes_filtered.csv"],
    }
    temporary: Path | None = None
    try:
        fd, name = tempfile.mkstemp(prefix=f".{receipt_path.name}.", suffix=".tmp", dir=receipts_dir)
        temporary = Path(name)
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(_json_line(receipt) + "\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, receipt_path)
    except (OSError, ValueError) as exc:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
        raise EVAError("cannot atomically write EVA receipt") from exc


def _fetch(root_value: Path, *, keep_archives: bool = False, runner: Callable[..., Any] = subprocess.run) -> int:
    root = _external_root(root_value)
    _fixed_directory(root, "archives", create=True)
    _fixed_directory(root, "data", create=True)
    _fixed_directory(root, "docs", create=True)
    _fixed_directory(root, "receipts", create=True)
    images = _fixed_directory(root, "images", allow_missing=True)
    raw_manifest = _fixed_file(root, "raw-manifest.jsonl", create_parent=True)
    inventory = _fixed_file(root, "inventory.jsonl", create_parent=True)

    for spec in METADATA_SPECS:
        _download(spec, _fixed_file(root, spec["path"], create_parent=True), runner)
    for spec in DOCUMENT_SPECS:
        document_name = Path(spec["path"]).name
        _download(spec, _fixed_file(root, f"docs/{document_name}", create_parent=True), runner)

    merged: Path | None = None
    segment_paths: list[Path] = []
    reuse = _receipt_allows_reuse(root)
    existing_segments = _verified_segment_paths(root)
    if reuse and keep_archives and len(existing_segments) != len(SEGMENT_SPECS):
        reuse = False
    if reuse:
        rows = _image_rows(root)
        candidate = _fixed_file(root, "archives/EVA_together.zip")
        if candidate.exists():
            # No whole-archive pin exists; cleanup must not preserve or trust it.
            merged = candidate
        segment_paths = existing_segments
    else:
        merged, segment_paths = _concatenate_segments(root, SEGMENT_SPECS, runner)
        _extract_images(merged, images)
        rows = _image_rows(root)
        _atomic_write_jsonl(raw_manifest, rows)
        _run_verify_local(root)
    _cleanup_archives(root, merged, segment_paths, keep_archives)
    _write_receipt(
        root,
        rows=rows,
        archives_retained=bool(_verified_segment_paths(root)),
    )
    print(f"PASS fetch-eva source_id={SOURCE_ID} records={len(rows)} keep_archives={str(keep_archives).lower()}")
    return 0


def _self_test() -> None:
    try:
        from PIL import Image
    except ImportError as exc:
        raise EVAError("Pillow is required for the local self-test") from exc

    with tempfile.TemporaryDirectory(prefix="fetch-eva-") as temp_dir:
        base = Path(temp_dir)
        root = base / "external"
        root.mkdir()

        image_bytes: dict[str, bytes] = {}
        for image_id, color in (("2", (20, 40, 80)), ("10", (80, 40, 20))):
            image = io.BytesIO()
            Image.new("RGB", (3, 2), color).save(image, format="JPEG")
            image_bytes[image_id] = image.getvalue()
        archive_bytes = io.BytesIO()
        with zipfile.ZipFile(archive_bytes, "w", compression=zipfile.ZIP_STORED) as archive:
            for image_id in ("2", "10"):
                archive.writestr(f"EVA_together/{image_id}.jpg", image_bytes[image_id])
        archive_payload = archive_bytes.getvalue()
        split_payloads = (archive_payload[: len(archive_payload) // 2], archive_payload[len(archive_payload) // 2 :])
        fixture_specs = tuple(
            {
                "name": f"EVA_together.zip.00{index}",
                "url": f"{RAW_BASE_URL}/fixture/EVA_together.zip.00{index}",
                "size_bytes": len(payload),
                "git_blob_sha1": _git_blob_sha1_bytes(payload),
            }
            for index, payload in enumerate(split_payloads, 1)
        )
        payload_by_name = {spec["name"]: payload for spec, payload in zip(fixture_specs, split_payloads)}
        calls: list[list[str]] = []

        def fake_curl(command: list[str], *, check: bool) -> None:
            calls.append(command)
            output = Path(command[command.index("--output") + 1])
            payload = payload_by_name[Path(command[-1]).name]
            offset = output.stat().st_size if output.exists() else 0
            assert offset <= len(payload)
            with output.open("ab") as stream:
                stream.write(payload[offset:])

        first_part = _segment_path(root, fixture_specs[0]).with_name(f"{fixture_specs[0]['name']}.part")
        first_part.parent.mkdir(parents=True, exist_ok=True)
        first_payload = split_payloads[0]
        first_part.write_bytes(first_payload[: max(1, len(first_payload) // 3)])
        segment_paths = [_download(spec, _segment_path(root, spec), fake_curl) for spec in fixture_specs]
        assert len(calls) == 2 and all(
            "--continue-at" in call
            and "--proto-redir" in call
            and "--retry" not in call
            and "--retry-all-errors" not in call
            for call in calls
        )
        before_rerun = len(calls)
        assert [_download(spec, _segment_path(root, spec), fake_curl) for spec in fixture_specs] == segment_paths
        assert len(calls) == before_rerun

        flaky_payload = b"outer-python-retry-preserves-progress"
        flaky_spec = {
            "name": "outer-retry.bin",
            "url": f"{RAW_BASE_URL}/fixture/outer-retry.bin",
            "size_bytes": len(flaky_payload),
            "git_blob_sha1": _git_blob_sha1_bytes(flaky_payload),
        }
        flaky_destination = root / "archives" / flaky_spec["name"]
        flaky_offsets: list[int] = []
        flaky_commands: list[list[str]] = []
        prefix_size = max(1, len(flaky_payload) // 2)

        def flaky_curl(command: list[str], *, check: bool) -> None:
            flaky_commands.append(command)
            output = Path(command[command.index("--output") + 1])
            offset = output.stat().st_size if output.exists() else 0
            flaky_offsets.append(offset)
            with output.open("ab") as stream:
                if len(flaky_offsets) == 1:
                    assert offset == 0
                    stream.write(flaky_payload[:prefix_size])
                    raise subprocess.CalledProcessError(18, command)
                assert offset == prefix_size
                stream.write(flaky_payload[offset:])

        assert _download(flaky_spec, flaky_destination, flaky_curl) == flaky_destination
        assert flaky_offsets == [0, prefix_size]
        assert flaky_destination.read_bytes() == flaky_payload
        assert not Path(f"{flaky_destination}.part").exists()
        assert all(
            "--proto-redir" in command
            and "--retry" not in command
            and "--retry-all-errors" not in command
            for command in flaky_commands
        )

        wrong_archive = io.BytesIO()
        with zipfile.ZipFile(wrong_archive, "w", compression=zipfile.ZIP_STORED) as archive:
            for image_id, wrong_id in (("2", "10"), ("10", "2")):
                archive.writestr(f"EVA_together/{image_id}.jpg", image_bytes[wrong_id])
        wrong_payload = wrong_archive.getvalue()
        assert wrong_payload != archive_payload and len(wrong_payload) == len(archive_payload)
        archive_dir = _fixed_directory(root, "archives", create=True)
        (archive_dir / "EVA_together.zip").write_bytes(wrong_payload)
        merged, _ = _concatenate_segments(root, fixture_specs, fake_curl)
        assert merged.read_bytes() == archive_payload
        assert _inspect_zip(merged)
        extracted_ids = _extract_images(merged, root / "images")
        assert extracted_ids == ["10", "2"]
        rows = _image_rows(root)
        assert rows == [
            {"image_id": "10", "path": "images/10.jpg"},
            {"image_id": "2", "path": "images/2.jpg"},
        ]
        first_digest = _atomic_write_jsonl(root / "raw-manifest.jsonl", rows)
        second_digest = _atomic_write_jsonl(root / "raw-manifest-rerun.jsonl", rows)
        assert first_digest == second_digest
        _fixed_directory(root, "receipts", create=True)
        (root / "receipts" / "keep.json").write_text("keep\n", encoding="utf-8")
        _run_verify_local(root)

        stale_root = base / "stale"
        stale_root.mkdir()
        stale_images = _fixed_directory(stale_root, "images", create=True)
        (stale_images / "forged.jpg").write_bytes(image_bytes["2"])
        _fixed_file(stale_root, "raw-manifest.jsonl", create_parent=True).write_bytes(
            _jsonl_bytes([{"image_id": "forged", "path": "images/forged.jpg"}])
        )
        _fixed_file(stale_root, "inventory.jsonl", create_parent=True).write_text("stale\n", encoding="utf-8")
        assert not _receipt_allows_reuse(stale_root)
        assert not _receipt_allows_reuse(root)
        _write_receipt(root, rows=rows, archives_retained=False)
        assert _receipt_allows_reuse(root)

        receipt_path = _fixed_file(root, "receipts/eva-source-receipt.json")
        valid_receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        receipt_path.write_text(_json_line({**valid_receipt, "commit": "stale"}) + "\n", encoding="utf-8")
        assert not _receipt_allows_reuse(root)
        _write_receipt(root, rows=rows, archives_retained=False)
        raw_manifest_path = _fixed_file(root, "raw-manifest.jsonl")
        original_manifest = raw_manifest_path.read_bytes()
        raw_manifest_path.write_bytes(original_manifest + b"\n")
        assert not _receipt_allows_reuse(root)
        raw_manifest_path.write_bytes(original_manifest)
        assert _receipt_allows_reuse(root)

        receipt_sentinel = base / "receipt-sentinel"
        receipt_sentinel.write_text("untouched\n", encoding="utf-8")
        fixed_receipt_temp = root / "receipts" / ".eva-source-receipt.json.tmp"
        fixed_receipt_temp.symlink_to(receipt_sentinel)
        _write_receipt(root, rows=rows, archives_retained=False)
        assert fixed_receipt_temp.is_symlink() and receipt_sentinel.read_text(encoding="utf-8") == "untouched\n"
        fixed_receipt_temp.unlink()

        reuse_root = base / "reuse"
        reuse_root.mkdir()
        original_segment_specs = SEGMENT_SPECS
        original_metadata_specs = METADATA_SPECS
        original_document_specs = DOCUMENT_SPECS
        try:
            globals()["SEGMENT_SPECS"] = fixture_specs
            globals()["METADATA_SPECS"] = ()
            globals()["DOCUMENT_SPECS"] = ()
            reuse_merged, reuse_segments = _concatenate_segments(reuse_root, fixture_specs, fake_curl)
            _extract_images(reuse_merged, reuse_root / "images")
            reuse_rows = _image_rows(reuse_root)
            _atomic_write_jsonl(reuse_root / "raw-manifest.jsonl", reuse_rows)
            _run_verify_local(reuse_root)
            _cleanup_archives(reuse_root, reuse_merged, reuse_segments, keep_archives=False)
            _write_receipt(
                reuse_root,
                rows=reuse_rows,
                archives_retained=bool(_verified_segment_paths(reuse_root)),
            )
            assert not _verified_segment_paths(reuse_root)

            calls.clear()
            _fetch(reuse_root, keep_archives=False, runner=fake_curl)
            assert calls == []

            _fetch(reuse_root, keep_archives=True, runner=fake_curl)
            assert len(calls) == len(fixture_specs)
            retained_receipt = json.loads(
                _fixed_file(reuse_root, "receipts/eva-source-receipt.json").read_text(encoding="utf-8")
            )
            assert retained_receipt["archives_retained"] is True
            assert len(_verified_segment_paths(reuse_root)) == len(fixture_specs)
        finally:
            globals()["SEGMENT_SPECS"] = original_segment_specs
            globals()["METADATA_SPECS"] = original_metadata_specs
            globals()["DOCUMENT_SPECS"] = original_document_specs

        archive_target = base / "archive-target"
        archive_target.mkdir()
        archive_probe = base / "archive-probe"
        archive_probe.mkdir()
        (archive_probe / "archives").symlink_to(archive_target, target_is_directory=True)
        try:
            _fixed_directory(archive_probe, "archives", create=True)
        except EVAError as exc:
            assert "symlink" in str(exc)
        else:
            raise AssertionError("archives symlink was accepted")

        receipt_probe = base / "receipt-probe"
        receipt_probe.mkdir()
        (receipt_probe / "receipts").symlink_to(archive_target, target_is_directory=True)
        try:
            _fixed_directory(receipt_probe, "receipts", create=True)
        except EVAError as exc:
            assert "symlink" in str(exc)
        else:
            raise AssertionError("receipts symlink was accepted")

        bad_zip = base / "traversal.zip"
        with zipfile.ZipFile(bad_zip, "w") as archive:
            archive.writestr("EVA_together/../escape.jpg", image_bytes["2"])
        try:
            _extract_images(bad_zip, base / "bad-images")
        except EVAError as exc:
            assert "escapes" in str(exc) or "unsafe" in str(exc)
        else:
            raise AssertionError("ZIP traversal was accepted")

        symlink_zip = base / "symlink.zip"
        symlink_info = zipfile.ZipInfo("EVA_together/link.jpg")
        symlink_info.create_system = 3
        symlink_info.external_attr = (stat.S_IFLNK | 0o777) << 16
        with zipfile.ZipFile(symlink_zip, "w") as archive:
            archive.writestr(symlink_info, b"target")
        try:
            _extract_images(symlink_zip, base / "symlink-images")
        except EVAError as exc:
            assert "symlink" in str(exc)
        else:
            raise AssertionError("ZIP symlink was accepted")

        _cleanup_archives(root, merged, segment_paths, keep_archives=False)
        assert not merged.exists() and all(not path.exists() for path in segment_paths)
        assert (root / "images" / "10.jpg").is_file()
        assert (root / "raw-manifest.jsonl").is_file()
        assert (root / "inventory.jsonl").is_file()
        assert (root / "receipts" / "keep.json").is_file()

        for unsafe in (ROOT, ROOT.parent, Path(ROOT.anchor)):
            try:
                _external_root(unsafe)
            except EVAError as exc:
                assert "outside the repository" in str(exc)
            else:
                raise AssertionError("repository-boundary root was accepted")
    print("PASS fetch_eva self-test fake_curl pinned_resume outer_retry_resume proto_redir_no_internal_retry git_blob_sha1 safe_concat rebuilt_merge zip_crc traversal symlink deterministic_manifest verify_local receipt_reuse retention_gate archives_retained_truth stale_attestation safe_receipt_temp archive_dir_guard receipts_dir_guard cleanup repo_boundary")


def _git_blob_sha1_bytes(payload: bytes) -> str:
    digest = hashlib.sha1(f"blob {len(payload)}\0".encode("ascii"))
    digest.update(payload)
    return digest.hexdigest()


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", help="run the network-free fixture self-test")
    subparsers = parser.add_subparsers(dest="command")
    fetch = subparsers.add_parser("fetch", help="fetch the pinned EVA source into an external data root")
    fetch.add_argument("--data-root", type=Path, required=True)
    fetch.add_argument("--keep-archives", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.self_test:
            _self_test()
            return 0
        if args.command == "fetch":
            return _fetch(args.data_root, keep_archives=args.keep_archives)
        _parser().error("choose --self-test or fetch")
    except EVAError as exc:
        print(f"FAIL {exc}", file=sys.stderr)
        return 1
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
