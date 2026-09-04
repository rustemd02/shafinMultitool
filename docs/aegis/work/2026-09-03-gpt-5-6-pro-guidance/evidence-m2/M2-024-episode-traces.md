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
`coachingEpisodeState` to presentation. A terminal episode cannot be reopened
by a late frame; only a fresh baseline event resets it and issues a new token.

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
`/tmp/setos-camera-b1-fix-6-20260904c.xcresult`. The final run above compiled
the production target and passed all 73 focused tests. Earlier simulator launch
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

## Known boundary

The actual device path still requires M2-025/M2-026 for four-way verification,
calibration of technical confidence, and physical-camera validation. This
package proves deterministic episode ownership and fail-closed transitions,
not model quality, ARKit behavior, or hardware timing.
