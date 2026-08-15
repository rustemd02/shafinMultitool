//
//  CameraViewModel.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import Combine
import Foundation

@MainActor
final class CameraViewModel: ObservableObject {
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
    @Published var pauseCritique: PauseCritiquePresentation?
    @Published var overlayAnnotations: [OverlayAnnotationPresentation] = []
    @Published var legacySuggestion: Suggestion?
    
    // Debug данные
    @Published var detrDetections: [DETRDetection] = []
    @Published var visionSubjects: [VisionSubject] = []
    @Published var saliencyCenter: CGPoint?
    
    // Зум/объективы
    @Published var currentLens: CameraLens = .wide
    @Published var availableLenses: [CameraLens] = []

    private let cameraManager: CameraManager
    private let analysisPipeline: AnalysisPipeline
    private var cancellables = Set<AnyCancellable>()
    private var featurePollingCancellable: AnyCancellable?
    private var pauseRequestToken: UUID?
    private var lifecycleTask: Task<Void, Never>?
    private var lifecycleIntent = UUID()
    private var releaseTask: Task<Void, Never>?

    init(cameraManager: CameraManager,
         analysisPipeline: AnalysisPipeline) {
        self.cameraManager = cameraManager
        self.analysisPipeline = analysisPipeline

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
            .assign(to: &$liveHint)

        analysisPipeline.$currentPauseCritique
            .receive(on: DispatchQueue.main)
            .assign(to: &$pauseCritique)

        analysisPipeline.$currentOverlayAnnotations
            .receive(on: DispatchQueue.main)
            .assign(to: &$overlayAnnotations)
    }

    func start() {
        let intent = beginLifecycleRequest(.starting)
        let pendingRelease = releaseTask
        lifecycleTask = Task { [weak self] in
            guard let self else { return }
            if let pendingRelease {
                await pendingRelease.value
            }
            guard !Task.isCancelled, self.lifecycleIntent == intent else { return }
            guard self.startCaptureRegistrationIfNeeded(for: intent) else {
                return
            }
            await self.performStart(intent: intent)
        }
    }

    func startAndWait() async {
        let intent = beginLifecycleRequest(.starting)
        if let releaseTask {
            await releaseTask.value
        }
        guard !Task.isCancelled, lifecycleIntent == intent else { return }
        guard startCaptureRegistrationIfNeeded(for: intent) else {
            return
        }
        await performStart(intent: intent)
    }

    func stop() {
        let intent = beginLifecycleRequest(.stopping)
        stopFeaturePolling()
        lifecycleTask = Task { [weak self] in
            guard let self else { return }
            await self.performStop(intent: intent)
        }
    }

    func stopAndWait() async {
        let intent = beginLifecycleRequest(.stopping)
        stopFeaturePolling()
        await performStop(intent: intent)
    }

    func releaseAndWait() async {
        let intent = beginLifecycleRequest(.stopping)
        stopFeaturePolling()
        pauseRequestToken = nil

        let operation: Task<Void, Never>
        if let existing = releaseTask {
            operation = existing
        } else {
            operation = Task { [weak self] in
                guard let self else { return }

                // Full release order: stop frame production, fence pipeline work and
                // registrations, then release the camera configuration.
                await self.cameraManager.stopAndWait()
                await self.analysisPipeline.releaseAndWait()
                await self.cameraManager.releaseAndWait()
            }
            releaseTask = operation
        }

        await operation.value
        if releaseTask != nil {
            releaseTask = nil
        }

        guard lifecycleIntent == intent else { return }
        isPaused = false
        previewSuggestions = []
        pauseCritique = nil
        overlayState = .init(primaryBoundingBox: nil,
                             horizonAngle: 0,
                             horizonConfidence: 0,
                             saliencyBalance: 0)
        suggestion = nil
        legacySuggestion = nil
        liveHint = nil
        overlayAnnotations = []
        lifecycleState = .idle
        lifecycleError = nil
        availableLenses = []
    }

    private func beginLifecycleRequest(_ requestedState: CameraLifecycleState) -> UUID {
        lifecycleTask?.cancel()
        let intent = UUID()
        lifecycleIntent = intent
        lifecycleState = requestedState
        lifecycleError = nil
        return intent
    }

    private func performStart(intent: UUID) async {
        do {
            try await cameraManager.startAndWait()
            guard !Task.isCancelled, lifecycleIntent == intent else { return }
            lifecycleState = .running
            lifecycleError = nil
            availableLenses = cameraManager.availableLenses
        } catch let error as CameraManagerError {
            guard !Task.isCancelled, lifecycleIntent == intent else { return }
            stopFeaturePolling()
            lifecycleState = .failed(error)
            lifecycleError = error
        } catch {
            guard !Task.isCancelled, lifecycleIntent == intent else { return }
            stopFeaturePolling()
            let typedError = CameraManagerError.startFailed
            lifecycleState = .failed(typedError)
            lifecycleError = typedError
        }
    }

    private func performStop(intent: UUID) async {
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

    func togglePause() {
        analysisPipeline.clearLivePresentationState()
        if isPaused {
            isPaused = false
            pauseRequestToken = nil
            start()
            previewSuggestions = []
            pauseCritique = nil
            analysisPipeline.clearPausePresentationState()
        } else {
            isPaused = true
            let token = UUID()
            pauseRequestToken = token
            stop()
            analysisPipeline.runPauseAnalysis { [weak self] list, critique in
                guard let self else { return }
                guard self.isPaused, self.pauseRequestToken == token else { return }
                self.previewSuggestions = list
                self.pauseCritique = critique
            }
        }
    }
    
    func switchLens(to lens: CameraLens) {
        currentLens = lens
        cameraManager.switchLens(to: lens)
    }

    private func startFeaturePolling() {
        guard featurePollingCancellable == nil else { return }
        featurePollingCancellable = Timer.publish(every: 0.3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.features = self.analysisPipeline.currentFeatures

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
}
