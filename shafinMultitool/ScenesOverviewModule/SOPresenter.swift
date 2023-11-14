//
//  SOPresenter.swift
//  shafinMultitool
//
//  Created by Рустем on 07.11.2023.
//

import Foundation

protocol SOPresenterProtocol: AnyObject {
    func getSceneNames() -> [String]
    func deleteScene(with title: String)
    func loadSceneWithName(title: String?, newScene: Bool)
    
    func updateUI()
}

class SOPresenter {
    weak var view: SOViewControllerProtocol?
    let router: SORouterProtocol
    let interactor: SOInteractorProtocol
    
    init(router: SORouterProtocol, interactor: SOInteractorProtocol) {
        self.router = router
        self.interactor = interactor
    }
    
}

extension SOPresenter: SOPresenterProtocol {
    
    func deleteScene(with title: String) {
        interactor.deleteScene(with: title)
    }

    func loadSceneWithName(title: String?, newScene: Bool) {
        router.loadSceneWithName(title: title, newScene: newScene)
    }
    
    
    func getSceneNames() -> [String] {
        return interactor.getSceneNames()
    }
    
    func updateUI() {
        view?.updateUI()
    }
}
