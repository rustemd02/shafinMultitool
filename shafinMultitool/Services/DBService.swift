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
    
    func saveARWorldMap(map: ARWorldMap?, sceneData: SceneData) throws {
        guard let map = map else { return }
        let arMapsDirectory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("Scenes")
        
        let mapURL = arMapsDirectory.appendingPathComponent(sceneData.name + "_map")
        let dataMap = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
        try dataMap.write(to: mapURL, options: [.atomic])
        
        let sceneDataURL = arMapsDirectory.appendingPathComponent(sceneData.name + "_data")
        let dataScene = try JSONEncoder().encode(sceneData)
        try dataScene.write(to: sceneDataURL, options: [.atomic])
    }
    
    func getAllARWorldMapTitles() -> [String]? {
        do {
            createARMapsDirectory()
            
            let arMapsDirectory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("Scenes")

            let fileURLs = try FileManager.default.contentsOfDirectory(at: arMapsDirectory, includingPropertiesForKeys: nil)
            
            var fileNames: [String] = []
            
            for fileURL in fileURLs where fileURL.path.hasSuffix("_map") {
                let fileName = fileURL.deletingPathExtension().lastPathComponent
                let cleanFileName = fileName.replacingOccurrences(of: "_map", with: "")
                fileNames.append(cleanFileName)
            }
            
            return fileNames
        } catch {
            print(error)
            return nil
        }
    }
    
    func loadARWorldMap(sceneName: String) -> (ARWorldMap, SceneData)? {
        do {
            let arMapsDirectory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("Scenes")
            
            let mapURL = arMapsDirectory.appendingPathComponent(sceneName + "_map")
            let mapData = try Data(contentsOf: mapURL)
            guard let unarchivedMap = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: mapData) else { return nil }
            
            let sceneDataURL = arMapsDirectory.appendingPathComponent(sceneName + "_data")
            let sceneData = try Data(contentsOf: sceneDataURL)
            let sceneDataDecoded = try JSONDecoder().decode(SceneData.self, from: sceneData)
            
            return (unarchivedMap, sceneDataDecoded)
        } catch {
            print("Error loading ARWorldMap: \(error)")
            return nil
        }
    }
    
    func deleteMap(with name: String, completion: @escaping (Bool) -> ()) {
        do {
            let arMapsDirectory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("Scenes")
            
            let mapURL = arMapsDirectory.appendingPathComponent(name + "_map")
            if FileManager.default.fileExists(atPath: mapURL.path) {
                try FileManager.default.removeItem(at: mapURL)
            }
            
            let sceneDataURL = arMapsDirectory.appendingPathComponent(name + "_data")
            if FileManager.default.fileExists(atPath: sceneDataURL.path) {
                try FileManager.default.removeItem(at: sceneDataURL)
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
