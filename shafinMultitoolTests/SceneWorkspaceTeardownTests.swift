import SwiftUI
import UIKit
import ARKit
import XCTest
@testable import shafinMultitool

@MainActor
final class SceneWorkspaceTeardownTests: XCTestCase {

    func testTeardownPersistsThenPausesWhenWorkspaceIsIdle() async {
        let recorder = EventRecorder()
        let workspace = TestSceneWorkspace(
            isRecording: false,
            isPlaying: false,
            recorder: recorder
        )

        let result = await workspace.teardownAndWait()

        XCTAssertEqual(result, .released)
        XCTAssertEqual(
            recorder.events,
            ["persist", "release-recording", "pause-and-detach"]
        )
    }

    func testTeardownStopsRecordingAndPlaybackBeforePersistence() async {
        let recorder = EventRecorder()
        let workspace = TestSceneWorkspace(
            isRecording: true,
            isPlaying: true,
            recorder: recorder
        )

        let result = await workspace.teardownAndWait()

        XCTAssertEqual(result, .released)
        XCTAssertEqual(
            recorder.events,
            [
                "stop-recording",
                "stop-playback",
                "persist",
                "release-recording",
                "pause-and-detach"
            ]
        )
    }

    func testTeardownAwaitsRecordingFinalizationBeforePlaybackAndPersistence() async {
        let recordingStopStarted = AsyncGate()
        let recordingStopCompleted = AsyncGate()
        let recorder = EventRecorder()
        let workspace = TestSceneWorkspace(
            isRecording: true,
            isPlaying: true,
            recorder: recorder,
            stopRecording: {
                recordingStopStarted.open()
                await recordingStopCompleted.wait()
            }
        )

        let teardown = Task { @MainActor in
            await workspace.teardownAndWait()
        }
        await recordingStopStarted.wait()

        XCTAssertEqual(recorder.events, ["stop-recording"])
        recordingStopCompleted.open()

        let result = await teardown.value
        XCTAssertEqual(result, .released)
        XCTAssertEqual(
            recorder.events,
            [
                "stop-recording",
                "stop-playback",
                "persist",
                "release-recording",
                "pause-and-detach"
            ]
        )
    }

    func testTeardownAwaitsPersistenceBeforeTerminalRecordingReleaseAndDetach() async {
        let persistenceStarted = AsyncGate()
        let persistenceCompleted = AsyncGate()
        let releaseStarted = AsyncGate()
        let releaseCompleted = AsyncGate()
        let recorder = EventRecorder()
        let workspace = TestSceneWorkspace(
            isRecording: true,
            isPlaying: true,
            recorder: recorder,
            releaseRecording: {
                releaseStarted.open()
                await releaseCompleted.wait()
            },
            persist: {
                persistenceStarted.open()
                await persistenceCompleted.wait()
            },
        )

        let teardown = Task { @MainActor in
            await workspace.teardownAndWait()
        }
        await persistenceStarted.wait()

        XCTAssertEqual(recorder.events, ["stop-recording", "stop-playback", "persist"])

        persistenceCompleted.open()
        await releaseStarted.wait()
        XCTAssertEqual(
            recorder.events,
            ["stop-recording", "stop-playback", "persist", "release-recording"]
        )

        releaseCompleted.open()
        let result = await teardown.value
        XCTAssertEqual(result, .released)
        XCTAssertEqual(
            recorder.events,
            [
                "stop-recording",
                "stop-playback",
                "persist",
                "release-recording",
                "pause-and-detach"
            ]
        )
    }

    func testConcurrentTeardownCallersShareOneOperation() async {
        let persistenceStarted = AsyncGate()
        let persistenceCompletion = AsyncGate()
        let recorder = EventRecorder()
        let workspace = TestSceneWorkspace(
            isRecording: true,
            isPlaying: true,
            recorder: recorder,
            persist: {
                persistenceStarted.open()
                await persistenceCompletion.wait()
            }
        )

        let first = Task { @MainActor in
            await workspace.teardownAndWait()
        }
        await persistenceStarted.wait()

        let second = Task { @MainActor in
            await workspace.teardownAndWait()
        }
        for _ in 0..<10 {
            await Task.yield()
        }

        XCTAssertEqual(
            recorder.events,
            ["stop-recording", "stop-playback", "persist"]
        )

        persistenceCompletion.open()
        let firstResult = await first.value
        let secondResult = await second.value
        let repeatedResult = await workspace.teardownAndWait()
        XCTAssertEqual(firstResult, .released)
        XCTAssertEqual(secondResult, .released)
        XCTAssertEqual(repeatedResult, .released)
        XCTAssertEqual(
            recorder.events,
            [
                "stop-recording",
                "stop-playback",
                "persist",
                "release-recording",
                "pause-and-detach"
            ]
        )
    }

