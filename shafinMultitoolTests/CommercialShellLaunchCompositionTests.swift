import UIKit
import SwiftUI
import XCTest
@testable import shafinMultitool

@MainActor
final class CommercialShellLaunchCompositionTests: XCTestCase {

    func testNormalCompositionSelectsCameraAndKeepsSecondaryRoutesLazy() throws {
        let shell = CommercialShellComposition(
            cameraCoachBuilder: {
                CommercialCameraCoachRoute(
                    viewController: UIViewController(),
                    stopAndWait: {}
                )
            },
            sceneLibraryBuilder: { UIViewController() },
            historyBuilder: { CommercialHistoryEmptyViewController() }
        ).makeShell()

        XCTAssertEqual(shell.selectedSection, .camera)
        XCTAssertEqual(shell.children.count, 1)
        XCTAssertEqual(shell.view.accessibilityIdentifier, "commercial-shell")
        XCTAssertTrue(shell.activeRoute is CommercialCameraCoachRoute)
        XCTAssertNil(shell.activeRoute as? CommercialSceneLibraryRoute)
        XCTAssertNil(shell.activeRoute as? CommercialHistoryRoute)
    }

    func testScenesRouteUsesInjectedLibraryBuilderInsideNavigationContainer() async throws {
        let sceneLibrary = UIViewController()
        var builderCallCount = 0
        let shell = CommercialShellComposition(
            cameraCoachBuilder: {
                CommercialCameraCoachRoute(
                    viewController: UIViewController(),
                    stopAndWait: {}
                )
            },
            sceneLibraryBuilder: {
                builderCallCount += 1
                return sceneLibrary
            },
            historyBuilder: { CommercialHistoryEmptyViewController() }
        ).makeShell()

        XCTAssertEqual(builderCallCount, 0)

        await shell.selectAndWait(.scenes)

        let route = try XCTUnwrap(shell.activeRoute as? CommercialSceneLibraryRoute)
        let navigationController = try XCTUnwrap(
            route.viewController as? UINavigationController
        )
        XCTAssertEqual(builderCallCount, 1)
        XCTAssertEqual(navigationController.viewControllers.count, 1)
        XCTAssertIdentical(navigationController.viewControllers.first, sceneLibrary)
        XCTAssertTrue(navigationController.navigationBar.isHidden)
        XCTAssertTrue(
            navigationController.interactivePopGestureRecognizer?.delegate
                is CommercialNavigationInteractivePopGuard
        )
    }

    func testCameraRouteUsesContentViewAndNotBenchmarkOrLegacyCameraScreen() throws {
        let shell = CommercialShellComposition(
            sceneLibraryBuilder: { UIViewController() },
            historyBuilder: { CommercialHistoryEmptyViewController() }
        ).makeShell()

        let route = try XCTUnwrap(shell.activeRoute as? CommercialCameraCoachRoute)
        let viewController = route.viewController

        XCTAssertTrue(viewController is UIHostingController<ContentView>)
        XCTAssertFalse(viewController is UIHostingController<DeviceBenchmarkRootView>)
        XCTAssertFalse(viewController is CameraScreenViewController)
    }

    func testHistoryRouteIsExplicitEmptyStateWithoutPersistenceAction() async throws {
        let shell = CommercialShellComposition(
            cameraCoachBuilder: {
                CommercialCameraCoachRoute(
                    viewController: UIViewController(),
                    stopAndWait: {}
                )
            },
            sceneLibraryBuilder: { UIViewController() }
        ).makeShell()

        await shell.selectAndWait(.history)

        let route = try XCTUnwrap(shell.activeRoute as? CommercialHistoryRoute)
        let emptyViewController = try XCTUnwrap(
            route.viewController as? CommercialHistoryEmptyViewController
        )

        XCTAssertTrue(emptyViewController.isEmptyState)
        XCTAssertNil(emptyViewController.persistenceAction)
        XCTAssertFalse(emptyViewController.view.subviews.contains { $0 is UIButton })
        XCTAssertEqual(
            emptyViewController.emptyStateMessage,
            "Completed coaching results will appear here."
        )
    }

