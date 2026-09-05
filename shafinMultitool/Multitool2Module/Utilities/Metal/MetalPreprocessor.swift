//
//  MetalPreprocessor.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import CoreImage
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
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
                            orientation: CGImagePropertyOrientation = .up,
                            targetSize: CGSize,
                            cropRect: CGRect? = nil) -> CVPixelBuffer? {
        guard targetSize.width.isFinite, targetSize.height.isFinite,
              targetSize.width > 0, targetSize.height > 0 else {
            return nil
        }
        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        let cropped = cropRect.map { image.cropped(to: $0) } ?? image
        guard cropped.extent.width > 0, cropped.extent.height > 0 else {
            return nil
        }
        let scaleX = targetSize.width / cropped.extent.width
        let scaleY = targetSize.height / cropped.extent.height
        let scaled = cropped.transformed(by: .init(scaleX: scaleX, y: scaleY))
        let rendered = scaled.transformed(
            by: .init(translationX: -scaled.extent.minX, y: -scaled.extent.minY)
        )

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

        context.render(
            rendered,
            to: outputBuffer,
            bounds: CGRect(origin: .zero, size: targetSize),
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return outputBuffer
    }

    /// Frozen SETCompositionNet-v1 camera tensors. Core Image performs the
    /// orientation exactly once; mirrored orientations are carried by the
    /// ImageIO orientation value and are never mirrored again here.
    func setCompositionNetPixelBuffers(
        from pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        roi: SETCompositionNetROI
    ) -> (fullFrame: CVPixelBuffer, subjectCrop: CVPixelBuffer)? {
        guard roi.validate().isEmpty else { return nil }
        guard let fullFrame = resizedPixelBuffer(
            from: pixelBuffer,
            orientation: orientation,
            targetSize: CGSize(
                width: SETCompositionNetContract.fullFrameWidth,
                height: SETCompositionNetContract.fullFrameHeight
            )
        ) else {
            return nil
        }

        let subjectCrop: CVPixelBuffer
        if roi.present {
            // CIImage coordinates have a bottom-left origin; convert the
            // manifest's top-left normalized ROI before clipping and cropping.
            let orientedExtent = orientedPixelBufferExtent(for: pixelBuffer, orientation: orientation)
            let rawRect = CGRect(
                x: orientedExtent.minX + CGFloat(roi.x) * orientedExtent.width,
                y: orientedExtent.minY + CGFloat(1.0 - roi.y - roi.height) * orientedExtent.height,
                width: CGFloat(roi.width) * orientedExtent.width,
                height: CGFloat(roi.height) * orientedExtent.height
            )
            let side = max(rawRect.width, rawRect.height) * 1.25
            let padded = CGRect(
                x: rawRect.midX - side / 2,
                y: rawRect.midY - side / 2,
                width: side,
                height: side
            )
            let bounds = orientedExtent
            let cropRect = padded.intersection(bounds)
            guard !cropRect.isNull, !cropRect.isEmpty,
                  let resized = resizedPixelBuffer(
                    from: pixelBuffer,
                    orientation: orientation,
                    targetSize: CGSize(
                        width: SETCompositionNetContract.subjectCropWidth,
                        height: SETCompositionNetContract.subjectCropHeight
                    ),
                    cropRect: cropRect
                  ) else {
                return nil
            }
            subjectCrop = resized
        } else {
            guard let zero = makeZeroPixelBuffer(
                width: SETCompositionNetContract.subjectCropWidth,
                height: SETCompositionNetContract.subjectCropHeight
            ) else {
                return nil
            }
            subjectCrop = zero
        }
        return (fullFrame: fullFrame, subjectCrop: subjectCrop)
    }

    /// Converts the BGRA camera transport into logical RGB values in [0, 1].
    /// This is a deterministic parity seam for fixtures; model inference still
    /// receives the native pixel-buffer transport.
    func setCompositionNetRGBValues(from pixelBuffer: CVPixelBuffer) -> [Double]? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            return nil
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        var values: [Double] = []
        values.reserveCapacity(width * height * 3)
        for row in 0..<height {
            let rowStart = row * bytesPerRow
            for column in 0..<width {
                let pixel = rowStart + column * 4
                values.append(Double(bytes[pixel + 2]) / 255.0)
                values.append(Double(bytes[pixel + 1]) / 255.0)
                values.append(Double(bytes[pixel]) / 255.0)
            }
        }
        return values
    }

    private func orientedPixelBufferExtent(
        for pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> CGRect {
        CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation).extent
    }

    private func makeZeroPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer,
              CVPixelBufferLockBaseAddress(pixelBuffer, []) == kCVReturnSuccess else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(baseAddress, 0, CVPixelBufferGetDataSize(pixelBuffer))
        }
        return pixelBuffer
    }
}
