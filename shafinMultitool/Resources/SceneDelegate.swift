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
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        let window = UIWindow(windowScene: windowScene)
        self.window = window
        window.backgroundColor = .black
        if let benchmarkConfig = DeviceBenchmarkConfig.fromEnvironment() {
            let hostingController = UIHostingController(
                rootView: DeviceBenchmarkRootView(config: benchmarkConfig, interactive: true)
            )
            window.rootViewController = hostingController
        } else {
            let vc = SOModuleBuilder.build()
            let navigationController = UINavigationController(rootViewController: vc)
            navigationController.navigationBar.isHidden = true
            window.rootViewController = navigationController
        }
        window.makeKeyAndVisible()
    }
}
