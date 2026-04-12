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
final class LLMParserService {

    static let shared = LLMParserService()
    private static let generationTokenBudgets: [Int32] = [512, 768]
    private static let genericRoleNames: Set<String> = [
        "мужчина", "женщина", "парень", "девушка", "человек", "персонаж",
        "актёр", "актер", "актриса", "герой", "героиня", "он", "она", "они"
    ]
    private let lemmatizer = Lemmatizer()
    private lazy var markedObjectMatcher = MarkedObjectMatcher(lemmatizer: lemmatizer)

    /// LlamaContext (actor) — загружается лениво при первом использовании
    private var llamaContext: LlamaContext?

    /// Статус загрузки модели
    private(set) var loadingState: LoadingState = .notLoaded

    /// Последнее описание для вставки в originalDescription
    private var lastDescription: String = ""

    /// Проверяет, доступна ли LLM модель
    var isAvailable: Bool {
        loadingState == .loaded
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
        guard loadingState == .notLoaded else { return }

        loadingState = .loading
        print("🤖 [LLM] Начинаю загрузку модели...")

        guard let modelPath = Bundle.main.path(forResource: "qwen2.5-1.5b-instruct.Q4_K_M", ofType: "gguf") else {
            let error = "GGUF модель не найдена в бандле приложения"
            print("❌ [LLM] \(error)")
            loadingState = .failed(error)
            return
        }

        print("🤖 [LLM] Путь к модели: \(modelPath)")

        do {
            let context = try LlamaContext.create(
                modelPath: modelPath,
                temperature: 0.1,
                grammarStr: Self.sceneScriptGrammar
            )
            self.llamaContext = context
            self.loadingState = .loaded

            let info = await context.modelInfo()
            print("✅ [LLM] Модель загружена: \(info)")
        } catch {
            let errorMsg = "Ошибка загрузки модели: \(error.localizedDescription)"
            print("❌ [LLM] \(errorMsg)")
            loadingState = .failed(errorMsg)
        }
    }

    // MARK: - Public API

