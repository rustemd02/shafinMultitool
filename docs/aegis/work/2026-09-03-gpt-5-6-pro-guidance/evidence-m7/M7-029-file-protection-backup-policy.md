# M7-029 — file protection / backup policy

Status: **implemented and verified in the isolated external-M7 lane**
(`codex/external-m7-recording`, BASE_HEAD `02f03f6`).

## What changed

`RecordingArtifactStore` applies and documents the storage policy for the two
media classes:

| Class | Policy |
|---|---|
| Pending artifacts, promotion journal (transient) | **excluded from backups** (`isExcludedFromBackup` applied to the Pending and Journal roots at store creation and to every pending file via `applyPendingArtifactPolicy`); protection set to `.completeUntilFirstUserAuthentication` where the platform supports per-file protection (device only), so a background finalization can complete after a locked-device kill |
| Completed project-owned media | keeps the platform default file protection and **stays included in backups** — it is user data; `applyPendingArtifactPolicy` deliberately refuses paths outside the owned Pending root |

The policy helpers are no-ops-safe on filesystems that do not support a key
(simulator, temp containers): they never fail the recording path.

## Acceptance criteria evidence

`testTransientRootsAndPendingFilesAreExcludedFromBackup`: Pending and Journal
directories read back `isExcludedFromBackup == true`; a pending file after
`applyPendingArtifactPolicy` reads excluded; a project file passed to the
same helper is left non-excluded (user data stays backed up).

## Narrow verification

Package D focused run: **16/16 PASS** (xcresult
`/private/tmp/m7-pkgD-tests-r3.xcresult`). `git diff --check` clean.

## Honest boundaries

`FileProtectionType` values cannot be verified on the simulator (protection
is device-only); the code path is `#if os(iOS) && !targetEnvironment(simulator)`
and its effect is an explicit M13 physical-device check. Backup-exclusion
behavior against a real iCloud account is likewise device work.
