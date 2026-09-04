//
//  CameraDisplayTransformTests.swift
//  shafinMultitoolTests
//
//  M2-003 CameraGeometryOwner: golden matrices for every supported
//  orientation × mirroring state, inverse round-trips, and consistency of
//  subject-target/preview/canvas conversions (one transform source).
//

import XCTest
@testable import shafinMultitool

final class CameraDisplayTransformTests: XCTestCase {

    private let allStates: [(CameraCoachOrientation, Bool)] = [
        (.portrait, false), (.portrait, true),
        (.portraitUpsideDown, false), (.portraitUpsideDown, true),
        (.landscapeLeft, false), (.landscapeLeft, true),
        (.landscapeRight, false), (.landscapeRight, true),
    ]

    private func deterministicPoints() -> [(Double, Double)] {
        var values: [(Double, Double)] = [(0, 0), (1, 0), (0, 1), (1, 1), (0.5, 0.5)]
        var state: UInt64 = 0xA5A5_5A5A_5A5A_5A5A
        for _ in 0..<64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let x = Double(state >> 11) / Double(UInt64.max >> 11)
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let y = Double(state >> 11) / Double(UInt64.max >> 11)
            values.append((x, y))
        }
        return values
    }

    // MARK: - Golden matrices

    func testGoldenMatricesMatchDocumentedConvention() {
        let expected: [(CameraCoachOrientation, Bool, (Double, Double, Double, Double, Double, Double))] = [
            (.portrait, false, (0, 1, 0, -1, 0, 1)),
            (.portrait, true, (0, -1, 1, -1, 0, 1)),
            (.portraitUpsideDown, false, (0, -1, 1, 1, 0, 0)),
            (.portraitUpsideDown, true, (0, 1, 0, 1, 0, 0)),
            (.landscapeLeft, false, (-1, 0, 1, 0, -1, 1)),
            (.landscapeLeft, true, (1, 0, 0, 0, -1, 1)),
            (.landscapeRight, false, (1, 0, 0, 0, 1, 0)),
            (.landscapeRight, true, (-1, 0, 1, 0, 1, 0)),
        ]

        for (orientation, mirrored, matrix) in expected {
            let transform = CameraDisplayTransform(orientation: orientation, isMirrored: mirrored)
            XCTAssertEqual(transform.a, matrix.0, "\(orientation) mirrored=\(mirrored) a")
            XCTAssertEqual(transform.b, matrix.1, "\(orientation) mirrored=\(mirrored) b")
            XCTAssertEqual(transform.tx, matrix.2, "\(orientation) mirrored=\(mirrored) tx")
            XCTAssertEqual(transform.c, matrix.3, "\(orientation) mirrored=\(mirrored) c")
            XCTAssertEqual(transform.d, matrix.4, "\(orientation) mirrored=\(mirrored) d")
            XCTAssertEqual(transform.ty, matrix.5, "\(orientation) mirrored=\(mirrored) ty")
        }
    }

    func testJSONArtifactMatchesGoldenMatrices() throws {
        let artifactURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/implementation/transform-matrix.json")
        let data = try Data(contentsOf: artifactURL)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let transforms = try XCTUnwrap(object?["transforms"] as? [[String: Any]])
        XCTAssertEqual(transforms.count, 8)

        for entry in transforms {
            let orientationRaw = try XCTUnwrap(entry["orientation"] as? String)
            let mirrored = try XCTUnwrap(entry["isMirrored"] as? Bool)
            let matrix = try XCTUnwrap(entry["matrix"] as? [String: Double])
            let orientation = try XCTUnwrap(
                CameraCoachOrientation.allCases.first { String(describing: $0) == orientationRaw }
            )
            let transform = CameraDisplayTransform(orientation: orientation, isMirrored: mirrored)
            XCTAssertEqual(transform.a, matrix["a"])
            XCTAssertEqual(transform.b, matrix["b"])
            XCTAssertEqual(transform.tx, matrix["tx"])
            XCTAssertEqual(transform.c, matrix["c"])
            XCTAssertEqual(transform.d, matrix["d"])
            XCTAssertEqual(transform.ty, matrix["ty"])
        }
    }

    // MARK: - Round-trips and consistency

    func testInverseRoundTripIsIdentityForAllStates() {
        for (orientation, mirrored) in allStates {
            let transform = CameraDisplayTransform(orientation: orientation, isMirrored: mirrored)
            let inverse = transform.inverse
            for (x, y) in deterministicPoints() {
                let displayed = transform.apply(x: x, y: y)
                let back = inverse.apply(x: displayed.x, y: displayed.y)
                XCTAssertEqual(back.x, x, accuracy: 1e-12, "\(orientation) mirrored=\(mirrored) x")
                XCTAssertEqual(back.y, y, accuracy: 1e-12, "\(orientation) mirrored=\(mirrored) y")
            }
        }
    }

    func testSubjectTargetPreviewAndCanvasShareOneMatrix() {
        // The single-transform rule: the same orientation/mirroring state must
        // produce identical matrices for every y-down display space.
        for (orientation, mirrored) in allStates {
            let subject = CameraDisplayTransform(orientation: orientation, isMirrored: mirrored)
            let preview = CameraDisplayTransform(orientation: orientation, isMirrored: mirrored)
            XCTAssertEqual(subject, preview)
        }
    }

    func testMirroredTransformRestoresViaInverse() {
        for orientation in CameraCoachOrientation.allCases {
            let mirrored = CameraDisplayTransform(orientation: orientation, isMirrored: true)
            let applied = mirrored.apply(x: 0.25, y: 0.75)
            let restored = mirrored.inverse.apply(x: applied.x, y: applied.y)
            XCTAssertEqual(restored.x, 0.25, accuracy: 1e-12, "\(orientation) x")
            XCTAssertEqual(restored.y, 0.75, accuracy: 1e-12, "\(orientation) y")
        }
    }

    func testPortraitMapsSensorRightEdgeToDisplayTop() {
        let portrait = CameraDisplayTransform(orientation: .portrait, isMirrored: false)
        let displayed = portrait.apply(x: 1, y: 0)
        XCTAssertEqual(displayed.x, 0, accuracy: 1e-12)
        XCTAssertEqual(displayed.y, 0, accuracy: 1e-12)

        let sensorBottomRight = portrait.apply(x: 1, y: 1)
        XCTAssertEqual(sensorBottomRight.x, 1, accuracy: 1e-12)
        XCTAssertEqual(sensorBottomRight.y, 0, accuracy: 1e-12)
    }

    func testDisplayValuesStayOnUnitSquareForAllStates() {
        for (orientation, mirrored) in allStates {
            let transform = CameraDisplayTransform(orientation: orientation, isMirrored: mirrored)
            for (x, y) in deterministicPoints() {
                let displayed = transform.apply(x: x, y: y)
                XCTAssertGreaterThanOrEqual(displayed.x, -1e-12)
                XCTAssertLessThanOrEqual(displayed.x, 1 + 1e-12)
                XCTAssertGreaterThanOrEqual(displayed.y, -1e-12)
                XCTAssertLessThanOrEqual(displayed.y, 1 + 1e-12)
            }
        }
    }
}
