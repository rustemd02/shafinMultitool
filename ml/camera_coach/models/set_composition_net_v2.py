"""SETCompositionNet-v2 input contract reader and intent-conditioned trust boundary.

v2 is a *numeric* successor of the frozen ``set_composition_net_v1`` contract.
It adds one explicit 9-component input, ``intent_features``, that carries the
user's CaptureIntent style selection, and a frozen supervision-mask rule for the
intent-conditioned heads.  The v1 manifest is never rewritten and a v1
checkpoint cannot be relabelled as v2: the model input signature changes.

This module owns the v2 contract reader, the intent input validation, and the
v2 candidate architectures that actually consume ``intent_features``.  It does
not train, does not export, and does not enable any runtime provider.
"""

from __future__ import annotations

from collections import OrderedDict
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
import json
from pathlib import Path

import torch
from torch import Tensor, nn

from .set_composition_net import (
    ContractError,
    SETCompositionNetInputs,
    _MobileNetV3Backbone,
    _SETCompositionNetCandidateBase,
    _prepare_inputs,
)


_V2_CONTRACTS_DIR = Path(__file__).resolve().parents[1] / "contracts"
V2_MANIFEST_PATH = _V2_CONTRACTS_DIR / "set_composition_net_v2.json"

# Frozen v2 numeric signature.  These guards are read back from the manifest
# and must match exactly; a silent tensor or head change fails loudly.
_FROZEN_INPUT_SHAPES = {
    "full_frame_rgb": (320, 320, 3),
    "subject_crop_rgb": (192, 192, 3),
    "roi_normalized_xywh": (4,),
    "roi_mask": (320, 320, 1),
    "scalar_features": (40,),
    "intent_features": (9,),
}
_FROZEN_OUTPUT_HEAD_ORDER = (
    "scene_class_logits",
    "subjectness_roi_agreement_logits",
    "issue_logits",
    "action_utility_logits",
    "good_frame_probability",
    "abstention_probability",
    "risk_probability",
    "continuous_target_deltas",
    "embedding",
)
_FROZEN_OUTPUT_HEAD_SHAPES = {
    "scene_class_logits": 8,
    "subjectness_roi_agreement_logits": 3,
    "issue_logits": 8,
    "action_utility_logits": 26,
    "good_frame_probability": 1,
    "abstention_probability": 1,
    "risk_probability": 1,
    "continuous_target_deltas": 5,
    "embedding": 128,
}
INTENT_STYLE_NAMES: tuple[str, ...] = (
    "natural",
    "silhouette",
    "low_key",
    "symmetry",
    "negative_space",
    "dutch_angle",
    "intentional_motion_blur",
    "handheld",
)
KNOWN_FLAG_NAME = "known"
INTENT_ORDER: tuple[str, ...] = INTENT_STYLE_NAMES + (KNOWN_FLAG_NAME,)
KNOWN_FLAG_INDEX = 8
INTENT_CONDITIONED_HEAD_ORDER: tuple[str, ...] = (
    "good_frame_probability",
    "risk_probability",
    "action_utility_logits",
    "continuous_target_deltas",
)


