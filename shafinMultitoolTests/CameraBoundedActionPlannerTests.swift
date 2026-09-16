//
//  CameraBoundedActionPlannerTests.swift
//  shafinMultitoolTests
//
//  M2-020 AdvicePlannerOwner: exhaustive state/action table — the planner
//  emits exactly one decision, safety gate wins, bounded selection, no
//  secondary advice.
//

import XCTest
@testable import shafinMultitool

final class CameraBoundedActionPlannerTests: XCTestCase {

    private func candidate(id: String,
                           probability: Double = 0.8,
                           band: Int = 1,
                           target: (Double, Double)? = (0.5, 0.5),
                           targetIdentity: SubjectTrackIdentity? = nil) -> CameraPlannerCandidate {
        CameraPlannerCandidate(
            actionID: id,
            actionFamily: .composition,
            calibratedProbability: probability,
            priorityBand: band,
            targetPoint: target,
            targetIdentity: targetIdentity
        )
    }

    private let targetA = SubjectTrackIdentity(
        trackID: "target-a",
        firstSeenFrameID: "f-a",
        generation: 7
    )

    // MARK: - Safety gate passthrough (fail closed)

    func testSafetyWaitDecisionPassesThroughUnchanged() {
        let decision = CameraBoundedActionPlanner.plan(
            safetyDecision: .wait(reason: .motionNotStill),
            candidates: [candidate(id: "a")],
            goodFrameScore: 0.2,
            frameID: "f1"
        )
        XCTAssertEqual(decision.decision, .wait)
        XCTAssertEqual(decision.blockReason, .motionNotStill)
        XCTAssertNil(decision.actionID, "WAIT carries no action — no secondary live advice")
    }

    func testSafetySelectSubjectPassesThrough() {
        let decision = CameraBoundedActionPlanner.plan(
            safetyDecision: .selectSubject(reason: .subjectAmbiguous),
            candidates: [candidate(id: "a")],
            goodFrameScore: 0.9,
            frameID: "f1"
        )
        XCTAssertEqual(decision.decision, .selectSubject)
        XCTAssertEqual(decision.blockReason, .subjectAmbiguous)
        XCTAssertNil(decision.actionID, "even a good frame score cannot override SELECT_SUBJECT")
    }

    func testSafetyAbstainPassesThrough() {
        let decision = CameraBoundedActionPlanner.plan(
            safetyDecision: .abstain(reason: .lensGenerationUnknown),
            candidates: [candidate(id: "a")],
            goodFrameScore: 0.1,
            frameID: "f1"
        )
        XCTAssertEqual(decision.decision, .abstain)
        XCTAssertEqual(decision.blockReason, .lensGenerationUnknown)
    }

    // MARK: - Bounded selection

    func testHighestProbabilityCandidateWins() {
        let decision = CameraBoundedActionPlanner.plan(
            safetyDecision: .allow,
            candidates: [candidate(id: "weak", probability: 0.55),
                         candidate(id: "strong", probability: 0.9),
                         candidate(id: "mid", probability: 0.7)],
            goodFrameScore: 0.1,
            frameID: "f1"
        )
        XCTAssertEqual(decision.decision, .correct)
        XCTAssertEqual(decision.actionID, "strong")
        XCTAssertEqual(decision.calibratedProbability, 0.9)
        XCTAssertEqual(decision.frameID, "f1")
    }

