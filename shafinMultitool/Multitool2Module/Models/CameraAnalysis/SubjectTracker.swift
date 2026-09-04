//
//  SubjectTracker.swift
//  shafinMultitool
//
//  M2-010 SubjectTrackingOwner: temporal tracking for the selected/auto
//  subject. Pure and deterministic: the pipeline feeds per-frame candidate
//  lists; the tracker keeps the SubjectTrackIdentity stable through moderate
//  motion and partial occlusion, reconciles after loss without silent
//  identity swaps, exposes an explicit loss phase (advice must invalidate),
//  and flags when periodic full redetection is due.
//

import Foundation

enum SubjectTrackPhase: String, Codable, Equatable, Sendable {
    case active
    case lost
}

struct SubjectTrackState: Codable, Equatable, Sendable {
    let identity: SubjectTrackIdentity
    let phase: SubjectTrackPhase
    let lastRegion: NormalizedRect?
    let lastSeenFrameID: String
    /// Set when the track entered `.lost` (frame ID of the loss).
    let lostSinceFrameID: String?
    /// Consecutive frames without a re-association.
    let missedFrames: Int
    /// How many times a lost track was reconciled to the same identity.
    let reconciliations: Int
    /// True when the pipeline should run a full redetection pass now.
    let redetectionDue: Bool

    var isLost: Bool { phase == .lost }
}

final class SubjectTracker {

    /// Minimum IoU between the tracked region and a candidate to treat them
    /// as the same subject.
    var iouMatchThreshold: Double = 0.3
    /// A matched candidate whose center jumped farther than this from the
    /// tracked center is an identity-swap risk: it is not silently accepted.
    var centerJumpThreshold: Double = 0.4
    /// Consecutive misses after which the track is explicitly lost.
    var lossFrameLimit: Int = 10
    /// Periodic full-redetection cadence (frames since the last association).
    var redetectionIntervalFrames: Int = 15

    private(set) var state: SubjectTrackState?
    private(set) var framesSinceLastRedetection = 0

    var current: SubjectTrackState? { state }

    /// Starts tracking from a resolved subject (M2-008 auto or M2-009 tap).
    func begin(resolution: SubjectResolutionV2, frameID: String, generation: UInt64) {
        guard let selected = resolution.selected, let region = selected.region else {
            // Unknown resolutions carry no trackable subject.
            state = nil
            return
        }
        let identity = SubjectTrackIdentity(
            trackID: "track-\(selected.id)-\(frameID)",
            firstSeenFrameID: frameID,
            generation: generation
        )
        framesSinceLastRedetection = 0
        state = SubjectTrackState(
            identity: identity,
            phase: .active,
            lastRegion: region,
            lastSeenFrameID: frameID,
            lostSinceFrameID: nil,
            missedFrames: 0,
            reconciliations: 0,
            redetectionDue: false
        )
    }

    /// Feeds one frame of candidates; returns the updated state.
    @discardableResult
    func observe(frameID: String, candidates: [SubjectCandidate]) -> SubjectTrackState? {
        guard var current = state else { return nil }
        // The cadence counts frames observed since the last association; the
        // flag is evaluated after the increment so frame N (interval N) is due.
        framesSinceLastRedetection += 1
        let redetectionDue = framesSinceLastRedetection >= redetectionIntervalFrames

        let missLimit = lossFrameLimit
        if current.isLost {
            // Reconciliation: a candidate consistent with the remembered
            // region re-activates the SAME identity. A distant candidate is a
            // new subject and must go through the resolver — no silent swap.
            guard let candidate = bestMatch(for: current, candidates: candidates),
                  let region = candidate.region else {
                current = SubjectTrackState(
                    identity: current.identity,
                    phase: .lost,
                    lastRegion: current.lastRegion,
                    lastSeenFrameID: current.lastSeenFrameID,
                    lostSinceFrameID: current.lostSinceFrameID ?? frameID,
                    missedFrames: current.missedFrames + 1,
                    reconciliations: current.reconciliations,
                    redetectionDue: redetectionDue
                )
                state = current
                return current
            }
            current = SubjectTrackState(
                identity: current.identity,
                phase: .active,
                lastRegion: region,
                lastSeenFrameID: frameID,
                lostSinceFrameID: nil,
                missedFrames: 0,
                reconciliations: current.reconciliations + 1,
                redetectionDue: redetectionDue
            )
            state = current
            return current
        }

        if let candidate = bestMatch(for: current, candidates: candidates),
           let region = candidate.region,
           !isIdentitySwap(current: current, candidateRegion: region) {
            current = SubjectTrackState(
                identity: current.identity,
                phase: .active,
                lastRegion: region,
                lastSeenFrameID: frameID,
                lostSinceFrameID: nil,
                missedFrames: 0,
                reconciliations: current.reconciliations,
                redetectionDue: redetectionDue
            )
            state = current
            return current
        }

        let missed = current.missedFrames + 1
        let lost = missed >= missLimit
        current = SubjectTrackState(
            identity: current.identity,
            phase: lost ? .lost : current.phase,
            lastRegion: current.lastRegion,
            lastSeenFrameID: current.lastSeenFrameID,
            lostSinceFrameID: lost ? frameID : current.lostSinceFrameID,
            missedFrames: missed,
            reconciliations: current.reconciliations,
            redetectionDue: redetectionDue
        )
        state = current
        return current
    }

