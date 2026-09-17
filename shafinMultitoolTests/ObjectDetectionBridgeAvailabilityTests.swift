import XCTest
import CoreVideo
@testable import shafinMultitool

@MainActor
final class ObjectDetectionBridgeAvailabilityTests: XCTestCase {
    func testUnavailableDoesNotBecomeSuccessfulEmpty() async throws {
        let bridge = ObjectDetectionBridge(
            testingDetectionOperation: nil,
            currentDate: { Date(timeIntervalSince1970: 1_000) }
        )
        let result = await detect(bridge, buffer: try makePixelBuffer())

        assertFailure(result, .modelUnavailable)
        assertFailure(bridge.lastDetectionResult, .modelUnavailable)
        XCTAssertFalse(bridge.isReady)
        XCTAssertTrue(bridge.lastDetections.isEmpty)
    }

    func testSuccessfulEmptyRemainsSuccessfulDuringThrottle() async throws {
        var calls = 0
        let bridge = ObjectDetectionBridge(
            testingDetectionOperation: { _, completion in
                calls += 1
                completion(.success([]))
            },
            currentDate: { Date(timeIntervalSince1970: 1_000) }
        )
        let buffer = try makePixelBuffer()

        let initial = await detect(bridge, buffer: buffer)
        let cached = await detect(bridge, buffer: buffer)
        XCTAssertTrue(try initial.get().isEmpty)
        XCTAssertTrue(try cached.get().isEmpty)
        XCTAssertTrue(try bridge.lastDetectionResult.get().isEmpty)
        XCTAssertEqual(calls, 1)
    }

    func testFailureClearsSuccessfulCacheAndDetectedPositionsAndCanRecover() async throws {
        let failures: [DETRDetectionFailure] = [
            .modelUnavailable, .inferenceFailed, .missingOutput, .invalidOutput
        ]
        let buffer = try makePixelBuffer()
        for failure in failures {
            var now = Date(timeIntervalSince1970: 1_000)
            var calls = 0
            let detection = makeChair(confidence: 0.8)
            var nextResult: DETRDetectionResult = .success([detection])
            let bridge = ObjectDetectionBridge(
                testingDetectionOperation: { _, completion in
                    calls += 1
                    completion(nextResult)
                },
                currentDate: { now }
            )

            let initial = await detect(bridge, buffer: buffer)
            XCTAssertEqual(try initial.get().map(\.id), [detection.id])
            XCTAssertEqual(bridge.findObject(ofType: .chair)?.id, detection.id)

            now = now.addingTimeInterval(1)
            nextResult = .failure(failure)
            assertFailure(await detect(bridge, buffer: buffer), failure)
            assertFailure(bridge.lastDetectionResult, failure)
            XCTAssertTrue(bridge.lastDetections.isEmpty)
            XCTAssertNil(bridge.findObject(ofType: .chair))
            XCTAssertTrue(bridge.findAllObjects(ofType: .chair).isEmpty)
            XCTAssertTrue(bridge.detectedObjectsWithRussianLabels().isEmpty)

            let previouslyLocatedObject = SceneObject(
                id: "chair_1",
                type: .chair,
                detectedPosition: Position3D(x: 1, y: 0, z: -2),
                relativePosition: .center
            )
            let matched = bridge.matchObjectsWithDetections([previouslyLocatedObject], arFrame: nil)
            XCTAssertNil(matched[0].detectedPosition)

            // A request inside the interval must return the failure, not the prior chair.
            assertFailure(await detect(bridge, buffer: buffer), failure)
            XCTAssertEqual(calls, 2)

            now = now.addingTimeInterval(1)
            nextResult = .success([detection])
            let recovered = await detect(bridge, buffer: buffer)
            XCTAssertEqual(try recovered.get().map(\.id), [detection.id])
            XCTAssertEqual(bridge.lastDetections.map(\.id), [detection.id])
            XCTAssertEqual(calls, 3)
        }

        let table = DETRDetection(
            boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4),
            label: "dining table",
            confidence: 0.8
        )
        // Both valid empty and a different current object must replace the old chair.
        for replacements in [[], [table]] {
            var now = Date(timeIntervalSince1970: 2_000)
            var calls = 0
            let chair = makeChair(confidence: 0.8)
            var nextResult: DETRDetectionResult = .success([chair])
            let bridge = ObjectDetectionBridge(
                testingDetectionOperation: { _, completion in
                    calls += 1
                    completion(nextResult)
                },
                currentDate: { now }
            )
            let initial = await detect(bridge, buffer: buffer)
            XCTAssertEqual(try initial.get().map(\.id), [chair.id])
            XCTAssertEqual(bridge.findObject(ofType: .chair)?.id, chair.id)

            now = now.addingTimeInterval(1)
            nextResult = .success(replacements)
            let replacement = await detect(bridge, buffer: buffer)
            XCTAssertEqual(try replacement.get().map(\.id), replacements.map(\.id))
            XCTAssertEqual(bridge.lastDetections.map(\.id), replacements.map(\.id))
            XCTAssertNil(bridge.findObject(ofType: .chair))
            XCTAssertEqual(bridge.findObject(ofType: .table)?.id, replacements.first?.id)

            let previouslyLocatedChair = SceneObject(
                id: "chair_1", type: .chair, name: "Wooden chair",
                detectedPosition: Position3D(x: 1, y: 0, z: -2),
                relativePosition: .left
            )
            let matched = bridge.matchObjectsWithDetections([previouslyLocatedChair], arFrame: nil)
            var expected = previouslyLocatedChair
            expected.detectedPosition = nil
            XCTAssertEqual(matched, [expected], "No matching current detection may retain an old detected position")
            XCTAssertEqual(calls, 2)
        }
    }

    func testSuccessfulDetectionKeepsExistingLabelAndConfidenceFiltering() async throws {
        let accepted = makeChair(confidence: 0.3)
        let belowThreshold = makeChair(confidence: 0.29)
        let irrelevant = DETRDetection(
            boundingBox: accepted.boundingBox,
            label: "dog",
            confidence: 0.9
        )
        let bridge = ObjectDetectionBridge(
            testingDetectionOperation: { _, completion in
                completion(.success([belowThreshold, irrelevant, accepted]))
            },
            currentDate: { Date(timeIntervalSince1970: 1_000) }
        )
        let result = await detect(bridge, buffer: try makePixelBuffer())
        let detections = try result.get()

        XCTAssertEqual(detections.map(\.id), [accepted.id])
        XCTAssertEqual(detections[0].boundingBox, accepted.boundingBox)
        XCTAssertEqual(detections[0].confidence, accepted.confidence)
        XCTAssertNil(detections[0].worldPosition)
    }

    private func detect(
        _ bridge: ObjectDetectionBridge,
        buffer: CVPixelBuffer
    ) async -> SceneObjectDetectionResult {
        await withCheckedContinuation { continuation in
            bridge.detectObjects(in: buffer, arFrame: nil) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func assertFailure(
        _ result: SceneObjectDetectionResult,
        _ expected: DETRDetectionFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(let failure) = result else {
            XCTFail("Expected detector failure, received success", file: file, line: line)
            return
        }
        XCTAssertEqual(failure.rawValue, expected.rawValue, file: file, line: line)
    }

    private func makeChair(confidence: Float) -> DETRDetection {
        DETRDetection(
            boundingBox: CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5),
            label: "chair",
            confidence: confidence
        )
    }

    private func makePixelBuffer() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, 4, 4, kCVPixelFormatType_32BGRA, nil, &buffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        return try XCTUnwrap(buffer)
    }
}
