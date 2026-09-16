//
//  CameraCoachLocalizationAddresseeTests.swift
//  shafinMultitoolTests
//
//  C07: RU/EN copy for one accepted command. These checks are deliberately
//  text/contract checks on the shipped catalog and the pure planner/resolver
//  owners. They do not weaken the pipeline's admission gates; they prove the
//  copy cannot act as a second, softer admission path.
//

import CoreGraphics
import XCTest
@testable import shafinMultitool

final class CameraCoachLocalizationAddresseeTests: XCTestCase {

    private enum Addressee: String {
        case proposalToPerson
        case operatorPhone
        case operatorCamera
        case operatorObject
        case neutralStatus
    }

    private static let cameraCatalogPrefixes = [
        "set.camera.",
        "set.trace.action.",
        "set.a11y.",
        "set.action.",
    ]

    /// Curated addressee contract for the corrections that physically differ.
    /// Both languages must resolve to the same addressee; neutral status copy
    /// is not forced into an imperative bucket.
    private static let expectedAddressee: [String: Addressee] = [
        "set.trace.action.shift_left": .operatorCamera,
        "set.trace.action.shift_right": .operatorCamera,
        "set.trace.action.shift_up": .operatorPhone,
        "set.trace.action.shift_down": .operatorPhone,
        "set.trace.action.raise_camera": .operatorPhone,
        "set.trace.action.lower_camera": .operatorPhone,
        "set.trace.action.change_angle": .operatorPhone,
        "set.trace.action.move_subject_left": .proposalToPerson,
        "set.trace.action.move_subject_right": .proposalToPerson,
        "set.trace.action.move_subject_away": .proposalToPerson,
        "set.trace.action.rotate_subject": .proposalToPerson,
        "set.trace.action.move_object_left": .operatorObject,
        "set.trace.action.move_object_right": .operatorObject,
        "set.trace.action.move_object_forward": .operatorObject,
        "set.trace.action.move_object_back": .operatorObject,
        "set.trace.action.reposition_prop": .operatorObject,
        "set.trace.action.remove_distracting_object": .operatorObject,
        "set.camera.corrective.move_up": .operatorPhone,
        "set.camera.corrective.move_down": .operatorPhone,
        "set.camera.corrective.move_left": .operatorCamera,
        "set.camera.corrective.move_right": .operatorCamera,
        "set.camera.corrective.change_angle": .operatorPhone,
        "set.camera.corrective.improve_light": .operatorCamera,
    ]

    // MARK: - Recounted audit surface: no technical placeholders in user copy

