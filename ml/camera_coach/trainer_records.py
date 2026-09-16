"""M01 production-record training mode for the existing SETCompositionNet trainer.

This module is the ``camera_training.v2`` / ``production_records`` mode of the
one trainer entry point::

    python3 -m ml.camera_coach.train \
        --config ml/camera_coach/configs/production_records_smoke.json \
        --run-dir /private/tmp/setos-m01-v2-smoke

The v1 synthetic dry run (``camera_training.v1``) and the separate silver
research script (``train_silver_actions.py``) are preserved unchanged; this is
the same CLI extended with a third *mode*, not a third framework.  A full human
fit is the identical command with a ``camera_training.v2`` config whose
``dataset`` points at admitted typed records produced by D04 — that command
exists and is exercised here on a declared non-admitted research bundle.

What v2 adds over the synthetic dry run:

* per-head supervision masks, including the frozen 4-component intent mask;
* family-balanced sampling, train-only class weights, admissible paired ranking;
* validation, early stopping and one fixed selection rule;
* several seeds, a trained-head mask, and atomic checkpoint/resume carrying
  optimizer, scheduler, RNG and sampler state.

It does not generate benchmarks, does not run on GPU, and makes no quality
claim.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import time
from typing import Any

import torch
from torch import Tensor, nn

from .data.training_records import (
    FamilyBalancedSampler,
    TRAINABLE_SPLITS,
    TrainingRecord,
    TrainingRecordError,
    apply_horizontal_flip,
    class_pos_weights,
    eligible_ranking_pairs,
    intent_head_mask,
    load_records,
    stack_inputs,
    stack_masks,
    stack_targets,
    validate_record_admission,
)
from .losses import DIRECT_LOSS_HEADS, LossConfig, compute_multitask_loss
from .component_supervision import (
    CHECKPOINT_VERSION, LEGACY_CHECKPOINT_VERSION, batch_supervision, canonical_hash,
    checkpoint_supervision, new_supervision, record_successful_step, records_fingerprint,
    trained_head_mask as observed_head_mask, validate_supervision,
)
from .models.set_composition_net_v2 import (
    SETCompositionNetV2CandidateA,
    SETCompositionNetV2CandidateB,
    SETCompositionNetV2Inputs,
    SETCompositionNetV2Manifest,
)
from .train import (
    MAX_SEED,
    ConfigError,
    TrainingError,
    _canonical_hash,
    _command_receipt,
    _configure_runtime,
    _file_hash,
    _load_runtime_lock,
    _new_run_dir,
    _path_for_receipt,
    _require_bool,
    _require_float,
    _require_int,
    _require_keys,
    _require_sha256,
    _require_string,
    _resolve_repo_path,
    _state_hash,
    _verify_installed_closure,
)


CONFIG_VERSION = "camera_training.v2"
RECEIPT_VERSION = "camera_training_receipt.v3"
MODEL_MANIFEST_RELATIVE = "ml/camera_coach/contracts/set_composition_net_v2.json"
LOSS_CONFIG_RELATIVE = "ml/camera_coach/configs/loss_weights.json"
RUNTIME_LOCK_RELATIVE = "ml/camera_coach/requirements.lock"
SELECTION_RULE = "minimum_validation_total_loss_then_earliest_epoch"
MODE = "production_records"
ADMISSION_STATES = ("non_admitted_research", "declared_admitted")

# An explicit runtime profile is part of the M02 package.  ``pinned_local`` is
# the M01 contract: a hash-pinned macOS/arm64 wheel closure and CPU-only
# execution.  ``colab_installed_runtime`` is the declared Colab profile: the
# interpreter and Torch versions are pinned in the config and checked against
# the installed runtime, but no wheel-hash closure is applied because Colab
# owns the base image; CUDA is admitted only after the actual tensors are
# proven to live on the device in ``train_one_seed`` and again in preflight.
RUNTIME_PROFILES = ("pinned_local", "colab_installed_runtime")
DEVICE_CHOICES = ("cpu", "cuda")

# Runtime fields the Colab notebook is allowed to rebind at run time from the
# bundled template config.  Everything else is frozen training semantics.
RUNTIME_OVERRIDABLE_CONFIG_FIELDS = (
    "device",
    "output_root",
    "resume_from",
    "runtime.python_version",
    "runtime.torch_version",
)


@dataclass(frozen=True)
class RecordsConfig:
    path: str
    sha256: str
    admission: str
    rights_manifest_sha256: str | None


@dataclass(frozen=True)
class ModelV2Config:
    manifest_path: str
    manifest_sha256: str


@dataclass(frozen=True)
class TrainingParams:
    epochs: int
    batch_size: int
    learning_rate: float
    weight_decay: float
    early_stop_patience: int
    trained_heads: tuple[str, ...]
    class_weight_max: float
    gradient_clip: float


@dataclass(frozen=True)
class AugmentationParams:
    horizontal_flip: bool


@dataclass(frozen=True)
class RuntimeConfigV2:
    python_version: str
    torch_version: str


@dataclass(frozen=True)
class LossReference:
    path: str
    sha256: str


@dataclass(frozen=True)
class RecordsTrainingConfig:
    config_version: str
    mode: str
    seed: int
    seeds: tuple[int, ...]
    deterministic: bool
    device: str
    candidate: str
    dataset: RecordsConfig
    model: ModelV2Config
    training: TrainingParams
    augmentation: AugmentationParams
    runtime: RuntimeConfigV2
    loss: LossReference
    lock_sha256: str | None
    output_root: str
    resume_from: str | None
    config_sha256: str
    runtime_profile: str = "pinned_local"

    @classmethod
    def from_mapping(cls, raw: Mapping[str, object]) -> "RecordsTrainingConfig":
        raw = dict(raw)
        runtime_profile = raw.pop("runtime_profile", "pinned_local")
        if runtime_profile not in RUNTIME_PROFILES:
            raise ConfigError(f"runtime_profile must be one of {RUNTIME_PROFILES}, got {runtime_profile!r}")
        top = _require_keys(
            raw,
            {
                "config_version",
                "mode",
                "seed",
                "seeds",
                "deterministic",
                "device",
                "candidate",
                "dataset",
                "model",
                "training",
                "augmentation",
                "runtime",
                "loss",
                "lock_sha256",
                "output_root",
                "resume_from",
            },
            "records training config",
        )
        if top["config_version"] != CONFIG_VERSION:
            raise ConfigError(f"config_version must be {CONFIG_VERSION!r}")
        if top["mode"] != MODE:
            raise ConfigError(f"mode must be {MODE!r}")
        seed = _require_int(top["seed"], "seed", minimum=0, maximum=MAX_SEED)
        raw_seeds = top["seeds"]
        if not isinstance(raw_seeds, list) or not raw_seeds:
            raise ConfigError("seeds must be a non-empty array")
        seeds = tuple(_require_int(item, "seeds item", minimum=0, maximum=MAX_SEED) for item in raw_seeds)
        if len(seeds) != len(set(seeds)):
            raise ConfigError("seeds must be unique")
        deterministic = _require_bool(top["deterministic"], "deterministic")
        if not deterministic:
            raise ConfigError("deterministic must be true")
        device = _require_string(top["device"], "device")
        if device not in DEVICE_CHOICES:
            raise ConfigError(f"device must be one of {DEVICE_CHOICES}, got {device!r}")
        if runtime_profile == "pinned_local" and device != "cpu":
            raise ConfigError("runtime_profile 'pinned_local' admits only device='cpu'; use 'colab_installed_runtime' with a CUDA preflight for a GPU run")
        candidate = _require_string(top["candidate"], "candidate")
        if candidate not in {SETCompositionNetV2CandidateA.candidate_id, SETCompositionNetV2CandidateB.candidate_id}:
            raise ConfigError(f"candidate is not a v2 candidate: {candidate!r}")

        dataset_node = _require_keys(top["dataset"], {"path", "sha256", "admission", "rights_manifest_sha256"}, "dataset")
        admission = _require_string(dataset_node["admission"], "dataset.admission")
        if admission not in ADMISSION_STATES:
            raise ConfigError(f"dataset.admission must be one of {ADMISSION_STATES}")
        rights = dataset_node["rights_manifest_sha256"]
        if admission == "declared_admitted":
            rights = _require_sha256(rights, "dataset.rights_manifest_sha256")
        elif rights is not None:
            raise ConfigError("dataset.rights_manifest_sha256 must be null for non-admitted research data")
        dataset = RecordsConfig(
            _require_string(dataset_node["path"], "dataset.path"),
            _require_sha256(dataset_node["sha256"], "dataset.sha256"),
            admission,
            rights,
        )

        model_node = _require_keys(top["model"], {"manifest_path", "manifest_sha256"}, "model")
        if model_node["manifest_path"] != MODEL_MANIFEST_RELATIVE:
            raise ConfigError(f"model.manifest_path must be {MODEL_MANIFEST_RELATIVE!r}")
        model = ModelV2Config(
            _require_string(model_node["manifest_path"], "model.manifest_path"),
            _require_sha256(model_node["manifest_sha256"], "model.manifest_sha256"),
        )

        training_node = _require_keys(
            top["training"],
            {
                "epochs",
                "batch_size",
                "learning_rate",
                "weight_decay",
                "early_stop_patience",
                "trained_heads",
                "class_weight_max",
                "gradient_clip",
            },
            "training",
        )
        epochs = _require_int(training_node["epochs"], "training.epochs", minimum=1, maximum=10000)
        batch_size = _require_int(training_node["batch_size"], "training.batch_size", minimum=1, maximum=256)
        learning_rate = _require_float(training_node["learning_rate"], "training.learning_rate", minimum=0.0, maximum=10.0)
        weight_decay = _require_float(training_node["weight_decay"], "training.weight_decay", minimum=-1e-9, maximum=1.0)
        patience = _require_int(training_node["early_stop_patience"], "training.early_stop_patience", minimum=1, maximum=10000)
        heads = training_node["trained_heads"]
        if not isinstance(heads, list) or not heads or not all(isinstance(item, str) for item in heads):
            raise ConfigError("training.trained_heads must be a non-empty array of head names")
        unknown_heads = sorted(set(heads).difference(DIRECT_LOSS_HEADS))
        if unknown_heads:
            raise ConfigError(f"training.trained_heads has unknown heads: {unknown_heads}")
        class_weight_max = _require_float(training_node["class_weight_max"], "training.class_weight_max", minimum=0.0, maximum=1000.0)
        gradient_clip = _require_float(training_node["gradient_clip"], "training.gradient_clip", minimum=0.0, maximum=1000.0)
        training = TrainingParams(
            epochs,
            batch_size,
            learning_rate,
            max(0.0, weight_decay),
            patience,
            tuple(dict.fromkeys(heads)),
            class_weight_max,
            gradient_clip,
        )

        augmentation_node = _require_keys(top["augmentation"], {"horizontal_flip"}, "augmentation")
        augmentation = AugmentationParams(_require_bool(augmentation_node["horizontal_flip"], "augmentation.horizontal_flip"))

        runtime_node = _require_keys(top["runtime"], {"python_version", "torch_version"}, "runtime")
        runtime = RuntimeConfigV2(
            _require_string(runtime_node["python_version"], "runtime.python_version"),
            _require_string(runtime_node["torch_version"], "runtime.torch_version"),
        )

        loss_node = _require_keys(top["loss"], {"path", "sha256"}, "loss")
        if loss_node["path"] != LOSS_CONFIG_RELATIVE:
            raise ConfigError(f"loss.path must be {LOSS_CONFIG_RELATIVE!r}")
        loss = LossReference(
            _require_string(loss_node["path"], "loss.path"),
            _require_sha256(loss_node["sha256"], "loss.sha256"),
        )
        if runtime_profile == "pinned_local":
            lock_sha256: str | None = _require_sha256(top["lock_sha256"], "lock_sha256")
        else:
            if top["lock_sha256"] is not None:
                raise ConfigError(
                    "runtime_profile 'colab_installed_runtime' does not apply a wheel-hash lock; "
                    "lock_sha256 must be null"
                )
            lock_sha256 = None
        output_root = _require_string(top["output_root"], "output_root")
        resume_from = top["resume_from"]
        if resume_from is not None:
            resume_from = _require_string(resume_from, "resume_from")
            if len(seeds) != 1:
                # Fail closed instead of silently starting from scratch: a
                # multi-seed config cannot be resumed by one checkpoint, and a
                # receipt must never claim a resumed run that never resumed.
                raise ConfigError(
                    f"resume_from requires exactly one seed, got {len(seeds)} seeds; "
                    "resume a single-seed run or start a new run explicitly"
                )

        semantic = {
            "config_version": CONFIG_VERSION,
            "mode": MODE,
            "seed": seed,
            "seeds": list(seeds),
            "deterministic": deterministic,
            "device": device,
            "candidate": candidate,
            "dataset": {
                "path": dataset.path,
                "sha256": dataset.sha256,
                "admission": dataset.admission,
                "rights_manifest_sha256": dataset.rights_manifest_sha256,
            },
            "model": {"manifest_path": model.manifest_path, "manifest_sha256": model.manifest_sha256},
            "training": {
                "epochs": training.epochs,
                "batch_size": training.batch_size,
                "learning_rate": training.learning_rate,
                "weight_decay": training.weight_decay,
                "early_stop_patience": training.early_stop_patience,
                "trained_heads": list(training.trained_heads),
                "class_weight_max": training.class_weight_max,
                "gradient_clip": training.gradient_clip,
            },
            "augmentation": {"horizontal_flip": augmentation.horizontal_flip},
            "runtime": {"python_version": runtime.python_version, "torch_version": runtime.torch_version},
            "loss": {"path": loss.path, "sha256": loss.sha256},
            "lock_sha256": lock_sha256,
            "output_root": output_root,
            "resume_from": resume_from,
        }
        return cls(
            CONFIG_VERSION,
            MODE,
            seed,
            seeds,
            deterministic,
            device,
            candidate,
            dataset,
            model,
            training,
            augmentation,
            runtime,
            loss,
            lock_sha256,
            output_root,
            resume_from,
            _canonical_hash(semantic),
            runtime_profile,
        )

    @classmethod
    def from_file(cls, path: str | Path) -> "RecordsTrainingConfig":
        try:
            with Path(path).open(encoding="utf-8") as stream:
                raw = json.load(stream)
        except (OSError, json.JSONDecodeError) as exc:
            raise ConfigError(f"cannot load records training config: {path}") from exc
        if not isinstance(raw, Mapping):
            raise ConfigError("records training config must be a JSON object")
        return cls.from_mapping(raw)

    def as_mapping(self) -> dict[str, object]:
        return json.loads(json.dumps({
            "config_version": self.config_version,
            "mode": self.mode,
            "seed": self.seed,
            "seeds": list(self.seeds),
            "deterministic": self.deterministic,
            "device": self.device,
            "candidate": self.candidate,
            "dataset": {
                "path": self.dataset.path,
                "sha256": self.dataset.sha256,
                "admission": self.dataset.admission,
                "rights_manifest_sha256": self.dataset.rights_manifest_sha256,
            },
            "model": {"manifest_path": self.model.manifest_path, "manifest_sha256": self.model.manifest_sha256},
            "training": {
                "epochs": self.training.epochs,
                "batch_size": self.training.batch_size,
                "learning_rate": self.training.learning_rate,
                "weight_decay": self.training.weight_decay,
                "early_stop_patience": self.training.early_stop_patience,
                "trained_heads": list(self.training.trained_heads),
                "class_weight_max": self.training.class_weight_max,
                "gradient_clip": self.training.gradient_clip,
            },
            "augmentation": {"horizontal_flip": self.augmentation.horizontal_flip},
            "runtime": {"python_version": self.runtime.python_version, "torch_version": self.runtime.torch_version},
            "loss": {"path": self.loss.path, "sha256": self.loss.sha256},
            "lock_sha256": self.lock_sha256,
            "output_root": self.output_root,
            "resume_from": self.resume_from,
            "runtime_profile": self.runtime_profile,
        }))


def _atomic_write_json(path: Path, value: object) -> None:
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("w", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, sort_keys=True, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def _atomic_save_checkpoint(path: Path, payload: Mapping[str, object]) -> None:
    temporary = path.with_name(path.name + ".tmp")
    torch.save(dict(payload), temporary)
    os.replace(temporary, path)


def _stable_flip(record_id: str, seed: int, epoch: int) -> bool:
    digest = hashlib.sha256(f"{seed}:{epoch}:{record_id}".encode("utf-8")).digest()
    return digest[0] % 2 == 1


def resume_semantic_sha256(config: "RecordsTrainingConfig") -> str:
    """Hash of the semantics a checkpoint must share to be resumed.

    ``resume_from`` is orchestration, not training semantics: a run interrupted
    with ``resume_from: null`` must be resumable through the same CLI with the
    same config plus ``resume_from`` pointing at the durable checkpoint.  The
    legacy ``config_sha256`` keeps including ``resume_from`` so the M01 receipt
    hash algorithm is unchanged; this separate hash is what checkpoints carry.
    """

    return _canonical_hash(
        {
            "config_version": config.config_version,
            "mode": config.mode,
            "seed": config.seed,
            "seeds": list(config.seeds),
            "deterministic": config.deterministic,
            "device": config.device,
            "runtime_profile": config.runtime_profile,
            "candidate": config.candidate,
            "dataset": {
                "path": config.dataset.path,
                "sha256": config.dataset.sha256,
                "admission": config.dataset.admission,
                "rights_manifest_sha256": config.dataset.rights_manifest_sha256,
            },
            "model": {
                "manifest_path": config.model.manifest_path,
                "manifest_sha256": config.model.manifest_sha256,
            },
            "training": {
                "epochs": config.training.epochs,
                "batch_size": config.training.batch_size,
                "learning_rate": config.training.learning_rate,
                "weight_decay": config.training.weight_decay,
                "early_stop_patience": config.training.early_stop_patience,
                "trained_heads": list(config.training.trained_heads),
                "class_weight_max": config.training.class_weight_max,
                "gradient_clip": config.training.gradient_clip,
            },
            "augmentation": {"horizontal_flip": config.augmentation.horizontal_flip},
            "runtime": {
                "python_version": config.runtime.python_version,
                "torch_version": config.runtime.torch_version,
            },
            "loss": {"path": config.loss.path, "sha256": config.loss.sha256},
        }
    )


def _torch_device(config: RecordsTrainingConfig) -> torch.device:
    device = torch.device(config.device)
    if device.type == "cuda" and not torch.cuda.is_available():
        raise TrainingError(
            "device='cuda' requested but torch.cuda.is_available() is False; preflight must prove CUDA before the run"
        )
    return device


def _inputs_to_device(values: SETCompositionNetV2Inputs, device: torch.device) -> SETCompositionNetV2Inputs:
    if device.type == "cpu":
        return values
    return SETCompositionNetV2Inputs(
        values.full_frame_rgb.to(device),
        values.subject_crop_rgb.to(device),
        values.roi_normalized_xywh.to(device),
        values.roi_mask.to(device),
        values.scalar_features.to(device),
        values.missing_feature_mask.to(device),
        values.intent_features.to(device),
    )


def _assert_actually_on_device(
    model: nn.Module, device: torch.device, tensors: Sequence[Tensor], label: str
) -> None:
    """Fail closed unless the model and the used tensors really live on ``device``."""

    for name, parameter in model.named_parameters():
        if parameter.device != device:
            raise TrainingError(f"{label}: parameter {name} is on {parameter.device}, expected {device}")
    for index, tensor in enumerate(tensors):
        if tensor.device != device:
            raise TrainingError(f"{label}: tensor {index} is on {tensor.device}, expected {device}")
    if device.type == "cuda" and torch.cuda.max_memory_allocated(device) <= 0:
        raise TrainingError(f"{label}: CUDA is selected but no CUDA memory was allocated for the used tensors")


def _make_model(
    config: RecordsTrainingConfig, contract: SETCompositionNetV2Manifest, device: torch.device
) -> nn.Module:
    if config.candidate == SETCompositionNetV2CandidateA.candidate_id:
        return SETCompositionNetV2CandidateA(contract).to(device)
    return SETCompositionNetV2CandidateB(contract).to(device)


def _available_heads(records: Sequence[TrainingRecord], config: RecordsTrainingConfig,
                     loss_config: LossConfig | None = None) -> tuple[dict[str, bool], dict[str, Tensor]]:
    mask_sums = {name: float(stack_masks(records)[name].sum()) for name in DIRECT_LOSS_HEADS}
    trained = {
        name: (name in config.training.trained_heads) and (
            (mask_sums[name] > 0.0 and (loss_config is None or getattr(loss_config.weights, name) > 0)) or
            (name == "good_frame_probability" and loss_config is not None and
             loss_config.weights.ranking > 0 and bool(eligible_ranking_pairs(records))))
        for name in DIRECT_LOSS_HEADS
    }
    return trained, stack_masks(records)


def _masked_for_training(masks: Mapping[str, Tensor], trained: Mapping[str, bool]) -> dict[str, Tensor]:
    return {name: (mask if trained.get(name, False) else torch.zeros_like(mask)) for name, mask in masks.items()}


def _supervised_records(records: Sequence[TrainingRecord], trained: Mapping[str, bool], *,
                        ranking_enabled: bool = False) -> list[TrainingRecord]:
    """Fully masked rows cannot create optimizer steps or zero-loss validation."""
    ranked = {index for left, right, _ in eligible_ranking_pairs(records) for index in (left, right)} if (
        ranking_enabled and trained.get("good_frame_probability", False)) else set()
    return [record for index, record in enumerate(records) if index in ranked or any(
        trained.get(head, False) and bool(torch.any(mask != 0.0)) for head, mask in record.masks.items()
    )]


def _batch_loss(
    model: nn.Module,
    records: Sequence[TrainingRecord],
    contract: SETCompositionNetV2Manifest,
    loss_config: LossConfig,
    trained: Mapping[str, bool],
    *,
    pos_weights: Mapping[str, Tensor] | None,
    augment: bool,
    seed: int,
    epoch: int,
    device: torch.device,
) -> tuple[Tensor, dict[str, float], dict]:
    prepared = []
    for record in records:
        if augment and _stable_flip(record.record_id, seed, epoch):
            record = apply_horizontal_flip(record, contract)
        prepared.append(record)
    inputs = _inputs_to_device(stack_inputs(prepared, contract), device)
    targets = {name: value.to(device) for name, value in stack_targets(prepared).items()}
    masks = {name: value.to(device) for name, value in _masked_for_training(stack_masks(prepared), trained).items()}
    intent_mask = intent_head_mask(prepared, contract).to(device)
    # Paired ranking is applied only to pairs that are admissible on both
    # sides (explicit intent and ROI) and share the split; anything else is
    # dropped instead of being reinterpreted as a preference.
    pair_spec = eligible_ranking_pairs(prepared)
    pair_labels = None
    if pair_spec and trained.get("good_frame_probability", False) and loss_config.weights.ranking > 0:
        pair_labels = {
            "good_vs_harmful": {
                "indices": torch.tensor(
                    [[first, second] for first, second, _ in pair_spec], dtype=torch.long, device=device
                ),
                "labels": torch.tensor(
                    [preference for _, _, preference in pair_spec], dtype=torch.float32, device=device
                ),
                "mask": torch.ones(len(pair_spec), dtype=torch.float32, device=device),
            }
        }
    outputs = model(inputs)
    _assert_actually_on_device(model, device, [outputs["embedding"]], "forward")
    result = compute_multitask_loss(
        outputs,
        targets,
        masks=masks,
        intent_mask=intent_mask,
        head_pos_weights=pos_weights,
        pair_labels=pair_labels,
        config=loss_config,
    )
    scalar_terms = {name: float(result.per_head[name].detach()) for name in result.per_head}
    observation = batch_supervision(outputs, targets, masks, intent_mask, loss_config,
        [record.record_id for record in prepared], ranking_pairs=len(pair_spec) if pair_labels else 0)
    return result.total, scalar_terms, observation


def _validate(
    model: nn.Module,
    records: Sequence[TrainingRecord],
    contract: SETCompositionNetV2Manifest,
    loss_config: LossConfig,
    trained: Mapping[str, bool],
    batch_size: int,
    device: torch.device,
) -> tuple[float, dict[str, float]]:
    model.eval()
    total_weighted = 0.0
    per_head_totals: dict[str, float] = {name: 0.0 for name in DIRECT_LOSS_HEADS}
    count = 0
    with torch.no_grad():
        for start in range(0, len(records), batch_size):
            chunk = records[start : start + batch_size]
            inputs = _inputs_to_device(stack_inputs(chunk, contract), device)
            targets = {name: value.to(device) for name, value in stack_targets(chunk).items()}
            masks = {name: value.to(device) for name, value in _masked_for_training(stack_masks(chunk), trained).items()}
            intent_mask = intent_head_mask(chunk, contract).to(device)
            outputs = model(inputs)
            _assert_actually_on_device(model, device, [outputs["embedding"]], "validation forward")
            result = compute_multitask_loss(outputs, targets, masks=masks, intent_mask=intent_mask, config=loss_config)
            observation = batch_supervision(outputs, targets, masks, intent_mask, loss_config,
                [record.record_id for record in chunk])
            if not observation["has_supervision"]:
                continue
            total_weighted += float(result.total) * len(chunk)
            for name in DIRECT_LOSS_HEADS:
                per_head_totals[name] += float(result.per_head[name]) * len(chunk)
            count += len(chunk)
    model.train()
    if count == 0:
        raise TrainingError("validation split has no effective direct supervision")
    return total_weighted / count, {name: value / count for name, value in per_head_totals.items()}


def _seed_records(records: Sequence[TrainingRecord], seed: int, device: torch.device) -> None:
    del records
    random.seed(seed)
    torch.manual_seed(seed)
    if device.type == "cuda":
        torch.cuda.manual_seed_all(seed)


def _restore_checkpoint(
    path: Path,
    *,
    model: nn.Module,
    optimizer: torch.optim.Optimizer,
    scheduler: torch.optim.lr_scheduler.LRScheduler,
    sampler: FamilyBalancedSampler,
    config: RecordsTrainingConfig,
    seed: int,
    device: torch.device,
    contract: SETCompositionNetV2Manifest,
    supervision_source: Mapping[str, str],
) -> dict[str, Any]:
    checkpoint = torch.load(path, map_location="cpu", weights_only=False)
    if not isinstance(checkpoint, dict) or checkpoint.get("checkpoint_version") not in (CHECKPOINT_VERSION, LEGACY_CHECKPOINT_VERSION):
        raise TrainingError(f"checkpoint at {path} is not a {CHECKPOINT_VERSION} file")
    recorded = checkpoint.get("resume_semantic_sha256", checkpoint.get("config_sha256"))
    if recorded != resume_semantic_sha256(config) or checkpoint.get("seed") != seed:
        raise TrainingError(
            "checkpoint semantics (code/config/data/device) do not match the requested resume run; "
            "start a new run with an explicit warm-start instead"
        )
    checkpoint_supervision(checkpoint, contract, source=supervision_source)
    checkpoint_supervision(checkpoint, contract, source=supervision_source, selected_best=True)
    model.load_state_dict(checkpoint["model_state"])
    optimizer.load_state_dict(checkpoint["optimizer_state"])
    scheduler.load_state_dict(checkpoint["scheduler_state"])
    sampler.load_state_dict(checkpoint["sampler_state"])
    torch.set_rng_state(checkpoint["torch_rng_state"])
    random.setstate(checkpoint["python_rng_state"])
    if device.type == "cuda" and checkpoint.get("cuda_rng_state_all") is not None:
        torch.cuda.set_rng_state_all(checkpoint["cuda_rng_state_all"])
    return checkpoint


def train_one_seed(
    config: RecordsTrainingConfig,
    *,
    seed: int,
    run_dir: Path,
    contract: SETCompositionNetV2Manifest,
    loss_config: LossConfig,
    records: Sequence[TrainingRecord],
    argv: Sequence[str] = (),
    interrupt_after_epoch: int | None = None,
    resume_from: Path | None = None,
) -> dict[str, Any]:
    """Train one seed with validation, early stop, atomic checkpoint/resume."""

    validate_record_admission(records, config.dataset.admission)
    train_records = [record for record in records if record.split == "train"]
    validation_records = [record for record in records if record.split == "validation"]
    if not train_records:
        raise TrainingError("records bundle has no train split")
    if not validation_records:
        raise TrainingError("records bundle has no validation split")
    trained, train_masks = _available_heads(train_records, config, loss_config)
    train_records = _supervised_records(train_records, trained, ranking_enabled=loss_config.weights.ranking > 0)
    validation_records = _supervised_records(validation_records, trained, ranking_enabled=loss_config.weights.ranking > 0)
    if not train_records:
        raise TrainingError("train split has no supervised targets for the requested heads")
    if not validation_records:
        raise TrainingError("validation split has no supervised targets for the trained heads")

    device = _torch_device(config)
    _seed_records(records, seed, device)
    model = _make_model(config, contract, device)
    if device.type == "cuda":
        torch.cuda.reset_peak_memory_stats(device)
    for name, parameter in model.named_parameters():
        head = name.split(".")[1] if name.startswith("heads.") else None
        if head is not None and not trained.get(head, False):
            parameter.requires_grad_(False)
    trainable = [parameter for parameter in model.parameters() if parameter.requires_grad]
    if not trainable:
        raise TrainingError("trained-head mask froze every parameter")
    optimizer = torch.optim.AdamW(
        trainable, lr=config.training.learning_rate, weight_decay=config.training.weight_decay
    )
    scheduler = torch.optim.lr_scheduler.StepLR(
        optimizer, step_size=max(1, config.training.epochs // 3), gamma=0.5
    )
    sampler = FamilyBalancedSampler(train_records, seed=seed)
    pos_weights: dict[str, Tensor] = {}
    if config.training.class_weight_max > 0.0:
        for head in ("issue_logits", "action_utility_logits"):
            if trained.get(head, False):
                pos_weights[head] = class_pos_weights(
                    train_records, head, maximum=config.training.class_weight_max
                )

    start_epoch = 1
    best = {"score": float("inf"), "epoch": 0, "state": None}
    history: list[dict[str, Any]] = []
    resume_lineage: str | None = None
    checkpoint_path = run_dir / "checkpoint.pt"
    best_path = run_dir / "best.pt"
    supervision_source = dict(declared_dataset_sha256=config.dataset.sha256,
        observed_records_sha256=records_fingerprint(records), model_contract_sha256=config.model.manifest_sha256,
        effective_loss_sha256=canonical_hash(loss_config.as_mapping()), resume_semantic_sha256=resume_semantic_sha256(config))
    supervision = new_supervision(contract, supervision_source)
    if resume_from is not None:
        state = _restore_checkpoint(
            resume_from,
            model=model,
            optimizer=optimizer,
            scheduler=scheduler,
            sampler=sampler,
            config=config,
            seed=seed,
            device=device,
            contract=contract,
            supervision_source=supervision_source,
        )
        start_epoch = int(state["epoch"]) + 1
        best = dict(state["best"])
        supervision = checkpoint_supervision(state, contract, source=supervision_source)
        best["component_supervision"] = checkpoint_supervision(state, contract,
            source=supervision_source, selected_best=True)
        history = list(state["history"])
        resume_lineage = str(resume_from)

    model.train()
    stopped_early = False
    final_epoch = start_epoch - 1
    for epoch in range(start_epoch, config.training.epochs + 1):
        indices = sampler.epoch_indices()
        train_total = 0.0
        train_count = 0
        optimizer_steps = 0
        epoch_started = time.perf_counter()
        for start in range(0, len(indices), config.training.batch_size):
            batch_indices = indices[start : start + config.training.batch_size]
            batch = [train_records[index] for index in batch_indices]
            optimizer.zero_grad(set_to_none=True)
            total, _terms, observation = _batch_loss(
                model,
                batch,
                contract,
                loss_config,
                trained,
                pos_weights=pos_weights,
                augment=config.augmentation.horizontal_flip,
                seed=seed,
                epoch=epoch,
                device=device,
            )
            if not torch.isfinite(total):
                raise TrainingError(f"non-finite training loss at seed {seed} epoch {epoch}")
            if not observation["has_supervision"]:
                continue
            total.backward()
            _assert_actually_on_device(model, device, [total], "backward")
            for _name, parameter in model.named_parameters():
                if parameter.grad is not None and not torch.isfinite(parameter.grad).all():
                    raise TrainingError(f"non-finite gradient at seed {seed} epoch {epoch}")
            if config.training.gradient_clip > 0.0:
                torch.nn.utils.clip_grad_norm_(trainable, config.training.gradient_clip)
            optimizer.step()
            record_successful_step(supervision, observation)
            train_total += float(total.detach()) * len(batch)
            train_count += len(batch)
            optimizer_steps += 1
        if optimizer_steps == 0:
            raise TrainingError("epoch has no effective supervised optimizer steps")
        scheduler.step()
        validation_loss, per_head = _validate(
            model, validation_records, contract, loss_config, trained, config.training.batch_size, device
        )
        epoch_seconds = time.perf_counter() - epoch_started
        epoch_record = {
            "epoch": epoch,
            "train_loss": train_total / max(1, train_count),
            "validation_loss": validation_loss,
            "validation_per_head": per_head,
            "learning_rate": optimizer.param_groups[0]["lr"],
            "optimizer_steps": optimizer_steps,
            "successful_optimizer_steps_cumulative": supervision["successful_optimizer_steps"],
            "epoch_seconds": epoch_seconds,
            "seconds_per_optimizer_step": epoch_seconds / max(1, optimizer_steps),
            "device": device.type,
            "peak_vram_bytes": torch.cuda.max_memory_allocated(device) if device.type == "cuda" else 0,
        }
        history.append(epoch_record)
        final_epoch = epoch
        if validation_loss < best["score"]:
            best = {
                "score": validation_loss,
                "epoch": epoch,
                "state": {name: value.detach().clone() for name, value in model.state_dict().items()},
                "component_supervision": validate_supervision(supervision, contract),
            }
            _atomic_save_checkpoint(
                best_path,
                {
                    "checkpoint_version": CHECKPOINT_VERSION,
                    "config_sha256": config.config_sha256,
                    "resume_semantic_sha256": resume_semantic_sha256(config),
                    "runtime_profile": config.runtime_profile,
                    "device": device.type,
                    "seed": seed,
                    "epoch": epoch,
                    "score": validation_loss,
                    "model_state": model.state_dict(),
                    "enabled_head_mask": trained,
                    "trained_head_mask": observed_head_mask(supervision),
                    "component_supervision": validate_supervision(supervision, contract),
                },
            )
        elif epoch - best["epoch"] >= config.training.early_stop_patience:
            stopped_early = True
        _atomic_save_checkpoint(
            checkpoint_path,
            {
                "checkpoint_version": CHECKPOINT_VERSION,
                "config_sha256": config.config_sha256,
                "resume_semantic_sha256": resume_semantic_sha256(config),
                "runtime_profile": config.runtime_profile,
                "device": device.type,
                "seed": seed,
                "epoch": epoch,
                "model_state": model.state_dict(),
                "optimizer_state": optimizer.state_dict(),
                "scheduler_state": scheduler.state_dict(),
                "sampler_state": sampler.state_dict(),
                "torch_rng_state": torch.get_rng_state(),
                "python_rng_state": random.getstate(),
                "cuda_rng_state_all": torch.cuda.get_rng_state_all() if device.type == "cuda" else None,
                "best": best,
                "history": history,
                "enabled_head_mask": trained,
                "trained_head_mask": observed_head_mask(supervision),
                "component_supervision": validate_supervision(supervision, contract),
            },
        )
        if stopped_early or (interrupt_after_epoch is not None and epoch >= interrupt_after_epoch):
            break

    if best["state"] is None:
        raise TrainingError("no validation checkpoint was selected")
    model.load_state_dict(best["state"])
    model_hash = _state_hash(model)
    ranking_pairs = [pair for pair in eligible_ranking_pairs(train_records)]
    return {
        "seed": seed,
        "run_dir": str(run_dir),
        "start_epoch": start_epoch,
        "final_epoch": final_epoch,
        "stopped_early": stopped_early,
        "selection_rule": SELECTION_RULE,
        "selected_epoch": best["epoch"],
        "selected_validation_loss": best["score"],
        "enabled_head_mask": trained,
        "trained_head_mask": observed_head_mask(best["component_supervision"]),
        "component_supervision": validate_supervision(best["component_supervision"], contract),
        "final_component_supervision": validate_supervision(supervision, contract),
        "class_pos_weight_heads": sorted(pos_weights),
        "eligible_ranking_pairs": len(ranking_pairs),
        "history": history,
        "model_state_sha256": model_hash,
        "resume_lineage": resume_lineage,
        "checkpoint_path": str(checkpoint_path),
        "best_checkpoint_path": str(best_path),
        "device": device.type,
        "runtime_profile": config.runtime_profile,
        "peak_vram_bytes": torch.cuda.max_memory_allocated(device) if device.type == "cuda" else 0,
        "cuda_device_name": torch.cuda.get_device_name(device) if device.type == "cuda" else None,
    }


def _configure_records_runtime(config: RecordsTrainingConfig) -> dict[str, Any]:
    """Admit the declared runtime profile and return its receipt fragment."""

    if config.runtime_profile == "pinned_local":
        assert config.lock_sha256 is not None
        lock, lock_hash = _load_runtime_lock(config.lock_sha256)
        _verify_installed_closure(lock)
        _configure_runtime(config, lock)
        return {"lock_kind": "pinned_local_wheel_hash_closure", "lock_sha256": lock_hash}

    # colab_installed_runtime: Colab owns the base image, so the wheel-hash
    # closure is not applied.  The declared interpreter/Torch versions are
    # still checked against the installed runtime and the actual tensors are
    # proven on the requested device inside train_one_seed and preflight.
    if platform.python_implementation() != "CPython" or platform.python_version() != config.runtime.python_version:
        raise TrainingError(
            f"Python runtime drift: expected CPython {config.runtime.python_version}, "
            f"got {platform.python_implementation()} {platform.python_version()}"
        )
    if torch.__version__ != config.runtime.torch_version:
        raise TrainingError(f"Torch runtime drift: expected {config.runtime.torch_version}, got {torch.__version__}")
    if config.device == "cuda" and not torch.cuda.is_available():
        raise TrainingError("device='cuda' was declared but torch.cuda.is_available() is False")
    os.environ.setdefault("CUBLAS_WORKSPACE_CONFIG", ":4096:8")
    random.seed(config.seed)
    torch.manual_seed(config.seed)
    torch.set_num_threads(1)
    try:
        torch.set_num_interop_threads(1)
    except RuntimeError:
        pass
    torch.use_deterministic_algorithms(True)
    if not torch.are_deterministic_algorithms_enabled():
        raise TrainingError("PyTorch deterministic algorithms could not be enabled")
    return {"lock_kind": "colab_installed_runtime", "lock_sha256": None}


def _environment_receipt_v2(config: RecordsTrainingConfig, runtime: Mapping[str, Any]) -> dict[str, Any]:
    device = torch.device(config.device)
    fragment: dict[str, Any] = {
        "python": {
            "implementation": platform.python_implementation(),
            "version": platform.python_version(),
        },
        "torch": {"version": torch.__version__, "cuda_version": torch.version.cuda},
        "lock": {"kind": runtime["lock_kind"], "sha256": runtime["lock_sha256"]},
        "platform": {
            "system": platform.system(),
            "release": platform.release(),
            "machine": platform.machine(),
        },
        "runtime": {
            "profile": config.runtime_profile,
            "requested_device": config.device,
            "actual_device": device.type,
            "cuda_available": bool(torch.cuda.is_available()),
            "deterministic_algorithms": torch.are_deterministic_algorithms_enabled(),
            "deterministic_warn_only": torch.is_deterministic_algorithms_warn_only_enabled(),
            "torch_num_threads": torch.get_num_threads(),
            "torch_num_interop_threads": torch.get_num_interop_threads(),
        },
    }
    if device.type == "cuda":
        fragment["runtime"]["cuda_device_name"] = torch.cuda.get_device_name(device)
        fragment["runtime"]["cuda_total_memory_bytes"] = torch.cuda.get_device_properties(device).total_memory
    return fragment


def run_records_training(
    config: RecordsTrainingConfig,
    *,
    config_path: str | Path,
    run_dir: str | Path | None = None,
    argv: Sequence[str] = (),
) -> dict[str, object]:
    """Admit the environment, load typed records, and train every configured seed."""

    target = _new_run_dir(config, run_dir)
    if target.exists():
        raise TrainingError(f"output target already exists: {target}")

    runtime = _configure_records_runtime(config)
    environment = _environment_receipt_v2(config, runtime)
    command = _command_receipt(argv)

    manifest_path = _resolve_repo_path(config.model.manifest_path)
    if manifest_path.resolve() != (Path(__file__).resolve().parents[2] / MODEL_MANIFEST_RELATIVE).resolve():
        raise TrainingError(f"model manifest path is not the frozen v2 path: {manifest_path}")
    manifest_hash = _file_hash(manifest_path)
    if manifest_hash != config.model.manifest_sha256:
        raise TrainingError(
            f"v2 manifest hash mismatch: expected {config.model.manifest_sha256}, got {manifest_hash}"
        )
    contract = SETCompositionNetV2Manifest.load(manifest_path)

    loss_path = _resolve_repo_path(config.loss.path)
    if loss_path.resolve() != (Path(__file__).resolve().parents[2] / LOSS_CONFIG_RELATIVE).resolve():
        raise TrainingError(f"loss config path is not the frozen path: {loss_path}")
    loss_hash = _file_hash(loss_path)
    if loss_hash != config.loss.sha256:
        raise TrainingError(f"loss config hash mismatch: expected {config.loss.sha256}, got {loss_hash}")
    loss_config = LossConfig.from_file(loss_path)

    records_path = _resolve_repo_path(config.dataset.path)
    records_hash = _file_hash(records_path)
    if records_hash != config.dataset.sha256:
        raise TrainingError(
            f"records hash mismatch: expected {config.dataset.sha256}, got {records_hash}"
        )
    try:
        records = load_records(records_path, config.dataset.sha256, admission=config.dataset.admission)
    except TrainingRecordError as exc:
        raise TrainingError(f"typed training records rejected: {exc}") from exc
    sealed = sorted(record.record_id for record in records if record.split == "locked_test")
    if sealed:
        raise TrainingError(f"locked_test records must stay sealed and cannot enter a training bundle: {sealed}")
    unknown_splits = sorted({record.split for record in records} - set(TRAINABLE_SPLITS))
    if unknown_splits:
        raise TrainingError(f"training bundle has non-trainable splits: {unknown_splits}")

    try:
        target.mkdir(parents=True, exist_ok=False)
    except FileExistsError as exc:
        raise TrainingError(f"refusing to overwrite existing output: {target}") from exc
    _atomic_write_json(target / "config.json", config.as_mapping())

    if config.resume_from is not None and len(config.seeds) != 1:
        raise TrainingError(
            f"resume_from requires exactly one seed, got {len(config.seeds)}; refusing to silently start from scratch"
        )
    seed_results = []
    for seed in config.seeds:
        seed_dir = target / f"seed-{seed}"
        seed_dir.mkdir(parents=True, exist_ok=False)
        resume_from = None
        if config.resume_from is not None:
            resume_from = Path(config.resume_from).expanduser().resolve()
        result = train_one_seed(
            config,
            seed=seed,
            run_dir=seed_dir,
            contract=contract,
            loss_config=loss_config,
            records=records,
            argv=argv,
            resume_from=resume_from,
        )
        seed_results.append(result)
        _atomic_write_json(seed_dir / "result.json", result)

    selected = min(seed_results, key=lambda item: (item["selected_validation_loss"], item["seed"]))
    declared_admitted = config.dataset.admission == "declared_admitted"
    receipt: dict[str, object] = {
        "receipt_version": RECEIPT_VERSION,
        "status": "pass",
        "scope": "M01-production-capable-loader-losses-trainer",
        "mode": MODE,
        "data_admission": {
            "declared": config.dataset.admission,
            "rights_manifest_sha256": config.dataset.rights_manifest_sha256,
            "note": (
                "declared admission is a producer claim; M01 does not verify rights. "
                "A full admitted human fit remains blocked until D04 supplies admitted records."
                if declared_admitted
                else "non-admitted research bundle used for the narrowest smoke; no quality claim."
            ),
        },
        "config": config.as_mapping(),
        "dataset": {
            "path": _path_for_receipt(records_path),
            "sha256": records_hash,
            "record_count": len(records),
            "train_count": sum(1 for record in records if record.split == "train"),
            "validation_count": sum(1 for record in records if record.split == "validation"),
        },
        "model": {
            "candidate": config.candidate,
            "manifest": _path_for_receipt(manifest_path),
            "manifest_sha256": manifest_hash,
        },
        "loss": {"path": _path_for_receipt(loss_path), "sha256": loss_hash},
        "selection_rule": SELECTION_RULE,
        "augmentation": {"horizontal_flip": config.augmentation.horizontal_flip},
        "seeds": seed_results,
        "selected_seed": selected["seed"],
        "selected_validation_loss": selected["selected_validation_loss"],
        "environment": environment,
        "command": command,
        "config_sha256": config.config_sha256,
        "resume_semantic_sha256": resume_semantic_sha256(config),
        "runtime_profile": config.runtime_profile,
        "device": config.device,
        "lock_sha256": config.lock_sha256,
    }
    receipt["hashes"] = {
        "config_sha256": config.config_sha256,
        "resume_semantic_sha256": resume_semantic_sha256(config),
        "records_sha256": records_hash,
        "model_manifest_sha256": manifest_hash,
        "loss_config_sha256": loss_hash,
        "lock_sha256": config.lock_sha256,
        "environment_sha256": _canonical_hash(environment),
        "command_sha256": _canonical_hash(command),
    }
    receipt["hashes"]["receipt_sha256"] = _canonical_hash(receipt)
    _atomic_write_json(target / "receipt.json", receipt)
    return receipt


def run_from_config(
    config_path: str | Path,
    *,
    run_dir: str | Path | None = None,
    argv: Sequence[str] = (),
) -> dict[str, object]:
    config = RecordsTrainingConfig.from_file(config_path)
    return run_records_training(config, config_path=config_path, run_dir=run_dir, argv=argv)


__all__ = [
    "CONFIG_VERSION",
    "MODE",
    "RECEIPT_VERSION",
    "SELECTION_RULE",
    "RecordsTrainingConfig",
    "run_from_config",
    "run_records_training",
    "train_one_seed",
]
