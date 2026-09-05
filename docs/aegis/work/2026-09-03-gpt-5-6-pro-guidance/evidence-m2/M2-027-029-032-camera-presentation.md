# M2-027/M2-028/M2-029/M2-032 — camera presentation owner

Date: 2026-09-05
Owner: CameraPresentationOwner
Branch: `codex/set-os-m2-027-029-032`

## Scope delivered

The existing `CameraOverlayUXPresentation` projection now consumes the typed
camera lifecycle, planner decision, coaching episode, verifier result, pause
and lens presentation states, plus the effective runtime performance snapshot
and a bounded analysis-health value. Lifecycle, pause, lens, cancellation,
verification and planner boundaries are mapped before live copy. Invalid or
incomplete payloads retain the existing single safe fallback and never expose
raw confidence, debug, trace or free-form model text.

`CameraViewModel` owns the handoff from the existing pipeline publishers. A
new episode clears stale verification/advice; WAIT/ABSTAIN/SELECT and
incomparable verification clear the live projection. `reportAnalysisFailure`
is a fail-closed owner seam that clears the live hint, annotations and
pipeline presentation state before publishing failed analysis to the
projection.

## State matrix

| Source boundary | Presentation state | Primary/recovery behavior | Exit |
|---|---|---|---|
| camera starting/idle | `starting` / `S01` | preparing copy; no stale advice | existing close |
| stopping or session interruption | `interrupted` / `S02` | interrupted copy; resume where applicable | existing close |
| camera/runtime or analysis failure | `failed` / `S03` | catalog failure copy and retry | existing close |
| planner WAIT/ABSTAIN/SELECT, no hint | `liveSeeking` / `S04` | seeking copy; wait for a new owner event | existing close |
| verified corrective episode | `stableTip` / `S06` or `explanation` / `S07` | one catalog physical action; optional Why expansion | existing close |
| verified KEEP / leave-as-is | `keepAsIs` / `S10c` | keep copy; no corrective marker | existing close |
| cancelled/expired or incomparable evidence | existing fallback projection (`S04`, `isFallback`) | safe fallback copy; no marker | existing close |
| lens switching/failure | `lensSwitching` / `L01` | lens status remains subordinate | existing close |
| pause loading/success/empty/failure/resuming | `P01`–`P05` | existing pause owner controls/resume | existing close |
| effective governor/scheduler ECO | additive `showsECO`/limited projection | compact ECO label; stale advice cleared | existing close |

## Marker and occlusion

The runtime preview already maps normalized subject and target regions through
`AVCaptureVideoPreviewLayer` aspect-fill/orientation transforms. The corrective
leader now consumes the mapped accepted subject region as its origin and the
mapped action target as its endpoint, using the existing pure
`SETCorrectiveArrowGeometry` primitive. Invalid, missing, overlapping or
out-of-safe-rect geometry yields no marker. The event ID is the same
`LiveHintPresentation.id` carried by `CameraOverlayUXPresentation.eventID` and
passed to the existing `SETMotionEventLedger` one-shot draw guide. Reduce
Motion still uses the existing immediate final geometry plus fade behavior.

`CameraOcclusionSolver` is a thin wrapper around the existing
`SETSubjectSafeControlPlacement.resolve` owner. It protects subject, target,
reserved header/lens frames and the safe rect, and only adds a deterministic
four-corner compact fallback bounded to 360×96 points. The preview remains the
hero and the command band is never a central/full-width card.

## Runtime thermal/error path

`ThermalGovernor.nextBudget()` publishes its effective tier and budget to the
process-local `CameraRuntimePerformanceStore`; `RealtimeScheduler` republishes
the effective budget it dispatches. Publications are deduplicated, and the
view model observes the store on the main queue. Heavy-model disablement is
the runtime ECO truth, so no fixture identifier creates ECO. ECO/limited mode
clears live hint, annotations, planner and verifier state. Returning to nominal
does not resurrect old advice; a fresh pipeline event is required.

The owned files cannot automatically subscribe the excluded
`AnalysisPipeline`/camera analyzer failure producer because that producer
publishes no typed failure signal. The bounded
`CameraAnalysisRuntimeSignal.publishFailure` and
`CameraViewModel.reportAnalysisFailure` seams are ready for that owner handoff;
no detector, timer or view heuristic was added.

## Focused verification

All runs used the ordinary `iPhone 17e` iOS 26.5 simulator
(`1F680A42-CEB3-43E8-9CED-52F874962A62`), serially, with signing disabled and
task-specific derived data. No physical device, iPhone 17 Pro, global
simulator shutdown or erase was used.

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -collect-test-diagnostics never \
  -only-testing:shafinMultitoolTests/CameraOverlayUXPresentationTests \
  -only-testing:shafinMultitoolTests/ThermalGovernorTests \
  -only-testing:shafinMultitoolTests/RealtimeSchedulerTests \
  -only-testing:shafinMultitoolTests/CameraViewModelLifecycleTests \
  -derivedDataPath /private/tmp/setos-m2-027-029-032-dd8 \
  -resultBundlePath /private/tmp/setos-m2-027-029-032-unit8.xcresult \
  CODE_SIGNING_ALLOWED=NO
```

Result: `** TEST SUCCEEDED **`; 47/47 passed, 0 failed, 0 skipped:
19 `CameraOverlayUXPresentationTests`, 13
`CameraViewModelLifecycleTests`, 8 `RealtimeSchedulerTests`, and 7
`ThermalGovernorTests`. The requested `CameraMarkerGeometryTests` and
`CameraOcclusionSolverTests` selectors were omitted because their assertions
are expressed in the existing owned `CameraOverlayUXPresentationTests` suite;
no new test target/file was needed.

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -collect-test-diagnostics never \
  -only-testing:shafinMultitoolUITests/CameraCoachProductionUITests \
  -derivedDataPath /private/tmp/setos-m2-027-029-032-dd-ui-final3 \
  -resultBundlePath /private/tmp/setos-m2-027-029-032-ui-final3.xcresult \
  CODE_SIGNING_ALLOWED=NO
```

Result: `** TEST SUCCEEDED **`; 8/8 passed, 0 failed, 0 skipped. The exported
attachment manifest is
`/private/tmp/setos-m2-027-029-032-ui-final3-attachments.VDZGUE/manifest.json` and
contains 19 PNG attachments from the existing corrective RU/EN, orientation,
lens, pause, interruption, motion, Dynamic Type and Reduce Motion fixtures.
The required noisy-frame, failure-stale-advice and injected ECO-limited
attachments remain pending because those runtime signals belong to excluded
upstream owners; the `camera.eco` fixture stays seeking unless the shared
runtime store is actually ECO.

`git diff --check` passed. The changed production additions contain no
`.blur(`, `.shadow(`, `Material`, `LinearGradient` or `RadialGradient` use.
The final commit is limited to the owned production, test and evidence paths.

## Pending integration evidence

The root coordinator still owns the final post-integration marker-motion video.
Automatic analyzer-failure publication and runtime ECO/noisy-frame UI
attachments require the excluded `AnalysisPipeline`/camera producer to call
the bounded owner seams above.
