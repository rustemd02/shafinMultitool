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

/// Native pixel format FourCC value used by the serialized capture path. The
/// plain `UInt32` representation keeps this contracts file free of a
/// CoreVideo dependency; the Apple adapter maps it onto
/// `kCVPixelBufferPixelFormatTypeKey`.
enum RecordingPixelFormat {
    /// `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange` (`420v`), the native
    /// output of AVCapture/ARKit capture pipelines.
    static let yPlanar420VideoRange: UInt32 = 875704438
}

struct RecordingConfiguration: Sendable, Equatable {
    let id: RecordingID
    let outputURL: URL
    let width: Int
    let height: Int
    let fps: Int
    let audioMode: RecordingAudioMode
    /// M7-005: native capture pixel format the writer must accept. `nil`
    /// preserves the platform-default adaptor behavior for direct
    /// constructions; the serialized capture path always passes the active
    /// buffer's actual FourCC. A present `0` is rejected by the factory.
    let pixelFormatFourCC: UInt32?
    /// M7-005: explicitly selected, device-supported video codec. There is no
    /// implicit codec fallback: an unsupported selection fails before recording.
    let videoCodec: RecordingQuickTimeCodec
    /// M7-007: orientation/mirroring metadata written to the video track.
    /// `nil` preserves the identity-transform behavior of existing takes.
    let trackTransform: RecordingTrackTransformMetadata?

    init(id: RecordingID,
         outputURL: URL,
         width: Int,
         height: Int,
         fps: Int,
         audioMode: RecordingAudioMode,
         pixelFormatFourCC: UInt32? = nil,
         videoCodec: RecordingQuickTimeCodec = .h264,
         trackTransform: RecordingTrackTransformMetadata? = nil) {
        self.id = id
        self.outputURL = outputURL
        self.width = width
        self.height = height
        self.fps = fps
        self.audioMode = audioMode
        self.pixelFormatFourCC = pixelFormatFourCC
        self.videoCodec = videoCodec
        self.trackTransform = trackTransform
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
    case sourceClaimRejected
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
    let ownerToken: RecordingOwnerToken?

    init(recordingID: RecordingID,
         generation: UInt64,
         ownerToken: RecordingOwnerToken? = nil) {
        self.recordingID = recordingID
        self.generation = generation
        self.ownerToken = ownerToken
    }

    init(ownerToken: RecordingOwnerToken) {
        self.init(recordingID: ownerToken.recordingID,
                  generation: ownerToken.generation,
                  ownerToken: ownerToken)
    }
}

struct RecorderStateSnapshot: Sendable, Equatable {
    let state: RecorderState
    let recordingID: RecordingID?
    let generation: UInt64
    let ownerToken: RecordingOwnerToken?

    init(state: RecorderState,
         recordingID: RecordingID?,
         generation: UInt64,
         ownerToken: RecordingOwnerToken? = nil) {
        self.state = state
        self.recordingID = recordingID
        self.generation = generation
        self.ownerToken = ownerToken
    }

    var frameFence: RecordingFrameFence? {
        guard let recordingID else { return nil }
        return RecordingFrameFence(recordingID: recordingID,
                                   generation: generation,
                                   ownerToken: ownerToken)
    }
}

protocol RecordingVideoFramePayload: Sendable {}
protocol RecordingAudioFramePayload: Sendable {}

struct RecordingVideoFrame: Sendable {
    let recordingID: RecordingID
    let generation: UInt64
    let timestamp: TimeInterval
    let ownerToken: RecordingOwnerToken?
    let payload: (any RecordingVideoFramePayload)?

    init(recordingID: RecordingID,
         generation: UInt64,
         timestamp: TimeInterval,
         payload: (any RecordingVideoFramePayload)? = nil,
         ownerToken: RecordingOwnerToken? = nil) {
        self.recordingID = recordingID
        self.generation = generation
        self.timestamp = timestamp
        self.ownerToken = ownerToken
        self.payload = payload
    }

