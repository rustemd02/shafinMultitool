//
//  DiagnosticsCalculator.swift
//  shafinMultitool
//
//  Created on 28.01.2026.
//

import Foundation
import NaturalLanguage

/// Класс для вычисления метрик качества парсинга
final class DiagnosticsCalculator {
    
    private let lemmatizer = Lemmatizer()
    private let tagger = NLTagger(tagSchemes: [.lexicalClass])
    
    // MARK: - Public API
    
    /// Вычисляет диагностику на основе результатов парсинга
    /// - Parameters:
    ///   - script: Распарсенный скрипт
    ///   - originalText: Оригинальный текст описания
    ///   - markedObjects: Размеченные объекты
    ///   - matchedMarkedObjects: ID размеченных объектов, которые были распознаны
    /// - Returns: Диагностика парсинга
    func calculateDiagnostics(
        script: SceneScript,
        originalText: String,
        markedObjects: [MarkedObject],
        matchedMarkedObjects: [UUID]
    ) -> ParsingDiagnostics {
        print("🔍 [DIAGNOSTICS] === НАЧАЛО ВЫЧИСЛЕНИЯ ДИАГНОСТИКИ ===")
        print("🔍 [DIAGNOSTICS] Script: actors=\(script.actors.count), objects=\(script.objects.count), actions=\(script.actions.count)")
        print("🔍 [DIAGNOSTICS] OriginalText: '\(originalText)'")
        print("🔍 [DIAGNOSTICS] MarkedObjects: \(markedObjects.count), matchedMarkedObjects: \(matchedMarkedObjects.count)")
        
        var notes: [String] = []
        var confidence: Float = 0.5 // Базовая уверенность
        var coverage: Float = 0.0
        var missingActors = false
        var missingObjects = false
        var unresolvedPronouns = false
        var unresolvedMarkedObjects = false
        
        // 1. Проверяем наличие актёров
        if script.actors.isEmpty {
            print("🔍 [DIAGNOSTICS] ⚠️ Актёры не найдены")
            confidence -= 0.2
            notes.append("Не найдено актёров")
        } else {
            print("🔍 [DIAGNOSTICS] Найдено актёров: \(script.actors.count)")
            confidence += Float(min(script.actors.count, 3)) * 0.1 // Бонус за актёров
        }
        
        // 2. Проверяем наличие объектов
        if script.objects.isEmpty {
            print("🔍 [DIAGNOSTICS] ⚠️ Объекты не найдены")
            confidence -= 0.15
            notes.append("Не найдено объектов")
        } else {
            print("🔍 [DIAGNOSTICS] Найдено объектов: \(script.objects.count)")
            confidence += Float(min(script.objects.count, 5)) * 0.05 // Бонус за объекты
        }
        
        // 3. Проверяем наличие действий
        if script.actions.isEmpty {
            confidence -= 0.1
            notes.append("Не найдено действий")
        } else {
            confidence += Float(min(script.actions.count, 5)) * 0.05 // Бонус за действия
        }
        
        // 4. Проверяем missingActors: есть действия, но нет актёров
        if !script.actions.isEmpty && script.actors.isEmpty {
            print("🔍 [DIAGNOSTICS] ⚠️ missingActors: есть действия (\(script.actions.count)), но нет актёров")
            missingActors = true
            confidence -= 0.15
            notes.append("Найдены действия, но нет актёров")
        }
        
        // 5. Проверяем missingObjects: есть ссылки на объекты в действиях, но объекты не найдены
        let actionTargets = script.actions.compactMap { $0.target }
        let objectIds = Set(script.objects.map { $0.id })
        let missingTargets = actionTargets.filter { !objectIds.contains($0) }
        if !missingTargets.isEmpty {
            print("🔍 [DIAGNOSTICS] ⚠️ missingObjects: найдены ссылки на несуществующие объекты: \(missingTargets.joined(separator: ", "))")
            missingObjects = true
            confidence -= 0.1
            notes.append("Действия ссылаются на несуществующие объекты: \(missingTargets.joined(separator: ", "))")
        }
        
        // 6. Проверяем unresolvedPronouns: поиск "он/она/другой/первый/второй" без явной привязки
        let pronounPatterns = ["он", "она", "оно", "они", "другой", "другая", "другое", "другие",
                              "первый", "первая", "первое", "первые",
                              "второй", "вторая", "второе", "вторые",
                              "третий", "третья", "третье", "третьи"]
        let lowercasedText = originalText.lowercased()
        var foundPronouns: [String] = []
        for pronoun in pronounPatterns {
            if lowercasedText.contains(pronoun) {
                foundPronouns.append(pronoun)
            }
        }
        
        // Если есть местоимения, но недостаточно актёров для их разрешения
        if !foundPronouns.isEmpty && script.actors.count < 2 {
            unresolvedPronouns = true
            confidence -= 0.1
            notes.append("Найдены местоимения (\(foundPronouns.joined(separator: ", "))), но недостаточно актёров для разрешения")
        }
        
        // 7. Проверяем unresolvedMarkedObjects: есть markedObjects, имена которых упомянуты в тексте, но не распознаны
        let matchedIds = Set(matchedMarkedObjects)
        for marker in markedObjects {
            if !matchedIds.contains(marker.id) {
                // Проверяем, упоминается ли имя маркера в тексте
                let markerName = marker.name.lowercased()
                if lemmatizer.textContainsKeyword(lowercasedText, keyword: markerName) ||
                   lowercasedText.contains(markerName) {
                    unresolvedMarkedObjects = true
                    confidence -= 0.05
                    notes.append("Объект '\(marker.name)' упомянут, но не распознан")
                }
            }
        }
        
        // 8. Вычисляем coverage: процент распознанных существительных/глаголов
        coverage = calculateCoverage(text: originalText, script: script)
        
        // 9. Нормализуем confidence в диапазон 0.0...1.0
        confidence = max(0.0, min(1.0, confidence))
        
        // 10. Если всё хорошо, добавляем положительную заметку
        if confidence >= 0.7 && notes.isEmpty {
            notes.append("Парсинг выполнен успешно")
        }
        
        print("🔍 [DIAGNOSTICS] Итоговая диагностика: confidence=\(String(format: "%.2f", confidence)), coverage=\(String(format: "%.2f", coverage))")
        print("🔍 [DIAGNOSTICS] Флаги: missingActors=\(missingActors ? 1 : 0), missingObjects=\(missingObjects ? 1 : 0), unresolvedPronouns=\(unresolvedPronouns ? 1 : 0), unresolvedMarkedObjects=\(unresolvedMarkedObjects ? 1 : 0)")
        if !notes.isEmpty {
            print("🔍 [DIAGNOSTICS] Заметки: \(notes.joined(separator: "; "))")
        }
        print("🔍 [DIAGNOSTICS] === ВЫЧИСЛЕНИЕ ДИАГНОСТИКИ ЗАВЕРШЕНО ===")
        
        return ParsingDiagnostics(
            confidence: confidence,
            coverage: coverage,
            missingActors: missingActors,
            missingObjects: missingObjects,
            unresolvedPronouns: unresolvedPronouns,
            unresolvedMarkedObjects: unresolvedMarkedObjects,
            notes: notes,
            matchedMarkedObjects: matchedMarkedObjects
        )
    }
    
