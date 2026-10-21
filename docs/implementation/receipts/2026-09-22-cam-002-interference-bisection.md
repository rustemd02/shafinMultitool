# CAM-002 — suite-order interference bisection: serial pair sweep, root-cause classification, A-family serial evidence

Date: 2026-09-22 (runs 2026-09-22/23 local). Candidate HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee` (branch `store`), same working tree as REL-001 (includes the accepted CAM-009 deterministic-KEEP diff and other accepted uncommitted slices — none touched).
Toolchain: Xcode 27.0 (27A266a) / iOS SDK 27.0 — the first CAM-002 execution since the toolchain drift recorded in `receipts/2026-09-22-cam-003-calibration-contract.md`. Destination `id=1F680A42-CEB3-43E8-9CED-52F874962A62` (iPhone 17e, iOS 26.5), every lane serial (`-parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -collect-test-diagnostics never`), scratch DerivedData/logs only under `/private/tmp/setos-cam002/` (removed after the run).

## Task

CAM-002 (tracker §9, was PARTIAL with 2026-09-20 progress): eliminate the suite-order interference behind CAM-001's 12 category-A (parallel-order-dependent) methods via a common root cause — not via retries/disable/assertion changes. Prescribed method: minimal serial pairs "suspect class → `CameraCoachClosedLoopTests` capture-path methods", then bounded triples/quartets, then honest conclusion + serial evidence if not reproducible.

## Method

- Bisection target: the 6 closed-loop capture-path category-A methods of `CameraCoachClosedLoopTests` (`testCaptureMotionHysteresisRejectsStillButUnstableFrame`, `testCaptureMotionSamplingKeepsCameraActionAndExpiresMissingVisionEvidence`, `testProductionCapturePathAutomaticallyVerifiesCorrectiveEpisode`, `testProductionCapturePathPublishesCorrectiveAndHonestAbstention`, `testProductionCapturePathSceneCutRejectsLatePreCutSampleAndRetries`, `testProductionCaptureWithoutCalibrationCannotVerifySubjectMovement`). `testFreshReplanningPreservesEpisodeThroughVerification` was excluded per the row (genuine, CAM-008/009 scope) and was additionally observed green in the M1 lane.
- Build workaround for the Xcode 27.0 drift (documented in CAM-003 receipt): one Pods prebuild with a command-line-only override, then the `-project` lane for every test run:
  `xcodebuild -workspace shafinMultitool.xcworkspace -scheme Pods-shafinMultitool -sdk iphonesimulator -destination <DST> -derivedDataPath /private/tmp/setos-cam002/dd IPHONEOS_DEPLOYMENT_TARGET=15.0 build` → BUILD SUCCEEDED; all test lanes then used `-project shafinMultitool.xcodeproj -scheme shafinMultitool` + the serial flags above. No repository file was changed by the workaround.

## Runs (22 xcodebuild test invocations, all serial)

| Run | Mask (order as executed) | Result |
|---|---|---|
| r00 | 6 closed-loop capture-path alone | green (6/0) |
| p1 | `CameraViewModelLensSwitchTests` (13) + 6 CL | only known E-class `testReleaseResetsLensPresentationAndFencesLateCompletion` red; 6 CL green |
| p2 | `CameraViewModelLifecycleTests` (18) + 6 CL | green (24/0) |
| p3 | `CameraManagerLifecycleTests` (28) + 6 CL | green (34/0) |
| p4 | `CaptureConfigurationTests` (2) + 6 CL | only known E-class `testUIStateReadsBackFromDeviceAfterStart` red; 6 CL green |
| p5 | `CameraTorchTests` (2) + 6 CL | **`testProductionCapturePathSceneCutRejectsLatePreCutSampleAndRetries` RED** + known E-class torch red |
| p6 | `CameraAudioMeterTests` (2, executed first) + 6 CL | only known E-class `testMeterClearsOnRelease` red; 6 CL green |
| q1 | Torch class + scene-cut only | torch E red only; scene-cut green |
| q2 | exact p5 mask, repeat | entirely green — including `testTorchStateResetsOnRelease` |
| q3 | `testTorchStateResetsOnRelease` + scene-cut | torch E red only; scene-cut green |
| q4 | `testTorchUnsupportedWithoutConfiguredInput` + scene-cut | green |
| a4-1…4 | scene-cut alone, ×4 | green ×4 |
| f1-f3 | exact p5 mask, ×3 repeats | green ×3 |
| f4 | serial A-family: 6 CL + lens-switch subject-change + committed-pause + 3 pseudo-UI (`CameraCoachProductionUITests`) | 9 green; 2 pseudo-UI RED (`testSceneControlRuntimeENLandscapeXXLReachesEveryIndependentAnswer`, `testSceneControlRuntimeRUPauseAnswersReachPlannerAndReset`) |
| g1 | the 2 red pseudo-UI methods alone (UI lane only, nothing before them) | **2/2 RED in isolation** |
| M1 | matrix lane M1: closed-loop full class + SafetyGate/GoodFrame/Verifier/MovementObserver/Planner/PauseSnapshot/Release/Calibrator + 7 CAM-009 presentation selectors | **209 tests / 0 failures, TEST SUCCEEDED** |

Execution-order fact (checked in every log): inside the unit bundle XCTest orders classes alphabetically, so `CameraCoachClosedLoopTests` ran BEFORE `CameraTorchTests`/`CameraViewModel*`/`CameraManager*`/`CaptureConfiguration*` in p1–p5 (only `CameraAudioMeterTests` sorts earlier and truly ran first in p6). The p5 red therefore cannot be attributed to its pair-mate at all — see finding 1.

## Findings

1. **No cross-class shared-state poisoner exists in serial mode on this tree.** Six camera-candidate classes were paired with the closed-loop capture-path set; every pair red is exactly the known device-gated E-class failure of the candidate class itself, and the closed-loop methods stayed green (18/18 executions across pairs, minus the single p5 flake below). The tracker's suspect #2 ("shared state в прочих camera-классах") is not supported: the capture-path harness builds fresh `CameraManager`/`AnalysisPipeline`/`CameraViewModel` per test with an isolated `NotificationCenter`, and no candidate class was observed to poison it.
2. **The single closed-loop red (p5, 1 red in 20 serial executions of the scene-cut method) is resource contention, not an order artifact.** Evidence from the failing run's own log:
   - per-pipeline-instance first DETR inference (`lowFrame=1 sinceLast≈distantPast`) took **1676 ms and 2192 ms** in p5 versus **607–656 ms in every other run** (r00/f-runs table);
   - during that window the production high-priority path shed frames by design: only `frame_1000`, `frame_1500` got `[PIPE_HIGH]` processing out of the 10 baseline samples (frames 1100–1400 dropped), so the 2 s `waitUntil` baseline window starved (assertions at `CameraCoachClosedLoopTests.swift:1855` and `:1869`);
   - once the heavy first-use work completed, the same test instance proceeded green through its retry phase.
   This is the same root cause CAM-001 already named for the parallel clones (BNNS/CoreML compile/inference contention in logs), now visible in serial at ~5% frequency under Xcode 27.0. It lives in the production heavy-model lifecycle (`DETRDetector` per-instance `MLModel` load + first `VNCoreMLRequest`, `AnalysisPipeline` low-priority scheduling), not in test shared state. The affected assertions (exact PTS publication, baseline/scene-cut publication within the fixture's 2 s windows) were not weakened, not retried, and not disabled.
3. **Two of the 12 category-A methods are no longer order artifacts — they fail in isolation today.** `testSceneControlRuntimeENLandscapeXXLReachesEveryIndependentAnswer` and `testSceneControlRuntimeRUPauseAnswersReachPlannerAndReset` (pseudo-UI) went red in the serial A-family lane AND red 2/2 alone (g1: "Executed 2 tests, with 2 failures"), at `CameraCoachProductionUITests.swift:1016` — the pause-review advice literal (`label == "Try another camera position while keeping the main subject in frame"` / RU «Попробуй другую точку съёмки, сохраняя главный объект в кадре») no longer appears. That literal exists **only in the test file** (checked HEAD and tree); the shipped copy keys `set.camera.corrective.change_angle` / `set.trace.action.change_angle` carry "Move with the phone to another camera position while keeping the main subject in frame" at HEAD and in the working tree. Whether this is a stale test oracle or a presentation regression of the accepted uncommitted UI/localization slices (`Localizable.xcstrings` +144 lines, `SETCameraCoachProductionView.swift`, `CameraOverlayUXPresentation.swift`, …) must be classified by the owning task chain (UI-004/CAM-009 follow-up); per matrix §2 invariant 2 it stays release-gated until classified. It is outside CAM-002's Own zone, so nothing was edited there.
4. **`testTorchStateResetsOnRelease` (E-class device-gated) is itself flaky on the new toolchain**: red in p5/q1 (`.failure(.unavailable)` vs expected `.stale`), red in q3 ("The capture session reported a runtime error"), green in q2/f1–f3. The E-class classification (simulator cannot qualify torch hardware) stands; only the error signature is toolchain-dependent. `FigCaptureSessionSimulator` err `-12782` lines appear in green and red runs alike (incidental simulator noise).
5. **A-family serial evidence (f4):** 11 of the 12 category-A methods in one serial lane: 9 green — all 6 closed-loop capture-path, `CameraViewModelLensSwitchTests/testProductionSubjectChangeResetsOwnerBeforeFreshResolutionBaseline`, `CameraViewModelLifecycleTests/testCommittedPauseSurvivesSceneInactiveUntilSuccessfulResume`, `CameraCoachProductionUITests/testImagePlacementENLandscapeXXLUsesAcceptedImageEditor`; 2 red per finding 3. `IPadWindowingModeDiagnosticTests/testInspectIPadMultitaskingControls` remains environment-gated to an explicit iPad destination (matrix M7), not runnable in this lane — unchanged from CAM-001.
6. `testFreshReplanningPreservesEpisodeThroughVerification` remained untouched and green (inside M1's 209/209 and the closed-loop class lanes).

## What was changed

Nothing in code or tests. The surviving serial flake's root cause is outside the Own zone (production heavy-model lifecycle; `AnalysisPipeline.swift` is the CAM-009 diff file, explicitly excluded), and no honest in-zone fix exists that is not a retry/disable/timing-weakening: no shared mutable state between test classes was found (finding 1), so there is nothing to clean up in `CameraCoachClosedLoopTests` setup/teardown, and adding a "reset everything" fixture would be exactly the unjustified global reset the row forbids. The only artifact of this task is this receipt.

## Proposed tracker row update (for the orchestrator)

Keep CAM-002 evidence-based **PARTIAL** with a re-scoped remainder:

1. At the next CAM-001 re-run (on the current tree + Xcode 27.0 toolchain), retire the blanket "12 order-dependent category-A" classification. Serial evidence above supports: 9 methods pass serially and in pairs; 1 method (`…SceneCutRejectsLatePreCutSampleAndRetries`) is a ~5% serial contention flake (resource class, not order class) — keep in serial blocking lanes; 2 pseudo-UI methods are isolation reds needing a NEW bounded task (stale oracle vs regression of the accepted UI slices) — they leave category A entirely; iPad diagnostic stays env-gated.
2. Serial mode (`-parallel-testing-enabled NO`) remains the canonical lane for all A-family-adjacent lanes (already the matrix rule).
3. The durable fix for finding 2 belongs to a production-owned task (prepare/serialize the heavy-model first use, or a low-queue drain hook for tests) — deliberately not attempted here to keep the CAM-009 diff boundaries intact.

## Commands

```bash
DST='id=1F680A42-CEB3-43E8-9CED-52F874962A62'
DD=/private/tmp/setos-cam002/dd
# 1) Pods prebuild (Xcode 27.0 drift workaround, no file changes):
xcodebuild -workspace shafinMultitool.xcworkspace -scheme Pods-shafinMultitool \
  -sdk iphonesimulator -destination "$DST" -derivedDataPath "$DD" \
  IPHONEOS_DEPLOYMENT_TARGET=15.0 build
