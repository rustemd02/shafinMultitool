//
//  DBService.swift
//  shafinMultitool
//
//  Created by Рустем on 03.11.2023.
//

import Foundation
import ARKit

/// M1-015 PersistenceOwner failure taxonomy. `staleSnapshot` is the recoverable
/// optimistic-concurrency conflict: the caller's snapshot no longer matches the
/// stored project, so nothing was overwritten and the caller may reload and retry.
enum DBServiceError: Error, Equatable {
    case staleSnapshot(storedUpdatedAt: Date)
}

class DBService {

    private struct UnifiedSceneProjectFile: Codable {
        let project: UnifiedSceneProject
        let archivedWorldMap: Data?
    }

    static let shared = DBService()

    /// M1-015: every file operation is serialized on this queue, so overlapping
    /// save/rename/delete/list operations cannot interleave reads and writes and
    /// no partially written project is ever visible. Public methods keep their
    /// synchronous signatures; internal `*OnQueue` implementations call each
    /// other directly because `sync` is not reentrant.
    private let persistenceQueue = DispatchQueue(
        label: "com.shafinMultitool.dbservice.persistence",
        qos: .userInitiated
    )

    private let fileManager: FileManager
    private let recordingArtifactStore: Result<RecordingArtifactStore, Error>
    /// M1-016: deletion is rejected while an active workspace holds a lease.
    private let projectLeases: ProjectLifecycleRegistry
    private let legacyScenesDirectoryName = "Scenes"
    private let unifiedProjectsDirectoryName = "UnifiedSceneProjects"

    init(
        fileManager: FileManager = .default,
        recordingArtifactStore: RecordingArtifactStore? = nil,
        projectLeases: ProjectLifecycleRegistry = .shared
    ) {
        self.fileManager = fileManager
        self.projectLeases = projectLeases
        if let recordingArtifactStore {
            self.recordingArtifactStore = .success(recordingArtifactStore)
        } else {
            do {
                self.recordingArtifactStore = .success(try RecordingArtifactStore(fileManager: fileManager))
            } catch {
                self.recordingArtifactStore = .failure(error)
            }
        }
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
        try persistenceQueue.sync {
            try saveLegacySceneOnQueue(mapData: mapData, sceneData: sceneData)
        }
    }

    /// Persists the existing `_map`/`_data` file contract without requiring an AR session.
    /// A nil map is a metadata-only update and intentionally leaves an existing map untouched.
    /// Encoding finishes before either file changes. Each write is atomic, but a non-nil save
    /// remains a two-file legacy operation and is not an atomic transaction across both files.
    func saveLegacyScene(mapData: Data?, sceneData: SceneData) throws {
        try persistenceQueue.sync {
            try saveLegacySceneOnQueue(mapData: mapData, sceneData: sceneData)
        }
    }

    private func saveLegacySceneOnQueue(mapData: Data?, sceneData: SceneData) throws {
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
        persistenceQueue.sync {
            do {
                try createLegacyScenesDirectory()

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
    }

    func loadARWorldMap(sceneName: String) -> (ARWorldMap, SceneData)? {
        persistenceQueue.sync {
            guard let stored = loadLegacySceneFilesOnQueue(sceneName: sceneName),
                  let worldMap = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self,
                                                                         from: stored.mapData) else {
                return nil
            }
            return (worldMap, stored.sceneData)
        }
    }

    func loadSceneData(sceneName: String) -> SceneData? {
        persistenceQueue.sync {
            loadSceneDataOnQueue(sceneName: sceneName)
        }
    }

    private func loadSceneDataOnQueue(sceneName: String) -> SceneData? {
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
        persistenceQueue.sync {
            loadLegacySceneFilesOnQueue(sceneName: sceneName)
        }
    }

    private func loadLegacySceneFilesOnQueue(sceneName: String) -> (mapData: Data, sceneData: SceneData)? {
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
        persistenceQueue.sync {
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
    }

    func createARMapsDirectory() {
        do {
            try persistenceQueue.sync {
                try createLegacyScenesDirectory()
            }
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
        persistenceQueue.sync {
            listUnifiedSceneProjectsOnQueue()
        }
    }

    private func listUnifiedSceneProjectsOnQueue() -> [UnifiedSceneProjectSummary] {
        do {
            try createUnifiedSceneProjectsDirectory()
            let directory = try unifiedSceneProjectsDirectoryURL()
            let fileURLs = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            let projects = fileURLs
                .filter { $0.lastPathComponent.hasSuffix("_project.json") }
                .compactMap { fileURL -> UnifiedSceneProject? in
                    guard let stored = try? loadUnifiedSceneProjectFile(fileURL) else {
                        return nil
                    }
                    return stored.project
                }
                .sorted { $0.updatedAt > $1.updatedAt }
            return projects.map(\.summary)
        } catch {
            print("Error listing unified scene projects: \(error)")
            return []
        }
    }

    func createUnifiedSceneProject(named name: String) throws -> UnifiedSceneProject {
        try persistenceQueue.sync {
            try createUnifiedSceneProjectOnQueue(named: name)
        }
    }

    private func createUnifiedSceneProjectOnQueue(named name: String) throws -> UnifiedSceneProject {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw NSError(domain: "DBService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Project name must not be empty"])
        }
        if listUnifiedSceneProjectsOnQueue().contains(where: { $0.name == trimmedName }) {
            throw NSError(domain: "DBService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Project with this name already exists"])
        }

        let project = UnifiedSceneProject(name: trimmedName)
        let projectData = try JSONEncoder().encode(
            UnifiedSceneProjectFile(project: project, archivedWorldMap: nil)
        )
        try saveUnifiedSceneProjectOnQueue(encoded: projectData, project: project, expectedUpdatedAt: nil)
        return project
    }

