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
        DBService.shared.deleteMap(with: title) { deleted in
            self.presenter?.updateUI()
        }
    }
    
    
    func getSceneNames() -> [String] {
        guard let sceneNames = DBService.shared.getAllARWorldMapTitles() else { return [] }
        return sceneNames
    }
}
