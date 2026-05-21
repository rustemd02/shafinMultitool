//
//  SceneParserService.swift
//  shafinMultitool
//
//  Created on 30.11.2025.
//

import Foundation
import NaturalLanguage

/// Сервис для парсинга текстового описания сцены в структурированный SceneScript
final class SceneParserService {
    enum V9RuntimeMode: String, CaseIterable, Equatable {
        case v8Hotfix = "v8_hotfix"
        case v9Bridge = "v9_bridge"
        case v9Full = "v9_full"
    }

    private enum LLMSelectionDecision {
        case accept
        case merge
        case reject(String)
    }

    static let shared = SceneParserService()

    private let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma, .nameType])
    private let lemmatizer = Lemmatizer()
    private lazy var markedObjectMatcher = MarkedObjectMatcher(lemmatizer: lemmatizer)
    private let diagnosticsCalculator = DiagnosticsCalculator()
    private let llmParser = LLMParserService.shared
    private let anchorExtractor = SceneAnchorExtractor()
    private let metadataExtractor = SceneMetadataExtractor()
    private let planCompiler = ScenePlanCompiler()
    private let qualityGate = SceneQualityGate()
    private let v9RuntimeModeDefaultsKey = "scene_generator_v9_runtime_mode"
    private let v9EnabledDefaultsKey = "scene_generator_v9_enabled"
    private lazy var bundlePipeline = SceneBundlePipeline(
        anchorExtractor: anchorExtractor,
        metadataExtractor: metadataExtractor,
        localProvider: llmParser,
        planCompiler: planCompiler
    )
    private var remotePlanProvider: RemoteScenePlanProvider?
    private var remoteOffloadEnabled = false

    private(set) var lastRuntimeTrace: SceneRuntimeTrace?
    private(set) var lastChunkState: SceneChunkState?
    private(set) var lastDocumentState: ScriptDocumentState?
    private(set) var lastBundleResult: SceneBundleParsingResult?

    private init() {}

    // MARK: - Public API

    /// Парсит текстовое описание и возвращает структурированный результат с диагностикой
    /// - Parameters:
    ///   - description: Текстовое описание сцены
    ///   - markedObjects: Размеченные пользователем объекты в реальном пространстве
    /// - Returns: Результат парсинга с диагностикой
    func parse(_ description: String, markedObjects: [MarkedObject] = []) async -> ParsingResult {
        await parse(description, markedObjects: markedObjects, state: nil)
    }

    func parse(_ description: String, markedObjects: [MarkedObject] = [], state: SceneChunkState?) async -> ParsingResult {
        if state == nil {
            let bundleResult = await parseBundle(description, markedObjects: markedObjects)
            return ParsingResult(script: bundleResult.activeSceneScript ?? SceneScript(actors: [], objects: [], beats: [], spatialRelations: [], originalDescription: description), diagnostics: bundleResult.diagnostics)
        }
        let output = makeParseCoordinator().parse(description: description, markedObjects: markedObjects, state: state) { [weak self] in
            self?.ruleBasedParse(description, markedObjects: markedObjects)
                ?? ParsingResult(script: SceneScript(actors: [], objects: [], beats: [], spatialRelations: [], originalDescription: description), diagnostics: .empty)
        }
        lastRuntimeTrace = output.trace
        lastChunkState = makeChunkState(from: output.result.script, fallbackLocationName: state?.locationName)
        print("🤖 [PARSER_V8] route=\(output.trace.route.rawValue) reasons=\(output.trace.reasons.joined(separator: ","))")
        return output.result
    }

    private func matchedMarkedObjectIDs(from objects: [SceneObject], markedObjects: [MarkedObject]) -> [UUID] {
        objects.compactMap { object in
            matchedMarkedObjectUUID(for: object.id, markedObjects: markedObjects)
        }
    }

    private func matchedMarkedObjectUUID(for objectID: String, markedObjects: [MarkedObject]) -> UUID? {
        guard let shortID = normalizedMarkedShortID(from: objectID) else { return nil }
        return markedObjects.first(where: { $0.markedShortID == shortID })?.id
    }

    private func normalizedMarkedShortID(from objectID: String) -> String? {
        let lowercasedID = objectID.lowercased()
        guard lowercasedID.hasPrefix("object_marked_") else { return nil }
        let suffix = String(lowercasedID.dropFirst("object_marked_".count))
        guard !suffix.isEmpty else { return nil }
        return String(suffix.prefix(8))
    }

    private func ruleBasedParse(_ description: String, markedObjects: [MarkedObject]) -> ParsingResult {
        let lowercased = description.lowercased()
        let metadata = metadataExtractor.extract(description: description)

        // 1. Извлекаем актёров
        let actors = extractActors(from: lowercased, originalText: description)

        // 2. Извлекаем объекты (с учётом markedObjects)
        let objects = extractObjects(from: lowercased, markedObjects: markedObjects)

        // 3. Определяем какие markedObjects были распознаны
        let matchedMarkedObjectIds = matchedMarkedObjectIDs(from: objects, markedObjects: markedObjects)

        // 4. Извлекаем действия (с учётом markedObjects)
        let actions = extractActions(from: lowercased, actors: actors, objects: objects, markedObjects: markedObjects)

        // 5. Извлекаем пространственные отношения (с учётом markedObjects)
        let spatialRelations = extractSpatialRelations(from: lowercased, actors: actors, objects: objects, markedObjects: markedObjects)

        // Оборачиваем все действия rule-based парсера в один beat
        // (rule-based пока не умеет разбивать на beats, это задача LLM)
        let beats: [SceneBeat]
        if actions.isEmpty {
            beats = []
        } else {
            beats = [SceneBeat(id: "beat_1", actions: actions)]
        }

        let script = SceneScript(
            sceneHeading: metadata.sceneHeading,
            locationName: metadata.locationName,
            interiorExterior: metadata.interiorExterior,
            timeOfDay: metadata.timeOfDay,
            actors: actors,
            objects: objects,
            beats: beats,
            spatialRelations: spatialRelations,
            originalDescription: description
        )

        // 6. Вычисляем диагностику
        let diagnostics = diagnosticsCalculator.calculateDiagnostics(
            script: script,
            originalText: description,
            markedObjects: markedObjects,
            matchedMarkedObjects: matchedMarkedObjectIds
        )

        return ParsingResult(script: script, diagnostics: diagnostics)
    }

    /// Асинхронный парсинг с поддержкой LLM fallback.
    /// LLM пробуется всегда, если модель доступна.
    func parseAsync(_ description: String, markedObjects: [MarkedObject] = []) async -> ParsingResult {
        await parseAsync(description, markedObjects: markedObjects, state: nil)
    }

    func parseAsync(_ description: String, markedObjects: [MarkedObject] = [], state: SceneChunkState?) async -> ParsingResult {
        if state == nil {
            let bundleResult = await parseBundleAsync(description, markedObjects: markedObjects)
            return ParsingResult(script: bundleResult.activeSceneScript ?? SceneScript(actors: [], objects: [], beats: [], spatialRelations: [], originalDescription: description), diagnostics: bundleResult.diagnostics)
        }
        let output = await makeParseCoordinator().parseAsync(description: description, markedObjects: markedObjects, state: state) { [weak self] in
            self?.ruleBasedParse(description, markedObjects: markedObjects)
                ?? ParsingResult(script: SceneScript(actors: [], objects: [], beats: [], spatialRelations: [], originalDescription: description), diagnostics: .empty)
        }
        lastRuntimeTrace = output.trace
        lastChunkState = makeChunkState(from: output.result.script, fallbackLocationName: state?.locationName)
        print("🤖 [PARSER_V8] route=\(output.trace.route.rawValue) reasons=\(output.trace.reasons.joined(separator: ","))")
        return output.result
    }

    func clarificationMessage(for trace: SceneRuntimeTrace?) -> String? {
        trace?.clarificationMessage
    }

    func parseBundle(
        _ description: String,
        markedObjects: [MarkedObject] = [],
        mode: SceneBundleParseMode = .full,
        previousState: ScriptDocumentState? = nil
    ) async -> SceneBundleParsingResult {
        let result = await bundlePipeline.parse(
            description: description,
            markedObjects: markedObjects,
            mode: mode,
            previousState: previousState
        ) { [weak self] text, markers, state in
            self?.ruleBasedParse(text, markedObjects: markers)
                ?? ParsingResult(script: SceneScript(actors: [], objects: [], beats: [], spatialRelations: [], originalDescription: text), diagnostics: .empty)
        }
        updateBundleContext(with: result, fallbackLocationName: previousState?.stitchStates.last?.metadata.locationName)
        print("🤖 [PARSER_V1] bundle scenes=\(result.bundleScript.scenes.count) chunks=\(result.sceneChunks.count)")
        return result
    }

    func parseBundleAsync(
        _ description: String,
        markedObjects: [MarkedObject] = [],
        mode: SceneBundleParseMode = .full,
        previousState: ScriptDocumentState? = nil
    ) async -> SceneBundleParsingResult {
        let result = await bundlePipeline.parseAsync(
            description: description,
            markedObjects: markedObjects,
            mode: mode,
            previousState: previousState
        ) { [weak self] text, markers, _ in
            self?.ruleBasedParse(text, markedObjects: markers)
                ?? ParsingResult(script: SceneScript(actors: [], objects: [], beats: [], spatialRelations: [], originalDescription: text), diagnostics: .empty)
        }
        updateBundleContext(with: result, fallbackLocationName: previousState?.stitchStates.last?.metadata.locationName)
        print("🤖 [PARSER_V1] bundle scenes=\(result.bundleScript.scenes.count) chunks=\(result.sceneChunks.count)")
        return result
    }

    func configureRemoteOffload(enabled: Bool, provider: RemoteScenePlanProvider?) {
        remoteOffloadEnabled = enabled
        remotePlanProvider = provider
    }

    func setV9RuntimeMode(_ mode: V9RuntimeMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: v9RuntimeModeDefaultsKey)
        // Backward compatibility: old boolean toggle stays aligned with explicit mode.
        UserDefaults.standard.set(mode != .v8Hotfix, forKey: v9EnabledDefaultsKey)
    }

    func getV9RuntimeMode() -> V9RuntimeMode {
        if let raw = UserDefaults.standard.string(forKey: v9RuntimeModeDefaultsKey),
           let mode = V9RuntimeMode(rawValue: raw) {
            return mode
        }
        if UserDefaults.standard.object(forKey: v9EnabledDefaultsKey) != nil,
           UserDefaults.standard.bool(forKey: v9EnabledDefaultsKey) == false {
            return .v8Hotfix
        }
        return .v9Bridge
    }

    func resetRuntimeContext() {
        lastRuntimeTrace = nil
        lastChunkState = nil
        lastDocumentState = nil
        lastBundleResult = nil
        remoteOffloadEnabled = false
        remotePlanProvider = nil
    }

    private func makeChunkState(from script: SceneScript, fallbackLocationName: String?) -> SceneChunkState {
        let knownActors = Dictionary(uniqueKeysWithValues: script.actors.map { actor in
            let key = actor.name?.lowercased() ?? actor.id
            return (key, actor.id)
        })
        let knownObjects = Dictionary(uniqueKeysWithValues: script.objects.map { object in
            let key = object.name?.lowercased() ?? object.id
            return (key, object.id)
        })
        var actorPoses: [String: ActorPose] = [:]
        var heldObjects: [String: String] = [:]

        for beat in script.beats {
            for action in beat.actions {
                if let pose = action.resultingPose {
                    actorPoses[action.actorId] = pose
                }
                switch action.type {
                case .pickUp:
                    if let target = action.target {
                        heldObjects[action.actorId] = target
                    }
                case .putDown, .give:
                    heldObjects.removeValue(forKey: action.actorId)
                default:
                    break
                }
            }
        }

        return SceneChunkState(
            sceneHeading: script.sceneHeading,
            locationName: script.locationName ?? fallbackLocationName,
            knownActors: knownActors,
            knownObjects: knownObjects,
            actorAliases: knownActors,
            objectAliases: knownObjects,
            speakerAliasMap: [:],
            actorPoses: actorPoses,
            heldObjects: heldObjects,
            previousChunkSummary: script.originalDescription
        )
    }

    private func makeChunkState(from stitchState: SceneStitchState, fallbackLocationName: String?) -> SceneChunkState {
        let knownActors = Dictionary(uniqueKeysWithValues: stitchState.actors.map { actor in
            ((actor.name?.lowercased() ?? actor.ref), actor.ref)
        })
        let knownObjects = Dictionary(uniqueKeysWithValues: stitchState.objects.map { object in
            ((object.name?.lowercased() ?? object.ref), object.ref)
        })
        return SceneChunkState(
            sceneID: stitchState.sceneID,
            sceneHeading: stitchState.metadata.sceneHeading,
            locationName: stitchState.metadata.locationName ?? fallbackLocationName,
            knownActors: knownActors.merging(stitchState.registry.actorAliasMap) { current, _ in current },
            knownObjects: knownObjects.merging(stitchState.registry.objectAliasMap) { current, _ in current },
            actorAliases: stitchState.registry.actorAliasMap,
            objectAliases: stitchState.registry.objectAliasMap,
            speakerAliasMap: stitchState.registry.speakerAliasMap,
            actorPoses: stitchState.registry.actorPoses,
            heldObjects: stitchState.registry.heldObjects,
            lastResolvedSpeaker: stitchState.registry.lastResolvedSpeaker,
            previousChunkSummary: stitchState.registry.previousChunkSummary,
            openBeatContext: stitchState.registry.openBeatContext,
            lastActorPositions: stitchState.registry.lastActorPositions
        )
    }

    private func updateBundleContext(with result: SceneBundleParsingResult, fallbackLocationName: String?) {
        lastBundleResult = result
        lastDocumentState = result.documentState
        if let activeSceneID = result.activeSceneId,
           let stitchState = result.documentState.stitchStates.first(where: { $0.sceneID == activeSceneID }) {
            lastChunkState = makeChunkState(from: stitchState, fallbackLocationName: fallbackLocationName)
        } else if let stitchState = result.documentState.stitchStates.last {
            lastChunkState = makeChunkState(from: stitchState, fallbackLocationName: fallbackLocationName)
        } else if let activeSceneScript = result.activeSceneScript {
            lastChunkState = makeChunkState(from: activeSceneScript, fallbackLocationName: fallbackLocationName)
        } else {
            lastChunkState = nil
        }
        lastRuntimeTrace = makeRuntimeTrace(from: result)
    }

    private func makeRuntimeTrace(from result: SceneBundleParsingResult) -> SceneRuntimeTrace {
        let activeChunk = result.chunkDiagnostics.last
        let route: SceneRouterOutcome = result.activeSceneScript == nil ? .fallbackRuleOnly : .acceptLocal
        let reasons = activeChunk?.reasonCodes ?? result.diagnostics.notes
        return SceneRuntimeTrace(
            route: route,
            reasons: reasons,
            anchors: activeChunk?.anchors.sourceBundle ?? .empty,
            usedLegacyPlanBridge: activeChunk?.usedLegacyPlanBridge ?? false,
            clarificationMessage: nil
        )
    }

    /// Старый метод для обратной совместимости (deprecated)
    @available(*, deprecated, message: "Используйте parse(_:markedObjects:) который возвращает ParsingResult")
    func parse(_ description: String) async -> SceneScript {
        return await parse(description, markedObjects: []).script
    }

    private func makeParseCoordinator() -> SceneParseCoordinator {
        SceneParseCoordinator(
            anchorExtractor: anchorExtractor,
            metadataExtractor: metadataExtractor,
            localProvider: llmParser,
            remoteProvider: remotePlanProvider,
            compiler: planCompiler,
            qualityGate: qualityGate,
            diagnosticsCalculator: diagnosticsCalculator,
            remoteOffloadEnabled: remoteOffloadEnabled
        )
    }

    private func decideLLMSelection(
        llmResult: ParsingResult,
        ruleBasedResult: ParsingResult,
        description: String,
        markedObjects: [MarkedObject]
    ) -> LLMSelectionDecision {
        let llmScript = llmResult.script
        let llmDiagnostics = llmResult.diagnostics
        let ruleScript = ruleBasedResult.script
        let ruleDiagnostics = ruleBasedResult.diagnostics
        let lowercasedDescription = description.lowercased()

        if llmScript.actions.isEmpty {
            return .reject("нет действий")
        }

        if llmDiagnostics.matchedMarkedObjects.count < ruleDiagnostics.matchedMarkedObjects.count {
            let canMerge = !llmScript.beats.isEmpty && !ruleScript.objects.isEmpty
            return canMerge
                ? .merge
                : .reject("потеряны размеченные объекты (\(llmDiagnostics.matchedMarkedObjects.count) < \(ruleDiagnostics.matchedMarkedObjects.count))")
        }

        let mentionedMarkedObjects = markedObjects.filter { marker in
            let markerName = marker.name.lowercased()
            return lemmatizer.textContainsKeyword(lowercasedDescription, keyword: markerName) ||
                lowercasedDescription.contains(markerName)
        }
        if !mentionedMarkedObjects.isEmpty && llmDiagnostics.unresolvedMarkedObjects && !ruleDiagnostics.unresolvedMarkedObjects {
            let names = mentionedMarkedObjects.map(\.name).joined(separator: ", ")
            return .reject("упомянутые размеченные объекты потеряны (\(names))")
        }

        if llmScript.objects.count < ruleScript.objects.count && !ruleScript.objects.isEmpty {
            if !llmScript.beats.isEmpty {
                return .merge
            }
            return .reject("объектов меньше, чем в rule-based (\(llmScript.objects.count) < \(ruleScript.objects.count))")
        }

        if llmScript.actions.count + 1 < ruleScript.actions.count {
            return .reject("действий заметно меньше, чем в rule-based (\(llmScript.actions.count) << \(ruleScript.actions.count))")
        }

        let llmHasDanglingTargets = llmScript.actions.contains { action in
            switch action.type {
            case .approach, .stop, .passBy:
                return action.target == nil
            default:
                return false
            }
        }
        let ruleHasDanglingTargets = ruleScript.actions.contains { action in
            switch action.type {
            case .approach, .stop, .passBy:
                return action.target == nil
            default:
                return false
            }
        }
        if llmHasDanglingTargets && !ruleHasDanglingTargets {
            if !ruleScript.objects.isEmpty {
                return .merge
            }
            return .reject("появились действия без target, которых не было в rule-based")
        }

        if llmDiagnostics.confidence + 0.05 < ruleDiagnostics.confidence {
            return .reject("confidence ниже rule-based (\(String(format: "%.2f", llmDiagnostics.confidence)) < \(String(format: "%.2f", ruleDiagnostics.confidence)))")
        }

        return .accept
    }

    private func mergeLLMResult(
        _ llmResult: ParsingResult,
        with ruleBasedResult: ParsingResult,
        description: String,
        markedObjects: [MarkedObject]
    ) -> ParsingResult {
        let mergedActors: [SceneActor] = {
            guard llmResult.script.actors.count == ruleBasedResult.script.actors.count else {
                return ruleBasedResult.script.actors
            }
            let llmHasGenericNames = llmResult.script.actors.contains { actor in
                guard let name = actor.name?.lowercased(), !name.isEmpty else { return false }
                return ["мужчина", "женщина", "парень", "девушка", "он", "она"].contains(name)
            }
            return llmHasGenericNames ? ruleBasedResult.script.actors : llmResult.script.actors
        }()

        var mergedObjects = ruleBasedResult.script.objects
        for object in llmResult.script.objects where !mergedObjects.contains(where: { $0.id == object.id }) {
            mergedObjects.append(object)
        }
        let actorIdMap = makeActorIDMap(
            llmActors: llmResult.script.actors,
            mergedActors: mergedActors,
            beats: llmResult.script.beats
        )
        if actorIdMap == nil, !llmResult.script.beats.isEmpty {
            print("⚠️ [PARSER] Не удалось безопасно смержить actorId из LLM, оставляем rule-based beats")
        }
        let remappedBeats = remapLLMBeats(
            llmResult.script.beats,
            actorIdMap: actorIdMap,
            llmObjects: llmResult.script.objects,
            mergedObjects: mergedObjects,
            description: description
        )
        let remappedRelations = remapSpatialRelations(
            llmResult.script.spatialRelations,
            actorIdMap: actorIdMap,
            llmObjects: llmResult.script.objects,
            mergedObjects: mergedObjects
        )

        let mergedScript = SceneScript(
            sceneHeading: llmResult.script.sceneHeading ?? ruleBasedResult.script.sceneHeading,
            locationName: llmResult.script.locationName ?? ruleBasedResult.script.locationName,
            interiorExterior: llmResult.script.interiorExterior ?? ruleBasedResult.script.interiorExterior,
            timeOfDay: llmResult.script.timeOfDay ?? ruleBasedResult.script.timeOfDay,
            actors: mergedActors,
            objects: mergedObjects,
            beats: remappedBeats.isEmpty ? ruleBasedResult.script.beats : remappedBeats,
            spatialRelations: remappedRelations.isEmpty ? ruleBasedResult.script.spatialRelations : remappedRelations,
            originalDescription: description
        )

        let matchedMarkedObjectIds = matchedMarkedObjectIDs(from: mergedObjects, markedObjects: markedObjects)

        let diagnostics = diagnosticsCalculator.calculateDiagnostics(
            script: mergedScript,
            originalText: description,
            markedObjects: markedObjects,
            matchedMarkedObjects: matchedMarkedObjectIds
        )

        return ParsingResult(script: mergedScript, diagnostics: diagnostics)
    }

    private func remapLLMBeats(
        _ beats: [SceneBeat],
        actorIdMap: [String: String]?,
        llmObjects: [SceneObject],
        mergedObjects: [SceneObject],
        description: String
    ) -> [SceneBeat] {
        guard !beats.isEmpty, let actorIdMap else { return [] }

        let objectIdMap = makeObjectIDMap(llmObjects: llmObjects, mergedObjects: mergedObjects)
        let fallbackObjectId = selectPrimaryGroundedObjectID(from: mergedObjects, description: description)
        let validObjectIDs = Set(mergedObjects.map(\.id))
        let validActorIDs = Set(actorIdMap.values)

        return beats.map { beat in
            let actions = beat.actions.map { action in
                let remappedActorId = actorIdMap[action.actorId] ?? action.actorId
                let remappedTarget = remapActionTarget(
                    action.target,
                    actionType: action.type,
                    objectIdMap: objectIdMap,
                    actorIdMap: actorIdMap,
                    validObjectIDs: validObjectIDs,
                    validActorIDs: validActorIDs,
                    fallbackObjectId: fallbackObjectId
                )

                return SceneAction(
                    id: action.id,
                    actorId: remappedActorId,
                    type: action.type,
                    target: remappedTarget,
                    direction: action.direction,
                    modifier: action.modifier,
                    resultingPose: action.resultingPose,
                    holdingObject: action.holdingObject,
                    dialogue: action.dialogue,
                    fallbackText: action.fallbackText,
                    sourceText: action.sourceText
                )
            }

            return SceneBeat(id: beat.id, actions: actions, camera: beat.camera, minDuration: beat.minDuration)
        }
    }

    private func remapSpatialRelations(
        _ relations: [SpatialRelation],
        actorIdMap: [String: String]?,
        llmObjects: [SceneObject],
        mergedObjects: [SceneObject]
    ) -> [SpatialRelation] {
        guard !relations.isEmpty, let actorIdMap else { return [] }

        let objectIdMap = makeObjectIDMap(llmObjects: llmObjects, mergedObjects: mergedObjects)
        let validObjectIDs = Set(mergedObjects.map(\.id))
        let validActorIDs = Set(actorIdMap.values)

        return relations.compactMap { relation in
            guard let remappedSubject = remapGraphID(
                relation.subject,
                objectIdMap: objectIdMap,
                actorIdMap: actorIdMap,
                validObjectIDs: validObjectIDs,
                validActorIDs: validActorIDs
            ), let remappedObject = remapGraphID(
                relation.object,
                objectIdMap: objectIdMap,
                actorIdMap: actorIdMap,
                validObjectIDs: validObjectIDs,
                validActorIDs: validActorIDs
            ) else {
                return nil
            }

            return SpatialRelation(
                id: relation.id,
                subject: remappedSubject,
                relation: relation.relation,
                object: remappedObject
            )
        }
    }

    private func makeObjectIDMap(llmObjects: [SceneObject], mergedObjects: [SceneObject]) -> [String: String] {
        var idMap: [String: String] = [:]

        for llmObject in llmObjects {
            if mergedObjects.contains(where: { $0.id == llmObject.id }) {
                idMap[llmObject.id] = llmObject.id
                continue
            }

            if let llmMarkedShortID = llmObject.markedObjectShortID,
               let exactMarkedMatch = mergedObjects.first(where: { $0.markedObjectShortID == llmMarkedShortID }) {
                idMap[llmObject.id] = exactMarkedMatch.id
                continue
            }

            if let exactNameMatch = mergedObjects.first(where: {
                $0.type == llmObject.type &&
                $0.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ==
                llmObject.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }) {
                idMap[llmObject.id] = exactNameMatch.id
                continue
            }

            let groundedTypeMatches = mergedObjects.filter {
                $0.type == llmObject.type && $0.markedObjectShortID != nil
            }
            if groundedTypeMatches.count == 1, let groundedTypeMatch = groundedTypeMatches.first {
                idMap[llmObject.id] = groundedTypeMatch.id
            }
        }

        return idMap
    }

    private func makeActorIDMap(
        llmActors: [SceneActor],
        mergedActors: [SceneActor],
        beats: [SceneBeat]
    ) -> [String: String]? {
        let llmActorIds = llmActors.map(\.id)
        let mergedActorIds = mergedActors.map(\.id)

        guard llmActorIds.count == mergedActorIds.count else { return nil }

        let referencedActorIds = Set(beats.flatMap { $0.actions.map(\.actorId) })
        if !referencedActorIds.isSubset(of: Set(llmActorIds)) {
            return nil
        }

        return Dictionary(uniqueKeysWithValues: zip(llmActorIds, mergedActorIds))
    }

    private func remapActionTarget(
        _ target: String?,
        actionType: SceneAction.ActionType,
        objectIdMap: [String: String],
        actorIdMap: [String: String],
        validObjectIDs: Set<String>,
        validActorIDs: Set<String>,
        fallbackObjectId: String?
    ) -> String? {
        guard let target else {
            return requiresObjectTarget(actionType) ? fallbackObjectId : nil
        }

        if let remappedObjectId = objectIdMap[target] {
            return remappedObjectId
        }

        if let remappedActorId = actorIdMap[target] {
            return remappedActorId
        }

        if validObjectIDs.contains(target) || validActorIDs.contains(target) {
            return target
        }

        if target.hasPrefix("actor_") {
            return nil
        }

        let looksLikeObjectID = target.hasPrefix("object_") || target.contains("marked_")
        if looksLikeObjectID || requiresObjectTarget(actionType) {
            return fallbackObjectId
        }

        return nil
    }

    private func remapGraphID(
        _ id: String,
        objectIdMap: [String: String],
        actorIdMap: [String: String],
        validObjectIDs: Set<String>,
        validActorIDs: Set<String>
    ) -> String? {
        if let remappedObjectId = objectIdMap[id] {
            return remappedObjectId
        }

        if let remappedActorId = actorIdMap[id] {
            return remappedActorId
        }

        if validObjectIDs.contains(id) || validActorIDs.contains(id) {
            return id
        }

        return nil
    }

    private func selectPrimaryGroundedObjectID(from objects: [SceneObject], description: String) -> String? {
        let lowercasedDescription = description.lowercased()

        if let namedGroundedObject = objects.first(where: { object in
            guard object.markedObjectShortID != nil,
                  let name = object.name?.lowercased(),
                  !name.isEmpty else { return false }
            return lemmatizer.textContainsKeyword(lowercasedDescription, keyword: name) || lowercasedDescription.contains(name)
        }) {
            return namedGroundedObject.id
        }

        return objects.first(where: { $0.markedObjectShortID != nil })?.id
    }

    private func requiresObjectTarget(_ actionType: SceneAction.ActionType) -> Bool {
        switch actionType {
        case .approach, .stop, .passBy, .lookAt, .pickUp, .putDown, .open, .close:
            return true
        default:
            return false
        }
    }

    // MARK: - Actor Extraction

    private func extractActors(from text: String, originalText: String) -> [SceneActor] {
        var actors: [SceneActor] = []
        var actorCounter = 1
        var processedTypes: Set<SceneActor.ActorType> = []

        // Паттерны для поиска актёров с количеством
        let patterns: [(pattern: String, type: SceneActor.ActorType)] = [
            // С количеством
            (#"(\d+)\s*(?:актёр|актер|актёра|актера|актёров|актеров)"#, .human),
            (#"(\d+)\s*(?:человек|человека|людей)"#, .human),
            (#"(\d+)\s*(?:персонаж|персонажа|персонажей)"#, .human),
            (#"(\d+)\s*(?:тигр|тигра|тигров)"#, .tiger),
            (#"(\d+)\s*(?:собак|собаки|пёс|пса|псов)"#, .dog),
            (#"(\d+)\s*(?:кот|кота|котов|кошк|кошек)"#, .cat),
            (#"(\d+)\s*(?:птиц|птицы)"#, .bird),
        ]

        // Ищем паттерны с числами
        for (pattern, type) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

                for match in matches {
                    let nsRange = match.range(at: 1)
                    // Безопасная проверка диапазона
                    guard nsRange.location != NSNotFound,
                          nsRange.location + nsRange.length <= (text as NSString).length,
                          nsRange.length > 0,
                          let numberRange = Range(nsRange, in: text),
                          numberRange.lowerBound >= text.startIndex,
                          numberRange.upperBound <= text.endIndex,
                          numberRange.lowerBound < numberRange.upperBound else { continue }

                    let count = Int(text[numberRange]) ?? 1

                    for _ in 0..<count {
                        actors.append(SceneActor(
                            id: "actor_\(actorCounter)",
                            type: type,
                            name: nil
                        ))
                        actorCounter += 1
                    }
                    processedTypes.insert(type)
                }
            }
        }

        // Ищем упоминания без чисел (с использованием лемматизации)
        print("🔍 [EXTRACT_ACTORS] Поиск упоминаний без чисел (processedTypes: \(processedTypes.map { $0.rawValue }.joined(separator: ", ")))...")
        for (keyword, type) in KeywordsMapping.actorKeywords {
            // Пропускаем если уже обработали этот тип
            if processedTypes.contains(type) {
                print("🔍 [EXTRACT_ACTORS] Пропуск ключевого слова '\(keyword)' (тип \(type.rawValue) уже обработан)")
                continue
            }

            // Используем лемматизацию для более точного поиска
            if lemmatizer.textContainsKeyword(text, keyword: keyword) {
                var actualType = type

                // Исправление конфликта с именем "Лев"
                if actualType == .lion {
                    let isCapitalized = originalText.contains("Лев") || originalText.contains("Льва") ||
                                        originalText.contains("Льву") || originalText.contains("Львом") ||
                                        originalText.contains("ЛЕВ")
                    if isCapitalized {
                        print("🔍 [EXTRACT_ACTORS] Слово '\(keyword)' определено как имя персонажа (human)")
                        actualType = .human
                    }
                }

                // Проверяем что это не часть уже найденного паттерна с числом
                let hasNumberBefore = hasDigitBefore(keyword: keyword, in: text)

                if !hasNumberBefore {
                    let actor = SceneActor(
                        id: "actor_\(actorCounter)",
                        type: actualType,
                        name: nil
                    )
                    actors.append(actor)
                    print("🔍 [EXTRACT_ACTORS] Создан актёр из ключевого слова: id='\(actor.id)', type=\(actualType.rawValue)")
                    actorCounter += 1
                    processedTypes.insert(actualType)
                } else {
                    print("🔍 [EXTRACT_ACTORS] Пропуск '\(keyword)' - есть число перед ним")
                }
            }
        }

        // Если ничего не найдено, создаём одного актёра по умолчанию
        if actors.isEmpty {
            print("🔍 [EXTRACT_ACTORS] Актёры не найдены, создаём актёра по умолчанию")
            actors.append(SceneActor(id: "actor_1", type: .human, name: nil))
        }

        print("🔍 [EXTRACT_ACTORS] Итого актёров: \(actors.count)")
        return actors
    }

    // MARK: - Object Extraction

    private func extractObjects(from text: String, markedObjects: [MarkedObject] = []) -> [SceneObject] {
        print("🔍 [EXTRACT_OBJECTS] Начало извлечения объектов из текста: '\(text)'")
        print("🔍 [EXTRACT_OBJECTS] Размеченных объектов для поиска: \(markedObjects.count)")

        var objects: [SceneObject] = []
        var objectCounter = 1
        var matchedMarkedObjectIds: Set<UUID> = []

        // 1. Сначала ищем упоминания markedObjects по именам (с лемматизацией)
        if !markedObjects.isEmpty {
            print("🔍 [EXTRACT_OBJECTS] Шаг 1: Поиск упоминаний markedObjects...")
            let references = markedObjectMatcher.findMarkedObjectReferences(in: text, markedObjects: markedObjects)
            print("🔍 [EXTRACT_OBJECTS] Найдено ссылок на markedObjects: \(references.count)")

            for (index, reference) in references.enumerated() {
                print("🔍 [EXTRACT_OBJECTS]   Reference[\(index)]: markerId=\(reference.markerId.uuidString), markerName='\(reference.markerName)', matchedText='\(reference.matchedText)'")

                if let marker = markedObjects.first(where: { $0.id == reference.markerId }) {
                    let relativePosition = determineRelativePosition(for: reference.matchedText, in: text)

                    let newObject = SceneObject(
                        id: marker.canonicalMarkedObjectID,
                        type: marker.type,
                        detectedPosition: marker.worldPosition,
                        relativePosition: relativePosition
                    )
                    objects.append(newObject)
                    print("🔍 [EXTRACT_OBJECTS] Создан объект из markedObject: id='\(newObject.id)', type=\(newObject.type.rawValue), position=\(newObject.detectedPosition != nil ? "YES" : "NO")")
                    objectCounter += 1
                    matchedMarkedObjectIds.insert(marker.id)
                }
            }
        }

        // 2. Затем ищем стандартные объекты из KeywordsMapping
        // ВАЖНО: добавляем только один объект каждого типа (чтобы избежать дубликатов из-за разных падежей)
        print("🔍 [EXTRACT_OBJECTS] Шаг 2: Поиск стандартных объектов из KeywordsMapping...")
        // Собираем типы объектов, которые уже добавлены из markedObjects
        let markedObjectTypes = Set(matchedMarkedObjectIds.compactMap { markerId in
            markedObjects.first(where: { $0.id == markerId })?.type
        })
        var processedObjectTypes = Set(markedObjectTypes) // Начинаем с типов из markedObjects

        for (keyword, type) in KeywordsMapping.objectKeywords {
            // Пропускаем если объект этого типа уже добавлен (из markedObjects или ранее)
            if processedObjectTypes.contains(type) {
                print("🔍 [EXTRACT_OBJECTS] Пропуск ключевого слова '\(keyword)' (тип \(type.rawValue) уже добавлен)")
                continue
            }

            // Используем лемматизацию для поиска
            if lemmatizer.textContainsKeyword(text, keyword: keyword) {
                print("🔍 [EXTRACT_OBJECTS] Найдено ключевое слово '\(keyword)' (тип \(type.rawValue)) через лемматизацию")

                let relativePosition = determineRelativePosition(for: keyword, in: text)

                let newObject = SceneObject(
                    id: "object_\(objectCounter)",
                    type: type,
                    detectedPosition: nil,
                    relativePosition: relativePosition
                )
                objects.append(newObject)
                processedObjectTypes.insert(type)
                print("🔍 [EXTRACT_OBJECTS] Создан стандартный объект: id='\(newObject.id)', type=\(newObject.type.rawValue), relativePosition=\(newObject.relativePosition.rawValue)")
                objectCounter += 1
            }
        }

        print("🔍 [EXTRACT_OBJECTS] Итого объектов: \(objects.count) (из markedObjects: \(matchedMarkedObjectIds.count), стандартных: \(objects.count - matchedMarkedObjectIds.count))")
        return objects
    }

    // MARK: - Action Extraction

    private func extractActions(
        from text: String,
        actors: [SceneActor],
        objects: [SceneObject],
        markedObjects: [MarkedObject] = []
    ) -> [SceneAction] {
        print("🔍 [EXTRACT_ACTIONS] Начало извлечения действий из текста: '\(text)'")
        print("🔍 [EXTRACT_ACTIONS] Доступно актёров: \(actors.count), объектов: \(objects.count)")

        var actions: [SceneAction] = []
        var actionCounter = 1

        // Специальные паттерны для комплексных действий
        let complexPatterns: [(pattern: String, type: SceneAction.ActionType, direction: SceneAction.Direction?)] = [
            // Навстречу друг другу
            (#"(?:идут|идёт|идет)\s*(?:навстречу|друг\s*(?:к|на)\s*друг)"#, .walk, .towardEachOther),
            (#"навстречу\s*друг\s*другу"#, .walk, .towardEachOther),

            // Направления
            (#"(?:идёт|идет|идут|поворачивает|поворачивают)\s*(?:на)?лево"#, .walk, .left),
            (#"(?:идёт|идет|идут|поворачивает|поворачивают)\s*(?:на)?право"#, .walk, .right),
            (#"(?:идёт|идет|идут)\s*прямо"#, .walk, .forward),
            (#"(?:идёт|идет|идут)\s*(?:вперёд|вперед)"#, .walk, .forward),

            // Повороты
            (#"поворачивает\s*(?:на)?лево"#, .turn, .left),
            (#"поворачивает\s*(?:на)?право"#, .turn, .right),

            // Продолжает идти
            (#"продолжает\s*(?:идти|двигаться)"#, .walk, .forward),
        ]

        // Паттерны для подхода к объектам
        let approachPatterns: [(pattern: String, preposition: String)] = [
            (#"(?:подходит|подходят|идёт|идет|идут)\s*(?:к|ко)\s*(\w+)"#, "к"),
            (#"(?:проходит|проходят)\s*мимо\s*(\w+)"#, "мимо"),
        ]

        // Паттерн "от X к Y" - движение между двумя объектами
        let fromToPattern = #"(?:бежит|бегут|бежать|идёт|идет|идут)\s*от\s*(\w+)\s*(?:к|ко|до)\s*(\w+)"#
        if let regex = try? NSRegularExpression(pattern: fromToPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

            if !matches.isEmpty {
                print("🔍 [EXTRACT_ACTIONS] Найден паттерн 'от X к Y', совпадений: \(matches.count)")
            }

            for match in matches {
                guard match.numberOfRanges > 2 else { continue }

                // Безопасная проверка диапазонов
                let fromNSRange = match.range(at: 1)
                let toNSRange = match.range(at: 2)

                guard fromNSRange.location != NSNotFound,
                      fromNSRange.location + fromNSRange.length <= (text as NSString).length,
                      fromNSRange.length > 0,
                      let fromRange = Range(fromNSRange, in: text),
                      fromRange.lowerBound >= text.startIndex,
                      fromRange.upperBound <= text.endIndex,
                      fromRange.lowerBound < fromRange.upperBound,
                      toNSRange.location != NSNotFound,
                      toNSRange.location + toNSRange.length <= (text as NSString).length,
                      toNSRange.length > 0,
                      let toRange = Range(toNSRange, in: text),
                      toRange.lowerBound >= text.startIndex,
                      toRange.upperBound <= text.endIndex,
                      toRange.lowerBound < toRange.upperBound else { continue }

                let fromWord = String(text[fromRange])
                let toWord = String(text[toRange])
                print("🔍 [EXTRACT_ACTIONS] Паттерн 'от X к Y': from='\(fromWord)', to='\(toWord)'")

                // Находим объекты (с учётом markedObjects)
                let fromObject = findMatchingObject(word: fromWord, objects: objects, markedObjects: markedObjects)
                let toObject = findMatchingObject(word: toWord, objects: objects, markedObjects: markedObjects)
                print("🔍 [EXTRACT_ACTIONS] Найденные объекты: fromObject=\(fromObject?.id ?? "nil"), toObject=\(toObject?.id ?? "nil")")

                // Определяем тип действия (бег или ходьба)
                let actionType: SceneAction.ActionType = text.contains("бег") ? .run : .walk

                // Создаём действия для ВСЕХ актёров
                for actor in actors {
                    // Действие 1: начальное положение у первого объекта (если найден)
                    if let fromObj = fromObject {
                        actions.append(SceneAction(
                            id: "action_\(actionCounter)",
                            actorId: actor.id,
                            type: .stand,
                            target: fromObj.id,
                            direction: .toTarget,
                            modifier: nil
                        ))
                        actionCounter += 1
                    }

                    // Действие 2: движение ко второму объекту
                    if let toObj = toObject {
                        actions.append(SceneAction(
                            id: "action_\(actionCounter)",
                            actorId: actor.id,
                            type: actionType,
                            target: toObj.id,
                            direction: .toTarget,
                            modifier: extractModifier(from: text)
                        ))
                        actionCounter += 1
                    }
                }
            }
        }

        // Обрабатываем комплексные паттерны
        for (pattern, actionType, direction) in complexPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {

                // Определяем к каким актёрам относится действие
                if direction == .towardEachOther && actors.count >= 2 {
                    // Для "навстречу друг другу" - создаём действия для первых двух актёров
                    actions.append(SceneAction(
                        id: "action_\(actionCounter)",
                        actorId: actors[0].id,
                        type: actionType,
                        target: actors[1].id,
                        direction: direction,
                        modifier: extractModifier(from: text)
                    ))
                    actionCounter += 1

                    actions.append(SceneAction(
                        id: "action_\(actionCounter)",
                        actorId: actors[1].id,
                        type: actionType,
                        target: actors[0].id,
                        direction: direction,
                        modifier: extractModifier(from: text)
                    ))
                    actionCounter += 1
                } else {
                    // Для остальных - назначаем первому актёру (или последнему упомянутому)
                    let actorId = determineActorForAction(text: text, actors: actors, actionPattern: pattern)

                    actions.append(SceneAction(
                        id: "action_\(actionCounter)",
                        actorId: actorId,
                        type: actionType,
                        target: nil,
                        direction: direction,
                        modifier: extractModifier(from: text)
                    ))
                    actionCounter += 1
                }
            }
        }

        // Обрабатываем паттерны с объектами
        for (pattern, preposition) in approachPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

                for match in matches {
                    guard match.numberOfRanges > 1 else { continue }

                    let nsRange = match.range(at: 1)
                    // Безопасная проверка диапазона
                    guard nsRange.location != NSNotFound,
                          nsRange.location + nsRange.length <= (text as NSString).length,
                          nsRange.length > 0,
                          let objectRange = Range(nsRange, in: text),
                          objectRange.lowerBound >= text.startIndex,
                          objectRange.upperBound <= text.endIndex,
                          objectRange.lowerBound < objectRange.upperBound else { continue }

                    let objectWord = String(text[objectRange])

                    // Находим соответствующий объект (с учётом markedObjects)
                    if let targetObject = findMatchingObject(word: objectWord, objects: objects, markedObjects: markedObjects) {
                        let actionType: SceneAction.ActionType = preposition == "мимо" ? .passBy : .approach

                        // Определяем, во множественном ли числе глагол (например, "идут" vs "идёт")
                        let isPluralVerb = isPluralVerbForm(in: text, pattern: pattern)

                        if isPluralVerb && actors.count > 1 {
                            // Если глагол во множественном числе и есть несколько актёров - создаём действия для всех
                            print("🔍 [EXTRACT_ACTIONS] Глагол во множественном числе, создаём действия для всех \(actors.count) актёров")
                            for actor in actors {
                                let action = SceneAction(
                                    id: "action_\(actionCounter)",
                                    actorId: actor.id,
                                    type: actionType,
                                    target: targetObject.id,
                                    direction: .toTarget,
                                    modifier: extractModifier(from: text)
                                )
                                actions.append(action)
                                print("🔍 [EXTRACT_ACTIONS] Создано действие: id='\(action.id)', actorId='\(action.actorId)', type=\(action.type.rawValue), target='\(action.target ?? "nil")'")
                                actionCounter += 1
                            }
                        } else {
                            // Если единственное число или только один актёр - создаём действие для первого
                            let action = SceneAction(
                                id: "action_\(actionCounter)",
                                actorId: actors.first?.id ?? "actor_1",
                                type: actionType,
                                target: targetObject.id,
                                direction: .toTarget,
                                modifier: extractModifier(from: text)
                            )
                            actions.append(action)
                            print("🔍 [EXTRACT_ACTIONS] Создано действие: id='\(action.id)', actorId='\(action.actorId)', type=\(action.type.rawValue), target='\(action.target ?? "nil")'")
                            actionCounter += 1
                        }
                    } else {
                        print("🔍 [EXTRACT_ACTIONS] Объект для слова '\(objectWord)' не найден")
                    }
                }
            }
        }

        // Паттерны для остановки около объекта
        // «останавливается около/у/возле/рядом с X»
        let stopPatterns: [String] = [
            #"(?:останавлива(?:ется|ются)|встаёт|встают|стоит|стоят)\s*(?:около|у|возле|рядом\s*с|рядом\s*со)\s+(\w+)"#,
        ]

        for pattern in stopPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

                for match in matches {
                    guard match.numberOfRanges > 1 else { continue }

                    let nsRange = match.range(at: 1)
                    guard nsRange.location != NSNotFound,
                          nsRange.location + nsRange.length <= (text as NSString).length,
                          nsRange.length > 0,
                          let objectRange = Range(nsRange, in: text),
                          objectRange.lowerBound >= text.startIndex,
                          objectRange.upperBound <= text.endIndex,
                          objectRange.lowerBound < objectRange.upperBound else { continue }

                    let objectWord = String(text[objectRange])

                    // Находим целевой объект
                    if let targetObject = findMatchingObject(word: objectWord, objects: objects, markedObjects: markedObjects) {
                        // Определяем форму глагола (множественное число?)
                        let pluralForms = ["останавливаются", "встают", "стоят"]
                        let isPlural = pluralForms.contains(where: { text.contains($0) })

                        let actorsForStop = (isPlural && actors.count > 1) ? actors : [actors.first].compactMap { $0 }

                        for actor in actorsForStop {
                            // Не дублируем если уже есть stop для этого актёра
                            let alreadyHasStop = actions.contains { $0.actorId == actor.id && ($0.type == .stop || $0.type == .stand) && $0.target == targetObject.id }
                            if !alreadyHasStop {
                                let action = SceneAction(
                                    id: "action_\(actionCounter)",
                                    actorId: actor.id,
                                    type: .stop,
                                    target: targetObject.id,
                                    direction: .toTarget,
                                    modifier: nil
                                )
                                actions.append(action)
                                print("🔍 [EXTRACT_ACTIONS] Создано действие stop: id='\(action.id)', actorId='\(action.actorId)', target='\(action.target ?? "nil")'")
                                actionCounter += 1
                            }
                        }
                    }
                }
            }
        }


        // Если не нашли комплексных паттернов, ищем простые действия (с лемматизацией)
        if actions.isEmpty {
            for (keyword, actionType) in KeywordsMapping.actionKeywords {
                if lemmatizer.textContainsKeyword(text, keyword: keyword) {
                    let direction = extractDirection(from: text)
                    let target = findTargetForAction(text: text, objects: objects, markedObjects: markedObjects)

                    actions.append(SceneAction(
                        id: "action_\(actionCounter)",
                        actorId: actors.first?.id ?? "actor_1",
                        type: actionType,
                        target: target,
                        direction: direction,
                        modifier: extractModifier(from: text)
                    ))
                    actionCounter += 1
                    break  // Берём только первое действие при простом парсинге
                }
            }
        }

        // Обрабатываем "один ... другой ..." конструкции
        print("🔍 [EXTRACT_ACTIONS] Обработка конструкций 'один ... другой'...")
        actions = processOneAnotherConstruction(text: text, actors: actors, existingActions: actions, actionCounter: &actionCounter)

        // Дедупликация: убираем дублирующиеся действия (одинаковый actorId + type + target + direction)
        var seen: Set<String> = []
        actions = actions.filter { action in
            let key = "\(action.actorId)_\(action.type.rawValue)_\(action.target ?? "")_\(action.direction?.rawValue ?? "")"
            if seen.contains(key) {
                print("🔍 [EXTRACT_ACTIONS] Удалён дубликат: \(action.id) (\(key))")
                return false
            }
            seen.insert(key)
            return true
        }

        print("🔍 [EXTRACT_ACTIONS] Итого действий (после дедупликации): \(actions.count)")
        return actions
    }

    // MARK: - Spatial Relations Extraction

    private func extractSpatialRelations(
        from text: String,
        actors: [SceneActor],
        objects: [SceneObject],
        markedObjects: [MarkedObject] = []
    ) -> [SpatialRelation] {
        var relations: [SpatialRelation] = []
        var relationCounter = 1

        // Паттерны для пространственных отношений
        let patterns: [(pattern: String, relation: SpatialRelation.RelationType)] = [
            (#"мимо\s+(\w+)"#, .passBy),
            (#"около\s+(\w+)"#, .near),
            (#"рядом\s+с\s+(\w+)"#, .near),
            (#"возле\s+(\w+)"#, .near),
            (#"перед\s+(\w+)"#, .inFrontOf),
            (#"за\s+(\w+)"#, .behind),
            (#"позади\s+(\w+)"#, .behind),
            (#"слева\s+от\s+(\w+)"#, .leftOf),
            (#"справа\s+от\s+(\w+)"#, .rightOf),
            (#"между\s+(\w+)"#, .between),
        ]

        for (pattern, relationType) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

                for match in matches {
                    guard match.numberOfRanges > 1 else { continue }

                    let nsRange = match.range(at: 1)
                    // Безопасная проверка диапазона
                    guard nsRange.location != NSNotFound,
                          nsRange.location + nsRange.length <= (text as NSString).length,
                          nsRange.length > 0,
                          let objectRange = Range(nsRange, in: text),
                          objectRange.lowerBound >= text.startIndex,
                          objectRange.upperBound <= text.endIndex,
                          objectRange.lowerBound < objectRange.upperBound else { continue }

                    let objectWord = String(text[objectRange])

                    // Находим объект (с учётом markedObjects)
                    if let targetObject = findMatchingObject(word: objectWord, objects: objects, markedObjects: markedObjects) {
                        // Субъект - первый актёр
                        let subjectId = actors.first?.id ?? "actor_1"

                        relations.append(SpatialRelation(
                            id: "relation_\(relationCounter)",
                            subject: subjectId,
                            relation: relationType,
                            object: targetObject.id
                        ))
                        relationCounter += 1
                    }
                }
            }
        }

        return relations
    }

    // MARK: - Helper Methods

    private func hasDigitBefore(keyword: String, in text: String) -> Bool {
        guard let range = text.range(of: keyword, options: .caseInsensitive) else { return false }

        let beforeIndex = range.lowerBound
        guard beforeIndex > text.startIndex else { return false }

        // Безопасно вычисляем начальную позицию для проверки (максимум 3 символа назад)
        let maxLookback = 3
        let startCheck: String.Index
        if let calculatedStart = text.index(beforeIndex, offsetBy: -maxLookback, limitedBy: text.startIndex) {
            startCheck = calculatedStart
        } else {
            startCheck = text.startIndex
        }

        // Безопасно извлекаем подстроку
        guard startCheck < beforeIndex else { return false }
        let beforeText = String(text[startCheck..<beforeIndex])

        return beforeText.contains(where: { $0.isNumber })
    }

    private func determineRelativePosition(for keyword: String, in text: String) -> SceneObject.RelativePosition {
        // Ищем контекст вокруг ключевого слова
        guard let range = text.range(of: keyword, options: .caseInsensitive) else { return .unknown }

        // Безопасно вычисляем границы контекста
        let startIndex = text.index(range.lowerBound, offsetBy: -30, limitedBy: text.startIndex) ?? text.startIndex
        let endIndex = text.index(range.upperBound, offsetBy: 30, limitedBy: text.endIndex) ?? text.endIndex

        // Проверяем что startIndex < endIndex
        guard startIndex < endIndex else { return .unknown }

        let context = String(text[startIndex..<endIndex])

        if context.contains("слева") || context.contains("левой") {
            return .left
        } else if context.contains("справа") || context.contains("правой") {
            return .right
        } else if context.contains("сзади") || context.contains("позади") {
            return .background
        } else if context.contains("впереди") || context.contains("перед") {
            return .foreground
        } else if context.contains("центр") || context.contains("середин") {
            return .center
        }

        return .unknown
    }

    private func extractModifier(from text: String) -> SceneAction.ActionModifier? {
        for (keyword, modifier) in KeywordsMapping.modifierKeywords {
            if lemmatizer.textContainsKeyword(text, keyword: keyword) {
                return modifier
            }
        }
        return nil
    }

    private func extractDirection(from text: String) -> SceneAction.Direction? {
        // Проверяем комплексные направления
        if lemmatizer.textContainsKeyword(text, keyword: "навстречу") ||
           text.contains("друг к другу") || text.contains("друг на друга") {
            return .towardEachOther
        }
        if text.contains("друг от друга") {
            return .awayFromEachOther
        }

        // Простые направления (с лемматизацией)
        for (keyword, direction) in KeywordsMapping.directionKeywords {
            if lemmatizer.textContainsKeyword(text, keyword: keyword) {
                return direction
            }
        }
        return nil
    }

    private func findTargetForAction(text: String, objects: [SceneObject], markedObjects: [MarkedObject] = []) -> String? {
        // 1. Сначала ищем в markedObjects (приоритет)
        for marker in markedObjects {
            let markerName = marker.name.lowercased()
            let patterns = ["к \(markerName)", "ко \(markerName)", "мимо \(markerName)", "около \(markerName)", "к моему \(markerName)", "к моей \(markerName)"]
            for pattern in patterns {
                if lemmatizer.textContainsKeyword(text, keyword: pattern) || text.contains(pattern) {
                    // Находим соответствующий объект в списке
                    if let object = objects.first(where: { $0.markedObjectShortID == marker.markedShortID || ($0.type == marker.type && $0.detectedPosition == marker.worldPosition) }) {
                        return object.id
                    }
                }
            }
        }

        // 2. Ищем "к <объекту>" или "мимо <объекта>" (с лемматизацией) в стандартных ключевых словах
        for object in objects {
            for (keyword, _) in KeywordsMapping.objectKeywords where KeywordsMapping.objectKeywords[keyword] == object.type {
                // Проверяем паттерны типа "к столу", "мимо шкафа" с учётом лемматизации
                let patterns = ["к \(keyword)", "ко \(keyword)", "мимо \(keyword)", "около \(keyword)"]
                for pattern in patterns {
                    // Разбиваем паттерн на предлог и объект
                    let parts = pattern.split(separator: " ", maxSplits: 1)
                    if parts.count == 2 {
                        let preposition = String(parts[0])
                        let objectKeyword = String(parts[1])

                        // Ищем предлог в тексте, затем проверяем объект через лемматизацию
                        if text.contains(preposition) {
                            // Ищем объект после предлога
                            if let range = text.range(of: preposition) {
                                // Безопасно извлекаем текст после предлога
                                guard range.upperBound < text.endIndex else { continue }
                                let afterPreposition = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                                if lemmatizer.textContainsKeyword(afterPreposition, keyword: objectKeyword) {
                                    return object.id
                                }
                            }
                        }
                    } else if text.contains(pattern) {
                        return object.id
                    }
                }
            }
        }
        return nil
    }

    private func findMatchingObject(word: String, objects: [SceneObject], markedObjects: [MarkedObject] = []) -> SceneObject? {
        let lowercasedWord = word.lowercased()
        print("🔍 [FIND_MATCHING_OBJECT] Поиск объекта для слова: '\(lowercasedWord)'")

        // 1. Сначала ищем в markedObjects по имени (с лемматизацией)
        if let marker = markedObjectMatcher.findMarkedObject(byWord: lowercasedWord, in: markedObjects) {
            print("🔍 [FIND_MATCHING_OBJECT] Найден markedObject: id=\(marker.id.uuidString), name='\(marker.name)', type=\(marker.type.rawValue)")

            // Ищем соответствующий SceneObject в списке объектов
            let found = objects.first { object in
                // Проверяем по ID (если объект был создан из маркера)
                if object.markedObjectShortID == marker.markedShortID {
                    return true
                }
                // Или по типу и позиции
                return object.type == marker.type && object.detectedPosition == marker.worldPosition
            }

            if let found = found {
                print("🔍 [FIND_MATCHING_OBJECT] Найден SceneObject из markedObject: id='\(found.id)'")
                return found
            } else {
                print("🔍 [FIND_MATCHING_OBJECT] MarkedObject найден, но соответствующий SceneObject не найден в списке")
            }
        }

        // 2. Ищем объект по ключевому слову (с лемматизацией)
        print("🔍 [FIND_MATCHING_OBJECT] Поиск в стандартных ключевых словах...")
        for (keyword, type) in KeywordsMapping.objectKeywords {
            if lemmatizer.matchesKeyword(lowercasedWord, keyword: keyword) {
                print("🔍 [FIND_MATCHING_OBJECT] Совпадение с ключевым словом '\(keyword)' (тип \(type.rawValue))")
                if let found = objects.first(where: { $0.type == type }) {
                    print("🔍 [FIND_MATCHING_OBJECT] Найден стандартный объект: id='\(found.id)'")
                    return found
                } else {
                    print("🔍 [FIND_MATCHING_OBJECT] Ключевое слово найдено, но объект типа \(type.rawValue) отсутствует в списке")
                }
            }
        }

        // 3. Пытаемся найти частичное совпадение через лемматизацию
        print("🔍 [FIND_MATCHING_OBJECT] Поиск частичных совпадений...")
        for object in objects {
            for (keyword, type) in KeywordsMapping.objectKeywords where type == object.type {
                if lemmatizer.matchesKeyword(lowercasedWord, keyword: keyword) {
                    print("🔍 [FIND_MATCHING_OBJECT] Найдено частичное совпадение: id='\(object.id)'")
                    return object
                }
            }
        }

        print("🔍 [FIND_MATCHING_OBJECT] Объект не найден для слова '\(lowercasedWord)'")
        return nil
    }

    private func determineActorForAction(text: String, actors: [SceneActor], actionPattern: String) -> String {
        // Для паттернов типа "один поворачивает направо" - определяем по контексту
        if text.contains("один") && text.contains("друг") {
            // Это "один ... другой" конструкция
            // Определяем какой актёр к какому действию
            if let patternRange = text.range(of: actionPattern, options: .regularExpression) {
                // Безопасно извлекаем текст до паттерна
                guard patternRange.lowerBound > text.startIndex else { return actors.first?.id ?? "actor_1" }
                let beforePattern = String(text[..<patternRange.lowerBound])
                if beforePattern.contains("один") && !beforePattern.contains("друг") {
                    return actors.first?.id ?? "actor_1"
                } else if beforePattern.contains("друг") {
                    return actors.count > 1 ? actors[1].id : actors.first?.id ?? "actor_1"
                }
            }
        }

        return actors.first?.id ?? "actor_1"
    }

    private func processOneAnotherConstruction(
        text: String,
        actors: [SceneActor],
        existingActions: [SceneAction],
        actionCounter: inout Int
    ) -> [SceneAction] {
        var actions = existingActions

        // Паттерн "один ... другой ..."
        // Например: "один поворачивает направо, другой продолжает идти прямо"
        let oneAnotherPattern = #"один\s+(.+?)\s*,\s*друг(?:ой|ая|ие)\s+(.+?)(?:\.|,|$)"#

        guard actors.count >= 2 else { return actions }

        if let regex = try? NSRegularExpression(pattern: oneAnotherPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

            for match in matches {
                // Действие первого актёра
                if match.numberOfRanges > 1 {
                    let nsRange = match.range(at: 1)
                    // Проверяем что диапазон валидный
                    guard nsRange.location != NSNotFound,
                          nsRange.location + nsRange.length <= (text as NSString).length,
                          nsRange.length > 0,
                          let firstRange = Range(nsRange, in: text) else { continue }

                    // Проверяем границы диапазона
                    guard firstRange.lowerBound >= text.startIndex,
                          firstRange.upperBound <= text.endIndex,
                          firstRange.lowerBound < firstRange.upperBound else { continue }

                    let firstActionText = String(text[firstRange])

                    if let action = parseSimpleAction(from: firstActionText, actorId: actors[0].id, actionId: "action_\(actionCounter)") {
                        // Удаляем дубликаты если есть
                        actions.removeAll { $0.actorId == actors[0].id && $0.type == action.type }
                        actions.append(action)
                        actionCounter += 1
                    }
                }

                // Действие второго актёра
                if match.numberOfRanges > 2 {
                    let nsRange = match.range(at: 2)
                    // Проверяем что диапазон валидный
                    guard nsRange.location != NSNotFound,
                          nsRange.location + nsRange.length <= (text as NSString).length,
                          nsRange.length > 0,
                          let secondRange = Range(nsRange, in: text) else { continue }

                    // Проверяем границы диапазона
                    guard secondRange.lowerBound >= text.startIndex,
                          secondRange.upperBound <= text.endIndex,
                          secondRange.lowerBound < secondRange.upperBound else { continue }

                    let secondActionText = String(text[secondRange])

                    if let action = parseSimpleAction(from: secondActionText, actorId: actors[1].id, actionId: "action_\(actionCounter)") {
                        // Удаляем дубликаты если есть
                        actions.removeAll { $0.actorId == actors[1].id && $0.type == action.type }
                        actions.append(action)
                        actionCounter += 1
                    }
                }
            }
        }

        return actions
    }

    /// Определяет, во множественном ли числе глагол в тексте
    /// - Parameters:
    ///   - text: Текст для проверки
    ///   - pattern: Паттерн, который был найден (для определения позиции глагола)
    /// - Returns: true, если глагол во множественном числе
    private func isPluralVerbForm(in text: String, pattern: String) -> Bool {
        let lowercasedText = text.lowercased()

        // Глаголы во множественном числе (3-е лицо множественного числа)
        // Проверяем только целые слова, чтобы избежать ложных срабатываний
        let pluralVerbForms = ["идут", "подходят", "бегут", "поворачивают", "проходят"]

        // Разбиваем текст на слова и проверяем каждое
        let words = lowercasedText.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        for word in words {
            if pluralVerbForms.contains(word) {
                print("🔍 [EXTRACT_ACTIONS] Найден глагол во множественном числе: '\(word)'")
                return true
            }
        }

        // Дополнительная проверка: ищем в найденном паттерне
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let matches = regex.matches(in: lowercasedText, range: NSRange(lowercasedText.startIndex..., in: lowercasedText))
            for match in matches {
                // Извлекаем найденный текст
                let matchRange = match.range
                guard matchRange.location != NSNotFound,
                      matchRange.location + matchRange.length <= (lowercasedText as NSString).length,
                      matchRange.length > 0,
                      let textRange = Range(matchRange, in: lowercasedText),
                      textRange.lowerBound >= lowercasedText.startIndex,
                      textRange.upperBound <= lowercasedText.endIndex,
                      textRange.lowerBound < textRange.upperBound else { continue }

                let matchedText = String(lowercasedText[textRange])
                let matchedWords = matchedText.components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { !$0.isEmpty }

                // Проверяем множественное число глаголов в найденном тексте
                for word in matchedWords {
                    if pluralVerbForms.contains(word) {
                        print("🔍 [EXTRACT_ACTIONS] Найден глагол во множественном числе в паттерне: '\(word)'")
                        return true
                    }
                }
            }
        }

        return false
    }

    private func parseSimpleAction(from text: String, actorId: String, actionId: String) -> SceneAction? {
        let lowercased = text.lowercased()

        // Ищем тип действия
        var actionType: SceneAction.ActionType?
        for (keyword, type) in KeywordsMapping.actionKeywords {
            if lowercased.contains(keyword) {
                actionType = type
                break
            }
        }

        guard let type = actionType else { return nil }

        // Ищем направление
        var direction: SceneAction.Direction?
        for (keyword, dir) in KeywordsMapping.directionKeywords {
            if lowercased.contains(keyword) {
                direction = dir
                break
            }
        }

        // Модификатор
        let modifier = extractModifier(from: lowercased)

        return SceneAction(
            id: actionId,
            actorId: actorId,
            type: type,
            target: nil,
            direction: direction,
            modifier: modifier
        )
    }
}

// MARK: - Extension for Debug

extension SceneScript {
    var debugDescription: String {
        var result = "=== SceneScript ===\n"
        result += "Original: \(originalDescription)\n\n"

        result += "Actors (\(actors.count)):\n"
        for actor in actors {
            result += "  - \(actor.id): \(actor.type.rawValue)"
            if let name = actor.name { result += " (\(name))" }
            result += "\n"
        }

        result += "\nObjects (\(objects.count)):\n"
        for object in objects {
            result += "  - \(object.id): \(object.type.rawValue) at \(object.relativePosition.rawValue)\n"
        }

        result += "\nActions (\(actions.count)):\n"
        for action in actions {
            result += "  - \(action.id): \(action.actorId) \(action.type.rawValue)"
            if let dir = action.direction { result += " -> \(dir.rawValue)" }
            if let target = action.target { result += " to \(target)" }
            if let mod = action.modifier { result += " (\(mod.rawValue))" }
            result += "\n"
        }

        result += "\nSpatial Relations (\(spatialRelations.count)):\n"
        for relation in spatialRelations {
            result += "  - \(relation.subject) \(relation.relation.rawValue) \(relation.object)\n"
        }

        return result
    }
}
