# 37 — Pause advice admission audit (2026-09-17)

Scope: why `shafinMultitoolTests/AnalysisPipelinePresentationTests` reports **44 failing
methods out of 110** on the committed snapshot, and which of those failures are product
defects versus oracles that predate the current admission policy.

Source: clean working tree at `d37ca42` (`store`), Debug configuration,
`xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool`,
destination `iOS Simulator id=79E82949-E735-45CC-9092-DE74200971E7`,
`-parallel-testing-enabled NO`.

## 1. Measured baseline

| Run | Result |
| --- | --- |
| Full class | 110 executed, 44 failed, 204 assertion failures, 5 unreadable references |
| Earlier receipts | 6–19 *selected* methods only; the full class had not been characterized |

The five unreadable references are `168.jpg`, `179.jpg`, `189.jpg`, `190.jpg`, `202.jpg`.
Four methods (`testStillImageReplayWithholdsUnownedFillWhileKeepingCameraOcclusionAdvice`,
`…MapsSyntheticHotspotToCorrectiveSemanticActions`, `…SuppressesPreservationForReadableSyntheticSmallSubject`,
`…MapsSyntheticCrookedFramesToLevelHorizon`) cannot run at all without them.

## 2. Mechanisms

Numbers below come from a temporary read-only dump of `pauseRow` for 23 named frames
(the dump test was deleted after use; the rows it printed are quoted here).

### M1 — Most frames raise no semantic issue, so the semantic channel is empty

For 15 of the 23 dumped frames `debugIssueTypes` is empty while `debugNumericFeatures`
shows a technical defect (for example `ca_img_007`: `technical_max_severity 1.00`,
`exposure_bias -2.23`, and no issue). The planner has an explicit branch for this state:

```swift
// SemanticTipPlanner.plan
} else if input.critique.issues.isEmpty {
    rankedCandidates = []          // "no_supported_correction_for_non_good_frame"
}
```

The app then answers with the technical exposure note only. This is the single largest
source of `semanticActions=[]` in the failures.

### M2 — Limited scene coverage demotes the verdict and caps confidence at 0.55

`FrameCritiqueEngine.analyze` admits a positive verdict only when
`hasCurrentTechnicalMeasurement && hasPositiveSemanticCoverage`; otherwise it demotes
`good → mixed` and caps confidence at `degradedVerdictConfidenceCap = 0.55`.
`hasPositiveSemanticCoverage` also refuses frames carrying `lowSceneConfidence`, which
`AnalysisPipeline` sets when horizon, Vision **and** DETR source confidences are all
below 0.20.

Thirteen of the dumped frames report confidence exactly `0.55` — the documented ceiling,
not a measured probability. Tests that assert `confidence >= 0.75` on those frames are
asserting past the cap.

### M3 — The lighting mapping is gated twice and is effectively unreachable today

Lighting actions (`addFrontFillLight`, `addBackgroundLight`) require
`PauseSceneControlFacts.lighting == .allowed` for the exact frame
(`PauseSceneControlFacts.permits`). Even with all three categories granted, a probe over
12 frames produced **no semantic action at all** — including frames that do raise
`backlight_hides_subject` (`022`, `224`, `180`, `188`, `204`). The lighting tips are also
dropped when the driving issue's confidence is below 0.45
(`SemanticTipPlanner.shouldInclude`).

**This disproved the first hypothesis of this audit**: the pause scene-control gate is not
what removes the expected actions, so re-granting facts in the replay path does not
restore them. The corresponding replay seam and the test edits built on that hypothesis
were reverted.

### M4 — A technical issue displaces the semantic presentation

`selectPreparedPauseReplayPresentation` tries `technicalPauseIssue(...)` first and returns
a technical-only presentation when the eligible technical issue survives the preservation
guards and no non-keep semantic tip exists. That is why rows can be `shown` and still
carry `semanticActions=[]`.

### M5 — `keep_current_setup` coexists with an exported correction

Four frames report `keep_current_setup` **and** non-empty `futureActions`:

| Frame | Verdict | keep | futureActions | Current label set |
| --- | --- | --- | --- | --- |
| `220` | good | yes | `reduce_exposure` | `forbidden: keep_current_setup` |
| `232` | good | yes | `increase_exposure` | `forbidden: keep_current_setup` |
| `181` | good | yes | `increase_exposure`, `stabilize_camera` | test expects technical-only |
| `184` | good | yes | `increase_exposure` | legacy oracle expects `step_back` |

The row's `futureActions` is a union built by `testingSemanticEvalFutureActions` from the
resolved technical signal **plus** motion state, `exposureBiasHint` and legacy
suggestions, while the critique verdict only sees the resolved signal. For these four
frames `technical_issue_count` is 0, so the critique is right that nothing was measured —
and the exported correction comes from the wider union.

**Resolved by owner decision 2026-09-17.** The owner confirmed that a confirmation and a
technical note may appear together, and that the note must be phrased as an optional
improvement ("everything is fine, you could also do this") rather than as a defect. The
implemented boundary is the one the code already used for admission:

- `PauseCritiquePresentation.optionalImprovement` (`PauseOptionalImprovement`) carries at
  most one non-dominant measured improvement, attached only when the presentation
  confirms the frame (verdict `good`, positive semantic coverage, current measurement).
- A **dominant** measured defect is not an improvement: `dominantTechnicalQualityIssue`
  keeps precedence, the frame is not confirmed and the corrective path is unchanged.
