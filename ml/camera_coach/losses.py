"""Manifest-shaped multi-task losses for disabled SETCompositionNet candidates.

This module owns loss math only.  Labels are caller supplied; a missing label
is represented by a zero mask and contributes neither value nor gradient.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
import json
import math
from pathlib import Path
from types import MappingProxyType
from typing import Any

import torch
from torch import Tensor
from torch.nn import functional as F

from .models.set_composition_net import SETCompositionNetManifest
from .models.set_composition_net_v2 import INTENT_CONDITIONED_HEAD_ORDER


MANIFEST = SETCompositionNetManifest.load()
HEAD_NAMES = MANIFEST.output_head_names
DIRECT_LOSS_HEADS = tuple(name for name in HEAD_NAMES if name != MANIFEST.embedding_name)
LOSS_TERM_NAMES = DIRECT_LOSS_HEADS + ("ranking", "contrastive")
CONFIG_VERSION = "camera_losses.v1"


class LossError(ValueError):
    """Raised when predictions, labels, masks, or weights are malformed."""


def _finite_tensor(value: Tensor, label: str) -> None:
    if not isinstance(value, Tensor):
        raise LossError(f"{label} must be a torch.Tensor")
    if value.dtype.is_complex:
        raise LossError(f"{label} must be real")
    if not torch.is_floating_point(value):
        # Integer labels are valid for scene CE; callers validate them at the
        # loss boundary.  This helper only rejects NaN/Inf when meaningful.
        return
    if not torch.isfinite(value).all():
        raise LossError(f"{label} must contain only finite values")


def _as_float_weight(value: object, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise LossError(f"{label} must be a finite non-negative number")
    result = float(value)
    if not math.isfinite(result) or result < 0.0:
        raise LossError(f"{label} must be a finite non-negative number")
    return result


def _as_finite_float(value: object, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise LossError(f"{label} must be a finite number")
    result = float(value)
    if not math.isfinite(result):
        raise LossError(f"{label} must be a finite number")
    return result


def _mask_for(values: Tensor, mask: Tensor | None, label: str) -> Tensor:
    if mask is None:
        return torch.ones_like(values, dtype=values.dtype)
    if not isinstance(mask, Tensor):
        raise LossError(f"{label} must be a tensor")
    if mask.dtype.is_complex:
        raise LossError(f"{label} must be a real 0/1 tensor")
    _finite_tensor(mask, label)
    if mask.shape == values.shape:
        result = mask.to(dtype=values.dtype, device=values.device)
    elif mask.ndim == 1 and values.ndim >= 2 and mask.shape[0] == values.shape[0]:
        result = mask.to(dtype=values.dtype, device=values.device).reshape(mask.shape[0], *([1] * (values.ndim - 1)))
    elif mask.ndim == 2 and values.ndim >= 2 and mask.shape == (values.shape[0], 1):
        result = mask.to(dtype=values.dtype, device=values.device).reshape(mask.shape[0], *([1] * (values.ndim - 1)))
    else:
        raise LossError(f"{label} shape {tuple(mask.shape)} does not match {tuple(values.shape)}")
    # A sample-level mask applies to every element in that sample.  Expand it
    # before summing so the denominator counts the same elements as the
    # numerator; otherwise a [B] mask would scale a [B, C] loss by C.
    if result.shape != values.shape:
        result = result.expand_as(values)
    if torch.any((result != 0.0) & (result != 1.0)):
        raise LossError(f"{label} must contain only 0/1 values")
    return result


def masked_mean(values: Tensor, mask: Tensor | None = None, *, label: str = "mask") -> Tensor:
    """Reduce finite per-element values over available labels only."""

    _finite_tensor(values, "loss values")
    active = _mask_for(values, mask, label)
    denominator = active.sum()
    # Keep a differentiable zero when every label is unavailable.  This makes
    # ``backward`` produce exact zero gradients for that task.
    return (values * active).sum() / denominator if denominator.item() else values.sum() * 0.0


def focal_binary_cross_entropy(
    logits: Tensor,
    targets: Tensor,
    mask: Tensor | None = None,
    *,
    gamma: float = 2.0,
    alpha: float = 0.25,
    pos_weight: Tensor | None = None,
) -> Tensor:
    """Focal BCE for multi-label issue/action heads.

    ``pos_weight`` is an optional per-class positive-class weight.  It is
    applied by the train split only; validation and evaluation pass ``None``.
    """

    _finite_tensor(logits, "logits")
    _finite_tensor(targets, "targets")
    if logits.shape != targets.shape:
        raise LossError(f"focal BCE logits/targets shape mismatch: {tuple(logits.shape)} vs {tuple(targets.shape)}")
    gamma = _as_finite_float(gamma, "focal gamma")
    alpha = _as_finite_float(alpha, "focal alpha")
    if gamma < 0.0:
        raise LossError("focal gamma must be finite and non-negative")
    if not 0.0 <= alpha <= 1.0:
        raise LossError("focal alpha must be finite in [0, 1]")
    if pos_weight is not None:
        if not isinstance(pos_weight, Tensor) or pos_weight.ndim != 1 or pos_weight.shape[0] != logits.shape[1]:
            raise LossError(f"pos_weight must be a [{logits.shape[1]}] tensor")
        _finite_tensor(pos_weight, "pos_weight")
        if torch.any(pos_weight <= 0.0):
            raise LossError("pos_weight must be strictly positive")
        pos_weight = pos_weight.to(dtype=logits.dtype, device=logits.device)
    target = targets.to(dtype=logits.dtype, device=logits.device)
    if torch.any((target < 0.0) | (target > 1.0)):
        raise LossError("focal BCE targets must be in [0, 1]")
    base = F.binary_cross_entropy_with_logits(logits, target, reduction="none", pos_weight=pos_weight)
    probability_of_target = torch.exp(-base)
    balancing = alpha * target + (1.0 - alpha) * (1.0 - target)
    return masked_mean(balancing * (1.0 - probability_of_target).pow(gamma) * base, mask)


def cross_entropy(logits: Tensor, targets: Tensor, mask: Tensor | None = None) -> Tensor:
    """Categorical cross-entropy for scene classes."""

    _finite_tensor(logits, "scene logits")
    if logits.ndim != 2 or logits.shape[1] < 2:
        raise LossError("cross-entropy logits must have shape [batch, classes]")
    if not isinstance(targets, Tensor) or targets.dtype not in {
        torch.uint8, torch.int8, torch.int16, torch.int32, torch.int64,
    }:
        raise LossError("cross-entropy targets must be an integer tensor")
    if targets.ndim == 2 and targets.shape[1] == 1:
        targets = targets[:, 0]
    if targets.ndim != 1 or targets.shape[0] != logits.shape[0]:
        raise LossError("cross-entropy targets must have shape [batch]")
    if torch.any((targets < 0) | (targets >= logits.shape[1])):
        raise LossError("cross-entropy class index is outside the logits dimension")
    values = F.cross_entropy(logits, targets.to(device=logits.device), reduction="none")
    if mask is not None and mask.ndim == 2 and mask.shape[1] == 1:
        mask = mask[:, 0]
    return masked_mean(values, mask, label="cross-entropy mask")


def smooth_l1_loss(
    predictions: Tensor,
    targets: Tensor,
    mask: Tensor | None = None,
    *,
    beta: float = 1.0,
) -> Tensor:
    """Smooth L1/Huber loss for bounded continuous target deltas."""

    _finite_tensor(predictions, "continuous predictions")
    _finite_tensor(targets, "continuous targets")
    if predictions.shape != targets.shape:
        raise LossError("smooth L1 predictions/targets shape mismatch")
    beta = _as_finite_float(beta, "smooth L1 beta")
    if beta <= 0.0:
        raise LossError("smooth L1 beta must be finite and positive")
    return masked_mean(F.smooth_l1_loss(predictions, targets.to(predictions), beta=beta, reduction="none"), mask)


def binary_cross_entropy(logits: Tensor, targets: Tensor, mask: Tensor | None = None) -> Tensor:
    """Masked BCE for bounded probability heads in the frozen output contract."""

    _finite_tensor(logits, "binary probabilities")
    _finite_tensor(targets, "binary targets")
    if logits.shape != targets.shape:
        raise LossError("binary BCE probabilities/targets shape mismatch")
    if torch.any((logits < 0.0) | (logits > 1.0)):
        raise LossError("binary BCE probabilities must be in [0, 1]")
    target = targets.to(dtype=logits.dtype, device=logits.device)
    if torch.any((target < 0.0) | (target > 1.0)):
        raise LossError("binary BCE targets must be in [0, 1]")
    return masked_mean(F.binary_cross_entropy(logits, target, reduction="none"), mask)


def binary_cross_entropy_with_logits(logits: Tensor, targets: Tensor, mask: Tensor | None = None) -> Tensor:
    """Masked BCE-with-logits for unbounded operational logit heads."""

    _finite_tensor(logits, "binary logits")
    _finite_tensor(targets, "binary targets")
    if logits.shape != targets.shape:
        raise LossError("binary BCE logits/targets shape mismatch")
    target = targets.to(dtype=logits.dtype, device=logits.device)
    if torch.any((target < 0.0) | (target > 1.0)):
        raise LossError("binary BCE targets must be in [0, 1]")
    return masked_mean(F.binary_cross_entropy_with_logits(logits, target, reduction="none"), mask)


def _pair_tensor(value: object, label: str, *, dtype: torch.dtype | None = None) -> Tensor:
    if not isinstance(value, Tensor):
        try:
            value = torch.as_tensor(value)
        except Exception as exc:  # pragma: no cover - torch formats vary.
            raise LossError(f"{label} must be tensor-like") from exc
    if value.ndim == 0:
        value = value.reshape(1)
    if dtype is not None:
        value = value.to(dtype=dtype)
    _finite_tensor(value, label)
    return value


def _pair_parts(spec: object, label: str) -> tuple[Tensor, Tensor, Tensor | None, Tensor | None, Tensor | None]:
    """Read a pair mapping without manufacturing labels for absent fields."""

    if isinstance(spec, PairLabels):
        return spec.first, spec.second, spec.labels, spec.mask, spec.contrastive_labels
    if isinstance(spec, Mapping):
        indices = spec.get("indices", spec.get("pairs"))
        first = spec.get("first", spec.get("first_indices"))
        second = spec.get("second", spec.get("second_indices"))
        if indices is not None:
            pair_indices = _pair_tensor(indices, f"{label}.indices")
            if pair_indices.ndim != 2 or pair_indices.shape[1] != 2:
                raise LossError(f"{label}.indices must have shape [pairs, 2]")
            if first is not None or second is not None:
                raise LossError(f"{label} cannot provide both indices and first/second")
            first, second = pair_indices[:, 0], pair_indices[:, 1]
        if first is None or second is None:
            raise LossError(f"{label} needs pair indices")
        labels = spec.get("labels", spec.get("preference"))
        mask = spec.get("mask", spec.get("available"))
        contrastive = spec.get("contrastive_labels", spec.get("same"))
        return (
            _pair_tensor(first, f"{label}.first"),
            _pair_tensor(second, f"{label}.second"),
            None if labels is None else _pair_tensor(labels, f"{label}.labels"),
            None if mask is None else _pair_tensor(mask, f"{label}.mask"),
            None if contrastive is None else _pair_tensor(contrastive, f"{label}.contrastive_labels"),
        )
    if isinstance(spec, Sequence) and not isinstance(spec, (str, bytes, bytearray)) and len(spec) in (3, 4):
        first, second, labels = spec[:3]
        mask = spec[3] if len(spec) == 4 else None
        return (
            _pair_tensor(first, f"{label}.first"),
            _pair_tensor(second, f"{label}.second"),
            _pair_tensor(labels, f"{label}.labels"),
            None if mask is None else _pair_tensor(mask, f"{label}.mask"),
            None,
        )
    raise LossError(f"{label} must be PairLabels or a pair mapping")


def _validate_pair_indices(first: Tensor, second: Tensor, batch_size: int, label: str) -> tuple[Tensor, Tensor]:
    if first.shape != second.shape or first.ndim != 1:
        raise LossError(f"{label} pair indices must be matching vectors")
    if first.dtype not in {torch.uint8, torch.int8, torch.int16, torch.int32, torch.int64} \
            or second.dtype not in {torch.uint8, torch.int8, torch.int16, torch.int32, torch.int64}:
        if torch.any(first != first.round()) or torch.any(second != second.round()):
            raise LossError(f"{label} pair indices must be integers")
    first = first.to(dtype=torch.long)
    second = second.to(dtype=torch.long)
    if torch.any(first < 0) or torch.any(first >= batch_size) or torch.any(second < 0) or torch.any(second >= batch_size):
        raise LossError(f"{label} pair index is outside the batch")
    return first, second


def pairwise_ranking_loss(
    scores: Tensor,
    pairs: Tensor,
    labels: Tensor,
    mask: Tensor | None = None,
    *,
    margin: float = 0.1,
) -> Tensor:
    """Margin ranking where label 1 means first is preferred, 0 second."""

    _finite_tensor(scores, "ranking scores")
    if scores.ndim not in (1, 2) or (scores.ndim == 2 and scores.shape[1] != 1):
        raise LossError("ranking scores must have shape [batch] or [batch, 1]")
    flat_scores = scores.reshape(scores.shape[0])
    pair_indices = _pair_tensor(pairs, "ranking pairs")
    if pair_indices.ndim != 2 or pair_indices.shape[1] != 2:
        raise LossError("ranking pairs must have shape [pairs, 2]")
    first, second = _validate_pair_indices(pair_indices[:, 0], pair_indices[:, 1], flat_scores.shape[0], "ranking")
    labels = _pair_tensor(labels, "ranking labels").reshape(-1)
    if labels.shape[0] != first.shape[0] or torch.any((labels != 0.0) & (labels != 1.0)):
        raise LossError("ranking labels must be one value per pair and contain only 0/1")
    margin = _as_finite_float(margin, "ranking margin")
    if margin < 0.0:
        raise LossError("ranking margin must be finite and non-negative")
    direction = labels.to(dtype=flat_scores.dtype, device=flat_scores.device).mul(2.0).sub(1.0)
    values = F.relu(margin - direction * (flat_scores[first] - flat_scores[second]))
    return masked_mean(values, mask, label="ranking mask")


def pairwise_contrastive_loss(
    embeddings: Tensor,
    pairs: Tensor,
    labels: Tensor,
    mask: Tensor | None = None,
    *,
    margin: float = 1.0,
) -> Tensor:
    """Contrastive embedding loss where label 1 means the pair is positive."""

    _finite_tensor(embeddings, "embedding")
    if embeddings.ndim != 2 or embeddings.shape[1] < 1:
        raise LossError("embeddings must have shape [batch, dimension]")
    pair_indices = _pair_tensor(pairs, "contrastive pairs")
    if pair_indices.ndim != 2 or pair_indices.shape[1] != 2:
        raise LossError("contrastive pairs must have shape [pairs, 2]")
    first, second = _validate_pair_indices(pair_indices[:, 0], pair_indices[:, 1], embeddings.shape[0], "contrastive")
    labels = _pair_tensor(labels, "contrastive labels").reshape(-1)
    if labels.shape[0] != first.shape[0] or torch.any((labels != 0.0) & (labels != 1.0)):
        raise LossError("contrastive labels must be one value per pair and contain only 0/1")
    margin = _as_finite_float(margin, "contrastive margin")
    if margin < 0.0:
        raise LossError("contrastive margin must be finite and non-negative")
    distances = torch.linalg.vector_norm(embeddings[first] - embeddings[second], dim=1)
    positive = labels.to(dtype=distances.dtype, device=distances.device) * distances.square()
    negative = (1.0 - labels.to(dtype=distances.dtype, device=distances.device)) * F.relu(margin - distances).square()
    return masked_mean(positive + negative, mask, label="contrastive mask")


@dataclass(frozen=True)
class PairLabels:
    """Pair supervision; ``labels`` is preference for ranking.

    ``contrastive_labels`` is intentionally separate: a preference pair is not
    silently reinterpreted as a same/different embedding label.
    """

    first: Tensor
    second: Tensor
    labels: Tensor | None = None
    mask: Tensor | None = None
    contrastive_labels: Tensor | None = None

    @classmethod
    def from_mapping(cls, value: Mapping[str, object]) -> "PairLabels":
        first, second, labels, mask, contrastive = _pair_parts(value, "pair labels")
        return cls(first, second, labels, mask, contrastive)


@dataclass(frozen=True)
class LossWeights:
    """Explicit weights for every canonical direct/pair loss term."""

    scene_class_logits: float = 1.0
    subjectness_roi_agreement_logits: float = 1.0
    issue_logits: float = 1.0
    action_utility_logits: float = 1.0
    good_frame_probability: float = 1.0
    abstention_probability: float = 1.0
    risk_probability: float = 1.0
    continuous_target_deltas: float = 1.0
    ranking: float = 1.0
    contrastive: float = 1.0

    def __post_init__(self) -> None:
        for name in LOSS_TERM_NAMES:
            _as_float_weight(getattr(self, name), f"loss weight {name}")

    @classmethod
    def from_mapping(cls, value: Mapping[str, object] | None) -> "LossWeights":
        if value is None:
            return cls()
        if not isinstance(value, Mapping):
            raise LossError("loss weights must be an object")
        expected = set(LOSS_TERM_NAMES)
        if set(value) != expected:
            raise LossError(f"loss weights must name exactly {sorted(expected)}")
        parsed = {name: _as_float_weight(value[name], f"loss weight {name}") for name in LOSS_TERM_NAMES}
        return cls(**parsed)

    def as_mapping(self) -> dict[str, float]:
        return {name: float(getattr(self, name)) for name in LOSS_TERM_NAMES}


@dataclass(frozen=True)
class LossConfig:
    """Closed hyperparameter/config view used by the deterministic train smoke."""

    weights: LossWeights
    focal_gamma: float = 2.0
    focal_alpha: float = 0.25
    ranking_margin: float = 0.1
    contrastive_margin: float = 1.0

    @classmethod
    def from_mapping(cls, value: Mapping[str, object]) -> "LossConfig":
        if not isinstance(value, Mapping):
            raise LossError("loss config must be an object")
        expected = {"config_version", "weights", "focal_gamma", "focal_alpha", "ranking_margin", "contrastive_margin"}
        if set(value) != expected or value.get("config_version") != CONFIG_VERSION:
            raise LossError("loss config keys/version drifted")
        weights = value.get("weights")
        if not isinstance(weights, Mapping):
            raise LossError("loss config weights must be an object")
        gamma = _as_finite_float(value["focal_gamma"], "loss config focal_gamma")
        alpha = _as_finite_float(value["focal_alpha"], "loss config focal_alpha")
        ranking_margin = _as_finite_float(value["ranking_margin"], "loss config ranking_margin")
        contrastive_margin = _as_finite_float(value["contrastive_margin"], "loss config contrastive_margin")
        if gamma < 0.0 or not 0.0 <= alpha <= 1.0 or ranking_margin < 0.0 or contrastive_margin < 0.0:
            raise LossError("loss config hyperparameters are out of range")
        return cls(LossWeights.from_mapping(weights), gamma, alpha, ranking_margin, contrastive_margin)

    def __post_init__(self) -> None:
        if not isinstance(self.weights, LossWeights):
            raise LossError("loss config weights must be LossWeights")
        gamma = _as_finite_float(self.focal_gamma, "loss config focal_gamma")
        alpha = _as_finite_float(self.focal_alpha, "loss config focal_alpha")
        ranking_margin = _as_finite_float(self.ranking_margin, "loss config ranking_margin")
        contrastive_margin = _as_finite_float(self.contrastive_margin, "loss config contrastive_margin")
        if gamma < 0.0 or not 0.0 <= alpha <= 1.0 or ranking_margin < 0.0 or contrastive_margin < 0.0:
            raise LossError("loss config hyperparameters are out of range")

    @classmethod
    def from_file(cls, path: str | Path) -> "LossConfig":
        try:
            with Path(path).open(encoding="utf-8") as stream:
                raw = json.load(stream)
        except (OSError, json.JSONDecodeError) as exc:
            raise LossError(f"cannot load loss config: {path}") from exc
        if not isinstance(raw, Mapping):
            raise LossError("loss config must be an object")
        return cls.from_mapping(raw)

    def as_mapping(self) -> dict[str, object]:
        return {
            "config_version": CONFIG_VERSION,
            "weights": self.weights.as_mapping(),
            "focal_gamma": self.focal_gamma,
            "focal_alpha": self.focal_alpha,
            "ranking_margin": self.ranking_margin,
            "contrastive_margin": self.contrastive_margin,
        }


@dataclass(frozen=True)
class LossResult:
    """Canonical total and inspectable terms from one multi-task reduction."""

    total: Tensor
    per_head: Mapping[str, Tensor]
    ranking: Tensor
    contrastive: Tensor

    @property
    def terms(self) -> Mapping[str, Tensor]:
        return MappingProxyType({**self.per_head, "ranking": self.ranking, "contrastive": self.contrastive})


def _prediction_targets(
    outputs: Mapping[str, Tensor],
    targets: Mapping[str, Tensor],
    masks: Mapping[str, Tensor] | None,
) -> tuple[dict[str, Tensor], dict[str, Tensor], int]:
    if not isinstance(outputs, Mapping) or not isinstance(targets, Mapping):
        raise LossError("outputs and targets must be mappings")
    output_names = set(outputs)
    unknown_outputs = output_names.difference(HEAD_NAMES)
    missing_outputs = set(HEAD_NAMES).difference(output_names)
    unknown_targets = set(targets).difference(HEAD_NAMES)
    if unknown_outputs or unknown_targets:
        raise LossError(f"unknown output/target heads: {sorted(unknown_outputs | unknown_targets)}")
    if missing_outputs:
        raise LossError(f"outputs must contain every manifest head; missing={sorted(missing_outputs)}")
    output_values: dict[str, Tensor] = {}
    for name, prediction in outputs.items():
        if not isinstance(prediction, Tensor):
            raise LossError(f"output {name} must be a tensor")
        _finite_tensor(prediction, f"output {name}")
        expected_width = MANIFEST.output_head_shapes[name]
        if prediction.ndim == 1 and expected_width == 1:
            prediction = prediction.reshape(-1, 1)
        if prediction.ndim != 2 or prediction.shape[1] != expected_width:
            raise LossError(f"output {name} must have shape [batch, {expected_width}]")
        output_values[name] = prediction
    batch_sizes = {prediction.shape[0] for prediction in output_values.values()}
    if len(batch_sizes) != 1:
        raise LossError("all output heads must share a batch dimension")
    batch_size = next(iter(batch_sizes))
    if batch_size < 1:
        raise LossError("outputs must contain at least one sample")
    target_values: dict[str, Tensor] = {}
    for name, target in targets.items():
        if not isinstance(target, Tensor):
            raise LossError(f"target {name} must be a tensor")
        _finite_tensor(target, f"target {name}")
        expected_width = MANIFEST.output_head_shapes[name]
        if name == "scene_class_logits":
            if target.dtype not in {
                torch.uint8, torch.int8, torch.int16, torch.int32, torch.int64,
            }:
                raise LossError("scene class targets must be an integer tensor")
            if target.ndim == 2 and target.shape[1] == 1:
                target = target[:, 0]
            if target.ndim != 1 or target.shape[0] != batch_size:
                raise LossError("scene class targets must have shape [batch]")
        else:
            if target.ndim == 1 and expected_width == 1:
                target = target.reshape(-1, 1)
            if target.ndim != 2 or target.shape != (batch_size, expected_width):
                raise LossError(f"target {name} must have shape [batch, {expected_width}]")
        target_values[name] = target
    if masks is not None and not isinstance(masks, Mapping):
        raise LossError("label masks must be a mapping of manifest head names")
    label_masks = masks or {}
    if not isinstance(label_masks, Mapping) or set(label_masks).difference(HEAD_NAMES):
        raise LossError("label masks must be a mapping of manifest head names")
    for name, mask in label_masks.items():
        reference = output_values.get(name)
        if reference is None:
            reference = target_values.get(name)
        if reference is None:
            raise LossError(f"label mask {name} has no corresponding output or target")
        if name == "scene_class_logits" and isinstance(mask, Tensor) and mask.ndim == 2 and mask.shape[1] == 1:
            mask = mask[:, 0]
        _mask_for(reference, mask, f"{name} mask")
    # Targets absent from a batch are unavailable, not implicit supervision.
    return output_values, target_values, batch_size


def merge_intent_supervision_mask(
    outputs: Mapping[str, Tensor],
    masks: Mapping[str, Tensor] | None,
    intent_mask: Tensor | None,
    *,
    batch_size: int,
) -> dict[str, Tensor]:
    """Fold the frozen `[B, 4]` intent mask into the four head masks.

    A head with no caller mask but a zero intent column receives an explicit
    all-zero mask, so the head contributes exactly zero loss and zero gradient
    instead of silently falling back to an all-ones mask.
    """

    merged: dict[str, Tensor] = dict(masks or {})
    if intent_mask is None:
        return merged
    if not isinstance(intent_mask, Tensor) or intent_mask.ndim not in (1, 2):
        raise LossError("intent_mask must be a [B] or [B, 4] tensor")
    if intent_mask.ndim == 2 and intent_mask.shape[1] != len(INTENT_CONDITIONED_HEAD_ORDER):
        raise LossError("intent_mask second dimension must mirror the four intent-conditioned heads")
    _finite_tensor(intent_mask, "intent_mask")
    if torch.any((intent_mask != 0.0) & (intent_mask != 1.0)):
        raise LossError("intent_mask must contain only 0/1 values")
    if intent_mask.shape[0] != batch_size:
        raise LossError("intent_mask first dimension must match the output batch")
    for index, head in enumerate(INTENT_CONDITIONED_HEAD_ORDER):
        reference = outputs.get(head)
        if reference is None:
            raise LossError(f"intent-conditioned head {head} is missing from outputs")
        sample = intent_mask if intent_mask.ndim == 1 else intent_mask[:, index]
        existing = merged.get(head)
        if existing is None:
            merged[head] = sample.to(dtype=reference.dtype, device=reference.device).reshape(
                batch_size, *([1] * (reference.ndim - 1))
            )
        elif existing.ndim == 1:
            merged[head] = existing * sample.to(dtype=existing.dtype, device=existing.device)
        else:
            merged[head] = existing * sample.to(dtype=existing.dtype, device=existing.device).reshape(
                batch_size, *([1] * (existing.ndim - 1))
            )
    return merged


def compute_multitask_loss(
    outputs: Mapping[str, Tensor],
    targets: Mapping[str, Tensor],
    *,
    masks: Mapping[str, Tensor] | None = None,
    label_masks: Mapping[str, Tensor] | None = None,
    intent_mask: Tensor | None = None,
    head_pos_weights: Mapping[str, Tensor] | None = None,
    pair_labels: Mapping[str, object] | None = None,
    contrastive_pairs: Mapping[str, object] | None = None,
    weights: LossWeights | Mapping[str, object] | None = None,
    config: LossConfig | None = None,
) -> LossResult:
    """Compute weighted manifest losses and optional labelled pair terms.

    ``intent_mask`` is the frozen `[B]`/`[B, 4]` admissibility mask for the
    intent-conditioned heads; it can only remove supervision, never add it.
    ``head_pos_weights`` supplies train-only per-class positive weights for the
    multi-label issue/utility heads.
    """

    if masks is not None and label_masks is not None:
        raise LossError("pass masks or label_masks, not both")
    if config is None:
        selected_weights = LossWeights.from_mapping(weights) if isinstance(weights, Mapping) else weights or LossWeights()
        if not isinstance(selected_weights, LossWeights):
            raise LossError("weights must be LossWeights or a complete mapping")
        config = LossConfig(selected_weights)
    elif weights is not None:
        raise LossError("pass config or weights, not both")
    if not isinstance(config, LossConfig):
        raise LossError("config must be LossConfig")
    if head_pos_weights is not None and not isinstance(head_pos_weights, Mapping):
        raise LossError("head_pos_weights must be a mapping of head name to per-class weight")
    output_values, targets, batch_size = _prediction_targets(outputs, targets, label_masks or masks)
    active_masks = merge_intent_supervision_mask(output_values, label_masks or masks, intent_mask, batch_size=batch_size)
    raw_terms: dict[str, Tensor] = {}
    weighted_terms: dict[str, Tensor] = {}

    def absent(prediction: Tensor) -> Tensor:
        return prediction.sum() * 0.0

    for name in DIRECT_LOSS_HEADS:
        prediction = outputs.get(name)
        target = targets.get(name)
        if prediction is None or target is None:
            raw_terms[name] = absent(prediction if prediction is not None else next(iter(outputs.values())))
            weighted_terms[name] = raw_terms[name] * float(getattr(config.weights, name))
            continue
        mask = active_masks.get(name)
        if name == "scene_class_logits":
            raw = cross_entropy(prediction, target, mask)
        elif name in {"issue_logits", "action_utility_logits"}:
            if target.shape != prediction.shape:
                raise LossError(f"{name} targets must match logits shape")
            raw = focal_binary_cross_entropy(
                prediction,
                target,
                mask,
                gamma=config.focal_gamma,
                alpha=config.focal_alpha,
                pos_weight=None if head_pos_weights is None else head_pos_weights.get(name),
            )
        elif name == "continuous_target_deltas":
            raw = smooth_l1_loss(prediction, target, mask)
        elif name == "subjectness_roi_agreement_logits":
            if target.shape != prediction.shape:
                raise LossError(f"{name} targets must match logits shape")
            raw = binary_cross_entropy_with_logits(prediction, target, mask)
        else:
            if target.shape != prediction.shape:
                raise LossError(f"{name} targets must match probabilities shape")
            raw = binary_cross_entropy(prediction, target, mask)
        raw_terms[name] = raw
        weighted_terms[name] = raw * float(getattr(config.weights, name))

    ranking_terms: list[Tensor] = []
    contrastive_terms: list[Tensor] = []
    if pair_labels is not None:
        if not isinstance(pair_labels, Mapping):
            raise LossError("pair_labels must be a mapping")
        for pair_name, spec in pair_labels.items():
            if pair_name not in {"good_vs_harmful", "before_after"}:
                raise LossError(f"unknown ranking pair set: {pair_name}")
            first, second, labels, pair_mask, spec_contrastive = _pair_parts(spec, pair_name)
            first, second = _validate_pair_indices(first, second, batch_size, pair_name)
            pair_indices = torch.stack((first, second), dim=1)
            if labels is not None and "good_frame_probability" in outputs:
                ranking_terms.append(
                    pairwise_ranking_loss(
                        outputs["good_frame_probability"],
                        pair_indices,
                        labels,
                        pair_mask,
                        margin=config.ranking_margin,
                    )
                )
            if spec_contrastive is not None and "embedding" in outputs:
                contrastive_terms.append(
                    pairwise_contrastive_loss(
                        outputs["embedding"],
                        pair_indices,
                        spec_contrastive,
                        pair_mask,
                        margin=config.contrastive_margin,
                    )
                )
    if contrastive_pairs is not None:
        if not isinstance(contrastive_pairs, Mapping):
            raise LossError("contrastive_pairs must be a mapping")
        for pair_name, spec in contrastive_pairs.items():
            if pair_name not in {"good_vs_harmful", "before_after"}:
                raise LossError(f"unknown contrastive pair set: {pair_name}")
            first, second, _labels, pair_mask, spec_contrastive = _pair_parts(spec, f"contrastive.{pair_name}")
            if spec_contrastive is None:
                raise LossError(f"contrastive.{pair_name} needs explicit contrastive_labels")
            first, second = _validate_pair_indices(first, second, batch_size, f"contrastive.{pair_name}")
            if "embedding" not in outputs:
                continue
            contrastive_terms.append(
                pairwise_contrastive_loss(
                    outputs["embedding"],
                    torch.stack((first, second), dim=1),
                    spec_contrastive,
                    pair_mask,
                    margin=config.contrastive_margin,
                )
            )
    reference = next(iter(outputs.values()))
    ranking = torch.stack(ranking_terms).mean() if ranking_terms else absent(reference)
    contrastive = torch.stack(contrastive_terms).mean() if contrastive_terms else absent(reference)
    weighted_ranking = ranking * config.weights.ranking
    weighted_contrastive = contrastive * config.weights.contrastive
    total = torch.stack([*weighted_terms.values(), weighted_ranking, weighted_contrastive]).sum()
    return LossResult(total, MappingProxyType(raw_terms), ranking, contrastive)


def multi_task_loss(*args: Any, **kwargs: Any) -> LossResult:
    """Spelling-compatible alias for :func:`compute_multitask_loss`."""

    return compute_multitask_loss(*args, **kwargs)


def multitask_loss(*args: Any, **kwargs: Any) -> LossResult:
    return compute_multitask_loss(*args, **kwargs)


MultiTaskLoss = compute_multitask_loss


__all__ = [
    "CONFIG_VERSION",
    "DIRECT_LOSS_HEADS",
    "HEAD_NAMES",
    "LOSS_TERM_NAMES",
    "LossConfig",
    "LossError",
    "LossResult",
    "LossWeights",
    "MultiTaskLoss",
    "PairLabels",
    "binary_cross_entropy",
    "binary_cross_entropy_with_logits",
    "compute_multitask_loss",
    "cross_entropy",
    "focal_binary_cross_entropy",
    "masked_mean",
    "merge_intent_supervision_mask",
    "multi_task_loss",
    "multitask_loss",
    "pairwise_contrastive_loss",
    "pairwise_ranking_loss",
    "smooth_l1_loss",
]
