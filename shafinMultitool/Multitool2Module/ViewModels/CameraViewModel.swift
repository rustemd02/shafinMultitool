//
//  CameraViewModel.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import Combine
import Foundation

final class CameraViewModel: ObservableObject {
    @Published var overlayState: OverlayState = .init(primaryBoundingBox: nil,
                                                      horizonAngle: 0,
                                                      horizonConfidence: 0,
                                                      saliencyBalance: 0)
    @Published var suggestion: Suggestion?
    @Published var features: CoachingFeatures = CoachingFeatures()
    @Published var debugMode: Bool = false
    @Published var isPaused: Bool = false
    @Published var previewSuggestions: [Suggestion] = []
    
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
    private var hasRegistered = false

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
        
        // Подписка на features и debug данные из pipeline через таймер
        Timer.publish(every: 0.3, on: .main, in: .common)
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
            .store(in: &cancellables)
    }

    func start() {
        if !hasRegistered {
            analysisPipeline.register(with: cameraManager)
            hasRegistered = true
        }
        cameraManager.start()
        
        // Обновляем список доступных объективов после старта
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.availableLenses = self?.cameraManager.availableLenses ?? []
        }
    }

    func stop() {
        cameraManager.stop()
    }
    
    func toggleDebug() {
        debugMode.toggle()
    }

    func togglePause() {
        if isPaused {
            isPaused = false
            cameraManager.start()
            previewSuggestions = []
        } else {
            isPaused = true
            cameraManager.stop()
            analysisPipeline.runPreviewAnalysis { [weak self] list in
                self?.previewSuggestions = list
            }
        }
    }
    
    func switchLens(to lens: CameraLens) {
        currentLens = lens
        cameraManager.switchLens(to: lens)
    }
}


