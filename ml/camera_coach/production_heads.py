"""Production-heads trainer extension for the ML-002 heads contract (ML-003).

This module is the trainer/config owner for the minimal production head set of
``camera_production_heads_v1.md`` (authority ``ML-002``): the six tensor heads

* ``good_frame_probability``      [1]   masked_bce (single logit)
* ``issue_logits``                [15]  masked_bce_with_logits per head
* ``action_utility_logits``       [26]  masked_bce_with_logits (mapped actions)
* ``continuous_target_deltas``    [5]   masked_huber
* ``risk_probability``            [1]   masked_bce
* ``abstention_probability``      [1]   masked_bce

plus the non-tensor ``calibration_artifact`` (owned by CAM-003/ML-007; it is
deliberately absent from the tensor head set).

It owns three things and nothing more:

1. **Spec** — :class:`ProductionHeadsSpec` reads the *pinned* contracts
   (label schema, capability mapping, production-heads document) read-only and
   freezes the head layout: 15 DATA-001 issue ids, the 26 DATA-002
   ``disposition=mapped`` action ids (contract order), the 5 magnitude axes,
   and the width of every tensor head. Unsupported actions and
   ``keep_current_setup`` are structurally absent from the head.
2. **Masked supervision and losses** — release-label-shaped records become
   per-head ``(targets, masks)`` where the mask is *label presence*. A missing
   label is a zero mask, never a zero target; ``not_observed`` is uncertainty
   (mask 0), an explicit ``absent`` is a negative (mask 1). The masked losses
   reuse the existing :mod:`ml.camera_coach.losses` primitives (their
   ``masked_mean`` reduction keeps an all-masked head a differentiable zero).
3. **Research-baseline loading** — :func:`load_research_baseline` loads the old
   focused silver Stage-2 checkpoint (``train_silver_actions.py``,
   ``camera-silver-actions-stage2-checkpoint-v1``) *only* with an explicit
   ``research_only=True`` argument. It verifies the payload's own
   ``research_only/human_gold/release_admissible`` flags and the frozen v1
   research layout (issue width 8, old action width 26) and returns metadata
   that can never be presented as a production claim. The old checkpoint is
   NOT loadable into the production head layout — the width mismatch is the
   compatibility boundary, reported as an error instead of being silently
   partially loaded.

Out of scope and unchanged: the frozen v1/v2 model manifests and their parity
artifacts, the contracts and validators under ``ml/camera_coach/contracts/``,
Core ML export/admission (ML-012+), calibration fitting (ML-007), and any
actual training run. No quality and no release claim is made here.
"""

from __future__ import annotations

from collections import OrderedDict
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
import hashlib
import json
import math
import pickle
from pathlib import Path
from types import MappingProxyType
import re

import torch
from torch import Tensor, nn

from .losses import binary_cross_entropy_with_logits, smooth_l1_loss


_CONTRACTS_DIR = Path(__file__).resolve().parent / "contracts"
PRODUCTION_HEADS_DOC_PATH = _CONTRACTS_DIR / "camera_production_heads_v1.md"
LABEL_SCHEMA_PATH = _CONTRACTS_DIR / "camera_release_label_v1.schema.json"
CAPABILITY_MAPPING_PATH = _CONTRACTS_DIR / "camera_release_capability_mapping_v1.json"
V1_MANIFEST_PATH = _CONTRACTS_DIR / "set_composition_net_v1.json"

_BEGIN_MARKER = "<!-- camera-production-heads-v1:machine-readable-begin -->"
_END_MARKER = "<!-- camera-production-heads-v1:machine-readable-end -->"

CALIBRATION_HEAD_ID = "calibration_artifact"

#: Frozen tensor-head order of the production trainer. ``calibration_artifact``
#: is intentionally absent: it is not a gradient head.
PRODUCTION_TENSOR_HEAD_ORDER: tuple[str, ...] = (
    "good_frame_probability",
    "issue_logits",
    "action_utility_logits",
    "continuous_target_deltas",
    "risk_probability",
    "abstention_probability",
)
#: Heads whose target is a single calibrated probability (contract H1/H5/H6).
SINGLE_LOGIT_HEADS: tuple[str, ...] = (
    "good_frame_probability",
    "risk_probability",
    "abstention_probability",
)
EXPECTED_PRODUCTION_HEAD_IDS = frozenset(PRODUCTION_TENSOR_HEAD_ORDER) | {CALIBRATION_HEAD_ID}

VERDICT_POSITIVE = "good"
VERDICT_NEGATIVES = ("needs_fix", "mixed")
ISSUE_STATUS_PRESENT = "present"
ISSUE_STATUS_ABSENT = "absent"
ISSUE_STATUS_NOT_OBSERVED = "not_observed"
OBSERVATION_OBSERVED = "observed"
OBSERVATION_NOT_OBSERVED = "not_observed"
ABSTENTION_ABSTAIN = "abstain"
ABSTENTION_NONE = "none"

