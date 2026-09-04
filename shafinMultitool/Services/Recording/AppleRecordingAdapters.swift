import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

/// Core Video buffers are retained by the frame value and consumed only by the
/// serialized writer queue. Core Media sample buffers are copied by the audio
/// driver before this wrapper crosses the capture/recorder queue boundary.
struct AppleRecordingVideoFramePayload: RecordingVideoFramePayload, @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer

    init(pixelBuffer: CVPixelBuffer) {
        self.pixelBuffer = pixelBuffer
    }
}

/// The copied, host-clock-retimed sample buffer remains alive until the
/// recorder has serialized the append. The unchecked conformance is limited
/// to that ownership hand-off.
struct AppleRecordingAudioFramePayload: RecordingAudioFramePayload, @unchecked Sendable {
    let sampleBuffer: CMSampleBuffer

    init(sampleBuffer: CMSampleBuffer) {
        self.sampleBuffer = sampleBuffer
    }
}

/// AVCapture sample buffers are clocked to the session synchronization clock.
/// Retiming here keeps host-time timestamps intact before the payload crosses
/// into the recorder's queue. A nil/invalid clock or any invalid timing entry
/// drops the sample rather than mixing clock domains.
func copyAudioSampleBufferToHostTime(
    _ sampleBuffer: CMSampleBuffer,
    synchronizationClock: CMClockOrTimebase?,
    hostClock: CMClockOrTimebase = CMClockGetHostTimeClock()
) -> CMSampleBuffer? {
    guard let synchronizationClock,
          CMSampleBufferDataIsReady(sampleBuffer) else {
        return nil
    }

    var timingCount: CMItemCount = 0
    guard CMSampleBufferGetSampleTimingInfoArray(
        sampleBuffer,
        entryCount: 0,
        arrayToFill: nil,
        entriesNeededOut: &timingCount
    ) == noErr,
    timingCount > 0 else {
        return nil
    }

    var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(
        duration: .invalid,
        presentationTimeStamp: .invalid,
        decodeTimeStamp: .invalid
    ), count: Int(timingCount))
    let readStatus = timings.withUnsafeMutableBufferPointer { buffer in
        CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: timingCount,
            arrayToFill: buffer.baseAddress,
            entriesNeededOut: nil
        )
    }
    guard readStatus == noErr else { return nil }

    for index in timings.indices {
        let presentationTime = timings[index].presentationTimeStamp
        guard presentationTime.isNumeric,
              presentationTime.seconds.isFinite else {
            return nil
        }
        let hostPresentationTime = CMSyncConvertTime(
            presentationTime,
            from: synchronizationClock,
            to: hostClock
        )
        guard hostPresentationTime.isNumeric,
              hostPresentationTime.seconds.isFinite else {
            return nil
        }
        timings[index].presentationTimeStamp = hostPresentationTime

        if timings[index].decodeTimeStamp.isNumeric {
            let decodeTime = timings[index].decodeTimeStamp
            guard decodeTime.seconds.isFinite else { return nil }
            let hostDecodeTime = CMSyncConvertTime(
                decodeTime,
                from: synchronizationClock,
                to: hostClock
            )
            guard hostDecodeTime.isNumeric,
                  hostDecodeTime.seconds.isFinite else {
                return nil
            }
            timings[index].decodeTimeStamp = hostDecodeTime
        }
    }

    var copiedSampleBuffer: CMSampleBuffer?
    let copyStatus = timings.withUnsafeBufferPointer { buffer in
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: timingCount,
            sampleTimingArray: buffer.baseAddress,
            sampleBufferOut: &copiedSampleBuffer
        )
    }
    guard copyStatus == noErr else { return nil }
    return copiedSampleBuffer
}

struct AVAssetWriterRecordingWriterFactory: RecordingWriterFactory {
    func makeWriter(for configuration: RecordingConfiguration) throws -> any RecordingWriter {
        guard configuration.width > 0,
              configuration.height > 0,
              configuration.fps > 0 else {
            throw RecordingWriterError.inputRejected
        }

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: configuration.outputURL, fileType: .mov)
        } catch {
            throw error
        }

        do {
            return try AVAssetWriterRecordingWriter(writer: writer, configuration: configuration)
        } catch {
            writer.cancelWriting()
            throw error
        }
    }
}

