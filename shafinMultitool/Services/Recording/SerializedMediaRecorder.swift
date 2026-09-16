import Foundation

/// A queue-confined recorder core. AVFoundation adapters can implement the
/// contracts in `RecorderContracts.swift` without becoming part of this state
/// machine or of the route lifecycle.
///
/// `@unchecked Sendable` is limited to the owner object because Swift's
/// compiler cannot infer confinement through a private DispatchQueue. Every
/// mutable writer, audio, timing and state reference below is read or mutated
/// only from `queue`; frame submission merely enqueues work onto that queue.
final class SerializedMediaRecorder: MediaRecording, @unchecked Sendable {
    /// Internal test/diagnostic identity for proving that writer callbacks run
    /// on this recorder's serial queue. It has no production behavior.
    static let queueSpecificKey = DispatchSpecificKey<UUID>()

    private let queue: DispatchQueue
    private let writerFactory: any RecordingWriterFactory
    private let audioDriverFactory: (any RecordingAudioDriverFactory)?
    private let outputChecker: any RecordingOutputChecking
    private let frameAdmission: RecordingFrameAdmissionGate
    private let maxConsecutiveDroppedFrames: Int
    private let finalizationTimeout: TimeInterval
    /// M7-030: bounded redacted diagnostics sink. Called only from the
    /// recorder queue; the sink is responsible for its own thread safety.
    private let diagnostics: (any RecordingDiagnosticsEmitting)?

    // All properties below are queue-confined. Do not access them from a
    // callback or caller without first dispatching to `queue`.
    private var stateStorage: RecorderState = .idle
    private var currentConfiguration: RecordingConfiguration?
    private var writer: (any RecordingWriter)?
    private var audioDriver: (any RecordingAudioDriver)?
    private var audioStarted = false
    private var activeGeneration: UInt64 = 0
    private var activeSourceOwnerToken: RecordingOwnerToken?
    private var latestSourceGeneration: UInt64 = 0
    private var acceptingFrames = false
    /// M7-006: the single monotonic media timebase of the active take. Video
    /// and audio admission, derived duration and the sync report all read this
    /// structure; no other timestamp state exists.
    private var timebase = RecordingMediaTimebase()
    private var pendingFailure: RecorderFailure?
    private var finishInFlight = false
    private var releaseRequested = false
    private var lastStopReason: RecordingStopReason?
    private var lastStopResult: RecordingStopResult?
    private var stopWaiters: [CheckedContinuation<RecordingStopResult, Never>] = []
    private var releaseWaiters: [CheckedContinuation<RecordingStopResult?, Never>] = []

    init(writerFactory: any RecordingWriterFactory,
         audioDriverFactory: (any RecordingAudioDriverFactory)? = nil,
         outputChecker: any RecordingOutputChecking = LocalRecordingOutputChecker(),
         queueLabel: String = "com.shafinMultitool.serializedMediaRecorder",
         maxConsecutiveDroppedFrames: Int = 900,
         maxQueuedVideoFrames: Int = 4,
         maxQueuedAudioFrames: Int = 16,
         finalizationTimeout: TimeInterval = 10,
         diagnostics: (any RecordingDiagnosticsEmitting)? = nil) {
        self.writerFactory = writerFactory
        self.audioDriverFactory = audioDriverFactory
        self.outputChecker = outputChecker
        self.frameAdmission = RecordingFrameAdmissionGate(
            videoCapacity: maxQueuedVideoFrames, audioCapacity: maxQueuedAudioFrames
        )
        self.queue = DispatchQueue(label: queueLabel, qos: .userInitiated)
        self.queue.setSpecific(key: Self.queueSpecificKey, value: UUID())
        // M7-011: ≈15 s of continuous writer backpressure at 60 fps before
        // the explicit failure policy fires. Configurable for fixtures.
        self.maxConsecutiveDroppedFrames = max(1, maxConsecutiveDroppedFrames)
        // M7-013: the writer must deliver its finish callback within this
        // bound or the take fails typed and its resources are closed.
        self.finalizationTimeout = max(0.05, finalizationTimeout)
        // M7-030: bounded redacted diagnostics sink (nil = silent).
        self.diagnostics = diagnostics
    }

    var state: RecorderState {
        get async {
            await stateSnapshot().state
        }
    }

