import CoreVideo
import AVFoundation
import ARKit
import Foundation
import XCTest
@testable import shafinMultitool

@MainActor
final class SceneRecordingControllerTests: XCTestCase {

    func testTimestampGateRejectsStaleFramesAndAllowsFreshTake() async throws {
        let (controller, box, temporaryDirectory) = try makeController()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let pixelBuffer = try makePixelBuffer(width: 640, height: 480)
        controller.enqueueVideo(pixelBuffer, at: 0)

        try await controller.start(requestedFPS: 30, audioMode: .disabled)
        let firstRecorder = try XCTUnwrap(box.recorder(at: 0))
        let firstSourceToken = try XCTUnwrap(controller.recordingSourceToken)

        controller.enqueueVideo(pixelBuffer, at: 0.010, ownerToken: controller.recordingSourceToken)
        controller.enqueueVideo(pixelBuffer, at: 0.020, ownerToken: controller.recordingSourceToken)
        controller.enqueueVideo(pixelBuffer, at: 0.021, ownerToken: controller.recordingSourceToken)
        controller.enqueueVideo(pixelBuffer, at: 0.040, ownerToken: controller.recordingSourceToken)
        controller.enqueueVideo(pixelBuffer, at: 0.040, ownerToken: controller.recordingSourceToken)
        controller.enqueueVideo(pixelBuffer, at: 0.030, ownerToken: controller.recordingSourceToken)
        controller.enqueueVideo(pixelBuffer, at: .nan, ownerToken: controller.recordingSourceToken)
        controller.enqueueVideo(pixelBuffer, at: .infinity, ownerToken: controller.recordingSourceToken)

        XCTAssertEqual(firstRecorder.enqueuedTimestamps, [0, 0.010, 0.020, 0.021, 0.040])
        XCTAssertEqual(firstRecorder.configuration?.width, 640)
        XCTAssertEqual(firstRecorder.configuration?.height, 480)

        let firstResult = await controller.stop(reason: .user)
        XCTAssertEqual(firstRecorder.stopCount, 1)

        // The old fence is closed before finalization and cannot append after
        // stop, even though the AR delegate may still be delivering frames.
        controller.enqueueVideo(pixelBuffer, at: 0.050)
        XCTAssertEqual(firstRecorder.enqueuedTimestamps, [0, 0.010, 0.020, 0.021, 0.040])

        controller.enqueueVideo(pixelBuffer, at: 20)
        try await controller.start(
            firstPixelBuffer: pixelBuffer,
            requestedFPS: 30,
            audioMode: .disabled,
            timestamp: 20
        )
        let secondRecorder = try XCTUnwrap(box.recorder(at: 1))
        let secondSourceToken = try XCTUnwrap(controller.recordingSourceToken)

        XCTAssertNotEqual(firstRecorder.configuration?.id, secondRecorder.configuration?.id)
        XCTAssertEqual(secondSourceToken.ownerID, firstSourceToken.ownerID)
        XCTAssertGreaterThan(secondSourceToken.generation, firstSourceToken.generation)
        XCTAssertEqual(secondRecorder.configuration?.width, 640)
        XCTAssertEqual(secondRecorder.configuration?.height, 480)
        XCTAssertEqual(secondRecorder.enqueuedTimestamps, [20])

        let secondResult = await controller.stop(reason: .user)
        XCTAssertNotNil(firstResult)
        XCTAssertNotNil(secondResult)
        _ = await controller.releaseAndWait()
        XCTAssertNil(controller.recordingSourceToken)
    }

    func testCoordinatorRebindPreservesActiveSourceAndForeignCoordinatorCannotBorrowToken() async throws {
        let (controller, box, temporaryDirectory) = try makeController()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let viewModel = SceneGeneratorViewModel(recordingController: controller)
        let firstRuntime = RecordingCoordinatorRuntime()
        let firstCoordinator = ARSceneContainer.Coordinator(
            viewModel: viewModel,
            capabilityProvider: RecordingCoordinatorCapabilities(),
            sessionRuntime: firstRuntime
        )
        firstCoordinator.attachSession(runtime: firstRuntime)
        firstCoordinator.updateSessionState(
            for: firstRuntime,
            request: ARWorldTrackingConfigurationRequest(depthRequested: false, initialWorldMap: nil),
            isGenerating: false,
            shouldForwardCapturedImage: true,
            isSceneGenerated: false,
            isARSessionReady: false,
            isARSessionInterrupted: false,
            isARSessionRecovering: false,
            force: true
        )

        let pixelBuffer = try makePixelBuffer(width: 320, height: 240)
        controller.enqueueVideo(pixelBuffer, at: 1)
        try await controller.start(requestedFPS: 30, audioMode: .disabled)
        let activeToken = try XCTUnwrap(controller.recordingSourceToken)
        XCTAssertEqual(activeToken.source, .arWorkspace)

        firstCoordinator.updateSessionState(
            for: firstRuntime,
            request: ARWorldTrackingConfigurationRequest(depthRequested: false, initialWorldMap: nil),
            isGenerating: false,
            shouldForwardCapturedImage: true,
            isSceneGenerated: false,
            isARSessionReady: false,
            isARSessionInterrupted: false,
            isARSessionRecovering: false,
            force: true
        )
        firstCoordinator.testingForwardRecordingFrame(pixelBuffer, at: 2)
        firstCoordinator.testingForwardRecordingFrame(pixelBuffer, at: 3)
        XCTAssertEqual(box.recorder(at: 0)?.enqueuedTimestamps, [1, 2, 3])
        XCTAssertEqual(controller.recordingSourceToken, activeToken)

        let secondRuntime = RecordingCoordinatorRuntime()
        let secondCoordinator = ARSceneContainer.Coordinator(
            viewModel: viewModel,
            capabilityProvider: RecordingCoordinatorCapabilities(),
            sessionRuntime: secondRuntime
        )
        secondCoordinator.attachSession(runtime: secondRuntime)
        secondCoordinator.updateSessionState(
            for: secondRuntime,
            request: ARWorldTrackingConfigurationRequest(depthRequested: false, initialWorldMap: nil),
            isGenerating: false,
            shouldForwardCapturedImage: true,
            isSceneGenerated: false,
            isARSessionReady: false,
            isARSessionInterrupted: false,
            isARSessionRecovering: false,
            force: true
        )

        secondCoordinator.testingForwardRecordingFrame(pixelBuffer, at: 2)
        XCTAssertEqual(box.recorder(at: 0)?.enqueuedTimestamps, [1, 2, 3])
        XCTAssertEqual(controller.recordingSourceToken, activeToken)

        _ = await controller.stop(reason: .routeExit)
        _ = await controller.releaseAndWait()
    }

