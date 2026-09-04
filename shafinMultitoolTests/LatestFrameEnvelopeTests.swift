//
//  LatestFrameEnvelopeTests.swift
//  shafinMultitoolTests
//
//  M2-005 AnalysisPipelineOwner: the immutable AcceptedFrameEnvelope binds
//  frame identity, capture time, orientation, lens generation, pixels and
//  per-source feature timestamps. Freshness windows are fail-closed: out-of-
//  window or missing sources are unavailable — never silently mixed.
//

import XCTest
@testable import shafinMultitool

final class LatestFrameEnvelopeTests: XCTestCase {

    private let captureTime = Date(timeIntervalSince1970: 1_000)

    private func makeEnvelope(
        lensGeneration: UInt64 = 7,
        timestamps: [FeatureSourceID: Date]
    ) -> AcceptedFrameEnvelope {
        AcceptedFrameEnvelope(
            frameID: "frame-1",
            capturedAt: captureTime,
            orientation: .up,
            lensGeneration: lensGeneration,
            pixelBuffer: makePixelBuffer(),
            featureSourceTimestamps: timestamps
        )
    }

    private func makePixelBuffer() -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, 4, 4, kCVPixelFormatType_32BGRA, nil, &buffer
        )
        precondition(status == kCVReturnSuccess, "fixture pixel buffer creation failed")
        return buffer!
    }

    private func agesFromCapture(_ seconds: Double?) -> [FeatureSourceID: Date] {
        guard let seconds else { return [:] }
        return [FeatureSourceID.vision: captureTime.addingTimeInterval(-seconds)]
    }

    // MARK: - Freshness windows

    func testFreshSourceInsideWindowIsAvailable() {
        let envelope = makeEnvelope(timestamps: agesFromCapture(0.1))
        XCTAssertEqual(envelope.sourceAvailability(asOf: captureTime)[.vision], true)
    }

    func testExpiredSourceIsUnavailableNotMixed() {
        // Vision window is 0.25s; a 2s-old vision value must not be combined
        // with fresh lighting values — it is simply unavailable.
        var timestamps = agesFromCapture(2.0)
        timestamps[.lighting] = captureTime
        let envelope = makeEnvelope(timestamps: timestamps)
        let availability = envelope.sourceAvailability(asOf: captureTime)
        XCTAssertEqual(availability[.vision], false, "expired vision must be unavailable")
        XCTAssertEqual(availability[.lighting], true, "fresh lighting stays available")
    }

    func testEachSourceUsesItsDeclaredWindow() {
        let ages: [FeatureSourceID: TimeInterval] = [
            .vision: 0.2,      // inside 0.25
            .horizon: 0.35,    // inside 0.4
            .lighting: 0.5,    // inside 0.6
            .detr: 0.75,       // inside 0.8
            .aesthetic: 1.4,   // inside 1.5
        ]
        let envelope = makeEnvelope(timestamps: ages.mapValues { captureTime.addingTimeInterval(-$0) })
        let availability = envelope.sourceAvailability(asOf: captureTime)
        for source in FeatureSourceID.allCases {
            XCTAssertEqual(availability[source], true, "\(source) inside its window")
        }

        let expiredAges = ages.mapValues { $0 + 0.2 }
        let expiredEnvelope = makeEnvelope(timestamps: expiredAges.mapValues {
            captureTime.addingTimeInterval(-$0)
        })
        let expiredAvailability = expiredEnvelope.sourceAvailability(asOf: captureTime)
        // vision (0.4 > 0.25), horizon (0.55 > 0.4), lighting (0.7 > 0.6),
        // detr (0.95 > 0.8) expire; aesthetic (1.6 > 1.5) expires too.
        for source in FeatureSourceID.allCases {
            XCTAssertEqual(expiredAvailability[source], false, "\(source) outside its window")
        }
    }

    func testMissingSourceTimestampIsUnavailable() {
        let envelope = makeEnvelope(timestamps: [:])
        let availability = envelope.sourceAvailability(asOf: captureTime)
        for source in FeatureSourceID.allCases {
            XCTAssertEqual(availability[source], false, "\(source) without a timestamp is unavailable")
        }
    }

    func testUnknownLensGenerationFailsClosedAllSourcesUnavailable() {
        let envelope = makeEnvelope(
            lensGeneration: 0,
            timestamps: agesFromCapture(0.0) // perfectly fresh, but unattributable
        )
        let availability = envelope.sourceAvailability(asOf: captureTime)
        for source in FeatureSourceID.allCases {
            XCTAssertEqual(
                availability[source], false,
                "\(source) must be unavailable without a known lens generation"
            )
        }
        XCTAssertFalse(envelope.isLensGenerationKnown)
    }

    func testFutureTimestampClampsToZeroAgeAndStaysAvailable() {
        // A source timestamp slightly ahead of the reference clock (clock skew)
        // must not become "negative age" magic; it is clamped and available.
        let envelope = makeEnvelope(timestamps: [FeatureSourceID.vision: captureTime.addingTimeInterval(0.05)])
        XCTAssertEqual(availabilityAge(envelope, .vision), 0, accuracy: 1e-9)
        XCTAssertEqual(envelope.sourceAvailability(asOf: captureTime)[.vision], true)
    }

    private func availabilityAge(_ envelope: AcceptedFrameEnvelope, _ source: FeatureSourceID) -> TimeInterval {
        envelope.age(of: source, asOf: captureTime) ?? -1
    }

    // MARK: - Frame identity

    func testFrameIDMatchIsWhitespaceTolerantAndMismatchDetects() {
        let envelope = makeEnvelope(timestamps: [:])
        XCTAssertTrue(envelope.matches(frameID: "frame-1"))
        XCTAssertTrue(envelope.matches(frameID: "  frame-1  "))
        XCTAssertFalse(envelope.matches(frameID: "frame-2"))
    }

    // MARK: - Store wiring

    func testStoreSnapshotCarriesLensGenerationAndEnvelope() {
        let store = LatestFrameEvidenceStore()
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, 4, 4, kCVPixelFormatType_32BGRA, nil, &buffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        let pixels = buffer!

        store.publish(pixelBuffer: pixels,
                      orientation: .up,
                      sourceFrameId: "store-frame",
                      capturedAt: captureTime,
                      isStable: true,
                      lensGeneration: 23)

        guard let accepted = store.acceptCurrentSnapshot() else {
            return XCTFail("accepted snapshot expected")
        }
        XCTAssertEqual(store.snapshot()?.lensGeneration, 23)
        XCTAssertEqual(accepted.evidence.lensGeneration, 23,
                       "accepted snapshots preserve the published capture generation")
        let envelope = accepted.evidence.makeEnvelope()
        XCTAssertEqual(envelope.frameID, "store-frame")
        XCTAssertEqual(envelope.lensGeneration, 23)
        XCTAssertTrue(envelope.isLensGenerationKnown)
    }
}
