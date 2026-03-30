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
        
        guard let modelPath = Bundle.main.path(forResource: "qwen2.5-0.5b-instruct.Q4_K_M", ofType: "gguf") else {
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
        var markedObjectsContext = ""
        if !markedObjects.isEmpty {
            let list = markedObjects.map { "\($0.name) (тип: \($0.type.rawValue))" }.joined(separator: ", ")
            markedObjectsContext = "В сцене есть размеченные пользователем объекты: \(list).\n"
        }
        
        return """
        <|im_start|>system
        Ты парсер мизансцен для кинопроизводства. Преобразуй текстовое описание мизансцены на русском языке в JSON (SceneScript). Разбивай действия на хронологические такты (beats). Каждый beat — одновременные действия всех актёров. Выводи ТОЛЬКО валидный JSON, без пояснений.<|im_end|>
        <|im_start|>user
        \(markedObjectsContext)\(description)<|im_end|>
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
        
        // 5. Вставляем originalDescription и конвертируем legacy-формат (actions → beats)
        guard let data = text.data(using: .utf8) else {
            print("❌ [LLM] Не удалось конвертировать в Data")
            return nil
        }
        
        do {
            if var jsonObj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                jsonObj["originalDescription"] = self.lastDescription
                
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
                let script = try JSONDecoder().decode(SceneScript.self, from: fixedData)
                print("✅ [LLM] Декодировано: \(script.actors.count) актёров, \(script.objects.count) объектов, \(script.beats.count) тактов, \(script.actions.count) действий")
                if let camera = script.beats.first?.camera {
                    print("📷 [LLM] Камера beat_1: \(camera.shotType.rawValue), movement=\(camera.movement?.rawValue ?? "nil")")
                }
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
    
    /// GBNF-грамматика, описывающая JSON-схему SceneScript v2 (beat-система + камера + позы).
    /// Constrained decoding: сэмплер физически не может выдать невалидный JSON.
    static let sceneScriptGrammar: String = {
        // GBNF grammar — каждая строка без ведущих пробелов (парсер GBNF чувствителен к отступам)
        // v2: beats вместо actions, camera/minDuration/resultingPose/holdingObject
        let lines = [
            // --- Корневой объект: actors, objects, beats, spatialRelations ---
            #"root ::= "{" ws actors-field "," ws objects-field "," ws beats-field "," ws relations-field ws "}""#,
            "",
            #"ws ::= ([ \t\n])*"#,
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
            // --- Beat: id + actions + optional camera + optional minDuration ---
            #"beat ::= "{" ws "\"id\"" ws ":" ws string "," ws "\"actions\"" ws ":" ws "[" ws action-list ws "]" beat-camera beat-duration ws "}""#,
            #"action-list ::= action ("," ws action)* | """#,
            #"beat-camera ::= ("," ws "\"camera\"" ws ":" ws camera-obj) | """#,
            #"beat-duration ::= ("," ws "\"minDuration\"" ws ":" ws number) | """#,
            "",
            // --- Camera: shotType + optional movement + optional target ---
            #"camera-obj ::= "{" ws "\"shotType\"" ws ":" ws shot-type camera-movement camera-target ws "}""#,
            #"shot-type ::= "\"wide\"" | "\"medium\"" | "\"close_up\"" | "\"extreme_close_up\"" | "\"over_shoulder\"" | "\"two_shot\"""#,
            #"camera-movement ::= ("," ws "\"movement\"" ws ":" ws movement-type) | """#,
            #"movement-type ::= "\"static\"" | "\"pan_left\"" | "\"pan_right\"" | "\"tilt_up\"" | "\"tilt_down\"" | "\"dolly_in\"" | "\"dolly_out\"" | "\"tracking\"" | "\"crane_up\"" | "\"crane_down\"""#,
            #"camera-target ::= ("," ws "\"target\"" ws ":" ws string) | """#,
            "",
            // --- Актёры ---
            #"actor ::= "{" ws "\"id\"" ws ":" ws string "," ws "\"type\"" ws ":" ws actor-type ws "}""#,
            #"actor-type ::= "\"human\"" | "\"tiger\"" | "\"lion\"" | "\"dog\"" | "\"cat\"" | "\"bird\"" | "\"horse\"" | "\"generic\"""#,
            "",
            // --- Объекты ---
            #"object ::= "{" ws "\"id\"" ws ":" ws string "," ws "\"type\"" ws ":" ws object-type ws "}""#,
            #"object-type ::= "\"table\"" | "\"chair\"" | "\"couch\"" | "\"bed\"" | "\"door\"" | "\"window\"" | "\"cabinet\"" | "\"shelf\"" | "\"stairs\"" | "\"car\"" | "\"phone\"" | "\"cup\"" | "\"bottle\"" | "\"gun\"" | "\"book\"" | "\"bag\"" | "\"box\"" | "\"flower\"" | "\"letter\"" | "\"key\"" | "\"lamp\"" | "\"mirror\"" | "\"tv\"" | "\"generic\"""#,
            "",
            // --- Действия: type + optional target/direction/speed/resultingPose/holdingObject ---
            #"action ::= "{" ws "\"actorId\"" ws ":" ws string "," ws "\"type\"" ws ":" ws action-type action-target action-direction action-speed action-pose action-holding action-dialogue ws "}""#,
            #"action-type ::= "\"walk\"" | "\"run\"" | "\"approach\"" | "\"pass_by\"" | "\"enter\"" | "\"exit\"" | "\"stand\"" | "\"sit\"" | "\"lie_down\"" | "\"stop\"" | "\"turn\"" | "\"crouch\"" | "\"look_at\"" | "\"pick_up\"" | "\"put_down\"" | "\"open\"" | "\"close\"" | "\"give\"" | "\"talk\"""#,
            #"action-target ::= ("," ws "\"target\"" ws ":" ws string) | """#,
            #"action-direction ::= ("," ws "\"direction\"" ws ":" ws direction-type) | """#,
            #"direction-type ::= "\"left\"" | "\"right\"" | "\"forward\"" | "\"backward\"" | "\"toward_each_other\"" | "\"away_from_each_other\"" | "\"to_target\"""#,
            #"action-speed ::= ("," ws "\"speed\"" ws ":" ws speed-type) | """#,
            #"speed-type ::= "\"slowly\"" | "\"quickly\"" | "\"carefully\"""#,
            #"action-pose ::= ("," ws "\"resultingPose\"" ws ":" ws pose-type) | """#,
            #"pose-type ::= "\"standing\"" | "\"sitting\"" | "\"crouching\"" | "\"lying\"" | "\"walking\"" | "\"running\"""#,
            #"action-holding ::= ("," ws "\"holdingObject\"" ws ":" ws string) | """#,
            #"action-dialogue ::= ("," ws "\"dialogue\"" ws ":" ws string) | """#,
            "",
            // --- Пространственные отношения ---
            #"relation ::= "{" ws "\"id\"" ws ":" ws string "," ws "\"subject\"" ws ":" ws string "," ws "\"relation\"" ws ":" ws relation-type "," ws "\"object\"" ws ":" ws string ws "}""#,
            #"relation-type ::= "\"near\"" | "\"in_front_of\"" | "\"behind\"" | "\"left_of\"" | "\"right_of\"" | "\"between\"" | "\"pass_by\"" | "\"inside\"" | "\"outside\"""#,
            "",
            // --- Примитивы ---
            #"string ::= "\"" [a-zA-Z0-9_]+ "\"""#,
            #"number ::= [0-9]+ ("." [0-9]+)?"#,
        ]
        return lines.joined(separator: "\n")
    }()
}

