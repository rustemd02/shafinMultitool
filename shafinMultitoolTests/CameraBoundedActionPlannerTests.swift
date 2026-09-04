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
                           target: (Double, Double)? = (0.5, 0.5)) -> CameraPlannerCandidate {
        CameraPlannerCandidate(
            actionID: id,
            actionFamily: .composition,
            calibratedProbability: probability,
            priorityBand: band,
            targetPoint: target
        )
    }

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

    func testNonCorrectDecisionsCarryNoTarget() {
        for decision in [
            CameraBoundedActionPlanner.plan(
                safetyDecision: .wait(reason: .motionNotStill),
                candidates: [candidate(id: "a", target: (1, 1))],
                goodFrameScore: 0.1, frameID: "f1"
            ),
        ] {
            XCTAssertNil(decision.targetPoint, "\(decision.decision) must not carry a target")
        }
    }
}