@dataclass(frozen=True)
class SETCompositionNetV2Manifest:
    """Parsed view of the frozen machine-readable v2 manifest."""

    raw: dict
    input_shapes: dict[str, tuple[int, ...]]
    output_head_names: tuple[str, ...]
    output_head_shapes: dict[str, int]
    output_head_specs: dict[str, dict]
    intent_order: tuple[str, ...]
    intent_style_names: tuple[str, ...]
    known_index: int
    intent_conditioned_heads: tuple[str, ...]
    supervision_mask_fill_value: float
    embedding_name: str

    @classmethod
    def load(cls, path: str | Path | None = None) -> "SETCompositionNetV2Manifest":
        manifest_path = Path(path) if path else V2_MANIFEST_PATH
        try:
            with manifest_path.open(encoding="utf-8") as stream:
                raw = json.load(stream)
        except (OSError, json.JSONDecodeError) as exc:
            raise ContractError(f"cannot load SETCompositionNet-v2 manifest: {manifest_path}") from exc
        if not isinstance(raw, dict):
            raise ContractError("SETCompositionNet-v2 manifest must be a JSON object")
        return cls._from_raw(raw, manifest_path)

    @classmethod
    def _from_raw(cls, raw: dict, path: Path) -> "SETCompositionNetV2Manifest":
        required_top_level = {
            "contract_id",
            "contract_version",
            "input_contract_version",
            "preprocessing_version",
            "feature_version",
            "output_contract_version",
            "tensor_layout",
            "inputs",
            "preprocessing",
            "categorical_features",
            "feature_normalization",
            "supervision",
            "outputs",
        }
        if set(raw) != required_top_level:
            raise ContractError(f"v2 manifest top-level keys drifted in {path}")
        expected_versions = {
            "contract_id": "SETCompositionNet",
            "contract_version": "setcompositionnet.v2",
            "input_contract_version": "setcompositionnet.input.v2",
            "preprocessing_version": "setcompositionnet.preprocessing.v2",
            "feature_version": "setcompositionnet.features.v2",
            "output_contract_version": "setcompositionnet.output.v2",
        }
        for key, expected in expected_versions.items():
            if raw.get(key) != expected:
                raise ContractError(f"v2 manifest {key} is not the frozen v2 value")
        if raw.get("tensor_layout") != "HWC":
            raise ContractError("SETCompositionNet-v2 requires HWC logical tensors")

        inputs = raw.get("inputs")
        if not isinstance(inputs, dict):
            raise ContractError("v2 manifest inputs must be an object")
        if set(inputs) != set(_FROZEN_INPUT_SHAPES):
            raise ContractError("v2 manifest input names drifted")
        input_shapes: dict[str, tuple[int, ...]] = {}
        for name, node in inputs.items():
            if not isinstance(node, dict) or node.get("dtype") != "float32":
                raise ContractError(f"v2 manifest input {name} must be float32")
            shape = node.get("shape")
            if not isinstance(shape, list) or not shape or not all(
                type(value) is int and value > 0 for value in shape
            ):
                raise ContractError(f"v2 manifest input {name} has an invalid shape")
            input_shapes[name] = tuple(shape)
        if input_shapes != _FROZEN_INPUT_SHAPES:
            raise ContractError("v2 manifest input tensor shapes are not frozen v2 values")
        if input_shapes["full_frame_rgb"][-1] != 3 or len(input_shapes["full_frame_rgb"]) != 3:
            raise ContractError("full_frame_rgb must remain HWC RGB")
        if input_shapes["subject_crop_rgb"][-1] != 3 or len(input_shapes["subject_crop_rgb"]) != 3:
            raise ContractError("subject_crop_rgb must remain HWC RGB")
        if input_shapes["roi_mask"][-1] != 1 or len(input_shapes["roi_mask"]) != 3:
            raise ContractError("roi_mask must remain HWC binary")
        if input_shapes["roi_normalized_xywh"] != (4,):
            raise ContractError("roi_normalized_xywh shape drifted")
        scalar_node = inputs["scalar_features"]
        if scalar_node.get("count") != input_shapes["scalar_features"][0]:
            raise ContractError("scalar feature count does not match its shape")
        missing_node = scalar_node.get("missing_mask")
        if not isinstance(missing_node, dict) or missing_node.get("shape") != list(input_shapes["scalar_features"]):
            raise ContractError("missing feature mask shape drifted")
        if scalar_node.get("inherited_from") != "setcompositionnet.input.v1":
            raise ContractError("v2 scalar features must declare their v1 lineage")

        intent_node = inputs["intent_features"]
        intent_order, known_index, style_names = cls._validate_intent_node(intent_node)

        supervision = cls._validate_supervision(raw.get("supervision"), intent_order)

        outputs = raw.get("outputs")
        if not isinstance(outputs, dict) or set(outputs) != {"head_order", "heads", "forbidden_outputs"}:
            raise ContractError("v2 manifest output contract is not closed")
        head_order = outputs.get("head_order")
        heads = outputs.get("heads")
        if not isinstance(head_order, list) or not head_order or not isinstance(heads, list):
            raise ContractError("v2 manifest output heads are malformed")
        if tuple(head_order) != _FROZEN_OUTPUT_HEAD_ORDER or len(heads) != len(head_order):
            raise ContractError("v2 output head order is not the frozen v2 order")
        if outputs.get("forbidden_outputs") != ["generated_text", "arbitrary_object_name"]:
            raise ContractError("v2 forbidden output catalog drifted")
        head_shapes: dict[str, int] = {}
        head_specs: dict[str, dict] = {}
        for expected_name, node in zip(head_order, heads):
            if not isinstance(expected_name, str) or not isinstance(node, dict):
                raise ContractError("v2 output head entry is malformed")
            if node.get("name") != expected_name or node.get("dtype") != "float32":
                raise ContractError(f"v2 output head {expected_name!r} is out of order")
            shape = node.get("shape")
            if not isinstance(shape, list) or len(shape) != 1 or type(shape[0]) is not int or shape[0] < 1:
                raise ContractError(f"v2 output head {expected_name!r} has an invalid shape")
            head_shapes[expected_name] = shape[0]
            head_specs[expected_name] = node
        if head_shapes != _FROZEN_OUTPUT_HEAD_SHAPES:
            raise ContractError("v2 output head dimensions are not frozen v2 values")
        if head_shapes["embedding"] != 128:
            raise ContractError("SETCompositionNet-v2 embedding must remain 128D")
        return cls(
            raw=raw,
            input_shapes=input_shapes,
            output_head_names=tuple(head_order),
            output_head_shapes=head_shapes,
            output_head_specs=head_specs,
            intent_order=intent_order,
            intent_style_names=style_names,
            known_index=known_index,
            intent_conditioned_heads=supervision,
            supervision_mask_fill_value=float(
                raw["supervision"]["supervision_mask"]["fill_value"]
            ),
            embedding_name="embedding",
        )

    @staticmethod
    def _validate_intent_node(node: object) -> tuple[tuple[str, ...], int, tuple[str, ...]]:
        expected_keys = {
            "dtype",
            "shape",
            "count",
            "value_range",
            "values",
            "separate_input",
            "not_encoded_in_scalar_features",
            "source",
            "ordered_names",
            "style_flags",
            "known_flag",
            "unknown_encoding",
            "known_encoding",
            "explicit_natural",
            "distinctness",
        }
        if not isinstance(node, dict) or set(node) != expected_keys:
            raise ContractError("v2 intent_features node is not a closed object")
        if node.get("dtype") != "float32" or node.get("shape") != [9] or node.get("count") != 9:
            raise ContractError("v2 intent_features must be a float32 [9] vector")
        if node.get("value_range") != [0.0, 1.0] or node.get("values") != [0.0, 1.0]:
            raise ContractError("v2 intent_features must remain binary-valued in [0, 1]")
        if node.get("separate_input") is not True:
            raise ContractError("v2 intent_features must be a separate input tensor")
        if not isinstance(node.get("not_encoded_in_scalar_features"), str) or not node[
            "not_encoded_in_scalar_features"
        ]:
            raise ContractError("v2 intent_features must document scalar-slot isolation")
        ordered_names = node.get("ordered_names")
        if not isinstance(ordered_names, list) or tuple(ordered_names) != INTENT_ORDER:
            raise ContractError("v2 intent_features order drifted from the frozen 9-component order")
        style_flags = node.get("style_flags")
        if not isinstance(style_flags, dict) or set(style_flags) != {
            "count", "indices", "ordered_names", "one_hot", "multi_style_allowed", "multi_style_semantics"
        }:
            raise ContractError("v2 intent style_flags node is not closed")
        if style_flags.get("count") != 8 or style_flags.get("indices") != list(range(8)):
            raise ContractError("v2 intent style flag count/indices drifted")
        if tuple(style_flags.get("ordered_names", ())) != INTENT_STYLE_NAMES:
            raise ContractError("v2 intent style flag order drifted")
        if style_flags.get("one_hot") is not False or style_flags.get("multi_style_allowed") is not True:
            raise ContractError("v2 intent flags must be non-one-hot and multi-style preserving")
        known_flag = node.get("known_flag")
        if not isinstance(known_flag, dict) or set(known_flag) != {"name", "index", "values", "semantics"}:
            raise ContractError("v2 intent known_flag node is not closed")
        if known_flag.get("name") != KNOWN_FLAG_NAME or known_flag.get("index") != KNOWN_FLAG_INDEX:
            raise ContractError("v2 intent known flag index/name drifted")
        unknown = node.get("unknown_encoding")
        if not isinstance(unknown, dict) or set(unknown) != {"known", "style_flags", "forbidden_default", "rule"}:
            raise ContractError("v2 intent unknown_encoding node is not closed")
        if unknown.get("known") != 0.0 or unknown.get("style_flags") != [0.0] * 8:
            raise ContractError("v2 unknown intent must be known=0 with all style flags 0")
        if unknown.get("forbidden_default") != "natural":
            raise ContractError("v2 unknown intent must forbid the natural default")
        known_encoding = node.get("known_encoding")
        if not isinstance(known_encoding, dict) or known_encoding.get("empty_with_known_one_invalid") is not True:
            raise ContractError("v2 known encoding must reject an empty explicit style set")
        explicit_natural = node.get("explicit_natural")
        if not isinstance(explicit_natural, dict) or explicit_natural.get("distinct_from_unknown") is not True:
            raise ContractError("v2 explicit natural must remain distinct from unknown")
        if not isinstance(node.get("distinctness"), str) or not node["distinctness"]:
            raise ContractError("v2 intent distinctness rule must be documented")
        return INTENT_ORDER, KNOWN_FLAG_INDEX, INTENT_STYLE_NAMES

    @staticmethod
    def _validate_supervision(node: object, intent_order: tuple[str, ...]) -> tuple[str, ...]:
        expected_keys = {
            "principle",
            "runtime_gates_owner",
            "intent_conditioned_heads",
            "intent_independent_heads",
            "supervision_mask",
            "admissibility",
            "unsupported_target_rule",
            "forbidden_neural_targets",
            "new_intent_inputs",
        }
        if not isinstance(node, dict) or set(node) != expected_keys:
            raise ContractError("v2 supervision node is not a closed object")
        conditioned = node.get("intent_conditioned_heads")
        if not isinstance(conditioned, list) or tuple(conditioned) != INTENT_CONDITIONED_HEAD_ORDER:
            raise ContractError("v2 intent-conditioned head order drifted")
        independent = node.get("intent_independent_heads")
        if tuple(independent or ()) != tuple(
            name for name in _FROZEN_OUTPUT_HEAD_ORDER if name not in INTENT_CONDITIONED_HEAD_ORDER
        ):
            raise ContractError("v2 intent-independent head partition drifted")
        mask = node.get("supervision_mask")
        if not isinstance(mask, dict) or set(mask) != {
            "dtype", "shape", "ordered_names", "values", "fill_value", "semantics"
        }:
            raise ContractError("v2 supervision_mask node is not closed")
        if mask.get("dtype") != "float32" or mask.get("shape") != [4] or tuple(mask.get("ordered_names", ())) != tuple(conditioned):
            raise ContractError("v2 supervision_mask must mirror the intent-conditioned head order")
        if mask.get("values") != [0.0, 1.0] or mask.get("fill_value") != 0.0:
            raise ContractError("v2 supervision_mask must be a 0/1 mask with a zero fill")
        admissibility = node.get("admissibility")
        if not isinstance(admissibility, dict) or admissibility.get("requires_intent_known") is not True \
                or admissibility.get("requires_roi_present") is not True:
            raise ContractError("v2 supervision admissibility must require known intent and a present ROI")
        unsupported = node.get("unsupported_target_rule")
        if not isinstance(unsupported, dict) or unsupported.get("fabricated_conditional_label_forbidden") is not True \
                or unsupported.get("set_neural_mask_zero") is not True \
                or unsupported.get("preserve_human_annotation") is not True:
            raise ContractError("v2 unsupported-target rule must mask the neural target and keep the annotation")
        forbidden = node.get("forbidden_neural_targets")
        if not isinstance(forbidden, list) or len(forbidden) != 3:
            raise ContractError("v2 forbidden neural targets must list the three hidden constraints")
        for entry in forbidden:
            if not isinstance(entry, dict) or entry.get("neural_target") is not False \
                    or entry.get("policy_evaluation_label_retained") is not True:
                raise ContractError("v2 hidden constraints must not be neural targets")
        if not isinstance(node.get("new_intent_inputs"), str) or not node["new_intent_inputs"]:
            raise ContractError("v2 must document the separate schema decision for new intent inputs")
        return tuple(conditioned)

    @property
    def scalar_feature_count(self) -> int:
        return self.input_shapes["scalar_features"][0]

    @property
    def intent_feature_count(self) -> int:
        return self.input_shapes["intent_features"][0]

    @property
    def full_frame_shape(self) -> tuple[int, int, int]:
        return self.input_shapes["full_frame_rgb"]  # type: ignore[return-value]

    @property
    def subject_crop_shape(self) -> tuple[int, int, int]:
        return self.input_shapes["subject_crop_rgb"]  # type: ignore[return-value]

    @property
    def roi_mask_shape(self) -> tuple[int, int, int]:
        return self.input_shapes["roi_mask"]  # type: ignore[return-value]


