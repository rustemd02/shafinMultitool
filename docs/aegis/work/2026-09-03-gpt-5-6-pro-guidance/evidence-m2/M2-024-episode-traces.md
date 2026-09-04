# M2-024 — coaching episode traces

Date: 2026-09-04
Owner: VerificationOwner
Branch: `codex/set-os-camera-b1`
Commit: local correction commit; final SHA is recorded in the handoff report

## Scope

M2-024 adds one production-owned `CoachingEpisodeCoordinator`. It freezes one
same-frame baseline (`StabilizedAdvice`, `SubjectTrackIdentity`, orientation,
lens ID, and capture generation), then consumes only typed
`UserMovementFrame` evidence. Progress is frame-based:

```text
idle → awaitingMovement → collectingStableAfterFrames → readyForVerification
                         ↘ cancelled / expired
```

The coordinator does not implement M2-025 verification. A terminal
`readyForVerification` state is the handoff boundary for that next owner.

## Deterministic traces

| Trace | Input sequence | Expected terminal state |
|---|---|---|
| `EP-01` relevant movement | baseline `f0` → relevant `f1` → relevant `f2` → stable/no-op `f3` → stable/no-op `f4` | `readyForVerification`; baseline remains `f0` |
| `EP-02` no-op | baseline → four same-region frames | `awaitingMovement`; no movement streak |
| `EP-03` opposite | baseline → two opposite-direction frames | `awaitingMovement`; no movement streak |
| `EP-04` uncertain | baseline → low-confidence feature frame → fresh frame | never ready |
| `EP-05` stale | baseline → stale feature frame → fresh frame | never ready from stale evidence |
| `EP-06` time-only | baseline → explicit expiry at the duration boundary | `expired`; never ready |
| `EP-07` lifecycle | baseline → generation/lens/orientation/route/background/scene change | `cancelled` with the matching reason |
| `EP-08` identity/action | baseline → changed subject identity or stabilized action | `cancelled` |
| `EP-09` ordering | baseline → `f1` → duplicate `f1` → older `f0` | duplicate does not advance; older frame cancels |
| `EP-10` retry | expired baseline → `resetForRetry` → new baseline | fresh token and fresh baseline are required |

Every fixture carries a typed subject binding, source availability,
confidence, calibration marker, measured-at timestamp, capture generation, and
orientation. No fixture advances on wall-clock passage alone.

## Production ownership and provenance

`AnalysisPipeline` now constructs the immutable observation on the real live
path after recommendation planning, the safety gate, bounded planning, and
`AdviceStabilizer`. It publishes a typed stream through
`currentCoachingEpisodeEvent`: one `.baseline` freezes the advice, subsequent
`.frame` events carry fresh same-frame provenance (including a nil current
action when the recommendation disappears), and `.cancel` is an explicit
terminal boundary. `CameraViewModel` consumes this stream, owns the
coordinator, cancels it on route/lens/background teardown, and exposes only
`coachingEpisodeState` to presentation. The pipeline owner is cancelled before
the ViewModel projection at a lens boundary, so a no-op result cannot leave a
second live stream behind. A terminal episode cannot be reopened by a late
frame; only a fresh baseline event resets it and issues a new token. During an
active ordinary episode, camera motion hides the presentation and forbids a
new ordinary baseline, but does not discard the frozen transaction; the next
valid still frames can complete its movement and stable-after evidence.

Vision-person and DETR-object bindings are source-isolated. A selected source,
track identity, binding region, frame region, capture generation, orientation,
and lens are checked together; source mixing or geometry mismatch fails closed.
The lens-switch boundary cancels before its asynchronous switch begins.

The technical stabilization action is the only safety family admitted while
the camera is moving. Its bounded technical-quality issue is converted into a
typed stability baseline; AdviceStabilizer hysteresis is preserved across
continued moving frames, while stable-after frames remain strict. No ordinary
composition/subject action is admitted during camera motion. Same-semantic
actions refresh the current frame provenance rather than replaying an old
`frameID`; frozen baseline advice is never rewritten.

The package has no existing deterministic material scene-signature producer.
The live lifecycle context therefore intentionally carries `sceneSignature:
nil`, and this correction makes no live scene-cut claim. Scene-cut
invalidation is covered only at the typed `SubjectTrackLifecycleGuard`
contract seam; connecting a real scene signal is a later, separately scoped
change.

The current branch intentionally stops at the `readyForVerification` handoff.
M2-025 owns the action-specific four-way verifier and must supply its own
verification owner; no verifier or marker UI is added here.

## Focused verification

Command (allowed non-Pro simulator; no physical device or CUA):

```text
xcodebuild -workspace shafinMultitool.xcworkspace \
  -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  -derivedDataPath /tmp/setos-camera-b1-final-derived-20260904d \
  -resultBundlePath /tmp/setos-camera-b1-final-20260904d.xcresult \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -only-testing:shafinMultitoolTests/CoachingEpisodeCoordinatorTests \
  -only-testing:shafinMultitoolTests/AdviceStabilizerTests \
  -only-testing:shafinMultitoolTests/SubjectTrackLifecycleTests \
  -only-testing:shafinMultitoolTests/UserMovementObserverTests \
  -only-testing:shafinMultitoolTests/CameraAdviceSafetyGateTests test
```

