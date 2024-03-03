//
//  SettingsInteractor.swift
//  shafinMultitool
//
//  Created by Рустем on 15.05.2023.
//

import Foundation

protocol EditScriptInteractorProtocol: AnyObject {
    func fetchScript() -> String
    func submitButtonPressed(newScript: String)
    

    
}


class EditScriptInteractor {
    // MARK: - Properties
    weak var presenter: EditScriptPresenterProtocol?
    var sceneData: SceneData?


}

extension EditScriptInteractor: EditScriptInteractorProtocol {
    func fetchScript() -> String {
        guard let script = sceneData?.script else { return "" }
        return script
    }
    
    func submitButtonPressed(newScript: String) {
        sceneData?.script = newScript
    }
    

    
}

