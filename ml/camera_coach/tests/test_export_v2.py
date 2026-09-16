#!/usr/bin/env python3
"""Tooling checks for the SETCompositionNet-v2 Core ML export path.

These tests cover the *export machinery* for M05's tooling slice.  They do not
train anything, do not load admitted data, and make no quality claim: the
exported package is a deterministically seeded untrained candidate used only to
prove that the v2 contract (seven inputs including the separate nine-component
``intent_features``, nine heads in ``head_order``) survives FP16 conversion and
that PyTorch/Core ML stay numerically paired.

Run from the repository root::

    python3 -m pytest ml/camera_coach/tests/test_export_v2.py -q
"""

from __future__ import annotations

import copy
import json
from pathlib import Path
import sys

import numpy as np
import pytest
import torch

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from ml.camera_coach import export_v2  # noqa: E402
from ml.camera_coach.models.set_composition_net import ContractError  # noqa: E402
from ml.camera_coach.models.set_composition_net_v2 import (  # noqa: E402
    SETCompositionNetV2Manifest,
    encode_intent,
)

MANIFEST = SETCompositionNetV2Manifest.load()
EXPECTED_INPUT_NAMES = [
    "full_frame_rgb",
    "subject_crop_rgb",
    "roi_normalized_xywh",
    "roi_mask",
    "scalar_features",
    "missing_feature_mask",
    "intent_features",
]


def test_expected_export_signature_matches_manifest() -> None:
    expected = export_v2.expected_coreml_io(MANIFEST)
    names = [entry["name"] for entry in expected["inputs"]]
    assert names == EXPECTED_INPUT_NAMES
    shapes = {entry["name"]: entry["shape"] for entry in expected["inputs"]}
    assert shapes["full_frame_rgb"] == [1, 3, 320, 320]
    assert shapes["subject_crop_rgb"] == [1, 3, 192, 192]
    assert shapes["roi_normalized_xywh"] == [1, 4]
    assert shapes["roi_mask"] == [1, 1, 320, 320]
    assert shapes["scalar_features"] == [1, 40]
    assert shapes["missing_feature_mask"] == [1, 40]
    assert shapes["intent_features"] == [1, 9]
    # The missing mask is the manifest's nested scalar_features.missing_mask,
    # not a newly invented contract input.
    missing_entry = next(entry for entry in expected["inputs"] if entry["name"] == "missing_feature_mask")
    assert missing_entry["manifest_node"] == "inputs.scalar_features.missing_mask"
    assert [entry["name"] for entry in expected["outputs"]] == list(MANIFEST.output_head_names)
    assert [entry["shape"] for entry in expected["outputs"]] == [
        [1, MANIFEST.output_head_shapes[name]] for name in MANIFEST.output_head_names
    ]
    assert all(entry["dtype"] == "float32" for entry in expected["inputs"] + expected["outputs"])


def test_contract_validator_accepts_manifest_derived_signature() -> None:
    report = export_v2.validate_contract(export_v2.expected_coreml_io(MANIFEST), MANIFEST)
    assert report["passed"] is True
    assert report["intent_features_separate_input"] is True
    assert report["intent_features_dtype_shape"] == "float32[1, 9]"
    assert report["scalar_slots"] == 40
    assert report["scalar_intent_name_overlap"] == []
    assert report["output_head_order_matches"] is True
    assert all(row["matched"] for row in report["inputs"])
    assert all(row["matched"] for row in report["outputs"])


def test_contract_validator_rejects_missing_intent_input() -> None:
    exported = copy.deepcopy(export_v2.expected_coreml_io(MANIFEST))
    exported["inputs"] = [entry for entry in exported["inputs"] if entry["name"] != "intent_features"]
    with pytest.raises(ContractError):
        export_v2.validate_contract(exported, MANIFEST)


def test_contract_validator_rejects_head_order_drift() -> None:
    exported = copy.deepcopy(export_v2.expected_coreml_io(MANIFEST))
    exported["outputs"] = list(reversed(exported["outputs"]))
    with pytest.raises(ContractError):
        export_v2.validate_contract(exported, MANIFEST)


def test_contract_validator_rejects_scalar_slot_growth() -> None:
    exported = copy.deepcopy(export_v2.expected_coreml_io(MANIFEST))
    for entry in exported["inputs"]:
        if entry["name"] == "scalar_features":
            entry["shape"] = [1, 49]
    with pytest.raises(ContractError):
        export_v2.validate_contract(exported, MANIFEST)


def test_contract_validator_rejects_wrong_dtype() -> None:
    exported = copy.deepcopy(export_v2.expected_coreml_io(MANIFEST))
    for entry in exported["inputs"]:
        if entry["name"] == "intent_features":
            entry["dtype"] = "float16"
    with pytest.raises(ContractError):
        export_v2.validate_contract(exported, MANIFEST)


