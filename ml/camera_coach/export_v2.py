#!/usr/bin/env python3
"""Tooling-only Core ML export path for the SETCompositionNet-v2 input contract.

This module builds and validates the *export machinery* for a v2 Core ML
``mlprogram`` against the frozen manifest
``ml/camera_coach/contracts/set_composition_net_v2.json``.  It is deliberately
not a release path:

* Without a checkpoint, exports a deterministically seeded untrained candidate.
  An explicit records checkpoint plus its exact training config can instead
  exercise the same export/parity path with actual research weights.
* Every package stays research/tooling-only and not release admissible. Legacy
  component supervision remains unknown, regardless of aggregate head flags.
* The output path is forced outside the iOS app target tree so the package can
  never be picked up by the application bundle.

Inputs verified against the frozen manifest (transport is batched NCHW, i.e.
HWC with a leading batch dimension):

* ``full_frame_rgb``   float32[1, 3, 320, 320]
* ``subject_crop_rgb`` float32[1, 3, 192, 192]
* ``roi_normalized_xywh`` float32[1, 4]
* ``roi_mask``         float32[1, 1, 320, 320]
* ``scalar_features``  float32[1, 40]
* ``missing_feature_mask`` float32[1, 40]  (nested ``scalar_features.missing_mask``)
* ``intent_features``  float32[1, 9]  (separate input; order natural, silhouette,
  low_key, symmetry, negative_space, dutch_angle, intentional_motion_blur,
  handheld, known)

Outputs are the nine manifest heads in ``outputs.head_order``.

Run from the repository root::

    python3 -m ml.camera_coach.export_v2
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import warnings

import numpy as np
import torch
from torch import Tensor, nn


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from ml.camera_coach.models.set_composition_net import ContractError  # noqa: E402
from ml.camera_coach.component_supervision import (  # noqa: E402
    CHECKPOINT_VERSION, LEGACY_CHECKPOINT_VERSION, canonical_hash, checkpoint_supervision,
    export_metadata, new_supervision,
)
from ml.camera_coach.models.set_composition_net_v2 import (  # noqa: E402
    SETCompositionNetV2CandidateA,
    SETCompositionNetV2CandidateB,
    SETCompositionNetV2Manifest,
)

V2_MANIFEST_PATH = REPO_ROOT / "ml/camera_coach/contracts/set_composition_net_v2.json"
APP_TARGET_ROOT = REPO_ROOT / "shafinMultitool"
DEFAULT_OUTPUT_DIR = REPO_ROOT.parent / "setos-backend/local-data/SETOS/Models/camera-coach/exports"
DEFAULT_OUTPUT_NAME = "SETCompositionNet-v2-tooling-untrained.mlpackage"
MISSING_FEATURE_MASK_NAME = "missing_feature_mask"

CANDIDATE_TYPES = {
    SETCompositionNetV2CandidateA.candidate_id: SETCompositionNetV2CandidateA,
    SETCompositionNetV2CandidateB.candidate_id: SETCompositionNetV2CandidateB,
}
# The frozen records/production config selects candidate B, so it is the
# default here; candidate A remains available to exercise the dual-branch path.
DEFAULT_CANDIDATE_ID = SETCompositionNetV2CandidateB.candidate_id

PROVENANCE_FLAGS = {
    "artifact_kind": "tooling_export_path_validation",
    "tooling_only": "true",
    "untrained_weights": "true",
    "release_admissible": "false",
    "human_gold": "false",
    "not_a_release_candidate": "true",
    "quality_claim": "none",
    "calibration": "absent",
    "warning": "not a release candidate / not a quality claim",
    "blocked_on": "M03,M04 admitted data (0 admitted)",
}
ARTIFACT_PROVENANCE = {f"com.setos.{key}": value for key, value in PROVENANCE_FLAGS.items()}
PARITY_ATOL = 0.005
PARITY_RTOL = 0.01


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_tree(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        relative = path.relative_to(root).as_posix()
        digest.update(f"{relative}\0{path.stat().st_size}\0{sha256_file(path)}\n".encode())
    return digest.hexdigest()


def sha256_state_dict(state_dict: dict) -> str:
    """Deterministic content hash over a model state_dict."""
    digest = hashlib.sha256()
    for name in sorted(state_dict):
        tensor = state_dict[name]
        if not isinstance(tensor, Tensor):
            raise ContractError(f"state_dict entry {name!r} is not a tensor")
        array = tensor.detach().cpu().contiguous().numpy()
        digest.update(name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(str(array.dtype).encode("ascii"))
        digest.update(b"\0")
        digest.update(",".join(str(dim) for dim in array.shape).encode("ascii"))
        digest.update(b"\0")
        digest.update(array.tobytes())
        digest.update(b"\n")
    return digest.hexdigest()


def write_json(path: Path, value: dict) -> None:
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def _transport_shape(hwc_shape: tuple[int, ...]) -> tuple[int, ...]:
    """Map a logical HWC manifest shape to the batched NCHW transport shape."""
    if len(hwc_shape) == 3:
        height, width, channels = hwc_shape
        return (1, channels, height, width)
    if len(hwc_shape) == 1:
        return (1, hwc_shape[0])
    raise ContractError(f"unsupported manifest input rank for shape {hwc_shape}")


def expected_coreml_io(manifest: SETCompositionNetV2Manifest) -> dict:
    """Derive the exact expected Core ML input/output signature from the manifest.

    The six manifest-level inputs are taken as declared.  ``missing_feature_mask``
    is not a new contract input: it is the manifest's nested
    ``inputs.scalar_features.missing_mask`` node, exposed as its own tensor
    exactly like the frozen v1 six-tensor payload.  It is inserted directly
    after ``scalar_features`` in declaration order.
    """

    raw_inputs = manifest.raw["inputs"]
    inputs: list[dict] = []
    for name, node in raw_inputs.items():
        inputs.append(
            {
                "name": name,
                "dtype": node["dtype"],
                "shape": list(_transport_shape(tuple(node["shape"]))),
                "manifest_node": f"inputs.{name}",
            }
        )
        if name == "scalar_features":
            missing = node["missing_mask"]
            if missing["shape"] != node["shape"]:
                raise ContractError("missing_mask must mirror the scalar feature shape")
            inputs.append(
                {
                    "name": MISSING_FEATURE_MASK_NAME,
                    "dtype": node["dtype"],
                    "shape": list(_transport_shape(tuple(missing["shape"]))),
                    "manifest_node": "inputs.scalar_features.missing_mask",
                }
            )

    outputs = [
        {
            "name": name,
            "dtype": manifest.output_head_specs[name]["dtype"],
            "shape": [1, manifest.output_head_shapes[name]],
            "manifest_node": f"outputs.heads[{index}]",
        }
        for index, name in enumerate(manifest.output_head_names)
    ]
    return {"inputs": inputs, "outputs": outputs}


def _normalize_dtype(value: object) -> str:
    text = str(value)
    if "FLOAT32" in text or text in {"65568", "float32"}:
        return "float32"
    return text.lower()


def coreml_io_from_description(description) -> dict:
    """Read names/dtypes/shapes out of a Core ML model description."""

    def entries(items) -> list[dict]:
        collected: list[dict] = []
        for item in items:
            node = item.type.multiArrayType
            collected.append(
                {
                    "name": item.name,
                    "dtype": _normalize_dtype(node.dataType),
                    "shape": [int(dim) for dim in node.shape],
                }
            )
        return collected

    return {"inputs": entries(description.input), "outputs": entries(description.output)}


def validate_contract(exported: dict, manifest: SETCompositionNetV2Manifest) -> dict:
    """Compare an exported signature to the frozen manifest; raise on any drift.

    Returns a machine-readable report.  Any name/type/dtype/shape/order mismatch
    is a hard failure: "it converted" is not contract conformance.
    """

    expected = expected_coreml_io(manifest)
    report: dict = {"inputs": [], "outputs": [], "passed": True}

    def compare(kind: str) -> None:
        nonlocal report
        expected_entries = expected[kind]
        actual_entries = exported[kind]
        expected_by_name = {entry["name"]: entry for entry in expected_entries}
        actual_by_name = {entry["name"]: entry for entry in actual_entries}
        missing = sorted(set(expected_by_name) - set(actual_by_name))
        extra = sorted(set(actual_by_name) - set(expected_by_name))
        if missing or extra:
            raise ContractError(f"{kind} name mismatch: missing={missing}, extra={extra}")
        for entry in expected_entries:
            actual = actual_by_name[entry["name"]]
            matched = (
                actual["dtype"] == entry["dtype"]
                and [int(dim) for dim in actual["shape"]] == [int(dim) for dim in entry["shape"]]
            )
            report[kind].append(
                {
                    "name": entry["name"],
                    "manifest_node": entry["manifest_node"],
                    "manifest_dtype": entry["dtype"],
                    "export_dtype": actual["dtype"],
                    "manifest_shape": list(entry["shape"]),
                    "export_shape": list(actual["shape"]),
                    "matched": matched,
                }
            )
            if not matched:
                report["passed"] = False
                raise ContractError(
                    f"{kind} {entry['name']!r} drifted: manifest "
                    f"{entry['dtype']}{entry['shape']} vs export {actual['dtype']}{actual['shape']}"
                )

    compare("inputs")
    compare("outputs")

    exported_output_order = [entry["name"] for entry in exported["outputs"]]
    if exported_output_order != list(manifest.output_head_names):
        raise ContractError(
            "exported output order is not the manifest head_order: "
            f"{exported_output_order} != {list(manifest.output_head_names)}"
        )
    report["output_head_order_matches"] = True
    report["output_head_order"] = exported_output_order

    input_names = [entry["name"] for entry in exported["inputs"]]
    scalar = next(entry for entry in exported["inputs"] if entry["name"] == "scalar_features")
    intent = next(entry for entry in exported["inputs"] if entry["name"] == "intent_features")
    if intent["name"] == scalar["name"] or intent["shape"] == scalar["shape"]:
        raise ContractError("intent_features must be a separate input from the 40 scalar slots")
    if scalar["shape"] != [1, 40]:
        raise ContractError(f"scalar_features must stay 40 slots, got {scalar['shape']}")
    if intent["shape"] != [1, 9]:
        raise ContractError(f"intent_features must be 9 components, got {intent['shape']}")
    if MISSING_FEATURE_MASK_NAME not in input_names:
        raise ContractError("missing_feature_mask must remain an explicit input")
    intent_node = manifest.raw["inputs"]["intent_features"]
    if intent_node.get("separate_input") is not True:
        raise ContractError("manifest no longer declares intent_features as a separate input")
    scalar_names = manifest.raw["inputs"]["scalar_features"]["ordered_names"]
    overlap = sorted(set(scalar_names).intersection(manifest.intent_order))
    if overlap:
        raise ContractError(f"intent names leaked into scalar slots: {overlap}")
    report["intent_features_separate_input"] = True
    report["intent_features_dtype_shape"] = f"{intent['dtype']}{intent['shape']}"
    report["intent_order"] = list(manifest.intent_order)
    report["scalar_slots"] = scalar["shape"][-1]
    report["scalar_intent_name_overlap"] = overlap
    if not report["passed"]:
        raise ContractError("exported contract validation failed")
    return report


def build_untrained_model(candidate_id: str, manifest: SETCompositionNetV2Manifest, seed: int):
    """Build a deterministically seeded, untrained v2 candidate in eval mode."""

    if candidate_id not in CANDIDATE_TYPES:
        raise ValueError(f"unknown candidate_id: {candidate_id}; expected one of {sorted(CANDIDATE_TYPES)}")
    torch.manual_seed(seed)
    model = CANDIDATE_TYPES[candidate_id](manifest).eval()
    for parameter in model.parameters():
        parameter.requires_grad_(False)
    weight_sha = sha256_state_dict(model.state_dict())
    parameter_count = sum(parameter.numel() for parameter in model.parameters())
    return model, weight_sha, parameter_count


def load_checkpoint_model(checkpoint_path: Path, config_path: Path, manifest, *, required_components=None):
    """Load the selected state with explicit config/contract and component binding.

    This is a research export boundary, not a runtime or release admission.
    ``required_components`` can tighten it; it cannot authorize release use.
    """
    from ml.camera_coach.trainer_records import RecordsTrainingConfig, resume_semantic_sha256
    from ml.camera_coach.losses import LossConfig

    config = RecordsTrainingConfig.from_file(config_path)
    manifest_hash = sha256_file(V2_MANIFEST_PATH)
    if config.model.manifest_sha256 != manifest_hash or manifest.raw != SETCompositionNetV2Manifest.load().raw:
        raise ContractError("checkpoint export model contract does not match the frozen manifest/config")
    configured_manifest = Path(config.model.manifest_path)
    if not configured_manifest.is_absolute():
        configured_manifest = REPO_ROOT / configured_manifest
    if configured_manifest.resolve() != V2_MANIFEST_PATH.resolve():
        raise ContractError("checkpoint config points outside the frozen model contract")
    payload = torch.load(checkpoint_path, map_location="cpu", weights_only=True)
    if not isinstance(payload, dict) or payload.get("checkpoint_version") not in (CHECKPOINT_VERSION, LEGACY_CHECKPOINT_VERSION):
        raise ContractError("unsupported records checkpoint format")
    if payload.get("resume_semantic_sha256", payload.get("config_sha256")) != resume_semantic_sha256(config):
        raise ContractError("checkpoint/config training semantics mismatch")
    if payload.get("seed") not in config.seeds or type(payload.get("epoch")) is not int or payload["epoch"] < 1:
        raise ContractError("checkpoint seed/epoch does not match its training config")
    selected = payload.get("best", payload)
    if not isinstance(selected, dict):
        raise ContractError("selected checkpoint state must be an object")
    selected_epoch = selected.get("epoch")
    if type(selected_epoch) is not int or not 1 <= selected_epoch <= payload["epoch"]:
        raise ContractError("selected checkpoint epoch is invalid")
    state = selected.get("state", selected.get("model_state"))
    if not isinstance(state, dict) or not state or any(not isinstance(v, Tensor) or not torch.isfinite(v).all() for v in state.values()):
        raise ContractError("checkpoint model state is empty, malformed or nonfinite")
    if config.candidate not in CANDIDATE_TYPES:
        raise ContractError("checkpoint candidate is not a supported v2 architecture")
    model = CANDIDATE_TYPES[config.candidate](manifest).eval()
    expected_state = model.state_dict()
    if set(state) != set(expected_state) or any(state[k].shape != v.shape or state[k].dtype != v.dtype
            for k,v in expected_state.items() if k in state):
        raise ContractError("checkpoint state keys/shapes/dtypes do not match its v2 candidate")
    model.load_state_dict(state, strict=True)
    for parameter in model.parameters():
        parameter.requires_grad_(False)
    supervision = checkpoint_supervision(payload, manifest, selected_best=True)
    if payload["checkpoint_version"] == CHECKPOINT_VERSION:
        source = supervision["source"]
        loss_path = Path(config.loss.path)
        if not loss_path.is_absolute():
            loss_path = REPO_ROOT / loss_path
        if sha256_file(loss_path) != config.loss.sha256:
            raise ContractError("checkpoint loss config hash differs from its declared source")
        expected = dict(model_contract_sha256=config.model.manifest_sha256,
            declared_dataset_sha256=config.dataset.sha256, resume_semantic_sha256=resume_semantic_sha256(config),
            effective_loss_sha256=canonical_hash(LossConfig.from_file(loss_path).as_mapping()))
        if any(source.get(k) != v for k,v in expected.items()):
            raise ContractError("selected-state component evidence/config binding mismatch")
    evidence = export_metadata(supervision, manifest, required_components=required_components)
    origin = dict(checkpoint_path=str(checkpoint_path.resolve()), checkpoint_sha256=sha256_file(checkpoint_path),
        training_config_sha256=sha256_file(config_path), config_sha256=config.config_sha256,
        checkpoint_config_sha256=payload.get("config_sha256"), training_seed=payload["seed"],
        resume_semantic_sha256=resume_semantic_sha256(config), candidate_id=config.candidate,
        selected_epoch=selected_epoch, checkpoint_epoch=payload["epoch"], data_admission=config.dataset.admission,
        component_evidence=evidence, research_only=True, release_admissible=False)
    return model, sha256_state_dict(model.state_dict()), sum(p.numel() for p in model.parameters()), origin


class _V2ExportWrapper(nn.Module):
    """Traced view: seven tensors in, nine heads out in manifest head_order."""

    def __init__(self, model: nn.Module, output_names: tuple[str, ...]):
        super().__init__()
        self.model = model
        self.output_names = output_names

    def forward(
        self,
        full_frame_rgb: Tensor,
        subject_crop_rgb: Tensor,
        roi_normalized_xywh: Tensor,
        roi_mask: Tensor,
        scalar_features: Tensor,
        missing_feature_mask: Tensor,
        intent_features: Tensor,
    ):
        outputs = self.model(
            full_frame_rgb,
            subject_crop_rgb,
            roi_normalized_xywh,
            roi_mask,
            scalar_features,
            missing_feature_mask,
            intent_features,
        )
        return tuple(outputs[name] for name in self.output_names)


def parity_cases(manifest: SETCompositionNetV2Manifest, seed: int) -> list[dict]:
    """Deterministic random inputs exercising known/unknown intent and ROI presence."""

    rng = np.random.default_rng(seed)
    full = rng.random((1, 3, 320, 320), dtype=np.float32)
    crop = rng.random((1, 3, 192, 192), dtype=np.float32)
    roi = np.array([[0.2, 0.25, 0.4, 0.5]], dtype=np.float32)
    mask = np.zeros((1, 1, 320, 320), dtype=np.float32)
    mask[:, :, 80:240, 64:192] = 1.0
    scalars = rng.random((1, 40), dtype=np.float32) * 0.5
    # Categorical slots must stay exactly on the manifest catalog values.
    scalar_names = manifest.raw["inputs"]["scalar_features"]["ordered_names"]
    for categorical in ("orientation_category", "lens_category"):
        index = scalar_names.index(categorical)
        scalars[0, index] = manifest.raw["categorical_features"][categorical]["allowed_normalized_values"][0]
    missing = np.zeros((1, 40), dtype=np.float32)
    missing[:, 3:5] = 1.0
    explicit_natural = np.zeros((1, 9), dtype=np.float32)
    explicit_natural[0, 0] = 1.0
    explicit_natural[0, 8] = 1.0
    unknown = np.zeros((1, 9), dtype=np.float32)
    no_roi = np.zeros((1, 4), dtype=np.float32)

    def case(case_id: str, roi_values, mask_values, intent_values) -> dict:
        return {
            "case_id": case_id,
            "full_frame_rgb": full,
            "subject_crop_rgb": crop,
            "roi_normalized_xywh": roi_values,
            "roi_mask": mask_values,
            "scalar_features": scalars,
            "missing_feature_mask": missing,
            "intent_features": intent_values,
        }

    return [
        case("explicit_natural_roi_present", roi, mask, explicit_natural),
        case(
            "unknown_intent_roi_present",
            roi,
            mask,
            unknown,
        ),
        case("silhouette_no_roi", no_roi, np.zeros_like(mask), _one_hot(manifest, "silhouette")),
    ]


def _one_hot(manifest: SETCompositionNetV2Manifest, style: str) -> np.ndarray:
    vector = np.zeros((1, manifest.intent_feature_count), dtype=np.float32)
    vector[0, manifest.intent_order.index(style)] = 1.0
    vector[0, manifest.known_index] = 1.0
    return vector


def _torch_inputs(case: dict, manifest: SETCompositionNetV2Manifest) -> tuple[Tensor, ...]:
    order = [entry["name"] for entry in expected_coreml_io(manifest)["inputs"]]
    return tuple(torch.from_numpy(case[name]) for name in order)


def parity_report(wrapper: nn.Module, coreml_model, manifest: SETCompositionNetV2Manifest, cases: list[dict]) -> dict:
    """Compare PyTorch and Core ML outputs per head on the provided cases.

    Actual errors are recorded; fixed atol=0.005/rtol=0.01 must hold for every
    head/case. Empty cases, shape drift and nonfinite values cannot pass.
    """

    if not cases:
        raise ContractError("parity requires nonempty cases")
    order = [entry["name"] for entry in expected_coreml_io(manifest)["inputs"]]
    per_head: dict[str, dict] = {
        name: {"max_abs_error": 0.0, "mean_abs_error": None, "cases": {}} for name in manifest.output_head_names
    }
    classification_heads = {
        "scene_class_logits",
        "subjectness_roi_agreement_logits",
        "issue_logits",
        "action_utility_logits",
    }
    for case in cases:
        tensors = _torch_inputs(case, manifest)
        with torch.no_grad():
            reference = wrapper(*tensors)
        provider = {name: case[name] for name in order}
        predictions = coreml_model.predict(provider)
        for name, expected in zip(manifest.output_head_names, reference):
            expected_array = expected.detach().cpu().numpy()
            actual_array = np.asarray(predictions[name], dtype=np.float32)
            if list(actual_array.shape) != list(expected_array.shape):
                raise ContractError(
                    f"head {name!r} shape mismatch: pytorch {expected_array.shape} vs coreml {actual_array.shape}"
                )
            difference = np.abs(expected_array - actual_array)
            maximum = float(difference.max(initial=0.0))
            entry = {
                "max_abs_error": maximum,
                "mean_abs_error": float(difference.mean()),
                "worst_index": [int(index) for index in np.unravel_index(int(difference.argmax()), difference.shape)],
                "worst_pytorch": float(expected_array.reshape(-1)[int(difference.argmax())]),
                "worst_coreml": float(actual_array.reshape(-1)[int(difference.argmax())]),
                "finite": bool(np.isfinite(actual_array).all() and np.isfinite(expected_array).all()),
                "passed": bool(np.isfinite(actual_array).all() and np.isfinite(expected_array).all()
                    and np.allclose(actual_array, expected_array, atol=PARITY_ATOL, rtol=PARITY_RTOL)),
            }
            if name in classification_heads:
                entry["argmax_match"] = bool(int(expected_array.argmax()) == int(actual_array.argmax()))
                entry["argmax_pytorch"] = int(expected_array.argmax())
                entry["argmax_coreml"] = int(actual_array.argmax())
            value_range = manifest.output_head_specs[name].get("value_range")
            if value_range is not None:
                low, high = value_range
                entry["coreml_in_declared_range"] = bool(
                    actual_array.min() >= low - 1e-4 and actual_array.max() <= high + 1e-4
                )
            per_head[name]["cases"][case["case_id"]] = entry
            per_head[name]["max_abs_error"] = max(per_head[name]["max_abs_error"], maximum)
            previous = per_head[name]["mean_abs_error"]
            per_head[name]["mean_abs_error"] = (
                entry["mean_abs_error"] if previous is None else max(previous, entry["mean_abs_error"])
            )

    # Intent wiring check: the separate input must actually move the
    # intent-conditioned heads, identically in both implementations.  The two
    # cases below differ only at intent_features (explicit natural vs unknown).
    case_by_id = {case["case_id"]: case for case in cases}
    intent_sensitivity: dict[str, dict] = {}
    if "explicit_natural_roi_present" in case_by_id and "unknown_intent_roi_present" in case_by_id:
        known_case = case_by_id["explicit_natural_roi_present"]
        unknown_case = case_by_id["unknown_intent_roi_present"]
        with torch.no_grad():
            left = wrapper(*_torch_inputs(known_case, manifest))
            right = wrapper(*_torch_inputs(unknown_case, manifest))
        left_coreml = coreml_model.predict({key: known_case[key] for key in order})
        right_coreml = coreml_model.predict({key: unknown_case[key] for key in order})
        for name in manifest.intent_conditioned_heads:
            index = manifest.output_head_names.index(name)
            pytorch_delta = float(
                np.abs(left[index].detach().cpu().numpy() - right[index].detach().cpu().numpy()).max(initial=0.0)
            )
            coreml_delta = float(
                np.abs(
                    np.asarray(left_coreml[name], dtype=np.float32)
                    - np.asarray(right_coreml[name], dtype=np.float32)
                ).max(initial=0.0)
            )
            intent_sensitivity[name] = {
                "pytorch_intent_delta": pytorch_delta,
                "coreml_intent_delta": coreml_delta,
                "both_respond_to_intent": bool(pytorch_delta > 0.0 and coreml_delta > 0.0),
            }

    info_threshold = 5e-2
    all_heads_finite = all(
        case_entry["finite"]
        for name in manifest.output_head_names
        for case_entry in per_head[name]["cases"].values()
    )
    return {
        "per_head": per_head,
        "overall_max_abs_error": max(entry["max_abs_error"] for entry in per_head.values()),
        "within_fp16_expectation": all(entry["max_abs_error"] <= info_threshold for entry in per_head.values()),
        "informational_threshold": info_threshold,
        "all_heads_finite": all_heads_finite,
        "passed": all(row["passed"] for entry in per_head.values() for row in entry["cases"].values()),
        "atol": PARITY_ATOL,
        "rtol": PARITY_RTOL,
        "intent_sensitivity": intent_sensitivity,
        "cases": [case["case_id"] for case in cases],
    }


def _assert_output_path_allowed(output: Path) -> Path:
    resolved = output.resolve()
    app_root = APP_TARGET_ROOT.resolve()
    if resolved == app_root or app_root in resolved.parents:
        raise ValueError(
            f"refusing to write a Core ML package inside the app target tree: {resolved}"
        )
    if resolved.suffix != ".mlpackage":
        raise ValueError("--output must end in .mlpackage")
    return resolved


def _remove_existing(output: Path) -> None:
    if output.is_dir():
        shutil.rmtree(output)
    elif output.exists():
        output.unlink()
    for sidecar in (parity_path(output), receipt_path(output)):
        if sidecar.exists():
            sidecar.unlink()


def parity_path(output: Path) -> Path:
    return output.with_name(f"{output.name}.parity.json")


def receipt_path(output: Path) -> Path:
    return output.with_name(f"{output.name}.provenance.json")


def export(
    output: Path,
    *,
    candidate_id: str | None = None,
    seed: int = 20260913,
    manifest_path: Path = V2_MANIFEST_PATH,
    overwrite: bool = False,
    checkpoint_path: Path | None = None,
    training_config_path: Path | None = None,
    required_components: dict | None = None,
) -> dict:
    import coremltools as ct

    output = _assert_output_path_allowed(output)
    manifest_path = manifest_path.resolve()
    manifest_sha = sha256_file(manifest_path)
    manifest = SETCompositionNetV2Manifest.load(manifest_path)
    expected = expected_coreml_io(manifest)

    if (checkpoint_path is None) != (training_config_path is None):
        raise ValueError("checkpoint and training config must be supplied together")
    checkpoint_origin = None
    if checkpoint_path is not None:
        model, weight_sha, parameter_count, checkpoint_origin = load_checkpoint_model(
            checkpoint_path, training_config_path, manifest, required_components=required_components)
        if candidate_id is not None and candidate_id != checkpoint_origin["candidate_id"]:
            raise ContractError("requested candidate conflicts with checkpoint architecture")
        candidate_id = checkpoint_origin["candidate_id"]
        component_evidence = checkpoint_origin["component_evidence"]
        weights_origin = "selected state of explicit records checkpoint; research export only"
    else:
        candidate_id = candidate_id or DEFAULT_CANDIDATE_ID
        model, weight_sha, parameter_count = build_untrained_model(candidate_id, manifest, seed)
        component_evidence = export_metadata(new_supervision(manifest, {"initialization_sha256":weight_sha}),
            manifest, required_components=required_components)
        weights_origin = "deterministically seeded random initialization; no training performed"
    provenance_flags = dict(PROVENANCE_FLAGS, research_only="true")
    if checkpoint_origin is not None:
        provenance_flags.update(artifact_kind="research_checkpoint_export_path_validation", untrained_weights="false",
            blocked_on="independent data/rights, component coverage, quality, calibration and runtime admission")

    if output.exists() or parity_path(output).exists() or receipt_path(output).exists():
        if not overwrite:
            raise FileExistsError(f"output already exists (pass --overwrite): {output}")
        _remove_existing(output)
    output.parent.mkdir(parents=True, exist_ok=True)

    wrapper = _V2ExportWrapper(model, manifest.output_head_names).eval()
    cases = parity_cases(manifest, seed)
    trace_inputs = _torch_inputs(cases[0], manifest)
    with torch.no_grad(), warnings.catch_warnings():
        warnings.simplefilter("ignore", torch.jit.TracerWarning)
        traced = torch.jit.trace(wrapper, trace_inputs, strict=True)

    with tempfile.TemporaryDirectory(prefix="setos-coreml-v2-", dir=output.parent) as directory:
        temporary_package = Path(directory) / output.name
        converted = ct.convert(
            traced,
            source="pytorch",
            convert_to="mlprogram",
            minimum_deployment_target=ct.target.iOS17,
            compute_precision=ct.precision.FLOAT16,
            compute_units=ct.ComputeUnit.CPU_ONLY,
            inputs=[
                ct.TensorType(name=entry["name"], shape=tuple(entry["shape"]), dtype=np.float32)
                for entry in expected["inputs"]
            ],
            outputs=[
                ct.TensorType(name=entry["name"], dtype=np.float32) for entry in expected["outputs"]
            ],
        )
        converted.author = "SET OS tooling"
        converted.short_description = (
            "RESEARCH/TOOLING ONLY: SETCompositionNet-v2 export-path validation. "
            "Not a release candidate / not a quality claim."
        )
        converted.version = f"v2-{'research-checkpoint' if checkpoint_origin else 'tooling-untrained'}-{candidate_id}"
        converted.user_defined_metadata.update(
            {
                **{f"com.setos.{key}":value for key,value in provenance_flags.items()},
                "com.setos.candidate_id": candidate_id,
                "com.setos.contract_manifest_path": str(manifest_path.relative_to(REPO_ROOT)),
                "com.setos.contract_manifest_sha256": manifest_sha,
                "com.setos.weights_sha256": weight_sha,
                "com.setos.weights_origin": weights_origin,
                "com.setos.component_evidence": json.dumps(component_evidence, sort_keys=True, separators=(",", ":")),
                "com.setos.source_checkpoint_sha256": checkpoint_origin["checkpoint_sha256"] if checkpoint_origin else "none",
                "com.setos.weight_parameter_count": str(parameter_count),
                "com.setos.contract_version": manifest.raw["contract_version"],
                "com.setos.input_contract_version": manifest.raw["input_contract_version"],
                "com.setos.preprocessing_version": manifest.raw["preprocessing_version"],
                "com.setos.output_contract_version": manifest.raw["output_contract_version"],
                "com.setos.intent_feature_name": "intent_features",
                "com.setos.intent_feature_count": str(manifest.intent_feature_count),
                "com.setos.intent_order": ",".join(manifest.intent_order),
                "com.setos.output_head_order": ",".join(manifest.output_head_names),
                "com.setos.coremltools": ct.__version__,
                "com.setos.torch": torch.__version__,
            }
        )
        converted.save(str(temporary_package))

        coreml_model = ct.models.MLModel(str(temporary_package), compute_units=ct.ComputeUnit.CPU_ONLY)
        exported_io = coreml_io_from_description(coreml_model.get_spec().description)
        contract = validate_contract(exported_io, manifest)
        parity = parity_report(wrapper, coreml_model, manifest, cases)
        if not parity["passed"]:
            raise ContractError("PyTorch/Core ML parity failed fixed tolerances; package not published")
        package_sha256 = sha256_tree(temporary_package)
        os.replace(temporary_package, output)

    package = {
        "path": str(output),
        "tree_sha256": package_sha256,
        "format": "mlprogram",
        "precision": "float16",
        "minimum_deployment_target": "iOS17",
        "compute_units_for_parity": "CPU_ONLY",
    }
    provenance = {
        "schema_id": "camera-v2-coreml-research-export-v2" if checkpoint_origin else "camera-v2-coreml-tooling-export-v1",
        "status": "tooling_path_validated",
        **provenance_flags,
        "human_gold": False,
        "release_admissible": False,
        "admitted_data": "not verified by research exporter" if checkpoint_origin else "none (M03/M04 blocked)",
        "candidate_id": candidate_id,
        "weights_sha256": weight_sha,
        "weights_origin": weights_origin,
        "component_evidence": component_evidence,
        "checkpoint_provenance": checkpoint_origin,
        "weight_parameter_count": parameter_count,
        "seed": seed,
        "parity_seed": seed,
        "contract_manifest": {
            "path": str(manifest_path.relative_to(REPO_ROOT)),
            "sha256": manifest_sha,
            "contract_version": manifest.raw["contract_version"],
        },
        "source_model_sha256": sha256_file(REPO_ROOT / "ml/camera_coach/models/set_composition_net_v2.py"),
        "exporter_sha256": sha256_file(Path(__file__).resolve()),
        "mlpackage": package,
        "contract_validation": contract,
        "inputs": exported_io["inputs"],
        "outputs": exported_io["outputs"],
        "output_head_order": list(manifest.output_head_names),
        "intent_features": {
            "name": "intent_features",
            "count": manifest.intent_feature_count,
            "order": list(manifest.intent_order),
            "separate_input": True,
        },
        "coremltools": ct.__version__,
        "torch": torch.__version__,
        "numpy": np.__version__,
    }
    write_json(parity_path(output), parity)
    write_json(receipt_path(output), provenance)
    return {
        "mlpackage": str(output),
        "tree_sha256": package_sha256,
        "contract_passed": contract["passed"],
        "overall_max_abs_error": parity["overall_max_abs_error"],
        "provenance": str(receipt_path(output)),
        "parity": str(parity_path(output)),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_DIR / DEFAULT_OUTPUT_NAME)
    parser.add_argument("--candidate", choices=sorted(CANDIDATE_TYPES))
    parser.add_argument("--seed", type=int, default=20260913)
    parser.add_argument("--manifest", type=Path, default=V2_MANIFEST_PATH)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--checkpoint", type=Path)
    parser.add_argument("--training-config", type=Path)
    parser.add_argument("--require-component", action="append", default=[], metavar="HEAD:NAME")
    args = parser.parse_args()
    required = {}
    for component in args.require_component:
        if ":" not in component:
            parser.error("--require-component must be HEAD:NAME")
        head, name = component.split(":", 1)
        required.setdefault(head, []).append(name)
    if args.checkpoint is not None and args.output == DEFAULT_OUTPUT_DIR / DEFAULT_OUTPUT_NAME:
        parser.error("checkpoint export requires an explicit --output")
    summary = export(
        args.output,
        candidate_id=args.candidate,
        seed=args.seed,
        manifest_path=args.manifest,
        overwrite=args.overwrite,
        checkpoint_path=args.checkpoint,
        training_config_path=args.training_config,
        required_components=required,
    )
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
