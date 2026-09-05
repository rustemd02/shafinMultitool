# M4-007 / M4-009 — training preprocessing and multi-task losses

Status: `PASS` for contract and infrastructure evidence only.  Both
SETCompositionNet-v1 candidates remain production-disabled.  This evidence
does not claim model quality, candidate selection, calibration, Core ML
export, or iOS runtime enablement.

## Implementation

- `ml/camera_coach/data/preprocessing.py` is the single training-side adapter
  for the frozen `setcompositionnet.v1` manifest.  It accepts deterministic
  32BGRA/RGB source pixels, discards alpha, applies ImageIO orientation exactly
  once, honors mirrored orientations without a second flip, uses the Swift
  pixel-centre bilinear resize, derives the clipped `square_expand_1.25.v1`
  subject crop, zero-fills an absent crop, rasterizes the normalized ROI mask,
  and normalizes all 40 scalar features through the manifest mappings.  ROI
  derived features and missing-feature fill/masks are checked against the
  frozen semantics.
- `ml/camera_coach/data/fixtures/preprocessing_parity.json` is a compact
  deterministic 50-case manifest (`lcg_bgra_u8.v1`, seed `20260905`) containing
  the source-dimension formulas (`width = 2 + (index * 5 % 7)`, `height = 2 +
  (index * 5 % 8)`), explicit dimension/aspect-ratio diversity receipts, and
  per-case/aggregate image digests rather than copied pixel blobs.
  `check_preprocessing_parity.py` independently recomputes the frozen
  reference math, checks full/crop/ROI/mask/scalar/missing tensors and all eight
  orientation/mirror states, compares every case digest, and rejects any
  corpus whose source dimensions lose the recorded diversity.
- `shafinMultitoolTests/SETCompositionNetRuntimeSchemaTests.swift` adds one
  compact cross-language test.  It generates the same source buffers and ROI
  cases, invokes the real production `MetalPreprocessor` seam, and compares
  its per-case and aggregate image hashes to the Python fixture.  No second
  Swift preprocessing implementation was added and no production Swift file
  was changed.
- `ml/camera_coach/losses.py` owns manifest-driven direct terms for scene
  cross-entropy, subjectness/ROI binary BCE-with-logits, issue/action focal
  BCE, probability-head BCE (including risk), and Smooth L1 deltas.  It also
  owns explicit weighted ranking and contrastive terms for only
  `good_vs_harmful` and `before_after`; preference and same/different labels
  are separate, and absent pair labels do not create supervision.  Every
  reduction validates finite values, shapes, binary masks and non-negative
  finite weights.  Sample-level masks expand to the element-loss shape before
  both numerator and denominator reduction; an all-missing term is
  differentiable zero so its gradient is exactly zero.
- `ml/camera_coach/configs/loss_weights.json` and its closed schema pin all ten
  terms plus focal/margin hyperparameters.  `train.py` consumes this config
  through a closed path/SHA-256 reference in the existing training config,
  includes target masks in the synthetic receipt dataset hash, and records the
  weighted loss definition/config/hash/weight map.  Existing M4-006 integrity
  guards remain in `check_training_environment.py`.

## Verification

Interpreter and platform for the Python checks:

```text
Python 3.11.9 (v3.11.9:de54cf5be3, Apr  2 2024, 07:12:50) [Clang 13.0.0 (clang-1300.0.29.30)]
macOS-27.0-arm64-arm-64bit
CPython 3.11.9 2.10.0
```

The frozen contract checker passed:

```text
python3 -m ml.camera_coach.contracts.check_parity
```

Result: `status=pass`, contract `setcompositionnet.v1`, 40 scalar features,
nine output heads, and all existing mutation probes rejected.

The deterministic Python parity checker passed twice:

```text
PYTHONHASHSEED=1 python3 -m ml.camera_coach.data.check_preprocessing_parity
PYTHONHASHSEED=777 python3 -m ml.camera_coach.data.check_preprocessing_parity
```

Both commands returned the identical result:

