# M7-020 — atomic promotion

Status: **implemented and verified in the isolated external-M7 lane**
(`codex/external-m7-recording`, BASE_HEAD `02f03f6`).

## What changed

`RecordingArtifactStore.promoteFinalizedArtifact` now wraps the M1-014
idempotent rename in the M7-019 journal transaction:

1. **Journal write (atomic, before anything moves).** `beginPromotionJournalEntry`
   records the `.promoting` intent with source/destination relative paths and
   the pending file's observed size. A leftover record for the same identity
   resumes (retry budget owned by recovery); a record for a different
   identity fails closed as typed corruption; corruption anywhere fails
   closed **before** any file moves.
2. **The move itself** — the unchanged M1-014 transaction: fd-based directory
   traversal with `O_NOFOLLOW`, `RENAME_EXCL` rename, idempotent reporting of
   a concurrently committed take, inode verification with rollback on
   mismatch, symlinks and non-regular sources rejected.
3. **Journal removal (only after commit).** Every success path — including
   the idempotent "destination already committed" returns — removes the
   record; removal races resolve to the same terminal state.
4. **Fault injection (DEBUG-only, self-clearing):** `beforeJournalWrite`,
   `afterJournalWrite`, `afterRename`, `afterJournalRemoval` — deterministic
   crash points used by the convergence tests (and reused for M7-022).

## Acceptance criteria evidence

Fault matrix (`RecordingArtifactPromotionTests`, one test per crash point):
each point is injected, the attempt fails typed, and the retried promotion
converges to exactly one valid project reference, one destination file, a
consumed pending source, and **no leftover journal record**:

- `testPromotionRecoversFromCrashBeforeJournalWrite`
- `testPromotionRecoversFromCrashAfterJournalWrite`
- `testPromotionRecoversFromCrashAfterRename` (rename committed before the
  "crash": retry reports the same reference idempotently)
- `testPromotionRecoversFromCrashAfterJournalRemoval` (fully committed before
  the "crash": retry converges without duplicating)

M1-014 regressions stay green in the same run: 8-thread concurrent promotion
→ one file, identical references; interrupted-promotion resume; non-regular
destination conflict preserves the pending source.

## Narrow verification

Package C focused run: **70/70 PASS, 0 failures** (xcresult
`/private/tmp/m7-pkgC-tests.xcresult`). `git diff --check` clean.
