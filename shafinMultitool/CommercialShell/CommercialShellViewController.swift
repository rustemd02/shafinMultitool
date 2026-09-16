import UIKit

/// The routes exposed by the commercial shell.
public enum CommercialSection: Int, CaseIterable, Hashable, Sendable {
    case camera
    case scenes
    case history
}

/// The result of asking a route to stop its work before it is replaced.
public enum CommercialRouteDeactivationResult: Equatable, Sendable {
    case released
    case blocked
}

/// A compatibility name for callers that describe route deactivation as teardown.
public typealias CommercialRouteTeardownResult = CommercialRouteDeactivationResult

/// One route owned by ``CommercialShellViewController``.
@MainActor
public protocol CommercialRoute: AnyObject {
    typealias DeactivationResult = CommercialRouteDeactivationResult

    var viewController: UIViewController { get }
    func deactivateAndWait() async -> CommercialRouteDeactivationResult
}

/// Constructs a route only when the shell makes that section active.
public typealias CommercialRouteFactory = @MainActor (_ section: CommercialSection) -> any CommercialRoute

/// A camera-first, single-active-route UIKit container.
@MainActor
public final class CommercialShellViewController: UIViewController {
    public typealias RouteFactory = CommercialRouteFactory

    private let routeFactory: CommercialRouteFactory
    private var activeRouteStorage: (any CommercialRoute)?
    private var activeChildStorage: UIViewController?
    private var transitionTask: Task<Void, Never>?
    private var releaseTask: Task<CommercialRouteDeactivationResult?, Never>?
    private var pendingSection: CommercialSection?
    private var requestedSectionBeforeLoad: CommercialSection?
    private var lastTransitionResult: CommercialRouteDeactivationResult?
    private let selectionFeedbackGenerator = UISelectionFeedbackGenerator()
    private var cameraCoachChromeVisible = true

    private(set) var isTearingDown = false
    public private(set) var selectedSection: CommercialSection = .camera
    public private(set) var isTransitioning = false

    /// The visual mode control; route truth remains owned by this shell.
    private(set) var modeControl = CommercialShellModeControl()

    /// The route currently retained by the shell, if one has been installed.
    /// M7-015: UIKit background task lease covering the background lifecycle
    /// dispatch. `.invalid` means no live lease.
    private var backgroundTaskIDs: Set<UIBackgroundTaskIdentifier> = []
    var backgroundTaskCoordinator: SceneBackgroundTaskCoordinating = UIKitSceneBackgroundTaskCoordinator()

    public var activeRoute: (any CommercialRoute)? {
        activeRouteStorage
    }

    /// The single child currently contained by the shell.
    public var activeViewController: UIViewController? {
        activeChildStorage
    }

    func handleAppDidBecomeActive() {
        guard selectedSection == .camera else { return }
        (activeRouteStorage as? CommercialCameraCoachRoute)?.handleAppDidBecomeActive()
    }

    /// M1-004 LifecycleCoordinatorOwner adapter: exactly one forwarding per app
    /// lifecycle event, reaching only the active route owner. SceneDelegate is
    /// the single UIKit entry point; SwiftUI scenePhase effects converge on the
    /// same idempotent owners (reportSceneInactive guard, single-flight
    /// workspace teardown) rather than owning the event.
    func handleSceneDidEnterBackground() {
        // M7-015: an in-flight recording finalize needs CPU time after the
        // app backgrounds. One UIKit background task covers the whole
        // lifecycle dispatch; expiration (or dispatch completion) ends it
        // exactly once. The serialized owners make the flushed work itself
        // idempotent, so expiration mid-dispatch cannot double-finalize.
        let taskID = backgroundTaskCoordinator.begin(withName: "set-scene-background-flush")
        if taskID != .invalid { backgroundTaskIDs.insert(taskID) }
        let finish = { [weak self] in
            self?.endBackgroundTask(taskID)
        }
        if let cameraRoute = activeRouteStorage as? CommercialCameraCoachRoute {
            Task { @MainActor in
                await cameraRoute.handleSceneDidEnterBackground()
                finish()
            }
        } else if let scenesRoute = activeRouteStorage as? CommercialSceneLibraryRoute {
            Task { @MainActor in
                _ = await scenesRoute.handleDidEnterBackground()
                finish()
            }
        } else {
            finish()
        }
    }

