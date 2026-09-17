import CoreMedia
import CoreVideo
import XCTest
@testable import shafinMultitool

final class AnalysisPipelineReleaseTests: XCTestCase {

    func testRegisterTwiceKeepsExactlyOneThreeTokenSet() async {
        let (pipeline, manager, scheduler, _) = makeComponents()

        XCTAssertTrue(pipeline.register(with: manager))
        XCTAssertTrue(pipeline.register(with: manager))

        XCTAssertEqual(scheduler.registrationCountForTesting, 3)
        await pipeline.releaseAndWait()
    }

    func testReleaseUnregistersEveryTokenAndIsIdempotent() async {
        let (pipeline, manager, scheduler, _) = makeComponents()
        XCTAssertTrue(pipeline.register(with: manager))

        await pipeline.releaseAndWait()
        XCTAssertEqual(scheduler.registrationCountForTesting, 0)

        await pipeline.releaseAndWait()
        XCTAssertEqual(scheduler.registrationCountForTesting, 0)
    }

    func testReleaseThenRegisterCreatesOneFreshActiveSet() async {
        let (pipeline, manager, scheduler, _) = makeComponents()
        XCTAssertTrue(pipeline.register(with: manager))
        await pipeline.releaseAndWait()

        XCTAssertTrue(pipeline.register(with: manager))
        XCTAssertEqual(scheduler.registrationCountForTesting, 3)

        await pipeline.releaseAndWait()
    }

    func testReleaseClearsFrameAndFeatureEvidenceBeforeFreshRegistration() async {
        let (pipeline, manager, _, _) = makeComponents()

        pipeline.ingestHigh(context: makeFrameContext(timestamp: 1.0, orientation: .up, isStable: true))
        let receivedFirstFrame = await waitUntil {
            pipeline.testingLatestFrameEvidence?.sourceFrameId == "frame_1000"
                && pipeline.testingFeatureEvidenceSampleCount > 0
        }
        XCTAssertTrue(receivedFirstFrame)

        await pipeline.releaseAndWait()

        XCTAssertNil(pipeline.testingLatestFrameEvidence)
        XCTAssertEqual(pipeline.testingFeatureEvidenceSampleCount, 0)

        XCTAssertTrue(pipeline.register(with: manager))
        XCTAssertNil(pipeline.testingLatestFrameEvidence)
        XCTAssertEqual(pipeline.testingFeatureEvidenceSampleCount, 0)

        var completedWithoutEvidence = false
        pipeline.runPauseAnalysis { suggestions, critique in
            completedWithoutEvidence = true
            XCTAssertTrue(suggestions.isEmpty)
            XCTAssertNil(critique)
        }
        XCTAssertTrue(completedWithoutEvidence)

        pipeline.ingestHigh(context: makeFrameContext(timestamp: 2.0, orientation: .left, isStable: false))
        let receivedFreshFrame = await waitUntil {
            guard let evidence = pipeline.testingLatestFrameEvidence else { return false }
            return evidence.sourceFrameId == "frame_2000"
                && evidence.orientation == .left
                && !evidence.isStable
                && pipeline.testingFeatureEvidenceSampleCount > 0
        }
        XCTAssertTrue(receivedFreshFrame)

        await pipeline.releaseAndWait()
    }

    func testHighEvidencePreservesCallbackCaptureTimeAndAdapterState() async {
        let (pipeline, _, _, _) = makeComponents()
        let capturedAt = Date()

        pipeline.ingestHigh(context: makeFrameContext(capturedAt: capturedAt, captureGeneration: 23))

        let receivedFrame = await waitUntil {
            pipeline.testingLatestFrameEvidence?.sourceFrameId == "frame_1000"
        }
        XCTAssertTrue(receivedFrame)
        XCTAssertEqual(pipeline.testingLatestFrameEvidence?.capturedAt, capturedAt)
        XCTAssertEqual(pipeline.testingLatestFrameEvidence?.lensGeneration, 23)
        XCTAssertEqual(pipeline.testingLatestFrameEvidence?.makeEnvelope().lensGeneration, 23)
        XCTAssertNotNil(pipeline.testingLatestFrameEvidence?.adapterState)

        await pipeline.releaseAndWait()
    }

    func testOlderCaptureGenerationCannotReplaceNewLensEvidence() async {
        let (pipeline, _, _, _) = makeComponents()
        let firstCapturedAt = Date()

        pipeline.ingestHigh(context: makeFrameContext(
            timestamp: 2,
            orientation: .up,
            capturedAt: firstCapturedAt,
            captureGeneration: 8
        ))
        let receivedNewGeneration = await waitUntil {
            pipeline.testingLatestFrameEvidence?.lensGeneration == 8
        }
        XCTAssertTrue(receivedNewGeneration)

        pipeline.ingestHigh(context: makeFrameContext(
            timestamp: 3,
            orientation: .right,
            capturedAt: firstCapturedAt.addingTimeInterval(1),
            captureGeneration: 7
        ))
        await pipeline.testingDrainHighQueue()

        XCTAssertEqual(pipeline.testingLatestFrameEvidence?.sourceFrameId, "frame_2000")
        XCTAssertEqual(pipeline.testingLatestFrameEvidence?.orientation, .up)
        XCTAssertEqual(pipeline.testingLatestFrameEvidence?.lensGeneration, 8)
        await pipeline.releaseAndWait()
    }

    func testNewerHighEvidenceCannotBeReplacedByOlderEvidence() async {
        let (pipeline, _, _, _) = makeComponents()
        let newerCapturedAt = Date()
        let olderCapturedAt = newerCapturedAt.addingTimeInterval(-1.0)

        pipeline.ingestHigh(
            context: makeFrameContext(
                timestamp: 2.0,
                orientation: .up,
                capturedAt: newerCapturedAt
            )
        )
        let receivedNewerFrame = await waitUntil {
            pipeline.testingLatestFrameEvidence?.sourceFrameId == "frame_2000"
        }
        XCTAssertTrue(receivedNewerFrame)

        let newerFeatures = pipeline.currentFeatures
        let newerVisionMeasuredAt = pipeline.currentDebugData.visionMeasuredAt

        pipeline.ingestHigh(
            context: makeFrameContext(
                timestamp: 1.0,
                orientation: .left,
                capturedAt: olderCapturedAt
            )
        )

        await pipeline.testingDrainHighQueue()
        let evidence = pipeline.testingLatestFrameEvidence
        XCTAssertEqual(evidence?.sourceFrameId, "frame_2000")
        XCTAssertEqual(evidence?.orientation, .up)
        XCTAssertEqual(evidence?.capturedAt, newerCapturedAt)

        let featuresAfterOlder = pipeline.currentFeatures
        XCTAssertEqual(featuresAfterOlder.horizon.angle, newerFeatures.horizon.angle)
        XCTAssertEqual(featuresAfterOlder.horizon.confidence, newerFeatures.horizon.confidence)
        XCTAssertEqual(featuresAfterOlder.motion.shakeLevel, newerFeatures.motion.shakeLevel)
        XCTAssertEqual(featuresAfterOlder.subject.count, newerFeatures.subject.count)
        XCTAssertEqual(pipeline.currentDebugData.visionMeasuredAt, newerVisionMeasuredAt)

        await pipeline.releaseAndWait()
    }

    @MainActor
    func testSuspendedLiveFusionCannotPublishAfterFrameReplacement() async {
        let fusionGate = SuspendingNeuralEvidenceGate()
        let provider = MockNeuralEvidenceProvider { request in
            try await fusionGate.infer(request: request)
        }
        let service = NeuralEvidenceInferenceService(
            configuration: makeLiveNeuralEvidenceConfiguration(),
            provider: provider
        )
        let (pipeline, _, _, _) = makeComponents(
            neuralEvidenceService: service,
            liveHybridFusionEnabled: true
        )
        defer { fusionGate.releaseAll() }

        pipeline.ingestHigh(
            context: makeFrameContext(
                timestamp: 1.0,
                capturedAt: Date()
            )
        )
        let firstFusionStarted = await waitUntil {
            fusionGate.hasRequestedFrame("frame_1000")
        }
        XCTAssertTrue(firstFusionStarted)

        pipeline.ingestHigh(
            context: makeFrameContext(
                timestamp: 2.0,
                capturedAt: Date()
            )
        )
        let replacementPublished = await waitUntil {
            pipeline.testingLatestFrameEvidence?.sourceFrameId == "frame_2000"
        }
        XCTAssertTrue(replacementPublished)
        let replacementFusionStarted = await waitUntil {
            fusionGate.hasRequestedFrame("frame_2000")
        }
        XCTAssertTrue(replacementFusionStarted)

        // Frame 2 is still suspended, so these values are the complete
        // presentation baseline immediately before the stale frame resumes.
        let hintBeforeResume = pipeline.currentLiveHint
        let suggestionBeforeResume = pipeline.currentSuggestion
        let annotationsBeforeResume = pipeline.currentOverlayAnnotations
        let traceBeforeResume = pipeline.testingLiveFusionTraceBundle

        fusionGate.release(frameId: "frame_1000")
        let staleFusionFinished = await waitUntil {
            fusionGate.hasCompletedFrame("frame_1000")
        }
        XCTAssertTrue(staleFusionFinished)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(pipeline.currentLiveHint, hintBeforeResume)
        XCTAssertEqual(pipeline.currentSuggestion, suggestionBeforeResume)
        XCTAssertEqual(pipeline.currentOverlayAnnotations, annotationsBeforeResume)
        XCTAssertEqual(pipeline.testingLiveFusionTraceBundle, traceBeforeResume)

        fusionGate.releaseAll()
        await pipeline.releaseAndWait()
    }

