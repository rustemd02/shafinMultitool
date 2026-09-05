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
    SETCompositionNetInputs,
    SETCompositionNetManifest,
    count_macs,
    count_parameters,
)


SEED = 20260905


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