    func testCameraCoachVisibleCopyHasNoTechnicalPlaceholders() throws {
        let strings = try catalogStrings()
        let keys = strings.keys.filter { key in
            Self.cameraCatalogPrefixes.contains { key.hasPrefix($0) }
        }
        XCTAssertGreaterThan(keys.count, 50, "camera coach copy surface unexpectedly small")

        let forbidden = [
            "todo", "fixme", "%s", "%d", "nil", "null",
            "changecameraangle", "subject_too_close_to_edge",
            "shift_frame_", "move_object_", "keep_current_setup",
            "semanticactiontype", "actiontypev1", "traceid", "crit_",
            "confidence", "pipeline"
        ]
        for key in keys {
            let localizations = try XCTUnwrap(strings[key]?["localizations"] as? [String: Any], key)
            for (lang, unit) in localizations {
                let value = ((unit as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String ?? ""
                let lowered = value.lowercased()
                for fragment in forbidden {
                    XCTAssertFalse(
                        lowered.contains(fragment),
                        "\(key) [\(lang)] leaks a technical placeholder or id: \(value)"
                    )
                }
            }
        }
    }

    // MARK: - RU and EN never disagree on who is addressed

    func testCameraCoachRUAndENAgreeOnAddressee() throws {
        let strings = try catalogStrings()
        for (key, expected) in Self.expectedAddressee.sorted(by: { $0.key < $1.key }) {
            let ru = try localizedValue(key, "ru", in: strings)
            let en = try localizedValue(key, "en", in: strings)
            XCTAssertEqual(classify(ru), expected, "\(key) RU: \(ru)")
            XCTAssertEqual(classify(en), expected, "\(key) EN: \(en)")
            XCTAssertEqual(
                classify(ru), classify(en),
                "\(key): RU and EN disagree on the addressee\n  RU: \(ru)\n  EN: \(en)"
            )
        }
    }

    /// Subject-facing actions are proposals to the operator, never a command
    /// aimed at a person taking part in the scene.
    func testSubjectFacingCopyIsAProposalInBothLanguages() throws {
        let strings = try catalogStrings()
        let keys = [
            "set.trace.action.move_subject_left",
            "set.trace.action.move_subject_right",
            "set.trace.action.move_subject_away",
            "set.trace.action.rotate_subject",
        ]
        for key in keys {
            let ru = try localizedValue(key, "ru", in: strings).lowercased()
            let en = try localizedValue(key, "en", in: strings).lowercased()
            XCTAssertTrue(ru.contains("можно предложить"), "\(key) RU must stay a proposal: \(ru)")
            XCTAssertTrue(en.contains("you could ask"), "\(key) EN must stay a proposal: \(en)")
            XCTAssertEqual(classify(ru), .proposalToPerson, key)
            XCTAssertEqual(classify(en), .proposalToPerson, key)
        }
    }

    // MARK: - Addressee is not lost between neighbouring movements

    func testVerticalCopyDistinguishesAimFromPhoneHeight() throws {
        let strings = try catalogStrings()
        for key in ["set.trace.action.shift_up", "set.trace.action.shift_down", "set.camera.corrective.move_up", "set.camera.corrective.move_down"] {
            let ru = try localizedValue(key, "ru", in: strings).lowercased()
            let en = try localizedValue(key, "en", in: strings).lowercased()
            XCTAssertTrue(ru.contains("телефон"), "\(key) RU must name the phone constraint: \(ru)")
            XCTAssertTrue(en.contains("phone"), "\(key) EN must name the phone constraint: \(en)")
        }
        // Physically raising/lowering the phone is a different, direct action.
        for key in ["set.trace.action.raise_camera", "set.trace.action.lower_camera"] {
            let ru = try localizedValue(key, "ru", in: strings).lowercased()
            let en = try localizedValue(key, "en", in: strings).lowercased()
            XCTAssertTrue(ru.contains("сам телефон"), "\(key) RU must say the phone itself moves: \(ru)")
            XCTAssertTrue(en.contains("phone itself"), "\(key) EN must say the phone itself moves: \(en)")
        }
        XCTAssertNotEqual(
            try localizedValue("set.trace.action.shift_up", "ru", in: strings),
            try localizedValue("set.trace.action.raise_camera", "ru", in: strings)
        )
    }

    func testDepthCopyUsesLensReferenceNotForwardVector() throws {
        let strings = try catalogStrings()
        let forwardRU = try localizedValue("set.trace.action.move_object_forward", "ru", in: strings).lowercased()
        let forwardEN = try localizedValue("set.trace.action.move_object_forward", "en", in: strings).lowercased()
        XCTAssertTrue(forwardRU.contains("объектив"), forwardRU)
        XCTAssertFalse(forwardRU.contains("вперёд") || forwardRU.contains("вперед"), forwardRU)
        XCTAssertTrue(forwardEN.contains("lens"), forwardEN)
        XCTAssertFalse(forwardEN.contains("forward"), forwardEN)

        let backRU = try localizedValue("set.trace.action.move_object_back", "ru", in: strings).lowercased()
        let backEN = try localizedValue("set.trace.action.move_object_back", "en", in: strings).lowercased()
        XCTAssertTrue(backRU.contains("объектив"), backRU)
        XCTAssertFalse(backRU.contains("назад"), backRU)
        XCTAssertTrue(backEN.contains("lens"), backEN)
        XCTAssertFalse(backEN.contains("back"), backEN)
    }

    func testLightAndBackgroundCopyInventsNoWindowOrDevice() throws {
        let strings = try catalogStrings()
        for key in ["set.trace.action.add_front_fill", "set.trace.action.add_background_light",
                    "set.camera.corrective.improve_light", "set.camera.technical.reduce_noise"] {
            let ru = try localizedValue(key, "ru", in: strings).lowercased()
            let en = try localizedValue(key, "en", in: strings).lowercased()
            XCTAssertFalse(ru.contains("окн") || ru.contains("настольн"), "\(key) RU invents a reference: \(ru)")
            XCTAssertFalse(en.contains("window") || en.contains("desk"), "\(key) EN invents a reference: \(en)")
            XCTAssertTrue(ru.contains("доступн"), "\(key) RU must defer to the available resource: \(ru)")
            XCTAssertTrue(en.contains("available"), "\(key) EN must defer to the available resource: \(en)")
        }
    }

    // MARK: - The documentary/resource prohibition is a gate, not politeness

    /// In live mode a backlit subject may only produce the operator-addressed
    /// proposal. Resource-requiring light manipulation is the pause-only
    /// branch, so no polite copy can admit it during live capture.
    func testLiveBacklightNeverEmitsACommandeeredLightAction() throws {
        let planner = SemanticTipPlanner()
        let critique = makeBacklightCritique(mode: .live)
        let plan = makePlan(
            mode: .live,
            frameId: critique.frameId,
            actionType: .improveFrontLight,
            issueId: "issue-backlight"
        )
        let output = planner.plan(
            input: SemanticTipPlannerInput(
                frameId: critique.frameId,
                mode: .live,
                critique: critique,
                recommendationPlan: plan,
                semantics: makeSemantics(frameId: critique.frameId, mode: .live)
            )
        )

        let tipTypes = [output.livePrimaryTip].compactMap { $0?.tipType }
            + output.pauseExpandedTips.map(\.tipType)
            + output.allRankedCandidates.map(\.tipType)
        XCTAssertFalse(tipTypes.contains(.addFrontFillOnSubject), "live admitted a resource light action")
        XCTAssertFalse(tipTypes.contains(.addBackgroundLightForSeparation), "live admitted a resource light action")
        XCTAssertFalse(tipTypes.contains(.removeBrightSpotBehindSubject), "ungrounded light removal reached live output")
    }

    /// Resource-requiring scene manipulation is a pause-mode branch in the
    /// catalog. A gate (mode/resource/evidence) removes it before copy exists,
    /// so no polite wording can lift the documentary prohibition.
    func testResourceSceneManipulationIsPauseGated() throws {
        let pauseGated: [SemanticTipType] = [
            .addFrontFillOnSubject,
            .addBackgroundLightForSeparation,
            .rebalancePropLayout,
            .moveSubjectLeftForBalance,
            .moveSubjectRightForBalance,
            .showMoreLowerFrame,
        ]
        for tipType in pauseGated {
            let definition = try XCTUnwrap(SemanticTipCatalog.definition(for: tipType), "\(tipType)")
            XCTAssertFalse(
                definition.supportedModes.contains(.live),
                "\(tipType) must be gated out of live capture, not softened by copy"
            )
        }
    }

    // MARK: - Comparable / unknown status is explicit

    func testVerificationClarityIsComparableOrUnknownOnly() {
        func presentation(_ state: CameraOverlayUXPresentation.State) -> CameraOverlayUXPresentation {
            CameraOverlayUXPresentation(
                state: state,
                baseState: .stableTip,
                observation: "status",
                actionInstruction: nil,
                explanation: nil,
                supportingObservation: nil,
                showsWhy: false,
                isFallback: state == .abstention,
                liveHintID: nil,
                episodeToken: nil,
                targetRegion: nil,
                overlayHint: nil,
                eventID: nil,
                effectivePerformanceMode: .nominal,
                analysisStatus: .healthy
            )
        }

        XCTAssertEqual(presentation(.verificationImproved).verificationClarity, .comparable)
        XCTAssertEqual(presentation(.verificationNotImproved).verificationClarity, .comparable)
        XCTAssertEqual(presentation(.abstention).verificationClarity, .unknown)
        XCTAssertNil(presentation(.liveSeeking).verificationClarity)

        for locale in [Locale(identifier: "ru"), Locale(identifier: "en")] {
            XCTAssertFalse(CameraOverlayUXPresentation.VerificationClarity.comparable.label(locale: locale).isEmpty)
            XCTAssertFalse(CameraOverlayUXPresentation.VerificationClarity.unknown.label(locale: locale).isEmpty)
            XCTAssertNotEqual(
                CameraOverlayUXPresentation.VerificationClarity.comparable.label(locale: locale),
                CameraOverlayUXPresentation.VerificationClarity.unknown.label(locale: locale)
            )
        }
    }

    // MARK: - Cycle controls never become motor actions

    func testCycleControlsAreNotMotorActionsAndAreLocalized() {
        let motorIDs = Set(SemanticActionType.allCases.map(\.rawValue))
            .union(ActionTypeV1.allCases.map(\.rawValue))
        for control in CameraCoachCycleControl.allCases {
            XCTAssertFalse(control.isMotorAction, control.rawValue)
            XCTAssertFalse(motorIDs.contains(control.rawValue), "\(control.rawValue) collides with a motor action")
            XCTAssertFalse(control.copyKey.rawValue.isEmpty)
            for locale in [Locale(identifier: "ru"), Locale(identifier: "en")] {
                XCTAssertFalse(control.label(locale: locale).isEmpty, "\(control.rawValue) \(locale)")
            }
        }
    }

    // MARK: - Voice never joins the recorded track by default

    func testCameraCoachVoiceUsesSystemAnnouncementNotSynthesizedAudio() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shafinMultitool/Multitool2Module/UI/Overlay")
        let files = [
            root.appendingPathComponent("SETCameraCoachProductionView.swift"),
            root.appendingPathComponent("CameraOverlayUXPresentation.swift"),
        ]
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(source.contains("AVSpeechSynthesizer"), "\(file.lastPathComponent) synthesizes audio")
            XCTAssertFalse(source.contains("AVAudioPlayer"), "\(file.lastPathComponent) plays audio")
            XCTAssertFalse(source.contains(".speak("), "\(file.lastPathComponent) speaks into the session")
        }
        let coachSource = try String(
            contentsOf: root.appendingPathComponent("SETCameraCoachProductionView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(coachSource.contains("UIAccessibility.post(notification: .announcement"),
                      "repeat must use the system VoiceOver channel")
    }

    // MARK: - Unobstructed shutter

    func testCommandRailPlacementLeavesReservedShutterAreaUncovered() {
        let canvases: [(CGSize, String)] = [
            (CGSize(width: 390, height: 844), "portrait"),
            (CGSize(width: 844, height: 390), "landscape"),
            (CGSize(width: 768, height: 1024), "iPad portrait"),
        ]
        for (canvas, label) in canvases {
            let viewport = CGRect(origin: .zero, size: canvas)
            let shutter = CGRect(
                x: (canvas.width - 88) / 2,
                y: canvas.height - 96,
                width: 88,
                height: 88
            )
            let railHeight = SETCameraCoachMetric.liveRailHeight(
                canvasSize: canvas,
                isAccessibilityType: true,
                isExpanded: false
            )
            guard let placement = CameraOcclusionSolver.resolve(
                viewport: viewport,
                safeRect: viewport.insetBy(dx: 8, dy: 8),
                subjectRect: CGRect(x: canvas.width * 0.3, y: canvas.height * 0.18,
                                    width: canvas.width * 0.25, height: canvas.height * 0.3),
                targetRect: CGRect(x: canvas.width * 0.62, y: canvas.height * 0.2,
                                   width: canvas.width * 0.2, height: canvas.height * 0.28),
                contentSize: CGSize(width: 420, height: railHeight),
                preferredAnchor: .bottomLeading,
                reservedRects: [shutter]
            ) else {
                XCTFail("\(label): no command rail placement")
                continue
            }
            XCTAssertFalse(
                placement.frame.intersects(shutter),
                "\(label): command rail covers the reserved shutter area"
            )
        }
    }

    // MARK: - One accepted action drives text, marker and VoiceOver

    func testTextMarkerAndVoiceOverShareTheAcceptedAction() {
        let locale = Locale(identifier: "en")
        let subject = NormalizedRect(x: 0.22, y: 0.28, width: 0.22, height: 0.40)
        let hint = LiveHintPresentation(
            id: "one-source-hint",
            frameId: "one-source-frame",
            // Deliberately different free-form core text: the projection must
            // not use it as a second meaning source.
            text: "Русская команда из ядра",
            confidence: 0.86,
            actionType: .moveFrameLeft,
            actionId: "one-source-action",
            linkedIssueIds: [],
            summaryId: nil,
            traceRootIds: [],
            targetRegion: NormalizedRect(x: 0.62, y: 0.2, width: 0.24, height: 0.44),
            subjectIdentity: SubjectTrackIdentity(
                trackID: "one-source-subject",
                firstSeenFrameID: "one-source-frame",
                generation: 7
            ),
            observedSourceRegion: NormalizedRect(x: 0.20, y: 0.26, width: 0.22, height: 0.34),
            overlayHint: OverlayHint(
                id: "one-source-arrow",
                kind: .arrow,
                targetRegion: NormalizedRect(x: 0.62, y: 0.2, width: 0.24, height: 0.44),
                direction: .left
            ),
            isFallback: false,
            expandedVerdict: LiveExpandedVerdictPresentation(
                shortVerdict: "Главный объект у края.",
                supportingText: nil,
                actionText: "Второй источник смысла.",
                fallbackUsed: false
            ),
            semanticActionType: .shiftFrameLeft
        )

        let presentation = CameraOverlayUXPresentation.make(
            liveHint: hint,
            context: CameraOverlayUXContext(hasSpatialEvidence: true),
            locale: locale
        )
        XCTAssertEqual(presentation.state, .stableTip)
        XCTAssertEqual(
            presentation.actionInstruction,
            SETCameraCopy.actionKey(for: .shiftFrameLeft).localizedString(locale: locale)
        )
        XCTAssertFalse(presentation.actionInstruction?.contains("Второй источник") ?? false)
        XCTAssertTrue(presentation.accessibilityLabel.contains(presentation.actionInstruction ?? ""))
        XCTAssertTrue(presentation.accessibilityLabel.contains(presentation.observation))
        // The marker consumes the accepted hint direction, not a fresh string.
        XCTAssertEqual(presentation.overlayHint?.direction, .left)
        XCTAssertEqual(presentation.targetRegion, hint.overlayHint?.targetRegion)
        // shiftFrameLeft moves the camera left; the same action's subject
        // displacement is the inverted destination used by episode markers.
        XCTAssertEqual(SemanticActionType.shiftFrameLeft.subjectDisplacementDirection, .right)
        XCTAssertFalse(subject.isDegenerate)
    }

    // MARK: - The pipeline itself authors no second wording

    /// C07 seam: the pipeline publishes the catalog instruction of the accepted
    /// action, not a pipeline-authored sentence. This compares strings (not
    /// "both non-empty") for every closed action family in both languages,
    /// mirroring the presentation's resolution order.
    func testPipelineInstructionResolvesToTheShippedCatalogForEveryActionType() {
        let technicalIssueTypes: [TechnicalQualityIssueType] = [
            .motionBlur, .defocus, .overexposure, .underexposure, .noise, .occlusion, .lensSmudge,
        ]
        for locale in [Locale(identifier: "ru"), Locale(identifier: "en")] {
            for actionType in ActionTypeV1.allCases {
                let expected = SETCameraCopy.actionKey(for: actionType).localizedString(locale: locale)
                XCTAssertEqual(
                    CameraAcceptedActionCopy.instruction(for: actionType, locale: locale),
                    expected,
                    "\(actionType.rawValue) [\(locale.identifier)]"
                )
                XCTAssertFalse(expected.isEmpty, "\(actionType.rawValue) [\(locale.identifier)]")
            }
            for semanticActionType in SemanticActionType.allCases {
                let expected = SETCameraCopy.actionKey(for: semanticActionType).localizedString(locale: locale)
                XCTAssertEqual(
                    CameraAcceptedActionCopy.instruction(for: semanticActionType, locale: locale),
                    expected,
                    "\(semanticActionType.rawValue) [\(locale.identifier)]"
                )
                XCTAssertFalse(expected.isEmpty, "\(semanticActionType.rawValue) [\(locale.identifier)]")
            }
            for issueType in technicalIssueTypes {
                let expected = SETCameraCopy.technicalActionKey(for: issueType).localizedString(locale: locale)
                XCTAssertEqual(
                    CameraAcceptedActionCopy.instruction(for: issueType, locale: locale),
                    expected,
                    "\(issueType.rawValue) [\(locale.identifier)]"
                )
                XCTAssertFalse(expected.isEmpty, "\(issueType.rawValue) [\(locale.identifier)]")
            }
            // Resolution order is the same one CameraOverlayUXPresentation uses:
            // semantic action, then technical issue, then legacy action type.
            for semanticActionType in SemanticActionType.allCases {
                XCTAssertEqual(
                    CameraAcceptedActionCopy.instruction(
                        actionType: .moveFrameLeft,
                        semanticActionType: semanticActionType,
                        technicalIssueType: .defocus,
                        locale: locale
                    ),
                    SETCameraCopy.actionKey(for: semanticActionType).localizedString(locale: locale)
                )
            }
        }
    }

    /// Regression guard: a new hardcoded instruction literal in the pipeline
    /// must fail this test. Only the non-user-facing snapshot invariant message
    /// is allowed to stay a literal.
    func testPipelineSourceAuthorsNoCameraInstructionLiteral() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let instructionFields = ["liveText:", "pauseActionText:", "actionText:", "expectedOutcome:", "text:"]
        let allowedNonInstructionLiterals: Set<String> = [
            "text: \"Snapshot payload does not satisfy expected contract invariants.\",",
        ]
        for (index, rawLine) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard let field = instructionFields.first(where: { line.hasPrefix($0) }) else { continue }
            let value = String(line.dropFirst(field.count)).trimmingCharacters(in: .whitespaces)
            guard value.hasPrefix("\"") else { continue }
            XCTAssertTrue(
                allowedNonInstructionLiterals.contains(line),
                "AnalysisPipeline.swift:\(index + 1) authors camera instruction text: \(line)"
            )
        }
    }

