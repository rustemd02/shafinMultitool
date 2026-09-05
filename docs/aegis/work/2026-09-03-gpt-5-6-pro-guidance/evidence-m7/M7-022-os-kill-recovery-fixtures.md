# M7-022 — OS-kill recovery fixtures

Status: **deterministic host kill-point fixtures implemented and verified**
(`codex/external-m7-recording`, BASE_HEAD `02f03f6`).

## Declared kill-point matrix and convergence

| Kill point | State on relaunch | Convergence (fixture) |
|---|---|---|
| K0 — kill before journal write (during recording/finalization) | Pending file, no journal record | `testKillBeforeJournalWriteConvergesThroughOrphanCleanup`: cold launch classifies the file as an orphan; cleanup converges it to "gone" while project media survives |
| K1 — kill before the promotion journal write | Nothing moved; no record | `testPromotionRecoversFromCrashBeforeJournalWrite` |
| K2 — kill after journal write, before rename | `.promoting` record, source in Pending | `testPromotionRecoversFromCrashAfterJournalWrite` → retry completes, one reference |
| K3 — kill after rename, before tombstone removal | Destination committed, source consumed, record present | `testPromotionRecoversFromCrashAfterRename` → idempotent reference, tombstone removed |
| K4 — kill after tombstone removal (caller never learned) | Fully committed, no record | `testPromotionRecoversFromCrashAfterJournalRemoval` → retry converges without duplicating |
| K5 — kill during journal-record write itself | At most a fully-written or absent record (atomic temp+rename) | `testAtomicReplaceKeepsExactlyOneRecordPerRecording` + `testMissingRecordReadsAsNilNotAnError` |
| K6 — kill mid-recording leaves a partial writer output that never finalizes | Invalid partial file | Adapter discard removes not-completed outputs (`testNativeWriterRemovesOutputOnFailedFinish` regression); if the process died before cleanup, K0 classification handles the leftover |

Every declared point converges to **exactly one** of: one valid project
reference, one recoverable pending state, or a reported corrupt/missing
classification — never a duplicate reference or an orphan left unaccounted.

## Physical boundary (honest)

These are host fault fixtures (injected crash points on the real filesystem
owner), exactly the tracker's "host fault fixtures" half of the evidence
column. Actual `SIGKILL` timing on physical iPhone/iPad hardware remains M13
device qualification and is explicitly not claimed.
