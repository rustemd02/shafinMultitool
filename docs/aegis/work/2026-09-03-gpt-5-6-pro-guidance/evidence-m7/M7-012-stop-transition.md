# M7-012 — stop transition

Status: **production owner verified in the isolated external-M7 lane; no new
production change required** (`codex/external-m7-recording`, BASE_HEAD `02f03f6`).

## Verified production behavior

- **Idempotent recording → stopping, exactly once.** All stop entry points —
  user stop, interruption, background, route exit, storage/thermal pressure,
  and error stops — funnel into one serialized operation:
  `SceneRecordingController.stop` transitions `.recording → .stopping` under
  the state queue and creates a single stop task; the recorder's
  `handleStopOnQueue` funnels every reason through `beginFinishOnQueue`,
  guarded by `finishInFlight` so the writer finishes exactly once.
- **Stop admission boundary is exact.** The accepting fence is cleared before
  finalization begins, the recorder advances its generation, and the M7-010
  verdict rejects post-boundary samples as `inactive` (now with a counted
  ledger instead of silent drops).
- **Join semantics.** Concurrent stops share one finish and receive the
  identical result; repeated stop after completion returns the cached result
  without a second finish; stop during an in-flight start joins the start
  task first; release during finishing waits for the shared result.
- **Late callbacks cannot revive the take.** `finishCompletedOnQueue` is
  guarded by `finishInFlight`; the M7-013 watchdog makes a hung writer
  terminal, after which even a late successful callback cannot replace the
  result.

## Verification (fresh in this lane)

`SerializedMediaRecorderTests` stop matrix rerun green — concurrent stop
sources share one finish, repeated stop is cached, duplicate writer callback
resolves waiters once, late frame after the stop fence is rejected,
video-append failure stop returns the typed recoverable result — plus
`SceneRecordingControllerTests` (stop joins start, stop single-flight,
release ordering) and `RecordingStartTeardownRaceTests`.

Package B focused run: **79/79 PASS, 0 failures** on iPhone Air simulator
iOS 26.5 (xcresult `/private/tmp/m7-pkgB-tests-r2.xcresult`).

## Honest boundaries

Interruption/background stop *sources* (M7-014/M7-015) are other owners; this
task covers the serialized stop transition they must call into.
