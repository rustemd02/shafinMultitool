import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

/// M7-005: production codec-availability check. Both v1 codecs use platform
/// encoders that exist on every supported deployment target (iOS 17.2);
/// hardware-encode behavior per physical device stays an external
/// qualification concern and is deliberately not claimed here.
struct AppleRecordingCodecSupportChecker: RecordingCodecSupportChecking {
    func isSupported(_ codec: RecordingQuickTimeCodec) -> Bool {
        switch codec {
        case .h264:
            AVVideoCodecType.h264 != nil
        case .hevc:
            AVVideoCodecType.hevc != nil
        }
    }
}

/// M7-007: maps the frozen orientation/mirroring metadata onto the
/// CGAffineTransform written into the QuickTime track. Pixels are never
/// rotated; the player applies this transform at display time.
///
/// The producer declares the source pixel baseline. Existing portrait-oriented
/// producers retain their convention; unrotated Camera Coach sensor buffers
/// use landscape-right as identity. The dimension-aware overload translates
/// the transformed rectangle into positive display coordinates.
enum AppleRecordingTrackTransformMapper {
    static func transform(for metadata: RecordingTrackTransformMetadata) -> CGAffineTransform {
        guard metadata.strategy != .identityMetadata else { return .identity }
        let rotation: CGAffineTransform
        switch metadata.pixelOrientationBaseline {
        case .portraitOriented:
            switch metadata.captureOrientation {
            case .portrait: rotation = .identity
            case .portraitUpsideDown: rotation = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 0, ty: 0)
            case .landscapeLeft: rotation = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)
            case .landscapeRight: rotation = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0)
            }
        case .nativeLandscapeRight:
            switch metadata.captureOrientation {
            case .portrait: rotation = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0)
            case .portraitUpsideDown: rotation = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)
            case .landscapeLeft: rotation = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 0, ty: 0)
            case .landscapeRight: rotation = .identity
            }
        }
        guard metadata.isMirrored else { return rotation }
        return rotation.scaledBy(x: -1, y: 1)
    }

    static func transform(for metadata: RecordingTrackTransformMetadata,
                          width: Int,
                          height: Int) -> CGAffineTransform {
        let rotation = transform(for: metadata)
        let source = CGRect(x: 0, y: 0, width: width, height: height)
        let bounds = source.applying(rotation)
        return CGAffineTransform(a: rotation.a, b: rotation.b,
                                 c: rotation.c, d: rotation.d,
                                 tx: -bounds.minX, ty: -bounds.minY)
    }
}

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

/// M7-026: answers whether a local movie is playable before a player is
/// presented. Missing, unreadable, or undecodable files fail closed so the
/// shell can surface localized recovery instead of an empty player.
protocol RecordingPlaybackProbing: Sendable {
    func isPlayableMovie(at url: URL) async -> Bool
}

struct AVURLAssetPlaybackProbe: RecordingPlaybackProbing {
    func isPlayableMovie(at url: URL) async -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let asset = AVURLAsset(url: url)
        guard (try? await asset.load(.isPlayable)) == true else { return false }
        let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        return !tracks.isEmpty
    }
}

/// M7-021: reads duration/audio truth from a finalized movie for recovery.
/// Returns nil for unreadable assets so recovery classifies honestly instead
/// of inventing metadata.
enum AppleRecordingMediaMetadataProbe {
    static func probe(_ url: URL) -> (duration: TimeInterval?, hasAudio: Bool) {
        let asset = AVURLAsset(url: url)
        let assetDuration = asset.duration
        let duration: TimeInterval?
        if assetDuration.isNumeric,
           assetDuration.seconds.isFinite,
           assetDuration.seconds >= 0 {
            duration = assetDuration.seconds
        } else {
            duration = nil
        }
        let hasAudio = !asset.tracks(withMediaType: .audio).isEmpty
        return (duration, hasAudio)
    }
}

/// M7-018: answers whether a writer/append error is storage exhaustion
/// (ENOSPC-class). POSIX ENOSPC (28) and Cocoa's out-of-space codes both map
/// here so disk exhaustion can be typed instead of reported as a generic
/// append failure.
func isStoragePressureError(_ error: (any Error)?) -> Bool {
    guard let error else { return false }
    let nsError = error as NSError
    switch nsError.domain {
    case NSPOSIXErrorDomain:
        return nsError.code == Int(ENOSPC)
    case NSCocoaErrorDomain:
        return nsError.code == NSFileWriteOutOfSpaceError
    default:
        return false
    }
}

struct AVAssetWriterRecordingWriterFactory: RecordingWriterFactory {
    let codecSupport: any RecordingCodecSupportChecking

