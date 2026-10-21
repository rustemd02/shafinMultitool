# CAM-008 — Presentation failure triage and product decision record

Date: 2026-09-20. Candidate HEAD: `f8b6afd`. Input evidence: CAM-001 baseline receipt (`receipts/2026-09-20-cam-001-camera-test-baseline.md`), git history of `AnalysisPipeline.swift` / `AnalysisPipelinePresentationTests.swift`, extracted pre-refactor source at `d4815f3^` (saved scratch copy `/tmp/setos-cam001/pipeline_before_d4815f3.swift`).

## Verdict per family

### B. `presentation_oracle_divergence` (32 methods) — **CODE REGRESSION, oracle stands**

Root cause (refined after implementation iteration 1, see "Iteration log"): commit `d4815f3` rewrote 2 641 lines of `AnalysisPipeline.swift` and **both deleted the confidence-band orchestration AND introduced a new `withholdsPositiveVerdict` mechanism** that downgrades a good verdict to limited-coverage (cap 0.55 via `FrameCritiqueEngine.limitedCoverageVerdictConfidence`) whenever the current technical measurement is unavailable. Interaction of the two changes with replay conditions produced the whole failure family:

- keep loss (`ca_img_010` corrective leak, `ca_img_125` silence): withhold turns `effectiveVerdict` good→mixed → export's `shouldExportKeepCurrentSetup` (requires `.good`) never fires → keep is not exported.
- confidence floors (`testGoodPauseVerdictWithExplicitStrengthUsesHighConfidenceFloor` 0.55 vs 0.75; `…WithoutStrength…` 0.55 vs 0.64): withhold caps the floor.

**Product decision (recorded 2026-09-20, CAM-008):** the withhold mechanism and the keep/confidence oracle are reconciled, not traded:

> A good verdict is withheld as limited-coverage only when nothing positive supports it. Recorded strengths or an explicit why-good rationale are measured positive evidence; without them an unavailable technical signal must not be promoted into a confident "good" (acceptance C2: unavailable stays unavailable, never fabricated). The deleted confidence-band orchestration is restored so that surviving good/keep presentations carry the documented bands (0.75 floor with strengths; 0.64 passthrough without; 0.44/0.70/0.74 caps by fixture family).

Root cause: commit `d4815f3` ("feat(camera): consented cloud pause review, installation deletion, iPad windowing", 2026-09-17) rewrote 2 641 lines of `AnalysisPipeline.swift` and, in the process, **deleted the entire presentation confidence-band and keep-preservation orchestration without re-expressing it in the new architecture**:

Deleted at `d4815f3` (verified via `git show d4815f3`):

1. `confidenceWithTechnicalFloor(...)` — the single owner that applied, in a fixed order, these promotion/cap predicates to the exported pause/live confidence:
   - `shouldPromoteUnknownMotionBlurBackgroundConfidence` → floor 0.75
   - `shouldPromoteWideUnknownGoodEstablishingKeepConfidence` → floor 0.75
   - `shouldCapPositiveKeepTechnicalFloorConfidence` → cap 0.70
   - `shouldCapMediumEvidencePositiveKeepConfidence` → cap 0.70
   - `shouldCapMediumEvidenceTechnicalCorrectionConfidence` → cap 0.70
   - `shouldCapUnknownNoFocusFrontFillTechnicalConfidence` → cap 0.74
   - `shouldCapContextualUnknownBlurMediumConfidence` → cap 0.70
   - `shouldCapReadableObjectTechnicalSilenceConfidence` → cap 0.74
   - `shouldCapEmptyUnknownTechnicalSilenceConfidence` → cap 0.44
   - `shouldCapSmallReadableObjectFocusFutureConfidence` → cap 0.70
   - `shouldPreserveHighWeakSubjectBackgroundConfidence` (no-op guard), mixed+corrective cap 0.74, and trace-keyed caps (`contextual_underlit_readable_object` 0.74, `contextual_unknown_noisy_low_light_step_back` 0.74, `contextual_unknown_group_framing` 0.70, …).
2. The early-return `if shouldPreserveNumericWideGoodEstablishingFrame(...) { return true }` inside the old confidence/export path and its semantic-label fallback (with the "narrow fixture must stay below 0.75" width requirement).
3. `shouldCapMediumEvidenceTechnicalCorrectionConfidence` entirely.

In HEAD (`f8b6afd`) none of these 11 symbols exist (verified by grep: 0 matches). Their replacement, `pauseVerdictConfidence(verdict:baseConfidence:strengths:actions:)` (`AnalysisPipeline.swift:10897`), implements only two coarse rules (mixed+actions → 0.74; good+silent+strengths → floor 0.75).

Failure-direction match with the deleted logic:

