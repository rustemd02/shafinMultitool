#!/usr/bin/env python3
"""Research-only Stage-2 Camera Coach silver-action trainer.

This runner consumes the external output of ``generate_camera_corruptions.py``
(``pairs.jsonl`` + ``receipt.json`` + derivative image root).  It never reads
the source/control image referenced by a pair.  A completed EVA Stage-1
encoder may initialise CandidateA's full-frame branch only when its artifact
hash is supplied explicitly and agrees with the completed Stage-1 receipt.

Only the three heads represented by the silver pair schema are optimized:
``issue_logits``, ``action_utility_logits``, and
``continuous_target_deltas``.  The other SET heads remain frozen and absent
targets remain unavailable rather than becoming negative labels.  Outputs are
fit-only research evidence; no validation/test split or release claim exists.
"""

from __future__ import annotations

import argparse
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import datetime, timezone
from io import BytesIO
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import pickle
import platform
import random
import re
import stat
import subprocess
import sys
import tempfile
import warnings
from types import MappingProxyType
from typing import Any, Callable

try:
    import torch
    from PIL import Image
    from torch import Tensor, nn
except ImportError as exc:  # pragma: no cover - normal Colab runtime has both.
    raise SystemExit("Stage-2 silver training needs the preinstalled Torch and Pillow runtimes") from exc


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from ml.camera_coach.data.preprocessing import PreprocessingError, preprocess_frame  # noqa: E402
from ml.camera_coach.losses import LossConfig, LossError, LossWeights, compute_multitask_loss  # noqa: E402
from ml.camera_coach.models import CandidateA, SETCompositionNetInputs, SETCompositionNetManifest  # noqa: E402


CONFIG_SCHEMA_ID = "camera-silver-actions-stage2-config-v1"
CONFIG_SCHEMA_VERSION = "1.0.0"
PAIR_RECEIPT_SCHEMA_ID = "camera-silver-action-pair-receipt-v1"
PAIR_SCHEMA_ID = "camera-silver-action-pair-v1"
PAIR_SCHEMA_VERSION = "1.0.0"
STAGE1_RECEIPT_SCHEMA_ID = "camera-eva-stage1-training-receipt-v1"
STAGE1_ENCODER_SCHEMA_ID = "camera-eva-stage1-encoder-v1"
CHECKPOINT_SCHEMA_ID = "camera-silver-actions-stage2-checkpoint-v1"
RECEIPT_SCHEMA_ID = "camera-silver-actions-stage2-training-receipt-v1"
ARTIFACT_SCHEMA_ID = "camera-silver-actions-stage2-artifact-v1"
MODEL_CONTRACT_ID = "SETCompositionNet-v1"
MODEL_MANIFEST_RELATIVE = "ml/camera_coach/contracts/set_composition_net_v1.json"
MODEL_SOURCE_RELATIVE = "ml/camera_coach/models/set_composition_net.py"
PREPROCESSING_SOURCE_RELATIVE = "ml/camera_coach/data/preprocessing.py"
LOSSES_SOURCE_RELATIVE = "ml/camera_coach/losses.py"
PAIR_SCHEMA_RELATIVE = "datasets/camera-coach/v1/silver-action-pair-schema.json"
GENERATOR_SOURCE_RELATIVE = "tools/dataset/generate_camera_corruptions.py"
GEOMETRY_SCHEMA_RELATIVE = "datasets/camera-coach/v1/silver-geometry-schema.json"
GEOMETRY_TOOL_RELATIVE = "tools/dataset/extract_camera_geometry.swift"
GEOMETRY_RECEIPT_SCHEMA_ID = "camera-silver-geometry-receipt-v1"
GEOMETRY_DETERMINISM = "conditional_on_captured_apple_os_vision_runtime"
VISION_REQUEST_FAMILY = (
    "VNDetectHumanRectanglesRequest",
    "VNDetectFaceRectanglesRequest",
    "VNGenerateAttentionBasedSaliencyImageRequest",
    "VNDetectHorizonRequest",
)
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
PAIR_ID_RE = re.compile(r"^pair_[0-9a-f]{40}$")
FAMILY_ID_RE = re.compile(r"^family_[0-9a-f]{32}$")
DERIVATIVE_RE = re.compile(r"^images/pair_[0-9a-f]{40}\.png$")
CHECKPOINT_RE = re.compile(r"^epoch-(?P<epoch>[0-9]{4})\.pt$")
TRAINABLE_HEADS = ("issue_logits", "action_utility_logits", "continuous_target_deltas")
EXPECTED_CONFIG_KEYS = {"schema_id", "schema_version", "seed", "input_size", "data", "stage1", "training", "model"}
EXPECTED_DATA_KEYS = {"manifest", "receipt", "image_root"}
EXPECTED_STAGE1_KEYS = {"artifact", "receipt"}
EXPECTED_TRAINING_KEYS = {
    "epochs", "batch_size", "learning_rate", "weight_decay", "max_records", "focal_gamma", "focal_alpha", "loss_weights",
}
EXPECTED_MODEL_KEYS = {"candidate", "manifest_path", "manifest_sha256"}
EXPECTED_WEIGHT_KEYS = set(TRAINABLE_HEADS)
PAIR_TOP_KEYS = {
    "schema_id", "schema_version", "pair_id", "source_family_id", "derivation_family_id", "split",
    "is_independent", "counts_toward_quota", "research_only", "human_gold", "release_admissible",
    "source", "derivative", "recipe", "roi", "geometry", "targets", "semantics_sha256",
}
PAIR_TOP_OPTIONAL_KEYS = {"issue_projection"}
PAIR_TARGET_KEYS = {"issue", "action", "continuous"}
PAIR_RECEIPT_KEYS = {
    "schema_id", "schema_version", "research_only", "human_gold", "release_admissible", "split",
    "seed", "max_per_source", "inputs", "geometry_receipt", "generator_source", "contract",
    "pair_schema", "semantics", "semantics_sha256", "counts", "output_manifest", "output_media",
}
GEOMETRY_INPUT_KEYS = {"sha256", "schema_sha256", "records", "receipt_path", "receipt_sha256"}
GEOMETRY_RECEIPT_BINDING_KEYS = {"path", "sha256", "schema_id", "schema_version", "determinism", "environment", "tool_source"}
GEOMETRY_ENVIRONMENT_KEYS = {
    "os_version", "os_version_components", "platform", "vision_framework",
    "vision_request_family", "vision_request_revisions",
}


class Stage2Error(ValueError):
    """Raised when a Stage-2 run cannot be admitted or resumed safely."""


class ConfigError(Stage2Error):
    """Raised for an unsupported or malformed Stage-2 config."""


def _reject_nonfinite(value: str) -> Any:
    raise Stage2Error(f"non-finite JSON value is not allowed: {value}")


def _canonical_json(value: object) -> str:
    try:
        return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)
    except (TypeError, ValueError, OverflowError, RecursionError) as exc:
        raise Stage2Error("value is not canonical JSON") from exc


def _read_json(path: Path, label: str) -> Any:
    try:
        payload = path.read_text(encoding="utf-8")
        return json.loads(payload, parse_constant=_reject_nonfinite)
    except Stage2Error:
        raise
    except (OSError, UnicodeError, json.JSONDecodeError, RecursionError) as exc:
        raise Stage2Error(f"cannot read {label}: {path}") from exc


def _read_jsonl(path: Path, label: str) -> tuple[list[dict[str, Any]], bytes]:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise Stage2Error(f"cannot read {label}: {path}") from exc
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise Stage2Error(f"{label} is not UTF-8") from exc
    rows: list[dict[str, Any]] = []
    for line_number, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            raise Stage2Error(f"{label} has a blank line at {line_number}")
        try:
            value = json.loads(line, parse_constant=_reject_nonfinite)
        except Stage2Error:
            raise
        except (json.JSONDecodeError, RecursionError) as exc:
            raise Stage2Error(f"{label} line {line_number} is malformed JSON") from exc
        if not isinstance(value, dict):
            raise Stage2Error(f"{label} line {line_number} must be an object")
        rows.append(value)
    if not rows:
        raise Stage2Error(f"{label} contains no rows")
    return rows, raw


def _sha256_file(path: Path, label: str = "file") -> str:
    try:
        info = path.lstat()
    except OSError as exc:
        raise Stage2Error(f"cannot inspect {label}: {path}") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise Stage2Error(f"{label} is not a regular non-symlink file: {path}")
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise Stage2Error(f"cannot read {label}: {path}") from exc
    return digest.hexdigest()


def _sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _valid_sha(value: object, label: str) -> str:
    if not isinstance(value, str) or SHA256_RE.fullmatch(value) is None:
        raise Stage2Error(f"{label} must be a lowercase SHA-256 digest")
    return value


def _require_keys(value: object, expected: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ConfigError(f"{label} must be an object")
    actual = set(value)
    if actual != expected:
        raise ConfigError(f"{label} keys drifted; missing={sorted(expected - actual)}, extra={sorted(actual - expected)}")
    return value


def _require_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip() or "\x00" in value:
        raise ConfigError(f"{label} must be a non-empty string")
    return value


def _require_int(value: object, label: str, minimum: int, maximum: int) -> int:
    if type(value) is not int or not minimum <= value <= maximum:
        raise ConfigError(f"{label} must be an integer in [{minimum}, {maximum}]")
    return value


def _require_float(value: object, label: str, minimum: float, maximum: float) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ConfigError(f"{label} must be a finite number in [{minimum}, {maximum}]")
    result = float(value)
    if not math.isfinite(result) or not minimum <= result <= maximum:
        raise ConfigError(f"{label} must be a finite number in [{minimum}, {maximum}]")
    return result


def _safe_relative(value: object, label: str, *, allow_dot: bool = False) -> str:
    if not isinstance(value, str) or not value or "\x00" in value:
        raise ConfigError(f"{label} must be a non-empty relative path")
    normalized = value.replace("\\", "/")
    if allow_dot and normalized == ".":
        return "."
    path = PurePosixPath(normalized)
    if path.is_absolute() or not path.parts or any(part in {"", ".", ".."} for part in path.parts) or ":" in path.parts[0]:
        raise ConfigError(f"{label} must be a safe relative path")
    return path.as_posix()


def _assert_no_symlink_components(path: Path, label: str = "path") -> None:
    absolute = Path(os.path.abspath(path))
    current = Path(absolute.anchor)
    for part in absolute.parts[1:]:
        current /= part
        try:
            info = current.lstat()
        except FileNotFoundError:
            break
        except OSError as exc:
            raise Stage2Error(f"cannot inspect {label}: {current}") from exc
        if stat.S_ISLNK(info.st_mode):
            raise Stage2Error(f"{label} uses a symlink: {current}")


def _external_directory(value: Path, *, create: bool, label: str) -> Path:
    candidate = Path(value).expanduser()
    _assert_no_symlink_components(candidate, label)
    absolute = Path(os.path.abspath(candidate))
    repository = REPO_ROOT.resolve()
    if absolute == repository or repository in absolute.parents or absolute in repository.parents:
        raise Stage2Error(f"{label} must be outside the repository and its ancestors")
    if create:
        try:
            absolute.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            raise Stage2Error(f"cannot create {label}: {absolute}") from exc
    if absolute.is_symlink() or not absolute.is_dir():
        raise Stage2Error(f"{label} is missing or not a directory: {absolute}")
    try:
        resolved = absolute.resolve(strict=True)
    except OSError as exc:
        raise Stage2Error(f"cannot resolve {label}: {absolute}") from exc
    if resolved != absolute:
        raise Stage2Error(f"{label} must not resolve through a symlink")
    return absolute


def _relative_file(root: Path, value: str, label: str) -> tuple[Path, str]:
    path = PurePosixPath(value)
    if path.is_absolute() or not path.parts or any(part in {"", ".", ".."} for part in path.parts):
        raise Stage2Error(f"{label} is not a safe relative path")
    candidate = root.joinpath(*path.parts)
    _assert_no_symlink_components(candidate, label)
    resolved = candidate.resolve(strict=False)
    if resolved != candidate:
        raise Stage2Error(f"{label} escapes its root")
    try:
        resolved.relative_to(root)
    except ValueError as exc:
        raise Stage2Error(f"{label} is outside its root") from exc
    return candidate, path.as_posix()


@dataclass(frozen=True)
class Stage2Config:
    source_path: Path
    source_sha256: str
    seed: int
    input_size: tuple[int, int]
    manifest_relative: str
    receipt_relative: str
    image_root_relative: str
    stage1_artifact_relative: str
    stage1_receipt_relative: str
    epochs: int
    batch_size: int
    learning_rate: float
    weight_decay: float
    max_records: int
    focal_gamma: float
    focal_alpha: float
    loss_weights: Mapping[str, float]
    model_manifest_relative: str
    model_manifest_sha256: str
    candidate: str

    @classmethod
    def load(cls, path: Path) -> "Stage2Config":
        try:
            source = path.expanduser().resolve(strict=True)
        except OSError as exc:
            raise ConfigError(f"cannot resolve config: {path}") from exc
        source_sha256 = _sha256_file(source, "config")
        raw = _read_json(source, "config")
        top = _require_keys(raw, EXPECTED_CONFIG_KEYS, "config")
        if top["schema_id"] != CONFIG_SCHEMA_ID or top["schema_version"] != CONFIG_SCHEMA_VERSION:
            raise ConfigError("config schema/version is unsupported")
        seed = _require_int(top["seed"], "seed", 0, 2**63 - 1)
        input_size = top["input_size"]
        if not isinstance(input_size, list) or len(input_size) != 2 or any(type(v) is not int or v < 1 for v in input_size):
            raise ConfigError("input_size must be [height, width]")
        if tuple(input_size) != (320, 320):
            raise ConfigError("Stage-2 requires the frozen 320x320 input contract")
        data = _require_keys(top["data"], EXPECTED_DATA_KEYS, "data")
        stage1 = _require_keys(top["stage1"], EXPECTED_STAGE1_KEYS, "stage1")
        training = _require_keys(top["training"], EXPECTED_TRAINING_KEYS, "training")
        model = _require_keys(top["model"], EXPECTED_MODEL_KEYS, "model")
        weights = _require_keys(training["loss_weights"], EXPECTED_WEIGHT_KEYS, "training.loss_weights")
        parsed_weights = {
            name: _require_float(weights[name], f"training.loss_weights.{name}", 0.0, 100.0)
            for name in TRAINABLE_HEADS
        }
        if not any(value > 0.0 for value in parsed_weights.values()):
            raise ConfigError("at least one Stage-2 head loss weight must be positive")
        return cls(
            source_path=source,
            source_sha256=source_sha256,
            seed=seed,
            input_size=(320, 320),
            manifest_relative=_safe_relative(data["manifest"], "data.manifest"),
            receipt_relative=_safe_relative(data["receipt"], "data.receipt"),
            image_root_relative=_safe_relative(data["image_root"], "data.image_root", allow_dot=True),
            stage1_artifact_relative=_safe_relative(stage1["artifact"], "stage1.artifact"),
            stage1_receipt_relative=_safe_relative(stage1["receipt"], "stage1.receipt"),
            epochs=_require_int(training["epochs"], "training.epochs", 1, 1000),
            batch_size=_require_int(training["batch_size"], "training.batch_size", 2, 512),
            learning_rate=_require_float(training["learning_rate"], "training.learning_rate", 1e-9, 1.0),
            weight_decay=_require_float(training["weight_decay"], "training.weight_decay", 0.0, 1.0),
            max_records=_require_int(training["max_records"], "training.max_records", 0, 10_000_000),
            focal_gamma=_require_float(training["focal_gamma"], "training.focal_gamma", 0.0, 100.0),
            focal_alpha=_require_float(training["focal_alpha"], "training.focal_alpha", 0.0, 1.0),
            loss_weights=MappingProxyType(parsed_weights),
            model_manifest_relative=_safe_relative(model["manifest_path"], "model.manifest_path"),
            model_manifest_sha256=_valid_sha(model["manifest_sha256"], "model.manifest_sha256"),
            candidate=_require_string(model["candidate"], "model.candidate"),
        )


@dataclass(frozen=True)
class PairRecord:
    pair_id: str
    derivative_path: Path
    derivative_relative: str
    derivative_sha256: str
    derivative_width: int
    derivative_height: int
    derivative_roi: tuple[float, float, float, float] | None
    issue_values: tuple[int, ...]
    issue_mask: tuple[int, ...]
    action_values: tuple[int, ...]
    action_mask: tuple[int, ...]
    delta_values: tuple[float, ...]
    delta_mask: tuple[int, ...]
    root_index: int = 0
    source_family_id: str = ""


@dataclass(frozen=True)
class PairRootAdmission:
    root_index: int
    root: Path
    image_root: Path
    manifest_path: Path
    receipt_path: Path
    manifest_sha256: str
    receipt_sha256: str
    expected_receipt_sha256: str
    full_record_count: int
    records: tuple[PairRecord, ...]
    pair_receipt: Mapping[str, Any]
    media_aggregate_sha256: str
    provenance: Mapping[str, Any]


@dataclass(frozen=True)
class DataAdmission:
    roots: tuple[PairRootAdmission, ...]
    records: tuple[PairRecord, ...]
    full_record_count: int
    manifest_sha256: str | None
    receipt_sha256: str | None
    manifest_sha256_by_root: tuple[str, ...]
    receipt_sha256_by_root: tuple[str, ...]
    data_hash: str
    pair_receipts: tuple[Mapping[str, Any], ...]
    media_aggregate_sha256: str
    media_aggregate_sha256_by_root: tuple[str, ...]


@dataclass(frozen=True)
class Stage1Binding:
    artifact_path: Path
    receipt_path: Path
    artifact_sha256: str
    receipt_sha256: str
    receipt_contract_sha256: str
    state_dict: Mapping[str, Tensor]


def _finite_number(value: object, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)):
        raise Stage2Error(f"{label} must be finite")
    return float(value)


