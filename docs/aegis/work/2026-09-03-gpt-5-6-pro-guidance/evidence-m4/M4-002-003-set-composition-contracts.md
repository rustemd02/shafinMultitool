# M4-002 / M4-003 — SETCompositionNet-v1 contracts

Task: Freeze the SETCompositionNet-v1 input/preprocessing/ROI/scalar-mask
contract and the bounded multi-task output-head shape, then validate the same
versioned shapes at the existing Swift runtime boundary.

Owner boundary: `ml/camera_coach/contracts/**`, the existing camera-analysis
domain/runtime schema, and the existing `MetalPreprocessor` utility. No model,
training, dataset, planner, provider, or production enablement change is part
of this batch.

## Frozen contract

`set_composition_net_v1.json` is the machine-readable authority. It defines:

- sRGB 32BGRA transport converted to logical RGB HWC, alpha discarded, ImageIO
  orientation applied exactly once, mirrored orientations honored without a
  second mirror, bilinear/independent resize, and channel normalization by
  `byte / 255.0`;
- full-frame `320×320×3`, subject crop `192×192×3`, normalized top-left ROI
  `xywh`, pixel-center ROI mask `320×320×1`, and a fixed ordered 40-value
  scalar vector with an equally indexed 0/1 missing-feature mask;
- nine ordered output heads: scene classes (8), subjectness/ROI agreement (3),
  issues (8), action utility (10), good-frame probability (1), abstention
  probability (1), risk probability (1), target deltas (5, bounded `[-1, 1]`),
  and an internal embedding (128). Generated text and arbitrary object-name
  outputs are forbidden.

Swift `SETCompositionNetContract` keeps the runtime catalog in the same order;
the stdlib parity checker mechanically compares those declarations and the
existing `IssueTypeV1` / `ActionTypeV1` enum order to the manifest. The runtime
schema retains the pre-M4 H06 constructor for the active legacy boundary, while
strict v1 input/output validation rejects absent tensors, wrong shapes,
non-finite values, stale versions, unsupported heads, and ROI-mask drift.

## Deterministic synthetic parity

The fixtures use a 4×4 synthetic RGB byte pattern and deterministic scalar/head
values only; they are not dataset or quality evidence. SHA-256 is over
little-endian float32 values. The declared tolerances are pixel `1e-6` and
scalar `1e-6`.

Input hashes:

| Tensor | SHA-256 |
|---|---|
| full frame RGB | `5ddc2c5c5c2dff60f1a2f3adcaaa9f7ff76ce6c4b140ff316a1edcb5f47a62f0` |
| subject crop RGB | `c95a927a6b5d1d1a902201b29cb37684d5bc02f4edd9f4cf01f3fe40d6b56067` |
| ROI mask | `260802a4865f20a83e157c82bd3f07ab6a0eb13ff759db5c7cac65c54fa3e0bd` |
| scalar features | `ffdd8c80ebfbc563858d2a9c704701f9038b694f1c3e8ad8fa0457f65eb3c281` |
| missing-feature mask | `f70651d882c736a535bf6daca943049ddf7e824bd6cc6289a6d83066ad03817e` |

Flattened output-head hash:
`10f1f28b3d14542d2a4253d8c7ba71e1986579ee9eb20d76a5f5ff19e9bc567e`.

## Verification evidence

- JSON parsing and manifest self-consistency: `python3 -m json.tool` on all
  four JSON artifacts — exit 0.
- Deterministic Python checker, run twice sequentially:
  `python3 ml/camera_coach/contracts/check_parity.py` — both receipts reported
  `status=pass`, 40 scalar features, 9 output heads, the hashes above, and
  byte-identical normalized output.
- Swift command (ordinary iPhone 17, iOS 26.5):
  `xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F708A11-8262-4E09-9F3A-46C86381911D' -derivedDataPath /private/tmp/setos-m4-002-003-deriveddata-final5 -resultBundlePath /private/tmp/setos-m4-002-003-final5.xcresult -only-testing:shafinMultitoolTests/SETCompositionNetRuntimeSchemaTests -only-testing:shafinMultitoolTests/SETCompositionNetParityTests -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO` — 17 selected tests, 0 skipped, all passed. Result: `/private/tmp/setos-m4-002-003-final5.xcresult`.
- `git diff --check` — exit 0; final path inspection is limited to the owned
  contract, runtime/preprocessor, focused test, and evidence paths.

## Judgment calls and gaps

- The legacy H06 schema remains as a compatibility seam for the existing M2
  provider; it is not treated as a v1 output and no malformed v1 payload is
  coerced into it. Retirement trigger: a later provider/model integration
  emits and consumes the strict v1 tensors and heads with its own focused
  verification.
- The current CoreML provider still calls its pre-M4 `256×256` / `160×160`
  preprocessing path and is outside this owned file set. This batch adds the
  exact `320×320` / `192×192` contract preprocessor seam and does not rebind or
  enable that provider. Provider integration, model metadata, and production
  availability remain a later M4 boundary.
- No training, model asset, dataset, holdout, metric, candidate-quality, or
  planner behavior claim is made here.
