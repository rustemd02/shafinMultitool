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
            XCTAssertEqualWithAccuracy(
                actual.presentationTimeStamp.seconds,
                expected.presentationTimeStamp.seconds,
                accuracy: 0.001
            )
            XCTAssertEqualWithAccuracy(
                actual.decodeTimeStamp.seconds,
                expected.decodeTimeStamp.seconds,
                accuracy: 0.001
            )
        }
        XCTAssertEqualWithAccuracy(
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
