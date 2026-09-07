#!/usr/bin/env python3
"""Research training lane: rule-labelled synthetic compositions (M4 research).

Owner-authorized research lane (2026-09-07): generates a LEARNABLE
synthetic dataset by deriving `good_frame_probability` labels from a
known composition rule over the ROI features (rule-of-thirds center,
plausible subject size), trains the frozen SETCompositionNet-v1
candidate with the frozen multitask losses, and evaluates on a
held-out synthetic split.

THIS IS NOT A PRODUCTION CANDIDATE. Labels are rule-derived, not
human gold: the result validates that the training environment
(data → train → evaluate) works end-to-end so the human-gold chain
(M3-022 → M4-010 → M4-012) can drop in unchanged. No Core ML export,
no iOS route, no candidate selection claim.
"""

from __future__ import annotations

import hashlib
import json
import sys
import time
from pathlib import Path
from types import MappingProxyType

import torch

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from ml.camera_coach.losses import compute_multitask_loss, LossConfig, LossWeights  # noqa: E402
from ml.camera_coach.models import set_composition_net as scm  # noqa: E402
from ml.camera_coach.train import SyntheticSample, _mask_for_roi  # noqa: E402

DATASET_ID = "camera_synthetic_rule_lane"
GENERATOR = "rule_labelled_contract_tensors.v1"
RULE = {
    "center_x": [0.30, 0.70],
    "center_y": [0.25, 0.75],
    "area": [0.05, 0.35],
}


def rule_label(roi: torch.Tensor) -> float:
    """Known ground-truth rule: subject present, centered, plausibly sized."""
    if float(roi[2]) == 0.0 and float(roi[3]) == 0.0:
        return 0.0
    cx = float(roi[0]) + float(roi[2]) / 2
    cy = float(roi[1]) + float(roi[3]) / 2
    area = float(roi[2]) * float(roi[3])
    inside = (
        RULE["center_x"][0] <= cx <= RULE["center_x"][1]
        and RULE["center_y"][0] <= cy <= RULE["center_y"][1]
        and RULE["area"][0] <= area <= RULE["area"][1]
    )
    return 1.0 if inside else 0.0


def make_sample(
    contract: scm.SETCompositionNetManifest,
    index: int,
    seed: int,
    split: str,
) -> SyntheticSample:
    generator = torch.Generator(device="cpu")
    generator.manual_seed((seed + index * 104729) % 2147483647)
    full = torch.rand(contract.full_frame_shape, generator=generator, dtype=torch.float32)
    crop = torch.rand(contract.subject_crop_shape, generator=generator, dtype=torch.float32)
    # ROI drawn to straddle the rule boundary so the model must learn it.
    has_roi = index % 8 != 7
    if has_roi:
        x = float(torch.rand((), generator=generator)) * 0.7
        y = float(torch.rand((), generator=generator)) * 0.7
        w = min(0.05 + float(torch.rand((), generator=generator)) * 0.4, 1.0 - x)
        h = min(0.05 + float(torch.rand((), generator=generator)) * 0.4, 1.0 - y)
        roi = torch.tensor([x, y, w, h], dtype=torch.float32)
    else:
        roi = torch.zeros(4)
    mask = _mask_for_roi(roi, contract.roi_mask_shape[0], contract.roi_mask_shape[1])

    feature_names = contract.raw["inputs"]["scalar_features"]["ordered_names"]
    normalization = contract.raw["feature_normalization"]
    feature_to_norm = normalization["feature_to_normalization"]
    scalar_rows = []
    for name in feature_names:
        lower, upper = normalization[feature_to_norm[name]]["value_range"]
        value = float(torch.rand((), generator=generator)) * (upper - lower) + lower
        scalar_rows.append(torch.tensor(value))
    scalar = torch.stack(scalar_rows).to(dtype=torch.float32)
    scalar[feature_names.index("orientation_category")] = (index % 4) / 3.0
    scalar[feature_names.index("lens_category")] = (index % 3) / 2.0
    if has_roi:
        area = float(roi[2]) * float(roi[3])
        updates = {
            "subject_bbox_x": float(roi[0]),
            "subject_bbox_y": float(roi[1]),
            "subject_bbox_width": float(roi[2]),
            "subject_bbox_height": float(roi[3]),
            "subject_area_ratio": area,
            "roi_present": 1.0,
            "roi_area_ratio": area,
            "roi_mask_coverage": float(mask.mean()),
        }
    else:
        updates = {
            "subject_bbox_x": 0.0, "subject_bbox_y": 0.0,
            "subject_bbox_width": 0.0, "subject_bbox_height": 0.0,
            "subject_area_ratio": 0.0, "roi_present": 0.0,
            "roi_area_ratio": 0.0, "roi_mask_coverage": 0.0,
        }
    for name, value in updates.items():
        scalar[feature_names.index(name)] = value
    missing = torch.zeros(contract.scalar_feature_count, dtype=torch.float32)

    label = rule_label(roi)
    targets: dict[str, torch.Tensor] = {}
    label_masks: dict[str, torch.Tensor] = {}
    for name in contract.output_head_names:
        width = contract.output_head_shapes[name]
        if name == "good_frame_probability":
            targets[name] = torch.tensor([label], dtype=torch.float32)
            label_masks[name] = torch.ones(1, dtype=torch.float32)
        elif name == "abstention_probability":
            targets[name] = torch.tensor([1.0 - label], dtype=torch.float32)
            label_masks[name] = torch.ones(1, dtype=torch.float32)
        elif name == "scene_class_logits":
            targets[name] = torch.zeros(1, dtype=torch.int64)
            label_masks[name] = torch.zeros(1, dtype=torch.float32)
        else:
            targets[name] = torch.zeros(width, dtype=torch.float32)
            label_masks[name] = torch.zeros(width, dtype=torch.float32)
    return SyntheticSample(
        f"{split}-{index:05d}",
        scm.SETCompositionNetInputs(full, crop, roi, mask, scalar, missing),
        MappingProxyType(targets),
        MappingProxyType(label_masks),
    )


