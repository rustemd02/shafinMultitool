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
#endif

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

#if DEBUG
    private static func makeUITestingRootViewController() -> UIViewController {
        CommercialShellComposition(
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
                    )
                )
                let viewController = UIHostingController(
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
