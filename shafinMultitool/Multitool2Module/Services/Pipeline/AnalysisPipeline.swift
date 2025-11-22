//
//  AnalysisPipeline.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import Combine
import CoreGraphics
import CoreMedia
import Foundation
import Vision
import QuartzCore
import os.log

struct OverlayState {
    var primaryBoundingBox: CGRect?
    var horizonAngle: CGFloat
    var horizonConfidence: CGFloat
    var saliencyBalance: CGFloat
}

struct DebugData {
    var detrDetections: [DETRDetection] = []
    var visionSubjects: [VisionSubject] = []
    var saliencyCenter: CGPoint?
}

final class AnalysisPipeline: ObservableObject {
    @Published private(set) var overlayState = OverlayState(primaryBoundingBox: nil,
                                                            horizonAngle: 0,
                                                            horizonConfidence: 0,
                                                            saliencyBalance: 0)
    @Published private(set) var currentSuggestion: Suggestion?

    private let visionTracking = VisionTracking()
    private let horizonEstimator = HorizonEstimator()
    private let lightingEstimator = LightingEstimator()
    private let detrDetector = try? DETRDetector()
    private let aestheticScorer = AestheticScorer()
    private let suggestionEngine = SuggestionEngine()

    private let highQueue = DispatchQueue(label: "AnalysisPipeline.high", qos: .userInitiated)
    private let mediumQueue = DispatchQueue(label: "AnalysisPipeline.medium", qos: .userInitiated)
    private let lowQueue = DispatchQueue(label: "AnalysisPipeline.low", qos: .utility)

    private var features = CoachingFeatures()
    private var debugData = DebugData()
    private let featureQueue = DispatchQueue(label: "AnalysisPipeline.features")
    private var lastPixelBuffer: CVPixelBuffer?
    private var lastOrientation: CGImagePropertyOrientation = .right
    private var suggestionExpiry: Date = .distantPast
    private var lastAestheticRequest: Date = .distantPast
    private var lastDETRRequest: Date = .distantPast
    private var lowFrameCount: Int = 0

    private var suggestionCancellable: AnyCancellable?
    
    var currentFeatures: CoachingFeatures {
        featureQueue.sync { features }
    }
    
    var currentDebugData: DebugData {
        featureQueue.sync { debugData }
    }

    private lazy var highConsumer = HighStream(pipeline: self)
    private lazy var mediumConsumer = MediumStream(pipeline: self)
    private lazy var lowConsumer = LowStream(pipeline: self)

    private var registrations: [UUID] = []

    func register(with manager: CameraManager) {
        registrations = [
            manager.register(consumer: highConsumer, priority: .high, targetFrequency: 15),
            manager.register(consumer: mediumConsumer, priority: .medium, targetFrequency: 8),
            manager.register(consumer: lowConsumer, priority: .low, targetFrequency: 0.8, requiresStability: true)
        ]
    }

    fileprivate func handleHigh(context: FrameContext) {
        highQueue.async { [weak self] in
            guard let self else { return }
            self.performHigh(context: context)
        }
    }

    fileprivate func handleMedium(context: FrameContext) {
        mediumQueue.async { [weak self] in
            guard let self else { return }
            self.performMedium(context: context)
        }
    }

    fileprivate func handleLow(context: FrameContext) {
        lowQueue.async { [weak self] in
            guard let self else { return }
            self.performLow(context: context)
        }
    }

