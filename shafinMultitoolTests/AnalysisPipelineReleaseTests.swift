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
