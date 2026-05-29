import CoreGraphics
import Foundation

struct DecisionTraceDebugSignals: Equatable {
    let detrObjectCount: Int
    let visionSubjectCount: Int
    let saliencyCenter: CGPoint?
    let subjectAreaRatio: CGFloat?
    let horizonAngle: CGFloat?
    let horizonConfidence: CGFloat?
    let backlightIndex: CGFloat?
    let exposureBiasHint: CGFloat?
    let motionState: String?
    let aestheticScore: CGFloat?

    static let empty = DecisionTraceDebugSignals(
        detrObjectCount: 0,
        visionSubjectCount: 0,
        saliencyCenter: nil,
        subjectAreaRatio: nil,
        horizonAngle: nil,
        horizonConfidence: nil,
        backlightIndex: nil,
        exposureBiasHint: nil,
        motionState: nil,
        aestheticScore: nil
    )

    static func make(features: CoachingFeatures,
                     detrDetections: [DETRDetection],
                     visionSubjects: [VisionSubject],
                     saliencyCenter: CGPoint?) -> DecisionTraceDebugSignals {
        DecisionTraceDebugSignals(
            detrObjectCount: detrDetections.count,
            visionSubjectCount: visionSubjects.count,
            saliencyCenter: saliencyCenter,
            subjectAreaRatio: features.composition.subjectAreaRatio,
            horizonAngle: features.horizon.angle,
            horizonConfidence: features.horizon.confidence,
            backlightIndex: features.lighting.backlightIndex,
            exposureBiasHint: features.lighting.exposureBiasHint,
            motionState: String(describing: features.motion.state),
            aestheticScore: features.aestheticScore
        )
    }
}

struct DecisionTracePresentation: Identifiable, Equatable {
    struct ReasonLine: Identifiable, Equatable {
        let id: String
        let title: String
        let text: String
    }

    struct EvidenceRow: Identifiable, Equatable {
        let id: String
        let sourceId: String
        let kindLabel: String
        let title: String
        let text: String
        let confidence: ConfidencePresentation
        let severity: ConfidencePresentation?
        let regionDescription: String?
        let traceId: String?
    }

    struct ActionRow: Identifiable, Equatable {
        let id: String
        let title: String
        let semanticActionId: String
        let coarseActionId: String?
        let detail: String
        let linkedEvidenceIds: [String]
        let confidence: ConfidencePresentation
        let targetDescription: String?
        let overlayHintId: String?
        let traceId: String?
    }

    struct SignalRow: Identifiable, Equatable {
        let id: String
        let title: String
        let value: String
        let detail: String?
    }

    struct LimitationRow: Identifiable, Equatable {
        let id: String
        let text: String
    }

    let id: String
    let modeLabel: String
    let verdictLabel: String
    let headline: String
    let confidence: ConfidencePresentation
    let reasonLines: [ReasonLine]
    let evidenceRows: [EvidenceRow]
    let actionRows: [ActionRow]
    let signalRows: [SignalRow]
    let limitationRows: [LimitationRow]
    let traceIds: [String]

    static func current(liveHint: LiveHintPresentation?,
                        pauseCritique: PauseCritiquePresentation?,
                        isPaused: Bool,
                        overlayAnnotations: [OverlayAnnotationPresentation],
                        debugSignals: DecisionTraceDebugSignals) -> DecisionTracePresentation? {
        if isPaused, let pauseCritique {
            return pause(
                critique: pauseCritique,
                overlayAnnotations: overlayAnnotations,
                debugSignals: debugSignals
            )
        }
        if !isPaused, let liveHint {
            return live(
                hint: liveHint,
                overlayAnnotations: overlayAnnotations,
                debugSignals: debugSignals
            )
        }
        return nil
    }

