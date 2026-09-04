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
                                    configuration: .ready)
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
