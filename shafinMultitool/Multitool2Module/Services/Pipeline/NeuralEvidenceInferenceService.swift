//
//  NeuralEvidenceInferenceService.swift
//  multitool2
//
//  Created by Codex on 22.04.2026.
//

import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

struct NeuralEvidenceProviderDescriptor: Equatable, Sendable {
    let providerKind: NeuralEvidenceProviderKind
    let inferenceTarget: InferenceTargetKind
    let modelFamily: String
    let modelVersion: String
    let preprocessingVersion: String
    let thresholdProfileLive: String
    let thresholdProfilePause: String
    let bundleVersion: String
}

struct NeuralEvidenceProviderRequest {
    let frameId: String
    let mode: AnalysisMode
    let pixelBuffer: CVPixelBuffer
    let orientation: CGImagePropertyOrientation
    let roiStrategy: NeuralEvidenceROIStrategy
    let primarySubjectRegion: NormalizedRect?
    let thresholdProfile: String
}

extension NeuralEvidenceProviderRequest: @unchecked Sendable {}

struct NeuralEvidenceProviderOutput: Equatable, Sendable {
    let scalarScores: [Double]
    let scalarConfidences: [Double]
    let supportingSignalScores: [[Double]]
    let shotTypeAffinities: [Double]
    let shotTypeConfidence: Double
    let actualROIStrategy: NeuralEvidenceROIStrategy

    static let scalarHeadCount = 7
    static let supportingSignalCount = 21
    static let shotTypeCount = 7

    func validateShape() -> [String] {
        var errors: [String] = []

        if scalarScores.count != Self.scalarHeadCount {
            errors.append("provider scalarScores must contain \(Self.scalarHeadCount) values")
        }
        if scalarConfidences.count != Self.scalarHeadCount {
            errors.append("provider scalarConfidences must contain \(Self.scalarHeadCount) values")
        }
        if supportingSignalScores.count != Self.scalarHeadCount {
            errors.append("provider supportingSignalScores must contain \(Self.scalarHeadCount) rows")
        } else if supportingSignalScores.contains(where: { $0.count != Self.supportingSignalCount }) {
            errors.append("provider supportingSignalScores rows must contain \(Self.supportingSignalCount) values")
        }
        if shotTypeAffinities.count != Self.shotTypeCount {
            errors.append("provider shotTypeAffinities must contain \(Self.shotTypeCount) values")
        }

        return errors
    }
}

enum NeuralEvidenceProviderError: Error, Equatable, Sendable {
    case modelNotLoaded
    case preprocessingFailed
    case inferenceFailed
    case postprocessingFailed
    case runtimeTimeout
    case unknown

    var failureReason: NeuralEvidenceFailureReason {
        switch self {
        case .modelNotLoaded:
            return .modelNotLoaded
        case .preprocessingFailed:
            return .preprocessingFailed
        case .inferenceFailed:
            return .inferenceFailed
        case .postprocessingFailed:
            return .postprocessingFailed
        case .runtimeTimeout:
            return .runtimeTimeout
        case .unknown:
            return .unknown
        }
    }
}

struct NeuralEvidenceProviderExecutionError: Error, Sendable {
    let providerError: NeuralEvidenceProviderError
    let actualROIStrategy: NeuralEvidenceROIStrategy?
}

protocol NeuralEvidenceProvider: AnyObject {
    var descriptor: NeuralEvidenceProviderDescriptor { get }
    func prepareIfNeeded() async throws
    func infer(request: NeuralEvidenceProviderRequest) async throws -> NeuralEvidenceProviderOutput
}

struct NeuralEvidenceInferenceConfiguration: Sendable {
    var featureEnabled: Bool
    var liveModeEnabled: Bool
    var pauseModeEnabled: Bool
    var liveMinIntervalUnrestricted: TimeInterval
    var liveMinIntervalConstrained: TimeInterval
    var liveTimeout: TimeInterval
    var pauseTimeout: TimeInterval
    var lowBatteryThreshold: Float
    var liveSupportingSignalThreshold: Double
    var pauseSupportingSignalThreshold: Double

    static let disabled = NeuralEvidenceInferenceConfiguration(
        featureEnabled: false,
        liveModeEnabled: false,
        pauseModeEnabled: false,
        liveMinIntervalUnrestricted: 1.25,
        liveMinIntervalConstrained: 2.50,
        liveTimeout: 0.180,
        pauseTimeout: 0.600,
        lowBatteryThreshold: 0.20,
        liveSupportingSignalThreshold: 0.60,
        pauseSupportingSignalThreshold: 0.55
    )