    func testCameraServiceStopPreservesReplacementClaimMadeDuringUnlockedCleanup() {
        let cameraService = CameraService.makeTestingInstance()
        let oldToken = RecordingOwnerToken(
            source: .cameraCoach,
            ownerID: UUID(),
            recordingID: RecordingID(rawValue: UUID()),
            generation: 1
        )
        let replacementToken = RecordingOwnerToken(
            source: .cameraCoach,
            ownerID: UUID(),
            recordingID: RecordingID(rawValue: UUID()),
            generation: 2
        )

        XCTAssertTrue(cameraService.claimRecordingSource(oldToken))
        cameraService.beforeIdleSourceClearForTesting = {
            XCTAssertTrue(cameraService.releaseRecordingSource(oldToken))
            XCTAssertTrue(cameraService.claimRecordingSource(replacementToken))
        }
        cameraService.stopRecording()
        cameraService.beforeIdleSourceClearForTesting = nil

        XCTAssertEqual(cameraService.recordingSourceToken, replacementToken)
        XCTAssertTrue(cameraService.releaseRecordingSource(replacementToken))
    }

    func testConcurrentStopsShareOneFinalizationResult() async throws {
        let stopGate = ControllerAsyncGate()
        let (controller, box, temporaryDirectory) = try makeController(stopGate: stopGate)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let pixelBuffer = try makePixelBuffer(width: 320, height: 240)
        controller.enqueueVideo(pixelBuffer, at: 1)
        try await controller.start(requestedFPS: 30, audioMode: .disabled)
        let recorder = try XCTUnwrap(box.recorder(at: 0))

        let firstStop = Task { await controller.stop(reason: .user) }
        await stopGate.started.wait()
        let secondStop = Task { await controller.stop(reason: .routeExit) }
        await Task.yield()

        XCTAssertEqual(recorder.stopCount, 1)
        stopGate.completion.open()

        let firstResult = await firstStop.value
        let secondResult = await secondStop.value
        XCTAssertEqual(firstResult, secondResult)
        XCTAssertEqual(recorder.stopCount, 1)
        _ = await controller.releaseAndWait()
    }

