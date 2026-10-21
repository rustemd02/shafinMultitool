# REL-001 — Canonical test command matrix v1

Date: 2026-09-22. Candidate baseline: HEAD `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee` (branch `store`) **plus the uncommitted CAM-009 deterministic-KEEP diff** (`AnalysisPipeline.swift`, `AnalysisPipelinePresentationTests.swift`, `CameraCoachClosedLoopTests.swift`, `CameraCloudPauseIntegrationTests.swift` — see `receipts/2026-09-22-cam-009-deterministic-keep-restoration.md`).

Authority: tracker §7 («Ограничение работы над эвристиками») and tracker row REL-001. This document **classifies** existing tests and commands; it does not modify, delete, skip-create or weaken any test, scheme, or assertion. Nothing here removes a failure from the release gate: historical heuristic perceptual assertions are routed to ML evaluation as diagnostic evidence (§7), and every other failure — including any failure not named in this matrix — stays release-gated until separately classified.

Inputs (not re-run, per task boundary): CAM-001 baseline receipt (2 358 tests; 48 persistent genuine categories B–G; 12 order-dependent category A), CAM-008 triage, CAM-009 focused verification (runtime/safety 8/8 green; 3 historical perceptual methods red as recorded diagnostic evidence).

---

## 1. Factual test inventory (grep-derived, 2026-09-22)

| Fact | Value | Evidence |
|---|---|---|
| Project / schemes | `shafinMultitool.xcodeproj` (+ `.xcworkspace` with Pods); one shared scheme `shafinMultitool` | `xcodebuild -list` |
| Targets | `shafinMultitool` (app), `shafinMultitoolTests` (unit, app-hosted `TEST_HOST`), `shafinMultitoolUITests` (UI, `TEST_TARGET_NAME`) | `xcodebuild -list`; scheme TestAction lists both `.xctest` testables with `parallelizable = "YES"`, `shouldAutocreateTestPlan = "YES"` |
| Unit test files / classes | 183 `.swift` files / **196 distinct `XCTestCase` classes** | `grep -rhoE '(final )?class [A-Za-z0-9_]+ *: *XCTestCase' shafinMultitoolTests` → 196 unique names |
| UI test files / classes | 8 `.swift` files / **8 classes** (`CameraCoachEntryFlowUITests`, `CameraCoachProductionUITests`, `IPadWindowingModeDiagnosticTests`, `SETDesignSystemGalleryUITests`, `SETGeneratorProductionUITests`, `SETLibraryProductionUITests`, `SETPrivacyUITests`, `CameraCoachLaunchUITests` in `UITests.swift`) | same grep on `shafinMultitoolUITests` |
| Declared test methods | **2 299 unit + 62 UI = 2 361** | `grep -rhoE 'func test[A-Za-z0-9_]+\('` per target |
| CAM-001 executed | 2 358 (delta vs declared = known skip-gated opt-in lanes, e.g. env-gated semantic-eval export, `DeviceBenchmarkUITests` unconditional skip) | `receipts/2026-09-20-cam-001-camera-test-baseline.md` |
| Multi-class files | `AnalysisPipelinePresentationTests.swift` → `AnalysisPipelinePauseSnapshotTests` (3 methods), `AnalysisPipelinePresentationTests` (112), `SemanticEvalStillImageBatchReplayTests` (2). `CameraAnalysisDomainContractsTests.swift` → 9 classes, 115 methods total | line-range grep of class decls and `func test` |
| Pinned simulator destination | `id=1F680A42-CEB3-43E8-9CED-52F874962A62` = iPhone 17e, iOS 26.5 (same as CAM-001/CAM-009) | `xcrun simctl list devices` |
| Canonical batch runner | `scripts/run_swift_unit_tests.sh` (disk-guarded, batches the unit target by class via `-only-testing`, re-stages legacy references per batch; rc 0/1/2/3 documented in-script) | file exists; header comment |