    init(fence: RecordingFrameFence,
         timestamp: TimeInterval,
         payload: (any RecordingVideoFramePayload)? = nil) {
        self.init(recordingID: fence.recordingID,
                  generation: fence.generation,
                  timestamp: timestamp,
                  payload: payload,
                  ownerToken: fence.ownerToken)
    }

    init(ownerToken: RecordingOwnerToken,
         timestamp: TimeInterval,
         payload: (any RecordingVideoFramePayload)? = nil) {
        self.init(recordingID: ownerToken.recordingID,
                  generation: ownerToken.generation,
                  timestamp: timestamp,
                  payload: payload,
                  ownerToken: ownerToken)
    }
}

struct RecordingAudioFrame: Sendable {
    let recordingID: RecordingID
    let generation: UInt64
    let timestamp: TimeInterval
    let ownerToken: RecordingOwnerToken?
    let payload: (any RecordingAudioFramePayload)?

    init(recordingID: RecordingID,
         generation: UInt64,
         timestamp: TimeInterval,
         payload: (any RecordingAudioFramePayload)? = nil,
         ownerToken: RecordingOwnerToken? = nil) {
        self.recordingID = recordingID
        self.generation = generation
        self.timestamp = timestamp
        self.ownerToken = ownerToken
        self.payload = payload
    }

    init(fence: RecordingFrameFence,
         timestamp: TimeInterval,
         payload: (any RecordingAudioFramePayload)? = nil) {
        self.init(recordingID: fence.recordingID,
                  generation: fence.generation,
                  timestamp: timestamp,
                  payload: payload,
                  ownerToken: fence.ownerToken)
    }

    init(ownerToken: RecordingOwnerToken,
         timestamp: TimeInterval,
         payload: (any RecordingAudioFramePayload)? = nil) {
        self.init(recordingID: ownerToken.recordingID,
                  generation: ownerToken.generation,
                  timestamp: timestamp,
                  payload: payload,
                  ownerToken: ownerToken)
    }
}

/// A failed finish may carry an artifact only when the writer itself
/// explicitly attests that the local file is finalized/recoverable. The
/// recorder never derives that disposition from accepted frame counts.
enum RecordingWriterError: Error, Sendable, Equatable {
    case inputRejected
    /// M7-005: the selected codec is not supported by this device, rejected
    /// before any writer is created so recording never starts with a fallback.
    case unsupportedVideoCodec
    case finishFailed(recoverableArtifact: RecordingArtifact?)
}

/// M7-005: answers whether the platform can encode the selected codec. The
/// production implementation checks the platform encoder availability; the
/// narrow seam keeps unsupported-codec fixtures deterministic without
/// fabricating hardware.
protocol RecordingCodecSupportChecking: Sendable {
    func isSupported(_ codec: RecordingQuickTimeCodec) -> Bool
}

/// M7-006: bounded report of the serialized recorder's monotonic media
/// timebase. Timestamps are host seconds as supplied by the producer; the
/// report never contains sample payloads. Rejection and discontinuity counts
/// are the recorder's only "handling" of timeline faults: faulted samples are
/// never appended, and the stream timeline continues monotonically.
struct RecordingTimebaseReport: Sendable, Equatable {
    /// Host timestamp of the first admitted video sample of the take.
    /// `nil` until the first video sample passes admission.
    let videoOrigin: TimeInterval?
    let acceptedVideoCount: Int
    let acceptedAudioCount: Int
    /// Samples rejected because their timestamp was non-finite.
    let rejectedInvalidTimestampCount: Int
    /// Video samples rejected for a non-strictly-monotonic timestamp.
    let rejectedNonMonotonicVideoCount: Int
    /// Audio samples rejected for a non-strictly-monotonic timestamp.
    let rejectedNonMonotonicAudioCount: Int
    /// Audio samples rejected because they precede the established video
    /// origin (a negative session time cannot be represented).
    let rejectedBeforeOriginAudioCount: Int
    /// Forward gaps larger than the documented discontinuity threshold that
    /// were tolerated while keeping the timeline monotonic.
    let discontinuityCount: Int
    let lastVideoTimestamp: TimeInterval?
    let lastAudioTimestamp: TimeInterval?
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
    func claimRecordingSource(_ ownerToken: RecordingOwnerToken) async -> Bool
    func releaseRecordingSource(_ ownerToken: RecordingOwnerToken) async -> Bool
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

// MARK: - M7-001 recording contract v1

/// The two production workspaces that may own a recording source.  A source
/// is part of the owner token rather than an inferred property of a frame so a
/// Camera and AR producer cannot silently share a take.
enum RecordingWorkspaceSource: String, CaseIterable, Sendable, Equatable {
    case cameraCoach
    case arWorkspace
}

/// The non-UI identity fence for one recording take.  `generation` starts at
/// one and changes whenever the source owner is replaced.  It is deliberately
/// separate from `RecordingFrameFence`: the latter is the existing enqueue
/// boundary, while this token is the v1 source contract.
struct RecordingOwnerToken: Hashable, Sendable {
    let source: RecordingWorkspaceSource
    let ownerID: UUID
    let recordingID: RecordingID
    let generation: UInt64

