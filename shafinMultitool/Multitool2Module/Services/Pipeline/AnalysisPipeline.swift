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
    var detrMeasuredAt: Date?
    var visionSubjects: [VisionSubject] = []
    var visionMeasuredAt: Date?
    var saliencyCenter: CGPoint?
}

struct FeatureSample<Value> {
    let value: Value
    let measuredAt: Date
    let baseConfidence: Double?

    init(value: Value, measuredAt: Date, baseConfidence: Double? = nil) {
        self.value = value
        self.measuredAt = measuredAt
        self.baseConfidence = baseConfidence.map { min(1.0, max(0.0, $0)) }
    }
}

extension FeatureSample: Equatable where Value: Equatable {}

private extension Array {
    func stableSorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> [Element] {
        enumerated().sorted { lhs, rhs in
            if areInIncreasingOrder(lhs.element, rhs.element) {
                return true
            }
            if areInIncreasingOrder(rhs.element, lhs.element) {
                return false
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}

struct FeatureSnapshotVisionSubject: Equatable {
    let boundingBox: CGRect
    let confidence: Double
    let isFace: Bool
}

struct FeatureSnapshotVisionPayload: Equatable {
    let subjects: [FeatureSnapshotVisionSubject]
    let saliencyCenter: CGPoint?
    let faceCount: Int
    let personCount: Int
}

struct FeatureSnapshotHorizonPayload: Equatable {
    let angleDegrees: Double
    let confidence: Double
}

struct FeatureSnapshotLightingPayload: Equatable {
    let exposureBiasHint: Double
    let backlightIndex: Double
    let keyToFillRatio: Double?
}

struct FeatureSnapshotDetectedObject: Equatable {
    let boundingBox: CGRect
    let label: String
    let confidence: Double
}

struct FeatureSnapshotDetrPayload: Equatable {
    let detections: [FeatureSnapshotDetectedObject]
}

struct FeatureSnapshotAestheticPayload: Equatable {
    let score10: Double
}

struct FeatureAggregationInput: Equatable {
    let frameId: String
    let mode: AnalysisMode
    let capturedAt: Date
    let motionState: CameraAnalysisMotionState
    let shakeLevel: Double
    let vision: FeatureSample<FeatureSnapshotVisionPayload>?
    let horizon: FeatureSample<FeatureSnapshotHorizonPayload>?
    let lighting: FeatureSample<FeatureSnapshotLightingPayload>?
    let detr: FeatureSample<FeatureSnapshotDetrPayload>?
    let aesthetic: FeatureSample<FeatureSnapshotAestheticPayload>?
}

struct PipelineFeatureSnapshotAdapterState {
    let features: CoachingFeatures
    let debugData: DebugData
    let vision: FeatureSample<FeatureSnapshotVisionPayload>?
    let horizonMeasuredAt: Date?
    let horizon: FeatureSample<FeatureSnapshotHorizonPayload>?
    let lightingMeasuredAt: Date?
    let lighting: FeatureSample<FeatureSnapshotLightingPayload>?
    let detr: FeatureSample<FeatureSnapshotDetrPayload>?
    let aestheticMeasuredAt: Date?
    let aesthetic: FeatureSample<FeatureSnapshotAestheticPayload>?
}

struct PipelineFeatureSnapshotAdapter {
    func makeInput(frameId: String,
                   mode: AnalysisMode,
                   capturedAt: Date,
                   state: PipelineFeatureSnapshotAdapterState) -> FeatureAggregationInput {
        let vision = state.vision ?? fallbackVisionSample(from: state.debugData)
        let horizon = state.horizon ?? fallbackHorizonSample(from: state.features, measuredAt: state.horizonMeasuredAt)
        let lighting = state.lighting ?? fallbackLightingSample(from: state.features, measuredAt: state.lightingMeasuredAt)
        let detr = state.detr ?? fallbackDetrSample(from: state.debugData)
        let aesthetic = state.aesthetic ?? fallbackAestheticSample(from: state.features, measuredAt: state.aestheticMeasuredAt)

        return FeatureAggregationInput(
            frameId: frameId,
            mode: mode,
            capturedAt: capturedAt,
            motionState: state.features.motion.state.cameraAnalysisMotionState,
            shakeLevel: Double(state.features.motion.shakeLevel),
            vision: vision,
            horizon: horizon,
            lighting: lighting,
            detr: detr,
            aesthetic: aesthetic
        )
    }

    private func fallbackVisionSample(from debugData: DebugData) -> FeatureSample<FeatureSnapshotVisionPayload>? {
        guard let measuredAt = debugData.visionMeasuredAt else {
            return nil
        }
        let subjects = debugData.visionSubjects.map {
            FeatureSnapshotVisionSubject(
                boundingBox: $0.boundingBox,
                confidence: Double($0.confidence),
                isFace: $0.isFace
            )
        }
        guard !subjects.isEmpty || debugData.saliencyCenter != nil else {
            return nil
        }

        let faceCount = subjects.filter(\.isFace).count
        let personCount = subjects.count
        let payload = FeatureSnapshotVisionPayload(
            subjects: subjects,
            saliencyCenter: debugData.saliencyCenter,
            faceCount: faceCount,
            personCount: personCount
        )
        let baseConfidence = subjects.map(\.confidence).max()
        return FeatureSample(value: payload, measuredAt: measuredAt, baseConfidence: baseConfidence)
    }

    private func fallbackHorizonSample(from features: CoachingFeatures,
                                       measuredAt: Date?) -> FeatureSample<FeatureSnapshotHorizonPayload>? {
        guard let measuredAt else { return nil }
        let angle = Double(features.horizon.angle)
        let confidence = min(1.0, max(0.0, Double(features.horizon.confidence)))
        guard abs(angle) > 0.0001 || confidence > 0 else { return nil }
        let payload = FeatureSnapshotHorizonPayload(angleDegrees: angle, confidence: confidence)
        return FeatureSample(value: payload, measuredAt: measuredAt, baseConfidence: confidence)
    }

    private func fallbackLightingSample(from features: CoachingFeatures,
                                        measuredAt: Date?) -> FeatureSample<FeatureSnapshotLightingPayload>? {
        guard let measuredAt else { return nil }
        let exposure = Double(features.lighting.exposureBiasHint)
        let backlight = Double(features.lighting.backlightIndex)
        let keyFill = Double(features.lighting.keyToFillRatio)
        guard abs(exposure) > 0.0001 || abs(backlight) > 0.0001 || abs(keyFill - 1.0) > 0.0001 else {
            return nil
        }
        let payload = FeatureSnapshotLightingPayload(
            exposureBiasHint: exposure,
            backlightIndex: backlight,
            keyToFillRatio: keyFill
        )
        return FeatureSample(value: payload, measuredAt: measuredAt, baseConfidence: nil)
    }

    private func fallbackDetrSample(from debugData: DebugData) -> FeatureSample<FeatureSnapshotDetrPayload>? {
        guard let measuredAt = debugData.detrMeasuredAt else {
            return nil
        }
        guard !debugData.detrDetections.isEmpty else { return nil }
        let detections = debugData.detrDetections.map {
            FeatureSnapshotDetectedObject(
                boundingBox: $0.boundingBox,
                label: $0.label,
                confidence: Double($0.confidence)
            )
        }
        let baseConfidence = detections.map(\.confidence).max()
        return FeatureSample(
            value: FeatureSnapshotDetrPayload(detections: detections),
            measuredAt: measuredAt,
            baseConfidence: baseConfidence
        )
    }

    private func fallbackAestheticSample(from features: CoachingFeatures,
                                         measuredAt: Date?) -> FeatureSample<FeatureSnapshotAestheticPayload>? {
        guard let measuredAt else { return nil }
        guard let score = features.aestheticScore else { return nil }
        return FeatureSample(
            value: FeatureSnapshotAestheticPayload(score10: Double(score)),
            measuredAt: measuredAt,
            baseConfidence: nil
        )
    }
}

struct FeatureSnapshotAggregator {
    struct FreshnessBudget {
        let visionMs: Int
        let horizonMs: Int
        let lightingMs: Int
        let detrMs: Int
        let aestheticMs: Int
        let staleMultiplier: Int

        init(visionMs: Int = 250,
             horizonMs: Int = 250,
             lightingMs: Int = 700,
             detrMs: Int = 1200,
             aestheticMs: Int = 3000,
             staleMultiplier: Int = 3) {
            self.visionMs = visionMs
            self.horizonMs = horizonMs
            self.lightingMs = lightingMs
            self.detrMs = detrMs
            self.aestheticMs = aestheticMs
            self.staleMultiplier = staleMultiplier
        }
    }

    private enum CandidateSource {
        case vision
        case detr
    }

    private struct Candidate {
        let source: CandidateSource
        let rawConfidence: Double
        let effectiveConfidence: Double
        let region: NormalizedRect
    }

    let freshnessBudget: FreshnessBudget

    init(freshnessBudget: FreshnessBudget = .init()) {
        self.freshnessBudget = freshnessBudget
    }

    func makeSnapshot(from input: FeatureAggregationInput) -> FrameFeatureSnapshot {
        let sourceStatuses = makeSourceStatuses(from: input)

        let visionPayload = sourceStatuses.vision.available ? input.vision?.value : nil
        let horizonPayload = sourceStatuses.horizon.available ? input.horizon?.value : nil
        let lightingPayload = sourceStatuses.lighting.available ? input.lighting?.value : nil
        let detrPayload = sourceStatuses.detr.available ? input.detr?.value : nil
        let aestheticPayload = sourceStatuses.aesthetic.available ? input.aesthetic?.value : nil

        let sortedVisionSubjects = sortVisionSubjects(visionPayload?.subjects ?? [])
        let sortedDetections = sortDetections(detrPayload?.detections ?? [])

        let primaryCandidate = selectPrimaryCandidate(
            visionSubjects: sortedVisionSubjects,
            detections: sortedDetections,
            sourceStatuses: sourceStatuses
        )

        let composition = makeComposition(
            primaryRegion: primaryCandidate?.region,
            saliencyCenter: visionPayload?.saliencyCenter
        )

        let subjectSignals = FrameFeatureSnapshot.SubjectSignals(
            faceDetected: (visionPayload?.faceCount ?? 0) > 0,
            personDetected: (visionPayload?.personCount ?? 0) > 0 || (visionPayload?.faceCount ?? 0) > 0,
            personCount: visionPayload?.personCount ?? 0,
            topObjectLabel: sortedDetections.first?.label,
            topObjectConfidence: sortedDetections.first?.confidence,
            primaryCandidateRegion: primaryCandidate?.region,
            primaryCandidateConfidence: primaryCandidate?.effectiveConfidence
        )

        let horizonFeatures = FrameFeatureSnapshot.HorizonFeatures(
            angleDegrees: horizonPayload?.angleDegrees ?? 0,
            confidence: horizonPayload?.confidence ?? 0
        )

        let lightingFeatures = FrameFeatureSnapshot.LightingFeatures(
            exposureBiasHint: lightingPayload?.exposureBiasHint ?? 0,
            backlightIndex: lightingPayload?.backlightIndex ?? 0,
            keyToFillRatio: lightingPayload?.keyToFillRatio
        )

        let motionFeatures = FrameFeatureSnapshot.MotionFeatures(
            state: input.motionState,
            shakeLevel: input.shakeLevel
        )

        let aestheticFeatures = FrameFeatureSnapshot.AestheticFeatures(
            score: aestheticPayload.map { clamp01($0.score10 / 10.0) },
            scoreConfidence: sourceStatuses.aesthetic.confidence
        )

        let objects = FrameFeatureSnapshot.ObjectDetectionsSummary(
            totalCount: sortedDetections.count,
            topKLabels: Array(sortedDetections.prefix(3).map(\.label))
        )

        let technicalFlags = makeTechnicalFlags(
            sourceStatuses: sourceStatuses,
            lighting: lightingFeatures,
            motion: motionFeatures,
            primaryCandidateConfidence: primaryCandidate?.effectiveConfidence
        )

        return FrameFeatureSnapshot(
            frameId: input.frameId,
            mode: input.mode,
            capturedAt: input.capturedAt,
            sources: sourceStatuses,
            composition: composition,
            subjectSignals: subjectSignals,
            horizon: horizonFeatures,
            lighting: lightingFeatures,
            motion: motionFeatures,
            aesthetics: aestheticFeatures,
            objects: objects,
            technicalFlags: technicalFlags
        )
    }

    private func makeSourceStatuses(from input: FeatureAggregationInput) -> FeatureSourceStatus {
        FeatureSourceStatus(
            vision: makeSourceState(sample: input.vision, budgetMs: freshnessBudget.visionMs, capturedAt: input.capturedAt),
            horizon: makeSourceState(sample: input.horizon, budgetMs: freshnessBudget.horizonMs, capturedAt: input.capturedAt),
            lighting: makeSourceState(sample: input.lighting, budgetMs: freshnessBudget.lightingMs, capturedAt: input.capturedAt),
            detr: makeSourceState(sample: input.detr, budgetMs: freshnessBudget.detrMs, capturedAt: input.capturedAt),
            aesthetic: makeSourceState(sample: input.aesthetic, budgetMs: freshnessBudget.aestheticMs, capturedAt: input.capturedAt)
        )
    }

    private func makeSourceState<T>(sample: FeatureSample<T>?,
                                    budgetMs: Int,
                                    capturedAt: Date) -> SourceState {
        guard let sample else {
            return SourceState(available: false)
        }

        let freshnessMs = normalizedFreshnessMs(capturedAt: capturedAt, measuredAt: sample.measuredAt)
        if freshnessMs > (budgetMs * freshnessBudget.staleMultiplier) {
            return SourceState(available: false, freshnessMs: freshnessMs, confidence: nil)
        }

        guard let baseConfidence = sample.baseConfidence else {
            return SourceState(available: true, freshnessMs: freshnessMs, confidence: nil)
        }

        let freshnessRatio = clamp01(1.0 - (Double(freshnessMs) / Double(2 * budgetMs)))
        let effectiveConfidence = clamp01(baseConfidence * freshnessRatio)
        return SourceState(available: true, freshnessMs: freshnessMs, confidence: effectiveConfidence)
    }

    private func normalizedFreshnessMs(capturedAt: Date, measuredAt: Date) -> Int {
        let raw = capturedAt.timeIntervalSince(measuredAt) * 1000.0
        return max(0, Int(floor(raw)))
    }

    private func makeComposition(primaryRegion: NormalizedRect?,
                                 saliencyCenter: CGPoint?) -> FrameFeatureSnapshot.CompositionFeatures {
        let defaultCenter = CGPoint(x: 0.5, y: 0.5)
        let center = primaryRegion.map {
            CGPoint(x: $0.x + ($0.width * 0.5), y: $0.y + ($0.height * 0.5))
        } ?? saliencyCenter ?? defaultCenter

        let horizontalOffset = clamp11((Double(center.x) - 0.5) / 0.5)
        let verticalOffset = clamp11((Double(center.y) - 0.333) / 0.333)
        let subjectAreaRatio = primaryRegion.map { $0.width * $0.height } ?? 0
        let saliencyLeftRightBalance = saliencyCenter.map { clamp11((Double($0.x) - 0.5) * 2.0) } ?? horizontalOffset
        let saliencyTopBottomBalance = saliencyCenter.map { clamp11((Double($0.y) - 0.5) * 2.0) } ?? 0

        return FrameFeatureSnapshot.CompositionFeatures(
            horizontalOffset: horizontalOffset,
            verticalOffset: verticalOffset,
            subjectAreaRatio: subjectAreaRatio,
            saliencyLeftRightBalance: saliencyLeftRightBalance,
            saliencyTopBottomBalance: saliencyTopBottomBalance
        )
    }

    private func sortVisionSubjects(_ subjects: [FeatureSnapshotVisionSubject]) -> [FeatureSnapshotVisionSubject] {
        subjects.stableSorted { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }
            let lhsArea = max(0, Double(lhs.boundingBox.width * lhs.boundingBox.height))
            let rhsArea = max(0, Double(rhs.boundingBox.width * rhs.boundingBox.height))
            if lhsArea != rhsArea {
                return lhsArea > rhsArea
            }
            if lhs.isFace != rhs.isFace {
                return lhs.isFace && !rhs.isFace
            }
            let lhsMidX = Double(lhs.boundingBox.midX)
            let rhsMidX = Double(rhs.boundingBox.midX)
            if lhsMidX != rhsMidX {
                return lhsMidX < rhsMidX
            }
            return Double(lhs.boundingBox.midY) < Double(rhs.boundingBox.midY)
        }
    }

    private func sortDetections(_ detections: [FeatureSnapshotDetectedObject]) -> [FeatureSnapshotDetectedObject] {
        detections.stableSorted { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }
            let lhsArea = max(0, Double(lhs.boundingBox.width * lhs.boundingBox.height))
            let rhsArea = max(0, Double(rhs.boundingBox.width * rhs.boundingBox.height))
            if lhsArea != rhsArea {
                return lhsArea > rhsArea
            }
            if lhs.label != rhs.label {
                return lhs.label < rhs.label
            }
            let lhsMidX = Double(lhs.boundingBox.midX)
            let rhsMidX = Double(rhs.boundingBox.midX)
            if lhsMidX != rhsMidX {
                return lhsMidX < rhsMidX
            }
            return Double(lhs.boundingBox.midY) < Double(rhs.boundingBox.midY)
        }
    }

    private func selectPrimaryCandidate(visionSubjects: [FeatureSnapshotVisionSubject],
                                        detections: [FeatureSnapshotDetectedObject],
                                        sourceStatuses: FeatureSourceStatus) -> Candidate? {
        var candidates: [Candidate] = []
        let visionSourceConfidence = sourceStatuses.vision.confidence ?? 1.0
        let detrSourceConfidence = sourceStatuses.detr.confidence ?? 1.0

        for subject in visionSubjects {
            guard let region = normalizedRect(from: subject.boundingBox) else { continue }
            let effective = clamp01(subject.confidence * visionSourceConfidence)
            candidates.append(
                Candidate(
                    source: .vision,
                    rawConfidence: subject.confidence,
                    effectiveConfidence: effective,
                    region: region
                )
            )
        }

        if let topDetection = detections.first,
           let region = normalizedRect(from: topDetection.boundingBox) {
            let effective = clamp01(topDetection.confidence * detrSourceConfidence)
            candidates.append(
                Candidate(
                    source: .detr,
                    rawConfidence: topDetection.confidence,
                    effectiveConfidence: effective,
                    region: region
                )
            )
        }

        let eligible = candidates.filter { $0.effectiveConfidence >= 0.20 }
        return eligible.max { lhs, rhs in
            let delta = lhs.effectiveConfidence - rhs.effectiveConfidence
            if abs(delta) >= 0.01 {
                return delta < 0
            }
            if lhs.source != rhs.source {
                return lhs.source == .detr
            }
            if lhs.rawConfidence != rhs.rawConfidence {
                return lhs.rawConfidence < rhs.rawConfidence
            }
            if lhs.region.x != rhs.region.x {
                return lhs.region.x > rhs.region.x
            }
            if lhs.region.y != rhs.region.y {
                return lhs.region.y > rhs.region.y
            }
            if lhs.region.width != rhs.region.width {
                return lhs.region.width < rhs.region.width
            }
            return lhs.region.height < rhs.region.height
        }
    }

    private func normalizedRect(from boundingBox: CGRect) -> NormalizedRect? {
        let rect = NormalizedRect(
            x: Double(boundingBox.origin.x),
            y: Double(boundingBox.origin.y),
            width: Double(boundingBox.width),
            height: Double(boundingBox.height)
        )
        return rect.isDegenerate ? nil : rect
    }

    private func makeTechnicalFlags(sourceStatuses: FeatureSourceStatus,
                                    lighting: FrameFeatureSnapshot.LightingFeatures,
                                    motion: FrameFeatureSnapshot.MotionFeatures,
                                    primaryCandidateConfidence: Double?) -> [TechnicalFlag] {
        var flags: [TechnicalFlag] = []

        if lighting.exposureBiasHint <= -0.35 || lighting.backlightIndex >= 0.65 {
            flags.append(.lowLight)
        }

        if motion.state != .still || motion.shakeLevel >= 0.65 {
            flags.append(.highMotion)
        }

        if primaryCandidateConfidence == nil || (primaryCandidateConfidence ?? 0) < 0.35 {
            flags.append(.lowSubjectConfidence)
        }

        let horizonConfidence = sourceStatuses.horizon.confidence ?? 0
        let visionConfidence = sourceStatuses.vision.confidence ?? 0
        let detrConfidence = sourceStatuses.detr.confidence ?? 0
        if horizonConfidence < 0.20 && visionConfidence < 0.20 && detrConfidence < 0.20 {
            flags.append(.lowSceneConfidence)
        }

        return flags.sorted { $0.rawValue < $1.rawValue }
    }

    private func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }

