//
//  LlamaContext.swift
//  shafinMultitool
//
//  Created on 13.03.2026.
//

import Foundation
import llama

/// Swift-обёртка для llama.cpp C API
/// Инкапсулирует загрузку модели, токенизацию и генерацию текста
actor LlamaContext {
    struct GenerationOutput {
        enum StopReason: String {
            case endOfGeneration = "eog"
            case maxTokensReached = "max_tokens_reached"
        }

        let text: String
        let generatedTokenCount: Int32
        let maxTokens: Int32
        let stopReason: StopReason
    }
    
    private var model: OpaquePointer
    private var context: OpaquePointer
    private var vocab: OpaquePointer
    private var sampling: UnsafeMutablePointer<llama_sampler>
    private var batch: llama_batch
    private var tokensList: [llama_token]
    private var temporaryInvalidCChars: [CChar]
    
    private(set) var isDone: Bool = false
    
    /// Максимальное количество токенов для генерации
    var maxTokens: Int32 = 512
    
    /// Текущая позиция в последовательности
    private var nCur: Int32 = 0
    /// Количество сгенерированных токенов (без токенов промпта)
    private var generatedTokens: Int32 = 0
    /// Причина остановки последней генерации
    private var stopReason: GenerationOutput.StopReason?
    
    // MARK: - Initialization
    
    private init(model: OpaquePointer, context: OpaquePointer, temperature: Float = 0.1, grammarStr: String? = nil) {
        self.model = model
        self.context = context
        self.tokensList = []
        self.batch = llama_batch_init(4096, 0, 1)
        self.temporaryInvalidCChars = []
        self.vocab = llama_model_get_vocab(model)
        
        // Настройка сэмплера для JSON-генерации
        let sparams = llama_sampler_chain_default_params()
        self.sampling = llama_sampler_chain_init(sparams)
        // GBNF Grammar — физически ограничивает вывод только валидным JSON
        if let grammar = grammarStr {
            let grammarSampler = llama_sampler_init_grammar(vocab, grammar, "root")
            if let sampler = grammarSampler {
                llama_sampler_chain_add(self.sampling, sampler)
                print("✅ [LLM] GBNF grammar сэмплер добавлен")
            } else {
                print("⚠️ [LLM] Не удалось создать grammar сэмплер, работаем без него")
            }
        }
        // Top-K sampling (k=20)
        llama_sampler_chain_add(self.sampling, llama_sampler_init_top_k(20))
        // Repetition penalty
        llama_sampler_chain_add(self.sampling, llama_sampler_init_penalties(
            64, 1.3, 0.0, 0.0
        ))
        llama_sampler_chain_add(self.sampling, llama_sampler_init_temp(temperature))
        llama_sampler_chain_add(self.sampling, llama_sampler_init_dist(1234))
    }
    
    deinit {
        llama_sampler_free(sampling)
        llama_batch_free(batch)
        llama_model_free(model)
        llama_free(context)
        llama_backend_free()
    }
    
    // MARK: - Factory
    
    /// Создаёт контекст из файла модели
    /// - Parameters:
    ///   - path: Путь к GGUF файлу модели
    ///   - temperature: Температура генерации (0.1 = почти детерминированная)
    /// - Returns: Инициализированный LlamaContext
    static func create(modelPath path: String, temperature: Float = 0.1, grammarStr: String? = nil) throws -> LlamaContext {
        llama_backend_init()
        
        var modelParams = llama_model_default_params()
        
        #if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
        print("🤖 [LLM] Запуск на симуляторе, GPU отключён")
        #else
        modelParams.n_gpu_layers = 99 // Все слои на GPU (Metal)
        print("🤖 [LLM] GPU слоёв: 99 (Metal)")
        #endif
        
        guard let model = llama_model_load_from_file(path, modelParams) else {
            print("❌ [LLM] Не удалось загрузить модель: \(path)")
            throw LlamaContextError.modelLoadFailed
        }
        
        let nThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        print("🤖 [LLM] Потоков: \(nThreads)")
        
        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = 2048
        ctxParams.n_threads = Int32(nThreads)
        ctxParams.n_threads_batch = Int32(nThreads)
        
        guard let context = llama_init_from_model(model, ctxParams) else {
            llama_model_free(model)
            print("❌ [LLM] Не удалось создать контекст")
            throw LlamaContextError.contextCreationFailed
        }
        
        print("✅ [LLM] Модель загружена успешно")
        return LlamaContext(model: model, context: context, temperature: temperature, grammarStr: grammarStr)
    }
    
    // MARK: - Public API
    
    /// Генерирует текст по промпту (полный цикл)
    /// - Parameters:
    ///   - prompt: Входной текст
    ///   - maxTokens: Максимальное количество токенов (по умолчанию 512)
    /// - Returns: Сгенерированный текст
    func generate(prompt: String, maxTokens: Int32 = 512) -> String {
        let output = generateWithMetadata(prompt: prompt, maxTokens: maxTokens)
        return output.text
    }

    /// Генерирует текст и возвращает метаданные остановки
    func generateWithMetadata(prompt: String, maxTokens: Int32 = 512) -> GenerationOutput {
        self.maxTokens = maxTokens

        // Инициализируем промпт
        completionInit(text: prompt)
        
        // Генерируем токены
        var result = ""
        while !isDone {
            let piece = completionLoop()
            result += piece
        }

        let output = GenerationOutput(
            text: result,
            generatedTokenCount: generatedTokens,
            maxTokens: maxTokens,
            stopReason: stopReason ?? .endOfGeneration
        )

        // Сброс для повторного использования
        clear()

        return output
    }
    
    /// Информация о модели
    func modelInfo() -> String {
        let buf = UnsafeMutablePointer<Int8>.allocate(capacity: 256)
        buf.initialize(repeating: 0, count: 256)
        defer { buf.deallocate() }
        
        let n = llama_model_desc(model, buf, 256)
        let bufferPointer = UnsafeBufferPointer(start: buf, count: Int(n))
        return String(bufferPointer.map { Character(UnicodeScalar(UInt8($0))) })
    }
    
    // MARK: - Private: Completion
    
    private func completionInit(text: String) {
        isDone = false
        tokensList = tokenize(text: text, addBos: true)
        temporaryInvalidCChars = []
        generatedTokens = 0
        stopReason = nil
        // Samplers are stateful in llama.cpp. In particular, grammar and
        // repetition samplers must be reset between independent prompts,
        // otherwise a previous EOG can make the next call return 0 tokens.
        llama_sampler_reset(sampling)
        llama_memory_clear(llama_get_memory(context), true)

        llama_batch_clear(&batch)
        
        for (i, token) in tokensList.enumerated() {
            llama_batch_add(&batch, token, Int32(i), [0], false)
        }
        // Помечаем последний токен для вычисления logits
        batch.logits[Int(batch.n_tokens) - 1] = 1
        
        if llama_decode(context, batch) != 0 {
            print("❌ [LLM] llama_decode() failed при инициализации")
        }
        
        nCur = batch.n_tokens
    }
    
    private func completionLoop() -> String {
        if generatedTokens >= maxTokens {
            isDone = true
            stopReason = .maxTokensReached
            let str = String(cString: temporaryInvalidCChars + [0])
            temporaryInvalidCChars.removeAll()
            return str
        }

        let newTokenId = llama_sampler_sample(sampling, context, batch.n_tokens - 1)

        // Проверяем конец генерации
        if llama_vocab_is_eog(vocab, newTokenId) {
            isDone = true
            stopReason = .endOfGeneration
            let str = String(cString: temporaryInvalidCChars + [0])
            temporaryInvalidCChars.removeAll()
            return str
        }
        
        let newTokenCChars = tokenToPiece(token: newTokenId)
        temporaryInvalidCChars.append(contentsOf: newTokenCChars)
        
        let newTokenStr: String
        if let string = String(validatingUTF8: temporaryInvalidCChars + [0]) {
            temporaryInvalidCChars.removeAll()
            newTokenStr = string
        } else if (0 ..< temporaryInvalidCChars.count).contains(where: {
            $0 != 0 && String(validatingUTF8: Array(temporaryInvalidCChars.suffix($0)) + [0]) != nil
        }) {
            let string = String(cString: temporaryInvalidCChars + [0])
            temporaryInvalidCChars.removeAll()
            newTokenStr = string
        } else {
            newTokenStr = ""
        }
        
        // Подготовка следующего шага
        llama_batch_clear(&batch)
        llama_batch_add(&batch, newTokenId, nCur, [0], true)

        nCur += 1
        generatedTokens += 1
        if generatedTokens >= maxTokens {
            isDone = true
            stopReason = .maxTokensReached
        }

        if llama_decode(context, batch) != 0 {
            print("❌ [LLM] llama_decode() failed при генерации")
        }
        
        return newTokenStr
    }
    
    private func clear() {
        tokensList.removeAll()
        temporaryInvalidCChars.removeAll()
        isDone = false
        generatedTokens = 0
        stopReason = nil
        llama_sampler_reset(sampling)
        llama_memory_clear(llama_get_memory(context), true)
    }
    
    // MARK: - Private: Tokenization
    
    private func tokenize(text: String, addBos: Bool) -> [llama_token] {
        let utf8Count = text.utf8.count
        let nTokens = utf8Count + (addBos ? 1 : 0) + 1
        let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: nTokens)
        let tokenCount = llama_tokenize(vocab, text, Int32(utf8Count), tokens, Int32(nTokens), addBos, false)
        
        var swiftTokens: [llama_token] = []
        for i in 0..<tokenCount {
            swiftTokens.append(tokens[Int(i)])
        }
        tokens.deallocate()
        
        return swiftTokens
    }
    
    private func tokenToPiece(token: llama_token) -> [CChar] {
        let buf = UnsafeMutablePointer<Int8>.allocate(capacity: 8)
        buf.initialize(repeating: 0, count: 8)
        defer { buf.deallocate() }
        
        let n = llama_token_to_piece(vocab, token, buf, 8, 0, false)
        
        if n < 0 {
            let newBuf = UnsafeMutablePointer<Int8>.allocate(capacity: Int(-n))
            newBuf.initialize(repeating: 0, count: Int(-n))
            defer { newBuf.deallocate() }
            let nNew = llama_token_to_piece(vocab, token, newBuf, -n, 0, false)
            return Array(UnsafeBufferPointer(start: newBuf, count: Int(nNew)))
        } else {
            return Array(UnsafeBufferPointer(start: buf, count: Int(n)))
        }
    }
}

// MARK: - Batch Helpers

private func llama_batch_clear(_ batch: inout llama_batch) {
    batch.n_tokens = 0
}

private func llama_batch_add(_ batch: inout llama_batch, _ id: llama_token, _ pos: llama_pos, _ seqIds: [llama_seq_id], _ logits: Bool) {
    let n = Int(batch.n_tokens)
    batch.token   [n] = id
    batch.pos     [n] = pos
    batch.n_seq_id[n] = Int32(seqIds.count)
    if let seqIdRow = batch.seq_id[n] {
        for i in 0..<seqIds.count {
            seqIdRow[i] = seqIds[i]
        }
    }
    batch.logits  [n] = logits ? 1 : 0
    batch.n_tokens += 1
}

// MARK: - Errors

enum LlamaContextError: Error, LocalizedError {
    case modelLoadFailed
    case contextCreationFailed
    case modelNotFound
    
    var errorDescription: String? {
        switch self {
        case .modelLoadFailed:
            return "Не удалось загрузить GGUF модель"
        case .contextCreationFailed:
            return "Не удалось создать контекст llama.cpp"
        case .modelNotFound:
            return "GGUF модель не найдена в бандле приложения"
        }
    }
}
