# M2-023 — Production-compatible movement observation contract

Task: observe action-relevant user movement from accepted feature and motion
evidence instead of elapsed time.

Owner boundary: `UserMovementObserver` and its existing frame-streak tracker.
The observer remains pure; episode coordination and final verification stay
outside this slice. Production consumption of the observer is intentionally
owned by M2-024 (`CoachingEpisodeCoordinator`); this task does not claim that
the live suggestion path already invokes it.

## Production contract

`UserMovementFrame` keeps the source-compatible displacement/luma initializer
and adds action-aware metrics plus typed `UserMovementEvidence`.
Action-aware evidence requires a non-optional coach orientation, known and
matching shared pipeline capture generation, calibrated input, distinct frame IDs, fresh source
timestamps, and confidence at least `0.5`. Subject-dependent families
(displacement, scale/distance, light/exposure, and focus) additionally require
one equal `SubjectTrackIdentity` bound to the measured region in each frame. A
free-form `subjectTrackID` is retained only as compatibility metadata and
cannot satisfy that binding. Horizon/rotation and stability are frame-global
families and validate frame, lens, orientation, calibration, and source
freshness without requiring a selected subject.

`CameraManager` owns a capture generation distinct from the analysis lifecycle
generation. It stamps that generation into `FrameContext`, rotates it after a
successful input replacement and at teardown/failure boundaries, and pauses and
drains frame delivery around lens/orientation mutations so a queued old-input
buffer cannot inherit new provenance. The accepted-frame path stores the same
value in the existing `AcceptedFrameEnvelope.lensGeneration` field.
`SubjectTrackIdentity.generation` must equal it; the observer keeps this as one
shared-generation invariant rather than treating the fields as independent
counters.

The snapshot/envelope adapter requires the frame IDs and capture timestamps to
match and requires the supplied coach orientation's image orientation to match
the accepted envelope. A selected subject binding, when present, must be a
`.vision` or `.detr` source in Vision coordinates and must equal
`SubjectSignals.primaryCandidateSource`; legacy snapshots without that source
are rejected for subject-bound observation. Its source timestamp and
confidence are read from that same source (Vision bindings use Vision evidence,
DETR bindings use DETR evidence). The adapter is also constructible without a
binding for frame-global horizon/stability metrics. In that case subject region,
subject-dependent metrics, timestamps, confidence, and availability are absent.
Asynchronous DETR samples carry their originating frame ID, capture generation,
and orientation. A mismatched sample and its legacy debug fallback are removed
before an accepted snapshot is built. Source inspection confirms that delayed
callbacks use the same provenance fence before mutating shared feature or
overlay state; the targeted suite does not inject a delayed detector callback.
Stale, missing, low-confidence,
uncalibrated, unknown-lens,
orientation-changing, or identity/region-mismatched evidence returns
`.uncertain` (or is rejected by the adapter).

The lighting estimator currently publishes no producer confidence. The
adapter therefore treats lighting/exposure as unavailable when the lighting
confidence is `nil`, clears its subject-light metrics, and does not synthesize
a confidence value. This is an explicit current product limitation; lighting
actions remain fail-closed at this boundary.

Observer freshness uses the canonical `FeatureSourceFreshnessWindows`: subject
families resolve the window from the binding source, horizon uses `.horizon`,
lighting uses `.lighting`, and frame-global stability uses the narrowest
declared source window for capture/motion age. No observer-local 1.5-second
freshness owner remains.

Vision candidate regions are y-up. The adapter converts their rectangle through
the existing `CameraSpacePointV2.flippedVertically` M2-003 conversion before
the observer evaluates canonical coaching y-down coordinates. No second
coordinate system is introduced.

## Action mapping and signals

All mapped action IDs are covered by the focused table-driven tests:

- Subject displacement: `shift_frame_left`, `shift_frame_right`,
  `shift_frame_up`, `shift_frame_down`, `lower_camera`, `raise_camera`,
  `move_subject_left`, `move_subject_right`, `move_object_left`, and
  `move_object_right`. The observer compares canonical subject-center deltas
  and distinguishes relevant, no-op, and opposite directions.
- Scale/distance: `step_closer`, `step_back`, `move_object_forward`, and
  `move_object_back` use subject area. `move_subject_away_from_background`
  remains mapped to the scale family but is uncertain because no typed depth
  measurement exists at the production snapshot boundary.
- Horizon/rotation: `level_horizon` moves horizon-angle magnitude toward zero;
  `change_camera_angle` detects a material absolute angle change. The latter is
  directionless, so an opposite direction is not inferred.
- Light/exposure: `rotate_subject_toward_light` uses
  subject/background separation; `add_front_fill_light` uses subject luma;
  `add_background_light` uses background luma;
  `remove_background_hotspot` uses hotspot ratio; and
  `reduce_exposure`/`increase_exposure` use exposure bias. Subject-light
  actions never fall back to legacy whole-frame `meanLuma`.
- Focus: `refocus_subject` is mapped to the focus family but remains uncertain;
  `FrameFeatureSnapshot` exposes no typed focus score, timestamp, confidence,
  or provenance seam, so no synthetic focus value is advertised.
