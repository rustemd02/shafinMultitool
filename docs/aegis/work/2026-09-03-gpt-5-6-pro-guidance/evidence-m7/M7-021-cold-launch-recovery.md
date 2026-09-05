# M7-021 — cold-launch recovery

Status: **implemented and verified in the isolated external-M7 lane**
(`codex/external-m7-recording`, BASE_HEAD `02f03f6`).

## What changed

`RecordingArtifactStore.recoverPendingRecordings()` classifies and converges
every journal record after a cold launch, deterministically ordered by
recording ID, each record independent so one corrupt entry cannot block the
rest:

| Classification | Convergence |
|---|---|
| Complete-valid (destination regular) | `.alreadyPromoted` — journal tombstone removed, destination untouched |
| Resumable promotion (source regular, no destination) | `.completed(reference)` — promotion re-run through the journaled transaction; retry count incremented by recovery (bounded budget); metadata (duration/audio) restored by the pluggable probe (production: `AppleRecordingMediaMetadataProbe` reads the actual asset) |
| Corrupt record | `.corruptRecord` — surfaced for honest diagnosis, **never deleted** |
| Missing (source + destination gone) | `.missingArtifact` — tombstone removed |
| Failed / retry budget exhausted | `.failedEntry` — pending file preserved for user-visible recovery, never silently deleted |

**Production wiring:** `DBService.init` runs recovery best-effort on the
store it creates itself (the shared recordings root's first cold-launch
consumer — before any workspace can observe a half-promoted take); an injected
store (tests) keeps its own lifecycle. A recovery failure is logged and
deferred to the next launch; the SceneDelegate launch hook (tracker's
suggested area) is outside this lane's file ownership and remains a
one-call-site option for the main flow.

## Acceptance criteria evidence

`RecordingRecoveryAndRetentionTests`: resumable promotion completes with
real metadata and consumes the pending source; crash-after-commit converges
to already-promoted without touching destination bytes; corrupt records are
reported and preserved; missing artifacts converge with tombstone removal;
retry-budget exhaustion and failed entries preserve pending files; sibling
project media is byte-identical after recovery.

## Narrow verification

Package D focused run: **16/16 PASS** (`RecordingRecoveryAndRetentionTests`,
`RecordingDiagnosticsTests`, xcresult `/private/tmp/m7-pkgD-tests-r3.xcresult`);
journal + DBService regressions green in `/private/tmp/m7-pkgD-tests-r2.xcresult`
(41/41 there). `git diff --check` clean.