    private func clamp11(_ value: Double) -> Double {
        min(1.0, max(-1.0, value))
    }
}

private extension MotionState {
    var cameraAnalysisMotionState: CameraAnalysisMotionState {
        switch self {
        case .still:
            return .still
        case .moving:
            return .moving
        case .panning:
            return .panning
        }
    }
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
    private let featureSnapshotAggregator = FeatureSnapshotAggregator()
    private let featureSnapshotAdapter = PipelineFeatureSnapshotAdapter()

    private let highQueue = DispatchQueue(label: "AnalysisPipeline.high", qos: .userInitiated)
    private let mediumQueue = DispatchQueue(label: "AnalysisPipeline.medium", qos: .userInitiated)
    private let lowQueue = DispatchQueue(label: "AnalysisPipeline.low", qos: .utility)

    private var features = CoachingFeatures()
    private var debugData = DebugData()
    private var latestVisionSample: FeatureSample<FeatureSnapshotVisionPayload>?
    private var latestHorizonSample: FeatureSample<FeatureSnapshotHorizonPayload>?
    private var latestHorizonMeasuredAt: Date?
    private var latestLightingSample: FeatureSample<FeatureSnapshotLightingPayload>?
    private var latestLightingMeasuredAt: Date?
    private var latestDetrSample: FeatureSample<FeatureSnapshotDetrPayload>?
    private var latestAestheticSample: FeatureSample<FeatureSnapshotAestheticPayload>?
    private var latestAestheticMeasuredAt: Date?
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

