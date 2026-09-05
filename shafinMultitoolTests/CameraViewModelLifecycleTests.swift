import Foundation
import AVFoundation
import XCTest
@testable import shafinMultitool

@MainActor
final class CameraViewModelLifecycleTests: XCTestCase {

    func testFailedStartPublishesFailureOnlyAfterRegistrationRollback() async {
        let fixture = makeFixture(startPlans: [
            .init(succeeds: false)
        ])
        let rollbackGate = CameraViewModelTestGate()
        fixture.scheduler.setDrainGateForTesting(rollbackGate.semaphore)
        defer {
            rollbackGate.signal()
            fixture.scheduler.setDrainGateForTesting(nil)
        }

        let start = Task { @MainActor in
            await fixture.viewModel.startAndWait()
        }

        let rollbackStarted = await waitUntil {
            fixture.pipeline.testingReleaseInProgress
        }
        XCTAssertTrue(rollbackStarted)
        XCTAssertEqual(fixture.runner.registrationCountsAtStart, [3])
        XCTAssertFalse(isFailed(fixture.viewModel.lifecycleState))
        XCTAssertNil(fixture.viewModel.lifecycleError)

        rollbackGate.signal()
        await start.value
        fixture.scheduler.setDrainGateForTesting(nil)

        XCTAssertEqual(fixture.viewModel.lifecycleState, .failed(.startFailed))
        XCTAssertEqual(fixture.viewModel.lifecycleError, .startFailed)
        XCTAssertEqual(fixture.scheduler.registrationCountForTesting, 0)

        await fixture.viewModel.releaseAndWait()
    }

    func testRetryStartedDuringFailedStartRollbackWaitsForFreshRegistrationSet() async {
        let fixture = makeFixture(startPlans: [
            .init(succeeds: false),
            .init(succeeds: true)
        ])
        let rollbackGate = CameraViewModelTestGate()
        fixture.scheduler.setDrainGateForTesting(rollbackGate.semaphore)
        defer {
            rollbackGate.signal()
            fixture.scheduler.setDrainGateForTesting(nil)
        }

        let failedStart = Task { @MainActor in
            await fixture.viewModel.startAndWait()
        }
        let rollbackStarted = await waitUntil {
            fixture.pipeline.testingReleaseInProgress
        }
        XCTAssertTrue(rollbackStarted)
        XCTAssertEqual(fixture.runner.registrationCountsAtStart, [3])

        // start() captures the in-flight rollback synchronously and must not reach
        // CameraManager while the pipeline release boundary is held.
        fixture.viewModel.start()
        let secondStartBeforeRollback = await waitUntil(timeout: .milliseconds(100)) {
            fixture.runner.startCount == 2
        }
        XCTAssertFalse(secondStartBeforeRollback)

        rollbackGate.signal()
        await failedStart.value

        let retryRunning = await waitUntil {
            fixture.runner.startCount == 2
                && fixture.scheduler.registrationCountForTesting == 3
                && fixture.viewModel.lifecycleState == .running
        }
        fixture.scheduler.setDrainGateForTesting(nil)

        XCTAssertTrue(retryRunning)
        XCTAssertEqual(fixture.scheduler.registrationCountForTesting, 3)
        XCTAssertEqual(fixture.viewModel.lifecycleState, .running)
        XCTAssertNil(fixture.viewModel.lifecycleError)
        XCTAssertEqual(fixture.runner.registrationCountsAtStart, [3, 3])
        XCTAssertFalse(fixture.runner.didTimeoutWaitingForStartGate)

        await fixture.viewModel.releaseAndWait()
    }

