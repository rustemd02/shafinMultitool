//
//  FocusEvidenceSignals.swift
//  shafinMultitool
//
//  M2-016 TechnicalFeatureOwner: a conservative focus/readability signal and
//  the camera focus-state contract that gates REFOCUS advice. Refocus advice
//  is admitted ONLY when the measured sharpness and the camera focus state
//  JOINTLY satisfy the validated predicate; unsupported devices fail closed
//  (no advice ever). Raw gradient values never leave this type — consumers
//  see the verdict and the measured evidence summary.
//

import CoreVideo
import Foundation

/// Camera focus-state contract. Derived from AVCaptureDevice capabilities;
/// `unsupported` means the lens cannot focus at all (fixed focus) — refocus
/// advice is permanently disabled there.
enum CameraFocusStateV2: String, Codable, Sendable {
    /// Device has no focus control (fixed-focus lens).
    case unsupported
    /// Focus is settled and locked at a usable position.
    case locked
    /// A focus sweep is in progress; measurements are mid-adjustment.
    case adjusting
    /// The last focus attempt failed; positions are unknown.
    case failed
}

/// The focus/readability verdict for one frame.
struct FocusEvidence: Equatable, Sendable {
    /// Measured frame softness (gradient-mean predicate, aligned with
    /// TechnicalQualityAnalyzer).
    let isDefocused: Bool
    /// Subject-region readability inside the readable luma band (0 when no
    /// subject region is given — fail closed).
    let subjectReadability: Double
    /// The camera focus state this verdict was computed against.
    let focusState: CameraFocusStateV2
    /// The validated joint predicate: refocus advice may be exposed only when
    /// this is true. Unsupported devices and adjusting/failed focus states
    /// never admit advice.
    let refocusAdviceAdmitted: Bool
}

enum FocusEvidenceSignals {

    /// Thresholds aligned with TechnicalQualityAnalyzer.sharpnessIssues.
    static let defocusGradientMeanThreshold: Double = 38
    static let defocusGradientVarianceThreshold: Double = 780
    static let readableLumaLow: Double = 0.15
    static let readableLumaHigh: Double = 0.92

    /// Pure focus/readability analysis over a linear luma grid (0...255,
    /// row-major) plus the precomputed gradient statistics.
    ///
    /// Joint admission predicate (validated): refocus advice is admitted when
    ///   1. the device focus state is `locked` (unsupported/adjusting/failed
    ///      fail closed), AND
    ///   2. the measured frame is defocused by the gradient predicate, AND
    ///   3. there is enough light to measure sharpness at all (mean ≥ 0.12).
    static func analyse(gradientMean: Double,
                        gradientVariance: Double,
                        meanLuma: Double,
                        focusState: CameraFocusStateV2,
                        subjectRegion: CGRect?,
                        lumaGrid: [Double],
                        gridWidth: Int,
                        gridHeight: Int) -> FocusEvidence {
        // Fail closed on insufficient light: gradients are meaningless in
        // near-black frames and no refocus claim is honest there.
        let measurableLight = meanLuma >= 0.12
        let isDefocused = measurableLight
            && ((gradientVariance <= defocusGradientVarianceThreshold
                && gradientMean <= defocusGradientMeanThreshold)
                || gradientMean <= 13)

        let readability = FocusEvidenceSignals.subjectReadability(
            lumaGrid: lumaGrid, gridWidth: gridWidth, gridHeight: gridHeight,
            subjectRegion: subjectRegion
        )

        let admitted: Bool = {
            guard focusState == .locked else { return false }
            guard isDefocused, measurableLight else { return false }
            return true
        }()

        return FocusEvidence(
            isDefocused: isDefocused,
            subjectReadability: readability,
            focusState: focusState,
            refocusAdviceAdmitted: admitted
        )
    }

    /// Convenience entry over a BGRA pixel buffer: computes luma grid, mean
    /// and gradient statistics, then the verdict.
    static func analyse(pixelBuffer: CVPixelBuffer,
                        focusState: CameraFocusStateV2,
                        subjectRegion: CGRect?) -> FocusEvidence {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            return FocusEvidence(isDefocused: false, subjectReadability: 0,
                                 focusState: focusState, refocusAdviceAdmitted: false)
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return FocusEvidence(isDefocused: false, subjectReadability: 0,
                                 focusState: focusState, refocusAdviceAdmitted: false)
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
        let mean = lumaGrid.reduce(0, +) / Double(max(1, lumaGrid.count)) / 255.0
        let gradients = FocusEvidenceSignals.gradientStats(lumaGrid: lumaGrid, gridWidth: width, gridHeight: height)
        return analyse(
            gradientMean: gradients.mean,
            gradientVariance: gradients.variance,
            meanLuma: mean,
            focusState: focusState,
            subjectRegion: subjectRegion,
            lumaGrid: lumaGrid,
            gridWidth: width,
            gridHeight: height
        )
    }

    /// Subject-region readability: readable-band membership fraction.
    static func subjectReadability(lumaGrid: [Double],
                                   gridWidth: Int,
                                   gridHeight: Int,
                                   subjectRegion: CGRect?) -> Double {
        guard let region = subjectRegion, region.width > 0, region.height > 0,
              gridWidth > 0, gridHeight > 0 else { return 0 }
        var subjectSamples = 0
        var readableSamples = 0
        for gy in 0..<gridHeight {
            for gx in 0..<gridWidth {
                let nx = Double(gx) / Double(gridWidth)
                let ny = Double(gy) / Double(gridHeight)
                if region.minX <= nx, nx <= region.maxX,
                   region.minY <= ny, ny <= region.maxY {
                    subjectSamples += 1
                    let luma = min(1, max(0, lumaGrid[gy * gridWidth + gx] / 255.0))
                    if luma >= readableLumaLow, luma <= readableLumaHigh {
                        readableSamples += 1
                    }
                }
            }
        }
        guard subjectSamples > 0 else { return 0 }
        return Double(readableSamples) / Double(subjectSamples)
    }

    /// Gradient statistics over the grid (horizontal + vertical absolute
    /// differences), matching TechnicalQualityAnalyzer's definitions.
    static func gradientStats(lumaGrid: [Double], gridWidth: Int, gridHeight: Int)
        -> (mean: Double, variance: Double) {
        var gradients: [Double] = []
        gradients.reserveCapacity(lumaGrid.count)
        for gy in 0..<gridHeight {
            for gx in 0..<gridWidth {
                let index = gy * gridWidth + gx
                if gx + 1 < gridWidth {
                    gradients.append(abs(lumaGrid[index] - lumaGrid[index + 1]))
                }
                if gy + 1 < gridHeight {
                    gradients.append(abs(lumaGrid[index] - lumaGrid[index + gridWidth]))
                }
            }
        }
        guard !gradients.isEmpty else { return (0, 0) }
        let mean = gradients.reduce(0, +) / Double(gradients.count)
        let variance = gradients.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(gradients.count)
        return (mean, variance)
    }
}