Note: the default scheme setting runs both bundles with parallel clones enabled. **Category A of CAM-001 (12 order-dependent methods) is an artifact of that mode.** All blocking lanes below therefore pin `-parallel-testing-enabled NO` (serial), exactly as CAM-001 isolation pass 2 and CAM-009 did. Retries, disables, or re-enabling parallelism to green a lane are forbidden.

---

## 2. Release-relevance categories

| Category | Meaning | Gate effect |
|---|---|---|
| `blocking` | Runtime/safety (fail-closed gates), ActionVerifier/planner контракты, model contract validators, privacy manifest/bundle scripts, closed CAM-004…007/009 runtime controls, product acceptance checks. Must be green on the candidate. | Red (or not executed) ⇒ release blocked. |
| `blocking — known failure` | Blocking assertion currently red with a recorded, owned cause (tracked by a named tracker task). | Stays in the lane. Red ⇒ release blocked until the owning task closes it. Never removed or weakened. |
| `diagnostic` | Historical heuristic perceptual replay assertions only (§7), routed to ML-006/010; research-model qualification payload (NIMA, §3.2 research-only). Assertions stay intact; failures are recorded ML-eval targets. | Not a release gate; must not be claimed green; new failures outside the recorded set are treated as unknown ⇒ release-gated. |
| `device-gated` | Asserts physical capture-device behavior a simulator cannot provide. Explicitly **not** a diagnostic false pass: excluded from simulator lanes by name, replaced by physical DEV evidence. | Release blocked until the matching DEV receipt exists. |
| `fixture gap — owner pending` | Requires missing owner-side authenticated assets (168/179/190.jpg); owner decision pending (§19 п.7: restore or explicit acceptance exclusion). | Release blocked either way until resolved. |
| `opt-in lane` | Env/config-gated by design (live model smoke, benchmark harness, semantic-eval export). Skip when unconfigured is the designed behavior; a configured lane must report skips separately. | Not a silent pass; lane result reported with skip count. |
| `order-artifact` | Category A: passes in isolation; fails only in shared parallel processes. | Run serial; keep in blocking lanes; CAM-002 owns the shared-state root cause. |

**Invariants (apply to every lane):**

1. **Zero-test run = failure.** A lane that executes 0 test cases, aborts before execution (disk guard rc=3, spawn failure, build failure), or reports "0 passed, 0 failed" is a FAILED lane, never a pass.
2. **Unknown failure stays release-gated.** Any failure not present in the classification table (§4) keeps the release blocked until a new bounded task classifies it.
3. No assertion is deleted, commented out, retried into green, or skipped into green by this matrix. `-skip-testing` appears exactly once below (M-UI legacy shell suite routed to diagnostic) and names a whole legacy file whose false-green risk is already documented in `docs/implementation/audits/test-topology.md` (CC-005) — it removes no safety or runtime assertion.
4. Skips are reported per lane; an unexpected skip in a blocking lane is treated as a failure of the lane, not a pass.

---

## 3. Canonical commands

Common prefix (used by every `xcodebuild test` lane):

```bash
DST='id=1F680A42-CEB3-43E8-9CED-52F874962A62'   # iPhone 17e, iOS 26.5 (CAM-001/CAM-009 pinned)
DD=/private/tmp/setos-rel001-dd
```

### M0 — Smoke, blocking core (≈133 tests + 1 script; minutes)

The minimal green set that proves the closed-loop runtime/safety spine: safety gate, keep/false-KEEP controls, verifier, planner, and the CAM-009 runtime/safety selectors. CAM-009 verified the 8-selector core green (8 tests, 0 failures) on the current diff.

