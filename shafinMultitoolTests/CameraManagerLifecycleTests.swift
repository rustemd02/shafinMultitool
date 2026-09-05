import XCTest
import AVFoundation
import Combine
import CoreMedia
import CoreVideo
import ImageIO
import UIKit
@testable import shafinMultitool

final class CameraManagerLifecycleTests: XCTestCase {

    func testPhysicalLensInventoryHasOneTruthfulTelephotoDescriptor() {
        XCTAssertEqual(CameraLens.allCases, [.ultraWide, .wide, .telephoto])
        XCTAssertEqual(CameraLens.telephoto.displayName, "TELE")
        XCTAssertFalse(CameraLens.allCases.map(\.displayName).joined(separator: " ").contains("×"))
    }

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

    func testExactSessionInterruptionAndRuntimeNotificationsFailOnceAndCloseFrameGate() async throws {
        let notificationCenter = NotificationCenter()
        let session = AVCaptureSession()
        let runner = FakeCameraSessionRunner()
        let thermalGovernor = makeThermalGovernor()
        let manager = CameraManager(scheduler: RealtimeScheduler(),
                                    thermalGovernor: thermalGovernor,
                                    motionGate: MotionGate(),
                                    sessionRunner: runner,
                                    configuration: .ready,
                                    session: session,
                                    notificationCenter: notificationCenter)
        var failures: [CameraManagerError] = []
        let subscription = manager.failurePublisher.sink { failures.append($0) }
        defer { subscription.cancel() }

        try await manager.startAndWait()
        XCTAssertTrue(manager.frameDeliveryEnabledForTesting)

        notificationCenter.post(name: AVCaptureSession.wasInterruptedNotification,
                                object: AVCaptureSession())
        XCTAssertTrue(failures.isEmpty)
        XCTAssertTrue(manager.frameDeliveryEnabledForTesting)

        notificationCenter.post(name: AVCaptureSession.wasInterruptedNotification,
                                object: session)
        XCTAssertFalse(manager.frameDeliveryEnabledForTesting)
        XCTAssertEqual(manager.lifecycleState, .failed(.sessionInterrupted))
        XCTAssertEqual(manager.lifecycleError, .sessionInterrupted)
        XCTAssertEqual(failures, [.sessionInterrupted])

        notificationCenter.post(name: AVCaptureSession.runtimeErrorNotification,
                                object: session)
        XCTAssertEqual(failures, [.sessionInterrupted])

        await manager.releaseAndWait()
        try await manager.startAndWait()
        notificationCenter.post(name: AVCaptureSession.runtimeErrorNotification,
                                object: session)

        XCTAssertFalse(manager.frameDeliveryEnabledForTesting)
        XCTAssertEqual(manager.lifecycleState, .failed(.runtimeError))
        XCTAssertEqual(manager.lifecycleError, .runtimeError)
        XCTAssertEqual(failures, [.sessionInterrupted, .runtimeError])
        await manager.releaseAndWait()
    }

    func testConcurrentSessionFailuresPublishOnlyOneClaim() async throws {
        let notificationCenter = NotificationCenter()
        let session = AVCaptureSession()
        let manager = CameraManager(scheduler: RealtimeScheduler(),
                                    thermalGovernor: makeThermalGovernor(),
                                    motionGate: MotionGate(),
                                    sessionRunner: FakeCameraSessionRunner(),
                                    configuration: .ready,
                                    session: session,
                                    notificationCenter: notificationCenter)
        let failureLock = NSLock()
        var failures: [CameraManagerError] = []
        let subscription = manager.failurePublisher.sink { error in
            failureLock.lock()
            failures.append(error)
            failureLock.unlock()
        }
        defer { subscription.cancel() }

        try await manager.startAndWait()

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "CameraManagerLifecycleTests.ConcurrentFailures",
                                  attributes: .concurrent)
        for name in [AVCaptureSession.wasInterruptedNotification,
                     AVCaptureSession.runtimeErrorNotification] {
            group.enter()
            queue.async {
                notificationCenter.post(name: name, object: session)
                group.leave()
            }
        }
        group.wait()

        failureLock.lock()
        let publishedFailures = failures
        failureLock.unlock()
        XCTAssertEqual(publishedFailures.count, 1)
        guard let publishedFailure = publishedFailures.first else {
            return XCTFail("one concurrent failure must be published")
        }
        XCTAssertEqual(manager.lifecycleState, .failed(publishedFailure))
        XCTAssertFalse(manager.frameDeliveryEnabledForTesting)

