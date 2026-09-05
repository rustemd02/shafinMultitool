//
//  SETCompositionNetRuntimeSchema.swift
//  shafinMultitool
//
//  M2-017 CameraNeuralRuntimeOwner: the typed input/output boundary of the
//  mandatory production neural Camera component (SETCompositionNet). Binds
//  model identity/preprocessing, subject ROI provenance and the output heads
//  (issue/action logits, risk/abstention, good-frame score, continuous
//  targets) into one validated value with explicit unavailable/failure
//  states. Validation fails closed: NaN, missing heads, wrong frame/
//  generation, and mismatched ROI are rejected, never coerced.
//

import CoreGraphics
import Foundation
import ImageIO

/// Input boundary: everything the neural component may consume, with the
/// provenance needed to attribute its outputs.
struct SETCompositionNetInput {
    let contractVersion: String
    let inputContractVersion: String
    let frameId: String
    let generation: UInt64
    let mode: AnalysisMode
    let orientation: CGImagePropertyOrientation
    /// Requested subject ROI provenance. Nil only for strategies that do not
    /// use a subject crop.
    let subjectROI: NormalizedRect?
    let roiStrategy: NeuralEvidenceROIStrategy
    let modelFamily: String
    let modelVersion: String
    let preprocessingVersion: String
    let bundleVersion: String
    let featureVersion: String
    let tensors: SETCompositionNetInputTensors?

    init(request: NeuralEvidenceProviderRequest,
         descriptor: NeuralEvidenceProviderDescriptor,
         generation: UInt64,
         tensors: SETCompositionNetInputTensors? = nil) {
        self.contractVersion = SETCompositionNetContract.contractVersion
        self.inputContractVersion = tensors?.inputContractVersion ?? SETCompositionNetContract.inputContractVersion
        self.frameId = request.frameId
        self.generation = generation
        self.mode = request.mode
        self.orientation = request.orientation
        self.subjectROI = request.primarySubjectRegion
        self.roiStrategy = request.roiStrategy
        self.modelFamily = descriptor.modelFamily
        self.modelVersion = descriptor.modelVersion
        self.preprocessingVersion = descriptor.preprocessingVersion
        self.bundleVersion = descriptor.bundleVersion
        self.featureVersion = tensors?.featureVersion ?? SETCompositionNetContract.featureVersion
        self.tensors = tensors
    }

    /// Strict v1 validation is separate from the legacy M2 provenance fields.
    /// A missing tensor payload or stale provider metadata keeps the candidate
    /// unavailable rather than silently filling a default tensor.
    func validate() -> [String] {
        var errors: [String] = []
        if contractVersion != SETCompositionNetContract.contractVersion {
            errors.append("compositionNet.contractVersion is unsupported")
        }
        if inputContractVersion != SETCompositionNetContract.inputContractVersion {
            errors.append("compositionNet.inputContractVersion is unsupported")
        }
        if modelFamily != "SETCompositionNet" {
            errors.append("compositionNet.modelFamily is unsupported")
        }
        if modelVersion.isEmpty {
            errors.append("compositionNet.modelVersion must be non-empty")
        }
        if preprocessingVersion != SETCompositionNetContract.preprocessingVersion {
            errors.append("compositionNet.preprocessingVersion is unsupported")
        }
        if featureVersion != SETCompositionNetContract.featureVersion {
            errors.append("compositionNet.featureVersion is unsupported")
        }
        if bundleVersion.isEmpty {
            errors.append("compositionNet.bundleVersion must be non-empty")
        }
        guard let tensors else {
            errors.append("compositionNet input tensors are missing")
            return errors
        }
        if tensors.roi != SETCompositionNetROI(subjectROI) {
            errors.append("compositionNet.roi does not match request subject ROI provenance")
        }
        errors.append(contentsOf: tensors.validate())
        return errors
    }
}

/// Output boundary with explicit availability. Only `.available` outputs may
/// enter evidence aggregation; `.unavailable` and `.failed` carry no scores.
struct SETCompositionNetOutput {
    enum Status: Equatable, Sendable {
        case available
        case unavailable
        case failed(NeuralEvidenceProviderError)
    }

    let status: Status
    /// Echoed provenance — validated against the input before use.
    let frameId: String
    let generation: UInt64
    let mode: AnalysisMode
    let subjectROI: NormalizedRect?
    let roiStrategy: NeuralEvidenceROIStrategy

    /// Issue/action logits, one per evidence head. All heads required.
    let issueActionLogits: [EvidenceHeadId: Double]
    /// Continuous supporting targets, one per supporting-signal tag.
    let continuousTargets: [SupportingSignalTag: Double]
    /// Shot-type affinities, one per category id.
    let shotTypeAffinities: [EvidenceCategoryId: Double]
    /// Risk head output (0 = no risk, 1 = certain risk).
    let riskScore: Double
    /// Abstention head output (0 = decide, 1 = abstain).
    let abstentionScore: Double
    /// Good-frame score head output.
    let goodFrameScore: Double
    /// Explicit v1 contract metadata and dense multi-task tensors. Nil means
    /// this value uses the pre-M4 legacy H06 shape.
    let contractVersion: String?
    let inputContractVersion: String?
    let preprocessingVersion: String?
    let featureVersion: String?
    let outputContractVersion: String?
    let heads: SETCompositionNetOutputHeads?