    func testProbabilityTieBreaksByPriorityBandThenStableId() {
        let tiedA = candidate(id: "b-action", probability: 0.8, band: 2)
        let tiedB = candidate(id: "a-action", probability: 0.8, band: 2)
        let highBand = candidate(id: "z", probability: 0.8, band: 1)

        // Same probability: lower priority band wins.
        let byBand = CameraBoundedActionPlanner.plan(
            safetyDecision: .allow,
            candidates: [tiedA, highBand],
            goodFrameScore: 0.1,
            frameID: "f1"
        )
        XCTAssertEqual(byBand.actionID, "z")

        // Same probability and band: stable id order wins regardless of input order.
        let first = CameraBoundedActionPlanner.plan(
            safetyDecision: .allow, candidates: [tiedA, tiedB], goodFrameScore: 0.1, frameID: "f1"
        )
        let second = CameraBoundedActionPlanner.plan(
            safetyDecision: .allow, candidates: [tiedB, tiedA], goodFrameScore: 0.1, frameID: "f1"
        )
        XCTAssertEqual(first.actionID, "a-action")
        XCTAssertEqual(second.actionID, "a-action")
    }

    func testAllowWithNoCandidatesIsHonestWait() {
        let decision = CameraBoundedActionPlanner.plan(
            safetyDecision: .allow,
            candidates: [],
            goodFrameScore: 0.3,
            frameID: "f1"
        )
        XCTAssertEqual(decision.decision, .wait)
        XCTAssertEqual(decision.blockReason, .calibratedProbabilityMissing)
    }

    // MARK: - KEEP path

    func testGoodFrameScoreEmitsKeepInsteadOfCorrection() {
        let decision = CameraBoundedActionPlanner.plan(
            safetyDecision: .allow,
            candidates: [candidate(id: "a", probability: 0.9)],
            goodFrameScore: 0.85,
            frameID: "f1"
        )
        XCTAssertEqual(decision.decision, .keep)
        XCTAssertNil(decision.actionID)
        XCTAssertEqual(decision.calibratedProbability, 0.85)
    }

    func testGoodFrameBelowThresholdStillCorrects() {
        let decision = CameraBoundedActionPlanner.plan(
            safetyDecision: .allow,
            candidates: [candidate(id: "a", probability: 0.9)],
            goodFrameScore: 0.79,
            frameID: "f1"
        )
        XCTAssertEqual(decision.decision, .correct)
        XCTAssertEqual(decision.actionID, "a")
    }

    // MARK: - Exactly-one semantics with linked evidence

    func testCorrectCarriesLinkedTargetPoint() {
        let decision = CameraBoundedActionPlanner.plan(
            safetyDecision: .allow,
            candidates: [candidate(id: "a", probability: 0.9, target: (1.0, 0.5))],
            goodFrameScore: 0.1,
            frameID: "f1"
        )
        XCTAssertEqual(decision.decision, .correct)
        XCTAssertEqual(decision.targetPoint?.x, 1.0)
        XCTAssertEqual(decision.targetPoint?.y, 0.5)
    }

    func testCorrectPropagatesTargetIdentity() {
        let decision = CameraBoundedActionPlanner.plan(
            safetyDecision: .allow,
            candidates: [candidate(id: "a", probability: 0.9, targetIdentity: targetA)],
            goodFrameScore: 0.1,
            frameID: "f1"
        )
        XCTAssertEqual(decision.targetIdentity, targetA)
    }

    func testNonCorrectDecisionsCarryNoTarget() {
        for decision in [
            CameraBoundedActionPlanner.plan(
                safetyDecision: .wait(reason: .motionNotStill),
                candidates: [candidate(id: "a", target: (1, 1))],
                goodFrameScore: 0.1, frameID: "f1"
            ),
        ] {
            XCTAssertNil(decision.targetPoint, "\(decision.decision) must not carry a target")
            XCTAssertNil(decision.targetIdentity, "\(decision.decision) must not carry a target identity")
        }
    }

    // MARK: - C05 pre-ranking admissibility matrix

