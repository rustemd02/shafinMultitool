//
//  AdviceStabilizer.swift
//  shafinMultitool
//
//  M2-022 AdviceTemporalOwner: ONE temporal advice stabilizer with dwell,
//  hysteresis, cooldown and material-change semantics. Advice changes no
//  more than once per cooldown window (3 s default) unless a MATERIAL SAFETY
//  CHANGE occurs — invalidation (route/lens/generation/scene cut, M2-011)
//  removes the old advice IMMEDIATELY, bypassing every dwell/cooldown gate.
//

import Foundation

/// The stabilized advice a consumer sees.
struct StabilizedAdvice: Equatable, Sendable {
    let decision: CameraCoachDecisionV2
    let actionID: String?
    let frameID: String
    /// Nil when no advice is published (WAIT/ABSTAIN/SELECT_SUBJECT without
    /// an action).
    let targetX: Double?
    let targetY: Double?

    var targetPoint: (x: Double, y: Double)? {
        guard let targetX, let targetY else { return nil }
        return (targetX, targetY)
    }
}

/// Material safety change: bypasses dwell/cooldown — the old advice is
/// removed immediately.
struct MaterialSafetyChange: Equatable, Sendable {
    let frameID: String
    /// Any M2-011 cause or an explicit safety contradiction flag.
    let reason: String
}

/// Pure temporal stabilizer; the pipeline feeds it one planner decision per
/// frame with the deterministic clock it owns.
struct AdviceStabilizer {

    /// Minimum seconds between PUBLISHED advice changes (dwell + cooldown).
    static let defaultChangeCooldownSeconds: TimeInterval = 3.0
    /// Consecutive identical decisions required before a change is published.
    static let defaultHysteresisFrames: Int = 3

    private var published: StabilizedAdvice?
    private var lastChangeAt: Date?
    private var pendingDecision: CameraCoachDecisionV2?
    private var pendingActionID: String?
    private var pendingCount = 0

    private let cooldownSeconds: TimeInterval
    private let hysteresisFrames: Int
    private var clock: () -> Date

    init(cooldownSeconds: TimeInterval = AdviceStabilizer.defaultChangeCooldownSeconds,
         hysteresisFrames: Int = AdviceStabilizer.defaultHysteresisFrames,
         clock: @escaping () -> Date = { Date() }) {
        self.cooldownSeconds = cooldownSeconds
        self.hysteresisFrames = hysteresisFrames
        self.clock = clock
    }

    /// The advice currently published to consumers.
    var currentAdvice: StabilizedAdvice? {
        published
    }

    /// Feeds one planner decision. Returns the advice that should be
    /// PRESENTED after this frame: the previous advice, the new advice, or
    /// nil (no advice published/remaining).
    mutating func observe(_ decision: CameraPlannerDecision) -> StabilizedAdvice? {
        let incoming = StabilizedAdvice(
            decision: decision.decision,
            actionID: decision.actionID,
            frameID: decision.frameID,
            targetX: decision.targetPoint?.x,
            targetY: decision.targetPoint?.y
        )

        guard let current = published else {
            // Nothing published yet: non-correction decisions pass through
            // immediately (WAIT/ABSTAIN are honest states, not advice).
            if decision.decision != .correct {
                published = incoming
                lastChangeAt = clock()
                return incoming
            }
            // First CORRECT needs the hysteresis dwell.
            return countPending(incoming)
        }

        // The frame ID and target are provenance, not the semantic identity
        // of advice. A recurring action on a fresh frame must refresh its
        // attribution; otherwise downstream consumers receive an old frame
        // ID and reject otherwise-valid same-action evidence as stale.
        if incoming.decision == current.decision,
           incoming.actionID == current.actionID {
            pendingDecision = nil
            pendingActionID = nil
            pendingCount = 0
            published = incoming
            return incoming
        }

        // A different decision is building up: require the hysteresis dwell.
        if decision.decision != .correct || current.decision != .correct {
            return countPending(incoming)
        }
        // Both CORRECT but a different action: same dwell.
        return countPending(incoming)
    }

    /// Material safety change (M2-011 cause, safety contradiction): the old
    /// advice is removed IMMEDIATELY — dwell and cooldown are bypassed.
    @discardableResult
    mutating func invalidate(frameID: String, reason: String) -> StabilizedAdvice? {
        let removed = published
        published = nil
        pendingDecision = nil
        pendingActionID = nil
        pendingCount = 0
        lastChangeAt = clock()
        _ = frameID
        _ = reason
        return removed
    }

    private mutating func countPending(_ incoming: StabilizedAdvice) -> StabilizedAdvice? {
        let same = pendingDecision == incoming.decision && pendingActionID == incoming.actionID
        if same {
            pendingCount += 1
        } else {
            pendingDecision = incoming.decision
            pendingActionID = incoming.actionID
            pendingCount = 1
        }
        guard pendingCount >= hysteresisFrames else {
            return published
        }

        // Hysteresis satisfied: respect the change cooldown unless the
        // published advice is nil (nothing to protect).
        let now = clock()
        if let current = published,
           let changedAt = lastChangeAt,
           now.timeIntervalSince(changedAt) < cooldownSeconds {
            _ = current
            return current
        }

        published = incoming
        lastChangeAt = now
        pendingDecision = nil
        pendingActionID = nil
        pendingCount = 0
        return incoming
    }
}