def test_intent_features_are_not_reused_scalar_slots() -> None:
    scalar_names = MANIFEST.raw["inputs"]["scalar_features"]["ordered_names"]
    assert len(scalar_names) == 40
    assert MANIFEST.intent_feature_count == 9
    assert not set(scalar_names).intersection(MANIFEST.intent_order)
    assert MANIFEST.raw["inputs"]["intent_features"]["separate_input"] is True
    vector = encode_intent(["silhouette", "negative_space"])
    assert vector.shape == (9,)
    assert vector.dtype == torch.float32
    assert vector.tolist() == [0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
    # Unknown must stay all-zero and never become natural.
    assert encode_intent([]).tolist() == [0.0] * 9


def test_output_path_guard_blocks_app_target() -> None:
    with pytest.raises(ValueError):
        export_v2._assert_output_path_allowed(export_v2.APP_TARGET_ROOT / "SETCompositionNetV2.mlpackage")
    with pytest.raises(ValueError):
        export_v2._assert_output_path_allowed(export_v2.DEFAULT_OUTPUT_DIR / "not-a-package.pt")


def test_export_refuses_app_target_before_converting(tmp_path) -> None:
    with pytest.raises(ValueError):
        export_v2.export(export_v2.APP_TARGET_ROOT / "SETCompositionNetV2-tooling.mlpackage")
    assert not (export_v2.APP_TARGET_ROOT / "SETCompositionNetV2-tooling.mlpackage").exists()


@pytest.mark.parametrize("candidate_id", sorted(export_v2.CANDIDATE_TYPES))
def test_export_end_to_end_contract_parity_and_provenance(tmp_path, candidate_id: str) -> None:
    pytest.importorskip("coremltools")
    output = tmp_path / f"SETCompositionNet-v2-tooling-{candidate_id}.mlpackage"
    summary = export_v2.export(output, candidate_id=candidate_id, seed=4242, overwrite=False)

    assert summary["contract_passed"] is True
    assert output.is_dir()
    assert export_v2.APP_TARGET_ROOT.resolve() not in output.resolve().parents

    receipt = json.loads(export_v2.receipt_path(output).read_text(encoding="utf-8"))
    assert receipt["schema_id"] == "camera-v2-coreml-tooling-export-v1"
    assert receipt["tooling_only"] == "true"
    assert receipt["untrained_weights"] == "true"
    assert receipt["not_a_release_candidate"] == "true"
    assert receipt["release_admissible"] is False
    assert receipt["human_gold"] is False
    assert receipt["calibration"] == "absent"
    assert receipt["quality_claim"] == "none"
    assert receipt["warning"] == "not a release candidate / not a quality claim"
    assert receipt["admitted_data"] == "none (M03/M04 blocked)"
    assert "no training performed" in receipt["weights_origin"]
    assert isinstance(receipt["weights_sha256"], str) and len(receipt["weights_sha256"]) == 64
    assert receipt["mlpackage"]["tree_sha256"] == summary["tree_sha256"]
    assert receipt["contract_manifest"]["sha256"] == export_v2.sha256_file(
        REPO_ROOT / "ml/camera_coach/contracts/set_composition_net_v2.json"
    )

    exported_inputs = {entry["name"]: entry for entry in receipt["inputs"]}
    assert list(exported_inputs) == EXPECTED_INPUT_NAMES
    assert exported_inputs["intent_features"]["shape"] == [1, 9]
    assert exported_inputs["scalar_features"]["shape"] == [1, 40]
    exported_outputs = [entry["name"] for entry in receipt["outputs"]]
    assert exported_outputs == list(MANIFEST.output_head_names)

    contract = receipt["contract_validation"]
    assert contract["passed"] is True
    assert all(row["matched"] for row in contract["inputs"])
    assert all(row["matched"] for row in contract["outputs"])
    assert contract["intent_features_separate_input"] is True
    assert contract["scalar_intent_name_overlap"] == []

    parity = json.loads(export_v2.parity_path(output).read_text(encoding="utf-8"))
    assert set(parity["per_head"]) == set(MANIFEST.output_head_names)
    assert parity["all_heads_finite"] is True
    for name in MANIFEST.output_head_names:
        entry = parity["per_head"][name]
        assert np.isfinite(entry["max_abs_error"])
        assert entry["max_abs_error"] >= 0.0
        assert set(entry["cases"]) == set(parity["cases"])
    for name in MANIFEST.intent_conditioned_heads:
        assert parity["intent_sensitivity"][name]["both_respond_to_intent"] is True

    import coremltools as ct

    model = ct.models.MLModel(str(output), compute_units=ct.ComputeUnit.CPU_ONLY)
    metadata = dict(model.user_defined_metadata)
    assert metadata["com.setos.artifact_kind"] == "tooling_export_path_validation"
    assert metadata["com.setos.not_a_release_candidate"] == "true"
    assert metadata["com.setos.untrained_weights"] == "true"
    assert metadata["com.setos.release_admissible"] == "false"
    assert metadata["com.setos.warning"] == "not a release candidate / not a quality claim"
    assert metadata["com.setos.weights_sha256"] == receipt["weights_sha256"]
    assert metadata["com.setos.contract_manifest_sha256"] == receipt["contract_manifest"]["sha256"]

    description = model.get_spec().description
    declared = export_v2.coreml_io_from_description(description)
    report = export_v2.validate_contract(declared, MANIFEST)
    assert report["passed"] is True


def main() -> None:
    raise SystemExit("run with pytest: python3 -m pytest ml/camera_coach/tests/test_export_v2.py -q")


if __name__ == "__main__":
    main()
