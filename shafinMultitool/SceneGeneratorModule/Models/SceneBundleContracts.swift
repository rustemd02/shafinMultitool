//
//  SceneBundleContracts.swift
//  shafinMultitool
//
//  Created on 22.04.2026.
//

import Foundation

/// M5-001: typed, non-owning contract for the production Scene journey.
/// The existing Library/Generator/AR/Storyboard/recording owners remain the
/// mutation owners; this catalog only describes their shared hand-off.
enum SceneJourneyState: String, CaseIterable, Codable, Equatable, Identifiable {
    case libraryEmpty, libraryLoaded, librarySelected, libraryFailure
    case generatorInput, generatorValidating, generatorClarification
    case generatorAccepted, generatorQueued, generatorGenerating
    case generatorBackgrounded, generatorRetryableFailure, generatorFailure
    case generatorSuccess
    case arPreparing, arReady, arSurfaceSearch, arPlacement, arPlayback
    case storyboardResult
    case recordingReady, recordingInProgress, recordingReview, recordingFailure

    var id: String { rawValue }
}

enum SceneJourneyOwner: String, Codable, Equatable {
    case library = "SETLibraryModel"
    case generator = "SceneGeneratorViewModel"
    case ar = "SceneWorkspace/ARSceneContainer"
    case storyboard = "Storyboard presentation owner"
    case recording = "RecordingLifecycleOwner"
}

enum SceneJourneyPersistence: String, Codable, Equatable {
    case none
    case draft = "scene draft only"
    case project = "UnifiedSceneProject"
    case artifact = "project + owned recording artifact"
}

enum SceneJourneyArtifact: String, Codable, Equatable {
    case project = "project.id"
    case script = "SceneScript"
    case plannedScene = "PlannedScene"
    case arBindings = "AR marker/entity bindings"
    case storyboard = "Storyboard beat/action links"
    case recording = "recording artifact"
}

struct SceneJourneyStateContract: Codable, Equatable, Identifiable {
    let state: SceneJourneyState
    let owner: SceneJourneyOwner
    let entry: String
    let primaryAction: String
    let recovery: String
    let exit: String
    let persistence: SceneJourneyPersistence
    let downstreamArtifacts: [SceneJourneyArtifact]
    let allowedNext: [SceneJourneyState]

    var id: String { state.id }
}

struct SceneJourneyContract: Codable, Equatable {
    let sourceTypes: [String]
    let states: [SceneJourneyStateContract]

