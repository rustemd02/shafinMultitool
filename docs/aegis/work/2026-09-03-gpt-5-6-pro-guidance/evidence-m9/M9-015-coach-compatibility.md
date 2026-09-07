# M9-015 — Coach compatibility evidence

Status: CLOSED on the current store (verify-and-close over the
control-change invalidation chain; calibrated-model re-verification
returns at M4-GATE).

## Acceptance → existing owners/proof

- "Format/exposure/focus/WB/lens changes invalidate affected
  evidence": `SubjectTrackInvalidationCause` enumerates
  `lensChange`, `orientationChange`, `cameraGenerationChange` (plus
  route/background/scene-cut) — every capture-control change
  invalidates the subject track immediately
  (`SubjectTracker.invalidate`, explicit loss phase, advice must
  invalidate). Lens switches run the M1-006 serialized transaction
  with preview/config/track/episode invalidation (M9-002/003);
  format changes consult the device-derived support gate before
  writer/input creation (M9-008); exposure/WB changes are
  session-queue serialized with read-back and applied-only
  persistence (M9-009/010/014).
- "No stale advice": every feature source carries a
  `FeatureFreshnessVerdict` (age measured, unavailable exposed) and
  evidence enters published state only with an available verdict
  (M2-005/M2-006 pause package); the advice safety gate invalidates
  subject-dependent corrections first on a lost track
  (`CameraAdviceSafetyGate`).
- "User control intent suppresses contradictory automatic advice":
  the M9-011/012 focus/WB policy pins explicit tap routing with no
  silent focus change and manual surfaces absent from the Coach path
  (3/3 policy tests); WB honestly legacyOnly.

## Verification

The chain is covered by the closed dependencies' suites
(SubjectResolver/Tracker, safety gate, fusion/calibrator 40/40 at
M4-019/020, lens 41/42, capture config, exposure/WB/persistence
12/12). No new production change was required: the semantic content
of this task is the invalidation/recalibration structure, which is
implemented and pinned.

## Boundary

"Recalibrate" quality with the production neural model re-verifies
at M4-GATE (calibrated evidence arrival, M4-016 conversion); Pro
Controls presentation builds on this in M9-016/017.