    // MARK: - Helpers

    private func catalogStrings() throws -> [String: [String: Any]] {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shafinMultitool/Resources/Localizable.xcstrings")
        let data = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        return try XCTUnwrap(data?["strings"] as? [String: [String: Any]])
    }

    private func localizedValue(_ key: String, _ lang: String, in strings: [String: [String: Any]]) throws -> String {
        let entry = try XCTUnwrap(strings[key], key)
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
        let unit = try XCTUnwrap(localizations[lang] as? [String: Any], "\(key) [\(lang)]")
        let stringUnit = try XCTUnwrap(unit["stringUnit"] as? [String: Any], "\(key) [\(lang)]")
        return try XCTUnwrap(stringUnit["value"] as? String, "\(key) [\(lang)]")
    }

    private func classify(_ value: String) -> Addressee {
        let lowered = value.lowercased()
        if lowered.contains("можно предложить") || lowered.contains("you could ask") {
            return .proposalToPerson
        }
        if lowered.contains("телефон") || lowered.contains("phone") {
            return .operatorPhone
        }
        if lowered.contains("камер") || lowered.contains("camera") {
            return .operatorCamera
        }
        if lowered.contains("предмет") || lowered.contains("item") {
            return .operatorObject
        }
        return .neutralStatus
    }