    static let production = SceneJourneyContract(
        sourceTypes: [
            "SETLibraryModel.FlowState", "SceneGenerationStage",
            "SceneWorkspaceMode", "RecordingLifecycleState", "SceneScript", "PlannedScene"
        ],
        states: [
            .init(state: .libraryEmpty, owner: .library, entry: "real project count is zero", primaryAction: "create scene", recovery: "reload library", exit: "creating or loaded", persistence: .none, downstreamArtifacts: [], allowedNext: [.libraryLoaded]),
            .init(state: .libraryLoaded, owner: .library, entry: "real projects loaded", primaryAction: "select project", recovery: "reload library", exit: "selected or empty", persistence: .none, downstreamArtifacts: [.project], allowedNext: [.librarySelected, .libraryEmpty, .libraryFailure]),
            .init(state: .librarySelected, owner: .library, entry: "stable project ID selected", primaryAction: "open generator", recovery: "reopen project or reload", exit: "generator input", persistence: .project, downstreamArtifacts: [.project, .script, .plannedScene, .arBindings, .storyboard, .recording], allowedNext: [.generatorInput, .libraryFailure]),
            .init(state: .libraryFailure, owner: .library, entry: "load or project operation failed", primaryAction: "retry failed operation", recovery: "preserve selection and draft", exit: "loaded, selected, or empty", persistence: .none, downstreamArtifacts: [.project], allowedNext: [.libraryLoaded, .librarySelected, .libraryEmpty]),
            .init(state: .generatorInput, owner: .generator, entry: "selected project opened", primaryAction: "submit validated draft", recovery: "edit or cancel draft", exit: "validating", persistence: .draft, downstreamArtifacts: [.project, .script], allowedNext: [.generatorValidating]),
            .init(state: .generatorValidating, owner: .generator, entry: "single request accepted by owner", primaryAction: "validate and classify", recovery: "return field errors to draft", exit: "clarification, accepted, or failure", persistence: .draft, downstreamArtifacts: [.script], allowedNext: [.generatorClarification, .generatorAccepted, .generatorRetryableFailure, .generatorFailure, .generatorInput]),
            .init(state: .generatorClarification, owner: .generator, entry: "ambiguity requires user input", primaryAction: "answer structured question", recovery: "cancel to same draft", exit: "validating or input", persistence: .draft, downstreamArtifacts: [.script], allowedNext: [.generatorValidating, .generatorInput]),
            .init(state: .generatorAccepted, owner: .generator, entry: "validated request accepted", primaryAction: "enqueue idempotent job", recovery: "cancel before work starts", exit: "queued or cancelled", persistence: .draft, downstreamArtifacts: [.script], allowedNext: [.generatorQueued, .generatorRetryableFailure]),
            .init(state: .generatorQueued, owner: .generator, entry: "request has stable idempotency key", primaryAction: "start generation", recovery: "resume or cancel", exit: "generating, backgrounded, or failure", persistence: .draft, downstreamArtifacts: [.script], allowedNext: [.generatorGenerating, .generatorBackgrounded, .generatorRetryableFailure]),
            .init(state: .generatorGenerating, owner: .generator, entry: "local/backend phase is running", primaryAction: "consume truthful progress", recovery: "cancel or retry when classified", exit: "success, retryable failure, or failure", persistence: .draft, downstreamArtifacts: [.script], allowedNext: [.generatorSuccess, .generatorRetryableFailure, .generatorFailure]),
            .init(state: .generatorBackgrounded, owner: .generator, entry: "scene leaves foreground during request", primaryAction: "reconcile same request", recovery: "poll/resume without duplicate job", exit: "queued, generating, success, or failure", persistence: .draft, downstreamArtifacts: [.script], allowedNext: [.generatorQueued, .generatorGenerating, .generatorSuccess, .generatorRetryableFailure, .generatorFailure]),
            .init(state: .generatorRetryableFailure, owner: .generator, entry: "bounded retryable error", primaryAction: "retry same draft/request", recovery: "keep input and explain cause", exit: "validating or failure", persistence: .draft, downstreamArtifacts: [.script], allowedNext: [.generatorValidating, .generatorFailure, .generatorInput]),
            .init(state: .generatorFailure, owner: .generator, entry: "non-retryable validation/model/persistence error", primaryAction: "edit or leave result", recovery: "preserve prior readable project", exit: "input or selected library", persistence: .draft, downstreamArtifacts: [.project, .script], allowedNext: [.generatorInput, .librarySelected]),
            .init(state: .generatorSuccess, owner: .generator, entry: "validated SceneScript + PlannedScene", primaryAction: "commit one project version", recovery: "rollback transaction and retain draft", exit: "AR or storyboard", persistence: .project, downstreamArtifacts: [.project, .script, .plannedScene, .storyboard], allowedNext: [.arPreparing, .storyboardResult, .generatorFailure]),
            .init(state: .arPreparing, owner: .ar, entry: "success hand-off owns stable project ID", primaryAction: "prepare supported AR session", recovery: "release session and retry", exit: "ready or failure", persistence: .project, downstreamArtifacts: [.plannedScene, .arBindings], allowedNext: [.arReady, .arSurfaceSearch, .generatorFailure]),
            .init(state: .arReady, owner: .ar, entry: "supported running session has valid frame", primaryAction: "search surface", recovery: "relocalize or reset", exit: "surface search or failure", persistence: .project, downstreamArtifacts: [.arBindings], allowedNext: [.arSurfaceSearch, .arPreparing]),
            .init(state: .arSurfaceSearch, owner: .ar, entry: "ready tracking evidence", primaryAction: "confirm surface", recovery: "reposition and retry", exit: "placement or ready", persistence: .project, downstreamArtifacts: [.arBindings], allowedNext: [.arPlacement, .arReady]),
            .init(state: .arPlacement, owner: .ar, entry: "user-confirmed surface", primaryAction: "place stable entities", recovery: "undo/retry placement", exit: "playback, recording, or storyboard", persistence: .project, downstreamArtifacts: [.arBindings, .storyboard], allowedNext: [.arPlayback, .recordingReady, .storyboardResult]),
            .init(state: .arPlayback, owner: .ar, entry: "placed plan selected", primaryAction: "play selected beat", recovery: "stop playback", exit: "recording ready or placement", persistence: .project, downstreamArtifacts: [.arBindings, .storyboard], allowedNext: [.recordingReady, .arPlacement]),
            .init(state: .storyboardResult, owner: .storyboard, entry: "real SceneScript/PlannedScene projection", primaryAction: "select/edit beat or record", recovery: "show missing-link warning", exit: "AR placement or recording", persistence: .project, downstreamArtifacts: [.script, .plannedScene, .storyboard, .recording], allowedNext: [.arPlacement, .recordingReady]),
            .init(state: .recordingReady, owner: .recording, entry: "capture format and AR/storyboard links ready", primaryAction: "start take", recovery: "return to placement", exit: "recording or failure", persistence: .project, downstreamArtifacts: [.arBindings, .storyboard], allowedNext: [.recordingInProgress, .recordingFailure]),
            .init(state: .recordingInProgress, owner: .recording, entry: "recorder is recording", primaryAction: "stop and finalize", recovery: "cancel to recoverable terminal state", exit: "review or failure", persistence: .artifact, downstreamArtifacts: [.recording, .storyboard], allowedNext: [.recordingReview, .recordingFailure]),
            .init(state: .recordingReview, owner: .recording, entry: "final artifact is regular and owned", primaryAction: "save/reopen or playback", recovery: "retry promotion without duplicate", exit: "storyboard or library", persistence: .artifact, downstreamArtifacts: [.project, .recording, .storyboard], allowedNext: [.storyboardResult, .librarySelected]),
            .init(state: .recordingFailure, owner: .recording, entry: "capture/finalize/promotion failed", primaryAction: "retry or discard task artifact", recovery: "preserve finalized media and journal", exit: "ready or review", persistence: .project, downstreamArtifacts: [.recording], allowedNext: [.recordingReady, .recordingReview])
        ]
    )

