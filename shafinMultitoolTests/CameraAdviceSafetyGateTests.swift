//
//  CameraAdviceSafetyGateTests.swift
//  shafinMultitoolTests
//
//  M2-019 SafetyPolicyOwner: table-driven protected-case tests — each
//  forbidden action family and each fail-closed evidence state produces its
//  deterministic decision; nothing reaches .allow through a broken path.
//

import XCTest
@testable import shafinMultitool

final class CameraAdviceSafetyGateTests: XCTestCase {

    private func input(
        lensGenerationKnown: Bool = true,
        subjectTrackLost: Bool? = false,
        subjectAmbiguous: Bool = false,
        motionStateIsStill: Bool = true,
        exposureContradictionFree: Bool = true,
        refocusAdviceAdmitted: Bool? = true,
        horizonAvailable: Bool? = true,
        calibratedProbability: Double? = 0.8,
        minimumConfidence: Double = 0.5
    ) -> CameraAdviceSafetyInput {
        CameraAdviceSafetyInput(
            lensGenerationKnown: lensGenerationKnown,
            subjectTrackLost: subjectTrackLost,
            subjectAmbiguous: subjectAmbiguous,
            motionStateIsStill: motionStateIsStill,
            exposureContradictionFree: exposureContradictionFree,
            refocusAdviceAdmitted: refocusAdviceAdmitted,
            horizonAvailable: horizonAvailable,
            calibratedProbability: calibratedProbability,
            minimumConfidence: minimumConfidence
        )
    }

    // MARK: - Per-family forbidden rules (table)

    func testHorizonFamilyRequiresAvailableHorizonEvidence() {
        let blocked = CameraAdviceSafetyGate.evaluate(
            actionFamily: .horizon,
            input: input(horizonAvailable: false)
        )
        XCTAssertEqual(blocked, .abstain(reason: .horizonEvidenceUnavailable))

        let missing = CameraAdviceSafetyGate.evaluate(
            actionFamily: .horizon,
            input: input(horizonAvailable: nil)
        )
        XCTAssertEqual(missing, .abstain(reason: .horizonEvidenceUnavailable))

        let allowed = CameraAdviceSafetyGate.evaluate(
            actionFamily: .horizon,
            input: input(horizonAvailable: true)
        )
        XCTAssertEqual(allowed, .allow)
    }

    func testFocusFamilyRequiresAdmittedFocusEvidence() {
        for bad in [false, nil] {
            let blocked = CameraAdviceSafetyGate.evaluate(
                actionFamily: .focus,
                input: input(refocusAdviceAdmitted: bad)
            )
            XCTAssertEqual(blocked, .abstain(reason: .focusEvidenceNotAdmitted))
        }

        let allowed = CameraAdviceSafetyGate.evaluate(
            actionFamily: .focus,
            input: input(refocusAdviceAdmitted: true)
        )
        XCTAssertEqual(allowed, .allow)
    }

    func testExposureCompositionAndKeepHaveNoFamilyForbiddenRules() {
        for family in [CameraAdviceActionFamily.exposure, .composition, .keep] {
            let decision = CameraAdviceSafetyGate.evaluate(
                actionFamily: family,
                input: input()
            )
            XCTAssertEqual(decision, .allow, "\(family) has no family gate")
        }
    }

    // MARK: - Fail-closed evidence states

    func testUnknownLensGenerationAbstainsEverything() {
        for family in CameraAdviceActionFamily.allCases {
            XCTAssertEqual(
                CameraAdviceSafetyGate.evaluate(actionFamily: family, input: input(lensGenerationKnown: false)),
                .abstain(reason: .lensGenerationUnknown),
                "\(family) must abstain without a known lens generation"
            )
        }
    }

    func testLostSubjectIdentityAbstainsCorrections() {
        for family in [CameraAdviceActionFamily.exposure, .composition, .focus] {
            XCTAssertEqual(
                CameraAdviceSafetyGate.evaluate(actionFamily: family, input: input(subjectTrackLost: true)),
                .abstain(reason: .subjectIdentityLost)
            )
        }
    }

    func testFrameGlobalFamiliesDoNotRequireSubjectIdentity() {
        XCTAssertEqual(
            CameraAdviceSafetyGate.evaluate(
                actionFamily: .horizon,
                input: input(subjectTrackLost: nil, horizonAvailable: true)
            ),
            .allow
        )
        XCTAssertEqual(
            CameraAdviceSafetyGate.evaluate(
                actionFamily: .stability,
                input: input(subjectTrackLost: nil, motionStateIsStill: false)
            ),
            .allow
        )
    }

    func testUnresolvedSubjectRequiresSelection() {
        XCTAssertEqual(
            CameraAdviceSafetyGate.evaluate(actionFamily: .exposure, input: input(subjectTrackLost: nil)),
            .selectSubject(reason: .subjectAmbiguous)
        )
        XCTAssertEqual(
            CameraAdviceSafetyGate.evaluate(actionFamily: .exposure, input: input(subjectAmbiguous: true)),
            .selectSubject(reason: .subjectAmbiguous)
        )
    }

    func testMotionCannotProduceCorrection() {
        for moving in [false] {
            let decision = CameraAdviceSafetyGate.evaluate(
                actionFamily: .exposure,
                input: input(motionStateIsStill: moving)
            )
            XCTAssertEqual(decision, .wait(reason: .motionNotStill))
        }
    }

    func testExposureContradictionWaits() {
        let decision = CameraAdviceSafetyGate.evaluate(
            actionFamily: .exposure,
            input: input(exposureContradictionFree: false)
        )
        XCTAssertEqual(decision, .wait(reason: .exposureContradiction))
    }

    // MARK: - Calibration gate

    func testMissingCalibratedProbabilityAbstains() {
        XCTAssertEqual(
            CameraAdviceSafetyGate.evaluate(actionFamily: .exposure, input: input(calibratedProbability: nil)),
            .abstain(reason: .calibratedProbabilityMissing)
        )
    }

    func testLowCalibratedProbabilityWaits() {
        XCTAssertEqual(
            CameraAdviceSafetyGate.evaluate(
                actionFamily: .exposure,
                input: input(calibratedProbability: 0.49, minimumConfidence: 0.5)
            ),
            .wait(reason: .calibratedProbabilityLow)
        )
    }

    func testProbabilityAtThresholdAllows() {
        XCTAssertEqual(
            CameraAdviceSafetyGate.evaluate(
                actionFamily: .exposure,
                input: input(calibratedProbability: 0.5, minimumConfidence: 0.5)
            ),
            .allow
        )
    }

    // MARK: - Order of gates: identity beats family gates

    func testIdentityLossOverridesSubjectDependentFamilyGates() {
        // Subject-dependent corrections still abstain even when their other
        // evidence is available.
        XCTAssertEqual(
            CameraAdviceSafetyGate.evaluate(
                actionFamily: .exposure,
                input: input(subjectTrackLost: true)
            ),
            .abstain(reason: .subjectIdentityLost)
        )
    }
}
