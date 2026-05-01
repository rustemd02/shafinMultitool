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

struct SceneV9SlotCatalog: Codable, Equatable {
    struct ActorSlot: Codable, Equatable {
        var slotID: String
        var ref: String
        var type: SceneActor.ActorType
        var name: String?
    }

    struct ObjectSlot: Codable, Equatable {
        var slotID: String
        var ref: String
        var type: SceneObject.ObjectType
        var relativePosition: SceneObject.RelativePosition
        var markedObjectID: String?
        var name: String?
    }

    struct BeatSlot: Codable, Equatable {
        var slotID: String
        var beatRef: String
        var phaseHint: String?
        var order: Int
        var minDuration: Double?
    }

    struct RelationHint: Codable, Equatable {
        var subjectSlot: String
        var relation: SceneRelationType
        var objectSlot: String
    }

    var contractVersion: String
    var actorSlots: [ActorSlot]
    var objectSlots: [ObjectSlot]
    var markedObjectSlots: [String]
    var beatSlots: [BeatSlot]
    var actionTypes: [SceneAction.ActionType]
    var relationHints: [RelationHint]

    static let empty = SceneV9SlotCatalog(
        contractVersion: "sg_v9_slot_catalog_v1",
        actorSlots: [],
        objectSlots: [],
        markedObjectSlots: [],
        beatSlots: [],
        actionTypes: [],
        relationHints: []
    )
}

struct SceneV9EventTable: Codable, Equatable {
    struct EventRow: Codable, Equatable {
        var rowID: String
        var beatSlot: String
        var actorSlot: String
        var actionType: SceneAction.ActionType
        var targetSlot: String?
        var holdingObjectSlot: String?
        var dialogueText: String?
        var describedActionText: String?
        var sourceSpan: String?
        var confidence: Double?

        private enum CodingKeys: String, CodingKey {
            case rowID
            case rowId
            case beatSlot
            case actorSlot
            case actionType
            case targetSlot
            case holdingObjectSlot
            case dialogueText
            case describedActionText
            case sourceSpan
            case confidence
        }

        init(
            rowID: String,
            beatSlot: String,
            actorSlot: String,
            actionType: SceneAction.ActionType,
            targetSlot: String? = nil,
            holdingObjectSlot: String? = nil,
            dialogueText: String? = nil,
            describedActionText: String? = nil,
            sourceSpan: String? = nil,
            confidence: Double? = nil
        ) {
            self.rowID = rowID
            self.beatSlot = beatSlot
            self.actorSlot = actorSlot
            self.actionType = actionType
            self.targetSlot = targetSlot
            self.holdingObjectSlot = holdingObjectSlot
            self.dialogueText = dialogueText
            self.describedActionText = describedActionText
            self.sourceSpan = sourceSpan
            self.confidence = confidence
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let rowIDFromCamel = try container.decodeIfPresent(String.self, forKey: .rowId)
            let rowIDFromLegacy = try container.decodeIfPresent(String.self, forKey: .rowID)
            self.rowID = rowIDFromCamel ?? rowIDFromLegacy ?? ""
            self.beatSlot = try container.decode(String.self, forKey: .beatSlot)
            self.actorSlot = try container.decode(String.self, forKey: .actorSlot)
            self.actionType = try container.decode(SceneAction.ActionType.self, forKey: .actionType)
            self.targetSlot = try container.decodeIfPresent(String.self, forKey: .targetSlot)
            self.holdingObjectSlot = try container.decodeIfPresent(String.self, forKey: .holdingObjectSlot)
            self.dialogueText = try container.decodeIfPresent(String.self, forKey: .dialogueText)
            self.describedActionText = try container.decodeIfPresent(String.self, forKey: .describedActionText)
            self.sourceSpan = try container.decodeIfPresent(String.self, forKey: .sourceSpan)
            self.confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(rowID, forKey: .rowId)
            try container.encode(beatSlot, forKey: .beatSlot)
            try container.encode(actorSlot, forKey: .actorSlot)
            try container.encode(actionType, forKey: .actionType)
            try container.encodeIfPresent(targetSlot, forKey: .targetSlot)
            try container.encodeIfPresent(holdingObjectSlot, forKey: .holdingObjectSlot)
            try container.encodeIfPresent(dialogueText, forKey: .dialogueText)
            try container.encodeIfPresent(describedActionText, forKey: .describedActionText)
            try container.encodeIfPresent(sourceSpan, forKey: .sourceSpan)
            try container.encodeIfPresent(confidence, forKey: .confidence)
        }
    }

