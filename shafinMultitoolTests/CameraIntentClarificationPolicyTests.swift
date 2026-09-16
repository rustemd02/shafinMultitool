//
//  CameraIntentClarificationPolicyTests.swift
//  shafinMultitool
//
//  CC-I05 contract: style cues are detected only when the subject still reads,
//  answers are session-scoped, and confirmed intent suppresses exactly the
//  conflicting corrective families.
//

import XCTest
@testable import shafinMultitool

final class CameraIntentClarificationPolicyTests: XCTestCase {

    private func evidence(
        horizonAngleDegrees: Double = 0,
        horizonConfidence: Double = 0,
        exposureBiasHint: Double = 0,
        backlightIndex: Double = 0,
        shakeLevel: Double = 0,
        subjectReadable: Bool = true,
        hasClearFocus: Bool = true
    ) -> CameraStyleCueEvidence {
        CameraStyleCueEvidence(
            horizonAngleDegrees: horizonAngleDegrees,
            horizonConfidence: horizonConfidence,
            exposureBiasHint: exposureBiasHint,
            backlightIndex: backlightIndex,
            shakeLevel: shakeLevel,
            subjectReadable: subjectReadable,
            hasClearFocus: hasClearFocus
        )
    }

    func testTiltCueRequiresAngleAndConfidence() {
        XCTAssertEqual(
            CameraIntentClarificationPolicy.detectedCues(from: evidence(horizonAngleDegrees: 4, horizonConfidence: 0.9)),
            [.tilt]
        )
        XCTAssertTrue(
            CameraIntentClarificationPolicy.detectedCues(from: evidence(horizonAngleDegrees: 1, horizonConfidence: 0.9)).isEmpty,
            "a one-degree tilt is not a style decision"
        )
        XCTAssertTrue(
            CameraIntentClarificationPolicy.detectedCues(from: evidence(horizonAngleDegrees: 4, horizonConfidence: 0.2)).isEmpty,
            "low-confidence horizon evidence must not prompt"
        )
    }

    func testLowKeySilhouetteAndMotionBlurCues() {
        XCTAssertEqual(
            CameraIntentClarificationPolicy.detectedCues(from: evidence(exposureBiasHint: -1.2)),
            [.lowKey]
        )
        XCTAssertEqual(
            CameraIntentClarificationPolicy.detectedCues(from: evidence(backlightIndex: 0.7)),
            [.silhouette]
        )
        XCTAssertEqual(
            CameraIntentClarificationPolicy.detectedCues(from: evidence(shakeLevel: 0.8, hasClearFocus: false)),
            [.motionBlur]
        )
        XCTAssertTrue(
            CameraIntentClarificationPolicy.detectedCues(from: evidence(shakeLevel: 0.8, hasClearFocus: true)).isEmpty,
            "shake with a clear focus point is not a blur style"
        )
    }

    func testUnreadableSubjectNeverPromptsForStyle() {
        let cues = CameraIntentClarificationPolicy.detectedCues(
            from: evidence(horizonAngleDegrees: 4, horizonConfidence: 0.9, exposureBiasHint: -1.5,
                           backlightIndex: 0.8, shakeLevel: 0.9, subjectReadable: false, hasClearFocus: false)
        )
        XCTAssertTrue(cues.isEmpty, "an unreadable subject is a real defect, not an intentional style")
    }

    func testCueFamiliesMapToTheConflictingCorrections() {
        XCTAssertEqual(CameraIntentClarificationPolicy.conflictingFamilies(for: .tilt), [.horizon])
        XCTAssertEqual(CameraIntentClarificationPolicy.conflictingFamilies(for: .lowKey), [.exposure])
        XCTAssertEqual(CameraIntentClarificationPolicy.conflictingFamilies(for: .silhouette), [.exposure])
        XCTAssertEqual(CameraIntentClarificationPolicy.conflictingFamilies(for: .symmetry), [.composition])
        XCTAssertEqual(CameraIntentClarificationPolicy.conflictingFamilies(for: .negativeSpace), [.composition])
        XCTAssertEqual(
            Set(CameraIntentClarificationPolicy.conflictingFamilies(for: .motionBlur)),
            [.focus, .stability]
        )
    }

    func testConfirmedIntentSuppressesExactlyTheConflictingFamiliesForTheSession() {
        var policy = CameraIntentClarificationPolicy()
        XCTAssertFalse(policy.hasAnswered(.lowKey))

        policy.record(cue: .lowKey, intended: true)
        XCTAssertTrue(policy.hasAnswered(.lowKey))
        XCTAssertTrue(policy.isSuppressed(.exposure))
        XCTAssertFalse(policy.isSuppressed(.composition))
        XCTAssertFalse(policy.isSuppressed(.horizon))

        policy.record(cue: .tilt, intended: false)
        XCTAssertTrue(policy.hasAnswered(.tilt))
        XCTAssertFalse(policy.isSuppressed(.horizon), "a 'no' answer keeps the correction actionable")

        policy.record(cue: .motionBlur, intended: true)
        XCTAssertEqual(policy.suppressedFamilies, [.exposure, .focus, .stability])

        policy.resetSession()
        XCTAssertTrue(policy.suppressedFamilies.isEmpty)
        XCTAssertFalse(policy.hasAnswered(.lowKey))
    }

    @MainActor
    func testPipelinePlumbsSessionAnswersIntoTheGateSuppressionSet() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, visualEvidenceProvider: nil, neuralEvidenceService: nil)
        XCTAssertTrue(pipeline.testingIntentSuppressedFamilies.isEmpty)
        XCTAssertNil(pipeline.testingIntentAnswer(for: .lowKey))

        pipeline.recordIntentClarification(cue: .lowKey, intended: true)
        XCTAssertEqual(pipeline.testingIntentSuppressedFamilies, [.exposure])
        XCTAssertEqual(pipeline.testingIntentAnswer(for: .lowKey), true)

        pipeline.recordIntentClarification(cue: .tilt, intended: false)
        XCTAssertFalse(pipeline.testingIntentSuppressedFamilies.contains(.horizon))

        pipeline.resetIntentClarificationSession()
        XCTAssertTrue(pipeline.testingIntentSuppressedFamilies.isEmpty)
        XCTAssertNil(pipeline.testingIntentAnswer(for: .lowKey))
    }

    func testPromptCarriesLocalizationKeyAndFamilies() {
        let prompt = CameraIntentClarificationPolicy.clarificationPrompt(for: .silhouette)
        XCTAssertEqual(prompt.cue, .silhouette)
        XCTAssertEqual(prompt.promptKey, "camera.coach.intent.silhouette")
        XCTAssertEqual(prompt.conflictingFamilies, [.exposure])
    }
}