    func testInitialFramePrecedesPublicationWhileConcurrentStopAndReleaseWait() async throws {
        let startRace = ControllerStartRaceProbe()
        let (controller, box, temporaryDirectory) = try makeController(
            initialEnqueueObserver: { startRace.begin() }
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        startRace.attach(controller)

        let pixelBuffer = try makePixelBuffer(width: 640, height: 480)
        controller.enqueueVideo(pixelBuffer, at: 4)

        let startTask = Task {
            try await controller.start(
                requestedFPS: 30,
                audioMode: .disabled,
                timestamp: 4
            )
        }
        await startRace.requestsStarted.wait()

        let recorder = try XCTUnwrap(box.recorder(at: 0))
        XCTAssertNil(recorder.firstEnqueueFence)

        let raceTasks = try XCTUnwrap(startRace.tasks())
        _ = try await startTask.value
        let stopResult = await raceTasks.stop.value
        let releaseResult = await raceTasks.release.value

        XCTAssertEqual(recorder.enqueuedTimestamps, [4])
        XCTAssertEqual(recorder.stopCount, 1)
        XCTAssertEqual(releaseResult, stopResult)
        XCTAssertFalse(controller.isAcceptingFrames)
        XCTAssertNil(controller.recordingSourceToken)

        do {
            try await controller.start(
                firstPixelBuffer: pixelBuffer,
                requestedFPS: 30,
                audioMode: .disabled,
                timestamp: 5
            )
            XCTFail("A terminally released controller must reject a later take")
        } catch let failure as RecorderFailure {
            XCTAssertEqual(failure, .invalidTransition)
        } catch {
            XCTFail("Unexpected start failure: \(error)")
        }
    }

    func testMicrophoneDenialDoesNotCreateOrStartARecorder() async throws {
        let (controller, box, temporaryDirectory) = try makeController()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let viewModel = SceneGeneratorViewModel(
            permissionClient: DeniedMicrophonePermissionClient(),
            recordingController: controller
        )
        viewModel.plannedScene = PlannedScene(placedActors: [], placedObjects: [])
        viewModel.isARSessionReady = true
        viewModel.claimRecordingSource(ownerID: UUID(), fps: 30)

        viewModel.startRecording()
        for _ in 0..<20 {
            await Task.yield()
        }

        XCTAssertFalse(viewModel.isRecording)
        XCTAssertFalse(viewModel.isRecordingStarting)
        XCTAssertEqual(box.count, 0)
        XCTAssertEqual(viewModel.errorMessage, viewModel.localizedCopy(.generatorErrorMicrophoneDenied))
        XCTAssertEqual(viewModel.recordingPermissionRecovery, .openSettings)
        XCTAssertTrue(viewModel.recordingVideoOnlyRecoveryAvailable)

        viewModel.errorMessage = viewModel.localizedCopy(.generatorErrorNoScene)
        XCTAssertEqual(viewModel.errorMessage, viewModel.localizedCopy(.generatorErrorNoScene))
        XCTAssertNil(viewModel.recordingPermissionRecovery)
    }

    func testMicrophoneRecoveryClearsWhenPermissionBecomesUnavailable() async throws {
        let (controller, box, temporaryDirectory) = try makeController()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let permissionClient = ToggleMicrophonePermissionClient(authorization: .denied)
        let viewModel = SceneGeneratorViewModel(
            permissionClient: permissionClient,
            recordingController: controller,
            audioSessionCoordinator: makeTestAudioSessionCoordinator()
        )
        viewModel.plannedScene = PlannedScene(placedActors: [], placedObjects: [])
        viewModel.isARSessionReady = true
        viewModel.claimRecordingSource(ownerID: UUID(), fps: 30)

        viewModel.startRecording()
        for _ in 0..<20 {
            await Task.yield()
        }
        XCTAssertEqual(viewModel.recordingPermissionRecovery, .openSettings)

        await permissionClient.setSnapshot(
            authorization: .authorized,
            availability: .unavailable(.microphoneHardware)
        )
        viewModel.retryRecording()
        for _ in 0..<20 {
            await Task.yield()
        }

        XCTAssertFalse(viewModel.isRecording)
        XCTAssertEqual(box.count, 0)
        XCTAssertEqual(viewModel.errorMessage, viewModel.localizedCopy(.generatorErrorRecorder))
        XCTAssertNil(viewModel.recordingPermissionRecovery)
    }

    func testMicrophoneRestrictionOffersRecheckRecovery() async throws {
        let (controller, box, temporaryDirectory) = try makeController()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let viewModel = SceneGeneratorViewModel(
            permissionClient: RestrictedMicrophonePermissionClient(),
            recordingController: controller
        )
        viewModel.plannedScene = PlannedScene(placedActors: [], placedObjects: [])
        viewModel.isARSessionReady = true
        viewModel.claimRecordingSource(ownerID: UUID(), fps: 30)

        viewModel.startRecording()
        for _ in 0..<20 {
            await Task.yield()
        }

        XCTAssertFalse(viewModel.isRecording)
        XCTAssertFalse(viewModel.isRecordingStarting)
        XCTAssertEqual(box.count, 0)
        XCTAssertEqual(viewModel.errorMessage, viewModel.localizedCopy(.generatorErrorMicrophoneRestricted))
        XCTAssertEqual(viewModel.recordingPermissionRecovery, .recheck)
        XCTAssertTrue(viewModel.recordingVideoOnlyRecoveryAvailable)
    }

    func testMicrophoneUnavailableAndUnknownUseGenericRecorderErrorWithoutRecovery() async throws {
        for permissionClient in [
            AnyPermissionClient(UnavailableMicrophonePermissionClient()),
            AnyPermissionClient(UnknownMicrophonePermissionClient())
        ] {
            let (controller, box, temporaryDirectory) = try makeController()
            defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

            let viewModel = SceneGeneratorViewModel(
                permissionClient: permissionClient,
                recordingController: controller
            )
            viewModel.plannedScene = PlannedScene(placedActors: [], placedObjects: [])
            viewModel.isARSessionReady = true
            viewModel.claimRecordingSource(ownerID: UUID(), fps: 30)

            viewModel.startRecording()
            for _ in 0..<20 {
                await Task.yield()
            }

            XCTAssertFalse(viewModel.isRecording)
            XCTAssertFalse(viewModel.isRecordingStarting)
            XCTAssertEqual(box.count, 0)
            XCTAssertEqual(viewModel.errorMessage, viewModel.localizedCopy(.generatorErrorRecorder))
            XCTAssertNil(viewModel.recordingPermissionRecovery)
            XCTAssertTrue(viewModel.recordingVideoOnlyRecoveryAvailable)
        }
    }

    func testSoundOffSkipsMicrophoneAndAudioSessionAndUsesDisabledContract() async throws {
        let (controller, box, temporaryDirectory) = try makeController()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let permissionClient = CountingMicrophonePermissionClient(authorization: .denied)
        let platform = SceneRecordingTestAudioSessionPlatform()
        let viewModel = SceneGeneratorViewModel(
            permissionClient: permissionClient,
            recordingController: controller,
            audioSessionCoordinator: AudioSessionCoordinator(platform: platform)
        )
        viewModel.plannedScene = PlannedScene(placedActors: [], placedObjects: [])
        viewModel.isARSessionReady = true
        viewModel.claimRecordingSource(ownerID: UUID(), fps: 30)
        controller.enqueueVideo(try makePixelBuffer(width: 640, height: 480), at: 1)

        viewModel.setRecordingSoundEnabled(false)
        viewModel.startRecording()
        for _ in 0..<200 where !viewModel.isRecording {
            await Task.yield()
        }

        let recorder = try XCTUnwrap(box.recorder(at: 0))
        XCTAssertTrue(viewModel.isRecording)
        XCTAssertEqual(recorder.configuration?.audioMode, .disabled)
        let soundOffSnapshotCount = await permissionClient.snapshotCount
        let soundOffRequestCount = await permissionClient.requestCount
        XCTAssertEqual(soundOffSnapshotCount, 0)
        XCTAssertEqual(soundOffRequestCount, 0)
        XCTAssertEqual(platform.callCount, 0)

        viewModel.stopRecording()
        for _ in 0..<50 where viewModel.isRecordingFinalizing {
            await Task.yield()
        }
        _ = await controller.releaseAndWait()
    }

    func testDeniedMicrophoneOffersExplicitSilentRetryWithoutPermissionRequest() async throws {
        let (controller, box, temporaryDirectory) = try makeController()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let permissionClient = CountingMicrophonePermissionClient(authorization: .denied)
        let viewModel = SceneGeneratorViewModel(
            permissionClient: permissionClient,
            recordingController: controller,
            audioSessionCoordinator: AudioSessionCoordinator(
                platform: SceneRecordingTestAudioSessionPlatform()
            )
        )
        viewModel.plannedScene = PlannedScene(placedActors: [], placedObjects: [])
        viewModel.isARSessionReady = true
        viewModel.claimRecordingSource(ownerID: UUID(), fps: 30)
        controller.enqueueVideo(try makePixelBuffer(width: 640, height: 480), at: 1)

        viewModel.startRecording()
        for _ in 0..<50 where viewModel.isRecordingStarting {
            await Task.yield()
        }

        XCTAssertFalse(viewModel.isRecording)
        XCTAssertEqual(viewModel.recordingPermissionRecovery, .openSettings)
        XCTAssertTrue(viewModel.recordingVideoOnlyRecoveryAvailable)
        let initialSnapshotCount = await permissionClient.snapshotCount
        let initialRequestCount = await permissionClient.requestCount
        XCTAssertEqual(initialSnapshotCount, 1)
        XCTAssertEqual(initialRequestCount, 0)

        viewModel.startRecordingWithoutSound()
        for _ in 0..<200 where !viewModel.isRecording {
            await Task.yield()
        }

        let recorder = try XCTUnwrap(box.recorder(at: 0))
        XCTAssertTrue(viewModel.isRecording)
        XCTAssertEqual(recorder.configuration?.audioMode, .disabled)
        let silentSnapshotCount = await permissionClient.snapshotCount
        let silentRequestCount = await permissionClient.requestCount
        XCTAssertEqual(silentSnapshotCount, 1)
        XCTAssertEqual(silentRequestCount, 0)

        viewModel.stopRecording()
        for _ in 0..<50 where viewModel.isRecordingFinalizing {
            await Task.yield()
        }
        _ = await controller.releaseAndWait()
    }

    func testAuthorizedRetryClearsMicrophoneRecoveryAndStartsRecording() async throws {
        let (controller, box, temporaryDirectory) = try makeController()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let permissionClient = ToggleMicrophonePermissionClient(authorization: .denied)
        let viewModel = SceneGeneratorViewModel(
            permissionClient: permissionClient,
            recordingController: controller,
            audioSessionCoordinator: makeTestAudioSessionCoordinator()
        )
        viewModel.plannedScene = PlannedScene(placedActors: [], placedObjects: [])
        viewModel.isARSessionReady = true
        viewModel.claimRecordingSource(ownerID: UUID(), fps: 30)
        controller.enqueueVideo(try makePixelBuffer(width: 640, height: 480), at: 1)

        viewModel.startRecording()
        for _ in 0..<20 {
            await Task.yield()
        }
        XCTAssertEqual(viewModel.recordingPermissionRecovery, .openSettings)

        await permissionClient.setAuthorization(.authorized)
        viewModel.retryRecording()
        for _ in 0..<200 where !viewModel.isRecording {
            await Task.yield()
        }

        XCTAssertTrue(viewModel.isRecording)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.recordingPermissionRecovery)
        XCTAssertEqual(box.count, 1)

        viewModel.stopRecording()
        for _ in 0..<20 {
            await Task.yield()
        }
        _ = await controller.releaseAndWait()
    }

