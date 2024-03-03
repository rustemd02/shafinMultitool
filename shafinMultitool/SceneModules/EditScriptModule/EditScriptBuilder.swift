//
//  SettingsScreenBuilder.swift
//  shafinMultitool
//
//  Created by Рустем on 15.05.2023.
//

import UIKit

class EditScriptBuilder: UIViewController {
    static func build(with sceneData: SceneData, newScriptHandler: @escaping (String) -> Void) -> EditScriptViewController {
        let interactor = EditScriptInteractor()
        let router = EditScriptRouter()
        let presenter = EditScriptPresenter(router: router, interactor: interactor)
        let viewController = EditScriptViewController()
        viewController.presenter = presenter
        presenter.view = viewController
        interactor.presenter = presenter
        interactor.sceneData = sceneData
        router.view = viewController
        router.newScriptHandler = newScriptHandler
        return viewController
    }
}
