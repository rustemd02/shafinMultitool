import CoreVideo
import Foundation

/// Owns one raw-camera take and the small capture-side gate around the shared
/// serialized recorder. State snapshots are synchronous and queue-scoped;
/// video enqueue remains nonblocking for the AR session delegate.
final class SceneRecordingController: @unchecked Sendable {
    typealias RecorderFactory = @Sendable (
        _ configuration: RecordingConfiguration
    ) throws -> any MediaRecording

    private enum Lifecycle: Equatable {
        case idle
        case starting
        case recording
        case stopping
        case released

        /// M1-010: canonical lifecycle projection. The controller keeps its
        /// coarser vocabulary; observers and tests read the shared machine.
        var canonical: RecordingLifecycleState {
            switch self {
            case .idle: .idle
            case .starting: .starting
            case .recording: .recording
            case .stopping: .stopping
            case .released: .released
            }
        }
    }

    private enum StartDecision {
        case alreadyRecording
        case wait(Task<Void, Error>)
        case failure(RecorderFailure)
    }

    private enum StopDecision {
        case result(RecordingStopResult?)
        case waitForStart(Task<Void, Error>)
        case waitForStop(Task<RecordingStopResult, Never>)
    }

    private enum ReleaseDecision {
        case result(RecordingStopResult?)
        case stop
        case waitForStart(Task<Void, Error>)
        case waitForStop(Task<RecordingStopResult, Never>)
        case release(recorder: (any MediaRecording)?, result: RecordingStopResult?)
    }

    private let stateQueue = DispatchQueue(
        label: "com.shafinMultitool.sceneRecordingController",
        qos: .userInitiated
    )
    private let artifactStore: RecordingArtifactStore
    private let makeRecorder: RecorderFactory
    /// M7-008: mandatory start preconditions are validated before any
    /// recorder is created or the lifecycle leaves idle.
    private let preflight: any RecordingStartPreflighting

    // Every property below is accessed through `withState`; no await occurs
    // inside that synchronous critical section.
    private var lifecycle: Lifecycle = .idle
    private var recorder: (any MediaRecording)?
    private var acceptingFrameFence: RecordingFrameFence?
    private var sourceOwnerID: UUID
    private var sourceGenerationStorage: UInt64 = 0
    private var activeSourceOwnerToken: RecordingOwnerToken?
    private var lastAcceptedTimestamp: TimeInterval?
    private var latestVideoPayload: AppleRecordingVideoFramePayload?
    private var latestTimestamp: TimeInterval?
    private var latestVideoOwnerID: UUID?
    private var latestVideoGeneration: UInt64?
    private var hasExplicitSourceOwnerBinding = false
    private var lastStopResult: RecordingStopResult?
    private var startTask: Task<Void, Error>?
    private var stopTask: Task<RecordingStopResult, Never>?
    private var releaseTask: Task<RecordingStopResult?, Never>?

    init(artifactStore: RecordingArtifactStore,
         sourceOwnerID: UUID = UUID(),
         preflight: (any RecordingStartPreflighting)? = nil,
         makeRecorder: @escaping RecorderFactory) {
        self.artifactStore = artifactStore
        self.sourceOwnerID = sourceOwnerID
        // The unit-seam default is deliberately availability-neutral so
        // tests never depend on the host's real privacy/audio-session state;
        // production wiring (convenience init) supplies the real checkers.
        self.preflight = preflight ?? StandardRecordingStartPreflight(
            microphonePermission: AlwaysAvailableMicrophonePermissionChecker(),
            audioSession: AlwaysAvailableAudioSessionChecker()
        )
        self.makeRecorder = makeRecorder
    }

    /// Production wiring for a fresh AVAssetWriter + optional capture-audio
    /// driver. Permission is intentionally owned by the ViewModel before this
    /// initializer is used for a required-audio take; the preflight adds a
    /// read-only last-line defense (denied permission, interrupted audio
    /// session, disk budget) before any writer is created.
    convenience init(artifactStore: RecordingArtifactStore) {
        let store = artifactStore
        self.init(
            artifactStore: artifactStore,
            preflight: StandardRecordingStartPreflight(
                diskBudget: { context in
                    try store.diskBudgetEstimate(
                        width: context.width,
                        height: context.height,
                        fps: context.fps,
                        codec: context.codec,
                        audioMode: context.audioMode,
                        durationLimitSeconds: context.durationLimitSeconds
                    )
                }
            )
        ) { configuration in
            SerializedMediaRecorder(
                writerFactory: AVAssetWriterRecordingWriterFactory(),
                audioDriverFactory: configuration.audioMode == .required
                    ? AVCaptureAudioRecordingDriverFactory()
                    : nil
            )
        }
    }

