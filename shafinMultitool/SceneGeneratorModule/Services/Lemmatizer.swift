//
//  Lemmatizer.swift
//  shafinMultitool
//
//  Created on 28.01.2026.
//

import Foundation
import NaturalLanguage

/// Утилита для нормализации слов через лемматизацию
/// Приводит слова к их базовой форме (столу -> стол, идёт -> идти)
final class Lemmatizer {
    
    private let tagger: NLTagger
    
    init() {
        tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
    }
    
    // MARK: - Public API
    
    /// Приводит слово к лемме (столу -> стол, идёт -> идти)
    /// - Parameter word: Слово для нормализации
    /// - Returns: Лемма слова или исходное слово, если лемматизация не удалась
    func lemmatize(_ word: String) -> String {
        guard !word.isEmpty else { return word }
        
        let lowercasedWord = word.lowercased()
        tagger.string = lowercasedWord
        
        // Используем безопасный подход: проверяем границы перед использованием
        guard !lowercasedWord.isEmpty else { return lowercasedWord }
        
        let range = lowercasedWord.startIndex..<lowercasedWord.endIndex
        var lemmatizedWord = lowercasedWord
        
        tagger.enumerateTags(in: range, unit: .word, scheme: .lemma) { tag, tokenRange in
            // Безопасная проверка границ Range<String.Index>
            guard tokenRange.lowerBound >= lowercasedWord.startIndex,
                  tokenRange.upperBound <= lowercasedWord.endIndex,
                  tokenRange.lowerBound < tokenRange.upperBound else {
                return false
            }
            
            // Безопасное извлечение слова
            guard tokenRange.lowerBound < lowercasedWord.endIndex,
                  tokenRange.upperBound <= lowercasedWord.endIndex else {
                return false
            }
            
            if let lemma = tag?.rawValue, !lemma.isEmpty {
                lemmatizedWord = lemma.lowercased()
            }
            return false // Останавливаемся после первого слова
        }
        
        // Fallback: если лемматизация не дала результата, пробуем найти корень через префиксы
        if lemmatizedWord == lowercasedWord {
            // Для русских слов пробуем убрать окончания
            let commonEndings = ["у", "ом", "е", "а", "ы", "ов", "ам", "ами", "ах", "ём", "ёт", "ут", "ют", "ит", "ал", "ел", "ил"]
            for ending in commonEndings {
                if lowercasedWord.hasSuffix(ending) && lowercasedWord.count > ending.count {
                    let potentialRoot = String(lowercasedWord.dropLast(ending.count))
                    if potentialRoot.count >= 2 { // Минимальная длина корня
                        return potentialRoot
                    }
                }
            }
        }
        
        return lemmatizedWord
    }
    
    /// Приводит весь текст к леммам
    /// - Parameter text: Текст для нормализации
    /// - Returns: Текст с лемматизированными словами
    func lemmatizeText(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        
        let lowercasedText = text.lowercased()
        tagger.string = lowercasedText
        
        var lemmatizedParts: [String] = []
        let range = lowercasedText.startIndex..<lowercasedText.endIndex
        let nsString = lowercasedText as NSString
        
        tagger.enumerateTags(in: range, unit: .word, scheme: .lemma) { tag, tokenRange in
            // Безопасная проверка границ Range<String.Index>
            guard tokenRange.lowerBound >= lowercasedText.startIndex,
                  tokenRange.upperBound <= lowercasedText.endIndex,
                  tokenRange.lowerBound < tokenRange.upperBound else {
                return true
            }
            
            // Безопасное извлечение слова
            let originalWord = String(lowercasedText[tokenRange])
            guard !originalWord.isEmpty else {
                return true
            }
            
            if let lemma = tag?.rawValue, !lemma.isEmpty {
                lemmatizedParts.append(lemma.lowercased())
            } else {
                // Fallback: используем lemmatize для отдельного слова
                lemmatizedParts.append(self.lemmatize(originalWord))
            }
            return true // Продолжаем обработку
        }
        
        return lemmatizedParts.joined(separator: " ")
    }
    
    /// Проверяет, является ли слово формой ключевого слова (с учётом лемматизации)
    /// - Parameters:
    ///   - word: Проверяемое слово
    ///   - keyword: Ключевое слово для сравнения
    /// - Returns: true, если слова совпадают после лемматизации
    func matchesKeyword(_ word: String, keyword: String) -> Bool {
        let lowercasedWord = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedKeyword = keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Прямое совпадение исходных слов
        if lowercasedWord == lowercasedKeyword {
            return true
        }
        
        // Лемматизация
        let wordLemma = lemmatize(lowercasedWord)
        let keywordLemma = lemmatize(lowercasedKeyword)
        
        // Прямое совпадение лемм
        if wordLemma == keywordLemma {
            return true
        }
        
        // НЕ используем contains для избежания ложных срабатываний (например, "кот" в "актера")
        // Только точное совпадение лемм или проверка на общий корень (минимум 4 символа)
        let minRootLength = 4
        if wordLemma.count >= minRootLength && keywordLemma.count >= minRootLength {
            let wordRoot = String(wordLemma.prefix(minRootLength))
            let keywordRoot = String(keywordLemma.prefix(minRootLength))
            
            if wordRoot == keywordRoot {
                return true
            }
        }
        
        return false
    }
    
    /// Проверяет, содержит ли текст ключевое слово (с учётом лемматизации)
    /// ВАЖНО: проверяет только ЦЕЛЫЕ слова, не подстроки
    /// - Parameters:
    ///   - text: Текст для поиска
    ///   - keyword: Ключевое слово
    /// - Returns: true, если текст содержит ключевое слово в любой форме
    func textContainsKeyword(_ text: String, keyword: String) -> Bool {
        guard !text.isEmpty && !keyword.isEmpty else { return false }
        
        let lowercasedText = text.lowercased()
        let keywordLowercased = keyword.lowercased()
        
        // Разбиваем текст на слова (только целые слова, не подстроки)
        let words = lowercasedText.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        
        for word in words {
            // Проверяем прямое совпадение
            if word == keywordLowercased {
                return true
            }
            
            // Проверяем через matchesKeyword (который использует лемматизацию и НЕ использует contains)
            if matchesKeyword(word, keyword: keyword) {
                return true
            }
        }
        
        // Дополнительная проверка: лемматизируем весь текст и ищем лемму ключевого слова
        // Это более безопасный подход, чем использование NLTagger.enumerateTags
        let textWords = lowercasedText.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let keywordLemma = lemmatize(keywordLowercased)
        
        for textWord in textWords {
            let textWordLemma = lemmatize(textWord)
            if textWordLemma == keywordLemma {
                return true
            }
        }
        
        return false
    }
}
