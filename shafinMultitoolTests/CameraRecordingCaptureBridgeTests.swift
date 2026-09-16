import CoreVideo
import XCTest
@testable import shafinMultitool

final class CameraRecordingCaptureBridgeTests: XCTestCase {
    func testFormatPolicyKeepsConfirmedModeAndSelectsOnlyActualSameSizeOptions() throws {
        var readback = CameraProControlReadback()
        readback.width = 1920; readback.height = 1080; readback.fixedFPS = 60; readback.formatID = "1080p60"
        var capabilities = CameraProControlCapabilities()
        capabilities.formats = [
            .init(id: "4k30", width: 3840, height: 2160, fps: 30),
            .init(id: "1080p60", width: 1920, height: 1080, fps: 60),
            .init(id: "1080p30", width: 1920, height: 1080, fps: 30)
        ]
        func snapshot() -> CameraProControlsSnapshot {
            .init(deviceID: "actual-camera", captureGeneration: 1, capabilities: capabilities, readback: readback)
        }
        XCTAssertNil(try CameraRecordingCapturePolicy.formatToApply(snapshot()))
        readback.fixedFPS = nil; readback.formatID = nil
        XCTAssertEqual(try CameraRecordingCapturePolicy.formatToApply(snapshot())?.id, "1080p30")
        capabilities.formats.removeAll { $0.width == 1920 }
        XCTAssertThrowsError(try CameraRecordingCapturePolicy.formatToApply(snapshot())) {
            XCTAssertEqual($0 as? CameraRecordingCaptureError, .formatUnavailable)
        }
    }

    func testFractionalOrInvalidFrameRateIsNotRoundedIntoAClaimedRecordingRate() {
        for value: Double? in [nil, .nan, .infinity, 0, -1, 29.97, 59.94, 241] {
            XCTAssertNil(CameraRecordingCapturePolicy.fixedFramesPerSecond(value))
        }
        XCTAssertEqual(CameraRecordingCapturePolicy.fixedFramesPerSecond(24), 24)
        XCTAssertEqual(CameraRecordingCapturePolicy.fixedFramesPerSecond(60), 60)
    }

    func testFirstFrameRequiresFreshTimestampAndCurrentCaptureGeneration() async throws {
        let bridge = CameraRecordingCaptureBridge()
        let lease = try bridge.reserve(ownerID: UUID(), sessionGeneration: 9)
        defer { bridge.release(lease) }
        let context = makeContext(lease, generation: 9, minimum: 100)
        let waiting = Task { try await bridge.waitForFirstFrame(context: context) }
        defer { waiting.cancel() }
        try await waitUntilRegistered(bridge)
        let pixels = try pixelBuffer()
        XCTAssertNil(bridge.forwardVideo(pixels, hostTimestamp: 101, sessionGeneration: 8))
        XCTAssertNil(bridge.forwardVideo(pixels, hostTimestamp: 99, sessionGeneration: 9))
        XCTAssertNil(bridge.forwardVideo(pixels, hostTimestamp: .nan, sessionGeneration: 9))
        XCTAssertTrue(bridge.hasPendingFirstFrameForTesting)
        XCTAssertNil(bridge.forwardVideo(pixels, hostTimestamp: 100.5, sessionGeneration: 9))
        let prepared = try await waiting.value
        XCTAssertEqual(prepared.lease, lease)
        XCTAssertEqual(prepared.timestamp, 100.5)
        XCTAssertEqual(prepared.fps, 30)
        XCTAssertTrue(prepared.pixelBuffer === pixels)
        XCTAssertNil(prepared.audioDriverFactory)
    }

    func testChangedPixelFormatFailsPreparationAndClosesAdmission() async throws {
        let bridge = CameraRecordingCaptureBridge()
        let lease = try bridge.reserve(ownerID: UUID(), sessionGeneration: 1)
        defer { bridge.release(lease) }
        let waiting = Task { try await bridge.waitForFirstFrame(context: makeContext(lease)) }
        defer { waiting.cancel() }
        try await waitUntilRegistered(bridge)
        let differentSize = try pixelBuffer(width: 320)
        XCTAssertEqual(bridge.forwardVideo(differentSize, hostTimestamp: 1, sessionGeneration: 1), .sourceChanged)
        do { _ = try await waiting.value; XCTFail("A changed input cannot be accepted as the prepared format") }
        catch { XCTAssertEqual(error as? CameraRecordingCaptureError, .sourceChanged) }
        XCTAssertFalse(bridge.startAudio(lease: lease, driverID: UUID(), handler: { _, _ in }))
    }

