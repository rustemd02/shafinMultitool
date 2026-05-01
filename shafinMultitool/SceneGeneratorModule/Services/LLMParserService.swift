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
    private static let modelPathOverrideDefaultsKey = "scene_generator_llm_model_path"
    private static let generationTokenBudgets: [Int32] = [1024, 1536, 2048]
    private static let maxGenerationTokens: Int32 = 3072
    private static let v9EventTokenBudgets: [Int32] = [768, 1024, 1536]
    private static let v9EventMaxGenerationTokens: Int32 = 2048
    private static let v9PatchMaxRetry: Int = 1
    private static let v9PatchMaxTokens: Int32 = 512
    private static let v9PatchWallClockBudgetSeconds: TimeInterval = 8
    private static let v9EventTargetRequiredTypes: Set<SceneAction.ActionType> = [
        .lookAt, .pickUp, .open, .close, .approach, .putDown, .give, .passBy, .stop
    ]
    private static let genericRoleNames: Set<String> = [
        "мужчина", "женщина", "парень", "девушка", "человек", "персонаж",
        "актёр", "актер", "актриса", "герой", "героиня", "он", "она", "они"
    ]
    private let lemmatizer = Lemmatizer()
    private lazy var markedObjectMatcher = MarkedObjectMatcher(lemmatizer: lemmatizer)
    private let planCompiler = ScenePlanCompiler()
    private let stateLock = NSLock()
    private var loadingTask: Task<Void, Never>?

    /// Plan context с grammar ScenePlanIR — текущий backward-compatible путь.
    private var llamaContext: LlamaContext?
    /// Отдельный context под V9 event-table grammar.
    private var eventTableLlamaContext: LlamaContext?
    /// Отдельный context под V9 patch-ops grammar.
    private var patchOpsLlamaContext: LlamaContext?

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

            guard let modelPath = self.resolvePreferredModelPath() else {
                let availableGGUF = self.discoverBundledGGUFModelURLs()
                    .map { $0.lastPathComponent }
                    .sorted()
                    .joined(separator: ", ")
                let error = availableGGUF.isEmpty
                    ? "V8 GGUF модель не найдена в приложении"
                    : "V8 GGUF модель не найдена. Доступные GGUF: [\(availableGGUF)]"
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

    private enum V9ContextKind {
        case eventTable
        case patchOps
    }

    private func loadV9ContextIfNeeded(_ kind: V9ContextKind) async -> LlamaContext? {
        await loadModelIfNeeded()

        if !isAvailable {
            return nil
        }

        if let existing = withStateLock({
            switch kind {
            case .eventTable:
                return eventTableLlamaContext
            case .patchOps:
                return patchOpsLlamaContext
            }
        }) {
            return existing
        }

        guard let modelPath = resolvePreferredModelPath() else {
            print("⚠️ [LLM][V9] Модель не найдена для \(kind == .eventTable ? "event_table" : "patch_ops") context")
            return nil
        }

        let grammar: String
        switch kind {
        case .eventTable:
            grammar = Self.sceneV9EventTableGrammar
        case .patchOps:
            grammar = Self.sceneV9PatchOpsGrammar
        }

        do {
            let context = try LlamaContext.create(
                modelPath: modelPath,
                temperature: 0.05,
                grammarStr: grammar
            )
            withStateLock {
                switch kind {
                case .eventTable:
                    self.eventTableLlamaContext = context
                case .patchOps:
                    self.patchOpsLlamaContext = context
                }
            }
            print("✅ [LLM][V9] Загружен отдельный context: \(kind == .eventTable ? "event_table" : "patch_ops")")
            return context
        } catch {
            print("⚠️ [LLM][V9] Не удалось загрузить \(kind == .eventTable ? "event_table" : "patch_ops") context: \(error.localizedDescription)")
            return nil
        }
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
        let budgets = generationBudgets(for: description, anchors: anchors, state: state)
        var reasonCodes: [String] = []

        for (attemptIndex, maxTokens) in budgets.enumerated() {
            let attemptStart = CFAbsoluteTimeGetCurrent()
            let attemptSuffix = budgets.count > 1
                ? " [попытка \(attemptIndex + 1)/\(budgets.count), maxTokens=\(maxTokens)]"
                : ""

            // Генерируем ответ через llama.cpp
            let generationOutput = await context.generateWithMetadata(prompt: prompt, maxTokens: maxTokens)
            let generatedText = generationOutput.text
            let hitTokenLimit = generationOutput.stopReason == .maxTokensReached

            let elapsed = CFAbsoluteTimeGetCurrent() - attemptStart
            print("🤖 [LLM] Генерация\(attemptSuffix) заняла: \(String(format: "%.2f", elapsed)) сек")
            print("🤖 [LLM] stopReason=\(generationOutput.stopReason.rawValue), generatedTokens=\(generationOutput.generatedTokenCount)/\(generationOutput.maxTokens)")
            print("🤖 [LLM] Ответ модели\(attemptSuffix):\n\(generatedText)")

            // Парсим JSON из ответа
            if let planResult = parsePlanFromResponse(
                generatedText,
                description: description,
                markedObjects: markedObjects,
                anchors: anchors
            ) {
                if shouldRetryForLikelyTruncatedResponse(
                    generatedText,
                    plan: planResult.plan,
                    description: description,
                    stoppedByTokenBudget: hitTokenLimit
                ), attemptIndex < budgets.count - 1 {
                    let nextBudget = budgets[attemptIndex + 1]
                    let reason = hitTokenLimit
                        ? "обрезано по maxTokens"
                        : "план выглядит неполным"
                    print("⚠️ [LLM] План распознан, но \(reason). Повторяем с maxTokens=\(nextBudget)")
                    if hitTokenLimit, !reasonCodes.contains("llm.retry_after_max_tokens") {
                        reasonCodes.append("llm.retry_after_max_tokens")
                    } else if !reasonCodes.contains("llm.retry_after_possible_truncation") {
                        reasonCodes.append("llm.retry_after_possible_truncation")
                    }
                    continue
                }
                print("✅ [LLM] ScenePlanIR успешно извлечён из ответа LLM")
                if attemptIndex > 0, !reasonCodes.contains("llm.retry_recovered") {
                    reasonCodes.append("llm.retry_recovered")
                }
                if hitTokenLimit, !reasonCodes.contains("llm.max_tokens_reached") {
                    reasonCodes.append("llm.max_tokens_reached")
                }
                return ScenePlanProviderResult(
                    plan: planResult.plan,
                    usedLegacySceneScriptBridge: planResult.usedLegacySceneScriptBridge,
                    reasonCodes: reasonCodes
                )
            }

            if hitTokenLimit, !reasonCodes.contains("llm.max_tokens_reached") {
                reasonCodes.append("llm.max_tokens_reached")
            }

            if attemptIndex < budgets.count - 1 {
                let nextBudget = budgets[attemptIndex + 1]
                print("⚠️ [LLM] Ответ не удалось распарсить, повторяем генерацию с maxTokens=\(nextBudget)")
                if !reasonCodes.contains("llm.retry_after_json_parse_failure") {
                    reasonCodes.append("llm.retry_after_json_parse_failure")
                }
            }
        }

        print("❌ [LLM] Не удалось извлечь SceneScript из ответа")
        return nil
    }

    private func generationBudgets(
        for description: String,
        anchors: SourceAnchorBundle,
        state: SceneChunkState?
    ) -> [Int32] {
        let stateEntityCount = (state?.knownActors.count ?? 0) + (state?.knownObjects.count ?? 0)
        let anchorComplexity = (anchors.mentionedMarkedObjects.count * 60)
            + (anchors.objectSurfaceMentions.count * 30)
            + (anchors.phaseCues.count * 20)
        let estimated = Int32(description.count / 2) + 640 + Int32(anchorComplexity + (stateEntityCount * 25))
        let firstBudget = max(Self.generationTokenBudgets[0], min(estimated, Self.maxGenerationTokens))

        var budgets = [firstBudget]
        for budget in Self.generationTokenBudgets {
            let normalized = min(max(budget, firstBudget), Self.maxGenerationTokens)
            if !budgets.contains(normalized) {
                budgets.append(normalized)
            }
        }

        if let last = budgets.last, last < Self.maxGenerationTokens {
            budgets.append(Self.maxGenerationTokens)
        }

        return budgets
    }

    private func shouldRetryForLikelyTruncatedPlan(_ plan: ScenePlanIR, description: String) -> Bool {
        guard plan.beats.isEmpty else { return false }
        return descriptionLikelyContainsActionsOrDialogue(description)
    }

    private func shouldRetryForLikelyTruncatedResponse(
        _ response: String,
        plan: ScenePlanIR,
        description: String,
        stoppedByTokenBudget: Bool
    ) -> Bool {
        if shouldRetryForLikelyTruncatedPlan(plan, description: description) {
            return true
        }
        guard stoppedByTokenBudget else {
            return false
        }
        return responseLikelyContainsIncompleteJSON(response)
    }

    private func responseLikelyContainsIncompleteJSON(_ response: String) -> Bool {
        guard let payload = extractJSONPayload(from: response) else {
            return true
        }
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return true
        }
        if trimmed.hasSuffix(",") {
            return true
        }
        return !trimmed.hasSuffix("}")
    }

    private func descriptionLikelyContainsActionsOrDialogue(_ description: String) -> Bool {
        let text = description.lowercased()

        if text.contains(":") || text.contains("«") || text.contains("\"") {
            return true
        }

        let actionCues = [
            "идет", "идёт", "пошел", "пошёл", "идут",
            "бежит", "бегут", "подходит", "подошел", "подошёл",
            "садится", "встает", "встаёт", "берет", "берёт",
            "кладет", "кладёт", "открывает", "закрывает",
            "поворачивается", "смотрит", "говорит", "спрашивает",
            "подбегает", "проходит", "останавливается"
        ]

        return actionCues.contains { text.contains($0) }
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

    func generateEventTable(
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle,
        state: SceneChunkState?,
        slotCatalog: SceneV9SlotCatalog
    ) -> SceneV9EventProviderResult? {
        if Thread.isMainThread {
            print("⚠️ [LLM][V9] Sync generateEventTable вызван с main thread; пропускаем")
            return nil
        }

        var result: SceneV9EventProviderResult?
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            result = await generateEventTableAsync(
                description: description,
                markedObjects: markedObjects,
                anchors: anchors,
                state: state,
                slotCatalog: slotCatalog
            )
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    func generateEventTableAsync(
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle,
        state: SceneChunkState?,
        slotCatalog: SceneV9SlotCatalog
    ) async -> SceneV9EventProviderResult? {
        guard let context = await loadV9ContextIfNeeded(.eventTable) else {
            print("⚠️ [LLM][V9] Event-table context недоступен, fallback на V8 path")
            return nil
        }

        let prompt = buildV9EventTablePrompt(
            description: description,
            markedObjects: markedObjects,
            anchors: anchors,
            state: state,
            slotCatalog: slotCatalog
        )
        let budgets = v9EventGenerationBudgets(for: description, anchors: anchors, slotCatalog: slotCatalog)
        var reasonCodes: [String] = ["v9.event_table_prompt_used"]
        let startedAt = CFAbsoluteTimeGetCurrent()

        for (attemptIndex, maxTokens) in budgets.enumerated() {
            let output = await context.generateWithMetadata(prompt: prompt, maxTokens: maxTokens)
            let hitTokenLimit = output.stopReason == .maxTokensReached
            print("🤖 [LLM][V9] EventTable attempt \(attemptIndex + 1)/\(budgets.count), tokens=\(output.generatedTokenCount)/\(output.maxTokens), stop=\(output.stopReason.rawValue)")

            guard let parsed = parseEventTableFromResponse(output.text, slotCatalog: slotCatalog) else {
                if hitTokenLimit, !reasonCodes.contains("v9.event_table_max_tokens_reached") {
                    reasonCodes.append("v9.event_table_max_tokens_reached")
                }
                if attemptIndex < budgets.count - 1, !reasonCodes.contains("v9.event_table_retry_after_parse_failure") {
                    reasonCodes.append("v9.event_table_retry_after_parse_failure")
                }
                continue
            }

            var currentEventTable = parsed
            var patchOps: SceneV9PatchOps?
            var verifierIssues = v9VerifierIssues(for: currentEventTable, slotCatalog: slotCatalog)
            if !verifierIssues.isEmpty {
                reasonCodes.append("v9.event_table_verifier_issues_detected")
            }

            if !verifierIssues.isEmpty {
                let patchDeadline = startedAt + Self.v9PatchWallClockBudgetSeconds
                var retriesLeft = Self.v9PatchMaxRetry
                while retriesLeft > 0, CFAbsoluteTimeGetCurrent() < patchDeadline, !verifierIssues.isEmpty {
                    retriesLeft -= 1
                    reasonCodes.append("v9.patch_retry_attempted")
                    guard let candidatePatch = await generateEventPatchOpsAsync(
                        description: description,
                        markedObjects: markedObjects,
                        anchors: anchors,
                        state: state,
                        slotCatalog: slotCatalog,
                        eventTable: currentEventTable,
                        verifierIssues: verifierIssues
                    ) else {
                        reasonCodes.append("v9.patch_retry_unavailable")
                        break
                    }
                    patchOps = candidatePatch
                    currentEventTable = applying(candidatePatch, to: currentEventTable)
                    verifierIssues = v9VerifierIssues(for: currentEventTable, slotCatalog: slotCatalog)
                    if verifierIssues.isEmpty {
                        reasonCodes.append("v9.patch_retry_recovered")
                    } else {
                        reasonCodes.append("v9.patch_retry_not_recovered")
                    }
                }
                if !verifierIssues.isEmpty {
                    reasonCodes.append("v9.patch_retry_failed")
                }
            }

            if attemptIndex > 0 {
                reasonCodes.append("v9.event_table_retry_recovered")
            }
            if hitTokenLimit, !reasonCodes.contains("v9.event_table_max_tokens_reached") {
                reasonCodes.append("v9.event_table_max_tokens_reached")
            }

            return SceneV9EventProviderResult(
                slotCatalog: slotCatalog,
                eventTable: currentEventTable,
                patchOps: patchOps,
                reasonCodes: dedupeReasons(reasonCodes)
            )
        }

        print("❌ [LLM][V9] Не удалось сгенерировать EventTable")
        return nil
    }

    func generateEventPatchOps(
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle,
        state: SceneChunkState?,
        slotCatalog: SceneV9SlotCatalog,
        eventTable: SceneV9EventTable,
        verifierIssues: [String]
    ) -> SceneV9PatchOps? {
        if Thread.isMainThread {
            print("⚠️ [LLM][V9] Sync generateEventPatchOps вызван с main thread; пропускаем")
            return nil
        }

        var result: SceneV9PatchOps?
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            result = await generateEventPatchOpsAsync(
                description: description,
                markedObjects: markedObjects,
                anchors: anchors,
                state: state,
                slotCatalog: slotCatalog,
                eventTable: eventTable,
                verifierIssues: verifierIssues
            )
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    func generateEventPatchOpsAsync(
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle,
        state: SceneChunkState?,
        slotCatalog: SceneV9SlotCatalog,
        eventTable: SceneV9EventTable,
        verifierIssues: [String]
    ) async -> SceneV9PatchOps? {
        guard !verifierIssues.isEmpty else {
            return SceneV9PatchOps.empty
        }
        guard let context = await loadV9ContextIfNeeded(.patchOps) else {
            return nil
        }

        let prompt = buildV9PatchPrompt(
            description: description,
            markedObjects: markedObjects,
            anchors: anchors,
            state: state,
            slotCatalog: slotCatalog,
            eventTable: eventTable,
            verifierIssues: verifierIssues
        )
        let output = await context.generateWithMetadata(prompt: prompt, maxTokens: Self.v9PatchMaxTokens)
        print("🤖 [LLM][V9] PatchOps tokens=\(output.generatedTokenCount)/\(output.maxTokens), stop=\(output.stopReason.rawValue)")
        guard let patchOps = parsePatchOpsFromResponse(output.text) else {
            return nil
        }
        return patchOps
    }

    // MARK: - Prompt Building

    /// Формирует промпт для LLM
    private func buildPrompt(description: String, markedObjects: [MarkedObject], anchors: SourceAnchorBundle, state: SceneChunkState?) -> String {
        var stateContext = ""
        if let state = state {
            let actors = state.knownActors.map { "\($0.key) (id: \($0.value))" }.joined(separator: ", ")
            let objects = state.knownObjects.map { "\($0.key) (id: \($0.value))" }.joined(separator: ", ")
            let poses = state.actorPoses.map { "\($0.key)=\($0.value.rawValue)" }.joined(separator: ", ")
            let held = state.heldObjects.map { "\($0.key)->\($0.value)" }.joined(separator: ", ")
            let actorAliases = state.actorAliases.map { "\($0.key)->\($0.value)" }.joined(separator: ", ")
            let objectAliases = state.objectAliases.map { "\($0.key)->\($0.value)" }.joined(separator: ", ")
            stateContext = "Предыдущее состояние сцены:\n"
            if let sceneID = state.sceneID { stateContext += "Scene ID: \(sceneID)\n" }
            if let heading = state.sceneHeading { stateContext += "Scene heading: \(heading)\n" }
            if let loc = state.locationName { stateContext += "Локация: \(loc)\n" }
            if !actors.isEmpty { stateContext += "Известные персонажи (сохраняй их id): \(actors)\n" }
            if !objects.isEmpty { stateContext += "Известные объекты (переиспользуй их id): \(objects)\n" }
            if !actorAliases.isEmpty { stateContext += "Actor alias map: \(actorAliases)\n" }
            if !objectAliases.isEmpty { stateContext += "Object alias map: \(objectAliases)\n" }
            if !poses.isEmpty { stateContext += "Пози/poses актёров: \(poses)\n" }
            if !held.isEmpty { stateContext += "Что кто держит: \(held)\n" }
            if let speaker = state.lastResolvedSpeaker { stateContext += "Последний говорящий: \(speaker)\n" }
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
        - JSON должен быть полностью закрыт: все { } и [ ] должны быть сбалансированы
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

    private func buildV9EventTablePrompt(
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle,
        state: SceneChunkState?,
        slotCatalog: SceneV9SlotCatalog
    ) -> String {
        let stateContext = buildStateContext(state)
        let markedObjectsContext = buildMarkedObjectsContext(markedObjects)
        let anchorContext = buildAnchorContext(anchors)
        let slotCatalogJSON = encodePrettyJSON(slotCatalog) ?? "{}"

        return """
        <|im_start|>system
        Ты planner V9 slot-event. Верни ТОЛЬКО валидный JSON контракта sg_v9_event_table_v1.
        ПРАВИЛА:
        - используй только slot id из slotCatalog
        - не придумывай новые actor/object/beat слоты
        - actionType только из разрешённых actionTypes
        - если actionType=described_action, заполни describedActionText
        - если не уверен, оставь targetSlot пустым, но НЕ выдумывай слот
        - формат ответа: {"contractVersion":"sg_v9_event_table_v1","rows":[...]}
        <|im_end|>
        <|im_start|>user
        \(stateContext)\(markedObjectsContext)\(anchorContext)SLOT CATALOG JSON:
        \(slotCatalogJSON)

        SOURCE:
        \(description)
        <|im_end|>
        <|im_start|>assistant
        """
    }

    private func buildV9PatchPrompt(
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle,
        state: SceneChunkState?,
        slotCatalog: SceneV9SlotCatalog,
        eventTable: SceneV9EventTable,
        verifierIssues: [String]
    ) -> String {
        let stateContext = buildStateContext(state)
        let markedObjectsContext = buildMarkedObjectsContext(markedObjects)
        let anchorContext = buildAnchorContext(anchors)
        let slotCatalogJSON = encodePrettyJSON(slotCatalog) ?? "{}"
        let eventTableJSON = encodePrettyJSON(eventTable) ?? "{}"
        let issues = verifierIssues.joined(separator: "\n- ")

        return """
        <|im_start|>system
        Ты fixer V9. Верни ТОЛЬКО валидный JSON контракта sg_v9_patch_ops_v1.
        Разрешены операции: replace, add, delete.
        Меняй только поля существующего event table и только по списку verifier issues.
        Не меняй contractVersion. Не добавляй комментарии.
        <|im_end|>
        <|im_start|>user
        \(stateContext)\(markedObjectsContext)\(anchorContext)SLOT CATALOG JSON:
        \(slotCatalogJSON)

        EVENT TABLE JSON:
        \(eventTableJSON)

        VERIFIER ISSUES:
        - \(issues)

        SOURCE:
        \(description)
        <|im_end|>
        <|im_start|>assistant
        """
    }

    private func buildStateContext(_ state: SceneChunkState?) -> String {
        guard let state else { return "" }
        let actors = state.knownActors.map { "\($0.key) (id: \($0.value))" }.joined(separator: ", ")
        let objects = state.knownObjects.map { "\($0.key) (id: \($0.value))" }.joined(separator: ", ")
        let poses = state.actorPoses.map { "\($0.key)=\($0.value.rawValue)" }.joined(separator: ", ")
        let held = state.heldObjects.map { "\($0.key)->\($0.value)" }.joined(separator: ", ")
        let actorAliases = state.actorAliases.map { "\($0.key)->\($0.value)" }.joined(separator: ", ")
        let objectAliases = state.objectAliases.map { "\($0.key)->\($0.value)" }.joined(separator: ", ")

        var context = "Предыдущее состояние сцены:\n"
        if let sceneID = state.sceneID { context += "Scene ID: \(sceneID)\n" }
        if let heading = state.sceneHeading { context += "Scene heading: \(heading)\n" }
        if let loc = state.locationName { context += "Локация: \(loc)\n" }
        if !actors.isEmpty { context += "Известные персонажи: \(actors)\n" }
        if !objects.isEmpty { context += "Известные объекты: \(objects)\n" }
        if !actorAliases.isEmpty { context += "Actor alias map: \(actorAliases)\n" }
        if !objectAliases.isEmpty { context += "Object alias map: \(objectAliases)\n" }
        if !poses.isEmpty { context += "Позы актёров: \(poses)\n" }
        if !held.isEmpty { context += "Что кто держит: \(held)\n" }
        if let speaker = state.lastResolvedSpeaker { context += "Последний говорящий: \(speaker)\n" }
        context += "\n"
        return context
    }

    private func encodePrettyJSON<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func v9EventGenerationBudgets(
        for description: String,
        anchors: SourceAnchorBundle,
        slotCatalog: SceneV9SlotCatalog
    ) -> [Int32] {
        let estimated = Int32(description.count / 3)
            + 256
            + Int32(slotCatalog.beatSlots.count * 48)
            + Int32(slotCatalog.actorSlots.count * 20)
            + Int32(anchors.phaseCues.count * 12)
        let first = max(Self.v9EventTokenBudgets[0], min(estimated, Self.v9EventMaxGenerationTokens))

        var budgets = [first]
        for budget in Self.v9EventTokenBudgets {
            let normalized = min(max(budget, first), Self.v9EventMaxGenerationTokens)
            if !budgets.contains(normalized) {
                budgets.append(normalized)
            }
        }
        if budgets.last != Self.v9EventMaxGenerationTokens {
            budgets.append(Self.v9EventMaxGenerationTokens)
        }
        return budgets
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

    private func parseEventTableFromResponse(
        _ response: String,
        slotCatalog: SceneV9SlotCatalog
    ) -> SceneV9EventTable? {
        guard let extractedJSON = extractJSONPayload(from: response) else {
            print("❌ [LLM][V9] Не найден JSON EventTable")
            return nil
        }
        let candidates = makeJSONCandidates(from: extractedJSON)
        for (index, candidate) in candidates.enumerated() {
            do {
                let decoded = try decodeEventTable(from: candidate, slotCatalog: slotCatalog)
                print("✅ [LLM][V9] EventTable decoded [вариант \(index + 1)/\(candidates.count)], rows=\(decoded.rows.count)")
                return decoded
            } catch {
                print("⚠️ [LLM][V9] EventTable decode failed [вариант \(index + 1)/\(candidates.count)]: \(error)")
            }
        }
        return nil
    }

    private func parsePatchOpsFromResponse(_ response: String) -> SceneV9PatchOps? {
        guard let extractedJSON = extractJSONPayload(from: response) else {
            print("❌ [LLM][V9] Не найден JSON PatchOps")
            return nil
        }
        let candidates = makeJSONCandidates(from: extractedJSON)
        for (index, candidate) in candidates.enumerated() {
            do {
                let decoded = try decodePatchOps(from: candidate)
                print("✅ [LLM][V9] PatchOps decoded [вариант \(index + 1)/\(candidates.count)], ops=\(decoded.ops.count)")
                return decoded
            } catch {
                print("⚠️ [LLM][V9] PatchOps decode failed [вариант \(index + 1)/\(candidates.count)]: \(error)")
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

    private func decodeEventTable(from text: String, slotCatalog: SceneV9SlotCatalog) throws -> SceneV9EventTable {
        guard let data = text.data(using: .utf8) else {
            throw NSError(domain: "LLMParserService", code: 31, userInfo: [NSLocalizedDescriptionKey: "Не удалось конвертировать EventTable в Data"])
        }
        guard var jsonObj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "LLMParserService", code: 32, userInfo: [NSLocalizedDescriptionKey: "Корневой JSON event table не является объектом"])
        }

        if jsonObj["contractVersion"] == nil {
            jsonObj["contractVersion"] = "sg_v9_event_table_v1"
        }
        var rows = (jsonObj["rows"] as? [[String: Any]]) ?? []
        let defaultBeat = slotCatalog.beatSlots.first?.slotID ?? "beat_slot_1"
        let defaultActor = slotCatalog.actorSlots.first?.slotID ?? "actor_slot_1"

        for index in rows.indices {
            let existingRowID = (rows[index]["rowId"] as? String) ?? (rows[index]["rowID"] as? String)
            if existingRowID?.isEmpty != false {
                rows[index]["rowId"] = "row_\(index + 1)"
            } else if rows[index]["rowId"] == nil {
                rows[index]["rowId"] = existingRowID
            }
            if rows[index]["beatSlot"] == nil {
                rows[index]["beatSlot"] = defaultBeat
            }
            if rows[index]["actorSlot"] == nil {
                rows[index]["actorSlot"] = defaultActor
            }
            if rows[index]["actionType"] == nil {
                rows[index]["actionType"] = SceneAction.ActionType.stand.rawValue
            } else if let raw = rows[index]["actionType"] as? String,
                      SceneAction.ActionType(rawValue: raw) == nil {
                rows[index]["actionType"] = SceneAction.ActionType.describedAction.rawValue
                if rows[index]["describedActionText"] == nil {
                    rows[index]["describedActionText"] = rows[index]["sourceSpan"] as? String ?? "described_action"
                }
            }
        }
        jsonObj["rows"] = rows
        let fixedData = try JSONSerialization.data(withJSONObject: jsonObj)
        return try JSONDecoder().decode(SceneV9EventTable.self, from: fixedData)
    }

    private func decodePatchOps(from text: String) throws -> SceneV9PatchOps {
        guard let data = text.data(using: .utf8) else {
            throw NSError(domain: "LLMParserService", code: 33, userInfo: [NSLocalizedDescriptionKey: "Не удалось конвертировать PatchOps в Data"])
        }
        guard var jsonObj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "LLMParserService", code: 34, userInfo: [NSLocalizedDescriptionKey: "Корневой JSON patch ops не является объектом"])
        }

        if jsonObj["contractVersion"] == nil {
            jsonObj["contractVersion"] = "sg_v9_patch_ops_v1"
        }
        var ops = (jsonObj["ops"] as? [[String: Any]]) ?? []
        for index in ops.indices {
            if ops[index]["op"] == nil {
                ops[index]["op"] = SceneV9PatchOps.PatchOp.Operation.replace.rawValue
            }
            let existingRowID = (ops[index]["rowId"] as? String) ?? (ops[index]["rowID"] as? String)
            if existingRowID?.isEmpty != false {
                ops[index]["rowId"] = "row_\(index + 1)"
            } else if ops[index]["rowId"] == nil {
                ops[index]["rowId"] = existingRowID
            }
        }
        jsonObj["ops"] = ops

        let fixedData = try JSONSerialization.data(withJSONObject: jsonObj)
        return try JSONDecoder().decode(SceneV9PatchOps.self, from: fixedData)
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
                        action = replacingActionType(in: action, with: .run)
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
                    action = replacingActionType(in: action, with: .passBy)
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

    private func replacingActionType(in action: SceneAction, with type: SceneAction.ActionType) -> SceneAction {
        SceneAction(
            id: action.id,
            actorId: action.actorId,
            type: type,
            target: action.target,
            direction: action.direction,
            modifier: action.modifier,
            resultingPose: action.resultingPose,
            holdingObject: action.holdingObject,
            dialogue: action.dialogue,
            fallbackText: action.fallbackText,
            sourceText: action.sourceText
        )
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

    private func v9VerifierIssues(
        for eventTable: SceneV9EventTable,
        slotCatalog: SceneV9SlotCatalog
    ) -> [String] {
        let actorSlots = Set(slotCatalog.actorSlots.map(\.slotID))
        let objectSlots = Set(slotCatalog.objectSlots.map(\.slotID))
        let beatSlots = Set(slotCatalog.beatSlots.map(\.slotID))

        var issues: [String] = []
        for row in eventTable.rows {
            if !beatSlots.contains(row.beatSlot) {
                issues.append("row=\(row.rowID): unknown beatSlot=\(row.beatSlot)")
            }
            if !actorSlots.contains(row.actorSlot) {
                issues.append("row=\(row.rowID): unknown actorSlot=\(row.actorSlot)")
            }
            if let targetSlot = row.targetSlot,
               !targetSlot.isEmpty,
               !actorSlots.contains(targetSlot),
               !objectSlots.contains(targetSlot) {
                issues.append("row=\(row.rowID): unknown targetSlot=\(targetSlot)")
            }
            if let holdingSlot = row.holdingObjectSlot,
               !holdingSlot.isEmpty,
               !objectSlots.contains(holdingSlot) {
                issues.append("row=\(row.rowID): unknown holdingObjectSlot=\(holdingSlot)")
            }
            if Self.v9EventTargetRequiredTypes.contains(row.actionType),
               (row.targetSlot ?? "").isEmpty {
                issues.append("row=\(row.rowID): target required for actionType=\(row.actionType.rawValue)")
            }
            if row.actionType == .describedAction,
               (row.describedActionText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("row=\(row.rowID): describedActionText is required")
            }
        }

        return issues
    }

    private func applying(_ patchOps: SceneV9PatchOps, to table: SceneV9EventTable) -> SceneV9EventTable {
        var rows = table.rows
        for op in patchOps.ops {
            switch op.op {
            case .delete:
                rows.removeAll { $0.rowID == op.rowID }
            case .add:
                let defaultBeat = rows.first?.beatSlot ?? "beat_slot_1"
                let defaultActor = rows.first?.actorSlot ?? "actor_slot_1"
                guard let newRow = makeEventRowFromPatch(
                    op: op,
                    fallbackRowID: op.rowID,
                    defaultBeatSlot: defaultBeat,
                    defaultActorSlot: defaultActor
                ) else { continue }
                if !rows.contains(where: { $0.rowID == newRow.rowID }) {
                    rows.append(newRow)
                }
            case .replace:
                guard let index = rows.firstIndex(where: { $0.rowID == op.rowID }),
                      let field = op.field,
                      let value = op.value else {
                    continue
                }
                var row = rows[index]
                switch field {
                case "beatSlot":
                    row.beatSlot = value
                case "actorSlot":
                    row.actorSlot = value
                case "actionType":
                    if let action = SceneAction.ActionType(rawValue: value) {
                        row.actionType = action
                    }
                case "targetSlot":
                    row.targetSlot = value.isEmpty ? nil : value
                case "holdingObjectSlot":
                    row.holdingObjectSlot = value.isEmpty ? nil : value
                case "dialogueText":
                    row.dialogueText = value.isEmpty ? nil : value
                case "describedActionText":
                    row.describedActionText = value.isEmpty ? nil : value
                case "sourceSpan":
                    row.sourceSpan = value.isEmpty ? nil : value
                case "confidence":
                    row.confidence = Double(value)
                default:
                    continue
                }
                rows[index] = row
            }
        }
        return SceneV9EventTable(contractVersion: table.contractVersion, rows: rows)
    }

    private func makeEventRowFromPatch(
        op: SceneV9PatchOps.PatchOp,
        fallbackRowID: String,
        defaultBeatSlot: String,
        defaultActorSlot: String
    ) -> SceneV9EventTable.EventRow? {
        if let raw = op.value, let data = raw.data(using: .utf8) {
            if let decoded = try? JSONDecoder().decode(SceneV9EventTable.EventRow.self, from: data) {
                return decoded
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let beatSlot = json["beatSlot"] as? String,
               let actorSlot = json["actorSlot"] as? String,
               let actionRaw = json["actionType"] as? String,
               let actionType = SceneAction.ActionType(rawValue: actionRaw) {
                let rowID = ((json["rowId"] as? String) ?? (json["rowID"] as? String)).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackRowID
                return SceneV9EventTable.EventRow(
                    rowID: rowID,
                    beatSlot: beatSlot,
                    actorSlot: actorSlot,
                    actionType: actionType,
                    targetSlot: json["targetSlot"] as? String,
                    holdingObjectSlot: json["holdingObjectSlot"] as? String,
                    dialogueText: json["dialogueText"] as? String,
                    describedActionText: json["describedActionText"] as? String,
                    sourceSpan: json["sourceSpan"] as? String,
                    confidence: json["confidence"] as? Double
                )
            }
        }

        var row = SceneV9EventTable.EventRow(
            rowID: fallbackRowID,
            beatSlot: defaultBeatSlot,
            actorSlot: defaultActorSlot,
            actionType: .stand,
            targetSlot: nil,
            holdingObjectSlot: nil,
            dialogueText: nil,
            describedActionText: nil,
            sourceSpan: nil,
            confidence: 1.0
        )
        guard let field = op.field else {
            return row
        }
        switch field {
        case "beatSlot":
            row.beatSlot = op.value ?? row.beatSlot
        case "actorSlot":
            row.actorSlot = op.value ?? row.actorSlot
        case "actionType":
            if let value = op.value, let parsed = SceneAction.ActionType(rawValue: value) {
                row.actionType = parsed
            }
        case "targetSlot":
            row.targetSlot = op.value
        case "holdingObjectSlot":
            row.holdingObjectSlot = op.value
        case "dialogueText":
            row.dialogueText = op.value
        case "describedActionText":
            row.describedActionText = op.value
        case "sourceSpan":
            row.sourceSpan = op.value
        case "confidence":
            if let value = op.value, let parsed = Double(value) {
                row.confidence = parsed
            }
        default:
            break
        }
        return row
    }

    private func dedupeReasons(_ reasons: [String]) -> [String] {
        var seen = Set<String>()
        return reasons.filter { seen.insert($0).inserted }
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

    private func resolvePreferredModelPath() -> String? {
        if let overridePath = UserDefaults.standard.string(forKey: Self.modelPathOverrideDefaultsKey),
           FileManager.default.fileExists(atPath: overridePath) {
            print("🤖 [LLM] Используем модель из override path: \(overridePath)")
            return overridePath
        }

        let urls = discoverBundledGGUFModelURLs()
        let preferred = urls
            .map { ($0, modelSelectionScore(for: $0.lastPathComponent.lowercased())) }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.lastPathComponent < rhs.0.lastPathComponent
                }
                return lhs.1 > rhs.1
            }

        guard let selected = preferred.first, selected.1 > 0 else {
            return nil
        }

        print("🤖 [LLM] Автовыбор модели: \(selected.0.lastPathComponent)")
        return selected.0.path
    }

    private func discoverBundledGGUFModelURLs() -> [URL] {
        let bundleRoots = ([Bundle.main] + Bundle.allBundles + Bundle.allFrameworks)
            .compactMap(\.resourceURL)
        var seenPaths = Set<String>()
        var urls: [URL] = []

        for resourceRoot in bundleRoots {
            guard seenPaths.insert(resourceRoot.path).inserted else { continue }
            guard let enumerator = FileManager.default.enumerator(
                at: resourceRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension.lowercased() == "gguf" else { continue }
                urls.append(fileURL)
            }
        }

        return urls
    }

    private func modelSelectionScore(for filename: String) -> Int {
        var score = 0
        if filename.contains("v8") { score += 100 }
        if filename.contains("iter1") || filename.contains("orpo") { score += 40 }
        if filename.contains("qwen3") { score += 20 }
        if filename.contains("qwen2.5") { score -= 1000 }
        return score
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

    static let sceneV9EventTableGrammar: String = {
        let lines = [
            #"root ::= "{" ws "\"contractVersion\"" ws ":" ws "\"sg_v9_event_table_v1\"" ws "," ws "\"rows\"" ws ":" ws "[" ws row-list ws "]" ws "}""#,
            "",
            #"ws ::= ([ \t\n])*"#,
            "",
            #"row-list ::= row ("," ws row)* | """#,
            #"row ::= "{" ws "\"rowId\"" ws ":" ws id-string "," ws "\"beatSlot\"" ws ":" ws slot-string "," ws "\"actorSlot\"" ws ":" ws slot-string "," ws "\"actionType\"" ws ":" ws action-type row-target row-holding row-dialogue row-described row-source row-confidence ws "}""#,
            #"row-target ::= ("," ws "\"targetSlot\"" ws ":" ws nullable-slot) | """#,
            #"row-holding ::= ("," ws "\"holdingObjectSlot\"" ws ":" ws nullable-slot) | """#,
            #"row-dialogue ::= ("," ws "\"dialogueText\"" ws ":" ws nullable-text) | """#,
            #"row-described ::= ("," ws "\"describedActionText\"" ws ":" ws nullable-text) | """#,
            #"row-source ::= ("," ws "\"sourceSpan\"" ws ":" ws nullable-text) | """#,
            #"row-confidence ::= ("," ws "\"confidence\"" ws ":" ws number) | """#,
            "",
            #"action-type ::= "\"walk\"" | "\"run\"" | "\"approach\"" | "\"pass_by\"" | "\"enter\"" | "\"exit\"" | "\"stand\"" | "\"sit\"" | "\"lie_down\"" | "\"stop\"" | "\"turn\"" | "\"crouch\"" | "\"look_at\"" | "\"pick_up\"" | "\"put_down\"" | "\"open\"" | "\"close\"" | "\"give\"" | "\"talk\"" | "\"described_action\"""#,
            #"nullable-slot ::= slot-string | "null""#,
            #"nullable-text ::= text-string | "null""#,
            #"slot-string ::= "\"" [a-zA-Z0-9_]+ "\"""#,
            #"id-string ::= "\"" [a-zA-Z0-9_]+ "\"""#,
            #"text-string ::= "\"" ([^"\\] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]))* "\"""#,
            #"number ::= [0-9]+ ("." [0-9]+)?"#
        ]
        return lines.joined(separator: "\n")
    }()

    static let sceneV9PatchOpsGrammar: String = {
        let lines = [
            #"root ::= "{" ws "\"contractVersion\"" ws ":" ws "\"sg_v9_patch_ops_v1\"" ws "," ws "\"ops\"" ws ":" ws "[" ws op-list ws "]" ws "}""#,
            "",
            #"ws ::= ([ \t\n])*"#,
            "",
            #"op-list ::= op-entry ("," ws op-entry)* | """#,
            #"op-entry ::= "{" ws "\"op\"" ws ":" ws op-type "," ws "\"rowId\"" ws ":" ws id-string op-field op-value ws "}""#,
            #"op-type ::= "\"replace\"" | "\"add\"" | "\"delete\"""#,
            #"op-field ::= ("," ws "\"field\"" ws ":" ws text-string) | """#,
            #"op-value ::= ("," ws "\"value\"" ws ":" ws text-string) | """#,
            #"id-string ::= "\"" [a-zA-Z0-9_]+ "\"""#,
            #"text-string ::= "\"" ([^"\\] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]))* "\"""#
        ]
        return lines.joined(separator: "\n")
    }()
}
