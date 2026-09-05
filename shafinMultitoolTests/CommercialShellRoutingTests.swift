import Foundation
import ARKit
import AVFoundation
import UIKit
import XCTest
@testable import shafinMultitool

@MainActor
final class CommercialShellRoutingTests: XCTestCase {

    func testDefaultCameraIsEagerAndSecondaryRoutesAreLazy() {
        let (shell, factory) = makeShell()

        XCTAssertEqual(factory.constructedSections, [.camera])
        XCTAssertEqual(shell.selectedSection, .camera)
        XCTAssertEqual(shell.children.count, 1)
        XCTAssertEqual(shell.modeControl.renderedSection, .camera)
        XCTAssertEqual(
            Set(modeControlButtons(in: shell).map(\.accessibilityIdentifier)),
            Set(["commercial-shell-open-scenes", "commercial-shell-return-camera"])
        )
        XCTAssertIdentical(shell.activeViewController, factory.route(for: .camera)?.viewController)
        XCTAssertNil(factory.route(for: .scenes))
        XCTAssertNil(factory.route(for: .history))
    }

    func testSelectingSecondaryRouteConstructsOnlyThatRoute() async {
        let (shell, factory) = makeShell()

        shell.select(.scenes)
        await shell.waitForTransition()

        XCTAssertEqual(factory.constructedSections, [.camera, .scenes])
        XCTAssertNotNil(factory.route(for: .scenes))
        XCTAssertNil(factory.route(for: .history))
        XCTAssertEqual(shell.selectedSection, .scenes)
    }

    func testSwitchKeepsExactlyOneContainedChild() async {
        let (shell, factory) = makeShell()

        shell.select(.scenes)
        await shell.waitForTransition()
        XCTAssertEqual(shell.children.count, 1)
        XCTAssertIdentical(shell.children.first, factory.route(for: .scenes)?.viewController)

        shell.select(.history)
        await shell.waitForTransition()
        XCTAssertEqual(shell.children.count, 1)
        XCTAssertIdentical(shell.children.first, factory.route(for: .history)?.viewController)
        XCTAssertEqual(factory.constructedSections, [.camera, .scenes, .history])
        XCTAssertEqual(shell.modeControl.renderedSection, .history)
        XCTAssertEqual(modeControlButton(in: shell).accessibilityIdentifier, "commercial-shell-return-camera")
    }

    func testOldRouteReleasesBeforeNextRouteIsConstructed() async throws {
        let deactivationGate = CommercialTestGate()
        let (shell, factory) = makeShell(plans: [
            .camera: [CommercialRoutePlan(gate: deactivationGate)]
        ])
        let cameraRoute = try XCTUnwrap(factory.route(for: .camera))

        shell.select(.scenes)
        await cameraRoute.deactivationStarted.wait()

        XCTAssertEqual(factory.constructedSections, [.camera])
        XCTAssertEqual(shell.children.count, 1)

        deactivationGate.open()
        await shell.waitForTransition()

        let scenesRoute = try XCTUnwrap(factory.route(for: .scenes))
        XCTAssertEqual(factory.events, [
            .constructed(.camera, cameraRoute.id),
            .deactivationStarted(.camera, cameraRoute.id),
            .deactivationFinished(.camera, cameraRoute.id),
            .constructed(.scenes, scenesRoute.id)
        ])
    }

