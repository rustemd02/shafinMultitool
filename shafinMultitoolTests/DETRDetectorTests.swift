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

import CoreMedia

/// Exercises only the injected object sequence; these tests do not run Vision,
/// CoreML, camera capture, or the detector's existing fixture inference.
final class VisionObjectTrackingTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 10_000)
    private let sourceBox = CGRect(x: 0.15, y: 0.2, width: 0.2, height: 0.3)
    private let measuredBox = CGRect(x: 0.3, y: 0.25, width: 0.2, height: 0.3)

    func testPrimesOriginalPixelsThenMeasuresCurrentPixelsWithoutRaisingDetectorSupport() throws {
        let sourcePixels = try pixels()
        let currentPixels = try pixels()
        let source = frame(0)
        let current = frame(200)
        let sequence = RecordingObjectSequence(replies: [
            .values([measurement(sourceBox)]),
            .values([measurement(measuredBox, quality: 0.99)])
        ])
        var requestedBoxes: [CGRect] = []
        let tracking = VisionTracking { boxes in
            requestedBoxes = boxes
            return sequence
        }
        XCTAssertTrue(tracking.offerObjectSeed(VisionObjectSeed(
            frame: source, pixelBuffer: sourcePixels,
            detections: [detection(support: 0.13)]
        )))

        let batch = try XCTUnwrap(tracking.trackObjects(
            pixelBuffer: currentPixels, frame: current, evaluatedAt: at(220)
        ))

        XCTAssertEqual(requestedBoxes, [sourceBox])
        XCTAssertEqual(sequence.pixelIdentities, [identity(sourcePixels), identity(currentPixels)])
        XCTAssertEqual(sequence.orientations, [.up, .up])
        XCTAssertEqual(batch.source, source)
        XCTAssertEqual(batch.current, current)
        XCTAssertEqual(batch.detections.count, 1)
        XCTAssertEqual(batch.detections.first?.boundingBox, measuredBox)
        XCTAssertEqual(batch.detections.first?.label, "cup")
        XCTAssertEqual(batch.detections.first?.confidence, Float(0.13))
        XCTAssertEqual(batch.qualities, [Float(0.99)])
        XCTAssertEqual(batch.sourceCandidateCount, 1)
    }

    func testRepeatedCurrentMeasurementsKeepOriginalAgeAndExpireWithoutResurrection() throws {
        let sourcePixels = try pixels()
        let currentPixels = try pixels()
        let source = frame(0)
        let sequence = RecordingObjectSequence(replies: [
            .values([measurement(sourceBox)]),
            .values([measurement(measuredBox)]),
            .values([measurement(measuredBox)])
        ])
        let tracking = VisionTracking { _ in sequence }
        let seed = VisionObjectSeed(frame: source, pixelBuffer: sourcePixels, detections: [detection()])
        XCTAssertTrue(tracking.offerObjectSeed(seed))

        for milliseconds in [200, 900] {
            let batch = try XCTUnwrap(tracking.trackObjects(
                pixelBuffer: currentPixels, frame: frame(milliseconds), evaluatedAt: at(milliseconds)
            ))
            XCTAssertEqual(batch.source, source, "Tracking must not renew the detector's image age")
            XCTAssertEqual(batch.detections.first?.confidence, Float(0.3))
        }
        XCTAssertNil(tracking.trackObjects(
            pixelBuffer: currentPixels, frame: frame(1_201), evaluatedAt: at(1_201)
        ))
        XCTAssertNil(tracking.trackObjects(
            pixelBuffer: currentPixels, frame: frame(1_220), evaluatedAt: at(1_220)
        ))
        XCTAssertFalse(tracking.offerObjectSeed(seed))
        XCTAssertEqual(sequence.pixelIdentities.count, 3, "Expired seeds must not run the sequence again")
    }

    func testCapturePresentationAndEvaluationAgesIndependentlyLimitSeedLifetime() throws {
        let seedPixels = try pixels()
        let currentPixels = try pixels()
        let cases: [(String, VisionObjectFrame, Date)] = [
            ("old source pixels by PTS", frame(1_500, capturedMilliseconds: 100), at(100)),
            ("old source pixels by capture date", frame(100, capturedMilliseconds: 1_500), at(1_500)),
            ("inference or delivery latency", frame(100), at(1_500)),
            ("evaluation before current capture", frame(100), at(99))
        ]
        for (name, current, evaluatedAt) in cases {
            let sequence = RecordingObjectSequence(replies: [
                .values([measurement(sourceBox)]), .values([measurement(measuredBox)])
            ])
            let tracking = VisionTracking { _ in sequence }
            XCTAssertTrue(tracking.offerObjectSeed(VisionObjectSeed(
                frame: frame(0), pixelBuffer: seedPixels, detections: [detection()]
            )), name)
            XCTAssertNil(tracking.trackObjects(
                pixelBuffer: currentPixels, frame: current, evaluatedAt: evaluatedAt
            ), name)
            XCTAssertTrue(sequence.pixelIdentities.isEmpty, name)
        }
    }

    func testLossOnCurrentFrameDropsSlotWithoutReusingItsOldRectangle() throws {
        let badReplies: [(String, RecordingObjectSequence.Reply)] = [
            ("missing result", .values([nil])),
            ("empty result list", .values([])),
            ("sequence error", .failure),
            ("weak tracking", .values([measurement(measuredBox, quality: 0.74)])),
            ("nonfinite quality", .values([measurement(measuredBox, quality: .nan)])),
            ("quality above one", .values([measurement(measuredBox, quality: 1.01)])),
            ("fully outside left", .values([measurement(CGRect(x: -0.3, y: 0.2, width: 0.2, height: 0.2))])),
            ("fully outside right", .values([measurement(CGRect(x: 1, y: 0.2, width: 0.2, height: 0.2))])),
            ("visible sliver below existing area floor", .values([measurement(CGRect(x: 0.999, y: 0.2, width: 0.2, height: 0.2))])),
            ("empty box", .values([measurement(.zero)])),
            ("nonfinite box", .values([measurement(CGRect(x: CGFloat.nan, y: 0.2, width: 0.2, height: 0.2))]))
        ]
        for (name, badReply) in badReplies {
            let sourcePixels = try pixels()
            let currentPixels = try pixels()
            let sequence = RecordingObjectSequence(replies: [
                .values([measurement(sourceBox)]), badReply,
                .values([measurement(measuredBox)])
            ])
            let tracking = VisionTracking { _ in sequence }
            XCTAssertTrue(tracking.offerObjectSeed(VisionObjectSeed(
                frame: frame(0), pixelBuffer: sourcePixels, detections: [detection()]
            )), name)
            XCTAssertNil(tracking.trackObjects(
                pixelBuffer: currentPixels, frame: frame(100), evaluatedAt: at(100)
            ), name)
            XCTAssertNil(tracking.trackObjects(
                pixelBuffer: currentPixels, frame: frame(200), evaluatedAt: at(200)
            ), name)
            XCTAssertEqual(sequence.pixelIdentities, [identity(sourcePixels), identity(currentPixels)], name)
        }
    }

    func testFailedPrimingDoesNotMeasureCurrentPixels() throws {
        let failures: [RecordingObjectSequence.Reply] = [
            .failure, .values([nil]), .values([]),
            .values([measurement(sourceBox, quality: 0.5)])
        ]
        for failure in failures {
            let sourcePixels = try pixels()
            let sequence = RecordingObjectSequence(replies: [
                failure, .values([measurement(measuredBox)])
            ])
            let tracking = VisionTracking { _ in sequence }
            XCTAssertTrue(tracking.offerObjectSeed(VisionObjectSeed(
                frame: frame(0), pixelBuffer: sourcePixels, detections: [detection()]
            )))
            XCTAssertNil(tracking.trackObjects(
                pixelBuffer: try pixels(), frame: frame(100), evaluatedAt: at(100)
            ))
            XCTAssertNil(tracking.trackObjects(
                pixelBuffer: try pixels(), frame: frame(200), evaluatedAt: at(200)
            ))
            XCTAssertEqual(sequence.pixelIdentities, [identity(sourcePixels)])
        }
    }

    func testDuplicateAndReverseFramesDoNotAdvanceSequence() throws {
        let sourcePixels = try pixels()
        let currentPixels = try pixels()
        let sequence = RecordingObjectSequence(replies: [
            .values([measurement(sourceBox)]),
            .values([measurement(measuredBox)]),
            .values([measurement(measuredBox)])
        ])
        let tracking = VisionTracking { _ in sequence }
        XCTAssertTrue(tracking.offerObjectSeed(VisionObjectSeed(
            frame: frame(0), pixelBuffer: sourcePixels, detections: [detection()]
        )))
        XCTAssertNotNil(tracking.trackObjects(
            pixelBuffer: currentPixels, frame: frame(200), evaluatedAt: at(200)
        ))
        for rejected in [frame(200), frame(150), frame(200, id: "other-id"),
                         frame(250, id: "frame-200")] {
            XCTAssertNil(tracking.trackObjects(
                pixelBuffer: currentPixels, frame: rejected, evaluatedAt: at(300)
            ))
        }
        XCTAssertEqual(sequence.pixelIdentities.count, 2)
        XCTAssertNotNil(tracking.trackObjects(
            pixelBuffer: currentPixels, frame: frame(300), evaluatedAt: at(300)
        ))
        XCTAssertEqual(sequence.pixelIdentities.count, 3)
    }

    func testFutureAndEqualSeedPixelsWaitForAnActuallyLaterMeasurement() throws {
        let sourcePixels = try pixels()
        let currentPixels = try pixels()
        let sequence = RecordingObjectSequence(replies: [
            .values([measurement(sourceBox)]), .values([measurement(measuredBox)])
        ])
        let tracking = VisionTracking { _ in sequence }
        XCTAssertNil(tracking.trackObjects(
            pixelBuffer: currentPixels, frame: frame(100), evaluatedAt: at(100)
        ))
        XCTAssertTrue(tracking.offerObjectSeed(VisionObjectSeed(
            frame: frame(200), pixelBuffer: sourcePixels, detections: [detection()]
        )))
        for milliseconds in [150, 200] {
            XCTAssertNil(tracking.trackObjects(
                pixelBuffer: currentPixels, frame: frame(milliseconds), evaluatedAt: at(milliseconds)
            ))
        }
        XCTAssertTrue(sequence.pixelIdentities.isEmpty)
        let batch = try XCTUnwrap(tracking.trackObjects(
            pixelBuffer: currentPixels, frame: frame(300), evaluatedAt: at(300)
        ))
        XCTAssertEqual(batch.source, frame(200))
        XCTAssertEqual(batch.current, frame(300))
        XCTAssertEqual(sequence.pixelIdentities, [identity(sourcePixels), identity(currentPixels)])
    }

    func testNewerEmptySeedIsBarrierAgainstLatePositiveCallbacks() throws {
        let pixelBuffer = try pixels()
        var sequences: [RecordingObjectSequence] = []
        let tracking = VisionTracking { _ in
            let sequence = RecordingObjectSequence(replies: [
                .values([self.measurement(self.sourceBox)]),
                .values([self.measurement(self.measuredBox)])
            ])
            sequences.append(sequence)
            return sequence
        }
        XCTAssertTrue(tracking.offerObjectSeed(VisionObjectSeed(
            frame: frame(0), pixelBuffer: pixelBuffer, detections: [detection()]
        )))
        XCTAssertNotNil(tracking.trackObjects(
            pixelBuffer: pixelBuffer, frame: frame(100), evaluatedAt: at(100)
        ))
        XCTAssertTrue(tracking.offerObjectSeed(VisionObjectSeed(
            frame: frame(200), pixelBuffer: pixelBuffer, detections: []
        )))
        XCTAssertNil(tracking.trackObjects(
            pixelBuffer: pixelBuffer, frame: frame(250), evaluatedAt: at(250)
        ))
        for milliseconds in [0, 150, 200] {
            XCTAssertFalse(tracking.offerObjectSeed(VisionObjectSeed(
                frame: frame(milliseconds), pixelBuffer: pixelBuffer, detections: [detection()]
            )))
        }
        XCTAssertNil(tracking.trackObjects(
            pixelBuffer: pixelBuffer, frame: frame(275), evaluatedAt: at(275)
        ))
        XCTAssertEqual(sequences.count, 1)
        XCTAssertEqual(sequences.first?.pixelIdentities.count, 2)
        XCTAssertTrue(tracking.offerObjectSeed(VisionObjectSeed(
            frame: frame(300), pixelBuffer: pixelBuffer, detections: [detection(label: "vase")]
        )))
        let recovered = try XCTUnwrap(tracking.trackObjects(
            pixelBuffer: pixelBuffer, frame: frame(400), evaluatedAt: at(400)
        ))
        XCTAssertEqual(recovered.detections.first?.label, "vase")
        XCTAssertEqual(recovered.source, frame(300))
        XCTAssertEqual(sequences.count, 2)
    }

    func testNewerPositiveSeedWinsOverLateOlderCallback() throws {
        let olderPixels = try pixels()
        let newerPixels = try pixels()
        let currentPixels = try pixels()
        let sequence = RecordingObjectSequence(replies: [
            .values([measurement(sourceBox)]), .values([measurement(measuredBox)])
        ])
        let tracking = VisionTracking { _ in sequence }
        XCTAssertTrue(tracking.offerObjectSeed(VisionObjectSeed(
            frame: frame(200), pixelBuffer: newerPixels, detections: [detection(label: "vase")]
        )))
        XCTAssertFalse(tracking.offerObjectSeed(VisionObjectSeed(
            frame: frame(100), pixelBuffer: olderPixels, detections: [detection(label: "cup")]
        )))
        let batch = try XCTUnwrap(tracking.trackObjects(
            pixelBuffer: currentPixels, frame: frame(300), evaluatedAt: at(300)
        ))
        XCTAssertEqual(batch.source, frame(200))
        XCTAssertEqual(batch.detections.first?.label, "vase")
        XCTAssertEqual(sequence.pixelIdentities, [identity(newerPixels), identity(currentPixels)])
    }

    func testEveryEpochChangeDropsActiveSequenceAndRejectsOldCallback() throws {
        let variants: [(UInt64, UInt64?, UInt64, CGImagePropertyOrientation)] = [
            (2, 0, 7, .up), (1, 1, 7, .up), (1, 0, 8, .up), (1, 0, 7, .right)
        ]
        for (capture, session, lifecycle, orientation) in variants {
            let pixelBuffer = try pixels()
            var sequences: [RecordingObjectSequence] = []
            let tracking = VisionTracking { _ in
                let sequence = RecordingObjectSequence(replies: [
                    .values([self.measurement(self.sourceBox)]),
                    .values([self.measurement(self.measuredBox)])
                ])
                sequences.append(sequence)
                return sequence
            }
            XCTAssertTrue(tracking.offerObjectSeed(VisionObjectSeed(
                frame: frame(0), pixelBuffer: pixelBuffer, detections: [detection()]
            )))
            XCTAssertNotNil(tracking.trackObjects(
                pixelBuffer: pixelBuffer, frame: frame(100), evaluatedAt: at(100)
            ))
            let first = frame(200, capture: capture, session: session, lifecycle: lifecycle, orientation: orientation)
            XCTAssertNil(tracking.trackObjects(
                pixelBuffer: pixelBuffer, frame: first, evaluatedAt: at(200)
            ))
            XCTAssertFalse(tracking.offerObjectSeed(VisionObjectSeed(
                frame: frame(150), pixelBuffer: pixelBuffer, detections: [detection()]
            )))
            let seed = frame(250, capture: capture, session: session, lifecycle: lifecycle, orientation: orientation)
            XCTAssertTrue(tracking.offerObjectSeed(VisionObjectSeed(
                frame: seed, pixelBuffer: pixelBuffer, detections: [detection()]
            )))
            let current = frame(300, capture: capture, session: session, lifecycle: lifecycle, orientation: orientation)
            let batch = try XCTUnwrap(tracking.trackObjects(
                pixelBuffer: pixelBuffer, frame: current, evaluatedAt: at(300)
            ))
            XCTAssertEqual(batch.source, seed)
            XCTAssertEqual(batch.current, current)
            XCTAssertEqual(sequences.count, 2)
            XCTAssertEqual(sequences[0].pixelIdentities.count, 2)
            XCTAssertEqual(sequences[1].orientations, [orientation, orientation])
        }
    }

    func testFirstCurrentFrameOfAnotherEpochClearsPendingSeedOrderingBarrier() throws {
        let pixelBuffer = try pixels()
        let sequence = RecordingObjectSequence(replies: [
            .values([measurement(sourceBox)]), .values([measurement(measuredBox)])
        ])
        let tracking = VisionTracking { _ in sequence }
        XCTAssertTrue(tracking.offerObjectSeed(VisionObjectSeed(
            frame: frame(0), pixelBuffer: pixelBuffer, detections: [detection()]
        )))
        XCTAssertNil(tracking.trackObjects(
            pixelBuffer: pixelBuffer, frame: frame(100, capture: 2), evaluatedAt: at(100)
        ))
        XCTAssertTrue(tracking.offerObjectSeed(VisionObjectSeed(
            frame: frame(150, capture: 2), pixelBuffer: pixelBuffer, detections: [detection()]
        )), "An old pending epoch must not poison the new epoch's ordering barrier")
        let batch = try XCTUnwrap(tracking.trackObjects(
            pixelBuffer: pixelBuffer, frame: frame(200, capture: 2), evaluatedAt: at(200)
        ))
        XCTAssertEqual(batch.source, frame(150, capture: 2))
        XCTAssertEqual(sequence.pixelIdentities.count, 2)
    }

    func testLostSlotNeverBorrowsAnotherObjectsLabelOrReappearsWithoutDetection() throws {
        let pixelBuffer = try pixels()
        let secondBox = CGRect(x: 0.6, y: 0.2, width: 0.2, height: 0.3)
        let sequence = RecordingObjectSequence(replies: [
            .values([measurement(sourceBox), measurement(secondBox)]),
            .values([nil, measurement(secondBox)]),
            .values([measurement(measuredBox), measurement(secondBox)])
        ])
        let tracking = VisionTracking { _ in sequence }
        XCTAssertTrue(tracking.offerObjectSeed(VisionObjectSeed(
            frame: frame(0), pixelBuffer: pixelBuffer,
            detections: [detection(label: "cup"), detection(label: "vase", box: secondBox)]
        )))
        for milliseconds in [100, 200] {
            let batch = try XCTUnwrap(tracking.trackObjects(
                pixelBuffer: pixelBuffer, frame: frame(milliseconds), evaluatedAt: at(milliseconds)
            ))
            XCTAssertEqual(batch.detections.map(\.label), ["vase"])
            XCTAssertEqual(batch.detections.map(\.boundingBox), [secondBox])
            XCTAssertEqual(batch.qualities.count, 1)
            XCTAssertEqual(batch.sourceCandidateCount, 2,
                           "Losing one object must not make the remaining observation set complete")
        }
    }

    func testUnknownFramesAndExplicitResetCannotContinueExistingSequence() throws {
        let pixelBuffer = try pixels()
        let unknowns = [
            frame(200, id: ""), frame(200, capture: 0), frame(200, session: nil),
            frame(200, pts: .invalid)
        ]
        for unknown in unknowns {
            let sequence = RecordingObjectSequence(replies: [
                .values([measurement(sourceBox)]), .values([measurement(measuredBox)])
            ])
            let tracking = VisionTracking { _ in sequence }
            XCTAssertFalse(tracking.offerObjectSeed(VisionObjectSeed(
                frame: unknown, pixelBuffer: pixelBuffer, detections: [detection()]
            )))
            XCTAssertTrue(tracking.offerObjectSeed(VisionObjectSeed(
                frame: frame(0), pixelBuffer: pixelBuffer, detections: [detection()]
            )))
            XCTAssertNotNil(tracking.trackObjects(
                pixelBuffer: pixelBuffer, frame: frame(100), evaluatedAt: at(100)
            ))
            XCTAssertNil(tracking.trackObjects(
                pixelBuffer: pixelBuffer, frame: unknown, evaluatedAt: at(200)
            ))
            XCTAssertNil(tracking.trackObjects(
                pixelBuffer: pixelBuffer, frame: frame(300), evaluatedAt: at(300)
            ))
            XCTAssertEqual(sequence.pixelIdentities.count, 2)
            tracking.resetObjectTracking()
            XCTAssertTrue(tracking.offerObjectSeed(VisionObjectSeed(
                frame: frame(0), pixelBuffer: pixelBuffer, detections: [detection()]
            )), "Explicit reset permits a fresh sequence whose capture clock restarted")
        }
    }

    func testSequenceReceivesAtMostFourValidSeedRectangles() throws {
        let pixelBuffer = try pixels()
        let good = (0..<6).map { index in
            detection(label: "object-\(index)",
                      box: CGRect(x: Double(index) * 0.1, y: 0.2, width: 0.08, height: 0.2))
        }
        let invalid = [
            detection(box: .zero),
            detection(box: CGRect(x: 0.95, y: 0.2, width: 0.1, height: 0.2)),
            detection(support: .nan)
        ]
        let expected = Array(good.prefix(4))
        let measurements = expected.map { Optional(measurement($0.boundingBox)) }
        let sequence = RecordingObjectSequence(replies: [.values(measurements), .values(measurements)])
        var receivedBoxes: [CGRect] = []
        let tracking = VisionTracking { boxes in receivedBoxes = boxes; return sequence }
        XCTAssertTrue(tracking.offerObjectSeed(VisionObjectSeed(
            frame: frame(0), pixelBuffer: pixelBuffer, detections: invalid + good
        )))
        let batch = try XCTUnwrap(tracking.trackObjects(
            pixelBuffer: pixelBuffer, frame: frame(100), evaluatedAt: at(100)
        ))
        XCTAssertEqual(receivedBoxes, expected.map(\.boundingBox))
        XCTAssertEqual(batch.detections.map(\.label), expected.map(\.label))
        XCTAssertEqual(batch.detections.count, 4)
        XCTAssertEqual(batch.sourceCandidateCount, invalid.count + good.count)
        XCTAssertGreaterThan(batch.sourceCandidateCount, batch.detections.count,
                             "Filtering and the request cap must preserve known coverage gaps")
    }

    func testVisibleIntersectionPreservesRawEdgesWithoutClaimingEntityVisibility() throws {
        let boundary = CGRect(x: 0, y: 0, width: 1, height: 1)
        let full = try XCTUnwrap(VisionObjectGeometry(seedSlot: 0, rawBoundingBox: boundary))
        XCTAssertEqual(full.rawBoundingBox, boundary)
        XCTAssertEqual(full.visibleImageIntersection, boundary)
        XCTAssertEqual(full.rectangleClippedFraction, 0)
        XCTAssertTrue(full.clippedEdges.isEmpty, "Boundary contact alone does not prove physical full visibility")
        let raw = CGRect(x: -0.25, y: -0.25, width: 1.5, height: 1.5)
        let clipped = try XCTUnwrap(VisionObjectGeometry(seedSlot: 2, rawBoundingBox: raw))
        XCTAssertEqual(clipped.rawBoundingBox, raw)
        XCTAssertEqual(clipped.visibleImageIntersection, boundary)
        XCTAssertEqual(clipped.rectangleClippedFraction, 1 - 1 / 2.25, accuracy: 1e-12)
        XCTAssertEqual(clipped.clippedEdges, [.left, .bottom, .right, .top])
        XCTAssertEqual(clipped.seedSlot, 2)
        XCTAssertTrue(clipped.hasClippedTrackingGeometry)
        let sliver = try XCTUnwrap(VisionObjectGeometry(
            seedSlot: 0, rawBoundingBox: CGRect(x: 0.999, y: 0.2, width: 0.3, height: 0.3)))
        XCTAssertFalse(sliver.meetsPublicationArea)
        XCTAssertTrue(sliver.hasClippedTrackingGeometry)
    }

    func testMalformedAndDisjointRawGeometryCannotCreateVisibleEvidence() {
        let invalid = [
            CGRect.zero, CGRect(x: 0.5, y: 0.5, width: -0.2, height: 0.2),
            CGRect(x: 0.5, y: 0.5, width: 0.2, height: -0.2),
            CGRect(x: CGFloat.nan, y: 0, width: 0.3, height: 0.3),
            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 0.3),
            CGRect(x: 1, y: 0, width: 0.2, height: 0.2),
            CGRect(x: -0.2, y: 0, width: 0.2, height: 0.2),
            CGRect(x: 0, y: 1.1, width: 0.2, height: 0.2)
        ]
        for box in invalid { XCTAssertNil(VisionObjectGeometry(seedSlot: 0, rawBoundingBox: box)) }
        for slot in [-1, 4] { XCTAssertNil(VisionObjectGeometry(seedSlot: slot, rawBoundingBox: sourceBox)) }
    }

    func testClippedCurrentMeasurementsKeepSourceSlotQualityAndSupportWithoutRenewingAge() throws {
        let pixelBuffer = try pixels()
        let raw = CGRect(x: 0.8, y: -0.01, width: 0.3, height: 0.4)
        let sequence = RecordingObjectSequence(replies: [
            .values([measurement(sourceBox), measurement(sourceBox)]),
            .values([measurement(raw, quality: 0.91), measurement(measuredBox, quality: 0.749)])
        ])
        let tracking = VisionTracking { _ in sequence }
        XCTAssertTrue(tracking.offerObjectSeed(VisionObjectSeed(
            frame: frame(0), pixelBuffer: pixelBuffer,
            detections: [detection(label: "chair", support: 0.56), detection(label: "cup", support: 0.99)])))
        let batch = try XCTUnwrap(tracking.trackObjects(
            pixelBuffer: pixelBuffer, frame: frame(100), evaluatedAt: at(100)))
        let geometry = try XCTUnwrap(batch.geometries.first)
        XCTAssertEqual(batch.detections.map(\.label), ["chair"])
        XCTAssertEqual(batch.detections.first?.confidence, Float(0.56))
        XCTAssertEqual(batch.qualities, [Float(0.91)])
        XCTAssertEqual(geometry.rawBoundingBox, raw)
        XCTAssertEqual(geometry.clippedEdges, [.bottom, .right])
        XCTAssertEqual(batch.detections.first?.boundingBox, geometry.visibleImageIntersection)
        XCTAssertEqual(geometry.seedSlot, 0)
        XCTAssertEqual(batch.source, frame(0))
        XCTAssertEqual(batch.sourceCandidateCount, 2)
        XCTAssertNil(tracking.trackObjects(pixelBuffer: pixelBuffer, frame: frame(1_201), evaluatedAt: at(1_201)))
    }

    private func at(_ milliseconds: Int) -> Date {
        origin.addingTimeInterval(Double(milliseconds) / 1_000)
    }

    private func frame(_ milliseconds: Int, id: String? = nil,
                       capture: UInt64 = 1, session: UInt64? = 0,
                       lifecycle: UInt64 = 7, orientation: CGImagePropertyOrientation = .up,
                       capturedMilliseconds: Int? = nil, pts: CMTime? = nil) -> VisionObjectFrame {
        VisionObjectFrame(
            frameID: id ?? "frame-\(milliseconds)", captureGeneration: capture,
            sessionGeneration: session, lifecycleGeneration: lifecycle, orientation: orientation,
            samplePTS: pts ?? CMTime(value: Int64(milliseconds), timescale: 1_000),
            capturedAt: at(capturedMilliseconds ?? milliseconds)
        )
    }

    private func detection(label: String = "cup", box: CGRect? = nil,
                           support: Float = 0.3) -> DETRDetection {
        DETRDetection(boundingBox: box ?? sourceBox, label: label, confidence: support)
    }

    private func measurement(_ box: CGRect, quality: Float = 0.95) -> VisionObjectMeasurement {
        VisionObjectMeasurement(boundingBox: box, quality: quality)
    }

    private func pixels() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, 8, 8, kCVPixelFormatType_32BGRA, nil, &buffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        return try XCTUnwrap(buffer)
    }

    private func identity(_ pixels: CVPixelBuffer) -> ObjectIdentifier {
        ObjectIdentifier(pixels as AnyObject)
    }

    private final class RecordingObjectSequence: VisionObjectSequence {
        enum Reply {
            case values([VisionObjectMeasurement?])
            case failure
        }
        enum Failure: Error { case requested, unexpectedExtraMeasurement }
        private let replies: [Reply]
        private var nextReply = 0
        private(set) var pixelIdentities: [ObjectIdentifier] = []
        private(set) var orientations: [CGImagePropertyOrientation] = []

        init(replies: [Reply]) { self.replies = replies }

        func measure(pixelBuffer: CVPixelBuffer,
                     orientation: CGImagePropertyOrientation) throws -> [VisionObjectMeasurement?] {
            pixelIdentities.append(ObjectIdentifier(pixelBuffer as AnyObject))
            orientations.append(orientation)
            guard replies.indices.contains(nextReply) else {
                throw Failure.unexpectedExtraMeasurement
            }
            let reply = replies[nextReply]
            nextReply += 1
            switch reply {
            case .values(let measurements): return measurements
            case .failure: throw Failure.requested
            }
        }
    }
}
