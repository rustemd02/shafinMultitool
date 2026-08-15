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
        let mapData = try map.map {
            try NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
        }
        try saveLegacyScene(mapData: mapData, sceneData: sceneData)
    }

    /// Persists the existing `_map`/`_data` file contract without requiring an AR session.
    /// A nil map is a metadata-only update and intentionally leaves an existing map untouched.
    /// Encoding finishes before either file changes. Each write is atomic, but a non-nil save
    /// remains a two-file legacy operation and is not an atomic transaction across both files.
    func saveLegacyScene(mapData: Data?, sceneData: SceneData) throws {
        try createLegacyScenesDirectory()
        let directory = try legacyScenesDirectoryURL()
        let encodedSceneData = try JSONEncoder().encode(sceneData)

        if let mapData {
            let mapURL = directory.appendingPathComponent(sceneData.name + "_map")
            try mapData.write(to: mapURL, options: [.atomic])
        }

        let sceneDataURL = directory.appendingPathComponent(sceneData.name + "_data")
        try encodedSceneData.write(to: sceneDataURL, options: [.atomic])
    }
    
    func getAllARWorldMapTitles() -> [String]? {
        do {
            createARMapsDirectory()
            
            let arMapsDirectory = try legacyScenesDirectoryURL()

            let fileURLs = try fileManager.contentsOfDirectory(at: arMapsDirectory, includingPropertiesForKeys: nil)
            
            let fileNames = fileURLs.compactMap { fileURL -> String? in
                let fileName = fileURL.lastPathComponent
                if fileName.hasSuffix("_data") {
                    return String(fileName.dropLast("_data".count))
                }
                return nil
            }

            return Array(Set(fileNames)).sorted()
        } catch {
            print(error)
            return nil
        }
    }
    
    func loadARWorldMap(sceneName: String) -> (ARWorldMap, SceneData)? {
        guard let stored = loadLegacySceneFiles(sceneName: sceneName),
              let worldMap = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self,
                                                                     from: stored.mapData) else {
            return nil
        }
        return (worldMap, stored.sceneData)
    }

    func loadSceneData(sceneName: String) -> SceneData? {
        do {
            let directory = try legacyScenesDirectoryURL()
            let sceneDataURL = directory.appendingPathComponent(sceneName + "_data")
            let sceneData = try Data(contentsOf: sceneDataURL)
            return try JSONDecoder().decode(SceneData.self, from: sceneData)
        } catch {
            print("Error loading scene data: \(error)")
            return nil
        }
    }

    func loadLegacySceneFiles(sceneName: String) -> (mapData: Data, sceneData: SceneData)? {
        do {
            let directory = try legacyScenesDirectoryURL()
            let mapData = try Data(contentsOf: directory.appendingPathComponent(sceneName + "_map"))
            let sceneData = try Data(contentsOf: directory.appendingPathComponent(sceneName + "_data"))
            return (mapData, try JSONDecoder().decode(SceneData.self, from: sceneData))
        } catch {
            return nil
        }
    }
    
    func deleteMap(with name: String, completion: @escaping (Bool) -> ()) {
        do {
            let arMapsDirectory = try legacyScenesDirectoryURL()
            
            let storedFiles = [
                arMapsDirectory.appendingPathComponent(name + "_map"),
                arMapsDirectory.appendingPathComponent(name + "_data")
            ]
            for storedFile in storedFiles where fileManager.fileExists(atPath: storedFile.path) {
                try fileManager.removeItem(at: storedFile)
            }
            
            completion(true)
        } catch {
            print(error)
            completion(false)
        }
    }
    
    func createARMapsDirectory() {
        do {
            try createLegacyScenesDirectory()
        } catch {
            print("Error creating ARMaps directory: \(error)")
        }
    }

    private func createLegacyScenesDirectory() throws {
        let arMapsDirectory = try legacyScenesDirectoryURL()
        if !fileManager.fileExists(atPath: arMapsDirectory.path) {
            try fileManager.createDirectory(at: arMapsDirectory, withIntermediateDirectories: true, attributes: nil)
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
