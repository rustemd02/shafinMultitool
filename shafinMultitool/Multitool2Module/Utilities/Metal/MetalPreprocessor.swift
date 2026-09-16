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

/// The oriented-frame crop window actually sampled into the subject-crop
/// tensor, in TOP-LEFT pixel coordinates of the oriented frame (the same
/// convention the frozen ROI uses). It is recorded separately from the resize
/// transform so a subject point can be checked for visibility without
/// inventing coordinates.
struct SETCompositionNetCropWindow: Equatable, Sendable {
    let left: Double
    let top: Double
    let right: Double
    let bottom: Double

    var isDegenerate: Bool { right <= left || bottom <= top }

    func contains(pixelX: Double, pixelY: Double) -> Bool {
        !isDegenerate
            && pixelX >= left && pixelX <= right
            && pixelY >= top && pixelY <= bottom
    }
}

/// Actual N11 transform provenance for the frozen SETCompositionNet-v1
/// tensors. Each transform is derived from the geometry the renderer/sampler
/// really applied (oriented source extent and the actual crop/scale), then
/// validated against the frozen contract; nothing here is borrowed from a
/// preview aspect-fill matrix.
struct SETCompositionNetTensorTransformRecord: Equatable, Sendable {
    let fullFrameTransform: CameraTensorTransform
    /// Nil when no ROI crop was applied: the subject tensor is a zero fill, so
    /// there is no resize geometry that could be recorded honestly.
    let subjectCropTransform: CameraTensorTransform?
    let subjectCropWindow: SETCompositionNetCropWindow?
    let orientedSourcePixelSize: CGSize

    /// Maps an oriented-frame normalized point (top-left, y-down — the space
    /// the ROI and the tensors share) into the named tensor's destination
    /// coordinates. Returns nil for an unknown tensor id or for a point that is
    /// not visible in that tensor (e.g. outside the applied subject-crop
    /// window). It is never clamped onto an edge, so a cropped-away target
    /// cannot be presented as a manufactured on-screen point.
    func destinationPoint(inTensorID tensorID: String,
                          fromOrientedX x: Double,
                          y: Double) -> (x: Double, y: Double)? {
        guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else {
            return nil
        }
        if tensorID == CameraTensorTransformContract.setCompositionNetFullFrameTensorID {
            return fullFrameTransform.destinationPoint(fromSourceNormalized: x, y: y)
        }
        guard tensorID == CameraTensorTransformContract.setCompositionNetSubjectCropTensorID,
              let subjectCropTransform,
              let window = subjectCropWindow,
              orientedSourcePixelSize.width > 0,
              orientedSourcePixelSize.height > 0 else {
            return nil
        }
        let pixelX = x * Double(orientedSourcePixelSize.width)
        let pixelY = y * Double(orientedSourcePixelSize.height)
        guard window.contains(pixelX: pixelX, pixelY: pixelY) else { return nil }
        let localX = (pixelX - window.left) / (window.right - window.left)
        let localY = (pixelY - window.top) / (window.bottom - window.top)
        return subjectCropTransform.destinationPoint(fromSourceNormalized: localX, y: localY)
    }
}

/// One SETCompositionNet raster preprocessing result: both frozen tensors plus
/// the actual transform recorded for each of them.
struct SETCompositionNetTensorBundle {
    let fullFrame: CVPixelBuffer
    let subjectCrop: CVPixelBuffer
    let transforms: SETCompositionNetTensorTransformRecord
}

/// One SETCompositionNet logical RGB preprocessing result: both frozen float
/// tensors plus the actual transform recorded for each of them.
struct SETCompositionNetRGBTensorBundle {
    let fullFrameRGB: [Double]
    let subjectCropRGB: [Double]
    let transforms: SETCompositionNetTensorTransformRecord
}

/// The geometry Core Image actually applied for one raster resize. These are
/// the values read back from the rendered source, not a separate calculation.
/// `appliedSourceRect` is the extent of the oriented/cropped image Core Image
/// really sampled (which can differ from the nominal crop by its integralized
/// bounds), so the recorded transform and visibility window use it verbatim.
private struct SETCompositionNetRenderedRaster {
    let buffer: CVPixelBuffer
    let appliedSourceRect: CGRect
    let appliedDestinationSize: CGSize
    let appliedScaleX: Double
    let appliedScaleY: Double

