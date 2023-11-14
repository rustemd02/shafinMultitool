//
//  MainScreenRouter.swift
//  shafinMultitool
//
//  Created by Рустем on 23.03.2023.
//

import Foundation

protocol CameraScreenRouterProtocol: AnyObject {
    func openSettings()
    func openScenesOverviewScreen()
}

class CameraScreenRouter: CameraScreenRouterProtocol {
    weak var view: CameraScreenViewController?
    
    func openSettings() {
        let vc = SettingsBuilder.build()
        view?.present(vc, animated: true)
    }
    
    func openScenesOverviewScreen() {
        view?.navigationController?.popToRootViewController(animated: true)
    }
}