    func testTypedPauseResultDistinguishesMissingEvidenceAndStaleCancellation() async {
        let (pipeline, manager, _, _) = makeComponents()
        var missingResult: PauseAnalysisResult?
        pipeline.runPauseAnalysisResult(acceptedSnapshot: nil) { result, _, _ in
            missingResult = result
        }
        XCTAssertEqual(missingResult, .failure(.noAcceptedEvidence))

        await pipeline.releaseAndWait()
        var staleResult: PauseAnalysisResult?
        pipeline.runPauseAnalysisResult(acceptedSnapshot: nil) { result, _, _ in
            staleResult = result
        }
        XCTAssertEqual(staleResult, .cancelled)
        _ = manager
    }

    func testPauseTimeoutWinsExactlyOnceAndDoesNotBecomeEmpty() async {
        let (pipeline, manager, _, _) = makeComponents()
        XCTAssertTrue(pipeline.register(with: manager))
        pipeline.ingestHigh(context: makeFrameContext(timestamp: 8.0))
        let receivedFrame = await waitUntil {
            pipeline.testingLatestFrameEvidence?.sourceFrameId == "frame_8000"
        }
        XCTAssertTrue(receivedFrame)
        guard let acceptedSnapshot = pipeline.acceptPauseSnapshot() else {
            return XCTFail("pause test requires an accepted frame")
        }

        var results: [PauseAnalysisResult] = []
        pipeline.runPauseAnalysisResult(
            acceptedSnapshot: acceptedSnapshot,
            timeoutNanoseconds: 1
        ) { result, _, _ in
            results.append(result)
        }

        let completed = await waitUntil {
            results.count == 1
        }
        XCTAssertTrue(completed)
        XCTAssertEqual(results, [.failure(.timeout)])

        // Keep the underlying work alive for a bounded window. A late
        // callback must be fenced rather than publishing a critique or
        // annotations after the timeout result has already won.
        let timeoutObservedAt = ContinuousClock.now
        let lateWorkSettled = await waitUntil {
            results.count == 1
                && ContinuousClock.now >= timeoutObservedAt.advanced(by: .milliseconds(250))
        }
        XCTAssertTrue(lateWorkSettled)
        XCTAssertEqual(results.count, 1)
        XCTAssertNil(pipeline.currentPauseCritique)
        XCTAssertTrue(pipeline.currentOverlayAnnotations.isEmpty)
        await pipeline.releaseAndWait()
    }

    func testPauseTimeoutClaimsBeforeLateTerminalPublication() async {
        let (pipeline, manager, _, _) = makeComponents()
        XCTAssertTrue(pipeline.register(with: manager))
        pipeline.ingestHigh(context: makeFrameContext(timestamp: 10.0))
        let receivedFrame = await waitUntil {
            pipeline.testingLatestFrameEvidence?.sourceFrameId == "frame_10000"
        }
        XCTAssertTrue(receivedFrame)
        guard let acceptedSnapshot = pipeline.acceptPauseSnapshot() else {
            return XCTFail("pause test requires an accepted frame")
        }

        let hookState = PauseClaimHookState()
        pipeline.testingSetPauseAnalysisBeforeTerminalClaimHook {
            hookState.enterAndWait()
        }
        defer {
            hookState.release()
            pipeline.testingSetPauseAnalysisBeforeTerminalClaimHook(nil)
        }

        var results: [PauseAnalysisResult] = []
        pipeline.runPauseAnalysisResult(
            acceptedSnapshot: acceptedSnapshot,
            timeoutNanoseconds: 5_000_000_000
        ) { result, _, _ in
            results.append(result)
        }

        let hookEntered = await waitUntil { hookState.hasEntered }
        XCTAssertTrue(hookEntered)
        pipeline.testingTriggerPauseAnalysisTimeout()
        hookState.release()

        let completed = await waitUntil { results.count == 1 }
        XCTAssertTrue(completed)
        XCTAssertEqual(results, [.failure(.timeout)])
        XCTAssertNil(pipeline.currentPauseCritique)
        XCTAssertTrue(pipeline.currentOverlayAnnotations.isEmpty)
        await pipeline.releaseAndWait()
    }

