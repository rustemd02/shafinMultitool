# M2-031 immutable pause/resume

- Date: 2026-09-05
- Branch: `codex/set-os-m2-031-pause`
- Worktree: `/Users/unterlantas/.codex/worktrees/shafinMultitool/m2-031-pause`
- Base: `1b5b9e3`
- Scope: one accepted pause snapshot owns the displayed pixels, typed linked evidence, deterministic Why/Decision Trace projection and marker until a successful resume restart.

## Implementation

- `AnalysisPipeline.swift` adds the optional typed `CameraLinkedEvidenceProjection` to `PauseCritiquePresentation`. Pause presentation construction derives it only from the accepted critique frame, one rendered action row and one known issue with observed structured evidence. Refinement merges bounded text while carrying the original projection unchanged.
- `PauseReasoningCoordinator.swift` preserves the draft projection when applying a text patch; provider output cannot replace frame/action/issue/evidence identity, and existing request/frame validation still rejects stale responses.
- `DecisionTracePresentation.swift` validates the pause projection before emitting deterministic Why, evidence and action linkage. Missing or mismatched provenance remains empty; validation is bound to `critique.actions.first`, so a later observed action cannot stand in for an unproven primary row.
- `SETCameraCoachProductionView.swift` validates the accepted snapshot ID, critique, action, issue and deterministic explanation before deriving the pause marker region; rotation only reprojects the accepted geometry.
- `CameraViewModel.swift` keeps the accepted review across a fully committed background transition, cancels/fails pre-commit pause work, invalidates pause work on resume, preserves review/configuration through restart, and clears pause output only after a successful restart. A failed resume now reconciles `.resuming` to a recoverable paused `.failure` while retaining the accepted display snapshot and critique.
- Focused tests cover projection identity/refinement, mixed primary/secondary evidence fail-closed behavior, stale publication fencing, pre-commit cancellation, committed background preservation, resume success/failure boundaries, portrait↔landscape marker reprojection and deterministic trace output.

## Verification

All simulator runs below used only iPhone 17e / iOS 26.5, device UUID `1F680A42-CEB3-43E8-9CED-52F874962A62`, sequentially, with `CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never`.

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' -only-testing:shafinMultitoolTests/LatestFrameEvidenceStoreTests -derivedDataPath /private/tmp/setos-m2-031-pause-dd-store -resultBundlePath /private/tmp/setos-m2-031-pause-store.xcresult CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' -only-testing:shafinMultitoolTests/AnalysisPipelineReleaseTests -derivedDataPath /private/tmp/setos-m2-031-pause-dd-release -resultBundlePath /private/tmp/setos-m2-031-pause-release.xcresult CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testPauseActionConfidenceIsCappedByPlanAndLinkedIssue -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testPauseActionConfidenceCanUseSemanticTipIssueScope -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testGoodPauseVerdictWithExplicitStrengthUsesHighConfidenceFloor -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testGoodPauseVerdictWithoutStrengthKeepsConservativeConfidence -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testMixedPauseCorrectiveVerdictConfidenceIsCappedToMedium -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testPausePresentationKeepsActionIssueAndTraceOnOneFrameProjection -derivedDataPath /private/tmp/setos-m2-031-pause-dd-pause-methods -resultBundlePath /private/tmp/setos-m2-031-pause-pause-methods.xcresult CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' -only-testing:shafinMultitoolTests/PauseReasoningCoordinatorTests -derivedDataPath /private/tmp/setos-m2-031-pause-dd-reasoning -resultBundlePath /private/tmp/setos-m2-031-pause-reasoning.xcresult CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' -only-testing:shafinMultitoolTests/CameraViewModelLifecycleTests -derivedDataPath /private/tmp/setos-m2-031-pause-dd-lifecycle-final -resultBundlePath /private/tmp/setos-m2-031-pause-lifecycle-final.xcresult CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' -only-testing:shafinMultitoolTests/DecisionTracePresentationTests -derivedDataPath /private/tmp/setos-m2-031-pause-dd-trace-final -resultBundlePath /private/tmp/setos-m2-031-pause-trace-final.xcresult CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' -only-testing:shafinMultitoolTests/SETDesignSystemTokenTests -derivedDataPath /private/tmp/setos-m2-031-pause-dd-tokens-final -resultBundlePath /private/tmp/setos-m2-031-pause-tokens-final.xcresult CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' -only-testing:shafinMultitoolUITests/CameraCoachProductionUITests/testProductionPauseTransitionAndResumeRoute -only-testing:shafinMultitoolUITests/CameraCoachProductionUITests/testPauseLoadingSuccessEmptyFailureMatrix -derivedDataPath /private/tmp/setos-m2-031-pause-dd-ui -resultBundlePath /private/tmp/setos-m2-031-pause-ui.xcresult CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never
```

Result bundles and counts:

- `/private/tmp/setos-m2-031-pause-store.xcresult`: 6/6 passed, 0 skipped.
- `/private/tmp/setos-m2-031-pause-release.xcresult`: 18/18 passed, 0 skipped.
- `/private/tmp/setos-m2-031-pause-pause-methods.xcresult`: 6/6 passed, 0 skipped.
- `/private/tmp/setos-m2-031-pause-reasoning.xcresult`: 20/20 passed, 0 skipped.
- `/private/tmp/setos-m2-031-pause-lifecycle-final.xcresult`: 16/16 passed, 0 skipped.
- `/private/tmp/setos-m2-031-pause-trace-final.xcresult`: 5/5 passed, 0 skipped.
- `/private/tmp/setos-m2-031-pause-tokens-final.xcresult`: 16/16 passed, 0 skipped.
- `/private/tmp/setos-m2-031-pause-ui.xcresult`: 2/2 passed, 0 skipped.

FIX-FIRST correction verification (all runs used only iPhone 17e / iOS 26.5, device UUID `1F680A42-CEB3-43E8-9CED-52F874962A62`, sequentially, with `CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never`):

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testPauseActionConfidenceIsCappedByPlanAndLinkedIssue -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testPauseActionConfidenceCanUseSemanticTipIssueScope -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testGoodPauseVerdictWithExplicitStrengthUsesHighConfidenceFloor -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testGoodPauseVerdictWithoutStrengthKeepsConservativeConfidence -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testMixedPauseCorrectiveVerdictConfidenceIsCappedToMedium -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testPausePresentationKeepsActionIssueAndTraceOnOneFrameProjection -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testPauseProjectionFailsClosedWhenOnlySecondaryActionHasObservedEvidence -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testCommittedPauseRotationReprojectsMarkerWithoutChangingProvenance -derivedDataPath /private/tmp/setos-m2-031-pause-fix-dd-pause-methods -resultBundlePath /private/tmp/setos-m2-031-pause-fix-pause-methods.xcresult CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' -only-testing:shafinMultitoolTests/CameraViewModelLifecycleTests -derivedDataPath /private/tmp/setos-m2-031-pause-fix-dd-lifecycle-final -resultBundlePath /private/tmp/setos-m2-031-pause-fix-lifecycle-final.xcresult CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' -only-testing:shafinMultitoolTests/AnalysisPipelineReleaseTests -derivedDataPath /private/tmp/setos-m2-031-pause-fix-dd-release -resultBundlePath /private/tmp/setos-m2-031-pause-fix-release.xcresult CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' -only-testing:shafinMultitoolTests/PauseReasoningCoordinatorTests -derivedDataPath /private/tmp/setos-m2-031-pause-fix-dd-reasoning -resultBundlePath /private/tmp/setos-m2-031-pause-fix-reasoning.xcresult CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' -only-testing:shafinMultitoolTests/DecisionTracePresentationTests -derivedDataPath /private/tmp/setos-m2-031-pause-fix-dd-trace -resultBundlePath /private/tmp/setos-m2-031-pause-fix-trace.xcresult CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' -only-testing:shafinMultitoolUITests/CameraCoachProductionUITests/testProductionPauseTransitionAndResumeRoute -only-testing:shafinMultitoolUITests/CameraCoachProductionUITests/testPauseLoadingSuccessEmptyFailureMatrix -derivedDataPath /private/tmp/setos-m2-031-pause-fix-dd-ui -resultBundlePath /private/tmp/setos-m2-031-pause-fix-ui.xcresult CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never
```

