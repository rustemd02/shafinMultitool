//
//  PauseEvidencePackageTests.swift
//  shafinMultitoolTests
//
//  M2-006 PauseAnalysisOwner: the pause evidence package declares its
//  temporality explicitly, exposes every source age to validation, and fails
//  closed on stale or missing sources so pause output can never combine
//  current inference with stale unmarked values.
//

import XCTest
@testable import shafinMultitool

final class PauseEvidencePackageTests: XCTestCase {

    private let capturedAt = Date(timeIntervalSince1970: 5_000)
    private var pixelBuffer: CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, 4, 4, kCVPixelFormatType_32BGRA, nil, &buffer
        )
        precondition(status == kCVReturnSuccess)
        return buffer!
    }

    private func makeEnvelope(
        lensGeneration: UInt64 = 3,
        timestamps: [FeatureSourceID: Date]
    ) -> AcceptedFrameEnvelope {
        AcceptedFrameEnvelope(
            frameID: "pause-frame",
            capturedAt: capturedAt,
            orientation: .up,
            lensGeneration: lensGeneration,
            pixelBuffer: pixelBuffer,
            featureSourceTimestamps: timestamps
        )
    }

    // MARK: - Temporality declaration

    func testNoRecomputeDeclaresSameFrame() {
        let envelope = makeEnvelope(timestamps: [
            .vision: capturedAt, .horizon: capturedAt, .lighting: capturedAt,
        ])
        let package = PauseEvidencePackage(
            envelope: envelope,
            recomputeTimestamps: [:],
            asOf: capturedAt.addingTimeInterval(0.1)
        )
        XCTAssertEqual(package.temporality, .sameFrame)
    }

    func testPauseTimeRecomputeDeclaresTemporalAggregate() {
        let envelope = makeEnvelope(timestamps: [.vision: capturedAt])
        let pauseTime = capturedAt.addingTimeInterval(0.3)
        let package = PauseEvidencePackage(
            envelope: envelope,
            recomputeTimestamps: [.detr: pauseTime],
            asOf: pauseTime
        )
        XCTAssertEqual(package.temporality, .temporalAggregate)
        XCTAssertEqual(package.verdicts[.detr]?.isAvailable, true,
                       "fresh pause-time recompute stays available")
        XCTAssertEqual(package.verdicts[.detr]?.ageSeconds ?? -1, 0, accuracy: 1e-9)
    }

    // MARK: - Stale-source barrier

    func testStaleBaseSourcesAreUnavailableAndExcluded() {
        // Base values measured with the frame; pause validation happens 2s
        // later. Every declared window (max 1.5s for aesthetic) has expired,
        // so all five sources must be unavailable.
        let envelope = makeEnvelope(timestamps: [
            .vision: capturedAt, .horizon: capturedAt, .lighting: capturedAt,
            .detr: capturedAt, .aesthetic: capturedAt,
        ])
        let package = PauseEvidencePackage(
            envelope: envelope,
            recomputeTimestamps: [:],
            asOf: capturedAt.addingTimeInterval(2.0)
        )

        XCTAssertFalse(package.isSourceUsable(.vision))
        XCTAssertFalse(package.isSourceUsable(.horizon))
        XCTAssertFalse(package.isSourceUsable(.lighting))
        XCTAssertFalse(package.isSourceUsable(.detr))
        XCTAssertFalse(package.isSourceUsable(.aesthetic))

        // Every source age is exposed to validation (including unavailable).
        XCTAssertEqual(package.exposedAges.count, FeatureSourceID.allCases.count)
        XCTAssertEqual(package.exposedAges[.vision].flatMap { $0 } ?? -1, 2.0, accuracy: 1e-9)
        XCTAssertEqual(package.exposedAges[.aesthetic].flatMap { $0 } ?? -1, 2.0, accuracy: 1e-9)
    }

    func testMissingBaseSourceIsUnavailableWithNilAge() {
        let envelope = makeEnvelope(timestamps: [.vision: capturedAt])
        let package = PauseEvidencePackage(
            envelope: envelope,
            recomputeTimestamps: [:],
            asOf: capturedAt
        )
        XCTAssertFalse(package.isSourceUsable(.horizon))
        XCTAssertEqual(package.verdicts[.horizon]?.measuredAt, nil)
        XCTAssertNil(package.exposedAges[.horizon] ?? nil)
    }

    func testFreshRecomputeCannotRescueStaleEnvelopeMixing() {
        // A fresh pause-time DETR recompute must not implicitly mark the stale
        // base sources usable: availability is judged per source.
        let envelope = makeEnvelope(timestamps: [
            .vision: capturedAt, .lighting: capturedAt,
        ])
        let pauseTime = capturedAt.addingTimeInterval(1.2)
        let package = PauseEvidencePackage(
            envelope: envelope,
            recomputeTimestamps: [.detr: pauseTime],
            asOf: pauseTime
        )
        XCTAssertEqual(package.temporality, .temporalAggregate)
        XCTAssertTrue(package.isSourceUsable(.detr), "fresh recompute available")
        XCTAssertFalse(package.isSourceUsable(.vision), "stale base stays excluded")
        XCTAssertFalse(package.isSourceUsable(.lighting), "stale base stays excluded")
    }

    func testUnknownLensGenerationFailsClosedForWholePackage() {
        let envelope = makeEnvelope(lensGeneration: 0, timestamps: [
            .vision: capturedAt,
        ])
        let package = PauseEvidencePackage(
            envelope: envelope,
            recomputeTimestamps: [:],
            asOf: capturedAt
        )
        XCTAssertFalse(package.isSourceUsable(.vision))
    }
}
