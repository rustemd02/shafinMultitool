import CoreGraphics
import CoreMedia
import CoreVideo
import CryptoKit
import Foundation
import ImageIO
import XCTest
@testable import shafinMultitool

/// Proposed native image-codec tests. Synthetic pixels only; no model, provider or upload.
final class CameraCloudFramePreprocessorTests: XCTestCase {
    func testAlreadyOrientedAsymmetricAcceptedPixelsAreNotRotatedOrMirroredAgain() async throws {
        let orientations: [CGImagePropertyOrientation] = [
            .up, .upMirrored, .down, .downMirrored, .left, .leftMirrored, .right, .rightMirrored
        ]
        for orientation in orientations {
            let fixture = try makeFixture(width: 160, height: 96, orientation: orientation)
            let display = try XCTUnwrap(fixture.accepted.displayImage)
            let prepared = try await CameraCloudFramePreprocessor.prepare(snapshot: fixture.accepted)
            let decoded = try decode(prepared.jpegData)
            XCTAssertEqual(decoded.width, display.width)
            XCTAssertEqual(decoded.height, display.height)
            XCTAssertEqual(prepared.pixelWidth, display.width, "Small stills must not be enlarged")
            XCTAssertEqual(prepared.pixelHeight, display.height)
            XCTAssertEqual(prepared.provenance.sourceOrientationRawValue, orientation.rawValue)
            let before = try rgba(display)
            let after = try rgba(decoded)
            let points = [(display.width / 4, display.height / 4),
                          (3 * display.width / 4, display.height / 4),
                          (display.width / 4, 3 * display.height / 4),
                          (3 * display.width / 4, 3 * display.height / 4)]
            var distinctSourceColors = Set<[UInt8]>()
            for (x, y) in points {
                let offset = (y * display.width + x) * 4
                distinctSourceColors.insert(Array(before[offset..<(offset + 3)]))
                for channel in 0..<3 {
                    XCTAssertEqual(Double(after[offset + channel]), Double(before[offset + channel]),
                                   accuracy: 24, "orientation=\(orientation.rawValue), point=\(x),\(y)")
                }
            }
            XCTAssertEqual(distinctSourceColors.count, 4, "The fixture must distinguish every corner")
            if [.left, .leftMirrored, .right, .rightMirrored].contains(orientation) {
                XCTAssertEqual(display.width, 96)
                XCTAssertEqual(display.height, 160)
            } else {
                XCTAssertEqual(display.width, 160)
                XCTAssertEqual(display.height, 96)
            }
        }
    }

