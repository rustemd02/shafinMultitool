//
//  CameraViewModel.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import Combine
import Foundation

enum CameraPausePresentationState: Equatable, Sendable {
    case idle
    case loading(snapshotID: String)
    case success(snapshotID: String, critique: PauseCritiquePresentation)
    case empty(snapshotID: String)
    case failure(snapshotID: String)
    case resuming(snapshotID: String)

    var snapshotID: String? {
        switch self {
        case .idle:
            return nil
        case .loading(let snapshotID), .empty(let snapshotID), .failure(let snapshotID), .resuming(let snapshotID):
            return snapshotID
        case .success(let snapshotID, _):
            return snapshotID
        }
    }
}

enum CameraPauseFailureReason: Equatable, Sendable {
    case noAcceptedEvidence
    case displayRenderFailed
    case pipelineUnavailable
    case timeout
}

enum CameraLensSwitchPresentationState: Equatable, Sendable {
    case idle
    case switching(CameraLens)
    case failed(CameraLensSwitchResult.FailureReason)

    var isSwitching: Bool {
        if case .switching = self { return true }
        return false
    }
}

enum CameraNominalTimecode {
    static let nominalFramesPerSecond = 24

    static func string(elapsed: TimeInterval, showsFrames: Bool = true) -> String {
        let safeElapsed = max(0, elapsed)
        let totalFrames = Int((safeElapsed * Double(nominalFramesPerSecond)).rounded(.down))
        let totalSeconds = totalFrames / nominalFramesPerSecond
        let frames = totalFrames % nominalFramesPerSecond
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3_600
        if showsFrames {
            return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
        }
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

@MainActor
private final class CameraNominalTimecodeSession {
    private var accumulatedSeconds: TimeInterval = 0
    private var runningSince: TimeInterval?

    var elapsed: TimeInterval {
        guard let runningSince else { return accumulatedSeconds }
        return accumulatedSeconds + max(0, ProcessInfo.processInfo.systemUptime - runningSince)
    }

    var hasStarted: Bool { runningSince != nil || accumulatedSeconds > 0 }

    func beginOrResume() {
        guard runningSince == nil else { return }
        runningSince = ProcessInfo.processInfo.systemUptime
    }

    func pause() {
        guard let runningSince else { return }
        accumulatedSeconds += max(0, ProcessInfo.processInfo.systemUptime - runningSince)
        self.runningSince = nil
    }

    func reset() {
        accumulatedSeconds = 0
        runningSince = nil
    }
}

/// Dedicated observation owner for the nominal timecode. Camera Coach's
/// periodic 0.3-second clock must not make the whole capture surface the owner
/// of that invalidation; the HUD observes this small publisher instead.
@MainActor
final class CameraNominalTimecodePublisher: ObservableObject {
    @Published private(set) var value: String

    init(initialValue: String = CameraNominalTimecode.string(elapsed: 0)) {
        value = initialValue
    }

    func publish(_ value: String) {
        guard self.value != value else { return }
        self.value = value
    }
}

@MainActor
final class CameraViewModel: ObservableObject {
    private struct PendingPauseAnalysis {
        let result: PauseAnalysisResult
        let suggestions: [Suggestion]
        let critique: PauseCritiquePresentation?
    }

    private final class FailedStartRollbackOperation {
        let generation: UInt64
        let task: Task<Void, Never>

        init(generation: UInt64, task: Task<Void, Never>) {
            self.generation = generation
            self.task = task
        }
    }

    private final class ReleaseOperation {
        let task: Task<Void, Never>

        init(task: Task<Void, Never>) {
            self.task = task
        }
    }

    @Published private(set) var lifecycleState: CameraLifecycleState = .idle
    @Published private(set) var lifecycleError: CameraManagerError?

    @Published var overlayState: OverlayState = .init(primaryBoundingBox: nil,
                                                      horizonAngle: 0,
                                                      horizonConfidence: 0,
                                                      saliencyBalance: 0)
    @Published var suggestion: Suggestion?
    @Published var features: CoachingFeatures = CoachingFeatures()
    @Published var debugMode: Bool = false
    @Published var isPaused: Bool = false
    @Published var previewSuggestions: [Suggestion] = []
    @Published var liveHint: LiveHintPresentation?
    /// Bounded domain outputs consumed by CameraOverlayUXPresentation. Raw
    /// model confidence/debug values never enter this projection.
    @Published private(set) var plannerDecision: CameraCoachDecisionV2?
    @Published private(set) var verificationResult: ActionVerificationResult?
    @Published private(set) var analysisStatus: CameraOverlayAnalysisStatus = .healthy
    @Published private(set) var analysisFailure: CameraAnalysisFailure?
    @Published private(set) var effectivePerformance: CameraRuntimePerformanceSnapshot = .nominal
    @Published var pauseCritique: PauseCritiquePresentation?
    @Published private(set) var pausePresentationState: CameraPausePresentationState = .idle
    @Published private(set) var pauseFailureReason: CameraPauseFailureReason?
    @Published var overlayAnnotations: [OverlayAnnotationPresentation] = []
    @Published var legacySuggestion: Suggestion?
    
    // Debug данные
    @Published var detrDetections: [DETRDetection] = []
    @Published var visionSubjects: [VisionSubject] = []
    @Published var saliencyCenter: CGPoint?
    
    // Зум/объективы
    @Published var currentLens: CameraLens = .wide
    @Published var availableLenses: [CameraLens] = []
    @Published private(set) var lensSwitchPresentationState: CameraLensSwitchPresentationState = .idle
    @Published private(set) var lensSwitchRequestedLens: CameraLens?
    /// Legacy read access remains available to callers/tests, but this value is
    /// intentionally not published. The HUD observes `nominalTimecodePublisher`
    /// so clock ticks do not rebuild the capture owner.
    private(set) var nominalTimecode = CameraNominalTimecode.string(elapsed: 0)

    let nominalTimecodePublisher = CameraNominalTimecodePublisher()

    /// The accepted pause handoff owns the immutable display pixels and the
    /// exact evidence envelope analysed by the pipeline.
    @Published private(set) var acceptedPauseSnapshot: LatestFrameEvidenceStore.AcceptedSnapshot?
    @Published private(set) var takeNumber: Int = 0
    @Published private(set) var subjectRegions: [NormalizedRect] = []
    @Published private(set) var coachingEpisodeState: CoachingEpisodeState = .idle

    var isPauseProjectionReady: Bool {
        isPaused && acceptedPauseSnapshot?.displayImage != nil
    }

    var isPauseCapturePending: Bool {
        !isPaused && pauseDisplayRenderTask != nil && pauseRequestToken != nil
    }

    /// Session-owned marker consumption survives SwiftUI recomposition and
    /// route rotation. Production marker views never own this ledger.
    let motionEventLedger = SETMotionEventLedger()
    let pauseCutMarkController: SETPauseCutMarkController
    /// Camera Coach owns the episode lifetime; presentation views only observe
    /// this projection and cannot restart an episode during recomposition.
    private var coachingEpisodeCoordinator = CoachingEpisodeCoordinator()

    private let cameraManager: CameraManager
    private let analysisPipeline: AnalysisPipeline
    private let lensSwitchOperation: @Sendable (CameraLens) async -> CameraLensSwitchResult
    private let lensSelectionHaptic: SETHapticPerforming
    private var cancellables = Set<AnyCancellable>()
    private var featurePollingCancellable: AnyCancellable?
    private var pauseRequestToken: UUID?
    private var acceptedPauseRequestToken: UUID?
    private var lifecycleTask: Task<Void, Never>?
    private var lifecycleIntent = UUID()
    private var lensSwitchTask: Task<Void, Never>?
    private var lensSwitchIntent = UUID()
    private var pauseDisplayRenderTask: Task<Void, Never>?
    private var pendingPauseAnalysis: PendingPauseAnalysis?
    private var releaseOperation: ReleaseOperation?
    private var failedStartRollbackOperation: FailedStartRollbackOperation?
    private var nextFailedStartRollbackGeneration: UInt64 = 0
    private let timecodeSession = CameraNominalTimecodeSession()

    init(cameraManager: CameraManager,
         analysisPipeline: AnalysisPipeline,
         lensSwitchOperation: (@Sendable (CameraLens) async -> CameraLensSwitchResult)? = nil,
         lensSelectionHaptic: SETHapticPerforming? = nil,
         performanceStore: CameraRuntimePerformanceStore = .shared) {
        self.cameraManager = cameraManager
        self.analysisPipeline = analysisPipeline
        self.pauseCutMarkController = SETPauseCutMarkController(eventLedger: motionEventLedger)
        self.lensSelectionHaptic = lensSelectionHaptic ?? SETHapticFeedback()
        self.effectivePerformance = performanceStore.currentSnapshot
        self.analysisStatus = performanceStore.currentSnapshot.isLimited ? .limited : .healthy
        self.lensSwitchOperation = lensSwitchOperation ?? { [cameraManager] lens in
            await cameraManager.switchLensAndWait(to: lens)
        }

        analysisPipeline.$overlayState
            .receive(on: DispatchQueue.main)
            .assign(to: &$overlayState)

        analysisPipeline.$currentSuggestion
            .receive(on: DispatchQueue.main)
            .assign(to: &$suggestion)

        analysisPipeline.$currentSuggestion
            .receive(on: DispatchQueue.main)
            .assign(to: &$legacySuggestion)

        analysisPipeline.$currentLiveHint
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hint in
                self?.applyLiveHint(hint)
            }
            .store(in: &cancellables)

        analysisPipeline.$currentCoachingEpisodeEvent
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] event in
                self?.consumeCoachingEpisodeEvent(event)
            }
            .store(in: &cancellables)