    static func defaultForModelAvailability(_ modelAvailable: Bool) -> NeuralEvidenceInferenceConfiguration {
        var configuration = Self.disabled
        configuration.featureEnabled = modelAvailable
        configuration.liveModeEnabled = modelAvailable
        configuration.pauseModeEnabled = modelAvailable
        return configuration
    }
}

struct NeuralEvidenceInferenceRequest {
    let frameId: String
    let mode: AnalysisMode
    let capturedAt: Date
    let pixelBuffer: CVPixelBuffer
    let orientation: CGImagePropertyOrientation
    let sceneSemantics: SceneSemanticsReport?
    let primarySubjectRegion: NormalizedRect?
    let motionState: CameraAnalysisMotionState
    let shakeLevel: Double
    let isStable: Bool
    let thermalTier: ThermalBudgetTier
    let heavyModelsEnabled: Bool
    let batteryLevel: Float?
    let forcePauseExecution: Bool
}

extension NeuralEvidenceInferenceRequest: @unchecked Sendable {}

enum NeuralEvidenceInferenceOutcomeKind: String, Equatable, Sendable {
    case disabled
    case executed
    case policySkipped = "policy_skipped"
    case failed
}

enum NeuralEvidenceInferenceOutcome: Sendable {
    case disabled
    case executed(snapshot: NeuralEvidenceSnapshot, metadata: NeuralEvidenceRuntimeMetadata)
    case policySkipped(snapshot: NeuralEvidenceSnapshot, metadata: NeuralEvidenceRuntimeMetadata)
    case failed(snapshot: NeuralEvidenceSnapshot, metadata: NeuralEvidenceRuntimeMetadata)

    var kind: NeuralEvidenceInferenceOutcomeKind {
        switch self {
        case .disabled:
            return .disabled
        case .executed:
            return .executed
        case .policySkipped:
            return .policySkipped
        case .failed:
            return .failed
        }
    }

    var snapshot: NeuralEvidenceSnapshot? {
        switch self {
        case .disabled:
            return nil
        case let .executed(snapshot, _),
             let .policySkipped(snapshot, _),
             let .failed(snapshot, _):
            return snapshot
        }
    }

    var metadata: NeuralEvidenceRuntimeMetadata? {
        switch self {
        case .disabled:
            return nil
        case let .executed(_, metadata),
             let .policySkipped(_, metadata),
             let .failed(_, metadata):
            return metadata
        }
    }
}

struct NeuralEvidenceRecordedOutcome: Equatable, Sendable {
    let kind: NeuralEvidenceInferenceOutcomeKind
    let snapshot: NeuralEvidenceSnapshot?
    let metadata: NeuralEvidenceRuntimeMetadata?

    init(_ outcome: NeuralEvidenceInferenceOutcome) {
        kind = outcome.kind
        snapshot = outcome.snapshot
        metadata = outcome.metadata
    }
}

private struct NeuralEvidenceExecutionProfile: Sendable {
    let timeout: TimeInterval
    let roiStrategy: NeuralEvidenceROIStrategy
    let thresholdProfile: String
    let supportingSignalThreshold: Double
}

private enum NeuralEvidenceCadenceDecision: Sendable {
    case disabled
    case skip
    case execute(NeuralEvidenceExecutionProfile)
}