_PRODUCTION_HEADS_V1_DOCUMENT_ID = "camera-production-heads-v1"
_LABEL_SCHEMA_ID = "https://set-os.local/ml/camera_coach/contracts/camera-release-label-v1.schema.json"
_RESEARCH_CHECKPOINT_SCHEMA_ID = "camera-silver-actions-stage2-checkpoint-v1"
#: The heads the old focused silver trainer actually optimized.
RESEARCH_TRAINED_HEADS: tuple[str, ...] = (
    "issue_logits",
    "action_utility_logits",
    "continuous_target_deltas",
)
_HEAD_WIDTH_KEY_RE = re.compile(r"^heads\.([a-z_]+)\.(?:(?:.+)\.)?weight$")


class ProductionHeadsError(ValueError):
    """Raised when the spec, labels, targets, masks, or outputs are malformed."""


class ResearchBaselineError(ValueError):
    """Raised when a research-only checkpoint is misused or malformed."""


def _read_json(path: Path, label: str) -> object:
    try:
        with path.open(encoding="utf-8") as stream:
            return json.load(stream)
    except (OSError, json.JSONDecodeError) as exc:
        raise ProductionHeadsError(f"cannot read {label}: {path}") from exc


def _load_production_heads_block() -> dict:
    """Parse the machine-readable fence of the pinned contract document."""

    try:
        text = PRODUCTION_HEADS_DOC_PATH.read_text(encoding="utf-8")
    except OSError as exc:
        raise ProductionHeadsError(f"cannot read the production-heads contract: {PRODUCTION_HEADS_DOC_PATH}") from exc
    if _BEGIN_MARKER not in text or _END_MARKER not in text:
        raise ProductionHeadsError("production-heads contract markers are missing")
    begin = text.index(_BEGIN_MARKER) + len(_BEGIN_MARKER)
    end = text.index(_END_MARKER)
    block = text[begin:end]
    fence = re.search(r"```json\s*(\{.*?\})\s*```", block, re.DOTALL)
    if fence is None:
        raise ProductionHeadsError("production-heads contract has no machine-readable JSON fence")
    try:
        parsed = json.loads(fence.group(1))
    except json.JSONDecodeError as exc:
        raise ProductionHeadsError(f"production-heads machine-readable block is not valid JSON: {exc}") from exc
    if not isinstance(parsed, dict):
        raise ProductionHeadsError("production-heads machine-readable block must be an object")
    return parsed