Result: `TEST SUCCEEDED`, 73/73 tests passed, 0 failures, 0 skipped, on
`iPhone 17e` iOS Simulator 26.5. The prohibited `iPhone 17 Pro` was not used
or targeted. Durable result bundle:
`/tmp/setos-camera-b1-final-20260904d.xcresult`.

### Correction2 verification

Correction2 added the production pipeline-to-ViewModel stream regression and
closed the asynchronous lens boundary. The rollback-failure test initially
reproduced a fail-closed presentation mismatch: a result with no
manager-confirmed active lens left the old ViewModel lens inventory visible.
The production fix restores the established contract by presenting the neutral
wide label with an empty inventory when no active lens is known. The focused
rerun passed 1/1 on the allowed `iPhone 17e`:

```text
xcodebuild -workspace shafinMultitool.xcworkspace \
  -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  -derivedDataPath /tmp/setos-camera-b1-correction2-rollbackfix-derived-20260904a \
  -resultBundlePath /tmp/setos-camera-b1-correction2-rollbackfix-20260904a.xcresult \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -only-testing:shafinMultitoolTests/CameraViewModelLensSwitchTests/testRollbackFailureClearsPresentationAndSynchronizesManagerLifecycle test
```

Result: `TEST SUCCEEDED`, 1/1 passed, 0 failures, 0 skipped, on `iPhone 17e`
iOS Simulator 26.5. Durable result bundle:
`/tmp/setos-camera-b1-correction2-rollbackfix-20260904a.xcresult`.

The production-path and full M2-024 focused rerun passed 82/82 on the same
allowed simulator:

```text
xcodebuild -workspace shafinMultitool.xcworkspace \
  -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  -derivedDataPath /tmp/setos-camera-b1-correction2-final-derived-20260904b \
  -resultBundlePath /tmp/setos-camera-b1-correction2-final-20260904b.xcresult \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -only-testing:shafinMultitoolTests/CoachingEpisodeCoordinatorTests \
  -only-testing:shafinMultitoolTests/AdviceStabilizerTests \
  -only-testing:shafinMultitoolTests/SubjectTrackLifecycleTests \
  -only-testing:shafinMultitoolTests/UserMovementObserverTests \
  -only-testing:shafinMultitoolTests/CameraAdviceSafetyGateTests \
  -only-testing:shafinMultitoolTests/CameraViewModelLensSwitchTests test
```

Result: `TEST SUCCEEDED`, 82/82 passed, 0 failures, 0 skipped, on `iPhone 17e`
iOS Simulator 26.5. Durable result bundle:
`/tmp/setos-camera-b1-correction2-final-20260904b.xcresult`.
The two new integration tests prove recommendation disappearance followed by
movement and stable-after frames reaches `readyForVerification`, and that a
no-op lens request cancels both owners before a fresh baseline receives a new
token. A temporary diagnostic rerun was stopped after the simulator's
`simctl diagnose` stalled; it is not counted as product evidence. No iPhone 17
Pro or physical device was used.

### Correction3 verification

Correction3 closes the production terminal-boundary gap. When a coordinator
terminal is caused by retryable evidence (`actionChanged`, `subjectChanged`,
`staleEvidence`, `outOfOrder`, `invalidObservation`, or `expired`),
`CameraViewModel` clears the pipeline-owned action, lifecycle, source, and
stabilizer state exactly once without emitting a recursive cancellation event.
Capture and route boundaries (`lensChange`, `routeExit`, `background`,
orientation/generation changes, and `sceneCut`) remain explicit lifecycle
owners. The typed baseline publisher also refuses to overwrite an active
pipeline owner, so the production regression fails unless a fresh baseline is
actually admitted after the terminal reset.

The two production-path regressions passed 2/2 on the allowed `iPhone 17e`
iOS Simulator 26.5, with no manual `resetForRetry`:

```text
xcodebuild -workspace shafinMultitool.xcworkspace \
  -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  -derivedDataPath /tmp/setos-camera-b1-correction3-seam-derived-20260904a \
  -resultBundlePath /tmp/setos-camera-b1-correction3-seam-20260904a.xcresult \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -only-testing:shafinMultitoolTests/CameraViewModelLensSwitchTests/testProductionTerminalCancellationResetsPipelineBeforeFreshBaseline \
  -only-testing:shafinMultitoolTests/CameraViewModelLensSwitchTests/testProductionExpiryResetsPipelineBeforeFreshBaseline test
```

Result: `TEST SUCCEEDED`, 2/2 passed, 0 failures, 0 skipped. Durable result
bundle: `/tmp/setos-camera-b1-correction3-seam-20260904a.xcresult`.

The complete M2-024 focused suite (including the rollback/lens tests and both
new terminal-boundary regressions) then passed 84/84, 0 failures, 0 skipped on
the same `iPhone 17e` iOS Simulator 26.5. Durable result bundle:
`/tmp/setos-camera-b1-correction3-final-20260904a.xcresult`.

