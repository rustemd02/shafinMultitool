//
//  DBService.swift
//  shafinMultitool
//
//  Created by Рустем on 03.11.2023.
//

import Foundation
import ARKit

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
    
    func saveARWorldMap(map: ARWorldMap?, sceneName: String) throws {
        guard let map = map else { return }
        createARMapsDirectory()
        let arMapsDirectory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("Scenes")
        
        let mapURL = arMapsDirectory.appendingPathComponent(sceneName)
        let data = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
        try data.write(to: mapURL, options: [.atomic])
    }
    
    func getAllARWorldMapTitles() -> [String]? {
        //return ["FDSF", "fdsgg", "gdga dajsfdisfj f"]
        
        do {
            createARMapsDirectory()
            
            let arMapsDirectory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("Scenes")

            let fileURLs = try FileManager.default.contentsOfDirectory(at: arMapsDirectory, includingPropertiesForKeys: nil)
            
            var fileNames: [String] = []
            
            for fileURL in fileURLs {
                fileNames.append(fileURL.lastPathComponent)
            }
            return fileNames
        } catch {
            print(error)
            return nil
        }
    }
    
    func loadARWorldMap(sceneName: String) -> ARWorldMap? {
        do {
            let arMapsDirectory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("Scenes")
            let mapURL = arMapsDirectory.appendingPathComponent(sceneName)
            let mapData = try Data(contentsOf: mapURL)
            guard let unarchievedMap = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: mapData) else { return nil }
            return unarchievedMap
        } catch {
            print("Error loading ARWorldMap: \(error)")
            return nil
        }
    }
    
    func deleteMap(with name: String, completion: @escaping (Bool) -> ()) {
        do {
            let arMapsDirectory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("Scenes")
            let mapURL = arMapsDirectory.appendingPathComponent(name)
            
            if FileManager.default.fileExists(atPath: mapURL.path) {
                try FileManager.default.removeItem(at: mapURL)
            }
            completion(true)
        } catch {
            print(error)
        }
    }
    
    func createARMapsDirectory() {
        let fileManager = FileManager.default
        do {
            let documentsDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let arMapsDirectory = documentsDirectory.appendingPathComponent("Scenes")
            
            if !fileManager.fileExists(atPath: arMapsDirectory.path) {
                try fileManager.createDirectory(at: arMapsDirectory, withIntermediateDirectories: true, attributes: nil)
            }
        } catch {
            print("Error creating ARMaps directory: \(error)")
        }
    }

}
