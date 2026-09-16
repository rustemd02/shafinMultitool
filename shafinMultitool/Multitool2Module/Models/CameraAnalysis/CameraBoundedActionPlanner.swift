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
    /// Local subject/object identity the advice is bound to. Nil for
    /// frame-global advice.
    let targetIdentity: SubjectTrackIdentity?

    init(actionID: String,
         actionFamily: CameraAdviceActionFamily,
         calibratedProbability: Double,
         priorityBand: Int,
         targetPoint: (x: Double, y: Double)?,
         targetIdentity: SubjectTrackIdentity? = nil) {
        self.actionID = actionID
        self.actionFamily = actionFamily
        self.calibratedProbability = calibratedProbability
        self.priorityBand = priorityBand
        self.targetPoint = targetPoint
        self.targetIdentity = targetIdentity
    }

    static func == (lhs: CameraPlannerCandidate, rhs: CameraPlannerCandidate) -> Bool {
        lhs.actionID == rhs.actionID
            && lhs.calibratedProbability == rhs.calibratedProbability
            && lhs.priorityBand == rhs.priorityBand
            && lhs.targetIdentity == rhs.targetIdentity
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
    /// Local subject/object identity the CORRECT advice is bound to.
    let targetIdentity: SubjectTrackIdentity?
    /// The safety reason when the decision is not ALLOW.
    let blockReason: SafetyBlockReason?

    init(decision: CameraCoachDecisionV2,
         actionID: String?,
         frameID: String,
         calibratedProbability: Double?,
         targetPoint: (x: Double, y: Double)?,
         blockReason: SafetyBlockReason?,
         targetIdentity: SubjectTrackIdentity? = nil) {
        self.decision = decision
        self.actionID = actionID
        self.frameID = frameID
        self.calibratedProbability = calibratedProbability
        self.targetPoint = targetPoint
        self.targetIdentity = targetIdentity
        self.blockReason = blockReason
    }

    static func == (lhs: CameraPlannerDecision, rhs: CameraPlannerDecision) -> Bool {
        lhs.decision == rhs.decision
            && lhs.actionID == rhs.actionID
            && lhs.frameID == rhs.frameID
            && lhs.calibratedProbability == rhs.calibratedProbability
            && lhs.blockReason == rhs.blockReason
            && lhs.targetPoint?.x == rhs.targetPoint?.x
            && lhs.targetPoint?.y == rhs.targetPoint?.y
            && lhs.targetIdentity == rhs.targetIdentity
    }
}

enum CameraBoundedActionPlanner {