    func saveUnifiedSceneProject(_ project: UnifiedSceneProject, worldMap: ARWorldMap?) throws {
        try saveUnifiedSceneProject(project, worldMap: worldMap, expectedUpdatedAt: nil)
    }

    /// M1-015 optimistic conflict behavior. When `expectedUpdatedAt` is supplied
    /// and a project file already exists whose `updatedAt` differs, the caller's
    /// snapshot is stale: nothing is written and
    /// `DBServiceError.staleSnapshot(storedUpdatedAt:)` is thrown so the caller
    /// can reload and retry. A missing stored file is treated as an initial
    /// write, not a conflict.
    func saveUnifiedSceneProject(
        _ project: UnifiedSceneProject,
        worldMap: ARWorldMap?,
        expectedUpdatedAt: Date?
    ) throws {
        let archivedWorldMap = try worldMap.map {
            try NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
        }
        let projectData = try JSONEncoder().encode(
            UnifiedSceneProjectFile(project: project, archivedWorldMap: archivedWorldMap)
        )

        try persistenceQueue.sync {
            try saveUnifiedSceneProjectOnQueue(
                encoded: projectData,
                project: project,
                expectedUpdatedAt: expectedUpdatedAt
            )
        }
    }

    private func saveUnifiedSceneProjectOnQueue(
        encoded projectData: Data,
        project: UnifiedSceneProject,
        expectedUpdatedAt: Date?
    ) throws {
        if let expectedUpdatedAt,
           let stored = loadUnifiedSceneProjectByIDOnQueue(project.id) {
            guard stored.project.updatedAt == expectedUpdatedAt else {
                throw DBServiceError.staleSnapshot(storedUpdatedAt: stored.project.updatedAt)
            }
        }

        try createUnifiedSceneProjectsDirectory()
        let directory = try unifiedSceneProjectsDirectoryURL()
        let projectURL = directory.appendingPathComponent(projectFilename(for: project.id))
        try projectData.write(to: projectURL, options: [.atomic])

        let mapURL = directory.appendingPathComponent(worldMapFilename(for: project.id))
        try? fileManager.removeItem(at: mapURL)
    }

    private func loadUnifiedSceneProjectByIDOnQueue(_ id: UUID) -> (project: UnifiedSceneProject, archivedWorldMap: Data?)? {
        guard let directory = try? unifiedSceneProjectsDirectoryURL() else {
            return nil
        }
        let projectURL = directory.appendingPathComponent(projectFilename(for: id))
        guard fileManager.fileExists(atPath: projectURL.path),
              let stored = try? loadUnifiedSceneProjectFile(projectURL) else {
            return nil
        }
        return (stored.project, stored.archivedWorldMap)
    }

    func loadUnifiedSceneProject(named name: String) -> (UnifiedSceneProject, ARWorldMap?)? {
        persistenceQueue.sync {
            loadUnifiedSceneProjectOnQueue(named: name)
        }
    }