    func testHighEntropyStillHonorsActualByteAndDimensionLimitsAndHashesFinalJPEG() async throws {
        let fixture = try makeFixture(width: 1_536, height: 1_024, noise: true)
        let prepared = try await CameraCloudFramePreprocessor.prepare(snapshot: fixture.accepted)
        let decoded = try decode(prepared.jpegData)
        let properties = try imageProperties(prepared.jpegData)
        XCTAssertFalse(prepared.jpegData.isEmpty)
        XCTAssertLessThanOrEqual(prepared.byteCount, 512 * 1_024)
        XCTAssertEqual(prepared.byteCount, prepared.jpegData.count)
        XCTAssertLessThanOrEqual(max(decoded.width, decoded.height), 1_024)
        XCTAssertEqual(prepared.pixelWidth, decoded.width)
        XCTAssertEqual(prepared.pixelHeight, decoded.height)
        XCTAssertEqual((properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue,
                       decoded.width)
        XCTAssertEqual((properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue,
                       decoded.height)
        XCTAssertEqual(prepared.sha256,
                       SHA256.hash(data: prepared.jpegData).map { String(format: "%02x", $0) }.joined())
        XCTAssertEqual(prepared.sha256.count, 64)
        XCTAssertEqual(prepared.mimeType, "image/jpeg")
        XCTAssertEqual(prepared.redaction, .none, "Metadata stripping is not anonymization")
        XCTAssertEqual(prepared.provenance.displayPixelWidth, 1_536)
        XCTAssertEqual(prepared.provenance.displayPixelHeight, 1_024)
    }

    func testVeryNarrowImageKeepsPositiveDimensionsWithinBudget() async throws {
        let fixture = try makeFixture(width: 1, height: 4_096)
        let prepared = try await CameraCloudFramePreprocessor.prepare(snapshot: fixture.accepted)
        XCTAssertEqual(prepared.pixelWidth, 1)
        XCTAssertEqual(prepared.pixelHeight, 1_024)
        XCTAssertLessThanOrEqual(prepared.byteCount, CameraCloudFramePreprocessor.maximumJPEGByteCount)
    }

    func testFreshEncodeStripsSyntheticEXIFAndGPSAndUsesDisplayOrientation() async throws {
        let fixture = try makeFixture(width: 160, height: 96)
        let display = try XCTUnwrap(fixture.accepted.displayImage)
        let annotated = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            annotated, "public.jpeg" as CFString, 1, nil
        ))
        let properties: [String: Any] = [
            kCGImageDestinationLossyCompressionQuality as String: 0.95,
            kCGImagePropertyOrientation as String: 1,
            kCGImagePropertyExifDictionary as String: [kCGImagePropertyExifUserComment as String: "synthetic fixture only"],
            kCGImagePropertyGPSDictionary as String: [kCGImagePropertyGPSLatitude as String: 12.25,
                                                     kCGImagePropertyGPSLatitudeRef as String: "N",
                                                     kCGImagePropertyGPSLongitude as String: 34.5,
                                                     kCGImagePropertyGPSLongitudeRef as String: "E"]
        ]
        CGImageDestinationAddImage(destination, display, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let input = annotated as Data
        let inputProperties = try imageProperties(input)
        XCTAssertNotNil(inputProperties[kCGImagePropertyExifDictionary as String])
        XCTAssertNotNil(inputProperties[kCGImagePropertyGPSDictionary as String])
        let annotatedDisplay = try decode(input)
        let accepted = fixture.accepted.withDisplayImage(annotatedDisplay)
        let prepared = try await CameraCloudFramePreprocessor.prepare(snapshot: accepted)
        let outputProperties = try imageProperties(prepared.jpegData)
        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyExifAuxDictionary,
                    kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary] {
            XCTAssertNil(outputProperties[key as String], "Unexpected metadata: \(key)")
        }
        let outputOrientation = outputProperties[kCGImagePropertyOrientation as String] as? NSNumber
        XCTAssertTrue(outputOrientation == nil || outputOrientation?.intValue == 1)
        XCTAssertEqual(prepared.redaction.rawValue, "none")
        XCTAssertEqual(try imageProperties(input).count, inputProperties.count,
                       "The source data itself must remain intact")
    }

    func testAcceptedFrameProvenanceAndPixelsSurviveLaterPublicationWithoutMutation() async throws {
        let fixture = try makeFixture(width: 160, height: 96, orientation: .rightMirrored)
        let accepted = fixture.accepted
        let beforeBuffer = try pixelBufferBytes(accepted.pixelBuffer)
        let beforeDisplay = try rgba(XCTUnwrap(accepted.displayImage))
        let later = try makePixelBuffer(width: 160, height: 96, noise: true)
        XCTAssertTrue(fixture.store.publish(
            pixelBuffer: later, orientation: .up, sourceFrameId: "later-frame",
            capturedAt: accepted.capturedAt.addingTimeInterval(1), isStable: false,
            lensID: "later-lens", lensGeneration: 8,
            samplePresentationTimestamp: CMTime(value: 1_201, timescale: 600), sessionGeneration: 0
        ))
        let prepared = try await CameraCloudFramePreprocessor.prepare(snapshot: accepted)
        XCTAssertEqual(prepared.provenance.snapshotID, accepted.snapshotID)
        XCTAssertEqual(prepared.provenance.sourceFrameID, "accepted-frame")
        XCTAssertEqual(prepared.provenance.capturedAt, accepted.capturedAt)
        XCTAssertEqual(prepared.provenance.sessionGeneration, 0, "Session zero is known and valid")
        XCTAssertEqual(prepared.provenance.captureGeneration, 7)
        XCTAssertEqual(prepared.provenance.lensID, "fixture-lens")
        XCTAssertEqual(prepared.provenance.samplePresentationTimestamp.value, 1_200)
        XCTAssertEqual(prepared.provenance.samplePresentationTimestamp.timescale, 600)
        XCTAssertEqual(prepared.provenance.samplePresentationTimestamp.flags,
                       accepted.samplePresentationTimestamp.flags.rawValue)
        XCTAssertEqual(prepared.provenance.samplePresentationTimestamp.epoch,
                       accepted.samplePresentationTimestamp.epoch)
        XCTAssertEqual(prepared.provenance.sourcePixelWidth, 160)
        XCTAssertEqual(prepared.provenance.sourcePixelHeight, 96)
        XCTAssertEqual(prepared.provenance.displayPixelWidth, 96)
        XCTAssertEqual(prepared.provenance.displayPixelHeight, 160)
        XCTAssertEqual(try pixelBufferBytes(accepted.pixelBuffer), beforeBuffer)
        XCTAssertEqual(try rgba(XCTUnwrap(accepted.displayImage)), beforeDisplay)
        XCTAssertEqual(fixture.store.snapshot()?.sourceFrameId, "later-frame")
    }