def forward_batch(model, samples, indices):
    inputs = [samples[i].inputs for i in indices]
    batch = scm.SETCompositionNetInputs(
        torch.stack([s.full_frame_rgb for s in inputs]),
        torch.stack([s.subject_crop_rgb for s in inputs]),
        torch.stack([s.roi_normalized_xywh for s in inputs]),
        torch.stack([s.roi_mask for s in inputs]),
        torch.stack([s.scalar_features for s in inputs]),
        torch.stack([s.missing_feature_mask for s in inputs]),
    )
    return model(batch)


def evaluate(model, samples, indices, loss_config):
    model.eval()
    correct = 0
    absolute_error = 0.0
    with torch.no_grad():
        for start in range(0, len(indices), 32):
            chunk = indices[start:start + 32]
            outputs = forward_batch(model, samples, chunk)
            for offset, i in enumerate(chunk):
                probability = float(outputs["good_frame_probability"][offset, 0])
                target = float(samples[i].targets["good_frame_probability"][0])
                absolute_error += abs(probability - target)
                correct += int((probability > 0.5) == (target > 0.5))
    model.train()
    return {
        "accuracy": correct / len(indices),
        "mean_absolute_error": absolute_error / len(indices),
    }


def main() -> int:
    seed = 20260907
    train_count, eval_count = 640, 160
    epochs, batch_size = 12, 32
    started = time.time()

    manifest = scm.SETCompositionNetManifest.load(
        REPO_ROOT / "ml/camera_coach/contracts/set_composition_net_v1.json"
    )
    model = scm.CandidateB(manifest)
    loss_config = LossConfig.from_file(REPO_ROOT / "ml/camera_coach/configs/loss_weights.json")

    samples = [
        make_sample(manifest, i, seed, "train")
        for i in range(train_count + eval_count)
    ]
    train_indices = list(range(train_count))
    eval_indices = list(range(train_count, train_count + eval_count))

    generator = torch.Generator(device="cpu")
    generator.manual_seed(seed)
    optimizer = torch.optim.Adam(model.parameters(), lr=1e-3)

    baseline = evaluate(model, samples, eval_indices, loss_config)
    history = []
    for epoch in range(epochs):
        order = torch.randperm(train_count, generator=generator).tolist()
        epoch_loss = 0.0
        batches = 0
        for start in range(0, train_count, batch_size):
            chunk = order[start:start + batch_size]
            outputs = forward_batch(model, samples, chunk)
            targets = {name: torch.stack([samples[i].targets[name] for i in chunk]) for name in samples[chunk[0]].targets}
            masks = {name: torch.stack([samples[i].target_masks[name] for i in chunk]) for name in samples[chunk[0]].target_masks}
            optimizer.zero_grad()
            result = compute_multitask_loss(outputs, targets, label_masks=masks, config=loss_config)
            result.total.backward()
            optimizer.step()
            epoch_loss += float(result.total)
            batches += 1
        metrics = evaluate(model, samples, eval_indices, loss_config)
        history.append({"epoch": epoch + 1, "train_loss": epoch_loss / batches, **metrics})
        print(f"epoch {epoch + 1:02d} loss={history[-1]['train_loss']:.4f} "
              f"acc={metrics['accuracy']:.4f} mae={metrics['mean_absolute_error']:.4f}")

    final = history[-1]
    digest = hashlib.sha256()
    digest.update(GENERATOR.encode())
    digest.update(json.dumps(RULE, sort_keys=True).encode())
    receipt = {
        "lane": "research-synthetic-rule",
        "dataset_id": DATASET_ID,
        "generator": GENERATOR,
        "approved_human_data": False,
        "rule": RULE,
        "seed": seed,
        "candidate": "candidate_b_roi_conditioned_ablation",
        "train_samples": train_count,
        "eval_samples": eval_count,
        "epochs": epochs,
        "batch_size": batch_size,
        "baseline": baseline,
        "final": {k: final[k] for k in ("accuracy", "mean_absolute_error")},
        "history": history,
        "runtime_seconds": round(time.time() - started, 1),
        "torch_version": torch.__version__,
        "disclaimer": "Rule-derived synthetic labels; validates the training environment end-to-end. NOT a production candidate; M4-012/014 remain gated on frozen human gold (M3-022).",
        "receipt_sha256_input": digest.hexdigest(),
    }
    out_dir = REPO_ROOT / "docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-m4/research-synthetic-training"
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "receipt.json").write_text(json.dumps(receipt, indent=1), encoding="utf-8")
    print(json.dumps({k: receipt[k] for k in ("baseline", "final", "runtime_seconds")}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