    func testProductionCameraARBoundaryAwaitsTerminalOwnersAndRetriesSafely() async throws {
        let firstCamera = makeCameraARInteropFixture()
        let secondCamera = makeCameraARInteropFixture()
        let arRuntime = CameraARInteropRuntime()
        let arOwner = ARSceneContainer.Coordinator(
            viewModel: SceneGeneratorViewModel(
                projectName: "m6-004-interop-\(UUID().uuidString)",
                presentationLocale: Locale(identifier: "en")
            ),
            capabilityProvider: CameraARInteropCapabilities(),
            sessionRuntime: arRuntime
        )
        let sceneLibraryRoot = UIViewController()
        let sceneWorkspaceHost = CameraARInteropWorkspaceViewController()

        var persistenceAttempt = 0
        let persistenceStarted = CommercialTestGate()
        let retryPersistenceStarted = CommercialTestGate()
        let persistenceCompletion = CommercialTestGate()
        let workspaceTeardown = SceneWorkspaceTeardownCoordinator(
            stopRecordingIfNeeded: {},
            stopPlaybackIfNeeded: {},
            persist: {
                persistenceAttempt += 1
                persistenceStarted.open()
                if persistenceAttempt == 1 {
                    return .failure(.persistenceFailed)
                }
                retryPersistenceStarted.open()
                await persistenceCompletion.wait()
                return .success(())
            },
            pauseAndDetach: {
                arOwner.releaseSession()
            }
        )
        sceneWorkspaceHost.sceneWorkspaceTeardownProvider = workspaceTeardown

        var cameraConstructionCount = 0
        let sceneBuilder: @MainActor () -> UIViewController = {
            arOwner.attachSession(runtime: arRuntime)
            arOwner.configureSessionIfNeeded(
                request: ARWorldTrackingConfigurationRequest(depthRequested: false, initialWorldMap: nil),
                force: true
            )
            return sceneLibraryRoot
        }
        let composition = CommercialShellComposition(
            cameraCoachBuilder: {
                cameraConstructionCount += 1
                let fixture = cameraConstructionCount == 1 ? firstCamera : secondCamera
                if cameraConstructionCount == 2 {
                    // A real camera child may resume/start from a delayed
                    // presentation callback while it is being installed. The
                    // route fence must make this harmless after the first exit.
                    fixture.viewModel.start()
                }
                return CommercialCameraCoachRoute(
                    viewController: UIViewController(),
                    cameraViewModel: fixture.viewModel
                )
            },
            sceneLibraryBuilder: sceneBuilder,
            historyBuilder: { UIViewController() }
        )
        let shell = composition.makeShell()
        let cameraRoute = try XCTUnwrap(shell.activeRoute as? CommercialCameraCoachRoute)
        await firstCamera.viewModel.startAndWait()

        XCTAssertEqual(cameraConstructionCount, 1)
        XCTAssertEqual(firstCamera.runner.startCount, 1)

        // Camera -> Scene: route teardown must hold the shell at the current
        // route until CameraManager.stop/release has crossed its terminal gate.
        shell.select(.scenes)
        await firstCamera.runner.stopStarted.wait()
        shell.select(.scenes)
        shell.select(.history)
        shell.select(.scenes)

        // The old child is still retained by the shell while release is blocked.
        // Its late start/resume/lens callbacks must not reacquire the camera.
        firstCamera.viewModel.start()
        await firstCamera.viewModel.startAndWait()
        firstCamera.viewModel.togglePause()
        firstCamera.viewModel.switchLens(to: .telephoto)
        XCTAssertEqual(shell.selectedSection, .camera)
        XCTAssertIdentical(shell.activeRoute as AnyObject?, cameraRoute)
        XCTAssertEqual(cameraConstructionCount, 1)
        XCTAssertEqual(firstCamera.runner.startCount, 1)
        XCTAssertEqual(arRuntime.runCount, 0)

        firstCamera.runner.allowStop()
        await shell.waitForTransition()

        XCTAssertEqual(cameraConstructionCount, 1)
        XCTAssertEqual(firstCamera.runner.startCount, 1)
        XCTAssertEqual(firstCamera.manager.configurationState, .unconfigured)
        XCTAssertEqual(arRuntime.runCount, 1)
        let sceneRoute = try XCTUnwrap(shell.activeRoute as? CommercialSceneLibraryRoute)
        sceneRoute.navigationController.pushViewController(sceneWorkspaceHost, animated: false)

        // AR -> Camera: the first persistence attempt is blocked/failed, so the
        // route and AR owner remain active and no replacement Camera is started.
        shell.select(.camera)
        await persistenceStarted.wait()
        await shell.waitForTransition()
        XCTAssertEqual(shell.selectedSection, .scenes)
        XCTAssertIdentical(shell.activeRoute as AnyObject?, sceneRoute)
        XCTAssertEqual(cameraConstructionCount, 1)
        XCTAssertEqual(secondCamera.runner.startCount, 0)
        XCTAssertEqual(arOwner.releaseCount, 0)
        XCTAssertEqual(
            sceneRoute.lastSceneWorkspaceTeardownResult,
            .blocked(.persistenceFailed)
        )
        XCTAssertEqual(
            sceneRoute.deactivationBlockReason,
            .sceneWorkspaceTeardownFailed(.persistenceFailed)
        )

        // Retry through the shell owner. Persistence may now be held to prove
        // that AR pause/detach and replacement Camera construction are ordered.
        shell.select(.camera)
        await retryPersistenceStarted.wait()
        XCTAssertEqual(shell.selectedSection, .scenes)
        XCTAssertEqual(cameraConstructionCount, 1)
        XCTAssertEqual(secondCamera.runner.startCount, 0)
        XCTAssertEqual(arRuntime.pauseCount, 0)

        persistenceCompletion.open()
        await shell.waitForTransition()
        await secondCamera.runner.startCompleted.wait()

        XCTAssertEqual(shell.selectedSection, .camera)
        XCTAssertEqual(cameraConstructionCount, 2)
        XCTAssertEqual(arRuntime.pauseCount, 1)
        XCTAssertTrue(arOwner.isReleased)
        XCTAssertEqual(secondCamera.runner.startCount, 1)
        XCTAssertEqual(shell.children.count, 1)

        secondCamera.runner.allowStop()
        await shell.releaseAndWait()
    }

