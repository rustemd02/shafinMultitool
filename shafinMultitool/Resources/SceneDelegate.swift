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
    private let interactivePopGuard = NavigationInteractivePopGuard()
    
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
            interactivePopGuard.navigationController = navigationController
            navigationController.interactivePopGestureRecognizer?.delegate = interactivePopGuard
            window.rootViewController = navigationController
        }
        window.makeKeyAndVisible()
    }
}

private final class NavigationInteractivePopGuard: NSObject, UIGestureRecognizerDelegate {
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