    /// M7-006: bounded timebase report for diagnostics and the A/V sync
    /// measurement. The report is a queue-consistent snapshot; it never
    /// contains payloads, paths, or user content.
    func timebaseReport() async -> RecordingTimebaseReport {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                drainSubmissionStatisticsOnQueue()
                continuation.resume(returning: timebase.report())
            }
        }
    }

    /// M7-016: audio/video synchronization measurement over the session
    /// timeline (first/last PTS deltas and monotonicity faults). The release
    /// criterion is absolute sync error ≤ 80 ms at start and end with no
    /// monotonicity fault; physical content-marker validation stays external.
    func syncReport() async -> RecordingSyncReport {
        let report = await timebaseReport()
        return RecordingMediaTimebase.syncReport(from: report)
    }

    func stateSnapshot() async -> RecorderStateSnapshot {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                drainSubmissionStatisticsOnQueue()
                continuation.resume(returning: RecorderStateSnapshot(
                    state: stateStorage,
                    recordingID: currentConfiguration?.id,
                    generation: activeGeneration,
                    ownerToken: activeSourceOwnerToken,
                    droppedVideoCount: timebase.droppedVideoCount,
                    droppedAudioCount: timebase.droppedAudioCount
                ))
            }
        }
    }

    func prepare(_ configuration: RecordingConfiguration) async throws {
        let admissionGeneration = frameAdmission.preparationGeneration
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    try prepareOnQueue(configuration, admissionGeneration: admissionGeneration)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    try startOnQueue()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop(reason: RecordingStopReason) async -> RecordingStopResult {
        frameAdmission.close()
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                handleStopOnQueue(reason: reason, continuation: continuation)
            }
        }
    }

    func releaseAndWait() async -> RecordingStopResult? {
        frameAdmission.close()
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                handleReleaseOnQueue(continuation)
            }
        }
    }

    func claimRecordingSource(_ ownerToken: RecordingOwnerToken) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: claimRecordingSourceOnQueue(ownerToken))
            }
        }
    }

    func releaseRecordingSource(_ ownerToken: RecordingOwnerToken) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: releaseRecordingSourceOnQueue(ownerToken))
            }
        }
    }

    func enqueueVideo(_ frame: RecordingVideoFrame) {
        _ = frameAdmission.reserveVideo(frame) {
            queue.async { [self] in
                defer {
                    frameAdmission.release(.video)
                    drainSubmissionStatisticsOnQueue()
                }
                drainSubmissionStatisticsOnQueue()
                appendVideoOnQueue(frame)
            }
        }
    }

    func enqueueAudio(_ frame: RecordingAudioFrame) {
        _ = frameAdmission.reserveAudio(frame) {
            queue.async { [self] in
                defer {
                    frameAdmission.release(.audio)
                    drainSubmissionStatisticsOnQueue()
                }
                drainSubmissionStatisticsOnQueue()
                appendAudioOnQueue(frame)
            }
        }
    }

    // MARK: - Source ownership

    private func claimRecordingSourceOnQueue(_ ownerToken: RecordingOwnerToken) -> Bool {
        guard ownerToken.isValid,
              ownerToken.generation > latestSourceGeneration else {
            return activeSourceOwnerToken == ownerToken
        }

        guard activeSourceOwnerToken == nil,
              stateStorage == .idle || stateStorage == .prepared else {
            return false
        }

        if let currentConfiguration {
            guard stateStorage == .prepared,
                  currentConfiguration.id == ownerToken.recordingID,
                  !acceptingFrames else {
                return false
            }
            // A source may be claimed either before prepare (the controller's
            // path) or after prepare (legacy/adaptor callers). In both cases
            // the claim owns the recorder generation before frames are
            // admitted.
            activeGeneration = ownerToken.generation
        }

        activeSourceOwnerToken = ownerToken
        latestSourceGeneration = ownerToken.generation
        return true
    }

    private func releaseRecordingSourceOnQueue(_ ownerToken: RecordingOwnerToken) -> Bool {
        guard activeSourceOwnerToken == ownerToken,
              stateStorage == .idle
                || stateStorage == .finished
                || stateStorage == .failed
                || stateStorage == .released,
              !finishInFlight else {
            return false
        }
        activeSourceOwnerToken = nil
        return true
    }

    // MARK: - Prepare/start

    private func prepareOnQueue(_ configuration: RecordingConfiguration,
                                admissionGeneration: UInt64) throws {
        if stateStorage == .prepared,
           let currentConfiguration,
           currentConfiguration == configuration {
            return
        }

        guard stateStorage == .idle else {
            throw RecorderFailure.invalidTransition
        }
        guard frameAdmission.prepare(expectedGeneration: admissionGeneration) else {
            throw RecorderFailure.invalidTransition
        }

        guard !outputChecker.exists(at: configuration.outputURL) else {
            throw RecorderFailure.outputAlreadyExists
        }

        if let activeSourceOwnerToken {
            guard activeSourceOwnerToken.recordingID == configuration.id else {
                throw RecorderFailure.invalidTransition
            }
        }

        let newWriter: any RecordingWriter
        do {
            newWriter = try writerFactory.makeWriter(for: configuration)
        } catch let error as RecordingWriterError {
            // M7-005: input rejections (including an unsupported codec or
            // pixel format) are configuration failures the caller can fix;
            // anything else is a writer-creation fault.
            if error == .inputRejected || error == .unsupportedVideoCodec {
                throw RecorderFailure.writerInputRejected
            }
            throw RecorderFailure.writerCreationFailed
        } catch {
            throw RecorderFailure.writerCreationFailed
        }

        currentConfiguration = configuration
        writer = newWriter
        audioDriver = nil
        audioStarted = false
        timebase = RecordingMediaTimebase()
        pendingFailure = nil
        finishInFlight = false
        releaseRequested = false
        lastStopReason = nil
        lastStopResult = nil
        if let activeSourceOwnerToken {
            activeGeneration = activeSourceOwnerToken.generation
        } else {
            advanceGenerationOnQueue()
        }
        acceptingFrames = false
        setStateOnQueue(.prepared)
    }

    private func startOnQueue() throws {
        if stateStorage == .recording {
            return
        }

        guard stateStorage == .prepared,
              let configuration = currentConfiguration,
              let preparedWriter = writer else {
            throw RecorderFailure.invalidTransition
        }

        var preparedAudioDriver: (any RecordingAudioDriver)?
        if configuration.audioMode == .required {
            guard let audioDriverFactory else {
                failStartOnQueue(.audioUnavailable, writer: preparedWriter, audioDriver: nil)
                throw RecorderFailure.audioUnavailable
            }

            do {
                preparedAudioDriver = try audioDriverFactory.makeAudioDriver(for: configuration)
            } catch {
                failStartOnQueue(.audioUnavailable, writer: preparedWriter, audioDriver: nil)
                throw RecorderFailure.audioUnavailable
            }
        }

        guard preparedWriter.start() else {
            failStartOnQueue(.writerStartFailed,
                             writer: preparedWriter,
                             audioDriver: preparedAudioDriver)
            throw RecorderFailure.writerStartFailed
        }

        let frameFence = RecordingFrameFence(
            recordingID: configuration.id,
            generation: activeGeneration,
            ownerToken: activeSourceOwnerToken
        )

        guard frameAdmission.open(fence: frameFence, audioEnabled: configuration.audioMode == .required) else {
            failStartOnQueue(.invalidTransition, writer: preparedWriter, audioDriver: preparedAudioDriver)
            throw RecorderFailure.invalidTransition
        }

        if let preparedAudioDriver {
            let frameHandler: RecordingAudioFrameHandler = { [weak self] timestamp, payload in
                self?.enqueueAudio(RecordingAudioFrame(
                    fence: frameFence,
                    timestamp: timestamp,
                    payload: payload
                ))
            }
            guard preparedAudioDriver.start(onFrame: frameHandler) else {
                failStartOnQueue(.audioStartFailed,
                                 writer: preparedWriter,
                                 audioDriver: preparedAudioDriver)
                throw RecorderFailure.audioStartFailed
            }
            audioDriver = preparedAudioDriver
            audioStarted = true
        }

        pendingFailure = nil
        acceptingFrames = true
        setStateOnQueue(.recording)

        // M7-030: thermal posture is part of the bounded take diagnostics.
        diagnostics?.emit(
            .thermal(state: Self.thermalStateName(ProcessInfo.processInfo.thermalState)),
            recordingID: configuration.id.rawValue
        )
    }

