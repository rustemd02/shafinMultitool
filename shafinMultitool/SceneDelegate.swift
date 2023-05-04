//
//  SceneDelegate.swift
//  shafinMultitool
//
//  Created by Рустем on 25.04.2023.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.windowScene = windowScene
        window?.backgroundColor = .white
        let vc = CameraScreenBuilder.build()
        
        window?.rootViewController = vc
        window?.makeKeyAndVisible()
    }
}
