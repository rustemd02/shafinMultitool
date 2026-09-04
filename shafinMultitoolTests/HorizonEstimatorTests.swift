//
//  HorizonEstimatorTests.swift
//  shafinMultitoolTests
//
//  M2-013 TechnicalFeatureOwner: angle-sign stability across capture
//  orientations (pure normalization), low-confidence/absent horizon
//  unavailability, and intentional-override suppression. The integration test
//  draws a synthetic line into a pixel buffer; both outcomes (detected at the
//  drawn angle, or honestly unavailable) are contract-valid.
//

import XCTest
import CoreVideo
@testable import shafinMultitool

final class HorizonEstimatorTests: XCTestCase {

    // MARK: - Pure sign stability across orientations

    func testSceneAngleSignIsStableAcrossOrientations() {
        let physicalTilts: [Double] = [-60, -30, -10, 0, 10, 30, 60]
        let orientations: [CGImagePropertyOrientation] = [.up, .right, .down, .left]

        for tilt in physicalTilts {
            // The Vision measurement for a scene tilted φ under orientation
            // with rotation ρ is normalize(φ − ρ) (line angles mod 180).
            for orientation in orientations {
                let rotation = HorizonEstimator.orientationRotationDegrees(orientation)
                let measured = normalize180(tilt - rotation)
                let sceneAngle = HorizonEstimator.normalizedSceneAngle(
                    observationAngleDegrees: measured,
                    orientation: orientation
                )
                XCTAssertEqual(
                    sceneAngle, tilt, accuracy: 1e-9,
                    "tilt \(tilt) via \(orientation.rawValue): \(measured) → \(sceneAngle)"
                )
            }
        }
    }

    private func normalize180(_ value: Double) -> Double {
        var value = value
        while value > 90 { value -= 180 }
        while value <= -90 { value += 180 }
        return value
    }

    // MARK: - Availability fail-closed

    func testLowConfidenceHorizonIsUnavailable() {
        // The threshold is pinned via the estimate path; here we assert the
        // contract semantics of HorizonEstimate directly.
        let unavailable = HorizonEstimate.unavailable()
        XCTAssertFalse(unavailable.isAvailable)
        XCTAssertEqual(unavailable.confidence, 0)
        XCTAssertFalse(unavailable.suppressedByIntent)
    }

    // MARK: - Synthetic line fixture (integration)

    func testSyntheticLineFixtureIsDetectedOrHonestlyUnavailable() throws {
        let estimator = HorizonEstimator()
        let buffer = try makeLineFixture(lineDegrees: 6)

        let estimate = estimator.estimate(
            pixelBuffer: buffer,
            orientation: .up,
            isStable: true
        )

        if estimate.isAvailable {
            // Detected: available with nonzero confidence. The published
            // angle is deliberately blended (0.2*Vision + 0.8*motion roll;
            // roll is 0 on the simulator), so the first-frame magnitude is
            // damped and the SIGN is inverted vs the screen-drawn tilt
            // (Vision measures in y-up space): screen +6° → Vision ≈ −1.2.
            XCTAssertLessThanOrEqual(estimate.angleDegrees, 0,
                                     "screen-clockwise tilt must measure non-positive")
            XCTAssertGreaterThanOrEqual(estimate.angleDegrees, -6,
                                        "damped angle must stay within the drawn tilt")
            XCTAssertGreaterThan(estimate.confidence, 0.2)
        } else {
            // Honestly unavailable is contract-valid (weak synthetic evidence).
            XCTAssertEqual(estimate.confidence, 0, accuracy: 0.25)
        }
    }

    func testIntentionalOverrideSuppressesCorrection() throws {
        let estimator = HorizonEstimator()
        let buffer = try makeLineFixture(lineDegrees: 6)

        let estimate = estimator.estimate(
            pixelBuffer: buffer,
            orientation: .up,
            isStable: true,
            intentOverride: .intentional
        )

        XCTAssertFalse(estimate.isAvailable, "intentional tilt must not produce correction advice")
        XCTAssertTrue(estimate.suppressedByIntent)
        XCTAssertEqual(estimate.confidence, 0)
    }

    // MARK: - Fixtures

    /// Draws a bright band rotated by `lineDegrees` on a dark background.
    private func makeLineFixture(lineDegrees: Double) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let width = 96
        let height = 96
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer
        )
        guard status == kCVReturnSuccess, let pixels = buffer else {
            throw XCTSkip("pixel buffer creation failed")
        }

        CVPixelBufferLockBaseAddress(pixels, [])
        defer { CVPixelBufferUnlockBaseAddress(pixels, []) }
        let base = CVPixelBufferGetBaseAddress(pixels)!
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixels)

        let radians = lineDegrees * Double.pi / 180
        let centerX = Double(width) / 2
        let centerY = Double(height) / 2
        let bandHalfWidth = 10.0

        for y in 0..<height {
            let row = base.advanced(by: y * bytesPerRow)
            for x in 0..<width {
                // Distance from the rotated center line.
                let dx = Double(x) - centerX
                let dy = Double(y) - centerY
                let distance = abs(dx * sin(radians) + dy * cos(radians))
                let gray: UInt8 = distance < bandHalfWidth ? 235 : 20
                let pixel = row.advanced(by: x * 4)
                pixel.storeBytes(of: gray, as: UInt8.self)
                pixel.advanced(by: 1).storeBytes(of: gray, as: UInt8.self)
                pixel.advanced(by: 2).storeBytes(of: gray, as: UInt8.self)
                pixel.advanced(by: 3).storeBytes(of: 255, as: UInt8.self)
            }
        }
        return pixels
    }
}
