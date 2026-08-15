import XCTest
@testable import shafinMultitool

final class SerializedMediaRecorderTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SerializedMediaRecorderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL,
                                                 withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        try super.tearDownWithError()
    }

    func testInitialStateIsIdle() async {
        let fixture = makeFixture()

        let snapshot = await fixture.recorder.stateSnapshot()

        XCTAssertEqual(snapshot.state, .idle)
        XCTAssertNil(snapshot.recordingID)
        XCTAssertEqual(snapshot.generation, 0)
    }

    func testPrepareDoesNotStartAudio() async throws {
        let fixture = makeFixture(audioMode: .required)

        try await fixture.recorder.prepare(makeConfiguration(audioMode: .required))

        XCTAssertEqual(fixture.writerFactory.makeCount, 1)
        XCTAssertEqual(fixture.writer.startCount, 0)
        XCTAssertEqual(fixture.audioFactory.makeCount, 0)
        XCTAssertEqual(fixture.audioDriver.startCount, 0)
        let state = await fixture.recorder.state
        XCTAssertEqual(state, .prepared)
    }

    func testPrepareIsIdempotentForSameConfigurationAndRejectsDifferentID() async throws {
        let fixture = makeFixture()
        let id = RecordingID(rawValue: UUID())
        let configuration = makeConfiguration(id: id)

        try await fixture.recorder.prepare(configuration)
        try await fixture.recorder.prepare(configuration)

        XCTAssertEqual(fixture.writerFactory.makeCount, 1)

        do {
            try await fixture.recorder.prepare(makeConfiguration(id: RecordingID(rawValue: UUID())))
            XCTFail("A prepared recorder must reject a different recording ID")
        } catch let error as RecorderFailure {
            XCTAssertEqual(error, .invalidTransition)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(fixture.writerFactory.makeCount, 1)
    }

    func testExistingOutputIsTypedFailure() async {
        let fixture = makeFixture()
        let configuration = makeConfiguration()
        fixture.outputChecker.existingURLs.insert(configuration.outputURL)

        do {
            try await fixture.recorder.prepare(configuration)
            XCTFail("Existing output should be rejected")
        } catch let error as RecorderFailure {
            XCTAssertEqual(error, .outputAlreadyExists)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(fixture.writerFactory.makeCount, 0)
    }

    func testWriterInputRejectionIsTyped() async {
        let fixture = makeFixture()
        fixture.writerFactory.error = .inputRejected

        do {
            try await fixture.recorder.prepare(makeConfiguration())
            XCTFail("Writer input rejection should be surfaced")
        } catch let error as RecorderFailure {
            XCTAssertEqual(error, .writerInputRejected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStartTwiceStartsWriterAndAudioOnce() async throws {
        let fixture = makeFixture(audioMode: .required)
        let configuration = makeConfiguration(audioMode: .required)

        try await fixture.recorder.prepare(configuration)
        try await fixture.recorder.start()
        try await fixture.recorder.start()

        XCTAssertEqual(fixture.writer.startCount, 1)
        XCTAssertEqual(fixture.audioFactory.makeCount, 1)
        XCTAssertEqual(fixture.audioDriver.startCount, 1)
        let state = await fixture.recorder.state
        XCTAssertEqual(state, .recording)

        _ = await fixture.recorder.releaseAndWait()
    }

    func testRequiredAudioFailureIsTyped() async throws {
        let fixture = makeFixture(audioMode: .required)
        fixture.audioFactory.error = .unavailable
        let configuration = makeConfiguration(audioMode: .required)

        try await fixture.recorder.prepare(configuration)

        do {
            try await fixture.recorder.start()
            XCTFail("Required audio failure should be surfaced")
        } catch let error as RecorderFailure {
            XCTAssertEqual(error, .audioUnavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(fixture.writer.startCount, 0)
        let state = await fixture.recorder.state
        XCTAssertEqual(state, .failed)
        _ = await fixture.recorder.releaseAndWait()
    }

    func testAudioStartFailureIsTyped() async throws {
        let fixture = makeFixture(audioMode: .required)
        fixture.audioDriver.startResult = false
        let configuration = makeConfiguration(audioMode: .required)

        try await fixture.recorder.prepare(configuration)

        do {
            try await fixture.recorder.start()
            XCTFail("Audio start failure should be surfaced")
        } catch let error as RecorderFailure {
            XCTAssertEqual(error, .audioStartFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(fixture.writer.startCount, 1)
        XCTAssertEqual(fixture.audioDriver.startCount, 1)
        let state = await fixture.recorder.state
        XCTAssertEqual(state, .failed)
        _ = await fixture.recorder.releaseAndWait()
    }

    func testDisabledAudioNeverCreatesDriver() async throws {
        let fixture = makeFixture(audioMode: .disabled)
        let configuration = makeConfiguration(audioMode: .disabled)

        try await fixture.recorder.prepare(configuration)
        try await fixture.recorder.start()
        let snapshot = await fixture.recorder.stateSnapshot()
        let fence = try XCTUnwrap(snapshot.frameFence)

        fixture.recorder.enqueueAudio(RecordingAudioFrame(fence: fence, timestamp: 0.0))
        fixture.recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 1.0))
        let result = await fixture.recorder.stop(reason: .user)

        assertFinalized(result, hasAudio: false)
        XCTAssertEqual(fixture.audioFactory.makeCount, 0)
        XCTAssertEqual(fixture.audioDriver.startCount, 0)
        XCTAssertEqual(fixture.writer.audioAppendCount, 0)
    }

    func testAppendedAudioUsesWriterMetadataTrue() async throws {
        let fixture = makeFixture(audioMode: .required)
        let configuration = makeConfiguration(audioMode: .required)
        fixture.writer.finishResult = .success(RecordingWriterFinish(hasAudio: true))

        try await fixture.recorder.prepare(configuration)
        try await fixture.recorder.start()
        let snapshot = await fixture.recorder.stateSnapshot()
        let fence = try XCTUnwrap(snapshot.frameFence)

        for index in 0..<32 {
            fixture.recorder.enqueueVideo(RecordingVideoFrame(
                fence: fence,
                timestamp: Double(index),
                payload: TestVideoPayload(index: index)
            ))
            fixture.recorder.enqueueAudio(RecordingAudioFrame(
                fence: fence,
                timestamp: Double(index),
                payload: TestAudioPayload(index: index)
            ))
        }

        let result = await fixture.recorder.stop(reason: .user)

        assertFinalized(result, hasAudio: true)
        XCTAssertEqual(fixture.writer.videoAppendCount, 32)
        XCTAssertEqual(fixture.writer.audioAppendCount, 32)
        XCTAssertEqual(fixture.writer.maximumConcurrentAppendCalls, 1)
        XCTAssertEqual(fixture.writer.videoFrameOrdinals, Array(0..<32))
        XCTAssertEqual(fixture.writer.audioFrameOrdinals, Array(0..<32))
    }

    func testAppendedAudioCannotOverrideWriterMetadataFalse() async throws {
        let fixture = makeFixture(audioMode: .required)
        let configuration = makeConfiguration(audioMode: .required)
        fixture.writer.finishResult = .success(RecordingWriterFinish(hasAudio: false))

        try await fixture.recorder.prepare(configuration)
        try await fixture.recorder.start()
        let snapshot = await fixture.recorder.stateSnapshot()
        let fence = try XCTUnwrap(snapshot.frameFence)

        fixture.recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 0.0))
        fixture.recorder.enqueueAudio(RecordingAudioFrame(fence: fence, timestamp: 0.0))

        let result = await fixture.recorder.stop(reason: .user)

        assertFinalized(result, hasAudio: false)
        XCTAssertEqual(fixture.writer.audioAppendCount, 1)
    }

    func testConcurrentAppendSubmissionsStayOnOneRecorderQueueAndFinishAfterAppends() async throws {
        let fixture = makeFixture(audioMode: .required)
        let configuration = makeConfiguration(audioMode: .required)
        fixture.writer.finishResult = .success(RecordingWriterFinish(hasAudio: true))

        try await fixture.recorder.prepare(configuration)
        try await fixture.recorder.start()
        let snapshot = await fixture.recorder.stateSnapshot()
        let fence = try XCTUnwrap(snapshot.frameFence)

        await enqueueConcurrently(recorder: fixture.recorder, fence: fence)
        let result = await fixture.recorder.stop(reason: .user)

        assertFinalized(result, hasAudio: true)
        XCTAssertEqual(fixture.writer.videoAppendCount, 32)
        XCTAssertEqual(fixture.writer.audioAppendCount, 32)
        XCTAssertEqual(fixture.writer.maximumConcurrentAppendCalls, 1)

        let queueTokens = fixture.writer.appendQueueTokens.compactMap { $0 }
        XCTAssertEqual(queueTokens.count, 64)
        XCTAssertEqual(Set(queueTokens).count, 1)

        let events = fixture.writer.events
        guard let firstMarkerIndex = events.firstIndex(of: "mark-video"),
              let finishIndex = events.firstIndex(of: "finish") else {
            XCTFail("Writer lifecycle events were incomplete: \(events)")
            return
        }
        XCTAssertEqual(firstMarkerIndex, 64)
        XCTAssertEqual(events[firstMarkerIndex...finishIndex], ["mark-video", "mark-audio", "finish"])
        XCTAssertTrue(events[..<firstMarkerIndex].allSatisfy { $0 == "video" || $0 == "audio" })
    }

    func testLateFrameDroppedAfterStopFence() async throws {
        let fixture = makeFixture()
        fixture.writer.holdFinish = true
        let finishEntered = expectation(description: "finish entered")
        fixture.writer.onFinish = { finishEntered.fulfill() }

        try await fixture.recorder.prepare(makeConfiguration())
        try await fixture.recorder.start()
        let snapshot = await fixture.recorder.stateSnapshot()
        let fence = try XCTUnwrap(snapshot.frameFence)

        let stopTask = Task {
            await fixture.recorder.stop(reason: .routeExit)
        }
        await fulfillment(of: [finishEntered], timeout: 1.0)

        fixture.recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 1.0))
        fixture.writer.completeFinish(with: .success(RecordingWriterFinish(duration: 0.0)))

        let result = await stopTask.value
        switch result {
        case .finalized:
            XCTFail("A stop without a video frame must not report success")
        case let .failed(failure, recoverableArtifact):
            XCTAssertEqual(failure, .noVideoFrames)
            XCTAssertNil(recoverableArtifact)
        }
        XCTAssertEqual(fixture.writer.videoAppendCount, 0)
    }

    func testConcurrentStopSharesOneFinishAndResult() async throws {
        let fixture = makeFixture()
        fixture.writer.holdFinish = true
        let finishEntered = expectation(description: "finish entered")
        fixture.writer.onFinish = { finishEntered.fulfill() }

        try await fixture.recorder.prepare(makeConfiguration())
        try await fixture.recorder.start()
        let snapshot = await fixture.recorder.stateSnapshot()
        let fence = try XCTUnwrap(snapshot.frameFence)
        fixture.recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 1.0))

        let firstStop = Task { await fixture.recorder.stop(reason: .user) }
        let secondStop = Task { await fixture.recorder.stop(reason: .background) }
        await fulfillment(of: [finishEntered], timeout: 1.0)
        XCTAssertEqual(fixture.writer.finishCount, 1)

        fixture.writer.completeFinish(with: .success(RecordingWriterFinish(duration: 0.5)))
        let firstResult = await firstStop.value
        let secondResult = await secondStop.value

        XCTAssertEqual(firstResult, secondResult)
        assertFinalized(firstResult, duration: 0.5)
        XCTAssertEqual(fixture.writer.finishCount, 1)
    }

    func testRepeatedStopAfterCompletionReturnsCachedResultWithoutSecondFinish() async throws {
        let fixture = makeFixture()
        fixture.writer.finishResult = .success(RecordingWriterFinish(duration: 0.5))

        try await fixture.recorder.prepare(makeConfiguration())
        try await fixture.recorder.start()
        let snapshot = await fixture.recorder.stateSnapshot()
        let fence = try XCTUnwrap(snapshot.frameFence)
        fixture.recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 1.0))

        let firstResult = await fixture.recorder.stop(reason: .user)
        let secondResult = await fixture.recorder.stop(reason: .background)

        XCTAssertEqual(firstResult, secondResult)
        assertFinalized(secondResult, duration: 0.5)
        XCTAssertEqual(fixture.writer.finishCount, 1)
    }

    func testDuplicateWriterCallbackResolvesWaitersOnceAndKeepsStableResult() async throws {
        let fixture = makeFixture()
        fixture.writer.holdFinish = true
        let finishEntered = expectation(description: "finish entered")
        fixture.writer.onFinish = { finishEntered.fulfill() }

        try await fixture.recorder.prepare(makeConfiguration())
        try await fixture.recorder.start()
        let snapshot = await fixture.recorder.stateSnapshot()
        let fence = try XCTUnwrap(snapshot.frameFence)
        fixture.recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 1.0))

        let firstStop = Task { await fixture.recorder.stop(reason: .user) }
        let secondStop = Task { await fixture.recorder.stop(reason: .background) }
        await fulfillment(of: [finishEntered], timeout: 1.0)

        fixture.writer.completeFinishTwice(with: .success(RecordingWriterFinish(duration: 0.75)))
        let firstResult = await firstStop.value
        let secondResult = await secondStop.value
        let stateAfterDuplicateCallback = await fixture.recorder.state

        XCTAssertEqual(firstResult, secondResult)
        assertFinalized(firstResult, duration: 0.75)
        XCTAssertEqual(stateAfterDuplicateCallback, .finished)
        XCTAssertEqual(fixture.writer.finishCount, 1)

        let repeatedResult = await fixture.recorder.stop(reason: .thermal)
        XCTAssertEqual(repeatedResult, firstResult)
        XCTAssertEqual(fixture.writer.finishCount, 1)
    }

    func testConcurrentStopAndReleaseShareOneFinishAndExactResult() async throws {
        let fixture = makeFixture()
        fixture.writer.holdFinish = true
        let finishEntered = expectation(description: "finish entered")
        fixture.writer.onFinish = { finishEntered.fulfill() }

        try await fixture.recorder.prepare(makeConfiguration())
        try await fixture.recorder.start()
        let snapshot = await fixture.recorder.stateSnapshot()
        let fence = try XCTUnwrap(snapshot.frameFence)
        fixture.recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 1.0))

        let stopTask = Task { await fixture.recorder.stop(reason: .user) }
        let releaseTask = Task { await fixture.recorder.releaseAndWait() }
        await fulfillment(of: [finishEntered], timeout: 1.0)
        XCTAssertEqual(fixture.writer.finishCount, 1)

        fixture.writer.completeFinish(with: .success(RecordingWriterFinish(duration: 0.25)))
        let stopResult = await stopTask.value
        let releaseResult = await releaseTask.value

        XCTAssertEqual(releaseResult, Optional(stopResult))
        assertFinalized(stopResult, duration: 0.25)
        let state = await fixture.recorder.state
        XCTAssertEqual(state, .released)
        XCTAssertEqual(fixture.writer.finishCount, 1)

        let repeatedReleaseResult = await fixture.recorder.releaseAndWait()
        XCTAssertEqual(repeatedReleaseResult, Optional(stopResult))
    }

    func testVideoAppendFailureReturnsRecoverableArtifact() async throws {
        let fixture = makeFixture()
        fixture.writer.videoAppendResult = false

        try await fixture.recorder.prepare(makeConfiguration())
        try await fixture.recorder.start()
        let snapshot = await fixture.recorder.stateSnapshot()
        let fence = try XCTUnwrap(snapshot.frameFence)
        fixture.recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 1.0))

        let result = await fixture.recorder.stop(reason: .storagePressure)

        switch result {
        case .finalized:
            XCTFail("A video append failure must not report success")
        case let .failed(failure, recoverableArtifact):
            XCTAssertEqual(failure, .videoAppendFailed)
            XCTAssertNil(recoverableArtifact)
        }
    }

    func testAudioAppendFailureReturnsTypedFailure() async throws {
        let fixture = makeFixture(audioMode: .required)
        fixture.writer.audioAppendResult = false

        try await fixture.recorder.prepare(makeConfiguration(audioMode: .required))
        try await fixture.recorder.start()
        let snapshot = await fixture.recorder.stateSnapshot()
        let fence = try XCTUnwrap(snapshot.frameFence)
        fixture.recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 1.0))
        fixture.recorder.enqueueAudio(RecordingAudioFrame(fence: fence, timestamp: 1.0))

        let result = await fixture.recorder.stop(reason: .interruption)

        switch result {
        case .finalized:
            XCTFail("An audio append failure must not report success")
        case let .failed(failure, recoverableArtifact):
            XCTAssertEqual(failure, .audioAppendFailed)
            XCTAssertNotNil(recoverableArtifact)
        }
    }

    func testAppendFailureStopsAudioImmediatelyAndOnlyOnce() async throws {
        let fixture = makeFixture(audioMode: .required)
        fixture.writer.audioAppendResult = false

        try await fixture.recorder.prepare(makeConfiguration(audioMode: .required))
        try await fixture.recorder.start()
        let snapshot = await fixture.recorder.stateSnapshot()
        let fence = try XCTUnwrap(snapshot.frameFence)
        fixture.recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 1.0))
        fixture.recorder.enqueueAudio(RecordingAudioFrame(fence: fence, timestamp: 1.0))

        let stateAfterFailure = await fixture.recorder.state
        XCTAssertEqual(stateAfterFailure, .failed)
        XCTAssertEqual(fixture.audioDriver.stopCount, 1)

        let result = await fixture.recorder.stop(reason: .interruption)

        switch result {
        case .finalized:
            XCTFail("An audio append failure must not report success")
        case let .failed(failure, _):
            XCTAssertEqual(failure, .audioAppendFailed)
        }
        XCTAssertEqual(fixture.writer.finishCount, 1)
        XCTAssertEqual(fixture.audioDriver.stopCount, 1)
    }

    func testFinishFailureDoesNotInventRecoverableArtifact() async throws {
        let fixture = makeFixture()
        fixture.writer.finishResult = .failure(.finishFailed(recoverableArtifact: nil))

        try await fixture.recorder.prepare(fixture.configuration)
        try await fixture.recorder.start()
        let snapshot = await fixture.recorder.stateSnapshot()
        let fence = try XCTUnwrap(snapshot.frameFence)
        fixture.recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 1.0))

        let result = await fixture.recorder.stop(reason: .thermal)

        switch result {
        case .finalized:
            XCTFail("Finish failure must not report success")
        case let .failed(failure, recoverableArtifact):
            XCTAssertEqual(failure, .finishFailed)
            XCTAssertNil(recoverableArtifact)
        }
    }

    func testFinishFailureUsesOnlyExplicitWriterAttestation() async throws {
        let fixture = makeFixture()
        let attestedArtifact = RecordingArtifact(
            id: fixture.configuration.id,
            localURL: fixture.configuration.outputURL,
            duration: 0.25,
            hasAudio: false
        )
        fixture.writer.finishResult = .failure(
            .finishFailed(recoverableArtifact: attestedArtifact)
        )

        try await fixture.recorder.prepare(fixture.configuration)
        try await fixture.recorder.start()
        let snapshot = await fixture.recorder.stateSnapshot()
        let fence = try XCTUnwrap(snapshot.frameFence)
        fixture.recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 1.0))

        let result = await fixture.recorder.stop(reason: .thermal)

        switch result {
        case .finalized:
            XCTFail("Finish failure must not report success")
        case let .failed(failure, recoverableArtifact):
            XCTAssertEqual(failure, .finishFailed)
            XCTAssertEqual(recoverableArtifact, attestedArtifact)
        }
    }

    func testStopWithoutVideoFramesNeverFinalizes() async throws {
        let fixture = makeFixture()

        try await fixture.recorder.prepare(makeConfiguration())
        try await fixture.recorder.start()

        let result = await fixture.recorder.stop(reason: .user)

        switch result {
        case .finalized:
            XCTFail("No video frames must never produce a finalized artifact")
        case let .failed(failure, recoverableArtifact):
            XCTAssertEqual(failure, .noVideoFrames)
            XCTAssertNil(recoverableArtifact)
        }
        XCTAssertEqual(fixture.writer.finishCount, 1)
        let state = await fixture.recorder.state
        XCTAssertEqual(state, .failed)
    }

    func testReleaseIdleReturnsNilAndIsIdempotent() async {
        let fixture = makeFixture()

        let firstRelease = await fixture.recorder.releaseAndWait()
        let secondRelease = await fixture.recorder.releaseAndWait()

        XCTAssertNil(firstRelease)
        XCTAssertNil(secondRelease)
        let state = await fixture.recorder.state
        XCTAssertEqual(state, .released)
    }

    func testReleasePreparedCleansResourcesAndIsIdempotent() async throws {
        let fixture = makeFixture()

        try await fixture.recorder.prepare(makeConfiguration())
        let firstRelease = await fixture.recorder.releaseAndWait()
        let secondRelease = await fixture.recorder.releaseAndWait()

        XCTAssertNil(firstRelease)
        XCTAssertNil(secondRelease)
        XCTAssertEqual(fixture.writer.discardCount, 1)
        let state = await fixture.recorder.state
        XCTAssertEqual(state, .released)
    }

    func testReleaseRecordingAwaitsOneFinish() async throws {
        let fixture = makeFixture()
        fixture.writer.holdFinish = true
        let finishEntered = expectation(description: "finish entered")
        fixture.writer.onFinish = { finishEntered.fulfill() }

        try await fixture.recorder.prepare(makeConfiguration())
        try await fixture.recorder.start()
        let snapshot = await fixture.recorder.stateSnapshot()
        let fence = try XCTUnwrap(snapshot.frameFence)
        fixture.recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 1.0))

        let releaseProbe = CompletionProbe()
        let releaseTask = Task {
            let result = await fixture.recorder.releaseAndWait()
            await releaseProbe.markCompleted()
            return result
        }

        await fulfillment(of: [finishEntered], timeout: 1.0)
        XCTAssertEqual(fixture.writer.finishCount, 1)
        let completedBeforeFinish = await releaseProbe.isCompleted
        XCTAssertFalse(completedBeforeFinish)

        fixture.writer.completeFinish(with: .success(RecordingWriterFinish(duration: 0.0)))
        let optionalReleaseResult = await releaseTask.value
        let releaseResult = try XCTUnwrap(optionalReleaseResult)

        let completedAfterFinish = await releaseProbe.isCompleted
        XCTAssertTrue(completedAfterFinish)
        assertFinalized(releaseResult, duration: 0.0, hasAudio: false)
        let state = await fixture.recorder.state
        XCTAssertEqual(state, .released)
        XCTAssertEqual(fixture.writer.finishCount, 1)
    }

    func testCancelledStopWaiterDoesNotCancelCleanup() async throws {
        let fixture = makeFixture()
        fixture.writer.holdFinish = true
        let finishEntered = expectation(description: "finish entered")
        fixture.writer.onFinish = { finishEntered.fulfill() }

        try await fixture.recorder.prepare(makeConfiguration())
        try await fixture.recorder.start()
        let snapshot = await fixture.recorder.stateSnapshot()
        let fence = try XCTUnwrap(snapshot.frameFence)
        fixture.recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 1.0))

        let stopTask = Task { await fixture.recorder.stop(reason: .user) }
        await fulfillment(of: [finishEntered], timeout: 1.0)
        stopTask.cancel()

        XCTAssertEqual(fixture.writer.finishCount, 1)
        fixture.writer.completeFinish(with: .success(RecordingWriterFinish(duration: 0.0)))

        let result = await stopTask.value
        assertFinalized(result)
        let state = await fixture.recorder.state
        XCTAssertEqual(state, .finished)
    }

    func testCancelledReleaseWaiterDoesNotCancelCleanup() async throws {
        let fixture = makeFixture()
        fixture.writer.holdFinish = true
        let finishEntered = expectation(description: "finish entered")
        fixture.writer.onFinish = { finishEntered.fulfill() }

        try await fixture.recorder.prepare(makeConfiguration())
        try await fixture.recorder.start()
        let snapshot = await fixture.recorder.stateSnapshot()
        let fence = try XCTUnwrap(snapshot.frameFence)
        fixture.recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 1.0))

        let releaseTask = Task { await fixture.recorder.releaseAndWait() }
        await fulfillment(of: [finishEntered], timeout: 1.0)
        releaseTask.cancel()

        XCTAssertEqual(fixture.writer.finishCount, 1)
        fixture.writer.completeFinish(with: .success(RecordingWriterFinish(duration: 0.0)))

        let optionalResult = await releaseTask.value
        let result = try XCTUnwrap(optionalResult)
        assertFinalized(result)
        let state = await fixture.recorder.state
        XCTAssertEqual(state, .released)
        XCTAssertEqual(fixture.writer.finishCount, 1)
    }

    func testStopDoesNotAutomaticallyPrepareOrExport() async throws {
        let fixture = makeFixture()

        try await fixture.recorder.prepare(makeConfiguration())
        try await fixture.recorder.start()
        let snapshot = await fixture.recorder.stateSnapshot()
        let fence = try XCTUnwrap(snapshot.frameFence)
        fixture.recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 1.0))

        let result = await fixture.recorder.stop(reason: .user)

        assertFinalized(result)
        XCTAssertEqual(fixture.writerFactory.makeCount, 1)
        let finishedState = await fixture.recorder.state
        XCTAssertEqual(finishedState, .finished)

        let releaseResult = await fixture.recorder.releaseAndWait()
        XCTAssertEqual(releaseResult, Optional(result))
        XCTAssertEqual(fixture.writerFactory.makeCount, 1)
        let releasedState = await fixture.recorder.state
        XCTAssertEqual(releasedState, .released)
    }

    private func enqueueConcurrently(
        recorder: SerializedMediaRecorder,
        fence: RecordingFrameFence,
        workerCount: Int = 8,
        framesPerWorker: Int = 8
    ) async {
        await withCheckedContinuation { continuation in
            let group = DispatchGroup()

            for worker in 0..<workerCount {
                let submissionQueue = DispatchQueue(
                    label: "com.shafinMultitool.recorder-test-submission-\(worker)"
                )
                group.enter()
                submissionQueue.async {
                    for frame in 0..<framesPerWorker {
                        let index = worker * framesPerWorker + frame
                        if worker.isMultiple(of: 2) {
                            recorder.enqueueVideo(RecordingVideoFrame(
                                fence: fence,
                                timestamp: Double(index),
                                payload: TestVideoPayload(index: index)
                            ))
                        } else {
                            recorder.enqueueAudio(RecordingAudioFrame(
                                fence: fence,
                                timestamp: Double(index),
                                payload: TestAudioPayload(index: index)
                            ))
                        }
                    }
                    group.leave()
                }
            }

            group.notify(queue: .global(qos: .userInitiated)) {
                continuation.resume()
            }
        }
    }

    private func makeConfiguration(
        id: RecordingID = RecordingID(rawValue: UUID()),
        audioMode: RecordingAudioMode = .disabled
    ) -> RecordingConfiguration {
        RecordingConfiguration(
            id: id,
            outputURL: temporaryDirectoryURL.appendingPathComponent("recording-\(id.rawValue.uuidString).mov"),
            width: 1920,
            height: 1080,
            fps: 30,
            audioMode: audioMode
        )
    }

    private func makeFixture(audioMode: RecordingAudioMode = .disabled) -> RecorderFixture {
        let writer = FakeWriter()
        let writerFactory = FakeWriterFactory(writer: writer)
        let audioDriver = FakeAudioDriver()
        let audioFactory = FakeAudioDriverFactory(driver: audioDriver)
        let outputChecker = FakeOutputChecker()
        let configuration = makeConfiguration(audioMode: audioMode)
        let recorder = SerializedMediaRecorder(
            writerFactory: writerFactory,
            audioDriverFactory: audioFactory,
            outputChecker: outputChecker
        )
        return RecorderFixture(
            recorder: recorder,
            writer: writer,
            writerFactory: writerFactory,
            audioDriver: audioDriver,
            audioFactory: audioFactory,
            outputChecker: outputChecker,
            configuration: configuration
        )
    }

    private func assertFinalized(
        _ result: RecordingStopResult,
        duration: TimeInterval? = nil,
        hasAudio: Bool? = nil
    ) {
        switch result {
        case let .finalized(artifact):
            if let duration {
                XCTAssertEqual(artifact.duration, duration)
            }
            if let hasAudio {
                XCTAssertEqual(artifact.hasAudio, hasAudio)
            }
        case let .failed(failure, recoverableArtifact):
            XCTFail("Expected finalized result, got failure \(failure), artifact \(String(describing: recoverableArtifact))")
        }
    }
}