    func testBlockedDeactivationRetainsChildAndSelection() async throws {
        let deactivationGate = CommercialTestGate()
        let (shell, factory) = makeShell(plans: [
            .camera: [CommercialRoutePlan(gate: deactivationGate, result: .blocked)]
        ])
        let cameraRoute = try XCTUnwrap(factory.route(for: .camera))

        shell.select(.scenes)
        await cameraRoute.deactivationStarted.wait()
        deactivationGate.open()
        await shell.waitForTransition()

        XCTAssertEqual(cameraRoute.deactivationCallCount, 1)
        XCTAssertEqual(factory.constructedSections, [.camera])
        XCTAssertIdentical(shell.activeViewController, cameraRoute.viewController)
        XCTAssertIdentical(shell.children.first, cameraRoute.viewController)
        XCTAssertEqual(shell.selectedSection, .camera)
        XCTAssertEqual(shell.modeControl.renderedSection, .camera)
        XCTAssertEqual(
            modeControlButton(in: shell, identifier: "commercial-shell-open-scenes").accessibilityIdentifier,
            "commercial-shell-open-scenes"
        )
        XCTAssertFalse(shell.isTransitioning)
        XCTAssertTrue(modeControlButton(in: shell, identifier: "commercial-shell-open-scenes").isUserInteractionEnabled)
    }

    func testModeControlInteractionIsLockedDuringSwitch() async throws {
        let deactivationGate = CommercialTestGate()
        let (shell, factory) = makeShell(plans: [
            .camera: [CommercialRoutePlan(gate: deactivationGate)]
        ])
        let cameraRoute = try XCTUnwrap(factory.route(for: .camera))

        shell.select(.scenes)
        await cameraRoute.deactivationStarted.wait()

        XCTAssertTrue(shell.isTransitioning)
        XCTAssertFalse(modeControlButton(in: shell, identifier: "commercial-shell-open-scenes").isUserInteractionEnabled)
        XCTAssertEqual(shell.selectedSection, .camera)
        XCTAssertEqual(shell.modeControl.renderedSection, .camera)
        XCTAssertEqual(
            modeControlButton(in: shell, identifier: "commercial-shell-open-scenes").accessibilityIdentifier,
            "commercial-shell-open-scenes"
        )

        deactivationGate.open()
        await shell.waitForTransition()
        XCTAssertEqual(shell.selectedSection, .scenes)
        XCTAssertEqual(shell.modeControl.renderedSection, .scenes)
        XCTAssertEqual(
            modeControlButton(in: shell, identifier: "commercial-shell-return-camera").accessibilityIdentifier,
            "commercial-shell-return-camera"
        )
        XCTAssertTrue(modeControlButton(in: shell, identifier: "commercial-shell-return-camera").isUserInteractionEnabled)
    }

    func testRapidSelectionsCoalesceToLastRequestedSection() async throws {
        let deactivationGate = CommercialTestGate()
        let (shell, factory) = makeShell(plans: [
            .camera: [CommercialRoutePlan(gate: deactivationGate)]
        ])
        let cameraRoute = try XCTUnwrap(factory.route(for: .camera))

        shell.select(.scenes)
        await cameraRoute.deactivationStarted.wait()
        shell.select(.history)
        shell.select(.scenes)

        deactivationGate.open()
        await shell.waitForTransition()

        XCTAssertEqual(factory.constructedSections, [.camera, .scenes])
        XCTAssertNil(factory.route(for: .history))
        XCTAssertEqual(shell.selectedSection, .scenes)
    }

