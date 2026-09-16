#!/usr/bin/env python3
"""Research-only EVA Stage-1 warm-start for CandidateA's full-frame encoder.

This runner deliberately trains only ``CandidateA.full_frame_backbone`` and a
disposable set of EVA-native auxiliary heads.  It never creates labels for the
SET scene, issue, action, good-frame, abstention, risk, or delta heads.  The
final artifact contains encoder weights only; the separate checkpoint contains
the disposable heads and is not a SET runtime model.

The command is intentionally self-contained so the Colab notebook can call it
without duplicating trainer logic::

    python3 ml/camera_coach/pretrain_eva.py \
        --config ml/camera_coach/configs/eva_stage1_colab.json \
        --data-root /external/eva/fb40a9f1 \
        --run-dir /external/runs/eva-stage1

The data root and run directory must be outside the Git checkout.  Both are
research-only, rights-uncleared inputs and outputs.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
from io import BytesIO
import json
import math
import os
from pathlib import Path, PurePosixPath
import platform
import pickle
import random
import re
import subprocess
import sys
import tempfile
from typing import Any, Callable, Mapping, Sequence

try:
    import torch
    from PIL import Image, ImageCms, ImageOps
    from torch import Tensor, nn
    from torch.nn import functional as F
except ImportError as exc:  # pragma: no cover - the normal runtime has both.
    raise SystemExit("EVA Stage-1 needs the preinstalled Torch and Pillow runtimes") from exc


# Keep direct execution and ``python -m`` execution equivalent.  The project
# has no top-level ml/__init__.py, so Python's namespace-package import is used.
REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from ml.camera_coach.models import set_composition_net as scm  # noqa: E402


CONFIG_SCHEMA_ID = "camera-eva-stage1-config-v1"
CONFIG_SCHEMA_VERSION = "1.0.0"
RECEIPT_SCHEMA_ID = "camera-eva-silver-receipt-v1"
MODEL_CONTRACT_ID = "SETCompositionNet-v1"
STAGE1_RECEIPT_SCHEMA_ID = "camera-eva-stage1-training-receipt-v1"
ENCODER_ARTIFACT_SCHEMA_ID = "camera-eva-stage1-encoder-v1"
CHECKPOINT_SCHEMA_ID = "camera-eva-stage1-checkpoint-v1"
MANIFEST_RELATIVE = "ml/camera_coach/contracts/set_composition_net_v1.json"
MODEL_SOURCE_RELATIVE = "ml/camera_coach/models/set_composition_net.py"
PRETRAIN_SOURCE_RELATIVE = "ml/camera_coach/pretrain_eva.py"
VOTE_FIELDS = ("score", "difficulty", "visual", "composition", "quality", "semantic")
ATTRIBUTE_FIELDS = frozenset(VOTE_FIELDS[1:])
CATEGORY_COUNT = 6
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
ID_RE = re.compile(r"^[^/\\\x00\r\n]+$")
CHECKPOINT_FILENAME_RE = re.compile(r"^epoch-(?P<epoch>[0-9]{4})\.pt$")
EXPECTED_CONFIG_KEYS = {
    "schema_id", "schema_version", "seed", "input_size", "data", "training", "model",
}
EXPECTED_DATA_KEYS = {"manifest", "receipt"}
EXPECTED_TRAINING_KEYS = {"epochs", "batch_size", "learning_rate", "weight_decay", "category_loss_weight", "max_records"}
EXPECTED_MODEL_KEYS = {"candidate", "backbone", "manifest_path", "manifest_sha256"}
EXPECTED_SILVER_KEYS = {
    "schema_id", "schema_version", "dataset_kind", "image_id", "relative_path", "image_sha256",
    "provenance", "content_category", "counts", "aggregates", "uncertainty", "label_boundary",
    "intake_tier", "human_gold", "release_admissible",
}


class Stage1Error(ValueError):
    """Raised when a Stage-1 run cannot be admitted safely."""


class ConfigError(Stage1Error):
    """Raised for a malformed or unsupported Stage-1 config."""


def _reject_nonfinite(value: str) -> Any:
    raise ConfigError(f"non-finite JSON value is not allowed: {value}")


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"), parse_constant=_reject_nonfinite)
    except ConfigError:
        raise
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise Stage1Error(f"cannot read JSON: {path}") from exc


def _canonical_json(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def _sha256_file(path: Path) -> str:
    try:
        info = path.lstat()
    except OSError as exc:
        raise Stage1Error(f"cannot inspect file: {path}") from exc
    if not stat_is_regular(info.st_mode):
        raise Stage1Error(f"not a regular file: {path}")
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise Stage1Error(f"cannot read file: {path}") from exc
    return digest.hexdigest()


def stat_is_regular(mode: int) -> bool:
    # Keep imports minimal while retaining a single explicit regular-file test.
    import stat
    return stat.S_ISREG(mode)


def _assert_no_symlink_components(path: Path) -> None:
    """Reject symlinks in every existing lexical component of ``path``."""

    import stat

    absolute = Path(os.path.abspath(path))
    current = Path(absolute.anchor)
    for part in absolute.parts[1:]:
        current /= part
        try:
            info = current.lstat()
        except FileNotFoundError:
            break
        except OSError as exc:
            raise Stage1Error(f"cannot inspect path component: {current}") from exc
        if stat.S_ISLNK(info.st_mode):
            raise Stage1Error(f"path uses a symlink: {current}")


def _external_directory(value: Path, *, create: bool) -> Path:
    candidate = Path(value).expanduser()
    _assert_no_symlink_components(candidate)
    absolute = Path(os.path.abspath(candidate))
    repository = REPO_ROOT.resolve()
    if absolute == repository or repository in absolute.parents or absolute in repository.parents:
        raise Stage1Error("data and run roots must be outside the repository and its ancestors")
    if create:
        try:
            absolute.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            raise Stage1Error(f"cannot create external directory: {absolute}") from exc
    if absolute.is_symlink() or not absolute.is_dir():
        raise Stage1Error(f"external directory is missing or not a directory: {absolute}")
    try:
        resolved = absolute.resolve(strict=True)
    except OSError as exc:
        raise Stage1Error(f"cannot resolve external directory: {absolute}") from exc
    if resolved != absolute:
        raise Stage1Error("external directory must not resolve through a symlink")
    return absolute


def _safe_relative(root: Path, value: object, *, label: str) -> tuple[Path, str]:
    if not isinstance(value, str) or not value or "\x00" in value:
        raise Stage1Error(f"{label} must be a non-empty relative path")
    normalized = value.replace("\\", "/")
    path = PurePosixPath(normalized)
    parts = path.parts
    if path.is_absolute() or not parts or any(part in {"", ".", ".."} for part in parts):
        raise Stage1Error(f"{label} is not a safe relative path")
    if ":" in parts[0]:
        raise Stage1Error(f"{label} has a drive prefix")
    current = root
    for part in parts:
        current /= part
        try:
            info = current.lstat()
        except FileNotFoundError:
            continue
        except OSError as exc:
            raise Stage1Error(f"cannot inspect {label}") from exc
        import stat
        if stat.S_ISLNK(info.st_mode):
            raise Stage1Error(f"{label} uses a symlink")
    candidate = root.joinpath(*parts)
    resolved = candidate.resolve(strict=False)
    if resolved != candidate:
        raise Stage1Error(f"{label} escapes the data root")
    try:
        resolved.relative_to(root)
    except ValueError as exc:
        raise Stage1Error(f"{label} is outside the data root") from exc
    return candidate, PurePosixPath(*parts).as_posix()


def _regular_file(path: Path, *, label: str) -> Path:
    import stat
    try:
        info = path.lstat()
    except OSError as exc:
        raise Stage1Error(f"cannot inspect {label}: {path}") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise Stage1Error(f"{label} is not a regular file: {path}")
    return path


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


def _require_int(value: object, label: str, *, minimum: int, maximum: int) -> int:
    if type(value) is not int or not minimum <= value <= maximum:
        raise ConfigError(f"{label} must be an integer in [{minimum}, {maximum}]")
    return value


def _require_float(value: object, label: str, *, minimum: float, maximum: float) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ConfigError(f"{label} must be a finite number in [{minimum}, {maximum}]")
    result = float(value)
    if not math.isfinite(result) or result < minimum or result > maximum:
        raise ConfigError(f"{label} must be a finite number in [{minimum}, {maximum}]")
    return result


def _require_sha(value: object, label: str) -> str:
    result = _require_string(value, label)
    if SHA256_RE.fullmatch(result) is None:
        raise ConfigError(f"{label} must be a lowercase SHA-256 digest")
    return result


@dataclass(frozen=True)
class Stage1Config:
    source_path: Path
    source_bytes_sha256: str
    seed: int
    input_size: tuple[int, int]
    manifest_relative: str
    receipt_relative: str
    epochs: int
    batch_size: int
    learning_rate: float
    weight_decay: float
    category_loss_weight: float
    max_records: int
    model_manifest_relative: str
    model_manifest_sha256: str
    candidate: str
    backbone: str

    @classmethod
    def load(cls, path: Path) -> "Stage1Config":
        source = _regular_file(path, label="config")
        raw = _read_json(source)
        top = _require_keys(raw, EXPECTED_CONFIG_KEYS, "config")
        if top["schema_id"] != CONFIG_SCHEMA_ID or top["schema_version"] != CONFIG_SCHEMA_VERSION:
            raise ConfigError("config schema/version is unsupported")
        seed = _require_int(top["seed"], "seed", minimum=0, maximum=2**63 - 1)
        input_size = top["input_size"]
        if not isinstance(input_size, list) or len(input_size) != 2 or any(type(v) is not int or v < 1 for v in input_size):
            raise ConfigError("input_size must be [height, width]")
        if tuple(input_size) != (320, 320):
            raise ConfigError("CandidateA Stage-1 requires the frozen 320x320 input contract")
        data = _require_keys(top["data"], EXPECTED_DATA_KEYS, "data")
        training = _require_keys(top["training"], EXPECTED_TRAINING_KEYS, "training")
        model = _require_keys(top["model"], EXPECTED_MODEL_KEYS, "model")
        manifest_relative = _safe_config_relative(data["manifest"], "data.manifest")
        receipt_relative = _safe_config_relative(data["receipt"], "data.receipt")
        model_manifest_relative = _safe_config_relative(model["manifest_path"], "model.manifest_path")
        return cls(
            source_path=source,
            source_bytes_sha256=_sha256_file(source),
            seed=seed,
            input_size=(320, 320),
            manifest_relative=manifest_relative,
            receipt_relative=receipt_relative,
            epochs=_require_int(training["epochs"], "training.epochs", minimum=1, maximum=1000),
            batch_size=_require_int(training["batch_size"], "training.batch_size", minimum=2, maximum=512),
            learning_rate=_require_float(training["learning_rate"], "training.learning_rate", minimum=1e-9, maximum=1.0),
            weight_decay=_require_float(training["weight_decay"], "training.weight_decay", minimum=0.0, maximum=1.0),
            category_loss_weight=_require_float(training["category_loss_weight"], "training.category_loss_weight", minimum=0.0, maximum=100.0),
            max_records=_require_int(training["max_records"], "training.max_records", minimum=0, maximum=10_000_000),
            model_manifest_relative=model_manifest_relative,
            model_manifest_sha256=_require_sha(model["manifest_sha256"], "model.manifest_sha256"),
            candidate=_require_string(model["candidate"], "model.candidate"),
            backbone=_require_string(model["backbone"], "model.backbone"),
        )


def _safe_config_relative(value: object, label: str) -> str:
    if not isinstance(value, str) or not value or "\x00" in value:
        raise ConfigError(f"{label} must be a non-empty relative path")
    normalized = value.replace("\\", "/")
    path = PurePosixPath(normalized)
    if path.is_absolute() or not path.parts or any(part in {"", ".", ".."} for part in path.parts) or ":" in path.parts[0]:
        raise ConfigError(f"{label} must be a safe relative path")
    return PurePosixPath(*path.parts).as_posix()


@dataclass(frozen=True)
class DataRecord:
    image_id: str
    path: Path
    relative_path: str
    image_sha256: str
    labels: tuple[float, ...]
    category: int


@dataclass(frozen=True)
class DataAdmission:
    records: tuple[DataRecord, ...]
    data_root: Path
    manifest_path: Path
    receipt_path: Path
    manifest_sha256: str
    receipt_sha256: str
    data_hash: str
    source_receipt: Mapping[str, Any]
    full_record_count: int
    preprocessing_counts: Mapping[str, int]


def _validate_receipt(receipt_path: Path, *, manifest_relative: str, manifest_sha256: str, manifest_records: int) -> Mapping[str, Any]:
    raw = _read_json(receipt_path)
    if not isinstance(raw, dict):
        raise Stage1Error("EVA silver receipt must be an object")
    if raw.get("schema_id") != RECEIPT_SCHEMA_ID or raw.get("intake_tier") != "research_only" or raw.get("human_gold") is not False or raw.get("release_admissible") is not False:
        raise Stage1Error("EVA silver receipt is not the expected research-only non-gold receipt")
    output = raw.get("output")
    if not isinstance(output, dict) or output.get("path") != manifest_relative or output.get("sha256") != manifest_sha256 or output.get("records") != manifest_records:
        raise Stage1Error("EVA silver receipt output attestation does not match the manifest")
    boundary = raw.get("label_boundary")
    if not isinstance(boundary, str) or "not_camera_coach" not in boundary:
        raise Stage1Error("EVA silver receipt does not declare the Camera Coach label boundary")
    colab_export = raw.get("colab_export")
    if not isinstance(colab_export, dict) or colab_export.get("join_key") != "image_id" or colab_export.get("image_path_field") != "relative_path":
        raise Stage1Error("EVA silver receipt has no explicit image join contract")
    scales = colab_export.get("upstream_scale")
    if not isinstance(scales, dict):
        raise Stage1Error("EVA silver receipt has no upstream scale contract")
    score = scales.get("score")
    difficulty = scales.get("difficulty")
    attributes = scales.get("attributes")
    if (
        not isinstance(score, dict) or score.get("min") != 0 or score.get("max") != 10
        or not isinstance(difficulty, dict) or difficulty.get("min") != 1 or difficulty.get("max") != 4
        or not isinstance(attributes, dict) or attributes.get("min") != 1 or attributes.get("max") != 4
        or attributes.get("fields") != list(VOTE_FIELDS[2:])
    ):
        raise Stage1Error("EVA silver receipt upstream scales do not match the six EVA targets")
    return raw


def _valid_sha(value: object, label: str) -> str:
    if not isinstance(value, str) or SHA256_RE.fullmatch(value) is None:
        raise Stage1Error(f"{label} must be a lowercase SHA-256 digest")
    return value


def _label_value(row: Mapping[str, Any], field: str, scales: Mapping[str, tuple[float, float]]) -> float:
    aggregates = row.get("aggregates")
    if not isinstance(aggregates, Mapping):
        raise Stage1Error(f"silver row {row.get('image_id', '?')} has no aggregates")
    dimension = aggregates.get(field)
    if not isinstance(dimension, Mapping):
        raise Stage1Error(f"silver row {row.get('image_id', '?')} has no aggregate {field}")
    value = dimension.get("mean")
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)):
        raise Stage1Error(f"silver row {row.get('image_id', '?')}.{field}.mean is not finite")
    low, high = scales[field]
    if not low <= float(value) <= high:
        raise Stage1Error(f"silver row {row.get('image_id', '?')}.{field}.mean is outside the EVA scale")
    return (float(value) - low) / (high - low)


def admit_data(data_root_value: Path, config: Stage1Config) -> DataAdmission:
    root = _external_directory(data_root_value, create=False)
    manifest_path, manifest_relative = _safe_relative(root, config.manifest_relative, label="silver manifest")
    receipt_path, receipt_relative = _safe_relative(root, config.receipt_relative, label="silver receipt")
    if manifest_relative != config.manifest_relative or receipt_relative != config.receipt_relative:
        raise Stage1Error("data paths did not remain canonical after normalization")
    _regular_file(manifest_path, label="silver manifest")
    _regular_file(receipt_path, label="silver receipt")
    manifest_sha256 = _sha256_file(manifest_path)
    try:
        lines = manifest_path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as exc:
        raise Stage1Error("cannot read silver manifest") from exc
    if not lines:
        raise Stage1Error("silver manifest is empty")
    manifest_records = len(lines)
    receipt = _validate_receipt(receipt_path, manifest_relative=config.manifest_relative, manifest_sha256=manifest_sha256, manifest_records=manifest_records)
    upstream_scale = receipt["colab_export"]["upstream_scale"]
    scales: dict[str, tuple[float, float]] = {
        "score": (float(upstream_scale["score"]["min"]), float(upstream_scale["score"]["max"])),
        "difficulty": (float(upstream_scale["difficulty"]["min"]), float(upstream_scale["difficulty"]["max"])),
    }
    for field in VOTE_FIELDS[2:]:
        scales[field] = (float(upstream_scale["attributes"]["min"]), float(upstream_scale["attributes"]["max"]))
    records: list[DataRecord] = []
    seen_ids: set[str] = set()
    seen_paths: set[str] = set()
    preprocessing_counts = {
        "orientation_transformed_images": 0,
        "embedded_icc_images": 0,
        "embedded_icc_converted_to_srgb_images": 0,
        "untagged_srgb_assumption_images": 0,
    }
    for line_number, line in enumerate(lines, 1):
        if not line.strip():
            raise Stage1Error(f"silver manifest has a blank line at {line_number}")
        try:
            row = json.loads(line, parse_constant=_reject_nonfinite)
        except ConfigError:
            raise
        except (UnicodeError, json.JSONDecodeError) as exc:
            raise Stage1Error(f"silver manifest line {line_number} is malformed JSON") from exc
        if not isinstance(row, dict):
            raise Stage1Error(f"silver manifest line {line_number} must be an object")
        if set(row) != EXPECTED_SILVER_KEYS:
            raise Stage1Error(f"silver manifest line {line_number} keys drifted")
        image_id = row.get("image_id")
        if not isinstance(image_id, str) or not image_id or ID_RE.fullmatch(image_id) is None or image_id in seen_ids:
            raise Stage1Error(f"silver manifest line {line_number} has a duplicate or unsafe image_id")
        if row.get("schema_id") != "camera-eva-silver-v1" or row.get("intake_tier") != "research_only" or row.get("human_gold") is not False or row.get("release_admissible") is not False:
            raise Stage1Error(f"silver manifest line {line_number} is not an immutable research-only row")
        if row.get("label_boundary") != "silver_reference_only_not_camera_coach_action_label":
            raise Stage1Error(f"silver manifest line {line_number} crosses the Camera Coach label boundary")
        relative_path = row.get("relative_path")
        image_path, normalized_relative = _safe_relative(root, relative_path, label=f"silver row {line_number}.relative_path")
        if normalized_relative in seen_paths:
            raise Stage1Error(f"silver manifest line {line_number} has a duplicate relative_path")
        _regular_file(image_path, label=f"silver row {line_number}.image")
        expected_image_sha = _valid_sha(row.get("image_sha256"), f"silver row {line_number}.image_sha256")
        actual_image_sha = _sha256_file(image_path)
        if actual_image_sha != expected_image_sha:
            raise Stage1Error(f"silver image hash mismatch for {image_id}")
        orientation_applied, has_embedded_icc = _inspect_preprocessing(image_path)
        preprocessing_counts["orientation_transformed_images"] += int(orientation_applied)
        preprocessing_counts["embedded_icc_images"] += int(has_embedded_icc)
        preprocessing_counts["embedded_icc_converted_to_srgb_images"] += int(has_embedded_icc)
        preprocessing_counts["untagged_srgb_assumption_images"] += int(not has_embedded_icc)
        category = row.get("content_category")
        if type(category) is not int or not 1 <= category <= CATEGORY_COUNT:
            raise Stage1Error(f"silver row {line_number}.content_category must be in 1..6")
        provenance = row.get("provenance")
        if not isinstance(provenance, Mapping) or provenance.get("source_id") != "eva_official":
            raise Stage1Error(f"silver manifest line {line_number} has unexpected provenance")
        labels = tuple(_label_value(row, field, scales) for field in VOTE_FIELDS)
        records.append(
            DataRecord(
                image_id=image_id,
                path=image_path,
                relative_path=normalized_relative,
                image_sha256=expected_image_sha,
                labels=labels,
                category=category - 1,
            )
        )
        seen_ids.add(image_id)
        seen_paths.add(normalized_relative)
    records.sort(key=lambda record: record.image_id)
    full_record_count = len(records)
    if config.max_records:
        records = records[: config.max_records]
    if len(records) < 2:
        raise Stage1Error("admitted silver rows must contain at least two fit records")
    receipt_sha256 = _sha256_file(receipt_path)
    data_hash = hashlib.sha256(
        _canonical_json({"manifest_sha256": manifest_sha256, "receipt_sha256": receipt_sha256, "full_records": full_record_count, "selected_records": len(records)}).encode("utf-8")
    ).hexdigest()
    # A second fence catches a replacement of the manifest/receipt while rows
    # were being decoded.  Each image is also rechecked when it is loaded.
    if _sha256_file(manifest_path) != manifest_sha256 or _sha256_file(receipt_path) != receipt_sha256:
        raise Stage1Error("silver inputs changed during admission")
    return DataAdmission(
        records=tuple(records),
        data_root=root,
        manifest_path=manifest_path,
        receipt_path=receipt_path,
        manifest_sha256=manifest_sha256,
        receipt_sha256=receipt_sha256,
        data_hash=data_hash,
        source_receipt=receipt,
        full_record_count=full_record_count,
        preprocessing_counts=preprocessing_counts,
    )


def _load_model_contract(config: Stage1Config) -> tuple[scm.SETCompositionNetManifest, dict[str, Any], str]:
    manifest_path = _regular_file(REPO_ROOT / config.model_manifest_relative, label="model contract")
    actual_manifest_sha = _sha256_file(manifest_path)
    if actual_manifest_sha != config.model_manifest_sha256:
        raise Stage1Error("model contract hash does not match the config")
    contract = scm.SETCompositionNetManifest.load(manifest_path)
    if contract.raw.get("contract_id") != "SETCompositionNet" or config.candidate != "candidate_a_dual_branch" or config.backbone != "full_frame_backbone":
        raise Stage1Error("config is not for CandidateA.full_frame_backbone")
    model_source_path = _regular_file(REPO_ROOT / MODEL_SOURCE_RELATIVE, label="model source")
    model_contract = {
        "model_contract_id": MODEL_CONTRACT_ID,
        "candidate": config.candidate,
        "backbone": config.backbone,
        "backbone_architecture": "MobileNetV3-large-width-0.75",
        "input_size": list(config.input_size),
        "input_channels": 3,
        "output_dim": 720,
        "manifest_relative": config.model_manifest_relative,
        "manifest_sha256": actual_manifest_sha,
        "model_source_relative": MODEL_SOURCE_RELATIVE,
        "model_source_sha256": _sha256_file(model_source_path),
        "forbidden_supervision": [
            "scene_class_logits", "subjectness_roi_agreement_logits", "issue_logits", "action_utility_logits",
            "good_frame_probability", "abstention_probability", "risk_probability", "continuous_target_deltas",
        ],
    }
    return contract, model_contract, hashlib.sha256(_canonical_json(model_contract).encode("utf-8")).hexdigest()


class EVAAuxiliaryHeads(nn.Module):
    """Disposable source-native heads; never part of SET runtime output."""

    def __init__(self, encoder_dim: int):
        super().__init__()
        hidden = min(256, max(64, encoder_dim // 2))
        self.shared = nn.Sequential(nn.Linear(encoder_dim, hidden), nn.Hardswish(inplace=True))
        self.regression = nn.ModuleDict({field: nn.Linear(hidden, 1) for field in VOTE_FIELDS})
        self.category = nn.Linear(hidden, CATEGORY_COUNT)

    def forward(self, features: Tensor) -> dict[str, Tensor]:
        hidden = self.shared(features)
        return {
            "regression": torch.cat([torch.sigmoid(self.regression[field](hidden)) for field in VOTE_FIELDS], dim=1),
            "category": self.category(hidden),
        }


class EVAStage1Model(nn.Module):
    """CandidateA full-frame encoder plus disposable EVA supervision."""

    def __init__(self, encoder: nn.Module):
        super().__init__()
        self.encoder = encoder
        output_dim = getattr(encoder, "output_dim", None)
        if type(output_dim) is not int or output_dim < 1:
            raise Stage1Error("full-frame encoder does not expose a valid output_dim")
        self.auxiliary = EVAAuxiliaryHeads(output_dim)

    def forward(self, image: Tensor) -> dict[str, Tensor]:
        features = self.encoder(image)
        if features.ndim != 2:
            raise Stage1Error(f"full-frame encoder must return [B, D], got {tuple(features.shape)}")
        return self.auxiliary(features)


def _candidate_a_encoder(contract: scm.SETCompositionNetManifest) -> nn.Module:
    candidate = scm.CandidateA(contract)
    encoder = candidate.full_frame_backbone
    if not isinstance(encoder, nn.Module) or getattr(encoder, "output_dim", None) != 720:
        raise Stage1Error("CandidateA full-frame backbone no longer matches the frozen 720D contract")
    return encoder


def _normalise_source_image(image: Image.Image) -> tuple[Image.Image, bool, bool]:
    """Apply EXIF orientation once, then convert embedded ICC to sRGB.

    Untagged images are intentionally treated as sRGB.  A malformed or
    unsupported embedded profile is an input error rather than a silent colour
    shift.  The returned image owns its decoded pixels and can be resized by
    the caller.
    """

    exif_orientation = image.getexif().get(274, 1)
    # Pillow and the EVA JPEG inventory use 0 as an unspecified legacy
    # sentinel; preserve its documented no-op behavior.  Reject other numeric
    # values outside the EXIF 1..8 domain before Pillow can interpret them.
    if isinstance(exif_orientation, int) and not isinstance(exif_orientation, bool) and (exif_orientation < 0 or exif_orientation > 8):
        raise Stage1Error("unsupported EXIF orientation value")
    orientation_applied = isinstance(exif_orientation, int) and not isinstance(exif_orientation, bool) and exif_orientation in {2, 3, 4, 5, 6, 7, 8}
    try:
        oriented = ImageOps.exif_transpose(image)
    except Exception as exc:  # noqa: BLE001 - Pillow varies by malformed EXIF payload.
        raise Stage1Error("malformed EXIF orientation") from exc
    profile_bytes = oriented.info.get("icc_profile")
    has_embedded_icc = profile_bytes is not None
    try:
        if has_embedded_icc:
            if not isinstance(profile_bytes, bytes) or not profile_bytes:
                raise Stage1Error("embedded ICC profile is empty or malformed")
            source_profile = ImageCms.ImageCmsProfile(BytesIO(profile_bytes))
            target_profile = ImageCms.createProfile("sRGB")
            source_space = str(source_profile.profile.xcolor_space or "").strip().upper()
            # Pillow's transform builder requires the image mode to agree
            # with the profile connection space.  Some EVA JPEGs carry a
            # grayscale pixel mode with an RGB ICC tag (and vice versa); make
            # the smallest explicit mode adaptation before the one ICC
            # conversion, while always emitting RGB/sRGB pixels.
            if source_space == "RGB" and oriented.mode != "RGB":
                oriented = oriented.convert("RGB")
            elif source_space in {"GRAY", "GREY"} and oriented.mode != "L":
                oriented = oriented.convert("L")
            elif source_space not in {"RGB", "GRAY", "GREY"}:
                raise Stage1Error(f"unsupported embedded ICC colour space: {source_space or 'unknown'}")
            normalised = ImageCms.profileToProfile(
                oriented,
                source_profile,
                target_profile,
                outputMode="RGB",
            )
        else:
            normalised = oriented.convert("RGB")
        normalised.load()
    except Stage1Error:
        raise
    except Exception as exc:  # noqa: BLE001 - unsupported ICC/mode must fail closed.
        raise Stage1Error("unsupported or malformed embedded ICC profile") from exc
    return normalised, orientation_applied, has_embedded_icc


def _inspect_preprocessing(path: Path) -> tuple[bool, bool]:
    try:
        with Image.open(path) as image:
            normalised, orientation_applied, has_embedded_icc = _normalise_source_image(image)
            normalised.close()
            return orientation_applied, has_embedded_icc
    except Stage1Error:
        raise
    except Exception as exc:  # noqa: BLE001 - all decoder errors are input failures.
        raise Stage1Error(f"cannot decode image for preprocessing inspection: {path.name}") from exc


def _image_tensor(record: DataRecord, input_size: tuple[int, int]) -> Tensor:
    _assert_no_symlink_components(record.path)
    _regular_file(record.path, label=f"image {record.image_id}")
    if _sha256_file(record.path) != record.image_sha256:
        raise Stage1Error(f"image changed after admission: {record.image_id}")
    try:
        with Image.open(record.path) as image:
            normalised, _orientation_applied, _has_embedded_icc = _normalise_source_image(image)
            resized = normalised.resize((input_size[1], input_size[0]), Image.Resampling.BILINEAR)
            raw = torch.frombuffer(bytearray(resized.tobytes()), dtype=torch.uint8)
            resized.close()
            normalised.close()
    except Stage1Error:
        raise
    except Exception as exc:  # noqa: BLE001 - Pillow and buffer errors are input failures.
        raise Stage1Error(f"cannot decode image {record.image_id}") from exc
    return (raw.reshape(input_size[0], input_size[1], 3).to(dtype=torch.float32) / 255.0).permute(2, 0, 1).contiguous()


def _batch(records: Sequence[DataRecord], indices: Sequence[int], input_size: tuple[int, int], device: torch.device) -> tuple[Tensor, Tensor, Tensor]:
    images = torch.stack([_image_tensor(records[index], input_size) for index in indices]).to(device)
    labels = torch.tensor([records[index].labels for index in indices], dtype=torch.float32, device=device)
    categories = torch.tensor([records[index].category for index in indices], dtype=torch.long, device=device)
    return images, labels, categories


def _loss_from_outputs(outputs: Mapping[str, Tensor], labels: Tensor, categories: Tensor, category_loss_weight: float) -> tuple[Tensor, Tensor, Tensor]:
    regression = F.smooth_l1_loss(outputs["regression"], labels)
    category = F.cross_entropy(outputs["category"], categories)
    return regression + category_loss_weight * category, regression, category


def _loss_and_predictions(model: EVAStage1Model, images: Tensor, labels: Tensor, categories: Tensor, category_loss_weight: float) -> tuple[Tensor, Tensor, Tensor]:
    return _loss_from_outputs(model(images), labels, categories, category_loss_weight)


def _fit_metrics(model: EVAStage1Model, records: Sequence[DataRecord], indices: Sequence[int], config: Stage1Config, device: torch.device) -> dict[str, Any]:
    if not indices:
        raise Stage1Error("fit records are empty")
    was_training = model.training
    model.eval()
    total_loss = 0.0
    total_regression = 0.0
    total_category = 0.0
    absolute = [0.0] * len(VOTE_FIELDS)
    correct = 0
    count = 0
    with torch.no_grad():
        for start in range(0, len(indices), config.batch_size):
            chunk = indices[start:start + config.batch_size]
            images, labels, categories = _batch(records, chunk, config.input_size, device)
            outputs = model(images)
            loss, regression, category = _loss_from_outputs(outputs, labels, categories, config.category_loss_weight)
            total_loss += float(loss.detach().cpu()) * len(chunk)
            total_regression += float(regression.detach().cpu()) * len(chunk)
            total_category += float(category.detach().cpu()) * len(chunk)
            predicted = outputs["regression"].detach().cpu()
            absolute = [old + float(value) for old, value in zip(absolute, torch.abs(predicted - labels.cpu()).sum(dim=0).tolist())]
            correct += int((outputs["category"].argmax(dim=1) == categories).sum().detach().cpu())
            count += len(chunk)
    if was_training:
        model.train()
    source_mae = {field: absolute[index] / count * (10.0 if field == "score" else 3.0) for index, field in enumerate(VOTE_FIELDS)}
    normalized_mae = {field: absolute[index] / count for index, field in enumerate(VOTE_FIELDS)}
    return {
        "loss": total_loss / count,
        "regression_loss": total_regression / count,
        "category_loss": total_category / count,
        "count": count,
        "mae_normalized": normalized_mae,
        "mae_source_scale": source_mae,
        "category_accuracy": correct / count,
    }


def _git_context() -> dict[str, Any]:
    def run(args: list[str]) -> str | None:
        try:
            result = subprocess.run(args, cwd=REPO_ROOT, capture_output=True, text=True, check=False)
        except OSError:
            return None
        return result.stdout.strip() if result.returncode == 0 else None
    head = run(["git", "rev-parse", "HEAD"])
    status = run(["git", "status", "--porcelain", "--untracked-files=all"])
    return {"head": head or "unavailable", "dirty": bool(status), "status_recorded": status or ""}


def _environment(device: torch.device) -> dict[str, Any]:
    return {
        "python": sys.version.split()[0],
        "platform": platform.platform(),
        "torch": torch.__version__,
        "pillow": getattr(Image, "__version__", "unknown"),
        "cuda_available": bool(torch.cuda.is_available()),
        "cuda_version": torch.version.cuda,
        "device": str(device),
    }


def _code_boundary() -> dict[str, str]:
    paths = {
        "pretrain": REPO_ROOT / PRETRAIN_SOURCE_RELATIVE,
        "model": REPO_ROOT / MODEL_SOURCE_RELATIVE,
        "contract": REPO_ROOT / MANIFEST_RELATIVE,
    }
    return {name: _sha256_file(_regular_file(path, label=name)) for name, path in paths.items()}


def _atomic_bytes(path: Path, payload: bytes) -> str:
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise Stage1Error(f"output is not a regular file: {path}")
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
        raise Stage1Error(f"cannot atomically write {path}") from exc
    return hashlib.sha256(payload).hexdigest()


def _atomic_json(path: Path, value: Mapping[str, Any]) -> str:
    return _atomic_bytes(path, (_canonical_json(value) + "\n").encode("utf-8"))


def _atomic_torch(path: Path, value: Mapping[str, Any]) -> str:
    temporary: Path | None = None
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise Stage1Error(f"checkpoint output is not a regular file: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
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
        raise Stage1Error(f"cannot atomically write torch artifact: {path}") from exc
    return _sha256_file(path)


def _resolve_device(value: str) -> torch.device:
    if value == "cpu":
        return torch.device("cpu")
    if value == "cuda":
        if not torch.cuda.is_available():
            raise Stage1Error("CUDA was requested but is unavailable")
        return torch.device("cuda")
    if value == "mps":
        if not getattr(torch.backends, "mps", None) or not torch.backends.mps.is_available():
            raise Stage1Error("MPS was requested but is unavailable")
        return torch.device("mps")
    if value != "auto":
        raise Stage1Error("device must be auto, cpu, cuda, or mps")
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
        raise Stage1Error("Torch cannot enable deterministic algorithms for this runtime") from exc


def _checkpoint_context(config: Stage1Config, admission: DataAdmission, model_contract: Mapping[str, Any], model_contract_hash: str, code_boundary: Mapping[str, str]) -> dict[str, Any]:
    return {
        "config_sha256": config.source_bytes_sha256,
        "data_hash": admission.data_hash,
        "manifest_sha256": admission.manifest_sha256,
        "receipt_sha256": admission.receipt_sha256,
        "model_contract": dict(model_contract),
        "model_contract_sha256": model_contract_hash,
        "code_boundary": dict(code_boundary),
        "fit_semantics": "all admitted P3 silver records; no family IDs, no validation split, no release/locked split, and no model-selection claim",
    }


def _check_checkpoint_context(payload: Mapping[str, Any], expected: Mapping[str, Any]) -> None:
    if payload.get("schema_id") != CHECKPOINT_SCHEMA_ID:
        raise Stage1Error("checkpoint schema is unsupported")
    actual = payload.get("context")
    if actual != expected:
        raise Stage1Error("resume rejected: config, data, model contract, fit semantics, or code boundary changed")
    epoch = payload.get("epoch")
    if type(epoch) is not int or epoch < 1:
        raise Stage1Error("checkpoint epoch is invalid")


def _checkpoint_filename_epoch(path: Path) -> int:
    match = CHECKPOINT_FILENAME_RE.fullmatch(path.name)
    if match is None:
        raise Stage1Error(f"checkpoint filename is not canonical: {path.name}")
    return int(match.group("epoch"))


def _run_receipt(run_root: Path, context: Mapping[str, Any]) -> Mapping[str, Any]:
    receipt_path = run_root / "receipt.json"
    _regular_file(receipt_path, label="run receipt")
    receipt = _read_json(receipt_path)
    if not isinstance(receipt, Mapping) or receipt.get("schema_id") != STAGE1_RECEIPT_SCHEMA_ID or receipt.get("schema_version") != "1.0.0":
        raise Stage1Error("resume receipt schema is unsupported")
    if receipt.get("config_sha256") != context["config_sha256"] or receipt.get("data_hash") != context["data_hash"] or receipt.get("model_contract_sha256") != context["model_contract_sha256"] or receipt.get("code_boundary") != context["code_boundary"]:
        raise Stage1Error("resume rejected: run receipt context changed")
    if receipt.get("status") not in {"in_progress", "complete"}:
        raise Stage1Error("resume receipt status is invalid")
    if not isinstance(receipt.get("started_at"), str) or not receipt["started_at"]:
        raise Stage1Error("resume receipt has no original started_at")
    return receipt


def _checkpoint_from_receipt(run_root: Path, receipt: Mapping[str, Any], *, explicit: str | Path | None) -> tuple[Path, int, str]:
    checkpoints = run_root / "checkpoints"
    if checkpoints.is_symlink() or not checkpoints.is_dir():
        raise Stage1Error("resume requested but checkpoints directory is missing")
    ledger = receipt.get("last_checkpoint")
    if not isinstance(ledger, Mapping):
        raise Stage1Error("resume receipt has no last_checkpoint ledger")
    relative = ledger.get("path")
    expected_sha = _valid_sha(ledger.get("sha256"), "resume receipt last_checkpoint.sha256")
    if not isinstance(relative, str) or PurePosixPath(relative).parts[:1] != ("checkpoints",):
        raise Stage1Error("resume receipt last_checkpoint path is not under checkpoints")
    relative_path = PurePosixPath(relative)
    if relative_path.as_posix() != relative or len(relative_path.parts) != 2:
        raise Stage1Error("resume receipt last_checkpoint path is not canonical")
    ledger_path = Path(os.path.abspath(run_root.joinpath(*relative_path.parts)))
    try:
        ledger_path.relative_to(checkpoints)
    except ValueError as exc:
        raise Stage1Error("resume receipt last_checkpoint escapes checkpoints") from exc
    _assert_no_symlink_components(ledger_path)
    ledger_epoch = _checkpoint_filename_epoch(ledger_path)
    if explicit is not None and str(explicit) != "latest":
        requested = Path(explicit).expanduser()
        if requested.is_absolute():
            requested_path = Path(os.path.abspath(requested))
        elif len(requested.parts) == 1:
            requested_path = Path(os.path.abspath(checkpoints / requested))
        else:
            requested_path = Path(os.path.abspath(run_root / requested))
        try:
            requested_path.relative_to(checkpoints)
        except ValueError as exc:
            raise Stage1Error("explicit resume checkpoint must stay under run_root/checkpoints") from exc
        if requested_path != ledger_path:
            raise Stage1Error("explicit resume checkpoint does not match receipt last_checkpoint")
    if not ledger_path.is_file() or ledger_path.is_symlink():
        raise Stage1Error("receipt last_checkpoint file is missing or unsafe")
    actual_sha = _sha256_file(ledger_path)
    if actual_sha != expected_sha:
        raise Stage1Error("resume checkpoint SHA-256 does not match receipt ledger")
    return ledger_path, ledger_epoch, expected_sha


def _load_checkpoint(path: Path, expected: Mapping[str, Any], expected_epoch: int, configured_epochs: int) -> Mapping[str, Any]:
    _regular_file(path, label="resume checkpoint")
    filename_epoch = _checkpoint_filename_epoch(path)
    if filename_epoch != expected_epoch or expected_epoch > configured_epochs:
        raise Stage1Error("resume checkpoint epoch does not match its filename/config")
    try:
        payload = torch.load(path, map_location="cpu", weights_only=True)
    except (OSError, RuntimeError, EOFError, ValueError, pickle.UnpicklingError) as exc:
        raise Stage1Error("cannot load resume checkpoint with weights_only=True") from exc
    if not isinstance(payload, Mapping):
        raise Stage1Error("resume checkpoint must contain an object")
    _check_checkpoint_context(payload, expected)
    return payload


def _final_payload(model: EVAStage1Model, config: Stage1Config, model_contract: Mapping[str, Any], model_contract_hash: str) -> dict[str, Any]:
    return {
        "schema_id": ENCODER_ARTIFACT_SCHEMA_ID,
        "schema_version": "1.0.0",
        "kind": "disposable_research_encoder_state_only",
        "source_model": "CandidateA.full_frame_backbone",
        "candidate": config.candidate,
        "backbone": config.backbone,
        "model_contract": dict(model_contract),
        "model_contract_sha256": model_contract_hash,
        "state_dict": {key: value.detach().cpu() for key, value in model.encoder.state_dict().items()},
        "contains_set_runtime_heads": False,
        "contains_eva_auxiliary_heads": False,
        "runtime_import_boundary": "not_a_SETCompositionNet_runtime_checkpoint; attach only after M3 human-gold training",
        "research_only": True,
        "human_gold": False,
        "release_admissible": False,
        "disclaimer": "EVA is AVA-derived; underlying image rights are unresolved. This warm-start does not select a production candidate or create Camera Coach labels.",
    }


def _verify_encoder_artifact(path: Path, *, model_contract_hash: str, expected_sha256: str | None = None) -> str:
    _regular_file(path, label="encoder artifact")
    actual_sha256 = _sha256_file(path)
    if expected_sha256 is not None and actual_sha256 != expected_sha256:
        raise Stage1Error("encoder artifact SHA-256 does not match receipt")
    try:
        payload = torch.load(path, map_location="cpu", weights_only=True)
    except (OSError, RuntimeError, EOFError, ValueError, pickle.UnpicklingError) as exc:
        raise Stage1Error("cannot verify encoder artifact with weights_only=True") from exc
    if not isinstance(payload, Mapping) or payload.get("schema_id") != ENCODER_ARTIFACT_SCHEMA_ID or payload.get("model_contract_sha256") != model_contract_hash:
        raise Stage1Error("encoder artifact metadata is not the expected Stage-1 contract")
    if payload.get("contains_set_runtime_heads") is not False or payload.get("contains_eva_auxiliary_heads") is not False:
        raise Stage1Error("encoder artifact contains forbidden runtime or auxiliary heads")
    state_dict = payload.get("state_dict")
    if not isinstance(state_dict, Mapping) or not state_dict or any(str(key).startswith(("auxiliary.", "heads.", "fusion.")) for key in state_dict):
        raise Stage1Error("encoder artifact state_dict is not encoder-only")
    return actual_sha256


def _final_artifact_sha(value: object, *, required: bool) -> str | None:
    """Validate the receipt attestation for the fixed encoder export path."""

    if value is None:
        if required:
            raise Stage1Error("complete receipt has no final_artifact attestation")
        return None
    if not isinstance(value, Mapping) or value.get("path") != "encoder-final.pt" or value.get("kind") != ENCODER_ARTIFACT_SCHEMA_ID:
        raise Stage1Error("final_artifact attestation is malformed")
    return _valid_sha(value.get("sha256"), "final_artifact.sha256")


def train(
    config_path: Path,
    data_root: Path,
    run_dir: Path,
    *,
    resume: Path | str | None = None,
    device_name: str = "auto",
    stop_after_epoch: int | None = None,
    encoder_factory: Callable[[scm.SETCompositionNetManifest], nn.Module] | None = None,
) -> dict[str, Any]:
    config = Stage1Config.load(config_path)
    admission = admit_data(data_root, config)
    run_root = _external_directory(run_dir, create=True)
    contract, model_contract, model_contract_hash = _load_model_contract(config)
    code_boundary = _code_boundary()
    context = _checkpoint_context(config, admission, model_contract, model_contract_hash, code_boundary)
    if stop_after_epoch is not None and (stop_after_epoch < 1 or stop_after_epoch > config.epochs):
        raise Stage1Error("stop_after_epoch must be within the configured epoch range")
    resume_receipt: Mapping[str, Any] | None = None
    resume_path: Path | None = None
    checkpoint_epoch = 0
    if resume is None:
        existing = [path for path in run_root.iterdir() if path.name not in {".DS_Store"}]
        if existing:
            raise Stage1Error("run directory is non-empty; pass --resume to continue it")
        started_at = datetime.now(timezone.utc).isoformat()
    else:
        resume_receipt = _run_receipt(run_root, context)
        resume_path, checkpoint_epoch, _checkpoint_sha256 = _checkpoint_from_receipt(run_root, resume_receipt, explicit=resume)
        started_at = str(resume_receipt["started_at"])
    device = _resolve_device(device_name)
    _set_determinism(config.seed, device)
    encoder = encoder_factory(contract) if encoder_factory is not None else _candidate_a_encoder(contract)
    model = EVAStage1Model(encoder).to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=config.learning_rate, weight_decay=config.weight_decay)
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
            raise Stage1Error("resume checkpoint state is incompatible with the current model") from exc
    checkpoints_dir = run_root / "checkpoints"
    checkpoints_dir.mkdir(parents=True, exist_ok=True)
    metrics_path = run_root / "metrics.jsonl"
    if start_epoch > config.epochs:
        final_path = run_root / "encoder-final.pt"
        receipt_final = resume_receipt.get("final_artifact") if resume_receipt is not None else None
        expected_final_sha = _final_artifact_sha(
            receipt_final,
            required=resume_receipt is not None and resume_receipt.get("status") == "complete",
        )
        if resume_receipt is not None and resume_receipt.get("status") == "in_progress":
            # A crash can leave an old or attacker-replaced valid-looking
            # encoder beside the receipt.  Never attest that file: rebuild the
            # export from the already verified ledger checkpoint state, then
            # verify the bytes that will be recorded as complete.
            final_sha256 = _atomic_torch(final_path, _final_payload(model, config, model_contract, model_contract_hash))
            _verify_encoder_artifact(final_path, model_contract_hash=model_contract_hash, expected_sha256=expected_final_sha or final_sha256)
        elif final_path.is_file():
            final_sha256 = _verify_encoder_artifact(final_path, model_contract_hash=model_contract_hash, expected_sha256=expected_final_sha)
        else:
            final_sha256 = _atomic_torch(final_path, _final_payload(model, config, model_contract, model_contract_hash))
            # If an earlier completion attested a hash but the file was lost,
            # reconstruction is accepted only when deterministic state yields
            # that exact attested artifact.
            _verify_encoder_artifact(final_path, model_contract_hash=model_contract_hash, expected_sha256=expected_final_sha or final_sha256)
        receipt = _receipt(
            config, admission, context, model_contract, model_contract_hash, code_boundary, device, history,
            resume_path if resume_path is not None else checkpoints_dir / f"epoch-{config.epochs:04d}.pt",
            _sha256_file(resume_path) if resume_path is not None else "", completed=True, started_at=started_at,
        )
        receipt["final_artifact"] = {"path": "encoder-final.pt", "sha256": final_sha256, "kind": ENCODER_ARTIFACT_SCHEMA_ID}
        _atomic_json(run_root / "receipt.json", receipt)
        return receipt
    records = admission.records
    fit_indices = list(range(len(records)))
    for epoch in range(start_epoch, config.epochs + 1):
        model.train()
        generator = torch.Generator(device="cpu")
        generator.manual_seed(config.seed + epoch)
        order = torch.randperm(len(fit_indices), generator=generator).tolist()
        total_loss = 0.0
        total_regression = 0.0
        total_category = 0.0
        batches = 0
        examples = 0
        for start in range(0, len(order), config.batch_size):
            positions = order[start:start + config.batch_size]
            if len(positions) < config.batch_size and len(order) >= config.batch_size:
                # CandidateA uses BatchNorm at its final feature map.  Drop a
                # singleton tail deterministically rather than changing the
                # model's normalization semantics.
                continue
            indices = [fit_indices[position] for position in positions]
            images, labels, categories = _batch(records, indices, config.input_size, device)
            optimizer.zero_grad(set_to_none=True)
            loss, regression, category = _loss_and_predictions(model, images, labels, categories, config.category_loss_weight)
            loss.backward()
            optimizer.step()
            total_loss += float(loss.detach().cpu()) * len(indices)
            total_regression += float(regression.detach().cpu()) * len(indices)
            total_category += float(category.detach().cpu()) * len(indices)
            examples += len(indices)
            batches += 1
        if batches == 0:
            raise Stage1Error("no complete training batch was available")
        fit = _fit_metrics(model, records, fit_indices, config, device)
        metric = {
            "schema_id": "camera-eva-stage1-metric-v1",
            "epoch": epoch,
            "train_loss": total_loss / examples,
            "train_regression_loss": total_regression / examples,
            "train_category_loss": total_category / examples,
            "train_examples": examples,
            "train_batches": batches,
            "fit": fit,
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
            "auxiliary_heads_disposable": True,
        }
        checkpoint_path = checkpoints_dir / f"epoch-{epoch:04d}.pt"
        checkpoint_sha256 = _atomic_torch(checkpoint_path, checkpoint)
        metric["checkpoint_sha256"] = checkpoint_sha256
        _atomic_bytes(metrics_path, ("".join(_canonical_json(row) + "\n" for row in history)).encode("utf-8"))
        # The durable receipt is intentionally in_progress even for the last
        # epoch.  The final encoder is written and verified before completion.
        receipt = _receipt(
            config, admission, context, model_contract, model_contract_hash, code_boundary, device, history,
            checkpoint_path, checkpoint_sha256, completed=False, started_at=started_at,
        )
        _atomic_json(run_root / "receipt.json", receipt)
        if stop_after_epoch is not None and epoch >= stop_after_epoch:
            break
    if history[-1]["epoch"] < config.epochs:
        return _read_json(run_root / "receipt.json")
    final_path = run_root / "encoder-final.pt"
    if final_path.exists():
        raise Stage1Error("final encoder exists before completion; use resume to verify it")
    final_sha256 = _atomic_torch(final_path, _final_payload(model, config, model_contract, model_contract_hash))
    _verify_encoder_artifact(final_path, model_contract_hash=model_contract_hash, expected_sha256=final_sha256)
    final_checkpoint = checkpoints_dir / f"epoch-{config.epochs:04d}.pt"
    final_checkpoint_sha256 = _sha256_file(final_checkpoint)
    receipt = _receipt(
        config, admission, context, model_contract, model_contract_hash, code_boundary, device, history,
        final_checkpoint, final_checkpoint_sha256, completed=True, started_at=started_at,
    )
    receipt["final_artifact"] = {"path": "encoder-final.pt", "sha256": final_sha256, "kind": ENCODER_ARTIFACT_SCHEMA_ID}
    _atomic_json(run_root / "receipt.json", receipt)
    return receipt


def _receipt(
    config: Stage1Config,
    admission: DataAdmission,
    context: Mapping[str, Any],
    model_contract: Mapping[str, Any],
    model_contract_hash: str,
    code_boundary: Mapping[str, str],
    device: torch.device,
    history: Sequence[Mapping[str, Any]],
    checkpoint_path: Path,
    checkpoint_sha256: str,
    *,
    completed: bool,
    started_at: str,
) -> dict[str, Any]:
    try:
        checkpoint_relative = checkpoint_path.resolve(strict=True).relative_to((checkpoint_path.parents[1]).resolve(strict=True))
    except (OSError, ValueError) as exc:
        raise Stage1Error("receipt checkpoint must be inside the run checkpoints directory") from exc
    if checkpoint_relative.parts[:1] != ("checkpoints",) or len(checkpoint_relative.parts) != 2:
        raise Stage1Error("receipt checkpoint path is not canonical")
    return {
        "schema_id": STAGE1_RECEIPT_SCHEMA_ID,
        "schema_version": "1.0.0",
        "status": "complete" if completed else "in_progress",
        "started_at": started_at,
        "finished_at": datetime.now(timezone.utc).isoformat() if completed else None,
        "lane": "eva-stage1-encoder-warm-start",
        "candidate": config.candidate,
        "backbone": config.backbone,
        "source": {"receipt_schema": RECEIPT_SCHEMA_ID, "manifest": config.manifest_relative, "manifest_sha256": admission.manifest_sha256, "receipt": config.receipt_relative, "receipt_sha256": admission.receipt_sha256, "records_full": admission.full_record_count, "records_selected": len(admission.records)},
        "preprocessing": {
            "rule": "integer EXIF orientation tags 1..8 are handled by ImageOps.exif_transpose exactly once before resize; missing/unrecognized tags (including Pillow's legacy 0 sentinel) follow no-op behavior; numeric orientation below 0 or above 8 is rejected; embedded ICC profiles are converted to sRGB with Pillow ImageCms; untagged images use the documented sRGB assumption; malformed or unsupported ICC inputs fail closed",
            "counts": dict(admission.preprocessing_counts),
        },
        "fit": {"records": len(admission.records), "metrics_scope": "training fit metrics only; P3 supplies no family IDs, so this auxiliary warm-start has no validation split and makes no model-selection claim"},
        "counts": {"fit": len(admission.records), "epochs_completed": len(history)},
        "config_sha256": config.source_bytes_sha256,
        "data_hash": admission.data_hash,
        "model_contract": dict(model_contract),
        "model_contract_sha256": model_contract_hash,
        "model_contract_sha256_definition": "SHA-256 of canonical JSON model_contract in this receipt",
        "code_boundary": dict(code_boundary),
        "contract_source_sha256": code_boundary.get("contract"),
        "contract_source_sha256_definition": "SHA-256 of the tracked set_composition_net_v1.json bytes; this is distinct from model_contract_sha256",
        "git": _git_context(),
        "environment": _environment(device),
        "seed": config.seed,
        "training": {"epochs_configured": config.epochs, "batch_size": config.batch_size, "learning_rate": config.learning_rate, "weight_decay": config.weight_decay, "category_loss_weight": config.category_loss_weight, "normalization": "score=(x-0)/10; difficulty/visual/composition/quality/semantic=(x-1)/3", "uncertainty_weighting": "none"},
        "last_checkpoint": {"path": checkpoint_relative.as_posix(), "sha256": checkpoint_sha256},
        "history": list(history),
        "research_only": True,
        "human_gold": False,
        "release_admissible": False,
        "disclaimer": "EVA supervision is source-native auxiliary pretraining only. No SET scene/issue/action/good-frame/abstention/risk/delta head is supervised. No success threshold is claimed.",
    }


class _TinyEncoder(nn.Module):
    """Only used by the local self-test to keep it CPU-small."""

    output_dim = 8

    def __init__(self) -> None:
        super().__init__()
        self.layers = nn.Sequential(nn.Conv2d(3, 8, 3, stride=8), nn.ReLU(), nn.AdaptiveAvgPool2d(1))

    def forward(self, image: Tensor) -> Tensor:
        return self.layers(image).flatten(1)


def _self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="eva-stage1-") as temp_dir:
        base = Path(temp_dir).resolve()
        data_root = base / "data"
        run_root = base / "run"
        config_path = base / "config.json"
        (data_root / "images").mkdir(parents=True)
        (data_root / "receipts").mkdir()
        rows: list[dict[str, Any]] = []

        def make_image(image_id: str, color: tuple[int, int, int]) -> Path:
            suffix = ".jpg" if image_id in {"01", "02", "03"} else ".png"
            path = data_root / "images" / f"{image_id}{suffix}"
            image = Image.new("RGB", (12, 10), color)
            save_kwargs: dict[str, Any] = {}
            if image_id == "01":
                # JPEG dimensions swap under orientation 6.  The pipeline
                # must apply this tag once before its fixed-size resize.
                exif = Image.Exif()
                exif[274] = 6
                save_kwargs.update(format="JPEG", quality=100, exif=exif.tobytes())
            elif image_id == "02":
                # A valid embedded profile exercises the ImageCms path.  The
                # production receipt records this conversion separately from
                # the untagged-sRGB assumption used by the PNG fixtures.
                profile = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
                save_kwargs.update(format="JPEG", quality=100, icc_profile=profile)
            elif image_id == "03":
                # Orientation 1 is a valid identity tag and must not be
                # counted as a transformed image.
                exif = Image.Exif()
                exif[274] = 1
                save_kwargs.update(format="JPEG", quality=100, exif=exif.tobytes())
            else:
                save_kwargs["format"] = "PNG"
            image.save(path, **save_kwargs)
            image.close()
            return path

        for image_id, color in (("01", (20, 40, 80)), ("02", (80, 40, 20)), ("03", (40, 90, 30)), ("04", (90, 30, 70))):
            path = make_image(image_id, color)
            rows.append({
                "schema_id": "camera-eva-silver-v1", "schema_version": "1.0.0", "dataset_kind": "auxiliary_aesthetic_composition",
                "image_id": image_id, "relative_path": path.relative_to(data_root).as_posix(), "image_sha256": _sha256_file(path),
                "provenance": {"source_id": "eva_official"}, "content_category": (int(image_id) % CATEGORY_COUNT) + 1,
                "counts": {"votes": 1, "unique_voters": 1},
                "aggregates": {field: {"mean": (5.0 if field == "score" else 2.5), "median": 2.5, "std": 0.0, "mad": 0.0} for field in VOTE_FIELDS},
                "uncertainty": {"conflict": False}, "label_boundary": "silver_reference_only_not_camera_coach_action_label",
                "intake_tier": "research_only", "human_gold": False, "release_admissible": False,
            })
        rows.sort(key=lambda row: row["image_id"])
        manifest_text = "".join(_canonical_json(row) + "\n" for row in rows)
        manifest_path = data_root / "silver-manifest.jsonl"
        manifest_path.write_text(manifest_text, encoding="utf-8")
        manifest_sha256 = _sha256_file(manifest_path)
        receipt = {
            "schema_id": RECEIPT_SCHEMA_ID, "schema_version": "1.0.0", "output": {"path": "silver-manifest.jsonl", "sha256": manifest_sha256, "records": len(rows)},
            "colab_export": {
                "join_key": "image_id", "image_path_field": "relative_path",
                "upstream_scale": {
                    "score": {"min": 0, "max": 10}, "difficulty": {"min": 1, "max": 4},
                    "attributes": {"min": 1, "max": 4, "fields": list(VOTE_FIELDS[2:])},
                },
            }, "label_boundary": "research_only_silver_reference_not_camera_coach_action_label",
            "intake_tier": "research_only", "human_gold": False, "release_admissible": False,
        }
        (data_root / "receipts/eva-silver-receipt.json").write_text(_canonical_json(receipt) + "\n", encoding="utf-8")
        contract_path = REPO_ROOT / MANIFEST_RELATIVE
        config = {
            "schema_id": CONFIG_SCHEMA_ID, "schema_version": CONFIG_SCHEMA_VERSION, "seed": 7, "input_size": [320, 320],
            "data": {"manifest": "silver-manifest.jsonl", "receipt": "receipts/eva-silver-receipt.json"},
            "training": {"epochs": 2, "batch_size": 2, "learning_rate": 0.001, "weight_decay": 0.0, "category_loss_weight": 1.0, "max_records": 0},
            "model": {"candidate": "candidate_a_dual_branch", "backbone": "full_frame_backbone", "manifest_path": MANIFEST_RELATIVE, "manifest_sha256": _sha256_file(contract_path)},
        }
        config_path.write_text(_canonical_json(config) + "\n", encoding="utf-8")
        admission = admit_data(data_root, Stage1Config.load(config_path))
        expected_preprocessing_counts = {
            "orientation_transformed_images": 1,
            "embedded_icc_images": 1,
            "embedded_icc_converted_to_srgb_images": 1,
            "untagged_srgb_assumption_images": 3,
        }
        assert admission.preprocessing_counts == expected_preprocessing_counts, admission.preprocessing_counts
        with Image.open(data_root / "images/01.jpg") as oriented_source:
            oriented, orientation_applied, has_embedded_icc = _normalise_source_image(oriented_source)
            assert orientation_applied is True and has_embedded_icc is False and oriented.size == (10, 12)
            oriented.close()
        with Image.open(data_root / "images/02.jpg") as icc_source:
            normalised, orientation_applied, has_embedded_icc = _normalise_source_image(icc_source)
            assert orientation_applied is False and has_embedded_icc is True and normalised.mode == "RGB"
            normalised.close()
        with Image.open(data_root / "images/03.jpg") as identity_source:
            identity, orientation_applied, has_embedded_icc = _normalise_source_image(identity_source)
            assert orientation_applied is False and has_embedded_icc is False and identity.size == (12, 10)
            identity.close()
        malformed_icc = data_root / "images/malformed-icc.jpg"
        Image.new("RGB", (8, 8), (1, 2, 3)).save(malformed_icc, format="JPEG", icc_profile=b"not-an-icc-profile")
        try:
            with Image.open(malformed_icc) as malformed_source:
                _normalise_source_image(malformed_source)
        except Stage1Error as exc:
            assert "ICC" in str(exc)
        else:
            raise AssertionError("malformed embedded ICC profile was accepted")
        unsupported_orientation = data_root / "images/unsupported-orientation.jpg"
        unsupported_exif = Image.Exif()
        unsupported_exif[274] = 9
        Image.new("RGB", (8, 8), (1, 2, 3)).save(unsupported_orientation, format="JPEG", exif=unsupported_exif.tobytes())
        try:
            with Image.open(unsupported_orientation) as unsupported_source:
                _normalise_source_image(unsupported_source)
        except Stage1Error as exc:
            assert "EXIF orientation" in str(exc)
        else:
            raise AssertionError("out-of-range EXIF orientation was accepted")
        first = train(config_path, data_root, run_root, device_name="cpu", stop_after_epoch=1, encoder_factory=lambda _contract: _TinyEncoder())
        assert first["status"] == "in_progress" and (run_root / "checkpoints/epoch-0001.pt").is_file()
        checkpoint = run_root / "checkpoints/epoch-0001.pt"
        checkpoint_bytes = checkpoint.read_bytes()
        checkpoint.write_bytes(checkpoint_bytes + b"tamper")
        try:
            train(config_path, data_root, run_root, resume="latest", device_name="cpu", encoder_factory=lambda _contract: _TinyEncoder())
        except Stage1Error as exc:
            assert "checkpoint SHA-256" in str(exc)
        else:
            raise AssertionError("tampered checkpoint was loaded")
        checkpoint.write_bytes(checkpoint_bytes)
        try:
            train(config_path, data_root, run_root, resume="../epoch-0001.pt", device_name="cpu", encoder_factory=lambda _contract: _TinyEncoder())
        except Stage1Error as exc:
            assert "under run_root/checkpoints" in str(exc) or "does not match" in str(exc)
        else:
            raise AssertionError("checkpoint path escape was accepted")
        try:
            train(config_path, data_root, run_root, resume="checkpoints/epoch-0002.pt", device_name="cpu", encoder_factory=lambda _contract: _TinyEncoder())
        except Stage1Error as exc:
            assert "does not match" in str(exc) or "missing" in str(exc)
        else:
            raise AssertionError("non-ledger checkpoint path was accepted")
        final = train(config_path, data_root, run_root, resume="latest", device_name="cpu", encoder_factory=lambda _contract: _TinyEncoder())
        assert final["status"] == "complete" and (run_root / "encoder-final.pt").is_file()
        exported = torch.load(run_root / "encoder-final.pt", map_location="cpu", weights_only=True)
        assert exported["contains_set_runtime_heads"] is False and exported["contains_eva_auxiliary_heads"] is False
        assert all(not key.startswith("auxiliary.") for key in exported["state_dict"])
        assert final["counts"] == {"fit": 4, "epochs_completed": 2}
        assert "partition" not in final and all("dev" not in metric and "eval" not in metric for metric in final["history"])
        started_at = final["started_at"]
        # Simulate a crash after the final encoder write but before receipt
        # completion.  Place a different valid-looking Stage-1 artifact in the
        # crash window: resume must replace it from the verified checkpoint,
        # not attest its metadata/hash, while retaining the original start time.
        replaced_final = dict(exported)
        replaced_state = {key: value.clone() for key, value in exported["state_dict"].items()}
        first_state_key = next(iter(replaced_state))
        replaced_state[first_state_key] = replaced_state[first_state_key] + 1.0
        replaced_final["state_dict"] = replaced_state
        _atomic_torch(run_root / "encoder-final.pt", replaced_final)
        replaced_sha = _sha256_file(run_root / "encoder-final.pt")
        receipt_path = run_root / "receipt.json"
        interrupted = dict(final)
        interrupted["status"] = "in_progress"
        interrupted["finished_at"] = None
        interrupted.pop("final_artifact", None)
        _atomic_json(receipt_path, interrupted)
        recovered = train(config_path, data_root, run_root, resume="latest", device_name="cpu", encoder_factory=lambda _contract: _TinyEncoder())
        assert recovered["status"] == "complete" and recovered["started_at"] == started_at
        assert recovered["final_artifact"]["sha256"] == _sha256_file(run_root / "encoder-final.pt")
        assert recovered["final_artifact"]["sha256"] != replaced_sha
        image = data_root / "images/01.jpg"
        image.write_bytes(b"tampered")
        try:
            train(config_path, data_root, run_root, resume="latest", device_name="cpu", encoder_factory=lambda _contract: _TinyEncoder())
        except Stage1Error as exc:
            assert "hash mismatch" in str(exc) or "decode" in str(exc)
        else:
            raise AssertionError("tampered image was admitted on resume")
    print("PASS pretrain_eva self-test silver-admission exif-once exif-range-rejection icc-to-srgb fit-only tiny-train checkpoint-ledger-resume tamper-rejection crash-recovery-rebuild encoder-only-export")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", help="run the tiny CPU-only synthetic self-test")
    parser.add_argument("--config", type=Path, help="tracked Stage-1 JSON config")
    parser.add_argument("--data-root", type=Path, help="external EVA silver data root")
    parser.add_argument("--run-dir", type=Path, help="external training run directory")
    parser.add_argument("--resume", nargs="?", const="latest", help="resume from a checkpoint path or the latest checkpoint")
    parser.add_argument("--device", default="auto", choices=("auto", "cpu", "cuda", "mps"))
    parser.add_argument("--stop-after-epoch", type=int, help=argparse.SUPPRESS)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.self_test:
            _self_test()
            return 0
        if args.config is None or args.data_root is None or args.run_dir is None:
            _parser().error("--config, --data-root, and --run-dir are required unless --self-test is used")
        result = train(args.config, args.data_root, args.run_dir, resume=args.resume, device_name=args.device, stop_after_epoch=args.stop_after_epoch)
        print(json.dumps({"status": result.get("status"), "run_dir": str(args.run_dir), "final_artifact": result.get("final_artifact"), "epochs_completed": result.get("counts", {}).get("epochs_completed")}, ensure_ascii=False, sort_keys=True))
        return 0
    except Stage1Error as exc:
        print(f"FAIL {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
