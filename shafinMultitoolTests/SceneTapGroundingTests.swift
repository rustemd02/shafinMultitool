//
//  SceneTapGroundingTests.swift
//  shafinMultitool
//
//  CC-O02 wiring contract tests: the tap-naming decision core
//  (SceneTapEvidence.namesTrackedInstance) and the inverse preview-layer
//  point conversion (CameraPreviewRegionMapper.scenePoint). The production
//  gesture itself requires a physical camera and stays a physical gate.
//

import XCTest
@testable import shafinMultitool

final class SceneTapGroundingTests: XCTestCase {

    private func instance(
        x: Double, y: Double, width: Double, height: Double, trackID: String = "sir_g1_1"
    ) -> (trackID: String, region: NormalizedRect) {
        (trackID, NormalizedRect(x: x, y: y, width: width, height: height))
    }

    // MARK: - SceneTapEvidence.namesTrackedInstance

    func testFreshTapInsideTrackedInstanceNamesIt() {
        let evidence = SceneTapEvidence(
            sceneX: 0.5, sceneY: 0.5,
            capturedAt: Date(timeIntervalSinceNow: -0.05)
        )
        XCTAssertTrue(evidence.namesTrackedInstance(
            in: [instance(x: 0.4, y: 0.4, width: 0.2, height: 0.2)],
            now: Date()
        ))
    }

    func testFreshTapInEmptySpaceNamesNothing() {
        let evidence = SceneTapEvidence(
            sceneX: 0.95, sceneY: 0.95,
            capturedAt: Date(timeIntervalSinceNow: -0.05)
        )
        XCTAssertFalse(evidence.namesTrackedInstance(
            in: [instance(x: 0.4, y: 0.4, width: 0.2, height: 0.2)],
            now: Date()
        ))
    }

    func testStaleTapDoesNotNameEvenInsideInstance() {
        let evidence = SceneTapEvidence(
            sceneX: 0.5, sceneY: 0.5,
            capturedAt: Date(timeIntervalSinceNow: -1.0)
        )
        XCTAssertFalse(evidence.namesTrackedInstance(
            in: [instance(x: 0.4, y: 0.4, width: 0.2, height: 0.2)],
            now: Date()
        ))
    }

    func testTapFromTheFutureDoesNotName() {
        let evidence = SceneTapEvidence(
            sceneX: 0.5, sceneY: 0.5,
            capturedAt: Date(timeIntervalSinceNow: 0.5)
        )
        XCTAssertFalse(evidence.namesTrackedInstance(
            in: [instance(x: 0.4, y: 0.4, width: 0.2, height: 0.2)],
            now: Date()
        ))
    }

    func testFreshTapHonoursTouchSlopAroundRegion() {
        // Region (0.25, 0.25, 0.1, 0.1) inflated by the 0.04 slop covers
        // x in [0.21, 0.39]: (0.35, 0.3) is outside the raw region but hits.
        let evidence = SceneTapEvidence(
            sceneX: 0.35, sceneY: 0.3,
            capturedAt: Date(timeIntervalSinceNow: -0.02)
        )
        XCTAssertTrue(evidence.namesTrackedInstance(
            in: [instance(x: 0.25, y: 0.25, width: 0.1, height: 0.1)],
            now: Date()
        ))
        // But 0.05 past the edge does not hit.
        let outside = SceneTapEvidence(
            sceneX: 0.4, sceneY: 0.3,
            capturedAt: Date(timeIntervalSinceNow: -0.02)
        )
        XCTAssertFalse(outside.namesTrackedInstance(
            in: [instance(x: 0.25, y: 0.25, width: 0.1, height: 0.1)],
            now: Date()
        ))
    }

    // MARK: - CameraPreviewRegionMapper.scenePoint

    func testScenePointUndoesTheMetadataYFlip() {
        // Identity converter: the layer rect equals the metadata rect, so the
        // only remaining step is the upper-left metadata y-flip.
        let point = CameraPreviewRegionMapper.scenePoint(
            forLayerPoint: CGPoint(x: 100, y: 200),
            using: { $0 }
        )
        XCTAssertEqual(point?.x ?? -1, 100, accuracy: 0.001)
        XCTAssertEqual(point?.y ?? -1, 1.0 - 200, accuracy: 0.001)
    }

    func testScenePointUsesTheConvertedRectCenter() {
        // A converter that maps every probe to a fixed metadata rect: the
        // scene point must be that rect's center, y-flipped.
        let point = CameraPreviewRegionMapper.scenePoint(
            forLayerPoint: CGPoint(x: 42, y: 17),
            using: { _ in CGRect(x: 0.2, y: 0.3, width: 0.1, height: 0.2) }
        )
        XCTAssertEqual(point?.x ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(point?.y ?? -1, 1.0 - 0.4, accuracy: 0.0001)
    }

    func testScenePointRejectsDegenerateConversion() {
        let point = CameraPreviewRegionMapper.scenePoint(
            forLayerPoint: CGPoint(x: 10, y: 10),
            using: { _ in .null }
        )
        XCTAssertNil(point)
    }

    func testScenePointRoundTripsThroughTheRegionMapping() {
        // A scene region mapped to metadata with the production y-flip, then
        // its center tapped and inverted, must return the region center.
        let region = NormalizedRect(x: 0.3, y: 0.4, width: 0.2, height: 0.2)
        let metadata = CameraPreviewRegionMapper.metadataOutputRect(for: region)
        XCTAssertNotNil(metadata)
        // Pretend the layer coordinates equal metadata coordinates.
        let point = CameraPreviewRegionMapper.scenePoint(
            forLayerPoint: CGPoint(x: metadata!.midX, y: metadata!.midY),
            using: { $0 }
        )
        XCTAssertEqual(point?.x ?? -1, region.x + region.width / 2, accuracy: 0.0001)
        XCTAssertEqual(point?.y ?? -1, region.y + region.height / 2, accuracy: 0.0001)
    }
}
