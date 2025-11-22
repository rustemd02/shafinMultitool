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

        let subjectLuma = averageLuminance(in: image, rect: subjectRect)
        let backgroundLuma = averageLuminance(in: image, rect: extent)

        let backlightIndex = max(0, backgroundLuma - subjectLuma)
        let keyFillRatio = subjectLuma > 0 ? backgroundLuma / subjectLuma : 1
        let exposureBias = log2(max(subjectLuma, 1e-3)) - log2(0.5)

        return LightingFeatures(backlightIndex: CGFloat(backlightIndex),
                                keyFillRatio: CGFloat(keyFillRatio),
                                exposureBiasHint: CGFloat(exposureBias))
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
}


