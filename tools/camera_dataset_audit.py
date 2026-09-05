#!/usr/bin/env python3
"""Deterministic Camera Coach dedup audit and protected split tooling (M3-007/M3-008).

The audit consumes a small external-media manifest. It never copies media and
never writes source paths, labels, or candidate/model fields to the cluster
or split receipt. The local ``embedding`` is intentionally a deterministic image
descriptor, not a learned model; a model-backed descriptor is an upgrade
boundary for a future versioned contract. Split inputs are metadata-only and
assign indivisible protected-family components to train, calibration, and
locked_test without exposing locked labels or content.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass, field, replace
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re
import struct
import sys
from tempfile import TemporaryDirectory
from typing import Any, Iterable
import warnings

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SCHEMA_PATH = ROOT / "datasets/camera-coach/v1/cluster-schema.json"
SPLIT_SCHEMA_PATH = ROOT / "datasets/camera-coach/v1/split-manifest-schema.json"
SCHEMA_ID = "camera-dedup-clusters-v1"
INPUT_SCHEMA_ID = "camera-dedup-input-v1"
SPLIT_INPUT_SCHEMA_ID = "camera-split-input-v1"
SPLIT_MANIFEST_TYPE = "camera_split_input"
SPLIT_SCHEMA_ID = "camera-split-manifest-v1"
SCHEMA_VERSION = "v1.0.0"
ALGORITHM_ID = "camera-dedup-v1"
SPLIT_ALGORITHM_ID = "camera-split-v1"
SPLITS = ("train", "calibration", "locked_test")
BUCKETS = ("organic", "synthetic")
PROTECTED_CATEGORIES = (
    "source_shoot",
    "scene",
    "person",
    "location",
    "time",
    "derivation",
    "sequence",
    "take",
    "device",
    "dedup_cluster",
)
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
ID_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
PHASH_SIZE = 32
PHASH_LOW_FREQUENCY_SIZE = 8
PHASH_BITS = PHASH_LOW_FREQUENCY_SIZE * PHASH_LOW_FREQUENCY_SIZE
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
RESOLVED_REVIEW_STATUSES = {"dual_reviewed", "adjudicated"}
SPLIT_PATH_FIELDS = {
    "path",
    "media_path",
    "file",
    "asset_path",
    "raw_storage",
    "storage",
    "storage_path",
    "uri",
    "url",
    "media_uri",
    "asset_uri",
}
SPLIT_CONTENT_FIELDS = {
    "label",
    "labels",
    "locked_label",
    "locked_labels",
    "content",
    "content_bytes",
    "content_sha256",
    "raw_content",
    "raw_media",
    "media_bytes",
    "pixels",
    "image",
}
SPLIT_HEADER_FIELDS = {
    "manifest_type",
    "schema_id",
    "schema_version",
    "manifest_version",
    "record_count",
    "entries",
}
SPLIT_RECORD_FIELDS = {
    "record_id",
    "record_type",
    "split",
    "bucket",
    "source_bucket",
    "source_kind",
    "rights_disposition",
    "source_shoot_id",
    "scene_family_id",
    "person_family_ids",
    "location_family_id",
    "time_family_id",
    "derivation_family_id",
    "take_family_id",
    "device_family_id",
    "sequence_id",
    "asset_id",
    "asset_ids",
    "source_asset_ids",
    "media",
    "provenance",
    "capture",
    "sequence",
    "review",
    # Kept in the allowlist so _split_review_status can reject the legacy
    # status-only projection with its specific admission error.
    "review_status",
}
SPLIT_PROVENANCE_FIELDS = {
    "source_shoot_id",
    "derivation_family_id",
    "rights_disposition",
    "source_kind",
    "asset_id",
    "asset_ids",
    "source_asset_ids",
}
SPLIT_CAPTURE_FIELDS = {
    "source_shoot_id",
    "scene_family_id",
    "person_family_ids",
    "location_family_id",
    "time_family_id",
    "take_family_id",
    "device_family_id",
    "sequence_id",
    "asset_id",
    "asset_ids",
    "source_asset_ids",
}
SPLIT_MEDIA_FIELDS = {"asset_id", "asset_ids"}
SPLIT_SEQUENCE_FIELDS = {"sequence_id", "derivation_family_id", "frames"}
SPLIT_FRAME_FIELDS = {"asset_id", "asset_ids", "sequence_id", "ordinal", "derivation_family_id"}
SPLIT_REVIEW_FIELDS = {"status", "vote_history", "adjudication_history"}
SPLIT_VOTE_FIELDS = {"vote_id", "annotator_id", "submitted_at", "decision"}
SPLIT_ADJUDICATION_FIELDS = {
    "adjudication_id",
    "adjudicator_id",
    "occurred_at",
    "based_on_vote_ids",
    "outcome",
}


class AuditInputError(ValueError):
    """Raised when an audit input cannot be safely interpreted."""


_CAMERA_COACH_CHECK: Any | None = None
_ADMISSION_TOKEN = object()


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


@dataclass(frozen=True)
class _SplitAdmission:
    token: object
    rights_disposition: str
    review_status: str
    evidence_sha256: str


@dataclass(frozen=True, init=False)
class SplitRecord:
    """Metadata-only record projection consumed by the M3-008 splitter."""

    record_id: str
    asset_ids: tuple[str, ...]
    bucket: str
    families: tuple[tuple[str, tuple[str, ...]], ...]
    rights_disposition: str
    review_status: str
    _admission: _SplitAdmission = field(repr=False)

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        raise TypeError("SplitRecord must be produced by load_split_manifest")

    def family_map(self) -> dict[str, tuple[str, ...]]:
        return dict(self.families)


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
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(path) as opened:
                opened.verify()
            with Image.open(path) as opened:
                opened.load()
                if opened.width < 1 or opened.height < 1:
                    raise AuditInputError(f"invalid_media_dimensions: {path}")
                return opened.convert("RGB")
    except AuditInputError:
        raise
    except (Image.DecompressionBombError, Image.DecompressionBombWarning) as exc:
        raise AuditInputError(f"decompression_bomb: {path}") from exc
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
    # Exclude the DC coefficient from the threshold, but retain its bit so the
    # emitted hash has exactly 64 bits rather than a padded 63-bit body.
    median = sorted(coefficients[1:])[len(coefficients[1:]) // 2]
    bits = sum((value > median) << index for index, value in enumerate(coefficients))
    result = f"{bits:0{PHASH_BITS // 4}x}"
    if len(result) != PHASH_BITS // 4:
        raise AuditInputError("invalid_perceptual_hash_length")
    return result


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
        or schema_id not in ({INPUT_SCHEMA_ID, SPLIT_INPUT_SCHEMA_ID} | CAMERA_RECORD_SCHEMA_IDS)
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


def _metadata(
    entry: dict[str, Any], *, require_rights: bool = True
) -> tuple[str | None, str | None, str | None, int | None, str | None]:
    record_id = entry.get("record_id")
    if record_id is not None:
        record_id = _ensure_id(record_id, "record_id")
    provenance = entry.get("provenance")
    family = entry.get("derivation_family_id")
    rights = entry.get("rights_disposition")
    if provenance is not None:
        if not isinstance(provenance, dict):
            raise AuditInputError("invalid_provenance")
        provenance_family = provenance.get("derivation_family_id")
        provenance_rights = provenance.get("rights_disposition")
        if family is not None and provenance_family is not None and family != provenance_family:
            raise AuditInputError("derivation_family_conflict")
        if rights is not None and provenance_rights is not None and rights != provenance_rights:
            raise AuditInputError("rights_disposition_conflict")
        family = provenance_family or family
        rights = provenance_rights or rights
        if family is None and require_rights and entry.get("sequence") is None and entry.get("sequence_id") is None:
            raise AuditInputError("missing_derivation_family_id")
    if family is not None:
        family = _ensure_id(family, "derivation_family_id")
    if rights is None and require_rights:
        raise AuditInputError("missing_rights_disposition")
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
    _reject_forbidden(payload, str(path))
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
        if entry.get("record_count") is not None and not any(
            key in entry for key in ("asset_id", "asset_ids", "media", "path", "media_path", "file", "asset_path")
        ):
            _validate_header(entry, f"{path}:header")
            continue
        asset_id = _ensure_id(entry.get("asset_id"), "media_map.asset_id")
        raw_path, declared = _extract_path(entry, {})
        if raw_path is None:
            raise AuditInputError(f"missing_media_path: {asset_id}")
        resolved = _resolve_path(raw_path, media_root)
        candidate = {"path": str(resolved), "content_sha256": declared}
        existing = result.get(asset_id)
        if existing is not None:
            if existing["path"] != candidate["path"]:
                raise AuditInputError(f"asset_path_conflict: {asset_id}")
            if existing.get("content_sha256") != candidate["content_sha256"]:
                raise AuditInputError(f"asset_sha256_conflict: {asset_id}")
            continue
        result[asset_id] = candidate
    return result


def _derived_sequence_family(sequence_id: str) -> str:
    return "derivation-family-" + hashlib.sha256(("sequence|" + sequence_id).encode("utf-8")).hexdigest()[:16]


def _resolve_sequence_families(items: list[MediaItem]) -> list[MediaItem]:
    """Require one family per sequence, deriving one when the input omits it."""

    sequences: dict[str, list[int]] = {}
    resolved: list[MediaItem] = []
    for index, item in enumerate(items):
        if len(item.derivation_family_ids) > 1:
            raise AuditInputError(f"asset_derivation_family_conflict: {item.asset_id}")
        if len(item.sequence_ids) > 1:
            raise AuditInputError(f"asset_sequence_conflict: {item.asset_id}")
        resolved.append(item)
        for sequence_id in item.sequence_ids:
            sequences.setdefault(sequence_id, []).append(index)
    for sequence_id, indexes in sorted(sequences.items()):
        family_ids = {
            family
            for index in indexes
            for family in resolved[index].derivation_family_ids
        }
        if len(family_ids) > 1:
            raise AuditInputError(f"sequence_derivation_family_conflict: {sequence_id}")
        family_id = next(iter(family_ids), _derived_sequence_family(sequence_id))
        for index in indexes:
            item = resolved[index]
            if family_id not in item.derivation_family_ids:
                resolved[index] = replace(
                    item,
                    derivation_family_ids=tuple(sorted((*item.derivation_family_ids, family_id))),
                )
    return resolved


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
            sequence_family = sequence.get("derivation_family_id")
            if sequence_family is not None:
                sequence_family = _ensure_id(sequence_family, "sequence.derivation_family_id")
                if family is not None and family != sequence_family:
                    raise AuditInputError("sequence_derivation_family_conflict")
                family = sequence_family
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
                _, frame_family, frame_sequence_id, _, _ = _metadata(frame, require_rights=False)
                if frame_family is not None and family is not None and frame_family != family:
                    raise AuditInputError("sequence_derivation_family_conflict")
                if frame_sequence_id is not None and frame_sequence_id != seq_id:
                    raise AuditInputError("asset_sequence_conflict")
                frame_family = frame_family or family
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
                    family=frame_family,
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
    return sorted(_resolve_sequence_families(frozen), key=lambda item: item.asset_id)


def _split_no_media_paths(value: Any, path: str = "manifest") -> None:
    """Reject raw-media references in the metadata-only split projection."""

    if isinstance(value, dict):
        for key, child in value.items():
            lowered = key.lower() if isinstance(key, str) else ""
            if lowered in SPLIT_PATH_FIELDS or lowered.endswith("_path"):
                if lowered in {"raw_storage", "storage"} and child == "outside_git":
                    _split_no_media_paths(child, f"{path}.{key}")
                    continue
                raise AuditInputError(f"raw_media_reference_in_split_input: {path}.{key}")
            _split_no_media_paths(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _split_no_media_paths(child, f"{path}[{index}]")


def _split_no_content_payloads(value: Any, path: str = "manifest") -> None:
    """Reject labels, raw content, and pixel payloads from split inputs."""

    if isinstance(value, dict):
        for key, child in value.items():
            lowered = key.lower() if isinstance(key, str) else ""
            if lowered in SPLIT_CONTENT_FIELDS:
                raise AuditInputError(f"content_payload_in_split_input: {path}.{key}")
            _split_no_content_payloads(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _split_no_content_payloads(child, f"{path}[{index}]")


def _split_allowlist(value: Any, allowed: set[str], path: str) -> None:
    if not isinstance(value, dict):
        raise AuditInputError(f"invalid_split_object: {path}")
    unknown = sorted((key for key in value if key not in allowed), key=str)
    if unknown:
        raise AuditInputError(f"unknown_split_field: {path}.{unknown[0]}")


def _split_validate_header_values(header: dict[str, Any], path: str) -> None:
    if type(header.get("manifest_type")) is not str or header["manifest_type"] != SPLIT_MANIFEST_TYPE:
        raise AuditInputError(f"invalid_split_manifest_type: {path}.manifest_type")
    if "record_count" in header and type(header["record_count"]) is not int:
        raise AuditInputError(f"invalid_split_record_count: {path}.record_count")


def _split_validate_record_topology(record: Any, path: str) -> None:
    _split_allowlist(record, SPLIT_RECORD_FIELDS, path)
    for field_name, allowed in (
        ("provenance", SPLIT_PROVENANCE_FIELDS),
        ("capture", SPLIT_CAPTURE_FIELDS),
        ("media", SPLIT_MEDIA_FIELDS),
        ("sequence", SPLIT_SEQUENCE_FIELDS),
        ("review", SPLIT_REVIEW_FIELDS),
    ):
        value = record.get(field_name)
        if value is None:
            continue
        _split_allowlist(value, allowed, f"{path}.{field_name}")
    sequence = record.get("sequence")
    if isinstance(sequence, dict) and "frames" in sequence:
        frames = sequence["frames"]
        if not isinstance(frames, list):
            raise AuditInputError(f"invalid_split_list: {path}.sequence.frames")
        for index, frame in enumerate(frames):
            _split_allowlist(frame, SPLIT_FRAME_FIELDS, f"{path}.sequence.frames[{index}]")
    review = record.get("review")
    if isinstance(review, dict):
        for field_name, allowed in (
            ("vote_history", SPLIT_VOTE_FIELDS),
            ("adjudication_history", SPLIT_ADJUDICATION_FIELDS),
        ):
            history = review.get(field_name)
            if history is None:
                continue
            if not isinstance(history, list):
                raise AuditInputError(f"invalid_split_list: {path}.review.{field_name}")
            for index, item in enumerate(history):
                _split_allowlist(item, allowed, f"{path}.review.{field_name}[{index}]")


def _split_validate_record_list(entries: Any, path: str) -> None:
    if not isinstance(entries, list):
        raise AuditInputError(f"invalid_split_list: {path}")
    for index, entry in enumerate(entries):
        _split_validate_record_topology(entry, f"{path}[{index}]")


def _split_validate_topology(payload: Any) -> None:
    """Validate the complete metadata-only split input object topology."""

    if isinstance(payload, dict):
        _split_allowlist(payload, SPLIT_HEADER_FIELDS, "manifest")
        _split_validate_header_values(payload, "manifest")
        if "entries" not in payload:
            raise AuditInputError("missing_split_manifest_entries")
        _split_validate_record_list(payload["entries"], "manifest.entries")
        return
    if isinstance(payload, list):
        if not payload or not isinstance(payload[0], dict) or "record_id" in payload[0]:
            raise AuditInputError("missing_split_manifest_header")
        _split_allowlist(payload[0], SPLIT_HEADER_FIELDS, "manifest[0]")
        _split_validate_header_values(payload[0], "manifest[0]")
        if "entries" in payload[0]:
            _split_validate_record_list(payload[0]["entries"], "manifest[0].entries")
        _split_validate_record_list(payload[1:], "manifest")
        return
    raise AuditInputError("invalid_split_manifest_topology")


def _split_consistent_field(
    entry: dict[str, Any],
    key: str,
    *nested: dict[str, Any] | None,
) -> Any:
    values = [entry[key]] if key in entry else []
    values.extend(source[key] for source in nested if isinstance(source, dict) and key in source)
    if not values:
        return None
    first = values[0]
    if any(value != first for value in values[1:]):
        raise AuditInputError(f"split_field_conflict: {key}")
    return first


def _split_id_values(value: Any, field_name: str, *, required: bool = True) -> tuple[str, ...]:
    if value is None:
        if required:
            raise AuditInputError(f"missing_protected_id: {field_name}")
        return ()
    if isinstance(value, str):
        return (_ensure_id(value, field_name),)
    if not isinstance(value, list):
        raise AuditInputError(f"invalid_id_list: {field_name}")
    if not value and required:
        raise AuditInputError(f"missing_protected_id: {field_name}")
    result = tuple(sorted({_ensure_id(item, field_name) for item in value}))
    if len(result) != len(value):
        raise AuditInputError(f"duplicate_id: {field_name}")
    return result


def _split_asset_values(entry: dict[str, Any], provenance: dict[str, Any] | None, capture: dict[str, Any] | None) -> tuple[str, ...]:
    values: list[Any] = []
    for source in (entry, provenance, capture):
        if not isinstance(source, dict):
            continue
        if "asset_id" in source:
            values.append(source["asset_id"])
        if "asset_ids" in source:
            asset_ids = source["asset_ids"]
            if not isinstance(asset_ids, list):
                raise AuditInputError("invalid_asset_ids")
            if len({item for item in asset_ids if isinstance(item, str)}) != len(asset_ids):
                raise AuditInputError("duplicate_asset_id")
            values.extend(asset_ids)
        if "source_asset_ids" in source:
            source_asset_ids = source["source_asset_ids"]
            if not isinstance(source_asset_ids, list):
                raise AuditInputError("invalid_source_asset_ids")
            if len({item for item in source_asset_ids if isinstance(item, str)}) != len(source_asset_ids):
                raise AuditInputError("duplicate_asset_id")
            values.extend(source_asset_ids)
    media = entry.get("media")
    if isinstance(media, dict):
        if "asset_id" in media:
            values.append(media["asset_id"])
        if "asset_ids" in media:
            asset_ids = media["asset_ids"]
            if not isinstance(asset_ids, list):
                raise AuditInputError("invalid_asset_ids")
            if len({item for item in asset_ids if isinstance(item, str)}) != len(asset_ids):
                raise AuditInputError("duplicate_asset_id")
            values.extend(asset_ids)
    sequence = entry.get("sequence")
    if isinstance(sequence, dict):
        frames = sequence.get("frames")
        if frames is not None:
            if not isinstance(frames, list) or not frames:
                raise AuditInputError("invalid_sequence_frames")
            frame_asset_ids_seen: set[str] = set()
            for frame in frames:
                if not isinstance(frame, dict):
                    raise AuditInputError("invalid_sequence_frame")
                if "asset_id" in frame:
                    frame_asset_id = _ensure_id(frame["asset_id"], "asset_id")
                    if frame_asset_id in frame_asset_ids_seen:
                        raise AuditInputError("duplicate_asset_id")
                    frame_asset_ids_seen.add(frame_asset_id)
                    values.append(frame_asset_id)
                frame_asset_ids = frame.get("asset_ids")
                if frame_asset_ids is not None:
                    if not isinstance(frame_asset_ids, list):
                        raise AuditInputError("invalid_frame_asset_ids")
                    if len({item for item in frame_asset_ids if isinstance(item, str)}) != len(frame_asset_ids):
                        raise AuditInputError("duplicate_asset_id")
                    normalized_frame_assets = [_ensure_id(item, "asset_id") for item in frame_asset_ids]
                    if frame_asset_ids_seen.intersection(normalized_frame_assets):
                        raise AuditInputError("duplicate_asset_id")
                    frame_asset_ids_seen.update(normalized_frame_assets)
                    values.extend(normalized_frame_assets)
                ordinal = frame.get("ordinal")
                if ordinal is not None and (type(ordinal) is not int or ordinal < 0):
                    raise AuditInputError("invalid_frame_ordinal")
    if not values:
        raise AuditInputError("missing_asset_id")
    result = tuple(sorted({_ensure_id(value, "asset_id") for value in values}))
    return result


def _release_review_checker() -> Any:
    global _CAMERA_COACH_CHECK
    if _CAMERA_COACH_CHECK is not None:
        return _CAMERA_COACH_CHECK
    checker_path = ROOT / "tools/dataset/camera_coach_check.py"
    try:
        spec = importlib.util.spec_from_file_location("_camera_coach_check_for_split", checker_path)
        if spec is None or spec.loader is None:
            raise AuditInputError("release_review_validator_unavailable")
        checker = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(checker)
    except (ImportError, OSError, ValueError) as exc:
        raise AuditInputError("release_review_validator_unavailable") from exc
    _CAMERA_COACH_CHECK = checker
    return checker


def _split_review_status(entry: dict[str, Any]) -> str:
    review = entry.get("review")
    if not isinstance(review, dict):
        if "review_status" in entry:
            raise AuditInputError("review_status_only_not_admissible")
        raise AuditInputError("review_not_admissible")
    if "review_status" in entry:
        raise AuditInputError("review_status_only_not_admissible")
    checker = _release_review_checker()
    errors: list[str] = []
    checker._validate_closed_keys(review, "review", "review", errors)
    checker._validate_review(review, errors)
    # The release helper has identical admission rules for train and
    # calibration; use train as the unassigned-input gate.
    checker._validate_release_review(review, "train", errors)
    status = review.get("status")
    if not isinstance(status, str) or status not in RESOLVED_REVIEW_STATUSES:
        errors.append("review_not_admissible: requires dual_reviewed or adjudicated")
    if errors:
        raise AuditInputError(f"review_not_admissible: {errors[0]}")
    return status


def _split_admission_digest(rights_disposition: str, review: dict[str, Any]) -> str:
    return _json_digest(
        {
            "rights_disposition": rights_disposition,
            "review": review,
        }
    )


def _validate_split_admission(record: SplitRecord) -> None:
    record_id = getattr(record, "record_id", "<unknown>")
    admission = getattr(record, "_admission", None)
    if not isinstance(admission, _SplitAdmission) or admission.token is not _ADMISSION_TOKEN:
        raise AuditInputError(f"split_record_admission_required: {record_id}")
    record_rights = getattr(record, "rights_disposition", None)
    record_status = getattr(record, "review_status", None)
    if admission.rights_disposition != record_rights:
        raise AuditInputError(f"split_record_admission_conflict: rights_disposition:{record_id}")
    if admission.review_status != record_status:
        raise AuditInputError(f"split_record_admission_conflict: review_status:{record_id}")
    if not isinstance(admission.evidence_sha256, str) or not SHA256_RE.fullmatch(admission.evidence_sha256):
        raise AuditInputError(f"split_record_admission_invalid: {record_id}")


def _split_record_entry(entry: dict[str, Any]) -> SplitRecord:
    if not isinstance(entry, dict):
        raise AuditInputError("invalid_split_record")
    record_id = _ensure_id(entry.get("record_id"), "record_id")
    if "split" in entry and entry["split"] not in (None, ""):
        raise AuditInputError("preassigned_split_not_allowed")
    provenance = entry.get("provenance")
    capture = entry.get("capture")
    sequence = entry.get("sequence")
    if provenance is not None and not isinstance(provenance, dict):
        raise AuditInputError("invalid_provenance")
    if capture is not None and not isinstance(capture, dict):
        raise AuditInputError("invalid_capture")
    if sequence is not None and not isinstance(sequence, dict):
        raise AuditInputError("invalid_sequence")

    rights = _split_consistent_field(entry, "rights_disposition", provenance)
    if rights is None:
        raise AuditInputError("missing_rights_disposition")
    if not isinstance(rights, str) or rights not in ALLOWED_RIGHTS:
        raise AuditInputError("rights_not_admissible")
    source_kind = _split_consistent_field(entry, "source_kind", provenance)
    if source_kind is not None and not isinstance(source_kind, str):
        raise AuditInputError("invalid_source_kind")
    bucket = _split_consistent_field(entry, "bucket")
    if bucket is None:
        bucket = _split_consistent_field(entry, "source_bucket")
    source_bucket = {
        "synthetic_fixture": "synthetic",
        "synthetic": "synthetic",
        "fixture": "synthetic",
        "organic": "organic",
        "original": "organic",
        "original_still": "organic",
        "captured": "organic",
    }
    if bucket is None and isinstance(source_kind, str):
        bucket = source_bucket.get(source_kind)
    if not isinstance(bucket, str) or bucket not in BUCKETS:
        raise AuditInputError("invalid_bucket")
    if isinstance(source_kind, str) and source_kind in source_bucket and source_bucket[source_kind] != bucket:
        raise AuditInputError("bucket_source_kind_conflict")

    families: dict[str, tuple[str, ...]] = {}
    family_sources = {
        "source_shoot": ("source_shoot_id", (provenance, capture)),
        "scene": ("scene_family_id", (capture,)),
        "person": ("person_family_ids", (capture,)),
        "location": ("location_family_id", (capture,)),
        "time": ("time_family_id", (capture,)),
        "derivation": ("derivation_family_id", (provenance,)),
    }
    for category, (field_name, nested_sources) in family_sources.items():
        value = _split_consistent_field(entry, field_name, *nested_sources)
        # M3-007 may derive the family for a temporal sequence; split_records
        # resolves that one narrow omission against the cluster receipt.
        required = category != "derivation" or sequence is None
        families[category] = _split_id_values(value, field_name, required=required)
    for category, field_name in (("take", "take_family_id"), ("device", "device_family_id")):
        value = _split_consistent_field(entry, field_name, capture)
        families[category] = _split_id_values(value, field_name, required=False)

    sequence_id = _split_consistent_field(entry, "sequence_id", sequence, capture)
    sequence_ids = _split_id_values(sequence_id, "sequence_id", required=False)
    if sequence is not None:
        sequence_ids = _split_id_values(sequence.get("sequence_id", sequence_id), "sequence.sequence_id")
        sequence_family = sequence.get("derivation_family_id")
        if sequence_family is not None:
            sequence_family = _ensure_id(sequence_family, "sequence.derivation_family_id")
            declared_derivation = families.get("derivation", ())
            if declared_derivation and declared_derivation != (sequence_family,):
                raise AuditInputError("sequence_derivation_family_conflict")
            families["derivation"] = (sequence_family,)
        frame_families: set[str] = set()
        frame_ordinals: set[int] = set()
        frames = sequence.get("frames")
        if frames is not None:
            for frame in frames:
                frame_sequence_id = frame.get("sequence_id") if isinstance(frame, dict) else None
                if frame_sequence_id is not None and frame_sequence_id != sequence_ids[0]:
                    raise AuditInputError("asset_sequence_conflict")
                frame_ordinal = frame.get("ordinal") if isinstance(frame, dict) else None
                if frame_ordinal is not None:
                    if type(frame_ordinal) is not int or frame_ordinal < 0 or frame_ordinal in frame_ordinals:
                        raise AuditInputError("invalid_frame_ordinal")
                    frame_ordinals.add(frame_ordinal)
                frame_family = frame.get("derivation_family_id") if isinstance(frame, dict) else None
                if frame_family is not None:
                    frame_families.add(_ensure_id(frame_family, "frame.derivation_family_id"))
            if len(frame_families) > 1:
                raise AuditInputError("sequence_derivation_family_conflict")
            if frame_families:
                frame_family = next(iter(frame_families))
                declared_derivation = families.get("derivation", ())
                if declared_derivation and declared_derivation != (frame_family,):
                    raise AuditInputError("sequence_derivation_family_conflict")
                families["derivation"] = (frame_family,)
    record_type = entry.get("record_type")
    if record_type is not None and not isinstance(record_type, str):
        raise AuditInputError("invalid_record_type")
    is_temporal = sequence is not None or bool(sequence_ids) or record_type in {"temporal", "episode"}
    if is_temporal and not sequence_ids:
        raise AuditInputError("missing_sequence_id")
    families["sequence"] = sequence_ids
    assets = _split_asset_values(entry, provenance, capture)
    review_status = _split_review_status(entry)
    admission = _SplitAdmission(
        token=_ADMISSION_TOKEN,
        rights_disposition=rights,
        review_status=review_status,
        evidence_sha256=_split_admission_digest(rights, entry["review"]),
    )
    record = object.__new__(SplitRecord)
    object.__setattr__(record, "record_id", record_id)
    object.__setattr__(record, "asset_ids", assets)
    object.__setattr__(record, "bucket", bucket)
    object.__setattr__(record, "families", tuple((category, values) for category, values in sorted(families.items()) if values))
    object.__setattr__(record, "rights_disposition", rights)
    object.__setattr__(record, "review_status", review_status)
    object.__setattr__(record, "_admission", admission)
    return record


def load_split_manifest(path: Path) -> list[SplitRecord]:
    """Load a metadata-only, unassigned M3-008 record projection."""

    path = Path(path)
    payload = _read_json_or_jsonl(path)
    _split_no_content_payloads(payload, str(path))
    _reject_forbidden(payload, str(path))
    _split_no_media_paths(payload, str(path))
    _split_validate_topology(payload)
    entries, header = _container_entries(payload, str(path))
    if isinstance(payload, list):
        if not payload or not isinstance(payload[0], dict) or "record_id" in payload[0]:
            raise AuditInputError(f"missing_split_manifest_header: {path}")
        header = payload[0]
        entries = payload[1:]
    _validate_header(header, str(path))
    if header.get("schema_id") != SPLIT_INPUT_SCHEMA_ID:
        raise AuditInputError(f"invalid_split_schema_id: {path}")
    if header.get("schema_version") != SCHEMA_VERSION or (
        "manifest_version" in header and header.get("manifest_version") != SCHEMA_VERSION
    ):
        raise AuditInputError(f"invalid_split_schema_version: {path}")
    records: list[SplitRecord] = []
    for entry in entries:
        if entry.get("record_count") is not None and "record_id" not in entry:
            _validate_header(entry, f"{path}:header")
            continue
        records.append(_split_record_entry(entry))
    if not records:
        raise AuditInputError("empty_split_manifest")
    record_ids = [record.record_id for record in records]
    if len(set(record_ids)) != len(record_ids):
        raise AuditInputError("duplicate_record_id")
    if "record_count" in header and header["record_count"] != len(records):
        raise AuditInputError(f"split_manifest_record_count_mismatch: {path}")
    return sorted(records, key=lambda record: record.record_id)


load_split_records = load_split_manifest


def _canonical_split_records(records: Iterable[SplitRecord]) -> list[dict[str, Any]]:
    return [
        {
            "record_id": record.record_id,
            "asset_ids": list(record.asset_ids),
            "bucket": record.bucket,
            "families": {category: list(values) for category, values in record.families},
            "rights_disposition": record.rights_disposition,
            "review_status": record.review_status,
            "admission_sha256": record._admission.evidence_sha256,
        }
        for record in sorted(records, key=lambda item: item.record_id)
    ]


def _cluster_receipt_index(cluster_output: dict[str, Any]) -> tuple[dict[str, str], dict[str, tuple[str, str]]]:
    validate_cluster_output(cluster_output)
    if cluster_output.get("schema_id") != SCHEMA_ID:
        raise AuditInputError("invalid_cluster_receipt_schema_id")
    asset_to_cluster: dict[str, str] = {}
    cluster_ids: set[str] = set()
    for cluster in cluster_output["clusters"]:
        cluster_id = cluster["cluster_id"]
        if cluster_id in cluster_ids:
            raise AuditInputError(f"duplicate_cluster_id: {cluster_id}")
        cluster_ids.add(cluster_id)
        asset_ids = list(cluster["asset_ids"])
        member_ids = [member["asset_id"] for member in cluster["members"]]
        if sorted(asset_ids) != sorted(member_ids) or len(set(asset_ids)) != len(asset_ids):
            raise AuditInputError(f"cluster_membership_conflict: {cluster_id}")
        for asset_id in asset_ids:
            if asset_id in asset_to_cluster:
                raise AuditInputError(f"asset_cluster_conflict: {asset_id}")
            asset_to_cluster[asset_id] = cluster_id
    sequence_index: dict[str, tuple[str, str]] = {}
    for sequence in cluster_output["sequence_families"]:
        sequence_id = sequence["sequence_id"]
        if sequence_id in sequence_index:
            raise AuditInputError(f"duplicate_sequence_family: {sequence_id}")
        family_ids = sequence["derivation_family_ids"]
        if len(family_ids) != 1 or sequence["derivation_family_id"] != family_ids[0]:
            raise AuditInputError(f"sequence_derivation_family_conflict: {sequence_id}")
        sequence_assets = sequence["asset_ids"]
        if not sequence_assets or any(asset_id not in asset_to_cluster for asset_id in sequence_assets):
            raise AuditInputError(f"sequence_asset_missing: {sequence_id}")
        cluster_id = sequence["cluster_id"]
        if any(asset_to_cluster[asset_id] != cluster_id for asset_id in sequence_assets):
            raise AuditInputError(f"sequence_family_split: {sequence_id}")
        sequence_index[sequence_id] = (cluster_id, family_ids[0])
    return asset_to_cluster, sequence_index


def _split_family_hash(category: str, value: str) -> str:
    return "fh_" + hashlib.sha256(f"{SPLIT_ALGORITHM_ID}|{category}|{value}".encode("utf-8")).hexdigest()[:16]


def _split_component_id(record_ids: Iterable[str]) -> str:
    canonical = "|".join(sorted(record_ids))
    return "csp_" + hashlib.sha256(f"{SPLIT_ALGORITHM_ID}|{canonical}".encode("utf-8")).hexdigest()[:16]


def _split_targets(count: int, ratios: dict[str, float]) -> dict[str, int]:
    bases = {split: math.floor(count * ratios[split]) for split in SPLITS}
    remainder = count - sum(bases.values())
    fractions = sorted(
        ((count * ratios[split] - bases[split], index, split) for index, split in enumerate(SPLITS)),
        key=lambda item: (-item[0], item[1]),
    )
    for _, _, split in fractions[:remainder]:
        bases[split] += 1
    return bases


def _seeded_component_assignments(
    components: list[dict[str, Any]],
    *,
    algorithm_id: str,
    seed: int,
    bucket_target_component_counts: dict[str, dict[str, int]],
) -> dict[str, str]:
    """Derive component splits from the declared seeded assignment contract."""

    assigned: dict[str, str] = {}
    for bucket in BUCKETS:
        bucket_components = [component for component in components if component["bucket"] == bucket]
        bucket_components.sort(
            key=lambda component: (
                hashlib.sha256(
                    f"{algorithm_id}|{seed}|{bucket}|{component['component_id']}".encode("utf-8")
                ).hexdigest(),
                component["component_id"],
            )
        )
        offset = 0
        for split in SPLITS:
            target_count = bucket_target_component_counts[bucket][split]
            for component in bucket_components[offset : offset + target_count]:
                assigned[component["component_id"]] = split
            offset += target_count
    return assigned


def split_records(
    records: list[SplitRecord],
    cluster_output: dict[str, Any],
    *,
    seed: int = 0,
    train_ratio: float = 0.8,
    calibration_ratio: float = 0.1,
    locked_test_ratio: float = 0.1,
) -> dict[str, Any]:
    """Assign indivisible protected-family components deterministically."""

    seed = _ensure_exact_int(seed, "seed")
    ratio_values = {
        "train": _ensure_finite_number(train_ratio, "train_ratio"),
        "calibration": _ensure_finite_number(calibration_ratio, "calibration_ratio"),
        "locked_test": _ensure_finite_number(locked_test_ratio, "locked_test_ratio"),
    }
    if any(value < 0.0 or value > 1.0 for value in ratio_values.values()):
        raise AuditInputError("invalid_split_ratio")
    if not math.isclose(sum(ratio_values.values()), 1.0, rel_tol=0.0, abs_tol=1e-9):
        raise AuditInputError("split_ratios_must_sum_to_one")
    if not isinstance(records, list) or not records:
        raise AuditInputError("empty_split_manifest")
    if any(type(record) is not SplitRecord for record in records):
        raise AuditInputError("invalid_split_record_type")
    for record in records:
        _validate_split_admission(record)
    records = sorted(records, key=lambda record: record.record_id)
    if len({record.record_id for record in records}) != len(records):
        raise AuditInputError("duplicate_record_id")
    asset_to_cluster, sequence_index = _cluster_receipt_index(cluster_output)
    record_families: list[dict[str, tuple[str, ...]]] = []
    record_clusters: list[tuple[str, ...]] = []
    for record in records:
        family_map = record.family_map()
        for category in ("source_shoot", "scene", "person", "location", "time"):
            if not family_map.get(category):
                raise AuditInputError(f"missing_protected_id: {category}")
        asset_clusters: set[str] = set()
        for asset_id in record.asset_ids:
            cluster_id = asset_to_cluster.get(asset_id)
            if cluster_id is None:
                raise AuditInputError(f"asset_missing_from_cluster_receipt: {asset_id}")
            asset_clusters.add(cluster_id)
        sequence_ids = family_map.get("sequence", ())
        resolved_families = dict(family_map)
        for sequence_id in sequence_ids:
            sequence = sequence_index.get(sequence_id)
            if sequence is None:
                raise AuditInputError(f"sequence_missing_from_cluster_receipt: {sequence_id}")
            sequence_cluster, sequence_family = sequence
            if sequence_cluster not in asset_clusters:
                raise AuditInputError(f"sequence_asset_cluster_conflict: {sequence_id}")
            declared_derivation = resolved_families.get("derivation", ())
            if declared_derivation and declared_derivation != (sequence_family,):
                raise AuditInputError(f"sequence_derivation_family_conflict: {sequence_id}")
            resolved_families["derivation"] = (sequence_family,)
        if not resolved_families.get("derivation"):
            raise AuditInputError("missing_protected_id: derivation_family_id")
        record_families.append(resolved_families)
        record_clusters.append(tuple(sorted(asset_clusters)))

    union_find = _UnionFind(len(records))
    family_owner: dict[tuple[str, str], int] = {}
    for index, (families, cluster_ids) in enumerate(zip(record_families, record_clusters)):
        keys = [
            (category, value)
            for category, values in families.items()
            for value in values
            if category in PROTECTED_CATEGORIES
        ]
        keys.extend(("dedup_cluster", cluster_id) for cluster_id in cluster_ids)
        for key in keys:
            previous = family_owner.get(key)
            if previous is not None:
                union_find.union(index, previous)
            else:
                family_owner[key] = index

    grouped: dict[int, list[int]] = {}
    for index in range(len(records)):
        grouped.setdefault(union_find.find(index), []).append(index)
    components: list[dict[str, Any]] = []
    for indexes in grouped.values():
        indexes.sort()
        buckets = {records[index].bucket for index in indexes}
        if len(buckets) != 1:
            raise AuditInputError("bucket_component_conflict")
        bucket = next(iter(buckets))
        component_families: dict[str, set[str]] = {category: set() for category in PROTECTED_CATEGORIES}
        cluster_ids: set[str] = set()
        sequence_ids: set[str] = set()
        for index in indexes:
            for category, values in record_families[index].items():
                component_families.setdefault(category, set()).update(values)
            cluster_ids.update(record_clusters[index])
            sequence_ids.update(record_families[index].get("sequence", ()))
        component_families["dedup_cluster"].update(cluster_ids)
        record_ids = tuple(sorted(records[index].record_id for index in indexes))
        family_hashes = [
            {"category": category, "hash": _split_family_hash(category, value)}
            for category in PROTECTED_CATEGORIES
            for value in sorted(component_families.get(category, set()))
        ]
        family_hashes.sort(
            key=lambda family: (PROTECTED_CATEGORIES.index(family["category"]), family["hash"])
        )
        components.append(
            {
                "component_id": _split_component_id(record_ids),
                "bucket": bucket,
                "record_ids": list(record_ids),
                "record_count": len(record_ids),
                "protected_family_hashes": family_hashes,
                "family_count": len(family_hashes),
                "dedup_cluster_count": len(cluster_ids),
                "sequence_count": len(sequence_ids),
                "_indexes": indexes,
            }
        )
    components.sort(key=lambda component: component["component_id"])
    ratios = {split: float(ratio_values[split]) for split in SPLITS}
    targets = {bucket: _split_targets(sum(component["bucket"] == bucket for component in components), ratios) for bucket in BUCKETS}
    assigned = _seeded_component_assignments(
        components,
        algorithm_id=SPLIT_ALGORITHM_ID,
        seed=seed,
        bucket_target_component_counts=targets,
    )

    for component in components:
        split = assigned[component["component_id"]]
        component["split"] = split
        component.pop("_indexes")
    assignment_rows: list[dict[str, str]] = []
    for component in components:
        for record_id in component["record_ids"]:
            assignment_rows.append(
                {
                    "record_id": record_id,
                    "component_id": component["component_id"],
                    "split": component["split"],
                    "bucket": component["bucket"],
                }
            )
    assignment_rows.sort(key=lambda row: row["record_id"])

    split_family_owners: dict[tuple[str, str], set[str]] = {}
    for index, families in enumerate(record_families):
        component_id = next(
            component["component_id"]
            for component in components
            if records[index].record_id in component["record_ids"]
        )
        split = assigned[component_id]
        for category, values in families.items():
            for value in values:
                split_family_owners.setdefault((category, value), set()).add(split)
        for cluster_id in record_clusters[index]:
            split_family_owners.setdefault(("dedup_cluster", cluster_id), set()).add(split)
    cross_split_leak_count = sum(len(splits) > 1 for splits in split_family_owners.values())
    if cross_split_leak_count:
        raise AuditInputError("cross_split_leak_detected")

    per_split: dict[str, dict[str, Any]] = {}
    for split in SPLITS:
        split_components = [component for component in components if component["split"] == split]
        per_split[split] = {
            "component_count": len(split_components),
            "record_count": sum(component["record_count"] for component in split_components),
            "buckets": {
                bucket: {
                    "component_count": sum(component["bucket"] == bucket for component in split_components),
                    "record_count": sum(component["record_count"] for component in split_components if component["bucket"] == bucket),
                }
                for bucket in BUCKETS
            },
        }
    family_counts = {
        category: len({value for families in record_families for value in families.get(category, ())})
        for category in PROTECTED_CATEGORIES
    }
    family_counts["dedup_cluster"] = len({cluster_id for cluster_ids in record_clusters for cluster_id in cluster_ids})
    config = {
        "seed": seed,
        "ratios": ratios,
        "bucket_target_component_counts": targets,
    }
    config_sha256 = _json_digest(config)
    canonical_records = _canonical_split_records(records)
    records_manifest_sha256 = _json_digest(canonical_records)
    clusters_receipt_sha256 = _json_digest(cluster_output)
    input_sha256 = _json_digest(
        {
            "records_manifest_sha256": records_manifest_sha256,
            "clusters_receipt_sha256": clusters_receipt_sha256,
        }
    )
    output = {
        "schema_id": SPLIT_SCHEMA_ID,
        "schema_version": SCHEMA_VERSION,
        "algorithm": {
            "algorithm_id": SPLIT_ALGORITHM_ID,
            "assignment": "seeded_largest_remainder_v1",
            "splits": list(SPLITS),
            "buckets": list(BUCKETS),
            "protected_categories": list(PROTECTED_CATEGORIES),
            "locked_test_disclosure": "opaque_record_ids_and_family_hashes_only",
        },
        "config": {**config, "config_sha256": config_sha256},
        "input": {
            "records_manifest_schema_id": SPLIT_INPUT_SCHEMA_ID,
            "record_count": len(records),
            "cluster_count": len(cluster_output["clusters"]),
            "records_manifest_sha256": records_manifest_sha256,
            "clusters_receipt_sha256": clusters_receipt_sha256,
            "input_sha256": input_sha256,
        },
        "components": components,
        "assignments": assignment_rows,
        "counts": {
            "component_count": len(components),
            "record_count": len(records),
            "family_counts": family_counts,
            "dedup_cluster_count": len({cluster_id for cluster_ids in record_clusters for cluster_id in cluster_ids}),
            "sequence_count": len({sequence_id for families in record_families for sequence_id in families.get("sequence", ())}),
            "per_split": per_split,
        },
        "cross_split_leak_count": cross_split_leak_count,
        "audit": {
            "status": "pass",
            "input_order_independent": True,
            "changed_seed_integrity": True,
            "locked_test_labels_exposed": False,
            "locked_test_content_exposed": False,
            "candidate_identity_leakage": False,
            "raw_media_copied_to_git": False,
        },
    }
    output["manifest_sha256"] = _json_digest(output)
    validate_split_output(output)
    return output


build_split_manifest = split_records


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


def _ensure_exact_bool(value: Any, field_name: str) -> bool:
    if type(value) is not bool:
        raise AuditInputError(f"invalid_boolean: {field_name}")
    return value


def _ensure_exact_int(value: Any, field_name: str) -> int:
    if type(value) is not int:
        raise AuditInputError(f"invalid_integer: {field_name}")
    return value


def _ensure_finite_number(value: Any, field_name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise AuditInputError(f"invalid_number: {field_name}")
    try:
        result = float(value)
    except (OverflowError, ValueError) as exc:
        raise AuditInputError(f"non_finite_number: {field_name}") from exc
    if not math.isfinite(result):
        raise AuditInputError(f"non_finite_number: {field_name}")
    return result


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

    ssim_review = _ensure_exact_bool(ssim_review, "ssim_review")
    phash_distance = _ensure_exact_int(phash_distance, "phash_distance")
    descriptor_similarity = _ensure_finite_number(descriptor_similarity, "descriptor_similarity")
    ssim_threshold = _ensure_finite_number(ssim_threshold, "ssim_threshold")
    if not items:
        raise AuditInputError("empty_media_manifest")
    if phash_distance < 0 or phash_distance > 64:
        raise AuditInputError("invalid_phash_distance")
    if not 0.0 <= descriptor_similarity <= 1.0:
        raise AuditInputError("invalid_descriptor_similarity")
    if not -1.0 <= ssim_threshold <= 1.0:
        raise AuditInputError("invalid_ssim_threshold")
    items = _resolve_sequence_families(sorted(items, key=lambda item: item.asset_id))
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
        if len(family_ids) != 1:
            raise AuditInputError(f"sequence_derivation_family_conflict: {sequence_id}")
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


def _validate_json_schema(output: dict[str, Any], schema_path: Path, label: str) -> None:
    """Validate one closed receipt through its repository-owned JSON Schema."""

    def reject_nonfinite(value: Any) -> None:
        if isinstance(value, float) and not math.isfinite(value):
            raise AuditInputError(f"{label}_schema_invalid: non_finite_number")
        if isinstance(value, dict):
            for child in value.values():
                reject_nonfinite(child)
        elif isinstance(value, list):
            for child in value:
                reject_nonfinite(child)

    if not isinstance(output, dict):
        raise AuditInputError(f"{label}_schema_invalid: receipt must be an object")
    reject_nonfinite(output)
    try:
        from jsonschema import Draft202012Validator
    except ImportError as exc:
        raise AuditInputError(f"{label}_schema_validator_unavailable") from exc
    try:
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
        Draft202012Validator.check_schema(schema)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        raise AuditInputError(f"invalid_{label}_schema_definition") from exc
    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(output), key=lambda error: tuple(str(part) for part in error.absolute_path))
    if errors:
        error = errors[0]
        path = ".".join(str(part) for part in error.absolute_path) or "receipt"
        raise AuditInputError(f"{label}_schema_invalid: {path}: {error.message}")


def _validate_split_semantics(output: dict[str, Any]) -> None:
    """Recompute receipt identities and cross-check all redundant counts."""

    manifest_body = {key: value for key, value in output.items() if key != "manifest_sha256"}
    if _json_digest(manifest_body) != output["manifest_sha256"]:
        raise AuditInputError("split_receipt_drift: manifest_sha256")

    config = output["config"]
    config_body = {key: value for key, value in config.items() if key != "config_sha256"}
    if _json_digest(config_body) != config["config_sha256"]:
        raise AuditInputError("split_receipt_drift: config_sha256")
    ratios = {
        split: _ensure_finite_number(config["ratios"][split], f"config.ratios.{split}")
        for split in SPLITS
    }
    if not math.isclose(sum(ratios.values()), 1.0, rel_tol=0.0, abs_tol=1e-9):
        raise AuditInputError("split_receipt_drift: ratios")

    input_data = output["input"]
    input_body = {
        "records_manifest_sha256": input_data["records_manifest_sha256"],
        "clusters_receipt_sha256": input_data["clusters_receipt_sha256"],
    }
    if _json_digest(input_body) != input_data["input_sha256"]:
        raise AuditInputError("split_receipt_drift: input_sha256")

    components = output["components"]
    if [component["component_id"] for component in components] != sorted(component["component_id"] for component in components):
        raise AuditInputError("split_receipt_drift: component_order")
    component_by_id: dict[str, dict[str, Any]] = {}
    record_owner: dict[str, str] = {}
    family_owner: dict[tuple[str, str], set[tuple[str, str, str]]] = {}
    for component in components:
        component_id = component["component_id"]
        if component_id in component_by_id:
            raise AuditInputError(f"split_receipt_drift: duplicate_component_id:{component_id}")
        record_ids = component["record_ids"]
        if record_ids != sorted(record_ids):
            raise AuditInputError(f"split_receipt_drift: component_record_order:{component_id}")
        if len(record_ids) != component["record_count"] or len(set(record_ids)) != len(record_ids):
            raise AuditInputError(f"split_receipt_drift: component_record_count:{component_id}")
        if _split_component_id(record_ids) != component_id:
            raise AuditInputError(f"split_receipt_drift: component_id:{component_id}")
        family_pairs = {
            (family["category"], family["hash"])
            for family in component["protected_family_hashes"]
        }
        family_order = [
            (family["category"], family["hash"])
            for family in component["protected_family_hashes"]
        ]
        expected_family_order = sorted(
            family_pairs,
            key=lambda item: (PROTECTED_CATEGORIES.index(item[0]), item[1]),
        )
        if family_order != expected_family_order:
            raise AuditInputError(f"split_receipt_drift: family_order:{component_id}")
        if len(family_pairs) != len(component["protected_family_hashes"]):
            raise AuditInputError(f"split_receipt_drift: duplicate_family_hash:{component_id}")
        if not {category for category, _ in family_pairs}.issuperset(
            {"source_shoot", "scene", "person", "location", "time", "derivation"}
        ):
            raise AuditInputError(f"split_receipt_drift: missing_protected_family:{component_id}")
        if component["family_count"] != len(family_pairs):
            raise AuditInputError(f"split_receipt_drift: family_count:{component_id}")
        if component["dedup_cluster_count"] != sum(category == "dedup_cluster" for category, _ in family_pairs):
            raise AuditInputError(f"split_receipt_drift: dedup_cluster_count:{component_id}")
        if component["sequence_count"] != sum(category == "sequence" for category, _ in family_pairs):
            raise AuditInputError(f"split_receipt_drift: sequence_count:{component_id}")
        component_by_id[component_id] = component
        for record_id in record_ids:
            if record_id in record_owner:
                raise AuditInputError(f"split_receipt_drift: duplicate_record_id:{record_id}")
            record_owner[record_id] = component_id
        for family_pair in family_pairs:
            family_owner.setdefault(family_pair, set()).add(
                (component_id, component["bucket"], component["split"])
            )

    for (category, family_hash), owners in family_owner.items():
        component_bucket_owners = {(component_id, bucket) for component_id, bucket, _ in owners}
        if len(component_bucket_owners) != 1:
            raise AuditInputError(
                f"split_receipt_drift: family_owner:{category}:{family_hash}"
            )

    assignments = output["assignments"]
    assignment_by_record: dict[str, dict[str, Any]] = {}
    for assignment in assignments:
        record_id = assignment["record_id"]
        if record_id in assignment_by_record:
            raise AuditInputError(f"split_receipt_drift: duplicate_assignment_id:{record_id}")
        component = component_by_id.get(assignment["component_id"])
        if component is None:
            raise AuditInputError(f"split_receipt_drift: assignment_component:{record_id}")
        if record_id not in component["record_ids"]:
            raise AuditInputError(f"split_receipt_drift: assignment_membership:{record_id}")
        if assignment["split"] != component["split"] or assignment["bucket"] != component["bucket"]:
            raise AuditInputError(f"split_receipt_drift: assignment_component_metadata:{record_id}")
        assignment_by_record[record_id] = assignment
    if [assignment["record_id"] for assignment in assignments] != sorted(assignment["record_id"] for assignment in assignments):
        raise AuditInputError("split_receipt_drift: assignment_order")
    if set(assignment_by_record) != set(record_owner):
        raise AuditInputError("split_receipt_drift: assignment_record_set")
    if input_data["record_count"] != len(record_owner):
        raise AuditInputError("split_receipt_drift: input_record_count")

    counts = output["counts"]
    if counts["component_count"] != len(components) or counts["record_count"] != len(assignments):
        raise AuditInputError("split_receipt_drift: aggregate_count")
    expected_family_counts = {
        category: len({family_hash for (family_category, family_hash) in family_owner if family_category == category})
        for category in PROTECTED_CATEGORIES
    }
    if counts["family_counts"] != expected_family_counts:
        raise AuditInputError("split_receipt_drift: family_counts")
    expected_dedup_count = sum(component["dedup_cluster_count"] for component in components)
    expected_sequence_count = sum(component["sequence_count"] for component in components)
    if counts["dedup_cluster_count"] != expected_dedup_count or counts["sequence_count"] != expected_sequence_count:
        raise AuditInputError("split_receipt_drift: family_aggregate_counts")
    if config["bucket_target_component_counts"] != {
        bucket: _split_targets(sum(component["bucket"] == bucket for component in components), ratios)
        for bucket in BUCKETS
    }:
        raise AuditInputError("split_receipt_drift: bucket_targets")

    expected_assignments = _seeded_component_assignments(
        components,
        algorithm_id=output["algorithm"]["algorithm_id"],
        seed=config["seed"],
        bucket_target_component_counts=config["bucket_target_component_counts"],
    )
    for component in components:
        if expected_assignments.get(component["component_id"]) != component["split"]:
            raise AuditInputError(f"split_receipt_drift: seeded_assignment:{component['component_id']}")

    for split in SPLITS:
        split_components = [component for component in components if component["split"] == split]
        split_assignments = [assignment for assignment in assignments if assignment["split"] == split]
        expected = {
            "component_count": len(split_components),
            "record_count": len(split_assignments),
            "buckets": {
                bucket: {
                    "component_count": sum(component["bucket"] == bucket for component in split_components),
                    "record_count": sum(
                        assignment["bucket"] == bucket for assignment in split_assignments
                    ),
                }
                for bucket in BUCKETS
            },
        }
        if counts["per_split"][split] != expected:
            raise AuditInputError(f"split_receipt_drift: per_split:{split}")

    cross_split_leak_count = sum(
        len({split for _, _, split in owners}) > 1 for owners in family_owner.values()
    )
    if output["cross_split_leak_count"] != cross_split_leak_count or cross_split_leak_count != 0:
        raise AuditInputError("split_receipt_drift: cross_split_leak_count")


def validate_cluster_output(output: dict[str, Any]) -> None:
    _validate_json_schema(output, SCHEMA_PATH, "cluster")


def validate_split_output(output: dict[str, Any]) -> None:
    _validate_json_schema(output, SPLIT_SCHEMA_PATH, "split")
    _validate_split_semantics(output)


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


def _cli_int(value: str) -> int:
    try:
        return int(value)
    except (TypeError, ValueError) as exc:
        raise argparse.ArgumentTypeError("expected an integer") from exc


def _cli_finite_float(value: str) -> float:
    try:
        result = float(value)
    except (TypeError, ValueError) as exc:
        raise argparse.ArgumentTypeError("expected a finite number") from exc
    if not math.isfinite(result):
        raise argparse.ArgumentTypeError("expected a finite number")
    return result


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", "--records", "--input-manifest", "--asset-manifest", required=False, type=Path, help="camera audit input JSON/JSONL")
    parser.add_argument("--media-root", type=Path, help="root containing external media paths")
    parser.add_argument("--media-manifest", "--media-map", type=Path, help="asset_id to external path JSON/JSONL")
    parser.add_argument("--output", "-o", type=Path, help="cluster receipt path; stdout when omitted")
    parser.add_argument("--ssim-review", "--ssim", action="store_true", help="add SSIM review signals without changing admission")
    parser.add_argument("--phash-distance", type=_cli_int, default=DEFAULT_PHASH_DISTANCE)
    parser.add_argument("--descriptor-similarity", type=_cli_finite_float, default=DEFAULT_DESCRIPTOR_SIMILARITY)
    parser.add_argument("--ssim-threshold", type=_cli_finite_float, default=DEFAULT_SSIM_REVIEW_THRESHOLD)
    parser.add_argument("--split", action="store_true", help="assign protected metadata components to M3-008 splits")
    parser.add_argument("--split-manifest", "--split-input", type=Path, help="metadata-only unassigned split input JSON/JSONL")
    parser.add_argument("--cluster-output", "--clusters", "--cluster-receipt", type=Path, help="validated M3-007 cluster receipt for split protection")
    parser.add_argument("--seed", type=_cli_int, default=0)
    parser.add_argument("--train-ratio", type=_cli_finite_float, default=0.8)
    parser.add_argument("--calibration-ratio", type=_cli_finite_float, default=0.1)
    parser.add_argument("--locked-test-ratio", type=_cli_finite_float, default=0.1)
    parser.add_argument("--self-test", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.self_test:
            _self_test()
            return 0
        if args.split or args.split_manifest is not None or args.cluster_output is not None:
            split_path = args.split_manifest or args.manifest
            if split_path is None:
                raise AuditInputError("--split-manifest or --manifest is required for --split")
            if args.cluster_output is None:
                raise AuditInputError("--cluster-output is required for --split")
            if args.media_manifest is not None:
                # Validate an explicitly supplied map even though split input is metadata-only.
                _media_map(args.media_manifest, args.media_root)
            cluster_payload = _read_json_or_jsonl(args.cluster_output)
            if not isinstance(cluster_payload, dict):
                raise AuditInputError("invalid_cluster_receipt_shape")
            split_output = split_records(
                load_split_manifest(split_path),
                cluster_payload,
                seed=args.seed,
                train_ratio=args.train_ratio,
                calibration_ratio=args.calibration_ratio,
                locked_test_ratio=args.locked_test_ratio,
            )
            rendered = json.dumps(split_output, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
            if args.output is None:
                sys.stdout.write(rendered)
            else:
                args.output.parent.mkdir(parents=True, exist_ok=True)
                args.output.write_text(rendered, encoding="utf-8")
                print(
                    f"PASS M3-008 camera_dataset_split records={split_output['counts']['record_count']} "
                    f"components={split_output['counts']['component_count']} "
                    f"leaks={split_output['cross_split_leak_count']} seed={args.seed} output={args.output}"
                )
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
        task = "M3-008 camera_dataset_split" if args.split or args.split_manifest is not None or args.cluster_output is not None else "M3-007 camera_dataset_audit"
        print(f"FAIL {task}: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
