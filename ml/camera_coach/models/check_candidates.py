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
    _ScalarFeatureMLP,
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
    if type(module) is torch.nn.ReLU:
        assert module.inplace is True
        return "RE"
    if type(module) is torch.nn.Hardswish:
        assert module.inplace is True
        return "HS"
    raise AssertionError(f"unexpected MobileNetV3 activation: {type(module).__name__}")


def _assert_batch_norm(module: torch.nn.Module, expected_features: int) -> None:
    assert type(module) is torch.nn.BatchNorm2d
    assert module.num_features == expected_features
    assert module.eps == _EXPECTED_BATCH_NORM_EPS
    assert module.momentum == _EXPECTED_BATCH_NORM_MOMENTUM
    assert module.affine is True
    assert module.track_running_stats is True
    assert module.weight is not None and module.bias is not None
    assert module.running_mean is not None and module.running_var is not None


def _assert_conv(
    module: torch.nn.Module,
    expected_input: int,
    expected_output: int,
    expected_kernel: int,
    expected_stride: int,
    expected_padding: int,
    expected_dilation: int,
    expected_groups: int,
    expected_bias: bool,
) -> None:
    assert type(module) is torch.nn.Conv2d
    assert (module.in_channels, module.out_channels) == (expected_input, expected_output)
    assert module.kernel_size == (expected_kernel, expected_kernel)
    assert module.stride == (expected_stride, expected_stride)
    assert module.padding == (expected_padding, expected_padding)
    assert module.dilation == (expected_dilation, expected_dilation)
    assert module.groups == expected_groups
    assert (module.bias is not None) is expected_bias


def _assert_linear(module: torch.nn.Module, expected_input: int, expected_output: int, expected_bias: bool) -> None:
    assert type(module) is torch.nn.Linear
    assert (module.in_features, module.out_features) == (expected_input, expected_output)
    assert (module.bias is not None) is expected_bias


def _assert_activation(module: torch.nn.Module, expected_activation: str) -> None:
    if expected_activation in {"RE", "HS"}:
        assert _activation_code(module) == expected_activation
        return
    if expected_activation == "HARD_SIGMOID":
        assert type(module) is torch.nn.Hardsigmoid
        assert module.inplace is False
        return
    raise AssertionError(f"unexpected expected activation: {expected_activation}")


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
    _assert_conv(
        conv,
        expected_input,
        expected_output,
        expected_kernel,
        expected_stride,
        (expected_kernel - 1) // 2,
        1,
        expected_groups,
        False,
    )
    _assert_batch_norm(batch_norm, expected_output)
    _assert_activation(activation, expected_activation)


def _assert_projection_conv(module: torch.nn.Module, expected_input: int, expected_output: int) -> None:
    _assert_conv(module, expected_input, expected_output, 1, 1, 0, 1, 1, False)


