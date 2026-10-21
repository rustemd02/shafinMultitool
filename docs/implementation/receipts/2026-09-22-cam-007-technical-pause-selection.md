# CAM-007 — technical pause action selection receipt

Date: 2026-09-22. HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee` (branch `store`). The working tree was already dirty, including a large user-owned `AnalysisPipeline.swift` diff and documentation changes; those changes were preserved. No staging, commit, branch, reset, clean, stash, or worktree operation was performed.

## Evidence

- **Exact command:**
  `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' -derivedDataPath /private/tmp/setos-cam001/dd -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -collect-test-diagnostics never -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testPauseStylePreservationCannotReopenGoodWithoutCurrentTechnicalMeasurement -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayMapsDominantHotspotToSemanticAction -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayWithholdsFrontFillWithoutGroundedSubjectRegion -only-testing:shafinMultitoolTests/CameraCloudPauseIntegrationTests/testTechnicalPauseAlsoWithholdsUnownedLightWithoutChangingMeasurement -only-testing:shafinMultitoolTests/CameraBoundedActionPlannerTests/testAlternativeGroupYieldsExactlyOneExecutableStep test`
- **Result:** exit `0`; `** TEST SUCCEEDED **`.
- **Per-test result:** `AnalysisPipelinePresentationTests.testPauseStylePreservationCannotReopenGoodWithoutCurrentTechnicalMeasurement` passed; `AnalysisPipelinePresentationTests.testStillImageReplayMapsDominantHotspotToSemanticAction` passed; `AnalysisPipelinePresentationTests.testStillImageReplayWithholdsFrontFillWithoutGroundedSubjectRegion` passed; `CameraCloudPauseIntegrationTests.testTechnicalPauseAlsoWithholdsUnownedLightWithoutChangingMeasurement` passed; `CameraBoundedActionPlannerTests.testAlternativeGroupYieldsExactlyOneExecutableStep` passed. Total: 5 executed / 0 failures / 0 skipped.

## Contract result

- The technical pause production boundary calls `PauseActionRow.executableCommands(from:)` before publication, so one prioritized row is selected per alternative group.
- Overexposure hotspot/camera-angle rows are specific spatial advice. When the selected row has no valid `targetRegion`, the row is withheld; the selector does not fall through to a lower-priority alternative. The measured issue, verdict, trace, and explanation remain available, while the localized command is unavailable at the region boundary.
- Underexposure front-fill is emitted only with a non-degenerate `snapshot.subjectSignals.primaryCandidateRegion`. The positive cloud scene-control fixture proves one allowed front-fill row with a non-nil target; the still-replay 006 fixture has no grounded candidate region and therefore correctly withholds the action while retaining `increase_exposure` evidence.
- `waitForBackgroundClearance` is no longer constructed from clutter/object counts. No temporal-evidence type exists in this path, so no wait command is emitted.
- Scene-control permission filtering remains applied after technical row selection; unknown lighting continues to withhold front-fill without changing measurement, verdict, or confidence.

## Temporary space and verification boundary

The focused run reused existing `/private/tmp/setos-cam001/dd`; no new DerivedData directory or separately requested result bundle was created, and no historical temp/evidence was deleted. `git diff --check` was run on the owned source, tests, tracker row, and receipt and exited `0`.

## Residual risk

This is a focused five-test serial simulator verification. It does not add temporal evidence or invent a hotspot detector region, and it does not certify unrelated semantic pause actions or the broader test suite. A future specific technical command may only be emitted after its same-frame target region is grounded.
