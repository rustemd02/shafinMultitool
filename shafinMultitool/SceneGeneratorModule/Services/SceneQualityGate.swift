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
        remoteEnabled: Bool
    ) -> SceneRuntimeTrace {
        guard let providerResult else {
            return SceneRuntimeTrace(
                route: .fallbackRuleOnly,
                reasons: ["planner_unavailable"],
                anchors: anchors,
                usedLegacyPlanBridge: false,
                clarificationMessage: nil
            )
        }

        let plan = providerResult.plan
        var reasons: [String] = []

        if plan.beats.isEmpty || plan.beats.contains(where: { $0.actions.isEmpty }) {
            reasons.append("beat_collapse_or_empty")
        }

        let boundMarkedObjects = Set(plan.referenceBindings.markedObjectIDs)
        let mentionedMarkedObjects = Set(anchors.mentionedMarkedObjects)
        if !mentionedMarkedObjects.isSubset(of: boundMarkedObjects) {
            reasons.append("unresolved_marked_object")
        }
        if boundMarkedObjects.contains(where: { !$0.hasPrefix("object_marked_") }) {
            reasons.append("invalid_marked_object_binding")
        }
        let hallucinatedMarkedObjects = boundMarkedObjects.subtracting(mentionedMarkedObjects)
        if !mentionedMarkedObjects.isEmpty && !hallucinatedMarkedObjects.isEmpty {
            reasons.append("hallucinated_marked_object_binding")
        }

        let actorRefs = Set(plan.actors.map(\.ref))
        if anchors.ordinalMentions.contains("second") && !actorRefs.contains("second") {
            reasons.append("ordinal_ambiguity")
        }
        if anchors.ordinalMentions.contains("third") && !actorRefs.contains("third") {
            reasons.append("ordinal_ambiguity")
        }

        if !anchors.unsupportedActionFlags.isEmpty {
            let hasDescribedAction = plan.beats.flatMap(\.actions).contains(where: { $0.type == .describedAction })
            if !hasDescribedAction {
                reasons.append("unsupported_action_not_preserved")
            }
        }

        if compiledScript == nil {
            reasons.append("compiler_failed")
        }

        if anchors.sameTypeMarkerConflict {
            reasons.append("same_type_marker_conflict")
        }
        if !anchors.lowConfidenceFlags.isEmpty {
            reasons.append(contentsOf: anchors.lowConfidenceFlags.map { "low_confidence:\($0)" })
        }

        if reasons.isEmpty {
            return SceneRuntimeTrace(
                route: .acceptLocal,
                reasons: providerResult.usedLegacySceneScriptBridge ? ["legacy_scene_script_bridge"] : ["local_plan_valid"],
                anchors: anchors,
                usedLegacyPlanBridge: providerResult.usedLegacySceneScriptBridge,
                clarificationMessage: nil
            )
        }

        let clarificationReasons = reasons.filter {
            $0 == "ordinal_ambiguity"
                || $0 == "same_type_marker_conflict"
                || $0.hasPrefix("low_confidence:")
        }
        let route: SceneRouterOutcome
        let clarificationMessage: String?
        if !clarificationReasons.isEmpty {
            route = .needsClarification
            clarificationMessage = clarificationMessage(for: clarificationReasons)
        } else if remoteEnabled {
            route = .offloadRemote
            clarificationMessage = nil
        } else {
            route = .fallbackRuleOnly
            clarificationMessage = nil
        }
        return SceneRuntimeTrace(
            route: route,
            reasons: reasons,
            anchors: anchors,
            usedLegacyPlanBridge: providerResult.usedLegacySceneScriptBridge,
            clarificationMessage: clarificationMessage
        )
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
