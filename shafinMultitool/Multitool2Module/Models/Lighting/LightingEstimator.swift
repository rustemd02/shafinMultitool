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

    func analyse(pixelBuffer: CVPixelBuffer,
                 subjectBoundingBox: CGRect) -> LightingFeatures {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = image.extent
        let subjectRect = CGRect(x: extent.minX + extent.width * subjectBoundingBox.minX,
                                 y: extent.minY + extent.height * subjectBoundingBox.minY,
                                 width: extent.width * subjectBoundingBox.width,
                                 height: extent.height * subjectBoundingBox.height)

        let subjectMetrics = luminanceMetrics(in: image, rect: subjectRect)
        let backgroundMetrics = luminanceMetrics(in: image, rect: extent)
        let subjectLuma = subjectMetrics.mean
        let backgroundLuma = backgroundMetrics.mean

        let backlightIndex = max(0, backgroundLuma - subjectLuma)
        let keyFillRatio = subjectLuma > 0 ? backgroundLuma / subjectLuma : 1
        let exposureBias = log2(max(subjectLuma, 1e-3)) - log2(0.5)

        return LightingFeatures(backlightIndex: CGFloat(backlightIndex),
                                keyFillRatio: CGFloat(keyFillRatio),
                                exposureBiasHint: CGFloat(exposureBias),
                                subjectMeanLuma: CGFloat(subjectLuma),
                                backgroundMeanLuma: CGFloat(backgroundLuma),
                                subjectToBackgroundDelta: CGFloat(subjectLuma - backgroundLuma),
                                subjectClippedBrightRatio: CGFloat(subjectMetrics.clippedBrightRatio),
                                backgroundHotspotRatio: CGFloat(backgroundMetrics.hotspotRatio))
    }

    private func averageLuminance(in image: CIImage, rect: CGRect) -> CGFloat {
        guard let filter = CIFilter(name: "CIAreaAverage") else {
            return 0.5
        }
        filter.setValue(image.cropped(to: rect), forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: rect), forKey: kCIInputExtentKey)
        
        guard let outputImage = filter.outputImage,
              let cgImage = context.createCGImage(outputImage, from: CGRect(origin: .zero, size: CGSize(width: 1, height: 1))),
              let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else {
            return 0.5
        }
        // BGRA pixel
        let b = Double(ptr[0]) / 255.0
        let g = Double(ptr[1]) / 255.0
        let r = Double(ptr[2]) / 255.0
        return CGFloat(0.299 * r + 0.587 * g + 0.114 * b)
    }

    private func luminanceMetrics(in image: CIImage,
                                  rect: CGRect,
                                  sampleWidth: Int = 32,
                                  sampleHeight: Int = 32) -> (mean: CGFloat, clippedBrightRatio: CGFloat, hotspotRatio: CGFloat) {
        let clippedRect = rect.intersection(image.extent)
        guard clippedRect.width > 1, clippedRect.height > 1 else {
            return (0.5, 0, 0)
        }

        let mean = averageLuminance(in: image, rect: clippedRect)
        var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
        let rowBytes = sampleWidth * 4
        let transform = CGAffineTransform(translationX: -clippedRect.minX, y: -clippedRect.minY)
            .scaledBy(x: CGFloat(sampleWidth) / clippedRect.width,
                      y: CGFloat(sampleHeight) / clippedRect.height)
        let sampled = image
            .cropped(to: clippedRect)
            .transformed(by: transform)
        let bounds = CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight)
        context.render(sampled,
                       toBitmap: &pixels,
                       rowBytes: rowBytes,
                       bounds: bounds,
                       format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())

        var clippedBrightCount = 0
        var hotspotCount = 0
        let pixelCount = sampleWidth * sampleHeight
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Double(pixels[index]) / 255.0
            let green = Double(pixels[index + 1]) / 255.0
            let blue = Double(pixels[index + 2]) / 255.0
            let luma = (0.299 * red) + (0.587 * green) + (0.114 * blue)
            if luma >= 0.92 { clippedBrightCount += 1 }
            if luma >= 0.82 { hotspotCount += 1 }
        }

        guard pixelCount > 0 else { return (mean, 0, 0) }
        return (
            mean,
            CGFloat(Double(clippedBrightCount) / Double(pixelCount)),
            CGFloat(Double(hotspotCount) / Double(pixelCount))
        )
    }
}