#if DEBUG
    var frameSubmissionOpenForTesting: Bool { frameAdmission.isOpenForTesting }

    static func thermalStateNameForTesting(_ state: ProcessInfo.ThermalState) -> String {
        thermalStateName(state)
    }
#endif

    private static func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    private func failStartOnQueue(_ failure: RecorderFailure,
                                  writer failedWriter: any RecordingWriter,
                                  audioDriver failedAudioDriver: (any RecordingAudioDriver)?) {
        frameAdmission.close()
        failedAudioDriver?.stop()
        failedWriter.discard()
        writer = nil
        audioDriver = nil
        audioStarted = false
        acceptingFrames = false
        advanceGenerationOnQueue()
        pendingFailure = failure
        setStateOnQueue(.failed)
    }

    // MARK: - Frame queue

    /// Fold bounded, payload-free admission counters into the existing media
    /// timeline. Overflow uses the same explicit loss policy as native writer
    /// backpressure; accepted frames retain their real host-clock timestamps.
    private func drainSubmissionStatisticsOnQueue() {
        let counts = frameAdmission.drainStatistics()
        timebase.recordAdmissionRejection(.inactive, stream: .video, count: counts.inactiveVideo)
        timebase.recordAdmissionRejection(.inactive, stream: .audio, count: counts.inactiveAudio)
        timebase.recordAdmissionRejection(.staleSource, stream: .video, count: counts.staleVideo)
        timebase.recordAdmissionRejection(.staleSource, stream: .audio, count: counts.staleAudio)
        _ = timebase.recordDroppedAudio(count: counts.droppedAudio)
        let videoStreak = timebase.recordDroppedVideo(count: counts.droppedVideo)
        if counts.droppedVideo > 0, videoStreak >= maxConsecutiveDroppedFrames, stateStorage == .recording {
            diagnostics?.emit(.dropPolicyFired, recordingID: currentConfiguration?.id.rawValue)
            markAppendFailureOnQueue(.videoAppendFailed)
        }
    }

    /// M7-010: sample admission reasons. Every rejected sample is counted by
    /// its reason and never reaches the writer.
    private enum SampleAdmission {
        case accept
        case rejectInactive
        case rejectStaleSource
    }

    private func admissionVerdict(_ recordingID: RecordingID,
                                  generation: UInt64,
                                  ownerToken: RecordingOwnerToken?) -> SampleAdmission {
        guard acceptingFrames,
              stateStorage == .recording,
              let configuration = currentConfiguration else {
            return .rejectInactive
        }
        let matchesSource = configuration.id == recordingID
            && activeGeneration == generation
            && RecordingSourceFence.accepts(
                frameOwnerToken: ownerToken,
                activeOwnerToken: activeSourceOwnerToken
            )
        return matchesSource ? .accept : .rejectStaleSource
    }

    private func appendVideoOnQueue(_ frame: RecordingVideoFrame) {
        switch admissionVerdict(frame.recordingID,
                                generation: frame.generation,
                                ownerToken: frame.ownerToken) {
        case .rejectInactive:
            timebase.recordAdmissionRejection(.inactive, stream: .video)
            return
        case .rejectStaleSource:
            timebase.recordAdmissionRejection(.staleSource, stream: .video)
            return
        case .accept:
            break
        }
        guard let writer else {
            timebase.recordAdmissionRejection(.inactive, stream: .video)
            return
        }

        // M7-006: timestamp admission happens before any writer call. A
        // faulted sample is rejected and counted; it can never fail the take.
        switch timebase.admitVideo(timestamp: frame.timestamp) {
        case .reject:
            return
        case .accept:
            break
        }

        switch writer.appendVideo(frame) {
        case .failed:
            markAppendFailureOnQueue(.videoAppendFailed)
            return
        case .storagePressure:
            // M7-018: ENOSPC-class failure — typed, terminates safely, and
            // never touches existing project media.
            diagnostics?.emit(.storagePressure, recordingID: currentConfiguration?.id.rawValue)
            markAppendFailureOnQueue(.insufficientStorage)
            return
        case .dropped:
            // M7-011: bounded backpressure accounting. The capture queue is
            // never blocked (submission is nonblocking); continuous writer
            // pressure beyond the policy limit fails the take explicitly.
            if timebase.recordDroppedVideo() >= maxConsecutiveDroppedFrames {
                diagnostics?.emit(.dropPolicyFired, recordingID: currentConfiguration?.id.rawValue)
                markAppendFailureOnQueue(.videoAppendFailed)
            }
            return
        case .appended:
            break
        }

        timebase.commitVideo(timestamp: frame.timestamp)
    }

    private func appendAudioOnQueue(_ frame: RecordingAudioFrame) {
        guard let configuration = currentConfiguration,
              configuration.audioMode == .required else {
            return
        }
        switch admissionVerdict(frame.recordingID,
                                generation: frame.generation,
                                ownerToken: frame.ownerToken) {
        case .rejectInactive:
            timebase.recordAdmissionRejection(.inactive, stream: .audio)
            return
        case .rejectStaleSource:
            timebase.recordAdmissionRejection(.staleSource, stream: .audio)
            return
        case .accept:
            break
        }
        guard audioStarted, let writer else {
            timebase.recordAdmissionRejection(.inactive, stream: .audio)
            return
        }

        // M7-006: audio follows the same monotonic policy on the session
        // timeline established by the first admitted video sample.
        switch timebase.admitAudio(timestamp: frame.timestamp) {
        case .reject:
            return
        case .accept:
            break
        }

        switch writer.appendAudio(frame) {
        case .failed:
            markAppendFailureOnQueue(.audioAppendFailed)
            return
        case .storagePressure:
            markAppendFailureOnQueue(.insufficientStorage)
            return
        case .dropped:
            // M7-011: audio backpressure is counted but does not fail the
            // take; AAC input pressure degrades sound, it does not corrupt
            // the timeline, and the video policy is the explicit trigger.
            _ = timebase.recordDroppedAudio()
            return
        case .appended:
            break
        }

        timebase.commitAudio(timestamp: frame.timestamp)
    }

    private func markAppendFailureOnQueue(_ failure: RecorderFailure) {
        frameAdmission.close()
        if pendingFailure == nil {
            pendingFailure = failure
        }
        acceptingFrames = false
        if audioStarted {
            audioDriver?.stop()
            audioStarted = false
        }
        advanceGenerationOnQueue()
        setStateOnQueue(.failed)
    }

    // MARK: - Stop/finalization

    private func handleStopOnQueue(reason: RecordingStopReason,
                                   continuation: CheckedContinuation<RecordingStopResult, Never>) {
        drainSubmissionStatisticsOnQueue()
        if let lastStopResult,
           stateStorage == .finished || stateStorage == .failed || stateStorage == .released {
            continuation.resume(returning: lastStopResult)
            return
        }

        switch stateStorage {
        case .recording:
            stopWaiters.append(continuation)
            beginFinishOnQueue(reason: reason)

        case .finishing:
            stopWaiters.append(continuation)

        case .prepared:
            let result = terminalFailureResultOnQueue(.noVideoFrames)
            discardPreparedResourcesOnQueue()
            setStateOnQueue(.failed)
            lastStopResult = result
            continuation.resume(returning: result)

        case .failed:
            if writer != nil, !finishInFlight {
                stopWaiters.append(continuation)
                beginFinishOnQueue(reason: reason)
            } else if finishInFlight {
                stopWaiters.append(continuation)
            } else {
                let result = terminalFailureResultOnQueue(pendingFailure ?? .invalidTransition)
                lastStopResult = result
                continuation.resume(returning: result)
            }

        case .finished, .released:
            let result = terminalFailureResultOnQueue(.invalidTransition)
            lastStopResult = lastStopResult ?? result
            continuation.resume(returning: lastStopResult ?? result)

        case .idle:
            continuation.resume(returning: terminalFailureResultOnQueue(.invalidTransition))
        }
    }

    private func beginFinishOnQueue(reason: RecordingStopReason) {
        guard !finishInFlight else { return }

        guard let writer else {
            let result = terminalFailureResultOnQueue(pendingFailure ?? .finishFailed)
            lastStopResult = result
            resolveStopWaitersOnQueue(with: result)
            resolveReleaseWaitersOnQueue(with: result)
            setStateOnQueue(releaseRequested ? .released : .failed)
            return
        }

        lastStopReason = reason
        finishInFlight = true
        acceptingFrames = false
        advanceGenerationOnQueue()
        setStateOnQueue(.finishing)

        writer.markVideoInputAsFinished()
        if currentConfiguration?.audioMode == .required {
            writer.markAudioInputAsFinished()
        }
        if audioStarted {
            audioDriver?.stop()
            audioStarted = false
        }

        writer.finishWriting { [weak self] result in
            guard let self else { return }
            self.queue.async { [self] in
                self.finishCompletedOnQueue(result)
            }
        }

        // M7-013: a writer that never delivers its finish callback must not
        // hold stop/release waiters forever. The watchdog runs on this same
        // serialized queue; a completed finish sets finishInFlight to false
        // so a fired watchdog is a no-op, and a fired watchdog makes any
        // late callback a no-op in the same way.
        let timeout = finalizationTimeout
        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finalizationWatchdogFiredOnQueue()
        }
    }

    private func finalizationWatchdogFiredOnQueue() {
        guard finishInFlight else { return }

        writer?.discard()
        writer = nil
        audioDriver = nil
        audioStarted = false
        acceptingFrames = false
        finishInFlight = false

        let result = terminalFailureResultOnQueue(pendingFailure ?? .finishFailed)
        lastStopResult = result
        if releaseRequested {
            setStateOnQueue(.released)
        } else {
            setStateOnQueue(.failed)
        }
        resolveStopWaitersOnQueue(with: result)
        resolveReleaseWaitersOnQueue(with: result)
    }

    private func finishCompletedOnQueue(_ writerResult: Result<RecordingWriterFinish, RecordingWriterError>) {
        guard finishInFlight else { return }

        let finishMetadata: RecordingWriterFinish?
        let finishFailure: RecorderFailure?
        let finishFailureArtifact: RecordingArtifact?
        switch writerResult {
        case let .success(metadata):
            finishMetadata = metadata
            finishFailure = nil
            finishFailureArtifact = nil
        case let .failure(error):
            finishMetadata = nil
            finishFailure = .finishFailed
            if case let .finishFailed(recoverableArtifact) = error {
                finishFailureArtifact = recoverableArtifact
            } else {
                finishFailureArtifact = nil
            }
        }

        let artifact = makeArtifactOnQueue(using: finishMetadata)
        let failure: RecorderFailure?
        if let pendingFailure {
            failure = pendingFailure
        } else if timebase.acceptedVideoCount == 0 {
            failure = .noVideoFrames
        } else {
            failure = finishFailure
        }

        let result: RecordingStopResult
        if let failure {
            let recoverableArtifact: RecordingArtifact?
            if timebase.acceptedVideoCount == 0 {
                recoverableArtifact = nil
            } else if finishFailure != nil {
                recoverableArtifact = finishFailureArtifact
            } else {
                recoverableArtifact = artifact
            }
            result = .failed(failure, recoverableArtifact: recoverableArtifact)
        } else if let artifact {
            result = .finalized(artifact)
        } else {
            // This branch is defensive: acceptedVideoCount is checked above.
            result = .failed(.noVideoFrames, recoverableArtifact: nil)
        }

        finishInFlight = false
        writer = nil
        audioDriver = nil
        audioStarted = false
        acceptingFrames = false
        pendingFailure = nil
        lastStopResult = result

        // M7-030: terminal outcome diagnostics (typed, no content).
        switch result {
        case .finalized:
            diagnostics?.emit(
                .stopCompleted(outcome: "finalized", failure: nil),
                recordingID: currentConfiguration?.id.rawValue
            )
        case let .failed(failure, _):
            diagnostics?.emit(
                .stopCompleted(outcome: "failed", failure: String(describing: failure)),
                recordingID: currentConfiguration?.id.rawValue
            )
        }

        if releaseRequested {
            setStateOnQueue(.released)
        } else {
            switch result {
            case .finalized:
                setStateOnQueue(.finished)
            case .failed:
                setStateOnQueue(.failed)
            }
        }

        resolveStopWaitersOnQueue(with: result)
        resolveReleaseWaitersOnQueue(with: result)
    }

    private func makeArtifactOnQueue(using finishMetadata: RecordingWriterFinish?) -> RecordingArtifact? {
        guard timebase.acceptedVideoCount > 0,
              let configuration = currentConfiguration else {
            return nil
        }

        let duration = finishMetadata?.duration ?? derivedDurationOnQueue()
        let sanitizedDuration = duration.map { max(0, $0) }
        let hasAudio = finishMetadata?.hasAudio ?? false

        return RecordingArtifact(id: configuration.id,
                                 localURL: configuration.outputURL,
                                 duration: sanitizedDuration,
                                 hasAudio: hasAudio)
    }

    private func derivedDurationOnQueue() -> TimeInterval? {
        timebase.derivedDuration()
    }

    private func terminalFailureResultOnQueue(_ failure: RecorderFailure) -> RecordingStopResult {
        .failed(failure, recoverableArtifact: nil)
    }

    private func resolveStopWaitersOnQueue(with result: RecordingStopResult) {
        let waiters = stopWaiters
        stopWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.resume(returning: result)
        }
    }

    // MARK: - Release

    private func handleReleaseOnQueue(_ continuation: CheckedContinuation<RecordingStopResult?, Never>) {
        drainSubmissionStatisticsOnQueue()
        switch stateStorage {
        case .released:
            continuation.resume(returning: lastStopResult)

        case .idle:
            discardPreparedResourcesOnQueue()
            setStateOnQueue(.released)
            continuation.resume(returning: lastStopResult)

        case .prepared:
            discardPreparedResourcesOnQueue()
            setStateOnQueue(.released)
            continuation.resume(returning: nil)

        case .recording:
            releaseRequested = true
            releaseWaiters.append(continuation)
            beginFinishOnQueue(reason: .routeExit)

        case .finishing:
            releaseRequested = true
            releaseWaiters.append(continuation)

        case .finished:
            discardPreparedResourcesOnQueue()
            setStateOnQueue(.released)
            continuation.resume(returning: lastStopResult)

        case .failed:
            if writer != nil, !finishInFlight {
                releaseRequested = true
                releaseWaiters.append(continuation)
                beginFinishOnQueue(reason: .routeExit)
            } else if finishInFlight {
                releaseRequested = true
                releaseWaiters.append(continuation)
            } else {
                discardPreparedResourcesOnQueue()
                setStateOnQueue(.released)
                continuation.resume(returning: lastStopResult)
            }
        }
    }

    private func discardPreparedResourcesOnQueue() {
        writer?.discard()
        writer = nil
        if audioStarted {
            audioDriver?.stop()
        }
        audioDriver = nil
        audioStarted = false
        acceptingFrames = false
        finishInFlight = false
    }

    private func resolveReleaseWaitersOnQueue(with result: RecordingStopResult?) {
        let waiters = releaseWaiters
        releaseWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.resume(returning: result)
        }
    }

    private func advanceGenerationOnQueue() {
        activeGeneration &+= 1
        if activeGeneration == 0 {
            activeGeneration = 1
        }
    }

    /// M1-010: every state assignment funnels through the canonical transition
    /// table so an illegal transition fails deterministically in the test lane
    /// (assert is stripped from release builds).
    private func setStateOnQueue(_ newState: RecorderState) {
        let from = RecordingLifecycleState(stateStorage)
        let to = RecordingLifecycleState(newState)
        assert(
            RecordingLifecycleState.isLegalTransition(from: from, to: to),
            "SerializedMediaRecorder illegal lifecycle transition \(from) -> \(to)"
        )
        stateStorage = newState
        // M7-030: bounded redacted lifecycle diagnostics.
        diagnostics?.emit(
            .stateChanged(from: from.rawValue, to: to.rawValue),
            recordingID: currentConfiguration?.id.rawValue
        )
    }
}