    init(source: RecordingWorkspaceSource,
         ownerID: UUID,
         recordingID: RecordingID,
         generation: UInt64) {
        self.source = source
        self.ownerID = ownerID
        self.recordingID = recordingID
        self.generation = generation
    }

    var isValid: Bool {
        !isZeroUUID(ownerID)
            && !isZeroUUID(recordingID.rawValue)
            && generation > 0
    }
}

/// Shared source identity comparison used by every recorder append boundary.
/// An untagged frame remains compatible only while no source claim exists;
/// once claimed, the exact owner token (including route, owner and generation)
/// is required.
enum RecordingSourceFence {
    static func accepts(frameOwnerToken: RecordingOwnerToken?,
                        activeOwnerToken: RecordingOwnerToken?) -> Bool {
        guard let activeOwnerToken else { return frameOwnerToken == nil }
        return frameOwnerToken == activeOwnerToken
    }
}

/// QuickTime movies are the only v1 container.  Codec support is still
/// checked by the later adapter task; the contract records the selected
/// supported codec instead of guessing a fallback.
enum RecordingQuickTimeCodec: String, CaseIterable, Sendable, Equatable {
    case h264
    case hevc
}

enum RecordingMediaContainer: String, CaseIterable, Sendable, Equatable {
    case quickTimeMovie
}

struct RecordingQuickTimeMediaFormat: Sendable, Equatable {
    let container: RecordingMediaContainer
    let codec: RecordingQuickTimeCodec
    /// Native pixel-format FourCC.  Zero is not a valid pixel format.
    let pixelFormatFourCC: UInt32
    let width: Int
    let height: Int
    let framesPerSecond: Int

    init(container: RecordingMediaContainer,
         codec: RecordingQuickTimeCodec,
         pixelFormatFourCC: UInt32,
         width: Int,
         height: Int,
         framesPerSecond: Int) {
        self.container = container
        self.codec = codec
        self.pixelFormatFourCC = pixelFormatFourCC
        self.width = width
        self.height = height
        self.framesPerSecond = framesPerSecond
    }

    /// Alias matching the existing recording vocabulary and plan wording.
    var fps: Int { framesPerSecond }
}

/// Four capture orientations are represented as metadata.  The recording
/// writer must not rotate every frame merely to make a preview look upright.
enum RecordingCaptureOrientation: String, CaseIterable, Sendable, Equatable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight
}

enum RecordingTrackTransformMetadataStrategy: String, CaseIterable, Sendable, Equatable {
    /// Keep source pixels native and write the orientation to the track.
    case preferredTransformMetadata
    /// Preserve an explicitly identity transform for already-normalized input.
    case identityMetadata
}

struct RecordingTrackTransformMetadata: Sendable, Equatable {
    let captureOrientation: RecordingCaptureOrientation
    let isMirrored: Bool
    let strategy: RecordingTrackTransformMetadataStrategy