    func validate() -> Bool {
        let ids = states.map(\.id)
        return states.count == SceneJourneyState.allCases.count
            && Set(ids).count == ids.count
            && states.allSatisfy { !$0.entry.isEmpty && !$0.primaryAction.isEmpty && !$0.recovery.isEmpty && !$0.exit.isEmpty }
            && states.allSatisfy { state in state.allowedNext.allSatisfy { ids.contains($0.id) } }
    }
}

enum SceneBundleParseMode: String, Codable, Equatable {
    case full
    case append
}

enum NormalizedScriptUnitKind: String, Codable, Equatable {
    case sceneHeading = "scene_heading"
    case speakerCue = "speaker_cue"
    case parenthetical = "parenthetical"
    case dialogue = "dialogue"
    case screenText = "screen_text"
    case stageNote = "stage_note"
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
    var isMontage: Bool = false
}

struct SceneVisualOverlay: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, Equatable {
        case screenText = "screen_text"
        case stageNote = "stage_note"
    }

    var id: String
    var kind: Kind
    var text: String
    var sceneID: String
    var sourceRange: ScriptOffsetRange
    var displayOrder: Int
    var beatID: String?
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
    var previousChunkSummary: String? = nil
    var openBeatContext: String? = nil
    var lastActorPositions: [String: String] = [:]

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
        heldObjects: [:],
        previousChunkSummary: nil,
        openBeatContext: nil,
        lastActorPositions: [:]
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
    var previousChunkSummary: String? = nil
    var openBeatContext: String? = nil
    var lastActorPositions: [String: String] = [:]

    static let empty = SceneChunkStateDelta(
        locationUpdate: nil,
        actorPoseUpdates: [:],
        heldObjectUpdates: [:],
        releasedObjects: [],
        previousChunkSummary: nil,
        openBeatContext: nil,
        lastActorPositions: [:]
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
    var visualOverlays: [SceneVisualOverlay] = []
    var diagnostics: [String]
}

struct SceneBundleScript: Codable, Equatable {
    var bundleID: String
    var scenes: [SceneScript]
    var activeSceneIndex: Int
    var visualOverlays: [SceneVisualOverlay] = []
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
    var visualOverlays: [SceneVisualOverlay] = []
}

struct SceneBundleParsingResult: Equatable {
    var bundleScript: SceneBundleScript
    var activeSceneScript: SceneScript?
    var activeSceneId: String?
    var sceneChunks: [SceneChunk]
    var visualOverlays: [SceneVisualOverlay] = []
    var documentState: ScriptDocumentState
    var diagnostics: ParsingDiagnostics
    var chunkDiagnostics: [SceneChunkDiagnostics]
    var executionTrace: SceneExecutionTrace?
}
