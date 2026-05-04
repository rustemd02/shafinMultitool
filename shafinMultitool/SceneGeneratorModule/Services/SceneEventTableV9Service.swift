//
//  SceneEventTableV9Service.swift
//  shafinMultitool
//
//  Created on 30.04.2026.
//

import Foundation

struct SceneV9VerificationResult {
    var repairedEventTable: SceneV9EventTable
    var reasonCodes: [String]
}

final class SceneEventTableV9Service {
    struct RuntimeGuardrails {
        var maxRows: Int
        var maxActors: Int
        var maxObjects: Int
        var maxBeats: Int
        var wallClockBudgetMs: Double
    }

    private let targetRequiredTypes: Set<SceneAction.ActionType> = [
        .lookAt, .pickUp, .open, .close, .approach, .putDown, .give, .passBy, .stop
    ]
    private let fixableVerifierReasonCodes: Set<String> = [
        "v9.beat_slot_mismatch",
        "v9.action_type_repaired",
        "v9.target_slot_repaired",
        "v9.holding_slot_repaired",
        "v9.targetless_event_repaired",
        "v9.described_text_repaired",
        "v9.missing_event_for_beat",
        "v9.wrong_target_slot",
        "v9.collective_action_not_expanded",
        "v9.dialogue_action_collapsed",
        "v9.unsupported_action_missing_text",
    ]

    func buildSlotCatalog(from plan: ScenePlanIR) -> SceneV9SlotCatalog {
        let actorSlots = plan.actors.enumerated().map { index, actor in
            SceneV9SlotCatalog.ActorSlot(
                slotID: "actor_slot_\(index + 1)",
                ref: actor.ref,
                type: actor.type,
                name: actor.name
            )
        }

        let objectSlots = plan.objects.enumerated().map { index, object in
            SceneV9SlotCatalog.ObjectSlot(
                slotID: "object_slot_\(index + 1)",
                ref: object.ref,
                type: object.type,
                relativePosition: object.relativePosition,
                markedObjectID: object.markedObjectID,
                name: object.name
            )
        }

        let beatSlots = plan.beats.enumerated().map { index, beat in
            SceneV9SlotCatalog.BeatSlot(
                slotID: "beat_slot_\(index + 1)",
                beatRef: beat.ref,
                phaseHint: beat.phase,
                order: index + 1,
                minDuration: beat.minDuration
            )
        }

        let actorRefToSlot = Dictionary(uniqueKeysWithValues: actorSlots.map { ($0.ref, $0.slotID) })
        let objectRefToSlot = Dictionary(uniqueKeysWithValues: objectSlots.map { ($0.ref, $0.slotID) })
        let relationHints = plan.spatialRelations.compactMap { relation -> SceneV9SlotCatalog.RelationHint? in
            let subjectSlot = actorRefToSlot[relation.subjectRef] ?? objectRefToSlot[relation.subjectRef]
            let objectSlot = actorRefToSlot[relation.objectRef] ?? objectRefToSlot[relation.objectRef]
            guard let subjectSlot, let objectSlot else { return nil }
            return SceneV9SlotCatalog.RelationHint(
                subjectSlot: subjectSlot,
                relation: relation.relation,
                objectSlot: objectSlot
            )
        }

        let markedSlots = objectSlots
            .filter { ($0.markedObjectID ?? $0.ref).hasPrefix("object_marked_") }
            .map(\.slotID)

        return SceneV9SlotCatalog(
            contractVersion: "sg_v9_slot_catalog_v1",
            actorSlots: actorSlots,
            objectSlots: objectSlots,
            markedObjectSlots: markedSlots,
            beatSlots: beatSlots,
            actionTypes: SceneAction.ActionType.allCases,
            relationHints: relationHints
        )
    }