# 2) every lane: -project + serial, e.g. the p5 pair:
xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool \
  -sdk iphonesimulator -destination "$DST" -derivedDataPath "$DD" \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -collect-test-diagnostics never \
  -only-testing:shafinMultitoolTests/CameraTorchTests \
  -only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testCaptureMotionHysteresisRejectsStillButUnstableFrame \
  … (6 capture-path selectors) … test
# 3) M1 verification lane: exactly the mask in docs/implementation/test-command-matrix-v1.md §3 (M1), serial
```

Raw logs from this bisection lived in `/private/tmp/setos-cam002/logs/` (r00, p1–p6, q1–q4, a4-1…4, f1–f4, g1, m1-lane, pods-prebuild) and were removed with the scratch directory after this receipt, per the owner's disk rule. This receipt is the durable record; no raw-log claims in it go beyond what is quoted above.

## Limits / what this does NOT claim

- No full suite was re-run; CAM-001's 2 358-test baseline has still never been re-verified on Xcode 27.0 (finding 2's flake rate is a 20-execution estimate for one method, not a suite statistic).
- The scene-cut contention flake (1/20) is recorded as evidence, not fixed; it remains release-gated exactly as before (serial blocking lane).
- Finding 3's root cause (which accepted slice moved the pause-review advice) is deliberately unclassified here — that is the owning UI task's decision, made against its own diff.
- The tracker row was not edited (orchestrator owns the tracker); the proposal above is advisory.
