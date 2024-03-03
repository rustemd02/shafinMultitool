//
//  SettingsRouter.swift
//  shafinMultitool
//
//  Created by Рустем on 15.05.2023.
//

import Foundation

protocol EditScriptRouterProtocol: AnyObject {
    func dismiss(withUpdatedScript newScript: String)
}

class EditScriptRouter: EditScriptRouterProtocol {
    weak var view: EditScriptViewController?
    var newScriptHandler: ((String) -> Void)?
    
    func dismiss(withUpdatedScript newScript: String) {
        view?.dismiss(animated: true)
        newScriptHandler?(newScript)
    }
}