    func testMissingDisplayImageIsTypedFailureWithoutImplicitRendering() async throws {
        let fixture = try makeFixture(render: false)
        await assertFailure(.missingDisplayImage, snapshot: fixture.accepted)
        XCTAssertNil(fixture.accepted.displayImage)
    }

    func testUnknownSessionAndInvalidTimestampDoNotBecomeInventedProvenance() async throws {
        let fixture = try makeFixture()
        let unknownEvidence = try XCTUnwrap(LatestFrameEvidenceStore.Snapshot(
            pixelBuffer: fixture.accepted.pixelBuffer, orientation: .up, sourceFrameId: "legacy-frame",
            capturedAt: fixture.accepted.capturedAt, isStable: true,
            lensGeneration: 7, samplePresentationTimestamp: CMTime(value: 1, timescale: 600),
            sessionGeneration: nil
        ))
        let unknown = LatestFrameEvidenceStore.AcceptedSnapshot(
            snapshotID: "legacy-snapshot", evidence: unknownEvidence,
            displayImage: fixture.accepted.displayImage
        )
        await assertFailure(.unknownProvenance(.sessionGeneration), snapshot: unknown)
        let invalidDateEvidence = try XCTUnwrap(LatestFrameEvidenceStore.Snapshot(
            pixelBuffer: fixture.accepted.pixelBuffer, orientation: .up, sourceFrameId: "invalid-date",
            capturedAt: Date(timeIntervalSince1970: .infinity), isStable: true,
            lensGeneration: 7, samplePresentationTimestamp: CMTime(value: 1, timescale: 600),
            sessionGeneration: 0
        ))
        let invalidDate = LatestFrameEvidenceStore.AcceptedSnapshot(
            snapshotID: "invalid-date-snapshot", evidence: invalidDateEvidence,
            displayImage: fixture.accepted.displayImage
        )
        await assertFailure(.unknownProvenance(.capturedAt), snapshot: invalidDate)
    }

    func testDisplayDimensionsMustBelongToAcceptedOrientation() async throws {
        let fixture = try makeFixture(width: 160, height: 96, orientation: .right)
        let other = try makeFixture(width: 160, height: 96, orientation: .up)
        let mismatched = fixture.accepted.withDisplayImage(try XCTUnwrap(other.accepted.displayImage))
        await assertFailure(.displayImageDimensionsMismatch, snapshot: mismatched)
    }

    func testImageMaskIsExplicitlyUnsupported() async throws {
        let fixture = try makeFixture(width: 160, height: 96)
        let bytes = Data(repeating: 128, count: 160 * 96)
        let provider = try XCTUnwrap(CGDataProvider(data: bytes as CFData))
        let mask = try XCTUnwrap(CGImage(maskWidth: 160, height: 96, bitsPerComponent: 8,
                                       bitsPerPixel: 8, bytesPerRow: 160, provider: provider,
                                       decode: nil, shouldInterpolate: false))
        await assertFailure(.unsupportedImageFormat, snapshot: fixture.accepted.withDisplayImage(mask))
    }