    /// Project persistence owns the reference; the controller only forwards
    /// artifact-store operations so UI code never handles filesystem paths.
    func promoteFinalizedArtifact(
        _ artifact: RecordingArtifact,
        projectID: UUID
    ) throws -> SceneRecordingReference {
        try artifactStore.promoteFinalizedArtifact(artifact, projectID: projectID)
    }

    func resolve(_ reference: SceneRecordingReference) -> RecordingArtifact? {
        artifactStore.resolveArtifact(reference)
    }

    /// Synchronous state access keeps queue/lock ownership out of async
    /// contexts and makes it impossible to hold state ownership across await.
    /// M1-010: lifecycle mutations are validated against the canonical
    /// transition table (assert is stripped from release builds).
    @inline(__always)
    private func withState<T>(_ body: () -> T) -> T {
        stateQueue.sync {
            let previousLifecycle = lifecycle
            let result = body()
            if lifecycle != previousLifecycle {
                assert(
                    RecordingLifecycleState.isLegalTransition(
                        from: previousLifecycle.canonical,
                        to: lifecycle.canonical
                    ),
                    "SceneRecordingController illegal lifecycle transition \(previousLifecycle) -> \(lifecycle)"
                )
            }
            return result
        }
    }

    /// M1-010 canonical lifecycle projection of the current controller state.
    var canonicalLifecycleState: RecordingLifecycleState {
        withState { lifecycle.canonical }
    }

    var frameFence: RecordingFrameFence? {
        withState { acceptingFrameFence }
    }

    var recordingSourceToken: RecordingOwnerToken? {
        withState { activeSourceOwnerToken }
    }

    var recordingSourceOwnerID: UUID {
        withState { sourceOwnerID }
    }

    /// ARSceneContainer supplies its coordinator identity before the first
    /// take. Changing an owner while a take is active is rejected so stale
    /// callbacks cannot inherit a newer producer's token.
    @discardableResult
    func setRecordingSourceOwnerID(_ ownerID: UUID) -> Bool {
        withState {
            guard ownerID != UUID(uuidString: "00000000-0000-0000-0000-000000000000")! else { return false }
            if sourceOwnerID == ownerID {
                guard lifecycle != .released else { return false }
                hasExplicitSourceOwnerBinding = true
                return true
            }
            guard activeSourceOwnerToken == nil,
                  lifecycle == .idle else { return false }
            sourceOwnerID = ownerID
            sourceGenerationStorage = 0
            hasExplicitSourceOwnerBinding = true
            clearCachedVideo()
            return true
        }
    }

    var isAcceptingFrames: Bool {
        withState { acceptingFrameFence != nil }
    }

    /// Dimensions of the latest raw AR buffer. This is a source fact used by
    /// the capture-setting projection; it never describes a requested scaler
    /// preset.
    var currentVideoDimensions: (width: Int, height: Int)? {
        withState {
            guard let latestVideoPayload else { return nil }
            return (
                width: CVPixelBufferGetWidth(latestVideoPayload.pixelBuffer),
                height: CVPixelBufferGetHeight(latestVideoPayload.pixelBuffer)
            )
        }
    }