    private func performHigh(context: FrameContext) {
        // Запомним последний кадр для режима предпросмотра
        self.lastPixelBuffer = context.pixelBuffer
        self.lastOrientation = context.orientation
        let startTime = CACurrentMediaTime()
        
        Telemetry.shared.setActiveModule("Vision", active: true)
        let trackingResult = visionTracking.process(pixelBuffer: context.pixelBuffer,
                                                    orientation: context.orientation)
        let visionLatency = CACurrentMediaTime() - startTime
        Telemetry.shared.recordLatency(label: "Vision", duration: visionLatency)
        Telemetry.shared.setActiveModule("Vision", active: false)

        let bestSubject = trackingResult.subjects.sorted { $0.confidence > $1.confidence }.first
        
        // Обновляем debug данные (Vision)
        featureQueue.async { [weak self] in
            self?.debugData.visionSubjects = trackingResult.subjects.map { subject in
                VisionSubject(boundingBox: subject.boundingBox, isFace: subject.isFace, confidence: subject.confidence)
            }
            self?.debugData.saliencyCenter = trackingResult.saliencyCenter
        }
        
        let horizonStart = CACurrentMediaTime()
        Telemetry.shared.setActiveModule("Horizon", active: true)
        let horizon = horizonEstimator.estimate(pixelBuffer: context.pixelBuffer,
                                               orientation: context.orientation,
                                               isStable: context.isStable)
        let horizonLatency = CACurrentMediaTime() - horizonStart
        Telemetry.shared.recordLatency(label: "Horizon", duration: horizonLatency)
        Telemetry.shared.setActiveModule("Horizon", active: false)

        let saliencyBalance = computeSaliencyBalance(from: bestSubject?.boundingBox ?? .zero,
                                                    saliencyCenter: trackingResult.saliencyCenter)

        updateFeatures { features in
            features.horizon.angle = horizon.angle
            features.horizon.confidence = horizon.confidence
            features.motion.shakeLevel = CGFloat(context.shakeLevel)
            features.motion.state = context.motionState
            if let subject = bestSubject {
                features.composition = self.compositionFeatures(from: subject.boundingBox)
                features.composition.saliencyLeftRightBalance = saliencyBalance
                features.composition.subjectAreaRatio = subject.boundingBox.width * subject.boundingBox.height
                features.lensRecommendation = self.lensRecommendation(for: subject.boundingBox)
                features.subject.isFace = subject.isFace
                features.subject.isPerson = true
                features.subject.count = trackingResult.personCount
            } else if let sCenter = trackingResult.saliencyCenter {
                features.composition = self.compositionFeatures(fromSaliency: sCenter)
                features.subject.isFace = false
                features.subject.isPerson = false
                features.subject.count = 0
            }
        }
        
        Telemetry.shared.setCameraStable(context.isStable, shakeLevel: context.shakeLevel)

        Task { @MainActor in
            self.overlayState = OverlayState(primaryBoundingBox: bestSubject?.boundingBox,
                                             horizonAngle: horizon.angle,
                                             horizonConfidence: horizon.confidence,
                                             saliencyBalance: saliencyBalance)
            await self.emitSuggestion()
        }

        Telemetry.shared.recordFrameProcessed()
    }

    private func performMedium(context: FrameContext) {
        guard let bbox = overlayState.primaryBoundingBox else { return }
        
        let startTime = CACurrentMediaTime()
        Telemetry.shared.setActiveModule("Lighting", active: true)
        let lighting = lightingEstimator.analyse(pixelBuffer: context.pixelBuffer,
                                                 subjectBoundingBox: bbox)
        let lightingLatency = CACurrentMediaTime() - startTime
        Telemetry.shared.recordLatency(label: "Lighting", duration: lightingLatency)
        Telemetry.shared.setActiveModule("Lighting", active: false)

        updateFeatures { features in
            features.lighting.backlightIndex = lighting.backlightIndex
            features.lighting.keyToFillRatio = lighting.keyFillRatio
            features.lighting.exposureBiasHint = lighting.exposureBiasHint
        }

        Task { @MainActor in
            await self.emitSuggestion()
        }
    }

