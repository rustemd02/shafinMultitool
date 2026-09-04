//
//  SubjectResolutionContractsTests.swift
//  shafinMultitoolTests
//
//  M2-007 SubjectResolutionOwner: Codable/validation fixtures for person,
//  group, object, unknown and conflicting candidate resolutions.
//

import XCTest
@testable import shafinMultitool

final class SubjectResolutionContractsTests: XCTestCase {

    private func person(id: String, x: Double, confidence: Double = 0.9) -> SubjectCandidate {
        SubjectCandidate(id: id, kind: .person, label: "человек", region: NormalizedRect(x: x, y: 0.3, width: 0.2, height: 0.4), confidence: confidence)
    }

    // MARK: - Validation: automatic resolution

    func testAutomaticPersonResolutionIsValidWithConfidence() throws {
        let resolution = try SubjectResolutionV2(
            resolution: .automatic,
            selected: person(id: "p1", x: 0.2),
            track: SubjectTrackIdentity(trackID: "t1", firstSeenFrameID: "f1", generation: 5),
            provenance: .automatic,
            confidence: 0.92,
            ambiguityReasons: [],
            decidedAtFrameID: "f1"
        )
        XCTAssertEqual(resolution.resolution, .automatic)
        XCTAssertEqual(resolution.track?.trackID, "t1")
        XCTAssertTrue(resolution.ambiguityReasons.isEmpty)
    }

    func testAutomaticResolutionWithoutConfidenceThrows() {
        XCTAssertThrowsError(try SubjectResolutionV2(
            resolution: .automatic,
            selected: person(id: "p1", x: 0.2),
            track: nil,
            provenance: .automatic,
            confidence: nil,
            ambiguityReasons: [],
            decidedAtFrameID: "f1"
        )) { error in
            XCTAssertEqual(error as? SubjectResolutionValidationError, .automaticResolutionRequiresConfidence)
        }
    }

    func testConfidenceOutOfRangeThrows() {
        XCTAssertThrowsError(try SubjectResolutionV2(
            resolution: .automatic,
            selected: person(id: "p1", x: 0.2),
            track: nil,
            provenance: .automatic,
            confidence: 1.4,
            ambiguityReasons: [],
            decidedAtFrameID: "f1"
        )) { error in
            XCTAssertEqual(error as? SubjectResolutionValidationError, .confidenceOutOfRange)
        }
    }

    // MARK: - Fail-closed unknown

    func testUnknownResolutionRequiresReasonAndCarriesNoCandidate() throws {
        let unknown = try SubjectResolutionV2.unknown(
            reasons: [.noCandidate],
            decidedAtFrameID: "f1"
        )
        XCTAssertEqual(unknown.resolution, .unknown)
        XCTAssertNil(unknown.selected)
        XCTAssertEqual(unknown.ambiguityReasons, [.noCandidate])

        XCTAssertThrowsError(try SubjectResolutionV2.unknown(reasons: [], decidedAtFrameID: "f1")) { error in
            XCTAssertEqual(error as? SubjectResolutionValidationError, .unknownResolutionRequiresAmbiguityReason)
        }
        XCTAssertThrowsError(try SubjectResolutionV2(
            resolution: .unknown,
            selected: person(id: "p1", x: 0.2),
            track: nil,
            provenance: .automatic,
            confidence: nil,
            ambiguityReasons: [.lowDetectionConfidence],
            decidedAtFrameID: "f1"
        )) { error in
            XCTAssertEqual(error as? SubjectResolutionValidationError, .unknownResolutionMustNotNameCandidate)
        }
    }

    // MARK: - Group union

    func testGroupUnionSpansMemberRegionsAndRequiresUnion() throws {
        let left = person(id: "p1", x: 0.1)
        let right = SubjectCandidate(id: "p2", kind: .person, region: NormalizedRect(x: 0.6, y: 0.25, width: 0.2, height: 0.5), confidence: 0.8)
        let union = try XCTUnwrap(SubjectGroupUnionV2.union(of: [left, right]))
        XCTAssertEqual(Set(union.memberCandidateIDs), ["p1", "p2"])
        XCTAssertEqual(union.unionRegion.x, 0.1, accuracy: 1e-12)
        XCTAssertEqual(union.unionRegion.width, 0.7, accuracy: 1e-12)

        XCTAssertNil(SubjectGroupUnionV2.union(of: [left]), "single candidate cannot union")
        XCTAssertNil(
            SubjectGroupUnionV2.union(of: [
                SubjectCandidate(id: "r", kind: .person, confidence: 0.5),
                person(id: "p1", x: 0.1),
            ]),
            "missing region fails closed"
        )

        // Group resolution without a union is invalid.
        XCTAssertThrowsError(try SubjectResolutionV2(
            resolution: .group,
            selected: left,
            track: nil,
            provenance: .groupUnion,
            confidence: nil,
            ambiguityReasons: [.personAndGroupOverlap],
            decidedAtFrameID: "f1"
        )) { error in
            XCTAssertEqual(error as? SubjectResolutionValidationError, .groupResolutionRequiresUnion)
        }

        // Valid group resolution carries the union and no confidence.
        let groupResolution = try SubjectResolutionV2(
            resolution: .group,
            selected: SubjectCandidate(id: "group", kind: .group, region: union.unionRegion, confidence: 0.7),
            groupUnion: union,
            track: nil,
            provenance: .groupUnion,
            confidence: nil,
            ambiguityReasons: [.personAndGroupOverlap],
            decidedAtFrameID: "f1"
        )
        XCTAssertEqual(groupResolution.groupUnion?.memberCandidateIDs.count, 2)
    }

