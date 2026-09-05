# M4-002 / M4-003 — SETCompositionNet-v1 contracts

This correction is contract/parity work only. It does not add a model asset,
training path, planner behavior, provider enablement, quality claim, or
production availability change.

## Frozen authority

`ml/camera_coach/contracts/set_composition_net_v1.json` is the checked
machine-readable authority. Its explicit versions are:

- contract: `setcompositionnet.v1`
- input: `setcompositionnet.input.v1`
- preprocessing: `setcompositionnet.preprocessing.v1`
- scalar features: `setcompositionnet.features.v1`
- output: `setcompositionnet.output.v1`

The input is HWC logical RGB: full frame `320×320×3`, subject crop
`192×192×3`, normalized top-left `xywh` ROI, pixel-center `320×320×1` ROI
mask, and 40 ordered scalar values with an equally indexed 0/1 missing mask.
Missing scalars use the explicit fill value `0.0`; signed features and all
other feature-specific ranges are enumerated in `feature_to_normalization`.
ROI, mask, and the `roi_present` / `roi_area_ratio` / `roi_mask_coverage`
scalars are cross-checked at the Swift and Python boundaries.

Preprocessing freezes sRGB 32BGRA transport, alpha discard, RGB order,
`byte / 255.0`, ImageIO orientation exactly once, no extra mirror, bilinear
sampling, independent resize, and a `1.25×` square ROI expansion clipped to
oriented full-frame bounds before resize. `MetalPreprocessor` exposes a
SET-specific logical RGB tensor seam using those rules. The shared legacy
`resizedPixelBuffer` implementation remains unchanged for existing camera and
CoreML callers.

The nine ordered output heads are scene class (8), subjectness/ROI agreement
(3), issue labels (8), bounded action utility (26), good-frame probability
(1), abstention probability (1), risk probability (1), continuous target
deltas (5, `[-1, 1]`), and internal embedding (128). Action utility derives
from `CameraCoachContractV2.production.approvedActionIDs`, i.e. the ordered
`SemanticActionType` v2 catalog. Legacy `ActionTypeV1` IDs such as
`move_frame_*` and `change_angle` remain only in the explicit migration table;
they are not model output heads. Generated text and arbitrary object names are
forbidden.

`SETCompositionNetRuntimeSchema` and `SETCompositionNetOutputHeads` reject
missing, extra, wrong-sized, non-finite, out-of-range, or version-mismatched
payloads. The correction adds focused negative coverage for scalar ranges,
missing-fill and ROI scalar drift, embedding dimension 64, risk 99, removed
heads, ROI/mask mismatch, and stale versions. Unavailable/failed states remain
explicit and scoreless.

## Deterministic synthetic parity

The fixtures are a small deterministic 4×4 RGB byte pattern and synthetic
scalar/head values; they are not dataset or quality evidence. Hashes are
SHA-256 over little-endian float32 values. Declared pixel/scalar tolerances are
`1e-6` / `1e-6`.

Input hashes:

| Tensor | SHA-256 |
|---|---|
| full frame RGB | `5ddc2c5c5c2dff60f1a2f3adcaaa9f7ff76ce6c4b140ff316a1edcb5f47a62f0` |
| center subject crop RGB | `c95a927a6b5d1d1a902201b29cb37684d5bc02f4edd9f4cf01f3fe40d6b56067` |
| top-left edge-clipped crop | `49fe6bf5661eedfda2f2443cd97c2c89dc6e8414430a04713d7472a9f9492788` |
| bottom-right edge-clipped crop | `4e48b33dabbe3c774bfaeb08687293c30d617e09ad14314523bc0606e79d804f` |
| ROI mask | `260802a4865f20a83e157c82bd3f07ab6a0eb13ff759db5c7cac65c54fa3e0bd` |
| scalar features | `b88d7c69932c3005c15018867013523b994651f75ace444d64cdc3de52b79292` |
| missing-feature mask | `f70651d882c736a535bf6daca943049ddf7e824bd6cc6289a6d83066ad03817e` |

Flattened output-head hash (including 26 action values and 128 embedding
values):
`357c2ef83b1bfd7f04f06d888e67507698152e2fd8942dbc3a5743b42019928d`.

## Verification evidence

- Stdlib JSON parsing: `python3 -m json.tool` on the manifest, schema, and both
  fixtures — 4 files, exit 0.
- Deterministic parity/mutation checker, twice sequentially:
  `python3 ml/camera_coach/contracts/check_parity.py` — both receipts report
  `status=pass`, 40 scalar features, 9 heads, center and both edge crop hashes,
  output hash above, and all five mutation checks rejected. Receipts were
  byte-identical (`cmp -s`) at `/private/tmp/setos-m4-fix-parity3.json` and
  `/private/tmp/setos-m4-fix-parity4.json`.
- Focused Swift tests on ordinary iPhone 17 simulator (UUID
  `1F708A11-8262-4E09-9F3A-46C86381911D`, iOS 26.5), sequential xcodebuild,
  diagnostics disabled:

  ```text
  xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F708A11-8262-4E09-9F3A-46C86381911D' -derivedDataPath /private/tmp/setos-m4-fix-final-dd2 -resultBundlePath /private/tmp/setos-m4-fix-final2.xcresult -only-testing:shafinMultitoolTests/SETCompositionNetRuntimeSchemaTests -only-testing:shafinMultitoolTests/SETCompositionNetParityTests -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO
  ```

  Result: `** TEST SUCCEEDED **`; 20 selected tests, 0 skipped. The parity
  class exercised the production `setCompositionNetRGBTensors` path for center
  and edge-clipped ROI fixtures; the schema class covered negative trust-boundary
  cases.
- `git diff --check` — exit 0.

## Judgment calls and bounded gaps

- A SET-specific logical RGB tensor API was added so fixture hashes exercise
  production preprocessing without altering shared legacy pixel-buffer callers.
  The existing CoreML provider still owns its pre-M4 `256×256` / `160×160`
  path and remains outside this correction; no provider was rebound or enabled.
- The v2 action head is intentionally the existing
  `CameraCoachContractV2` / `SemanticActionType` catalog and migration source,
  not the legacy 10-ID transport catalog. Future architecture/training work
  must consume these shapes and preserve the version checks.
- No training, model download, dataset/holdout inspection, metric, candidate
  quality, planner, Visual Policy, UI, route, or production enablement claim is
  made here.