def _sha_in_mapping(value: object, label: str) -> str:
    return _valid_sha(value, label)


def _nonnegative_int(value: object, label: str) -> int:
    if type(value) is not int or value < 0:
        raise Stage2Error(f"{label} must be a non-negative integer")
    return value


def _exact_mapping(value: object, keys: set[str], label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping) or set(value) != keys:
        raise Stage2Error(f"{label} schema drifted")
    return value


def _validate_roi(value: object, label: str) -> tuple[float, float, float, float] | None:
    if value is None:
        return None
    if not isinstance(value, list) or len(value) != 4:
        raise Stage2Error(f"{label} must be null or a four-element array")
    result = tuple(_finite_number(item, label) for item in value)
    if any(item < 0.0 or item > 1.0 for item in result):
        raise Stage2Error(f"{label} must remain in [0, 1]")
    x, y, width, height = result
    if width <= 0.0 or height <= 0.0 or x + width > 1.0 or y + height > 1.0:
        raise Stage2Error(f"{label} is not a valid normalized rectangle")
    return result


def _validate_vector(node: object, *, label: str, names: Sequence[str], continuous: bool) -> tuple[tuple[Any, ...], tuple[int, ...]]:
    if not isinstance(node, dict) or set(node) != {"ordered_names", "values", "mask"}:
        raise Stage2Error(f"{label} target schema drifted")
    if node["ordered_names"] != list(names):
        raise Stage2Error(f"{label}.ordered_names disagree with the frozen contract")
    values = node["values"]
    masks = node["mask"]
    if not isinstance(values, list) or not isinstance(masks, list) or len(values) != len(names) or len(masks) != len(names):
        raise Stage2Error(f"{label} target length disagrees with the frozen contract")
    if any(type(mask) is not int or mask not in {0, 1} for mask in masks):
        raise Stage2Error(f"{label}.mask must contain only integer 0/1 values")
    if continuous:
        parsed_values = tuple(_finite_number(value, f"{label}.values") for value in values)
        if any(value < -1.0 or value > 1.0 for value in parsed_values):
            raise Stage2Error(f"{label}.values must remain in [-1, 1]")
    else:
        if any(type(value) is not int or value not in {0, 1} for value in values):
            raise Stage2Error(f"{label}.values must contain only integer 0/1 values")
        parsed_values = tuple(values)
    return parsed_values, tuple(masks)


def _validate_pair_row(
    row: Mapping[str, Any],
    *,
    line_number: int,
    root_index: int,
    contract: SETCompositionNetManifest,
    image_root: Path,
    expected_semantics_sha256: str,
    expected_geometry_sha256: str,
    expected_geometry_schema_sha256: str,
    seen_pair_ids: set[str],
    seen_derivative_paths: set[str],
) -> PairRecord:
    actual_keys = set(row)
    if not actual_keys.issubset(PAIR_TOP_KEYS | PAIR_TOP_OPTIONAL_KEYS) or not PAIR_TOP_KEYS.issubset(actual_keys):
        raise Stage2Error(f"pair line {line_number} keys drifted")
    if row.get("schema_id") != PAIR_SCHEMA_ID or row.get("schema_version") != PAIR_SCHEMA_VERSION:
        raise Stage2Error(f"pair line {line_number} schema identity is unsupported")
    if row.get("split") != "research_fit" or row.get("is_independent") is not False or row.get("counts_toward_quota") is not False:
        raise Stage2Error(f"pair line {line_number} is not the research_fit non-independent split")
    if row.get("research_only") is not True or row.get("human_gold") is not False or row.get("release_admissible") is not False:
        raise Stage2Error(f"pair line {line_number} crosses the research/silver boundary")
    pair_id = row.get("pair_id")
    if not isinstance(pair_id, str) or PAIR_ID_RE.fullmatch(pair_id) is None or pair_id in seen_pair_ids:
        raise Stage2Error(f"pair line {line_number} has an unsafe or duplicate pair_id")
    for field in ("source_family_id", "derivation_family_id"):
        value = row.get(field)
        if not isinstance(value, str) or FAMILY_ID_RE.fullmatch(value) is None:
            raise Stage2Error(f"pair line {line_number}.{field} is malformed")
    if "issue_projection" in row and row["issue_projection"] != "object_edge_pressure_to_subject_too_close_to_edge_silver":
        raise Stage2Error(f"pair line {line_number}.issue_projection is unsupported")
    source = row.get("source")
    if not isinstance(source, dict) or set(source) != {"source_id", "source_record_id", "relative_path", "sha256", "width", "height", "format"}:
        raise Stage2Error(f"pair line {line_number}.source schema drifted")
    if not isinstance(source["source_id"], str) or not source["source_id"] or any(c in "\\/\x00\r\n" for c in source["source_id"]):
        raise Stage2Error(f"pair line {line_number}.source.source_id is unsafe")
    if not isinstance(source["source_record_id"], str) or not source["source_record_id"] or any(c in "\\/\x00\r\n" for c in source["source_record_id"]):
        raise Stage2Error(f"pair line {line_number}.source.source_record_id is unsafe")
    source_relative = source["relative_path"]
    if not isinstance(source_relative, str) or not source_relative or "\x00" in source_relative:
        raise Stage2Error(f"pair line {line_number}.source.relative_path is malformed")
    source_path_parts = PurePosixPath(source_relative.replace("\\", "/"))
    if source_path_parts.is_absolute() or not source_path_parts.parts or any(part in {"", ".", ".."} for part in source_path_parts.parts):
        raise Stage2Error(f"pair line {line_number}.source.relative_path is unsafe")
    _sha_in_mapping(source["sha256"], f"pair line {line_number}.source.sha256")
    if type(source["width"]) is not int or source["width"] < 1 or type(source["height"]) is not int or source["height"] < 1:
        raise Stage2Error(f"pair line {line_number}.source dimensions are invalid")
    if not isinstance(source["format"], str) or not source["format"]:
        raise Stage2Error(f"pair line {line_number}.source.format is invalid")
    derivative = row.get("derivative")
    if not isinstance(derivative, dict) or set(derivative) != {"relative_path", "sha256", "width", "height", "format"}:
        raise Stage2Error(f"pair line {line_number}.derivative schema drifted")
    derivative_relative = derivative.get("relative_path")
    if not isinstance(derivative_relative, str) or DERIVATIVE_RE.fullmatch(derivative_relative) is None:
        raise Stage2Error(f"pair line {line_number}.derivative.relative_path is unsafe")
    if derivative_relative in seen_derivative_paths:
        raise Stage2Error(f"pair line {line_number} has a duplicate derivative path")
    derivative_sha256 = _sha_in_mapping(derivative.get("sha256"), f"pair line {line_number}.derivative.sha256")
    width = derivative.get("width")
    height = derivative.get("height")
    if type(width) is not int or type(height) is not int or width < 1 or height < 1 or width > 4096 or height > 4096 or width * height > 4096 * 4096:
        raise Stage2Error(f"pair line {line_number}.derivative dimensions are unsafe")
    if derivative.get("format") != "png":
        raise Stage2Error(f"pair line {line_number}.derivative format is not png")
    derivative_path, normalized_derivative = _relative_file(image_root, derivative_relative, f"pair line {line_number}.derivative")
    if normalized_derivative != derivative_relative:
        raise Stage2Error(f"pair line {line_number}.derivative path is not canonical")
    recipe = row.get("recipe")
    if not isinstance(recipe, dict) or set(recipe) != {"name", "version", "parameters"} or recipe.get("version") != "camera-corruption-v1" or not isinstance(recipe.get("parameters"), dict):
        raise Stage2Error(f"pair line {line_number}.recipe schema drifted")
    if recipe.get("name") not in {"rotate_horizon", "crop_translate", "crop_zoom_in"}:
        raise Stage2Error(f"pair line {line_number}.recipe.name is unsupported")
    roi = row.get("roi")
    if not isinstance(roi, dict) or set(roi) != {"coordinate_space", "transform", "source_xywh", "derivative_xywh"} or roi.get("coordinate_space") != "oriented_full_frame_top_left_normalized" or roi.get("transform") != "analytic":
        raise Stage2Error(f"pair line {line_number}.roi schema drifted")
    _validate_roi(roi.get("source_xywh"), f"pair line {line_number}.roi.source_xywh")
    derivative_roi = _validate_roi(roi.get("derivative_xywh"), f"pair line {line_number}.roi.derivative_xywh")
    geometry = row.get("geometry")
    if not isinstance(geometry, dict) or set(geometry) != {"provider", "runtime", "sha256", "schema_id", "schema_version", "schema_sha256", "source_record_id"}:
        raise Stage2Error(f"pair line {line_number}.geometry schema drifted")
    if geometry.get("provider") != "silver_apple_vision" or geometry.get("runtime") != "conditional_on_captured_apple_os_vision_runtime" or geometry.get("schema_id") != "camera-silver-geometry-v1" or geometry.get("schema_version") != "1.0.0":
        raise Stage2Error(f"pair line {line_number}.geometry authority is unsupported")
    if _sha_in_mapping(geometry.get("sha256"), f"pair line {line_number}.geometry.sha256") != expected_geometry_sha256:
        raise Stage2Error(f"pair line {line_number}.geometry.sha256 disagrees with the pair receipt")
    if _sha_in_mapping(geometry.get("schema_sha256"), f"pair line {line_number}.geometry.schema_sha256") != expected_geometry_schema_sha256:
        raise Stage2Error(f"pair line {line_number}.geometry.schema_sha256 disagrees with the pair receipt")
    if geometry.get("source_record_id") != source["source_record_id"]:
        raise Stage2Error(f"pair line {line_number}.geometry/source linkage disagrees")
    targets = row.get("targets")
    if not isinstance(targets, dict) or set(targets) != PAIR_TARGET_KEYS:
        raise Stage2Error(f"pair line {line_number}.targets schema drifted")
    issue_values, issue_mask = _validate_vector(targets["issue"], label=f"pair line {line_number}.targets.issue", names=contract.output_head_specs["issue_logits"]["ordered_names"], continuous=False)
    action_values, action_mask = _validate_vector(targets["action"], label=f"pair line {line_number}.targets.action", names=contract.output_head_specs["action_utility_logits"]["ordered_names"], continuous=False)
    delta_values, delta_mask = _validate_vector(targets["continuous"], label=f"pair line {line_number}.targets.continuous", names=contract.output_head_specs["continuous_target_deltas"]["ordered_names"], continuous=True)
    if not any(issue_mask) and not any(action_mask) and not any(delta_mask):
        raise Stage2Error(f"pair line {line_number} has no known target labels")
    if _sha_in_mapping(row.get("semantics_sha256"), f"pair line {line_number}.semantics_sha256") != expected_semantics_sha256:
        raise Stage2Error(f"pair line {line_number}.semantics_sha256 disagrees with the pair receipt")
    seen_pair_ids.add(pair_id)
    seen_derivative_paths.add(normalized_derivative)
    return PairRecord(
        pair_id, derivative_path, normalized_derivative, derivative_sha256, width, height, derivative_roi,
        issue_values, issue_mask, action_values, action_mask, delta_values, delta_mask,
        root_index, source_family_id=row["source_family_id"],
    )


