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

/// One locally tracked detector object. lastObserved* fields describe the
/// last accepted detector observation; frameID/sampleSequence describe the
/// update that produced this state, including a loss/invalidation update.
struct ObjectTrackState: Codable, Equatable, Sendable {
    let identity: SubjectTrackIdentity
    let label: String?
    let lastObservedRegion: NormalizedRect?
    let lastObservedFrameID: String?
    let lastObservedSampleSequence: UInt64?
    let phase: SubjectTrackPhase
    let frameID: String
    let sampleSequence: UInt64

    var region: NormalizedRect? {
        phase == .active ? lastObservedRegion : nil
    }

    var isActive: Bool { phase == .active }
    var isLost: Bool { phase == .lost }
}

/// A frozen selection on one tracked object (C03.2/C03.4). Identity is the
/// session `trackID`; `displayLabel` is presentation-only and never proves
/// identity. Resolution never silently follows a different object: when the
/// bound track is lost, absent, or belongs to a retired generation the binding
/// fails closed to `.unresolved` instead of re-pointing at another same-label
/// object.
struct ObjectTargetBinding: Equatable, Sendable {
    let trackID: String
    /// Presentation label of the selected object. Not an identity key.
    let displayLabel: String?
    let generation: UInt64
    let boundAtFrameID: String

    enum UnresolvedReason: String, Codable, CaseIterable, Equatable, Sendable {
        /// No live object carries the bound trackID.
        case trackUnknown = "track_unknown"
        /// The bound track exists but is currently lost.
        case trackLost = "track_lost"
        /// The capture generation changed; the old identity is retired.
        case generationChanged = "generation_changed"
    }

    enum Resolution: Equatable, Sendable {
        case bound(region: NormalizedRect)
        case unresolved(reason: UnresolvedReason)
    }

    /// Resolves the binding against the tracker's current object set. Only the
    /// exact bound trackID can resolve; a same-label sibling is never adopted.
    func resolve(in objects: [ObjectTrackState], generation: UInt64) -> Resolution {
        guard generation == self.generation else {
            return .unresolved(reason: .generationChanged)
        }
        guard let object = objects.first(where: { $0.identity.trackID == trackID }) else {
            return .unresolved(reason: .trackUnknown)
        }
        guard object.phase == .active, let region = object.lastObservedRegion else {
            return .unresolved(reason: .trackLost)
        }
        return .bound(region: region)
    }
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

    /// Bounded local object tracking is intentionally owned by this tracker,
    /// while remaining independent from the selected primary subject.
    var maxObjectCount: Int = 4

    private(set) var currentObjects: [ObjectTrackState] = []

    private var objectGeneration: UInt64?
    private var objectSampleSequence: UInt64?
    private var nextObjectOrdinal: UInt64 = 0

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

    /// Updates the bounded local object set. Detector IDs are frame-local and
    /// deliberately ignored; identities come only from conservative geometry
    /// and label matching.
    @discardableResult
    func updateObjects(
        candidates: [SubjectCandidate],
        frameID: String,
        generation: UInt64,
        sampleSequence: UInt64
    ) -> [ObjectTrackState] {
        if let currentGeneration = objectGeneration {
            guard generation >= currentGeneration else {
                // A retired generation is stale even if its sample sequence is
                // numerically newer. Keep the last accepted object state and
                // its provenance until a newer generation is observed.
                return currentObjects
            }
            guard generation > currentGeneration else {
                // Same generation: the sample-sequence fence below decides
                // whether this observation is new.
                if let previousSequence = objectSampleSequence,
                   sampleSequence <= previousSequence {
                    return currentObjects
                }
                objectSampleSequence = sampleSequence
                return updateObjectsInCurrentGeneration(
                    candidates: candidates,
                    frameID: frameID,
                    generation: generation,
                    sampleSequence: sampleSequence
                )
            }
            currentObjects.removeAll(keepingCapacity: true)
            objectGeneration = generation
            objectSampleSequence = nil
        } else {
            objectGeneration = generation
        }

        if let previousSequence = objectSampleSequence,
           sampleSequence <= previousSequence {
            // Do not stamp an older observation as current. The exposed
            // states retain the provenance of the last accepted sample.
            return currentObjects
        }
        objectSampleSequence = sampleSequence

        return updateObjectsInCurrentGeneration(
            candidates: candidates,
            frameID: frameID,
            generation: generation,
            sampleSequence: sampleSequence
        )
    }

