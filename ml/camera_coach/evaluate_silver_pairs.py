#!/usr/bin/env python3
"""Research-only evaluation of a Stage-2 silver checkpoint on silver pairs.

Loads a ``camera-silver-actions-stage2-checkpoint-v1`` checkpoint and scores a
generator-produced pairs root (``pairs.jsonl`` + ``receipt.json``). Only the
three silver-supervised heads are measured: ``issue_logits`` (per-component
confusion matrix, accuracy and balanced accuracy), ``action_utility_logits``
(masked top-1 hit) and ``continuous_target_deltas`` (masked MAE). The same
records define a no-op baseline (all-negative issues, zero deltas) so the
numbers cannot be quoted without their reference.

This is fit-quality evidence for a research checkpoint. It is not a release
gate, not a calibration source and not a claim that the model beats the
analytic geometry path that produced the targets.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import platform
import sys
import time

import torch
from torch import Tensor

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from ml.camera_coach.models import CandidateA, SETCompositionNetManifest  # noqa: E402
from ml.camera_coach.train_silver_actions import (  # noqa: E402
    _load_image_inputs,
    _record_from_row_without_image,
    _stack_batch,
)

CHECKPOINT_SCHEMA = "camera-silver-actions-stage2-checkpoint-v1"


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_pairs_root(pairs_root: Path, contract: SETCompositionNetManifest) -> list:
    manifest_path = pairs_root / "pairs.jsonl"
    receipt_path = pairs_root / "receipt.json"
    receipt = json.loads(receipt_path.read_text())
    output = receipt.get("output_manifest") or {}
    if output.get("path") != "pairs.jsonl" or output.get("sha256") != _sha256_file(manifest_path):
        raise ValueError(f"pair receipt does not attest pairs.jsonl in {pairs_root}")
    records = []
    for line in manifest_path.read_text().splitlines():
        if not line.strip():
            continue
        row = json.loads(line)
        records.append(_record_from_row_without_image(row, pairs_root, contract, root_index=0))
    return records


def load_model(checkpoint_path: Path, device: torch.device) -> tuple[CandidateA, dict]:
    payload = torch.load(checkpoint_path, map_location="cpu", weights_only=False)
    schema_id = payload.get("schema_id")
    if schema_id == CHECKPOINT_SCHEMA:
        state_dict = payload["model_state"]
    elif schema_id == "camera-silver-actions-stage2-artifact-v1":
        state_dict = payload["state_dict"]
    else:
        raise ValueError("unsupported checkpoint schema")
    if payload.get("release_admissible") is not False or payload.get("research_only") is not True:
        raise ValueError("checkpoint crossed the research boundary")
    contract = SETCompositionNetManifest.load()
    model = CandidateA(contract).to(device)
    model.load_state_dict(state_dict, strict=True)
    model.eval()
    return model, {
        "epoch": payload.get("epoch"),
        "schema_id": schema_id,
    }


def evaluate(model: CandidateA, records: list, device: torch.device, batch_size: int = 8) -> dict:
    contract = SETCompositionNetManifest.load()
    issue_names = contract.output_head_specs["issue_logits"]["ordered_names"]
    action_names = contract.output_head_specs["action_utility_logits"]["ordered_names"]
    delta_names = contract.output_head_specs["continuous_target_deltas"]["ordered_names"]

    confusion: dict[int, Counter] = {}
    action_hit = 0
    action_total = 0
    action_rows_predicting_any_positive = 0
    delta_abs_sum: dict[int, float] = {}
    delta_count: dict[int, int] = {}
    noop_delta_abs_sum: dict[int, float] = {}
    noop_delta_count: dict[int, int] = {}

    with torch.no_grad():
        for start in range(0, len(records), batch_size):
            batch = records[start:start + batch_size]
            inputs, targets, masks = _stack_batch(batch, device)
            outputs = model(inputs)
            issue_probs = torch.sigmoid(outputs["issue_logits"])
            action_scores = outputs["action_utility_logits"]
            deltas = outputs["continuous_target_deltas"]

            for row, record in enumerate(batch):
                for column, (value, mask) in enumerate(zip(record.issue_values, record.issue_mask)):
                    if not mask:
                        continue
                    actual = int(value)
                    predicted = int(issue_probs[row, column].item() >= 0.5)
                    confusion.setdefault(column, [[0, 0], [0, 0]])  # [actual][predicted]
                    confusion[column][actual][predicted] += 1

                positives = [index for index, (value, mask) in
                             enumerate(zip(record.action_values, record.action_mask)) if mask and value == 1]
                if positives:
                    action_total += 1
                    masked = action_scores[row].clone()
                    unavailable = torch.tensor([0.0 if m else -1e9 for m in record.action_mask],
                                               device=masked.device)
                    masked = masked + unavailable
                    if int(torch.argmax(masked).item()) in positives:
                        action_hit += 1
                if any(action_scores[row][index].item() > 0 for index, mask in
                       enumerate(record.action_mask) if mask):
                    action_rows_predicting_any_positive += 1

                for column, (value, mask) in enumerate(zip(record.delta_values, record.delta_mask)):
                    if not mask:
                        continue
                    error = abs(deltas[row][column].item() - float(value))
                    delta_abs_sum[column] = delta_abs_sum.get(column, 0.0) + error
                    delta_count[column] = delta_count.get(column, 0) + 1
                    noop_delta_abs_sum[column] = noop_delta_abs_sum.get(column, 0.0) + abs(float(value))
                    noop_delta_count[column] = noop_delta_count.get(column, 0) + 1

    issue_report = {}
    for column, cells in sorted(confusion.items()):
        tn, fp = cells[0]
        fn, tp = cells[1]
        total = tn + fp + fn + tp
        sensitivity = tp / (tp + fn) if (tp + fn) else None
        specificity = tn / (tn + fp) if (tn + fp) else None
        balanced = 0.5 * (sensitivity + specificity) if sensitivity is not None and specificity is not None else None
        issue_report[issue_names[column]] = {
            "n": total,
            "true_negative": tn, "false_positive": fp, "false_negative": fn, "true_positive": tp,
            "accuracy": (tp + tn) / total,
            "balanced_accuracy": balanced,
            "noop_baseline_accuracy": (tn + fp) / total,
        }

    delta_report = {}
    for column, name in enumerate(delta_names):
        count = delta_count.get(column, 0)
        noop_count = noop_delta_count.get(column, 0)
        if count:
            delta_report[name] = {
                "model_mae": delta_abs_sum[column] / count,
                "noop_baseline_mae": (noop_delta_abs_sum[column] / noop_count) if noop_count else None,
                "n": count,
            }

    return {
        "records": len(records),
        "issue": issue_report,
        "action_top1_hit": action_hit / action_total if action_total else None,
        "action_records_with_positive": action_total,
        "action_rows_predicting_any_positive": action_rows_predicting_any_positive,
        "action_top1_hit_noop_baseline": 0.0 if action_total else None,
        "delta": delta_report,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--pairs-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--device", default="cpu", choices=("cpu", "mps"))
    parser.add_argument("--batch-size", type=int, default=8)
    args = parser.parse_args()

    if args.output.exists():
        raise SystemExit("refusing to overwrite an existing evaluation output")
    device = torch.device(args.device)
    model, checkpoint_meta = load_model(args.checkpoint, device)
    contract = SETCompositionNetManifest.load()
    records = load_pairs_root(args.pairs_root, contract)
    started = time.monotonic()
    metrics = evaluate(model, records, device, batch_size=args.batch_size)
    result = {
        "schema_id": "camera-silver-pair-evaluation-v1",
        "research_only": True,
        "human_gold": False,
        "release_admissible": False,
        "checkpoint_path": str(args.checkpoint),
        "checkpoint_sha256": _sha256_file(args.checkpoint),
        "checkpoint": checkpoint_meta,
        "pairs_root": str(args.pairs_root),
        "pairs_manifest_sha256": _sha256_file(args.pairs_root / "pairs.jsonl"),
        "pairs_receipt_sha256": _sha256_file(args.pairs_root / "receipt.json"),
        "contract_sha256": _sha256_file(REPO_ROOT / "ml/camera_coach/contracts/set_composition_net_v1.json"),
        "device": args.device,
        "torch": torch.__version__,
        "python": platform.python_version(),
        "elapsed_seconds": time.monotonic() - started,
        "metrics": metrics,
        "scope": "Fit-quality evidence on silver corruption pairs; no release, calibration or analytic-baseline-superiority claim.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x") as stream:
        json.dump(result, stream, indent=2, sort_keys=True, allow_nan=False)
        stream.write("\n")
    print(json.dumps({"status": "ok", "records": metrics["records"],
                      "action_top1_hit": metrics["action_top1_hit"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