def _assert_squeeze_excitation(module: torch.nn.Module, expected_feature: int, expected_squeeze: int) -> None:
    assert type(module) is _SqueezeExcitation
    assert tuple(module._modules) == ("reduce", "expand", "gate")
    assert module.feature_channels == expected_feature
    assert module.squeeze_channels == expected_squeeze
    reduce, expand, gate = list(module.children())
    _assert_conv(reduce, expected_feature, expected_squeeze, 1, 1, 0, 1, 1, True)
    _assert_conv(expand, expected_squeeze, expected_feature, 1, 1, 0, 1, 1, True)
    _assert_activation(gate, "HARD_SIGMOID")


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
    _assert_conv(final_conv, expected_final_input, expected_final_output, 1, 1, 0, 1, 1, False)
    _assert_batch_norm(final_batch_norm, expected_final_output)
    _assert_activation(final_activation, "HS")
    blocks = features[1:-3]
    assert len(blocks) == len(expected_schedule)
    assert len(expected_se_squeeze) == len(expected_schedule)
    for block, expected, expected_squeeze in zip(blocks, expected_schedule, expected_se_squeeze):
        assert type(block) is _InvertedResidual
        expected_input, expected_expanded, expected_output, expected_kernel, expected_stride, expected_se, expected_activation = expected
        children = list(block.block)
        has_expansion = expected_expanded != expected_input
        expected_child_count = 3 + int(has_expansion) + int(expected_se)
        assert len(children) == expected_child_count
        depthwise_index = 1 if has_expansion else 0
        depthwise = children[depthwise_index]
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
        if has_expansion:
            expansion = children[0]
            _assert_conv_bn_activation(expansion, expected_input, expected_expanded, 1, 1, expected_activation)
            expansion_conv = expansion[0]
            actual_input = expansion_conv.in_channels
        else:
            assert children[0] is depthwise
            actual_input = depthwise_conv.in_channels
        projection_index = depthwise_index + 1 + int(expected_se)
        output_conv = children[projection_index]
        _assert_projection_conv(output_conv, expected_expanded, expected_output)
        _assert_batch_norm(children[projection_index + 1], expected_output)
        assert (actual_input, depthwise_conv.in_channels, output_conv.out_channels) == (
            expected_input, expected_expanded, expected_output
        )
        assert output_conv.in_channels == depthwise_conv.out_channels == expected_expanded
        if expected_se:
            assert expected_squeeze is not None
            _assert_squeeze_excitation(children[depthwise_index + 1], expected_expanded, expected_squeeze)
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
    assert type(scalar_mlp) is _ScalarFeatureMLP
    layers = list(scalar_mlp.layers)
    assert len(layers) == 4
    first, first_activation, second, second_activation = layers
    _assert_linear(first, 80, 128, True)
    _assert_activation(first_activation, "HS")
    _assert_linear(second, 128, 64, True)
    _assert_activation(second_activation, "HS")


def _assert_candidate_wiring(
    candidate: torch.nn.Module,
    contract: SETCompositionNetManifest,
    expected_fusion_input: int,
) -> None:
    _assert_scalar_mlp(candidate.scalar_features)
    fusion = list(candidate.fusion)
    assert len(fusion) == 2
    fusion_projection, fusion_activation = fusion
    _assert_linear(fusion_projection, expected_fusion_input, 256, True)
    _assert_activation(fusion_activation, "HS")

    embedding = candidate.embedding_projection
    expected_embedding_output = contract.output_head_shapes[contract.embedding_name]
    _assert_linear(embedding, 256, expected_embedding_output, True)

    expected_head_names = tuple(name for name in contract.output_head_names if name != contract.embedding_name)
    assert tuple(candidate.heads) == expected_head_names
    for name in expected_head_names:
        head = candidate.heads[name]
        _assert_linear(head, 256, contract.output_head_shapes[name], True)

    routed_modules = [fusion_projection, embedding, *candidate.heads.values()]
    assert len(routed_modules) == 1 + len(contract.output_head_names)
    assert len({id(module) for module in routed_modules}) == len(routed_modules)