    func testTypedPauseResultReportsPipelineUnavailableSeparatelyFromEmpty() {
        let store = LatestFrameEvidenceStore()
        let pixelBuffer = makeFrameContext(timestamp: 9.0).pixelBuffer
        XCTAssertTrue(store.publish(
            pixelBuffer: pixelBuffer,
            orientation: .up,
            sourceFrameId: "pipeline-unavailable-frame",
            capturedAt: Date(),
            isStable: true
        ))
        guard let acceptedSnapshot = store.acceptCurrentSnapshot() else {
            return XCTFail("pause test requires an accepted frame")
        }
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil,
            neuralHeavyModelsEnabledProvider: { true },
            pauseAnalysisAvailabilityProvider: { false }
        )
        var result: PauseAnalysisResult?
        pipeline.runPauseAnalysisResult(acceptedSnapshot: acceptedSnapshot) { pauseResult, _, _ in
            result = pauseResult
        }
        XCTAssertEqual(result, .failure(.pipelineUnavailable))
    }

    @MainActor
    func testReleaseInvalidatesQueuedPresentationAndClearsLivePauseAndOverlayState() async {
        let (pipeline, manager, scheduler, _) = makeComponents()
        XCTAssertTrue(pipeline.register(with: manager))

        let candidate = makeLiveHint()
        pipeline.testingApplyLiveHintCandidate(candidate)
        pipeline.testingPreparePauseState(
            critique: makePauseCritique(),
            traceBundle: ExplainabilityTraceBundle(
                frameId: "pause-frame",
                mode: .pause,
                items: [],
                rootSummaryIds: []
            ),
            revision: 1,
            overlayAnnotations: [
                OverlayAnnotationPresentation(
                    id: "overlay-1",
                    kind: .regionHighlight,
                    direction: nil,
                    targetRegion: nil,
                    emphasis: 0.8,
                    tone: .warning,
                    label: "test"
                )
            ]
        )

        let staleGeneration = pipeline.testingLifecycleGeneration
        pipeline.testingEnqueueLivePresentation(candidate)
        await pipeline.releaseAndWait()

        XCTAssertEqual(scheduler.registrationCountForTesting, 0)
        XCTAssertNil(pipeline.currentLiveHint)
        XCTAssertNil(pipeline.currentPauseCritique)
        XCTAssertTrue(pipeline.currentOverlayAnnotations.isEmpty)

        pipeline.testingEnqueueLivePresentationForGeneration(staleGeneration,
                                                              candidate: candidate)
        await Task.yield()

        XCTAssertNil(pipeline.currentLiveHint)
        XCTAssertNil(pipeline.currentPauseCritique)
        XCTAssertTrue(pipeline.currentOverlayAnnotations.isEmpty)
    }

    func testReleaseCancelsAndClearsAllOwnedTaskSlots() async {
        let (pipeline, manager, _, _) = makeComponents()
        XCTAssertTrue(pipeline.register(with: manager))
        pipeline.testingStartOwnedCancellableTasks()

        XCTAssertEqual(pipeline.testingOwnedTaskCount, 3)

        await pipeline.releaseAndWait()

        XCTAssertEqual(pipeline.testingOwnedTaskCount, 0)
        XCTAssertFalse(pipeline.testingHasPauseReasoningTask)
        XCTAssertFalse(pipeline.testingHasLiveNeuralInferenceTask)
        XCTAssertFalse(pipeline.testingHasPauseNeuralInferenceTask)
    }

    @MainActor
    func testViewModelReleaseStopsCaptureBeforePipelineReleaseAndCanResume() async {
        let (pipeline, manager, scheduler, runner) = makeComponents()
        runner.onStop = {
            runner.schedulerRegistrationCountAtStop = scheduler.registrationCountForTesting
        }
        let viewModel = CameraViewModel(cameraManager: manager, analysisPipeline: pipeline)

        await viewModel.startAndWait()
        XCTAssertEqual(runner.startCount, 1)
        XCTAssertTrue(runner.isRunning)
        XCTAssertEqual(manager.lifecycleState, .running)
        XCTAssertEqual(scheduler.registrationCountForTesting, 3)

        await viewModel.releaseAndWait()

        XCTAssertEqual(runner.schedulerRegistrationCountAtStop, 3)
        XCTAssertEqual(runner.stopCount, 1)
        XCTAssertEqual(scheduler.registrationCountForTesting, 0)
        XCTAssertEqual(manager.configurationState, .unconfigured)
        XCTAssertEqual(viewModel.lifecycleState, .idle)

        await viewModel.startAndWait()

        XCTAssertEqual(scheduler.registrationCountForTesting, 3)
        XCTAssertEqual(runner.startCount, 2)
        XCTAssertEqual(viewModel.lifecycleState, .running)

        await viewModel.releaseAndWait()
    }

    @MainActor
    func testSupersededStartDuringReleaseKeepsReplacementRegistrations() async {
        let (pipeline, manager, scheduler, runner) = makeComponents()
        let viewModel = CameraViewModel(cameraManager: manager, analysisPipeline: pipeline)

        await viewModel.startAndWait()
        XCTAssertEqual(runner.startCount, 1)
        XCTAssertTrue(runner.isRunning)
        XCTAssertEqual(manager.lifecycleState, .running)
        XCTAssertEqual(scheduler.registrationCountForTesting, 3)

        let drainGate = DispatchSemaphore(value: 0)
        scheduler.setDrainGateForTesting(drainGate)

        let release = Task { @MainActor in
            await viewModel.releaseAndWait()
        }
        var releaseStarted = false
        for _ in 0..<1_000 {
            if pipeline.testingReleaseInProgress {
                releaseStarted = true
                break
            }
            await Task.yield()
        }
        XCTAssertTrue(releaseStarted)

        viewModel.start()
        viewModel.start()
        drainGate.signal()

        await release.value
        scheduler.setDrainGateForTesting(nil)

        let replacementRunning = await waitUntil {
            runner.startCount == 2
                && scheduler.registrationCountForTesting == 3
                && viewModel.lifecycleState == .running
        }

        XCTAssertTrue(replacementRunning)
        XCTAssertEqual(runner.startCount, 2)
        XCTAssertEqual(scheduler.registrationCountForTesting, 3)
        XCTAssertEqual(viewModel.lifecycleState, .running)

        await viewModel.releaseAndWait()
    }

    func testDirectSceneIngestRemainsAcceptedUntilFullRelease() async {
        let (pipeline, _, _, _) = makeComponents()

        pipeline.ingestHigh(context: makeFrameContext())
        XCTAssertEqual(pipeline.testingDirectFrameAcceptanceCount, 1)

        await pipeline.releaseAndWait()

        pipeline.ingestHigh(context: makeFrameContext())
        XCTAssertEqual(pipeline.testingDirectFrameAcceptanceCount, 1)
    }

    func testRegisterDuringReleaseIsRejectedAndSecondReleaseHasTerminalBoundary() async {
        let (pipeline, manager, scheduler, _) = makeComponents()
        XCTAssertTrue(pipeline.register(with: manager))

        let drainGate = DispatchSemaphore(value: 0)
        scheduler.setDrainGateForTesting(drainGate)

        let pipelineRelease = Task { await pipeline.releaseAndWait() }
        var releaseStarted = false
        for _ in 0..<1_000 {
            if pipeline.testingReleaseInProgress {
                releaseStarted = true
                break
            }
            await Task.yield()
        }
        XCTAssertTrue(releaseStarted)

        XCTAssertFalse(pipeline.register(with: manager))

        let secondRelease = Task { await pipeline.releaseAndWait() }
        drainGate.signal()

        await pipelineRelease.value
        await secondRelease.value

        XCTAssertEqual(scheduler.registrationCountForTesting, 0)
        scheduler.setDrainGateForTesting(nil)

        XCTAssertTrue(pipeline.register(with: manager))
        XCTAssertEqual(scheduler.registrationCountForTesting, 3)
        await pipeline.releaseAndWait()
        XCTAssertEqual(scheduler.registrationCountForTesting, 0)
    }


    @MainActor
    func testDelayedDetectorSeedMeasuresCurrentPixelsBeforeFrozenSnapshotAndOverlay() async {
        let pipeline = makeObjectTrackingPipeline()
        let measuredBox = CGRect(x: 0.55, y: 0.25, width: 0.2, height: 0.3)
        let sequence = PipelineObjectTrackingSequence(box: measuredBox)
        pipeline.testingSetObjectTrackingSequenceFactory { _ in sequence }
        let source = makeObjectTrackingContext(timestamp: 10, capturedAt: Date().addingTimeInterval(-0.1))
        let f2 = makeObjectTrackingContext(timestamp: 10.1)
        pipeline.ingestHigh(context: f2)
        await pipeline.testingDrainHighQueue()
        let frozenF2 = pipeline.testingLatestFrameEvidence
        XCTAssertEqual(frozenF2?.sourceFrameId, "frame_10100")
        XCTAssertNil(frozenF2?.adapterState?.detr)

        pipeline.testingDeliverLiveDetrSeed([DETRDetection(
            boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.3),
            label: "chair", confidence: 0.24)], context: source)
        let f3 = makeObjectTrackingContext(timestamp: 10.2)
        pipeline.ingestHigh(context: f3)
        await pipeline.testingDrainHighQueue()
        let published = await waitUntil {
            pipeline.overlayState.primaryBoundingBox == measuredBox
        }
        XCTAssertTrue(published)
        let sample = pipeline.testingLatestFrameEvidence?.adapterState?.detr
        XCTAssertNil(frozenF2?.adapterState?.detr, "late callback must not mutate F2")
        XCTAssertEqual(sample?.provenance?.frameID, "frame_10200")
        XCTAssertEqual(sample?.value.tracking?.source.frameID, "frame_10000")
        XCTAssertEqual(sample?.value.tracking?.current.frameID, "frame_10200")
        XCTAssertEqual(sample?.measuredAt, source.capturedAt, "tracking cannot renew semantic age")
        XCTAssertEqual(sample?.value.detections.first?.confidence ?? 0, Double(Float(0.24)), accuracy: 0.000001)
        XCTAssertEqual(sample?.value.detections.first?.boundingBox, measuredBox)
        XCTAssertEqual(sequence.pixels, [
            ObjectIdentifier(source.pixelBuffer as AnyObject),
            ObjectIdentifier(f3.pixelBuffer as AnyObject)
        ], "prime on F1; measure F3; never use F2 or relabel the seed box")
        XCTAssertEqual(pipeline.testingPresentedObjectFrame?.frameID, "frame_10200")
        XCTAssertNil(pipeline.currentLiveHint, "tracking does not manufacture calibrated action evidence")

        // The newer detector batch is empty after unchanged production filters.
        // An older positive callback must not revive it.
        let empty = makeObjectTrackingContext(timestamp: 10.3)
        pipeline.testingDeliverLiveDetrSeed([
            DETRDetection(boundingBox: measuredBox, label: "chair", confidence: 0.1),
            DETRDetection(boundingBox: measuredBox, label: "wall (other)", confidence: 1)
        ], context: empty)
        pipeline.testingDeliverLiveDetrSeed([DETRDetection(
            boundingBox: measuredBox, label: "chair", confidence: 0.9)], context: source)
        pipeline.ingestHigh(context: makeObjectTrackingContext(timestamp: 10.4))
        await pipeline.testingDrainHighQueue()
        let cleared = await waitUntil { pipeline.overlayState.primaryBoundingBox == nil }
        XCTAssertTrue(cleared)
        XCTAssertNil(pipeline.testingLatestFrameEvidence?.adapterState?.detr)
        XCTAssertTrue(pipeline.currentDebugData.detrDetections.isEmpty)
        XCTAssertEqual(sequence.pixels.count, 2, "empty barrier cannot track an old rectangle")
        XCTAssertNil(pipeline.currentLiveHint, "no detection must not become a good-frame claim")
        await pipeline.releaseAndWait()
    }

    func testOldDetectorCallbackCannotCrossReleaseAndRegisterWithReusedCameraIDs() async {
        let pipeline = makeObjectTrackingPipeline()
        let (_, manager, _, _) = makeComponents()
        let sequence = PipelineObjectTrackingSequence(box: CGRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2))
        pipeline.testingSetObjectTrackingSequenceFactory { _ in sequence }
        XCTAssertTrue(pipeline.register(with: manager))
        let oldGeneration = pipeline.testingLifecycleGeneration
        let oldSource = makeObjectTrackingContext(timestamp: 20, capturedAt: Date().addingTimeInterval(-0.1))
        await pipeline.releaseAndWait()
        XCTAssertTrue(pipeline.register(with: manager))

        pipeline.testingDeliverLiveDetrSeed([DETRDetection(
            boundingBox: sequence.box, label: "chair", confidence: 0.8)],
            context: oldSource, generation: oldGeneration)
        pipeline.ingestHigh(context: makeObjectTrackingContext(timestamp: 20.1))
        await pipeline.testingDrainHighQueue()
        XCTAssertNil(pipeline.testingLatestFrameEvidence?.adapterState?.detr)
        XCTAssertTrue(sequence.pixels.isEmpty, "late callback must fail inside the queued operation")

        let currentSource = makeObjectTrackingContext(timestamp: 20.2)
        pipeline.testingDeliverLiveDetrSeed([DETRDetection(
            boundingBox: sequence.box, label: "chair", confidence: 0.8)], context: currentSource)
        pipeline.ingestHigh(context: makeObjectTrackingContext(timestamp: 20.3))
        await pipeline.testingDrainHighQueue()
        XCTAssertNotNil(pipeline.testingLatestFrameEvidence?.adapterState?.detr)
        XCTAssertEqual(sequence.pixels.count, 2)
        await pipeline.releaseAndWait()
    }


    @MainActor
    func testTrackedObjectOverlayUsesEvaluatedSnapshotTargetWhenRankingsDisagree() async {
        let pipeline = makeObjectTrackingPipeline()
        let chair = CGRect(x: 0.02, y: 0.2, width: 0.3, height: 0.6)
        let cup = CGRect(x: 0.65, y: 0.2, width: 0.3, height: 0.6)
        let sequence = PipelineMultipleObjectTrackingSequence(boxes: [chair, cup])
        pipeline.testingSetObjectTrackingSequenceFactory { _ in sequence }
        pipeline.testingDeliverLiveDetrSeed([
            DETRDetection(boundingBox: chair, label: "chair", confidence: 0.9),
            DETRDetection(boundingBox: cup, label: "cup", confidence: 0.5)
        ], context: makeObjectTrackingContext(timestamp: 30, capturedAt: Date().addingTimeInterval(-0.1)))
        pipeline.ingestHigh(context: makeObjectTrackingContext(timestamp: 30.1))
        await pipeline.testingDrainHighQueue()
        let published = await waitUntil { pipeline.overlayState.primaryBoundingBox == cup }
        XCTAssertTrue(published, "composition ranking prefers chair, evaluated snapshot prefers cup")
        guard let evidence = pipeline.testingLatestFrameEvidence,
              let state = evidence.adapterState else {
            XCTFail("current frame must freeze measured object evidence")
            await pipeline.releaseAndWait()
            return
        }
        let input = PipelineFeatureSnapshotAdapter().makeInput(
            frameId: evidence.sourceFrameId, mode: .live, capturedAt: evidence.capturedAt, state: state)
        let snapshot = FeatureSnapshotAggregator().makeSnapshot(from: input)
        XCTAssertEqual(snapshot.subjectSignals.topObjectLabel, "cup")
        XCTAssertEqual(snapshot.subjectSignals.primaryCandidateRegion,
                       NormalizedRect(x: 0.65, y: 0.2, width: 0.3, height: 0.6))
        XCTAssertEqual(pipeline.currentFeatures.subject.objectName, "cup")
        XCTAssertEqual(pipeline.overlayState.primaryBoundingBox, cup)
        await pipeline.releaseAndWait()
    }

    @MainActor
    func testBoundedTrackingSubsetDoesNotClaimUniqueTapTarget() async {
        let pipeline = makeObjectTrackingPipeline()
        let boxes = (0..<5).map { CGRect(x: Double($0) * 0.15, y: 0.2, width: 0.1, height: 0.1) }
        let sequence = PipelineMultipleObjectTrackingSequence(boxes: Array(boxes.prefix(4)))
        pipeline.testingSetObjectTrackingSequenceFactory { _ in sequence }
        pipeline.testingDeliverLiveDetrSeed(boxes.map {
            DETRDetection(boundingBox: $0, label: "chair", confidence: 0.9)
        }, context: makeObjectTrackingContext(timestamp: 40, capturedAt: Date().addingTimeInterval(-0.1)))
        for timestamp in [40.1, 40.2, 40.3] {
            pipeline.ingestHigh(context: makeObjectTrackingContext(timestamp: timestamp))
            await pipeline.testingDrainHighQueue()
            let accepted = await waitUntil {
                pipeline.testingPresentedObjectFrame?.frameID == "frame_\(Int((timestamp * 1000).rounded()))"
            }
            XCTAssertTrue(accepted, "each tracked observation must reach its accepted presentation")
        }
        XCTAssertEqual(pipeline.testingPresentedObjectFrame?.frameID, "frame_40300")
        let tracking = pipeline.testingLatestFrameEvidence?.adapterState?.detr?.value.tracking
        XCTAssertEqual(tracking?.sourceCandidateCount, 5)
        XCTAssertEqual(tracking?.qualities.count, 4)
        XCTAssertEqual(tracking?.objectObservationCoverage, .partial)
        XCTAssertEqual(pipeline.testingPresentedObjectFrame?.currentObjects.count, 4)
        if let presented = pipeline.testingPresentedObjectFrame {
            XCTAssertNotNil(SceneTapEvidence(sceneX: 0.05, sceneY: 0.25, frame: presented, now: Date()),
                            "direct measured geometry binds; pipeline must reject only partial coverage")
        } else {
            XCTFail("expected current accepted object frame")
        }
        pipeline.handleSceneTap(normalizedX: 0.05, normalizedY: 0.25)
        XCTAssertNil(pipeline.testingSceneTapEvidence, "omitted detector candidates cannot establish uniqueness")
        XCTAssertNil(pipeline.currentLiveHint)
        await pipeline.releaseAndWait()
    }


    @MainActor
    func testTrackedObjectSelectedBySnapshotIsNotHiddenByWeakerVisionSubject() async {
        let face = CGRect(x: 0.02, y: 0.2, width: 0.2, height: 0.3)
        let cup = CGRect(x: 0.65, y: 0.2, width: 0.3, height: 0.4)
        let pipeline = makeObjectTrackingPipeline(
            visionSubjects: [TrackedSubject(boundingBox: face, confidence: 0.65, isFace: true)])
        let sequence = PipelineObjectTrackingSequence(box: cup)
        pipeline.testingSetObjectTrackingSequenceFactory { _ in sequence }
        pipeline.testingDeliverLiveDetrSeed([DETRDetection(
            boundingBox: cup, label: "cup", confidence: 0.99)],
            context: makeObjectTrackingContext(timestamp: 50, capturedAt: Date().addingTimeInterval(-0.1)))
        pipeline.ingestHigh(context: makeObjectTrackingContext(timestamp: 50.1))
        await pipeline.testingDrainHighQueue()
        let published = await waitUntil { pipeline.overlayState.primaryBoundingBox == cup }
        XCTAssertTrue(published)
        XCTAssertEqual(pipeline.currentFeatures.subject.objectName, "cup")
        if let evidence = pipeline.testingLatestFrameEvidence, let state = evidence.adapterState {
            let input = PipelineFeatureSnapshotAdapter().makeInput(
                frameId: evidence.sourceFrameId, mode: .live, capturedAt: evidence.capturedAt, state: state)
            let snapshot = FeatureSnapshotAggregator().makeSnapshot(from: input)
            XCTAssertEqual(snapshot.subjectSignals.primaryCandidateSource, .detr)
            XCTAssertEqual(snapshot.subjectSignals.primaryCandidateRegion,
                           NormalizedRect(x: 0.65, y: 0.2, width: 0.3, height: 0.4))
        } else { XCTFail("expected frozen current evidence") }
        await pipeline.releaseAndWait()
    }


    @MainActor
    func testWeakMeasuredObjectCannotMakeOverlappingOtherObjectUniquelyTappable() async {
        let pipeline = makeObjectTrackingPipeline()
        let chair = CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        let cup = CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2)
        let sequence = PipelineMultipleObjectTrackingSequence(boxes: [chair, cup])
        pipeline.testingSetObjectTrackingSequenceFactory { _ in sequence }
        pipeline.testingDeliverLiveDetrSeed([
            DETRDetection(boundingBox: chair, label: "chair", confidence: 0.9),
            DETRDetection(boundingBox: cup, label: "cup", confidence: 0.5)
        ], context: makeObjectTrackingContext(timestamp: 60, capturedAt: Date().addingTimeInterval(-0.1)))
        for timestamp in [60.1, 60.2, 60.3] {
            pipeline.ingestHigh(context: makeObjectTrackingContext(timestamp: timestamp))
            await pipeline.testingDrainHighQueue()
            let accepted = await waitUntil {
                pipeline.testingPresentedObjectFrame?.frameID == "frame_\(Int((timestamp * 1000).rounded()))"
            }
            XCTAssertTrue(accepted)
        }
        let measured = pipeline.testingLatestFrameEvidence?.adapterState?.detr?.value
        XCTAssertEqual(measured?.tracking?.objectObservationCoverage, .complete)
        XCTAssertEqual(measured?.detections.count, 2, "both rectangles were measured on current pixels")
        XCTAssertEqual(pipeline.testingPresentedObjectFrame?.currentObjects.count, 1,
                       "identity admission must retain its existing support floor")
        if let presented = pipeline.testingPresentedObjectFrame {
            XCTAssertNotNil(SceneTapEvidence(sceneX: 0.35, sceneY: 0.35, frame: presented, now: Date()),
                            "retained geometry alone would select the wrong unique candidate")
        } else { XCTFail("expected current accepted frame") }
        pipeline.handleSceneTap(normalizedX: 0.35, normalizedY: 0.35)
        XCTAssertNil(pipeline.testingSceneTapEvidence,
                     "a measured but unadmitted overlapping object prevents a uniqueness claim")
        XCTAssertNil(pipeline.currentLiveHint)
        await pipeline.releaseAndWait()
    }

    @MainActor
    func testVisibleClippedObjectKeepsOverlayButCannotClaimUniqueTapTarget() async {
        for clipped in [false, true] {
            let pipeline = makeObjectTrackingPipeline()
            let seed = CGRect(x: 0.2, y: 0.1, width: 0.3, height: 0.4)
            let raw = CGRect(x: 0.2, y: clipped ? -0.01 : 0.01, width: 0.3, height: 0.4)
            let sequence = PipelineMultipleObjectTrackingSequence(boxes: [raw])
            pipeline.testingSetObjectTrackingSequenceFactory { _ in sequence }
            pipeline.testingDeliverLiveDetrSeed([DETRDetection(boundingBox: seed, label: "chair", confidence: 0.9)],
                context: makeObjectTrackingContext(timestamp: 70, capturedAt: Date().addingTimeInterval(-0.1)))
            for timestamp in [70.1, 70.2, 70.3] {
                pipeline.ingestHigh(context: makeObjectTrackingContext(timestamp: timestamp))
                await pipeline.testingDrainHighQueue()
                let accepted = await waitUntil {
                    pipeline.testingPresentedObjectFrame?.frameID == "frame_\(Int((timestamp * 1000).rounded()))"
                }
                XCTAssertTrue(accepted)
            }
            let tracking = pipeline.testingLatestFrameEvidence?.adapterState?.detr?.value.tracking
            XCTAssertEqual(tracking?.objectObservationCoverage, .complete)
            XCTAssertEqual(tracking?.trackingGeometryStatus, clipped ? .clipped : .unclipped)
            XCTAssertEqual(tracking?.geometries.first?.rawBoundingBox, raw)
            XCTAssertEqual(pipeline.overlayState.primaryBoundingBox, tracking?.geometries.first?.visibleImageIntersection)
            XCTAssertEqual(pipeline.testingPresentedObjectFrame?.currentObjects.count, 1)
            if let frame = pipeline.testingPresentedObjectFrame {
                XCTAssertNotNil(SceneTapEvidence(sceneX: 0.3, sceneY: 0.2, frame: frame, now: Date()),
                                "Current geometry alone binds; clipping is an additional policy fence")
            } else { XCTFail("expected accepted object frame") }
            pipeline.handleSceneTap(normalizedX: 0.3, normalizedY: 0.2)
            XCTAssertEqual(pipeline.testingSceneTapEvidence != nil, !clipped)
            XCTAssertNil(pipeline.currentLiveHint, "Clipping does not bypass unavailable calibration")
            await pipeline.releaseAndWait()
        }
    }

    @MainActor
    func testAcceptedObjectMeasurementsReachMovementFrameWithSourceProvenanceAndNoActionAuthority() async throws {
        let pipeline = makeObjectTrackingPipeline()
        let left = CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.3)
        let right = CGRect(x: 0.6, y: -0.01, width: 0.2, height: 0.4)
        let sequence = PipelineMultipleObjectTrackingSequence(boxes: [left, right])
        pipeline.testingSetObjectTrackingSequenceFactory { _ in sequence }
        let source = makeObjectTrackingContext(timestamp: 90, capturedAt: Date().addingTimeInterval(-0.1))
        pipeline.testingDeliverLiveDetrSeed([
            DETRDetection(boundingBox: left, label: "chair", confidence: 0.95),
            DETRDetection(boundingBox: CGRect(x: 0.6, y: 0.01, width: 0.2, height: 0.4),
                          label: "chair", confidence: 0.95)
        ], context: source)
        pipeline.ingestHigh(context: makeObjectTrackingContext(timestamp: 90.1))
        await pipeline.testingDrainHighQueue()
        let accepted = await waitUntil { pipeline.testingPresentedObjectFrame?.frameID == "frame_90100" }
        XCTAssertTrue(accepted)
        let evidence = try XCTUnwrap(pipeline.testingLatestFrameEvidence)
        let asOf = Date()
        let observations = pipeline.testingLiveEntityObservations(for: evidence, evaluatedAt: asOf)
        XCTAssertEqual(observations.count, 2)
        XCTAssertEqual(Set(observations.compactMap(\.trackID)).count, 2)
        XCTAssertEqual(observations.filter { $0.visibility == .partial }.count, 1)
        XCTAssertEqual(observations.filter(\.hasComparableGeometry).count, 1)
        for observation in observations {
            XCTAssertEqual(observation.provenance?.frameID, evidence.sourceFrameId)
            XCTAssertEqual(observation.provenance?.semanticSourceFrameID, "frame_90000")
            XCTAssertEqual(observation.provenance?.semanticMeasuredAt, source.capturedAt)
            XCTAssertEqual(observation.provenance?.trackingQuality, 0.99)
            XCTAssertEqual(observation.provenance?.pipelineGeneration, pipeline.testingLifecycleGeneration)
        }
        let state = try XCTUnwrap(evidence.adapterState)
        let input = PipelineFeatureSnapshotAdapter().makeInput(
            frameId: evidence.sourceFrameId, mode: .live, capturedAt: evidence.capturedAt,
            evaluatedAt: asOf, state: state)
        let snapshot = FeatureSnapshotAggregator().makeSnapshot(from: input)
        let movement = try XCTUnwrap(UserMovementFrame(
            snapshot: snapshot, envelope: evidence.makeEnvelope(), subjectBinding: nil,
            entityObservations: observations, pipelineGeneration: pipeline.testingLifecycleGeneration,
            evaluatedAt: asOf, isCalibrated: false, orientation: .landscapeRight))
        XCTAssertEqual(movement.entityObservations, observations)
        XCTAssertFalse(movement.evidence?.isCalibrated ?? true)
        XCTAssertNil(movement.evidence?.subjectBinding)
        XCTAssertNil(pipeline.currentLiveHint, "Measurement inventory must not create action scope/calibration")
        XCTAssertTrue(pipeline.testingLiveEntityObservations(
            for: evidence, evaluatedAt: evidence.capturedAt.addingTimeInterval(0.251)).isEmpty)
        let substitutedPixels = try XCTUnwrap(LatestFrameEvidenceStore.Snapshot(
            pixelBuffer: makeObjectTrackingContext(timestamp: 90.3).pixelBuffer,
            orientation: evidence.orientation, sourceFrameId: evidence.sourceFrameId,
            capturedAt: evidence.capturedAt, isStable: evidence.isStable,
            adapterState: evidence.adapterState, lensGeneration: evidence.lensGeneration,
            samplePresentationTimestamp: evidence.samplePresentationTimestamp,
            sessionGeneration: evidence.sessionGeneration))
        XCTAssertTrue(pipeline.testingLiveEntityObservations(for: substitutedPixels, evaluatedAt: asOf).isEmpty,
                      "Equal frame strings cannot attribute accepted geometry to different pixel bytes")

        // A same-source reseed changes the semantic anchor while preserving
        // measured object identity. This uses the existing high-lane fixture;
        // it qualifies accepted observations, not an admitted coaching episode.
        let refinedLeft = left.offsetBy(dx: 0.04, dy: 0)
        let reseededSequence = PipelineMultipleObjectTrackingSequence(boxes: [refinedLeft, right])
        pipeline.testingSetObjectTrackingSequenceFactory { _ in reseededSequence }
        let reseedSource = makeObjectTrackingContext(timestamp: 90.2)
        pipeline.testingDeliverLiveDetrSeed([
            DETRDetection(boundingBox: left, label: "chair", confidence: 0.95),
            DETRDetection(boundingBox: CGRect(x: 0.6, y: 0.01, width: 0.2, height: 0.4),
                          label: "chair", confidence: 0.95)
        ], context: reseedSource)
        pipeline.ingestHigh(context: makeObjectTrackingContext(timestamp: 90.3))
        await pipeline.testingDrainHighQueue()
        let reseedAccepted = await waitUntil { pipeline.testingPresentedObjectFrame?.frameID == "frame_90300" }
        XCTAssertTrue(reseedAccepted)
        let reseededEvidence = try XCTUnwrap(pipeline.testingLatestFrameEvidence)
        let reseededObservations = pipeline.testingLiveEntityObservations(for: reseededEvidence)
        XCTAssertEqual(reseededObservations.count, 2, "Missing post-reseed rows cannot qualify continuity")
        XCTAssertEqual(Set(reseededObservations.compactMap(\.trackID)), Set(observations.compactMap(\.trackID)))
        XCTAssertEqual(Set(reseededObservations.map(\.entityRef)), Set(observations.map(\.entityRef)))
        XCTAssertEqual(reseededObservations.first { $0.visibility == .visible }?.region?.x ?? -1,
                       Double(refinedLeft.minX), accuracy: 0.000001)
        for observation in reseededObservations {
            XCTAssertEqual(observation.provenance?.semanticSourceFrameID, "frame_90200")
            XCTAssertEqual(observation.provenance?.semanticMeasuredAt, reseedSource.capturedAt)
        }
        XCTAssertEqual(observations.first?.provenance?.semanticSourceFrameID, "frame_90000",
                       "An immutable earlier observation must keep its original semantic anchor")
        XCTAssertNil(pipeline.currentLiveHint, "Reseeding alone supplies no calibration or action authority")
        if case .baseline = pipeline.currentCoachingEpisodeEvent {
            XCTFail("This uncalibrated measurement fixture must not silently create a coaching baseline")
        }

        // An empty detector barrier followed by a new frame clears current
        // measurements. Previous immutable evidence stays intact; no absent row.
        pipeline.testingDeliverLiveDetrSeed([], context: makeObjectTrackingContext(timestamp: 90.4))
        pipeline.ingestHigh(context: makeObjectTrackingContext(timestamp: 90.5))
        await pipeline.testingDrainHighQueue()
        let lost = await waitUntil { pipeline.testingPresentedObjectFrame?.frameID == "frame_90500" }
        XCTAssertTrue(lost)
        let current = try XCTUnwrap(pipeline.testingLatestFrameEvidence)
        XCTAssertTrue(pipeline.testingLiveEntityObservations(for: current).isEmpty)
        XCTAssertTrue(pipeline.testingLiveEntityObservations(for: evidence).isEmpty,
                      "Old geometry cannot be relabeled as the new accepted frame")
        XCTAssertEqual(movement.entityObservations.count, 2)
        await pipeline.releaseAndWait()
        XCTAssertTrue(pipeline.testingLiveEntityObservations(for: current).isEmpty)
    }

    @MainActor
    func testLiveDetrFailureInvalidatesInOrderAndRecoversWithoutOldSeedResurrection() async throws {
        let pipeline = makeObjectTrackingPipeline()
        let box = CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3)
        let sequence = PipelineObjectTrackingSequence(box: box)
        pipeline.testingSetObjectTrackingSequenceFactory { _ in sequence }
        let detection = DETRDetection(boundingBox: box, label: "chair", confidence: 0.8)
        let firstSource = makeObjectTrackingContext(timestamp: 400)
        pipeline.testingDeliverLiveDetrSeed([detection], context: firstSource)
        pipeline.ingestHigh(context: makeObjectTrackingContext(timestamp: 400.1))
        await pipeline.testingDrainHighQueue()
        XCTAssertNotNil(pipeline.testingLatestFrameEvidence?.adapterState?.detr)

        let failedSource = makeObjectTrackingContext(timestamp: 400.2)
        pipeline.testingDeliverLiveDetrFailure(.inferenceFailed, context: failedSource)
        pipeline.testingDeliverLiveDetrSeed([detection], context: firstSource)
        pipeline.ingestHigh(context: makeObjectTrackingContext(timestamp: 400.3))
        await pipeline.testingDrainHighQueue()
        let unavailable = try XCTUnwrap(pipeline.testingLatestFrameEvidence?.adapterState)
        XCTAssertNil(unavailable.detr, "An older success cannot cross a newer failed-source barrier")
        XCTAssertNil(unavailable.debugData.detrMeasuredAt)
        XCTAssertTrue(unavailable.debugData.detrDetections.isEmpty)

        let recoveredSource = makeObjectTrackingContext(timestamp: 400.4)
        pipeline.testingDeliverLiveDetrSeed([detection], context: recoveredSource)
        pipeline.testingDeliverLiveDetrFailure(.missingOutput, context: failedSource)
        pipeline.ingestHigh(context: makeObjectTrackingContext(timestamp: 400.5))
        await pipeline.testingDrainHighQueue()
        let recovered = try XCTUnwrap(pipeline.testingLatestFrameEvidence?.adapterState?.detr)
        XCTAssertEqual(recovered.value.detections.map(\.label), ["chair"])
        XCTAssertEqual(recovered.value.tracking?.source.frameID, "frame_400400")
        XCTAssertEqual(sequence.pixels.count, 4, "Only the two successful seeds prime and measure")
        await pipeline.releaseAndWait()
    }

    @MainActor
    func testReplayDetrFailureIsUnknownAndValidEmptyCanRecover() async throws {
        let pipeline = makeObjectTrackingPipeline()
        let context = makeObjectTrackingContext(timestamp: 500)
        let detection = DETRDetection(boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3),
                                      label: "chair", confidence: 0.8)
        let differentObject = DETRDetection(boundingBox: CGRect(x: 0.6, y: 0.4, width: 0.2, height: 0.2),
                                            label: "cup", confidence: 0.8)
        let results: [DETRDetectionResult] = [
            .success([detection]), .success([]), .success([differentObject]),
            .failure(.inferenceFailed), .failure(.missingOutput),
            .failure(.invalidOutput), .failure(.modelUnavailable), .success([]), .success([detection])
        ]
        for result in results {
            let state = pipeline.testingApplyDetrResult(result, pixelBuffer: context.pixelBuffer,
                                                        measuredAt: context.capturedAt)
            assertDetrObservation(result, state: state, capturedAt: context.capturedAt)
            if case .success(let detections) = result {
                XCTAssertEqual(state.features.subject.objectName, detections.first?.label)
                XCTAssertEqual(state.features.subject.count, detections.count)
                XCTAssertEqual(state.features.composition.subjectAreaRatio,
                               detections.first.map { $0.boundingBox.width * $0.boundingBox.height } ?? 0)
            }
        }
        await pipeline.releaseAndWait()
    }

    @MainActor
    func testPauseDetrFailureCannotFallbackToAcceptedObjectEvidence() async throws {
        let pipeline = makeObjectTrackingPipeline()
        let context = makeObjectTrackingContext(timestamp: 600)
        let detection = DETRDetection(boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3),
                                      label: "chair", confidence: 0.8)
        let accepted = pipeline.testingApplyDetrResult(.success([detection]),
            pixelBuffer: context.pixelBuffer, measuredAt: context.capturedAt)
        XCTAssertNotNil(accepted.detr)
        XCTAssertEqual(accepted.features.subject.objectName, "chair")
        XCTAssertGreaterThan(accepted.features.composition.subjectAreaRatio, 0)
        // Empty must clear an immediately preceding positive object, without
        // relying on a failure having cleared the legacy fields first.
        let directEmpty = pipeline.testingApplyPauseDetrResult(.success([]),
            measuredAt: context.capturedAt, state: accepted)
        assertDetrObservation(.success([]), state: directEmpty, capturedAt: context.capturedAt)
        XCTAssertNil(directEmpty.features.subject.objectName)
        XCTAssertEqual(directEmpty.features.subject.count, 0)
        XCTAssertEqual(directEmpty.features.composition.subjectAreaRatio, 0)
        XCTAssertEqual(directEmpty.features.composition.horizontalOffset,
                       accepted.features.composition.horizontalOffset)
        XCTAssertEqual(directEmpty.features.horizon.angle, accepted.features.horizon.angle)
        let differentObject = DETRDetection(boundingBox: CGRect(x: 0.6, y: 0.4, width: 0.2, height: 0.2),
                                            label: "cup", confidence: 0.8)
        for previous in [accepted, directEmpty] {
            let current = pipeline.testingApplyPauseDetrResult(.success([differentObject]),
                measuredAt: context.capturedAt, state: previous)
            assertDetrObservation(.success([differentObject]), state: current, capturedAt: context.capturedAt)
            XCTAssertEqual(current.features.subject.objectName, "cup")
            XCTAssertEqual(current.features.subject.count, 1)
            XCTAssertEqual(current.features.composition.subjectAreaRatio,
                           differentObject.boundingBox.width * differentObject.boundingBox.height)
        }
        for failure in [DETRDetectionFailure.inferenceFailed, .missingOutput, .invalidOutput, .modelUnavailable] {
            let state = pipeline.testingApplyPauseDetrResult(.failure(failure),
                measuredAt: context.capturedAt, state: accepted)
            assertDetrObservation(.failure(failure), state: state, capturedAt: context.capturedAt)
            XCTAssertNil(state.features.subject.objectName)
            let recovered = pipeline.testingApplyPauseDetrResult(.success([]),
                measuredAt: context.capturedAt, state: state)
            assertDetrObservation(.success([]), state: recovered, capturedAt: context.capturedAt)
        }
        await pipeline.releaseAndWait()

        // Exercise the independent Vision owner through the actual high lane.
        let visionSubject = TrackedSubject(
            boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.4, height: 0.4),
            confidence: 1, isFace: true)
        let personPipeline = makeObjectTrackingPipeline(visionSubjects: [visionSubject])
        let personContext = makeObjectTrackingContext(timestamp: 600)
        personPipeline.ingestHigh(context: personContext)
        await personPipeline.testingDrainHighQueue()
        let published = await waitUntil { personPipeline.testingPresentedObjectFrame?.frameID == "frame_600000" }
        XCTAssertTrue(published)
        let personState = try XCTUnwrap(personPipeline.testingLatestFrameEvidence?.adapterState)
        XCTAssertTrue(personState.features.subject.isFace)
        XCTAssertTrue(personState.features.subject.isPerson)
        XCTAssertEqual(personState.features.subject.count, 1)
        let objectResults: [DETRDetectionResult] = [
            .failure(.inferenceFailed), .success([]), .success([differentObject])
        ]
        for result in objectResults {
            let state = personPipeline.testingApplyPauseDetrResult(result,
                measuredAt: personContext.capturedAt, state: personState)
            XCTAssertTrue(state.features.subject.isFace)
            XCTAssertTrue(state.features.subject.isPerson)
            XCTAssertEqual(state.features.subject.count, personState.features.subject.count)
            XCTAssertEqual(state.features.subject.objectName, personState.features.subject.objectName)
            XCTAssertEqual(state.features.composition.subjectAreaRatio,
                           personState.features.composition.subjectAreaRatio)
            XCTAssertEqual(state.features.composition.horizontalOffset,
                           personState.features.composition.horizontalOffset)
            XCTAssertEqual(state.vision?.value.personCount, personState.vision?.value.personCount)
        }
        await personPipeline.releaseAndWait()
    }

    private func assertDetrObservation(_ result: DETRDetectionResult,
                                       state: PipelineFeatureSnapshotAdapterState, capturedAt: Date,
                                       file: StaticString = #filePath, line: UInt = #line) {
        let snapshot = FeatureSnapshotAggregator().makeSnapshot(from:
            PipelineFeatureSnapshotAdapter().makeInput(
                frameId: "typed-detr-availability", mode: .pause, capturedAt: capturedAt,
                evaluatedAt: capturedAt, state: state))
        switch result {
        case .success(let detections):
            XCTAssertTrue(snapshot.sources.detr.available, file: file, line: line)
            XCTAssertNotNil(state.detr, file: file, line: line)
            XCTAssertEqual(snapshot.objects.totalCount, detections.count, file: file, line: line)
            XCTAssertEqual(state.debugData.detrMeasuredAt, capturedAt, file: file, line: line)
        case .failure:
            XCTAssertFalse(snapshot.sources.detr.available, file: file, line: line)
            XCTAssertNil(state.detr, file: file, line: line)
            XCTAssertNil(state.debugData.detrMeasuredAt, file: file, line: line)
            XCTAssertTrue(state.debugData.detrDetections.isEmpty, file: file, line: line)
            XCTAssertNil(snapshot.subjectSignals.primaryCandidateRegion, file: file, line: line)
        }
    }

    func testFailedVisionBatchCannotCarryPartialObservationPayload() {
        let result = VisionTrackingResult(
            subjects: [TrackedSubject(boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4),
                                      confidence: 1, isFace: true)],
            saliencyCenter: CGPoint(x: 0.4, y: 0.4),
            saliencyRegion: CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4),
            faceCount: 1, personCount: 1, processingStatus: .failed)
        XCTAssertEqual(result.processingStatus, .failed)
        XCTAssertTrue(result.subjects.isEmpty)
        XCTAssertNil(result.saliencyCenter)
        XCTAssertNil(result.saliencyRegion)
        XCTAssertEqual(result.faceCount, 0)
        XCTAssertEqual(result.personCount, 0)
    }

    @MainActor
    func testHighVisionFailureClearsEarlierEvidenceAndCompletedEmptyRemainsAvailable() async throws {
        let subject = TrackedSubject(boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4),
                                     confidence: 1, isFace: true)
        let positive = VisionTrackingResult(subjects: [subject], saliencyCenter: nil,
                                            saliencyRegion: nil, faceCount: 1, personCount: 1)
        let failed = VisionTrackingResult(subjects: [], saliencyCenter: nil, saliencyRegion: nil,
                                         faceCount: 0, personCount: 0, processingStatus: .failed)
        let empty = VisionTrackingResult(subjects: [], saliencyCenter: nil, saliencyRegion: nil,
                                        faceCount: 0, personCount: 0)
        let provider = PipelineVisionResultSequence([positive, failed, empty, positive])
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil, visualEvidenceProvider: nil, neuralEvidenceService: nil,
            liveHybridFusionEnabled: false, demoLiveCoachEnabled: false,
            visionResultProviderForTesting: { _, _ in provider.next() })
        let expectedAvailable = [true, false, true, true]
        let expectedPeople = [1, 0, 0, 1]
        for index in expectedAvailable.indices {
            let timestamp = 200.0 + Double(index) * 0.1
            let context = makeObjectTrackingContext(timestamp: timestamp)
            let frameID = "frame_\(Int((timestamp * 1000).rounded()))"
            pipeline.ingestHigh(context: context)
            await pipeline.testingDrainHighQueue()
            let accepted = await waitUntil { pipeline.testingPresentedObjectFrame?.frameID == frameID }
            XCTAssertTrue(accepted, "Missing high-lane publication at step \(index)")
            let evidence = try XCTUnwrap(pipeline.testingLatestFrameEvidence)
            XCTAssertEqual(evidence.sourceFrameId, frameID)
            let state = try XCTUnwrap(evidence.adapterState)
            // Evaluate at this producer timestamp to isolate availability from age expiry.
            let asOf = state.vision?.measuredAt ?? evidence.capturedAt
            let snapshot = FeatureSnapshotAggregator().makeSnapshot(from:
                PipelineFeatureSnapshotAdapter().makeInput(
                    frameId: frameID, mode: .live, capturedAt: evidence.capturedAt,
                    evaluatedAt: asOf, state: state))
            XCTAssertEqual(state.vision != nil, expectedAvailable[index], "step \(index)")
            XCTAssertEqual(snapshot.sources.vision.available, expectedAvailable[index], "step \(index)")
            XCTAssertEqual(snapshot.subjectSignals.personCount, expectedPeople[index], "step \(index)")
            if index == 1 {
                XCTAssertNil(state.debugData.visionMeasuredAt, "Debug fallback cannot resurrect failed evidence")
                XCTAssertTrue(state.debugData.visionSubjects.isEmpty)
                XCTAssertNil(snapshot.subjectSignals.primaryCandidateRegion)
            }
        }
        XCTAssertEqual(provider.remainingCount, 0)
        await pipeline.releaseAndWait()
    }

    @MainActor
    func testStillReplayDistinguishesUnavailableVisionFromCompletedEmptyBatch() async {
        let failed = VisionTrackingResult(subjects: [], saliencyCenter: nil, saliencyRegion: nil,
                                         faceCount: 0, personCount: 0, processingStatus: .failed)
        let empty = VisionTrackingResult(subjects: [], saliencyCenter: nil, saliencyRegion: nil,
                                        faceCount: 0, personCount: 0)
        let provider = PipelineVisionResultSequence([failed, empty])
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil, visualEvidenceProvider: nil, neuralEvidenceService: nil,
            liveHybridFusionEnabled: false, demoLiveCoachEnabled: false,
            visionResultProviderForTesting: { _, _ in provider.next() })
        for (index, expectedAvailable) in [0.0, 1.0].enumerated() {
            let context = makeObjectTrackingContext(timestamp: 300.0 + Double(index))
            let result = await pipeline.testingReplayStillImageForSemanticEval(
                recordId: "vision-availability-\(index)", filename: "generated-control.bgra",
                pixelBuffer: context.pixelBuffer, orientation: .up, capturedAt: context.capturedAt,
                options: .lightweightTest)
            for row in [result.liveRow, result.pauseRow] {
                XCTAssertEqual(row.debugNumericFeatures["vision_available"], expectedAvailable)
                XCTAssertEqual(row.debugNumericFeatures["person_count"], 0)
                XCTAssertEqual(row.runtimeClaim, .testFixture)
            }
        }
        XCTAssertEqual(provider.remainingCount, 0)
        await pipeline.releaseAndWait()
    }

    func testSceneClassificationDoesNotTreatUnavailableVisionAsObservedPersonAbsence() {
        let capturedAt = Date(timeIntervalSince1970: 1_790_000_000)
        func scene(visionAvailable: Bool, width: CGFloat, confidence: Double,
                   objectCount: Int = 1) -> SceneSemanticsReport {
            let emptyVision = FeatureSample(
                value: FeatureSnapshotVisionPayload(subjects: [], saliencyCenter: nil,
                    saliencyRegion: nil, faceCount: 0, personCount: 0),
                measuredAt: capturedAt, baseConfidence: nil)
            let detections = (0..<objectCount).map { index in
                FeatureSnapshotDetectedObject(
                    boundingBox: CGRect(x: 0.1 + CGFloat(index) * 0.25, y: 0.2,
                                        width: width, height: width),
                    label: "cup", confidence: confidence)
            }
            let input = FeatureAggregationInput(
                frameId: "same-detr-person-observation-control", mode: .pause,
                capturedAt: capturedAt, motionState: .still, shakeLevel: 0,
                vision: visionAvailable ? emptyVision : nil, horizon: nil, lighting: nil,
                detr: FeatureSample(value: FeatureSnapshotDetrPayload(detections: detections),
                                    measuredAt: capturedAt, baseConfidence: confidence),
                aesthetic: nil)
            let snapshot = FeatureSnapshotAggregator().makeSnapshot(from: input)
            XCTAssertTrue(snapshot.sources.detr.available)
            XCTAssertEqual(snapshot.sources.vision.available, visionAvailable)
            XCTAssertEqual(snapshot.objects.totalCount, objectCount)
            XCTAssertEqual(snapshot.subjectSignals.personCount, 0,
                           "The numeric zero alone does not establish observed absence")
            return SceneSemanticsAnalyzer().analyze(snapshot: snapshot)
        }
        XCTAssertEqual(scene(visionAvailable: true, width: 0.4, confidence: 0.9).sceneType, .objectInsert)
        XCTAssertEqual(scene(visionAvailable: false, width: 0.4, confidence: 0.9).sceneType, .unknown)
        XCTAssertEqual(scene(visionAvailable: true, width: 0.1, confidence: 0.4).sceneType, .establishingLikeFrame)
        XCTAssertEqual(scene(visionAvailable: false, width: 0.1, confidence: 0.4).sceneType, .unknown)
        // Independent observed objects remain valid positive establishing evidence.
        XCTAssertEqual(scene(visionAvailable: false, width: 0.1, confidence: 0.4,
                             objectCount: 3).sceneType, .establishingLikeFrame)
    }

    private func makeObjectTrackingPipeline(visionSubjects: [TrackedSubject] = []) -> AnalysisPipeline {
        AnalysisPipeline(reasoningProvider: nil, visualEvidenceProvider: nil,
                         neuralEvidenceService: nil, liveHybridFusionEnabled: false,
                         demoLiveCoachEnabled: false,
                         visionResultProviderForTesting: { _, _ in
            VisionTrackingResult(subjects: visionSubjects, saliencyCenter: nil, saliencyRegion: nil,
                                 faceCount: visionSubjects.filter(\.isFace).count, personCount: visionSubjects.count)
        })
    }

    private func makeObjectTrackingContext(timestamp: Double, capturedAt: Date = Date()) -> FrameContext {
        let legacy = makeFrameContext(timestamp: timestamp, capturedAt: capturedAt, captureGeneration: 23)
        return FrameContext(pixelBuffer: legacy.pixelBuffer, timestamp: legacy.timestamp,
                            orientation: .up, isStable: true, shakeLevel: 0,
                            motionState: .still, capturedAt: capturedAt,
                            captureGeneration: 23, sessionGeneration: 0)
    }

    private func makeComponents(
        neuralEvidenceService: NeuralEvidenceInferenceService? = nil,
        liveHybridFusionEnabled: Bool = false
    ) -> (AnalysisPipeline,
          CameraManager,
          RealtimeScheduler,
          ReleaseTestSessionRunner) {
        let scheduler = RealtimeScheduler()
        let thermalGovernor = ThermalGovernor(thermalStateProvider: { .nominal },
                                               batteryLevelProvider: { 1.0 })
        let runner = ReleaseTestSessionRunner()
        let manager = CameraManager(scheduler: scheduler,
                                    thermalGovernor: thermalGovernor,
                                    motionGate: MotionGate(),
                                    sessionRunner: runner,
                                    configuration: .ready,
                                    notificationCenter: NotificationCenter())
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: neuralEvidenceService,
            thermalGovernor: thermalGovernor,
            neuralHeavyModelsEnabledProvider: { true },
            liveHybridFusionEnabled: liveHybridFusionEnabled,
            demoLiveCoachEnabled: false
        )
        return (pipeline, manager, scheduler, runner)
    }

    private func makeLiveNeuralEvidenceConfiguration() -> NeuralEvidenceInferenceConfiguration {
        var configuration = NeuralEvidenceInferenceConfiguration.disabled
        configuration.featureEnabled = true
        configuration.liveModeEnabled = true
        configuration.liveTimeout = 5.0
        configuration.liveMinIntervalUnrestricted = 0
        configuration.liveMinIntervalConstrained = 0
        return configuration
    }

    private func makeLiveHint() -> LiveHintPresentation {
        LiveHintPresentation(
            id: "lh_release_test",
            frameId: "release-frame",
            text: "Сместите кадр чуть левее.",
            confidence: 0.8,
            actionType: .moveFrameLeft,
            actionId: "release-action",
            linkedIssueIds: ["release-issue"],
            summaryId: "release-summary",
            traceRootIds: ["release-trace"],
            targetRegion: nil,
            overlayHint: nil,
            isFallback: false,
            expandedVerdict: nil
        )
    }

    private func makePauseCritique() -> PauseCritiquePresentation {
        PauseCritiquePresentation(
            frameId: "pause-frame",
            verdict: .mixed,
            verdictConfidence: 0.7,
            summaryId: "pause-summary",
            shortVerdict: "Тестовая пауза.",
            whyGood: nil,
            whyProblematic: nil,
            strengths: [],
            issues: [],
            actions: [],
            noChangeRationale: nil,
            assumptions: [],
            traceRootIds: [],
            fallbackUsed: false
        )
    }

    private func makeFrameContext(timestamp: Double = 1.0,
                                  orientation: CGImagePropertyOrientation = .up,
                                  isStable: Bool = true,
                                  capturedAt: Date = Date(),
                                  captureGeneration: UInt64 = 0) -> FrameContext {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: 4,
            kCVPixelBufferHeightKey as String: 4,
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            4,
            4,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        return FrameContext(
            pixelBuffer: pixelBuffer!,
            timestamp: CMTimeMakeWithSeconds(timestamp, preferredTimescale: 600),
            orientation: orientation,
            isStable: isStable,
            shakeLevel: 0.05,
            motionState: .still,
            capturedAt: capturedAt,
            captureGeneration: captureGeneration
        )
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async -> Bool {
        // High analysis runs on a dedicated queue; use elapsed time instead of a fixed yield budget.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))

        while clock.now < deadline {
            if condition() { return true }
            do {
                try await Task.sleep(nanoseconds: 1_000_000)
            } catch {
                return false
            }
        }
        return condition()
    }
}