    func testSelectingCurrentSectionIsANoOp() async throws {
        let (shell, factory) = makeShell()
        let cameraRoute = try XCTUnwrap(factory.route(for: .camera))

        shell.select(.camera)
        await shell.waitForTransition()

        XCTAssertEqual(factory.constructedSections, [.camera])
        XCTAssertEqual(cameraRoute.deactivationCallCount, 0)
        XCTAssertIdentical(shell.activeViewController, cameraRoute.viewController)
        XCTAssertFalse(shell.isTransitioning)
        XCTAssertTrue(modeControlButton(in: shell).isUserInteractionEnabled)
    }

    func testContainmentLifecycleIsBalanced() async throws {
        let (shell, factory) = makeShell()
        let cameraRoute = try XCTUnwrap(factory.route(for: .camera))
        let cameraViewController = try XCTUnwrap(cameraRoute.viewController as? CommercialLifecycleViewController)

        XCTAssertIdentical(cameraViewController.parent, shell)
        XCTAssertEqual(cameraViewController.lifecycleEvents, [.willMoveToParent, .didMoveToParent])

        shell.select(.scenes)
        await shell.waitForTransition()

        let scenesRoute = try XCTUnwrap(factory.route(for: .scenes))
        let scenesViewController = try XCTUnwrap(scenesRoute.viewController as? CommercialLifecycleViewController)

        XCTAssertNil(cameraViewController.parent)
        XCTAssertEqual(cameraViewController.lifecycleEvents, [
            .willMoveToParent,
            .didMoveToParent,
            .willMoveToNil,
            .didMoveToNil
        ])
        XCTAssertIdentical(scenesViewController.parent, shell)
        XCTAssertEqual(scenesViewController.lifecycleEvents, [.willMoveToParent, .didMoveToParent])
    }

    func testContainerTeardownReleasesActiveRoute() async throws {
        let deactivationGate = CommercialTestGate()
        let (shell, factory) = makeShell(plans: [
            .camera: [CommercialRoutePlan(gate: deactivationGate)]
        ])
        let cameraRoute = try XCTUnwrap(factory.route(for: .camera))

        let releaseTask = Task { @MainActor in
            await shell.releaseAndWait()
        }
        await cameraRoute.deactivationStarted.wait()
        deactivationGate.open()

        let result = await releaseTask.value
        XCTAssertEqual(result, .released)
        XCTAssertEqual(cameraRoute.deactivationCallCount, 1)
        XCTAssertNil(shell.activeRoute)
        XCTAssertNil(shell.activeViewController)
        XCTAssertTrue(shell.children.isEmpty)
        XCTAssertFalse(modeControlButton(in: shell).isUserInteractionEnabled)
    }

    func testContainerTeardownSuppressesStalePendingSelection() async throws {
        let deactivationGate = CommercialTestGate()
        let (shell, factory) = makeShell(plans: [
            .camera: [CommercialRoutePlan(gate: deactivationGate)]
        ])
        let cameraRoute = try XCTUnwrap(factory.route(for: .camera))

        shell.select(.scenes)
        await cameraRoute.deactivationStarted.wait()
        shell.select(.history)

        let releaseTask = Task { @MainActor in
            await shell.releaseAndWait()
        }
        while !shell.isTearingDown {
            await Task.yield()
        }

        deactivationGate.open()
        let result = await releaseTask.value

        XCTAssertEqual(result, .released)
        XCTAssertEqual(factory.constructedSections, [.camera])
        XCTAssertNil(factory.route(for: .scenes))
        XCTAssertNil(factory.route(for: .history))
        XCTAssertTrue(shell.children.isEmpty)
        XCTAssertEqual(shell.selectedSection, .camera)
        XCTAssertEqual(shell.modeControl.renderedSection, .camera)
    }

    private func makeShell(
        plans: [CommercialSection: [CommercialRoutePlan]] = [:]
    ) -> (CommercialShellViewController, CommercialShellFactorySpy) {
        let factory = CommercialShellFactorySpy(plans: plans)
        let shell = CommercialShellViewController { section in
            factory.makeRoute(for: section)
        }
        shell.loadViewIfNeeded()
        return (shell, factory)
    }

