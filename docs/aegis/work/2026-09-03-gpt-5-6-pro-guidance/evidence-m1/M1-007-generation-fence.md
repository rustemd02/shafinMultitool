# M1-007 — AnalysisPipeline session generation and cancellation boundary

Task: Give AnalysisPipeline an explicit session generation and cancellation boundary independent
of UI recomposition.
Owner boundary: `AnalysisPipelineOwner`. No production change required — the fence exists and its
dedicated suite (AnalysisPipelineReleaseTests, 17/17) ran green this session
(xcresult /private/tmp/shafin-m1-007.xcresult, fresh-boot run).

## Fence (AnalysisPipeline.swift)

`lifecycleGeneration` + `acquireFrameGeneration(requiresRegistration:)` + `isGenerationCurrent(_)`
re-checked after every await; install-guards for live/pause/pause-neural task slots
(`acceptsFrameWork && lifecycleGeneration == generation`); release captures `releaseGeneration`
and invalidates queued presentation; superseded start during release keeps replacement
registrations.

## Coverage (all green this run)

- testNewerHighEvidenceCannotBeReplacedByOlderEvidence — out-of-order evidence dropped
- testSuspendedLiveFusionCannotPublishAfterFrameReplacement — stale output never reaches presentation
- testSupersededStartDuringReleaseKeepsReplacementRegistrations — rollover across release
- testingEnqueueLivePresentationForGeneration(staleGeneration, …) — injected stale-generation publication rejected
- testReleaseInvalidatesQueuedPresentation…, testReleaseCancelsAndClearsAllOwnedTaskSlots,
  testRegisterDuringReleaseIsRejectedAndSecondReleaseHasTerminalBoundary,
  testTypedPauseResultDistinguishesMissingEvidenceAndStaleCancellation, + 9 more

## Registered side-findings (out of M1-007 scope; see EXECUTION_STATE known failures)

AnalysisPipelinePresentationTests: 41 failures, two baseline causes, neither related to fencing:
1. ~20 still-image replay tests — missing DeviceBenchmark fixture images (93 of 240 numbered
   images absent from camera_device_benchmark_pack_v1/images, e.g. 011-015, 190). Data
   restoration is an owner action; tests cannot pass on this checkout.
2. ~21 demo/semantic whitelist tests — semantic tip behavior drift vs fixture expectations
   (e.g. shift_frame_* appearing in live hints). Product-scope (M2 semantic tip taxonomy).
