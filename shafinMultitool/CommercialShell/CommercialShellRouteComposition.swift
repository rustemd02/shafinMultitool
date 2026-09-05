import Combine
import SwiftUI
import UIKit

/// The production route composition boundary for the commercial shell.
///
/// Builders are injected here so route wiring can be tested without introducing
/// runtime switches or replacing any route's existing owner.
@MainActor
struct CommercialShellComposition {
    typealias ViewControllerBuilder = @MainActor () -> UIViewController
    typealias CameraCoachRouteBuilder = @MainActor () -> CommercialCameraCoachRoute

    private let cameraCoachBuilder: CameraCoachRouteBuilder
    private let sceneLibraryBuilder: ViewControllerBuilder
    private let historyBuilder: ViewControllerBuilder

    init(
        cameraCoachBuilder: @escaping CameraCoachRouteBuilder = {
            let dependencies = ContentView.makeCameraCoachDependencies()
            let viewController = CommercialCameraCoachHostingController(
                rootView: ContentView(dependencies: dependencies)
            )
            return CommercialCameraCoachRoute(
                viewController: viewController,
                cameraViewModel: dependencies.viewModel,
                entryFlowModel: dependencies.entryFlowModel
            )
        },
        sceneLibraryBuilder: @escaping ViewControllerBuilder = {
            SOModuleBuilder.build()
        },
        historyBuilder: @escaping ViewControllerBuilder = {
            CommercialHistoryEmptyViewController()
        }
    ) {
        self.cameraCoachBuilder = cameraCoachBuilder
        self.sceneLibraryBuilder = sceneLibraryBuilder
        self.historyBuilder = historyBuilder
    }

    func makeShell() -> CommercialShellViewController {
        let cameraCoachBuilder = self.cameraCoachBuilder
        let sceneLibraryBuilder = self.sceneLibraryBuilder
        let historyBuilder = self.historyBuilder

        let shell = CommercialShellViewController { section in
            switch section {
            case .camera:
                return cameraCoachBuilder()
            case .scenes:
                return CommercialSceneLibraryRoute(
                    sceneLibraryViewController: sceneLibraryBuilder()
                )
            case .history:
                return CommercialHistoryRoute(
                    viewController: historyBuilder()
                )
            }
        }
        shell.loadViewIfNeeded()
        return shell
    }
}

@MainActor
final class CommercialCameraCoachHostingController<Content: View>: UIHostingController<Content> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .all
    }
}

@MainActor
class CommercialViewControllerRoute: CommercialRoute {
    let viewController: UIViewController

    init(viewController: UIViewController) {
        self.viewController = viewController
    }

    func deactivateAndWait() async -> CommercialRouteDeactivationResult {
        // Routes with no asynchronous owner-specific cleanup can release at this
        // boundary. Routes with an owner must provide a concrete subclass boundary.
        .released
    }
}

@MainActor
final class CommercialCameraCoachRoute: CommercialViewControllerRoute {
    typealias StopAndWait = @MainActor () async -> Void
    typealias SceneBackgroundHandler = @MainActor () -> Void
    typealias ChromeVisibilityHandler = @MainActor (Bool) -> Void

    private let stopAndWait: StopAndWait
    private let sceneBackgroundHandler: SceneBackgroundHandler?
    private let entryFlowModel: CameraCoachEntryFlowModel?
    private var chromeVisibilityHandler: ChromeVisibilityHandler?
    private var entryFlowObservation: AnyCancellable?
    private var deactivationTask: Task<Void, Never>?

    init(
        viewController: UIViewController,
        cameraViewModel: CameraViewModel,
        entryFlowModel: CameraCoachEntryFlowModel? = nil
    ) {
        // A route handoff must release the complete Camera Coach owner before
        // the shell constructs a Scene route. `releaseAndWait()` joins the
        // ViewModel's shared stop → pipeline release → AVCapture release
        // operation; stopping frame delivery alone leaves the AVCapture
        // configuration owner alive beside the incoming ARSession.
        self.stopAndWait = { await cameraViewModel.releaseAndWait() }
        self.sceneBackgroundHandler = { [weak cameraViewModel] in
            cameraViewModel?.reportSceneInactive()
        }
        self.entryFlowModel = entryFlowModel
        super.init(viewController: viewController)
    }

    init(
        viewController: UIViewController,
        stopAndWait: @escaping StopAndWait,
        entryFlowModel: CameraCoachEntryFlowModel? = nil,
        sceneDidEnterBackground: SceneBackgroundHandler? = nil
    ) {
        self.stopAndWait = stopAndWait
        self.sceneBackgroundHandler = sceneDidEnterBackground
        self.entryFlowModel = entryFlowModel
        super.init(viewController: viewController)
    }

    func setChromeVisibilityHandler(_ handler: @escaping ChromeVisibilityHandler) {
        chromeVisibilityHandler = handler
        entryFlowObservation?.cancel()

        guard let entryFlowModel else {
            handler(true)
            return
        }

        handler(entryFlowModel.phase == .ready)
        entryFlowObservation = entryFlowModel.$phase.sink { [weak self] phase in
            self?.chromeVisibilityHandler?(phase == .ready)
        }
    }

    func handleAppDidBecomeActive() {
        guard let entryFlowModel,
              entryFlowModel.phase != .ready else { return }

        Task { @MainActor [weak self] in
            guard let self,
                  let entryFlowModel = self.entryFlowModel,
                  entryFlowModel.phase != .ready else { return }
            await entryFlowModel.recheckCameraAccess()
        }
    }