    func buildEventTable(from plan: ScenePlanIR, slotCatalog: SceneV9SlotCatalog) -> SceneV9EventTable {
        let actorRefToSlot = Dictionary(uniqueKeysWithValues: slotCatalog.actorSlots.map { ($0.ref, $0.slotID) })
        let objectRefToSlot = Dictionary(uniqueKeysWithValues: slotCatalog.objectSlots.map { ($0.ref, $0.slotID) })
        let beatRefToSlot = Dictionary(uniqueKeysWithValues: slotCatalog.beatSlots.map { ($0.beatRef, $0.slotID) })

        var rows: [SceneV9EventTable.EventRow] = []
        var rowIndex = 1
        for beat in plan.beats {
            let beatSlot = beatRefToSlot[beat.ref] ?? "beat_slot_\(max(1, rowIndex))"
            for action in beat.actions {
                guard let actorSlot = actorRefToSlot[action.actorRef] else { continue }
                let targetSlot = action.targetRef.flatMap { actorRefToSlot[$0] ?? objectRefToSlot[$0] }
                let holdingSlot = action.holdingObjectRef.flatMap { objectRefToSlot[$0] }
                rows.append(
                    SceneV9EventTable.EventRow(
                        rowID: "row_\(rowIndex)",
                        beatSlot: beatSlot,
                        actorSlot: actorSlot,
                        actionType: action.type,
                        targetSlot: targetSlot,
                        holdingObjectSlot: holdingSlot,
                        dialogueText: action.dialogue,
                        describedActionText: action.type == .describedAction ? (action.fallbackText ?? action.sourceText) : nil,
                        sourceSpan: action.sourceText,
                        confidence: 1.0
                    )
                )
                rowIndex += 1
            }
        }
        return SceneV9EventTable(contractVersion: "sg_v9_event_table_v1", rows: rows)
    }

    func verifyAndRepair(
        eventTable: SceneV9EventTable,
        slotCatalog: SceneV9SlotCatalog
    ) -> SceneV9VerificationResult {
        let actorSlots = Set(slotCatalog.actorSlots.map(\.slotID))
        let objectSlots = Set(slotCatalog.objectSlots.map(\.slotID))
        let beatSlots = Set(slotCatalog.beatSlots.map(\.slotID))
        let actionTypes = Set(slotCatalog.actionTypes)

        var seen: Set<String> = []
        var repairedRows: [SceneV9EventTable.EventRow] = []
        var reasonCodes: [String] = []

        for row in eventTable.rows {
            var current = row
            if current.rowID.isEmpty || seen.contains(current.rowID) {
                appendReason("v9.duplicate_row_dropped", to: &reasonCodes)
                continue
            }
            seen.insert(current.rowID)

            if !beatSlots.contains(current.beatSlot), let fallback = slotCatalog.beatSlots.first?.slotID {
                current.beatSlot = fallback
                appendReason("v9.beat_slot_mismatch", to: &reasonCodes)
            }

            if !actorSlots.contains(current.actorSlot) {
                appendReason("v9.unknown_slot_blocked", to: &reasonCodes)
                continue
            }

            if !actionTypes.contains(current.actionType) {
                current.actionType = .describedAction
                if (current.describedActionText ?? "").isEmpty {
                    current.describedActionText = current.sourceSpan ?? "described_action"
                }
                appendReason("v9.action_type_repaired", to: &reasonCodes)
            }

            if let targetSlot = current.targetSlot, !targetSlot.isEmpty {
                if !actorSlots.contains(targetSlot) && !objectSlots.contains(targetSlot) {
                    current.targetSlot = nil
                    appendReason("v9.target_slot_repaired", to: &reasonCodes)
                }
            }

            if let holdingSlot = current.holdingObjectSlot, !holdingSlot.isEmpty, !objectSlots.contains(holdingSlot) {
                current.holdingObjectSlot = nil
                appendReason("v9.holding_slot_repaired", to: &reasonCodes)
            }

            if targetRequiredTypes.contains(current.actionType), current.targetSlot == nil {
                current.actionType = .stand
                appendReason("v9.targetless_event_repaired", to: &reasonCodes)
            }

            if current.actionType == .describedAction,
               (current.describedActionText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                current.describedActionText = current.sourceSpan ?? "described_action"
                appendReason("v9.described_text_repaired", to: &reasonCodes)
            }
            repairedRows.append(current)
        }

        return SceneV9VerificationResult(
            repairedEventTable: SceneV9EventTable(contractVersion: eventTable.contractVersion, rows: repairedRows),
            reasonCodes: reasonCodes
        )
    }