    func testPrecancelledRequestReturnsTypedCancellation() async throws {
        let fixture = try makeFixture()
        let task = Task { () -> CameraCloudFramePreprocessingError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await CameraCloudFramePreprocessor.prepare(snapshot: fixture.accepted)
                return nil
            } catch {
                return error as? CameraCloudFramePreprocessingError
            }
        }
        let failure = await task.value
        XCTAssertEqual(failure, .cancelled)
    }

    func testJPEGMetadataRemovalRejectsMalformedHeadersAndPreservesCompressedPixels() throws {
        let fixture = try makeFixture(width: 160, height: 96)
        let display = try XCTUnwrap(fixture.accepted.displayImage)
        let buffer = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            buffer, "public.jpeg" as CFString, 1, nil
        ))
        let properties: [String: Any] = [
            kCGImageDestinationLossyCompressionQuality as String: 0.85,
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifUserComment as String: "SYNTHETIC PRIVATE COMMENT"
            ],
            kCGImagePropertyGPSDictionary as String: [
                kCGImagePropertyGPSLatitude as String: 12.25,
                kCGImagePropertyGPSLatitudeRef as String: "N",
                kCGImagePropertyGPSLongitude as String: 34.5,
                kCGImagePropertyGPSLongitudeRef as String: "E"
            ]
        ]
        CGImageDestinationAddImage(destination, display, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let input = buffer as Data
        let inputDigest = SHA256.hash(data: input)
        let inputProperties = try imageProperties(input)
        let exif = try XCTUnwrap(inputProperties[kCGImagePropertyExifDictionary as String] as? [String: Any])
        XCTAssertEqual(exif[kCGImagePropertyExifUserComment as String] as? String,
                       "SYNTHETIC PRIVATE COMMENT")
        XCTAssertNotNil(inputProperties[kCGImagePropertyGPSDictionary as String])

        let cleaned = try CameraCloudFramePreprocessor.removingJPEGMetadata(input)
        let outputProperties = try imageProperties(cleaned)
        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyExifAuxDictionary,
                    kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary] {
            XCTAssertNil(outputProperties[key as String])
        }
        XCTAssertEqual(try rgba(decode(input)), try rgba(decode(cleaned)),
                       "Metadata removal must not recompress or recolor pixels")
        XCTAssertEqual(SHA256.hash(data: input), inputDigest)
        XCTAssertEqual(try CameraCloudFramePreprocessor.removingJPEGMetadata(cleaned), cleaned)

        // ImageIO does not write arbitrary MakerNote values. Insert a valid TIFF
        // Exif IFD with an UNDEFINED MakerNote payload and verify the physical bytes.
        let maker = Data("SYNTHETIC PRIVATE MAKER".utf8)
        let tiff = Data([0x49, 0x49, 0x2a, 0, 8, 0, 0, 0,
                         1, 0, 0x69, 0x87, 4, 0, 1, 0, 0, 0, 26, 0, 0, 0, 0, 0, 0, 0,
                         1, 0, 0x7c, 0x92, 7, 0, UInt8(maker.count), 0, 0, 0, 44, 0, 0, 0,
                         0, 0, 0, 0]) + maker
        let payload = Data("Exif\0\0".utf8) + tiff
        let length = payload.count + 2
        let segment = Data([0xff, 0xe1, UInt8(length >> 8), UInt8(length & 0xff)]) + payload
        let makerInput = Data(cleaned.prefix(2)) + segment + Data(cleaned.dropFirst(2))
        let makerDigest = SHA256.hash(data: makerInput)
        XCTAssertNotNil(makerInput.range(of: maker))
        let makerOutput = try CameraCloudFramePreprocessor.removingJPEGMetadata(makerInput)
        XCTAssertEqual(makerOutput, cleaned)
        XCTAssertNil(makerOutput.range(of: maker))
        XCTAssertEqual(try rgba(decode(makerInput)), try rgba(decode(makerOutput)))
        XCTAssertEqual(SHA256.hash(data: makerInput), makerDigest)

        // APP2 may carry the ICC profile; it must survive byte-for-byte.
        let app2 = Data([0xff, 0xe2, 0, 0x12]) + Data("ICC_PROFILE\0".utf8) + Data([1, 1, 8, 9])
        let withAPP2 = Data(input.prefix(2)) + app2 + Data(input.dropFirst(2))
        XCTAssertEqual(try CameraCloudFramePreprocessor.removingJPEGMetadata(withAPP2),
                       Data(cleaned.prefix(2)) + app2 + Data(cleaned.dropFirst(2)))

        let malformed: [[UInt8]] = [[], [0xff], [0xff, 0xd8], [0, 0, 0, 0],
            [0xff, 0xd8, 0xff, 0xff], [0xff, 0xd8, 0xff, 0xe1],
            [0xff, 0xd8, 0xff, 0xe1, 0], [0xff, 0xd8, 0xff, 0xe1, 0, 0],
            [0xff, 0xd8, 0xff, 0xe1, 0, 1], [0xff, 0xd8, 0xff, 0xe1, 0xff, 0xff],
            [0xff, 0xd8, 0xff, 0xd9], [0xff, 0xd8, 0xff, 0xd0],
            [0xff, 0xd8, 0xff, 0x00], [0xff, 0xd8, 0xff, 0x01],
            [0xff, 0xd8, 0x12, 0x34], [0xff, 0xd8, 0xff, 0xe1, 0, 2]]
        for bytes in malformed {
            XCTAssertThrowsError(try CameraCloudFramePreprocessor.removingJPEGMetadata(Data(bytes))) {
                XCTAssertEqual($0 as? CameraCloudFramePreprocessingError, .invalidEncodedImage)
            }
        }
    }

    private func assertFailure(_ expected: CameraCloudFramePreprocessingError,
                               snapshot: LatestFrameEvidenceStore.AcceptedSnapshot,
                               file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await CameraCloudFramePreprocessor.prepare(snapshot: snapshot)
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? CameraCloudFramePreprocessingError, expected, file: file, line: line)
        }
    }

    private func makeFixture(width: Int = 160, height: Int = 96,
                             orientation: CGImagePropertyOrientation = .up,
                             noise: Bool = false, render: Bool = true) throws
        -> (store: LatestFrameEvidenceStore, accepted: LatestFrameEvidenceStore.AcceptedSnapshot) {
        let buffer = try makePixelBuffer(width: width, height: height, noise: noise)
        let store = LatestFrameEvidenceStore()
        XCTAssertTrue(store.publish(
            pixelBuffer: buffer, orientation: orientation, sourceFrameId: "accepted-frame",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000.125), isStable: true,
            lensID: "fixture-lens", lensGeneration: 7,
            samplePresentationTimestamp: CMTime(value: 1_200, timescale: 600), sessionGeneration: 0
        ))
        let accepted = try XCTUnwrap(store.acceptCurrentSnapshot())
        if render { return (store, try XCTUnwrap(store.renderDisplayImage(for: accepted))) }
        return (store, accepted)
    }

    private func makePixelBuffer(width: Int, height: Int, noise: Bool) throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                        [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary,
                                        &result)
        XCTAssertEqual(status, kCVReturnSuccess)
        let buffer = try XCTUnwrap(result)
        XCTAssertEqual(CVPixelBufferLockBaseAddress(buffer, []), kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        memset(base, 0, rowBytes * height)
        let colors: [[UInt8]] = [[25, 35, 220], [30, 210, 40], [215, 40, 30], [25, 210, 215]]
        var random: UInt32 = 0x5e70_5123
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * rowBytes + x * 4
                if noise {
                    for channel in 0..<3 {
                        random = random &* 1_664_525 &+ 1_013_904_223
                        base[offset + channel] = UInt8(truncatingIfNeeded: random >> 24)
                    }
                } else {
                    let color = colors[(y >= height / 2 ? 2 : 0) + (x >= width / 2 ? 1 : 0)]
                    for channel in 0..<3 { base[offset + channel] = color[channel] }
                }
                base[offset + 3] = 255
            }
        }
        return buffer
    }

    private func pixelBufferBytes(_ buffer: CVPixelBuffer) throws -> Data {
        XCTAssertEqual(CVPixelBufferLockBaseAddress(buffer, .readOnly), kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        return Data(bytes: base, count: CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
    }

    private func decode(_ data: Data) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 1)
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func imageProperties(_ data: Data) throws -> [String: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
    }

    private func rgba(_ image: CGImage) throws -> [UInt8] {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
                                            bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                            space: space, bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                                                | CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pointer = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: pointer, count: image.width * image.height * 4))
    }
}