    func testCanceledPreparationCannotReopenItsClosedLease() async throws {
        let bridge = CameraRecordingCaptureBridge()
        let lease = try bridge.reserve(ownerID: UUID(), sessionGeneration: 1)
        defer { bridge.release(lease) }
        let context = makeContext(lease)
        let waiting = Task { try await bridge.waitForFirstFrame(context: context) }
        try await waitUntilRegistered(bridge)
        waiting.cancel()
        do { _ = try await waiting.value; XCTFail("Canceled waiter must fail") }
        catch { XCTAssertEqual(error as? CameraRecordingCaptureError, .staleLease) }
        XCTAssertFalse(bridge.validates(lease, sessionGeneration: 1))
        do {
            _ = try await bridge.waitForFirstFrame(context: context, timeout: 0.05)
            XCTFail("A delayed preparation must not reopen a canceled lease")
        } catch { XCTAssertEqual(error as? CameraRecordingCaptureError, .staleLease) }
        XCTAssertNil(bridge.forwardVideo(try pixelBuffer(), hostTimestamp: 1, sessionGeneration: 1))
    }

    func testFirstFrameTimeoutIsTypedAndCannotRegisterAudioDriver() async throws {
        let bridge = CameraRecordingCaptureBridge()
        let lease = try bridge.reserve(ownerID: UUID(), sessionGeneration: 1)
        defer { bridge.release(lease) }
        do {
            _ = try await bridge.waitForFirstFrame(context: makeContext(lease, audio: true), timeout: 0.05)
            XCTFail("No native frame must never become a ready recording")
        } catch { XCTAssertEqual(error as? CameraRecordingCaptureError, .noFrames) }
        XCTAssertFalse(bridge.startAudio(lease: lease, driverID: UUID(), handler: { _, _ in }))
    }

    func testOldLeaseAndAudioDriverCannotClearNewTake() async throws {
        let bridge = CameraRecordingCaptureBridge()
        let owner = UUID()
        let old = try bridge.reserve(ownerID: owner, sessionGeneration: 1)
        bridge.release(old)
        let lease = try bridge.reserve(ownerID: owner, sessionGeneration: 2)
        defer { bridge.release(lease) }
        let waiting = Task { try await bridge.waitForFirstFrame(context: makeContext(lease, generation: 2, audio: true)) }
        defer { waiting.cancel() }
        try await waitUntilRegistered(bridge)
        bridge.closeAdmission(old)
        bridge.release(old)
        XCTAssertTrue(bridge.hasPendingFirstFrameForTesting)
        XCTAssertNil(bridge.forwardVideo(try pixelBuffer(), hostTimestamp: 1, sessionGeneration: 2))
        let prepared = try await waiting.value
        let factory = try XCTUnwrap(prepared.audioDriverFactory)
        let configuration = RecordingConfiguration(id: RecordingID(rawValue: UUID()),
            outputURL: URL(fileURLWithPath: "/unused.mov"), width: 640,
            height: 480, fps: 30, audioMode: .required)
        let driver = try factory.makeAudioDriver(for: configuration)
        XCTAssertTrue(driver.start(onFrame: { _, _ in }))
        bridge.stopAudio(lease: old, driverID: UUID())
        XCTAssertFalse(bridge.startAudio(lease: lease, driverID: UUID(), handler: { _, _ in }),
                       "Only the current registered audio driver owns the callback")
        driver.stop()
        XCTAssertTrue(bridge.startAudio(lease: lease, driverID: UUID(), handler: { _, _ in }))
        bridge.closeAdmission(lease)
        XCTAssertFalse(driver.start(onFrame: { _, _ in }))
    }

    private func waitUntilRegistered(_ bridge: CameraRecordingCaptureBridge) async throws {
        for _ in 0..<100 {
            if bridge.hasPendingFirstFrameForTesting { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("First-frame waiter was never registered")
        throw CameraRecordingCaptureError.noFrames
    }

    private func makeContext(_ lease: CameraRecordingCaptureLease, generation: UInt64 = 1,
                             minimum: TimeInterval = 0, audio: Bool = false) -> CameraRecordingCaptureBridge.Context {
        .init(lease: lease, sessionGeneration: generation, deviceID: "fixture-device", formatID: "fixture-format",
              width: 640, height: 480, fps: 30, pixelFormat: kCVPixelFormatType_32BGRA,
              minimumHostTimestamp: minimum,
              trackTransform: .init(captureOrientation: .portrait, isMirrored: false,
                  strategy: .preferredTransformMetadata, pixelOrientationBaseline: .nativeLandscapeRight),
              audioEnabled: audio)
    }

    private func pixelBuffer(width: Int = 640) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, width, 480,
            kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        return try XCTUnwrap(buffer)
    }
}