private final class PauseClaimHookState: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseGate = DispatchSemaphore(value: 0)
    private var entered = false

    var hasEntered: Bool {
        lock.lock()
        defer { lock.unlock() }
        return entered
    }

    func enterAndWait() {
        lock.lock()
        entered = true
        lock.unlock()
        releaseGate.wait()
    }

    func release() {
        releaseGate.signal()
    }
}

private final class SuspendingNeuralEvidenceGate: @unchecked Sendable {
    private let stateQueue = DispatchQueue(label: "AnalysisPipelineReleaseTests.suspendingNeuralEvidence")
    private var requestedFrameIds: Set<String> = []
    private var completedFrameIds: Set<String> = []
    private var releasedFrameIds: Set<String> = []

    func infer(request: NeuralEvidenceProviderRequest) async throws -> NeuralEvidenceProviderOutput {
        stateQueue.sync {
            _ = requestedFrameIds.insert(request.frameId)
        }

        while true {
            let isReleased = stateQueue.sync {
                releasedFrameIds.contains(request.frameId)
            }
            if isReleased { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        stateQueue.sync {
            _ = completedFrameIds.insert(request.frameId)
        }
        return Self.output(actualROIStrategy: request.roiStrategy)
    }

    func hasRequestedFrame(_ frameId: String) -> Bool {
        stateQueue.sync {
            requestedFrameIds.contains(frameId)
        }
    }

    func hasCompletedFrame(_ frameId: String) -> Bool {
        stateQueue.sync {
            completedFrameIds.contains(frameId)
        }
    }

    func release(frameId: String) {
        stateQueue.sync {
            _ = releasedFrameIds.insert(frameId)
        }
    }

    func releaseAll() {
        stateQueue.sync {
            releasedFrameIds.formUnion(requestedFrameIds)
        }
    }

    private static func output(actualROIStrategy: NeuralEvidenceROIStrategy) -> NeuralEvidenceProviderOutput {
        let row = Array(repeating: 0.7, count: NeuralEvidenceProviderOutput.supportingSignalCount)
        return NeuralEvidenceProviderOutput(
            scalarScores: Array(repeating: 0.7, count: NeuralEvidenceProviderOutput.scalarHeadCount),
            scalarConfidences: Array(repeating: 0.8, count: NeuralEvidenceProviderOutput.scalarHeadCount),
            supportingSignalScores: Array(
                repeating: row,
                count: NeuralEvidenceProviderOutput.scalarHeadCount
            ),
            shotTypeAffinities: Array(repeating: 0.5, count: NeuralEvidenceProviderOutput.shotTypeCount),
            shotTypeConfidence: 0.8,
            actualROIStrategy: actualROIStrategy
        )
    }
}

private final class ReleaseTestSessionRunner: CameraSessionRunner {
    private let lock = NSLock()
    private var starts = 0
    private var stops = 0
    private var running = false

    var onStop: (() -> Void)?
    var schedulerRegistrationCountAtStop: Int?

    var startCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return starts
    }

    var stopCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return stops
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    func startRunning() {
        lock.lock()
        starts += 1
        running = true
        lock.unlock()
    }

    func stopRunning() {
        lock.lock()
        stops += 1
        running = false
        let callback = onStop
        lock.unlock()
        callback?()
    }
}

private final class PipelineVisionResultSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [VisionTrackingResult]