def _aggregate_media_hash(records: Sequence[PairRecord], *, include_root: bool = False) -> str:
    payload = "".join(
        f"{(str(record.root_index) + chr(0)) if include_root else ''}{record.derivative_relative}\0{record.derivative_sha256}\0{record.derivative_width}\0{record.derivative_height}\n"
        for record in sorted(records, key=lambda item: (item.root_index, item.derivative_relative) if include_root else (item.derivative_relative,))
    ).encode("utf-8")
    return _sha256_bytes(payload)


def _validate_geometry_environment(value: object) -> Mapping[str, Any]:
    environment = _exact_mapping(value, GEOMETRY_ENVIRONMENT_KEYS, "pair receipt geometry environment")
    if not isinstance(environment["os_version"], str) or not environment["os_version"] or environment["platform"] != "macOS":
        raise Stage2Error("pair receipt geometry environment identity is invalid")
    components = _exact_mapping(environment["os_version_components"], {"major", "minor", "patch"}, "pair receipt geometry OS version")
    for key, component in components.items():
        _nonnegative_int(component, f"pair receipt geometry OS version.{key}")
    framework = _exact_mapping(environment["vision_framework"], {"bundle_identifier", "name", "version"}, "pair receipt Vision framework")
    if framework["bundle_identifier"] != "com.apple.Vision" or framework["name"] != "Vision" or not isinstance(framework["version"], str) or not framework["version"]:
        raise Stage2Error("pair receipt Vision framework identity is invalid")
    if environment["vision_request_family"] != list(VISION_REQUEST_FAMILY):
        raise Stage2Error("pair receipt Vision request family is not the frozen extractor set")
    revisions = _exact_mapping(environment["vision_request_revisions"], set(VISION_REQUEST_FAMILY), "pair receipt Vision request revisions")
    for request, revision in revisions.items():
        if type(revision) is not int or revision < 1:
            raise Stage2Error(f"pair receipt Vision request revision is invalid: {request}")
    return environment


def _validate_pair_receipt(
    receipt: Mapping[str, Any],
    *,
    manifest_relative: str,
    manifest_sha256: str,
    manifest_records: int,
    contract: SETCompositionNetManifest,
    contract_sha256: str,
    pair_schema_sha256: str,
) -> Mapping[str, Any]:
    if set(receipt) != PAIR_RECEIPT_KEYS:
        raise Stage2Error("pair receipt keys drifted")
    if receipt.get("schema_id") != PAIR_RECEIPT_SCHEMA_ID or receipt.get("schema_version") != PAIR_SCHEMA_VERSION:
        raise Stage2Error("pair receipt schema/version is unsupported")
    if receipt.get("research_only") is not True or receipt.get("human_gold") is not False or receipt.get("release_admissible") is not False or receipt.get("split") != "research_fit":
        raise Stage2Error("pair receipt is not the research-only research_fit receipt")
    _nonnegative_int(receipt.get("seed"), "pair receipt seed")
    max_per_source = receipt.get("max_per_source")
    if max_per_source is not None and (type(max_per_source) is not int or max_per_source < 1):
        raise Stage2Error("pair receipt max_per_source is invalid")
    output = _exact_mapping(receipt.get("output_manifest"), {"path", "records", "sha256"}, "pair receipt output_manifest")
    if output["path"] != manifest_relative or output["sha256"] != manifest_sha256 or output["records"] != manifest_records:
        raise Stage2Error("pair receipt does not attest the supplied manifest")
    _valid_sha(output["sha256"], "pair receipt output_manifest.sha256")
    media = _exact_mapping(receipt.get("output_media"), {"files", "aggregate_sha256"}, "pair receipt output_media")
    if media["files"] != manifest_records:
        raise Stage2Error("pair receipt media file count does not attest the supplied manifest")
    _valid_sha(media["aggregate_sha256"], "pair receipt output_media.aggregate_sha256")

    generator_source = _exact_mapping(receipt.get("generator_source"), {"path", "sha256"}, "pair receipt generator_source")
    if generator_source["path"] != GENERATOR_SOURCE_RELATIVE or _valid_sha(generator_source["sha256"], "pair receipt generator_source.sha256") != _sha256_file(REPO_ROOT / GENERATOR_SOURCE_RELATIVE, "generator source"):
        raise Stage2Error("pair receipt generator_source does not bind the tracked generator")

    contract_node = _exact_mapping(receipt.get("contract"), {"path", "sha256"}, "pair receipt contract")
    if contract_node["path"] != MODEL_MANIFEST_RELATIVE or contract_node["sha256"] != contract_sha256:
        raise Stage2Error("pair receipt contract binding disagrees with the frozen contract")
    schema_node = _exact_mapping(receipt.get("pair_schema"), {"path", "sha256"}, "pair receipt pair_schema")
    if schema_node["path"] != PAIR_SCHEMA_RELATIVE or schema_node["sha256"] != pair_schema_sha256:
        raise Stage2Error("pair receipt pair-schema binding disagrees with the tracked schema")
    semantics = receipt.get("semantics")
    semantics_sha256 = _sha_in_mapping(receipt.get("semantics_sha256"), "pair receipt semantics_sha256")
    if not isinstance(semantics, Mapping):
        raise Stage2Error("pair receipt semantics are missing")
    schema = _read_json(REPO_ROOT / PAIR_SCHEMA_RELATIVE, "silver action-pair schema")
    if semantics != schema.get("x-semantics") or semantics_sha256 != schema.get("x-semantics-sha256"):
        raise Stage2Error("pair receipt semantics are not the frozen action-pair semantics")

    inputs = _exact_mapping(receipt.get("inputs"), {"inventory", "geometry"}, "pair receipt inputs")
    inventory = _exact_mapping(inputs["inventory"], {"sha256", "records"}, "pair receipt inventory input")
    _valid_sha(inventory["sha256"], "pair receipt inventory.sha256")
    inventory_records = _nonnegative_int(inventory["records"], "pair receipt inventory.records")
    geometry_input = _exact_mapping(inputs["geometry"], GEOMETRY_INPUT_KEYS, "pair receipt geometry input")
    geometry_sha256 = _valid_sha(geometry_input["sha256"], "pair receipt geometry.sha256")
    geometry_schema_sha256 = _valid_sha(geometry_input["schema_sha256"], "pair receipt geometry.schema_sha256")
    geometry_records = _nonnegative_int(geometry_input["records"], "pair receipt geometry.records")
    if geometry_input["receipt_path"] != "receipt.json":
        raise Stage2Error("pair receipt geometry receipt path is not the extractor sibling receipt")
    geometry_receipt_sha256 = _valid_sha(geometry_input["receipt_sha256"], "pair receipt geometry.receipt_sha256")
    geometry_schema = _read_json(REPO_ROOT / GEOMETRY_SCHEMA_RELATIVE, "silver geometry schema")
    if not isinstance(geometry_schema, Mapping) or geometry_schema.get("$id") != "https://set-os.local/datasets/camera-coach/v1/silver-geometry-schema.json":
        raise Stage2Error("tracked silver geometry schema identity is unsupported")
    properties = geometry_schema.get("properties")
    schema_id_node = properties.get("schema_id") if isinstance(properties, Mapping) else None
    schema_version_node = properties.get("schema_version") if isinstance(properties, Mapping) else None
    if not isinstance(schema_id_node, Mapping) or not isinstance(schema_version_node, Mapping) or schema_id_node.get("const") != "camera-silver-geometry-v1" or schema_version_node.get("const") != "1.0.0":
        raise Stage2Error("tracked silver geometry schema version is unsupported")
    if _sha256_file(REPO_ROOT / GEOMETRY_SCHEMA_RELATIVE, "silver geometry schema") != geometry_schema_sha256:
        raise Stage2Error("pair receipt geometry.schema_sha256 does not bind the tracked geometry schema")

    geometry_receipt = _exact_mapping(receipt.get("geometry_receipt"), GEOMETRY_RECEIPT_BINDING_KEYS, "pair receipt geometry_receipt")
    if geometry_receipt["path"] != "receipt.json" or geometry_receipt["schema_id"] != GEOMETRY_RECEIPT_SCHEMA_ID or geometry_receipt["schema_version"] != "1.0.0" or geometry_receipt["determinism"] != GEOMETRY_DETERMINISM or geometry_receipt["sha256"] != geometry_receipt_sha256:
        raise Stage2Error("pair receipt geometry_receipt does not bind the extractor receipt")
    _valid_sha(geometry_receipt["sha256"], "pair receipt geometry_receipt.sha256")
    _validate_geometry_environment(geometry_receipt["environment"])
    tool_source = _exact_mapping(geometry_receipt["tool_source"], {"path", "sha256"}, "pair receipt geometry tool_source")
    if tool_source["path"] != GEOMETRY_TOOL_RELATIVE or _valid_sha(tool_source["sha256"], "pair receipt geometry tool_source.sha256") != _sha256_file(REPO_ROOT / GEOMETRY_TOOL_RELATIVE, "geometry extractor source"):
        raise Stage2Error("pair receipt geometry tool source does not bind the tracked extractor")

    counts = _exact_mapping(receipt.get("counts"), {"sources", "geometry_records", "pairs", "by_recipe", "by_action", "skip_reasons"}, "pair receipt counts")
    if _nonnegative_int(counts["sources"], "pair receipt counts.sources") != inventory_records or _nonnegative_int(counts["geometry_records"], "pair receipt counts.geometry_records") != geometry_records or _nonnegative_int(counts["pairs"], "pair receipt counts.pairs") != manifest_records:
        raise Stage2Error("pair receipt counts do not attest the supplied inputs")
    by_recipe = counts["by_recipe"]
    if not isinstance(by_recipe, Mapping) or any(key not in {"rotate_horizon", "crop_translate", "crop_zoom_in"} or _nonnegative_int(value, f"pair receipt counts.by_recipe.{key}") < 0 for key, value in by_recipe.items()) or sum(by_recipe.values()) != manifest_records:
        raise Stage2Error("pair receipt counts.by_recipe do not attest the manifest")
    by_action = counts["by_action"]
    if not isinstance(by_action, Mapping) or any(key not in contract.output_head_specs["action_utility_logits"]["ordered_names"] or _nonnegative_int(value, f"pair receipt counts.by_action.{key}") < 0 for key, value in by_action.items()) or sum(by_action.values()) > manifest_records:
        raise Stage2Error("pair receipt counts.by_action are malformed")
    skip_reasons = counts["skip_reasons"]
    if not isinstance(skip_reasons, Mapping) or any(not isinstance(key, str) or _nonnegative_int(value, f"pair receipt counts.skip_reasons.{key}") < 0 for key, value in skip_reasons.items()):
        raise Stage2Error("pair receipt counts.skip_reasons are malformed")
    return receipt


def _load_contract(config: Stage2Config) -> tuple[SETCompositionNetManifest, str, str]:
    path = REPO_ROOT / config.model_manifest_relative
    actual_sha256 = _sha256_file(path, "model contract")
    if actual_sha256 != config.model_manifest_sha256:
        raise Stage2Error("model contract hash does not match the Stage-2 config")
    if config.model_manifest_relative != MODEL_MANIFEST_RELATIVE or config.candidate != CandidateA.candidate_id:
        raise Stage2Error("Stage-2 is fixed to CandidateA and the tracked contract")
    contract = SETCompositionNetManifest.load(path)
    if contract.raw.get("contract_version") != "setcompositionnet.v1":
        raise Stage2Error("unexpected SETCompositionNet contract version")
    model_source_hash = _sha256_file(REPO_ROOT / MODEL_SOURCE_RELATIVE, "model source")
    return contract, actual_sha256, model_source_hash


