"""Small deterministic architecture check for M4-004/M4-005.

Run from the repository root with:

    python3 -m ml.camera_coach.models.check_candidates

The receipt is intentionally stdout-only; no weights, cache, or generated
artifact is written by this check.
"""

from __future__ import annotations

from hashlib import sha256
import json
from pathlib import Path
import struct
import sys

import torch

from .set_composition_net import (
    CandidateA,
    CandidateB,
    _InvertedResidual,
    _SqueezeExcitation,
    SETCompositionNetInputs,
    SETCompositionNetManifest,
    count_macs,
    count_parameters,
)


SEED = 20260905

# Independent admission expectations for the canonical MobileNetV3 schedules.
# These are intentionally not read back from the implementation table: a
# missing/reordered block or recursive channel scaling must fail this check.
_EXPECTED_LARGE_075 = (
    (16, 16, 16, 3, 1, False, "RE"),
    (16, 48, 24, 3, 2, False, "RE"),
    (24, 56, 24, 3, 1, False, "RE"),
    (24, 56, 32, 5, 2, True, "RE"),
    (32, 88, 32, 5, 1, True, "RE"),
    (32, 88, 32, 5, 1, True, "RE"),
    (32, 184, 64, 3, 2, False, "HS"),
    (64, 152, 64, 3, 1, False, "HS"),
    (64, 136, 64, 3, 1, False, "HS"),
    (64, 136, 64, 3, 1, False, "HS"),
    (64, 360, 88, 3, 1, True, "HS"),
    (88, 504, 88, 3, 1, True, "HS"),
    (88, 504, 120, 5, 2, True, "HS"),
    (120, 720, 120, 5, 1, True, "HS"),
    (120, 720, 120, 5, 1, True, "HS"),
)
_EXPECTED_SMALL_050 = (
    (8, 8, 8, 3, 2, True, "RE"),
    (8, 40, 16, 3, 2, False, "RE"),
    (16, 48, 16, 3, 1, False, "RE"),
    (16, 48, 24, 5, 2, True, "HS"),
    (24, 120, 24, 5, 1, True, "HS"),
    (24, 120, 24, 5, 1, True, "HS"),
    (24, 64, 24, 5, 1, True, "HS"),
    (24, 72, 24, 5, 1, True, "HS"),
    (24, 144, 48, 5, 2, True, "HS"),
    (48, 288, 48, 5, 1, True, "HS"),
    (48, 288, 48, 5, 1, True, "HS"),
)
_EXPECTED_LARGE_SE_SQUEEZE = (None, None, None, 16, 24, 24, None, None, None, None, 88, 128, 128, 184, 184)
_EXPECTED_SMALL_SE_SQUEEZE = (8, None, None, 16, 32, 32, 16, 24, 40, 72, 72)


def _tensor_hash(value: torch.Tensor) -> str:
    values = value.detach().to(device="cpu", dtype=torch.float32).contiguous().flatten().tolist()
    return sha256(struct.pack(f"<{len(values)}f", *values)).hexdigest()


