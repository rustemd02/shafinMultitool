"""Offline deterministic training smoke runner for SETCompositionNet-v1.

This is infrastructure evidence only.  It accepts a declared synthetic source,
performs one CPU optimisation step, and writes an immutable run receipt.  It
does not load human data, inspect a holdout, select a candidate, export Core ML,
or enable an iOS route.

Run from the repository root with::

    python3 -m ml.camera_coach.train \
        --config ml/camera_coach/configs/synthetic_dry_run.json \
        --run-dir /private/tmp/setos-m4-006-example
"""

from __future__ import annotations

import argparse
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
from importlib import metadata
import json
from pathlib import Path
import platform
import random
import re
import sys
import uuid
from types import MappingProxyType
from typing import Any

import torch
from torch import Tensor
from torch.nn import functional as F

# Keep both documented module execution and direct ``python train.py`` useful.
if not __package__:
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from ml.camera_coach.models import set_composition_net as set_composition_net_module
from ml.camera_coach.models.set_composition_net import (
    CandidateA,
    CandidateB,
    SETCompositionNetInputs,
    SETCompositionNetManifest,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
MANIFEST_RELATIVE_PATH = "ml/camera_coach/contracts/set_composition_net_v1.json"
MODEL_SOURCE_RELATIVE_PATH = "ml/camera_coach/models/set_composition_net.py"
LOCK_RELATIVE_PATH = "ml/camera_coach/requirements.lock"
MODEL_SOURCE_PATH = REPO_ROOT / MODEL_SOURCE_RELATIVE_PATH
LOCK_PATH = REPO_ROOT / LOCK_RELATIVE_PATH
CONFIG_VERSION = "camera_training.v1"
RECEIPT_VERSION = "camera_training_receipt.v1"
DATASET_GENERATOR_VERSION = "seeded_contract_tensors.v1"
LOSS_DEFINITION = "mean_mse_over_manifest_heads_before_one_sgd_step"
FIRST_STEP_LOSS_TOLERANCE = 1e-7
MAX_SEED = 2**63 - 1
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
LOCK_REQUIREMENT_RE = re.compile(
    r"^(?P<name>[A-Za-z0-9][A-Za-z0-9._-]*)==(?P<version>[^\s]+) "
    r"--hash=sha256:(?P<wheel_sha256>[0-9a-f]{64})$"
)
RUNTIME_LOCK_PACKAGE_NAMES = frozenset(
    {
        "filelock",
        "fsspec",
        "jinja2",
        "markupsafe",
        "mpmath",
        "networkx",
        "sympy",
        "torch",
        "typing-extensions",
    }
)
RUNTIME_LOCK_HEADER = (
    "# camera_runtime_lock.v2",
    "# python-implementation=CPython",
    "# python-version=3.11.9",
    "# platform-system=Darwin",
    "# platform-machine=arm64",
    "--only-binary=:all:",
)


class TrainingError(ValueError):
    """Raised when a run cannot be admitted by the frozen environment."""


class ConfigError(TrainingError):
    """Raised for malformed, unknown, or out-of-range configuration values."""


def _canonical_json(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _canonical_hash(value: object) -> str:
    return hashlib.sha256(_canonical_json(value).encode("utf-8")).hexdigest()


def _file_hash(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise TrainingError(f"cannot hash required file: {path}") from exc
    return digest.hexdigest()


def _tensor_hash(value: Tensor) -> str:
    """Hash tensor metadata and bytes without requiring NumPy."""

    # ``contiguous()`` may return a storage-offset view unchanged.  Clone after
    # canonicalization so unrelated bytes in a larger backing allocation never
    # enter this logical slice's digest.
    tensor = value.detach().to(device="cpu").contiguous().clone()
    digest = hashlib.sha256()
    digest.update(str(tensor.dtype).encode("ascii"))
    digest.update(_canonical_json(list(tensor.shape)).encode("ascii"))
    digest.update(bytes(tensor.untyped_storage()))
    return digest.hexdigest()


def _state_hash(module: torch.nn.Module) -> str:
    digest = hashlib.sha256()
    for name, value in sorted(module.state_dict().items()):
        digest.update(name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(_tensor_hash(value).encode("ascii"))
        digest.update(b"\n")
    return digest.hexdigest()


def _freeze(value: Any) -> Any:
    if isinstance(value, dict):
        return MappingProxyType({key: _freeze(item) for key, item in value.items()})
    if isinstance(value, list):
        return tuple(_freeze(item) for item in value)
    return value


def _thaw(value: Any) -> Any:
    if isinstance(value, Mapping):
        return {key: _thaw(item) for key, item in value.items()}
    if isinstance(value, tuple):
        return [_thaw(item) for item in value]
    return value


def _require_keys(value: object, expected: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ConfigError(f"{label} must be a JSON object")
    actual = set(value)
    if actual != expected:
        missing = sorted(expected - actual)
        extra = sorted(actual - expected)
        raise ConfigError(f"{label} keys drifted; missing={missing}, extra={extra}")
    return value


def _require_string(value: object, label: str, *, non_empty: bool = True) -> str:
    if not isinstance(value, str) or (non_empty and not value.strip()) or "\x00" in value:
        raise ConfigError(f"{label} must be a non-empty string")
    return value


def _require_bool(value: object, label: str) -> bool:
    if type(value) is not bool:
        raise ConfigError(f"{label} must be a boolean")
    return value


def _require_int(value: object, label: str, *, minimum: int, maximum: int) -> int:
    if type(value) is not int or not minimum <= value <= maximum:
        raise ConfigError(f"{label} must be an integer in [{minimum}, {maximum}]")
    return value


def _require_float(value: object, label: str, *, minimum: float, maximum: float) -> float:
    if type(value) not in {int, float} or not minimum < float(value) <= maximum:
        raise ConfigError(f"{label} must be a finite number in ({minimum}, {maximum}]")
    result = float(value)
    if not torch.isfinite(torch.tensor(result)):
        raise ConfigError(f"{label} must be finite")
    return result


def _require_sha256(value: object, label: str) -> str:
    result = _require_string(value, label)
    if SHA256_RE.fullmatch(result) is None:
        raise ConfigError(f"{label} must be a lowercase SHA-256 digest")
    return result


def _load_runtime_lock(expected_hash: str) -> tuple[dict[str, Any], str]:
    actual_hash = _file_hash(LOCK_PATH)
    if actual_hash != expected_hash:
        raise TrainingError(
            f"runtime lock hash mismatch for {LOCK_PATH}: expected {expected_hash}, got {actual_hash}"
        )
    try:
        raw = LOCK_PATH.read_text(encoding="utf-8")
    except OSError as exc:
        raise TrainingError(f"cannot load runtime lock: {LOCK_PATH}") from exc
    if not raw.endswith("\n"):
        raise TrainingError("runtime lock must end with a newline")
    lines = raw.splitlines()
    if tuple(lines[: len(RUNTIME_LOCK_HEADER)]) != RUNTIME_LOCK_HEADER:
        raise TrainingError("runtime lock header drifted")
    packages: list[dict[str, str]] = []
    seen: set[str] = set()
    for line_number, line in enumerate(lines[len(RUNTIME_LOCK_HEADER) :], start=len(RUNTIME_LOCK_HEADER) + 1):
        match = LOCK_REQUIREMENT_RE.fullmatch(line)
        if match is None:
            raise TrainingError(f"runtime lock requirement line {line_number} is not hash locked")
        raw_name = match.group("name")
        name = re.sub(r"[-_.]+", "-", raw_name).lower()
        if name in seen:
            raise TrainingError(f"runtime lock package repeated: {name}")
        seen.add(name)
        packages.append(
            {
                "name": name,
                "version": match.group("version"),
                "wheel_sha256": match.group("wheel_sha256"),
            }
        )
    if seen != RUNTIME_LOCK_PACKAGE_NAMES:
        raise TrainingError(
            f"runtime lock closure drifted; expected={sorted(RUNTIME_LOCK_PACKAGE_NAMES)}, got={sorted(seen)}"
        )
    if [package["name"] for package in packages] != sorted(item["name"] for item in packages):
        raise TrainingError("runtime lock packages must be sorted by normalized name")
    lock = {
        "lock_version": "camera_runtime_lock.v2",
        "lock_kind": "pip_requirements_hashes",
        "python": {"implementation": "CPython", "version": "3.11.9"},
        "platform": {"system": "Darwin", "machine": "arm64"},
        "packages": packages,
    }
    return lock, actual_hash


def _verify_installed_closure(lock: Mapping[str, object]) -> None:
    packages = lock["packages"]
    assert isinstance(packages, list)
    for package in packages:
        assert isinstance(package, dict)
        name = package["name"]
        version = package["version"]
        try:
            distribution = metadata.distribution(name)
        except metadata.PackageNotFoundError as exc:
            raise TrainingError(f"runtime lock package is not installed: {name}") from exc
        if distribution.version != version:
            raise TrainingError(
                f"runtime package version drift for {name}: expected {version}, got {distribution.version}"
            )


@dataclass(frozen=True)
class DatasetConfig:
    kind: str
    path: str
    sha256: str


@dataclass(frozen=True)
class ModelConfig:
    manifest_path: str
    manifest_sha256: str


@dataclass(frozen=True)
class RuntimeConfig:
    python_version: str
    torch_version: str


@dataclass(frozen=True)
class DryRunConfig:
    sample_count: int
    batch_size: int
    steps: int
    learning_rate: float


@dataclass(frozen=True)
class TrainingConfig:
    """Parsed config with frozen nested values and a semantic content hash."""

    config_version: str
    seed: int
    deterministic: bool
    device: str
    candidate: str
    dataset: DatasetConfig
    model: ModelConfig
    runtime: RuntimeConfig
    lock_sha256: str
    output_root: str
    dry_run: DryRunConfig
    _raw: Mapping[str, object]
    config_sha256: str

    @classmethod
    def from_mapping(cls, raw: Mapping[str, object]) -> "TrainingConfig":
        top = _require_keys(
            dict(raw),
            {
                "config_version",
                "seed",
                "deterministic",
                "device",
                "candidate",
                "dataset",
                "model",
                "runtime",
                "lock_sha256",
                "output_root",
                "dry_run",
            },
            "training config",
        )
        config_version = _require_string(top["config_version"], "config_version")
        if config_version != CONFIG_VERSION:
            raise ConfigError(f"config_version must be {CONFIG_VERSION!r}")
        seed = _require_int(top["seed"], "seed", minimum=0, maximum=MAX_SEED)
        deterministic = _require_bool(top["deterministic"], "deterministic")
        if not deterministic:
            raise ConfigError("deterministic must be true for M4-006")
        device = _require_string(top["device"], "device")
        if device != "cpu":
            raise ConfigError("M4-006 admits only device='cpu'")
        candidate = _require_string(top["candidate"], "candidate")
        if candidate not in {CandidateA.candidate_id, CandidateB.candidate_id}:
            raise ConfigError(f"candidate is not an accepted disabled architecture: {candidate!r}")

        dataset_node = _require_keys(top["dataset"], {"kind", "path", "sha256"}, "dataset")
        dataset_kind = _require_string(dataset_node["kind"], "dataset.kind")
        if dataset_kind != "synthetic":
            raise ConfigError("M4-006 accepts only a declared synthetic dataset source")
        dataset = DatasetConfig(
            dataset_kind,
            _require_string(dataset_node["path"], "dataset.path"),
            _require_sha256(dataset_node["sha256"], "dataset.sha256"),
        )

        model_node = _require_keys(top["model"], {"manifest_path", "manifest_sha256"}, "model")
        if model_node["manifest_path"] != MANIFEST_RELATIVE_PATH:
            raise ConfigError(f"model.manifest_path must be {MANIFEST_RELATIVE_PATH!r}")
        model = ModelConfig(
            _require_string(model_node["manifest_path"], "model.manifest_path"),
            _require_sha256(model_node["manifest_sha256"], "model.manifest_sha256"),
        )

        runtime_node = _require_keys(top["runtime"], {"python_version", "torch_version"}, "runtime")
        runtime = RuntimeConfig(
            _require_string(runtime_node["python_version"], "runtime.python_version"),
            _require_string(runtime_node["torch_version"], "runtime.torch_version"),
        )
        lock_sha256 = _require_sha256(top["lock_sha256"], "lock_sha256")

        output_root = _require_string(top["output_root"], "output_root")
        dry_node = _require_keys(
            top["dry_run"],
            {"sample_count", "batch_size", "steps", "learning_rate"},
            "dry_run",
        )
        sample_count = _require_int(dry_node["sample_count"], "dry_run.sample_count", minimum=2, maximum=4)
        batch_size = _require_int(dry_node["batch_size"], "dry_run.batch_size", minimum=1, maximum=16)
        if batch_size > sample_count:
            raise ConfigError("dry_run.batch_size cannot exceed dry_run.sample_count")
        steps = _require_int(dry_node["steps"], "dry_run.steps", minimum=1, maximum=1)
        learning_rate = _require_float(
            dry_node["learning_rate"],
            "dry_run.learning_rate",
            minimum=0.0,
            maximum=1.0,
        )

        semantic_raw = {
            "config_version": config_version,
            "seed": seed,
            "deterministic": deterministic,
            "device": device,
            "candidate": candidate,
            "dataset": {
                "kind": dataset.kind,
                "path": dataset.path,
                "sha256": dataset.sha256,
            },
            "model": {
                "manifest_path": model.manifest_path,
                "manifest_sha256": model.manifest_sha256,
            },
            "runtime": {
                "python_version": runtime.python_version,
                "torch_version": runtime.torch_version,
            },
            "lock_sha256": lock_sha256,
            "output_root": output_root,
            "dry_run": {
                "sample_count": sample_count,
                "batch_size": batch_size,
                "steps": steps,
                "learning_rate": learning_rate,
            },
        }
        return cls(
            config_version,
            seed,
            deterministic,
            device,
            candidate,
            dataset,
            model,
            runtime,
            lock_sha256,
            output_root,
            DryRunConfig(sample_count, batch_size, steps, learning_rate),
            _freeze(semantic_raw),
            _canonical_hash(semantic_raw),
        )

    @classmethod
    def from_file(cls, path: str | Path) -> "TrainingConfig":
        config_path = Path(path)
        try:
            with config_path.open(encoding="utf-8") as stream:
                raw = json.load(stream)
        except (OSError, json.JSONDecodeError) as exc:
            raise ConfigError(f"cannot load JSON config: {config_path}") from exc
        if not isinstance(raw, dict):
            raise ConfigError("training config must be a JSON object")
        return cls.from_mapping(raw)

    def to_mapping(self) -> dict[str, object]:
        return _thaw(self._raw)


@dataclass(frozen=True)
class SyntheticSource:
    dataset_id: str
    dataset_version: str
    sample_ids: tuple[str, ...]
    generator: str
    approved_human_data: bool


def _resolve_repo_path(value: str) -> Path:
    path = Path(value).expanduser()
    return path if path.is_absolute() else REPO_ROOT / path


def _actual_model_source_path() -> Path:
    module_path = getattr(set_composition_net_module, "__file__", None)
    if not isinstance(module_path, str):
        raise TrainingError("SETCompositionNet module has no source path")
    path = Path(module_path).resolve()
    if path != MODEL_SOURCE_PATH.resolve():
        raise TrainingError(
            f"SETCompositionNet module imported from unexpected path: {path}"
        )
    return path


def _path_for_receipt(path: Path) -> str:
    try:
        return path.resolve().relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return str(path.resolve())


def _load_synthetic_source(path: Path, expected_hash: str) -> SyntheticSource:
    actual_hash = _file_hash(path)
    if actual_hash != expected_hash:
        raise TrainingError(
            f"dataset hash mismatch for {path}: expected {expected_hash}, got {actual_hash}"
        )
    try:
        with path.open(encoding="utf-8") as stream:
            raw = json.load(stream)
    except (OSError, json.JSONDecodeError) as exc:
        raise TrainingError(f"cannot load synthetic dataset source: {path}") from exc
    node = _require_keys(
        raw,
        {"dataset_id", "dataset_version", "kind", "approved_human_data", "sample_ids", "generator"},
        "synthetic dataset source",
    )
    if node["kind"] != "synthetic" or node["approved_human_data"] is not False:
        raise TrainingError("synthetic dataset source is not explicitly non-human")
    if node["generator"] != DATASET_GENERATOR_VERSION:
        raise TrainingError("synthetic dataset generator version is not frozen")
    if not isinstance(node["sample_ids"], list) or not node["sample_ids"]:
        raise TrainingError("synthetic dataset sample_ids must be a non-empty array")
    sample_ids = tuple(node["sample_ids"])
    if not all(type(sample_id) is str and sample_id for sample_id in sample_ids):
        raise TrainingError("synthetic dataset sample_ids must be non-empty strings")
    if len(set(sample_ids)) != len(sample_ids):
        raise TrainingError("synthetic dataset sample_ids must be unique")
    return SyntheticSource(
        _require_string(node["dataset_id"], "dataset_id"),
        _require_string(node["dataset_version"], "dataset_version"),
        sample_ids,
        node["generator"],
        node["approved_human_data"],
    )


@dataclass(frozen=True)
class SyntheticSample:
    sample_id: str
    inputs: SETCompositionNetInputs
    targets: Mapping[str, Tensor]


def _mask_for_roi(roi: Tensor, height: int, width: int) -> Tensor:
    mask = torch.zeros((height, width, 1), dtype=torch.float32)
    if float(roi.abs().sum()) == 0.0:
        return mask
    left = int(float(roi[0]) * width)
    top = int(float(roi[1]) * height)
    right = int(float(roi[0] + roi[2]) * width)
    bottom = int(float(roi[1] + roi[3]) * height)
    mask[top:bottom, left:right, :] = 1.0
    return mask


def _rand_scalar(generator: torch.Generator, lower: float, upper: float) -> Tensor:
    value = torch.rand((), generator=generator, dtype=torch.float32)
    return value * (upper - lower) + lower


def _synthetic_sample(
    contract: SETCompositionNetManifest,
    source: SyntheticSource,
    index: int,
    seed: int,
) -> SyntheticSample:
    generator = torch.Generator(device="cpu")
    generator.manual_seed((seed + (index * 104729)) % MAX_SEED)
    full = torch.rand(contract.full_frame_shape, generator=generator, dtype=torch.float32)
    crop = torch.rand(contract.subject_crop_shape, generator=generator, dtype=torch.float32)
    has_roi = index != len(source.sample_ids) - 1
    roi = torch.tensor((0.20 + 0.05 * index, 0.15, 0.35, 0.45), dtype=torch.float32) if has_roi else torch.zeros(4)
    mask = _mask_for_roi(roi, contract.roi_mask_shape[0], contract.roi_mask_shape[1])

    feature_names = contract.raw["inputs"]["scalar_features"]["ordered_names"]
    feature_to_normalization = contract.raw["feature_normalization"]["feature_to_normalization"]
    normalization_specs = contract.raw["feature_normalization"]
    scalar_values: list[Tensor] = []
    for name in feature_names:
        lower, upper = normalization_specs[feature_to_normalization[name]]["value_range"]
        scalar_values.append(_rand_scalar(generator, float(lower), float(upper)))
    scalar = torch.stack(scalar_values).to(dtype=torch.float32)
    scalar[feature_names.index("orientation_category")] = (index % 4) / 3.0
    scalar[feature_names.index("lens_category")] = (index % 3) / 2.0
    if has_roi:
        roi_area = roi[2] * roi[3]
        updates = {
            "subject_bbox_x": roi[0],
            "subject_bbox_y": roi[1],
            "subject_bbox_width": roi[2],
            "subject_bbox_height": roi[3],
            "subject_area_ratio": roi_area,
            "roi_present": torch.tensor(1.0),
            "roi_area_ratio": roi_area,
            "roi_mask_coverage": mask.mean(),
        }
    else:
        updates = {
            "subject_bbox_x": torch.tensor(0.0),
            "subject_bbox_y": torch.tensor(0.0),
            "subject_bbox_width": torch.tensor(0.0),
            "subject_bbox_height": torch.tensor(0.0),
            "subject_area_ratio": torch.tensor(0.0),
            "roi_present": torch.tensor(0.0),
            "roi_area_ratio": torch.tensor(0.0),
            "roi_mask_coverage": torch.tensor(0.0),
        }
    for name, value in updates.items():
        scalar[feature_names.index(name)] = value
    missing = torch.zeros(contract.scalar_feature_count, dtype=torch.float32)
    if index % 2 == 1:
        missing[(index * 7) % contract.scalar_feature_count] = 1.0

    targets: dict[str, Tensor] = {}
    for name in contract.output_head_names:
        width = contract.output_head_shapes[name]
        value_range = contract.output_head_specs[name].get("value_range")
        if value_range == [0.0, 1.0]:
            target = torch.rand(width, generator=generator, dtype=torch.float32)
        else:
            target = _rand_scalar(generator, -1.0, 1.0).expand(width).clone()
        targets[name] = target
    return SyntheticSample(
        source.sample_ids[index],
        SETCompositionNetInputs(full, crop, roi, mask, scalar, missing),
        MappingProxyType(targets),
    )


def _dataset_hash(source: SyntheticSource, samples: Sequence[SyntheticSample], seed: int) -> str:
    digest = hashlib.sha256()
    digest.update(DATASET_GENERATOR_VERSION.encode("ascii"))
    digest.update(b"\0")
    digest.update(str(seed).encode("ascii"))
    digest.update(b"\0")
    for sample in samples:
        digest.update(sample.sample_id.encode("utf-8"))
        digest.update(b"\0")
        for name, value in (
            ("full_frame_rgb", sample.inputs.full_frame_rgb),
            ("subject_crop_rgb", sample.inputs.subject_crop_rgb),
            ("roi_normalized_xywh", sample.inputs.roi_normalized_xywh),
            ("roi_mask", sample.inputs.roi_mask),
            ("scalar_features", sample.inputs.scalar_features),
            ("missing_feature_mask", sample.inputs.missing_feature_mask),
        ):
            digest.update(name.encode("ascii"))
            digest.update(_tensor_hash(value).encode("ascii"))
        for name, value in sample.targets.items():
            digest.update(name.encode("utf-8"))
            digest.update(_tensor_hash(value).encode("ascii"))
    return digest.hexdigest()


def _configure_runtime(config: TrainingConfig, lock: Mapping[str, object]) -> None:
    if platform.python_implementation() != "CPython" or platform.python_version() != config.runtime.python_version:
        raise TrainingError(
            f"Python runtime drift: expected CPython {config.runtime.python_version}, "
            f"got {platform.python_implementation()} {platform.python_version()}"
        )
    if torch.__version__ != config.runtime.torch_version:
        raise TrainingError(
            f"Torch runtime drift: expected {config.runtime.torch_version}, got {torch.__version__}"
        )
    lock_python = lock["python"]
    assert isinstance(lock_python, dict)
    if lock_python["version"] != config.runtime.python_version:
        raise TrainingError("runtime config and lock disagree on Python version")
    lock_packages = lock["packages"]
    assert isinstance(lock_packages, list)
    torch_lock = next((item for item in lock_packages if item.get("name", "").lower() == "torch"), None)
    if not isinstance(torch_lock, dict) or torch_lock["version"] != config.runtime.torch_version:
        raise TrainingError("runtime config and lock disagree on Torch version")
    lock_platform = lock["platform"]
    assert isinstance(lock_platform, dict)
    actual_platform = {"system": platform.system(), "machine": platform.machine()}
    if lock_platform != actual_platform:
        raise TrainingError(f"runtime platform drift: expected {lock_platform}, got {actual_platform}")
    random.seed(config.seed)
    torch.manual_seed(config.seed)
    torch.set_num_threads(1)
    try:
        torch.set_num_interop_threads(1)
    except RuntimeError:
        # The check runner intentionally executes two runs in one interpreter;
        # inter-op threads are process-global and already fixed after run one.
        pass
    torch.use_deterministic_algorithms(True)
    if not torch.are_deterministic_algorithms_enabled():
        raise TrainingError("PyTorch deterministic algorithms could not be enabled")


def _environment_receipt(config: TrainingConfig, lock_hash: str) -> dict[str, object]:
    return {
        "python": {
            "implementation": platform.python_implementation(),
            "version": platform.python_version(),
        },
        "torch": {
            "version": torch.__version__,
            "cuda_version": torch.version.cuda,
        },
        "lock": {
            "path": LOCK_RELATIVE_PATH,
            "sha256": lock_hash,
        },
        "platform": {
            "system": platform.system(),
            "release": platform.release(),
            "machine": platform.machine(),
        },
        "runtime": {
            "requested_device": config.device,
            "actual_device": "cpu",
            "deterministic_algorithms": torch.are_deterministic_algorithms_enabled(),
            "deterministic_warn_only": torch.is_deterministic_algorithms_warn_only_enabled(),
            "torch_num_threads": torch.get_num_threads(),
            "torch_num_interop_threads": torch.get_num_interop_threads(),
        },
    }


def _command_receipt(argv: Sequence[str]) -> dict[str, object]:
    normalized: list[str] = []
    skip_next = False
    for index, item in enumerate(argv):
        if skip_next:
            skip_next = False
            continue
        if item in {"--run-dir", "--output-dir", "--output-root"} and index + 1 < len(argv):
            normalized.extend((item, "<run-dir>"))
            skip_next = True
        elif item == "--config" and index + 1 < len(argv):
            normalized.extend((item, "<config>"))
            skip_next = True
        else:
            normalized.append(item)
    return {
        "entrypoint": "python3 -m ml.camera_coach.train",
        "argv": normalized,
    }


def _stack_batch(samples: Sequence[SyntheticSample]) -> tuple[SETCompositionNetInputs, dict[str, Tensor]]:
    inputs = SETCompositionNetInputs(
        torch.stack([sample.inputs.full_frame_rgb for sample in samples]),
        torch.stack([sample.inputs.subject_crop_rgb for sample in samples]),
        torch.stack([sample.inputs.roi_normalized_xywh for sample in samples]),
        torch.stack([sample.inputs.roi_mask for sample in samples]),
        torch.stack([sample.inputs.scalar_features for sample in samples]),
        torch.stack([sample.inputs.missing_feature_mask for sample in samples]),
    )
    targets = {
        name: torch.stack([sample.targets[name] for sample in samples])
        for name in samples[0].targets
    }
    return inputs, targets


def _loss(outputs: Mapping[str, Tensor], targets: Mapping[str, Tensor]) -> Tensor:
    terms = [F.mse_loss(outputs[name], targets[name]) for name in outputs]
    return torch.stack(terms).mean()


def _make_model(config: TrainingConfig, contract: SETCompositionNetManifest) -> torch.nn.Module:
    if config.candidate == CandidateA.candidate_id:
        return CandidateA(contract)
    if config.candidate == CandidateB.candidate_id:
        return CandidateB(contract)
    raise ConfigError(f"unsupported candidate: {config.candidate}")


def _new_run_dir(config: TrainingConfig, requested: str | Path | None) -> Path:
    if requested is not None:
        return Path(requested).expanduser().resolve()
    root = _resolve_repo_path(config.output_root).resolve()
    return root / f"run-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}-{uuid.uuid4().hex[:12]}"


def _write_exclusive(path: Path, value: object) -> None:
    try:
        with path.open("x", encoding="utf-8") as stream:
            json.dump(value, stream, ensure_ascii=False, sort_keys=True, indent=2)
            stream.write("\n")
    except FileExistsError as exc:
        raise TrainingError(f"refusing to overwrite existing output: {path}") from exc
    except OSError as exc:
        raise TrainingError(f"cannot write output: {path}") from exc


def run_training(
    config: TrainingConfig,
    *,
    config_path: str | Path,
    run_dir: str | Path | None = None,
    argv: Sequence[str] = (),
) -> dict[str, object]:
    """Execute one admitted synthetic dry run and write its receipt."""

    target = _new_run_dir(config, run_dir)
    if target.exists():
        raise TrainingError(f"output target already exists: {target}")

    lock, lock_hash = _load_runtime_lock(config.lock_sha256)
    _verify_installed_closure(lock)
    _configure_runtime(config, lock)
    environment = _environment_receipt(config, lock_hash)
    environment_hash = _canonical_hash(environment)
    command = _command_receipt(argv)
    command_hash = _canonical_hash(command)

    manifest_path = _resolve_repo_path(config.model.manifest_path)
    if manifest_path.resolve() != (REPO_ROOT / MANIFEST_RELATIVE_PATH).resolve():
        raise TrainingError(f"manifest path is not the frozen contract path: {manifest_path}")
    model_source_path = _actual_model_source_path()
    manifest_hash = _file_hash(manifest_path)
    if manifest_hash != config.model.manifest_sha256:
        raise TrainingError(
            f"model manifest hash mismatch for {manifest_path}: "
            f"expected {config.model.manifest_sha256}, got {manifest_hash}"
        )
    model_source_hash = _file_hash(model_source_path)
    runner_source_path = Path(__file__).resolve()
    runner_source_hash = _file_hash(runner_source_path)
    manifest = SETCompositionNetManifest.load(manifest_path)

    dataset_path = _resolve_repo_path(config.dataset.path)
    dataset_reference_hash = _file_hash(dataset_path)
    if dataset_reference_hash != config.dataset.sha256:
        raise TrainingError(
            f"dataset hash mismatch for {dataset_path}: "
            f"expected {config.dataset.sha256}, got {dataset_reference_hash}"
        )
    source = _load_synthetic_source(dataset_path, config.dataset.sha256)
    if len(source.sample_ids) != config.dry_run.sample_count:
        raise TrainingError(
            f"config sample_count={config.dry_run.sample_count} does not match "
            f"synthetic source count={len(source.sample_ids)}"
        )
    samples = tuple(
        _synthetic_sample(manifest, source, index, config.seed)
        for index in range(len(source.sample_ids))
    )
    realized_dataset_hash = _dataset_hash(source, samples, config.seed)
    order_generator = torch.Generator(device="cpu")
    order_generator.manual_seed(config.seed)
    order = torch.randperm(len(samples), generator=order_generator).tolist()
    ordered_ids = [samples[index].sample_id for index in order]
    sample_order_hash = _canonical_hash(ordered_ids)

    model = _make_model(config, manifest)
    model_initialization_hash = _state_hash(model)
    model_hash = _canonical_hash(
        {
            "candidate": config.candidate,
            "manifest_sha256": manifest_hash,
            "source_sha256": model_source_hash,
            "constructor": type(model).__name__,
        }
    )
    batch_indices = order[: config.dry_run.batch_size]
    batch, targets = _stack_batch([samples[index] for index in batch_indices])
    optimizer = torch.optim.SGD(model.parameters(), lr=config.dry_run.learning_rate)
    optimizer.zero_grad(set_to_none=True)
    outputs = model(batch)
    if tuple(outputs) != manifest.output_head_names:
        raise TrainingError("candidate output order does not match frozen manifest")
    loss = _loss(outputs, targets)
    if not torch.isfinite(loss):
        raise TrainingError("first-step synthetic loss is not finite")
    loss.backward()
    for name, parameter in model.named_parameters():
        if parameter.grad is not None and not torch.isfinite(parameter.grad).all():
            raise TrainingError(f"non-finite gradient in first synthetic step: {name}")
    optimizer.step()
    first_step_loss = float(loss.detach().cpu().item())

    dataset_info = {
        "kind": "synthetic",
        "version": source.dataset_version,
        "declared_source": _path_for_receipt(dataset_path),
        "source_sha256": dataset_reference_hash,
        "realized_sha256": realized_dataset_hash,
        "approved_human_data": source.approved_human_data,
        "sample_count": len(samples),
        "generator": DATASET_GENERATOR_VERSION,
    }
    model_info = {
        "candidate": config.candidate,
        "constructor": type(model).__name__,
        "manifest": _path_for_receipt(manifest_path),
        "manifest_sha256": manifest_hash,
        "source": _path_for_receipt(model_source_path),
        "source_sha256": model_source_hash,
        "imported_module": _path_for_receipt(model_source_path),
        "model_sha256": model_hash,
        "initialization_sha256": model_initialization_hash,
    }
    training_info = {
        "mode": "synthetic_dry_run",
        "steps_requested": config.dry_run.steps,
        "steps_completed": config.dry_run.steps,
        "sample_count": len(samples),
        "batch_size": config.dry_run.batch_size,
        "learning_rate": config.dry_run.learning_rate,
        "loss_definition": LOSS_DEFINITION,
        "first_step_loss": first_step_loss,
        "first_step_loss_tolerance": FIRST_STEP_LOSS_TOLERANCE,
    }
    reproducibility = {
        "seed": config.seed,
        "sample_order": ordered_ids,
        "sample_order_sha256": sample_order_hash,
        "model_initialization_sha256": model_initialization_hash,
        "first_step_loss": first_step_loss,
        "first_step_loss_tolerance": FIRST_STEP_LOSS_TOLERANCE,
    }
    stable_projection = {
        "receipt_version": RECEIPT_VERSION,
        "scope": "M4-006-infrastructure-only",
        "config": config.to_mapping(),
        "dataset": dataset_info,
        "model": model_info,
        "runner": {
            "source": _path_for_receipt(runner_source_path),
            "source_sha256": runner_source_hash,
        },
        "environment": environment,
        "command": command,
        "training": training_info,
        "reproducibility": reproducibility,
    }
    hashes: dict[str, object] = {
        "config_sha256": config.config_sha256,
        "dataset_sha256": realized_dataset_hash,
        "dataset_reference_sha256": dataset_reference_hash,
        "model_sha256": model_hash,
        "model_contract_sha256": manifest_hash,
        "model_source_sha256": model_source_hash,
        "runner_source_sha256": runner_source_hash,
        "lockfile_sha256": lock_hash,
        "model_initialization_sha256": model_initialization_hash,
        "environment_sha256": environment_hash,
        "command_sha256": command_hash,
        "content_stable_projection_sha256": _canonical_hash(stable_projection),
    }
    created_at = datetime.now(timezone.utc).isoformat(timespec="seconds")
    run_instance = {
        "run_id": uuid.uuid4().hex,
        "created_at_utc": created_at,
        "output_dir": str(target),
        "config_path": str(Path(config_path).expanduser().resolve()),
    }
    receipt: dict[str, object] = {
        "receipt_version": RECEIPT_VERSION,
        "status": "pass",
        "scope": "M4-006-infrastructure-only",
        "content_stable_projection": stable_projection,
        "hashes": hashes,
        "run_instance": run_instance,
    }
    hashes["receipt_sha256"] = _canonical_hash(receipt)

    try:
        target.mkdir(parents=True, exist_ok=False)
    except FileExistsError as exc:
        raise TrainingError(f"refusing to overwrite existing output: {target}") from exc
    except OSError as exc:
        raise TrainingError(f"cannot create output directory: {target}") from exc
    _write_exclusive(target / "config.json", config.to_mapping())
    _write_exclusive(target / "receipt.json", receipt)
    return receipt


def _parse_args(argv: Sequence[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, help="strict JSON training config")
    parser.add_argument(
        "--run-dir",
        "--output-dir",
        "--output-root",
        dest="run_dir",
        help="new run directory; an existing target is rejected",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    raw_argv = list(sys.argv[1:] if argv is None else argv)
    try:
        args = _parse_args(raw_argv)
        config = TrainingConfig.from_file(args.config)
        receipt = run_training(config, config_path=args.config, run_dir=args.run_dir, argv=raw_argv)
    except (ConfigError, TrainingError, OSError) as exc:
        print(f"training environment rejected: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(receipt, ensure_ascii=False, sort_keys=True, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