    func compileToPlan(
        eventTable: SceneV9EventTable,
        slotCatalog: SceneV9SlotCatalog,
        originalPlan: ScenePlanIR
    ) -> ScenePlanIR {
        let actorSlotToRef = Dictionary(uniqueKeysWithValues: slotCatalog.actorSlots.map { ($0.slotID, $0.ref) })
        let objectSlotToRef = Dictionary(uniqueKeysWithValues: slotCatalog.objectSlots.map { ($0.slotID, $0.ref) })
        let beatSlotIndex = Dictionary(uniqueKeysWithValues: slotCatalog.beatSlots.enumerated().map { ($1.slotID, $0) })
        var rowsByBeatSlot: [String: [SceneV9EventTable.EventRow]] = [:]
        for row in eventTable.rows {
            rowsByBeatSlot[row.beatSlot, default: []].append(row)
        }

        var beats: [ScenePlanIR.Beat] = []
        for beatSlot in slotCatalog.beatSlots.sorted(by: { $0.order < $1.order }) {
            let rows = (rowsByBeatSlot[beatSlot.slotID] ?? []).sorted(by: { $0.rowID < $1.rowID })
            if rows.isEmpty {
                continue
            }
            let actions = rows.compactMap { row -> ScenePlanIR.Action? in
                guard let actorRef = actorSlotToRef[row.actorSlot] else { return nil }
                let targetRef = row.targetSlot.flatMap { actorSlotToRef[$0] ?? objectSlotToRef[$0] }
                let holdingRef = row.holdingObjectSlot.flatMap { objectSlotToRef[$0] }
                return ScenePlanIR.Action(
                    actorRef: actorRef,
                    type: row.actionType,
                    targetRef: targetRef,
                    direction: nil,
                    modifier: nil,
                    resultingPose: nil,
                    holdingObjectRef: holdingRef,
                    dialogue: row.dialogueText,
                    fallbackText: row.describedActionText,
                    sourceText: row.sourceSpan ?? row.describedActionText
                )
            }
            if actions.isEmpty {
                continue
            }
            let beatRef = beatSlot.beatRef.isEmpty
                ? "beat_\(1 + (beatSlotIndex[beatSlot.slotID] ?? beats.count))"
                : beatSlot.beatRef
            beats.append(
                ScenePlanIR.Beat(
                    ref: beatRef,
                    phase: beatSlot.phaseHint,
                    actions: actions,
                    minDuration: beatSlot.minDuration
                )
            )
        }

        let validRefs = Set(slotCatalog.actorSlots.map(\.ref)).union(slotCatalog.objectSlots.map(\.ref))
        var spatialRelations: [ScenePlanIR.SpatialRelation] = []
        for (index, hint) in slotCatalog.relationHints.enumerated() {
            guard let subjectRef = actorSlotToRef[hint.subjectSlot] ?? objectSlotToRef[hint.subjectSlot],
                  let objectRef = actorSlotToRef[hint.objectSlot] ?? objectSlotToRef[hint.objectSlot],
                  validRefs.contains(subjectRef),
                  validRefs.contains(objectRef) else {
                continue
            }
            spatialRelations.append(
                ScenePlanIR.SpatialRelation(
                    ref: "rel_slot_\(index + 1)",
                    subjectRef: subjectRef,
                    relation: hint.relation,
                    objectRef: objectRef
                )
            )
        }
        for relation in originalPlan.spatialRelations where
            validRefs.contains(relation.subjectRef) &&
            validRefs.contains(relation.objectRef) &&
            !spatialRelations.contains(where: {
                $0.subjectRef == relation.subjectRef &&
                    $0.relation == relation.relation &&
                    $0.objectRef == relation.objectRef
            }) {
            spatialRelations.append(relation)
        }

        return ScenePlanIR(
            actors: slotCatalog.actorSlots.map { .init(ref: $0.ref, type: $0.type, name: $0.name) },
            objects: slotCatalog.objectSlots.map {
                .init(
                    ref: $0.ref,
                    type: $0.type,
                    relativePosition: $0.relativePosition,
                    name: $0.name,
                    markedObjectID: $0.markedObjectID
                )
            },
            beats: beats,
            spatialRelations: spatialRelations,
            referenceBindings: originalPlan.referenceBindings
        )
    }

