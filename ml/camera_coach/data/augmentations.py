"""Closed Camera Coach training augmentations.

The v1 record is an immutable source label.  This module never creates a
canonical derived record and never treats a receipt hash as authentication.
An external M3-008 cluster/split receipt is injected, copied into immutable
canonical bytes, and replayed against every supplied encoded asset before a
training result is accepted.  The only non-identity operation is a horizontal
flip; photometric identity is retained for schedule completeness and crop or
non-identity photometric transforms fail closed pending reannotation.
"""

from __future__ import annotations

import copy
from dataclasses import dataclass
import hashlib
import json
import math
from io import BytesIO
from pathlib import Path
import re
import struct
import tempfile
import warnings
from collections.abc import Mapping, Sequence
from types import MappingProxyType
from typing import Any

from tools import camera_dataset_audit as _m3
from tools.dataset.camera_coach_check import ACTION_IDS, VERIFIER_IDS, validate_record

Image = _m3.Image
_PILLOW_RUNTIME_VERSION = Image.__version__


ROOT = Path(__file__).resolve().parents[3]
CAMERA_DIR = ROOT / "datasets" / "camera-coach" / "v1"
LABEL_SCHEMA_PATH = CAMERA_DIR / "label-schema.json"
CONTRACT_PATH = ROOT / "ml" / "camera_coach" / "contracts" / "set_composition_net_v1.json"
CLUSTER_SCHEMA_PATH = CAMERA_DIR / "cluster-schema.json"
SPLIT_SCHEMA_PATH = CAMERA_DIR / "split-manifest-schema.json"
DERIVATION_MANIFEST_PATH = CAMERA_DIR / "derivation-manifest.jsonl"

RECORD_SCHEMA_VERSION = "v1.0.0"
AUGMENTATION_VERSION = "v4.0.0"
POLICY_SCHEMA_ID = "camera-augmentation-policy-v4"
LINEAGE_SCHEMA_ID = "camera-augmentation-lineage-v4"
SCHEDULE_SCHEMA_ID = "camera-augmentation-schedule-v2"
SCHEDULE_SCHEMA_VERSION = "v2.0.0"
AUTHORITY_SCHEMA_ID = "camera-m3-authority-v1"
ID_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")

# Existing M3/preprocessing code already uses Pillow in this environment.  A
# version mismatch is rejected rather than silently changing decoded pixels.
_PINNED_PILLOW_VERSION_PIN = "12.2.0"
_PINNED_DECODER_NAME = "Pillow"
_PINNED_MAX_ENCODED_BYTES = 8 * 1024 * 1024
_PINNED_MAX_WIDTH = 4096
_PINNED_MAX_HEIGHT = 4096
_PINNED_MAX_PIXELS = 16_777_216
PILLOW_VERSION_PIN = _PINNED_PILLOW_VERSION_PIN
DECODER_NAME = _PINNED_DECODER_NAME
MAX_ENCODED_BYTES = _PINNED_MAX_ENCODED_BYTES
MAX_WIDTH = _PINNED_MAX_WIDTH
MAX_HEIGHT = _PINNED_MAX_HEIGHT
MAX_PIXELS = _PINNED_MAX_PIXELS

# This is intentionally duplicated from the frozen catalog as an explicit,
# reviewable remap table.  All directional IDs in the frozen catalogs must be
# present here; no substring-based guessing is permitted.
_PINNED_ACTION_PAIRS = (
    ("shift_frame_left", "shift_frame_right"),
    ("move_subject_left", "move_subject_right"),
    ("move_object_left", "move_object_right"),
)
_PINNED_VERIFIER_PAIRS = (
    ("framing_left_improves", "framing_right_improves"),
    ("subject_position_improves_left", "subject_position_improves_right"),
    ("object_position_improves_left", "object_position_improves_right"),
)
_PINNED_REMAP_LOCATIONS = (
    "label.acceptable_action_ids",
    "label.forbidden_action_ids",
    "label.selected_action_id",
    "label.issues[*].acceptable_action_ids",
    "label.issues[*].forbidden_action_ids",
    "label.verification[*].action_id",
    "label.verification[*].verifier_id",
    "episode.action_step.action_id",
    "episode.outcome_verifier",
    "subject.candidates[*].region",
)
_PINNED_PROTECTED_CATEGORIES = tuple(_m3.PROTECTED_CATEGORIES)
ACTION_PAIRS = _PINNED_ACTION_PAIRS
VERIFIER_PAIRS = _PINNED_VERIFIER_PAIRS
REMAP_LOCATIONS = _PINNED_REMAP_LOCATIONS
PROTECTED_CATEGORIES = _PINNED_PROTECTED_CATEGORIES

_ACTION_PAIR_IDS = frozenset(item for pair in _PINNED_ACTION_PAIRS for item in pair)
_VERIFIER_PAIR_IDS = frozenset(item for pair in _PINNED_VERIFIER_PAIRS for item in pair)
if any(item not in ACTION_IDS for item in _ACTION_PAIR_IDS):
    raise RuntimeError("augmentation remap table references an unknown frozen action")
if any(item not in VERIFIER_IDS for item in _VERIFIER_PAIR_IDS):
    raise RuntimeError("augmentation remap table references an unknown frozen verifier")
if any(("left" in item or "right" in item) and item not in _ACTION_PAIR_IDS for item in ACTION_IDS):
    raise RuntimeError("frozen directional action is not explicitly remapped")
if any(("left" in item or "right" in item) and item not in _VERIFIER_PAIR_IDS for item in VERIFIER_IDS):
    raise RuntimeError("frozen directional verifier is not explicitly remapped")

# The internal tuple is the authority.  The same-named alias is retained only
# so old evidence readers can see the fixture boundary; behavior never reads a
# mutable exported dictionary or caller-owned object.
_PINNED_FIXTURE_ASSET_SHA256 = (
    ("asset-still-fixture-001", "96b3febf39c4e35f2f3ff5d008a46f9e8774c48331d7925b096f120fedf4556a"),
    ("asset-seq-fixture-002-f0", "d8bf62ec82ab5ee160458eb2f5a6e7a6507c6ec97579bcba62c929685c66583a"),
    ("asset-seq-fixture-002-f1", "4f174d180b6a628b308d9ddc8607863ee5c676ec9ef22cf72745de1034580696"),
    ("asset-seq-fixture-002-f2", "fc50e46d7e27328f9b4d20eb1545e67ebe972c2df03c9566d5631e4f1e3b8298"),
    ("asset-episode-fixture-003-before", "76dd8e1f052e8d556a38616ea90ba8636133c8e1b6f45ea9f51191d69c4cc6d3"),
    ("asset-episode-fixture-003-after", "49506a05e22e2cb69928636c629f5e09ba00f234a17b1f586c03227ab3c01543"),
)
_FIXTURE_ASSET_SHA256 = _PINNED_FIXTURE_ASSET_SHA256

# Fixed schedule authority.  There is no public constructor that accepts
# caller-provided jobs, ratios, seeds, counters, or source subsets.
_PINNED_SCHEDULE_SEED = 17
_PINNED_SCHEDULE_TRANSFORMS = (("horizontal_flip", ()), ("photometric_identity", ()))


class AugmentationError(ValueError):
    """Raised when an untrusted source, authority, spec, or result is rejected."""