    func testWorldMapCaptureTimeoutResumesExactlyOnceAndIgnoresLateCallback() async {
        var lateCompletion: SETWorldMapCaptureResolver<Int>.Completion?

        let result = await SETWorldMapCaptureResolver<Int>.resolve(
            timeoutNanoseconds: 1,
            request: { completion in
                lateCompletion = completion
            },
            sleep: { _ in }
        )

        XCTAssertEqual(result, .failure(.worldMapSnapshotFailed))
        lateCompletion?(.success(42))
    }

    func testWorldMapCaptureCancellationResumesExactlyOnceAndIgnoresLateCallback() async {
        let timeoutGate = AsyncGate()
        var lateCompletion: SETWorldMapCaptureResolver<Int>.Completion?
        let capture = Task { @MainActor in
            await SETWorldMapCaptureResolver<Int>.resolve(
                timeoutNanoseconds: 1_000_000,
                request: { completion in
                    lateCompletion = completion
                },
                sleep: { _ in await timeoutGate.wait() }
            )
        }

        for _ in 0..<20 where lateCompletion == nil {
            await Task.yield()
        }
        XCTAssertNotNil(lateCompletion)

        capture.cancel()
        let result = await capture.value
        XCTAssertEqual(result, .failure(.worldMapSnapshotFailed))

        lateCompletion?(.success(42))
        timeoutGate.open()
    }

    func testWorldMapTimeoutUnblocksTeardownAndLateCallbackCannotOverwriteRetry() async {
        let projectName = "world-map-timeout-\(UUID().uuidString)"
        let viewModel = SceneGeneratorViewModel(projectName: projectName)
        var lateCompletion: SETWorldMapCaptureResolver<ARWorldMap?>.Completion?
        viewModel.testingWorldMapCaptureOverride = {
            await SETWorldMapCaptureResolver<ARWorldMap?>.resolve(
                timeoutNanoseconds: 1,
                request: { completion in
                    lateCompletion = completion
                },
                sleep: { _ in }
            )
        }
        defer {
            DBService.shared.deleteUnifiedSceneProject(named: projectName) { _ in }
        }

        let firstResult = await viewModel.teardownAndWait()
        XCTAssertEqual(firstResult, .blocked(.worldMapSnapshotFailed))
        XCTAssertEqual(viewModel.testingProjectSnapshotSaveCount, 1)
        XCTAssertFalse(viewModel.testingInitialWorldMapIsPresent)
        XCTAssertNil(
            DBService.shared.loadUnifiedSceneProject(named: projectName)?.1,
            "A successful nil-map fallback must remove any persisted world map"
        )

        viewModel.testingWorldMapCaptureOverride = {
            .success(nil)
        }
        let retryResult = await viewModel.teardownAndWait()
        XCTAssertEqual(retryResult, .released)
        XCTAssertEqual(viewModel.testingProjectSnapshotSaveCount, 2)
        XCTAssertFalse(viewModel.testingInitialWorldMapIsPresent)
        XCTAssertNil(
            DBService.shared.loadUnifiedSceneProject(named: projectName)?.1,
            "A retry without a fresh map must not resurrect stale persisted state"
        )

        lateCompletion?(.success(nil))
        XCTAssertEqual(viewModel.testingProjectSnapshotSaveCount, 2)
    }

