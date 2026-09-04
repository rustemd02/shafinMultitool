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

    private static let unifiedSceneProjectSchemaVersion = 1

    private struct UnifiedSceneProjectFile: Codable {
        let schemaVersion: Int
        let project: UnifiedSceneProject
        let archivedWorldMap: Data?

        init(project: UnifiedSceneProject, archivedWorldMap: Data?) {
            schemaVersion = DBService.unifiedSceneProjectSchemaVersion
            self.project = project
            self.archivedWorldMap = archivedWorldMap
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.schemaVersion) {
                schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            } else {
                schemaVersion = 0
            }
            guard schemaVersion >= 0,
                  schemaVersion <= DBService.unifiedSceneProjectSchemaVersion else {
                throw DecodingError.dataCorruptedError(
                    forKey: .schemaVersion,
                    in: container,
                    debugDescription: "Unsupported unified scene project schema version " + String(schemaVersion)
                )
            }
            project = try container.decode(UnifiedSceneProject.self, forKey: .project)
            archivedWorldMap = try container.decodeIfPresent(Data.self, forKey: .archivedWorldMap)
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case project
            case archivedWorldMap
        }
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

    /// Typed Library projection. Unlike the legacy list API, a malformed
    /// persisted project is a load failure and can never be mistaken for an
    /// empty Library.
    func loadLibrarySceneSnapshots() -> Result<[SETLibrarySceneSnapshot], SETLibraryFailure> {
        persistenceQueue.sync {
            do {
                let projects = try loadUnifiedSceneProjectsOnQueue()
                return .success(projects.map { makeLibrarySnapshotOnQueue(for: $0) })
            } catch {
                return .failure(libraryFailure(for: error))
            }
        }
    }

    /// Typed create path. Duplicate detection and the actual write share the
    /// existing serial persistence queue, so two callers cannot both win.
    func createLibraryScene(named name: String) -> Result<SETLibrarySceneSnapshot, SETLibraryFailure> {
        persistenceQueue.sync {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return .failure(.invalidName) }

            do {
                let projects = try loadUnifiedSceneProjectsOnQueue()
                if let duplicate = projects.first(where: { $0.name == trimmed }) {
                    return .failure(.duplicateName(name: trimmed, conflictingID: duplicate.id))
                }
                let project = try createUnifiedSceneProjectOnQueue(named: trimmed)
                return .success(makeLibrarySnapshotOnQueue(for: project))
            } catch {
                return .failure(libraryFailure(for: error))
            }
        }
    }

    /// Renames only the project identity fields. The aggregate (script,
    /// planning, overlays and recording references) and any archived world-map
    /// bytes are carried into the replacement envelope unchanged.
    func renameUnifiedSceneProject(
        id: UUID,
        to name: String,
        expectedUpdatedAt: Date
    ) -> Result<SETLibrarySceneSnapshot, SETLibraryFailure> {
        persistenceQueue.sync {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return .failure(.invalidName) }

            do {
                let directory = try unifiedSceneProjectsDirectoryURL()
                try createUnifiedSceneProjectsDirectory()
                guard let projectURL = try findUnifiedProjectFileURL(id: id, in: directory) else {
                    return .failure(.missingProject(id: id))
                }

                let stored = try loadUnifiedSceneProjectFile(projectURL)
                guard stored.project.updatedAt == expectedUpdatedAt else {
                    return .failure(.staleSnapshot(
                        expectedUpdatedAt: expectedUpdatedAt,
                        storedUpdatedAt: stored.project.updatedAt
                    ))
                }
                if let duplicate = try loadUnifiedSceneProjectsOnQueue().first(where: {
                    $0.id != id && $0.name == trimmed
                }) {
                    return .failure(.duplicateName(name: trimmed, conflictingID: duplicate.id))
                }

                var renamed = stored.project
                renamed.name = trimmed
                renamed.updatedAt = Date()

                // Legacy v0 projects may keep the map beside the JSON file.
                // Promote those bytes into the new envelope so a rename does
                // not silently sever the world-map relation.
                let archivedWorldMap = try preservedWorldMapDataOnQueue(
                    stored: stored,
                    directory: directory
                )
                let data = try JSONEncoder().encode(
                    UnifiedSceneProjectFile(project: renamed, archivedWorldMap: archivedWorldMap)
                )
                try data.write(to: projectURL, options: [.atomic])
                return .success(makeLibrarySnapshotOnQueue(for: renamed))
            } catch {
                return .failure(libraryFailure(for: error))
            }
        }
    }

    /// UUID/snapshot based deletion for the production Library provider. All
    /// filesystem work remains on the existing serial queue; an artifact
    /// cleanup failure returns before mutating the project file.
    func deleteUnifiedSceneProject(
        id: UUID,
        expectedUpdatedAt: Date,
        completion: @escaping (Result<Void, SETLibraryFailure>) -> Void
    ) {
        persistenceQueue.sync {
            completion(deleteUnifiedSceneProjectOnQueue(id: id, expectedUpdatedAt: expectedUpdatedAt))
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

    private func loadUnifiedSceneProjectsOnQueue() throws -> [UnifiedSceneProject] {
        try createUnifiedSceneProjectsDirectory()
        let directory = try unifiedSceneProjectsDirectoryURL()
        let fileURLs = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return try fileURLs
            .filter { $0.lastPathComponent.hasSuffix("_project.json") }
            .map { try loadUnifiedSceneProjectFile($0).project }
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id.uuidString < $1.id.uuidString
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
        let directory = try unifiedSceneProjectsDirectoryURL()
        let projectURL = directory.appendingPathComponent(projectFilename(for: project.id))

        // Decode an existing file before writing so malformed/future records
        // fail closed instead of being silently downgraded by a save.
        if fileManager.fileExists(atPath: projectURL.path) {
            let stored = try loadUnifiedSceneProjectFile(projectURL)
            if let expectedUpdatedAt {
                guard stored.project.updatedAt == expectedUpdatedAt else {
                    throw DBServiceError.staleSnapshot(storedUpdatedAt: stored.project.updatedAt)
                }
            }
        }

        try createUnifiedSceneProjectsDirectory()
        try projectData.write(to: projectURL, options: [.atomic])

        let mapURL = directory.appendingPathComponent(worldMapFilename(for: project.id))
        try? fileManager.removeItem(at: mapURL)
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
            do {
                try createUnifiedSceneProjectsDirectory()
                let directory = try unifiedSceneProjectsDirectoryURL()
                guard let projectURL = try findUnifiedProjectFileURL(named: name, in: directory),
                      let id = UUID(uuidString: String(projectURL.lastPathComponent.dropLast("_project.json".count))) else {
                    completion(false)
                    return
                }
                if case .success = deleteUnifiedSceneProjectOnQueue(id: id, expectedUpdatedAt: nil) {
                    completion(true)
                } else {
                    completion(false)
                }
            } catch {
                print("Error deleting unified scene project: \(error)")
                completion(false)
            }
        }
    }

    private func deleteUnifiedSceneProjectOnQueue(
        id: UUID,
        expectedUpdatedAt: Date?
    ) -> Result<Void, SETLibraryFailure> {
        do {
            try createUnifiedSceneProjectsDirectory()
            let directory = try unifiedSceneProjectsDirectoryURL()
            guard let projectURL = try findUnifiedProjectFileURL(id: id, in: directory) else {
                return .failure(.missingProject(id: id))
            }

            let stored = try loadUnifiedSceneProjectFile(projectURL)
            if let expectedUpdatedAt,
               stored.project.updatedAt != expectedUpdatedAt {
                return .failure(.staleSnapshot(
                    expectedUpdatedAt: expectedUpdatedAt,
                    storedUpdatedAt: stored.project.updatedAt
                ))
            }
            guard !projectLeases.isLeased(projectID: stored.project.id) else {
                // M1-016: an active workspace owns this project; deleting it
                // now would strand that workspace on a ghost project and let a
                // later autosave resurrect partial state.
                print("Deletion rejected: project \(stored.project.name) is open in an active workspace")
                return .failure(.inUse)
            }

            // Validate and remove owned artifacts before deleting the project
            // record. RecordingArtifactStore validates the complete directory
            // before unlinking, so a cleanup failure leaves project state intact.
            if !stored.project.recordingReferences.isEmpty {
                guard case .success(let artifactStore) = recordingArtifactStore else {
                    return .failure(.artifactCleanup)
                }
                do {
                    try artifactStore.removeProjectArtifacts(projectID: stored.project.id)
                } catch {
                    return .failure(.artifactCleanup)
                }
            }

            let mapURL = directory.appendingPathComponent(worldMapFilename(for: stored.project.id))
            if fileManager.fileExists(atPath: mapURL.path) {
                try fileManager.removeItem(at: mapURL)
            }
            if fileManager.fileExists(atPath: projectURL.path) {
                try fileManager.removeItem(at: projectURL)
            }
            return .success(())
        } catch {
            return .failure(libraryFailure(for: error))
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

        let hasProjectKey = object.keys.contains("project")
        let hasSchemaVersionKey = object.keys.contains("schemaVersion")
        let stored: (project: UnifiedSceneProject, archivedWorldMap: Data?, isLegacy: Bool)
        if hasProjectKey {
            let file = try JSONDecoder().decode(UnifiedSceneProjectFile.self, from: data)
            stored = (file.project, file.archivedWorldMap, file.schemaVersion == 0)
        } else if hasSchemaVersionKey {
            // A schema discriminator belongs to the envelope. Refusing this
            // shape prevents a versioned/malformed record from falling back to
            // the raw v0 project decoder, which would ignore the discriminator.
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "Unified scene project schema version requires an envelope"
            ))
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

    private func findUnifiedProjectFileURL(id: UUID, in directory: URL) throws -> URL? {
        let projectURL = directory.appendingPathComponent(projectFilename(for: id))
        return fileManager.fileExists(atPath: projectURL.path) ? projectURL : nil
    }

    private func makeLibrarySnapshotOnQueue(for project: UnifiedSceneProject) -> SETLibrarySceneSnapshot {
        let preview: SETLibraryPreviewMetadata
        if let plannedScene = project.plannedScene {
            preview = SETLibraryPreviewMetadata(
                kind: .storyboard,
                beatCount: project.parsedScript?.beats.count ?? 0,
                actorCount: plannedScene.placedActors.count,
                objectCount: plannedScene.placedObjects.count,
                recordingCount: project.recordingReferences.count
            )
        } else if let parsedScript = project.parsedScript {
            preview = SETLibraryPreviewMetadata(
                kind: .screenplay,
                beatCount: parsedScript.beats.count,
                actorCount: parsedScript.actors.count,
                objectCount: parsedScript.objects.count,
                recordingCount: project.recordingReferences.count
            )
        } else if !project.sceneDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            preview = SETLibraryPreviewMetadata(
                kind: .metadataOnly,
                beatCount: 0,
                actorCount: 0,
                objectCount: 0,
                recordingCount: project.recordingReferences.count
            )
        } else {
            preview = .unavailable
        }

        return SETLibrarySceneSnapshot(
            id: project.id,
            name: project.name,
            updatedAt: project.updatedAt,
            preview: preview,
            artifactHealth: artifactHealthOnQueue(for: project)
        )
    }

    private func artifactHealthOnQueue(for project: UnifiedSceneProject) -> SETLibraryArtifactHealth {
        guard !project.recordingReferences.isEmpty else { return .none }
        guard case .success(let artifactStore) = recordingArtifactStore else { return .unavailable }

        var hasCorruptArtifact = false
        for reference in project.recordingReferences {
            guard let url = artifactStore.resolve(reference) else { return .missing }
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  let fileSize = attributes[.size] as? NSNumber else {
                return .missing
            }
            if fileSize.int64Value <= 0 {
                hasCorruptArtifact = true
            }
        }
        return hasCorruptArtifact ? .corrupt : .healthy
    }

    private func preservedWorldMapDataOnQueue(
        stored: (project: UnifiedSceneProject, archivedWorldMap: Data?, isLegacy: Bool),
        directory: URL
    ) throws -> Data? {
        if let archivedWorldMap = stored.archivedWorldMap {
            return archivedWorldMap
        }
        guard stored.isLegacy else { return nil }
        let mapURL = directory.appendingPathComponent(worldMapFilename(for: stored.project.id))
        guard fileManager.fileExists(atPath: mapURL.path) else { return nil }
        return try Data(contentsOf: mapURL)
    }

    private func libraryFailure(for error: Error) -> SETLibraryFailure {
        if let error = error as? DBServiceError {
            switch error {
            case .staleSnapshot(let storedUpdatedAt):
                return .staleSnapshot(expectedUpdatedAt: storedUpdatedAt, storedUpdatedAt: storedUpdatedAt)
            }
        }
        if let error = error as NSError?, error.domain == "DBService" {
            switch error.code {
            case 1: return .invalidName
            case 2: return .duplicateName(name: error.localizedFailureReason ?? "", conflictingID: nil)
            default: break
            }
        }
        return .persistence
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
