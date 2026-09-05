"""Disabled SETCompositionNet-v1 candidate architectures.

This module deliberately stops at architecture contracts.  It does not train,
select, export, or enable a model in the iOS runtime.  The manifest under
``ml/camera_coach/contracts`` is the only source of tensor and output-head
shapes; changing it without changing this v1 reader fails loudly.
"""

from __future__ import annotations

from collections import OrderedDict
from dataclasses import dataclass
import json
from pathlib import Path
from typing import Mapping, Sequence

import torch
from torch import Tensor, nn


FUSION_DIMENSION = 256

# These values are admission guards only.  Layers are still built from the
# parsed manifest below, so a valid v1 manifest cannot silently change the
# model's output order or tensor dimensions.
_FROZEN_INPUT_SHAPES = {
    "full_frame_rgb": (320, 320, 3),
    "subject_crop_rgb": (192, 192, 3),
    "roi_normalized_xywh": (4,),
    "roi_mask": (320, 320, 1),
    "scalar_features": (40,),
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


class ContractError(ValueError):
    """Raised when the frozen v1 manifest or an input tensor is not trusted."""


@dataclass(frozen=True)
class SETCompositionNetManifest:
    """The small parsed view of the frozen machine-readable v1 manifest."""

    raw: dict
    input_shapes: dict[str, tuple[int, ...]]
    output_head_names: tuple[str, ...]
    output_head_shapes: dict[str, int]
    output_head_specs: dict[str, dict]
    embedding_name: str

    @classmethod
    def load(cls, path: str | Path | None = None) -> "SETCompositionNetManifest":
        manifest_path = Path(path) if path else (
            Path(__file__).resolve().parents[1] / "contracts" / "set_composition_net_v1.json"
        )
        try:
            with manifest_path.open(encoding="utf-8") as stream:
                raw = json.load(stream)
        except (OSError, json.JSONDecodeError) as exc:
            raise ContractError(f"cannot load SETCompositionNet-v1 manifest: {manifest_path}") from exc
        if not isinstance(raw, dict):
            raise ContractError("SETCompositionNet-v1 manifest must be a JSON object")
        return cls._from_raw(raw, manifest_path)

    @classmethod
    def _from_raw(cls, raw: dict, path: Path) -> "SETCompositionNetManifest":
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
            "outputs",
        }
        if set(raw) != required_top_level:
            raise ContractError(f"manifest top-level keys drifted in {path}")
        expected_versions = {
            "contract_id": "SETCompositionNet",
            "contract_version": "setcompositionnet.v1",
            "input_contract_version": "setcompositionnet.input.v1",
            "preprocessing_version": "setcompositionnet.preprocessing.v1",
            "feature_version": "setcompositionnet.features.v1",
            "output_contract_version": "setcompositionnet.output.v1",
        }
        for key, expected in expected_versions.items():
            if raw.get(key) != expected:
                raise ContractError(f"manifest {key} is not the frozen v1 value")
        if raw.get("tensor_layout") != "HWC":
            raise ContractError("SETCompositionNet-v1 requires HWC logical tensors")

        inputs = raw.get("inputs")
        if not isinstance(inputs, dict):
            raise ContractError("manifest inputs must be an object")
        expected_inputs = {
            "full_frame_rgb",
            "subject_crop_rgb",
            "roi_normalized_xywh",
            "roi_mask",
            "scalar_features",
        }
        if set(inputs) != expected_inputs:
            raise ContractError("manifest input names drifted from SETCompositionNet-v1")
        input_shapes: dict[str, tuple[int, ...]] = {}
        for name, node in inputs.items():
            if not isinstance(node, dict) or node.get("dtype") != "float32":
                raise ContractError(f"manifest input {name} must be float32")
            shape = node.get("shape")
            if not isinstance(shape, list) or not shape or not all(
                type(value) is int and value > 0 for value in shape
            ):
                raise ContractError(f"manifest input {name} has an invalid shape")
            input_shapes[name] = tuple(shape)
        if input_shapes != _FROZEN_INPUT_SHAPES:
            raise ContractError("manifest input tensor shapes are not frozen SETCompositionNet-v1 values")
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

        outputs = raw.get("outputs")
        if not isinstance(outputs, dict) or set(outputs) != {"head_order", "heads", "forbidden_outputs"}:
            raise ContractError("manifest output contract is not closed")
        head_order = outputs.get("head_order")
        heads = outputs.get("heads")
        if not isinstance(head_order, list) or not head_order or not isinstance(heads, list):
            raise ContractError("manifest output heads are malformed")
        if tuple(head_order) != _FROZEN_OUTPUT_HEAD_ORDER or len(heads) != len(head_order):
            raise ContractError("manifest output head order is not the frozen SETCompositionNet-v1 order")
        if outputs.get("forbidden_outputs") != ["generated_text", "arbitrary_object_name"]:
            raise ContractError("manifest forbidden output catalog drifted")
        head_shapes: dict[str, int] = {}
        head_specs: dict[str, dict] = {}
        for expected_name, node in zip(head_order, heads):
            if not isinstance(expected_name, str) or not isinstance(node, dict):
                raise ContractError("manifest output head entry is malformed")
            if node.get("name") != expected_name or node.get("dtype") != "float32":
                raise ContractError(f"manifest output head {expected_name!r} is out of order")
            shape = node.get("shape")
            if not isinstance(shape, list) or len(shape) != 1 or type(shape[0]) is not int or shape[0] < 1:
                raise ContractError(f"manifest output head {expected_name!r} has an invalid shape")
            head_shapes[expected_name] = shape[0]
            head_specs[expected_name] = node
        if head_shapes != _FROZEN_OUTPUT_HEAD_SHAPES:
            raise ContractError("manifest output head dimensions are not frozen SETCompositionNet-v1 values")
        if "embedding" not in head_shapes or head_shapes["embedding"] != 128:
            raise ContractError("SETCompositionNet-v1 embedding must remain 128D")
        return cls(
            raw=raw,
            input_shapes=input_shapes,
            output_head_names=tuple(head_order),
            output_head_shapes=head_shapes,
            output_head_specs=head_specs,
            embedding_name="embedding",
        )

    @property
    def scalar_feature_count(self) -> int:
        return self.input_shapes["scalar_features"][0]

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
class SETCompositionNetInputs:
    """Logical HWC tensors at the model trust boundary.

    A single unbatched HWC tensor or a batched BHWC tensor is canonical.  The
    implementation also accepts BCHW for an adapter-free PyTorch caller, but
    never changes values or silently casts dtype.
    """

    full_frame_rgb: Tensor
    subject_crop_rgb: Tensor
    roi_normalized_xywh: Tensor
    roi_mask: Tensor
    scalar_features: Tensor
    missing_feature_mask: Tensor

    @classmethod
    def from_mapping(cls, values: Mapping[str, Tensor]) -> "SETCompositionNetInputs":
        expected = {
            "full_frame_rgb",
            "subject_crop_rgb",
            "roi_normalized_xywh",
            "roi_mask",
            "scalar_features",
            "missing_feature_mask",
        }
        if set(values) != expected:
            missing = sorted(expected.difference(values))
            extra = sorted(set(values).difference(expected))
            raise ContractError(f"model inputs differ from frozen contract; missing={missing}, extra={extra}")
        return cls(**{key: values[key] for key in expected})


