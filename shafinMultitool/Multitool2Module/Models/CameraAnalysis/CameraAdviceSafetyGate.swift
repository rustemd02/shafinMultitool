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
}

/// Evidence per forbidden action family: which family the candidate belongs
/// to and whether its supporting evidence is currently available.
enum CameraAdviceActionFamily: String, Equatable, Sendable, CaseIterable {
    case horizon = "horizon"
    case focus = "focus"
    case exposure = "exposure"
    case composition = "composition"
    case keep = "keep"
}

/// The deterministic safety gate. Pure: same input always yields the same
/// decision.
enum CameraAdviceSafetyGate {

    static let defaultMinimumConfidence: Double = 0.5

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

        // 2. Subject identity: a lost track invalidates every correction.
        if input.subjectTrackLost == true {
            return .abstain(reason: .subjectIdentityLost)
        }
        // 2a. Declared ambiguity requires the S05 tap: no correction can be
        //     emitted while the subject is not resolved.
        if input.subjectAmbiguous {
            return .selectSubject(reason: .subjectAmbiguous)
        }
        // 2b. No subject resolution at all is also a SELECT_SUBJECT case.
        if input.subjectTrackLost == nil {
            return .selectSubject(reason: .subjectAmbiguous)
        }

        // 3. Motion: corrections wait for a still frame — stabilisation
        //    advice is not actionable while the camera moves.
        if !input.motionStateIsStill {
            return .wait(reason: .motionNotStill)
        }

        // 4. Exposure contradiction: under- and overexposure cannot both be
        //    advised — the metric set is unreliable, wait it out.
        if !input.exposureContradictionFree {
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
        case .exposure, .composition, .keep:
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
