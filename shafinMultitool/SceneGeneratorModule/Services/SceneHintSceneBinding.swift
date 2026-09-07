//
//  SceneHintSceneBinding.swift
//  shafinMultitool
//
//  M6-010: binds Scene live hints to the real planned action/entity
//  identities. The binding references ONLY existing parsed-script
//  entity IDs (validated at resolution time — a dangling reference
//  yields nil, never a fabricated name); hints carrying a binding are
//  suppressed when AR tracking posture is unstable, mirroring the
//  capture gating from M6-018.
//

import Foundation

/// Scene-side identity bound to a live hint. All IDs come from the
/// parsed script; names resolve against the same script's rosters.
struct SceneHintBindingPresentation: Equatable {
    let beatID: String
    let actionID: String
    let actorID: String
    let actorName: String
    let targetID: String?
    let targetName: String?
}

enum SceneHintSceneBinding: Sendable {
    /// Resolves the planned-action binding for a live hint. Returns nil
    /// when tracking is unstable, no script exists, the requested beat
    /// is unknown, or the beat/action references unresolved entities —
    /// suppression is honest absence, never a guessed identity.
    static func resolve(
        script: SceneScript?,
        requestedBeatID: String?,
        postureStable: Bool
    ) -> SceneHintBindingPresentation? {
        guard postureStable, let script else { return nil }
        let beat: SceneBeat?
        if let requestedBeatID {
            beat = script.beats.first { $0.id == requestedBeatID }
        } else {
            beat = script.beats.first
        }
        guard let beat, let action = beat.actions.first else { return nil }

        guard let actor = script.actors.first(where: { $0.id == action.actorId }) else {
            return nil
        }
        var targetID: String?
        var targetName: String?
        if let rawTarget = action.target {
            if let targetActor = script.actors.first(where: { $0.id == rawTarget }) {
                targetID = targetActor.id
                targetName = targetActor.name ?? targetActor.id
            } else if let targetObject = script.objects.first(where: { $0.id == rawTarget }) {
                targetID = targetObject.id
                targetName = targetObject.name ?? targetObject.id
            } else {
                // Dangling target: suppress rather than guess.
                return nil
            }
        }
        return SceneHintBindingPresentation(
            beatID: beat.id,
            actionID: action.id,
            actorID: actor.id,
            actorName: actor.name ?? actor.id,
            targetID: targetID,
            targetName: targetName
        )
    }
}