struct NeuralEvidenceCadencePolicy: Sendable {
    fileprivate func decision(for request: NeuralEvidenceInferenceRequest,
                              configuration: NeuralEvidenceInferenceConfiguration,
                              descriptor: NeuralEvidenceProviderDescriptor,
                              lastLiveExecutionAt: Date?,
                              now: Date) -> NeuralEvidenceCadenceDecision {
        guard configuration.featureEnabled else {
            return .disabled
        }

        switch request.mode {
        case .live:
            guard configuration.liveModeEnabled else {
                return .disabled
            }

            if request.thermalTier == .critical ||
                !request.heavyModelsEnabled ||
                isLowBattery(request.batteryLevel, threshold: configuration.lowBatteryThreshold) ||
                !request.isStable ||
                request.motionState != .still ||
                request.shakeLevel > 0.35 {
                return .skip
            }

            let minInterval: TimeInterval
            switch request.thermalTier {
            case .unrestricted:
                minInterval = configuration.liveMinIntervalUnrestricted
            case .constrained, .critical:
                minInterval = configuration.liveMinIntervalConstrained
            }

            if let lastLiveExecutionAt, now.timeIntervalSince(lastLiveExecutionAt) < minInterval {
                return .skip
            }

            return .execute(
                NeuralEvidenceExecutionProfile(
                    timeout: configuration.liveTimeout,
                    roiStrategy: .fullFrameOnly,
                    thresholdProfile: descriptor.thresholdProfileLive,
                    supportingSignalThreshold: configuration.liveSupportingSignalThreshold
                )
            )
        case .pause:
            guard configuration.pauseModeEnabled else {
                return .disabled
            }

            let useDegradedProfile = request.thermalTier == .critical || !request.heavyModelsEnabled
            let roiStrategy: NeuralEvidenceROIStrategy
            if useDegradedProfile {
                roiStrategy = .fullFrameOnly
            } else if request.primarySubjectRegion != nil {
                roiStrategy = .fullFramePlusSubjectCrop
            } else {
                roiStrategy = .fullFrameOnly
            }

            return .execute(
                NeuralEvidenceExecutionProfile(
                    timeout: configuration.pauseTimeout,
                    roiStrategy: roiStrategy,
                    thresholdProfile: descriptor.thresholdProfilePause,
                    supportingSignalThreshold: configuration.pauseSupportingSignalThreshold
                )
            )
        }
    }

    private func isLowBattery(_ batteryLevel: Float?, threshold: Float) -> Bool {
        guard let batteryLevel, batteryLevel >= 0 else { return false }
        return batteryLevel < threshold
    }
}

final class NeuralEvidenceInferenceService {
    private let configuration: NeuralEvidenceInferenceConfiguration
    private let cadencePolicy: NeuralEvidenceCadencePolicy
    private let provider: NeuralEvidenceProvider
    private let dateProvider: () -> Date
    private let stateQueue = DispatchQueue(label: "NeuralEvidenceInferenceService.state")
    private var lastLiveExecutionAt: Date?

    init(configuration: NeuralEvidenceInferenceConfiguration,
         provider: NeuralEvidenceProvider,
         cadencePolicy: NeuralEvidenceCadencePolicy = NeuralEvidenceCadencePolicy(),
         dateProvider: @escaping () -> Date = Date.init) {
        self.configuration = configuration
        self.provider = provider
        self.cadencePolicy = cadencePolicy
        self.dateProvider = dateProvider
    }

    static func makeDefault(bundle: Bundle = .main) -> NeuralEvidenceInferenceService {
        let provider = CoreMLNeuralEvidenceProvider(bundle: bundle)
        let configuration = NeuralEvidenceInferenceConfiguration.defaultForModelAvailability(provider.isModelAvailable)
        return NeuralEvidenceInferenceService(configuration: configuration, provider: provider)
    }

    func infer(request: NeuralEvidenceInferenceRequest) async -> NeuralEvidenceInferenceOutcome {
        let now = dateProvider()
        let decision = reserveCadenceDecision(for: request, now: now)

        switch decision {
        case .disabled:
            return .disabled
        case .skip:
            return makePolicySkippedOutcome(request: request)
        case let .execute(profile):
            return await execute(profile: profile, request: request)
        }
    }

    private func reserveCadenceDecision(for request: NeuralEvidenceInferenceRequest,
                                        now: Date) -> NeuralEvidenceCadenceDecision {
        stateQueue.sync {
            let decision = cadencePolicy.decision(
                for: request,
                configuration: configuration,
                descriptor: provider.descriptor,
                lastLiveExecutionAt: lastLiveExecutionAt,
                now: now
            )
            if case .execute = decision, request.mode == .live {
                lastLiveExecutionAt = now
            }
            return decision
        }
    }