private struct RecorderFixture {
    let recorder: SerializedMediaRecorder
    let writer: FakeWriter
    let writerFactory: FakeWriterFactory
    let audioDriver: FakeAudioDriver
    let audioFactory: FakeAudioDriverFactory
    let outputChecker: FakeOutputChecker
    let configuration: RecordingConfiguration
}

private struct TestVideoPayload: RecordingVideoFramePayload {
    let index: Int
}

private struct TestAudioPayload: RecordingAudioFramePayload {
    let index: Int
}

private actor CompletionProbe {
    private(set) var isCompleted = false

    func markCompleted() {
        isCompleted = true
    }
}

private final class FakeOutputChecker: RecordingOutputChecking {
    var existingURLs = Set<URL>()

    func exists(at url: URL) -> Bool {
        existingURLs.contains(url)
    }
}

private final class FakeWriterFactory: RecordingWriterFactory {
    let writer: FakeWriter
    var error: RecordingWriterError?
    private(set) var makeCount = 0

    init(writer: FakeWriter) {
        self.writer = writer
    }

    func makeWriter(for configuration: RecordingConfiguration) throws -> any RecordingWriter {
        makeCount += 1
        if let error {
            throw error
        }
        return writer
    }
}

private final class FakeWriter: RecordingWriter {
    private let lock = NSLock()
    private var finishCompletion: ((Result<RecordingWriterFinish, RecordingWriterError>) -> Void)?
    private var storedFinishResult: Result<RecordingWriterFinish, RecordingWriterError> = .success(
        RecordingWriterFinish()
    )
    private var storedFinishCount = 0
    private var storedDiscardCount = 0
    private var storedStartCount = 0
    private var storedVideoAppendCount = 0
    private var storedAudioAppendCount = 0
    private var storedConcurrentAppendCalls = 0
    private var storedMaximumConcurrentAppendCalls = 0
    private var storedVideoFrameOrdinals: [Int] = []
    private var storedAudioFrameOrdinals: [Int] = []
    private var storedAppendQueueTokens: [UUID?] = []
    private var storedEvents: [String] = []

