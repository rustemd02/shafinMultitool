# M7-019 — pending artifact journal

Status: **implemented and verified in the isolated external-M7 lane**
(`codex/external-m7-recording`, BASE_HEAD `02f03f6`).

## What changed

New `Services/Recording/PendingRecordingJournal.swift` — the durable
pending-artifact journal:

- `PendingRecordingJournalEntry`: project/recording IDs, Application
  Support-relative source temp path, project destination relative path,
  expected file size, a reserved `expectedSHA256` schema field (promotion
  writes size-only integrity for v1 — hashing gigabyte media on the promotion
  path is deliberately avoided), typed state (`pending`, `promoting`,
  `promoted`, `failed`), bounded retry count, and timestamps. No absolute
  paths, no user content.
- `PendingRecordingJournal`: one record per pending file at
  `Recordings/Journal/<recordingID>.json`, written **atomically** (temporary
  file + rename), so a killed process cannot expose a half-written record.
  Reads fail closed: an undecodable record is the typed
  `.journalCorrupt(recordingID:)`, never silently ignored; `allEntries()`
  classifies readable vs. corrupt records for recovery.
- Exactly one record per pending file is enforced by the keyed filename; the
  retry budget (`maxRetryCount = 3`) is owned by cold recovery, not the hot
  promotion path, so concurrent idempotent promotions cannot exhaust it.

## Acceptance criteria evidence

| Criterion | Evidence (PendingRecordingJournalTests) |
|---|---|
| Journal writes atomically before promotion | Production integration: `RecordingArtifactStore.promoteFinalizedArtifact` writes the `.promoting` record before any directory/rename work (verified through the M7-020 fault matrix). |
| Atomic replace | `testAtomicReplaceKeepsExactlyOneRecordPerRecording` (one file, latest wins). |
| Every pending file has one record | Keyed record name = recording ID; `testRemoveIsIdempotentAndAllEntriesClassifiesStates`. |
| Encode/decode round-trip | `testRecordAndReadBackIsLossless`. |
| Corrupt/missing journal is detectable | `testMissingRecordReadsAsNilNotAnError`; `testCorruptRecordIsATypedDetectableFailure` (typed corruption in `entry(for:)` and `allEntries()`). |

## Narrow verification

Package C focused run: **70/70 PASS, 0 failures** (xcresult
`/private/tmp/m7-pkgC-tests.xcresult`). `git diff --check` clean.