    private func updateObjectsInCurrentGeneration(
        candidates: [SubjectCandidate],
        frameID: String,
        generation: UInt64,
        sampleSequence: UInt64
    ) -> [ObjectTrackState] {

        let validCandidates = uniqueValidObjectCandidates(candidates)
        let activeTracks = currentObjects
            .filter { $0.phase == .active }
            .sorted(by: objectStatePrecedes)
        let lostTracks = currentObjects
            .filter { $0.phase == .lost }
            .sorted(by: objectStatePrecedes)
        let capacity = min(4, max(0, maxObjectCount))

        var nextStates = lostTracks.map {
            lostObjectState($0, frameID: frameID, sampleSequence: sampleSequence)
        }
        if activeTracks.isEmpty {
            for candidateIndex in validCandidates.indices
                where !ambiguousNewCandidate(at: candidateIndex, among: validCandidates) {
                let candidate = validCandidates[candidateIndex]
                let compatibleLost = lostTracks.filter {
                    objectCanMatch($0, candidate: candidate)
                }
                guard compatibleLost.count <= 1 else { continue }
                addFreshObject(
                    candidate,
                    to: &nextStates,
                    capacity: capacity,
                    frameID: frameID,
                    generation: generation,
                    sampleSequence: sampleSequence,
                    replacingLost: compatibleLost
                )
            }
            currentObjects = limitedObjectStates(nextStates, capacity: capacity)
            return currentObjects
        }

        var trackCandidates = Array(repeating: [Int](), count: activeTracks.count)
        var candidateTracks = Array(repeating: [Int](), count: validCandidates.count)
        for (trackIndex, track) in activeTracks.enumerated() {
            for (candidateIndex, candidate) in validCandidates.enumerated()
                where objectCanMatch(track, candidate: candidate) {
                trackCandidates[trackIndex].append(candidateIndex)
                candidateTracks[candidateIndex].append(trackIndex)
            }
        }

        var ambiguousTracks = Set<Int>()
        var ambiguousCandidates = Set<Int>()
        for (trackIndex, matches) in trackCandidates.enumerated() where matches.count > 1 {
            ambiguousTracks.insert(trackIndex)
            ambiguousCandidates.formUnion(matches)
        }
        for (candidateIndex, matches) in candidateTracks.enumerated() where matches.count > 1 {
            ambiguousCandidates.insert(candidateIndex)
        }
        for (candidateIndex, candidate) in validCandidates.enumerated() {
            let compatibleLostCount = lostTracks.reduce(into: 0) { count, lostTrack in
                if objectCanMatch(lostTrack, candidate: candidate) {
                    count += 1
                }
            }
            // A candidate that could explain both an active and a historical
            // lost identity is ambiguous. Do not keep the active match or
            // resurrect the lost identity from geometry alone.
            if candidateTracks[candidateIndex].count + compatibleLostCount > 1 {
                ambiguousCandidates.insert(candidateIndex)
            }
        }
        for firstIndex in validCandidates.indices {
            for secondIndex in validCandidates.indices where secondIndex > firstIndex {
                guard objectCanMatch(
                    validCandidates[firstIndex],
                    candidate: validCandidates[secondIndex]
                ) else { continue }
                ambiguousCandidates.insert(firstIndex)
                ambiguousCandidates.insert(secondIndex)
            }
        }

        var matchedCandidates = Set<Int>()
        for (trackIndex, track) in activeTracks.enumerated() {
            guard !ambiguousTracks.contains(trackIndex),
                  trackCandidates[trackIndex].count == 1,
                  let candidateIndex = trackCandidates[trackIndex].first,
                  !ambiguousCandidates.contains(candidateIndex) else {
                nextStates.append(
                    lostObjectState(track, frameID: frameID, sampleSequence: sampleSequence)
                )
                continue
            }
            let candidate = validCandidates[candidateIndex]
            nextStates.append(
                ObjectTrackState(
                    identity: track.identity,
                    label: candidate.label,
                    lastObservedRegion: candidate.region!,
                    lastObservedFrameID: frameID,
                    lastObservedSampleSequence: sampleSequence,
                    phase: .active,
                    frameID: frameID,
                    sampleSequence: sampleSequence
                )
            )
            matchedCandidates.insert(candidateIndex)
        }

        for candidateIndex in validCandidates.indices
            where !matchedCandidates.contains(candidateIndex)
                && !ambiguousCandidates.contains(candidateIndex) {
            let candidate = validCandidates[candidateIndex]
            let compatibleLost = lostTracks.filter {
                objectCanMatch($0, candidate: candidate)
            }
            // A lost track is never matched back. A single compatible lost
            // state may be replaced by a fresh identity; competing lost
            // states keep this candidate ambiguous and unusable.
            guard compatibleLost.count <= 1 else { continue }
            addFreshObject(
                candidate,
                to: &nextStates,
                capacity: capacity,
                frameID: frameID,
                generation: generation,
                sampleSequence: sampleSequence,
                replacingLost: compatibleLost
            )
        }

        currentObjects = limitedObjectStates(nextStates, capacity: capacity)
        return currentObjects
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
        resetObjects()
    }

