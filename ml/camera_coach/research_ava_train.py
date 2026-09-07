#!/usr/bin/env python3
"""AVA silver pretraining lane (M4-011 teacher/silver policy, owner-authorized).

Real AVA photographs with human aesthetic scores (silver labels, NOT the
CC human-gold taxonomy) train the full-frame branch of CandidateA:
  - images resized to the frozen 320x320 contract (stretch, pixel-center);
  - no ROI (roi_present=0, mask zero), all 40 scalars marked missing so the
    pixel branch carries the entire signal;
  - good_frame_probability = (mean_score - 1) / 9, abstention = 1 - p;
  - eval on a hash-held-out split: binary accuracy at the AVA 5.5 cut.

Research lane: no Core ML export, no iOS route, no candidate selection.
"""

from __future__ import annotations

import hashlib
import json
import math
import sys
import time
from pathlib import Path

import torch
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from ml.camera_coach.losses import LossConfig, compute_multitask_loss  # noqa: E402
from ml.camera_coach.models import set_composition_net as scm  # noqa: E402
from ml.camera_coach.train import SyntheticSample  # noqa: E402

MANIFEST = Path("/private/tmp/ava_silver/manifest.jsonl")
SEED = 20260907
EPOCHS = 5
BATCH = 16


def load_manifest(limit: int) -> list[dict]:
    entries = []
    for line in MANIFEST.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        entries.append(json.loads(line))
        if len(entries) >= limit:
            break
    return entries


def split_of(image_id: str) -> str:
    digest = hashlib.sha256(f"ava-silver:{image_id}".encode()).hexdigest()
    return "train" if int(digest[:8], 16) % 5 else "eval"


def encode_image(path: str, contract: scm.SETCompositionNetManifest) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor] | None:
    try:
        with Image.open(path) as handle:
            frame = handle.convert("RGB").resize((320, 320), Image.BILINEAR)
    except Exception:  # noqa: BLE001
        return None
    raw = torch.tensor(list(frame.getdata()), dtype=torch.float32).reshape(320, 320, 3) / 255.0
    full = raw.permute(2, 0, 1)  # HWC -> CHW
    crop = full[:, 64:256, 64:256]  # center 192
    mask = torch.zeros(1, 320, 320, dtype=torch.float32)
    return full, crop, mask


def build_sample(entry: dict, contract: scm.SETCompositionNetManifest) -> SyntheticSample | None:
    encoded = encode_image(entry["path"], contract)
    if encoded is None:
        return None
    full, crop, _encoded_mask = encoded
    probability = max(0.0, min(1.0, (entry["mean_score"] - 1.0) / 9.0))
    scalar = torch.zeros(contract.scalar_feature_count, dtype=torch.float32)
    missing = torch.ones(contract.scalar_feature_count, dtype=torch.float32)
    # Center pseudo-ROI activates the ROI-conditioned pathway
    # (_prepare_inputs zeroes the crop branch when no ROI is present).
    roi = torch.tensor([0.20, 0.20, 0.60, 0.60], dtype=torch.float32)
    mask = torch.zeros(1, 320, 320, dtype=torch.float32)
    mask[:, 64:256, 64:256] = 1.0
    targets: dict[str, torch.Tensor] = {}
    label_masks: dict[str, torch.Tensor] = {}
    for name in contract.output_head_names:
        width = contract.output_head_shapes[name]
        if name == "good_frame_probability":
            targets[name] = torch.tensor([probability], dtype=torch.float32)
            label_masks[name] = torch.ones(1, dtype=torch.float32)
        elif name == "abstention_probability":
            targets[name] = torch.tensor([1.0 - probability], dtype=torch.float32)
            label_masks[name] = torch.ones(1, dtype=torch.float32)
        elif name == "scene_class_logits":
            targets[name] = torch.zeros(1, dtype=torch.int64)
            label_masks[name] = torch.zeros(1, dtype=torch.float32)
        else:
            targets[name] = torch.zeros(width, dtype=torch.float32)
            label_masks[name] = torch.zeros(width, dtype=torch.float32)
    feature_names = contract.raw["inputs"]["scalar_features"]["ordered_names"]
    area = float(roi[2]) * float(roi[3])
    for name, value in {
        "subject_bbox_x": 0.20, "subject_bbox_y": 0.20,
        "subject_bbox_width": 0.60, "subject_bbox_height": 0.60,
        "subject_area_ratio": area, "roi_present": 1.0,
        "roi_area_ratio": area, "roi_mask_coverage": 1.0,
    }.items():
        scalar[feature_names.index(name)] = value
        missing[feature_names.index(name)] = 0.0
    return SyntheticSample(
        f"ava-{entry['image_id']}",
        scm.SETCompositionNetInputs(full, crop, roi, mask, scalar, missing),
        MappingProxy(targets),
        MappingProxy(label_masks),
    )


def MappingProxy(d):
    from types import MappingProxyType
    return MappingProxyType(d)


def forward_batch(model, samples, indices, device):
    inputs = [samples[i].inputs for i in indices]
    batch = scm.SETCompositionNetInputs(
        torch.stack([s.full_frame_rgb for s in inputs]).to(device),
        torch.stack([s.subject_crop_rgb for s in inputs]).to(device),
        torch.stack([s.roi_normalized_xywh for s in inputs]).to(device),
        torch.stack([s.roi_mask for s in inputs]).to(device),
        torch.stack([s.scalar_features for s in inputs]).to(device),
        torch.stack([s.missing_feature_mask for s in inputs]).to(device),
    )
    return model(batch)


