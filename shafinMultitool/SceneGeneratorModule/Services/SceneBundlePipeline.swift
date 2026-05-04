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
    private let inlineSpeakerRegex = try? NSRegularExpression(pattern: #"^([A-ZА-ЯЁ][A-Za-zА-Яа-яЁё0-9 \-_.]{1,40}):\s*(.+)$"#)

    func normalize(description: String) -> [NormalizedScriptUnit] {
        let prepared = description
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "—", with: " — ")
        let lines = prepared.components(separatedBy: "\n")

        var units: [NormalizedScriptUnit] = []
        var cursor = 0
        var previousNonBlankKind: NormalizedScriptUnitKind?
        var screenTextMode = false

        func appendRawUnit(kind: NormalizedScriptUnitKind, text: String, lineIndex: Int, range: ScriptOffsetRange) {
            units.append(
                NormalizedScriptUnit(
                    id: "unit_\(units.count + 1)",
                    kind: kind,
                    text: text,
                    lineIndex: lineIndex,
                    charRange: range
                )
            )
            if kind != .blank {
                previousNonBlankKind = kind
            }
        }

        func appendUnit(kind: NormalizedScriptUnitKind, text: String, lineIndex: Int, range: ScriptOffsetRange) {
            guard kind == .dialogue else {
                appendRawUnit(kind: kind, text: text, lineIndex: lineIndex, range: range)
                return
            }

            let (dialogueText, stageNotes) = splitStageNotes(from: text)
            for segment in splitLongDialogue(dialogueText) {
                appendRawUnit(kind: .dialogue, text: segment, lineIndex: lineIndex, range: range)
            }
            for note in stageNotes {
                appendRawUnit(kind: .stageNote, text: note, lineIndex: lineIndex, range: range)
            }
        }

        for (lineIndex, rawLine) in lines.enumerated() {
            let rawLength = rawLine.count
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                appendUnit(
                    kind: .blank,
                    text: "",
                    lineIndex: lineIndex,
                    range: ScriptOffsetRange(start: cursor, end: cursor + rawLength)
                )
                screenTextMode = false
            } else {
                let normalizedText = rawLine
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if let split = splitInlineSpeakerCue(normalizedText) {
                    appendUnit(
                        kind: .speakerCue,
                        text: split.speaker,
                        lineIndex: lineIndex,
                        range: ScriptOffsetRange(start: cursor, end: cursor + split.speaker.count)
                    )
                    appendUnit(
                        kind: .dialogue,
                        text: split.dialogue,
                        lineIndex: lineIndex,
                        range: ScriptOffsetRange(start: cursor + split.speaker.count + 1, end: cursor + rawLength)
                    )
                    screenTextMode = false
                } else {
                    let kind = classify(
                        line: normalizedText,
                        previousNonBlankKind: previousNonBlankKind,
                        screenTextMode: screenTextMode
                    )
                    appendUnit(
                        kind: kind,
                        text: normalizedText,
                        lineIndex: lineIndex,
                        range: ScriptOffsetRange(start: cursor, end: cursor + rawLength)
                    )
                    let lowercased = normalizedText.lowercased()
                    screenTextMode = lowercased.contains("на экране появляются надписи")
                        || (screenTextMode && kind == .screenText)
                }
            }
            cursor += rawLength + 1
        }

        return units
    }

    private func splitInlineSpeakerCue(_ line: String) -> (speaker: String, dialogue: String)? {
        guard headingDetector.extract(description: line).sceneHeading == nil,
              let inlineSpeakerRegex
        else { return nil }
        let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = inlineSpeakerRegex.firstMatch(in: line, range: nsRange),
              let speakerRange = Range(match.range(at: 1), in: line),
              let dialogueRange = Range(match.range(at: 2), in: line)
        else { return nil }
        let speaker = String(line[speakerRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let dialogue = String(line[dialogueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !speaker.isEmpty, !dialogue.isEmpty else { return nil }
        return (speaker, dialogue)
    }

    private func splitStageNotes(from text: String) -> (dialogue: String, stageNotes: [String]) {
        let pattern = #"\*([^*]+)\*"#
        let nsText = text as NSString
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (text, [])
        }
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        let notes = matches.compactMap { match -> String? in
            guard match.numberOfRanges > 1 else { return nil }
            let note = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            return note.isEmpty ? nil : note
        }
        let dialogue = regex
            .stringByReplacingMatches(in: text, range: NSRange(location: 0, length: nsText.length), withTemplate: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (dialogue, notes)
    }

    private func splitLongDialogue(_ text: String, maxCharacters: Int = 170) -> [String] {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }
        guard cleaned.count > maxCharacters else { return [cleaned] }

        let nsText = cleaned as NSString
        let sentenceRegex = try? NSRegularExpression(pattern: #"[^.!?…]+[.!?…]?"#)
        let sentences = sentenceRegex?
            .matches(in: cleaned, range: NSRange(location: 0, length: nsText.length))
            .map { nsText.substring(with: $0.range).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        var chunks: [String] = []
        var current = ""
        for sentence in sentences.isEmpty ? [cleaned] : sentences {
            if current.isEmpty {
                current = sentence
            } else if current.count + sentence.count + 1 <= maxCharacters {
                current += " " + sentence
            } else {
                chunks.append(current)
                current = sentence
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    private func classify(
        line: String,
        previousNonBlankKind: NormalizedScriptUnitKind?,
        screenTextMode: Bool
    ) -> NormalizedScriptUnitKind {
        if headingDetector.extract(description: line).sceneHeading != nil {
            return .sceneHeading
        }
        if line.hasPrefix("*"), line.hasSuffix("*") {
            return .stageNote
        }
        if line.hasPrefix("("), line.hasSuffix(")") {
            return .parenthetical
        }
        if screenTextMode, isLikelyScreenText(line) {
            return .screenText
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

    private func isLikelyScreenText(_ line: String) -> Bool {
        guard !line.contains(":") else { return false }
        guard line.count <= 80 else { return false }
        let lowercased = line.lowercased()
        let actionWords = ["сидит", "идёт", "идет", "говорит", "смотрит", "берёт", "берет", "кладёт", "кладет"]
        return !actionWords.contains(where: { lowercased.contains($0) })
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
        if let firstHeading = headingIndices.first, firstHeading > 0 {
            let preHeadingUnits = Array(units[0..<firstHeading])
            let contentUnits = preHeadingUnits.filter { $0.kind != .blank }
            if !contentUnits.isEmpty {
                let sourceText = render(units: preHeadingUnits)
                scenes.append(
                    ScriptSceneCandidate(
                        id: "scene_1",
                        sceneIndex: 0,
                        heading: nil,
                        unitRange: 0..<firstHeading,
                        sourceRange: ScriptOffsetRange(
                            start: preHeadingUnits.first?.charRange.start ?? 0,
                            end: preHeadingUnits.last?.charRange.end ?? 0
                        ),
                        sourceText: sourceText,
                        metadata: SceneTopLevelMetadata(
                            sceneHeading: "MONTAGE",
                            locationName: "montage",
                            interiorExterior: nil,
                            timeOfDay: nil
                        ),
                        isImplicit: true,
                        isMontage: true
                    )
                )
            }
        }
        for (sceneOrdinal, startIndex) in headingIndices.enumerated() {
            let endIndex = headingIndices.dropFirst(sceneOrdinal + 1).first ?? units.count
            let sceneUnits = Array(units[startIndex..<endIndex])
            let contentUnits = sceneUnits.filter { $0.kind != .blank }
            guard contentUnits.count > 1 else { continue }
            let sourceText = render(units: sceneUnits)
            let metadata = metadataExtractor.extract(description: sourceText)
            if let splitIndex = implicitShotSplitIndex(in: sceneUnits, absoluteStartIndex: startIndex) {
                appendSceneCandidate(
                    units: Array(units[startIndex..<splitIndex]),
                    unitRange: startIndex..<splitIndex,
                    metadata: metadata,
                    isImplicit: false,
                    to: &scenes
                )
                let shotUnits = Array(units[splitIndex..<endIndex])
                let shotText = render(units: shotUnits)
                let shotMetadata = metadataExtractor.extract(description: shotText, fallbackLocationName: metadata.locationName)
                appendSceneCandidate(
                    units: shotUnits,
                    unitRange: splitIndex..<endIndex,
                    metadata: shotMetadata,
                    isImplicit: true,
                    to: &scenes
                )
            } else {
                appendSceneCandidate(
                    units: sceneUnits,
                    unitRange: startIndex..<endIndex,
                    metadata: metadata,
                    isImplicit: false,
                    to: &scenes
                )
            }
        }

        return scenes
    }

    private func appendSceneCandidate(
        units: [NormalizedScriptUnit],
        unitRange: Range<Int>,
        metadata: SceneTopLevelMetadata,
        isImplicit: Bool,
        to scenes: inout [ScriptSceneCandidate]
    ) {
        let contentUnits = units.filter { $0.kind != .blank }
        guard !contentUnits.isEmpty else { return }
        let sourceText = render(units: units)
        let sourceRange = ScriptOffsetRange(
            start: units.first?.charRange.start ?? 0,
            end: units.last?.charRange.end ?? 0
        )
        scenes.append(
            ScriptSceneCandidate(
                id: "scene_\(scenes.count + 1)",
                sceneIndex: scenes.count,
                heading: metadata.sceneHeading,
                unitRange: unitRange,
                sourceRange: sourceRange,
                sourceText: sourceText,
                metadata: metadata,
                isImplicit: isImplicit
            )
        )
    }

    private func implicitShotSplitIndex(in sceneUnits: [NormalizedScriptUnit], absoluteStartIndex: Int) -> Int? {
        var dialogueCharacterCount = 0
        var dialogueUnitCount = 0
        for (localIndex, unit) in sceneUnits.enumerated() {
            switch unit.kind {
            case .dialogue:
                dialogueCharacterCount += unit.text.count
                dialogueUnitCount += 1
            case .actionLine, .proseLine:
                if (dialogueCharacterCount > 450 || dialogueUnitCount >= 4),
                   looksLikeNamedActorPhysicalAction(unit.text) {
                    return absoluteStartIndex + localIndex
                }
            default:
                continue
            }
        }
        return nil
    }

    private func looksLikeNamedActorPhysicalAction(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let physicalCues = ["сидит", "стоит", "идёт", "идет", "смотрит", "берёт", "берет", "кладёт", "кладет", "подходит", "останавливается"]
        guard physicalCues.contains(where: { lowercased.contains($0) }) else { return false }
        guard let firstScalar = text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.first else { return false }
        return CharacterSet.uppercaseLetters.contains(firstScalar)
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
            lastResolvedSpeaker: registry.lastResolvedSpeaker,
            previousChunkSummary: registry.previousChunkSummary,
            openBeatContext: registry.openBeatContext,
            lastActorPositions: registry.lastActorPositions
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
        let existingActorsInOrder = stitchState?.actors ?? []
        let existingObjectsInOrder = stitchState?.objects ?? []
        var deferredRefs: [SceneDeferredRef] = []
        var orderedStableActorRefs: [String] = existingActorsInOrder.map(\.ref)
        let chunkSourceText = draft.sourceText.lowercased()

        for (index, actor) in draft.plan.actors.enumerated() {
            let normalizedName = normalizeAlias(actor.name)
            let stableRef: String
            if let existing = actorRefMap[actor.ref] {
                stableRef = existing
            } else if let normalizedName, let existing = actorAliasMap[normalizedName] {
                stableRef = existing
            } else if let ordinalRef = resolveOrdinalActorRef(actor.ref, index: index, existingActors: existingActorsInOrder) {
                stableRef = ordinalRef
            } else {
                stableRef = makeStableActorRef(
                    rawRef: actor.ref,
                    normalizedName: normalizedName,
                    sceneIndex: sceneIndex,
                    existingActorMap: existingActorMap,
                    createdActors: createdActors
                )
            }

            if existingActorMap[stableRef] == nil && !createdActors.contains(where: { $0.ref == stableRef }) {
                let created = ScenePlanIR.Actor(ref: stableRef, type: actor.type, name: normalizedName ?? actor.name)
                createdActors.append(created)
                existingActorMap[stableRef] = created
            }

            actorRefMap[actor.ref] = stableRef
            if !orderedStableActorRefs.contains(stableRef) {
                orderedStableActorRefs.append(stableRef)
            }
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

        let referencedObjectRefs = Set(
            draft.plan.beats
                .flatMap(\.actions)
                .flatMap { [$0.targetRef, $0.holdingObjectRef] }
                .compactMap { $0 }
        )

        for object in draft.plan.objects {
            guard shouldAcceptObject(
                object,
                chunkSourceText: chunkSourceText,
                anchors: draft.anchors,
                existingObjects: existingObjectsInOrder,
                objectAliasMap: objectAliasMap,
                referencedObjectRefs: referencedObjectRefs
            ) else {
                if !reasonCodes.contains("v1.hallucinated_object_skipped") {
                    reasonCodes.append("v1.hallucinated_object_skipped")
                }
                continue
            }

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

        let beatPatch = draft.plan.beats.enumerated().compactMap { beatIndex, beat -> ScenePlanIR.Beat? in
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
                let newAction = normalizeActionSemantics(
                    action: ScenePlanIR.Action(
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
                    ),
                    orderedActorRefs: orderedStableActorRefs,
                    anchorBundle: draft.anchors.sourceBundle,
                    objectMap: objectRefMap,
                    objectAliasMap: objectAliasMap
                )
                if newAction.type == .describedAction,
                   !reasonCodes.contains("v1.unsupported_action_described") {
                    reasonCodes.append("v1.unsupported_action_described")
                }
                actions.append(newAction)
            }
            if shouldDropUngroundedStandBeat(actions: actions, chunkSourceText: draft.sourceText) {
                if !reasonCodes.contains("v1.ungrounded_stand_beat_dropped") {
                    reasonCodes.append("v1.ungrounded_stand_beat_dropped")
                }
                return nil
            }
            actions = normalizeCollectiveBeatSemantics(
                actions: actions,
                orderedActorRefs: orderedStableActorRefs,
                beatPhase: beat.phase,
                chunkSourceText: draft.sourceText,
                objectMap: objectRefMap,
                objectAliasMap: objectAliasMap,
                reasonCodes: &reasonCodes
            )
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

        let stateDelta = makeStateDelta(
            beats: beatPatch,
            metadata: draft.registrySnapshot.locationName ?? draft.anchors.locationCues.first,
            sourceText: draft.sourceText
        )

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
        let lowered = rawRef.lowercased()
        if !anchors.speakerCues.isEmpty,
           ["он", "она", "они", "герой", "героиня", "человек", "персонаж"].contains(lowered),
           let fallback = existingActors.first?.ref {
            return fallback
        }
        return nil
    }

    private func shouldAcceptObject(
        _ object: ScenePlanIR.Object,
        chunkSourceText: String,
        anchors: SceneChunkAnchor,
        existingObjects: [ScenePlanIR.Object],
        objectAliasMap: [String: String],
        referencedObjectRefs: Set<String>
    ) -> Bool {
        if object.ref.hasPrefix("object_marked_") || (object.markedObjectID?.hasPrefix("object_marked_") ?? false) {
            return true
        }
        if referencedObjectRefs.contains(object.ref) {
            return true
        }
        if existingObjects.contains(where: { $0.ref == object.ref }) {
            return true
        }

        let normalizedName = normalizeAlias(object.name)
        if let normalizedName, objectAliasMap[normalizedName] != nil {
            return true
        }
        if let normalizedName, chunkSourceText.contains(normalizedName) {
            return true
        }

        let surfaceMentions = Set(anchors.sourceBundle.objectSurfaceMentions.map { $0.lowercased() })
        if let normalizedName, surfaceMentions.contains(normalizedName) {
            return true
        }
        if surfaceMentions.contains(object.type.rawValue.lowercased()) {
            return true
        }

        return false
    }

    private func shouldDropUngroundedStandBeat(actions: [ScenePlanIR.Action], chunkSourceText: String) -> Bool {
        guard !actions.isEmpty, actions.allSatisfy({ $0.type == .stand }) else {
            return false
        }
        let lowercased = chunkSourceText.lowercased()
        let hasStandCue = lowercased.contains("стоит")
            || lowercased.contains("стоят")
            || lowercased.contains("остан")
            || lowercased.contains("жд")
        let hasMotionCue = lowercased.contains("ид")
            || lowercased.contains("подход")
            || lowercased.contains("направ")
            || lowercased.contains("навстреч")
        return hasMotionCue && !hasStandCue
    }

    private func makeStableActorRef(
        rawRef: String,
        normalizedName: String?,
        sceneIndex: Int,
        existingActorMap: [String: ScenePlanIR.Actor],
        createdActors: [ScenePlanIR.Actor]
    ) -> String {
        if ["first", "second", "third"].contains(rawRef),
           existingActorMap[rawRef] == nil,
           !createdActors.contains(where: { $0.ref == rawRef }) {
            return rawRef
        }

        let slug = slugify(normalizedName ?? "actor")
        let nextIndex = existingActorMap.count + createdActors.count + 1
        return "actor_scene\(sceneIndex)_\(slug)_\(nextIndex)"
    }

    private func normalizeActionSemantics(
        action: ScenePlanIR.Action,
        orderedActorRefs: [String],
        anchorBundle: SourceAnchorBundle,
        objectMap: [String: String],
        objectAliasMap: [String: String]
    ) -> ScenePlanIR.Action {
        guard action.type == .walk || action.type == .run else {
            return action
        }

        var normalized = action
        let actionText = (action.sourceText ?? action.fallbackText ?? "").lowercased()

        if let explicitObjectTarget = inferObjectTarget(
            from: actionText,
            objectMap: objectMap,
            objectAliasMap: objectAliasMap
        ) {
            if normalized.targetRef == nil || orderedActorRefs.contains(normalized.targetRef ?? "") {
                normalized.targetRef = explicitObjectTarget
            }
            if normalized.direction == nil, actionText.contains(" к ") || actionText.hasPrefix("к ") {
                normalized.direction = .toTarget
            }
            return normalized
        }

        let shouldMoveTowardEachOther = actionTextIndicatesTowardEachOther(actionText)
            || (actionText.isEmpty && anchorBundle.phaseCues.contains("navstrechu"))

        guard shouldMoveTowardEachOther,
              orderedActorRefs.count >= 2,
              normalized.direction == nil else {
            return normalized
        }

        normalized.direction = .towardEachOther
        if normalized.targetRef == nil,
           let actorIndex = orderedActorRefs.firstIndex(of: action.actorRef) {
            let counterpartIndex = actorIndex == 0 ? 1 : 0
            if orderedActorRefs.indices.contains(counterpartIndex) {
                normalized.targetRef = orderedActorRefs[counterpartIndex]
            }
        }
        return normalized
    }

    private func actionTextIndicatesTowardEachOther(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        return text.contains("навстреч")
            || text.contains("друг к другу")
            || text.contains("друг на друга")
            || text.contains("другому")
    }

    private func inferObjectTarget(
        from actionText: String,
        objectMap: [String: String],
        objectAliasMap: [String: String]
    ) -> String? {
        guard !actionText.isEmpty else { return nil }

        for (alias, objectRef) in objectAliasMap.sorted(by: { $0.key.count > $1.key.count }) {
            if actionTextMentionsAlias(actionText, alias: alias) {
                return objectRef
            }
        }

        if (actionText.contains(" к ") || actionText.hasPrefix("к ")) && objectMap.count == 1 {
            return objectMap.values.first
        }

        return nil
    }

    private func actionTextMentionsAlias(_ actionText: String, alias: String) -> Bool {
        if actionText.contains(alias) {
            return true
        }

        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedAlias.count >= 5 else { return false }
        let prefixLength = min(5, trimmedAlias.count - 1)
        let prefix = String(trimmedAlias.prefix(prefixLength))
        return actionText.contains(prefix)
    }

    private func normalizeCollectiveBeatSemantics(
        actions: [ScenePlanIR.Action],
        orderedActorRefs: [String],
        beatPhase: String?,
        chunkSourceText: String,
        objectMap: [String: String],
        objectAliasMap: [String: String],
        reasonCodes: inout [String]
    ) -> [ScenePlanIR.Action] {
        var normalizedTowardEachOther = normalizeCollectiveTowardEachOtherBeat(
            actions: actions,
            orderedActorRefs: orderedActorRefs,
            beatPhase: beatPhase,
            chunkSourceText: chunkSourceText,
            reasonCodes: &reasonCodes
        )

        if let collectiveStopTarget = collectiveStopNearObjectTarget(
            chunkSourceText: chunkSourceText,
            objectMap: objectMap,
            objectAliasMap: objectAliasMap
        ) {
            normalizedTowardEachOther = expandCollectiveStopNearObject(
                actions: normalizedTowardEachOther,
                orderedActorRefs: orderedActorRefs,
                targetRef: collectiveStopTarget,
                chunkSourceText: chunkSourceText,
                reasonCodes: &reasonCodes
            )
        }
        if let collectivePassByTarget = collectivePassByObjectTarget(
            chunkSourceText: chunkSourceText,
            objectMap: objectMap,
            objectAliasMap: objectAliasMap
        ) {
            normalizedTowardEachOther = expandCollectivePassByObject(
                actions: normalizedTowardEachOther,
                orderedActorRefs: orderedActorRefs,
                targetRef: collectivePassByTarget,
                chunkSourceText: chunkSourceText,
                reasonCodes: &reasonCodes
            )
        }

        guard orderedActorRefs.count >= 2,
              chunkTextIndicatesCollectiveApproach(chunkSourceText) else {
            return normalizedTowardEachOther
        }

        guard let seedAction = normalizedTowardEachOther.first(where: { action in
            (action.type == .approach || action.direction == .toTarget) &&
            (action.targetRef?.hasPrefix("object_") ?? false)
        }) else {
            return normalizedTowardEachOther
        }

        var normalized = normalizedTowardEachOther
        let actorsWithActions = Set(normalizedTowardEachOther.map(\.actorRef))
        let targetRef = seedAction.targetRef

        for index in normalized.indices {
            let action = normalized[index]
            guard action.actorRef != seedAction.actorRef else { continue }
            let shouldReplace = action.type == .stand
                || action.type == .stop
                || action.direction == .towardEachOther
                || ((action.type == .walk || action.type == .run) && (action.targetRef?.hasPrefix("actor_") ?? false))
            guard shouldReplace else { continue }

            normalized[index] = ScenePlanIR.Action(
                actorRef: action.actorRef,
                type: .approach,
                targetRef: targetRef,
                direction: .toTarget,
                modifier: seedAction.modifier,
                resultingPose: .walking,
                holdingObjectRef: action.holdingObjectRef,
                dialogue: action.dialogue,
                fallbackText: action.fallbackText,
                sourceText: action.sourceText ?? seedAction.sourceText
            )
        }

        let missingActors = orderedActorRefs.filter { !actorsWithActions.contains($0) }
        for actorRef in missingActors {
            normalized.append(
                ScenePlanIR.Action(
                    actorRef: actorRef,
                    type: .approach,
                    targetRef: targetRef,
                    direction: .toTarget,
                    modifier: seedAction.modifier,
                    resultingPose: .walking,
                    holdingObjectRef: nil,
                    dialogue: nil,
                    fallbackText: nil,
                    sourceText: seedAction.sourceText
                )
            )
        }

        if !reasonCodes.contains("v1.collective_object_motion_hotfix_v2") {
            reasonCodes.append("v1.collective_object_motion_hotfix_v2")
        }
        if !reasonCodes.contains("v9.collective_action_expanded") {
            reasonCodes.append("v9.collective_action_expanded")
        }
        if normalized != actions, !reasonCodes.contains("v1.collective_motion_expanded") {
            reasonCodes.append("v1.collective_motion_expanded")
        }

        return normalized
    }

    private func collectivePassByObjectTarget(
        chunkSourceText: String,
        objectMap: [String: String],
        objectAliasMap: [String: String]
    ) -> String? {
        let lowercased = chunkSourceText.lowercased()
        let hasPluralActorCue = lowercased.contains("оба")
            || lowercased.contains("обе")
            || lowercased.contains("первый") && lowercased.contains("второй")
            || lowercased.contains("2 акт")
            || lowercased.contains("два акт")
        let hasPassByCue = lowercased.contains("проход")
            && (lowercased.contains("мимо") || lowercased.contains("возле") || lowercased.contains("около"))
        guard hasPluralActorCue && hasPassByCue else {
            return nil
        }
        return inferObjectTarget(from: lowercased, objectMap: objectMap, objectAliasMap: objectAliasMap)
    }

    private func expandCollectivePassByObject(
        actions: [ScenePlanIR.Action],
        orderedActorRefs: [String],
        targetRef: String,
        chunkSourceText: String,
        reasonCodes: inout [String]
    ) -> [ScenePlanIR.Action] {
        guard orderedActorRefs.count >= 2 else { return actions }

        var normalized = actions
        let firstTwoActors = Array(orderedActorRefs.prefix(2))
        for actorRef in firstTwoActors {
            if let existingIndex = normalized.firstIndex(where: { $0.actorRef == actorRef && $0.type == .passBy }) {
                normalized[existingIndex].targetRef = targetRef
                normalized[existingIndex].sourceText = normalized[existingIndex].sourceText ?? chunkSourceText
            } else if !normalized.contains(where: { $0.actorRef == actorRef && $0.type == .passBy && $0.targetRef == targetRef }) {
                normalized.append(
                    ScenePlanIR.Action(
                        actorRef: actorRef,
                        type: .passBy,
                        targetRef: targetRef,
                        resultingPose: .walking,
                        sourceText: chunkSourceText
                    )
                )
            }
        }

        if normalized != actions, !reasonCodes.contains("v9.collective_pass_by_expanded") {
            reasonCodes.append("v9.collective_pass_by_expanded")
        }
        return normalized
    }

    private func normalizeCollectiveTowardEachOtherBeat(
        actions: [ScenePlanIR.Action],
        orderedActorRefs: [String],
        beatPhase: String?,
        chunkSourceText: String,
        reasonCodes: inout [String]
    ) -> [ScenePlanIR.Action] {
        guard orderedActorRefs.count >= 2 else {
            return actions
        }

        let phaseText = (beatPhase ?? "").lowercased()
        let chunkText = chunkSourceText.lowercased()
        let hasTowardEachOtherCue = phaseText.contains("navstrechu")
            || phaseText.contains("toward_each_other")
            || actionTextIndicatesTowardEachOther(chunkText)
            || actions.contains { action in
                action.direction == .towardEachOther
                    || actionTextIndicatesTowardEachOther((action.sourceText ?? action.fallbackText ?? "").lowercased())
            }
        let chunkHasExplicitObjectTarget = textHasExplicitObjectTarget(chunkText)

        guard hasTowardEachOtherCue else {
            return actions
        }

        var normalized = actions
        let primary = orderedActorRefs[0]
        let secondary = orderedActorRefs[1]

        normalized = normalized.map { action in
            guard action.type == .walk || action.type == .run else { return action }
            if isExplicitObjectMovementAction(action) && chunkHasExplicitObjectTarget {
                if !reasonCodes.contains("v1.object_target_preserved") {
                    reasonCodes.append("v1.object_target_preserved")
                }
                return action
            }
            var updated = action
            if action.actorRef == primary {
                updated.direction = .towardEachOther
                updated.targetRef = secondary
            } else if action.actorRef == secondary {
                updated.direction = .towardEachOther
                updated.targetRef = primary
            }
            return updated
        }

        let existingActorRefs = Set(normalized.map(\.actorRef))
        if !existingActorRefs.contains(primary) {
            normalized.append(
                ScenePlanIR.Action(
                    actorRef: primary,
                    type: .walk,
                    targetRef: secondary,
                    direction: .towardEachOther,
                    modifier: nil,
                    resultingPose: .walking,
                    holdingObjectRef: nil,
                    dialogue: nil,
                    fallbackText: nil,
                    sourceText: "collective_toward_each_other"
                )
            )
        }
        if !existingActorRefs.contains(secondary) {
            normalized.append(
                ScenePlanIR.Action(
                    actorRef: secondary,
                    type: .walk,
                    targetRef: primary,
                    direction: .towardEachOther,
                    modifier: nil,
                    resultingPose: .walking,
                    holdingObjectRef: nil,
                    dialogue: nil,
                    fallbackText: nil,
                    sourceText: "collective_toward_each_other"
                )
            )
        }

        if normalized != actions, !reasonCodes.contains("v1.collective_toward_each_other_expanded") {
            reasonCodes.append("v1.collective_toward_each_other_expanded")
        }
        if normalized != actions, !reasonCodes.contains("v9.reciprocal_motion_expanded") {
            reasonCodes.append("v9.reciprocal_motion_expanded")
        }

        return normalized
    }

    private func collectiveStopNearObjectTarget(
        chunkSourceText: String,
        objectMap: [String: String],
        objectAliasMap: [String: String]
    ) -> String? {
        let lowercased = chunkSourceText.lowercased()
        let hasPluralActorCue = lowercased.contains("оба")
            || lowercased.contains("обе")
            || lowercased.contains("первый") && lowercased.contains("второй")
            || lowercased.contains("2 акт")
            || lowercased.contains("два акт")
        let hasStopCue = lowercased.contains("остан")
        let hasNearCue = lowercased.contains("рядом")
            || lowercased.contains("около")
            || lowercased.contains(" возле ")
            || lowercased.contains(" у ")
        guard hasPluralActorCue && hasStopCue && hasNearCue else {
            return nil
        }
        return inferObjectTarget(from: lowercased, objectMap: objectMap, objectAliasMap: objectAliasMap)
    }

    private func expandCollectiveStopNearObject(
        actions: [ScenePlanIR.Action],
        orderedActorRefs: [String],
        targetRef: String,
        chunkSourceText: String,
        reasonCodes: inout [String]
    ) -> [ScenePlanIR.Action] {
        guard orderedActorRefs.count >= 2 else { return actions }

        var normalized = actions
        let firstTwoActors = Array(orderedActorRefs.prefix(2))
        for actorRef in firstTwoActors {
            if let existingIndex = normalized.firstIndex(where: { $0.actorRef == actorRef && ($0.type == .stand || $0.type == .stop) }) {
                normalized[existingIndex].type = .stop
                normalized[existingIndex].targetRef = targetRef
                normalized[existingIndex].resultingPose = .standing
                normalized[existingIndex].sourceText = normalized[existingIndex].sourceText ?? chunkSourceText
            } else if !normalized.contains(where: { $0.actorRef == actorRef && $0.type == .stop && $0.targetRef == targetRef }) {
                normalized.append(
                    ScenePlanIR.Action(
                        actorRef: actorRef,
                        type: .stop,
                        targetRef: targetRef,
                        resultingPose: .standing,
                        sourceText: chunkSourceText
                    )
                )
            }
        }

        if normalized != actions, !reasonCodes.contains("v1.collective_stop_near_object_expanded") {
            reasonCodes.append("v1.collective_stop_near_object_expanded")
        }
        if normalized != actions, !reasonCodes.contains("v9.collective_stop_near_object_expanded") {
            reasonCodes.append("v9.collective_stop_near_object_expanded")
        }
        return normalized
    }

    private func isExplicitObjectMovementAction(_ action: ScenePlanIR.Action) -> Bool {
        if let targetRef = action.targetRef, targetRef.hasPrefix("object_") || targetRef.hasPrefix("object_marked_") {
            return true
        }
        let text = (action.sourceText ?? action.fallbackText ?? "").lowercased()
        return inferObjectTarget(from: text, objectMap: [:], objectAliasMap: [:]) != nil
            || text.contains(" к ")
            || text.hasPrefix("к ")
    }

    private func textHasExplicitObjectTarget(_ text: String) -> Bool {
        let movementToCue = (text.contains(" к ") || text.hasPrefix("к "))
            && !text.contains("друг к другу")
            && !text.contains("друг ко другу")
        return movementToCue
            || text.contains(" у ")
            || text.contains("рядом")
            || text.contains("около")
            || text.contains("возле")
    }

    private func chunkTextIndicatesCollectiveApproach(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let hasPluralActorCue = lowercased.contains("2 акт")
            || lowercased.contains("два акт")
            || lowercased.contains("2 челов")
            || lowercased.contains("два челов")
            || lowercased.contains("оба")
            || lowercased.contains("обе")
        let hasCollectiveMovementCue = lowercased.contains("идут к")
            || lowercased.contains("подходят к")
            || lowercased.contains("направляются к")
            || lowercased.contains("потом идут к")
            || lowercased.contains("затем идут к")
        return hasPluralActorCue && hasCollectiveMovementCue
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

    private func makeStateDelta(beats: [ScenePlanIR.Beat], metadata: String?, sourceText: String) -> SceneChunkStateDelta {
        var poses: [String: ActorPose] = [:]
        var heldObjects: [String: String] = [:]
        var released: [String] = []
        var lastPositions: [String: String] = [:]

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
                if let target = action.targetRef {
                    lastPositions[action.actorRef] = "near:\(target)"
                } else if let pose = action.resultingPose {
                    lastPositions[action.actorRef] = "pose:\(pose.rawValue)"
                }
            }
        }

        return SceneChunkStateDelta(
            locationUpdate: metadata,
            actorPoseUpdates: poses,
            heldObjectUpdates: heldObjects,
            releasedObjects: released,
            previousChunkSummary: compactChunkSummary(sourceText),
            openBeatContext: beats.last.map { beat in
                let actionSummary = beat.actions.map { "\($0.actorRef):\($0.type.rawValue)" }.joined(separator: ",")
                return "\(beat.ref)|\(actionSummary)"
            },
            lastActorPositions: lastPositions
        )
    }

    private func compactChunkSummary(_ sourceText: String) -> String {
        let normalized = sourceText
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > 180 else { return normalized }
        return String(normalized.prefix(180))
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
        if let summary = delta.previousChunkSummary, !summary.isEmpty {
            state.registry.previousChunkSummary = summary
        }
        if let context = delta.openBeatContext, !context.isEmpty {
            state.registry.openBeatContext = context
        }
        state.registry.lastActorPositions.merge(delta.lastActorPositions) { _, new in new }
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
            visualOverlays: bundlePlan.visualOverlays,
            diagnostics: bundlePlan.diagnostics
        )
    }
}

final class SceneBundlePipeline {
    private enum V9RuntimeMode: String {
        case v8Hotfix = "v8_hotfix"
        case v9Bridge = "v9_bridge"
        case v9Full = "v9_full"
    }

    private let normalizer = ScriptNormalizer()
    private let boundaryDetector = SceneBoundaryDetector()
    private let segmenter = ChunkSegmenter()
    private let chunkAnchorExtractor: SceneChunkAnchorExtractor
    private let registryProjector = EntityRegistryProjector()
    private let canonicalizer = ChunkCanonicalizer()
    private let stitcher = SceneStitcher()
    private let v9EventService = SceneEventTableV9Service()
    private let metadataExtractor: SceneMetadataExtractor
    private let localProvider: LocalScenePlanProvider
    private let bundleCompiler: SceneBundleCompiler
    private let v9EnabledDefaultsKey = "scene_generator_v9_enabled"
    private let v9RuntimeModeDefaultsKey = "scene_generator_v9_runtime_mode"
    private let v9MaxRowsDefaultsKey = "scene_generator_v9_max_rows"
    private let v9MaxActorsDefaultsKey = "scene_generator_v9_max_actors"
    private let v9MaxObjectsDefaultsKey = "scene_generator_v9_max_objects"
    private let v9MaxBeatsDefaultsKey = "scene_generator_v9_max_beats"
    private let v9ChunkBudgetMsDefaultsKey = "scene_generator_v9_chunk_budget_ms"

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
            if scene.isMontage {
                continue
            }
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

        var renderableSceneEntries = sceneEntries.filter { !$0.plan.beats.isEmpty || !$0.plan.objects.isEmpty }
        if renderableSceneEntries.isEmpty,
           let fallbackScene = sceneEntries.first(where: { !$0.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            let actorRef = fallbackScene.plan.actors.first?.ref ?? "first"
            var fallbackPlan = fallbackScene.plan
            if fallbackPlan.actors.isEmpty {
                fallbackPlan.actors = [.init(ref: actorRef, type: .human)]
            }
            if fallbackPlan.beats.isEmpty {
                let fallbackText = fallbackScene.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
                let actionType: SceneAction.ActionType = fallbackText.contains("«")
                    || fallbackText.contains("\"")
                    || fallbackText.lowercased().contains("говор")
                    ? .talk
                    : .stand
                let dialogue = actionType == .talk ? fallbackText : nil
                fallbackPlan.beats = [
                    .init(
                        ref: "beat_fallback_1",
                        phase: "fallback",
                        actions: [
                            .init(
                                actorRef: actorRef,
                                type: actionType,
                                resultingPose: .standing,
                                dialogue: dialogue,
                                sourceText: fallbackText
                            ),
                        ],
                        minDuration: 0.5
                    ),
                ]
            }
            let fallbackEntry = SceneBundlePlan.SceneEntry(
                sceneID: fallbackScene.sceneID,
                sceneIndex: fallbackScene.sceneIndex,
                sourceText: fallbackScene.sourceText,
                metadata: fallbackScene.metadata,
                chunks: fallbackScene.chunks,
                diagnostics: fallbackScene.diagnostics + ["v9.fallback_scene_materialized"],
                plan: fallbackPlan
            )
            renderableSceneEntries = [fallbackEntry]
        } else if renderableSceneEntries.isEmpty {
            let fallbackText = workload.finalDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallbackText.isEmpty {
                let lowercased = fallbackText.lowercased()
                let actorCount = lowercased.contains("трет") ? 3 : ((lowercased.contains("перв") && lowercased.contains("втор")) || lowercased.contains("оба") ? 2 : 1)
                let actorRefs = Array(["first", "second", "third"].prefix(actorCount))
                let actors = actorRefs.map { ScenePlanIR.Actor(ref: $0, type: .human) }
                let objects = markedObjects
                    .filter { markerMentioned($0, in: lowercased) }
                    .map { marker in
                        ScenePlanIR.Object(
                            ref: marker.canonicalMarkedObjectID,
                            type: marker.type,
                            relativePosition: .center,
                            name: marker.name,
                            markedObjectID: marker.canonicalMarkedObjectID
                        )
                    }
                let fallbackPlan = ScenePlanIR(
                    actors: actors,
                    objects: objects,
                    beats: [
                        .init(
                            ref: "beat_fallback_1",
                            phase: "fallback",
                            actions: [
                                .init(
                                    actorRef: actorRefs.first ?? "first",
                                    type: .stand,
                                    resultingPose: .standing,
                                    sourceText: fallbackText
                                ),
                            ],
                            minDuration: 0.5
                        ),
                    ],
                    spatialRelations: [],
                    referenceBindings: .init(
                        actorBindings: Dictionary(uniqueKeysWithValues: actorRefs.enumerated().map { ($0.element, "actor_\($0.offset + 1)") }),
                        markedObjectIDs: objects.compactMap(\.markedObjectID),
                        aliasToObjectRef: Dictionary(uniqueKeysWithValues: objects.compactMap { object in
                            guard let name = object.name else { return nil }
                            return (name.lowercased(), object.ref)
                        })
                    )
                )
                renderableSceneEntries = [
                    SceneBundlePlan.SceneEntry(
                        sceneID: workload.finalSceneCandidates.first?.id ?? "scene_1",
                        sceneIndex: workload.finalSceneCandidates.first?.sceneIndex ?? 0,
                        sourceText: fallbackText,
                        metadata: workload.finalSceneCandidates.first?.metadata ?? .empty,
                        chunks: [],
                        diagnostics: ["v9.fallback_scene_materialized", "v9.bundle_empty_scene_recovered"],
                        plan: fallbackPlan
                    ),
                ]
            }
        }
        let activeRenderableIndex = 0
        let bundlePlan = SceneBundlePlan(
            bundleID: workload.bundleID,
            scenes: renderableSceneEntries,
            activeSceneIndex: activeRenderableIndex,
            visualOverlays: workload.visualOverlays,
            diagnostics: ["bundle_mode=\(workload.mode.rawValue)", "scene_count=\(sceneEntries.count)"]
        )
        let bundleScript = hydrateMarkedObjectPositions(
            in: bundleCompiler.compile(bundlePlan: bundlePlan),
            markedObjects: markedObjects
        )
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
            activeSceneIndex: bundlePlan.activeSceneIndex,
            visualOverlays: workload.visualOverlays
        )

        return SceneBundleParsingResult(
            bundleScript: bundleScript,
            activeSceneScript: activeSceneScript,
            activeSceneId: renderableSceneEntries.indices.contains(bundlePlan.activeSceneIndex) ? renderableSceneEntries[bundlePlan.activeSceneIndex].sceneID : nil,
            sceneChunks: allChunks.sorted { lhs, rhs in
                if lhs.sceneID == rhs.sceneID {
                    return lhs.chunkIndex < rhs.chunkIndex
                }
                return lhs.sceneID < rhs.sceneID
            },
            visualOverlays: workload.visualOverlays,
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
        fallbackPlanner: @escaping (_ text: String, _ markedObjects: [MarkedObject], _ state: SceneChunkState?) -> ParsingResult,
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
            var reasonCodes = providerResult.usedLegacySceneScriptBridge ? ["v1.legacy_scene_bridge_chunk"] : ["v1.local_chunk_plan"]
            appendReasons(providerResult.reasonCodes, provenance: "provider", into: &reasonCodes)

            let runtimeMode = selectedV9RuntimeMode()
            let limits = runtimeGuardrails(for: runtimeMode)
            let startTime = CFAbsoluteTimeGetCurrent()

            let v8BasePlan = providerResult.plan
            var sourcePlan = v8BasePlan

            if runtimeMode != .v8Hotfix {
                let guardrailPlan = v9EventService.applyGuardrails(to: sourcePlan, limits: limits)
                sourcePlan = guardrailPlan.plan
                appendReasons(guardrailPlan.reasonCodes, provenance: "runtime_guardrail", into: &reasonCodes)
                if didExceedChunkBudget(startTime: startTime, budgetMs: limits.wallClockBudgetMs) {
                    appendReasonWithProvenance(
                        "v9.runtime_budget_exceeded_fallback_v8",
                        provenance: "runtime_guardrail",
                        into: &reasonCodes
                    )
                    sourcePlan = v8BasePlan
                } else {
                    let v9Plan = applyV9RuntimeMode(
                        runtimeMode,
                        sourcePlan: sourcePlan,
                        v8FallbackPlan: v8BasePlan,
                        sourceText: rawSegment.sourceText,
                        anchors: anchors.sourceBundle,
                        chunkState: chunkState,
                        markedObjects: markedObjects,
                        limits: limits,
                        startTime: startTime,
                        reasonCodes: &reasonCodes
                    )
                    sourcePlan = v9Plan
                }
            } else {
                appendReasonWithProvenance(
                    "v9.runtime_mode_v8_hotfix",
                    provenance: "runtime_guardrail",
                    into: &reasonCodes
                )
            }

            let beforeEnrich = Set(reasonCodes)
            let enrichedPlan = enrichRuleFallbackPlan(
                sourcePlan,
                sourceText: rawSegment.sourceText,
                anchors: anchors.sourceBundle,
                markedObjects: markedObjects,
                reasonCodes: &reasonCodes
            )
            let afterEnrich = Set(reasonCodes)
            let newEnricherCodes = afterEnrich.subtracting(beforeEnrich).sorted()
            appendReasons(newEnricherCodes, provenance: "enricher", into: &reasonCodes)
            return SceneChunkDraft(
                sceneID: scene.id,
                chunkID: rawSegment.chunkID,
                chunkIndex: rawSegment.chunkIndex,
                sourceText: rawSegment.sourceText,
                sourceRange: rawSegment.sourceRange,
                anchors: anchors,
                registrySnapshot: registrySnapshot,
                plan: enrichedPlan,
                usedFallbackPlanner: false,
                usedLegacyPlanBridge: providerResult.usedLegacySceneScriptBridge,
                confidence: 0.9,
                unresolvedMentions: anchors.pronounMentions,
                reasonCodes: reasonCodes
            )
        }

        let fallback = fallbackPlanner(rawSegment.sourceText, markedObjects, chunkState)
        var reasonCodes = ["v1.rule_chunk_plan"]
        var bridgedPlan = bridgePlan(
            from: fallback.script,
            markedObjects: markedObjects,
            anchors: anchors.sourceBundle
        )
        bridgedPlan = enrichRuleFallbackPlan(
            bridgedPlan,
            sourceText: rawSegment.sourceText,
            anchors: anchors.sourceBundle,
            markedObjects: markedObjects,
            reasonCodes: &reasonCodes
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
            reasonCodes: reasonCodes
        )
    }

    private func selectedV9RuntimeMode() -> V9RuntimeMode {
        if let raw = UserDefaults.standard.string(forKey: v9RuntimeModeDefaultsKey),
           let parsed = V9RuntimeMode(rawValue: raw) {
            return parsed
        }
        // Backward compatibility for older boolean toggle.
        if UserDefaults.standard.object(forKey: v9EnabledDefaultsKey) != nil,
           UserDefaults.standard.bool(forKey: v9EnabledDefaultsKey) == false {
            return .v8Hotfix
        }
        return .v9Bridge
    }

    private func runtimeGuardrails(for mode: V9RuntimeMode) -> SceneEventTableV9Service.RuntimeGuardrails {
        let defaults: SceneEventTableV9Service.RuntimeGuardrails
        switch mode {
        case .v8Hotfix:
            defaults = .init(maxRows: 64, maxActors: 8, maxObjects: 12, maxBeats: 16, wallClockBudgetMs: 80)
        case .v9Bridge:
            defaults = .init(maxRows: 96, maxActors: 10, maxObjects: 16, maxBeats: 24, wallClockBudgetMs: 120)
        case .v9Full:
            defaults = .init(maxRows: 128, maxActors: 12, maxObjects: 20, maxBeats: 32, wallClockBudgetMs: 180)
        }
        return .init(
            maxRows: max(1, UserDefaults.standard.object(forKey: v9MaxRowsDefaultsKey) == nil ? defaults.maxRows : UserDefaults.standard.integer(forKey: v9MaxRowsDefaultsKey)),
            maxActors: max(1, UserDefaults.standard.object(forKey: v9MaxActorsDefaultsKey) == nil ? defaults.maxActors : UserDefaults.standard.integer(forKey: v9MaxActorsDefaultsKey)),
            maxObjects: max(1, UserDefaults.standard.object(forKey: v9MaxObjectsDefaultsKey) == nil ? defaults.maxObjects : UserDefaults.standard.integer(forKey: v9MaxObjectsDefaultsKey)),
            maxBeats: max(1, UserDefaults.standard.object(forKey: v9MaxBeatsDefaultsKey) == nil ? defaults.maxBeats : UserDefaults.standard.integer(forKey: v9MaxBeatsDefaultsKey)),
            wallClockBudgetMs: UserDefaults.standard.object(forKey: v9ChunkBudgetMsDefaultsKey) == nil
                ? defaults.wallClockBudgetMs
                : max(10, UserDefaults.standard.double(forKey: v9ChunkBudgetMsDefaultsKey))
        )
    }

    private func didExceedChunkBudget(startTime: CFAbsoluteTime, budgetMs: Double) -> Bool {
        (CFAbsoluteTimeGetCurrent() - startTime) * 1_000.0 > budgetMs
    }

    private func applyV9RuntimeMode(
        _ mode: V9RuntimeMode,
        sourcePlan: ScenePlanIR,
        v8FallbackPlan: ScenePlanIR,
        sourceText: String,
        anchors: SourceAnchorBundle,
        chunkState: SceneChunkState,
        markedObjects: [MarkedObject],
        limits: SceneEventTableV9Service.RuntimeGuardrails,
        startTime: CFAbsoluteTime,
        reasonCodes: inout [String]
    ) -> ScenePlanIR {
        switch mode {
        case .v8Hotfix:
            return v8FallbackPlan
        case .v9Bridge:
            return applyV9Bridge(
                sourcePlan: sourcePlan,
                v8FallbackPlan: v8FallbackPlan,
                limits: limits,
                startTime: startTime,
                reasonCodes: &reasonCodes
            )
        case .v9Full:
            return applyV9Full(
                sourcePlan: sourcePlan,
                v8FallbackPlan: v8FallbackPlan,
                sourceText: sourceText,
                anchors: anchors,
                chunkState: chunkState,
                markedObjects: markedObjects,
                limits: limits,
                startTime: startTime,
                reasonCodes: &reasonCodes
            )
        }
    }

    private func applyV9Bridge(
        sourcePlan: ScenePlanIR,
        v8FallbackPlan: ScenePlanIR,
        limits: SceneEventTableV9Service.RuntimeGuardrails,
        startTime: CFAbsoluteTime,
        reasonCodes: inout [String]
    ) -> ScenePlanIR {
        let slotCatalog = v9EventService.buildSlotCatalog(from: sourcePlan)
        var eventTable = v9EventService.buildEventTable(from: sourcePlan, slotCatalog: slotCatalog)
        let rowClamp = v9EventService.clampRows(in: eventTable, maxRows: limits.maxRows)
        eventTable = rowClamp.eventTable
        appendReasons(rowClamp.reasonCodes, provenance: "runtime_guardrail", into: &reasonCodes)

        if didExceedChunkBudget(startTime: startTime, budgetMs: limits.wallClockBudgetMs) {
            appendReasonWithProvenance("v9.runtime_budget_exceeded_fallback_v8", provenance: "runtime_guardrail", into: &reasonCodes)
            return v8FallbackPlan
        }

        let verification = v9EventService.verifyAndRepair(eventTable: eventTable, slotCatalog: slotCatalog)
        appendReasons(verification.reasonCodes, provenance: "v9_verifier", into: &reasonCodes)
        if !verification.reasonCodes.isEmpty {
            appendReasonWithProvenance("v9.local_event_table_pipeline", provenance: "v9_verifier", into: &reasonCodes)
        }
        return v9EventService.compileToPlan(
            eventTable: verification.repairedEventTable,
            slotCatalog: slotCatalog,
            originalPlan: sourcePlan
        )
    }

    private func applyV9Full(
        sourcePlan: ScenePlanIR,
        v8FallbackPlan: ScenePlanIR,
        sourceText: String,
        anchors: SourceAnchorBundle,
        chunkState: SceneChunkState,
        markedObjects: [MarkedObject],
        limits: SceneEventTableV9Service.RuntimeGuardrails,
        startTime: CFAbsoluteTime,
        reasonCodes: inout [String]
    ) -> ScenePlanIR {
        var slotCatalog = v9EventService.buildSlotCatalog(from: sourcePlan)
        var eventTable = v9EventService.buildEventTable(from: sourcePlan, slotCatalog: slotCatalog)
        var usedProvider = false

        if let providerResult = localProvider.generateEventTable(
            description: sourceText,
            markedObjects: markedObjects,
            anchors: anchors,
            state: chunkState,
            slotCatalog: slotCatalog
        ) {
            usedProvider = true
            slotCatalog = providerResult.slotCatalog
            eventTable = providerResult.eventTable
            appendReasons(providerResult.reasonCodes, provenance: "provider", into: &reasonCodes)
            if let patchOps = providerResult.patchOps {
                // Provider may return already-applied patch ops for diagnostics; runtime must not apply them twice.
                if !patchOps.ops.isEmpty {
                    appendReasonWithProvenance("v9.patch_ops_embedded_in_provider_payload", provenance: "provider", into: &reasonCodes)
                }
            }
            appendReasonWithProvenance("v9.event_provider_path_used", provenance: "provider", into: &reasonCodes)
        } else {
            appendReasonWithProvenance("v9.event_provider_unavailable_fallback_bridge", provenance: "provider", into: &reasonCodes)
        }

        let rowClamp = v9EventService.clampRows(in: eventTable, maxRows: limits.maxRows)
        eventTable = rowClamp.eventTable
        appendReasons(rowClamp.reasonCodes, provenance: "runtime_guardrail", into: &reasonCodes)

        if didExceedChunkBudget(startTime: startTime, budgetMs: limits.wallClockBudgetMs) {
            appendReasonWithProvenance("v9.runtime_budget_exceeded_fallback_v8", provenance: "runtime_guardrail", into: &reasonCodes)
            return v8FallbackPlan
        }

        var verification = v9EventService.verifyAndRepair(eventTable: eventTable, slotCatalog: slotCatalog)
        appendReasons(verification.reasonCodes, provenance: "v9_verifier", into: &reasonCodes)
        let coverageIssues = v9EventService.coverageIssueCodes(
            eventTable: verification.repairedEventTable,
            slotCatalog: slotCatalog,
            sourceText: sourceText,
            anchors: anchors
        )
        appendReasons(coverageIssues, provenance: "v9_verifier", into: &reasonCodes)
        var verifierIssuesForRetry = verification.reasonCodes + coverageIssues

        let canRetry = usedProvider
            && v9EventService.containsFixableVerifierIssues(verifierIssuesForRetry)
            && !didExceedChunkBudget(startTime: startTime, budgetMs: limits.wallClockBudgetMs * 0.75)
        if canRetry {
            appendReasonWithProvenance("v9.patch_retry_attempted", provenance: "v9_verifier", into: &reasonCodes)
            if let retryPatchOps = localProvider.generateEventPatchOps(
                description: sourceText,
                markedObjects: markedObjects,
                anchors: anchors,
                state: chunkState,
                slotCatalog: slotCatalog,
                eventTable: verification.repairedEventTable,
                verifierIssues: verifierIssuesForRetry
            ) {
                let patched = v9EventService.applyPatchOps(
                    retryPatchOps,
                    to: verification.repairedEventTable,
                    slotCatalog: slotCatalog
                )
                appendReasons(patched.reasonCodes, provenance: "v9_verifier", into: &reasonCodes)
                let retryClamp = v9EventService.clampRows(in: patched.eventTable, maxRows: limits.maxRows)
                let retryVerification = v9EventService.verifyAndRepair(eventTable: retryClamp.eventTable, slotCatalog: slotCatalog)
                let retryCoverageIssues = v9EventService.coverageIssueCodes(
                    eventTable: retryVerification.repairedEventTable,
                    slotCatalog: slotCatalog,
                    sourceText: sourceText,
                    anchors: anchors
                )
                let retryIssues = retryVerification.reasonCodes + retryCoverageIssues
                if retryIssues.count <= verifierIssuesForRetry.count {
                    verification = retryVerification
                    verifierIssuesForRetry = retryIssues
                    appendReasonWithProvenance("v9.patch_retry_applied", provenance: "v9_verifier", into: &reasonCodes)
                    appendReasons(retryVerification.reasonCodes, provenance: "v9_verifier", into: &reasonCodes)
                    appendReasons(retryCoverageIssues, provenance: "v9_verifier", into: &reasonCodes)
                } else {
                    appendReasonWithProvenance("v9.patch_retry_no_gain", provenance: "v9_verifier", into: &reasonCodes)
                }
            } else {
                appendReasonWithProvenance("v9.patch_retry_unavailable", provenance: "v9_verifier", into: &reasonCodes)
            }
        }

        if didExceedChunkBudget(startTime: startTime, budgetMs: limits.wallClockBudgetMs) {
            appendReasonWithProvenance("v9.runtime_budget_exceeded_fallback_v8", provenance: "runtime_guardrail", into: &reasonCodes)
            return v8FallbackPlan
        }

        appendReasonWithProvenance("v9.local_event_table_pipeline", provenance: "v9_verifier", into: &reasonCodes)
        return v9EventService.compileToPlan(
            eventTable: verification.repairedEventTable,
            slotCatalog: slotCatalog,
            originalPlan: sourcePlan
        )
    }

    private func appendReasonWithProvenance(
        _ reason: String,
        provenance: String,
        into reasons: inout [String]
    ) {
        if !reasons.contains(reason) {
            reasons.append(reason)
        }
        let tagged = "\(provenance):\(reason)"
        if !reasons.contains(tagged) {
            reasons.append(tagged)
        }
    }

    private func appendReasons(
        _ additional: [String],
        provenance: String,
        into reasons: inout [String]
    ) {
        for reason in additional {
            appendReasonWithProvenance(reason, provenance: provenance, into: &reasons)
        }
    }

    private func enrichRuleFallbackPlan(
        _ plan: ScenePlanIR,
        sourceText: String,
        anchors: SourceAnchorBundle,
        markedObjects: [MarkedObject],
        reasonCodes: inout [String]
    ) -> ScenePlanIR {
        var enriched = ensureOrdinalActors(in: plan, sourceText: sourceText, anchors: anchors)
        enriched = ensureMentionedMarkedObjects(
            in: enriched,
            sourceText: sourceText,
            markedObjects: markedObjects,
            reasonCodes: &reasonCodes
        )
        enriched = ensureDialogueEvents(
            in: enriched,
            sourceText: sourceText,
            reasonCodes: &reasonCodes
        )
        enriched = ensureTransferEvents(
            in: enriched,
            sourceText: sourceText,
            reasonCodes: &reasonCodes
        )

        guard !anchors.unsupportedActionFlags.isEmpty,
              !enriched.beats.flatMap(\.actions).contains(where: { $0.type == .describedAction })
        else { return enriched }

        let describedText = extractUnsupportedActionSentence(
            from: sourceText,
            unsupportedFlags: anchors.unsupportedActionFlags
        )
        guard !describedText.isEmpty else { return enriched }

        let actorRef = inferUnsupportedActionActorRef(from: describedText, sourceText: sourceText, anchors: anchors)
        if !enriched.actors.contains(where: { $0.ref == actorRef }) {
            enriched.actors.append(.init(ref: actorRef, type: .human))
        }
        enriched.beats.append(
            ScenePlanIR.Beat(
                ref: "beat_described_\(enriched.beats.count + 1)",
                phase: "described_action",
                actions: [
                    ScenePlanIR.Action(
                        actorRef: actorRef,
                        type: .describedAction,
                        resultingPose: .standing,
                        fallbackText: describedText,
                        sourceText: describedText
                    ),
                ],
                minDuration: 0.5
            )
        )
        if !reasonCodes.contains("v1.unsupported_action_described") {
            reasonCodes.append("v1.unsupported_action_described")
        }
        return enriched
    }

    private func ensureOrdinalActors(in plan: ScenePlanIR, sourceText: String, anchors: SourceAnchorBundle) -> ScenePlanIR {
        var enriched = plan
        let lowercased = sourceText.lowercased()
        let speakerCount = Set(inlineSpeakerPairs(in: sourceText).map(\.speaker)).count
        let requiredCount: Int
        if anchors.actorCountHint >= 3 || lowercased.contains("трет") {
            requiredCount = 3
        } else if anchors.actorCountHint >= 2
            || lowercased.contains("оба")
            || lowercased.contains("обе")
            || lowercased.contains("перв") && lowercased.contains("втор")
            || speakerCount >= 2 {
            requiredCount = 2
        } else {
            requiredCount = max(enriched.actors.count, speakerCount)
        }

        let ordinalRefs = ["first", "second", "third"]
        for ref in ordinalRefs.prefix(requiredCount) where !enriched.actors.contains(where: { $0.ref == ref }) {
            enriched.actors.append(.init(ref: ref, type: .human))
        }
        return enriched
    }

    private func ensureMentionedMarkedObjects(
        in plan: ScenePlanIR,
        sourceText: String,
        markedObjects: [MarkedObject],
        reasonCodes: inout [String]
    ) -> ScenePlanIR {
        guard !markedObjects.isEmpty else { return plan }
        var enriched = plan
        let lowercased = sourceText.lowercased()
        var added = false

        for marker in markedObjects where markerMentioned(marker, in: lowercased) {
            let objectID = marker.canonicalMarkedObjectID
            guard !enriched.objects.contains(where: { $0.ref == objectID || $0.markedObjectID == objectID }) else {
                continue
            }
            enriched.objects.append(
                ScenePlanIR.Object(
                    ref: objectID,
                    type: marker.type,
                    relativePosition: .center,
                    name: marker.name,
                    markedObjectID: objectID
                )
            )
            added = true
        }

        if added {
            appendUniqueReason("v9.mentioned_marked_object_materialized", to: &reasonCodes)
        }
        return enriched
    }

    private func markerMentioned(_ marker: MarkedObject, in lowercasedText: String) -> Bool {
        let markerName = marker.name.lowercased().replacingOccurrences(of: "_", with: " ")
        if markerName.count >= 3, lowercasedText.contains(markerName) {
            return true
        }

        let tokens = markerName
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        let hasTypeCue = tokens.contains { token in
            token.count >= 4 && lowercasedText.contains(String(token.prefix(min(5, token.count))))
        } || lowercasedText.contains(marker.type.rawValue.lowercased())

        let hasDirectionalCue = [
            ("лев", "лев"),
            ("прав", "прав"),
            ("ближ", "ближ"),
            ("даль", "даль"),
        ].contains { markerCue, textCue in
            markerName.contains(markerCue) && lowercasedText.contains(textCue)
        }

        return hasTypeCue && hasDirectionalCue
    }

    private func ensureDialogueEvents(
        in plan: ScenePlanIR,
        sourceText: String,
        reasonCodes: inout [String]
    ) -> ScenePlanIR {
        let speakerPairs = inlineSpeakerPairs(in: sourceText)
        let quotedText = quotedDialogue(in: sourceText)
        guard !speakerPairs.isEmpty || !quotedText.isEmpty else { return plan }

        let hasDialogue = plan.beats.flatMap(\.actions).contains { action in
            action.type == .talk && !(action.dialogue ?? action.sourceText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !hasDialogue else { return plan }

        var enriched = plan
        if enriched.actors.isEmpty {
            enriched.actors.append(.init(ref: "first", type: .human))
        }
        let actorRefs = enriched.actors.map(\.ref)
        let dialogueActions: [ScenePlanIR.Action]
        if !speakerPairs.isEmpty {
            dialogueActions = speakerPairs.enumerated().map { index, pair in
                let actorRef = actorRefs.indices.contains(index) ? actorRefs[index] : actorRefs.first ?? "first"
                return ScenePlanIR.Action(
                    actorRef: actorRef,
                    type: .talk,
                    resultingPose: .standing,
                    dialogue: pair.dialogue,
                    sourceText: "\(pair.speaker): \(pair.dialogue)"
                )
            }
        } else {
            dialogueActions = [
                ScenePlanIR.Action(
                    actorRef: actorRefs.first ?? "first",
                    type: .talk,
                    resultingPose: .standing,
                    dialogue: quotedText,
                    sourceText: quotedText
                ),
            ]
        }

        let beat = ScenePlanIR.Beat(
            ref: "beat_dialogue_runtime_\(enriched.beats.count + 1)",
            phase: "talk",
            actions: dialogueActions,
            minDuration: 0.5
        )
        enriched.beats.insert(beat, at: 0)
        appendUniqueReason("v9.dialogue_event_materialized", to: &reasonCodes)
        return enriched
    }

    private func ensureTransferEvents(
        in plan: ScenePlanIR,
        sourceText: String,
        reasonCodes: inout [String]
    ) -> ScenePlanIR {
        let lowercased = sourceText.lowercased()
        let needsPickUp = containsAny(lowercased, ["берёт", "берет", "поднимает", "поднял", "взял", "берут"])
        let needsPutDown = containsAny(lowercased, ["кладёт", "кладет", "положи", "положил", "оставь", "ставит"])
        let needsGive = containsAny(lowercased, ["передаёт", "передает", "передам", "даёт", "дает", "получает"])

        guard needsPickUp || needsPutDown || needsGive else { return plan }
        var enriched = plan
        if enriched.actors.isEmpty {
            enriched.actors.append(.init(ref: "first", type: .human))
        }
        let objectRef = ensureTransferObject(in: &enriched, sourceText: lowercased)
        let actorRef = transferActorRef(in: enriched, sourceText: lowercased)
        let recipientRef = transferRecipientRef(in: enriched, sourceText: lowercased)
        var actionsToAdd: [ScenePlanIR.Action] = []
        let existingTypes = Set(enriched.beats.flatMap(\.actions).map(\.type))

        if needsPickUp, !existingTypes.contains(.pickUp) {
            actionsToAdd.append(
                ScenePlanIR.Action(
                    actorRef: actorRef,
                    type: .pickUp,
                    targetRef: objectRef,
                    resultingPose: .standing,
                    holdingObjectRef: objectRef,
                    sourceText: sourceText
                )
            )
        }

        if needsPutDown, !existingTypes.contains(.putDown) {
            actionsToAdd.append(
                ScenePlanIR.Action(
                    actorRef: actorRef,
                    type: .putDown,
                    targetRef: objectRef,
                    resultingPose: .standing,
                    sourceText: sourceText
                )
            )
        }

        if needsGive, !existingTypes.contains(.give) {
            actionsToAdd.append(
                ScenePlanIR.Action(
                    actorRef: actorRef,
                    type: .give,
                    targetRef: recipientRef,
                    resultingPose: .standing,
                    holdingObjectRef: objectRef,
                    sourceText: sourceText
                )
            )
        }

        guard !actionsToAdd.isEmpty else { return enriched }
        enriched.beats.append(
            ScenePlanIR.Beat(
                ref: "beat_transfer_runtime_\(enriched.beats.count + 1)",
                phase: "object_transfer",
                actions: actionsToAdd,
                minDuration: 0.5
            )
        )
        appendUniqueReason("v9.transfer_action_materialized", to: &reasonCodes)
        return enriched
    }

    private func inlineSpeakerPairs(in sourceText: String) -> [(speaker: String, dialogue: String)] {
        let pattern = #"(?m)(?:^|[.!?]\s+)([A-ZА-ЯЁ][A-Za-zА-Яа-яЁё0-9 \-_.]{1,40}):\s*([^.\n]+(?:[.!?]|$))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = sourceText as NSString
        return regex.matches(in: sourceText, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard match.numberOfRanges > 2 else { return nil }
            let speaker = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let dialogue = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !speaker.isEmpty, !dialogue.isEmpty else { return nil }
            return (speaker, dialogue)
        }
    }

    private func quotedDialogue(in sourceText: String) -> String {
        let patterns = [
            #"«([^»]+)»"#,
            #""([^"]+)""#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsText = sourceText as NSString
            let matches = regex.matches(in: sourceText, range: NSRange(location: 0, length: nsText.length))
            let snippets = matches.compactMap { match -> String? in
                guard match.numberOfRanges > 1 else { return nil }
                let value = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            if !snippets.isEmpty {
                return snippets.joined(separator: " ")
            }
        }
        return ""
    }

    private func ensureTransferObject(in plan: inout ScenePlanIR, sourceText: String) -> String {
        let existingObject = plan.objects.first { object in
            let name = object.name?.lowercased() ?? object.ref.lowercased()
            return sourceText.contains(name) || object.ref.hasPrefix("object_marked_")
        }
        if let existingObject {
            return existingObject.ref
        }

        let objectName = transferObjectName(in: sourceText)
        let objectRef = "object_runtime_transfer"
        if !plan.objects.contains(where: { $0.ref == objectRef }) {
            plan.objects.append(
                ScenePlanIR.Object(
                    ref: objectRef,
                    type: .generic,
                    relativePosition: .center,
                    name: objectName,
                    markedObjectID: nil
                )
            )
        }
        return objectRef
    }

    private func transferObjectName(in sourceText: String) -> String {
        let candidates = ["письмо", "планшет", "сумка", "сумку", "коробка", "коробку", "пакет", "конверт", "отчёт", "отчет", "скриншот"]
        let candidate = candidates.first { sourceText.contains($0) } ?? "предмет"
        switch candidate {
        case "сумку": return "сумка"
        case "коробку": return "коробка"
        case "отчет": return "отчёт"
        default: return candidate
        }
    }

    private func transferActorRef(in plan: ScenePlanIR, sourceText: String) -> String {
        let actorRefs = plan.actors.map(\.ref)
        if actorRefs.contains("second"),
           containsAny(sourceText, ["второй бер", "вторая бер", "второй клад", "вторая клад", "второй перед", "вторая перед"]) {
            return "second"
        }
        if actorRefs.contains("first"),
           containsAny(sourceText, ["первый бер", "первая бер", "первый клад", "первая клад", "первый перед", "первая перед"]) {
            return "first"
        }
        if sourceText.contains("перв"), actorRefs.contains("first") { return "first" }
        if sourceText.contains("втор"), actorRefs.contains("second") { return "second" }
        if sourceText.contains("трет"), actorRefs.contains("third") { return "third" }
        return actorRefs.first ?? "first"
    }

    private func transferRecipientRef(in plan: ScenePlanIR, sourceText: String) -> String {
        let actorRefs = plan.actors.map(\.ref)
        if (sourceText.contains("трет") || sourceText.contains("лиз") || sourceText.contains("егор")),
           actorRefs.contains("third") {
            return "third"
        }
        if sourceText.contains("втор"), actorRefs.contains("second") { return "second" }
        return actorRefs.dropFirst().first ?? actorRefs.first ?? "first"
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private func appendUniqueReason(_ reason: String, to reasons: inout [String]) {
        if !reasons.contains(reason) {
            reasons.append(reason)
        }
    }

    private func extractUnsupportedActionSentence(from sourceText: String, unsupportedFlags: [String]) -> String {
        let candidates = sourceText
            .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let lowercasedFlags = unsupportedFlags.map { $0.lowercased() }
        return candidates.first { sentence in
            let lowercased = sentence.lowercased()
            return lowercasedFlags.contains(where: { lowercased.contains($0) })
        } ?? ""
    }

    private func inferUnsupportedActionActorRef(
        from describedText: String,
        sourceText: String,
        anchors: SourceAnchorBundle
    ) -> String {
        let lowercased = describedText.lowercased()
        if lowercased.contains("трет") { return "third" }
        if lowercased.contains("втор") { return "second" }
        if lowercased.contains("перв") { return "first" }

        let fullText = sourceText.lowercased()
        if fullText.contains("трет") { return "third" }
        if fullText.contains("втор") { return "second" }
        if fullText.contains("перв") { return "first" }
        if anchors.ordinalMentions.contains("second") { return "second" }
        return "first"
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

    private func hydrateMarkedObjectPositions(
        in bundleScript: SceneBundleScript,
        markedObjects: [MarkedObject]
    ) -> SceneBundleScript {
        guard !markedObjects.isEmpty else { return bundleScript }
        let markerMap = Dictionary(uniqueKeysWithValues: markedObjects.map { ($0.canonicalMarkedObjectID, $0) })
        let hydratedScenes = bundleScript.scenes.map { scene in
            let hydratedObjects = scene.objects.map { object in
                guard let marker = markerMap[object.id] else { return object }
                var objectCopy = object
                objectCopy.detectedPosition = marker.worldPosition
                if objectCopy.name == nil {
                    objectCopy.name = marker.name
                }
                return objectCopy
            }
            return SceneScript(
                sceneHeading: scene.sceneHeading,
                locationName: scene.locationName,
                interiorExterior: scene.interiorExterior,
                timeOfDay: scene.timeOfDay,
                actors: scene.actors,
                objects: hydratedObjects,
                beats: scene.beats,
                spatialRelations: scene.spatialRelations,
                originalDescription: scene.originalDescription
            )
        }
        return SceneBundleScript(
            bundleID: bundleScript.bundleID,
            scenes: hydratedScenes,
            activeSceneIndex: bundleScript.activeSceneIndex,
            visualOverlays: bundleScript.visualOverlays,
            diagnostics: bundleScript.diagnostics
        )
    }

    private func unitsIntersecting(_ range: ScriptOffsetRange, units: [NormalizedScriptUnit]) -> [NormalizedScriptUnit] {
        units.filter { unit in
            unit.charRange.end >= range.start && unit.charRange.start <= range.end
        }
    }

    private func emptyResult(description: String) -> SceneBundleParsingResult {
        let bundlePlan = SceneBundlePlan(bundleID: UUID().uuidString.lowercased(), scenes: [], activeSceneIndex: 0, visualOverlays: [], diagnostics: ["bundle_empty"])
        let bundleScript = SceneBundleScript(bundleID: bundlePlan.bundleID, scenes: [], activeSceneIndex: 0, visualOverlays: [], diagnostics: bundlePlan.diagnostics)
        let documentState = ScriptDocumentState(
            documentID: UUID().uuidString.lowercased(),
            mode: .full,
            sourceText: description,
            normalizedUnits: [],
            sceneCandidates: [],
            stitchStates: [],
            bundlePlan: bundlePlan,
            bundleScript: bundleScript,
            activeSceneIndex: 0,
            visualOverlays: []
        )
        return SceneBundleParsingResult(
            bundleScript: bundleScript,
            activeSceneScript: nil,
            activeSceneId: nil,
            sceneChunks: [],
            visualOverlays: [],
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
        let visualOverlays = makeVisualOverlays(units: units, scenes: scenes)
        return SceneBundleWorkload(
            documentID: previousState?.documentID ?? UUID().uuidString.lowercased(),
            bundleID: previousState?.bundlePlan.bundleID ?? UUID().uuidString.lowercased(),
            mode: mode,
            units: units,
            finalDescription: description,
            finalSceneCandidates: scenes,
            visualOverlays: visualOverlays,
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
        let visualOverlays = makeVisualOverlays(units: units, scenes: scenes)

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
            visualOverlays: visualOverlays,
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
                visualOverlays: previousState.visualOverlays,
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

        let visualOverlays = makeVisualOverlays(units: units, scenes: finalCandidates)
        return SceneBundleWorkload(
            documentID: previousState.documentID,
            bundleID: previousState.bundlePlan.bundleID,
            mode: .append,
            units: units,
            finalDescription: description,
            finalSceneCandidates: finalCandidates,
            visualOverlays: visualOverlays,
            pendingScenes: pendingScenes,
            reusedStates: reusedStates,
            reusedSceneEntries: reusedSceneEntries,
            reusedChunks: reusedChunks,
            reusedChunkDiagnostics: reusedChunkDiagnostics,
            coldStartSceneIDs: startsWithImplicitContinuation ? [previousState.sceneCandidates.last?.id ?? ""] : []
        )
    }

    private func makeVisualOverlays(units: [NormalizedScriptUnit], scenes: [ScriptSceneCandidate]) -> [SceneVisualOverlay] {
        var overlays: [SceneVisualOverlay] = []
        var displayOrder = 0

        func sceneID(forUnitIndex unitIndex: Int) -> String {
            scenes.first { scene in
                scene.unitRange.contains(unitIndex)
            }?.id ?? scenes.first?.id ?? "scene_1"
        }

        func appendOverlay(kind: SceneVisualOverlay.Kind, text: String, unit: NormalizedScriptUnit, unitIndex: Int, range: ScriptOffsetRange? = nil) {
            let cleaned = text
                .replacingOccurrences(of: "*", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return }
            displayOrder += 1
            overlays.append(
                SceneVisualOverlay(
                    id: "overlay_\(displayOrder)",
                    kind: kind,
                    text: cleaned,
                    sceneID: sceneID(forUnitIndex: unitIndex),
                    sourceRange: range ?? unit.charRange,
                    displayOrder: displayOrder,
                    beatID: nil
                )
            )
        }

        for (unitIndex, unit) in units.enumerated() {
            switch unit.kind {
            case .screenText:
                appendOverlay(kind: .screenText, text: unit.text, unit: unit, unitIndex: unitIndex)
            case .stageNote, .parenthetical:
                appendOverlay(kind: .stageNote, text: unit.text, unit: unit, unitIndex: unitIndex)
            case .dialogue, .actionLine, .proseLine:
                let pattern = #"\*([^*]+)\*"#
                let nsText = unit.text as NSString
                let matches = (try? NSRegularExpression(pattern: pattern))?.matches(
                    in: unit.text,
                    range: NSRange(location: 0, length: nsText.length)
                ) ?? []
                for match in matches where match.numberOfRanges > 1 {
                    let text = nsText.substring(with: match.range(at: 1))
                    appendOverlay(
                        kind: .stageNote,
                        text: text,
                        unit: unit,
                        unitIndex: unitIndex
                    )
                }
            default:
                continue
            }
        }
        return overlays
    }
}

private struct SceneBundleWorkload {
    var documentID: String
    var bundleID: String
    var mode: SceneBundleParseMode
    var units: [NormalizedScriptUnit]
    var finalDescription: String
    var finalSceneCandidates: [ScriptSceneCandidate]
    var visualOverlays: [SceneVisualOverlay]
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
        if let existing = previousState?.stitchStates.first(where: { $0.sceneID == scene.id }) {
            return existing
        }
        return SceneStitchState(
            sceneID: scene.id,
            sceneIndex: scene.sceneIndex,
            sourceText: "",
            metadata: scene.metadata,
            registry: SceneEntityRegistrySnapshot(
                actors: [],
                objects: [],
                actorAliasMap: [:],
                objectAliasMap: [:],
                speakerAliasMap: [:],
                unresolvedMentions: [],
                lastResolvedSpeaker: nil,
                locationName: scene.metadata.locationName,
                actorPoses: [:],
                heldObjects: [:]
            )
        )
    }
}