def _make_inputs(contract: SETCompositionNetManifest, *, absent_roi: bool = False) -> SETCompositionNetInputs:
    full_h, full_w, full_c = contract.full_frame_shape
    crop_h, crop_w, crop_c = contract.subject_crop_shape
    mask_h, mask_w, mask_c = contract.roi_mask_shape
    full = torch.rand(full_h, full_w, full_c, dtype=torch.float32)
    crop = torch.rand(crop_h, crop_w, crop_c, dtype=torch.float32)
    if absent_roi:
        roi = torch.zeros(4, dtype=torch.float32)
        mask = torch.zeros(mask_h, mask_w, mask_c, dtype=torch.float32)
    else:
        roi = torch.tensor([0.25, 0.20, 0.40, 0.50], dtype=torch.float32)
        mask = torch.zeros(mask_h, mask_w, mask_c, dtype=torch.float32)
        left = int(roi[0].item() * mask_w)
        top = int(roi[1].item() * mask_h)
        right = int((roi[0] + roi[2]).item() * mask_w)
        bottom = int((roi[1] + roi[3]).item() * mask_h)
        mask[top:bottom, left:right, :] = 1.0
    scalar = torch.rand(contract.scalar_feature_count, dtype=torch.float32)
    feature_names = contract.raw["inputs"]["scalar_features"]["ordered_names"]
    feature_to_normalization = contract.raw["feature_normalization"]["feature_to_normalization"]
    for index, name in enumerate(feature_names):
        if feature_to_normalization[name] in {"signed_unit_interval", "angle_degrees_to_unit"}:
            scalar[index] = scalar[index] * 2.0 - 1.0
    scalar[feature_names.index("orientation_category")] = 0.0
    scalar[feature_names.index("lens_category")] = 0.5
    missing = torch.zeros(contract.scalar_feature_count, dtype=torch.float32)
    return SETCompositionNetInputs(full, crop, roi, mask, scalar, missing)


def _activation_code(module: torch.nn.Module) -> str:
    if isinstance(module, torch.nn.ReLU):
        return "RE"
    if isinstance(module, torch.nn.Hardswish):
        return "HS"
    raise AssertionError(f"unexpected MobileNetV3 activation: {type(module).__name__}")


def _assert_actual_backbone(
    backbone: torch.nn.Module,
    expected_schedule: tuple[tuple[int, int, int, int, int, bool, str], ...],
    expected_se_squeeze: tuple[int | None, ...],
    family: str,
    width_multiplier: float,
) -> None:
    assert backbone.family == family and backbone.width_multiplier == width_multiplier
    blocks = [module for module in backbone.features if isinstance(module, _InvertedResidual)]
    assert len(blocks) == len(expected_schedule)
    assert len(expected_se_squeeze) == len(expected_schedule)
    for block, expected, expected_squeeze in zip(blocks, expected_schedule, expected_se_squeeze):
        expected_input, expected_expanded, expected_output, expected_kernel, expected_stride, expected_se, expected_activation = expected
        children = list(block.block)
        depthwise = next(
            child for child in children
            if isinstance(child, torch.nn.Sequential)
            and isinstance(child[0], torch.nn.Conv2d)
            and child[0].groups == child[0].in_channels
        )
        depthwise_conv = depthwise[0]
        output_conv = children[-2]
        assert isinstance(output_conv, torch.nn.Conv2d)
        actual_input = depthwise_conv.in_channels
        if expected_expanded != expected_input:
            expansion = children[0]
            assert isinstance(expansion, torch.nn.Sequential)
            expansion_conv = expansion[0]
            assert isinstance(expansion_conv, torch.nn.Conv2d)
            assert expansion_conv.kernel_size == (1, 1)
            assert expansion_conv.in_channels == expected_input
            assert expansion_conv.out_channels == expected_expanded
            assert _activation_code(expansion[-1]) == expected_activation
            actual_input = expansion_conv.in_channels
        else:
            assert not (
                isinstance(children[0], torch.nn.Sequential)
                and isinstance(children[0][0], torch.nn.Conv2d)
                and children[0][0].groups == 1
            )
        assert (actual_input, depthwise_conv.in_channels, output_conv.out_channels) == (
            expected_input, expected_expanded, expected_output
        )
        assert output_conv.in_channels == depthwise_conv.out_channels == expected_expanded
        assert depthwise_conv.kernel_size == (expected_kernel, expected_kernel)
        assert depthwise_conv.stride == (expected_stride, expected_stride)
        assert depthwise_conv.groups == expected_expanded
        assert _activation_code(depthwise[-1]) == expected_activation
        actual_se = next((child for child in children if isinstance(child, _SqueezeExcitation)), None)
        assert (actual_se is not None) == expected_se
        if actual_se is not None:
            assert expected_squeeze is not None
            assert actual_se.reduce.in_channels == expected_expanded
            assert actual_se.reduce.out_channels == expected_squeeze
            assert actual_se.expand.in_channels == expected_squeeze
            assert actual_se.expand.out_channels == expected_expanded
            assert isinstance(actual_se.gate, torch.nn.Hardsigmoid)
        else:
            assert expected_squeeze is None
        actual_stride = depthwise_conv.stride[0]
        actual_residual = actual_stride == 1 and actual_input == output_conv.out_channels
        assert block.use_residual == actual_residual
        assert block.use_residual == (expected_stride == 1 and expected_input == expected_output)


