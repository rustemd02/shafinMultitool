//
//  SubjectIdentityRegistry.swift
//  shafinMultitool
//
//  R03 groundwork: bounded multi-object identity owner. Maintains N
//  simultaneous observation identities across frames using greedy IoU
//  association, miss-based loss aging, capacity fencing, and capture
//  generation isolation. Pure value semantics: deterministic, unit-testable,
//  no camera dependence. This registry does not select an advice target and
//  does not feed live coaching by itself — wiring into the pipeline is a
//  separate package.
//

import Foundation

/// One per-frame detection offered to the registry (from Vision/DETR lanes).
/// `entityID` is the frame-local detector identity (one analysis); it is not a
/// session track identity. A reflection is provenance-tagged so a mirrored
/// image never becomes a rearrangeable object.
struct SubjectIdentityObservation: Equatable, Sendable {
    let region: NormalizedRect
    let confidence: Double
    let label: String?
    /// Frame-local detector entity id, when the detector supplies one.
    let entityID: String?
    /// Provider/decode provenance: a reflected image of a scene object.
    let isReflection: Bool

    init(region: NormalizedRect,
         confidence: Double,
         label: String? = nil,
         entityID: String? = nil,
         isReflection: Bool = false) {
        self.region = region
        self.confidence = confidence
        self.label = label
        self.entityID = entityID
        self.isReflection = isReflection
    }
}

/// A registered multi-object identity with its current observation state.
struct RegisteredSubjectIdentity: Equatable, Sendable {
    let identity: SubjectTrackIdentity
    var label: String?
    var region: NormalizedRect
    var confidence: Double
    var consecutiveMisses: Int
    var lifetimeFrames: Int
    /// Frame-local entity id of the last accepted observation (nil when the
    /// detector did not supply one). Kept separate from the session trackID.
    var lastEntityID: String?
    /// Frame of the last accepted observation.
    var lastFrameID: String
}

/// What happened to one detection/identity during `observe`.
enum SubjectIdentityEvent: Equatable, Sendable {
    case associated(trackID: String, iou: Double)
    case created(trackID: String)
    case lost(trackID: String)
    case capacityExceeded
}

/// Bounded registry of simultaneous subject identities. Not an advice-target
/// selector: `SubjectTracker` remains the single advice-target owner.
struct SubjectIdentityRegistry: Equatable, Sendable {

    static let maxIdentities = 6
    static let associationIoUThreshold = 0.30
    static let missLimit = 3

    private(set) var identities: [RegisteredSubjectIdentity] = []
    private let generation: UInt64
    private var nextTrackNumber = 1

    /// `generation` isolates registries across lens/orientation/route changes
    /// (same fence semantics as SubjectTrackIdentity).
    init(generation: UInt64) {
        self.generation = generation
    }