    var startResult = true
    var videoAppendResult = true
    var audioAppendResult = true
    var holdFinish = false
    var onFinish: (() -> Void)?

    var startCount: Int { lock.withLock { storedStartCount } }
    var finishCount: Int { lock.withLock { storedFinishCount } }
    var discardCount: Int { lock.withLock { storedDiscardCount } }
    var videoAppendCount: Int { lock.withLock { storedVideoAppendCount } }
    var audioAppendCount: Int { lock.withLock { storedAudioAppendCount } }
    var maximumConcurrentAppendCalls: Int { lock.withLock { storedMaximumConcurrentAppendCalls } }
    var videoFrameOrdinals: [Int] { lock.withLock { storedVideoFrameOrdinals } }
    var audioFrameOrdinals: [Int] { lock.withLock { storedAudioFrameOrdinals } }
    var appendQueueTokens: [UUID?] { lock.withLock { storedAppendQueueTokens } }
    var events: [String] { lock.withLock { storedEvents } }

    var finishResult: Result<RecordingWriterFinish, RecordingWriterError> {
        get { lock.withLock { storedFinishResult } }
        set { lock.withLock { storedFinishResult = newValue } }
    }

    func start() -> Bool {
        lock.withLock {
            storedStartCount += 1
        }
        return startResult
    }