    private func admissibility(
        intent: Bool = true,
        manipulation: Bool = true,
        resource: Bool = true,
        destination: Bool = true,
        mode: Bool = true,
        calibratedEvidence: Bool = true,
        verifier: Bool = true,
        targetFresh: Bool = true
    ) -> CameraAdviceAdmissibilityDecision {
        CameraAdviceSafetyGate.evaluateAdmissibility(
            CameraAdviceAdmissibilityInput(
                intentAllowsCorrection: intent,
                manipulationPermitted: manipulation,
                resourceAvailable: resource,
                destinationReachable: destination,
                modeAdmitted: mode,
                calibratedEvidenceAvailable: calibratedEvidence,
                verifierSupported: verifier,
                targetFresh: targetFresh
            )
        )
    }

    /// issue → candidate → reject reason → displayed action. A rejected
    /// prerequisite can never be ranked back into CORRECT, even at 0.99.
    func testRejectedPrerequisiteNeverBecomesCorrectRegardlessOfScore() {
        let matrix: [(name: String,
                      verdict: CameraAdviceAdmissibilityDecision,
                      reason: SafetyBlockReason,
                      decision: CameraCoachDecisionV2)] = [
            ("intent", admissibility(intent: false), .intentionalStylePreserved, .abstain),
            ("manipulation", admissibility(manipulation: false), .manipulationNotPermitted, .abstain),
            ("resource", admissibility(resource: false), .resourceUnavailable, .abstain),
            ("destination", admissibility(destination: false), .destinationUnreachable, .abstain),
            ("mode", admissibility(mode: false), .modeNotAdmitted, .abstain),
            ("calibrated_evidence", admissibility(calibratedEvidence: false), .calibratedProbabilityMissing, .abstain),
            ("verifier", admissibility(verifier: false), .verifierUnsupported, .abstain),
            ("freshness", admissibility(targetFresh: false), .targetStale, .wait),
        ]

        for entry in matrix {
            let planned = CameraBoundedActionPlanner.plan(
                admissibility: entry.verdict,
                safetyDecision: .allow,
                candidates: [candidate(id: "act_simplify_background", probability: 0.99, band: 0)],
                goodFrameScore: 0.99,
                frameID: "f-matrix"
            )
            XCTAssertEqual(planned.decision, entry.decision, entry.name)
            XCTAssertNil(planned.actionID, "\(entry.name): no command may be displayed")
            XCTAssertNil(planned.targetPoint, "\(entry.name): no target may be displayed")
            XCTAssertEqual(planned.blockReason, entry.reason, entry.name)
        }
    }

    func testAdmissibleHighScoreStillCorrects() {
        let planned = CameraBoundedActionPlanner.plan(
            admissibility: admissibility(),
            safetyDecision: .allow,
            candidates: [candidate(id: "a", probability: 0.9)],
            goodFrameScore: 0.1,
            frameID: "f1"
        )
        XCTAssertEqual(planned.decision, .correct)
        XCTAssertEqual(planned.actionID, "a")
    }

    // MARK: - Generic label expansion (C05 item 4)

    func testGenericSimplifyHotspotRebalanceRequireConcreteActuator() {
        for generic in [SemanticActionType.simplifyBackground,
                        .removeBackgroundHotspot,
                        .repositionPropForBalance] {
            XCTAssertTrue(CameraAdviceActionExpansion.isGenericExecutableLabel(generic))
            XCTAssertNil(
                CameraAdviceActionExpansion.concreteActuator(for: generic, hasGroundedTarget: false),
                "\(generic) without a grounded target must not become a command"
            )
            XCTAssertNotNil(
                CameraAdviceActionExpansion.concreteActuator(for: generic, hasGroundedTarget: true),
                "\(generic) with a grounded target expands to a concrete actuator"
            )
        }
    }

    func testConcreteLabelIsNotExpanded() {
        XCTAssertFalse(CameraAdviceActionExpansion.isGenericExecutableLabel(.shiftFrameLeft))
        XCTAssertEqual(
            CameraAdviceActionExpansion.concreteActuator(for: .shiftFrameLeft, hasGroundedTarget: false),
            .shiftFrameLeft
        )
    }

    // MARK: - Single owner: technical fallback cannot override the planner

