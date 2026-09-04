import Foundation
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