    init(captureOrientation: RecordingCaptureOrientation,
         isMirrored: Bool,
         strategy: RecordingTrackTransformMetadataStrategy) {
        self.captureOrientation = captureOrientation
        self.isMirrored = isMirrored
        self.strategy = strategy
    }
}

/// A required microphone is a hard precondition.  Video-only capture is an
/// explicit caller selection (`.disabled`), never a fallback from `.required`.
enum RecordingAudioUnavailableBehavior: String, CaseIterable, Sendable, Equatable {
    case notRequested
    case failRecording
    case explicitVideoOnlySelection
}

struct RecordingAudioPolicy: Sendable, Equatable {
    let mode: RecordingAudioMode
    let unavailableBehavior: RecordingAudioUnavailableBehavior

    init(mode: RecordingAudioMode,
         unavailableBehavior: RecordingAudioUnavailableBehavior) {
        self.mode = mode
        self.unavailableBehavior = unavailableBehavior
    }
}

/// The host clock, origin and ordering rule are all explicit parts of the
/// schema.  No AVFoundation clock or UIKit orientation type crosses this
/// boundary.
enum RecordingHostTimebase: String, CaseIterable, Sendable, Equatable {
    case hostMonotonic
}

enum RecordingTimeOrigin: String, CaseIterable, Sendable, Equatable {
    case firstAcceptedVideoOrigin
}

enum RecordingStreamTimePolicy: String, CaseIterable, Sendable, Equatable {
    case strictPerStreamMonotonic
}

struct RecordingTimebasePolicy: Sendable, Equatable {
    let hostClock: RecordingHostTimebase
    let origin: RecordingTimeOrigin
    let streamPolicy: RecordingStreamTimePolicy

    init(hostClock: RecordingHostTimebase,
         origin: RecordingTimeOrigin,
         streamPolicy: RecordingStreamTimePolicy) {
        self.hostClock = hostClock
        self.origin = origin
        self.streamPolicy = streamPolicy
    }

    static let canonical = RecordingTimebasePolicy(
        hostClock: .hostMonotonic,
        origin: .firstAcceptedVideoOrigin,
        streamPolicy: .strictPerStreamMonotonic
    )
}

/// A recording can remain app-local until a project exists, or can be
/// promoted to exactly one identified scene project.  The all-zero UUID is
/// rejected by `RecordingContractV1.validate()`.
enum RecordingPromotionTarget: Sendable, Equatable {
    case appLocal
    case sceneProject(UUID)
}

enum RecordingTerminalOutcome: String, CaseIterable, Sendable, Equatable {
    case finalized
    case recoverableFailure
    case unrecoverableFailure
    case cancelledPrecommit
    case promotedProjectOwned
}

enum RecordingTerminalObligation: String, CaseIterable, Sendable, Equatable {
    /// Keep a finalized artifact in app-local storage until a project exists.
    case preserveAppLocalMedia
    /// Pending → durable journal → idempotent promotion.
    case pendingJournalThenIdempotentPromotion
    /// Keep the failed artifact and write a recovery journal.
    case recoveryJournal
    /// Remove only partials owned by this recording task.
    case cleanTaskPartials
    /// A promoted project file is user media and must not be cleaned up here.
    case preserveProjectOwnedMedia
    /// `.promotedProjectOwned` cannot occur while the target is app-local.
    case notApplicableForAppLocalTarget

