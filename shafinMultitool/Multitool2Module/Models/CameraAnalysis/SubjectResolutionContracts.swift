//
//  SubjectResolutionContracts.swift
//  shafinMultitool
//
//  M2-007 SubjectResolutionOwner: the subject resolution contract. A primary
//  subject is automatic, user-selected, a group union, or unknown; confidence
//  and ambiguity are modelled separately; track identity persists across
//  temporal tracking (M2-010). Every ambiguous outcome fails closed to the
//  SELECT_SUBJECT state — the pipeline never invents a subject.
//

import Foundation

/// Stable subject identity across frames. Issued when a candidate first
/// appears and kept while temporal tracking (M2-010) can re-associate it.
struct SubjectTrackIdentity: Codable, Equatable, Sendable {
    let trackID: String
    let firstSeenFrameID: String
    /// Capture generation the track was born in; a lens/orientation/route
    /// change invalidates the track (M2-011).
    let generation: UInt64

    init(trackID: String, firstSeenFrameID: String, generation: UInt64) {
        self.trackID = trackID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.firstSeenFrameID = firstSeenFrameID
        self.generation = generation
    }

    var isValid: Bool {
        !trackID.isEmpty && !firstSeenFrameID.isEmpty
    }
}

/// Why automatic resolution failed and SELECT_SUBJECT is required. These are
/// the subject-level ambiguity reasons (scene-type ambiguity remains in the
/// semantics layer as `AmbiguityType`).
enum SubjectAmbiguityReasonV2: String, Codable, CaseIterable, Sendable {
    case tieBetweenPersons = "tie_between_persons"
    case personAndGroupOverlap = "person_and_group_overlap"
    case lowDetectionConfidence = "low_detection_confidence"
    case conflictingEvidence = "conflicting_evidence"
    case noCandidate = "no_candidate"
}

/// How the primary subject was decided.
enum SubjectSelectionSourceV2: String, Codable, Sendable {
    /// The pipeline resolved confidently (confidence required).
    case automatic
    /// The user tapped a candidate in the S05 clarification state.
    case userTap
    /// The user or pipeline chose a group union of overlapping candidates.
    case groupUnion
}

/// The resolved primary subject. Invariants are enforced by the throwing
/// initializer; construction cannot produce a half-valid resolution.
struct SubjectResolutionV2: Codable, Equatable, Sendable {
    /// How the subject was decided.
    enum Resolution: String, Codable, Sendable {
        case automatic
        case userSelected = "user_selected"
        case group
        /// Fail-closed outcome: no honest subject claim (SELECT_SUBJECT).
        case unknown
    }

    let resolution: Resolution
    /// The selected candidate. Nil only for `.unknown`.
    let selected: SubjectCandidate?
    /// Present only when the resolution is a group union.
    let groupUnion: SubjectGroupUnionV2?
    /// Track identity for temporal continuity. Nil while the subject is not
    /// yet tracked (e.g. immediately after a user tap before M2-010 issues it).
    let track: SubjectTrackIdentity?
    let provenance: SubjectSelectionSourceV2
    /// Model confidence of the automatic decision. Deliberately separate from
    /// ambiguity: a resolution can be confident and still ambiguous, or a user
    /// tap can resolve ambiguity without any model confidence. Nil for user
    /// decisions.
    let confidence: Double?
    /// Ambiguity reasons. Empty only for confident automatic resolutions.
    let ambiguityReasons: [SubjectAmbiguityReasonV2]
    /// Envelope frame ID the decision was made on (provenance).
    let decidedAtFrameID: String

    /// - Throws: `SubjectResolutionValidationError` when the combination is
    ///   not expressible as an honest subject claim.
    init(resolution: Resolution,
         selected: SubjectCandidate?,
         groupUnion: SubjectGroupUnionV2? = nil,
         track: SubjectTrackIdentity?,
         provenance: SubjectSelectionSourceV2,
         confidence: Double?,
         ambiguityReasons: [SubjectAmbiguityReasonV2],
         decidedAtFrameID: String) throws {
        if resolution == .unknown {
            guard selected == nil else {
                throw SubjectResolutionValidationError.unknownResolutionMustNotNameCandidate
            }
            guard ambiguityReasons.isEmpty == false else {
                throw SubjectResolutionValidationError.unknownResolutionRequiresAmbiguityReason
            }
        } else {
            guard let selected else {
                throw SubjectResolutionValidationError.resolutionRequiresCandidate
            }
            if resolution == .group {
                guard groupUnion != nil else {
                    throw SubjectResolutionValidationError.groupResolutionRequiresUnion
                }
            } else {
                guard groupUnion == nil else {
                    throw SubjectResolutionValidationError.nonGroupResolutionCannotCarryUnion
                }
            }
            if provenance == .automatic {
                guard let confidence else {
                    throw SubjectResolutionValidationError.automaticResolutionRequiresConfidence
                }
                guard (0...1).contains(confidence) else {
                    throw SubjectResolutionValidationError.confidenceOutOfRange
                }
            }
        }

        self.resolution = resolution
        self.selected = selected
        self.groupUnion = groupUnion
        self.track = track
        self.provenance = provenance
        self.confidence = confidence
        self.ambiguityReasons = ambiguityReasons
        self.decidedAtFrameID = decidedAtFrameID
    }

    /// Fail-closed outcome: no subject claim, with the reasons why
    /// SELECT_SUBJECT is required.
    static func unknown(reasons: [SubjectAmbiguityReasonV2],
                        decidedAtFrameID: String) throws -> SubjectResolutionV2 {
        try SubjectResolutionV2(
            resolution: .unknown,
            selected: nil,
            track: nil,
            provenance: .automatic,
            confidence: nil,
            ambiguityReasons: reasons,
            decidedAtFrameID: decidedAtFrameID
        )
    }
}

enum SubjectResolutionValidationError: Error, Equatable, Sendable {
    case unknownResolutionMustNotNameCandidate
    case unknownResolutionRequiresAmbiguityReason
    case resolutionRequiresCandidate
    case groupResolutionRequiresUnion
    case nonGroupResolutionCannotCarryUnion
    case automaticResolutionRequiresConfidence
    case confidenceOutOfRange
}

/// Union of overlapping person candidates into one group subject. The union
/// region is the bounding box of the member regions.
struct SubjectGroupUnionV2: Codable, Equatable, Sendable {
    let memberCandidateIDs: [String]
    let unionRegion: NormalizedRect

    /// Builds the union of at least two candidates that all carry regions.
    /// Returns nil (fail closed) for degenerate input: fewer than two members,
    /// any missing region, or any non-finite region value.
    static func union(of candidates: [SubjectCandidate]) -> SubjectGroupUnionV2? {
        guard candidates.count >= 2 else { return nil }
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for candidate in candidates {
            guard let region = candidate.region else { return nil }
            minX = min(minX, region.x)
            minY = min(minY, region.y)
            maxX = max(maxX, region.x + region.width)
            maxY = max(maxY, region.y + region.height)
        }
        let union = NormalizedRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
        return SubjectGroupUnionV2(
            memberCandidateIDs: candidates.map(\.id),
            unionRegion: union
        )
    }
}