    static func pause(critique: PauseCritiquePresentation,
                      overlayAnnotations: [OverlayAnnotationPresentation] = [],
                      debugSignals: DecisionTraceDebugSignals = .empty) -> DecisionTracePresentation {
        let reasonLines = pauseReasonLines(for: critique)
        let evidenceRows = pauseEvidenceRows(for: critique)
        let actionRows = pauseActionRows(for: critique)
        let limitations = limitationRows(
            fallbackUsed: critique.fallbackUsed,
            assumptions: critique.assumptions
        )
        let traceIds = orderedTraceIds(
            critique.traceRootIds
                + critique.issues.compactMap(\.traceRefId)
                + critique.strengths.compactMap(\.traceRefId)
                + critique.actions.compactMap(\.traceRefId)
        )

        return DecisionTracePresentation(
            id: "pause_\(critique.frameId)_\(critique.summaryId)",
            modeLabel: "Пауза",
            verdictLabel: verdictTitle(for: critique.verdict),
            headline: critique.shortVerdict,
            confidence: .make(critique.verdictConfidence),
            reasonLines: reasonLines,
            evidenceRows: evidenceRows,
            actionRows: actionRows,
            signalRows: signalRows(
                overlayAnnotations: overlayAnnotations,
                debugSignals: debugSignals
            ),
            limitationRows: limitations,
            traceIds: traceIds
        )
    }

    static func live(hint: LiveHintPresentation,
                     overlayAnnotations: [OverlayAnnotationPresentation] = [],
                     debugSignals: DecisionTraceDebugSignals = .empty) -> DecisionTracePresentation {
        let reasonLines = liveReasonLines(for: hint)
        let actionRows = liveActionRows(for: hint)
        let limitations = limitationRows(
            fallbackUsed: hint.isFallback || hint.expandedVerdict?.fallbackUsed == true,
            assumptions: hint.linkedIssueIds.isEmpty ? [] : ["Live-подсказка связана с issue ids: \(hint.linkedIssueIds.joined(separator: ", "))."]
        )

        return DecisionTracePresentation(
            id: "live_\(hint.frameId)_\(hint.id)",
            modeLabel: "Live",
            verdictLabel: "Текущая подсказка",
            headline: hint.text,
            confidence: .make(hint.confidence),
            reasonLines: reasonLines,
            evidenceRows: [],
            actionRows: actionRows,
            signalRows: signalRows(
                overlayAnnotations: overlayAnnotations,
                debugSignals: debugSignals
            ),
            limitationRows: limitations,
            traceIds: orderedTraceIds(hint.traceRootIds)
        )
    }

    private static func pauseReasonLines(for critique: PauseCritiquePresentation) -> [ReasonLine] {
        var rows: [ReasonLine] = []
        if critique.verdict == .good {
            appendReason(&rows, id: "why_good", title: "Что сработало", text: critique.whyGood)
            appendReason(&rows, id: "no_change", title: "Почему можно не менять", text: critique.noChangeRationale)
        } else {
            appendReason(&rows, id: "why_problematic", title: "Что мешает", text: critique.whyProblematic)
            appendReason(&rows, id: "why_good", title: "Что уже работает", text: critique.whyGood)
        }
        if rows.isEmpty {
            appendReason(&rows, id: "summary", title: "Краткий вывод", text: critique.shortVerdict)
        }
        return rows
    }

    private static func liveReasonLines(for hint: LiveHintPresentation) -> [ReasonLine] {
        var rows: [ReasonLine] = []
        appendReason(&rows, id: "short_verdict", title: "Сигнал", text: hint.expandedVerdict?.shortVerdict)
        appendReason(&rows, id: "supporting_text", title: "Почему", text: hint.expandedVerdict?.supportingText)
        appendReason(&rows, id: "action_text", title: "Действие", text: hint.expandedVerdict?.actionText)
        if rows.isEmpty {
            appendReason(&rows, id: "hint", title: "Подсказка", text: hint.text)
        }
        return rows
    }