```json
{"absent_roi_cases":5,"canonical_digest":"2795a72659873d369581b686f29d3fe0b70aa7513db98a28374de3cdb581f26a","case_count":50,"case_image_digest_count":50,"contract_version":"setcompositionnet.v1","mirrored_cases":25,"orientation_counts":{"down":6,"downMirrored":6,"left":6,"leftMirrored":6,"right":6,"rightMirrored":6,"up":7,"upMirrored":7},"source":"lcg_bgra_u8.v1","source_dimension_formula":{"height":"2 + (index * 5 % 8)","width":"2 + (index * 5 % 7)"},"source_dimension_summary":{"aspect_ratio_max":4.0,"aspect_ratio_min":0.2222222222222222,"height_max":9,"height_min":2,"unique_aspect_ratios":36,"unique_dimension_pairs":50,"unique_heights":8,"unique_widths":7,"width_max":8,"width_min":2},"status":"pass","swift_image_digest":"962ee64634f9ccb52d91971fa247e141e7800014609963c54e123b2c225c49a1","tolerance":1e-06}
```

The required real Swift-side parity run used only the permitted iPhone Air
destination and isolated temporary paths:

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'id=A6E7238C-B4C6-4988-B399-8E127CA8683B' \
  -derivedDataPath /tmp/m4007009-swift-dimdiv-OqFw7h/DerivedData \
  -resultBundlePath /tmp/m4007009-swift-dimdiv-OqFw7h/Results.xcresult \
  -only-testing:shafinMultitoolTests/SETCompositionNetParityTests
