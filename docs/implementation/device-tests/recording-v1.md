# recording-v1 — locked physical recording/playback/media qualification

Status: **locked script (v1). Execution requires physical iPhone and iPad —
deferred to M13. Simulator evidence never substitutes for this script.**

Scope authority: Master Plan v2 M7-032. Every step below records its exact
evidence field into the M13 device-evidence bundle. A step passes only with
its recorded artifact; partial completion may not be reported as a PASS.

## Device matrix (locked)

- iPhone (minimum supported iOS version of the app), portrait + landscape
  both orientations.
- iPad (same build), both orientations, Split View not required for v1.
- Two devices for interruption/Phone-call steps if available; otherwise the
  steps are marked `not-executed` honestly.

## Steps

1. **Microphone permission** — fresh install, sound-on take triggers the
   contextual request exactly once; deny → explicit video-only choice or
   localized denied state; no silent downgrade. Evidence: screen recording +
   permission snapshot.
2. **Start/stop** — 10 takes: start ≤ 1 s from tap to recording state, stop
   finalizes each take, exactly one project reference per take, no orphan
   pending files after each stop. Evidence: project list + Pending/Projects
   directory listing.
3. **Orientation** — record 10 s in each device orientation; playback is
   upright in all four; encoded natural size keeps source dimensions.
   Evidence: four exported clips + playback screenshots.
4. **Lens change policy** — lens switch during an active take follows the
   M1-006 transaction policy (rejected or cleanly fenced); no take survives
   with mixed lens metadata. Evidence: take metadata dump.
5. **Audio session interruption** — start a sound-on take, place a phone
   call: take finalizes the partial clip exactly once (one reference, no
   hidden second clip), recovery after the call does not auto-resume.
   Evidence: reference count + audio-track presence.
6. **Background** — background the app mid-take and mid-finalize: finalize
   completes under the background lease or converges through cold-launch
   recovery on relaunch; exactly one reference either way. Evidence:
   relaunch state dump.
7. **A/V sync** — clap/flash at start and end of a 30 s sound-on take:
   absolute sync error ≤ 80 ms at start and end, no monotonicity fault in
   the recorder report. Evidence: sync report export + measurement sheet.
8. **Drops/backpressure** — 10-minute continuous take on device: dropped
   frame counts stay inside the documented policy; no unexplained failure.
   Evidence: timebase report export.
9. **Low disk** — fill storage to the documented budget boundary: start is
   rejected with the localized insufficient-storage recovery; an active
   take under ENOSPC fails typed without damaging existing project media.
   Evidence: preflight failure screenshot + media inventory checksums.
10. **OS kill** — SIGKILL (instruments or Xcode) at the locked kill points
    K0–K4 during finalization/promotion: relaunch converges to exactly one
    valid reference or one recoverable failure; no duplicate references, no
    orphan temp files. Evidence: per-point relaunch state dump.
11. **Playback** — play a promoted recording: upright with audio when
    present; missing/corrupt media yields the localized recovery; leaving
    the state releases the player and the playback audio lease. Evidence:
    player screenshots + lease state.
12. **Photos export** — contextual add-only permission on first export;
    success emitted only after Photos completion; denied/restricted states
    localized. Evidence: Photos app verification + export receipt.
13. **Share** — share sheet presents the resolved file; cancellation is a
    no-op; deleting the project removes the stale URL safely. Evidence:
    share screenshots.
14. **Deletion** — delete a project with media while recording in another
    project: only the deleted project's media is removed; journals cleaned;
    sibling media byte-identical. Evidence: before/after checksums.
15. **Soak** — 30-minute mixed recording/playback/rotation session: no
    thermal failure above the documented policy, no memory growth beyond
    the documented budget, no monotonicity fault. Evidence: diagnostics
    export.

## Execution order and lock

Steps run in order on a freshly installed build of a single locked commit.
Any failure re-runs the step once; a persistent failure records the step as
`FAIL` with the receipt and reopens the corresponding tracker dependency.