    func testSupersededStaleFailureCannotReleaseNewRunningRegistrationSet() async {
        let firstStartGate = CameraViewModelTestGate()
        defer { firstStartGate.signal() }
        let fixture = makeFixture(startPlans: [
            .init(succeeds: false, gate: firstStartGate),
            .init(succeeds: true)
        ])

        fixture.viewModel.start()
        let firstStartEntered = await waitUntil {
            fixture.runner.startCount == 1
        }
        XCTAssertTrue(firstStartEntered)

        // This supersedes the blocked start before its failure is observed by the
        // view model. The replacement reuses the current registration set.
        fixture.viewModel.start()
        firstStartGate.signal()

        let replacementRunning = await waitUntil {
            fixture.runner.startCount == 2
                && fixture.scheduler.registrationCountForTesting == 3
                && fixture.viewModel.lifecycleState == .running
        }

        XCTAssertTrue(replacementRunning)
        XCTAssertEqual(fixture.scheduler.registrationCountForTesting, 3)
        XCTAssertEqual(fixture.viewModel.lifecycleState, .running)
        XCTAssertNil(fixture.viewModel.lifecycleError)
        XCTAssertEqual(fixture.runner.registrationCountsAtStart, [3, 3])
        XCTAssertFalse(fixture.runner.didTimeoutWaitingForStartGate)

        await fixture.viewModel.releaseAndWait()
    }

    func testReleaseAndWaitSharesFailedStartRollbackBoundary() async {
        let fixture = makeFixture(startPlans: [
            .init(succeeds: false)
        ])
        let rollbackGate = CameraViewModelTestGate()
        fixture.scheduler.setDrainGateForTesting(rollbackGate.semaphore)
        defer {
            rollbackGate.signal()
            fixture.scheduler.setDrainGateForTesting(nil)
        }

        let failedStart = Task { @MainActor in
            await fixture.viewModel.startAndWait()
        }
        let rollbackStarted = await waitUntil {
            fixture.pipeline.testingReleaseInProgress
        }
        XCTAssertTrue(rollbackStarted)

        let releaseCompletion = CompletionProbe()
        let release = Task { @MainActor in
            await fixture.viewModel.releaseAndWait()
            releaseCompletion.markCompleted()
        }

        let releaseStarted = await waitUntil {
            fixture.viewModel.lifecycleState == .stopping
        }
        XCTAssertTrue(releaseStarted)

        let releaseFinishedBeforeRollback = await waitUntil(timeout: .milliseconds(100)) {
            releaseCompletion.isCompleted
        }
        XCTAssertFalse(releaseFinishedBeforeRollback)
        XCTAssertEqual(fixture.runner.stopCount, 0)

        rollbackGate.signal()
        await failedStart.value
        await release.value
        fixture.scheduler.setDrainGateForTesting(nil)

        XCTAssertTrue(releaseCompletion.isCompleted)
        XCTAssertEqual(fixture.viewModel.lifecycleState, .idle)
        XCTAssertNil(fixture.viewModel.lifecycleError)
        XCTAssertEqual(fixture.scheduler.registrationCountForTesting, 0)
        XCTAssertEqual(fixture.manager.configurationState, .unconfigured)
        XCTAssertEqual(fixture.runner.registrationCountsAtStart, [3])
    }

    func testSuccessfulStartRemainsRunningWithExactlyThreeRegistrations() async {
        let fixture = makeFixture(startPlans: [
            .init(succeeds: true)
        ])

        await fixture.viewModel.startAndWait()

        XCTAssertEqual(fixture.viewModel.lifecycleState, .running)
        XCTAssertNil(fixture.viewModel.lifecycleError)
        XCTAssertEqual(fixture.scheduler.registrationCountForTesting, 3)

        await fixture.viewModel.releaseAndWait()
    }

    func testAnalysisFailureClearsStaleLiveAdviceAndPublishesFailure() async {
        let fixture = makeFixture(startPlans: [.init(succeeds: true)])
        await fixture.viewModel.startAndWait()

        fixture.viewModel.liveHint = LiveHintPresentation(
            id: "failure-hint",
            frameId: "failure-frame",
            text: "Move the frame.",
            confidence: 0.8,
            actionType: .moveFrameLeft,
            actionId: "failure-action",
            linkedIssueIds: [],
            summaryId: nil,
            traceRootIds: [],
            targetRegion: nil,
            overlayHint: nil,
            isFallback: false,
            expandedVerdict: nil
        )
        fixture.viewModel.overlayAnnotations = [
            OverlayAnnotationPresentation(
                id: "failure-annotation",
                kind: .regionHighlight,
                direction: nil,
                targetRegion: NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                emphasis: 1
            )
        ]

        fixture.viewModel.reportAnalysisFailure(.failed)

        XCTAssertEqual(fixture.viewModel.analysisStatus, .failed)
        XCTAssertEqual(fixture.viewModel.analysisFailure, .failed)
        XCTAssertNil(fixture.viewModel.liveHint)
        XCTAssertTrue(fixture.viewModel.overlayAnnotations.isEmpty)

        await fixture.viewModel.releaseAndWait()
    }