```bash
xcodebuild test \
  -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -sdk iphonesimulator -destination "$DST" -derivedDataPath "$DD" \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:shafinMultitoolTests/CameraAdviceSafetyGateTests \
  -only-testing:shafinMultitoolTests/GoodFramePreservationPolicyTests \
  -only-testing:shafinMultitoolTests/ActionVerifierTests \
  -only-testing:shafinMultitoolTests/UserMovementObserverTests \
  -only-testing:shafinMultitoolTests/SemanticTipPlannerTests \
  -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testPauseStylePreservationCannotReopenGoodWithoutCurrentTechnicalMeasurement \
  -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplaySuppressesFalseKeepForBadTechnicalFrames \
  -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayPreservesLowKeyMoodKeepDespiteTechnicalFuture \
  -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayPreservesReadableObjectInsertDespiteWindowHotspot \
  -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayDoesNotOvercorrectCinematicGoodObjectInsertFrames \
  -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testGoodPauseVerdictWithExplicitStrengthUsesHighConfidenceFloor \
  -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testGoodPauseVerdictWithoutStrengthKeepsConservativeConfidence \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testFreshReplanningPreservesEpisodeThroughVerification \
  test
scripts/validate_privacy_manifest.sh
```

### M1 — Camera Coach runtime batch (blocking; ≈203 tests)

M0 classes plus the full closed-loop, pause-snapshot, release-policy and calibration classes.

```bash
xcodebuild test …common… \
  -only-testing:shafinMultitoolTests/CameraAdviceSafetyGateTests \
  -only-testing:shafinMultitoolTests/GoodFramePreservationPolicyTests \
  -only-testing:shafinMultitoolTests/ActionVerifierTests \
  -only-testing:shafinMultitoolTests/UserMovementObserverTests \
  -only-testing:shafinMultitoolTests/SemanticTipPlannerTests \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests \
  -only-testing:shafinMultitoolTests/AnalysisPipelinePauseSnapshotTests \
  -only-testing:shafinMultitoolTests/AnalysisPipelineReleaseTests \
  -only-testing:shafinMultitoolTests/CameraConfidenceCalibratorTests \
  -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testPauseStylePreservationCannotReopenGoodWithoutCurrentTechnicalMeasurement \
  -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplaySuppressesFalseKeepForBadTechnicalFrames \
  -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayPreservesLowKeyMoodKeepDespiteTechnicalFuture \
  -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayPreservesReadableObjectInsertDespiteWindowHotspot \
  -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayDoesNotOvercorrectCinematicGoodObjectInsertFrames \
  -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testGoodPauseVerdictWithExplicitStrengthUsesHighConfidenceFloor \
  -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testGoodPauseVerdictWithoutStrengthKeepsConservativeConfidence \
  test
```

Expected on current baseline: green for the class lanes; the CAM-009 selector set green (8/8 recorded). Any red here = release-gated (known or unknown per §4).

### M2 — Verifier batch (blocking; 67 tests)

Exact mask used and passed by CAM-004 (28 + 39 methods, 0 failures):

```bash
xcodebuild test …common… \
  -only-testing:shafinMultitoolTests/ActionVerifierTests \
  -only-testing:shafinMultitoolTests/UserMovementObserverTests \
  test
```

### M3 — Planner batch (blocking; 116 tests)

```bash
xcodebuild test …common… \
  -only-testing:shafinMultitoolTests/SemanticTipPlannerTests \
  -only-testing:shafinMultitoolTests/CameraBoundedActionPlannerTests \
  -only-testing:shafinMultitoolTests/AdviceStabilizerTests \
  -only-testing:shafinMultitoolTests/SemanticDirectionBehaviorTests \
  -only-testing:shafinMultitoolTests/FrameCritiqueEngineTests \
  test
```

### M4 — Contract / model-contract / privacy batch (blocking; 216 tests + 2 validators + privacy script)

