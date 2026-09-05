"""Small deterministic architecture check for M4-004/M4-005.

Run from the repository root with:

    python3 -m ml.camera_coach.models.check_candidates

The receipt is intentionally stdout-only; no weights, cache, or generated
artifact is written by this check.
"""

from __future__ import annotations

from collections.abc import Callable
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
_EXPECTED_BATCH_NORM_EPS = 0.001
_EXPECTED_BATCH_NORM_MOMENTUM = 0.01

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


def _assert_conv_bn_activation(
    module: torch.nn.Module,
    expected_input: int,
    expected_output: int,
    expected_kernel: int,
    expected_stride: int,
    expected_activation: str,
    expected_groups: int = 1,
) -> None:
    assert isinstance(module, torch.nn.Sequential)
    assert len(module) == 3
    conv, batch_norm, activation = module
    assert isinstance(conv, torch.nn.Conv2d)
    assert (conv.in_channels, conv.out_channels) == (expected_input, expected_output)
    assert conv.kernel_size == (expected_kernel, expected_kernel)
    assert conv.stride == (expected_stride, expected_stride)
    assert conv.groups == expected_groups
    _assert_batch_norm(batch_norm, expected_output)
    assert _activation_code(activation) == expected_activation


def _assert_batch_norm(module: torch.nn.Module, expected_features: int) -> None:
    assert isinstance(module, torch.nn.BatchNorm2d)
    assert module.num_features == expected_features
    assert module.eps == _EXPECTED_BATCH_NORM_EPS
    assert module.momentum == _EXPECTED_BATCH_NORM_MOMENTUM


def _assert_projection_conv(module: torch.nn.Module, expected_input: int, expected_output: int) -> None:
    assert isinstance(module, torch.nn.Conv2d)
    assert (module.in_channels, module.out_channels) == (expected_input, expected_output)
    assert module.kernel_size == (1, 1)
    assert module.stride == (1, 1)
    assert module.groups == 1
    assert module.padding == (0, 0)
    assert module.bias is None


def _assert_actual_backbone(
    backbone: torch.nn.Module,
    expected_schedule: tuple[tuple[int, int, int, int, int, bool, str], ...],
    expected_se_squeeze: tuple[int | None, ...],
    label: str,
    expected_stem_input: int,
    expected_stem_output: int,
    expected_final_input: int,
    expected_final_output: int,
) -> None:
    features = list(backbone.features)
    assert len(features) == len(expected_schedule) + 4, label
    _assert_conv_bn_activation(features[0], expected_stem_input, expected_stem_output, 3, 2, "HS")
    final_conv, final_batch_norm, final_activation = features[-3:]
    assert isinstance(final_conv, torch.nn.Conv2d)
    assert (final_conv.in_channels, final_conv.out_channels) == (expected_final_input, expected_final_output)
    assert final_conv.kernel_size == (1, 1)
    assert final_conv.stride == (1, 1)
    assert final_conv.groups == 1
    _assert_batch_norm(final_batch_norm, expected_final_output)
    assert _activation_code(final_activation) == "HS"
    blocks = features[1:-3]
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
        _assert_conv_bn_activation(
            depthwise,
            expected_expanded,
            expected_expanded,
            expected_kernel,
            expected_stride,
            expected_activation,
            expected_groups=expected_expanded,
        )
        output_conv = children[-2]
        _assert_projection_conv(output_conv, expected_expanded, expected_output)
        assert len(children) >= 3
        _assert_batch_norm(children[-1], expected_output)
        actual_input = depthwise_conv.in_channels
        if expected_expanded != expected_input:
            expansion = children[0]
            _assert_conv_bn_activation(expansion, expected_input, expected_expanded, 1, 1, expected_activation)
            expansion_conv = expansion[0]
            actual_input = expansion_conv.in_channels
        else:
            assert children[0] is depthwise
            assert not (
                isinstance(children[0], torch.nn.Sequential)
                and isinstance(children[0][0], torch.nn.Conv2d)
                and children[0][0].groups == 1
            )
        assert (actual_input, depthwise_conv.in_channels, output_conv.out_channels) == (
            expected_input, expected_expanded, expected_output
        )
        assert output_conv.in_channels == depthwise_conv.out_channels == expected_expanded
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
        3,
        16,
        120,
        720,
    )
    _assert_actual_backbone(
        candidate_a.subject_crop_backbone,
        _EXPECTED_SMALL_050,
        _EXPECTED_SMALL_SE_SQUEEZE,
        "small",
        3,
        8,
        48,
        288,
    )
    _assert_actual_backbone(
        candidate_b.backbone,
        _EXPECTED_SMALL_050,
        _EXPECTED_SMALL_SE_SQUEEZE,
        "small",
        4,
        8,
        48,
        288,
    )


def _assert_scalar_mlp(scalar_mlp: torch.nn.Module) -> None:
    layers = list(scalar_mlp.layers)
    assert len(layers) == 4
    first, first_activation, second, second_activation = layers
    assert isinstance(first, torch.nn.Linear)
    assert (first.in_features, first.out_features) == (80, 128)
    assert isinstance(first_activation, torch.nn.Hardswish)
    assert isinstance(second, torch.nn.Linear)
    assert (second.in_features, second.out_features) == (128, 64)
    assert isinstance(second_activation, torch.nn.Hardswish)


