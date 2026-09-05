# M4-004 / M4-005 — candidate architectures

This batch freezes two disabled, CPU-compatible PyTorch architecture
candidates. It does not train, calibrate, select, export, or enable a model in
the iOS provider. The frozen authority remains
`ml/camera_coach/contracts/set_composition_net_v1.json`; the new code reads it
at construction time and rejects v1 input/output shape or order drift.

## Implementation

`ml/camera_coach/models/set_composition_net.py` contains the smallest native
`torch.nn` MobileNetV3-style blocks needed for this comparison (canonical
fixed Large-15/Small-11 depthwise inverted-residual schedules,
squeeze-excitation, ReLU/h-swish, and global average pooling). Width is
applied independently to each fixed raw input/expansion/output channel. The
SE bottleneck derives from the scaled expanded feature channels, and its
explicit `torch.nn.Hardsigmoid` gate returns to that expanded width.
Every MobileNetV3 BatchNorm uses the centralized canonical configuration
`eps=0.001`, `momentum=0.01`. `torchvision` is not required and no weights are
downloaded.

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

The raw expansion-channel schedules are frozen explicitly in code and checked
independently by the self-check:

- Large: `[16, 64, 72, 72, 120, 120, 240, 200, 184, 184, 480, 672, 672, 960, 960]`.
- Small: `[16, 72, 88, 96, 240, 240, 120, 144, 288, 576, 576]`.

The two Large `80 → 80` blocks at positions 9–10 therefore scale to 136
channels at width 0.75; the preceding 2.5× block remains 200 raw / 152
scaled.

## Verification receipt

Environment and reproducibility:

- PyTorch `2.10.0`; Python `3.11.9`.
- CPU forward, one thread, `torch.use_deterministic_algorithms(True)`.
- Fixed seed `20260905`; repeated receipts were byte-identical.
- Synthetic random tensors only: full frame `320×320×3`, subject crop
  `192×192×3`, ROI mask `320×320×1`, 40 scalars and 40-value missing mask.
- The check exercises all nine output heads and exact manifest shapes, repeated
  forward equality, absent ROI/crop zero-gating, missing-slot zero-fill,
  finite gradient traversal, and the B/A MAC gate. Its independent admission
  constants inspect the constructed Conv2d/Sequential modules directly for
  stem and final projection channels/kernels/strides/activations, canonical
  Large-15/Small-11 block count and channel schedule, kernel, stride,
  activation, residual flag, SE presence, expanded-width squeeze channels,
  hard-sigmoid gate, and BatchNorm presence/settings in every stem, block, and
  final projection. It also inspects the scalar MLP, exact fusion widths, 256D
  embedding projection, and every manifest head; the convenience
  `block_schedule` and dimension metadata are not trusted. Deliberate
  Hardswish-to-ReLU stem/final, 256-to-128 fusion, depthwise/projection-BN
  removal, and BN eps/momentum mutation probes are required to fail the guards.

Commands:

```text
python3 -m py_compile ml/camera_coach/models/set_composition_net.py ml/camera_coach/models/check_candidates.py
python3 -m ml.camera_coach.models.check_candidates > /private/tmp/setos-m4-004-005-candidates-bn-1.json
python3 -m ml.camera_coach.models.check_candidates > /private/tmp/setos-m4-004-005-candidates-bn-2.json
cmp -s /private/tmp/setos-m4-004-005-candidates-bn-1.json /private/tmp/setos-m4-004-005-candidates-bn-2.json
python3 ml/camera_coach/contracts/check_parity.py > /private/tmp/setos-m4-004-005-parity-bn.json
python3 -m py_compile ml/camera_coach/models/*.py
git diff --check
```

Result: `status=pass`; both candidate receipts matched byte-for-byte. The
existing frozen contract checker also returned `status=pass` with 40 scalar
features, nine heads, all synthetic hashes, and all mutation probes rejected.

| Measurement | Candidate A | Candidate B |
|---|---:|---:|
| Parameters | 2,320,541 | 411,877 |
| Conv2d + Linear MACs (batch 1) | 295,340,192 | 39,246,272 |
| B / A MAC ratio | — | `0.13288496812516462` |
| Deterministic output receipt hash | `71392c56f6e9a5dd18065686689e1230779cac46e8f9dce95ca00ee7a833134d` | `f4d6d2d3691bbad1a27d725ca3483b1e5309a17689209a06203af295d1d3ee26` |

The measured ratio is `13.29%`, satisfying the required `B ≤ 70% of A`
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
