//
//  CoachingEpisodeCoordinator.swift
//  shafinMultitool
//
//  M2-024 VerificationOwner: owns one bounded before/after coaching episode.
//  The coordinator is deliberately a value type. Its state is moved with the
//  Camera owner, so a transient view cannot accidentally restart an episode
//  during recomposition or rotation.
//

import Foundation

/// The only phases an episode can expose to a production consumer.
enum CoachingEpisodePhase: String, Codable, CaseIterable, Equatable, Sendable {
    case idle
    case awaitingMovement = "awaiting_movement"
    case collectingStableAfterFrames = "collecting_stable_after_frames"
    case readyForVerification = "ready_for_verification"
    case cancelled
    case expired
}

/// Why an active episode stopped before verification. These are stable IDs for
/// diagnostics and presentation; no human-facing copy is stored here.
enum CoachingEpisodeCancellationReason: String, Codable, CaseIterable, Equatable, Sendable {
    case cameraGenerationChange = "camera_generation_change"
    case lensChange = "lens_change"
    case orientationChange = "orientation_change"
    case routeExit = "route_exit"
    case background
    case sceneCut = "scene_cut"
    case actionChanged = "action_changed"
    case subjectChanged = "subject_changed"
    case staleEvidence = "stale_evidence"
    case outOfOrder = "out_of_order"
    case invalidObservation = "invalid_observation"
    case expired
}

/// Immutable configuration for one episode. Counts are frame counts, never
/// time-based completion signals. `maxDuration` only provides a safety expiry.
struct CoachingEpisodeConfiguration: Equatable, Sendable {
    let requiredMovementFrames: Int
    let requiredStableAfterFrames: Int
    let maxDuration: TimeInterval

    init(requiredMovementFrames: Int = 2,
         requiredStableAfterFrames: Int = 2,
         maxDuration: TimeInterval = 12) {
        self.requiredMovementFrames = max(1, requiredMovementFrames)
        self.requiredStableAfterFrames = max(1, requiredStableAfterFrames)
        self.maxDuration = max(0.001, maxDuration.isFinite ? maxDuration : 12)
    }
}

/// The single baseline frozen when an episode starts. The baseline stores the
/// typed action and subject identity as well as the capture context that made
/// the advice valid; later UI text or mutable planner samples cannot replace it.
struct CoachingEpisodeBaseline: Equatable, Sendable {
    let advice: StabilizedAdvice
    let actionID: String
    /// Nil for frame-global actions (horizon/stability). Subject-dependent
    /// actions always freeze a valid identity here.
    let subjectIdentity: SubjectTrackIdentity?
    let frameID: String
    let capturedAt: Date
    let orientation: CameraCoachOrientation
    let lensID: String?
    let captureGeneration: UInt64
    let subjectRegion: NormalizedRect?
}

extension UserMovementActionFamily {
    /// Subject identity is part of the evidence contract only for actions that
    /// measure a subject. Horizon and stability are frame-global and must be
    /// able to proceed without inventing a subject sentinel.
    var requiresSubjectBinding: Bool {
        switch self {
        case .subjectDisplacement, .scaleDistance, .lightExposure, .focus:
            return true
        case .horizonRotation, .stability:
            return false
        }
    }
}

/// One same-frame handoff from the bounded/stabilized pipeline into the
/// episode owner. This is the baseline event: it is the only event that
/// carries the advice which becomes frozen for the episode.
struct CoachingEpisodeObservation: Equatable, Sendable {
    let frame: UserMovementFrame
    let stabilizedAdvice: StabilizedAdvice
    let subjectTrack: SubjectTrackState?
    let lifecycle: SubjectTrackLifecycleContext
    let isStable: Bool

