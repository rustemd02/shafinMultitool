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
        XCTAssertEqual(trace.headline, "Кадр можно улучшить: фон спорит с главным объектом.")
        XCTAssertEqual(trace.confidence.percent, 74)
        XCTAssertTrue(trace.reasonLines.map(\.text).contains("Фон конкурирует с главным объектом и забирает внимание."))

        XCTAssertEqual(trace.evidenceRows.map(\.sourceId), ["iss_background", "str_focus"])
        XCTAssertEqual(trace.evidenceRows.first?.title, "Фон конкурирует с субъектом")
        XCTAssertEqual(trace.evidenceRows.first?.traceId, "trace_issue_background")

        XCTAssertEqual(trace.actionRows.first?.semanticActionId, "simplify_background")
        XCTAssertEqual(trace.actionRows.first?.linkedEvidenceIds, ["iss_background"])
        XCTAssertEqual(trace.actionRows.first?.traceId, "trace_action_simplify")

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
        XCTAssertEqual(trace.headline, "Смести кадр чуть вправо.")
        XCTAssertEqual(trace.actionRows.first?.semanticActionId, "shift_frame_right")
        XCTAssertTrue(trace.reasonLines.map(\.text).contains("Главный объект слишком близко к краю."))
        XCTAssertTrue(trace.reasonLines.map(\.text).contains("Стабильность сигнала средняя, поэтому совет показан как осторожный."))
        XCTAssertTrue(trace.limitationRows.contains(where: { $0.text.contains("fallback") }))
        XCTAssertEqual(trace.traceIds, ["trace_live_root"])
    }
}
