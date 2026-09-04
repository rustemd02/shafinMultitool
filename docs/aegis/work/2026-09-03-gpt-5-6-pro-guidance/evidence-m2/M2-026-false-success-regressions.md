# M2-026 — false-success regressions

Date: 2026-09-05
Owner: VerificationOwner
Branch: `codex/set-os-m2-026`
Base: `cc245ba` (integrated M2-025)

## Scope delivered

M2-026 extends the existing immutable M2-025 `ActionVerificationInput` and
`CoachingEpisodeCoordinator.verificationInput` seam. It does not add a second
detector, verifier, gate, clock, state machine, or producer. The verifier now
fails closed before classifying a favorable metric when the pair lacks
comparable scene or framing provenance, or when automatic exposure adjustment
has not been explicitly declared stable.

`ActionVerificationGeometryContext` composes the existing
`CameraDisplayTransform` and `AspectFillTransform` values and binds them to the
exact frame ID. It performs no new coordinate math. Subject-bound pairs require
valid before/after contexts with matching display transform and aspect-fill
crop; frame-global horizon/stability pairs retain their nil-subject contract.
`ActionVerificationExposureState` is an explicit stable/adjusting predicate;
luma or exposure-bias deltas never substitute for it. Scene signatures are now
required on both lifecycle snapshots for any positive decision: two different
signatures return `sceneMismatch`, while either missing signature returns
`sceneProvenanceMissing`.

The coordinator freezes and forwards the optional geometry and exposure
evidence with the baseline and final frame. Existing test fixtures provide
these values to prove the same-context f0→f4 handoff; the live producer remains
unchanged and therefore continues to fail closed until it supplies them.

## Confounder matrix

| Confounder | Adversarial fixture | Required result | Covered by |
|---|---|---|---|
| Crop/aspect-fill changed | Same subject/action and favorable placement delta, different destination aspect-fill transform | `incomparable(.geometryMismatch)`; never improved/fixed | `ActionVerifierTests.testFramingProvenanceBlocksCropChangeAndAllowsSameContext` |
| Crop/aspect-fill unchanged | Same subject/action and matching immutable transform/crop, different frame IDs | Comparable directional outcome (`improved`) | `ActionVerifierTests.testFramingProvenanceBlocksCropChangeAndAllowsSameContext`; coordinator f0→f4 handoff |
| Framing provenance missing/invalid | Subject-bound pair with no contexts; non-finite display matrix | `incomparable(.geometryProvenanceMissing)` / `incomparable(.geometryInvalid)` | `ActionVerifierTests.testFramingProvenanceBlocksCropChangeAndAllowsSameContext`; `testInvalidFramingProvenanceFailsClosed` |
| New subject | Favorable after box is bound to a different identity or expected identity | `incomparable(.subjectIdentityMismatch)` | `ActionVerifierTests.testSubjectIdentitySourceAndCoordinateSpaceMustContinue`; coordinator subject-change cancellation |
| Lens/generation switch | Different lifecycle lens or generation/token | Typed verifier mismatch; coordinator cancels the episode | `ActionVerifierTests.testTokenGenerationOrientationLensAndCalibrationMismatchFailClosed`; `CoachingEpisodeCoordinatorTests.testInvalidatingLifecycleChangesCancelTheEpisode`; `SubjectTrackLifecycleTests` |
| Exposure adjusting | Favorable exposure fault/bias delta while before or after state is `.adjusting` | `incomparable(.exposureAdjusting)`; no fixed/improved result | `ActionVerifierTests.testExposureAdjustmentEvidenceIsRequiredForLightActions` |
| Exposure state missing | Favorable exposure fault clears without explicit states | `incomparable(.exposureEvidenceMissing)` | `ActionVerifierTests.testExposureAdjustmentEvidenceIsRequiredForLightActions` |
| Exposure stable control | Explicit `.stable` on both frames and objective fault clears | `comparable(.fixed)` | `ActionVerifierTests.testExposureAdjustmentEvidenceIsRequiredForLightActions`; `testExposureFaultAndFocusPredicatesCanReturnFixed` |
| Scene A → B | Lifecycle signatures differ | `incomparable(.sceneMismatch)` | `ActionVerifierTests.testSceneMismatchAndMissingProvenanceFailClosed` |
| Scene provenance missing | One or both lifecycle signatures absent | `incomparable(.sceneProvenanceMissing)` | `ActionVerifierTests.testSceneMismatchAndMissingProvenanceFailClosed` |
| Wrong direction / stale-at-own-frame | Existing observer trajectories and own-time stale measurement | `worse` or typed stale incomparable, never success | `ActionVerifierTests.testPlacementReturnsImprovedUnchangedAndWorse`; `testStaleAtEachFramesOwnEvaluationTimeRemainsIncomparable`; observer suite |
| Safety regression | Favorable finite delta plus confidence/camera safety regression | `incomparable(.safetyRegression)` while retaining delta | `ActionVerifierTests.testSafetyRegressionBlocksPositiveAndKeepsMeasuredDelta` |
| Nil-subject frame-global control | Horizon/stability with no subject binding | Existing comparable/fixed behavior preserved | `ActionVerifierTests.testHorizonAndStabilityUseObjectiveFixedPredicates`; coordinator and observer frame-global tests |

## Contract preservation

- `UserMovementObserver` remains the sole mapping, deadband, direction and
  own-frame freshness owner; no observer mapping or freshness window changed.
- `CoachingEpisodeCoordinator` remains the sole lifecycle owner. It still
  reaches verification only after the configured movement/stable-after streak,
  freezes the baseline, ignores late ready frames, and cancels on lifecycle
  changes.
