//
//  LLMParserService.swift
//  shafinMultitool
//
//  Created on 28.01.2026.
//  Rewritten on 13.03.2026 — реальная интеграция llama.cpp
//

import Foundation

/// Сервис для парсинга сценариев через локальную LLM (llama.cpp + Qwen2-0.5B)
/// Используется как fallback когда rule-based парсер имеет низкую confidence
final class LLMParserService: LocalScenePlanProvider {

    static let shared = LLMParserService()
    private static let generationTokenBudgets: [Int32] = [512, 768]
    private static let genericRoleNames: Set<String> = [
        "мужчина", "женщина", "парень", "девушка", "человек", "персонаж",
        "актёр", "актер", "актриса", "герой", "героиня", "он", "она", "они"
    ]
    private let lemmatizer = Lemmatizer()
    private lazy var markedObjectMatcher = MarkedObjectMatcher(lemmatizer: lemmatizer)
    private let planCompiler = ScenePlanCompiler()
    private let stateLock = NSLock()
    private var loadingTask: Task<Void, Never>?

    /// LlamaContext (actor) — загружается лениво при первом использовании
    private var llamaContext: LlamaContext?

    /// Статус загрузки модели
    private(set) var loadingState: LoadingState = .notLoaded

    /// Проверяет, доступна ли LLM модель
    var isAvailable: Bool {
        withStateLock { loadingState == .loaded }
    }

    private init() {
        // Модель загружается лениво при первом вызове parse()
    }

    // MARK: - Loading State

    enum LoadingState: Equatable {
        case notLoaded
        case loading
        case loaded
        case failed(String)
    }

    // MARK: - Model Loading

    /// Загружает модель асинхронно
    func loadModelIfNeeded() async {
        if let task = withStateLock({ loadingTask }) {
            await task.value
            return
        }
        if withStateLock({ loadingState == .loaded }) {
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            if self.withStateLock({ self.loadingState == .loaded }) {
                self.clearLoadingTask()
                return
            }

            self.withStateLock {
                self.loadingState = .loading
            }
            print("🤖 [LLM] Начинаю загрузку модели...")

            guard let modelPath = Bundle.main.path(forResource: "qwen2.5-1.5b-instruct.Q4_K_M", ofType: "gguf") else {
                let error = "GGUF модель не найдена в бандле приложения"
                print("❌ [LLM] \(error)")
                self.withStateLock {
                    self.loadingState = .failed(error)
                }
                self.clearLoadingTask()
                return
            }

            print("🤖 [LLM] Путь к модели: \(modelPath)")

            do {
                let context = try LlamaContext.create(
                    modelPath: modelPath,
                    temperature: 0.1,
                    grammarStr: Self.scenePlanIRGrammar
                )
                self.withStateLock {
                    self.llamaContext = context
                    self.loadingState = .loaded
                }

                let info = await context.modelInfo()
                print("✅ [LLM] Модель загружена: \(info)")
            } catch {
                let errorMsg = "Ошибка загрузки модели: \(error.localizedDescription)"
                print("❌ [LLM] \(errorMsg)")
                self.withStateLock {
                    self.loadingState = .failed(errorMsg)
                }
            }
            self.clearLoadingTask()
        }

        withStateLock {
            loadingTask = task
        }
        await task.value
    }

    // MARK: - Public API

    /// Парсит описание сцены через LLM (async)
    /// - Parameters:
    ///   - description: Текстовое описание сцены
    ///   - markedObjects: Размеченные объекты для контекста
    /// - Returns: Распарсенный SceneScript или nil если не удалось
    func parseAsync(_ description: String, markedObjects: [MarkedObject] = [], state: SceneChunkState? = nil) async -> SceneScript? {
        let anchors = SourceAnchorBundle.empty
        guard let providerResult = await generatePlanAsync(
            description: description,
            markedObjects: markedObjects,
            anchors: anchors,
            state: state
        ) else {
            return nil
        }
        return try? planCompiler.compile(plan: providerResult.plan, originalDescription: description)
    }

    func generatePlanAsync(
        description: String,
        markedObjects: [MarkedObject] = [],
        anchors: SourceAnchorBundle,
        state: SceneChunkState? = nil
    ) async -> ScenePlanProviderResult? {
        // Загружаем модель если ещё не загружена
        await loadModelIfNeeded()

        guard let context = withStateLock({ llamaContext }), isAvailable else {
            print("⚠️ [LLM] Модель не доступна, пропускаем LLM парсинг")
            return nil
        }

        print("🤖 [LLM] Начало LLM парсинга для: '\(description)'")
        let prompt = buildPrompt(description: description, markedObjects: markedObjects, anchors: anchors, state: state)

        for (attemptIndex, maxTokens) in Self.generationTokenBudgets.enumerated() {
            let attemptStart = CFAbsoluteTimeGetCurrent()
            let attemptSuffix = Self.generationTokenBudgets.count > 1
                ? " [попытка \(attemptIndex + 1)/\(Self.generationTokenBudgets.count), maxTokens=\(maxTokens)]"
                : ""

            // Генерируем ответ через llama.cpp
            let generatedText = await context.generate(prompt: prompt, maxTokens: maxTokens)

            let elapsed = CFAbsoluteTimeGetCurrent() - attemptStart
            print("🤖 [LLM] Генерация\(attemptSuffix) заняла: \(String(format: "%.2f", elapsed)) сек")
            print("🤖 [LLM] Ответ модели\(attemptSuffix):\n\(generatedText)")

            // Парсим JSON из ответа
            if let planResult = parsePlanFromResponse(
                generatedText,
                description: description,
                markedObjects: markedObjects,
                anchors: anchors
            ) {
                print("✅ [LLM] ScenePlanIR успешно извлечён из ответа LLM")
                return planResult
            }

            if attemptIndex < Self.generationTokenBudgets.count - 1 {
                let nextBudget = Self.generationTokenBudgets[attemptIndex + 1]
                print("⚠️ [LLM] Ответ не удалось распарсить, повторяем генерацию с maxTokens=\(nextBudget)")
            }
        }

        print("❌ [LLM] Не удалось извлечь SceneScript из ответа")
        return nil
    }