    init(status: Status,
         frameId: String,
         generation: UInt64,
         mode: AnalysisMode,
         subjectROI: NormalizedRect?,
         roiStrategy: NeuralEvidenceROIStrategy,
         issueActionLogits: [EvidenceHeadId: Double],
         continuousTargets: [SupportingSignalTag: Double],
         shotTypeAffinities: [EvidenceCategoryId: Double],
         riskScore: Double,
         abstentionScore: Double,
         goodFrameScore: Double,
         contractVersion: String? = nil,
         inputContractVersion: String? = nil,
         preprocessingVersion: String? = nil,
         featureVersion: String? = nil,
         outputContractVersion: String? = nil,
         heads: SETCompositionNetOutputHeads? = nil) {
        self.status = status
        self.frameId = frameId
        self.generation = generation
        self.mode = mode
        self.subjectROI = subjectROI
        self.roiStrategy = roiStrategy
        self.issueActionLogits = issueActionLogits
        self.continuousTargets = continuousTargets
        self.shotTypeAffinities = shotTypeAffinities
        self.riskScore = riskScore
        self.abstentionScore = abstentionScore
        self.goodFrameScore = goodFrameScore
        self.contractVersion = contractVersion
        self.inputContractVersion = inputContractVersion
        self.preprocessingVersion = preprocessingVersion
        self.featureVersion = featureVersion
        self.outputContractVersion = outputContractVersion ?? heads?.outputContractVersion
        self.heads = heads
    }

    // MARK: Construction

    static func available(request: NeuralEvidenceProviderRequest,
                          generation: UInt64,
                          output: NeuralEvidenceProviderOutput) -> SETCompositionNetOutput {
        var logits: [EvidenceHeadId: Double] = [:]
        for (index, headId) in EvidenceHeadId.allCases.enumerated()
        where index < output.scalarScores.count {
            logits[headId] = output.scalarScores[index]
        }
        // The shot-type head is delivered as its own field, not a scalar row.
        logits[.shotTypeConfidence] = output.shotTypeConfidence
        var targets: [SupportingSignalTag: Double] = [:]
        let tags = SupportingSignalTag.allCases
        for (row, rowValues) in output.supportingSignalScores.enumerated()
        where row < EvidenceHeadId.allCases.count {
            for (column, tag) in tags.enumerated() where column < rowValues.count {
                // Rows repeat per head; the canonical continuous target set is
                // keyed by tag — first non-empty row wins to stay total.
                if targets[tag] == nil {
                    targets[tag] = rowValues[column]
                }
            }
        }
        var affinities: [EvidenceCategoryId: Double] = [:]
        for (index, categoryId) in EvidenceCategoryId.allCases.enumerated()
        where index < output.shotTypeAffinities.count {
            affinities[categoryId] = output.shotTypeAffinities[index]
        }
        return SETCompositionNetOutput(
            status: .available,
            frameId: request.frameId,
            generation: generation,
            mode: request.mode,
            subjectROI: request.primarySubjectRegion,
            roiStrategy: output.actualROIStrategy,
            issueActionLogits: logits,
            continuousTargets: targets,
            shotTypeAffinities: affinities,
            riskScore: output.scalarConfidences.first ?? 0,
            abstentionScore: output.scalarConfidences.dropFirst().first ?? 0,
            goodFrameScore: output.shotTypeConfidence
        )
    }

    /// Constructor for the frozen M4 multi-task shape. The legacy provider
    /// output remains supported only through the legacy constructor; this is
    /// the explicit handoff for a versioned SETCompositionNet-v1 artifact.
    static func availableV1(request: NeuralEvidenceProviderRequest,
                            generation: UInt64,
                            heads: SETCompositionNetOutputHeads) -> SETCompositionNetOutput {
        SETCompositionNetOutput(
            status: .available,
            frameId: request.frameId,
            generation: generation,
            mode: request.mode,
            subjectROI: request.primarySubjectRegion,
            roiStrategy: request.roiStrategy,
            issueActionLogits: [:],
            continuousTargets: [:],
            shotTypeAffinities: [:],
            // Keep malformed heads non-plausible until strict validation runs;
            // never turn a missing or wrong-sized probability into a default.
            riskScore: requiredV1Probability(heads, name: "risk_probability"),
            abstentionScore: requiredV1Probability(heads, name: "abstention_probability"),
            goodFrameScore: requiredV1Probability(heads, name: "good_frame_probability"),
            contractVersion: SETCompositionNetContract.contractVersion,
            inputContractVersion: SETCompositionNetContract.inputContractVersion,
            preprocessingVersion: SETCompositionNetContract.preprocessingVersion,
            featureVersion: SETCompositionNetContract.featureVersion,
            outputContractVersion: heads.outputContractVersion,
            heads: heads
        )
    }

