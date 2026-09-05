# M4-004 / M4-005 — candidate architectures

This batch freezes two disabled, CPU-compatible PyTorch architecture
candidates. It does not train, calibrate, select, export, or enable a model in
the iOS provider. The frozen authority remains
`ml/camera_coach/contracts/set_composition_net_v1.json`; the new code reads it
at construction time and rejects v1 input/output shape or order drift.

## Implementation

`ml/camera_coach/models/set_composition_net.py` contains the smallest native
`torch.nn` MobileNetV3-style blocks needed for this comparison (depthwise
inverted residuals, squeeze-excitation, ReLU/h-swish, and global average
pooling). `torchvision` is not required and no weights are downloaded.

The common `SETCompositionNetInputs` boundary accepts logical HWC/BHWC tensors
(and BCHW as an explicit PyTorch adapter), preserves `float32`, validates
frozen shapes/ranges, and returns an ordered mapping of the nine manifest
heads. Head dimensions and output order come from the manifest; probability
and target-delta activation bounds also come from each head's manifest
`value_range`. The 40 scalar values are concatenated with their equally
indexed missing mask after declared-missing scalar slots are zero-filled.
Absent ROI gates the subject crop and ROI mask to zero deterministically.

| Candidate | Architecture | Contract path | Production status |
|---|---|---|---|
| A | Full-frame MobileNetV3-Large width 0.75 + subject-crop MobileNetV3-Small width 0.50 + scalar/missing-mask MLP → 256D fusion → 128D embedding and manifest heads | `full_frame_rgb`, `subject_crop_rgb`, scalar features and mask | Disabled; architecture comparison only |
| B | One MobileNetV3-Small width 0.50 consuming 4-channel full RGB + ROI mask, plus the same scalar/missing-mask MLP → 256D fusion → 128D embedding and manifest heads | `full_frame_rgb` + `roi_mask` + scalar features and mask; common subject crop is validated but intentionally not consumed | Disabled; lower-complexity ablation only |

Candidate B is deliberately only a capacity/MAC ablation. It is not evidence
that it will coach better than A.

## Verification receipt

Environment and reproducibility:

- PyTorch `2.10.0`; Python `3.11.9`.
- CPU forward, one thread, `torch.use_deterministic_algorithms(True)`.
- Fixed seed `20260905`; repeated receipts were byte-identical.
- Synthetic random tensors only: full frame `320×320×3`, subject crop
  `192×192×3`, ROI mask `320×320×1`, 40 scalars and 40-value missing mask.
- The check exercises all nine output heads and exact manifest shapes, repeated
  forward equality, absent ROI/crop zero-gating, missing-slot zero-fill,
  finite gradient traversal, and the B/A MAC gate.

Commands:

```text
python3 -m py_compile ml/camera_coach/models/set_composition_net.py ml/camera_coach/models/check_candidates.py
python3 -m ml.camera_coach.models.check_candidates > /private/tmp/setos-m4-004-005-candidates.json
python3 -m ml.camera_coach.models.check_candidates > /private/tmp/setos-m4-004-005-candidates-2.json
cmp -s /private/tmp/setos-m4-004-005-candidates.json /private/tmp/setos-m4-004-005-candidates-2.json
python3 ml/camera_coach/contracts/check_parity.py > /private/tmp/setos-m4-004-005-parity.json
python3 -m py_compile ml/camera_coach/models/*.py
git diff --check
```

Result: `status=pass`; both candidate receipts matched byte-for-byte. The
existing frozen contract checker also returned `status=pass` with 40 scalar
features, nine heads, all synthetic hashes, and all mutation probes rejected.

| Measurement | Candidate A | Candidate B |
|---|---:|---:|
| Parameters | 2,383,069 | 427,349 |
| Conv2d + Linear MACs (batch 1) | 317,852,928 | 42,139,072 |
| B / A MAC ratio | — | `0.1325741193109286` |
| Deterministic output receipt hash | `34ec92c42e90a82873727beff6076303d6d7c034ec7fc9648208326f6aed7f17` | `afd2669884cec9e70996fe2573ad8fd53d4ec26efe5be0f48c7f627a42f90a6f` |

The measured ratio is `13.26%`, satisfying the required `B ≤ 70% of A`
threshold. The counter includes convolution multiply-accumulates and linear
multiply-accumulates only; it is not a device-latency or thermal estimate.

## Limitations and next owner

- No real camera frames, approved dataset, holdout, training, calibration,
  accuracy/quality metric, model selection, CoreML artifact, or iOS runtime
  enablement is claimed.
- MobileNetV3 blocks are a faithful native-op comparison implementation, not
  a claim of parity with a torchvision checkpoint.
- M4-006 owns the pinned training/export environment and later runtime
  integration gates. Candidate quality and selection remain open decisions.
- No Swift, dataset, contract, route, or production provider files changed in
  this batch.
