# CAM-001 — Camera Coach test baseline receipt (candidate HEAD)

Date: 2026-09-20. HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee` (branch `store`), working tree contained only foreign docs changes (see GOV-001 receipt). Destination: iPhone 17e simulator, iOS 26.5, Xcode 26.6. Scheme `shafinMultitool`, unit bundle `shafinMultitoolTests` (+ legacy `shafinMultitoolUITests` pseudo-UI sources executed app-hosted).

## Run facts

1. **Full-suite pass 1 (parallel clones, default scheme settings):** 2 358 tests executed, 2 270 passed, 62 failures (60 unique method names extracted; 2 names lost to cross-clone log interleaving — both from the same presentation replay family and covered by the family classification below).
2. **Isolation pass 2 (all failing methods re-run serially, `-parallel-testing-enabled NO`):** 56 tests executed, 199 assertion failures across **48 unique methods that failed again**, while **12 passed** → those 12 are parallel/ordering-dependent, not genuine product failures.

Raw logs: `/tmp/setos-cam001/test.log`, `/tmp/setos-cam001/serial_retry.log`; result bundles `cam001.xcresult`, `cam001-serial-retry.xcresult` (same dir). Lists: `failed_unique.txt`, `serial_failed_norm.txt`, `parallel_only.txt`.

## Category classification (per method)

### A. `parallel_order_dependent` — 12 methods, passed in isolation → CAM-002 scope

| Method | Note |
|---|---|
| CameraCoachClosedLoopTests.testCaptureMotionHysteresisRejectsStillButUnstableFrame | known suite-order pair |
| CameraCoachClosedLoopTests.testCaptureMotionSamplingKeepsCameraActionAndExpiresMissingVisionEvidence | known suite-order pair |
| CameraCoachClosedLoopTests.testProductionCapturePathAutomaticallyVerifiesCorrectiveEpisode | "must invoke ActionVerifier from CameraViewModel" — only fails after other suites ran |
| CameraCoachClosedLoopTests.testProductionCapturePathPublishesCorrectiveAndHonestAbstention | capture path publishes nothing in shared-process run |
| CameraCoachClosedLoopTests.testProductionCapturePathSceneCutRejectsLatePreCutSampleAndRetries | same |
| CameraCoachClosedLoopTests.testProductionCaptureWithoutCalibrationCannotVerifySubjectMovement | fail-closed expectation holds only in fresh process |
| CameraCoachProductionUITests.testImagePlacementENLandscapeXXLUsesAcceptedImageEditor | pseudo-UI (XCUIApplication in unit bundle) |
| CameraCoachProductionUITests.testSceneControlRuntimeENLandscapeXXLReachesEveryIndependentAnswer | pseudo-UI |
| CameraCoachProductionUITests.testSceneControlRuntimeRUPauseAnswersReachPlannerAndReset | pseudo-UI |
| CameraViewModelLensSwitchTests.testProductionSubjectChangeResetsOwnerBeforeFreshResolutionBaseline | shared process state |
| CameraViewModelLifecycleTests.testCommittedPauseSurvivesSceneInactiveUntilSuccessfulResume | shared process state |
| IPadWindowingModeDiagnosticTests.testInspectIPadMultitaskingControls | environment-gated diagnostic (requires explicit iPad destination) |

### B. `presentation_oracle_divergence` — 32 methods, genuine → CAM-008/009/010 scope

All in `AnalysisPipelinePresentationTests`. Two directions of divergence between deterministic pipeline and locked oracle:

- **Good frames get forced corrective actions** (expect keep/silence, got e.g. `["shift_frame_right","step_back"]` on `demo_keep_wide_establishing`/`ca_img_010`; `ca_img_084` got `["change_camera_angle","remove_background_hotspot"]`; `ca_img_232` kept false keep; low-key/cinematic/establishing preservation tests all fail).
- **Underlit/bad frames lose specific corrective advice** (expect `add_front_fill_light` / background clearance / step-back; got empty semanticActions with only `increase_exposure` in futureActions).
- Plus 2 confidence-floor tests (`testGoodPauseVerdict…`: 0.55 vs expected 0.75/0.64) and `testStillImageReplayCalibratesResidualR20ConfidenceBands`.

### C. `missing_authenticated_fixture` — 3 methods, genuine (unrunnable) → owner/acceptance decision

`testStillImageReplayMapsSyntheticHotspotToCorrectiveSemanticActions` (179.jpg), `testStillImageReplaySuppressesPreservationForReadableSyntheticSmallSubject` (190.jpg), `testStillImageReplayWithholdsUnownedFillWhileKeepingCameraOcclusionAdvice` (168.jpg). These images are in neither the Debug benchmark pack (`camera_device_benchmark_pack_v1/images`, 174 files, checked) nor the SHA-pinned legacy recovery payload (9 images: 180–184, 188, 194, 204, 206) nor anywhere under `local-data/SETOS` (searched by name). Matches tracker §3.3 "reference assets not restored". Resolution requires owner-side asset restoration or explicit acceptance-exclusion.

### D. `missing_staged_qualification_payload` — 3 methods, genuine-but-environmental

`NIMACorrectedFP32SimulatorQualificationTests` (all 3): the SHA-pinned NIMA payload (`protocol.json`, sha256 `203aeed…`) EXISTS in `local-data/SETOS/verification/nima-ios-simulator-qualification-20260916-955kofxs/payload/` but has no staging script; a fresh app container (created by pass 1's reinstall) does not contain `Caches/SETOSNIMAQualification/…`. Unlike the legacy-camera fixture loader, the NIMA loader hard-throws instead of skip-gating on absent payload. Fix path (agent-owned): add `scripts/stage_nima_qualification.sh` + absent-payload XCTSkip gate, then stage and re-verify the 3 tests actually PASS.

### E. `device_gated_simulator` — 4 methods, genuine on simulator

`CameraTorchTests.testTorchStateResetsOnRelease`, `CameraAudioMeterTests.testMeterClearsOnRelease`, `CaptureConfigurationTests.testUIStateReadsBackFromDeviceAfterStart` ("capture session reported a runtime error"), `CameraViewModelLensSwitchTests.testReleaseResetsLensPresentationAndFencesLateCompletion` (`[]` vs `[wide]`). These assert real capture-device behavior; simulator cannot provide it (consistent with tracker §3.3 "4 device-gated"). Physical-device evidence belongs to DEV tasks.

### F. `ar_blank_snapshot` — 1 method

`ARAssetOwnerIntegrationTests.testLegacyNamedAnchorsRebuildAssetsUsingPersistedActorMetadata` ("Snapshot is blank or lacks its expected uniform background: fraction=0.0") → DEV-007 root-cause thread.

### G. `other_genuine` — 2 methods

- `SceneRecordingControllerTests.testAuthorizedRetryClearsMicrophoneRecoveryAndStartsRecording` — expected `SceneRecordingPermissionRecovery.openSettings`, got nil (mic recovery mapping).
- `InstallationDeletionLifecycleTests.testDeletionDrainsLateRefreshBeforeSigningAndCannotCacheReturnedToken` — `XCTAssertNotNil` on a drained-refresh value.

## Baseline summary for the tracker

- Full suite: **2 358 executed / 2 270 passed / 48 persistent failing methods (+2 interleaved-name members of family B) / 12 order-dependent**.
- vs previous tracker baseline (2 233 pass / 25 failing): suite grew; genuine failure families are the same three (presentation oracle, closed-loop order dependence, device-gated) plus the documented fixture/payload gaps (C, D) which previously presented differently.
- No test count inflation: unique-method accounting used throughout; skip-gated opt-in lanes (device benchmark, live model smoke, semantic eval export) behaved as designed.
