//
//  SettingsPresenter.swift
//  shafinMultitool
//
//  Created by Рустем on 15.05.2023.
//

import Foundation


protocol SettingsPresenterProtocol: AnyObject {
    func viewDidLoad()
    func submitButtonPressed()
    func getResolutionsArrayLength() -> Int
    func titleForRow(row: Int) -> String
    func didSelectRow(row: Int)
    func getCurrentRow() -> Int

}

class SettingsPresenter {
    // MARK: - Properties
    weak var view: SettingsViewProtocol?
    let router: SettingsRouterProtocol
    let interactor: SettingsInteractorProtocol
    
    init(router: SettingsRouterProtocol, interactor: SettingsInteractorProtocol) {
        self.router = router
        self.interactor = interactor
    }
    
}


extension SettingsPresenter: SettingsPresenterProtocol {
    func getCurrentRow() -> Int {
        return interactor.getCurrentRow()
    }
    
    func didSelectRow(row: Int) {
        interactor.didSelectRow(row: row)
    }
    
    func titleForRow(row: Int) -> String {
        return interactor.titleForRow(row: row)
    }
    
    func getResolutionsArrayLength() -> Int {
        return interactor.getResolutionsArrayLength()
    }
    
    func submitButtonPressed() {
        interactor.submitButtonPressed()
        router.dismiss()
    }
    
    
    func viewDidLoad() {
    }

    
}
