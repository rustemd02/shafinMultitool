"""Closed, replayable Camera Coach training augmentations.

The frozen Camera Coach record is never rewritten.  ``augment`` returns a
training result containing the source ``record_id``, transformed pixels,
explicit target/feature fields, and a lineage receipt.  A result is admitted
only when ``validate_result`` replays the source record, source pixels, and
canonical transform and obtains the same output.
"""

from __future__ import annotations

import copy
from dataclasses import dataclass, field
import hashlib
import json
import math
from pathlib import Path
import re
import struct
from typing import Any, Mapping, Sequence

from tools.dataset.camera_coach_check import validate_record


ROOT = Path(__file__).resolve().parents[3]
CAMERA_DIR = ROOT / "datasets" / "camera-coach" / "v1"
LABEL_SCHEMA_PATH = CAMERA_DIR / "label-schema.json"
CONTRACT_PATH = ROOT / "ml" / "camera_coach" / "contracts" / "set_composition_net_v1.json"
DERIVATION_MANIFEST_PATH = CAMERA_DIR / "derivation-manifest.jsonl"

RECORD_SCHEMA_VERSION = "v1.0.0"
AUGMENTATION_VERSION = "v2.0.0"
POLICY_SCHEMA_ID = "camera-augmentation-policy-v2"
LINEAGE_SCHEMA_ID = "camera-augmentation-lineage-v2"
ID_RE = "^[a-z0-9][a-z0-9._-]*$"
RECORD_ID_RE = "^cam-[a-z0-9][a-z0-9._-]*$"
SHA256_RE = "^[0-9a-f]{64}$"
_ID_PATTERN = re.compile(ID_RE)
_RECORD_ID_PATTERN = re.compile(RECORD_ID_RE)
_SHA256_PATTERN = re.compile(SHA256_RE)
SPLITS = frozenset({"train", "calibration", "holdout", "quarantine", "fixture"})
PROTECTED_CATEGORIES = (
    "source_shoot", "scene", "person", "location", "time", "derivation",
    "sequence", "take", "device", "dedup_cluster",
)


class AugmentationError(ValueError):
    """Raised when an input, transform, result, or receipt is not admissible."""


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:  # pragma: no cover - repository setup
        raise AugmentationError(f"cannot load frozen authority: {path}") from exc
    if not isinstance(value, dict):
        raise AugmentationError(f"frozen authority is not an object: {path}")
    return value


_LABEL_SCHEMA = _read_json(LABEL_SCHEMA_PATH)
_CONTRACT = _read_json(CONTRACT_PATH)


def _catalog(*path: str) -> tuple[str, ...]:
    current: Any = _LABEL_SCHEMA
    for part in path:
        if not isinstance(current, Mapping):
            raise AugmentationError(f"missing frozen catalog: {'.'.join(path)}")
        current = current.get(part)
    if not isinstance(current, list) or not current or any(type(item) is not str for item in current):
        raise AugmentationError(f"missing frozen catalog: {'.'.join(path)}")
    if len(set(current)) != len(current):
        raise AugmentationError(f"duplicate frozen catalog: {'.'.join(path)}")
    return tuple(current)


def _head_catalog(name: str) -> tuple[str, ...]:
    heads = _CONTRACT.get("outputs", {}).get("heads")
    if not isinstance(heads, list):
        raise AugmentationError("missing frozen output heads")
    for head in heads:
        if isinstance(head, Mapping) and head.get("name") == name:
            values = head.get("ordered_names")
            if isinstance(values, list) and values and all(type(item) is str for item in values):
                return tuple(values)
    raise AugmentationError(f"missing frozen output head: {name}")


ACTION_IDS = _catalog("$defs", "actionId", "enum")
VERIFICATION_ACTION_IDS = _catalog("$defs", "verificationActionId", "enum")
VERIFIER_IDS = _catalog("$defs", "verifierId", "enum")
if set(VERIFICATION_ACTION_IDS) != set(ACTION_IDS) | {"abstain"}:
    raise AugmentationError("frozen verification action catalog drifted from action catalog")
FEATURE_NAMES = tuple(_CONTRACT["inputs"]["scalar_features"]["ordered_names"])
if not FEATURE_NAMES or any(type(name) is not str for name in FEATURE_NAMES) or len(set(FEATURE_NAMES)) != len(FEATURE_NAMES):
    raise AugmentationError("frozen scalar feature catalog is invalid")
ACTION_INDEX = {name: index for index, name in enumerate(ACTION_IDS)}
FEATURE_INDEX = {name: index for index, name in enumerate(FEATURE_NAMES)}
DELTA_NAMES = _head_catalog("continuous_target_deltas")
DELTA_INDEX = {name: index for index, name in enumerate(DELTA_NAMES)}


ACTION_PAIRS = (
    ("shift_frame_left", "shift_frame_right"),
    ("move_subject_left", "move_subject_right"),
    ("move_object_left", "move_object_right"),
)
VERIFIER_PAIRS = (
    ("framing_left_improves", "framing_right_improves"),
    ("subject_position_improves_left", "subject_position_improves_right"),
    ("object_position_improves_left", "object_position_improves_right"),
)
for pair, catalog, name in (
    (ACTION_PAIRS, ACTION_IDS, "action"),
    (VERIFIER_PAIRS, VERIFIER_IDS, "verifier"),
):
    if any(item not in catalog for pair_item in pair for item in pair_item):
        raise AugmentationError(f"frozen {name} directional pair is not in its catalog")