    private func execute(profile: NeuralEvidenceExecutionProfile,
                         request: NeuralEvidenceInferenceRequest) async -> NeuralEvidenceInferenceOutcome {
        let start = DispatchTime.now()

        do {
            let providerOutput = try await withTimeout(seconds: profile.timeout) { [provider] in
                try await provider.prepareIfNeeded()
                let providerRequest = NeuralEvidenceProviderRequest(
                    frameId: request.frameId,
                    mode: request.mode,
                    pixelBuffer: request.pixelBuffer,
                    orientation: request.orientation,
                    roiStrategy: profile.roiStrategy,
                    primarySubjectRegion: request.primarySubjectRegion,
                    thresholdProfile: profile.thresholdProfile
                )
                return try await provider.infer(request: providerRequest)
            }

            let snapshot = try makeSnapshot(
                from: providerOutput,
                request: request,
                roiStrategy: providerOutput.actualROIStrategy,
                thresholdProfile: profile.thresholdProfile,
                supportingSignalThreshold: profile.supportingSignalThreshold
            )
            let metadata = makeMetadata(
                for: request,
                descriptor: provider.descriptor,
                thresholdProfile: profile.thresholdProfile,
                producedAt: dateProvider(),
                latencyMs: elapsedMilliseconds(since: start),
                roiStrategy: providerOutput.actualROIStrategy,
                failureReason: nil
            )

            let validationErrors = snapshot.validate(
                expectedFrameId: request.frameId,
                semanticsReport: request.sceneSemantics,
                runtimeMetadata: metadata
            )
            guard validationErrors.isEmpty else {
                throw NeuralEvidenceProviderError.postprocessingFailed
            }

            return .executed(snapshot: snapshot, metadata: metadata)
        } catch {
            let failureContext = makeFailureContext(from: error, fallbackROIStrategy: profile.roiStrategy)
            let snapshot = makeFailureSnapshot(
                request: request,
                descriptor: provider.descriptor,
                roiStrategy: failureContext.actualROIStrategy ?? profile.roiStrategy
            )
            let metadata = makeMetadata(
                for: request,
                descriptor: provider.descriptor,
                thresholdProfile: profile.thresholdProfile,
                producedAt: dateProvider(),
                latencyMs: elapsedMilliseconds(since: start),
                roiStrategy: failureContext.actualROIStrategy,
                failureReason: failureContext.providerError.failureReason
            )
            return .failed(snapshot: snapshot, metadata: metadata)
        }
    }

    private func makePolicySkippedOutcome(request: NeuralEvidenceInferenceRequest) -> NeuralEvidenceInferenceOutcome {
        let snapshot = makePolicySkippedSnapshot(request: request, descriptor: provider.descriptor)
        let metadata = makeMetadata(
            for: request,
            descriptor: provider.descriptor,
            thresholdProfile: provider.descriptor.thresholdProfileLive,
            producedAt: dateProvider(),
            latencyMs: nil,
            roiStrategy: nil,
            failureReason: .policySkipped
        )
        return .policySkipped(snapshot: snapshot, metadata: metadata)
    }

    private func makeSnapshot(from providerOutput: NeuralEvidenceProviderOutput,
                              request: NeuralEvidenceInferenceRequest,
                              roiStrategy: NeuralEvidenceROIStrategy,
                              thresholdProfile: String,
                              supportingSignalThreshold: Double) throws -> NeuralEvidenceSnapshot {
        guard providerOutput.validateShape().isEmpty else {
            throw NeuralEvidenceProviderError.postprocessingFailed
        }

        let scalarHeadOrder = EvidenceHeadId.allCases.filter { $0 != .shotTypeConfidence }
        var entries: [NeuralEvidenceHeadEntry] = []

        for (index, headId) in scalarHeadOrder.enumerated() {
            let status = statusForScalarHead(headId: headId, request: request, unavailableWhenApplicable: false)
            let entry: NeuralEvidenceHeadEntry
            switch status {
            case .available:
                let score = providerOutput.scalarScores[index]
                let confidence = providerOutput.scalarConfidences[index]
                let signals = selectSupportingSignals(
                    headId: headId,
                    scores: providerOutput.supportingSignalScores[index],
                    minimumScore: supportingSignalThreshold
                )
                entry = .init(
                    headId: headId,
                    payload: .scalar(
                        ScalarEvidenceHeadOutput(
                            headId: headId,
                            status: .available,
                            score: score,
                            confidence: confidence,
                            mode: request.mode,
                            supportingSignals: signals
                        )
                    )
                )
            case .notApplicable, .unavailable:
                entry = .init(
                    headId: headId,
                    payload: .scalar(
                        ScalarEvidenceHeadOutput(
                            headId: headId,
                            status: status,
                            score: nil,
                            confidence: 0.0,
                            mode: request.mode,
                            supportingSignals: []
                        )
                    )
                )
            }
            entries.append(entry)
        }

        let shotTypeStatus: EvidenceHeadStatus = request.mode == .live ? .notApplicable : .available
        let shotEntry: NeuralEvidenceHeadEntry
        switch shotTypeStatus {
        case .available:
            shotEntry = .init(
                headId: .shotTypeConfidence,
                payload: .categorical(
                    CategoricalEvidenceHeadOutput(
                        headId: .shotTypeConfidence,
                        status: .available,
                        affinities: zip(EvidenceCategoryId.allCases, providerOutput.shotTypeAffinities).map {
                            EvidenceCategoryScore(categoryId: $0.0, score: $0.1)
                        },
                        confidence: providerOutput.shotTypeConfidence,
                        mode: request.mode,
                        supportingSignals: []
                    )
                )
            )
        case .notApplicable, .unavailable:
            shotEntry = .init(
                headId: .shotTypeConfidence,
                payload: .categorical(
                    CategoricalEvidenceHeadOutput(
                        headId: .shotTypeConfidence,
                        status: shotTypeStatus,
                        affinities: [],
                        confidence: 0.0,
                        mode: request.mode,
                        supportingSignals: []
                    )
                )
            )
        }
        entries.append(shotEntry)

        return NeuralEvidenceSnapshot(
            schemaVersion: NeuralEvidenceSnapshot.currentSchemaVersion,
            frameId: request.frameId,
            mode: request.mode,
            capturedAt: request.capturedAt,
            bundleVersion: provider.descriptor.bundleVersion,
            headOutputs: entries
        )
    }

