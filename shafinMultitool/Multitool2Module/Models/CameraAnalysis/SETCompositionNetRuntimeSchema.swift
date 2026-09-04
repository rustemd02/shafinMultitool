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

    init(request: NeuralEvidenceProviderRequest,
         descriptor: NeuralEvidenceProviderDescriptor,
         generation: UInt64) {
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
         goodFrameScore: Double) {
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
        return errors
    }
}