/// M7-006: the one monotonic media timebase for a recording take.
///
/// Timestamp conversion (v1, fixed):
/// 1. Producers deliver host seconds. The audio driver converts capture-clock
///    sample buffers to the host clock (`CMSyncConvertTime`) before enqueue;
///    video frames carry the capture session's host-retimed timestamps.
/// 2. The first admitted video sample establishes the session origin
///    (`RecordingTimeOrigin.firstAcceptedVideoOrigin`).
/// 3. The Apple adapter converts admitted host seconds to `CMTime` at a 600
///    timescale and subtracts its own copy of the first appended timestamp, so
///    the written file's presentation timestamps are session-relative and
///    start at zero. Audio timing entries are normalized with the same origin,
///    which keeps both streams on one session timeline.
///
/// Stream policy is `RecordingStreamTimePolicy.strictPerStreamMonotonic`:
/// a sample whose timestamp is not strictly greater than its stream's last
/// committed timestamp is rejected and counted, never appended. Forward gaps
/// larger than ``maxForwardGapSeconds`` are tolerated as counted
/// discontinuities so one stalled producer cannot end the take; backwards
/// motion is never tolerated. Admission and commit are separate so a sample
/// rejected by the writer (backpressure) cannot pin the timeline.
private struct RecordingMediaTimebase {
    /// A forward gap above this threshold is recorded as a discontinuity
    /// instead of a normal sample. Chosen well above any expected encoder
    /// backpressure stall so only real timeline breaks are counted.
    static let maxForwardGapSeconds: TimeInterval = 2.0