A preceding `-9` run on the same allowed iPhone 17e built and launched, but
reported 53/54 because the uncertain-case test fixture force-unwrapped an
observation that production correctly rejects (an unstable ordinary action).
That was a test-fixture defect, not a production-code failure. The prior
M2-024 `-10` result (54/54) remains historical baseline evidence only and is
insufficient for this fix-first correction. During this correction, the first
run (`fix-1`) stopped at a test compile error from an optional fixture value;
the duplicate/out-of-order spot check then exposed a test timestamp outside
the declared Vision freshness window and was corrected to exercise ordering
after a valid first frame. The focused spot check passed 1/1 in
`/tmp/setos-camera-b1-fix-6-20260904c.xcresult`. The first correction run above
compiled the production target and passed all 73 focused tests; correction3's
84/84 result is recorded above. Earlier simulator launch
stall output with repeated `DVTDeviceOperation: Encountered a build number
""` messages is recorded as infrastructure, not product proof.

`git diff --check`: passed.

Automated proof covers coordinator transitions, frame-only progress,
recommendation disappearance, competing action cancellation, retry tokens,
same-semantic-action frame provenance refresh, stale and uncertain evidence,
invalidations, ordering, subject geometry, Vision/DETR source isolation,
frame-global horizon/stability without a subject, moving stability admission,
AdviceStabilizer, CameraAdviceSafetyGate, SubjectTrackLifecycle, and
UserMovementObserver. Code inspection covers the live pipeline call site,
lens-switch cancellation, technical-signal reuse (no second full-resolution
exposure traversal in the episode handoff), and teardown integration; there is
no hardware-camera or physical-device proof in this package.

### Correction4 verification

Correction4 closes the terminal-publication ordering gap. Every live episode
boundary now resets the pipeline-owned stabilizer, subject tracker, lifecycle
context, source provenance, and action metadata before publishing the queued
typed cancellation event. The ViewModel's retry reset remains idempotent for a
coordinator-owned terminal, but no longer relies on `liveEpisodeActionID` alone
to decide whether stale lifecycle state exists. A baseline publication also
records lifecycle provenance at the typed owner boundary and refuses to
overwrite an uncleared lifecycle owner. The live handoff defers lifecycle
ownership until a baseline is actually admitted, so pre-baseline Vision/DETR
resolution cannot block the first valid episode.

The new production-path regression starts with an old subject baseline, invokes
the pipeline's subject-resolution invalidation method (which calls the same
production `clearLiveCoachingEpisodeObservation` path rather than injecting a
typed cancel), waits for the queued `.subjectChanged` terminal, and then
publishes a fresh resolved baseline. The fresh baseline is accepted with a new
token only when the pipeline reset occurred before event delivery; this
specifically guards against the old identity surviving behind a cleared action
ID.

The seam regression passed 1/1 on the allowed `iPhone 17e` iOS Simulator 26.5:

```text
xcodebuild -workspace shafinMultitool.xcworkspace \
  -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  -derivedDataPath /tmp/setos-camera-b1-correction4-seam-derived-20260904e \
  -resultBundlePath /tmp/setos-camera-b1-correction4-seam-20260904e.xcresult \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -only-testing:shafinMultitoolTests/CameraViewModelLensSwitchTests/testProductionSubjectChangeResetsOwnerBeforeFreshResolutionBaseline test
```

Result: `TEST SUCCEEDED`, 1/1 passed, 0 failures, 0 skipped. Durable result
bundle: `/tmp/setos-camera-b1-correction4-seam-20260904e.xcresult`.

The complete M2-024 focused suite then passed 85/85, 0 failures, 0 skipped on
the same allowed simulator:

```text
xcodebuild -workspace shafinMultitool.xcworkspace \
  -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  -derivedDataPath /tmp/setos-camera-b1-correction4-final-derived-20260904e \
  -resultBundlePath /tmp/setos-camera-b1-correction4-final-20260904e.xcresult \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -only-testing:shafinMultitoolTests/CoachingEpisodeCoordinatorTests \
  -only-testing:shafinMultitoolTests/AdviceStabilizerTests \
  -only-testing:shafinMultitoolTests/SubjectTrackLifecycleTests \
  -only-testing:shafinMultitoolTests/UserMovementObserverTests \
  -only-testing:shafinMultitoolTests/CameraAdviceSafetyGateTests \
  -only-testing:shafinMultitoolTests/CameraViewModelLensSwitchTests test
```

Result: `TEST SUCCEEDED`, 85/85 passed, 0 failures, 0 skipped. Durable result
bundle: `/tmp/setos-camera-b1-correction4-final-20260904e.xcresult`. The run
used only `iPhone 17e`; no iPhone 17 Pro, physical device, or CUA was used.
`git diff --check`: passed. The simulator emitted the existing CoreMotion and
FigCaptureSourceSimulator diagnostics during launch; they did not affect the
85/85 deterministic result and are not hardware-camera proof.

## Known boundary

The actual device path still requires M2-025/M2-026 for four-way verification,
calibration of technical confidence, and physical-camera validation. This
package proves deterministic episode ownership and fail-closed transitions,
not model quality, ARKit behavior, or hardware timing.
