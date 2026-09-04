import XCTest
import CoreGraphics
import CoreML
import CoreVideo
import ImageIO
@testable import shafinMultitool

final class DETRDetectorTests: XCTestCase {
    private let chairClassID: Int32 = 62

    func testDisconnectedSameClassComponentsBecomeSeparateBoxes() throws {
        let array = try makeArray(
            shape: [10, 10],
            values: [
                (x: 1, y: 1), (x: 1, y: 2), (x: 2, y: 1),
                (x: 7, y: 7), (x: 7, y: 8), (x: 8, y: 7)
            ]
        )

        let detections = DETRDetector.extractDetections(from: array)

        XCTAssertEqual(detections.count, 2)
        XCTAssertEqual(detections.map(\.label), ["chair", "chair"])
        assertBox(detections[0].boundingBox, x: 0.1, y: 0.7, width: 0.2, height: 0.2)
        assertBox(detections[1].boundingBox, x: 0.7, y: 0.1, width: 0.2, height: 0.2)
        XCTAssertEqual(detections[0].confidence, 0.6, accuracy: 0.0001)
        XCTAssertEqual(detections[1].confidence, 0.6, accuracy: 0.0001)
    }

    func testTopOriginRowsConvertToVisionLowerLeftY() throws {
        let array = try makeArray(
            shape: [4, 5],
            values: [
                (x: 2, y: 0), (x: 3, y: 0),
                (x: 2, y: 1), (x: 3, y: 1)
            ]
        )

        let detections = DETRDetector.extractDetections(from: array)

        XCTAssertEqual(detections.count, 1)
        assertBox(detections[0].boundingBox, x: 0.4, y: 0.5, width: 0.4, height: 0.5)
    }

    func testSubThresholdNoiseIsDiscardedPerComponent() throws {
        let array = try makeArray(
            shape: [25, 40],
            values: [
                (x: 1, y: 1),
                (x: 10, y: 5), (x: 11, y: 5)
            ]
        )

        let detections = DETRDetector.extractDetections(from: array)

        XCTAssertEqual(detections.count, 1)
        XCTAssertEqual(detections[0].label, "chair")
        assertBox(detections[0].boundingBox, x: 0.25, y: 0.76, width: 0.05, height: 0.04)
        XCTAssertEqual(detections[0].confidence, 0.04, accuracy: 0.0001)
    }

    func testNonInt32AndNonRankTwoInputsFailClosed() throws {
        let floatArray = try MLMultiArray(shape: [2, 2].map { NSNumber(value: $0) }, dataType: .float32)
        let rankThreeArray = try MLMultiArray(shape: [2, 2, 1].map { NSNumber(value: $0) }, dataType: .int32)

        XCTAssertTrue(DETRDetector.extractDetections(from: floatArray).isEmpty)
        XCTAssertTrue(DETRDetector.extractDetections(from: rankThreeArray).isEmpty)
    }

    func testNontrivialStridesDriveLogicalPixelExtraction() throws {
        guard #available(iOS 18.0, *) else {
            throw XCTSkip("Custom MLMultiArray strides require iOS 18 or newer")
        }

        let array = try makeArray(
            shape: [3, 4],
            strides: [6, 2],
            values: [(x: 1, y: 2)]
        )

        XCTAssertEqual(array.strides.map { $0.intValue }, [6, 2])
        let detections = DETRDetector.extractDetections(from: array)

        XCTAssertEqual(detections.count, 1)
        assertBox(detections[0].boundingBox, x: 0.25, y: 0, width: 0.25, height: 1.0 / 3.0)
    }

    func testFixture019ProducesTwoChairDetections() async throws {
        let detector = try DETRDetector()
        let imageURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1/images/019.jpg")
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw XCTSkip("Fixture 019 is unavailable")
        }

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            image.width,
            image.height,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferCGImageCompatibilityKey: true,
             kCVPixelBufferCGBitmapContextCompatibilityKey: true,
             kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &pixelBuffer
        )
        guard let pixelBuffer else { throw XCTSkip("Fixture 019 pixel buffer is unavailable") }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            throw XCTSkip("Fixture 019 CGContext is unavailable")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        let detections = await withCheckedContinuation { continuation in
            detector.detect(pixelBuffer: pixelBuffer, orientation: .up) { continuation.resume(returning: $0) }
        }
        let chairs = detections.filter { $0.label == "chair" }
        XCTAssertEqual(chairs.count, 2)
        guard chairs.count == 2 else { return }
        let sortedChairs = chairs.sorted { $0.boundingBox.midX < $1.boundingBox.midX }
        let left = sortedChairs[0].boundingBox
        let right = sortedChairs[1].boundingBox
        XCTAssertGreaterThan(left.width * left.height, 0)
        XCTAssertGreaterThan(right.width * right.height, 0)
        XCTAssertGreaterThan(right.midX - left.midX, 0.1)
        XCTAssertTrue(left.intersection(right).isNull)
    }

    private func makeArray(shape: [Int],
                           strides: [Int]? = nil,
                           values: [(x: Int, y: Int)]) throws -> MLMultiArray {
        let array: MLMultiArray
        if let strides {
            guard #available(iOS 18.0, *) else {
                throw XCTSkip("Custom MLMultiArray strides require iOS 18 or newer")
            }
            array = MLMultiArray(shape: shape, dataType: .int32, strides: strides)
        } else {
            array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .int32)
        }

        let actualStrides = array.strides.map { $0.intValue }
        let pointer = array.dataPointer.assumingMemoryBound(to: Int32.self)
        for y in 0..<shape[0] {
            for x in 0..<shape[1] {
                pointer[y * actualStrides[0] + x * actualStrides[1]] = 0
            }
        }
        for value in values {
            pointer[value.y * actualStrides[0] + value.x * actualStrides[1]] = chairClassID
        }
        return array
    }

    private func assertBox(_ box: CGRect,
                           x: CGFloat,
                           y: CGFloat,
                           width: CGFloat,
                           height: CGFloat,
                           file: StaticString = #filePath,
                           line: UInt = #line) {
        XCTAssertEqual(box.minX, x, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(box.minY, y, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(box.width, width, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(box.height, height, accuracy: 0.0001, file: file, line: line)
    }
}