    /// Caches the latest raw camera image even while idle, so an explicit REC
    /// tap can prepare a writer from the current AR frame without dispatching a
    /// MainActor task for every frame.
    func enqueueVideo(_ pixelBuffer: CVPixelBuffer,
                      at timestamp: TimeInterval,
                      ownerID: UUID? = nil,
                      ownerToken: RecordingOwnerToken? = nil) {
        guard timestamp.isFinite else { return }
        let payload = AppleRecordingVideoFramePayload(pixelBuffer: pixelBuffer)
        let submission: (any MediaRecording, RecordingVideoFrame)? = withState {
            // The owner check and cache/append mutation share this stateQueue
            // transaction. A late producer therefore cannot re-seed a cache
            // after another owner has replaced the source while this caller
            // was reading the coordinator's snapshot.
            guard ownerID == sourceOwnerID
                    || (!hasExplicitSourceOwnerBinding && ownerID == nil) else { return nil }

            // Idle frames are the only unclaimed source samples allowed to
            // seed the next take. Once a take has a token, stale/untagged
            // producers cannot even replace that seed buffer.
            switch lifecycle {
            case .idle:
                guard ownerToken == nil else { return nil }
            case .recording:
                guard let activeSourceOwnerToken,
                      ownerToken == activeSourceOwnerToken,
                      ownerID == activeSourceOwnerToken.ownerID
                        || (!hasExplicitSourceOwnerBinding && ownerID == nil) else { return nil }
            case .starting, .stopping, .released:
                return nil
            }

            latestVideoPayload = payload
            latestTimestamp = timestamp
            latestVideoOwnerID = ownerID ?? sourceOwnerID
            latestVideoGeneration = ownerToken?.generation ?? nextSourceGenerationValue()

            guard let fence = acceptingFrameFence,
                  let activeSourceOwnerToken,
                  ownerToken == activeSourceOwnerToken,
                  let recorder,
                  lifecycle == .recording,
                  shouldAccept(timestamp: timestamp) else {
                return nil
            }

            lastAcceptedTimestamp = timestamp
            return (
                recorder,
                RecordingVideoFrame(
                    fence: fence,
                    timestamp: timestamp,
                    payload: payload
                )
            )
        }

        // SerializedMediaRecorder owns the append queue; this call only
        // submits work and never waits for writer availability.
        if let submission {
            submission.0.enqueueVideo(submission.1)
        }
    }

    /// Starts a fresh take. When no explicit buffer is supplied, the most
    /// recent buffer observed by `enqueueVideo` is used. Dimensions always
    /// come from that actual CVPixelBuffer. `videoCodec` defaults to the v1
    /// baseline; `trackTransform` defaults to the identity metadata of takes
    /// recorded before orientation wiring exists.
    func start(firstPixelBuffer: CVPixelBuffer? = nil,
               requestedFPS: Int,
               audioMode: RecordingAudioMode,
               timestamp: TimeInterval? = nil,
               videoCodec: RecordingQuickTimeCodec = .h264,
               trackTransform: RecordingTrackTransformMetadata? = nil) async throws {
        let explicitPayload = firstPixelBuffer.map(AppleRecordingVideoFramePayload.init(pixelBuffer:))
        let decision: StartDecision = withState {
            switch lifecycle {
            case .recording:
                return .alreadyRecording
            case .starting:
                guard let startTask else {
                    return .failure(.invalidTransition)
                }
                return .wait(startTask)
            case .stopping, .released:
                return .failure(.invalidTransition)
            case .idle:
                guard let initialPayload = explicitPayload ?? latestVideoPayload else {
                    return .failure(.noVideoFrames)
                }

                if explicitPayload == nil {
                    guard latestVideoOwnerID == sourceOwnerID,
                          latestVideoGeneration == nextSourceGenerationValue() else {
                        return .failure(.noVideoFrames)
                    }
                }

                let initialTimestamp = timestamp ?? latestTimestamp ?? 0
                guard initialTimestamp.isFinite else {
                    return .failure(.writerInputRejected)
                }

                lifecycle = .starting
                let task: Task<Void, Error> = Task { [self] in
                    try await performStart(
                        initialPayload: initialPayload,
                        initialTimestamp: initialTimestamp,
                        requestedFPS: requestedFPS,
                        audioMode: audioMode,
                        videoCodec: videoCodec,
                        trackTransform: trackTransform
                    )
                }
                startTask = task
                return .wait(task)
            }
        }

        switch decision {
        case .alreadyRecording:
            return
        case .failure(let failure):
            throw failure
        case .wait(let task):
            try await task.value
        }
    }