    private(set) var videoOrigin: TimeInterval?
    /// Admission fence: the last timestamp admitted to the writer. It advances
    /// even when the writer later drops the sample under backpressure, so the
    /// file's presentation timestamps stay strictly increasing.
    private var lastAdmittedVideoTimestamp: TimeInterval?
    private var lastAdmittedAudioTimestamp: TimeInterval?
    /// Last timestamps actually persisted by the writer.
    private(set) var lastVideoTimestamp: TimeInterval?
    private(set) var lastAudioTimestamp: TimeInterval?
    /// M7-016: first admitted audio sample for the start-delta measurement.
    private(set) var firstAudioTimestamp: TimeInterval?
    private(set) var acceptedVideoCount = 0
    private(set) var acceptedAudioCount = 0
    private(set) var rejectedInvalidTimestampCount = 0
    private(set) var rejectedNonMonotonicVideoCount = 0
    private(set) var rejectedNonMonotonicAudioCount = 0
    private(set) var rejectedBeforeOriginAudioCount = 0
    private(set) var discontinuityCount = 0
    /// M7-010: samples arriving outside the recording window (before start,
    /// after the stop boundary, or with no writer attached).
    private(set) var rejectedInactiveCount = 0
    /// M7-010: samples from a stale/foreign source identity.
    private(set) var rejectedStaleSourceCount = 0
    /// M7-011: writer backpressure drops.
    private(set) var droppedVideoCount = 0
    private(set) var droppedAudioCount = 0
    private var consecutiveDroppedVideoCount = 0
    private var consecutiveDroppedAudioCount = 0