@dataclass(frozen=True)
class SETCompositionNetV2Inputs:
    """Logical HWC tensors at the v2 model trust boundary.

    Six inputs: the five inherited v1 tensors plus the explicit 9-component
    ``intent_features``.  A single unbatched HWC tensor or a batched BHWC
    tensor is canonical.
    """

    full_frame_rgb: Tensor
    subject_crop_rgb: Tensor
    roi_normalized_xywh: Tensor
    roi_mask: Tensor
    scalar_features: Tensor
    missing_feature_mask: Tensor
    intent_features: Tensor

    @classmethod
    def from_mapping(cls, values: Mapping[str, Tensor]) -> "SETCompositionNetV2Inputs":
        expected = {
            "full_frame_rgb",
            "subject_crop_rgb",
            "roi_normalized_xywh",
            "roi_mask",
            "scalar_features",
            "missing_feature_mask",
            "intent_features",
        }
        if set(values) != expected:
            missing = sorted(expected.difference(values))
            extra = sorted(set(values).difference(expected))
            raise ContractError(f"model inputs differ from frozen v2 contract; missing={missing}, extra={extra}")
        return cls(**{key: values[key] for key in expected})


def _as_batch_vector(value: Tensor, expected_width: int, name: str) -> Tensor:
    if value.dtype != torch.float32:
        raise ContractError(f"{name} must be torch.float32, got {value.dtype}")
    if value.ndim == 1 and value.shape[0] == expected_width:
        value = value.unsqueeze(0)
    elif value.ndim != 2 or value.shape[1] != expected_width:
        raise ContractError(f"{name} must have shape [B, {expected_width}] or [{expected_width}]")
    if not torch.isfinite(value).all():
        raise ContractError(f"{name} must contain only finite values")
    return value.contiguous()