    private func performLow(context: FrameContext) {
        lowFrameCount += 1
        let now = Date()

        // DETR object detection каждые 0.5 сек
        let timeSinceLastDETR = now.timeIntervalSince(lastDETRRequest)
        let hasDetector = detrDetector != nil

        // Логируем каждые 30 фреймов (~2 сек)
        if lowFrameCount % 30 == 0 {
            os_log("🔥 DETR: time=%.1fs (need>0.5) detector=%d",
                   log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
                   type: .info,
                   timeSinceLastDETR, hasDetector)
        }

        // Запускаем DETR каждые 0.5 сек
        if timeSinceLastDETR > 0.5,
           let detector = detrDetector {

            os_log("🚀 DETR: Starting detection...",
                   log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
                   type: .info)

            lastDETRRequest = now
            let detrStart = CACurrentMediaTime()
            Telemetry.shared.setActiveModule("DETR", active: true)

            detector.detect(pixelBuffer: context.pixelBuffer,
                             orientation: context.orientation) { [weak self] detections in
                let detrLatency = CACurrentMediaTime() - detrStart
                Telemetry.shared.recordLatency(label: "DETR", duration: detrLatency)
                Telemetry.shared.setActiveModule("DETR", active: false)

                os_log("✅ DETR callback: %d detections received in %.0fms",
                       log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
                       type: .info, detections.count, detrLatency * 1000)

                guard let self else { return }

                // Обновляем debug данные (DETR)
                self.featureQueue.async {
                    self.debugData.detrDetections = detections
                }

                // Берём объект с максимальной confidence
                if let top = detections.sorted(by: { $0.confidence > $1.confidence }).first {
                    os_log("🎯 DETR PRIORITY: Using %{public}@ (conf=%.2f) for composition",
                           log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
                           type: .info, top.label, top.confidence)

                    self.updateFeatures { features in
                        features.composition = self.compositionFeatures(from: top.boundingBox)
                        features.composition.subjectAreaRatio = top.boundingBox.width * top.boundingBox.height
                        features.subject.objectName = top.label
                        features.subject.isFace = (top.label.lowercased() == "person")
                        features.subject.isPerson = (top.label.lowercased() == "person")
                        features.subject.count = detections.count
                    }
                    Task { @MainActor in
                        self.overlayState.primaryBoundingBox = top.boundingBox
                        await self.emitSuggestion()
                    }
                }
            }
        }

        // Aesthetic каждые 2 сек
        if now.timeIntervalSince(lastAestheticRequest) > 2.0 {
            lastAestheticRequest = now
            let aestheticStart = CACurrentMediaTime()
            Telemetry.shared.setActiveModule("Aesthetic", active: true)
            aestheticScorer.score(pixelBuffer: context.pixelBuffer,
                                   orientation: context.orientation) { [weak self] score in
                let aestheticLatency = CACurrentMediaTime() - aestheticStart
                Telemetry.shared.recordLatency(label: "Aesthetic", duration: aestheticLatency)
                Telemetry.shared.setActiveModule("Aesthetic", active: false)

                guard let self, let score else { return }
                os_log("🎨 Aesthetic score: %.2f (in %.0fms)",
                       log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
                       type: .info, score, aestheticLatency * 1000)

                // Обновляем Debug Overlay
                Telemetry.shared.setAestheticScore(score)

                self.updateFeatures { features in
                    features.aestheticScore = CGFloat(score)
                }
            }
        }
    }

    @MainActor
    private func emitSuggestion() async {
        let now = Date()
        let localFeatures = featureQueue.sync { features }
        
        // Если камера движется - немедленно убираем подсказку
        if localFeatures.motion.state != .still {
            if currentSuggestion != nil {
                os_log("🚫 Hiding suggestion (camera %{public}@)", 
                       log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
                       type: .info, String(describing: localFeatures.motion.state))
                currentSuggestion = nil
            }
            return
        }
        
        if let pick = suggestionEngine.nextSuggestion(from: localFeatures) {
            currentSuggestion = pick
            suggestionExpiry = now.addingTimeInterval(pick.ttl)
            Telemetry.shared.recordSuggestion(pick)
        } else {
            // Нет новой подсказки — удерживаем прежнюю до TTL
            if now > suggestionExpiry {
                currentSuggestion = nil
            }
        }
    }