    private func makeBacklightCritique(mode: AnalysisMode) -> CritiqueReport {
        let issue = FrameIssue(
            id: "issue-backlight",
            type: .backlightHidesSubject,
            severity: 0.80,
            confidence: 0.82,
            rationale: "Лицо провалено в контражуре.",
            evidence: [EvidenceRef(source: .snapshot, key: "lighting.backlight", value: "observed", confidence: 0.82)],
            suggestedFixTypes: [.lightingAdjustment]
        )
        return CritiqueReport(
            frameId: "frame-backlight",
            mode: mode,
            verdict: .needsFix,
            verdictConfidence: 0.82,
            strengths: [],
            issues: [issue],
            summary: CritiqueSummary(id: "summary-backlight", shortVerdict: "Кадр требует правки.", whyProblematic: issue.rationale),
            traceRefs: ["trace-backlight-summary", "trace-backlight-issue"],
            fallbackUsed: false
        )
    }

    private func makePlan(mode: AnalysisMode,
                          frameId: String,
                          actionType: ActionTypeV1,
                          issueId: String) -> RecommendationPlan {
        RecommendationPlan(
            frameId: frameId,
            mode: mode,
            inputVerdict: .needsFix,
            primaryAction: RecommendationAction(
                id: "action-backlight",
                actionType: actionType,
                priority: 1,
                targetRegion: NormalizedRect(x: 0.24, y: 0.16, width: 0.30, height: 0.44),
                linkedIssueIds: [issueId],
                expectedOutcome: "Свет спереди",
                guardrail: ActionGuardrail(requiresStillCamera: false, minConfidence: 0.4, suppressWhenMoving: false),
                overlayHint: nil
            ),
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.8
        )
    }

    private func makeSemantics(frameId: String, mode: AnalysisMode) -> SceneSemanticsReport {
        SceneSemanticsReport(
            frameId: frameId,
            mode: mode,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.82,
            primarySubject: .init(
                kind: .person,
                label: "person",
                region: NormalizedRect(x: 0.24, y: 0.16, width: 0.30, height: 0.44),
                confidence: 0.88
            ),
            dominance: .init(hasClearFocus: true, focusCompetitionScore: 0.2, backgroundClutterScore: 0.2),
            readability: .init(subjectReadable: true, lookSpaceAdequate: true, edgePressureScore: 0.1, separationScore: 0.7),
            ambiguities: [],
            assumptions: []
        )
    }
}
