//
//  SceneScript.swift
//  shafinMultitool
//
//  Created on 30.11.2025.
//

import Foundation
import simd
import UIKit

// MARK: - Marked Object (User-placed real world marker)

/// Объект, размеченный пользователем вручную в реальном пространстве
struct MarkedObject: Identifiable, Equatable {
    let id: UUID
    var name: String                    // Название объекта (шкаф, стол и т.д.)
    var type: SceneObject.ObjectType    // Тип объекта
    var worldPosition: Position3D       // 3D позиция в AR пространстве
    var anchorID: UUID?                 // ID связанного ARAnchor
    let createdAt: Date
    
    /// Создаёт MarkedObject из названия и позиции
    init(name: String, position: Position3D) {
        self.id = UUID()
        self.name = name.lowercased().trimmingCharacters(in: .whitespaces)
        self.type = MarkedObject.inferType(from: name)
        self.worldPosition = position
        self.anchorID = nil
        self.createdAt = Date()
    }
    
    /// Определяет тип объекта по названию
    static func inferType(from name: String) -> SceneObject.ObjectType {
        let lowercased = name.lowercased()
        
        for (keyword, type) in KeywordsMapping.objectKeywords {
            if lowercased.contains(keyword) || keyword.contains(lowercased) {
                return type
            }
        }
        
        return .generic
    }
    
    /// Проверяет, соответствует ли объект ключевому слову
    /// - Parameter keyword: Ключевое слово для проверки
    /// - Returns: true, если объект соответствует ключевому слову
    func matches(keyword: String) -> Bool {
        let lowercasedKeyword = keyword.lowercased()
        let lowercasedName = name.lowercased()
        
        // Прямое совпадение
        if lowercasedName == lowercasedKeyword { return true }
        
        // Совпадение по корню слова (стол -> столу, столом)
        if lowercasedKeyword.hasPrefix(lowercasedName.prefix(3)) { return true }
        if lowercasedName.hasPrefix(lowercasedKeyword.prefix(3)) { return true }
        
        // Совпадение по типу
        if let keywordType = KeywordsMapping.objectKeywords[lowercasedKeyword] {
            return keywordType == type
        }
        
        return false
    }
    
    /// Проверяет, соответствует ли объект ключевому слову с использованием лемматизации
    /// - Parameters:
    ///   - keyword: Ключевое слово для проверки
    ///   - lemmatizer: Лемматизатор для нормализации слов
    /// - Returns: true, если объект соответствует ключевому слову
    func matches(keyword: String, lemmatizer: Lemmatizer) -> Bool {
        // Используем лемматизацию для более точного сравнения
        if lemmatizer.matchesKeyword(name, keyword: keyword) {
            return true
        }
        
        // Fallback на старый метод
        return matches(keyword: keyword)
    }
    
    /// Цвет маркера
    var markerColor: UIColor {
        UIColor(red: 0.0, green: 0.8, blue: 0.4, alpha: 1.0) // Зелёный для размеченных объектов
    }
}

// MARK: - Camera Setup

/// Настройка камеры для конкретного beat (кадра раскадровки)
struct CameraSetup: Codable, Equatable {
    let shotType: ShotType              // Крупность кадра
    var movement: CameraMovement?       // Движение камеры (опционально)
    var target: String?                 // На кого/что направлена камера (actorId или objectId)
    
    /// Тип кадра (крупность)
    enum ShotType: String, Codable, CaseIterable {
        case wide = "wide"                          // Общий план
        case medium = "medium"                      // Средний план
        case closeUp = "close_up"                   // Крупный план
        case extremeCloseUp = "extreme_close_up"    // Деталь
        case overShoulder = "over_shoulder"          // Через плечо
        case twoShot = "two_shot"                    // Двойной план (оба актёра)
    }
    