    func makeFeatureSnapshot(mode: AnalysisMode = .live,
                             frameId: String = UUID().uuidString,
                             capturedAt: Date = Date()) -> FrameFeatureSnapshot {
        let adapterState = featureQueue.sync {
            PipelineFeatureSnapshotAdapterState(
                features: features,
                debugData: debugData,
                vision: latestVisionSample,
                horizonMeasuredAt: latestHorizonMeasuredAt,
                horizon: latestHorizonSample,
                lightingMeasuredAt: latestLightingMeasuredAt,
                lighting: latestLightingSample,
                detr: latestDetrSample,
                aestheticMeasuredAt: latestAestheticMeasuredAt,
                aesthetic: latestAestheticSample
            )
        }
        let input = featureSnapshotAdapter.makeInput(
            frameId: frameId,
            mode: mode,
            capturedAt: capturedAt,
            state: adapterState
        )
        return featureSnapshotAggregator.makeSnapshot(from: input)
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
        let measurementTime = Date()
        let visionSubjectsPayload = trackingResult.subjects.map {
            FeatureSnapshotVisionSubject(
                boundingBox: $0.boundingBox,
                confidence: Double($0.confidence),
                isFace: $0.isFace
            )
        }
        let visionBaseConfidence = visionSubjectsPayload.map(\.confidence).max()

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

            self.debugData.visionSubjects = trackingResult.subjects.map { subject in
                VisionSubject(
                    boundingBox: subject.boundingBox,
                    isFace: subject.isFace,
                    confidence: subject.confidence
                )
            }
            self.debugData.visionMeasuredAt = measurementTime
            self.debugData.saliencyCenter = trackingResult.saliencyCenter
            self.latestVisionSample = FeatureSample(
                value: FeatureSnapshotVisionPayload(
                    subjects: visionSubjectsPayload,
                    saliencyCenter: trackingResult.saliencyCenter,
                    faceCount: trackingResult.faceCount,
                    personCount: trackingResult.personCount
                ),
                measuredAt: measurementTime,
                baseConfidence: visionBaseConfidence
            )
            self.latestHorizonSample = FeatureSample(
                value: FeatureSnapshotHorizonPayload(
                    angleDegrees: Double(horizon.angle),
                    confidence: Double(horizon.confidence)
                ),
                measuredAt: measurementTime,
                baseConfidence: Double(horizon.confidence)
            )
            self.latestHorizonMeasuredAt = measurementTime
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

        let measurementTime = Date()
        updateFeatures { features in
            features.lighting.backlightIndex = lighting.backlightIndex
            features.lighting.keyToFillRatio = lighting.keyFillRatio
            features.lighting.exposureBiasHint = lighting.exposureBiasHint
            self.latestLightingSample = FeatureSample(
                value: FeatureSnapshotLightingPayload(
                    exposureBiasHint: Double(lighting.exposureBiasHint),
                    backlightIndex: Double(lighting.backlightIndex),
                    keyToFillRatio: Double(lighting.keyFillRatio)
                ),
                measuredAt: measurementTime,
                baseConfidence: nil
            )
            self.latestLightingMeasuredAt = measurementTime
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

                // Берём объект с максимальной confidence
                let sortedDetections = self.sortedDetectionsForPriority(detections)
                if let top = sortedDetections.first {
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
                        self.debugData.detrDetections = detections
                        self.debugData.detrMeasuredAt = Date()
                        self.latestDetrSample = FeatureSample(
                            value: FeatureSnapshotDetrPayload(
                                detections: sortedDetections.map {
                                    FeatureSnapshotDetectedObject(
                                        boundingBox: $0.boundingBox,
                                        label: $0.label,
                                        confidence: Double($0.confidence)
                                    )
                                }
                            ),
                            measuredAt: Date(),
                            baseConfidence: sortedDetections.first.map { Double($0.confidence) } ?? 0
                        )
                    }
                    Task { @MainActor in
                        self.overlayState.primaryBoundingBox = top.boundingBox
                        await self.emitSuggestion()
                    }
                } else {
                    self.updateFeatures { _ in
                        self.debugData.detrDetections = detections
                        self.debugData.detrMeasuredAt = Date()
                        self.latestDetrSample = FeatureSample(
                            value: FeatureSnapshotDetrPayload(detections: []),
                            measuredAt: Date(),
                            baseConfidence: 0
                        )
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
                    self.latestAestheticSample = FeatureSample(
                        value: FeatureSnapshotAestheticPayload(score10: score),
                        measuredAt: Date(),
                        baseConfidence: nil
                    )
                    self.latestAestheticMeasuredAt = Date()
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
                    if let top = self.sortedDetectionsForPriority(detections).first {
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

    private func sortedDetectionsForPriority(_ detections: [DETRDetection]) -> [DETRDetection] {
        detections.stableSorted { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }
            let lhsArea = lhs.boundingBox.width * lhs.boundingBox.height
            let rhsArea = rhs.boundingBox.width * rhs.boundingBox.height
            if lhsArea != rhsArea {
                return lhsArea > rhsArea
            }
            if lhs.label != rhs.label {
                return lhs.label < rhs.label
            }
            if lhs.boundingBox.midX != rhs.boundingBox.midX {
                return lhs.boundingBox.midX < rhs.boundingBox.midX
            }
            return lhs.boundingBox.midY < rhs.boundingBox.midY
        }
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
