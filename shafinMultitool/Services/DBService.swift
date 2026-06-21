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
    private let fileManager: FileManager
    private let legacyScenesDirectoryName = "Scenes"
    private let unifiedProjectsDirectoryName = "UnifiedSceneProjects"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func fetchSettingsButtonValues() -> SettingsValues {
        let width = UserDefaults.standard.integer(forKey: "resolutionWidth")
        let height = UserDefaults.standard.integer(forKey: "resolutionHeight")
        let fps = UserDefaults.standard.integer(forKey: "framerate")
        let wb = UserDefaults.standard.integer(forKey: "whiteBalance")
        let iso = UserDefaults.standard.integer(forKey: "iso")
        let speed = UserDefaults.standard.double(forKey: "speedMultiplier")
        let settingsValues = SettingsValues(resolution: [(width: width, height: height)], fps: fps, wb: wb, iso: iso, speed: speed)
        return settingsValues
    }
    
    func saveARWorldMap(map: ARWorldMap?, sceneData: SceneData) throws {
        guard let map = map else { return }
        let arMapsDirectory = try legacyScenesDirectoryURL()
        
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
            
            let arMapsDirectory = try legacyScenesDirectoryURL()

            let fileURLs = try fileManager.contentsOfDirectory(at: arMapsDirectory, includingPropertiesForKeys: nil)
            
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
            let arMapsDirectory = try legacyScenesDirectoryURL()
            
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
            let arMapsDirectory = try legacyScenesDirectoryURL()
            
            let mapURL = arMapsDirectory.appendingPathComponent(name + "_map")
            if fileManager.fileExists(atPath: mapURL.path) {
                try fileManager.removeItem(at: mapURL)
            }
            
            let sceneDataURL = arMapsDirectory.appendingPathComponent(name + "_data")
            if fileManager.fileExists(atPath: sceneDataURL.path) {
                try fileManager.removeItem(at: sceneDataURL)
            }
            
            completion(true)
        } catch {
            print(error)
        }
    }
    
    func createARMapsDirectory() {
        do {
            let arMapsDirectory = try legacyScenesDirectoryURL()
            
            if !fileManager.fileExists(atPath: arMapsDirectory.path) {
                try fileManager.createDirectory(at: arMapsDirectory, withIntermediateDirectories: true, attributes: nil)
            }
        } catch {
            print("Error creating ARMaps directory: \(error)")
        }
    }

    func listUnifiedSceneProjects() -> [UnifiedSceneProjectSummary] {
        do {
            try createUnifiedSceneProjectsDirectory()
            let directory = try unifiedSceneProjectsDirectoryURL()
            let fileURLs = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            let projects = try fileURLs
                .filter { $0.lastPathComponent.hasSuffix("_project.json") }
                .map(loadUnifiedSceneProjectFile)
                .sorted { $0.updatedAt > $1.updatedAt }
            return projects.map(\.summary)
        } catch {
            print("Error listing unified scene projects: \(error)")
            return []
        }
    }

    func createUnifiedSceneProject(named name: String) throws -> UnifiedSceneProject {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw NSError(domain: "DBService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Project name must not be empty"])
        }
        if listUnifiedSceneProjects().contains(where: { $0.name == trimmedName }) {
            throw NSError(domain: "DBService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Project with this name already exists"])
        }

        let project = UnifiedSceneProject(name: trimmedName)
        try saveUnifiedSceneProject(project, worldMap: nil)
        return project
    }

    func saveUnifiedSceneProject(_ project: UnifiedSceneProject, worldMap: ARWorldMap?) throws {
        try createUnifiedSceneProjectsDirectory()
        let directory = try unifiedSceneProjectsDirectoryURL()

        let projectURL = directory.appendingPathComponent(projectFilename(for: project.id))
        let projectData = try JSONEncoder().encode(project)
        try projectData.write(to: projectURL, options: [.atomic])

        let mapURL = directory.appendingPathComponent(worldMapFilename(for: project.id))
        if let worldMap {
            let mapData = try NSKeyedArchiver.archivedData(withRootObject: worldMap, requiringSecureCoding: true)
            try mapData.write(to: mapURL, options: [.atomic])
        } else if fileManager.fileExists(atPath: mapURL.path) {
            try fileManager.removeItem(at: mapURL)
        }
    }

    func loadUnifiedSceneProject(named name: String) -> (UnifiedSceneProject, ARWorldMap?)? {
        do {
            try createUnifiedSceneProjectsDirectory()
            let directory = try unifiedSceneProjectsDirectoryURL()
            let projectURL = try findUnifiedProjectFileURL(named: name, in: directory)
            guard let projectURL else { return nil }

            let project = try loadUnifiedSceneProjectFile(projectURL)
            let mapURL = directory.appendingPathComponent(worldMapFilename(for: project.id))
            let worldMap: ARWorldMap?
            if fileManager.fileExists(atPath: mapURL.path) {
                let mapData = try Data(contentsOf: mapURL)
                worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: mapData)
            } else {
                worldMap = nil
            }
            return (project, worldMap)
        } catch {
            print("Error loading unified scene project: \(error)")
            return nil
        }
    }

    func deleteUnifiedSceneProject(named name: String, completion: @escaping (Bool) -> ()) {
        do {
            try createUnifiedSceneProjectsDirectory()
            let directory = try unifiedSceneProjectsDirectoryURL()
            guard let projectURL = try findUnifiedProjectFileURL(named: name, in: directory) else {
                completion(false)
                return
            }

            let project = try loadUnifiedSceneProjectFile(projectURL)
            let mapURL = directory.appendingPathComponent(worldMapFilename(for: project.id))
            if fileManager.fileExists(atPath: projectURL.path) {
                try fileManager.removeItem(at: projectURL)
            }
            if fileManager.fileExists(atPath: mapURL.path) {
                try fileManager.removeItem(at: mapURL)
            }
            completion(true)
        } catch {
            print("Error deleting unified scene project: \(error)")
            completion(false)
        }
    }

    private func legacyScenesDirectoryURL() throws -> URL {
        try fileManager.url(for: .documentDirectory,
                            in: .userDomainMask,
                            appropriateFor: nil,
                            create: false)
            .appendingPathComponent(legacyScenesDirectoryName)
    }

    private func unifiedSceneProjectsDirectoryURL() throws -> URL {
        try fileManager.url(for: .documentDirectory,
                            in: .userDomainMask,
                            appropriateFor: nil,
                            create: false)
            .appendingPathComponent(unifiedProjectsDirectoryName)
    }

    private func createUnifiedSceneProjectsDirectory() throws {
        let directory = try unifiedSceneProjectsDirectoryURL()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
    }

    private func projectFilename(for id: UUID) -> String {
        "\(id.uuidString)_project.json"
    }

    private func worldMapFilename(for id: UUID) -> String {
        "\(id.uuidString)_worldmap"
    }

    private func loadUnifiedSceneProjectFile(_ fileURL: URL) throws -> UnifiedSceneProject {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(UnifiedSceneProject.self, from: data)
    }

    private func findUnifiedProjectFileURL(named name: String, in directory: URL) throws -> URL? {
        let fileURLs = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for fileURL in fileURLs where fileURL.lastPathComponent.hasSuffix("_project.json") {
            if try loadUnifiedSceneProjectFile(fileURL).name == name {
                return fileURL
            }
        }
        return nil
    }

}