    /// Движение камеры
    enum CameraMovement: String, Codable, CaseIterable {
        case `static` = "static"            // Камера неподвижна
        case panLeft = "pan_left"            // Панорамирование влево
        case panRight = "pan_right"          // Панорамирование вправо
        case tiltUp = "tilt_up"              // Наклон вверх
        case tiltDown = "tilt_down"          // Наклон вниз
        case dollyIn = "dolly_in"            // Наезд (камера приближается)
        case dollyOut = "dolly_out"          // Отъезд (камера отдаляется)
        case tracking = "tracking"           // Слежение за персонажем
        case craneUp = "crane_up"            // Кран вверх
        case craneDown = "crane_down"        // Кран вниз
    }
}

// MARK: - Actor Pose

/// Поза актёра (персистентное состояние, меняется только действиями)
enum ActorPose: String, Codable, CaseIterable {
    case standing = "standing"      // Стоит (по умолчанию)
    case sitting = "sitting"        // Сидит
    case crouching = "crouching"    // Присел
    case lying = "lying"            // Лежит
    case walking = "walking"        // Идёт
    case running = "running"        // Бежит
}

// MARK: - Scene Beat

/// Такт (beat) — атомарная единица времени сцены.
/// Все действия внутри одного beat выполняются одновременно.
/// Следующий beat начинается только после завершения предыдущего.
struct SceneBeat: Codable, Equatable, Identifiable {
    let id: String                  // "beat_1", "beat_2", ...
    let actions: [SceneAction]      // Действия, выполняемые одновременно в этом такте
    var camera: CameraSetup?        // Камера для данного beat (nil = не меняется)
    var minDuration: Double?        // Минимальная длительность в секундах (для пауз)
}

// MARK: - Main Scene Script

/// Главная структура, содержащая все данные распознанной сцены
struct SceneScript: Codable, Equatable {
    let actors: [SceneActor]
    let objects: [SceneObject]
    let beats: [SceneBeat]
    let spatialRelations: [SpatialRelation]
    let originalDescription: String
    
    /// Обратная совместимость: плоский список всех действий из всех beats
    var actions: [SceneAction] {
        beats.flatMap { $0.actions }
    }
    
    var isEmpty: Bool {
        actors.isEmpty && objects.isEmpty && beats.isEmpty
    }
}


// MARK: - Parsing Diagnostics

/// Метаданные о качестве парсинга текста
struct ParsingDiagnostics: Equatable {
    let confidence: Float              // 0.0...1.0 - общая уверенность в результате
    let coverage: Float                // 0.0...1.0 - покрытие текста (сколько слов распознано)
    let missingActors: Bool            // Есть действия без актёров
    let missingObjects: Bool          // Есть ссылки на объекты, которых нет
    let unresolvedPronouns: Bool       // Есть "он/она/другой" без привязки
    let unresolvedMarkedObjects: Bool // Есть упоминания markedObjects, но не распознаны
    let notes: [String]                // Человекочитаемые заметки для пользователя
    let matchedMarkedObjects: [UUID]  // ID размеченных объектов, которые были распознаны
    
    static let empty = ParsingDiagnostics(
        confidence: 0.0,
        coverage: 0.0,
        missingActors: false,
        missingObjects: false,
        unresolvedPronouns: false,
        unresolvedMarkedObjects: false,
        notes: [],
        matchedMarkedObjects: []
    )
}

// MARK: - Parsing Result

/// Результат парсинга текста с диагностикой
struct ParsingResult: Equatable {
    let script: SceneScript
    let diagnostics: ParsingDiagnostics
}

// MARK: - Scene Actor

/// Представляет актёра/персонажа в сцене
struct SceneActor: Codable, Equatable, Identifiable {
    let id: String              // Уникальный ID: "actor_1", "actor_2"
    let type: ActorType         // Тип: human, animal и т.д.
    var name: String?           // Опциональное имя актёра
    
    enum ActorType: String, Codable, CaseIterable {
        case human = "human"
        case tiger = "tiger"
        case lion = "lion"
        case dog = "dog"
        case cat = "cat"
        case bird = "bird"
        case generic = "generic"
        