    private func modeControlButtons(in shell: CommercialShellViewController) -> [UIButton] {
        allViews(in: shell.modeControl)
            .compactMap { $0 as? UIButton }
            .filter {
                $0.accessibilityIdentifier == "commercial-shell-open-scenes"
                    || $0.accessibilityIdentifier == "commercial-shell-return-camera"
            }
    }

    private func modeControlButton(
        in shell: CommercialShellViewController,
        identifier: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> UIButton {
        guard let button = modeControlButtons(in: shell).first(where: { identifier == nil || $0.accessibilityIdentifier == identifier }) else {
            XCTFail("Missing shell mode control", file: file, line: line)
            return UIButton(type: .system)
        }
        return button
    }

    private func allViews(in root: UIView) -> [UIView] {
        [root] + root.subviews.flatMap(allViews)
    }
}

private struct CommercialRoutePlan {
    let gate: CommercialTestGate?
    let result: CommercialRouteDeactivationResult

    init(
        gate: CommercialTestGate? = nil,
        result: CommercialRouteDeactivationResult = .released
    ) {
        self.gate = gate
        self.result = result
    }
}

@MainActor
private final class CommercialShellFactorySpy {
    private var plans: [CommercialSection: [CommercialRoutePlan]]
    private var nextID = 0

    private(set) var constructedSections: [CommercialSection] = []
    private(set) var events: [CommercialRouteEvent] = []
    private(set) var routes: [CommercialTestRoute] = []

    init(plans: [CommercialSection: [CommercialRoutePlan]]) {
        self.plans = plans
    }

    func makeRoute(for section: CommercialSection) -> CommercialTestRoute {
        let plan: CommercialRoutePlan
        var sectionPlans = plans[section] ?? []
        if sectionPlans.isEmpty {
            plan = CommercialRoutePlan()
        } else {
            plan = sectionPlans.removeFirst()
            plans[section] = sectionPlans
        }

        nextID += 1
        let route = CommercialTestRoute(
            id: nextID,
            section: section,
            deactivationGate: plan.gate,
            deactivationResult: plan.result,
            eventSink: { [weak self] event in
                self?.events.append(event)
            }
        )
        routes.append(route)
        constructedSections.append(section)
        events.append(.constructed(section, route.id))
        return route
    }

    func route(for section: CommercialSection) -> CommercialTestRoute? {
        routes.first { $0.section == section }
    }
}

@MainActor
private final class CommercialTestRoute: CommercialRoute {
    let id: Int
    let section: CommercialSection
    let viewController: UIViewController
    let deactivationStarted = CommercialTestGate()

    private let deactivationGate: CommercialTestGate?
    private let deactivationResult: CommercialRouteDeactivationResult
    private let eventSink: @MainActor (CommercialRouteEvent) -> Void

    private(set) var deactivationCallCount = 0
    private(set) var didFinishDeactivation = false

    init(
        id: Int,
        section: CommercialSection,
        deactivationGate: CommercialTestGate?,
        deactivationResult: CommercialRouteDeactivationResult,
        eventSink: @escaping @MainActor (CommercialRouteEvent) -> Void
    ) {
        self.id = id
        self.section = section
        self.deactivationGate = deactivationGate
        self.deactivationResult = deactivationResult
        self.eventSink = eventSink
        self.viewController = CommercialLifecycleViewController(label: "route-\(id)")
    }

    func deactivateAndWait() async -> CommercialRouteDeactivationResult {
        deactivationCallCount += 1
        eventSink(.deactivationStarted(section, id))
        deactivationStarted.open()

        if let deactivationGate {
            await deactivationGate.wait()
        }

        didFinishDeactivation = true
        eventSink(.deactivationFinished(section, id))
        return deactivationResult
    }
}

private enum CommercialRouteEvent: Equatable {
    case constructed(CommercialSection, Int)
    case deactivationStarted(CommercialSection, Int)
    case deactivationFinished(CommercialSection, Int)
}

@MainActor
private final class CommercialLifecycleViewController: UIViewController {
    enum LifecycleEvent: Equatable {
        case willMoveToParent
        case didMoveToParent
        case willMoveToNil
        case didMoveToNil
    }

