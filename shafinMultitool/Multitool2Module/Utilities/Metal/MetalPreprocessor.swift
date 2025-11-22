//
//  MetalPreprocessor.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import CoreImage
import CoreVideo
import Metal

final class MetalPreprocessor {
    private let device: MTLDevice?
    private let context: CIContext

    init() {
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        if let device {
            self.context = CIContext(mtlDevice: device)
        } else {
            self.context = CIContext()
        }
    }

    func resizedPixelBuffer(from pixelBuffer: CVPixelBuffer,
                            targetSize: CGSize,
                            cropRect: CGRect? = nil) -> CVPixelBuffer? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let cropped = cropRect.map { image.cropped(to: $0) } ?? image
        let scaleX = targetSize.width / cropped.extent.width
        let scaleY = targetSize.height / cropped.extent.height
        let scaled = cropped.transformed(by: .init(scaleX: scaleX, y: scaleY))

        var outputBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferWidthKey as String: Int(targetSize.width),
            kCVPixelBufferHeightKey as String: Int(targetSize.height),
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(targetSize.width),
                                         Int(targetSize.height),
                                         kCVPixelFormatType_32BGRA,
                                         attrs as CFDictionary,
                                         &outputBuffer)
        guard status == kCVReturnSuccess, let outputBuffer else {
            return nil
        }

        context.render(scaled, to: outputBuffer)
        return outputBuffer
    }
}