        await manager.releaseAndWait()
    }

    func testNotificationWinsFinalStartTransition() async throws {
        let notificationCenter = NotificationCenter()
        let session = AVCaptureSession()
        let runner = FakeCameraSessionRunner()
        let manager = CameraManager(scheduler: RealtimeScheduler(),
                                    thermalGovernor: makeThermalGovernor(),
                                    motionGate: MotionGate(),
                                    sessionRunner: runner,
                                    configuration: .ready,
                                    session: session,
                                    notificationCenter: notificationCenter)
        runner.onStart = {
            notificationCenter.post(name: AVCaptureSession.runtimeErrorNotification,
                                    object: session)
        }

        do {
            try await manager.startAndWait()
            XCTFail("the claimed runtime failure must win the start transition")
        } catch let error as CameraManagerError {
            XCTAssertEqual(error, .runtimeError)
        }

        XCTAssertEqual(runner.startCount, 1)
        XCTAssertEqual(runner.stopCount, 1)
        XCTAssertEqual(manager.lifecycleState, .failed(.runtimeError))
        XCTAssertEqual(manager.lifecycleError, .runtimeError)
        XCTAssertFalse(manager.frameDeliveryEnabledForTesting)

        await manager.releaseAndWait()
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

    func testPreviewGeometryIsValidatedAndClearedByItsCameraOwner() {
        let (manager, _) = makeManager()
        XCTAssertNil(CameraPreviewGeometry(
            destinationSize: .zero,
            imageOrientation: .up,
            isMirrored: false
        ))

        let geometry = CameraPreviewGeometry(
            destinationSize: CGSize(width: 390, height: 844),
            imageOrientation: .right,
            isMirrored: false
        )
        XCTAssertNotNil(geometry)
        manager.updatePreviewGeometry(geometry)
        XCTAssertEqual(manager.previewGeometryForTesting, geometry)

        manager.clearPreviewGeometry()
        XCTAssertNil(manager.previewGeometryForTesting)
    }

    @MainActor
    func testPreviewViewClearsStaleGeometryWhenRemovedFromWindow() {
        let (manager, _) = makeManager()
        let preview = PreviewView()
        preview.cameraManager = manager
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.addSubview(preview)
        XCTAssertNotNil(preview.window)

        let staleGeometry = CameraPreviewGeometry(
            destinationSize: CGSize(width: 390, height: 844),
            imageOrientation: .right,
            isMirrored: false
        )!
        manager.updatePreviewGeometry(staleGeometry)

        preview.removeFromSuperview()

        XCTAssertNil(
            manager.previewGeometryForTesting,
            "PreviewView removal must clear stale camera-owned geometry"
        )
    }

    @MainActor
    func testPreviewViewDoesNotRepublishGeometryForUnchangedRegionUpdate() async throws {
        let (manager, _) = makeManager()
        try await manager.startAndWait()
        defer {
            Task { @MainActor in
                await manager.releaseAndWait()
            }
        }

        let preview = PreviewView()
        preview.cameraManager = manager
        preview.interfaceOrientationOverrideForTesting = .portrait
        preview.videoConnectionOverrideForTesting = AVCaptureConnection(
            inputPorts: [],
            output: AVCaptureVideoDataOutput()
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.addSubview(preview)
        preview.frame = window.bounds
        preview.layoutIfNeeded()
        await Task.yield()
        preview.layoutIfNeeded()

        guard let geometry = manager.previewGeometryForTesting else {
            return XCTFail("PreviewView must publish measurable geometry before region updates")
        }
        var boundaryCalls = 0
        manager.beforePreviewGeometryBoundaryForTesting = { boundaryCalls += 1 }
        let boundaryCallsBeforeRegionUpdate = boundaryCalls

        preview.subjectRegions = [NormalizedRect(x: 0.20, y: 0.20, width: 0.30, height: 0.40)]
        preview.layoutIfNeeded()
        preview.updateOrientation()
        preview.updateMappedRegions()

        XCTAssertEqual(manager.previewGeometryForTesting, geometry)
        XCTAssertEqual(
            boundaryCalls,
            boundaryCallsBeforeRegionUpdate,
            "an unchanged region update must not cross the camera geometry boundary"
        )
        manager.beforePreviewGeometryBoundaryForTesting = nil
    }

    @MainActor
    func testCameraPreviewRebindingClearsOldOwnerAndRepublishesGeometryToNewOwner() {
        let (oldManager, _) = makeManager()
        let (newManager, _) = makeManager()
        let oldSession = AVCaptureSession()
        let newSession = AVCaptureSession()
        let preview = PreviewView()
        preview.videoPreviewLayer.session = oldSession
        preview.videoConnectionOverrideForTesting = AVCaptureConnection(
            inputPorts: [],
            output: AVCaptureVideoDataOutput()
        )
        preview.cameraManager = oldManager
        preview.interfaceOrientationOverrideForTesting = .portrait

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.addSubview(preview)
        preview.frame = window.bounds
        preview.layoutIfNeeded()
        guard let oldGeometry = oldManager.previewGeometryForTesting else {
            return XCTFail("initial PreviewView owner must publish geometry")
        }

        let updatedPreview = CameraPreview(session: newSession, cameraManager: newManager)
        updatedPreview.updateUIViewForTesting(preview)

        XCTAssertNil(
            oldManager.previewGeometryForTesting,
            "rebinding must clear geometry retained by the previous camera owner"
        )
        XCTAssertEqual(
            newManager.previewGeometryForTesting,
            oldGeometry,
            "rebinding must republish the same measurable geometry to the new owner"
        )
        XCTAssertTrue(preview.cameraManager === newManager)
        XCTAssertTrue(preview.videoPreviewLayer.session === newSession)
        preview.removeFromSuperview()
    }

    func testConcurrentPreviewGeometryUpdatesRevalidateEqualityAtCaptureBoundary() {
        let (manager, _) = makeManager()
        let geometry = CameraPreviewGeometry(
            destinationSize: CGSize(width: 390, height: 844),
            imageOrientation: .right,
            isMirrored: false
        )!
        let firstEntered = DispatchSemaphore(value: 0)
        let releaseFirst = DispatchSemaphore(value: 0)
        let hookLock = NSLock()
        var shouldPause = true
        manager.beforePreviewGeometryBoundaryForTesting = {
            hookLock.lock()
            let pause = shouldPause
            shouldPause = false
            hookLock.unlock()
            if pause {
                firstEntered.signal()
                releaseFirst.wait()
            }
        }

        let firstDone = DispatchSemaphore(value: 0)
        let secondDone = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(
            label: "CameraManagerLifecycleTests.ConcurrentPreviewGeometry",
            attributes: .concurrent
        )
        queue.async {
            manager.updatePreviewGeometry(geometry)
            firstDone.signal()
        }
        XCTAssertEqual(firstEntered.wait(timeout: .now() + 1), .success)

        queue.async {
            manager.updatePreviewGeometry(geometry)
            secondDone.signal()
        }
        XCTAssertEqual(secondDone.wait(timeout: .now() + 1), .success)

        releaseFirst.signal()
        XCTAssertEqual(firstDone.wait(timeout: .now() + 1), .success)
        manager.beforePreviewGeometryBoundaryForTesting = nil

        XCTAssertEqual(manager.previewGeometryForTesting, geometry)
        XCTAssertEqual(
            manager.previewGeometryMutationsForTesting,
            1,
            "capture-boundary equality must be revalidated after a concurrent update"
        )
    }

    func testCaptureOutputBindsLensAndPreviewGeometryBeforeAnalysisPipelineReceivesFrame() async throws {
        let (manager, _) = makeManager()
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil,
            thermalGovernor: makeThermalGovernor(),
            neuralHeavyModelsEnabledProvider: { true },
            liveHybridFusionEnabled: false,
            demoLiveCoachEnabled: false
        )
        XCTAssertTrue(pipeline.register(with: manager))
        try await manager.startAndWait()

        let geometry = CameraPreviewGeometry(
            destinationSize: CGSize(width: 390, height: 844),
            imageOrientation: .down,
            isMirrored: true
        )!
        manager.updatePreviewGeometry(geometry)

        let output = AVCaptureVideoDataOutput()
        let connection = AVCaptureConnection(inputPorts: [], output: output)
        let sampleBuffer = try makeVideoSampleBuffer(
            pixelBuffer: makePixelBuffer(width: 16, height: 16),
            timestamp: CMTime(value: 1, timescale: 30)
        )
        manager.captureOutput(output, didOutput: sampleBuffer, from: connection)

        await manager.drainSchedulerAndWait()
        await pipeline.testingDrainHighQueue()

        let evidence = try XCTUnwrap(pipeline.testingLatestFrameEvidence)
        XCTAssertEqual(evidence.lensID, CameraLens.wide.rawValue)
        XCTAssertEqual(evidence.previewGeometry, geometry)
        XCTAssertEqual(evidence.orientation, .down)
        XCTAssertEqual(evidence.lensGeneration, 1)

        await pipeline.releaseAndWait()
        await manager.releaseAndWait()
    }

    func testVideoDataConnectionConfiguratorRequestsNativeRotationAndNoMirroring() {
        let supported = CameraDataOutputConnectionFake(
            supportsRotation: true,
            supportsMirroring: true
        )
        CameraDataOutputConnectionConfigurator.applyNativeGeometry(to: supported)

        XCTAssertEqual(supported.rotationSupportChecks, [0])
        XCTAssertEqual(supported.rotationAssignments, [0])
        XCTAssertEqual(supported.configurationEvents, ["automatic:false", "mirrored:false"])

        let unsupported = CameraDataOutputConnectionFake(
            supportsRotation: false,
            supportsMirroring: false
        )
        CameraDataOutputConnectionConfigurator.applyNativeGeometry(to: unsupported)

        XCTAssertEqual(unsupported.rotationSupportChecks, [0])
        XCTAssertTrue(unsupported.rotationAssignments.isEmpty)
        XCTAssertEqual(unsupported.configurationEvents, ["automatic:false"])
        XCTAssertEqual(
            CameraFrameDeliveryOrientationContract.imageOrientation(for: .portrait),
            .right
        )
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

    func testStopDuringGatedStartFinishesIdleWithoutRevival() async throws {
        // Isolated NotificationCenter: the gated window would otherwise admit
        // async simulator AVCaptureSession noise (FigCaptureSessionSimulator)
        // that other (fast, non-gated) tests never observe.
        let runner = FakeCameraSessionRunner()
        let startEntered = expectation(description: "runner start entered")
        runner.onStart = { startEntered.fulfill() }
        runner.startGate = DispatchSemaphore(value: 0)
        let manager = CameraManager(scheduler: RealtimeScheduler(),
                                    thermalGovernor: makeThermalGovernor(),
                                    motionGate: MotionGate(),
                                    sessionRunner: runner,
                                    configuration: .ready,
                                    notificationCenter: NotificationCenter())

        let startTask = Task { try await manager.startAndWait() }
        await fulfillment(of: [startEntered], timeout: 1.0)

        let stopTask = Task { await manager.stopAndWait() }
        runner.allowStart()
        try await startTask.value
        await stopTask.value

        XCTAssertEqual(runner.startCount, 1)
        XCTAssertEqual(runner.stopCount, 1)
        XCTAssertEqual(manager.lifecycleState, .idle)
    }

    func testStopRequestedBeforeStartReattachKeepsFrameGateClosed() async throws {
        let (manager, _) = makeManager()
        let reattachEntered = expectation(description: "start reached frame reattach")
        let reattachGate = DispatchSemaphore(value: 0)
        manager.beforeFrameDeliveryEnableForTesting = {
            reattachEntered.fulfill()
            reattachGate.wait()
        }

        let startTask = Task { try await manager.startAndWait() }
        await fulfillment(of: [reattachEntered], timeout: 1)
        let stopTask = Task { await manager.stopAndWait() }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while manager.sessionGenerationForTesting == 0, clock.now < deadline {
            await Task.yield()
        }
        XCTAssertEqual(manager.sessionGenerationForTesting, 1)
        reattachGate.signal()

        try await startTask.value
        await stopTask.value
        XCTAssertFalse(manager.frameDeliveryEnabledForTesting)
        // Initial input configuration owns generation 1; stop closes it with generation 2.
        XCTAssertEqual(manager.captureGenerationForTesting, 2)
        XCTAssertEqual(manager.lifecycleState, .idle)
    }

    func testFailureDuringOrientationReattachCannotReopenFrameGate() async throws {
        let notificationCenter = NotificationCenter()
        let runner = FakeCameraSessionRunner()
        let manager = CameraManager(
            scheduler: RealtimeScheduler(),
            thermalGovernor: makeThermalGovernor(),
            motionGate: MotionGate(),
            sessionRunner: runner,
            configuration: .ready,
            notificationCenter: notificationCenter
        )
        try await manager.startAndWait()

        let reattachEntered = expectation(description: "orientation reached frame reattach")
        let reattachGate = DispatchSemaphore(value: 0)
        manager.beforeFrameDeliveryEnableForTesting = {
            reattachEntered.fulfill()
            reattachGate.wait()
        }
        let orientationTask = Task {
            await manager.setVideoOrientationAndWait(.portrait)
        }
        await fulfillment(of: [reattachEntered], timeout: 1)

        notificationCenter.post(
            name: AVCaptureSession.runtimeErrorNotification,
            object: manager.captureSession
        )
        reattachGate.signal()
        await orientationTask.value

        XCTAssertFalse(manager.frameDeliveryEnabledForTesting)
        XCTAssertEqual(manager.captureGenerationForTesting, 2)
        XCTAssertEqual(manager.lifecycleState, .failed(.runtimeError))
    }

    func testSessionGenerationBumpsOnStopAndReleaseOnly() async throws {
        let (manager, _) = makeManager()
        XCTAssertEqual(manager.sessionGenerationForTesting, 0)

        try await manager.startAndWait()
        XCTAssertEqual(manager.sessionGenerationForTesting, 0)

        await manager.stopAndWait()
        XCTAssertEqual(manager.sessionGenerationForTesting, 1)

        try await manager.startAndWait()
        XCTAssertEqual(manager.sessionGenerationForTesting, 1)
        XCTAssertEqual(manager.lifecycleState, .running)

        let releaseGeneration = manager.sessionGenerationForTesting
        await manager.releaseAndWait()
        XCTAssertEqual(manager.sessionGenerationForTesting, releaseGeneration + 1)
        XCTAssertEqual(manager.lifecycleState, .idle)
        XCTAssertEqual(manager.configurationState, .unconfigured)
    }

    func testSequentialDoubleStopStopsRunnerOnceAndStaysIdle() async throws {
        let (manager, runner) = makeManager()
        try await manager.startAndWait()

        await manager.stopAndWait()
        await manager.stopAndWait()

        XCTAssertEqual(runner.stopCount, 1)
        XCTAssertEqual(manager.lifecycleState, .idle)
        XCTAssertEqual(manager.configurationState, .configured)
    }

    private func makeManager(
        configuration: CameraManagerTestConfiguration = .ready,
        notificationCenter: NotificationCenter = NotificationCenter()
    ) -> (CameraManager, FakeCameraSessionRunner) {
        let runner = FakeCameraSessionRunner()
        let thermalGovernor = makeThermalGovernor()
        let manager = CameraManager(scheduler: RealtimeScheduler(),
                                    thermalGovernor: thermalGovernor,
                                    motionGate: MotionGate(),
                                    sessionRunner: runner,
                                    configuration: configuration,
                                    notificationCenter: notificationCenter)
        return (manager, runner)
    }

    private func makeThermalGovernor() -> ThermalGovernor {
        ThermalGovernor(thermalStateProvider: { .nominal },
                         batteryLevelProvider: { 1.0 })
    }

    private func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        return pixelBuffer!
    }

    private func makeVideoSampleBuffer(
        pixelBuffer: CVPixelBuffer,
        timestamp: CMTime
    ) throws -> CMSampleBuffer {
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: timestamp,
            decodeTimeStamp: .invalid
        )
        var formatDescription: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            throw NSError(domain: "CameraManagerLifecycleTests", code: Int(formatStatus))
        }
        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else {
            throw NSError(domain: "CameraManagerLifecycleTests", code: Int(status))
        }
        return sampleBuffer
    }
}

@available(iOS 17.0, *)
private final class CameraDataOutputConnectionFake: CameraDataOutputRotationConnectionConfiguring {
    let supportsRotation: Bool
    let supportsMirroring: Bool
    private(set) var rotationSupportChecks: [CGFloat] = []
    private(set) var rotationAssignments: [CGFloat] = []
    private(set) var configurationEvents: [String] = []

    var videoRotationAngle: CGFloat = 90 {
        didSet { rotationAssignments.append(videoRotationAngle) }
    }

    var automaticallyAdjustsVideoMirroring: Bool = true {
        didSet { configurationEvents.append("automatic:\(automaticallyAdjustsVideoMirroring)") }
    }

    var isVideoMirroringSupported: Bool { supportsMirroring }

    var isVideoMirrored: Bool = true {
        didSet { configurationEvents.append("mirrored:\(isVideoMirrored)") }
    }

    init(supportsRotation: Bool, supportsMirroring: Bool) {
        self.supportsRotation = supportsRotation
        self.supportsMirroring = supportsMirroring
    }

    func isVideoRotationAngleSupported(_ videoRotationAngle: CGFloat) -> Bool {
        rotationSupportChecks.append(videoRotationAngle)
        return supportsRotation && videoRotationAngle == 0
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