    enum RejectionReason {
        case inactive
        case staleSource
    }

    enum SampleStream {
        case video
        case audio
    }

    mutating func recordAdmissionRejection(_ reason: RejectionReason, stream: SampleStream, count: Int = 1) {
        guard count > 0 else { return }
        switch (reason, stream) {
        case (.inactive, .video), (.inactive, .audio):
            rejectedInactiveCount = Self.saturatingAdd(rejectedInactiveCount, count)
        case (.staleSource, .video), (.staleSource, .audio):
            rejectedStaleSourceCount = Self.saturatingAdd(rejectedStaleSourceCount, count)
        }
    }

    /// M7-011: records one video backpressure drop and returns the current
    /// consecutive-drop streak for the policy decision.
    mutating func recordDroppedVideo(count: Int = 1) -> Int {
        guard count > 0 else { return consecutiveDroppedVideoCount }
        droppedVideoCount = Self.saturatingAdd(droppedVideoCount, count)
        consecutiveDroppedVideoCount = Self.saturatingAdd(consecutiveDroppedVideoCount, count)
        return consecutiveDroppedVideoCount
    }

    mutating func recordDroppedAudio(count: Int = 1) -> Int {
        guard count > 0 else { return consecutiveDroppedAudioCount }
        droppedAudioCount = Self.saturatingAdd(droppedAudioCount, count)
        consecutiveDroppedAudioCount = Self.saturatingAdd(consecutiveDroppedAudioCount, count)
        return consecutiveDroppedAudioCount
    }