    private func makePolicySkippedSnapshot(request: NeuralEvidenceInferenceRequest,
                                           descriptor: NeuralEvidenceProviderDescriptor) -> NeuralEvidenceSnapshot {
        let entries = EvidenceHeadId.allCases.map { headId -> NeuralEvidenceHeadEntry in
            if headId == .shotTypeConfidence {
                return .init(
                    headId: headId,
                    payload: .categorical(
                        CategoricalEvidenceHeadOutput(
                            headId: headId,
                            status: .notApplicable,
                            affinities: [],
                            confidence: 0.0,
                            mode: request.mode,
                            supportingSignals: []
                        )
                    )
                )
            }

            let status = statusForScalarHead(headId: headId, request: request, unavailableWhenApplicable: true)
            return .init(
                headId: headId,
                payload: .scalar(
                    ScalarEvidenceHeadOutput(
                        headId: headId,
                        status: status,
                        score: nil,
                        confidence: 0.0,
                        mode: request.mode,
                        supportingSignals: []
                    )
                )
            )
        }

        return NeuralEvidenceSnapshot(
            schemaVersion: NeuralEvidenceSnapshot.currentSchemaVersion,
            frameId: request.frameId,
            mode: request.mode,
            capturedAt: request.capturedAt,
            bundleVersion: descriptor.bundleVersion,
            headOutputs: entries
        )
    }

    private func makeFailureSnapshot(request: NeuralEvidenceInferenceRequest,
                                     descriptor: NeuralEvidenceProviderDescriptor,
                                     roiStrategy: NeuralEvidenceROIStrategy) -> NeuralEvidenceSnapshot {
        let entries = EvidenceHeadId.allCases.map { headId -> NeuralEvidenceHeadEntry in
            if headId == .shotTypeConfidence {
                let status: EvidenceHeadStatus = request.mode == .live ? .notApplicable : .unavailable
                return .init(
                    headId: headId,
                    payload: .categorical(
                        CategoricalEvidenceHeadOutput(
                            headId: headId,
                            status: status,
                            affinities: [],
                            confidence: 0.0,
                            mode: request.mode,
                            supportingSignals: []
                        )
                    )
                )
            }

            let status = statusForScalarHead(headId: headId, request: request, unavailableWhenApplicable: true)
            return .init(
                headId: headId,
                payload: .scalar(
                    ScalarEvidenceHeadOutput(
                        headId: headId,
                        status: status,
                        score: nil,
                        confidence: 0.0,
                        mode: request.mode,
                        supportingSignals: []
                    )
                )
            )
        }

        return NeuralEvidenceSnapshot(
            schemaVersion: NeuralEvidenceSnapshot.currentSchemaVersion,
            frameId: request.frameId,
            mode: request.mode,
            capturedAt: request.capturedAt,
            bundleVersion: descriptor.bundleVersion,
            headOutputs: entries
        )
    }