def _normalize_data_roots(value: Path | Sequence[Path]) -> tuple[Path, ...]:
    try:
        if isinstance(value, (str, Path)):
            values: tuple[Path, ...] = (Path(value),)
        elif isinstance(value, Sequence) and not isinstance(value, (bytes, bytearray)):
            values = tuple(Path(item) for item in value)
        else:
            raise Stage2Error("pair data roots must be one or more paths")
    except (TypeError, ValueError) as exc:
        raise Stage2Error("pair data roots must be paths") from exc
    if not values:
        raise Stage2Error("at least one pair data root is required")
    roots = tuple(_external_directory(item, create=False, label="pair data root") for item in values)
    if len(set(roots)) != len(roots):
        raise Stage2Error("pair data roots must be unique")
    return roots


def _normalize_receipt_hashes(value: Sequence[str] | None, root_count: int) -> tuple[str, ...]:
    if value is None or isinstance(value, (str, bytes, bytearray)):
        raise Stage2Error("one expected receipt SHA-256 must be declared for every pair root")
    hashes = tuple(value)
    if len(hashes) != root_count:
        raise Stage2Error(f"expected {root_count} pair receipt SHA-256 values, got {len(hashes)}")
    return tuple(_valid_sha(item, f"pair root {index} expected receipt SHA-256") for index, item in enumerate(hashes))


def admit_data(
    data_root_value: Path | Sequence[Path],
    config: Stage2Config,
    contract: SETCompositionNetManifest,
    contract_sha256: str,
    *,
    receipt_sha256s: Sequence[str] | None = None,
) -> DataAdmission:
    data_roots = _normalize_data_roots(data_root_value)
    declared_receipts = _normalize_receipt_hashes(receipt_sha256s, len(data_roots))
    root_specs = tuple(sorted(zip(data_roots, declared_receipts), key=lambda item: str(item[0])))
    pair_schema_path = REPO_ROOT / PAIR_SCHEMA_RELATIVE
    pair_schema_sha256 = _sha256_file(pair_schema_path, "pair schema")
    root_admissions: list[PairRootAdmission] = []
    all_full_records: list[PairRecord] = []
    for root_index, (data_root, expected_receipt_sha256) in enumerate(root_specs):
        manifest_path, manifest_relative = _relative_file(data_root, config.manifest_relative, "pair manifest")
        receipt_path, receipt_relative = _relative_file(data_root, config.receipt_relative, "pair receipt")
        image_root_path, _ = _relative_file(data_root, config.image_root_relative, "pair image root") if config.image_root_relative != "." else (data_root, ".")
        if manifest_relative != config.manifest_relative or receipt_relative != config.receipt_relative:
            raise Stage2Error("pair data paths did not remain canonical")
        manifest_sha256 = _sha256_file(manifest_path, "pair manifest")
        rows, manifest_bytes = _read_jsonl(manifest_path, "pair manifest")
        if _sha256_bytes(manifest_bytes) != manifest_sha256:
            raise Stage2Error("pair manifest changed while it was read")
        receipt_sha256 = _sha256_file(receipt_path, "pair receipt")
        if receipt_sha256 != expected_receipt_sha256:
            raise Stage2Error(f"pair root {root_index} receipt SHA-256 does not match the declared value")
        receipt_raw = _read_json(receipt_path, "pair receipt")
        if not isinstance(receipt_raw, Mapping):
            raise Stage2Error("pair receipt must be an object")
        receipt = _validate_pair_receipt(
            receipt_raw,
            manifest_relative=config.manifest_relative,
            manifest_sha256=manifest_sha256,
            manifest_records=len(rows),
            contract=contract,
            contract_sha256=contract_sha256,
            pair_schema_sha256=pair_schema_sha256,
        )
        inputs = receipt["inputs"]
        geometry_input = inputs["geometry"]
        expected_geometry_sha256 = _valid_sha(geometry_input["sha256"], "pair receipt geometry.sha256")
        expected_geometry_schema_sha256 = _valid_sha(geometry_input["schema_sha256"], "pair receipt geometry.schema_sha256")
        expected_semantics_sha256 = _valid_sha(receipt["semantics_sha256"], "pair receipt semantics_sha256")
        seen_pair_ids: set[str] = set()
        seen_derivative_paths: set[str] = set()
        full_records = [
            _validate_pair_row(
                row,
                line_number=line_number,
                root_index=root_index,
                contract=contract,
                image_root=image_root_path,
                expected_semantics_sha256=expected_semantics_sha256,
                expected_geometry_sha256=expected_geometry_sha256,
                expected_geometry_schema_sha256=expected_geometry_schema_sha256,
                seen_pair_ids=seen_pair_ids,
                seen_derivative_paths=seen_derivative_paths,
            )
            for line_number, row in enumerate(rows, 1)
        ]
        full_records.sort(key=lambda item: item.pair_id)
        selected_records = full_records[:config.max_records] if config.max_records else full_records
        if not selected_records:
            raise Stage2Error("an admitted pair root must contain at least one fit record")
        for record in selected_records:
            _assert_no_symlink_components(record.derivative_path, f"derivative {record.pair_id}")
            try:
                encoded = record.derivative_path.read_bytes()
            except OSError as exc:
                raise Stage2Error(f"cannot read derivative image {record.pair_id}") from exc
            if _sha256_bytes(encoded) != record.derivative_sha256:
                raise Stage2Error(f"derivative image hash mismatch for {record.pair_id}")
            try:
                with warnings.catch_warnings():
                    warnings.simplefilter("error", Image.DecompressionBombWarning)
                    with Image.open(BytesIO(encoded)) as opened:
                        opened.verify()
                    with Image.open(BytesIO(encoded)) as opened:
                        if getattr(opened, "n_frames", 1) != 1 or opened.format != "PNG" or (opened.width, opened.height) != (record.derivative_width, record.derivative_height):
                            raise Stage2Error(f"derivative image metadata mismatch for {record.pair_id}")
            except Stage2Error:
                raise
            except Exception as exc:  # noqa: BLE001 - decoder errors are admission failures.
                raise Stage2Error(f"cannot decode derivative image {record.pair_id}") from exc
        full_media_records = [_record_from_row_without_image(row, image_root_path, contract, root_index=root_index) for row in rows]
        if receipt["output_media"]["aggregate_sha256"] != _aggregate_media_hash(full_media_records):
            # Validate the full generator media ledger, including rows truncated
            # by max_records, without reading source/control images.
            raise Stage2Error("pair receipt media aggregate does not match manifest metadata")
        selected_media_sha256 = _aggregate_media_hash(selected_records)
        provenance = {
            "root_index": root_index,
            "data_root": str(data_root),
            "image_root": config.image_root_relative,
            "manifest": {"path": manifest_relative, "sha256": manifest_sha256, "records_full": len(full_records), "records_selected": len(selected_records)},
            "receipt": {"path": receipt_relative, "expected_sha256": expected_receipt_sha256, "sha256": receipt_sha256},
            "media": {"records_selected": len(selected_records), "aggregate_sha256": selected_media_sha256, "receipt_files": receipt["output_media"]["files"], "receipt_aggregate_sha256": receipt["output_media"]["aggregate_sha256"]},
            "generator_source": dict(receipt["generator_source"]),
            "inputs": json.loads(_canonical_json(receipt["inputs"])),
            "geometry_receipt": json.loads(_canonical_json(receipt["geometry_receipt"])),
            "pair_receipt": json.loads(_canonical_json(receipt)),
        }
        if _sha256_file(manifest_path, "pair manifest") != manifest_sha256 or _sha256_file(receipt_path, "pair receipt") != receipt_sha256:
            raise Stage2Error("pair inputs changed during admission")
        root_admissions.append(
            PairRootAdmission(
                root_index, data_root, image_root_path, manifest_path, receipt_path,
                manifest_sha256, receipt_sha256, expected_receipt_sha256, len(full_records),
                tuple(selected_records), receipt, selected_media_sha256, provenance,
            )
        )
        all_full_records.extend(full_records)

    seen_pair_ids: dict[str, int] = {}
    seen_source_families: dict[str, int] = {}
    seen_media_paths: dict[str, int] = {}
    for record in all_full_records:
        prior_root = seen_pair_ids.get(record.pair_id)
        if prior_root is not None:
            raise Stage2Error(f"duplicate pair_id across pair roots: {record.pair_id}")
        seen_pair_ids[record.pair_id] = record.root_index
        prior_root = seen_source_families.get(record.source_family_id)
        if prior_root is not None and prior_root != record.root_index:
            raise Stage2Error(f"source-family collision across pair roots: {record.source_family_id}")
        seen_source_families.setdefault(record.source_family_id, record.root_index)
        prior_root = seen_media_paths.get(record.derivative_relative)
        if prior_root is not None:
            raise Stage2Error(f"duplicate derivative media path across pair roots: {record.derivative_relative}")
        seen_media_paths[record.derivative_relative] = record.root_index
    records = tuple(sorted((record for root in root_admissions for record in root.records), key=lambda item: (item.pair_id, item.root_index, item.derivative_relative)))
    if len(records) < 2:
        raise Stage2Error("admitted silver-action pairs must contain at least two fit records across all roots")
    full_record_count = sum(root.full_record_count for root in root_admissions)
    manifest_hashes = tuple(root.manifest_sha256 for root in root_admissions)
    receipt_hashes = tuple(root.receipt_sha256 for root in root_admissions)
    media_hashes = tuple(root.media_aggregate_sha256 for root in root_admissions)
    global_media_sha256 = media_hashes[0] if len(media_hashes) == 1 else _aggregate_media_hash(records, include_root=True)
    root_hash_payload = [
        {
            "root_index": root.root_index,
            "data_root": str(root.root),
            "manifest_sha256": root.manifest_sha256,
            "receipt_sha256": root.receipt_sha256,
            "expected_receipt_sha256": root.expected_receipt_sha256,
            "records_full": root.full_record_count,
            "records_selected": len(root.records),
            "media_aggregate_sha256": root.media_aggregate_sha256,
        }
        for root in root_admissions
    ]
    data_hash = _sha256_bytes(_canonical_json({"roots": root_hash_payload, "records_full": full_record_count, "records_selected": len(records), "media_aggregate_sha256": global_media_sha256}).encode("utf-8"))
    return DataAdmission(
        tuple(root_admissions), records, full_record_count,
        manifest_hashes[0] if len(manifest_hashes) == 1 else None,
        receipt_hashes[0] if len(receipt_hashes) == 1 else None,
        manifest_hashes, receipt_hashes, data_hash,
        tuple(root.pair_receipt for root in root_admissions), global_media_sha256, media_hashes,
    )


def _record_from_row_without_image(row: Mapping[str, Any], image_root: Path, contract: SETCompositionNetManifest, *, root_index: int = 0) -> PairRecord:
    # The manifest's media ledger is metadata-only; source/control pixels are
    # deliberately never opened here.
    derivative = row["derivative"]
    relative = derivative["relative_path"]
    path, _ = _relative_file(image_root, relative, "derivative metadata")
    issue_values, issue_mask = _validate_vector(row["targets"]["issue"], label="manifest issue", names=contract.output_head_specs["issue_logits"]["ordered_names"], continuous=False)
    action_values, action_mask = _validate_vector(row["targets"]["action"], label="manifest action", names=contract.output_head_specs["action_utility_logits"]["ordered_names"], continuous=False)
    delta_values, delta_mask = _validate_vector(row["targets"]["continuous"], label="manifest continuous", names=contract.output_head_specs["continuous_target_deltas"]["ordered_names"], continuous=True)
    roi = _validate_roi(row["roi"]["derivative_xywh"], "manifest derivative ROI")
    return PairRecord(
        row["pair_id"], path, relative, derivative["sha256"], derivative["width"], derivative["height"], roi,
        issue_values, issue_mask, action_values, action_mask, delta_values, delta_mask,
        root_index, source_family_id=row["source_family_id"],
    )


def _load_pair_schema_sha256() -> str:
    path = REPO_ROOT / PAIR_SCHEMA_RELATIVE
    schema = _read_json(path, "silver action-pair schema")
    digest = _sha256_file(path, "pair schema")
    if not isinstance(schema, dict) or schema.get("$id", "") != "https://set-os.local/datasets/camera-coach/v1/silver-action-pair-schema.json":
        raise Stage2Error("silver action-pair schema identity is unsupported")
    return digest


