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
    private var firstVideoTimestamp: TimeInterval?
    private var lastVideoTimestamp: TimeInterval?
    private var acceptedVideoCount = 0
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
         queueLabel: String = "com.shafinMultitool.serializedMediaRecorder") {
        self.writerFactory = writerFactory
        self.audioDriverFactory = audioDriverFactory
        self.outputChecker = outputChecker
        self.queue = DispatchQueue(label: queueLabel, qos: .userInitiated)
        self.queue.setSpecific(key: Self.queueSpecificKey, value: UUID())
    }

    var state: RecorderState {
        get async {
            await stateSnapshot().state
        }
    }

    func stateSnapshot() async -> RecorderStateSnapshot {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: RecorderStateSnapshot(
                    state: stateStorage,
                    recordingID: currentConfiguration?.id,
                    generation: activeGeneration,
                    ownerToken: activeSourceOwnerToken
                ))
            }
        }
    }

    func prepare(_ configuration: RecordingConfiguration) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    try prepareOnQueue(configuration)
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
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                handleStopOnQueue(reason: reason, continuation: continuation)
            }
        }
    }

    func releaseAndWait() async -> RecordingStopResult? {
        await withCheckedContinuation { continuation in
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
        queue.async { [self] in
            appendVideoOnQueue(frame)
        }
    }

    func enqueueAudio(_ frame: RecordingAudioFrame) {
        queue.async { [self] in
            appendAudioOnQueue(frame)
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

    private func prepareOnQueue(_ configuration: RecordingConfiguration) throws {
        if stateStorage == .prepared,
           let currentConfiguration,
           currentConfiguration == configuration {
            return
        }

        guard stateStorage == .idle else {
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
            if error == .inputRejected {
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
        acceptedVideoCount = 0
        firstVideoTimestamp = nil
        lastVideoTimestamp = nil
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
    }

    private func failStartOnQueue(_ failure: RecorderFailure,
                                  writer failedWriter: any RecordingWriter,
                                  audioDriver failedAudioDriver: (any RecordingAudioDriver)?) {
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

    private func appendVideoOnQueue(_ frame: RecordingVideoFrame) {
        guard canAccept(frame.recordingID,
                        generation: frame.generation,
                        ownerToken: frame.ownerToken),
              let writer else {
            return
        }

        switch writer.appendVideo(frame) {
        case .failed:
            markAppendFailureOnQueue(.videoAppendFailed)
            return
        case .dropped:
            return
        case .appended:
            break
        }

        acceptedVideoCount += 1
        if frame.timestamp.isFinite {
            if firstVideoTimestamp == nil {
                firstVideoTimestamp = frame.timestamp
            }
            lastVideoTimestamp = frame.timestamp
        }
    }

    private func appendAudioOnQueue(_ frame: RecordingAudioFrame) {
        guard let configuration = currentConfiguration,
              configuration.audioMode == .required,
              canAccept(frame.recordingID,
                        generation: frame.generation,
                        ownerToken: frame.ownerToken),
              audioStarted,
              let writer else {
            return
        }

        switch writer.appendAudio(frame) {
        case .failed:
            markAppendFailureOnQueue(.audioAppendFailed)
            return
        case .dropped, .appended:
            return
        }

    }

    private func canAccept(_ recordingID: RecordingID,
                           generation: UInt64,
                           ownerToken: RecordingOwnerToken?) -> Bool {
        guard acceptingFrames,
              stateStorage == .recording,
              let configuration = currentConfiguration else {
            return false
        }
        return configuration.id == recordingID
            && activeGeneration == generation
            && RecordingSourceFence.accepts(
                frameOwnerToken: ownerToken,
                activeOwnerToken: activeSourceOwnerToken
            )
    }

    private func markAppendFailureOnQueue(_ failure: RecorderFailure) {
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
        } else if acceptedVideoCount == 0 {
            failure = .noVideoFrames
        } else {
            failure = finishFailure
        }

        let result: RecordingStopResult
        if let failure {
            let recoverableArtifact: RecordingArtifact?
            if acceptedVideoCount == 0 {
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
        guard acceptedVideoCount > 0,
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
        guard let firstVideoTimestamp,
              let lastVideoTimestamp,
              firstVideoTimestamp.isFinite,
              lastVideoTimestamp.isFinite else {
            return nil
        }
        return max(0, lastVideoTimestamp - firstVideoTimestamp)
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
    }
}