    /// Explicit loss (route exit, lens change, declared occlusion): advice
    /// consumers must invalidate immediately.
    func markLost(frameID: String) {
        guard var current = state, !current.isLost else { return }
        current = SubjectTrackState(
            identity: current.identity,
            phase: .lost,
            lastRegion: current.lastRegion,
            lastSeenFrameID: current.lastSeenFrameID,
            lostSinceFrameID: frameID,
            missedFrames: current.missedFrames,
            reconciliations: current.reconciliations,
            redetectionDue: current.redetectionDue
        )
        state = current
    }

    /// The pipeline calls this after it performed the flagged full
    /// redetection pass; the cadence restarts from zero.
    func noteRedetectionPerformed() {
        framesSinceLastRedetection = 0
        guard let current = state, current.redetectionDue else { return }
        state = SubjectTrackState(
            identity: current.identity,
            phase: current.phase,
            lastRegion: current.lastRegion,
            lastSeenFrameID: current.lastSeenFrameID,
            lostSinceFrameID: current.lostSinceFrameID,
            missedFrames: current.missedFrames,
            reconciliations: current.reconciliations,
            redetectionDue: false
        )
    }

    /// Clears tracking (new resolution begins a new identity).
    func reset() {
        state = nil
        framesSinceLastRedetection = 0
    }

    // MARK: - Matching

    private func bestMatch(
        for track: SubjectTrackState,
        candidates: [SubjectCandidate]
    ) -> SubjectCandidate? {
        guard let trackedRegion = track.lastRegion else { return nil }
        var best: (candidate: SubjectCandidate, iou: Double)?
        for candidate in candidates {
            guard let region = candidate.region else { continue }
            let iou = Self.intersectionOverUnion(trackedRegion, region)
            if iou >= iouMatchThreshold {
                if best == nil || iou > best!.iou {
                    best = (candidate, iou)
                }
            }
        }
        return best?.candidate
    }

    private func isIdentitySwap(current: SubjectTrackState, candidateRegion: NormalizedRect) -> Bool {
        guard let tracked = current.lastRegion else { return false }
        let trackedCenterX = tracked.x + tracked.width / 2
        let trackedCenterY = tracked.y + tracked.height / 2
        let candidateCenterX = candidateRegion.x + candidateRegion.width / 2
        let candidateCenterY = candidateRegion.y + candidateRegion.height / 2
        let dx = candidateCenterX - trackedCenterX
        let dy = candidateCenterY - trackedCenterY
        return (dx * dx + dy * dy).squareRoot() > centerJumpThreshold
    }

    static func intersectionOverUnion(_ a: NormalizedRect, _ b: NormalizedRect) -> Double {
        let interX1 = max(a.x, b.x)
        let interY1 = max(a.y, b.y)
        let interX2 = min(a.x + a.width, b.x + b.width)
        let interY2 = min(a.y + a.height, b.y + b.height)
        let interW = max(0, interX2 - interX1)
        let interH = max(0, interY2 - interY1)
        let intersection = interW * interH
        let union = a.width * a.height + b.width * b.height - intersection
        guard union > 0 else { return 0 }
        return intersection / union
    }
}