```bash
xcodebuild test …common… \
  -only-testing:shafinMultitoolTests/CameraAnalysisV3ContractsTests \
  -only-testing:shafinMultitoolTests/CameraCoachContractV2Tests \
  -only-testing:shafinMultitoolTests/CameraCoachDraftV3ProposalIngressTests \
  -only-testing:shafinMultitoolTests/SubjectResolutionContractsTests \
  -only-testing:shafinMultitoolTests/SubjectIdentityRegistryTests \
  -only-testing:shafinMultitoolTests/DecisionTraceFixtureContractTests \
  -only-testing:shafinMultitoolTests/SemanticEvalModelExecutionMetadataTests \
  -only-testing:shafinMultitoolTests/CameraAnalysisDomainContractsTests \
  -only-testing:shafinMultitoolTests/NeuralEvidenceDomainContractTests \
  -only-testing:shafinMultitoolTests/SemanticTipContractTests \
  -only-testing:shafinMultitoolTests/VLMVisualEvidenceContractTests \
  -only-testing:shafinMultitoolTests/CameraAnalysisExplainabilityContractTests \
  -only-testing:shafinMultitoolTests/FeatureSnapshotAggregatorTests \
  -only-testing:shafinMultitoolTests/PipelineFeatureSnapshotAdapterTests \
  -only-testing:shafinMultitoolTests/SuggestionEngineTests \
  -only-testing:shafinMultitoolTests/SceneSemanticsAnalyzerTests \
  test

python3 ml/camera_coach/contracts/validate_camera_release_label.py
python3 ml/camera_coach/contracts/validate_camera_release_capability_mapping.py
scripts/validate_privacy_manifest.sh
```

(The last nine `-only-testing` entries are the nine classes inside `CameraAnalysisDomainContractsTests.swift`; class-level masks are required because the file is multi-class.)

### M5 — Full unit batch, blocking interpretation (196 classes / 2 299 methods)

Disk-guarded canonical runner (extends the existing owner; do not invent a parallel one). It re-stages legacy references per batch; stage the NIMA payload first if the D-family should run for real:

```bash
scripts/stage_nima_qualification.sh --udid "${UDID}" || true   # optional; D-family lane
scripts/run_swift_unit_tests.sh --udid 1F680A42-CEB3-43E8-9CED-52F874962A62
```

Interpretation rule (this is the release-gate rule, not a filter): every failure must be either (a) in the §4 classification table — accepted as the recorded diagnostic/device-gated/fixture-gap set — or (b) **unknown ⇒ release blocked** until classified. rc=1 with only documented failures = "known-red baseline"; rc=3 (disk abort) or 0 executed tests = lane FAILURE; rc=0 = full green. The known-red expectation on the current baseline is exactly the §4 set: part of family B (diagnostic), C (fixture gap), D (if unstaged), E (device-gated), F, G (known blockers).

### M6 — Diagnostic replay batch (diagnostic; NOT a release gate)

Runs the historical heuristic perceptual assertions with their assertions intact; red is the recorded, expected state on the current diff (CAM-009: 3 methods / 8 assertions). Purpose: (1) preserve the diagnostic evidence for ML-006/010, (2) detect new regressions — any failure in this lane **outside** the recorded set is unknown ⇒ release-gated.

```bash
xcodebuild test …common… \
  -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests \
  -only-testing:shafinMultitoolTests/SemanticEvalStillImageBatchReplayTests \
  -only-testing:shafinMultitoolTests/NIMACorrectedFP32SimulatorQualificationTests \
  test
```

Recorded diagnostic set (routed ML-006/010 per §7/CAM-009; do not claim green, do not weaken):

- `AnalysisPipelinePresentationTests/testStillImageReplayPreservesCinematicEstablishingDespiteTechnicalFuture`
- `AnalysisPipelinePresentationTests/testStillImageReplayPreservesNarrativeEstablishingFramesWithKeepCurrentSetup`
- `AnalysisPipelinePresentationTests/testStillImageReplayPromotesWideUnknownGoodEstablishingConfidence`
- remaining replay keep/mapping members of family B as measured by this lane (CAM-008 recorded 37 failing methods pre-CAM-009; the exact current split is established by running M6, not by this document)
- `NIMACorrectedFP32SimulatorQualificationTests` (3 methods) — research-only Stage-2 qualification; runs only with the staged SHA-pinned payload (`scripts/stage_nima_qualification.sh`); otherwise the absent-payload hard-throw is the documented D-classification, not a product failure.
- `SemanticEvalStillImageBatchReplayTests/testExportSemanticEvalCandidateOutputsFromStillImages` — env-gated opt-in export (skip by design when unconfigured; report skips).