    func testTeardownCancelsGenerationAndPersistsExistingSceneOnce() async throws {
        let projectName = "generation-teardown-\(UUID().uuidString)"
        let oldScript = SceneScript(
            actors: [SceneActor(id: "actor_1", type: .human, name: "Старый актёр")],
            objects: [],
            beats: [
                SceneBeat(
                    id: "old_beat",
                    actions: [
                        SceneAction(
                            id: "old_action",
                            actorId: "actor_1",
                            type: .talk,
                            dialogue: "Старый текст",
                            sourceText: "Старый текст"
                        )
                    ],
                    minDuration: 0.5
                )
            ],
            spatialRelations: [],
            originalDescription: "Старый сценарий"
        )
        var cameraTransform = matrix_identity_float4x4
        cameraTransform.columns.3 = SIMD4<Float>(0, 1.5, 0, 1)
        let oldPlannedScene = SpatialPlannerService.shared.planScene(
            script: oldScript,
            cameraTransform: cameraTransform,
            detectedObjects: [],
            availablePlanes: [ScenePlaneSnapshot(alignment: .horizontal, y: 0)],
            markedObjects: []
        )
        let project = UnifiedSceneProject(
            name: projectName,
            sceneDescription: "Старый сценарий",
            parsedScript: oldScript,
            plannedScene: oldPlannedScene
        )
        try DBService.shared.saveUnifiedSceneProject(project, worldMap: nil)
        defer {
            DBService.shared.deleteUnifiedSceneProject(named: projectName) { _ in }
        }

        let viewModel = SceneGeneratorViewModel(projectName: projectName, isNewProject: false)
        viewModel.testingSetPlanningContext(
            cameraTransform: cameraTransform,
            planes: [ScenePlaneSnapshot(alignment: .horizontal, y: 0)]
        )
        viewModel.sceneDescription = "Новый сценарий"
        viewModel.testingSetGenerationDelay(60)
        let captureStarted = AsyncGate()
        let captureCompleted = AsyncGate()
        viewModel.testingWorldMapCaptureOverride = {
            captureStarted.open()
            await captureCompleted.wait()
            return .success(nil)
        }
        viewModel.showInput()
        viewModel.testingResetGenerationStateTrace()
        let oldStoryboardItems = viewModel.storyboardBeatItems
        XCTAssertFalse(oldStoryboardItems.isEmpty)

        let firstGeneration = Task { @MainActor in
            await viewModel.generateScene()
        }
        for _ in 0..<100 where viewModel.generationStage != .reading {
            await Task.yield()
        }
        XCTAssertEqual(viewModel.generationStage, .reading)

        let secondCallerEntered = AsyncGate()
        let secondGenerationEvents = EventRecorder()
        let secondGeneration = Task { @MainActor in
            secondCallerEntered.open()
            await viewModel.generateScene()
            secondGenerationEvents.events.append("finished")
        }
        await secondCallerEntered.wait()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(viewModel.testingGenerationOwnerCount, 1)
        XCTAssertTrue(secondGenerationEvents.events.isEmpty)

        let teardown = Task { @MainActor in
            await viewModel.teardownAndWait()
        }
        await captureStarted.wait()
        XCTAssertFalse(viewModel.isWorkspaceReleased)
        XCTAssertFalse(viewModel.canGenerateScene)

        let generationDuringTeardown = Task { @MainActor in
            await viewModel.generateScene()
        }
        await generationDuringTeardown.value
        XCTAssertEqual(viewModel.testingGenerationOwnerCount, 1)
        XCTAssertEqual(viewModel.plannedScene, oldPlannedScene)
        XCTAssertEqual(viewModel.storyboardBeatItems, oldStoryboardItems)

        captureCompleted.open()
        let teardownResult = await teardown.value
        XCTAssertEqual(teardownResult, .released)
        XCTAssertEqual(viewModel.testingProjectSnapshotSaveCount, 1)
        XCTAssertFalse(viewModel.isGenerating)
        XCTAssertEqual(viewModel.generationRequestState.phase, .idle)
        XCTAssertTrue(viewModel.testingGenerationStateTrace.contains { $0.phase == .cancelling })
        XCTAssertFalse(viewModel.testingGenerationStateTrace.contains { $0.phase == .success })
        XCTAssertTrue(viewModel.isWorkspaceReleased)
        XCTAssertEqual(viewModel.plannedScene, oldPlannedScene)
        XCTAssertEqual(viewModel.storyboardBeatItems, oldStoryboardItems)
        XCTAssertTrue(viewModel.showInputSheet)

        await firstGeneration.value
        await secondGeneration.value

        XCTAssertEqual(secondGenerationEvents.events, ["finished"])
        XCTAssertEqual(viewModel.testingProjectSnapshotSaveCount, 1)
        XCTAssertEqual(viewModel.plannedScene, oldPlannedScene)
        XCTAssertEqual(viewModel.storyboardBeatItems, oldStoryboardItems)
        let persisted = try XCTUnwrap(DBService.shared.loadUnifiedSceneProject(named: projectName)?.0)
        XCTAssertEqual(persisted.plannedScene, oldPlannedScene)
        XCTAssertEqual(persisted.parsedScript, oldScript)
    }

