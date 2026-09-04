//
//  SubjectResolverTests.swift
//  shafinMultitoolTests
//
//  M2-008 SubjectResolutionOwner: resolver decision table over synthetic
//  Vision observation fixtures covering 0/1/2/3 subjects, ties, saliency
//  endorsement, face-in-person merging, and low-confidence conflicts.
//

import XCTest
@testable import shafinMultitool

final class SubjectResolverTests: XCTestCase {

    private func fixture(
        subjects: [(CGRect, Float, Bool)],
        saliencyCenter: CGPoint? = nil
    ) -> VisionTrackingResult {
        VisionTrackingResult(
            subjects: subjects.map { TrackedSubject(boundingBox: $0.0, confidence: $0.1, isFace: $0.2) },
            saliencyCenter: saliencyCenter,
            saliencyRegion: nil,
            faceCount: subjects.filter { $0.2 }.count,
            personCount: subjects.filter { !$0.2 }.count
        )
    }

    private let personBox = CGRect(x: 0.1, y: 0.3, width: 0.2, height: 0.5)

    // MARK: - 0 subjects

    func testNoSubjectsFailsClosedToUnknownNoCandidate() throws {
        let resolution = try SubjectResolver.resolve(
            result: fixture(subjects: []), frameID: "f1", generation: 1
        )
        XCTAssertEqual(resolution.resolution, .unknown)
        XCTAssertEqual(resolution.ambiguityReasons, [.noCandidate])
        XCTAssertNil(resolution.selected)
    }

    // MARK: - 1 subject

    func testSinglePersonResolvesAutomatically() throws {
        let resolution = try SubjectResolver.resolve(
            result: fixture(subjects: [(personBox, 0.9, false)]), frameID: "f1", generation: 1
        )
        XCTAssertEqual(resolution.resolution, .automatic)
        XCTAssertEqual(resolution.selected?.kind, .person)
        XCTAssertEqual(resolution.confidence ?? 0, 0.9, accuracy: 1e-6)
        XCTAssertTrue(resolution.ambiguityReasons.isEmpty)
    }

    func testSingleLowConfidencePersonResolvesWithLowConfidenceReason() throws {
        let resolution = try SubjectResolver.resolve(
            result: fixture(subjects: [(personBox, 0.3, false)]), frameID: "f1", generation: 1
        )
        XCTAssertEqual(resolution.resolution, .automatic)
        XCTAssertEqual(resolution.ambiguityReasons, [.lowDetectionConfidence])
    }

    // MARK: - Face-in-person merging

    func testFaceInsidePersonMergesIntoOneSubject() throws {
        let face = CGRect(x: 0.15, y: 0.32, width: 0.08, height: 0.08)
        let resolution = try SubjectResolver.resolve(
            result: fixture(subjects: [(personBox, 0.8, false), (face, 0.9, true)]),
            frameID: "f1",
            generation: 1
        )
        XCTAssertEqual(resolution.resolution, .automatic)
        // Merged subject keeps the person box and takes the max confidence.
        XCTAssertEqual(resolution.selected?.region?.width ?? 0, personBox.width, accuracy: 1e-9)
        XCTAssertEqual(resolution.confidence ?? 0, 0.9, accuracy: 1e-6)
    }

    // MARK: - 2 subjects: tie vs saliency endorsement

    func testTwoSimilarlySalientPeopleResolveToGroupUnion() throws {
        let left = CGRect(x: 0.1, y: 0.3, width: 0.2, height: 0.5)
        let right = CGRect(x: 0.7, y: 0.3, width: 0.2, height: 0.5)
        let resolution = try SubjectResolver.resolve(
            result: fixture(subjects: [(left, 0.8, false), (right, 0.75, false)]),
            frameID: "f1",
            generation: 1
        )
        XCTAssertEqual(resolution.resolution, .group)
        XCTAssertEqual(resolution.groupUnion?.memberCandidateIDs.count, 2)
        XCTAssertEqual(resolution.selected?.kind, .group)
        XCTAssertEqual(resolution.ambiguityReasons, [.personAndGroupOverlap])
    }

    func testSaliencyEndorsementPicksOneOfTwoPeople() throws {
        let left = CGRect(x: 0.1, y: 0.3, width: 0.2, height: 0.5)
        let right = CGRect(x: 0.7, y: 0.3, width: 0.2, height: 0.5)
        let resolution = try SubjectResolver.resolve(
            result: fixture(
                subjects: [(left, 0.8, false), (right, 0.8, false)],
                saliencyCenter: CGPoint(x: right.midX, y: right.midY)
            ),
            frameID: "f1",
            generation: 1
        )
        XCTAssertEqual(resolution.resolution, .automatic)
        XCTAssertEqual(
            resolution.selected?.region?.x ?? -1,            right.minX,
            accuracy: 1e-9,
            "saliency must endorse the right person"
        )
    }

    // MARK: - 3 subjects

    func testThreeSalientPeopleResolveToGroupUnion() throws {
        let boxes = [
            CGRect(x: 0.05, y: 0.3, width: 0.2, height: 0.5),
            CGRect(x: 0.4, y: 0.3, width: 0.2, height: 0.5),
            CGRect(x: 0.75, y: 0.3, width: 0.2, height: 0.5),
        ]
        let resolution = try SubjectResolver.resolve(
            result: fixture(subjects: boxes.map { ($0, Float(0.85), false) }),
            frameID: "f1",
            generation: 1
        )
        XCTAssertEqual(resolution.resolution, .group)
        XCTAssertEqual(resolution.groupUnion?.memberCandidateIDs.count, 3)
    }

    // MARK: - Low-confidence conflicts

    func testLowConfidenceConflictReturnsAmbiguityNotRandomPick() throws {
        let left = CGRect(x: 0.1, y: 0.3, width: 0.2, height: 0.5)
        let right = CGRect(x: 0.7, y: 0.3, width: 0.2, height: 0.5)
        let resolution = try SubjectResolver.resolve(
            result: fixture(subjects: [(left, 0.3, false), (right, 0.35, false)]),
            frameID: "f1",
            generation: 1
        )
        XCTAssertEqual(resolution.resolution, .unknown)
        XCTAssertTrue(resolution.ambiguityReasons.contains(.lowDetectionConfidence))
        XCTAssertNil(resolution.selected)
    }

    func testTiedLowConfidenceReportsBothReasons() throws {
        let left = CGRect(x: 0.1, y: 0.3, width: 0.2, height: 0.5)
        let right = CGRect(x: 0.7, y: 0.3, width: 0.2, height: 0.5)
        let resolution = try SubjectResolver.resolve(
            result: fixture(subjects: [(left, 0.3, false), (right, 0.3, false)]),
            frameID: "f1",
            generation: 1
        )
        XCTAssertEqual(resolution.resolution, .unknown)
        XCTAssertEqual(resolution.ambiguityReasons, [.tieBetweenPersons, .lowDetectionConfidence])
    }

    func testDistinctSalienceGapResolvesHigherCandidate() throws {
        let left = CGRect(x: 0.1, y: 0.3, width: 0.2, height: 0.5)
        let right = CGRect(x: 0.7, y: 0.3, width: 0.2, height: 0.5)
        // Confidence gap above the tie threshold and both above the floor:
        // the higher candidate wins without saliency.
        let resolution = try SubjectResolver.resolve(
            result: fixture(subjects: [(left, 0.9, false), (right, 0.6, false)]),
            frameID: "f1",
            generation: 1
        )
        XCTAssertEqual(resolution.resolution, .automatic)
        XCTAssertEqual(resolution.selected?.region?.x ?? -1, left.minX, accuracy: 1e-9)
    }
}
