//
//  SOModuleBuilder.swift
//  shafinMultitool
//
//  Created by Рустем on 07.11.2023.
//

import UIKit

class SOModuleBuilder: UIViewController {
    static func build(projectStore: DBService = .shared) -> SOViewController {
        let interactor = SOInteractor(projectStore: projectStore)
        let router = SORouter(projectStore: projectStore)
        let presenter = SOPresenter(router: router, interactor: interactor)
        let viewController = SOViewController()
        viewController.presenter = presenter
        presenter.view = viewController
        interactor.presenter = presenter
        router.view = viewController
        return viewController
    }
}