    func testConcurrentProjectSnapshotsShareCaptureAndPersistLatestState() async {
        let projectName = "world-map-coalesced-\(UUID().uuidString)"
        let viewModel = SceneGeneratorViewModel(projectName: projectName)
        let captureStarted = AsyncGate()
        let captureCompleted = AsyncGate()
        var captureCount = 0
        viewModel.testingWorldMapCaptureOverride = {
            captureCount += 1
            captureStarted.open()
            await captureCompleted.wait()
            return .success(nil)
        }
        defer {
            DBService.shared.deleteUnifiedSceneProject(named: projectName) { _ in }
        }

        let first = Task { @MainActor in
            await viewModel.testingPersistProjectSnapshot()
        }
        await captureStarted.wait()

        let latestDescription = "Состояние изменилось во время снимка"
        viewModel.sceneDescription = latestDescription
        let second = Task { @MainActor in
            await viewModel.testingPersistProjectSnapshot()
        }
        for _ in 0..<10 {
            await Task.yield()
        }

        XCTAssertEqual(captureCount, 1)
        captureCompleted.open()

        let firstResult = await first.value
        let secondResult = await second.value
        if case .failure(let failure) = firstResult {
            XCTFail("first snapshot failed: \(failure)")
        }
        if case .failure(let failure) = secondResult {
            XCTFail("second snapshot failed: \(failure)")
        }
        XCTAssertEqual(viewModel.testingProjectSnapshotSaveCount, 1)
        XCTAssertEqual(
            DBService.shared.loadUnifiedSceneProject(named: projectName)?.0.sceneDescription,
            latestDescription
        )
    }

    func testPersistenceFailureCanRetryAndDetachExactlyOnce() async {
        let recorder = EventRecorder()
        var persistenceAttempt = 0
        let workspace = TestSceneWorkspace(
            isRecording: true,
            isPlaying: true,
            recorder: recorder,
            persistResultProvider: {
                persistenceAttempt += 1
                return persistenceAttempt == 1
                    ? .failure(.persistenceFailed)
                    : .success(())
            }
        )

        let result = await workspace.teardownAndWait()

        XCTAssertEqual(result, .blocked(.persistenceFailed))
        XCTAssertEqual(
            recorder.events,
            ["stop-recording", "stop-playback", "persist"]
        )
        XCTAssertNotEqual(result, .released)
        let retryResult = await workspace.teardownAndWait()
        XCTAssertEqual(retryResult, .released)
        XCTAssertEqual(persistenceAttempt, 2)
        XCTAssertEqual(
            recorder.events,
            [
                "stop-recording",
                "stop-playback",
                "persist",
                "persist",
                "release-recording",
                "pause-and-detach"
            ]
        )
        XCTAssertEqual(recorder.events.filter { $0 == "release-recording" }.count, 1)
        XCTAssertEqual(recorder.events.filter { $0 == "pause-and-detach" }.count, 1)
    }

    func testConcurrentPersistenceFailureCallersShareAttemptAndLaterRetry() async {
        let persistenceStarted = AsyncGate()
        let persistenceCompletion = AsyncGate()
        let recorder = EventRecorder()
        var persistenceAttempt = 0
        let workspace = TestSceneWorkspace(
            isRecording: true,
            isPlaying: true,
            recorder: recorder,
            persist: {
                persistenceStarted.open()
                await persistenceCompletion.wait()
            },
            persistResultProvider: {
                persistenceAttempt += 1
                return persistenceAttempt == 1
                    ? .failure(.persistenceFailed)
                    : .success(())
            }
        )

        let first = Task { @MainActor in
            await workspace.teardownAndWait()
        }
        await persistenceStarted.wait()

        let second = Task { @MainActor in
            await workspace.teardownAndWait()
        }
        for _ in 0..<10 {
            await Task.yield()
        }

        XCTAssertEqual(recorder.events.filter { $0 == "persist" }.count, 1)
        persistenceCompletion.open()

        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertEqual(firstResult, .blocked(.persistenceFailed))
        XCTAssertEqual(secondResult, .blocked(.persistenceFailed))
        XCTAssertEqual(recorder.events, ["stop-recording", "stop-playback", "persist"])
        let retryResult = await workspace.teardownAndWait()

        XCTAssertEqual(retryResult, .released)
        XCTAssertEqual(persistenceAttempt, 2)
        XCTAssertEqual(recorder.events.filter { $0 == "persist" }.count, 2)
        XCTAssertEqual(recorder.events.filter { $0 == "release-recording" }.count, 1)
        XCTAssertEqual(recorder.events.filter { $0 == "pause-and-detach" }.count, 1)
    }