    private func loadUnifiedSceneProjectOnQueue(named name: String) -> (UnifiedSceneProject, ARWorldMap?)? {
        do {
            try createUnifiedSceneProjectsDirectory()
            let directory = try unifiedSceneProjectsDirectoryURL()
            let projectURL = try findUnifiedProjectFileURL(named: name, in: directory)
            guard let projectURL else { return nil }

            let stored = try loadUnifiedSceneProjectFile(projectURL)
            let mapURL = directory.appendingPathComponent(worldMapFilename(for: stored.project.id))
            let worldMap: ARWorldMap?
            if let archivedWorldMap = stored.archivedWorldMap {
                worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: archivedWorldMap)
            } else if stored.isLegacy && fileManager.fileExists(atPath: mapURL.path) {
                let mapData = try Data(contentsOf: mapURL)
                worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: mapData)
            } else {
                worldMap = nil
            }
            return (stored.project, worldMap)
        } catch {
            print("Error loading unified scene project: \(error)")
            return nil
        }
    }

    func deleteUnifiedSceneProject(named name: String, completion: @escaping (Bool) -> ()) {
        persistenceQueue.sync {
            deleteUnifiedSceneProjectOnQueue(named: name, completion: completion)
        }
    }

    private func deleteUnifiedSceneProjectOnQueue(named name: String, completion: @escaping (Bool) -> ()) {
        do {
            try createUnifiedSceneProjectsDirectory()
            let directory = try unifiedSceneProjectsDirectoryURL()
            guard let projectURL = try findUnifiedProjectFileURL(named: name, in: directory) else {
                completion(false)
                return
            }

            let stored = try loadUnifiedSceneProjectFile(projectURL)
            guard !projectLeases.isLeased(projectID: stored.project.id) else {
                // M1-016: an active workspace owns this project; deleting it
                // now would strand that workspace on a ghost project and let a
                // later autosave resurrect partial state.
                print("Deletion rejected: project \(stored.project.name) is open in an active workspace")
                completion(false)
                return
            }
            let mapURL = directory.appendingPathComponent(worldMapFilename(for: stored.project.id))
            if fileManager.fileExists(atPath: mapURL.path) {
                try fileManager.removeItem(at: mapURL)
            }
            if fileManager.fileExists(atPath: projectURL.path) {
                try fileManager.removeItem(at: projectURL)
            }

            do {
                try recordingArtifactStore.get().removeProjectArtifacts(projectID: stored.project.id)
            } catch {
                print("Error deleting recording artifacts for unified scene project: \(error)")
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

    private func loadUnifiedSceneProjectFile(_ fileURL: URL) throws -> (project: UnifiedSceneProject,
                                                                         archivedWorldMap: Data?,
                                                                         isLegacy: Bool) {
        let data = try Data(contentsOf: fileURL)
        guard let object = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "Unified scene project must be a JSON object"
            ))
        }

        let stored: (project: UnifiedSceneProject, archivedWorldMap: Data?, isLegacy: Bool)
        if object.keys.contains("project") {
            let file = try JSONDecoder().decode(UnifiedSceneProjectFile.self, from: data)
            stored = (file.project, file.archivedWorldMap, false)
        } else {
            stored = (try JSONDecoder().decode(UnifiedSceneProject.self, from: data), nil, true)
        }

        let suffix = "_project.json"
        guard fileURL.lastPathComponent.hasSuffix(suffix),
              let filenameID = UUID(uuidString: String(fileURL.lastPathComponent.dropLast(suffix.count))),
              filenameID == stored.project.id else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "Unified scene project ID does not match filename"
            ))
        }
        return stored
    }

    private func findUnifiedProjectFileURL(named name: String, in directory: URL) throws -> URL? {
        let fileURLs = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for fileURL in fileURLs where fileURL.lastPathComponent.hasSuffix("_project.json") {
            guard let stored = try? loadUnifiedSceneProjectFile(fileURL) else {
                continue
            }
            if stored.project.name == name {
                return fileURL
            }
        }
        return nil
    }

}

#if DEBUG
extension DBService {
    /// UI-test support only: removes every persisted unified scene project so
    /// a production-route test starts from a deterministic empty library.
    /// Never called from production flows.
    func resetUnifiedSceneProjectsForUITesting() {
        persistenceQueue.sync {
            guard let directory = try? unifiedSceneProjectsDirectoryURL(),
                  fileManager.fileExists(atPath: directory.path) else {
                return
            }
            try? fileManager.removeItem(at: directory)
        }
    }
}
#endif