### M7 — Device-gated lane (excluded from simulator gates by name)

These assert physical capture-device behavior; a simulator cannot satisfy them, so they are **named exclusions with a physical-evidence replacement**, not passes and not diagnostics:

- `CameraTorchTests/testTorchStateResetsOnRelease` → DEV-004
- `CameraAudioMeterTests/testMeterClearsOnRelease` → DEV-003/004
- `CaptureConfigurationTests/testUIStateReadsBackFromDeviceAfterStart` → DEV-002/004
- `CameraViewModelLensSwitchTests/testReleaseResetsLensPresentationAndFencesLateCompletion` → DEV-004
- `IPadWindowingModeDiagnosticTests/testInspectIPadMultitaskingControls` (UI bundle; requires explicit iPad destination) → DEV-011 / GOV-003 iPad contract

Replacement evidence: physical receipts of DEV-002…004, DEV-011. Release stays blocked on these until the DEV receipts exist.

Opt-in physical/config lanes (same rule): `DeviceBenchmarkHarnessTests` (device benchmark config), `SceneV8PipelineTests/testLiveLocalModelSmokeCases` and `testLiveLocalModelDatasetSampledCases` (`SG_*` env), `DeviceBenchmarkUITests` (unconditional skip placeholder — never counted as coverage).

### M-UI — UI bundle lane (blocking subset + one diagnostic legacy file; 62 methods / 8 classes)

```bash
xcodebuild test …common… \
  -only-testing:shafinMultitoolUITests/CameraCoachEntryFlowUITests \
  -only-testing:shafinMultitoolUITests/CameraCoachProductionUITests \
  -only-testing:shafinMultitoolUITests/SETGeneratorProductionUITests \
  -only-testing:shafinMultitoolUITests/SETLibraryProductionUITests \
  -only-testing:shafinMultitoolUITests/SETPrivacyUITests \
  -only-testing:shafinMultitoolUITests/SETDesignSystemGalleryUITests \
  -skip-testing:shafinMultitoolUITests/CameraCoachLaunchUITests \
  test
```

- Blocking subset (54 methods): production journeys incl. privacy UI and the Camera Coach production runtime paths (the latter contains three CAM-001 category-A methods — run serial; they pass in isolation).
- `-skip-testing:shafinMultitoolUITests/CameraCoachLaunchUITests` (file `UITests.swift`, 7 methods): legacy shell automation with documented false-green risk (CC-005: guarded no-op paths, commented assertions). Diagnostic until hardened by the UI-task chain (UI-001…UI-008); it grants no coverage credit and asserts no safety/runtime contract, so this skip removes nothing from the gate.
- `IPadWindowingModeDiagnosticTests` → M7 (iPad destination required).

---

## 4. Classification of the known CAM-001 failures

CAM-001: 48 persistent genuine methods (categories B–G) + 12 order-dependent (A). Per-category relevance, cause and replacement:

