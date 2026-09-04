//
//  LightingEstimator.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import CoreImage
import CoreGraphics

struct LightingFeatures {
    let backlightIndex: CGFloat
    let keyFillRatio: CGFloat
    let exposureBiasHint: CGFloat
    let subjectMeanLuma: CGFloat
    let backgroundMeanLuma: CGFloat
    let subjectToBackgroundDelta: CGFloat
    let subjectClippedBrightRatio: CGFloat
    let backgroundHotspotRatio: CGFloat
}

final class LightingEstimator {
    private let context = CIContext()

    /// Subject samples below this fraction of the grid leave too little
    /// subject evidence; subject metrics then fail closed to neutral values.
    private static let minimumSubjectSamples = 8
    /// Background samples below this count fall back to the whole-frame mean
    /// (documented approximation for subjects filling nearly the whole frame).
    private static let minimumBackgroundSamples = 64
    /// A subject this heavily clipped cannot simultaneously be claimed
    /// underlit/backlit — the backlight claim is suppressed.
    private static let clippingContradictionThreshold: CGFloat = 0.02
    private static let sampleGridWidth = 32
    private static let sampleGridHeight = 32

    func analyse(pixelBuffer: CVPixelBuffer,
                 subjectBoundingBox: CGRect) -> LightingFeatures {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = image.extent

        // One deterministic grid sample over the whole frame; each sample is
        // assigned to subject or background by its center.
        let samples = Self.sampleGrid(image: image,
                                      extent: extent,
                                      context: context,
                                      gridWidth: Self.sampleGridWidth,
                                      gridHeight: Self.sampleGridHeight)

        let subjectRect = Self.subjectRect(normalized: subjectBoundingBox, extent: extent)
        var subjectLumas: [Double] = []
        var backgroundLumas: [Double] = []
        var subjectClipped = 0
        var backgroundHotspots = 0

        for sample in samples {
            let inSubject = subjectRect.contains(sample.location)
            if inSubject {
                subjectLumas.append(sample.luma)
                if sample.luma >= 0.92 { subjectClipped += 1 }
            } else {
                backgroundLumas.append(sample.luma)
                if sample.luma >= 0.82 { backgroundHotspots += 1 }
            }
        }

        // Subject metrics (fail closed to neutral when evidence is missing).
        let subjectMean: Double
        let subjectClippedRatio: Double
        if subjectLumas.count >= Self.minimumSubjectSamples {
            subjectMean = subjectLumas.reduce(0, +) / Double(subjectLumas.count)
            subjectClippedRatio = Double(subjectClipped) / Double(subjectLumas.count)
        } else {
            subjectMean = 0.5
            subjectClippedRatio = 0
        }

        // Background metrics EXCLUDE subject pixels. When the subject mask
        // leaves almost no background samples, fall back to the whole-frame
        // mean (documented approximation; ratios stay background-only).
        let backgroundMean: Double
        let backgroundHotspotRatio: Double
        if backgroundLumas.count >= Self.minimumBackgroundSamples {
            backgroundMean = backgroundLumas.reduce(0, +) / Double(backgroundLumas.count)
            backgroundHotspotRatio = Double(backgroundHotspots) / Double(backgroundLumas.count)
        } else {
            let allLumas = samples.map(\.luma)
            backgroundMean = allLumas.isEmpty ? 0.5 : allLumas.reduce(0, +) / Double(allLumas.count)
            backgroundHotspotRatio = 0
        }

        // Contradiction guard: a clipped (blown-out) subject cannot also be
        // claimed underlit — the backlight claim is suppressed.
        let clippedContradicts = subjectClippedRatio >= Double(Self.clippingContradictionThreshold)
        let rawBacklight = max(0, backgroundMean - subjectMean)
        let backlightIndex = clippedContradicts ? 0 : rawBacklight
        let keyFillRatio = subjectMean > 0 ? backgroundMean / subjectMean : 1
        let exposureBias = log2(max(subjectMean, 1e-3)) - log2(0.5)

        return LightingFeatures(
            backlightIndex: CGFloat(Self.finite(backlightIndex)),
            keyFillRatio: CGFloat(Self.finite(keyFillRatio)),
            exposureBiasHint: CGFloat(Self.finite(exposureBias)),
            subjectMeanLuma: CGFloat(Self.finite(subjectMean)),
            backgroundMeanLuma: CGFloat(Self.finite(backgroundMean)),
            subjectToBackgroundDelta: CGFloat(Self.finite(subjectMean - backgroundMean)),
            subjectClippedBrightRatio: CGFloat(Self.finite(subjectClippedRatio)),
            backgroundHotspotRatio: CGFloat(Self.finite(backgroundHotspotRatio))
        )
    }

    // MARK: - Sampling

    private struct GridSample {
        let location: CGPoint
        let luma: Double
    }

    private static func sampleGrid(image: CIImage,
                                   extent: CGRect,
                                   context: CIContext,
                                   gridWidth: Int,
                                   gridHeight: Int) -> [GridSample] {
        var pixels = [UInt8](repeating: 0, count: gridWidth * gridHeight * 4)
        let rowBytes = gridWidth * 4
        let transform = CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
            .scaledBy(x: CGFloat(gridWidth) / extent.width,
                      y: CGFloat(gridHeight) / extent.height)
        context.render(image.transformed(by: transform),
                       toBitmap: &pixels,
                       rowBytes: rowBytes,
                       bounds: CGRect(x: 0, y: 0, width: gridWidth, height: gridHeight),
                       format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())

        var samples: [GridSample] = []
        samples.reserveCapacity(gridWidth * gridHeight)
        for row in 0..<gridHeight {
            for column in 0..<gridWidth {
                // Grid sample centers in EXTENT coordinates (CI, y-up).
                let location = CGPoint(
                    x: extent.minX + (CGFloat(column) + 0.5) * extent.width / CGFloat(gridWidth),
                    y: extent.minY + (CGFloat(row) + 0.5) * extent.height / CGFloat(gridHeight)
                )
                let offset = (row * gridWidth + column) * 4
                let red = Double(pixels[offset]) / 255.0
                let green = Double(pixels[offset + 1]) / 255.0
                let blue = Double(pixels[offset + 2]) / 255.0
                let luma = 0.299 * red + 0.587 * green + 0.114 * blue
                samples.append(GridSample(location: location, luma: luma))
            }
        }
        return samples
    }

    private static func subjectRect(normalized: CGRect, extent: CGRect) -> CGRect {
        guard normalized.width > 0, normalized.height > 0 else { return .null }
        return CGRect(
            x: extent.minX + extent.width * normalized.minX,
            y: extent.minY + extent.height * normalized.minY,
            width: extent.width * normalized.width,
            height: extent.height * normalized.height
        )
    }

    private static func finite(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }
}
