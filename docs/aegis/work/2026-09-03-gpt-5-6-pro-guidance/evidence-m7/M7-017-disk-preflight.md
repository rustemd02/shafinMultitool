# M7-017 — disk preflight

Status: **implemented and verified in the isolated external-M7 lane**
(`codex/external-m7-recording`, BASE_HEAD `02f03f6`).

## What changed

`RecordingArtifactStore` now owns a conservative free-space model:

- `RecordingDiskBudgetModel` — documented worst-case bitrate model:
  - video bits/second = width × height × fps × bits-per-pixel (H.264 0.12,
    HEVC 0.07 — deliberate upper bounds, not observed averages),
  - audio adds the fixed v1 AAC 128 kbps,
  - the byte estimate is **doubled** (pending and finalized storage must
    coexist) and a 50 MB safety floor is added,
  - default duration budget 600 s.
- `RecordingDiskBudgetEstimate` (required vs. available) is answered by
  `diskBudgetEstimate(width:height:fps:codec:audioMode:durationLimitSeconds:)`,
  querying `volumeAvailableCapacityForImportantUsage` with the plain
  volume-available fallback; a capacity query failure **fails closed**.
- Wired into the M7-008 start preflight: below-budget starts are rejected
  with typed `.insufficientStorage` before any writer exists — existing
  project media is never a target of this check.

## Acceptance criteria evidence

| Criterion | Evidence (RecordingPreflightTests) |
|---|---|
| Start blocks below required space | `testDiskBudgetBelowRequirementFailsBeforeRecording`, controller integration `testStartPreflightRejectionHappensBeforeRecorderCreation`. |
| Fail closed on query failure | `testDiskBudgetQueryFailureFailsClosed`. |
| Conservative model, monotonic in duration/codec | `testDiskBudgetModelIsConservativeAndMonotonic` (>1 GB for a 10-min 1080p30 H.264 take; HEVC < H.264; half duration < full). |
| Estimate includes duplication margin | Model doubles the estimate (asserted through the >1 GB bound) — pending + final coexist without pressuring existing media. |
| Real volume answers | `testArtifactStoreDiskBudgetEstimateAnswersOnRealVolume` (satisfied on the test volume). |

## Narrow verification

Package C focused run: **70/70 PASS, 0 failures** (xcresult
`/private/tmp/m7-pkgC-tests.xcresult`). `git diff --check` clean.

## Honest boundaries

Boundary-value fixtures run against injected estimates and the real macOS
volume; physical-device storage behavior (purgeable pressure, APFS snapshots
on a full device) remains M13 qualification.