    /// Синхронная обёртка (для обратной совместимости)
    func parse(_ description: String, markedObjects: [MarkedObject] = [], state: SceneChunkState? = nil) -> SceneScript? {
        let anchors = SourceAnchorBundle.empty
        guard let providerResult = generatePlan(
            description: description,
            markedObjects: markedObjects,
            anchors: anchors,
            state: state
        ) else {
            return nil
        }
        return try? planCompiler.compile(plan: providerResult.plan, originalDescription: description)
    }

    func generatePlan(
        description: String,
        markedObjects: [MarkedObject] = [],
        anchors: SourceAnchorBundle,
        state: SceneChunkState? = nil
    ) -> ScenePlanProviderResult? {
        if Thread.isMainThread {
            print("⚠️ [LLM] Sync generatePlan вызван с main thread; пропускаем, чтобы не блокировать UI")
            return nil
        }
        guard isAvailable else {
            print("⚠️ [LLM] Модель не загружена, пропускаем LLM planner")
            return nil
        }

        var result: ScenePlanProviderResult?
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            result = await generatePlanAsync(
                description: description,
                markedObjects: markedObjects,
                anchors: anchors,
                state: state
            )
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }

    // MARK: - Prompt Building

    /// Формирует промпт для LLM
    private func buildPrompt(description: String, markedObjects: [MarkedObject], anchors: SourceAnchorBundle, state: SceneChunkState?) -> String {
        var stateContext = ""
        if let state = state {
            let actors = state.knownActors.map { "\($0.key) (id: \($0.value))" }.joined(separator: ", ")
            stateContext = "Предыдущее состояние сцены:\n"
            if let loc = state.locationName { stateContext += "Локация: \(loc)\n" }
            if !actors.isEmpty { stateContext += "Известные персонажи (сохраняй их id): \(actors)\n" }
            stateContext += "\n"
        }
        let markedObjectsContext = buildMarkedObjectsContext(markedObjects)
        let anchorContext = buildAnchorContext(anchors)

        return """
        <|im_start|>system
        Ты planner мизансцен для кинопроизводства. Преобразуй чанк русского описания сцены в валидный JSON ScenePlanIR.
        КРИТИЧЕСКИ ВАЖНО:
        - лучше недоразметить, чем додумать лишнее
        - не выдумывай объекты, действия и отношения, которых нет в тексте
        - каждый beat = одновременные действия актёров в одной микрофазе
        - финальный SceneScript ты НЕ генерируешь
        - actor refs должны быть символическими: "first", "second", "third"
        - unmarked objects должны использовать refs вида "object_slot_1", "object_slot_2"
        - marked objects должны использовать exact refs вида "object_marked_xxxxxxxx"
        - если действие unsupported, сохраняй его как type="described_action" с fallbackText/sourceText
        - выводи ТОЛЬКО валидный JSON ScenePlanIR, без пояснений
        <|im_end|>
        <|im_start|>user
        \(stateContext)\(markedObjectsContext)\(anchorContext)SOURCE:
        \(description)<|im_end|>
        <|im_start|>assistant
        """
    }

    private func buildMarkedObjectsContext(_ markedObjects: [MarkedObject]) -> String {
        guard !markedObjects.isEmpty else {
            return "MARKED OBJECTS:\n- none\n\n"
        }

        let lines = markedObjects.map { marker in
            let id = marker.canonicalMarkedObjectID
            return "- id=\(id), name=\(marker.name.lowercased()), type=\(marker.type.rawValue)"
        }.joined(separator: "\n")

        let exampleId = markedObjects[0].canonicalMarkedObjectID
        let exampleName = markedObjects[0].name.lowercased()

        return """
        MARKED OBJECTS:
        \(lines)

        RULES FOR MARKED OBJECTS:
        - if source mentions a marked object by name or lemma, reuse its exact id
        - do not invent a duplicate object for the same real-world item
        - example: if source mentions "\(exampleName)", output target "\(exampleId)"

        """
    }