    func testPublishedRecordingSourceFPSIsExactAndUnavailableBlocksRecording() async throws {
        let (controller, box, temporaryDirectory) = try makeController()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let pixelBuffer = try makePixelBuffer(width: 640, height: 480)
        controller.enqueueVideo(pixelBuffer, at: 1)
        let viewModel = SceneGeneratorViewModel(
            permissionClient: AuthorizedMicrophonePermissionClient(),
            recordingController: controller,
            audioSessionCoordinator: makeTestAudioSessionCoordinator()
        )
        viewModel.plannedScene = PlannedScene(placedActors: [], placedObjects: [])
        viewModel.isARSessionReady = true

        XCTAssertNil(viewModel.recordingSourceFPS)
        XCTAssertFalse(viewModel.canStartRecording)
        viewModel.startRecording()
        for _ in 0..<20 {
            await Task.yield()
        }
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertEqual(box.count, 0)

        viewModel.claimRecordingSource(ownerID: UUID(), fps: 60)
        XCTAssertEqual(viewModel.recordingSourceFPS, 60)
        XCTAssertTrue(viewModel.canStartRecording)
        viewModel.startRecording()
        for _ in 0..<50 {
            await Task.yield()
        }

        let recorder = try XCTUnwrap(box.recorder(at: 0))
        XCTAssertEqual(recorder.configuration?.fps, 60)

        viewModel.stopRecording()
        for _ in 0..<20 {
            await Task.yield()
        }
        _ = await controller.releaseAndWait()
    }

    func testRecordingSourceOwnershipRejectsStaleCoordinatorUpdatesAndRelease() {
        let viewModel = SceneGeneratorViewModel()
        let oldOwnerID = UUID()
        let newOwnerID = UUID()

        XCTAssertTrue(viewModel.claimRecordingSource(ownerID: oldOwnerID, fps: 60))
        XCTAssertEqual(viewModel.recordingSourceFPS, 60)

        XCTAssertTrue(viewModel.claimRecordingSource(ownerID: newOwnerID, fps: 30))
        viewModel.updateRecordingSourceFPS(120, ownerID: oldOwnerID)
        viewModel.releaseRecordingSource(ownerID: oldOwnerID)
        XCTAssertEqual(viewModel.recordingSourceFPS, 30)

        viewModel.updateRecordingSourceFPS(24, ownerID: newOwnerID)
        XCTAssertEqual(viewModel.recordingSourceFPS, 24)
        viewModel.releaseRecordingSource(ownerID: newOwnerID)
        XCTAssertNil(viewModel.recordingSourceFPS)
    }