@dataclass(frozen=True)
class ProductionHeadsSpec:
    """Frozen production head layout derived from the pinned ML-002 contracts."""

    contract_id: str
    contract_version: str
    issue_ids: tuple[str, ...]
    action_ids: tuple[str, ...]
    excluded_action_ids: tuple[str, ...]
    delta_axes: tuple[str, ...]
    head_widths: Mapping[str, int]
    untrained_in_research_baseline: tuple[str, ...]

    @classmethod
    def load(cls) -> "ProductionHeadsSpec":
        schema = _read_json(LABEL_SCHEMA_PATH, "release label schema")
        mapping = _read_json(CAPABILITY_MAPPING_PATH, "capability mapping")
        v1_manifest = _read_json(V1_MANIFEST_PATH, "v1 model manifest")
        block = _load_production_heads_block()
        if not isinstance(schema, dict) or schema.get("$id") != _LABEL_SCHEMA_ID:
            raise ProductionHeadsError("release label schema identity is unsupported")
        if not isinstance(mapping, dict) or mapping.get("schema_id") != "camera-release-capability-mapping-v1":
            raise ProductionHeadsError("capability mapping identity is unsupported")
        if block.get("contract_id") != _PRODUCTION_HEADS_V1_DOCUMENT_ID:
            raise ProductionHeadsError("production-heads contract id drifted")

        heads = block.get("heads")
        if not isinstance(heads, list):
            raise ProductionHeadsError("production-heads contract heads must be a list")
        block_head_ids = {head.get("head_id") for head in heads if isinstance(head, dict)}
        if block_head_ids != set(EXPECTED_PRODUCTION_HEAD_IDS):
            raise ProductionHeadsError(
                f"production-heads contract head set drifted: {sorted(block_head_ids)}"
            )

        defs = schema.get("$defs")
        if not isinstance(defs, dict):
            raise ProductionHeadsError("release label schema has no $defs")
        issue_defs = defs.get("issueID")
        issue_enum = issue_defs.get("enum") if isinstance(issue_defs, dict) else None
        if not isinstance(issue_enum, list) or len(issue_enum) != 15 or len(set(issue_enum)) != 15:
            raise ProductionHeadsError("label schema must declare exactly 15 unique issue ids")
        issue_ids = tuple(str(issue_id) for issue_id in issue_enum)
        block_issue_head = next(
            (head for head in heads if isinstance(head, dict) and head.get("head_id") == "issue_logits"),
            None,
        )
        covered = (block_issue_head or {}).get("covered_issue_ids")
        if covered != list(issue_ids):
            raise ProductionHeadsError("contract issue coverage disagrees with the label schema order")

        dispositions = mapping.get("action_dispositions")
        if not isinstance(dispositions, dict) or not dispositions:
            raise ProductionHeadsError("capability mapping has no action dispositions")
        mapped_ids = [
            action_id
            for action_id, record in dispositions.items()
            if isinstance(record, dict) and record.get("status") == "mapped"
        ]
        block_action_head = next(
            (head for head in heads if isinstance(head, dict) and head.get("head_id") == "action_utility_logits"),
            None,
        )
        proposed = (block_action_head or {}).get("proposed_action_ids")
        excluded_documented = (block_action_head or {}).get("excluded_action_ids")
        if not isinstance(proposed, list) or len(proposed) != 26:
            raise ProductionHeadsError("contract must propose exactly 26 mapped actions")
        if set(proposed) != set(mapped_ids):
            raise ProductionHeadsError("contract proposed actions disagree with the DATA-002 mapped set")
        if not isinstance(excluded_documented, list):
            raise ProductionHeadsError("contract must document excluded actions")
        excluded_ids = tuple(str(action_id) for action_id in excluded_documented)
        action_ids = tuple(str(action_id) for action_id in proposed)
        if set(action_ids) & set(excluded_ids):
            raise ProductionHeadsError("an action cannot be both proposed and excluded")

        magnitude_defs = defs.get("magnitude")
        axis_enum = (
            magnitude_defs.get("properties", {}).get("axis", {}).get("enum")
            if isinstance(magnitude_defs, dict)
            else None
        )
        if not isinstance(axis_enum, list):
            raise ProductionHeadsError("label schema magnitude axis enum is missing")
        delta_axes = tuple(axis for axis in axis_enum if isinstance(axis, str))
        v1_heads = v1_manifest.get("outputs", {}).get("heads") if isinstance(v1_manifest, dict) else None
        v1_delta_names = next(
            (
                head.get("ordered_names")
                for head in (v1_heads or [])
                if isinstance(head, dict) and head.get("name") == "continuous_target_deltas"
            ),
            None,
        )
        if tuple(v1_delta_names or ()) != delta_axes or len(delta_axes) != 5:
            raise ProductionHeadsError("delta axes disagree with the frozen v1 manifest ordering")

        widths = {
            "good_frame_probability": 1,
            "issue_logits": len(issue_ids),
            "action_utility_logits": len(action_ids),
            "continuous_target_deltas": len(delta_axes),
            "risk_probability": 1,
            "abstention_probability": 1,
        }
        untrained_in_research = tuple(
            head for head in SINGLE_LOGIT_HEADS  # GAP-1: good/risk/abstention were never trained.
        )
        return cls(
            contract_id=str(block["contract_id"]),
            contract_version=str(block.get("contract_version", "")),
            issue_ids=issue_ids,
            action_ids=action_ids,
            excluded_action_ids=excluded_ids,
            delta_axes=delta_axes,
            head_widths=MappingProxyType(widths),
            untrained_in_research_baseline=untrained_in_research,
        )

    @property
    def tensor_head_order(self) -> tuple[str, ...]:
        return PRODUCTION_TENSOR_HEAD_ORDER

    def width(self, head: str) -> int:
        try:
            return self.head_widths[head]
        except KeyError as exc:
            raise ProductionHeadsError(f"unknown production head: {head}") from exc

    def require_action_supported(self, action_id: object) -> str:
        """Fail closed unless the action is a proposed (mapped) production action."""

        if not isinstance(action_id, str):
            raise ProductionHeadsError("action_id must be a string")
        if action_id in self.excluded_action_ids:
            raise ProductionHeadsError(
                f"action {action_id!r} is not a production head action "
                "(unsupported or app-only); it is never supervised or proposed"
            )
        if action_id not in self.action_ids:
            raise ProductionHeadsError(f"unknown action id: {action_id!r}")
        return action_id


