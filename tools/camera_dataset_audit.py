#!/usr/bin/env python3
"""Deterministic Camera Coach exact/near-duplicate audit (M3-007).

The audit consumes a small external-media manifest. It never copies media and
never writes source paths, labels, or candidate/model fields to the cluster
receipt. The local ``embedding`` is intentionally a deterministic image
descriptor, not a learned model; a model-backed descriptor is an upgrade
boundary for a future versioned contract.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass, field
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import sys
from tempfile import TemporaryDirectory
from typing import Any, Iterable

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SCHEMA_PATH = ROOT / "datasets/camera-coach/v1/cluster-schema.json"
SCHEMA_ID = "camera-dedup-clusters-v1"
INPUT_SCHEMA_ID = "camera-dedup-input-v1"
SCHEMA_VERSION = "v1.0.0"
ALGORITHM_ID = "camera-dedup-v1"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
ID_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
CLUSTER_ID_RE = re.compile(r"^cdc_[0-9a-f]{16}$")
PHASH_SIZE = 32
PHASH_LOW_FREQUENCY_SIZE = 8
DESCRIPTOR_SIZE = 8
DEFAULT_PHASH_DISTANCE = 14
MIN_DESCRIPTOR_FOR_PHASH = 0.55
DEFAULT_DESCRIPTOR_SIMILARITY = 0.965
DEFAULT_SSIM_REVIEW_THRESHOLD = 0.80
FORBIDDEN_FIELDS = {
    "candidate",
    "candidate_output",
    "locked_label",
    "model_output",
    "prediction",
    "oracle",
}
ALLOWED_RIGHTS = {"approved", "fixture_only"}
CAMERA_RECORD_SCHEMA_IDS = {"camera-label-v1", "camera-temporal-v1", "camera-episode-v1"}


class AuditInputError(ValueError):
    """Raised when an audit input cannot be safely interpreted."""


@dataclass(frozen=True)
class MediaItem:
    """One content-addressed image reference with non-sensitive lineage."""

    asset_id: str
    path: Path
    record_ids: tuple[str, ...] = ()
    sequence_ids: tuple[str, ...] = ()
    frame_ordinals: tuple[int, ...] = ()
    derivation_family_ids: tuple[str, ...] = ()
    declared_sha256: str | None = None


@dataclass
class _MutableMediaItem:
    asset_id: str
    path: Path
    record_ids: set[str] = field(default_factory=set)
    sequence_ids: set[str] = field(default_factory=set)
    frame_ordinals: set[int] = field(default_factory=set)
    derivation_family_ids: set[str] = field(default_factory=set)
    declared_sha256: str | None = None

    def freeze(self) -> MediaItem:
        return MediaItem(
            asset_id=self.asset_id,
            path=self.path,
            record_ids=tuple(sorted(self.record_ids)),
            sequence_ids=tuple(sorted(self.sequence_ids)),
            frame_ordinals=tuple(sorted(self.frame_ordinals)),
            derivation_family_ids=tuple(sorted(self.derivation_family_ids)),
            declared_sha256=self.declared_sha256,
        )


@dataclass(frozen=True)
class _Feature:
    sha256: str
    perceptual_hash: str
    descriptor: tuple[float, ...]
    descriptor_sha256: str
    image: Image.Image


class _UnionFind:
    def __init__(self, size: int) -> None:
        self.parent = list(range(size))
        self.rank = [0] * size

    def find(self, value: int) -> int:
        while self.parent[value] != value:
            self.parent[value] = self.parent[self.parent[value]]
            value = self.parent[value]
        return value

    def union(self, left: int, right: int) -> None:
        left_root, right_root = self.find(left), self.find(right)
        if left_root == right_root:
            return
        if self.rank[left_root] < self.rank[right_root]:
            left_root, right_root = right_root, left_root
        self.parent[right_root] = left_root
        if self.rank[left_root] == self.rank[right_root]:
            self.rank[left_root] += 1


def _json_digest(value: Any) -> str:
    return hashlib.sha256(
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise AuditInputError(f"unreadable_media: {path}") from exc
    return digest.hexdigest()


def _load_image(path: Path) -> Image.Image:
    try:
        with Image.open(path) as opened:
            opened.verify()
        with Image.open(path) as opened:
            opened.load()
            if opened.width < 1 or opened.height < 1:
                raise AuditInputError(f"invalid_media_dimensions: {path}")
            return opened.convert("RGB")
    except AuditInputError:
        raise
    except (OSError, ValueError) as exc:
        raise AuditInputError(f"unreadable_media: {path}") from exc


def _grayscale_pixels(image: Image.Image, size: int) -> tuple[float, ...]:
    resized = image.convert("L").resize((size, size), Image.Resampling.BILINEAR)
    return tuple(pixel / 255.0 for pixel in resized.tobytes())


def perceptual_hash(image: Image.Image | Path) -> str:
    """Return a deterministic 64-bit DCT perceptual hash."""

    if isinstance(image, Path):
        image = _load_image(image)
    pixels = _grayscale_pixels(image, PHASH_SIZE)
    coefficients: list[float] = []
    for u in range(PHASH_LOW_FREQUENCY_SIZE):
        for v in range(PHASH_LOW_FREQUENCY_SIZE):
            total = 0.0
            for x in range(PHASH_SIZE):
                for y in range(PHASH_SIZE):
                    total += pixels[x * PHASH_SIZE + y] * math.cos(
                        math.pi * u * (2 * x + 1) / (2 * PHASH_SIZE)
                    ) * math.cos(math.pi * v * (2 * y + 1) / (2 * PHASH_SIZE))
            scale_u = 1 / math.sqrt(PHASH_SIZE) if u == 0 else math.sqrt(2 / PHASH_SIZE)
            scale_v = 1 / math.sqrt(PHASH_SIZE) if v == 0 else math.sqrt(2 / PHASH_SIZE)
            coefficients.append(total * scale_u * scale_v)
    body = coefficients[1:]
    median = sorted(body)[len(body) // 2]
    bits = sum((value > median) << index for index, value in enumerate(body))
    return f"{bits:016x}"


def local_embedding(image: Image.Image | Path) -> tuple[float, ...]:
    """Return the approved local deterministic low-dimensional descriptor.

    This is deliberately not a learned embedding: it is a centered 8x8
    grayscale thumbnail normalized to unit length. It is useful as a stable
    secondary similarity signal and is not a production quality claim.
    """

    if isinstance(image, Path):
        image = _load_image(image)
    pixels = _grayscale_pixels(image, DESCRIPTOR_SIZE)
    mean = sum(pixels) / len(pixels)
    centered = tuple(value - mean for value in pixels)
    norm = math.sqrt(sum(value * value for value in centered))
    if norm == 0.0:
        return tuple(0.0 for _ in centered)
    return tuple(value / norm for value in centered)


def _descriptor_digest(descriptor: tuple[float, ...]) -> str:
    packed = struct.pack(f"<{len(descriptor)}d", *descriptor)
    return hashlib.sha256(packed).hexdigest()


def _cosine_similarity(left: tuple[float, ...], right: tuple[float, ...]) -> float:
    left_norm = math.sqrt(sum(value * value for value in left))
    right_norm = math.sqrt(sum(value * value for value in right))
    if left_norm == 0.0 or right_norm == 0.0:
        return 0.0
    return max(-1.0, min(1.0, sum(a * b for a, b in zip(left, right)) / (left_norm * right_norm)))


def _phash_distance(left: str, right: str) -> int:
    return (int(left, 16) ^ int(right, 16)).bit_count()


def structural_similarity(left: Image.Image | Path, right: Image.Image | Path) -> float:
    """Return a small deterministic grayscale SSIM review signal."""

    first = _load_image(left) if isinstance(left, Path) else left
    second = _load_image(right) if isinstance(right, Path) else right
    a, b = _grayscale_pixels(first, 64), _grayscale_pixels(second, 64)
    mean_a, mean_b = sum(a) / len(a), sum(b) / len(b)
    variance_a = sum((value - mean_a) ** 2 for value in a) / len(a)
    variance_b = sum((value - mean_b) ** 2 for value in b) / len(b)
    covariance = sum((x - mean_a) * (y - mean_b) for x, y in zip(a, b)) / len(a)
    c1, c2 = 0.01**2, 0.03**2
    denominator = (mean_a**2 + mean_b**2 + c1) * (variance_a + variance_b + c2)
    if denominator == 0.0:
        return 1.0 if a == b else 0.0
    numerator = (2 * mean_a * mean_b + c1) * (2 * covariance + c2)
    return max(-1.0, min(1.0, numerator / denominator))


def _ensure_id(value: Any, field_name: str) -> str:
    if not isinstance(value, str) or not ID_RE.fullmatch(value):
        raise AuditInputError(f"invalid_id: {field_name}")
    return value


def _ensure_sha(value: Any, field_name: str) -> str:
    if not isinstance(value, str) or not SHA256_RE.fullmatch(value):
        raise AuditInputError(f"invalid_sha256: {field_name}")
    return value


def _reject_forbidden(value: Any, path: str = "manifest") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            lowered = key.lower() if isinstance(key, str) else ""
            if lowered in FORBIDDEN_FIELDS or lowered in {"candidate_id", "model", "model_id", "model_name", "prediction_id"}:
                raise AuditInputError(f"candidate_identity_leakage: {path}.{key}")
            _reject_forbidden(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _reject_forbidden(child, f"{path}[{index}]")


def _read_json_or_jsonl(path: Path) -> Any:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise AuditInputError(f"unreadable_manifest: {path}") from exc
    if not text.strip():
        raise AuditInputError(f"empty_manifest: {path}")
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        rows: list[Any] = []
        for line_number, line in enumerate(text.splitlines(), 1):
            if not line.strip():
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise AuditInputError(f"malformed_manifest_json: {path}:{line_number}") from exc
        if not rows:
            raise AuditInputError(f"malformed_manifest_json: {path}")
        return rows


def _container_entries(payload: Any, label: str) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    if isinstance(payload, list):
        entries = payload
        header: dict[str, Any] = {}
    elif isinstance(payload, dict):
        header = payload
        container_keys = ("entries", "assets", "records")
        if "media" in payload and not any(key in payload for key in ("record_id", "record_type", "sequence", "provenance")):
            container_keys += ("media",)
        entries_value = next((payload.get(key) for key in container_keys if key in payload), None)
        if isinstance(entries_value, dict):
            entries_value = [
                {"asset_id": asset_id, **(value if isinstance(value, dict) else {"path": value})}
                for asset_id, value in entries_value.items()
            ]
        entries = entries_value if entries_value is not None else [payload]
    else:
        raise AuditInputError(f"invalid_manifest_shape: {label}")
    if not isinstance(entries, list) or not entries or any(not isinstance(item, dict) for item in entries):
        raise AuditInputError(f"invalid_manifest_entries: {label}")
    return entries, header


def _validate_header(header: dict[str, Any], label: str) -> None:
    schema_id = header.get("schema_id")
    if schema_id is not None and (
        not isinstance(schema_id, str)
        or schema_id not in ({INPUT_SCHEMA_ID} | CAMERA_RECORD_SCHEMA_IDS)
    ):
        raise AuditInputError(f"invalid_schema_id: {label}.schema_id")
    version = header.get("manifest_version", header.get("schema_version"))
    if version is not None and version != SCHEMA_VERSION:
        raise AuditInputError(f"invalid_schema_version: {label}")
    if header.get("hash_algorithm") not in (None, "sha256"):
        raise AuditInputError(f"invalid_hash_algorithm: {label}.hash_algorithm")
    for key in ("raw_data_location", "rights_uncleared_location"):
        if key in header and header[key] != "outside_git":
            raise AuditInputError(f"raw_media_inside_git: {label}.{key}")


def _extract_path(entry: dict[str, Any], media_map: dict[str, dict[str, Any]]) -> tuple[str | None, str | None]:
    path_value: Any = next((entry.get(key) for key in ("path", "media_path", "file", "asset_path") if key in entry), None)
    declared = entry.get("content_sha256", entry.get("sha256"))
    media = entry.get("media")
    if isinstance(media, dict):
        if path_value is None:
            path_value = next((media.get(key) for key in ("path", "media_path", "file", "asset_path") if key in media), None)
        if declared is None:
            declared = media.get("content_sha256", media.get("sha256"))
    asset_id = entry.get("asset_id")
    mapped = media_map.get(asset_id) if isinstance(asset_id, str) else None
    if mapped is not None:
        if path_value is None:
            path_value = mapped.get("path")
        if declared is None:
            declared = mapped.get("content_sha256", mapped.get("sha256"))
    if path_value is not None and not isinstance(path_value, str):
        raise AuditInputError("invalid_media_path")
    if declared is not None:
        declared = _ensure_sha(declared, "content_sha256")
    return path_value, declared


def _resolve_path(raw_path: str, media_root: Path | None) -> Path:
    if "://" in raw_path:
        raise AuditInputError("media_path_must_be_local")
    raw = Path(raw_path).expanduser()
    if media_root is None:
        resolved = raw.resolve()
    else:
        root = media_root.expanduser().resolve()
        if not root.is_dir():
            raise AuditInputError(f"missing_media_root: {root}")
        resolved = (raw if raw.is_absolute() else root / raw).resolve()
        try:
            resolved.relative_to(root)
        except ValueError as exc:
            raise AuditInputError("media_path_outside_root") from exc
    if not resolved.is_file():
        raise AuditInputError(f"missing_media: {resolved}")
    return resolved


def _metadata(entry: dict[str, Any]) -> tuple[str | None, str | None, str | None, int | None, str | None]:
    record_id = entry.get("record_id")
    if record_id is not None:
        record_id = _ensure_id(record_id, "record_id")
    provenance = entry.get("provenance")
    family = entry.get("derivation_family_id")
    rights = entry.get("rights_disposition")
    if provenance is not None:
        if not isinstance(provenance, dict):
            raise AuditInputError("invalid_provenance")
        family = provenance.get("derivation_family_id", family)
        rights = provenance.get("rights_disposition", rights)
        if family is None:
            raise AuditInputError("missing_derivation_family_id")
    if family is not None:
        family = _ensure_id(family, "derivation_family_id")
    if rights is not None and (not isinstance(rights, str) or rights not in ALLOWED_RIGHTS):
        raise AuditInputError("rights_not_admissible")
    sequence = entry.get("sequence")
    sequence_id = entry.get("sequence_id")
    ordinal = entry.get("frame_ordinal")
    if isinstance(sequence, dict):
        sequence_id = sequence.get("sequence_id", sequence_id)
    if sequence_id is not None:
        sequence_id = _ensure_id(sequence_id, "sequence_id")
    if ordinal is not None:
        if type(ordinal) is not int or ordinal < 0:
            raise AuditInputError("invalid_frame_ordinal")
    return record_id, family, sequence_id, ordinal, rights


def _merge_item(
    items: dict[str, _MutableMediaItem],
    *,
    asset_id: Any,
    raw_path: str | None,
    declared_sha256: str | None,
    record_id: str | None,
    family: str | None,
    sequence_id: str | None,
    ordinal: int | None,
    media_root: Path | None,
) -> None:
    asset_id = _ensure_id(asset_id, "asset_id")
    if raw_path is None:
        raise AuditInputError(f"missing_media_path: {asset_id}")
    path = _resolve_path(raw_path, media_root)
    current = items.get(asset_id)
    if current is None:
        current = _MutableMediaItem(asset_id=asset_id, path=path, declared_sha256=declared_sha256)
        items[asset_id] = current
    elif current.path != path:
        raise AuditInputError(f"asset_path_conflict: {asset_id}")
    elif current.declared_sha256 != declared_sha256 and declared_sha256 is not None and current.declared_sha256 is not None:
        raise AuditInputError(f"asset_sha256_conflict: {asset_id}")
    if current.declared_sha256 is None:
        current.declared_sha256 = declared_sha256
    if sequence_id is not None and current.sequence_ids and sequence_id not in current.sequence_ids:
        raise AuditInputError(f"asset_sequence_conflict: {asset_id}")
    if ordinal is not None and current.frame_ordinals and ordinal not in current.frame_ordinals:
        raise AuditInputError(f"asset_frame_ordinal_conflict: {asset_id}")
    if record_id is not None:
        current.record_ids.add(record_id)
    if family is not None:
        current.derivation_family_ids.add(family)
    if sequence_id is not None:
        current.sequence_ids.add(sequence_id)
    if ordinal is not None:
        current.frame_ordinals.add(ordinal)


def _media_map(path: Path | None, media_root: Path | None) -> dict[str, dict[str, Any]]:
    if path is None:
        return {}
    payload = _read_json_or_jsonl(path)
    entries, header = _container_entries(payload, str(path))
    _validate_header(header, str(path))
    if isinstance(payload, dict) and not any(key in payload for key in ("entries", "assets", "records")):
        if all(isinstance(value, str) for value in payload.values()):
            return {
                _ensure_id(key, "media_map.asset_id"): {"path": str(_resolve_path(value, media_root))}
                for key, value in payload.items()
            }
    result: dict[str, dict[str, Any]] = {}
    for entry in entries:
        asset_id = _ensure_id(entry.get("asset_id"), "media_map.asset_id")
        raw_path, declared = _extract_path(entry, {})
        if raw_path is None:
            raise AuditInputError(f"missing_media_path: {asset_id}")
        resolved = _resolve_path(raw_path, media_root)
        if asset_id in result and result[asset_id]["path"] != str(resolved):
            raise AuditInputError(f"asset_path_conflict: {asset_id}")
        result[asset_id] = {"path": str(resolved), "content_sha256": declared}
    return result


def load_manifest(path: Path, *, media_root: Path | None = None, media_manifest: Path | None = None) -> list[MediaItem]:
    """Load either the M3 audit input or camera record-shaped JSON/JSONL."""

    payload = _read_json_or_jsonl(path)
    _reject_forbidden(payload)
    entries, header = _container_entries(payload, str(path))
    _validate_header(header, str(path))
    media_map = _media_map(media_manifest, media_root)
    items: dict[str, _MutableMediaItem] = {}

    def add(entry: dict[str, Any], *, inherited_record: str | None = None, inherited_family: str | None = None, inherited_sequence: str | None = None, inherited_ordinal: int | None = None) -> None:
        record_id, family, sequence_id, ordinal, _ = _metadata(entry)
        record_id = record_id or inherited_record
        family = family or inherited_family
        sequence_id = sequence_id or inherited_sequence
        ordinal = ordinal if ordinal is not None else inherited_ordinal
        sequence = entry.get("sequence")
        asset_id = entry.get("asset_id")
        raw_path, declared = _extract_path(entry, media_map)
        if isinstance(sequence, dict):
            # Temporal frame paths/digests are authoritative; record.media may
            # describe the sequence as a whole and must not be copied to each frame.
            add_one = []
        elif asset_id is not None:
            add_one = [(asset_id, raw_path, declared, sequence_id, ordinal)]
        else:
            media = entry.get("media")
            asset_ids = media.get("asset_ids") if isinstance(media, dict) else entry.get("asset_ids")
            if asset_ids is None and isinstance(media, dict):
                asset_ids = [media.get("asset_id")]
            if not isinstance(asset_ids, list) or not asset_ids:
                raise AuditInputError("missing_asset_id")
            if any(not isinstance(value, str) for value in asset_ids):
                raise AuditInputError("invalid_asset_ids")
            if len(asset_ids) > 1 and raw_path is not None:
                raise AuditInputError("one_path_for_multiple_assets")
            add_one = [(value, None, declared if len(asset_ids) == 1 else None, sequence_id, ordinal) for value in asset_ids]
        for current_asset_id, current_path, current_declared, current_sequence, current_ordinal in add_one:
            mapped = media_map.get(current_asset_id)
            if current_path is None and mapped is not None:
                current_path, mapped_declared = mapped["path"], mapped.get("content_sha256")
                current_declared = current_declared or mapped_declared
            _merge_item(
                items,
                asset_id=current_asset_id,
                raw_path=current_path,
                declared_sha256=current_declared,
                record_id=record_id,
                family=family,
                sequence_id=current_sequence,
                ordinal=current_ordinal,
                media_root=None if mapped is not None else media_root,
            )

        if sequence is not None:
            if not isinstance(sequence, dict):
                raise AuditInputError("invalid_sequence")
            seq_id = sequence.get("sequence_id", sequence_id)
            seq_id = _ensure_id(seq_id, "sequence.sequence_id")
            frames = sequence.get("frames")
            if not isinstance(frames, list) or not frames:
                raise AuditInputError("invalid_sequence_frames")
            for frame in frames:
                if not isinstance(frame, dict):
                    raise AuditInputError("invalid_sequence_frame")
                frame_asset = frame.get("asset_id")
                frame_ordinal = frame.get("ordinal")
                if type(frame_ordinal) is not int or frame_ordinal < 0:
                    raise AuditInputError("invalid_frame_ordinal")
                frame_path, frame_declared = _extract_path(frame, media_map)
                if frame_path is None:
                    mapped = media_map.get(frame_asset) if isinstance(frame_asset, str) else None
                    if mapped is not None:
                        frame_path, frame_declared = mapped["path"], frame_declared or mapped.get("content_sha256")
                _merge_item(
                    items,
                    asset_id=frame_asset,
                    raw_path=frame_path,
                    declared_sha256=frame_declared,
                    record_id=record_id,
                    family=family,
                    sequence_id=seq_id,
                    ordinal=frame_ordinal,
                    media_root=None if frame_asset in media_map else media_root,
                )

    for entry in entries:
        # A JSONL collection may contain a header row followed by entries.
        if entry.get("record_count") is not None and not any(key in entry for key in ("asset_id", "asset_ids", "media", "sequence")):
            _validate_header(entry, f"{path}:header")
            continue
        add(entry)
    if not items:
        raise AuditInputError("empty_media_manifest")
    frozen = [item.freeze() for item in items.values()]
    for item in frozen:
        if len(item.derivation_family_ids) > 1:
            raise AuditInputError(f"asset_derivation_family_conflict: {item.asset_id}")
        if len(item.sequence_ids) > 1:
            raise AuditInputError(f"asset_sequence_conflict: {item.asset_id}")
    sequence_ordinals: dict[str, set[int]] = {}
    for item in frozen:
        for sequence_id in item.sequence_ids:
            sequence_ordinals.setdefault(sequence_id, set()).update(item.frame_ordinals)
    for sequence_id, ordinals in sequence_ordinals.items():
        sequence_items = [item for item in frozen if sequence_id in item.sequence_ids]
        if any(not item.frame_ordinals for item in sequence_items):
            continue
        if len(ordinals) != len(sequence_items):
            raise AuditInputError(f"duplicate_frame_ordinal: {sequence_id}")
    return sorted(frozen, key=lambda item: item.asset_id)


def _feature(item: MediaItem) -> _Feature:
    actual_sha = sha256_file(item.path)
    if item.declared_sha256 is not None and actual_sha != item.declared_sha256:
        raise AuditInputError(f"sha256_mismatch: {item.asset_id}")
    image = _load_image(item.path)
    descriptor = local_embedding(image)
    return _Feature(
        sha256=actual_sha,
        perceptual_hash=perceptual_hash(image),
        descriptor=descriptor,
        descriptor_sha256=_descriptor_digest(descriptor),
        image=image,
    )


def _edge_evidence(
    left: _Feature,
    right: _Feature,
    *,
    phash_distance: int,
    descriptor_similarity: float,
) -> tuple[bool, dict[str, Any]]:
    distance = _phash_distance(left.perceptual_hash, right.perceptual_hash)
    similarity = _cosine_similarity(left.descriptor, right.descriptor)
    reasons: list[str] = []
    if left.sha256 == right.sha256:
        reasons.append("sha256_exact")
    if distance <= phash_distance and similarity >= MIN_DESCRIPTOR_FOR_PHASH:
        reasons.append("perceptual_hash")
    if similarity >= descriptor_similarity:
        reasons.append("local_embedding_similarity")
    return bool(reasons), {
        "phash_hamming_distance": distance,
        "local_embedding_similarity": round(similarity, 6),
        "reasons": reasons,
    }


def _cluster_id(items: Iterable[MediaItem], features: dict[str, _Feature]) -> str:
    members = sorted(f"{item.asset_id}:{features[item.asset_id].sha256}" for item in items)
    return "cdc_" + hashlib.sha256((ALGORITHM_ID + "|" + "|".join(members)).encode("utf-8")).hexdigest()[:16]


def _canonical_input(items: list[MediaItem], features: dict[str, _Feature]) -> dict[str, Any]:
    return {
        "assets": [
            {
                "asset_id": item.asset_id,
                "content_sha256": features[item.asset_id].sha256,
                "record_ids": list(item.record_ids),
                "sequence_ids": list(item.sequence_ids),
                "frame_ordinals": list(item.frame_ordinals),
                "derivation_family_ids": list(item.derivation_family_ids),
            }
            for item in sorted(items, key=lambda value: value.asset_id)
        ]
    }


def cluster_media(
    items: list[MediaItem],
    *,
    ssim_review: bool = False,
    phash_distance: int = DEFAULT_PHASH_DISTANCE,
    descriptor_similarity: float = DEFAULT_DESCRIPTOR_SIMILARITY,
    ssim_threshold: float = DEFAULT_SSIM_REVIEW_THRESHOLD,
) -> dict[str, Any]:
    """Build a stable cluster receipt from validated external image refs."""

    if not items:
        raise AuditInputError("empty_media_manifest")
    if phash_distance < 0 or phash_distance > 64:
        raise AuditInputError("invalid_phash_distance")
    if not 0.0 <= descriptor_similarity <= 1.0:
        raise AuditInputError("invalid_descriptor_similarity")
    if not -1.0 <= ssim_threshold <= 1.0:
        raise AuditInputError("invalid_ssim_threshold")
    items = sorted(items, key=lambda item: item.asset_id)
    if len({item.asset_id for item in items}) != len(items):
        raise AuditInputError("duplicate_asset_id")
    features = {item.asset_id: _feature(item) for item in items}
    index = {item.asset_id: position for position, item in enumerate(items)}
    union_find = _UnionFind(len(items))
    edges: dict[tuple[str, str], dict[str, Any]] = {}

    for left_index, left_item in enumerate(items):
        for right_item in items[left_index + 1 :]:
            right_index = index[right_item.asset_id]
            matched, evidence = _edge_evidence(
                features[left_item.asset_id],
                features[right_item.asset_id],
                phash_distance=phash_distance,
                descriptor_similarity=descriptor_similarity,
            )
            if matched:
                union_find.union(left_index, right_index)
                edges[(left_item.asset_id, right_item.asset_id)] = evidence

    sequences: dict[str, list[MediaItem]] = {}
    for item in items:
        for sequence_id in item.sequence_ids:
            sequences.setdefault(sequence_id, []).append(item)
    for sequence_id, sequence_items in sorted(sequences.items()):
        sequence_items.sort(key=lambda item: (item.frame_ordinals or (sys.maxsize,), item.asset_id))
        anchor = sequence_items[0]
        for member in sequence_items[1:]:
            key = tuple(sorted((anchor.asset_id, member.asset_id)))
            evidence = edges.setdefault(
                key,
                {
                    "phash_hamming_distance": _phash_distance(features[anchor.asset_id].perceptual_hash, features[member.asset_id].perceptual_hash),
                    "local_embedding_similarity": round(_cosine_similarity(features[anchor.asset_id].descriptor, features[member.asset_id].descriptor), 6),
                    "reasons": [],
                },
            )
            if "sequence_family_inheritance" not in evidence["reasons"]:
                evidence["reasons"].append("sequence_family_inheritance")
            union_find.union(index[anchor.asset_id], index[member.asset_id])

    grouped: dict[int, list[MediaItem]] = {}
    for position, item in enumerate(items):
        grouped.setdefault(union_find.find(position), []).append(item)

    clusters: list[dict[str, Any]] = []
    for members in grouped.values():
        members.sort(key=lambda item: item.asset_id)
        cluster_id = _cluster_id(members, features)
        member_ids = {member.asset_id for member in members}
        member_edges = []
        for (left_id, right_id), evidence in sorted(edges.items()):
            if left_id in member_ids and right_id in member_ids:
                member_edges.append({"left_asset_id": left_id, "right_asset_id": right_id, **evidence})
        sha_values = {features[member.asset_id].sha256 for member in members}
        has_sequence_inheritance = any(
            "sequence_family_inheritance" in edge["reasons"] for edge in member_edges
        )
        if len(members) == 1:
            cluster_kind = "singleton"
        elif len(sha_values) == 1:
            cluster_kind = "exact_duplicate"
        elif has_sequence_inheritance:
            cluster_kind = "sequence_family"
        else:
            cluster_kind = "near_duplicate"
        family_ids = sorted({family for member in members for family in member.derivation_family_ids})
        clusters.append(
            {
                "cluster_id": cluster_id,
                "cluster_kind": cluster_kind,
                "asset_ids": [member.asset_id for member in members],
                "record_ids": sorted({record for member in members for record in member.record_ids}),
                "sequence_ids": sorted({sequence for member in members for sequence in member.sequence_ids}),
                "derivation_family_id": family_ids[0] if len(family_ids) == 1 else None,
                "derivation_family_ids": family_ids,
                "members": [
                    {
                        "asset_id": member.asset_id,
                        "content_sha256": features[member.asset_id].sha256,
                        "perceptual_hash": features[member.asset_id].perceptual_hash,
                        "local_embedding_sha256": features[member.asset_id].descriptor_sha256,
                        "record_ids": list(member.record_ids),
                        "sequence_ids": list(member.sequence_ids),
                        "frame_ordinals": list(member.frame_ordinals),
                        "derivation_family_ids": list(member.derivation_family_ids),
                    }
                    for member in members
                ],
                "edges": member_edges,
            }
        )

    clusters.sort(key=lambda cluster: cluster["cluster_id"])
    cluster_by_asset = {
        asset_id: cluster["cluster_id"]
        for cluster in clusters
        for asset_id in cluster["asset_ids"]
    }
    sequence_families = []
    for sequence_id, sequence_items in sorted(sequences.items()):
        asset_ids = sorted({item.asset_id for item in sequence_items})
        family_ids = sorted({family for item in sequence_items for family in item.derivation_family_ids})
        if not family_ids:
            family_ids = ["derivation-family-" + hashlib.sha256(("sequence|" + sequence_id).encode("utf-8")).hexdigest()[:16]]
        cluster_ids = {cluster_by_asset[asset_id] for asset_id in asset_ids}
        if len(cluster_ids) != 1:
            raise AuditInputError(f"sequence_family_split: {sequence_id}")
        sequence_families.append(
            {
                "sequence_id": sequence_id,
                "cluster_id": next(iter(cluster_ids)),
                "derivation_family_id": family_ids[0] if len(family_ids) == 1 else None,
                "derivation_family_ids": family_ids,
                "asset_ids": asset_ids,
            }
        )

    review_pairs: list[dict[str, Any]] = []
    if ssim_review:
        # ponytail: pairwise review is O(n²) per cluster; add an image index/ANN only if audits need scale.
        for cluster in clusters:
            member_ids = cluster["asset_ids"]
            for offset, left_id in enumerate(member_ids):
                for right_id in member_ids[offset + 1 :]:
                    score = round(structural_similarity(features[left_id].image, features[right_id].image), 6)
                    review_pairs.append(
                        {
                            "left_asset_id": left_id,
                            "right_asset_id": right_id,
                            "ssim": score,
                            "review_signal": "similar" if score >= ssim_threshold else "different",
                        }
                    )

    output = {
        "schema_id": SCHEMA_ID,
        "schema_version": SCHEMA_VERSION,
        "algorithm": {
            "algorithm_id": ALGORITHM_ID,
            "sha256": {"name": "sha256", "role": "exact_content_identity"},
            "perceptual_hash": {
                "name": "phash64_dct_v1",
                "distance_metric": "hamming",
                "max_hamming_distance": phash_distance,
                "min_descriptor_similarity": MIN_DESCRIPTOR_FOR_PHASH,
            },
            "local_embedding": {
                "name": "local_descriptor_v1",
                "dimension": DESCRIPTOR_SIZE * DESCRIPTOR_SIZE,
                "similarity_metric": "cosine",
                "min_similarity": descriptor_similarity,
                "learned_model": False,
            },
            "ssim_review": {
                "enabled": ssim_review,
                "name": "ssim_grayscale_v1",
                "threshold": ssim_threshold,
                "admission_oracle": False,
            },
        },
        "input": {
            "manifest_schema_id": INPUT_SCHEMA_ID,
            "asset_count": len(items),
            "manifest_sha256": _json_digest(_canonical_input(items, features)),
        },
        "clusters": clusters,
        "sequence_families": sequence_families,
        "ssim_review": {
            "enabled": ssim_review,
            "admission_oracle": False,
            "pairs": review_pairs,
        },
        "audit": {
            "status": "pass",
            "cluster_count": len(clusters),
            "exact_cluster_count": sum(cluster["cluster_kind"] == "exact_duplicate" for cluster in clusters),
            "near_cluster_count": sum(cluster["cluster_kind"] in {"near_duplicate", "sequence_family"} for cluster in clusters),
            "singleton_count": sum(cluster["cluster_kind"] == "singleton" for cluster in clusters),
            "sequence_family_inheritance": "pass",
            "input_order_independent": True,
            "raw_media_copied_to_git": False,
            "candidate_identity_leakage": False,
        },
    }
    validate_cluster_output(output)
    return output


def validate_cluster_output(output: dict[str, Any]) -> None:
    """Validate the closed cluster receipt without requiring jsonschema."""

    if not isinstance(output, dict) or output.get("schema_id") != SCHEMA_ID or output.get("schema_version") != SCHEMA_VERSION:
        raise AuditInputError("invalid_cluster_schema")
    for required in ("algorithm", "input", "clusters", "sequence_families", "ssim_review", "audit"):
        if required not in output:
            raise AuditInputError(f"cluster_missing_field: {required}")
    algorithm = output["algorithm"]
    if not isinstance(algorithm, dict) or algorithm.get("algorithm_id") != ALGORITHM_ID:
        raise AuditInputError("invalid_cluster_algorithm")
    algorithm_ssim = algorithm.get("ssim_review")
    if not isinstance(algorithm_ssim, dict) or algorithm_ssim.get("admission_oracle") is not False:
        raise AuditInputError("ssim_cannot_be_admission_oracle")
    output_ssim = output["ssim_review"]
    if not isinstance(output_ssim, dict) or output_ssim.get("admission_oracle") is not False:
        raise AuditInputError("ssim_cannot_be_admission_oracle")
    clusters = output["clusters"]
    if not isinstance(clusters, list):
        raise AuditInputError("invalid_clusters")
    seen_assets: set[str] = set()
    seen_cluster_ids: set[str] = set()
    allowed_kinds = {"singleton", "exact_duplicate", "near_duplicate", "sequence_family"}
    for cluster in clusters:
        if not isinstance(cluster, dict) or not CLUSTER_ID_RE.fullmatch(cluster.get("cluster_id", "")):
            raise AuditInputError("invalid_cluster_id")
        if cluster["cluster_id"] in seen_cluster_ids:
            raise AuditInputError("duplicate_cluster_id")
        seen_cluster_ids.add(cluster["cluster_id"])
        if cluster.get("cluster_kind") not in allowed_kinds:
            raise AuditInputError("invalid_cluster_kind")
        asset_ids = cluster.get("asset_ids")
        members = cluster.get("members")
        if not isinstance(asset_ids, list) or not asset_ids or not isinstance(members, list) or len(asset_ids) != len(members):
            raise AuditInputError("invalid_cluster_members")
        if asset_ids != sorted(asset_ids) or len(set(asset_ids)) != len(asset_ids):
            raise AuditInputError("unstable_cluster_member_order")
        for asset_id, member in zip(asset_ids, members):
            _ensure_id(asset_id, "cluster.asset_id")
            if asset_id in seen_assets:
                raise AuditInputError("asset_in_multiple_clusters")
            seen_assets.add(asset_id)
            if not isinstance(member, dict) or member.get("asset_id") != asset_id:
                raise AuditInputError("invalid_cluster_member")
            _ensure_sha(member.get("content_sha256"), "cluster.member.content_sha256")
            if not isinstance(member.get("perceptual_hash"), str) or not re.fullmatch(r"[0-9a-f]{16}", member["perceptual_hash"]):
                raise AuditInputError("invalid_perceptual_hash")
            _ensure_sha(member.get("local_embedding_sha256"), "cluster.member.local_embedding_sha256")
        if cluster["cluster_kind"] == "exact_duplicate":
            if len({member["content_sha256"] for member in members}) != 1:
                raise AuditInputError("exact_cluster_sha_mismatch")
    sequences = output["sequence_families"]
    if not isinstance(sequences, list):
        raise AuditInputError("invalid_sequence_families")
    sequence_assets: set[str] = set()
    for sequence in sequences:
        if not isinstance(sequence, dict):
            raise AuditInputError("invalid_sequence_family")
        _ensure_id(sequence.get("sequence_id"), "sequence.sequence_id")
        if sequence.get("cluster_id") not in seen_cluster_ids:
            raise AuditInputError("sequence_cluster_missing")
        asset_ids = sequence.get("asset_ids")
        if not isinstance(asset_ids, list) or asset_ids != sorted(asset_ids) or not asset_ids:
            raise AuditInputError("invalid_sequence_assets")
        for asset_id in asset_ids:
            if asset_id not in seen_assets:
                raise AuditInputError("sequence_asset_missing")
            if asset_id in sequence_assets:
                raise AuditInputError("asset_in_multiple_sequences")
            sequence_assets.add(asset_id)


def _self_test() -> None:
    with TemporaryDirectory(prefix="camera-audit-self-test-") as temp:
        root = Path(temp)
        image = Image.new("RGB", (64, 64), (25, 25, 25))
        draw = ImageDraw.Draw(image)
        draw.rectangle((16, 12, 49, 52), fill=(220, 120, 60))
        first, second = root / "a.png", root / "b.png"
        image.save(first)
        second.write_bytes(first.read_bytes())
        output = cluster_media([MediaItem("asset-a", first), MediaItem("asset-b", second)])
        assert output["audit"]["exact_cluster_count"] == 1
        assert output["clusters"][0]["cluster_kind"] == "exact_duplicate"
        validate_cluster_output(json.loads(json.dumps(output)))
    print("PASS M3-007 camera_dataset_audit self-test")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", "--records", "--input-manifest", "--asset-manifest", required=False, type=Path, help="camera audit input JSON/JSONL")
    parser.add_argument("--media-root", type=Path, help="root containing external media paths")
    parser.add_argument("--media-manifest", "--media-map", type=Path, help="asset_id to external path JSON/JSONL")
    parser.add_argument("--output", "-o", type=Path, help="cluster receipt path; stdout when omitted")
    parser.add_argument("--ssim-review", "--ssim", action="store_true", help="add SSIM review signals without changing admission")
    parser.add_argument("--phash-distance", type=int, default=DEFAULT_PHASH_DISTANCE)
    parser.add_argument("--descriptor-similarity", type=float, default=DEFAULT_DESCRIPTOR_SIMILARITY)
    parser.add_argument("--ssim-threshold", type=float, default=DEFAULT_SSIM_REVIEW_THRESHOLD)
    parser.add_argument("--self-test", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.self_test:
            _self_test()
            return 0
        if args.manifest is None:
            raise AuditInputError("--manifest is required unless --self-test is used")
        items = load_manifest(args.manifest, media_root=args.media_root, media_manifest=args.media_manifest)
        output = cluster_media(
            items,
            ssim_review=args.ssim_review,
            phash_distance=args.phash_distance,
            descriptor_similarity=args.descriptor_similarity,
            ssim_threshold=args.ssim_threshold,
        )
        rendered = json.dumps(output, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
        if args.output is None:
            sys.stdout.write(rendered)
        else:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(rendered, encoding="utf-8")
            audit = output["audit"]
            print(
                f"PASS M3-007 camera_dataset_audit assets={output['input']['asset_count']} "
                f"clusters={audit['cluster_count']} exact={audit['exact_cluster_count']} "
                f"near={audit['near_cluster_count']} singleton={audit['singleton_count']} "
                f"ssim_review={args.ssim_review} output={args.output}"
            )
        return 0
    except (AuditInputError, OSError, ValueError) as exc:
        print(f"FAIL M3-007 camera_dataset_audit: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