    /// Plans at most one recommendation.
    ///
    /// - Parameters:
    ///   - admissibility: the C05 pre-ranking verdict. It is evaluated FIRST,
    ///     before the safety gate and before any candidate comparison. A
    ///     rejected prerequisite can never be outranked by a higher
    ///     calibrated probability — this is the package invariant.
    ///   - safetyDecision: the M2-019 gate verdict for the top candidate's
    ///     family. Non-allow decisions pass through unchanged (fail closed).
    ///   - candidates: calibrated SAFE candidates for the allowed family.
    ///   - goodFrameScore: good-frame head output; ≥ 0.8 with no candidate
    ///     emits KEEP instead of CORRECT (explicit already-good protection is
    ///     completed by M2-021; this is the planner-side keep path).
    ///   - frameID: provenance.
    static func plan(
        admissibility: CameraAdviceAdmissibilityDecision = .admissible,
        safetyDecision: CameraAdviceSafetyDecision,
        candidates: [CameraPlannerCandidate],
        goodFrameScore: Double,
        frameID: String
    ) -> CameraPlannerDecision {
        // 0. C05 pre-ranking prohibition. No score, logit or provider
        //    confidence can bypass this branch.
        if case .rejected(let reason) = admissibility {
            return CameraPlannerDecision(
                decision: admissibility.plannerDecision,
                actionID: nil,
                frameID: frameID,
                calibratedProbability: nil,
                targetPoint: nil,
                blockReason: reason
            )
        }

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
            blockReason: nil,
            targetIdentity: best.targetIdentity
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

/// C05/N6.2/N9.4: generic labels that name an outcome but not a concrete
/// actuator. They must expand into a concrete frozen action when issued, or be
/// withheld — they are never an independent executable command.
enum CameraAdviceActionExpansion {

    /// The generic semantic labels the actions consilium (§9.4) requires to be
    /// merged into a concrete operation at issue time.
    static let genericExecutableLabels: Set<SemanticActionType> = [
        .simplifyBackground,
        .removeBackgroundHotspot,
        .repositionPropForBalance
    ]

    static func isGenericExecutableLabel(_ action: SemanticActionType) -> Bool {
        genericExecutableLabels.contains(action)
    }

    /// The concrete frozen actuator a generic label must expand into, or nil
    /// when no grounded concrete actuator exists (fail closed). A caller must
    /// then keep the generic label as an explanation/alternative only.
    ///
    /// Grounding rule (N6.1/N6.2): without a confirmed target there is no
    /// concrete move; a class label alone never proves a movable instance.
    static func concreteActuator(for generic: SemanticActionType,
                                 hasGroundedTarget: Bool) -> SemanticActionType? {
        switch generic {
        case .simplifyBackground, .removeBackgroundHotspot:
            // Background competition is resolved by a camera reposition with a
            // confirmed free point; the generic score does not say which thing
            // is "clutter".
            return hasGroundedTarget ? .changeCameraAngle : nil
        case .repositionPropForBalance:
            // "Rebalance" is an outcome; the concrete operation is moving the
            // grounded prop. Never invent a cup or a window.
            return hasGroundedTarget ? .moveObjectBack : nil
        default:
            return generic
        }
    }
}

/// C05/N6.2 order-of-comparison: alternatives of one cause share one group.
/// The group guarantees that at most one of them is ever displayed/executed as
/// the current step; the rest are compared options, not a queue.
enum CameraAdviceAlternativeGrouping {

    /// Deterministic group id for one cause on one frame. Callers pass the
    /// issue/finding key so all rows of the same cause group together.
    static func groupID(cause: String, traceID: String) -> String {
        "alt_\(cause)_\(traceID)"
    }

    /// The one executable row per group. Independent rows (nil group) each
    /// remain their own command. Deterministic: lowest priority, then id.
    static func executableCommands<Row>(from rows: [Row],
                                        groupID: (Row) -> String?,
                                        priority: (Row) -> Int,
                                        actionID: (Row) -> String) -> [Row] {
        var seenGroups = Set<String>()
        var result: [Row] = []
        for row in rows.sorted(by: { lhs, rhs in
            if priority(lhs) != priority(rhs) { return priority(lhs) < priority(rhs) }
            return actionID(lhs) < actionID(rhs)
        }) {
            guard let group = groupID(row) else {
                result.append(row)
                continue
            }
            guard !seenGroups.contains(group) else { continue }
            seenGroups.insert(group)
            result.append(row)
        }
        return result
    }
}

/// C05 item 1: the planner is the single owner of the final decision. The
/// technical live fallback may only speak about the same action family the
/// accepted plan chose; it must never silently substitute a competing command
/// produced from the raw technical signal.
enum CameraAdviceSingleOwner {

    static func family(for actionType: ActionTypeV1) -> CameraAdviceActionFamily? {
        switch actionType {
        case .changeAngle, .moveFrameLeft, .moveFrameRight, .moveFrameUp, .moveFrameDown,
             .increaseSubjectSize, .reduceBackgroundDistractions:
            return .composition
        case .improveFrontLight:
            return .exposure
        case .levelHorizon:
            return .horizon
        case .leaveFrameAsIs:
            return nil
        }
    }

    static func technicalFamily(for action: TechnicalQualityActionType) -> CameraAdviceActionFamily {
        switch action {
        case .stabilizeCamera: return .stability
        case .refocusSubject: return .focus
        case .reduceExposure, .increaseExposure, .cleanLens, .reduceIsoNoise: return .exposure
        case .avoidOcclusion: return .composition
        }
    }

    /// True when the technical command may be shown without becoming a second
    /// owner of the final decision.
    ///
    /// - The plan is silent (no corrective primary): the technical layer may
    ///   act as the fallback that produced the only evidence.
    /// - The plan accepted a corrective action of the SAME family: the
    ///   technical hint describes that same accepted action.
    /// - The plan accepted KEEP or a different family: a technical command
    ///   would override the planner, so it is withheld (fail closed).
    static func admitsTechnicalCommand(planPrimaryActionType: ActionTypeV1?,
                                       technicalAction: TechnicalQualityActionType) -> Bool {
        guard let planType = planPrimaryActionType else { return true }
        guard let planFamily = family(for: planType) else { return false }
        return planFamily == technicalFamily(for: technicalAction)
    }
}
