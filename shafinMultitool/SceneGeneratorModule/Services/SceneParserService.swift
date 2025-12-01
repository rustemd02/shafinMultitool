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
    
    static let shared = SceneParserService()
    
    private let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma, .nameType])
    
    private init() {}
    
    // MARK: - Public API
    
    /// Парсит текстовое описание и возвращает структурированный SceneScript
    func parse(_ description: String) -> SceneScript {
        let lowercased = description.lowercased()
        
        // 1. Извлекаем актёров
        let actors = extractActors(from: lowercased)
        
        // 2. Извлекаем объекты
        let objects = extractObjects(from: lowercased)
        
        // 3. Извлекаем действия
        let actions = extractActions(from: lowercased, actors: actors, objects: objects)
        
        // 4. Извлекаем пространственные отношения
        let spatialRelations = extractSpatialRelations(from: lowercased, actors: actors, objects: objects)
        
        return SceneScript(
            actors: actors,
            objects: objects,
            actions: actions,
            spatialRelations: spatialRelations,
            originalDescription: description
        )
    }
    
    // MARK: - Actor Extraction
    
    private func extractActors(from text: String) -> [SceneActor] {
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
                    if let numberRange = Range(match.range(at: 1), in: text) {
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
        }
        
        // Ищем упоминания без чисел
        for (keyword, type) in KeywordsMapping.actorKeywords {
            // Пропускаем если уже обработали этот тип
            if processedTypes.contains(type) { continue }
            
            if text.contains(keyword) {
                // Проверяем что это не часть уже найденного паттерна с числом
                let hasNumberBefore = hasDigitBefore(keyword: keyword, in: text)
                
                if !hasNumberBefore {
                    actors.append(SceneActor(
                        id: "actor_\(actorCounter)",
                        type: type,
                        name: nil
                    ))
                    actorCounter += 1
                    processedTypes.insert(type)
                }
            }
        }
        
        // Если ничего не найдено, создаём одного актёра по умолчанию
        if actors.isEmpty {
            actors.append(SceneActor(id: "actor_1", type: .human, name: nil))
        }
        
        return actors
    }
    
    // MARK: - Object Extraction
    
    private func extractObjects(from text: String) -> [SceneObject] {
        var objects: [SceneObject] = []
        var objectCounter = 1
        var processedTypes: Set<SceneObject.ObjectType> = []
        
        for (keyword, type) in KeywordsMapping.objectKeywords {
            // Пропускаем если уже нашли этот тип объекта
            if processedTypes.contains(type) { continue }
            
            if text.contains(keyword) {
                let relativePosition = determineRelativePosition(for: keyword, in: text)
                
                let newObject = SceneObject(
                    id: "object_\(objectCounter)",
                    type: type,
                    detectedPosition: nil,
                    relativePosition: relativePosition
                )
                objects.append(newObject)
                objectCounter += 1
                processedTypes.insert(type)
            }
        }
        
        return objects
    }
    
    // MARK: - Action Extraction
    
    private func extractActions(
        from text: String,
        actors: [SceneActor],
        objects: [SceneObject]
    ) -> [SceneAction] {
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
            
            for match in matches {
                if match.numberOfRanges > 2,
                   let fromRange = Range(match.range(at: 1), in: text),
                   let toRange = Range(match.range(at: 2), in: text) {
                    let fromWord = String(text[fromRange])
                    let toWord = String(text[toRange])
                    
                    // Находим объекты
                    let fromObject = findMatchingObject(word: fromWord, objects: objects)
                    let toObject = findMatchingObject(word: toWord, objects: objects)
                    
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
                    if match.numberOfRanges > 1,
                       let objectRange = Range(match.range(at: 1), in: text) {
                        let objectWord = String(text[objectRange])
                        
                        // Находим соответствующий объект
                        if let targetObject = findMatchingObject(word: objectWord, objects: objects) {
                            let actionType: SceneAction.ActionType = preposition == "мимо" ? .passBy : .approach
                            
                            actions.append(SceneAction(
                                id: "action_\(actionCounter)",
                                actorId: actors.first?.id ?? "actor_1",
                                type: actionType,
                                target: targetObject.id,
                                direction: .toTarget,
                                modifier: extractModifier(from: text)
                            ))
                            actionCounter += 1
                        }
                    }
                }
            }
        }
        
        // Если не нашли комплексных паттернов, ищем простые действия
        if actions.isEmpty {
            for (keyword, actionType) in KeywordsMapping.actionKeywords {
                if text.contains(keyword) {
                    let direction = extractDirection(from: text)
                    let target = findTargetForAction(text: text, objects: objects)
                    
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
        actions = processOneAnotherConstruction(text: text, actors: actors, existingActions: actions, actionCounter: &actionCounter)
        
        return actions
    }
    
    // MARK: - Spatial Relations Extraction
    
    private func extractSpatialRelations(
        from text: String,
        actors: [SceneActor],
        objects: [SceneObject]
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
                    if match.numberOfRanges > 1,
                       let objectRange = Range(match.range(at: 1), in: text) {
                        let objectWord = String(text[objectRange])
                        
                        // Находим объект
                        if let targetObject = findMatchingObject(word: objectWord, objects: objects) {
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
        }
        
        return relations
    }
    
    // MARK: - Helper Methods
    
    private func hasDigitBefore(keyword: String, in text: String) -> Bool {
        if let range = text.range(of: keyword) {
            let beforeIndex = range.lowerBound
            if beforeIndex > text.startIndex {
                let startCheck = text.index(beforeIndex, offsetBy: -3, limitedBy: text.startIndex) ?? text.startIndex
                let beforeText = String(text[startCheck..<beforeIndex])
                return beforeText.contains(where: { $0.isNumber })
            }
        }
        return false
    }
    
    private func determineRelativePosition(for keyword: String, in text: String) -> SceneObject.RelativePosition {
        // Ищем контекст вокруг ключевого слова
        guard let range = text.range(of: keyword) else { return .unknown }
        
        let startIndex = text.index(range.lowerBound, offsetBy: -30, limitedBy: text.startIndex) ?? text.startIndex
        let endIndex = text.index(range.upperBound, offsetBy: 30, limitedBy: text.endIndex) ?? text.endIndex
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
            if text.contains(keyword) {
                return modifier
            }
        }
        return nil
    }
    
    private func extractDirection(from text: String) -> SceneAction.Direction? {
        // Проверяем комплексные направления
        if text.contains("навстречу") || text.contains("друг к другу") || text.contains("друг на друга") {
            return .towardEachOther
        }
        if text.contains("друг от друга") {
            return .awayFromEachOther
        }
        
        // Простые направления
        for (keyword, direction) in KeywordsMapping.directionKeywords {
            if text.contains(keyword) {
                return direction
            }
        }
        return nil
    }
    
    private func findTargetForAction(text: String, objects: [SceneObject]) -> String? {
        // Ищем "к <объекту>" или "мимо <объекта>"
        for object in objects {
            for (keyword, _) in KeywordsMapping.objectKeywords where KeywordsMapping.objectKeywords[keyword] == object.type {
                // Проверяем паттерны типа "к столу", "мимо шкафа"
                let patterns = ["к \(keyword)", "ко \(keyword)", "мимо \(keyword)", "около \(keyword)"]
                for pattern in patterns {
                    if text.contains(pattern) {
                        return object.id
                    }
                }
            }
        }
        return nil
    }
    
    private func findMatchingObject(word: String, objects: [SceneObject]) -> SceneObject? {
        // Ищем объект по ключевому слову
        if let objectType = KeywordsMapping.objectKeywords[word.lowercased()] {
            return objects.first { $0.type == objectType }
        }
        
        // Пытаемся найти частичное совпадение
        for object in objects {
            for (keyword, type) in KeywordsMapping.objectKeywords where type == object.type {
                if word.lowercased().hasPrefix(keyword.prefix(3)) {
                    return object
                }
            }
        }
        
        return nil
    }
    
    private func determineActorForAction(text: String, actors: [SceneActor], actionPattern: String) -> String {
        // Для паттернов типа "один поворачивает направо" - определяем по контексту
        if text.contains("один") && text.contains("друг") {
            // Это "один ... другой" конструкция
            // Определяем какой актёр к какому действию
            if let patternRange = text.range(of: actionPattern, options: .regularExpression) {
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
                if match.numberOfRanges > 1,
                   let firstRange = Range(match.range(at: 1), in: text) {
                    let firstActionText = String(text[firstRange])
                    
                    if let action = parseSimpleAction(from: firstActionText, actorId: actors[0].id, actionId: "action_\(actionCounter)") {
                        // Удаляем дубликаты если есть
                        actions.removeAll { $0.actorId == actors[0].id && $0.type == action.type }
                        actions.append(action)
                        actionCounter += 1
                    }
                }
                
                // Действие второго актёра
                if match.numberOfRanges > 2,
                   let secondRange = Range(match.range(at: 2), in: text) {
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