    init?(frame: UserMovementFrame,
          stabilizedAdvice: StabilizedAdvice,
          subjectTrack: SubjectTrackState?,
          lifecycle: SubjectTrackLifecycleContext,
          isStable: Bool) {
        guard stabilizedAdvice.decision == .correct,
              let actionID = stabilizedAdvice.actionID,
              !actionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              stabilizedAdvice.frameID == frame.frameID,
              let actionFamily = UserMovementObserver.actionFamily(for: actionID),
              lifecycle.generation != 0,
              let evidence = frame.evidence,
              evidence.lensGeneration != 0,
              evidence.lensGeneration == lifecycle.generation,
              evidence.orientation == lifecycle.orientation,
              evidence.capturedAt <= evidence.evaluatedAt,
              actionFamily == .stability || (isStable && frame.motionIsStill) else {
            return nil
        }

        if actionFamily.requiresSubjectBinding {
            guard let subjectTrack,
                  Self.isValidSubjectBinding(
                    evidence.subjectBinding,
                    frame: frame,
                    subjectTrack: subjectTrack,
                    generation: evidence.lensGeneration
                  ) else {
                return nil
            }
        } else if let subjectTrack {
            // A frame-global baseline may carry optional subject context, but
            // if it does, that context must still be same-frame and honest.
            guard subjectTrack.phase == .active,
                  subjectTrack.identity.isValid,
                  subjectTrack.identity.generation == evidence.lensGeneration else {
                return nil
            }
            if evidence.subjectBinding != nil {
                guard Self.isValidSubjectBinding(
                    evidence.subjectBinding,
                    frame: frame,
                    subjectTrack: subjectTrack,
                    generation: evidence.lensGeneration
                ) else {
                    return nil
                }
            }
        } else if evidence.subjectBinding != nil {
            // A free binding without a track owner cannot establish identity.
            return nil
        }

        self.frame = frame
        self.stabilizedAdvice = stabilizedAdvice
        self.subjectTrack = subjectTrack
        self.lifecycle = lifecycle
        self.isStable = isStable
    }

    private static func isValidSubjectBinding(
        _ binding: UserMovementSubjectBinding?,
        frame: UserMovementFrame,
        subjectTrack: SubjectTrackState,
        generation: UInt64
    ) -> Bool {
        guard subjectTrack.phase == .active,
              subjectTrack.identity.isValid,
              subjectTrack.identity.generation == generation,
              let binding,
              binding.frameID == frame.frameID,
              binding.identity == subjectTrack.identity,
              binding.identity.generation == generation,
              // SubjectTracker stores the source region (y-up), while the
              // frame stores the explicit coaching-space conversion. Both
              // must agree before identity can enter an episode.
              binding.region == subjectTrack.lastRegion,
              binding.coachingRegion == frame.subjectRegion else {
            return false
        }
        return true
    }

    /// Converts a baseline observation into a fresh frame event. The event
    /// deliberately carries only the current action signal; the baseline
    /// advice itself remains frozen in the coordinator.
    func asFrameEvidence(currentActionID: String? = nil) -> CoachingEpisodeFrameEvidence? {
        CoachingEpisodeFrameEvidence(
            frame: frame,
            subjectTrack: subjectTrack,
            lifecycle: lifecycle,
            isStable: isStable,
            currentActionID: currentActionID
        )
    }
}

/// Fresh same-frame evidence after the baseline. It may report that the
/// recommendation disappeared (`currentActionID == nil`) without replacing the
/// frozen baseline advice. A competing action is explicit and cancels the
/// episode in the coordinator.
struct CoachingEpisodeFrameEvidence: Equatable, Sendable {
    let frame: UserMovementFrame
    let subjectTrack: SubjectTrackState?
    let lifecycle: SubjectTrackLifecycleContext
    let isStable: Bool
    let currentActionID: String?

