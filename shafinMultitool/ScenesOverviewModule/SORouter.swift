//
//  SORoutre.swift
//  shafinMultitool
//
//  Created by Рустем on 07.11.2023.
//

import Foundation

protocol SORouterProtocol: AnyObject {
    func loadSceneWithName(title: String?, newScene: Bool)
}

class SORouter: SORouterProtocol {
    weak var view: SOViewController?
    
    func loadSceneWithName(title: String?, newScene: Bool) {
        guard let title = title else { return }
        let vc = CameraScreenBuilder.build(sceneName: title, newScene: newScene)
        view?.navigationController?.pushViewController(vc, animated: true)
        
    }
    
    
}