    func applyGuardrails(
        to plan: ScenePlanIR,
        limits: RuntimeGuardrails
    ) -> (plan: ScenePlanIR, reasonCodes: [String]) {
        var guarded = plan
        var reasonCodes: [String] = []

        if guarded.actors.count > limits.maxActors {
            guarded.actors = Array(guarded.actors.prefix(max(1, limits.maxActors)))
            appendReason("v9.max_actors_guardrail_applied", to: &reasonCodes)
        }

        if guarded.objects.count > limits.maxObjects {
            guarded.objects = Array(guarded.objects.prefix(max(0, limits.maxObjects)))
            appendReason("v9.max_objects_guardrail_applied", to: &reasonCodes)
        }

        if guarded.beats.count > limits.maxBeats {
            guarded.beats = Array(guarded.beats.prefix(max(1, limits.maxBeats)))
            appendReason("v9.max_beats_guardrail_applied", to: &reasonCodes)
        }

        let actorRefs = Set(guarded.actors.map(\.ref))
        let objectRefs = Set(guarded.objects.map(\.ref))
        var totalRows = 0
        var keptBeats: [ScenePlanIR.Beat] = []
        for beat in guarded.beats {
            var actions: [ScenePlanIR.Action] = []
            for action in beat.actions {
                guard actorRefs.contains(action.actorRef) else {
                    appendReason("v9.unknown_slot_blocked", to: &reasonCodes)
                    continue
                }
                if let targetRef = action.targetRef,
                   !actorRefs.contains(targetRef),
                   !objectRefs.contains(targetRef) {
                    appendReason("v9.target_slot_repaired", to: &reasonCodes)
                    continue
                }

                if let holdingRef = action.holdingObjectRef, !objectRefs.contains(holdingRef) {
                    appendReason("v9.holding_slot_repaired", to: &reasonCodes)
                    continue
                }

                if totalRows >= limits.maxRows {
                    appendReason("v9.max_rows_guardrail_applied", to: &reasonCodes)
                    continue
                }

                actions.append(action)
                totalRows += 1
            }

            if !actions.isEmpty {
                keptBeats.append(
                    ScenePlanIR.Beat(
                        ref: beat.ref,
                        phase: beat.phase,
                        actions: actions,
                        minDuration: beat.minDuration
                    )
                )
            }
        }
        guarded.beats = keptBeats

        let validRefs = actorRefs.union(objectRefs)
        guarded.spatialRelations = guarded.spatialRelations.filter { relation in
            let valid = validRefs.contains(relation.subjectRef) && validRefs.contains(relation.objectRef)
            if !valid {
                appendReason("v9.invalid_spatial_relation_skipped", to: &reasonCodes)
            }
            return valid
        }

        return (plan: guarded, reasonCodes: reasonCodes)
    }

    func clampRows(
        in eventTable: SceneV9EventTable,
        maxRows: Int
    ) -> (eventTable: SceneV9EventTable, reasonCodes: [String]) {
        guard eventTable.rows.count > maxRows else {
            return (eventTable: eventTable, reasonCodes: [])
        }
        return (
            eventTable: SceneV9EventTable(
                contractVersion: eventTable.contractVersion,
                rows: Array(eventTable.rows.prefix(max(1, maxRows)))
            ),
            reasonCodes: ["v9.max_rows_guardrail_applied"]
        )
    }

    func containsFixableVerifierIssues(_ reasonCodes: [String]) -> Bool {
        reasonCodes.contains { code in
            fixableVerifierReasonCodes.contains { fixable in
                code == fixable || code.hasPrefix("\(fixable):")
            }
        }
    }

