import AVFoundation
import AudioToolbox
import CoreVideo
import XCTest
@testable import shafinMultitool

final class AppleRecordingAdaptersTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppleRecordingAdaptersTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        try super.tearDownWithError()
    }

    func testNativeWriterProducesLocalMovieWithVideoAndDuration() async throws {
        let outputURL = temporaryDirectoryURL.appendingPathComponent("recording.mov")
        let configuration = RecordingConfiguration(
            id: RecordingID(rawValue: UUID()),
            outputURL: outputURL,
            width: 320,
            height: 240,
            fps: 30,
            audioMode: .disabled
        )
        let writer = try AVAssetWriterRecordingWriterFactory().makeWriter(for: configuration)

        XCTAssertTrue(writer.start())
        for index in 0..<3 {
            let pixelBuffer = try makePixelBuffer(
                width: configuration.width,
                height: configuration.height,
                pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            )
            XCTAssertEqual(
                writer.appendVideo(RecordingVideoFrame(
                    recordingID: configuration.id,
                    generation: 1,
                    timestamp: 10.0 + (Double(index) / Double(configuration.fps)),
                    payload: AppleRecordingVideoFramePayload(pixelBuffer: pixelBuffer)
                )),
                .appended
            )
        }

        let finishExpectation = expectation(description: "writer finished")
        var finishResult: Result<RecordingWriterFinish, RecordingWriterError>?
        writer.finishWriting { result in
            finishResult = result
            finishExpectation.fulfill()
        }
        await fulfillment(of: [finishExpectation], timeout: 10)

        guard case let .success(metadata) = finishResult else {
            XCTFail("Native writer did not finish successfully: \(String(describing: finishResult))")
            return
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertTrue(metadata.duration?.isFinite == true)
        XCTAssertTrue((metadata.duration ?? 0) > 0)

        let asset = AVAsset(url: outputURL)
        XCTAssertFalse(asset.tracks(withMediaType: .video).isEmpty)
        XCTAssertTrue(asset.duration.isNumeric)
        XCTAssertTrue(asset.duration.seconds > 0)
    }

    func testNativeWriterRejectsInvalidVideoConfiguration() {
        let configuration = RecordingConfiguration(
            id: RecordingID(rawValue: UUID()),
            outputURL: temporaryDirectoryURL.appendingPathComponent("invalid.mov"),
            width: 0,
            height: 240,
            fps: 30,
            audioMode: .disabled
        )

        XCTAssertThrowsError(try AVAssetWriterRecordingWriterFactory().makeWriter(for: configuration)) { error in
            XCTAssertEqual(error as? RecordingWriterError, .inputRejected)
        }
    }

    func testNativeWriterReportsAudioTrackAfterAppendingSampleBuffer() async throws {
        let outputURL = temporaryDirectoryURL.appendingPathComponent("recording-with-audio.mov")
        let configuration = RecordingConfiguration(
            id: RecordingID(rawValue: UUID()),
            outputURL: outputURL,
            width: 320,
            height: 240,
            fps: 30,
            audioMode: .required
        )
        let writer = try AVAssetWriterRecordingWriterFactory().makeWriter(for: configuration)
        XCTAssertTrue(writer.start())

        let pixelBuffer = try makePixelBuffer(width: configuration.width, height: configuration.height)
        XCTAssertEqual(
            writer.appendVideo(RecordingVideoFrame(
                recordingID: configuration.id,
                generation: 1,
                timestamp: 10.0,
                payload: AppleRecordingVideoFramePayload(pixelBuffer: pixelBuffer)
            )),
            .appended
        )
        let sampleBuffer = try makeAudioSampleBuffer(timestamp: 10.0)
        XCTAssertEqual(
            writer.appendAudio(RecordingAudioFrame(
                recordingID: configuration.id,
                generation: 1,
                timestamp: 10.0,
                payload: AppleRecordingAudioFramePayload(sampleBuffer: sampleBuffer)
            )),
            .appended
        )

        let finishExpectation = expectation(description: "writer with audio finished")
        var finishResult: Result<RecordingWriterFinish, RecordingWriterError>?
        writer.finishWriting { result in
            finishResult = result
            finishExpectation.fulfill()
        }
        await fulfillment(of: [finishExpectation], timeout: 10)

        guard case let .success(metadata) = finishResult else {
            XCTFail("Native writer with audio did not finish successfully: \(String(describing: finishResult))")
            return
        }
        XCTAssertTrue(metadata.hasAudio)
        XCTAssertFalse(AVAsset(url: outputURL).tracks(withMediaType: .audio).isEmpty)
    }

    func testNativeWriterDropsAudioBeforeVideoOrigin() throws {
        let outputURL = temporaryDirectoryURL.appendingPathComponent("recording-audio-before-video.mov")
        let configuration = RecordingConfiguration(
            id: RecordingID(rawValue: UUID()),
            outputURL: outputURL,
            width: 320,
            height: 240,
            fps: 30,
            audioMode: .required
        )
        let writer = try AVAssetWriterRecordingWriterFactory().makeWriter(for: configuration)
        XCTAssertTrue(writer.start())

        let sampleBuffer = try makeAudioSampleBuffer(timestamp: 10.0)
        XCTAssertEqual(
            writer.appendAudio(RecordingAudioFrame(
                recordingID: configuration.id,
                generation: 1,
                timestamp: 10.0,
                payload: AppleRecordingAudioFramePayload(sampleBuffer: sampleBuffer)
            )),
            .dropped
        )
        writer.discard()
    }

    func testAudioSampleBufferHostClockRetimingConvertsEveryTimingEntry() throws {
        let hostClock = CMClockGetHostTimeClock()
        var synchronizationTimebase: CMTimebase?
        XCTAssertEqual(
            CMTimebaseCreateWithSourceClock(
                allocator: kCFAllocatorDefault,
                sourceClock: hostClock,
                timebaseOut: &synchronizationTimebase
            ),
            noErr
        )
        guard let synchronizationTimebase else {
            XCTFail("Could not create synchronization timebase")
            return
        }

        let sourceAnchor = CMTimeMakeWithSeconds(100, preferredTimescale: 600)
        let hostAnchor = CMClockGetTime(hostClock)
        XCTAssertEqual(
            CMTimebaseSetRateAndAnchorTime(
                synchronizationTimebase,
                rate: 1,
                anchorTime: sourceAnchor,
                immediateSourceTime: hostAnchor
            ),
            noErr
        )

        let timings = [
            CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: 48_000),
                presentationTimeStamp: CMTimeMakeWithSeconds(100, preferredTimescale: 600),
                decodeTimeStamp: CMTimeMakeWithSeconds(99.99, preferredTimescale: 600)
            ),
            CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: 48_000),
                presentationTimeStamp: CMTimeMakeWithSeconds(100.01, preferredTimescale: 600),
                decodeTimeStamp: CMTimeMakeWithSeconds(100, preferredTimescale: 600)
            ),
        ]
        let sampleBuffer = try makeAudioSampleBuffer(timings: timings)
        let expectedTimings = timings.map { timing in
            CMSampleTimingInfo(
                duration: timing.duration,
                presentationTimeStamp: CMSyncConvertTime(
                    timing.presentationTimeStamp,
                    from: synchronizationTimebase,
                    to: hostClock
                ),
                decodeTimeStamp: CMSyncConvertTime(
                    timing.decodeTimeStamp,
                    from: synchronizationTimebase,
                    to: hostClock
                )
            )
        }

        guard let hostSampleBuffer = copyAudioSampleBufferToHostTime(
            sampleBuffer,
            synchronizationClock: synchronizationTimebase,
            hostClock: hostClock
        ) else {
            XCTFail("Audio sample buffer did not retime to host clock")
            return
        }
        let actualTimings = try sampleTimings(hostSampleBuffer)
        XCTAssertEqual(actualTimings.count, expectedTimings.count)
        for (actual, expected) in zip(actualTimings, expectedTimings) {
            // XCTAssertEqualWithAccuracy is deprecated in this toolchain; the
            // accuracy form of XCTAssertEqual is the same assertion.
            XCTAssertEqual(
                actual.presentationTimeStamp.seconds,
                expected.presentationTimeStamp.seconds,
                accuracy: 0.001
            )
            XCTAssertEqual(
                actual.decodeTimeStamp.seconds,
                expected.decodeTimeStamp.seconds,
                accuracy: 0.001
            )
        }
        XCTAssertEqual(
            CMSampleBufferGetPresentationTimeStamp(hostSampleBuffer).seconds,
            actualTimings[0].presentationTimeStamp.seconds,
            accuracy: 0.001
        )
        XCTAssertNil(
            copyAudioSampleBufferToHostTime(
                sampleBuffer,
                synchronizationClock: nil,
                hostClock: hostClock
            )
        )
    }

    func testCaptureQueueStopHelperDoesNotSynchronouslyReenter() {
        let session = AVCaptureSession()
        let queue = DispatchQueue(label: "AppleRecordingAdaptersTests.captureQueue")
        queue.setSpecific(
            key: AVCaptureAudioRecordingDriver.captureQueueSpecificKey,
            value: true
        )
        let returned = expectation(description: "reentrant stop returned")

        queue.async {
            AVCaptureAudioRecordingDriver.stopSession(on: queue, session: session)
            returned.fulfill()
        }

        wait(for: [returned], timeout: 1)
    }

    func testNativeWriterDiscardRemovesPartialOutput() throws {
        let outputURL = temporaryDirectoryURL.appendingPathComponent("recording-discarded.mov")
        let configuration = RecordingConfiguration(
            id: RecordingID(rawValue: UUID()),
            outputURL: outputURL,
            width: 320,
            height: 240,
            fps: 30,
            audioMode: .disabled
        )
        let writer = try AVAssetWriterRecordingWriterFactory().makeWriter(for: configuration)
        XCTAssertTrue(writer.start())
        let pixelBuffer = try makePixelBuffer(width: configuration.width, height: configuration.height)
        XCTAssertEqual(
            writer.appendVideo(RecordingVideoFrame(
                recordingID: configuration.id,
                generation: 1,
                timestamp: 10.0,
                payload: AppleRecordingVideoFramePayload(pixelBuffer: pixelBuffer)
            )),
            .appended
        )

        writer.discard()

        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testNativeWriterFailedFinishRemovesPartialOutput() async throws {
        let outputURL = temporaryDirectoryURL.appendingPathComponent("recording-failed-finish.mov")
        let configuration = RecordingConfiguration(
            id: RecordingID(rawValue: UUID()),
            outputURL: outputURL,
            width: 320,
            height: 240,
            fps: 30,
            audioMode: .disabled
        )
        let writer = try AVAssetWriterRecordingWriterFactory().makeWriter(for: configuration)
        XCTAssertTrue(writer.start())

        let finishExpectation = expectation(description: "writer failed finish")
        var finishResult: Result<RecordingWriterFinish, RecordingWriterError>?
        writer.finishWriting { result in
            finishResult = result
            finishExpectation.fulfill()
        }
        await fulfillment(of: [finishExpectation], timeout: 10)

        guard case let .failure(error) = finishResult else {
            XCTFail("Expected failed finish, got \(String(describing: finishResult))")
            return
        }
        XCTAssertEqual(error, .finishFailed(recoverableArtifact: nil))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testPendingArtifactStoreCreatesUniqueMovURLsWithoutDeletingFiles() throws {
        let applicationSupportURL = temporaryDirectoryURL.appendingPathComponent("Application Support")
        let store = try RecordingArtifactStore(
            applicationSupportDirectoryURL: applicationSupportURL
        )

        let firstURL = try store.makePendingURL()
        let secondURL = try store.makePendingURL()

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.pendingDirectoryURL.path))
        XCTAssertEqual(firstURL.pathExtension, "mov")
        XCTAssertNotEqual(firstURL, secondURL)
        FileManager.default.createFile(atPath: firstURL.path, contents: Data())
        _ = try store.makePendingURL()
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))
    }

    // MARK: - M7-005 writer configuration

    private struct RejectingCodecSupportChecker: RecordingCodecSupportChecking {
        let supported: Set<RecordingQuickTimeCodec>

        func isSupported(_ codec: RecordingQuickTimeCodec) -> Bool {
            supported.contains(codec)
        }
    }

    private final class AlwaysMissingOutputChecker: RecordingOutputChecking {
        func exists(at url: URL) -> Bool { false }
    }

    func testWriterFactoryRejectsUnsupportedCodecBeforeCreatingAnyWriter() throws {
        let outputURL = temporaryDirectoryURL.appendingPathComponent("unsupported-codec.mov")
        let configuration = RecordingConfiguration(
            id: RecordingID(rawValue: UUID()),
            outputURL: outputURL,
            width: 320,
            height: 240,
            fps: 30,
            audioMode: .disabled,
            videoCodec: .hevc
        )
        let factory = AVAssetWriterRecordingWriterFactory(
            codecSupport: RejectingCodecSupportChecker(supported: [.h264])
        )

        XCTAssertThrowsError(try factory.makeWriter(for: configuration)) { error in
            XCTAssertEqual(error as? RecordingWriterError, .unsupportedVideoCodec)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testWriterFactoryRejectsExplicitZeroPixelFormat() throws {
        let configuration = RecordingConfiguration(
            id: RecordingID(rawValue: UUID()),
            outputURL: temporaryDirectoryURL.appendingPathComponent("zero-fourcc.mov"),
            width: 320,
            height: 240,
            fps: 30,
            audioMode: .disabled,
            pixelFormatFourCC: 0
        )

        XCTAssertThrowsError(try AVAssetWriterRecordingWriterFactory().makeWriter(for: configuration)) { error in
            XCTAssertEqual(error as? RecordingWriterError, .inputRejected)
        }
    }

    func testSerializedRecorderRejectsUnsupportedCodecAsTypedInputFailure() async throws {
        let outputURL = temporaryDirectoryURL.appendingPathComponent("recorder-unsupported.mov")
        let configuration = RecordingConfiguration(
            id: RecordingID(rawValue: UUID()),
            outputURL: outputURL,
            width: 320,
            height: 240,
            fps: 30,
            audioMode: .disabled,
            videoCodec: .hevc
        )
        let recorder = SerializedMediaRecorder(
            writerFactory: AVAssetWriterRecordingWriterFactory(
                codecSupport: RejectingCodecSupportChecker(supported: [.h264])
            ),
            audioDriverFactory: nil,
            outputChecker: AlwaysMissingOutputChecker()
        )

        do {
            try await recorder.prepare(configuration)
            XCTFail("Prepare with an unsupported codec must fail")
        } catch let failure as RecorderFailure {
            XCTAssertEqual(failure, .writerInputRejected)
        }
        let snapshot = await recorder.stateSnapshot()
        XCTAssertEqual(snapshot.state, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testWrittenAssetCarriesSelectedCodecAndPixelFormat() async throws {
        let outputURL = temporaryDirectoryURL.appendingPathComponent("hevc-420.mov")
        let configuration = RecordingConfiguration(
            id: RecordingID(rawValue: UUID()),
            outputURL: outputURL,
            width: 320,
            height: 240,
            fps: 30,
            audioMode: .disabled,
            pixelFormatFourCC: RecordingPixelFormat.yPlanar420VideoRange,
            videoCodec: .hevc
        )
        let writer = try AVAssetWriterRecordingWriterFactory().makeWriter(for: configuration)
        XCTAssertTrue(writer.start())

        for index in 0..<3 {
            let pixelBuffer = try makePixelBuffer(
                width: configuration.width,
                height: configuration.height,
                pixelFormat: RecordingPixelFormat.yPlanar420VideoRange
            )
            XCTAssertEqual(
                writer.appendVideo(RecordingVideoFrame(
                    recordingID: configuration.id,
                    generation: 1,
                    timestamp: 10.0 + (Double(index) / Double(configuration.fps)),
                    payload: AppleRecordingVideoFramePayload(pixelBuffer: pixelBuffer)
                )),
                .appended
            )
        }

        let finishExpectation = expectation(description: "writer finished")
        var finishResult: Result<RecordingWriterFinish, RecordingWriterError>?
        writer.finishWriting { result in
            finishResult = result
            finishExpectation.fulfill()
        }
        await fulfillment(of: [finishExpectation], timeout: 10)

        guard case .success = finishResult else {
            XCTFail("Writer did not finish successfully: \(String(describing: finishResult))")
            return
        }

        let asset = AVAsset(url: outputURL)
        let videoTrack = try await asset.loadTracks(withMediaType: .video).first
        let formatDescriptions = try await videoTrack?.load(.formatDescriptions) ?? []
        XCTAssertEqual(formatDescriptions.count, 1)
        if let formatDescription = formatDescriptions.first {
            let subType = CMFormatDescriptionGetMediaSubType(formatDescription)
            XCTAssertEqual(subType, kCMVideoCodecType_HEVC)
        }
    }

    // MARK: - M7-007 orientation metadata

    func testCameraCoachControllerFinalizesPlayableNativeMovieWithoutCompressingTimestampGaps() async throws {
        let store = try RecordingArtifactStore(
            applicationSupportDirectoryURL: temporaryDirectoryURL.appendingPathComponent("saved", isDirectory: true)
        )
        let controller = SceneRecordingController(artifactStore: store, source: .cameraCoach) { _ in
            SerializedMediaRecorder(writerFactory: AVAssetWriterRecordingWriterFactory())
        }
        let pixels = try makePixelBuffer(width: 640, height: 480,
                                        pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        controller.enqueueVideo(pixels, at: 100)
        try await controller.start(requestedFPS: 30, audioMode: .disabled,
            trackTransform: .init(captureOrientation: .portrait, isMirrored: false,
                strategy: .preferredTransformMetadata, pixelOrientationBaseline: .nativeLandscapeRight))
        let token = try XCTUnwrap(controller.recordingSourceToken)
        XCTAssertEqual(token.source, .cameraCoach)
        _ = await controller.recorderStateSnapshot()
        let foreign = RecordingOwnerToken(source: .arWorkspace, ownerID: token.ownerID,
            recordingID: token.recordingID, generation: token.generation)
        controller.enqueueVideo(pixels, at: 150, ownerID: token.ownerID, ownerToken: foreign)
        controller.enqueueVideo(pixels, at: 100 + 1.0 / 30, ownerID: token.ownerID, ownerToken: token)
        _ = await controller.recorderStateSnapshot()
        controller.enqueueVideo(pixels, at: 111, ownerID: token.ownerID, ownerToken: token)
        let beforeStop = await controller.recorderStateSnapshot()
        XCTAssertEqual(beforeStop?.droppedVideoCount, 0)
        let result = await controller.stop(reason: .background)
        guard case .finalized(let artifact)? = result else {
            _ = await controller.releaseAndWait()
            return XCTFail("Actual shared recorder did not finalize: \(String(describing: result))")
        }
        _ = await controller.releaseAndWait()
        XCTAssertEqual(artifact.id, token.recordingID)
        XCTAssertEqual(artifact.localURL.deletingPathExtension().lastPathComponent,
                       artifact.id.rawValue.uuidString)
        let asset = AVURLAsset(url: artifact.localURL)
        let duration = try await asset.load(.duration).seconds
        XCTAssertGreaterThanOrEqual(duration, 11)
        XCTAssertLessThan(duration, 11.1, "The rejected foreign sample at150 must not stretch the take")
        XCTAssertEqual(duration, 11 + 1.0 / 30, accuracy: 1.0 / 600,
                       "A sparse last frame must last one nominal frame, not the preceding gap")
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let transform = try await track.load(.preferredTransform)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(CGRect(origin: .zero, size: size).applying(transform),
                       CGRect(x: 0, y: 0, width: 480, height: 640))
        let playable = await AVURLAssetPlaybackProbe().isPlayableMovie(at: artifact.localURL)
        XCTAssertTrue(playable)
        let timestamps = try videoPresentationTimes(asset: asset, track: track)
        XCTAssertEqual(timestamps.count, 3)
        for (actual, expected) in zip(timestamps, [0, 1.0 / 30, 11]) {
            XCTAssertEqual(actual, expected, accuracy: 1.0 / 600)
        }
    }

    func testNativeWriterEndsSparseVideoAtOneFrameBoundaryAndClipsAudioTail() async throws {
        let outputURL = temporaryDirectoryURL.appendingPathComponent("sparse-video-audio-tail.mov")
        let configuration = RecordingConfiguration(
            id: RecordingID(rawValue: UUID()), outputURL: outputURL,
            width: 320, height: 240, fps: 30, audioMode: .required
        )
        let writer = try AVAssetWriterRecordingWriterFactory().makeWriter(for: configuration)
        XCTAssertTrue(writer.start())
        let pixels = try makePixelBuffer(width: 320, height: 240)
        for timestamp in [100.0, 100 + 1.0 / 30, 111] {
            let frame = RecordingVideoFrame(
                recordingID: configuration.id, generation: 1, timestamp: timestamp,
                payload: AppleRecordingVideoFramePayload(pixelBuffer: pixels)
            )
            try await waitForNativeAppend { writer.appendVideo(frame) }
        }
        for timestamp in [100.0, 112] {
            let sample = try makeAudioSampleBuffer(timestamp: timestamp)
            let frame = RecordingAudioFrame(
                recordingID: configuration.id, generation: 1, timestamp: timestamp,
                payload: AppleRecordingAudioFramePayload(sampleBuffer: sample)
            )
            try await waitForNativeAppend { writer.appendAudio(frame) }
        }
        // Match SerializedMediaRecorder's input-finished ordering.
        writer.markVideoInputAsFinished()
        writer.markAudioInputAsFinished()
        let metadata = try await finishNativeWriter(writer)
        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 11 + 1.0 / 30, accuracy: 1.0 / 600)
        XCTAssertEqual(try XCTUnwrap(metadata.duration), duration, accuracy: 1.0 / 600)
        XCTAssertTrue(metadata.hasAudio)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(videoTracks.first)
        let timestamps = try videoPresentationTimes(asset: asset, track: track)
        XCTAssertEqual(timestamps.count, 3)
        for (actual, expected) in zip(timestamps, [0, 1.0 / 30, 11]) {
            XCTAssertEqual(actual, expected, accuracy: 1.0 / 600)
        }
        let playable = await AVURLAssetPlaybackProbe().isPlayableMovie(at: outputURL)
        XCTAssertTrue(playable)
    }

    func testNativeWriterSingleVideoFrameHasOneNominalFrameOfDuration() async throws {
        let outputURL = temporaryDirectoryURL.appendingPathComponent("single-frame-end.mov")
        let configuration = RecordingConfiguration(
            id: RecordingID(rawValue: UUID()), outputURL: outputURL,
            width: 320, height: 240, fps: 24, audioMode: .disabled
        )
        let writer = try AVAssetWriterRecordingWriterFactory().makeWriter(for: configuration)
        XCTAssertTrue(writer.start())
        let pixels = try makePixelBuffer(width: 320, height: 240)
        let frame = RecordingVideoFrame(
            recordingID: configuration.id, generation: 1, timestamp: 47,
            payload: AppleRecordingVideoFramePayload(pixelBuffer: pixels)
        )
        try await waitForNativeAppend { writer.appendVideo(frame) }
        writer.markVideoInputAsFinished()
        let metadata = try await finishNativeWriter(writer)
        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 1.0 / 24, accuracy: 1.0 / 600)
        XCTAssertEqual(try XCTUnwrap(metadata.duration), duration, accuracy: 1.0 / 600)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        XCTAssertEqual(try videoPresentationTimes(asset: asset, track: track), [0])
    }

    /// A native readiness drop is not accepted media. These direct-adapter
    /// fixtures retry the same sample without changing its timestamp.
    private func waitForNativeAppend(_ append: () -> RecordingAppendDisposition) async throws {
        for _ in 0..<200 {
            let result = append()
            if result == .appended { return }
            guard result == .dropped else {
                XCTFail("Native fixture append failed: \(result)")
                throw NSError(domain: "AppleRecordingAdaptersTests", code: -20)
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Native writer readiness did not recover")
        throw NSError(domain: "AppleRecordingAdaptersTests", code: -21)
    }

    private func finishNativeWriter(_ writer: any RecordingWriter) async throws -> RecordingWriterFinish {
        let finished = expectation(description: "duration fixture writer finished")
        var result: Result<RecordingWriterFinish, RecordingWriterError>?
        writer.finishWriting { value in result = value; finished.fulfill() }
        await fulfillment(of: [finished], timeout: 10)
        return try XCTUnwrap(result).get()
    }

    private func videoPresentationTimes(asset: AVAsset, track: AVAssetTrack) throws -> [TimeInterval] {
        let compressed = try readVideoMediaTimes(asset: asset, track: track, decoded: false)
        let decoded = try readVideoMediaTimes(asset: asset, track: track, decoded: true)
        XCTAssertEqual(compressed.count, decoded.count,
                       "Every compressed media sample must decode to one image frame")
        for (encodedTime, decodedTime) in zip(compressed, decoded) {
            XCTAssertEqual(encodedTime, decodedTime, accuracy: 1.0 / 600,
                           "Decoding must preserve the actual media-frame presentation sequence")
        }
        return decoded
    }

    private func readVideoMediaTimes(
        asset: AVAsset, track: AVAssetTrack, decoded: Bool
    ) throws -> [TimeInterval] {
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any]? = decoded
            ? [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            : nil
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "AppleRecordingAdaptersTests", code: -22)
        }
        var timestamps: [TimeInterval] = []
        while let sample = output.copyNextSampleBuffer() {
            let count = CMSampleBufferGetNumSamples(sample)
            // AVAssetReaderOutput documents zero-sample marker buffers for
            // compressed output. Edit boundaries, drain notifications and the
            // permanent-empty end marker are not media frames, even when their
            // PTS is numeric. Classify by sample count, never by timestamp.
            if count == 0 && !decoded {
                XCTAssertEqual(CMSampleBufferGetTotalSampleSize(sample), 0)
                XCTAssertNil(CMSampleBufferGetImageBuffer(sample))
                continue
            }
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sample)
            let hasMedia = decoded
                ? CMSampleBufferGetImageBuffer(sample) != nil
                : CMSampleBufferGetDataBuffer(sample) != nil
                    && CMSampleBufferGetTotalSampleSize(sample) > 0
            guard count == 1, CMSampleBufferIsValid(sample),
                  CMSampleBufferDataIsReady(sample), hasMedia,
                  presentationTime.isNumeric, presentationTime.seconds.isFinite else {
                XCTFail("Invalid \(decoded ? "decoded" : "compressed") media frame: count=\(count), PTS=\(presentationTime)")
                throw NSError(domain: "AppleRecordingAdaptersTests", code: -24)
            }
            timestamps.append(presentationTime.seconds)
        }
        guard reader.status == .completed else {
            throw reader.error ?? NSError(domain: "AppleRecordingAdaptersTests", code: -23)
        }
        return timestamps
    }

    func testTrackTransformMapperProducesDeterministicMetadataMatrices() {
        func matrix(_ orientation: RecordingCaptureOrientation, mirrored: Bool) -> CGAffineTransform {
            AppleRecordingTrackTransformMapper.transform(for: RecordingTrackTransformMetadata(
                captureOrientation: orientation,
                isMirrored: mirrored,
                strategy: .preferredTransformMetadata
            ))
        }

        // Portrait capture is the identity baseline; the fixed conventions are
        // landscapeLeft -90°, landscapeRight +90°, upside-down 180°, and a
        // horizontal flip composed under mirroring.
        XCTAssertEqual(matrix(.portrait, mirrored: false), .identity)
        let upsideDown = matrix(.portraitUpsideDown, mirrored: false)
        XCTAssertEqual(upsideDown.a, -1, accuracy: 1e-9)
        XCTAssertEqual(upsideDown.d, -1, accuracy: 1e-9)
        let landscapeLeft = matrix(.landscapeLeft, mirrored: false)
        XCTAssertEqual(landscapeLeft.b, -1, accuracy: 1e-9)
        XCTAssertEqual(landscapeLeft.c, 1, accuracy: 1e-9)
        let landscapeRight = matrix(.landscapeRight, mirrored: false)
        XCTAssertEqual(landscapeRight.b, 1, accuracy: 1e-9)
        XCTAssertEqual(landscapeRight.c, -1, accuracy: 1e-9)
        let mirroredPortrait = matrix(.portrait, mirrored: true)
        XCTAssertEqual(mirroredPortrait.a, -1, accuracy: 1e-9)
        XCTAssertEqual(mirroredPortrait.d, 1, accuracy: 1e-9)
    }

    func testNativeSensorOrientationMapsAllCornersInsideUprightTrackBounds() {
        let width = 640
        let height = 480
        let cases: [(RecordingCaptureOrientation, CGPoint, CGPoint, CGSize)] = [
            (.portrait, CGPoint(x: 480, y: 0), CGPoint(x: 0, y: 640), CGSize(width: 480, height: 640)),
            (.portraitUpsideDown, CGPoint(x: 0, y: 640), CGPoint(x: 480, y: 0), CGSize(width: 480, height: 640)),
            (.landscapeLeft, CGPoint(x: 640, y: 480), .zero, CGSize(width: 640, height: 480)),
            (.landscapeRight, .zero, CGPoint(x: 640, y: 480), CGSize(width: 640, height: 480)),
        ]
        for (orientation, expectedOrigin, expectedFarCorner, expectedSize) in cases {
            let metadata = RecordingTrackTransformMetadata(
                captureOrientation: orientation, isMirrored: false,
                strategy: .preferredTransformMetadata,
                pixelOrientationBaseline: .nativeLandscapeRight
            )
            let transform = AppleRecordingTrackTransformMapper.transform(
                for: metadata, width: width, height: height
            )
            XCTAssertEqual(CGPoint.zero.applying(transform), expectedOrigin, "\(orientation)")
            XCTAssertEqual(CGPoint(x: width, y: height).applying(transform), expectedFarCorner, "\(orientation)")
            XCTAssertEqual(CGRect(x: 0, y: 0, width: width, height: height).applying(transform),
                           CGRect(origin: .zero, size: expectedSize), "\(orientation)")
        }
    }

    func testExplicitIdentityMetadataPreservesAlreadyOrientedPixels() {
        let metadata = RecordingTrackTransformMetadata(
            captureOrientation: .portrait, isMirrored: false,
            strategy: .identityMetadata, pixelOrientationBaseline: .nativeLandscapeRight
        )
        XCTAssertEqual(AppleRecordingTrackTransformMapper.transform(
            for: metadata, width: 480, height: 640
        ), .identity)
    }

    func testWrittenNativePortraitTrackRetainsLandscapePixelsAndUprightDisplayBounds() async throws {
        let outputURL = temporaryDirectoryURL.appendingPathComponent("native-portrait-transform.mov")
        let metadata = RecordingTrackTransformMetadata(
            captureOrientation: .portrait, isMirrored: false,
            strategy: .preferredTransformMetadata, pixelOrientationBaseline: .nativeLandscapeRight
        )
        let configuration = RecordingConfiguration(
            id: RecordingID(rawValue: UUID()), outputURL: outputURL,
            width: 640, height: 480, fps: 30, audioMode: .disabled,
            trackTransform: metadata
        )
        let writer = try AVAssetWriterRecordingWriterFactory().makeWriter(for: configuration)
        XCTAssertTrue(writer.start())
        let pixels = try makePixelBuffer(width: 640, height: 480,
                                        pixelFormat: RecordingPixelFormat.yPlanar420VideoRange)
        XCTAssertEqual(writer.appendVideo(RecordingVideoFrame(
            recordingID: configuration.id, generation: 1, timestamp: 10,
            payload: AppleRecordingVideoFramePayload(pixelBuffer: pixels)
        )), .appended)
        let completion = expectation(description: "native portrait movie finalized")
        writer.finishWriting { result in
            if case .failure(let error) = result { XCTFail("Finalization failed: \(error)") }
            completion.fulfill()
        }
        await fulfillment(of: [completion], timeout: 10)
        let asset = AVURLAsset(url: outputURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        XCTAssertEqual(size, CGSize(width: 640, height: 480))
        XCTAssertEqual(CGPoint.zero.applying(transform), CGPoint(x: 480, y: 0))
        XCTAssertEqual(CGRect(origin: .zero, size: size).applying(transform),
                       CGRect(x: 0, y: 0, width: 480, height: 640))
        let playable = await AVURLAssetPlaybackProbe().isPlayableMovie(at: outputURL)
        XCTAssertTrue(playable)
    }

    func testWrittenAssetTrackCarriesOrientationTransformWithoutRotatingDimensions() async throws {
        let outputURL = temporaryDirectoryURL.appendingPathComponent("landscape-transform.mov")
        let transformMetadata = RecordingTrackTransformMetadata(
            captureOrientation: .landscapeLeft,
            isMirrored: false,
            strategy: .preferredTransformMetadata
        )
        let configuration = RecordingConfiguration(
            id: RecordingID(rawValue: UUID()),
            outputURL: outputURL,
            width: 640,
            height: 480,
            fps: 30,
            audioMode: .disabled,
            trackTransform: transformMetadata
        )
        let writer = try AVAssetWriterRecordingWriterFactory().makeWriter(for: configuration)
        XCTAssertTrue(writer.start())

        let pixelBuffer = try makePixelBuffer(
            width: configuration.width,
            height: configuration.height,
            pixelFormat: RecordingPixelFormat.yPlanar420VideoRange
        )
        XCTAssertEqual(
            writer.appendVideo(RecordingVideoFrame(
                recordingID: configuration.id,
                generation: 1,
                timestamp: 10.0,
                payload: AppleRecordingVideoFramePayload(pixelBuffer: pixelBuffer)
            )),
            .appended
        )

        let finishExpectation = expectation(description: "writer finished")
        writer.finishWriting { _ in finishExpectation.fulfill() }
        await fulfillment(of: [finishExpectation], timeout: 10)

        let asset = AVAsset(url: outputURL)
        let videoTrack = try await asset.loadTracks(withMediaType: .video).first
        let trackTransform = try await videoTrack?.load(.preferredTransform) ?? .identity
        let expected = AppleRecordingTrackTransformMapper.transform(for: transformMetadata)
        XCTAssertEqual(trackTransform.a, expected.a, accuracy: 1e-6)
        XCTAssertEqual(trackTransform.b, expected.b, accuracy: 1e-6)
        XCTAssertEqual(trackTransform.c, expected.c, accuracy: 1e-6)
        XCTAssertEqual(trackTransform.d, expected.d, accuracy: 1e-6)
        let expectedBounds = CGRect(x: 0, y: 0, width: 480, height: 640)
        XCTAssertEqual(CGRect(x: 0, y: 0, width: configuration.width, height: configuration.height)
            .applying(trackTransform), expectedBounds)
        // Metadata-only orientation: the encoded natural track size keeps the
        // source pixel dimensions; the transform conveys the rotation.
        let naturalSize = try await videoTrack?.load(.naturalSize) ?? .zero
        XCTAssertEqual(Int(naturalSize.width), configuration.width)
        XCTAssertEqual(Int(naturalSize.height), configuration.height)
    }

    // MARK: - M7-026 playback probe

    func testPlaybackProbeAcceptsRealMovieAndRejectsMissingAndCorruptFiles() async throws {
        let probe = AVURLAssetPlaybackProbe()

        // A real written movie is playable and has a video track.
        let movieURL = temporaryDirectoryURL.appendingPathComponent("probe-movie.mov")
        let configuration = RecordingConfiguration(
            id: RecordingID(rawValue: UUID()),
            outputURL: movieURL,
            width: 320,
            height: 240,
            fps: 30,
            audioMode: .disabled
        )
        let writer = try AVAssetWriterRecordingWriterFactory().makeWriter(for: configuration)
        XCTAssertTrue(writer.start())
        let pixelBuffer = try makePixelBuffer(
            width: configuration.width,
            height: configuration.height,
            pixelFormat: RecordingPixelFormat.yPlanar420VideoRange
        )
        XCTAssertEqual(
            writer.appendVideo(RecordingVideoFrame(
                recordingID: configuration.id,
                generation: 1,
                timestamp: 10.0,
                payload: AppleRecordingVideoFramePayload(pixelBuffer: pixelBuffer)
            )),
            .appended
        )
        let finishExpectation = expectation(description: "writer finished")
        writer.finishWriting { _ in finishExpectation.fulfill() }
        await fulfillment(of: [finishExpectation], timeout: 10)
        let moviePlayable = await probe.isPlayableMovie(at: movieURL)
        XCTAssertTrue(moviePlayable)

        // A garbage file is not a playable movie.
        let garbageURL = temporaryDirectoryURL.appendingPathComponent("garbage.mov")
        try Data("not a movie".utf8).write(to: garbageURL)
        let garbagePlayable = await probe.isPlayableMovie(at: garbageURL)
        XCTAssertFalse(garbagePlayable)

        // A missing file fails closed.
        let missingURL = temporaryDirectoryURL.appendingPathComponent("missing.mov")
        let missingPlayable = await probe.isPlayableMovie(at: missingURL)
        XCTAssertFalse(missingPlayable)
    }

    private func makePixelBuffer(
        width: Int,
        height: Int,
        pixelFormat: OSType = kCVPixelFormatType_32BGRA
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            pixelFormat,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw NSError(domain: "AppleRecordingAdaptersTests", code: Int(status))
        }
        return pixelBuffer
    }

    private func makeAudioSampleBuffer(timestamp: TimeInterval) throws -> CMSampleBuffer {
        try makeAudioSampleBuffer(timings: [
            CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: 48_000),
                presentationTimeStamp: CMTimeMakeWithSeconds(timestamp, preferredTimescale: 600),
                decodeTimeStamp: .invalid
            ),
        ])
    }

    private func makeAudioSampleBuffer(
        timings: [CMSampleTimingInfo]
    ) throws -> CMSampleBuffer {
        guard !timings.isEmpty else {
            throw NSError(domain: "AppleRecordingAdaptersTests", code: -5)
        }

        var streamDescription = AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &streamDescription,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        ) == noErr,
        let formatDescription else {
            throw NSError(domain: "AppleRecordingAdaptersTests", code: -1)
        }

        var blockBuffer: CMBlockBuffer?
        let blockLength = timings.count * 2
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: blockLength,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: blockLength,
            flags: 0,
            blockBufferOut: &blockBuffer
        ) == kCMBlockBufferNoErr,
        let blockBuffer else {
            throw NSError(domain: "AppleRecordingAdaptersTests", code: -2)
        }
        let sampleBytes = [UInt8](repeating: 0, count: blockLength)
        let replaceStatus = sampleBytes.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(
                with: bytes.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: sampleBytes.count
            )
        }
        guard replaceStatus == kCMBlockBufferNoErr else {
            throw NSError(domain: "AppleRecordingAdaptersTests", code: -3)
        }

        var sampleTimings = timings
        var sampleSizes = [Int](repeating: 2, count: timings.count)
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: timings.count,
            sampleTimingEntryCount: timings.count,
            sampleTimingArray: &sampleTimings,
            sampleSizeEntryCount: timings.count,
            sampleSizeArray: &sampleSizes,
            sampleBufferOut: &sampleBuffer
        ) == noErr,
        let sampleBuffer else {
            throw NSError(domain: "AppleRecordingAdaptersTests", code: -4)
        }
        return sampleBuffer
    }

    private func sampleTimings(_ sampleBuffer: CMSampleBuffer) throws -> [CMSampleTimingInfo] {
        var timingCount: CMItemCount = 0
        guard CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &timingCount
        ) == noErr,
        timingCount > 0 else {
            throw NSError(domain: "AppleRecordingAdaptersTests", code: -6)
        }

        var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: .invalid,
            decodeTimeStamp: .invalid
        ), count: Int(timingCount))
        let status = timings.withUnsafeMutableBufferPointer { buffer in
            CMSampleBufferGetSampleTimingInfoArray(
                sampleBuffer,
                entryCount: timingCount,
                arrayToFill: buffer.baseAddress,
                entriesNeededOut: nil
            )
        }
        guard status == noErr else {
            throw NSError(domain: "AppleRecordingAdaptersTests", code: -7)
        }
        return timings
    }
}
