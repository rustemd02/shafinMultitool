import CoreGraphics
import CoreMedia
import CoreVideo
import CryptoKit
import Foundation
import ImageIO

/// Local preparation only. This value grants no consent and defines no server wire format.
/// JPEG pixels remain identifying content: resizing and metadata removal are not anonymization.
struct CameraCloudPreparedStill: Sendable {
    enum Redaction: String, Sendable { case none }

    struct PresentationTimestamp: Equatable, Sendable {
        let value: Int64
        let timescale: Int32
        let flags: UInt32
        let epoch: Int64
    }

    struct Provenance: Equatable, Sendable {
        let snapshotID: String
        let sourceFrameID: String
        let capturedAt: Date
        let sessionGeneration: UInt64
        /// The accepted evidence's lensGeneration, not a newly sampled camera state.
        let captureGeneration: UInt64
        let samplePresentationTimestamp: PresentationTimestamp
        let sourceOrientationRawValue: UInt32
        let lensID: String?
        let sourcePixelWidth: Int
        let sourcePixelHeight: Int
        let displayPixelWidth: Int
        let displayPixelHeight: Int
    }

    let jpegData: Data
    let sha256: String
    let pixelWidth: Int
    let pixelHeight: Int
    let provenance: Provenance
    let redaction: Redaction
    var mimeType: String { "image/jpeg" }
    var byteCount: Int { jpegData.count }
}

enum CameraCloudFramePreprocessingError: Error, Equatable, Sendable {
    enum UnknownField: Equatable, Sendable {
        case snapshotID, sourceFrameID, capturedAt, sessionGeneration
        case captureGeneration, samplePresentationTimestamp
    }

    case cancelled
    case unknownProvenance(UnknownField)
    case missingDisplayImage
    case invalidImageDimensions
    case displayImageDimensionsMismatch
    case unsupportedImageFormat
    case renderingFailed
    case encodingFailed
    case byteLimitExceeded
    case invalidEncodedImage
    case unexpectedEncodedMetadata
}

enum CameraCloudFramePreprocessor {
    static let maximumLongEdge = 1_024
    static let maximumJPEGByteCount = 512 * 1_024