Correction result bundles:

- `/private/tmp/setos-m2-031-pause-fix-pause-methods.xcresult`: 8/8 passed, 0 skipped. This includes the primary-only mixed-evidence regression and portrait↔landscape accepted-frame/projection/marker test.
- `/private/tmp/setos-m2-031-pause-fix-lifecycle-final.xcresult`: 17/17 passed, 0 skipped, including failed-resume recovery and the existing successful-resume/configuration tests.
- `/private/tmp/setos-m2-031-pause-fix-release.xcresult`: 18/18 passed, 0 skipped.
- `/private/tmp/setos-m2-031-pause-fix-reasoning.xcresult`: 20/20 passed, 0 skipped.
- `/private/tmp/setos-m2-031-pause-fix-trace.xcresult`: 5/5 passed, 0 skipped.
- `/private/tmp/setos-m2-031-pause-fix-ui.xcresult`: 2/2 passed, 0 skipped; `testProductionPauseTransitionAndResumeRoute` rotates the committed pause review to landscape and back before resuming.

The first correction lifecycle run (`/private/tmp/setos-m2-031-pause-fix-lifecycle.xcresult`) was 16/17 because the synthetic blank-frame fixture legitimately produced no critique and the new test initially asserted one. The assertion was removed; the isolated corrected test (`/private/tmp/setos-m2-031-pause-fix-resume-retry.xcresult`) passed 1/1, followed by the final 17/17 class run. This was a test-fixture expectation correction, not a production failure.

The requested full `AnalysisPipelinePresentationTests` class was also run:

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests -derivedDataPath /private/tmp/setos-m2-031-pause-dd-presentation -resultBundlePath /private/tmp/setos-m2-031-pause-presentation.xcresult CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never
```

Its result was 63/103 passed, 40 failed, 0 skipped. Failure details were existing still-image replay expectation mismatches and missing untracked `DeviceBenchmark` images in this isolated worktree; the six task-owned pause methods above passed independently. No fixtures were copied and no unrelated baseline tests were changed.

Additional focused projection compile/run evidence: `/private/tmp/setos-m2-031-pause-projection.xcresult`, 1/1 passed.

`git diff --check`: passed.

## Judgment calls and boundaries

- The pause projection is optional and fail-closed. Technical/contextual/keep actions without one known observed issue do not receive Why/evidence/marker provenance.
- Background preservation is gated on both the accepted display image and a terminal pause state (`success`, `empty` or `failure`); loading work is canceled through the existing lifecycle failure path.
- Resume keeps the accepted review visible while the existing configured Camera session restarts. Only successful `startAndWait()` clears the review; failure leaves it inspectable.
- No unowned fixtures, project files, catalogs, IDs, or unrelated baseline logic were modified. No physical device or iPhone 17 Pro run was used.

## Gaps

- The full presentation class remains red only at the documented pre-existing replay/missing-fixture boundary; task-owned pause methods and all other selected classes pass.
- Device-only physical-camera behavior was not exercised; simulator evidence is complete for the bounded lifecycle and presentation contract.