    func appendVideo(_ frame: RecordingVideoFrame) -> Bool {
        let result: Bool
        lock.lock()
        storedConcurrentAppendCalls += 1
        storedMaximumConcurrentAppendCalls = max(storedMaximumConcurrentAppendCalls,
                                                  storedConcurrentAppendCalls)
        storedVideoAppendCount += 1
        if let payload = frame.payload as? TestVideoPayload {
            storedVideoFrameOrdinals.append(payload.index)
        }
        storedAppendQueueTokens.append(
            DispatchQueue.getSpecific(key: SerializedMediaRecorder.queueSpecificKey)
        )
        storedEvents.append("video")
        result = videoAppendResult
        storedConcurrentAppendCalls -= 1
        lock.unlock()
        return result
    }

    func appendAudio(_ frame: RecordingAudioFrame) -> Bool {
        let result: Bool
        lock.lock()
        storedConcurrentAppendCalls += 1
        storedMaximumConcurrentAppendCalls = max(storedMaximumConcurrentAppendCalls,
                                                  storedConcurrentAppendCalls)
        storedAudioAppendCount += 1
        if let payload = frame.payload as? TestAudioPayload {
            storedAudioFrameOrdinals.append(payload.index)
        }
        storedAppendQueueTokens.append(
            DispatchQueue.getSpecific(key: SerializedMediaRecorder.queueSpecificKey)
        )
        storedEvents.append("audio")
        result = audioAppendResult
        storedConcurrentAppendCalls -= 1
        lock.unlock()
        return result
    }

