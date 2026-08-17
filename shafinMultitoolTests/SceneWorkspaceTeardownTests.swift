import SwiftUI
import UIKit
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
        XCTAssertEqual(recorder.events, ["persist", "pause-and-detach"])
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
            ["stop-recording", "stop-playback", "persist", "pause-and-detach"]
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

        XCTAssertEqual(recorder.events, ["stop-recording", "stop-playback", "persist"])

        persistenceCompletion.open()
        let firstResult = await first.value
        let secondResult = await second.value
        let repeatedResult = await workspace.teardownAndWait()
        XCTAssertEqual(firstResult, .released)
        XCTAssertEqual(secondResult, .released)
        XCTAssertEqual(repeatedResult, .released)
        XCTAssertEqual(
            recorder.events,
            ["stop-recording", "stop-playback", "persist", "pause-and-detach"]
        )
    }

    func testPersistenceFailureBlocksWithoutPausingOrClaimingRelease() async {
        let recorder = EventRecorder()
        let workspace = TestSceneWorkspace(
            isRecording: true,
            isPlaying: true,
            recorder: recorder,
            persistResult: .failure(.persistenceFailed)
        )

        let result = await workspace.teardownAndWait()

        XCTAssertEqual(result, .blocked(.persistenceFailed))
        XCTAssertEqual(recorder.events, ["stop-recording", "stop-playback", "persist"])
        XCTAssertNotEqual(result, .released)
        let repeatedResult = await workspace.teardownAndWait()
        XCTAssertEqual(repeatedResult, .blocked(.persistenceFailed))
        XCTAssertEqual(recorder.events, ["stop-recording", "stop-playback", "persist"])
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
            ["stop-recording", "stop-playback", "persist", "pause-and-detach"]
        )
        let repeatedResult = await route.handleDidEnterBackground()
        XCTAssertEqual(repeatedResult, .released)
        XCTAssertEqual(
            recorder.events,
            ["stop-recording", "stop-playback", "persist", "pause-and-detach"]
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
            ["stop-recording", "stop-playback", "persist", "pause-and-detach"]
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
        XCTAssertEqual(recorder.events, ["stop-recording", "stop-playback", "persist"])
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
        persist: @escaping @MainActor () async -> Void = {},
        persistResult: Result<Void, SceneWorkspaceTeardownFailure> = .success(())
    ) {
        var recordingActive = isRecording
        var playbackActive = isPlaying
        coordinator = SceneWorkspaceTeardownCoordinator(
            stopRecordingIfNeeded: {
                guard recordingActive else { return }
                recordingActive = false
                recorder.events.append("stop-recording")
            },
            stopPlaybackIfNeeded: {
                guard playbackActive else { return }
                playbackActive = false
                recorder.events.append("stop-playback")
            },
            persist: {
                recorder.events.append("persist")
                await persist()
                return persistResult
            },
            pauseAndDetach: {
                recorder.events.append("pause-and-detach")
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