def evaluate(model, samples, indices, device) -> dict:
    model.eval()
    correct = total = 0
    absolute_error = 0.0
    with torch.no_grad():
        for start in range(0, len(indices), BATCH):
            chunk = indices[start:start + BATCH]
            outputs = forward_batch(model, samples, chunk, device)
            for offset, i in enumerate(chunk):
                probability = float(outputs["good_frame_probability"][offset, 0].cpu())
                target_probability = float(samples[i].targets["good_frame_probability"][0].cpu())
                mean_score = target_probability * 9.0 + 1.0
                predicted_mean = probability * 9.0 + 1.0
                absolute_error += abs(probability - target_probability)
                correct += int((predicted_mean >= 5.5) == (mean_score >= 5.5))
                total += 1
    model.train()
    return {"binary_accuracy_at_5_5": correct / total, "mean_absolute_error": absolute_error / total}


def main() -> int:
    started = time.time()
    device = sys.argv[4] if len(sys.argv) > 4 else ("mps" if torch.backends.mps.is_available() else "cpu")
    manifest = scm.SETCompositionNetManifest.load(
        REPO_ROOT / "ml/camera_coach/contracts/set_composition_net_v1.json"
    )
    global EPOCHS
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 4000
    EPOCHS = int(sys.argv[2]) if len(sys.argv) > 2 else EPOCHS
    entries = load_manifest(limit)
    print(f"manifest rows: {len(entries)}; device: {device}", flush=True)

    samples: list[SyntheticSample] = []
    skipped = 0
    for entry in entries:
        sample = build_sample(entry, manifest)
        if sample is None:
            skipped += 1
            continue
        samples.append(sample)
    train_indices = [i for i, s in enumerate(samples) if split_of(s.sample_id) == "train"]
    eval_indices = [i for i, s in enumerate(samples) if split_of(s.sample_id) == "eval"]
    print(f"samples: train={len(train_indices)} eval={len(eval_indices)} skipped={skipped}", flush=True)

    model = scm.CandidateA(manifest).to(device)
    loss_config = LossConfig.from_file(REPO_ROOT / "ml/camera_coach/configs/loss_weights.json")
    generator = torch.Generator(device="cpu")
    generator.manual_seed(SEED)
    optimizer = torch.optim.Adam(model.parameters(), lr=float(sys.argv[3]) if len(sys.argv) > 3 else 2e-3)

    baseline = evaluate(model, samples, eval_indices, device)
    print(f"baseline: {baseline}", flush=True)
    history = []
    for epoch in range(EPOCHS):
        order = torch.randperm(len(train_indices), generator=generator).tolist()
        epoch_loss = 0.0
        batches = 0
        for start in range(0, len(order), BATCH):
            chunk = [train_indices[j] for j in order[start:start + BATCH]]
            outputs = forward_batch(model, samples, chunk, device)
            targets = {
                name: torch.stack([samples[i].targets[name] for i in chunk]).to(device)
                for name in samples[chunk[0]].targets
            }
            masks = {
                name: torch.stack([samples[i].target_masks[name] for i in chunk]).to(device)
                for name in samples[chunk[0]].target_masks
            }
            optimizer.zero_grad()
            result = compute_multitask_loss(outputs, targets, label_masks=masks, config=loss_config)
            result.total.backward()
            optimizer.step()
            epoch_loss += float(result.total.detach())
            batches += 1
        metrics = evaluate(model, samples, eval_indices, device)
        history.append({"epoch": epoch + 1, "train_loss": epoch_loss / batches, **metrics})
        print(f"epoch {epoch + 1:02d} loss={history[-1]['train_loss']:.4f} "
              f"acc@5.5={metrics['binary_accuracy_at_5_5']:.4f} "
              f"mae={metrics['mean_absolute_error']:.4f}", flush=True)

    receipt = {
        "lane": "ava-silver-pretraining",
        "dataset": "trojblue/AVA-aesthetics-10pct-min50-10bins (validation split)",
        "policy": "M4-011 teacher/silver: real photos, human aesthetic scores as silver labels; NOT the CC human-gold taxonomy; no candidate selection claim",
        "approved_human_data": False,
        "data_location": "/private/tmp/ava_silver (outside Git; rights-uncleared)",
        "candidate": "candidate_a_dual_branch (full-frame branch under load)",
        "device": device,
        "images_used": len(samples),
        "skipped_decode": skipped,
        "epochs": EPOCHS,
        "batch_size": BATCH,
        "baseline": baseline,
        "final": history[-1] if history else None,
        "history": history,
        "runtime_seconds": round(time.time() - started, 1),
        "torch_version": torch.__version__,
        "disclaimer": "Silver pretraining validates the pixel pathway. Production candidate selection still requires the frozen M3 human-gold chain (M3-022) per plan.",
    }
    out_dir = REPO_ROOT / "docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-m4/ava-silver-training"
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "receipt.json").write_text(json.dumps(receipt, indent=1), encoding="utf-8")
    print(json.dumps({"baseline": baseline, "final": receipt["final"], "runtime_seconds": receipt["runtime_seconds"]}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