- A safety regression can retain a finite `ActionVerificationMetricDelta` but
  can never become `improved` or `fixed`.
- Subject-bound verification still requires exact expected identity, matching
  binding source/space/generation and calibrated evidence. Horizon and
  stability do not invent a subject sentinel.
- No timer, elapsed-time score, percentage, luma heuristic, layout/UI route,
  accessibility ID, Xcode project, or protected file was changed.

## Focused verification

All tests used the allowed ordinary `iPhone 17e` iOS 26.5 simulator
(`1F680A42-CEB3-43E8-9CED-52F874962A62`). No physical device and no iPhone 17
Pro were used or targeted. Tests ran serially with a task-specific derived-data
directory and result bundle.

```text
xcodebuild -workspace shafinMultitool.xcworkspace \
  -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  -derivedDataPath /tmp/setos-m2-026-action-dd1 \
  -resultBundlePath /tmp/setos-m2-026-action-1.xcresult \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -only-testing:shafinMultitoolTests/ActionVerifierTests \
  -only-testing:shafinMultitoolTests/CoachingEpisodeCoordinatorTests \
  -only-testing:shafinMultitoolTests/UserMovementObserverTests \
  -only-testing:shafinMultitoolTests/CameraDisplayTransformTests \
  -only-testing:shafinMultitoolTests/CameraCoordinateSpaceTests \
  -only-testing:shafinMultitoolTests/SubjectTrackLifecycleTests \
  -only-testing:shafinMultitoolTests/CameraAdviceSafetyGateTests test
```

Result: `** TEST SUCCEEDED **`; 96/96 tests passed, 0 failures, 0 skipped.

Breakdown:

- `ActionVerifierTests`: 16
- `CoachingEpisodeCoordinatorTests`: 15
- `UserMovementObserverTests`: 30
- `CameraDisplayTransformTests`: 7
- `CameraCoordinateSpaceTests`: 8
- `SubjectTrackLifecycleTests`: 7
- `CameraAdviceSafetyGateTests`: 13

Result bundle: `/tmp/setos-m2-026-action-1.xcresult`

`git diff --check`: passed after the focused run.

## Honest downstream limitation

The packet intentionally does not touch the out-of-scope
`AnalysisPipeline`/camera producers. In the current live path,
`SubjectTrackLifecycleContext.sceneSignature` is still absent and accepted
frames do not carry the new geometry or exposure-settling contexts. Therefore
the verifier will return typed missing-provenance results rather than claim a
live subject/exposure success. A future producer-owned seam must populate and
freeze these values; adding a heuristic fallback here would reintroduce the
false-success bug this packet closes.

Simulator results prove deterministic contract behavior only. ARKit, camera,
microphone, thermal, hardware timing and physical A/V behavior remain outside
this packet.

## Sol/High correction

The first Sol/High review found three correction points:

1. Confounder guards returned before the observer comparison, which discarded
   useful finite diagnostics. `ActionVerifier` now asks the existing observer
   for its own-evaluation-time comparison once before applying the higher-level
   crop, scene, exposure, lifecycle and identity blockers. A complete finite
   `ActionVerificationMetricDelta` is retained on blocked results when the
   observer can establish it; it never changes an incomparable decision. The
   calibration blocker intentionally retains no invented delta when the
   observer itself rejects the pair at its calibration-provenance gate.
2. The duplicate determinant calculation was removed from
   `ActionVerificationGeometryContext.isValid`. Validation now reuses the
   canonical `CameraDisplayTransform(orientation:isMirrored:)` construction
   and the existing `AspectFillTransform(sourceSize:destinationSize:)`
   invariants; no new geometry formula was added.
3. Scene signatures are considered missing only when absent or all whitespace.
   Non-empty signatures, including surrounding whitespace, retain exact
   identity semantics and are compared byte-for-byte.

The first correction test invocation exposed one over-specific test assertion:
the calibration-mismatch fixture expected a delta even though the canonical
observer correctly fails closed before producing a numeric comparison. The
test now asserts that any retained diagnostics are finite without bypassing
that validation gate. A separate attempt hung in Xcode's automatic
`simctl diagnose` collection after the tests completed; it was not a product
failure. The final run disables only that harness diagnostics collection.

Final correction verification used the ordinary iPhone 17e simulator,
serially, with fresh task-specific paths:

```text
xcodebuild -workspace shafinMultitool.xcworkspace \
  -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  -derivedDataPath /private/tmp/setos-m2-026-correction-dd \
  -resultBundlePath /private/tmp/setos-m2-026-correction.xcresult \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -collect-test-diagnostics never \
  -only-testing:shafinMultitoolTests/ActionVerifierTests \
  -only-testing:shafinMultitoolTests/CoachingEpisodeCoordinatorTests \
  -only-testing:shafinMultitoolTests/UserMovementObserverTests \
  -only-testing:shafinMultitoolTests/CameraDisplayTransformTests \
  -only-testing:shafinMultitoolTests/CameraCoordinateSpaceTests \
  -only-testing:shafinMultitoolTests/SubjectTrackLifecycleTests \
  -only-testing:shafinMultitoolTests/CameraAdviceSafetyGateTests test
```

Result: `** TEST SUCCEEDED **`; 96/96 tests passed, 0 failures, 0 skipped.
The breakdown remained 16 ActionVerifier, 15 coordinator, 30 observer, 7
display-transform, 8 camera-coordinate-space, 7 subject-lifecycle and 13
safety-gate tests. Result bundle:
`/private/tmp/setos-m2-026-correction.xcresult`.

`git diff --check`: passed. The correction diff is limited to the original
M2-026 production/test/evidence ownership; no `EXECUTION_STATE`, tracker,
route, UI, project or protected file was changed.