    /// Парсит описание сцены через LLM (async)
    /// - Parameters:
    ///   - description: Текстовое описание сцены
    ///   - markedObjects: Размеченные объекты для контекста
    /// - Returns: Распарсенный SceneScript или nil если не удалось
    func parseAsync(_ description: String, markedObjects: [MarkedObject] = [], state: SceneChunkState? = nil) async -> SceneScript? {
        // Загружаем модель если ещё не загружена
        await loadModelIfNeeded()

        guard let context = llamaContext, isAvailable else {
            print("⚠️ [LLM] Модель не доступна, пропускаем LLM парсинг")
            return nil
        }

        print("🤖 [LLM] Начало LLM парсинга для: '\(description)'")
        self.lastDescription = description
        let prompt = buildPrompt(description: description, markedObjects: markedObjects, state: state)

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
            if let script = parseJSONFromResponse(generatedText, description: description, markedObjects: markedObjects) {
                print("✅ [LLM] SceneScript успешно извлечён из ответа LLM")
                return script
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
        guard isAvailable else {
            print("⚠️ [LLM] Модель не загружена, пропускаем LLM парсинг")
            return nil
        }

        // Синхронный вызов — блокирует поток, использовать только в крайнем случае
        var result: SceneScript?
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            result = await parseAsync(description, markedObjects: markedObjects, state: state)
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }

    // MARK: - Prompt Building

    /// Формирует промпт для LLM
    private func buildPrompt(description: String, markedObjects: [MarkedObject], state: SceneChunkState?) -> String {
        var stateContext = ""
        if let state = state {
            let actors = state.knownActors.map { "\($0.key) (id: \($0.value))" }.joined(separator: ", ")
            stateContext = "Предыдущее состояние сцены:\n"
            if let loc = state.locationName { stateContext += "Локация: \(loc)\n" }
            if !actors.isEmpty { stateContext += "Известные персонажи (сохраняй их id): \(actors)\n" }
            stateContext += "\n"
        }
        let markedObjectsContext = buildMarkedObjectsContext(markedObjects)

        return """
        <|im_start|>system
        Ты парсер мизансцен для кинопроизводства. Преобразуй чанк русского описания сцены в валидный JSON SceneScript.
        КРИТИЧЕСКИ ВАЖНО:
        - лучше недоразметить, чем додумать лишнее
        - не выдумывай объекты, действия и отношения, которых нет в тексте
        - каждый beat = одновременные действия актёров в одной микрофазе
        - если в тексте явно сказано "идут навстречу друг другу", сохрани симметрию движения и используй direction="toward_each_other"
        - если сказано "второй начинает бежать", actor_2 должен получить type="run" или modifier="quickly", а не остаться обычным walk
        - если сказано "проходят мимо объекта", используй type="pass_by" и target этого объекта
        - actor.name заполняй только собственным именем; не используй "Мужчина", "Женщина", "Он", "Она"
        - если объект упомянут в тексте и есть среди MARKED OBJECTS, обязательно переиспользуй его id и не создавай новый object с другим id
        - у каждого action обязательно должны быть id, actorId, type, resultingPose
        - выводи ТОЛЬКО валидный JSON, без пояснений

        Короткий пример 1:
        source: 2 актёра идут навстречу друг другу, останавливаются около ноутбука
        idea: два action walk c direction="toward_each_other", затем stop/approach к object_marked_...

        Короткий пример 2:
        source: 2 актёра идут навстречу друг другу, проходят мимо ноутбука, второй начинает бежать
        idea: actor_1 = walk, actor_2 = run, оба сохраняют target/объект и не теряют ноутбук
        <|im_end|>
        <|im_start|>user
        \(stateContext)\(markedObjectsContext)SOURCE:
        \(description)<|im_end|>
        <|im_start|>assistant
        """
    }

    private func buildMarkedObjectsContext(_ markedObjects: [MarkedObject]) -> String {
        guard !markedObjects.isEmpty else {
            return "MARKED OBJECTS:\n- none\n\n"
        }

        let lines = markedObjects.map { marker in
            let id = "object_marked_\(marker.id.uuidString.prefix(8))"
            return "- id=\(id), name=\(marker.name.lowercased()), type=\(marker.type.rawValue)"
        }.joined(separator: "\n")

        let exampleId = "object_marked_\(markedObjects[0].id.uuidString.prefix(8))"
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


    // MARK: - JSON Parsing

    /// Парсит JSON (SceneScript) из ответа LLM с починкой типичных ошибок маленькой модели
    private func parseJSONFromResponse(_ response: String, description: String, markedObjects: [MarkedObject]) -> SceneScript? {
        guard let extractedJSON = extractJSONPayload(from: response) else {
            print("❌ [LLM] Не найден JSON в ответе")
            return nil
        }

        let candidates = makeJSONCandidates(from: extractedJSON)

        for (index, candidate) in candidates.enumerated() {
            print("🔧 [LLM] JSON после починки [вариант \(index + 1)/\(candidates.count)]: \(candidate.prefix(200))...")

            do {
                let decoded = try decodeSceneScript(from: candidate)
                let script = repairSceneScript(decoded, description: description, markedObjects: markedObjects)
                print("✅ [LLM] Декодировано: \(script.actors.count) актёров, \(script.objects.count) объектов, \(script.beats.count) тактов, \(script.actions.count) действий")
                if let camera = script.beats.first?.camera {
                    print("📷 [LLM] Камера beat_1: \(camera.shotType.rawValue), movement=\(camera.movement?.rawValue ?? "nil")")
                }
                return script
            } catch {
                print("❌ [LLM] Ошибка декодирования [вариант \(index + 1)/\(candidates.count)]: \(error)")
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

    private func decodeSceneScript(from text: String) throws -> SceneScript {
        guard let data = text.data(using: .utf8) else {
            throw NSError(domain: "LLMParserService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не удалось конвертировать JSON в Data"])
        }

        guard var jsonObj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "LLMParserService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Корневой JSON не является объектом"])
        }

        jsonObj["originalDescription"] = self.lastDescription

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

    private func repairSceneScript(_ script: SceneScript, description: String, markedObjects: [MarkedObject]) -> SceneScript {
        var repaired = script
        let lowercasedDescription = description.lowercased()
        let mentionedMarkers = findMentionedMarkers(in: lowercasedDescription, markedObjects: markedObjects)

        repaired = normalizeActorNames(in: repaired)
        repaired = ensurePoses(in: repaired)
        repaired = injectMarkedObjectsIfNeeded(in: repaired, mentionedMarkers: mentionedMarkers)
        repaired = repairMotionSemantics(in: repaired, description: lowercasedDescription, mentionedMarkers: mentionedMarkers)

        return repaired
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

        return SceneScript(
            sceneHeading: script.sceneHeading,
            locationName: script.locationName,
            interiorExterior: script.interiorExterior,
            timeOfDay: script.timeOfDay,
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

        return SceneScript(
            sceneHeading: script.sceneHeading,
            locationName: script.locationName,
            interiorExterior: script.interiorExterior,
            timeOfDay: script.timeOfDay,
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
            let objectId = "object_marked_\(marker.id.uuidString.prefix(8))"
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

        return SceneScript(
            sceneHeading: script.sceneHeading,
            locationName: script.locationName,
            interiorExterior: script.interiorExterior,
            timeOfDay: script.timeOfDay,
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
        let primaryMarkedObjectId = mentionedMarkers.first.map { "object_marked_\($0.id.uuidString.prefix(8))" }
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

        return SceneScript(
            sceneHeading: script.sceneHeading,
            locationName: script.locationName,
            interiorExterior: script.interiorExterior,
            timeOfDay: script.timeOfDay,
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

    // MARK: - GBNF Grammar

    /// GBNF-грамматика, описывающая JSON-схему SceneScript v2 (beat-система + камера + позы).
    /// Constrained decoding: сэмплер физически не может выдать невалидный JSON.
    static let sceneScriptGrammar: String = {
        // GBNF grammar — каждая строка без ведущих пробелов (парсер GBNF чувствителен к отступам)
        // v2: beats вместо actions, camera/minDuration/resultingPose/holdingObject
        let lines = [
            // --- Корневой объект ---
            #"root ::= "{" ws root-scene-heading root-location-name root-interior-exterior root-time-of-day actors-field "," ws objects-field "," ws beats-field root-relations ws "}""#,
            "",
            #"ws ::= ([ \t\n])*"#,
            "",
            // --- Опциональные поля сцены ---
            #"root-scene-heading ::= ("\"sceneHeading\"" ws ":" ws text-string "," ws) | """#,
            #"root-location-name ::= ("\"locationName\"" ws ":" ws text-string "," ws) | """#,
            #"root-interior-exterior ::= ("\"interiorExterior\"" ws ":" ws ie-type "," ws) | """#,
            #"root-time-of-day ::= ("\"timeOfDay\"" ws ":" ws text-string "," ws) | """#,
            #"root-relations ::= ("," ws relations-field) | """#,
            #"ie-type ::= "\"int\"" | "\"ext\"" | "\"mixed\"" | "\"unknown\"""#,
            "",
            // --- Массивы верхнего уровня ---
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
            // --- Beat ---
            #"beat ::= "{" ws "\"id\"" ws ":" ws id-string "," ws "\"actions\"" ws ":" ws "[" ws action-list ws "]" beat-camera beat-duration ws "}""#,
            #"action-list ::= action ("," ws action)* | """#,
            #"beat-camera ::= ("," ws "\"camera\"" ws ":" ws camera-obj) | """#,
            #"beat-duration ::= ("," ws "\"minDuration\"" ws ":" ws number) | """#,
            "",
            // --- Camera ---
            #"camera-obj ::= "{" ws "\"shotType\"" ws ":" ws shot-type camera-movement camera-target ws "}""#,
            #"shot-type ::= "\"wide\"" | "\"medium\"" | "\"close_up\"" | "\"extreme_close_up\"" | "\"over_shoulder\"" | "\"two_shot\"""#,
            #"camera-movement ::= ("," ws "\"movement\"" ws ":" ws movement-type) | """#,
            #"movement-type ::= "\"static\"" | "\"pan_left\"" | "\"pan_right\"" | "\"tilt_up\"" | "\"tilt_down\"" | "\"dolly_in\"" | "\"dolly_out\"" | "\"tracking\"" | "\"crane_up\"" | "\"crane_down\"""#,
            #"camera-target ::= ("," ws "\"target\"" ws ":" ws id-string) | """#,
            "",
            // --- Актёры ---
            #"actor ::= "{" ws "\"id\"" ws ":" ws id-string "," ws "\"type\"" ws ":" ws actor-type actor-name ws "}""#,
            #"actor-type ::= "\"human\"" | "\"tiger\"" | "\"lion\"" | "\"dog\"" | "\"cat\"" | "\"bird\"" | "\"horse\"" | "\"generic\"""#,
            #"actor-name ::= ("," ws "\"name\"" ws ":" ws text-string) | """#,
            "",
            // --- Объекты ---
            #"object ::= "{" ws "\"id\"" ws ":" ws id-string "," ws "\"type\"" ws ":" ws object-type object-name "," ws "\"relativePosition\"" ws ":" ws relative-pos ws "}""#,
            #"object-type ::= "\"table\"" | "\"chair\"" | "\"couch\"" | "\"bed\"" | "\"door\"" | "\"window\"" | "\"cabinet\"" | "\"shelf\"" | "\"tv\"" | "\"counter\"" | "\"desk\"" | "\"fridge\"" | "\"sink\"" | "\"stove\"" | "\"mirror\"" | "\"car\"" | "\"generic\"""#,
            #"object-name ::= ("," ws "\"name\"" ws ":" ws text-string) | """#,
            #"relative-pos ::= "\"left\"" | "\"right\"" | "\"center\"" | "\"background\"" | "\"foreground\"" | "\"unknown\"""#,
            "",
            // --- Действия ---
            #"action ::= "{" ws "\"id\"" ws ":" ws id-string "," ws "\"actorId\"" ws ":" ws id-string "," ws "\"type\"" ws ":" ws action-type action-target action-direction action-speed "," ws "\"resultingPose\"" ws ":" ws pose-type action-holding action-dialogue action-fallback action-source ws "}""#,
            #"action-type ::= "\"walk\"" | "\"run\"" | "\"approach\"" | "\"pass_by\"" | "\"enter\"" | "\"exit\"" | "\"stand\"" | "\"sit\"" | "\"lie_down\"" | "\"stop\"" | "\"turn\"" | "\"crouch\"" | "\"look_at\"" | "\"pick_up\"" | "\"put_down\"" | "\"open\"" | "\"close\"" | "\"give\"" | "\"talk\"" | "\"described_action\"""#,
            #"action-target ::= ("," ws "\"target\"" ws ":" ws id-string) | """#,
            #"action-direction ::= ("," ws "\"direction\"" ws ":" ws direction-type) | """#,
            #"direction-type ::= "\"left\"" | "\"right\"" | "\"forward\"" | "\"backward\"" | "\"toward_each_other\"" | "\"away_from_each_other\"" | "\"to_target\"""#,
            #"action-speed ::= ("," ws "\"modifier\"" ws ":" ws speed-type) | """#,
            #"speed-type ::= "\"slowly\"" | "\"quickly\"" | "\"carefully\"""#,
            #"pose-type ::= "\"standing\"" | "\"sitting\"" | "\"crouching\"" | "\"lying\"" | "\"walking\"" | "\"running\"""#,
            #"action-holding ::= ("," ws "\"holdingObject\"" ws ":" ws id-string) | """#,
            #"action-dialogue ::= ("," ws "\"dialogue\"" ws ":" ws text-string) | """#,
            #"action-fallback ::= ("," ws "\"fallbackText\"" ws ":" ws text-string) | """#,
            #"action-source ::= ("," ws "\"sourceText\"" ws ":" ws text-string) | """#,
            "",
            // --- Пространственные отношения ---
            #"relation ::= "{" ws "\"id\"" ws ":" ws id-string "," ws "\"subject\"" ws ":" ws id-string "," ws "\"relation\"" ws ":" ws relation-type "," ws "\"object\"" ws ":" ws id-string ws "}""#,
            #"relation-type ::= "\"near\"" | "\"in_front_of\"" | "\"behind\"" | "\"left_of\"" | "\"right_of\"" | "\"between\"" | "\"pass_by\"" | "\"inside\"" | "\"outside\"""#,
            "",
            // --- Примитивы ---
            #"id-string ::= "\"" [a-zA-Z0-9_]+ "\"""#,
            #"text-string ::= "\"" ([^"\\] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]))* "\"""#,
            #"number ::= [0-9]+ ("." [0-9]+)?"#,
        ]
        return lines.joined(separator: "\n")
    }()
}
