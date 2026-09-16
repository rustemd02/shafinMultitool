#!/usr/bin/env python3
"""M00 contract checks for the SETCompositionNet-v2 intent input.

Run from the repository root:

    python3 -m ml.camera_coach.tests.test_set_composition_net_v2

This is a contract/preprocessing/input check.  It does not train, load a GPU,
or assert any quality claim.  It validates:

* v2 manifest <-> v2 schema conformance;
* the 9 output head families, the 40 scalar slots, and the 26 utility index
  order are preserved from v1;
* intent encoding, including the unknown state and multi-style preservation;
* a tiny real-batch input build with finite tensors and correct shapes;
* paired identical pixels/ROI with different explicit styles and with unknown;
* the intent-conditioned supervision mask;
* that a v1 manifest cannot be read as v2 by a metadata swap.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import torch

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from ml.camera_coach.data.intent_features import (  # noqa: E402
    INTENT_ORDER,
    INTENT_STYLE_NAMES,
    KNOWN_FLAG_INDEX,
    encode_intent,
    intent_supervision_mask,
    preprocess_frame_v2,
    validate_intent_features,
)
from ml.camera_coach.models.set_composition_net import ContractError  # noqa: E402
from ml.camera_coach.models.set_composition_net_v2 import (  # noqa: E402
    INTENT_CONDITIONED_HEAD_ORDER,
    SETCompositionNetV2Manifest,
)

CONTRACTS_DIR = REPO_ROOT / "ml" / "camera_coach" / "contracts"
V1_MANIFEST_PATH = CONTRACTS_DIR / "set_composition_net_v1.json"
V2_MANIFEST_PATH = CONTRACTS_DIR / "set_composition_net_v2.json"
V2_SCHEMA_PATH = CONTRACTS_DIR / "set_composition_net_v2.schema.json"
V2_FIXTURE_PATH = CONTRACTS_DIR / "fixtures" / "set_composition_net_v2_intent_parity.json"


def _load(path: Path) -> dict:
    with path.open(encoding="utf-8") as stream:
        return json.load(stream)


def _tiny_frame(width: int = 8, height: int = 6) -> list[int]:
    return [((x * 17 + y * 29 + channel * 53) % 256) for y in range(height) for x in range(width) for channel in range(3)]


def _build(styles, *, roi=(0.25, 0.25, 0.5, 0.5)):
    return preprocess_frame_v2(
        _tiny_frame(),
        width=8,
        height=6,
        roi=list(roi),
        channel_order="RGB",
        intent_styles=styles,
    )


def test_manifest_schema_conformance() -> None:
    manifest = _load(V2_MANIFEST_PATH)
    schema = _load(V2_SCHEMA_PATH)
    try:
        import jsonschema

        validator = jsonschema.Draft202012Validator(schema)
        errors = sorted(validator.iter_errors(manifest), key=lambda error: list(error.path))
        assert not errors, [(list(error.path), error.message) for error in errors]
    except ImportError:  # pragma: no cover - jsonschema is present in CI/dev
        pass
    parsed = SETCompositionNetV2Manifest.load(V2_MANIFEST_PATH)
    assert parsed.intent_order == INTENT_ORDER
    assert parsed.intent_style_names == INTENT_STYLE_NAMES
    assert parsed.known_index == KNOWN_FLAG_INDEX == 8
    assert parsed.input_shapes["intent_features"] == (9,)
    assert parsed.scalar_feature_count == 40
    assert parsed.intent_conditioned_heads == INTENT_CONDITIONED_HEAD_ORDER
    assert parsed.supervision_mask_fill_value == 0.0


def test_v1_numeric_semantics_preserved() -> None:
    v1 = _load(V1_MANIFEST_PATH)
    v2 = _load(V2_MANIFEST_PATH)
    assert v2["outputs"]["head_order"] == v1["outputs"]["head_order"]
    assert [head["name"] for head in v2["outputs"]["heads"]] == [head["name"] for head in v1["outputs"]["heads"]]
    assert v2["inputs"]["scalar_features"]["ordered_names"] == v1["inputs"]["scalar_features"]["ordered_names"]
    v1_actions = next(h for h in v1["outputs"]["heads"] if h["name"] == "action_utility_logits")
    v2_actions = next(h for h in v2["outputs"]["heads"] if h["name"] == "action_utility_logits")
    assert v2_actions["ordered_names"] == v1_actions["ordered_names"]
    assert len(v2_actions["ordered_names"]) == 26
    assert v2["inputs"]["intent_features"]["shape"] == [9]
    assert "intent_features" not in v1["inputs"]


def test_v1_checkpoint_cannot_be_declared_v2() -> None:
    # A metadata-only swap of the v1 manifest must fail the v2 reader.
    with_v2_versions = json.loads(V1_MANIFEST_PATH.read_text(encoding="utf-8"))
    with_v2_versions["contract_version"] = "setcompositionnet.v2"
    with_v2_versions["input_contract_version"] = "setcompositionnet.input.v2"
    with_v2_versions["preprocessing_version"] = "setcompositionnet.preprocessing.v2"
    with_v2_versions["feature_version"] = "setcompositionnet.features.v2"
    with_v2_versions["output_contract_version"] = "setcompositionnet.output.v2"
    try:
        SETCompositionNetV2Manifest._from_raw(with_v2_versions, V1_MANIFEST_PATH)
    except ContractError:
        return
    raise AssertionError("v1 manifest accepted as v2 after a metadata-only change")


def test_intent_fixture_encoding_and_mask() -> None:
    fixture = _load(V2_FIXTURE_PATH)
    assert fixture["intent_order"] == list(INTENT_ORDER)
    for case in fixture["encoding_cases"]:
        encoded = encode_intent(case["styles"])
        assert encoded.dtype == torch.float32
        assert encoded.shape == (9,)
        assert encoded.tolist() == case["expected"], case["case_id"]
    for case in fixture["invalid_cases"]:
        try:
            validate_intent_features(torch.tensor(case["vector"], dtype=torch.float32))
        except ContractError:
            continue
        raise AssertionError(f"invalid intent vector accepted: {case['case_id']}")
    for case in fixture["supervision_mask_cases"]:
        intent = encode_intent(case["styles"])
        mask = intent_supervision_mask(intent, case["roi_present"])
        assert mask.shape == (len(INTENT_CONDITIONED_HEAD_ORDER),)
        assert mask.tolist() == case["expected"], case["case_id"]


def test_unknown_is_not_natural() -> None:
    unknown = encode_intent([])
    natural = encode_intent(["natural"])
    assert unknown.tolist() == [0.0] * 9
    assert unknown[KNOWN_FLAG_INDEX].item() == 0.0
    assert natural[0].item() == 1.0 and natural[KNOWN_FLAG_INDEX].item() == 1.0
    assert not torch.equal(unknown, natural)
    # known=1 with an empty style set is rejected.
    try:
        encode_intent([], known=True)
    except ContractError:
        pass
    else:
        raise AssertionError("known=1 with an empty style set must be rejected")
    # the natural placeholder for unknown is rejected at the tensor boundary.
    try:
        validate_intent_features(torch.tensor([1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]))
    except ContractError:
        pass
    else:
        raise AssertionError("unknown encoded as natural must be rejected")


def test_tiny_real_batch_inputs() -> None:
    records = [
        _build([]),
        _build(["natural"]),
        _build(["silhouette", "negative_space"]),
    ]
    full = torch.stack([record.full_frame_rgb for record in records])
    crop = torch.stack([record.subject_crop_rgb for record in records])
    mask = torch.stack([record.roi_mask for record in records])
    scalar = torch.stack([record.scalar_features for record in records])
    missing = torch.stack([record.missing_feature_mask for record in records])
    intent = torch.stack([record.intent_features for record in records])
    assert full.shape == (3, 320, 320, 3)
    assert crop.shape == (3, 192, 192, 3)
    assert mask.shape == (3, 320, 320, 1)
    assert scalar.shape == (3, 40)
    assert missing.shape == (3, 40)
    assert intent.shape == (3, 9)
    for tensor in (full, crop, mask, scalar, missing, intent):
        assert tensor.dtype == torch.float32
        assert torch.isfinite(tensor).all()
    assert torch.equal(intent[0], encode_intent([]))
    assert torch.equal(intent[1], encode_intent(["natural"]))
    assert torch.equal(intent[2], encode_intent(["silhouette", "negative_space"]))
    assert not torch.equal(intent[0], intent[1])
    # Only intent_features differ between the unknown and explicit-natural record.
    assert torch.equal(full[0], full[1]) and torch.equal(crop[0], crop[1])
    assert torch.equal(mask[0], mask[1]) and torch.equal(scalar[0], scalar[1])
    assert torch.equal(missing[0], missing[1])


def test_paired_intent_distinctness() -> None:
    fixture = _load(V2_FIXTURE_PATH)
    for case in fixture["paired_distinctness_cases"]:
        left = _build(case["left_styles"])
        right = _build(case["right_styles"])
        # Identical pixels/ROI/scalars: only the intent part may differ.
        for field in (
            "full_frame_rgb",
            "subject_crop_rgb",
            "roi_normalized_xywh",
            "roi_mask",
            "scalar_features",
            "missing_feature_mask",
        ):
            assert torch.equal(getattr(left, field), getattr(right, field)), (case["case_id"], field)
        differing = [
            index
            for index, (a, b) in enumerate(zip(left.intent_features.tolist(), right.intent_features.tolist()))
            if a != b
        ]
        assert differing == case["expected_differing_indices"], (case["case_id"], differing)


def test_missing_inputs_not_filled_with_false_knowledge() -> None:
    # Absent ROI must keep intent independent from ROI, and unknown must stay unknown.
    unknown_no_roi = preprocess_frame_v2(
        _tiny_frame(),
        width=8,
        height=6,
        roi=None,
        channel_order="RGB",
        intent_styles=None,
    )
    assert unknown_no_roi.roi_normalized_xywh.tolist() == [0.0, 0.0, 0.0, 0.0]
    assert unknown_no_roi.intent_features.tolist() == [0.0] * 9
    mask = intent_supervision_mask(unknown_no_roi.intent_features, roi_present=0.0)
    assert mask.tolist() == [0.0] * 4


def main() -> None:
    tests = [
        test_manifest_schema_conformance,
        test_v1_numeric_semantics_preserved,
        test_v1_checkpoint_cannot_be_declared_v2,
        test_intent_fixture_encoding_and_mask,
        test_unknown_is_not_natural,
        test_tiny_real_batch_inputs,
        test_paired_intent_distinctness,
        test_missing_inputs_not_filled_with_false_knowledge,
    ]
    for test in tests:
        test()
    print(json.dumps({
        "status": "pass",
        "contract_version": "setcompositionnet.v2",
        "intent_shape": [9],
        "intent_count": 9,
        "checks": [test.__name__ for test in tests],
    }, sort_keys=True, separators=(",", ":")))


if __name__ == "__main__":
    main()
