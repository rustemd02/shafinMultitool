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

/// Read-time classification for links owned by a persisted scene project.
/// `optionalMissing` is a truthful empty/metadata-only projection; it is not a
/// request to synthesize a fixture. `compatibleLegacy` preserves readable v0
/// projects without rewriting them during open. Only `blocking` prevents the
/// workspace from being constructed.
enum UnifiedSceneProjectLinkStatus: String, Codable, Equatable, Sendable {
    case healthy
    case compatibleLegacy = "compatible-legacy"
    case optionalMissing = "optional-missing"
    case blocking
}

struct UnifiedSceneProjectOpenValidation: Equatable, Sendable {
    let identity: UnifiedSceneProjectLinkStatus
    let generator: UnifiedSceneProjectLinkStatus
    let ar: UnifiedSceneProjectLinkStatus
    let storyboard: UnifiedSceneProjectLinkStatus
    let recording: UnifiedSceneProjectLinkStatus

    var isOpenable: Bool {
        [identity, generator, ar, storyboard, recording].allSatisfy { $0 != .blocking }
    }
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

    /// Validates only persisted identities and links needed to construct the
    /// existing Generator/AR/Storyboard workspace. This remains a pure
    /// read-time check: it never repairs or persists the aggregate.
    func validateForOpening(
        expectedID: UUID,
        isLegacy: Bool,
        recordingStatus: UnifiedSceneProjectLinkStatus
    ) -> UnifiedSceneProjectOpenValidation {
        let identityIsValid = expectedID == id &&
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            createdAt.timeIntervalSinceReferenceDate.isFinite &&
            updatedAt.timeIntervalSinceReferenceDate.isFinite &&
            uniqueNonEmpty(markedObjects.map { $0.id.uuidString }) &&
            uniqueNonEmpty(recordingReferences.map { $0.recordingID.uuidString }) &&
            markedObjects.allSatisfy { marker in
                !marker.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    marker.worldPosition.isFinite
            }
        let identity: UnifiedSceneProjectLinkStatus = identityIsValid ? .healthy : .blocking

        let scriptIsValid = parsedScript.map(validateScript) ?? true
        let generator: UnifiedSceneProjectLinkStatus
        if !scriptIsValid {
            generator = .blocking
        } else if parsedScript == nil {
            generator = isLegacy ? .compatibleLegacy : .optionalMissing
        } else {
            generator = .healthy
        }

        let markedObjectLinksAreValid = validateMarkedObjectLinks()
        let plannedSceneIsValid = plannedScene.map {
            validatePlannedScene($0, script: parsedScript)
        } ?? true
        let ar: UnifiedSceneProjectLinkStatus
        if !markedObjectLinksAreValid || !plannedSceneIsValid {
            ar = .blocking
        } else if plannedScene == nil && markedObjects.isEmpty {
            ar = isLegacy ? .compatibleLegacy : .optionalMissing
        } else {
            ar = .healthy
        }

        let overlaysAreValid = validateVisualOverlays()
        let storyboard: UnifiedSceneProjectLinkStatus
        if !scriptIsValid || !plannedSceneIsValid || !overlaysAreValid {
            storyboard = .blocking
        } else if parsedScript == nil && plannedScene == nil && visualOverlays.isEmpty {
            storyboard = isLegacy ? .compatibleLegacy : .optionalMissing
        } else {
            storyboard = .healthy
        }

        let recording: UnifiedSceneProjectLinkStatus
        if !uniqueNonEmpty(recordingReferences.map { $0.recordingID.uuidString }) {
            recording = .blocking
        } else {
            recording = recordingStatus
        }

        return UnifiedSceneProjectOpenValidation(
            identity: identity,
            generator: generator,
            ar: ar,
            storyboard: storyboard,
            recording: recording
        )
    }