def _jsonable(value: Any) -> Any:
    if isinstance(value, Mapping):
        return {key: _jsonable(item) for key, item in value.items()}
    if isinstance(value, tuple):
        return [_jsonable(item) for item in value]
    if isinstance(value, list):
        return [_jsonable(item) for item in value]
    return value


def canonical_json(value: Any) -> str:
    try:
        return json.dumps(_jsonable(value), ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)
    except (TypeError, ValueError, OverflowError, RecursionError) as exc:
        raise AugmentationError("value is not canonical JSON") from exc


def digest(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def _file_digest(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError as exc:
        raise AugmentationError(f"authority file is unreadable: {path}") from exc


def _remap_authority() -> dict[str, Any]:
    return {
        "action_pairs": [list(pair) for pair in _PINNED_ACTION_PAIRS],
        "verifier_pairs": [list(pair) for pair in _PINNED_VERIFIER_PAIRS],
        "locations": list(_PINNED_REMAP_LOCATIONS),
        "unsupported_v1_fields": [
            "contract.scalar_features",
            "contract.scalar_features.missing_mask",
            "contract.outputs.action_utility_logits",
            "contract.outputs.issue_logits",
            "contract.outputs.roi_mask",
            "contract.outputs.continuous_target_deltas",
        ],
    }


def _schedule_authority() -> dict[str, Any]:
    return {
        "schema_id": SCHEDULE_SCHEMA_ID,
        "schema_version": SCHEDULE_SCHEMA_VERSION,
        "seed": _PINNED_SCHEDULE_SEED,
        "transforms": [{"kind": kind, "parameters": {}} for kind, _ in _PINNED_SCHEDULE_TRANSFORMS],
        "blocked": {"photometric": "requires_reannotation", "crop": "requires_reannotation"},
        "job_fields": ["job_id", "record_id", "kind", "parameters", "seed", "sample_counter"],
    }


REMAP_AUTHORITY_SHA256 = digest(_remap_authority())
SCHEDULE_AUTHORITY_SHA256 = digest(_schedule_authority())


def _fixture_map() -> dict[str, str]:
    return {key: value for key, value in _PINNED_FIXTURE_ASSET_SHA256}


def _config() -> dict[str, Any]:
    if _PILLOW_RUNTIME_VERSION != _PINNED_PILLOW_VERSION_PIN:
        decoder_status = f"runtime-mismatch:{_PILLOW_RUNTIME_VERSION}"
    else:
        decoder_status = _PINNED_PILLOW_VERSION_PIN
    return {
        "augmentation_version": AUGMENTATION_VERSION,
        "policy_schema_id": POLICY_SCHEMA_ID,
        "lineage_schema_id": LINEAGE_SCHEMA_ID,
        "authority_schema_id": AUTHORITY_SCHEMA_ID,
        "schedule_schema_id": SCHEDULE_SCHEMA_ID,
        "schedule_schema_version": SCHEDULE_SCHEMA_VERSION,
        "label_schema_sha256": _file_digest(LABEL_SCHEMA_PATH),
        "contract_sha256": _file_digest(CONTRACT_PATH),
        "cluster_schema_sha256": _file_digest(CLUSTER_SCHEMA_PATH),
        "split_schema_sha256": _file_digest(SPLIT_SCHEMA_PATH),
        "remap_authority_sha256": REMAP_AUTHORITY_SHA256,
        "schedule_authority_sha256": SCHEDULE_AUTHORITY_SHA256,
        "fixture_asset_sha256": _fixture_map(),
        "decoder": {
            "name": _PINNED_DECODER_NAME,
            "version_pin": _PINNED_PILLOW_VERSION_PIN,
            "runtime_version": decoder_status,
            "encoded_byte_cap": _PINNED_MAX_ENCODED_BYTES,
            "width_cap": _PINNED_MAX_WIDTH,
            "height_cap": _PINNED_MAX_HEIGHT,
            "pixel_cap": _PINNED_MAX_PIXELS,
            "normalization": "RGB8-HWC-model-pixels",
            "orientation": "reject-EXIF-orientation-unless-1; preprocessing applies ImageIO orientation exactly once",
            "multi_frame": "reject",
        },
        "source_authority": "external-m3-008-cluster-and-split-receipts-replayed-over-all-assets",
        "eligible_split_owners": ["train", "calibration"],
        "protected_categories": list(_PINNED_PROTECTED_CATEGORIES),
    }


def _freeze(value: Any) -> Any:
    if isinstance(value, dict):
        return MappingProxyType({key: _freeze(item) for key, item in value.items()})
    if isinstance(value, list):
        return tuple(_freeze(item) for item in value)
    return value


# Replaced with the independently computed digest after this file is written.
_PINNED_CONFIG_SHA256 = "c54a4c4ace2165a84a17ea4b8670fba8a3159a772ab371751c4a3206b89d4746"
AUGMENTATION_CONFIG = _freeze(_config())
AUGMENTATION_CONFIG_SHA256 = _PINNED_CONFIG_SHA256


def _current_config_sha256() -> str:
    actual = digest(_config())
    if actual != _PINNED_CONFIG_SHA256:
        raise AugmentationError("frozen augmentation authority changed")
    return actual


def _id(value: Any, label: str) -> str:
    if type(value) is not str or ID_RE.fullmatch(value) is None:
        raise AugmentationError(f"invalid {label}")
    return value


def _sha(value: Any, label: str) -> str:
    if type(value) is not str or SHA256_RE.fullmatch(value) is None:
        raise AugmentationError(f"invalid {label}")
    return value


def _exact_int(value: Any, label: str) -> int:
    if type(value) is not int:
        raise AugmentationError(f"invalid {label}")
    return value


def _finite(value: Any, label: str) -> float:
    if type(value) not in (int, float) or isinstance(value, bool) or not math.isfinite(float(value)):
        raise AugmentationError(f"invalid {label}")
    return float(value)


def _record(record: Any) -> dict[str, Any]:
    if type(record) is not dict:
        raise AugmentationError("source record must be a plain object")
    errors = validate_record(record, {}, admission=False)
    if errors:
        raise AugmentationError(f"source record is not canonical-valid: {errors[0]}")
    return copy.deepcopy(record)


def _required_asset_ids(record: Mapping[str, Any]) -> tuple[str, ...]:
    media = record["media"]
    ids = tuple(_id(item, "media.asset_ids item") for item in media["asset_ids"])
    if not ids or len(set(ids)) != len(ids):
        raise AugmentationError("source media.asset_ids must be non-empty and unique")
    source_ids = tuple(_id(item, "provenance.source_asset_ids item") for item in record["provenance"]["source_asset_ids"])
    if set(source_ids) != set(ids):
        raise AugmentationError("provenance.source_asset_ids must cover exactly media.asset_ids")
    if record["record_type"] == "still" and (len(ids) != 1 or media["asset_id"] != ids[0]):
        raise AugmentationError("still media.asset_id must identify its sole asset")
    if record["record_type"] == "temporal":
        frames = record.get("sequence", {}).get("frames", [])
        if {frame["asset_id"] for frame in frames} != set(ids):
            raise AugmentationError("temporal frames do not cover media.asset_ids")
    if record["record_type"] == "episode":
        episode = record.get("episode")
        if type(episode) is not dict or {episode["before"]["asset_id"], episode["after"]["asset_id"]} != set(ids):
            raise AugmentationError("episode before/after assets do not cover media.asset_ids")
    return tuple(sorted(ids))


def _decode(encoded: bytes, asset_id: str) -> tuple[int, int, bytes]:
    if type(encoded) is not bytes or not encoded:
        raise AugmentationError(f"asset {asset_id} must contain encoded bytes")
    if len(encoded) > _PINNED_MAX_ENCODED_BYTES:
        raise AugmentationError(f"asset {asset_id} exceeds encoded byte cap")
    if _PILLOW_RUNTIME_VERSION != _PINNED_PILLOW_VERSION_PIN:
        raise AugmentationError("decoder version is not the pinned Pillow version")
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(BytesIO(encoded)) as opened:
                opened.verify()
            with Image.open(BytesIO(encoded)) as opened:
                orientation = opened.getexif().get(274, 1)
                if type(orientation) is not int or orientation != 1:
                    raise AugmentationError(f"asset {asset_id} has non-normalized EXIF orientation")
                if type(getattr(opened, "n_frames", 1)) is not int or opened.n_frames != 1:
                    raise AugmentationError(f"asset {asset_id} must contain exactly one frame")
                width, height = int(opened.width), int(opened.height)
                if not (1 <= width <= _PINNED_MAX_WIDTH and 1 <= height <= _PINNED_MAX_HEIGHT and width * height <= _PINNED_MAX_PIXELS):
                    raise AugmentationError(f"asset {asset_id} exceeds decoded dimension/pixel cap")
                opened.load()
                image = opened.convert("RGB")
                pixels = image.tobytes()
                if len(pixels) != width * height * 3:
                    raise AugmentationError(f"asset {asset_id} has an invalid decoded RGB shape")
                return height, width, pixels
    except AugmentationError:
        raise
    except (Image.DecompressionBombError, OSError, ValueError) as exc:
        raise AugmentationError(f"asset {asset_id} is not a deterministic RGB image") from exc


@dataclass(frozen=True, slots=True)
class _DecodedAsset:
    asset_id: str
    encoded: bytes
    encoded_sha256: str
    height: int
    width: int
    pixels: bytes


def _asset_pixels_digest(assets: Sequence[_DecodedAsset]) -> str:
    body = bytearray(b"camera-pixel-bundle-v1\0")
    for asset in assets:
        asset_id = asset.asset_id.encode("utf-8")
        body.extend(struct.pack(">I", len(asset_id)))
        body.extend(asset_id)
        body.extend(struct.pack(">II", asset.height, asset.width))
        body.extend(asset.pixels)
    return hashlib.sha256(bytes(body)).hexdigest()


def _bytes_to_pixels(height: int, width: int, pixels: bytes) -> list[list[list[int]]]:
    return [
        [list(pixels[(row * width + column) * 3 : (row * width + column + 1) * 3]) for column in range(width)]
        for row in range(height)
    ]


class SourceBundle:
    """Canonical source record plus every identified encoded asset."""

    __slots__ = ("_record_json", "_assets")

    def __setattr__(self, name: str, value: Any) -> None:
        if hasattr(self, name):
            raise AttributeError("SourceBundle is immutable")
        object.__setattr__(self, name, value)

    def __init__(self, record_json: str, assets: tuple[_DecodedAsset, ...], token: object) -> None:
        if token is not _SOURCE_TOKEN:
            raise TypeError("SourceBundle is produced by make_source_bundle")
        self._record_json = record_json
        self._assets = assets

    @property
    def record(self) -> dict[str, Any]:
        return copy.deepcopy(json.loads(self._record_json))

    @property
    def asset_ids(self) -> tuple[str, ...]:
        return tuple(asset.asset_id for asset in self._assets)

    def _decoded(self, asset_id: str) -> _DecodedAsset:
        for asset in self._assets:
            if asset.asset_id == asset_id:
                return asset
        raise AugmentationError(f"source asset is absent: {asset_id}")


_SOURCE_TOKEN = object()
_AUTHORITY_TOKEN = object()


def _record_sequences(record: Mapping[str, Any]) -> tuple[str, ...]:
    if record["record_type"] == "temporal":
        return (_id(record["sequence"]["sequence_id"], "sequence_id"),)
    if record["record_type"] == "episode":
        return (_id(record["episode"]["episode_id"], "episode_id"),)
    return ()


def _asset_metadata(record: Mapping[str, Any], asset_id: str) -> tuple[tuple[str, ...], tuple[int, ...]]:
    if record["record_type"] == "temporal":
        for frame in record["sequence"]["frames"]:
            if frame["asset_id"] == asset_id:
                return (record["sequence"]["sequence_id"],), (frame["ordinal"],)
    if record["record_type"] == "episode":
        before = record["episode"]["before"]["asset_id"]
        return (record["episode"]["episode_id"],), (0 if asset_id == before else 1,)
    return (), ()


def _bundle_list(bundles: Any) -> list[SourceBundle]:
    if type(bundles) is not list or not bundles:
        raise AugmentationError("source bundle collection must be a non-empty list")
    if any(type(bundle) is not SourceBundle for bundle in bundles):
        raise AugmentationError("source bundle collection contains an invalid object")
    ids = [bundle.record["record_id"] for bundle in bundles]
    if len(ids) != len(set(ids)):
        raise AugmentationError("duplicate source record in bundle collection")
    return bundles


def _m3_items(bundles: list[SourceBundle], root: Path) -> list[_m3.MediaItem]:
    merged: dict[str, dict[str, Any]] = {}
    for bundle in bundles:
        record = bundle.record
        for asset_id in bundle.asset_ids:
            asset = bundle._decoded(asset_id)
            row = merged.setdefault(
                asset_id,
                {"encoded": asset.encoded, "record_ids": set(), "sequence_ids": set(), "frame_ordinals": set(), "derivation_family_ids": set()},
            )
            if row["encoded"] != asset.encoded:
                raise AugmentationError(f"asset bytes conflict across records: {asset_id}")
            row["record_ids"].add(record["record_id"])
            sequences, ordinals = _asset_metadata(record, asset_id)
            row["sequence_ids"].update(sequences)
            row["frame_ordinals"].update(ordinals)
            row["derivation_family_ids"].add(record["provenance"]["derivation_family_id"])
    items: list[_m3.MediaItem] = []
    for index, asset_id in enumerate(sorted(merged)):
        row = merged[asset_id]
        encoded = row["encoded"]
        path = root / f"asset-{index}.bin"
        path.write_bytes(encoded)
        items.append(
            _m3.MediaItem(
                asset_id=asset_id,
                path=path,
                record_ids=tuple(sorted(row["record_ids"])),
                sequence_ids=tuple(sorted(row["sequence_ids"])),
                frame_ordinals=tuple(sorted(row["frame_ordinals"])),
                derivation_family_ids=tuple(sorted(row["derivation_family_ids"])),
                declared_sha256=hashlib.sha256(encoded).hexdigest(),
            )
        )
    return items


def _split_projection(record: Mapping[str, Any]) -> dict[str, Any]:
    provenance, capture = record["provenance"], record["capture"]
    projection: dict[str, Any] = {
        "record_id": record["record_id"],
        "record_type": record["record_type"],
        "bucket": "synthetic" if provenance["source_kind"] == "synthetic_fixture" else "organic",
        "rights_disposition": provenance["rights_disposition"],
        "source_shoot_id": provenance["source_shoot_id"],
        "scene_family_id": capture["scene_family_id"],
        "person_family_ids": list(capture["person_family_ids"]),
        "location_family_id": capture["location_family_id"],
        "time_family_id": capture["time_family_id"],
        "take_family_id": capture["take_family_id"],
        "device_family_id": capture["device_family_id"],
        "derivation_family_id": provenance["derivation_family_id"],
        "asset_ids": list(record["media"]["asset_ids"]),
        "review": copy.deepcopy(record["review"]),
    }
    sequence_ids = _record_sequences(record)
    if sequence_ids:
        projection["sequence_id"] = sequence_ids[0]
    if record["record_type"] == "temporal":
        projection["sequence"] = {
            "sequence_id": sequence_ids[0],
            "derivation_family_id": provenance["derivation_family_id"],
            "frames": [
                {
                    "asset_id": frame["asset_id"],
                    "sequence_id": sequence_ids[0],
                    "ordinal": frame["ordinal"],
                    "derivation_family_id": provenance["derivation_family_id"],
                }
                for frame in record["sequence"]["frames"]
            ],
        }
    return projection


def _m3_records_from_records(records: Sequence[Mapping[str, Any]]) -> list[_m3.SplitRecord]:
    payload = {
        "manifest_type": _m3.SPLIT_MANIFEST_TYPE,
        "schema_id": _m3.SPLIT_INPUT_SCHEMA_ID,
        "schema_version": _m3.SCHEMA_VERSION,
        "entries": [_split_projection(record) for record in records],
    }
    with tempfile.TemporaryDirectory(prefix="camera-augmentation-split-input-") as temp:
        path = Path(temp) / "split-input.json"
        path.write_text(canonical_json(payload), encoding="utf-8")
        try:
            return _m3.load_split_manifest(path)
        except Exception as exc:
            raise AugmentationError(f"M3 split input is not admissible: {exc}") from exc


def _cluster_index(receipt: Mapping[str, Any]) -> dict[str, tuple[str, str, tuple[str, ...]]]:
    try:
        _m3.validate_cluster_output(copy.deepcopy(dict(receipt)))
    except Exception as exc:
        raise AugmentationError(f"invalid M3 cluster authority: {exc}") from exc
    result: dict[str, tuple[str, str, tuple[str, ...]]] = {}
    for cluster in receipt["clusters"]:
        for member in cluster["members"]:
            asset_id = _id(member["asset_id"], "cluster asset_id")
            if asset_id in result:
                raise AugmentationError(f"duplicate M3 asset authority: {asset_id}")
            result[asset_id] = (
                _sha(member["content_sha256"], "cluster content_sha256"),
                _id(cluster["cluster_id"], "cluster_id"),
                tuple(sorted(_id(item, "cluster member record_id") for item in member["record_ids"])),
            )
    if not result:
        raise AugmentationError("M3 cluster authority has no assets")
    return result


@dataclass(frozen=True, slots=True)
class _AuthoritySource:
    record_id: str
    record_sha256: str
    asset_ids: tuple[str, ...]
    asset_sha256: tuple[tuple[str, str], ...]
    split_owner: str
    protected_families: tuple[tuple[str, tuple[str, ...]], ...]

    def asset_hash(self, asset_id: str) -> str:
        for key, value in self.asset_sha256:
            if key == asset_id:
                return value
        raise AugmentationError(f"asset is absent from authority source: {asset_id}")


class M3Authority:
    """Immutable external M3 receipt plus its exact canonical source set."""

    __slots__ = (
        "_records_json", "_cluster_json", "_split_json", "_rows", "_record_ids", "_asset_ids",
        "_authority_sha256", "_cluster_sha256", "_split_sha256", "_split_seed", "_split_ratios",
    )

    def __setattr__(self, name: str, value: Any) -> None:
        if hasattr(self, name):
            raise AttributeError("M3Authority is immutable")
        object.__setattr__(self, name, value)

    def __init__(
        self,
        records_json: str,
        cluster_json: str,
        split_json: str,
        rows: tuple[_AuthoritySource, ...],
        cluster_sha256: str,
        split_sha256: str,
        split_seed: int,
        split_ratios: tuple[tuple[str, float], ...],
        token: object,
    ) -> None:
        if token is not _AUTHORITY_TOKEN:
            raise TypeError("M3Authority is produced by load_m3_authority")
        self._records_json = records_json
        self._cluster_json = cluster_json
        self._split_json = split_json
        self._rows = rows
        self._record_ids = tuple(row.record_id for row in rows)
        self._asset_ids = tuple(sorted({asset_id for row in rows for asset_id in row.asset_ids}))
        self._cluster_sha256 = cluster_sha256
        self._split_sha256 = split_sha256
        self._split_seed = split_seed
        self._split_ratios = split_ratios
        self._authority_sha256 = digest(
            {
                "schema_id": AUTHORITY_SCHEMA_ID,
                "records_sha256": digest(json.loads(records_json)),
                "cluster_receipt_sha256": cluster_sha256,
                "split_manifest_sha256": split_sha256,
            }
        )

    @property
    def authority_sha256(self) -> str:
        return self._authority_sha256

    @property
    def cluster_receipt_sha256(self) -> str:
        return self._cluster_sha256

    @property
    def split_manifest_sha256(self) -> str:
        return self._split_sha256

    @property
    def record_ids(self) -> tuple[str, ...]:
        return self._record_ids

    @property
    def asset_ids(self) -> tuple[str, ...]:
        return self._asset_ids

    @property
    def split_seed(self) -> int:
        return self._split_seed

    @property
    def split_ratios(self) -> dict[str, float]:
        return dict(self._split_ratios)

    def records(self) -> list[dict[str, Any]]:
        return copy.deepcopy(json.loads(self._records_json))

    def cluster_receipt(self) -> dict[str, Any]:
        return copy.deepcopy(json.loads(self._cluster_json))

    def split_receipt(self) -> dict[str, Any]:
        return copy.deepcopy(json.loads(self._split_json))

    def record(self, record_id: str) -> dict[str, Any]:
        for row in json.loads(self._records_json):
            if row["record_id"] == record_id:
                return copy.deepcopy(row)
        raise AugmentationError(f"record is absent from M3 authority: {record_id}")

    def source(self, record_id: str) -> _AuthoritySource:
        for row in self._rows:
            if row.record_id == record_id:
                return row
        raise AugmentationError(f"record is absent from M3 authority: {record_id}")

    def asset_sha256(self, asset_id: str) -> str:
        for row in self._rows:
            try:
                return row.asset_hash(asset_id)
            except AugmentationError:
                continue
        raise AugmentationError(f"asset is absent from M3 authority: {asset_id}")

    def cluster_id(self, asset_id: str) -> str:
        for cluster in self.cluster_receipt()["clusters"]:
            if asset_id in cluster["asset_ids"]:
                return cluster["cluster_id"]
        raise AugmentationError(f"asset is absent from M3 cluster authority: {asset_id}")


def _authority_families(record: Mapping[str, Any], cluster: Mapping[str, tuple[str, str, tuple[str, ...]]]) -> tuple[tuple[str, tuple[str, ...]], ...]:
    capture, provenance = record["capture"], record["provenance"]
    assets = _required_asset_ids(record)
    families: dict[str, tuple[str, ...]] = {
        "source_shoot": (provenance["source_shoot_id"],),
        "scene": (capture["scene_family_id"],),
        "person": tuple(sorted(capture["person_family_ids"])),
        "location": (capture["location_family_id"],),
        "time": (capture["time_family_id"],),
        "derivation": (provenance["derivation_family_id"],),
        "sequence": tuple(_record_sequences(record)),
        "take": (capture["take_family_id"],),
        "device": (capture["device_family_id"],),
        "dedup_cluster": tuple(sorted({cluster[asset_id][1] for asset_id in assets})),
    }
    required_categories = ("source_shoot", "scene", "person", "location", "time", "derivation", "take", "device", "dedup_cluster")
    if any(not families.get(category) for category in required_categories):
        raise AugmentationError("source record lacks a protected family value")
    return tuple((category, families[category]) for category in _PINNED_PROTECTED_CATEGORIES)


def load_m3_authority(
    records: list[Mapping[str, Any]],
    cluster_receipt: Mapping[str, Any],
    split_receipt: Mapping[str, Any],
) -> M3Authority:
    """Inject external M3 receipts without requiring pixels or issuing jobs."""

    if type(records) is not list or not records:
        raise AugmentationError("external M3 authority records must be a non-empty list")
    source_records = tuple(sorted((_record(record) for record in records), key=lambda item: item["record_id"]))
    record_ids = tuple(record["record_id"] for record in source_records)
    if len(set(record_ids)) != len(record_ids):
        raise AugmentationError("external M3 authority has duplicate record IDs")
    cluster = copy.deepcopy(dict(cluster_receipt)) if type(cluster_receipt) is dict else None
    split = copy.deepcopy(dict(split_receipt)) if type(split_receipt) is dict else None
    if cluster is None or split is None:
        raise AugmentationError("external M3 authority receipts must be plain objects")
    cluster_index = _cluster_index(cluster)
    expected_assets = tuple(sorted({asset_id for record in source_records for asset_id in _required_asset_ids(record)}))
    if tuple(sorted(cluster_index)) != expected_assets:
        raise AugmentationError("M3 cluster authority does not cover the exact source asset set")
    for asset_id, (_, _, member_records) in cluster_index.items():
        expected_members = tuple(sorted(record["record_id"] for record in source_records if asset_id in _required_asset_ids(record)))
        if member_records != expected_members:
            raise AugmentationError(f"M3 cluster record membership disagrees for {asset_id}")
    try:
        _m3.validate_split_output(copy.deepcopy(split))
    except Exception as exc:
        raise AugmentationError(f"invalid M3 split authority: {exc}") from exc
    if split["input"]["clusters_receipt_sha256"] != digest(cluster):
        raise AugmentationError("M3 split authority is bound to a different cluster receipt")
    if split["input"]["record_count"] != len(source_records):
        raise AugmentationError("M3 split authority record count disagrees with source set")
    if set(row["record_id"] for row in split["assignments"]) != set(record_ids):
        raise AugmentationError("M3 split authority does not cover the exact source record set")
    split_seed = _exact_int(split["config"]["seed"], "M3 split seed")
    ratios = tuple((name, _finite(split["config"]["ratios"][name], f"M3 split ratio {name}")) for name in _m3.SPLITS)
    try:
        recomputed = _m3.split_records(
            _m3_records_from_records(source_records),
            cluster,
            seed=split_seed,
            train_ratio=dict(ratios)["train"],
            calibration_ratio=dict(ratios)["calibration"],
            locked_test_ratio=dict(ratios)["locked_test"],
        )
    except Exception as exc:
        raise AugmentationError(f"M3 split authority cannot replay source set: {exc}") from exc
    if canonical_json(recomputed) != canonical_json(split):
        raise AugmentationError("M3 split authority does not replay from canonical source records")
    assignments = {row["record_id"]: row["split"] for row in split["assignments"]}
    if any(assignments[record_id] not in ("train", "calibration") for record_id in record_ids):
        raise AugmentationError("locked-test authority is outside this training owner")
    rows: list[_AuthoritySource] = []
    for record in source_records:
        record_id = record["record_id"]
        assigned = assignments[record_id]
        declared = record["split"]
        if declared == "fixture":
            if record["provenance"]["source_kind"] != "synthetic_fixture" or record["provenance"]["rights_disposition"] != "fixture_only":
                raise AugmentationError("fixture split requires fixture-only provenance")
        elif declared == "holdout":
            raise AugmentationError("holdout source cannot enter augmentation authority")
        elif declared != assigned:
            raise AugmentationError(f"source split disagrees with M3 authority: {record_id}")
        asset_ids = _required_asset_ids(record)
        rows.append(
            _AuthoritySource(
                record_id=record_id,
                record_sha256=digest(record),
                asset_ids=asset_ids,
                asset_sha256=tuple((asset_id, cluster_index[asset_id][0]) for asset_id in asset_ids),
                split_owner=assigned,
                protected_families=_authority_families(record, cluster_index),
            )
        )
    return M3Authority(
        records_json=canonical_json(list(source_records)),
        cluster_json=canonical_json(cluster),
        split_json=canonical_json(split),
        rows=tuple(rows),
        cluster_sha256=digest(cluster),
        split_sha256=split["manifest_sha256"],
        split_seed=split_seed,
        split_ratios=ratios,
        token=_AUTHORITY_TOKEN,
    )


def make_source_bundle(
    record: Mapping[str, Any],
    assets: Mapping[str, Any],
    *,
    authority: M3Authority | None = None,
) -> SourceBundle:
    """Bind actual encoded bytes to every canonical asset in ``record``."""

    source = _record(record)
    expected_ids = _required_asset_ids(source)
    if type(assets) is not dict:
        raise AugmentationError("source assets must be an asset_id-to-bytes object")
    supplied_ids = tuple(sorted(_id(key, "asset map key") for key in assets))
    if supplied_ids != expected_ids:
        raise AugmentationError("source asset bundle is missing or has extra assets")
    if authority is not None and type(authority) is not M3Authority:
        raise AugmentationError("authority must be an externally loaded M3Authority")
    if authority is not None:
        row = authority.source(source["record_id"])
        if row.record_sha256 != digest(source) or row.asset_ids != expected_ids:
            raise AugmentationError("source record disagrees with external M3 authority")
    decoded: list[_DecodedAsset] = []
    for asset_id in expected_ids:
        value = assets[asset_id]
        height, width, pixels = _decode(value, asset_id)
        actual_sha = hashlib.sha256(value).hexdigest()
        if authority is not None and actual_sha != authority.asset_sha256(asset_id):
            raise AugmentationError(f"asset bytes disagree with external M3 authority: {asset_id}")
        decoded.append(_DecodedAsset(asset_id, value, actual_sha, height, width, pixels))
    if source["record_type"] == "still" and source["media"]["content_sha256"] != decoded[0].encoded_sha256:
        raise AugmentationError("record media.content_sha256 does not match actual asset bytes")
    fixture_only = source["provenance"]["source_kind"] == "synthetic_fixture" and source["provenance"]["rights_disposition"] == "fixture_only"
    if authority is None and source["record_type"] != "still" and not fixture_only:
        raise AugmentationError("requires_external_asset_authority for grouped production media")
    if authority is None and fixture_only:
        expected_fixture = _fixture_map()
        for asset in decoded:
            if expected_fixture.get(asset.asset_id) != asset.encoded_sha256:
                raise AugmentationError(f"fixture bytes disagree with pinned fixture authority: {asset.asset_id}")
    return SourceBundle(canonical_json(source), tuple(decoded), _SOURCE_TOKEN)


@dataclass(frozen=True, slots=True)
class _ScheduleJob:
    job_id: str
    record_id: str
    kind: str
    seed: int
    sample_counter: int

    def as_dict(self) -> dict[str, Any]:
        return {
            "job_id": self.job_id,
            "record_id": self.record_id,
            "kind": self.kind,
            "parameters": {},
            "seed": self.seed,
            "sample_counter": self.sample_counter,
        }


class TrustedSchedule:
    """Immutable fixed schedule derived solely from one M3Authority."""

    __slots__ = ("_body_json", "_jobs", "_sources", "_authority", "_schedule_sha256")

    def __setattr__(self, name: str, value: Any) -> None:
        if hasattr(self, name):
            raise AttributeError("TrustedSchedule is immutable")
        object.__setattr__(self, name, value)

    def __init__(
        self,
        body_json: str,
        jobs: tuple[_ScheduleJob, ...],
        sources: tuple[_AuthoritySource, ...],
        authority: M3Authority,
        schedule_sha256: str,
        token: object,
    ) -> None:
        if token is not _SCHEDULE_TOKEN:
            raise TypeError("TrustedSchedule is produced by make_trusted_schedule")
        self._body_json = body_json
        self._jobs = jobs
        self._sources = sources
        self._authority = authority
        self._schedule_sha256 = schedule_sha256

    @property
    def authority(self) -> M3Authority:
        return self._authority

    @property
    def schedule_sha256(self) -> str:
        return self._schedule_sha256

    @property
    def jobs(self) -> tuple[dict[str, Any], ...]:
        return tuple(job.as_dict() for job in self._jobs)

    def schedule(self) -> dict[str, Any]:
        return copy.deepcopy(json.loads(self._body_json))

    def job(self, job_id: str) -> _ScheduleJob:
        for job in self._jobs:
            if job.job_id == job_id:
                return job
        raise AugmentationError(f"job is absent from trusted schedule: {job_id}")

    def source(self, record_id: str) -> _AuthoritySource:
        for source in self._sources:
            if source.record_id == record_id:
                return source
        raise AugmentationError(f"source is absent from trusted schedule: {record_id}")


_SCHEDULE_TOKEN = object()


def make_trusted_schedule(authority: M3Authority) -> TrustedSchedule:
    """Derive the complete fixed schedule from immutable external authority."""

    if type(authority) is not M3Authority:
        raise AugmentationError("an externally loaded M3Authority is required")
    config_sha = _current_config_sha256()
    jobs: list[_ScheduleJob] = []
    counter = 0
    for source in authority._rows:
        for kind, _ in _PINNED_SCHEDULE_TRANSFORMS:
            jobs.append(_ScheduleJob(f"aug-{counter:06d}", source.record_id, kind, _PINNED_SCHEDULE_SEED, counter))
            counter += 1
    if not jobs:
        raise AugmentationError("cannot construct an empty trusted schedule")
    body = {
        "schema_id": SCHEDULE_SCHEMA_ID,
        "schema_version": SCHEDULE_SCHEMA_VERSION,
        "config_sha256": config_sha,
        "schedule_authority_sha256": SCHEDULE_AUTHORITY_SHA256,
        "source_authority_sha256": authority.authority_sha256,
        "cluster_receipt_sha256": authority.cluster_receipt_sha256,
        "split_manifest_sha256": authority.split_manifest_sha256,
        "seed": _PINNED_SCHEDULE_SEED,
        "transforms": [{"kind": kind, "parameters": {}} for kind, _ in _PINNED_SCHEDULE_TRANSFORMS],
        "sources": [
            {
                "record_id": source.record_id,
                "record_sha256": source.record_sha256,
                "asset_ids": list(source.asset_ids),
                "asset_sha256": {key: value for key, value in source.asset_sha256},
                "split_owner": source.split_owner,
                "protected_families": {key: list(values) for key, values in source.protected_families},
            }
            for source in authority._rows
        ],
        "jobs": [job.as_dict() for job in jobs],
    }
    body_json = canonical_json(body)
    return TrustedSchedule(body_json, tuple(jobs), authority._rows, authority, digest(body), _SCHEDULE_TOKEN)


def _assert_authority(schedule: TrustedSchedule, authority: M3Authority) -> None:
    if type(schedule) is not TrustedSchedule or type(authority) is not M3Authority:
        raise AugmentationError("trusted schedule and M3 authority are required")
    if schedule.authority is not authority:
        raise AugmentationError("validation authority is not the schedule's injected authority")
    body = schedule.schedule()
    if body["config_sha256"] != _current_config_sha256():
        raise AugmentationError("schedule configuration digest is stale")
    if body["schedule_authority_sha256"] != SCHEDULE_AUTHORITY_SHA256:
        raise AugmentationError("schedule authority digest changed")
    if body["source_authority_sha256"] != authority.authority_sha256:
        raise AugmentationError("schedule source authority digest changed")


def _check_bundle(bundle: SourceBundle, schedule: TrustedSchedule, authority: M3Authority, record_id: str) -> dict[str, Any]:
    if type(bundle) is not SourceBundle:
        raise AugmentationError("a canonical source bundle is required")
    record = _record(bundle.record)
    row = schedule.source(record_id)
    if record["record_id"] != record_id or digest(record) != row.record_sha256:
        raise AugmentationError("source record does not match trusted schedule")
    if tuple(sorted(bundle.asset_ids)) != row.asset_ids:
        raise AugmentationError("source bundle asset set does not match trusted schedule")
    for asset_id in row.asset_ids:
        actual = bundle._decoded(asset_id).encoded_sha256
        if actual != row.asset_hash(asset_id) or actual != authority.asset_sha256(asset_id):
            raise AugmentationError(f"source asset bytes do not match trusted authority: {asset_id}")
    return record


def _flip_action(value: Any, label: str) -> Any:
    if value is None:
        return None
    if type(value) is not str:
        raise AugmentationError(f"invalid action ID at {label}")
    for left, right in _PINNED_ACTION_PAIRS:
        if value == left:
            return right
        if value == right:
            return left
    return value


def _flip_verifier(value: Any, label: str) -> Any:
    if type(value) is not str:
        raise AugmentationError(f"invalid verifier ID at {label}")
    for left, right in _PINNED_VERIFIER_PAIRS:
        if value == left:
            return right
        if value == right:
            return left
    return value


def _flip_action_list(values: Any, label: str) -> list[str]:
    if type(values) is not list:
        raise AugmentationError(f"invalid action list at {label}")
    return [_flip_action(value, f"{label}[{index}]") for index, value in enumerate(values)]


def _flip_region(region: Any, label: str) -> list[float | int]:
    if type(region) is not list or len(region) != 4:
        raise AugmentationError(f"invalid region at {label}")
    x, y, width, height = (_finite(value, f"{label}[{index}]") for index, value in enumerate(region))
    if not all(0.0 <= value <= 1.0 for value in (x, y, width, height)) or x + width > 1.0 or y + height > 1.0:
        raise AugmentationError(f"region is outside normalized frame at {label}")
    mirrored_x = 1.0 - x - width
    # IEEE-754 subtraction can lose a low-order bit.  Reject that case rather
    # than round, silently drift, or carry an oracle-only restoration token.
    if 1.0 - mirrored_x - width != x:
        raise AugmentationError("requires_reannotation: region is not an exact flip involution")
    return [mirrored_x, y, width, height]


def _flip_targets(record: Mapping[str, Any], *, flip: bool) -> dict[str, Any]:
    result: dict[str, Any] = {
        "capture": copy.deepcopy(record["capture"]),
        "subject": copy.deepcopy(record["subject"]),
        "label": copy.deepcopy(record["label"]),
    }
    if "sequence" in record:
        result["sequence"] = copy.deepcopy(record["sequence"])
    if "episode" in record:
        result["episode"] = copy.deepcopy(record["episode"])
    if not flip:
        return result
    label = result["label"]
    label["acceptable_action_ids"] = _flip_action_list(label["acceptable_action_ids"], "label.acceptable_action_ids")
    label["forbidden_action_ids"] = _flip_action_list(label["forbidden_action_ids"], "label.forbidden_action_ids")
    label["selected_action_id"] = _flip_action(label["selected_action_id"], "label.selected_action_id")
    for index, issue in enumerate(label["issues"]):
        issue["acceptable_action_ids"] = _flip_action_list(issue["acceptable_action_ids"], f"label.issues[{index}].acceptable_action_ids")
        issue["forbidden_action_ids"] = _flip_action_list(issue["forbidden_action_ids"], f"label.issues[{index}].forbidden_action_ids")
    for index, verification in enumerate(label["verification"]):
        verification["action_id"] = _flip_action(verification["action_id"], f"label.verification[{index}].action_id")
        verification["verifier_id"] = _flip_verifier(verification["verifier_id"], f"label.verification[{index}].verifier_id")
    for index, candidate in enumerate(result["subject"]["candidates"]):
        if "region" in candidate:
            candidate["region"] = _flip_region(candidate["region"], f"subject.candidates[{index}].region")
    if "episode" in result:
        result["episode"]["action_step"]["action_id"] = _flip_action(result["episode"]["action_step"]["action_id"], "episode.action_step.action_id")
        result["episode"]["outcome_verifier"] = _flip_verifier(result["episode"]["outcome_verifier"], "episode.outcome_verifier")
    return result


def _flip_pixels(asset: _DecodedAsset) -> bytes:
    row_size = asset.width * 3
    return b"".join(
        b"".join(asset.pixels[row * row_size + column * 3 : row * row_size + (column + 1) * 3] for column in range(asset.width - 1, -1, -1))
        for row in range(asset.height)
    )


def _validate_transform(kind: Any, parameters: Any) -> str:
    if type(kind) is not str or type(parameters) is not dict:
        raise AugmentationError("transform kind and parameters are closed typed values")
    if kind == "horizontal_flip" and parameters == {}:
        return kind
    if kind == "photometric_identity" and parameters == {}:
        return kind
    if kind in ("photometric", "crop"):
        raise AugmentationError("requires_reannotation")
    raise AugmentationError("unknown transform kind or parameters")


def _result_pixels(bundle: SourceBundle, kind: str) -> dict[str, list[list[list[int]]]]:
    result: dict[str, list[list[list[int]]]] = {}
    for asset_id in bundle.asset_ids:
        asset = bundle._decoded(asset_id)
        pixels = _flip_pixels(asset) if kind == "horizontal_flip" else asset.pixels
        result[asset_id] = _bytes_to_pixels(asset.height, asset.width, pixels)
    return result


def _pixel_map_digest(pixels_by_asset: Mapping[str, Any], expected: Sequence[_DecodedAsset]) -> str:
    if type(pixels_by_asset) is not dict or set(pixels_by_asset) != {asset.asset_id for asset in expected}:
        raise AugmentationError("output pixels must cover exactly every source asset")
    packed: list[_DecodedAsset] = []
    for asset in expected:
        pixels = pixels_by_asset[asset.asset_id]
        if type(pixels) is not list or not pixels or any(type(row) is not list for row in pixels):
            raise AugmentationError("output pixels must be HWC lists")
        if len(pixels) != asset.height or any(len(row) != asset.width for row in pixels):
            raise AugmentationError("output pixel shape changed")
        raw = bytearray()
        for row in pixels:
            for pixel in row:
                if type(pixel) is not list or len(pixel) != 3 or any(type(channel) is not int or not 0 <= channel <= 255 for channel in pixel):
                    raise AugmentationError("output pixels contain an invalid RGB value")
                raw.extend(pixel)
        packed.append(_DecodedAsset(asset.asset_id, b"", "", asset.height, asset.width, bytes(raw)))
    return _asset_pixels_digest(packed)


def _lineage(
    bundle: SourceBundle,
    record: Mapping[str, Any],
    source: _AuthoritySource,
    job: _ScheduleJob,
    schedule: TrustedSchedule,
    targets: Mapping[str, Any],
    pixels: Mapping[str, Any],
) -> dict[str, Any]:
    assets = tuple(bundle._decoded(asset_id) for asset_id in bundle.asset_ids)
    body = {
        "schema_id": LINEAGE_SCHEMA_ID,
        "schema_version": AUGMENTATION_VERSION,
        "job_id": job.job_id,
        "record_id": record["record_id"],
        "source_record_sha256": digest(record),
        "source_asset_content_sha256": {asset.asset_id: asset.encoded_sha256 for asset in assets},
        "input_pixels_sha256": _asset_pixels_digest(assets),
        "output_pixels_sha256": _pixel_map_digest(pixels, assets),
        "source_targets_sha256": digest(_flip_targets(record, flip=False)),
        "output_targets_sha256": digest(targets),
        "transform": {"kind": job.kind, "version": AUGMENTATION_VERSION, "parameters": {}},
        "seed": job.seed,
        "sample_counter": job.sample_counter,
        "config_sha256": _current_config_sha256(),
        "authority_sha256": schedule.authority.authority_sha256,
        "schedule_sha256": schedule.schedule_sha256,
        "cluster_receipt_sha256": schedule.authority.cluster_receipt_sha256,
        "split_manifest_sha256": schedule.authority.split_manifest_sha256,
        "protected_families": {key: list(values) for key, values in source.protected_families},
        "split_owner": source.split_owner,
    }
    return {**body, "receipt_sha256": digest(body)}


def _expected_result(bundle: SourceBundle, schedule: TrustedSchedule, authority: M3Authority, job_id: str) -> dict[str, Any]:
    _assert_authority(schedule, authority)
    job = schedule.job(job_id)
    record = _check_bundle(bundle, schedule, authority, job.record_id)
    kind = _validate_transform(job.kind, {})
    targets = _flip_targets(record, flip=kind == "horizontal_flip")
    pixels = _result_pixels(bundle, kind)
    source = authority.source(record["record_id"])
    return {
        "job_id": job.job_id,
        "record_id": record["record_id"],
        "pixels_by_asset": pixels,
        "targets": targets,
        "lineage": _lineage(bundle, record, source, job, schedule, targets, pixels),
    }


def augment(bundle: SourceBundle, schedule: TrustedSchedule, job_id: str) -> dict[str, Any]:
    if type(schedule) is not TrustedSchedule or type(job_id) is not str:
        raise AugmentationError("augment requires a trusted schedule and job ID")
    return copy.deepcopy(_expected_result(bundle, schedule, schedule.authority, job_id))


_RESULT_KEYS = {"job_id", "record_id", "pixels_by_asset", "targets", "lineage"}


def validate_result(
    bundle: SourceBundle,
    result: Mapping[str, Any],
    *,
    authority: M3Authority,
    schedule: TrustedSchedule,
) -> None:
    """Replay the fixed job over actual source pixels and compare every field."""

    _assert_authority(schedule, authority)
    if type(result) is not dict or set(result) != _RESULT_KEYS:
        raise AugmentationError("result has unknown or missing keys")
    expected = _expected_result(bundle, schedule, authority, result["job_id"])
    if canonical_json(dict(result)) != canonical_json(expected):
        raise AugmentationError("result does not replay from the trusted source bundle and schedule")


def _replay_external_authority(bundles: list[SourceBundle], authority: M3Authority) -> None:
    """Re-run M3 over every actual asset and compare to the injected receipts."""

    with tempfile.TemporaryDirectory(prefix="camera-augmentation-m3-replay-") as temp:
        try:
            cluster = _m3.cluster_media(_m3_items(bundles, Path(temp)))
        except Exception as exc:
            raise AugmentationError(f"M3 cluster replay failed: {exc}") from exc
    if digest(cluster) != authority.cluster_receipt_sha256:
        raise AugmentationError("actual assets do not reproduce trusted M3 cluster receipt")
    try:
        split = _m3.split_records(
            _m3_records_from_records([bundle.record for bundle in bundles]),
            authority.cluster_receipt(),
            seed=authority.split_seed,
            train_ratio=authority.split_ratios["train"],
            calibration_ratio=authority.split_ratios["calibration"],
            locked_test_ratio=authority.split_ratios["locked_test"],
        )
    except Exception as exc:
        raise AugmentationError(f"M3 split replay failed: {exc}") from exc
    if canonical_json(split) != canonical_json(authority.split_receipt()):
        raise AugmentationError("actual source records do not reproduce trusted M3 split receipt")


def validate_lineage_batch(
    bundles: list[SourceBundle],
    results: list[Mapping[str, Any]],
    *,
    authority: M3Authority,
    schedule: TrustedSchedule,
) -> None:
    """Validate a complete fixed batch and cross-check every protected family."""

    _assert_authority(schedule, authority)
    if type(bundles) is not list or type(results) is not list or not bundles or not results:
        raise AugmentationError("lineage batch must be a non-empty complete batch")
    checked = _bundle_list(bundles)
    by_id = {bundle.record["record_id"]: bundle for bundle in checked}
    if set(by_id) != set(authority.record_ids):
        raise AugmentationError("batch source set is incomplete or has extra records")
    result_ids = []
    for result in results:
        if type(result) is not dict or type(result.get("job_id")) is not str:
            raise AugmentationError("batch result has no valid job ID")
        result_ids.append(result["job_id"])
    expected_ids = [job.job_id for job in schedule._jobs]
    if len(result_ids) != len(set(result_ids)) or set(result_ids) != set(expected_ids):
        raise AugmentationError("batch result set is incomplete, duplicated, or has extras")
    _replay_external_authority(checked, authority)
    for result in results:
        job = schedule.job(result["job_id"])
        validate_result(by_id[job.record_id], result, authority=authority, schedule=schedule)
    owners: dict[tuple[str, str], str] = {}
    for source in schedule._sources:
        for category, values in source.protected_families:
            for value in values:
                key = (category, value)
                previous = owners.setdefault(key, source.split_owner)
                if previous != source.split_owner:
                    raise AugmentationError(f"protected family crosses split owners: {category}:{value}")


def _manifest_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise AugmentationError("derivation manifest has duplicate JSON keys")
        result[key] = value
    return result


_MANIFEST_KEYS = frozenset(
    {
        "manifest_type", "schema_id", "manifest_version", "manifest_id", "manifest_sha256", "entry_schema",
        "record_count", "hash_algorithm", "raw_data_location", "rights_uncleared_location", "template_only",
        "independence_rule", "augmentation_policy_schema_id", "augmentation_lineage_schema_id",
        "augmentation_config_sha256", "schedule_schema_id", "schedule_authority_sha256",
    }
)


def validate_derivation_manifest(path: Path | str = DERIVATION_MANIFEST_PATH) -> dict[str, Any]:
    manifest_path = Path(path)
    try:
        lines = manifest_path.read_text(encoding="utf-8").splitlines()
        if len(lines) != 1 or not lines[0]:
            raise AugmentationError("derivation manifest must contain one JSONL header")
        payload = json.loads(lines[0], object_pairs_hook=_manifest_pairs)
    except (OSError, json.JSONDecodeError) as exc:
        raise AugmentationError(f"invalid derivation manifest: {manifest_path}") from exc
    if type(payload) is not dict or set(payload) != _MANIFEST_KEYS:
        raise AugmentationError("derivation manifest has unknown or missing keys")
    if canonical_json(payload) != lines[0]:
        raise AugmentationError("derivation manifest is not canonical JSON")
    if payload["manifest_type"] != "derivation" or payload["schema_id"] != "camera-derivation-manifest-v1":
        raise AugmentationError("derivation manifest schema mismatch")
    if payload["manifest_version"] != RECORD_SCHEMA_VERSION or payload["entry_schema"] != "camera-derivation-entry-v1":
        raise AugmentationError("derivation manifest version mismatch")
    if payload["manifest_id"] != "camera-derivation-manifest" or payload["hash_algorithm"] != "sha256":
        raise AugmentationError("derivation manifest identity mismatch")
    if type(payload["record_count"]) is not int or isinstance(payload["record_count"], bool) or payload["record_count"] != 0:
        raise AugmentationError("derivation manifest must remain zero-record")
    if payload["raw_data_location"] != "outside_git" or payload["rights_uncleared_location"] != "outside_git" or payload["template_only"] is not True:
        raise AugmentationError("derivation manifest storage/template policy mismatch")
    if payload["augmentation_policy_schema_id"] != POLICY_SCHEMA_ID or payload["augmentation_lineage_schema_id"] != LINEAGE_SCHEMA_ID:
        raise AugmentationError("derivation manifest augmentation binding mismatch")
    if payload["schedule_schema_id"] != SCHEDULE_SCHEMA_ID or payload["schedule_authority_sha256"] != SCHEDULE_AUTHORITY_SHA256:
        raise AugmentationError("derivation manifest schedule binding mismatch")
    if payload["augmentation_config_sha256"] != _current_config_sha256():
        raise AugmentationError("derivation manifest configuration binding mismatch")
    if payload["independence_rule"] != "only explicitly independent source decisions count toward a split quota":
        raise AugmentationError("derivation manifest independence rule mismatch")
    expected = digest({key: value for key, value in payload.items() if key != "manifest_sha256"})
    if payload["manifest_sha256"] != expected:
        raise AugmentationError("derivation manifest hash mismatch")
    return copy.deepcopy(payload)


__all__ = [
    "ACTION_PAIRS", "AUGMENTATION_CONFIG", "AUGMENTATION_CONFIG_SHA256", "AugmentationError", "AUTHORITY_SCHEMA_ID",
    "DECODER_NAME", "DERIVATION_MANIFEST_PATH", "LINEAGE_SCHEMA_ID", "M3Authority", "MAX_ENCODED_BYTES",
    "MAX_HEIGHT", "MAX_PIXELS", "MAX_WIDTH", "PILLOW_VERSION_PIN", "POLICY_SCHEMA_ID", "REMAP_AUTHORITY_SHA256",
    "SCHEDULE_AUTHORITY_SHA256", "SCHEDULE_SCHEMA_ID", "SourceBundle", "TrustedSchedule", "VERIFIER_PAIRS",
    "augment", "canonical_json", "digest", "load_m3_authority", "make_source_bundle", "make_trusted_schedule",
    "validate_derivation_manifest", "validate_lineage_batch", "validate_result",
]