    private func buildAnchorContext(_ anchors: SourceAnchorBundle) -> String {
        let ordinals = anchors.ordinalMentions.joined(separator: ", ")
        let mentioned = anchors.mentionedMarkedObjects.joined(separator: ", ")
        let phases = anchors.phaseCues.joined(separator: ", ")
        let unsupported = anchors.unsupportedActionFlags.joined(separator: ", ")

        return """
        ANCHOR BUNDLE:
        - actor_count_hint=\(anchors.actorCountHint)
        - ordinal_mentions=\(ordinals.isEmpty ? "none" : ordinals)
        - mentioned_marked_objects=\(mentioned.isEmpty ? "none" : mentioned)
        - phase_cues=\(phases.isEmpty ? "none" : phases)
        - unsupported_action_flags=\(unsupported.isEmpty ? "none" : unsupported)
        - same_type_marker_conflict=\(anchors.sameTypeMarkerConflict ? "true" : "false")

        """
    }


    // MARK: - JSON Parsing

    /// Парсит JSON (ScenePlanIR) из ответа LLM. В transitional режиме
    /// допускает legacy SceneScript и конвертирует его во внутренний план.
    private func parsePlanFromResponse(
        _ response: String,
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle
    ) -> ScenePlanProviderResult? {
        guard let extractedJSON = extractJSONPayload(from: response) else {
            print("❌ [LLM] Не найден JSON в ответе")
            return nil
        }

        let candidates = makeJSONCandidates(from: extractedJSON)

        for (index, candidate) in candidates.enumerated() {
            print("🔧 [LLM] JSON после починки [вариант \(index + 1)/\(candidates.count)]: \(candidate.prefix(200))...")

            do {
                let decoded = try decodeScenePlan(from: candidate)
                let plan = repairScenePlanIR(decoded, description: description, markedObjects: markedObjects, anchors: anchors)
                print("✅ [LLM] Декодирован ScenePlanIR: actors=\(plan.actors.count), objects=\(plan.objects.count), beats=\(plan.beats.count)")
                return ScenePlanProviderResult(plan: plan, usedLegacySceneScriptBridge: false)
            } catch {
                print("⚠️ [LLM] ScenePlanIR decode failed [вариант \(index + 1)/\(candidates.count)]: \(error)")
            }

            do {
                let decoded = try decodeSceneScript(from: candidate, description: description)
                let script = repairSceneScript(decoded, description: description, markedObjects: markedObjects)
                let bridgedPlan = makePlanIR(from: script, markedObjects: markedObjects, anchors: anchors)
                print("✅ [LLM] Legacy SceneScript bridged to ScenePlanIR")
                return ScenePlanProviderResult(plan: bridgedPlan, usedLegacySceneScriptBridge: true)
            } catch {
                print("❌ [LLM] Legacy SceneScript decode failed [вариант \(index + 1)/\(candidates.count)]: \(error)")
                print("   JSON: \(candidate.prefix(300))")
            }
        }

        return nil
    }

    private func extractJSONPayload(from response: String) -> String? {
        var text = response

        text = text.replacingOccurrences(of: "<|im_end|>", with: "")
        text = text.replacingOccurrences(of: "<|im_start|>", with: "")
        text = text.replacingOccurrences(of: "```json", with: "")
        text = text.replacingOccurrences(of: "```", with: "")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let startIndex = text.firstIndex(of: "{") else {
            return nil
        }

        if let endIndex = text.lastIndex(of: "}") {
            return String(text[startIndex...endIndex])
        }

        return String(text[startIndex...])
    }

    private func makeJSONCandidates(from input: String) -> [String] {
        let repaired = repairJSON(input)
        let balanced = balanceBrackets(repaired)
        let trimmed = trimToLastCompleteBoundary(repaired)
        let trimmedBalanced = balanceBrackets(trimmed)

        var seen = Set<String>()
        return [balanced, trimmedBalanced].filter { seen.insert($0).inserted }
    }

    /// Если модель оборвалась посреди нового поля, отбрасываем хвост до последней
    /// завершённой структуры/элемента и уже после этого балансируем скобки.
    private func trimToLastCompleteBoundary(_ input: String) -> String {
        var isInsideString = false
        var isEscaping = false
        var lastSafeEnd: String.Index?

        for index in input.indices {
            let character = input[index]

            if isInsideString {
                if isEscaping {
                    isEscaping = false
                    continue
                }

                if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    isInsideString = false
                }
                continue
            }

            switch character {
            case "\"":
                isInsideString = true
            case ",":
                lastSafeEnd = index
            case "}", "]":
                lastSafeEnd = input.index(after: index)
            default:
                break
            }
        }

