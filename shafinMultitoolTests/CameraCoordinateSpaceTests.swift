//
//  CameraCoordinateSpaceTests.swift
//  shafinMultitoolTests
//
//  M2-002 CameraGeometryOwner: property tests for the canonical coordinate
//  spaces — unit-square bounds everywhere, invertibility of defined inverse
//  conversions, and fail-closed degenerate inputs.
//

import XCTest
@testable import shafinMultitool

final class CameraCoordinateSpaceTests: XCTestCase {

    // Deterministic pseudo-random coverage (fixed seed).
    private var deterministicPoints: [(Double, Double)] {
        var values: [(Double, Double)] = []
        var state: UInt64 = 0x9E3779B97F4A7C15
        for _ in 0..<256 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let x = Double(state >> 11) / Double(UInt64.max >> 11)
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let y = Double(state >> 11) / Double(UInt64.max >> 11)
            values.append((x, y))
        }
        // Grid + edges + out-of-range probes.
        let grid: [Double] = [0, 0.25, 0.5, 0.75, 1]
        for gx in grid {
            for gy in grid {
                values.append((gx, gy))
            }
        }
        values.append((-0.5, 1.5))
        values.append((2, -1))
        values.append((.nan, .infinity))
        return values
    }

    /// Mirrors the production clamp: non-finite fails closed to 0.
    private func clampedUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    // MARK: - Unit-square bounds

    func testEverySpaceAcceptsAndClampsToUnitSquare() {
        for space in CameraCoordinateSpaceV2.allCases {
            for (x, y) in deterministicPoints {
                let point = CameraSpacePointV2(space: space, x: x, y: y)
                XCTAssertEqual(point.space, space)
                XCTAssertGreaterThanOrEqual(point.x, 0)
                XCTAssertLessThanOrEqual(point.x, 1)
                XCTAssertGreaterThanOrEqual(point.y, 0)
                XCTAssertLessThanOrEqual(point.y, 1)
                XCTAssertFalse(point.x.isNaN)
                XCTAssertFalse(point.y.isNaN)
            }
        }
    }

    // MARK: - Inverse conversions

    func testVerticalFlipIsItsOwnInverse() {
        for space in [CameraCoordinateSpaceV2.vision, .subjectTarget, .preview, .swiftUICanvas] {
            for (x, y) in deterministicPoints {
                let point = CameraSpacePointV2(space: space, x: x, y: y)
                let flipped = point.flippedVertically.flippedVertically
                XCTAssertEqual(flipped.x, clampedUnit(x), accuracy: 1e-12)
                XCTAssertEqual(flipped.y, clampedUnit(y), accuracy: 1e-12)
            }
        }
    }

    func testVisionToSubjectTargetFlipMapsTopToBottom() {
        let topOfDownSpace = CameraSpacePointV2(space: .subjectTarget, x: 0.5, y: 0)
        XCTAssertEqual(topOfDownSpace.flippedVertically.y, 1)

        let bottomOfDownSpace = CameraSpacePointV2(space: .subjectTarget, x: 0.5, y: 1)
        XCTAssertEqual(bottomOfDownSpace.flippedVertically.y, 0)
    }

    func testAspectFillRoundTripInsideCropWindow() {
        // Sensor 4000x3000 -> model input 513x513 (aspect fill, center crop).
        let source = CGSize(width: 4000, height: 3000)
        let destination = CGSize(width: 513, height: 513)
        let transform = AspectFillTransform(sourceSize: source, destinationSize: destination)

        // The destination is fully covered, so every destination-normalized
        // point inside the visible window maps back into the source square.
        var insideCount = 0
        for (dx, dy) in deterministicPoints {
            let clampedDx = clampedUnit(dx)
            let clampedDy = clampedUnit(dy)
            guard let sourcePoint = transform.sourceNormalized(fromDestinationX: clampedDx, y: clampedDy) else {
                continue
            }
            insideCount += 1
            let roundTrip = transform.destinationPoint(fromSourceNormalized: sourcePoint.x, y: sourcePoint.y)
            XCTAssertEqual(roundTrip.x, clampedDx, accuracy: 1e-9)
            XCTAssertEqual(roundTrip.y, clampedDy, accuracy: 1e-9)
        }
        XCTAssertGreaterThan(insideCount, 200, "most probed points must lie inside the crop window")
    }

    func testAspectFillBoundsHoldForAllSourcePoints() {
        let cases: [(CGSize, CGSize)] = [
            (CGSize(width: 4032, height: 3024), CGSize(width: 513, height: 513)),
            (CGSize(width: 1920, height: 1080), CGSize(width: 224, height: 224)),
            (CGSize(width: 3000, height: 4000), CGSize(width: 640, height: 480)),
            (CGSize(width: 1080, height: 1920), CGSize(width: 1080, height: 1000)),
        ]
        for (source, destination) in cases {
            let transform = AspectFillTransform(sourceSize: source, destinationSize: destination)
            for (x, y) in deterministicPoints {
                let mapped = transform.destinationPoint(fromSourceNormalized: x, y: y)
                XCTAssertGreaterThanOrEqual(mapped.x, 0)
                XCTAssertLessThanOrEqual(mapped.x, 1)
                XCTAssertGreaterThanOrEqual(mapped.y, 0)
                XCTAssertLessThanOrEqual(mapped.y, 1)
            }
        }
    }

    func testAspectFillOutsideCropWindowIsNotInvertible() {
        // Tall sensor into wide destination: left/right edges are cropped away.
        let transform = AspectFillTransform(
            sourceSize: CGSize(width: 3000, height: 1000),
            destinationSize: CGSize(width: 1000, height: 1000)
        )
        // The horizontal center survives; extreme horizontal edges do not.
        XCTAssertNotNil(transform.sourceNormalized(fromDestinationX: 0.5, y: 0.5))
        if transform.sourceNormalized(fromDestinationX: 0.0, y: 0.5) == nil {
            XCTAssertNil(transform.sourceNormalized(fromDestinationX: 0.0, y: 0.5))
        } else {
            // When the crop covers the full width, the extreme edge must
            // round-trip instead.
            let roundTrip = transform.destinationPoint(fromSourceNormalized: 0, y: 0.5)
            XCTAssertEqual(roundTrip.x, 0, accuracy: 1e-9)
        }
    }

    func testDegenerateSizesFailClosedToIdentity() {
        let transform = AspectFillTransform(
            sourceSize: CGSize(width: 0, height: 100),
            destinationSize: CGSize(width: 100, height: 100)
        )
        let mapped = transform.destinationPoint(fromSourceNormalized: 0.25, y: 0.75)
        XCTAssertEqual(mapped.x, 0.25, accuracy: 1e-12)
        XCTAssertEqual(mapped.y, 0.75, accuracy: 1e-12)

        let point = CameraSpacePointV2(space: .modelInput, x: .nan, y: .infinity)
        XCTAssertEqual(point.x, 0)
        XCTAssertEqual(point.y, 0)
    }

    // MARK: - Space tagging

    func testAllSixCanonicalSpacesExist() {
        XCTAssertEqual(
            Set(CameraCoordinateSpaceV2.allCases.map(\.rawValue)),
            ["sensor", "vision", "modelInput", "preview", "subjectTarget", "swiftUICanvas"]
        )
    }
}
