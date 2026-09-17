#if DEBUG
import SwiftUI
import UIKit

/// UI-test diagnostics for the UIKit-hosted SwiftUI lifecycle boundary. This
/// observes owner state and the exact window scene; it never changes capture.
struct CameraLifecycleDiagnosticProbe: UIViewRepresentable {
    let viewModel: CameraViewModel
    let cameraManager: CameraManager
    let swiftUIScenePhase: String

    func makeUIView(context: Context) -> CameraLifecycleDiagnosticView {
        CameraLifecycleDiagnosticView()
    }

    func updateUIView(_ view: CameraLifecycleDiagnosticView, context: Context) {
        view.viewModel = viewModel
        view.cameraManager = cameraManager
        view.swiftUIScenePhase = swiftUIScenePhase
    }
}

final class CameraLifecycleDiagnosticView: UIView {
    weak var viewModel: CameraViewModel?
    weak var cameraManager: CameraManager?
    var swiftUIScenePhase = "unavailable"

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityIdentifier = "camera_coach_lifecycle_diagnostic"
        accessibilityLabel = "Camera lifecycle diagnostic"
    }

    required init?(coder: NSCoder) { return nil }

    // SwiftUI may reuse the representable while the reference-valued input
    // objects mutate. Read the owners on the actual accessibility query, not
    // when updateUIView or a UIKit notification happened to run.
    override var accessibilityValue: String? {
        get { liveSnapshot() }
        set { }
    }

    private func liveSnapshot() -> String {
        let windowSceneState: String
        switch window?.windowScene?.activationState {
        case .foregroundActive: windowSceneState = "foregroundActive"
        case .foregroundInactive: windowSceneState = "foregroundInactive"
        case .background: windowSceneState = "background"
        case .unattached: windowSceneState = "unattached"
        case nil: windowSceneState = "noWindowScene"
        @unknown default: windowSceneState = "unknown"
        }
        return [
            "autBundle=\(Bundle.main.bundleIdentifier ?? "unreported")",
            "autPID=\(ProcessInfo.processInfo.processIdentifier)",
            "autSimulatorUDID=\(ProcessInfo.processInfo.environment["SIMULATOR_UDID"] ?? "unreported")",
            "autSimulatorDevice=\(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "unreported")",
            "viewModel=\(viewModel.map { String(describing: $0.lifecycleState) } ?? "unavailable")",
            "manager=\(cameraManager.map { String(describing: $0.lifecycleState) } ?? "unavailable")",
            "swiftUIPhase=\(swiftUIScenePhase)",
            "uiWindowScene=\(windowSceneState)",
            "deviceOrientation=\(UIDevice.current.orientation.rawValue)",
            "deviceEvents=\(UIDevice.current.isGeneratingDeviceOrientationNotifications)",
            "interfaceOrientation=\(window?.windowScene?.interfaceOrientation.rawValue ?? -1)",
            "explicitFixtureGeometry=\((window?.windowScene?.delegate as? SceneDelegate)?.uiTestingFixtureGeometryStatus ?? "unavailable")",
            "fixtureGeometryFailure=\((window?.windowScene?.delegate as? SceneDelegate)?.uiTestingFixtureGeometryFailureDetail ?? "none")",
            "sceneGeometry=\(sceneGeometrySnapshot())",
            "windowBounds=\(String(describing: window?.bounds))",
            "windowFrame=\(String(describing: window?.frame))",
            "windowTransform=\(String(describing: window?.transform))",
            "appOrientationMask=\(UIApplication.shared.supportedInterfaceOrientations(for: window).rawValue)",
            "controllers=\(controllerSnapshot(window?.rootViewController, depth: 0))",
            "avCaptureRunning=\(cameraManager.map { String($0.captureSession.isRunning) } ?? "unavailable")"
        ].joined(separator: ";")
    }

    private func sceneGeometrySnapshot() -> String {
        guard let scene = window?.windowScene else { return "noWindowScene" }
        var values = [
            "effectiveOrientation=\(scene.effectiveGeometry.interfaceOrientation.rawValue)",
            "screenBounds=\(scene.screen.bounds)",
            "screenNativeBounds=\(scene.screen.nativeBounds)",
            "sceneBounds=\(scene.coordinateSpace.bounds)",
            "sizeMinimum=\(String(describing: scene.sizeRestrictions?.minimumSize))",
            "sizeMaximum=\(String(describing: scene.sizeRestrictions?.maximumSize))"
        ]
        if #available(iOS 26.0, *) {
            values += [
                "orientationLocked=\(scene.effectiveGeometry.isInterfaceOrientationLocked)",
                "interactivelyResizing=\(scene.effectiveGeometry.isInteractivelyResizing)",
                "effectiveBounds=\(scene.effectiveGeometry.coordinateSpace.bounds)"
            ]
        }
        return values.joined(separator: ",")
    }

    private func controllerSnapshot(_ controller: UIViewController?, depth: Int) -> String {
        guard let controller else { return "none" }
        guard depth < 6 else { return "depthLimit" }
        let description = "\(String(describing: type(of: controller)))"
            + "[mask=\(controller.supportedInterfaceOrientations.rawValue)"
            + ",autorotate=\(controller.shouldAutorotate)"
            + ",preferred=\(controller.preferredInterfaceOrientationForPresentation.rawValue)"
            + ",bounds=\(String(describing: controller.viewIfLoaded?.bounds))]"
        let children = controller.children.map { controllerSnapshot($0, depth: depth + 1) }.joined(separator: "|")
        let presented = controller.presentedViewController.map { controllerSnapshot($0, depth: depth + 1) } ?? "none"
        return description + "{children=\(children);presented=\(presented)}"
    }
}
#endif