def _assert_candidate_wiring(
    candidate: torch.nn.Module,
    contract: SETCompositionNetManifest,
    expected_fusion_input: int,
) -> None:
    _assert_scalar_mlp(candidate.scalar_features)
    fusion = list(candidate.fusion)
    assert len(fusion) == 2
    fusion_projection, fusion_activation = fusion
    assert isinstance(fusion_projection, torch.nn.Linear)
    assert (fusion_projection.in_features, fusion_projection.out_features) == (expected_fusion_input, 256)
    assert isinstance(fusion_activation, torch.nn.Hardswish)

    embedding = candidate.embedding_projection
    assert isinstance(embedding, torch.nn.Linear)
    assert (embedding.in_features, embedding.out_features) == (
        256,
        contract.output_head_shapes[contract.embedding_name],
    )

    expected_head_names = tuple(name for name in contract.output_head_names if name != contract.embedding_name)
    assert tuple(candidate.heads) == expected_head_names
    for name in expected_head_names:
        head = candidate.heads[name]
        assert isinstance(head, torch.nn.Linear)
        assert (head.in_features, head.out_features) == (256, contract.output_head_shapes[name])


def _assert_rejects(label: str, check: Callable[[], None]) -> None:
    try:
        check()
    except AssertionError:
        return
    raise AssertionError(f"mutation guard escaped: {label}")


def _assert_mutation_guards(
    candidate_a: torch.nn.Module,
    candidate_b: torch.nn.Module,
    contract: SETCompositionNetManifest,
) -> None:
    stem = candidate_a.full_frame_backbone.features[0]
    original_stem_activation = stem[-1]
    stem[-1] = torch.nn.ReLU(inplace=True)
    try:
        _assert_rejects(
            "candidate A stem Hardswish -> ReLU",
            lambda: _assert_mobilenet_schedules(candidate_a, candidate_b),
        )
    finally:
        stem[-1] = original_stem_activation

    final_features = candidate_a.full_frame_backbone.features
    original_final_activation = final_features[-1]
    final_features[-1] = torch.nn.ReLU(inplace=True)
    try:
        _assert_rejects(
            "candidate A final Hardswish -> ReLU",
            lambda: _assert_mobilenet_schedules(candidate_a, candidate_b),
        )
    finally:
        final_features[-1] = original_final_activation

    original_fusion_projection = candidate_a.fusion[0]
    candidate_a.fusion[0] = torch.nn.Linear(1072, 128)
    try:
        _assert_rejects(
            "candidate A fusion 256 -> 128",
            lambda: _assert_candidate_wiring(candidate_a, contract, 1072),
        )
    finally:
        candidate_a.fusion[0] = original_fusion_projection

    block = candidate_a.full_frame_backbone.features[1]
    projection_conv = block.block[-2]
    mutated_projection = torch.nn.Conv2d(
        projection_conv.in_channels,
        projection_conv.out_channels,
        kernel_size=3,
        padding=1,
        bias=False,
    )
    block.block[-2] = mutated_projection
    try:
        _assert_rejects(
            "candidate A projection 1x1 -> 3x3",
            lambda: _assert_mobilenet_schedules(candidate_a, candidate_b),
        )
    finally:
        block.block[-2] = projection_conv

    depthwise = next(
        child for child in block.block
        if isinstance(child, torch.nn.Sequential)
        and isinstance(child[0], torch.nn.Conv2d)
        and child[0].groups == child[0].in_channels
    )
    original_depthwise_batch_norm = depthwise[1]
    depthwise[1] = torch.nn.Identity()
    try:
        _assert_rejects(
            "candidate A depthwise BatchNorm removal",
            lambda: _assert_mobilenet_schedules(candidate_a, candidate_b),
        )
    finally:
        depthwise[1] = original_depthwise_batch_norm

    projection_batch_norm = block.block[-1]
    block.block[-1] = torch.nn.Identity()
    try:
        _assert_rejects(
            "candidate A projection BatchNorm removal",
            lambda: _assert_mobilenet_schedules(candidate_a, candidate_b),
        )
    finally:
        block.block[-1] = projection_batch_norm

    stem_batch_norm = candidate_a.full_frame_backbone.features[0][1]
    original_stem_eps = stem_batch_norm.eps
    stem_batch_norm.eps = 1e-5
    try:
        _assert_rejects(
            "candidate A stem BatchNorm eps mutation",
            lambda: _assert_mobilenet_schedules(candidate_a, candidate_b),
        )
    finally:
        stem_batch_norm.eps = original_stem_eps

    final_batch_norm = candidate_a.full_frame_backbone.features[-2]
    original_final_momentum = final_batch_norm.momentum
    final_batch_norm.momentum = 0.1
    try:
        _assert_rejects(
            "candidate A final BatchNorm momentum mutation",
            lambda: _assert_mobilenet_schedules(candidate_a, candidate_b),
        )
    finally:
        final_batch_norm.momentum = original_final_momentum


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
    _assert_candidate_wiring(candidate_a, contract, 1072)
    _assert_candidate_wiring(candidate_b, contract, 352)
    _assert_mutation_guards(candidate_a, candidate_b, contract)
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
            "actual MobileNetV3 stem, Large-15/Small-11 blocks, and final projections",
            "actual scalar MLP, 256D fusion, 256-to-embedding, and manifest head wiring",
            "actual BatchNorm topology/settings plus removal and settings mutation guards",
            "actual 1x1 projection topology plus 1x1-to-3x3 mutation guard",
            "mutation guards for stem/final Hardswish and fusion output width",
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
