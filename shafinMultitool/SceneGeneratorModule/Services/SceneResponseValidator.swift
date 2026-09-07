//
//  SceneResponseValidator.swift
//  shafinMultitool
//
//  M5-026: explicit response validation before any generator output
//  reaches project state. The quality gate checks plan shape and
//  routing; this validator checks the compiled SceneScript itself:
//  schema/entity references, chronology, action targets, and
//  marked-object bindings. Invalid outputs are rejected with typed
//  reasons — never silently repaired (M5-027 owns the repair
//  boundary) and never partially committed.
//

import Foundation

/// Typed validation failures for a compiled generator response.
enum SceneResponseIssue: String, Equatable, Sendable {
    case emptyBeats
    case emptyBeatActions
    case danglingActorReference
    case danglingObjectReference
    case danglingActionTarget
    case danglingHoldingReference
    case duplicateEntityID
    case unresolvedMarkedBinding
    case invalidMarkedBinding
    case beatOrderViolation
}

/// Fail-closed validator over a compiled SceneScript plus the binding
/// snapshot the output was produced against.
enum SceneResponseValidator: Sendable {
    /// Validates the script. Returns the ordered issues (empty = valid).
    /// Chronology check: beat IDs must carry non-decreasing source
    /// ordinals where present (`beat_<n>`); beats without ordinals keep
    /// their relative order and never fail.
    static func validate(
        script: SceneScript,
        markedObjectIDs: Set<String> = [],
        mentionedMarkedObjects: Set<String> = []
    ) -> [SceneResponseIssue] {
        var issues: [SceneResponseIssue] = []
        func add(_ issue: SceneResponseIssue) {
            if !issues.contains(issue) { issues.append(issue) }
        }

        if script.beats.isEmpty { add(.emptyBeats) }
        for beat in script.beats where beat.actions.isEmpty { add(.emptyBeatActions) }

        var seenIDs = Set<String>()
        for actor in script.actors {
            if !seenIDs.insert(actor.id).inserted { add(.duplicateEntityID) }
        }
        for object in script.objects {
            if !seenIDs.insert(object.id).inserted { add(.duplicateEntityID) }
        }
        for beat in script.beats {
            if !seenIDs.insert(beat.id).inserted { add(.duplicateEntityID) }
            for action in beat.actions {
                if !seenIDs.insert(action.id).inserted { add(.duplicateEntityID) }
            }
        }

        let actorIDs = Set(script.actors.map(\.id))
        let objectIDs = Set(script.objects.map(\.id))
        for beat in script.beats {
            for action in beat.actions {
                if !actorIDs.contains(action.actorId) { add(.danglingActorReference) }
                if let target = action.target,
                   !actorIDs.contains(target), !objectIDs.contains(target) {
                    add(.danglingActionTarget)
                }
                if let holding = action.holdingObject, !objectIDs.contains(holding) {
                    add(.danglingHoldingReference)
                }
            }
        }
        for relation in script.spatialRelations {
            if !actorIDs.contains(relation.subject), !objectIDs.contains(relation.subject) {
                add(.danglingObjectReference)
            }
            if !actorIDs.contains(relation.object), !objectIDs.contains(relation.object) {
                add(.danglingObjectReference)
            }
        }

        let boundMarked = Set(
            script.objects.map(\.id).filter { $0.hasPrefix("object_marked_") }
        )
        for marked in boundMarked where !markedObjectIDs.contains(marked) {
            add(.unresolvedMarkedBinding)
        }
        for mentioned in mentionedMarkedObjects where !boundMarked.contains(mentioned) {
            add(.unresolvedMarkedBinding)
        }
        if boundMarked.contains(where: { !$0.hasPrefix("object_marked_") }) {
            add(.invalidMarkedBinding)
        }

        var lastOrdinal: Int?
        for beat in script.beats {
            guard let ordinal = SceneResponseValidator.ordinal(of: beat.id) else { continue }
            if let last = lastOrdinal, ordinal < last {
                add(.beatOrderViolation)
                break
            }
            lastOrdinal = ordinal
        }

        return issues
    }

    private static func ordinal(of beatID: String) -> Int? {
        guard beatID.hasPrefix("beat_") else { return nil }
        return Int(beatID.dropFirst("beat_".count))
    }
}
