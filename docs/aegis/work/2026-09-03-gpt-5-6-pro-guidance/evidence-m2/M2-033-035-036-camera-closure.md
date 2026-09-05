# M2-033 / M2-035 / M2-036 — Camera Coach closure

- Date: 2026-09-05
- Owner: Camera Coach closure lane
- Branch: `codex/set-os-m2-033-035-036`
- Base: `ed861ba`
- Device used for verification: iPhone Air, iOS 26.5,
  `A6E7238C-B4C6-4988-B399-8E127CA8683B`
- Device exclusions observed: no iPhone 17 Pro, no physical iPhone 13

## Scope delivered

This batch closes the three camera-closure contracts without changing
CommercialShell route semantics, asynchronous teardown ownership, or existing
accessibility identifiers.

### M2-033 — root control behavior

Camera Coach is the CommercialShell root in the shipped composition. Its top
chrome therefore does not render a non-functional close button. The reusable
chrome still accepts an optional real destination callback: when a composing
route supplies one, the xmark retains the existing `camera_coach_close`
identifier and the existing minimum 44-point hit target. The runtime root
passes no callback, so there is no misleading exit affordance. Pause remains
owned by the existing camera route and keeps `camera_coach_pause`.

The entry-flow and production UI checks assert both the root surface and the
absence of `camera_coach_close` at the root.

### M2-035 — production-owner closed loop

`CameraCoachClosedLoopTests` exercises the real owner chain rather than a mock
of the final planner or verifier:

1. `SceneSemanticsAnalyzer` and `FrameCritiqueEngine` produce the semantic
   candidate and issue evidence.
2. `RecommendationPlanner` resolves the bounded action and safety decision.
3. `AnalysisPipeline.testingPublishLivePresentation` and
   `testingPublishLiveCoachingEpisodeObservation` hand the stabilized episode
   through the production presentation owner to `CameraViewModel`. The live
   producer also carries active-lens provenance, immutable frame geometry and
   an episode-scoped frozen scene identity, so `ActionVerifier` compares the
   same capture provenance rather than a test-invented token.
4. `NeuralEvidenceInferenceService` runs through its typed provider seam and
   stores the resulting frame evidence in the production evidence store.
5. `UserMovementObserver` classifies relevant, no-op and opposite movement.
6. `ActionVerifier` returns the four-way comparable outcomes (improved,
   unchanged, worse) and fixed stability; protected select-subject, wait and
   abstain inputs remain fail-closed.

The scene identity is a bounded thresholded measurement, not the old exact
per-frame histogram: median exposure alignment ignores ordinary luminance
breathing, four local outliers are discarded, and a material distance rotates
the opaque identity. The `.12` structural-distance and `.18` exposure-tolerance
values are calibration points that require a physical-device capture corpus
before release; they do not disable the fail-closed lifecycle guard.

The test keeps the existing one-action safety boundary: no unsafe action is
published as a correction, no missing subject/evidence is treated as success,
and a stale/future neural result is rejected by the production freshness
contract.

### M2-036 — DEBUG true-process state coverage

`CameraCoachProductionUITests` launches the application process with the
existing DEBUG-only `-SHAFIN_CAMERA_PRODUCTION_FIXTURE` seam and enters the
shipped `SETCameraCoachProductionView` monitor surface. The matrix reaches
select-subject, wait, abstain, corrective, explanation, movement,
verification, keep, interrupted and recovery fixtures across portrait and
landscape. Existing pause, lens, ECO, failure, seeking and starting coverage
remains in the same production-surface suite. The owner-chain unit tests above
provide the deterministic semantic transitions behind the display fixtures;
the UI suite proves the app-process root, stable legacy fixture IDs,
`accessibilityValue` semantic mapping and orientation-safe surface reachability.

Fixture argument construction and the fixture root remain inside `#if DEBUG`.
The Release `SceneDelegate` overload accepts only the normal commercial root,
so Release has no public fixture switch or deterministic state injection.

## Changed files

- The complete nine-file batch scope from `ed861ba` through the closure
  commits is:

- `shafinMultitool/Multitool2Module/Services/Camera/CameraManager.swift` —
  ready-fixture active-lens provenance and real available-lens setup.
- `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift`
  — production owner handoff, immutable verification geometry, stable scene
  identity and corrective-episode admission.
- `shafinMultitool/Multitool2Module/UI/Overlay/OverlayView.swift` — remove the
  root environment-dismiss callback.
- `shafinMultitool/Multitool2Module/UI/Overlay/SETCameraCoachProductionView.swift`
  — explicit root close behavior and distinct DEBUG fixture semantic surfaces;
  legacy fixture IDs remain unchanged and semantic state is in the value.
- `shafinMultitool/Multitool2Module/ViewModels/CameraViewModel.swift` —
  DEBUG-only read seam for the production coordinator's immutable verifier pair.
- `shafinMultitoolTests/CameraCoachClosedLoopTests.swift` — production-owner
  closed-loop, neural evidence, movement, verification, fail-closed and scene
  identity stability/cut tests.
- `shafinMultitoolUITests/CameraCoachEntryFlowUITests.swift` — root close
  control contract assertion.
- `shafinMultitoolUITests/CameraCoachProductionUITests.swift` — root-control
  assertion and portrait/landscape fixture semantic-value matrix.
- `docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-m2/M2-033-035-036-camera-closure.md`
  — this evidence record.