    func testPipelineTerminalFailurePublishesOnceAndClearsViewModelProjection() async {
        let fixture = makeFixture(startPlans: [.init(succeeds: true)])
        await fixture.viewModel.startAndWait()

        fixture.viewModel.liveHint = LiveHintPresentation(
            id: "producer-failure-hint",
            frameId: "producer-failure-frame",
            text: "Move the frame.",
            confidence: 0.8,
            actionType: .moveFrameLeft,
            actionId: "producer-failure-action",
            linkedIssueIds: [],
            summaryId: nil,
            traceRootIds: [],
            targetRegion: NormalizedRect(x: 0.7, y: 0.2, width: 0.2, height: 0.3),
            overlayHint: OverlayHint(
                id: "producer-failure-arrow",
                kind: .arrow,
                targetRegion: NormalizedRect(x: 0.7, y: 0.2, width: 0.2, height: 0.3),
                direction: .left
            ),
            isFallback: false,
            expandedVerdict: nil
        )
        fixture.viewModel.overlayAnnotations = [
            OverlayAnnotationPresentation(
                id: "producer-failure-annotation",
                kind: .regionHighlight,
                direction: nil,
                targetRegion: NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                emphasis: 1
            )
        ]

        let failureNotification = expectation(description: "one terminal failure notification")
        failureNotification.expectedFulfillmentCount = 1
        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: CameraAnalysisRuntimeSignal.failureNotification,
            object: nil,
            queue: .main
        ) { _ in
            notificationCount += 1
            failureNotification.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let generation = fixture.pipeline.testingLifecycleGeneration
        let staleGeneration = generation == 0 ? UInt64.max : generation - 1
        fixture.pipeline.testingPublishAnalysisRuntimeFailure(
            .failed,
            generation: staleGeneration
        )
        XCTAssertEqual(notificationCount, 0)

        fixture.pipeline.testingPublishAnalysisRuntimeFailure(.failed)
        fixture.pipeline.testingPublishAnalysisRuntimeFailure(.failed)
        await fulfillment(of: [failureNotification], timeout: 1)

        XCTAssertEqual(notificationCount, 1)
        XCTAssertEqual(fixture.viewModel.analysisStatus, .failed)
        XCTAssertEqual(fixture.viewModel.analysisFailure, .failed)
        XCTAssertNil(fixture.viewModel.liveHint)
        XCTAssertTrue(fixture.viewModel.overlayAnnotations.isEmpty)

        await fixture.viewModel.releaseAndWait()
    }