    func coverageIssueCodes(
        eventTable: SceneV9EventTable,
        slotCatalog: SceneV9SlotCatalog,
        sourceText: String,
        anchors: SourceAnchorBundle
    ) -> [String] {
        let lowercased = sourceText.lowercased()
        var issues: [String] = []
        let rows = eventTable.rows
        let rowsByBeat = Dictionary(grouping: rows, by: \.beatSlot)
        let actorCount = max(1, slotCatalog.actorSlots.count)

        func append(_ code: String) {
            if !issues.contains(code) {
                issues.append(code)
            }
        }

        for beatSlot in slotCatalog.beatSlots where rowsByBeat[beatSlot.slotID, default: []].isEmpty {
            append("v9.missing_event_for_beat:\(beatSlot.slotID)")
        }

        let hasTemporalSplit = containsAny(lowercased, ["потом", "затем", "после этого", "в этот момент", "после чего"])
        if hasTemporalSplit, slotCatalog.beatSlots.count > 1, Set(rows.map(\.beatSlot)).count < 2 {
            append("v9.missing_event_for_beat:temporal_connector")
        }

        let hasDialogueCue = sourceText.contains("«")
            || sourceText.contains("\"")
            || containsAny(lowercased, ["говорит", "спрашивает", "отвечает", "произносит"])
        if hasDialogueCue, !rows.contains(where: { $0.actionType == .talk && !($0.dialogueText ?? "").isEmpty }) {
            append("v9.dialogue_action_collapsed")
        }

        let hasCollectiveCue = containsAny(lowercased, ["оба", "вместе", "двое", "первый актёр и второй актёр", "первый актер и второй актер"])
        let motionRows = rows.filter { [.walk, .approach, .run, .stop].contains($0.actionType) }
        if hasCollectiveCue, actorCount > 1, motionRows.count < min(actorCount, 2) {
            append("v9.collective_action_not_expanded")
        }

        if lowercased.contains("навстреч") {
            let reciprocalRows = rows.filter { [.walk, .approach].contains($0.actionType) && $0.targetSlot != nil }
            if actorCount > 1, reciprocalRows.count < 2 {
                append("v9.collective_action_not_expanded:reciprocal_motion")
            }
        }

        let unsupportedCue = !anchors.unsupportedActionFlags.isEmpty
            || containsAny(lowercased, ["поправляет", "улыбается", "вздыхает", "кивает", "машет", "смотрит на экран", "речь затухает"])
        if unsupportedCue,
           !rows.contains(where: { $0.actionType == .describedAction && !($0.describedActionText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            append("v9.unsupported_action_missing_text")
        }

        let mentionsMarkedObject = slotCatalog.markedObjectSlots.contains { slotID in
            guard let object = slotCatalog.objectSlots.first(where: { $0.slotID == slotID }) else { return false }
            return [object.name, object.markedObjectID, object.ref]
                .compactMap { $0?.lowercased() }
                .contains { !$0.isEmpty && lowercased.contains($0) }
        }
        let objectMotionCue = containsAny(lowercased, ["к компьютеру", "к объекту", "рядом", "около", "у "])
        if mentionsMarkedObject || objectMotionCue {
            let rowsWithTarget = rows.filter { $0.targetSlot != nil }
            if rowsWithTarget.isEmpty, rows.contains(where: { targetRequiredTypes.contains($0.actionType) }) {
                append("v9.wrong_target_slot:marked_object")
            }
        }

        return issues
    }

    func applyPatchOps(
        _ patchOps: SceneV9PatchOps,
        to eventTable: SceneV9EventTable,
        slotCatalog: SceneV9SlotCatalog
    ) -> (eventTable: SceneV9EventTable, reasonCodes: [String]) {
        var rows = eventTable.rows
        var reasonCodes: [String] = []

        func applyField(_ field: String, value: String?, on row: inout SceneV9EventTable.EventRow) {
            switch field {
            case "beatSlot":
                row.beatSlot = value ?? row.beatSlot
            case "actorSlot":
                row.actorSlot = value ?? row.actorSlot
            case "actionType":
                if let value, let parsed = SceneAction.ActionType(rawValue: value) {
                    row.actionType = parsed
                } else {
                    appendReason("v9.patch_op_invalid_value", to: &reasonCodes)
                }
            case "targetSlot":
                row.targetSlot = value
            case "holdingObjectSlot":
                row.holdingObjectSlot = value
            case "dialogueText":
                row.dialogueText = value
            case "describedActionText":
                row.describedActionText = value
            case "sourceSpan":
                row.sourceSpan = value
            case "confidence":
                if let value, let parsed = Double(value) {
                    row.confidence = parsed
                } else {
                    appendReason("v9.patch_op_invalid_value", to: &reasonCodes)
                }
            default:
                appendReason("v9.patch_op_unknown_field", to: &reasonCodes)
            }
        }

        for op in patchOps.ops {
            switch op.op {
            case .delete:
                let before = rows.count
                rows.removeAll { $0.rowID == op.rowID }
                if rows.count == before {
                    appendReason("v9.patch_op_unknown_row", to: &reasonCodes)
                }
            case .replace:
                guard let index = rows.firstIndex(where: { $0.rowID == op.rowID }) else {
                    appendReason("v9.patch_op_unknown_row", to: &reasonCodes)
                    continue
                }
                guard let field = op.field else {
                    appendReason("v9.patch_op_unknown_field", to: &reasonCodes)
                    continue
                }
                applyField(field, value: op.value, on: &rows[index])
            case .add:
                if rows.contains(where: { $0.rowID == op.rowID }) {
                    appendReason("v9.patch_op_duplicate_row_id", to: &reasonCodes)
                    continue
                }
                var newRow = SceneV9EventTable.EventRow(
                    rowID: op.rowID,
                    beatSlot: slotCatalog.beatSlots.first?.slotID ?? "beat_slot_1",
                    actorSlot: slotCatalog.actorSlots.first?.slotID ?? "actor_slot_1",
                    actionType: .stand,
                    targetSlot: nil,
                    holdingObjectSlot: nil,
                    dialogueText: nil,
                    describedActionText: nil,
                    sourceSpan: nil,
                    confidence: 1.0
                )
                if let field = op.field {
                    applyField(field, value: op.value, on: &newRow)
                }
                rows.append(newRow)
            }
        }

        return (
            eventTable: SceneV9EventTable(contractVersion: eventTable.contractVersion, rows: rows),
            reasonCodes: reasonCodes
        )
    }

    private func appendReason(_ reason: String, to reasons: inout [String]) {
        if !reasons.contains(reason) {
            reasons.append(reason)
        }
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
