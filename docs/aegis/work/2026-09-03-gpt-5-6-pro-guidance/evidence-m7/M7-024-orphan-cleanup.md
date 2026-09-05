# M7-024 — orphan cleanup

Status: **implemented and verified in the isolated external-M7 lane**
(`codex/external-m7-recording`, BASE_HEAD `02f03f6`).

## What changed

`RecordingArtifactStore.orphanInventory()` / `removeOrphans(_:)` — a dry-run
first, re-verify-then-delete orphan owner over the owned Pending root:

- **Eligible (`orphan`)**: regular files with a canonical `<UUID>.mov` name
  and **no journal reference**.
- **Reported and skipped (never deleted, never followed)**:
  - directories (never traversed — `projectEntries` reads names only),
  - symlinks (detected via `fstatat AT_SYMLINK_NOFOLLOW` before any follow),
  - foreign file names (anything that is not `<UUID>.mov` — user files
    cannot be matched even by name collision),
  - irregular file types,
  - validly named files that have a journal reference.
- **Deletion is structurally traversal-safe**: names come from `readdir`,
  unlinks are `unlinkat(pendingFD, name)` (dirfd-relative), and every
  candidate is re-verified at deletion time (regular, same name↔UUID binding,
  still no journal record). There is no code path that accepts an externally
  supplied path string.

## Acceptance criteria evidence

`testOrphanCleanupIsAttackSafeAndDryRunFirst`: a genuine orphan is classified
and removed; a journal-referenced file, a `notes.txt` foreign file, and a
symlink (whose **target** survives untouched) are all skipped with explicit
reasons; the dry-run inventory precedes deletion and its classification is
asserted. `testKillBeforeJournalWriteConvergesThroughOrphanCleanup` proves
the kill-recovery convergence through this path.

## Narrow verification

Package D focused run: **16/16 PASS** (xcresult
`/private/tmp/m7-pkgD-tests-r3.xcresult`). `git diff --check` clean.
