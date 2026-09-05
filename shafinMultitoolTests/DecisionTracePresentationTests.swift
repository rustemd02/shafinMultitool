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
            SETCopyKey.traceIssueBackgroundCompetes.localizedString(locale: Locale(identifier: "ru"))
        )
        XCTAssertEqual(trace.confidence.percent, 74)
        XCTAssertEqual(
            trace.reasonLines.map(\.text),
            [SETCopyKey.traceIssueBackgroundCompetes.localizedString(locale: Locale(identifier: "ru"))]
        )

        XCTAssertEqual(trace.evidenceRows.map(\.sourceId), ["iss_background", "str_focus"])
        XCTAssertEqual(trace.evidenceRows.first?.title, "Фон конкурирует с субъектом")
        XCTAssertEqual(trace.evidenceRows.first?.text, "Фон конкурирует с субъектом")
        XCTAssertEqual(trace.evidenceRows.first?.traceId, "trace_issue_background")

        XCTAssertEqual(trace.actionRows.first?.semanticActionId, "simplify_background")
        XCTAssertEqual(trace.actionRows.first?.linkedEvidenceIds, ["iss_background"])
        XCTAssertEqual(trace.actionRows.first?.detail, "Упростить фон")
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
        XCTAssertTrue(trace.limitationRows.contains(where: { $0.text == "Субъект считается главным объектом кадра." }))
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
            [SETCopyKey.cameraExplanation.localizedString(locale: Locale(identifier: "ru"))]
        )
        XCTAssertEqual(trace.evidenceRows.map(\.sourceId), ["iss_edge"])
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

    func testLiveTraceOmitsExplanationWhenEvidenceIsUnlinked() {
        let hint = LiveHintPresentation(
            id: "unlinked_hint",
            frameId: "unlinked_frame",
            text: "Neural text must not be rendered.",
            confidence: 0.8,
            actionType: .moveFrameLeft,
            actionId: "unlinked_action",
            linkedIssueIds: [],
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
        XCTAssertEqual(trace.actionRows.first?.detail, "Move your subject right")
        XCTAssertFalse(trace.headline.contains("Unsupported speculation"))
    }
}