    // Полный прогон heavy‑модулей на последнем кадре; возвращает список подсказок.
    func runPreviewAnalysis(completion: @escaping ([Suggestion]) -> Void) {
        guard let pixelBuffer = lastPixelBuffer else {
            completion([])
            return
        }
        let orientation = lastOrientation
        lowQueue.async { [weak self] in
            guard let self else { return }
            var localFeatures = self.featureQueue.sync { self.features }

            let group = DispatchGroup()

            // Если нет bbox, попробуем DETR
            if localFeatures.composition.subjectAreaRatio == 0 {
                group.enter()
                self.detrDetector?.detect(pixelBuffer: pixelBuffer, orientation: orientation) { detections in
                    if let top = detections.sorted(by: { $0.confidence > $1.confidence }).first {
                        localFeatures.composition = self.compositionFeatures(from: top.boundingBox)
                        localFeatures.composition.subjectAreaRatio = top.boundingBox.width * top.boundingBox.height
                        localFeatures.subject.objectName = top.label
                    }
                    group.leave()
                }
            }

            // Эстетика (off‑by‑default в live, но в preview считаем)
            group.enter()
            self.aestheticScorer.score(pixelBuffer: pixelBuffer, orientation: orientation) { score in
                if let score {
                    localFeatures.composition.saliencyTopBottomBalance = CGFloat(score / 10.0)
                }
                group.leave()
            }

            group.notify(queue: .main) {
                let list = self.suggestionEngine.rankedSuggestions(from: localFeatures, topN: 6)
                completion(list)
            }
        }
    }

    private func updateFeatures(_ block: (inout CoachingFeatures) -> Void) {
        featureQueue.sync {
            block(&features)
        }
    }

    private func computationCenter(from boundingBox: CGRect) -> CGPoint {
        CGPoint(x: boundingBox.midX, y: boundingBox.midY)
    }

    private func compositionFeatures(from boundingBox: CGRect) -> CoachingFeatures.Composition {
        let center = computationCenter(from: boundingBox)
        var composition = CoachingFeatures.Composition()
        composition.horizontalOffset = CGFloat((center.x - 0.5) / 0.5)
        composition.verticalOffset = CGFloat((center.y - 0.333) / 0.333)
        composition.subjectAreaRatio = boundingBox.width * boundingBox.height
        return composition
    }

    private func computeSaliencyBalance(from boundingBox: CGRect, saliencyCenter: CGPoint?) -> CGFloat {
        if let saliencyCenter {
            return (saliencyCenter.x - 0.5) * 2.0
        } else {
            let center = computationCenter(from: boundingBox)
            return (center.x - 0.5) * 2.0
        }
    }

    private func compositionFeatures(fromSaliency center: CGPoint) -> CoachingFeatures.Composition {
        var composition = CoachingFeatures.Composition()
        composition.horizontalOffset = CGFloat((center.x - 0.5) / 0.5)
        composition.verticalOffset = CGFloat((center.y - 0.333) / 0.333)
        composition.subjectAreaRatio = 0.0
        return composition
    }

    private func lensRecommendation(for boundingBox: CGRect) -> Int? {
        let width = boundingBox.width
        if width < 0.2 { return 3 }
        if width < 0.35 { return 2 }
        if width > 0.7 { return 1 }
        return nil
    }
}

private final class HighStream: FrameConsumer {
    weak var pipeline: AnalysisPipeline?

    init(pipeline: AnalysisPipeline) {
        self.pipeline = pipeline
    }

    func consumeFrame(_ context: FrameContext) {
        pipeline?.handleHigh(context: context)
    }
}

private final class MediumStream: FrameConsumer {
    weak var pipeline: AnalysisPipeline?

    init(pipeline: AnalysisPipeline) {
        self.pipeline = pipeline
    }

    func consumeFrame(_ context: FrameContext) {
        pipeline?.handleMedium(context: context)
    }
}

private final class LowStream: FrameConsumer {
    weak var pipeline: AnalysisPipeline?

    init(pipeline: AnalysisPipeline) {
        self.pipeline = pipeline
    }

    func consumeFrame(_ context: FrameContext) {
        pipeline?.handleLow(context: context)
    }
}