def validate_intent_features(
    value: Tensor,
    contract: SETCompositionNetV2Manifest | None = None,
) -> Tensor:
    """Validate the frozen v2 unknown/explicit intent semantics.

    Enforced exactly:

    * values are finite and exactly 0.0 or 1.0;
    * ``known=0`` requires all eight style flags to be 0.0;
    * ``known=1`` requires at least one style flag to be 1.0.

    These two rules make an empty/unknown intent unencodable as ``natural`` and
    make ``natural`` an explicit choice that is distinct from unknown.
    """

    contract = contract or SETCompositionNetV2Manifest.load()
    intent = _as_batch_vector(value, contract.intent_feature_count, "intent_features")
    if torch.any((intent != 0.0) & (intent != 1.0)):
        raise ContractError("intent_features values must be exactly 0 or 1")
    known = intent[:, contract.known_index]
    style = intent[:, : contract.known_index]
    unknown_rows = known == 0.0
    if torch.any(unknown_rows & (style.sum(dim=1) > 0.0)):
        raise ContractError(
            "unknown intent must encode known=0 with all eight style flags 0; "
            "an absent intent must not be filled with a style such as natural"
        )
    known_rows = known == 1.0
    if torch.any(known_rows & (style.sum(dim=1) <= 0.0)):
        raise ContractError("known=1 requires at least one explicit style flag")
    return intent


