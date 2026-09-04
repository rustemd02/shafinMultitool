//
//  SceneData.swift
//  shafinMultitool
//
//  Created by Рустем on 14.11.2023.
//

import Foundation
import RealityKit

struct SceneData: Codable {
    var name: String
    var actors: [ActorData]?
    var script: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case actors
        case script
    }
    
    init(name: String, actors: [ActorData]?, script: String) {
        self.name = name
        self.actors = actors
        self.script = script
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        actors = try container.decodeIfPresent([ActorData].self, forKey: .actors)
        script = try container.decodeIfPresent(String.self, forKey: .script)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(actors, forKey: .actors)
        try container.encodeIfPresent(script, forKey: .script)
    }
}

struct UnifiedSceneProjectSummary: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let updatedAt: Date
}

/// A project-owned pointer to one finalized recording.  The path is relative
/// to Application Support and is resolved only by RecordingArtifactStore.
struct SceneRecordingReference: Codable, Equatable, Sendable {
    let recordingID: UUID
    let relativePath: String
    let duration: TimeInterval?
    let hasAudio: Bool

    init(
        recordingID: UUID,
        relativePath: String,
        duration: TimeInterval? = nil,
        hasAudio: Bool = false
    ) {
        self.recordingID = recordingID
        self.relativePath = relativePath
        self.duration = duration
        self.hasAudio = hasAudio
    }

    enum CodingKeys: String, CodingKey {
        case recordingID
        case relativePath
        case duration
        case hasAudio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordingID = try container.decode(UUID.self, forKey: .recordingID)
        let decodedPath = try container.decode(String.self, forKey: .relativePath)
        guard Self.isSafeRelativePath(decodedPath) else {
            throw DecodingError.dataCorruptedError(
                forKey: .relativePath,
                in: container,
                debugDescription: "Recording reference path must be relative and safe"
            )
        }
        relativePath = decodedPath
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        hasAudio = try container.decodeIfPresent(Bool.self, forKey: .hasAudio) ?? false
    }

    func encode(to encoder: Encoder) throws {
        guard Self.isSafeRelativePath(relativePath) else {
            throw EncodingError.invalidValue(
                relativePath,
                .init(codingPath: [], debugDescription: "Recording reference path must be relative and safe")
            )
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(recordingID, forKey: .recordingID)
        try container.encode(relativePath, forKey: .relativePath)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encode(hasAudio, forKey: .hasAudio)
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        let pathComponents = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.isEmpty &&
            !path.hasPrefix("/") &&
            !path.contains("\0") &&
            !pathComponents.contains(where: { $0 == "." || $0 == ".." || $0.isEmpty })
    }
}

struct UnifiedSceneProject: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var sceneDescription: String
    var markedObjects: [MarkedObject]
    var parsedScript: SceneScript?
    var plannedScene: PlannedScene?
    var sceneChunkState: SceneChunkState?
    var visualOverlays: [SceneVisualOverlay]
    var recordingReferences: [SceneRecordingReference]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sceneDescription: String = "",
        markedObjects: [MarkedObject] = [],
        parsedScript: SceneScript? = nil,
        plannedScene: PlannedScene? = nil,
        sceneChunkState: SceneChunkState? = nil,
        visualOverlays: [SceneVisualOverlay] = [],
        recordingReferences: [SceneRecordingReference] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sceneDescription = sceneDescription
        self.markedObjects = markedObjects
        self.parsedScript = parsedScript
        self.plannedScene = plannedScene
        self.sceneChunkState = sceneChunkState
        self.visualOverlays = visualOverlays
        self.recordingReferences = recordingReferences
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case updatedAt
        case sceneDescription
        case markedObjects
        case parsedScript
        case plannedScene
        case sceneChunkState
        case visualOverlays
        case recordingReferences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        sceneDescription = try container.decode(String.self, forKey: .sceneDescription)
        markedObjects = try container.decode([MarkedObject].self, forKey: .markedObjects)
        parsedScript = try container.decodeIfPresent(SceneScript.self, forKey: .parsedScript)
        plannedScene = try container.decodeIfPresent(PlannedScene.self, forKey: .plannedScene)
        sceneChunkState = try container.decodeIfPresent(SceneChunkState.self, forKey: .sceneChunkState)
        visualOverlays = try container.decodeIfPresent([SceneVisualOverlay].self, forKey: .visualOverlays) ?? []
        recordingReferences = try container.decodeIfPresent(
            [SceneRecordingReference].self,
            forKey: .recordingReferences
        ) ?? []
    }

    var summary: UnifiedSceneProjectSummary {
        UnifiedSceneProjectSummary(id: id, name: name, updatedAt: updatedAt)
    }

    var recordings: [SceneRecordingReference] {
        get { recordingReferences }
        set { recordingReferences = newValue }
    }
}