        /// Цвет placeholder кубика для данного типа
        var placeholderColor: (r: Float, g: Float, b: Float) {
            switch self {
            case .human: return (0.2, 0.6, 1.0)    // Синий
            case .tiger: return (1.0, 0.5, 0.0)    // Оранжевый
            case .lion: return (0.9, 0.7, 0.1)     // Золотисто-жёлтый
            case .dog: return (0.6, 0.4, 0.2)      // Коричневый
            case .cat: return (0.8, 0.8, 0.8)      // Серый
            case .bird: return (1.0, 1.0, 0.0)     // Жёлтый
            case .generic: return (0.5, 0.5, 0.5)  // Серый
            }
        }
        
        /// Размер placeholder кубика
        var placeholderSize: simd_float3 {
            switch self {
            case .human: return simd_float3(0.3, 1.7, 0.3)
            case .tiger: return simd_float3(0.8, 0.6, 0.3)
            case .lion: return simd_float3(0.9, 0.7, 0.4)
            case .dog: return simd_float3(0.5, 0.4, 0.2)
            case .cat: return simd_float3(0.3, 0.25, 0.15)
            case .bird: return simd_float3(0.1, 0.1, 0.1)
            case .generic: return simd_float3(0.3, 0.3, 0.3)
            }
        }
    }
}

// MARK: - Scene Object

/// Представляет объект в сцене (стол, стул, шкаф и т.д.)
struct SceneObject: Codable, Equatable, Identifiable {
    let id: String                      // Уникальный ID: "object_1"
    let type: ObjectType                // Тип объекта
    var detectedPosition: Position3D?   // Позиция из object detection (если найден)
    var relativePosition: RelativePosition // Относительная позиция в кадре
    
    enum ObjectType: String, Codable, CaseIterable {
        case table = "table"
        case chair = "chair"
        case cabinet = "cabinet"
        case door = "door"
        case couch = "couch"
        case bed = "bed"
        case window = "window"
        case shelf = "shelf"
        case tv = "tv"
        case generic = "generic"
        
        /// COCO labels, соответствующие данному типу
        var cocoLabels: [String] {
            switch self {
            case .table: return ["dining table", "table"]
            case .chair: return ["chair"]
            case .cabinet: return ["cabinet"]
            case .door: return ["door"]
            case .couch: return ["couch"]
            case .bed: return ["bed"]
            case .window: return ["window (blind)", "window (other)"]
            case .shelf: return ["shelf"]
            case .tv: return ["tv"]
            case .generic: return []
            }
        }
        
        /// Размер placeholder кубика
        var placeholderSize: simd_float3 {
            switch self {
            case .table: return simd_float3(1.2, 0.75, 0.8)
            case .chair: return simd_float3(0.5, 0.9, 0.5)
            case .cabinet: return simd_float3(1.0, 1.8, 0.5)
            case .door: return simd_float3(0.9, 2.0, 0.1)
            case .couch: return simd_float3(2.0, 0.8, 0.9)
            case .bed: return simd_float3(2.0, 0.5, 1.5)
            case .window: return simd_float3(1.0, 1.2, 0.1)
            case .shelf: return simd_float3(1.0, 0.3, 0.3)
            case .tv: return simd_float3(1.0, 0.6, 0.1)
            case .generic: return simd_float3(0.5, 0.5, 0.5)
            }
        }
        
        /// Цвет placeholder кубика
        var placeholderColor: (r: Float, g: Float, b: Float) {
            switch self {
            case .table: return (0.6, 0.4, 0.2)     // Коричневый
            case .chair: return (0.5, 0.3, 0.1)     // Тёмно-коричневый
            case .cabinet: return (0.4, 0.3, 0.2)   // Тёмный
            case .door: return (0.7, 0.5, 0.3)      // Светло-коричневый
            case .couch: return (0.3, 0.3, 0.6)     // Синеватый
            case .bed: return (0.9, 0.9, 0.9)       // Белый
            case .window: return (0.7, 0.9, 1.0)    // Голубой
            case .shelf: return (0.5, 0.4, 0.3)     // Коричневый
            case .tv: return (0.1, 0.1, 0.1)        // Чёрный
            case .generic: return (0.5, 0.5, 0.5)   // Серый
            }
        }
    }
    
