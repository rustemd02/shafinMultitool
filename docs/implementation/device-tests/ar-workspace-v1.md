# ar-workspace-v1 — locked physical AR workspace qualification

Status: **locked script (v1). Execution requires physical iPhone and iPad —
deferred to M13. Simulator evidence never substitutes for this script.**

Scope authority: Master Plan v2 M6-021. Every step records its exact
evidence field into the M13 device-evidence bundle. A step passes only with
its recorded artifact; partial completion may not be reported as a PASS.

## Device matrix (locked)

- iPhone (minimum supported iOS version of the app, ARKit world-tracking
  capable), portrait + landscape.
- iPad (same build, ARKit world-tracking capable), both orientations.
- A room with real textured surfaces and even lighting; a second dim room
  for the tracking-limitation step.

## Steps

1. **Entry readiness** — open the generator workspace: preparing → ready
   requires a real AR frame with detected planes (no timed fake readiness);
   unsupported-device path shows the localized AR-unavailable recovery.
   Evidence: screen recording + readiness trace export.
2. **Surface search** — point at a textureless floor beyond the bounded
   window: retry/reposition guidance appears; no fake surface is selected;
   pointing at a textured surface promotes search → placement-ready.
   Evidence: screen recording + posture trace.
3. **Placement determinism** — generate a two-actor scene twice in the same
   room: actors/objects place at stable positions relative to markers/
   detections; same inputs → same placement; invalid targets rejected with
   typed recovery. Evidence: before/after screenshots + placement dump.
4. **Marking lifecycle** — mark three objects: tap → name sheet → save;
   rename one, cancel one, duplicate-alias conflict fails closed with
   guidance; marker anchors survive an app relaunch via world-map restore
   (same session: anchors restore once, no duplicates). Evidence: project
   reload dump + anchor count before/after.
5. **Tracking limitations** — cover the camera / shake the device: limited
   tracking state surfaces the localized guidance, capture controls disable
   semantically + accessibly, recovery re-promotes readiness only on a real
   frame. Evidence: screen recording + posture events.
6. **Interruption** — trigger a system interruption (Siri/phone call) with
   an active take and open workspace: recording finalizes exactly once,
   playback/hints stop, recovery is evidence-based, no hidden second take.
   Evidence: reference count + recorder report.
7. **Background/foreground** — background mid-take: the single background
   lease runs the awaited teardown; relaunch converges through cold-launch
   recovery with exactly one project reference; foreground after clean exit
   re-promotes readiness on a real frame only. Evidence: relaunch dumps.
8. **World map restore** — save a project with a world map, move the device
   >2 m, reopen: map restores entity bindings once; an incompatible/corrupt
   map falls back to reset with the localized recovery (never duplicates
   anchors). Evidence: anchor count + restore trace.
9. **Hint pause** — pause hints: hint advancement freezes; AR tracking and
   an active recording continue untouched; resume continues from the owned
   action; leave workspace during pause → clean teardown. Evidence: screen
   recording + teardown trace.
10. **Recording integrity in AR** — record a 60 s take while walking the
    full placement/marking flow: one owner token throughout, no samples
    outside the take window, orientation metadata upright in playback.
    Evidence: recorder report + playback screenshots.
11. **Teardown convergence** — exit the workspace during each of: surface
    search, active marking, hint pause, active take: concurrent exit calls
    converge to one teardown; blocked results name the owner; route retains
    on failure. Evidence: teardown traces ×4.
12. **iPad window modes** — repeat steps 1–4, 8 on iPad in both
    orientations plus a resizable-window size change mid-workspace: layout
    reflows without state loss; invalid camera/AR size pauses safely.
    Evidence: screenshots + state dump.

## Pass criteria

Every step's artifact recorded; zero fabricated surfaces/anchors; every
failure path surfaces its localized typed recovery; no duplicate anchors or
project references after restore/interruption/teardown.
