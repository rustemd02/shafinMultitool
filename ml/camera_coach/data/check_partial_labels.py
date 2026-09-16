"""Bounded real-record gradient check, using the existing v2 model and loss.

python3 -B -m ml.camera_coach.data.check_partial_labels --intake PATH --out PATH
No model selection, optimizer step, provider call or release admission occurs.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import platform
import time

import torch

from .training_records import (PARTIAL_LABEL_SCHEMA_VERSION, load_records, stack_inputs,
    stack_targets, stack_masks, intent_head_mask)
from ..models.set_composition_net_v2 import SETCompositionNetV2CandidateB, SETCompositionNetV2Manifest
from ..losses import DIRECT_LOSS_HEADS, LossConfig, compute_multitask_loss


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def check(intake: Path, out: Path, seed: int = 20260916):
    if out.exists():
        raise ValueError("Refusing to overwrite a gradient-check artifact")
    source = json.loads((intake / "receipt.json").read_text())
    records = load_records(intake / "records.jsonl", source["records_sha256"], admission="non_admitted_research")
    if any(record.schema_version != PARTIAL_LABEL_SCHEMA_VERSION or record.split == "locked_test" for record in records):
        raise ValueError("This check admits only v2.1 partial research records outside locked test")
    if len(records) != source["records"]:
        raise ValueError("Receipt and record count disagree")
    for name in ("lineage", "split-assessment"):
        filename = "lineage.jsonl" if name == "lineage" else "split-assessment.json"
        if sha256(intake / filename) != source[name.replace("-", "_") + "_sha256"]:
            raise ValueError("Intake evidence hash mismatch")
    split = json.loads((intake / "split-assessment.json").read_text())
    if not split["usable_for_gradient_probe"]:
        raise ValueError("Unresolved split conflict")
    train = [r for r in records if r.split == "train" and r.masks["issue_logits"].any()]
    if not train:
        raise ValueError("No supervised train records; empty gradient check refused")
    torch.set_num_threads(1)
    torch.manual_seed(seed)
    torch.use_deterministic_algorithms(True)
    contract = SETCompositionNetV2Manifest.load()
    model = SETCompositionNetV2CandidateB(contract).cpu().train()
    root = Path(__file__).resolve().parents[3]
    loss_path = root / "ml/camera_coach/configs/loss_weights.json"
    config = LossConfig.from_file(loss_path)
    active = {head: 0 for head in DIRECT_LOSS_HEADS}
    output_gradient_l1 = {head: 0.0 for head in DIRECT_LOSS_HEADS}
    issue_gradient_l1 = torch.zeros(len(contract.output_head_specs["issue_logits"]["ordered_names"]))
    parameter_gradient_l1 = 0.0
    batches = []
    started = time.perf_counter()
    for index in range(0, len(train), 2):
        batch = train[index:index + 2]
        model.zero_grad(set_to_none=True)
        inputs = stack_inputs(batch, contract)
        targets, masks = stack_targets(batch), stack_masks(batch)
        outputs = model(inputs)
        for head in DIRECT_LOSS_HEADS:
            outputs[head].retain_grad()
        result = compute_multitask_loss(outputs, targets, masks=masks,
                                       intent_mask=intent_head_mask(batch, contract), config=config)
        if not torch.isfinite(result.total) or result.total.item() <= 0:
            raise ValueError("Real labeled batch produced empty/non-finite loss")
        result.total.backward()
        for head in DIRECT_LOSS_HEADS:
            gradient = outputs[head].grad
            if gradient is None or not torch.isfinite(gradient).all():
                raise ValueError("Missing/non-finite output gradient: " + head)
            mask = masks[head]
            # Categorical scene has a [B,1] label mask but [B,8] logits.
            if mask.shape != gradient.shape:
                mask = mask.expand_as(gradient)
            if torch.any(gradient[mask == 0] != 0):
                raise ValueError("A masked label received a gradient: " + head)
            active[head] += int(masks[head].sum())
            output_gradient_l1[head] += float(gradient.abs().sum())
        if torch.any(outputs["issue_logits"].grad[masks["issue_logits"] == 1] == 0):
            raise ValueError("An active issue target received no gradient")
        issue_gradient_l1 += outputs["issue_logits"].grad.abs().sum(dim=0).detach()
        for parameter in model.parameters():
            if parameter.grad is not None:
                if not torch.isfinite(parameter.grad).all():
                    raise ValueError("Non-finite model parameter gradient")
                parameter_gradient_l1 += float(parameter.grad.abs().sum())
        batches.append(dict(record_ids=[r.record_id for r in batch], loss=float(result.total.detach()),
                            known_issue_targets=int(masks["issue_logits"].sum())))
    if active["issue_logits"] == 0 or parameter_gradient_l1 <= 0:
        raise ValueError("No actual issue supervision reached model parameters")
    if any(value != 0 for head, value in output_gradient_l1.items() if head != "issue_logits"):
        raise ValueError("Unsupported head received a gradient")
    receipt = dict(schema_id="camera-partial-label-gradient-check-v1", status="pass",
        source_receipt_sha256=sha256(intake / "receipt.json"), records_sha256=source["records_sha256"],
        seed=seed, candidate=model.candidate_id, initial_weights="deterministic random initialization; no trained checkpoint loaded",
        device="cpu", python=platform.python_version(), torch=torch.__version__,
        records_loaded=len(records), supervised_train_records=len(train),
        fully_masked_train_records=sum(r.split == "train" for r in records) - len(train),
        validation_records_used_for_backward=0, optimizer_steps=0, batches=batches,
        active_targets=active, output_gradient_l1=output_gradient_l1,
        issue_gradient_l1=dict(zip(contract.output_head_specs["issue_logits"]["ordered_names"], issue_gradient_l1.tolist())),
        parameter_gradient_l1=parameter_gradient_l1, masked_gradient_violations=0,
        elapsed_seconds=time.perf_counter() - started,
        source_code_sha256={name: sha256(root / name) for name in (
            "ml/camera_coach/data/check_partial_labels.py", "ml/camera_coach/data/training_records.py",
            "ml/camera_coach/models/set_composition_net_v2.py", "ml/camera_coach/losses.py",
            "ml/camera_coach/configs/loss_weights.json", "ml/camera_coach/contracts/set_composition_net_v2.json")},
        research_only=True, human_gold=False, release_admissible=False, training_ready=False,
        meaning="Loader/preprocessing/loss/backward integrity on real reviewed photos; not fit, accuracy, calibration or release evidence")
    out.mkdir(parents=True, exist_ok=False)
    with (out / "receipt.json").open("x") as stream:
        json.dump(receipt, stream, indent=2, allow_nan=False); stream.write("\n")
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--intake", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    receipt = check(args.intake, args.out)
    print(json.dumps({key: receipt[key] for key in (
        "status", "records_loaded", "supervised_train_records", "active_targets", "masked_gradient_violations", "optimizer_steps")}, sort_keys=True))


if __name__ == "__main__":
    main()