    let label: String
    private(set) var lifecycleEvents: [LifecycleEvent] = []

    init(label: String) {
        self.label = label
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CommercialLifecycleViewController does not support storyboard construction")
    }

    override func willMove(toParent parent: UIViewController?) {
        lifecycleEvents.append(parent == nil ? .willMoveToNil : .willMoveToParent)
        super.willMove(toParent: parent)
    }

    override func didMove(toParent parent: UIViewController?) {
        lifecycleEvents.append(parent == nil ? .didMoveToNil : .didMoveToParent)
        super.didMove(toParent: parent)
    }
}

private final class CommercialTestGate: @unchecked Sendable {
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

    deinit {
        open()
    }
}

private struct CameraARInteropFixture {
    let runner: CameraARInteropSessionRunner
    let manager: CameraManager
    let viewModel: CameraViewModel
}

private final class CameraARInteropSessionRunner: CameraSessionRunner {
    private let lock = NSLock()
    private var running = false
    private var starts = 0
    private var stops = 0
    private var stopWasAllowed = false
    private let stopCompletion = DispatchSemaphore(value: 0)

    let startCompleted = CommercialTestGate()
    let stopStarted = CommercialTestGate()

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

    func startRunning() {
        lock.lock()
        starts += 1
        running = true
        lock.unlock()
        startCompleted.open()
    }

    func stopRunning() {
        lock.lock()
        stops += 1
        running = false
        lock.unlock()

        stopStarted.open()
        stopCompletion.wait()
    }

    func allowStop() {
        lock.lock()
        guard !stopWasAllowed else {
            lock.unlock()
            return
        }
        stopWasAllowed = true
        lock.unlock()
        stopCompletion.signal()
    }

    deinit {
        allowStop()
    }
}

private final class CameraARInteropRuntime: ARSessionRuntime {
    private let identity = NSObject()
    private let lock = NSLock()
    private var storedRunCount = 0
    private var storedPauseCount = 0

    var sessionIdentifier: ObjectIdentifier { ObjectIdentifier(identity) }
    let videoFormatFramesPerSecond: Int? = 60
    weak var delegate: ARSessionDelegate?

    var runCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedRunCount
    }

    var pauseCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedPauseCount
    }

    func run(_ configuration: ARConfiguration, options: ARSession.RunOptions) {
        lock.lock()
        storedRunCount += 1
        lock.unlock()
    }

    func pause() {
        lock.lock()
        storedPauseCount += 1
        lock.unlock()
    }
}

private struct CameraARInteropCapabilities: ARWorldTrackingCapabilityProviding {
    let evidence = ARWorldTrackingCapabilityEvidence(
        supportsWorldTracking: true,
        supportsHorizontalPlaneDetection: true,
        supportsGravityAlignment: true,
        supportsSmoothedSceneDepth: false,
        supportsSceneDepth: false
    )
}

@MainActor
private final class CameraARInteropWorkspaceViewController: UIViewController,
    @MainActor SceneWorkspaceHostingControllerProviding {
    var sceneWorkspaceTeardownProvider: (any SceneWorkspaceTeardownProviding)?
}

@MainActor
private func makeCameraARInteropFixture() -> CameraARInteropFixture {
    let scheduler = RealtimeScheduler()
    let thermalGovernor = ThermalGovernor(
        thermalStateProvider: { .nominal },
        batteryLevelProvider: { 1.0 }
    )
    let runner = CameraARInteropSessionRunner()
    let manager = CameraManager(
        scheduler: scheduler,
        thermalGovernor: thermalGovernor,
        motionGate: MotionGate(startMotionUpdates: false),
        sessionRunner: runner,
        configuration: .ready,
        notificationCenter: NotificationCenter()
    )
    let pipeline = AnalysisPipeline(
        reasoningProvider: nil,
        visualEvidenceProvider: nil,
        neuralEvidenceService: nil,
        thermalGovernor: thermalGovernor,
        neuralHeavyModelsEnabledProvider: { true },
        liveHybridFusionEnabled: false,
        demoLiveCoachEnabled: false
    )
    return CameraARInteropFixture(
        runner: runner,
        manager: manager,
        viewModel: CameraViewModel(cameraManager: manager, analysisPipeline: pipeline)
    )
}
