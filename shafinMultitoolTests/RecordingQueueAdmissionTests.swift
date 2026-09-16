import Foundation
import XCTest
@testable import shafinMultitool

@MainActor
final class RecordingQueueAdmissionTests: XCTestCase {
    func testBlockedWriterBoundsRetainedVideoPayloadsAndPreservesElapsedTimeAcrossDrops() async throws {
        let entered = expectation(description: "first native append is held")
        let finishing = expectation(description: "one finish requested")
        let fixture = makeFixture(videoCapacity: 2, onAppend: { entered.fulfill() },
                                  onFinish: { finishing.fulfill() })
        defer { fixture.writer.unblock(); fixture.writer.completeFinish() }
        let fence = try await start(fixture)
        let payloads = QueuePayloadLifetime()
        fixture.recorder.enqueueVideo(video(fence, timestamp: 100, lifetime: payloads))
        await fulfillment(of: [entered], timeout: 2)
        fixture.recorder.enqueueVideo(video(fence, timestamp: 100 + 1.0 / 30, lifetime: payloads))
        for index in 2..<102 {
            fixture.recorder.enqueueVideo(video(fence, timestamp: 100 + Double(index) / 30, lifetime: payloads))
        }
        XCTAssertEqual(payloads.live, 2, "Only the held append and one queued frame may retain pixels")
        XCTAssertLessThanOrEqual(payloads.peak, 3, "A rejected caller temporary must be released immediately")
        fixture.writer.unblock()
        _ = await fixture.recorder.stateSnapshot()
        fixture.recorder.enqueueVideo(video(fence, timestamp: 110, lifetime: payloads))
        _ = await fixture.recorder.stateSnapshot()
        let stop = Task { await fixture.recorder.stop(reason: .user) }
        await fulfillment(of: [finishing], timeout: 2)
        XCTAssertEqual(fixture.writer.finishCount, 1)
        fixture.writer.completeFinish()
        let result = await stop.value
        guard case .finalized(let artifact) = result else { return XCTFail("Expected finalized take, got \(result)") }
        XCTAssertEqual(try XCTUnwrap(artifact.duration), 10, accuracy: 0.000_001)
        XCTAssertEqual(fixture.writer.videoTimestamps, [100, 100 + 1.0 / 30, 110])
        let report = await fixture.recorder.timebaseReport()
        XCTAssertEqual(report.acceptedVideoCount, 3)
        XCTAssertEqual(report.droppedVideoCount, 100)
        XCTAssertEqual(report.videoOrigin, 100)
        XCTAssertEqual(report.lastVideoTimestamp, 110)
        XCTAssertEqual(payloads.live, 0)
        XCTAssertFalse(fixture.writer.appendTimedOut)
        _ = await fixture.recorder.releaseAndWait()
    }

