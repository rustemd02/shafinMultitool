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
        let locale = Locale(identifier: "en")
        for actionType in ActionTypeV1.allCases {
            let liveText = "Точная команда для " + actionType.rawValue + "."
            let presentation = CameraOverlayUXPresentation.make(
                liveHint: makeLiveHint(text: liveText, actionType: actionType),
                locale: locale
            )

            if actionType == .leaveFrameAsIs {
                XCTAssertEqual(presentation.state, .keepAsIs)
                XCTAssertEqual(
                    presentation.actionInstruction,
                    SETCopyKey.actionMain.localizedString(locale: locale)
                )
                XCTAssertFalse(presentation.showsWhy)
                XCTAssertNil(presentation.overlayHint)
            } else {
                XCTAssertEqual(presentation.state, .stableTip, actionType.rawValue)
                XCTAssertEqual(presentation.baseState, .stableTip)
                XCTAssertEqual(
                    presentation.actionInstruction,
                    SETCameraCopy.actionKey(for: actionType).localizedString(locale: locale),
                    actionType.rawValue
                )
                XCTAssertTrue(presentation.showsWhy, actionType.rawValue)
                XCTAssertNotNil(presentation.explanation, actionType.rawValue)
                XCTAssertFalse(containsCyrillic(presentation.visibleCopy.joined(separator: " ")))
            }
        }
    }

    func testObjectInstructionIsNotRewrittenFromActionEnum() {
        let liveText = "Сдвиньте предмет левее."
        let presentation = CameraOverlayUXPresentation.make(
            liveHint: makeLiveHint(text: liveText, actionType: .moveFrameLeft)
        )

        XCTAssertEqual(
            presentation.actionInstruction,
            SETCopyKey.cameraCorrectiveMoveLeft.localizedString(locale: .current)
        )
        XCTAssertFalse(presentation.actionInstruction?.contains("Сдвиньте") ?? false)
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
            makeLiveHint(actionType: nil, expandedVerdict: nil),
            makeLiveHint(
                actionType: nil,
                expandedVerdict: LiveExpandedVerdictPresentation(
                    shortVerdict: "   ",
                    supportingText: "Есть объяснение.",
                    actionText: nil,
                    fallbackUsed: false
                )
            ),
            makeLiveHint(id: "   ", actionType: .moveFrameLeft),
            makeLiveHint(confidence: .infinity, actionType: .moveFrameLeft),
            makeLiveHint(
                actionType: .moveFrameLeft,
                expandedVerdict: LiveExpandedVerdictPresentation(
                    shortVerdict: "Главный объект у края.",
                    supportingText: "trace: внутренние данные",
                    actionText: "После смещения объект будет читаться спокойнее.",
                    fallbackUsed: false
                )
            ),
            makeLiveHint(
                actionType: nil,
                expandedVerdict: LiveExpandedVerdictPresentation(
                    shortVerdict: "Главный объект у края.",
                    supportingText: nil,
                    actionText: "semantic reserve output",
                    fallbackUsed: false
                )
            ),
            makeLiveHint(
                actionType: .leaveFrameAsIs,
                expandedVerdict: LiveExpandedVerdictPresentation(
                    shortVerdict: "Кадр уже сбалансирован.",
                    supportingText: "Всё выглядит спокойно.",
                    actionText: "confidence: 0.9",
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

    func testActionableHintWithoutExplanationRemainsStableWithWhyHidden() {
        let liveText = "Сдвиньте предмет левее."
        let hint = makeLiveHint(
            text: liveText,
            actionType: .moveFrameLeft,
            expandedVerdict: LiveExpandedVerdictPresentation(
                shortVerdict: "Главный объект у края.",
                supportingText: nil,
                actionText: nil,
                fallbackUsed: false
            )
        )

        let presentation = CameraOverlayUXPresentation.make(
            liveHint: hint,
            isExpanded: true,
            locale: Locale(identifier: "en")
        )
        XCTAssertEqual(presentation.state, .stableTip)
        XCTAssertEqual(
            presentation.observation,
            SETCopyKey.cameraCorrectiveObservation.localizedString(locale: Locale(identifier: "en"))
        )
        XCTAssertEqual(
            presentation.actionInstruction,
            SETCopyKey.cameraCorrectiveMoveLeft.localizedString(locale: Locale(identifier: "en"))
        )
        XCTAssertNil(presentation.explanation)
        XCTAssertFalse(presentation.showsWhy)
    }

    func testTechnicalHintUsesLiveTextAndExpandsWhenExplanationExists() {
        let liveText = "Проверьте фокус на объекте."
        let hint = makeLiveHint(
            text: liveText,
            actionType: nil,
            overlayHint: OverlayHint(
                id: "technical-geometry-must-not-render",
                kind: .arrow,
                targetRegion: NormalizedRect(x: 0.62, y: 0.2, width: 0.24, height: 0.44),
                direction: .left
            ),
            technicalIssueType: .defocus
        )

        let collapsed = CameraOverlayUXPresentation.make(liveHint: hint, locale: Locale(identifier: "en"))
        XCTAssertEqual(collapsed.state, .stableTip)
        XCTAssertEqual(collapsed.observation, SETCopyKey.cameraCorrectiveObservation.localizedString(locale: Locale(identifier: "en")))
        XCTAssertEqual(collapsed.actionInstruction, SETCopyKey.cameraTechnicalRefocusSubject.localizedString(locale: Locale(identifier: "en")))
        XCTAssertEqual(collapsed.explanation, SETCopyKey.cameraExplanation.localizedString(locale: Locale(identifier: "en")))
        XCTAssertTrue(collapsed.showsWhy)
        XCTAssertFalse(containsCyrillic(collapsed.visibleCopy.joined(separator: " ")))
        XCTAssertNil(collapsed.overlayHint)
        XCTAssertNil(collapsed.targetRegion)

        let expanded = CameraOverlayUXPresentation.make(
            liveHint: hint,
            isExpanded: true,
            locale: Locale(identifier: "en")
        )
        XCTAssertEqual(expanded.state, .explanation)
        XCTAssertEqual(
            expanded.actionInstruction,
            SETCopyKey.cameraTechnicalRefocusSubject.localizedString(locale: Locale(identifier: "en"))
        )
        XCTAssertEqual(expanded.explanation, collapsed.explanation)
        XCTAssertNil(expanded.overlayHint)
    }

    func testTechnicalHintWithoutExplanationRemainsStableWithWhyHidden() {
        let liveText = "Оценка качества кадра завершена."
        let hint = makeLiveHint(
            text: liveText,
            actionType: nil,
            technicalIssueType: .defocus,
            expandedVerdict: LiveExpandedVerdictPresentation(
                shortVerdict: "Кадр можно оценить без дополнительных пояснений.",
                supportingText: nil,
                actionText: nil,
                fallbackUsed: false
            )
        )

        let presentation = CameraOverlayUXPresentation.make(liveHint: hint, isExpanded: true, locale: Locale(identifier: "en"))
        XCTAssertEqual(presentation.state, .stableTip)
        XCTAssertEqual(presentation.observation, SETCopyKey.cameraCorrectiveObservation.localizedString(locale: Locale(identifier: "en")))
        XCTAssertEqual(presentation.actionInstruction, SETCopyKey.cameraTechnicalRefocusSubject.localizedString(locale: Locale(identifier: "en")))
        XCTAssertNil(presentation.explanation)
        XCTAssertFalse(presentation.showsWhy)
        XCTAssertNil(presentation.overlayHint)
    }

    func testCorrectiveGuideIsKeptOnlyForTheActiveAction() {
        let corrective = makeLiveHint(
            actionType: .moveFrameLeft,
            overlayHint: OverlayHint(
                id: "guide-left",
                kind: .arrow,
                targetRegion: NormalizedRect(x: 0.62, y: 0.2, width: 0.24, height: 0.44),
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

    func testRegionlessCorrectiveAdviceRemainsTextOnly() {
        let regionless = makeLiveHint(
            actionType: .moveFrameLeft,
            overlayHint: OverlayHint(id: "guide-without-region", kind: .arrow, direction: .left)
        )
        let presentation = CameraOverlayUXPresentation.make(liveHint: regionless)
        XCTAssertNil(presentation.overlayHint)
        XCTAssertNil(presentation.targetRegion)
        XCTAssertEqual(presentation.state, .stableTip)
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

    func testSeekingKeepAndFallbackFollowRequestedLocale() {
        let english = Locale(identifier: "en")
        let russian = Locale(identifier: "ru")

        XCTAssertEqual(
            CameraOverlayUXPresentation.make(liveHint: nil, locale: english).observation,
            SETCopyKey.cameraSeeking.localizedString(locale: english)
        )
        XCTAssertEqual(
            CameraOverlayUXPresentation.make(liveHint: nil, locale: russian).observation,
            SETCopyKey.cameraSeeking.localizedString(locale: russian)
        )

        let keep = makeLiveHint(actionType: .leaveFrameAsIs)
        let englishKeep = CameraOverlayUXPresentation.make(liveHint: keep, locale: english)
        let russianKeep = CameraOverlayUXPresentation.make(liveHint: keep, locale: russian)
        XCTAssertEqual(englishKeep.observation, SETCopyKey.cameraKeep.localizedString(locale: english))
        XCTAssertEqual(englishKeep.actionInstruction, SETCopyKey.actionMain.localizedString(locale: english))
        XCTAssertEqual(russianKeep.observation, SETCopyKey.cameraKeep.localizedString(locale: russian))
        XCTAssertEqual(russianKeep.actionInstruction, SETCopyKey.actionMain.localizedString(locale: russian))

        let fallback = makeLiveHint(text: "Наблюдение", actionType: .moveFrameLeft)
        let englishFallback = CameraOverlayUXPresentation.make(
            liveHint: LiveHintPresentation(
                id: "fallback",
                frameId: "frame-fallback",
                text: "   ",
                confidence: 0.7,
                actionType: .moveFrameLeft,
                actionId: nil,
                linkedIssueIds: [],
                summaryId: nil,
                traceRootIds: [],
                targetRegion: nil,
                overlayHint: nil,
                isFallback: true,
                expandedVerdict: nil
            ),
            locale: english
        )
        XCTAssertEqual(englishFallback.observation, SETCopyKey.cameraFallback.localizedString(locale: english))
        XCTAssertNil(englishFallback.targetRegion)
    }

    func testEverySemanticActionProjectsToCatalogCopyInEnglish() {
        let locale = Locale(identifier: "en")
        for semanticActionType in SemanticActionType.allCases {
            let presentation = CameraOverlayUXPresentation.make(
                liveHint: makeLiveHint(
                    text: "Русская команда из ядра",
                    actionType: .changeAngle,
                    semanticActionType: semanticActionType
                ),
                locale: locale
            )

            XCTAssertEqual(
                presentation.actionInstruction,
                SETCameraCopy.actionKey(for: semanticActionType).localizedString(locale: locale),
                semanticActionType.rawValue
            )
            XCTAssertFalse(containsCyrillic(presentation.visibleCopy.joined(separator: " ")))
        }
    }

    func testEveryTechnicalIssueProjectsToCatalogCopyInEnglish() {
        let locale = Locale(identifier: "en")
        let issueTypes: [TechnicalQualityIssueType] = [
            .motionBlur, .defocus, .overexposure, .underexposure, .noise, .occlusion, .lensSmudge
        ]

        for issueType in issueTypes {
            let presentation = CameraOverlayUXPresentation.make(
                liveHint: makeLiveHint(
                    text: "Русская техническая команда из ядра",
                    actionType: nil,
                    technicalIssueType: issueType
                ),
                locale: locale
            )

            XCTAssertEqual(
                presentation.actionInstruction,
                SETCameraCopy.technicalActionKey(for: issueType).localizedString(locale: locale),
                issueType.rawValue
            )
            XCTAssertFalse(containsCyrillic(presentation.visibleCopy.joined(separator: " ")))
        }
    }

    private func makeLiveHint(
        id: String = "hint-1",
        frameId: String = "frame-1",
        text: String = "Сигнал кадра.",
        confidence: Double = 0.86,
        actionType: ActionTypeV1? = .moveFrameLeft,
        overlayHint: OverlayHint? = nil,
        semanticActionType: SemanticActionType? = nil,
        technicalIssueType: TechnicalQualityIssueType? = nil,
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
            expandedVerdict: expandedVerdict,
            semanticActionType: semanticActionType,
            technicalIssueType: technicalIssueType
        )
    }

    private func containsCyrillic(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x0400...0x04FF).contains(scalar.value)
        }
    }

}
