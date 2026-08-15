import Foundation

struct RecordingID: Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

enum RecordingAudioMode: Sendable, Equatable {
    case disabled
    case required
}

struct RecordingConfiguration: Sendable, Equatable {
    let id: RecordingID
    let outputURL: URL
    let width: Int
    let height: Int
    let fps: Int
    let audioMode: RecordingAudioMode

    init(id: RecordingID,
         outputURL: URL,
         width: Int,
         height: Int,
         fps: Int,
         audioMode: RecordingAudioMode) {
        self.id = id
        self.outputURL = outputURL
        self.width = width
        self.height = height
        self.fps = fps
        self.audioMode = audioMode
    }
}

enum RecordingStopReason: String, Sendable, Equatable {
    case user
    case routeExit
    case background
    case interruption
    case storagePressure
    case thermal
}

struct RecordingArtifact: Sendable, Equatable {
    let id: RecordingID
    let localURL: URL
    let duration: TimeInterval?
    let hasAudio: Bool
}

enum RecorderFailure: Error, Sendable, Equatable {
    case invalidTransition
    case outputAlreadyExists
    case writerCreationFailed
    case writerInputRejected
    case writerStartFailed
    case audioUnavailable
    case audioStartFailed
    case videoAppendFailed
    case audioAppendFailed
    case noVideoFrames
    case finishFailed
}

enum RecordingStopResult: Sendable, Equatable {
    case finalized(RecordingArtifact)
    case failed(RecorderFailure, recoverableArtifact: RecordingArtifact?)
}

enum RecorderState: String, Sendable, Equatable {
    case idle
    case prepared
    case recording
    case finishing
    case finished
    case failed
    case released
}

struct RecordingFrameFence: Hashable, Sendable, Equatable {
    let recordingID: RecordingID
    let generation: UInt64
}

struct RecorderStateSnapshot: Sendable, Equatable {
    let state: RecorderState
    let recordingID: RecordingID?
    let generation: UInt64

    var frameFence: RecordingFrameFence? {
        guard let recordingID else { return nil }
        return RecordingFrameFence(recordingID: recordingID, generation: generation)
    }
}

protocol RecordingVideoFramePayload: Sendable {}
protocol RecordingAudioFramePayload: Sendable {}

struct RecordingVideoFrame: Sendable {
    let recordingID: RecordingID
    let generation: UInt64
    let timestamp: TimeInterval
    let payload: (any RecordingVideoFramePayload)?

    init(recordingID: RecordingID,
         generation: UInt64,
         timestamp: TimeInterval,
         payload: (any RecordingVideoFramePayload)? = nil) {
        self.recordingID = recordingID
        self.generation = generation
        self.timestamp = timestamp
        self.payload = payload
    }

    init(fence: RecordingFrameFence,
         timestamp: TimeInterval,
         payload: (any RecordingVideoFramePayload)? = nil) {
        self.init(recordingID: fence.recordingID,
                  generation: fence.generation,
                  timestamp: timestamp,
                  payload: payload)
    }
}

struct RecordingAudioFrame: Sendable {
    let recordingID: RecordingID
    let generation: UInt64
    let timestamp: TimeInterval
    let payload: (any RecordingAudioFramePayload)?

    init(recordingID: RecordingID,
         generation: UInt64,
         timestamp: TimeInterval,
         payload: (any RecordingAudioFramePayload)? = nil) {
        self.recordingID = recordingID
        self.generation = generation
        self.timestamp = timestamp
        self.payload = payload
    }

    init(fence: RecordingFrameFence,
         timestamp: TimeInterval,
         payload: (any RecordingAudioFramePayload)? = nil) {
        self.init(recordingID: fence.recordingID,
                  generation: fence.generation,
                  timestamp: timestamp,
                  payload: payload)
    }
}

/// A failed finish may carry an artifact only when the writer itself
/// explicitly attests that the local file is finalized/recoverable. The
/// recorder never derives that disposition from accepted frame counts.
enum RecordingWriterError: Error, Sendable, Equatable {
    case inputRejected
    case finishFailed(recoverableArtifact: RecordingArtifact?)
}

enum RecordingAudioDriverError: Error, Sendable, Equatable {
    case unavailable
}

struct RecordingWriterFinish: Sendable, Equatable {
    let duration: TimeInterval?
    /// The writer's completion metadata is authoritative for the artifact's
    /// audio disposition.
    let hasAudio: Bool

    init(duration: TimeInterval? = nil, hasAudio: Bool = false) {
        self.duration = duration
        self.hasAudio = hasAudio
    }
}

protocol RecordingWriter: AnyObject {
    func start() -> Bool
    func appendVideo(_ frame: RecordingVideoFrame) -> Bool
    func appendAudio(_ frame: RecordingAudioFrame) -> Bool
    func markVideoInputAsFinished()
    func markAudioInputAsFinished()
    func finishWriting(completion: @escaping (Result<RecordingWriterFinish, RecordingWriterError>) -> Void)
    func discard()
}

protocol RecordingWriterFactory {
    func makeWriter(for configuration: RecordingConfiguration) throws -> any RecordingWriter
}

protocol RecordingAudioDriver: AnyObject {
    func start() -> Bool
    func stop()
}

protocol RecordingAudioDriverFactory {
    func makeAudioDriver(for configuration: RecordingConfiguration) throws -> any RecordingAudioDriver
}

protocol RecordingOutputChecking {
    func exists(at url: URL) -> Bool
}

struct LocalRecordingOutputChecker: RecordingOutputChecking, Sendable {
    func exists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

/// Exporting is intentionally separate from local recording. A future Photos or
/// share implementation owns this boundary; the recorder never invokes it.
protocol RecordingExporting {
    func export(_ artifact: RecordingArtifact) async throws
}

protocol MediaRecording: AnyObject {
    var state: RecorderState { get async }

    func stateSnapshot() async -> RecorderStateSnapshot
    func prepare(_ configuration: RecordingConfiguration) async throws
    func start() async throws
    func stop(reason: RecordingStopReason) async -> RecordingStopResult

    /// Idle/prepared release returns `nil` after cleanup. Recording/finishing
    /// release waits for and returns the shared final result. Terminal release
    /// returns the cached final result when one exists, making repeated release
    /// deterministic without re-preparing or exporting anything.
    func releaseAndWait() async -> RecordingStopResult?

    /// Enqueue methods return immediately. The recorder queue decides whether a
    /// frame is still valid when the submitted work reaches the queue.
    func enqueueVideo(_ frame: RecordingVideoFrame)
    func enqueueAudio(_ frame: RecordingAudioFrame)
}
