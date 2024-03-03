//
//  SettingsPresenter.swift
//  shafinMultitool
//
//  Created by Рустем on 15.05.2023.
//

import Foundation


protocol EditScriptPresenterProtocol: AnyObject {
    func fetchScript() -> String
    func submitButtonPressed(newScript: String)
    

}

class EditScriptPresenter {
    // MARK: - Properties
    weak var view: EditScriptViewProtocol?
    let router: EditScriptRouterProtocol
    let interactor: EditScriptInteractorProtocol
    
    init(router: EditScriptRouterProtocol, interactor: EditScriptInteractorProtocol) {
        self.router = router
        self.interactor = interactor
    }
    
}


extension EditScriptPresenter: EditScriptPresenterProtocol {
    
    func submitButtonPressed(newScript: String) {
        interactor.submitButtonPressed(newScript: newScript)
        router.dismiss(withUpdatedScript: newScript)
    }
    
    
    func fetchScript() -> String {
        return interactor.fetchScript()
    }

    
}