def encode_intent(
    styles: Sequence[str] | None = None,
    *,
    known: bool | None = None,
    contract: SETCompositionNetV2Manifest | None = None,
) -> Tensor:
    """Encode an explicit CaptureIntent style selection into the 9-vector.

    ``styles`` is the explicit user selection.  ``None`` or an empty sequence is
    the unknown state and is encoded as ``known=0`` with all flags 0.  The
    ``natural`` flag is set only when ``"natural"`` is explicitly present; it is
    never used as a placeholder for an absent intent.  Multiple explicit styles
    are preserved simultaneously.  ``known`` may be passed explicitly to assert
    intent; it must agree with the style selection.
    """

    contract = contract or SETCompositionNetV2Manifest.load()
    if styles is None:
        selected: list[str] = []
    elif isinstance(styles, (str, bytes, bytearray)):
        raise ContractError("styles must be a sequence of style names, not a bare string")
    else:
        selected = [str(style) for style in styles]
    if len(set(selected)) != len(selected):
        raise ContractError("styles must not contain duplicates")
    unknown_styles = sorted(set(selected).difference(contract.intent_style_names))
    if unknown_styles:
        raise ContractError(f"unknown CaptureIntent styles: {unknown_styles}")
    explicit = bool(selected)
    if known is not None:
        if known and not explicit:
            raise ContractError("known=1 requires a non-empty explicit style set")
        if not known and explicit:
            raise ContractError("known=0 cannot carry explicit styles")
    vector = [0.0] * contract.intent_feature_count
    for style in selected:
        vector[contract.intent_order.index(style)] = 1.0
    vector[contract.known_index] = 1.0 if explicit else 0.0
    return torch.tensor(vector, dtype=torch.float32)