xcrun xcresulttool get test-results summary --path /tmp/m4007009-swift-dimdiv-OqFw7h/Results.xcresult
```

The result summary was `result=Passed`, device `iPhone Air` / UUID
`A6E7238C-B4C6-4988-B399-8E127CA8683B`, `passedTests=3`,
`failedTests=0`, `skippedTests=0`.  The three passed tests included
`testDeterministicPythonSwiftParityManifestCoversFiftyCases()`,
`testMetalContractPreprocessorDimensionsAndRGBOrder`, and
`testSyntheticPythonSwiftParityFixtureHashes`; xcodebuild ended with
`** TEST SUCCEEDED **`.  The isolated `/tmp/m4007009-swift-dimdiv-OqFw7h`
tree was removed with `find ... -type f -delete` followed by empty-directory
cleanup and verified absent.  No iPhone 17 Pro destination was used.

The follow-up dimensional-diversity correction supersedes the earlier parity
receipt whose width expression was `2 + (index * 7 % 7)` (all 50 widths were
`2`).  The bounded replacement and receipt are:

| Receipt | Width formula | Canonical digest | Swift image digest |
|---|---|---|---|
| previous | `2 + (index * 7 % 7)` | `0f036152603ab1895a966b78cffd1d364b55f918e36a5bb10e51f97a97e0e822` | `1285ec71b9df0a7b3101aedec9ade37ab2d13381dfba5509e07756bf8874471d` |
| corrected | `2 + (index * 5 % 7)` | `2795a72659873d369581b686f29d3fe0b70aa7513db98a28374de3cdb581f26a` | `962ee64634f9ccb52d91971fa247e141e7800014609963c54e123b2c225c49a1` |

The corrected Python and Swift receipts assert 7 unique widths (2–8), 8
unique heights (2–9), 50 unique dimension pairs, and 36 reduced aspect
ratios spanning `2/9` through `4/1`, while retaining all eight orientations,
25 mirrored cases, and five absent-ROI cases.

The stale-formula falsification probe also passed: the old expression yields
one unique width against the fixture's required seven, while the corrected
expression yields seven:

```text
python3 - <<'PY'
import json
from pathlib import Path
fixture = json.loads(Path('ml/camera_coach/data/fixtures/preprocessing_parity.json').read_text())
old_widths = {2 + (index * 7 % 7) for index in range(fixture['case_count'])}
new_widths = {2 + (index * 5 % 7) for index in range(fixture['case_count'])}
print({'stale_width_unique': len(old_widths), 'expected_width_unique': fixture['source_dimension_summary']['unique_widths'], 'corrected_width_unique': len(new_widths)})
assert len(old_widths) != fixture['source_dimension_summary']['unique_widths']
assert len(new_widths) == fixture['source_dimension_summary']['unique_widths']
PY
```

Output: `{'stale_width_unique': 1, 'expected_width_unique': 7, 'corrected_width_unique': 7}`.  The parity checker's fixture-summary equality
assertions and the Swift test's matching assertions therefore reject a return
to the degenerate corpus.

The focused loss checker passed:

```text
python3 -m ml.camera_coach.check_losses
```

```json
{"direct_loss_heads":["scene_class_logits","subjectness_roi_agreement_logits","issue_logits","action_utility_logits","good_frame_probability","abstention_probability","risk_probability","continuous_target_deltas"],"loss_terms":["scene_class_logits","subjectness_roi_agreement_logits","issue_logits","action_utility_logits","good_frame_probability","abstention_probability","risk_probability","continuous_target_deltas","ranking","contrastive"],"malformed_inputs_rejected":true,"missing_gradients_zero":true,"missing_label_gradient_zero":true,"missing_total":0.0,"perfect_contrastive":0.0,"perfect_ranking":0.0,"perfect_total":0.4339101016521454,"status":"pass","wrong_contrastive":0.5,"wrong_ranking":0.8500000238418579,"wrong_total":3.710824728012085}
```

This exercised perfect/wrong direct heads, both approved pair sets, explicit
contrastive labels, all-missing and partially missing masks, exact zero
missing gradients/contribution, all-ones sample-mask equivalence to an
unmasked multi-column loss, partial sample-mask selected-row reduction,
complete output-head enforcement, and rejection of malformed/non-finite
predictions, targets, masks, weights, hyperparameters, shapes, pair sets and
missing contrastive labels.

The M4-006 environment/integrity checker passed with the new canonical loss:

```text
python3 -m ml.camera_coach.check_training_environment
```

Material output was:

```json
{
  "changed_config_drift_detected": true,
  "changed_seed_drift_detected": true,
  "contract_hash_pin_rejected": true,
  "dataset_hash_pin_rejected": true,
  "existing_target_rejected": true,
  "expected_first_step_loss": 5.071068286895752,
  "first_step_loss": 5.071068286895752,
  "loss_config": "ml/camera_coach/configs/loss_weights.json",
  "loss_config_hash_pin_rejected": true,
  "loss_config_sha256": "b48cfca4e8de5e5930ed8498f0220cb9591ebd0d5a71ba69f99a8f8a9783b4be",
  "loss_definition": "weighted_manifest_multitask_loss_before_one_sgd_step",
  "obsolete_mse_definition_rejected": true,
  "runtime_lock_hash_pin_rejected": true,
  "runtime_version_drift_rejected": true,
  "same_seed_projection_equal": true,
  "status": "pass",
  "weighted_loss_receipt_validated": true
}
```

The prior M4-006 smoke definition/value is intentionally superseded:

| Receipt | Definition | First-step value |
|---|---|---:|
| historical M4-006 | `mean_mse_over_manifest_heads_before_one_sgd_step` | `0.20278294384479523` |
| M4-007/M4-009 replacement | `weighted_manifest_multitask_loss_before_one_sgd_step` | `5.071068286895752` |

The values are synthetic one-step infrastructure receipts, not quality
measurements.  Same-seed projection equality, changed-seed/config drift,
source/runner/lock/self hashes, and existing-target rejection remain passing.

Because `train.py` changed its model-facing loss wiring, the candidate guard
was rerun:

```text
python3 -m ml.camera_coach.models.check_candidates
```

Result: `status=pass`; candidate A `295340192` MACs / `2320541` parameters,
candidate B `39246272` MACs / `411877` parameters, B/A ratio
`0.13288496812516462`, all nine output heads and existing deterministic,
missing-ROI, missing-scalar and finiteness checks passing.  This is an
architecture-contract regression check only, not candidate selection.

Static checks passed:

```text
python3 -m py_compile \
  ml/camera_coach/check_losses.py \
  ml/camera_coach/check_training_environment.py \
  ml/camera_coach/data/__init__.py \
  ml/camera_coach/data/check_preprocessing_parity.py \
  ml/camera_coach/data/preprocessing.py \
  ml/camera_coach/losses.py \
  ml/camera_coach/train.py
