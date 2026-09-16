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
                XCTAssertEqual(
                    presentation.explanation,
                    SETCopyKey.traceIssueSubjectEdge.localizedString(locale: locale),
                    actionType.rawValue
                )
                XCTAssertFalse(containsCyrillic(presentation.visibleCopy.joined(separator: " ")))
            }
        }
    }

    func testLinkedExplanationUsesRequestedLocale() {
        let english = Locale(identifier: "en")
        let russian = Locale(identifier: "ru")
        let englishPresentation = CameraOverlayUXPresentation.make(
            liveHint: makeLiveHint(actionType: .moveFrameLeft),
            locale: english
        )
        let russianPresentation = CameraOverlayUXPresentation.make(
            liveHint: makeLiveHint(actionType: .moveFrameLeft),
            locale: russian
        )

        XCTAssertEqual(
            englishPresentation.explanation,
            SETCopyKey.traceIssueSubjectEdge.localizedString(locale: english)
        )
        XCTAssertEqual(
            russianPresentation.explanation,
            SETCopyKey.traceIssueSubjectEdge.localizedString(locale: russian)
        )
        XCTAssertFalse(containsCyrillic(englishPresentation.visibleCopy.joined(separator: " ")))
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

    func testActionableHintUsesLinkedEvidenceWithoutFreeformExplanationText() {
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
        XCTAssertEqual(presentation.state, .explanation)
        XCTAssertEqual(
            presentation.observation,
            SETCopyKey.cameraCorrectiveObservation.localizedString(locale: Locale(identifier: "en"))
        )
        XCTAssertEqual(
            presentation.actionInstruction,
            SETCopyKey.cameraCorrectiveMoveLeft.localizedString(locale: Locale(identifier: "en"))
        )
        XCTAssertEqual(
            presentation.explanation,
            SETCopyKey.traceIssueSubjectEdge.localizedString(locale: Locale(identifier: "en"))
        )
        XCTAssertTrue(presentation.showsWhy)
    }

    func testUnlinkedEvidenceHidesWhyEvenWhenFreeformTextExists() {
        let presentation = CameraOverlayUXPresentation.make(
            liveHint: makeLiveHint(
                actionType: .moveFrameLeft,
                linkedIssueIDs: [],
                expandedVerdict: LiveExpandedVerdictPresentation(
                    shortVerdict: "Unsupported speculation.",
                    supportingText: "Unsupported speculation.",
                    actionText: "Unsupported speculation.",
                    fallbackUsed: false
                )
            ),
            isExpanded: true,
            locale: Locale(identifier: "en")
        )

        XCTAssertEqual(presentation.state, .stableTip)
        XCTAssertNil(presentation.explanation)
        XCTAssertFalse(presentation.showsWhy)
    }

    func testUnknownOrStaleEvidenceNeverShowsWhy() {
        let unknown = CameraOverlayUXPresentation.make(
            liveHint: makeLiveHint(
                actionType: .moveFrameLeft,
                linkedIssueIDs: ["missing"],
                includeLinkedEvidence: false,
                expandedVerdict: LiveExpandedVerdictPresentation(
                    shortVerdict: "Safe arbitrary text.",
                    supportingText: "Safe arbitrary support.",
                    actionText: "Safe arbitrary action.",
                    fallbackUsed: false
                )
            ),
            isExpanded: true,
            locale: Locale(identifier: "en")
        )
        XCTAssertEqual(unknown.state, .stableTip)
        XCTAssertNil(unknown.explanation)
        XCTAssertFalse(unknown.showsWhy)

        let staleProjection = CameraLinkedEvidenceProjection(
            frameID: "different-frame",
            actionID: "action-1",
            actionType: .moveFrameLeft,
            semanticActionType: .shiftFrameLeft,
            issueID: "issue-1",
            issueType: .subjectTooCloseToEdge,
            evidence: [EvidenceRef(source: .snapshot, key: "subject.edge", value: "observed")]
        )
        let stale = CameraOverlayUXPresentation.make(
            liveHint: makeLiveHint(
                actionType: .moveFrameLeft,
                linkedEvidence: staleProjection
            ),
            isExpanded: true,
            locale: Locale(identifier: "en")
        )
        XCTAssertEqual(stale.state, .stableTip)
        XCTAssertNil(stale.explanation)
        XCTAssertFalse(stale.showsWhy)
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
        XCTAssertNil(collapsed.explanation)
        XCTAssertFalse(collapsed.showsWhy)
        XCTAssertFalse(containsCyrillic(collapsed.visibleCopy.joined(separator: " ")))
        XCTAssertNil(collapsed.overlayHint)
        XCTAssertNil(collapsed.targetRegion)

        let expanded = CameraOverlayUXPresentation.make(
            liveHint: hint,
            isExpanded: true,
            locale: Locale(identifier: "en")
        )
        XCTAssertEqual(expanded.state, .stableTip)
        XCTAssertEqual(
            expanded.actionInstruction,
            SETCopyKey.cameraTechnicalRefocusSubject.localizedString(locale: Locale(identifier: "en"))
        )
        XCTAssertNil(expanded.explanation)
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

    func testTypedFrameGlobalHintsKeepCopyWithoutSpatialGeometry() {
        let locale = Locale(identifier: "en")
        let frameGlobalHints = [
            makeLiveHint(
                actionType: nil,
                targetRegion: nil,
                semanticActionType: .levelHorizon,
                technicalIssueType: nil,
                technicalActionType: nil,
                includeLinkedEvidence: false
            ),
            makeLiveHint(
                actionType: nil,
                targetRegion: nil,
                semanticActionType: nil,
                technicalIssueType: .motionBlur,
                technicalActionType: .stabilizeCamera,
                includeLinkedEvidence: false
            )
        ]

        for hint in frameGlobalHints {
            let presentation = CameraOverlayUXPresentation.make(
                liveHint: hint,
                context: CameraOverlayUXContext(hasSpatialEvidence: false),
                locale: locale
            )
            XCTAssertEqual(presentation.state, .stableTip)
            XCTAssertNotNil(presentation.actionInstruction)
            XCTAssertNil(presentation.targetRegion)
            XCTAssertNil(presentation.overlayHint)
        }

        let subjectBound = CameraOverlayUXPresentation.make(
            liveHint: makeLiveHint(
                actionType: .moveFrameLeft,
                targetRegion: nil,
                includeLinkedEvidence: false
            ),
            context: CameraOverlayUXContext(hasSpatialEvidence: false),
            locale: locale
        )
        XCTAssertEqual(subjectBound.state, .liveSeeking)

        let unknown = CameraOverlayUXPresentation.make(
            liveHint: makeLiveHint(
                actionId: TechnicalQualityActionType.stabilizeCamera.rawValue,
                actionType: nil,
                targetRegion: nil,
                technicalIssueType: .motionBlur,
                technicalActionType: nil,
                includeLinkedEvidence: false
            ),
            context: CameraOverlayUXContext(hasSpatialEvidence: false),
            locale: locale
        )
        XCTAssertEqual(unknown.state, .liveSeeking)
    }

    func testCorrectiveGuideIsKeptOnlyForTheActiveAction() {
        let corrective = makeLiveHint(
            actionType: .moveFrameLeft,
            subjectIdentity: SubjectTrackIdentity(
                trackID: "hint-subject",
                firstSeenFrameID: "frame-1",
                generation: 7
            ),
            observedSourceRegion: NormalizedRect(x: 0.20, y: 0.26, width: 0.22, height: 0.34),
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

        for canvas in [portrait, landscape] {
            for locale in [Locale(identifier: "en"), Locale(identifier: "ru")] {
                let observation = SETCopyKey.cameraEpisodeAwaitingMovement.localizedString(locale: locale)
                let content = SETCameraCoachRailContent(
                    observation: observation + "\n" + observation,
                    actionInstruction: "Move the camera slightly to the left",
                    whyLabel: SETCopyKey.cameraWhy.localizedString(locale: locale)
                )
                let minimum = SETCameraCoachMetric.liveRailHeight(
                    canvasSize: canvas, isAccessibilityType: false, isExpanded: false
                )
                let measured = SETCameraCoachMetric.liveRailHeight(
                    canvasSize: canvas, isAccessibilityType: false, isExpanded: false,
                    content: content
                )
                XCTAssertGreaterThan(measured, minimum, "Wrapped command must enlarge the shared reservation")
                let expanded = SETCameraCoachMetric.liveRailHeight(
                    canvasSize: canvas, isAccessibilityType: false, isExpanded: true,
                    content: SETCameraCoachRailContent(
                        observation: content.observation,
                        actionInstruction: content.actionInstruction,
                        explanation: observation + "\n" + observation,
                        whyLabel: content.whyLabel
                    )
                )
                XCTAssertGreaterThan(expanded, measured)
            }
        }

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

    func testOwnerContextMapsLifecyclePauseLensAndDegradationBoundaries() {
        let hint = makeLiveHint(
            overlayHint: OverlayHint(
                id: "guide",
                kind: .arrow,
                targetRegion: NormalizedRect(x: 0.62, y: 0.2, width: 0.24, height: 0.44),
                direction: .left
            )
        )

        let lifecycleCases: [(CameraLifecycleState, CameraOverlayUXPresentation.State)] = [
            (.starting, .starting),
            (.stopping, .interrupted),
            (.failed(.sessionInterrupted), .interrupted),
            (.failed(.runtimeError), .failed)
        ]
        for (lifecycle, expected) in lifecycleCases {
            let presentation = CameraOverlayUXPresentation.make(
                liveHint: hint,
                context: CameraOverlayUXContext(lifecycleState: lifecycle)
            )
            XCTAssertEqual(presentation.state, expected)
            XCTAssertNil(presentation.markerEventID)
            XCTAssertFalse(presentation.visibleCopy.contains(hint.text))
        }

        let pauseCases: [(CameraPausePresentationState, CameraOverlayUXPresentation.State)] = [
            (.loading(snapshotID: "pause"), .pauseLoading),
            (.empty(snapshotID: "pause"), .pauseEmpty),
            (.failure(snapshotID: "pause"), .pauseFailure),
            (.resuming(snapshotID: "pause"), .resuming)
        ]
        for (pause, expected) in pauseCases {
            XCTAssertEqual(
                CameraOverlayUXPresentation.make(
                    liveHint: hint,
                    context: CameraOverlayUXContext(pauseState: pause)
                ).state,
                expected
            )
        }

        XCTAssertEqual(
            CameraOverlayUXPresentation.make(
                liveHint: hint,
                context: CameraOverlayUXContext(lensState: .switching(.wide))
            ).state,
            .lensSwitching
        )

        let limitedLocale = Locale(identifier: "en")
        let limited = CameraOverlayUXPresentation.make(
            liveHint: hint,
            context: CameraOverlayUXContext(
                performance: CameraRuntimePerformanceSnapshot(
                    budget: ThermalGovernor.Budget(
                        highPriorityFrequency: 2,
                        mediumPriorityFrequency: 0.5,
                        lowPriorityFrequency: 0,
                        heavyModelsEnabled: false
                    ),
                    thermalTier: .constrained
                )
            ),
            locale: limitedLocale
        )
        XCTAssertEqual(limited.state, CameraOverlayUXPresentation.State.liveSeeking)
        XCTAssertTrue(limited.showsECO)
        XCTAssertTrue(limited.isLimited)
        XCTAssertNil(limited.overlayHint)
        let ecoCopy = SETCopyKey.cameraEco.localizedString(locale: limitedLocale)
        XCTAssertEqual(limited.supportingObservation, ecoCopy)
        XCTAssertTrue(limited.accessibilityLabel.contains(ecoCopy))

        let failed = CameraOverlayUXPresentation.make(
            liveHint: hint,
            context: CameraOverlayUXContext(analysisStatus: .failed)
        )
        XCTAssertEqual(failed.state, .failed)
        XCTAssertFalse(failed.isFallback)
        XCTAssertNil(failed.markerEventID)
    }

    func testFailClosedDecisionsNeverShowActionOrExplanation() {
        for decision in [CameraCoachDecisionV2.wait, .selectSubject, .abstain] {
            let presentation = CameraOverlayUXPresentation.make(
                liveHint: makeLiveHint(actionType: .moveFrameLeft),
                context: CameraOverlayUXContext(decision: decision)
            )

            XCTAssertEqual(presentation.state, .liveSeeking, decision.rawValue)
            XCTAssertNil(presentation.actionInstruction, decision.rawValue)
            XCTAssertNil(presentation.explanation, decision.rawValue)
            XCTAssertFalse(presentation.showsWhy, decision.rawValue)
        }
    }

    func testActiveEpisodeWinsOverTransientKeepAndKeepsAcceptedAction() {
        let locale = Locale(identifier: "en")
        let token = CoachingEpisodeToken(
            rawValue: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            generation: 7
        )
        let keepHint = makeLiveHint(
            actionType: .leaveFrameAsIs,
            targetRegion: nil,
            overlayHint: nil,
            includeLinkedEvidence: false
        )
        let expectedAction = SETCameraCopy.actionKey(
            forCanonicalActionID: SemanticActionType.shiftFrameLeft.rawValue
        )!.localizedString(locale: locale)
        let expectedPhases: [(
            CoachingEpisodePhase,
            SETCopyKey,
            CameraOverlayUXPresentation.State
        )] = [
            (.awaitingMovement, .cameraEpisodeAwaitingMovement, .stableTip),
            (.collectingStableAfterFrames, .cameraEpisodeCollecting, .actionObserved),
            (.readyForVerification, .cameraEpisodeChecking, .verification)
        ]

        for (phase, copyKey, expectedState) in expectedPhases {
            let state = makeEpisodeState(
                token: token,
                subjectRegion: NormalizedRect(x: 0.22, y: 0.28, width: 0.22, height: 0.40),
                phase: phase
            )
            let presentation = CameraOverlayUXPresentation.make(
                liveHint: keepHint,
                context: CameraOverlayUXContext(
                    decision: .keep,
                    episodeState: state
                ),
                locale: locale
            )

            XCTAssertEqual(presentation.state, expectedState, phase.rawValue)
            XCTAssertEqual(presentation.observation, copyKey.localizedString(locale: locale), phase.rawValue)
            XCTAssertEqual(
                presentation.actionInstruction,
                phase == .readyForVerification ? nil : expectedAction,
                phase.rawValue
            )
            XCTAssertEqual(presentation.markerEventID, token.rawValue.uuidString, phase.rawValue)
            // `shiftFrameLeft` moves the camera left; its subject-facing
            // displacement/overlay direction is therefore right.
            XCTAssertEqual(presentation.overlayHint?.direction, .right, phase.rawValue)
            XCTAssertNotEqual(presentation.observation, SETCopyKey.cameraKeep.localizedString(locale: locale), phase.rawValue)
        }

        let limited = CameraOverlayUXPresentation.make(
            liveHint: keepHint,
            context: CameraOverlayUXContext(
                decision: .keep,
                episodeState: makeEpisodeState(
                    token: token,
                    subjectRegion: NormalizedRect(x: 0.22, y: 0.28, width: 0.22, height: 0.40),
                    phase: .awaitingMovement
                ),
                performance: CameraRuntimePerformanceSnapshot(
                    budget: ThermalGovernor.Budget(
                        highPriorityFrequency: 2,
                        mediumPriorityFrequency: 0.5,
                        lowPriorityFrequency: 0,
                        heavyModelsEnabled: false
                    ),
                    thermalTier: .constrained
                )
            ),
            locale: locale
        )
        XCTAssertEqual(limited.state, .liveSeeking)
        XCTAssertNil(limited.actionInstruction)
        XCTAssertNil(limited.overlayHint)
    }

    func testMatchingVerificationOutcomesUseLocalizedOwnerCopyAndStaleResultsAreIgnored() {
        let locale = Locale(identifier: "en")
        let token = CoachingEpisodeToken(
            rawValue: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
            generation: 7
        )
        let staleToken = CoachingEpisodeToken(
            rawValue: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!,
            generation: 7
        )
        let state = makeEpisodeState(
            token: token,
            subjectRegion: NormalizedRect(x: 0.22, y: 0.28, width: 0.22, height: 0.40),
            phase: .readyForVerification
        )
        let outcomes: [(ActionVerificationDecision, SETCopyKey, CameraOverlayUXPresentation.State)] = [
            (.comparable(outcome: .improved), .cameraVerificationImproved, .verificationImproved),
            (.comparable(outcome: .unchanged), .cameraVerificationUnchanged, .verificationNotImproved),
            (.comparable(outcome: .worse), .cameraVerificationWorse, .verificationNotImproved),
            (.incomparable(reason: .evidenceMissing), .cameraVerificationIncomparable, .abstention),
            (.comparable(outcome: .fixed), .cameraVerificationFixed, .verificationImproved)
        ]

        for (decision, copyKey, expectedState) in outcomes {
            let result = makeVerificationResult(token: token, decision: decision)
            let presentation = CameraOverlayUXPresentation.make(
                liveHint: makeLiveHint(actionType: .leaveFrameAsIs, includeLinkedEvidence: false),
                context: CameraOverlayUXContext(
                    decision: .keep,
                    episodeState: state,
                    verificationResult: result
                ),
                locale: locale
            )

            XCTAssertEqual(presentation.state, expectedState, copyKey.rawValue)
            XCTAssertEqual(presentation.observation, copyKey.localizedString(locale: locale), copyKey.rawValue)
            XCTAssertNotEqual(presentation.observation, SETCopyKey.cameraKeep.localizedString(locale: locale), copyKey.rawValue)
            if case .incomparable = decision {
                XCTAssertTrue(presentation.isFallback)
                XCTAssertNil(presentation.markerEventID)
                XCTAssertEqual(presentation.episodeToken, token)
                XCTAssertTrue(presentation.canContinueEpisode)
            } else if case .comparable(outcome: .fixed) = decision {
                XCTAssertNil(presentation.markerEventID)
                XCTAssertEqual(presentation.episodeToken, token)
                XCTAssertTrue(presentation.canContinueEpisode)
            } else {
                XCTAssertEqual(presentation.markerEventID, token.rawValue.uuidString)
                XCTAssertEqual(presentation.episodeToken, token)
                XCTAssertTrue(presentation.canContinueEpisode)
            }
        }

        let limitedResult = CameraOverlayUXPresentation.make(
            liveHint: makeLiveHint(actionType: .leaveFrameAsIs, includeLinkedEvidence: false),
            context: CameraOverlayUXContext(
                decision: .keep,
                episodeState: state,
                verificationResult: makeVerificationResult(
                    token: token,
                    decision: .comparable(outcome: .improved)
                ),
                analysisStatus: .limited
            ),
            locale: locale
        )
        XCTAssertEqual(limitedResult.state, .verificationImproved)
        XCTAssertFalse(limitedResult.canContinueEpisode)

        let ecoResult = CameraOverlayUXPresentation.make(
            liveHint: makeLiveHint(actionType: .leaveFrameAsIs, includeLinkedEvidence: false),
            context: CameraOverlayUXContext(
                decision: .keep,
                episodeState: state,
                verificationResult: makeVerificationResult(
                    token: token,
                    decision: .comparable(outcome: .improved)
                ),
                performance: CameraRuntimePerformanceSnapshot(
                    budget: ThermalGovernor.Budget(
                        highPriorityFrequency: 2,
                        mediumPriorityFrequency: 0.5,
                        lowPriorityFrequency: 0,
                        heavyModelsEnabled: false
                    ),
                    thermalTier: .constrained
                )
            ),
            locale: locale
        )
        XCTAssertEqual(ecoResult.state, .verificationImproved)
        XCTAssertFalse(ecoResult.canContinueEpisode)

        let sameTokenBeforeReady = CameraOverlayUXPresentation.make(
            liveHint: makeLiveHint(actionType: .leaveFrameAsIs, includeLinkedEvidence: false),
            context: CameraOverlayUXContext(
                decision: .keep,
                episodeState: makeEpisodeState(
                    token: token,
                    subjectRegion: NormalizedRect(x: 0.22, y: 0.28, width: 0.22, height: 0.40),
                    phase: .awaitingMovement
                ),
                verificationResult: makeVerificationResult(
                    token: token,
                    decision: .comparable(outcome: .improved)
                )
            ),
            locale: locale
        )
        XCTAssertEqual(sameTokenBeforeReady.state, .stableTip)
        XCTAssertEqual(
            sameTokenBeforeReady.observation,
            SETCopyKey.cameraEpisodeAwaitingMovement.localizedString(locale: locale)
        )
        XCTAssertFalse(sameTokenBeforeReady.canContinueEpisode)

        let stale = CameraOverlayUXPresentation.make(
            liveHint: makeLiveHint(actionType: .leaveFrameAsIs, includeLinkedEvidence: false),
            context: CameraOverlayUXContext(
                decision: .keep,
                episodeState: state,
                verificationResult: makeVerificationResult(
                    token: staleToken,
                    decision: .comparable(outcome: .fixed)
                )
            ),
            locale: locale
        )
        XCTAssertEqual(stale.state, .verification)
        XCTAssertEqual(stale.observation, SETCopyKey.cameraEpisodeChecking.localizedString(locale: locale))
        XCTAssertNil(stale.actionInstruction)
        XCTAssertEqual(stale.markerEventID, token.rawValue.uuidString)
    }

    func testLifecyclePriorityHidesActiveEpisodeAndVerificationResult() {
        let token = CoachingEpisodeToken(
            rawValue: UUID(uuidString: "66666666-6666-4666-8666-666666666666")!,
            generation: 7
        )
        let presentation = CameraOverlayUXPresentation.make(
            liveHint: makeLiveHint(actionType: .leaveFrameAsIs, includeLinkedEvidence: false),
            context: CameraOverlayUXContext(
                lifecycleState: .failed(.runtimeError),
                decision: .keep,
                episodeState: makeEpisodeState(
                    token: token,
                    subjectRegion: NormalizedRect(x: 0.22, y: 0.28, width: 0.22, height: 0.40),
                    phase: .readyForVerification
                ),
                verificationResult: makeVerificationResult(
                    token: token,
                    decision: .comparable(outcome: .improved)
                )
            ),
            locale: Locale(identifier: "en")
        )

        XCTAssertEqual(presentation.state, .failed)
        XCTAssertNil(presentation.markerEventID)
        XCTAssertEqual(presentation.observation, SETCopyKey.cameraFailed.localizedString(locale: Locale(identifier: "en")))
        XCTAssertFalse(presentation.observation.contains("checked change"))
    }

    func testCorrectiveGeometryUsesSubjectAndTargetAndStaysInsideSafeRect() {
        let sizes = [
            CGSize(width: 390, height: 844),
            CGSize(width: 844, height: 390),
            CGSize(width: 600, height: 600)
        ]

        for size in sizes {
            let canvas = CGRect(origin: .zero, size: size)
            let safe = canvas.insetBy(dx: 20, dy: 20)
            let subject = CGRect(
                x: safe.minX + size.width * 0.08,
                y: safe.minY + size.height * 0.16,
                width: size.width * 0.16,
                height: size.height * 0.18
            )
            let target = CGRect(
                x: safe.maxX - size.width * 0.24,
                y: safe.minY + size.height * 0.32,
                width: size.width * 0.16,
                height: size.height * 0.18
            )
            guard let geometry = SETCorrectiveArrowGeometry.resolveValidated(
                canvasSize: size,
                targetRect: target,
                commandRailFrame: subject,
                safeInset: 20
            ) else {
                XCTFail("subject/target geometry should be drawable")
                continue
            }
            XCTAssertTrue(safe.contains(geometry.start))
            XCTAssertTrue(safe.contains(geometry.end))
            XCTAssertTrue(geometry.strokeAvoidsTarget())
            XCTAssertEqual(geometry.commandRailFrame, subject.intersection(canvas))
        }
    }

    func testOcclusionPlacementPrefersSafeCornersAndBoundsFallbackBand() {
        let viewport = CGRect(x: 0, y: 0, width: 390, height: 844)
        let safe = viewport.insetBy(dx: 8, dy: 8)
        let placement = CameraOcclusionSolver.resolve(
            viewport: viewport,
            safeRect: safe,
            subjectRect: CGRect(x: 145, y: 190, width: 100, height: 280),
            targetRect: CGRect(x: 270, y: 300, width: 90, height: 180),
            contentSize: CGSize(width: 180, height: 80)
        )
        XCTAssertNotNil(placement)
        XCTAssertTrue(safe.contains(placement!.frame))
        XCTAssertFalse(placement!.frame.intersects(CGRect(x: 145, y: 190, width: 100, height: 280)))
        XCTAssertFalse(placement!.frame.intersects(CGRect(x: 270, y: 300, width: 90, height: 180)))

        let fallback = CameraOcclusionSolver.resolve(
            viewport: viewport,
            safeRect: safe,
            subjectRect: safe,
            contentSize: CGSize(width: 380, height: 200)
        )
        XCTAssertNotNil(fallback)
        XCTAssertLessThanOrEqual(fallback!.frame.width, 360)
        XCTAssertLessThanOrEqual(fallback!.frame.height, 96)
        XCTAssertTrue(safe.contains(fallback!.frame))
    }

    func testProductionPlannerCarriesSubjectDestinationInsteadOfAffectedRegion() {
        let subject = NormalizedRect(x: 0.22, y: 0.28, width: 0.22, height: 0.40)
        let snapshot = FrameFeatureSnapshot(
            frameId: "production-target-frame",
            mode: .live,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
            sources: FeatureSourceStatus(
                vision: SourceState(available: true, freshnessMs: 12, confidence: 0.94),
                horizon: SourceState(available: true, freshnessMs: 12, confidence: 0.90),
                lighting: SourceState(available: true, freshnessMs: 12, confidence: 0.90),
                detr: SourceState(available: true, freshnessMs: 12, confidence: 0.90),
                aesthetic: SourceState(available: true, freshnessMs: 12, confidence: 0.90)
            ),
            composition: .init(
                horizontalOffset: 0.34,
                verticalOffset: 0,
                subjectAreaRatio: 0.12,
                saliencyLeftRightBalance: 0.34,
                saliencyTopBottomBalance: 0
            ),
            subjectSignals: .init(
                faceDetected: true,
                personDetected: true,
                personCount: 1,
                faceRegion: subject,
                primaryCandidateRegion: subject,
                primaryCandidateConfidence: 0.94,
                primaryCandidateSource: .vision
            ),
            horizon: .init(angleDegrees: 0, confidence: 0.90),
            lighting: .init(exposureBiasHint: 0, backlightIndex: 0, keyToFillRatio: 1),
            motion: .init(state: .still, shakeLevel: 0.02),
            aesthetics: .init(score: 0.70, scoreConfidence: 0.80),
            objects: .init(totalCount: 1, topKLabels: ["person"]),
            technicalFlags: []
        )
        let issue = FrameIssue(
            id: "production-subject-edge",
            type: .subjectTooCloseToEdge,
            severity: 0.92,
            confidence: 0.94,
            rationale: "Subject edge pressure.",
            evidence: [EvidenceRef(source: .snapshot, key: "subject", value: "accepted", confidence: 0.94)],
            affectedRegion: subject,
            suggestedFixTypes: [.reframing]
        )
        let critique = CritiqueReport(
            frameId: snapshot.frameId,
            mode: .live,
            verdict: .needsFix,
            verdictConfidence: 0.94,
            strengths: [],
            issues: [issue],
            summary: .init(id: "production-target-summary", shortVerdict: "Кадр требует правки."),
            traceRefs: ["production-target-trace"],
            fallbackUsed: false
        )

        let plan = RecommendationPlanner().makePlan(snapshot: snapshot, critique: critique)

        XCTAssertEqual(plan.primaryAction?.actionType, .moveFrameRight)
        XCTAssertEqual(
            plan.primaryAction?.targetRegion,
            SemanticActionType.shiftFrameRight.subjectTargetRegion(from: subject, sourceSpace: .vision)
        )
        XCTAssertNotEqual(plan.primaryAction?.targetRegion, issue.affectedRegion)
        XCTAssertFalse(overlaps(plan.primaryAction?.targetRegion, subject))
    }

    func testEpisodeTokenOwnsMarkerIdentityAndFrozenTargetGeometry() {
        let subject = NormalizedRect(x: 0.22, y: 0.28, width: 0.22, height: 0.40)
        let target = SemanticActionType.shiftFrameLeft
            .subjectTargetRegion(from: subject, sourceSpace: .subjectTarget)!
            .converted(from: .subjectTarget, to: .vision)!
        let firstToken = CoachingEpisodeToken(
            rawValue: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            generation: 7
        )
        let secondToken = CoachingEpisodeToken(
            rawValue: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            generation: 7
        )
        let firstState = makeEpisodeState(token: firstToken, subjectRegion: subject)
        let secondState = makeEpisodeState(token: secondToken, subjectRegion: subject)
        let context = CameraOverlayUXContext(
            episodeState: firstState,
            hasSpatialEvidence: true
        )
        let changedHint = makeLiveHint(
            targetRegion: NormalizedRect(x: 0.72, y: 0.10, width: 0.20, height: 0.30),
            overlayHint: OverlayHint(
                id: "episode-arrow",
                kind: .arrow,
                targetRegion: NormalizedRect(x: 0.72, y: 0.10, width: 0.20, height: 0.30),
                direction: .left
            )
        )

        let rerendered = CameraOverlayUXPresentation.make(
            liveHint: changedHint,
            context: context,
            locale: Locale(identifier: "en")
        )
        let newEpisode = CameraOverlayUXPresentation.make(
            liveHint: changedHint,
            context: CameraOverlayUXContext(episodeState: secondState, hasSpatialEvidence: true),
            locale: Locale(identifier: "en")
        )

        let expectedPoint = SemanticActionType.shiftFrameLeft.subjectDisplacementDirection!
            .subjectTargetPoint(from: subject, sourceSpace: .subjectTarget)!
        XCTAssertEqual(firstState.baseline?.advice.targetPoint?.x, expectedPoint.x)
        XCTAssertEqual(firstState.baseline?.advice.targetPoint?.y, expectedPoint.y)
        XCTAssertEqual(rerendered.markerEventID, firstToken.rawValue.uuidString)
        XCTAssertEqual(rerendered.targetRegion, target)
        XCTAssertEqual(rerendered.overlayHint?.targetRegion, target)
        XCTAssertNotEqual(newEpisode.markerEventID, rerendered.markerEventID)
    }

    private func makeLiveHint(
        id: String = "hint-1",
        frameId: String = "frame-1",
        actionId: String? = "action-1",
        text: String = "Сигнал кадра.",
        confidence: Double = 0.86,
        actionType: ActionTypeV1? = .moveFrameLeft,
        targetRegion: NormalizedRect? = NormalizedRect(x: 0.62, y: 0.2, width: 0.24, height: 0.44),
        subjectIdentity: SubjectTrackIdentity? = nil,
        observedSourceRegion: NormalizedRect? = nil,
        overlayHint: OverlayHint? = nil,
        semanticActionType: SemanticActionType? = nil,
        technicalIssueType: TechnicalQualityIssueType? = nil,
        technicalActionType: TechnicalQualityActionType? = nil,
        linkedIssueIDs: [String] = ["issue-1"],
        includeLinkedEvidence: Bool = true,
        linkedEvidence: CameraLinkedEvidenceProjection? = nil,
        expandedVerdict: LiveExpandedVerdictPresentation? = LiveExpandedVerdictPresentation(
            shortVerdict: "Главный объект теряется у края.",
            supportingText: "Слева осталось мало свободного пространства.",
            actionText: "После смещения объект будет читаться спокойнее.",
            fallbackUsed: false
        )
    ) -> LiveHintPresentation {
        let resolvedLinkedEvidence: CameraLinkedEvidenceProjection?
        if let linkedEvidence {
            resolvedLinkedEvidence = linkedEvidence
        } else if includeLinkedEvidence,
                  linkedIssueIDs == ["issue-1"],
                  let actionType {
            resolvedLinkedEvidence = CameraLinkedEvidenceProjection(
                frameID: frameId,
                actionID: "action-1",
                actionType: actionType,
                semanticActionType: semanticActionType ?? actionType.semanticActionType,
                issueID: "issue-1",
                issueType: .subjectTooCloseToEdge,
                evidence: [EvidenceRef(source: .snapshot, key: "subject.edge", value: "observed")]
            )
        } else {
            resolvedLinkedEvidence = nil
        }
        return LiveHintPresentation(
            id: id,
            frameId: frameId,
            text: text,
            confidence: confidence,
            actionType: actionType,
            actionId: actionId,
            linkedIssueIds: linkedIssueIDs,
            summaryId: "summary-1",
            traceRootIds: ["trace-1"],
            targetRegion: targetRegion,
            subjectIdentity: subjectIdentity,
            observedSourceRegion: observedSourceRegion,
            overlayHint: overlayHint,
            isFallback: false,
            expandedVerdict: expandedVerdict,
            semanticActionType: semanticActionType,
            technicalIssueType: technicalIssueType,
            technicalActionType: technicalActionType,
            linkedEvidence: resolvedLinkedEvidence
        )
    }

    private func makeEpisodeState(
        token: CoachingEpisodeToken,
        subjectRegion: NormalizedRect,
        phase: CoachingEpisodePhase = .awaitingMovement,
        movementFrames: Int = 0,
        stableAfterFrames: Int = 0
    ) -> CoachingEpisodeState {
        let frameID = "episode-frame"
        let subjectIdentity = SubjectTrackIdentity(
            trackID: "episode-subject",
            firstSeenFrameID: frameID,
            generation: token.generation
        )
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let binding = UserMovementSubjectBinding(
            identity: subjectIdentity,
            frameID: frameID,
            region: subjectRegion,
            source: .vision,
            coordinateSpace: .subjectTarget,
            measuredAt: capturedAt,
            confidence: 0.92
        )!
        let evidence = UserMovementEvidence(
            capturedAt: capturedAt,
            evaluatedAt: capturedAt,
            lensGeneration: token.generation,
            subjectTrackID: subjectIdentity.trackID,
            subjectBinding: binding,
            orientation: .portrait,
            isCalibrated: true,
            calibrationVersion: "overlay-test",
            featureMeasuredAt: [.subjectDisplacement: capturedAt],
            featureConfidence: [.subjectDisplacement: 0.92],
            sourceAvailability: [.subjectDisplacement: true]
        )
        let baseline = CoachingEpisodeBaseline(
            advice: StabilizedAdvice(
                decision: .correct,
                actionID: SemanticActionType.shiftFrameLeft.rawValue,
                frameID: frameID,
                targetX: 1.0,
                targetY: subjectRegion.y + subjectRegion.height / 2
            ),
            actionID: SemanticActionType.shiftFrameLeft.rawValue,
            frame: UserMovementFrame(
                frameID: frameID,
                subjectRegion: subjectRegion,
                meanLuma: 0.5,
                motionIsStill: true,
                metrics: UserMovementMetrics(),
                evidence: evidence
            ),
            lifecycle: .initial(generation: token.generation, orientation: .portrait, lensID: "wide"),
            subjectIdentity: subjectIdentity,
            frameID: frameID,
            capturedAt: capturedAt,
            orientation: .portrait,
            lensID: "wide",
            captureGeneration: token.generation,
            subjectRegion: subjectRegion,
            geometryContext: nil,
            exposureState: nil
        )
        return CoachingEpisodeState(
            phase: phase,
            token: token,
            baseline: baseline,
            movementFrames: movementFrames,
            stableAfterFrames: stableAfterFrames,
            lastFrameID: frameID,
            cancellationReason: nil
        )
    }

    private func makeVerificationResult(
        token: CoachingEpisodeToken,
        decision: ActionVerificationDecision
    ) -> ActionVerificationResult {
        ActionVerificationResult(
            token: token,
            actionID: SemanticActionType.shiftFrameLeft.rawValue,
            beforeFrameID: "episode-frame",
            afterFrameID: "episode-after",
            decision: decision,
            deltas: [],
            safetyRegressions: []
        )
    }

    private func containsCyrillic(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x0400...0x04FF).contains(scalar.value)
        }
    }

    private func overlaps(_ lhs: NormalizedRect?, _ rhs: NormalizedRect) -> Bool {
        guard let lhs else { return false }
        return lhs.x < rhs.x + rhs.width
            && rhs.x < lhs.x + lhs.width
            && lhs.y < rhs.y + rhs.height
            && rhs.y < lhs.y + lhs.height
    }

}