def _finite(value: object, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ProductionHeadsError(f"{label} must be a finite number")
    result = float(value)
    if not math.isfinite(result):
        raise ProductionHeadsError(f"{label} must be a finite number")
    return result


def _unit_interval(value: object, label: str) -> float:
    result = _finite(value, label)
    if not 0.0 <= result <= 1.0:
        raise ProductionHeadsError(f"{label} must be in [0, 1]")
    return result


@dataclass(frozen=True)
class ProductionLabelSupervision:
    """Per-example ``(targets, masks)`` for the six production tensor heads.

    ``masks`` is label presence: 1.0 where an adjudicated label exists, 0.0
    where it does not. A target slot under a zero mask is an ignored placeholder
    (always 0.0 by construction), never a zero-class label.
    """

    targets: Mapping[str, Tensor]
    masks: Mapping[str, Tensor]
    spec: ProductionHeadsSpec = field(repr=False, default=None)  # type: ignore[assignment]

    def __post_init__(self) -> None:
        if self.spec is None:
            raise ProductionHeadsError("supervision requires a ProductionHeadsSpec")
        if set(self.targets) != set(PRODUCTION_TENSOR_HEAD_ORDER) or set(self.masks) != set(
            PRODUCTION_TENSOR_HEAD_ORDER
        ):
            raise ProductionHeadsError("supervision must cover exactly the six production tensor heads")
        for head in PRODUCTION_TENSOR_HEAD_ORDER:
            target, mask = self.targets[head], self.masks[head]
            if not isinstance(target, Tensor) or not isinstance(mask, Tensor):
                raise ProductionHeadsError(f"{head} targets/masks must be tensors")
            expected = (1, self.spec.width(head))
            if tuple(target.shape) != expected or tuple(mask.shape) != expected:
                raise ProductionHeadsError(f"{head} targets/masks must have shape {expected}")
            if not torch.isfinite(target).all():
                raise ProductionHeadsError(f"{head} targets must be finite")
            if torch.any((mask != 0.0) & (mask != 1.0)):
                raise ProductionHeadsError(f"{head} masks must be 0/1")
            if torch.any((mask == 0.0) & (target != 0.0)):
                raise ProductionHeadsError(f"{head} has a non-zero target under a zero mask")

    def collate(self, others: Sequence["ProductionLabelSupervision"]) -> tuple[dict[str, Tensor], dict[str, Tensor]]:
        """Stack this and the given supervisions into ``[B, W]`` tensors."""

        group = (self, *others)
        for item in group:
            if item.spec.contract_id != self.spec.contract_id:
                raise ProductionHeadsError("cannot collate supervisions from different specs")
        targets: dict[str, Tensor] = {}
        masks: dict[str, Tensor] = {}
        for head in PRODUCTION_TENSOR_HEAD_ORDER:
            targets[head] = torch.cat([item.targets[head] for item in group], dim=0)
            masks[head] = torch.cat([item.masks[head] for item in group], dim=0)
        return targets, masks


def supervision_from_release_label(
    label: Mapping[str, object] | None,
    spec: ProductionHeadsSpec | None = None,
) -> ProductionLabelSupervision:
    """Convert one release-label-shaped record into masked head supervision.

    Accepted shape mirrors ``camera_release_label_v1`` for the supervised
    fields: ``verdict`` (``good``/``mixed``/``needs_fix``/``None``), ``issues``
    (exactly 15 entries with ``issue_id``/``status``), ``action`` (``None`` or
    ``{action_id, magnitude}``), ``risk`` and ``abstention`` (``None`` or
    ``{status, ...}``). A ``None`` section means *not adjudicated* and yields a
    zero mask — never a zero target. Unknown ids/statuses fail closed.

    Semantics (contract H1–H6):

    * ``verdict='good'`` → good-frame target 1; ``'needs_fix'``/``'mixed'`` →
      explicit negative 0; ``None`` (abstain/unadjudicated) → masked out.
    * issue ``present`` → 1 with mask; ``absent`` → explicit negative 0 with
      mask; ``not_observed`` → uncertainty, masked out.
    * a corrective action is supervised only on its own mapped column;
      unsupported/app-only actions are rejected; ``action=None`` (keep frame)
      masks the whole utility head; ``magnitude`` labels one delta axis when
      ``observed``.
    * ``risk.status='observed'`` and an adjudicated ``abstention.status``
      supervise their single-logit heads; everything else stays masked.
    """

    spec = spec or ProductionHeadsSpec.load()
    targets: dict[str, Tensor] = {}
    masks: dict[str, Tensor] = {}

    # H1 good_frame_probability ------------------------------------------------
    verdict = None if label is None else label.get("verdict", None)
    if verdict is not None and verdict not in (VERDICT_POSITIVE, *VERDICT_NEGATIVES):
        raise ProductionHeadsError(f"unknown verdict: {verdict!r}")
    good_target = 1.0 if verdict == VERDICT_POSITIVE else 0.0
    good_mask = 1.0 if verdict is not None else 0.0
    targets["good_frame_probability"] = torch.tensor([[good_target]], dtype=torch.float32)
    masks["good_frame_probability"] = torch.tensor([[good_mask]], dtype=torch.float32)

    # H2 issue_logits ----------------------------------------------------------
    issue_target = torch.zeros(1, len(spec.issue_ids), dtype=torch.float32)
    issue_mask = torch.zeros(1, len(spec.issue_ids), dtype=torch.float32)
    raw_issues = None if label is None else label.get("issues", None)
    if raw_issues is not None:
        if not isinstance(raw_issues, Sequence) or isinstance(raw_issues, (str, bytes, bytearray)):
            raise ProductionHeadsError("issues must be a sequence of issue entries")
        seen: set[str] = set()
        for entry in raw_issues:
            if not isinstance(entry, Mapping):
                raise ProductionHeadsError("each issue entry must be an object")
            issue_id = entry.get("issue_id")
            if not isinstance(issue_id, str) or issue_id not in spec.issue_ids:
                raise ProductionHeadsError(f"unknown issue id: {issue_id!r}")
            if issue_id in seen:
                raise ProductionHeadsError(f"duplicate issue entry: {issue_id}")
            seen.add(issue_id)
            status = entry.get("status")
            column = spec.issue_ids.index(issue_id)
            if status == ISSUE_STATUS_PRESENT:
                issue_target[0, column] = 1.0
                issue_mask[0, column] = 1.0
            elif status == ISSUE_STATUS_ABSENT:
                issue_target[0, column] = 0.0  # explicit negative
                issue_mask[0, column] = 1.0
            elif status == ISSUE_STATUS_NOT_OBSERVED:
                issue_target[0, column] = 0.0  # placeholder; uncertainty is masked out
                issue_mask[0, column] = 0.0
            else:
                raise ProductionHeadsError(f"unknown issue status for {issue_id}: {status!r}")
        missing = [issue_id for issue_id in spec.issue_ids if issue_id not in seen]
        if missing:
            raise ProductionHeadsError(f"issues must cover all 15 release heads; missing: {missing}")
    targets["issue_logits"] = issue_target
    masks["issue_logits"] = issue_mask

    # H3 action_utility_logits + H4 continuous_target_deltas -------------------
    action_target = torch.zeros(1, len(spec.action_ids), dtype=torch.float32)
    action_mask = torch.zeros(1, len(spec.action_ids), dtype=torch.float32)
    delta_target = torch.zeros(1, len(spec.delta_axes), dtype=torch.float32)
    delta_mask = torch.zeros(1, len(spec.delta_axes), dtype=torch.float32)
    raw_action = None if label is None else label.get("action", None)
    if raw_action is not None:
        if not isinstance(raw_action, Mapping):
            raise ProductionHeadsError("action must be an object or null")
        action_id = spec.require_action_supported(raw_action.get("action_id"))
        action_target[0, spec.action_ids.index(action_id)] = 1.0
        action_mask[0, spec.action_ids.index(action_id)] = 1.0
        magnitude = raw_action.get("magnitude")
        if not isinstance(magnitude, Mapping):
            raise ProductionHeadsError("action.magnitude must be an object")
        magnitude_status = magnitude.get("status")
        if magnitude_status == OBSERVATION_OBSERVED:
            axis = magnitude.get("axis")
            if not isinstance(axis, str) or axis not in spec.delta_axes:
                raise ProductionHeadsError(f"unknown magnitude axis: {axis!r}")
            value = _finite(magnitude.get("value"), "magnitude value")
            if not -1.0 <= value <= 1.0:
                raise ProductionHeadsError("magnitude value must be in [-1, 1]")
            delta_target[0, spec.delta_axes.index(axis)] = value
            delta_mask[0, spec.delta_axes.index(axis)] = 1.0
        elif magnitude_status != OBSERVATION_NOT_OBSERVED:
            raise ProductionHeadsError(f"unknown magnitude status: {magnitude_status!r}")
    targets["action_utility_logits"] = action_target
    masks["action_utility_logits"] = action_mask
    targets["continuous_target_deltas"] = delta_target
    masks["continuous_target_deltas"] = delta_mask

    # H5 risk_probability ------------------------------------------------------
    raw_risk = None if label is None else label.get("risk", None)
    risk_target, risk_mask_value = 0.0, 0.0
    if raw_risk is not None:
        if not isinstance(raw_risk, Mapping):
            raise ProductionHeadsError("risk must be an object or null")
        status = raw_risk.get("status")
        if status == OBSERVATION_OBSERVED:
            risk_target = _unit_interval(raw_risk.get("probability"), "risk probability")
            risk_mask_value = 1.0
        elif status != OBSERVATION_NOT_OBSERVED:
            raise ProductionHeadsError(f"unknown risk status: {status!r}")
    targets["risk_probability"] = torch.tensor([[risk_target]], dtype=torch.float32)
    masks["risk_probability"] = torch.tensor([[risk_mask_value]], dtype=torch.float32)

    # H6 abstention_probability ------------------------------------------------
    raw_abstention = None if label is None else label.get("abstention", None)
    abstain_target, abstain_mask_value = 0.0, 0.0
    if raw_abstention is not None:
        if not isinstance(raw_abstention, Mapping):
            raise ProductionHeadsError("abstention must be an object or null")
        status = raw_abstention.get("status")
        if status == ABSTENTION_ABSTAIN:
            abstain_target, abstain_mask_value = 1.0, 1.0
        elif status == ABSTENTION_NONE:
            abstain_target, abstain_mask_value = 0.0, 1.0
        else:
            raise ProductionHeadsError(f"unknown abstention status: {status!r}")
    targets["abstention_probability"] = torch.tensor([[abstain_target]], dtype=torch.float32)
    masks["abstention_probability"] = torch.tensor([[abstain_mask_value]], dtype=torch.float32)

    return ProductionLabelSupervision(targets, masks, spec)


@dataclass(frozen=True)
class ProductionLossWeights:
    """Non-negative weights for the six production loss terms."""

    good_frame_probability: float = 1.0
    issue_logits: float = 1.0
    action_utility_logits: float = 1.0
    continuous_target_deltas: float = 1.0
    risk_probability: float = 1.0
    abstention_probability: float = 1.0

    def __post_init__(self) -> None:
        for head in PRODUCTION_TENSOR_HEAD_ORDER:
            value = getattr(self, head)
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(
                float(value)
            ) or float(value) < 0.0:
                raise ProductionHeadsError(f"loss weight {head} must be finite and non-negative")

    @classmethod
    def from_mapping(cls, value: Mapping[str, object] | None) -> "ProductionLossWeights":
        if value is None:
            return cls()
        if not isinstance(value, Mapping) or set(value) != set(PRODUCTION_TENSOR_HEAD_ORDER):
            raise ProductionHeadsError(
                f"loss weights must name exactly {sorted(PRODUCTION_TENSOR_HEAD_ORDER)}"
            )
        return cls(**{head: float(value[head]) for head in PRODUCTION_TENSOR_HEAD_ORDER})


@dataclass(frozen=True)
class ProductionLossResult:
    total: Tensor
    per_head: Mapping[str, Tensor]


def _checked_batch(
    values: Mapping[str, Tensor] | None,
    spec: ProductionHeadsSpec,
    batch_size: int,
    label: str,
    *,
    required: bool,
) -> dict[str, Tensor]:
    if values is None:
        if required:
            raise ProductionHeadsError(f"{label} must be provided for every supervised batch")
        return {}
    if not isinstance(values, Mapping) or set(values) != set(PRODUCTION_TENSOR_HEAD_ORDER):
        raise ProductionHeadsError(f"{label} must cover exactly the six production tensor heads")
    checked: dict[str, Tensor] = {}
    for head, tensor in values.items():
        if not isinstance(tensor, Tensor):
            raise ProductionHeadsError(f"{label}[{head}] must be a tensor")
        expected = (batch_size, spec.width(head))
        if tuple(tensor.shape) != expected:
            raise ProductionHeadsError(f"{label}[{head}] must have shape {expected}, got {tuple(tensor.shape)}")
        if tensor.dtype != torch.float32:
            raise ProductionHeadsError(f"{label}[{head}] must be float32")
        if not torch.isfinite(tensor).all():
            raise ProductionHeadsError(f"{label}[{head}] must be finite")
        if label == "masks" and torch.any((tensor != 0.0) & (tensor != 1.0)):
            raise ProductionHeadsError(f"{label}[{head}] must be 0/1")
        checked[head] = tensor
    return checked


def compute_production_heads_loss(
    outputs: Mapping[str, Tensor],
    targets: Mapping[str, Tensor] | None,
    masks: Mapping[str, Tensor] | None,
    spec: ProductionHeadsSpec | None = None,
    *,
    weights: ProductionLossWeights | Mapping[str, object] | None = None,
) -> ProductionLossResult:
    """Masked multi-task loss over the six production tensor heads.

    ``outputs`` are raw head logits (no sigmoid/tanh applied). ``targets`` and
    ``masks`` must both be provided and share every head; a target without an
    explicit mask is rejected — supervision is never implicitly all-ones. A
    fully masked head reduces to a differentiable zero (existing
    :func:`ml.camera_coach.losses.masked_mean` semantics), so a missing label
    contributes neither loss nor gradient while staying backward-safe.

    Loss per contract H1–H6: ``masked_bce`` on the single-logit probability
    heads, ``masked_bce_with_logits`` on issue/action utility, ``masked_huber``
    on target deltas.
    """

    spec = spec or ProductionHeadsSpec.load()
    selected_weights = weights if isinstance(weights, ProductionLossWeights) else ProductionLossWeights.from_mapping(
        weights
    )
    if not isinstance(outputs, Mapping) or set(outputs) != set(PRODUCTION_TENSOR_HEAD_ORDER):
        raise ProductionHeadsError("outputs must cover exactly the six production tensor heads")
    batch_sizes = set()
    for head, tensor in outputs.items():
        if not isinstance(tensor, Tensor):
            raise ProductionHeadsError(f"output {head} must be a tensor")
        if tensor.ndim != 2 or tensor.shape[1] != spec.width(head):
            raise ProductionHeadsError(f"output {head} must have shape [batch, {spec.width(head)}]")
        if tensor.dtype != torch.float32:
            raise ProductionHeadsError(f"output {head} must be float32")
        if not torch.isfinite(tensor).all():
            raise ProductionHeadsError(f"output {head} must be finite")
        batch_sizes.add(tensor.shape[0])
    if len(batch_sizes) != 1:
        raise ProductionHeadsError("all production outputs must share one batch size")
    batch_size = next(iter(batch_sizes))
    if batch_size < 1:
        raise ProductionHeadsError("outputs must contain at least one sample")
    target_batch = _checked_batch(targets, spec, batch_size, "targets", required=True)
    mask_batch = _checked_batch(masks, spec, batch_size, "masks", required=True)

    per_head: dict[str, Tensor] = {}
    for head in PRODUCTION_TENSOR_HEAD_ORDER:
        prediction = outputs[head]
        head_target = target_batch.get(head)
        head_mask = mask_batch.get(head)
        if head_target is None or head_mask is None:
            raise ProductionHeadsError(f"head {head} needs both a target and a mask")
        if head == "continuous_target_deltas":
            raw = smooth_l1_loss(prediction, head_target, head_mask)
        else:
            raw = binary_cross_entropy_with_logits(prediction, head_target, head_mask)
        per_head[head] = raw * selected_weights.__getattribute__(head)
    total = torch.stack(list(per_head.values())).sum()
    return ProductionLossResult(total, MappingProxyType(per_head))


class ProductionHeadsScorer(nn.Module):
    """Trainer-side scorer over the production head layout.

    A deliberately small deterministic trunk plus one linear head per
    production tensor head, sized by :class:`ProductionHeadsSpec`. It emits
    **raw logits** (the masked losses apply ``binary_cross_entropy_with_logits``
    internally). This is the head-layout owner used to verify masked training
    semantics; it is not the frozen v1/v2 export architecture, not a Core ML
    artifact, and carries no admission or quality claim (ML-012+ owns export).
    """

    architecture_id = "SETCompositionNet-production-heads-trainer-v1"

    def __init__(
        self,
        spec: ProductionHeadsSpec | None = None,
        *,
        feature_dim: int = 32,
        hidden_dim: int = 64,
    ):
        super().__init__()
        self.spec = spec or ProductionHeadsSpec.load()
        if feature_dim < 1 or hidden_dim < 1:
            raise ProductionHeadsError("feature_dim and hidden_dim must be positive")
        self.trunk = nn.Sequential(
            nn.Linear(feature_dim, hidden_dim),
            nn.Hardswish(inplace=True),
        )
        self.heads = nn.ModuleDict(
            {head: nn.Linear(hidden_dim, self.spec.width(head)) for head in PRODUCTION_TENSOR_HEAD_ORDER}
        )

    def forward(self, features: Tensor) -> "OrderedDict[str, Tensor]":
        if not isinstance(features, Tensor) or features.dtype != torch.float32 or features.ndim != 2:
            raise ProductionHeadsError("features must be a float32 [batch, feature_dim] tensor")
        if not torch.isfinite(features).all():
            raise ProductionHeadsError("features must be finite")
        fused = self.trunk(features)
        outputs: "OrderedDict[str, Tensor]" = OrderedDict()
        for head in PRODUCTION_TENSOR_HEAD_ORDER:
            outputs[head] = self.heads[head](fused)
        return outputs


@dataclass(frozen=True)
class ResearchBaseline:
    """Metadata of a loaded old focused checkpoint; never a production claim."""

    checkpoint_path: str
    checkpoint_sha256: str
    schema_id: str
    epoch: int
    research_only: bool
    human_gold: bool
    release_admissible: bool
    production_admitted: bool
    trained_heads: tuple[str, ...]
    untrained_production_heads: tuple[str, ...]
    head_widths: Mapping[str, int]
    state_dict: Mapping[str, Tensor] = field(repr=False)


def _baseline_head_widths(state: Mapping[str, object]) -> dict[str, int]:
    widths: dict[str, int] = {}
    for key, value in state.items():
        match = _HEAD_WIDTH_KEY_RE.match(str(key))
        if match is None:
            continue
        if not isinstance(value, Tensor) or value.ndim != 2:
            raise ResearchBaselineError(f"baseline state entry {key!r} is not a 2-D weight tensor")
        head, width = match.group(1), int(value.shape[0])
        prior = widths.get(head)
        if prior is not None and prior != width:
            raise ResearchBaselineError(f"baseline head {head} has inconsistent widths")
        widths[head] = width
    return widths


def load_research_baseline(checkpoint_path: str | Path, *, research_only: bool = False) -> ResearchBaseline:
    """Load the old focused silver Stage-2 checkpoint as a research baseline.

    The explicit ``research_only=True`` argument is mandatory: the checkpoint
    is silver-supervised research evidence (``human_gold=false``,
    ``release_admissible=false``) and can never back a production claim. The
    payload's own flags are re-verified, the frozen research layout is checked
    (issue width 8, old action width 26, 5 delta axes — contract GAP-2/GAP-3),
    and the production heads that the baseline never trained (good-frame, risk,
    abstention — GAP-1) are reported as untrained. Loading this state into the
    15/26-mapped production layout is a width error by design.
    """

    if research_only is not True:
        raise ResearchBaselineError(
            "the old focused checkpoint is loadable only as a research baseline: "
            "call load_research_baseline(path, research_only=True); "
            "production use is forbidden without separate admission (ML-014/ML-018)"
        )
    path = Path(checkpoint_path)
    try:
        payload = torch.load(path, map_location="cpu", weights_only=False)
    except (OSError, RuntimeError, ValueError, EOFError, pickle.UnpicklingError) as exc:  # type: ignore[name-defined]
        raise ResearchBaselineError(f"cannot load research baseline checkpoint: {path}") from exc
    if not isinstance(payload, Mapping):
        raise ResearchBaselineError("research baseline checkpoint must be a mapping")
    if payload.get("schema_id") != _RESEARCH_CHECKPOINT_SCHEMA_ID:
        raise ResearchBaselineError(
            f"checkpoint is not a {_RESEARCH_CHECKPOINT_SCHEMA_ID} file: {path}"
        )
    if payload.get("research_only") is not True or payload.get("human_gold") is not False or (
        payload.get("release_admissible") is not False
    ):
        raise ResearchBaselineError(
            "research baseline payload crossed the research-only boundary "
            "(research_only/human_gold/release_admissible flags disagree)"
        )
    state = payload.get("model_state")
    if not isinstance(state, Mapping) or not state:
        raise ResearchBaselineError("research baseline has no model_state")
    widths = _baseline_head_widths(state)
    research_layout = {
        "issue_logits": 8,
        "action_utility_logits": 26,
        "continuous_target_deltas": 5,
    }
    for head, expected in research_layout.items():
        if widths.get(head) != expected:
            raise ResearchBaselineError(
                f"baseline head {head} width {widths.get(head)} is not the focused research "
                f"layout ({expected}); this loader only accepts the old focused checkpoint"
            )
    for head in PRODUCTION_TENSOR_HEAD_ORDER:
        widths.setdefault(head, 0)
    try:
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError as exc:
        raise ResearchBaselineError(f"cannot hash research baseline checkpoint: {path}") from exc
    epoch = payload.get("epoch")
    if not isinstance(epoch, int) or epoch < 0:
        raise ResearchBaselineError("research baseline epoch must be a non-negative integer")
    return ResearchBaseline(
        checkpoint_path=str(path),
        checkpoint_sha256=digest,
        schema_id=str(payload["schema_id"]),
        epoch=epoch,
        research_only=True,
        human_gold=False,
        release_admissible=False,
        production_admitted=False,
        trained_heads=RESEARCH_TRAINED_HEADS,
        untrained_production_heads=SINGLE_LOGIT_HEADS,
        head_widths=MappingProxyType(widths),
        state_dict=MappingProxyType(dict(state)),
    )


__all__ = [
    "CALIBRATION_HEAD_ID",
    "PRODUCTION_TENSOR_HEAD_ORDER",
    "PRODUCTION_HEADS_DOC_PATH",
    "ProductionHeadsError",
    "ProductionHeadsScorer",
    "ProductionHeadsSpec",
    "ProductionLabelSupervision",
    "ProductionLossResult",
    "ProductionLossWeights",
    "RESEARCH_TRAINED_HEADS",
    "ResearchBaseline",
    "ResearchBaselineError",
    "compute_production_heads_loss",
    "load_research_baseline",
    "supervision_from_release_label",
]