    private func validateScript(_ script: SceneScript) -> Bool {
        let actorIDs = script.actors.map(\.id)
        let objectIDs = script.objects.map(\.id)
        let beatIDs = script.beats.map(\.id)
        guard uniqueNonEmpty(actorIDs),
              uniqueNonEmpty(objectIDs),
              uniqueNonEmpty(beatIDs),
              Set(actorIDs).isDisjoint(with: Set(objectIDs)) else {
            return false
        }

        let entityIDs = Set(actorIDs + objectIDs)
        var actionIDs = Set<String>()
        for beat in script.beats {
            if let minDuration = beat.minDuration,
               !minDuration.isFinite || minDuration < 0 {
                return false
            }
            for action in beat.actions {
                guard !action.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      actionIDs.insert(action.id).inserted,
                      actorIDs.contains(action.actorId) else {
                    return false
                }
                if let target = action.target, !entityIDs.contains(target) {
                    return false
                }
                if let holdingObject = action.holdingObject, !objectIDs.contains(holdingObject) {
                    return false
                }
            }
            if let target = beat.camera?.target, !entityIDs.contains(target) {
                return false
            }
        }

        var relationIDs = Set<String>()
        for relation in script.spatialRelations {
            guard !relation.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  relationIDs.insert(relation.id).inserted,
                  entityIDs.contains(relation.subject),
                  entityIDs.contains(relation.object) else {
                return false
            }
        }
        return true
    }

    private func validatePlannedScene(_ plan: PlannedScene, script: SceneScript?) -> Bool {
        let actorIDs = Set(script?.actors.map(\.id) ?? [])
        let objectIDs = Set(script?.objects.map(\.id) ?? [])
        let beatIDs = Set(script?.beats.map(\.id) ?? [])
        let entityIDs = actorIDs.union(objectIDs)
        var placedIDs = Set<String>()

        // A persisted plan is a binding from every scripted entity to one
        // concrete placement.  If a script is present, accepting duplicate or
        // missing bindings would make downstream Generator/Storyboard lookup
        // ambiguous (or silently omit a scripted entity).
        if script != nil {
            let plannedActorIDs = plan.placedActors.map(\.actorId)
            let plannedObjectIDs = plan.placedObjects.map(\.objectId)
            guard uniqueNonEmpty(plannedActorIDs),
                  uniqueNonEmpty(plannedObjectIDs),
                  Set(plannedActorIDs) == actorIDs,
                  Set(plannedObjectIDs) == objectIDs else {
                return false
            }
        }

        for actor in plan.placedActors {
            guard !actor.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  placedIDs.insert(actor.id).inserted,
                  !actor.actorId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  actor.initialPosition.isFinite,
                  actor.initialRotation.isFinite,
                  actor.path.allSatisfy(\.isFinite),
                  actor.pathDurations.count == max(actor.path.count - 1, 0),
                  actor.pathDurations.allSatisfy({ $0.isFinite && $0 >= 0 }),
                  actor.pathCameras.allSatisfy({ $0?.target.map(entityIDs.contains) ?? true }),
                  actor.pathBeatIDs.allSatisfy({ $0.map(beatIDs.contains) ?? true }) else {
                return false
            }
            if script != nil && !actorIDs.contains(actor.actorId) {
                return false
            }
        }

        for object in plan.placedObjects {
            guard !object.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  placedIDs.insert(object.id).inserted,
                  !object.objectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  object.position.isFinite,
                  object.rotation.isFinite else {
                return false
            }
            if script != nil && !objectIDs.contains(object.objectId) {
                return false
            }
        }
        return true
    }

    private func validateMarkedObjectLinks() -> Bool {
        let markedIDs = Set(markedObjects.map { $0.canonicalMarkedObjectID.lowercased() })
        let referencedMarkedIDs = parsedScript?.objects.map(\.id).filter {
            $0.lowercased().hasPrefix("object_marked_")
        } ?? []
        return referencedMarkedIDs.allSatisfy { markedIDs.contains($0.lowercased()) }
    }

    private func validateVisualOverlays() -> Bool {
        var overlayIDs = Set<String>()
        let beatIDs = Set(parsedScript?.beats.map(\.id) ?? [])
        for overlay in visualOverlays {
            guard !overlay.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  overlayIDs.insert(overlay.id).inserted,
                  !overlay.sceneID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !overlay.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            if let beatID = overlay.beatID, !beatIDs.contains(beatID) {
                return false
            }
        }
        return true
    }

    private func uniqueNonEmpty(_ values: [String]) -> Bool {
        values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } &&
            Set(values).count == values.count
    }
}

private extension Position3D {
    var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}
