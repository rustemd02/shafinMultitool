//
//  CameraAdviceSafetyGate.swift
//  shafinMultitool
//
//  M2-019 SafetyPolicyOwner: deterministic forbidden-action and abstention
//  gates applied AFTER neural inference and calibration. Critical forbidden
//  cases override any neural action utility; low confidence, identity loss,
//  motion and missing evidence can never produce a correction — they fail
//  closed to WAIT / SELECT_SUBJECT / ABSTAIN.
//

import Foundation

/// The safety decision for one advice candidate.
enum CameraAdviceSafetyDecision: Equatable, Sendable {
    /// The calibrated action may proceed to presentation.
    case allow
    /// Evidence is still acquiring — wait (no correction emitted).
    case wait(reason: SafetyBlockReason)
    /// Subject ambiguity requires one user tap (no correction emitted).
    case selectSubject(reason: SafetyBlockReason)
    /// Insufficient evidence for any honest advice (no correction emitted).
    case abstain(reason: SafetyBlockReason)
}

/// Machine-readable block reasons (stable ids for diagnostics/validation).
enum SafetyBlockReason: String, Equatable, Sendable, CaseIterable {
    case lensGenerationUnknown = "lens_generation_unknown"
    case subjectIdentityLost = "subject_identity_lost"
    case subjectAmbiguous = "subject_ambiguous"
    case motionNotStill = "motion_not_still"
    case exposureContradiction = "exposure_contradiction"
    case focusEvidenceNotAdmitted = "focus_evidence_not_admitted"
    case horizonEvidenceUnavailable = "horizon_evidence_unavailable"
    case calibratedProbabilityMissing = "calibrated_probability_missing"
    case calibratedProbabilityLow = "calibrated_probability_low"
    /// The user confirmed this effect is intentional (CC-I05); the coach must
    /// not "fix" a deliberate style for the rest of the session.
    case intentionalStylePreserved = "intentional_style_preserved"
    // C05 pre-ranking admissibility reasons. These are prohibitions, not
    // scores: a candidate rejected for one of them can never be ranked back
    // into CORRECT by a higher probability.
    case manipulationNotPermitted = "manipulation_not_permitted"
    case resourceUnavailable = "resource_unavailable"
    case destinationUnreachable = "destination_unreachable"
    case modeNotAdmitted = "mode_not_admitted"
    case verifierUnsupported = "verifier_unsupported"
    case targetStale = "target_stale"
}

/// Evidence snapshot the gate reads. Built by the pipeline from the frame
/// envelope and the M2-012…016/M2-018 feature owners.
struct CameraAdviceSafetyInput: Equatable, Sendable {
    let lensGenerationKnown: Bool
    /// Nil while no subject resolution exists; `isLost` when tracking failed.
    let subjectTrackLost: Bool?
    /// True when automatic resolution reported subject ambiguity (M2-007).
    let subjectAmbiguous: Bool
    let motionStateIsStill: Bool
    let exposureContradictionFree: Bool
    /// Focus evidence verdict (nil = not computed → fail closed).
    let refocusAdviceAdmitted: Bool?
    /// Horizon evidence verdict (nil = not computed → fail closed).
    let horizonAvailable: Bool?
    /// Calibrated probability of the candidate action (nil = calibration
    /// abstained, e.g. out-of-domain or no entry).
    let calibratedProbability: Double?
    /// Minimum calibrated probability for a correction to be allowed.
    let minimumConfidence: Double
    /// Session-scoped families the user confirmed as intentional (CC-I05).
    /// Empty by default so existing call sites are unaffected.
    var intentionallySuppressedFamilies: Set<CameraAdviceActionFamily> = []
}