def intent_supervision_mask(
    intent_features: Tensor,
    roi_present: bool | float | Sequence[float] | Tensor,
    contract: SETCompositionNetV2Manifest | None = None,
) -> Tensor:
    """Frozen v2 supervision mask for the intent-conditioned heads.

    A neural target is supervised only when it is expressible from the supplied
    inputs: the intent is explicitly known and a ROI is present.  Every other
    record gets mask 0.0 for every intent-conditioned head, so no fabricated
    conditional label is learned when the required input is absent.  The human
    annotation is untouched and stays available for policy evaluation.
    """

    contract = contract or SETCompositionNetV2Manifest.load()
    unbatched = intent_features.ndim == 1
    intent = validate_intent_features(intent_features, contract)
    known = intent[:, contract.known_index]
    present = _as_batch_vector(
        torch.as_tensor(roi_present, dtype=torch.float32).reshape(-1, 1),
        1,
        "roi_present",
    ).squeeze(1)
    if present.shape[0] == 1 and known.shape[0] != 1:
        present = present.expand(known.shape[0])
    if present.shape[0] != known.shape[0]:
        raise ContractError("intent_features and roi_present must share the batch size")
    if torch.any((present != 0.0) & (present != 1.0)):
        raise ContractError("roi_present must be 0 or 1")
    admissible = ((known == 1.0) & (present == 1.0)).to(dtype=torch.float32)
    mask = admissible.unsqueeze(1).expand(-1, len(contract.intent_conditioned_heads)).contiguous()
    return mask.squeeze(0) if unbatched else mask