    enum RelativePosition: String, Codable {
        case left = "left"
        case right = "right"
        case center = "center"
        case background = "background"
        case foreground = "foreground"
        case unknown = "unknown"
    }
}

private let markedObjectPrefix = "object_marked_"

extension MarkedObject {
    var markedShortID: String {
        String(id.uuidString.prefix(8)).lowercased()
    }

    var canonicalMarkedObjectID: String {
        "\(markedObjectPrefix)\(markedShortID)"
    }
}

extension SceneObject {
    var markedObjectShortID: String? {
        let lowercasedID = id.lowercased()
        guard lowercasedID.hasPrefix(markedObjectPrefix) else { return nil }
        let raw = String(lowercasedID.dropFirst(markedObjectPrefix.count))
        guard !raw.isEmpty else { return nil }
        let shortID = String(raw.prefix(8))
        guard shortID.count == 8 else { return nil }
        return shortID
    }
}

// MARK: - Scene Action

/// Представляет действие актёра
struct SceneAction: Codable, Equatable, Identifiable {
    let id: String
    let actorId: String             // ID актёра, выполняющего действие
    let type: ActionType            // Тип действия
    var target: String?             // ID цели (другой актёр или объект)
    var direction: Direction?       // Направление движения
    var modifier: ActionModifier?   // Модификатор (быстро, медленно)
    var resultingPose: ActorPose?   // В какую позу переходит актёр после этого действия
    var holdingObject: String?      // Какой объект держит (после pick_up)
    var dialogue: String?           // Текст реплики прямой речи (для type = talk)
    
    enum ActionType: String, Codable, CaseIterable {
        case walk = "walk"
        case run = "run"
        case stop = "stop"
        case turn = "turn"
        case approach = "approach"
        case passBy = "pass_by"
        case enter = "enter"
        case exit = "exit"
        case stand = "stand"
        case sit = "sit"
        case lieDown = "lie_down"
        case crouch = "crouch"
        case lookAt = "look_at"
        case pickUp = "pick_up"
        case putDown = "put_down"
        case open = "open"
        case close = "close"
        case give = "give"
        case talk = "talk"
    }
    
    enum Direction: String, Codable {
        case left = "left"
        case right = "right"
        case forward = "forward"
        case backward = "backward"
        case towardEachOther = "toward_each_other"
        case awayFromEachOther = "away_from_each_other"
        case toTarget = "to_target"
    }
    
    enum ActionModifier: String, Codable {
        case slowly = "slowly"
        case quickly = "quickly"
        case carefully = "carefully"
    }
    
    /// Скорость движения в м/с
    var speed: Float {
        let baseSpeed: Float = switch type {
        case .walk, .approach, .passBy, .enter, .exit: 0.8
        case .run: 2.5
        case .stop, .stand, .sit, .lieDown, .crouch, .lookAt, .pickUp, .putDown, .open, .close, .give, .talk: 0.0
        case .turn: 0.3
        }
        
        let multiplier: Float = switch modifier {
        case .slowly: 0.5
        case .quickly: 1.5
        case .carefully: 0.7
        case .none: 1.0
        }
        
        return baseSpeed * multiplier
    }
}

// MARK: - Spatial Relation

/// Пространственное отношение между объектами
struct SpatialRelation: Codable, Equatable, Identifiable {
    let id: String
    let subject: String         // ID субъекта (кто/что)
    let relation: RelationType  // Тип отношения
    let object: String          // ID объекта (относительно чего)
    
    enum RelationType: String, Codable, CaseIterable {
        case near = "near"
        case inFrontOf = "in_front_of"
        case behind = "behind"
        case leftOf = "left_of"
        case rightOf = "right_of"
        case between = "between"
        case passBy = "pass_by"
        case inside = "inside"
        case outside = "outside"
    }
}

// MARK: - Position Types

/// 3D позиция в AR пространстве
struct Position3D: Codable, Equatable {
    var x: Float
    var y: Float
    var z: Float
    
    var simdVector: simd_float3 {
        simd_float3(x, y, z)
    }
    