    init(_ values: [VisionTrackingResult]) { self.values = values }

    var remainingCount: Int {
        lock.lock(); defer { lock.unlock() }
        return values.count
    }

    func next() -> VisionTrackingResult {
        lock.lock(); defer { lock.unlock() }
        precondition(!values.isEmpty, "Unexpected extra Vision invocation")
        return values.removeFirst()
    }
}

private final class PipelineObjectTrackingSequence: VisionObjectSequence {
    let box: CGRect
    private(set) var pixels: [ObjectIdentifier] = []
    init(box: CGRect) { self.box = box }
    func measure(pixelBuffer: CVPixelBuffer,
                 orientation: CGImagePropertyOrientation) throws -> [VisionObjectMeasurement?] {
        pixels.append(ObjectIdentifier(pixelBuffer as AnyObject))
        return [VisionObjectMeasurement(boundingBox: box, quality: 0.99)]
    }
}

private final class PipelineMultipleObjectTrackingSequence: VisionObjectSequence {
    let boxes: [CGRect]
    init(boxes: [CGRect]) { self.boxes = boxes }
    func measure(pixelBuffer: CVPixelBuffer,
                 orientation: CGImagePropertyOrientation) throws -> [VisionObjectMeasurement?] {
        boxes.map { VisionObjectMeasurement(boundingBox: $0, quality: 0.99) }
    }
}