No routes, `EXECUTION_STATE.md`, shared catalogs, project files, datasets,
History/Debug/Benchmark code, thesis/litreview files, or unrelated worktree
changes were touched.

## Focused verification

All commands were serial, used the allowed iPhone Air simulator, disabled
code signing, and used `-collect-test-diagnostics never`.

### M2-035 owner-chain unit suite

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=A6E7238C-B4C6-4988-B399-8E127CA8683B' \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests \
  -derivedDataPath /private/tmp/setos-m2-033-035-036-unit-owners-air-scene-dd \
  -resultBundlePath /private/tmp/setos-m2-033-035-036-unit-owners-air-closed-loop-final2.xcresult \
  CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never \
  -parallel-testing-enabled NO
```

Result: `** TEST SUCCEEDED **`; 4/4 tests passed, 0 failed, 0 skipped.
The suite covered the production owner handoff, protected safety decisions,
neural evidence execution, movement observation, ActionVerifier outcomes and
the stable-scene/material-cut contract. This is the original 3-test closure
suite plus the new scene-identity test.

### M2-035 scene identity focused run

The same production helper was first run directly before the full class:

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=A6E7238C-B4C6-4988-B399-8E127CA8683B' \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testProductionSceneIdentityIgnoresNoiseAndLocalMotionButRotatesOnMaterialCut \
  -derivedDataPath /private/tmp/setos-m2-033-035-036-unit-owners-air-scene-dd \
  -resultBundlePath /private/tmp/setos-m2-033-035-036-unit-owners-air-scene.xcresult \
  CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never \
  -parallel-testing-enabled NO
```

Result: `** TEST SUCCEEDED **`; 1/1 test passed, 0 failed, 0 skipped.

### M2-036 production Camera UI matrix

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=A6E7238C-B4C6-4988-B399-8E127CA8683B' \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:shafinMultitoolUITests/CameraCoachProductionUITests \
  -derivedDataPath /private/tmp/setos-m2-033-035-036-unit-owners-air-scene-dd \
  -resultBundlePath /private/tmp/setos-m2-033-035-036-ui-production-air-final3.xcresult \
  CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never
```

Result: `** TEST SUCCEEDED **`; 10/10 tests passed, 0 failed, 0 skipped,
including the new 10-fixture portrait/landscape matrix. The result bundle
contains the production-surface screenshots attached by the UI test. The
semantic assertions query the original fixture IDs and verify the mapped state
through `accessibilityValue`; no legacy ID was replaced.

### M2-033 entry/root contract

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=A6E7238C-B4C6-4988-B399-8E127CA8683B' \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:shafinMultitoolUITests/CameraCoachEntryFlowUITests \
  -derivedDataPath /private/tmp/setos-m2-033-035-036-evidence-dd \
  -resultBundlePath /private/tmp/setos-m2-033-035-036-camera-entry-ui-air-final.xcresult \
  CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never
```

Result: `** TEST SUCCEEDED **`; 9/9 tests passed, 0 failed, 0 skipped.

### M2-033 source composition

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=A6E7238C-B4C6-4988-B399-8E127CA8683B' \
  -only-testing:shafinMultitoolTests/CommercialShellLaunchCompositionTests/testNormalCompositionSelectsCameraAndKeepsSecondaryRoutesLazy \
  -derivedDataPath /private/tmp/setos-m2-033-035-036-evidence-dd \
  -resultBundlePath /private/tmp/setos-m2-033-035-036-composition-air-final.xcresult \
  CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never \
  -parallel-testing-enabled NO
```

Result: `** TEST SUCCEEDED **`; 1/1 test passed, 0 failed, 0 skipped. The
composition owner selects Camera as the CommercialShell root while retaining
secondary routes as lazy alternatives, which makes omission of a root xmark
truthful.

An earlier UI retry was an infrastructure failure before test execution:
SpringBoard returned `FBSOpenApplicationServiceErrorDomain / RequestDenied`
with `Busy`; it executed zero tests and is not counted as a product test
failure. The subsequent Air rerun above completed all 10 tests.

### Release build and DEBUG isolation

```text
xcodebuild build -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/setos-m2-033-035-036-release-dd \
  CODE_SIGNING_ALLOWED=NO
