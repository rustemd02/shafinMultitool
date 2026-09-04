//
//  ExposureFeatureSignals.swift
//  shafinMultitool
//
//  M2-014 TechnicalFeatureOwner: measurable underexposure, overexposure,
//  clipping and SUBJECT READABILITY signals with explicit predicates. These
//  are safe-advice features: exposure issues are declared only through these
//  predicates — never inferred solely from a global mean or an aesthetic
//  score — and the under/over pair is contradiction-checked.
//

import CoreVideo
import Foundation

struct ExposureFeatures: Equatable, Sendable {
    /// Global mean luma below the underexposure predicate.
    let isUnderexposed: Bool
    /// Clipped/hotspot predicates satisfied.
    let isOverexposed: Bool
    /// Fraction of the frame at/above the clipping luma.
    let clippingRatio: Double
    /// Fraction of subject-region samples inside the readable luma band
    /// [0.15, 0.92]. 0 when no subject region is given (fail closed: no
    /// region means no readability claim).
    let subjectReadability: Double
    /// True when under- and overexposure are not both declared.
    let isContradictionFree: Bool
}

enum ExposureFeatureSignals {

    /// Luma thresholds aligned with TechnicalQualityAnalyzer predicates.
    static let overexposureClippedRatio: Double = 0.055
    static let overexposureMeanLuma: Double = 0.36
    static let underexposureMeanLuma: Double = 0.18
    static let underexposureDarkRatio: Double = 0.35
    static let readableLumaLow: Double = 0.15
    static let readableLumaHigh: Double = 0.92

    /// Pure analysis over a linear luma grid (row-major, 0...255).
    /// `subjectRegion` is normalized (x, y, w, h) in the same top-left y-down
    /// framing as the grid.
    static func analyse(lumaGrid: [Double],
                        width: Int,
                        height: Int,
                        subjectRegion: CGRect?) -> ExposureFeatures {
        let pixelCount = Double(lumaGrid.count)
        guard pixelCount > 0, width > 0, height > 0 else {
            return ExposureFeatures(
                isUnderexposed: false, isOverexposed: false, clippingRatio: 0,
                subjectReadability: 0, isContradictionFree: true
            )
        }

        let unitLumas = lumaGrid.map { min(1, max(0, $0 / 255.0)) }
        let meanLuma = unitLumas.reduce(0, +) / pixelCount
        let darkRatio = Double(unitLumas.filter { $0 < 25.0 / 255.0 }.count) / pixelCount
        let clippedRatio = Double(unitLumas.filter { $0 > 235.0 / 255.0 }.count) / pixelCount
        let hotspotRatio = Double(unitLumas.filter { $0 > 220.0 / 255.0 }.count) / pixelCount

        // Explicit predicates — the same shape TechnicalQualityAnalyzer uses,
        // exposed here so advice never infers them from a single mean.
        let underexposure = (meanLuma <= 0.36 && darkRatio >= 0.46)
            || (meanLuma <= underexposureMeanLuma && darkRatio >= underexposureDarkRatio)
        let overexposure = (clippedRatio >= overexposureClippedRatio && meanLuma >= overexposureMeanLuma)
            || hotspotRatio >= 0.060 && meanLuma >= 0.38

        // Subject readability: readable-band membership inside the region.
        var subjectSamples = 0
        var readableSamples = 0
        if let region = subjectRegion, region.width > 0, region.height > 0 {
            for gridY in 0..<height {
                for gridX in 0..<width {
                    let nx = Double(gridX) / Double(width)
                    let ny = Double(gridY) / Double(height)
                    if region.minX <= nx, nx <= region.maxX,
                       region.minY <= ny, ny <= region.maxY {
                        subjectSamples += 1
                        let luma = unitLumas[gridY * width + gridX]
                        if luma >= readableLumaLow, luma <= readableLumaHigh {
                            readableSamples += 1
                        }
                    }
                }
            }
        }
        let readability = subjectSamples > 0
            ? Double(readableSamples) / Double(subjectSamples)
            : 0

        return ExposureFeatures(
            isUnderexposed: underexposure,
            isOverexposed: overexposure,
            clippingRatio: clippedRatio,
            subjectReadability: readability,
            isContradictionFree: !(underexposure && overexposure)
        )
    }

    /// Convenience entry over a BGRA pixel buffer.
    static func analyse(pixelBuffer: CVPixelBuffer, subjectRegion: CGRect?) -> ExposureFeatures {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            return ExposureFeatures(
                isUnderexposed: false, isOverexposed: false, clippingRatio: 0,
                subjectReadability: 0, isContradictionFree: true
            )
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return ExposureFeatures(
                isUnderexposed: false, isOverexposed: false, clippingRatio: 0,
                subjectReadability: 0, isContradictionFree: true
            )
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        var lumaGrid: [Double] = []
        lumaGrid.reserveCapacity(width * height)
        for y in 0..<height {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let offset = x * 4
                let red = Double(row[offset + 2])
                let green = Double(row[offset + 1])
                let blue = Double(row[offset])
                lumaGrid.append((0.2126 * red) + (0.7152 * green) + (0.0722 * blue))
            }
        }
        return analyse(lumaGrid: lumaGrid, width: width, height: height, subjectRegion: subjectRegion)
    }

}
