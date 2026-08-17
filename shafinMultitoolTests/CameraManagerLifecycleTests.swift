import XCTest
import AVFoundation
import ImageIO
import UIKit
@testable import shafinMultitool

final class CameraManagerLifecycleTests: XCTestCase {

    func testConcurrentStartsInvokeRunnerOnceAndFinishRunning() async throws {
        let (manager, runner) = makeManager()

        async let firstStart: Void = manager.startAndWait()
        async let secondStart: Void = manager.startAndWait()
        try await firstStart
        try await secondStart

        XCTAssertEqual(runner.startCount, 1)
        XCTAssertEqual(manager.lifecycleState, .running)
        XCTAssertEqual(manager.configurationState, .configured)
    }

    func testConcurrentStopsInvokeRunnerOnceAndFinishIdleConfigured() async throws {
        let (manager, runner) = makeManager()
        try await manager.startAndWait()

        async let firstStop: Void = manager.stopAndWait()
        async let secondStop: Void = manager.stopAndWait()
        await firstStop
        await secondStop

        XCTAssertEqual(runner.stopCount, 1)
        XCTAssertEqual(manager.lifecycleState, .idle)
        XCTAssertEqual(manager.configurationState, .configured)
    }

    func testStartStopStartUsesOneConfigurationAndTwoStarts() async throws {
        let (manager, runner) = makeManager()

        try await manager.startAndWait()
        await manager.stopAndWait()
        try await manager.startAndWait()

        XCTAssertEqual(runner.startCount, 2)
        XCTAssertEqual(runner.stopCount, 1)
        XCTAssertEqual(manager.configurationCountForTesting, 1)
        XCTAssertEqual(manager.lifecycleState, .running)
    }

    func testReleaseIsIdempotentAndStartAfterReleaseReconfiguresOnce() async throws {
        let (manager, runner) = makeManager()
        let sessionIdentity = ObjectIdentifier(manager.captureSession)

        try await manager.startAndWait()
        await manager.releaseAndWait()
        await manager.releaseAndWait()

        XCTAssertEqual(runner.stopCount, 1)
        XCTAssertEqual(manager.lifecycleState, .idle)
        XCTAssertEqual(manager.configurationState, .unconfigured)
        XCTAssertTrue(manager.availableLenses.isEmpty)
        XCTAssertEqual(ObjectIdentifier(manager.captureSession), sessionIdentity)

        try await manager.startAndWait()

        XCTAssertEqual(runner.startCount, 2)
        XCTAssertEqual(manager.configurationCountForTesting, 2)
        XCTAssertEqual(manager.lifecycleState, .running)
    }

    func testConfigurationFailureNeverStartsRunnerAndPublishesTypedError() async {
        let failures: [CameraManagerError] = [
            .noWideCamera,
            .inputConstructionFailed,
            .inputAddFailed,
            .outputAddFailed
        ]

        for failure in failures {
            let (manager, runner) = makeManager(configuration: .failure(failure))

            do {
                try await manager.startAndWait()
                XCTFail("Expected configuration failure to be thrown")
            } catch let error as CameraManagerError {
                XCTAssertEqual(error, failure)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }

            XCTAssertEqual(runner.startCount, 0)
            XCTAssertEqual(manager.lifecycleState, .failed(failure))
            XCTAssertEqual(manager.lifecycleError, failure)

            await manager.releaseAndWait()
            XCTAssertEqual(manager.lifecycleState, .idle)
            XCTAssertEqual(manager.configurationState, .unconfigured)
        }
    }

    func testFrameDeliveryGateOnlyEnablesAfterStartAndFencesStopAndRelease() async throws {
        let (manager, _) = makeManager()

        XCTAssertFalse(manager.frameDeliveryEnabledForTesting)

        try await manager.startAndWait()
        XCTAssertTrue(manager.frameDeliveryEnabledForTesting)

        await manager.stopAndWait()
        XCTAssertFalse(manager.frameDeliveryEnabledForTesting)

        try await manager.startAndWait()
        XCTAssertTrue(manager.frameDeliveryEnabledForTesting)

        await manager.releaseAndWait()
        XCTAssertFalse(manager.frameDeliveryEnabledForTesting)
    }

