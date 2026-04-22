//
//  ScenePlanCompiler.swift
//  shafinMultitool
//
//  Created on 21.04.2026.
//

import Foundation

final class ScenePlanCompiler {
    private let targetRequiredTypes: Set<SceneAction.ActionType> = [
        .lookAt, .pickUp, .open, .close, .approach, .putDown, .give, .passBy, .stop
    ]
    private let targetlessActionDowngradedCode = "v8.targetless_action_downgraded"
    private let invalidSpatialRelationSkippedCode = "v8.invalid_spatial_relation_skipped"

    func compile(
        plan: ScenePlanIR,
        originalDescription: String,
        topLevelMetadata: (sceneHeading: String?, locationName: String?, interiorExterior: String?, timeOfDay: String?) = (nil, nil, nil, nil)
    ) throws -> SceneScript {
        try compileWithNotes(
            plan: plan,
            originalDescription: originalDescription,
            topLevelMetadata: topLevelMetadata
        ).script
    }

    func compileWithNotes(
        plan: ScenePlanIR,
        originalDescription: String,
        topLevelMetadata: (sceneHeading: String?, locationName: String?, interiorExterior: String?, timeOfDay: String?) = (nil, nil, nil, nil)
    ) throws -> (script: SceneScript, notes: [String]) {
        guard !plan.actors.isEmpty else {
            throw ScenePlanCompilerError.invalidPlan("ScenePlanIR must contain at least one actor")
        }

        var compileNotes: [String] = []
        let actorIdMap = try compileActorIDMap(plan.actors)
        let objectIdMap = try compileObjectIDMap(plan.objects)
        let actors = compileActors(plan.actors, actorIdMap: actorIdMap)
        let objects = compileObjects(plan.objects, objectIdMap: objectIdMap)
        let beats = try compileBeats(
            plan.beats,
            actorIdMap: actorIdMap,
            objectIdMap: objectIdMap,
            compileNotes: &compileNotes
        )
        let relations = try compileRelations(
            plan.spatialRelations,
            actorIdMap: actorIdMap,
            objectIdMap: objectIdMap,
            compileNotes: &compileNotes
        )

        let script = SceneScript(
            sceneHeading: topLevelMetadata.sceneHeading,
            locationName: topLevelMetadata.locationName,
            interiorExterior: topLevelMetadata.interiorExterior,
            timeOfDay: topLevelMetadata.timeOfDay,
            actors: actors,
            objects: objects,
            beats: beats,
            spatialRelations: relations,
            originalDescription: originalDescription
        )
        return (script: script, notes: uniqueNotes(compileNotes))
    }

    private func compileActorIDMap(_ actors: [ScenePlanIR.Actor]) throws -> [String: String] {
        let canonicalRefs = ["first", "second", "third"]
        var map: [String: String] = [:]
        let seen = Set(actors.map(\.ref))
        if seen.contains("first") {
            var nextIndex = 1
            for ref in canonicalRefs where seen.contains(ref) {
                map[ref] = "actor_\(nextIndex)"
                nextIndex += 1
            }

            for actor in actors where map[actor.ref] == nil {
                map[actor.ref] = "actor_\(nextIndex)"
                nextIndex += 1
            }
        } else {
            for (index, actor) in actors.enumerated() {
                map[actor.ref] = "actor_\(index + 1)"
            }
        }
        return map
    }

    private func compileObjectIDMap(_ objects: [ScenePlanIR.Object]) throws -> [String: String] {
        var map: [String: String] = [:]
        var nextUnmarked = 1
        let sortedObjects = objects.sorted { lhs, rhs in
            if lhs.ref.hasPrefix("object_marked_") && !rhs.ref.hasPrefix("object_marked_") {
                return true
            }
            if !lhs.ref.hasPrefix("object_marked_") && rhs.ref.hasPrefix("object_marked_") {
                return false
            }
            return lhs.ref < rhs.ref
        }

        for object in sortedObjects {
            if object.ref.hasPrefix("object_marked_") {
                map[object.ref] = object.markedObjectID ?? object.ref
            } else {
                map[object.ref] = "object_\(nextUnmarked)"
                nextUnmarked += 1
            }
        }
        return map
    }

    private func compileActors(_ actors: [ScenePlanIR.Actor], actorIdMap: [String: String]) -> [SceneActor] {
        actors.compactMap { actor in
            guard let actorID = actorIdMap[actor.ref] else { return nil }
            return SceneActor(id: actorID, type: actor.type, name: actor.name)
        }.sorted { $0.id < $1.id }
    }

    private func compileObjects(_ objects: [ScenePlanIR.Object], objectIdMap: [String: String]) -> [SceneObject] {
        objects.compactMap { object in
            guard let objectID = objectIdMap[object.ref] else { return nil }
            return SceneObject(
                id: objectID,
                type: object.type,
                name: object.name,
                detectedPosition: nil,
                relativePosition: object.relativePosition
            )
        }.sorted {
            if $0.id.hasPrefix("object_marked_") && !$1.id.hasPrefix("object_marked_") {
                return true
            }
            if !$0.id.hasPrefix("object_marked_") && $1.id.hasPrefix("object_marked_") {
                return false
            }
            return $0.id < $1.id
        }
    }

