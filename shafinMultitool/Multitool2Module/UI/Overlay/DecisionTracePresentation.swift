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
                        debugSignals: DecisionTraceDebugSignals,
                        locale: Locale = Locale(identifier: "ru")) -> DecisionTracePresentation? {
        if isPaused, let pauseCritique {
            return pause(
                critique: pauseCritique,
                overlayAnnotations: overlayAnnotations,
                debugSignals: debugSignals,
                locale: locale
            )
        }
        if !isPaused, let liveHint {
            return live(
                hint: liveHint,
                overlayAnnotations: overlayAnnotations,
                debugSignals: debugSignals,
                locale: locale
            )
        }
        return nil
    }

    static func pause(critique: PauseCritiquePresentation,
                      overlayAnnotations: [OverlayAnnotationPresentation] = [],
                      debugSignals: DecisionTraceDebugSignals = .empty,
                      locale: Locale = Locale(identifier: "ru")) -> DecisionTracePresentation {
        let reasonLines = pauseReasonLines(for: critique, locale: locale)
        let evidenceRows = pauseEvidenceRows(for: critique, locale: locale)
        let actionRows = pauseActionRows(for: critique, locale: locale)
        let limitations = limitationRows(
            fallbackUsed: critique.fallbackUsed,
            assumptions: critique.assumptions,
            locale: locale
        )
        let traceIds = orderedTraceIds(
            critique.traceRootIds
                + critique.issues.compactMap(\.traceRefId)
                + critique.strengths.compactMap(\.traceRefId)
                + critique.actions.compactMap(\.traceRefId)
        )

        return DecisionTracePresentation(
            id: "pause_\(critique.frameId)_\(critique.summaryId)",
            modeLabel: copy(.traceModePause, locale: locale),
            verdictLabel: verdictTitle(for: critique.verdict, locale: locale),
            headline: critique.shortVerdict,
            confidence: .make(critique.verdictConfidence),
            reasonLines: reasonLines,
            evidenceRows: evidenceRows,
            actionRows: actionRows,
            signalRows: signalRows(
                overlayAnnotations: overlayAnnotations,
                debugSignals: debugSignals,
                locale: locale
            ),
            limitationRows: limitations,
            traceIds: traceIds
        )
    }

    static func live(hint: LiveHintPresentation,
                     overlayAnnotations: [OverlayAnnotationPresentation] = [],
                     debugSignals: DecisionTraceDebugSignals = .empty,
                     locale: Locale = Locale(identifier: "ru")) -> DecisionTracePresentation {
        let reasonLines = liveReasonLines(for: hint, locale: locale)
        let actionRows = liveActionRows(for: hint, locale: locale)
        let limitations = limitationRows(
            fallbackUsed: hint.isFallback || hint.expandedVerdict?.fallbackUsed == true,
            assumptions: hint.linkedIssueIds.isEmpty
                ? []
                : [format(.traceAssumptionLinkedIssues, locale: locale, arguments: [hint.linkedIssueIds.joined(separator: ", ")])],
            locale: locale
        )

        return DecisionTracePresentation(
            id: "live_\(hint.frameId)_\(hint.id)",
            modeLabel: copy(.traceModeLive, locale: locale),
            verdictLabel: copy(.traceVerdictLive, locale: locale),
            headline: hint.text,
            confidence: .make(hint.confidence),
            reasonLines: reasonLines,
            evidenceRows: [],
            actionRows: actionRows,
            signalRows: signalRows(
                overlayAnnotations: overlayAnnotations,
                debugSignals: debugSignals,
                locale: locale
            ),
            limitationRows: limitations,
            traceIds: orderedTraceIds(hint.traceRootIds)
        )
    }

