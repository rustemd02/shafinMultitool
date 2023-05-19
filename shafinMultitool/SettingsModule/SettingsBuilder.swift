//
//  SettingsScreenBuilder.swift
//  shafinMultitool
//
//  Created by Рустем on 15.05.2023.
//

import UIKit

class SettingsBuilder: UIViewController {
    static func build() -> SettingsViewController {
        let interactor = SettingsInteractor()
        let router = SettingsRouter()
        let presenter = SettingsPresenter(router: router, interactor: interactor)
        let viewController = SettingsViewController()
        viewController.presenter = presenter
        presenter.view = viewController
        interactor.presenter = presenter
        router.view = viewController
        return viewController
    }
}
