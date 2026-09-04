//
//  GoodFramePreservationPolicy.swift
//  shafinMultitool
//
//  M2-021 SafetyPolicyOwner: explicit already-good detection and protection
//  against overcorrection. KEEP is emitted only for a STABLE streak of high
//  good-frame scores with NO dominant technical failure. An uncertain
//  strong-looking frame (high score but a dominant failure present, or the
//  streak too short) ABSTAINS instead of inventing a fix — overcorrection of
//  a good frame is a forbidden correction.
//

import Foundation

/// The already-good verdict for the current frame stream.
enum GoodFrameVerdict: Equatable, Sendable {
    /// The frame stream is stably good: KEEP is honest.
    case keepStable(lastFrameID: String, score: Double)
    /// Uncertain strong-looking frame: abstain, no fix invented.
    case abstain(reason: GoodFrameAbstainReason)
}

enum GoodFrameAbstainReason: String, Equatable, Sendable, CaseIterable {
    /// Fewer consecutive high-score frames than the stability window.
    case historyTooShort = "history_too_short"
    /// A dominant technical failure contradicts the good-frame head.
    case dominantTechnicalFailure = "dominant_technical_failure"
    /// The last score dropped below the keep threshold (streak broken).
    case scoreBelowThreshold = "score_below_threshold"
}

struct GoodFrameSample: Equatable, Sendable {
    let frameID: String
    let score: Double
}

/// Pure policy over the good-frame score history. Same input, same verdict.
enum GoodFramePreservationPolicy {

    static let defaultKeepThreshold: Double = 0.8
    static let defaultStableStreak: Int = 5

    /// - Parameters:
    ///   - samples: good-frame head scores in frame order.
    ///   - hasDominantTechnicalFailure: true when TechnicalQualitySignal
    ///     reports a DOMINANT failure (defocus/under/over/clipping) — a
    ///     strong-looking frame with a dominant failure abstains.
    ///   - keepThreshold: the high-confidence keep threshold.
    ///   - stableStreak: consecutive above-threshold frames KEEP requires.
    static func evaluate(
        samples: [GoodFrameSample],
        hasDominantTechnicalFailure: Bool,
        keepThreshold: Double = defaultKeepThreshold,
        stableStreak: Int = defaultStableStreak
    ) -> GoodFrameVerdict {
        guard stableStreak > 0 else {
            return .abstain(reason: .historyTooShort)
        }

        // Walk from the newest sample backwards, counting the current
        // above-threshold streak.
        var streak: [GoodFrameSample] = []
        for sample in samples.reversed() {
            guard sample.score >= keepThreshold else { break }
            streak.insert(sample, at: 0)
        }

        guard streak.count >= stableStreak, let last = streak.last else {
            return .abstain(reason: .historyTooShort)
        }

        // A dominant technical failure contradicts the good-frame head:
        // the honest outcome is abstention, not a fix and not a KEEP.
        if hasDominantTechnicalFailure {
            return .abstain(reason: .dominantTechnicalFailure)
        }

        return .keepStable(lastFrameID: last.frameID, score: last.score)
    }
}
