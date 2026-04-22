//
//  SceneBundlePipeline.swift
//  shafinMultitool
//
//  Created on 22.04.2026.
//

import Foundation

struct RawSceneChunkSegment {
    var sceneID: String
    var sceneIndex: Int
    var chunkID: String
    var chunkIndex: Int
    var sourceText: String
    var sourceRange: ScriptOffsetRange
    var metadata: SceneTopLevelMetadata
}

final class ScriptNormalizer {
    private let headingDetector = SceneMetadataExtractor()
    private let speakerCueRegex = try? NSRegularExpression(pattern: #"^[A-ZА-Я0-9][A-ZА-Я0-9 \-_.]{1,40}:?$"#)

    func normalize(description: String) -> [NormalizedScriptUnit] {
        let prepared = description
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "—", with: " — ")
        let lines = prepared.components(separatedBy: "\n")

        var units: [NormalizedScriptUnit] = []
        var cursor = 0
        var previousNonBlankKind: NormalizedScriptUnitKind?

        for (lineIndex, rawLine) in lines.enumerated() {
            let rawLength = rawLine.count
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let kind: NormalizedScriptUnitKind
            let normalizedText: String

            if trimmed.isEmpty {
                kind = .blank
                normalizedText = ""
            } else {
                normalizedText = rawLine
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                kind = classify(line: normalizedText, previousNonBlankKind: previousNonBlankKind)
                previousNonBlankKind = kind
            }

            let unit = NormalizedScriptUnit(
                id: "unit_\(lineIndex + 1)",
                kind: kind,
                text: normalizedText,
                lineIndex: lineIndex,
                charRange: ScriptOffsetRange(start: cursor, end: cursor + rawLength)
            )
            units.append(unit)
            cursor += rawLength + 1
        }

        return units
    }

    private func classify(line: String, previousNonBlankKind: NormalizedScriptUnitKind?) -> NormalizedScriptUnitKind {
        if headingDetector.extract(description: line).sceneHeading != nil {
            return .sceneHeading
        }
        if line.hasPrefix("("), line.hasSuffix(")") {
            return .parenthetical
        }
        let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
        if let speakerCueRegex, speakerCueRegex.firstMatch(in: line, range: nsRange) != nil {
            return .speakerCue
        }
        if previousNonBlankKind == .speakerCue || previousNonBlankKind == .parenthetical || previousNonBlankKind == .dialogue {
            return .dialogue
        }
        if line.count > 160 || line.contains("\"") || line.contains("«") {
            return .proseLine
        }
        return .actionLine
    }
}

final class SceneBoundaryDetector {
    func detect(
        units: [NormalizedScriptUnit],
        originalText: String,
        metadataExtractor: SceneMetadataExtractor
    ) -> [ScriptSceneCandidate] {
        let headingIndices = units.enumerated().compactMap { index, unit in
            unit.kind == .sceneHeading ? index : nil
        }

        if headingIndices.isEmpty {
            let trimmed = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            let metadata = metadataExtractor.extract(description: originalText)
            return [
                ScriptSceneCandidate(
                    id: "scene_1",
                    sceneIndex: 0,
                    heading: metadata.sceneHeading,
                    unitRange: 0..<units.count,
                    sourceRange: ScriptOffsetRange(start: 0, end: max(originalText.count, 0)),
                    sourceText: trimmed,
                    metadata: metadata,
                    isImplicit: true
                )
            ]
        }

        var scenes: [ScriptSceneCandidate] = []
        for (sceneOrdinal, startIndex) in headingIndices.enumerated() {
            let endIndex = headingIndices.dropFirst(sceneOrdinal + 1).first ?? units.count
            let sceneUnits = Array(units[startIndex..<endIndex])
            let contentUnits = sceneUnits.filter { $0.kind != .blank }
            guard contentUnits.count > 1 else { continue }
            let sourceText = render(units: sceneUnits)
            let metadata = metadataExtractor.extract(description: sourceText)
            let sourceRange = ScriptOffsetRange(
                start: sceneUnits.first?.charRange.start ?? 0,
                end: sceneUnits.last?.charRange.end ?? 0
            )
            scenes.append(
                ScriptSceneCandidate(
                    id: "scene_\(scenes.count + 1)",
                    sceneIndex: scenes.count,
                    heading: metadata.sceneHeading,
                    unitRange: startIndex..<endIndex,
                    sourceRange: sourceRange,
                    sourceText: sourceText,
                    metadata: metadata,
                    isImplicit: false
                )
            )
        }

        return scenes
    }

