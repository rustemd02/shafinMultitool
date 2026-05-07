//
//  SuggestionEngine.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import Foundation
import CoreGraphics
import os.log

struct CoachingFeatures {
    struct Subject {
        var isFace: Bool = false
        var isPerson: Bool = false
        var count: Int = 0
        var objectName: String? = nil // Название объекта из DETR (lamp, cup, etc.)
    }
    struct Composition {
        var horizontalOffset: CGFloat = 0.0 // -1...1 (левее/правее третей)
        var verticalOffset: CGFloat = 0.0   // -1...1 (ниже/выше третей)
        var saliencyLeftRightBalance: CGFloat = 0.0
        var saliencyTopBottomBalance: CGFloat = 0.0
        var subjectAreaRatio: CGFloat = 0.0 // 0..1 относительно кадра
    }

    struct Horizon {
        var angle: CGFloat = 0.0 // градусы, положительный — по часовой
        var confidence: CGFloat = 0.0
    }

    struct Lighting {
        var backlightIndex: CGFloat = 0.0 // 0..1
        var keyToFillRatio: CGFloat = 1.0
        var exposureBiasHint: CGFloat = 0.0
    }

    struct Motion {
        var shakeLevel: CGFloat = 0.0
        var state: MotionState = .still
    }

    var composition = Composition()
    var horizon = Horizon()
    var lighting = Lighting()
    var motion = Motion()
    var subject = Subject()
    var aestheticScore: CGFloat? = nil
    var lensRecommendation: Int?
}

enum MotionState {
    case still
    case moving
    case panning
}

final class SuggestionEngine {
    struct Configuration {
        var horizonThresholdDegrees: CGFloat = 2.5
        var horizonConfidenceThreshold: CGFloat = 0.65
        var compositionOffsetThreshold: CGFloat = 0.30
        var backlightThreshold: CGFloat = 0.35
        var shakeThreshold: CGFloat = 0.65
        var cooldownPerKind: TimeInterval = 5.0 // Увеличен для меньшего мелькания
        var globalSwitchCooldown: TimeInterval = 7.0
        var displayDuration: TimeInterval = 4.5
        var activationWindowCount: Int = 3
        var deactivationWindowCount: Int = 2
    }

    private let configuration: Configuration
    private var history: [SuggestionType: Date] = [:]
    private var activationCounters: [SuggestionType: Int] = [:]
    private var deactivationCounters: [SuggestionType: Int] = [:]
    private var lastPublishedAt: Date = .distantPast
    private var lastPublishedType: SuggestionType?
    private let log = OSLog(subsystem: "com.multitool2.suggestions", category: "SuggestionEngine")
    private var logCounter = 0