    private static func saturatingAdd(_ value: Int, _ increment: Int) -> Int {
        let (sum, overflow) = value.addingReportingOverflow(max(0, increment))
        return overflow ? .max : sum
    }

    enum Admission {
        case accept
        case reject
    }

    func report() -> RecordingTimebaseReport {
        RecordingTimebaseReport(
            videoOrigin: videoOrigin,
            acceptedVideoCount: acceptedVideoCount,
            acceptedAudioCount: acceptedAudioCount,
            rejectedInvalidTimestampCount: rejectedInvalidTimestampCount,
            rejectedNonMonotonicVideoCount: rejectedNonMonotonicVideoCount,
            rejectedNonMonotonicAudioCount: rejectedNonMonotonicAudioCount,
            rejectedBeforeOriginAudioCount: rejectedBeforeOriginAudioCount,
            discontinuityCount: discontinuityCount,
            rejectedInactiveCount: rejectedInactiveCount,
            rejectedStaleSourceCount: rejectedStaleSourceCount,
            droppedVideoCount: droppedVideoCount,
            droppedAudioCount: droppedAudioCount,
            firstAudioTimestamp: firstAudioTimestamp,
            lastVideoTimestamp: lastVideoTimestamp,
            lastAudioTimestamp: lastAudioTimestamp
        )
    }