    func testTeardownInFlightBlocksRecordingUntilPersistenceGateOpens() async throws {
        let (controller, box, temporaryDirectory) = try makeController()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let viewModel = SceneGeneratorViewModel(
            permissionClient: AuthorizedMicrophonePermissionClient(),
            recordingController: controller
        )
        viewModel.plannedScene = PlannedScene(placedActors: [], placedObjects: [])
        viewModel.isARSessionReady = true
        viewModel.claimRecordingSource(ownerID: UUID(), fps: 30)

        let captureStarted = ControllerGate()
        let captureCompleted = ControllerGate()
        viewModel.testingWorldMapCaptureOverride = {
            captureStarted.open()
            await captureCompleted.wait()
            return .success(nil)
        }

        let teardown = Task { @MainActor in
            await viewModel.teardownAndWait()
        }
        await captureStarted.wait()

        XCTAssertFalse(viewModel.isWorkspaceReleased)
        XCTAssertFalse(viewModel.canStartRecording)
        viewModel.startRecording()
        XCTAssertFalse(viewModel.isRecordingStarting)
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertEqual(box.count, 0)

        captureCompleted.open()
        let teardownResult = await teardown.value
        XCTAssertEqual(teardownResult, .released)
        XCTAssertTrue(viewModel.isWorkspaceReleased)
    }