    /// Clears only the independently tracked object set. The next accepted
    /// sample starts fresh identities in its generation.
    func resetObjects() {
        currentObjects.removeAll(keepingCapacity: true)
        objectGeneration = nil
        objectSampleSequence = nil
    }

    private func invalidateObjects(frameID: String) {
        let sequence = objectSampleSequence ?? 0
        currentObjects = currentObjects.map {
            lostObjectState($0, frameID: frameID, sampleSequence: sequence)
        }
    }

    // MARK: - Matching

    private func uniqueValidObjectCandidates(
        _ candidates: [SubjectCandidate]
    ) -> [SubjectCandidate] {
        let sorted = candidates
            .filter(isValidObjectCandidate)
            .sorted(by: objectCandidatePrecedes)
        var result: [SubjectCandidate] = []
        var index = 0
        while index < sorted.count {
            guard let region = sorted[index].region else {
                index += 1
                continue
            }
            var end = index + 1
            while end < sorted.count, sorted[end].region == region {
                end += 1
            }
            let group = Array(sorted[index..<end])
            let groupLabel = objectLabelKey(group[0].label)
            if group.dropFirst().allSatisfy({ objectLabelKey($0.label) == groupLabel }),
               let selected = group.sorted(by: objectCandidatePrecedesBest).first {
                result.append(selected)
            }
            index = end
        }
        return result.sorted(by: objectCandidatePrecedes)
    }

    private func isValidObjectCandidate(_ candidate: SubjectCandidate) -> Bool {
        guard candidate.kind == .object,
              candidate.confidence.isFinite,
              candidate.confidence >= 0.55,
              let region = candidate.region else {
            return false
        }
        return region.x.isFinite
            && region.y.isFinite
            && region.width.isFinite
            && region.height.isFinite
            && region.x >= 0
            && region.y >= 0
            && region.width > 0
            && region.height > 0
            && region.x + region.width <= 1
            && region.y + region.height <= 1
    }