    private static func pauseEvidenceRows(for critique: PauseCritiquePresentation) -> [EvidenceRow] {
        let issueRows = critique.issues.map { issue in
            EvidenceRow(
                id: "issue_\(issue.issueId)",
                sourceId: issue.issueId,
                kindLabel: "Проблема",
                title: issueTitle(issue.type),
                text: issue.rationale,
                confidence: .make(issue.confidence),
                severity: .make(issue.severity),
                regionDescription: regionDescription(issue.affectedRegion),
                traceId: issue.traceRefId
            )
        }
        let strengthRows = critique.strengths.map { strength in
            EvidenceRow(
                id: "strength_\(strength.strengthId)",
                sourceId: strength.strengthId,
                kindLabel: "Сильная сторона",
                title: strengthTitle(strength.type),
                text: strength.rationale,
                confidence: .make(strength.confidence),
                severity: nil,
                regionDescription: regionDescription(strength.supportingRegion),
                traceId: strength.traceRefId
            )
        }
        return issueRows + strengthRows
    }

    private static func pauseActionRows(for critique: PauseCritiquePresentation) -> [ActionRow] {
        let rows = critique.actions.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            return lhs.actionId < rhs.actionId
        }.map { action in
            ActionRow(
                id: action.actionId,
                title: semanticActionTitle(action.semanticActionType),
                semanticActionId: action.semanticActionType.rawValue,
                coarseActionId: action.actionType.rawValue,
                detail: action.expectedOutcome,
                linkedEvidenceIds: action.linkedIssueIds,
                confidence: .make(action.confidence),
                targetDescription: regionDescription(action.targetRegion),
                overlayHintId: action.overlayHintId,
                traceId: action.traceRefId
            )
        }
        if !rows.isEmpty {
            return rows
        }
        guard let rationale = nonEmpty(critique.noChangeRationale) else {
            return []
        }
        return [
            ActionRow(
                id: "keep_current_setup",
                title: semanticActionTitle(.keepCurrentSetup),
                semanticActionId: SemanticActionType.keepCurrentSetup.rawValue,
                coarseActionId: ActionTypeV1.leaveFrameAsIs.rawValue,
                detail: rationale,
                linkedEvidenceIds: critique.strengths.map(\.strengthId),
                confidence: .make(critique.verdictConfidence),
                targetDescription: nil,
                overlayHintId: nil,
                traceId: nil
            )
        ]
    }

    private static func liveActionRows(for hint: LiveHintPresentation) -> [ActionRow] {
        guard let actionType = hint.actionType else {
            return []
        }
        let semanticAction = actionType.semanticActionType
        return [
            ActionRow(
                id: hint.actionId ?? "live_action",
                title: semanticActionTitle(semanticAction),
                semanticActionId: semanticAction.rawValue,
                coarseActionId: actionType.rawValue,
                detail: hint.expandedVerdict?.actionText ?? hint.text,
                linkedEvidenceIds: hint.linkedIssueIds,
                confidence: .make(hint.confidence),
                targetDescription: regionDescription(hint.targetRegion),
                overlayHintId: hint.overlayHint?.id,
                traceId: nil
            )
        ]
    }

    private static func signalRows(overlayAnnotations: [OverlayAnnotationPresentation],
                                   debugSignals: DecisionTraceDebugSignals) -> [SignalRow] {
        var rows: [SignalRow] = []
        if debugSignals.detrObjectCount > 0 {
            rows.append(SignalRow(id: "detr", title: "DETR objects", value: "\(debugSignals.detrObjectCount)", detail: "Объекты, найденные детектором."))
        }
        if debugSignals.visionSubjectCount > 0 {
            rows.append(SignalRow(id: "vision", title: "Vision subjects", value: "\(debugSignals.visionSubjectCount)", detail: "Кандидаты субъекта от Vision."))
        }
        if !overlayAnnotations.isEmpty {
            rows.append(SignalRow(id: "overlay", title: "Overlay annotations", value: "\(overlayAnnotations.count)", detail: overlaySummary(overlayAnnotations)))
        }
        if let saliencyCenter = debugSignals.saliencyCenter {
            rows.append(SignalRow(id: "saliency", title: "Saliency center", value: pointString(saliencyCenter), detail: "Нормализованный центр внимания."))
        }
        if let subjectAreaRatio = debugSignals.subjectAreaRatio {
            rows.append(SignalRow(id: "subject_area", title: "Subject area", value: percentString(subjectAreaRatio), detail: "Доля главного субъекта в кадре."))
        }
        if let horizonAngle = debugSignals.horizonAngle,
           let horizonConfidence = debugSignals.horizonConfidence {
            rows.append(SignalRow(id: "horizon", title: "Horizon", value: "\(decimalString(horizonAngle))°", detail: "Уверенность \(percentString(horizonConfidence))."))
        }
        if let backlightIndex = debugSignals.backlightIndex {
            rows.append(SignalRow(id: "backlight", title: "Backlight", value: percentString(backlightIndex), detail: "Оценка контрового света."))
        }
        if let exposureBiasHint = debugSignals.exposureBiasHint {
            rows.append(SignalRow(id: "exposure", title: "Exposure bias", value: decimalString(exposureBiasHint), detail: "Знак показывает направление экспокоррекции."))
        }
        if let motionState = nonEmpty(debugSignals.motionState) {
            rows.append(SignalRow(id: "motion", title: "Motion", value: motionState, detail: "Состояние движения камеры."))
        }
        if let aestheticScore = debugSignals.aestheticScore {
            rows.append(SignalRow(id: "aesthetic", title: "Aesthetic score", value: percentString(aestheticScore), detail: "Нейрооценка качества кадра."))
        }
        return rows
    }

    private static func limitationRows(fallbackUsed: Bool,
                                       assumptions: [String]) -> [LimitationRow] {
        var rows: [LimitationRow] = []
        if fallbackUsed {
            rows.append(
                LimitationRow(
                    id: "fallback",
                    text: "Использован fallback: часть расширенного reasoning недоступна, поэтому решение опирается на устойчивые структурные признаки."
                )
            )
        }
        rows.append(contentsOf: assumptions.enumerated().compactMap { index, assumption in
            guard let text = nonEmpty(assumption) else { return nil }
            return LimitationRow(id: "assumption_\(index)", text: text)
        })
        if rows.isEmpty {
            rows.append(
                LimitationRow(
                    id: "scope",
                    text: "Панель объясняет текущую presentation-цепочку; она не является ручной разметкой и не гарантирует причинность за пределами доступных признаков."
                )
            )
        }
        return rows
    }

    private static func appendReason(_ rows: inout [ReasonLine],
                                     id: String,
                                     title: String,
                                     text: String?) {
        guard let text = nonEmpty(text) else { return }
        rows.append(ReasonLine(id: id, title: title, text: text))
    }

    private static func orderedTraceIds(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            guard !value.isEmpty, seen.insert(value).inserted else { continue }
            result.append(value)
        }
        return result
    }

    private static func verdictTitle(for verdict: FrameVerdict) -> String {
        switch verdict {
        case .good:
            return "Кадр принят"
        case .mixed:
            return "Можно улучшить"
        case .needsFix:
            return "Нужна правка"
        }
    }

    private static func issueTitle(_ issue: IssueTypeV1) -> String {
        switch issue {
        case .subjectTooCloseToEdge:
            return "Субъект близко к краю"
        case .subjectNotProminentEnough:
            return "Субъект недостаточно заметен"
        case .backgroundCompetesWithSubject:
            return "Фон конкурирует с субъектом"
        case .insufficientLookSpace:
            return "Недостаточно пространства взгляда"
        case .backlightHidesSubject:
            return "Контровой свет скрывает субъект"
        case .sceneHasNoClearFocus:
            return "Нет ясного фокуса внимания"
        case .frameVisuallyOverloaded:
            return "Кадр визуально перегружен"
        case .horizonDistracts:
            return "Горизонт отвлекает"
        }
    }

    private static func strengthTitle(_ strength: StrengthTypeV1) -> String {
        switch strength {
        case .goodSubjectIsolation:
            return "Субъект хорошо отделён"
        case .goodLightEmphasis:
            return "Свет подчёркивает субъект"
        case .clearFocusHierarchy:
            return "Ясная иерархия фокуса"
        case .stableHorizonSupportsScene:
            return "Горизонт поддерживает сцену"
        case .balancedCompositionForScene:
            return "Композиция сбалансирована"
        }
    }

    private static func semanticActionTitle(_ action: SemanticActionType) -> String {
        switch action {
        case .shiftFrameLeft:
            return "Сместить кадр влево"
        case .shiftFrameRight:
            return "Сместить кадр вправо"
        case .shiftFrameUp:
            return "Поднять кадр"
        case .shiftFrameDown:
            return "Опустить кадр"
        case .stepBack:
            return "Отойти назад"
        case .stepCloser:
            return "Подойти ближе"
        case .lowerCamera:
            return "Опустить камеру"
        case .raiseCamera:
            return "Поднять камеру"
        case .changeCameraAngle:
            return "Сменить ракурс"
        case .levelHorizon:
            return "Выровнять горизонт"
        case .rotateSubjectTowardLight:
            return "Повернуть субъект к свету"
        case .moveSubjectLeft:
            return "Сдвинуть субъект левее"
        case .moveSubjectRight:
            return "Сдвинуть субъект правее"
        case .moveSubjectAwayFromBackground:
            return "Отделить субъект от фона"
        case .moveObjectLeft:
            return "Сдвинуть объект левее"
        case .moveObjectRight:
            return "Сдвинуть объект правее"
        case .moveObjectForward:
            return "Подвинуть объект вперёд"
        case .moveObjectBack:
            return "Отодвинуть объект назад"
        case .removeDistractingObject:
            return "Убрать отвлекающий объект"
        case .repositionPropForBalance:
            return "Переставить объект для баланса"
        case .addFrontFillLight:
            return "Добавить фронтальный заполняющий свет"
        case .addBackgroundLight:
            return "Добавить фоновый свет"
        case .removeBackgroundHotspot:
            return "Убрать яркое пятно на фоне"
        case .simplifyBackground:
            return "Упростить фон"
        case .waitForBackgroundClearance:
            return "Дождаться чистого фона"
        case .keepCurrentSetup:
            return "Оставить текущую постановку"
        }
    }

    private static func overlaySummary(_ annotations: [OverlayAnnotationPresentation]) -> String {
        let arrowCount = annotations.filter { $0.kind == .arrow }.count
        let regionCount = annotations.filter { $0.kind == .regionHighlight }.count
        let horizonCount = annotations.filter { $0.kind == .horizonLine }.count
        return "arrows=\(arrowCount), regions=\(regionCount), horizon=\(horizonCount)"
    }

    private static func regionDescription(_ region: NormalizedRect?) -> String? {
        guard let region else { return nil }
        return "x=\(percentString(region.x)), y=\(percentString(region.y)), w=\(percentString(region.width)), h=\(percentString(region.height))"
    }

    private static func pointString(_ point: CGPoint) -> String {
        "x=\(percentString(point.x)), y=\(percentString(point.y))"
    }

    private static func percentString(_ value: CGFloat) -> String {
        percentString(Double(value))
    }

    private static func percentString(_ value: Double) -> String {
        "\(Int((value * 100.0).rounded()))%"
    }

    private static func decimalString(_ value: CGFloat) -> String {
        decimalString(Double(value))
    }

    private static func decimalString(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