    /// Feed one frame of detections. Returns events in deterministic order:
    /// associations (by identity trackID), creations (by detection order),
    /// losses (by trackID).
    mutating func observe(detections: [SubjectIdentityObservation],
                          frameId: String) -> [SubjectIdentityEvent] {
        // Reflections are provenance-tagged images, not scene objects: they
        // never claim an identity and never take part in association.
        let detections = detections.filter { !$0.isReflection }
        var events: [SubjectIdentityEvent] = []
        var matched = [Int: Int]() // identity index -> detection index
        let existingIdentityCount = identities.count

        // Greedy best-IoU association: each identity and detection is claimed
        // at most once.
        var pairs: [(identity: Int, detection: Int, iou: Double)] = []
        for identityIndex in identities.indices {
            for detectionIndex in detections.indices {
                let iou = Self.iou(identities[identityIndex].region, detections[detectionIndex].region)
                if iou >= Self.associationIoUThreshold {
                    pairs.append((identityIndex, detectionIndex, iou))
                }
            }
        }
        pairs.sort {
            if $0.iou != $1.iou { return $0.iou > $1.iou }
            return $0.identity < $1.identity
        }
        var claimedIdentities = Set<Int>()
        var claimedDetections = Set<Int>()
        for pair in pairs where !claimedIdentities.contains(pair.identity) && !claimedDetections.contains(pair.detection) {
            claimedIdentities.insert(pair.identity)
            claimedDetections.insert(pair.detection)
            matched[pair.identity] = pair.detection
            identities[pair.identity].consecutiveMisses = 0
            identities[pair.identity].lifetimeFrames += 1
            identities[pair.identity].region = detections[pair.detection].region
            identities[pair.identity].confidence = detections[pair.detection].confidence
            identities[pair.identity].lastEntityID = detections[pair.detection].entityID
            identities[pair.identity].lastFrameID = frameId
            if let label = detections[pair.detection].label {
                identities[pair.identity].label = label
            }
            events.append(.associated(trackID: identities[pair.identity].identity.trackID, iou: pair.iou))
        }

        // Unmatched detections become new identities while capacity lasts.
        for detectionIndex in detections.indices where !claimedDetections.contains(detectionIndex) {
            guard identities.count < Self.maxIdentities else {
                events.append(.capacityExceeded)
                continue
            }
            let trackID = "sir_g\(generation)_\(nextTrackNumber)"
            nextTrackNumber += 1
            let detection = detections[detectionIndex]
            identities.append(
                RegisteredSubjectIdentity(
                    identity: SubjectTrackIdentity(trackID: trackID, firstSeenFrameID: frameId, generation: generation),
                    label: detection.label,
                    region: detection.region,
                    confidence: detection.confidence,
                    consecutiveMisses: 0,
                    lifetimeFrames: 1,
                    lastEntityID: detection.entityID,
                    lastFrameID: frameId
                )
            )
            events.append(.created(trackID: trackID))
        }

        // Unmatched identities age out after the miss limit. Identities
        // created in this same call are never aged in it.
        var lostTrackIDs: [String] = []
        for identityIndex in identities.indices
        where identityIndex < existingIdentityCount && !claimedIdentities.contains(identityIndex) {
            identities[identityIndex].consecutiveMisses += 1
            if identities[identityIndex].consecutiveMisses > Self.missLimit {
                lostTrackIDs.append(identities[identityIndex].identity.trackID)
            }
        }
        if !lostTrackIDs.isEmpty {
            identities.removeAll { identity in
                lostTrackIDs.contains(identity.identity.trackID)
            }
            for trackID in lostTrackIDs.sorted() {
                events.append(.lost(trackID: trackID))
            }
        }

        identities.sort { $0.identity.trackID < $1.identity.trackID }
        return events
    }

    func identity(forTrackID trackID: String) -> RegisteredSubjectIdentity? {
        identities.first { $0.identity.trackID == trackID }
    }

    /// The three identifiers that must never be conflated (C03.1). `trackID`
    /// is the session tracker identity; `entityID` is frame-local and may be
    /// absent when the detector does not supply one; `displayLabel` is
    /// sanitized presentation text and never proves identity.
    func entityReferences() -> [SubjectEntityReference] {
        identities.map { identity in
            SubjectEntityReference(
                frameID: identity.lastFrameID,
                entityID: identity.lastEntityID,
                trackID: identity.identity.trackID,
                displayLabel: SubjectEntityReference.safeDisplayLabel(identity.label)
            )
        }
    }

    /// O02/O05 groundwork: derived multi-object scene facts. The summary is
    /// read-only evidence for downstream consumers — it does not select
    /// advice targets and does not alter any coaching path.
    /// CC-O02: the tracked instance under a scene-space tap, nearest center
    /// wins. Pure read; the selection decision belongs to the caller.
    func instance(atSceneX x: Double, y: Double, touchSlop: Double = 0.04)
        -> RegisteredSubjectIdentity? {
        var best: (identity: RegisteredSubjectIdentity, distance: Double)?
        for identity in identities {
            let region = identity.region
            let insideInflated = x >= region.x - touchSlop
                && x <= region.x + region.width + touchSlop
                && y >= region.y - touchSlop
                && y <= region.y + region.height + touchSlop
            guard insideInflated else { continue }
            let dx = x - (region.x + region.width / 2)
            let dy = y - (region.y + region.height / 2)
            let distance = (dx * dx + dy * dy).squareRoot()
            if best == nil || distance < best!.distance {
                best = (identity, distance)
            }
        }
        return best?.identity
    }