    private func render(units: [NormalizedScriptUnit]) -> String {
        units.map(\.text).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class ChunkSegmenter {
    private let temporalSplitKeywords = ["затем", "после этого", "в этот момент", "потом"]

    func segment(scene: ScriptSceneCandidate, units: [NormalizedScriptUnit]) -> [RawSceneChunkSegment] {
        let sceneUnits = Array(units[scene.unitRange])
        guard !sceneUnits.isEmpty else { return [] }

        var chunks: [RawSceneChunkSegment] = []
        var cursor = 0

        while cursor < sceneUnits.count {
            while cursor < sceneUnits.count && sceneUnits[cursor].kind == .blank {
                cursor += 1
            }
            guard cursor < sceneUnits.count else { break }

            let start = cursor
            let startUnit = sceneUnits[start]
            if startUnit.kind == .speakerCue {
                cursor = consumeDialogueChunk(from: start, units: sceneUnits)
            } else {
                cursor = consumeActionChunk(from: start, units: sceneUnits)
            }

            let chunkUnits = Array(sceneUnits[start..<min(cursor, sceneUnits.count)])
            let sourceText = render(units: chunkUnits)
            guard !sourceText.isEmpty else { continue }
            let sourceRange = ScriptOffsetRange(
                start: chunkUnits.first?.charRange.start ?? 0,
                end: chunkUnits.last?.charRange.end ?? 0
            )
            chunks.append(
                RawSceneChunkSegment(
                    sceneID: scene.id,
                    sceneIndex: scene.sceneIndex,
                    chunkID: "\(scene.id)_chunk_\(chunks.count + 1)",
                    chunkIndex: chunks.count,
                    sourceText: sourceText,
                    sourceRange: sourceRange,
                    metadata: scene.metadata
                )
            )
        }

        return chunks
    }

    private func consumeDialogueChunk(from start: Int, units: [NormalizedScriptUnit]) -> Int {
        var index = start + 1
        var blankSeen = false
        while index < units.count {
            let kind = units[index].kind
            if kind == .blank {
                blankSeen = true
                index += 1
                continue
            }
            if kind == .sceneHeading || kind == .speakerCue {
                break
            }
            if blankSeen {
                break
            }
            index += 1
        }
        return index
    }

    private func consumeActionChunk(from start: Int, units: [NormalizedScriptUnit]) -> Int {
        var index = start
        var sentenceBudget = 0
        var charBudget = 0

        while index < units.count {
            let unit = units[index]
            if index > start, unit.kind == .blank {
                break
            }
            if index > start, unit.kind == .sceneHeading || unit.kind == .speakerCue {
                break
            }
            if index > start, shouldSplitBefore(unit: unit) {
                break
            }

            charBudget += unit.text.count
            sentenceBudget += unit.text.components(separatedBy: CharacterSet(charactersIn: ".!?")).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
            index += 1

            if sentenceBudget >= 3 || charBudget >= 500 {
                break
            }
        }
        return index
    }

    private func shouldSplitBefore(unit: NormalizedScriptUnit) -> Bool {
        let lowercased = unit.text.lowercased()
        return temporalSplitKeywords.contains(where: { lowercased.contains($0) })
    }

    private func render(units: [NormalizedScriptUnit]) -> String {
        units.map(\.text).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class SceneChunkAnchorExtractor {
    private let baseExtractor: SceneAnchorExtractor
    private let metadataExtractor = SceneMetadataExtractor()
    private let objectKeywords = Set(KeywordsMapping.objectKeywords.keys)
    private let pronouns = ["он", "она", "они", "ему", "ей", "его", "её", "ее", "их", "другой", "другая", "первый", "второй", "третий"]

    init(baseExtractor: SceneAnchorExtractor) {
        self.baseExtractor = baseExtractor
    }

    func extract(sourceText: String, markedObjects: [MarkedObject], normalizedUnits: [NormalizedScriptUnit]) -> SceneChunkAnchor {
        let bundle = baseExtractor.extract(description: sourceText, markedObjects: markedObjects)
        let lowercased = sourceText.lowercased()
        let speakerCues = normalizedUnits
            .filter { $0.kind == .speakerCue }
            .map { $0.text.replacingOccurrences(of: ":", with: "").lowercased() }

        let objectMentions = objectKeywords.filter { lowercased.contains($0) }.sorted()
        let actorMentions = speakerCues + ["человек", "мужчина", "женщина", "парень", "девушка"].filter { lowercased.contains($0) }
        let pronounMentions = pronouns.filter { lowercased.contains($0) }
        let chronologyCues = ["затем", "после этого", "в этот момент", "потом", "сразу"].filter { lowercased.contains($0) }
        let metadata = metadataExtractor.extract(description: sourceText)
        let locationCues = [metadata.locationName].compactMap { $0?.lowercased() }
        let timeCues = [metadata.timeOfDay].compactMap { $0?.lowercased() }
        var uncertaintyFlags = bundle.lowConfidenceFlags
        if !pronounMentions.isEmpty && actorMentions.isEmpty {
            uncertaintyFlags.append("pronoun_without_named_actor")
        }

        return SceneChunkAnchor(
            sourceBundle: bundle,
            speakerCues: speakerCues,
            actorMentions: unique(actorMentions),
            objectMentions: objectMentions,
            markedObjectMentions: bundle.mentionedMarkedObjects,
            pronounMentions: pronounMentions,
            chronologyCues: chronologyCues,
            locationCues: locationCues,
            timeCues: timeCues,
            uncertaintyFlags: unique(uncertaintyFlags)
        )
    }

    private func unique(_ values: [String]) -> [String] {
        var result: [String] = []
        for value in values where !result.contains(value) {
            result.append(value)
        }
        return result
    }
}

final class EntityRegistryProjector {
    func project(from state: SceneStitchState?) -> SceneEntityRegistrySnapshot {
        state?.registry ?? .empty
    }

    func chunkState(from registry: SceneEntityRegistrySnapshot, sceneID: String, metadata: SceneTopLevelMetadata) -> SceneChunkState {
        SceneChunkState(
            sceneID: sceneID,
            sceneHeading: metadata.sceneHeading,
            locationName: metadata.locationName,
            knownActors: registry.actorAliasMap,
            knownObjects: registry.objectAliasMap,
            actorAliases: registry.actorAliasMap,
            objectAliases: registry.objectAliasMap,
            speakerAliasMap: registry.speakerAliasMap,
            actorPoses: registry.actorPoses,
            heldObjects: registry.heldObjects,
            lastResolvedSpeaker: registry.lastResolvedSpeaker
        )
    }
}

final class ChunkCanonicalizer {
    private let genericRoleNames: Set<String> = [
        "мужчина", "женщина", "парень", "девушка", "человек", "персонаж", "он", "она", "они"
    ]

    func canonicalize(
        draft: SceneChunkDraft,
        stitchState: SceneStitchState?
    ) -> SceneChunk {
        let sceneIndex = draft.sceneID.components(separatedBy: "_").last.flatMap(Int.init) ?? (stitchState?.sceneIndex ?? 0) + 1
        var existingActorMap = Dictionary(uniqueKeysWithValues: (stitchState?.actors ?? []).map { ($0.ref, $0) })
        var existingObjectMap = Dictionary(uniqueKeysWithValues: (stitchState?.objects ?? []).map { ($0.ref, $0) })
        var actorAliasMap = stitchState?.registry.actorAliasMap ?? [:]
        var objectAliasMap = stitchState?.registry.objectAliasMap ?? [:]
        var speakerAliasMap = stitchState?.registry.speakerAliasMap ?? [:]
        var createdActors: [ScenePlanIR.Actor] = []
        var createdObjects: [ScenePlanIR.Object] = []
        var actorRefMap: [String: String] = [:]
        var objectRefMap: [String: String] = [:]
        var reasonCodes = draft.reasonCodes
        var deferredRefs: [SceneDeferredRef] = []

        let existingActorsInOrder = stitchState?.actors ?? []
        let existingObjectsInOrder = stitchState?.objects ?? []

        for (index, actor) in draft.plan.actors.enumerated() {
            let normalizedName = normalizeAlias(actor.name)
            let stableRef: String
            if let normalizedName, let existing = actorAliasMap[normalizedName] {
                stableRef = existing
            } else if let ordinalRef = resolveOrdinalActorRef(actor.ref, index: index, existingActors: existingActorsInOrder) {
                stableRef = ordinalRef
            } else if normalizedName == nil, let existing = existingActorsInOrder.first?.ref {
                stableRef = existing
            } else if normalizedName == nil, let existing = createdActors.first?.ref {
                stableRef = existing
            } else {
                let slug = slugify(normalizedName ?? "actor")
                let nextIndex = existingActorMap.count + createdActors.count + 1
                stableRef = "actor_scene\(sceneIndex)_\(slug)_\(nextIndex)"
                let created = ScenePlanIR.Actor(ref: stableRef, type: actor.type, name: normalizedName ?? actor.name)
                createdActors.append(created)
                existingActorMap[stableRef] = created
            }

            actorRefMap[actor.ref] = stableRef
            if let normalizedName {
                actorAliasMap[normalizedName] = stableRef
                if draft.anchors.speakerCues.contains(normalizedName) {
                    speakerAliasMap[normalizedName] = stableRef
                }
            }
        }

        if draft.plan.actors.isEmpty && !existingActorsInOrder.isEmpty {
            actorRefMap["first"] = existingActorsInOrder[0].ref
        }

        for object in draft.plan.objects {
            let stableRef: String
            let normalizedName = normalizeAlias(object.name)

            if let markedObjectID = object.markedObjectID, markedObjectID.hasPrefix("object_marked_") {
                stableRef = markedObjectID
                let canonical = ScenePlanIR.Object(
                    ref: stableRef,
                    type: object.type,
                    relativePosition: object.relativePosition,
                    name: normalizedName ?? object.name,
                    markedObjectID: markedObjectID
                )
                if existingObjectMap[stableRef] == nil {
                    existingObjectMap[stableRef] = canonical
                    createdObjects.append(canonical)
                }
            } else if object.ref.hasPrefix("object_marked_") {
                stableRef = object.ref
                let canonical = ScenePlanIR.Object(
                    ref: stableRef,
                    type: object.type,
                    relativePosition: object.relativePosition,
                    name: normalizedName ?? object.name,
                    markedObjectID: object.ref
                )
                if existingObjectMap[stableRef] == nil {
                    existingObjectMap[stableRef] = canonical
                    createdObjects.append(canonical)
                }
            } else if let normalizedName, let existing = objectAliasMap[normalizedName] {
                stableRef = existing
            } else if let matched = existingObjectsInOrder.first(where: { existing in
                existing.type == object.type && normalizeAlias(existing.name) == normalizedName
            })?.ref {
                stableRef = matched
            } else {
                let slug = slugify(normalizedName ?? object.type.rawValue)
                let nextIndex = existingObjectMap.values.filter { !$0.ref.hasPrefix("object_marked_") }.count + createdObjects.count + 1
                stableRef = "object_scene\(sceneIndex)_\(slug)_\(nextIndex)"
                let canonical = ScenePlanIR.Object(
                    ref: stableRef,
                    type: object.type,
                    relativePosition: object.relativePosition,
                    name: normalizedName ?? object.name,
                    markedObjectID: nil
                )
                createdObjects.append(canonical)
                existingObjectMap[stableRef] = canonical
            }

            objectRefMap[object.ref] = stableRef
            if let normalizedName {
                objectAliasMap[normalizedName] = stableRef
            }
        }

        let beatPatch = draft.plan.beats.enumerated().map { beatIndex, beat in
            var actions: [ScenePlanIR.Action] = []
            for actionIndex in beat.actions.indices {
                let action = beat.actions[actionIndex]
                let actorRef = resolveActorRef(
                    action.actorRef,
                    actorMap: actorRefMap,
                    existingActors: existingActorsInOrder,
                    anchors: draft.anchors
                )
                guard let actorRef else {
                    if !reasonCodes.contains("v1.unknown_actor_action_dropped") {
                        reasonCodes.append("v1.unknown_actor_action_dropped")
                    }
                    continue
                }
                let targetResolution = resolveTargetRef(
                    action.targetRef,
                    actorMap: actorRefMap,
                    objectMap: objectRefMap,
                    actorAliasMap: actorAliasMap,
                    objectAliasMap: objectAliasMap,
                    chunkID: draft.chunkID,
                    deferredRefs: &deferredRefs,
                    reasonCodes: &reasonCodes
                )
                let holdingObjectResolution = resolveObjectRef(
                    action.holdingObjectRef,
                    objectMap: objectRefMap,
                    objectAliasMap: objectAliasMap,
                    chunkID: draft.chunkID,
                    deferredRefs: &deferredRefs,
                    reasonCodes: &reasonCodes
                )
                let newAction = ScenePlanIR.Action(
                    actorRef: actorRef,
                    type: action.type,
                    targetRef: targetResolution,
                    direction: action.direction,
                    modifier: action.modifier,
                    resultingPose: action.resultingPose,
                    holdingObjectRef: holdingObjectResolution,
                    dialogue: action.dialogue,
                    fallbackText: action.fallbackText,
                    sourceText: action.sourceText
                )
                actions.append(newAction)
            }
            return ScenePlanIR.Beat(
                ref: "\(draft.chunkID)_beat_\(beatIndex + 1)",
                phase: beat.phase,
                actions: actions,
                minDuration: beat.minDuration
            )
        }

        let spatialRelationPatch = draft.plan.spatialRelations.enumerated().compactMap { entry -> ScenePlanIR.SpatialRelation? in
            let (relationIndex, relation) = entry
            guard let subjectRef = resolvePlanRef(relation.subjectRef, actorMap: actorRefMap, objectMap: objectRefMap),
                  let objectRef = resolvePlanRef(relation.objectRef, actorMap: actorRefMap, objectMap: objectRefMap)
            else {
                if !reasonCodes.contains("v1.invalid_spatial_relation_skipped") {
                    reasonCodes.append("v1.invalid_spatial_relation_skipped")
                }
                return nil
            }
            return ScenePlanIR.SpatialRelation(
                ref: "\(draft.chunkID)_rel_\(relationIndex + 1)",
                subjectRef: subjectRef,
                relation: relation.relation,
                objectRef: objectRef
            )
        }

        let stateDelta = makeStateDelta(beats: beatPatch, metadata: draft.registrySnapshot.locationName ?? draft.anchors.locationCues.first)

        return SceneChunk(
            sceneID: draft.sceneID,
            chunkID: draft.chunkID,
            chunkIndex: draft.chunkIndex,
            sourceText: draft.sourceText,
            sourceRange: draft.sourceRange,
            anchors: draft.anchors,
            registryPatch: .init(
                actors: createdActors,
                objects: createdObjects,
                actorAliasMap: actorAliasMap,
                objectAliasMap: objectAliasMap,
                speakerAliasMap: speakerAliasMap
            ),
            beatPatch: beatPatch,
            spatialRelationPatch: spatialRelationPatch,
            stateDelta: stateDelta,
            deferredRefs: deferredRefs,
            reasonCodes: unique(reasonCodes),
            usedFallbackPlanner: draft.usedFallbackPlanner,
            usedLegacyPlanBridge: draft.usedLegacyPlanBridge
        )
    }

    private func resolveOrdinalActorRef(_ rawRef: String, index: Int, existingActors: [ScenePlanIR.Actor]) -> String? {
        let ordinalIndex: Int?
        switch rawRef {
        case "first": ordinalIndex = 0
        case "second": ordinalIndex = 1
        case "third": ordinalIndex = 2
        default: ordinalIndex = index < existingActors.count ? index : nil
        }
        guard let ordinalIndex, existingActors.indices.contains(ordinalIndex) else { return nil }
        return existingActors[ordinalIndex].ref
    }

    private func resolveActorRef(
        _ rawRef: String,
        actorMap: [String: String],
        existingActors: [ScenePlanIR.Actor],
        anchors: SceneChunkAnchor
    ) -> String? {
        if let mapped = actorMap[rawRef] {
            return mapped
        }
        if let resolved = resolveOrdinalActorRef(rawRef, index: 0, existingActors: existingActors) {
            return resolved
        }
        if !anchors.speakerCues.isEmpty, let fallback = existingActors.first?.ref {
            return fallback
        }
        return actorMap.values.sorted().first
    }

    private func resolveTargetRef(
        _ rawRef: String?,
        actorMap: [String: String],
        objectMap: [String: String],
        actorAliasMap: [String: String],
        objectAliasMap: [String: String],
        chunkID: String,
        deferredRefs: inout [SceneDeferredRef],
        reasonCodes: inout [String]
    ) -> String? {
        guard let rawRef, !rawRef.isEmpty else { return nil }
        if let mapped = resolvePlanRef(rawRef, actorMap: actorMap, objectMap: objectMap) {
            return mapped
        }
        let normalized = normalizeAlias(rawRef)
        if let normalized, let actor = actorAliasMap[normalized] {
            return actor
        }
        if let normalized, let object = objectAliasMap[normalized] {
            return object
        }
        let deferredID = "deferred_\(chunkID)_\(slugify(rawRef))"
        if !deferredRefs.contains(where: { $0.id == deferredID }) {
            deferredRefs.append(
                SceneDeferredRef(
                    id: deferredID,
                    localRef: rawRef,
                    kind: .object,
                    alias: normalized,
                    sourceText: rawRef
                )
            )
        }
        if !reasonCodes.contains("v1.deferred_target_ref") {
            reasonCodes.append("v1.deferred_target_ref")
        }
        return deferredID
    }

    private func resolveObjectRef(
        _ rawRef: String?,
        objectMap: [String: String],
        objectAliasMap: [String: String],
        chunkID: String,
        deferredRefs: inout [SceneDeferredRef],
        reasonCodes: inout [String]
    ) -> String? {
        guard let rawRef, !rawRef.isEmpty else { return nil }
        if let mapped = objectMap[rawRef] {
            return mapped
        }
        let normalized = normalizeAlias(rawRef)
        if let normalized, let object = objectAliasMap[normalized] {
            return object
        }
        let deferredID = "deferred_\(chunkID)_holding_\(slugify(rawRef))"
        if !deferredRefs.contains(where: { $0.id == deferredID }) {
            deferredRefs.append(
                SceneDeferredRef(
                    id: deferredID,
                    localRef: rawRef,
                    kind: .object,
                    alias: normalized,
                    sourceText: rawRef
                )
            )
        }
        if !reasonCodes.contains("v1.deferred_holding_object") {
            reasonCodes.append("v1.deferred_holding_object")
        }
        return deferredID
    }

    private func resolvePlanRef(_ rawRef: String, actorMap: [String: String], objectMap: [String: String]) -> String? {
        actorMap[rawRef] ?? objectMap[rawRef] ?? (rawRef.hasPrefix("object_marked_") ? rawRef : nil)
    }

    private func makeStateDelta(beats: [ScenePlanIR.Beat], metadata: String?) -> SceneChunkStateDelta {
        var poses: [String: ActorPose] = [:]
        var heldObjects: [String: String] = [:]
        var released: [String] = []

        for beat in beats {
            for action in beat.actions {
                if let pose = action.resultingPose {
                    poses[action.actorRef] = pose
                }
                switch action.type {
                case .pickUp:
                    if let target = action.targetRef {
                        heldObjects[action.actorRef] = target
                    }
                case .putDown, .give:
                    released.append(action.actorRef)
                default:
                    break
                }
            }
        }

        return SceneChunkStateDelta(
            locationUpdate: metadata,
            actorPoseUpdates: poses,
            heldObjectUpdates: heldObjects,
            releasedObjects: released
        )
    }

    private func normalizeAlias(_ value: String?) -> String? {
        guard let value = value?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return genericRoleNames.contains(value) ? nil : value
    }

    private func slugify(_ value: String) -> String {
        let lowercased = value.lowercased()
        let sanitized = lowercased.replacingOccurrences(of: #"[^a-zа-я0-9]+"#, with: "_", options: .regularExpression)
        return sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "_")).isEmpty ? "item" : sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private func unique(_ values: [String]) -> [String] {
        var result: [String] = []
        for value in values where !result.contains(value) {
            result.append(value)
        }
        return result
    }
}

final class SceneStitcher {
    private let targetRequiredTypes: Set<SceneAction.ActionType> = [
        .lookAt, .pickUp, .open, .close, .approach, .putDown, .give, .passBy, .stop
    ]

    func apply(chunk: SceneChunk, to baseState: SceneStitchState?) -> SceneStitchState {
        let derivedSceneIndex = max((chunk.sceneID.components(separatedBy: "_").last).flatMap(Int.init).map { $0 - 1 } ?? 0, 0)
        var state = baseState ?? SceneStitchState(
            sceneID: chunk.sceneID,
            sceneIndex: derivedSceneIndex,
            sourceText: "",
            metadata: .empty
        )

        if !state.sourceText.isEmpty {
            state.sourceText += "\n"
        }
        state.sourceText += chunk.sourceText
        if state.metadata == .empty {
            state.metadata = chunkAnchoredMetadata(chunk.anchors)
        }

        mergeRegistryPatch(chunk.registryPatch, into: &state)
        mergeBeats(chunk.beatPatch, into: &state)
        mergeRelations(chunk.spatialRelationPatch, into: &state)
        applyStateDelta(chunk.stateDelta, to: &state)

        state.deferredRefs.append(contentsOf: chunk.deferredRefs.filter { deferred in
            !state.deferredRefs.contains(where: { $0.id == deferred.id })
        })
        state.chunkLedger.append(chunk.chunkID)
        for reason in chunk.reasonCodes where !state.continuityDiagnostics.contains(reason) {
            state.continuityDiagnostics.append(reason)
        }
        return state
    }

    func finalize(state: SceneStitchState) -> ScenePlanIR {
        let actorRefs = Set(state.actors.map(\.ref))
        let objectRefs = Set(state.objects.map(\.ref))
        let unresolvedDeferredIDs = Set(state.deferredRefs.map(\.id))

        let finalizedBeats = state.beats.compactMap { beat -> ScenePlanIR.Beat? in
            var actions: [ScenePlanIR.Action] = []
            for action in beat.actions {
                guard actorRefs.contains(action.actorRef) else { continue }
                var finalizedAction = action
                if let targetRef = action.targetRef, unresolvedDeferredIDs.contains(targetRef) || (!actorRefs.contains(targetRef) && !objectRefs.contains(targetRef)) {
                    if targetRequiredTypes.contains(action.type) {
                        finalizedAction.type = .describedAction
                        finalizedAction.targetRef = nil
                        finalizedAction.fallbackText = finalizedAction.fallbackText ?? finalizedAction.sourceText ?? action.type.rawValue
                    } else {
                        finalizedAction.targetRef = nil
                    }
                }
                if let holdingRef = action.holdingObjectRef, unresolvedDeferredIDs.contains(holdingRef) || !objectRefs.contains(holdingRef) {
                    finalizedAction.holdingObjectRef = nil
                }
                actions.append(finalizedAction)
            }
            guard !actions.isEmpty else { return nil }
            return ScenePlanIR.Beat(ref: beat.ref, phase: beat.phase, actions: actions, minDuration: beat.minDuration)
        }

        let finalizedRelations = state.spatialRelations.filter { relation in
            (actorRefs.contains(relation.subjectRef) || objectRefs.contains(relation.subjectRef)) &&
                (actorRefs.contains(relation.objectRef) || objectRefs.contains(relation.objectRef)) &&
                !unresolvedDeferredIDs.contains(relation.subjectRef) &&
                !unresolvedDeferredIDs.contains(relation.objectRef)
        }

        let aliasBindings = state.registry.objectAliasMap
        let markedObjectIDs = state.objects.compactMap { object in
            object.markedObjectID ?? (object.ref.hasPrefix("object_marked_") ? object.ref : nil)
        }

        return ScenePlanIR(
            actors: state.actors,
            objects: state.objects,
            beats: finalizedBeats,
            spatialRelations: finalizedRelations,
            referenceBindings: .init(
                actorBindings: Dictionary(uniqueKeysWithValues: state.actors.map { ($0.ref, $0.ref) }),
                markedObjectIDs: markedObjectIDs,
                aliasToObjectRef: aliasBindings
            )
        )
    }

    private func chunkAnchoredMetadata(_ anchors: SceneChunkAnchor) -> SceneTopLevelMetadata {
        SceneTopLevelMetadata(
            sceneHeading: nil,
            locationName: anchors.locationCues.first,
            interiorExterior: nil,
            timeOfDay: anchors.timeCues.first
        )
    }

    private func mergeRegistryPatch(_ patch: SceneChunk.RegistryPatch, into state: inout SceneStitchState) {
        for actor in patch.actors where !state.actors.contains(where: { $0.ref == actor.ref }) {
            state.actors.append(actor)
            state.registry.actors.append(actor)
        }
        for object in patch.objects where !state.objects.contains(where: { $0.ref == object.ref }) {
            state.objects.append(object)
            state.registry.objects.append(object)
        }
        state.registry.actorAliasMap.merge(patch.actorAliasMap) { _, new in new }
        state.registry.objectAliasMap.merge(patch.objectAliasMap) { _, new in new }
        state.registry.speakerAliasMap.merge(patch.speakerAliasMap) { _, new in new }
        if let lastSpeaker = patch.speakerAliasMap.values.sorted().last {
            state.registry.lastResolvedSpeaker = lastSpeaker
        }
    }

    private func mergeBeats(_ beats: [ScenePlanIR.Beat], into state: inout SceneStitchState) {
        for beat in beats {
            let dedupedActions = beat.actions.filter { action in
                let fingerprint = actionFingerprint(action)
                return !state.beats.flatMap(\.actions).contains(where: { actionFingerprint($0) == fingerprint })
            }
            guard !dedupedActions.isEmpty else { continue }
            state.beats.append(ScenePlanIR.Beat(ref: beat.ref, phase: beat.phase, actions: dedupedActions, minDuration: beat.minDuration))
        }
    }

    private func mergeRelations(_ relations: [ScenePlanIR.SpatialRelation], into state: inout SceneStitchState) {
        for relation in relations where !state.spatialRelations.contains(where: { existing in
            existing.subjectRef == relation.subjectRef &&
                existing.relation == relation.relation &&
                existing.objectRef == relation.objectRef
        }) {
            state.spatialRelations.append(relation)
        }
    }

    private func applyStateDelta(_ delta: SceneChunkStateDelta, to state: inout SceneStitchState) {
        if let locationUpdate = delta.locationUpdate, !locationUpdate.isEmpty {
            state.registry.locationName = locationUpdate
            state.metadata.locationName = locationUpdate
        }
        state.registry.actorPoses.merge(delta.actorPoseUpdates) { _, new in new }
        state.registry.heldObjects.merge(delta.heldObjectUpdates) { _, new in new }
        for actorRef in delta.releasedObjects {
            state.registry.heldObjects.removeValue(forKey: actorRef)
        }
    }

    private func actionFingerprint(_ action: ScenePlanIR.Action) -> String {
        [
            action.actorRef,
            action.type.rawValue,
            action.targetRef ?? "",
            action.dialogue ?? "",
            action.sourceText ?? ""
        ].joined(separator: "|")
    }
}

final class SceneBundleCompiler {
    private let planCompiler: ScenePlanCompiler

    init(planCompiler: ScenePlanCompiler) {
        self.planCompiler = planCompiler
    }

    func compile(bundlePlan: SceneBundlePlan) -> SceneBundleScript {
        let scripts = bundlePlan.scenes.compactMap { sceneEntry in
            try? planCompiler.compile(
                plan: sceneEntry.plan,
                originalDescription: sceneEntry.sourceText,
                topLevelMetadata: (
                    sceneHeading: sceneEntry.metadata.sceneHeading,
                    locationName: sceneEntry.metadata.locationName,
                    interiorExterior: sceneEntry.metadata.interiorExterior,
                    timeOfDay: sceneEntry.metadata.timeOfDay
                )
            )
        }
        let activeIndex = min(bundlePlan.activeSceneIndex, max(scripts.count - 1, 0))
        return SceneBundleScript(
            bundleID: bundlePlan.bundleID,
            scenes: scripts,
            activeSceneIndex: scripts.isEmpty ? 0 : activeIndex,
            diagnostics: bundlePlan.diagnostics
        )
    }
}

final class SceneBundlePipeline {
    private let normalizer = ScriptNormalizer()
    private let boundaryDetector = SceneBoundaryDetector()
    private let segmenter = ChunkSegmenter()
    private let chunkAnchorExtractor: SceneChunkAnchorExtractor
    private let registryProjector = EntityRegistryProjector()
    private let canonicalizer = ChunkCanonicalizer()
    private let stitcher = SceneStitcher()
    private let metadataExtractor: SceneMetadataExtractor
    private let localProvider: LocalScenePlanProvider
    private let bundleCompiler: SceneBundleCompiler

    init(
        anchorExtractor: SceneAnchorExtractor,
        metadataExtractor: SceneMetadataExtractor,
        localProvider: LocalScenePlanProvider,
        planCompiler: ScenePlanCompiler
    ) {
        self.chunkAnchorExtractor = SceneChunkAnchorExtractor(baseExtractor: anchorExtractor)
        self.metadataExtractor = metadataExtractor
        self.localProvider = localProvider
        self.bundleCompiler = SceneBundleCompiler(planCompiler: planCompiler)
    }

    func parse(
        description: String,
        markedObjects: [MarkedObject],
        mode: SceneBundleParseMode,
        previousState: ScriptDocumentState?,
        fallbackPlanner: (_ text: String, _ markedObjects: [MarkedObject], _ state: SceneChunkState?) -> ParsingResult
    ) -> SceneBundleParsingResult {
        let workload = makeWorkload(description: description, mode: mode, previousState: previousState)
        return finalizeWorkload(
            workload,
            markedObjects: markedObjects,
            previousState: previousState,
            fallbackPlanner: fallbackPlanner,
            asyncPlanner: nil
        )
    }

    func parseAsync(
        description: String,
        markedObjects: [MarkedObject],
        mode: SceneBundleParseMode,
        previousState: ScriptDocumentState?,
        fallbackPlanner: @escaping (_ text: String, _ markedObjects: [MarkedObject], _ state: SceneChunkState?) -> ParsingResult
    ) async -> SceneBundleParsingResult {
        let workload = makeWorkload(description: description, mode: mode, previousState: previousState)
        return await finalizeWorkload(
            workload,
            markedObjects: markedObjects,
            previousState: previousState,
            fallbackPlanner: fallbackPlanner,
            asyncPlanner: { [localProvider] text, markers, anchors, state in
                await localProvider.generatePlanAsync(description: text, markedObjects: markers, anchors: anchors, state: state)
            }
        )
    }

    private func finalizeWorkload(
        _ workload: SceneBundleWorkload,
        markedObjects: [MarkedObject],
        previousState: ScriptDocumentState?,
        fallbackPlanner: (_ text: String, _ markedObjects: [MarkedObject], _ state: SceneChunkState?) -> ParsingResult,
        asyncPlanner: ((_ text: String, _ markers: [MarkedObject], _ anchors: SourceAnchorBundle, _ state: SceneChunkState?) async -> ScenePlanProviderResult?)?
    ) async -> SceneBundleParsingResult {
        var stitchedStates = workload.reusedStates
        var sceneEntries = workload.reusedSceneEntries
        var allChunks: [SceneChunk] = workload.reusedChunks
        var chunkDiagnostics: [SceneChunkDiagnostics] = workload.reusedChunkDiagnostics

        for scene in workload.pendingScenes {
            var sceneState = workload.seedState(for: scene, previousState: previousState)
            var sceneChunks: [SceneChunk] = []
            let rawSegments = segmenter.segment(scene: scene, units: workload.units)

            for rawSegment in rawSegments {
                let segmentUnits = unitsIntersecting(rawSegment.sourceRange, units: workload.units)
                let anchors = chunkAnchorExtractor.extract(
                    sourceText: rawSegment.sourceText,
                    markedObjects: markedObjects,
                    normalizedUnits: segmentUnits
                )
                let registrySnapshot = registryProjector.project(from: sceneState)
                let chunkState = registryProjector.chunkState(from: registrySnapshot, sceneID: scene.id, metadata: scene.metadata)
                let providerResult: ScenePlanProviderResult?
                if let asyncPlanner {
                    providerResult = await asyncPlanner(rawSegment.sourceText, markedObjects, anchors.sourceBundle, chunkState)
                } else {
                    providerResult = localProvider.generatePlan(
                        description: rawSegment.sourceText,
                        markedObjects: markedObjects,
                        anchors: anchors.sourceBundle,
                        state: chunkState
                    )
                }

                let draft = makeDraft(
                    scene: scene,
                    rawSegment: rawSegment,
                    anchors: anchors,
                    registrySnapshot: registrySnapshot,
                    providerResult: providerResult,
                    markedObjects: markedObjects,
                    chunkState: chunkState,
                    fallbackPlanner: fallbackPlanner
                )
                let canonicalChunk = canonicalizer.canonicalize(draft: draft, stitchState: sceneState)
                sceneState = stitcher.apply(chunk: canonicalChunk, to: sceneState)
                sceneChunks.append(canonicalChunk)
                allChunks.append(canonicalChunk)
                chunkDiagnostics.append(
                    SceneChunkDiagnostics(
                        sceneID: canonicalChunk.sceneID,
                        chunkID: canonicalChunk.chunkID,
                        chunkIndex: canonicalChunk.chunkIndex,
                        reasonCodes: canonicalChunk.reasonCodes,
                        unresolvedRefs: canonicalChunk.deferredRefs.map(\.id),
                        anchors: canonicalChunk.anchors,
                        usedFallbackPlanner: canonicalChunk.usedFallbackPlanner,
                        usedLegacyPlanBridge: canonicalChunk.usedLegacyPlanBridge
                    )
                )
            }

            guard let finalizedState = sceneState else { continue }
            let finalizedPlan = stitcher.finalize(state: finalizedState)
            let sceneEntry = SceneBundlePlan.SceneEntry(
                sceneID: scene.id,
                sceneIndex: scene.sceneIndex,
                sourceText: finalizedState.sourceText,
                metadata: finalizedState.metadata == .empty ? scene.metadata : finalizedState.metadata,
                chunks: sceneChunks,
                diagnostics: finalizedState.continuityDiagnostics,
                plan: finalizedPlan
            )
            stitchedStates.append(finalizedState)
            sceneEntries.append(sceneEntry)
        }

        sceneEntries.sort { $0.sceneIndex < $1.sceneIndex }
        stitchedStates.sort { $0.sceneIndex < $1.sceneIndex }

        let bundlePlan = SceneBundlePlan(
            bundleID: workload.bundleID,
            scenes: sceneEntries.filter { !$0.plan.beats.isEmpty || !$0.plan.objects.isEmpty },
            activeSceneIndex: max(0, sceneEntries.indices.last ?? 0),
            diagnostics: ["bundle_mode=\(workload.mode.rawValue)", "scene_count=\(sceneEntries.count)"]
        )
        let bundleScript = bundleCompiler.compile(bundlePlan: bundlePlan)
        let activeSceneScript = bundleScript.activeSceneScript
        let diagnostics = makeDiagnostics(
            bundleScript: bundleScript,
            activeSceneScript: activeSceneScript,
            fullDescription: workload.finalDescription,
            markedObjects: markedObjects,
            chunkDiagnostics: chunkDiagnostics
        )
        let documentState = ScriptDocumentState(
            documentID: workload.documentID,
            mode: workload.mode,
            sourceText: workload.finalDescription,
            normalizedUnits: workload.units,
            sceneCandidates: workload.finalSceneCandidates,
            stitchStates: stitchedStates,
            bundlePlan: bundlePlan,
            bundleScript: bundleScript,
            activeSceneIndex: bundlePlan.activeSceneIndex
        )

        return SceneBundleParsingResult(
            bundleScript: bundleScript,
            activeSceneScript: activeSceneScript,
            activeSceneId: sceneEntries.indices.contains(bundlePlan.activeSceneIndex) ? sceneEntries[bundlePlan.activeSceneIndex].sceneID : nil,
            sceneChunks: allChunks.sorted { lhs, rhs in
                if lhs.sceneID == rhs.sceneID {
                    return lhs.chunkIndex < rhs.chunkIndex
                }
                return lhs.sceneID < rhs.sceneID
            },
            documentState: documentState,
            diagnostics: diagnostics,
            chunkDiagnostics: chunkDiagnostics.sorted { lhs, rhs in
                if lhs.sceneID == rhs.sceneID {
                    return lhs.chunkIndex < rhs.chunkIndex
                }
                return lhs.sceneID < rhs.sceneID
            }
        )
    }

    private func finalizeWorkload(
        _ workload: SceneBundleWorkload,
        markedObjects: [MarkedObject],
        previousState: ScriptDocumentState?,
        fallbackPlanner: (_ text: String, _ markedObjects: [MarkedObject], _ state: SceneChunkState?) -> ParsingResult,
        asyncPlanner: ((_ text: String, _ markers: [MarkedObject], _ anchors: SourceAnchorBundle, _ state: SceneChunkState?) async -> ScenePlanProviderResult?)?
    ) -> SceneBundleParsingResult {
        let semaphore = DispatchSemaphore(value: 0)
        var result: SceneBundleParsingResult?
        Task {
            result = await finalizeWorkload(
                workload,
                markedObjects: markedObjects,
                previousState: previousState,
                fallbackPlanner: fallbackPlanner,
                asyncPlanner: asyncPlanner
            )
            semaphore.signal()
        }
        semaphore.wait()
        return result ?? emptyResult(description: workload.finalDescription)
    }

    private func makeDraft(
        scene: ScriptSceneCandidate,
        rawSegment: RawSceneChunkSegment,
        anchors: SceneChunkAnchor,
        registrySnapshot: SceneEntityRegistrySnapshot,
        providerResult: ScenePlanProviderResult?,
        markedObjects: [MarkedObject],
        chunkState: SceneChunkState,
        fallbackPlanner: (_ text: String, _ markedObjects: [MarkedObject], _ state: SceneChunkState?) -> ParsingResult
    ) -> SceneChunkDraft {
        if let providerResult {
            return SceneChunkDraft(
                sceneID: scene.id,
                chunkID: rawSegment.chunkID,
                chunkIndex: rawSegment.chunkIndex,
                sourceText: rawSegment.sourceText,
                sourceRange: rawSegment.sourceRange,
                anchors: anchors,
                registrySnapshot: registrySnapshot,
                plan: providerResult.plan,
                usedFallbackPlanner: false,
                usedLegacyPlanBridge: providerResult.usedLegacySceneScriptBridge,
                confidence: 0.9,
                unresolvedMentions: anchors.pronounMentions,
                reasonCodes: providerResult.usedLegacySceneScriptBridge ? ["v1.legacy_scene_bridge_chunk"] : ["v1.local_chunk_plan"]
            )
        }

        let fallback = fallbackPlanner(rawSegment.sourceText, markedObjects, chunkState)
        let bridgedPlan = bridgePlan(
            from: fallback.script,
            markedObjects: markedObjects,
            anchors: anchors.sourceBundle
        )
        return SceneChunkDraft(
            sceneID: scene.id,
            chunkID: rawSegment.chunkID,
            chunkIndex: rawSegment.chunkIndex,
            sourceText: rawSegment.sourceText,
            sourceRange: rawSegment.sourceRange,
            anchors: anchors,
            registrySnapshot: registrySnapshot,
            plan: bridgedPlan,
            usedFallbackPlanner: true,
            usedLegacyPlanBridge: true,
            confidence: max(0.3, fallback.diagnostics.confidence),
            unresolvedMentions: anchors.pronounMentions,
            reasonCodes: ["v1.rule_chunk_plan"]
        )
    }

    private func bridgePlan(
        from script: SceneScript,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle
    ) -> ScenePlanIR {
        let actorRefMap = Dictionary(uniqueKeysWithValues: script.actors.enumerated().map { index, actor in
            let ref = index == 0 ? "first" : (index == 1 ? "second" : (index == 2 ? "third" : "actor_ref_\(index + 1)"))
            return (actor.id, ref)
        })

        var objectCounter = 1
        let objectRefMap = Dictionary(uniqueKeysWithValues: script.objects.map { object in
            let ref: String
            if object.id.hasPrefix("object_marked_") {
                ref = object.id
            } else {
                ref = "object_slot_\(objectCounter)"
                objectCounter += 1
            }
            return (object.id, ref)
        })

        let actors = script.actors.enumerated().map { index, actor in
            ScenePlanIR.Actor(
                ref: index == 0 ? "first" : (index == 1 ? "second" : (index == 2 ? "third" : "actor_ref_\(index + 1)")),
                type: actor.type,
                name: actor.name
            )
        }

        let objects = script.objects.map { object in
            ScenePlanIR.Object(
                ref: objectRefMap[object.id] ?? object.id,
                type: object.type,
                relativePosition: object.relativePosition,
                name: object.name,
                markedObjectID: object.id.hasPrefix("object_marked_") ? object.id : nil
            )
        }

        let beats = script.beats.enumerated().map { beatIndex, beat in
            ScenePlanIR.Beat(
                ref: beat.id.isEmpty ? "beat_\(beatIndex + 1)" : beat.id,
                phase: anchors.phaseCues.first,
                actions: beat.actions.map { action in
                    ScenePlanIR.Action(
                        actorRef: actorRefMap[action.actorId] ?? "first",
                        type: action.type,
                        targetRef: bridgeTargetRef(for: action.target, actorRefMap: actorRefMap, objectRefMap: objectRefMap),
                        direction: action.direction,
                        modifier: action.modifier,
                        resultingPose: action.resultingPose,
                        holdingObjectRef: bridgeTargetRef(for: action.holdingObject, actorRefMap: [:], objectRefMap: objectRefMap),
                        dialogue: action.dialogue,
                        fallbackText: action.fallbackText,
                        sourceText: action.sourceText
                    )
                },
                minDuration: beat.minDuration
            )
        }

        let relations = script.spatialRelations.map { relation in
            ScenePlanIR.SpatialRelation(
                ref: relation.id,
                subjectRef: bridgeTargetRef(for: relation.subject, actorRefMap: actorRefMap, objectRefMap: objectRefMap) ?? relation.subject,
                relation: relation.relation,
                objectRef: bridgeTargetRef(for: relation.object, actorRefMap: actorRefMap, objectRefMap: objectRefMap) ?? relation.object
            )
        }

        let markedObjectIDs = objects.compactMap { $0.markedObjectID ?? ($0.ref.hasPrefix("object_marked_") ? $0.ref : nil) }
        let aliasBindings = Dictionary(uniqueKeysWithValues: markedObjects.map { marker in
            (marker.name.lowercased(), marker.canonicalMarkedObjectID)
        })

        return ScenePlanIR(
            actors: actors,
            objects: objects,
            beats: beats,
            spatialRelations: relations,
            referenceBindings: .init(
                actorBindings: Dictionary(uniqueKeysWithValues: actors.enumerated().map { index, actor in
                    (actor.ref, "actor_\(index + 1)")
                }),
                markedObjectIDs: markedObjectIDs,
                aliasToObjectRef: aliasBindings
            )
        )
    }

    private func bridgeTargetRef(
        for targetID: String?,
        actorRefMap: [String: String],
        objectRefMap: [String: String]
    ) -> String? {
        guard let targetID, !targetID.isEmpty else { return nil }
        if let actorRef = actorRefMap[targetID] {
            return actorRef
        }
        if let objectRef = objectRefMap[targetID] {
            return objectRef
        }
        return nil
    }

    private func makeDiagnostics(
        bundleScript: SceneBundleScript,
        activeSceneScript: SceneScript?,
        fullDescription: String,
        markedObjects: [MarkedObject],
        chunkDiagnostics: [SceneChunkDiagnostics]
    ) -> ParsingDiagnostics {
        guard let activeSceneScript else {
            return ParsingDiagnostics(
                confidence: 0.0,
                coverage: 0.0,
                missingActors: true,
                missingObjects: true,
                unresolvedPronouns: true,
                unresolvedMarkedObjects: !markedObjects.isEmpty,
                notes: ["bundle_empty"],
                matchedMarkedObjects: []
            )
        }

        let matchedMarkedObjectsSet = Set<UUID>(bundleScript.scenes.flatMap { scene in
            scene.objects.compactMap { object in
                guard let shortID = object.markedObjectShortID else { return nil }
                return markedObjects.first(where: { $0.markedShortID == shortID })?.id
            }
        })
        let matchedMarkedObjects = Array(matchedMarkedObjectsSet)

        var notes = bundleScript.diagnostics
        notes.append("active_scene_index=\(bundleScript.activeSceneIndex)")
        notes.append("chunk_count=\(chunkDiagnostics.count)")
        let unresolvedPronouns = chunkDiagnostics.contains { !$0.anchors.pronounMentions.isEmpty && $0.reasonCodes.contains("v1.rule_chunk_plan") }
        return ParsingDiagnostics(
            confidence: min(1.0, max(0.3, 0.55 + Float(bundleScript.scenes.count) * 0.05)),
            coverage: activeSceneScript.originalDescription.isEmpty ? 0.0 : min(1.0, Float(activeSceneScript.originalDescription.count) / Float(max(fullDescription.count, 1))),
            missingActors: activeSceneScript.actors.isEmpty,
            missingObjects: activeSceneScript.objects.isEmpty && markedObjects.isEmpty == false,
            unresolvedPronouns: unresolvedPronouns,
            unresolvedMarkedObjects: !matchedMarkedObjects.isEmpty ? false : !markedObjects.isEmpty,
            notes: notes,
            matchedMarkedObjects: matchedMarkedObjects
        )
    }

    private func unitsIntersecting(_ range: ScriptOffsetRange, units: [NormalizedScriptUnit]) -> [NormalizedScriptUnit] {
        units.filter { unit in
            unit.charRange.end >= range.start && unit.charRange.start <= range.end
        }
    }

    private func emptyResult(description: String) -> SceneBundleParsingResult {
        let bundlePlan = SceneBundlePlan(bundleID: UUID().uuidString.lowercased(), scenes: [], activeSceneIndex: 0, diagnostics: ["bundle_empty"])
        let bundleScript = SceneBundleScript(bundleID: bundlePlan.bundleID, scenes: [], activeSceneIndex: 0, diagnostics: bundlePlan.diagnostics)
        let documentState = ScriptDocumentState(
            documentID: UUID().uuidString.lowercased(),
            mode: .full,
            sourceText: description,
            normalizedUnits: [],
            sceneCandidates: [],
            stitchStates: [],
            bundlePlan: bundlePlan,
            bundleScript: bundleScript,
            activeSceneIndex: 0
        )
        return SceneBundleParsingResult(
            bundleScript: bundleScript,
            activeSceneScript: nil,
            activeSceneId: nil,
            sceneChunks: [],
            documentState: documentState,
            diagnostics: .empty,
            chunkDiagnostics: []
        )
    }

    private func makeWorkload(description: String, mode: SceneBundleParseMode, previousState: ScriptDocumentState?) -> SceneBundleWorkload {
        if mode == .append,
           let previousState,
           description.hasPrefix(previousState.sourceText) {
            return makeAppendWorkload(description: description, previousState: previousState)
        }
        if mode == .full, let previousState {
            return makeFullReuseWorkload(description: description, previousState: previousState)
        }

        let units = normalizer.normalize(description: description)
        let scenes = boundaryDetector.detect(units: units, originalText: description, metadataExtractor: metadataExtractor)
        return SceneBundleWorkload(
            documentID: previousState?.documentID ?? UUID().uuidString.lowercased(),
            bundleID: previousState?.bundlePlan.bundleID ?? UUID().uuidString.lowercased(),
            mode: mode,
            units: units,
            finalDescription: description,
            finalSceneCandidates: scenes,
            pendingScenes: scenes,
            reusedStates: [],
            reusedSceneEntries: [],
            reusedChunks: [],
            reusedChunkDiagnostics: [],
            coldStartSceneIDs: []
        )
    }

    private func makeFullReuseWorkload(description: String, previousState: ScriptDocumentState) -> SceneBundleWorkload {
        let units = normalizer.normalize(description: description)
        let scenes = boundaryDetector.detect(units: units, originalText: description, metadataExtractor: metadataExtractor)

        var reusedStates: [SceneStitchState] = []
        var reusedEntries: [SceneBundlePlan.SceneEntry] = []
        var reusedChunks: [SceneChunk] = []
        var reusedChunkDiagnostics: [SceneChunkDiagnostics] = []
        var pendingScenes: [ScriptSceneCandidate] = []

        for (index, scene) in scenes.enumerated() {
            guard previousState.sceneCandidates.indices.contains(index) else {
                pendingScenes.append(scene)
                continue
            }
            let previousScene = previousState.sceneCandidates[index]
            let sameScene = previousScene.sourceText == scene.sourceText
                && previousScene.heading == scene.heading
                && previousScene.isImplicit == scene.isImplicit
            if sameScene,
               let state = previousState.stitchStates.first(where: { $0.sceneID == previousScene.id }),
               let entry = previousState.bundlePlan.scenes.first(where: { $0.sceneID == previousScene.id }) {
                reusedStates.append(state)
                reusedEntries.append(entry)
                reusedChunks.append(contentsOf: entry.chunks)
                reusedChunkDiagnostics.append(contentsOf: entry.chunks.map {
                    SceneChunkDiagnostics(
                        sceneID: $0.sceneID,
                        chunkID: $0.chunkID,
                        chunkIndex: $0.chunkIndex,
                        reasonCodes: $0.reasonCodes,
                        unresolvedRefs: $0.deferredRefs.map(\.id),
                        anchors: $0.anchors,
                        usedFallbackPlanner: $0.usedFallbackPlanner,
                        usedLegacyPlanBridge: $0.usedLegacyPlanBridge
                    )
                })
            } else {
                pendingScenes.append(scene)
            }
        }

        return SceneBundleWorkload(
            documentID: previousState.documentID,
            bundleID: previousState.bundlePlan.bundleID,
            mode: .full,
            units: units,
            finalDescription: description,
            finalSceneCandidates: scenes,
            pendingScenes: pendingScenes,
            reusedStates: reusedStates,
            reusedSceneEntries: reusedEntries,
            reusedChunks: reusedChunks,
            reusedChunkDiagnostics: reusedChunkDiagnostics,
            coldStartSceneIDs: []
        )
    }

    private func makeAppendWorkload(description: String, previousState: ScriptDocumentState) -> SceneBundleWorkload {
        let suffix = String(description.dropFirst(previousState.sourceText.count))
        guard !suffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return SceneBundleWorkload(
                documentID: previousState.documentID,
                bundleID: previousState.bundlePlan.bundleID,
                mode: .append,
                units: previousState.normalizedUnits,
                finalDescription: description,
                finalSceneCandidates: previousState.sceneCandidates,
                pendingScenes: [],
                reusedStates: previousState.stitchStates,
                reusedSceneEntries: previousState.bundlePlan.scenes,
                reusedChunks: previousState.bundlePlan.scenes.flatMap(\.chunks),
                reusedChunkDiagnostics: previousState.bundlePlan.scenes.flatMap { scene in
                    scene.chunks.map {
                        SceneChunkDiagnostics(
                            sceneID: $0.sceneID,
                            chunkID: $0.chunkID,
                            chunkIndex: $0.chunkIndex,
                            reasonCodes: $0.reasonCodes,
                            unresolvedRefs: $0.deferredRefs.map(\.id),
                            anchors: $0.anchors,
                            usedFallbackPlanner: $0.usedFallbackPlanner,
                            usedLegacyPlanBridge: $0.usedLegacyPlanBridge
                        )
                    }
                },
                coldStartSceneIDs: []
            )
        }

        let suffixUnits = normalizer.normalize(description: suffix)
        let suffixScenes = boundaryDetector.detect(units: suffixUnits, originalText: suffix, metadataExtractor: metadataExtractor)
        let startsWithImplicitContinuation = suffixScenes.first?.isImplicit == true

        var reusedStates = previousState.stitchStates
        var reusedSceneEntries = previousState.bundlePlan.scenes
        var reusedChunks = previousState.bundlePlan.scenes.flatMap(\.chunks)
        var reusedChunkDiagnostics = previousState.bundlePlan.scenes.flatMap { scene in
            scene.chunks.map {
                SceneChunkDiagnostics(
                    sceneID: $0.sceneID,
                    chunkID: $0.chunkID,
                    chunkIndex: $0.chunkIndex,
                    reasonCodes: $0.reasonCodes,
                    unresolvedRefs: $0.deferredRefs.map(\.id),
                    anchors: $0.anchors,
                    usedFallbackPlanner: $0.usedFallbackPlanner,
                    usedLegacyPlanBridge: $0.usedLegacyPlanBridge
                )
            }
        }

        var pendingScenes: [ScriptSceneCandidate] = []
        var finalCandidates = previousState.sceneCandidates
        let units = normalizer.normalize(description: description)

        if startsWithImplicitContinuation, let lastScene = previousState.sceneCandidates.last {
            let continuedPrefix = lastScene.sourceText
            let firstSuffixScene = suffixScenes[0]
            let combinedText = [continuedPrefix, firstSuffixScene.sourceText]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
            let reparsedUnits = normalizer.normalize(description: combinedText)
            let reparsedScene = ScriptSceneCandidate(
                id: lastScene.id,
                sceneIndex: lastScene.sceneIndex,
                heading: lastScene.heading,
                unitRange: 0..<reparsedUnits.count,
                sourceRange: ScriptOffsetRange(start: 0, end: combinedText.count),
                sourceText: combinedText,
                metadata: metadataExtractor.extract(description: combinedText, fallbackLocationName: lastScene.metadata.locationName),
                isImplicit: lastScene.isImplicit
            )

            if !reusedStates.isEmpty { reusedStates.removeLast() }
            if !reusedSceneEntries.isEmpty { reusedSceneEntries.removeLast() }
            reusedChunks.removeAll { $0.sceneID == lastScene.id }
            reusedChunkDiagnostics.removeAll { $0.sceneID == lastScene.id }
            pendingScenes.append(reparsedScene)

            for suffixScene in suffixScenes.dropFirst() {
                let nextIndex = finalCandidates.count + pendingScenes.count - 1
                pendingScenes.append(
                    ScriptSceneCandidate(
                        id: "scene_\(nextIndex + 1)",
                        sceneIndex: nextIndex,
                        heading: suffixScene.heading,
                        unitRange: suffixScene.unitRange,
                        sourceRange: suffixScene.sourceRange,
                        sourceText: suffixScene.sourceText,
                        metadata: suffixScene.metadata,
                        isImplicit: suffixScene.isImplicit
                    )
                )
            }
            finalCandidates.removeLast()
            finalCandidates.append(reparsedScene)
            finalCandidates.append(contentsOf: pendingScenes.dropFirst())
        } else {
            let startIndex = previousState.sceneCandidates.count
            pendingScenes = suffixScenes.enumerated().map { offset, scene in
                ScriptSceneCandidate(
                    id: "scene_\(startIndex + offset + 1)",
                    sceneIndex: startIndex + offset,
                    heading: scene.heading,
                    unitRange: scene.unitRange,
                    sourceRange: scene.sourceRange,
                    sourceText: scene.sourceText,
                    metadata: scene.metadata,
                    isImplicit: scene.isImplicit
                )
            }
            finalCandidates.append(contentsOf: pendingScenes)
        }

        return SceneBundleWorkload(
            documentID: previousState.documentID,
            bundleID: previousState.bundlePlan.bundleID,
            mode: .append,
            units: units,
            finalDescription: description,
            finalSceneCandidates: finalCandidates,
            pendingScenes: pendingScenes,
            reusedStates: reusedStates,
            reusedSceneEntries: reusedSceneEntries,
            reusedChunks: reusedChunks,
            reusedChunkDiagnostics: reusedChunkDiagnostics,
            coldStartSceneIDs: startsWithImplicitContinuation ? [previousState.sceneCandidates.last?.id ?? ""] : []
        )
    }
}

private struct SceneBundleWorkload {
    var documentID: String
    var bundleID: String
    var mode: SceneBundleParseMode
    var units: [NormalizedScriptUnit]
    var finalDescription: String
    var finalSceneCandidates: [ScriptSceneCandidate]
    var pendingScenes: [ScriptSceneCandidate]
    var reusedStates: [SceneStitchState]
    var reusedSceneEntries: [SceneBundlePlan.SceneEntry]
    var reusedChunks: [SceneChunk]
    var reusedChunkDiagnostics: [SceneChunkDiagnostics]
    var coldStartSceneIDs: [String]

    func seedState(for scene: ScriptSceneCandidate, previousState: ScriptDocumentState?) -> SceneStitchState? {
        if coldStartSceneIDs.contains(scene.id) {
            return nil
        }
        return previousState?.stitchStates.first(where: { $0.sceneID == scene.id })
    }
}
