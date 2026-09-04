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

enum RecordingAppendDisposition: Sendable, Equatable {
    case appended
    case dropped
    case failed
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

/// M1-010 RecordingOwner canonical recording lifecycle. This is the single
/// state vocabulary for recording progress across `SerializedMediaRecorder`,
/// `SceneRecordingController` and the legacy `CameraService` writer path; the
/// owners keep their own confinement and policies but every state they expose
/// maps onto one of these cases, and every transition must be legal per
/// ``isLegalTransition(from:to:)``.
enum RecordingLifecycleState: String, CaseIterable, Sendable, Equatable {
    case idle
    case preparing
    case ready
    case starting
    case recording
    case stopping
    case finalizing
    case promoting
    case completed
    case failed
    case cancelled
    /// Owner-cleanup terminal: workspace/route release has disposed the take.
    /// Beyond the plan's canonical set because both existing owners expose it.
    case released

    init(_ recorderState: RecorderState) {
        self = switch recorderState {
        case .idle: .idle
        case .prepared: .ready
        case .recording: .recording
        case .finishing: .finalizing
        case .finished: .completed
        case .failed: .failed
        case .released: .released
        }
    }

    /// Canonical transition table. `released` is terminal. Coarse legacy edges
    /// (`idle → recording` atomic start, `finalizing/failed → idle` cleanup)
    /// and the controller's between-takes return (`recording/stopping → idle`)
    /// exist on the owner paths and are kept legal so the table describes
    /// observed behavior; the serialized recorder enforces its own stricter
    /// policy on top.
    static func isLegalTransition(from: RecordingLifecycleState,
                                  to: RecordingLifecycleState) -> Bool {
        if from == to { return false }
        switch from {
        case .idle:
            switch to {
            case .preparing, .ready, .starting, .recording, .failed, .cancelled, .released:
                return true
            default:
                return false
            }
        case .preparing:
            return to == .ready || to == .failed || to == .cancelled || to == .released
        case .ready:
            return to == .starting || to == .recording || to == .failed
                || to == .cancelled || to == .released
        case .starting:
            return to == .recording || to == .stopping || to == .idle
                || to == .failed || to == .cancelled || to == .released
        case .recording:
            return to == .stopping || to == .finalizing || to == .idle
                || to == .failed || to == .cancelled || to == .released
        case .stopping:
            return to == .finalizing || to == .completed || to == .idle || to == .failed
                || to == .cancelled || to == .released
        case .finalizing:
            return to == .promoting || to == .completed || to == .failed
                || to == .cancelled || to == .idle || to == .released
        case .promoting:
            return to == .completed || to == .failed || to == .cancelled
        case .completed:
            return to == .promoting || to == .released
        case .failed:
            return to == .finalizing || to == .idle || to == .cancelled || to == .released
        case .cancelled:
            return to == .released
        case .released:
            return false
        }
    }
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
    func appendVideo(_ frame: RecordingVideoFrame) -> RecordingAppendDisposition
    func appendAudio(_ frame: RecordingAudioFrame) -> RecordingAppendDisposition
    func markVideoInputAsFinished()
    func markAudioInputAsFinished()
    func finishWriting(completion: @escaping (Result<RecordingWriterFinish, RecordingWriterError>) -> Void)
    func discard()
}

protocol RecordingWriterFactory {
    func makeWriter(for configuration: RecordingConfiguration) throws -> any RecordingWriter
}

typealias RecordingAudioFrameHandler = @Sendable (
    _ timestamp: TimeInterval,
    _ payload: any RecordingAudioFramePayload
) -> Void

protocol RecordingAudioDriver: AnyObject {
    func start(onFrame: @escaping RecordingAudioFrameHandler) -> Bool
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