| Cat | Methods | Assertion under test | Cause (CAM-001/008/009) | Release relevance | Replacement |
|---|---:|---|---|---|---|
| B — runtime/safety controls subset | 8 verified green (CAM-009); remainder of class per M6 | structured-availability gate, partial/unavailable boundary, false-KEEP suppression (ca090/ca232), low-key/object KEEP owners, confidence guards, closed-loop replanning KEEP | fixed by CAM-009 bounded diff | **blocking** (green on current diff) | — |
| B — historical perceptual replay | 3 confirmed red (CAM-009 diagnostic extension: 3 methods / 8 assertions); family remainder measured by M6 | cinematic/narrative/wide-establishing KEEP projections and confidence bands on `ca_img_125/127/132/010` | out-of-scope replay-only heuristics removed by CAM-009 per §7; heuristics restoration is POST-007, excluded from CAM-009/010 | **diagnostic** (assertions intact) | perceptual accuracy → **ML-006** per-head eval incl. good-frame false positives; deterministic-vs-model choice → **ML-010** |
| B — front-fill/clearance mapping | part of family B | underlit readable objects must yield `add_front_fill_light` (+ light-rotation where evidence exists) | lighting mapping intentionally NOT hand-restored; goes through admitted model path | **diagnostic until CAM-010**, then **blocking** via CAM-010/ML integration | **CAM-010** (existing gates) + **ML-006** |
| C — missing authenticated fixtures | 3 | replay behavior on `179.jpg`, `190.jpg`, `168.jpg` | assets absent everywhere (Debug pack 174 files, SHA-pinned 9-image payload, `local-data/SETOS`); loader hard-throws; no skip gate present in current tree (CAM-008 planned one — not landed; recorded as gap) | **fixture gap — owner pending** (§19 п.7: restore or explicit acceptance exclusion); NOT diagnostic by default | if excluded: equivalent cases covered by **ML-006** eval on restored/owned assets |
| D — NIMA qualification payload | 3 | FP32 simulator qualification against SHA-pinned NIMA payload | payload exists in `local-data/SETOS/verification/…` but must be staged per app container; absent payload hard-throws | **diagnostic** (research-only Stage-2, §3.2; not the production contract) | research evidence for **ML-006/010** comparability; run via `scripts/stage_nima_qualification.sh` |
| E — device-gated capture | 4 | torch reset, audio-meter clear, capture-session readback, lens-release fencing | require real capture hardware; simulator cannot provide | **device-gated** (named exclusion, never a pass) | DEV-002…004 physical receipts |
| F — AR blank snapshot | 1 | legacy named anchors rebuild assets (`fraction=0.0` blank render) | render/root-cause thread, open | **blocking — known failure** (tracked) | **DEV-007** root cause + physical AR evidence |
| G — genuine defects | 2 | mic-denial retry must resurface `.openSettings`; deletion must drain late refresh before signing | small mapping/lifecycle defects, unfixed | **blocking — known failures** (tracked) | fix scope owned by **REL-002** (and DEV/SEC owners for lifecycle); release blocked until green |
| A — order-dependent | 12 | capture-path publishing, pseudo-UI runtime answers, lens-switch owner reset, committed pause, iPad diagnostic | shared parallel-process state/resource contention (BNNS/CoreML compile failures in logs) | **blocking, serial mode** (all pass in isolation; CAM-002 owns shared-state cleanup) | no replacement; root cause → **CAM-002** |

Accounting note: the CAM-001 receipt states 48 persistent methods; its explicit enumerations name 47 (32 B + 2 interleaved-name B members + 3 C + 3 D + 4 E + 1 F + 2 G). The residual 1 method is not individually recoverable from the receipt (its raw logs in `/tmp/setos-cam001/` are gone), and is covered by the M5/M6 unknown-failure rule above.

---

## 5. Non-weakening statement

- This matrix adds documentation only. No test file, scheme, assertion, threshold, or skip gate was created, edited, or removed by REL-001.
- All §7 constraints are preserved verbatim: runtime/safety/model-contract/acceptance checks remain mandatory; only the historical heuristic perceptual assertions are diagnostic, each with a named replacement ML eval; `PRODUCTION_ACCEPTANCE.md` thresholds remain binding for the integrated product.
- The three CAM-009 historical perceptual methods keep their assertions and remain red-by-record until ML-006/010 supersede them; they are not claimed green anywhere.
- Device-gated tests are listed as device-gated (with their DEV replacements), not as diagnostic false passes.
- Zero-test runs and unclassified failures block the release by rule (§2 invariants 1–2).
