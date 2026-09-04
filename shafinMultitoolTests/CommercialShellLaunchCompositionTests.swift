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
        XCTAssertEqual(shell.modeControl.renderedSection, .camera)
        XCTAssertEqual(shell.children.count, 1)
        XCTAssertEqual(shell.view.accessibilityIdentifier, "commercial-shell")
        XCTAssertTrue(shell.activeRoute is CommercialCameraCoachRoute)
        XCTAssertFalse(shell.modeControl.isHidden)
        XCTAssertNil(shell.activeRoute as? CommercialSceneLibraryRoute)
        XCTAssertNil(shell.activeRoute as? CommercialHistoryRoute)
        XCTAssertTrue(shell.supportedInterfaceOrientations.contains(.portrait))
        XCTAssertTrue(shell.supportedInterfaceOrientations.contains(.landscape))
    }

    func testSharedCameraEntryFlowHidesChromeUntilEntryIsReady() async {
        let denied = shellPermissionSnapshot(authorization: .denied)
        let authorized = shellPermissionSnapshot(authorization: .authorized)
        let client = ShellEntryFlowPermissionClient(snapshots: [denied, authorized])
        let model = CameraCoachEntryFlowModel(
            permissionClient: client,
            introStore: ShellEntryFlowIntroStore(seen: true)
        )
        let shell = CommercialShellComposition(
            cameraCoachBuilder: {
                CommercialCameraCoachRoute(
                    viewController: UIViewController(),
                    stopAndWait: {},
                    entryFlowModel: model
                )
            },
            sceneLibraryBuilder: { UIViewController() },
            historyBuilder: { UIViewController() }
        ).makeShell()

        XCTAssertTrue(shell.modeControl.isHidden)
        XCTAssertFalse(modeControlButton(in: shell).isUserInteractionEnabled)

        await model.resolveInitialState()
        XCTAssertEqual(model.phase, .blocked(.denied))
        XCTAssertTrue(shell.modeControl.isHidden)

        await model.recheckCameraAccess()
        await Task.yield()

        XCTAssertEqual(model.phase, .ready)
        XCTAssertFalse(shell.modeControl.isHidden)
        XCTAssertTrue(modeControlButton(in: shell).isUserInteractionEnabled)
        let snapshotCount = await client.snapshotCount
        let requestCount = await client.requestCount
        XCTAssertEqual(snapshotCount, 2)
        XCTAssertEqual(requestCount, 0)

        shell.view.layoutIfNeeded()
        let snapshotCountAfterLayout = await client.snapshotCount
        XCTAssertEqual(snapshotCountAfterLayout, 2)
    }

    func testCameraChildFillsShellAndModeControlUsesTopSafeAreaOverlay() throws {
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
        shell.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        shell.view.layoutIfNeeded()

        let child = try XCTUnwrap(shell.activeViewController)
        XCTAssertEqual(child.view.frame, shell.view.bounds)
        // Icon-only size assertions are superseded by SET OS O-1: the published
        // control is the two-segment A/B ROLL capsule.
        XCTAssertGreaterThanOrEqual(
            shell.modeControl.bounds.width,
            SETABRollCapsuleContract.minimumControlSize.width
        )
        XCTAssertGreaterThanOrEqual(
            shell.modeControl.bounds.height,
            SETABRollCapsuleContract.minimumControlSize.height
        )
        XCTAssertEqual(
            shell.modeControl.frame.midX,
            shell.view.safeAreaLayoutGuide.layoutFrame.midX,
            accuracy: 0.5
        )
        XCTAssertGreaterThanOrEqual(
            shell.modeControl.frame.minY,
            shell.view.safeAreaLayoutGuide.layoutFrame.minY
        )
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
        XCTAssertEqual(navigationController.supportedInterfaceOrientations, .landscape)
        XCTAssertEqual(shell.supportedInterfaceOrientations, .landscape)
    }

    func testSwitchingSelectedRouteUpdatesShellOrientationPolicy() async throws {
        let shell = CommercialShellComposition(
            sceneLibraryBuilder: { UIViewController() },
            historyBuilder: { UIViewController() }
        ).makeShell()

        XCTAssertTrue(shell.supportedInterfaceOrientations.contains(.portrait))
        XCTAssertTrue(shell.supportedInterfaceOrientations.contains(.landscape))

        await shell.selectAndWait(.scenes)
        XCTAssertEqual(shell.supportedInterfaceOrientations, .landscape)

        await shell.selectAndWait(.camera)
        XCTAssertTrue(shell.supportedInterfaceOrientations.contains(.portrait))
        XCTAssertTrue(shell.supportedInterfaceOrientations.contains(.landscape))
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
        XCTAssertTrue(viewController.supportedInterfaceOrientations.contains(.portrait))
        XCTAssertTrue(viewController.supportedInterfaceOrientations.contains(.landscape))
        XCTAssertTrue(shell.supportedInterfaceOrientations.contains(.portrait))
        XCTAssertTrue(shell.supportedInterfaceOrientations.contains(.landscape))
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
        XCTAssertEqual(emptyViewController.emptyStateTitle, "История")
        XCTAssertEqual(
            emptyViewController.emptyStateMessage,
            "Завершённые разборы этой сессии появятся здесь."
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
        XCTAssertEqual(shell.supportedInterfaceOrientations, .landscape)
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

    private func modeControlButton(
        in shell: CommercialShellViewController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> UIButton {
        guard let button = allViews(in: shell.modeControl)
            .compactMap({ $0 as? UIButton })
            .first else {
            XCTFail("Missing shell mode control button", file: file, line: line)
            return UIButton(type: .system)
        }
        return button
    }

    private func allViews(in root: UIView) -> [UIView] {
        [root] + root.subviews.flatMap(allViews)
    }

    private func shellPermissionSnapshot(
        authorization: PermissionAuthorization,
        available: Bool = true
    ) -> PermissionSnapshot {
        PermissionSnapshot(
            permission: .camera,
            authorization: authorization,
            availability: available ? .available : .unavailable(.cameraHardware)
        )
    }
}

private actor ShellEntryFlowPermissionClient: PermissionClient {
    private var snapshots: [PermissionSnapshot]
    private(set) var snapshotCount = 0
    private(set) var requestCount = 0

    init(snapshots: [PermissionSnapshot]) {
        self.snapshots = snapshots
    }

    func snapshot(for permission: AppPermission) async -> PermissionSnapshot {
        snapshotCount += 1
        guard permission == .camera else {
            return PermissionSnapshot(
                permission: permission,
                authorization: .unknown,
                availability: .available
            )
        }
        if snapshots.count > 1 {
            return snapshots.removeFirst()
        }
        return snapshots[0]
    }

    func request(_ permission: AppPermission) async -> PermissionSnapshot {
        requestCount += 1
        return await snapshot(for: permission)
    }
}

private final class ShellEntryFlowIntroStore: CameraCoachIntroStore {
    private var seen: Bool

    init(seen: Bool) {
        self.seen = seen
    }

    func hasSeenCameraCoachIntro() -> Bool {
        seen
    }

    func markCameraCoachIntroSeen() {
        seen = true
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