INTENT_ENCODER_DIM = 32


class _SETCompositionNetV2CandidateBase(_SETCompositionNetCandidateBase):
    """Shared v2 plumbing: v1 tensor trust boundary plus a validated intent.

    The v1 backbone/head code is reused unchanged; v2 only adds an explicit
    intent encoder whose output joins the fusion vector.  ``intent_features``
    is validated at the same trust boundary as the pixels, so an unknown intent
    cannot silently masquerade as ``natural``.
    """

    def __init__(self, contract: SETCompositionNetV2Manifest | None = None):
        contract = contract or SETCompositionNetV2Manifest.load()
        super().__init__(contract)
        self.architecture_id = "SETCompositionNet-v2"
        self.intent_encoder = nn.Sequential(
            nn.Linear(contract.intent_feature_count, INTENT_ENCODER_DIM),
            nn.Hardswish(inplace=True),
        )

    def _coerce_v2_inputs(
        self, inputs: object, args: tuple[object, ...], kwargs: dict[str, object]
    ) -> SETCompositionNetV2Inputs:
        if isinstance(inputs, SETCompositionNetV2Inputs):
            if args or kwargs:
                raise TypeError("do not combine SETCompositionNetV2Inputs with extra model arguments")
            return inputs
        if isinstance(inputs, Mapping):
            if args or kwargs:
                raise TypeError("do not combine input mapping with extra model arguments")
            return SETCompositionNetV2Inputs.from_mapping(inputs)
        if isinstance(inputs, Tensor):
            values = (inputs, *args)
            if kwargs or len(values) != 7:
                raise TypeError(
                    "tensor form is model(full_frame_rgb, subject_crop_rgb, roi_normalized_xywh, "
                    "roi_mask, scalar_features, missing_feature_mask, intent_features)"
                )
            return SETCompositionNetV2Inputs(*values)  # type: ignore[arg-type]
        if inputs is None and not args:
            expected = {
                "full_frame_rgb",
                "subject_crop_rgb",
                "roi_normalized_xywh",
                "roi_mask",
                "scalar_features",
                "missing_feature_mask",
                "intent_features",
            }
            if set(kwargs) != expected:
                raise TypeError(f"keyword model inputs must be exactly {sorted(expected)}")
            return SETCompositionNetV2Inputs(**kwargs)  # type: ignore[arg-type]
        raise TypeError("model input must be SETCompositionNetV2Inputs, a mapping, or seven tensors")

    def _prepare_v2(
        self, values: SETCompositionNetV2Inputs
    ) -> tuple[Tensor, Tensor, Tensor, Tensor, Tensor, Tensor]:
        base = SETCompositionNetInputs(
            values.full_frame_rgb,
            values.subject_crop_rgb,
            values.roi_normalized_xywh,
            values.roi_mask,
            values.scalar_features,
            values.missing_feature_mask,
        )
        full, crop, _roi, mask, scalar, missing, _has_roi = _prepare_inputs(base, self.contract)
        intent = validate_intent_features(values.intent_features, self.contract)
        if intent.shape[0] != full.shape[0]:
            raise ContractError("intent_features batch size must match the other inputs")
        return full, crop, mask, scalar, missing, intent


