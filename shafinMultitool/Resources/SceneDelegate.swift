//
//  SceneDelegate.swift
//  shafinMultitool
//
//  Created by Рустем on 25.04.2023.
//

import UIKit
import SwiftUI
#if DEBUG
import AVFoundation
#endif

#if DEBUG
private let uiTestingEnvironmentKey = "SHAFIN_UI_TESTING"
private let uiTestingCameraPermissionArgument = "-SHAFIN_CAMERA_PERMISSION_STATE"
private let uiTestingCameraIntroArgument = "-SHAFIN_CAMERA_INTRO_STATE"
#endif

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

#if DEBUG
    private static func makeUITestingRootViewController() -> UIViewController {
        let uiTestingConfiguration = CameraCoachUITestingConfiguration(
            arguments: ProcessInfo.processInfo.arguments
        )

        return CommercialShellComposition(
            cameraCoachBuilder: {
                let thermal = ThermalGovernor()
                let cameraManager = CameraManager(
                    scheduler: RealtimeScheduler(),
                    thermalGovernor: thermal,
                    motionGate: MotionGate(),
                    sessionRunner: AVCaptureSessionRunner(session: AVCaptureSession()),
                    configuration: .failure(.noWideCamera)
                )
                let analysisPipeline = AnalysisPipeline(
                    thermalGovernor: thermal,
                    neuralHeavyModelsEnabledProvider: {
                        thermal.nextBudget().heavyModelsEnabled
                    }
                )
                let dependencies = ContentView.CameraCoachDependencies(
                    cameraManager: cameraManager,
                    viewModel: CameraViewModel(
                        cameraManager: cameraManager,
                        analysisPipeline: analysisPipeline
                    ),
                    permissionClient: CameraCoachUITestingPermissionClient(
                        snapshot: uiTestingConfiguration.cameraSnapshot,
                        requestResult: uiTestingConfiguration.cameraRequestResult
                    ),
                    introStore: CameraCoachUITestingIntroStore(
                        initiallySeen: uiTestingConfiguration.introSeen
                    )
                )
                let viewController = CommercialCameraCoachHostingController(
                    rootView: ContentView(dependencies: dependencies)
                )
                return CommercialCameraCoachRoute(
                    viewController: viewController,
                    cameraViewModel: dependencies.viewModel
                )
            }
        ).makeShell()
    }

    static func makeRootViewController(
        benchmarkConfig: DeviceBenchmarkConfig?,
        benchmarkRootBuilder: @escaping (DeviceBenchmarkConfig) -> UIViewController,
        commercialRootBuilder: @escaping () -> UIViewController
    ) -> UIViewController {
        if let benchmarkConfig {
            return benchmarkRootBuilder(benchmarkConfig)
        }

        return commercialRootBuilder()
    }
#else
    static func makeRootViewController(
        commercialRootBuilder: @escaping () -> UIViewController
    ) -> UIViewController {
        commercialRootBuilder()
    }
#endif

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        let window = UIWindow(windowScene: windowScene)
        self.window = window
        window.backgroundColor = .black
#if DEBUG
        let isUITesting = ProcessInfo.processInfo.environment[uiTestingEnvironmentKey] == "1"
        let rootViewController = Self.makeRootViewController(
            benchmarkConfig: DeviceBenchmarkConfig.fromEnvironment(),
            benchmarkRootBuilder: { benchmarkConfig in
                UIHostingController(
                    rootView: DeviceBenchmarkRootView(config: benchmarkConfig, interactive: true)
                )
            },
            commercialRootBuilder: {
                if isUITesting {
                    return Self.makeUITestingRootViewController()
                }
                return CommercialShellComposition().makeShell()
            }
        )
#else
        let rootViewController = Self.makeRootViewController {
            CommercialShellComposition().makeShell()
        }
#endif
        window.rootViewController = rootViewController
        window.makeKeyAndVisible()
    }
}

#if DEBUG
private struct CameraCoachUITestingConfiguration {
    enum PermissionState: String {
        case notDetermined
        case authorized
        case denied
        case restricted
        case unavailable
        case unknown
    }

    let cameraSnapshot: PermissionSnapshot
    let cameraRequestResult: PermissionSnapshot
    let introSeen: Bool

    init(arguments: [String]) {
        let permissionState = Self.value(
            for: uiTestingCameraPermissionArgument,
            in: arguments
        ).flatMap(PermissionState.init(rawValue:)) ?? .authorized
        let availableSnapshot = Self.snapshot(for: permissionState)

        self.cameraSnapshot = availableSnapshot
        self.cameraRequestResult = permissionState == .notDetermined
            ? Self.snapshot(for: .authorized)
            : availableSnapshot
        self.introSeen = Self.value(
            for: uiTestingCameraIntroArgument,
            in: arguments
        ) != "notSeen"
    }

    private static func value(for argument: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: argument),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func snapshot(for state: PermissionState) -> PermissionSnapshot {
        switch state {
        case .notDetermined:
            return PermissionSnapshot(
                permission: .camera,
                authorization: .notDetermined,
                availability: .available
            )
        case .authorized:
            return PermissionSnapshot(
                permission: .camera,
                authorization: .authorized,
                availability: .available
            )
        case .denied:
            return PermissionSnapshot(
                permission: .camera,
                authorization: .denied,
                availability: .available
            )
        case .restricted:
            return PermissionSnapshot(
                permission: .camera,
                authorization: .restricted,
                availability: .available
            )
        case .unavailable:
            return PermissionSnapshot(
                permission: .camera,
                authorization: .authorized,
                availability: .unavailable(.cameraHardware)
            )
        case .unknown:
            return PermissionSnapshot(
                permission: .camera,
                authorization: .unknown,
                availability: .available
            )
        }
    }
}

private actor CameraCoachUITestingPermissionClient: PermissionClient {
    private let cameraSnapshot: PermissionSnapshot
    private let cameraRequestResult: PermissionSnapshot

    init(snapshot: PermissionSnapshot, requestResult: PermissionSnapshot) {
        self.cameraSnapshot = snapshot
        self.cameraRequestResult = requestResult
    }

    func snapshot(for permission: AppPermission) async -> PermissionSnapshot {
        permission == .camera
            ? cameraSnapshot
            : PermissionSnapshot(
                permission: permission,
                authorization: .unknown,
                availability: .available
            )
    }

    func request(_ permission: AppPermission) async -> PermissionSnapshot {
        permission == .camera
            ? cameraRequestResult
            : PermissionSnapshot(
                permission: permission,
                authorization: .unknown,
                availability: .available
            )
    }
}

private final class CameraCoachUITestingIntroStore: CameraCoachIntroStore {
    private var seen: Bool

    init(initiallySeen: Bool) {
        self.seen = initiallySeen
    }

    func hasSeenCameraCoachIntro() -> Bool {
        seen
    }

    func markCameraCoachIntroSeen() {
        seen = true
    }
}
#endif
