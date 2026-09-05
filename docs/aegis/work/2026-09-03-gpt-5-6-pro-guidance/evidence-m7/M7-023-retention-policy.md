# M7-023 — retention policy

Status: **implemented and verified in the isolated external-M7 lane**
(`codex/external-m7-recording`, BASE_HEAD `02f03f6`).

## What changed

`RecordingArtifactStore` now exposes a two-step, clock-controlled retention
owner for transient recording data:

- `retentionInventory(now:pendingMaxAge:)` — **dry-run** inventory. Only
  Pending artifacts older than the retention window are proposed, and only
  when they have **no live journal record** (a `.promoting` intent is never
  retention-deleted) or sit behind a `.failed` tombstone. Candidates carry
  their typed reason (`expiredPending` / `expiredFailedEntry`).
- `applyRetention(removing:)` — deletes **exactly** the proposed candidates,
  re-verifying each before unlink: regular file under the owned Pending root
  (dirfd-relative unlinkat), canonical `<UUID>.mov` name, still no live
  journal record. A stale inventory therefore cannot delete something that
  became live in between. Removing an `expiredFailedEntry` also removes its
  tombstone.

**Explicit policy table** (documented behavior):

| Media class | Retention behavior |
|---|---|
| Pending (no journal, expired) | deleted by retention |
| Pending behind `.failed` (expired) | deleted + tombstone removed |
| Pending behind live `.promoting`/`.pending` | never deleted |
| Completed project-owned media | **never auto-deleted** — only explicit project deletion (M7-025) |
| Journal tombstones of successful promotions | removed at commit time (M7-020) |

## Acceptance criteria evidence

`testRetentionIsClockControlledAndNeverTouchesLiveOrProjectMedia`: 8-day-old
pending files (with and without a failed tombstone) are proposed and removed;
a young pending file, an aged file behind a live `.promoting` record, and
project media all survive; the failed tombstone is removed together with its
expired file. Clock, not wall time, drives the window.

## Narrow verification

Package D focused run: **16/16 PASS** (xcresult
`/private/tmp/m7-pkgD-tests-r3.xcresult`). `git diff --check` clean.

## Honest boundaries

The production caller that schedules retention sweeps at launch/teardown
cadence is a one-line call site for the main flow (SceneDelegate-type owners
are outside this lane's file list); the policy itself is complete and tested.
Retention windows are a parameter; no product default beyond the API is
claimed.


## Acceptance addendum (coordinator integration, 2026-09-05)

The production sweep caller gap is closed: `RecordingArtifactStore
.performColdLaunchMaintenance()` converges journal records (M7-021) and then
sweeps expired pending artifacts through the dry-run retention inventory with
the documented 7-day default window (`defaultPendingRetentionWindow`);
`DBService.init` invokes it at its existing cold-launch recovery boundary.
Test: `testColdLaunchMaintenanceConvergesJournalAndSweepsOnlyExpiredPending`.
