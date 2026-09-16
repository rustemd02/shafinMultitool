#!/usr/bin/env python3
"""Build one deterministic, research-only Stage-2 data ZIP for Colab.

The input roots are already audited paired-corruption outputs.  This tool does
not copy source/control pixels: it admits only each root's receipt, pairs.jsonl,
and the derivative PNGs referenced by that manifest.  The archive is stored
uncompressed so the large PNG payload can be uploaded and extracted without a
second CPU-heavy compression pass.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import tempfile
from typing import Any, Mapping
import zipfile


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DATA_ROOT = Path(
    "~/Documents/XCode/setos-backend/local-data/SETOS/Datasets/"
    "camera-coach/research/paired-corruptions/v1"
).expanduser()
DATA_SCHEMA_ID = "camera-coach-stage2-data-bundle-v1"
DATA_SUMS_SCHEMA_ID = "camera-coach-stage2-data-sha256-v1"
DATA_SCHEMA_VERSION = "1.0.0"
PAIR_SCHEMA_ID = "camera-silver-action-pair-v1"
PAIR_SCHEMA_VERSION = "1.0.0"
RESEARCH_SPLIT = "research_fit"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
PAIR_ID_RE = re.compile(r"^pair_[0-9a-f]{40}$")
IMAGE_NAME_RE = re.compile(r"^pair_[0-9a-f]{40}\.png$")
MAX_MEMBER_BYTES = 16 * 1024 * 1024
MAX_TOTAL_BYTES = 2 * 1024 * 1024 * 1024
MAX_MEMBERS = 20_000
MAX_IMAGE_DIMENSION = 4096
MAX_IMAGE_PIXELS = MAX_IMAGE_DIMENSION * MAX_IMAGE_DIMENSION

ROOT_SPECS = (
    (
        "commons",
        "commons-scale-1000",
        "bab422ec74c47852866ffa37c60ae27121ede045a239683e2969a61d9e2c874a",
    ),
    (
        "eva",
        "eva-fb40a9f1",
        "ec40169d8d58a96c80652365c04e8eeae88ad5fa07e479c445cab47e92d34680",
    ),
    (
        "aadb",
        "aadb-warp256-v1",
        "85ae7d6849895a721d1aceba9df0dd3db0046cc302d4edc6e0470919d7c312ce",
    ),
)


class DataBundleError(ValueError):
    """Raised when an input cannot be admitted into the data bundle."""


def _canonical_json(value: Any) -> str:
    try:
        return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)
    except (TypeError, ValueError, OverflowError, RecursionError) as exc:
        raise DataBundleError("value is not canonical JSON") from exc


def _reject_constant(value: str) -> Any:
    raise DataBundleError(f"non-finite JSON number is not allowed: {value}")


def _read_json(path: Path, label: str) -> tuple[Any, bytes]:
    try:
        payload = path.read_bytes()
    except OSError as exc:
        raise DataBundleError(f"cannot read {label}: {path}") from exc
    try:
        value = json.loads(payload.decode("utf-8"), parse_constant=_reject_constant)
    except DataBundleError:
        raise
    except (UnicodeDecodeError, json.JSONDecodeError, RecursionError) as exc:
        raise DataBundleError(f"{label} is malformed JSON: {path}") from exc
    return value, payload


def _sha256_file(path: Path, label: str) -> tuple[int, str]:
    try:
        info = path.lstat()
    except OSError as exc:
        raise DataBundleError(f"cannot inspect {label}: {path}") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise DataBundleError(f"{label} is not a regular non-symlink file: {path}")
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise DataBundleError(f"cannot read {label}: {path}") from exc
    return info.st_size, digest.hexdigest()


def _assert_no_symlink_components(path: Path) -> None:
    absolute = Path(os.path.abspath(path))
    current = Path(absolute.anchor)
    for part in absolute.parts[1:]:
        current /= part
        try:
            info = current.lstat()
        except FileNotFoundError:
            break
        except OSError as exc:
            raise DataBundleError(f"cannot inspect path component: {current}") from exc
        if stat.S_ISLNK(info.st_mode):
            raise DataBundleError(f"path uses a symlink: {current}")


def _external_directory(value: Path, label: str) -> Path:
    candidate = Path(value).expanduser()
    _assert_no_symlink_components(candidate)
    absolute = Path(os.path.abspath(candidate))
    try:
        info = absolute.lstat()
    except OSError as exc:
        raise DataBundleError(f"cannot inspect {label}: {absolute}") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
        raise DataBundleError(f"{label} must be a regular directory: {absolute}")
    resolved = absolute.resolve(strict=True)
    repository = ROOT.resolve(strict=True)
    if resolved == repository or repository in resolved.parents or resolved in repository.parents:
        raise DataBundleError(f"{label} must be outside the repository")
    return resolved


def _external_output(value: Path) -> Path:
    candidate = Path(value).expanduser()
    _assert_no_symlink_components(candidate)
    absolute = Path(os.path.abspath(candidate))
    if absolute.exists() or absolute.is_symlink():
        raise DataBundleError(f"output already exists or is a symlink: {absolute}")
    parent = absolute.parent
    _assert_no_symlink_components(parent)
    try:
        info = parent.lstat()
    except OSError as exc:
        raise DataBundleError(f"cannot inspect output parent: {parent}") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
        raise DataBundleError(f"output parent must be a regular directory: {parent}")
    repository = ROOT.resolve(strict=True)
    resolved_parent = parent.resolve(strict=True)
    if resolved_parent == repository or repository in resolved_parent.parents or resolved_parent in repository.parents:
        raise DataBundleError("output must be outside the repository")
    return absolute


def _safe_archive_path(value: str, label: str) -> str:
    if not isinstance(value, str) or not value or "\x00" in value or "\\" in value:
        raise DataBundleError(f"{label} is not a safe POSIX path")
    path = PurePosixPath(value)
    if path.is_absolute() or not path.parts or any(part in {"", ".", ".."} for part in path.parts):
        raise DataBundleError(f"{label} is not a safe relative path")
    return path.as_posix()


def _validate_sha(value: Any, label: str) -> str:
    if not isinstance(value, str) or not SHA256_RE.fullmatch(value):
        raise DataBundleError(f"{label} must be a lowercase SHA-256")
    return value


def _validate_receipt(receipt: Any, expected_pairs: int, expected_receipt: str, root_id: str) -> None:
    if not isinstance(receipt, dict):
        raise DataBundleError(f"{root_id} receipt must be an object")
    if receipt.get("schema_id") != "camera-silver-action-pair-receipt-v1" or receipt.get("schema_version") != PAIR_SCHEMA_VERSION:
        raise DataBundleError(f"{root_id} receipt schema is unsupported")
    if receipt.get("research_only") is not True or receipt.get("human_gold") is not False or receipt.get("release_admissible") is not False:
        raise DataBundleError(f"{root_id} crosses the research-only boundary")
    if receipt.get("split") != RESEARCH_SPLIT:
        raise DataBundleError(f"{root_id} receipt split is not {RESEARCH_SPLIT}")
    counts = receipt.get("counts")
    if not isinstance(counts, dict) or counts.get("pairs") != expected_pairs:
        raise DataBundleError(f"{root_id} receipt pair count disagrees with pairs.jsonl")
    output_manifest = receipt.get("output_manifest")
    output_media = receipt.get("output_media")
    if not isinstance(output_manifest, dict) or output_manifest.get("path") != "pairs.jsonl" or output_manifest.get("records") != expected_pairs:
        raise DataBundleError(f"{root_id} receipt manifest binding is invalid")
    if not isinstance(output_media, dict) or output_media.get("files") != expected_pairs or not _validate_sha(output_media.get("aggregate_sha256"), f"{root_id} media aggregate"):
        raise DataBundleError(f"{root_id} receipt media binding is invalid")
    _validate_sha(expected_receipt, f"{root_id} expected receipt")


def _validate_pair(pair: Any, root_id: str, seen: set[str]) -> tuple[str, str, int, int]:
    if not isinstance(pair, dict) or pair.get("schema_id") != PAIR_SCHEMA_ID or pair.get("schema_version") != PAIR_SCHEMA_VERSION:
        raise DataBundleError(f"{root_id} has a pair with an unsupported schema")
    if pair.get("split") != RESEARCH_SPLIT or pair.get("research_only") is not True or pair.get("human_gold") is not False or pair.get("release_admissible") is not False:
        raise DataBundleError(f"{root_id} pair crosses the research-only boundary")
    pair_id = pair.get("pair_id")
    if not isinstance(pair_id, str) or not PAIR_ID_RE.fullmatch(pair_id) or pair_id in seen:
        raise DataBundleError(f"{root_id} pair id is malformed or duplicated")
    derivative = pair.get("derivative")
    if not isinstance(derivative, dict) or derivative.get("format") != "png":
        raise DataBundleError(f"{root_id} derivative metadata is invalid")
    relative_path = derivative.get("relative_path")
    expected_path = f"images/{pair_id}.png"
    if relative_path != expected_path:
        raise DataBundleError(f"{root_id} derivative path is not the canonical pair path")
    _safe_archive_path(relative_path, f"{root_id} derivative path")
    _validate_sha(derivative.get("sha256"), f"{root_id} derivative hash")
    width = derivative.get("width")
    height = derivative.get("height")
    if type(width) is not int or type(height) is not int or not 0 < width <= MAX_IMAGE_DIMENSION or not 0 < height <= MAX_IMAGE_DIMENSION or width * height > MAX_IMAGE_PIXELS:
        raise DataBundleError(f"{root_id} derivative dimensions exceed the safe bound")
    seen.add(pair_id)
    return relative_path, derivative["sha256"], width, height


def _collect_root(root_id: str, root_path: Path, expected_receipt: str) -> dict[str, Any]:
    root = _external_directory(root_path, f"{root_id} pair root")
    expected_top_level = {"images", "pairs.jsonl", "receipt.json"}
    try:
        top_level = {item.name for item in root.iterdir()}
    except OSError as exc:
        raise DataBundleError(f"cannot enumerate {root_id} pair root") from exc
    if top_level != expected_top_level:
        raise DataBundleError(f"{root_id} pair root contains non-admitted files")
    images_dir = root / "images"
    _assert_no_symlink_components(images_dir)
    try:
        info = images_dir.lstat()
    except OSError as exc:
        raise DataBundleError(f"cannot inspect {root_id} images directory") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
        raise DataBundleError(f"{root_id} images is not a regular directory")

    receipt_path = root / "receipt.json"
    receipt_size, receipt_sha = _sha256_file(receipt_path, f"{root_id} receipt")
    if receipt_sha != expected_receipt:
        raise DataBundleError(f"{root_id} receipt SHA-256 mismatch: expected {expected_receipt}, got {receipt_sha}")
    receipt, receipt_bytes = _read_json(receipt_path, f"{root_id} receipt")
    if receipt_size != len(receipt_bytes):
        raise DataBundleError(f"{root_id} receipt changed while reading")

    pairs_path = root / "pairs.jsonl"
    pair_manifest_size, pair_manifest_sha = _sha256_file(pairs_path, f"{root_id} pairs manifest")
    seen: set[str] = set()
    derivatives: dict[str, dict[str, Any]] = {}
    pair_count = 0
    media_aggregate = hashlib.sha256()
    manifest_digest = hashlib.sha256()
    try:
        with pairs_path.open("rb") as stream:
            for line_number, raw_line in enumerate(stream, 1):
                if not raw_line.strip():
                    raise DataBundleError(f"{root_id} pairs.jsonl has a blank line at {line_number}")
                manifest_digest.update(raw_line)
                try:
                    pair = json.loads(raw_line.decode("utf-8"), parse_constant=_reject_constant)
                except DataBundleError:
                    raise
                except (UnicodeDecodeError, json.JSONDecodeError, RecursionError) as exc:
                    raise DataBundleError(f"{root_id} pairs.jsonl line {line_number} is malformed") from exc
                relative_path, digest, width, height = _validate_pair(pair, root_id, seen)
                derivatives[relative_path] = {"sha256": digest, "width": width, "height": height}
                media_aggregate.update(f"{relative_path}\0{digest}\0{width}\0{height}\n".encode("utf-8"))
                pair_count += 1
                if pair_count > MAX_MEMBERS:
                    raise DataBundleError("pair count exceeds archive member ceiling")
    except OSError as exc:
        raise DataBundleError(f"cannot read {root_id} pairs manifest") from exc
    if pair_count == 0:
        raise DataBundleError(f"{root_id} pairs manifest is empty")
    if manifest_digest.hexdigest() != pair_manifest_sha:
        raise DataBundleError(f"{root_id} pairs manifest changed while reading")
    _validate_receipt(receipt, pair_count, expected_receipt, root_id)
    output_manifest = receipt["output_manifest"]
    if output_manifest.get("sha256") != pair_manifest_sha:
        raise DataBundleError(f"{root_id} receipt does not bind pairs.jsonl")
    output_media = receipt["output_media"]
    media_aggregate_sha = media_aggregate.hexdigest()
    if output_media.get("aggregate_sha256") != media_aggregate_sha:
        raise DataBundleError(f"{root_id} receipt does not bind derivative metadata")

    try:
        image_paths = sorted(images_dir.iterdir(), key=lambda item: item.name)
    except OSError as exc:
        raise DataBundleError(f"cannot enumerate {root_id} images") from exc
    if len(image_paths) != pair_count:
        raise DataBundleError(f"{root_id} image count disagrees with pairs.jsonl")
    images: list[dict[str, Any]] = []
    expected_image_names = {PurePosixPath(path).name for path in derivatives}
    media_bytes = 0
    for image_path in image_paths:
        if image_path.name not in expected_image_names or not IMAGE_NAME_RE.fullmatch(image_path.name):
            raise DataBundleError(f"{root_id} contains an unreferenced or unsafe image: {image_path.name}")
        size, digest = _sha256_file(image_path, f"{root_id} derivative image")
        if size > MAX_MEMBER_BYTES:
            raise DataBundleError(f"{root_id} derivative image exceeds per-member size ceiling")
        relative_path = f"images/{image_path.name}"
        expected = derivatives.get(relative_path)
        if expected is None or digest != expected["sha256"]:
            raise DataBundleError(f"{root_id} derivative image hash disagrees with pairs.jsonl: {image_path.name}")
        media_bytes += size
        images.append({"path": relative_path, "source": image_path, "bytes": size, "sha256": digest})
    if set(derivatives) != {item["path"] for item in images}:
        raise DataBundleError(f"{root_id} derivative manifest/image set mismatch")

    archive_root = f"pairs/{root_id}"
    files = [
        {"path": "pairs.jsonl", "source": pairs_path, "bytes": pair_manifest_size, "sha256": pair_manifest_sha},
        {"path": "receipt.json", "source": receipt_path, "bytes": receipt_size, "sha256": receipt_sha},
    ]
    files.extend({"path": item["path"], "source": item["source"], "bytes": item["bytes"], "sha256": item["sha256"]} for item in images)
    return {
        "id": root_id,
        "archive_root": archive_root,
        "source_root": root,
        "receipt_sha256": receipt_sha,
        "pairs": pair_count,
        "images": pair_count,
        "pairs_manifest_sha256": pair_manifest_sha,
        "media_aggregate_sha256": media_aggregate_sha,
        "media_bytes": media_bytes,
        "files": files,
    }


def _zip_info(name: str) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
    info.create_system = 3
    info.external_attr = (stat.S_IFREG | 0o644) << 16
    info.compress_type = zipfile.ZIP_STORED
    return info


def _write_member(archive: zipfile.ZipFile, record: Mapping[str, Any]) -> None:
    name = str(record["path"])
    source = Path(record["source"])
    expected_bytes = int(record["bytes"])
    expected_sha = str(record["sha256"])
    digest = hashlib.sha256()
    count = 0
    try:
        with source.open("rb") as source_stream, archive.open(_zip_info(name), mode="w") as archive_stream:
            for chunk in iter(lambda: source_stream.read(1024 * 1024), b""):
                archive_stream.write(chunk)
                digest.update(chunk)
                count += len(chunk)
    except OSError as exc:
        raise DataBundleError(f"cannot add archive member: {name}") from exc
    if count != expected_bytes or digest.hexdigest() != expected_sha:
        raise DataBundleError(f"input changed while archiving: {name}")


def _external_root_inputs(overrides: Mapping[str, Path] | None = None) -> dict[str, Path]:
    return {
        root_id: Path(overrides[root_id]) if overrides and root_id in overrides else DEFAULT_DATA_ROOT / directory
        for root_id, directory, _ in ROOT_SPECS
    }


def _expected_receipts(overrides: Mapping[str, str] | None = None) -> dict[str, str]:
    return {
        root_id: overrides[root_id] if overrides and root_id in overrides else receipt_sha
        for root_id, _, receipt_sha in ROOT_SPECS
    }


def build(output: Path, roots: Mapping[str, Path] | None = None, expected_receipts: Mapping[str, str] | None = None) -> tuple[Path, str, dict[str, Any]]:
    output = _external_output(output)
    root_inputs = _external_root_inputs(roots)
    receipt_inputs = _expected_receipts(expected_receipts)
    if set(root_inputs) != {root_id for root_id, _, _ in ROOT_SPECS} or set(receipt_inputs) != set(root_inputs):
        raise DataBundleError("exactly commons, eva, and aadb roots and receipts are required")
    for root_id, _, _ in ROOT_SPECS:
        _validate_sha(receipt_inputs[root_id], f"{root_id} expected receipt")
    collected = [_collect_root(root_id, root_inputs[root_id], receipt_inputs[root_id]) for root_id, _, _ in ROOT_SPECS]
    file_records = [
        {"path": f"{root['archive_root']}/{record['path']}", "bytes": record["bytes"], "sha256": record["sha256"]}
        for root in collected
        for record in root["files"]
    ]
    total_bytes = sum(record["bytes"] for record in file_records)
    member_count = len(file_records) + 2
    if member_count > MAX_MEMBERS:
        raise DataBundleError("archive member count exceeds safety ceiling")
    if total_bytes > MAX_TOTAL_BYTES:
        raise DataBundleError("archive uncompressed size exceeds safety ceiling")
    manifest = {
        "schema_id": DATA_SCHEMA_ID,
        "schema_version": DATA_SCHEMA_VERSION,
        "kind": "research_only_paired_corruption_data",
        "research_only": True,
        "human_gold": False,
        "release_admissible": False,
        "split": RESEARCH_SPLIT,
        "roots": [
            {
                key: root[key]
                for key in (
                    "id",
                    "archive_root",
                    "receipt_sha256",
                    "pairs",
                    "images",
                    "pairs_manifest_sha256",
                    "media_aggregate_sha256",
                    "media_bytes",
                )
            }
            for root in collected
        ],
        "totals": {
            "roots": len(collected),
            "pairs": sum(root["pairs"] for root in collected),
            "images": sum(root["images"] for root in collected),
            "members": member_count,
            "uncompressed_bytes": total_bytes,
        },
        "files": file_records,
        "disclaimer": "Research-fit paired corruptions only. Derivative PNGs and metadata are not human-gold, calibrated, release-admissible, or a source-image redistribution package.",
    }
    manifest_bytes = (_canonical_json(manifest) + "\n").encode("utf-8")
    sums = {"schema_id": DATA_SUMS_SCHEMA_ID, "files": file_records}
    sums_bytes = (_canonical_json(sums) + "\n").encode("utf-8")
    temporary: Path | None = None
    try:
        fd, name = tempfile.mkstemp(prefix=f".{output.name}.", suffix=".tmp", dir=output.parent)
        os.close(fd)
        temporary = Path(name)
        with zipfile.ZipFile(temporary, mode="w", compression=zipfile.ZIP_STORED, allowZip64=False) as archive:
            for root in collected:
                for record in root["files"]:
                    _write_member(archive, {**record, "path": f"{root['archive_root']}/{record['path']}"})
            archive.writestr(_zip_info("bundle-manifest.json"), manifest_bytes)
            archive.writestr(_zip_info("SHA256SUMS.json"), sums_bytes)
        with temporary.open("rb") as stream:
            os.fsync(stream.fileno())
        os.replace(temporary, output)
        temporary = None
        try:
            parent_fd = os.open(output.parent, os.O_RDONLY)
            try:
                os.fsync(parent_fd)
            finally:
                os.close(parent_fd)
        except OSError:
            pass
    except (OSError, ValueError, zipfile.BadZipFile) as exc:
        raise DataBundleError("cannot atomically build Stage-2 data bundle") from exc
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    _, digest = _sha256_file(output, "output bundle")
    return output, digest, manifest


def _self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="camera-stage2-data-") as temp_dir:
        base = Path(temp_dir).resolve()
        roots: dict[str, Path] = {}
        receipts: dict[str, str] = {}
        for root_id, _, _ in ROOT_SPECS:
            root = base / root_id
            (root / "images").mkdir(parents=True)
            image = b"\x89PNG\r\nfixture-" + root_id.encode("ascii")
            pair_id = "pair_" + "0" * 40
            pair = {
                "schema_id": PAIR_SCHEMA_ID,
                "schema_version": PAIR_SCHEMA_VERSION,
                "pair_id": pair_id,
                "split": RESEARCH_SPLIT,
                "research_only": True,
                "human_gold": False,
                "release_admissible": False,
                "derivative": {"relative_path": f"images/{pair_id}.png", "sha256": hashlib.sha256(image).hexdigest(), "width": 1, "height": 1, "format": "png"},
            }
            pairs_bytes = (_canonical_json(pair) + "\n").encode("utf-8")
            (root / "pairs.jsonl").write_bytes(pairs_bytes)
            (root / "images" / f"{pair_id}.png").write_bytes(image)
            # Build the aggregate using the same canonical recipe as the real generator.
            aggregate = hashlib.sha256(
                f"images/{pair_id}.png\0{hashlib.sha256(image).hexdigest()}\0{1}\0{1}\n".encode()
            ).hexdigest()
            receipt = {
                "schema_id": "camera-silver-action-pair-receipt-v1",
                "schema_version": PAIR_SCHEMA_VERSION,
                "research_only": True,
                "human_gold": False,
                "release_admissible": False,
                "split": RESEARCH_SPLIT,
                "counts": {"pairs": 1},
                "output_manifest": {"path": "pairs.jsonl", "records": 1, "sha256": hashlib.sha256(pairs_bytes).hexdigest()},
                "output_media": {"files": 1, "aggregate_sha256": aggregate},
            }
            receipt_bytes = (_canonical_json(receipt) + "\n").encode("utf-8")
            (root / "receipt.json").write_bytes(receipt_bytes)
            roots[root_id] = root
            receipts[root_id] = hashlib.sha256(receipt_bytes).hexdigest()
        first, first_sha, first_manifest = build(base / "one.zip", roots, receipts)
        second, second_sha, _ = build(base / "two.zip", roots, receipts)
        assert first.read_bytes() == second.read_bytes() and first_sha == second_sha
        with zipfile.ZipFile(first) as archive:
            assert archive.namelist() == [
                "pairs/commons/pairs.jsonl",
                "pairs/commons/receipt.json",
                "pairs/commons/images/pair_" + "0" * 40 + ".png",
                "pairs/eva/pairs.jsonl",
                "pairs/eva/receipt.json",
                "pairs/eva/images/pair_" + "0" * 40 + ".png",
                "pairs/aadb/pairs.jsonl",
                "pairs/aadb/receipt.json",
                "pairs/aadb/images/pair_" + "0" * 40 + ".png",
                "bundle-manifest.json",
                "SHA256SUMS.json",
            ]
            manifest = json.loads(archive.read("bundle-manifest.json"))
            assert manifest == first_manifest
            assert manifest["totals"]["pairs"] == 3 and manifest["totals"]["images"] == 3
            for record in manifest["files"]:
                payload = archive.read(record["path"])
                assert len(payload) == record["bytes"] and hashlib.sha256(payload).hexdigest() == record["sha256"]
        try:
            build(base / "one.zip", roots, receipts)
        except DataBundleError as exc:
            assert "already exists" in str(exc)
        else:
            raise AssertionError("output collision was not rejected")
    print("PASS package_camera_stage2_data deterministic-jsonl-derivative-only receipt-binding safe-member-order atomic-output")


def _parse_assignments(values: list[str], label: str) -> dict[str, str]:
    parsed: dict[str, str] = {}
    for value in values:
        name, separator, payload = value.partition("=")
        if not separator or name not in {root_id for root_id, _, _ in ROOT_SPECS} or not payload or name in parsed:
            raise DataBundleError(f"invalid {label} assignment: {value}")
        parsed[name] = payload
    if set(parsed) != {root_id for root_id, _, _ in ROOT_SPECS}:
        raise DataBundleError(f"{label} must contain exactly commons, eva, and aadb")
    return parsed


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("build", nargs="?", choices=("build",))
    parser.add_argument("--output", type=Path)
    parser.add_argument("--root", action="append", default=[], metavar="NAME=PATH", help="override one root; provide all three")
    parser.add_argument("--receipt-sha256", action="append", default=[], metavar="NAME=SHA256", help="override one expected receipt; provide all three")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.self_test:
            _self_test()
            return 0
        if args.build != "build" or args.output is None:
            _parser().error("build and --output are required unless --self-test is used")
        root_values = _parse_assignments(args.root, "--root") if args.root else None
        receipt_values = _parse_assignments(args.receipt_sha256, "--receipt-sha256") if args.receipt_sha256 else None
        if (root_values is None) != (receipt_values is None):
            raise DataBundleError("--root and --receipt-sha256 must be supplied together")
        roots = {key: Path(value) for key, value in root_values.items()} if root_values else None
        output, digest, manifest = build(args.output, roots, receipt_values)
        totals = manifest["totals"]
        print(
            f"PASS package-camera-stage2-data output={output} sha256={digest} "
            f"bytes={output.stat().st_size} members={totals['members']} "
            f"roots={totals['roots']} pairs={totals['pairs']} images={totals['images']}"
        )
        return 0
    except DataBundleError as exc:
        print(f"FAIL {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
