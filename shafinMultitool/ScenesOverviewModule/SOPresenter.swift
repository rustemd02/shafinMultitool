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

/// SET OS Package 3 bridge: the library surface projects through the existing
/// VIPER owners instead of creating a new state owner.
extension SOPresenter: SETLibrarySceneProviding {
    func librarySceneSummaries() -> [UnifiedSceneProjectSummary] {
        interactor.getSceneSummaries()
    }

    func libraryCreateScene(named name: String) -> SETLibraryCreateOutcome {
        interactor.createScene(named: name)
    }

    func libraryDeleteScene(named name: String, completion: @escaping (Bool) -> Void) {
        interactor.deleteScene(with: name, completion: completion)
    }

    func libraryOpenScene(named name: String) {
        router.loadSceneWithName(title: name, newScene: false)
    }
}
