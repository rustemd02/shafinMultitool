# M5 full-suite baseline refresh — CAM-001-style re-run on the 20-slice tree (Xcode 27.0)

Date: 2026-09-23 (runs 2026-09-23 local). Candidate HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee` (branch `store`), working tree unchanged from REL-001/CAM-002/CAM-003 (93 pre-existing dirty/untracked entries: the accepted uncommitted slices incl. CAM-009 diff, `docs/admission/`, receipts; none touched, no commit/push).
Task: CAM-001-style test-baseline refresh routed through REL-001 — full M5 unit batch on the current tree, serial/isolation reconciliation of every unique failure, A-family (12 CAM-001 order-dependent methods) final fate, and diff vs the 2026-09-20 baseline (`receipts/2026-09-20-cam-001-camera-test-baseline.md`).
Toolchain: **Xcode 27.0 (27A266a) / iOS SDK 27.0** (same drift as CAM-002/003; CAM-001 ran Xcode 26.6/SDK 26.5). Destination `id=1F680A42-CEB3-43E8-9CED-52F874962A62` (iPhone 17e, iOS 26.5). Scratch DerivedData + logs only under `/private/tmp/setos-m5refresh/` (removed after this receipt per the owner disk rule). No repository file was created, edited or deleted except this receipt.

## Lane used (documented Xcode 27.0 workaround, not a new runner)

The canonical `-workspace` lane fails before compilation under Xcode 27.0 (checked-in Pods pin `IPHONEOS_DEPLOYMENT_TARGET` 12.0/14.0; SDK 27.0 floor is 15.0). Same workaround as CAM-003/CAM-002/`scripts/required_check.sh`:

1. One Pods prebuild: `xcodebuild -workspace shafinMultitool.xcworkspace -scheme Pods-shafinMultitool -sdk iphonesimulator -destination <DST> -derivedDataPath /private/tmp/setos-m5refresh/dd IPHONEOS_DEPLOYMENT_TARGET=15.0 build` → BUILD SUCCEEDED.
2. Every test lane: `-project shafinMultitool.xcodeproj -scheme shafinMultitool -sdk iphonesimulator -destination <DST> -derivedDataPath <shared dd> -collect-test-diagnostics never` (+ `-parallel-testing-enabled NO -maximum-parallel-testing-workers 1` on all serial lanes). Method-level `-only-testing` masks must use the slash form `Target/Class/method` — the dot form (`Target/Class.method`) silently selects 0 tests on this toolchain (probe recorded; `scripts/required_check.sh` already uses the slash form).

Pass 1 replicates the canonical M5 runner semantics (`scripts/run_swift_unit_tests.sh`): unit classes grepped by the runner's own pattern → **198 classes** (matrix recorded 196; +2 from accepted slices), batches of 6, `--keep-going`, disk guard 2048 MiB (never tripped; ≥75 GiB free), legacy-reference staging attempted per batch. Deviation from the runner (recorded): NIMA staging attempted per batch too, and the `-project` lane replaces `-workspace` per the workaround above. Both staging scripts silently no-op in this environment — see "Payload gaps" below.

## Run facts

### Pass 1 — full M5 unit batch, parallel-by-default (scheme `parallelizable = YES`), 33 batches, ~17 min wall

- Runnable unit methods: **2 325** (= 2 328 grep-declared − 1 parameterized helper `testingPublishMeasuredLiveFixture(frameId:…)` that XCTest never runs). Every one of the 198 classes executed.
- Observed: **2 264 passed, 44 failed (44 unique methods — zero names lost), 17 skipped by design.** Accounting is exact: 28 result lines were mangled by cross-clone log interleaving (1 per affected class, same mechanism that lost 2 names in CAM-001); all 28 were reconciled — 11 recovered from raw line fragments (10 passed + `NIMACorrectedFP32SimulatorQualificationTests.testExternalFP32NonSquareOrientationAndScorerAgreement` FAILED), 16 verified serially green (lane `noline_serial`, 16/16 green), 1 is the parameterized helper.

### Pass 2 — serial/isolation re-run of all 44 unique failures (one serial lane, 44 tests / 180 assertion failures)

- **40 failed again serially → genuine persistent set** (classification below).
- **4 passed serially → pass-1-only artifacts**: the 3 `CameraCoachClosedLoopTests` capture-path category-A methods that surfaced in this run's parallel batches (`testProductionCapturePathAutomaticallyVerifiesCorrectiveEpisode`, `testProductionCapturePathPublishesCorrectiveAndHonestAbstention`, `testProductionCapturePathSceneCutRejectsLatePreCutSampleAndRetries`) + `CameraAudioMeterTests.testMeterClearsOnRelease` (device-gated E-class whose pass-1 red is simulator noise — same toolchain-dependent signature family CAM-002 recorded for torch; its classification stays device-gated, not order-artifact).

### Focused lanes

- **NIMA (D-family) serial, unstaged**: 3/3 hard-throw `protocol.json … no such file or directory` (test code catches and fails). A staged run was attempted but is **impossible on this machine**: the SHA-pinned payload no longer exists at `setos-backend/local-data/SETOS/verification/nima-ios-simulator-qualification-20260916-955kofxs/payload` (staging script rc=2, "canonical payload not found"). See payload gaps.
- **A-family unit serial lane** (6 closed-loop capture-path + lens subject-change + committed-pause, exact CAM-002 f4 mask): **8/8 green**.
- **A-family UI serial lane**: `CameraCoachProductionUITests.testImagePlacementENLandscapeXXLUsesAcceptedImageEditor` green; the 2 SceneControl methods **red in isolation** (`CameraCoachProductionUITests.swift:1016`, `XCTAssertTrue failed` — same as CAM-002 g1); `IPadWindowingModeDiagnosticTests.testInspectIPadMultitaskingControls` fails fast on the iPhone destination with "This diagnostic requires the selected iPad Simulator" (env-gated, matrix M7).
- **Scene-cut contention probe**: `testProductionCapturePathSceneCutRejectsLatePreCutSampleAndRetries` alone serial ×5 → 5/5 green; total today 0 red in 7 serial executions (CAM-002 measured 1/20 ~24h earlier). Contention-class, not order-class, stands.
- **M-UI blocking subset, serial** (6 classes: EntryFlow, Production, Generator, Library, Privacy, Gallery): **54 executed, 52 green, 2 failures** (the 2 SceneControl methods above). No new UI-bundle failures. (7 legacy `CameraCoachLaunchUITests` methods not run per matrix M-UI skip rule; iPad diagnostic = M7.)

### A-family (12 CAM-001 order-dependent methods) — final fate, all serial evidence on this tree

| Fate | Methods |
|---|---|
| **9 serial-green → order-artifact status can be retired** (CAM-002 recommendation confirmed) | 6 closed-loop capture-path (`testCaptureMotionHysteresisRejectsStillButUnstableFrame`, `testCaptureMotionSamplingKeepsCameraActionAndExpiresMissingVisionEvidence`, `testProductionCapturePathAutomaticallyVerifiesCorrectiveEpisode`, `testProductionCapturePathPublishesCorrectiveAndHonestAbstention`, `testProductionCapturePathSceneCutRejectsLatePreCutSampleAndRetries`, `testProductionCaptureWithoutCalibrationCannotVerifySubjectMovement`) + `CameraViewModelLensSwitchTests.testProductionSubjectChangeResetsOwnerBeforeFreshResolutionBaseline` + `CameraViewModelLifecycleTests.testCommittedPauseSurvivesSceneInactiveUntilSuccessfulResume` + `CameraCoachProductionUITests.testImagePlacementENLandscapeXXLUsesAcceptedImageEditor` |
| **1 contention-class** (resource, not order; keep in serial blocking lanes) | `…SceneCutRejectsLatePreCutSampleAndRetries` — 0/7 serial red today, 1/20 in CAM-002; DETR/CoreML first-use contention in production heavy-model lifecycle (CAM-002 finding 2) |
| **2 isolation-red — leave category A entirely** (drift fact; stale test oracle vs accepted UI/localization slices; release-gated until owning UI task classifies) | `testSceneControlRuntimeENLandscapeXXLReachesEveryIndependentAnswer`, `testSceneControlRuntimeRUPauseAnswersReachPlannerAndReset` — red alone in this run's UI lane; literal re-verified on current tree: expected "Try another camera position while keeping the main subject in frame" exists only in the test file; shipped keys `set.camera.corrective.change_angle` / `set.trace.action.change_angle` carry "Move with the phone to another camera position…" |
| **1 environment-gated** (unchanged) | `IPadWindowingModeDiagnosticTests.testInspectIPadMultitaskingControls` → matrix M7, requires iPad destination |

## Unique persistent failures (40, serially confirmed) — classification per matrix REL-001

| Class | Count | Methods / evidence |
|---|---:|---|
| B — presentation oracle divergence | 27 | `AnalysisPipelinePresentationTests`, e.g. `testSemanticDemoScenarioPackReplaysExpectedPresentationActions`, `testStillImageReplayCalibratesResidualR20ConfidenceBands`, `testStillImageReplayMapsReadableUnderlitObjectToFrontFill`, `testStillImageReplayPreservesGoodReadableKeepDespiteTechnicalSignal`, both `testGoodPauseVerdict…` are GREEN now (CAM-009) — failures are assertion divergences on in-repo benchmark-pack fixtures (legacy payload staged or not needed), e.g. ca_img_208 required `remove_distracting_object`, got `["shift_frame_right","step_back","step_closer"]` |
| B — historical perceptual replay (recorded diagnostic set, CAM-009) | 3 | `testStillImageReplayPreservesCinematicEstablishingDespiteTechnicalFuture`, `testStillImageReplayPreservesNarrativeEstablishingFramesWithKeepCurrentSetup`, `testStillImageReplayPromotesWideUnknownGoodEstablishingConfidence` |
| C — missing authenticated fixtures (hard-throw) | 3 | `…MapsSyntheticHotspotToCorrectiveSemanticActions` → "Missing required benchmark image; no authenticated external reference: 179.jpg"; `…SuppressesPreservationForReadableSyntheticSmallSubject` → 190.jpg; `…WithholdsUnownedFillWhileKeepingCameraOcclusionAdvice` → 168.jpg |
| D — NIMA qualification payload absent | 3 | `NIMACorrectedFP32SimulatorQualificationTests` 3/3 hard-throw on missing `protocol.json`; payload directory GONE from `local-data/SETOS/verification/` (was present-unstaged at CAM-001) |
| E — device-gated | 4 | `CameraTorchTests.testTorchStateResetsOnRelease` ("capture session reported a runtime error" — toolchain-dependent signature per CAM-002), `CameraViewModelLensSwitchTests.testReleaseResetsLensPresentationAndFencesLateCompletion` (`[]` vs `[wide]`), `CaptureConfigurationTests.testUIStateReadsBackFromDeviceAfterStart` (runtime error), `CameraAudioMeterTests.testMeterClearsOnRelease` (pass-1 red, serial-green this refresh — noisy simulator behavior, classification unchanged) |
| F — AR blank snapshot | 1 | `ARAssetOwnerIntegrationTests.testLegacyNamedAnchorsRebuildAssetsUsingPersistedActorMetadata` — "Snapshot is blank or lacks its expected uniform background: fraction=0.0" (unchanged) |
| G — genuine defects | **0** | both 2026-09-20 G methods GREEN today — see diff |

Parallel/order artifacts of this run (4): the 3 closed-loop capture-path methods above + audio-meter (device-noise, E-class). Order-artifact category A is otherwise retired per the A-family table.

Skips (17, all by-design gates, reported per matrix invariant 4): 7 presentation tests that require the SHA-pinned legacy reference payload — the in-file `XCTSkip` gate at `AnalysisPipelinePresentationTests.swift:58` fires because the payload is absent (CAM-008's planned gate is now in the tree); 3 `VisionRequestIsolationDiagnosticTests.testRecovered184*` (same payload gate); `DeviceBenchmarkUITests.testBenchmarkModeLaunchesAndCompletesQuickRun` (unconditional placeholder); `DeviceBenchmarkHarnessTests.testRunConfiguredDeviceBenchmark` (config-gated); `SceneV8PipelineTests` live-smoke ×2 + `SceneScriptsMarkdownSmokeTests` (`SG_*`/env-gated opt-in); `SETCompositionNetScorerTests` ×2 (frozen model artifact absent — fail-closed skip).

## Diff vs the 2026-09-20 baseline (CAM-001)

| Family | 2026-09-20 | 2026-09-23 | Change |
|---|---:|---:|---|
| A order-dependent | 12 | 0 | **Resolved**: 9 serial-green (retire), 1 → contention-class, 2 → isolation-red drift fact (new bounded task needed), 1 env-gated (unchanged) |
| B presentation (oracle + perceptual) | 32 | 30 (27 oracle + 3 perceptual diagnostic) | CAM-009 restored its 7 presentation selectors (incl. both `testGoodPauseVerdict…` confidence floors) — green; net −2 at family level. Name-level diff beyond named methods is NOT reconstructable from surviving receipts (CAM-001 raw logs removed; CAM-008 receipt lists no full names) |
| C fixture gap | 3 | 3 | unchanged (hard-throw, same images) |
| D payload gap | 3 | 3 | classification unchanged, but the payload moved from "exists, unstaged" to **"absent from local-data"** — gap deepened; D is no longer agent-fixable via staging |
| E device-gated | 4 | 4 | unchanged set; audio-meter outcome is noisy on Xcode 27 (pass-1 red, serial green) |
| F AR blank snapshot | 1 | 1 | unchanged (identical signature) |
| G genuine defects | 2 | **0** | **FIXED by accepted slices**: `SceneRecordingControllerTests.testAuthorizedRetryClearsMicrophoneRecoveryAndStartsRecording` and `InstallationDeletionLifecycleTests.testDeletionDrainsLateRefreshBeforeSigningAndCannotCacheReturnedToken` both green in pass 1 (batch 26) |
| Unknown failures | — | **0** | matrix §2 invariant 2 satisfied: every one of the 44 pass-1 reds maps to a recorded family or the A-family resolution |

Suite deltas: declared unit methods 2 299 → 2 328 (+29 from the ~20 accepted slices); M5 lane executed 2 325 runnable (2 264 green / 44 red / 17 skip) vs CAM-001's 2 358 one-shot unit+UI (2 270 passed / 62 failure events / 48+2 genuine + 12 A). UI bundle separately today: M-UI blocking subset 54 executed / 52 green / 2 known SceneControl reds. No new red family appeared anywhere; the two SceneControl reds and the NIMA hard-throws were already the recorded expectation.

## Payload gaps (owner-relevant facts)

- `setos-backend/local-data/SETOS/verification/` now contains only `camera-runtime-owner-review-20260917-z0c1qz_i`; the NIMA qualification payload dir and the legacy-reference-recovery payload dir (`legacy-reference-recovery-20260917-p8m2af3s`) recorded in the staging scripts' defaults are **gone from local-data**. Consequently: `stage_nima_qualification.sh` rc=2 ("canonical payload not found") and `stage_legacy_camera_references.sh` cannot stage (same reason) — both silently no-op in batch drivers. D-family (3) hard-throws; 7 presentation + 3 VisionRequest tests skip by their in-file gates. If the owner restores the payloads (per `LOCAL_DATA.md` relocation mapping), the 10 skipped tests become runnable and D may be re-verified.
- Latent bug in owner script `scripts/stage_nima_qualification.sh`: the `--udid` case does `shift` instead of `shift 2`, so the documented invocation `--udid UDID` errors with "unknown argument: <udid>" (rc=2). Calling it with NO arguments (stage all booted sims) works. Not fixed here (outside Own zone); flagging for the owner.

## Limits / what this does NOT claim

- Xcode 27.0 / SDK 27.0 vs CAM-001's Xcode 26.6 / SDK 26.5: cross-toolchain family-count comparisons are indicative, not bit-identical. Signatures that repeated verbatim (C missing-fixture messages, F `fraction=0.0`, lens `[] vs [wide]`) are toolchain-stable.
- Pass 1 batches 6 classes per xcodebuild invocation (runner semantics); CAM-001 ran one shot. The batched composition changes which category-A methods surface in parallel mode (3 of 6 closed-loop vs CAM-001's 6); the serial evidence, not the pass-1 red set, is the classification of record.
- The 7 presentation selectors CAM-009 restored are green here; the remaining 27 oracle divergences remain POST-007 / ML-006/010 scope per tracker §7 — nothing was weakened, retried into green, or skipped into green by this task.
- M5 covers the unit bundle; the UI bundle was covered by the M-UI blocking-subset serial lane (54) + A-family iPad check, not by a full parallel UI run; the 7 legacy `CameraCoachLaunchUITests` methods were not executed (matrix M-UI skip rule, CC-005).
- Tracker §3.3 was NOT edited (orchestrator owns it); this receipt is the proposed replacement evidence.
- Scratch `/private/tmp/setos-m5refresh/` (dd, 33 pass-1 logs, serial/A-family/M-UI/probe logs) removed after this receipt; no raw-log claims above go beyond what is quoted.

## Commands

```bash
DST='id=1F680A42-CEB3-43E8-9CED-52F874962A62'
DD=/private/tmp/setos-m5refresh/dd
# 1) Pods prebuild (Xcode 27.0 drift workaround):
xcodebuild -workspace shafinMultitool.xcworkspace -scheme Pods-shafinMultitool \
  -sdk iphonesimulator -destination "$DST" -derivedDataPath "$DD" IPHONEOS_DEPLOYMENT_TARGET=15.0 build
# 2) Pass 1 (×33 batches, 6 unit classes each, parallel default, keep-going):
xcodebuild test -project shafinMultitool.xcodeproj -scheme shafinMultitool \
  -sdk iphonesimulator -destination "$DST" -only-testing:shafinMultitoolTests/<Class>… \
  -derivedDataPath "$DD" -collect-test-diagnostics never test
# 3) Every serial lane: same + -parallel-testing-enabled NO -maximum-parallel-testing-workers 1
#    method masks in slash form: -only-testing:shafinMultitoolTests/Class/method
```
