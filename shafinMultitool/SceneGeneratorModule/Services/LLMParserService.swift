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
        
        guard let modelPath = Bundle.main.path(forResource: "qwen3.5-0.8b-q4_k_m", ofType: "gguf") else {
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
    func parseAsync(_ description: String, markedObjects: [MarkedObject] = []) async -> SceneScript? {
        // Загружаем модель если ещё не загружена
        await loadModelIfNeeded()
        
        guard let context = llamaContext, isAvailable else {
            print("⚠️ [LLM] Модель не доступна, пропускаем LLM парсинг")
            return nil
        }
        
        print("🤖 [LLM] Начало LLM парсинга для: '\(description)'")
        self.lastDescription = description
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Формируем промпт
        let prompt = buildPrompt(description: description, markedObjects: markedObjects)
        
        // Генерируем ответ через llama.cpp
        let generatedText = await context.generate(prompt: prompt, maxTokens: 300)
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        print("🤖 [LLM] Генерация заняла: \(String(format: "%.2f", elapsed)) сек")
        print("🤖 [LLM] Ответ модели:\n\(generatedText)")
        
        // Парсим JSON из ответа
        if let script = parseJSONFromResponse(generatedText) {
            print("✅ [LLM] SceneScript успешно извлечён из ответа LLM")
            return script
        }
        
        print("❌ [LLM] Не удалось извлечь SceneScript из ответа")
        return nil
    }
    
    /// Синхронная обёртка (для обратной совместимости)
    func parse(_ description: String, markedObjects: [MarkedObject] = []) -> SceneScript? {
        guard isAvailable else {
            print("⚠️ [LLM] Модель не загружена, пропускаем LLM парсинг")
            return nil
        }
        
        // Синхронный вызов — блокирует поток, использовать только в крайнем случае
        var result: SceneScript?
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            result = await parseAsync(description, markedObjects: markedObjects)
            semaphore.signal()
        }
        
        semaphore.wait()
        return result
    }
    
    // MARK: - Prompt Building
    
    /// Формирует промпт для LLM
    private func buildPrompt(description: String, markedObjects: [MarkedObject]) -> String {
        let actorTypes = SceneActor.ActorType.allCases.map { $0.rawValue }.joined(separator: ", ")
        let objectTypes = SceneObject.ObjectType.allCases.map { $0.rawValue }.joined(separator: ", ")
        let actionTypes = SceneAction.ActionType.allCases.map { $0.rawValue }.joined(separator: ", ")
        let relationTypes = SpatialRelation.RelationType.allCases.map { $0.rawValue }.joined(separator: ", ")
        
        var markedObjectsContext = ""
        if !markedObjects.isEmpty {
            let list = markedObjects.map { "\($0.name) (тип: \($0.type.rawValue))" }.joined(separator: ", ")
            markedObjectsContext = "\nВ сцене есть размеченные пользователем объекты: \(list)."
        }
        
        return """
        <|im_start|>system
        Ты ассистент для разбора текстовых описаний сцен. Твоя задача — преобразовать описание в структурированный JSON.
        
        JSON должен содержать 4 поля:
        - "actors": массив участников сцены (люди, животные)
        - "objects": массив предметов в сцене (мебель, двери и т.д.)
        - "actions": массив действий (кто что делает и с какой целью)
        - "spatialRelations": массив пространственных отношений (кто/что где находится относительно чего)
        
        Допустимые типы актёров: \(actorTypes)
        Допустимые типы объектов: \(objectTypes)
        Допустимые типы действий: \(actionTypes)
        Допустимые типы пространственных отношений: \(relationTypes)
        
        Правила:
        - Выводи ТОЛЬКО валидный JSON, начиная с символа {
        - Никакого дополнительного текста, объяснений или markdown до и после JSON
        - IDs давай вида: actor_1, actor_2, object_1, action_1, rel_1 и т.д.
        - Если в описании несколько актёров — это отдельные записи в "actors"
        - Пространственные отношения (позади, рядом, впереди) помещай в "spatialRelations"
        <|im_end|>
        <|im_start|>user
        Человек подходит к столу и садится на стул
        <|im_end|>
        <|im_start|>assistant
        {"actors":[{"id":"actor_1","type":"human"}],"objects":[{"id":"object_1","type":"table"},{"id":"object_2","type":"chair"}],"actions":[{"id":"action_1","actorId":"actor_1","type":"approach","target":"object_1"},{"id":"action_2","actorId":"actor_1","type":"sit","target":"object_2"}],"spatialRelations":[]}
        <|im_end|>
        <|im_start|>user
        2 актёра идут навстречу друг другу, первый проходит мимо двери
        <|im_end|>
        <|im_start|>assistant
        {"actors":[{"id":"actor_1","type":"human"},{"id":"actor_2","type":"human"}],"objects":[{"id":"object_1","type":"door"}],"actions":[{"id":"action_1","actorId":"actor_1","type":"walk","target":"actor_2","direction":"toward_each_other"},{"id":"action_2","actorId":"actor_2","type":"walk","target":"actor_1","direction":"toward_each_other"},{"id":"action_3","actorId":"actor_1","type":"pass_by","target":"object_1"}],"spatialRelations":[]}
        <|im_end|>
        <|im_start|>user
        \(markedObjectsContext.isEmpty ? "" : markedObjectsContext + "\n")\(description)
        <|im_end|>
        <|im_start|>assistant
        """
    }

    
    // MARK: - JSON Parsing
    
    /// Парсит JSON (SceneScript) из ответа LLM с починкой типичных ошибок маленькой модели
    private func parseJSONFromResponse(_ response: String) -> SceneScript? {
        var text = response
        
        // 1. Убираем служебные токены модели
        text = text.replacingOccurrences(of: "<|im_end|>", with: "")
        text = text.replacingOccurrences(of: "<|im_start|>", with: "")
        text = text.replacingOccurrences(of: "```json", with: "")
        text = text.replacingOccurrences(of: "```", with: "")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 2. Извлекаем JSON от { до }
        guard let startIndex = text.firstIndex(of: "{") else {
            print("❌ [LLM] Не найден JSON в ответе")
            return nil
        }
        
        if let endIndex = text.lastIndex(of: "}") {
            text = String(text[startIndex...endIndex])
        } else {
            text = String(text[startIndex...])
        }
        
        // 3. Исправляем типичные ошибки маленькой модели
        text = repairJSON(text)
        
        // 4. Балансируем скобки если JSON обрезан
        text = balanceBrackets(text)
        
        print("🔧 [LLM] JSON после починки: \(text.prefix(200))...")
        
        // 5. Вставляем originalDescription (обязательное поле SceneScript, которое LLM не генерирует)
        // Сохраняем описание для передачи в parseJSONFromResponse
        guard let data = text.data(using: .utf8) else {
            print("❌ [LLM] Не удалось конвертировать в Data")
            return nil
        }
        
        // Вставляем originalDescription в JSON перед декодированием
        do {
            if var jsonObj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                jsonObj["originalDescription"] = self.lastDescription
                let fixedData = try JSONSerialization.data(withJSONObject: jsonObj)
                let script = try JSONDecoder().decode(SceneScript.self, from: fixedData)
                print("✅ [LLM] Декодировано: \(script.actors.count) актёров, \(script.objects.count) объектов, \(script.actions.count) действий")
                return script
            }
        } catch {
            print("❌ [LLM] Ошибка декодирования: \(error)")
            print("   JSON: \(text.prefix(300))")
        }
        return nil
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
        
        for _ in 0..<(openBrackets - closeBrackets) { json += "]" }
        for _ in 0..<(openBraces - closeBraces) { json += "}" }
        
        return json
    }
    
    // MARK: - GBNF Grammar
    
    /// GBNF-грамматика, описывающая JSON-схему SceneScript.
    /// Constrained decoding: сэмплер физически не может выдать невалидный JSON.
    static let sceneScriptGrammar = #"""
    root ::= "{" ws actors-field "," ws objects-field "," ws actions-field "," ws relations-field ws "}"

    ws ::= ([ \t\n])*

    actors-field ::= "\"actors\"" ws ":" ws "[" ws actor-list ws "]"
    actor-list ::= actor ("," ws actor)* | ""

    objects-field ::= "\"objects\"" ws ":" ws "[" ws object-list ws "]"
    object-list ::= object ("," ws object)* | ""

    actions-field ::= "\"actions\"" ws ":" ws "[" ws action-list ws "]"
    action-list ::= action ("," ws action)* | ""

    relations-field ::= "\"spatialRelations\"" ws ":" ws "[" ws relation-list ws "]"
    relation-list ::= relation ("," ws relation)* | ""

    actor ::= "{" ws "\"id\"" ws ":" ws string "," ws "\"type\"" ws ":" ws actor-type ws "}"
    actor-type ::= "\"human\"" | "\"tiger\"" | "\"lion\"" | "\"dog\"" | "\"cat\"" | "\"bird\"" | "\"generic\""

    object ::= "{" ws "\"id\"" ws ":" ws string "," ws "\"type\"" ws ":" ws object-type ws "}"
    object-type ::= "\"table\"" | "\"chair\"" | "\"cabinet\"" | "\"door\"" | "\"couch\"" | "\"bed\"" | "\"window\"" | "\"shelf\"" | "\"tv\"" | "\"generic\""

    action ::= "{" ws "\"id\"" ws ":" ws string "," ws "\"actorId\"" ws ":" ws string "," ws "\"type\"" ws ":" ws action-type action-target action-direction action-speed ws "}"
    action-type ::= "\"walk\"" | "\"run\"" | "\"stop\"" | "\"turn\"" | "\"approach\"" | "\"pass_by\"" | "\"enter\"" | "\"exit\"" | "\"stand\"" | "\"sit\""
    action-target ::= ("," ws "\"target\"" ws ":" ws string) | ""
    action-direction ::= ("," ws "\"direction\"" ws ":" ws direction-type) | ""
    direction-type ::= "\"left\"" | "\"right\"" | "\"forward\"" | "\"backward\"" | "\"toward_each_other\"" | "\"away_from_each_other\"" | "\"to_target\""
    action-speed ::= ("," ws "\"speed\"" ws ":" ws speed-type) | ""
    speed-type ::= "\"slowly\"" | "\"quickly\"" | "\"carefully\""

    relation ::= "{" ws "\"id\"" ws ":" ws string "," ws "\"subject\"" ws ":" ws string "," ws "\"relation\"" ws ":" ws relation-type "," ws "\"object\"" ws ":" ws string ws "}"
    relation-type ::= "\"near\"" | "\"in_front_of\"" | "\"behind\"" | "\"left_of\"" | "\"right_of\"" | "\"between\"" | "\"pass_by\"" | "\"inside\"" | "\"outside\""

    string ::= "\"" [a-zA-Z0-9_]+ "\""
    """#
}

