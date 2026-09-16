#!/usr/bin/env python3
"""Convert a Stage-2 silver Camera Coach artifact to a research-only FP16 mlprogram."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

import coremltools as ct
import numpy as np
import torch
from torch import Tensor, nn


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from ml.camera_coach.models import CandidateA, SETCompositionNetManifest  # noqa: E402
from ml.camera_coach.component_supervision import checkpoint_supervision, export_metadata  # noqa: E402


TRAINABLE_HEADS = ["issue_logits", "action_utility_logits", "continuous_target_deltas"]
INPUTS = (
    ("full_frame_rgb", (1, 3, 320, 320)),
    ("subject_crop_rgb", (1, 3, 192, 192)),
    ("roi_normalized_xywh", (1, 4)),
    ("roi_mask", (1, 1, 320, 320)),
    ("scalar_features", (1, 40)),
    ("missing_feature_mask", (1, 40)),
)


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


def write_json(path: Path, value: dict) -> None:
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def load_model(artifact_path: Path, receipt_path: Path) -> tuple[nn.Module, dict, dict]:
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    expected_boundary = {
        "contract": REPO_ROOT / "ml/camera_coach/contracts/set_composition_net_v1.json",
        "losses": REPO_ROOT / "ml/camera_coach/losses.py",
        "model": REPO_ROOT / "ml/camera_coach/models/set_composition_net.py",
        "pair_schema": REPO_ROOT / "datasets/camera-coach/v1/silver-action-pair-schema.json",
        "preprocessing": REPO_ROOT / "ml/camera_coach/data/preprocessing.py",
        "runner": REPO_ROOT / "ml/camera_coach/train_silver_actions.py",
    }
    if receipt.get("status") != "complete" or receipt.get("research_only") is not True \
            or receipt.get("human_gold") is not False or receipt.get("release_admissible") is not False \
            or receipt.get("trainable_heads") != TRAINABLE_HEADS:
        raise ValueError("receipt is not the completed research-only Stage-2 three-head contract")
    final = receipt.get("final_artifact", {})
    if final.get("path") != artifact_path.name or final.get("sha256") != sha256_file(artifact_path):
        raise ValueError("candidate artifact does not match the Stage-2 receipt")
    if any(sha256_file(path) != receipt.get("code_boundary", {}).get(name) for name, path in expected_boundary.items()):
        raise ValueError("current conversion sources do not match the Stage-2 code boundary")

    payload = torch.load(artifact_path, map_location="cpu", weights_only=True)
    if payload.get("research_only") is not True or payload.get("human_gold") is not False \
            or payload.get("release_admissible") is not False or payload.get("trainable_heads") != TRAINABLE_HEADS \
            or payload.get("model_contract_sha256") != receipt.get("model_contract_sha256"):
        raise ValueError("candidate metadata does not match the research-only receipt")
    state_dict = payload.get("state_dict")
    if not isinstance(state_dict, dict) or any(not torch.isfinite(value).all() for value in state_dict.values()):
        raise ValueError("candidate state_dict is missing or contains non-finite tensors")
    contract = SETCompositionNetManifest.load(expected_boundary["contract"])
    model = CandidateA(contract).eval()
    model.load_state_dict(state_dict, strict=True)
    return model, receipt, payload


class ExportModel(nn.Module):
    def __init__(self, model: nn.Module, output_names: tuple[str, ...]):
        super().__init__()
        self.model = model
        self.output_names = output_names

    def forward(self, full: Tensor, crop: Tensor, roi: Tensor, mask: Tensor, scalars: Tensor, missing: Tensor):
        outputs = self.model(full, crop, roi, mask, scalars, missing)
        return tuple(outputs[name] for name in self.output_names)


def parity_inputs() -> tuple[np.ndarray, ...]:
    rng = np.random.default_rng(20260911)
    full = rng.random(INPUTS[0][1], dtype=np.float32)
    crop = rng.random(INPUTS[1][1], dtype=np.float32)
    roi = np.array([[0.2, 0.25, 0.4, 0.5]], dtype=np.float32)
    mask = np.zeros(INPUTS[3][1], dtype=np.float32)
    mask[:, :, 80:240, 64:192] = 1.0
    scalars = np.zeros(INPUTS[4][1], dtype=np.float32)
    missing = np.ones(INPUTS[5][1], dtype=np.float32)
    return full, crop, roi, mask, scalars, missing


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact", type=Path, required=True)
    parser.add_argument("--receipt", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--atol", type=float, default=0.005)
    parser.add_argument("--rtol", type=float, default=0.01)
    args = parser.parse_args()
    if args.output.suffix != ".mlpackage":
        raise ValueError("--output must end in .mlpackage")
    parity_path = args.output.with_name(f"{args.output.name}.parity.json")
    conversion_path = args.output.with_name(f"{args.output.name}.conversion-receipt.json")
    if any(path.exists() for path in (args.output, parity_path, conversion_path)):
        raise FileExistsError("conversion output already exists; choose a new path")
    args.output.parent.mkdir(parents=True, exist_ok=True)

    model, receipt, payload = load_model(args.artifact.resolve(), args.receipt.resolve())
    output_names = tuple(model.contract.output_head_names)
    component_evidence = export_metadata(checkpoint_supervision(payload, model.contract), model.contract)
    arrays = parity_inputs()
    tensors = tuple(torch.from_numpy(value) for value in arrays)
    wrapper = ExportModel(model, output_names).eval()
    with torch.no_grad():
        reference = wrapper(*tensors)
        traced = torch.jit.trace(wrapper, tensors, strict=True)

    with tempfile.TemporaryDirectory(prefix="setos-coreml-", dir=args.output.parent) as directory:
        temporary_package = Path(directory) / args.output.name
        converted = ct.convert(
            traced,
            source="pytorch",
            convert_to="mlprogram",
            minimum_deployment_target=ct.target.iOS17,
            compute_precision=ct.precision.FLOAT16,
            compute_units=ct.ComputeUnit.CPU_ONLY,
            inputs=[ct.TensorType(name=name, shape=shape, dtype=np.float32) for name, shape in INPUTS],
            outputs=[ct.TensorType(name=name, dtype=np.float32) for name in output_names],
        )
        converted.author = "SET OS research"
        converted.short_description = "Research-only Stage-2 silver-action SETCompositionNet; not release admissible"
        converted.version = "stage2-silver-v1"
        converted.user_defined_metadata.update({
            "com.setos.research_only": "true",
            "com.setos.human_gold": "false",
            "com.setos.release_admissible": "false",
            "com.setos.trainable_heads": ",".join(TRAINABLE_HEADS),
            "com.setos.component_evidence": json.dumps(component_evidence, sort_keys=True, separators=(",", ":")),
            "com.setos.model_contract_sha256": receipt["model_contract_sha256"],
            "com.setos.source_artifact_sha256": receipt["final_artifact"]["sha256"],
            "com.setos.preprocessing_version": model.contract.raw["preprocessing_version"],
            "com.setos.output_contract_version": model.contract.raw["output_contract_version"],
            "com.setos.calibration": "absent",
            "com.setos.input_validation": "external_required",
        })
        converted.save(str(temporary_package))

        coreml_model = ct.models.MLModel(str(temporary_package), compute_units=ct.ComputeUnit.CPU_ONLY)
        predictions = coreml_model.predict(dict(zip((name for name, _ in INPUTS), arrays)))
        per_output = {}
        for name, expected in zip(output_names, reference):
            expected_array = expected.detach().cpu().numpy()
            actual_array = np.asarray(predictions[name])
            difference = np.abs(expected_array - actual_array)
            worst = np.unravel_index(int(difference.argmax()), difference.shape)
            passed = bool(np.allclose(expected_array, actual_array, atol=args.atol, rtol=args.rtol))
            per_output[name] = {
                "shape": list(actual_array.shape),
                "max_abs_error": float(difference.max(initial=0.0)),
                "mean_abs_error": float(difference.mean()),
                "worst_index": [int(index) for index in worst],
                "worst_pytorch": float(expected_array[worst]),
                "worst_coreml": float(actual_array[worst]),
                "argmax_match": bool(expected_array.argmax() == actual_array.argmax()),
                "passed": passed,
            }
        failed = {name: item for name, item in per_output.items() if not item["passed"]}
        if failed:
            raise RuntimeError(f"PyTorch/Core ML parity failed: {json.dumps(failed, sort_keys=True)}")
        package_sha256 = sha256_tree(temporary_package)
        os.replace(temporary_package, args.output)

    parity = {
        "schema_id": "camera-stage2-research-coreml-parity-v1",
        "seed": 20260911,
        "atol": args.atol,
        "rtol": args.rtol,
        "outputs": per_output,
        "passed": True,
    }
    conversion = {
        "schema_id": "camera-stage2-research-coreml-conversion-v1",
        "research_only": True,
        "human_gold": False,
        "release_admissible": False,
        "source_artifact": {"path": str(args.artifact.resolve()), "sha256": receipt["final_artifact"]["sha256"]},
        "source_receipt_sha256": sha256_file(args.receipt.resolve()),
        "converter_sha256": sha256_file(Path(__file__).resolve()),
        "mlpackage": {"path": str(args.output.resolve()), "tree_sha256": package_sha256},
        "format": "mlprogram",
        "precision": "float16",
        "minimum_deployment_target": "iOS17",
        "compute_units_for_parity": "CPU_ONLY",
        "inputs": {name: list(shape) for name, shape in INPUTS},
        "logical_image_layout": "HWC per frozen contract",
        "coreml_transport_image_layout": "NCHW with leading batch dimension",
        "input_validation": "external_required; traced Python trust-boundary guards are not embedded in the mlprogram",
        "outputs": list(output_names),
        "trainable_heads": payload["trainable_heads"],
        "component_evidence": component_evidence,
        "untrained_outputs_present": [name for name in output_names if name not in TRAINABLE_HEADS],
        "calibration": "absent",
        "parity_report": str(parity_path.resolve()),
        "coremltools": ct.__version__,
        "torch": torch.__version__,
    }
    write_json(parity_path, parity)
    write_json(conversion_path, conversion)
    print(json.dumps({"mlpackage": str(args.output), "tree_sha256": package_sha256, "parity": "pass"}, sort_keys=True))


if __name__ == "__main__":
    main()
