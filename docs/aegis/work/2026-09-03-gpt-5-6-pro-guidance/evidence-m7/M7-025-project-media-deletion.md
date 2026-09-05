# M7-025 — project media deletion

Status: **production owner verified and journal-cleanup extension implemented**
(`codex/external-m7-recording`, BASE_HEAD `02f03f6`).

## What changed

Project media deletion was already the M5-010/M5-006 reversible transaction:
`DBService.deleteUnifiedSceneProject` stages the project's owned artifacts
via `RecordingArtifactStore.stageProjectArtifacts` (same-volume hard links in
a private staging directory), commits only after the authoritative metadata
mutations, and restores on partial unlink failure. Deletion cannot escape the
project directory: staged entries must be regular `<UUID>.mov` files;
Pending, sibling projects, and user media are out of scope by construction.

This lane added the M7-019 integration the earlier work could not know
about: `RecordingArtifactStore.removeProjectJournalRecords(projectID:)` is
now called by the deletion transaction **after** its artifact commit, so a
leftover promotion tombstone bound to the deleted project (which could never
recover) does not linger for a later cold launch. Removal is best-effort per
record; a failure cannot resurrect the deleted project.

**Deliberate boundary (tested):** a failed take's **Pending** file is NOT
deleted by project deletion — pending files are not project-owned media, and
M7-023 retention owns their expiry so a deletion bug can never destroy a
recoverable take. Partial failure of the whole transaction remains surfaced
and retryable through the existing rollback/typed-failure path.

## Acceptance criteria evidence

`testProjectDeletionRemovesOwnedMediaAndLeftoverJournalRecords`: a project
with a leftover failed promotion record and pending file is deleted —
the tombstone is removed, the owned project artifacts are committed gone,
the pending file deliberately survives for retention, and sibling project
media is byte-identical. Rollback/partial-failure retryability remains
covered by the existing `DBServiceConcurrencyTests` deletion matrix
(regression green in `/private/tmp/m7-pkgD-tests-r2.xcresult`).

## Narrow verification

Package D runs: 16/16 (`RecordingRecoveryAndRetentionTests` +
`RecordingDiagnosticsTests`, xcresult `/private/tmp/m7-pkgD-tests-r3.xcresult`)
and 41/41 regression (`DBServiceConcurrencyTests`, `PendingRecordingJournalTests`,
same-file suite in r2). `git diff --check` clean.
