# M7-013 — finalization

Status: **implemented and verified in the isolated external-M7 lane**
(`codex/external-m7-recording`, BASE_HEAD `02f03f6`).

## What changed

Finalization was already single-shot and typed (inputs marked finished once,
writer terminal status validated, duplicate callbacks ignored); the gap this
task closed is the **timeout**:

- `SerializedMediaRecorder` gained a `finalizationTimeout` (production
  default 10 s). When `beginFinishOnQueue` submits `writer.finishWriting`, it
  schedules a watchdog **on the recorder's own serialized queue**.
- A fired watchdog: discards the writer (the Apple adapter cancels writing
  and removes the not-completed output file — no orphan partial), detaches
  resources, resolves all stop/release waiters with the typed
  `.failed(.finishFailed, recoverableArtifact: nil)`, and moves the state to
  `.failed` (or `.released` when a release was requested).
- Ordering is total because watchdog and completion run on the same queue:
  a completed finish sets `finishInFlight = false` so the watchdog is a
  no-op, and a fired watchdog clears it so a **late writer callback cannot
  revive the take** — it is dropped and the terminal result stays.
- A timed-out take still converges to a recoverable pending state: the
  pending file is removed by the adapter's discard path (no valid finalized
  bytes can be attested), so no unbounded temp data survives.

## Acceptance criteria evidence

| Criterion | Evidence |
|---|---|
| Inputs mark finished once; writer status validated | Existing matrix rerun green (`events` assertions: `mark-video, mark-audio, finish`; `writer.status == .completed` gate in the adapter). |
| Timeout → typed failure, resources closed | `testFinalizationTimeoutFailsTypedAndLateCallbackCannotReviveTheTake`: held writer finishes by watchdog with `.finishFailed`, `discardCount ≥ 1`, state `.failed`. |
| Duplicate/late callback cannot revive | Same test: late successful `completeFinishTwice` after the timeout leaves result and state unchanged; `testDuplicateWriterCallbackResolvesWaitersOnceAndKeepsStableResult` regression green. |
| Stop waiters always resolve | Same test (stop returns after the watchdog) and the release-during-finish regression. |

## Narrow verification

Package B focused run: **79/79 PASS, 0 failures** (xcresult
`/private/tmp/m7-pkgB-tests-r2.xcresult`). `git diff --check` clean.

## Honest boundaries

The watchdog proves the timeout policy deterministically with a held fake
writer; real-device writer stalls (page cache pressure, media-services reset
mid-finalize) belong to M13 physical qualification.
