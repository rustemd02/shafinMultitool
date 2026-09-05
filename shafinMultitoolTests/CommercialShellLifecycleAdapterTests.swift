import SwiftUI
import UIKit
import XCTest
@testable import shafinMultitool

/// M1-004: one lifecycle adapter (SceneDelegate → CommercialShellViewController)
/// forwards each app lifecycle event to the active route owner exactly once.
@MainActor
final class CommercialShellLifecycleAdapterTests: XCTestCase {

    func testBackgroundReachesActiveCameraRouteExactlyOncePerEvent() {
        var backgroundCount = 0
        let shell = makeShell(cameraBackground: { backgroundCount += 1 })

        shell.handleSceneDidEnterBackground()

        XCTAssertEqual(backgroundCount, 1)
    }

    func testBackgroundAfterRouteSwitchNeverReachesInactiveCameraRoute() async {
        var backgroundCount = 0
        let shell = makeShell(cameraBackground: { backgroundCount += 1 })

        await shell.selectAndWait(.scenes)
        shell.handleSceneDidEnterBackground()

        await shell.selectAndWait(.history)
        shell.handleSceneDidEnterBackground()

        XCTAssertEqual(backgroundCount, 0)
        XCTAssertEqual(shell.selectedSection, .history)
    }

    func testBackgroundReachesSceneWorkspaceProviderExactlyOnce() async throws {
        let shell = makeShell(cameraBackground: {})
        await shell.selectAndWait(.scenes)
        let route = try XCTUnwrap(shell.activeRoute as? CommercialSceneLibraryRoute)

        let workspace = LifecycleFakeWorkspace()
        let hostingController = LandscapeHostingController(rootView: Color.clear)
        hostingController.sceneWorkspaceTeardownProvider = workspace
        route.navigationController.pushViewController(hostingController, animated: false)

        shell.handleSceneDidEnterBackground()
        await fulfillment(of: [workspace.teardownEntered], timeout: 2.0)
        // Allow any duplicate adapter Task to arrive before asserting count.
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(workspace.teardownCallCount, 1)
    }

    // MARK: - M7-015 background policy lease

    func testBackgroundBeginsOneLeaseAndEndsItAfterSceneDispatch() async throws {
        let shell = makeShell(cameraBackground: {})
        let coordinator = FakeSceneBackgroundTaskCoordinator()
        shell.backgroundTaskCoordinator = coordinator
        await shell.selectAndWait(.scenes)
        let route = try XCTUnwrap(shell.activeRoute as? CommercialSceneLibraryRoute)

        let workspace = LifecycleFakeWorkspace()
        let hostingController = LandscapeHostingController(rootView: Color.clear)
        hostingController.sceneWorkspaceTeardownProvider = workspace
        route.navigationController.pushViewController(hostingController, animated: false)

        shell.handleSceneDidEnterBackground()
        await fulfillment(of: [workspace.teardownEntered], timeout: 2.0)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(coordinator.beginCount, 1, "exactly one lease per background event")
        XCTAssertEqual(coordinator.endedIdentifiers.count, 1, "the lease is ended after the dispatch flushes")
        XCTAssertNotEqual(coordinator.endedIdentifiers.first, .invalid)
    }

    func testBackgroundWithoutRoutesBeginsAndImmediatelyEndsLease() {
        let shell = makeShell(cameraBackground: {})
        let coordinator = FakeSceneBackgroundTaskCoordinator()
        shell.backgroundTaskCoordinator = coordinator

        shell.handleSceneDidEnterBackground()

        XCTAssertEqual(coordinator.beginCount, 1)
        XCTAssertEqual(coordinator.endedIdentifiers.count, 1)
    }

    func testBackgroundLeaseEndsOnlyOncePerIdentifier() {
        let shell = makeShell(cameraBackground: {})
        let coordinator = FakeSceneBackgroundTaskCoordinator()
        shell.backgroundTaskCoordinator = coordinator

        shell.handleSceneDidEnterBackground()
        shell.handleSceneDidEnterBackground()

        XCTAssertEqual(coordinator.beginCount, 2)
        XCTAssertEqual(coordinator.endedIdentifiers.count, 2)
        XCTAssertEqual(Set(coordinator.endedIdentifiers).count, 2, "a stale lease cannot end a newer one")
    }

    func testForegroundRecheckStillReachesBlockedCameraEntry() async {
        let client = LifecycleFakePermissionClient(snapshots: [
            LifecycleFakePermissionClient.snapshot(authorization: .denied),
            LifecycleFakePermissionClient.snapshot(authorization: .authorized)
        ])
        let model = CameraCoachEntryFlowModel(
            permissionClient: client,
            introStore: LifecycleFakeIntroStore()
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

        await model.resolveInitialState()
        XCTAssertEqual(model.phase, .blocked(.denied))

        shell.handleAppDidBecomeActive()

        for _ in 0..<200 {
            if await client.snapshotCount >= 2 { break }
            await Task.yield()
        }
        let snapshotCount = await client.snapshotCount
        XCTAssertEqual(snapshotCount, 2)
        XCTAssertNotEqual(model.phase, .blocked(.denied))
    }

    // MARK: - Helpers

    private func makeShell(cameraBackground: @escaping @MainActor () -> Void) -> CommercialShellViewController {
        CommercialShellComposition(
            cameraCoachBuilder: {
                CommercialCameraCoachRoute(
                    viewController: UIViewController(),
                    stopAndWait: {},
                    sceneDidEnterBackground: cameraBackground
                )
            },
            sceneLibraryBuilder: { UIViewController() },
            historyBuilder: { UIViewController() }
        ).makeShell()
    }
}

private final class LifecycleFakeWorkspace: SceneWorkspaceTeardownProviding {
    let teardownEntered = XCTestExpectation(description: "workspace teardown entered")
    private(set) var teardownCallCount = 0

    func teardownAndWait() async -> SceneWorkspaceTeardownResult {
        teardownCallCount += 1
        teardownEntered.fulfill()
        return .released
    }
}

private actor LifecycleFakePermissionClient: PermissionClient {
    private var snapshots: [PermissionSnapshot]
    private(set) var snapshotCount = 0

    init(snapshots: [PermissionSnapshot]) {
        self.snapshots = snapshots
    }

    static func snapshot(authorization: PermissionAuthorization) -> PermissionSnapshot {
        PermissionSnapshot(
            permission: .camera,
            authorization: authorization,
            availability: .available
        )
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
        await snapshot(for: permission)
    }
}

private final class LifecycleFakeIntroStore: CameraCoachIntroStore {
    func hasSeenCameraCoachIntro() -> Bool { true }
    func markCameraCoachIntroSeen() {}
}


/// M7-015: deterministic background-task lease for lifecycle tests.
private final class FakeSceneBackgroundTaskCoordinator: SceneBackgroundTaskCoordinating {
    private(set) var beginCount = 0
    private(set) var endedIdentifiers: [UIBackgroundTaskIdentifier] = []
    private var nextIdentifier = UIBackgroundTaskIdentifier(rawValue: 77)

    func begin(withName name: String) -> UIBackgroundTaskIdentifier {
        beginCount += 1
        defer {
            nextIdentifier = UIBackgroundTaskIdentifier(
                rawValue: nextIdentifier.rawValue + 1
            ) ?? .invalid
        }
        return nextIdentifier
    }

    func end(_ identifier: UIBackgroundTaskIdentifier) {
        endedIdentifiers.append(identifier)
    }
}