        guard let lastSafeEnd else { return input }
        return String(input[..<lastSafeEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeScenePlan(from text: String) throws -> ScenePlanIR {
        guard let data = text.data(using: .utf8) else {
            throw NSError(domain: "LLMParserService", code: 11, userInfo: [NSLocalizedDescriptionKey: "Не удалось конвертировать ScenePlanIR в Data"])
        }

        guard var jsonObj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "LLMParserService", code: 12, userInfo: [NSLocalizedDescriptionKey: "Корневой JSON plan не является объектом"])
        }

        if jsonObj["actors"] == nil {
            jsonObj["actors"] = []
        }
        if jsonObj["objects"] == nil {
            jsonObj["objects"] = []
        }
        if jsonObj["beats"] == nil {
            jsonObj["beats"] = []
        }
        if jsonObj["spatialRelations"] == nil {
            jsonObj["spatialRelations"] = []
        }
        if var objects = jsonObj["objects"] as? [[String: Any]] {
            for index in objects.indices {
                if objects[index]["relativePosition"] == nil {
                    objects[index]["relativePosition"] = "unknown"
                }
                if objects[index]["ref"] == nil {
                    if let markedObjectID = objects[index]["markedObjectID"] as? String, markedObjectID.hasPrefix("object_marked_") {
                        objects[index]["ref"] = markedObjectID
                    } else {
                        objects[index]["ref"] = "object_slot_\(index + 1)"
                    }
                }
            }
            jsonObj["objects"] = objects
        }
        if var actors = jsonObj["actors"] as? [[String: Any]] {
            let refs = ["first", "second", "third"]
            for index in actors.indices where actors[index]["ref"] == nil {
                actors[index]["ref"] = index < refs.count ? refs[index] : "actor_ref_\(index + 1)"
            }
            jsonObj["actors"] = actors
        }
        if var beats = jsonObj["beats"] as? [[String: Any]] {
            for beatIndex in beats.indices {
                if beats[beatIndex]["ref"] == nil {
                    beats[beatIndex]["ref"] = "beat_\(beatIndex + 1)"
                }
            }
            jsonObj["beats"] = beats
        }
        var referenceBindings = (jsonObj["referenceBindings"] as? [String: Any]) ?? [:]
        if referenceBindings["actorBindings"] == nil {
            referenceBindings["actorBindings"] = [:]
        }
        if referenceBindings["markedObjectIDs"] == nil {
            referenceBindings["markedObjectIDs"] = []
        }
        if referenceBindings["aliasToObjectRef"] == nil {
            referenceBindings["aliasToObjectRef"] = [:]
        }
        jsonObj["referenceBindings"] = referenceBindings

        let fixedData = try JSONSerialization.data(withJSONObject: jsonObj)
        return try JSONDecoder().decode(ScenePlanIR.self, from: fixedData)
    }

    private func decodeSceneScript(from text: String, description: String) throws -> SceneScript {
        guard let data = text.data(using: .utf8) else {
            throw NSError(domain: "LLMParserService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не удалось конвертировать JSON в Data"])
        }