python3 -m json.tool ml/camera_coach/configs/loss_weights.json >/dev/null
python3 -m json.tool ml/camera_coach/configs/loss_weights.schema.json >/dev/null
python3 -m json.tool ml/camera_coach/configs/synthetic_dry_run.json >/dev/null
python3 -m json.tool ml/camera_coach/configs/training_config.schema.json >/dev/null
python3 -m json.tool ml/camera_coach/data/fixtures/preprocessing_parity.json >/dev/null
git diff --check
```

## Hashes and scope boundaries

| Artifact | SHA-256 |
|---|---|
| frozen manifest | `ef05756ac5c78d89d0ec9a14864d193357ced0e1925ef9759b6ab8e78c36e074` |
| frozen manifest schema | `a5a364c7deff7e5c831093110dc0d7c481c9df93357bf72c6ca4e61081f1fdfa` |
| runtime lock | `b3c308e04fc071402e14114e0fd43fd59677142f3e51a03bf2276c35b8ab0992` |
| training config | `8908f2f71037f75a77c95b49f3710c00e0a217a6107c3fbb3d60313af5d21f0c` |
| training config schema | `5f5b4c2d9627d774d16a82e842af6466936c41a5a5115da4e56a5bdda905b73a` |
| loss config | `b48cfca4e8de5e5930ed8498f0220cb9591ebd0d5a71ba69f99a8f8a9783b4be` |
| loss config schema | `415325ae7358510cf94ab2267f7746bbf05ecbd2c57a3cefd5c3ab2ec0f7bf76` |
| preprocessing parity fixture | `0870a298a11b446b5a32144166848b6128fe0b43580aa9d72bc1bc6bfefb384f` |
| preprocessing implementation | `7cf4f7313e75ac0e3cd2c872b2bbf54f6cd25d938c3899bd52e945bef04181f0` |
| preprocessing parity checker | `9f4f334429c5cf31068022ccd268be37abe279895cde87396e190ba64b380634` |
| loss implementation | `1a2b51ee5db3e792b3bbdec6253329f2b28f81908e02f6d551340cff58f05899` |
| loss checker | `df5bf900cc9b64233a36fbfcc116a1257d49414728969e0aff91618720fa5299` |
| synthetic dataset source | `b79d47e6df6e4a808a8d30065ec163ed341db905659261559e2643f1e2806f7f` |
| model source (unchanged) | `dee99381729988d3d8294293d8dc552cb3d5a4066891c4ab65418ea8c17854f4` |
| Swift parity test | `5b4df40c3c50adff92c8c60cf1f07352e132f203d5d004b7fd95357f8f9097de` |
| final training receipt content-stable projection | `46f7bde00cc2097a0bddb72f97436c3f00d18e6482c8bfd0562975eb498d07f9` |
| final realized synthetic dataset | `7bd736b492bb4651b2ddaac7f56360b88710e3632c16a9eb409a7a113490a458` |

No external data, human labels, locked holdout, network access, calibration,
Core ML conversion, model selection, or production route/provider enablement
was performed.  No temporary wheelhouse or virtual environment was created
in this slice; the only temporary Swift build/result tree was cleaned as
described above.

## Judgment calls and bounded gaps

- The ten explicit weights are pinned at `1.0` for this contract-only smoke;
  later training work may choose validated weights without changing the
  frozen head semantics or enabling a candidate.
- The `risk_probability` manifest head is a one-dimensional bounded
  probability, so its direct term is probability BCE; categorical scene
  supervision uses cross-entropy.  This follows the frozen output shape/range
  rather than inventing a second risk-class output.
- Pair labels are never inferred from pair names or from preference labels:
  contrastive supervision requires its own `contrastive_labels` field.
- Synthetic tensors and fixture hashes prove determinism and contract parity
  only.  They are not evidence of accuracy, safety, latency, thermal behavior,
  or user benefit.