/// Evidence per forbidden action family: which family the candidate belongs
/// to and whether its supporting evidence is currently available.
enum CameraAdviceActionFamily: String, Equatable, Sendable, CaseIterable {
    case horizon = "horizon"
    case focus = "focus"
    case exposure = "exposure"
    case composition = "composition"
    /// Technical camera-stability evidence may be admitted while the camera
    /// is moving. It never makes composition/exposure/focus advice actionable
    /// during motion; those families still fail closed below.
    case stability = "stability"
    case keep = "keep"
}

/// C05 pre-ranking admissibility: the prerequisites a candidate must satisfy
/// BEFORE it is ranked. These are prohibitions, not signals — no calibrated
/// probability, raw logit or VLM confidence can turn a rejected candidate into
/// the accepted action. Every field is fail-closed: `false` means the
/// prerequisite is not established, so the candidate is withheld.
struct CameraAdviceAdmissibilityInput: Equatable, Sendable {
    /// The current intentRevision permits a correction of this kind at all.
    let intentAllowsCorrection: Bool
    /// The scene owner / presentation mode allows manipulating this target
    /// (for example a participant of a live event may not be repositioned).
    let manipulationPermitted: Bool
    /// The required physical resource really exists and is controllable.
    let resourceAvailable: Bool
    /// The destination region is known to be reachable/available.
    let destinationReachable: Bool
    /// The operation is admissible in the current capture mode/phase.
    let modeAdmitted: Bool
    /// Calibrated evidence for this candidate exists.
    let calibratedEvidenceAvailable: Bool
    /// A supported verifier can actually measure the promised effect.
    let verifierSupported: Bool
    /// The tracked target is fresh for the current baseline.
    let targetFresh: Bool

    init(intentAllowsCorrection: Bool,
         manipulationPermitted: Bool,
         resourceAvailable: Bool,
         destinationReachable: Bool,
         modeAdmitted: Bool,
         calibratedEvidenceAvailable: Bool,
         verifierSupported: Bool,
         targetFresh: Bool) {
        self.intentAllowsCorrection = intentAllowsCorrection
        self.manipulationPermitted = manipulationPermitted
        self.resourceAvailable = resourceAvailable
        self.destinationReachable = destinationReachable
        self.modeAdmitted = modeAdmitted
        self.calibratedEvidenceAvailable = calibratedEvidenceAvailable
        self.verifierSupported = verifierSupported
        self.targetFresh = targetFresh
    }
}

/// The pre-ranking verdict. Evaluation order is fixed (intent → permissions →
/// resource → destination → mode → calibrated evidence → verifier →
/// freshness) so diagnostics are deterministic.
enum CameraAdviceAdmissibilityDecision: Equatable, Sendable {
    case admissible
    case rejected(reason: SafetyBlockReason)

    var isAdmissible: Bool {
        self == .admissible
    }

    /// Fail-closed planner state for a rejected candidate. A prohibition maps
    /// to ABSTAIN; a temporarily removable condition (stale target) maps to
    /// WAIT. Neither carries an action.
    var plannerDecision: CameraCoachDecisionV2 {
        switch self {
        case .admissible:
            return .abstain
        case .rejected(let reason):
            switch reason {
            case .targetStale:
                return .wait
            default:
                return .abstain
            }
        }
    }
}

/// The deterministic safety gate. Pure: same input always yields the same
/// decision.
enum CameraAdviceSafetyGate {

    static let defaultMinimumConfidence: Double = 0.5

    /// C05: runs BEFORE any candidate ranking. A rejected prerequisite is a
    /// prohibition; the planner must not rank a candidate past it. The order
    /// is fixed and every missing prerequisite fails closed.
    static func evaluateAdmissibility(
        _ input: CameraAdviceAdmissibilityInput
    ) -> CameraAdviceAdmissibilityDecision {
        guard input.intentAllowsCorrection else {
            return .rejected(reason: .intentionalStylePreserved)
        }
        guard input.manipulationPermitted else {
            return .rejected(reason: .manipulationNotPermitted)
        }
        guard input.resourceAvailable else {
            return .rejected(reason: .resourceUnavailable)
        }
        guard input.destinationReachable else {
            return .rejected(reason: .destinationUnreachable)
        }
        guard input.modeAdmitted else {
            return .rejected(reason: .modeNotAdmitted)
        }
        guard input.calibratedEvidenceAvailable else {
            return .rejected(reason: .calibratedProbabilityMissing)
        }
        guard input.verifierSupported else {
            return .rejected(reason: .verifierUnsupported)
        }
        guard input.targetFresh else {
            return .rejected(reason: .targetStale)
        }
        return .admissible
    }