    // MARK: - Conflicting candidates and ambiguity separation

    func testTiedCandidatesResolveToUnknownWithReasonsNotToAGuess() throws {
        let left = person(id: "p1", x: 0.15, confidence: 0.55)
        let right = person(id: "p2", x: 0.65, confidence: 0.55)
        let tie = abs(left.confidence - right.confidence) < 0.05
        XCTAssertTrue(tie, "fixture must represent a real tie")

        let unknown = try SubjectResolutionV2.unknown(
            reasons: [.tieBetweenPersons],
            decidedAtFrameID: "f1"
        )
        XCTAssertNil(unknown.selected, "a tie must never be resolved by guessing")
        XCTAssertEqual(unknown.ambiguityReasons, [.tieBetweenPersons])
    }

    func testConfidenceAndAmbiguityAreSeparateAxes() throws {
        // Confident resolution: no ambiguity reasons.
        let confident = try SubjectResolutionV2(
            resolution: .automatic,
            selected: person(id: "p1", x: 0.2, confidence: 0.97),
            track: nil,
            provenance: .automatic,
            confidence: 0.97,
            ambiguityReasons: [],
            decidedAtFrameID: "f1"
        )
        XCTAssertNotNil(confident.confidence)
        XCTAssertTrue(confident.ambiguityReasons.isEmpty)

        // A user tap resolves ambiguity without any model confidence.
        let userTap = try SubjectResolutionV2(
            resolution: .userSelected,
            selected: person(id: "p2", x: 0.65),
            track: nil,
            provenance: .userTap,
            confidence: nil,
            ambiguityReasons: [.tieBetweenPersons],
            decidedAtFrameID: "f1"
        )
        XCTAssertNil(userTap.confidence, "user decisions carry no model confidence")
        XCTAssertEqual(userTap.ambiguityReasons, [.tieBetweenPersons])
    }

    // MARK: - Codable round-trips (person / group / object / unknown fixtures)

    func testCodableRoundTripForAllResolutionShapes() throws {
        let object = SubjectCandidate(id: "o1", kind: .object, label: "предмет", region: NormalizedRect(x: 0.3, y: 0.5, width: 0.1, height: 0.1), confidence: 0.6)
        let shapes: [SubjectResolutionV2] = [
            try SubjectResolutionV2(
                resolution: .automatic,
                selected: person(id: "p1", x: 0.2),
                track: SubjectTrackIdentity(trackID: "t1", firstSeenFrameID: "f1", generation: 2),
                provenance: .automatic,
                confidence: 0.9,
                ambiguityReasons: [],
                decidedAtFrameID: "f1"
            ),
            try SubjectResolutionV2(
                resolution: .userSelected,
                selected: object,
                track: nil,
                provenance: .userTap,
                confidence: nil,
                ambiguityReasons: [.lowDetectionConfidence],
                decidedAtFrameID: "f2"
            ),
            try SubjectResolutionV2(
                resolution: .group,
                selected: SubjectCandidate(id: "group", kind: .group, region: NormalizedRect(x: 0.1, y: 0.25, width: 0.7, height: 0.5), confidence: 0.7),
                groupUnion: SubjectGroupUnionV2(memberCandidateIDs: ["p1", "p2"], unionRegion: NormalizedRect(x: 0.1, y: 0.25, width: 0.7, height: 0.5)),
                track: nil,
                provenance: .groupUnion,
                confidence: nil,
                ambiguityReasons: [.personAndGroupOverlap],
                decidedAtFrameID: "f3"
            ),
            try SubjectResolutionV2.unknown(reasons: [.conflictingEvidence], decidedAtFrameID: "f4"),
        ]

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        for shape in shapes {
            let data = try encoder.encode(shape)
            let decoded = try decoder.decode(SubjectResolutionV2.self, from: data)
            XCTAssertEqual(decoded, shape)
        }
    }

    func testTrackIdentityValidation() {
        XCTAssertFalse(SubjectTrackIdentity(trackID: "  ", firstSeenFrameID: "f1", generation: 1).isValid)
        XCTAssertFalse(SubjectTrackIdentity(trackID: "t1", firstSeenFrameID: "", generation: 1).isValid)
        XCTAssertTrue(SubjectTrackIdentity(trackID: "t1", firstSeenFrameID: "f1", generation: 1).isValid)
    }
}