    private func makeMetadata(for request: NeuralEvidenceInferenceRequest,
                              descriptor: NeuralEvidenceProviderDescriptor,
                              thresholdProfile: String,
                              producedAt: Date,
                              latencyMs: Int?,
                              roiStrategy: NeuralEvidenceROIStrategy?,
                              failureReason: NeuralEvidenceFailureReason?) -> NeuralEvidenceRuntimeMetadata {
        NeuralEvidenceRuntimeMetadata(
            metadataSchemaVersion: NeuralEvidenceSnapshot.currentSchemaVersion,
            frameId: request.frameId,
            mode: request.mode,
            providerKind: descriptor.providerKind,
            inferenceTarget: descriptor.inferenceTarget,
            modelFamily: descriptor.modelFamily,
            modelVersion: descriptor.modelVersion,
            preprocessingVersion: descriptor.preprocessingVersion,
            thresholdProfile: thresholdProfile,
            producedAt: producedAt,
            latencyMs: latencyMs,
            roiStrategy: roiStrategy,
            failureReason: failureReason
        )
    }

    private func statusForScalarHead(headId: EvidenceHeadId,
                                     request: NeuralEvidenceInferenceRequest,
                                     unavailableWhenApplicable: Bool) -> EvidenceHeadStatus {
        switch headId {
        case .balanceConfidence, .depthSeparation, .cinematicExpressiveness:
            return request.mode == .live ? .notApplicable : (unavailableWhenApplicable ? .unavailable : .available)
        case .faceSaliency:
            guard let semantics = request.sceneSemantics else {
                return .unavailable
            }
            switch semantics.primarySubject.kind {
            case .face, .person, .group:
                return unavailableWhenApplicable ? .unavailable : .available
            case .object, .unknown:
                return .notApplicable
            }
        case .shotTypeConfidence:
            return request.mode == .live ? .notApplicable : (unavailableWhenApplicable ? .unavailable : .available)
        case .subjectProminence, .backgroundClutter, .lightingQuality:
            return unavailableWhenApplicable ? .unavailable : .available
        }
    }

    private func selectSupportingSignals(headId: EvidenceHeadId,
                                         scores: [Double],
                                         minimumScore: Double) -> [SupportingSignalTag] {
        guard scores.count == SupportingSignalTag.allCases.count else {
            return []
        }

        let allowedTags = allowedSupportingSignals(for: headId)
        let candidates = zip(SupportingSignalTag.allCases, scores)
            .filter { allowedTags.contains($0.0) && $0.1 >= minimumScore }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }
                return lhs.0.rawValue < rhs.0.rawValue
            }
            .prefix(2)
            .map(\.0)

        return candidates.sorted { lhs, rhs in
            SupportingSignalTag.allCases.firstIndex(of: lhs) ?? .max <
            SupportingSignalTag.allCases.firstIndex(of: rhs) ?? .max
        }
    }

    private func allowedSupportingSignals(for headId: EvidenceHeadId) -> Set<SupportingSignalTag> {
        switch headId {
        case .subjectProminence:
            return [.subjectScale, .subjectAttentionPull, .subjectReadability]
        case .backgroundClutter:
            return [.objectDensity, .textureNoise, .attentionCompetition]
        case .lightingQuality:
            return [.subjectExposureReadability, .facialLightSupport, .tonalStructure]
        case .faceSaliency:
            return [.faceAttentionPull, .eyeRegionVisibility, .facialAnchorStrength, .facialLightSupport]
        case .balanceConfidence:
            return [.frameBalance, .subjectPlacementStability, .negativeSpaceFit]
        case .depthSeparation:
            return [.foregroundBackgroundSplit, .subjectBackgroundContrast, .layeringClarity]
        case .cinematicExpressiveness:
            return [.stylisticIntent, .productionValueResidual, .visualHarmonyResidual]
        case .shotTypeConfidence:
            return []
        }
    }

    private func elapsedMilliseconds(since start: DispatchTime) -> Int {
        let nanos = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        return Int(nanos / 1_000_000)
    }

    private func makeFailureContext(from error: Error,
                                    fallbackROIStrategy: NeuralEvidenceROIStrategy) -> NeuralEvidenceProviderExecutionError {
        if let executionError = error as? NeuralEvidenceProviderExecutionError {
            return executionError
        }
        if let providerError = error as? NeuralEvidenceProviderError {
            return NeuralEvidenceProviderExecutionError(
                providerError: providerError,
                actualROIStrategy: fallbackROIStrategy
            )
        }
        return NeuralEvidenceProviderExecutionError(
            providerError: .unknown,
            actualROIStrategy: fallbackROIStrategy
        )
    }

    private func withTimeout<T>(seconds: TimeInterval,
                                operation: @escaping () async throws -> T) async throws -> T {
        if seconds <= 0 {
            return try await operation()
        }

        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                let nanoseconds = UInt64(seconds * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                throw NeuralEvidenceProviderError.runtimeTimeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