- Stability: `stabilize_camera` uses the existing stability score/inverse
  shake-level motion evidence and does not require subject identity.

Unsupported IDs are fail-closed: `remove_distracting_object`,
`reposition_prop_for_balance`, `simplify_background`,
`wait_for_background_clearance`, `keep_current_setup`, `avoid_occlusion`,
`clean_lens`, and `reduce_iso_noise` have no honest movement metric and return
`uncertain(reason: "unsupported_action")`.

Uncertainty resets the tracker's consecutive-relevant streak. Nonpositive
`requiredRelevantFrames` values are clamped to `1`; success still requires a
relevant frame observation after a prior frame and cannot result from elapsed
time. A 120-second unchanged-scale gap is explicitly classified as
`uncertain(reason: "stale_evidence")`, not as a no-op or success.

## Verification

Exact command:

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=1F708A11-8262-4E09-9F3A-46C86381911D' \
  -derivedDataPath /tmp/m2-023-provenance-root.HjIFkS/DerivedData \
  -resultBundlePath /tmp/m2-023-provenance-root.HjIFkS/result5.xcresult \
  -only-testing:shafinMultitoolTests/CameraManagerLifecycleTests \
  -only-testing:shafinMultitoolTests/UserMovementObserverTests \
  -only-testing:shafinMultitoolTests/LatestFrameEnvelopeTests \
  -only-testing:shafinMultitoolTests/LatestFrameEvidenceStoreTests \
  -only-testing:shafinMultitoolTests/AnalysisPipelineReleaseTests \
  CODE_SIGNING_ALLOWED=NO
```

The final command used `/tmp/m2-023-provenance-root.HjIFkS/result5.xcresult`, exited `0`, and
reported `** TEST SUCCEEDED **` on `Clone 1 of iPhone 17`.

Exact result summary:

```text
xcrun xcresulttool get test-results summary --path /tmp/m2-023-provenance-root.HjIFkS/result5.xcresult
passedTests: 82
failedTests: 0
skippedTests: 0
totalTestCount: 82
result: Passed
deviceName: iPhone 17
osVersion: 26.5
platform: iOS Simulator
```

The 82 focused tests across `UserMovementObserverTests`,
`LatestFrameEnvelopeTests`, `LatestFrameEvidenceStoreTests`, and
`AnalysisPipelineReleaseTests`, plus `CameraManagerLifecycleTests`, cover:

1. Every `SemanticActionType` and every technical action ID, with all mapped
   IDs assigned to the expected family and unsupported IDs rejected.
2. Relevant/no-op/opposite trajectories for every directional and signed
   scalar action, plus directionless horizon change, unavailable depth/focus,
   and stability.
3. Adapter canonical vertical conversion, selected Vision/DETR provenance,
   DETR timestamp/confidence, mixed-source rejection, and
   identity/source/region/frame gates.
4. Frame-global horizon/stability trajectories without subject binding,
   subject-dependent nil-binding rejection, and the shared
   `SubjectTrackIdentity.generation`/`AcceptedFrameEnvelope.lensGeneration`
   invariant.
5. Required orientation and lens-generation matching, snapshot/envelope capture
   matching, stale source rejection, low-confidence uncertainty, and
   uncalibrated uncertainty.
6. No whole-frame subject-light fallback, explicit nil-confidence lighting
   unavailability, canonical per-source freshness boundaries, and explicit
   focus/depth unavailable behavior.
7. Camera-motion uncertainty, uncertainty streak reset, nonpositive threshold
   clamping, reset behavior, the elapsed-time/stale-evidence invariant, and
   absolute angle change across a sign crossing while level behavior remains
   magnitude-based.
8. `LatestFrameEvidenceStore.publish` generation propagation through accepted
   and envelope snapshots, plus all declared source-window boundaries and
   fail-closed missing/unknown-source cases.
9. Exact DETR frame/generation/orientation sanitization at `Snapshot`
   construction (the sanitizer used by publish and acceptance), rejection of
   each mismatched dimension, and removal of the rejected debug fallback.
10. Production high-frame propagation of the camera capture generation and
    rejection of a delayed older-generation frame after newer-lens evidence.
11. Camera lifecycle frame-gate closure across start, stop, release, failure,
    and orientation mutation, including deterministic stop/failure races at
    the reattachment boundary without stale gate revival. Lens-switch behavior
    is covered only by source inspection in this focused run.

Verification used only the non-Pro `iPhone 17` iOS 26.5 simulator. No physical
device, iPhone 17 Pro, network service, or Computer Use was used. The result
bundle is transient build evidence and may be removed after this summary and
the execution ledger are updated. Focus/depth remain intentionally unavailable
until an existing typed production measured-evidence seam supplies real
timestamped, confidence-bearing, source-bound values. M2-024 remains the owner
that feeds consecutive accepted frames into this observer; M2-023 alone does
not establish end-to-end coaching completion. Delayed live DETR callback and
pause-local DETR provenance remain source-inspected rather than separately
injected by this focused suite.