    func testAudioPayloadCapacityIsIndependentWhileNativeVideoAppendIsHeld() async throws {
        let entered = expectation(description: "video append held")
        let finishing = expectation(description: "finish requested")
        let fixture = makeFixture(audioMode: .required, videoCapacity: 2, audioCapacity: 3,
                                  onAppend: { entered.fulfill() }, onFinish: { finishing.fulfill() })
        defer { fixture.writer.unblock(); fixture.writer.completeFinish() }
        let fence = try await start(fixture)
        fixture.recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 100))
        await fulfillment(of: [entered], timeout: 2)
        let payloads = QueuePayloadLifetime()
        for index in 0..<50 {
            fixture.recorder.enqueueAudio(RecordingAudioFrame(
                fence: fence, timestamp: 100.01 + Double(index) / 100,
                payload: QueueTrackedPayload(lifetime: payloads)
            ))
        }
        XCTAssertEqual(payloads.live, 3)
        XCTAssertLessThanOrEqual(payloads.peak, 4)
        fixture.writer.unblock()
        _ = await fixture.recorder.stateSnapshot()
        let stop = Task { await fixture.recorder.stop(reason: .user) }
        await fulfillment(of: [finishing], timeout: 2)
        fixture.writer.completeFinish()
        let result = await stop.value
        guard case .finalized(let artifact) = result else { return XCTFail("Expected finalized A/V take") }
        XCTAssertTrue(artifact.hasAudio)
        XCTAssertEqual(fixture.writer.audioTimestamps.count, 3)
        for (index, timestamp) in fixture.writer.audioTimestamps.enumerated() {
            XCTAssertEqual(timestamp, 100.01 + Double(index) / 100, accuracy: 0.000_001)
        }
        let snapshot = await fixture.recorder.stateSnapshot()
        XCTAssertEqual(snapshot.droppedAudioCount, 47)
        XCTAssertEqual(snapshot.droppedVideoCount, 0)
        XCTAssertEqual(payloads.live, 0)
        XCTAssertEqual(fixture.writer.maximumConcurrentAppends, 1)
        _ = await fixture.recorder.releaseAndWait()
    }

    func testSustainedQueueOverflowFailsAndStopReleaseShareOneFinalization() async throws {
        let entered = expectation(description: "native append held")
        let finishing = expectation(description: "finish requested once")
        let fixture = makeFixture(videoCapacity: 2, dropLimit: 2,
                                  onAppend: { entered.fulfill() }, onFinish: { finishing.fulfill() })
        defer { fixture.writer.unblock(); fixture.writer.completeFinish() }
        let fence = try await start(fixture)
        fixture.recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 1))
        await fulfillment(of: [entered], timeout: 2)
        fixture.recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 2))
        fixture.recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 3))
        fixture.recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 4))
        fixture.writer.unblock()
        let failed = await fixture.recorder.stateSnapshot()
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(failed.droppedVideoCount, 2)
        let stop = Task { await fixture.recorder.stop(reason: .user) }
        let release = Task { await fixture.recorder.releaseAndWait() }
        await fulfillment(of: [finishing], timeout: 2)
        XCTAssertEqual(fixture.writer.finishCount, 1)
        fixture.writer.completeFinish(twice: true)
        let result = await stop.value
        let released = await release.value
        guard case .failed(let failure, _) = result else { return XCTFail("Overload must not claim success") }
        XCTAssertEqual(failure, .videoAppendFailed)
        XCTAssertEqual(released, result)
        let repeated = await fixture.recorder.stop(reason: .background)
        XCTAssertEqual(repeated, result)
        let terminal = await fixture.recorder.stateSnapshot()
        XCTAssertEqual(terminal.state, .released)
        XCTAssertEqual(terminal.droppedVideoCount, 2)
        XCTAssertEqual(fixture.writer.finishCount, 1)
    }

    func testForeignFrameCannotTakeCapacityAndLateStoppedFrameCannotReviveWriter() async throws {
        let entered = expectation(description: "native append held")
        let finishing = expectation(description: "finish requested")
        let fixture = makeFixture(videoCapacity: 2, onAppend: { entered.fulfill() },
                                  onFinish: { finishing.fulfill() })
        defer { fixture.writer.unblock(); fixture.writer.completeFinish() }
        let fence = try await start(fixture)
        fixture.recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 10))
        await fulfillment(of: [entered], timeout: 2)
        let foreign = RecordingFrameFence(recordingID: fence.recordingID, generation: fence.generation + 1)
        let rejectedPayloads = QueuePayloadLifetime()
        for index in 0..<20 {
            fixture.recorder.enqueueVideo(video(foreign, timestamp: 11 + Double(index), lifetime: rejectedPayloads))
        }
        XCTAssertEqual(rejectedPayloads.live, 0)
        fixture.recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 11))
        fixture.writer.unblock()
        _ = await fixture.recorder.stateSnapshot()
        let stop = Task { await fixture.recorder.stop(reason: .user) }
        await fulfillment(of: [finishing], timeout: 2)
        fixture.recorder.enqueueVideo(video(fence, timestamp: 12, lifetime: rejectedPayloads))
        XCTAssertEqual(rejectedPayloads.live, 0)
        fixture.writer.completeFinish()
        let result = await stop.value
        guard case .finalized = result else { return XCTFail("Expected finalized valid frames") }
        let report = await fixture.recorder.timebaseReport()
        XCTAssertEqual(report.rejectedStaleSourceCount, 20)
        XCTAssertEqual(report.rejectedInactiveCount, 1)
        XCTAssertEqual(report.droppedVideoCount, 0)
        XCTAssertEqual(fixture.writer.videoTimestamps, [10, 11])
        _ = await fixture.recorder.releaseAndWait()
    }

    func testIdleStopDoesNotPermanentlyDisableLaterLegitimatePreparation() async throws {
        let finishing = expectation(description: "later take finalizes")
        let fixture = makeFixture(onAppend: {}, onFinish: { finishing.fulfill() }, holdFirstAppend: false)
        _ = await fixture.recorder.stop(reason: .user)
        let fence = try await start(fixture)
        fixture.recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 1))
        let stop = Task { await fixture.recorder.stop(reason: .user) }
        await fulfillment(of: [finishing], timeout: 2)
        fixture.writer.completeFinish()
        let result = await stop.value
        guard case .finalized = result else { return XCTFail("An idle stop must not poison a later take") }
        _ = await fixture.recorder.releaseAndWait()
    }

    func testStopClosesAdmissionWhileWriterHeldAndDrainsBothPreviouslyAdmittedFrames() async throws {
        let entered = expectation(description: "first native append held")
        let finishing = expectation(description: "finish follows admitted frames")
        let fixture = makeFixture(videoCapacity: 2, onAppend: { entered.fulfill() },
                                  onFinish: { finishing.fulfill() })
        defer { fixture.writer.unblock(); fixture.writer.completeFinish() }
        let fence = try await start(fixture)
        let payloads = QueuePayloadLifetime()
        fixture.recorder.enqueueVideo(video(fence, timestamp: 10, lifetime: payloads))
        await fulfillment(of: [entered], timeout: 2)
        fixture.recorder.enqueueVideo(video(fence, timestamp: 12, lifetime: payloads))
        let stop = Task { await fixture.recorder.stop(reason: .background) }
        for _ in 0..<100 {
            if !fixture.recorder.frameSubmissionOpenForTesting { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(fixture.recorder.frameSubmissionOpenForTesting)
        XCTAssertEqual(payloads.live, 2)
        XCTAssertEqual(fixture.writer.finishCount, 0)
        fixture.recorder.enqueueVideo(video(fence, timestamp: 20, lifetime: payloads))
        XCTAssertEqual(payloads.live, 2, "The post-stop payload cannot enter the held queue")
        fixture.writer.unblock()
        await fulfillment(of: [finishing], timeout: 2)
        XCTAssertEqual(fixture.writer.videoTimestamps, [10, 12])
        fixture.writer.completeFinish()
        let result = await stop.value
        guard case .finalized(let artifact) = result else { return XCTFail("Admitted frames must finalize") }
        XCTAssertEqual(try XCTUnwrap(artifact.duration), 2, accuracy: 0.000_001)
        XCTAssertEqual(payloads.live, 0)
        let report = await fixture.recorder.timebaseReport()
        XCTAssertEqual(report.acceptedVideoCount, 2)
        XCTAssertEqual(report.rejectedInactiveCount, 1)
        XCTAssertEqual(report.droppedVideoCount, 0)
        _ = await fixture.recorder.releaseAndWait()
    }

    private struct Fixture {
        let recorder: SerializedMediaRecorder
        let writer: QueueHeldWriter
        let configuration: RecordingConfiguration
    }

    private func makeFixture(audioMode: RecordingAudioMode = .disabled,
                             videoCapacity: Int = 4, audioCapacity: Int = 16, dropLimit: Int = 900,
                             onAppend: @escaping @Sendable () -> Void,
                             onFinish: @escaping @Sendable () -> Void,
                             holdFirstAppend: Bool = true) -> Fixture {
        let writer = QueueHeldWriter(onAppend: onAppend, onFinish: onFinish, holdFirstAppend: holdFirstAppend)
        let recorder = SerializedMediaRecorder(
            writerFactory: QueueWriterFactory(writer: writer),
            audioDriverFactory: audioMode == .required ? QueueAudioFactory() : nil,
            outputChecker: QueueNoExistingOutput(),
            maxConsecutiveDroppedFrames: dropLimit,
            maxQueuedVideoFrames: videoCapacity, maxQueuedAudioFrames: audioCapacity,
            finalizationTimeout: 3
        )
        let id = RecordingID(rawValue: UUID())
        let configuration = RecordingConfiguration(
            id: id, outputURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(id.rawValue).mov"),
            width: 640, height: 480, fps: 30, audioMode: audioMode
        )
        return Fixture(recorder: recorder, writer: writer, configuration: configuration)
    }

    private func start(_ fixture: Fixture) async throws -> RecordingFrameFence {
        try await fixture.recorder.prepare(fixture.configuration)
        try await fixture.recorder.start()
        let snapshot = await fixture.recorder.stateSnapshot()
        return try XCTUnwrap(snapshot.frameFence)
    }

    private func video(_ fence: RecordingFrameFence, timestamp: TimeInterval,
                       lifetime: QueuePayloadLifetime) -> RecordingVideoFrame {
        RecordingVideoFrame(fence: fence, timestamp: timestamp, payload: QueueTrackedPayload(lifetime: lifetime))
    }
}

private final class QueuePayloadLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var maximum = 0
    var live: Int { lock.lock(); defer { lock.unlock() }; return count }
    var peak: Int { lock.lock(); defer { lock.unlock() }; return maximum }
    func retain() { lock.lock(); defer { lock.unlock() }; count += 1; maximum = max(maximum, count) }
    func release() { lock.lock(); defer { lock.unlock() }; count -= 1 }
}