    private func compileBeats(
        _ beats: [ScenePlanIR.Beat],
        actorIdMap: [String: String],
        objectIdMap: [String: String],
        compileNotes: inout [String]
    ) throws -> [SceneBeat] {
        guard !beats.isEmpty else {
            throw ScenePlanCompilerError.invalidPlan("ScenePlanIR must contain at least one beat")
        }

        return try beats.enumerated().map { beatIndex, beat in
            guard !beat.actions.isEmpty else {
                throw ScenePlanCompilerError.invalidPlan("Beat \(beat.ref) must contain at least one action")
            }

            let actions = try beat.actions.enumerated().map { actionIndex, action in
                let actorID = try resolveActorRef(action.actorRef, actorIdMap: actorIdMap)
                let targetID = try resolveTargetRef(
                    action.targetRef,
                    actorIdMap: actorIdMap,
                    objectIdMap: objectIdMap,
                    requireTarget: false
                )
                let compiledActionType: SceneAction.ActionType
                if targetRequiredTypes.contains(action.type), targetID == nil {
                    compiledActionType = .stand
                    appendNote(targetlessActionDowngradedCode, to: &compileNotes)
                } else {
                    compiledActionType = action.type
                }
                let holdingObjectID = try resolveOptionalObjectRef(action.holdingObjectRef, objectIdMap: objectIdMap)

                return SceneAction(
                    id: "action_\(beatIndex + 1)_\(actionIndex + 1)",
                    actorId: actorID,
                    type: compiledActionType,
                    target: targetID,
                    direction: action.direction,
                    modifier: action.modifier,
                    resultingPose: action.resultingPose ?? defaultPose(for: compiledActionType),
                    holdingObject: holdingObjectID,
                    dialogue: action.dialogue,
                    fallbackText: action.fallbackText,
                    sourceText: action.sourceText
                )
            }

            return SceneBeat(
                id: beat.ref.isEmpty ? "beat_\(beatIndex + 1)" : beat.ref,
                actions: actions,
                camera: nil,
                minDuration: beat.minDuration
            )
        }
    }

    private func compileRelations(
        _ relations: [ScenePlanIR.SpatialRelation],
        actorIdMap: [String: String],
        objectIdMap: [String: String],
        compileNotes: inout [String]
    ) throws -> [SpatialRelation] {
        try relations.enumerated().compactMap { index, relation in
            let subject = try resolveTargetRef(
                relation.subjectRef,
                actorIdMap: actorIdMap,
                objectIdMap: objectIdMap,
                requireTarget: false
            )
            let object = try resolveTargetRef(
                relation.objectRef,
                actorIdMap: actorIdMap,
                objectIdMap: objectIdMap,
                requireTarget: false
            )
            guard let subject, let object else {
                appendNote(invalidSpatialRelationSkippedCode, to: &compileNotes)
                return nil
            }
            return SpatialRelation(
                id: relation.ref.isEmpty ? "rel_\(index + 1)" : relation.ref,
                subject: subject,
                relation: relation.relation,
                object: object
            )
        }
    }

    private func resolveActorRef(_ ref: String, actorIdMap: [String: String]) throws -> String {
        guard let actorID = actorIdMap[ref] else {
            throw ScenePlanCompilerError.missingActorRef(ref)
        }
        return actorID
    }

    private func resolveOptionalObjectRef(_ ref: String?, objectIdMap: [String: String]) throws -> String? {
        guard let ref, !ref.isEmpty else { return nil }
        guard let objectID = objectIdMap[ref] else {
            throw ScenePlanCompilerError.missingObjectRef(ref)
        }
        return objectID
    }

    private func resolveTargetRef(
        _ ref: String?,
        actorIdMap: [String: String],
        objectIdMap: [String: String],
        requireTarget: Bool
    ) throws -> String? {
        guard let ref, !ref.isEmpty else {
            if requireTarget {
                throw ScenePlanCompilerError.missingTarget("required target")
            }
            return nil
        }

        if let actorID = actorIdMap[ref] {
            return actorID
        }
        if let objectID = objectIdMap[ref] {
            return objectID
        }
        if requireTarget {
            throw ScenePlanCompilerError.missingTarget(ref)
        }
        return nil
    }

    private func defaultPose(for actionType: SceneAction.ActionType) -> ActorPose {
        switch actionType {
        case .walk, .approach, .passBy, .enter, .exit:
            return .walking
        case .run:
            return .running
        case .sit:
            return .sitting
        case .lieDown:
            return .lying
        case .crouch:
            return .crouching
        default:
            return .standing
        }
    }

    private func appendNote(_ note: String, to notes: inout [String]) {
        guard !notes.contains(note) else { return }
        notes.append(note)
    }

    private func uniqueNotes(_ notes: [String]) -> [String] {
        var result: [String] = []
        for note in notes where !result.contains(note) {
            result.append(note)
        }
        return result
    }
}