```

Result: exit `0`; the Release product was emitted at
`/private/tmp/setos-m2-033-035-036-release-dd/Build/Products/Release-iphonesimulator/shafinMultitool.app/shafinMultitool`.
`nm -gU` and `strings` found no `testingLiveSceneIdentity` or
`testingResetLiveSceneIdentity` symbols in that binary. The Release build
retained existing compiler warnings only (including known deprecations and
`Circle.rcproject` resource warnings).

## Contract and visual audit

- `git diff --check`: passed.
- No changed production code introduces material/blur/shadow/gradient or a
  second visual system; existing SET tokens and production presentation owners
  remain authoritative.
- Existing `camera_coach_pause`, `camera_coach_live_surface`, all fixture IDs
  and any real `camera_coach_close` IDs are preserved; only the non-functional
  root close is absent. Fixture semantic states are exposed through the
  non-breaking accessibility value.
- The camera per-frame surface remains a deterministic presentation layer; no
  decorative invalidation or layout churn was added.
- Fixture selection is DEBUG-only and is not a Release runtime backdoor.
- Retained result bundles are the Air paths listed above, including the scene
  identity, closed-loop, production UI, entry UI and composition bundles.
  Completed task-owned DerivedData was removed after the final evidence was
  retained; the xcresult bundles remain.

## Post-audit correction — frame-bound provenance and scene-cut recovery

The Sol audit identified a provenance gap in the earlier closure: a subject
comparison could be built with an analysis/source-size identity transform, and
the mutable manager lens could be read after capture. This correction keeps the
existing production owners and makes the comparison frame-bound:

- `CameraPreviewGeometry` is one immutable, validated carrier for the actual
  preview-layer destination size, ImageIO orientation and mirror state. The
  `CameraManager` stores it behind a lock; `PreviewView` publishes it only
  after a live connection, attached window and non-zero layer bounds exist, and
  clears it when those facts disappear.
- `CameraManager.captureOutput` takes one capture-bound lock snapshot of image
  orientation, active-lens ID, capture generation and matching preview
  geometry. `FrameContext` carries the values through
  `LatestFrameEvidenceStore.Snapshot` and `AcceptedFrameEnvelope`, including
  pause acceptance; later lens changes cannot rewrite accepted provenance.
- `AnalysisPipeline` builds `ActionVerificationGeometryContext` only from the
  immutable envelope. It rotates raw buffer dimensions for ImageIO left/right
  orientations, uses the actual preview destination and captured mirroring,
  and returns no geometry for missing, invalid or orientation-mismatched
  provenance. Subject-bound verification therefore remains fail-closed.
- `.sceneCut` is a retryable same-capture cancellation. The existing pipeline
  owner reset path clears the terminal episode so the next admissible baseline
  receives a fresh token; capture, lens, orientation and route boundaries stay
  non-retryable. The existing frozen, thresholded scene identity remains the
  producer-side scene owner. Its `.12` structural distance, `.18` exposure
  tolerance and four-outlier profile are explicitly uncalibrated until a
  physical-device corpus is available.

### Correction delta files

The post-audit correction changed only the following owned files in addition to
the previously documented closure commit:

- `shafinMultitool/Multitool2Module/Models/CameraAnalysis/CoachingEpisodeCoordinator.swift`
  — permits typed scene-cut retry.
- `shafinMultitool/Multitool2Module/Services/Camera/CameraManager.swift` —
  validated preview geometry, lock-backed capture provenance and lifecycle
  clearing.
- `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift`
  — frame-bound envelope propagation and verifier geometry construction.
- `shafinMultitool/Multitool2Module/Services/Pipeline/LatestFrameEvidenceStore.swift`
  — immutable lens/geometry propagation through snapshots and envelopes.
- `shafinMultitool/Multitool2Module/Services/Pipeline/RealtimeScheduler.swift`
  — frame-context provenance fields.
- `shafinMultitool/Multitool2Module/UI/Overlay/OverlayView.swift` — actual
  preview-layer geometry publication and clearing.
- `shafinMultitoolTests/CameraCoachClosedLoopTests.swift` — frame-bound
  geometry assertions and production closed-loop evidence.
- `shafinMultitoolTests/CameraManagerLifecycleTests.swift` — geometry owner
  validation/clearing.
- `shafinMultitoolTests/CoachingEpisodeCoordinatorTests.swift` — scene-cut
  cancellation and fresh-baseline recovery.
- `shafinMultitoolTests/LatestFrameEvidenceStoreTests.swift` — accepted-frame
  lens/geometry immutability and orientation mismatch rejection.
- This evidence file.

No `SubjectTracker.swift` change was necessary; its IoU and lifecycle contract
remain untouched. No route, accessibility-ID, catalog, fixture-root, release
surface, thesis/litreview or user file changed.

### Correction verification

All simulator tests below used iPhone Air (iOS 26.5,
`A6E7238C-B4C6-4988-B399-8E127CA8683B`), serial execution, code signing
disabled and `-collect-test-diagnostics never`. No iPhone 17 Pro was targeted.

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=A6E7238C-B4C6-4988-B399-8E127CA8683B' \
  -derivedDataPath /private/tmp/setos-m2-camera-provenance-unit-dd \
  -resultBundlePath /private/tmp/setos-m2-camera-provenance-unit.xcresult \
  CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never \
  -parallel-testing-enabled NO \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testProductionOwnersAdvanceSubjectSelectionThroughStabilizedEpisode \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testProductionSceneIdentityIgnoresNoiseAndLocalMotionButRotatesOnMaterialCut \
  -only-testing:shafinMultitoolTests/CoachingEpisodeCoordinatorTests/testSceneCutCancellationAdmitsFreshBaselineWithinSameCapture \
  -only-testing:shafinMultitoolTests/LatestFrameEvidenceStoreTests/testAcceptedFrameKeepsFrameBoundLensAndPreviewGeometryAfterLensChanges \
  -only-testing:shafinMultitoolTests/LatestFrameEvidenceStoreTests/testMismatchedPreviewGeometryIsUnavailableAtImmutableBoundary \
  -only-testing:shafinMultitoolTests/CameraManagerLifecycleTests/testPreviewGeometryIsValidatedAndClearedByItsCameraOwner
```