    init?(frame: UserMovementFrame,
          subjectTrack: SubjectTrackState?,
          lifecycle: SubjectTrackLifecycleContext,
          isStable: Bool,
          currentActionID: String? = nil) {
        let normalizedActionID = currentActionID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedActionID,
           (normalizedActionID.isEmpty || UserMovementObserver.actionFamily(for: normalizedActionID) == nil) {
            return nil
        }
        guard !frame.frameID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              lifecycle.generation != 0,
              let evidence = frame.evidence,
              evidence.lensGeneration == lifecycle.generation,
              evidence.orientation == lifecycle.orientation,
              evidence.capturedAt.timeIntervalSinceReferenceDate.isFinite,
              evidence.evaluatedAt.timeIntervalSinceReferenceDate.isFinite,
              evidence.capturedAt <= evidence.evaluatedAt else {
            return nil
        }

        if let subjectTrack {
            guard subjectTrack.phase == .active,
                  subjectTrack.identity.isValid,
                  subjectTrack.identity.generation == lifecycle.generation else {
                return nil
            }
            if let binding = evidence.subjectBinding {
                guard binding.frameID == frame.frameID,
                      binding.identity == subjectTrack.identity,
                      binding.identity.generation == evidence.lensGeneration,
                      binding.region == subjectTrack.lastRegion,
                      binding.coachingRegion == frame.subjectRegion else {
                    return nil
                }
            }
        } else if evidence.subjectBinding != nil {
            return nil
        }

        if let normalizedActionID,
           let actionFamily = UserMovementObserver.actionFamily(for: normalizedActionID),
           actionFamily.requiresSubjectBinding {
            guard let subjectTrack,
                  let binding = evidence.subjectBinding,
                  binding.frameID == frame.frameID,
                  binding.identity == subjectTrack.identity,
                  binding.region == subjectTrack.lastRegion,
                  binding.coachingRegion == frame.subjectRegion else {
                return nil
            }
        }

        self.frame = frame
        self.subjectTrack = subjectTrack
        self.lifecycle = lifecycle
        self.isStable = isStable
        self.currentActionID = normalizedActionID
    }
}

/// Typed boundary between AnalysisPipeline and CameraViewModel. Baseline is
/// the only advice-bearing event; frame events carry fresh evidence and an
/// optional current action signal; cancel is explicit instead of nil-as-stale.
enum CoachingEpisodeStreamEvent: Equatable, Sendable {
    case baseline(CoachingEpisodeObservation)
    case frame(CoachingEpisodeFrameEvidence)
    case cancel(CoachingEpisodeCancellationReason)
}

/// Observable state returned after every coordinator operation.
struct CoachingEpisodeState: Equatable, Sendable {
    let phase: CoachingEpisodePhase
    let token: CoachingEpisodeToken?
    let baseline: CoachingEpisodeBaseline?
    let movementFrames: Int
    let stableAfterFrames: Int
    let lastFrameID: String?
    let cancellationReason: CoachingEpisodeCancellationReason?

    static let idle = CoachingEpisodeState(
        phase: .idle,
        token: nil,
        baseline: nil,
        movementFrames: 0,
        stableAfterFrames: 0,
        lastFrameID: nil,
        cancellationReason: nil
    )
}

/// Production owner for one movement-and-after-frame episode. No clock is
/// captured and no timer can complete an episode: the only progress source is
/// immutable, fresh frame evidence supplied by `UserMovementTracker`.
struct CoachingEpisodeCoordinator {
    let configuration: CoachingEpisodeConfiguration

    private(set) var state: CoachingEpisodeState = .idle

    private var movementTracker: UserMovementTracker?
    private var lifecycleGuard: SubjectTrackLifecycleGuard?
    private var lastObservation: CoachingEpisodeFrameEvidence?
    private var seenFrameIDs = Set<String>()

    init(configuration: CoachingEpisodeConfiguration = .init()) {
        self.configuration = configuration
    }

    var phase: CoachingEpisodePhase { state.phase }
    var isReadyForVerification: Bool { state.phase == .readyForVerification }
    var episodeToken: CoachingEpisodeToken? { state.token }

    /// Starts exactly one episode from one accepted, stabilized same-frame
    /// observation. Calling this while active/ready is a no-op; callers must
    /// explicitly reset before retrying so a fresh token is unavoidable.
    @discardableResult
    mutating func begin(with observation: CoachingEpisodeObservation) -> CoachingEpisodeState {
        guard state.phase == .idle else { return state }

        guard let capturedAt = observation.frame.evidence?.capturedAt else {
            return state
        }
        return beginValidated(
            observation: observation,
            capturedAt: capturedAt,
            subjectRegion: observation.frame.subjectRegion
        )
    }

