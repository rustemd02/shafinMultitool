# M7-018 — disk exhaustion

Status: **implemented and verified in the isolated external-M7 lane**
(`codex/external-m7-recording`, BASE_HEAD `02f03f6`).

## What changed

ENOSPC-class failures during recording are now **typed and safe** instead of
generic append failures:

- `RecordingAppendDisposition.storagePressure` — the Apple writer inspects a
  failed writer (`AVAssetWriter.status == .failed`) via
  `isStoragePressureError` (POSIX `ENOSPC` and Cocoa
  `NSFileWriteOutOfSpaceError`) and reports storage pressure as its own
  disposition on video and audio appends.
- `SerializedMediaRecorder` maps the disposition to the typed
  `RecorderFailure.insufficientStorage` (M7-008 taxonomy), stops admission,
  and fails the take; no captured sample is lost silently and the capture
  queue never blocks.
- **Partial-file policy (validity):** on the subsequent stop the take
  finalizes through the normal single-shot path — if the writer can still
  complete a valid movie, the artifact is reported as recoverable (kept); if
  completion fails, the Apple adapter's discard path removes the
  not-completed output. Either way no unbounded temp data survives and
  **existing project media is never a candidate for deletion**.
- Promotion-time exhaustion is also safe: a journal write or rename failing
  with any filesystem error aborts BEFORE the move (or leaves the committed
  destination + journal record for recovery), leaving the pending file intact
  for a later retry (M7-019/M7-020).

## Acceptance criteria evidence

| Criterion | Evidence |
|---|---|
| Failure terminates safely | `testStoragePressureAppendFailsTypedWithoutRecoverableArtifactAndLeavesNoFrames` (typed `.insufficientStorage`, no recoverable artifact from an empty take, exactly one writer call). |
| Keeps/deletes partial per validity | Writer-completion path keeps the artifact recoverable only when `acceptedVideoCount > 0` and the writer attests completion (`testVideoAppendFailureReturnsRecoverableArtifact` regression green); incomplete outputs are removed by the adapter discard path (`testNativeWriterRemovesOutputOnFailedFinish` regression green). |
| Updates project once | The VM promotion ledger (M1-014) consumes only recorder-attested finalized results; a failed take produces no artifact and no project update (regression suites green). |
| No unbounded temp data | Removal-on-discard + removed partials; `Pending`/`Journal` stay bounded per take (journal records removed on success). |

## Narrow verification

Package C focused run: **70/70 PASS, 0 failures** (xcresult
`/private/tmp/m7-pkgC-tests.xcresult`). `git diff --check` clean.

## Honest boundaries

Injected ENOSPC fixtures drive the deterministic convergence; a real
device-level full-disk fill during recording/finalization is M13 physical
qualification.