class SETCompositionNetV2CandidateA(_SETCompositionNetV2CandidateBase):
    """Candidate A v2: dual visual branches plus the explicit intent encoder."""

    candidate_id = "candidate_a_dual_branch"

    def __init__(self, contract: SETCompositionNetV2Manifest | None = None):
        super().__init__(contract)
        self.full_frame_backbone = _MobileNetV3Backbone("large", 0.75, input_channels=3)
        self.subject_crop_backbone = _MobileNetV3Backbone("small", 0.50, input_channels=3)
        fusion_input = (
            self.full_frame_backbone.output_dim
            + self.subject_crop_backbone.output_dim
            + self.scalar_features.output_dim
            + INTENT_ENCODER_DIM
        )
        self.fusion = nn.Sequential(
            nn.Linear(fusion_input, self.fusion_dimension),
            nn.Hardswish(inplace=True),
        )
        self.embedding_projection = nn.Linear(
            self.fusion_dimension,
            self.contract.output_head_shapes[self.contract.embedding_name],
        )

    def forward(self, inputs: object = None, *args: object, **kwargs: object) -> "OrderedDict[str, Tensor]":  # noqa: F821
        values = self._coerce_v2_inputs(inputs, args, kwargs)
        full, crop, _mask, scalar, missing, intent = self._prepare_v2(values)
        fused = self.fusion(
            torch.cat(
                (
                    self.full_frame_backbone(full),
                    self.subject_crop_backbone(crop),
                    self.scalar_features(scalar, missing),
                    self.intent_encoder(intent),
                ),
                dim=1,
            )
        )
        return self._finish(fused)


class SETCompositionNetV2CandidateB(_SETCompositionNetV2CandidateBase):
    """Candidate B v2: ROI-mask ablation plus the explicit intent encoder."""

    candidate_id = "candidate_b_roi_conditioned_ablation"

    def __init__(self, contract: SETCompositionNetV2Manifest | None = None):
        super().__init__(contract)
        # One Small-0.50 backbone sees RGB and the binary ROI mask as four
        # channels.  The subject-crop tensor is still validated at the shared
        # trust boundary but is intentionally not consumed by this ablation.
        self.backbone = _MobileNetV3Backbone("small", 0.50, input_channels=4)
        fusion_input = self.backbone.output_dim + self.scalar_features.output_dim + INTENT_ENCODER_DIM
        self.fusion = nn.Sequential(
            nn.Linear(fusion_input, self.fusion_dimension),
            nn.Hardswish(inplace=True),
        )
        self.embedding_projection = nn.Linear(
            self.fusion_dimension,
            self.contract.output_head_shapes[self.contract.embedding_name],
        )

    def forward(self, inputs: object = None, *args: object, **kwargs: object) -> "OrderedDict[str, Tensor]":  # noqa: F821
        values = self._coerce_v2_inputs(inputs, args, kwargs)
        full, _crop, mask, scalar, missing, intent = self._prepare_v2(values)
        fused = self.fusion(
            torch.cat(
                (
                    self.backbone(torch.cat((full, mask), dim=1)),
                    self.scalar_features(scalar, missing),
                    self.intent_encoder(intent),
                ),
                dim=1,
            )
        )
        return self._finish(fused)


# Short aliases keep the trainer config readable without a model registry.
CandidateAv2 = SETCompositionNetV2CandidateA
CandidateBv2 = SETCompositionNetV2CandidateB


__all__ = [
    "CandidateAv2",
    "CandidateBv2",
    "INTENT_CONDITIONED_HEAD_ORDER",
    "INTENT_ENCODER_DIM",
    "INTENT_ORDER",
    "INTENT_STYLE_NAMES",
    "KNOWN_FLAG_INDEX",
    "KNOWN_FLAG_NAME",
    "SETCompositionNetV2CandidateA",
    "SETCompositionNetV2CandidateB",
    "SETCompositionNetV2Inputs",
    "SETCompositionNetV2Manifest",
    "V2_MANIFEST_PATH",
    "encode_intent",
    "intent_supervision_mask",
    "validate_intent_features",
]