    func testFinalizedArtifactPromotionIsIdempotentAndResolvesProjectFile() throws {
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scene-recording-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupportURL) }
        let store = try RecordingArtifactStore(
            applicationSupportDirectoryURL: applicationSupportURL
        )
        let sourceURL = try store.makePendingURL()
        let recordingID = UUID()
        let projectID = UUID()
        XCTAssertTrue(FileManager.default.createFile(atPath: sourceURL.path, contents: Data("first".utf8)))
        let artifact = RecordingArtifact(
            id: RecordingID(rawValue: recordingID),
            localURL: sourceURL,
            duration: 2.5,
            hasAudio: true
        )

        let reference = try store.promoteFinalizedArtifact(artifact, projectID: projectID)
        XCTAssertEqual(reference.recordingID, recordingID)
        XCTAssertFalse(reference.relativePath.hasPrefix("/"))
        XCTAssertEqual(
            reference.relativePath,
            "Recordings/Projects/\(projectID.uuidString)/\(recordingID.uuidString).mov"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        let resolved = try XCTUnwrap(store.resolve(reference))
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved.path))
        XCTAssertEqual(try Data(contentsOf: resolved), Data("first".utf8))
        XCTAssertEqual(store.resolveArtifact(reference)?.hasAudio, true)

        let repeatedReference = try store.promoteFinalizedArtifact(artifact, projectID: projectID)
        XCTAssertEqual(repeatedReference, reference)
        XCTAssertEqual(try Data(contentsOf: resolved), Data("first".utf8))
    }

    func testRecordingArtifactStoreRejectsOutsideAndSymlinkPaths() throws {
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scene-recording-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupportURL) }
        let store = try RecordingArtifactStore(
            applicationSupportDirectoryURL: applicationSupportURL
        )
        let outsideURL = applicationSupportURL
            .deletingLastPathComponent()
            .appendingPathComponent("outside-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: outsideURL) }
        XCTAssertTrue(FileManager.default.createFile(atPath: outsideURL.path, contents: Data()))
        let artifact = RecordingArtifact(
            id: RecordingID(rawValue: UUID()),
            localURL: outsideURL,
            duration: nil,
            hasAudio: false
        )
        XCTAssertThrowsError(try store.promoteFinalizedArtifact(artifact, projectID: UUID())) { error in
            XCTAssertEqual(error as? RecordingArtifactStoreError, .pendingSourceOutsideRoot)
        }

        let targetURL = applicationSupportURL
            .deletingLastPathComponent()
            .appendingPathComponent("symlink-target-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: targetURL) }
        XCTAssertTrue(FileManager.default.createFile(atPath: targetURL.path, contents: Data()))
        let symlinkURL = try store.makePendingURL()
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: targetURL)
        let symlinkArtifact = RecordingArtifact(
            id: RecordingID(rawValue: UUID()),
            localURL: symlinkURL,
            duration: nil,
            hasAudio: false
        )
        XCTAssertThrowsError(try store.promoteFinalizedArtifact(symlinkArtifact, projectID: UUID())) { error in
            XCTAssertEqual(error as? RecordingArtifactStoreError, .pendingSourceSymlink)
        }

        let traversal = SceneRecordingReference(
            recordingID: UUID(),
            relativePath: "Recordings/../outside.mov"
        )
        XCTAssertNil(store.resolve(traversal))
    }

    func testRecordingArtifactStoreRemovesOnlyChosenProjectAndIsIdempotent() throws {
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scene-recording-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupportURL) }
        let store = try RecordingArtifactStore(
            applicationSupportDirectoryURL: applicationSupportURL
        )
        let fileManager = FileManager.default
        let projectID = UUID()
        let siblingID = UUID()
        let projectURL = store.projectsDirectoryURL
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
        let siblingURL = store.projectsDirectoryURL
            .appendingPathComponent(siblingID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: siblingURL, withIntermediateDirectories: true)
        let projectArtifact = projectURL.appendingPathComponent("\(UUID().uuidString).mov")
        let siblingArtifact = siblingURL.appendingPathComponent("\(UUID().uuidString).mov")
        XCTAssertTrue(fileManager.createFile(atPath: projectArtifact.path, contents: Data("project".utf8)))
        XCTAssertTrue(fileManager.createFile(atPath: siblingArtifact.path, contents: Data("sibling".utf8)))

        try store.removeProjectArtifacts(projectID: projectID)

        XCTAssertFalse(fileManager.fileExists(atPath: projectURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: siblingArtifact.path))
        XCTAssertNoThrow(try store.removeProjectArtifacts(projectID: projectID))
    }

    func testStagedArtifactCommitRollsBackAfterInjectedPartialUnlink() throws {
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scene-recording-store-rollback-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupportURL) }
        let store = try RecordingArtifactStore(
            applicationSupportDirectoryURL: applicationSupportURL
        )
        let projectID = UUID()
        let projectURL = store.projectsDirectoryURL
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let firstURL = projectURL.appendingPathComponent("\(UUID().uuidString).mov")
        let secondURL = projectURL.appendingPathComponent("\(UUID().uuidString).mov")
        let firstData = Data("first artifact".utf8)
        let secondData = Data("second artifact".utf8)
        XCTAssertTrue(FileManager.default.createFile(atPath: firstURL.path, contents: firstData))
        XCTAssertTrue(FileManager.default.createFile(atPath: secondURL.path, contents: secondData))

        let staged = try store.stageProjectArtifacts(projectID: projectID)
        store.testArtifactCommitFailureAfterUnlinks = 1

        XCTAssertThrowsError(try staged.commit()) { error in
            XCTAssertEqual(error as? RecordingArtifactStoreError, .fileSystemFailure)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectURL.path))
        XCTAssertEqual(try Data(contentsOf: firstURL), firstData)
        XCTAssertEqual(try Data(contentsOf: secondURL), secondData)
    }

    func testRecordingArtifactStoreFailsClosedForUnexpectedEntryWithoutTouchingExternalTarget() throws {
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scene-recording-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupportURL) }
        let store = try RecordingArtifactStore(
            applicationSupportDirectoryURL: applicationSupportURL
        )
        let fileManager = FileManager.default
        let projectID = UUID()
        let projectURL = store.projectsDirectoryURL
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let validArtifact = projectURL.appendingPathComponent("\(UUID().uuidString).mov")
        let externalTarget = applicationSupportURL
            .deletingLastPathComponent()
            .appendingPathComponent("recording-external-\(UUID().uuidString).mov")
        let symlink = projectURL.appendingPathComponent("\(UUID().uuidString).mov")
        defer { try? fileManager.removeItem(at: externalTarget) }
        XCTAssertTrue(fileManager.createFile(atPath: validArtifact.path, contents: Data()))
        XCTAssertTrue(fileManager.createFile(atPath: externalTarget.path, contents: Data("external".utf8)))
        try fileManager.createSymbolicLink(at: symlink, withDestinationURL: externalTarget)

        XCTAssertThrowsError(try store.removeProjectArtifacts(projectID: projectID))
        XCTAssertTrue(fileManager.fileExists(atPath: validArtifact.path))
        XCTAssertTrue(fileManager.fileExists(atPath: symlink.path))
        XCTAssertEqual(try Data(contentsOf: externalTarget), Data("external".utf8))
    }

    func testRecordingArtifactStoreRejectsSymlinkedRootAndProjectDirectory() throws {
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scene-recording-store-\(UUID().uuidString)", isDirectory: true)
        let externalRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scene-recording-external-\(UUID().uuidString)", isDirectory: true)
        let fileManager = FileManager.default
        defer {
            try? fileManager.removeItem(at: applicationSupportURL)
            try? fileManager.removeItem(at: externalRootURL)
        }
        let store = try RecordingArtifactStore(
            applicationSupportDirectoryURL: applicationSupportURL
        )
        let projectID = UUID()
        let recordingID = UUID()
        let externalProjectURL = externalRootURL
            .appendingPathComponent("Recordings/Projects/\(projectID.uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: externalProjectURL, withIntermediateDirectories: true)
        let externalArtifactURL = externalProjectURL.appendingPathComponent("\(recordingID.uuidString).mov")
        XCTAssertTrue(fileManager.createFile(atPath: externalArtifactURL.path, contents: Data("external".utf8)))

        try fileManager.removeItem(at: applicationSupportURL)
        try fileManager.createSymbolicLink(at: applicationSupportURL, withDestinationURL: externalRootURL)
        XCTAssertThrowsError(try store.removeProjectArtifacts(projectID: projectID))
        XCTAssertEqual(try Data(contentsOf: externalArtifactURL), Data("external".utf8))

        try fileManager.removeItem(at: applicationSupportURL)
        try fileManager.createDirectory(at: store.projectsDirectoryURL, withIntermediateDirectories: true)
        let projectSymlinkURL = store.projectsDirectoryURL
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
        try fileManager.createSymbolicLink(at: projectSymlinkURL, withDestinationURL: externalProjectURL)

        XCTAssertThrowsError(try store.removeProjectArtifacts(projectID: projectID))
        XCTAssertTrue(fileManager.fileExists(atPath: projectSymlinkURL.path))
        XCTAssertEqual(try Data(contentsOf: externalArtifactURL), Data("external".utf8))
    }

    private func makeController(
        stopGate: ControllerAsyncGate? = nil,
        initialEnqueueObserver: (@Sendable () -> Void)? = nil
    ) throws -> (SceneRecordingController, ControllerRecorderBox, URL) {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("scene-recording-controller-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        let artifactStore = try RecordingArtifactStore(
            applicationSupportDirectoryURL: temporaryDirectory
        )
        let box = ControllerRecorderBox()
        let controller = SceneRecordingController(artifactStore: artifactStore) { configuration in
            let recorder = ControllerTestRecorder(
                stopGate: stopGate,
                fenceProvider: { box.currentFence() },
                initialEnqueueObserver: initialEnqueueObserver
            )
            box.append(recorder)
            return recorder
        }
        box.attach(controller)
        return (controller, box, temporaryDirectory)
    }

    private func makeTestAudioSessionCoordinator() -> AudioSessionCoordinator {
        AudioSessionCoordinator(platform: SceneRecordingTestAudioSessionPlatform())
    }

    private func makePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw NSError(domain: "SceneRecordingControllerTests", code: Int(status))
        }
        return pixelBuffer
    }
}

private final class RecordingCoordinatorRuntime: ARSessionRuntime {
    private let identity = NSObject()
    var sessionIdentifier: ObjectIdentifier { ObjectIdentifier(identity) }
    var videoFormatFramesPerSecond: Int? { 60 }
    weak var delegate: ARSessionDelegate?

    func run(_ configuration: ARConfiguration, options: ARSession.RunOptions) {}

    func pause() {}
}

private struct RecordingCoordinatorCapabilities: ARWorldTrackingCapabilityProviding {
    let evidence = ARWorldTrackingCapabilityEvidence(
        supportsWorldTracking: true,
        supportsHorizontalPlaneDetection: true,
        supportsGravityAlignment: true,
        supportsSmoothedSceneDepth: false,
        supportsSceneDepth: false
    )
}

