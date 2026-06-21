//
//  SOInteractor.swift
//  shafinMultitool
//
//  Created by Рустем on 07.11.2023.
//

import Foundation

protocol SOInteractorProtocol: AnyObject {
    func deleteScene(with title: String)
    func getSceneNames() -> [String]
}

class SOInteractor {
    weak var presenter: SOPresenterProtocol?
    private var sceneNames: [String] = []
    
}

extension SOInteractor: SOInteractorProtocol {
    func deleteScene(with title: String) {
        DBService.shared.deleteUnifiedSceneProject(named: title) { deleted in
            self.presenter?.updateUI()
        }
    }
    
    
    func getSceneNames() -> [String] {
        DBService.shared.listUnifiedSceneProjects().map(\.name)
    }
}