    var contractVersion: String
    var rows: [EventRow]

    static let empty = SceneV9EventTable(contractVersion: "sg_v9_event_table_v1", rows: [])
}

struct SceneV9PatchOps: Codable, Equatable {
    struct PatchOp: Codable, Equatable {
        enum Operation: String, Codable {
            case replace
            case add
            case delete
        }

        var op: Operation
        var rowID: String
        var field: String?
        var value: String?

        private enum CodingKeys: String, CodingKey {
            case op
            case rowID
            case rowId
            case field
            case value
        }

        init(op: Operation, rowID: String, field: String? = nil, value: String? = nil) {
            self.op = op
            self.rowID = rowID
            self.field = field
            self.value = value
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.op = try container.decode(Operation.self, forKey: .op)
            let rowIDFromCamel = try container.decodeIfPresent(String.self, forKey: .rowId)
            let rowIDFromLegacy = try container.decodeIfPresent(String.self, forKey: .rowID)
            self.rowID = rowIDFromCamel ?? rowIDFromLegacy ?? ""
            self.field = try container.decodeIfPresent(String.self, forKey: .field)
            self.value = try container.decodeIfPresent(String.self, forKey: .value)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(op, forKey: .op)
            try container.encode(rowID, forKey: .rowId)
            try container.encodeIfPresent(field, forKey: .field)
            try container.encodeIfPresent(value, forKey: .value)
        }
    }

    var contractVersion: String
    var ops: [PatchOp]

    static let empty = SceneV9PatchOps(contractVersion: "sg_v9_patch_ops_v1", ops: [])
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

    func generateEventTable(
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle,
        state: SceneChunkState?,
        slotCatalog: SceneV9SlotCatalog
    ) -> SceneV9EventProviderResult?

    func generateEventTableAsync(
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle,
        state: SceneChunkState?,
        slotCatalog: SceneV9SlotCatalog
    ) async -> SceneV9EventProviderResult?

    func generateEventPatchOps(
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle,
        state: SceneChunkState?,
        slotCatalog: SceneV9SlotCatalog,
        eventTable: SceneV9EventTable,
        verifierIssues: [String]
    ) -> SceneV9PatchOps?

    func generateEventPatchOpsAsync(
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle,
        state: SceneChunkState?,
        slotCatalog: SceneV9SlotCatalog,
        eventTable: SceneV9EventTable,
        verifierIssues: [String]
    ) async -> SceneV9PatchOps?
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

struct SceneV9EventProviderResult {
    let slotCatalog: SceneV9SlotCatalog
    let eventTable: SceneV9EventTable
    let patchOps: SceneV9PatchOps?
    let reasonCodes: [String]

    init(
        slotCatalog: SceneV9SlotCatalog,
        eventTable: SceneV9EventTable,
        patchOps: SceneV9PatchOps? = nil,
        reasonCodes: [String] = []
    ) {
        self.slotCatalog = slotCatalog
        self.eventTable = eventTable
        self.patchOps = patchOps
        self.reasonCodes = reasonCodes
    }
}

extension LocalScenePlanProvider {
    func generateEventTable(
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle,
        state: SceneChunkState?,
        slotCatalog: SceneV9SlotCatalog
    ) -> SceneV9EventProviderResult? {
        nil
    }

    func generateEventTableAsync(
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle,
        state: SceneChunkState?,
        slotCatalog: SceneV9SlotCatalog
    ) async -> SceneV9EventProviderResult? {
        nil
    }

    func generateEventPatchOps(
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle,
        state: SceneChunkState?,
        slotCatalog: SceneV9SlotCatalog,
        eventTable: SceneV9EventTable,
        verifierIssues: [String]
    ) -> SceneV9PatchOps? {
        nil
    }

    func generateEventPatchOpsAsync(
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle,
        state: SceneChunkState?,
        slotCatalog: SceneV9SlotCatalog,
        eventTable: SceneV9EventTable,
        verifierIssues: [String]
    ) async -> SceneV9PatchOps? {
        nil
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
