//
//  ScenePlanning.swift
//  shafinMultitool
//
//  Created on 21.04.2026.
//

import Foundation

typealias SceneRelationType = SpatialRelation.RelationType

struct SourceAnchorBundle: Codable, Equatable {
    var actorCountHint: Int
    var ordinalMentions: [String]
    var mentionedMarkedObjects: [String]
    var objectSurfaceMentions: [String]
    var phaseCues: [String]
    var unsupportedActionFlags: [String]
    var sameTypeMarkerConflict: Bool
    var lowConfidenceFlags: [String]

    static let empty = SourceAnchorBundle(
        actorCountHint: 0,
        ordinalMentions: [],
        mentionedMarkedObjects: [],
        objectSurfaceMentions: [],
        phaseCues: [],
        unsupportedActionFlags: [],
        sameTypeMarkerConflict: false,
        lowConfidenceFlags: []
    )
}

struct ScenePlanIR: Codable, Equatable {
    var actors: [Actor]
    var objects: [Object]
    var beats: [Beat]
    var spatialRelations: [SpatialRelation]
    var referenceBindings: ReferenceBindings

    struct Actor: Codable, Equatable {
        var ref: String
        var type: SceneActor.ActorType
        var name: String?

        init(ref: String, type: SceneActor.ActorType, name: String? = nil) {
            self.ref = ref
            self.type = type
            self.name = name
        }
    }

    struct Object: Codable, Equatable {
        var ref: String
        var type: SceneObject.ObjectType
        var relativePosition: SceneObject.RelativePosition
        var name: String?
        var markedObjectID: String?

        init(
            ref: String,
            type: SceneObject.ObjectType,
            relativePosition: SceneObject.RelativePosition = .unknown,
            name: String? = nil,
            markedObjectID: String? = nil
        ) {
            self.ref = ref
            self.type = type
            self.relativePosition = relativePosition
            self.name = name
            self.markedObjectID = markedObjectID
        }
    }

    struct Beat: Codable, Equatable {
        var ref: String
        var phase: String?
        var actions: [Action]
        var minDuration: Double?

        init(ref: String, phase: String? = nil, actions: [Action], minDuration: Double? = nil) {
            self.ref = ref
            self.phase = phase
            self.actions = actions
            self.minDuration = minDuration
        }
    }

    struct Action: Codable, Equatable {
        var actorRef: String
        var type: SceneAction.ActionType
        var targetRef: String?
        var direction: SceneAction.Direction?
        var modifier: SceneAction.ActionModifier?
        var resultingPose: ActorPose?
        var holdingObjectRef: String?
        var dialogue: String?
        var fallbackText: String?
        var sourceText: String?

        init(
            actorRef: String,
            type: SceneAction.ActionType,
            targetRef: String? = nil,
            direction: SceneAction.Direction? = nil,
            modifier: SceneAction.ActionModifier? = nil,
            resultingPose: ActorPose? = nil,
            holdingObjectRef: String? = nil,
            dialogue: String? = nil,
            fallbackText: String? = nil,
            sourceText: String? = nil
        ) {
            self.actorRef = actorRef
            self.type = type
            self.targetRef = targetRef
            self.direction = direction
            self.modifier = modifier
            self.resultingPose = resultingPose
            self.holdingObjectRef = holdingObjectRef
            self.dialogue = dialogue
            self.fallbackText = fallbackText
            self.sourceText = sourceText
        }
    }

    struct SpatialRelation: Codable, Equatable {
        var ref: String
        var subjectRef: String
        var relation: SceneRelationType
        var objectRef: String

        init(ref: String, subjectRef: String, relation: SceneRelationType, objectRef: String) {
            self.ref = ref
            self.subjectRef = subjectRef
            self.relation = relation
            self.objectRef = objectRef
        }
    }

    struct ReferenceBindings: Codable, Equatable {
        var actorBindings: [String: String]
        var markedObjectIDs: [String]
        var aliasToObjectRef: [String: String]

        init(
            actorBindings: [String: String] = [:],
            markedObjectIDs: [String] = [],
            aliasToObjectRef: [String: String] = [:]
        ) {
            self.actorBindings = actorBindings
            self.markedObjectIDs = markedObjectIDs
            self.aliasToObjectRef = aliasToObjectRef
        }
    }

    static let empty = ScenePlanIR(
        actors: [],
        objects: [],
        beats: [],
        spatialRelations: [],
        referenceBindings: .init()
    )
}

enum SceneRouterOutcome: String, Equatable {
    case acceptLocal = "accept_local"
    case fallbackRuleOnly = "fallback_rule_only"
    case offloadRemote = "offload_remote"
    case needsClarification = "needs_clarification"
}

struct SceneRuntimeTrace: Equatable {
    var route: SceneRouterOutcome
    var reasons: [String]
    var anchors: SourceAnchorBundle
    var usedLegacyPlanBridge: Bool
    var clarificationMessage: String?
}

protocol LocalScenePlanProvider {
    func generatePlan(
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle,
        state: SceneChunkState?
    ) -> ScenePlanProviderResult?

    func generatePlanAsync(
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle,
        state: SceneChunkState?
    ) async -> ScenePlanProviderResult?
}

protocol RemoteScenePlanProvider {
    func generateRemotePlan(
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle,
        state: SceneChunkState?
    ) async -> ScenePlanProviderResult?
}

struct ScenePlanProviderResult {
    let plan: ScenePlanIR
    let usedLegacySceneScriptBridge: Bool
    let reasonCodes: [String]

    init(plan: ScenePlanIR, usedLegacySceneScriptBridge: Bool, reasonCodes: [String] = []) {
        self.plan = plan
        self.usedLegacySceneScriptBridge = usedLegacySceneScriptBridge
        self.reasonCodes = reasonCodes
    }
}

enum ScenePlanCompilerError: Error, LocalizedError, Equatable {
    case missingActorRef(String)
    case missingObjectRef(String)
    case missingTarget(String)
    case invalidPlan(String)

    var errorDescription: String? {
        switch self {
        case .missingActorRef(let ref):
            return "Unknown actorRef: \(ref)"
        case .missingObjectRef(let ref):
            return "Unknown objectRef: \(ref)"
        case .missingTarget(let ref):
            return "Missing required targetRef for: \(ref)"
        case .invalidPlan(let reason):
            return reason
        }
    }
}