private final class SceneRecordingTestAudioSessionPlatform: AudioSessionPlatform, @unchecked Sendable {
    private let lock = NSLock()
    private var callsStorage = 0

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return callsStorage
    }

    func setCategory(
        _ category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    ) throws {
        lock.lock()
        callsStorage += 1
        lock.unlock()
    }

    func setActive(
        _ active: Bool,
        options: AVAudioSession.SetActiveOptions
    ) throws {
        lock.lock()
        callsStorage += 1
        lock.unlock()
    }
}

private actor CountingMicrophonePermissionClient: PermissionClient {
    private let authorization: PermissionAuthorization
    private var snapshots = 0
    private var requests = 0

    init(authorization: PermissionAuthorization) {
        self.authorization = authorization
    }

    var snapshotCount: Int { snapshots }
    var requestCount: Int { requests }

    func snapshot(for permission: AppPermission) async -> PermissionSnapshot {
        snapshots += 1
        return PermissionSnapshot(
            permission: permission,
            authorization: authorization,
            availability: .available
        )
    }

    func request(_ permission: AppPermission) async -> PermissionSnapshot {
        requests += 1
        return PermissionSnapshot(
            permission: permission,
            authorization: authorization,
            availability: .available
        )
    }
}

private final class ControllerRecorderBox: @unchecked Sendable {
    private let lock = NSLock()
    private var recorders: [ControllerTestRecorder] = []
    private weak var controller: SceneRecordingController?

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func append(_ recorder: ControllerTestRecorder) {
        withLock {
            recorders.append(recorder)
        }
    }

    func attach(_ controller: SceneRecordingController) {
        withLock {
            self.controller = controller
        }
    }

    func currentFence() -> RecordingFrameFence? {
        withLock {
            controller?.frameFence
        }
    }

    func recorder(at index: Int) -> ControllerTestRecorder? {
        withLock {
            guard recorders.indices.contains(index) else { return nil }
            return recorders[index]
        }
    }

    var count: Int {
        withLock { recorders.count }
    }
}

private final class ControllerTestRecorder: MediaRecording, @unchecked Sendable {
    private let lock = NSLock()
    private let stopGate: ControllerAsyncGate?
    private let fenceProvider: @Sendable () -> RecordingFrameFence?
    private let initialEnqueueObserver: (@Sendable () -> Void)?
    private var stateStorage: RecorderState = .idle
    private var generationStorage: UInt64 = 0
    private var ownerTokenStorage: RecordingOwnerToken?
    private var latestSourceGenerationStorage: UInt64 = 0
    private var configurationStorage: RecordingConfiguration?
    private var timestampsStorage: [TimeInterval] = []
    private var stopCountStorage = 0
    private var resultStorage: RecordingStopResult?
    private var hasEnqueuedFrameStorage = false
    private var firstEnqueueFenceStorage: RecordingFrameFence?

    init(
        stopGate: ControllerAsyncGate?,
        fenceProvider: @escaping @Sendable () -> RecordingFrameFence?,
        initialEnqueueObserver: (@Sendable () -> Void)?
    ) {
        self.stopGate = stopGate
        self.fenceProvider = fenceProvider
        self.initialEnqueueObserver = initialEnqueueObserver
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var state: RecorderState {
        get async {
            withLock { stateStorage }
        }
    }

    var configuration: RecordingConfiguration? {
        withLock { configurationStorage }
    }

    var enqueuedTimestamps: [TimeInterval] {
        withLock { timestampsStorage }
    }

    var stopCount: Int {
        withLock { stopCountStorage }
    }

    var firstEnqueueFence: RecordingFrameFence? {
        withLock { firstEnqueueFenceStorage }
    }

    func stateSnapshot() async -> RecorderStateSnapshot {
        withLock {
            RecorderStateSnapshot(
                state: stateStorage,
                recordingID: configurationStorage?.id,
                generation: generationStorage,
                ownerToken: ownerTokenStorage
            )
        }
    }

    func claimRecordingSource(_ ownerToken: RecordingOwnerToken) async -> Bool {
        withLock {
            guard ownerToken.isValid,
                  ownerToken.source == .arWorkspace else { return false }
            if ownerTokenStorage == ownerToken { return true }
            guard ownerTokenStorage == nil,
                  stateStorage == .idle || stateStorage == .prepared,
                  ownerToken.generation > latestSourceGenerationStorage else {
                return false
            }
            if let configurationStorage {
                guard stateStorage == .prepared,
                      configurationStorage.id == ownerToken.recordingID else {
                    return false
                }
                generationStorage = ownerToken.generation
            }
            ownerTokenStorage = ownerToken
            latestSourceGenerationStorage = ownerToken.generation
            return true
        }
    }

    func releaseRecordingSource(_ ownerToken: RecordingOwnerToken) async -> Bool {
        withLock {
            guard ownerTokenStorage == ownerToken,
                  stateStorage == .idle
                    || stateStorage == .finished
                    || stateStorage == .failed
                    || stateStorage == .released else {
                return false
            }
            ownerTokenStorage = nil
            return true
        }
    }

    func prepare(_ configuration: RecordingConfiguration) async throws {
        withLock {
            configurationStorage = configuration
            if let ownerTokenStorage {
                generationStorage = ownerTokenStorage.generation
            }
            stateStorage = .prepared
        }
    }

    func start() async throws {
        withLock {
            if ownerTokenStorage == nil {
                generationStorage += 1
            }
            stateStorage = .recording
        }
    }

    func stop(reason: RecordingStopReason) async -> RecordingStopResult {
        let result: RecordingStopResult = withLock {
            stopCountStorage += 1
            stateStorage = .finished
            if let resultStorage {
                return resultStorage
            }

            let configuration = configurationStorage!
            let artifact = RecordingArtifact(
                id: configuration.id,
                localURL: configuration.outputURL,
                duration: nil,
                hasAudio: false
            )
            let result: RecordingStopResult = .finalized(artifact)
            resultStorage = result
            return result
        }

        if let stopGate {
            stopGate.started.open()
            await stopGate.completion.wait()
        }
        return result
    }

    func releaseAndWait() async -> RecordingStopResult? {
        withLock {
            stateStorage = .released
            return resultStorage
        }
    }

    func enqueueVideo(_ frame: RecordingVideoFrame) {
        let isFirstFrame = withLock {
            guard frame.ownerToken == ownerTokenStorage else { return false }
            guard !hasEnqueuedFrameStorage else { return false }
            hasEnqueuedFrameStorage = true
            firstEnqueueFenceStorage = fenceProvider()
            return true
        }
        if isFirstFrame {
            initialEnqueueObserver?()
        }
        withLock {
            timestampsStorage.append(frame.timestamp)
        }
    }

    func enqueueAudio(_ frame: RecordingAudioFrame) {}
}

private final class ControllerAsyncGate: @unchecked Sendable {
    let started = ControllerGate()
    let completion = ControllerGate()
}

private final class ControllerStartRaceProbe: @unchecked Sendable {
    typealias RaceTasks = (
        stop: Task<RecordingStopResult?, Never>,
        release: Task<RecordingStopResult?, Never>
    )