_ACTION_PAIR_NAMES = {item for pair in ACTION_PAIRS for item in pair}
_VERIFIER_PAIR_NAMES = {item for pair in VERIFIER_PAIRS for item in pair}
if any(("left" in item or "right" in item) and item not in _ACTION_PAIR_NAMES for item in ACTION_IDS):
    raise AugmentationError("frozen directional action is not explicitly mapped")
if any(("left" in item or "right" in item) and item not in _VERIFIER_PAIR_NAMES for item in VERIFIER_IDS):
    raise AugmentationError("frozen directional verifier is not explicitly mapped")
ACTION_PAIR_MAP = {item: partner for pair in ACTION_PAIRS for item, partner in (pair, pair[::-1])}
VERIFIER_PAIR_MAP = {item: partner for pair in VERIFIER_PAIRS for item, partner in (pair, pair[::-1])}
SCALAR_PAIRS = (("subject_edge_pressure_left", "subject_edge_pressure_right"),)
SIGNED_SCALARS = ("saliency_left_right_balance", "horizon_angle")
SIGNED_DELTAS = ("delta_x", "horizon_delta")
if any(name.endswith(("_left", "_right")) and name not in {item for pair in SCALAR_PAIRS for item in pair} for name in FEATURE_NAMES):
    raise AugmentationError("frozen directional scalar feature is not explicitly mapped")


def _jsonable(value: Any) -> Any:
    if value is None or type(value) is bool or type(value) is int or type(value) is str:
        return value
    if type(value) is float:
        if not math.isfinite(value):
            raise AugmentationError("non-finite value is not canonical JSON")
        return value
    if isinstance(value, Mapping):
        result: dict[str, Any] = {}
        for key, child in value.items():
            if type(key) is not str:
                raise AugmentationError("canonical JSON object keys must be strings")
            result[key] = _jsonable(child)
        return result
    if isinstance(value, (list, tuple)):
        return [_jsonable(child) for child in value]
    raise AugmentationError(f"unsupported canonical value: {type(value).__name__}")