#if DEBUG
    /// Deterministic evidence for the real trace surface. Text is resolved
    /// through the requested locale so the fixture never bakes one language
    /// into the presentation payload.
    static func debugFixture(locale: Locale) -> DecisionTracePresentation {
        let issueRegion = NormalizedRect(x: 0.55, y: 0.20, width: 0.30, height: 0.50)
        let issueID = "fixture_issue_background"
        let issueTraceID = "fixture_trace_issue_background"
        let strengthTraceID = "fixture_trace_strength_focus"
        let actionTraceID = "fixture_trace_action_simplify"
        let critique = PauseCritiquePresentation(
            frameId: "fixture_trace_frame",
            verdict: .mixed,
            verdictConfidence: 0.78,
            summaryId: "fixture_trace_summary",
            shortVerdict: copy(.cameraCorrectiveObservation, locale: locale),
            whyGood: copy(.traceStrengthFocus, locale: locale),
            whyProblematic: copy(.traceIssueBackgroundCompetes, locale: locale),
            strengths: [
                PauseStrengthRow(
                    strengthId: "fixture_strength_focus",
                    type: .clearFocusHierarchy,
                    rationale: copy(.traceStrengthFocus, locale: locale),
                    confidence: 0.72,
                    supportingRegion: nil,
                    traceRefId: strengthTraceID
                )
            ],
            issues: [
                PauseIssueRow(
                    issueId: issueID,
                    type: .backgroundCompetesWithSubject,
                    severity: 0.64,
                    confidence: 0.81,
                    rationale: copy(.traceIssueBackgroundCompetes, locale: locale),
                    affectedRegion: issueRegion,
                    suggestedFixTypes: [.reframing],
                    traceRefId: issueTraceID
                )
            ],
            actions: [
                PauseActionRow(
                    actionId: "fixture_action_simplify",
                    actionType: .reduceBackgroundDistractions,
                    semanticActionType: .simplifyBackground,
                    priority: 1,
                    confidence: 0.84,
                    linkedIssueIds: [issueID],
                    expectedOutcome: copy(.traceActionSimplifyBackground, locale: locale),
                    targetRegion: issueRegion,
                    overlayHintId: "fixture_overlay_background",
                    traceRefId: actionTraceID
                )
            ],
            noChangeRationale: nil,
            assumptions: [
                format(.traceAssumptionLinkedIssues, locale: locale, arguments: [issueID])
            ],
            traceRootIds: ["fixture_trace_root"],
            fallbackUsed: false
        )
        return pause(
            critique: critique,
            overlayAnnotations: [
                OverlayAnnotationPresentation(
                    id: "fixture_overlay_background",
                    kind: .regionHighlight,
                    direction: nil,
                    targetRegion: issueRegion,
                    emphasis: 0.85
                )
            ],
            debugSignals: DecisionTraceDebugSignals(
                detrObjectCount: 2,
                visionSubjectCount: 1,
                saliencyCenter: CGPoint(x: 0.62, y: 0.48),
                subjectAreaRatio: 0.18,
                horizonAngle: -1.6,
                horizonConfidence: 0.72,
                backlightIndex: 0.31,
                exposureBiasHint: -0.12,
                motionState: "still",
                aestheticScore: 0.57
            ),
            locale: locale
        )
    }