    /// Evaluates one candidate action. Order matters: identity/evidence
    /// failures first (they invalidate EVERYTHING), then per-family
    /// forbidden rules, then confidence.
    static func evaluate(
        actionFamily: CameraAdviceActionFamily,
        input: CameraAdviceSafetyInput
    ) -> CameraAdviceSafetyDecision {
        // 1. Evidence attribution: an unknown lens generation means the frame
        //    cannot be attributed — no honest advice at all.
        guard input.lensGenerationKnown else {
            return .abstain(reason: .lensGenerationUnknown)
        }

        // 2. Subject identity is required only by subject-dependent action
        //    families. Horizon and stability are frame-global and must remain
        //    actionable when no subject was selected.
        let requiresSubjectIdentity: Bool
        switch actionFamily {
        case .composition, .exposure, .focus:
            requiresSubjectIdentity = true
        case .horizon, .stability, .keep:
            requiresSubjectIdentity = false
        }
        if requiresSubjectIdentity {
            // 2a. A lost track invalidates subject-dependent corrections.
            if input.subjectTrackLost == true {
                return .abstain(reason: .subjectIdentityLost)
            }
            // 2b. Declared ambiguity requires the S05 tap: no correction can
            //     be emitted while the subject is not resolved.
            if input.subjectAmbiguous {
                return .selectSubject(reason: .subjectAmbiguous)
            }
            // 2c. No subject resolution at all is also SELECT_SUBJECT.
            if input.subjectTrackLost == nil {
                return .selectSubject(reason: .subjectAmbiguous)
            }
        }

        // 2d. Confirmed intent: a style the user declared deliberate is never
        //     "corrected" for the rest of the session.
        if input.intentionallySuppressedFamilies.contains(actionFamily) {
            return .abstain(reason: .intentionalStylePreserved)
        }

        // 3. Motion: ordinary corrections wait for a still frame. A typed
        //    stability action is the sole exception: its purpose is to tell
        //    the operator to stop moving, and its after-frame verification
        //    remains strict in the episode coordinator.
        if !input.motionStateIsStill && actionFamily != .stability {
            return .wait(reason: .motionNotStill)
        }

        // 4. Exposure contradiction: under- and overexposure cannot both be
        //    advised — the metric set is unreliable, wait it out. Stability
        //    is frame-global and does not make an exposure claim, so it does
        //    not inherit this unrelated family gate.
        if !input.exposureContradictionFree && actionFamily != .stability {
            return .wait(reason: .exposureContradiction)
        }

        // 5. Per-family forbidden rules: critical evidence gates override the
        //    neural utility of the matching action family.
        switch actionFamily {
        case .horizon:
            guard input.horizonAvailable == true else {
                return .abstain(reason: .horizonEvidenceUnavailable)
            }
        case .focus:
            guard input.refocusAdviceAdmitted == true else {
                return .abstain(reason: .focusEvidenceNotAdmitted)
            }
        case .exposure, .composition, .stability, .keep:
            break
        }

        // 6. Calibration: raw utility never reaches advice without a
        //    calibrated probability, and low probability waits.
        guard let probability = input.calibratedProbability else {
            return .abstain(reason: .calibratedProbabilityMissing)
        }
        guard probability >= input.minimumConfidence else {
            return .wait(reason: .calibratedProbabilityLow)
        }

        return .allow
    }
}
