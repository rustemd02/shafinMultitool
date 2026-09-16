#!/usr/bin/env python3
"""Small, reproducible Camera Coach research-source intake utility.

Raw media is always kept in an external data root.  The JSONL inventory is
metadata only and deliberately does not claim rights, human-gold labels, or
release admissibility. Acquisition is intentionally delegated to
source-specific, allowlisted tooling; this utility only verifies local media.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import sys
import tempfile
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[2]
CHUNK_SIZE = 1024 * 1024
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
SOURCE_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/-]*$")
LOCAL_PATH_KEYS = {
    "path",
    "relative_path",
    "local_path",
    "file",
    "filename",
    "local_file",
    "image_path",
}
RECORD_ID_KEYS = ("source_record_id", "record_id", "image_id", "id")
SIZE_KEYS = ("byte_count", "size_bytes", "size", "bytes", "byte_length")
HASH_KEYS = ("sha256", "file_sha256", "content_sha256")
DIMENSION_KEYS = {"width", "height"}
CANONICAL_FIELDS = {
    "source_id",
    "source_record_id",
    "relative_path",
    "sha256",
    "byte_count",
    "size_bytes",
    "width",
    "height",
    "format",
    "intake_tier",
    "human_gold",
    "release_admissible",
}
POLICY_KEY_TOKENS = (
    "rights",
    "license",
    "consent",
    "split",
    "review",
    "gold",
    "human_gold",
    "release",
    "admission",
    "quarantine",
    "approved",
    "provenance",
)


class IntakeError(ValueError):
    """A user-facing, fail-closed intake error."""


def _json_line(value: Any) -> str:
    return json.dumps(value, allow_nan=False, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _digest_file(path: Path) -> tuple[int, str]:
    digest = hashlib.sha256()
    size = 0
    try:
        with path.open("rb") as stream:
            while chunk := stream.read(CHUNK_SIZE):
                size += len(chunk)
                digest.update(chunk)
    except OSError as exc:
        raise IntakeError("cannot read image") from exc
    return size, digest.hexdigest()


def _image_dimensions(path: Path) -> tuple[int, int, str]:
    try:
        from PIL import Image
    except ImportError as exc:
        raise IntakeError("Pillow is required to decode images and read dimensions") from exc
    try:
        with Image.open(path) as image:
            image.verify()
        with Image.open(path) as image:
            image.load()
            width, height = int(image.width), int(image.height)
            image_format = str(image.format or "").lower()
    except Exception as exc:  # Pillow raises several format-specific errors.
        raise IntakeError("file is not a decodable image") from exc
    if width < 1 or height < 1:
        raise IntakeError("image dimensions must be positive")
    if not image_format:
        raise IntakeError("image format is unavailable")
    return width, height, image_format


def _external_root(value: Path, *, create: bool = False) -> Path:
    root = value.expanduser().resolve()
    repo = ROOT.resolve()
    if root == repo or repo in root.parents or root in repo.parents:
        raise IntakeError("data root must be outside the repository")
    if create:
        try:
            root.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            raise IntakeError("cannot create external data root") from exc
    if not root.is_dir():
        raise IntakeError("data root must be an existing directory")
    return root


def _relative_path(value: Any, root: Path) -> tuple[Path, str]:
    root = root.expanduser().resolve()
    if not isinstance(value, str) or not value.strip() or "\x00" in value:
        raise IntakeError("manifest path must be a non-empty string")
    if ".." in PurePosixPath(value.replace("\\", "/")).parts:
        raise IntakeError("manifest path escapes data root")
    candidate = Path(value).expanduser()
    lexical = candidate if candidate.is_absolute() else root / candidate
    try:
        lexical_relative = lexical.relative_to(root)
    except ValueError as exc:
        raise IntakeError("manifest path is outside data root") from exc
    current = root
    for part in lexical_relative.parts:
        current /= part
        if current.is_symlink():
            raise IntakeError("manifest path must not use symlinks")
    resolved = lexical.resolve()
    try:
        relative = resolved.relative_to(root)
    except ValueError as exc:
        raise IntakeError("manifest path escapes data root through a symlink") from exc
    if not resolved.is_file():
        raise IntakeError("manifest path is not a regular file")
    normalized = PurePosixPath(relative.as_posix())
    if not normalized.parts or any(part in ("", ".", "..") for part in normalized.parts):
        raise IntakeError("manifest path is not a safe relative path")
    return resolved, normalized.as_posix()


def _source_record_id(row: dict[str, Any]) -> str:
    for key in RECORD_ID_KEYS:
        value = row.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
        if isinstance(value, int) and not isinstance(value, bool):
            return str(value)
    raise IntakeError("manifest row requires source_record_id, record_id, or image_id")


def _path_value(row: dict[str, Any]) -> Any:
    for key in ("relative_path", "path", "local_path", "file", "filename", "local_file", "image_path"):
        if key in row:
            return row[key]
    return None


def _declared_hash(row: dict[str, Any]) -> str | None:
    for key in HASH_KEYS:
        if key in row:
            value = row[key]
            if not isinstance(value, str) or not SHA256_RE.fullmatch(value):
                raise IntakeError(f"{key} must be a lowercase SHA-256 digest")
            return value
    return None


def _declared_size(row: dict[str, Any]) -> int | None:
    for key in SIZE_KEYS:
        if key in row:
            value = row[key]
            if not isinstance(value, int) or isinstance(value, bool) or value < 0:
                raise IntakeError(f"{key} must be a non-negative integer")
            return value
    return None


def _declared_dimension(row: dict[str, Any], key: str) -> int | None:
    if key not in row:
        return None
    value = row[key]
    if not isinstance(value, int) or isinstance(value, bool) or value < 1:
        raise IntakeError(f"{key} must be a positive integer")
    return value


def _reject_policy_metadata(value: Any, *, path: str = "row") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            key_text = str(key)
            if any(token in key_text.lower() for token in POLICY_KEY_TOKENS):
                raise IntakeError(f"policy-bearing metadata key is not accepted: {path}.{key_text}")
            _reject_policy_metadata(child, path=f"{path}.{key_text}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _reject_policy_metadata(child, path=f"{path}[{index}]")


def _metadata_value(value: Any, key: str) -> Any | None:
    """Keep JSON metadata while dropping local path-bearing values."""

    lowered = key.lower()
    if lowered in LOCAL_PATH_KEYS or "local_path" in lowered or lowered.endswith("_root"):
        return None
    if isinstance(value, str):
        if value.startswith(("/", "~/")) or "\x00" in value:
            return None
        return value
    if isinstance(value, float) and not math.isfinite(value):
        raise IntakeError(f"upstream metadata value for {key} must be finite")
    if isinstance(value, (bool, int, float)) or value is None:
        return value
    if isinstance(value, list):
        cleaned = [_metadata_value(item, key) for item in value]
        return [item for item in cleaned if item is not None]
    if isinstance(value, dict):
        raise IntakeError(f"upstream metadata value for {key} must not contain nested fields")
    return None


UPSTREAM_METADATA_KEYS = {
    "mean_score",
    "total_votes",
    "vote_count",
    "mos",
    "stddev",
    "index",
    "source_bucket",
    "source_dataset",
    "source_title",
    "source_slug",
    "source_page_url",
    "source_image_url",
    "category",
    "content_category",
    "difficulty",
}


def _upstream_fields(row: dict[str, Any]) -> dict[str, Any]:
    local_keys = CANONICAL_FIELDS | LOCAL_PATH_KEYS | set(RECORD_ID_KEYS) | set(HASH_KEYS) | set(SIZE_KEYS) | DIMENSION_KEYS
    fields: dict[str, Any] = {}
    for key in sorted(row):
        if key in local_keys:
            continue
        if key not in UPSTREAM_METADATA_KEYS:
            raise IntakeError(f"unknown upstream metadata key: {key}")
        value = _metadata_value(row[key], key)
        if value is not None:
            fields[key] = value
    return {"upstream_metadata": fields} if fields else {}


def _reject_nonfinite_json_constant(constant: str) -> Any:
    raise IntakeError(f"manifest contains non-finite number: {constant}")


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise IntakeError("cannot read manifest") from exc
    rows: list[dict[str, Any]] = []
    for line_number, line in enumerate(lines, 1):
        if not line.strip():
            continue
        try:
            value = json.loads(line, parse_constant=_reject_nonfinite_json_constant)
        except json.JSONDecodeError as exc:
            raise IntakeError(f"manifest line {line_number} is malformed JSON") from exc
        if not isinstance(value, dict):
            raise IntakeError(f"manifest line {line_number} must be a JSON object")
        rows.append(value)
    if not rows:
        raise IntakeError("manifest contains no rows")
    return rows


def _canonical_inventory(
    rows: Iterable[dict[str, Any]],
    root: Path,
    source_id: str,
) -> list[dict[str, Any]]:
    if not isinstance(source_id, str) or not SOURCE_ID_RE.fullmatch(source_id):
        raise IntakeError("source-id must be a non-empty safe identifier")
    inventory: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    seen_paths: set[str] = set()
    seen_hashes: set[str] = set()
    for index, row in enumerate(rows, 1):
        if not isinstance(row, dict):
            raise IntakeError(f"manifest row {index} must be a JSON object")
        _reject_policy_metadata(row, path=f"row[{index}]")
        record_id = _source_record_id(row)
        if record_id in seen_ids:
            raise IntakeError(f"duplicate source record id: {record_id}")
        path_value = _path_value(row)
        if path_value is None:
            raise IntakeError(f"manifest row {index} requires a local path")
        path, relative = _relative_path(path_value, root)
        if relative in seen_paths:
            raise IntakeError(f"duplicate relative path: {relative}")
        size, digest = _digest_file(path)
        if digest in seen_hashes:
            raise IntakeError(f"duplicate image content: {digest}")
        width, height, image_format = _image_dimensions(path)
        declared_hash = _declared_hash(row)
        if declared_hash is not None and declared_hash != digest:
            raise IntakeError(f"sha256 mismatch for source record: {record_id}")
        declared_size = _declared_size(row)
        if declared_size is not None and declared_size != size:
            raise IntakeError(f"size mismatch for source record: {record_id}")
        for dimension, actual in (("width", width), ("height", height)):
            declared = _declared_dimension(row, dimension)
            if declared is not None and declared != actual:
                raise IntakeError(f"{dimension} mismatch for source record: {record_id}")
        output: dict[str, Any] = _upstream_fields(row)
        output.update({
            "source_id": source_id,
            "source_record_id": record_id,
            "relative_path": relative,
            "byte_count": size,
            "sha256": digest,
            "width": width,
            "height": height,
            "format": image_format,
            "intake_tier": "research_only",
            "human_gold": False,
            "release_admissible": False,
        })
        inventory.append(output)
        seen_ids.add(record_id)
        seen_paths.add(relative)
        seen_hashes.add(digest)
    inventory.sort(key=lambda item: (item["source_record_id"], item["relative_path"]))
    return inventory


def _atomic_write_jsonl(path: Path, rows: Iterable[dict[str, Any]]) -> str:
    path = path.expanduser()
    temporary: Path | None = None
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
        temporary = Path(temporary_name)
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            for row in rows:
                stream.write(_json_line(row) + "\n")
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
            try:
                temporary.unlink(missing_ok=True)
            except OSError:
                pass
        if isinstance(exc, IntakeError):
            raise
        raise IntakeError("cannot atomically write inventory") from exc
    return _digest_file(path)[1]


def _validate_output_destination(output: Path, manifest: Path, rows: Iterable[dict[str, Any]], root: Path) -> None:
    output_resolved = output.expanduser().resolve()
    if output_resolved == manifest.expanduser().resolve():
        raise IntakeError("output must not replace the input manifest")
    for index, row in enumerate(rows, 1):
        path_value = _path_value(row)
        if path_value is None:
            raise IntakeError(f"manifest row {index} requires a local path")
        media_path, _ = _relative_path(path_value, root)
        if output_resolved in {media_path, Path(f"{media_path}.part").resolve()}:
            raise IntakeError("output must not replace a manifest media file or its part file")


def _verify_local(args: argparse.Namespace) -> int:
    root = _external_root(args.data_root)
    rows = _read_jsonl(args.manifest)
    inventory = _canonical_inventory(rows, root, args.source_id)
    _validate_output_destination(args.output, args.manifest, rows, root)
    digest = _atomic_write_jsonl(args.output, inventory)
    print(f"PASS verify-local source_id={args.source_id} records={len(inventory)} output_sha256={digest}")
    return 0


def _self_test() -> None:
    try:
        from PIL import Image
    except ImportError as exc:
        raise IntakeError("Pillow is required for --self-test image fixtures") from exc
    with tempfile.TemporaryDirectory(prefix="camera-source-intake-") as temp_dir:
        base = Path(temp_dir)
        data_root = (base / "external-data").resolve()
        data_root.mkdir()
        first = data_root / "images" / "first.png"
        second = data_root / "images" / "second.jpg"
        text_file = data_root / "bad.txt"
        first.parent.mkdir()
        Image.new("RGB", (3, 2), (220, 30, 30)).save(first)
        Image.new("RGB", (2, 4), (30, 30, 220)).save(second)
        text_file.write_text("not an image", encoding="utf-8")
        first_size, first_hash = _digest_file(first)
        rows = [
            {"image_id": "zeta", "path": "images/second.jpg", "mean_score": 4.25, "total_votes": 196},
            {"image_id": "alpha", "path": "images/first.png"},
        ]
        manifest = base / "input.jsonl"
        manifest.write_text("\n".join(_json_line(row) for row in rows) + "\n", encoding="utf-8")
        inventory = _canonical_inventory(_read_jsonl(manifest), data_root, "fixture")
        assert [item["source_record_id"] for item in inventory] == ["alpha", "zeta"]
        assert inventory[0]["relative_path"] == "images/first.png"
        assert inventory[0]["byte_count"] == first_size
        assert inventory[0]["sha256"] == first_hash
        assert (inventory[0]["width"], inventory[0]["height"]) == (3, 2)
        assert inventory[0]["format"] == "png"
        assert inventory[0]["intake_tier"] == "research_only"
        assert inventory[0]["human_gold"] is False
        assert inventory[0]["release_admissible"] is False
        assert inventory[1]["upstream_metadata"] == {"mean_score": 4.25, "total_votes": 196}
        assert "mean_score" not in inventory[1] and "total_votes" not in inventory[1]
        inventory_text = "\n".join(_json_line(row) for row in inventory)
        assert "path" not in inventory[0] and str(base) not in inventory_text
        output = base / "inventory.jsonl"
        output_digest = _atomic_write_jsonl(output, inventory)
        assert output.read_text(encoding="utf-8") == "\n".join(_json_line(row) for row in inventory) + "\n"
        assert output_digest == _digest_file(output)[1]
        assert not list(base.glob("*.tmp")) and not list(base.glob(".*.tmp"))

        rerun = _canonical_inventory(_read_jsonl(manifest), data_root, "fixture")
        rerun_output = base / "inventory-rerun.jsonl"
        assert _atomic_write_jsonl(rerun_output, rerun) == output_digest
        assert rerun == inventory

        raw_before_collision = first.read_bytes()
        for collision in (first, Path(f"{first}.part")):
            try:
                _validate_output_destination(collision, manifest, rows, data_root)
            except IntakeError as exc:
                assert "media file" in str(exc)
            else:
                raise AssertionError("media output collision was accepted")
            assert first.read_bytes() == raw_before_collision
        try:
            _validate_output_destination(manifest, manifest, rows, data_root)
        except IntakeError as exc:
            assert "input manifest" in str(exc)
        else:
            raise AssertionError("manifest output collision was accepted")

        payload = first.read_bytes()
        resumed = data_root / "resumed.png"
        part = Path(f"{resumed}.part")
        split = max(1, len(payload) // 2)
        part.write_bytes(payload[:split])
        with part.open("ab") as stream:
            stream.write(payload[split:])
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(part, resumed)
        assert resumed.read_bytes() == payload and not part.exists()

        duplicate_file = data_root / "images" / "duplicate.png"
        duplicate_file.write_bytes(first.read_bytes())
        duplicate_rows = rows + [{"image_id": "duplicate", "path": "images/duplicate.png"}]
        try:
            _canonical_inventory(duplicate_rows, data_root, "fixture")
        except IntakeError as exc:
            assert "duplicate image content" in str(exc)
        else:
            raise AssertionError("duplicate content was accepted")
        try:
            _canonical_inventory(rows + [{"image_id": "alpha", "path": "images/second.jpg"}], data_root, "fixture")
        except IntakeError as exc:
            assert "duplicate source record id" in str(exc)
        else:
            raise AssertionError("duplicate source record id was accepted")
        try:
            _canonical_inventory([{"image_id": "missing", "path": str(data_root / "missing.jpg")}], data_root, "fixture")
        except IntakeError as exc:
            assert "regular file" in str(exc)
        else:
            raise AssertionError("missing file was accepted")
        try:
            _canonical_inventory([{"image_id": "bad", "path": "bad.txt"}], data_root, "fixture")
        except IntakeError as exc:
            assert "decodable image" in str(exc)
        else:
            raise AssertionError("non-image was accepted")
        for malicious in (
            {"image_id": "rights", "path": "images/first.png", "rights": {"tier": "approved"}},
            {"image_id": "nested", "path": "images/first.png", "metadata": [{"human_GOLD": True}]},
            {"image_id": "eligible", "path": "images/first.png", "training_eligible": True},
            {"image_id": "redistribution", "path": "images/first.png", "redistribution": "yes"},
            {"image_id": "copyright", "path": "images/first.png", "copyright": "owner"},
            {"image_id": "unknown", "path": "images/first.png", "random_unknown": "value"},
            {"image_id": "nested_unknown", "path": "images/first.png", "source_title": {"random_unknown": "value"}},
        ):
            try:
                _canonical_inventory([malicious], data_root, "fixture")
            except IntakeError as exc:
                assert "metadata" in str(exc)
            else:
                raise AssertionError("policy-bearing metadata was accepted")
        outside = base / "outside.png"
        Image.new("RGB", (5, 5), (10, 10, 10)).save(outside)
        inside_link = data_root / "images" / "inside-link.png"
        outside_link = data_root / "images" / "outside-link.png"
        os.symlink(first, inside_link)
        os.symlink(outside, outside_link)
        for linked_path in ("images/inside-link.png", "images/outside-link.png"):
            try:
                _canonical_inventory([{"image_id": linked_path, "path": linked_path}], data_root, "fixture")
            except IntakeError as exc:
                assert "symlink" in str(exc)
            else:
                raise AssertionError("symlinked media was accepted")
        malformed = base / "malformed.jsonl"
        malformed.write_text("{not-json}\n", encoding="utf-8")
        try:
            _read_jsonl(malformed)
        except IntakeError as exc:
            assert "malformed JSON" in str(exc)
        else:
            raise AssertionError("malformed JSON was accepted")
        for constant in ("NaN", "Infinity", "-Infinity"):
            nonfinite = base / f"nonfinite-{constant.replace('-', 'negative-')}.jsonl"
            nonfinite.write_text(
                f'{{"image_id":"nonfinite","path":"images/first.png","mean_score":{constant}}}\n',
                encoding="utf-8",
            )
            try:
                _read_jsonl(nonfinite)
            except IntakeError as exc:
                assert "non-finite" in str(exc)
            else:
                raise AssertionError(f"JSON {constant} was accepted")
        for value in (float("nan"), float("inf"), float("-inf")):
            try:
                _canonical_inventory([{"image_id": "nonfinite", "path": "images/first.png", "mean_score": value}], data_root, "fixture")
            except IntakeError as exc:
                assert "finite" in str(exc)
            else:
                raise AssertionError("non-finite metadata was accepted")
            try:
                _json_line({"nonfinite": value})
            except ValueError:
                pass
            else:
                raise AssertionError("non-finite JSON output was accepted")
        for unsafe in (ROOT, ROOT / "datasets", ROOT.parent, Path(ROOT.anchor)):
            try:
                _external_root(unsafe)
            except IntakeError as exc:
                assert "outside the repository" in str(exc)
            else:
                raise AssertionError("repository data root was accepted")
    print("PASS camera_source_intake self-test atomic_write deterministic hashes dimensions format duplicates missing non_image metadata_allowlist nonfinite_guards output_collisions symlink_guards repo_boundary")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", help="run the local fixture self-test")
    subparsers = parser.add_subparsers(dest="command")
    verify = subparsers.add_parser("verify-local", help="verify existing external images and write an inventory")
    verify.add_argument("--source-id", required=True)
    verify.add_argument("--data-root", type=Path, required=True)
    verify.add_argument("--manifest", type=Path, required=True)
    verify.add_argument("--output", type=Path, required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.self_test:
            _self_test()
            return 0
        if args.command == "verify-local":
            return _verify_local(args)
        _parser().error("choose --self-test or verify-local")
    except IntakeError as exc:
        print(f"FAIL {exc}", file=sys.stderr)
        return 1
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