def _assert_mobilenet_schedules(candidate_a: torch.nn.Module, candidate_b: torch.nn.Module) -> None:
    # Inspect actual Conv2d/Sequential modules, not the convenience schedule
    # metadata attached to the backbone.
    _assert_actual_backbone(
        candidate_a.full_frame_backbone,
        _EXPECTED_LARGE_075,
        _EXPECTED_LARGE_SE_SQUEEZE,
        "large",
        0.75,
    )
    _assert_actual_backbone(
        candidate_a.subject_crop_backbone,
        _EXPECTED_SMALL_050,
        _EXPECTED_SMALL_SE_SQUEEZE,
        "small",
        0.50,
    )
    _assert_actual_backbone(
        candidate_b.backbone,
        _EXPECTED_SMALL_050,
        _EXPECTED_SMALL_SE_SQUEEZE,
        "small",
        0.50,
    )


def _assert_shapes(outputs: dict[str, torch.Tensor], contract: SETCompositionNetManifest) -> None:
    assert tuple(outputs) == contract.output_head_names
    for name in contract.output_head_names:
        assert outputs[name].dtype == torch.float32
        assert tuple(outputs[name].shape) == (1, contract.output_head_shapes[name]), (name, outputs[name].shape)
        value_range = contract.output_head_specs[name].get("value_range")
        if value_range:
            assert bool(torch.all(outputs[name] >= value_range[0]))
            assert bool(torch.all(outputs[name] <= value_range[1]))


def _assert_deterministic(model: torch.nn.Module, inputs: SETCompositionNetInputs, contract: SETCompositionNetManifest) -> str:
    model.eval()
    with torch.no_grad():
        first = model(inputs)
        second = model(inputs)
    for name in contract.output_head_names:
        assert torch.equal(first[name], second[name]), f"non-deterministic head: {name}"
    _assert_shapes(first, contract)
    return sha256(b"".join(_tensor_hash(first[name]).encode() for name in contract.output_head_names)).hexdigest()


def _assert_absent_roi_is_deterministic(model: torch.nn.Module, inputs: SETCompositionNetInputs) -> None:
    stale_crop = torch.rand_like(inputs.subject_crop_rgb)
    zero_crop = torch.zeros_like(stale_crop)
    stale = SETCompositionNetInputs(
        inputs.full_frame_rgb,
        stale_crop,
        inputs.roi_normalized_xywh,
        inputs.roi_mask,
        inputs.scalar_features,
        inputs.missing_feature_mask,
    )
    zero = SETCompositionNetInputs(
        inputs.full_frame_rgb,
        zero_crop,
        inputs.roi_normalized_xywh,
        inputs.roi_mask,
        inputs.scalar_features,
        inputs.missing_feature_mask,
    )
    model.eval()
    with torch.no_grad():
        stale_output = model(stale)
        zero_output = model(zero)
    for name in stale_output:
        assert torch.equal(stale_output[name], zero_output[name]), f"absent ROI leaked into {name}"