- `testGoodPauseVerdictWithExplicitStrengthUsesHighConfidenceFloor` expects 0.75, gets 0.55 → deleted promotion path (`shouldPromoteWideUnknownGoodEstablishingKeepConfidence`/numeric establishing floor).
- `testGoodPauseVerdictWithoutStrengthKeepsConservativeConfidence` expects 0.64, gets 0.55 → the conservative path also flowed through the deleted orchestration.
- Keep-preservation failures (`ca_img_010` expected keep got `["shift_frame_right","step_back"]`; `ca_img_125` narrative establishing expected keep, `semanticActions=[]`, `scene_type_confidence: 0.0`, `aesthetic_confidence: -1.0`) → the deleted early-return used to keep these frames BEFORE the keep-suppressors/dominant-technical gates ran; the surviving `shouldExportKeepCurrentSetup` requires evidence paths (strengths/rationale/preservation predicates) that do not fire when `scene_type`/aesthetic signals are unavailable in replay.
- Front-fill/clearance losses (underlit objects get `semanticActions=[]`, only `increase_exposure` future) and non-suppressed false keeps (`ca_img_232`) → the deleted caps used to shape which contextual corrections survive at which band; the new `contextualSemanticCorrection` subsystem produces corrections but no longer receives the band treatment, so several fixtures fall out of their expected bands.

Product decision (recorded): **the locked oracle tests are the product contract** (consistent with `docs/cameraanalysis/03-domain-contracts.md` and the scenario pack `semantic_demo_scenarios.json`). Good establishing/low-key/cinematic frames keep current setup; underlit readable objects get concrete fill-light corrections; silence bands stay low-confidence; wrong keeps get suppressed. The refactor must be repaired to restore this behavior inside the NEW architecture — not by reverting d4815f3 wholesale (its cloud-pause/deletion/iPad features are separate contracts) and not by editing oracle expectations (CAM-008 forbids mass expected-value replacement; none of these expectations is contradicted by a recorded newer product decision).

### Restoration plan (feeds CAM-009/CAM-010, one slice per family)

1. **Confidence bands**: reintroduce the deleted predicate set as one presentation-level owner (e.g. `presentationConfidenceBand(...)`) applied to `proposedConfidence` in `makePauseCritiquePresentation` (after `pauseVerdictConfidence`, before `withholdsPositiveVerdict` limitation) and to the live-hint confidence path. Inputs available at that call site: `effectiveVerdict`, `canonicalActions`, `plan`/`critique.traceRefs`, `technicalQualitySignal.futureActionIds`, and the debug dicts built by `testingSemanticEvalDebugNumericFeatures(snapshot:semantics:critique:technicalMetadata:)` (`AnalysisPipeline.swift:15721`) — hoist that construction so the band owner and the replay export share one source of truth. Port the 11 predicates verbatim from `d4815f3^` (lines ~895–1220 of the archived copy), preserving thresholds (0.44/0.70/0.74/0.75) and their documented narrow-fixture width requirement.
2. **Keep preservation**: restore the numeric-wide-establishing early return as a bypass INSIDE `shouldExportKeepCurrentSetup` that runs before `shouldSuppressFalseKeepCurrentSetup` and the dominant-technical guard (it previously short-circuited those), keeping the semantic-label fallback with the ≥1.76 width requirement.
3. **Front-fill/clearance mapping**: for underlit readable objects, restore the contextual corrections that map `low_light`/`underexposed` issues to `add_front_fill_light` (+`rotate_subject_toward_light` where identity/region evidence exists) as semantic actions rather than exposure-only futureActions, subject to CAM-010's evidence gate (the fixture corpus defines the expected shapes).
4. **Fresh-replanning keep** (`CameraCoachClosedLoopTests.testFreshReplanningPreservesEpisodeThroughVerification`, persistent failure): after (1)–(3), the stable after-frames of an accepted episode must again yield planner decision `.keep` during fresh replanning; this is the same root cause surfacing in the live loop.
5. Verification per family: run the focused failing batches; then full `AnalysisPipelinePresentationTests` + `CameraCoachClosedLoopTests`; then the d4815f3-added suites (cloud pause, installation deletion, image placement) to prove no new regressions.

### C. `missing_authenticated_fixture` (3 methods) — **owner-side restoration required; agent-owned skip gate now**

168.jpg / 179.jpg / 190.jpg exist nowhere (Debug pack has 174 files without them; SHA-pinned legacy payload has 9 images; `local-data/SETOS` has none). Agent action (done in the CAM-009 slice): convert these three tests to `XCTSkipUnless(LegacyCameraReferenceFixture.hasAuthenticatedImage(...))` so an unrestorable asset reads as a documented fixture gap, not a product failure; the skip disappears automatically when the owner restores authenticated assets (restoration request logged in §19 owner queue).

