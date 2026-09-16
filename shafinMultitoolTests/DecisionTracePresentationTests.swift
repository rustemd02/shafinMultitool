import CoreGraphics
import XCTest
@testable import shafinMultitool

final class DecisionTracePresentationTests: XCTestCase {
    func testPauseTraceConnectsVerdictEvidenceActionsAndLimitations() {
        let critique = PauseCritiquePresentation(
            frameId: "frame_trace_pause",
            verdict: .mixed,
            verdictConfidence: 0.74,
            summaryId: "summary_trace",
            shortVerdict: "Кадр можно улучшить: фон спорит с главным объектом.",
            whyGood: "Субъект читается достаточно уверенно.",
            whyProblematic: "Фон конкурирует с главным объектом и забирает внимание.",
            strengths: [
                PauseStrengthRow(
                    strengthId: "str_focus",
                    type: .clearFocusHierarchy,
                    rationale: "Главный объект всё ещё распознаётся как центр внимания.",
                    confidence: 0.68,
                    supportingRegion: nil,
                    traceRefId: "trace_strength_focus"
                )
            ],
            issues: [
                PauseIssueRow(
                    issueId: "iss_background",
                    type: .backgroundCompetesWithSubject,
                    severity: 0.63,
                    confidence: 0.79,
                    rationale: "Контрастный фон находится слишком близко к субъекту.",
                    affectedRegion: NormalizedRect(x: 0.55, y: 0.2, width: 0.3, height: 0.5),
                    suggestedFixTypes: [.reframing],
                    traceRefId: "trace_issue_background"
                )
            ],
            actions: [
                PauseActionRow(
                    actionId: "act_simplify",
                    actionType: .reduceBackgroundDistractions,
                    semanticActionType: .simplifyBackground,
                    priority: 1,
                    confidence: 0.81,
                    linkedIssueIds: ["iss_background"],
                    expectedOutcome: "Упростить фон, чтобы внимание вернулось к субъекту.",
                    targetRegion: nil,
                    overlayHintId: "overlay_background",
                    traceRefId: "trace_action_simplify"
                )
            ],
            noChangeRationale: nil,
            assumptions: ["Субъект считается главным объектом кадра."],
            traceRootIds: ["trace_root_pause"],
            fallbackUsed: true
        )

        let trace = DecisionTracePresentation.pause(
            critique: critique,
            overlayAnnotations: [
                OverlayAnnotationPresentation(
                    id: "overlay_background",
                    kind: .regionHighlight,
                    direction: nil,
                    targetRegion: NormalizedRect(x: 0.55, y: 0.2, width: 0.3, height: 0.5),
                    emphasis: 0.9
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
            )
        )

        XCTAssertEqual(trace.modeLabel, "Пауза")
        XCTAssertEqual(trace.verdictLabel, "Можно улучшить")
        XCTAssertEqual(
            trace.headline,
            SETCopyKey.traceVerdictMixed.localizedString(locale: Locale(identifier: "ru"))
        )
        XCTAssertEqual(trace.confidence.percent, 74)
        XCTAssertTrue(trace.reasonLines.isEmpty)
        XCTAssertTrue(trace.evidenceRows.isEmpty)

        XCTAssertEqual(trace.actionRows.first?.semanticActionId, "simplify_background")
        XCTAssertTrue(trace.actionRows.first?.linkedEvidenceIds.isEmpty == true)
        XCTAssertEqual(trace.actionRows.first?.detail, "Сместись к выбранной точке, где фон за человеком чище")
        XCTAssertEqual(trace.actionRows.first?.traceId, "trace_action_simplify")

        let rawNeuralCopy = [
            critique.shortVerdict,
            critique.whyGood ?? "",
            critique.whyProblematic ?? "",
            critique.issues[0].rationale,
            critique.actions[0].expectedOutcome
        ]
        let renderedCopy = [trace.headline]
            + trace.reasonLines.map(\.text)
            + trace.evidenceRows.map(\.text)
            + trace.actionRows.map(\.detail)
        for rawCopy in rawNeuralCopy where !rawCopy.isEmpty {
            XCTAssertFalse(renderedCopy.contains(rawCopy), rawCopy)
        }

        XCTAssertTrue(trace.signalRows.contains(where: { $0.title == "DETR objects" && $0.value == "2" }))
        XCTAssertTrue(trace.signalRows.contains(where: { $0.title == "Overlay annotations" && $0.value == "1" }))
        XCTAssertTrue(trace.limitationRows.contains(where: { $0.text.contains("fallback") }))
        XCTAssertFalse(trace.limitationRows.contains(where: { $0.text == "Субъект считается главным объектом кадра." }))
        XCTAssertEqual(trace.traceIds, [
            "trace_root_pause",
            "trace_issue_background",
            "trace_strength_focus",
            "trace_action_simplify"
        ])
    }

    func testLiveTraceExplainsCurrentHintAndFallbackBoundary() {
        let hint = LiveHintPresentation(
            id: "live_trace_hint",
            frameId: "frame_trace_live",
            text: "Смести кадр чуть вправо.",
            confidence: 0.66,
            actionType: .moveFrameRight,
            actionId: "act_live_right",
            linkedIssueIds: ["iss_edge"],
            summaryId: "summary_live",
            traceRootIds: ["trace_live_root"],
            targetRegion: nil,
            overlayHint: nil,
            isFallback: true,
            expandedVerdict: LiveExpandedVerdictPresentation(
                shortVerdict: "Главный объект слишком близко к краю.",
                supportingText: "Стабильность сигнала средняя, поэтому совет показан как осторожный.",
                actionText: "Смести камеру вправо на небольшой шаг.",
                fallbackUsed: true
            ),
            semanticActionType: .shiftFrameRight,
            linkedEvidence: CameraLinkedEvidenceProjection(
                frameID: "frame_trace_live",
                actionID: "act_live_right",
                actionType: .moveFrameRight,
                semanticActionType: .shiftFrameRight,
                issueID: "iss_edge",
                issueType: .subjectTooCloseToEdge,
                evidence: [EvidenceRef(source: .snapshot, key: "subject.edge", value: "observed")]
            )
        )

        let trace = DecisionTracePresentation.live(
            hint: hint,
            overlayAnnotations: [],
            debugSignals: .empty
        )

        XCTAssertEqual(trace.modeLabel, "Live")
        XCTAssertEqual(trace.verdictLabel, "Текущая подсказка")
        XCTAssertEqual(
            trace.headline,
            SETCopyKey.cameraCorrectiveObservation.localizedString(locale: Locale(identifier: "ru"))
        )
        XCTAssertEqual(trace.actionRows.first?.semanticActionId, "shift_frame_right")
        XCTAssertEqual(
            trace.actionRows.first?.detail,
            SETCopyKey.traceActionShiftRight.localizedString(locale: Locale(identifier: "ru"))
        )
        XCTAssertEqual(
            trace.reasonLines.map(\.text),
            [SETCopyKey.traceIssueSubjectEdge.localizedString(locale: Locale(identifier: "ru"))]
        )
        XCTAssertEqual(trace.evidenceRows.map(\.sourceId), ["iss_edge"])
        XCTAssertEqual(trace.evidenceRows.first?.kindLabel, SETCopyKey.traceKindIssue.localizedString(locale: Locale(identifier: "ru")))
        XCTAssertEqual(trace.evidenceRows.first?.title, SETCopyKey.traceIssueSubjectEdge.localizedString(locale: Locale(identifier: "ru")))
        XCTAssertTrue(trace.limitationRows.contains(where: { $0.text.contains("fallback") }))
        XCTAssertEqual(trace.traceIds, ["trace_live_root"])

        let rawNeuralCopy = [
            hint.text,
            hint.expandedVerdict?.shortVerdict ?? "",
            hint.expandedVerdict?.supportingText ?? "",
            hint.expandedVerdict?.actionText ?? ""
        ]
        let renderedCopy = [trace.headline]
            + trace.reasonLines.map(\.text)
            + trace.evidenceRows.map(\.text)
            + trace.actionRows.map(\.detail)
        for rawCopy in rawNeuralCopy where !rawCopy.isEmpty {
            XCTAssertFalse(renderedCopy.contains(rawCopy), rawCopy)
        }
    }

    func testLiveTraceOmitsExplanationWhenIssueIDIsUnknown() {
        let hint = LiveHintPresentation(
            id: "unlinked_hint",
            frameId: "unlinked_frame",
            text: "Neural text must not be rendered.",
            confidence: 0.8,
            actionType: .moveFrameLeft,
            actionId: "unlinked_action",
            linkedIssueIds: ["missing"],
            summaryId: "unlinked_summary",
            traceRootIds: [],
            targetRegion: nil,
            overlayHint: nil,
            isFallback: false,
            expandedVerdict: LiveExpandedVerdictPresentation(
                shortVerdict: "Unsupported speculation.",
                supportingText: "Unsupported speculation.",
                actionText: "Unsupported speculation.",
                fallbackUsed: false
            )
        )

        let trace = DecisionTracePresentation.live(
            hint: hint,
            locale: Locale(identifier: "en")
        )

        XCTAssertEqual(trace.headline, SETCopyKey.cameraCorrectiveObservation.localizedString(locale: Locale(identifier: "en")))
        XCTAssertTrue(trace.reasonLines.isEmpty)
        XCTAssertTrue(trace.evidenceRows.isEmpty)
        XCTAssertEqual(trace.actionRows.first?.detail, "Aim the camera slightly left, keeping the subject in the preview")
        XCTAssertTrue(trace.actionRows.first?.linkedEvidenceIds.isEmpty == true)
        XCTAssertFalse(trace.headline.contains("Unsupported speculation"))
    }

    func testEvidenceProjectionLocalizesObservedIssueAndRejectsNeuralOnlyEvidence() {
        let builder = DeterministicCritiqueSummaryBuilder()
        let observedIssue = FrameIssue(
            id: "issue_projection",
            type: .subjectTooCloseToEdge,
            severity: 0.78,
            confidence: 0.84,
            rationale: "Opaque rationale.",
            evidence: [EvidenceRef(source: .snapshot, key: "subject.edge", value: "observed")]
        )
        let critique = CritiqueReport(
            frameId: "frame_projection",
            mode: .live,
            verdict: .needsFix,
            verdictConfidence: 0.84,
            strengths: [],
            issues: [observedIssue],
            summary: CritiqueSummary(id: "summary_projection", shortVerdict: "Opaque summary."),
            traceRefs: [],
            fallbackUsed: false
        )
        let action = RecommendationAction(
            id: "action_projection",
            actionType: .moveFrameLeft,
            priority: 1,
            targetRegion: nil,
            linkedIssueIds: ["issue_projection"],
            expectedOutcome: "Opaque outcome.",
            guardrail: ActionGuardrail(
                requiresStillCamera: true,
                minConfidence: 0.5,
                suppressWhenMoving: true
            ),
            overlayHint: nil
        )
        guard let observed = builder.makeEvidenceProjection(
            frameID: "frame_projection",
            action: action,
            semanticActionType: .shiftFrameLeft,
            critique: critique
        ) else {
            XCTFail("same-frame linked observed evidence should project")
            return
        }

        XCTAssertEqual(observed.issueID, "issue_projection")
        XCTAssertNil(builder.makeEvidenceProjection(frameID: "stale_frame", action: action, critique: critique))

        let unknownAction = RecommendationAction(
            id: action.id,
            actionType: action.actionType,
            priority: action.priority,
            targetRegion: action.targetRegion,
            linkedIssueIds: ["missing"],
            expectedOutcome: action.expectedOutcome,
            guardrail: action.guardrail,
            overlayHint: action.overlayHint
        )
        XCTAssertNil(builder.makeEvidenceProjection(frameID: critique.frameId, action: unknownAction, critique: critique))

        XCTAssertEqual(
            builder.makeExplanation(for: observed, locale: Locale(identifier: "ru")),
            SETCopyKey.traceIssueSubjectEdge.localizedString(locale: Locale(identifier: "ru"))
        )
        XCTAssertEqual(
            builder.makeExplanation(for: observed, locale: Locale(identifier: "en")),
            SETCopyKey.traceIssueSubjectEdge.localizedString(locale: Locale(identifier: "en"))
        )

        let neuralOnly = CameraLinkedEvidenceProjection(
            frameID: observed.frameID,
            actionID: observed.actionID,
            actionType: observed.actionType,
            semanticActionType: observed.semanticActionType,
            issueID: observed.issueID,
            issueType: observed.issueType,
            evidence: [EvidenceRef(source: .neuralEvidence, key: "subject.edge", value: "model-only")]
        )
        XCTAssertNil(builder.makeExplanation(for: neuralOnly, locale: Locale(identifier: "en")))

        let neuralIssue = FrameIssue(
            id: observed.issueID,
            type: observed.issueType,
            severity: 0.78,
            confidence: 0.84,
            rationale: "Neural-only rationale.",
            evidence: [EvidenceRef(source: .neuralEvidence, key: "subject.edge", value: "model-only")]
        )
        let neuralCritique = CritiqueReport(
            frameId: critique.frameId,
            mode: critique.mode,
            verdict: critique.verdict,
            verdictConfidence: critique.verdictConfidence,
            strengths: [],
            issues: [neuralIssue],
            summary: critique.summary,
            traceRefs: [],
            fallbackUsed: false
        )
        XCTAssertNil(builder.makeEvidenceProjection(frameID: critique.frameId, action: action, critique: neuralCritique))

        let summaryOnly = CameraLinkedEvidenceProjection(
            frameID: observed.frameID,
            actionID: observed.actionID,
            actionType: observed.actionType,
            semanticActionType: observed.semanticActionType,
            issueID: observed.issueID,
            issueType: observed.issueType,
            evidence: [EvidenceRef(source: .derivedRule, key: "summary.shortVerdict", value: "opaque summary")]
        )
        XCTAssertNil(builder.makeExplanation(for: summaryOnly, locale: Locale(identifier: "en")))
    }

    func testLiveTraceUsesExplicitSemanticObjectActionWhenCoarseActionDiffers() {
        let hint = LiveHintPresentation(
            id: "object_action_hint",
            frameId: "object_action_frame",
            text: "Переместите объект вправо.",
            confidence: 0.82,
            actionType: .moveFrameLeft,
            actionId: "object_action",
            linkedIssueIds: ["object_issue"],
            summaryId: "object_summary",
            traceRootIds: [],
            targetRegion: nil,
            overlayHint: nil,
            isFallback: false,
            expandedVerdict: LiveExpandedVerdictPresentation(
                shortVerdict: "Объект требует смещения.",
                supportingText: "Свободное пространство справа подтверждено.",
                actionText: "Переместите объект вправо.",
                fallbackUsed: false
            ),
            semanticActionType: .moveObjectRight,
            linkedEvidence: CameraLinkedEvidenceProjection(
                frameID: "object_action_frame",
                actionID: "object_action",
                actionType: .moveFrameLeft,
                semanticActionType: .moveObjectRight,
                issueID: "object_issue",
                issueType: .subjectTooCloseToEdge,
                evidence: [EvidenceRef(source: .snapshot, key: "subject.edge", value: "observed")]
            )
        )

        let trace = DecisionTracePresentation.live(hint: hint, locale: Locale(identifier: "en"))
        XCTAssertEqual(trace.actionRows.first?.coarseActionId, ActionTypeV1.moveFrameLeft.rawValue)
        XCTAssertEqual(trace.actionRows.first?.semanticActionId, SemanticActionType.moveObjectRight.rawValue)
        XCTAssertEqual(
            trace.actionRows.first?.detail,
            SETCopyKey.traceActionMoveObjectRight.localizedString(locale: Locale(identifier: "en"))
        )
        XCTAssertEqual(trace.evidenceRows.map(\.sourceId), ["object_issue"])
    }
}
