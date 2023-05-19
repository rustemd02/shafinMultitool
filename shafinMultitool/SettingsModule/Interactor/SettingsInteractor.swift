//
//  SettingsInteractor.swift
//  shafinMultitool
//
//  Created by Рустем on 15.05.2023.
//

import Foundation

protocol SettingsInteractorProtocol: AnyObject {
    func submitButtonPressed()
    func getResolutionsArrayLength() -> Int
    func titleForRow(row: Int) -> String
    func didSelectRow(row: Int)
    func getCurrentRow() -> Int

    
}


class SettingsInteractor {
    // MARK: - Properties
    weak var presenter: SettingsPresenterProtocol?
    
    var selectedRow: Int?
    var cameraService = CameraService.shared


}

extension SettingsInteractor: SettingsInteractorProtocol {

    func getCurrentRow() -> Int {
        selectedRow = UserDefaults.standard.integer(forKey: "selectedResoultionsRow")
        return selectedRow ?? 0
    }
    
    
    func didSelectRow(row: Int) {
        selectedRow = row
    }
    
    func titleForRow(row: Int) -> String {
        return cameraService.resolutions[row].width.description + "x" + cameraService.resolutions[row].height.description
    }
    
    func getResolutionsArrayLength() -> Int {
        return cameraService.resolutions.count
    }
    
    
    func submitButtonPressed() {
        UserDefaults.standard.set(selectedRow, forKey: "selectedResoultionsRow")
    }
    
}