    init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }
    
    init(_ simd: simd_float3) {
        self.x = simd.x
        self.y = simd.y
        self.z = simd.z
    }
    
    static let zero = Position3D(x: 0, y: 0, z: 0)
    
    func distance(to other: Position3D) -> Float {
        simd_distance(simdVector, other.simdVector)
    }
}

// MARK: - Planned Scene (Output of Spatial Planner)

/// Результат планирования сцены - готовые координаты для размещения
struct PlannedScene {
    let placedActors: [PlacedActor]
    let placedObjects: [PlacedObject]
    
    struct PlacedActor: Identifiable {
        let id: String
        let actorId: String
        let type: SceneActor.ActorType
        var name: String?
        let initialPosition: Position3D
        var initialRotation: Float      // Угол в радианах вокруг Y
        let path: [Position3D]          // Траектория движения (включая начальную точку)
        let pathDurations: [Double]     // Время между точками пути
        var pathPoses: [ActorPose]      // Поза в каждой точке пути
        var pathCameras: [CameraSetup?] // Камера для каждого beat (nil = без изменений)
        
        var color: (r: Float, g: Float, b: Float) {
            type.placeholderColor
        }
        
        var size: simd_float3 {
            type.placeholderSize
        }
    }
    
    struct PlacedObject: Identifiable {
        let id: String
        let objectId: String
        let type: SceneObject.ObjectType
        let position: Position3D
        var rotation: Float  // Угол в радианах вокруг Y
        let isDetected: Bool // true если объект был обнаружен в реальном мире
        let placementSource: PlacementSource
        
        var color: (r: Float, g: Float, b: Float) {
            type.placeholderColor
        }
        
        var size: simd_float3 {
            type.placeholderSize
        }

        var isRealWorld: Bool {
            placementSource != .virtual
        }

        enum PlacementSource: String {
            case marked
            case detected
            case virtual
        }
    }
}

// MARK: - Detected Object (From Object Detection)

/// Объект, обнаруженный через DETRDetector
struct DetectedObject: Identifiable, Equatable {
    let id: UUID
    let label: String
    let confidence: Float
    let boundingBox: CGRect      // Normalized (0...1)
    var worldPosition: Position3D?  // 3D позиция (после raycast)
    
    /// Маппинг COCO label на SceneObject.ObjectType
    var objectType: SceneObject.ObjectType? {
        for type in SceneObject.ObjectType.allCases {
            if type.cocoLabels.contains(where: { $0.lowercased() == label.lowercased() }) {
                return type
            }
        }
        return nil
    }
}

// MARK: - Keywords Mapping

/// Маппинг русских ключевых слов на типы
struct KeywordsMapping {
    
    // MARK: Actor Keywords
    static let actorKeywords: [String: SceneActor.ActorType] = [
        // Человек
        "человек": .human,
        "люди": .human,
        "актёр": .human,
        "актер": .human,
        "актёры": .human,
        "актеры": .human,
        "персонаж": .human,
        "персонажи": .human,
        "мужчина": .human,
        "женщина": .human,
        "девушка": .human,
        "парень": .human,
        // Животные
        "тигр": .tiger,
        "тигры": .tiger,
        "собака": .dog,
        "собаки": .dog,
        "пёс": .dog,
        "пес": .dog,
        "кот": .cat,
        "кошка": .cat,
        "коты": .cat,
        "кошки": .cat,
        "птица": .bird,
        "птицы": .bird,
        // Лев
        "лев": .lion,
        "льва": .lion,
        "льву": .lion,
        "львом": .lion,
        "львы": .lion,
        "львов": .lion
    ]
    