    func testPlanKeepSuppressesCompetingTechnicalCommand() {
        XCTAssertFalse(
            CameraAdviceSingleOwner.admitsTechnicalCommand(
                planPrimaryActionType: .leaveFrameAsIs,
                technicalAction: .refocusSubject
            ),
            "a technical command must not override an accepted KEEP"
        )
    }

    func testPlanSilentAllowsTechnicalFallback() {
        XCTAssertTrue(
            CameraAdviceSingleOwner.admitsTechnicalCommand(
                planPrimaryActionType: nil,
                technicalAction: .refocusSubject
            )
        )
    }

    func testTechnicalCommandOfDifferentFamilyIsRejected() {
        // Plan accepted a composition correction; a focus technical command is
        // a competing second decision.
        XCTAssertFalse(
            CameraAdviceSingleOwner.admitsTechnicalCommand(
                planPrimaryActionType: .changeAngle,
                technicalAction: .refocusSubject
            )
        )
        XCTAssertTrue(
            CameraAdviceSingleOwner.admitsTechnicalCommand(
                planPrimaryActionType: .changeAngle,
                technicalAction: .avoidOcclusion
            ),
            "same composition family keeps the planner's ownership"
        )
    }

    // MARK: - Alternative grouping: one step per cause

    func testAlternativeGroupYieldsExactlyOneExecutableStep() {
        let rows = [
            PauseActionRow(
                actionId: "act_technical_change_angle",
                actionType: .changeAngle,
                semanticActionType: .changeCameraAngle,
                priority: 1,
                confidence: 0.9,
                linkedIssueIds: [],
                expectedOutcome: "сменить точку",
                targetRegion: nil,
                overlayHintId: nil,
                traceRefId: "t",
                alternativeGroupID: "alt_overexposure_t",
                concreteSemanticActionType: .changeCameraAngle
            ),
            PauseActionRow(
                actionId: "act_technical_remove_hotspot",
                actionType: .changeAngle,
                semanticActionType: .removeBackgroundHotspot,
                priority: 2,
                confidence: 0.9,
                linkedIssueIds: [],
                expectedOutcome: "убрать пятно",
                targetRegion: nil,
                overlayHintId: nil,
                traceRefId: "t",
                alternativeGroupID: "alt_overexposure_t",
                concreteSemanticActionType: .changeCameraAngle
            ),
            PauseActionRow(
                actionId: "act_technical_level_horizon",
                actionType: .levelHorizon,
                semanticActionType: .levelHorizon,
                priority: 3,
                confidence: 0.9,
                linkedIssueIds: [],
                expectedOutcome: "выровнять",
                targetRegion: nil,
                overlayHintId: nil,
                traceRefId: "t",
                alternativeGroupID: "alt_horizon_t",
                concreteSemanticActionType: .levelHorizon
            ),
        ]

        let executed = PauseActionRow.executableCommands(from: rows)
        XCTAssertEqual(executed.map(\.actionId),
                       ["act_technical_change_angle", "act_technical_level_horizon"],
                       "one step per alternative group, plus the independent horizon problem")
    }

    func testIndependentRowsAreAllExecutable() {
        let rows = [
            PauseActionRow(
                actionId: "a", actionType: .changeAngle, semanticActionType: .changeCameraAngle,
                priority: 1, confidence: 0.8, linkedIssueIds: [], expectedOutcome: "x",
                targetRegion: nil, overlayHintId: nil, traceRefId: "t"
            ),
            PauseActionRow(
                actionId: "b", actionType: .levelHorizon, semanticActionType: .levelHorizon,
                priority: 2, confidence: 0.8, linkedIssueIds: [], expectedOutcome: "y",
                targetRegion: nil, overlayHintId: nil, traceRefId: "t"
            ),
        ]
        XCTAssertEqual(PauseActionRow.executableCommands(from: rows).map(\.actionId), ["a", "b"])
    }
}