private final class QueueTrackedPayload: RecordingVideoFramePayload, RecordingAudioFramePayload, @unchecked Sendable {
    private let lifetime: QueuePayloadLifetime
    init(lifetime: QueuePayloadLifetime) { self.lifetime = lifetime; lifetime.retain() }
    deinit { lifetime.release() }
}

private struct QueueWriterFactory: RecordingWriterFactory {
    let writer: QueueHeldWriter
    func makeWriter(for configuration: RecordingConfiguration) throws -> any RecordingWriter { writer }
}

private struct QueueNoExistingOutput: RecordingOutputChecking {
    func exists(at url: URL) -> Bool { false }
}

private struct QueueAudioFactory: RecordingAudioDriverFactory {
    func makeAudioDriver(for configuration: RecordingConfiguration) throws -> any RecordingAudioDriver { QueueAudioDriver() }
}

private final class QueueAudioDriver: RecordingAudioDriver {
    func start(onFrame: @escaping RecordingAudioFrameHandler) -> Bool { true }
    func stop() {}
}

private final class QueueHeldWriter: RecordingWriter, @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private let onAppend: @Sendable () -> Void
    private let onFinish: @Sendable () -> Void
    private let holdFirstAppend: Bool
    private var videos: [TimeInterval] = []
    private var audios: [TimeInterval] = []
    private var concurrent = 0
    private var maximumConcurrent = 0
    private var finishes = 0
    private var timedOut = false
    private var finishCallback: ((Result<RecordingWriterFinish, RecordingWriterError>) -> Void)?

    init(onAppend: @escaping @Sendable () -> Void, onFinish: @escaping @Sendable () -> Void,
         holdFirstAppend: Bool) {
        self.onAppend = onAppend; self.onFinish = onFinish; self.holdFirstAppend = holdFirstAppend
    }
    var videoTimestamps: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return videos }
    var audioTimestamps: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return audios }
    var finishCount: Int { lock.lock(); defer { lock.unlock() }; return finishes }
    var maximumConcurrentAppends: Int { lock.lock(); defer { lock.unlock() }; return maximumConcurrent }
    var appendTimedOut: Bool { lock.lock(); defer { lock.unlock() }; return timedOut }
    func start() -> Bool { true }
    func appendVideo(_ frame: RecordingVideoFrame) -> RecordingAppendDisposition {
        lock.lock()
        let first = videos.isEmpty
        concurrent += 1; maximumConcurrent = max(maximumConcurrent, concurrent)
        lock.unlock()
        if first {
            onAppend()
            if holdFirstAppend, gate.wait(timeout: .now() + 5) == .timedOut {
                lock.lock(); timedOut = true; lock.unlock()
            }
        }
        lock.lock(); videos.append(frame.timestamp); concurrent -= 1; lock.unlock()
        return .appended
    }
    func appendAudio(_ frame: RecordingAudioFrame) -> RecordingAppendDisposition {
        lock.lock(); defer { lock.unlock() }
        concurrent += 1; maximumConcurrent = max(maximumConcurrent, concurrent)
        audios.append(frame.timestamp); concurrent -= 1
        return .appended
    }
    func markVideoInputAsFinished() {}
    func markAudioInputAsFinished() {}
    func finishWriting(completion: @escaping (Result<RecordingWriterFinish, RecordingWriterError>) -> Void) {
        lock.lock(); finishes += 1; finishCallback = completion; lock.unlock()
        onFinish()
    }
    func discard() {}
    func unblock() { gate.signal() }
    func completeFinish(twice: Bool = false) {
        lock.lock()
        let callback = finishCallback
        let duration = videos.first.flatMap { first in videos.last.map { $0 - first } }
        let result = RecordingWriterFinish(duration: duration, hasAudio: !audios.isEmpty)
        lock.unlock()
        callback?(.success(result))
        if twice { callback?(.success(result)) }
    }
}