    // MARK: Object Keywords
    static let objectKeywords: [String: SceneObject.ObjectType] = [
        "стол": .table,
        "столу": .table,
        "стола": .table,
        "столом": .table,
        "стул": .chair,
        "стулу": .chair,
        "стула": .chair,
        "стулом": .chair,
        "шкаф": .cabinet,
        "шкафу": .cabinet,
        "шкафа": .cabinet,
        "шкафом": .cabinet,
        "дверь": .door,
        "двери": .door,
        "дверью": .door,
        "диван": .couch,
        "дивану": .couch,
        "дивана": .couch,
        "диваном": .couch,
        "кровать": .bed,
        "кровати": .bed,
        "кроватью": .bed,
        "окно": .window,
        "окну": .window,
        "окна": .window,
        "окном": .window,
        "полка": .shelf,
        "полке": .shelf,
        "полки": .shelf,
        "полкой": .shelf,
        "телевизор": .tv,
        "телевизору": .tv,
        "телевизора": .tv,
        "телевизором": .tv,
        "тв": .tv,
        "телек": .tv,
        "телику": .tv,
        "телика": .tv,
        "телевизоре": .tv
    ]
    
    // MARK: Action Keywords
    static let actionKeywords: [String: SceneAction.ActionType] = [
        "идёт": .walk,
        "идет": .walk,
        "идут": .walk,
        "идти": .walk,
        "ходит": .walk,
        "ходят": .walk,
        "шагает": .walk,
        "шагают": .walk,
        "бежит": .run,
        "бегут": .run,
        "бегает": .run,
        "бегают": .run,
        "стоит": .stand,
        "стоят": .stand,
        "останавливается": .stop,
        "останавливаются": .stop,
        "остановился": .stop,
        "остановились": .stop,
        "поворачивает": .turn,
        "поворачивают": .turn,
        "повернул": .turn,
        "повернули": .turn,
        "подходит": .approach,
        "подходят": .approach,
        "подошёл": .approach,
        "подошел": .approach,
        "подошли": .approach,
        "проходит": .passBy,
        "проходят": .passBy,
        "прошёл": .passBy,
        "прошел": .passBy,
        "прошли": .passBy,
        "входит": .enter,
        "входят": .enter,
        "вошёл": .enter,
        "вошел": .enter,
        "вошли": .enter,
        "выходит": .exit,
        "выходят": .exit,
        "вышел": .exit,
        "вышли": .exit,
        "сидит": .sit,
        "сидят": .sit,
        "сел": .sit,
        "села": .sit,
        "сели": .sit
    ]
    
    // MARK: Direction Keywords
    static let directionKeywords: [String: SceneAction.Direction] = [
        "налево": .left,
        "влево": .left,
        "левее": .left,
        "направо": .right,
        "вправо": .right,
        "правее": .right,
        "прямо": .forward,
        "вперёд": .forward,
        "вперед": .forward,
        "назад": .backward,
        "обратно": .backward,
        "навстречу": .towardEachOther,
        "друг к другу": .towardEachOther,
        "друг на друга": .towardEachOther,
        "друг от друга": .awayFromEachOther
    ]
    
    // MARK: Relation Keywords
    static let relationKeywords: [String: SpatialRelation.RelationType] = [
        "мимо": .passBy,
        "около": .near,
        "рядом": .near,
        "возле": .near,
        "у": .near,
        "перед": .inFrontOf,
        "впереди": .inFrontOf,
        "за": .behind,
        "позади": .behind,
        "сзади": .behind,
        "слева": .leftOf,
        "справа": .rightOf,
        "между": .between,
        "внутри": .inside,
        "в": .inside,
        "снаружи": .outside,
        "из": .outside
    ]
    
    // MARK: Modifier Keywords
    static let modifierKeywords: [String: SceneAction.ActionModifier] = [
        "медленно": .slowly,
        "потихоньку": .slowly,
        "неспеша": .slowly,
        "быстро": .quickly,
        "стремительно": .quickly,
        "бегом": .quickly,
        "осторожно": .carefully,
        "аккуратно": .carefully
    ]
    
    // MARK: COCO to Russian Mapping
    static let cocoToRussian: [String: String] = [
        "person": "человек",
        "table": "стол",
        "dining table": "стол",
        "chair": "стул",
        "couch": "диван",
        "bed": "кровать",
        "tv": "телевизор",
        "door": "дверь",
        "cabinet": "шкаф",
        "shelf": "полка",
        "window (blind)": "окно",
        "window (other)": "окно",
        "dog": "собака",
        "cat": "кошка",
        "bird": "птица"
    ]
}