    static func canonical(for outcome: RecordingTerminalOutcome,
                          target: RecordingPromotionTarget) -> Self {
        switch (outcome, target) {
        case (.finalized, .appLocal):
            return .preserveAppLocalMedia
        case (.finalized, .sceneProject):
            return .pendingJournalThenIdempotentPromotion
        case (.recoverableFailure, _):
            return .recoveryJournal
        case (.unrecoverableFailure, _), (.cancelledPrecommit, _):
            return .cleanTaskPartials
        case (.promotedProjectOwned, .appLocal):
            return .notApplicableForAppLocalTarget
        case (.promotedProjectOwned, .sceneProject):
            return .preserveProjectOwnedMedia
        }
    }
}

/// Explicitly states whether a terminal row may carry a local artifact. A
/// recoverable failure therefore cannot silently become a journal-only error
/// with no artifact to recover.
enum RecordingTerminalArtifactRequirement: String, CaseIterable, Sendable, Equatable {
    case required
    case forbidden
}

/// Relates a terminal row to the existing typed recorder and cancellation
/// values. A nil associated value is a deliberate wildcard meaning "any value
/// of this existing typed category", not an untyped error fallback.
enum RecordingTerminalFailureRelation: Sendable, Equatable {
    case none
    case recoverableFailure(RecorderFailure?)
    case unrecoverableFailure(RecorderFailure?)
    case cancelled(RecordingStopReason?)

    private enum Kind: Sendable, Equatable {
        case none
        case recoverableFailure
        case unrecoverableFailure
        case cancelled
    }

    private var kind: Kind {
        switch self {
        case .none: return .none
        case .recoverableFailure: return .recoverableFailure
        case .unrecoverableFailure: return .unrecoverableFailure
        case .cancelled: return .cancelled
        }
    }

    /// Allows a row to be either wildcard-typed (the canonical table) or more
    /// specific while preserving the same terminal category.
    fileprivate func isCompatible(with expected: Self) -> Bool {
        kind == expected.kind
    }
}

struct RecordingTerminalDisposition: Sendable, Equatable {
    let outcome: RecordingTerminalOutcome
    let obligation: RecordingTerminalObligation
    let artifactRequirement: RecordingTerminalArtifactRequirement
    let failureRelation: RecordingTerminalFailureRelation

    init(outcome: RecordingTerminalOutcome,
         obligation: RecordingTerminalObligation,
         artifactRequirement: RecordingTerminalArtifactRequirement,
         failureRelation: RecordingTerminalFailureRelation) {
        self.outcome = outcome
        self.obligation = obligation
        self.artifactRequirement = artifactRequirement
        self.failureRelation = failureRelation
    }

    static func canonical(for outcome: RecordingTerminalOutcome,
                          target: RecordingPromotionTarget) -> Self {
        let artifactRequirement: RecordingTerminalArtifactRequirement
        let failureRelation: RecordingTerminalFailureRelation
        switch outcome {
        case .finalized, .promotedProjectOwned:
            artifactRequirement = .required
            failureRelation = .none
        case .recoverableFailure:
            artifactRequirement = .required
            failureRelation = .recoverableFailure(nil)
        case .unrecoverableFailure:
            artifactRequirement = .forbidden
            failureRelation = .unrecoverableFailure(nil)
        case .cancelledPrecommit:
            artifactRequirement = .forbidden
            failureRelation = .cancelled(nil)
        }
        return RecordingTerminalDisposition(
            outcome: outcome,
            obligation: RecordingTerminalObligation.canonical(
                for: outcome,
                target: target
            ),
            artifactRequirement: artifactRequirement,
            failureRelation: failureRelation
        )
    }