Result: `** TEST SUCCEEDED **`; 6/6 tests passed, 0 failed, 0 skipped.

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=A6E7238C-B4C6-4988-B399-8E127CA8683B' \
  -derivedDataPath /private/tmp/setos-m2-camera-provenance-unit-dd \
  -resultBundlePath /private/tmp/setos-m2-camera-provenance-closed-loop-final.xcresult \
  CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never \
  -parallel-testing-enabled NO \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests
```

Result: `** TEST SUCCEEDED **`; 4/4 production closed-loop tests passed, 0
failed, 0 skipped. Bundle: `/private/tmp/setos-m2-camera-provenance-closed-loop-final.xcresult`.

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=A6E7238C-B4C6-4988-B399-8E127CA8683B' \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:shafinMultitoolUITests/CameraCoachProductionUITests \
  -derivedDataPath /private/tmp/setos-m2-camera-provenance-unit-dd \
  -resultBundlePath /private/tmp/setos-m2-camera-provenance-ui-production-final.xcresult \
  CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never
```

Result: `** TEST SUCCEEDED **`; 10/10 production UI tests passed, 0 failed,
0 skipped, including portrait/landscape, fixture semantics, pause/lens,
Reduce Motion and Dynamic Type. Bundle:
`/private/tmp/setos-m2-camera-provenance-ui-production-final.xcresult`.

```text
xcodebuild build -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/setos-m2-camera-provenance-release-dd \
  -resultBundlePath /private/tmp/setos-m2-camera-provenance-release.xcresult \
  CODE_SIGNING_ALLOWED=NO
```

Result: exit `0`; Release bundle:
`/private/tmp/setos-m2-camera-provenance-release.xcresult`; product:
`/private/tmp/setos-m2-camera-provenance-release-dd/Build/Products/Release-iphonesimulator/shafinMultitool.app/shafinMultitool`.
The Release binary contained none of the selected DEBUG fixture/probe strings
(`previewGeometryForTesting`, `testingLiveSceneIdentity`,
`testingResetLiveSceneIdentity`, `SHAFIN_CAMERA_PRODUCTION_FIXTURE`).

`git diff --check` passed. The final Air xcresult bundles above were retained;
completed task-owned DerivedData was removed after evidence capture. Existing
M2-033 composition and entry-flow bundles remain the previously recorded Air
artifacts because this correction did not alter routes or root-control
semantics.

## Fresh Sol/High correction — atomic geometry publication and stale stream rejection

The earlier `6/6` correction claim above is superseded for the camera
boundary findings: it covered direct manager/store/coordinator seams but did
not prove the real `CameraManager.captureOutput` or `PreviewView` lifecycle
owners. The first boundary correction is also superseded where it described
an unlocked manager equality fast path and did not prove stale pre-cut event
rejection. This correction keeps the production changes narrow and adds the
missing atomicity and pipeline-to-view-model assertions.

- `CameraManagerLifecycleTests/testCaptureOutputBindsLensAndPreviewGeometryBeforeAnalysisPipelineReceivesFrame`
  invokes the actual `CameraManager.captureOutput` with a real video sample
  buffer, drains the production scheduler/pipeline, and verifies that the
  accepted evidence retains the active lens, orientation, capture generation
  and preview geometry.
- `CameraManagerLifecycleTests/testPreviewViewClearsStaleGeometryWhenRemovedFromWindow`
  attaches the real `PreviewView` to a `UIWindow`, seeds geometry through the
  camera owner, removes the view, and verifies that the production
  `didMoveToWindow` seam clears stale geometry.
- `CameraManagerLifecycleTests/testPreviewViewDoesNotRepublishGeometryForUnchangedRegionUpdate`
  exercises the real `PreviewView` with a synthetic video connection only for
  the hardware-free lifecycle seam, then drives a region/layout update and
  proves the manager boundary is not entered again for identical geometry.
- `CameraManagerLifecycleTests/testCameraPreviewRebindingClearsOldOwnerAndRepublishesGeometryToNewOwner`
  drives the shared `CameraPreview` owner-update path with a retained
  `PreviewView`, replaces both its session and manager, and verifies the old
  manager is cleared while the new manager receives the same geometry. This
  closes the long-lived UIView identity/rebinding case without assuming that
  SwiftUI always recreates the representable.
- `CameraManagerLifecycleTests/testConcurrentPreviewGeometryUpdatesRevalidateEqualityAtCaptureBoundary`
  overlaps two identical geometry publications using a DEBUG-only
  synchronization hook. The capture-boundary mutation count is one, proving
  equality is revalidated while the boundary lock is held; this is the
  deterministic atomicity equivalent for concurrent clear/update ordering.
- `CameraCoachClosedLoopTests/testProductionSceneCutFlowsThroughViewModelAndRetriesWithinSameCapture`
  consumes `.sceneCut` through the actual `CameraViewModel` subscriber, then
  publishes a valid late pre-cut `CoachingEpisodeFrameEvidence` through the
  `AnalysisPipeline` typed event stream. It asserts phase, token, baseline,
  last-frame ID and movement/stability counters remain unchanged. Fresh
  post-cut frames then admit a new baseline and episode token within the same
  capture. The test does not call the coordinator directly.
- `CameraManager.updatePreviewGeometry` now takes the capture-boundary lock
  before equality revalidation and mutation, matching the frame-provenance
  ordering; concurrent clear/update cannot publish from an unlocked
  time-of-check/time-of-use window. `PreviewView` locally publishes geometry
  only when its immutable value changes, while real bounds, orientation and
  mirroring changes still publish and invalid lifecycle state clears. The
  `CameraPreview.updateUIView` owner path clears the old manager and resets
  the local geometry/orientation cache whenever its manager or session
  identity changes, so the new owner cannot inherit a skipped publication.
  `PreviewView.updateMappedRegions` no longer republishes geometry during
  region-only updates.

