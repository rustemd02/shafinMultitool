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
        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
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

    /// Frozen SETCompositionNet-v1 camera tensors. Core Image performs the
    /// orientation exactly once; mirrored orientations are carried by the
    /// ImageIO orientation value and are never mirrored again here.
    func setCompositionNetPixelBuffers(
        from pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        roi: SETCompositionNetROI
    ) -> (fullFrame: CVPixelBuffer, subjectCrop: CVPixelBuffer)? {
        guard roi.validate().isEmpty else { return nil }
        guard let fullFrame = setCompositionNetResizedPixelBuffer(
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
            guard let cropBounds = setCompositionNetClippedSquareBounds(
                for: roi,
                width: orientedExtent.width,
                height: orientedExtent.height
            ) else {
                return nil
            }
            let cropRect = CGRect(
                x: orientedExtent.minX + CGFloat(cropBounds.left),
                y: orientedExtent.minY + CGFloat(orientedExtent.height - cropBounds.bottom),
                width: CGFloat(cropBounds.right - cropBounds.left),
                height: CGFloat(cropBounds.bottom - cropBounds.top)
            )
            guard let resized = setCompositionNetResizedPixelBuffer(
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

    /// Returns the logical SETCompositionNet tensors directly from the
    /// camera's 32BGRA transport. This SET-specific seam keeps the frozen
    /// float32 RGB/crop contract independent of the legacy pixel-buffer
    /// resize helper, whose callers intentionally retain their old behavior.
    /// Orientation, mirroring, clipping and bilinear sampling are all applied
    /// here exactly once in the manifest's top-left coordinate space.
    func setCompositionNetRGBTensors(
        from pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        roi: SETCompositionNetROI
    ) -> (fullFrameRGB: [Double], subjectCropRGB: [Double])? {
        guard roi.validate().isEmpty,
              let source = setCompositionNetSourceRGB(from: pixelBuffer),
              let oriented = setCompositionNetOrientedRGB(source, orientation: orientation) else {
            return nil
        }

        let fullFrame = setCompositionNetResize(
            oriented,
            targetWidth: SETCompositionNetContract.fullFrameWidth,
            targetHeight: SETCompositionNetContract.fullFrameHeight,
            left: 0.0,
            top: 0.0,
            right: Double(oriented.width),
            bottom: Double(oriented.height)
        )
        let subjectCrop: [Double]
        if roi.present {
            guard let cropBounds = setCompositionNetClippedSquareBounds(
                for: roi,
                width: Double(oriented.width),
                height: Double(oriented.height)
            ) else {
                return nil
            }
            subjectCrop = setCompositionNetResize(
                oriented,
                targetWidth: SETCompositionNetContract.subjectCropWidth,
                targetHeight: SETCompositionNetContract.subjectCropHeight,
                left: cropBounds.left,
                top: cropBounds.top,
                right: cropBounds.right,
                bottom: cropBounds.bottom
            )
        } else {
            subjectCrop = Array(
                repeating: 0.0,
                count: SETCompositionNetContract.subjectCropWidth
                    * SETCompositionNetContract.subjectCropHeight * 3
            )
        }
        return (fullFrameRGB: fullFrame, subjectCropRGB: subjectCrop)
    }

    private func setCompositionNetResizedPixelBuffer(
        from pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        targetSize: CGSize,
        cropRect: CGRect? = nil
    ) -> CVPixelBuffer? {
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

    /// Converts the BGRA camera transport into logical RGB values in [0, 1].
    /// This is a deterministic parity seam for fixtures; model inference still
    /// receives the native pixel-buffer transport.
    func setCompositionNetRGBValues(from pixelBuffer: CVPixelBuffer) -> [Double]? {
        setCompositionNetSourceRGB(from: pixelBuffer)?.values
    }

    private struct SETCompositionNetRGBImage {
        let values: [Double]
        let width: Int
        let height: Int
    }

    private func setCompositionNetSourceRGB(from pixelBuffer: CVPixelBuffer) -> SETCompositionNetRGBImage? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            return nil
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0,
              CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
            return nil
        }
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
        return SETCompositionNetRGBImage(values: values, width: width, height: height)
    }

    private func setCompositionNetOrientedRGB(
        _ source: SETCompositionNetRGBImage,
        orientation: CGImagePropertyOrientation
    ) -> SETCompositionNetRGBImage? {
        let swapsAxes: Bool
        switch orientation {
        case .up, .upMirrored, .down, .downMirrored:
            swapsAxes = false
        case .leftMirrored, .right, .rightMirrored, .left:
            swapsAxes = true
        @unknown default:
            return nil
        }

        let width = swapsAxes ? source.height : source.width
        let height = swapsAxes ? source.width : source.height
        var values: [Double] = []
        values.reserveCapacity(width * height * 3)
        for outputY in 0..<height {
            for outputX in 0..<width {
                let sourceCoordinate: (x: Int, y: Int)
                switch orientation {
                case .up:
                    sourceCoordinate = (outputX, outputY)
                case .upMirrored:
                    sourceCoordinate = (source.width - 1 - outputX, outputY)
                case .down:
                    sourceCoordinate = (source.width - 1 - outputX, source.height - 1 - outputY)
                case .downMirrored:
                    sourceCoordinate = (outputX, source.height - 1 - outputY)
                case .leftMirrored:
                    sourceCoordinate = (outputY, outputX)
                case .right:
                    sourceCoordinate = (outputY, source.height - 1 - outputX)
                case .rightMirrored:
                    sourceCoordinate = (source.width - 1 - outputY, source.height - 1 - outputX)
                case .left:
                    sourceCoordinate = (source.width - 1 - outputY, outputX)
                @unknown default:
                    return nil
                }
                let index = (sourceCoordinate.y * source.width + sourceCoordinate.x) * 3
                values.append(contentsOf: source.values[index..<(index + 3)])
            }
        }
        return SETCompositionNetRGBImage(values: values, width: width, height: height)
    }

    private func setCompositionNetResize(
        _ source: SETCompositionNetRGBImage,
        targetWidth: Int,
        targetHeight: Int,
        left: Double,
        top: Double,
        right: Double,
        bottom: Double
    ) -> [Double] {
        var output: [Double] = []
        output.reserveCapacity(targetWidth * targetHeight * 3)
        for targetY in 0..<targetHeight {
            let sourceY = max(
                0.0,
                min(
                    Double(source.height - 1),
                    top + (Double(targetY) + 0.5) * (bottom - top) / Double(targetHeight) - 0.5
                )
            )
            let y0 = Int(sourceY)
            let y1 = min(y0 + 1, source.height - 1)
            let yWeight = sourceY - Double(y0)
            for targetX in 0..<targetWidth {
                let sourceX = max(
                    0.0,
                    min(
                        Double(source.width - 1),
                        left + (Double(targetX) + 0.5) * (right - left) / Double(targetWidth) - 0.5
                    )
                )
                let x0 = Int(sourceX)
                let x1 = min(x0 + 1, source.width - 1)
                let xWeight = sourceX - Double(x0)
                for channel in 0..<3 {
                    let topLeft = source.values[(y0 * source.width + x0) * 3 + channel]
                    let topRight = source.values[(y0 * source.width + x1) * 3 + channel]
                    let bottomLeft = source.values[(y1 * source.width + x0) * 3 + channel]
                    let bottomRight = source.values[(y1 * source.width + x1) * 3 + channel]
                    let topValue = (1.0 - xWeight) * topLeft + xWeight * topRight
                    let bottomValue = (1.0 - xWeight) * bottomLeft + xWeight * bottomRight
                    output.append((1.0 - yWeight) * topValue + yWeight * bottomValue)
                }
            }
        }
        return output
    }

    private func setCompositionNetClippedSquareBounds(
        for roi: SETCompositionNetROI,
        width: Double,
        height: Double
    ) -> (left: Double, top: Double, right: Double, bottom: Double)? {
        guard roi.present, width.isFinite, height.isFinite, width > 0, height > 0 else {
            return nil
        }
        let rawX = roi.x * width
        let rawY = roi.y * height
        let rawWidth = roi.width * width
        let rawHeight = roi.height * height
        let side = max(rawWidth, rawHeight) * 1.25
        let rawLeft = rawX + rawWidth / 2.0 - side / 2.0
        let rawTop = rawY + rawHeight / 2.0 - side / 2.0
        let rawRight = rawX + rawWidth / 2.0 + side / 2.0
        let rawBottom = rawY + rawHeight / 2.0 + side / 2.0
        let left = max(0.0, rawLeft)
        let top = max(0.0, rawTop)
        let right = min(width, rawRight)
        let bottom = min(height, rawBottom)
        guard right > left, bottom > top else { return nil }
        return (left: left, top: top, right: right, bottom: bottom)
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