    /// Purely checks a terminal observation against this row. Runtime owners
    /// remain responsible for producing the observation; this method only
    /// applies the v1 schema.
    func accepts(artifact: RecordingArtifact?,
                 recorderFailure: RecorderFailure?,
                 stopReason: RecordingStopReason?) -> Bool {
        guard obligation != .notApplicableForAppLocalTarget else { return false }

        let artifactIsValid = switch artifactRequirement {
        case .required: artifact != nil
        case .forbidden: artifact == nil
        }
        guard artifactIsValid else { return false }

        switch failureRelation {
        case .none:
            return recorderFailure == nil && stopReason == nil
        case .recoverableFailure(let expectedFailure):
            guard let recorderFailure, stopReason == nil else { return false }
            return expectedFailure == nil || expectedFailure == recorderFailure
        case .unrecoverableFailure(let expectedFailure):
            guard let recorderFailure, stopReason == nil else { return false }
            return expectedFailure == nil || expectedFailure == recorderFailure
        case .cancelled(let expectedReason):
            guard recorderFailure == nil, let stopReason else { return false }
            return expectedReason == nil || expectedReason == stopReason
        }
    }
}

/// A data table rather than a switch keeps the terminal obligations inspectable
/// in evidence and makes missing/duplicate outcomes testable.  The canonical
/// table is the only v1 mapping accepted by `RecordingContractV1`.
struct RecordingTerminalDispositionMatrix: Sendable, Equatable {
    let entries: [RecordingTerminalDisposition]

    init(entries: [RecordingTerminalDisposition]) {
        self.entries = entries
    }

    static func canonical(for target: RecordingPromotionTarget) -> Self {
        RecordingTerminalDispositionMatrix(
            entries: RecordingTerminalOutcome.allCases.map {
                RecordingTerminalDisposition.canonical(for: $0, target: target)
            }
        )
    }

    func disposition(for outcome: RecordingTerminalOutcome) -> RecordingTerminalDisposition? {
        entries.first(where: { $0.outcome == outcome })
    }

    func obligation(for outcome: RecordingTerminalOutcome) -> RecordingTerminalObligation? {
        disposition(for: outcome)?.obligation
    }
}

/// Typed failures from the pure v1 contract validator.  These are contract
/// failures, not framework errors, and therefore do not import AVFoundation or
/// UIKit and do not expose raw framework strings to the UI.
enum RecordingContractViolation: Sendable, Equatable {
    case zeroOwnerID
    case zeroRecordingID
    case zeroGeneration
    case invalidDimensions
    case invalidFramesPerSecond
    case zeroPixelFormatFourCC
    case requiredAudioCannotDowngrade
    case invalidAudioPolicy
    case zeroPromotionProjectID
    case terminalOutcomeMissing(RecordingTerminalOutcome)
    case terminalOutcomeDuplicated(RecordingTerminalOutcome)
    case terminalObligationMismatch(RecordingTerminalOutcome)
    case terminalDispositionTargetMismatch(RecordingTerminalOutcome)
    case terminalArtifactRequirementMismatch(RecordingTerminalOutcome)
    case terminalFailureRelationMismatch(RecordingTerminalOutcome)
}

/// Canonical source/state/artifact contract for one recording take.  This is
/// intentionally schema-only: runtime adoption belongs to M7-002…M7-032.
/// Existing M1 lifecycle types remain the state authority; the computed
/// projection below prevents a second transition table from drifting.
struct RecordingContractV1: Sendable, Equatable {
    let owner: RecordingOwnerToken
    let audioPolicy: RecordingAudioPolicy
    let mediaFormat: RecordingQuickTimeMediaFormat
    let trackTransform: RecordingTrackTransformMetadata
    let timebase: RecordingTimebasePolicy
    let promotionTarget: RecordingPromotionTarget
    let terminalDisposition: RecordingTerminalDispositionMatrix

    init(owner: RecordingOwnerToken,
         audioPolicy: RecordingAudioPolicy,
         mediaFormat: RecordingQuickTimeMediaFormat,
         trackTransform: RecordingTrackTransformMetadata,
         timebase: RecordingTimebasePolicy,
         promotionTarget: RecordingPromotionTarget,
         terminalDisposition: RecordingTerminalDispositionMatrix) {
        self.owner = owner
        self.audioPolicy = audioPolicy
        self.mediaFormat = mediaFormat
        self.trackTransform = trackTransform
        self.timebase = timebase
        self.promotionTarget = promotionTarget
        self.terminalDisposition = terminalDisposition
    }