def _load_stage1_binding(stage1_root_value: Path, config: Stage2Config, declared_sha256: str, contract: SETCompositionNetManifest, contract_sha256: str) -> Stage1Binding:
    declared = _valid_sha(declared_sha256, "declared Stage-1 encoder SHA-256")
    stage1_root = _external_directory(stage1_root_value, create=False, label="Stage-1 root")
    artifact_path, artifact_relative = _relative_file(stage1_root, config.stage1_artifact_relative, "Stage-1 encoder artifact")
    receipt_path, receipt_relative = _relative_file(stage1_root, config.stage1_receipt_relative, "Stage-1 receipt")
    if artifact_relative != config.stage1_artifact_relative or receipt_relative != config.stage1_receipt_relative:
        raise Stage2Error("Stage-1 paths did not remain canonical")
    artifact_sha256 = _sha256_file(artifact_path, "Stage-1 encoder artifact")
    receipt_sha256 = _sha256_file(receipt_path, "Stage-1 receipt")
    if artifact_sha256 != declared:
        raise Stage2Error("Stage-1 encoder artifact SHA-256 does not match the declared hash")
    receipt_raw = _read_json(receipt_path, "Stage-1 receipt")
    if not isinstance(receipt_raw, Mapping) or receipt_raw.get("schema_id") != STAGE1_RECEIPT_SCHEMA_ID or receipt_raw.get("schema_version") != "1.0.0" or receipt_raw.get("status") != "complete":
        raise Stage2Error("Stage-1 receipt is not a completed Stage-1 training receipt")
    if receipt_raw.get("research_only") is not True or receipt_raw.get("human_gold") is not False or receipt_raw.get("release_admissible") is not False:
        raise Stage2Error("Stage-1 receipt has crossed the research-only boundary")
    final_artifact = receipt_raw.get("final_artifact")
    if not isinstance(final_artifact, Mapping) or final_artifact.get("path") != config.stage1_artifact_relative or final_artifact.get("kind") != STAGE1_ENCODER_SCHEMA_ID or final_artifact.get("sha256") != declared:
        raise Stage2Error("Stage-1 receipt final_artifact does not bind the declared encoder hash/path")
    receipt_contract_sha256 = _valid_sha(receipt_raw.get("model_contract_sha256"), "Stage-1 receipt model_contract_sha256")
    if receipt_contract_sha256 != receipt_raw.get("model_contract_sha256"):
        raise Stage2Error("Stage-1 receipt model contract hash is malformed")
    model_contract = receipt_raw.get("model_contract")
    if not isinstance(model_contract, Mapping) or model_contract.get("candidate") != CandidateA.candidate_id or model_contract.get("backbone") != "full_frame_backbone" or model_contract.get("manifest_sha256") != contract_sha256:
        raise Stage2Error("Stage-1 receipt model binding is not CandidateA.full_frame_backbone")
    try:
        payload = torch.load(artifact_path, map_location="cpu", weights_only=True)
    except (OSError, RuntimeError, EOFError, ValueError, pickle.UnpicklingError) as exc:
        raise Stage2Error("cannot load Stage-1 encoder artifact with weights_only=True") from exc
    if not isinstance(payload, Mapping) or payload.get("schema_id") != STAGE1_ENCODER_SCHEMA_ID or payload.get("model_contract_sha256") != receipt_contract_sha256 or payload.get("candidate") != CandidateA.candidate_id or payload.get("backbone") != "full_frame_backbone":
        raise Stage2Error("Stage-1 encoder artifact metadata is not receipt-bound")
    if payload.get("contains_set_runtime_heads") is not False or payload.get("contains_eva_auxiliary_heads") is not False:
        raise Stage2Error("Stage-1 encoder artifact contains forbidden runtime/auxiliary heads")
    state_dict = payload.get("state_dict")
    if not isinstance(state_dict, Mapping) or not state_dict or any(str(key).startswith(("heads.", "fusion.", "auxiliary.")) for key in state_dict):
        raise Stage2Error("Stage-1 artifact state_dict is not encoder-only")
    # Loading into a fresh CandidateA verifies the architecture/key boundary
    # before any Stage-2 optimizer is created.
    try:
        encoder = CandidateA(contract).full_frame_backbone
        encoder.load_state_dict(state_dict, strict=True)
    except (KeyError, RuntimeError, TypeError, ValueError) as exc:
        raise Stage2Error("Stage-1 encoder state is incompatible with CandidateA") from exc
    return Stage1Binding(artifact_path, receipt_path, artifact_sha256, receipt_sha256, receipt_contract_sha256, MappingProxyType(dict(state_dict)))


