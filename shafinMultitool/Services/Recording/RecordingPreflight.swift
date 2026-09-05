import AVFoundation
import Foundation

/// M7-008: the facts a start request is validated against. Everything is a
/// plain value so a fixture can construct a context without a live capture.
struct RecordingStartPreflightContext: Sendable, Equatable {
    let width: Int
    let height: Int
    let fps: Int
    let codec: RecordingQuickTimeCodec
    let pixelFormatFourCC: UInt32?
    let audioMode: RecordingAudioMode
    /// Conservative duration budget used by the disk estimate.
    let durationLimitSeconds: TimeInterval

    init(width: Int,
         height: Int,
         fps: Int,
         codec: RecordingQuickTimeCodec,
         pixelFormatFourCC: UInt32? = nil,
         audioMode: RecordingAudioMode,
         durationLimitSeconds: TimeInterval
             = RecordingDiskBudgetModel.defaultDurationLimitSeconds) {
        self.width = width
        self.height = height
        self.fps = fps
        self.codec = codec
        self.pixelFormatFourCC = pixelFormatFourCC
        self.audioMode = audioMode
        self.durationLimitSeconds = durationLimitSeconds
    }
}

/// M7-008: validates the mandatory preconditions of one start request before
/// the recording UI enters its recording state. A `nil` verdict means "all
/// mandatory preconditions hold"; otherwise the typed failure is localized
/// and recoverable at the caller. Validation is read-only: it never mutates
/// the audio session, permissions, or the filesystem.
protocol RecordingStartPreflighting: Sendable {
    func validate(_ context: RecordingStartPreflightContext) async -> RecorderFailure?
}

/// Read-only microphone posture. The production check reads the system
/// permission without prompting; the prompt/request decision stays owned by
/// the contextual permission flow (M7-004) before start is ever attempted.
protocol RecordingMicrophonePermissionChecking: Sendable {
    /// Returns true when a sound-required take may start.
    func microphoneAvailable() async -> Bool
}

/// Reads `AVAudioApplication`'s permission without triggering a prompt.
struct SystemMicrophonePermissionChecker: RecordingMicrophonePermissionChecking {
    func microphoneAvailable() async -> Bool {
        let permission = AVAudioApplication.shared.recordPermission
        return permission == .granted || permission == .undetermined
    }
}

/// Read-only audio-session posture for start decisions.
protocol RecordingAudioSessionChecking: Sendable {
    func audioSessionAvailable() async -> Bool
}

/// Production check against the serialized coordinator: an interrupted or
/// missing lease state must not host a new sound-required take.
struct CoordinatorAudioSessionChecker: RecordingAudioSessionChecking {
    func audioSessionAvailable() async -> Bool {
        await AudioSessionCoordinator.shared.state != .interrupted
    }
}

/// M7-008 production preflight. Order is deterministic and documented:
/// format → codec → pixel format → disk budget → microphone → audio session.
/// The first failing precondition wins.
struct StandardRecordingStartPreflight: RecordingStartPreflighting {
    let codecSupport: any RecordingCodecSupportChecking
    let microphonePermission: any RecordingMicrophonePermissionChecking
    let audioSession: any RecordingAudioSessionChecking
    let diskBudget: (@Sendable (RecordingStartPreflightContext) throws -> RecordingDiskBudgetEstimate)?

    init(codecSupport: any RecordingCodecSupportChecking = AppleRecordingCodecSupportChecker(),
         microphonePermission: any RecordingMicrophonePermissionChecking = SystemMicrophonePermissionChecker(),
         audioSession: any RecordingAudioSessionChecking = CoordinatorAudioSessionChecker(),
         diskBudget: (@Sendable (RecordingStartPreflightContext) throws -> RecordingDiskBudgetEstimate)? = nil) {
        self.codecSupport = codecSupport
        self.microphonePermission = microphonePermission
        self.audioSession = audioSession
        // Production default binds the artifact store lazily; tests inject a
        // fake capacity closure. A nil disk check would silently skip a
        // mandatory precondition, so the convenience factory below is the
        // only way to build the production instance with a store.
        self.diskBudget = diskBudget
    }

    /// Production instance wired to the recording artifact store's budget
    /// query.
    static func standard(diskBudget: @escaping (@Sendable (RecordingStartPreflightContext) throws -> RecordingDiskBudgetEstimate))
        -> StandardRecordingStartPreflight {
        StandardRecordingStartPreflight(diskBudget: diskBudget)
    }

    func validate(_ context: RecordingStartPreflightContext) async -> RecorderFailure? {
        guard context.width > 0, context.height > 0, context.fps > 0 else {
            return .writerInputRejected
        }
        guard codecSupport.isSupported(context.codec) else {
            return .writerInputRejected
        }
        if let pixelFormatFourCC = context.pixelFormatFourCC, pixelFormatFourCC == 0 {
            return .writerInputRejected
        }
        if let diskBudget {
            do {
                let estimate = try diskBudget(context)
                guard estimate.isSatisfied else {
                    return .insufficientStorage
                }
            } catch {
                return .insufficientStorage
            }
        }
        if context.audioMode == .required {
            guard await microphonePermission.microphoneAvailable() else {
                return .microphoneDenied
            }
            guard await audioSession.audioSessionAvailable() else {
                return .audioSessionUnavailable
            }
        }
        return nil
    }
}