final class AVAssetWriterRecordingWriter: RecordingWriter {
    private let writer: AVAssetWriter
    private let configuration: RecordingConfiguration
    private let videoInput: AVAssetWriterInput
    private let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?
    private let lock = NSLock()

    private var started = false
    private var sessionStarted = false
    private var sourceTimeOrigin: CMTime?
    private var finishRequested = false
    private var completionDelivered = false
    private var discarded = false
    private var videoInputFinished = false
    private var audioInputFinished = false

    init(writer: AVAssetWriter, configuration: RecordingConfiguration) throws {
        guard configuration.width > 0,
              configuration.height > 0,
              configuration.fps > 0 else {
            throw RecordingWriterError.inputRejected
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: configuration.width,
            AVVideoHeightKey: configuration.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoExpectedSourceFrameRateKey: configuration.fps,
                AVVideoAllowFrameReorderingKey: false,
            ],
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: configuration.width,
            kCVPixelBufferHeightKey as String: configuration.height,
        ]
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        let audioInput: AVAssetWriterInput?
        if configuration.audioMode == .required {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 48_000,
                AVEncoderBitRateKey: 128_000,
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            audioInput = input
        } else {
            audioInput = nil
        }

        guard writer.canAdd(videoInput) else {
            throw RecordingWriterError.inputRejected
        }
        writer.add(videoInput)
        if let audioInput {
            guard writer.canAdd(audioInput) else {
                throw RecordingWriterError.inputRejected
            }
            writer.add(audioInput)
        }