    private let lock = NSLock()
    private weak var controller: SceneRecordingController?
    private var hasStartedStorage = false
    private var tasksStorage: RaceTasks?
    let requestsStarted = ControllerGate()

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func attach(_ controller: SceneRecordingController) {
        withLock {
            self.controller = controller
        }
    }

    func begin() {
        let attachedController: SceneRecordingController? = withLock {
            guard !hasStartedStorage, let attachedController = controller else { return nil }
            hasStartedStorage = true
            return attachedController
        }
        guard let controller = attachedController else { return }

        let stop = Task { await controller.stop(reason: .routeExit) }
        let release = Task { await controller.releaseAndWait() }
        withLock {
            tasksStorage = (stop: stop, release: release)
        }
        requestsStarted.open()
    }

    func tasks() -> RaceTasks? {
        withLock { tasksStorage }
    }
}

private final class ControllerGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let shouldResumeImmediately = withLock {
                guard !isOpen else {
                    return true
                }
                waiters.append(continuation)
                return false
            }
            if shouldResumeImmediately {
                continuation.resume()
            }
        }
    }

    func open() {
        let pending: [CheckedContinuation<Void, Never>] = withLock {
            guard !isOpen else {
                return []
            }
            isOpen = true
            let pending = waiters
            waiters.removeAll()
            return pending
        }
        pending.forEach { $0.resume() }
    }
}

private actor DeniedMicrophonePermissionClient: PermissionClient {
    func snapshot(for permission: AppPermission) async -> PermissionSnapshot {
        PermissionSnapshot(
            permission: permission,
            authorization: .denied,
            availability: .available
        )
    }

    func request(_ permission: AppPermission) async -> PermissionSnapshot {
        await snapshot(for: permission)
    }
}

private actor RestrictedMicrophonePermissionClient: PermissionClient {
    func snapshot(for permission: AppPermission) async -> PermissionSnapshot {
        PermissionSnapshot(
            permission: permission,
            authorization: .restricted,
            availability: .available
        )
    }

    func request(_ permission: AppPermission) async -> PermissionSnapshot {
        await snapshot(for: permission)
    }
}

private actor UnavailableMicrophonePermissionClient: PermissionClient {
    func snapshot(for permission: AppPermission) async -> PermissionSnapshot {
        PermissionSnapshot(
            permission: permission,
            authorization: .authorized,
            availability: .unavailable(.microphoneHardware)
        )
    }

    func request(_ permission: AppPermission) async -> PermissionSnapshot {
        await snapshot(for: permission)
    }
}

private actor UnknownMicrophonePermissionClient: PermissionClient {
    func snapshot(for permission: AppPermission) async -> PermissionSnapshot {
        PermissionSnapshot(
            permission: permission,
            authorization: .unknown,
            availability: .available
        )
    }

    func request(_ permission: AppPermission) async -> PermissionSnapshot {
        await snapshot(for: permission)
    }
}

private actor ToggleMicrophonePermissionClient: PermissionClient {
    private var authorization: PermissionAuthorization
    private var availability: PermissionAvailability = .available

    init(authorization: PermissionAuthorization) {
        self.authorization = authorization
    }

    func setAuthorization(_ authorization: PermissionAuthorization) {
        self.authorization = authorization
    }

    func setSnapshot(
        authorization: PermissionAuthorization,
        availability: PermissionAvailability
    ) {
        self.authorization = authorization
        self.availability = availability
    }

    func snapshot(for permission: AppPermission) async -> PermissionSnapshot {
        PermissionSnapshot(
            permission: permission,
            authorization: authorization,
            availability: availability
        )
    }

    func request(_ permission: AppPermission) async -> PermissionSnapshot {
        await snapshot(for: permission)
    }
}

private struct AnyPermissionClient: PermissionClient {
    private let snapshotHandler: @Sendable (AppPermission) async -> PermissionSnapshot
    private let requestHandler: @Sendable (AppPermission) async -> PermissionSnapshot

    init(_ client: any PermissionClient) {
        snapshotHandler = { permission in await client.snapshot(for: permission) }
        requestHandler = { permission in await client.request(permission) }
    }

    func snapshot(for permission: AppPermission) async -> PermissionSnapshot {
        await snapshotHandler(permission)
    }

    func request(_ permission: AppPermission) async -> PermissionSnapshot {
        await requestHandler(permission)
    }
}

private actor AuthorizedMicrophonePermissionClient: PermissionClient {
    func snapshot(for permission: AppPermission) async -> PermissionSnapshot {
        PermissionSnapshot(
            permission: permission,
            authorization: .authorized,
            availability: .available
        )
    }

    func request(_ permission: AppPermission) async -> PermissionSnapshot {
        await snapshot(for: permission)
    }
}