def _atomic_bytes(path: Path, payload: bytes) -> str:
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise Stage2Error(f"output is not a regular file: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
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
    except (OSError, ValueError) as exc:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
        raise Stage2Error(f"cannot atomically write {path}") from exc
    return hashlib.sha256(payload).hexdigest()


def _atomic_json(path: Path, value: Mapping[str, Any]) -> str:
    return _atomic_bytes(path, (_canonical_json(value) + "\n").encode("utf-8"))


def _atomic_torch(path: Path, value: Mapping[str, Any]) -> str:
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise Stage2Error(f"checkpoint output is not a regular file: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary: Path | None = None
    try:
        fd, name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
        os.close(fd)
        temporary = Path(name)
        torch.save(value, temporary)
        with temporary.open("rb") as stream:
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    except (OSError, RuntimeError, ValueError) as exc:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
        raise Stage2Error(f"cannot atomically write torch artifact: {path}") from exc
    return _sha256_file(path, "Torch artifact")


def _resolve_device(value: str) -> torch.device:
    if value == "cpu":
        return torch.device("cpu")
    if value == "cuda":
        if not torch.cuda.is_available():
            raise Stage2Error("CUDA was requested but is unavailable")
        return torch.device("cuda")
    if value == "mps":
        if not getattr(torch.backends, "mps", None) or not torch.backends.mps.is_available():
            raise Stage2Error("MPS was requested but is unavailable")
        return torch.device("mps")
    if value != "auto":
        raise Stage2Error("device must be auto, cuda, mps, or cpu")
    if torch.cuda.is_available():
        return torch.device("cuda")
    if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


def _set_determinism(seed: int, device: torch.device) -> None:
    random.seed(seed)
    torch.manual_seed(seed)
    if device.type == "cuda":
        torch.cuda.manual_seed_all(seed)
        torch.backends.cudnn.deterministic = True
        torch.backends.cudnn.benchmark = False
    try:
        torch.use_deterministic_algorithms(True)
    except RuntimeError as exc:
        raise Stage2Error("Torch cannot enable deterministic algorithms for this runtime") from exc


def _code_boundary(config: Stage2Config, contract_sha256: str, pair_schema_sha256: str) -> dict[str, str]:
    paths = {
        "runner": Path(__file__),
        "model": REPO_ROOT / MODEL_SOURCE_RELATIVE,
        "preprocessing": REPO_ROOT / PREPROCESSING_SOURCE_RELATIVE,
        "losses": REPO_ROOT / LOSSES_SOURCE_RELATIVE,
        "contract": REPO_ROOT / config.model_manifest_relative,
        "pair_schema": REPO_ROOT / PAIR_SCHEMA_RELATIVE,
    }
    result = {name: _sha256_file(path, name) for name, path in paths.items()}
    if result["contract"] != contract_sha256 or result["pair_schema"] != pair_schema_sha256:
        raise Stage2Error("code boundary hashes changed during admission")
    return result


def _load_image_inputs(record: PairRecord) -> SETCompositionNetInputs:
    _assert_no_symlink_components(record.derivative_path, f"derivative {record.pair_id}")
    encoded = record.derivative_path.read_bytes()
    if hashlib.sha256(encoded).hexdigest() != record.derivative_sha256:
        raise Stage2Error(f"derivative image changed after admission: {record.pair_id}")
    try:
        with Image.open(BytesIO(encoded)) as opened:
            opened.load()
            rgb = opened.convert("RGB")
            pixels = torch.frombuffer(bytearray(rgb.tobytes()), dtype=torch.uint8).reshape(rgb.height, rgb.width, 3).clone()
            width, height = rgb.width, rgb.height
            rgb.close()
    except Exception as exc:  # noqa: BLE001 - decoder errors are input failures.
        raise Stage2Error(f"cannot decode derivative image {record.pair_id}") from exc
    raw_features: dict[str, object] = {}
    if record.derivative_roi is not None:
        x, y, roi_width, roi_height = record.derivative_roi
        raw_features.update({
            "subject_bbox_x": x,
            "subject_bbox_y": y,
            "subject_bbox_width": roi_width,
            "subject_bbox_height": roi_height,
            "subject_area_ratio": roi_width * roi_height,
            "subject_edge_pressure_left": x,
            "subject_edge_pressure_right": 1.0 - x - roi_width,
            "subject_edge_pressure_top": y,
            "subject_edge_pressure_bottom": 1.0 - y - roi_height,
        })
    try:
        # Derivatives are emitted from the generator's canonical oriented RGB
        # image and are metadata-free.  This is the same preprocessing owner
        # used by the runtime contract, with unknown metadata left masked.
        return preprocess_frame(
            pixels,
            width=width,
            height=height,
            roi=record.derivative_roi,
            raw_features=raw_features,
            orientation="up",
            mirroring=False,
            channel_order="RGB",
        )
    except (PreprocessingError, RuntimeError, ValueError) as exc:
        raise Stage2Error(f"preprocessing rejected derivative {record.pair_id}") from exc


def _stack_batch(records: Sequence[PairRecord], device: torch.device) -> tuple[SETCompositionNetInputs, dict[str, Tensor], dict[str, Tensor]]:
    inputs = [_load_image_inputs(record) for record in records]
    batch_inputs = SETCompositionNetInputs(
        torch.stack([item.full_frame_rgb for item in inputs]).to(device),
        torch.stack([item.subject_crop_rgb for item in inputs]).to(device),
        torch.stack([item.roi_normalized_xywh for item in inputs]).to(device),
        torch.stack([item.roi_mask for item in inputs]).to(device),
        torch.stack([item.scalar_features for item in inputs]).to(device),
        torch.stack([item.missing_feature_mask for item in inputs]).to(device),
    )
    targets = {
        "issue_logits": torch.tensor([record.issue_values for record in records], dtype=torch.float32, device=device),
        "action_utility_logits": torch.tensor([record.action_values for record in records], dtype=torch.float32, device=device),
        "continuous_target_deltas": torch.tensor([record.delta_values for record in records], dtype=torch.float32, device=device),
    }
    masks = {
        "issue_logits": torch.tensor([record.issue_mask for record in records], dtype=torch.float32, device=device),
        "action_utility_logits": torch.tensor([record.action_mask for record in records], dtype=torch.float32, device=device),
        "continuous_target_deltas": torch.tensor([record.delta_mask for record in records], dtype=torch.float32, device=device),
    }
    return batch_inputs, targets, masks


def _loss_config(config: Stage2Config) -> LossConfig:
    return LossConfig(
        LossWeights(
            scene_class_logits=0.0,
            subjectness_roi_agreement_logits=0.0,
            issue_logits=config.loss_weights["issue_logits"],
            action_utility_logits=config.loss_weights["action_utility_logits"],
            good_frame_probability=0.0,
            abstention_probability=0.0,
            risk_probability=0.0,
            continuous_target_deltas=config.loss_weights["continuous_target_deltas"],
            ranking=0.0,
            contrastive=0.0,
        ),
        focal_gamma=config.focal_gamma,
        focal_alpha=config.focal_alpha,
    )


def _validate_outputs(outputs: Mapping[str, Tensor], contract: SETCompositionNetManifest) -> None:
    if tuple(outputs) != contract.output_head_names:
        raise Stage2Error("CandidateA output ordering no longer matches the frozen contract")
    for name, value in outputs.items():
        if not isinstance(value, Tensor) or not torch.isfinite(value).all():
            raise Stage2Error(f"CandidateA output {name} is not finite")
        if value.ndim != 2 or value.shape[1] != contract.output_head_shapes[name]:
            raise Stage2Error(f"CandidateA output {name} shape disagrees with the frozen contract")
        value_range = contract.output_head_specs[name].get("value_range")
        if value_range is not None and (torch.any(value < float(value_range[0])) or torch.any(value > float(value_range[1]))):
            raise Stage2Error(f"CandidateA output {name} leaves its frozen value range")


def _configure_model(contract: SETCompositionNetManifest, binding: Stage1Binding, device: torch.device) -> tuple[nn.Module, list[nn.Parameter]]:
    model = CandidateA(contract)
    try:
        model.full_frame_backbone.load_state_dict(binding.state_dict, strict=True)
    except (KeyError, RuntimeError, TypeError, ValueError) as exc:
        raise Stage2Error("Stage-1 encoder cannot be loaded into CandidateA") from exc
    for parameter in model.parameters():
        parameter.requires_grad_(False)
    trainable: list[nn.Parameter] = []
    for name in TRAINABLE_HEADS:
        trainable.extend(parameter for parameter in model.heads[name].parameters())
        for parameter in model.heads[name].parameters():
            parameter.requires_grad_(True)
    model.to(device)
    # Frozen BatchNorm statistics must not mutate during head-only fitting.
    model.eval()
    return model, trainable


def _checkpoint_context(config: Stage2Config, admission: DataAdmission, binding: Stage1Binding, contract_info: Mapping[str, Any], code_boundary: Mapping[str, str]) -> dict[str, Any]:
    return {
        "config_sha256": config.source_sha256,
        "data_hash": admission.data_hash,
        "manifest_sha256": admission.manifest_sha256,
        "receipt_sha256": admission.receipt_sha256,
        "pair_root_manifest_sha256s": list(admission.manifest_sha256_by_root),
        "pair_root_receipt_sha256s": list(admission.receipt_sha256_by_root),
        "pair_root_count": len(admission.roots),
        "stage1_encoder_sha256": binding.artifact_sha256,
        "stage1_receipt_sha256": binding.receipt_sha256,
        "stage1_receipt_contract_sha256": binding.receipt_contract_sha256,
        "model_contract": dict(contract_info),
        "trainable_heads": list(TRAINABLE_HEADS),
        "code_boundary": dict(code_boundary),
        "fit_semantics": "all admitted research_fit silver pair derivatives only; source/control images are metadata references and no validation/test/release split exists",
    }


def _checkpoint_epoch(path: Path) -> int:
    match = CHECKPOINT_RE.fullmatch(path.name)
    if match is None:
        raise Stage2Error(f"checkpoint filename is not canonical: {path.name}")
    return int(match.group("epoch"))


def _run_receipt(run_root: Path, context: Mapping[str, Any]) -> Mapping[str, Any]:
    receipt_path = run_root / "receipt.json"
    _sha256_file(receipt_path, "Stage-2 run receipt")
    receipt = _read_json(receipt_path, "Stage-2 run receipt")
    if not isinstance(receipt, Mapping) or receipt.get("schema_id") != RECEIPT_SCHEMA_ID or receipt.get("schema_version") != "1.0.0":
        raise Stage2Error("Stage-2 resume receipt schema is unsupported")
    if receipt.get("context") != context or receipt.get("status") not in {"in_progress", "complete"}:
        raise Stage2Error("resume rejected: Stage-2 context or status changed")
    if not isinstance(receipt.get("started_at"), str) or not receipt["started_at"]:
        raise Stage2Error("Stage-2 resume receipt has no original started_at")
    return receipt


def _checkpoint_from_receipt(run_root: Path, receipt: Mapping[str, Any], explicit: str | Path | None) -> tuple[Path, int, str]:
    checkpoints = run_root / "checkpoints"
    if checkpoints.is_symlink() or not checkpoints.is_dir():
        raise Stage2Error("resume requested but checkpoints directory is missing")
    ledger = receipt.get("last_checkpoint")
    if not isinstance(ledger, Mapping):
        raise Stage2Error("Stage-2 receipt has no last_checkpoint ledger")
    relative = ledger.get("path")
    expected_sha = _valid_sha(ledger.get("sha256"), "Stage-2 last_checkpoint.sha256")
    if not isinstance(relative, str) or PurePosixPath(relative).parts[:1] != ("checkpoints",) or PurePosixPath(relative).as_posix() != relative or len(PurePosixPath(relative).parts) != 2:
        raise Stage2Error("Stage-2 last_checkpoint path is not canonical")
    ledger_path = run_root.joinpath(*PurePosixPath(relative).parts)
    try:
        ledger_path.resolve(strict=False).relative_to(checkpoints.resolve(strict=True))
    except (OSError, ValueError) as exc:
        raise Stage2Error("Stage-2 last_checkpoint escapes checkpoints") from exc
    if explicit is not None and str(explicit) != "latest":
        requested = Path(explicit).expanduser()
        requested_path = checkpoints / requested if len(requested.parts) == 1 else run_root / requested
        if requested_path.resolve(strict=False) != ledger_path.resolve(strict=False):
            raise Stage2Error("explicit Stage-2 checkpoint does not match receipt last_checkpoint")
    actual = _sha256_file(ledger_path, "Stage-2 last checkpoint")
    if actual != expected_sha:
        raise Stage2Error("Stage-2 checkpoint SHA-256 does not match receipt ledger")
    return ledger_path, _checkpoint_epoch(ledger_path), expected_sha


def _load_checkpoint(path: Path, context: Mapping[str, Any], expected_epoch: int, configured_epochs: int) -> Mapping[str, Any]:
    if _checkpoint_epoch(path) != expected_epoch or expected_epoch > configured_epochs:
        raise Stage2Error("Stage-2 checkpoint epoch does not match filename/config")
    try:
        payload = torch.load(path, map_location="cpu", weights_only=True)
    except (OSError, RuntimeError, EOFError, ValueError, pickle.UnpicklingError) as exc:
        raise Stage2Error("cannot load Stage-2 checkpoint with weights_only=True") from exc
    if not isinstance(payload, Mapping) or payload.get("schema_id") != CHECKPOINT_SCHEMA_ID or payload.get("context") != context:
        raise Stage2Error("Stage-2 checkpoint context is not receipt-bound")
    if type(payload.get("epoch")) is not int or payload["epoch"] != expected_epoch:
        raise Stage2Error("Stage-2 checkpoint epoch is invalid")
    return payload


def _environment(device: torch.device) -> dict[str, Any]:
    return {
        "python": sys.version.split()[0],
        "platform": platform.platform(),
        "torch": torch.__version__,
        "pillow": getattr(Image, "__version__", "unknown"),
        "cuda_available": bool(torch.cuda.is_available()),
        "cuda_version": torch.version.cuda,
        "device": str(device),
        "deterministic_algorithms": torch.are_deterministic_algorithms_enabled(),
    }


def _artifact_payload(model: nn.Module, config: Stage2Config, contract_info: Mapping[str, Any], binding: Stage1Binding) -> dict[str, Any]:
    return {
        "schema_id": ARTIFACT_SCHEMA_ID,
        "schema_version": "1.0.0",
        "kind": "candidate_a_stage2_silver_action_state_only",
        "candidate": config.candidate,
        "trainable_heads": list(TRAINABLE_HEADS),
        "model_contract": dict(contract_info),
        "model_contract_sha256": contract_info["model_contract_sha256"],
        "state_dict": {key: value.detach().cpu() for key, value in model.state_dict().items()},
        "stage1_encoder_sha256": binding.artifact_sha256,
        "stage1_receipt_sha256": binding.receipt_sha256,
        "contains_set_runtime_heads": True,
        "research_only": True,
        "human_gold": False,
        "release_admissible": False,
        "runtime_import_boundary": "not a release artifact; requires later human-gold training/calibration and separate promotion gate",
        "disclaimer": "Synthetic/silver action supervision only. No human-gold, validation, test, calibration, release, or model-redistribution claim is made.",
    }


def _verify_artifact(path: Path, expected_sha256: str | None, contract: SETCompositionNetManifest, contract_info: Mapping[str, Any], binding: Stage1Binding) -> str:
    actual = _sha256_file(path, "Stage-2 candidate artifact")
    if expected_sha256 is not None and actual != expected_sha256:
        raise Stage2Error("Stage-2 candidate artifact SHA-256 does not match receipt")
    try:
        payload = torch.load(path, map_location="cpu", weights_only=True)
    except (OSError, RuntimeError, EOFError, ValueError, pickle.UnpicklingError) as exc:
        raise Stage2Error("cannot verify Stage-2 candidate artifact with weights_only=True") from exc
    if not isinstance(payload, Mapping) or payload.get("schema_id") != ARTIFACT_SCHEMA_ID or payload.get("model_contract_sha256") != contract_info["model_contract_sha256"] or payload.get("candidate") != CandidateA.candidate_id or payload.get("trainable_heads") != list(TRAINABLE_HEADS) or payload.get("stage1_encoder_sha256") != binding.artifact_sha256 or payload.get("stage1_receipt_sha256") != binding.receipt_sha256:
        raise Stage2Error("Stage-2 candidate artifact metadata is not bound to this run")
    if payload.get("research_only") is not True or payload.get("human_gold") is not False or payload.get("release_admissible") is not False:
        raise Stage2Error("Stage-2 candidate artifact crossed the research-only boundary")
    state_dict = payload.get("state_dict")
    if not isinstance(state_dict, Mapping):
        raise Stage2Error("Stage-2 candidate artifact has no state_dict")
    try:
        model = CandidateA(contract)
        model.load_state_dict(state_dict, strict=True)
    except (KeyError, RuntimeError, TypeError, ValueError) as exc:
        raise Stage2Error("Stage-2 candidate artifact state is incompatible with CandidateA") from exc
    return actual


def _receipt(
    config: Stage2Config,
    admission: DataAdmission,
    binding: Stage1Binding,
    contract_info: Mapping[str, Any],
    context: Mapping[str, Any],
    code_boundary: Mapping[str, str],
    device: torch.device,
    history: Sequence[Mapping[str, Any]],
    checkpoint_path: Path,
    checkpoint_sha256: str,
    *,
    started_at: str,
    completed: bool,
) -> dict[str, Any]:
    run_root = checkpoint_path.parents[1]
    try:
        checkpoint_relative = checkpoint_path.resolve(strict=True).relative_to(run_root.resolve(strict=True))
    except (OSError, ValueError) as exc:
        raise Stage2Error("Stage-2 receipt checkpoint is outside the run root") from exc
    if checkpoint_relative.parts[:1] != ("checkpoints",) or len(checkpoint_relative.parts) != 2:
        raise Stage2Error("Stage-2 receipt checkpoint path is not canonical")
    active_counts = {name: 0 for name in TRAINABLE_HEADS}
    for record in admission.records:
        active_counts["issue_logits"] += sum(record.issue_mask)
        active_counts["action_utility_logits"] += sum(record.action_mask)
        active_counts["continuous_target_deltas"] += sum(record.delta_mask)
    return {
        "schema_id": RECEIPT_SCHEMA_ID,
        "schema_version": "1.0.0",
        "status": "complete" if completed else "in_progress",
        "started_at": started_at,
        "finished_at": datetime.now(timezone.utc).isoformat() if completed else None,
        "lane": "camera-coach-stage2-silver-actions",
        "candidate": config.candidate,
        "trainable_heads": list(TRAINABLE_HEADS),
        "context": dict(context),
        "source": {
            "pair_receipt_schema": PAIR_RECEIPT_SCHEMA_ID,
            "manifest": config.manifest_relative,
            "manifest_sha256": admission.manifest_sha256,
            "manifest_sha256_by_root": list(admission.manifest_sha256_by_root),
            "receipt": config.receipt_relative,
            "receipt_sha256": admission.receipt_sha256,
            "receipt_sha256_by_root": list(admission.receipt_sha256_by_root),
            "image_root": config.image_root_relative,
            "split": "research_fit",
            "roots": [dict(root.provenance) for root in admission.roots],
            "records_full": admission.full_record_count,
            "records_selected": len(admission.records),
            "media_aggregate_sha256": admission.media_aggregate_sha256,
            "media_aggregate_sha256_by_root": list(admission.media_aggregate_sha256_by_root),
        },
        "stage1_encoder": {
            "artifact": config.stage1_artifact_relative,
            "sha256": binding.artifact_sha256,
            "receipt": config.stage1_receipt_relative,
            "receipt_sha256": binding.receipt_sha256,
            "receipt_contract_sha256": binding.receipt_contract_sha256,
        },
        "preprocessing": {
            "owner": PREPROCESSING_SOURCE_RELATIVE,
            "rule": "derivative PNG is decoded as canonical oriented RGB and passed through preprocess_frame; runtime pixel-centre resize, clipped square_expand_1.25.v1 crop, ROI mask rasterization, known ROI/format/orientation scalars, and explicit missing masks are preserved",
            "source_images_loaded": False,
            "control_images_loaded": False,
        },
        "fit": {
            "records": len(admission.records),
            "active_labels": active_counts,
            "metrics_scope": "training-fit metrics only; all unknown target entries remain mask=0; no validation/test/release metrics or model-selection claim",
        },
        "counts": {"fit": len(admission.records), "epochs_completed": len(history), "active_labels": active_counts},
        "config_sha256": config.source_sha256,
        "data_hash": admission.data_hash,
        "model_contract": dict(contract_info),
        "model_contract_sha256": contract_info["model_contract_sha256"],
        "code_boundary": dict(code_boundary),
        "environment": _environment(device),
        "seed": config.seed,
        "training": {
            "epochs_configured": config.epochs,
            "batch_size": config.batch_size,
            "learning_rate": config.learning_rate,
            "weight_decay": config.weight_decay,
            "loss_weights": dict(config.loss_weights),
            "focal_gamma": config.focal_gamma,
            "focal_alpha": config.focal_alpha,
            "head_update_rule": "only CandidateA.heads.issue_logits, heads.action_utility_logits, and heads.continuous_target_deltas require gradients; all other parameters and buffers remain frozen/eval",
        },
        "last_checkpoint": {"path": checkpoint_relative.as_posix(), "sha256": checkpoint_sha256},
        "history": list(history),
        "research_only": True,
        "human_gold": False,
        "release_admissible": False,
        "disclaimer": "Silver/synthetic corruption supervision is research-only. This artifact is not human-gold evidence, a calibrated model, a release candidate, or a redistribution bundle.",
    }


def train(
    config_path: Path,
    data_root: Path | Sequence[Path],
    stage1_root: Path,
    run_dir: Path,
    *,
    declared_stage1_sha256: str,
    receipt_sha256s: Sequence[str] | None = None,
    resume: Path | str | None = None,
    device_name: str = "auto",
    stop_after_epoch: int | None = None,
    model_factory: Callable[[SETCompositionNetManifest, Stage1Binding, torch.device], tuple[nn.Module, list[nn.Parameter]]] | None = None,
) -> dict[str, Any]:
    config = Stage2Config.load(config_path)
    contract, contract_sha256, model_source_sha256 = _load_contract(config)
    pair_schema_sha256 = _load_pair_schema_sha256()
    admission = admit_data(data_root, config, contract, contract_sha256, receipt_sha256s=receipt_sha256s)
    binding = _load_stage1_binding(stage1_root, config, declared_stage1_sha256, contract, contract_sha256)
    run_root = _external_directory(run_dir, create=True, label="Stage-2 run root")
    if stop_after_epoch is not None and not 1 <= stop_after_epoch <= config.epochs:
        raise Stage2Error("stop_after_epoch must be within the configured epoch range")
    contract_info = {
        "model_contract_id": MODEL_CONTRACT_ID,
        "candidate": config.candidate,
        "backbone_architecture": "MobileNetV3-large-width-0.75",
        "input_size": list(config.input_size),
        "input_channels": 3,
        "output_head_order": list(contract.output_head_names),
        "trainable_heads": list(TRAINABLE_HEADS),
        "manifest_relative": config.model_manifest_relative,
        "manifest_sha256": contract_sha256,
        "model_source_relative": MODEL_SOURCE_RELATIVE,
        "model_source_sha256": model_source_sha256,
        "pair_schema_relative": PAIR_SCHEMA_RELATIVE,
        "pair_schema_sha256": pair_schema_sha256,
    }
    contract_info["model_contract_sha256"] = hashlib.sha256(_canonical_json(contract_info).encode("utf-8")).hexdigest()
    code_boundary = _code_boundary(config, contract_sha256, pair_schema_sha256)
    context = _checkpoint_context(config, admission, binding, contract_info, code_boundary)
    resume_receipt: Mapping[str, Any] | None = None
    resume_path: Path | None = None
    checkpoint_epoch = 0
    if resume is None:
        existing = [path for path in run_root.iterdir() if path.name not in {".DS_Store"}]
        if existing:
            raise Stage2Error("Stage-2 run directory is non-empty; pass --resume to continue it")
        started_at = datetime.now(timezone.utc).isoformat()
    else:
        resume_receipt = _run_receipt(run_root, context)
        resume_path, checkpoint_epoch, _ = _checkpoint_from_receipt(run_root, resume_receipt, resume)
        started_at = str(resume_receipt["started_at"])
    device = _resolve_device(device_name)
    _set_determinism(config.seed, device)
    model, trainable = model_factory(contract, binding, device) if model_factory is not None else _configure_model(contract, binding, device)
    if not trainable or any(not parameter.requires_grad for parameter in trainable):
        raise Stage2Error("Stage-2 model has no trainable action heads")
    trainable_ids = {id(parameter) for parameter in trainable}
    if any(parameter.requires_grad and id(parameter) not in trainable_ids for parameter in model.parameters()):
        raise Stage2Error("Stage-2 model exposes an unexpected trainable parameter")
    optimizer = torch.optim.AdamW(trainable, lr=config.learning_rate, weight_decay=config.weight_decay)
    loss_config = _loss_config(config)
    history: list[dict[str, Any]] = []
    start_epoch = 1
    if resume_path is not None:
        payload = _load_checkpoint(resume_path, context, checkpoint_epoch, config.epochs)
        try:
            model.load_state_dict(payload["model_state"], strict=True)
            optimizer.load_state_dict(payload["optimizer_state"])
            history = list(payload.get("history", []))
            start_epoch = checkpoint_epoch + 1
            random.setstate(payload["python_random_state"])
            torch.set_rng_state(payload["torch_rng_state"])
        except (KeyError, TypeError, RuntimeError, ValueError) as exc:
            raise Stage2Error("Stage-2 checkpoint state is incompatible with the current model") from exc
        model.eval()
    checkpoints_dir = run_root / "checkpoints"
    checkpoints_dir.mkdir(parents=True, exist_ok=True)
    metrics_path = run_root / "metrics.jsonl"
    if start_epoch > config.epochs:
        final_path = run_root / "candidate-final.pt"
        expected_final = None
        if resume_receipt is not None and resume_receipt.get("status") == "complete":
            final = resume_receipt.get("final_artifact")
            if not isinstance(final, Mapping) or final.get("path") != "candidate-final.pt":
                raise Stage2Error("complete Stage-2 receipt has no candidate-final.pt attestation")
            expected_final = _valid_sha(final.get("sha256"), "Stage-2 final_artifact.sha256")
        if resume_receipt is not None and resume_receipt.get("status") == "in_progress":
            final_sha256 = _atomic_torch(final_path, _artifact_payload(model, config, contract_info, binding))
        elif final_path.is_file():
            final_sha256 = _verify_artifact(final_path, expected_final, contract, contract_info, binding)
        else:
            final_sha256 = _atomic_torch(final_path, _artifact_payload(model, config, contract_info, binding))
        _verify_artifact(final_path, expected_final or final_sha256, contract, contract_info, binding)
        checkpoint = resume_path if resume_path is not None else checkpoints_dir / f"epoch-{config.epochs:04d}.pt"
        checkpoint_sha = _sha256_file(checkpoint, "Stage-2 final checkpoint")
        receipt = _receipt(config, admission, binding, contract_info, context, code_boundary, device, history, checkpoint, checkpoint_sha, started_at=started_at, completed=True)
        receipt["final_artifact"] = {"path": "candidate-final.pt", "sha256": final_sha256, "kind": ARTIFACT_SCHEMA_ID}
        _atomic_json(run_root / "receipt.json", receipt)
        return receipt
    for epoch in range(start_epoch, config.epochs + 1):
        model.eval()
        generator = torch.Generator(device="cpu")
        generator.manual_seed(config.seed + epoch)
        order = torch.randperm(len(admission.records), generator=generator).tolist()
        total_loss = 0.0
        total_terms = {name: 0.0 for name in TRAINABLE_HEADS}
        total_examples = 0
        batches = 0
        for start in range(0, len(order), config.batch_size):
            positions = order[start:start + config.batch_size]
            if len(positions) < config.batch_size and len(order) >= config.batch_size:
                # CandidateA's BatchNorm is kept in eval, but dropping the
                # singleton tail retains the Stage-1 batch contract exactly.
                continue
            batch_records = [admission.records[position] for position in positions]
            inputs, targets, masks = _stack_batch(batch_records, device)
            optimizer.zero_grad(set_to_none=True)
            outputs = model(inputs)
            _validate_outputs(outputs, contract)
            try:
                loss_result = compute_multitask_loss(outputs, targets, masks=masks, config=loss_config)
            except (LossError, RuntimeError, ValueError) as exc:
                raise Stage2Error("Stage-2 loss rejected an admitted batch") from exc
            loss = loss_result.total
            if not torch.isfinite(loss):
                raise Stage2Error("Stage-2 loss is not finite")
            loss.backward()
            for name, parameter in model.named_parameters():
                if parameter.requires_grad and (parameter.grad is None or not torch.isfinite(parameter.grad).all()):
                    raise Stage2Error(f"Stage-2 trainable gradient is missing/non-finite: {name}")
                if not parameter.requires_grad and parameter.grad is not None:
                    raise Stage2Error(f"Stage-2 frozen parameter received a gradient: {name}")
            optimizer.step()
            total_loss += float(loss.detach().cpu()) * len(batch_records)
            for name in TRAINABLE_HEADS:
                total_terms[name] += float(loss_result.per_head[name].detach().cpu()) * len(batch_records)
            total_examples += len(batch_records)
            batches += 1
        if batches == 0:
            raise Stage2Error("no complete Stage-2 training batch was available")
        metric = {
            "schema_id": "camera-silver-actions-stage2-metric-v1",
            "epoch": epoch,
            "train_loss": total_loss / total_examples,
            "train_head_losses": {name: total_terms[name] / total_examples for name in TRAINABLE_HEADS},
            "train_examples": total_examples,
            "train_batches": batches,
            "metrics_scope": "fit_only",
        }
        history.append(metric)
        checkpoint = {
            "schema_id": CHECKPOINT_SCHEMA_ID,
            "schema_version": "1.0.0",
            "epoch": epoch,
            "context": context,
            "history": history,
            "model_state": model.state_dict(),
            "optimizer_state": optimizer.state_dict(),
            "python_random_state": random.getstate(),
            "torch_rng_state": torch.get_rng_state(),
            "research_only": True,
            "human_gold": False,
            "release_admissible": False,
        }
        checkpoint_path = checkpoints_dir / f"epoch-{epoch:04d}.pt"
        checkpoint_sha256 = _atomic_torch(checkpoint_path, checkpoint)
        _atomic_bytes(metrics_path, ("".join(_canonical_json(row) + "\n" for row in history)).encode("utf-8"))
        _atomic_json(run_root / "receipt.json", _receipt(config, admission, binding, contract_info, context, code_boundary, device, history, checkpoint_path, checkpoint_sha256, started_at=started_at, completed=False))
        if stop_after_epoch is not None and epoch >= stop_after_epoch:
            return _read_json(run_root / "receipt.json", "Stage-2 run receipt")
    final_path = run_root / "candidate-final.pt"
    if final_path.exists():
        raise Stage2Error("candidate-final.pt exists before Stage-2 completion; resume to verify it")
    final_sha256 = _atomic_torch(final_path, _artifact_payload(model, config, contract_info, binding))
    _verify_artifact(final_path, final_sha256, contract, contract_info, binding)
    final_checkpoint = checkpoints_dir / f"epoch-{config.epochs:04d}.pt"
    final_checkpoint_sha256 = _sha256_file(final_checkpoint, "Stage-2 final checkpoint")
    receipt = _receipt(config, admission, binding, contract_info, context, code_boundary, device, history, final_checkpoint, final_checkpoint_sha256, started_at=started_at, completed=True)
    receipt["final_artifact"] = {"path": "candidate-final.pt", "sha256": final_sha256, "kind": ARTIFACT_SCHEMA_ID}
    _atomic_json(run_root / "receipt.json", receipt)
    return receipt


def _fixture_pair(
    pair_id: str,
    derivative_sha256: str,
    contract: SETCompositionNetManifest,
    *,
    horizon: bool = False,
    family_fill: str = "1",
) -> dict[str, Any]:
    issues = list(contract.output_head_specs["issue_logits"]["ordered_names"])
    actions = list(contract.output_head_specs["action_utility_logits"]["ordered_names"])
    deltas = list(contract.output_head_specs["continuous_target_deltas"]["ordered_names"])
    issue_values = [0] * len(issues)
    issue_mask = [0] * len(issues)
    action_values = [0] * len(actions)
    action_mask = [0] * len(actions)
    delta_values = [0.0] * len(deltas)
    delta_mask = [0] * len(deltas)
    issue_values[issues.index("horizon_distracts" if horizon else "subject_too_close_to_edge")] = 1
    issue_mask[issues.index("horizon_distracts" if horizon else "subject_too_close_to_edge")] = 1
    action_values[actions.index("level_horizon" if horizon else "shift_frame_left")] = 1
    action_mask[actions.index("level_horizon" if horizon else "shift_frame_left")] = 1
    delta_values[deltas.index("horizon_delta" if horizon else "delta_x")] = -0.05 if horizon else 0.15
    delta_mask[deltas.index("horizon_delta" if horizon else "delta_x")] = 1
    return {
        "schema_id": PAIR_SCHEMA_ID,
        "schema_version": PAIR_SCHEMA_VERSION,
        "pair_id": pair_id,
        "source_family_id": "family_" + family_fill * 32,
        "derivation_family_id": "family_" + family_fill * 32,
        "split": "research_fit",
        "is_independent": False,
        "counts_toward_quota": False,
        "research_only": True,
        "human_gold": False,
        "release_admissible": False,
        "source": {"source_id": f"fixture_{family_fill}", "source_record_id": pair_id, "relative_path": "source/never-loaded.png", "sha256": "3" * 64, "width": 320, "height": 240, "format": "png"},
        "derivative": {"relative_path": f"images/{pair_id}.png", "sha256": derivative_sha256, "width": 320, "height": 240, "format": "png"},
        "recipe": {"name": "rotate_horizon" if horizon else "crop_translate", "version": "camera-corruption-v1", "parameters": {}},
        "roi": {"coordinate_space": "oriented_full_frame_top_left_normalized", "transform": "analytic", "source_xywh": [0.30, 0.30, 0.25, 0.25], "derivative_xywh": [0.20, 0.30, 0.25, 0.25]},
        "geometry": {"provider": "silver_apple_vision", "runtime": "conditional_on_captured_apple_os_vision_runtime", "sha256": "4" * 64, "schema_id": "camera-silver-geometry-v1", "schema_version": "1.0.0", "schema_sha256": "5" * 64, "source_record_id": pair_id},
        "targets": {"issue": {"ordered_names": issues, "values": issue_values, "mask": issue_mask}, "action": {"ordered_names": actions, "values": action_values, "mask": action_mask}, "continuous": {"ordered_names": deltas, "values": delta_values, "mask": delta_mask}},
        "semantics_sha256": "6" * 64,
    }


def _write_fixture_pair_root(
    root: Path,
    contract: SETCompositionNetManifest,
    schema: Mapping[str, Any],
    pair_numbers: Sequence[int],
    *,
    family_fill: str,
) -> tuple[str, list[dict[str, Any]]]:
    root.mkdir(parents=True)
    (root / "images").mkdir()
    pairs: list[dict[str, Any]] = []
    for position, pair_number in enumerate(pair_numbers):
        horizon = position % 2 == 1
        pair_id = "pair_" + f"{pair_number:040x}"
        image = Image.new("RGB", (320, 240), (20 * (position + 1), 40, 80))
        encoded = BytesIO()
        image.save(encoded, format="PNG", optimize=False, compress_level=9)
        image.close()
        image_path = root / "images" / f"{pair_id}.png"
        image_path.write_bytes(encoded.getvalue())
        pair = _fixture_pair(
            pair_id,
            _sha256_bytes(encoded.getvalue()),
            contract,
            horizon=horizon,
            family_fill=family_fill,
        )
        pair["geometry"]["schema_sha256"] = _sha256_file(REPO_ROOT / GEOMETRY_SCHEMA_RELATIVE, "silver geometry schema")
        pair["semantics_sha256"] = schema["x-semantics-sha256"]
        pairs.append(pair)
    pairs.sort(key=lambda row: row["pair_id"])
    manifest_bytes = b"".join((_canonical_json(row) + "\n").encode("utf-8") for row in pairs)
    manifest_path = root / "pairs.jsonl"
    manifest_path.write_bytes(manifest_bytes)
    manifest_sha256 = _sha256_bytes(manifest_bytes)
    media_records = [_record_from_row_without_image(row, root, contract) for row in pairs]
    by_recipe: dict[str, int] = {}
    by_action: dict[str, int] = {}
    for pair in pairs:
        recipe_name = pair["recipe"]["name"]
        by_recipe[recipe_name] = by_recipe.get(recipe_name, 0) + 1
        for name, value, mask in zip(pair["targets"]["action"]["ordered_names"], pair["targets"]["action"]["values"], pair["targets"]["action"]["mask"]):
            if value and mask:
                by_action[name] = by_action.get(name, 0) + 1
    geometry_schema_sha256 = _sha256_file(REPO_ROOT / GEOMETRY_SCHEMA_RELATIVE, "silver geometry schema")
    geometry_receipt = {
        "path": "receipt.json",
        "sha256": "b" * 64,
        "schema_id": GEOMETRY_RECEIPT_SCHEMA_ID,
        "schema_version": "1.0.0",
        "determinism": GEOMETRY_DETERMINISM,
        "environment": {
            "os_version": "self-test",
            "os_version_components": {"major": 1, "minor": 0, "patch": 0},
            "platform": "macOS",
            "vision_framework": {"bundle_identifier": "com.apple.Vision", "name": "Vision", "version": "self-test"},
            "vision_request_family": list(VISION_REQUEST_FAMILY),
            "vision_request_revisions": {name: 1 for name in VISION_REQUEST_FAMILY},
        },
        "tool_source": {"path": GEOMETRY_TOOL_RELATIVE, "sha256": _sha256_file(REPO_ROOT / GEOMETRY_TOOL_RELATIVE, "geometry extractor source")},
    }
    receipt = {
        "schema_id": PAIR_RECEIPT_SCHEMA_ID,
        "schema_version": PAIR_SCHEMA_VERSION,
        "research_only": True,
        "human_gold": False,
        "release_admissible": False,
        "split": "research_fit",
        "seed": 1,
        "max_per_source": None,
        "inputs": {
            "inventory": {"sha256": "7" * 64, "records": len(pairs)},
            "geometry": {"sha256": "4" * 64, "schema_sha256": geometry_schema_sha256, "records": len(pairs), "receipt_path": "receipt.json", "receipt_sha256": geometry_receipt["sha256"]},
        },
        "geometry_receipt": geometry_receipt,
        "generator_source": {"path": GENERATOR_SOURCE_RELATIVE, "sha256": _sha256_file(REPO_ROOT / GENERATOR_SOURCE_RELATIVE, "generator source")},
        "contract": {"path": MODEL_MANIFEST_RELATIVE, "sha256": _sha256_file(REPO_ROOT / MODEL_MANIFEST_RELATIVE, "model contract")},
        "pair_schema": {"path": PAIR_SCHEMA_RELATIVE, "sha256": _sha256_file(REPO_ROOT / PAIR_SCHEMA_RELATIVE, "pair schema")},
        "semantics": schema["x-semantics"],
        "semantics_sha256": schema["x-semantics-sha256"],
        "counts": {"sources": len(pairs), "geometry_records": len(pairs), "pairs": len(pairs), "by_recipe": dict(sorted(by_recipe.items())), "by_action": dict(sorted(by_action.items())), "skip_reasons": {}},
        "output_manifest": {"path": "pairs.jsonl", "records": len(pairs), "sha256": manifest_sha256},
        "output_media": {"files": len(pairs), "aggregate_sha256": _aggregate_media_hash(media_records)},
    }
    receipt_path = root / "receipt.json"
    receipt_path.write_text(_canonical_json(receipt) + "\n", encoding="utf-8")
    return _sha256_file(receipt_path, "fixture pair receipt"), pairs


def _self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="camera-stage2-", dir="/private/tmp") as temp_dir:
        base = Path(temp_dir).resolve()
        data_root = base / "pairs"
        stage1_root = base / "stage1"
        run_root = base / "run"
        stage1_root.mkdir()
        contract, contract_sha256, model_source_sha256 = _load_contract(Stage2Config.load(REPO_ROOT / "ml/camera_coach/configs/silver_actions_stage2_colab.json")) if (REPO_ROOT / "ml/camera_coach/configs/silver_actions_stage2_colab.json").is_file() else (SETCompositionNetManifest.load(REPO_ROOT / MODEL_MANIFEST_RELATIVE), _sha256_file(REPO_ROOT / MODEL_MANIFEST_RELATIVE), _sha256_file(REPO_ROOT / MODEL_SOURCE_RELATIVE))
        schema_sha256 = _load_pair_schema_sha256()
        schema = _read_json(REPO_ROOT / PAIR_SCHEMA_RELATIVE, "silver action-pair schema")
        # The artifact is generated from a fresh CandidateA encoder so the
        # self-test exercises the real architecture/key compatibility guard.
        torch.manual_seed(20260909)
        seed_model = CandidateA(contract)
        stage1_model_contract = {
            "model_contract_id": MODEL_CONTRACT_ID,
            "candidate": CandidateA.candidate_id,
            "backbone": "full_frame_backbone",
            "backbone_architecture": "MobileNetV3-large-width-0.75",
            "input_size": [320, 320],
            "input_channels": 3,
            "output_dim": 720,
            "manifest_relative": MODEL_MANIFEST_RELATIVE,
            "manifest_sha256": contract_sha256,
            "model_source_relative": MODEL_SOURCE_RELATIVE,
            "model_source_sha256": model_source_sha256,
        }
        stage1_model_contract_hash = hashlib.sha256(_canonical_json(stage1_model_contract).encode("utf-8")).hexdigest()
        stage1_artifact = {
            "schema_id": STAGE1_ENCODER_SCHEMA_ID,
            "schema_version": "1.0.0",
            "kind": "disposable_research_encoder_state_only",
            "source_model": "CandidateA.full_frame_backbone",
            "candidate": CandidateA.candidate_id,
            "backbone": "full_frame_backbone",
            "model_contract": stage1_model_contract,
            "model_contract_sha256": stage1_model_contract_hash,
            "state_dict": {key: value.detach().cpu() for key, value in seed_model.full_frame_backbone.state_dict().items()},
            "contains_set_runtime_heads": False,
            "contains_eva_auxiliary_heads": False,
            "research_only": True,
            "human_gold": False,
            "release_admissible": False,
        }
        artifact_path = stage1_root / "encoder-final.pt"
        artifact_sha256 = _atomic_torch(artifact_path, stage1_artifact)
        stage1_receipt = {
            "schema_id": STAGE1_RECEIPT_SCHEMA_ID,
            "schema_version": "1.0.0",
            "status": "complete",
            "lane": "eva-stage1-encoder-warm-start",
            "candidate": CandidateA.candidate_id,
            "backbone": "full_frame_backbone",
            "model_contract": stage1_model_contract,
            "model_contract_sha256": stage1_model_contract_hash,
            "final_artifact": {"path": "encoder-final.pt", "sha256": artifact_sha256, "kind": STAGE1_ENCODER_SCHEMA_ID},
            "research_only": True,
            "human_gold": False,
            "release_admissible": False,
        }
        (stage1_root / "receipt.json").write_text(_canonical_json(stage1_receipt) + "\n", encoding="utf-8")
        pair_receipt_sha256, pairs = _write_fixture_pair_root(data_root, contract, schema, (1, 2), family_fill="1")
        config = {
            "schema_id": CONFIG_SCHEMA_ID,
            "schema_version": CONFIG_SCHEMA_VERSION,
            "seed": 20260909,
            "input_size": [320, 320],
            "data": {"manifest": "pairs.jsonl", "receipt": "receipt.json", "image_root": "."},
            "stage1": {"artifact": "encoder-final.pt", "receipt": "receipt.json"},
            "training": {"epochs": 2, "batch_size": 2, "learning_rate": 0.0001, "weight_decay": 0.0, "max_records": 0, "focal_gamma": 2.0, "focal_alpha": 0.25, "loss_weights": {name: 1.0 for name in TRAINABLE_HEADS}},
            "model": {"candidate": CandidateA.candidate_id, "manifest_path": MODEL_MANIFEST_RELATIVE, "manifest_sha256": contract_sha256},
        }
        config_path = base / "config.json"
        config_path.write_text(_canonical_json(config) + "\n", encoding="utf-8")
        first = train(config_path, data_root, stage1_root, run_root, declared_stage1_sha256=artifact_sha256, receipt_sha256s=(pair_receipt_sha256,), device_name="cpu", stop_after_epoch=1)
        assert first["status"] == "in_progress" and (run_root / "checkpoints/epoch-0001.pt").is_file()
        final = train(config_path, data_root, stage1_root, run_root, declared_stage1_sha256=artifact_sha256, receipt_sha256s=(pair_receipt_sha256,), resume="latest", device_name="cpu")
        assert final["status"] == "complete" and (run_root / "candidate-final.pt").is_file()
        assert final["research_only"] is True and final["human_gold"] is False and final["release_admissible"] is False
        assert final["trainable_heads"] == list(TRAINABLE_HEADS)
        artifact_payload = torch.load(run_root / "candidate-final.pt", map_location="cpu", weights_only=True)
        assert artifact_payload["trainable_heads"] == list(TRAINABLE_HEADS)
        assert len(final["source"]["roots"]) == 1 and final["source"]["roots"][0]["receipt"]["sha256"] == pair_receipt_sha256

        # Multiple audited roots remain separate trust domains; only metadata
        # is joined and global record ordering is independent of CLI root order.
        pair_root_a = base / "pairs-a"
        pair_root_b = base / "pairs-b"
        receipt_a, _ = _write_fixture_pair_root(pair_root_a, contract, schema, (3, 4), family_fill="3")
        receipt_b, _ = _write_fixture_pair_root(pair_root_b, contract, schema, (5, 6), family_fill="4")
        admission_ab = admit_data((pair_root_a, pair_root_b), Stage2Config.load(config_path), contract, contract_sha256, receipt_sha256s=(receipt_a, receipt_b))
        admission_ba = admit_data((pair_root_b, pair_root_a), Stage2Config.load(config_path), contract, contract_sha256, receipt_sha256s=(receipt_b, receipt_a))
        assert [record.pair_id for record in admission_ab.records] == [record.pair_id for record in admission_ba.records] == sorted(record.pair_id for record in admission_ab.records)
        assert admission_ab.data_hash == admission_ba.data_hash and admission_ab.receipt_sha256_by_root == admission_ba.receipt_sha256_by_root
        for label, roots, hashes in (
            ("swapped receipt hashes", (pair_root_a, pair_root_b), (receipt_b, receipt_a)),
            ("missing receipt hash", (pair_root_a, pair_root_b), (receipt_a,)),
        ):
            try:
                admit_data(roots, Stage2Config.load(config_path), contract, contract_sha256, receipt_sha256s=hashes)
            except Stage2Error:
                pass
            else:
                raise AssertionError(f"{label} was accepted")
        collision_root = base / "pairs-collision"
        collision_receipt, _ = _write_fixture_pair_root(collision_root, contract, schema, (7, 8), family_fill="1")
        try:
            admit_data((data_root, collision_root), Stage2Config.load(config_path), contract, contract_sha256, receipt_sha256s=(pair_receipt_sha256, collision_receipt))
        except Stage2Error as exc:
            assert "source-family collision" in str(exc)
        else:
            raise AssertionError("cross-root source-family collision was accepted")
        duplicate_media_root = base / "pairs-duplicate-media"
        duplicate_media_receipt, _ = _write_fixture_pair_root(duplicate_media_root, contract, schema, (1, 2), family_fill="9")
        try:
            admit_data((data_root, duplicate_media_root), Stage2Config.load(config_path), contract, contract_sha256, receipt_sha256s=(pair_receipt_sha256, duplicate_media_receipt))
        except Stage2Error as exc:
            assert "duplicate pair_id" in str(exc) or "duplicate derivative media path" in str(exc)
        else:
            raise AssertionError("cross-root pair/media collision was accepted")
        # Declared-hash mismatch must fail before any Stage-2 artifact can load.
        try:
            _load_stage1_binding(stage1_root, Stage2Config.load(config_path), "0" * 64, contract, contract_sha256)
        except Stage2Error as exc:
            assert "SHA-256" in str(exc)
        else:
            raise AssertionError("Stage-1 declared hash mismatch was accepted")
        print("PASS train_silver_actions self-test multi-root swapped-hash-missing-hash collision global-order pair-receipt-chain derivative-only-preprocessing masked-three-head-fit stage1-hash-gate atomic-resume research-boundary")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", help="run a tiny CPU-only bounded self-test")
    parser.add_argument("--config", type=Path, help="tracked Stage-2 JSON config")
    parser.add_argument("--data-root", "--pairs-root", dest="data_roots", action="append", type=Path, help="external pairs.jsonl/receipt.json root; repeat once per audited root")
    parser.add_argument("--receipt-sha256", "--data-receipt-sha256", dest="receipt_sha256s", action="append", help="expected SHA-256 of the corresponding pair root receipt; repeat in the same order as --data-root")
    parser.add_argument("--stage1-root", type=Path, help="external completed Stage-1 run root")
    parser.add_argument("--stage1-sha256", "--stage1-encoder-sha256", dest="stage1_sha256", help="declared SHA-256 of Stage-1 encoder-final.pt")
    parser.add_argument("--run-dir", type=Path, help="external restartable Stage-2 run root")
    parser.add_argument("--resume", nargs="?", const="latest", help="resume latest or an explicitly ledgered checkpoint")
    parser.add_argument("--device", default="auto", choices=("auto", "cpu", "cuda", "mps"))
    parser.add_argument("--stop-after-epoch", type=int, help=argparse.SUPPRESS)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.self_test:
            _self_test()
            return 0
        if args.config is None or args.data_roots is None or args.receipt_sha256s is None or args.stage1_root is None or args.stage1_sha256 is None or args.run_dir is None:
            _parser().error("--config, one or more --data-root values, one matching --receipt-sha256 per root, --stage1-root, --stage1-sha256, and --run-dir are required unless --self-test is used")
        result = train(args.config, args.data_roots, args.stage1_root, args.run_dir, declared_stage1_sha256=args.stage1_sha256, receipt_sha256s=args.receipt_sha256s, resume=args.resume, device_name=args.device, stop_after_epoch=args.stop_after_epoch)
        print(json.dumps({"status": result.get("status"), "run_dir": str(args.run_dir), "final_artifact": result.get("final_artifact"), "epochs_completed": result.get("counts", {}).get("epochs_completed")}, ensure_ascii=False, sort_keys=True))
        return 0
    except Stage2Error as exc:
        print(f"FAIL {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
