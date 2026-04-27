//
//  MarkedObjectMatcher.swift
//  shafinMultitool
//
//  Created on 28.01.2026.
//

import Foundation

/// Ссылка на размеченный объект, найденный в тексте
struct MarkedObjectReference {
    let markerId: UUID
    let markerName: String
    let matchedText: String        // Как именно упомянуто в тексте
    let position: Range<String.Index>  // Позиция в тексте
}

/// Класс для сопоставления текста с размеченными объектами
final class MarkedObjectMatcher {
    
    private let lemmatizer: Lemmatizer
    
    init(lemmatizer: Lemmatizer) {
        self.lemmatizer = lemmatizer
    }
    
    // MARK: - Public API
    
    /// Находит все упоминания размеченных объектов в тексте
    /// - Parameters:
    ///   - text: Текст для поиска
    ///   - markedObjects: Список размеченных объектов
    /// - Returns: Массив ссылок на найденные объекты
    func findMarkedObjectReferences(
        in text: String,
        markedObjects: [MarkedObject]
    ) -> [MarkedObjectReference] {
        print("🔍 [MATCHER] Поиск упоминаний markedObjects в тексте: '\(text)'")
        print("🔍 [MATCHER] Размеченных объектов для поиска: \(markedObjects.count)")
        
        var references: [MarkedObjectReference] = []
        let lowercasedText = text.lowercased()
        
        for (index, marker) in markedObjects.enumerated() {
            print("🔍 [MATCHER] Проверка markedObject[\(index)]: name='\(marker.name)', type=\(marker.type.rawValue)")
            let markerName = marker.name.lowercased()
            let normalizedMarkerNames = normalizedSearchCandidates(for: markerName)
            
            // Ищем прямое упоминание имени маркера
            for candidate in normalizedMarkerNames {
                if let range = lowercasedText.range(of: candidate) {
                    print("🔍 [MATCHER]   Найдено прямое упоминание '\(candidate)'")
                    references.append(MarkedObjectReference(
                        markerId: marker.id,
                        markerName: marker.name,
                        matchedText: String(text[range]),
                        position: range
                    ))
                    break
                }
            }
            if references.last?.markerId == marker.id { continue }
            
            // Ищем через лемматизацию
            for candidate in normalizedMarkerNames {
                if lemmatizer.textContainsKeyword(lowercasedText, keyword: candidate) {
                    print("🔍 [MATCHER]   Найдено через лемматизацию '\(candidate)'")
                    // Находим точную позицию через поиск по словам
                    if let position = findWordPosition(in: lowercasedText, word: candidate) {
                        references.append(MarkedObjectReference(
                            markerId: marker.id,
                            markerName: marker.name,
                            matchedText: String(text[position]),
                            position: position
                        ))
                        break
                    }
                }
            }
            if references.last?.markerId == marker.id { continue }

            for candidate in normalizedMarkerNames {
                if let position = findMultiWordMarkerPosition(in: lowercasedText, markerName: candidate) {
                    print("🔍 [MATCHER]   Найдено по многословной лемме '\(candidate)'")
                    references.append(MarkedObjectReference(
                        markerId: marker.id,
                        markerName: marker.name,
                        matchedText: String(text[position]),
                        position: position
                    ))
                    break
                }
            }
            if references.last?.markerId == marker.id { continue }

            print("🔍 [MATCHER]   Не найдено упоминание '\(markerName)'")
            
            // Ищем с притяжательными местоимениями ("мой стол", "этот стол")
            let possessivePatterns = ["мой \(markerName)", "моя \(markerName)", "моё \(markerName)",
                                      "этот \(markerName)", "эта \(markerName)", "это \(markerName)",
                                      "тот \(markerName)", "та \(markerName)", "то \(markerName)"]
            
            for pattern in possessivePatterns {
                if lowercasedText.contains(pattern) {
                    if let range = lowercasedText.range(of: pattern) {
                        references.append(MarkedObjectReference(
                            markerId: marker.id,
                            markerName: marker.name,
                            matchedText: String(text[range]),
                            position: range
                        ))
                        break // Нашли одно упоминание, переходим к следующему маркеру
                    }
                }
            }
        }
        
        // Убираем дубликаты (если один маркер найден несколько раз, берём первое упоминание)
        var seenIds: Set<UUID> = []
        return references.filter { reference in
            if seenIds.contains(reference.markerId) {
                return false
            }
            seenIds.insert(reference.markerId)
            return true
        }
    }
    
