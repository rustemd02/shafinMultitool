//
//  CameraIntentClarificationPolicy.swift
//  shafinMultitool
//
//  CC-I05 "intentional style looks like a defect": bounded, session-scoped
//  intent clarification. The policy detects style cues from existing evidence,
//  asks one yes/no question, and — when the user confirms intent — suppresses
//  the conflicting corrective families for the rest of the session so the
//  coach never "fixes" a deliberate style.
//
//  Pure value semantics; it does not present UI and does not alter the
//  planner. The safety gate consumes `suppressedFamilies`.
//

import Foundation

/// Style cues that can look like technical defects.
enum CameraStyleCue: String, CaseIterable, Codable, Sendable {
    case lowKey
    case silhouette
    case symmetry
    case tilt
    case motionBlur
    case negativeSpace
}

/// Evidence the cue detector reads (all fields already exist in the snapshot
/// or the semantics report).
struct CameraStyleCueEvidence: Equatable, Sendable {
    let horizonAngleDegrees: Double
    let horizonConfidence: Double
    let exposureBiasHint: Double
    let backlightIndex: Double
    let shakeLevel: Double
    let subjectReadable: Bool
    let hasClearFocus: Bool

    init(horizonAngleDegrees: Double,
         horizonConfidence: Double,
         exposureBiasHint: Double,
         backlightIndex: Double,
         shakeLevel: Double,
         subjectReadable: Bool,
         hasClearFocus: Bool) {
        self.horizonAngleDegrees = horizonAngleDegrees
        self.horizonConfidence = horizonConfidence
        self.exposureBiasHint = exposureBiasHint
        self.backlightIndex = backlightIndex
        self.shakeLevel = shakeLevel
        self.subjectReadable = subjectReadable
        self.hasClearFocus = hasClearFocus
    }
}

struct CameraIntentClarificationPrompt: Equatable, Sendable {
    let cue: CameraStyleCue
    /// Localization key for the one yes/no question.
    let promptKey: String
    let conflictingFamilies: [CameraAdviceActionFamily]
}

struct CameraIntentClarificationPolicy: Equatable, Sendable {

    /// Bounded detection thresholds (documented working values).
    static let tiltAngleThresholdDegrees = 2.0
    static let minimumTiltConfidence = 0.5
    static let lowKeyExposureBiasThreshold = -0.8
    static let silhouetteBacklightThreshold = 0.5
    static let motionBlurShakeThreshold = 0.6

    private(set) var answers: [CameraStyleCue: Bool] = [:]

    init() {}

    // MARK: - Detection

    /// Cues that plausibly reflect intent rather than a defect. A cue is only
    /// reported when the subject still reads (otherwise it is a real defect,
    /// not a style).
    static func detectedCues(from evidence: CameraStyleCueEvidence) -> Set<CameraStyleCue> {
        var cues: Set<CameraStyleCue> = []
        guard evidence.subjectReadable else { return cues }

        if abs(evidence.horizonAngleDegrees) >= tiltAngleThresholdDegrees,
           evidence.horizonConfidence >= minimumTiltConfidence {
            cues.insert(.tilt)
        }
        if Self.lowKeyExposureBiasThreshold >= evidence.exposureBiasHint {
            cues.insert(.lowKey)
        }
        if evidence.backlightIndex >= silhouetteBacklightThreshold {
            cues.insert(.silhouette)
        }
        if evidence.shakeLevel >= motionBlurShakeThreshold, !evidence.hasClearFocus {
            cues.insert(.motionBlur)
        }
        return cues
    }

    /// The single question to ask for the highest-priority unanswered cue.
    static func clarificationPrompt(for cue: CameraStyleCue) -> CameraIntentClarificationPrompt {
        CameraIntentClarificationPrompt(
            cue: cue,
            promptKey: "camera.coach.intent.\(cue.rawValue)",
            conflictingFamilies: conflictingFamilies(for: cue)
        )
    }

    /// Corrective families a confirmed cue suppresses.
    static func conflictingFamilies(for cue: CameraStyleCue) -> [CameraAdviceActionFamily] {
        switch cue {
        case .lowKey, .silhouette:
            return [.exposure]
        case .symmetry, .negativeSpace:
            return [.composition]
        case .tilt:
            return [.horizon]
        case .motionBlur:
            return [.focus, .stability]
        }
    }

    // MARK: - Answers

    /// Records one answer. Confirmed intent suppresses the conflicting
    /// families for the session; a "no" answer leaves them actionable and
    /// stops re-asking.
    mutating func record(cue: CameraStyleCue, intended: Bool) {
        answers[cue] = intended
    }

    func hasAnswered(_ cue: CameraStyleCue) -> Bool {
        answers[cue] != nil
    }

    var suppressedFamilies: Set<CameraAdviceActionFamily> {
        var families: Set<CameraAdviceActionFamily> = []
        for (cue, intended) in answers where intended {
            families.formUnion(Self.conflictingFamilies(for: cue))
        }
        return families
    }

    func isSuppressed(_ family: CameraAdviceActionFamily) -> Bool {
        suppressedFamilies.contains(family)
    }

    mutating func resetSession() {
        answers.removeAll()
    }
}
