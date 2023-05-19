//
//  SettingsRouter.swift
//  shafinMultitool
//
//  Created by Рустем on 15.05.2023.
//

import Foundation

protocol SettingsRouterProtocol: AnyObject {
    func dismiss()
}

class SettingsRouter: SettingsRouterProtocol {
    weak var view: SettingsViewController?
    
    func dismiss() {
        view?.dismiss(animated: true)
    }
}