def _assert_missing_mask_is_deterministic(model: torch.nn.Module, inputs: SETCompositionNetInputs) -> None:
    declared_missing = torch.zeros_like(inputs.missing_feature_mask)
    declared_missing[:4] = 1.0
    contaminated = inputs.scalar_features.clone()
    contaminated[:4] = 0.75
    clean = contaminated.clone()
    clean[:4] = 0.0
    masked_contaminated = SETCompositionNetInputs(
        inputs.full_frame_rgb,
        inputs.subject_crop_rgb,
        inputs.roi_normalized_xywh,
        inputs.roi_mask,
        contaminated,
        declared_missing,
    )
    masked_clean = SETCompositionNetInputs(
        inputs.full_frame_rgb,
        inputs.subject_crop_rgb,
        inputs.roi_normalized_xywh,
        inputs.roi_mask,
        clean,
        declared_missing,
    )
    model.eval()
    with torch.no_grad():
        contaminated_output = model(masked_contaminated)
        clean_output = model(masked_clean)
    for name in contaminated_output:
        assert torch.equal(contaminated_output[name], clean_output[name]), f"missing mask leaked into {name}"


def _assert_gradients(model: torch.nn.Module, inputs: SETCompositionNetInputs) -> None:
    model.eval()
    model.zero_grad(set_to_none=True)
    output = model(inputs)
    loss = sum(value.square().mean() for value in output.values())
    loss.backward()
    gradients = [parameter.grad for parameter in model.parameters() if parameter.requires_grad]
    assert gradients and all(gradient is not None and bool(torch.isfinite(gradient).all()) for gradient in gradients)


def main() -> int:
    torch.manual_seed(SEED)
    torch.set_num_threads(1)
    torch.use_deterministic_algorithms(True)
    contract = SETCompositionNetManifest.load()
    inputs = _make_inputs(contract)
    absent_inputs = _make_inputs(contract, absent_roi=True)

    torch.manual_seed(SEED)
    candidate_a = CandidateA(contract).eval()
    torch.manual_seed(SEED)
    candidate_b = CandidateB(contract).eval()

    _assert_mobilenet_schedules(candidate_a, candidate_b)
    hash_a = _assert_deterministic(candidate_a, inputs, contract)
    hash_b = _assert_deterministic(candidate_b, inputs, contract)
    _assert_absent_roi_is_deterministic(candidate_a, absent_inputs)
    _assert_absent_roi_is_deterministic(candidate_b, absent_inputs)
    _assert_missing_mask_is_deterministic(candidate_a, inputs)
    _assert_missing_mask_is_deterministic(candidate_b, inputs)
    _assert_gradients(candidate_a, inputs)
    _assert_gradients(candidate_b, inputs)

    params_a = count_parameters(candidate_a)
    params_b = count_parameters(candidate_b)
    macs_a = count_macs(candidate_a, inputs)
    macs_b = count_macs(candidate_b, inputs)
    ratio = macs_b / macs_a
    assert macs_a > macs_b and ratio <= 0.70, (macs_a, macs_b, ratio)
    receipt = {
        "status": "pass",
        "torch": torch.__version__,
        "python": sys.version.split()[0],
        "seed": SEED,
        "contract": {
            "path": "ml/camera_coach/contracts/set_composition_net_v1.json",
            "version": contract.raw["contract_version"],
            "head_order": list(contract.output_head_names),
            "head_shapes": contract.output_head_shapes,
        },
        "candidate_a": {
            "id": candidate_a.candidate_id,
            "parameters": params_a,
            "macs_conv_linear": macs_a,
            "output_hash": hash_a,
        },
        "candidate_b": {
            "id": candidate_b.candidate_id,
            "parameters": params_b,
            "macs_conv_linear": macs_b,
            "output_hash": hash_b,
        },
        "candidate_b_to_a_macs_ratio": ratio,
        "checks": [
            "canonical MobileNetV3 Large-0.75 (15) and Small-0.50 (11) schedules",
            "all nine manifest-driven output heads and shapes",
            "repeated forward equality",
            "absent ROI/crop deterministic zero gate",
            "declared missing scalar deterministic zero fill",
            "finite gradient traversal",
            "manifest lockstep and B <= 70% of A MACs",
        ],
        "limitations": [
            "synthetic random inputs only; no data, training, calibration, or quality claim",
            "MAC count covers Conv2d and Linear multiply-accumulates, not device latency",
            "no CoreML export or iOS provider enablement",
        ],
    }
    print(json.dumps(receipt, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
