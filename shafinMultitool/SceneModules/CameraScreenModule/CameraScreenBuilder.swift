//
//  MainScreenAssembly.swift
//  shafinMultitool
//
//  Created by Рустем on 23.03.2023.
//

import UIKit

class CameraScreenBuilder: UIViewController {
    static func build(sceneName: String, newScene: Bool) -> CameraScreenViewController {
        let interactor = CameraScreenInteractor()
        interactor.sceneName = sceneName
        interactor.newScene = newScene
        let router = CameraScreenRouter()
        let presenter = CameraScreenPresenter(router: router, interactor: interactor)
        let viewController = CameraScreenViewController()
        viewController.presenter = presenter
        presenter.view = viewController
        interactor.presenter = presenter
        router.view = viewController
        return viewController
    }
}
