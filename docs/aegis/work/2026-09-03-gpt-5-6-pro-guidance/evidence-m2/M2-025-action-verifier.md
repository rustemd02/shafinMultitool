# M2-025 — action before/after verifier

Date: 2026-09-04
Owner: VerificationOwner
Branch: `codex/set-os-m2-025`
Base: integrated M2-024 coordinator at `c7509dd`

## Scope delivered

M2-025 adds one pure `ActionVerifier` for an immutable coordinator pair. The
coordinator is still the only lifecycle owner: `verificationInput` is `nil`
until `readyForVerification`, freezes the baseline frame and lifecycle context,
and retains the last accepted stable-after frame. A ready episode ignores late
frames until an explicit retry baseline creates a new token.

The verifier returns only the typed four-way decision (`fixed`, `improved`,
`unchanged`, or `worse`) or an explicit `incomparable(reason)`. It consumes the
existing `UserMovementObserver` action mapping, deadbands, direction and
freshness gates through a detailed comparison extraction; it does not duplicate
that switch or use elapsed time, percentages, timers, tasks, or aesthetic
targets.

The covered measurements are placement, scale, depth, horizon, exposure/light,
focus, and stability. Subject-bound families require the same identity, source,
coordinate space and generation. Horizon and stability stay frame-global.
Lifecycle, lens, orientation, calibration, scene-signature, frame ordering,
feature provenance, confidence, finiteness and safety-regression seams fail
closed. Missing focus/depth/exposure-fault producers remain incomparable rather
than being inferred from unrelated values. Safety regressions retain any finite
measured delta but block a positive decision.

Objective `fixed` predicates are intentionally narrow: level-horizon enters the
existing rotation deadband, an explicitly supplied exposure fault becomes clear,
an explicitly supplied defocus predicate clears, or the established frame-level
still predicate is true for stabilization. Directional movement alone is only
`improved`.

## Contract inventory

| Contract | Owner / guarantee |
|---|---|
| `ActionVerificationOutcome` | Four explicit outcomes; no missing-evidence fallback to unchanged |
| `ActionVerificationDecision` | `comparable(outcome:)` or typed `incomparable(reason:)` |
| `ActionVerificationMetricDelta` | Finite raw and directed deltas plus the observer-owned deadband |
| `ActionVerificationInput` | Token, action, exact before/after frames, lifecycle snapshots, optional expected subject, typed safety regressions |
| `ActionVerificationResult` | Token/action/frame IDs, decision, measurable deltas, retained safety regressions |
| `CoachingEpisodeCoordinator.verificationInput` | Non-nil only for a ready coordinator; baseline/final handoff is immutable |

## Focused verification

All commands used the workspace (CocoaPods dependencies included), serial test
execution, and the allowed non-Pro `iPhone 17e` iOS 26.5 simulator
(`1F680A42-CEB3-43E8-9CED-52F874962A62`). No physical device and no iPhone 17
Pro were used or targeted.

```text
xcodebuild -workspace shafinMultitool.xcworkspace \
  -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  -derivedDataPath /tmp/setos-m2-025-action-dd6 \
  -resultBundlePath /tmp/setos-m2-025-action-6.xcresult \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -only-testing:shafinMultitoolTests/ActionVerifierTests \
  -only-testing:shafinMultitoolTests/UserMovementObserverTests \
  -only-testing:shafinMultitoolTests/CoachingEpisodeCoordinatorTests test
```

Result: `** TEST SUCCEEDED **`; 57/57 tests passed, 0 failures, 0 skipped.
The suite is 12 `ActionVerifierTests`, 15
`CoachingEpisodeCoordinatorTests`, and 30 `UserMovementObserverTests`.
Result bundle: `/tmp/setos-m2-025-action-6.xcresult`.

The first post-compile run exposed a fixture issue, not a reason to weaken the
freshness guard: the `worse` placement case compared a baseline 0.3 seconds
old, beyond the canonical Vision 0.25-second window, so the correct result was
`incomparable(evidenceStale)`. The fixture now keeps the pair inside that
window; stale evidence remains covered and fail-closed. A previous compile
attempt also caught and corrected only test argument/optional-value mistakes.

Repository check: `git diff --check` passed after the final focused run.

## Sol `fix-first` correction

The review finding was valid at the M2-024→M2-025 seam. The original verifier
called the single-time `UserMovementObserver.compare(..., asOf: after)` API;
that API intentionally ages both samples to one observation time for live
movement classification. Reusing it for an episode pair made a valid frozen
baseline look stale when `f4` arrived more than the 0.25-second Vision window
after `f0`.

The owner-level correction adds
`UserMovementObserver.compareAtOwnEvaluationTimes(...)`. It reuses the same
action mapping, deadbands and freshness windows, but validates feature and
subject-binding measurements against `before.evaluatedAt` and
`after.evaluatedAt` independently. A measurement stale at its own frame time,
future relative to that frame, unavailable, low-confidence, uncalibrated or
non-finite still fails closed. The legacy single-`asOf` API remains available
for the M2-023 tracker/coordinator behavior.

The verifier now also requires `subjectIdentity` on every subject-bound input;
the coordinator supplies its frozen episode identity, while frame-global
horizon/stability actions continue to accept nil. New regressions cover the
real coordinator f0→f4 +0.40-second seam, stale-at-baseline-time evidence,
missing expected identity and mismatched expected identity.

Fresh correction verification:

```text
xcodebuild -workspace shafinMultitool.xcworkspace \
  -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  -derivedDataPath /tmp/setos-m2-025-correction-dd2 \
  -resultBundlePath /tmp/setos-m2-025-correction-2.xcresult \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -only-testing:shafinMultitoolTests/ActionVerifierTests \
  -only-testing:shafinMultitoolTests/UserMovementObserverTests \
  -only-testing:shafinMultitoolTests/CoachingEpisodeCoordinatorTests test
```

Result: `** TEST SUCCEEDED **`; 58/58 tests passed, 0 failures, 0 skipped on
ordinary `iPhone 17e` iOS 26.5 Simulator. The breakdown is 13
`ActionVerifierTests`, 15 `CoachingEpisodeCoordinatorTests`, and 30
`UserMovementObserverTests`. Result bundle:
`/tmp/setos-m2-025-correction-2.xcresult`.

The first correction compile attempt failed only because the test helper gained
a local expected-identity value without an explicit return. The return was
added; no production behavior was weakened. `git diff --check` passes.

## Honest boundaries

- This packet supplies the pure result owner and the coordinator handoff. It
  does not wire presentation (`M2-027`) or add false-success confounder guards
  (`M2-026`).
- The current live producer does not yet emit typed depth, focus readability,
  or exposure-fault signals; those cases therefore remain incomparable until
  their owning producer packets supply provenance.
- The scene signature seam is verified when both lifecycle contexts provide
  signatures; one missing signature is not treated as a scene cut. Connecting
  a live scene producer is outside M2-025.
- Simulator evidence proves deterministic contracts only. Hardware camera,
  ARKit, microphone, thermal, timing and physical A/V behavior remain outside
  this packet.
