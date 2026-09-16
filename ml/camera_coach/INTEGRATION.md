# SETCompositionNet — Core ML integration

Status: **integrated and verified (research artifact, not release-wired).**
`SETCompositionNet-Stage2-Local.mlpackage` now ships in
`shafinMultitool/Multitool2Module/Models/CoreML/`, and
`Multitool2Module/Models/CoreMLWrappers/SETCompositionNetScorer.swift` loads it fail-closed.
`SETCompositionNetScorerTests` proves the artifact loads from the bundle, that its declared IO is
exactly the frozen 6-input / 9-output contract, and that an incomplete feature set returns nil
instead of fabricated scores (both tests pass on the iPhone 17e simulator).

No coaching path consumes the heads yet, by design: the artifact carries `research_only: true`,
`human_gold: false`, `release_admissible: false`. See "Gates" below.

Prepared 2026-09-13 alongside the local Stage-1 + Stage-2 training run
(`~/Documents/XCode/setos-backend/local-data/SETOS/Datasets/camera-coach/research/runs/`).

## What already exists in the app (do not duplicate)

| Piece | Path | Role |
|---|---|---|
| Typed runtime boundary | `Multitool2Module/Models/CameraAnalysis/SETCompositionNetRuntimeSchema.swift` | Validates input provenance and the output heads; fails closed on NaN, missing heads, wrong frame/generation, mismatched ROI |
| Frozen catalog mirror | `Multitool2Module/Models/CameraAnalysis/CameraAnalysisDomainContracts.swift` (`SETCompositionNetContract`) | Must stay in the same order as `ml/camera_coach/contracts/set_composition_net_v1.json` |
| Preprocessing helpers | `Multitool2Module/Utilities/Metal/MetalPreprocessor.swift` | Tensor layout for the neural input |
| Loader pattern to copy | `Multitool2Module/Models/CoreMLWrappers/AestheticScorer.swift` | `Bundle.main.url(forResource:withExtension: "mlmodelc") ?? …"mlpackage"`, `MLModel(contentsOf:configuration:)`, wrapped in `VNCoreMLModel` |

## What integrating a new candidate requires

1. ~~**Ship the package.**~~ **Done:** `SETCompositionNet-Stage2-Local.mlpackage` is in
   `shafinMultitool/Multitool2Module/Models/CoreML/`. Follow-up: a further candidate swap must
   re-check the Release bundle inventory (`CC-001`/`CC-002`), because model assets are excluded from
   some configurations by design and the current package is 4.6 MB.
2. ~~**Write the loader.**~~ **Done:** `Models/CoreMLWrappers/SETCompositionNetScorer.swift`
   follows `AestheticScorer`'s fail-closed pattern (missing/broken model ⇒ `nil`, never a fabricated score)
   and exposes `declaredIO()` so tests can pin the contract.
3. **Map the IO contract into the runtime owner** (still open — `SETCompositionNetRuntimeSchema`
   mapping of logits to `EvidenceHeadId` / `SupportingSignalTag` / `EvidenceCategoryId` must use the frozen
   catalog in `SETCompositionNetContract`, never an invented ordering). Raw tensors available from the
   loader (taken from the conversion receipt of the validated local run):

   | Input | Shape |
   |---|---|
   | `full_frame_rgb` | [1, 3, 320, 320] |
   | `subject_crop_rgb` | [1, 3, 192, 192] |
   | `roi_mask` | [1, 1, 320, 320] |
   | `roi_normalized_xywh` | [1, 4] |
   | `scalar_features` | [1, 40] |
   | `missing_feature_mask` | [1, 40] |

   | Output | Consumer |
   |---|---|
   | `scene_class_logits`, `subjectness_roi_agreement_logits` | scene/subject heads |
   | `issue_logits`, `action_utility_logits`, `continuous_target_deltas` | the three heads trained by the silver Stage-2 lane |
   | `good_frame_probability`, `abstention_probability`, `risk_probability` | keep/abstain/risk gating |
   | `embedding` | representation reuse |

   The `.mlpackage` metadata also records `minimum_deployment_target`, `precision`, `coremltools`/`torch`
   versions, and the parity report — keep them with the artifact.
4. **Bind provenance.** Every inference must carry the frame id, generation, orientation and ROI strategy
   through `SETCompositionNetInput`; the schema rejects mismatches instead of coercing them.
5. **Verify parity on device.** The offline parity report (`*.parity.json`, `atol` 5e-3) covers Core ML vs
   PyTorch on the conversion host; a device pass on the physical iPhone is still required before any
   coaching path consumes the head (this is the owner-gated physical step, not something the simulator can claim).

## Gates that still block shipping the model

The training lanes are explicitly research-only. Both the Stage-2 receipt and the conversion receipt carry
`research_only: true`, `human_gold: false`, `release_admissible: false`. Replacing the runtime model requires:

- human-gold labelling of the evaluation corpus (the silver labels are synthetic corruptions, not human judgement);
- an on-device evaluation pass on the physical iPhone 13 Pro;
- an accepted model-registry entry binding contract version, artifact hash and evaluation evidence.

Until those exist, the model can be measured and compared offline, but it must not be presented as a
production or release-ready Camera Coach model.
