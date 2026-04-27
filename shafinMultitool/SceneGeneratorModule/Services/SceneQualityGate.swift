//
//  SceneQualityGate.swift
//  shafinMultitool
//
//  Created on 21.04.2026.
//

import Foundation

final class SceneQualityGate {
    func decide(
        anchors: SourceAnchorBundle,
        providerResult: ScenePlanProviderResult?,
        compiledScript: SceneScript?,
        compileNotes: [String] = [],
        remoteEnabled: Bool
    ) -> SceneRuntimeTrace {
        guard let providerResult else {
            let reasons = mergeReasons(["planner_unavailable"], compileNotes: compileNotes)
            return SceneRuntimeTrace(
                route: .fallbackRuleOnly,
                reasons: reasons,
                anchors: anchors,
                usedLegacyPlanBridge: false,
                clarificationMessage: nil
            )
        }

        let plan = providerResult.plan
        let providerNotes = providerResult.reasonCodes
        var blockingReasons: [String] = []

        if plan.beats.isEmpty || plan.beats.contains(where: { $0.actions.isEmpty }) {
            blockingReasons.append("beat_collapse_or_empty")
        }

        let boundMarkedObjects = Set(plan.referenceBindings.markedObjectIDs)
        let mentionedMarkedObjects = Set(anchors.mentionedMarkedObjects)
        if !mentionedMarkedObjects.isSubset(of: boundMarkedObjects) {
            blockingReasons.append("unresolved_marked_object")
        }
        if boundMarkedObjects.contains(where: { !$0.hasPrefix("object_marked_") }) {
            blockingReasons.append("invalid_marked_object_binding")
        }
        let hallucinatedMarkedObjects = boundMarkedObjects.subtracting(mentionedMarkedObjects)
        if !mentionedMarkedObjects.isEmpty && !hallucinatedMarkedObjects.isEmpty {
            blockingReasons.append("hallucinated_marked_object_binding")
        }

        let actorRefs = Set(plan.actors.map(\.ref))
        if anchors.ordinalMentions.contains("second") && !actorRefs.contains("second") {
            blockingReasons.append("ordinal_ambiguity")
        }
        if anchors.ordinalMentions.contains("third") && !actorRefs.contains("third") {
            blockingReasons.append("ordinal_ambiguity")
        }

        if !anchors.unsupportedActionFlags.isEmpty {
            let hasDescribedAction = plan.beats.flatMap(\.actions).contains(where: { $0.type == .describedAction })
            if !hasDescribedAction {
                blockingReasons.append("unsupported_action_not_preserved")
            }
        }

        if compiledScript == nil {
            blockingReasons.append("compiler_failed")
        }

        if anchors.sameTypeMarkerConflict {
            blockingReasons.append("same_type_marker_conflict")
        }
        if !anchors.lowConfidenceFlags.isEmpty {
            blockingReasons.append(contentsOf: anchors.lowConfidenceFlags.map { "low_confidence:\($0)" })
        }

        if blockingReasons.isEmpty {
            let baseReasons = providerResult.usedLegacySceneScriptBridge ? ["legacy_scene_script_bridge"] : ["local_plan_valid"]
            let reasons = mergeReasons(baseReasons + providerNotes, compileNotes: compileNotes)
            return SceneRuntimeTrace(
                route: .acceptLocal,
                reasons: reasons,
                anchors: anchors,
                usedLegacyPlanBridge: providerResult.usedLegacySceneScriptBridge,
                clarificationMessage: nil
            )
        }

        let clarificationReasons = blockingReasons.filter {
            $0 == "ordinal_ambiguity"
                || $0 == "same_type_marker_conflict"
                || $0 == "low_confidence:ordinal_actor_count_mismatch"
        }
        let route: SceneRouterOutcome
        let routeClarificationMessage: String?
        if !clarificationReasons.isEmpty {
            route = .needsClarification
            routeClarificationMessage = clarificationMessage(for: clarificationReasons)
        } else if remoteEnabled {
            route = .offloadRemote
            routeClarificationMessage = nil
        } else {
            route = .fallbackRuleOnly
            routeClarificationMessage = nil
        }
        let reasons = mergeReasons(blockingReasons + providerNotes, compileNotes: compileNotes)
        return SceneRuntimeTrace(
            route: route,
            reasons: reasons,
            anchors: anchors,
            usedLegacyPlanBridge: providerResult.usedLegacySceneScriptBridge,
            clarificationMessage: routeClarificationMessage
        )
    }

    private func mergeReasons(_ reasons: [String], compileNotes: [String]) -> [String] {
        var merged: [String] = []
        for reason in reasons where !merged.contains(reason) {
            merged.append(reason)
        }
        for note in compileNotes where !merged.contains(note) {
            merged.append(note)
        }
        return merged
    }

    private func clarificationMessage(for reasons: [String]) -> String {
        if reasons.contains("same_type_marker_conflict") {
            return "Уточните, какой именно размеченный объект имеется в виду."
        }
        if reasons.contains("ordinal_ambiguity") {
            return "Уточните, кто из персонажей выполняет действие: первый, второй или третий."
        }
        return "Описание неоднозначно. Нужна короткая конкретизация персонажей или объектов."
    }
}