        self.writer = writer
        self.configuration = configuration
        self.videoInput = videoInput
        self.pixelBufferAdaptor = pixelBufferAdaptor
        self.audioInput = audioInput
    }

    func start() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if started {
            return writer.status == .writing
        }
        guard !discarded,
              writer.startWriting(),
              writer.status == .writing else {
            return false
        }
        started = true
        return true
    }

    func appendVideo(_ frame: RecordingVideoFrame) -> RecordingAppendDisposition {
        lock.lock()
        defer { lock.unlock() }

        guard started,
              !finishRequested,
              !discarded,
              writer.status == .writing else {
            return .failed
        }
        guard let payload = frame.payload as? AppleRecordingVideoFramePayload else {
            return .failed
        }
        guard CVPixelBufferGetWidth(payload.pixelBuffer) == configuration.width,
              CVPixelBufferGetHeight(payload.pixelBuffer) == configuration.height,
              let timestamp = makeTimestamp(frame.timestamp) else {
            return .failed
        }
        guard videoInput.isReadyForMoreMediaData else {
            return .dropped
        }

        let presentationTime: CMTime
        if let sourceTimeOrigin {
            presentationTime = CMTimeSubtract(timestamp, sourceTimeOrigin)
            guard presentationTime.isNumeric,
                  presentationTime.seconds >= 0 else {
                return .failed
            }
        } else {
            sourceTimeOrigin = timestamp
            writer.startSession(atSourceTime: .zero)
            sessionStarted = true
            presentationTime = .zero
        }

        guard sessionStarted,
              pixelBufferAdaptor.append(payload.pixelBuffer, withPresentationTime: presentationTime) else {
            return .failed
        }
        return .appended
    }

    func appendAudio(_ frame: RecordingAudioFrame) -> RecordingAppendDisposition {
        lock.lock()
        defer { lock.unlock() }

        guard started,
              !finishRequested,
              !discarded,
              writer.status == .writing else {
            return .failed
        }
        guard let payload = frame.payload as? AppleRecordingAudioFramePayload,
              let audioInput,
              makeTimestamp(frame.timestamp) != nil else {
            return .failed
        }
        guard audioInput.isReadyForMoreMediaData else {
            return .dropped
        }
        guard let sourceTimeOrigin else {
            return .dropped
        }
        let sampleTimestamp = CMSampleBufferGetPresentationTimeStamp(payload.sampleBuffer)
        guard sampleTimestamp.isNumeric else {
            return .failed
        }
        let normalizedSampleTimestamp = CMTimeSubtract(sampleTimestamp, sourceTimeOrigin)
        guard normalizedSampleTimestamp.isNumeric else {
            return .failed
        }
        if normalizedSampleTimestamp.seconds < 0 {
            return .dropped
        }
        guard let sampleBuffer = normalizedAudioSampleBuffer(
            payload.sampleBuffer,
            sourceTimeOrigin: sourceTimeOrigin
        ) else {
            return .failed
        }
        return audioInput.append(sampleBuffer) ? .appended : .failed
    }

    func markVideoInputAsFinished() {
        lock.lock()
        guard !videoInputFinished else {
            lock.unlock()
            return
        }
        videoInputFinished = true
        lock.unlock()
        videoInput.markAsFinished()
    }

    func markAudioInputAsFinished() {
        guard audioInput != nil else { return }

        lock.lock()
        guard !audioInputFinished else {
            lock.unlock()
            return
        }
        audioInputFinished = true
        lock.unlock()
        audioInput?.markAsFinished()
    }

    func finishWriting(completion: @escaping (Result<RecordingWriterFinish, RecordingWriterError>) -> Void) {
        lock.lock()
        guard !finishRequested else {
            lock.unlock()
            return
        }
        finishRequested = true
        let canFinish = started && !discarded
        lock.unlock()

        guard canFinish else {
            removeOutputIfNotCompleted()
            deliver(.failure(.finishFailed(recoverableArtifact: nil)), completion: completion)
            return
        }

        markVideoInputAsFinished()
        markAudioInputAsFinished()
        writer.finishWriting { [self] in
            guard self.writer.status == .completed else {
                self.removeOutputIfNotCompleted()
                self.deliver(
                    .failure(.finishFailed(recoverableArtifact: nil)),
                    completion: completion
                )
                return
            }
            self.deliver(
                .success(self.finishMetadata()),
                completion: completion
            )
        }
    }

    func discard() {
        lock.lock()
        guard !discarded else {
            lock.unlock()
            return
        }
        discarded = true
        let shouldCancel = writer.status == .writing
        let shouldRemove = writer.status != .completed
        lock.unlock()

        if shouldCancel {
            writer.cancelWriting()
        }
        if shouldRemove {
            removeOutputIfNotCompleted()
        }
    }

    private func deliver(
        _ result: Result<RecordingWriterFinish, RecordingWriterError>,
        completion: @escaping (Result<RecordingWriterFinish, RecordingWriterError>) -> Void
    ) {
        lock.lock()
        guard !completionDelivered else {
            lock.unlock()
            return
        }
        completionDelivered = true
        lock.unlock()
        completion(result)
    }

    private func finishMetadata() -> RecordingWriterFinish {
        let asset = AVURLAsset(url: writer.outputURL)
        let duration: TimeInterval?
        let assetDuration = asset.duration
        if assetDuration.isNumeric,
           assetDuration.seconds.isFinite,
           assetDuration.seconds >= 0 {
            duration = assetDuration.seconds
        } else {
            duration = nil
        }
        return RecordingWriterFinish(
            duration: duration,
            hasAudio: !asset.tracks(withMediaType: .audio).isEmpty
        )
    }

    private func removeOutputIfNotCompleted() {
        guard writer.status != .completed else { return }
        try? FileManager.default.removeItem(at: writer.outputURL)
    }

    private func makeTimestamp(_ seconds: TimeInterval) -> CMTime? {
        guard seconds.isFinite else { return nil }
        let timestamp = CMTimeMakeWithSeconds(seconds, preferredTimescale: 600)
        return timestamp.isNumeric ? timestamp : nil
    }

    private func normalizedAudioSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        sourceTimeOrigin: CMTime
    ) -> CMSampleBuffer? {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return nil }

        var timingCount: CMItemCount = 0
        guard CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &timingCount
        ) == noErr,
        timingCount > 0 else {
            return nil
        }

        var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: .invalid,
            decodeTimeStamp: .invalid
        ), count: Int(timingCount))
        let readStatus = timings.withUnsafeMutableBufferPointer { buffer in
            CMSampleBufferGetSampleTimingInfoArray(
                sampleBuffer,
                entryCount: timingCount,
                arrayToFill: buffer.baseAddress,
                entriesNeededOut: nil
            )
        }
        guard readStatus == noErr else { return nil }

        for index in timings.indices {
            let presentationTime = timings[index].presentationTimeStamp
            guard presentationTime.isNumeric else { return nil }
            let normalizedPresentationTime = CMTimeSubtract(presentationTime, sourceTimeOrigin)
            guard normalizedPresentationTime.isNumeric,
                  normalizedPresentationTime.seconds >= 0 else {
                return nil
            }
            timings[index].presentationTimeStamp = normalizedPresentationTime

            if timings[index].decodeTimeStamp.isNumeric {
                let normalizedDecodeTime = CMTimeSubtract(
                    timings[index].decodeTimeStamp,
                    sourceTimeOrigin
                )
                guard normalizedDecodeTime.isNumeric,
                      normalizedDecodeTime.seconds >= 0 else {
                    return nil
                }
                timings[index].decodeTimeStamp = normalizedDecodeTime
            }
        }

        var copiedSampleBuffer: CMSampleBuffer?
        let copyStatus = timings.withUnsafeBufferPointer { buffer in
            CMSampleBufferCreateCopyWithNewTiming(
                allocator: kCFAllocatorDefault,
                sampleBuffer: sampleBuffer,
                sampleTimingEntryCount: timingCount,
                sampleTimingArray: buffer.baseAddress,
                sampleBufferOut: &copiedSampleBuffer
            )
        }
        guard copyStatus == noErr else { return nil }
        return copiedSampleBuffer
    }
}