        analysisPipeline.$currentPauseCritique
            .receive(on: DispatchQueue.main)
            .assign(to: &$pauseCritique)

        analysisPipeline.$currentOverlayAnnotations
            .receive(on: DispatchQueue.main)
            .assign(to: &$overlayAnnotations)

        analysisPipeline.$subjectRegions
            .receive(on: DispatchQueue.main)
            .assign(to: &$subjectRegions)

        cameraManager.failurePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.handleCameraFailure(error)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: CameraRuntimePerformanceStore.notification)
            .compactMap { notification in
                notification.userInfo?[CameraRuntimePerformanceStore.snapshotUserInfoKey]
                    as? CameraRuntimePerformanceSnapshot
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.applyEffectivePerformance(snapshot)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: CameraAnalysisRuntimeSignal.failureNotification)
            .compactMap { notification in
                notification.userInfo?[CameraAnalysisRuntimeSignal.failureUserInfoKey]
                    as? CameraAnalysisFailure
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] failure in
                self?.reportAnalysisFailure(failure)
            }
            .store(in: &cancellables)
    }

    func start() {
        clearAnalysisFailureForNewCapture()
        resetCoachingEpisodeForNewCapture()
        let intent = beginLifecycleRequest(.starting)
        let pendingRollback = failedStartRollbackOperation
        let pendingRelease = releaseOperation
        lifecycleTask = Task { [weak self] in
            guard let self else { return }
            if let pendingRollback {
                await self.awaitFailedStartRollback(pendingRollback)
                guard !Task.isCancelled, self.lifecycleIntent == intent else { return }
            }
            if let pendingRelease {
                await self.awaitReleaseOperation(pendingRelease)
                guard !Task.isCancelled, self.lifecycleIntent == intent else { return }
            }
            guard !Task.isCancelled, self.lifecycleIntent == intent else { return }
            guard self.startCaptureRegistrationIfNeeded(for: intent) else {
                return
            }
            await self.performStart(intent: intent)
        }
    }

    func startAndWait() async {
        clearAnalysisFailureForNewCapture()
        resetCoachingEpisodeForNewCapture()
        let intent = beginLifecycleRequest(.starting)
        if let pendingRollback = failedStartRollbackOperation {
            await awaitFailedStartRollback(pendingRollback)
            guard !Task.isCancelled, lifecycleIntent == intent else { return }
        }
        if let pendingRelease = releaseOperation {
            await awaitReleaseOperation(pendingRelease)
            guard !Task.isCancelled, lifecycleIntent == intent else { return }
        }
        guard !Task.isCancelled, lifecycleIntent == intent else { return }
        guard startCaptureRegistrationIfNeeded(for: intent) else {
            return
        }
        await performStart(intent: intent)
    }

    func stop() {
        cancelCoachingEpisode(reason: .routeExit)
        cancelPendingPauseRenderIfNeeded()
        let intent = beginLifecycleRequest(.stopping)
        stopFeaturePolling()
        let pendingRelease = releaseOperation
        lifecycleTask = Task { [weak self] in
            guard let self else { return }
            if let pendingRelease {
                await self.awaitReleaseOperation(pendingRelease)
                guard !Task.isCancelled, self.lifecycleIntent == intent else { return }
            }
            await self.performStop(intent: intent)
        }
    }

    func stopAndWait() async {
        cancelCoachingEpisode(reason: .routeExit)
        cancelPendingPauseRenderIfNeeded()
        let intent = beginLifecycleRequest(.stopping)
        stopFeaturePolling()
        let pendingRelease = releaseOperation
        if let pendingRelease {
            await awaitReleaseOperation(pendingRelease)
            guard !Task.isCancelled, lifecycleIntent == intent else { return }
        }
        await performStop(intent: intent)
    }

    /// The production surface calls this for a non-active scene. AVFoundation
    /// does not guarantee that every background transition emits its own
    /// interruption notification.
    func reportSceneInactive() {
        guard hasActiveCaptureOrPauseWork else { return }
        cancelCoachingEpisode(reason: .background)
        if lifecycleState == .starting || lifecycleState == .running {
            cameraManager.reportSessionInterrupted()
        }
        handleCameraFailure(.sessionInterrupted)
    }

    func releaseAndWait() async {
        cancelCoachingEpisode(reason: .routeExit)
        let intent = beginLifecycleRequest(.stopping)
        stopFeaturePolling()
        clearPresentationProjection()

        let operation = makeReleaseOperation()

        await awaitReleaseOperation(operation)

        guard lifecycleIntent == intent else { return }
        lifecycleState = .idle
        lifecycleError = nil
    }

    private func makeReleaseOperation() -> ReleaseOperation {
        if let releaseOperation {
            return releaseOperation
        }

        let pendingRollback = failedStartRollbackOperation
        let operation = ReleaseOperation(task: Task { [weak self] in
            guard let self else { return }

            if let pendingRollback {
                await self.awaitFailedStartRollback(pendingRollback)
            }

            // Full release order: stop frame production, fence pipeline work and
            // registrations, then release the camera configuration.
            await self.cameraManager.stopAndWait()
            await self.analysisPipeline.releaseAndWait()
            await self.cameraManager.releaseAndWait()
        })
        releaseOperation = operation
        return operation
    }

    private func awaitReleaseOperation(_ operation: ReleaseOperation) async {
        await operation.task.value
        guard let current = releaseOperation, current === operation else { return }
        releaseOperation = nil
    }

    private func beginLifecycleRequest(_ requestedState: CameraLifecycleState) -> UUID {
        lifecycleTask?.cancel()
        lensSwitchTask?.cancel()
        lensSwitchTask = nil
        lensSwitchIntent = UUID()
        let intent = UUID()
        lifecycleIntent = intent
        lifecycleState = requestedState
        lifecycleError = nil
        return intent
    }

    private var hasActiveCaptureOrPauseWork: Bool {
        switch lifecycleState {
        case .starting, .running:
            return true
        case .idle, .failed:
            return isPaused
                || isPauseCapturePending
                || acceptedPauseSnapshot != nil
                || pausePresentationState != .idle
        case .stopping:
            return false
        }
    }

    private func handleCameraFailure(_ error: CameraManagerError) {
        guard hasActiveCaptureOrPauseWork else { return }

        cancelCoachingEpisode(reason: .routeExit)

        lifecycleTask?.cancel()
        lifecycleTask = nil
        lensSwitchTask?.cancel()
        lensSwitchTask = nil
        lensSwitchIntent = UUID()
        let intent = UUID()
        lifecycleIntent = intent
        lifecycleState = .stopping
        lifecycleError = error
        stopFeaturePolling()
        analysisPipeline.clearLivePresentationState()
        analysisPipeline.clearPausePresentationState()
        clearPresentationProjection()

        let operation = makeReleaseOperation()
        Task { [weak self] in
            guard let self else { return }
            await self.awaitReleaseOperation(operation)
            guard self.lifecycleIntent == intent else { return }
            self.lifecycleState = .failed(error)
            self.lifecycleError = error
        }
    }

    private func clearPresentationProjection() {
        pauseRequestToken = nil
        acceptedPauseRequestToken = nil
        pauseDisplayRenderTask?.cancel()
        pauseDisplayRenderTask = nil
        pendingPauseAnalysis = nil
        isPaused = false
        previewSuggestions = []
        pauseCritique = nil
        pauseFailureReason = nil
        pausePresentationState = .idle
        acceptedPauseSnapshot = nil
        takeNumber = 0
        overlayState = .init(primaryBoundingBox: nil,
                             horizonAngle: 0,
                             horizonConfidence: 0,
                             saliencyBalance: 0)
        suggestion = nil
        legacySuggestion = nil
        liveHint = nil
        plannerDecision = nil
        verificationResult = nil
        overlayAnnotations = []
        subjectRegions = []
        currentLens = .wide
        availableLenses = []
        lensSwitchPresentationState = .idle
        lensSwitchRequestedLens = nil
        timecodeSession.reset()
        nominalTimecode = CameraNominalTimecode.string(elapsed: 0)
        nominalTimecodePublisher.publish(nominalTimecode)
        motionEventLedger.reset()
        coachingEpisodeCoordinator.resetForRetry()
        coachingEpisodeState = .idle
    }

    private func cancelPendingPauseRenderIfNeeded() {
        guard !isPaused, pauseDisplayRenderTask != nil else { return }
        pauseDisplayRenderTask?.cancel()
        pauseDisplayRenderTask = nil
        pauseRequestToken = nil
        acceptedPauseRequestToken = nil
        acceptedPauseSnapshot = nil
        pendingPauseAnalysis = nil
        pauseFailureReason = nil
        pausePresentationState = .idle
    }

    private func performStart(intent: UUID) async {
        do {
            try await cameraManager.startAndWait()
            guard !Task.isCancelled, lifecycleIntent == intent else { return }
            lifecycleState = .running
            lifecycleError = nil
            // CameraManager owns the physical input. Query it after every
            // start/resume so a telephoto selection survives a pause stop and
            // never flashes back to a guessed wide default.
            currentLens = cameraManager.activeLens ?? currentLens
            availableLenses = cameraManager.availableLenses
            timecodeSession.beginOrResume()
            publishNominalTimecode()
            if case .resuming = pausePresentationState {
                pausePresentationState = .idle
                acceptedPauseSnapshot = nil
                acceptedPauseRequestToken = nil
                pendingPauseAnalysis = nil
                pauseFailureReason = nil
            }
            lensSwitchRequestedLens = nil
        } catch let error as CameraManagerError {
            guard lifecycleIntent == intent else { return }
            stopFeaturePolling()
            // A cancelled waiter still owns this current intent's registrations;
            // finish their rollback, but never publish after the boundary if it was
            // cancelled or superseded while the cleanup was in flight.
            let rollback = makeFailedStartRollback()
            await awaitFailedStartRollback(rollback)
            guard !Task.isCancelled, lifecycleIntent == intent else { return }
            lifecycleState = .failed(error)
            lifecycleError = error
        } catch {
            guard lifecycleIntent == intent else { return }
            stopFeaturePolling()
            let rollback = makeFailedStartRollback()
            await awaitFailedStartRollback(rollback)
            guard !Task.isCancelled, lifecycleIntent == intent else { return }
            let typedError = CameraManagerError.startFailed
            lifecycleState = .failed(typedError)
            lifecycleError = typedError
        }
    }

    private func makeFailedStartRollback() -> FailedStartRollbackOperation {
        if let failedStartRollbackOperation {
            return failedStartRollbackOperation
        }

        nextFailedStartRollbackGeneration &+= 1
        let generation = nextFailedStartRollbackGeneration
        let pipeline = analysisPipeline
        let task = Task {
            await pipeline.releaseAndWait()
        }
        let operation = FailedStartRollbackOperation(generation: generation, task: task)
        failedStartRollbackOperation = operation
        return operation
    }

    private func awaitFailedStartRollback(_ operation: FailedStartRollbackOperation) async {
        // Awaiting a shared unstructured task does not cancel it when one waiter is
        // cancelled; every waiter observes the same cleanup boundary.
        await operation.task.value
        guard let current = failedStartRollbackOperation,
              current === operation,
              current.generation == operation.generation else { return }
        failedStartRollbackOperation = nil
    }

    private func performStop(intent: UUID) async {
        timecodeSession.pause()
        publishNominalTimecode()
        await cameraManager.stopAndWait()
        guard !Task.isCancelled, lifecycleIntent == intent else { return }
        lifecycleState = cameraManager.lifecycleState
        lifecycleError = cameraManager.lifecycleError
    }

    private func startCaptureRegistrationIfNeeded(for intent: UUID) -> Bool {
        let didRegister = analysisPipeline.register(with: cameraManager)
        guard didRegister, !Task.isCancelled, lifecycleIntent == intent else {
            stopFeaturePolling()
            return false
        }
        startFeaturePolling()
        return true
    }
    
    func toggleDebug() {
        debugMode.toggle()
    }

    /// Verifier owner handoff. A result from a different episode token is
    /// stale and is discarded instead of changing the live presentation.
    @discardableResult
    func applyVerificationResult(_ result: ActionVerificationResult) -> Bool {
        guard coachingEpisodeState.token == result.token else { return false }
        verificationResult = result
        if case .incomparable = result.decision {
            clearLiveAdviceForAnalysisBoundary()
            analysisStatus = effectivePerformance.isLimited ? .limited : .healthy
        }
        return true
    }

    /// Planner owner handoff for WAIT/SELECT_SUBJECT/ABSTAIN states that do
    /// not carry a human-facing live hint. The normal production path derives
    /// this same bounded decision from the pipeline's typed LiveHint output.
    func applyPlannerDecision(_ decision: CameraCoachDecisionV2?) {
        plannerDecision = decision
        verificationResult = nil
        if decision == .wait || decision == .abstain || decision == .selectSubject {
            clearLiveAdviceForAnalysisBoundary()
        }
    }

    /// Analyzer failure is an explicit owner signal. The presentation becomes
    /// honest fallback immediately and all stale marker/copy is removed.
    func reportAnalysisFailure(_ failure: CameraAnalysisFailure = .failed) {
        analysisFailure = failure
        analysisStatus = .failed
        plannerDecision = nil
        verificationResult = nil
        clearLiveAdviceForAnalysisBoundary()
    }

    func togglePause() {
        analysisPipeline.clearLivePresentationState()
        if isPaused {
            pauseDisplayRenderTask?.cancel()
            pauseDisplayRenderTask = nil
            pendingPauseAnalysis = nil
            pauseFailureReason = nil
            let snapshotID = acceptedPauseSnapshot?.snapshotID
                ?? pausePresentationState.snapshotID
                ?? pauseRequestToken?.uuidString
                ?? UUID().uuidString
            isPaused = false
            pauseRequestToken = nil
            previewSuggestions = []
            pauseCritique = nil
            pausePresentationState = .resuming(snapshotID: snapshotID)
            analysisPipeline.clearPausePresentationState()
            start()
        } else {
            // A pause request owns one accepted frame and one render task. Do
            // not accept a second frame while that exact handoff is still
            // being rendered on the off-main owner.
            guard pauseDisplayRenderTask == nil else { return }

            // Accept the frame before any asynchronous stop can drain or reuse
            // the capture buffer. The live preview remains active until the
            // exact accepted pixels become display-ready; only then does this
            // owner enter pause and stop capture.
            let acceptedSnapshot = analysisPipeline.acceptPauseSnapshot()
            let token = UUID()
            pauseRequestToken = token
            acceptedPauseSnapshot = acceptedSnapshot
            acceptedPauseRequestToken = acceptedSnapshot == nil ? nil : token
            pendingPauseAnalysis = nil
            pauseFailureReason = nil
            let snapshotID = acceptedSnapshot?.snapshotID ?? token.uuidString
            pausePresentationState = .loading(snapshotID: snapshotID)
            if acceptedSnapshot != nil {
                takeNumber += 1
            }
            guard let acceptedSnapshot else {
                pauseRequestToken = nil
                pauseFailureReason = .noAcceptedEvidence
                pausePresentationState = .failure(snapshotID: snapshotID)
                return
            }

            // The copied buffer/evidence is already owned before this task. Full
            // Core Image rendering completes before pause projection or camera
            // stop, so a missing display image can never flash as the review.
            let pipeline = analysisPipeline
            pauseDisplayRenderTask = Task { [weak self, pipeline] in
                let renderedSnapshot = await pipeline.renderPauseDisplayImage(for: acceptedSnapshot)
                guard let self,
                      !self.isPaused,
                      self.pauseRequestToken == token,
                      self.acceptedPauseRequestToken == token,
                      self.acceptedPauseSnapshot?.snapshotID == acceptedSnapshot.snapshotID else { return }
                guard let renderedSnapshot else {
                    self.pauseDisplayRenderTask = nil
                    self.acceptedPauseSnapshot = nil
                    self.acceptedPauseRequestToken = nil
                    self.pauseRequestToken = nil
                    self.pauseFailureReason = .displayRenderFailed
                    self.pausePresentationState = .failure(snapshotID: acceptedSnapshot.snapshotID)
                    return
                }
                self.acceptedPauseSnapshot = renderedSnapshot
                self.pauseDisplayRenderTask = nil
                guard renderedSnapshot.displayImage != nil else { return }
                // Keep the live timecode honest while the exact accepted
                // pixels are being rendered. Freeze it only at the atomic
                // handoff that is ready to project the pause frame.
                self.timecodeSession.pause()
                self.publishNominalTimecode()
                self.isPaused = true
                self.stop()

                pipeline.runPauseAnalysisResult(acceptedSnapshot: renderedSnapshot) { [weak self] result, list, critique in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        guard self.isPaused,
                              self.pauseRequestToken == token,
                              self.acceptedPauseRequestToken == token,
                              self.acceptedPauseSnapshot?.snapshotID == acceptedSnapshot.snapshotID else { return }
                        guard result != .cancelled else { return }
                        self.pendingPauseAnalysis = PendingPauseAnalysis(
                            result: result,
                            suggestions: list,
                            critique: critique
                        )
                        self.applyPendingPauseAnalysisIfReady()
                    }
                }
            }
        }
    }

    private func applyPendingPauseAnalysisIfReady() {
        guard isPaused,
              let acceptedSnapshot = acceptedPauseSnapshot,
              acceptedSnapshot.displayImage != nil,
              let pendingPauseAnalysis else { return }

        self.pendingPauseAnalysis = nil
        previewSuggestions = pendingPauseAnalysis.suggestions
        pauseCritique = pendingPauseAnalysis.critique

        switch pendingPauseAnalysis.result {
        case .success:
            guard let critique = pendingPauseAnalysis.critique else {
                pausePresentationState = .empty(snapshotID: acceptedSnapshot.snapshotID)
                return
            }
            pauseFailureReason = nil
            pausePresentationState = .success(
                snapshotID: acceptedSnapshot.snapshotID,
                critique: critique
            )
        case .empty:
            pauseFailureReason = nil
            pausePresentationState = .empty(snapshotID: acceptedSnapshot.snapshotID)
        case .failure(let failure):
            pauseFailureReason = switch failure {
            case .noAcceptedEvidence: .noAcceptedEvidence
            case .pipelineUnavailable: .pipelineUnavailable
            case .timeout: .timeout
            }
            pausePresentationState = .failure(snapshotID: acceptedSnapshot.snapshotID)
        case .cancelled:
            break
        }
    }
    
    func switchLens(to lens: CameraLens) {
        // Invalidate the current episode before the asynchronous lens switch
        // starts. A delayed result from the old lens must not remain eligible
        // while CameraManager is changing the capture input.
        cancelCoachingEpisode(reason: .lensChange)
        lensSwitchTask?.cancel()
        let intent = UUID()
        lensSwitchIntent = intent
        lensSwitchRequestedLens = lens
        lensSwitchPresentationState = .switching(lens)
        let operation = lensSwitchOperation
        lensSwitchTask = Task { [weak self, operation] in
            let result = await operation(lens)
            guard let self,
                  !Task.isCancelled,
                  self.lensSwitchIntent == intent else { return }
            applyLensSwitchResult(result)
            lensSwitchTask = nil
        }
    }

    private func applyLensSwitchResult(_ result: CameraLensSwitchResult) {
        switch result {
        case .success(let activeLens):
            let previousLens = currentLens
            currentLens = cameraManager.activeLens ?? activeLens
            availableLenses = cameraManager.availableLenses
            lensSwitchPresentationState = .idle
            lensSwitchRequestedLens = nil
            if currentLens != previousLens {
                lensSelectionHaptic.perform(.selection)
            }
        case .noOp(let activeLens):
            currentLens = cameraManager.activeLens ?? activeLens
            availableLenses = cameraManager.availableLenses
            lensSwitchPresentationState = .idle
            lensSwitchRequestedLens = nil
        case .failure(_, let lastKnownActiveLens, let reason):
            lensSwitchPresentationState = .failed(reason)
            if let lastKnownActiveLens {
                currentLens = lastKnownActiveLens
                return
            }

            // With no manager-confirmed lens there is no safe physical input
            // to present. Clear the inventory and fall back to the neutral
            // wide label; retaining the previous selection would make the
            // HUD claim a lens that the session no longer owns.
            currentLens = .wide
            availableLenses = []
            if reason == .rollbackFailed {
                lifecycleState = cameraManager.lifecycleState
                lifecycleError = cameraManager.lifecycleError
            }
        }
    }

    private func startFeaturePolling() {
        guard featurePollingCancellable == nil else { return }
        featurePollingCancellable = Timer.publish(every: 0.3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.features = self.analysisPipeline.currentFeatures
                self.publishNominalTimecode()

                if self.debugMode {
                    let debugData = self.analysisPipeline.currentDebugData
                    self.detrDetections = debugData.detrDetections
                    self.visionSubjects = debugData.visionSubjects
                    self.saliencyCenter = debugData.saliencyCenter
                }
            }
    }

    private func stopFeaturePolling() {
        featurePollingCancellable?.cancel()
        featurePollingCancellable = nil
    }

    private func consumeCoachingEpisodeEvent(_ event: CoachingEpisodeStreamEvent) {
        // The coordinator owns the terminal-boundary rule: only a typed
        // baseline may reset a cancelled/expired episode. Frame events never
        // reopen a terminal state and never replace the frozen advice.
        let previousPhase = coachingEpisodeCoordinator.phase
        let nextState = coachingEpisodeCoordinator.consume(event)
        coachingEpisodeState = nextState

        let wasActive = previousPhase == .awaitingMovement
            || previousPhase == .collectingStableAfterFrames
        let reachedTerminal = nextState.phase == .cancelled
            || nextState.phase == .expired
        guard wasActive,
              reachedTerminal,
              let reason = nextState.cancellationReason,
              reason.permitsAutomaticRetryWithinCapture else {
            return
        }

        // The coordinator has already consumed the terminal frame. Clear the
        // pipeline owner exactly once so its next admissible sample can be a
        // fresh baseline with a new token; lifecycle boundaries use their own
        // explicit cancellation/reset path above.
        analysisPipeline.resetCoachingEpisodeAfterTerminal()
    }

    private func cancelCoachingEpisode(reason: CoachingEpisodeCancellationReason) {
        // The pipeline owns the stream identity. Invalidate it before the
        // ViewModel's local projection so an async lens result cannot reopen
        // the old episode after a no-op or failed switch.
        analysisPipeline.cancelCoachingEpisode(reason: reason)
        coachingEpisodeState = coachingEpisodeCoordinator.cancel(reason: reason)
        verificationResult = nil
    }

    private func resetCoachingEpisodeForNewCapture() {
        coachingEpisodeCoordinator.resetForRetry()
        coachingEpisodeState = .idle
        verificationResult = nil
    }

    private func applyLiveHint(_ hint: LiveHintPresentation?) {
        guard analysisStatus != .failed,
              !effectivePerformance.isLimited else {
            liveHint = nil
            plannerDecision = nil
            verificationResult = nil
            return
        }
        verificationResult = nil
        liveHint = hint
        guard let hint else {
            plannerDecision = nil
            return
        }
        plannerDecision = hint.actionType == .leaveFrameAsIs ? .keep : .correct
    }

    private func applyEffectivePerformance(_ snapshot: CameraRuntimePerformanceSnapshot) {
        effectivePerformance = snapshot

        if snapshot.isLimited {
            analysisStatus = .limited
            plannerDecision = nil
            verificationResult = nil
            clearLiveAdviceForAnalysisBoundary()
        } else if analysisStatus == .limited {
            // Returning to nominal cadence never resurrects stale advice. The
            // next valid pipeline publication must establish a fresh event.
            analysisStatus = .healthy
            plannerDecision = nil
            verificationResult = nil
        }
    }

    private func clearAnalysisFailureForNewCapture() {
        analysisFailure = nil
        analysisStatus = effectivePerformance.isLimited ? .limited : .healthy
    }

    private func clearLiveAdviceForAnalysisBoundary() {
        liveHint = nil
        overlayAnnotations = []
        subjectRegions = []
        analysisPipeline.clearLivePresentationState()
    }

    private func publishNominalTimecode() {
        nominalTimecode = CameraNominalTimecode.string(elapsed: timecodeSession.elapsed)
        nominalTimecodePublisher.publish(nominalTimecode)
    }
}