    func testCameraReleaseWaitsForStopBeforeSceneConstructionAndDropsOldOwner() async throws {
        let stopStarted = CommercialCompositionTestGate()
        let stopCompletion = CommercialCompositionTestGate()
        var events: [String] = []
        weak var oldCameraRoute: CommercialCameraCoachRoute?

        let shell = CommercialShellComposition(
            cameraCoachBuilder: {
                events.append("camera.constructed")
                let route = CommercialCameraCoachRoute(
                    viewController: UIViewController(),
                    stopAndWait: {
                        events.append("camera.stop.started")
                        stopStarted.open()
                        await stopCompletion.wait()
                        events.append("camera.stop.finished")
                    }
                )
                oldCameraRoute = route
                return route
            },
            sceneLibraryBuilder: {
                events.append("scene.constructed")
                return UIViewController()
            },
            historyBuilder: { UIViewController() }
        ).makeShell()

        let transition = Task { @MainActor in
            await shell.selectAndWait(.scenes)
        }
        await stopStarted.wait()

        XCTAssertEqual(events, ["camera.constructed", "camera.stop.started"])
        XCTAssertEqual(shell.children.count, 1)
        XCTAssertNil(shell.activeRoute as? CommercialSceneLibraryRoute)

        stopCompletion.open()
        await transition.value

        XCTAssertEqual(events, [
            "camera.constructed",
            "camera.stop.started",
            "camera.stop.finished",
            "scene.constructed"
        ])
        XCTAssertTrue(shell.activeRoute is CommercialSceneLibraryRoute)
        XCTAssertEqual(shell.children.count, 1)
        XCTAssertNil(oldCameraRoute)
    }

    func testCameraReleaseIsSharedAndIdempotentForReentrantCallers() async {
        let stopStarted = CommercialCompositionTestGate()
        let stopCompletion = CommercialCompositionTestGate()
        var stopCallCount = 0

        let route = CommercialCameraCoachRoute(
            viewController: UIViewController(),
            stopAndWait: {
                stopCallCount += 1
                stopStarted.open()
                await stopCompletion.wait()
            }
        )

        let firstRelease = Task { @MainActor in
            await route.deactivateAndWait()
        }
        await stopStarted.wait()
        let secondRelease = Task { @MainActor in
            await route.deactivateAndWait()
        }

        for _ in 0..<10 {
            await Task.yield()
        }
        XCTAssertEqual(stopCallCount, 1)

        stopCompletion.open()
        let firstResult = await firstRelease.value
        let secondResult = await secondRelease.value
        let repeatedResult = await route.deactivateAndWait()
        XCTAssertEqual(firstResult, .released)
        XCTAssertEqual(secondResult, .released)
        XCTAssertEqual(repeatedResult, .released)
        XCTAssertEqual(stopCallCount, 1)
    }

    func testSceneRouteReleasesAtOriginalLibraryRoot() async {
        let route = CommercialSceneLibraryRoute(
            sceneLibraryViewController: UIViewController()
        )

        XCTAssertEqual(
            route.deactivationBlockReason,
            .sceneWorkspaceTeardownIsNotAwaitable
        )
        let firstResult = await route.deactivateAndWait()
        let secondResult = await route.deactivateAndWait()
        XCTAssertEqual(firstResult, .released)
        XCTAssertEqual(secondResult, .released)
    }