def canonical_json(value: Any) -> str:
    return json.dumps(_jsonable(value), ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def digest(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


AUGMENTATION_CONFIG: dict[str, Any] = {
    "schema_id": POLICY_SCHEMA_ID,
    "version": AUGMENTATION_VERSION,
    "source_validator": "tools.dataset.camera_coach_check.validate_record(admission=False)",
    "pixel_encoding": "uint8_hwc_rgb_row_major_with_be_u32_shape",
    "protected_categories": list(PROTECTED_CATEGORIES),
    "seed": {"type": "uint63", "sample_counter": "uint63"},
    "transforms": {
        "horizontal_flip": {"parameters": [], "targets": "explicit_exhaustive"},
        "photometric": {"operations": ["identity"], "non_identity": "requires_reannotation"},
        "crop": {"non_full_frame": "requires_reannotation", "full_frame": "requires_reannotation"},
    },
}
AUGMENTATION_CONFIG_SHA256 = digest(AUGMENTATION_CONFIG)
AUGMENTATION_POLICY_SHA256 = digest({"schema_id": POLICY_SCHEMA_ID, "version": AUGMENTATION_VERSION, "config_sha256": AUGMENTATION_CONFIG_SHA256})


def _strict_uint(value: Any, name: str) -> int:
    if type(value) is not int or value < 0 or value > (2**63 - 1):
        raise AugmentationError(f"{name} must be a uint63 integer")
    return value


def _number(value: Any, name: str) -> float:
    if type(value) not in (int, float) or not math.isfinite(float(value)):
        raise AugmentationError(f"{name} must be a finite number (bool is not numeric)")
    return float(value)


def _rect(value: Any, name: str, *, allow_empty: bool = True) -> list[float]:
    if not isinstance(value, (list, tuple)) or len(value) != 4:
        raise AugmentationError(f"{name} must be normalized top-left xywh")
    x, y, width, height = (_number(item, f"{name}[{index}]") for index, item in enumerate(value))
    if not (0.0 <= x <= 1.0 and 0.0 <= y <= 1.0 and 0.0 <= width <= 1.0 and 0.0 <= height <= 1.0):
        raise AugmentationError(f"{name} is outside [0,1]")
    if not allow_empty and (width <= 0.0 or height <= 0.0):
        raise AugmentationError(f"{name} must have positive area")
    if x + width > 1.0 or y + height > 1.0:
        raise AugmentationError(f"{name} exceeds frame bounds")
    return [x, y, width, height]


def _flip_x(x: float, width: float, name: str) -> float:
    mirrored = 0.0 if x == width == 0.0 else 1.0 - x - width
    if not (0.0 <= mirrored <= 1.0 and mirrored + width <= 1.0):
        raise AugmentationError(f"{name} horizontal flip exceeds normalized bounds")
    round_trip = 0.0 if mirrored == width == 0.0 else 1.0 - mirrored - width
    if round_trip != x:
        raise AugmentationError(
            "requires_reannotation: horizontal geometry is not exactly involutive at full precision"
        )
    return mirrored


def _flip_rect(value: Any, name: str) -> list[float]:
    x, y, width, height = _rect(value, name)
    return [_flip_x(x, width, name), y, width, height]


def _canonical_parameters(kind: str, parameters: Any) -> dict[str, Any]:
    if type(parameters) is not dict:
        raise AugmentationError("transform parameters must be an object")
    keys = set(parameters)
    if kind == "horizontal_flip":
        if keys:
            raise AugmentationError("horizontal_flip has no parameters")
        return {}
    if kind == "photometric":
        if keys != {"operation"} or parameters.get("operation") != "identity":
            raise AugmentationError("requires_reannotation: only identity photometric is label-preserving")
        return {"operation": "identity"}
    if kind == "crop":
        if keys != {"window"}:
            raise AugmentationError("crop parameters must contain only window")
        return {"window": _rect(parameters["window"], "crop.window", allow_empty=False)}
    raise AugmentationError(f"unknown transform kind: {kind!r}")


@dataclass(frozen=True)
class AugmentationSpec:
    kind: str
    parameters: Mapping[str, Any] = field(default_factory=dict)
    seed: int = 0
    sample_counter: int = 0
    version: str = AUGMENTATION_VERSION
    config_sha256: str = AUGMENTATION_CONFIG_SHA256
    policy_sha256: str = AUGMENTATION_POLICY_SHA256

    def __post_init__(self) -> None:
        if type(self.kind) is not str or self.kind not in {"horizontal_flip", "photometric", "crop"}:
            raise AugmentationError(f"unknown transform kind: {self.kind!r}")
        if self.version != AUGMENTATION_VERSION:
            raise AugmentationError("unsupported augmentation version")
        if self.config_sha256 != AUGMENTATION_CONFIG_SHA256 or self.policy_sha256 != AUGMENTATION_POLICY_SHA256:
            raise AugmentationError("augmentation config/policy digest mismatch")
        _strict_uint(self.seed, "seed")
        _strict_uint(self.sample_counter, "sample_counter")
        _canonical_parameters(self.kind, self.parameters)

    def canonical(self) -> dict[str, Any]:
        return {
            "kind": self.kind,
            "version": self.version,
            "parameters": _canonical_parameters(self.kind, self.parameters),
            "seed": self.seed,
            "sample_counter": self.sample_counter,
            "config_sha256": self.config_sha256,
            "policy_sha256": self.policy_sha256,
        }


def validate_spec(spec: AugmentationSpec | Mapping[str, Any] | str) -> AugmentationSpec:
    if isinstance(spec, AugmentationSpec):
        return AugmentationSpec(**spec.canonical())
    if isinstance(spec, str):
        return AugmentationSpec(spec)
    if type(spec) is not dict:
        raise AugmentationError("spec must be an object")
    allowed = {"kind", "parameters", "seed", "sample_counter", "version", "config_sha256", "policy_sha256"}
    if set(spec).difference(allowed) or "kind" not in spec:
        raise AugmentationError("spec has unknown or missing keys")
    return AugmentationSpec(
        kind=spec["kind"], parameters=spec.get("parameters", {}), seed=spec.get("seed", 0),
        sample_counter=spec.get("sample_counter", 0), version=spec.get("version", AUGMENTATION_VERSION),
        config_sha256=spec.get("config_sha256", AUGMENTATION_CONFIG_SHA256),
        policy_sha256=spec.get("policy_sha256", AUGMENTATION_POLICY_SHA256),
    )


def _validate_source(record: Any) -> dict[str, Any]:
    if type(record) is not dict:
        raise AugmentationError("source record must be a plain object")
    errors = validate_record(record, {}, admission=False)
    if errors:
        raise AugmentationError("source record rejected: " + "; ".join(errors))
    return record


def _pixel_data(pixels: Any, name: str = "pixels") -> tuple[tuple[tuple[int, int, int], ...], ...]:
    if not isinstance(pixels, (list, tuple)) or not pixels:
        raise AugmentationError(f"{name} is required and must be non-empty HWC RGB")
    if any(not isinstance(row, (list, tuple)) or not row for row in pixels):
        raise AugmentationError(f"{name} must be non-empty HWC RGB")
    width = len(pixels[0])
    if any(len(row) != width for row in pixels):
        raise AugmentationError(f"{name} rows have inconsistent widths")
    rows: list[tuple[tuple[int, int, int], ...]] = []
    for row_index, row in enumerate(pixels):
        converted: list[tuple[int, int, int]] = []
        for col_index, pixel in enumerate(row):
            if not isinstance(pixel, (list, tuple)) or len(pixel) != 3:
                raise AugmentationError(f"{name}[{row_index}][{col_index}] must be RGB")
            channels = []
            for channel in pixel:
                if type(channel) is not int or not 0 <= channel <= 255:
                    raise AugmentationError(f"{name} must contain uint8 channels")
                channels.append(channel)
            converted.append(tuple(channels))  # type: ignore[arg-type]
        rows.append(tuple(converted))
    return tuple(rows)


def _pixel_bytes(data: tuple[tuple[tuple[int, int, int], ...], ...]) -> bytes:
    height, width = len(data), len(data[0])
    return struct.pack(">III", height, width, 3) + bytes(channel for row in data for pixel in row for channel in pixel)


def pixel_digest(pixels: Any) -> str:
    return hashlib.sha256(_pixel_bytes(_pixel_data(pixels))).hexdigest()


def _pixel_lists(data: tuple[tuple[tuple[int, int, int], ...], ...]) -> list[list[list[int]]]:
    return [[list(pixel) for pixel in row] for row in data]


def _transform_pixels(data: tuple[tuple[tuple[int, int, int], ...], ...], spec: AugmentationSpec) -> tuple[tuple[tuple[int, int, int], ...], ...]:
    if spec.kind == "horizontal_flip":
        return tuple(tuple(reversed(row)) for row in data)
    if spec.kind == "photometric":
        return data
    raise AugmentationError("requires_reannotation: crop output cannot be proven label-preserving")


def _map_action(value: Any) -> Any:
    return ACTION_PAIR_MAP.get(value, value)


def _map_verifier(value: Any) -> Any:
    return VERIFIER_PAIR_MAP.get(value, value)


def _flip_label(record: Mapping[str, Any]) -> dict[str, Any]:
    label = copy.deepcopy(record["label"])
    for key in ("acceptable_action_ids", "forbidden_action_ids"):
        label[key] = [_map_action(value) for value in label[key]]
    if label["selected_action_id"] is not None:
        label["selected_action_id"] = _map_action(label["selected_action_id"])
    for issue in label["issues"]:
        for key in ("acceptable_action_ids", "forbidden_action_ids"):
            issue[key] = [_map_action(value) for value in issue[key]]
    for verification in label["verification"]:
        verification["action_id"] = _map_action(verification["action_id"])
        verification["verifier_id"] = _map_verifier(verification["verifier_id"])
    return label


def _validate_regions(value: Any, name: str) -> dict[str, list[float]]:
    if type(value) is not dict:
        raise AugmentationError(f"{name} must be an object of target_id to xywh")
    result: dict[str, list[float]] = {}
    for key, region in value.items():
        if type(key) is not str or not _ID_PATTERN.fullmatch(key):
            raise AugmentationError(f"{name} has an invalid target ID")
        result[key] = _rect(region, f"{name}.{key}")
    return result


FEATURE_TARGET_KEYS = frozenset({
    "scalar_features", "scalar_vector", "missing_feature_mask", "action_utility_logits",
    "continuous_target_deltas", "roi_normalized_xywh", "roi_mask",
})
_FEATURE_NORMALIZATION = _CONTRACT.get("feature_normalization", {}).get("feature_to_normalization")
if not isinstance(_FEATURE_NORMALIZATION, Mapping) or set(_FEATURE_NORMALIZATION) != set(FEATURE_NAMES):
    raise AugmentationError("frozen scalar feature normalization catalog is invalid")
_CATEGORICAL_VALUES = {
    name: tuple(values)
    for name, values in (
        ("orientation_category", _CONTRACT["categorical_features"]["orientation_category"]["allowed_normalized_values"]),
        ("lens_category", _CONTRACT["categorical_features"]["lens_category"]["allowed_normalized_values"]),
    )
}


def _finite_vector(value: Any, length: int, name: str) -> list[float]:
    if not isinstance(value, (list, tuple)) or len(value) != length:
        raise AugmentationError(f"{name} must contain exactly {length} values")
    return [_number(item, f"{name}[{index}]") for index, item in enumerate(value)]


def _validate_scalar_values(values: Mapping[str, Any], name: str) -> dict[str, float]:
    if set(values) != set(FEATURE_NAMES):
        raise AugmentationError(f"{name} must contain exactly the frozen feature names")
    result = {feature: _number(values[feature], f"{name}.{feature}") for feature in FEATURE_NAMES}
    for feature, value in result.items():
        normalization = _FEATURE_NORMALIZATION[feature]
        lower, upper = (-1.0, 1.0) if normalization in {"signed_unit_interval", "angle_degrees_to_unit"} else (0.0, 1.0)
        if not lower <= value <= upper:
            raise AugmentationError(f"{name}.{feature} is outside its frozen normalized range")
        allowed = _CATEGORICAL_VALUES.get(feature)
        if allowed is not None and value not in allowed:
            raise AugmentationError(f"{name}.{feature} is not a frozen categorical value")
    x, y, width, height = (result[key] for key in ("subject_bbox_x", "subject_bbox_y", "subject_bbox_width", "subject_bbox_height"))
    if x + width > 1.0 or y + height > 1.0:
        raise AugmentationError(f"{name} subject bbox exceeds frame bounds")
    if result["mirroring_flag"] not in (0.0, 1.0) or result["roi_present"] not in (0.0, 1.0):
        raise AugmentationError(f"{name} boolean-like features must be binary")
    return result


def _validate_features(value: Any) -> dict[str, Any]:
    if type(value) is not dict or set(value).difference(FEATURE_TARGET_KEYS):
        raise AugmentationError("features has unknown or missing supported keys")
    result: dict[str, Any] = {}
    for key, child in value.items():
        if key == "scalar_features":
            if not isinstance(child, Mapping):
                raise AugmentationError("scalar_features must contain exactly the frozen feature names")
            result[key] = _validate_scalar_values(child, "scalar_features")
        elif key == "scalar_vector":
            vector = _finite_vector(child, len(FEATURE_NAMES), key)
            validated_vector = _validate_scalar_values(dict(zip(FEATURE_NAMES, vector)), key)
            result[key] = [validated_vector[name] for name in FEATURE_NAMES]
        elif key == "missing_feature_mask":
            values = _finite_vector(child, len(FEATURE_NAMES), key)
            if any(item not in (0.0, 1.0) for item in values):
                raise AugmentationError("missing_feature_mask must be binary")
            result[key] = values
        elif key == "action_utility_logits":
            result[key] = _finite_vector(child, len(ACTION_IDS), key)
        elif key == "continuous_target_deltas":
            result[key] = _finite_vector(child, len(DELTA_NAMES), key)
            if any(value < -1.0 or value > 1.0 for value in result[key]):
                raise AugmentationError("continuous_target_deltas is outside [-1,1]")
        elif key == "roi_normalized_xywh":
            result[key] = _rect(child, key)
        elif key == "roi_mask":
            values = _finite_vector(child, 320 * 320, key)
            if any(item not in (0.0, 1.0) for item in values):
                raise AugmentationError("roi_mask must be binary 320*320")
            result[key] = values
    return result


def _base_targets(record: Mapping[str, Any], targets: Mapping[str, Any] | None) -> dict[str, Any]:
    result: dict[str, Any] = {"label": copy.deepcopy(record["label"])}
    if "episode" in record:
        result["episode"] = copy.deepcopy(record["episode"])
    source_regions: dict[str, list[float]] = {}
    for candidate in record["subject"]["candidates"]:
        if "region" in candidate:
            subject_id = candidate["subject_id"]
            if subject_id in source_regions:
                raise AugmentationError("source subject IDs are not unique")
            source_regions[subject_id] = _rect(candidate["region"], f"subject.candidates.{subject_id}.region")
    if source_regions:
        result["regions"] = source_regions
    if targets is None:
        return result
    if type(targets) is not dict or set(targets).difference({"label", "episode", "regions", "features"}):
        raise AugmentationError("targets has unknown keys")
    if "label" in targets and targets["label"] != result["label"]:
        raise AugmentationError("targets.label must exactly match the source label")
    if "episode" in targets and targets["episode"] != result.get("episode"):
        raise AugmentationError("targets.episode must exactly match the source episode")
    if "regions" in targets:
        supplied_regions = _validate_regions(targets["regions"], "targets.regions")
        if source_regions and supplied_regions != source_regions:
            raise AugmentationError("targets.regions must preserve source tracked regions")
        result["regions"] = supplied_regions
    if "features" in targets:
        result["features"] = _validate_features(targets["features"])
    return result


def _flip_scalar_mapping(value: Mapping[str, Any]) -> dict[str, float]:
    if set(value) != set(FEATURE_NAMES):
        raise AugmentationError("scalar_features must contain exactly the frozen feature names")
    result = {name: _number(value[name], f"scalar_features.{name}") for name in FEATURE_NAMES}
    x, width = result["subject_bbox_x"], result["subject_bbox_width"]
    if not (0.0 <= x <= 1.0 and 0.0 <= width <= 1.0 and x + width <= 1.0):
        raise AugmentationError("scalar subject bbox is outside normalized bounds")
    result["subject_bbox_x"] = _flip_x(x, width, "scalar_features.subject_bbox_x")
    for left, right in SCALAR_PAIRS:
        result[left], result[right] = result[right], result[left]
    for name in SIGNED_SCALARS:
        result[name] = -result[name]
    # The contract stores quarter-turn orientation separately from mirror
    # state; a horizontal reflection therefore leaves orientation_category
    # unchanged and toggles only mirroring_flag.
    if result["mirroring_flag"] not in (0.0, 1.0):
        raise AugmentationError("mirroring_flag must be binary")
    result["mirroring_flag"] = 1.0 - result["mirroring_flag"]
    return result


def _flip_features(features: Mapping[str, Any]) -> dict[str, Any]:
    result = _validate_features(features)
    if "scalar_features" in result:
        result["scalar_features"] = _flip_scalar_mapping(result["scalar_features"])
    if "scalar_vector" in result:
        values = result["scalar_vector"]
        x_index, width_index = FEATURE_INDEX["subject_bbox_x"], FEATURE_INDEX["subject_bbox_width"]
        if not (0.0 <= values[x_index] <= 1.0 and 0.0 <= values[width_index] <= 1.0 and values[x_index] + values[width_index] <= 1.0):
            raise AugmentationError("scalar_vector subject bbox is outside normalized bounds")
        values[x_index] = _flip_x(values[x_index], values[width_index], "scalar_vector.subject_bbox_x")
        for left, right in SCALAR_PAIRS:
            left_index, right_index = FEATURE_INDEX[left], FEATURE_INDEX[right]
            values[left_index], values[right_index] = values[right_index], values[left_index]
        for name in SIGNED_SCALARS:
            values[FEATURE_INDEX[name]] = -values[FEATURE_INDEX[name]]
        mirror_index = FEATURE_INDEX["mirroring_flag"]
        if values[mirror_index] not in (0.0, 1.0):
            raise AugmentationError("scalar_vector mirroring_flag must be binary")
        values[mirror_index] = 1.0 - values[mirror_index]
    if "missing_feature_mask" in result:
        values = result["missing_feature_mask"]
        for left, right in SCALAR_PAIRS:
            left_index, right_index = FEATURE_INDEX[left], FEATURE_INDEX[right]
            values[left_index], values[right_index] = values[right_index], values[left_index]
    if "action_utility_logits" in result:
        values = result["action_utility_logits"]
        for left, right in ACTION_PAIRS:
            left_index, right_index = ACTION_INDEX[left], ACTION_INDEX[right]
            values[left_index], values[right_index] = values[right_index], values[left_index]
    if "continuous_target_deltas" in result:
        values = result["continuous_target_deltas"]
        for name in SIGNED_DELTAS:
            values[DELTA_INDEX[name]] = -values[DELTA_INDEX[name]]
    if "roi_normalized_xywh" in result:
        result["roi_normalized_xywh"] = _flip_rect(result["roi_normalized_xywh"], "roi_normalized_xywh")
    if "roi_mask" in result:
        values = result["roi_mask"]
        result["roi_mask"] = [item for offset in range(0, len(values), 320) for item in reversed(values[offset:offset + 320])]
    return result


def _transform_targets(base: Mapping[str, Any], spec: AugmentationSpec) -> dict[str, Any]:
    result = copy.deepcopy(dict(base))
    if spec.kind != "horizontal_flip":
        return result
    result["label"] = _flip_label({"label": base["label"]})
    if "episode" in base:
        episode = copy.deepcopy(base["episode"])
        episode["action_step"]["action_id"] = _map_action(episode["action_step"]["action_id"])
        episode["outcome_verifier"] = _map_verifier(episode["outcome_verifier"])
        result["episode"] = episode
    if "regions" in base:
        result["regions"] = {name: _flip_rect(region, f"regions.{name}") for name, region in base["regions"].items()}
    if "features" in base:
        result["features"] = _flip_features(base["features"])
    return result


def _families(record: Mapping[str, Any], dedup_cluster_id: str | None) -> tuple[dict[str, list[str]], str]:
    provenance, capture = record["provenance"], record["capture"]
    sequence = record.get("sequence")
    families = {
        "source_shoot": [provenance["source_shoot_id"]],
        "scene": [capture["scene_family_id"]],
        "person": sorted(capture["person_family_ids"]),
        "location": [capture["location_family_id"]],
        "time": [capture["time_family_id"]],
        "derivation": [provenance["derivation_family_id"]],
        "sequence": [sequence["sequence_id"]] if isinstance(sequence, Mapping) else [],
        "take": [capture["take_family_id"]],
        "device": [capture["device_family_id"]],
        "dedup_cluster": [dedup_cluster_id] if dedup_cluster_id is not None else [],
    }
    for category, values in families.items():
        if any(type(value) is not str or not _ID_PATTERN.fullmatch(value) for value in values) or len(set(values)) != len(values):
            raise AugmentationError(f"invalid protected family values: {category}")
        if values != sorted(values):
            raise AugmentationError(f"protected family values must be sorted: {category}")
    split = record["split"]
    if type(split) is not str or split not in SPLITS:
        raise AugmentationError("invalid protected split owner")
    return families, split


LINEAGE_KEYS = frozenset({
    "schema_id", "schema_version", "source_record_id", "source_record_sha256", "protected_families",
    "protected_split_owner", "transform", "frozen_config_sha256", "frozen_policy_sha256", "seed",
    "sample_counter", "input_pixels_sha256", "output_pixels_sha256", "source_targets_sha256",
    "output_targets_sha256", "receipt_sha256",
})
LINEAGE_ORDER = tuple(sorted(LINEAGE_KEYS))
PROTECTED_FAMILY_ORDER = tuple(sorted(PROTECTED_CATEGORIES))


def _lineage_body(record: Mapping[str, Any], input_data: Any, output_data: Any, source_targets: Mapping[str, Any], output_targets: Mapping[str, Any], spec: AugmentationSpec, dedup_cluster_id: str | None) -> dict[str, Any]:
    families, split = _families(record, dedup_cluster_id)
    body = {
        "schema_id": LINEAGE_SCHEMA_ID,
        "schema_version": AUGMENTATION_VERSION,
        "source_record_id": record["record_id"],
        "source_record_sha256": digest(record),
        "protected_families": dict(sorted(families.items())),
        "protected_split_owner": split,
        "transform": {"kind": spec.kind, "parameters": spec.canonical()["parameters"], "version": spec.version},
        "frozen_config_sha256": spec.config_sha256,
        "frozen_policy_sha256": spec.policy_sha256,
        "seed": spec.seed,
        "sample_counter": spec.sample_counter,
        "input_pixels_sha256": hashlib.sha256(_pixel_bytes(input_data)).hexdigest(),
        "output_pixels_sha256": hashlib.sha256(_pixel_bytes(output_data)).hexdigest(),
        "source_targets_sha256": digest(source_targets),
        "output_targets_sha256": digest(output_targets),
    }
    return dict(sorted(body.items()))


def _validate_lineage_shape(lineage: Any) -> None:
    if type(lineage) is not dict or set(lineage) != LINEAGE_KEYS:
        raise AugmentationError("lineage has unknown or missing keys")
    if tuple(lineage) != LINEAGE_ORDER:
        raise AugmentationError("lineage keys are not in canonical order")
    if lineage["schema_id"] != LINEAGE_SCHEMA_ID or lineage["schema_version"] != AUGMENTATION_VERSION:
        raise AugmentationError("lineage schema/version mismatch")
    if type(lineage["source_record_id"]) is not str or not _RECORD_ID_PATTERN.fullmatch(lineage["source_record_id"]):
        raise AugmentationError("lineage source record ID is invalid")
    if type(lineage["protected_split_owner"]) is not str or lineage["protected_split_owner"] not in SPLITS:
        raise AugmentationError("lineage split owner is invalid")
    protected = lineage["protected_families"]
    if type(protected) is not dict or set(protected) != set(PROTECTED_CATEGORIES):
        raise AugmentationError("lineage protected categories are unknown or incomplete")
    if tuple(protected) != PROTECTED_FAMILY_ORDER:
        raise AugmentationError("lineage protected categories are not in canonical order")
    for category in PROTECTED_CATEGORIES:
        values = protected[category]
        if not isinstance(values, list) or any(type(item) is not str or not _ID_PATTERN.fullmatch(item) for item in values) or len(set(values)) != len(values) or values != sorted(values):
            raise AugmentationError(f"lineage protected family list is invalid: {category}")
    if len(protected["derivation"]) != 1:
        raise AugmentationError("lineage derivation family is invalid")
    transform = lineage["transform"]
    if type(transform) is not dict or set(transform) != {"kind", "version", "parameters"}:
        raise AugmentationError("lineage transform is not closed")
    if tuple(transform) != tuple(sorted(("kind", "version", "parameters"))):
        raise AugmentationError("lineage transform is not in canonical order")
    spec = AugmentationSpec(
        kind=transform["kind"], version=transform["version"], parameters=transform["parameters"],
        seed=lineage["seed"], sample_counter=lineage["sample_counter"],
        config_sha256=lineage["frozen_config_sha256"], policy_sha256=lineage["frozen_policy_sha256"],
    )
    expected_transform = {"kind": spec.kind, "version": spec.version, "parameters": spec.canonical()["parameters"]}
    if canonical_json(transform) != canonical_json(expected_transform):
        raise AugmentationError("lineage transform is not canonical")
    for name in ("source_record_sha256", "frozen_config_sha256", "frozen_policy_sha256", "input_pixels_sha256", "output_pixels_sha256", "source_targets_sha256", "output_targets_sha256"):
        if type(lineage[name]) is not str or not _SHA256_PATTERN.fullmatch(lineage[name]):
            raise AugmentationError(f"lineage digest is invalid: {name}")
    _strict_uint(lineage["seed"], "lineage.seed")
    _strict_uint(lineage["sample_counter"], "lineage.sample_counter")
    receipt = lineage["receipt_sha256"]
    if type(receipt) is not str or not _SHA256_PATTERN.fullmatch(receipt):
        raise AugmentationError("lineage receipt is invalid")
    body = {key: value for key, value in lineage.items() if key != "receipt_sha256"}
    if digest(body) != receipt:
        raise AugmentationError("lineage receipt does not authenticate its body")


def validate_result(
    source_record: Mapping[str, Any],
    input_pixels: Any,
    result: Mapping[str, Any],
    spec: AugmentationSpec | Mapping[str, Any] | str,
    *,
    source_targets: Mapping[str, Any] | None = None,
    dedup_cluster_id: str | None = None,
) -> None:
    record = _validate_source(source_record)
    validated = validate_spec(spec)
    input_data = _pixel_data(input_pixels, "input_pixels")
    if type(result) is not dict or set(result) != {"record_id", "pixels", "targets", "lineage"}:
        raise AugmentationError("result has unknown or missing keys")
    if result["record_id"] != record["record_id"]:
        raise AugmentationError("result record_id does not retain the source record ID")
    if type(result["targets"]) is not dict or type(result["lineage"]) is not dict:
        raise AugmentationError("result targets and lineage must be plain objects")
    output_data = _pixel_data(result["pixels"], "result.pixels")
    base = _base_targets(record, source_targets)
    expected_targets = _transform_targets(base, validated)
    if validated.kind == "crop":
        raise AugmentationError("requires_reannotation: crop is not admitted")
    expected_pixels = _transform_pixels(input_data, validated)
    if output_data != expected_pixels:
        raise AugmentationError("result pixels disagree with replayed transform")
    if result["targets"] != expected_targets:
        raise AugmentationError("result targets disagree with replayed transform")
    lineage = result["lineage"]
    _validate_lineage_shape(lineage)
    expected_body = _lineage_body(record, input_data, expected_pixels, base, expected_targets, validated, dedup_cluster_id)
    expected_lineage = dict(sorted({**expected_body, "receipt_sha256": digest(expected_body)}.items()))
    if canonical_json(lineage) != canonical_json(expected_lineage):
        raise AugmentationError("lineage does not replay from source record/pixels/targets")


def augment(
    source_record: Mapping[str, Any],
    input_pixels: Any,
    spec: AugmentationSpec | Mapping[str, Any] | str,
    *,
    source_targets: Mapping[str, Any] | None = None,
    dedup_cluster_id: str | None = None,
) -> dict[str, Any]:
    """Return a replayable training result without creating a canonical record."""

    record = _validate_source(source_record)
    validated = validate_spec(spec)
    input_data = _pixel_data(input_pixels, "input_pixels")
    if validated.kind == "crop":
        raise AugmentationError("requires_reannotation: crop is not admitted")
    base = _base_targets(record, source_targets)
    output_targets = _transform_targets(base, validated)
    output_data = _transform_pixels(input_data, validated)
    body = _lineage_body(record, input_data, output_data, base, output_targets, validated, dedup_cluster_id)
    lineage = dict(sorted({**body, "receipt_sha256": digest(body)}.items()))
    result = {"record_id": record["record_id"], "pixels": _pixel_lists(output_data), "targets": output_targets, "lineage": lineage}
    validate_result(record, input_pixels, result, validated, source_targets=source_targets, dedup_cluster_id=dedup_cluster_id)
    return result


def validate_lineage_batch(lineages: Sequence[Mapping[str, Any]]) -> None:
    if not isinstance(lineages, Sequence) or isinstance(lineages, (str, bytes)):
        raise AugmentationError("lineage batch must be a sequence")
    seen_receipts: set[str] = set()
    seen_counters: set[tuple[str, int, int]] = set()
    category_splits: dict[tuple[str, str], str] = {}
    for lineage in lineages:
        _validate_lineage_shape(lineage)
        receipt = lineage["receipt_sha256"]
        if receipt in seen_receipts:
            raise AugmentationError("replayed lineage receipt")
        counter_key = (lineage["source_record_id"], lineage["seed"], lineage["sample_counter"])
        if counter_key in seen_counters:
            raise AugmentationError("replayed source seed/sample counter")
        split = lineage["protected_split_owner"]
        for category in PROTECTED_CATEGORIES:
            for family_id in lineage["protected_families"][category]:
                key = (category, family_id)
                if key in category_splits and category_splits[key] != split:
                    raise AugmentationError(f"protected {category} crosses split owners")
                category_splits[key] = split
        seen_receipts.add(receipt)
        seen_counters.add(counter_key)


def _manifest_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise AugmentationError("derivation manifest has duplicate JSON keys")
        result[key] = value
    return result


MANIFEST_KEYS = frozenset({
    "manifest_type", "schema_id", "manifest_version", "manifest_id", "manifest_sha256", "entry_schema",
    "record_count", "hash_algorithm", "raw_data_location", "rights_uncleared_location", "template_only",
    "independence_rule", "augmentation_policy_schema_id", "augmentation_lineage_schema_id",
})


def validate_derivation_manifest(path: Path | str = DERIVATION_MANIFEST_PATH) -> dict[str, Any]:
    manifest_path = Path(path)
    try:
        lines = manifest_path.read_text(encoding="utf-8").splitlines()
        payload = json.loads(lines[0], object_pairs_hook=_manifest_pairs) if len(lines) == 1 and lines[0] else None
    except (OSError, IndexError, json.JSONDecodeError) as exc:
        raise AugmentationError(f"invalid derivation manifest: {manifest_path}") from exc
    if not isinstance(payload, Mapping) or set(payload) != MANIFEST_KEYS:
        raise AugmentationError("derivation manifest has unknown or missing keys")
    if canonical_json(payload) != lines[0]:
        raise AugmentationError("derivation manifest is not canonical JSON")
    if payload["manifest_type"] != "derivation" or payload["schema_id"] != "camera-derivation-manifest-v1" or payload["manifest_version"] != RECORD_SCHEMA_VERSION:
        raise AugmentationError("derivation manifest schema mismatch")
    if payload["manifest_id"] != "camera-derivation-manifest" or payload["entry_schema"] != "camera-derivation-entry-v1":
        raise AugmentationError("derivation manifest identity mismatch")
    if type(payload["record_count"]) is not int or payload["record_count"] != 0 or payload["hash_algorithm"] != "sha256":
        raise AugmentationError("derivation manifest must remain zero-record sha256")
    if payload["raw_data_location"] != "outside_git" or payload["rights_uncleared_location"] != "outside_git" or payload["template_only"] is not True:
        raise AugmentationError("derivation manifest storage/template policy mismatch")
    if payload["augmentation_policy_schema_id"] != POLICY_SCHEMA_ID or payload["augmentation_lineage_schema_id"] != LINEAGE_SCHEMA_ID:
        raise AugmentationError("derivation manifest augmentation binding mismatch")
    if payload["independence_rule"] != "only explicitly independent source decisions count toward a split quota":
        raise AugmentationError("derivation manifest independence rule mismatch")
    if payload["manifest_sha256"] != digest({key: value for key, value in payload.items() if key != "manifest_sha256"}):
        raise AugmentationError("derivation manifest hash mismatch")
    return dict(payload)


__all__ = [
    "ACTION_IDS", "ACTION_PAIRS", "AUGMENTATION_CONFIG", "AUGMENTATION_CONFIG_SHA256", "AUGMENTATION_POLICY_SHA256",
    "AugmentationError", "AugmentationSpec", "DELTA_NAMES", "DERIVATION_MANIFEST_PATH", "FEATURE_NAMES",
    "LINEAGE_SCHEMA_ID", "POLICY_SCHEMA_ID", "VERIFIER_IDS", "VERIFIER_PAIRS", "augment", "canonical_json",
    "digest", "pixel_digest", "validate_derivation_manifest", "validate_lineage_batch", "validate_result", "validate_spec",
]