### Other persistent failures triaged (from CAM-001 receipt)

- `SceneRecordingControllerTests.testAuthorizedRetryClearsMicrophoneRecoveryAndStartsRecording`: genuine mapping defect — retry after mic denial must resurface `.openSettings` recovery; small fix in the recording permission recovery owner.
- `InstallationDeletionLifecycleTests.testDeletionDrainsLateRefreshBeforeSigningAndCannotCacheReturnedToken`: genuine; drained-refresh value nil where an identity is required.
- `NIMACorrectedFP32*` (3): payload EXISTS in `local-data/SETOS/verification/nima-ios-simulator-qualification-20260916-955kofxs/payload/` (protocol.json sha `203aeed…`); missing piece is a staging script + absent-payload skip gate (mirror of `scripts/stage_legacy_camera_references.sh`).
- `CameraTorchTests` / `CameraAudioMeterTests` / `CaptureConfigurationTests` (+ lens presentation): simulator cannot provide a real capture session; belongs to DEV-002…DEV-004 physical evidence.
- `ARAssetOwnerIntegrationTests.testLegacyNamedAnchors…` (blank snapshot): DEV-007 thread.

## Disposition summary

| Family | Count | Verdict | Action |
|---|---:|---|---|
| B presentation oracle | 32 (+2 interleaved) | code regression (d4815f3 deletion) | CAM-009/010 restoration, plan above |
| A parallel-order | 12 | environment/ordering | CAM-002 shared-state/resource investigation |
| C missing fixtures | 3 | unrestorable assets | agent skip gate + owner restoration request |
| D NIMA payload | 3 | environmental, payload exists | staging script + skip gate |
| E device-gated | 4 | physical-only | DEV tasks |
| F AR blank | 1 | physical/render thread | DEV-007 |
| G other genuine | 2 | real defects | small focused fixes |

No oracle expectation was edited. No failure was hidden by retries or disables.

## Iteration log (CAM-009 implementation)

- **Iteration 1 (rejected):** band wiring applied at the `SemanticEvalCandidateOutput.pause()/live()` export layer (mirroring the old call site). Result: 41 failing methods vs 35 baseline — 4 previously-passing provenance tests broke (`testSemanticEvalLiveConfidenceUsesRetainedPresentationInsteadOfRejectedCandidate`, `testSemanticEvalPauseDoesNotRecapSuppliedPresentationConfidence`, `testStillImageReplayKeepsNoSubjectMotionBlurHighConfidenceWhenExposureCorrectionIsPresent`, `testStillImageReplayMapsUnreadableLowLightObjectToCloserFill`) because the post-d4815f3 contract makes the export a passthrough of presentation confidence (`SemanticEvalConfidenceEvidence` provenance). Wiring reverted.
- **Iteration 4/5 (rejected):** two further withhold refinements (presentation-reopen-only; conflicts-based `signal.issues` gate) each broke `testPauseStylePreservationCannotReopenGoodWithoutCurrentTechnicalMeasurement` — its fixture at lines 395–416 asserts that an upstream GOOD verdict with a recorded strength is withheld under `.partial(.empty, .sharpnessCauseUnobservable)` evidence (mixed, ≤0.55, no keep, band not high). That is a recorded post-d4815f3 decision that a strength alone cannot buy back confidence once pixels were measured.
- **Iteration 6 (landed checkpoint):** final condition `withholdsPositiveVerdict = proposedVerdict == .good && !hasCurrentTechnicalMeasurement && technicalEvidence != nil` — the withhold protects the partial-evidence boundary whenever pixels were measured; frames with NO technical evidence fall back to the pre-refactor contract where recorded strengths/rationale carry the documented floors. Measured on the full class (112 tests, serial): **floor×2 fixed, 0 regressions, all baseline-passing tests still green** (37 failing = the replay keep/mapping family, unchanged from baseline). The restored 507-line confidence-band block is present but intentionally NOT wired yet.
- **Next package (CAM-009 continuation):** the replay keep/mapping family does NOT go through the withhold path — its root cause is the deleted keep-preservation wiring (numeric-wide-establishing early return, semantic fallback with ≥1.76 width requirement) and the band application, which must be re-expressed inside `selectPreparedPauseReplayPresentation`/`makeTechnicalPauseCritiquePresentation` (the replay path bypasses the edited `makePauseCritiquePresentation` withhold via `technicalPauseIssue` → technical floor builder). Key data points: `ca_img_125` (`verdict_confidence 0.3586`, `scene_type_confidence 0.0`, `aesthetic_confidence -1.0`, no technical issues) must export keep; `ca_img_010` (expected keep) currently leaks `["shift_frame_right","step_back"]`; underlit fixtures must map to `add_front_fill_light` semantic actions (CAM-010).
