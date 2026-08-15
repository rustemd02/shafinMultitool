import CoreGraphics
import CoreVideo
import Dispatch
import XCTest
@testable import shafinMultitool

final class LatestFrameEvidenceStoreTests: XCTestCase {

    func testConcurrentPublishAndSnapshotNeverTearsTheEnvelope() {
        let store = LatestFrameEvidenceStore()
        let firstPixelBuffer = makePixelBuffer()
        let secondPixelBuffer = makePixelBuffer()
        let firstPixelBufferId = ObjectIdentifier(firstPixelBuffer as AnyObject)
        let secondPixelBufferId = ObjectIdentifier(secondPixelBuffer as AnyObject)
        let firstCapturedAt = Date(timeIntervalSince1970: 1)
        let secondCapturedAt = Date(timeIntervalSince1970: 2)
        let queue = DispatchQueue(label: "LatestFrameEvidenceStoreTests.concurrent", attributes: .concurrent)
        let group = DispatchGroup()
        let failureLock = NSLock()
        var failures = 0

        for writer in 0..<4 {
            group.enter()
            queue.async {
                defer { group.leave() }
                for iteration in 0..<2_000 {
                    let isFirst = (writer + iteration).isMultiple(of: 2)
                    _ = store.publish(
                        pixelBuffer: isFirst ? firstPixelBuffer : secondPixelBuffer,
                        orientation: isFirst ? .up : .down,
                        sourceFrameId: isFirst ? "frame-a" : "frame-b",
                        capturedAt: isFirst ? firstCapturedAt : secondCapturedAt,
                        isStable: isFirst
                    )
                }
            }
        }

        for _ in 0..<4 {
            group.enter()
            queue.async {
                defer { group.leave() }
                for _ in 0..<10_000 {
                    guard let snapshot = store.snapshot() else { continue }
                    let isFirst = snapshot.sourceFrameId == "frame-a"
                    let isValid = snapshot.sourceFrameId == (isFirst ? "frame-a" : "frame-b")
                        && snapshot.orientation == (isFirst ? .up : .down)
                        && snapshot.capturedAt == (isFirst ? firstCapturedAt : secondCapturedAt)
                        && snapshot.isStable == isFirst
                        && ObjectIdentifier(snapshot.pixelBuffer as AnyObject) == (isFirst ? firstPixelBufferId : secondPixelBufferId)
                    if !isValid {
                        failureLock.lock()
                        failures += 1
                        failureLock.unlock()
                    }
                }
            }
        }

        group.wait()
        XCTAssertEqual(failures, 0)
    }

    func testClearReturnsNilAndReplacementIsVisible() {
        let store = LatestFrameEvidenceStore()
        let firstPixelBuffer = makePixelBuffer()
        let secondPixelBuffer = makePixelBuffer()

        XCTAssertTrue(store.publish(
            pixelBuffer: firstPixelBuffer,
            orientation: .left,
            sourceFrameId: " first-frame ",
            capturedAt: Date(timeIntervalSince1970: 10),
            isStable: true
        ))
        XCTAssertEqual(store.snapshot()?.sourceFrameId, "first-frame")

        store.clear()
        XCTAssertNil(store.snapshot())

        XCTAssertFalse(store.publish(
            pixelBuffer: secondPixelBuffer,
            orientation: .right,
            sourceFrameId: "   ",
            capturedAt: Date(timeIntervalSince1970: 20),
            isStable: false
        ))
        XCTAssertNil(store.snapshot())

        XCTAssertTrue(store.publish(
            pixelBuffer: secondPixelBuffer,
            orientation: .right,
            sourceFrameId: "second-frame",
            capturedAt: Date(timeIntervalSince1970: 20),
            isStable: false
        ))
        let replacement = store.snapshot()
        XCTAssertEqual(replacement?.sourceFrameId, "second-frame")
        XCTAssertEqual(replacement?.orientation, .right)
        XCTAssertEqual(replacement?.capturedAt, Date(timeIntervalSince1970: 20))
        XCTAssertFalse(replacement?.isStable ?? true)
    }

    private func makePixelBuffer() -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: 4,
            kCVPixelBufferHeightKey as String: 4,
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            4,
            4,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        return pixelBuffer!
    }
}
