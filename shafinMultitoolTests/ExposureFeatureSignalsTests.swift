//
//  ExposureFeatureSignalsTests.swift
//  shafinMultitoolTests
//
//  M2-014 TechnicalFeatureOwner: technical fixture matrix with
//  expected/forbidden flags over synthetic luma grids and BGRA buffers.
//

import XCTest
import CoreVideo
@testable import shafinMultitool

final class ExposureFeatureSignalsTests: XCTestCase {

    private let width = 64
    private let height = 64

    /// Builds a luma grid; optional dark/bright patches are axis-aligned
    /// normalized rects.
    private func grid(background: UInt8,
                      darkPatch: CGRect? = nil,
                      brightPatch: CGRect? = nil) -> [Double] {
        var grid = [Double](repeating: Double(background), count: width * height)
        func apply(_ rect: CGRect, _ value: Double) {
            for gy in 0..<height {
                for gx in 0..<width {
                    let nx = Double(gx) / Double(width)
                    let ny = Double(gy) / Double(height)
                    if rect.minX <= nx, nx <= rect.maxX, rect.minY <= ny, ny <= rect.maxY {
                        grid[gy * width + gx] = value
                    }
                }
            }
        }
        if let darkPatch { apply(darkPatch, 12) }
        if let brightPatch { apply(brightPatch, 250) }
        return grid
    }

    private let subjectRegion = CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3)

    // MARK: - Fixture matrix

    func testDarkFrameIsUnderexposedAndOverexposureIsForbidden() {
        let features = ExposureFeatureSignals.analyse(
            lumaGrid: grid(background: 12), width: width, height: height,
            subjectRegion: subjectRegion
        )
        XCTAssertTrue(features.isUnderexposed, "expected: underexposure")
        XCTAssertFalse(features.isOverexposed, "forbidden: overexposure on a dark frame")
        XCTAssertTrue(features.isContradictionFree)
    }

    func testBrightClippedFrameIsOverexposedAndUnderexposureIsForbidden() {
        let features = ExposureFeatureSignals.analyse(
            lumaGrid: grid(background: 250), width: width, height: height,
            subjectRegion: subjectRegion
        )
        XCTAssertTrue(features.isOverexposed, "expected: overexposure")
        XCTAssertTrue(features.clippingRatio > 0.9)
        XCTAssertFalse(features.isUnderexposed, "forbidden: underexposure on a blown-out frame")
        XCTAssertTrue(features.isContradictionFree)
    }

    func testNormalFrameDeclaresNeither() {
        let features = ExposureFeatureSignals.analyse(
            lumaGrid: grid(background: 128), width: width, height: height,
            subjectRegion: subjectRegion
        )
        XCTAssertFalse(features.isUnderexposed)
        XCTAssertFalse(features.isOverexposed)
        XCTAssertTrue(features.isContradictionFree)
        XCTAssertEqual(features.clippingRatio, 0, accuracy: 1e-9)
    }

    func testBoundaryMeanTieBreakResolvesToUnderexposureDeterministically() {
        // Engineered frame at the predicates' shared boundary: mean ≈ 0.3598
        // (just below 0.36) with 46% deep shadows and 8% clipped pixels. The
        // under/over predicates can only coincide exactly AT the boundary —
        // unattainable on a discrete grid — so the deterministic tie-break is
        // underexposure, and the contradiction flag stays true.
        var grid = [Double](repeating: 0, count: width * height)
        let midValue = 144.0
        for gy in 0..<height {
            for gx in 0..<width {
                let fraction = Double(gx) / Double(width)
                let value: Double
                if fraction < 0.46 {
                    value = 12        // deep shadow
                } else if fraction < 0.54 {
                    value = 250       // clipped bright
                } else {
                    value = midValue  // mid gray
                }
                grid[gy * width + gx] = value
            }
        }
        let features = ExposureFeatureSignals.analyse(
            lumaGrid: grid, width: width, height: height, subjectRegion: nil
        )
        XCTAssertTrue(features.isUnderexposed, "deep shadows + mean <= 0.36 must fire underexposure")
        XCTAssertFalse(features.isOverexposed, "mean below 0.36 must not fire overexposure")
        XCTAssertTrue(features.isContradictionFree)
        XCTAssertGreaterThan(features.clippingRatio, 0.05, "clipped pixels are still counted")
    }

    // MARK: - Subject readability

    func testReadableSubjectHasHighReadabilityAndDarkSubjectLow() {
        // Bright background, mid subject patch centered: readable band.
        var lumaGrid = grid(background: 180)
        let dark = CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3)
        for gy in 0..<height {
            for gx in 0..<width {
                let nx = Double(gx) / Double(width)
                let ny = Double(gy) / Double(height)
                if dark.minX <= nx, nx <= dark.maxX, dark.minY <= ny, ny <= dark.maxY {
                    lumaGrid[gy * width + gx] = 120
                }
            }
        }
        let readable = ExposureFeatureSignals.analyse(
            lumaGrid: lumaGrid, width: width, height: height, subjectRegion: subjectRegion
        )
        XCTAssertGreaterThan(readable.subjectReadability, 0.9)

        // A blown-out subject patch: readability collapses.
        var blown = grid(background: 60)
        let bright = CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3)
        for gy in 0..<height {
            for gx in 0..<width {
                let nx = Double(gx) / Double(width)
                let ny = Double(gy) / Double(height)
                if bright.minX <= nx, nx <= bright.maxX, bright.minY <= ny, ny <= bright.maxY {
                    blown[gy * width + gx] = 255
                }
            }
        }
        let unreadable = ExposureFeatureSignals.analyse(
            lumaGrid: blown, width: width, height: height, subjectRegion: subjectRegion
        )
        XCTAssertLessThan(unreadable.subjectReadability, 0.1)
    }

    func testNoSubjectRegionFailsClosedToZeroReadability() {
        let features = ExposureFeatureSignals.analyse(
            lumaGrid: grid(background: 128), width: width, height: height,
            subjectRegion: nil
        )
        XCTAssertEqual(features.subjectReadability, 0, accuracy: 1e-12)
    }

    // MARK: - BGRA entry point

    func testPixelBufferEntryPointMatchesGridSemantics() {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        CVPixelBufferLockBaseAddress(buffer!, [])
        let base = CVPixelBufferGetBaseAddress(buffer!)!
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer!)
        for y in 0..<height {
            let row = base.advanced(by: y * bytesPerRow)
            for x in 0..<width {
                let pixel = row.advanced(by: x * 4)
                pixel.storeBytes(of: UInt8(250), as: UInt8.self)
                pixel.advanced(by: 1).storeBytes(of: UInt8(250), as: UInt8.self)
                pixel.advanced(by: 2).storeBytes(of: UInt8(250), as: UInt8.self)
                pixel.advanced(by: 3).storeBytes(of: UInt8(255), as: UInt8.self)
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer!, [])

        let features = ExposureFeatureSignals.analyse(pixelBuffer: buffer!, subjectRegion: nil)
        XCTAssertTrue(features.isOverexposed)
        XCTAssertFalse(features.isUnderexposed)
    }
}
