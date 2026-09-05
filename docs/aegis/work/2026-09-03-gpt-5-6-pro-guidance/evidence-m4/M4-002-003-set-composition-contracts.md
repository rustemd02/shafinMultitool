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
The categorical order/count is frozen as orientation `[up, right, down, left]`
(normalized values `0`, `1/3`, `2/3`, `1`) and lens `[ultra_wide, wide, tele]`
(normalized values `0`, `0.5`, `1`); mirror state is a separate scalar.
ROI, mask, and the `roi_present` / `roi_area_ratio` / `roi_mask_coverage`
scalars are cross-checked at the Swift and Python boundaries. An absent ROI
is represented by zero ROI coordinates, a zero mask, and a zero-filled
subject crop at the production tensor trust boundary.

Preprocessing freezes sRGB 32BGRA transport, alpha discard, RGB order,
`uint8 → float32` channel conversion by exactly `/255.0` (source range
`[0,255]`, output range `[0,1]`), ImageIO orientation exactly once, no extra
mirror, bilinear sampling, independent resize, and a `1.25×` square ROI
expansion before resize. The raw padded square bounds are derived first, then
intersected with the oriented full-frame bounds edge-by-edge without shifting
the crop. `MetalPreprocessor` exposes a SET-specific logical RGB tensor seam
using those rules. The shared legacy `resizedPixelBuffer` implementation
remains unchanged for existing camera and CoreML callers.

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
payloads. The Swift/Python checks compare the manifest with nested schema
shapes, ranges, normalization formulas, RGB type/scale, the exact 40-feature
normalization map (including `person_count → count_0_to_8`), catalogs, and all
five runtime version constants. Focused negative coverage includes
feature-specific range and categorical-value rejection, missing-fill and ROI
scalar drift, non-zero absent-ROI crops, embedding dimension 64, risk 99,
removed heads, ROI/mask mismatch, paired formula/scale/type drift, paired
version drift, paired signed-range drift, and strict-v1 detection for each
metadata field.
Unavailable/failed states remain explicit and scoreless.

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
| top-left edge-clipped crop | `6d5ffae613c0ae9afe15391c69ce7eb536176de741e206afb16d3c0d22e1f793` |
| bottom-right edge-clipped crop | `4e48b33dabbe3c774bfaeb08687293c30d617e09ad14314523bc0606e79d804f` |
| ROI mask | `260802a4865f20a83e157c82bd3f07ab6a0eb13ff759db5c7cac65c54fa3e0bd` |
| absent-ROI zero mask | `d58201a30b35a60612306667b083ca4dfaf9efa107386fff36188e42c34c3c19` |
| absent-ROI zero subject crop | `ecdd54e7af52d8ca757fa4f6b58884c0d8b5c487abeebdf23a4008a3b1b810bf` |
| scalar features | `d1106f1b49650a56e647a0e0a9ed83784e6c39483991dc12d1f20c6e7cd29d02` |
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
  output hash above, absent-ROI zero hashes, and all 14 mutation checks
  rejected (including embedding 64, risk 99, removed head, paired RGB
  formula/scale/type drift, `person_count` mapping drift, paired version and
  signed-range drift, and unsupported categorical scalar). Receipts were
  byte-identical (`cmp -s`) at `/private/tmp/setos-m4-third-parity1.json` and
  `/private/tmp/setos-m4-third-parity2.json`.
- Focused Swift tests on ordinary iPhone 17 simulator (UUID
  `1F708A11-8262-4E09-9F3A-46C86381911D`, iOS 26.5), sequential xcodebuild,
  diagnostics disabled:

  ```text
  xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F708A11-8262-4E09-9F3A-46C86381911D' -derivedDataPath /private/tmp/setos-m4-third-dd1 -resultBundlePath /private/tmp/setos-m4-third1.xcresult -only-testing:shafinMultitoolTests/SETCompositionNetRuntimeSchemaTests -only-testing:shafinMultitoolTests/SETCompositionNetParityTests -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO
  ```

  Result: `** TEST SUCCEEDED **`; 21 selected tests, 0 skipped, 0 failed. The
  result summary records the exact ordinary iPhone 17 UUID and iOS 26.5. The
  parity class exercised the production `setCompositionNetRGBTensors` path for
  center, top-left and bottom-right edge-clipped fixtures plus an absent-ROI
  zero crop; the schema class covered negative trust-boundary cases. The build
  emitted only the existing non-fatal `Circle.rcproject` processing warning.
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