    func testRouteBackgroundHookUsesTheSameIdempotentWorkspaceTeardown() async throws {
        let recorder = EventRecorder()
        let workspace = TestSceneWorkspace(
            isRecording: true,
            isPlaying: true,
            recorder: recorder
        )
        let route = try makeRoute(with: workspace)

        let result = await route.handleDidEnterBackground()

        XCTAssertEqual(result, .released)
        XCTAssertEqual(
            recorder.events,
            [
                "stop-recording",
                "stop-playback",
                "persist",
                "release-recording",
                "pause-and-detach"
            ]
        )
        let repeatedResult = await route.handleDidEnterBackground()
        XCTAssertEqual(repeatedResult, .released)
        XCTAssertEqual(
            recorder.events,
            [
                "stop-recording",
                "stop-playback",
                "persist",
                "release-recording",
                "pause-and-detach"
            ]
        )
    }

    func testSceneRouteAwaitsInjectedWorkspaceBeforeConstructingCamera() async throws {
        let persistenceStarted = AsyncGate()
        let persistenceCompletion = AsyncGate()
        let recorder = EventRecorder()
        let workspace = TestSceneWorkspace(
            isRecording: true,
            isPlaying: true,
            recorder: recorder,
            persist: {
                persistenceStarted.open()
                await persistenceCompletion.wait()
            }
        )
        let sceneLibrary = UIViewController()
        var cameraBuilderCallCount = 0
        let shell = CommercialShellComposition(
            cameraCoachBuilder: {
                cameraBuilderCallCount += 1
                return CommercialCameraCoachRoute(
                    viewController: UIViewController(),
                    stopAndWait: {}
                )
            },
            sceneLibraryBuilder: { sceneLibrary },
            historyBuilder: { UIViewController() }
        ).makeShell()

        await shell.selectAndWait(.scenes)
        let route = try XCTUnwrap(shell.activeRoute as? CommercialSceneLibraryRoute)
        let hostingController = LandscapeHostingController(rootView: Color.clear)
        hostingController.sceneWorkspaceTeardownProvider = workspace
        route.navigationController.pushViewController(hostingController, animated: false)

        let transition = Task { @MainActor in
            await shell.selectAndWait(.camera)
        }
        await persistenceStarted.wait()

        XCTAssertEqual(cameraBuilderCallCount, 1)
        XCTAssertTrue(shell.activeRoute === route)
        XCTAssertEqual(route.navigationController.viewControllers.count, 2)

        persistenceCompletion.open()
        await transition.value

        XCTAssertEqual(cameraBuilderCallCount, 2)
        XCTAssertTrue(shell.activeRoute is CommercialCameraCoachRoute)
        XCTAssertEqual(route.navigationController.viewControllers.count, 1)
        XCTAssertIdentical(route.navigationController.viewControllers.first, sceneLibrary)
        XCTAssertEqual(
            recorder.events,
            [
                "stop-recording",
                "stop-playback",
                "persist",
                "release-recording",
                "pause-and-detach"
            ]
        )
    }

    func testSceneWorkspaceFailureRetainsRouteAndDoesNotConstructCamera() async throws {
        let recorder = EventRecorder()
        let workspace = TestSceneWorkspace(
            isRecording: true,
            isPlaying: true,
            recorder: recorder,
            persistResult: .failure(.persistenceFailed)
        )
        let sceneLibrary = UIViewController()
        var cameraBuilderCallCount = 0
        let shell = CommercialShellComposition(
            cameraCoachBuilder: {
                cameraBuilderCallCount += 1
                return CommercialCameraCoachRoute(
                    viewController: UIViewController(),
                    stopAndWait: {}
                )
            },
            sceneLibraryBuilder: { sceneLibrary },
            historyBuilder: { UIViewController() }
        ).makeShell()

        await shell.selectAndWait(.scenes)
        let route = try XCTUnwrap(shell.activeRoute as? CommercialSceneLibraryRoute)
        let hostingController = LandscapeHostingController(rootView: Color.clear)
        hostingController.sceneWorkspaceTeardownProvider = workspace
        route.navigationController.pushViewController(hostingController, animated: false)

        await shell.selectAndWait(.camera)

        XCTAssertEqual(cameraBuilderCallCount, 1)
        XCTAssertTrue(shell.activeRoute === route)
        XCTAssertEqual(route.navigationController.viewControllers.count, 2)
        XCTAssertEqual(
            route.lastSceneWorkspaceTeardownResult,
            .blocked(.persistenceFailed)
        )
        XCTAssertEqual(
            recorder.events,
            ["stop-recording", "stop-playback", "persist"]
        )
    }

