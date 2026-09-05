# M2-027/M2-028/M2-029/M2-032 — camera presentation owner

Date: 2026-09-05
Owner: CameraPresentationOwner
Branch: `codex/set-os-m2-027-029-032`

## Scope delivered

The existing `CameraOverlayUXPresentation` remains the single presentation
projection. It consumes the typed camera lifecycle, planner decision, coaching
episode, verifier result, pause and lens states, effective runtime performance
snapshot and bounded analysis health. Production branches in
`SETCameraCoachProductionView` now render this projection; the specialized
pause owner remains unchanged. No raw confidence, debug, trace or free-form
model text reaches the UI.

The correction also closes the two production handoffs that were previously
only seams: directional planner output now carries the accepted M2-004
subject-destination target, and a terminal live neural-analysis failure is
published once through the generation/lifecycle-fenced runtime signal after
stale presentation state is cleared.

## State matrix

| Source / entry | Presentation state | Primary action and recovery | Exit |
|---|---|---|---|
| camera starting/idle | `starting` / `S01` | preparing copy; no stale advice; start/retry | existing close or live start |
| stopping or session interruption | `interrupted` / `S02` | interruption copy; retry/resume where allowed | existing close or resumed lifecycle |
| camera/runtime or terminal analysis failure | `failed` / `S03` | catalog failure copy; retry through existing lifecycle owner | existing close or fresh start |
| planner WAIT/ABSTAIN/SELECT with no usable hint | `liveSeeking` / `S04` | seeking copy; wait for a new owner event | verified episode or fallback |
| verified corrective episode | `stableTip` / `S06` or `explanation` / `S07` | one catalog physical action; optional Why expansion | next episode, keep, failure or close |
| verified KEEP / leave-as-is | `keepAsIs` / `S10c` | keep copy; no corrective marker | next episode, failure or close |
| cancelled/expired/incomparable evidence | existing fallback projection / `S04` | safe fallback; no marker; wait for new evidence | new valid episode or close |
| lens switching/failure | `lensSwitching` / `L01` | lens status and truthful collapsed control remain subordinate | completed lens transition or close |
| pause loading/success/empty/failure/resuming | `P01`–`P05` | specialized pause owner controls loading, result and resume | existing pause exit/resume |
| effective governor/scheduler ECO or limited analysis | additive ECO/limited projection | compact localized ECO label; clear stale advice and markers | fresh owner event or close |

## Production target handoff, marker and occlusion

`RecommendationPlanner` no longer uses a directional issue's affected subject
region as its action target. For subject-displacement actions it maps the
accepted `snapshot.subjectSignals.primaryCandidateRegion` through the existing
M2-004 semantic displacement and subject-destination helpers. The same
production-shaped target is carried into the live annotation and frozen in
`StabilizedAdvice.targetPoint`/the coaching episode. Missing subject geometry,
invalid rectangles or an intersection fail closed to seeking/fallback without
a marker.

The runtime preview maps normalized frozen subject and target regions through
the canonical aspect-fill/orientation transform. Corrective geometry consumes
the mapped subject as origin and the mapped M2-004 action target as endpoint;
it clips to the camera-safe rect and remains upright for portrait, landscape,
crop and mirroring. The pure `SETCorrectiveArrowGeometry` primitive remains
the geometry owner.

Marker identity is the `CoachingEpisodeToken`/domain event UUID exposed by
`CameraOverlayUXPresentation.eventID`, not reusable `LiveHintPresentation.id`.
The projection uses the episode baseline's subject/action to freeze target
geometry, so re-rendering or rotating the same episode cannot replay the
existing `SETMotionEventLedger` 320 ms one-shot draw, while a same-action new
episode token reveals a new marker. No token, evidence gate, valid target or
safe geometry means no marker. Reduce Motion keeps the final geometry
immediately and uses the existing 120 ms fade.

`CameraOcclusionSolver` remains a thin deterministic wrapper over
`SETSubjectSafeControlPlacement.resolve`: it protects the subject, target,
reserved header/lens frames and safe rect, chooses a readable safe-edge anchor
when possible, and falls back to one compact edge band bounded to 360×96
points. Advice and lens controls stay visually subordinate to the camera
preview; there is no central/full-width card.

## Runtime thermal and terminal-analysis path

`ThermalGovernor.nextBudget()` publishes the effective tier/budget to the
process-local `CameraRuntimePerformanceStore`, and `RealtimeScheduler`
republishes the effective dispatched budget. These are runtime signals, not
fixture timers. Effective ECO is rendered additively as localized
`SETCopyKey.cameraEco` in the visible command/status band and accessibility
output. ECO/limited transitions clear live hint, marker annotations, planner
and verifier state; returning to nominal does not resurrect old advice.