    func testInterruptionClearsProjectionReleasesOnceAndRetryWaitsForCleanup() async {
        let fixture = makeFixture(startPlans: [
            .init(succeeds: true),
            .init(succeeds: true)
        ])
        await fixture.viewModel.startAndWait()

        fixture.viewModel.isPaused = true
        fixture.viewModel.liveHint = LiveHintPresentation(
            id: "interruption-hint",
            frameId: "interruption-frame",
            text: "Move the frame.",
            confidence: 0.8,
            actionType: nil,
            actionId: nil,
            linkedIssueIds: [],
            summaryId: nil,
            traceRootIds: [],
            targetRegion: nil,
            overlayHint: nil,
            isFallback: false,
            expandedVerdict: nil
        )
        fixture.viewModel.overlayAnnotations = [
            OverlayAnnotationPresentation(
                id: "interruption-annotation",
                kind: .regionHighlight,
                direction: nil,
                targetRegion: NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                emphasis: 1
            )
        ]
        fixture.viewModel.currentLens = .telephoto

        let releaseGate = CameraViewModelTestGate()
        fixture.scheduler.setDrainGateForTesting(releaseGate.semaphore)
        defer {
            releaseGate.signal()
            fixture.scheduler.setDrainGateForTesting(nil)
        }

        fixture.viewModel.reportSceneInactive()

        // The projection boundary is synchronous; cleanup is intentionally still
        // allowed to drain in the background.
        XCTAssertEqual(fixture.viewModel.lifecycleState, .stopping)
        XCTAssertFalse(fixture.viewModel.isPaused)
        XCTAssertNil(fixture.viewModel.liveHint)
        XCTAssertTrue(fixture.viewModel.overlayAnnotations.isEmpty)
        XCTAssertEqual(fixture.viewModel.currentLens, .wide)

        let releaseStarted = await waitUntil {
            fixture.pipeline.testingReleaseInProgress
        }
        XCTAssertTrue(releaseStarted)
        XCTAssertEqual(fixture.runner.stopCount, 1)

        // Retry captures the shared release task and cannot reach a second
        // registration set while that task is fenced.
        fixture.viewModel.start()
        let secondStartBeforeCleanup = await waitUntil(timeout: .milliseconds(100)) {
            fixture.runner.startCount == 2
        }
        XCTAssertFalse(secondStartBeforeCleanup)

        releaseGate.signal()
        let retryRunning = await waitUntil {
            fixture.runner.startCount == 2
                && fixture.scheduler.registrationCountForTesting == 3
                && fixture.viewModel.lifecycleState == .running
        }
        fixture.scheduler.setDrainGateForTesting(nil)

        XCTAssertTrue(retryRunning)
        XCTAssertEqual(fixture.runner.stopCount, 1)
        XCTAssertEqual(fixture.runner.registrationCountsAtStart, [3, 3])
        XCTAssertEqual(fixture.viewModel.lifecycleState, .running)
        XCTAssertNil(fixture.viewModel.lifecycleError)

        await fixture.viewModel.releaseAndWait()
    }

    func testLateStartCompletionCannotOverwriteInterruptionFailure() async {
        let startGate = CameraViewModelTestGate()
        let fixture = makeFixture(startPlans: [
            .init(succeeds: true, gate: startGate)
        ])

        fixture.viewModel.start()
        let startEntered = await waitUntil {
            fixture.runner.startCount == 1
        }
        XCTAssertTrue(startEntered)

        fixture.viewModel.reportSceneInactive()
        XCTAssertEqual(fixture.viewModel.lifecycleState, .stopping)

        startGate.signal()
        let failurePreserved = await waitUntil {
            fixture.viewModel.lifecycleState == .failed(.sessionInterrupted)
        }

        XCTAssertTrue(failurePreserved)
        XCTAssertEqual(fixture.viewModel.lifecycleError, .sessionInterrupted)
        XCTAssertEqual(fixture.runner.startCount, 1)
        XCTAssertEqual(fixture.runner.stopCount, 1)
        XCTAssertEqual(fixture.scheduler.registrationCountForTesting, 0)

        await fixture.viewModel.releaseAndWait()
    }

