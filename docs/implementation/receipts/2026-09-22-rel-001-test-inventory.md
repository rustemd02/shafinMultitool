# REL-001 — Test targets/schemes inventory and release-relevance classification

Date: 2026-09-22. Candidate HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee` (branch `store`), working tree contains the uncommitted CAM-009 bounded diff (`shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift`, `shafinMultitoolTests/AnalysisPipelinePresentationTests.swift`, `shafinMultitoolTests/CameraCoachClosedLoopTests.swift`, `shafinMultitoolTests/CameraCloudPauseIntegrationTests.swift`) and foreign untracked files (`docs/admission/` etc.) — none touched. Deliverable: `docs/implementation/test-command-matrix-v1.md`.

## Method

Read-only classification task. **No test suite, batch, or focused run was executed** (fresh baseline already exists: CAM-001, CAM-009). Evidence assembled from:

1. `xcodebuild -list -project shafinMultitool.xcodeproj` — targets/schemes/configurations.
2. Scheme source `shafinMultitool.xcodeproj/xcshareddata/xcschemes/shafinMultitool.xcscheme` — both `.xctest` testables, `parallelizable="YES"`, `shouldAutocreateTestPlan="YES"`.
3. grep over `shafinMultitoolTests/` and `shafinMultitoolUITests/`: `(final )?class <Name> : XCTestCase` for classes; `func test<Name>(` for declared methods; line-range partition for multi-class files.
4. `xcrun simctl list devices` — pinned destination `1F680A42-CEB3-43E8-9CED-52F874962A62` = iPhone 17e, iOS 26.5 (identical to CAM-001 destination and CAM-009 serial runs).
5. Classification inputs: CAM-001 baseline receipt (2 358 executed; 48 persistent genuine B–G; 12 order-dependent A), CAM-008 triage (family B verdict: code regression from `d4815f3`; oracle stands), CAM-009 receipt (runtime/safety controls 8/8 green on the current diff; 3 historical perceptual methods red as recorded diagnostic evidence routed ML-006/010), tracker §7.

## Inventory counts (grep-derived)

| Item | Count | Source command |
|---|---:|---|
| Targets / schemes | 3 / 1 | `xcodebuild -list` |
| Unit test files / classes | 183 / **196** | `grep -rhoE '(final )?class [A-Za-z0-9_]+ *: *XCTestCase' shafinMultitoolTests` (unique names) |
| UI test files / classes | 8 / **8** | same grep on `shafinMultitoolUITests` |
| Total test classes | **204** | sum |
| Declared test methods | **2 299 unit + 62 UI = 2 361** | `grep -rhoE 'func test[A-Za-z0-9_]+\('` |
| Executed by CAM-001 baseline | 2 358 (delta = designed skip-gated opt-in lanes) | CAM-001 receipt |
| Multi-class files | `AnalysisPipelinePresentationTests.swift`: `AnalysisPipelinePauseSnapshotTests` (3), `AnalysisPipelinePresentationTests` (112), `SemanticEvalStillImageBatchReplayTests` (2). `CameraAnalysisDomainContractsTests.swift`: 9 classes, 115 methods | line-range grep |

## Canonical lanes (detail in test-command-matrix-v1.md)

| Lane | Category | Content | Method count |
|---|---|---|---:|
| M0 smoke | **blocking** | `CameraAdviceSafetyGateTests` 19, `GoodFramePreservationPolicyTests` 8, `ActionVerifierTests` 28, `UserMovementObserverTests` 39, `SemanticTipPlannerTests` 31 (125) + 7 CAM-009 presentation selectors + 1 closed-loop selector | 133 (+ `scripts/validate_privacy_manifest.sh`) |
| M1 camera-coach runtime | **blocking** | M0 classes + `CameraCoachClosedLoopTests` 21, `AnalysisPipelinePauseSnapshotTests` 3, `AnalysisPipelineReleaseTests` 33, `CameraConfidenceCalibratorTests` 13 + the 8 selectors | 203 |
| M2 verifier | **blocking** | `ActionVerifierTests` 28 + `UserMovementObserverTests` 39 (CAM-004 passed this exact mask: 67 tests, 0 failures) | 67 |
| M3 planner | **blocking** | `SemanticTipPlannerTests` 31, `CameraBoundedActionPlannerTests` 20, `AdviceStabilizerTests` 16, `SemanticDirectionBehaviorTests` 7, `FrameCritiqueEngineTests` 42 | 116 |
| M4 contract/model-contract/privacy | **blocking** | 7 contract classes (25+10+19+9+18+2+18 = 101) + 9 classes of `CameraAnalysisDomainContractsTests.swift` (115) + `validate_camera_release_label.py` + `validate_camera_release_capability_mapping.py` + privacy script | 216 (+3 validators/scripts) |
| M5 full unit | **blocking interpretation** | all 196 classes via `scripts/run_swift_unit_tests.sh`; result read against the classification table; zero executed tests = lane failure | 2 299 |
| M6 diagnostic replay | **diagnostic** | `AnalysisPipelinePresentationTests` 112 + `SemanticEvalStillImageBatchReplayTests` 2 + `NIMACorrectedFP32SimulatorQualificationTests` 3 (staged payload via `scripts/stage_nima_qualification.sh`); expected red = recorded set; anything outside it = unknown ⇒ release-gated | 117 |
| M7 device-gated | **device-gated** | torch, audio-meter, capture readback, lens-release fencing, iPad windowing diagnostic; replacements DEV-002…004/011 | 5 (+ opt-in harness/live-model lanes) |
| M-UI | **blocking 54 / diagnostic 7 / iPad-gated 1** | production UI journeys + privacy UI; `CameraCoachLaunchUITests` (`UITests.swift`, 7) legacy shell automation skipped to diagnostic per CC-005 false-green audit (asserts no safety/runtime contract) | 62 |

Unit-method category totals (sum = 2 299): blocking 2 185 (2 182 expected green + 3 known-red blockers F+G), diagnostic 107 (102 presentation perceptual remainder + 2 semantic-eval replay + 3 NIMA), fixture-gap-owner-pending 3 (179/190/168.jpg methods, inside the presentation class), device-gated 4.

## Classification of known CAM-001 failures

| Cat | n | Release relevance | Replacement |
|---|---:|---|---|
| B runtime/safety controls | 8 verified green (CAM-009) | **blocking** (green on current diff) | — |
| B historical perceptual replay | 3 confirmed red + remainder measured by M6 | **diagnostic** (assertions intact, routed ML-006/010 per §7) | perceptual accuracy → **ML-006**; deterministic-vs-model → **ML-010**; heuristics restoration excluded to POST-007 |
| B front-fill/clearance mapping | subset of B | diagnostic until **CAM-010**, then blocking via model integration | CAM-010 + ML-006 |
| C missing authenticated fixtures | 3 | **fixture gap — owner pending** (§19 п.7: restore `168/179/190.jpg` or explicit acceptance exclusion); not diagnostic by default; loader currently hard-throws (no skip gate present — see GAPS) | if excluded: ML-006 on owned assets |
| D NIMA qualification | 3 | **diagnostic** (research-only Stage-2, tracker §3.2) | research evidence for ML-006/010; run after `scripts/stage_nima_qualification.sh` |
| E device-gated | 4 | **device-gated** (named simulator exclusions; never counted as pass) | DEV-002…004 physical receipts |
| F AR blank snapshot | 1 | **blocking — known failure** (open root cause) | DEV-007 |
| G genuine defects | 2 (mic-denial retry recovery; deletion drained-refresh) | **blocking — known failures** | fix scope REL-002; release blocked until green |
| A order-dependent | 12 | **blocking, serial mode** (all pass in isolation; parallel-clone artifact) | CAM-002 shared-state cleanup |

Rules encoded in the matrix: zero-test run = failure; a failure not in this table stays release-gated until classified; no assertion deleted/weighed/skipped into green (the single `-skip-testing` is the legacy `CameraCoachLaunchUITests` file, which asserts no safety/runtime contract and carries CC-005's documented false-green risk); device-gated tests are listed with their DEV replacements, not as diagnostic false passes.

## Consistency check (grep, 2026-09-22)

- Every test-class token in `test-command-matrix-v1.md` resolves to a real `XCTestCase` class in the repo: **49/49** (extracted `\b[A-Za-z0-9_]*Tests\b`, unique = 51; excluded `shafinMultitoolUITests` target name and its `UITests` suffix token).
- Every `-only-testing`/`-skip-testing` class mask in the matrix: **39/39** classes exist.
- Every test method named in the matrix: **18/18** (`func <name>()` found exactly once each) — 7 CAM-009 blocking selectors, 1 closed-loop selector, 3 historical perceptual, 3 fixture-gap, 4 device-gated, 1 AR blank, 2 category-G, plus A-family members cited (12/12 verified in the same pass).
- Referenced scripts/validators exist (6/6): `scripts/validate_privacy_manifest.sh`, `scripts/run_swift_unit_tests.sh`, `scripts/stage_nima_qualification.sh`, `scripts/stage_legacy_camera_references.sh`, `ml/camera_coach/contracts/validate_camera_release_label.py`, `ml/camera_coach/contracts/validate_camera_release_capability_mapping.py`.
- Pinned destination verified on host: `1F680A42-CEB3-43E8-9CED-52F874962A62` (iPhone 17e, iOS 26.5, Shutdown at receipt time).

## Sources

- `receipts/2026-09-20-cam-001-camera-test-baseline.md` (2 358/48/12 baseline, categories A–G)
- `receipts/2026-09-20-cam-008-presentation-triage.md` (family B verdict and restoration plan)
- `receipts/2026-09-22-cam-009-deterministic-keep-restoration.md` (runtime/safety 8/8; 3 historical methods red as diagnostic)
- `docs/implementation/APP_STORE_RELEASE_TRACKER.md` §7 and REL-001 row
- `docs/implementation/audits/test-topology.md` (CC-005 legacy UI false-green audit; historical 29-file topology — superseded by this inventory's counts)

## GAPS

1. **CAM-001 arithmetic residual:** the receipt states 48 persistent genuine methods; its explicit enumerations name 47 (32 B + 2 interleaved + 3 C + 3 D + 4 E + 1 F + 2 G). The 48th method is not individually recoverable (raw logs `/tmp/setos-cam001/` no longer present). It is covered by the unknown-failure rule, not silently dropped.
2. **C-family skip gate not landed:** CAM-008 records a planned `XCTSkipUnless(...hasAuthenticatedImage...)` conversion "done in the CAM-009 slice", but the current tree has no such gate — `LegacyCameraReferenceFixture.imageSHA` (9 images) does not contain 168/179/190.jpg and `makeDatasetPixelBuffer` hard-throws for them. The 3 methods remain unrunnable fixture-gap failures pending the §19 п.7 owner decision.
3. **Exact current split of family B is unknown without running M6:** CAM-009 verified only the 8-selector blocking core (green) and the 3 named historical methods (red, diagnostic). The remaining ~102 presentation-class methods' state after the CAM-009 diff is established by the M6 lane, intentionally not executed here.
4. **M5 is expected-red on the current baseline** exactly by the documented set (B remainder, C, D unstaged, E, F, G); closing it is REL-002/CAM-022 scope, not REL-001.
5. The UI-bundle pseudo-UI history differs between CAM-001 (legacy sources app-hosted) and the current tree (dedicated `shafinMultitoolUITests` target, 8 classes); this receipt classifies the current topology.