- `CameraReviewPresentation` exposes it as a `CameraReviewFinding` of kind `improvement`
  with dedicated optional wording (`set.camera.optional.*` in the string catalog, RU/EN),
  so the user reads an addition, not a fault. The corrective `set.camera.technical.*`
  wording keeps its defect role.
- The eval row gains an optional `optional_improvement` field, absent in historical rows.
- Verified by `testStillImageReplayConfirmsFrameWithOptionalImprovement` (`050`: keep plus
  `increase_exposure`, no issue rows) and
  `testStillImageReplayWithholdsOptionalImprovementUnderDominantDefect` (`006`, `130`: no
  note, no confirmation). The localization gate passes with 689 compiled keys in both
  locales.
- Still open for `220`/`232`: those labels forbid keep for a *perception* reason (large
  synthetic overlays the current features do not measure), which this decision does not
  address.

### M6 — The shipped demo pack encodes pre-policy expectations

`docs/cameraanalysis/demo/semantic_demo_scenarios.json` is bundled into the app
(`scripts/copy_debug_device_benchmark_resources.sh`) and expects light and object
commands: `demo_object_balance_move_back` requires `rotate_subject_toward_light`,
`add_front_fill_light`, `move_object_back`; `demo_step_closer_and_fill` requires
`add_front_fill_light`. `demo_keep_wide_establishing` (`010.jpg`) requires
`keep_current_setup` with `minimum_pause_confidence 0.75` while the app currently answers
`shift_frame_right, step_back`. The demo content therefore describes advice the current
admission policy does not produce.

## 3. Recovered references are device-local and five are unrecoverable

The five recovered legacy references are staged in the simulator app container
(`Library/Caches/SETOSLegacyCameraReferences/<manifest SHA>/`), not in the repository, and
are bound to the SHA-pinned manifest `ed652addfd2c661060bb6dfbcab8c9c7f7be1d02a50c1b9a8e518068153e9894`.
Erasing that simulator, or installing the app into a fresh container without re-staging,
makes those methods fail with a file error rather than a behavior mismatch.

The remaining five references (`168`, `179`, `189`, `190`, `202`) cannot be reproduced from
anything on this machine. The recovery receipt already records why
(`legacy-reference-recovery-20260917-p8m2af3s/recovery-receipt.json`, `missing_before`):

| Reference | Recorded reason | What it means here |
| --- | --- | --- |
| `179`, `189`, `190`, `202` | `AUTHENTICATED_PARENT_NOT_FOUND` | They are deterministic outputs of `synthetic_bad_variants_178_207.jsonl`, but the generator needs the parent stills (`129`, `139`, `140`, `152`). Those parents belong to the 15 `appletv_good` records dropped from the current label set, and their bytes are absent from the pack, the repository and `local-data`. |
| `168` | `IMAGEGEN_DERIVATIVE_BYTES_NOT_FOUND_NO_REGEN` | It came from the imagegen bucket and has no recorded recipe. |

So regeneration is **not** an available path, contrary to the first reading of the variants
manifest: a recorded seed and parameters reproduce bytes only together with the parent
pixels. Restoring these four methods needs the published Apple TV press stills to be
re-acquired from the recorded `parent_source_page_url` values, which is a network operation
with its own rights position, or the methods stay blocked.

## 4. Open decisions and next work

Engineering work that does not need an owner decision:

1. Decide how the four parent-dependent references are handled: re-acquire the recorded
   press stills (network, rights position) or retire the four blocked methods with the
   recorded `AUTHENTICATED_PARENT_NOT_FOUND` reason as their evidence.
2. Decide per failing method whether the oracle encodes a current product promise. The
   candidates that are clearly pre-policy are the front-fill family, `023`/`039` (keep on a
   deliberately low-key silhouette), and `184`/`183`/`182`/`206` (withdrawn
   `synthetic_bad_paired_apple_tv_press` bucket, dropped by the 2026-06-05 audit as
   "stylized cinematic frames and subtle synthetic artifacts").
3. Record the retracted hypothesis (M3) so the same experiment is not repeated.
4. Open a defect ticket for `220`/`232`: a frame with large synthetic overlays is answered
   `keep`. The overlays are not measured by any current feature, so this is a perception
   gap, not an admission-setting.
5. `DecisionTracePresentationTests.testPauseTraceConnectsVerdictEvidenceActionsAndLimitations`
   fails on the committed snapshot too (verified by re-running it with this session's
   changes stashed: identical assertion text at `DecisionTracePresentationTests.swift:94`).
   It expects the older `simplify_background` wording and is outside the class measured in
   §1, so the wider suite has more red tests than the 44 counted here.

Owner decisions, because they change the product promise rather than its implementation:

- ~~May the app confirm `keep_current_setup` while the same screen shows a technical
  correction?~~ **Answered 2026-09-17:** yes, provided the correction is phrased as an
  optional improvement. Implemented in M5.
- Should the bundled demo scenarios declare scene control explicitly, or be rewritten to
  camera-only actions (M6)?
- Is the semantic lighting advice path intended to stay reachable only after the user
  answers the scene-control sheet (M3), or should the pause path raise lighting issues
  without that answer?

## 5. What this audit does not claim

It does not claim the app's advice is correct or incorrect for any of these frames, does
not re-label any frame, and does not change a threshold, a label or a policy. It reports
measured row values, the code paths that produced them, and the two hypotheses that were
tested and rejected.