    func multiObjectSummary() -> MultiObjectSceneSummary {
        var perLabel: [String: Int] = [:]
        for identity in identities {
            let key = identity.label ?? "unknown"
            perLabel[key, default: 0] += 1
        }
        var overlappingPairs: [TrackIDPair] = []
        for lhs in identities.indices {
            for rhs in identities.indices where lhs < rhs {
                if Self.iou(identities[lhs].region, identities[rhs].region) > Self.overlapIoUThreshold {
                    overlappingPairs.append(
                        TrackIDPair(lhs: identities[lhs].identity.trackID, rhs: identities[rhs].identity.trackID)
                    )
                }
            }
        }
        let edgeCut = identities
            .filter {
                $0.region.x <= Self.edgeCutMargin
                    || $0.region.y <= Self.edgeCutMargin
                    || $0.region.x + $0.region.width >= 1 - Self.edgeCutMargin
                    || $0.region.y + $0.region.height >= 1 - Self.edgeCutMargin
            }
            .map { $0.identity.trackID }
        return MultiObjectSceneSummary(
            identityCount: identities.count,
            identityCountByLabel: perLabel,
            overlappingTrackIDPairs: overlappingPairs,
            edgeCutTrackIDs: edgeCut
        )
    }

    static let overlapIoUThreshold = 0.15
    static let edgeCutMargin = 0.02

    private static func iou(_ lhs: NormalizedRect, _ rhs: NormalizedRect) -> Double {
        let intersectionWidth = max(0, min(lhs.x + lhs.width, rhs.x + rhs.width) - max(lhs.x, rhs.x))
        let intersectionHeight = max(0, min(lhs.y + lhs.height, rhs.y + rhs.height) - max(lhs.y, rhs.y))
        let intersectionArea = intersectionWidth * intersectionHeight
        let unionArea = (lhs.width * lhs.height) + (rhs.width * rhs.height) - intersectionArea
        return unionArea > 0 ? intersectionArea / unionArea : 0
    }
}

/// The separated identity triple for one registered subject (C03.1):
/// frame-local `entityID`, session `trackID` and a safe `displayLabel`.
/// Equal labels never prove equal identity — only `trackID` does.
struct SubjectEntityReference: Equatable, Sendable {
    let frameID: String
    /// Frame-local detector entity id (nil when the detector supplied none).
    let entityID: String?
    /// Session tracker identity; the only identity key.
    let trackID: String
    /// Sanitized presentation label; never an identity key.
    let displayLabel: String?

    /// Sanitizes untrusted provider text for display: removes control and
    /// default-ignorable code points, trims whitespace and bounds the length.
    /// Returns nil for empty/whitespace-only input instead of an empty label.
    static func safeDisplayLabel(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let strippedScalars = CharacterSet.controlCharacters
            .union(.illegalCharacters)
            .union(CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}"))
        let filtered = raw.unicodeScalars.filter { !strippedScalars.contains($0) }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: filtered)
        let cleaned = String(view).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(64))
    }
}

/// Read-only multi-object facts derived from the identity registry.
struct MultiObjectSceneSummary: Equatable, Sendable {
    let identityCount: Int
    /// Simultaneous identity count per label (e.g. two "lamp" instances).
    let identityCountByLabel: [String: Int]
    /// Tracked identity pairs whose regions currently overlap (O05 signal).
    let overlappingTrackIDPairs: [TrackIDPair]
    /// Identities whose region is cut by the frame edge.
    let edgeCutTrackIDs: [String]
}

struct TrackIDPair: Equatable, Sendable {
    let lhs: String
    let rhs: String
}

