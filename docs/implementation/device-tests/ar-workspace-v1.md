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

## v3 case checks (AR / multi-object) — added Q03, not yet executed

These checks extend the v1 steps with the multi-object and review cases from
`camera-coach.domain.v3-draft.1` (`docs/cameraanalysis/03-domain-contracts.md`
N9–N12) and the release runbook §10.1. They are not a second handbook; the
recording-side v3 checks are in `recording-v1.md`.

**Status rule:** every check starts `not_executed`. No hardware gate is marked
`pass` by Q03 preparation. Statuses and evidence roles are enforced by
`tools/device/import_device_report.py`; the operation registry is still draft,
so an unqualified operation records `not_supported`, not a pass.

13. **`v3.two_object_target`** — cases CC-O01/O02/O05/CC-I01. Build a two-object
    scene (the two-lamp example): one active action at a time, exact target
    entity, protected person/object, and the same track before/after. A swap, an
    occlusion that hides the target, or success attributed to the wrong lamp
    fails the check. Evidence: `metadata_dump` (analysis/session ids, targetRefs,
    protectedRefs, track bindings) + `screen_recording`. Category `functional`.
14. **`v3.protected_ref_intent`** — cases CC-I05/CC-R01. Declare an intentional
    style (silhouette, dutch angle, negative space, low key): it must be
    protected. With darkness/style protected, the result is KEEP only alongside
    other sufficient positive checks, otherwise ABSTAIN/protected_intent; no
    automatic fill/level is applied. Evidence: `metadata_dump` (intent.styles +
    decision) + `screen_recording`. Category `functional`.
15. **`v3.glare_review`** — cases CC-L05/CC-L06. Confirm an observed hotspot and
    a light-direction hypothesis, then a review proposal (`rotate_entity` /
    bounded probe). The verifier compares the hotspot in the protected region;
    the VLM's confidence about its own advice is not the measurement. Evidence:
    `metadata_dump` (hotspot region before/after, proposal id) + `screen_recording`.
    Category `functional`.
16. **`v3.lens_switch_fence`** — cases CC-T04. Switch the physical lens during an
    active AR take / live workspace; the take must be rejected or cleanly fenced
    with no mixed-lens metadata surviving, and the AR overlay must not silently
    keep a stale camera transform. Evidence: `metadata_dump` (lens + per-take
    metadata) + `screen_recording`. Category `functional`.

Step 12 (`ar.ipad_window_modes`) keeps its v1 procedure; when executed in the
Q04 run it must also record the iPad model identifier, iPadOS version/build and
active-window size in the manifest. It remains `not_executed` until Q04.
