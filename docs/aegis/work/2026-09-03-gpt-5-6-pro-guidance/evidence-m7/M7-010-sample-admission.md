# M7-010 — sample admission

Status: **implemented and verified in the isolated external-M7 lane**
(`codex/external-m7-recording`, BASE_HEAD `02f03f6`).

## What changed

`SerializedMediaRecorder` admission is now a typed verdict with a per-take
bounded ledger:

- `admissionVerdict(_:generation:ownerToken:)` classifies every submitted
  sample as `accept`, `rejectInactive`, or `rejectStaleSource`:
  - **inactive** — before session start, after the stop boundary
    (`acceptingFrames` cleared in `beginFinish`), recorder not in
    `.recording`, or no writer attached;
  - **stale source** — recording ID, active generation, or owner-token
    mismatch (exact M7-002 source fence).
- Every rejection is counted by reason and stream in the M7-006 timebase
  report (`rejectedInactiveCount`, `rejectedStaleSourceCount`); rejected
  samples are never appended and can never fail the take.
- Timestamp validity and per-stream monotonicity gate admission **before**
  any writer call (M7-006), so non-finite/out-of-order samples are also
  rejected-and-counted rather than surfacing as writer failures.
- The M1-012/M7-002 invariants are unchanged: no sample is accepted before
  start or after stop; a late callback cannot revive a released take.

## Acceptance criteria evidence

| Criterion | Evidence |
|---|---|
| Before start / after stop rejected and counted | `testStaleSourceAndOutsideWindowSamplesAreRejectedAndCounted` (post-stop enqueue with the take's own fence is counted inactive); `testLateFrameDroppedAfterStopFence` (writer never sees it). |
| Stale source rejected and counted | Same test (generation-mismatched fence), `testExactSourceTokenIsRequiredForFramesAndStaleReleaseCannotClearOwner` (regression green in this lane). |
| Invalid timestamps rejected and counted | `testNonFiniteVideoTimestampIsRejectedAndCountedNeverAppended` (M7-006). |
| Monotonic time gate | M7-006 suite, rerun green in this lane. |
| Readiness gate | Writer-not-ready samples are writer `.dropped` results, accounted under the M7-011 policy — they never block the capture queue. |

## Narrow verification

Package B focused run: **79/79 PASS, 0 failures** (xcresult
`/private/tmp/m7-pkgB-tests-r2.xcresult`). `git diff --check` clean.