    /// Uses the already rendered, already oriented accepted still. The caller must await
    /// the existing pause display renderer first; this owner never samples the live store.
    /// Native raster/codec calls are synchronous; cancellation is checked around each call.
    static func prepare(
        snapshot: LatestFrameEvidenceStore.AcceptedSnapshot
    ) async throws -> CameraCloudPreparedStill {
        try checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try prepareOffMain(snapshot: snapshot)
        }
        return try await withTaskCancellationHandler {
            let prepared = try await worker.value
            // A cancelled caller must never receive a late successful preparation.
            try checkCancellation()
            return prepared
        } onCancel: {
            worker.cancel()
        }
    }

    private static func prepareOffMain(
        snapshot: LatestFrameEvidenceStore.AcceptedSnapshot
    ) throws -> CameraCloudPreparedStill {
        try checkCancellation()
        let provenance = try provenance(for: snapshot)
        guard let image = snapshot.displayImage else {
            throw CameraCloudFramePreprocessingError.missingDisplayImage
        }
        guard !image.isMask,
              image.bitsPerComponent == 8 || image.bitsPerComponent == 16,
              image.colorSpace?.model == .rgb || image.colorSpace?.model == .monochrome else {
            throw CameraCloudFramePreprocessingError.unsupportedImageFormat
        }

        // A bounded number of attempts; compression quality alone is never a byte guarantee.
        // Render every attempted size from the original display image, not an earlier JPEG.
        let edgeBudgets = [maximumLongEdge, 768, 512, 256]
        let qualities: [Double] = [0.85, 0.65, 0.45, 0.25]
        var previousSize: (width: Int, height: Int)?
        for edge in edgeBudgets {
            try checkCancellation()
            let size = boundedSize(width: image.width, height: image.height, longEdge: edge)
            if let previousSize, previousSize.width == size.width,
               previousSize.height == size.height { continue }
            previousSize = size
            let raster = try freshSRGBRaster(image, width: size.width, height: size.height)
            try checkCancellation()
            for quality in qualities {
                try checkCancellation()
                let data = try encodeJPEG(raster, quality: quality)
                try checkCancellation()
                guard data.count <= maximumJPEGByteCount else { continue }
                let decodedSize = try verifyJPEG(data, expectedWidth: size.width,
                                                expectedHeight: size.height)
                try checkCancellation()
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                try checkCancellation()
                return CameraCloudPreparedStill(
                    jpegData: data, sha256: digest,
                    pixelWidth: decodedSize.width, pixelHeight: decodedSize.height,
                    provenance: provenance, redaction: .none
                )
            }
        }
        throw CameraCloudFramePreprocessingError.byteLimitExceeded
    }

    private static func provenance(
        for snapshot: LatestFrameEvidenceStore.AcceptedSnapshot
    ) throws -> CameraCloudPreparedStill.Provenance {
        typealias Failure = CameraCloudFramePreprocessingError
        guard !snapshot.snapshotID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.unknownProvenance(.snapshotID)
        }
        guard !snapshot.sourceFrameId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.unknownProvenance(.sourceFrameID)
        }
        guard snapshot.capturedAt.timeIntervalSince1970.isFinite else {
            throw Failure.unknownProvenance(.capturedAt)
        }
        guard let session = snapshot.sessionGeneration else {
            throw Failure.unknownProvenance(.sessionGeneration)
        }
        guard snapshot.evidence.lensGeneration != 0 else {
            throw Failure.unknownProvenance(.captureGeneration)
        }
        let pts = snapshot.samplePresentationTimestamp
        guard pts.isNumeric, pts.timescale > 0 else {
            throw Failure.unknownProvenance(.samplePresentationTimestamp)
        }
        guard let image = snapshot.displayImage else { throw Failure.missingDisplayImage }
        let width = CVPixelBufferGetWidth(snapshot.pixelBuffer)
        let height = CVPixelBufferGetHeight(snapshot.pixelBuffer)
        guard width > 0, height > 0, image.width > 0, image.height > 0 else {
            throw Failure.invalidImageDimensions
        }
        let swapsAxes: Bool
        switch snapshot.orientation {
        case .up, .upMirrored, .down, .downMirrored: swapsAxes = false
        case .left, .leftMirrored, .right, .rightMirrored: swapsAxes = true
        @unknown default: throw Failure.unsupportedImageFormat
        }
        guard image.width == (swapsAxes ? height : width),
              image.height == (swapsAxes ? width : height) else {
            throw Failure.displayImageDimensionsMismatch
        }
        return .init(
            snapshotID: snapshot.snapshotID, sourceFrameID: snapshot.sourceFrameId,
            capturedAt: snapshot.capturedAt, sessionGeneration: session,
            captureGeneration: snapshot.evidence.lensGeneration,
            samplePresentationTimestamp: .init(value: pts.value, timescale: pts.timescale,
                                               flags: pts.flags.rawValue, epoch: pts.epoch),
            sourceOrientationRawValue: snapshot.orientation.rawValue,
            lensID: snapshot.evidence.lensID,
            sourcePixelWidth: width, sourcePixelHeight: height,
            displayPixelWidth: image.width, displayPixelHeight: image.height
        )
    }

    private static func boundedSize(width: Int, height: Int, longEdge: Int) -> (width: Int, height: Int) {
        let scale = min(1, Double(longEdge) / Double(max(width, height)))
        return (max(1, Int((Double(width) * scale).rounded(.down))),
                max(1, Int((Double(height) * scale).rounded(.down))))
    }

    private static func freshSRGBRaster(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                                        | CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw CameraCloudFramePreprocessingError.renderingFailed
        }
        // JPEG has no alpha. Flatten onto an explicit white background; do not attach
        // source properties, CVBuffer attachments, orientation, location or EXIF data.
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let raster = context.makeImage() else {
            throw CameraCloudFramePreprocessingError.renderingFailed
        }
        return raster
    }

    private static func encodeJPEG(_ image: CGImage, quality: Double) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
            throw CameraCloudFramePreprocessingError.encodingFailed
        }
        let properties = [kCGImageDestinationLossyCompressionQuality as String: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination), data.length > 0 else {
            throw CameraCloudFramePreprocessingError.encodingFailed
        }
        return try removingJPEGMetadata(data as Data)
    }

    /// ImageIO can synthesize EXIF even when the fresh raster has no source metadata.
    /// Remove header APP1 (EXIF/XMP) and APP13 (IPTC) without recompressing the scan.
    /// This accepts only the newly encoded JPEG above; full ImageIO validation follows.
    static func removingJPEGMetadata(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0] == 0xff, bytes[1] == 0xd8 else {
            throw CameraCloudFramePreprocessingError.invalidEncodedImage
        }
        var result = Array(bytes.prefix(2))
        result.reserveCapacity(bytes.count)
        var offset = 2
        while offset < bytes.count {
            let segmentStart = offset
            guard bytes[offset] == 0xff else {
                throw CameraCloudFramePreprocessingError.invalidEncodedImage
            }
            while offset < bytes.count, bytes[offset] == 0xff { offset += 1 }
            guard offset < bytes.count else {
                throw CameraCloudFramePreprocessingError.invalidEncodedImage
            }
            let marker = bytes[offset]
            offset += 1
            // Standalone/stuffed markers do not belong in a fresh JPEG header.
            guard marker != 0x00, marker != 0x01, !(0xd0...0xd9).contains(marker),
                  bytes.count - offset >= 2 else {
                throw CameraCloudFramePreprocessingError.invalidEncodedImage
            }
            let length = Int(bytes[offset]) * 256 + Int(bytes[offset + 1])
            guard length >= 2, length <= bytes.count - offset else {
                throw CameraCloudFramePreprocessingError.invalidEncodedImage
            }
            let segmentEnd = offset + length
            if marker == 0xda {
                // SOS and the complete compressed image remain byte-for-byte intact.
                result.append(contentsOf: bytes[segmentStart...])
                return Data(result)
            }
            if marker != 0xe1, marker != 0xed {
                // In particular, preserve APP2 ICC color profiles and codec tables.
                result.append(contentsOf: bytes[segmentStart..<segmentEnd])
            }
            offset = segmentEnd
        }
        throw CameraCloudFramePreprocessingError.invalidEncodedImage
    }

    private static func verifyJPEG(_ data: Data, expectedWidth: Int, expectedHeight: Int) throws
        -> (width: Int, height: Int) {
        guard !data.isEmpty, data.count <= maximumJPEGByteCount,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source), type as String == "public.jpeg",
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetStatus(source) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil),
              decoded.width == expectedWidth, decoded.height == expectedHeight,
              max(decoded.width, decoded.height) <= maximumLongEdge,
              (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue == decoded.width,
              (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue == decoded.height else {
            throw CameraCloudFramePreprocessingError.invalidEncodedImage
        }
        let forbiddenKeys = [kCGImagePropertyExifDictionary, kCGImagePropertyExifAuxDictionary,
                             kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary]
        guard forbiddenKeys.allSatisfy({ properties[$0 as String] == nil }),
              properties[kCGImagePropertyOrientation as String] == nil
                || (properties[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue == 1 else {
            throw CameraCloudFramePreprocessingError.unexpectedEncodedMetadata
        }
        return (decoded.width, decoded.height)
    }

    private static func checkCancellation() throws {
        if Task.isCancelled { throw CameraCloudFramePreprocessingError.cancelled }
    }
}
