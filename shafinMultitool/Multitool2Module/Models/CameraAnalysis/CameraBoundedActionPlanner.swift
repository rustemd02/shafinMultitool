//
//  CameraBoundedActionPlanner.swift
//  shafinMultitool
//
//  M2-020 AdvicePlannerOwner: ONE bounded planner that selects at most one
//  actionable recommendation from calibrated SAFE candidates. The safety gate
//  (M2-019) decision always wins; when allowed, the planner emits exactly one
//  CameraCoachDecisionV2 — CORRECT with the top calibrated candidate, or KEEP
//  when the good-frame evidence says the frame is already right. No secondary
//  live advice exists.
//

import Foundation

/// One calibrated safe candidate fed to the planner.
struct CameraPlannerCandidate: Equatable, Sendable {
    let actionID: String
    let actionFamily: CameraAdviceActionFamily
    let calibratedProbability: Double
    /// Priority band (lower = more primary), aligned with the tip catalog.
    let priorityBand: Int
    /// Subject-displacement target the text and marker will aim at
    /// (M2-004). Nil for depth/neutral actions.
    let targetPoint: (x: Double, y: Double)?

    static func == (lhs: CameraPlannerCandidate, rhs: CameraPlannerCandidate) -> Bool {
        lhs.actionID == rhs.actionID
            && lhs.calibratedProbability == rhs.calibratedProbability
            && lhs.priorityBand == rhs.priorityBand
    }
}

/// The planner's single decision with linked evidence.
struct CameraPlannerDecision: Equatable, Sendable {
    /// Exactly one of KEEP / CORRECT / SELECT_SUBJECT / WAIT / ABSTAIN.
    let decision: CameraCoachDecisionV2
    /// The chosen action (CORRECT only; nil otherwise).
    let actionID: String?
    /// Linked provenance.
    let frameID: String
    let calibratedProbability: Double?
    /// Linked subject-displacement target (CORRECT only).
    let targetPoint: (x: Double, y: Double)?
    /// The safety reason when the decision is not ALLOW.
    let blockReason: SafetyBlockReason?

    static func == (lhs: CameraPlannerDecision, rhs: CameraPlannerDecision) -> Bool {
        lhs.decision == rhs.decision
            && lhs.actionID == rhs.actionID
            && lhs.frameID == rhs.frameID
            && lhs.calibratedProbability == rhs.calibratedProbability
            && lhs.blockReason == rhs.blockReason
            && lhs.targetPoint?.x == rhs.targetPoint?.x
            && lhs.targetPoint?.y == rhs.targetPoint?.y
    }
}

enum CameraBoundedActionPlanner {

    /// Plans at most one recommendation.
    ///
    /// - Parameters:
    ///   - safetyDecision: the M2-019 gate verdict for the top candidate's
    ///     family. Non-allow decisions pass through unchanged (fail closed).
    ///   - candidates: calibrated SAFE candidates for the allowed family.
    ///   - goodFrameScore: good-frame head output; ≥ 0.8 with no candidate
    ///     emits KEEP instead of CORRECT (explicit already-good protection is
    ///     completed by M2-021; this is the planner-side keep path).
    ///   - frameID: provenance.
    static func plan(
        safetyDecision: CameraAdviceSafetyDecision,
        candidates: [CameraPlannerCandidate],
        goodFrameScore: Double,
        frameID: String
    ) -> CameraPlannerDecision {
        // The safety gate always wins — its reason is carried through.
        switch safetyDecision {
        case .wait(let reason):
            return CameraPlannerDecision(
                decision: .wait, actionID: nil, frameID: frameID,
                calibratedProbability: nil, targetPoint: nil, blockReason: reason
            )
        case .selectSubject(let reason):
            return CameraPlannerDecision(
                decision: .selectSubject, actionID: nil, frameID: frameID,
                calibratedProbability: nil, targetPoint: nil, blockReason: reason
            )
        case .abstain(let reason):
            return CameraPlannerDecision(
                decision: .abstain, actionID: nil, frameID: frameID,
                calibratedProbability: nil, targetPoint: nil, blockReason: reason
            )
        case .allow:
            break
        }

        // Explicit already-good: KEEP beats any correction candidate.
        if goodFrameScore >= 0.8 {
            return CameraPlannerDecision(
                decision: .keep, actionID: nil, frameID: frameID,
                calibratedProbability: goodFrameScore, targetPoint: nil, blockReason: nil
            )
        }

        // Bounded selection: exactly one candidate — highest calibrated
        // probability; ties resolve by priority band, then stable action id.
        guard let best = candidates.sorted(by: compareCandidates).first else {
            // ALLOW with no candidates: nothing actionable, frame not proven
            // good — honest WAIT.
            return CameraPlannerDecision(
                decision: .wait, actionID: nil, frameID: frameID,
                calibratedProbability: nil, targetPoint: nil,
                blockReason: .calibratedProbabilityMissing
            )
        }

        return CameraPlannerDecision(
            decision: .correct,
            actionID: best.actionID,
            frameID: frameID,
            calibratedProbability: best.calibratedProbability,
            targetPoint: best.targetPoint,
            blockReason: nil
        )
    }

    /// Deterministic candidate ordering: probability desc, priority band asc,
    /// action id asc.
    static func compareCandidates(_ lhs: CameraPlannerCandidate, _ rhs: CameraPlannerCandidate) -> Bool {
        if lhs.calibratedProbability != rhs.calibratedProbability {
            return lhs.calibratedProbability > rhs.calibratedProbability
        }
        if lhs.priorityBand != rhs.priorityBand {
            return lhs.priorityBand < rhs.priorityBand
        }
        return lhs.actionID < rhs.actionID
    }
}
