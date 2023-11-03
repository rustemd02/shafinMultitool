//
//  DBService.swift
//  shafinMultitool
//
//  Created by Рустем on 03.11.2023.
//

import Foundation

class DBService {
    static let shared = DBService()
    
    func fetchSettingsButtonValues() -> SettingsValues {
        let width = UserDefaults.standard.integer(forKey: "resolutionWidth")
        let height = UserDefaults.standard.integer(forKey: "resolutionHeight")
        let fps = UserDefaults.standard.integer(forKey: "framerate")
        let wb = UserDefaults.standard.integer(forKey: "whiteBalance")
        let iso = UserDefaults.standard.integer(forKey: "iso")
        let settingsValues = SettingsValues(resolution: [(width: width, height: height)], fps: fps, wb: wb, iso: iso)
        return settingsValues
    }
}