    init(codecSupport: any RecordingCodecSupportChecking = AppleRecordingCodecSupportChecker()) {
        self.codecSupport = codecSupport
    }

    func makeWriter(for configuration: RecordingConfiguration) throws -> any RecordingWriter {
        guard configuration.width > 0,
              configuration.height > 0,
              configuration.fps > 0 else {
            throw RecordingWriterError.inputRejected
        }
        // M7-005: an unsupported codec or an explicitly zero pixel format
        // fails before any writer is created; there is no implicit fallback.
        guard codecSupport.isSupported(configuration.videoCodec) else {
            throw RecordingWriterError.unsupportedVideoCodec
        }
        guard configuration.pixelFormatFourCC != 0 else {
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
    private var lastAppendedVideoPresentationTime: CMTime?
    private var finishRequested = false
    private var completionDelivered = false
    private var discarded = false
    private var videoInputFinished = false
    private var audioInputFinished = false

    init(writer: AVAssetWriter, configuration: RecordingConfiguration) throws {
        guard configuration.width > 0,
              configuration.height > 0,
              configuration.fps > 0,
              configuration.fps <= Int(CMTimeScale.max) else {
            throw RecordingWriterError.inputRejected
        }

        // M7-005: video settings are derived from the selected capture format
        // (codec, dimensions, FPS, pixel format); audio keeps the fixed v1
        // AAC 48 kHz mono format. Invalid combinations never reach recording.
        let codecType: AVVideoCodecType
        switch configuration.videoCodec {
        case .h264:
            codecType = .h264
        case .hevc:
            codecType = .hevc
        }
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codecType,
            AVVideoWidthKey: configuration.width,
            AVVideoHeightKey: configuration.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoExpectedSourceFrameRateKey: configuration.fps,
                AVVideoAllowFrameReorderingKey: false,
            ],
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        // M7-007: orientation/mirroring travels as track metadata so frames
        // keep their native dimensions and are never rotated per sample.
        if let trackTransform = configuration.trackTransform {
            videoInput.transform = AppleRecordingTrackTransformMapper.transform(
                for: trackTransform, width: configuration.width, height: configuration.height
            )
        }

        var pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: configuration.width,
            kCVPixelBufferHeightKey as String: configuration.height,
        ]
        // M7-005: an explicitly provided capture pixel format pins the
        // adaptor to the active capture format; `nil` keeps the platform
        // default for direct constructions.
        if let pixelFormatFourCC = configuration.pixelFormatFourCC {
            pixelBufferAttributes[kCVPixelBufferPixelFormatTypeKey as String] = pixelFormatFourCC
        }
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

    private func dispositionForWriterFailure() -> RecordingAppendDisposition {
        // M7-018: a failed writer is inspected for storage exhaustion so a
        // full disk produces the typed ENOSPC-class disposition.
        if writer.status == .failed, isStoragePressureError(writer.error) {
            return .storagePressure
        }
        return .failed
    }

    func appendVideo(_ frame: RecordingVideoFrame) -> RecordingAppendDisposition {
        lock.lock()
        defer { lock.unlock() }

        guard started,
              !finishRequested,
              !discarded else {
            return .failed
        }
        guard writer.status == .writing else {
            return dispositionForWriterFailure()
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

        guard sessionStarted else {
            return .failed
        }
        if pixelBufferAdaptor.append(payload.pixelBuffer, withPresentationTime: presentationTime) {
            lastAppendedVideoPresentationTime = presentationTime
            return .appended
        }
        return dispositionForWriterFailure()
    }

    func appendAudio(_ frame: RecordingAudioFrame) -> RecordingAppendDisposition {
        lock.lock()
        defer { lock.unlock() }

        guard started,
              !finishRequested,
              !discarded else {
            return .failed
        }
        guard writer.status == .writing else {
            return dispositionForWriterFailure()
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
        if audioInput.append(sampleBuffer) {
            return .appended
        }
        return dispositionForWriterFailure()
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
        if canFinish, sessionStarted, writer.status == .writing,
           let lastAppendedVideoPresentationTime {
            // The adaptor supplies PTS without a per-sample duration. Without
            // an explicit session end, a sparse final sample can inherit the
            // preceding timestamp gap as its duration. Keep every accepted
            // PTS and end only one nominal frame after the last written frame.
            // Dropped frames never advance this boundary. Audio beyond the
            // video end is edited out of playback by the same session end.
            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(configuration.fps))
            writer.endSession(atSourceTime: CMTimeAdd(lastAppendedVideoPresentationTime, frameDuration))
        }
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
