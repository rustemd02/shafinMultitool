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

    private struct RuntimeAnalysisFailureEvent {
        let failure: CameraAnalysisFailure
        let generation: UInt64?
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
    /// CC-I05: style cue awaiting the user's yes/no answer (nil when none).
    @Published private(set) var pendingIntentClarificationCue: CameraStyleCue?
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
    @Published private(set) var proControlsSnapshot: CameraProControlsSnapshot?
    @Published private(set) var proControlError: CameraProControlError?
    @Published private(set) var isApplyingProControl = false
    @Published private(set) var isFocusingProControl = false
    @Published private(set) var isFocusPointSelectionActive = false
    @Published private(set) var proAudioLevel: Float?
    @Published private(set) var proAudioMeterEnabled = false
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

    /// The episode token and baseline geometry are the only runtime marker
    /// identity/geometry inputs. A transient live hint or current detector
    /// rectangle cannot replace them once an episode has started.
    var coachingEpisodeEventID: String? {
        coachingEpisodeState.token?.rawValue.uuidString
    }

    var coachingEpisodePreviewGeometry: CoachingEpisodePreviewGeometry {
        CoachingEpisodeCoordinator.previewGeometry(
            for: coachingEpisodeState,
            actionID: liveHint?.coachingEpisodeActionID,
            subjectIdentity: liveHint?.subjectIdentity,
            observedSourceRegion: liveHint?.observedSourceRegion,
            targetRegion: liveHint?.targetRegion
        )
    }

    var coachingEpisodeSubjectRegion: NormalizedRect? {
        coachingEpisodePreviewGeometry.subjectRegion
    }

    var coachingEpisodeTargetRegion: NormalizedRect? {
        coachingEpisodePreviewGeometry.targetRegion
    }

    var isPauseProjectionReady: Bool {
        isPaused && acceptedPauseSnapshot?.displayImage != nil
    }

    /// A failed resume is a camera lifecycle failure, not a pause-analysis
    /// failure. The accepted review remains retryable and inspectable while
    /// the lifecycle reports the typed start error.
    var isResumeStartFailure: Bool {
        guard isPaused,
              lifecycleState == .failed(.startFailed),
              case .failure(let snapshotID) = pausePresentationState,
              acceptedPauseSnapshot?.snapshotID == snapshotID else { return false }
        return acceptedPauseSnapshot?.displayImage != nil
    }

    /// A background transition may preserve the review only after the
    /// terminal pause result has been committed alongside the accepted image.
    /// A display-ready frame that is still loading remains cancelable work.
    private var isPauseReviewCommitted: Bool {
        guard isPauseProjectionReady else { return false }
        switch pausePresentationState {
        case .success, .empty, .failure:
            return true
        case .idle, .loading, .resuming:
            return false
        }
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
    /// Generation/token fence for the one automatic verifier handoff. A ready
    /// event may be replayed by Combine, but one immutable pair is verified
    /// only once for its episode identity.
    private var automaticallyVerifiedEpisodeToken: CoachingEpisodeToken?

    private let cameraManager: CameraManager
    private let analysisPipeline: AnalysisPipeline
    /// The shared recording owner uses CameraManager's raw capture feed. Tests
    /// that exercise analysis alone do not create persistence or microphone work.
    @Published private(set) var recordingCoordinator: CameraCoachRecordingCoordinator?
    @Published private(set) var recordingInitializationFailed = false
    private let recordingCoordinatorFactory: (@MainActor () throws -> CameraCoachRecordingCoordinator)?
    private var recordingStopTask: Task<Void, Never>?
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
    private var proControlTask: Task<Void, Never>?
    private var proControlIntent = UUID()
    /// A route exit is terminal for this Camera Coach instance. The shell owns
    /// the replacement route, so a late view/presentation callback must not
    /// restart capture after this owner has begun releasing its session.
    private var routeExitRequested = false
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
         performanceStore: CameraRuntimePerformanceStore = .shared,
         recordingCoordinator: CameraCoachRecordingCoordinator? = nil,
         recordingCoordinatorFactory: (@MainActor () throws -> CameraCoachRecordingCoordinator)? = nil) {
        self.cameraManager = cameraManager
        self.analysisPipeline = analysisPipeline
        self.recordingCoordinator = recordingCoordinator
        self.recordingCoordinatorFactory = recordingCoordinatorFactory
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

        analysisPipeline.$pendingIntentClarificationCue
            .receive(on: DispatchQueue.main)
            .assign(to: &$pendingIntentClarificationCue)

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

        cameraManager.proControlsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard let self, !self.routeExitRequested else { return }
                self.proControlsSnapshot = snapshot
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
            .compactMap { notification -> RuntimeAnalysisFailureEvent? in
                guard let failure = notification.userInfo?[CameraAnalysisRuntimeSignal.failureUserInfoKey]
                    as? CameraAnalysisFailure else { return nil }
                return RuntimeAnalysisFailureEvent(
                    failure: failure,
                    generation: notification.userInfo?[CameraAnalysisRuntimeSignal.generationUserInfoKey] as? UInt64
                )
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (event: RuntimeAnalysisFailureEvent) in
                self?.reportAnalysisFailure(event.failure, generation: event.generation)
            }
            .store(in: &cancellables)

        if recordingCoordinator != nil { observeRecordingCoordinator() }
        else { retryRecordingPreparation() }
    }

    func retryRecordingPreparation() {
        guard !routeExitRequested, recordingCoordinator == nil,
              let recordingCoordinatorFactory else { return }
        do {
            recordingCoordinator = try recordingCoordinatorFactory()
            recordingInitializationFailed = false
            observeRecordingCoordinator()
        } catch {
            recordingInitializationFailed = true
        }
    }

    private func observeRecordingCoordinator() {
        guard let recordingCoordinator else { return }
        recordingCoordinator.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        recordingCoordinator.$meterEnabled.assign(to: &$proAudioMeterEnabled)
    }

    func start() {
        guard !routeExitRequested else { return }
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
        guard !routeExitRequested else { return }
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

    /// Closes the Camera Coach restart boundary before route teardown begins.
    /// This is intentionally separate from ordinary `releaseAndWait()`: a
    /// normal release may be followed by a user retry, while a route release
    /// must leave the old child unable to reacquire the camera.
    func beginRouteExit() {
        guard !routeExitRequested else { return }
        routeExitRequested = true
        invalidateProControlPresentation()

        lifecycleTask?.cancel()
        lifecycleTask = nil
        lensSwitchTask?.cancel()
        lensSwitchTask = nil
        lensSwitchIntent = UUID()
        lifecycleIntent = UUID()

        cancelCoachingEpisode(reason: .routeExit)
        stopFeaturePolling()
        clearPresentationProjection()
        lifecycleState = .stopping
        lifecycleError = nil
    }

    /// The production surface calls this for a non-active scene. AVFoundation
    /// does not guarantee that every background transition emits its own
    /// interruption notification.
    func reportSceneInactive() {
        guard hasActiveCaptureOrPauseWork else { return }
        // Keep a committed accepted frame/review intact across scene changes.
        // The user resumes explicitly; no camera restart is attempted while
        // the scene is inactive.
        if isPauseReviewCommitted {
            return
        }
        cancelCoachingEpisode(reason: .background)
        if lifecycleState == .starting || lifecycleState == .running {
            cameraManager.reportSessionInterrupted()
        }
        handleCameraFailure(.sessionInterrupted)
    }

    /// The UIKit scene adapter awaits writer finalization and persistence under
    /// its existing background task before releasing the capture graph.
    func handleSceneDidEnterBackground() async {
        await recordingCoordinator?.handleBackground()
        reportSceneInactive()
        if let releaseOperation { await awaitReleaseOperation(releaseOperation) }
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

            // Close recording admission and await finalize/save before capture
            // teardown. A camera failure remains retryable; route exit is terminal.
            await self.finishRecordingBeforeCaptureStop()
            if self.routeExitRequested {
                _ = await self.recordingCoordinator?.releaseAndWait(reason: .routeExit)
            }
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
        // An idempotent start keeps the same physical session and pending
        // device operation. Preserve its waiter/progress, including another
        // start arriving while the first start waiter is being scheduled.
        if requestedState != .starting || cameraManager.lifecycleState != .running {
            invalidateProControlPresentation()
        }
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
            // Pause enters stopping before its terminal result is committed.
            // Keep that in-flight review visible to the lifecycle boundary so
            // a scene transition cancels/fails it instead of silently letting
            // late output publish after backgrounding.
            return isPaused
                || isPauseCapturePending
                || acceptedPauseSnapshot != nil
                || pausePresentationState != .idle
        }
    }

    private func handleCameraFailure(_ error: CameraManagerError) {
        guard hasActiveCaptureOrPauseWork else { return }
        // A display-ready pause is a committed review. Camera is already
        // stopped at this boundary, so an interruption notification must not
        // erase the accepted pixels or their review while the scene is away.
        if isPauseReviewCommitted {
            return
        }

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
        invalidateProControlPresentation()
        proControlsSnapshot = nil
        proAudioMeterEnabled = false
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
        automaticallyVerifiedEpisodeToken = nil
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
        if let recordingStopTask { await recordingStopTask.value }
        guard !Task.isCancelled, lifecycleIntent == intent else { return }
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
                analysisPipeline.clearPausePresentationState()
                pausePresentationState = .idle
                acceptedPauseSnapshot = nil
                acceptedPauseRequestToken = nil
                pendingPauseAnalysis = nil
                pauseCritique = nil
                previewSuggestions = []
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
            restorePauseReviewAfterResumeFailureIfNeeded()
            lifecycleState = .failed(error)
            lifecycleError = error
        } catch {
            guard lifecycleIntent == intent else { return }
            stopFeaturePolling()
            let rollback = makeFailedStartRollback()
            await awaitFailedStartRollback(rollback)
            guard !Task.isCancelled, lifecycleIntent == intent else { return }
            restorePauseReviewAfterResumeFailureIfNeeded()
            let typedError = CameraManagerError.startFailed
            lifecycleState = .failed(typedError)
            lifecycleError = typedError
        }
    }

    /// A failed resume must not strand an accepted review behind `.resuming`.
    /// The camera lifecycle reports the start failure separately, while the
    /// accepted pixels and critique remain inspectable and can be retried.
    private func restorePauseReviewAfterResumeFailureIfNeeded() {
        guard case .resuming(let snapshotID) = pausePresentationState,
              let acceptedPauseSnapshot,
              acceptedPauseSnapshot.snapshotID == snapshotID,
              acceptedPauseSnapshot.displayImage != nil else { return }

        isPaused = true
        pausePresentationState = .failure(snapshotID: snapshotID)
    }

    private func makeFailedStartRollback() -> FailedStartRollbackOperation {
        if let failedStartRollbackOperation {
            return failedStartRollbackOperation
        }

        nextFailedStartRollbackGeneration &+= 1
        let generation = nextFailedStartRollbackGeneration
        let pipeline = analysisPipeline
        let task = Task {
            await pipeline.releaseAndWait(preservingCurrentPauseReview: true)
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
        await finishRecordingBeforeCaptureStop()
        guard !Task.isCancelled, lifecycleIntent == intent else { return }
        await cameraManager.stopAndWait()
        guard !Task.isCancelled, lifecycleIntent == intent else { return }
        lifecycleState = cameraManager.lifecycleState
        lifecycleError = cameraManager.lifecycleError
    }

    private func finishRecordingBeforeCaptureStop() async {
        if let recordingStopTask { await recordingStopTask.value; return }
        guard let recordingCoordinator else { return }
        let task = Task { @MainActor in
            await recordingCoordinator.suspendAndWait(reason: .interruption)
        }
        recordingStopTask = task
        await task.value
        recordingStopTask = nil
    }

    var hasActiveRecording: Bool {
        guard let phase = recordingCoordinator?.phase else { return false }
        return phase == .preparing || phase == .recording || phase == .finalizing || phase == .saving
    }

    var canStartRecording: Bool {
        lifecycleState == .running && !routeExitRequested && !isPaused
            && !isPauseCapturePending && !lensSwitchPresentationState.isSwitching
            && !isApplyingProControl && !hasActiveRecording && recordingStopTask == nil
            && proControlsSnapshot != nil
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
        guard coachingEpisodeState.phase == .readyForVerification,
              coachingEpisodeState.token == result.token else { return false }
        verificationResult = result
        if case .incomparable = result.decision {
            // Incomparable is a terminal result for this episode, not a route
            // boundary. Hide frame-local markers while retaining the token so
            // the projection can offer an explicit next-cycle action.
            liveHint = nil
            plannerDecision = nil
            overlayAnnotations = []
            subjectRegions = []
            analysisStatus = effectivePerformance.isLimited ? .limited : .healthy
        }
        return true
    }

    /// Starts the next bounded capture cycle only from the visible terminal
    /// result that owns `token`. A stale button action, lifecycle transition or
    /// newer pipeline baseline cannot clear the active capture transaction.
    @discardableResult
    /// CC-I05: records the user's answer for the pending style cue; a
    /// confirmed intent suppresses the conflicting corrections for the session.
    func answerIntentClarification(intended: Bool) {
        analysisPipeline.answerIntentClarification(intended: intended)
    }

    func continueCoaching(after token: CoachingEpisodeToken) -> Bool {
        guard !routeExitRequested,
              lifecycleState == .running,
              pausePresentationState == .idle,
              lensSwitchPresentationState == .idle,
              analysisStatus == .healthy,
              !effectivePerformance.isLimited,
              coachingEpisodeState.phase == .readyForVerification,
              coachingEpisodeState.token == token,
              let verificationResult,
              verificationResult.token == token,
              let baseline = coachingEpisodeState.baseline else {
            return false
        }

        guard analysisPipeline.resetCoachingEpisodeAfterTerminal(
            expectedBaselineFrameID: baseline.frameID,
            expectedCaptureGeneration: baseline.captureGeneration
        ) else {
            return false
        }

        liveHint = nil
        plannerDecision = nil
        overlayAnnotations = []
        subjectRegions = []
        resetCoachingEpisodeForNewCapture()
        return true
    }

#if DEBUG
    /// Test-only read seam for the exact immutable pair owned by the live
    /// coordinator. Production callers still receive verification only via
    /// `applyVerificationResult`; tests must not reconstruct a token or pair.
    var testingVerificationInput: ActionVerificationInput? {
        coachingEpisodeCoordinator.verificationInput
    }
#endif

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
    func reportAnalysisFailure(_ failure: CameraAnalysisFailure = .failed,
                               generation: UInt64? = nil) {
        if let generation {
            guard lifecycleState == .starting || lifecycleState == .running,
                  analysisPipeline.acceptsRuntimeSignal(generation: generation) else {
                return
            }
        }
        analysisFailure = failure
        analysisStatus = .failed
        plannerDecision = nil
        verificationResult = nil
        clearLiveAdviceForAnalysisBoundary()
    }

    /// CC-O02: the operator tapped the live preview at a scene-space point.
    /// Forwards to the pipeline, which resolves the naming against tracked
    /// instances when the next advice pass evaluates the quality gate.
    func handleSceneTap(sceneX: Double, sceneY: Double) {
        analysisPipeline.handleSceneTap(normalizedX: sceneX, normalizedY: sceneY)
    }

    func togglePause() {
        guard !routeExitRequested, !hasActiveRecording else { return }
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
            // Keep the accepted review recoverable while the same configured
            // session attempts to restart. A successful start clears it at
            // the restart commit boundary; failure leaves it inspectable.
            pausePresentationState = .resuming(snapshotID: snapshotID)
            analysisPipeline.clearPausePresentationState(preservingCurrentCritique: true)
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
        guard !routeExitRequested else { return }
        guard !hasActiveRecording else {
            lensSwitchPresentationState = .failed(.recordingInProgress)
            return
        }
        invalidateProControlPresentation()
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

    var canApplyProControl: Bool {
        lifecycleState == .running && !routeExitRequested && !isPaused
            && !isPauseCapturePending && !lensSwitchPresentationState.isSwitching
            && !isApplyingProControl && !hasActiveRecording && proControlsSnapshot != nil
    }

    /// Called by the panel's SwiftUI task; closing it cancels this bounded
    /// readback loop. The device is sampled on its existing session queue.
    func observeProControlsWhilePresented() async {
        while !Task.isCancelled, !routeExitRequested, lifecycleState == .running {
            let snapshot = await cameraManager.proControlsSnapshotAndWait()
            guard !Task.isCancelled, !routeExitRequested else { return }
            proControlsSnapshot = snapshot
            proAudioLevel = cameraManager.audioLevel
            do { try await Task.sleep(for: .milliseconds(500)) }
            catch { return }
        }
    }

    func applyProControl(_ command: CameraProControlCommand) {
        guard canApplyProControl, let snapshot = proControlsSnapshot else {
            proControlError = .unavailable
            return
        }
        isFocusPointSelectionActive = false
        proControlError = nil
        isApplyingProControl = true
        if case .focusPoint = command { isFocusingProControl = true }
        let intent = UUID()
        proControlIntent = intent
        // Controls alter the evidence used by the current coaching episode.
        // CameraManager advances the capture generation before native apply.
        cancelCoachingEpisode(reason: .cameraGenerationChange)
        clearLiveAdviceForAnalysisBoundary()
        proControlTask = Task { [weak self, cameraManager] in
            let result = await cameraManager.applyProControl(
                command, expectedDeviceID: snapshot.deviceID,
                expectedCaptureGeneration: snapshot.captureGeneration
            )
            let observed = await cameraManager.proControlsSnapshotAndWait()
            guard let self, !Task.isCancelled, self.proControlIntent == intent,
                  !self.routeExitRequested else { return }
            self.proControlsSnapshot = observed
            self.isApplyingProControl = false
            self.isFocusingProControl = false
            self.proControlTask = nil
            if case .failure(let error) = result { self.proControlError = error }
        }
    }

    func beginProFocusPointSelection() {
        guard canApplyProControl, proControlsSnapshot?.capabilities.tapFocusLock == true else { return }
        proControlError = nil
        isFocusPointSelectionActive = true
    }

    func cancelProFocusPointSelection() { isFocusPointSelectionActive = false }

    func handleProFocusPoint(_ devicePoint: CGPoint) {
        guard isFocusPointSelectionActive else { return }
        isFocusPointSelectionActive = false
        applyProControl(.focusPoint(devicePoint))
    }

    func enableProAudioMeter() {
        setProAudioMeterEnabled(true)
    }

    private func setProAudioMeterEnabled(_ enabled: Bool) {
        guard canApplyProControl else { return }
        guard let recordingCoordinator else { proControlError = .unavailable; return }
        proControlError = nil
        isApplyingProControl = true
        let intent = UUID()
        proControlIntent = intent
        proControlTask = Task { [weak self, recordingCoordinator] in
            await recordingCoordinator.setMeterEnabled(enabled)
            guard let self, !Task.isCancelled, self.proControlIntent == intent,
                  !self.routeExitRequested else { return }
            self.isApplyingProControl = false
            self.proControlTask = nil
            self.proAudioMeterEnabled = recordingCoordinator.meterEnabled
            if recordingCoordinator.meterEnabled != enabled {
                switch recordingCoordinator.issue {
                case .permission: self.proControlError = .microphoneDenied
                case .busy: self.proControlError = .busy
                default: self.proControlError = .unavailable
                }
            }
        }
    }

    private func invalidateProControlPresentation() {
        proControlIntent = UUID()
        proControlTask?.cancel()
        proControlTask = nil
        isApplyingProControl = false
        isFocusingProControl = false
        isFocusPointSelectionActive = false
        proControlError = nil
        proAudioLevel = nil
    }

    func disableProAudioMeter() {
        setProAudioMeterEnabled(false)
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
        let previousToken = coachingEpisodeCoordinator.episodeToken
        // Capture the consumed baseline before the coordinator advances. The
        // subscriber may run after a newer baseline has already been prepared
        // by the capture owner, so reading coachingEpisodeState afterwards
        // would fence against the wrong transaction.
        let consumedBaseline = coachingEpisodeState.baseline
        let nextState = coachingEpisodeCoordinator.consume(event)
        coachingEpisodeState = nextState

        if case .baseline = event,
           previousToken != nextState.token {
            // A fresh baseline owns a new immutable pair. Any result from the
            // prior token is stale even if a live hint arrives in the same
            // main-actor turn.
            verificationResult = nil
            automaticallyVerifiedEpisodeToken = nil
        }

        if previousPhase != .readyForVerification,
           nextState.phase == .readyForVerification,
           let token = nextState.token,
           token.generation != 0,
           automaticallyVerifiedEpisodeToken != token,
           let input = coachingEpisodeCoordinator.verificationInput,
           input.token == token {
            // The ViewModel is the production presentation owner. Verify the
            // coordinator's immutable before/after pair exactly once after
            // the generation-fenced ready transition; no test/manual seam is
            // involved in this path.
            automaticallyVerifiedEpisodeToken = token
            _ = applyVerificationResult(ActionVerifier.verify(input))
        }

        if nextState.phase == .cancelled || nextState.phase == .expired {
            verificationResult = nil
            automaticallyVerifiedEpisodeToken = nil
        }

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
        // The stream event may be deferred on the main queue. Fence the
        // pipeline reset to the baseline that this coordinator transition
        // consumed so an older terminal callback cannot clear a newer
        // baseline already prepared by the capture owner.
        guard let consumedBaseline else { return }
        analysisPipeline.resetCoachingEpisodeAfterTerminal(
            expectedBaselineFrameID: consumedBaseline.frameID,
            expectedCaptureGeneration: consumedBaseline.captureGeneration
        )
    }

    private func cancelCoachingEpisode(reason: CoachingEpisodeCancellationReason) {
        // The pipeline owns the stream identity. Invalidate it before the
        // ViewModel's local projection so an async lens result cannot reopen
        // the old episode after a no-op or failed switch.
        analysisPipeline.cancelCoachingEpisode(reason: reason)
        coachingEpisodeState = coachingEpisodeCoordinator.cancel(reason: reason)
        verificationResult = nil
        automaticallyVerifiedEpisodeToken = nil
    }

    private func resetCoachingEpisodeForNewCapture() {
        coachingEpisodeCoordinator.resetForRetry()
        coachingEpisodeState = .idle
        verificationResult = nil
        automaticallyVerifiedEpisodeToken = nil
    }

    private func applyLiveHint(_ hint: LiveHintPresentation?) {
        guard analysisStatus != .failed,
              !effectivePerformance.isLimited else {
            liveHint = nil
            plannerDecision = nil
            verificationResult = nil
            return
        }
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