    func testPresentedSceneModalBlocksWithoutStartingWorkspaceTeardown() async throws {
        let recorder = EventRecorder()
        let workspace = TestSceneWorkspace(
            isRecording: true,
            isPlaying: true,
            recorder: recorder
        )
        let sceneLibrary = UIViewController()
        var cameraBuilderCallCount = 0
        let shell = CommercialShellComposition(
            cameraCoachBuilder: {
                cameraBuilderCallCount += 1
                return CommercialCameraCoachRoute(
                    viewController: UIViewController(),
                    stopAndWait: {}
                )
            },
            sceneLibraryBuilder: { sceneLibrary },
            historyBuilder: { UIViewController() }
        ).makeShell()

        await shell.selectAndWait(.scenes)
        let route = try XCTUnwrap(shell.activeRoute as? CommercialSceneLibraryRoute)
        let hostingController = LandscapeHostingController(rootView: Color.clear)
        hostingController.sceneWorkspaceTeardownProvider = workspace
        route.navigationController.pushViewController(hostingController, animated: false)

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = shell
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let modal = UIViewController()
        hostingController.present(modal, animated: false)
        XCTAssertIdentical(hostingController.presentedViewController, modal)

        await shell.selectAndWait(.camera)

        XCTAssertEqual(cameraBuilderCallCount, 1)
        XCTAssertTrue(shell.activeRoute === route)
        XCTAssertEqual(recorder.events, [])
        XCTAssertEqual(route.navigationController.viewControllers.count, 2)
        modal.dismiss(animated: false)
    }

    private func makeRoute(
        with workspace: any SceneWorkspaceTeardownProviding
    ) throws -> CommercialSceneLibraryRoute {
        let root = UIViewController()
        let route = CommercialSceneLibraryRoute(sceneLibraryViewController: root)
        let hostingController = LandscapeHostingController(rootView: Color.clear)
        hostingController.sceneWorkspaceTeardownProvider = workspace
        route.navigationController.pushViewController(hostingController, animated: false)
        return route
    }
}

@MainActor
private final class TestSceneWorkspace: SceneWorkspaceTeardownProviding {
    private let coordinator: SceneWorkspaceTeardownCoordinator

    init(
        isRecording: Bool,
        isPlaying: Bool,
        recorder: EventRecorder,
        stopRecording: @escaping @MainActor () async -> Void = {},
        releaseRecording: @escaping @MainActor () async -> Void = {},
        persist: @escaping @MainActor () async -> Void = {},
        persistResult: Result<Void, SceneWorkspaceTeardownFailure> = .success(()),
        persistResultProvider: (@MainActor () -> Result<Void, SceneWorkspaceTeardownFailure>)? = nil
    ) {
        var recordingActive = isRecording
        var playbackActive = isPlaying
        coordinator = SceneWorkspaceTeardownCoordinator(
            stopRecordingIfNeeded: {
                if recordingActive {
                    recordingActive = false
                    recorder.events.append("stop-recording")
                    await stopRecording()
                }
            },
            stopPlaybackIfNeeded: {
                guard playbackActive else { return }
                playbackActive = false
                recorder.events.append("stop-playback")
            },
            persist: {
                recorder.events.append("persist")
                await persist()
                return persistResultProvider?() ?? persistResult
            },
            pauseAndDetach: {
                recorder.events.append("pause-and-detach")
            },
            releaseRecordingIfNeeded: {
                recorder.events.append("release-recording")
                await releaseRecording()
            }
        )
    }

    func teardownAndWait() async -> SceneWorkspaceTeardownResult {
        await coordinator.teardownAndWait()
    }
}

@MainActor
private final class EventRecorder {
    var events: [String] = []
}

private final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            guard !isOpen else {
                lock.unlock()
                continuation.resume()
                return
            }
            waiters.append(continuation)
            lock.unlock()
        }
    }

    func open() {
        lock.lock()
        guard !isOpen else {
            lock.unlock()
            return
        }
        isOpen = true
        let waiters = self.waiters
        self.waiters.removeAll()
        lock.unlock()
        waiters.forEach { $0.resume() }
    }
}
