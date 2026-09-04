//
//  LightingEstimatorTests.swift
//  shafinMultitoolTests
//
//  M2-012 TechnicalFeatureOwner: deterministic pixel-buffer fixtures —
//  front light, backlight, low-key, clipping, uniform — with numeric golden
//  metrics. Background means exclude subject pixels, all outputs are finite,
//  and no subject-underlit/subject-overexposed contradiction is emitted.
//

import XCTest
import CoreVideo
@testable import shafinMultitool

final class LightingEstimatorTests: XCTestCase {

    private let estimator = LightingEstimator()
    private let frameSize = (width: 64, height: 64)

    /// Builds a solid-color frame with an optional rectangular subject patch.
    /// Fill colors are given as luma via gray values (r=g=b).
    private func makeFrame(backgroundGray: UInt8,
                           subjectGray: UInt8?,
                           subjectRect: CGRect = CGRect(x: 0.375, y: 0.375, width: 0.25, height: 0.25)) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            frameSize.width,
            frameSize.height,
            kCVPixelFormatType_32BGRA,
            nil,
            &buffer
        )
        precondition(status == kCVReturnSuccess)
        let pixels = buffer!

        CVPixelBufferLockBaseAddress(pixels, [])
        defer { CVPixelBufferUnlockBaseAddress(pixels, []) }
        let base = CVPixelBufferGetBaseAddress(pixels)!
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixels)
        let width = CVPixelBufferGetWidth(pixels)
        let height = CVPixelBufferGetHeight(pixels)

        let row = frameSize.height
        let subjectX = Int(subjectRect.minX * CGFloat(width))
        let subjectY = Int((1 - subjectRect.maxY) * CGFloat(row)) // CI y-up flip
        let subjectW = Int(subjectRect.width * CGFloat(width))
        let subjectH = Int(subjectRect.height * CGFloat(row))

        for y in 0..<height {
            let rowBase = base.advanced(by: y * bytesPerRow)
            for x in 0..<width {
                let inSubject = subjectGray != nil
                    && x >= subjectX && x < subjectX + subjectW
                    && y >= subjectY && y < subjectY + subjectH
                let gray = inSubject ? subjectGray! : backgroundGray
                let pixel = rowBase.advanced(by: x * 4)
                pixel.storeBytes(of: gray, as: UInt8.self)          // B
                pixel.advanced(by: 1).storeBytes(of: gray, as: UInt8.self) // G
                pixel.advanced(by: 2).storeBytes(of: gray, as: UInt8.self) // R
                pixel.advanced(by: 3).storeBytes(of: 255, as: UInt8.self)  // A
            }
        }
        return pixels
    }

    private let neutralSubjectRect = CGRect(x: 0.375, y: 0.375, width: 0.25, height: 0.25)

    // MARK: - Front light (bright subject on dark background)

    func testFrontLightSubjectBrighterThanBackground() {
        let features = estimator.analyse(
            pixelBuffer: makeFrame(backgroundGray: 30, subjectGray: 200),
            subjectBoundingBox: neutralSubjectRect
        )
        XCTAssertGreaterThan(features.subjectMeanLuma, features.backgroundMeanLuma)
        XCTAssertEqual(features.backlightIndex, 0, accuracy: 1e-9)
        // Front light: the subject is brighter, so subject - background > 0.
        XCTAssertGreaterThan(features.subjectToBackgroundDelta, 0)
        XCTAssertLessThan(features.subjectClippedBrightRatio, 0.5)
    }

    // MARK: - Backlight (dark subject on bright background)

    func testBacklightDetectsDarkSubjectOnBrightBackground() {
        let features = estimator.analyse(
            pixelBuffer: makeFrame(backgroundGray: 210, subjectGray: 40),
            subjectBoundingBox: neutralSubjectRect
        )
        XCTAssertGreaterThan(features.backlightIndex, 0.1, "backlit subject must raise the index")
        XCTAssertGreaterThan(features.backgroundMeanLuma, features.subjectMeanLuma)
    }

    func testBackgroundMeanExcludesSubjectPixels() {
        // Bright background with a LARGE dark subject (36% of the frame,
        // CENTERED so the fixture is invariant to the Core Image y-orientation
        // convention): if the subject leaked into the background mean, the
        // mean would sag noticeably. Exclusion keeps it near pure background.
        let largeSubject = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        let features = estimator.analyse(
            pixelBuffer: makeFrame(backgroundGray: 210, subjectGray: 20, subjectRect: largeSubject),
            subjectBoundingBox: largeSubject
        )
        XCTAssertGreaterThan(features.backgroundMeanLuma, 0.75,
                             "background mean must exclude the dark subject pixels")
    }

    // MARK: - Low key

    func testLowKeyFrameProducesFiniteNearZeroMetrics() {
        let features = estimator.analyse(
            pixelBuffer: makeFrame(backgroundGray: 5, subjectGray: 10),
            subjectBoundingBox: neutralSubjectRect
        )
        for value in [features.backlightIndex, features.keyFillRatio, features.exposureBiasHint,
                      features.subjectMeanLuma, features.backgroundMeanLuma,
                      features.subjectToBackgroundDelta, features.subjectClippedBrightRatio,
                      features.backgroundHotspotRatio] {
            XCTAssertTrue(value.isFinite, "all outputs must be finite")
        }
        XCTAssertLessThan(features.subjectMeanLuma, 0.1)
        XCTAssertLessThan(features.backgroundMeanLuma, 0.1)
    }

    // MARK: - Clipping + contradiction guard

    func testClippedSubjectSuppressesBacklightClaim() {
        // White subject on mid-gray background: the subject is blown out.
        // An unguarded estimator could emit subject-underlit (bg > subject is
        // false here, but the guard must also hold when ratios are high) —
        // the core check: heavy clipping forces backlightIndex to 0.
        let features = estimator.analyse(
            pixelBuffer: makeFrame(backgroundGray: 128, subjectGray: 255),
            subjectBoundingBox: neutralSubjectRect
        )
        XCTAssertGreaterThan(features.subjectClippedBrightRatio, 0.9, "white subject is fully clipped")
        XCTAssertEqual(features.backlightIndex, 0, accuracy: 1e-9,
                       "a blown-out subject must not be claimed underlit")
    }

    // MARK: - Uniform frame

    func testUniformFrameIsNeutral() {
        let features = estimator.analyse(
            pixelBuffer: makeFrame(backgroundGray: 120, subjectGray: 120),
            subjectBoundingBox: neutralSubjectRect
        )
        XCTAssertEqual(features.backlightIndex, 0, accuracy: 1e-9)
        XCTAssertEqual(features.keyFillRatio, 1, accuracy: 0.05)
        XCTAssertEqual(features.subjectToBackgroundDelta, 0, accuracy: 0.02)
        XCTAssertEqual(features.subjectClippedBrightRatio, 0, accuracy: 1e-9)
        XCTAssertEqual(features.backgroundHotspotRatio, 0, accuracy: 1e-9)
    }

    // MARK: - Degenerate subject box fails closed and stays finite

    func testDegenerateSubjectBoxKeepsAllOutputsFinite() {
        let features = estimator.analyse(
            pixelBuffer: makeFrame(backgroundGray: 100, subjectGray: 200),
            subjectBoundingBox: .zero
        )
        for value in [features.backlightIndex, features.keyFillRatio, features.exposureBiasHint,
                      features.subjectMeanLuma, features.backgroundMeanLuma,
                      features.subjectToBackgroundDelta, features.subjectClippedBrightRatio,
                      features.backgroundHotspotRatio] {
            XCTAssertTrue(value.isFinite, "all outputs must be finite for degenerate input")
        }
        XCTAssertEqual(features.subjectMeanLuma, 0.5, accuracy: 1e-6,
                       "no subject samples must fail closed to neutral")
    }
}