The canonical live path is now fenced at the terminal
`NeuralEvidenceInferenceService` outcome: when
`runNeuralEvidenceInference` receives `.failed` for an active generation,
`AnalysisPipeline.publishAnalysisRuntimeFailureIfNeeded` accepts it once,
clears current suggestion/live hint/annotations/fusion trace/live TTL and
episode observation, then calls
`CameraAnalysisRuntimeSignal.publishFailure(failure:generation:)`. The
`CameraViewModel` subscriber accepts only the active starting/running
generation, maps the typed failure to the failed presentation state and clears
its live hint, annotations, planner and verifier. Stale generations and
duplicate terminal notifications are ignored. The failure path does not copy a
raw error into the UI.

The deterministic UI noisy-frame signal is DEBUG-only: the fixture launch
argument `-SHAFIN_CAMERA_RUNTIME_SIGNAL noisy-frame` selects the existing
bundled camera frame and deterministic subject/target geometry. It is used
only to exercise production surface placement and is not Release fake camera
or ECO/error data.

## Focused verification

All runs used the ordinary `iPhone 17e` iOS 26.5 simulator
(`1F680A42-CEB3-43E8-9CED-52F874962A62`), serially, with signing disabled and
task-specific derived data. No physical device, iPhone 17 Pro, global
simulator shutdown or erase was used.

Unit command:

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -collect-test-diagnostics never \
  -only-testing:shafinMultitoolTests/CameraOverlayUXPresentationTests \
  -only-testing:shafinMultitoolTests/ThermalGovernorTests \
  -only-testing:shafinMultitoolTests/RealtimeSchedulerTests \
  -only-testing:shafinMultitoolTests/CameraViewModelLifecycleTests \
  -derivedDataPath /private/tmp/setos-m2-027-029-032-correction-dd-final \
  -resultBundlePath /private/tmp/setos-m2-027-029-032-correction-unit-final.xcresult \
  CODE_SIGNING_ALLOWED=NO
```

Result: `** TEST SUCCEEDED **`; 50/50 passed, 0 failed, 0 skipped:
21 `CameraOverlayUXPresentationTests`, 14
`CameraViewModelLifecycleTests`, 8 `RealtimeSchedulerTests`, and 7
`ThermalGovernorTests`. The optional `CameraMarkerGeometryTests` and
`CameraOcclusionSolverTests` files do not exist; their production-shaped
planner, frozen episode identity/target, safe geometry and deterministic
occlusion assertions live in the existing owned
`CameraOverlayUXPresentationTests` suite, so no selector was fabricated.

UI command:

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -collect-test-diagnostics never \
  -only-testing:shafinMultitoolUITests/CameraCoachProductionUITests \
  -derivedDataPath /private/tmp/setos-m2-027-029-032-correction-ui-dd-final \
  -resultBundlePath /private/tmp/setos-m2-027-029-032-correction-ui-final.xcresult \
  CODE_SIGNING_ALLOWED=NO
```

Result: `** TEST SUCCEEDED **`; 9/9 passed, 0 failed, 0 skipped. The exported
attachment manifest is
`/private/tmp/setos-m2-027-029-032-correction-ui-final-attachments-v2/manifest.json`
and contains 21 PNG attachments. It includes corrective RU portrait,
corrective EN landscape, failure/start/fallback/keep/seeking live matrix,
pause and lens states, runtime ECO surface, Reduce Motion and Dynamic Type,
plus the new deterministic noisy-frame production-surface captures:

```text
v26-package2-camera-noisy-frame-portrait_0_BAFA4134-BF79-4041-BF1D-99ECCB255FE2.png
v26-package2-camera-noisy-frame-landscape_0_CECD21DE-31A8-4EDA-BE16-912CFEF44699.png
```

The noisy-frame test launches the DEBUG-only runtime signal in both portrait
and landscape and asserts the stable production identifiers while the compact
safe-edge command/marker remain visible. Failure stale-clearing is asserted by
`CameraViewModelLifecycleTests`; no fabricated Release failure/ECO data was
added. The `camera.eco` UI attachment is the existing production-surface ECO
fixture boundary; effective ECO truth remains the runtime governor/scheduler
store and is covered by the focused unit suites.

Final audits completed before correction commit: `git diff --check`; changed
production additions contain no `.blur(`, `.shadow(`, `Material`,
`LinearGradient` or `RadialGradient`; and the changed-path subset contains
only the two minimal canonical upstream files, the owned presentation/view
model/UI files, their tests, and this evidence file. No routes, Library files,
String Catalog, project file, or excluded M2-030/M2-031/M2-036/M11 owner was
touched.

## Pending integration evidence

The root coordinator owns the final post-integration marker-motion video and
the M11 motion ledger evidence. This correction does not claim device-only
evidence or move the M2-036 failure/ECO screenshot boundary.
