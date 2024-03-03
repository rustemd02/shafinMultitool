//
//  MainScreenRouter.swift
//  shafinMultitool
//
//  Created by Рустем on 23.03.2023.
//

import Foundation

protocol CameraScreenRouterProtocol: AnyObject {
    func openEditScriptScreen(with sceneData: SceneData, newScriptHandler: @escaping (String) -> Void)
    func openScenesOverviewScreen()
}

class CameraScreenRouter: CameraScreenRouterProtocol {
    weak var view: CameraScreenViewController?
    
    func openEditScriptScreen(with sceneData: SceneData, newScriptHandler: @escaping (String) -> Void) {
        let vc = EditScriptBuilder.build(with: sceneData, newScriptHandler: newScriptHandler)
        view?.present(vc, animated: true)
    }
    
    func openScenesOverviewScreen() {
        view?.navigationController?.popToRootViewController(animated: true)
    }
    
}