Focused production-boundary command:

```text
xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=A6E7238C-B4C6-4988-B399-8E127CA8683B' \
  -derivedDataPath /private/tmp/m2-camera-second-correction-focused-dd \
  -resultBundlePath /private/tmp/m2-camera-second-correction-focused-final.xcresult \
  CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never \
  -parallel-testing-enabled NO \
  -only-testing:shafinMultitoolTests/CameraManagerLifecycleTests/testPreviewViewDoesNotRepublishGeometryForUnchangedRegionUpdate \
  -only-testing:shafinMultitoolTests/CameraManagerLifecycleTests/testConcurrentPreviewGeometryUpdatesRevalidateEqualityAtCaptureBoundary \
  -only-testing:shafinMultitoolTests/CameraManagerLifecycleTests/testPreviewViewClearsStaleGeometryWhenRemovedFromWindow \
  -only-testing:shafinMultitoolTests/CameraManagerLifecycleTests/testCameraPreviewRebindingClearsOldOwnerAndRepublishesGeometryToNewOwner \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testProductionSceneCutFlowsThroughViewModelAndRetriesWithinSameCapture
```

Result: exit `0`; the Air result summary reports 5/5 passed, 0 failed, 0
skipped. Summary bundle:
`/private/tmp/m2-camera-second-correction-focused-rebinding.xcresult`.

Unit regression command:

```text
xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=A6E7238C-B4C6-4988-B399-8E127CA8683B' \
  -derivedDataPath /private/tmp/m2-camera-second-correction-regression-dd \
  -resultBundlePath /private/tmp/m2-camera-second-correction-regression-rebinding.xcresult \
  CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never \
  -parallel-testing-enabled NO \
  -only-testing:shafinMultitoolTests/CameraManagerLifecycleTests \
  -only-testing:shafinMultitoolTests/LatestFrameEvidenceStoreTests \
  -only-testing:shafinMultitoolTests/CoachingEpisodeCoordinatorTests \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testProductionOwnersAdvanceSubjectSelectionThroughStabilizedEpisode \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testProductionSceneIdentityIgnoresNoiseAndLocalMotionButRotatesOnMaterialCut \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testProductionSceneCutFlowsThroughViewModelAndRetriesWithinSameCapture
```

Result: exit `0`; the Air result summary reports 53/53 passed, 0 failed, 0
skipped. This is three tests larger than the prior 50-test command because it
includes the two new PreviewView/manager atomicity tests and the retained
UIView-owner rebinding test. Summary bundle:
`/private/tmp/m2-camera-second-correction-regression-rebinding.xcresult`.

Focused production UI command (required because the preview owner changed):

```text
xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=A6E7238C-B4C6-4988-B399-8E127CA8683B' \
  -derivedDataPath /private/tmp/m2-camera-second-correction-ui-dd \
  -resultBundlePath /private/tmp/m2-camera-second-correction-ui-rebinding.xcresult \
  CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never \
  -parallel-testing-enabled NO \
  -only-testing:shafinMultitoolUITests/CameraCoachProductionUITests
```

Result: exit `0`; the Air result summary reports 10/10 passed, 0 failed, 0
skipped, with retained accessibility-ID assertions. Summary bundle:
`/private/tmp/m2-camera-second-correction-ui-rebinding.xcresult`. No iPhone 17 Pro
target appears in any command or result summary; no Release fixture strings
were touched by this correction.

`git diff --check` passed, and the final changed paths remain within the
specified owned set. No changes were needed in `AnalysisPipeline.swift`,
`LatestFrameEvidenceStore.swift`, `CameraViewModel.swift`,
`CoachingEpisodeCoordinatorTests.swift` or
`LatestFrameEvidenceStoreTests.swift`; the existing frame-bound and retry
contracts in those files were exercised by the new boundary tests and
regression group.

## Final Sol/High correction — exact sample/session provenance and real capture-path evidence

This section supersedes the preceding correction claims wherever they called
the direct typed scene-cut fixture the decisive stale-frame proof, said that
`AnalysisPipeline.swift` and `LatestFrameEvidenceStore.swift` needed no
changes, or treated callback `Date` ordering as sufficient. The final bounded
correction carries the exact `CMSampleBuffer` presentation timestamp and
`CameraManager` session generation from `captureOutput` through
`FrameContext`, the immutable evidence snapshot and `AcceptedFrameEnvelope`,
and the live feature provenance. Within one session/capture epoch, the store
orders by numeric `CMTime`; session and capture-generation changes start a
new ordering epoch. Callback `capturedAt` remains a wall-clock freshness
value and is used for ordering only for fully legacy values with no session or
numeric sample timestamp. The pipeline checks the same comparator before
expensive work and the store repeats it while locked at publication.

The only deterministic test seam is the DEBUG-only Vision result provider at
the earliest ML boundary. The decisive tests still invoke the real
`CameraManager.captureOutput` with synthetic `CMSampleBuffer` values, the
real `RealtimeScheduler`, the real `AnalysisPipeline`, and the real
`CameraViewModel` publication path. No direct evidence-store injection or
late presentation publisher is used by these tests.

