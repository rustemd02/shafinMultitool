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

    private(set) var isTearingDown = false
    public private(set) var selectedSection: CommercialSection = .camera
    public private(set) var isTransitioning = false

    /// The system tab bar used to select the active route.
    public private(set) var tabBar = UITabBar()

    /// The route currently retained by the shell, if one has been installed.
    public var activeRoute: (any CommercialRoute)? {
        activeRouteStorage
    }

    /// The single child currently contained by the shell.
    public var activeViewController: UIViewController? {
        activeChildStorage
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
        rootView.backgroundColor = .systemBackground
        view = rootView
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        configureTabBar()

        // A container that has already been released must never resurrect a route when
        // UIKit later loads its view.
        guard !isTearingDown else {
            tabBar.isUserInteractionEnabled = false
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
        tabBar.isUserInteractionEnabled = false
        tabBar.selectedItem = item(for: selectedSection)

        // Cancellation prevents a pending selection from becoming active, while the
        // transition still awaits the route's own deactivation boundary.
        transitionTask?.cancel()
        let pendingTransition = transitionTask
        await pendingTransition?.value

        var result = lastTransitionResult
        if let activeRoute = activeRouteStorage {
            result = await activeRoute.deactivateAndWait()
            lastTransitionResult = result
            removeActiveRoute()
        }

        isTransitioning = false
        tabBar.isUserInteractionEnabled = false
        tabBar.selectedItem = item(for: selectedSection)
        return result
    }

    private func configureTabBar() {
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.delegate = self
        tabBar.items = CommercialSection.allCases.map { section in
            UITabBarItem(title: title(for: section),
                         image: image(for: section),
                         tag: section.rawValue)
        }
        tabBar.selectedItem = item(for: .camera)
        tabBar.accessibilityIdentifier = "commercial-shell-tab-bar"

        view.addSubview(tabBar)
        NSLayoutConstraint.activate([
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func requestSelection(_ section: CommercialSection) {
        guard !isTearingDown else { return }

        guard isViewLoaded else {
            requestedSectionBeforeLoad = section
            return
        }

        if isTransitioning {
            // UIKit normally updates selectedItem before calling its delegate. Keep the
            // visual selection aligned with the still-active route and retain only the
            // last request made during deactivation.
            pendingSection = section
            tabBar.selectedItem = item(for: selectedSection)
            return
        }

        guard section != selectedSection else {
            tabBar.selectedItem = item(for: selectedSection)
            return
        }

        pendingSection = nil
        isTransitioning = true
        tabBar.isUserInteractionEnabled = false
        tabBar.selectedItem = item(for: selectedSection)

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
            removeActiveRoute()
            finishTransition()
            return
        }

        // A blocked route remains the active owner. The old child and tab selection are
        // deliberately left untouched so the caller can retry or recover in place.
        guard result == .released else {
            pendingSection = nil
            tabBar.selectedItem = item(for: selectedSection)
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
        tabBar.selectedItem = item(for: finalSection)
        finishTransition()
    }

    private func finishTransition() {
        transitionTask = nil
        isTransitioning = false
        tabBar.isUserInteractionEnabled = !isTearingDown
    }

    private func installRoute(for section: CommercialSection) {
        precondition(activeRouteStorage == nil && activeChildStorage == nil,
                     "Commercial shell can contain only one active route")

        let route = routeFactory(section)
        let child = route.viewController

        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(child.view, belowSubview: tabBar)
        NSLayoutConstraint.activate([
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            child.view.topAnchor.constraint(equalTo: view.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: tabBar.topAnchor)
        ])
        child.didMove(toParent: self)

        activeRouteStorage = route
        activeChildStorage = child
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
    }

    private func item(for section: CommercialSection) -> UITabBarItem? {
        tabBar.items?.first { $0.tag == section.rawValue }
    }

    private func title(for section: CommercialSection) -> String {
        switch section {
        case .camera:
            return "Camera"
        case .scenes:
            return "Scenes"
        case .history:
            return "History"
        }
    }

    private func image(for section: CommercialSection) -> UIImage? {
        switch section {
        case .camera:
            return UIImage(systemName: "camera")
        case .scenes:
            return UIImage(systemName: "square.stack.3d.up")
        case .history:
            return UIImage(systemName: "clock")
        }
    }
}

extension CommercialShellViewController: UITabBarDelegate {
    public func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        guard let section = CommercialSection(rawValue: item.tag) else { return }
        requestSelection(section)
    }
}
