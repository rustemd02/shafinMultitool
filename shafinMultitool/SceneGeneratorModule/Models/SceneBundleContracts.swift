//
//  SceneBundleContracts.swift
//  shafinMultitool
//
//  Created on 22.04.2026.
//

import Foundation

enum SceneBundleParseMode: String, Codable, Equatable {
    case full
    case append
}

enum NormalizedScriptUnitKind: String, Codable, Equatable {
    case sceneHeading = "scene_heading"
    case speakerCue = "speaker_cue"
    case parenthetical = "parenthetical"
    case dialogue = "dialogue"
    case actionLine = "action_line"
    case proseLine = "prose_line"
    case blank
}

struct ScriptOffsetRange: Codable, Equatable {
    var start: Int
    var end: Int
}

struct NormalizedScriptUnit: Codable, Equatable, Identifiable {
    var id: String
    var kind: NormalizedScriptUnitKind
    var text: String
    var lineIndex: Int
    var charRange: ScriptOffsetRange
}

struct ScriptSceneCandidate: Codable, Equatable, Identifiable {
    var id: String
    var sceneIndex: Int
    var heading: String?
    var unitRange: Range<Int>
    var sourceRange: ScriptOffsetRange
    var sourceText: String
    var metadata: SceneTopLevelMetadata
    var isImplicit: Bool
}

struct SceneChunkAnchor: Codable, Equatable {
    var sourceBundle: SourceAnchorBundle
    var speakerCues: [String]
    var actorMentions: [String]
    var objectMentions: [String]
    var markedObjectMentions: [String]
    var pronounMentions: [String]
    var chronologyCues: [String]
    var locationCues: [String]
    var timeCues: [String]
    var uncertaintyFlags: [String]

    static let empty = SceneChunkAnchor(
        sourceBundle: .empty,
        speakerCues: [],
        actorMentions: [],
        objectMentions: [],
        markedObjectMentions: [],
        pronounMentions: [],
        chronologyCues: [],
        locationCues: [],
        timeCues: [],
        uncertaintyFlags: []
    )
}

struct SceneEntityRegistrySnapshot: Codable, Equatable {
    var actors: [ScenePlanIR.Actor]
    var objects: [ScenePlanIR.Object]
    var actorAliasMap: [String: String]
    var objectAliasMap: [String: String]
    var speakerAliasMap: [String: String]
    var unresolvedMentions: [String]
    var lastResolvedSpeaker: String?
    var locationName: String?
    var actorPoses: [String: ActorPose]
    var heldObjects: [String: String]

    static let empty = SceneEntityRegistrySnapshot(
        actors: [],
        objects: [],
        actorAliasMap: [:],
        objectAliasMap: [:],
        speakerAliasMap: [:],
        unresolvedMentions: [],
        lastResolvedSpeaker: nil,
        locationName: nil,
        actorPoses: [:],
        heldObjects: [:]
    )
}

struct SceneDeferredRef: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, Equatable {
        case actor
        case object
    }

    var id: String
    var localRef: String
    var kind: Kind
    var alias: String?
    var sourceText: String?
}

struct SceneChunkDraft: Codable, Equatable, Identifiable {
    var id: String { chunkID }
    var sceneID: String
    var chunkID: String
    var chunkIndex: Int
    var sourceText: String
    var sourceRange: ScriptOffsetRange
    var anchors: SceneChunkAnchor
    var registrySnapshot: SceneEntityRegistrySnapshot
    var plan: ScenePlanIR
    var usedFallbackPlanner: Bool
    var usedLegacyPlanBridge: Bool
    var confidence: Float
    var unresolvedMentions: [String]
    var reasonCodes: [String]
}

struct SceneChunkStateDelta: Codable, Equatable {
    var locationUpdate: String?
    var actorPoseUpdates: [String: ActorPose]
    var heldObjectUpdates: [String: String]
    var releasedObjects: [String]

    static let empty = SceneChunkStateDelta(
        locationUpdate: nil,
        actorPoseUpdates: [:],
        heldObjectUpdates: [:],
        releasedObjects: []
    )
}

struct SceneChunk: Codable, Equatable, Identifiable {
    struct RegistryPatch: Codable, Equatable {
        var actors: [ScenePlanIR.Actor]
        var objects: [ScenePlanIR.Object]
        var actorAliasMap: [String: String]
        var objectAliasMap: [String: String]
        var speakerAliasMap: [String: String]

        static let empty = RegistryPatch(
            actors: [],
            objects: [],
            actorAliasMap: [:],
            objectAliasMap: [:],
            speakerAliasMap: [:]
        )
    }