    private func endBackgroundTask(_ taskID: UIBackgroundTaskIdentifier) {
        guard taskID != .invalid, backgroundTaskIDs.remove(taskID) != nil else { return }
        backgroundTaskCoordinator.end(taskID)
    }

    /// UIKit asks the container for the orientations supported by the currently
    /// visible route. Before the first route is installed, keep Camera Coach's
    /// portrait-and-landscape launch policy.
    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        activeViewController?.supportedInterfaceOrientations ?? .all
    }

    public init(routeFactory: @escaping CommercialRouteFactory) {
        self.routeFactory = routeFactory
        super.init(nibName: nil, bundle: nil)
    }

    /// A shorter initializer label for callers that model the dependency as a factory.
    public convenience init(factory: @escaping CommercialRouteFactory) {
        self.init(routeFactory: factory)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CommercialShellViewController does not support storyboard construction")
    }

    public override func loadView() {
        let rootView = UIView()
        rootView.backgroundColor = CommercialShellModeControl.surfaceColor
        rootView.accessibilityIdentifier = "commercial-shell"
        view = rootView
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        configureModeControl()

        // A container that has already been released must never resurrect a route when
        // UIKit later loads its view.
        guard !isTearingDown else {
            renderSectionChrome()
            return
        }

        // Camera is the only eager route. Secondary routes are constructed only after
        // the current route has completed asynchronous deactivation.
        installRoute(for: .camera)

        let requestedSection = requestedSectionBeforeLoad
        requestedSectionBeforeLoad = nil
        if let requestedSection, requestedSection != .camera {
            requestSelection(requestedSection)
        }
    }

    /// Requests a section change. Requests received during teardown are coalesced to the
    /// most recent section and applied after the current route has released.
    public func select(_ section: CommercialSection) {
        requestSelection(section)
    }

    public func select(section: CommercialSection) {
        requestSelection(section)
    }

    /// Waits for the currently scheduled route switch, if any.
    public func waitForTransition() async {
        let task = transitionTask
        await task?.value
    }

    /// Requests a section and waits for the transition started by that request.
    public func selectAndWait(_ section: CommercialSection) async {
        requestSelection(section)
        await waitForTransition()
    }

    /// Releases the active route and permanently tears down the container.
    @discardableResult
    public func deactivateAndWait() async -> CommercialRouteDeactivationResult? {
        await releaseAndWait()
    }

    /// Releases the active route and permanently tears down the container.
    ///
    /// All callers share the same async teardown operation. This matters when a parent
    /// starts cleanup while a transition is already waiting for route deactivation.
    @discardableResult
    public func releaseAndWait() async -> CommercialRouteDeactivationResult? {
        if let releaseTask {
            return await releaseTask.value
        }

        let task: Task<CommercialRouteDeactivationResult?, Never> = Task { @MainActor [weak self] in
            guard let self else { return nil }
            return await self.performRelease()
        }
        releaseTask = task
        return await task.value
    }

    /// Alias used by container owners that name lifecycle cleanup as teardown.
    @discardableResult
    public func teardownAndWait() async -> CommercialRouteDeactivationResult? {
        await releaseAndWait()
    }

    private func performRelease() async -> CommercialRouteDeactivationResult? {
        isTearingDown = true
        pendingSection = nil
        requestedSectionBeforeLoad = nil
        renderSectionChrome()

        // Cancellation prevents a pending selection from becoming active, while the
        // transition still awaits the route's own deactivation boundary.
        transitionTask?.cancel()
        let pendingTransition = transitionTask
        await pendingTransition?.value

        var result = lastTransitionResult
        if let activeRoute = activeRouteStorage {
            result = await activeRoute.deactivateAndWait()
            lastTransitionResult = result
            if result == .released {
                removeActiveRoute()
            } else {
                // A blocked route still owns its child. Re-open the shell so the
                // owner can remain visible instead of being discarded unsafely.
                isTearingDown = false
            }
        }

        isTransitioning = false
        renderSectionChrome()
        return result
    }

    private func configureModeControl() {
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.onIntentRequested = { [weak self] intent in
            switch intent {
            case .openScenes:
                self?.requestSelection(.scenes)
            case .returnCamera:
                self?.requestSelection(.camera)
            }
        }

        view.addSubview(modeControl)
        NSLayoutConstraint.activate([
            modeControl.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            modeControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: SETSpacing.x4),
            modeControl.widthAnchor.constraint(equalToConstant: SETABRollCapsuleContract.minimumControlSize.width),
            modeControl.heightAnchor.constraint(equalToConstant: SETABRollCapsuleContract.minimumControlSize.height)
        ])
    }

    private func requestSelection(_ section: CommercialSection) {
        guard !isTearingDown else { return }

        guard isViewLoaded else {
            requestedSectionBeforeLoad = section
            return
        }

        if isTransitioning {
            // Keep visual selection aligned with the still-active route and retain only
            // the last request made during deactivation.
            pendingSection = section
            renderSectionChrome()
            return
        }

        guard section != selectedSection else {
            renderSectionChrome()
            return
        }

        emitSelectionFeedback()
        pendingSection = nil
        isTransitioning = true
        renderSectionChrome()

        transitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performTransition(to: section)
        }
    }

    private func performTransition(to requestedSection: CommercialSection) async {
        guard let oldRoute = activeRouteStorage else {
            finishTransition()
            return
        }

        let result = await oldRoute.deactivateAndWait()
        lastTransitionResult = result

        // Container teardown owns cleanup and suppresses every pending activation,
        // including a request coalesced while route deactivation was in flight.
        guard !isTearingDown else {
            if result == .released {
                removeActiveRoute()
            }
            finishTransition()
            return
        }

        // A blocked route remains the active owner. The old child and mode state are
        // deliberately left untouched so the caller can retry or recover in place.
        guard result == .released else {
            pendingSection = nil
            finishTransition()
            return
        }

        removeActiveRoute()

        // Any requests received during deactivation collapse into exactly one final
        // construction after the old route has released and been removed.
        let finalSection = pendingSection ?? requestedSection
        pendingSection = nil
        installRoute(for: finalSection)
        selectedSection = finalSection
        finishTransition()
    }

    private func finishTransition() {
        transitionTask = nil
        isTransitioning = false
        renderSectionChrome()
    }

    private func renderSectionChrome() {
        let modeControlVisible = selectedSection != .camera || cameraCoachChromeVisible
        modeControl.isHidden = !modeControlVisible
        modeControl.isUserInteractionEnabled = modeControlVisible
        modeControl.accessibilityElementsHidden = !modeControlVisible
        modeControl.render(
            selectedSection: selectedSection,
            isInteractionLocked: isTearingDown || isTransitioning || !modeControlVisible
        )
    }

    private func emitSelectionFeedback() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        selectionFeedbackGenerator.prepare()
        selectionFeedbackGenerator.selectionChanged()
    }

    private func installRoute(for section: CommercialSection) {
        precondition(activeRouteStorage == nil && activeChildStorage == nil,
                     "Commercial shell can contain only one active route")

        let route = routeFactory(section)
        let child = route.viewController

        if let cameraRoute = route as? CommercialCameraCoachRoute {
            cameraRoute.setChromeVisibilityHandler { [weak self] isVisible in
                self?.cameraCoachChromeVisible = isVisible
                self?.renderSectionChrome()
            }
        } else {
            cameraCoachChromeVisible = true
        }

        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(child.view, belowSubview: modeControl)
        NSLayoutConstraint.activate([
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            child.view.topAnchor.constraint(equalTo: view.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        child.didMove(toParent: self)

        activeRouteStorage = route
        activeChildStorage = child
        setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    private func removeActiveRoute() {
        guard let child = activeChildStorage else {
            activeRouteStorage = nil
            return
        }

        child.willMove(toParent: nil)
        child.view.removeFromSuperview()
        child.removeFromParent()
        activeChildStorage = nil
        activeRouteStorage = nil
        setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}