    func testStaleReleaseWaiterDoesNotClearReplacementReleaseOperation() async {
        let fixture = makeFixture(startPlans: [
            .init(succeeds: true),
            .init(succeeds: true),
            .init(succeeds: true)
        ])
        await fixture.viewModel.startAndWait()

        let releaseGate = DispatchSemaphore(value: 0)
        fixture.scheduler.setDrainGateForTesting(releaseGate)
        defer {
            releaseGate.signal()
            releaseGate.signal()
            fixture.scheduler.setDrainGateForTesting(nil)
        }

        let replacementReleaseStarted = CompletionProbe()
        let releaseAndReplace = Task { @MainActor in
            await fixture.viewModel.releaseAndWait()
            await fixture.viewModel.startAndWait()
            replacementReleaseStarted.markCompleted()
            await fixture.viewModel.releaseAndWait()
        }
        let firstReleaseStarted = await waitUntil {
            fixture.pipeline.testingReleaseInProgress
        }
        XCTAssertTrue(firstReleaseStarted)

        // This waiter owns the first release boundary. The replacement release
        // is created by the first waiter after a fresh registration set exists.
        // It is intentionally superseded before the first release drains so its
        // completion is the stale continuation that must not clear the newer op.
        let staleStart = Task(priority: .background) { @MainActor in
            await fixture.viewModel.startAndWait()
        }
        await Task.yield()
        releaseGate.signal()

        let replacementInvoked = await waitUntil {
            replacementReleaseStarted.isCompleted
        }
        XCTAssertTrue(replacementInvoked)

        let replacementReleaseInProgress = await waitUntil {
            fixture.pipeline.testingReleaseInProgress
        }
        XCTAssertTrue(replacementReleaseInProgress)

        fixture.viewModel.start()
        let startedBeforeReplacementRelease = await waitUntil(timeout: .milliseconds(100)) {
            fixture.runner.startCount == 3
        }
        XCTAssertFalse(startedBeforeReplacementRelease)

        releaseGate.signal()
        let retryRunning = await waitUntil {
            fixture.runner.startCount == 3
                && fixture.scheduler.registrationCountForTesting == 3
                && fixture.viewModel.lifecycleState == .running
        }
        XCTAssertTrue(retryRunning)

        await staleStart.value
        await releaseAndReplace.value
        XCTAssertEqual(fixture.runner.stopCount, 2)
        XCTAssertEqual(fixture.viewModel.lifecycleState, .running)

        fixture.scheduler.setDrainGateForTesting(nil)
        await fixture.viewModel.releaseAndWait()
    }

    func testSupersededStopWaiterCannotStopRetry() async {
        let fixture = makeFixture(startPlans: [
            .init(succeeds: true),
            .init(succeeds: true)
        ])
        await fixture.viewModel.startAndWait()

        let releaseGate = CameraViewModelTestGate()
        fixture.scheduler.setDrainGateForTesting(releaseGate.semaphore)
        defer {
            releaseGate.signal()
            fixture.scheduler.setDrainGateForTesting(nil)
        }

        fixture.viewModel.reportSceneInactive()
        let releaseStarted = await waitUntil {
            fixture.pipeline.testingReleaseInProgress
        }
        XCTAssertTrue(releaseStarted)

        let staleStop = Task { @MainActor in
            await fixture.viewModel.stopAndWait()
        }
        await Task.yield()
        fixture.viewModel.start()

        let retryStartedBeforeRelease = await waitUntil(timeout: .milliseconds(100)) {
            fixture.runner.startCount == 2
        }
        XCTAssertFalse(retryStartedBeforeRelease)

        releaseGate.signal()
        let retryRunning = await waitUntil {
            fixture.runner.startCount == 2
                && fixture.scheduler.registrationCountForTesting == 3
                && fixture.viewModel.lifecycleState == .running
        }
        XCTAssertTrue(retryRunning)

        await staleStop.value
        XCTAssertEqual(fixture.runner.stopCount, 1)
        XCTAssertEqual(fixture.viewModel.lifecycleState, .running)

        fixture.scheduler.setDrainGateForTesting(nil)
        await fixture.viewModel.releaseAndWait()
    }