    // MARK: - Private Helpers
    
    /// Вычисляет покрытие текста (сколько слов распознано)
    private func calculateCoverage(text: String, script: SceneScript) -> Float {
        guard !text.isEmpty else { return 0.0 }
        
        tagger.string = text.lowercased()
        let range = text.startIndex..<text.endIndex
        
        var totalNouns = 0
        var totalVerbs = 0
        var recognizedNouns = 0
        var recognizedVerbs = 0
        
        // Собираем все ключевые слова для проверки
        let allObjectKeywords = Set(KeywordsMapping.objectKeywords.keys)
        let allActorKeywords = Set(KeywordsMapping.actorKeywords.keys)
        let allActionKeywords = Set(KeywordsMapping.actionKeywords.keys)
        
        tagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass) { tag, tokenRange in
            guard let lexicalClass = tag else { return true }
            let word = String(text[tokenRange]).lowercased()
            let wordLemma = lemmatizer.lemmatize(word)
            
            switch lexicalClass {
            case .noun:
                totalNouns += 1
                // Проверяем, распознано ли это существительное
                if allObjectKeywords.contains(word) || allObjectKeywords.contains(wordLemma) ||
                   allActorKeywords.contains(word) || allActorKeywords.contains(wordLemma) ||
                   script.objects.contains(where: { lemmatizer.matchesKeyword(word, keyword: $0.type.rawValue) }) {
                    recognizedNouns += 1
                }
            case .verb:
                totalVerbs += 1
                // Проверяем, распознан ли этот глагол
                if allActionKeywords.contains(word) || allActionKeywords.contains(wordLemma) {
                    recognizedVerbs += 1
                }
            default:
                break
            }
            
            return true
        }
        
        // Вычисляем coverage как среднее между покрытием существительных и глаголов
        let nounCoverage = totalNouns > 0 ? Float(recognizedNouns) / Float(totalNouns) : 0.0
        let verbCoverage = totalVerbs > 0 ? Float(recognizedVerbs) / Float(totalVerbs) : 0.0
        
        if totalNouns == 0 && totalVerbs == 0 {
            return 0.0
        }
        
        return (nounCoverage + verbCoverage) / 2.0
    }
}
