import CoreGraphics
import XCTest
@testable import shafinMultitool

final class CameraOverlayUXPresentationTests: XCTestCase {
    func testNoLiveHintMapsToSeekingState() {
        let presentation = CameraOverlayUXPresentation.make(liveHint: nil)

        XCTAssertEqual(presentation.state, .liveSeeking)
        XCTAssertEqual(presentation.observation, CameraOverlayUXPresentation.seekingLine)
        XCTAssertNil(presentation.actionInstruction)
        XCTAssertFalse(presentation.showsWhy)
        XCTAssertFalse(presentation.isFallback)
    }

    func testEverySupportedActionMapsToOnePhysicalInstruction() {
        for actionType in ActionTypeV1.allCases {
            let presentation = CameraOverlayUXPresentation.make(
                liveHint: makeLiveHint(actionType: actionType)
            )

            if actionType == .leaveFrameAsIs {
                XCTAssertEqual(presentation.state, .keepAsIs)
                XCTAssertEqual(presentation.actionInstruction, "Снимайте")
                XCTAssertFalse(presentation.showsWhy)
                XCTAssertNil(presentation.overlayHint)
            } else {
                XCTAssertEqual(presentation.state, .stableTip, actionType.rawValue)
                XCTAssertEqual(presentation.baseState, .stableTip)
                XCTAssertEqual(presentation.actionInstruction, expectedInstruction(for: actionType), actionType.rawValue)
                XCTAssertTrue(presentation.showsWhy, actionType.rawValue)
                XCTAssertNotNil(presentation.explanation, actionType.rawValue)
            }
        }
    }

    func testWhyExpansionAndCollapseRemainTheSameLiveTip() {
        let hint = makeLiveHint(actionType: .moveFrameLeft)
        let collapsed = CameraOverlayUXPresentation.make(liveHint: hint, isExpanded: false)
        let expanded = CameraOverlayUXPresentation.make(liveHint: hint, isExpanded: true)

        XCTAssertEqual(collapsed.state, .stableTip)
        XCTAssertEqual(expanded.state, .explanation)
        XCTAssertEqual(expanded.baseState, .stableTip)
        XCTAssertEqual(expanded.liveHintID, collapsed.liveHintID)
        XCTAssertEqual(expanded.actionInstruction, collapsed.actionInstruction)
        XCTAssertEqual(expanded.explanation, collapsed.explanation)

        let collapsedAgain = CameraOverlayUXPresentation.make(liveHint: hint, isExpanded: false)
        XCTAssertEqual(collapsedAgain.state, .stableTip)
        XCTAssertEqual(collapsedAgain.liveHintID, expanded.liveHintID)
    }

    func testIncompleteOrMalformedPayloadUsesOneSafeNontechnicalLine() {
        let malformedHints = [
            makeLiveHint(text: "   ", actionType: .moveFrameLeft),
            makeLiveHint(actionType: nil),
            makeLiveHint(id: "   ", actionType: .moveFrameLeft),
            makeLiveHint(confidence: .infinity, actionType: .moveFrameLeft),
            makeLiveHint(
                actionType: .moveFrameLeft,
                expandedVerdict: LiveExpandedVerdictPresentation(
                    shortVerdict: "Главный объект у края.",
                    supportingText: nil,
                    actionText: nil,
                    fallbackUsed: false
                )
            )
        ]

        for hint in malformedHints {
            let presentation = CameraOverlayUXPresentation.make(liveHint: hint)

            XCTAssertEqual(presentation.state, .liveSeeking)
            XCTAssertTrue(presentation.isFallback)
            XCTAssertEqual(presentation.visibleCopy, [CameraOverlayUXPresentation.safeFallbackLine])
            XCTAssertNil(presentation.actionInstruction)
            XCTAssertNil(presentation.explanation)
            XCTAssertNil(presentation.overlayHint)
        }
    }

    func testCorrectiveGuideIsKeptOnlyForTheActiveAction() {
        let corrective = makeLiveHint(
            actionType: .moveFrameLeft,
            overlayHint: OverlayHint(
                id: "guide-left",
                kind: .arrow,
                direction: .left
            )
        )
        let keepAsIs = makeLiveHint(
            text: "Свет на объекте равномерный.",
            actionType: .leaveFrameAsIs,
            overlayHint: OverlayHint(
                id: "should-not-render",
                kind: .regionHighlight,
                targetRegion: NormalizedRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3)
            )
        )