    /// Stops the current take and returns the writer's exact result. The
    /// accepting fence is cleared before awaiting finalization, so already
    /// queued frames are rejected by the recorder's stale-generation check.
    func stop(reason: RecordingStopReason) async -> RecordingStopResult? {
        let decision: StopDecision = withState {
            switch lifecycle {
            case .idle, .released:
                return .result(lastStopResult)
            case .starting:
                guard let startTask else {
                    return .result(lastStopResult)
                }
                return .waitForStart(startTask)
            case .stopping:
                guard let stopTask else {
                    return .result(lastStopResult)
                }
                return .waitForStop(stopTask)
            case .recording:
                guard let recorder else {
                    acceptingFrameFence = nil
                    activeSourceOwnerToken = nil
                    clearCachedVideo()
                    lifecycle = .idle
                    return .result(nil)
                }

                acceptingFrameFence = nil
                lastAcceptedTimestamp = nil
                lifecycle = .stopping
                let task: Task<RecordingStopResult, Never> = Task { [self] in
                    let result = await recorder.stop(reason: reason)
                    _ = await recorder.releaseAndWait()
                    if let sourceToken = withState({ activeSourceOwnerToken }) {
                        _ = await recorder.releaseRecordingSource(sourceToken)
                    }

                    withState {
                        self.recorder = nil
                        self.activeSourceOwnerToken = nil
                        self.clearCachedVideo()
                        self.lifecycle = .idle
                        self.stopTask = nil
                        self.lastStopResult = result
                    }
                    return result
                }
                stopTask = task
                return .waitForStop(task)
            }
        }

        switch decision {
        case .result(let result):
            return result
        case .waitForStart(let task):
            _ = try? await task.value
            return await stop(reason: reason)
        case .waitForStop(let task):
            return await task.value
        }
    }

    /// Joins an in-flight start/stop and releases the underlying recorder.
    /// Repeated callers share one task and receive the same cached result.
    func releaseAndWait() async -> RecordingStopResult? {
        let task: Task<RecordingStopResult?, Never> = withState {
            if let releaseTask {
                return releaseTask
            }

            let task: Task<RecordingStopResult?, Never> = Task { [self] in
                await performRelease()
            }
            releaseTask = task
            return task
        }
        return await task.value
    }

