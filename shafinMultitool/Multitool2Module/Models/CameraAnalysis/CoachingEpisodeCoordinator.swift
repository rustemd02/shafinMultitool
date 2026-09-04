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
    let subjectIdentity: SubjectTrackIdentity
    let frameID: String
    let capturedAt: Date
    let orientation: CameraCoachOrientation
    let lensID: String?
    let captureGeneration: UInt64
    let subjectRegion: NormalizedRect
}

/// One same-frame handoff from the bounded/stabilized pipeline into the
/// episode owner. The initializer is failable so malformed or mixed-provenance
/// data cannot enter the state machine.
struct CoachingEpisodeObservation: Equatable, Sendable {
    let frame: UserMovementFrame
    let stabilizedAdvice: StabilizedAdvice
    let subjectTrack: SubjectTrackState
    let lifecycle: SubjectTrackLifecycleContext
    let isStable: Bool

    init?(frame: UserMovementFrame,
          stabilizedAdvice: StabilizedAdvice,
          subjectTrack: SubjectTrackState,
          lifecycle: SubjectTrackLifecycleContext,
          isStable: Bool) {
        guard stabilizedAdvice.decision == .correct,
              let actionID = stabilizedAdvice.actionID,
              !actionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              stabilizedAdvice.frameID == frame.frameID,
              let actionFamily = UserMovementObserver.actionFamily(for: actionID),
              subjectTrack.phase == .active,
              subjectTrack.identity.isValid,
              lifecycle.generation != 0,
              lifecycle.generation == subjectTrack.identity.generation,
              let evidence = frame.evidence,
              evidence.lensGeneration != 0,
              evidence.lensGeneration == lifecycle.generation,
              evidence.orientation == lifecycle.orientation,
              let binding = evidence.subjectBinding,
              binding.frameID == frame.frameID,
              binding.identity == subjectTrack.identity,
              binding.identity.generation == evidence.lensGeneration,
              // SubjectTracker stores the source Vision region (y-up), while
              // the frame stores the explicit coaching-space conversion. The
              // binding must agree with both; an identity with unrelated
              // geometry is not a same-subject observation.
              binding.region == subjectTrack.lastRegion,
              binding.coachingRegion == frame.subjectRegion,
              evidence.capturedAt <= evidence.evaluatedAt,
              // A stabilization action is intentionally baselined while the
              // camera is unstable; every other action requires a still,
              // stabilized baseline. The after-frame gate below remains
              // strict for both paths.
              actionFamily == .stability || (isStable && frame.motionIsStill) else {
            return nil
        }

        self.frame = frame
        self.stabilizedAdvice = stabilizedAdvice
        self.subjectTrack = subjectTrack
        self.lifecycle = lifecycle
        self.isStable = isStable
    }
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
    private var lastObservation: CoachingEpisodeObservation?
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

        let baseline = CoachingEpisodeBaseline(
            advice: observation.stabilizedAdvice,
            actionID: observation.stabilizedAdvice.actionID!,
            subjectIdentity: observation.subjectTrack.identity,
            frameID: observation.frame.frameID,
            capturedAt: observation.frame.evidence!.capturedAt,
            orientation: observation.lifecycle.orientation,
            lensID: observation.lifecycle.lensID,
            captureGeneration: observation.lifecycle.generation,
            subjectRegion: observation.frame.subjectRegion!
        )
        let actionFamily = UserMovementObserver.actionFamily(for: baseline.actionID)
        guard actionFamily == .stability
            || (observation.isStable && observation.frame.motionIsStill),
              observation.lifecycle.routeActive,
              !observation.lifecycle.isAppBackgrounded else {
            return state
        }
        let guardState = SubjectTrackLifecycleGuard(context: observation.lifecycle)
        var tracker = UserMovementTracker(
            actionID: baseline.actionID,
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
        lastObservation = observation
        seenFrameIDs = [observation.frame.frameID]
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

    /// Alias matching the domain vocabulary used by the state machine.
    @discardableResult
    mutating func start(with observation: CoachingEpisodeObservation) -> CoachingEpisodeState {
        begin(with: observation)
    }

    /// Consumes one fresh frame from the same action/subject/lifecycle. Every
    /// mismatch fails closed; duplicate frames are ignored without advancing.
    @discardableResult
    mutating func observe(_ observation: CoachingEpisodeObservation) -> CoachingEpisodeState {
        guard state.phase == .awaitingMovement || state.phase == .collectingStableAfterFrames else {
            return state
        }
        guard let baseline = state.baseline,
              let previous = lastObservation,
              var tracker = movementTracker else {
            return cancel(reason: .invalidObservation)
        }

        let frameID = observation.frame.frameID
        guard !seenFrameIDs.contains(frameID) else {
            // A retransmitted callback is not evidence of progress and must
            // not mutate the streak or stable-after count.
            return state
        }

        let capturedAt = observation.frame.evidence?.capturedAt
        guard let capturedAt, capturedAt.timeIntervalSinceReferenceDate.isFinite else {
            return cancel(reason: .invalidObservation)
        }
        if capturedAt.timeIntervalSince(baseline.capturedAt) >= configuration.maxDuration {
            return expire(at: capturedAt)
        }
        guard capturedAt > previous.frame.evidence!.capturedAt else {
            return cancel(reason: .outOfOrder)
        }

        guard observation.stabilizedAdvice.decision == .correct,
              observation.stabilizedAdvice.actionID == baseline.actionID else {
            return cancel(reason: .actionChanged)
        }
        if let invalidation = lifecycleGuard?.validate(
            observation.lifecycle,
            frameID: frameID
        ) {
            return cancel(reason: Self.reason(for: invalidation.cause))
        }

        guard observation.subjectTrack.phase == .active,
              observation.subjectTrack.identity == baseline.subjectIdentity else {
            return cancel(reason: .subjectChanged)
        }
        guard observation.lifecycle.generation == baseline.captureGeneration,
              observation.lifecycle.orientation == baseline.orientation,
              observation.lifecycle.lensID == baseline.lensID,
              observation.lifecycle.routeActive,
              !observation.lifecycle.isAppBackgrounded else {
            return cancel(reason: .invalidObservation)
        }

        guard let evidence = observation.frame.evidence,
              evidence.lensGeneration == baseline.captureGeneration,
              evidence.orientation == baseline.orientation,
              evidence.subjectBinding?.identity == baseline.subjectIdentity,
              evidence.subjectBinding?.source == previous.frame.evidence?.subjectBinding?.source else {
            return cancel(reason: .subjectChanged)
        }

        seenFrameIDs.insert(frameID)
        lastObservation = observation

        switch state.phase {
        case .awaitingMovement:
            let verdict = tracker.observe(observation.frame, asOf: evidence.evaluatedAt)
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
            case .noOp, .opposite, .uncertain:
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
                current: observation.frame,
                actionID: baseline.actionID,
                asOf: evidence.evaluatedAt
            )
            let isFreshStableAfterFrame: Bool
            if case .noOp = evidenceVerdict {
                isFreshStableAfterFrame = observation.isStable && observation.frame.motionIsStill
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
}