    func testPauseUsesAcceptedTakeCountAndResumeProjectsUntilStartRuns() async {
        let resumeGate = CameraViewModelTestGate()
        let fixture = makeFixture(startPlans: [
            .init(succeeds: true),
            .init(succeeds: true, gate: resumeGate)
        ])

        await fixture.viewModel.startAndWait()
        fixture.pipeline.ingestHigh(context: makeFrameContext(timestamp: 1))
        let evidenceReady = await waitUntil {
            fixture.pipeline.testingLatestFrameEvidence?.sourceFrameId == "frame_1000"
        }
        XCTAssertTrue(evidenceReady)

        fixture.viewModel.togglePause()
        let pauseAccepted = await waitUntil {
            fixture.viewModel.takeNumber == 1
                && fixture.viewModel.pausePresentationState.snapshotID == "frame_1000"
        }
        XCTAssertTrue(pauseAccepted)
        let pauseProjectionReady = await waitUntil {
            fixture.viewModel.isPaused && fixture.viewModel.isPauseProjectionReady
        }
        XCTAssertTrue(pauseProjectionReady)
        XCTAssertNotNil(fixture.viewModel.acceptedPauseSnapshot?.displayImage)

        fixture.viewModel.togglePause()
        XCTAssertFalse(fixture.viewModel.isPaused)
        XCTAssertEqual(fixture.viewModel.takeNumber, 1)
        if case .resuming(let snapshotID) = fixture.viewModel.pausePresentationState {
            XCTAssertEqual(snapshotID, "frame_1000")
        } else {
            XCTFail("resume must remain visibly represented until camera start succeeds")
        }

        resumeGate.signal()
        let resumed = await waitUntil {
            fixture.viewModel.lifecycleState == .running
                && fixture.viewModel.pausePresentationState == .idle
        }
        XCTAssertTrue(resumed)

        fixture.pipeline.ingestHigh(context: makeFrameContext(timestamp: 2))
        let secondEvidenceReady = await waitUntil {
            fixture.pipeline.testingLatestFrameEvidence?.sourceFrameId == "frame_2000"
        }
        XCTAssertTrue(secondEvidenceReady)
        fixture.viewModel.togglePause()
        let secondPauseAccepted = await waitUntil {
            fixture.viewModel.isPaused && fixture.viewModel.takeNumber == 2
        }
        XCTAssertTrue(secondPauseAccepted)

        await fixture.viewModel.releaseAndWait()
        XCTAssertEqual(fixture.viewModel.takeNumber, 0)
    }

    func testSelectedTeleLensPresentationSurvivesPauseResumeUntilManagerReportsAgain() async {
        let resumeGate = CameraViewModelTestGate()
        let fixture = makeFixture(startPlans: [
            .init(succeeds: true),
            .init(succeeds: true, gate: resumeGate)
        ])

        await fixture.viewModel.startAndWait()
        fixture.viewModel.currentLens = .telephoto
        fixture.pipeline.ingestHigh(context: makeFrameContext(timestamp: 3))
        let evidenceReady = await waitUntil {
            fixture.pipeline.testingLatestFrameEvidence?.sourceFrameId == "frame_3000"
        }
        XCTAssertTrue(evidenceReady)

        fixture.viewModel.togglePause()
        let paused = await waitUntil { fixture.viewModel.isPaused && fixture.viewModel.takeNumber == 1 }
        XCTAssertTrue(paused)
        fixture.viewModel.togglePause()
        XCTAssertEqual(fixture.viewModel.currentLens, .telephoto)

        resumeGate.signal()
        let resumed = await waitUntil {
            fixture.viewModel.lifecycleState == .running
                && fixture.viewModel.pausePresentationState == .idle
                && fixture.viewModel.currentLens == .telephoto
        }
        XCTAssertTrue(resumed)
        await fixture.viewModel.releaseAndWait()
    }

    func testPauseWithoutAcceptedEvidencePublishesRecoverableFailure() async {
        let fixture = makeFixture(startPlans: [.init(succeeds: true)])
        await fixture.viewModel.startAndWait()

        fixture.viewModel.togglePause()

        XCTAssertFalse(fixture.viewModel.isPaused)
        XCTAssertFalse(fixture.viewModel.isPauseProjectionReady)
        XCTAssertEqual(fixture.viewModel.pauseFailureReason, .noAcceptedEvidence)
        guard case .failure(let snapshotID) = fixture.viewModel.pausePresentationState else {
            return XCTFail("an unavailable accepted frame must be an explicit pause failure")
        }
        XCTAssertFalse(snapshotID.isEmpty)
        XCTAssertEqual(fixture.viewModel.takeNumber, 0)
        fixture.viewModel.togglePause()
        XCTAssertFalse(fixture.viewModel.isPaused)
        await fixture.viewModel.releaseAndWait()
    }