    init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    // Список ранжированных подсказок (для режима предпросмотра). Игнорирует cooldown,
    // возвращает TOP-N по приоритету и типу (по умолчанию 4).
    func rankedSuggestions(from features: CoachingFeatures,
                           topN: Int = 4,
                           timestamp: Date = Date()) -> [Suggestion] {
        var candidates: [Suggestion] = []
        
        if let exposureText = exposureSuggestionText(from: features) {
            candidates.append(Suggestion(text: exposureText,
                                         priority: .critical,
                                         type: .exposure,
                                         ttl: configuration.displayDuration,
                                         createdAt: timestamp))
        }
        if let horizonText = horizonSuggestion(from: features) {
            candidates.append(Suggestion(text: horizonText,
                                         priority: .critical,
                                         type: .horizon,
                                         ttl: configuration.displayDuration,
                                         createdAt: timestamp))
        }
        if let compositionText = compositionSuggestion(from: features) {
            candidates.append(Suggestion(text: compositionText,
                                         priority: .important,
                                         type: .composition,
                                         ttl: configuration.displayDuration,
                                         createdAt: timestamp))
        }
        if let lightingText = lightingSuggestion(from: features) {
            candidates.append(Suggestion(text: lightingText,
                                         priority: .important,
                                         type: .lighting,
                                         ttl: configuration.displayDuration,
                                         createdAt: timestamp))
        }
        if let lensText = lensSuggestion(from: features) {
            candidates.append(Suggestion(text: lensText,
                                         priority: .optional,
                                         type: .lens,
                                         ttl: configuration.displayDuration,
                                         createdAt: timestamp))
        }

        let sorted = candidates.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.type < rhs.type
        }
        return Array(sorted.prefix(topN))
    }

    func nextSuggestion(from features: CoachingFeatures, timestamp: Date = Date()) -> Suggestion? {
        logCounter += 1
        let shouldLog = CameraLog.suggestions && logCounter % 20 == 0
        
        // Если камера движется - скрываем подсказки (пользователь пытается исправить проблему)
        if features.motion.state != .still {
            if shouldLog {
                os_log("💡 Suggestions: Hidden (camera moving, state=%{public}@)", 
                       log: log, type: .debug, String(describing: features.motion.state))
            }
            return nil
        }
        
        var candidates: [Suggestion] = []

        if let exposureText = exposureSuggestionText(from: features) {
            candidates.append(Suggestion(text: exposureText,
                                         priority: .critical,
                                         type: .exposure,
                                         ttl: configuration.displayDuration,
                                         createdAt: timestamp))
        }
        
        if let horizonText = horizonSuggestion(from: features) {
            candidates.append(Suggestion(text: horizonText,
                                         priority: .critical,
                                         type: .horizon,
                                         ttl: configuration.displayDuration,
                                         createdAt: timestamp))
        }

        if let compositionText = compositionSuggestion(from: features) {
            candidates.append(Suggestion(text: compositionText,
                                         priority: .important,
                                         type: .composition,
                                         ttl: configuration.displayDuration,
                                         createdAt: timestamp))
        }

        if let lightingText = lightingSuggestion(from: features) {
            candidates.append(Suggestion(text: lightingText,
                                         priority: .important,
                                         type: .lighting,
                                         ttl: configuration.displayDuration,
                                         createdAt: timestamp))
        }

        if let lensText = lensSuggestion(from: features) {
            candidates.append(Suggestion(text: lensText,
                                         priority: .optional,
                                         type: .lens,
                                         ttl: configuration.displayDuration,
                                         createdAt: timestamp))
        }
        
        if shouldLog {
            // Детальная диагностика почему какие-то подсказки не срабатывают
            os_log("💡 Features values: horizon=%.2f°(conf=%.2f) exposure=%.2f backlight=%.2f h_offset=%.2f v_offset=%.2f",
                   log: log, type: .debug,
                   features.horizon.angle, features.horizon.confidence,
                   features.lighting.exposureBiasHint, features.lighting.backlightIndex,
                   features.composition.horizontalOffset, features.composition.verticalOffset)
            
            let candidateTypes = candidates.map { "\($0.type)" }.joined(separator: ", ")
            os_log("💡 Candidates: [%{public}@] motion=%{public}@", 
                   log: log, type: .debug, candidateTypes, String(describing: features.motion.state))
        }

        let eligible = filterByCooldown(candidates: candidates, timestamp: timestamp)
        
        if shouldLog && eligible.count != candidates.count {
            let eligibleTypes = eligible.map { "\($0.type)" }.joined(separator: ", ")
            os_log("💡 After cooldown: [%{public}@]", log: log, type: .debug, eligibleTypes)
        }
        
        guard let pick = selectSuggestion(eligible) else {
            updateCounters(for: candidates.map { $0.type }, activated: false)
            if shouldLog {
                os_log("💡 No suggestion selected", log: log, type: .debug)
            }
            return nil
        }

        activationCounters[pick.type, default: 0] += 1
        for type in candidates.map(\.type) where type != pick.type {
            activationCounters[type] = 0
        }

        guard activationCounters[pick.type, default: 0] >= configuration.activationWindowCount else {
            if shouldLog {
                os_log("💡 Stabilizing: %{public}@ (%d/%d)",
                       log: log,
                       type: .debug,
                       String(describing: pick.type),
                       activationCounters[pick.type, default: 0],
                       configuration.activationWindowCount)
            }
            return nil
        }

        history[pick.type] = timestamp
        lastPublishedAt = timestamp
        lastPublishedType = pick.type
        activationCounters[pick.type] = 0

        if shouldLog {
            os_log("💡 Selected: %{public}@ - \"%{public}@\"",
                   log: log, type: .debug, String(describing: pick.type), pick.text)
        }
        return pick
    }

    private func updateCounters(for types: [SuggestionType], activated: Bool) {
        for type in types {
            if activated {
                activationCounters[type, default: 0] = max(activationCounters[type, default: 0] - 1, 0)
            } else {
                deactivationCounters[type, default: 0] += 1
                if deactivationCounters[type, default: 0] >= configuration.deactivationWindowCount {
                    activationCounters[type] = 0
                }
            }
        }
    }

    private func filterByCooldown(candidates: [Suggestion], timestamp: Date) -> [Suggestion] {
        candidates.filter { candidate in
            let lastShown = history[candidate.type] ?? .distantPast
            let kindAllowed = timestamp.timeIntervalSince(lastShown) >= configuration.cooldownPerKind
            let switchAllowed = candidate.type == lastPublishedType ||
                timestamp.timeIntervalSince(lastPublishedAt) >= configuration.globalSwitchCooldown
            return kindAllowed && switchAllowed
        }
    }

    private func exposureSuggestionText(from features: CoachingFeatures) -> String? {
        guard abs(features.lighting.exposureBiasHint) >= 0.25 else { return nil }
        if features.lighting.exposureBiasHint > 0 {
            return "Слишком светло"
        } else {
            return "Слишком темно"
        }
    }

    private func horizonSuggestion(from features: CoachingFeatures) -> String? {
        let angle = features.horizon.angle
        guard features.horizon.confidence >= configuration.horizonConfidenceThreshold else { return nil }
        guard abs(angle) >= configuration.horizonThresholdDegrees else { return nil }
        guard abs(angle) <= 35 else { return nil }
        
        if angle > 0 {
            return "Камеру ровнее (↺)"
        } else {
            return "Камеру ровнее (↻)"
        }
    }
    
    private func compositionSuggestion(from features: CoachingFeatures) -> String? {
        let horizontal = features.composition.horizontalOffset
        let vertical = features.composition.verticalOffset
        let threshold = features.subject.count > 1
            ? max(configuration.compositionOffsetThreshold, 0.45)
            : configuration.compositionOffsetThreshold
        
        // Горизонтальный кадр: приоритет левее/правее
        if abs(horizontal) >= threshold {
            let direction = horizontal > 0 ? "правее" : "левее"
            
            // Контекстные фразы в стиле Camera Coach
            if let objectName = features.subject.objectName, !objectName.isEmpty {
                let localizedObject = localizeObjectName(objectName)
                return "Камеру \(direction) от \(localizedObject)"
            } else if features.subject.isFace {
                return "Камеру чуть \(direction)"
            } else if features.subject.isPerson {
                return "Камеру \(direction)"
            } else if features.subject.count > 1 {
                return "Сдвинь кадр \(direction)"
            } else {
                return "Камеру \(direction)"
            }
        }
        
        // Вертикальная коррекция (редкая для ландшафта)
        if abs(vertical) >= threshold * 1.3 {
            let direction = vertical > 0 ? "ниже" : "выше"
            return "Камеру чуть \(direction)"
        }
        
        return nil
    }
    
    private func localizeObjectName(_ name: String) -> String {
        let objectMap: [String: String] = [
            "lamp": "лампы",
            "cup": "чашки",
            "bottle": "бутылки",
            "vase": "вазы",
            "book": "книги",
            "chair": "стула",
            "potted plant": "растения",
            "clock": "часов",
            "laptop": "ноутбука",
            "mouse": "мыши",
            "keyboard": "клавиатуры",
            "cell phone": "телефона",
            "microwave": "микроволновки",
            "oven": "духовки",
            "toaster": "тостера",
            "sink": "раковины",
            "refrigerator": "холодильника",
            "bowl": "миски",
            "banana": "банана",
            "apple": "яблока",
            "sandwich": "сэндвича",
            "orange": "апельсина",
            "broccoli": "брокколи",
            "carrot": "моркови",
            "hot dog": "хот-дога",
            "pizza": "пиццы",
            "donut": "пончика",
            "cake": "торта",
            "car": "машины",
            "bicycle": "велосипеда",
            "motorcycle": "мотоцикла",
            "airplane": "самолёта",
            "bus": "автобуса",
            "train": "поезда",
            "truck": "грузовика",
            "boat": "лодки",
            "cat": "кота",
            "dog": "собаки",
            "horse": "лошади",
            "bird": "птицы",
            "teddy bear": "медвежонка",
            "backpack": "рюкзака",
            "umbrella": "зонта",
            "handbag": "сумки",
            "tie": "галстука",
            "suitcase": "чемодана",
            "frisbee": "фрисби",
            "skis": "лыж",
            "snowboard": "сноуборда",
            "sports ball": "мяча",
            "kite": "воздушного змея",
            "baseball bat": "биты",
            "skateboard": "скейтборда",
            "surfboard": "доски для сёрфинга",
            "tennis racket": "теннисной ракетки"
        ]
        return objectMap[name.lowercased()] ?? "объекта"
    }

    private func lightingSuggestion(from features: CoachingFeatures) -> String? {
        if features.lighting.backlightIndex >= configuration.backlightThreshold {
            return "Добавь света спереди"
        }
        return nil
    }

    private func lensSuggestion(from features: CoachingFeatures) -> String? {
        guard let lens = features.lensRecommendation else { return nil }
        guard features.subject.count <= 1 else { return nil }
        guard features.composition.subjectAreaRatio > 0,
              features.composition.subjectAreaRatio < 0.10 else { return nil }
        if features.subject.isFace || features.subject.isPerson {
            return "Поставь \(lens)x"
        }
        return "Попробуй \(lens)x"
    }

}

private extension String {
    func localizedFormat(_ values: CVarArg...) -> String {
        String(format: self, locale: Locale.current, arguments: values)
    }
}
