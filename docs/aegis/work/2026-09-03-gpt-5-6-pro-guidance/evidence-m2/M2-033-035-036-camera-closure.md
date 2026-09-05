# M2-033 / M2-035 / M2-036 — Camera Coach closure

- Date: 2026-09-05
- Owner: Camera Coach closure lane
- Branch: `codex/set-os-m2-033-035-036`
- Base: `ed861ba`
- Device used for verification: iPhone 17e, iOS 26.5,
  `1F680A42-CEB3-43E8-9CED-52F874962A62`
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
   through the production presentation owner to `CameraViewModel`.
4. `NeuralEvidenceInferenceService` runs through its typed provider seam and
   stores the resulting frame evidence in the production evidence store.
5. `UserMovementObserver` classifies relevant, no-op and opposite movement.
6. `ActionVerifier` returns the four-way comparable outcomes (improved,
   unchanged, worse) and fixed stability; protected select-subject, wait and
   abstain inputs remain fail-closed.

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
the UI suite proves the app-process root, stable IDs and orientation-safe
surface reachability.

Fixture argument construction and the fixture root remain inside `#if DEBUG`.
The Release `SceneDelegate` overload accepts only the normal commercial root,
so Release has no public fixture switch or deterministic state injection.

## Changed files

- `shafinMultitool/Multitool2Module/UI/Overlay/OverlayView.swift` — remove the
  root environment-dismiss callback.
- `shafinMultitool/Multitool2Module/UI/Overlay/SETCameraCoachProductionView.swift`
  — make the optional close destination explicit and omit the root xmark.
- `shafinMultitoolTests/CameraCoachClosedLoopTests.swift` — production-owner
  closed-loop, neural evidence, movement, verification and fail-closed tests.
- `shafinMultitoolUITests/CameraCoachEntryFlowUITests.swift` — root close
  control contract assertion.
- `shafinMultitoolUITests/CameraCoachProductionUITests.swift` — root-control
  assertion and portrait/landscape decision/recovery fixture matrix.
- `docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-m2/M2-033-035-036-camera-closure.md`
  — this evidence record.

No routes, `EXECUTION_STATE.md`, shared catalogs, project files, datasets,
History/Debug/Benchmark code, thesis/litreview files, or unrelated worktree
changes were touched.

## Focused verification

All commands were serial, used the allowed iPhone 17e simulator, disabled
code signing, and used `-collect-test-diagnostics never`.

### M2-035 owner-chain unit suite

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests \
  -derivedDataPath /private/tmp/setos-m2-033-035-036-unit-dd \
  -resultBundlePath /private/tmp/setos-m2-033-035-036-unit-owners3.xcresult \
  CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never
```

Result: `** TEST SUCCEEDED **`; 3/3 tests passed, 0 failed, 0 skipped.
The suite covered the production owner handoff, protected safety decisions,
neural evidence execution, movement observation and ActionVerifier outcomes.

### M2-036 production Camera UI matrix

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:shafinMultitoolUITests/CameraCoachProductionUITests \
  -derivedDataPath /private/tmp/setos-m2-033-035-036-unit-dd \
  -resultBundlePath /private/tmp/setos-m2-033-035-036-camera-ui3.xcresult \
  CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never
```

Result: `** TEST SUCCEEDED **`; 10/10 tests passed, 0 failed, 0 skipped,
including the new 10-fixture portrait/landscape matrix. The result bundle
contains the production-surface screenshots attached by the UI test.

### M2-033 entry/root contract

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:shafinMultitoolUITests/CameraCoachEntryFlowUITests \
  -derivedDataPath /private/tmp/setos-m2-033-035-036-unit-dd \
  -resultBundlePath /private/tmp/setos-m2-033-035-036-camera-entry-ui.xcresult \
  CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never
```

Result: `** TEST SUCCEEDED **`; 9/9 tests passed, 0 failed, 0 skipped.

The first UI retry was an infrastructure failure before test execution:
SpringBoard returned `FBSOpenApplicationServiceErrorDomain / RequestDenied`
and the process was terminated with no executed tests. Its partial result and
log were deleted; it is not counted as a product test failure.

## Contract and visual audit

- `git diff --check`: passed.
- No changed production code introduces material/blur/shadow/gradient or a
  second visual system; existing SET tokens and production presentation owners
  remain authoritative.
- Existing `camera_coach_pause`, `camera_coach_live_surface` and any real
  `camera_coach_close` IDs are preserved; only the non-functional root close is
  absent.
- The camera per-frame surface remains a deterministic presentation layer; no
  decorative invalidation or layout churn was added.
- Fixture selection is DEBUG-only and is not a Release runtime backdoor.
- Retained result bundles are the three paths listed above. Completed derived
  data/log scratch files can be removed after integration without losing the
  result bundles.

## Remaining boundary

Simulator and unit evidence cannot prove physical-device ARKit tracking,
camera/microphone permission hardware, Photos authorization, actual video
recording/playback, A/V sync, thermal behavior or hardware timing. Those remain
the explicit device-verification boundary and require an owner-supplied test
device; this batch does not claim them.

## Pending integration

The parent coordinator must inspect this batch diff, integrate the local commit,
and retain the result bundles for the M2 gate. No M2-GATE claim is made here.
