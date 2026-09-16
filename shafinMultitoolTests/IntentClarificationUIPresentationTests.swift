//
//  IntentClarificationUIPresentationTests.swift
//  shafinMultitool
//
//  CC-I05 UI layer: localized prompt projection, per-frame cue publication,
//  and the user's answer flowing into the session suppression set.
//

import XCTest
@testable import shafinMultitool

@MainActor
final class IntentClarificationUIPresentationTests: XCTestCase {

    private func snapshot(horizonAngle: Double = 0,
                          horizonConfidence: Double = 0,
                          exposureBias: Double = 0,
                          backlight: Double = 0,
                          shake: Double = 0,
                          capturedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> FrameFeatureSnapshot {
        FrameFeatureSnapshot(
            frameId: "intent-frame",
            mode: .live,
            capturedAt: capturedAt,
            sources: .init(
                vision: .init(available: true, freshnessMs: 80, confidence: 0.88),
                horizon: .init(available: horizonConfidence > 0, confidence: horizonConfidence),
                lighting: .init(available: true),
                detr: .init(available: false),
                aesthetic: .init(available: false)
            ),
            composition: .init(
                horizontalOffset: 0,
                verticalOffset: 0,
                subjectAreaRatio: 0.16,
                saliencyLeftRightBalance: 0,
                saliencyTopBottomBalance: 0
            ),
            subjectSignals: .init(
                faceDetected: false,
                personDetected: true,
                personCount: 1,
                primaryCandidateRegion: .init(x: 0.22, y: 0.16, width: 0.34, height: 0.48),
                primaryCandidateConfidence: 0.86
            ),
            horizon: .init(angleDegrees: horizonAngle, confidence: horizonConfidence),
            lighting: .init(exposureBiasHint: exposureBias, backlightIndex: backlight, keyToFillRatio: nil),
            motion: .init(state: .still, shakeLevel: shake),
            aesthetics: .init(),
            objects: .init(totalCount: 0, topKLabels: []),
            technicalFlags: []
        )
    }

    private func semantics(subjectReadable: Bool = true,
                           hasClearFocus: Bool = true) -> SceneSemanticsReport {
        SceneSemanticsReport(
            frameId: "intent-frame",
            mode: .live,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.88,
            primarySubject: .init(kind: .person, label: "person",
                                  region: .init(x: 0.22, y: 0.16, width: 0.34, height: 0.48),
                                  confidence: 0.86),
            dominance: .init(hasClearFocus: hasClearFocus, focusCompetitionScore: 0.12, backgroundClutterScore: 0.10),
            readability: .init(subjectReadable: subjectReadable, lookSpaceAdequate: true,
                                edgePressureScore: 0.10, separationScore: 0.82),
            ambiguities: [],
            assumptions: []
        )
    }

    func testPromptProjectionUsesLocalizedCopyAndStableAccessibilityIDs() {
        let ru = IntentClarificationPresentation.make(cue: .tilt, locale: Locale(identifier: "ru"))
        XCTAssertEqual(ru.question, "Оставить наклон?")
        XCTAssertEqual(ru.confirmTitle, "Да, так и задумано")
        XCTAssertEqual(ru.denyTitle, "Нет, исправь")
        XCTAssertEqual(ru.confirmAccessibilityIdentifier, "set.a11y.intent_confirm")
        XCTAssertEqual(ru.denyAccessibilityIdentifier, "set.a11y.intent_deny")

        let en = IntentClarificationPresentation.make(cue: .lowKey, locale: Locale(identifier: "en"))
        XCTAssertEqual(en.question, "Keep the dark, low-key look?")
        XCTAssertFalse(en.question.isEmpty)
    }

    func testEveryCueMapsToItsOwnQuestionKey() {
        var keys: Set<String> = []
        for cue in CameraStyleCue.allCases {
            let key = IntentClarificationPresentation.questionKey(for: cue).rawValue
            XCTAssertFalse(keys.contains(key), "duplicate question key for \(cue)")
            keys.insert(key)
        }
        XCTAssertEqual(keys.count, CameraStyleCue.allCases.count)
    }

    func testLiveFramePublishesTheFirstUnansweredCueAndAnswerSuppressesIt() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, visualEvidenceProvider: nil, neuralEvidenceService: nil)
        XCTAssertNil(pipeline.pendingIntentClarificationCue)

        pipeline.testingUpdateIntentClarification(
            snapshot: snapshot(horizonAngle: 4, horizonConfidence: 0.9),
            semantics: semantics()
        )
        XCTAssertEqual(pipeline.pendingIntentClarificationCue, .tilt)

        pipeline.answerIntentClarification(intended: true)
        XCTAssertNil(pipeline.pendingIntentClarificationCue, "the prompt clears after the answer")
        XCTAssertTrue(pipeline.testingIntentSuppressedFamilies.contains(.horizon))

        // already answered: the same cue is never asked again this session
        pipeline.testingUpdateIntentClarification(
            snapshot: snapshot(horizonAngle: 4, horizonConfidence: 0.9),
            semantics: semantics()
        )
        XCTAssertNil(pipeline.pendingIntentClarificationCue)
    }

    func testDeniedIntentKeepsTheCorrectionActionable() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, visualEvidenceProvider: nil, neuralEvidenceService: nil)
        pipeline.testingUpdateIntentClarification(
            snapshot: snapshot(exposureBias: -1.2),
            semantics: semantics()
        )
        XCTAssertEqual(pipeline.pendingIntentClarificationCue, .lowKey)

        pipeline.answerIntentClarification(intended: false)
        XCTAssertFalse(pipeline.testingIntentSuppressedFamilies.contains(.exposure))
        XCTAssertEqual(pipeline.testingIntentAnswer(for: .lowKey), false)
        XCTAssertNil(pipeline.pendingIntentClarificationCue)
    }

    func testUnreadableSubjectPublishesNoPrompt() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, visualEvidenceProvider: nil, neuralEvidenceService: nil)
        pipeline.testingUpdateIntentClarification(
            snapshot: snapshot(horizonAngle: 5, horizonConfidence: 0.9, exposureBias: -1.4, shake: 0.9),
            semantics: semantics(subjectReadable: false, hasClearFocus: false)
        )
        XCTAssertNil(pipeline.pendingIntentClarificationCue,
                     "an unreadable subject is a real defect, not a style choice")
    }

    func testDeterministicCueOrderingWhenSeveralCuesArePresent() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, visualEvidenceProvider: nil, neuralEvidenceService: nil)
        pipeline.testingUpdateIntentClarification(
            snapshot: snapshot(horizonAngle: 4, horizonConfidence: 0.9, exposureBias: -1.2, backlight: 0.8),
            semantics: semantics()
        )
        // rawValue ordering makes the choice deterministic (lowKey < silhouette < tilt)
        XCTAssertEqual(pipeline.pendingIntentClarificationCue, .lowKey)

        pipeline.answerIntentClarification(intended: false)
        pipeline.testingUpdateIntentClarification(
            snapshot: snapshot(horizonAngle: 4, horizonConfidence: 0.9, exposureBias: -1.2, backlight: 0.8),
            semantics: semantics()
        )
        XCTAssertEqual(pipeline.pendingIntentClarificationCue, .silhouette)
    }
}