    /// M1-004 lifecycle-adapter background hook. Forwards to the active capture
    /// owner; the owner (CameraViewModel.reportSceneInactive) is idempotent and
    /// early-returns unless capture or pause work is active, so a racing SwiftUI
    /// scenePhase effect converges on the same single state change.
    func handleSceneDidEnterBackground() {
        sceneBackgroundHandler?()
    }

    override func deactivateAndWait() async -> CommercialRouteDeactivationResult {
        if let deactivationTask {
            await deactivationTask.value
            return .released
        }

        let stopAndWait = self.stopAndWait
        let task = Task { @MainActor in
            await stopAndWait()
        }
        deactivationTask = task
        await task.value
        return .released
    }
}

@MainActor
final class CommercialSceneLibraryRoute: CommercialViewControllerRoute {
    enum DeactivationBlockReason: Equatable, Sendable {
        case sceneWorkspaceTeardownIsNotAwaitable
        case sceneWorkspaceTeardownFailed(SceneWorkspaceTeardownFailure)
    }

    private(set) var deactivationBlockReason: DeactivationBlockReason = .sceneWorkspaceTeardownIsNotAwaitable
    private(set) var lastSceneWorkspaceTeardownResult: SceneWorkspaceTeardownResult?
    let navigationController: UINavigationController
    private let sceneLibraryRootViewController: UIViewController
    private let interactivePopGuard: CommercialNavigationInteractivePopGuard

    init(sceneLibraryViewController: UIViewController) {
        let navigationController = CommercialSceneNavigationController(
            rootViewController: sceneLibraryViewController
        )
        navigationController.navigationBar.isHidden = true

        let interactivePopGuard = CommercialNavigationInteractivePopGuard()
        self.navigationController = navigationController
        self.sceneLibraryRootViewController = sceneLibraryViewController
        self.interactivePopGuard = interactivePopGuard
        super.init(viewController: navigationController)

        interactivePopGuard.navigationController = navigationController
        navigationController.interactivePopGestureRecognizer?.delegate = interactivePopGuard
    }

    override func deactivateAndWait() async -> CommercialRouteDeactivationResult {
        guard !hasPresentedControllerInRoute else { return .blocked }
        guard navigationController.viewControllers.count > 1 else {
            // The library root owns no AR/session or saved-project workspace.
            lastSceneWorkspaceTeardownResult = nil
            return .released
        }

        guard let workspaceProvider = currentSceneWorkspaceProvider else {
            deactivationBlockReason = .sceneWorkspaceTeardownIsNotAwaitable
            lastSceneWorkspaceTeardownResult = .blocked(.workspaceOwnerUnavailable)
            return .blocked
        }

        let result = await workspaceProvider.teardownAndWait()
        lastSceneWorkspaceTeardownResult = result
        switch result {
        case .released:
            navigationController.setViewControllers([sceneLibraryRootViewController], animated: false)
            return .released
        case .blocked(let failure):
            deactivationBlockReason = .sceneWorkspaceTeardownFailed(failure)
            return .blocked
        }
    }

    /// Explicit scene-owned background hook. The workspace owns the one teardown
    /// operation; the route can await the same result without a global app delegate.
    func handleDidEnterBackground() async -> CommercialRouteDeactivationResult {
        guard !hasPresentedControllerInRoute else { return .blocked }
        guard let workspaceProvider = currentSceneWorkspaceProvider else {
            return navigationController.viewControllers.count > 1 ? .blocked : .released
        }

        let result = await workspaceProvider.teardownAndWait()
        lastSceneWorkspaceTeardownResult = result
        switch result {
        case .released:
            return .released
        case .blocked(let failure):
            deactivationBlockReason = .sceneWorkspaceTeardownFailed(failure)
            return .blocked
        }
    }

    private var hasPresentedControllerInRoute: Bool {
        navigationController.presentedViewController != nil
            || navigationController.viewControllers.contains {
                $0.presentedViewController != nil
            }
    }

    private var currentSceneWorkspaceProvider: (any SceneWorkspaceTeardownProviding)? {
        guard let hostingController = navigationController.topViewController
                as? SceneWorkspaceHostingControllerProviding else {
            return nil
        }
        return hostingController.sceneWorkspaceTeardownProvider
    }
}

/// Scene Mode keeps its fixed 16:9 workspace in landscape while the application
/// target remains free to expose portrait for Camera Coach.
@MainActor
final class CommercialSceneNavigationController: UINavigationController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .landscape
    }
}

@MainActor
final class CommercialHistoryRoute: CommercialViewControllerRoute {}

/// Keeps Scene Mode's existing interactive-pop ownership with its navigation route.
final class CommercialNavigationInteractivePopGuard: NSObject, UIGestureRecognizerDelegate {
    weak var navigationController: UINavigationController?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigationController,
              gestureRecognizer === navigationController.interactivePopGestureRecognizer
        else { return true }

        guard navigationController.viewControllers.count > 1 else { return false }

        if let topController = navigationController.topViewController as? InteractivePopGestureControlling,
           topController.disablesInteractivePopGesture {
            return false
        }

        return true
    }
}

@MainActor
final class CommercialHistoryEmptyViewController: UIViewController {
    let isEmptyState = true
    let persistenceAction: (() -> Void)? = nil
    let emptyStateTitle = "История"
    let emptyStateMessage = "Завершённые разборы этой сессии появятся здесь."

    private let titleLabel = UILabel()
    private let messageLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = CommercialShellModeControl.surfaceColor
        view.accessibilityIdentifier = "commercial-history-empty"

        titleLabel.text = emptyStateTitle
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center

        messageLabel.text = emptyStateMessage
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = .white.withAlphaComponent(0.72)
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [titleLabel, messageLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