The first red capture-boundary retry was diagnosed as the scheduler cadence
gate, not a provenance drop: callbacks delivered faster than the nominal 6 Hz
high-priority interval were intentionally skipped, so the expected sample PTS
was not yet the latest accepted PTS. The fixture now spaces callbacks by 180
ms and waits for the actual high queue, preserving the production cadence and
making the boundary assertion report its sample index and PTS.

### Focused exact provenance and production-path run

```text
xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=A6E7238C-B4C6-4988-B399-8E127CA8683B' \
  -derivedDataPath /private/tmp/m2-camera-final-provenance-focused-1788621503-dd \
  -resultBundlePath /private/tmp/m2-camera-final-provenance-focused-1788621503.xcresult \
  CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never \
  -parallel-testing-enabled NO \
  -only-testing:shafinMultitoolTests/CameraManagerLifecycleTests/testCaptureOutputBindsLensAndPreviewGeometryBeforeAnalysisPipelineReceivesFrame \
  -only-testing:shafinMultitoolTests/LatestFrameEvidenceStoreTests/testKnownSamplePTSAndSessionGenerationRejectLateOlderEvidence \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testProductionCapturePathPublishesCorrectiveAndHonestAbstention \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testProductionCapturePathSceneCutRejectsLatePreCutSampleAndRetries
```

Result: exit `0`; Air summary reports `totalTestCount: 4`,
`passedTests: 4`, `failedTests: 0`, `skippedTests: 0`, `result: Passed`.
The capture-boundary test verifies exact PTS `1/30`, session generation and
capture generation in the evidence and envelope. The closed-loop corrective
test reaches a ViewModel baseline through captureOutput and separately proves
an unsupported frame remains an abstention. The scene-cut test rejects a late
pre-cut sample with older PTS after cancellation and then admits a fresh
post-cut baseline with a new token in the same capture/session.

The corrective capture test was rerun alone after the cadence diagnosis:

```text
xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=A6E7238C-B4C6-4988-B399-8E127CA8683B' \
  -derivedDataPath /private/tmp/m2-camera-corrective-capture-final-dd \
  -resultBundlePath /private/tmp/m2-camera-corrective-capture-final.xcresult \
  CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never \
  -parallel-testing-enabled NO \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testProductionCapturePathPublishesCorrectiveAndHonestAbstention
```

Result: exit `0`; Air summary reports `totalTestCount: 1`,
`passedTests: 1`, `failedTests: 0`, `skippedTests: 0`, `result: Passed`.

### Historical 53-test regression selection

The prior 53-test selection was rerun with the new standalone PTS/store test
excluded so its historical count remains comparable; that new test is included
in the focused four-test run above.

```text
xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=A6E7238C-B4C6-4988-B399-8E127CA8683B' \
  -derivedDataPath /private/tmp/m2-camera-final-provenance-regression53-1788621503-dd \
  -resultBundlePath /private/tmp/m2-camera-final-provenance-regression53-1788621503.xcresult \
  CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never \
  -parallel-testing-enabled NO \
  -only-testing:shafinMultitoolTests/CameraManagerLifecycleTests \
  -only-testing:shafinMultitoolTests/LatestFrameEvidenceStoreTests \
  -skip-testing:shafinMultitoolTests/LatestFrameEvidenceStoreTests/testKnownSamplePTSAndSessionGenerationRejectLateOlderEvidence \
  -only-testing:shafinMultitoolTests/CoachingEpisodeCoordinatorTests \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testProductionOwnersAdvanceSubjectSelectionThroughStabilizedEpisode \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testProductionSceneIdentityIgnoresNoiseAndLocalMotionButRotatesOnMaterialCut \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testTypedSceneCutCoordinatorFixtureRetainsTerminalState
```

Result: exit `0`; Air summary reports `totalTestCount: 53`,
`passedTests: 53`, `failedTests: 0`, `skippedTests: 0`, `result: Passed`.

The retained production UI result bundle
`/private/tmp/m2-camera-second-correction-ui-rebinding.xcresult` reports the
allowed Air device and `totalTestCount: 10`, `passedTests: 10`,
`failedTests: 0`, `skippedTests: 0`, `result: Passed`; accessibility IDs were
retained. A fresh Release rebuild of the current tree was attempted but was
blocked by the host disk reaching `100%` while another task's temporary
DerivedData was active; the prior Release fixture-string result remains
valid for the unchanged UI/fixture boundary, and the coordinator must rerun
the current-tree Release guard after serializing temporary storage.

`git diff --check` passed. No iPhone 17 Pro or physical device was targeted.
The only additional production-range file needed for this correction was
`RealtimeScheduler.swift`, because `FrameContext` is the existing owner-path
carrier for the new session/PTS provenance.

## Remaining boundary

Simulator and unit evidence cannot prove physical-device ARKit tracking,
camera/microphone permission hardware, Photos authorization, actual video
recording/playback, A/V sync, thermal behavior or hardware timing. Those remain
the explicit device-verification boundary and require an owner-supplied test
device; this batch does not claim them.

## Pending integration

The parent coordinator must inspect this batch diff, integrate the local commit,
and retain the result bundles for the M2 gate. No M2-GATE claim is made here.

## Final correction — automatic verification, exact provenance, and duplicate PTS