    private func makeFixture(startPlans: [CameraViewModelStartPlan]) -> CameraViewModelFixture {
        let scheduler = RealtimeScheduler()
        let thermalGovernor = ThermalGovernor(thermalStateProvider: { .nominal },
                                               batteryLevelProvider: { 1.0 })
        let runner = CameraViewModelTestSessionRunner(
            startPlans: startPlans,
            registrationCountProvider: { scheduler.registrationCountForTesting }
        )
        let manager = CameraManager(scheduler: scheduler,
                                    thermalGovernor: thermalGovernor,
                                    motionGate: MotionGate(startMotionUpdates: false),
                                    sessionRunner: runner,
                                    configuration: .ready,
                                    notificationCenter: NotificationCenter())
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil,
            thermalGovernor: thermalGovernor,
            neuralHeavyModelsEnabledProvider: { true },
            liveHybridFusionEnabled: false,
            demoLiveCoachEnabled: false
        )
        let viewModel = CameraViewModel(cameraManager: manager, analysisPipeline: pipeline)
        return CameraViewModelFixture(scheduler: scheduler,
                                      runner: runner,
                                      manager: manager,
                                      pipeline: pipeline,
                                      viewModel: viewModel)
    }

    private func waitUntil(timeout: Duration = .seconds(2),
                           _ condition: @escaping () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if condition() {
                return true
            }
            do {
                try await Task.sleep(nanoseconds: 1_000_000)
            } catch {
                return false
            }
        }
        return condition()
    }

    private func makeFrameContext(timestamp: Double) -> FrameContext {
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
            orientation: .up,
            isStable: true,
            shakeLevel: 0.05,
            motionState: .still
        )
    }

    private func isFailed(_ state: CameraLifecycleState) -> Bool {
        if case .failed = state {
            return true
        }
        return false
    }
}

private struct CameraViewModelStartPlan {
    let succeeds: Bool
    let gate: CameraViewModelTestGate?

    init(succeeds: Bool, gate: CameraViewModelTestGate? = nil) {
        self.succeeds = succeeds
        self.gate = gate
    }
}

private struct CameraViewModelFixture {
    let scheduler: RealtimeScheduler
    let runner: CameraViewModelTestSessionRunner
    let manager: CameraManager
    let pipeline: AnalysisPipeline
    let viewModel: CameraViewModel
}

private final class CompletionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    var isCompleted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }

    func markCompleted() {
        lock.lock()
        completed = true
        lock.unlock()
    }
}

private final class CameraViewModelTestSessionRunner: CameraSessionRunner {
    private let lock = NSLock()
    private var startPlans: [CameraViewModelStartPlan]
    private var starts = 0
    private var stops = 0
    private var running = false
    private var registrationCountsAtStartStorage: [Int] = []
    private var didTimeoutWaitingForStartGateStorage = false
    private let registrationCountProvider: () -> Int

    init(startPlans: [CameraViewModelStartPlan],
         registrationCountProvider: @escaping () -> Int) {
        self.startPlans = startPlans
        self.registrationCountProvider = registrationCountProvider
    }

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

    var registrationCountsAtStart: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return registrationCountsAtStartStorage
    }

    var didTimeoutWaitingForStartGate: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didTimeoutWaitingForStartGateStorage
    }

    func startRunning() {
        lock.lock()
        let plan = startPlans.isEmpty
            ? CameraViewModelStartPlan(succeeds: true)
            : startPlans.removeFirst()
        let registrationCountProvider = self.registrationCountProvider
        lock.unlock()

        let registrationCount = registrationCountProvider()

        lock.lock()
        starts += 1
        registrationCountsAtStartStorage.append(registrationCount)
        lock.unlock()

        let didOpenGate = plan.gate?.wait() ?? true

        lock.lock()
        if !didOpenGate {
            didTimeoutWaitingForStartGateStorage = true
        }
        running = plan.succeeds
        lock.unlock()
    }

    func stopRunning() {
        lock.lock()
        stops += 1
        running = false
        lock.unlock()
    }
}

private final class CameraViewModelTestGate: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var didSignal = false

    func signal() {
        lock.lock()
        guard !didSignal else {
            lock.unlock()
            return
        }
        didSignal = true
        lock.unlock()
        semaphore.signal()
    }

    @discardableResult
    func wait() -> Bool {
        semaphore.wait(timeout: .now() + .seconds(2)) == .success
    }

    deinit {
        signal()
    }
}