        guard var jsonObj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "LLMParserService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Корневой JSON не является объектом"])
        }

        jsonObj["originalDescription"] = description

        if jsonObj["spatialRelations"] == nil {
            jsonObj["spatialRelations"] = []
        }

        // Обратная совместимость: если модель выдала старый формат с "actions",
        // конвертируем в "beats" (один beat со всеми действиями)
        if jsonObj["beats"] == nil, let actions = jsonObj["actions"] as? [[String: Any]], !actions.isEmpty {
            print("🔧 [LLM] Конвертация legacy actions → beats (до переобучения модели)")
            jsonObj["beats"] = [
                ["id": "beat_1", "actions": actions]
            ]
            jsonObj.removeValue(forKey: "actions")
        }

        // Пост-обработка beats: автогенерация id для action, маппинг speed→modifier
        if var beats = jsonObj["beats"] as? [[String: Any]] {
            var actionCounter = 1
            for i in 0..<beats.count {
                if var actions = beats[i]["actions"] as? [[String: Any]] {
                    for j in 0..<actions.count {
                        // Автогенерация id если отсутствует
                        if actions[j]["id"] == nil {
                            actions[j]["id"] = "action_\(actionCounter)"
                        }
                        actionCounter += 1

                        // Маппинг "speed" → "modifier" (GBNF/датасет = speed, Swift = modifier)
                        if let speed = actions[j]["speed"] {
                            actions[j]["modifier"] = speed
                            actions[j].removeValue(forKey: "speed")
                        }
                    }
                    beats[i]["actions"] = actions
                }
            }
            jsonObj["beats"] = beats
        }

        let fixedData = try JSONSerialization.data(withJSONObject: jsonObj)
        return try JSONDecoder().decode(SceneScript.self, from: fixedData)
    }

    private func repairScenePlanIR(
        _ plan: ScenePlanIR,
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle
    ) -> ScenePlanIR {
        let mentionedMarkers = findMentionedMarkers(in: description.lowercased(), markedObjects: markedObjects)
        var repaired = plan

        repaired.actors = normalizePlanActors(repaired.actors)
        repaired.objects = normalizePlanObjects(repaired.objects, mentionedMarkers: mentionedMarkers)
        repaired.beats = normalizePlanBeats(repaired.beats, anchors: anchors)

        let markedObjectIDs = repaired.objects.compactMap { object -> String? in
            if object.ref.hasPrefix("object_marked_") { return object.ref }
            if let markedObjectID = object.markedObjectID, markedObjectID.hasPrefix("object_marked_") { return markedObjectID }
            return nil
        }
        repaired.referenceBindings.markedObjectIDs = Array(Set(markedObjectIDs)).sorted()
        repaired.referenceBindings.actorBindings = repaired.referenceBindings.actorBindings.merging(
            Dictionary(uniqueKeysWithValues: repaired.actors.enumerated().map { index, actor in
                let binding = index == 0 ? "actor_1" : "actor_\(index + 1)"
                return (actor.ref, binding)
            })
        ) { _, new in new }

        return repaired
    }

    private func normalizePlanActors(_ actors: [ScenePlanIR.Actor]) -> [ScenePlanIR.Actor] {
        let canonicalRefs = ["first", "second", "third"]
        return actors.enumerated().map { index, actor in
            var actor = actor
            if index < canonicalRefs.count {
                actor.ref = canonicalRefs[index]
            } else if actor.ref.isEmpty {
                actor.ref = "actor_ref_\(index + 1)"
            }
            if let name = actor.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               Self.genericRoleNames.contains(name) {
                actor.name = nil
            }
            return actor
        }
    }

    private func normalizePlanObjects(
        _ objects: [ScenePlanIR.Object],
        mentionedMarkers: [MarkedObject]
    ) -> [ScenePlanIR.Object] {
        var normalized = objects.enumerated().map { index, object in
            var object = object
            if let markedObjectID = object.markedObjectID, markedObjectID.hasPrefix("object_marked_") {
                object.ref = markedObjectID
            } else if object.ref.isEmpty {
                object.ref = "object_slot_\(index + 1)"
            }
            return object
        }

        for marker in mentionedMarkers {
            let objectID = marker.canonicalMarkedObjectID
            if !normalized.contains(where: { $0.ref == objectID || $0.markedObjectID == objectID }) {
                normalized.append(
                    ScenePlanIR.Object(
                        ref: objectID,
                        type: marker.type,
                        relativePosition: .unknown,
                        name: marker.name,
                        markedObjectID: objectID
                    )
                )
            }
        }

        return normalized
    }

    private func normalizePlanBeats(_ beats: [ScenePlanIR.Beat], anchors: SourceAnchorBundle) -> [ScenePlanIR.Beat] {
        beats.enumerated().map { beatIndex, beat in
            var beat = beat
            if beat.ref.isEmpty {
                beat.ref = "beat_\(beatIndex + 1)"
            }
            if beat.phase == nil {
                beat.phase = anchors.phaseCues.first
            }
            beat.actions = beat.actions.enumerated().map { _, action in
                var action = action
                if action.resultingPose == nil {
                    action.resultingPose = defaultPose(for: action.type)
                }
                return action
            }
            return beat
        }
    }

    private func makePlanIR(
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
                        targetRef: planTargetRef(for: action.target, actorRefMap: actorRefMap, objectRefMap: objectRefMap),
                        direction: action.direction,
                        modifier: action.modifier,
                        resultingPose: action.resultingPose,
                        holdingObjectRef: objectRefMap[action.holdingObject ?? ""],
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
                subjectRef: planTargetRef(for: relation.subject, actorRefMap: actorRefMap, objectRefMap: objectRefMap) ?? relation.subject,
                relation: relation.relation,
                objectRef: planTargetRef(for: relation.object, actorRefMap: actorRefMap, objectRefMap: objectRefMap) ?? relation.object
            )
        }

        let markedObjectIDs = objects.compactMap { $0.markedObjectID ?? ($0.ref.hasPrefix("object_marked_") ? $0.ref : nil) }
        let aliasBindings = Dictionary(uniqueKeysWithValues: markedObjects.map { marker in
            (marker.name.lowercased(), marker.canonicalMarkedObjectID)
        })

        return repairScenePlanIR(
            ScenePlanIR(
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
            ),
            description: script.originalDescription,
            markedObjects: markedObjects,
            anchors: anchors
        )
    }

    private func planTargetRef(
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

    private func repairSceneScript(_ script: SceneScript, description: String, markedObjects: [MarkedObject]) -> SceneScript {
        var repaired = script
        let lowercasedDescription = description.lowercased()
        let mentionedMarkers = findMentionedMarkers(in: lowercasedDescription, markedObjects: markedObjects)

        repaired = normalizeActorNames(in: repaired)
        repaired = ensurePoses(in: repaired)
        repaired = injectMarkedObjectsIfNeeded(in: repaired, mentionedMarkers: mentionedMarkers)
        repaired = repairMotionSemantics(in: repaired, description: lowercasedDescription, mentionedMarkers: mentionedMarkers)

        return canonicalSGv7SceneScript(
            actors: repaired.actors,
            objects: repaired.objects,
            beats: repaired.beats,
            spatialRelations: repaired.spatialRelations,
            originalDescription: repaired.originalDescription
        )
    }

    private func canonicalSGv7SceneScript(
        actors: [SceneActor],
        objects: [SceneObject],
        beats: [SceneBeat],
        spatialRelations: [SpatialRelation],
        originalDescription: String
    ) -> SceneScript {
        SceneScript(
            sceneHeading: nil,
            locationName: nil,
            interiorExterior: nil,
            timeOfDay: nil,
            actors: actors,
            objects: objects,
            beats: beats,
            spatialRelations: spatialRelations,
            originalDescription: originalDescription
        )
    }

    private func normalizeActorNames(in script: SceneScript) -> SceneScript {
        let actors = script.actors.map { actor in
            var actor = actor
            if let name = actor.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               Self.genericRoleNames.contains(name) {
                actor.name = nil
            }
            return actor
        }

        return canonicalSGv7SceneScript(
            actors: actors,
            objects: script.objects,
            beats: script.beats,
            spatialRelations: script.spatialRelations,
            originalDescription: script.originalDescription
        )
    }

    private func findMentionedMarkers(in description: String, markedObjects: [MarkedObject]) -> [MarkedObject] {
        guard !description.isEmpty, !markedObjects.isEmpty else { return [] }

        let references = markedObjectMatcher.findMarkedObjectReferences(in: description, markedObjects: markedObjects)
        var orderedMarkers: [MarkedObject] = []
        var seenIds = Set<UUID>()

        for reference in references {
            guard seenIds.insert(reference.markerId).inserted,
                  let marker = markedObjects.first(where: { $0.id == reference.markerId }) else { continue }
            orderedMarkers.append(marker)
        }

        if !orderedMarkers.isEmpty {
            return orderedMarkers
        }

        return markedObjects.filter { marker in
            let markerName = marker.name.lowercased()
            return lemmatizer.textContainsKeyword(description, keyword: markerName) || description.contains(markerName)
        }
    }

    private func ensurePoses(in script: SceneScript) -> SceneScript {
        let beats = script.beats.map { beat in
            let actions = beat.actions.map { action -> SceneAction in
                var action = action
                if action.resultingPose == nil {
                    action.resultingPose = defaultPose(for: action.type)
                }
                return action
            }
            return SceneBeat(id: beat.id, actions: actions, camera: beat.camera, minDuration: beat.minDuration)
        }

        return canonicalSGv7SceneScript(
            actors: script.actors,
            objects: script.objects,
            beats: beats,
            spatialRelations: script.spatialRelations,
            originalDescription: script.originalDescription
        )
    }

    private func injectMarkedObjectsIfNeeded(in script: SceneScript, mentionedMarkers: [MarkedObject]) -> SceneScript {
        guard !mentionedMarkers.isEmpty else { return script }

        var objects = script.objects
        for marker in mentionedMarkers {
            let objectId = marker.canonicalMarkedObjectID
            if !objects.contains(where: { $0.id == objectId }) {
                print("🔧 [LLM] Восстанавливаем размеченный объект '\(marker.name)' как \(objectId)")
                objects.append(SceneObject(
                    id: objectId,
                    type: marker.type,
                    name: marker.name,
                    detectedPosition: marker.worldPosition,
                    relativePosition: .unknown
                ))
            }
        }

        return canonicalSGv7SceneScript(
            actors: script.actors,
            objects: objects,
            beats: script.beats,
            spatialRelations: script.spatialRelations,
            originalDescription: script.originalDescription
        )
    }

    private func repairMotionSemantics(in script: SceneScript, description: String, mentionedMarkers: [MarkedObject]) -> SceneScript {
        guard !script.beats.isEmpty else { return script }

        let actorIds = script.actors.map(\.id)
        let primaryMarkedObjectId = mentionedMarkers.first.map(\.canonicalMarkedObjectID)
        let hasTowardEachOtherPhrase = description.contains("навстречу") || description.contains("друг к другу") || description.contains("друг на друга")
        let hasPassByPhrase = description.contains("мимо")
        let secondActorRuns = description.contains("второй начинает бежать") || description.contains("вторая начинает бежать")
        let secondActorRunUpgrade = secondActorRuns && script.actors.count >= 2
            ? selectSecondActorRunUpgrade(in: script.beats, secondActorId: actorIds.dropFirst().first)
            : nil

        let beats = script.beats.enumerated().map { beatIndex, beat in
            let actions = beat.actions.enumerated().map { actionIndex, originalAction -> SceneAction in
                var action = originalAction

                if let markedObjectId = primaryMarkedObjectId,
                   action.target == nil,
                   mentionedMarkers.count == 1,
                   ([SceneAction.ActionType.passBy, .approach, .stop, .stand].contains(action.type) ||
                    (action.type == .walk && hasPassByPhrase)) {
                    action.target = markedObjectId
                }

                if hasTowardEachOtherPhrase,
                   script.actors.count == 2,
                   action.type == .walk || action.type == .run,
                   actorIds.contains(action.actorId),
                   action.direction == nil {
                    action.direction = .towardEachOther
                    if action.target == nil {
                        action.target = action.actorId == actorIds.first ? actorIds.last : actorIds.first
                    }
                }

                if let secondActorRunUpgrade,
                   beatIndex == secondActorRunUpgrade.beatIndex,
                   actionIndex == secondActorRunUpgrade.actionIndex {
                    print("🔧 [LLM] Усиливаем семантику: второй актёр начинает бежать")
                    if secondActorRunUpgrade.shouldPromoteToRun {
                        action.type = .run
                        action.resultingPose = .running
                    } else {
                        action.modifier = .quickly
                        if action.resultingPose == .standing || action.resultingPose == nil {
                            action.resultingPose = defaultPose(for: action.type)
                        }
                    }
                }

                if hasPassByPhrase,
                   primaryMarkedObjectId != nil,
                   action.type == .walk,
                   action.target == primaryMarkedObjectId {
                    action.type = .passBy
                }

                return action
            }
            return SceneBeat(id: beat.id, actions: actions, camera: beat.camera, minDuration: beat.minDuration)
        }

        return canonicalSGv7SceneScript(
            actors: script.actors,
            objects: script.objects,
            beats: beats,
            spatialRelations: script.spatialRelations,
            originalDescription: script.originalDescription
        )
    }

    private func selectSecondActorRunUpgrade(in beats: [SceneBeat], secondActorId: String?) -> (beatIndex: Int, actionIndex: Int, shouldPromoteToRun: Bool)? {
        guard let secondActorId else { return nil }

        var latestWalk: (Int, Int)?
        var latestMovableNonWalk: (Int, Int)?

        for (beatIndex, beat) in beats.enumerated() {
            for (actionIndex, action) in beat.actions.enumerated() where action.actorId == secondActorId {
                switch action.type {
                case .walk:
                    latestWalk = (beatIndex, actionIndex)
                case .approach, .passBy:
                    latestMovableNonWalk = (beatIndex, actionIndex)
                default:
                    continue
                }
            }
        }

        if let latestWalk {
            return (latestWalk.0, latestWalk.1, true)
        }

        if let latestMovableNonWalk {
            return (latestMovableNonWalk.0, latestMovableNonWalk.1, false)
        }

        return nil
    }

    private func defaultPose(for type: SceneAction.ActionType) -> ActorPose {
        switch type {
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

    /// Исправляет типичные ошибки JSON от маленькой модели
    private func repairJSON(_ input: String) -> String {
        var json = input

        // Исправляем сломанные ключи вида: "spatialRelations[]: или spatialRelations[]:
        // Вариант 1: "key[]": → "key":  (закрывающая кавычка есть)
        // Вариант 2: "key[]:  → "key":  (закрывающей кавычки нет — типичная ошибка 0.5B)
        let brokenKeyPattern1 = try! NSRegularExpression(pattern: #""(\w+)\[\]"?\s*:"#)
        json = brokenKeyPattern1.stringByReplacingMatches(
            in: json,
            range: NSRange(json.startIndex..., in: json),
            withTemplate: #""$1":"#
        )

        // Исправляем ключи без кавычек: {key: -> {"key":
        // (но осторожно — не трогаем числа и строки в кавычках)
        let unquotedKeyPattern = try! NSRegularExpression(pattern: #"([{,])\s*(\w+)\s*:"#)
        json = unquotedKeyPattern.stringByReplacingMatches(
            in: json,
            range: NSRange(json.startIndex..., in: json),
            withTemplate: #"$1"$2":"#
        )

        // Убираем trailing commas перед ] и }
        json = json.replacingOccurrences(of: ",]", with: "]")
        json = json.replacingOccurrences(of: ",}", with: "}")
        let trailingCommaPattern = try! NSRegularExpression(pattern: #",\s*\]"#)
        json = trailingCommaPattern.stringByReplacingMatches(
            in: json,
            range: NSRange(json.startIndex..., in: json),
            withTemplate: "]"
        )
        let trailingCommaPattern2 = try! NSRegularExpression(pattern: #",\s*\}"#)
        json = trailingCommaPattern2.stringByReplacingMatches(
            in: json,
            range: NSRange(json.startIndex..., in: json),
            withTemplate: "}"
        )

        // Исправляем object-N -> object_N (модель иногда путает дефис с подчёркиванием)
        json = json.replacingOccurrences(of: "\"object-", with: "\"object_")
        json = json.replacingOccurrences(of: "\"actor-", with: "\"actor_")
        json = json.replacingOccurrences(of: "\"action-", with: "\"action_")
        json = json.replacingOccurrences(of: "\"rel-", with: "\"rel_")

        return json
    }

    /// Балансирует незакрытые [ и { скобки
    private func balanceBrackets(_ input: String) -> String {
        var json = input
        let openBrackets = json.filter { $0 == "[" }.count
        let closeBrackets = json.filter { $0 == "]" }.count
        let openBraces = json.filter { $0 == "{" }.count
        let closeBraces = json.filter { $0 == "}" }.count

        for _ in 0..<max(0, openBrackets - closeBrackets) { json += "]" }
        for _ in 0..<max(0, openBraces - closeBraces) { json += "}" }

        return json
    }

    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    private func clearLoadingTask() {
        withStateLock {
            loadingTask = nil
        }
    }

    // MARK: - GBNF Grammar

    /// GBNF-грамматика, описывающая внутренний ScenePlanIR.
    /// Финальный SceneScript собирается только через ScenePlanCompiler.
    static let scenePlanIRGrammar: String = {
        let lines = [
            #"root ::= "{" ws actors-field "," ws objects-field "," ws beats-field "," ws relations-field "," ws bindings-field ws "}""#,
            "",
            #"ws ::= ([ \t\n])*"#,
            "",
            #"actors-field ::= "\"actors\"" ws ":" ws "[" ws actor-list ws "]""#,
            #"actor-list ::= actor ("," ws actor)* | """#,
            "",
            #"objects-field ::= "\"objects\"" ws ":" ws "[" ws object-list ws "]""#,
            #"object-list ::= object ("," ws object)* | """#,
            "",
            #"beats-field ::= "\"beats\"" ws ":" ws "[" ws beat-list ws "]""#,
            #"beat-list ::= beat ("," ws beat)* | """#,
            "",
            #"relations-field ::= "\"spatialRelations\"" ws ":" ws "[" ws relation-list ws "]""#,
            #"relation-list ::= relation ("," ws relation)* | """#,
            "",
            #"bindings-field ::= "\"referenceBindings\"" ws ":" ws bindings-obj"#,
            #"bindings-obj ::= "{" ws "\"actorBindings\"" ws ":" ws bindings-map "," ws "\"markedObjectIDs\"" ws ":" ws "[" ws id-list ws "]" bindings-alias-map ws "}""#,
            #"bindings-alias-map ::= ("," ws "\"aliasToObjectRef\"" ws ":" ws bindings-map) | """#,
            #"bindings-map ::= "{" ws bindings-entry-list ws "}""#,
            #"bindings-entry-list ::= bindings-entry ("," ws bindings-entry)* | """#,
            #"bindings-entry ::= text-string ws ":" ws id-string"#,
            #"id-list ::= id-string ("," ws id-string)* | """#,
            "",
            #"beat ::= "{" ws "\"ref\"" ws ":" ws id-string beat-phase "," ws "\"actions\"" ws ":" ws "[" ws action-list ws "]" beat-duration ws "}""#,
            #"action-list ::= action ("," ws action)* | """#,
            #"beat-phase ::= ("," ws "\"phase\"" ws ":" ws text-string) | """#,
            #"beat-duration ::= ("," ws "\"minDuration\"" ws ":" ws number) | """#,
            "",
            #"actor ::= "{" ws "\"ref\"" ws ":" ws id-string "," ws "\"type\"" ws ":" ws actor-type actor-name ws "}""#,
            #"actor-type ::= "\"human\"" | "\"tiger\"" | "\"lion\"" | "\"dog\"" | "\"cat\"" | "\"bird\"" | "\"generic\"""#,
            #"actor-name ::= ("," ws "\"name\"" ws ":" ws text-string) | """#,
            "",
            #"object ::= "{" ws "\"ref\"" ws ":" ws id-string "," ws "\"type\"" ws ":" ws object-type "," ws "\"relativePosition\"" ws ":" ws relative-pos object-name object-marked-id ws "}""#,
            #"object-type ::= "\"table\"" | "\"chair\"" | "\"couch\"" | "\"bed\"" | "\"door\"" | "\"window\"" | "\"cabinet\"" | "\"shelf\"" | "\"tv\"" | "\"generic\"""#,
            #"object-name ::= ("," ws "\"name\"" ws ":" ws text-string) | """#,
            #"object-marked-id ::= ("," ws "\"markedObjectID\"" ws ":" ws id-string) | """#,
            #"relative-pos ::= "\"left\"" | "\"right\"" | "\"center\"" | "\"background\"" | "\"foreground\"" | "\"unknown\"""#,
            "",
            #"action ::= "{" ws "\"actorRef\"" ws ":" ws id-string "," ws "\"type\"" ws ":" ws action-type action-target action-direction action-speed "," ws "\"resultingPose\"" ws ":" ws pose-type action-holding action-dialogue action-fallback action-source ws "}""#,
            #"action-type ::= "\"walk\"" | "\"run\"" | "\"approach\"" | "\"pass_by\"" | "\"enter\"" | "\"exit\"" | "\"stand\"" | "\"sit\"" | "\"lie_down\"" | "\"stop\"" | "\"turn\"" | "\"crouch\"" | "\"look_at\"" | "\"pick_up\"" | "\"put_down\"" | "\"open\"" | "\"close\"" | "\"give\"" | "\"talk\"" | "\"described_action\"""#,
            #"action-target ::= ("," ws "\"targetRef\"" ws ":" ws id-string) | """#,
            #"action-direction ::= ("," ws "\"direction\"" ws ":" ws direction-type) | """#,
            #"direction-type ::= "\"left\"" | "\"right\"" | "\"forward\"" | "\"backward\"" | "\"toward_each_other\"" | "\"away_from_each_other\"" | "\"to_target\"""#,
            #"action-speed ::= ("," ws "\"modifier\"" ws ":" ws speed-type) | """#,
            #"speed-type ::= "\"slowly\"" | "\"quickly\"" | "\"carefully\"""#,
            #"pose-type ::= "\"standing\"" | "\"sitting\"" | "\"crouching\"" | "\"lying\"" | "\"walking\"" | "\"running\"""#,
            #"action-holding ::= ("," ws "\"holdingObjectRef\"" ws ":" ws id-string) | """#,
            #"action-dialogue ::= ("," ws "\"dialogue\"" ws ":" ws text-string) | """#,
            #"action-fallback ::= ("," ws "\"fallbackText\"" ws ":" ws text-string) | """#,
            #"action-source ::= ("," ws "\"sourceText\"" ws ":" ws text-string) | """#,
            "",
            #"relation ::= "{" ws "\"ref\"" ws ":" ws id-string "," ws "\"subjectRef\"" ws ":" ws id-string "," ws "\"relation\"" ws ":" ws relation-type "," ws "\"objectRef\"" ws ":" ws id-string ws "}""#,
            #"relation-type ::= "\"near\"" | "\"in_front_of\"" | "\"behind\"" | "\"left_of\"" | "\"right_of\"" | "\"between\"" | "\"pass_by\"" | "\"inside\"" | "\"outside\"""#,
            "",
            #"id-string ::= "\"" [a-zA-Z0-9_]+ "\"""#,
            #"text-string ::= "\"" ([^"\\] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]))* "\"""#,
            #"number ::= [0-9]+ ("." [0-9]+)?"#,
        ]
        return lines.joined(separator: "\n")
    }()
}
