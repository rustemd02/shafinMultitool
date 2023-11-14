//
//  SOModuleBuilder.swift
//  shafinMultitool
//
//  Created by Рустем on 07.11.2023.
//

import UIKit

class SOModuleBuilder: UIViewController {
    static func build() -> SOViewController {
        let interactor = SOInteractor()
        let router = SORouter()
        let presenter = SOPresenter(router: router, interactor: interactor)
        let viewController = SOViewController()
        viewController.presenter = presenter
        presenter.view = viewController
        interactor.presenter = presenter
        router.view = viewController
        return viewController
    }
}
