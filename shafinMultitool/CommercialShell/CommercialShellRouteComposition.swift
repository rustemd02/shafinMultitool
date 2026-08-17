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
                cameraViewModel: dependencies.viewModel
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

    private let stopAndWait: StopAndWait
    private var deactivationTask: Task<Void, Never>?

    init(viewController: UIViewController, cameraViewModel: CameraViewModel) {
        self.stopAndWait = { await cameraViewModel.stopAndWait() }
        super.init(viewController: viewController)
    }

    init(viewController: UIViewController, stopAndWait: @escaping StopAndWait) {
        self.stopAndWait = stopAndWait
        super.init(viewController: viewController)
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
    }

    let deactivationBlockReason: DeactivationBlockReason = .sceneWorkspaceTeardownIsNotAwaitable
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
        guard navigationController.viewControllers.count == 1,
              navigationController.viewControllers.first === sceneLibraryRootViewController,
              !hasPresentedControllerInRoute
        else {
            // The existing Scene Mode workspace owns AR and persistence cleanup, but it
            // exposes no awaitable release boundary in this slice. Keep the route active
            // rather than claiming that those resources have been released.
            return .blocked
        }

        // The library root owns no AR/session or saved-project workspace, so it can
        // safely release to the Camera route.
        return .released
    }

    private var hasPresentedControllerInRoute: Bool {
        navigationController.presentedViewController != nil
            || navigationController.viewControllers.contains {
                $0.presentedViewController != nil
            }
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
    let emptyStateMessage = "Completed coaching results will appear here."

    private let titleLabel = UILabel()
    private let messageLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "commercial-history-empty"

        titleLabel.text = "History"
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center

        messageLabel.text = emptyStateMessage
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.textColor = .secondaryLabel
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