final class AVCaptureAudioRecordingDriver: NSObject, RecordingAudioDriver, AVCaptureAudioDataOutputSampleBufferDelegate {
    static let captureQueueSpecificKey = DispatchSpecificKey<Bool>()

    private let session: AVCaptureSession
    private let audioOutput: AVCaptureAudioDataOutput
    private let captureQueue = DispatchQueue(
        label: "com.shafinMultitool.recording.audioCapture",
        qos: .userInitiated
    )
    private let stateLock = NSLock()
    private var started = false
    private var frameHandler: RecordingAudioFrameHandler?

    init(session: AVCaptureSession = AVCaptureSession()) throws {
        self.session = session
        let audioDevice = AVCaptureDevice.default(for: .audio)
        guard let audioDevice,
              let audioInput = try? AVCaptureDeviceInput(device: audioDevice) else {
            throw RecordingAudioDriverError.unavailable
        }

        let audioOutput = AVCaptureAudioDataOutput()
        session.beginConfiguration()
        guard session.canAddInput(audioInput), session.canAddOutput(audioOutput) else {
            session.commitConfiguration()
            throw RecordingAudioDriverError.unavailable
        }
        session.addInput(audioInput)
        session.addOutput(audioOutput)
        session.commitConfiguration()
        self.audioOutput = audioOutput
        super.init()
        captureQueue.setSpecific(key: Self.captureQueueSpecificKey, value: true)
    }

    func start(onFrame: @escaping RecordingAudioFrameHandler) -> Bool {
        stateLock.lock()
        if started {
            stateLock.unlock()
            return true
        }
        started = true
        frameHandler = onFrame
        stateLock.unlock()

        let didStart = captureQueue.sync {
            audioOutput.setSampleBufferDelegate(self, queue: captureQueue)
            session.startRunning()
            return session.isRunning
        }
        guard didStart else {
            stateLock.lock()
            started = false
            frameHandler = nil
            stateLock.unlock()

            audioOutput.setSampleBufferDelegate(nil, queue: nil)
            Self.stopSession(on: captureQueue, session: session)
            return false
        }
        return true
    }

    func stop() {
        stateLock.lock()
        guard started else {
            stateLock.unlock()
            return
        }
        started = false
        frameHandler = nil
        stateLock.unlock()

        audioOutput.setSampleBufferDelegate(nil, queue: nil)
        Self.stopSession(on: captureQueue, session: session)
    }

    static func stopSession(on queue: DispatchQueue, session: AVCaptureSession) {
        let stop = {
            session.stopRunning()
        }
        if DispatchQueue.getSpecific(key: captureQueueSpecificKey) != nil {
            queue.async(execute: stop)
        } else {
            queue.sync(execute: stop)
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        stateLock.lock()
        guard started,
              output === audioOutput,
              let frameHandler else {
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        guard let copiedSampleBuffer = copyAudioSampleBufferToHostTime(
            sampleBuffer,
            synchronizationClock: session.synchronizationClock
        ) else {
            return
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(copiedSampleBuffer)
        guard timestamp.isNumeric,
              timestamp.seconds.isFinite else {
            return
        }
        frameHandler(
            timestamp.seconds,
            AppleRecordingAudioFramePayload(sampleBuffer: copiedSampleBuffer)
        )
    }
}

struct AVCaptureAudioRecordingDriverFactory: RecordingAudioDriverFactory {
    func makeAudioDriver(for configuration: RecordingConfiguration) throws -> any RecordingAudioDriver {
        try AVCaptureAudioRecordingDriver()
    }
}