    /// M7-016: derives the synchronization measurement from a timebase
    /// report. Pure so the release criterion is table-testable.
    static func syncReport(from report: RecordingTimebaseReport) -> RecordingSyncReport {
        let startDelta = report.firstAudioTimestamp.map { $0 - (report.videoOrigin ?? $0) }
        let endDelta: TimeInterval?
        if let lastAudio = report.lastAudioTimestamp, let lastVideo = report.lastVideoTimestamp {
            endDelta = lastAudio - lastVideo
        } else {
            endDelta = nil
        }
        let monotonicityFaults = report.rejectedInvalidTimestampCount
            + report.rejectedNonMonotonicVideoCount
            + report.rejectedNonMonotonicAudioCount
            + report.rejectedBeforeOriginAudioCount
        return RecordingSyncReport(
            startDeltaSeconds: startDelta,
            endDeltaSeconds: endDelta,
            monotonicityFaultCount: monotonicityFaults,
            discontinuityCount: report.discontinuityCount
        )
    }

    /// Derived artifact duration: session length from the first to the last
    /// committed video timestamp (pre-existing behavior, now single-sourced).
    func derivedDuration() -> TimeInterval? {
        guard let origin = videoOrigin,
              let last = lastVideoTimestamp,
              origin.isFinite,
              last.isFinite else {
            return nil
        }
        return max(0, last - origin)
    }

    mutating func admitVideo(timestamp: TimeInterval) -> Admission {
        guard timestamp.isFinite else {
            rejectedInvalidTimestampCount += 1
            return .reject
        }
        if let last = lastAdmittedVideoTimestamp {
            guard timestamp > last else {
                rejectedNonMonotonicVideoCount += 1
                return .reject
            }
            if timestamp - last > Self.maxForwardGapSeconds {
                discontinuityCount += 1
            }
        }
        lastAdmittedVideoTimestamp = timestamp
        return .accept
    }

    mutating func commitVideo(timestamp: TimeInterval) {
        if videoOrigin == nil {
            videoOrigin = timestamp
        }
        lastVideoTimestamp = timestamp
        acceptedVideoCount += 1
        consecutiveDroppedVideoCount = 0
    }

    mutating func admitAudio(timestamp: TimeInterval) -> Admission {
        guard timestamp.isFinite else {
            rejectedInvalidTimestampCount += 1
            return .reject
        }
        guard let origin = videoOrigin else {
            rejectedBeforeOriginAudioCount += 1
            return .reject
        }
        if timestamp < origin {
            rejectedBeforeOriginAudioCount += 1
            return .reject
        }
        if let last = lastAdmittedAudioTimestamp {
            guard timestamp > last else {
                rejectedNonMonotonicAudioCount += 1
                return .reject
            }
            if timestamp - last > Self.maxForwardGapSeconds {
                discontinuityCount += 1
            }
        }
        lastAdmittedAudioTimestamp = timestamp
        return .accept
    }

    mutating func commitAudio(timestamp: TimeInterval) {
        if firstAudioTimestamp == nil {
            firstAudioTimestamp = timestamp
        }
        lastAudioTimestamp = timestamp
        acceptedAudioCount += 1
        consecutiveDroppedAudioCount = 0
    }
}