    func markVideoInputAsFinished() {
        lock.withLock {
            storedEvents.append("mark-video")
        }
    }

    func markAudioInputAsFinished() {
        lock.withLock {
            storedEvents.append("mark-audio")
        }
    }

    func finishWriting(completion: @escaping (Result<RecordingWriterFinish, RecordingWriterError>) -> Void) {
        let shouldHold: Bool
        let result: Result<RecordingWriterFinish, RecordingWriterError>
        lock.lock()
        storedFinishCount += 1
        storedEvents.append("finish")
        shouldHold = holdFinish
        result = storedFinishResult
        if shouldHold {
            finishCompletion = completion
        }
        lock.unlock()

        onFinish?()
        if !shouldHold {
            completion(result)
        }
    }

    func completeFinish(with result: Result<RecordingWriterFinish, RecordingWriterError>? = nil) {
        let completion: ((Result<RecordingWriterFinish, RecordingWriterError>) -> Void)?
        let completionResult: Result<RecordingWriterFinish, RecordingWriterError>
        lock.lock()
        completion = finishCompletion
        finishCompletion = nil
        completionResult = result ?? storedFinishResult
        lock.unlock()
        completion?(completionResult)
    }

    func completeFinishTwice(with result: Result<RecordingWriterFinish, RecordingWriterError>? = nil) {
        let completion: ((Result<RecordingWriterFinish, RecordingWriterError>) -> Void)?
        let completionResult: Result<RecordingWriterFinish, RecordingWriterError>
        lock.lock()
        completion = finishCompletion
        completionResult = result ?? storedFinishResult
        lock.unlock()

        completion?(completionResult)
        completion?(completionResult)

        lock.withLock {
            finishCompletion = nil
        }
    }

    func discard() {
        lock.withLock {
            storedDiscardCount += 1
        }
    }
}

private final class FakeAudioDriverFactory: RecordingAudioDriverFactory {
    let driver: FakeAudioDriver
    var error: RecordingAudioDriverError?
    private(set) var makeCount = 0

    init(driver: FakeAudioDriver) {
        self.driver = driver
    }

    func makeAudioDriver(for configuration: RecordingConfiguration) throws -> any RecordingAudioDriver {
        makeCount += 1
        if let error {
            throw error
        }
        return driver
    }
}

private final class FakeAudioDriver: RecordingAudioDriver {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    var startResult = true

    func start() -> Bool {
        startCount += 1
        return startResult
    }

    func stop() {
        stopCount += 1
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