    /// Проверяет, упоминается ли конкретный markedObject в тексте
    /// - Parameters:
    ///   - marker: Размеченный объект для проверки
    ///   - text: Текст для поиска
    /// - Returns: true, если объект упомянут в тексте
    func isMarkedObjectMentioned(
        _ marker: MarkedObject,
        in text: String
    ) -> Bool {
        let lowercasedText = text.lowercased()
        let markerName = marker.name.lowercased()
        
        // Прямое упоминание
        if lowercasedText.contains(markerName) {
            return true
        }
        
        // Через лемматизацию
        if lemmatizer.textContainsKeyword(lowercasedText, keyword: markerName) {
            return true
        }
        
        // С притяжательными местоимениями
        let possessivePatterns = ["мой \(markerName)", "моя \(markerName)", "моё \(markerName)",
                                  "этот \(markerName)", "эта \(markerName)", "это \(markerName)",
                                  "тот \(markerName)", "та \(markerName)", "то \(markerName)"]
        
        for pattern in possessivePatterns {
            if lowercasedText.contains(pattern) {
                return true
            }
        }
        
        return false
    }
    
    /// Находит объект по слову из текста (с учётом markedObjects)
    /// - Parameters:
    ///   - word: Слово из текста
    ///   - markedObjects: Список размеченных объектов
    /// - Returns: Найденный markedObject или nil
    func findMarkedObject(byWord word: String, in markedObjects: [MarkedObject]) -> MarkedObject? {
        let lowercasedWord = word.lowercased()
        
        for marker in markedObjects {
            let markerName = marker.name.lowercased()
            
            // Прямое совпадение
            if lowercasedWord == markerName {
                return marker
            }
            
            // Через лемматизацию
            if lemmatizer.matchesKeyword(lowercasedWord, keyword: markerName) {
                return marker
            }
            
            // Частичное совпадение (для случаев "мой стол" -> "стол")
            if lowercasedWord.contains(markerName) || markerName.contains(lowercasedWord) {
                return marker
            }
        }
        
        return nil
    }
    
    // MARK: - Private Helpers
    
    /// Находит позицию слова в тексте с учётом лемматизации
    private func findWordPosition(in text: String, word: String) -> Range<String.Index>? {
        let lowercasedText = text.lowercased()
        let wordLemma = lemmatizer.lemmatize(word)
        
        // Пробуем найти через простое совпадение
        if let range = lowercasedText.range(of: word) {
            return range
        }
        
        // Ищем по лемме (более сложно, нужно разбить текст на слова)
        let words = lowercasedText.split(separator: " ").map(String.init)
        var currentIndex = lowercasedText.startIndex
        
        for textWord in words {
            let textWordLemma = lemmatizer.lemmatize(textWord)
            if textWordLemma == wordLemma || lemmatizer.matchesKeyword(textWord, keyword: word) {
                let wordStart = currentIndex
                // Безопасно вычисляем конец слова
                guard let wordEnd = lowercasedText.index(currentIndex, offsetBy: textWord.count, limitedBy: lowercasedText.endIndex),
                      wordEnd <= lowercasedText.endIndex,
                      wordStart < wordEnd else { continue }
                return wordStart..<wordEnd
            }
            
            // Перемещаем индекс на следующее слово
            if let nextSpace = lowercasedText[currentIndex...].range(of: " ") {
                currentIndex = nextSpace.upperBound
                // Проверяем что не вышли за границы
                guard currentIndex <= lowercasedText.endIndex else { break }
            } else {
                break
            }
        }
        
        return nil
    }

    private func findMultiWordMarkerPosition(in text: String, markerName: String) -> Range<String.Index>? {
        let markerTokens = markerName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard markerTokens.count > 1 else { return nil }

        let textTokens = text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        let allTokensMatch = markerTokens.allSatisfy { markerToken in
            textTokens.contains { textToken in
                lemmatizer.matchesKeyword(textToken, keyword: markerToken)
                    || haveSharedStem(textToken, markerToken)
            }
        }
        guard allTokensMatch else { return nil }

        return findWordPosition(in: text, word: markerTokens[0])
    }

    private func haveSharedStem(_ lhs: String, _ rhs: String) -> Bool {
        let left = lemmatizer.lemmatize(lhs)
        let right = lemmatizer.lemmatize(rhs)
        guard left.count >= 3, right.count >= 3 else { return false }
        return String(left.prefix(3)) == String(right.prefix(3))
    }

    private func normalizedSearchCandidates(for markerName: String) -> [String] {
        let sanitized = markerName.replacingOccurrences(of: "_", with: " ")
        let tokens = sanitized.split(separator: " ").map(String.init)
        var candidates = [sanitized]
        if tokens.count > 1, ["мой", "моя", "моё", "мое", "наш", "наша", "этот", "эта", "тот", "та"].contains(tokens[0]) {
            candidates.append(tokens.dropFirst().joined(separator: " "))
        }
        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }
}
