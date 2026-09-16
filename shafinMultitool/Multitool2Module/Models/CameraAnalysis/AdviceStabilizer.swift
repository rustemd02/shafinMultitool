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
    /// Local subject/object identity the advice is bound to. Nil for
    /// frame-global advice.
    let targetIdentity: SubjectTrackIdentity?

    init(decision: CameraCoachDecisionV2,
         actionID: String?,
         frameID: String,
         targetX: Double?,
         targetY: Double?,
         targetIdentity: SubjectTrackIdentity? = nil) {
        self.decision = decision
        self.actionID = actionID
        self.frameID = frameID
        self.targetX = targetX
        self.targetY = targetY
        self.targetIdentity = targetIdentity
    }

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
    private var pendingTargetIdentity: SubjectTrackIdentity?
    private var pendingCount = 0
    /// C05 item 5: a user-dismissed advice key. The same unfit advice is not
    /// immediately returned; it may only return after a material change (a
    /// different action/target/decision) or after `invalidate` (new analysis).
    private var dismissedDecision: CameraCoachDecisionV2?
    private var dismissedActionID: String?
    private var dismissedTargetIdentity: SubjectTrackIdentity?

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
            targetY: decision.targetPoint?.y,
            targetIdentity: decision.targetIdentity
        )

        // C05 item 5: do not immediately return the advice the user just
        // dismissed. A material change (different decision/action/target)
        // releases the suppression; `invalidate` (new analysis/context) also
        // clears it. Suppression never rewrites the user's assessment.
        if isDismissed(incoming) {
            resetPending()
            return nil
        }
        clearDismissalIfMateriallyDifferent(incoming)

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

        // A target change is a material semantic change even when the action
        // is unchanged. Remove the old target immediately; the new target
        // must earn a fresh CORRECT dwell and never inherits old advice.
        let targetChanged = current.targetIdentity != incoming.targetIdentity
        if targetChanged,
           (current.targetIdentity != nil
               || (current.decision == .correct && incoming.decision == .correct)) {
            published = nil
            resetPending()
            lastChangeAt = nil
            if incoming.decision != .correct {
                published = incoming
                lastChangeAt = clock()
                return incoming
            }
            return countPending(incoming)
        }

        // The frame ID and target point are provenance, not semantic identity
        // of advice. A recurring action on a fresh frame must refresh its
        // attribution; otherwise downstream consumers receive an old frame
        // ID and reject otherwise-valid same-action evidence as stale. The
        // target identity is part of that semantic key.
        if incoming.decision == current.decision,
           incoming.actionID == current.actionID,
           incoming.targetIdentity == current.targetIdentity {
            resetPending()
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
    /// advice is removed IMMEDIATELY — dwell and cooldown are bypassed. A new
    /// analysis also clears any user dismissal, because the dismissed advice's
    /// evidence no longer applies to the new context.
    @discardableResult
    mutating func invalidate(frameID: String, reason: String) -> StabilizedAdvice? {
        let removed = published
        published = nil
        resetPending()
        clearDismissal()
        lastChangeAt = clock()
        _ = frameID
        _ = reason
        return removed
    }

    /// C05 item 5: the user declined the current advice. The same advice is
    /// suppressed until a material change or a new analysis. This is a
    /// presentation/cycle control, not a quality judgement: it does not mark
    /// the frame worse and does not punish the user.
    @discardableResult
    mutating func dismiss(actionID: String?,
                          targetIdentity: SubjectTrackIdentity?) -> StabilizedAdvice? {
        let removed = published
        dismissedDecision = published?.decision ?? removed?.decision
        dismissedActionID = actionID
        dismissedTargetIdentity = targetIdentity
        published = nil
        resetPending()
        lastChangeAt = clock()
        return removed
    }

    /// True while the exact advice key is suppressed by the user.
    var isDismissed: Bool {
        dismissedDecision != nil || dismissedActionID != nil || dismissedTargetIdentity != nil
    }

    private func isDismissed(_ advice: StabilizedAdvice) -> Bool {
        guard isDismissed else { return false }
        return dismissedDecision == advice.decision
            && dismissedActionID == advice.actionID
            && dismissedTargetIdentity == advice.targetIdentity
    }

    private mutating func clearDismissalIfMateriallyDifferent(_ advice: StabilizedAdvice) {
        guard isDismissed, !isDismissed(advice) else { return }
        clearDismissal()
    }

    private mutating func clearDismissal() {
        dismissedDecision = nil
        dismissedActionID = nil
        dismissedTargetIdentity = nil
    }

    private mutating func countPending(_ incoming: StabilizedAdvice) -> StabilizedAdvice? {
        let same = pendingDecision == incoming.decision
            && pendingActionID == incoming.actionID
            && pendingTargetIdentity == incoming.targetIdentity
        if same {
            pendingCount += 1
        } else {
            pendingDecision = incoming.decision
            pendingActionID = incoming.actionID
            pendingTargetIdentity = incoming.targetIdentity
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
        resetPending()
        return incoming
    }

    private mutating func resetPending() {
        pendingDecision = nil
        pendingActionID = nil
        pendingTargetIdentity = nil
        pendingCount = 0
    }
}