// MARK: - M2-011 Track lifecycle invalidation (SubjectTrackingOwner)

/// The invalidating changes: no advice or verifier result may survive them.
enum SubjectTrackInvalidationCause: String, Codable, CaseIterable, Sendable {
    case lensChange = "lens_change"
    case orientationChange = "orientation_change"
    case routeExit = "route_exit"
    case cameraGenerationChange = "camera_generation_change"
    case background = "background"
    case sceneCut = "scene_cut"
}

struct SubjectTrackInvalidation: Equatable, Sendable {
    let cause: SubjectTrackInvalidationCause
    let frameID: String
    /// The track identity that was invalidated (nil when no track was active).
    let invalidatedTrackID: String?
}

/// Lifecycle guard: compares the current capture context against the context
/// the track/episode was built in. The first detected change is returned as
/// an invalidation; callers must drop tracker state, advice and verifier
/// results and treat the next frames as a new episode (new episode token).
struct SubjectTrackLifecycleContext: Equatable, Sendable {
    let generation: UInt64
    let orientation: CameraCoachOrientation
    let lensID: String?
    let routeActive: Bool
    let isAppBackgrounded: Bool
    /// Deterministic scene signature (e.g. downsampled-luma hash). A material
    /// change flips the string; unchanged scenes keep it stable.
    let sceneSignature: String?

    static func initial(generation: UInt64,
                        orientation: CameraCoachOrientation,
                        lensID: String?) -> SubjectTrackLifecycleContext {
        SubjectTrackLifecycleContext(
            generation: generation,
            orientation: orientation,
            lensID: lensID,
            routeActive: true,
            isAppBackgrounded: false,
            sceneSignature: nil
        )
    }
}

/// Immutable episode token: consumers (advice, verifier) hold the token their
/// result was produced under; a mismatch with the guard's current token means
/// the result is stale and must be discarded.
struct CoachingEpisodeToken: Equatable, Sendable {
    let rawValue: UUID
    let generation: UInt64
}

struct SubjectTrackLifecycleGuard {
    private(set) var context: SubjectTrackLifecycleContext
    private(set) var episode: CoachingEpisodeToken

    init(context: SubjectTrackLifecycleContext) {
        self.context = context
        self.episode = CoachingEpisodeToken(rawValue: UUID(), generation: context.generation)
    }

    /// Validates the new context. Returns the invalidation (with the cause)
    /// and rotates the episode token; nil means no invalidating change.
    mutating func validate(
        _ newContext: SubjectTrackLifecycleContext,
        frameID: String
    ) -> SubjectTrackInvalidation? {
        let cause: SubjectTrackInvalidationCause? = {
            if newContext.generation != context.generation { return .cameraGenerationChange }
            if newContext.lensID != context.lensID { return .lensChange }
            if newContext.orientation != context.orientation { return .orientationChange }
            if context.routeActive, !newContext.routeActive { return .routeExit }
            if newContext.isAppBackgrounded, !context.isAppBackgrounded { return .background }
            if let signature = newContext.sceneSignature,
               let previous = context.sceneSignature,
               signature != previous { return .sceneCut }
            return nil
        }()

        context = newContext
        guard let cause else { return nil }
        episode = CoachingEpisodeToken(rawValue: UUID(), generation: newContext.generation)
        return SubjectTrackInvalidation(cause: cause, frameID: frameID, invalidatedTrackID: nil)
    }

    /// True when a result produced under `token` is stale for the current
    /// episode (fail closed: nil token is always stale).
    func isStale(_ token: CoachingEpisodeToken?) -> Bool {
        guard let token else { return true }
        return token != episode
    }
}

extension SubjectTracker {
    /// Applies an invalidation: an ACTIVE track is explicitly lost with the
    /// cause's frame and its identity is returned for episode bookkeeping.
    /// Already-lost (or absent) tracks report nil — there is nothing new to
    /// invalidate.
    @discardableResult
    func invalidate(cause: SubjectTrackInvalidationCause, frameID: String) -> String? {
        guard let state, state.phase == .active else { return nil }
        let invalidatedTrackID = state.identity.trackID
        markLost(frameID: frameID)
        return invalidatedTrackID
    }
}