    var id: String { chunkID }
    var sceneID: String
    var chunkID: String
    var chunkIndex: Int
    var sourceText: String
    var sourceRange: ScriptOffsetRange
    var anchors: SceneChunkAnchor
    var registryPatch: RegistryPatch
    var beatPatch: [ScenePlanIR.Beat]
    var spatialRelationPatch: [ScenePlanIR.SpatialRelation]
    var stateDelta: SceneChunkStateDelta
    var deferredRefs: [SceneDeferredRef]
    var reasonCodes: [String]
    var usedFallbackPlanner: Bool
    var usedLegacyPlanBridge: Bool
}

struct SceneStitchState: Codable, Equatable, Identifiable {
    var id: String { sceneID }
    var sceneID: String
    var sceneIndex: Int
    var sourceText: String
    var metadata: SceneTopLevelMetadata
    var registry: SceneEntityRegistrySnapshot
    var actors: [ScenePlanIR.Actor]
    var objects: [ScenePlanIR.Object]
    var beats: [ScenePlanIR.Beat]
    var spatialRelations: [ScenePlanIR.SpatialRelation]
    var chunkLedger: [String]
    var deferredRefs: [SceneDeferredRef]
    var continuityDiagnostics: [String]

    init(
        sceneID: String,
        sceneIndex: Int,
        sourceText: String,
        metadata: SceneTopLevelMetadata,
        registry: SceneEntityRegistrySnapshot = .empty,
        actors: [ScenePlanIR.Actor] = [],
        objects: [ScenePlanIR.Object] = [],
        beats: [ScenePlanIR.Beat] = [],
        spatialRelations: [ScenePlanIR.SpatialRelation] = [],
        chunkLedger: [String] = [],
        deferredRefs: [SceneDeferredRef] = [],
        continuityDiagnostics: [String] = []
    ) {
        self.sceneID = sceneID
        self.sceneIndex = sceneIndex
        self.sourceText = sourceText
        self.metadata = metadata
        self.registry = registry
        self.actors = actors
        self.objects = objects
        self.beats = beats
        self.spatialRelations = spatialRelations
        self.chunkLedger = chunkLedger
        self.deferredRefs = deferredRefs
        self.continuityDiagnostics = continuityDiagnostics
    }
}

struct SceneBundlePlan: Codable, Equatable {
    struct SceneEntry: Codable, Equatable, Identifiable {
        var id: String { sceneID }
        var sceneID: String
        var sceneIndex: Int
        var sourceText: String
        var metadata: SceneTopLevelMetadata
        var chunks: [SceneChunk]
        var diagnostics: [String]
        var plan: ScenePlanIR
    }

    var bundleID: String
    var scenes: [SceneEntry]
    var activeSceneIndex: Int
    var diagnostics: [String]
}

struct SceneBundleScript: Codable, Equatable {
    var bundleID: String
    var scenes: [SceneScript]
    var activeSceneIndex: Int
    var diagnostics: [String]

    var activeSceneScript: SceneScript? {
        guard scenes.indices.contains(activeSceneIndex) else { return scenes.last }
        return scenes[activeSceneIndex]
    }

    var activeSceneID: String? {
        activeSceneScript?.sceneHeading ?? activeSceneScript?.locationName
    }
}

struct SceneChunkDiagnostics: Codable, Equatable, Identifiable {
    var id: String { chunkID }
    var sceneID: String
    var chunkID: String
    var chunkIndex: Int
    var reasonCodes: [String]
    var unresolvedRefs: [String]
    var anchors: SceneChunkAnchor
    var usedFallbackPlanner: Bool
    var usedLegacyPlanBridge: Bool
}

struct ScriptDocumentState: Codable, Equatable {
    var documentID: String
    var mode: SceneBundleParseMode
    var sourceText: String
    var normalizedUnits: [NormalizedScriptUnit]
    var sceneCandidates: [ScriptSceneCandidate]
    var stitchStates: [SceneStitchState]
    var bundlePlan: SceneBundlePlan
    var bundleScript: SceneBundleScript
    var activeSceneIndex: Int
}

struct SceneBundleParsingResult: Equatable {
    var bundleScript: SceneBundleScript
    var activeSceneScript: SceneScript?
    var activeSceneId: String?
    var sceneChunks: [SceneChunk]
    var documentState: ScriptDocumentState
    var diagnostics: ParsingDiagnostics
    var chunkDiagnostics: [SceneChunkDiagnostics]
}
