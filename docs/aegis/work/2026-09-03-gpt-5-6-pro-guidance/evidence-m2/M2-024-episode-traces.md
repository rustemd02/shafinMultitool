# M2-024 — coaching episode traces

Date: 2026-09-04
Owner: VerificationOwner
Branch: `codex/set-os-camera-b1`
Commit: local M2-024 commit; final SHA is recorded in the handoff report

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
`AdviceStabilizer`. It publishes one same-frame handoff through
`currentCoachingEpisodeObservation`; `CameraViewModel` consumes it, owns the
coordinator, cancels it on route/lens/background teardown, and exposes only
`coachingEpisodeState` to presentation. A terminal episode cannot be reopened
by a late publisher; a new capture must explicitly call `resetForRetry`.

Vision-person and DETR-object bindings are source-isolated. A selected source,
track identity, binding region, frame region, capture generation, orientation,
and lens are checked together; source mixing or geometry mismatch fails closed.
The lens-switch boundary cancels before its asynchronous switch begins.

The technical stabilization action is the only safety family admitted while
the camera is moving. Its bounded technical-quality issue is converted into a
typed stability baseline; AdviceStabilizer hysteresis is preserved across
continued moving frames, while stable-after frames remain strict. No ordinary
composition/subject action is admitted during camera motion.

The current branch intentionally stops at the `readyForVerification` handoff.
M2-025 owns the action-specific four-way verifier and must supply its own
verification owner; no verifier or marker UI is added here.

## Focused verification

Command (allowed non-Pro simulator; no physical device or CUA):

```text
xcodebuild -workspace shafinMultitool.xcworkspace \
  -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  -derivedDataPath /tmp/setos-camera-b1-derived-10 \
  -resultBundlePath /tmp/setos-camera-b1-tests-10.xcresult \
  -only-testing:shafinMultitoolTests/CoachingEpisodeCoordinatorTests \
  -only-testing:shafinMultitoolTests/AdviceStabilizerTests \
  -only-testing:shafinMultitoolTests/SubjectTrackLifecycleTests \
  -only-testing:shafinMultitoolTests/UserMovementObserverTests test
```

Result: `TEST SUCCEEDED`, 54/54 tests passed, 0 failures, on `iPhone 17e`
iOS Simulator 26.5. The prohibited `iPhone 17 Pro` was not used or targeted.
Durable result bundle: `/tmp/setos-camera-b1-tests-10.xcresult`.

A preceding `-9` run on the same allowed iPhone 17e built and launched, but
reported 53/54 because the uncertain-case test fixture force-unwrapped an
observation that production correctly rejects (an unstable ordinary action).
That was a test-fixture defect, not a production-code failure; the fixture now
uses valid low-confidence evidence and the corrected `-10` run is clean. A
separate `-8` run was stopped after simulator launch stalled with repeated
`DVTDeviceOperation: Encountered a build number ""` messages. A fresh boot of
the allowed iPhone 17e and one retry completed successfully; that launch stall
is recorded as simulator infrastructure, not a product failure. The corrected
`-10` run also compiled the production target.

`git diff --check`: passed.

Automated proof covers coordinator transitions, frame-only progress, stale and
uncertain evidence, invalidations, ordering, retry tokens, subject geometry,
Vision/DETR source isolation, moving stability admission, AdviceStabilizer,
SubjectTrackLifecycle, and UserMovementObserver. Code inspection covers the
live pipeline call site, lens-switch cancellation, and teardown integration;
there is no hardware-camera or physical-device proof in this package.

## Known boundary

The actual device path still requires M2-025/M2-026 for four-way verification,
calibration of technical confidence, and physical-camera validation. This
package proves deterministic episode ownership and fail-closed transitions,
not model quality, ARKit behavior, or hardware timing.