    /// Compatibility aliases keep plan vocabulary readable without creating
    /// duplicate storage or another source of truth.
    var format: RecordingQuickTimeMediaFormat { mediaFormat }
    var audioMode: RecordingAudioMode { audioPolicy.mode }
    var terminalOutcomeMatrix: RecordingTerminalDispositionMatrix {
        terminalDisposition
    }

    /// M1-010 remains the single lifecycle state/transition authority.
    static var lifecycleStates: [RecordingLifecycleState] {
        RecordingLifecycleState.allCases
    }

    static func allowsTransition(from: RecordingLifecycleState,
                                 to: RecordingLifecycleState) -> Bool {
        RecordingLifecycleState.isLegalTransition(from: from, to: to)
    }

    /// Pure validation: the result depends only on immutable contract values;
    /// no filesystem, clock, device, or framework state is consulted.
    func validate() -> [RecordingContractViolation] {
        var violations: [RecordingContractViolation] = []

        if isZeroUUID(owner.ownerID) {
            violations.append(.zeroOwnerID)
        }
        if isZeroUUID(owner.recordingID.rawValue) {
            violations.append(.zeroRecordingID)
        }
        if owner.generation == 0 {
            violations.append(.zeroGeneration)
        }
        if mediaFormat.width <= 0 || mediaFormat.height <= 0 {
            violations.append(.invalidDimensions)
        }
        if mediaFormat.framesPerSecond <= 0 {
            violations.append(.invalidFramesPerSecond)
        }
        if mediaFormat.pixelFormatFourCC == 0 {
            violations.append(.zeroPixelFormatFourCC)
        }

        switch (audioPolicy.mode, audioPolicy.unavailableBehavior) {
        case (.disabled, .notRequested),
             (.disabled, .explicitVideoOnlySelection),
             (.required, .failRecording):
            break
        case (.required, .explicitVideoOnlySelection):
            violations.append(.requiredAudioCannotDowngrade)
        default:
            violations.append(.invalidAudioPolicy)
        }

        if case .sceneProject(let projectID) = promotionTarget,
           isZeroUUID(projectID) {
            violations.append(.zeroPromotionProjectID)
        }

        violations.append(contentsOf: terminalDispositionValidation())
        return violations
    }

    /// Convenience boundary for callers that need a typed throwing check
    /// while keeping `validate()` suitable for table-driven tests.
    func validated() throws -> RecordingContractV1 {
        let violations = validate()
        guard violations.isEmpty else {
            throw RecordingContractValidationError(violations: violations)
        }
        return self
    }

    private func terminalDispositionValidation() -> [RecordingContractViolation] {
        var violations: [RecordingContractViolation] = []
        for outcome in RecordingTerminalOutcome.allCases {
            let matches = terminalDisposition.entries.filter { $0.outcome == outcome }
            if matches.isEmpty {
                violations.append(.terminalOutcomeMissing(outcome))
                continue
            }
            if matches.count > 1 {
                violations.append(.terminalOutcomeDuplicated(outcome))
                continue
            }
            let actual = matches[0]
            let expected = RecordingTerminalDisposition.canonical(
                for: outcome,
                target: promotionTarget
            )
            if actual.obligation != expected.obligation {
                switch outcome {
                case .finalized, .promotedProjectOwned:
                    violations.append(.terminalDispositionTargetMismatch(outcome))
                case .recoverableFailure, .unrecoverableFailure, .cancelledPrecommit:
                    violations.append(.terminalObligationMismatch(outcome))
                }
            }

            if actual.artifactRequirement != expected.artifactRequirement {
                violations.append(.terminalArtifactRequirementMismatch(outcome))
            }
            if !actual.failureRelation.isCompatible(with: expected.failureRelation) {
                violations.append(.terminalFailureRelationMismatch(outcome))
            }
        }
        return violations
    }
}

struct RecordingContractValidationError: Error, Sendable, Equatable {
    let violations: [RecordingContractViolation]
}

private func isZeroUUID(_ value: UUID) -> Bool {
    value == UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}
