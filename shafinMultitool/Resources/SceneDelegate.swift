//
//  SceneDelegate.swift
//  shafinMultitool
//
//  Created by Рустем on 25.04.2023.
//

import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

#if DEBUG
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
        let rootViewController = Self.makeRootViewController(
            benchmarkConfig: DeviceBenchmarkConfig.fromEnvironment(),
            benchmarkRootBuilder: { benchmarkConfig in
                UIHostingController(
                    rootView: DeviceBenchmarkRootView(config: benchmarkConfig, interactive: true)
                )
            },
            commercialRootBuilder: {
                CommercialShellComposition().makeShell()
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