This section supersedes the preceding evidence wherever it described a direct
typed-fixture handoff as decisive automatic-verification evidence, or described
sample ordering without the complete PTS/session tuple. The current correction
keeps the production owner in `CameraViewModel`: a generation-fenced transition
to `.readyForVerification` obtains the coordinator's immutable before/after pair,
calls the existing `ActionVerifier` once for that episode token, and retains the
result while unrelated live frames arrive. New baseline/cancel/release boundaries
clear the result. The pair carries exact `CMSampleBuffer` PTS and
`CameraManager` session generation through `FrameContext`, accepted evidence,
`UserMovementEvidence`, coordinator baseline/current state, and the verifier.
Known samples order by PTS within the same session/capture epoch; callback
`Date` remains wall-clock freshness/expiry only. Equal known PTS is accepted only
for the same immutable buffer/provenance; a conflicting retransmission is
rejected without replacing the stored snapshot.

The decisive closed-loop tests deliver synthetic `CMSampleBuffer` instances to
the real `CameraManager.captureOutput` callback, then use the real
`RealtimeScheduler`, `AnalysisPipeline`, and `CameraViewModel` publication path.
The only deterministic seam is the DEBUG Vision provider at the earliest ML
boundary. No direct evidence-store, event, verifier, or presentation publisher
is used by these decisive tests. A late pre-cut sample is sent through the same
capture callback after scene-cut cancellation; state, token, baseline, accepted
evidence, live presentation, scene identity, and pipeline provenance remain
unchanged before fresh post-cut samples establish a new baseline/token.

### Focused automatic-verification and provenance run

```text
xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=A6E7238C-B4C6-4988-B399-8E127CA8683B' \
  -derivedDataPath /private/tmp/m2-camera-auto-dd \
  -resultBundlePath /private/tmp/m2-camera-auto-scenecut2.xcresult \
  CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testProductionCapturePathAutomaticallyVerifiesCorrectiveEpisode \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testProductionCapturePathSceneCutRejectsLatePreCutSampleAndRetries \
  -only-testing:shafinMultitoolTests/LatestFrameEvidenceStoreTests/testKnownSamplePTSAndSessionGenerationRejectLateOlderEvidence \
  -only-testing:shafinMultitoolTests/LatestFrameEvidenceStoreTests/testEqualKnownPTSRejectsConflictingEvidenceWithoutMutation \
  -only-testing:shafinMultitoolTests/LatestFrameEvidenceStoreTests/testEqualKnownPTSAcceptsOnlyIdempotentRetransmissionWithoutReplacement
```

Result: exit `0`; Air summary reports `totalTestCount: 5`,
`passedTests: 5`, `failedTests: 0`, `skippedTests: 0`, `result: Passed` in
`/private/tmp/m2-camera-auto-scenecut2.xcresult`. The automatic path classified
the corrective episode as `.improved` without a testing apply/verify call and
retained it after an unrelated live sample. The scene-cut path rejected the
late older-PTS sample and admitted a fresh post-cut baseline/token in the same
capture/session. The store tests prove conflicting equal-PTS non-replacement
and idempotent equal-PTS retention.

The three-test automatic/store subset also passed `3/3` in
`/private/tmp/m2-camera-auto-focused2.xcresult`; the lifecycle-order repair plus
both real capture-path tests passed `3/3` in
`/private/tmp/m2-camera-auto-coordinator-fix2.xcresult`.

### Current-head regression selections on Air

The broader affected selection (Camera lifecycle, evidence store, coordinator,
verifier, and retained production-owner/scene tests) passed `72/72`,
`0` failed, `0` skipped in
`/private/tmp/m2-camera-auto-regression-final.xcresult`. The historical
comparable selection was rerun with the three newly added duplicate-PTS tests
excluded and passed `53/53`, `0` failed, `0` skipped in
`/private/tmp/m2-camera-auto-regression53-final.xcresult`.

```text
xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=A6E7238C-B4C6-4988-B399-8E127CA8683B' \
  -derivedDataPath /private/tmp/m2-camera-auto-regression53-dd \
  -resultBundlePath /private/tmp/m2-camera-auto-regression53-final.xcresult \
  CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:shafinMultitoolTests/CameraManagerLifecycleTests \
  -only-testing:shafinMultitoolTests/LatestFrameEvidenceStoreTests \
  -skip-testing:shafinMultitoolTests/LatestFrameEvidenceStoreTests/testKnownSamplePTSAndSessionGenerationRejectLateOlderEvidence \
  -skip-testing:shafinMultitoolTests/LatestFrameEvidenceStoreTests/testEqualKnownPTSRejectsConflictingEvidenceWithoutMutation \
  -skip-testing:shafinMultitoolTests/LatestFrameEvidenceStoreTests/testEqualKnownPTSAcceptsOnlyIdempotentRetransmissionWithoutReplacement \
  -only-testing:shafinMultitoolTests/CoachingEpisodeCoordinatorTests \
  -only-testing:shafinMultitoolTests/ActionVerifierTests \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testProductionOwnersAdvanceSubjectSelectionThroughStabilizedEpisode \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testProductionSceneIdentityIgnoresNoiseAndLocalMotionButRotatesOnMaterialCut \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testTypedSceneCutCoordinatorFixtureRetainsTerminalState
```

### Current-head Release boundary