        XCTAssertNotNil(CameraOverlayUXPresentation.make(liveHint: corrective).overlayHint)
        XCTAssertNil(CameraOverlayUXPresentation.make(liveHint: keepAsIs).overlayHint)
    }

    func testForbiddenCopyNeverReachesTheSurface() {
        let forbiddenFragments = [
            "%", "trace", "semantic", "reserve", "confidence", "pipeline", "GOOD", "REVIEW",
            "трейс", "семантика", "резерв", "уверенность"
        ]

        for fragment in forbiddenFragments {
            let presentation = CameraOverlayUXPresentation.make(
                liveHint: makeLiveHint(
                    text: "Наблюдение \(fragment)",
                    actionType: .moveFrameLeft
                )
            )

            XCTAssertEqual(presentation.visibleCopy, [CameraOverlayUXPresentation.safeFallbackLine], fragment)
            let visibleCopy = presentation.visibleCopy.joined(separator: " ").lowercased()
            XCTAssertFalse(visibleCopy.contains(fragment.lowercased()), fragment)
        }
    }

    func testAccessibilityContractHasStableIdentifiersAndMinimumTargets() {
        let identifiers = [
            CameraOverlayAccessibilityID.surface,
            CameraOverlayAccessibilityID.observation,
            CameraOverlayAccessibilityID.action,
            CameraOverlayAccessibilityID.why,
            CameraOverlayAccessibilityID.explanation,
            CameraOverlayAccessibilityID.seeking,
            CameraOverlayAccessibilityID.zoom
        ]
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        XCTAssertTrue(identifiers.allSatisfy { !$0.isEmpty })
        XCTAssertGreaterThanOrEqual(CameraOverlayUXPresentation.minimumControlDimension, 44)

        let presentation = CameraOverlayUXPresentation.make(liveHint: makeLiveHint(actionType: .levelHorizon))
        XCTAssertEqual(presentation.accessibilityLabel, presentation.visibleCopy.joined(separator: ". "))
        XCTAssertTrue(presentation.accessibilityLabel.contains(presentation.observation))
        XCTAssertTrue(presentation.accessibilityLabel.contains(presentation.actionInstruction ?? ""))
    }

    func testPortraitAndLandscapeLayoutMetricsAreDeterministic() {
        let portrait = CGSize(width: 390, height: 844)
        let landscape = CGSize(width: 844, height: 390)

        XCTAssertEqual(CameraOverlayUXPresentation.surfaceWidth(for: portrait), 358, accuracy: 0.001)
        XCTAssertEqual(CameraOverlayUXPresentation.surfaceWidth(for: landscape), 420, accuracy: 0.001)
        XCTAssertEqual(
            CameraOverlayUXPresentation.lowerThirdBottomInset(hasZoomControl: false),
            28,
            accuracy: 0.001
        )
        XCTAssertEqual(
            CameraOverlayUXPresentation.lowerThirdBottomInset(hasZoomControl: true),
            104,
            accuracy: 0.001
        )

        let attachment = XCTAttachment(string: "portrait width=358 bottom=28\nlandscape width=420 bottom=104")
        attachment.name = "camera-coach-lower-third-layout.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func makeLiveHint(
        id: String = "hint-1",
        frameId: String = "frame-1",
        text: String = "Сигнал кадра.",
        confidence: Double = 0.86,
        actionType: ActionTypeV1? = .moveFrameLeft,
        overlayHint: OverlayHint? = nil,
        expandedVerdict: LiveExpandedVerdictPresentation? = LiveExpandedVerdictPresentation(
            shortVerdict: "Главный объект теряется у края.",
            supportingText: "Слева осталось мало свободного пространства.",
            actionText: "После смещения объект будет читаться спокойнее.",
            fallbackUsed: false
        )
    ) -> LiveHintPresentation {
        LiveHintPresentation(
            id: id,
            frameId: frameId,
            text: text,
            confidence: confidence,
            actionType: actionType,
            actionId: "action-1",
            linkedIssueIds: ["issue-1"],
            summaryId: "summary-1",
            traceRootIds: ["trace-1"],
            targetRegion: NormalizedRect(x: 0.62, y: 0.2, width: 0.24, height: 0.44),
            overlayHint: overlayHint,
            isFallback: false,
            expandedVerdict: expandedVerdict
        )
    }

    private func expectedInstruction(for actionType: ActionTypeV1) -> String {
        switch actionType {
        case .moveFrameLeft:
            return "Сместите камеру немного влево."
        case .moveFrameRight:
            return "Сместите камеру немного вправо."
        case .moveFrameUp:
            return "Поднимите камеру немного выше."
        case .moveFrameDown:
            return "Опустите камеру немного ниже."
        case .increaseSubjectSize:
            return "Подойдите ближе к главному объекту."
        case .reduceBackgroundDistractions:
            return "Упростите фон вокруг главного объекта."
        case .changeAngle:
            return "Измените угол съёмки."
        case .improveFrontLight:
            return "Добавьте мягкий свет спереди."
        case .levelHorizon:
            return "Выровняйте камеру."
        case .leaveFrameAsIs:
            return "Снимайте"
        }
    }
}