def _make_divisible(value: float, divisor: int = 8) -> int:
    rounded = max(divisor, int(value + divisor / 2) // divisor * divisor)
    if rounded < 0.9 * value:
        rounded += divisor
    return rounded


class _ConvBNActivation(nn.Sequential):
    def __init__(self, in_channels: int, out_channels: int, kernel: int, stride: int, activation: str):
        layers: list[nn.Module] = [
            nn.Conv2d(
                in_channels,
                out_channels,
                kernel_size=kernel,
                stride=stride,
                padding=(kernel - 1) // 2,
                bias=False,
            ),
            nn.BatchNorm2d(out_channels),
        ]
        layers.append(nn.ReLU(inplace=True) if activation == "RE" else nn.Hardswish(inplace=True))
        super().__init__(*layers)


class _SqueezeExcitation(nn.Module):
    def __init__(self, input_channels: int, feature_channels: int, squeeze_factor: int = 4):
        super().__init__()
        squeeze_channels = _make_divisible(input_channels / squeeze_factor, 8)
        self.input_channels = input_channels
        self.feature_channels = feature_channels
        self.squeeze_channels = squeeze_channels
        self.reduce = nn.Conv2d(feature_channels, squeeze_channels, kernel_size=1)
        self.expand = nn.Conv2d(squeeze_channels, feature_channels, kernel_size=1)

    def forward(self, x: Tensor) -> Tensor:
        scale = x.mean(dim=(2, 3), keepdim=True)
        scale = torch.relu(self.reduce(scale))
        # MobileNetV3's squeeze-excitation gate uses hard-sigmoid.
        scale = torch.clamp((self.expand(scale) + 3.0) / 6.0, 0.0, 1.0)
        return x * scale


class _InvertedResidual(nn.Module):
    def __init__(
        self,
        in_channels: int,
        expanded_channels: int,
        out_channels: int,
        kernel: int,
        stride: int,
        use_se: bool,
        activation: str,
    ):
        super().__init__()
        self.use_residual = stride == 1 and in_channels == out_channels
        layers: list[nn.Module] = []
        if expanded_channels != in_channels:
            layers.append(_ConvBNActivation(in_channels, expanded_channels, 1, 1, activation))
        layers.append(nn.Sequential(
            nn.Conv2d(
                expanded_channels,
                expanded_channels,
                kernel_size=kernel,
                stride=stride,
                padding=(kernel - 1) // 2,
                groups=expanded_channels,
                bias=False,
            ),
            nn.BatchNorm2d(expanded_channels),
            nn.ReLU(inplace=True) if activation == "RE" else nn.Hardswish(inplace=True),
        ))
        if use_se:
            # SET's frozen candidate specification derives the SE bottleneck
            # from the block input channels, never the expanded width.
            layers.append(_SqueezeExcitation(in_channels, expanded_channels))
        layers.extend(
            [
                nn.Conv2d(expanded_channels, out_channels, kernel_size=1, bias=False),
                nn.BatchNorm2d(out_channels),
            ]
        )
        self.block = nn.Sequential(*layers)

    def forward(self, x: Tensor) -> Tensor:
        result = self.block(x)
        return x + result if self.use_residual else result


_LARGE_CONFIG = (
    # kernel, expansion, raw output, squeeze-excitation, activation, stride
    (3, 1.0, 16, False, "RE", 1),
    (3, 4.0, 24, False, "RE", 2),
    (3, 3.0, 24, False, "RE", 1),
    (5, 3.0, 40, True, "RE", 2),
    (5, 3.0, 40, True, "RE", 1),
    (5, 3.0, 40, True, "RE", 1),
    (3, 6.0, 80, False, "HS", 2),
    (3, 2.5, 80, False, "HS", 1),
    (3, 2.5, 80, False, "HS", 1),
    (3, 2.5, 80, False, "HS", 1),
    (3, 6.0, 112, True, "HS", 1),
    (3, 6.0, 112, True, "HS", 1),
    (5, 6.0, 160, True, "HS", 2),
    (5, 6.0, 160, True, "HS", 1),
    (5, 6.0, 160, True, "HS", 1),
)

_SMALL_CONFIG = (
    # kernel, expansion, raw output, squeeze-excitation, activation, stride
    (3, 1.0, 16, True, "RE", 2),
    (3, 4.5, 24, False, "RE", 2),
    (3, 3.67, 24, False, "RE", 1),
    (5, 4.0, 40, True, "HS", 2),
    (5, 6.0, 40, True, "HS", 1),
    (5, 6.0, 40, True, "HS", 1),
    (5, 3.0, 48, True, "HS", 1),
    (5, 3.0, 48, True, "HS", 1),
    (5, 6.0, 96, True, "HS", 2),
    (5, 6.0, 96, True, "HS", 1),
    (5, 6.0, 96, True, "HS", 1),
)


class _MobileNetV3Backbone(nn.Module):
    """Minimal native-op MobileNetV3 feature extractor, no torchvision."""

    def __init__(self, family: str, width_multiplier: float, input_channels: int = 3):
        super().__init__()
        if family not in {"large", "small"}:
            raise ValueError(f"unsupported MobileNetV3 family: {family}")
        if width_multiplier <= 0:
            raise ValueError("width_multiplier must be positive")
        model_input_channels = input_channels
        config = _LARGE_CONFIG if family == "large" else _SMALL_CONFIG
        stem_channels = _make_divisible(16 * width_multiplier)
        blocks: list[nn.Module] = []
        raw_input = 16
        current = stem_channels
        block_schedule: list[tuple[int, int, int, int, int, bool, str]] = []
        for kernel, expansion, raw_out, use_se, activation, stride in config:
            block_input_channels = _make_divisible(raw_input * width_multiplier)
            out_channels = _make_divisible(raw_out * width_multiplier)
            expanded = _make_divisible(raw_input * expansion * width_multiplier)
            if block_input_channels != current:
                raise ContractError(
                    f"{family} MobileNetV3 schedule lost channel continuity at raw input {raw_input}"
                )
            blocks.append(
                _InvertedResidual(
                    block_input_channels,
                    expanded,
                    out_channels,
                    kernel,
                    stride,
                    use_se,
                    activation,
                )
            )
            current = out_channels
            block_schedule.append((block_input_channels, expanded, out_channels, kernel, stride, use_se, activation))
            raw_input = raw_out
        final_channels = _make_divisible((960 if family == "large" else 576) * width_multiplier)
        self.family = family
        self.width_multiplier = width_multiplier
        self.input_channels = model_input_channels
        self.output_dim = final_channels
        self.block_schedule = tuple(block_schedule)
        self.features = nn.Sequential(
            _ConvBNActivation(model_input_channels, stem_channels, 3, 2, "HS"),
            *blocks,
            nn.Conv2d(current, final_channels, kernel_size=1, bias=False),
            nn.BatchNorm2d(final_channels),
            nn.Hardswish(inplace=True),
        )

    def forward(self, x: Tensor) -> Tensor:
        return self.features(x).mean(dim=(2, 3))


class _ScalarFeatureMLP(nn.Module):
    def __init__(self, feature_count: int):
        super().__init__()
        self.input_dim = feature_count * 2
        self.output_dim = 64
        self.layers = nn.Sequential(
            nn.Linear(self.input_dim, 128),
            nn.Hardswish(inplace=True),
            nn.Linear(128, self.output_dim),
            nn.Hardswish(inplace=True),
        )

    def forward(self, scalar_features: Tensor, missing_feature_mask: Tensor) -> Tensor:
        # The missing mask is both an input signal and a deterministic guard:
        # malformed non-zero values cannot leak through a declared missing slot.
        filled = torch.where(missing_feature_mask > 0.5, torch.zeros_like(scalar_features), scalar_features)
        return self.layers(torch.cat((filled, missing_feature_mask), dim=1))


def _as_bchw(value: Tensor, expected_hwc: Sequence[int], name: str) -> Tensor:
    if value.dtype != torch.float32:
        raise ContractError(f"{name} must be torch.float32, got {value.dtype}")
    height, width, channels = expected_hwc
    if value.ndim == 3:
        if tuple(value.shape) == (height, width, channels):
            value = value.unsqueeze(0).permute(0, 3, 1, 2)
        elif tuple(value.shape) == (channels, height, width):
            value = value.unsqueeze(0)
        else:
            raise ContractError(f"{name} shape must be HWC or CHW {tuple(expected_hwc)}, got {tuple(value.shape)}")
    elif value.ndim == 4:
        if tuple(value.shape[1:]) == (height, width, channels):
            value = value.permute(0, 3, 1, 2)
        elif tuple(value.shape[1:]) != (channels, height, width):
            raise ContractError(f"{name} shape must be BHWC or BCHW {tuple(expected_hwc)}, got {tuple(value.shape)}")
    else:
        raise ContractError(f"{name} must have rank 3 or 4, got rank {value.ndim}")
    if not torch.isfinite(value).all():
        raise ContractError(f"{name} must contain only finite values")
    if torch.any(value < 0.0) or torch.any(value > 1.0):
        raise ContractError(f"{name} values must remain within [0, 1]")
    return value.contiguous()


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


def _prepare_inputs(
    inputs: SETCompositionNetInputs,
    contract: SETCompositionNetManifest,
) -> tuple[Tensor, Tensor, Tensor, Tensor, Tensor, Tensor, Tensor]:
    full = _as_bchw(inputs.full_frame_rgb, contract.full_frame_shape, "full_frame_rgb")
    crop = _as_bchw(inputs.subject_crop_rgb, contract.subject_crop_shape, "subject_crop_rgb")
    mask = _as_bchw(inputs.roi_mask, contract.roi_mask_shape, "roi_mask")
    roi = _as_batch_vector(inputs.roi_normalized_xywh, 4, "roi_normalized_xywh")
    scalar = _as_batch_vector(inputs.scalar_features, contract.scalar_feature_count, "scalar_features")
    missing = _as_batch_vector(inputs.missing_feature_mask, contract.scalar_feature_count, "missing_feature_mask")
    if full.shape[0] != crop.shape[0] or full.shape[0] != mask.shape[0] or full.shape[0] != roi.shape[0] \
            or full.shape[0] != scalar.shape[0] or full.shape[0] != missing.shape[0]:
        raise ContractError("all SETCompositionNet-v1 tensors must share the batch size")
    if torch.any(roi < 0.0) or torch.any(roi > 1.0):
        raise ContractError("roi_normalized_xywh values must remain within [0, 1]")
    has_roi = roi.abs().sum(dim=1) > 0.0
    if torch.any(has_roi & ((roi[:, 2] <= 0.0) | (roi[:, 3] <= 0.0))):
        raise ContractError("present ROI must have positive width and height")
    if torch.any(has_roi & ((roi[:, 0] + roi[:, 2] > 1.0) | (roi[:, 1] + roi[:, 3] > 1.0))):
        raise ContractError("present ROI must remain within the normalized frame")
    if torch.any(missing < 0.0) or torch.any(missing > 1.0):
        raise ContractError("missing_feature_mask values must remain within [0, 1]")
    if torch.any((missing != 0.0) & (missing != 1.0)):
        raise ContractError("missing_feature_mask values must be exactly 0 or 1")
    if torch.any((mask != 0.0) & (mask != 1.0)):
        raise ContractError("roi_mask values must be exactly 0 or 1")
    if torch.any(~has_roi & (mask.abs().sum(dim=(1, 2, 3)) > 0.0)):
        raise ContractError("an absent ROI must carry a zero ROI mask")
    if torch.any(scalar < -1.0) or torch.any(scalar > 1.0):
        raise ContractError("scalar_features must remain in the normalized [-1, 1] envelope")
    feature_names = contract.raw["inputs"]["scalar_features"]["ordered_names"]
    feature_to_normalization = contract.raw["feature_normalization"]["feature_to_normalization"]
    normalization_specs = contract.raw["feature_normalization"]
    categorical_values = {
        "orientation_category": contract.raw["categorical_features"]["orientation_category"]["allowed_normalized_values"],
        "lens_category": contract.raw["categorical_features"]["lens_category"]["allowed_normalized_values"],
    }
    for index, name in enumerate(feature_names):
        lower, upper = normalization_specs[feature_to_normalization[name]]["value_range"]
        values = scalar[:, index]
        if torch.any(values < lower) or torch.any(values > upper):
            raise ContractError(f"scalar feature {name} is outside its manifest normalization range")
        if name in categorical_values:
            allowed = torch.tensor(categorical_values[name], dtype=scalar.dtype, device=scalar.device)
            if torch.any((values.unsqueeze(1) - allowed.unsqueeze(0)).abs().amin(dim=1) > 0.000001):
                raise ContractError(f"scalar categorical feature {name} is not in its manifest catalog")
    # Make absence deterministic even when an upstream adapter supplied a
    # stale crop.  This does not replace the frozen preprocessor's zero-fill;
    # it protects both candidate branches at their trust boundary.
    crop = crop * has_roi.to(dtype=crop.dtype).view(-1, 1, 1, 1)
    mask = mask * has_roi.to(dtype=mask.dtype).view(-1, 1, 1, 1)
    return full, crop, roi, mask, scalar, missing, has_roi


class _SETCompositionNetCandidateBase(nn.Module):
    def __init__(self, contract: SETCompositionNetManifest | None = None):
        super().__init__()
        self.contract = contract or SETCompositionNetManifest.load()
        self.architecture_id = "SETCompositionNet-v1"
        self.fusion_dimension = FUSION_DIMENSION
        self.scalar_features = _ScalarFeatureMLP(self.contract.scalar_feature_count)
        self.heads = nn.ModuleDict(
            {
                name: nn.Linear(self.fusion_dimension, self.contract.output_head_shapes[name])
                for name in self.contract.output_head_names
                if name != self.contract.embedding_name
            }
        )

    def _coerce_inputs(self, inputs: object, args: tuple[object, ...], kwargs: dict[str, object]) -> SETCompositionNetInputs:
        if isinstance(inputs, SETCompositionNetInputs):
            if args or kwargs:
                raise TypeError("do not combine SETCompositionNetInputs with extra model arguments")
            return inputs
        if isinstance(inputs, Mapping):
            if args or kwargs:
                raise TypeError("do not combine input mapping with extra model arguments")
            return SETCompositionNetInputs.from_mapping(inputs)
        if isinstance(inputs, Tensor):
            values = (inputs, *args)
            if kwargs or len(values) != 6:
                raise TypeError(
                    "tensor form is model(full_frame_rgb, subject_crop_rgb, roi_normalized_xywh, "
                    "roi_mask, scalar_features, missing_feature_mask)"
                )
            return SETCompositionNetInputs(*values)  # type: ignore[arg-type]
        if inputs is None and not args:
            expected = {
                "full_frame_rgb",
                "subject_crop_rgb",
                "roi_normalized_xywh",
                "roi_mask",
                "scalar_features",
                "missing_feature_mask",
            }
            if set(kwargs) != expected:
                raise TypeError(f"keyword model inputs must be exactly {sorted(expected)}")
            return SETCompositionNetInputs(**kwargs)  # type: ignore[arg-type]
        raise TypeError("model input must be SETCompositionNetInputs, a mapping, or six tensors")

    def _render_heads(self, fusion: Tensor) -> "OrderedDict[str, Tensor]":
        outputs: "OrderedDict[str, Tensor]" = OrderedDict()
        for name in self.contract.output_head_names:
            if name == self.contract.embedding_name:
                outputs[name] = self.embedding_projection(fusion)
                continue
            values = self.heads[name](fusion)
            value_range = self.contract.output_head_specs[name].get("value_range")
            if value_range == [0.0, 1.0]:
                values = torch.sigmoid(values)
            elif value_range == [-1.0, 1.0]:
                values = torch.tanh(values)
            outputs[name] = values
        if tuple(outputs) != self.contract.output_head_names:
            raise ContractError("candidate output order no longer matches frozen manifest")
        return outputs

    def _finish(self, fusion: Tensor) -> "OrderedDict[str, Tensor]":
        return self._render_heads(fusion)


class SETCompositionNetCandidateA(_SETCompositionNetCandidateBase):
    """Candidate A: dual visual branches with full-frame and subject crop."""

    candidate_id = "candidate_a_dual_branch"

    def __init__(self, contract: SETCompositionNetManifest | None = None):
        super().__init__(contract)
        self.full_frame_backbone = _MobileNetV3Backbone("large", 0.75, input_channels=3)
        self.subject_crop_backbone = _MobileNetV3Backbone("small", 0.50, input_channels=3)
        fusion_input = (
            self.full_frame_backbone.output_dim
            + self.subject_crop_backbone.output_dim
            + self.scalar_features.output_dim
        )
        self.fusion = nn.Sequential(
            nn.Linear(fusion_input, self.fusion_dimension),
            nn.Hardswish(inplace=True),
        )
        self.embedding_projection = nn.Linear(
            self.fusion_dimension,
            self.contract.output_head_shapes[self.contract.embedding_name],
        )

    def forward(self, inputs: object = None, *args: object, **kwargs: object) -> "OrderedDict[str, Tensor]":
        values = self._coerce_inputs(inputs, args, kwargs)
        full, crop, _roi, _mask, scalar, missing, _has_roi = _prepare_inputs(values, self.contract)
        fused = self.fusion(
            torch.cat(
                (
                    self.full_frame_backbone(full),
                    self.subject_crop_backbone(crop),
                    self.scalar_features(scalar, missing),
                ),
                dim=1,
            )
        )
        return self._finish(fused)


class SETCompositionNetCandidateB(_SETCompositionNetCandidateBase):
    """Candidate B: lower-complexity full-frame + ROI-mask ablation."""

    candidate_id = "candidate_b_roi_conditioned_ablation"

    def __init__(self, contract: SETCompositionNetManifest | None = None):
        super().__init__(contract)
        # One Small-0.50 backbone sees RGB and the binary ROI mask as four
        # channels.  The subject-crop tensor remains validated at the common
        # contract boundary but is intentionally not consumed by this ablation.
        self.backbone = _MobileNetV3Backbone("small", 0.50, input_channels=4)
        fusion_input = self.backbone.output_dim + self.scalar_features.output_dim
        self.fusion = nn.Sequential(
            nn.Linear(fusion_input, self.fusion_dimension),
            nn.Hardswish(inplace=True),
        )
        self.embedding_projection = nn.Linear(
            self.fusion_dimension,
            self.contract.output_head_shapes[self.contract.embedding_name],
        )

    def forward(self, inputs: object = None, *args: object, **kwargs: object) -> "OrderedDict[str, Tensor]":
        values = self._coerce_inputs(inputs, args, kwargs)
        full, _crop, _roi, mask, scalar, missing, _has_roi = _prepare_inputs(values, self.contract)
        fused = self.fusion(
            torch.cat((self.backbone(torch.cat((full, mask), dim=1)), self.scalar_features(scalar, missing)), dim=1)
        )
        return self._finish(fused)


# Short aliases keep evaluation scripts readable without introducing another
# abstraction or a production model registry.
CandidateA = SETCompositionNetCandidateA
CandidateB = SETCompositionNetCandidateB


def count_parameters(model: nn.Module) -> int:
    """Count trainable and frozen parameters without buffers."""

    return sum(parameter.numel() for parameter in model.parameters())


def count_macs(model: nn.Module, inputs: SETCompositionNetInputs) -> int:
    """Count Conv2d/Linear multiply-accumulates for one deterministic forward.

    BatchNorm, activations, pooling, additions, and memory movement are not
    counted.  This is intentionally a comparable architecture counter, not a
    device latency estimate.
    """

    total = 0
    hooks: list[torch.utils.hooks.RemovableHandle] = []

    def conv_hook(module: nn.Conv2d, _args: tuple[Tensor, ...], output: Tensor) -> None:
        nonlocal total
        output_elements = output.numel()
        kernel_ops = module.kernel_size[0] * module.kernel_size[1] * (module.in_channels // module.groups)
        total += output_elements * kernel_ops

    def linear_hook(module: nn.Linear, _args: tuple[Tensor, ...], output: Tensor) -> None:
        nonlocal total
        total += output.numel() * module.in_features

    for module in model.modules():
        if isinstance(module, nn.Conv2d):
            hooks.append(module.register_forward_hook(conv_hook))
        elif isinstance(module, nn.Linear):
            hooks.append(module.register_forward_hook(linear_hook))
    was_training = model.training
    model.eval()
    try:
        with torch.no_grad():
            model(inputs)
    finally:
        for hook in hooks:
            hook.remove()
        model.train(was_training)
    return total


__all__ = [
    "CandidateA",
    "CandidateB",
    "ContractError",
    "SETCompositionNetCandidateA",
    "SETCompositionNetCandidateB",
    "SETCompositionNetInputs",
    "SETCompositionNetManifest",
    "count_macs",
    "count_parameters",
]