The production Release app was compiled on the allowed iPhone Air simulator with
bounded DerivedData:

```text
xcodebuild build -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -configuration Release \
  -destination 'platform=iOS Simulator,id=A6E7238C-B4C6-4988-B399-8E127CA8683B' \
  -derivedDataPath /private/tmp/m2-camera-auto-release-app-dd \
  CODE_SIGNING_ALLOWED=NO
```

Result: exit `0`; product:
`/private/tmp/m2-camera-auto-release-app-dd/Build/Products/Release-iphonesimulator/shafinMultitool.app`.
`strings` and `nm -gU` audits returned no matches for
`SHAFIN_CAMERA_PRODUCTION_FIXTURE`, `testingPublishLivePresentation`,
`testingLiveSceneIdentity`, `testingResetLiveSceneIdentity`, or
`previewGeometryForTesting`. A Release `build-for-testing` of the entire test
bundle is not a valid artifact for this repository because the tests use
`@testable` and DEBUG-only test seams; those attempts failed at test compilation
with the expected excluded-symbol errors, while the production Release app
compile above succeeded.

The prior Air production-UI bundle remains `10/10` passed at
`/private/tmp/m2-camera-second-correction-ui-rebinding.xcresult`. A fresh
current-tree UI attempt was interrupted by the host's Xcode simulator worker
launch/debugger-store failure before a result bundle could be saved; no product
failure is inferred from that infrastructure interruption. No iPhone 17 Pro or
physical device was targeted.

`git diff --check` passed after this update. Changed paths remain within the
M2 correction scope; no Release fixture behavior, routes, teardown, or
accessibility IDs changed.

## P0 correction — complete DETR provenance tuple at the adapter boundary

This section supersedes the preceding claim that the exact PTS/session tuple
was fully validated for every attributed DETR sample. The prior production
DETR sample carried the tuple, but `makeFeatureSnapshot` constructed its
expected provenance with the legacy `.invalid` PTS and `nil` session. Exact
equality therefore discarded every fully attributed production DETR sample.
The bounded fix passes the accepted frame's exact PTS and session generation
into the expected provenance for all three owner paths: live moving/stability,
live still, and pause. Legacy callers without a capture context retain their
existing compatibility behavior.

The existing adapter test now covers a matching production tuple and rejects
the same frame/lens/orientation when either PTS or session generation differs;
the rejected path clears DETR instead of falling back to stale debug detections.

### Focused DETR provenance run

```text
xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=A6E7238C-B4C6-4988-B399-8E127CA8683B' \
  -derivedDataPath /private/tmp/m2-camera-auto-dd \
  -resultBundlePath /private/tmp/m2-camera-detr-fix.xcresult \
  CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:shafinMultitoolTests/LatestFrameEvidenceStoreTests/testDetrProvenanceMustMatchFrameGenerationAndOrientation \
  -only-testing:shafinMultitoolTests/PipelineFeatureSnapshotAdapterTests/testAdapterDoesNotCreateFallbackSamplesWithoutMeasuredAt
```

Result: exit `0`; Air summary reports `totalTestCount: 2`, `passedTests: 2`,
`failedTests: 0`, `skippedTests: 0`, `result: Passed` in
`/private/tmp/m2-camera-detr-fix.xcresult`.

### Affected closed-loop run after the P0 fix

```text
xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=A6E7238C-B4C6-4988-B399-8E127CA8683B' \
  -derivedDataPath /private/tmp/m2-camera-auto-dd \
  -resultBundlePath /private/tmp/m2-camera-detr-closedloop.xcresult \
  CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testProductionCapturePathAutomaticallyVerifiesCorrectiveEpisode \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testProductionCapturePathSceneCutRejectsLatePreCutSampleAndRetries \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testProductionCapturePathPublishesCorrectiveAndHonestAbstention \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testProductionOwnersAdvanceSubjectSelectionThroughStabilizedEpisode
```

Result: exit `0`; Air summary reports `totalTestCount: 4`, `passedTests: 4`,
`failedTests: 0`, `skippedTests: 0`, `result: Passed` in
`/private/tmp/m2-camera-detr-closedloop.xcresult`. These tests retain the real
capture callback, scheduler, pipeline, and ViewModel path; no direct DETR or
presentation injection was added.

### Current-head Release compile and seam audit

```text
xcodebuild build -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -configuration Release \
  -destination 'platform=iOS Simulator,id=A6E7238C-B4C6-4988-B399-8E127CA8683B' \
  -derivedDataPath /private/tmp/m2-camera-detr-release-dd \
  CODE_SIGNING_ALLOWED=NO
```

Result: exit `0`; product:
`/private/tmp/m2-camera-detr-release-dd/Build/Products/Release-iphonesimulator/shafinMultitool.app`.
`strings` and `nm -gU` returned no matches for the selected DEBUG fixture/test
seams (`SHAFIN_CAMERA_PRODUCTION_FIXTURE`, `testingPublishLivePresentation`,
`testingLiveSceneIdentity`, `testingResetLiveSceneIdentity`,
`previewGeometryForTesting`). The permitted destination was iPhone Air only;
no iPhone 17 Pro or physical device was targeted.

`git diff --check` passed for this P0 correction. The earlier `53/53` unit and
retained `10/10` production-UI Air bundles remain applicable because this fix
only restores exact DETR adapter attribution and does not alter their owned
presentation/lifecycle contracts.