    private func performStart(initialPayload: AppleRecordingVideoFramePayload,
                              initialTimestamp: TimeInterval,
                              requestedFPS: Int,
                              audioMode: RecordingAudioMode,
                              videoCodec: RecordingQuickTimeCodec,
                              trackTransform: RecordingTrackTransformMetadata?) async throws {
        do {
            let width = CVPixelBufferGetWidth(initialPayload.pixelBuffer)
            let height = CVPixelBufferGetHeight(initialPayload.pixelBuffer)
            guard width > 0, height > 0 else {
                throw RecorderFailure.writerInputRejected
            }

            // M7-008: mandatory preconditions gate the start before any
            // recorder is created, any output URL is allocated, and the
            // lifecycle leaves its between-takes idle state.
            if let preflightFailure = await preflight.validate(RecordingStartPreflightContext(
                width: width,
                height: height,
                fps: max(1, requestedFPS),
                codec: videoCodec,
                pixelFormatFourCC: CVPixelBufferGetPixelFormatType(initialPayload.pixelBuffer),
                audioMode: audioMode
            )) {
                throw preflightFailure
            }

            let outputURL = try artifactStore.makePendingURL()
            // M7-005: the writer is built from the active capture format —
            // dimensions come from the actual buffer and the pixel format from
            // that buffer's native FourCC, not from a requested preset.
            let configuration = RecordingConfiguration(
                id: RecordingID(rawValue: UUID()),
                outputURL: outputURL,
                width: width,
                height: height,
                fps: max(1, requestedFPS),
                audioMode: audioMode,
                pixelFormatFourCC: CVPixelBufferGetPixelFormatType(initialPayload.pixelBuffer),
                videoCodec: videoCodec,
                trackTransform: trackTransform
            )
            let sourceToken = RecordingOwnerToken(
                source: .arWorkspace,
                ownerID: sourceOwnerID,
                recordingID: configuration.id,
                generation: nextSourceGeneration()
            )
            var newRecorder: (any MediaRecording)?
            var claimedSourceToken: RecordingOwnerToken?
            do {
                let preparedRecorder = try makeRecorder(configuration)
                newRecorder = preparedRecorder
                guard await preparedRecorder.claimRecordingSource(sourceToken) else {
                    throw RecorderFailure.sourceClaimRejected
                }
                claimedSourceToken = sourceToken
                try await preparedRecorder.prepare(configuration)
                try await preparedRecorder.start()
            } catch let failure as RecorderFailure {
                if let newRecorder {
                    _ = await newRecorder.releaseAndWait()
                    if let claimedSourceToken {
                        _ = await newRecorder.releaseRecordingSource(claimedSourceToken)
                    }
                }
                throw failure
            } catch {
                if let newRecorder {
                    _ = await newRecorder.releaseAndWait()
                    if let claimedSourceToken {
                        _ = await newRecorder.releaseRecordingSource(claimedSourceToken)
                    }
                }
                throw RecorderFailure.writerCreationFailed
            }

            guard let newRecorder else {
                throw RecorderFailure.writerCreationFailed
            }
            let snapshot = await newRecorder.stateSnapshot()
            guard snapshot.state == .recording,
                  snapshot.generation == sourceToken.generation,
                  snapshot.ownerToken == sourceToken else {
                _ = await newRecorder.releaseAndWait()
                _ = await newRecorder.releaseRecordingSource(sourceToken)
                throw RecorderFailure.invalidTransition
            }
            let fence = RecordingFrameFence(
                recordingID: configuration.id,
                generation: snapshot.generation,
                ownerToken: sourceToken
            )

            // Submit the source frame while the lifecycle is still `.starting`.
            // Stop/release callers therefore join this start task instead of
            // finalizing a take before its first frame reaches the recorder.
            newRecorder.enqueueVideo(RecordingVideoFrame(
                fence: fence,
                timestamp: initialTimestamp,
                payload: initialPayload
            ))

            let committed = withState { () -> Bool in
                guard lifecycle == .starting else { return false }
                recorder = newRecorder
                acceptingFrameFence = fence
                activeSourceOwnerToken = sourceToken
                lastAcceptedTimestamp = initialTimestamp
                lastStopResult = nil
                lifecycle = .recording
                startTask = nil
                return true
            }
            guard committed else {
                _ = await newRecorder.releaseAndWait()
                _ = await newRecorder.releaseRecordingSource(sourceToken)
                throw RecorderFailure.invalidTransition
            }
        } catch {
            withState {
                if lifecycle == .starting {
                    lifecycle = .idle
                    startTask = nil
                }
            }
            throw (error as? RecorderFailure) ?? .writerCreationFailed
        }
    }

    private func performRelease() async -> RecordingStopResult? {
        while true {
            let decision: ReleaseDecision = withState {
                switch lifecycle {
                case .released:
                    return .result(lastStopResult)
                case .starting:
                    guard let startTask else {
                        return .result(lastStopResult)
                    }
                    return .waitForStart(startTask)
                case .recording:
                    return .stop
                case .stopping:
                    guard let stopTask else {
                        return .result(lastStopResult)
                    }
                    return .waitForStop(stopTask)
                case .idle:
                    let recorder = self.recorder
                    let result = lastStopResult
                    self.recorder = nil
                    acceptingFrameFence = nil
                    self.clearCachedVideo()
                    lifecycle = .released
                    return .release(recorder: recorder, result: result)
                }
            }

            switch decision {
            case .result(let result):
                return result
            case .stop:
                _ = await stop(reason: .routeExit)
            case .waitForStart(let task):
                _ = try? await task.value
            case .waitForStop(let task):
                _ = await task.value
            case .release(let recorder, let result):
                if let recorder {
                    _ = await recorder.releaseAndWait()
                }
                return result
            }
        }
    }

    private func shouldAccept(timestamp: TimeInterval) -> Bool {
        guard let lastAcceptedTimestamp else { return true }
        return timestamp > lastAcceptedTimestamp
    }

    private func clearCachedVideo() {
        latestVideoPayload = nil
        latestTimestamp = nil
        latestVideoOwnerID = nil
        latestVideoGeneration = nil
    }

    private func nextSourceGenerationValue() -> UInt64 {
        sourceGenerationStorage == .max ? 1 : sourceGenerationStorage &+ 1
    }

    private func nextSourceGeneration() -> UInt64 {
        withState {
            sourceGenerationStorage = nextSourceGenerationValue()
            return sourceGenerationStorage
        }
    }
}