    private mutating func beginValidated(
        observation: CoachingEpisodeObservation,
        capturedAt: Date,
        subjectRegion: NormalizedRect?
    ) -> CoachingEpisodeState {
        guard let actionID = observation.stabilizedAdvice.actionID,
              let actionFamily = UserMovementObserver.actionFamily(for: actionID),
              observation.lifecycle.routeActive,
              !observation.lifecycle.isAppBackgrounded,
              actionFamily == .stability || (observation.isStable && observation.frame.motionIsStill) else {
            return state
        }

        let guardState = SubjectTrackLifecycleGuard(context: observation.lifecycle)
        var tracker = UserMovementTracker(
            actionID: actionID,
            requiredRelevantFrames: configuration.requiredMovementFrames
        )
        // Seed the tracker with the exact baseline. The first observation is
        // intentionally uncertain; only a later relevant frame may advance.
        _ = tracker.observe(
            observation.frame,
            asOf: observation.frame.evidence?.evaluatedAt
        )

        movementTracker = tracker
        lifecycleGuard = guardState
        guard let initialFrame = observation.asFrameEvidence(currentActionID: actionID) else {
            return state
        }
        lastObservation = initialFrame
        seenFrameIDs = [observation.frame.frameID]
        let baseline = CoachingEpisodeBaseline(
            advice: observation.stabilizedAdvice,
            actionID: actionID,
            subjectIdentity: actionFamily.requiresSubjectBinding
                ? observation.subjectTrack?.identity
                : nil,
            frameID: observation.frame.frameID,
            capturedAt: capturedAt,
            orientation: observation.lifecycle.orientation,
            lensID: observation.lifecycle.lensID,
            captureGeneration: observation.lifecycle.generation,
            subjectRegion: actionFamily.requiresSubjectBinding ? subjectRegion : nil
        )
        state = CoachingEpisodeState(
            phase: .awaitingMovement,
            token: guardState.episode,
            baseline: baseline,
            movementFrames: 0,
            stableAfterFrames: 0,
            lastFrameID: observation.frame.frameID,
            cancellationReason: nil
        )
        return state
    }

    /// Consumes the typed pipeline stream. A new baseline is the explicit
    /// terminal-boundary signal that permits one retry after cancellation or
    /// expiry; late frame events never reopen a terminal episode.
    @discardableResult
    mutating func consume(_ event: CoachingEpisodeStreamEvent) -> CoachingEpisodeState {
        switch event {
        case .baseline(let observation):
            if state.phase == .cancelled || state.phase == .expired {
                resetForRetry()
            }
            return begin(with: observation)
        case .frame(let frameEvidence):
            return observe(frameEvidence)
        case .cancel(let reason):
            return cancel(reason: reason)
        }
    }

    /// Alias matching the domain vocabulary used by the state machine.
    @discardableResult
    mutating func start(with observation: CoachingEpisodeObservation) -> CoachingEpisodeState {
        begin(with: observation)
    }

    /// Consumes one fresh frame from the same action/subject/lifecycle. Every
    /// mismatch fails closed; duplicate frames are ignored without advancing.
    @discardableResult
    mutating func observe(_ observation: CoachingEpisodeObservation) -> CoachingEpisodeState {
        guard let frameEvidence = observation.asFrameEvidence(
            currentActionID: observation.stabilizedAdvice.actionID
        ) else {
            return cancel(reason: .invalidObservation)
        }
        return observe(frameEvidence)
    }