def _assert_forward_routing(
    candidate: torch.nn.Module,
    inputs: SETCompositionNetInputs,
    contract: SETCompositionNetManifest,
    expected_fusion_input: int,
) -> None:
    routed = [("fusion", candidate.fusion[0]), ("embedding", candidate.embedding_projection)]
    routed.extend((name, candidate.heads[name]) for name in contract.output_head_names if name != contract.embedding_name)
    calls: dict[str, list[tuple[tuple[int, ...], tuple[int, ...]]]] = {name: [] for name, _ in routed}
    handles = []

    def record(name: str) -> Callable[[torch.nn.Module, tuple[torch.Tensor, ...], torch.Tensor], None]:
        def hook(_module: torch.nn.Module, args: tuple[torch.Tensor, ...], output: torch.Tensor) -> None:
            assert len(args) == 1
            calls[name].append((tuple(args[0].shape), tuple(output.shape)))

        return hook

    for name, module in routed:
        handles.append(module.register_forward_hook(record(name)))
    try:
        candidate.eval()
        with torch.no_grad():
            outputs = candidate(inputs)
    finally:
        for handle in handles:
            handle.remove()

    assert tuple(outputs) == contract.output_head_names
    assert calls["fusion"] == [((1, expected_fusion_input), (1, 256))]
    assert calls["embedding"] == [((1, 256), (1, contract.output_head_shapes[contract.embedding_name]))]
    for name in contract.output_head_names:
        if name == contract.embedding_name:
            continue
        assert calls[name] == [((1, 256), (1, contract.output_head_shapes[name]))]


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

    stem_conv = stem[0]
    mutated_stem_conv = torch.nn.Conv2d(
        stem_conv.in_channels,
        stem_conv.out_channels,
        kernel_size=3,
        stride=2,
        padding=0,
        bias=False,
    )
    stem[0] = mutated_stem_conv
    try:
        _assert_rejects(
            "candidate A stem padding mutation",
            lambda: _assert_mobilenet_schedules(candidate_a, candidate_b),
        )
    finally:
        stem[0] = stem_conv

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

    fusion_bias = candidate_a.fusion[0]
    original_fusion_bias = fusion_bias.bias
    fusion_bias.bias = None
    try:
        _assert_rejects(
            "candidate A fusion bias removal",
            lambda: _assert_candidate_wiring(candidate_a, contract, 1072),
        )
    finally:
        fusion_bias.bias = original_fusion_bias

    original_risk_head = candidate_a.heads["risk_probability"]
    candidate_a.heads["risk_probability"] = candidate_a.heads["good_frame_probability"]
    try:
        _assert_rejects(
            "candidate A aliased probability heads",
            lambda: _assert_candidate_wiring(candidate_a, contract, 1072),
        )
    finally:
        candidate_a.heads["risk_probability"] = original_risk_head

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

    mutated_projection = torch.nn.Conv2d(
        projection_conv.in_channels,
        projection_conv.out_channels,
        kernel_size=1,
        dilation=2,
        padding=0,
        bias=False,
    )
    block.block[-2] = mutated_projection
    try:
        _assert_rejects(
            "candidate A projection dilation mutation",
            lambda: _assert_mobilenet_schedules(candidate_a, candidate_b),
        )
    finally:
        block.block[-2] = projection_conv

    se_block = next(
        candidate_block for candidate_block in candidate_a.full_frame_backbone.features[1:-3]
        if any(type(child) is _SqueezeExcitation for child in candidate_block.block)
    )
    se_index = next(index for index, child in enumerate(se_block.block) if type(child) is _SqueezeExcitation)
    se = se_block.block[se_index]
    original_se_reduce = se.reduce
    se.reduce = torch.nn.Conv2d(
        original_se_reduce.in_channels,
        original_se_reduce.out_channels,
        kernel_size=3,
        padding=1,
        bias=True,
    )
    try:
        _assert_rejects(
            "candidate A SE reduce kernel mutation",
            lambda: _assert_mobilenet_schedules(candidate_a, candidate_b),
        )
    finally:
        se.reduce = original_se_reduce

    projection_index = se_index + 1
    original_se = se_block.block[se_index]
    original_projection = se_block.block[projection_index]
    se_block.block[se_index] = original_projection
    se_block.block[projection_index] = original_se
    try:
        _assert_rejects(
            "candidate A SE/projection order mutation",
            lambda: _assert_mobilenet_schedules(candidate_a, candidate_b),
        )
    finally:
        se_block.block[se_index] = original_se
        se_block.block[projection_index] = original_projection

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
    original_stem_affine = stem_batch_norm.affine
    stem_batch_norm.affine = False
    try:
        _assert_rejects(
            "candidate A stem BatchNorm affine mutation",
            lambda: _assert_mobilenet_schedules(candidate_a, candidate_b),
        )
    finally:
        stem_batch_norm.affine = original_stem_affine

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
    _assert_forward_routing(candidate_a, inputs, contract, 1072)
    _assert_forward_routing(candidate_b, inputs, contract, 352)
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
            "actual fusion/embedding/all-nine-head forward routing and distinct module identity",
            "actual BatchNorm topology/settings plus removal and settings mutation guards",
            "actual 1x1 projection topology plus 1x1-to-3x3 mutation guard",
            "actual Conv/BN/activation/SE/Linear signatures and identity/routing checks",
            "bounded mutation matrix for representative field, topology, and alias escapes",
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