#endif

    private static func pauseReasonLines(for critique: PauseCritiquePresentation,
                                         locale: Locale) -> [ReasonLine] {
        var rows: [ReasonLine] = []
        if critique.verdict == .good {
            appendReason(&rows, id: "why_good", title: copy(.traceReasonWorked, locale: locale), text: critique.whyGood)
            appendReason(&rows, id: "no_change", title: copy(.traceReasonKeep, locale: locale), text: critique.noChangeRationale)
        } else {
            appendReason(&rows, id: "why_problematic", title: copy(.traceReasonProblematic, locale: locale), text: critique.whyProblematic)
            appendReason(&rows, id: "why_good", title: copy(.traceReasonWorked, locale: locale), text: critique.whyGood)
        }
        if rows.isEmpty {
            appendReason(&rows, id: "summary", title: copy(.traceReasonSummary, locale: locale), text: critique.shortVerdict)
        }
        return rows
    }

    private static func liveReasonLines(for hint: LiveHintPresentation,
                                        locale: Locale) -> [ReasonLine] {
        var rows: [ReasonLine] = []
        appendReason(&rows, id: "short_verdict", title: copy(.traceReasonSignal, locale: locale), text: hint.expandedVerdict?.shortVerdict)
        appendReason(&rows, id: "supporting_text", title: copy(.traceReasonWhy, locale: locale), text: hint.expandedVerdict?.supportingText)
        appendReason(&rows, id: "action_text", title: copy(.traceReasonAction, locale: locale), text: hint.expandedVerdict?.actionText)
        if rows.isEmpty {
            appendReason(&rows, id: "hint", title: copy(.traceReasonHint, locale: locale), text: hint.text)
        }
        return rows
    }

    private static func pauseEvidenceRows(for critique: PauseCritiquePresentation,
                                          locale: Locale) -> [EvidenceRow] {
        let issueRows = critique.issues.map { issue in
            EvidenceRow(
                id: "issue_\(issue.issueId)",
                sourceId: issue.issueId,
                kindLabel: copy(.traceKindIssue, locale: locale),
                title: issueTitle(issue.type, locale: locale),
                text: issue.rationale,
                confidence: .make(issue.confidence),
                severity: .make(issue.severity),
                regionDescription: regionDescription(issue.affectedRegion, locale: locale),
                traceId: issue.traceRefId
            )
        }
        let strengthRows = critique.strengths.map { strength in
            EvidenceRow(
                id: "strength_\(strength.strengthId)",
                sourceId: strength.strengthId,
                kindLabel: copy(.traceKindStrength, locale: locale),
                title: strengthTitle(strength.type, locale: locale),
                text: strength.rationale,
                confidence: .make(strength.confidence),
                severity: nil,
                regionDescription: regionDescription(strength.supportingRegion, locale: locale),
                traceId: strength.traceRefId
            )
        }
        return issueRows + strengthRows
    }

    private static func pauseActionRows(for critique: PauseCritiquePresentation,
                                        locale: Locale) -> [ActionRow] {
        let rows = critique.actions.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            return lhs.actionId < rhs.actionId
        }.map { action in
            ActionRow(
                id: action.actionId,
                title: semanticActionTitle(action.semanticActionType, locale: locale),
                semanticActionId: action.semanticActionType.rawValue,
                coarseActionId: action.actionType.rawValue,
                detail: action.expectedOutcome,
                linkedEvidenceIds: action.linkedIssueIds,
                confidence: .make(action.confidence),
                targetDescription: regionDescription(action.targetRegion, locale: locale),
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
                title: semanticActionTitle(.keepCurrentSetup, locale: locale),
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

    private static func liveActionRows(for hint: LiveHintPresentation,
                                       locale: Locale) -> [ActionRow] {
        guard let actionType = hint.actionType else {
            return []
        }
        let semanticAction = actionType.semanticActionType
        return [
            ActionRow(
                id: hint.actionId ?? "live_action",
                title: semanticActionTitle(semanticAction, locale: locale),
                semanticActionId: semanticAction.rawValue,
                coarseActionId: actionType.rawValue,
                detail: hint.expandedVerdict?.actionText ?? hint.text,
                linkedEvidenceIds: hint.linkedIssueIds,
                confidence: .make(hint.confidence),
                targetDescription: regionDescription(hint.targetRegion, locale: locale),
                overlayHintId: hint.overlayHint?.id,
                traceId: nil
            )
        ]
    }

    private static func signalRows(overlayAnnotations: [OverlayAnnotationPresentation],
                                  debugSignals: DecisionTraceDebugSignals,
                                  locale: Locale) -> [SignalRow] {
        var rows: [SignalRow] = []
        if debugSignals.detrObjectCount > 0 {
            rows.append(
                SignalRow(
                    id: "detr",
                    title: copy(.traceSignalDETR, locale: locale),
                    value: "\(debugSignals.detrObjectCount)",
                    detail: copy(.traceSignalDETRDetail, locale: locale)
                )
            )
        }
        if debugSignals.visionSubjectCount > 0 {
            rows.append(
                SignalRow(
                    id: "vision",
                    title: copy(.traceSignalVision, locale: locale),
                    value: "\(debugSignals.visionSubjectCount)",
                    detail: copy(.traceSignalVisionDetail, locale: locale)
                )
            )
        }
        if !overlayAnnotations.isEmpty {
            rows.append(
                SignalRow(
                    id: "overlay",
                    title: copy(.traceSignalOverlay, locale: locale),
                    value: "\(overlayAnnotations.count)",
                    detail: overlaySummary(overlayAnnotations, locale: locale)
                )
            )
        }
        if let saliencyCenter = debugSignals.saliencyCenter {
            rows.append(
                SignalRow(
                    id: "saliency",
                    title: copy(.traceSignalSaliency, locale: locale),
                    value: pointString(saliencyCenter, locale: locale),
                    detail: copy(.traceSignalSaliencyDetail, locale: locale)
                )
            )
        }
        if let subjectAreaRatio = debugSignals.subjectAreaRatio {
            rows.append(
                SignalRow(
                    id: "subject_area",
                    title: copy(.traceSignalSubjectArea, locale: locale),
                    value: percentString(subjectAreaRatio),
                    detail: copy(.traceSignalSubjectAreaDetail, locale: locale)
                )
            )
        }
        if let horizonAngle = debugSignals.horizonAngle,
           let horizonConfidence = debugSignals.horizonConfidence {
            rows.append(
                SignalRow(
                    id: "horizon",
                    title: copy(.traceSignalHorizon, locale: locale),
                    value: "\(decimalString(horizonAngle))°",
                    detail: format(
                        .traceSignalHorizonDetail,
                        locale: locale,
                        arguments: [percentString(horizonConfidence)]
                    )
                )
            )
        }
        if let backlightIndex = debugSignals.backlightIndex {
            rows.append(
                SignalRow(
                    id: "backlight",
                    title: copy(.traceSignalBacklight, locale: locale),
                    value: percentString(backlightIndex),
                    detail: copy(.traceSignalBacklightDetail, locale: locale)
                )
            )
        }
        if let exposureBiasHint = debugSignals.exposureBiasHint {
            rows.append(
                SignalRow(
                    id: "exposure",
                    title: copy(.traceSignalExposure, locale: locale),
                    value: decimalString(exposureBiasHint),
                    detail: copy(.traceSignalExposureDetail, locale: locale)
                )
            )
        }
        if let motionState = nonEmpty(debugSignals.motionState) {
            rows.append(
                SignalRow(
                    id: "motion",
                    title: copy(.traceSignalMotion, locale: locale),
                    value: motionState,
                    detail: copy(.traceSignalMotionDetail, locale: locale)
                )
            )
        }
        if let aestheticScore = debugSignals.aestheticScore {
            rows.append(
                SignalRow(
                    id: "aesthetic",
                    title: copy(.traceSignalAesthetic, locale: locale),
                    value: percentString(aestheticScore),
                    detail: copy(.traceSignalAestheticDetail, locale: locale)
                )
            )
        }
        return rows
    }

    private static func limitationRows(fallbackUsed: Bool,
                                       assumptions: [String],
                                       locale: Locale) -> [LimitationRow] {
        var rows: [LimitationRow] = []
        if fallbackUsed {
            rows.append(
                LimitationRow(
                    id: "fallback",
                    text: copy(.traceLimitFallback, locale: locale)
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
                    text: copy(.traceLimitScope, locale: locale)
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

    private static func verdictTitle(for verdict: FrameVerdict,
                                     locale: Locale) -> String {
        switch verdict {
        case .good:
            return copy(.traceVerdictGood, locale: locale)
        case .mixed:
            return copy(.traceVerdictMixed, locale: locale)
        case .needsFix:
            return copy(.traceVerdictNeedsFix, locale: locale)
        }
    }

    private static func issueTitle(_ issue: IssueTypeV1,
                                   locale: Locale) -> String {
        switch issue {
        case .subjectTooCloseToEdge:
            return copy(.traceIssueSubjectEdge, locale: locale)
        case .subjectNotProminentEnough:
            return copy(.traceIssueSubjectProminence, locale: locale)
        case .backgroundCompetesWithSubject:
            return copy(.traceIssueBackgroundCompetes, locale: locale)
        case .insufficientLookSpace:
            return copy(.traceIssueLookSpace, locale: locale)
        case .backlightHidesSubject:
            return copy(.traceIssueBacklight, locale: locale)
        case .sceneHasNoClearFocus:
            return copy(.traceIssueFocus, locale: locale)
        case .frameVisuallyOverloaded:
            return copy(.traceIssueOverloaded, locale: locale)
        case .horizonDistracts:
            return copy(.traceIssueHorizon, locale: locale)
        }
    }

    private static func strengthTitle(_ strength: StrengthTypeV1,
                                      locale: Locale) -> String {
        switch strength {
        case .goodSubjectIsolation:
            return copy(.traceStrengthIsolation, locale: locale)
        case .goodLightEmphasis:
            return copy(.traceStrengthLight, locale: locale)
        case .clearFocusHierarchy:
            return copy(.traceStrengthFocus, locale: locale)
        case .stableHorizonSupportsScene:
            return copy(.traceStrengthHorizon, locale: locale)
        case .balancedCompositionForScene:
            return copy(.traceStrengthComposition, locale: locale)
        }
    }

    private static func semanticActionTitle(_ action: SemanticActionType,
                                            locale: Locale) -> String {
        switch action {
        case .shiftFrameLeft:
            return copy(.traceActionShiftLeft, locale: locale)
        case .shiftFrameRight:
            return copy(.traceActionShiftRight, locale: locale)
        case .shiftFrameUp:
            return copy(.traceActionShiftUp, locale: locale)
        case .shiftFrameDown:
            return copy(.traceActionShiftDown, locale: locale)
        case .stepBack:
            return copy(.traceActionStepBack, locale: locale)
        case .stepCloser:
            return copy(.traceActionStepCloser, locale: locale)
        case .lowerCamera:
            return copy(.traceActionLowerCamera, locale: locale)
        case .raiseCamera:
            return copy(.traceActionRaiseCamera, locale: locale)
        case .changeCameraAngle:
            return copy(.traceActionChangeAngle, locale: locale)
        case .levelHorizon:
            return copy(.traceActionLevelHorizon, locale: locale)
        case .rotateSubjectTowardLight:
            return copy(.traceActionRotateSubject, locale: locale)
        case .moveSubjectLeft:
            return copy(.traceActionMoveSubjectLeft, locale: locale)
        case .moveSubjectRight:
            return copy(.traceActionMoveSubjectRight, locale: locale)
        case .moveSubjectAwayFromBackground:
            return copy(.traceActionMoveSubjectAway, locale: locale)
        case .moveObjectLeft:
            return copy(.traceActionMoveObjectLeft, locale: locale)
        case .moveObjectRight:
            return copy(.traceActionMoveObjectRight, locale: locale)
        case .moveObjectForward:
            return copy(.traceActionMoveObjectForward, locale: locale)
        case .moveObjectBack:
            return copy(.traceActionMoveObjectBack, locale: locale)
        case .removeDistractingObject:
            return copy(.traceActionRemoveDistractingObject, locale: locale)
        case .repositionPropForBalance:
            return copy(.traceActionRepositionProp, locale: locale)
        case .addFrontFillLight:
            return copy(.traceActionAddFrontFill, locale: locale)
        case .addBackgroundLight:
            return copy(.traceActionAddBackgroundLight, locale: locale)
        case .removeBackgroundHotspot:
            return copy(.traceActionRemoveHotspot, locale: locale)
        case .simplifyBackground:
            return copy(.traceActionSimplifyBackground, locale: locale)
        case .waitForBackgroundClearance:
            return copy(.traceActionWaitClearance, locale: locale)
        case .keepCurrentSetup:
            return copy(.traceActionKeepSetup, locale: locale)
        }
    }

    private static func overlaySummary(_ annotations: [OverlayAnnotationPresentation],
                                       locale: Locale) -> String {
        let arrowCount = annotations.filter { $0.kind == .arrow }.count
        let regionCount = annotations.filter { $0.kind == .regionHighlight }.count
        let horizonCount = annotations.filter { $0.kind == .horizonLine }.count
        return format(
            .traceOverlaySummary,
            locale: locale,
            arguments: [arrowCount, regionCount, horizonCount]
        )
    }

    private static func regionDescription(_ region: NormalizedRect?,
                                          locale: Locale) -> String? {
        guard let region else { return nil }
        return format(
            .traceRegionCoordinates,
            locale: locale,
            arguments: [
                percentString(region.x),
                percentString(region.y),
                percentString(region.width),
                percentString(region.height)
            ]
        )
    }

    private static func pointString(_ point: CGPoint,
                                   locale: Locale) -> String {
        format(
            .tracePointCoordinates,
            locale: locale,
            arguments: [
                percentString(point.x),
                percentString(point.y)
            ]
        )
    }

    private static func copy(_ key: SETCopyKey,
                             locale: Locale) -> String {
        key.localizedString(locale: locale)
    }

    private static func format(_ key: SETCopyKey,
                               locale: Locale,
                               arguments: [CVarArg]) -> String {
        key.localizedFormat(locale: locale, arguments: arguments)
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