    /// Consumes fresh evidence without replacing the frozen baseline advice.
    /// `currentActionID == nil` means the recommendation disappeared; it is
    /// not itself a stale-evidence cancellation.
    @discardableResult
    mutating func observe(_ frameEvidence: CoachingEpisodeFrameEvidence) -> CoachingEpisodeState {
        guard state.phase == .awaitingMovement || state.phase == .collectingStableAfterFrames else {
            return state
        }
        guard let baseline = state.baseline,
              let previous = lastObservation,
              var tracker = movementTracker else {
            return cancel(reason: .invalidObservation)
        }

        let frameID = frameEvidence.frame.frameID
        guard !seenFrameIDs.contains(frameID) else {
            // A retransmitted callback is not evidence of progress and must
            // not mutate the streak or stable-after count.
            return state
        }

        let capturedAt = frameEvidence.frame.evidence?.capturedAt
        guard let capturedAt, capturedAt.timeIntervalSinceReferenceDate.isFinite else {
            return cancel(reason: .invalidObservation)
        }
        if capturedAt.timeIntervalSince(baseline.capturedAt) >= configuration.maxDuration {
            return expire(at: capturedAt)
        }
        guard capturedAt > previous.frame.evidence!.capturedAt else {
            return cancel(reason: .outOfOrder)
        }

        if let currentActionID = frameEvidence.currentActionID,
           currentActionID != baseline.actionID {
            return cancel(reason: .actionChanged)
        }
        if let invalidation = lifecycleGuard?.validate(
            frameEvidence.lifecycle,
            frameID: frameID
        ) {
            return cancel(reason: Self.reason(for: invalidation.cause))
        }

        guard frameEvidence.lifecycle.generation == baseline.captureGeneration,
              frameEvidence.lifecycle.orientation == baseline.orientation,
              frameEvidence.lifecycle.lensID == baseline.lensID,
              frameEvidence.lifecycle.routeActive,
              !frameEvidence.lifecycle.isAppBackgrounded else {
            return cancel(reason: .invalidObservation)
        }

        let actionFamily = UserMovementObserver.actionFamily(for: baseline.actionID)
        if actionFamily?.requiresSubjectBinding == true {
            guard let baselineIdentity = baseline.subjectIdentity,
                  let subjectTrack = frameEvidence.subjectTrack,
                  subjectTrack.phase == .active,
                  subjectTrack.identity == baselineIdentity else {
                return cancel(reason: .subjectChanged)
            }
        }

        guard let evidence = frameEvidence.frame.evidence,
              evidence.lensGeneration == baseline.captureGeneration,
              evidence.orientation == baseline.orientation,
              evidence.capturedAt <= evidence.evaluatedAt else {
            return cancel(reason: .staleEvidence)
        }
        if let baselineIdentity = baseline.subjectIdentity {
            guard frameEvidence.subjectTrack?.identity == baselineIdentity else {
                return cancel(reason: .subjectChanged)
            }
            guard evidence.subjectBinding?.identity == baselineIdentity,
                  evidence.subjectBinding?.source == previous.frame.evidence?.subjectBinding?.source else {
                return cancel(reason: .subjectChanged)
            }
        }

        seenFrameIDs.insert(frameID)
        lastObservation = frameEvidence

        switch state.phase {
        case .awaitingMovement:
            let verdict = tracker.observe(frameEvidence.frame, asOf: evidence.evaluatedAt)
            movementTracker = tracker
            switch verdict {
            case .relevant:
                let reached = tracker.movementGoalReached
                state = CoachingEpisodeState(
                    phase: reached ? .collectingStableAfterFrames : .awaitingMovement,
                    token: state.token,
                    baseline: baseline,
                    movementFrames: tracker.consecutiveRelevant,
                    stableAfterFrames: 0,
                    lastFrameID: frameID,
                    cancellationReason: nil
                )
            case .noOp, .opposite:
                state = CoachingEpisodeState(
                    phase: .awaitingMovement,
                    token: state.token,
                    baseline: baseline,
                    movementFrames: 0,
                    stableAfterFrames: 0,
                    lastFrameID: frameID,
                    cancellationReason: nil
                )
            case .uncertain(let reason):
                if Self.isStaleEvidenceReason(reason) {
                    return cancel(reason: .staleEvidence)
                }
                state = CoachingEpisodeState(
                    phase: .awaitingMovement,
                    token: state.token,
                    baseline: baseline,
                    movementFrames: 0,
                    stableAfterFrames: 0,
                    lastFrameID: frameID,
                    cancellationReason: nil
                )
            }

        case .collectingStableAfterFrames:
            // Once movement has been observed, stop counting movement streaks.
            // A valid after-frame is fresh, still, and no longer changing the
            // action's measured feature. A relevant/opposite frame restarts
            // the stable-after dwell but cannot fake completion.
            let evidenceVerdict = UserMovementObserver.observe(
                previous: previous.frame,
                current: frameEvidence.frame,
                actionID: baseline.actionID,
                asOf: evidence.evaluatedAt
            )
            let isFreshStableAfterFrame: Bool
            if case .noOp = evidenceVerdict {
                isFreshStableAfterFrame = frameEvidence.isStable && frameEvidence.frame.motionIsStill
            } else if case .uncertain(let reason) = evidenceVerdict,
                      Self.isStaleEvidenceReason(reason) {
                return cancel(reason: .staleEvidence)
            } else {
                isFreshStableAfterFrame = false
            }
            let nextStableCount = isFreshStableAfterFrame
                ? state.stableAfterFrames + 1
                : 0
            state = CoachingEpisodeState(
                phase: nextStableCount >= configuration.requiredStableAfterFrames
                    ? .readyForVerification
                    : .collectingStableAfterFrames,
                token: state.token,
                baseline: baseline,
                movementFrames: state.movementFrames,
                stableAfterFrames: nextStableCount,
                lastFrameID: frameID,
                cancellationReason: nil
            )

        case .idle, .readyForVerification, .cancelled, .expired:
            break
        }

        return state
    }

