"""Typed training-record loader for the SETCompositionNet-v2 trainer (M01).

A *training record* is the training-facing export produced from the frozen
camera label schema by the annotation/export lane (D02b).  This module is the
single consumer boundary for that export:

* it parses a closed, typed JSONL record and validates it fail-closed;
* it builds the six inherited v1 tensors plus the explicit 9-component
  ``intent_features`` vector at the same trust boundary as the pixels;
* it derives exactly one target and one supervision mask per head.

Two rules are non-negotiable:

1. An absent label becomes mask ``0.0`` and never an implicit zero target.  A
   missing issue, an unreviewed action catalog, or an unexpressed delta is
   ``unknown``, not "no change needed".
2. A value that contradicts its own availability fails closed.  A present
   delta with mask ``0``, a present intent-conditioned label with unknown
   intent or no ROI, or a positive and forbidden instance of the same action
   raise instead of being silently repaired.

The module also owns the deterministic family-balanced sampler and the
direction-preserving horizontal-flip augmentation.  A blind horizontal flip
does not preserve left/right labels, so the flip remaps the directional
utility indices, the lateral scalar features, the ROI, and ``delta_x`` and
refuses to run when a directional label has no explicit mirror.
"""

from __future__ import annotations

from collections import Counter
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, replace
import hashlib
import json
import math
import os
from pathlib import Path
from types import MappingProxyType
from typing import Any

import torch
from torch import Tensor

from ..models.set_composition_net_v2 import (
    INTENT_CONDITIONED_HEAD_ORDER,
    SETCompositionNetV2Inputs,
    SETCompositionNetV2Manifest,
    encode_intent,
    intent_supervision_mask,
    validate_intent_features,
)
from .intent_features import preprocess_frame_v2


TRAINING_RECORD_SCHEMA_ID = "camera-training-record-v2"
TRAINING_RECORD_SCHEMA_VERSION = "v2.0.0"
RECORDS_GENERATOR_VERSION = "typed_training_records.v2"

SPLITS = ("train", "validation", "calibration", "locked_test")
TRAINABLE_SPLITS = ("train", "validation", "calibration")

MATRIX_CLASSES = (
    "single_person",
    "two_people",
    "object_or_food",
    "interior",
    "street_or_landscape",
    "difficult_light",
    "already_good_frame",
)

# Explicit, reviewable direction remap for the frozen v2 26-index utility
# catalog.  Every directional id in the catalog must be present here; a
# directional id with no mirror makes the flip fail closed.
UTILITY_DIRECTIONAL_PAIRS = (
    ("shift_frame_left", "shift_frame_right"),
    ("move_subject_left", "move_subject_right"),
    ("move_object_left", "move_object_right"),
)
_UTILITY_MIRROR = {value: other for left, right in UTILITY_DIRECTIONAL_PAIRS for value, other in ((left, right), (right, left))}

# Lateral scalar features are transformed by the flip instead of treated as
# invariant.  ``swap:`` swaps a left/right pair, ``negate:`` flips sign,
# ``mirror_x:`` maps a normalized x coordinate.  A horizontal mirror reverses
# the scene roll, so the signed horizon angle changes sign exactly like a
# lateral direction (see ``angle_degrees_to_unit`` in the frozen v2 manifest).
_LATERAL_SCALAR_TRANSFORMS = {
    "saliency_left_right_balance": ("negate", None),
    "horizon_angle": ("negate", None),
    "subject_edge_pressure_left": ("swap", "subject_edge_pressure_right"),
    "subject_edge_pressure_right": ("swap", "subject_edge_pressure_left"),
    "subject_bbox_x": ("mirror_x", "subject_bbox_width"),
    "mirroring_flag": ("invert", None),
}

_RECORD_KEYS = {
    "schema_id",
    "schema_version",
    "record_id",
    "split",
    "source_family_id",
    "matrix_class",
    "capture_intent",
    "roi_normalized_xywh",
    "pixels",
    "scalar_features",
    "missing_feature_mask",
    "targets",
    "ranking",
}
_TARGET_KEYS = {
    "scene_class",
    "subjectness",
    "issues",
    "utility",
    "good_frame",
    "abstention",
    "risk",
    "target_deltas",
}
_DELTA_NAMES = ("delta_x", "delta_y", "scale_delta", "light_delta", "horizon_delta")