    func testOrientationMappingKeepsInterfaceCaptureAndImageSemanticsTogether() throws {
        let cases: [(UIInterfaceOrientation, AVCaptureVideoOrientation, CGImagePropertyOrientation)] = [
            (.portrait, .portrait, .right),
            (.portraitUpsideDown, .portraitUpsideDown, .left),
            (.landscapeLeft, .landscapeLeft, .down),
            (.landscapeRight, .landscapeRight, .up)
        ]

        for (interfaceOrientation, captureOrientation, imageOrientation) in cases {
            let orientation = try XCTUnwrap(
                CameraCoachOrientation(interfaceOrientation: interfaceOrientation)
            )
            XCTAssertEqual(orientation.captureOrientation, captureOrientation)
            XCTAssertEqual(orientation.interfaceOrientation, interfaceOrientation)
            XCTAssertEqual(orientation.imageOrientation, imageOrientation)
            XCTAssertEqual(
                CameraCoachOrientation(captureOrientation: captureOrientation),
                orientation
            )
        }
    }

    func testOrientationChangesInPlaceWithoutLifecycleReset() async throws {
        let (manager, runner) = makeManager()
        let sessionIdentity = ObjectIdentifier(manager.captureSession)

        try await manager.startAndWait()
        let configurationCount = manager.configurationCountForTesting

        await manager.setVideoOrientationAndWait(.portrait)
        let portraitOrientation = await manager.videoOrientationAndWait()

        XCTAssertEqual(portraitOrientation, .portrait)
        XCTAssertEqual(manager.lifecycleState, .running)
        XCTAssertEqual(manager.configurationCountForTesting, configurationCount)
        XCTAssertEqual(ObjectIdentifier(manager.captureSession), sessionIdentity)

        await manager.setVideoOrientationAndWait(.landscapeRight)
        let landscapeOrientation = await manager.videoOrientationAndWait()

        XCTAssertEqual(landscapeOrientation, .landscapeRight)
        XCTAssertEqual(manager.lifecycleState, .running)
        XCTAssertEqual(manager.configurationCountForTesting, configurationCount)
        XCTAssertEqual(ObjectIdentifier(manager.captureSession), sessionIdentity)
        XCTAssertEqual(runner.startCount, 1)
        XCTAssertEqual(runner.stopCount, 0)
    }

    func testOrientationSetBeforeStartIsAppliedWhenConfigurationIsCreated() async throws {
        let (manager, _) = makeManager()

        await manager.setVideoOrientationAndWait(.portraitUpsideDown)
        try await manager.startAndWait()

        let orientation = await manager.videoOrientationAndWait()
        XCTAssertEqual(orientation, .portraitUpsideDown)
        XCTAssertEqual(manager.lifecycleState, .running)
    }

    @MainActor
    func testStaleStartCompletionCannotOverwriteNewerStopStateOrError() async throws {
        let runner = FakeCameraSessionRunner()
        let startEntered = expectation(description: "runner start entered")
        runner.onStart = { startEntered.fulfill() }
        runner.startGate = DispatchSemaphore(value: 0)

        let thermalGovernor = makeThermalGovernor()
        let manager = CameraManager(scheduler: RealtimeScheduler(),
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
        let viewModel = CameraViewModel(cameraManager: manager, analysisPipeline: pipeline)

        let startTask = Task { @MainActor in
            await viewModel.startAndWait()
        }
        await fulfillment(of: [startEntered], timeout: 1.0)

        viewModel.stop()
        XCTAssertEqual(viewModel.lifecycleState, .stopping)

        runner.allowStart()
        await startTask.value
        await viewModel.stopAndWait()

        XCTAssertEqual(viewModel.lifecycleState, .idle)
        XCTAssertNil(viewModel.lifecycleError)
    }

    private func makeManager(
        configuration: CameraManagerTestConfiguration = .ready
    ) -> (CameraManager, FakeCameraSessionRunner) {
        let runner = FakeCameraSessionRunner()
        let thermalGovernor = makeThermalGovernor()
        let manager = CameraManager(scheduler: RealtimeScheduler(),
                                    thermalGovernor: thermalGovernor,
                                    motionGate: MotionGate(),
                                    sessionRunner: runner,
                                    configuration: configuration)
        return (manager, runner)
    }

    private func makeThermalGovernor() -> ThermalGovernor {
        ThermalGovernor(thermalStateProvider: { .nominal },
                         batteryLevelProvider: { 1.0 })
    }
}

private final class FakeCameraSessionRunner: CameraSessionRunner {
    private let lock = NSLock()
    private var running = false
    private var starts = 0
    private var stops = 0

    var startGate: DispatchSemaphore?
    var onStart: (() -> Void)?

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
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

    func startRunning() {
        lock.lock()
        starts += 1
        let gate = startGate
        let callback = onStart
        lock.unlock()

        callback?()
        gate?.wait()

        lock.lock()
        running = true
        lock.unlock()
    }

    func stopRunning() {
        lock.lock()
        stops += 1
        running = false
        lock.unlock()
    }

    func allowStart() {
        startGate?.signal()
    }
}