    /// Cancels an active episode. Cancellation is terminal until an explicit
    /// `resetForRetry`, which prevents stale frames from reopening it.
    @discardableResult
    mutating func cancel(reason: CoachingEpisodeCancellationReason) -> CoachingEpisodeState {
        guard state.phase == .awaitingMovement || state.phase == .collectingStableAfterFrames else {
            return state
        }
        state = CoachingEpisodeState(
            phase: .cancelled,
            token: state.token,
            baseline: state.baseline,
            movementFrames: state.movementFrames,
            stableAfterFrames: state.stableAfterFrames,
            lastFrameID: state.lastFrameID,
            cancellationReason: reason
        )
        return state
    }

    /// Expires an active episode using an explicit caller-supplied time. Time
    /// alone can only cancel; it can never produce `readyForVerification`.
    @discardableResult
    mutating func expire(at date: Date) -> CoachingEpisodeState {
        guard state.phase == .awaitingMovement || state.phase == .collectingStableAfterFrames,
              date.timeIntervalSinceReferenceDate.isFinite,
              let baseline = state.baseline,
              date.timeIntervalSince(baseline.capturedAt) >= configuration.maxDuration else {
            return state
        }
        state = CoachingEpisodeState(
            phase: .expired,
            token: state.token,
            baseline: state.baseline,
            movementFrames: state.movementFrames,
            stableAfterFrames: state.stableAfterFrames,
            lastFrameID: state.lastFrameID,
            cancellationReason: .expired
        )
        return state
    }

    /// Drops all episode-owned samples and requires a new baseline/token.
    mutating func resetForRetry() {
        state = .idle
        movementTracker = nil
        lifecycleGuard = nil
        lastObservation = nil
        seenFrameIDs.removeAll(keepingCapacity: true)
    }

    private static func reason(for cause: SubjectTrackInvalidationCause) -> CoachingEpisodeCancellationReason {
        switch cause {
        case .lensChange: return .lensChange
        case .orientationChange: return .orientationChange
        case .routeExit: return .routeExit
        case .cameraGenerationChange: return .cameraGenerationChange
        case .background: return .background
        case .sceneCut: return .sceneCut
        }
    }

    private static func isStaleEvidenceReason(_ reason: String) -> Bool {
        switch reason {
        case "evidence_missing", "feature_missing", "feature_confidence",
             "stale_evidence", "uncalibrated", "evidence_time",
             "orientation_changed", "lens_generation":
            return true
        default:
            return false
        }
    }
}