    func testSceneLibraryRootReleaseConstructsCameraRoute() async throws {
        var cameraBuilderCallCount = 0
        let shell = CommercialShellComposition(
            cameraCoachBuilder: {
                cameraBuilderCallCount += 1
                return CommercialCameraCoachRoute(
                    viewController: UIViewController(),
                    stopAndWait: {}
                )
            },
            sceneLibraryBuilder: { UIViewController() },
            historyBuilder: { UIViewController() }
        ).makeShell()

        await shell.selectAndWait(.scenes)
        XCTAssertTrue(shell.activeRoute is CommercialSceneLibraryRoute)

        await shell.selectAndWait(.camera)

        XCTAssertEqual(cameraBuilderCallCount, 2)
        XCTAssertTrue(shell.activeRoute is CommercialCameraCoachRoute)
        XCTAssertEqual(shell.selectedSection, .camera)
        XCTAssertEqual(shell.children.count, 1)
    }

    func testDeeperSceneWorkspaceBlocksAndDoesNotConstructCamera() async throws {
        var cameraBuilderCallCount = 0
        let sceneLibrary = UIViewController()
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
        let sceneRoute = try XCTUnwrap(shell.activeRoute as? CommercialSceneLibraryRoute)
        let workspace = UIViewController()
        sceneRoute.navigationController.pushViewController(workspace, animated: false)

        await shell.selectAndWait(.camera)

        XCTAssertEqual(cameraBuilderCallCount, 1)
        XCTAssertTrue(shell.activeRoute === sceneRoute)
        XCTAssertEqual(shell.selectedSection, .scenes)
        XCTAssertEqual(sceneRoute.navigationController.viewControllers.count, 2)
        XCTAssertEqual(shell.children.count, 1)
    }

    func testPresentedSceneModalBlocksAndDoesNotConstructCamera() async throws {
        var cameraBuilderCallCount = 0
        let sceneLibrary = UIViewController()
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
        let sceneRoute = try XCTUnwrap(shell.activeRoute as? CommercialSceneLibraryRoute)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = shell
        window.makeKeyAndVisible()
        defer {
            sceneLibrary.dismiss(animated: false)
            window.isHidden = true
        }

        let modal = UIViewController()
        sceneLibrary.present(modal, animated: false)
        XCTAssertIdentical(sceneLibrary.presentedViewController, modal)

        await shell.selectAndWait(.camera)

        XCTAssertEqual(cameraBuilderCallCount, 1)
        XCTAssertTrue(shell.activeRoute === sceneRoute)
        XCTAssertEqual(shell.selectedSection, .scenes)
        XCTAssertEqual(sceneRoute.navigationController.viewControllers.count, 1)
        XCTAssertEqual(shell.children.count, 1)
    }

    func testBenchmarkSelectionWinsBeforeCommercialComposition() {
        let benchmarkConfig = DeviceBenchmarkConfig.defaultQuick
        let benchmarkRoot = UIViewController()
        let commercialRoot = UIViewController()
        var benchmarkCallCount = 0
        var commercialCallCount = 0

        let selectedBenchmarkRoot = SceneDelegate.makeRootViewController(
            benchmarkConfig: benchmarkConfig,
            benchmarkRootBuilder: { receivedConfig in
                benchmarkCallCount += 1
                XCTAssertEqual(receivedConfig, benchmarkConfig)
                return benchmarkRoot
            },
            commercialRootBuilder: {
                commercialCallCount += 1
                return commercialRoot
            }
        )

        XCTAssertIdentical(selectedBenchmarkRoot, benchmarkRoot)
        XCTAssertEqual(benchmarkCallCount, 1)
        XCTAssertEqual(commercialCallCount, 0)

        let selectedCommercialRoot = SceneDelegate.makeRootViewController(
            benchmarkConfig: nil,
            benchmarkRootBuilder: { _ in XCTFail("Benchmark root must not be built")
                return benchmarkRoot
            },
            commercialRootBuilder: {
                commercialCallCount += 1
                return commercialRoot
            }
        )

        XCTAssertIdentical(selectedCommercialRoot, commercialRoot)
        XCTAssertEqual(benchmarkCallCount, 1)
        XCTAssertEqual(commercialCallCount, 1)
    }
}

private final class CommercialCompositionTestGate: @unchecked Sendable {
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
