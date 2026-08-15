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

        for _ in 0..<1_000 {
            if runner.startCount == 2 && scheduler.registrationCountForTesting == 3 {
                break
            }
            await Task.yield()
        }

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

    private func makeComponents() -> (AnalysisPipeline,
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
            neuralEvidenceService: nil,
            thermalGovernor: thermalGovernor,
            neuralHeavyModelsEnabledProvider: { true },
            liveHybridFusionEnabled: false,
            demoLiveCoachEnabled: false
        )
        return (pipeline, manager, scheduler, runner)
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

    private func makeFrameContext() -> FrameContext {
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
            timestamp: CMTimeMakeWithSeconds(1, preferredTimescale: 600),
            orientation: .up,
            isStable: true,
            shakeLevel: 0.05,
            motionState: .still
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