class TrainingRecordError(ValueError):
    """Raised when a typed training record is malformed or self-contradictory."""


def _require_keys(value: object, expected: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise TrainingRecordError(f"{label} must be an object")
    actual = set(value)
    if actual != expected:
        raise TrainingRecordError(
            f"{label} keys drifted; missing={sorted(expected - actual)}, extra={sorted(actual - expected)}"
        )
    return value


def _require_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise TrainingRecordError(f"{label} must be a non-empty string")
    return value


def _require_bool(value: object, label: str) -> bool:
    if type(value) is not bool:
        raise TrainingRecordError(f"{label} must be a boolean")
    return value


def _require_int(value: object, label: str) -> int:
    if type(value) is not int or isinstance(value, bool):
        raise TrainingRecordError(f"{label} must be an integer")
    return value


def _require_finite(value: object, label: str) -> float:
    if type(value) not in (int, float) or isinstance(value, bool) or not math.isfinite(float(value)):
        raise TrainingRecordError(f"{label} must be a finite number")
    return float(value)


def _require_binary(value: object, label: str) -> int:
    number = _require_int(value, label)
    if number not in (0, 1):
        raise TrainingRecordError(f"{label} must be 0 or 1")
    return number


def _file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise TrainingRecordError(f"cannot read training records: {path}") from exc
    return digest.hexdigest()


@dataclass(frozen=True)
class TrainingRecord:
    """One validated typed record with per-head targets and masks."""

    record_id: str
    split: str
    source_family_id: str
    matrix_class: str
    intent_styles: tuple[str, ...]
    intent_known: bool
    roi: tuple[float, float, float, float] | None
    pixels: Tensor  # uint8 HWC RGB
    scalar_features: Tensor | None
    missing_feature_mask: Tensor | None
    targets: Mapping[str, Tensor]
    masks: Mapping[str, Tensor]
    ranking: tuple[tuple[str, int], ...]
    admissible: bool

    def model_inputs(self, contract: SETCompositionNetV2Manifest) -> SETCompositionNetV2Inputs:
        return build_model_inputs(self, contract)


def _parse_pixels(node: object, label: str) -> Tensor:
    node = _require_keys(node, {"width", "height", "values"}, label)
    width = _require_int(node["width"], f"{label}.width")
    height = _require_int(node["height"], f"{label}.height")
    if width <= 0 or height <= 0 or width > 512 or height > 512:
        raise TrainingRecordError(f"{label} dimensions must be within [1, 512]")
    values = node["values"]
    if not isinstance(values, list) or len(values) != width * height * 3:
        raise TrainingRecordError(f"{label}.values must contain width*height*3 RGB bytes")
    if not all(type(value) is int and 0 <= value <= 255 for value in values):
        raise TrainingRecordError(f"{label}.values must be uint8 RGB bytes")
    return torch.tensor(values, dtype=torch.uint8).reshape(height, width, 3)


def _parse_vector(value: object, width: int, label: str) -> Tensor:
    if not isinstance(value, list) or len(value) != width:
        raise TrainingRecordError(f"{label} must be a length-{width} array")
    return torch.tensor([_require_finite(item, f"{label}[{index}]") for index, item in enumerate(value)], dtype=torch.float32)


def _parse_binary_vector(value: object, width: int, label: str) -> Tensor:
    if not isinstance(value, list) or len(value) != width:
        raise TrainingRecordError(f"{label} must be a length-{width} array")
    return torch.tensor([_require_binary(item, f"{label}[{index}]") for index, item in enumerate(value)], dtype=torch.float32)


def _roi_from_node(value: object, label: str) -> tuple[float, float, float, float] | None:
    if value is None:
        return None
    if not isinstance(value, list) or len(value) != 4:
        raise TrainingRecordError(f"{label} must be null or a normalized xywh array")
    x, y, width, height = (_require_finite(item, f"{label}[{index}]") for index, item in enumerate(value))
    if not (0.0 <= x <= 1.0 and 0.0 <= y <= 1.0 and 0.0 < width <= 1.0 and 0.0 < height <= 1.0):
        raise TrainingRecordError(f"{label} must be a positive normalized rectangle")
    if x + width > 1.0 + 1e-9 or y + height > 1.0 + 1e-9:
        raise TrainingRecordError(f"{label} must stay inside the normalized frame")
    return (x, y, width, height)


def _parse_intent(node: object, contract: SETCompositionNetV2Manifest, label: str) -> tuple[tuple[str, ...], Tensor]:
    node = _require_keys(node, {"styles", "known"}, label)
    raw_styles = node["styles"]
    if not isinstance(raw_styles, list) or not all(isinstance(item, str) for item in raw_styles):
        raise TrainingRecordError(f"{label}.styles must be a list of style names")
    styles = tuple(raw_styles)
    known = _require_bool(node["known"], f"{label}.known")
    if known and not styles:
        raise TrainingRecordError(f"{label}.known=true requires an explicit non-empty style set")
    if not known and styles:
        raise TrainingRecordError(f"{label}.known=false cannot carry explicit styles")
    intent = encode_intent(list(styles), contract=contract)
    validate_intent_features(intent, contract)
    return styles, intent


def _targets_from_node(
    node: object,
    *,
    contract: SETCompositionNetV2Manifest,
    admissible: bool,
    intent_name: str,
    label: str,
) -> tuple[dict[str, Tensor], dict[str, Tensor]]:
    node = _require_keys(node, _TARGET_KEYS, label)
    scene_names = tuple(contract.output_head_specs["scene_class_logits"]["ordered_names"])
    issue_names = tuple(contract.output_head_specs["issue_logits"]["ordered_names"])
    utility_names = tuple(contract.output_head_specs["action_utility_logits"]["ordered_names"])
    subjectness_names = tuple(contract.output_head_specs["subjectness_roi_agreement_logits"]["ordered_names"])
    targets: dict[str, Tensor] = {}
    masks: dict[str, Tensor] = {}

    # scene_class_logits: categorical, unlabeled -> mask 0.
    scene_class = node["scene_class"]
    if scene_class is not None:
        name = _require_string(scene_class, f"{label}.scene_class")
        if name not in scene_names:
            raise TrainingRecordError(f"{label}.scene_class is not a frozen scene class: {name!r}")
        targets["scene_class_logits"] = torch.tensor([scene_names.index(name)], dtype=torch.int64)
        masks["scene_class_logits"] = torch.ones(1, dtype=torch.float32)
    else:
        targets["scene_class_logits"] = torch.zeros(1, dtype=torch.int64)
        masks["scene_class_logits"] = torch.zeros(1, dtype=torch.float32)

    # subjectness_roi_agreement_logits: per-component availability.
    subjectness_node = _require_keys(node["subjectness"], set(subjectness_names), f"{label}.subjectness")
    subjectness_values: list[float] = []
    subjectness_mask: list[float] = []
    for name in subjectness_names:
        value = subjectness_node[name]
        if value is None:
            subjectness_values.append(0.0)
            subjectness_mask.append(0.0)
        else:
            subjectness_values.append(float(_require_binary(value, f"{label}.subjectness.{name}")))
            subjectness_mask.append(1.0)
    targets["subjectness_roi_agreement_logits"] = torch.tensor(subjectness_values, dtype=torch.float32)
    masks["subjectness_roi_agreement_logits"] = torch.tensor(subjectness_mask, dtype=torch.float32)

    # issue_logits: an unreviewed catalog is missing supervision, not a
    # negative.  A reviewed catalog labels every one of the eight issues.
    issues_node = _require_keys(node["issues"], {"reviewed", "present"}, f"{label}.issues")
    reviewed = _require_bool(issues_node["reviewed"], f"{label}.issues.reviewed")
    present = issues_node["present"]
    if not isinstance(present, list) or not all(isinstance(item, str) for item in present):
        raise TrainingRecordError(f"{label}.issues.present must be a list of issue names")
    unknown_issues = sorted(set(present).difference(issue_names))
    if unknown_issues:
        raise TrainingRecordError(f"{label}.issues.present has unknown neural issues: {unknown_issues}")
    if not reviewed and present:
        raise TrainingRecordError(
            f"{label}.issues.present carries issues while reviewed=false; unlabeled issues must stay unknown"
        )
    issue_values = [1.0 if name in set(present) else 0.0 for name in issue_names]
    targets["issue_logits"] = torch.tensor(issue_values, dtype=torch.float32)
    masks["issue_logits"] = torch.full((len(issue_names),), 1.0 if reviewed else 0.0, dtype=torch.float32)

    # action_utility_logits: intent-conditioned.  Admissible records label
    # acceptable actions 1.0 and forbidden actions 0.0; every other approved
    # action stays unknown (mask 0).  Forbidden is its own explicit meaning,
    # not "no label = bad action".
    utility_node = _require_keys(node["utility"], {"reviewed", "acceptable", "forbidden"}, f"{label}.utility")
    utility_reviewed = _require_bool(utility_node["reviewed"], f"{label}.utility.reviewed")
    acceptable = utility_node["acceptable"]
    forbidden = utility_node["forbidden"]
    for field, values in (("acceptable", acceptable), ("forbidden", forbidden)):
        if not isinstance(values, list) or not all(isinstance(item, str) for item in values):
            raise TrainingRecordError(f"{label}.utility.{field} must be a list of action names")
    unknown_actions = sorted(set(acceptable + forbidden).difference(utility_names))
    if unknown_actions:
        raise TrainingRecordError(f"{label}.utility references unknown actions: {unknown_actions}")
    overlap = sorted(set(acceptable).intersection(forbidden))
    if overlap:
        raise TrainingRecordError(f"{label}.utility marks actions both acceptable and forbidden: {overlap}")
    has_utility_labels = bool(acceptable or forbidden)
    if has_utility_labels and not utility_reviewed:
        raise TrainingRecordError(
            f"{label}.utility carries actions while reviewed=false; an unreviewed catalog must stay unknown"
        )
    if has_utility_labels and not admissible:
        raise TrainingRecordError(
            f"{label}.utility carries labels while {intent_name}; intent-conditioned supervision is not admissible"
        )
    utility_values = [0.0] * len(utility_names)
    utility_mask = [0.0] * len(utility_names)
    indexes = {name: index for index, name in enumerate(utility_names)}
    for name in acceptable:
        utility_values[indexes[name]] = 1.0
        utility_mask[indexes[name]] = 1.0
    for name in forbidden:
        utility_values[indexes[name]] = 0.0
        utility_mask[indexes[name]] = 1.0
    if not admissible:
        utility_mask = [0.0] * len(utility_names)
    targets["action_utility_logits"] = torch.tensor(utility_values, dtype=torch.float32)
    masks["action_utility_logits"] = torch.tensor(utility_mask, dtype=torch.float32)

    # Intent-conditioned scalar heads: good/risk.  Abstention is
    # intent-independent in the frozen v2 partition.
    for head, key in (("good_frame_probability", "good_frame"), ("risk_probability", "risk")):
        value = node[key]
        if value is None:
            targets[head] = torch.zeros(1, dtype=torch.float32)
            masks[head] = torch.zeros(1, dtype=torch.float32)
            continue
        if not admissible:
            raise TrainingRecordError(
                f"{label}.{key} carries a label while {intent_name}; intent-conditioned supervision is not admissible"
            )
        targets[head] = torch.tensor([float(_require_binary(value, f"{label}.{key}"))], dtype=torch.float32)
        masks[head] = torch.ones(1, dtype=torch.float32)

    abstention = node["abstention"]
    if abstention is None:
        targets["abstention_probability"] = torch.zeros(1, dtype=torch.float32)
        masks["abstention_probability"] = torch.zeros(1, dtype=torch.float32)
    else:
        targets["abstention_probability"] = torch.tensor([float(_require_binary(abstention, f"{label}.abstention"))], dtype=torch.float32)
        masks["abstention_probability"] = torch.ones(1, dtype=torch.float32)

    # continuous_target_deltas: per-component availability.  An unexpressed
    # delta is masked out and never regressed toward 0.0.
    deltas_node = _require_keys(node["target_deltas"], set(_DELTA_NAMES), f"{label}.target_deltas")
    delta_values: list[float] = []
    delta_mask: list[float] = []
    for name in _DELTA_NAMES:
        value = deltas_node[name]
        if value is None:
            delta_values.append(0.0)
            delta_mask.append(0.0)
            continue
        if not admissible:
            raise TrainingRecordError(
                f"{label}.target_deltas.{name} carries a label while {intent_name}; "
                "intent-conditioned supervision is not admissible"
            )
        delta = _require_finite(value, f"{label}.target_deltas.{name}")
        if not -1.0 <= delta <= 1.0:
            raise TrainingRecordError(f"{label}.target_deltas.{name} must be within [-1, 1]")
        delta_values.append(delta)
        delta_mask.append(1.0)
    targets["continuous_target_deltas"] = torch.tensor(delta_values, dtype=torch.float32)
    masks["continuous_target_deltas"] = torch.tensor(delta_mask, dtype=torch.float32)

    missing_heads = set(contract.output_head_names).difference(targets).difference({contract.embedding_name})
    if missing_heads:
        raise TrainingRecordError(f"{label} did not produce targets for {sorted(missing_heads)}")
    return targets, masks


def parse_record(raw: object, contract: SETCompositionNetV2Manifest | None = None) -> TrainingRecord:
    """Validate one typed record and derive per-head targets and masks."""

    contract = contract or SETCompositionNetV2Manifest.load()
    node = _require_keys(raw, _RECORD_KEYS, "training record")
    if node["schema_id"] != TRAINING_RECORD_SCHEMA_ID:
        raise TrainingRecordError(f"training record schema_id must be {TRAINING_RECORD_SCHEMA_ID!r}")
    if node["schema_version"] != TRAINING_RECORD_SCHEMA_VERSION:
        raise TrainingRecordError(f"training record schema_version must be {TRAINING_RECORD_SCHEMA_VERSION!r}")
    record_id = _require_string(node["record_id"], "record_id")
    split = _require_string(node["split"], "split")
    if split not in SPLITS:
        raise TrainingRecordError(f"split must be one of {SPLITS}")
    matrix_class = _require_string(node["matrix_class"], "matrix_class")
    if matrix_class not in MATRIX_CLASSES:
        raise TrainingRecordError(f"matrix_class must be one of {MATRIX_CLASSES}")
    source_family_id = _require_string(node["source_family_id"], "source_family_id")

    styles, intent = _parse_intent(node["capture_intent"], contract, "capture_intent")
    intent_known = bool(styles)
    roi = _roi_from_node(node["roi_normalized_xywh"], "roi_normalized_xywh")
    roi_present = roi is not None
    admissible = intent_known and roi_present
    intent_name = "intent is unknown" if not intent_known else "no ROI is present"

    pixels = _parse_pixels(node["pixels"], "pixels")
    scalars = None if node["scalar_features"] is None else _parse_vector(
        node["scalar_features"], contract.scalar_feature_count, "scalar_features"
    )
    missing = None if node["missing_feature_mask"] is None else _parse_binary_vector(
        node["missing_feature_mask"], contract.scalar_feature_count, "missing_feature_mask"
    )
    if missing is not None and scalars is None:
        raise TrainingRecordError("missing_feature_mask is present without scalar_features")

    targets, masks = _targets_from_node(
        node["targets"], contract=contract, admissible=admissible, intent_name=intent_name, label="targets"
    )

    # The frozen contract mask is authoritative for the four intent-conditioned
    # heads.  If a head mask is 1 while the contract mask is 0, the record is
    # self-contradictory and fails closed here.
    contract_mask = intent_supervision_mask(intent, 1.0 if admissible else 0.0, contract)
    for index, head in enumerate(INTENT_CONDITIONED_HEAD_ORDER):
        allowed = float(contract_mask[index])
        if allowed == 0.0 and torch.any(masks[head] != 0.0):
            raise TrainingRecordError(
                f"head {head} has supervision while the frozen intent mask forbids it"
            )

    ranking_node = node["ranking"]
    if not isinstance(ranking_node, list):
        raise TrainingRecordError("ranking must be a list")
    ranking: list[tuple[str, int]] = []
    for index, entry in enumerate(ranking_node):
        entry = _require_keys(entry, {"other_record_id", "preference"}, f"ranking[{index}]")
        preference = _require_binary(entry["preference"], f"ranking[{index}].preference")
        ranking.append((_require_string(entry["other_record_id"], f"ranking[{index}].other_record_id"), preference))

    return TrainingRecord(
        record_id=record_id,
        split=split,
        source_family_id=source_family_id,
        matrix_class=matrix_class,
        intent_styles=styles,
        intent_known=intent_known,
        roi=roi,
        pixels=pixels,
        scalar_features=scalars,
        missing_feature_mask=missing,
        targets=targets,
        masks=masks,
        ranking=tuple(ranking),
        admissible=admissible,
    )


def load_records(path: str | os.PathLike[str], expected_sha256: str | None = None) -> list[TrainingRecord]:
    """Load a typed JSONL bundle, verifying its content hash first."""

    records_path = Path(path)
    if expected_sha256 is not None:
        actual = _file_sha256(records_path)
        if actual != expected_sha256:
            raise TrainingRecordError(
                f"training records hash mismatch for {records_path}: expected {expected_sha256}, got {actual}"
            )
    try:
        text = records_path.read_text(encoding="utf-8")
    except OSError as exc:
        raise TrainingRecordError(f"cannot read training records: {records_path}") from exc
    records: list[TrainingRecord] = []
    for line_number, line in enumerate(text.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            raw = json.loads(line)
        except json.JSONDecodeError as exc:
            raise TrainingRecordError(f"training record line {line_number} is not JSON") from exc
        try:
            records.append(parse_record(raw))
        except TrainingRecordError as exc:
            raise TrainingRecordError(f"training record line {line_number}: {exc}") from exc
    if not records:
        raise TrainingRecordError("training records bundle is empty")
    ids = [record.record_id for record in records]
    if len(set(ids)) != len(ids):
        raise TrainingRecordError("training record ids must be unique")
    return records


def build_model_inputs(record: TrainingRecord, contract: SETCompositionNetV2Manifest) -> SETCompositionNetV2Inputs:
    """Preprocess one record into the frozen v2 input tensors."""

    return preprocess_frame_v2(
        record.pixels,
        width=int(record.pixels.shape[1]),
        height=int(record.pixels.shape[0]),
        roi=list(record.roi) if record.roi is not None else None,
        normalized_features=record.scalar_features,
        missing_feature_mask=record.missing_feature_mask,
        channel_order="RGB",
        intent_styles=list(record.intent_styles),
    )


def stack_inputs(records: Sequence[TrainingRecord], contract: SETCompositionNetV2Manifest) -> SETCompositionNetV2Inputs:
    built = [build_model_inputs(record, contract) for record in records]
    return SETCompositionNetV2Inputs(
        torch.stack([item.full_frame_rgb for item in built]),
        torch.stack([item.subject_crop_rgb for item in built]),
        torch.stack([item.roi_normalized_xywh for item in built]),
        torch.stack([item.roi_mask for item in built]),
        torch.stack([item.scalar_features for item in built]),
        torch.stack([item.missing_feature_mask for item in built]),
        torch.stack([item.intent_features for item in built]),
    )


def stack_targets(records: Sequence[TrainingRecord]) -> dict[str, Tensor]:
    return {name: torch.stack([record.targets[name] for record in records]) for name in records[0].targets}


def stack_masks(records: Sequence[TrainingRecord]) -> dict[str, Tensor]:
    return {name: torch.stack([record.masks[name] for record in records]) for name in records[0].masks}


def intent_head_mask(records: Sequence[TrainingRecord], contract: SETCompositionNetV2Manifest) -> Tensor:
    """Frozen `[B, 4]` mask for the intent-conditioned heads."""

    rows = [
        intent_supervision_mask(
            encode_intent(list(record.intent_styles), contract=contract),
            1.0 if record.roi is not None else 0.0,
            contract,
        )
        for record in records
    ]
    return torch.stack(rows)


def merge_intent_mask(masks: Mapping[str, Tensor], intent_mask: Tensor) -> dict[str, Tensor]:
    """Multiply the frozen intent mask into each intent-conditioned head mask."""

    merged = dict(masks)
    for index, head in enumerate(INTENT_CONDITIONED_HEAD_ORDER):
        column = intent_mask[:, index].reshape(-1, *([1] * (merged[head].ndim - 1)))
        merged[head] = merged[head] * column
    return merged


def class_pos_weights(
    records: Sequence[TrainingRecord],
    head: str,
    *,
    maximum: float = 20.0,
) -> Tensor:
    """Inverse-frequency positive weights computed on the train split only."""

    if head not in {"issue_logits", "action_utility_logits"}:
        raise TrainingRecordError(f"class weights are not defined for head {head!r}")
    stacked = stack_targets(records)[head]
    available = stack_masks(records)[head]
    positives = (stacked * available).sum(dim=0)
    counts = available.sum(dim=0)
    negatives = counts - positives
    weights = torch.where(
        (positives > 0) & (negatives > 0),
        negatives / positives.clamp_min(1.0),
        torch.ones_like(positives),
    ).clamp(1.0, maximum)
    return weights


def eligible_ranking_pairs(records: Sequence[TrainingRecord]) -> list[tuple[int, int, int]]:
    """Return within-run pairs that are admissible and preference-labelled.

    A pair is eligible only when both records are on the same split, both are
    admissible (explicit intent and ROI), and the preference is 0/1.  Anything
    else is dropped rather than reinterpreted as a ranking label.
    """

    index = {record.record_id: position for position, record in enumerate(records)}
    pairs: list[tuple[int, int, int]] = []
    for position, record in enumerate(records):
        for other_id, preference in record.ranking:
            other = index.get(other_id)
            if other is None or other == position:
                continue
            if records[other].split != record.split:
                continue
            if not (record.admissible and records[other].admissible):
                continue
            pairs.append((position, other, preference))
    return pairs


class FamilyBalancedSampler:
    """Deterministic sampler balancing matrix classes and source families.

    The sampling weights are inverse class frequency, further damped by
    inverse source-family frequency so a single shoot cannot dominate an epoch.
    ``state_dict`` carries the generator state and epoch counter so an
    interrupted run resumes the exact same sample stream.
    """

    def __init__(
        self,
        records: Sequence[TrainingRecord],
        *,
        seed: int,
        balance_source_families: bool = True,
    ):
        if not records:
            raise TrainingRecordError("sampler requires at least one record")
        class_counts = Counter(record.matrix_class for record in records)
        family_counts = Counter(record.source_family_id for record in records)
        raw = []
        for record in records:
            weight = 1.0 / class_counts[record.matrix_class]
            if balance_source_families:
                weight /= family_counts[record.source_family_id]
            raw.append(weight)
        total = sum(raw)
        self._weights = torch.tensor([value / total for value in raw], dtype=torch.float64)
        self._generator = torch.Generator(device="cpu")
        self._generator.manual_seed(seed)
        self.epoch = 0

    @property
    def weights(self) -> Tensor:
        return self._weights.clone()

    def epoch_indices(self) -> list[int]:
        indices = torch.multinomial(
            self._weights,
            num_samples=self._weights.shape[0],
            replacement=True,
            generator=self._generator,
        ).tolist()
        self.epoch += 1
        return indices

    def state_dict(self) -> dict[str, object]:
        return {
            "epoch": self.epoch,
            "generator_state": self._generator.get_state().clone(),
            "weights": self._weights.clone(),
        }

    def load_state_dict(self, state: Mapping[str, object]) -> None:
        self.epoch = _require_int(state["epoch"], "sampler epoch")
        self._generator.set_state(state["generator_state"])  # type: ignore[arg-type]
        stored = state["weights"]
        if not isinstance(stored, Tensor) or stored.shape != self._weights.shape:
            raise TrainingRecordError("sampler weights do not match the loaded record set")
        if not torch.allclose(stored, self._weights, atol=1e-12):
            raise TrainingRecordError("sampler weights changed across resume; data or seed drifted")


def _flip_pixels(pixels: Tensor) -> Tensor:
    return torch.flip(pixels, dims=(1,))


def _flip_roi(roi: tuple[float, float, float, float]) -> tuple[float, float, float, float]:
    x, y, width, height = roi
    mirrored_x = 1.0 - x - width
    # IEEE-754 subtraction can lose a low-order bit.  Reject only a real
    # misalignment (a ROI that is not the horizontal mirror of itself) rather
    # than a one-ULP artifact; clip the mirrored origin into the frame.
    if abs(1.0 - mirrored_x - width - x) > 1e-9:
        raise TrainingRecordError("requires_reannotation: ROI is not a horizontal flip involution")
    mirrored_x = min(max(mirrored_x, 0.0), 1.0 - width)
    return (mirrored_x, y, width, height)


def _flip_scalars(record: TrainingRecord, contract: SETCompositionNetV2Manifest) -> Tensor | None:
    if record.scalar_features is None:
        return None
    names = list(contract.raw["inputs"]["scalar_features"]["ordered_names"])
    values = record.scalar_features.clone()
    indexes = {name: index for index, name in enumerate(names)}
    missing = record.missing_feature_mask

    def is_missing(name: str) -> bool:
        if missing is None:
            return False
        return float(missing[indexes[name]]) != 0.0

    for name, (kind, partner) in _LATERAL_SCALAR_TRANSFORMS.items():
        if name not in indexes:
            raise TrainingRecordError(f"lateral scalar feature {name!r} is absent from the frozen contract")
        index = indexes[name]
        if is_missing(name):
            # An absent feature keeps its contract fill value (0.0) and its
            # missing mask; the flip must not revive it as a present value.
            continue
        if kind == "negate":
            values[index] = -values[index]
        elif kind == "invert":
            values[index] = 1.0 - values[index]
        elif kind == "mirror_x":
            if is_missing(partner):
                continue
            width_index = indexes[partner]
            values[index] = 1.0 - values[index] - values[width_index]
        elif kind == "swap":
            partner_index = indexes[partner]
            if is_missing(partner):
                continue
            if name < partner:
                values[index], values[partner_index] = values[partner_index].clone(), values[index].clone()
        else:  # pragma: no cover - table is closed above.
            raise TrainingRecordError(f"unsupported lateral transform {kind!r}")
    return values


def _flip_utility_targets(values: Tensor, mask: Tensor, contract: SETCompositionNetV2Manifest) -> tuple[Tensor, Tensor]:
    names = list(contract.output_head_specs["action_utility_logits"]["ordered_names"])
    indexes = {name: index for index, name in enumerate(names)}
    flipped_values = values.clone()
    flipped_mask = mask.clone()
    for left, right in UTILITY_DIRECTIONAL_PAIRS:
        left_index, right_index = indexes[left], indexes[right]
        flipped_values[left_index], flipped_values[right_index] = values[right_index].clone(), values[left_index].clone()
        flipped_mask[left_index], flipped_mask[right_index] = mask[right_index].clone(), mask[left_index].clone()
    # A directional id with an unknown mirror must never be flipped as if it
    # were direction-invariant.
    directional = set(_UTILITY_MIRROR)
    for name in names:
        if ("left" in name or "right" in name) and name not in directional:
            raise TrainingRecordError(f"directional utility id {name!r} has no explicit mirror")
    return flipped_values, flipped_mask


def apply_horizontal_flip(record: TrainingRecord, contract: SETCompositionNetV2Manifest | None = None) -> TrainingRecord:
    """Flip pixels, ROI, directions and lateral labels together."""

    contract = contract or SETCompositionNetV2Manifest.load()
    targets = dict(record.targets)
    masks = dict(record.masks)
    utility_values, utility_mask = _flip_utility_targets(
        targets["action_utility_logits"], masks["action_utility_logits"], contract
    )
    targets["action_utility_logits"] = utility_values
    masks["action_utility_logits"] = utility_mask
    # Sign-flipping correction axes under the mirror: ``delta_x`` is a lateral
    # translation and ``horizon_delta`` is the signed roll correction
    # (derivative +theta maps to -theta/180 in the frozen delta semantics).
    # Vertical scale and light corrections are mirror-invariant.
    delta_names = list(contract.output_head_specs["continuous_target_deltas"]["ordered_names"])
    flipped_deltas = targets["continuous_target_deltas"].clone()
    for axis in ("delta_x", "horizon_delta"):
        if axis not in delta_names:
            raise TrainingRecordError(f"signed delta axis {axis!r} is absent from the frozen contract")
        index = delta_names.index(axis)
        flipped_deltas[index] = -flipped_deltas[index]
    targets["continuous_target_deltas"] = flipped_deltas
    return replace(
        record,
        roi=_flip_roi(record.roi) if record.roi is not None else None,
        pixels=_flip_pixels(record.pixels),
        scalar_features=_flip_scalars(record, contract),
        targets=MappingProxyType(targets),
        masks=MappingProxyType(masks),
    )


__all__ = [
    "FamilyBalancedSampler",
    "MATRIX_CLASSES",
    "RECORDS_GENERATOR_VERSION",
    "SPLITS",
    "TRAINABLE_SPLITS",
    "TRAINING_RECORD_SCHEMA_ID",
    "TRAINING_RECORD_SCHEMA_VERSION",
    "TrainingRecord",
    "TrainingRecordError",
    "UTILITY_DIRECTIONAL_PAIRS",
    "apply_horizontal_flip",
    "build_model_inputs",
    "class_pos_weights",
    "eligible_ranking_pairs",
    "intent_head_mask",
    "load_records",
    "merge_intent_mask",
    "parse_record",
    "stack_inputs",
    "stack_masks",
    "stack_targets",
]