    private static func requiredV1Probability(_ heads: SETCompositionNetOutputHeads,
                                              name: String) -> Double {
        guard let values = heads.tensors[name], values.count == 1 else {
            return .nan
        }
        return values[0]
    }

    static func unavailable(request: NeuralEvidenceProviderRequest,
                            generation: UInt64) -> SETCompositionNetOutput {
        SETCompositionNetOutput(
            status: .unavailable,
            frameId: request.frameId,
            generation: generation,
            mode: request.mode,
            subjectROI: request.primarySubjectRegion,
            roiStrategy: request.roiStrategy,
            issueActionLogits: [:],
            continuousTargets: [:],
            shotTypeAffinities: [:],
            riskScore: 0,
            abstentionScore: 1,
            goodFrameScore: 0
        )
    }

    static func failed(_ error: NeuralEvidenceProviderError,
                       request: NeuralEvidenceProviderRequest,
                       generation: UInt64) -> SETCompositionNetOutput {
        SETCompositionNetOutput(
            status: .failed(error),
            frameId: request.frameId,
            generation: generation,
            mode: request.mode,
            subjectROI: request.primarySubjectRegion,
            roiStrategy: request.roiStrategy,
            issueActionLogits: [:],
            continuousTargets: [:],
            shotTypeAffinities: [:],
            riskScore: 0,
            abstentionScore: 1,
            goodFrameScore: 0
        )
    }

    // MARK: - Validation (fail closed)

    /// Rejects NaN/non-finite scores, missing heads, and provenance mismatch
    /// against the originating request/generation.
    func validate(request: NeuralEvidenceProviderRequest,
                  generation: UInt64) -> [String] {
        var errors: [String] = []

        switch status {
        case .unavailable, .failed:
            return errors // no scores to validate; consumers must skip them
        case .available:
            break
        }

        if frameId != request.frameId {
            errors.append("compositionNet.frameId does not match the request")
        }
        if self.generation != generation {
            errors.append("compositionNet.generation does not match the pipeline generation")
        }
        if mode != request.mode {
            errors.append("compositionNet.mode does not match the request")
        }
        if roiStrategy != request.roiStrategy {
            errors.append(
                "compositionNet.actualROIStrategy \(roiStrategy) mismatches requested \(request.roiStrategy)"
            )
        }
        let subjectROIRelvant = roiStrategy == .subjectCropOnly || request.primarySubjectRegion != nil
        if subjectROIRelvant, subjectROI == nil {
            errors.append("compositionNet is missing the subject ROI provenance")
        }

        let isV1 = heads != nil || outputContractVersion != nil || contractVersion != nil
        if !isV1 {
            for headId in EvidenceHeadId.allCases {
                guard let logit = issueActionLogits[headId] else {
                    errors.append("compositionNet is missing the \(headId.rawValue) head")
                    continue
                }
                if !logit.isFinite {
                    errors.append("compositionNet \(headId.rawValue) logit is not finite")
                }
            }
            for (tag, value) in continuousTargets where !value.isFinite {
                errors.append("compositionNet continuous target \(tag.rawValue) is not finite")
            }
            for (category, value) in shotTypeAffinities where !value.isFinite {
                errors.append("compositionNet shot affinity \(category.rawValue) is not finite")
            }
        }
        for (name, value) in [("riskScore", riskScore),
                              ("abstentionScore", abstentionScore),
                              ("goodFrameScore", goodFrameScore)] where !value.isFinite {
            errors.append("compositionNet \(name) is not finite")
        }
        if riskScore < 0 || riskScore > 1 {
            errors.append("compositionNet riskScore must be within [0, 1]")
        }
        if abstentionScore < 0 || abstentionScore > 1 {
            errors.append("compositionNet abstentionScore must be within [0, 1]")
        }
        if goodFrameScore < 0 || goodFrameScore > 1 {
            errors.append("compositionNet goodFrameScore must be within [0, 1]")
        }
        if heads != nil || outputContractVersion != nil || contractVersion != nil {
            guard let heads else {
                errors.append("compositionNet v1 output heads are missing")
                return errors
            }
            if contractVersion != SETCompositionNetContract.contractVersion {
                errors.append("compositionNet.contractVersion is unsupported")
            }
            if inputContractVersion != SETCompositionNetContract.inputContractVersion {
                errors.append("compositionNet.inputContractVersion is unsupported")
            }
            if preprocessingVersion != SETCompositionNetContract.preprocessingVersion {
                errors.append("compositionNet.preprocessingVersion is unsupported")
            }
            if featureVersion != SETCompositionNetContract.featureVersion {
                errors.append("compositionNet.featureVersion is unsupported")
            }
            if outputContractVersion != SETCompositionNetContract.outputContractVersion {
                errors.append("compositionNet.outputContractVersion is unsupported")
            }
            errors.append(contentsOf: heads.validate())
        }
        return errors
    }
}
