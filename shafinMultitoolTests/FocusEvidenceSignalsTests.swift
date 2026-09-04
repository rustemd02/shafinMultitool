//
//  FocusEvidenceSignalsTests.swift
//  shafinMultitoolTests
//
//  M2-016 TechnicalFeatureOwner: sharp/blur fixtures plus fake focus-state
//  tests — refocus advice is admitted only under the validated joint
//  predicate; unsupported devices fail closed.
//

import XCTest
import CoreVideo
@testable import shafinMultitool

final class FocusEvidenceSignalsTests: XCTestCase {

    private let width = 64
    private let height = 64
    private let subjectRegion = CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3)

    /// Sharp fixture: high-frequency checkerboard (large gradients).
    private func sharpGrid() -> [Double] {
        var grid = [Double](repeating: 0, count: width * height)
        for gy in 0..<height {
            for gx in 0..<width {
                grid[gy * width + gx] = (gx + gy) % 2 == 0 ? 220 : 30
            }
        }
        return grid
    }

    /// Blur fixture: smooth horizontal gradient (near-zero gradients).
    private func blurredGrid() -> [Double] {
        var grid = [Double](repeating: 0, count: width * height)
        for gy in 0..<height {
            for gx in 0..<width {
                grid[gy * width + gx] = 40 + Double(gx) * 2.5
            }
        }
        return grid
    }

    private func withReadableSubject(_ grid: inout [Double], value: Double) {
        for gy in 0..<height {
            for gx in 0..<width {
                let nx = Double(gx) / Double(width)
                let ny = Double(gy) / Double(height)
                if subjectRegion.minX <= nx, nx <= subjectRegion.maxX,
                   subjectRegion.minY <= ny, ny <= subjectRegion.maxY {
                    grid[gy * width + gx] = value
                }
            }
        }
    }

    private func stats(_ grid: [Double]) -> (mean: Double, gradientMean: Double, gradientVariance: Double) {
        let mean = grid.reduce(0, +) / Double(grid.count) / 255.0
        let gradients = FocusEvidenceSignals.gradientStats(lumaGrid: grid, gridWidth: width, gridHeight: height)
        return (mean, gradients.mean, gradients.variance)
    }

    private func analyse(_ grid: [Double], focusState: CameraFocusStateV2) -> FocusEvidence {
        let s = stats(grid)
        return FocusEvidenceSignals.analyse(
            gradientMean: s.gradientMean,
            gradientVariance: s.gradientVariance,
            meanLuma: s.mean,
            focusState: focusState,
            subjectRegion: subjectRegion,
            lumaGrid: grid,
            gridWidth: width,
            gridHeight: height
        )
    }

    // MARK: - Sharp / blur fixtures

    func testSharpFrameIsNotDefocused() {
        var grid = sharpGrid()
        withReadableSubject(&grid, value: 128)
        let evidence = analyse(grid, focusState: .locked)
        XCTAssertFalse(evidence.isDefocused, "checkerboard is sharp")
        XCTAssertFalse(evidence.refocusAdviceAdmitted, "no refocus advice for a sharp frame")
    }

    func testBlurredFrameAdmitsRefocusAdviceWhenFocusLocked() {
        var grid = blurredGrid()
        withReadableSubject(&grid, value: 128)
        let evidence = analyse(grid, focusState: .locked)
        XCTAssertTrue(evidence.isDefocused, "a smooth gradient is defocused")
        XCTAssertTrue(evidence.refocusAdviceAdmitted, "locked focus + measured softness admits advice")
        XCTAssertGreaterThan(evidence.subjectReadability, 0.9)
    }

    // MARK: - Fake focus-state matrix (fail closed)

    func testUnsupportedDeviceNeverAdmitsRefocusAdvice() {
        var blurred = blurredGrid()
        withReadableSubject(&blurred, value: 128)
        let evidence = analyse(blurred, focusState: .unsupported)
        XCTAssertFalse(evidence.refocusAdviceAdmitted,
                       "fixed-focus lenses must never receive refocus advice")
        XCTAssertEqual(evidence.focusState, .unsupported)
    }

    func testAdjustingFocusFailsClosed() {
        var blurred = blurredGrid()
        withReadableSubject(&blurred, value: 128)
        let evidence = analyse(blurred, focusState: .adjusting)
        XCTAssertFalse(evidence.refocusAdviceAdmitted,
                       "mid-sweep measurements cannot honestly claim defocus")
    }

    func testFailedFocusFailsClosed() {
        var blurred = blurredGrid()
        withReadableSubject(&blurred, value: 128)
        let evidence = analyse(blurred, focusState: .failed)
        XCTAssertFalse(evidence.refocusAdviceAdmitted,
                       "unknown focus positions cannot honestly claim defocus")
    }

    func testSharpFrameWithUnsupportedDeviceIsStillNotDefocused() {
        var grid = sharpGrid()
        withReadableSubject(&grid, value: 128)
        let evidence = analyse(grid, focusState: .unsupported)
        XCTAssertFalse(evidence.isDefocused)
        XCTAssertFalse(evidence.refocusAdviceAdmitted)
    }

    // MARK: - Dark-frame fail closed

    func testNearBlackFrameCannotClaimDefocus() {
        var grid = [Double](repeating: 5, count: width * height)
        withReadableSubject(&grid, value: 8)
        let evidence = analyse(grid, focusState: .locked)
        XCTAssertFalse(evidence.isDefocused, "gradients are meaningless in near-black frames")
        XCTAssertFalse(evidence.refocusAdviceAdmitted)
    }

    // MARK: - Subject readability

    func testNoSubjectRegionYieldsZeroReadability() {
        var blurred = blurredGrid()
        withReadableSubject(&blurred, value: 128)
        let s = stats(blurred)
        let evidence = FocusEvidenceSignals.analyse(
            gradientMean: s.gradientMean,
            gradientVariance: s.gradientVariance,
            meanLuma: s.mean,
            focusState: .locked,
            subjectRegion: nil,
            lumaGrid: blurred,
            gridWidth: width,
            gridHeight: height
        )
        XCTAssertEqual(evidence.subjectReadability, 0, accuracy: 1e-12)
    }

    // MARK: - Pixel buffer entry point

    func testPixelBufferEntryPointMatchesContract() {
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
                let value = UInt8((x + y) % 2 == 0 ? 220 : 30)
                pixel.storeBytes(of: value, as: UInt8.self)
                pixel.advanced(by: 1).storeBytes(of: value, as: UInt8.self)
                pixel.advanced(by: 2).storeBytes(of: value, as: UInt8.self)
                pixel.advanced(by: 3).storeBytes(of: UInt8(255), as: UInt8.self)
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer!, [])

        let evidence = FocusEvidenceSignals.analyse(
            pixelBuffer: buffer!, focusState: .locked, subjectRegion: nil
        )
        XCTAssertFalse(evidence.isDefocused, "checkerboard buffer is sharp")
        XCTAssertFalse(evidence.refocusAdviceAdmitted)
    }
}