    private func objectLabelKey(_ label: String?) -> String? {
        guard let label else { return nil }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    private func objectLabelsCompatible(_ lhs: String?, _ rhs: String?) -> Bool {
        objectLabelKey(lhs) == objectLabelKey(rhs)
    }

    private func objectCandidatePrecedes(
        _ lhs: SubjectCandidate,
        _ rhs: SubjectCandidate
    ) -> Bool {
        guard let left = lhs.region, let right = rhs.region else { return lhs.region != nil }
        if left.x != right.x { return left.x < right.x }
        if left.y != right.y { return left.y < right.y }
        if left.width != right.width { return left.width < right.width }
        if left.height != right.height { return left.height < right.height }
        let leftLabel = objectLabelKey(lhs.label) ?? ""
        let rightLabel = objectLabelKey(rhs.label) ?? ""
        if leftLabel != rightLabel { return leftLabel < rightLabel }
        return lhs.confidence > rhs.confidence
    }

    private func objectCandidatePrecedesBest(
        _ lhs: SubjectCandidate,
        _ rhs: SubjectCandidate
    ) -> Bool {
        if lhs.confidence != rhs.confidence {
            return lhs.confidence > rhs.confidence
        }
        let leftLabel = lhs.label ?? ""
        let rightLabel = rhs.label ?? ""
        return leftLabel < rightLabel
    }

    private func objectStatePrecedes(
        _ lhs: ObjectTrackState,
        _ rhs: ObjectTrackState
    ) -> Bool {
        guard let left = lhs.lastObservedRegion, let right = rhs.lastObservedRegion else {
            if lhs.lastObservedRegion != nil { return true }
            if rhs.lastObservedRegion != nil { return false }
            return lhs.identity.trackID < rhs.identity.trackID
        }
        if left.x != right.x { return left.x < right.x }
        if left.y != right.y { return left.y < right.y }
        if left.width != right.width { return left.width < right.width }
        if left.height != right.height { return left.height < right.height }
        return lhs.identity.trackID < rhs.identity.trackID
    }

    private func objectCanMatch(
        _ track: ObjectTrackState,
        candidate: SubjectCandidate
    ) -> Bool {
        guard objectLabelsCompatible(track.label, candidate.label),
              let trackedRegion = track.lastObservedRegion,
              let region = candidate.region else { return false }
        return objectCanMatch(trackedRegion, candidateRegion: region)
    }

    private func objectCanMatch(
        _ lhs: SubjectCandidate,
        candidate: SubjectCandidate
    ) -> Bool {
        guard objectLabelsCompatible(lhs.label, candidate.label),
              let left = lhs.region,
              let right = candidate.region else { return false }
        return objectCanMatch(left, candidateRegion: right)
    }

    private func objectCanMatch(
        _ trackedRegion: NormalizedRect,
        candidateRegion: NormalizedRect
    ) -> Bool {
        guard Self.intersectionOverUnion(trackedRegion, candidateRegion) >= iouMatchThreshold else {
            return false
        }
        return centerDistance(trackedRegion, candidateRegion) <= centerJumpThreshold
    }

    private func centerDistance(_ lhs: NormalizedRect, _ rhs: NormalizedRect) -> Double {
        let dx = (lhs.x + lhs.width / 2) - (rhs.x + rhs.width / 2)
        let dy = (lhs.y + lhs.height / 2) - (rhs.y + rhs.height / 2)
        return (dx * dx + dy * dy).squareRoot()
    }

    private func ambiguousNewCandidate(
        at index: Int,
        among candidates: [SubjectCandidate]
    ) -> Bool {
        for otherIndex in candidates.indices where otherIndex != index {
            if objectCanMatch(candidates[index], candidate: candidates[otherIndex]) {
                return true
            }
        }
        return false
    }

    private func freshObjectState(
        _ candidate: SubjectCandidate,
        frameID: String,
        generation: UInt64,
        sampleSequence: UInt64
    ) -> ObjectTrackState {
        nextObjectOrdinal &+= 1
        let identity = SubjectTrackIdentity(
            trackID: "object-track-\(nextObjectOrdinal)",
            firstSeenFrameID: frameID,
            generation: generation
        )
        return ObjectTrackState(
            identity: identity,
            label: candidate.label,
            lastObservedRegion: candidate.region!,
            lastObservedFrameID: frameID,
            lastObservedSampleSequence: sampleSequence,
            phase: .active,
            frameID: frameID,
            sampleSequence: sampleSequence
        )
    }

    private func lostObjectState(
        _ state: ObjectTrackState,
        frameID: String,
        sampleSequence: UInt64
    ) -> ObjectTrackState {
        ObjectTrackState(
            identity: state.identity,
            label: state.label,
            lastObservedRegion: state.lastObservedRegion,
            lastObservedFrameID: state.lastObservedFrameID,
            lastObservedSampleSequence: state.lastObservedSampleSequence,
            phase: .lost,
            frameID: frameID,
            sampleSequence: sampleSequence
        )
    }

    private func addFreshObject(
        _ candidate: SubjectCandidate,
        to states: inout [ObjectTrackState],
        capacity: Int,
        frameID: String,
        generation: UInt64,
        sampleSequence: UInt64,
        replacingLost: [ObjectTrackState]
    ) {
        guard capacity > 0 else { return }
        for lost in replacingLost {
            states.removeAll { $0.identity == lost.identity }
        }
        if states.count >= capacity {
            guard let lostIndex = states.firstIndex(where: { $0.phase == .lost }) else {
                return
            }
            states.remove(at: lostIndex)
        }
        states.append(
            freshObjectState(
                candidate,
                frameID: frameID,
                generation: generation,
                sampleSequence: sampleSequence
            )
        )
    }

    private func limitedObjectStates(
        _ states: [ObjectTrackState],
        capacity: Int
    ) -> [ObjectTrackState] {
        guard capacity > 0 else { return [] }
        let sorted = states.sorted(by: objectStatePrecedes)
        if sorted.count <= capacity { return sorted }
        let active = sorted.filter { $0.phase == .active }
        let lost = sorted.filter { $0.phase == .lost }
        return Array((active + lost).prefix(capacity)).sorted(by: objectStatePrecedes)
    }

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
        let invalidatedTrackID: String?
        if let state, state.phase == .active {
            invalidatedTrackID = state.identity.trackID
            markLost(frameID: frameID)
        } else {
            invalidatedTrackID = nil
        }
        invalidateObjects(frameID: frameID)
        return invalidatedTrackID
    }
}