    var appliedSourceSize: CGSize { appliedSourceRect.size }
}

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
    ///
    /// This is a convenience wrapper over `setCompositionNetPixelBufferBundle`;
    /// callers that need the actual per-tensor N11 transform must use the
    /// bundle API, which cannot return a tensor without its proven transform.
    func setCompositionNetPixelBuffers(
        from pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        roi: SETCompositionNetROI
    ) -> (fullFrame: CVPixelBuffer, subjectCrop: CVPixelBuffer)? {
        guard let bundle = setCompositionNetPixelBufferBundle(
            from: pixelBuffer,
            orientation: orientation,
            roi: roi
        ) else {
            return nil
        }
        return (fullFrame: bundle.fullFrame, subjectCrop: bundle.subjectCrop)
    }

    /// Builds the frozen SETCompositionNet-v1 raster tensors together with the
    /// actual transform applied to each. Fail-closed: if any tensor's real
    /// geometry cannot be expressed as a valid frozen recipe (unknown tensor,
    /// degenerate source, substituted aspect-fill recipe), the whole bundle is
    /// rejected — no tensor is returned with a "similar" transform.
    func setCompositionNetPixelBufferBundle(
        from pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        roi: SETCompositionNetROI
    ) -> SETCompositionNetTensorBundle? {
        guard roi.validate().isEmpty else { return nil }
        let orientedExtent = orientedPixelBufferExtent(for: pixelBuffer, orientation: orientation)
        guard orientedExtent.width > 0, orientedExtent.height > 0 else { return nil }
        let orientedSourceSize = CGSize(width: orientedExtent.width, height: orientedExtent.height)

        let fullFrameTarget = CGSize(
            width: SETCompositionNetContract.fullFrameWidth,
            height: SETCompositionNetContract.fullFrameHeight
        )
        guard let fullFrameRaster = setCompositionNetResizedPixelBuffer(
            from: pixelBuffer,
            orientation: orientation,
            targetSize: fullFrameTarget
        ) else {
            return nil
        }
        guard let fullFrameTransform = recordedTransform(
            matching: fullFrameRaster,
            tensorID: CameraTensorTransformContract.setCompositionNetFullFrameTensorID,
            orientation: orientation,
            targetSize: fullFrameTarget
        ) else {
            return nil
        }

        let subjectCrop: CVPixelBuffer
        var subjectCropTransform: CameraTensorTransform?
        var subjectCropWindow: SETCompositionNetCropWindow?
        if roi.present {
            // CIImage coordinates have a bottom-left origin; convert the
            // manifest's top-left normalized ROI before clipping and cropping.
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
            let subjectTarget = CGSize(
                width: SETCompositionNetContract.subjectCropWidth,
                height: SETCompositionNetContract.subjectCropHeight
            )
            guard let subjectRaster = setCompositionNetResizedPixelBuffer(
                    from: pixelBuffer,
                    orientation: orientation,
                    targetSize: subjectTarget,
                    cropRect: cropRect
                  ),
                  let transform = recordedTransform(
                    matching: subjectRaster,
                    tensorID: CameraTensorTransformContract.setCompositionNetSubjectCropTensorID,
                    orientation: orientation,
                    targetSize: subjectTarget
                  ) else {
                return nil
            }
            subjectCrop = subjectRaster.buffer
            subjectCropTransform = transform
            // Record the window from the extent Core Image actually sampled, in
            // the oriented frame's TOP-LEFT coordinates. This keeps the window
            // exactly consistent with the recorded transform source even when
            // Core Image integralizes the crop bounds.
            let applied = subjectRaster.appliedSourceRect
            subjectCropWindow = SETCompositionNetCropWindow(
                left: Double(applied.minX - orientedExtent.minX),
                top: Double(orientedExtent.maxY - applied.maxY),
                right: Double(applied.maxX - orientedExtent.minX),
                bottom: Double(orientedExtent.maxY - applied.minY)
            )
        } else {
            guard let zero = makeZeroPixelBuffer(
                width: SETCompositionNetContract.subjectCropWidth,
                height: SETCompositionNetContract.subjectCropHeight
            ) else {
                return nil
            }
            subjectCrop = zero
        }

        return SETCompositionNetTensorBundle(
            fullFrame: fullFrameRaster.buffer,
            subjectCrop: subjectCrop,
            transforms: SETCompositionNetTensorTransformRecord(
                fullFrameTransform: fullFrameTransform,
                subjectCropTransform: subjectCropTransform,
                subjectCropWindow: subjectCropWindow,
                orientedSourcePixelSize: orientedSourceSize
            )
        )
    }

    /// Returns the logical SETCompositionNet tensors directly from the
    /// camera's 32BGRA transport. This SET-specific seam keeps the frozen
    /// float32 RGB/crop contract independent of the legacy pixel-buffer
    /// resize helper, whose callers intentionally retain their old behavior.
    /// Orientation, mirroring, clipping and bilinear sampling are all applied
    /// here exactly once in the manifest's top-left coordinate space.
    /// Convenience wrapper over `setCompositionNetRGBTensorBundle`; see the
    /// bundle API for per-tensor N11 transform provenance.
    func setCompositionNetRGBTensors(
        from pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        roi: SETCompositionNetROI
    ) -> (fullFrameRGB: [Double], subjectCropRGB: [Double])? {
        guard let bundle = setCompositionNetRGBTensorBundle(
            from: pixelBuffer,
            orientation: orientation,
            roi: roi
        ) else {
            return nil
        }
        return (fullFrameRGB: bundle.fullFrameRGB, subjectCropRGB: bundle.subjectCropRGB)
    }

    /// Builds the logical float SETCompositionNet-v1 tensors together with the
    /// actual transform applied to each. Same fail-closed rule as the raster
    /// bundle: an unprovable transform rejects the whole result.
    func setCompositionNetRGBTensorBundle(
        from pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        roi: SETCompositionNetROI
    ) -> SETCompositionNetRGBTensorBundle? {
        guard roi.validate().isEmpty,
              let source = setCompositionNetSourceRGB(from: pixelBuffer),
              let oriented = setCompositionNetOrientedRGB(source, orientation: orientation),
              oriented.width > 0, oriented.height > 0 else {
            return nil
        }
        let orientedSourceSize = CGSize(width: oriented.width, height: oriented.height)

        let fullFrameTarget = CGSize(
            width: SETCompositionNetContract.fullFrameWidth,
            height: SETCompositionNetContract.fullFrameHeight
        )
        let fullFrame = setCompositionNetResize(
            oriented,
            targetWidth: SETCompositionNetContract.fullFrameWidth,
            targetHeight: SETCompositionNetContract.fullFrameHeight,
            left: 0.0,
            top: 0.0,
            right: Double(oriented.width),
            bottom: Double(oriented.height)
        )
        guard let fullFrameTransform = setCompositionNetRecordedTransform(
            tensorID: CameraTensorTransformContract.setCompositionNetFullFrameTensorID,
            orientation: orientation,
            sourcePixelSize: orientedSourceSize,
            destinationPixelSize: fullFrameTarget
        ) else {
            return nil
        }

        let subjectCrop: [Double]
        var subjectCropTransform: CameraTensorTransform?
        var subjectCropWindow: SETCompositionNetCropWindow?
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
            let subjectTarget = CGSize(
                width: SETCompositionNetContract.subjectCropWidth,
                height: SETCompositionNetContract.subjectCropHeight
            )
            guard let transform = setCompositionNetRecordedTransform(
                tensorID: CameraTensorTransformContract.setCompositionNetSubjectCropTensorID,
                orientation: orientation,
                sourcePixelSize: CGSize(
                    width: cropBounds.right - cropBounds.left,
                    height: cropBounds.bottom - cropBounds.top
                ),
                destinationPixelSize: subjectTarget
            ) else {
                return nil
            }
            subjectCropTransform = transform
            subjectCropWindow = SETCompositionNetCropWindow(
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
        return SETCompositionNetRGBTensorBundle(
            fullFrameRGB: fullFrame,
            subjectCropRGB: subjectCrop,
            transforms: SETCompositionNetTensorTransformRecord(
                fullFrameTransform: fullFrameTransform,
                subjectCropTransform: subjectCropTransform,
                subjectCropWindow: subjectCropWindow,
                orientedSourcePixelSize: orientedSourceSize
            )
        )
    }

    private func setCompositionNetResizedPixelBuffer(
        from pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        targetSize: CGSize,
        cropRect: CGRect? = nil
    ) -> SETCompositionNetRenderedRaster? {
        guard targetSize.width.isFinite, targetSize.height.isFinite,
              targetSize.width > 0, targetSize.height > 0 else {
            return nil
        }
        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        let cropped = cropRect.map { image.cropped(to: $0) } ?? image
        guard cropped.extent.width > 0, cropped.extent.height > 0 else {
            return nil
        }
        // The applied source is the extent Core Image really sampled after
        // orientation/cropping; the applied scales are the ones used below.
        let appliedSourceRect = cropped.extent
        let scaleX = targetSize.width / appliedSourceRect.width
        let scaleY = targetSize.height / appliedSourceRect.height
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
        return SETCompositionNetRenderedRaster(
            buffer: outputBuffer,
            appliedSourceRect: appliedSourceRect,
            appliedDestinationSize: targetSize,
            appliedScaleX: Double(scaleX),
            appliedScaleY: Double(scaleY)
        )
    }

    /// Records the frozen recipe transform for one tensor, rejecting an unknown
    /// tensor id, a non-finite/degenerate size, a substituted aspect-fill
    /// recipe, or any geometry that the N11 contract does not admit. Returns
    /// nil instead of a plausible-looking value.
    func setCompositionNetRecordedTransform(
        tensorID: String,
        orientation: CGImagePropertyOrientation,
        sourcePixelSize: CGSize,
        destinationPixelSize: CGSize
    ) -> CameraTensorTransform? {
        guard let tensorOrientation = cameraTensorOrientation(for: orientation),
              let transform = CameraTensorTransformContract.recipe(
                forTensorID: tensorID,
                orientation: tensorOrientation,
                sourcePixelSize: sourcePixelSize,
                destinationPixelSize: destinationPixelSize
              ),
              CameraTensorTransformContract.validate(transform).isEmpty else {
            return nil
        }
        return transform
    }

    /// Records the transform only when its scale equals the scale the renderer
    /// actually applied. A recorded/produced mismatch fails closed rather than
    /// publishing provenance that does not describe the tensor.
    private func recordedTransform(
        matching raster: SETCompositionNetRenderedRaster,
        tensorID: String,
        orientation: CGImagePropertyOrientation,
        targetSize: CGSize
    ) -> CameraTensorTransform? {
        guard let transform = setCompositionNetRecordedTransform(
            tensorID: tensorID,
            orientation: orientation,
            sourcePixelSize: raster.appliedSourceSize,
            destinationPixelSize: targetSize
        ),
        abs(transform.scaleX - raster.appliedScaleX) <= 1e-9,
        abs(transform.scaleY - raster.appliedScaleY) <= 1e-9 else {
            return nil
        }
        return transform
    }

    /// Maps the eight ImageIO orientations onto the frozen N11 orientation
    /// enum. An unknown orientation fails closed instead of being folded into
    /// a nearby value.
    private func cameraTensorOrientation(
        for orientation: CGImagePropertyOrientation
    ) -> CameraTensorOrientationV1? {
        switch orientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        case .left: return .left
        @unknown default: return nil
        }
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
                values.append(Double(bytes[pixel + 2]) / SETCompositionNetContract.rgbNormalizationDenominator)
                values.append(Double(bytes[pixel + 1]) / SETCompositionNetContract.rgbNormalizationDenominator)
                values.append(Double(bytes[pixel]) / SETCompositionNetContract.rgbNormalizationDenominator)
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
