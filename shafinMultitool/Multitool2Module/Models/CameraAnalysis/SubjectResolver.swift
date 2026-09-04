//
//  SubjectResolver.swift
//  shafinMultitool
//
//  M2-008 SubjectResolutionOwner: automatic face/person/group subject
//  resolution on top of Apple Vision output. Pure and deterministic: takes a
//  VisionTrackingResult, returns the M2-007 contract resolution. Ambiguous or
//  low-confidence inputs fail closed to the unknown resolution
//  (SELECT_SUBJECT) — the resolver never guesses a subject.
//

import Foundation

enum SubjectResolver {

    /// Two subjects whose boxes overlap at least this fraction of the smaller
    /// area are the same physical subject (a face inside its human rectangle).
    static let containmentOverlapThreshold: Double = 0.5
    /// Minimum confidence for an automatic resolution without saliency
    /// endorsement.
    static let automaticConfidenceFloor: Double = 0.5
    /// Top-two confidences within this distance are "similarly salient".
    static let salientTieThreshold: Double = 0.15

    /// Resolves the primary subject. See the decision table in
    /// `SubjectResolverTests` — the table is the contract; this function only
    /// implements it.
    static func resolve(result: VisionTrackingResult,
                        frameID: String,
                        generation: UInt64) throws -> SubjectResolutionV2 {
        let subjects = mergedSubjects(from: result)

        guard !subjects.isEmpty else {
            return try SubjectResolutionV2.unknown(
                reasons: [.noCandidate],
                decidedAtFrameID: frameID
            )
        }

        if subjects.count == 1 {
            let only = subjects[0]
            return try SubjectResolutionV2(
                resolution: .automatic,
                selected: candidate(from: only, frameID: frameID),
                track: nil,
                provenance: .automatic,
                confidence: only.confidence,
                ambiguityReasons: only.confidence < automaticConfidenceFloor
                    ? [.lowDetectionConfidence]
                    : [],
                decidedAtFrameID: frameID
            )
        }

        // Multiple subjects: saliency endorsement picks a single winner only
        // when exactly one subject contains the salient region center.
        let endorsed = saliencyEndorsedSubjects(from: result, subjects: subjects)
        let sorted = subjects.sorted { $0.confidence > $1.confidence }
        let topConfidence = sorted[0].confidence
        // Similarly salient: the top two confidences are within the tie
        // threshold of each other.
        let isTie = subjects.count >= 2
            && (topConfidence - sorted[1].confidence) <= salientTieThreshold

        if endorsed.count == 1 {
            let winner = endorsed[0]
            if winner.confidence >= automaticConfidenceFloor {
                return try SubjectResolutionV2(
                    resolution: .automatic,
                    selected: candidate(from: winner, frameID: frameID),
                    track: nil,
                    provenance: .automatic,
                    confidence: winner.confidence,
                    ambiguityReasons: [],
                    decidedAtFrameID: frameID
                )
            }
            // Saliency points at a low-confidence region: conflicting
            // evidence, no honest claim.
            return try SubjectResolutionV2.unknown(
                reasons: [.conflictingEvidence, .lowDetectionConfidence],
                decidedAtFrameID: frameID
            )
        }

        // A clear confidence gap (no tie) elects the top candidate directly.
        if !isTie, topConfidence >= automaticConfidenceFloor {
            return try SubjectResolutionV2(
                resolution: .automatic,
                selected: candidate(from: sorted[0], frameID: frameID),
                track: nil,
                provenance: .automatic,
                confidence: topConfidence,
                ambiguityReasons: [],
                decidedAtFrameID: frameID
            )
        }

        // Several similarly salient people: resolve to their group union
        // instead of picking one arbitrarily.
        if isTie, topConfidence >= automaticConfidenceFloor {
            if let union = SubjectGroupUnionV2.union(of: subjects.map({ candidate(from: $0, frameID: frameID) })) {
                let groupCandidate = SubjectCandidate(
                    id: "group-\(frameID)",
                    kind: .group,
                    label: nil,
                    region: union.unionRegion,
                    confidence: topConfidence
                )
                return try SubjectResolutionV2(
                    resolution: .group,
                    selected: groupCandidate,
                    groupUnion: union,
                    track: nil,
                    provenance: .groupUnion,
                    confidence: nil,
                    ambiguityReasons: [.personAndGroupOverlap],
                    decidedAtFrameID: frameID
                )
            }
        }

        // Low-confidence conflict: ambiguity rather than random selection.
        var reasons: [SubjectAmbiguityReasonV2] = []
        if isTie { reasons.append(.tieBetweenPersons) }
        if topConfidence < automaticConfidenceFloor { reasons.append(.lowDetectionConfidence) }
        if reasons.isEmpty { reasons.append(.conflictingEvidence) }
        return try SubjectResolutionV2.unknown(
            reasons: reasons,
            decidedAtFrameID: frameID
        )
    }

    // MARK: - Internals

    private struct ResolvedSubject {
        let boundingBox: CGRect
        let confidence: Double
        let isFace: Bool

        func contains(centerOf other: CGRect) -> Bool {
            let centerX = other.midX
            let centerY = other.midY
            return boundingBox.minX <= centerX
                && centerX <= boundingBox.maxX
                && boundingBox.minY <= centerY
                && centerY <= boundingBox.maxY
        }
    }

    /// Merges faces into their containing human rectangles (a face inside a
    /// person is one subject, confidence takes the max, isFace preserved).
    private static func mergedSubjects(from result: VisionTrackingResult) -> [ResolvedSubject] {
        var humans: [ResolvedSubject] = result.subjects
            .filter { !$0.isFace }
            .map { ResolvedSubject(boundingBox: $0.boundingBox, confidence: Double($0.confidence), isFace: false) }
        let faces = result.subjects.filter { $0.isFace }

        for face in faces {
            let faceBox = ResolvedSubject(boundingBox: face.boundingBox,
                                          confidence: Double(face.confidence),
                                          isFace: true)
            if let hostIndex = humans.firstIndex(where: { $0.contains(centerOf: face.boundingBox) }) {
                let host = humans[hostIndex]
                humans[hostIndex] = ResolvedSubject(
                    boundingBox: host.boundingBox,
                    confidence: max(host.confidence, faceBox.confidence),
                    isFace: false
                )
            } else {
                humans.append(faceBox)
            }
        }
        return humans
    }

    private static func saliencyEndorsedSubjects(
        from result: VisionTrackingResult,
        subjects: [ResolvedSubject]
    ) -> [ResolvedSubject] {
        guard let saliencyCenter = result.saliencyCenter else { return [] }
        return subjects.filter { subject in
            subject.contains(centerOf: CGRect(
                x: saliencyCenter.x,
                y: saliencyCenter.y,
                width: 0.001,
                height: 0.001
            ))
        }
    }

    private static func candidate(from subject: ResolvedSubject, frameID: String) -> SubjectCandidate {
        SubjectCandidate(
            id: "subject-\(frameID)-\(subject.isFace ? "face" : "person")-\(Int(subject.boundingBox.minX * 1000))-\(Int(subject.boundingBox.minY * 1000))",
            kind: subject.isFace ? .face : .person,
            label: subject.isFace ? "лицо" : "человек",
            region: NormalizedRect(
                x: Double(subject.boundingBox.minX),
                y: Double(subject.boundingBox.minY),
                width: Double(subject.boundingBox.width),
                height: Double(subject.boundingBox.height)
            ),
            confidence: subject.confidence
        )
    }
}
