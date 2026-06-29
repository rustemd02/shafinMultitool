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
    var saliencyRegion: CGRect?
}

private struct SendablePixelBuffer: @unchecked Sendable {
    let value: CVPixelBuffer
}

struct LiveHintPresentation: Identifiable, Equatable, Sendable {
    let id: String
    let frameId: String
    let text: String
    let confidence: Double
    let actionType: ActionTypeV1?
    let actionId: String?
    let linkedIssueIds: [String]
    let summaryId: String?
    let traceRootIds: [String]
    let targetRegion: NormalizedRect?
    let overlayHint: OverlayHint?
    let isFallback: Bool
    let expandedVerdict: LiveExpandedVerdictPresentation?
}

struct LiveExpandedVerdictPresentation: Equatable, Sendable {
    let shortVerdict: String
    let supportingText: String?
    let actionText: String?
    let fallbackUsed: Bool
}

enum ConfidenceTone: String, Equatable, Sendable {
    case high
    case medium
    case low
}

struct ConfidencePresentation: Equatable, Sendable {
    let value: Double
    let percent: Int
    let label: String
    let tone: ConfidenceTone

    var shortText: String {
        "\(label) · \(percent)%"
    }

    var accessibilityText: String {
        "Уверенность \(label), \(percent) процентов"
    }

    static func make(_ rawValue: Double) -> ConfidencePresentation {
        let value = min(1.0, max(0.0, rawValue))
        let percent = Int((value * 100.0).rounded())
        let tone: ConfidenceTone
        let label: String
        switch value {
        case 0.75...:
            tone = .high
            label = "высокая"
        case 0.55..<0.75:
            tone = .medium
            label = "средняя"
        default:
            tone = .low
            label = "низкая"
        }
        return ConfidencePresentation(value: value, percent: percent, label: label, tone: tone)
    }
}

extension LiveHintPresentation {
    var confidencePresentation: ConfidencePresentation {
        ConfidencePresentation.make(confidence)
    }
}

struct PauseStrengthRow: Equatable, Sendable {
    let strengthId: String
    let type: StrengthTypeV1
    let rationale: String
    let confidence: Double
    let supportingRegion: NormalizedRect?
    let traceRefId: String?
}

struct PauseIssueRow: Equatable, Sendable {
    let issueId: String
    let type: IssueTypeV1
    let severity: Double
    let confidence: Double
    let rationale: String
    let affectedRegion: NormalizedRect?
    let suggestedFixTypes: [FixTypeV1]
    let traceRefId: String?
}

struct PauseActionRow: Equatable, Sendable {
    let actionId: String
    let actionType: ActionTypeV1
    let semanticActionType: SemanticActionType
    let priority: Int
    let confidence: Double
    let linkedIssueIds: [String]
    let expectedOutcome: String
    let targetRegion: NormalizedRect?
    let overlayHintId: String?
    let traceRefId: String?
}

struct PauseCritiquePresentation: Equatable, Sendable {
    let frameId: String
    let verdict: FrameVerdict
    let verdictConfidence: Double
    let summaryId: String
    let shortVerdict: String
    let whyGood: String?
    let whyProblematic: String?
    let strengths: [PauseStrengthRow]
    let issues: [PauseIssueRow]
    let actions: [PauseActionRow]
    let noChangeRationale: String?
    let assumptions: [String]
    let traceRootIds: [String]
    let fallbackUsed: Bool
}

enum SemanticEvalRuntimeClaim: String, Codable, Equatable, Sendable {
    case labelOracle = "label_oracle"
    case testFixture = "test_fixture"
    case notRealRuntime = "not_real_runtime"
    case realRuntimeStillReplay = "real_runtime_still_replay"
}

struct SemanticEvalCandidateOutput: Codable, Equatable, Sendable {
    let recordId: String
    let filename: String
    let mode: String
    let shown: Bool
    let liveTip: String?
    let pauseSummary: String?
    let semanticActions: [String]
    let futureActions: [String]
    let confidence: Double
    let source: String
    let runtimeClaim: SemanticEvalRuntimeClaim
    let traceIds: [String]
    let debugIssueTypes: [String]
    let debugStrengthTypes: [String]
    let debugActionTypes: [String]
    let debugNumericFeatures: [String: Double]
    let debugSemanticLabels: [String: String]

    private enum CodingKeys: String, CodingKey {
        case recordId = "record_id"
        case filename
        case mode
        case shown
        case liveTip = "live_tip"
        case pauseSummary = "pause_summary"
        case semanticActions = "semantic_actions"
        case futureActions = "future_actions"
        case confidence
        case source
        case runtimeClaim = "runtime_claim"
        case traceIds = "trace_ids"
        case debugIssueTypes = "debug_issue_types"
        case debugStrengthTypes = "debug_strength_types"
        case debugActionTypes = "debug_action_types"
        case debugNumericFeatures = "debug_numeric_features"
        case debugSemanticLabels = "debug_semantic_labels"
    }

    static func live(recordId: String,
                     filename: String,
                     hint: LiveHintPresentation?,
                     source: String,
                     runtimeClaim: SemanticEvalRuntimeClaim,
                     futureActions: [String] = [],
                     dominantFutureActions: [String]? = nil,
                     technicalConfidenceFloor: Double? = nil,
                     traceIds: [String] = [],
                     debugNumericFeatures: [String: Double] = [:],
                     debugSemanticLabels: [String: String] = [:]) -> SemanticEvalCandidateOutput {
        let actionTypes = hint?.actionType.map { [$0] } ?? []
        let dominantActions = effectiveDominantFutureActions(
            explicitDominantFutureActions: dominantFutureActions,
            futureActions: futureActions
        )
        let exportableActionTypes = actionTypes.filter { actionType in
            !hasDominantTechnicalFutureAction(dominantActions) || actionType.semanticActionType != .keepCurrentSetup
        }
        let effectiveTraceIds = traceIds.isEmpty ? (hint?.traceRootIds ?? []) : traceIds
        let confidence = hint.map {
            confidenceWithTechnicalFloor(
                base: $0.confidence,
                technicalConfidenceFloor: technicalConfidenceFloor,
                semanticActions: semanticActionStrings(from: exportableActionTypes),
                futureActions: futureActions,
                traceIds: effectiveTraceIds,
                debugNumericFeatures: debugNumericFeatures,
                debugSemanticLabels: debugSemanticLabels
            )
        } ?? 0
        return SemanticEvalCandidateOutput(
            recordId: recordId,
            filename: filename,
            mode: AnalysisMode.live.rawValue,
            shown: hint != nil,
            liveTip: hint?.text,
            pauseSummary: nil,
            semanticActions: semanticActionStrings(from: exportableActionTypes),
            futureActions: futureActions,
            confidence: confidence,
            source: source,
            runtimeClaim: runtimeClaim,
            traceIds: effectiveTraceIds,
            debugIssueTypes: [],
            debugStrengthTypes: [],
            debugActionTypes: hint?.actionType.map { [$0.rawValue] } ?? [],
            debugNumericFeatures: debugNumericFeatures,
            debugSemanticLabels: debugSemanticLabels
        )
    }

    static func pause(recordId: String,
                      filename: String,
                      critique: PauseCritiquePresentation?,
                      source: String,
                      runtimeClaim: SemanticEvalRuntimeClaim,
                      futureActions: [String] = [],
                      dominantFutureActions: [String]? = nil,
                      technicalConfidenceFloor: Double? = nil,
                      traceIds: [String] = [],
                      debugNumericFeatures: [String: Double] = [:],
                      debugSemanticLabels: [String: String] = [:]) -> SemanticEvalCandidateOutput {
        let dominantActions = dominantFutureActions ?? defaultDominantFutureActions(futureActions)
        let semanticActionTypes = critique?.actions.map(\.semanticActionType) ?? []
        let allowsKeepCurrentSetup = critique.map {
            shouldExportKeepCurrentSetup(
                from: $0,
                dominantFutureActions: dominantActions,
                futureActions: futureActions,
                debugNumericFeatures: debugNumericFeatures,
                debugSemanticLabels: debugSemanticLabels
            )
        } ?? false
        let exportableActionTypes = semanticActionTypes.filter { actionType in
            allowsKeepCurrentSetup || actionType != .keepCurrentSetup
        }
        let semanticActions = semanticActionStrings(
            from: exportableActionTypes,
            includeKeepCurrentSetup: allowsKeepCurrentSetup
        )
        let effectiveTraceIds = traceIds.isEmpty ? (critique?.traceRootIds ?? []) : traceIds
        let confidence = confidenceWithTechnicalFloor(
            base: critique?.verdictConfidence ?? 0,
            technicalConfidenceFloor: technicalConfidenceFloor,
            verdict: critique?.verdict,
            semanticActions: semanticActions,
            futureActions: futureActions,
            traceIds: effectiveTraceIds,
            debugNumericFeatures: debugNumericFeatures,
            debugSemanticLabels: debugSemanticLabels
        )
        return SemanticEvalCandidateOutput(
            recordId: recordId,
            filename: filename,
            mode: AnalysisMode.pause.rawValue,
            shown: critique != nil,
            liveTip: nil,
            pauseSummary: critique?.shortVerdict,
            semanticActions: semanticActions,
            futureActions: futureActions,
            confidence: confidence,
            source: source,
            runtimeClaim: runtimeClaim,
            traceIds: effectiveTraceIds,
            debugIssueTypes: critique?.issues.map { $0.type.rawValue } ?? [],
            debugStrengthTypes: critique?.strengths.map { $0.type.rawValue } ?? [],
            debugActionTypes: critique?.actions.map { $0.actionType.rawValue } ?? [],
            debugNumericFeatures: debugNumericFeatures,
            debugSemanticLabels: debugSemanticLabels
        )
    }

    static func hidden(recordId: String,
                       filename: String,
                       mode: AnalysisMode,
                       source: String,
                       runtimeClaim: SemanticEvalRuntimeClaim,
                       futureActions: [String] = [],
                       traceIds: [String] = [],
                       debugNumericFeatures: [String: Double] = [:],
                       debugSemanticLabels: [String: String] = [:]) -> SemanticEvalCandidateOutput {
        SemanticEvalCandidateOutput(
            recordId: recordId,
            filename: filename,
            mode: mode.rawValue,
            shown: false,
            liveTip: nil,
            pauseSummary: nil,
            semanticActions: [],
            futureActions: futureActions,
            confidence: 0,
            source: source,
            runtimeClaim: runtimeClaim,
            traceIds: traceIds,
            debugIssueTypes: [],
            debugStrengthTypes: [],
            debugActionTypes: [],
            debugNumericFeatures: debugNumericFeatures,
            debugSemanticLabels: debugSemanticLabels
        )
    }

    private static func semanticActionStrings(from actionTypes: [ActionTypeV1],
                                              includeKeepCurrentSetup: Bool = false) -> [String] {
        semanticActionStrings(
            fromSemanticActionTypes: actionTypes.map(\.semanticActionType),
            includeKeepCurrentSetup: includeKeepCurrentSetup
        )
    }

    private static func semanticActionStrings(from actionTypes: [SemanticActionType],
                                              includeKeepCurrentSetup: Bool = false) -> [String] {
        semanticActionStrings(
            fromSemanticActionTypes: actionTypes,
            includeKeepCurrentSetup: includeKeepCurrentSetup
        )
    }

    private static func semanticActionStrings(fromSemanticActionTypes actionTypes: [SemanticActionType],
                                              includeKeepCurrentSetup: Bool = false) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        if includeKeepCurrentSetup {
            seen.insert(SemanticActionType.keepCurrentSetup.rawValue)
            result.append(SemanticActionType.keepCurrentSetup.rawValue)
        }
        for actionType in actionTypes {
            let semanticAction = actionType.rawValue
            if seen.insert(semanticAction).inserted {
                result.append(semanticAction)
            }
        }
        return result
    }

    private static func shouldExportKeepCurrentSetup(from critique: PauseCritiquePresentation,
                                                     dominantFutureActions: [String],
                                                     futureActions: [String],
                                                     debugNumericFeatures: [String: Double],
                                                     debugSemanticLabels: [String: String]) -> Bool {
        guard critique.verdict == .good else { return false }
        if critique.actions.contains(where: { $0.semanticActionType != .keepCurrentSetup }) {
            return false
        }
        if critique.traceRootIds.contains("cinematic_good_frame_action_preservation") {
            return true
        }
        let strengthTypes = Set(critique.strengths.map { $0.type.rawValue })
        let preservesLowKeyMood = shouldPreserveLowKeyMoodKeepCurrentSetup(
            strengthTypes: strengthTypes,
            debugNumericFeatures: debugNumericFeatures,
            debugSemanticLabels: debugSemanticLabels
        )
        let preservesReadableObjectInsert = shouldPreserveReadableObjectInsertKeepCurrentSetup(
            strengthTypes: strengthTypes,
            debugNumericFeatures: debugNumericFeatures,
            debugSemanticLabels: debugSemanticLabels
        )
        let preservesCinematicEstablishing = shouldPreserveCinematicEstablishingKeepCurrentSetup(
            strengthTypes: strengthTypes,
            debugNumericFeatures: debugNumericFeatures,
            debugSemanticLabels: debugSemanticLabels
        )
        let preservesNumericWideEstablishing = shouldPreserveNumericWideGoodEstablishingFrame(
            debugNumericFeatures: debugNumericFeatures
        )
        let hasPositiveEvidence: Bool
        if !critique.strengths.isEmpty {
            hasPositiveEvidence = true
        } else if let rationale = critique.noChangeRationale?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rationale.isEmpty {
            hasPositiveEvidence = true
        } else {
            hasPositiveEvidence = false
        }
        guard hasPositiveEvidence
                || preservesLowKeyMood
                || preservesReadableObjectInsert
                || preservesCinematicEstablishing
                || preservesNumericWideEstablishing else { return false }
        if !preservesLowKeyMood,
           !preservesReadableObjectInsert,
           !preservesCinematicEstablishing,
           !preservesNumericWideEstablishing,
           shouldSuppressFalseKeepCurrentSetup(
            futureActions: futureActions,
            debugNumericFeatures: debugNumericFeatures,
            debugSemanticLabels: debugSemanticLabels
        ) {
            return false
        }
        guard !hasDominantTechnicalFutureAction(dominantFutureActions) ||
                shouldPreserveReadableGoodKeepCurrentSetup(
                    debugNumericFeatures: debugNumericFeatures,
                    debugSemanticLabels: debugSemanticLabels
                ) ||
                preservesReadableObjectInsert ||
                preservesLowKeyMood ||
                preservesCinematicEstablishing ||
                preservesNumericWideEstablishing else {
            return false
        }
        return true
    }

    private static func shouldPreserveNumericWideGoodEstablishingFrame(debugNumericFeatures: [String: Double]) -> Bool {
        let aestheticScore = debugNumericFeatures["aesthetic_score"] ?? 0
        let objectCount = debugNumericFeatures["object_count"] ?? 1
        let personCount = debugNumericFeatures["person_count"] ?? 1
        let subjectArea = debugNumericFeatures["subject_area_ratio"] ?? 1
        let backgroundClutter = debugNumericFeatures["background_clutter"] ?? 1
        let focusCompetition = debugNumericFeatures["focus_competition"] ?? 1
        let sceneTypeConfidence = debugNumericFeatures["scene_type_confidence"] ?? 0
        let exposureBias = debugNumericFeatures["exposure_bias"] ?? 1
        let frameAspectRatio = debugNumericFeatures["frame_aspect_ratio"] ?? 0

        return aestheticScore >= 0.50
            && objectCount == 0
            && personCount == 0
            && subjectArea == 0
            && backgroundClutter <= 0.05
            && focusCompetition <= 0.50
            && sceneTypeConfidence >= 0.50
            && exposureBias > -0.20
            && exposureBias < 0.20
            && frameAspectRatio >= 1.76
    }

    private static func shouldPreserveReadableGoodKeepCurrentSetup(debugNumericFeatures: [String: Double],
                                                                   debugSemanticLabels: [String: String]) -> Bool {
        guard debugSemanticLabels["verdict"] == FrameVerdict.good.rawValue,
              debugSemanticLabels["subject_readable"] == "true",
              debugSemanticLabels["has_clear_focus"] == "true" else {
            return false
        }
        let aestheticScore = debugNumericFeatures["aesthetic_score"] ?? 0
        let subjectArea = debugNumericFeatures["subject_area_ratio"] ?? 0
        let subjectConfidence = debugNumericFeatures["primary_subject_confidence"] ?? 0
        let exposureBias = debugNumericFeatures["exposure_bias"] ?? 0
        return aestheticScore >= 0.40
            && subjectArea >= 0.34
            && subjectArea < 0.55
            && subjectConfidence >= 0.70
            && exposureBias > -1.50
    }

    private static func shouldPreserveLowKeyMoodKeepCurrentSetup(strengthTypes: Set<String>,
                                                                 debugNumericFeatures: [String: Double],
                                                                 debugSemanticLabels: [String: String]) -> Bool {
        guard debugSemanticLabels["verdict"] == FrameVerdict.good.rawValue,
              debugSemanticLabels["primary_subject_kind"] == SubjectKind.unknown.rawValue,
              debugSemanticLabels["subject_readable"] == "false",
              strengthTypes.contains(StrengthTypeV1.goodLightEmphasis.rawValue) else {
            return false
        }
        let aestheticScore = debugNumericFeatures["aesthetic_score"] ?? 0
        let exposureBias = debugNumericFeatures["exposure_bias"] ?? 0
        let objectCount = debugNumericFeatures["object_count"] ?? 0
        let subjectArea = debugNumericFeatures["subject_area_ratio"] ?? 1

        return objectCount == 0
            && subjectArea <= 0.001
            && aestheticScore >= 0.38
            && exposureBias <= -0.70
    }

    private static func shouldPreserveReadableObjectInsertKeepCurrentSetup(strengthTypes: Set<String>,
                                                                           debugNumericFeatures: [String: Double],
                                                                           debugSemanticLabels: [String: String]) -> Bool {
        guard debugSemanticLabels["verdict"] == FrameVerdict.good.rawValue,
              debugSemanticLabels["primary_subject_kind"] == SubjectKind.object.rawValue,
              debugSemanticLabels["subject_readable"] == "true",
              debugSemanticLabels["scene_type"] == SceneTypeV1.objectInsert.rawValue else {
            return false
        }

        let aestheticScore = debugNumericFeatures["aesthetic_score"] ?? 0
        let subjectArea = debugNumericFeatures["subject_area_ratio"] ?? 0
        let subjectConfidence = debugNumericFeatures["primary_subject_confidence"] ?? 0
        let objectCount = debugNumericFeatures["object_count"] ?? 0
        let sceneTypeConfidence = debugNumericFeatures["scene_type_confidence"] ?? 0
        let backgroundClutter = debugNumericFeatures["background_clutter"] ?? 1
        let hasClearFocus = debugSemanticLabels["has_clear_focus"] == "true"
        let hasInsertStrength = strengthTypes.contains(StrengthTypeV1.goodLightEmphasis.rawValue)
            || strengthTypes.contains(StrengthTypeV1.goodSubjectIsolation.rawValue)
            || strengthTypes.contains(StrengthTypeV1.clearFocusHierarchy.rawValue)
            || strengthTypes.contains(StrengthTypeV1.stableHorizonSupportsScene.rawValue)

        return (hasInsertStrength || hasClearFocus)
            && aestheticScore >= 0.37
            && sceneTypeConfidence >= 0.55
            && subjectArea >= 0.04
            && subjectArea <= 0.40
            && subjectConfidence >= 0.35
            && objectCount <= 6
            && backgroundClutter <= 0.80
    }

    private static func shouldPreserveCinematicEstablishingKeepCurrentSetup(strengthTypes: Set<String>,
                                                                            debugNumericFeatures: [String: Double],
                                                                            debugSemanticLabels: [String: String]) -> Bool {
        guard debugSemanticLabels["verdict"] == FrameVerdict.good.rawValue,
              debugSemanticLabels["primary_subject_kind"] == SubjectKind.unknown.rawValue,
              debugSemanticLabels["subject_readable"] == "false",
              debugSemanticLabels["scene_type"] == SceneTypeV1.establishingLikeFrame.rawValue else {
            return false
        }

        let aestheticScore = debugNumericFeatures["aesthetic_score"] ?? 0
        let objectCount = debugNumericFeatures["object_count"] ?? 1
        let personCount = debugNumericFeatures["person_count"] ?? 1
        let subjectArea = debugNumericFeatures["subject_area_ratio"] ?? 1
        let backgroundClutter = debugNumericFeatures["background_clutter"] ?? 1
        let focusCompetition = debugNumericFeatures["focus_competition"] ?? 0
        let sceneTypeConfidence = debugNumericFeatures["scene_type_confidence"] ?? 0
        let exposureBias = debugNumericFeatures["exposure_bias"] ?? 0
        let frameAspectRatio = debugNumericFeatures["frame_aspect_ratio"] ?? 1
        let hasStylisticStrength = strengthTypes.contains(StrengthTypeV1.goodLightEmphasis.rawValue)
            || strengthTypes.contains(StrengthTypeV1.balancedCompositionForScene.rawValue)

        let isNarrativeWideEstablishing = objectCount <= 1
            && personCount == 0
            && subjectArea <= 0.02
            && backgroundClutter <= 0.12
            && frameAspectRatio >= 1.45
            && sceneTypeConfidence >= 0.50
            && focusCompetition <= 0.56
            && exposureBias > -1.60
            && exposureBias < 0.20

        let isCleanOneObjectNarrativeEstablishing = objectCount == 1
            && personCount == 0
            && subjectArea <= 0.02
            && backgroundClutter <= 0.12
            && focusCompetition <= 0.56
            && sceneTypeConfidence >= 0.50
            && exposureBias > -2.35
            && exposureBias < 0.20
            && frameAspectRatio >= 1.40

        guard isNarrativeWideEstablishing || isCleanOneObjectNarrativeEstablishing else {
            return false
        }

        if isCleanOneObjectNarrativeEstablishing {
            return aestheticScore >= 0.415
                || (hasStylisticStrength && aestheticScore >= 0.405)
        }

        if objectCount == 0 {
            return aestheticScore >= 0.42 || hasStylisticStrength
        }

        return aestheticScore >= 0.42
    }

    private static func shouldSuppressFalseKeepCurrentSetup(futureActions: [String],
                                                            debugNumericFeatures: [String: Double],
                                                            debugSemanticLabels: [String: String]) -> Bool {
        guard debugSemanticLabels["verdict"] == FrameVerdict.good.rawValue else { return false }
        let futureActionSet = Set(futureActions)
        let aestheticScore = debugNumericFeatures["aesthetic_score"] ?? 1
        let objectCount = debugNumericFeatures["object_count"] ?? 0
        let subjectArea = debugNumericFeatures["subject_area_ratio"] ?? 0
        let exposureBias = debugNumericFeatures["exposure_bias"] ?? 0
        let subjectReadable = debugSemanticLabels["subject_readable"] == "true"
        let subjectKind = debugSemanticLabels["primary_subject_kind"] ?? ""
        let hasStabilization = futureActionSet.contains(TechnicalQualityActionType.stabilizeCamera.rawValue)
        let hasLowLightNoise = futureActionSet.contains(TechnicalQualityActionType.increaseExposure.rawValue)
            || futureActionSet.contains(TechnicalQualityActionType.reduceIsoNoise.rawValue)
        let hasExposureCorrection = futureActionSet.contains(TechnicalQualityActionType.reduceExposure.rawValue)
        let hasOcclusionPressure = futureActionSet.contains(TechnicalQualityActionType.avoidOcclusion.rawValue)
        let hasRefocusPressure = futureActionSet.contains(TechnicalQualityActionType.refocusSubject.rawValue)

        if subjectKind == SubjectKind.unknown.rawValue,
           !subjectReadable,
           objectCount == 0,
           aestheticScore < 0.46,
            (hasStabilization || hasLowLightNoise) {
            return true
        }

        if subjectKind == SubjectKind.unknown.rawValue,
           !subjectReadable,
           objectCount == 0,
           aestheticScore < 0.56,
           (hasOcclusionPressure || hasRefocusPressure || exposureBias <= -1.0),
           (hasStabilization || hasLowLightNoise || hasRefocusPressure) {
            return true
        }

        if subjectReadable,
           aestheticScore < 0.40,
           subjectArea >= 0.34,
           hasExposureCorrection {
            return true
        }

        if !subjectReadable,
           subjectKind == SubjectKind.unknown.rawValue,
           objectCount <= 1,
           aestheticScore < 0.46,
            (hasStabilization || hasLowLightNoise || hasExposureCorrection) {
            return true
        }

        return false
    }

    private static func defaultDominantFutureActions(_ futureActions: [String]) -> [String] {
        let dominantTechnicalActions: Set<String> = [
            "stabilize_camera",
            "refocus_subject",
            "reduce_exposure",
            "avoid_occlusion",
            "clean_lens"
        ]
        return futureActions.filter { dominantTechnicalActions.contains($0) }
    }

    private static func effectiveDominantFutureActions(explicitDominantFutureActions: [String]?,
                                                       futureActions: [String]) -> [String] {
        if let explicitDominantFutureActions, !explicitDominantFutureActions.isEmpty {
            return explicitDominantFutureActions
        }
        return defaultDominantFutureActions(futureActions)
    }

    private static func hasDominantTechnicalFutureAction(_ futureActions: [String]) -> Bool {
        !futureActions.isEmpty
    }

    private static func confidenceWithTechnicalFloor(base: Double,
                                                     technicalConfidenceFloor: Double?,
                                                     verdict: FrameVerdict? = nil,
                                                     semanticActions: [String] = [],
                                                     futureActions: [String] = [],
                                                     traceIds: [String] = [],
                                                     debugNumericFeatures: [String: Double] = [:],
                                                     debugSemanticLabels: [String: String] = [:]) -> Double {
        let confidence = clamp01(max(base, technicalConfidenceFloor ?? 0))
        if shouldPromoteUnknownMotionBlurBackgroundConfidence(
            confidence: confidence,
            semanticActions: semanticActions,
            futureActions: futureActions,
            debugNumericFeatures: debugNumericFeatures,
            debugSemanticLabels: debugSemanticLabels
        ) {
            return max(confidence, 0.75)
        }
        if shouldPromoteWideUnknownGoodEstablishingKeepConfidence(
            confidence: confidence,
            semanticActions: semanticActions,
            futureActions: futureActions,
            debugNumericFeatures: debugNumericFeatures,
            debugSemanticLabels: debugSemanticLabels
        ) {
            return max(confidence, 0.75)
        }
        if shouldCapPositiveKeepTechnicalFloorConfidence(
            confidence: confidence,
            semanticActions: semanticActions,
            futureActions: futureActions,
            debugNumericFeatures: debugNumericFeatures,
            debugSemanticLabels: debugSemanticLabels
        ) {
            return min(confidence, 0.70)
        }
        if shouldCapMediumEvidencePositiveKeepConfidence(
            confidence: confidence,
            semanticActions: semanticActions,
            futureActions: futureActions,
            debugNumericFeatures: debugNumericFeatures,
            debugSemanticLabels: debugSemanticLabels
        ) {
            return min(confidence, 0.70)
        }
        if shouldCapMediumEvidenceTechnicalCorrectionConfidence(
            confidence: confidence,
            semanticActions: semanticActions,
            futureActions: futureActions,
            traceIds: traceIds,
            debugNumericFeatures: debugNumericFeatures,
            debugSemanticLabels: debugSemanticLabels
        ) {
            return min(confidence, 0.70)
        }
        if shouldCapUnknownNoFocusFrontFillTechnicalConfidence(
            confidence: confidence,
            semanticActions: semanticActions,
            futureActions: futureActions,
            debugNumericFeatures: debugNumericFeatures,
            debugSemanticLabels: debugSemanticLabels
        ) {
            return min(confidence, 0.74)
        }
        if shouldCapContextualUnknownBlurMediumConfidence(
            confidence: confidence,
            semanticActions: semanticActions,
            futureActions: futureActions,
            traceIds: traceIds,
            debugNumericFeatures: debugNumericFeatures,
            debugSemanticLabels: debugSemanticLabels
        ) {
            return min(confidence, 0.70)
        }
        if shouldCapReadableObjectTechnicalSilenceConfidence(
            confidence: confidence,
            semanticActions: semanticActions,
            futureActions: futureActions,
            debugNumericFeatures: debugNumericFeatures,
            debugSemanticLabels: debugSemanticLabels
        ) {
            return min(confidence, 0.74)
        }
        if shouldCapEmptyUnknownTechnicalSilenceConfidence(
            confidence: confidence,
            semanticActions: semanticActions,
            futureActions: futureActions,
            traceIds: traceIds,
            debugNumericFeatures: debugNumericFeatures,
            debugSemanticLabels: debugSemanticLabels
        ) {
            return min(confidence, 0.44)
        }
        if semanticActions.isEmpty,
           traceIds.contains("contextual_unknown_stabilized_technical_silence") {
            return min(confidence, 0.70)
        }
        if traceIds.contains("contextual_underlit_readable_object") {
            return min(confidence, 0.74)
        }
        if traceIds.contains("contextual_readable_underlit_object_front_fill") {
            return min(confidence, 0.74)
        }
        if traceIds.contains("contextual_unknown_noisy_low_light_step_back") {
            return min(confidence, 0.74)
        }
        if traceIds.contains("contextual_unknown_group_framing") {
            return min(confidence, 0.70)
        }
        if shouldCapSmallReadableObjectFocusFutureConfidence(
            confidence: confidence,
            semanticActions: semanticActions,
            futureActions: futureActions,
            traceIds: traceIds,
            debugNumericFeatures: debugNumericFeatures,
            debugSemanticLabels: debugSemanticLabels
        ) {
            return min(confidence, 0.70)
        }
        if shouldPreserveHighWeakSubjectBackgroundConfidence(
            confidence: confidence,
            traceIds: traceIds,
            debugNumericFeatures: debugNumericFeatures
        ) {
            return confidence
        }
        guard verdict == .mixed,
              semanticActions.contains(where: { $0 != SemanticActionType.keepCurrentSetup.rawValue }) else {
            return confidence
        }
        return min(confidence, 0.74)
    }

    private static func shouldCapPositiveKeepTechnicalFloorConfidence(confidence: Double,
                                                                      semanticActions: [String],
                                                                      futureActions: [String],
                                                                      debugNumericFeatures: [String: Double],
                                                                      debugSemanticLabels: [String: String]) -> Bool {
        guard confidence >= 0.995,
              semanticActions == [SemanticActionType.keepCurrentSetup.rawValue],
              !futureActions.isEmpty else {
            return false
        }

        let aestheticScore = debugNumericFeatures["aesthetic_score"] ?? 1.0
        let objectCount = debugNumericFeatures["object_count"] ?? 0
        let subjectArea = debugNumericFeatures["subject_area_ratio"] ?? 0
        let subjectKind = debugSemanticLabels["primary_subject_kind"] ?? ""
        let subjectReadable = debugSemanticLabels["subject_readable"] == "true"

        if subjectKind == SubjectKind.unknown.rawValue,
           !subjectReadable,
           objectCount == 0,
           aestheticScore < 0.43 {
            return true
        }

        if subjectKind == SubjectKind.object.rawValue,
           subjectReadable,
           objectCount >= 2,
           aestheticScore < 0.43,
           (subjectArea >= 0.43 || subjectArea <= 0.25) {
            return true
        }

        return false
    }

    private static func shouldCapMediumEvidencePositiveKeepConfidence(confidence: Double,
                                                                      semanticActions: [String],
                                                                      futureActions: [String],
                                                                      debugNumericFeatures: [String: Double],
                                                                      debugSemanticLabels: [String: String]) -> Bool {
        guard confidence >= 0.75,
              semanticActions == [SemanticActionType.keepCurrentSetup.rawValue],
              !futureActions.isEmpty,
              debugSemanticLabels["verdict"] == FrameVerdict.good.rawValue,
              debugSemanticLabels["primary_subject_kind"] == SubjectKind.object.rawValue,
              debugSemanticLabels["subject_readable"] == "true" else {
            return false
        }

        let aestheticScore = debugNumericFeatures["aesthetic_score"] ?? 1.0
        let exposureBias = debugNumericFeatures["exposure_bias"] ?? 0.0
        let subjectArea = debugNumericFeatures["subject_area_ratio"] ?? 0.0
        let objectCount = debugNumericFeatures["object_count"] ?? 0.0
        let backgroundClutter = debugNumericFeatures["background_clutter"] ?? 0.0
        let subjectLabel = debugSemanticLabels["primary_subject_label"] ?? ""
        let hasStabilizationPressure = futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue)
        let hasClearFocus = debugSemanticLabels["has_clear_focus"] == "true"

        if shouldPreserveAmbiguousCurtainBoundaryConfidence(
            subjectLabel: subjectLabel,
            objectCount: objectCount,
            subjectArea: subjectArea,
            backgroundClutter: backgroundClutter,
            exposureBias: exposureBias,
            hasClearFocus: hasClearFocus
        ) {
            return false
        }

        if hasStabilizationPressure,
           aestheticScore < 0.50,
           subjectArea < 0.30,
           exposureBias > -1.20 {
            return true
        }

        if objectCount >= 4,
           subjectArea >= 0.55,
           backgroundClutter >= 0.55,
           debugSemanticLabels["has_clear_focus"] == "false",
           futureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue) {
            return true
        }

        if confidence >= 0.995,
           objectCount >= 2,
           aestheticScore < 0.46,
           (exposureBias > -1.0 || subjectArea < 0.30 || backgroundClutter >= 0.40) {
            return true
        }

        if confidence >= 0.995,
           subjectLabel == "light",
           objectCount == 1,
           subjectArea >= 0.40,
           aestheticScore < 0.40,
           exposureBias <= -1.50,
           backgroundClutter <= 0.15 {
            return true
        }

        return false
    }

    private static func shouldPreserveAmbiguousCurtainBoundaryConfidence(subjectLabel: String,
                                                                         objectCount: Double,
                                                                         subjectArea: Double,
                                                                         backgroundClutter: Double,
                                                                         exposureBias: Double,
                                                                         hasClearFocus: Bool) -> Bool {
        guard subjectLabel == "curtain" else {
            return false
        }

        if objectCount >= 5,
           subjectArea < 0.20,
           backgroundClutter >= 0.70,
           exposureBias <= -1.0 {
            return true
        }

        if objectCount <= 2,
           hasClearFocus,
           subjectArea < 0.12,
           backgroundClutter <= 0.40,
           exposureBias > -0.50 {
            return true
        }

        return false
    }

    private static func shouldPromoteUnknownMotionBlurBackgroundConfidence(confidence: Double,
                                                                           semanticActions: [String],
                                                                           futureActions: [String],
                                                                           debugNumericFeatures: [String: Double],
                                                                           debugSemanticLabels: [String: String]) -> Bool {
        guard confidence < 0.75,
              semanticActions.contains(SemanticActionType.changeCameraAngle.rawValue),
              semanticActions.contains(SemanticActionType.moveObjectBack.rawValue),
              futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue),
              futureActions.contains(TechnicalQualityActionType.reduceExposure.rawValue),
              debugSemanticLabels["verdict"] == FrameVerdict.mixed.rawValue,
              debugSemanticLabels["primary_subject_kind"] == SubjectKind.unknown.rawValue,
              debugSemanticLabels["subject_readable"] == "false" else {
            return false
        }

        let aestheticScore = debugNumericFeatures["aesthetic_score"] ?? 0.0
        let horizonConfidence = debugNumericFeatures["horizon_confidence"] ?? 0.0
        let objectCount = debugNumericFeatures["object_count"] ?? 0.0
        let subjectArea = debugNumericFeatures["subject_area_ratio"] ?? 1.0
        return objectCount == 2
            && subjectArea == 0
            && aestheticScore >= 0.44
            && horizonConfidence >= 0.50
    }

    private static func shouldPromoteWideUnknownGoodEstablishingKeepConfidence(confidence: Double,
                                                                               semanticActions: [String],
                                                                               futureActions: [String],
                                                                               debugNumericFeatures: [String: Double],
                                                                               debugSemanticLabels: [String: String]) -> Bool {
        guard confidence < 0.75,
              semanticActions == [SemanticActionType.keepCurrentSetup.rawValue] else {
            return false
        }

        let allowedFutureActions: Set<String> = [
            TechnicalQualityActionType.stabilizeCamera.rawValue,
            TechnicalQualityActionType.refocusSubject.rawValue,
            TechnicalQualityActionType.reduceIsoNoise.rawValue,
            TechnicalQualityActionType.increaseExposure.rawValue
        ]
        guard futureActions.allSatisfy({ allowedFutureActions.contains($0) }) else {
            return false
        }
        if shouldPreserveNumericWideGoodEstablishingFrame(debugNumericFeatures: debugNumericFeatures) {
            return true
        }
        return debugSemanticLabels["verdict"] == FrameVerdict.good.rawValue
            && debugSemanticLabels["scene_type"] == SceneTypeV1.establishingLikeFrame.rawValue
            && debugSemanticLabels["primary_subject_kind"] == SubjectKind.unknown.rawValue
            && debugSemanticLabels["subject_readable"] == "false"
    }

    private static func shouldCapMediumEvidenceTechnicalCorrectionConfidence(confidence: Double,
                                                                             semanticActions: [String],
                                                                             futureActions: [String],
                                                                             traceIds: [String],
                                                                             debugNumericFeatures: [String: Double],
                                                                             debugSemanticLabels: [String: String]) -> Bool {
        guard confidence >= 0.75,
              traceIds.contains("technical_quality_overexposure"),
              semanticActions.contains(SemanticActionType.simplifyBackground.rawValue),
              futureActions.contains(TechnicalQualityActionType.reduceExposure.rawValue),
              futureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue),
              debugSemanticLabels["primary_subject_kind"] == SubjectKind.object.rawValue,
              debugSemanticLabels["subject_readable"] == "true" else {
            return false
        }

        let aestheticScore = debugNumericFeatures["aesthetic_score"] ?? 1.0
        let exposureBias = debugNumericFeatures["exposure_bias"] ?? 0.0
        let subjectArea = debugNumericFeatures["subject_area_ratio"] ?? 1.0
        let objectCount = debugNumericFeatures["object_count"] ?? 0.0
        let backgroundClutter = debugNumericFeatures["background_clutter"] ?? 0.0
        return objectCount >= 2
            && (0.10...0.22).contains(subjectArea)
            && (0.40...0.43).contains(aestheticScore)
            && exposureBias <= -0.50
            && backgroundClutter >= 0.30
    }

    private static func shouldCapUnknownNoFocusFrontFillTechnicalConfidence(confidence: Double,
                                                                            semanticActions: [String],
                                                                            futureActions: [String],
                                                                            debugNumericFeatures: [String: Double],
                                                                            debugSemanticLabels: [String: String]) -> Bool {
        guard confidence >= 0.75,
              semanticActions.contains(SemanticActionType.addFrontFillLight.rawValue),
              semanticActions.contains(SemanticActionType.rotateSubjectTowardLight.rawValue),
              futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue),
              futureActions.contains(TechnicalQualityActionType.refocusSubject.rawValue),
              futureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue),
              debugSemanticLabels["verdict"] == FrameVerdict.needsFix.rawValue,
              debugSemanticLabels["primary_subject_kind"] == SubjectKind.unknown.rawValue,
              debugSemanticLabels["subject_readable"] == "false",
              debugSemanticLabels["has_clear_focus"] == "false" else {
            return false
        }

        let aestheticScore = debugNumericFeatures["aesthetic_score"] ?? 1.0
        let exposureBias = debugNumericFeatures["exposure_bias"] ?? 0.0
        let objectCount = debugNumericFeatures["object_count"] ?? 0.0
        let subjectArea = debugNumericFeatures["subject_area_ratio"] ?? 1.0
        return objectCount >= 3
            && subjectArea == 0
            && (0.39...0.43).contains(aestheticScore)
            && (-1.10 ... -0.80).contains(exposureBias)
    }

    private static func shouldCapContextualUnknownBlurMediumConfidence(confidence: Double,
                                                                       semanticActions: [String],
                                                                       futureActions: [String],
                                                                       traceIds: [String],
                                                                       debugNumericFeatures: [String: Double],
                                                                       debugSemanticLabels: [String: String]) -> Bool {
        guard (0.75...0.87).contains(confidence),
              traceIds.contains("contextual_unknown_blur_simplify_background"),
              semanticActions == [SemanticActionType.simplifyBackground.rawValue],
              futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue),
              futureActions.contains(TechnicalQualityActionType.refocusSubject.rawValue),
              futureActions.contains(TechnicalQualityActionType.reduceExposure.rawValue),
              debugSemanticLabels["primary_subject_kind"] == SubjectKind.unknown.rawValue,
              debugSemanticLabels["subject_readable"] == "false" else {
            return false
        }

        let aestheticScore = debugNumericFeatures["aesthetic_score"] ?? 1.0
        let objectCount = debugNumericFeatures["object_count"] ?? 1.0
        let subjectArea = debugNumericFeatures["subject_area_ratio"] ?? 1.0
        let exposureBias = debugNumericFeatures["exposure_bias"] ?? 0.0
        return objectCount == 0
            && subjectArea == 0
            && (0.36...0.39).contains(aestheticScore)
            && exposureBias > 0.20
    }

    private static func shouldCapReadableObjectTechnicalSilenceConfidence(confidence: Double,
                                                                          semanticActions: [String],
                                                                          futureActions: [String],
                                                                          debugNumericFeatures: [String: Double],
                                                                          debugSemanticLabels: [String: String]) -> Bool {
        guard confidence >= 0.75,
              confidence < 0.80,
              semanticActions.isEmpty,
              futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue),
              futureActions.contains(TechnicalQualityActionType.reduceExposure.rawValue),
              !futureActions.contains(TechnicalQualityActionType.refocusSubject.rawValue),
              debugSemanticLabels["verdict"] == FrameVerdict.good.rawValue,
              debugSemanticLabels["primary_subject_kind"] == SubjectKind.object.rawValue,
              debugSemanticLabels["subject_readable"] == "true" else {
            return false
        }

        let aestheticScore = debugNumericFeatures["aesthetic_score"] ?? 1.0
        let exposureBias = debugNumericFeatures["exposure_bias"] ?? 0.0
        let subjectArea = debugNumericFeatures["subject_area_ratio"] ?? 0.0
        let objectCount = debugNumericFeatures["object_count"] ?? 0.0
        let horizonConfidence = debugNumericFeatures["horizon_confidence"] ?? 0.0
        return objectCount == 1
            && subjectArea >= 0.40
            && aestheticScore < 0.40
            && exposureBias >= 0.50
            && horizonConfidence >= 0.75
    }

    private static func shouldCapEmptyUnknownTechnicalSilenceConfidence(confidence: Double,
                                                                        semanticActions: [String],
                                                                        futureActions: [String],
                                                                        traceIds: [String],
                                                                        debugNumericFeatures: [String: Double],
                                                                        debugSemanticLabels: [String: String]) -> Bool {
        guard confidence >= 0.75,
              semanticActions.isEmpty,
              !traceIds.contains("technical_quality_motion_blur"),
              futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue),
              futureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue),
              debugSemanticLabels["primary_subject_kind"] == SubjectKind.unknown.rawValue,
              debugSemanticLabels["subject_readable"] == "false" else {
            return false
        }

        let aestheticScore = debugNumericFeatures["aesthetic_score"] ?? 1.0
        let exposureBias = debugNumericFeatures["exposure_bias"] ?? 0.0
        let objectCount = debugNumericFeatures["object_count"] ?? 1.0
        let subjectArea = debugNumericFeatures["subject_area_ratio"] ?? 1.0
        return objectCount == 0
            && subjectArea == 0
            && (0.39...0.42).contains(aestheticScore)
            && abs(exposureBias) < 0.05
    }

    private static func shouldPreserveHighWeakSubjectBackgroundConfidence(confidence: Double,
                                                                          traceIds: [String],
                                                                          debugNumericFeatures: [String: Double]) -> Bool {
        guard confidence >= 0.75,
              traceIds.contains("contextual_weak_subject_background") else {
            return false
        }

        let exposureBias = debugNumericFeatures["exposure_bias"] ?? 0.0
        let subjectArea = debugNumericFeatures["subject_area_ratio"] ?? 1.0
        let objectCount = debugNumericFeatures["object_count"] ?? 0.0
        return objectCount == 1
            && subjectArea < 0.10
            && exposureBias <= -1.20
    }

    private static func shouldCapSmallReadableObjectFocusFutureConfidence(confidence: Double,
                                                                          semanticActions: [String],
                                                                          futureActions: [String],
                                                                          traceIds: [String],
                                                                          debugNumericFeatures: [String: Double],
                                                                          debugSemanticLabels: [String: String]) -> Bool {
        guard confidence >= 0.75,
              traceIds.contains("technical_quality_overexposure"),
              semanticActions.contains(SemanticActionType.simplifyBackground.rawValue),
              futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue),
              futureActions.contains(TechnicalQualityActionType.refocusSubject.rawValue),
              debugSemanticLabels["verdict"] == FrameVerdict.good.rawValue,
              debugSemanticLabels["primary_subject_kind"] == SubjectKind.object.rawValue,
              debugSemanticLabels["subject_readable"] == "true" else {
            return false
        }

        let aestheticScore = debugNumericFeatures["aesthetic_score"] ?? 1.0
        let subjectArea = debugNumericFeatures["subject_area_ratio"] ?? 1.0
        let exposureBias = debugNumericFeatures["exposure_bias"] ?? 0.0
        let objectCount = debugNumericFeatures["object_count"] ?? 0.0
        let backgroundClutter = debugNumericFeatures["background_clutter"] ?? 1.0
        return objectCount >= 2
            && subjectArea < 0.22
            && (0.40...0.43).contains(aestheticScore)
            && exposureBias <= -0.55
            && backgroundClutter <= 0.25
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}

#if DEBUG
struct SemanticEvalStillImageReplayOptions: Equatable, Sendable {
    let runHeavyModels: Bool
    let runNeuralEvidence: Bool
    let runVisualEvidence: Bool
    let source: String

    var runtimeClaim: SemanticEvalRuntimeClaim {
        runHeavyModels ? .realRuntimeStillReplay : .testFixture
    }

    static let fullRuntime = SemanticEvalStillImageReplayOptions(
        runHeavyModels: true,
        runNeuralEvidence: true,
        runVisualEvidence: true,
        source: "swift_still_image_replay"
    )

    static let lightweightTest = SemanticEvalStillImageReplayOptions(
        runHeavyModels: false,
        runNeuralEvidence: false,
        runVisualEvidence: false,
        source: "swift_still_image_replay_lightweight_test"
    )
}

struct SemanticEvalStillImageReplayResult: Equatable, Sendable {
    let recordId: String
    let filename: String
    let frameId: String
    let liveRow: SemanticEvalCandidateOutput
    let pauseRow: SemanticEvalCandidateOutput

    var rows: [SemanticEvalCandidateOutput] {
        [liveRow, pauseRow]
    }
}
#endif

struct TechnicalQualityAnalyzer {
    private struct ImageQualityMetrics {
        let meanLuma: Double
        let darkRatio: Double
        let deepShadowRatio: Double
        let clippedBrightRatio: Double
        let brightHotspotRatio: Double
        let centerMeanLuma: Double
        let maxSideBrightRatio: Double
        let gradientMean: Double
        let gradientVariance: Double
    }

    func signal(pixelBuffer: CVPixelBuffer) -> TechnicalQualitySignal {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            return .empty
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return .empty
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let sampleWidth = min(96, max(1, width))
        let sampleHeight = min(96, max(1, height))
        let stepX = max(1, width / sampleWidth)
        let stepY = max(1, height / sampleHeight)
        var lumaGrid: [Double] = []
        lumaGrid.reserveCapacity(sampleWidth * sampleHeight)

        for gridY in 0..<sampleHeight {
            let sourceY = min(height - 1, gridY * stepY)
            let row = baseAddress.advanced(by: sourceY * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for gridX in 0..<sampleWidth {
                let sourceX = min(width - 1, gridX * stepX)
                let offset = sourceX * 4
                let blue = Double(row[offset])
                let green = Double(row[offset + 1])
                let red = Double(row[offset + 2])
                lumaGrid.append((0.2126 * red) + (0.7152 * green) + (0.0722 * blue))
            }
        }

        guard !lumaGrid.isEmpty else { return .empty }

        let pixelCount = Double(lumaGrid.count)
        let meanLuma = (lumaGrid.reduce(0, +) / pixelCount) / 255.0
        let darkRatio = Double(lumaGrid.filter { $0 < 25 }.count) / pixelCount
        let deepShadowRatio = Double(lumaGrid.filter { $0 < 45 }.count) / pixelCount
        let clippedBrightRatio = Double(lumaGrid.filter { $0 > 235 }.count) / pixelCount
        let brightHotspotRatio = Double(lumaGrid.filter { $0 > 220 }.count) / pixelCount
        let spatialStats = spatialLumaStats(lumaGrid: lumaGrid, width: sampleWidth, height: sampleHeight)
        let (gradientMean, gradientVariance) = gradientStats(lumaGrid: lumaGrid, width: sampleWidth, height: sampleHeight)
        let metrics = ImageQualityMetrics(
            meanLuma: meanLuma,
            darkRatio: darkRatio,
            deepShadowRatio: deepShadowRatio,
            clippedBrightRatio: clippedBrightRatio,
            brightHotspotRatio: brightHotspotRatio,
            centerMeanLuma: spatialStats.centerMean,
            maxSideBrightRatio: spatialStats.maxSideBrightRatio,
            gradientMean: gradientMean,
            gradientVariance: gradientVariance
        )

        var issues: [TechnicalQualityIssueSignal] = []
        issues.append(contentsOf: exposureIssues(metrics))
        issues.append(contentsOf: sharpnessIssues(metrics))
        issues.append(contentsOf: lowLightTextureIssues(metrics))

        return TechnicalQualitySignal(issues: deduplicatedIssues(issues))
    }

    private func exposureIssues(_ metrics: ImageQualityMetrics) -> [TechnicalQualityIssueSignal] {
        var issues: [TechnicalQualityIssueSignal] = []
        let hasClippedHotspot = metrics.clippedBrightRatio >= 0.055 && metrics.meanLuma >= 0.36
        let hasWideHotspot = metrics.brightHotspotRatio >= 0.060 && metrics.meanLuma >= 0.38
        let hasFlashLikeContrast = metrics.clippedBrightRatio >= 0.022
            && metrics.deepShadowRatio >= 0.40
            && metrics.gradientMean >= 35
        if hasClippedHotspot || hasWideHotspot || hasFlashLikeContrast {
            let severity = max(
                normalized(metrics.clippedBrightRatio, lower: 0.04, upper: 0.18),
                normalized(metrics.brightHotspotRatio, lower: 0.06, upper: 0.22),
                normalized(metrics.meanLuma, lower: 0.52, upper: 0.72) * 0.7
            )
            issues.append(
                TechnicalQualityIssueSignal(
                    type: .overexposure,
                    actionType: .reduceExposure,
                    confidence: max(0.55, severity),
                    severity: max(0.50, severity),
                    isDominant: isDominantOverexposure(metrics)
                )
            )
        }

        let hasUnderexposure = (metrics.deepShadowRatio >= 0.46 && metrics.meanLuma <= 0.36)
            || (metrics.meanLuma <= 0.18 && metrics.darkRatio >= 0.35)
        if hasUnderexposure {
            let severity = max(
                normalized(metrics.deepShadowRatio, lower: 0.40, upper: 0.85),
                normalized(0.36 - metrics.meanLuma, lower: 0.0, upper: 0.30)
            )
            let isDominant = isDominantUnderexposure(metrics)
            issues.append(
                TechnicalQualityIssueSignal(
                    type: .underexposure,
                    actionType: .increaseExposure,
                    confidence: max(isDominant ? 0.58 : 0.52, severity),
                    severity: max(isDominant ? 0.55 : 0.45, severity),
                    isDominant: isDominant
                )
            )
        }
        return issues
    }

    private func isDominantOverexposure(_ metrics: ImageQualityMetrics) -> Bool {
        metrics.clippedBrightRatio >= 0.10
            || metrics.brightHotspotRatio >= 0.16
            || metrics.meanLuma >= 0.68
            || (metrics.clippedBrightRatio >= 0.055 && metrics.meanLuma >= 0.48)
            || (metrics.brightHotspotRatio >= 0.090 && metrics.meanLuma >= 0.48)
    }

    private func isDominantUnderexposure(_ metrics: ImageQualityMetrics) -> Bool {
        metrics.meanLuma <= 0.36
            && metrics.deepShadowRatio >= 0.40
            && metrics.centerMeanLuma <= 0.30
            && metrics.maxSideBrightRatio >= 0.20
    }

    private func sharpnessIssues(_ metrics: ImageQualityMetrics) -> [TechnicalQualityIssueSignal] {
        guard metrics.meanLuma >= 0.08 else { return [] }
        var issues: [TechnicalQualityIssueSignal] = []
        let lowTextureDefocus = metrics.meanLuma >= 0.12
            && ((metrics.gradientVariance <= 780 && metrics.gradientMean <= 38)
                || metrics.gradientMean <= 13)
        let motionSoftness = (metrics.gradientVariance <= 1150 && metrics.gradientMean <= 32)
            || metrics.gradientMean <= 14

        if lowTextureDefocus {
            let severity = max(
                normalized(780 - metrics.gradientVariance, lower: 0, upper: 780),
                normalized(38 - metrics.gradientMean, lower: 0, upper: 38)
            )
            issues.append(
                TechnicalQualityIssueSignal(
                    type: .defocus,
                    actionType: .refocusSubject,
                    confidence: max(0.55, severity),
                    severity: max(0.50, severity),
                    isDominant: isDominantSharpnessFailure(metrics)
                )
            )
        }

        if motionSoftness {
            let severity = max(
                normalized(1150 - metrics.gradientVariance, lower: 0, upper: 1150),
                normalized(32 - metrics.gradientMean, lower: 0, upper: 32)
            )
            issues.append(
                TechnicalQualityIssueSignal(
                    type: .motionBlur,
                    actionType: .stabilizeCamera,
                    confidence: max(0.50, severity),
                    severity: max(0.45, severity),
                    isDominant: isDominantSharpnessFailure(metrics)
                )
            )
        }
        return issues
    }

    private func isDominantSharpnessFailure(_ metrics: ImageQualityMetrics) -> Bool {
        guard metrics.meanLuma >= 0.12 else { return false }
        return metrics.gradientVariance <= 850 || metrics.gradientMean <= 13
    }

    private func lowLightTextureIssues(_ metrics: ImageQualityMetrics) -> [TechnicalQualityIssueSignal] {
        var issues: [TechnicalQualityIssueSignal] = []
        if metrics.meanLuma <= 0.30,
           metrics.deepShadowRatio >= 0.30,
           metrics.gradientMean <= 42 {
            let severity = max(
                normalized(0.30 - metrics.meanLuma, lower: 0, upper: 0.24),
                normalized(metrics.deepShadowRatio, lower: 0.30, upper: 0.75)
            )
            issues.append(
                TechnicalQualityIssueSignal(
                    type: .noise,
                    actionType: .reduceIsoNoise,
                    confidence: max(0.45, severity),
                    severity: max(0.40, severity)
                )
            )
        }

        if metrics.meanLuma <= 0.30,
           metrics.deepShadowRatio >= 0.45,
           metrics.gradientMean >= 30 {
            issues.append(
                TechnicalQualityIssueSignal(
                    type: .motionBlur,
                    actionType: .stabilizeCamera,
                    confidence: 0.50,
                    severity: 0.45
                )
            )
        }
        return issues
    }

    private func deduplicatedIssues(_ issues: [TechnicalQualityIssueSignal]) -> [TechnicalQualityIssueSignal] {
        var bestByType: [TechnicalQualityIssueType: TechnicalQualityIssueSignal] = [:]
        for issue in issues {
            if let existing = bestByType[issue.type] {
                if issue.severity > existing.severity
                    || (issue.severity == existing.severity && issue.confidence > existing.confidence) {
                    bestByType[issue.type] = issue
                }
            } else {
                bestByType[issue.type] = issue
            }
        }
        return bestByType.values.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return lhs.type.rawValue < rhs.type.rawValue
        }
    }

    private func spatialLumaStats(lumaGrid: [Double], width: Int, height: Int) -> (centerMean: Double, maxSideBrightRatio: Double) {
        guard width > 0, height > 0 else { return (0, 0) }
        let centerMinX = width / 4
        let centerMaxX = max(centerMinX + 1, (width * 3) / 4)
        let centerMinY = height / 4
        let centerMaxY = max(centerMinY + 1, (height * 3) / 4)
        let leftMaxX = max(1, width / 3)
        let rightMinX = min(width - 1, (width * 2) / 3)
        var centerSum = 0.0
        var centerCount = 0
        var leftBrightCount = 0
        var leftCount = 0
        var rightBrightCount = 0
        var rightCount = 0

        for y in 0..<height {
            for x in 0..<width {
                let luma = lumaGrid[(y * width) + x]
                if x >= centerMinX && x < centerMaxX && y >= centerMinY && y < centerMaxY {
                    centerSum += luma
                    centerCount += 1
                }
                if x < leftMaxX {
                    leftCount += 1
                    if luma > 180 { leftBrightCount += 1 }
                } else if x >= rightMinX {
                    rightCount += 1
                    if luma > 180 { rightBrightCount += 1 }
                }
            }
        }

        let centerMean = centerCount > 0 ? (centerSum / Double(centerCount)) / 255.0 : 0
        let leftBrightRatio = leftCount > 0 ? Double(leftBrightCount) / Double(leftCount) : 0
        let rightBrightRatio = rightCount > 0 ? Double(rightBrightCount) / Double(rightCount) : 0
        return (centerMean, max(leftBrightRatio, rightBrightRatio))
    }

    private func gradientStats(lumaGrid: [Double], width: Int, height: Int) -> (mean: Double, variance: Double) {
        guard width >= 3, height >= 3 else { return (0, 0) }

        var gradients: [Double] = []
        gradients.reserveCapacity((width - 2) * (height - 2))
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let index = (y * width) + x
                let gx = lumaGrid[index + 1] - lumaGrid[index - 1]
                let gy = lumaGrid[index + width] - lumaGrid[index - width]
                gradients.append(abs(gx) + abs(gy))
            }
        }

        guard !gradients.isEmpty else { return (0, 0) }

        let mean = gradients.reduce(0, +) / Double(gradients.count)
        let variance = gradients.reduce(0) { partial, value in
            let delta = value - mean
            return partial + (delta * delta)
        } / Double(gradients.count)
        return (mean, variance)
    }

    private func normalized(_ value: Double, lower: Double, upper: Double) -> Double {
        guard upper > lower else { return 0 }
        return min(1.0, max(0.0, (value - lower) / (upper - lower)))
    }
}

#if DEBUG
typealias SemanticEvalTechnicalQualityProbe = TechnicalQualityAnalyzer
#endif

extension ActionTypeV1 {
    var semanticActionType: SemanticActionType {
        switch self {
        case .moveFrameLeft:
            return .shiftFrameLeft
        case .moveFrameRight:
            return .shiftFrameRight
        case .moveFrameUp:
            return .shiftFrameUp
        case .moveFrameDown:
            return .shiftFrameDown
        case .increaseSubjectSize:
            return .stepCloser
        case .reduceBackgroundDistractions:
            return .simplifyBackground
        case .changeAngle:
            return .changeCameraAngle
        case .improveFrontLight:
            return .addFrontFillLight
        case .levelHorizon:
            return .levelHorizon
        case .leaveFrameAsIs:
            return .keepCurrentSetup
        }
    }
}

struct OverlayAnnotationPresentation: Identifiable, Equatable, Sendable {
    enum Tone: String, Equatable, Sendable {
        case neutral
        case success
        case warning
        case danger
    }

    let id: String
    let kind: OverlayKind
    let direction: OverlayDirection?
    let targetRegion: NormalizedRect?
    let emphasis: Double
    let tone: Tone
    let label: String?

    init(id: String,
         kind: OverlayKind,
         direction: OverlayDirection?,
         targetRegion: NormalizedRect?,
         emphasis: Double,
         tone: Tone = .neutral,
         label: String? = nil) {
        self.id = id
        self.kind = kind
        self.direction = direction
        self.targetRegion = targetRegion
        self.emphasis = emphasis
        self.tone = tone
        self.label = label
    }
}

private enum DemoCoachingSubjectKind: String, Equatable {
    case object
    case portrait
    case dialogue
}

private struct DemoCoachingSubject: Equatable {
    let kind: DemoCoachingSubjectKind
    let rawLabel: String?
    let displayLabel: String
    let region: NormalizedRect
    let confidence: Double
}

private struct DemoSubjectTrack {
    var subject: DemoCoachingSubject
    var stableCount: Int
    var missCount: Int
    var lastSeenAt: Date
}

private struct DemoCinematicPortraitStepEvidence {
    var lighting: FrameFeatureSnapshot.LightingFeatures.SubjectLightingMetrics?
    var presentationCount: Int

    static var empty: DemoCinematicPortraitStepEvidence {
        DemoCinematicPortraitStepEvidence(lighting: nil, presentationCount: 0)
    }
}

private enum DemoCinematicPortraitStep: String {
    case darkenBackground
    case addFaceLight
    case reduceFaceOverexposure
    case complete
}

private struct DemoCoachingDecision {
    let hint: LiveHintPresentation?
    let annotations: [OverlayAnnotationPresentation]
    let suppressesPipelineHint: Bool
}

private struct DemoCoachingRule {
    let id: String
    let text: String
    let shortVerdict: String
    let supportingText: String
    let actionText: String?
    let actionType: ActionTypeV1?
    let tone: OverlayAnnotationPresentation.Tone
    let confidence: Double
    let showHint: Bool
}

struct RecommendationPlanner {
    func makePlan(snapshot: FrameFeatureSnapshot, critique: CritiqueReport) -> RecommendationPlan {
        let rankedIssues = critique.issues.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }
            return lhs.type.rawValue < rhs.type.rawValue
        }

        if critique.verdict == .good {
            let rationale = nonEmpty(critique.summary.whyGood)
                ?? nonEmpty(critique.summary.shortVerdict)
                ?? "Кадр можно оставить как есть."
            return RecommendationPlan(
                frameId: snapshot.frameId,
                mode: snapshot.mode,
                inputVerdict: critique.verdict,
                primaryAction: nil,
                secondaryActions: [],
                deferredActions: [],
                noChangeRationale: rationale,
                planConfidence: critique.verdictConfidence
            )
        }

        let actions = rankedIssues.enumerated().compactMap { index, issue in
            makeAction(
                issue: issue,
                rank: index + 1,
                snapshot: snapshot,
                verdictConfidence: critique.verdictConfidence
            )
        }

        let primaryAction = actions.first
        let secondaryActions: [RecommendationAction]
        let deferredActions: [RecommendationAction]
        if snapshot.mode == .live {
            secondaryActions = []
            deferredActions = []
        } else {
            secondaryActions = Array(actions.dropFirst().prefix(2))
            deferredActions = Array(actions.dropFirst(3))
        }

        return RecommendationPlan(
            frameId: snapshot.frameId,
            mode: snapshot.mode,
            inputVerdict: critique.verdict,
            primaryAction: primaryAction,
            secondaryActions: secondaryActions,
            deferredActions: deferredActions,
            noChangeRationale: nil,
            planConfidence: critique.verdictConfidence
        )
    }

    private func makeAction(issue: FrameIssue,
                            rank: Int,
                            snapshot: FrameFeatureSnapshot,
                            verdictConfidence: Double) -> RecommendationAction? {
        let actionType = actionType(for: issue.type, composition: snapshot.composition)
        if actionType == .leaveFrameAsIs {
            return nil
        }

        let expectedOutcome = expectedOutcome(for: actionType)
        let targetRegion = issue.affectedRegion
        let overlayHint = overlayHint(actionType: actionType, actionRank: rank, targetRegion: targetRegion)
        let actionId = "act_\(snapshot.mode.rawValue)_\(rank)_\(actionType.rawValue)_\(issue.type.rawValue)"
        let guardrail = ActionGuardrail(
            requiresStillCamera: requiresStillCamera(actionType),
            minConfidence: clamp01(max(0.30, min(issue.confidence, verdictConfidence))),
            suppressWhenMoving: suppressWhenMoving(actionType)
        )

        return RecommendationAction(
            id: actionId,
            actionType: actionType,
            priority: rank,
            targetRegion: targetRegion,
            linkedIssueIds: [issue.id],
            expectedOutcome: expectedOutcome,
            guardrail: guardrail,
            overlayHint: overlayHint
        )
    }

    private func actionType(for issueType: IssueTypeV1,
                            composition: FrameFeatureSnapshot.CompositionFeatures) -> ActionTypeV1 {
        switch issueType {
        case .horizonDistracts:
            return .levelHorizon
        case .backlightHidesSubject:
            return .improveFrontLight
        case .subjectNotProminentEnough:
            return .increaseSubjectSize
        case .subjectTooCloseToEdge, .insufficientLookSpace:
            if composition.horizontalOffset > 0.15 { return .moveFrameLeft }
            if composition.horizontalOffset < -0.15 { return .moveFrameRight }
            if composition.verticalOffset > 0.15 { return .moveFrameDown }
            if composition.verticalOffset < -0.15 { return .moveFrameUp }
            return .changeAngle
        case .backgroundCompetesWithSubject:
            return .reduceBackgroundDistractions
        case .sceneHasNoClearFocus, .frameVisuallyOverloaded:
            return .changeAngle
        }
    }

    private func expectedOutcome(for actionType: ActionTypeV1) -> String {
        switch actionType {
        case .moveFrameLeft:
            return "Сместите кадр немного влево, чтобы вернуть баланс."
        case .moveFrameRight:
            return "Сместите кадр немного вправо, чтобы вернуть баланс."
        case .moveFrameUp:
            return "Поднимите кадр чуть выше для лучшей композиции."
        case .moveFrameDown:
            return "Опустите кадр чуть ниже для лучшей композиции."
        case .increaseSubjectSize:
            return "Сделайте главный объект крупнее, чтобы усилить фокус."
        case .reduceBackgroundDistractions:
            return "Упростите фон или смените ракурс, чтобы убрать отвлекающие детали."
        case .changeAngle:
            return "Смените угол съемки, чтобы кадр стал более выразительным."
        case .improveFrontLight:
            return "Добавьте фронтальный свет, чтобы отделить объект от фона."
        case .levelHorizon:
            return "Выравняйте горизонт для более устойчивой композиции."
        case .leaveFrameAsIs:
            return "Оставьте кадр как есть."
        }
    }

    private func overlayHint(actionType: ActionTypeV1,
                             actionRank: Int,
                             targetRegion: NormalizedRect?) -> OverlayHint? {
        if actionType == .leaveFrameAsIs {
            return nil
        }
        let regionKey = quantizedRegionKey(targetRegion)
        let id = "ovh_\(actionRank)_\(actionType.rawValue)_\(regionKey)"
        switch actionType {
        case .moveFrameLeft:
            return OverlayHint(id: id, kind: .arrow, targetRegion: targetRegion, direction: .left)
        case .moveFrameRight:
            return OverlayHint(id: id, kind: .arrow, targetRegion: targetRegion, direction: .right)
        case .moveFrameUp:
            return OverlayHint(id: id, kind: .arrow, targetRegion: targetRegion, direction: .up)
        case .moveFrameDown:
            return OverlayHint(id: id, kind: .arrow, targetRegion: targetRegion, direction: .down)
        case .levelHorizon:
            return OverlayHint(id: id, kind: .horizonLine, targetRegion: nil, direction: nil)
        default:
            return OverlayHint(id: id, kind: .regionHighlight, targetRegion: targetRegion, direction: nil)
        }
    }

    private func quantizedRegionKey(_ region: NormalizedRect?) -> String {
        guard let region else { return "screen" }
        func q(_ value: Double) -> String {
            let rounded = (value / 0.02).rounded() * 0.02
            return String(format: "%.2f", rounded)
        }
        return "\(q(region.x))_\(q(region.y))_\(q(region.width))_\(q(region.height))"
    }

    private func requiresStillCamera(_ actionType: ActionTypeV1) -> Bool {
        switch actionType {
        case .moveFrameLeft, .moveFrameRight, .moveFrameUp, .moveFrameDown, .levelHorizon:
            return true
        default:
            return false
        }
    }

    private func suppressWhenMoving(_ actionType: ActionTypeV1) -> Bool {
        switch actionType {
        case .leaveFrameAsIs:
            return false
        default:
            return true
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
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
    let saliencyRegion: CGRect?
    let faceCount: Int
    let personCount: Int

    init(subjects: [FeatureSnapshotVisionSubject],
         saliencyCenter: CGPoint?,
         saliencyRegion: CGRect? = nil,
         faceCount: Int,
         personCount: Int) {
        self.subjects = subjects
        self.saliencyCenter = saliencyCenter
        self.saliencyRegion = saliencyRegion
        self.faceCount = faceCount
        self.personCount = personCount
    }
}

struct FeatureSnapshotHorizonPayload: Equatable {
    let angleDegrees: Double
    let confidence: Double
}

struct FeatureSnapshotLightingPayload: Equatable {
    let exposureBiasHint: Double
    let backlightIndex: Double
    let keyToFillRatio: Double?
    let subjectLighting: FrameFeatureSnapshot.LightingFeatures.SubjectLightingMetrics?

    init(exposureBiasHint: Double,
         backlightIndex: Double,
         keyToFillRatio: Double?,
         subjectLighting: FrameFeatureSnapshot.LightingFeatures.SubjectLightingMetrics? = nil) {
        self.exposureBiasHint = exposureBiasHint
        self.backlightIndex = backlightIndex
        self.keyToFillRatio = keyToFillRatio
        self.subjectLighting = subjectLighting
    }
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
        guard !subjects.isEmpty || debugData.saliencyCenter != nil || debugData.saliencyRegion != nil else {
            return nil
        }

        let faceCount = subjects.filter(\.isFace).count
        let personCount = subjects.count
        let payload = FeatureSnapshotVisionPayload(
            subjects: subjects,
            saliencyCenter: debugData.saliencyCenter,
            saliencyRegion: debugData.saliencyRegion,
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
        let primaryFaceRegion = primaryFaceRegion(from: visionPayload?.subjects ?? [])
        let sortedDetections = sortDetections(detrPayload?.detections ?? [])
        let foregroundDetections = foregroundDetections(from: sortedDetections)

        let primaryCandidate = selectPrimaryCandidate(
            visionSubjects: sortedVisionSubjects,
            saliencyRegion: visionPayload?.saliencyRegion,
            detections: foregroundDetections,
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
            faceRegion: primaryFaceRegion,
            topObjectLabel: foregroundDetections.first?.label,
            topObjectConfidence: foregroundDetections.first?.confidence,
            topObjectRegion: foregroundDetections.first.flatMap { normalizedRect(from: $0.boundingBox) },
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
            keyToFillRatio: lightingPayload?.keyToFillRatio,
            subjectLighting: lightingPayload?.subjectLighting
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
            totalCount: foregroundDetections.count,
            topKLabels: Array(foregroundDetections.prefix(3).map(\.label))
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
        let defaultCenter = CGPoint(x: 0.5, y: 0.333)
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

    private func primaryFaceRegion(from subjects: [FeatureSnapshotVisionSubject]) -> NormalizedRect? {
        let face = subjects
            .filter { $0.isFace }
            .stableSorted { lhs, rhs in
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence > rhs.confidence
                }
                let lhsArea = max(0, Double(lhs.boundingBox.width * lhs.boundingBox.height))
                let rhsArea = max(0, Double(rhs.boundingBox.width * rhs.boundingBox.height))
                if lhsArea != rhsArea {
                    return lhsArea > rhsArea
                }
                let lhsMidX = Double(lhs.boundingBox.midX)
                let rhsMidX = Double(rhs.boundingBox.midX)
                if lhsMidX != rhsMidX {
                    return lhsMidX < rhsMidX
                }
                return Double(lhs.boundingBox.midY) < Double(rhs.boundingBox.midY)
            }
            .first
        return face.flatMap { normalizedRect(from: $0.boundingBox) }
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

    private func foregroundDetections(from detections: [FeatureSnapshotDetectedObject]) -> [FeatureSnapshotDetectedObject] {
        detections
            .filter(isForegroundDetection)
            .stableSorted { lhs, rhs in
                let lhsScore = foregroundDetectionPriorityScore(lhs)
                let rhsScore = foregroundDetectionPriorityScore(rhs)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence > rhs.confidence
                }
                let lhsArea = max(0, Double(lhs.boundingBox.width * lhs.boundingBox.height))
                let rhsArea = max(0, Double(rhs.boundingBox.width * rhs.boundingBox.height))
                if lhsArea != rhsArea {
                    return lhsArea < rhsArea
                }
                return lhs.label < rhs.label
            }
    }

    private func isForegroundDetection(_ detection: FeatureSnapshotDetectedObject) -> Bool {
        let label = normalizedObjectLabel(detection.label)
        let area = max(0, Double(detection.boundingBox.width * detection.boundingBox.height))

        guard detection.confidence >= 0.12 else { return false }
        guard area >= 0.003 else { return false }

        if structuralBackgroundLabels.contains(label) {
            return false
        }

        if area >= 0.65 && !largeFrameForegroundLabels.contains(label) {
            return false
        }

        if label == "paper", area >= 0.35 {
            return false
        }

        return true
    }

    private func foregroundDetectionPriorityScore(_ detection: FeatureSnapshotDetectedObject) -> Double {
        let label = normalizedObjectLabel(detection.label)
        let area = max(0, Double(detection.boundingBox.width * detection.boundingBox.height))
        let preferredAreaPenalty = min(0.28, abs(area - 0.16))
        let demoObjectBonus = demoPriorityObjectLabels.contains(label) ? 0.55 : 0.0
        let backgroundContextPenalty = backgroundContextObjectLabels.contains(label) ? 0.45 : 0.0
        return detection.confidence + demoObjectBonus - backgroundContextPenalty - preferredAreaPenalty
    }

    private func normalizedObjectLabel(_ label: String) -> String {
        let lowercased = label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let base = lowercased.split(separator: "(", maxSplits: 1).first.map(String.init) ?? lowercased
        return base.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var structuralBackgroundLabels: Set<String> {
        [
            "banner",
            "building",
            "ceiling",
            "dirt",
            "door",
            "fence",
            "floor",
            "grass",
            "mirror",
            "mountain",
            "pavement",
            "river",
            "road",
            "sea",
            "sky",
            "snow",
            "table",
            "tree",
            "wall",
            "water",
            "window"
        ]
    }

    private var demoPriorityObjectLabels: Set<String> {
        [
            "book",
            "bottle",
            "cell phone",
            "cup",
            "keyboard",
            "laptop",
            "potted plant",
            "vase"
        ]
    }

    private var backgroundContextObjectLabels: Set<String> {
        [
            "bed",
            "cabinet",
            "chair",
            "paper",
            "screen",
            "sofa",
            "tv"
        ]
    }

    private var largeFrameForegroundLabels: Set<String> {
        [
            "backpack",
            "bicycle",
            "book",
            "bottle",
            "car",
            "cell phone",
            "cup",
            "handbag",
            "keyboard",
            "laptop",
            "motorcycle",
            "person",
            "potted plant",
            "suitcase",
            "truck",
            "tv",
            "vase"
        ]
    }

    private func selectPrimaryCandidate(visionSubjects: [FeatureSnapshotVisionSubject],
                                        saliencyRegion: CGRect?,
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

        if visionSubjects.isEmpty,
           detections.isEmpty,
           let saliencyRegion,
           isUsableSaliencyFallbackRegion(saliencyRegion),
           let region = normalizedRect(from: saliencyRegion) {
            let effective = clamp01(0.48 * visionSourceConfidence)
            candidates.append(
                Candidate(
                    source: .vision,
                    rawConfidence: 0.48,
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

    private func isUsableSaliencyFallbackRegion(_ region: CGRect) -> Bool {
        guard region.minX.isFinite,
              region.minY.isFinite,
              region.width.isFinite,
              region.height.isFinite else {
            return false
        }
        let area = Double(region.width * region.height)
        guard area >= 0.004, area <= 0.45 else { return false }
        guard region.width <= 0.78, region.height <= 0.78 else { return false }
        return true
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

// MARK: - Scene Semantics (PR-005 + PR-006)

struct SceneSemanticsAnalyzer {
    private let primarySubjectResolver = PrimarySubjectResolver()
    private let visualDominanceAnalyzer = VisualDominanceAnalyzer()
    private let sceneTypeClassifier = SceneTypeClassifier()
    private let semanticReadabilityAnalyzer = SemanticReadabilityAnalyzer()

    func analyze(snapshot: FrameFeatureSnapshot) -> SceneSemanticsReport {
        if snapshot.frameId.isEmpty {
            return makeWeakSignalFallback(
                snapshot: snapshot,
                frameId: "unknown-frame",
                note: "Weak scene evidence: frameId is empty."
            )
        }

        if hasContractVersionMismatch(snapshot) {
            return makeWeakSignalFallback(
                snapshot: snapshot,
                note: "Weak scene evidence: snapshot contract version mismatch.",
                assumptions: [
                    .init(
                        id: "contract_version_mismatch",
                        text: "Snapshot payload does not satisfy expected contract invariants.",
                        confidence: 1.0
                    )
                ]
            )
        }

        if hasNoVisionAndDetrSources(snapshot.sources) {
            return makeWeakSignalFallback(snapshot: snapshot)
        }

        let subjectResult = primarySubjectResolver.resolve(snapshot: snapshot)
        let dominance = visualDominanceAnalyzer.analyze(snapshot: snapshot, primarySubject: subjectResult.primarySubject)
        let sceneClassification = sceneTypeClassifier.classify(
            snapshot: snapshot,
            primarySubject: subjectResult.primarySubject,
            dominance: dominance
        )
        let readability = semanticReadabilityAnalyzer.analyze(
            snapshot: snapshot,
            sceneType: sceneClassification.sceneType,
            primarySubject: subjectResult.primarySubject,
            dominance: dominance
        )

        var ambiguities = subjectResult.ambiguities + sceneClassification.ambiguities
        var sceneTypeConfidence = sceneClassification.sceneTypeConfidence
        if snapshot.technicalFlags.contains(.lowSceneConfidence) {
            sceneTypeConfidence = clamp01(sceneTypeConfidence * 0.85)
            ambiguities.append(
                SemanticsAmbiguity(
                    type: .weakSignal,
                    note: "Weak scene evidence: low_scene_confidence is active.",
                    candidateIds: []
                )
            )
        }

        if sceneTypeConfidence < 0.35 {
            sceneTypeConfidence = 0
        }
        let finalSceneType: SceneTypeV1 = (sceneClassification.bestScore < 0.40 || sceneTypeConfidence < 0.35)
            ? .unknown
            : sceneClassification.sceneType
        if finalSceneType == .unknown {
            sceneTypeConfidence = 0
        }

        let primarySubject: SceneSemanticsReport.PrimarySubject
        if subjectResult.primarySubject.confidence < 0.2 {
            primarySubject = SceneSemanticsReport.PrimarySubject(
                kind: .unknown,
                label: nil,
                region: nil,
                confidence: 0,
                competingCandidates: []
            )
        } else {
            primarySubject = subjectResult.primarySubject
        }

        return SceneSemanticsReport(
            frameId: snapshot.frameId.isEmpty ? "unknown-frame" : snapshot.frameId,
            mode: snapshot.mode,
            sceneType: finalSceneType,
            sceneTypeConfidence: sceneTypeConfidence,
            primarySubject: primarySubject,
            dominance: dominance,
            readability: readability,
            ambiguities: sortAmbiguities(ambiguities),
            assumptions: sortAssumptions([])
        )
    }

    private func hasNoVisionAndDetrSources(_ sources: FeatureSourceStatus) -> Bool {
        !sources.vision.available && !sources.detr.available
    }

    private func hasContractVersionMismatch(_ snapshot: FrameFeatureSnapshot) -> Bool {
        !snapshot.validate().isEmpty
    }

    private func makeWeakSignalFallback(snapshot: FrameFeatureSnapshot,
                                        frameId: String? = nil,
                                        note: String = "Weak scene evidence: vision and DETR sources are unavailable.",
                                        assumptions: [SemanticsAssumption] = []) -> SceneSemanticsReport {
        SceneSemanticsReport(
            frameId: frameId ?? snapshot.frameId,
            mode: snapshot.mode,
            sceneType: .unknown,
            sceneTypeConfidence: 0,
            primarySubject: .init(kind: .unknown, label: nil, region: nil, confidence: 0, competingCandidates: []),
            dominance: .init(hasClearFocus: false, focusCompetitionScore: 0.75, backgroundClutterScore: 0.65),
            readability: .init(subjectReadable: false, lookSpaceAdequate: nil, edgePressureScore: 0.50, separationScore: 0.20),
            ambiguities: [
                .init(type: .weakSignal, note: note, candidateIds: [])
            ],
            assumptions: sortAssumptions(assumptions)
        )
    }

    private func sortAmbiguities(_ ambiguities: [SemanticsAmbiguity]) -> [SemanticsAmbiguity] {
        ambiguities.stableSorted {
            if $0.type.rawValue != $1.type.rawValue {
                return $0.type.rawValue < $1.type.rawValue
            }
            return $0.note < $1.note
        }
    }

    private func sortAssumptions(_ assumptions: [SemanticsAssumption]) -> [SemanticsAssumption] {
        assumptions.stableSorted { lhs, rhs in
            lhs.id < rhs.id
        }
    }

    private func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}

struct PrimarySubjectResolver {
    private struct Candidate {
        let id: String
        let kind: SubjectKind
        let label: String?
        let region: NormalizedRect?
        let baseConfidence: Double
        let sourceReliability: Double
        let score: Double
    }

    struct Result {
        let primarySubject: SceneSemanticsReport.PrimarySubject
        let ambiguities: [SemanticsAmbiguity]
    }

    func resolve(snapshot: FrameFeatureSnapshot) -> Result {
        let hadMalformedPrimaryRegion = snapshot.subjectSignals.primaryCandidateRegion.map { !isValidRegion($0) } ?? false
        let coreCandidates = buildCoreCandidates(snapshot: snapshot)
        let eligible = coreCandidates.filter { $0.score >= 0.20 }
        guard let winner = selectWinner(eligible) else {
            var ambiguities: [SemanticsAmbiguity] = [
                .init(type: .weakSignal, note: "Weak subject evidence: no candidate reached minimum score.", candidateIds: [])
            ]
            if hadMalformedPrimaryRegion {
                ambiguities.append(
                    .init(
                        type: .weakSignal,
                        note: "Weak subject evidence: primary candidate region is malformed.",
                        candidateIds: ["snapshot-primary"]
                    )
                )
            }
            return Result(
                primarySubject: .init(kind: .unknown, confidence: 0, competingCandidates: []),
                ambiguities: ambiguities
            )
        }

        let competitors = eligible
            .filter { $0.id != winner.id }
            .stableSorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.id < rhs.id
            }
        var ambiguities: [SemanticsAmbiguity] = []
        if let second = competitors.first, abs(winner.score - second.score) < 0.07 {
            ambiguities.append(
                .init(
                    type: .multipleSubjectsSimilarConfidence,
                    note: "Top subject candidates have similar confidence.",
                    candidateIds: [winner.id, second.id]
                )
            )
        }
        if hadMalformedPrimaryRegion {
            ambiguities.append(
                .init(
                    type: .weakSignal,
                    note: "Weak subject evidence: primary candidate region is malformed.",
                    candidateIds: ["snapshot-primary"]
                )
            )
        }

        let competingCandidates = Array(competitors.prefix(2)).map {
            SubjectCandidate(id: $0.id, kind: $0.kind, label: $0.label, region: $0.region, confidence: $0.score)
        }
        let primary = SceneSemanticsReport.PrimarySubject(
            kind: winner.kind,
            label: winner.kind == .object ? winner.label : nil,
            region: winner.region,
            confidence: winner.score,
            competingCandidates: competingCandidates
        )
        return Result(primarySubject: primary, ambiguities: ambiguities)
    }

    private func buildCoreCandidates(snapshot: FrameFeatureSnapshot) -> [Candidate] {
        var candidates: [Candidate] = []

        if let region = snapshot.subjectSignals.faceRegion, isValidRegion(region) {
            let base = clamp01(max(
                snapshot.subjectSignals.primaryCandidateConfidence ?? 0,
                snapshot.sources.vision.confidence ?? 0,
                0.70
            ))
            let reliability = max(snapshot.sources.vision.confidence ?? 0.70, 0.82)
            candidates.append(
                makeCandidate(
                    id: "snapshot-face",
                    kind: .face,
                    label: nil,
                    region: region,
                    baseConfidence: base,
                    sourceReliability: reliability
                )
            )
        }

        if let region = snapshot.subjectSignals.primaryCandidateRegion, isValidRegion(region) {
            let kind: SubjectKind
            if snapshot.subjectSignals.faceDetected,
               let faceRegion = snapshot.subjectSignals.faceRegion,
               regionLikelyMatches(region, faceRegion) {
                kind = .face
            } else if snapshot.subjectSignals.personDetected {
                kind = .person
            } else {
                kind = .unknown
            }
            let base = clamp01(snapshot.subjectSignals.primaryCandidateConfidence ?? 0)
            let reliability = max(base, 0.25)
            candidates.append(
                makeCandidate(
                    id: "snapshot-primary",
                    kind: kind,
                    label: nil,
                    region: region,
                    baseConfidence: base,
                    sourceReliability: reliability
                )
            )
        }

        if let objectLabel = snapshot.subjectSignals.topObjectLabel {
            let base = clamp01(snapshot.subjectSignals.topObjectConfidence ?? 0)
            let region = snapshot.subjectSignals.topObjectRegion
            let normalizedLabel = normalizeObjectLabel(objectLabel)
            let hasPersonSignal = snapshot.subjectSignals.faceDetected || snapshot.subjectSignals.personDetected
            let reliabilityMultiplier: Double
            if hasPersonSignal && backgroundContextLabels.contains(normalizedLabel) {
                reliabilityMultiplier = 0.20
            } else if demoPriorityObjectLabels.contains(normalizedLabel) {
                reliabilityMultiplier = 1.08
            } else if backgroundContextLabels.contains(normalizedLabel) {
                reliabilityMultiplier = 0.55
            } else {
                reliabilityMultiplier = 0.92
            }
            let reliability = clamp01((snapshot.sources.detr.confidence ?? 0.50) * reliabilityMultiplier)
            candidates.append(
                makeCandidate(
                    id: "snapshot-object",
                    kind: .object,
                    label: objectLabel,
                    region: region,
                    baseConfidence: base,
                    sourceReliability: reliability
                )
            )
        }

        let hasValidPrimaryRegion = snapshot.subjectSignals.primaryCandidateRegion.map(isValidRegion) ?? false
        if snapshot.subjectSignals.personCount >= 2 && !hasValidPrimaryRegion {
            let base = clamp01(0.35 + (0.15 * Double(min(3, snapshot.subjectSignals.personCount - 1))))
            let reliability = snapshot.sources.vision.confidence ?? 0.55
            candidates.append(
                makeCandidate(
                    id: "snapshot-group",
                    kind: .group,
                    label: nil,
                    region: nil,
                    baseConfidence: base,
                    sourceReliability: reliability
                )
            )
        }

        return candidates
    }

    private func isValidRegion(_ region: NormalizedRect) -> Bool {
        region.x.isFinite &&
        region.y.isFinite &&
        region.width.isFinite &&
        region.height.isFinite &&
        !region.isDegenerate
    }

    private func regionLikelyMatches(_ lhs: NormalizedRect, _ rhs: NormalizedRect) -> Bool {
        let left = max(lhs.x, rhs.x)
        let top = max(lhs.y, rhs.y)
        let right = min(lhs.x + lhs.width, rhs.x + rhs.width)
        let bottom = min(lhs.y + lhs.height, rhs.y + rhs.height)
        let intersectionWidth = max(0, right - left)
        let intersectionHeight = max(0, bottom - top)
        let intersectionArea = intersectionWidth * intersectionHeight
        let lhsArea = max(0.001, lhs.width * lhs.height)
        let rhsArea = max(0.001, rhs.width * rhs.height)
        let unionArea = lhsArea + rhsArea - intersectionArea
        let iou = unionArea > 0 ? intersectionArea / unionArea : 0
        if iou >= 0.18 { return true }

        let lhsCenterX = lhs.x + lhs.width * 0.5
        let lhsCenterY = lhs.y + lhs.height * 0.5
        let rhsCenterX = rhs.x + rhs.width * 0.5
        let rhsCenterY = rhs.y + rhs.height * 0.5
        let dx = lhsCenterX - rhsCenterX
        let dy = lhsCenterY - rhsCenterY
        return sqrt(dx * dx + dy * dy) <= 0.10
    }

    private func makeCandidate(id: String,
                               kind: SubjectKind,
                               label: String?,
                               region: NormalizedRect?,
                               baseConfidence: Double,
                               sourceReliability: Double) -> Candidate {
        let area = region.map { $0.width * $0.height } ?? 0
        let regionWeight: Double
        if region == nil {
            regionWeight = 0.85
        } else if area < 0.02 {
            regionWeight = 0.75
        } else {
            regionWeight = 1.0
        }

        let kindWeight: Double
        switch kind {
        case .face:
            kindWeight = 1.0
        case .person:
            kindWeight = 0.92
        case .group:
            kindWeight = 0.90
        case .object:
            kindWeight = 0.88
        case .unknown:
            kindWeight = 0.70
        }

        let score = clamp01(baseConfidence * clamp01(sourceReliability) * kindWeight * regionWeight)
        return Candidate(
            id: id,
            kind: kind,
            label: label,
            region: region,
            baseConfidence: baseConfidence,
            sourceReliability: sourceReliability,
            score: score
        )
    }

    private var demoPriorityObjectLabels: Set<String> {
        [
            "book",
            "bottle",
            "cell phone",
            "cup",
            "keyboard",
            "laptop",
            "potted plant",
            "vase"
        ]
    }

    private var backgroundContextLabels: Set<String> {
        [
            "bed",
            "cabinet",
            "chair",
            "paper",
            "screen",
            "table",
            "tv"
        ]
    }

    private func normalizeObjectLabel(_ label: String) -> String {
        let lowercased = label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let base = lowercased.split(separator: "(", maxSplits: 1).first.map(String.init) ?? lowercased
        return base.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func selectWinner(_ candidates: [Candidate]) -> Candidate? {
        candidates.max { lhs, rhs in
            let delta = lhs.score - rhs.score
            if abs(delta) >= 0.03 {
                return delta < 0
            }

            let lhsPriority = kindPriority(lhs.kind)
            let rhsPriority = kindPriority(rhs.kind)
            if lhsPriority != rhsPriority {
                return lhsPriority > rhsPriority
            }

            let lhsArea = lhs.region.map { $0.width * $0.height } ?? 0
            let rhsArea = rhs.region.map { $0.width * $0.height } ?? 0
            if lhsArea != rhsArea {
                return lhsArea < rhsArea
            }

            return lhs.id > rhs.id
        }
    }

    private func kindPriority(_ kind: SubjectKind) -> Int {
        switch kind {
        case .face:
            return 0
        case .person:
            return 1
        case .group:
            return 2
        case .object:
            return 3
        case .unknown:
            return 4
        }
    }

    private func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}

struct VisualDominanceAnalyzer {
    func analyze(snapshot: FrameFeatureSnapshot,
                 primarySubject: SceneSemanticsReport.PrimarySubject) -> SceneSemanticsReport.VisualDominanceState {
        let objectDensity = clamp01(Double(snapshot.objects.totalCount) / 6.0)
        let saliencyConflict = abs(snapshot.composition.horizontalOffset - snapshot.composition.saliencyLeftRightBalance)
        let saliencySpread = abs(snapshot.composition.saliencyLeftRightBalance) * 0.5 + abs(snapshot.composition.saliencyTopBottomBalance) * 0.5

        let focusCompetitionScore = clamp01((0.50 * (1 - primarySubject.confidence)) + (0.30 * objectDensity) + (0.20 * saliencyConflict))
        let backgroundClutterScore = clamp01((0.65 * objectDensity) + (0.35 * saliencySpread))
        let hasClearFocus =
            primarySubject.confidence >= 0.55 &&
            focusCompetitionScore <= 0.45 &&
            backgroundClutterScore <= 0.55

        return .init(
            hasClearFocus: hasClearFocus,
            focusCompetitionScore: focusCompetitionScore,
            backgroundClutterScore: backgroundClutterScore
        )
    }

    private func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}

struct SceneTypeClassifier {
    struct Result {
        let sceneType: SceneTypeV1
        let sceneTypeConfidence: Double
        let bestScore: Double
        let ambiguities: [SemanticsAmbiguity]
    }

    func classify(snapshot: FrameFeatureSnapshot,
                  primarySubject: SceneSemanticsReport.PrimarySubject,
                  dominance: SceneSemanticsReport.VisualDominanceState) -> Result {
        let subjectPresence = primarySubject.kind == .unknown ? 0.0 : primarySubject.confidence
        let areaScore = clamp01((snapshot.composition.subjectAreaRatio - 0.08) / 0.22)
        let lowClutterScore = clamp01(1 - (Double(snapshot.objects.totalCount) / 5.0))
        let personSignal = snapshot.subjectSignals.personDetected ? 1.0 : 0.0
        let mediumAreaScore = max(0.0, 1.0 - (abs(snapshot.composition.subjectAreaRatio - 0.18) / 0.10))
        let focusScore = dominance.hasClearFocus ? 1.0 : clamp01(1 - dominance.focusCompetitionScore)
        let multiPersonScore = clamp01(Double(snapshot.subjectSignals.personCount) / 2.0)
        let balanceScore = clamp01(1.0 - abs(snapshot.composition.horizontalOffset))
        let objectConfidenceScore = clamp01(snapshot.subjectSignals.topObjectConfidence ?? 0.0)
        let isolationScore = clamp01(1.0 - Double(snapshot.subjectSignals.personCount > 0 ? 1 : 0) - Double(snapshot.objects.totalCount > 4 ? 0.3 : 0.0))
        let lowPersonScore = snapshot.subjectSignals.personDetected ? 0.0 : 1.0
        let wideCompositionScore = clamp01(1.0 - (snapshot.composition.subjectAreaRatio / 0.10))
        let multiObjectScore = clamp01(Double(snapshot.objects.totalCount) / 6.0)
        let lowPrimaryDominance = clamp01(1.0 - primarySubject.confidence)
        let backlightScore = clamp01((snapshot.lighting.backlightIndex - 0.45) / 0.35)
        let separationProxy = clamp01((0.50 * subjectPresence) + (0.30 * (1 - dominance.backgroundClutterScore)) + (0.20 * (1 - snapshot.lighting.backlightIndex)))
        let readabilityPenaltyInversion = clamp01(1.0 - separationProxy)

        let dialogueGate = (primarySubject.kind == .face || primarySubject.kind == .person) &&
            snapshot.composition.subjectAreaRatio >= 0.22 &&
            snapshot.objects.totalCount <= 3
        let singleMediumGate = snapshot.subjectSignals.personDetected &&
            snapshot.composition.subjectAreaRatio >= 0.08 &&
            snapshot.composition.subjectAreaRatio <= 0.28
        let twoCharacterGate = snapshot.subjectSignals.personCount >= 2
        let objectInsertGate = primarySubject.kind == .object &&
            (snapshot.subjectSignals.topObjectConfidence ?? 0) >= 0.45 &&
            !snapshot.subjectSignals.personDetected
        let establishingGate = snapshot.composition.subjectAreaRatio <= 0.08 &&
            (snapshot.objects.totalCount >= 3 || !snapshot.subjectSignals.personDetected)
        let moodyGate = snapshot.subjectSignals.personDetected &&
            snapshot.lighting.backlightIndex >= 0.62 &&
            snapshot.lighting.exposureBiasHint <= 0.05

        let scores: [(SceneTypeV1, Double)] = [
            (.dialogueCloseup, dialogueGate ? clamp01((0.45 * subjectPresence) + (0.35 * areaScore) + (0.20 * lowClutterScore)) : 0),
            (.singleCharacterMedium, singleMediumGate ? clamp01((0.50 * personSignal) + (0.30 * mediumAreaScore) + (0.20 * focusScore)) : 0),
            (.twoCharacterFrame, twoCharacterGate ? clamp01((0.60 * multiPersonScore) + (0.20 * balanceScore) + (0.20 * focusScore)) : 0),
            (.objectInsert, objectInsertGate ? clamp01((0.60 * objectConfidenceScore) + (0.25 * isolationScore) + (0.15 * lowPersonScore)) : 0),
            (.establishingLikeFrame, establishingGate ? clamp01((0.45 * wideCompositionScore) + (0.35 * multiObjectScore) + (0.20 * lowPrimaryDominance)) : 0),
            (.moodyBacklitSubject, moodyGate ? clamp01((0.45 * backlightScore) + (0.35 * subjectPresence) + (0.20 * readabilityPenaltyInversion)) : 0)
        ]

        let sorted = scores.stableSorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.rawValue < rhs.0.rawValue
        }
        guard let best = sorted.first else {
            return Result(sceneType: .unknown, sceneTypeConfidence: 0, bestScore: 0, ambiguities: [])
        }

        let bestScore = best.1
        let runnerUpScore = sorted.dropFirst().first?.1 ?? 0
        let margin = bestScore - runnerUpScore
        let sourceHealth = clamp01((0.5 * (snapshot.sources.vision.confidence ?? 0)) + (0.5 * (snapshot.sources.detr.confidence ?? 0)))
        let confidence = clamp01(bestScore * (0.65 + (0.35 * sourceHealth)) * (margin >= 0.10 ? 1.0 : 0.85))

        var ambiguities: [SemanticsAmbiguity] = []
        if margin < 0.08 && bestScore >= 0.45 && runnerUpScore >= 0.45 {
            ambiguities.append(
                .init(
                    type: .sceneTypeTie,
                    note: "Top scene type rules are too close to separate confidently.",
                    candidateIds: [best.0.rawValue, sorted.dropFirst().first?.0.rawValue ?? "unknown"]
                )
            )
        }

        return Result(
            sceneType: best.0,
            sceneTypeConfidence: confidence,
            bestScore: bestScore,
            ambiguities: ambiguities
        )
    }

    private func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}

struct SemanticReadabilityAnalyzer {
    func analyze(snapshot: FrameFeatureSnapshot,
                 sceneType: SceneTypeV1,
                 primarySubject: SceneSemanticsReport.PrimarySubject,
                 dominance: SceneSemanticsReport.VisualDominanceState) -> SceneSemanticsReport.SemanticReadabilityState {
        let edgePressureScore: Double
        if let region = primarySubject.region {
            let minEdgeDistance = min(
                region.x,
                region.y,
                1 - (region.x + region.width),
                1 - (region.y + region.height)
            )
            edgePressureScore = clamp01(1 - (minEdgeDistance / 0.10))
        } else {
            edgePressureScore = 0.50
        }

        let separationScore = clamp01(
            (0.45 * primarySubject.confidence) +
            (0.35 * (1 - dominance.backgroundClutterScore)) +
            (0.20 * (1 - snapshot.lighting.backlightIndex))
        )

        let lookSpaceAdequate: Bool?
        if sceneType == .objectInsert || sceneType == .establishingLikeFrame {
            lookSpaceAdequate = nil
        } else if edgePressureScore >= 0.75 && abs(snapshot.composition.horizontalOffset) >= 0.65 {
            lookSpaceAdequate = false
        } else {
            lookSpaceAdequate = true
        }

        let baseSubjectReadable =
            primarySubject.kind != .unknown &&
            separationScore >= 0.45 &&
            edgePressureScore <= 0.80
        let subjectReadable: Bool
        if snapshot.technicalFlags.contains(.highMotion) {
            // In high motion, avoid aggressive false negatives: only fail when separation is clearly low.
            subjectReadable = primarySubject.kind != .unknown && separationScore >= 0.40
        } else {
            subjectReadable = baseSubjectReadable
        }

        return .init(
            subjectReadable: subjectReadable,
            lookSpaceAdequate: lookSpaceAdequate,
            edgePressureScore: edgePressureScore,
            separationScore: separationScore
        )
    }

    private func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
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
    @Published private(set) var currentLiveHint: LiveHintPresentation?
    @Published private(set) var currentPauseCritique: PauseCritiquePresentation?
    @Published private(set) var currentOverlayAnnotations: [OverlayAnnotationPresentation] = []

    private let visionTracking = VisionTracking()
    private let horizonEstimator = HorizonEstimator()
    private let lightingEstimator = LightingEstimator()
    private let detrDetector = try? DETRDetector()
    private let aestheticScorer = AestheticScorer()
    private let suggestionEngine = SuggestionEngine()
    private let featureSnapshotAggregator = FeatureSnapshotAggregator()
    private let featureSnapshotAdapter = PipelineFeatureSnapshotAdapter()
    private let sceneSemanticsAnalyzer = SceneSemanticsAnalyzer()
    private let frameCritiqueEngine = FrameCritiqueEngine()
    private let hybridFusionService = HybridFusionService()
    private let recommendationPlanner = RecommendationPlanner()
    private let semanticTipPlanner = SemanticTipPlanner()
    private let technicalQualityAnalyzer = TechnicalQualityAnalyzer()
    private let pauseReasoningCoordinator: PauseReasoningCoordinator
    private let visualSemanticEvidenceCoordinator: VisualSemanticEvidenceCoordinator
    private let neuralEvidenceService: NeuralEvidenceInferenceService?
    private let thermalGovernor: ThermalGovernor
    private let neuralHeavyModelsEnabledProvider: () -> Bool
    private let liveHybridFusionEnabled: Bool
    private let demoLiveCoachEnabled: Bool

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
    private var lastFrameWasStable = false
    private var lastPixelBuffer: CVPixelBuffer?
    private var lastOrientation: CGImagePropertyOrientation = .right
    private var lastSourceFrameId: String = ""
    private var latestLiveNeuralOutcome: NeuralEvidenceRecordedOutcome?
    private var latestPauseNeuralOutcome: NeuralEvidenceRecordedOutcome?
    private var lastRequestedLiveNeuralFrameId: String?
    private var lastRequestedPauseNeuralFrameId: String?
    private var suggestionExpiry: Date = .distantPast
    private var lastAestheticRequest: Date = .distantPast
    private var lastDETRRequest: Date = .distantPast
    private var lowFrameCount: Int = 0
    private var liveHintShownAt: Date = .distantPast
    private var liveHintExpiresAt: Date = .distantPast
    private var lastLiveMotionBecameUnstableAt: Date?
    private var lastOverlayPublishAt: Date = .distantPast
    private var pauseAnalysisRevision: Int = 0
    private var pauseReasoningTask: Task<Void, Never>?
    private var liveNeuralInferenceTask: Task<Void, Never>?
    private var pauseNeuralInferenceTask: Task<Void, Never>?
    private var lastRefinedPauseFrameId: String?
    private var currentPauseTraceBundle: ExplainabilityTraceBundle?
    private var currentLiveFusionTraceBundle: ExplainabilityTraceBundle?
    private var liveHintDecisionLogCounter = 0
    private var lastLiveHintDecisionLogKey: String?
    private var lastLiveDecisionDebugLogKey: String?
    private var lastHighCameraDebugTimestamp: TimeInterval = 0
    private var lastLiveDecisionDebugLogTimestamp: TimeInterval = 0
    private var lastDemoLightDebugLogTimestamp: TimeInterval = 0
    private var lastDetrUnavailableDebugDate: Date = .distantPast
    private var cameraDemoSceneMode: CameraDemoSceneMode = .auto
    private var demoSubjectTrack: DemoSubjectTrack?
    private var demoCinematicPortraitStep: DemoCinematicPortraitStep = .darkenBackground
    private var demoCinematicPortraitStepEvidence: DemoCinematicPortraitStepEvidence = .empty
    private var currentDemoOverlayAnnotations: [OverlayAnnotationPresentation] = []

    private var suggestionCancellable: AnyCancellable?
    private let minLiveHintHold: TimeInterval = 2.0
    private let liveHintDisplayDuration: TimeInterval = 4.0
    private let liveHintMotionHideGrace: TimeInterval = 0.8
    private let liveHintConfidenceDelta: Double = 0.28
    private let liveHintTextOnlyConfidenceDelta: Double = 0.06
    private let maxOverlayHz: Double = 8.0
    private let objectDemoDetrInterval: TimeInterval = 1.2

    init(reasoningProvider: ReasoningProvider? = ReasoningProviderFactory.makeDefaultProvider(),
         visualEvidenceProvider: VisualSemanticEvidenceProvider? = VisualSemanticEvidenceProviderFactory.makeDefaultProvider(),
         neuralEvidenceService: NeuralEvidenceInferenceService? = NeuralEvidenceInferenceService.makeDefault(),
         thermalGovernor: ThermalGovernor = ThermalGovernor(),
         neuralHeavyModelsEnabledProvider: @escaping () -> Bool = { true },
         liveHybridFusionEnabled: Bool = true,
         demoLiveCoachEnabled: Bool = false) {
        self.pauseReasoningCoordinator = PauseReasoningCoordinator(provider: reasoningProvider)
        self.visualSemanticEvidenceCoordinator = VisualSemanticEvidenceCoordinator(provider: visualEvidenceProvider)
        self.neuralEvidenceService = neuralEvidenceService
        self.thermalGovernor = thermalGovernor
        self.neuralHeavyModelsEnabledProvider = neuralHeavyModelsEnabledProvider
        self.liveHybridFusionEnabled = liveHybridFusionEnabled
        self.demoLiveCoachEnabled = demoLiveCoachEnabled
    }

    @MainActor
    func setCameraDemoSceneMode(_ mode: CameraDemoSceneMode) {
        guard cameraDemoSceneMode != mode else { return }
        cameraDemoSceneMode = mode
        demoSubjectTrack = nil
        demoCinematicPortraitStep = .darkenBackground
        demoCinematicPortraitStepEvidence = .empty
        currentDemoOverlayAnnotations = []
        print("[CA_DEBUG][DEMO_MODE] mode=\(mode.rawValue)")
    }
    
    var currentFeatures: CoachingFeatures {
        featureQueue.sync { features }
    }
    
    var currentDebugData: DebugData {
        featureQueue.sync { debugData }
    }

    private func currentAdapterState() -> PipelineFeatureSnapshotAdapterState {
        featureQueue.sync {
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
    }

    func makeFeatureSnapshot(mode: AnalysisMode = .live,
                             frameId: String = UUID().uuidString,
                             capturedAt: Date = Date()) -> FrameFeatureSnapshot {
        let adapterState = currentAdapterState()
        return makeFeatureSnapshot(
            mode: mode,
            frameId: frameId,
            capturedAt: capturedAt,
            adapterState: adapterState
        )
    }

    private func makeFeatureSnapshot(mode: AnalysisMode,
                                     frameId: String,
                                     capturedAt: Date,
                                     adapterState: PipelineFeatureSnapshotAdapterState) -> FrameFeatureSnapshot {
        let input = featureSnapshotAdapter.makeInput(
            frameId: frameId,
            mode: mode,
            capturedAt: capturedAt,
            state: adapterState
        )
        return featureSnapshotAggregator.makeSnapshot(from: input)
    }

    private func makeDetrFeatureSample(from detections: [DETRDetection],
                                       measuredAt: Date) -> FeatureSample<FeatureSnapshotDetrPayload> {
        let sortedDetections = sortedDetectionsForPriority(detections)
        let payload = FeatureSnapshotDetrPayload(
            detections: sortedDetections.map {
                FeatureSnapshotDetectedObject(
                    boundingBox: $0.boundingBox,
                    label: $0.label,
                    confidence: Double($0.confidence)
                )
            }
        )
        return FeatureSample(
            value: payload,
            measuredAt: measuredAt,
            baseConfidence: sortedDetections.first.map { Double($0.confidence) } ?? 0
        )
    }

    private func makeAestheticFeatureSample(score10: Double,
                                            measuredAt: Date) -> FeatureSample<FeatureSnapshotAestheticPayload> {
        FeatureSample(
            value: FeatureSnapshotAestheticPayload(score10: score10),
            measuredAt: measuredAt,
            baseConfidence: nil
        )
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

    func ingestHigh(context: FrameContext) {
        handleHigh(context: context)
    }

    func ingestMedium(context: FrameContext) {
        handleMedium(context: context)
    }

    func ingestLow(context: FrameContext) {
        handleLow(context: context)
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
        let sourceFrameId = makeSourceFrameId(from: context.timestamp)
        featureQueue.sync {
            self.lastSourceFrameId = sourceFrameId
        }
        let startTime = CACurrentMediaTime()
        
        Telemetry.shared.setActiveModule("Vision", active: true)
        let trackingResult = visionTracking.process(pixelBuffer: context.pixelBuffer,
                                                    orientation: context.orientation)
        let visionLatency = CACurrentMediaTime() - startTime
        Telemetry.shared.recordLatency(label: "Vision", duration: visionLatency)
        Telemetry.shared.setActiveModule("Vision", active: false)

        let primarySubject = primaryVisionSubject(from: trackingResult)
        
        let horizonStart = CACurrentMediaTime()
        Telemetry.shared.setActiveModule("Horizon", active: true)
        let horizon = horizonEstimator.estimate(pixelBuffer: context.pixelBuffer,
                                               orientation: context.orientation,
                                               isStable: context.isStable)
        let horizonLatency = CACurrentMediaTime() - horizonStart
        Telemetry.shared.recordLatency(label: "Horizon", duration: horizonLatency)
        Telemetry.shared.setActiveModule("Horizon", active: false)

        let saliencyBalance = computeSaliencyBalance(from: primarySubject?.boundingBox ?? .zero,
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
            self.lastFrameWasStable = context.isStable
            if let subject = primarySubject {
                features.composition = self.compositionFeatures(from: subject.boundingBox)
                features.composition.saliencyLeftRightBalance = saliencyBalance
                features.composition.subjectAreaRatio = subject.boundingBox.width * subject.boundingBox.height
                features.lensRecommendation = self.lensRecommendation(for: subject.boundingBox)
                features.subject.objectName = nil
                features.subject.isFace = subject.isFace
                features.subject.isPerson = true
                features.subject.count = max(trackingResult.faceCount, trackingResult.personCount)
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
            self.debugData.saliencyRegion = trackingResult.saliencyRegion
            self.latestVisionSample = FeatureSample(
                value: FeatureSnapshotVisionPayload(
                    subjects: visionSubjectsPayload,
                    saliencyCenter: trackingResult.saliencyCenter,
                    saliencyRegion: trackingResult.saliencyRegion,
                    faceCount: trackingResult.faceCount,
                    personCount: trackingResult.personCount
                ),
                measuredAt: measurementTime,
                baseConfidence: visionBaseConfidence ?? (trackingResult.saliencyRegion == nil ? nil : 0.48)
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
        logHighFrameDebug(
            context: context,
            sourceFrameId: sourceFrameId,
            trackingResult: trackingResult,
            primarySubject: primarySubject,
            horizon: horizon,
            saliencyBalance: saliencyBalance,
            visionLatency: visionLatency,
            horizonLatency: horizonLatency
        )

        Task { @MainActor in
            self.overlayState = OverlayState(primaryBoundingBox: primarySubject?.boundingBox,
                                             horizonAngle: horizon.angle,
                                             horizonConfidence: horizon.confidence,
                                             saliencyBalance: saliencyBalance)
            await self.emitSuggestion()
        }

        Telemetry.shared.recordFrameProcessed()
    }

    private func primaryVisionSubject(from trackingResult: VisionTrackingResult) -> TrackedSubject? {
        let faces = trackingResult.subjects
            .filter { $0.isFace && $0.confidence >= 0.62 }
            .sorted { $0.confidence > $1.confidence }

        if faces.count >= 2 {
            let groupedFaces = Array(faces.prefix(4))
            let groupedBox = unionBoundingBox(groupedFaces.map(\.boundingBox))
            let confidence = groupedFaces.map(\.confidence).max() ?? faces[0].confidence
            return TrackedSubject(
                boundingBox: groupedBox,
                confidence: confidence,
                isFace: true
            )
        }

        return trackingResult.subjects.sorted { lhs, rhs in
            if lhs.isFace != rhs.isFace {
                return lhs.isFace && !rhs.isFace
            }
            return lhs.confidence > rhs.confidence
        }.first
    }

    private func unionBoundingBox(_ boxes: [CGRect]) -> CGRect {
        guard let first = boxes.first else { return .zero }
        let union = boxes.dropFirst().reduce(first) { partialResult, box in
            partialResult.union(box)
        }
        let minX = CGFloat(clamp01(Double(union.minX)))
        let minY = CGFloat(clamp01(Double(union.minY)))
        let maxX = CGFloat(clamp01(Double(union.maxX)))
        let maxY = CGFloat(clamp01(Double(union.maxY)))
        return CGRect(
            x: minX,
            y: minY,
            width: max(0, maxX - minX),
            height: max(0, maxY - minY)
        )
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
            let subjectLighting = FrameFeatureSnapshot.LightingFeatures.SubjectLightingMetrics(
                subjectMeanLuma: Double(lighting.subjectMeanLuma),
                backgroundMeanLuma: Double(lighting.backgroundMeanLuma),
                subjectToBackgroundDelta: Double(lighting.subjectToBackgroundDelta),
                subjectClippedBrightRatio: Double(lighting.subjectClippedBrightRatio),
                backgroundHotspotRatio: Double(lighting.backgroundHotspotRatio)
            )
            self.latestLightingSample = FeatureSample(
                value: FeatureSnapshotLightingPayload(
                    exposureBiasHint: Double(lighting.exposureBiasHint),
                    backlightIndex: Double(lighting.backlightIndex),
                    keyToFillRatio: Double(lighting.keyFillRatio),
                    subjectLighting: subjectLighting
                ),
                measuredAt: measurementTime,
                baseConfidence: nil
            )
            self.latestLightingMeasuredAt = measurementTime
        }
        let debugNow = CACurrentMediaTime()
        if debugNow - lastDemoLightDebugLogTimestamp >= 1.0 {
            lastDemoLightDebugLogTimestamp = debugNow
            print(
                "[CA_DEBUG][DEMO_LIGHT] bbox=\(debugRect(bbox)) subjectLuma=\(debugDouble(Double(lighting.subjectMeanLuma))) " +
                "backgroundLuma=\(debugDouble(Double(lighting.backgroundMeanLuma))) delta=\(debugDouble(Double(lighting.subjectToBackgroundDelta))) " +
                "subjectClip=\(debugDouble(Double(lighting.subjectClippedBrightRatio))) bgHotspot=\(debugDouble(Double(lighting.backgroundHotspotRatio)))"
            )
        }

        Task { @MainActor in
            await self.emitSuggestion()
        }
    }

    private func performLow(context: FrameContext) {
        lowFrameCount += 1
        let now = Date()
        let budget = thermalGovernor.nextBudget()
        let objectDemoDetrOverride = cameraDemoSceneMode == .object && thermalGovernor.currentTier() != .critical
        let thermalAllowsLowPriority = budget.heavyModelsEnabled && budget.lowPriorityFrequency > 0
        Telemetry.shared.setHeavyModelsEnabled(budget.heavyModelsEnabled || objectDemoDetrOverride)
        guard thermalAllowsLowPriority || objectDemoDetrOverride else { return }
        let lowBudgetInterval = thermalAllowsLowPriority ? 1.0 / budget.lowPriorityFrequency : objectDemoDetrInterval
        let detrInterval = objectDemoDetrOverride ? objectDemoDetrInterval : max(0.5, lowBudgetInterval)

        // DETR follows the low-priority thermal budget.
        let timeSinceLastDETR = now.timeIntervalSince(lastDETRRequest)
        let hasDetector = detrDetector != nil

        if !hasDetector, now.timeIntervalSince(lastDetrUnavailableDebugDate) > 2.0 {
            lastDetrUnavailableDebugDate = now
            print(
                "[CA_DEBUG][DETR_SKIP] reason=no_detector lowFrame=\(lowFrameCount) " +
                "sinceLast=\(debugDouble(timeSinceLastDETR)) image=\(debugPixelBufferSize(context.pixelBuffer)) " +
                "orientation=\(debugCGOrientationDescription(context.orientation))"
            )
        }

        if CameraLog.detr, lowFrameCount % 30 == 0 {
            os_log("🔥 DETR: time=%.1fs (need>%.1f) detector=%d",
                   log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
                   type: .debug,
                   timeSinceLastDETR, lowBudgetInterval, hasDetector ? 1 : 0)
        }

        if objectDemoDetrOverride, now.timeIntervalSince(lastDetrUnavailableDebugDate) > 2.0 {
            lastDetrUnavailableDebugDate = now
            print(
                "[CA_DEBUG][DETR_OVERRIDE] mode=object interval=\(debugDouble(detrInterval)) " +
                "thermalHeavy=\(budget.heavyModelsEnabled) lowFreq=\(debugDouble(budget.lowPriorityFrequency)) " +
                "sinceLast=\(debugDouble(timeSinceLastDETR)) detector=\(hasDetector)"
            )
        }

        if timeSinceLastDETR > detrInterval,
           let detector = detrDetector {

            if CameraLog.detr {
                os_log("🚀 DETR: Starting detection...",
                       log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
                       type: .debug)
            }

            lastDETRRequest = now
            let detrStart = CACurrentMediaTime()
            Telemetry.shared.setActiveModule("DETR", active: true)
            print(
                "[CA_DEBUG][DETR_REQUEST] lowFrame=\(lowFrameCount) sinceLast=\(debugDouble(timeSinceLastDETR)) " +
                "image=\(debugPixelBufferSize(context.pixelBuffer)) orientation=\(debugCGOrientationDescription(context.orientation))"
            )

            detector.detect(pixelBuffer: context.pixelBuffer,
                             orientation: context.orientation) { [weak self] detections in
                let detrLatency = CACurrentMediaTime() - detrStart
                Telemetry.shared.recordLatency(label: "DETR", duration: detrLatency)
                Telemetry.shared.setActiveModule("DETR", active: false)

                if CameraLog.detr {
                    os_log("✅ DETR callback: %d detections received in %.0fms",
                           log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
                           type: .debug, detections.count, detrLatency * 1000)
                }

                guard let self else { return }

                let priorityDetections = self.compositionPriorityDetections(detections)
                print(
                    "[CA_DEBUG][DETR_RESULT] count=\(detections.count) priority=\(priorityDetections.count) " +
                    "latencyMs=\(self.debugDouble(detrLatency * 1000)) detections=\(self.debugDetections(detections)) " +
                    "priorityTop=\(self.debugDetection(priorityDetections.first))"
                )
                if let top = priorityDetections.first {
                    var didUseDetrSubject = false

                    self.updateFeatures { features in
                        let measurementTime = Date()
                        self.debugData.detrDetections = detections
                        self.debugData.detrMeasuredAt = measurementTime
                        self.latestDetrSample = self.makeDetrFeatureSample(
                            from: detections,
                            measuredAt: measurementTime
                        )

                        guard !self.shouldPreserveVisionSubjectForLiveDetr(features) else { return }

                        didUseDetrSubject = true
                        features.composition = self.compositionFeatures(from: top.boundingBox)
                        features.composition.subjectAreaRatio = top.boundingBox.width * top.boundingBox.height
                        features.subject.objectName = top.label
                        features.subject.isFace = (top.label.lowercased() == "person")
                        features.subject.isPerson = (top.label.lowercased() == "person")
                        features.subject.count = detections.count
                    }
                    let didUseDetrSubjectSnapshot = didUseDetrSubject
                    print(
                        "[CA_DEBUG][DETR_APPLY] used=\(didUseDetrSubjectSnapshot) " +
                        "reason=\(didUseDetrSubjectSnapshot ? "priority_subject" : "preserved_vision_subject") " +
                        "top=\(self.debugDetection(top)) overlay=\(self.debugRect(didUseDetrSubjectSnapshot ? top.boundingBox : self.overlayState.primaryBoundingBox))"
                    )
                    Task { @MainActor in
                        if didUseDetrSubjectSnapshot {
                            if CameraLog.detr {
                                os_log("🎯 DETR PRIORITY: Using %{public}@ (conf=%.2f) for composition",
                                       log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
                                       type: .debug, top.label, top.confidence)
                            }
                            self.overlayState.primaryBoundingBox = top.boundingBox
                        } else {
                            if CameraLog.detr {
                                os_log("🎯 DETR PRIORITY: Keeping Vision subject over %{public}@",
                                       log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
                                       type: .debug, top.label)
                            }
                        }
                        await self.emitSuggestion()
                    }
                } else {
                    if CameraLog.detr {
                        os_log("🎯 DETR PRIORITY: No foreground subject for composition",
                               log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
                               type: .debug)
                    }
                    var shouldClearDetrOverlay = false
                    self.updateFeatures { features in
                        let measurementTime = Date()
                        self.debugData.detrDetections = detections
                        self.debugData.detrMeasuredAt = measurementTime
                        self.latestDetrSample = self.makeDetrFeatureSample(
                            from: detections,
                            measuredAt: measurementTime
                        )

                        guard !self.shouldPreserveVisionSubjectForLiveDetr(features) else { return }

                        shouldClearDetrOverlay = true
                        if let saliencyCenter = self.debugData.saliencyCenter {
                            features.composition = self.compositionFeatures(fromSaliency: saliencyCenter)
                        }
                        features.composition.subjectAreaRatio = 0
                        features.subject.objectName = nil
                        features.subject.count = 0
                    }
                    let shouldClearDetrOverlaySnapshot = shouldClearDetrOverlay
                    print(
                        "[CA_DEBUG][DETR_APPLY] used=false reason=\(shouldClearDetrOverlaySnapshot ? "cleared_no_priority_subject" : "preserved_vision_subject") " +
                        "top=none overlay=\(self.debugRect(shouldClearDetrOverlaySnapshot ? nil : self.overlayState.primaryBoundingBox))"
                    )
                    Task { @MainActor in
                        if shouldClearDetrOverlaySnapshot {
                            self.overlayState.primaryBoundingBox = nil
                        }
                        await self.emitSuggestion()
                    }
                }
            }
        }

        if thermalAllowsLowPriority, now.timeIntervalSince(lastAestheticRequest) > 6.0 {
            lastAestheticRequest = now
            let aestheticStart = CACurrentMediaTime()
            Telemetry.shared.setActiveModule("Aesthetic", active: true)
            aestheticScorer.score(pixelBuffer: context.pixelBuffer,
                                   orientation: context.orientation) { [weak self] score in
                let aestheticLatency = CACurrentMediaTime() - aestheticStart
                Telemetry.shared.recordLatency(label: "Aesthetic", duration: aestheticLatency)
                Telemetry.shared.setActiveModule("Aesthetic", active: false)

                guard let self, let score else { return }
                if CameraLog.detr {
                    os_log("🎨 Aesthetic score: %.2f (in %.0fms)",
                           log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
                           type: .debug, score, aestheticLatency * 1000)
                }

                // Обновляем Debug Overlay
                Telemetry.shared.setAestheticScore(score)

                self.updateFeatures { features in
                    features.aestheticScore = CGFloat(score)
                    let measurementTime = Date()
                    self.latestAestheticSample = self.makeAestheticFeatureSample(
                        score10: score,
                        measuredAt: measurementTime
                    )
                    self.latestAestheticMeasuredAt = measurementTime
                }
            }
        }
    }

    @MainActor
    private func emitSuggestion() async {
        let now = Date()
        let localFeatures = featureQueue.sync { features }
        
        if localFeatures.motion.state != .still {
            if lastLiveMotionBecameUnstableAt == nil {
                lastLiveMotionBecameUnstableAt = now
            }

            let unstableDuration = now.timeIntervalSince(lastLiveMotionBecameUnstableAt ?? now)
            guard unstableDuration >= liveHintMotionHideGrace else {
                return
            }

            if currentSuggestion != nil || currentLiveHint != nil {
                if CameraLog.liveHintDecisions {
                    os_log("🚫 Hiding suggestion (camera %{public}@)",
                           log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
                           type: .debug, String(describing: localFeatures.motion.state))
                }
                currentSuggestion = nil
            }
            currentLiveHint = nil
            liveHintExpiresAt = .distantPast
            currentDemoOverlayAnnotations = []
            demoSubjectTrack = nil
            currentLiveFusionTraceBundle = nil
            publishOverlayAnnotations([], now: now)
            return
        }
        lastLiveMotionBecameUnstableAt = nil
        
        if currentSuggestion != nil, now <= suggestionExpiry {
            // Keep the legacy fallback stable while it is alive; liveHint decides whether it is visible.
        } else if let pick = suggestionEngine.nextSuggestion(from: localFeatures) {
            if currentSuggestion?.type == pick.type,
               currentSuggestion?.text == pick.text {
                suggestionExpiry = now.addingTimeInterval(pick.ttl)
            } else {
                currentSuggestion = pick
                suggestionExpiry = now.addingTimeInterval(pick.ttl)
                Telemetry.shared.recordSuggestion(pick)
            }
        } else {
            // Нет новой подсказки — удерживаем прежнюю до TTL
            if now > suggestionExpiry {
                currentSuggestion = nil
            }
        }

        let snapshot = makeFeatureSnapshot(
            mode: .live,
            frameId: currentSourceFrameId(fallbackDate: now),
            capturedAt: now
        )
        let semantics = sceneSemanticsAnalyzer.analyze(snapshot: snapshot)
        let deterministicCritique = frameCritiqueEngine.analyze(snapshot: snapshot, semantics: semantics)
        let (fusionOutput, liveNeuralOutcome): (HybridFusionOutput, NeuralEvidenceRecordedOutcome?)
        if liveHybridFusionEnabled {
            (fusionOutput, liveNeuralOutcome) = await resolveCritiqueWithHybridFusion(
                mode: .live,
                capturedAt: now,
                pixelBuffer: lastPixelBuffer,
                orientation: lastOrientation,
                snapshot: snapshot,
                semantics: semantics,
                deterministicCritique: deterministicCritique,
                forcePauseExecution: false
            )
        } else {
            fusionOutput = hybridFusionService.fuse(
                HybridFusionInput(
                    snapshot: snapshot,
                    semantics: semantics,
                    critique: deterministicCritique,
                    neuralSnapshot: nil,
                    neuralMetadata: nil
                )
            )
            liveNeuralOutcome = nil
        }
        let critique = fusionOutput.critique
        let plan = recommendationPlanner.makePlan(snapshot: snapshot, critique: critique)
        let semanticTips = semanticTipPlanner.plan(
            input: SemanticTipPlannerInput(
                frameId: snapshot.frameId,
                mode: .live,
                critique: critique,
                recommendationPlan: plan,
                semantics: semantics,
                currentLiveTipKey: currentSemanticLiveTipKey()
            )
        )
        if let neuralSnapshot = executedNeuralSnapshot(from: liveNeuralOutcome),
           !fusionOutput.appliedDecisions.isEmpty {
            currentLiveFusionTraceBundle = makeLiveFusionTraceBundle(
                critique: critique,
                plan: plan,
                neuralSnapshot: neuralSnapshot,
                fusionOutput: fusionOutput
            )
        } else {
            currentLiveFusionTraceBundle = nil
        }
        let structuredDecision = structuredPathDecision(
            mode: .live,
            critique: critique,
            plan: plan,
            motionState: snapshot.motion.state
        )
        let technicalQualitySignal = technicalQualitySignal(for: lastPixelBuffer)
        publishLivePresentation(
            frameId: snapshot.frameId,
            critique: critique,
            plan: plan,
            snapshot: snapshot,
            semantics: semantics,
            semanticTips: semanticTips,
            legacySuggestion: currentSuggestion,
            structuredAvailable: structuredDecision.isAvailable,
            technicalQualitySignal: technicalQualitySignal,
            now: now
        )
        let annotations = makeOverlayAnnotations(
            frameId: snapshot.frameId,
            critique: critique,
            plan: plan,
            features: localFeatures,
            mode: .live,
            legacySuggestions: currentSuggestion.map { [$0] } ?? [],
            forceLegacyOnly: !structuredDecision.isAvailable,
            liveHint: currentLiveHint
        )
        publishOverlayAnnotations(annotations, now: now)
    }

    @MainActor
    private func publishLivePresentation(frameId: String,
                                         critique: CritiqueReport,
                                         plan: RecommendationPlan,
                                         snapshot: FrameFeatureSnapshot,
                                         semantics: SceneSemanticsReport,
                                         semanticTips: SemanticTipPlannerOutput,
                                         legacySuggestion: Suggestion?,
                                         structuredAvailable: Bool,
                                         technicalQualitySignal: TechnicalQualitySignal = .empty,
                                         now: Date) {
        let hintCandidate = makeLiveHintPresentation(
            frameId: frameId,
            critique: critique,
            plan: plan,
            semanticTip: semanticTips.livePrimaryTip,
            semanticFallbackUsed: semanticTips.fallbackUsed,
            legacySuggestion: legacySuggestion,
            forceLegacyFallback: !structuredAvailable,
            technicalQualitySignal: technicalQualitySignal,
            snapshot: snapshot,
            semantics: semantics
        )
        let demoDecision = makeDemoCoachingDecision(
            frameId: frameId,
            snapshot: snapshot,
            semantics: semantics,
            now: now
        )
        currentDemoOverlayAnnotations = demoDecision?.annotations ?? []
        let effectiveHintCandidate: LiveHintPresentation?
        if let demoDecision {
            effectiveHintCandidate = demoDecision.hint ?? (demoDecision.suppressesPipelineHint ? nil : hintCandidate)
        } else {
            effectiveHintCandidate = hintCandidate
        }
        printLiveDecisionDebug(
            candidate: effectiveHintCandidate,
            frameId: frameId,
            critique: critique,
            plan: plan,
            snapshot: snapshot,
            semantics: semantics,
            semanticTip: semanticTips.livePrimaryTip,
            legacySuggestion: legacySuggestion,
            structuredAvailable: structuredAvailable,
            technicalQualitySignal: technicalQualitySignal
        )
        logLiveHintDecision(
            candidate: effectiveHintCandidate,
            legacySuggestion: legacySuggestion,
            semanticTip: semanticTips.livePrimaryTip,
            structuredAvailable: structuredAvailable,
            critique: critique,
            plan: plan
        )
        applyLiveHint(candidate: effectiveHintCandidate, now: now)
    }

    @MainActor
    private func makeDemoCoachingDecision(frameId: String,
                                          snapshot: FrameFeatureSnapshot,
                                          semantics: SceneSemanticsReport,
                                          now: Date) -> DemoCoachingDecision? {
        guard demoLiveCoachEnabled else { return nil }

        let resolvedMode = resolvedDemoSceneMode(snapshot: snapshot, semantics: semantics)
        guard let detectedSubject = selectDemoSubject(mode: resolvedMode, snapshot: snapshot, semantics: semantics) else {
            if let heldDecision = makeHeldDemoSubjectDecision(
                frameId: frameId,
                mode: resolvedMode,
                snapshot: snapshot,
                now: now
            ) {
                return heldDecision
            }
            demoSubjectTrack = nil
            print(
                "[CA_DEBUG][DEMO_SUPPRESS] reason=no_demo_subject mode=\(cameraDemoSceneMode.rawValue) " +
                "resolved=\(resolvedMode.rawValue) topObject=\(snapshot.subjectSignals.topObjectLabel ?? "nil") " +
                "faceRegion=\(debugRegion(snapshot.subjectSignals.faceRegion)) topRegion=\(debugRegion(snapshot.subjectSignals.topObjectRegion)) " +
                "primaryRegion=\(debugRegion(snapshot.subjectSignals.primaryCandidateRegion)) semantic=\(debugPrimarySubject(semantics.primarySubject))"
            )
            return DemoCoachingDecision(hint: nil, annotations: [], suppressesPipelineHint: true)
        }

        let track = updateDemoSubjectTrack(with: detectedSubject, now: now)
        let subject = track.subject

        let rule = selectDemoRule(
            subject: subject,
            mode: resolvedMode,
            snapshot: snapshot,
            semantics: semantics,
            stableCount: track.stableCount
        )
        let annotations = makeDemoAnnotations(frameId: frameId, subject: subject, rule: rule)
        let hint = rule.showHint ? makeDemoLiveHint(
            frameId: frameId,
            subject: subject,
            rule: rule
        ) : nil

        print(
            "[CA_DEBUG][DEMO_SUBJECT] mode=\(cameraDemoSceneMode.rawValue) resolved=\(resolvedMode.rawValue) " +
            "kind=\(subject.kind.rawValue) label=\(subject.rawLabel ?? "nil") display=\(subject.displayLabel) " +
            "conf=\(debugDouble(subject.confidence)) stable=\(track.stableCount) misses=\(track.missCount) region=\(debugRegion(subject.region))"
        )
        print(
            "[CA_DEBUG][DEMO_TRACK] state=detected identity=\(demoSubjectIdentityKey(subject)) " +
            "stable=\(track.stableCount) misses=\(track.missCount) region=\(debugRegion(subject.region))"
        )
        print(
            "[CA_DEBUG][DEMO_RULE] id=\(rule.id) tone=\(rule.tone.rawValue) showHint=\(rule.showHint) " +
            "confidence=\(debugDouble(rule.confidence)) text=\(debugText(rule.text))"
        )
        print(
            "[CA_DEBUG][DEMO_PRESENTATION] rule=\(rule.id) annotations=\(annotations.count) " +
            "successCheckOnly=\(rule.tone == .success) visibleLabel=\(subject.displayLabel) rawLabel=\(subject.rawLabel ?? "nil")"
        )
        if let hint {
            print(
                "[CA_DEBUG][DEMO_HINT] id=\(hint.id) action=\(hint.actionType?.rawValue ?? "none") " +
                "target=\(debugRegion(hint.targetRegion)) text=\(debugText(hint.text))"
            )
        }

        return DemoCoachingDecision(
            hint: hint,
            annotations: annotations,
            suppressesPipelineHint: true
        )
    }

    @MainActor
    private func makeHeldDemoSubjectDecision(frameId: String,
                                             mode: CameraDemoSceneMode,
                                             snapshot: FrameFeatureSnapshot,
                                             now: Date) -> DemoCoachingDecision? {
        guard var track = demoSubjectTrack,
              now.timeIntervalSince(track.lastSeenAt) <= demoSubjectHoldAge(for: track.subject),
              track.missCount < demoSubjectHoldMissLimit(for: track.subject) else {
            return nil
        }
        track.missCount += 1
        demoSubjectTrack = track
        let rule = demoWaitingRule(for: track.subject)
        let annotations = makeDemoAnnotations(frameId: frameId, subject: track.subject, rule: rule)
        let hint = makeDemoLiveHint(frameId: frameId, subject: track.subject, rule: rule)
        print(
            "[CA_DEBUG][DEMO_TRACK] state=held mode=\(mode.rawValue) identity=\(demoSubjectIdentityKey(track.subject)) " +
            "stable=\(track.stableCount) misses=\(track.missCount) ageMs=\(debugDouble(now.timeIntervalSince(track.lastSeenAt) * 1000))"
        )
        print(
            "[CA_DEBUG][DEMO_SUPPRESS] reason=holding_last_subject topObject=\(snapshot.subjectSignals.topObjectLabel ?? "nil") " +
            "region=\(debugRegion(track.subject.region))"
        )
        return DemoCoachingDecision(hint: hint, annotations: annotations, suppressesPipelineHint: true)
    }

    @MainActor
    private func updateDemoSubjectTrack(with subject: DemoCoachingSubject, now: Date) -> DemoSubjectTrack {
        if var track = demoSubjectTrack,
           isSameDemoSubject(previous: track.subject, current: subject) {
            track.subject = subject
            track.stableCount += 1
            track.missCount = 0
            track.lastSeenAt = now
            demoSubjectTrack = track
            return track
        }

        let track = DemoSubjectTrack(subject: subject, stableCount: 1, missCount: 0, lastSeenAt: now)
        demoSubjectTrack = track
        return track
    }

    private func makeDemoAnnotations(frameId: String,
                                     subject: DemoCoachingSubject,
                                     rule: DemoCoachingRule) -> [OverlayAnnotationPresentation] {
        guard rule.tone != .success else { return [] }
        return [
            OverlayAnnotationPresentation(
                id: "demo_\(frameId)_\(rule.id)_\(quantizedRegionKey(for: subject.region))",
                kind: .regionHighlight,
                direction: nil,
                targetRegion: subject.region,
                emphasis: max(0.72, rule.confidence),
                tone: rule.tone,
                label: subject.displayLabel
            )
        ]
    }

    private func isSameDemoSubject(previous: DemoCoachingSubject,
                                   current: DemoCoachingSubject) -> Bool {
        guard previous.kind == current.kind else { return false }
        guard demoSubjectIdentityKey(previous) == demoSubjectIdentityKey(current) else { return false }
        let iou = intersectionOverUnion(previous.region, current.region)
        if iou >= 0.25 { return true }
        let distance = centerDistance(previous.region, current.region)
        let previousArea = max(0.001, previous.region.width * previous.region.height)
        let currentArea = max(0.001, current.region.width * current.region.height)
        let areaRatio = max(previousArea, currentArea) / min(previousArea, currentArea)
        return distance <= 0.12 && areaRatio <= 2.8
    }

    private func demoSubjectIdentityKey(_ subject: DemoCoachingSubject) -> String {
        switch subject.kind {
        case .object:
            return "\(subject.kind.rawValue)_\(normalizedDemoObjectLabel(subject.rawLabel ?? "object"))"
        case .portrait:
            return "\(subject.kind.rawValue)_person"
        case .dialogue:
            return "\(subject.kind.rawValue)_group"
        }
    }

    private func demoSubjectHoldAge(for subject: DemoCoachingSubject) -> TimeInterval {
        switch subject.kind {
        case .object:
            return 0.55
        case .portrait, .dialogue:
            return 0.35
        }
    }

    private func demoSubjectHoldMissLimit(for subject: DemoCoachingSubject) -> Int {
        switch subject.kind {
        case .object:
            return 1
        case .portrait, .dialogue:
            return 1
        }
    }

    private func intersectionOverUnion(_ lhs: NormalizedRect, _ rhs: NormalizedRect) -> Double {
        let left = max(lhs.x, rhs.x)
        let top = max(lhs.y, rhs.y)
        let right = min(lhs.x + lhs.width, rhs.x + rhs.width)
        let bottom = min(lhs.y + lhs.height, rhs.y + rhs.height)
        let intersectionWidth = max(0, right - left)
        let intersectionHeight = max(0, bottom - top)
        let intersectionArea = intersectionWidth * intersectionHeight
        let lhsArea = lhs.width * lhs.height
        let rhsArea = rhs.width * rhs.height
        let unionArea = lhsArea + rhsArea - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }

    private func centerDistance(_ lhs: NormalizedRect, _ rhs: NormalizedRect) -> Double {
        let lhsX = lhs.x + lhs.width * 0.5
        let lhsY = lhs.y + lhs.height * 0.5
        let rhsX = rhs.x + rhs.width * 0.5
        let rhsY = rhs.y + rhs.height * 0.5
        let dx = lhsX - rhsX
        let dy = lhsY - rhsY
        return sqrt(dx * dx + dy * dy)
    }

    private func resolvedDemoSceneMode(snapshot: FrameFeatureSnapshot,
                                       semantics: SceneSemanticsReport) -> CameraDemoSceneMode {
        if cameraDemoSceneMode != .auto {
            return cameraDemoSceneMode
        }
        if snapshot.subjectSignals.personCount >= 2 || semantics.sceneType == .twoCharacterFrame {
            return .dialogue
        }
        if snapshot.subjectSignals.faceDetected || snapshot.subjectSignals.personDetected {
            return .portrait
        }
        if let label = snapshot.subjectSignals.topObjectLabel,
           isDemoPriorityObjectLabel(label),
           snapshot.subjectSignals.topObjectRegion != nil {
            return .object
        }
        return .auto
    }

    private func selectDemoSubject(mode: CameraDemoSceneMode,
                                   snapshot: FrameFeatureSnapshot,
                                   semantics: SceneSemanticsReport) -> DemoCoachingSubject? {
        switch mode {
        case .portrait, .cinematicPortrait, .dialogue:
            if let subject = personDemoSubject(mode: mode, snapshot: snapshot, semantics: semantics) {
                return subject
            }
            if mode == .dialogue {
                return objectDemoSubject(snapshot: snapshot)
            }
            return nil
        case .object:
            return objectDemoSubject(snapshot: snapshot)
        case .auto:
            if let subject = personDemoSubject(mode: .portrait, snapshot: snapshot, semantics: semantics) {
                return subject
            }
            return objectDemoSubject(snapshot: snapshot)
        }
    }

    private func personDemoSubject(mode: CameraDemoSceneMode,
                                   snapshot: FrameFeatureSnapshot,
                                   semantics: SceneSemanticsReport) -> DemoCoachingSubject? {
        let subject = semantics.primarySubject
        let candidateRegion = validDemoRegion(subject.region)
            ?? validDemoRegion(snapshot.subjectSignals.primaryCandidateRegion)
        let region: NormalizedRect?
        if snapshot.subjectSignals.faceDetected {
            if let faceRegion = validDemoRegion(snapshot.subjectSignals.faceRegion) {
                region = faceRegion
            } else {
                region = candidateRegion.flatMap(portraitFaceFallbackRegion(from:))
            }
        } else {
            region = candidateRegion
        }
        guard let region else { return nil }

        let hasPerson = snapshot.subjectSignals.faceDetected
            || snapshot.subjectSignals.personDetected
            || subject.kind == .face
            || subject.kind == .person
            || subject.kind == .group
        guard hasPerson else { return nil }

        let isDialogue = mode == .dialogue || snapshot.subjectSignals.personCount >= 2 || subject.kind == .group
        return DemoCoachingSubject(
            kind: isDialogue ? .dialogue : .portrait,
            rawLabel: subject.kind.rawValue,
            displayLabel: isDialogue ? "Герои" : (snapshot.subjectSignals.faceDetected ? "Лицо" : "Герой"),
            region: region,
            confidence: max(subject.confidence, snapshot.subjectSignals.primaryCandidateConfidence ?? 0.45)
        )
    }

    private func objectDemoSubject(snapshot: FrameFeatureSnapshot) -> DemoCoachingSubject? {
        let label = snapshot.subjectSignals.topObjectLabel
        let normalizedLabel = label.map(normalizedDemoObjectLabel)
        let topRegion = validDemoObjectRegion(snapshot.subjectSignals.topObjectRegion)
        let primaryRegion = validDemoObjectRegion(snapshot.subjectSignals.primaryCandidateRegion)

        if let label,
           isDemoPriorityObjectLabel(label),
           let region = topRegion ?? primaryRegion {
            return DemoCoachingSubject(
                kind: .object,
                rawLabel: label,
                displayLabel: demoObjectDisplayName(label),
                region: region,
                confidence: snapshot.subjectSignals.topObjectConfidence ?? snapshot.subjectSignals.primaryCandidateConfidence ?? 0.45
            )
        }

        if let label,
           let region = topRegion,
           !isDemoBackgroundObjectLabel(label) {
            return DemoCoachingSubject(
                kind: .object,
                rawLabel: label,
                displayLabel: "Объект",
                region: region,
                confidence: snapshot.subjectSignals.topObjectConfidence ?? 0.52
            )
        }

        let hasPersonSignal = snapshot.subjectSignals.faceDetected || snapshot.subjectSignals.personDetected
        if !hasPersonSignal,
           let region = primaryRegion,
           normalizedLabel.map(isDemoBackgroundObjectLabel) != true {
            return DemoCoachingSubject(
                kind: .object,
                rawLabel: label ?? "object",
                displayLabel: "Объект",
                region: region,
                confidence: snapshot.subjectSignals.primaryCandidateConfidence ?? snapshot.subjectSignals.topObjectConfidence ?? 0.54
            )
        }

        return nil
    }

    private func selectDemoRule(subject: DemoCoachingSubject,
                                mode: CameraDemoSceneMode,
                                snapshot: FrameFeatureSnapshot,
                                semantics: SceneSemanticsReport,
                                stableCount: Int) -> DemoCoachingRule {
        let region = subject.region
        let centerX = region.x + region.width * 0.5
        let area = region.width * region.height
        let minEdgeDistance = min(region.x, region.y, 1 - (region.x + region.width), 1 - (region.y + region.height))

        if subject.kind == .portrait || subject.kind == .dialogue {
            if mode == .cinematicPortrait {
                return selectCinematicPortraitRule(
                    subject: subject,
                    snapshot: snapshot,
                    stableCount: stableCount
                )
            }

            if let subjectLighting = snapshot.lighting.subjectLighting {
                if subjectLighting.subjectMeanLuma >= 0.78 || subjectLighting.subjectClippedBrightRatio >= 0.10 {
                    return DemoCoachingRule(
                        id: "portrait_overexposed_face",
                        text: "Лицо пересвечено — убавь свет или смени угол.",
                        shortVerdict: "Лицо найдено, но свет слишком жёсткий.",
                        supportingText: demoLightingSupportingText(
                            prefix: "Система сравнила яркость лица и фона: на лице есть выбитые светлые участки.",
                            lighting: subjectLighting
                        ),
                        actionText: "Убавь источник, отведи его в сторону или поверни героя от прямого света.",
                        actionType: .improveFrontLight,
                        tone: .danger,
                        confidence: min(0.94, max(0.74, subjectLighting.subjectMeanLuma + subjectLighting.subjectClippedBrightRatio)),
                        showHint: true
                    )
                }

                let backgroundMinusSubject = subjectLighting.backgroundMeanLuma - subjectLighting.subjectMeanLuma
                if backgroundMinusSubject >= 0.18 ||
                    (subjectLighting.backgroundHotspotRatio >= 0.16 && subjectLighting.subjectMeanLuma <= 0.56) {
                    return DemoCoachingRule(
                        id: "portrait_backlight",
                        text: "Фон ярче лица — смени угол.",
                        shortVerdict: "Герой найден, но фон перетягивает внимание.",
                        supportingText: demoLightingSupportingText(
                            prefix: "Лицо темнее окружения: яркий фон или источник света конкурирует с героем.",
                            lighting: subjectLighting
                        ),
                        actionText: "Поверни камеру или героя так, чтобы яркий фон не бил из-за спины.",
                        actionType: .improveFrontLight,
                        tone: .danger,
                        confidence: min(0.94, max(0.74, backgroundMinusSubject + subjectLighting.backgroundHotspotRatio + 0.58)),
                        showHint: true
                    )
                }

                if subjectLighting.subjectMeanLuma <= 0.34 {
                    return DemoCoachingRule(
                        id: "portrait_dark_face",
                        text: "Лицо темновато — добавь мягкий свет спереди.",
                        shortVerdict: "Герой найден, но лицо недосвечено.",
                        supportingText: demoLightingSupportingText(
                            prefix: "Система измерила яркость внутри bbox лица: субъект темнее комфортного уровня.",
                            lighting: subjectLighting
                        ),
                        actionText: "Добавь фронтальный или боковой мягкий свет и подержи кадр стабильно.",
                        actionType: .improveFrontLight,
                        tone: .danger,
                        confidence: min(0.92, max(0.72, 0.92 - subjectLighting.subjectMeanLuma)),
                        showHint: true
                    )
                }
            }

            if snapshot.lighting.backlightIndex >= 0.22,
               snapshot.lighting.exposureBiasHint > -1.4 {
                return DemoCoachingRule(
                    id: "portrait_backlight",
                    text: "Фон ярче лица — смени угол.",
                    shortVerdict: "Фон перетягивает внимание с лица.",
                    supportingText: "Система видит лицо/героя и более яркий фон за ним: контровой свет снижает читаемость субъекта.",
                    actionText: "Поверни камеру или героя так, чтобы яркий источник не бил из-за спины.",
                    actionType: .improveFrontLight,
                    tone: .danger,
                    confidence: max(0.72, min(0.92, snapshot.lighting.backlightIndex + 0.55)),
                    showHint: true
                )
            }

            if snapshot.lighting.exposureBiasHint <= -0.45 {
                return DemoCoachingRule(
                    id: "portrait_dark_face",
                    text: "Лицо темновато — добавь мягкий свет спереди.",
                    shortVerdict: "Герой читается, но лицо недосвечено.",
                    supportingText: "Основной субъект найден как человек/лицо, при этом экспозиция по субъекту ниже комфортного уровня.",
                    actionText: "Добавь фронтальный или боковой мягкий свет и пересними кадр.",
                    actionType: .improveFrontLight,
                    tone: .danger,
                    confidence: min(0.92, max(0.70, abs(snapshot.lighting.exposureBiasHint) * 0.75)),
                    showHint: true
                )
            }

            if minEdgeDistance < 0.045 {
                let moveRight = centerX < 0.5
                return DemoCoachingRule(
                    id: "portrait_edge",
                    text: moveRight ? "Оставь больше воздуха слева от лица." : "Оставь больше воздуха справа от лица.",
                    shortVerdict: "Лицо слишком близко к краю кадра.",
                    supportingText: "Bounding box героя касается края, поэтому зрителю сложнее воспринимать портрет как аккуратно собранный.",
                    actionText: moveRight ? "Смести камеру чуть вправо." : "Смести камеру чуть влево.",
                    actionType: moveRight ? .moveFrameRight : .moveFrameLeft,
                    tone: .danger,
                    confidence: 0.82,
                    showHint: true
                )
            }

            if snapshot.objects.totalCount >= 4 && !semantics.dominance.hasClearFocus {
                return DemoCoachingRule(
                    id: "portrait_busy_background",
                    text: "Фон спорит с героем — упрости сцену.",
                    shortVerdict: "В кадре есть герой, но фон конкурирует с ним.",
                    supportingText: "Система видит несколько объектов вокруг субъекта и слабую иерархию внимания.",
                    actionText: "Смени угол или убери лишние элементы за человеком.",
                    actionType: .reduceBackgroundDistractions,
                    tone: .warning,
                    confidence: 0.74,
                    showHint: true
                )
            }

            if stableCount < 3 {
                return demoWaitingRule(for: subject)
            }

            return DemoCoachingRule(
                id: "portrait_good",
                text: subject.kind == .dialogue ? "Герои зафиксированы." : "Лицо зафиксировано.",
                shortVerdict: "Главный субъект стабильно найден.",
                supportingText: "Система несколько кадров подряд удерживает bbox героя и не видит критичных live-проблем.",
                actionText: nil,
                actionType: .leaveFrameAsIs,
                tone: .success,
                confidence: max(0.76, min(0.92, subject.confidence)),
                showHint: true
            )
        }

        if minEdgeDistance < 0.055 {
            let moveRight = centerX < 0.5
            return DemoCoachingRule(
                id: "object_edge",
                text: moveRight ? "Сдвинь объект правее." : "Сдвинь объект левее.",
                shortVerdict: "Предмет слишком близко к краю.",
                supportingText: "Система видит главный объект и bbox почти касается края кадра. Детектор: \(subject.rawLabel ?? "object").",
                actionText: moveRight ? "Перемести предмет или камеру чуть вправо." : "Перемести предмет или камеру чуть влево.",
                actionType: moveRight ? .moveFrameRight : .moveFrameLeft,
                tone: .danger,
                confidence: 0.86,
                showHint: true
            )
        }

        if area < 0.035 {
            return DemoCoachingRule(
                id: "object_too_small",
                text: "Объект теряется — подойди ближе.",
                shortVerdict: "Предмет найден, но занимает мало кадра.",
                supportingText: "Bounding box главного объекта слишком мал относительно всего кадра. Детектор: \(subject.rawLabel ?? "object").",
                actionText: "Подойди ближе или увеличь объект в кадре.",
                actionType: .increaseSubjectSize,
                tone: .danger,
                confidence: 0.84,
                showHint: true
            )
        }

        if !isNearDemoCompositionAnchor(x: centerX) {
            let moveRight = centerX < 0.5
            return DemoCoachingRule(
                id: "object_thirds",
                text: moveRight ? "Сдвинь объект правее к линии третей." : "Сдвинь объект левее к линии третей.",
                shortVerdict: "Предмет виден, но композиционно стоит невыгодно.",
                supportingText: "Центр bbox не попадает ни в устойчивую центральную зону, ни рядом с линиями третей.",
                actionText: "Смести предмет к ближайшей вертикали третей.",
                actionType: moveRight ? .moveFrameRight : .moveFrameLeft,
                tone: .danger,
                confidence: 0.78,
                showHint: true
            )
        }

        if snapshot.lighting.exposureBiasHint <= -0.55 {
            return DemoCoachingRule(
                id: "object_dark",
                text: "Объект темноват — добавь свет спереди.",
                shortVerdict: "Предмет найден, но освещение слабое.",
                supportingText: "Субъект найден по bbox, при этом экспозиция указывает на недостаток света.",
                actionText: "Добавь мягкий свет на предмет или поверни его к источнику.",
                actionType: .improveFrontLight,
                tone: .warning,
                confidence: 0.74,
                showHint: true
            )
        }

        if stableCount < 3 {
            return demoWaitingRule(for: subject)
        }

        return DemoCoachingRule(
            id: "object_good",
            text: "Объект зафиксирован.",
            shortVerdict: "Главный предмет стабильно найден.",
            supportingText: "Система несколько кадров подряд удерживает bbox предмета и не видит критичных live-проблем.",
            actionText: nil,
            actionType: .leaveFrameAsIs,
            tone: .success,
            confidence: max(0.76, min(0.92, subject.confidence)),
            showHint: true
        )
    }

    private func selectCinematicPortraitRule(subject: DemoCoachingSubject,
                                             snapshot: FrameFeatureSnapshot,
                                             stableCount: Int) -> DemoCoachingRule {
        guard let subjectLighting = snapshot.lighting.subjectLighting else {
            print(
                "[CA_DEBUG][DEMO_RECIPE] mode=cinematic_portrait step=\(demoCinematicPortraitStep.rawValue) " +
                "reason=no_subject_lighting subject=\(debugRegion(subject.region))"
            )
            return DemoCoachingRule(
                id: "cinematic_portrait_wait_light",
                text: "Фиксирую свет лица…",
                shortVerdict: "Лицо найдено, ждём метрики света.",
                supportingText: "Система удерживает bbox лица, но ещё не получила надёжные значения яркости лица и фона.",
                actionText: nil,
                actionType: nil,
                tone: .warning,
                confidence: max(0.55, min(0.72, subject.confidence)),
                showHint: true
            )
        }

        var safety = 0
        while safety < 5 {
            safety += 1
            prepareCinematicPortraitStepEvidence(lighting: subjectLighting)

            switch demoCinematicPortraitStep {
            case .darkenBackground:
                let satisfied = cinematicPortraitBackgroundReadyForDemo(subjectLighting)
                logCinematicPortraitRecipe(
                    step: .darkenBackground,
                    satisfied: satisfied,
                    subject: subject,
                    lighting: subjectLighting
                )
                if canAdvanceCinematicPortraitStep(with: satisfied) {
                    advanceCinematicPortraitStep(to: .addFaceLight)
                    continue
                }
                markCinematicPortraitStepPresented()
                return DemoCoachingRule(
                    id: "cinematic_portrait_darken_background",
                    text: "Сделай фон темнее.",
                    shortVerdict: "Лицо найдено, но фон слишком близок по яркости.",
                    supportingText: demoLightingSupportingText(
                        prefix: "Система сравнила лицо и фон: герой ещё недостаточно отделён по яркости.",
                        lighting: subjectLighting
                    ),
                    actionText: "Убери яркий фон, отвернись от светлой стены или затемни источник за героем.",
                    actionType: .reduceBackgroundDistractions,
                    tone: .danger,
                    confidence: min(0.92, max(0.72, 0.82 - subjectLighting.subjectToBackgroundDelta)),
                    showHint: true
                )

            case .addFaceLight:
                if cinematicPortraitBackgroundRegressedForDemo(subjectLighting) {
                    advanceCinematicPortraitStep(to: .darkenBackground)
                    continue
                }
                let satisfied = cinematicPortraitFaceLightReadyForDemo(subjectLighting)
                logCinematicPortraitRecipe(
                    step: .addFaceLight,
                    satisfied: satisfied,
                    subject: subject,
                    lighting: subjectLighting
                )
                if canAdvanceCinematicPortraitStep(with: satisfied) {
                    advanceCinematicPortraitStep(to: .reduceFaceOverexposure)
                    continue
                }
                markCinematicPortraitStepPresented()
                return DemoCoachingRule(
                    id: "cinematic_portrait_add_face_light",
                    text: "Добавь мягкий свет на лицо.",
                    shortVerdict: "Фон уже отделён, теперь лицо нужно вывести вперёд.",
                    supportingText: demoLightingSupportingText(
                        prefix: "Фон стал темнее, но яркость лица ниже комфортного уровня для читаемого портрета.",
                        lighting: subjectLighting
                    ),
                    actionText: "Подними мягкий фронтальный или боковой свет и держи его не впритык к лицу.",
                    actionType: .improveFrontLight,
                    tone: .danger,
                    confidence: min(0.92, max(0.72, 0.95 - subjectLighting.subjectMeanLuma)),
                    showHint: true
                )

            case .reduceFaceOverexposure:
                if cinematicPortraitBackgroundRegressedForDemo(subjectLighting) {
                    advanceCinematicPortraitStep(to: .darkenBackground)
                    continue
                }
                if cinematicPortraitFaceLightRegressedForDemo(subjectLighting) {
                    advanceCinematicPortraitStep(to: .addFaceLight)
                    continue
                }
                let overexposed = cinematicPortraitFaceLooksOverexposedForDemo(subjectLighting)
                logCinematicPortraitRecipe(
                    step: .reduceFaceOverexposure,
                    satisfied: !overexposed,
                    subject: subject,
                    lighting: subjectLighting
                )
                if overexposed {
                    markCinematicPortraitStepPresented()
                    return DemoCoachingRule(
                        id: "cinematic_portrait_reduce_face_overexposure",
                        text: "Убери пересвет на лице.",
                        shortVerdict: "Свет появился, но на лице выбиваются яркие участки.",
                        supportingText: demoLightingSupportingText(
                            prefix: "Система видит слишком высокую яркость или клиппинг внутри bbox лица.",
                            lighting: subjectLighting
                        ),
                        actionText: "Отодвинь свет, рассей его или поверни лицо от прямого источника.",
                        actionType: .improveFrontLight,
                        tone: .danger,
                        confidence: min(0.94, max(0.76, subjectLighting.subjectMeanLuma + subjectLighting.subjectClippedBrightRatio)),
                        showHint: true
                    )
                }
                if canAdvanceCinematicPortraitStep(with: cinematicPortraitOverexposureRecoveredForDemo(subjectLighting)) {
                    advanceCinematicPortraitStep(to: .complete)
                    continue
                }
                markCinematicPortraitStepPresented()
                return DemoCoachingRule(
                    id: "cinematic_portrait_hold_face_light",
                    text: "Свет на лице стал мягче.",
                    shortVerdict: "Пересвет ушёл, удерживаем лицо перед финальной оценкой.",
                    supportingText: demoLightingSupportingText(
                        prefix: "Система видит, что яркие участки на лице больше не выбиваются.",
                        lighting: subjectLighting
                    ),
                    actionText: nil,
                    actionType: nil,
                    tone: .warning,
                    confidence: max(0.68, min(0.82, subject.confidence)),
                    showHint: true
                )

            case .complete:
                logCinematicPortraitRecipe(
                    step: .complete,
                    satisfied: stableCount >= 3,
                    subject: subject,
                    lighting: subjectLighting
                )
                if stableCount < 3 {
                    return demoWaitingRule(for: subject)
                }
                return DemoCoachingRule(
                    id: "cinematic_portrait_good",
                    text: "Портрет собран.",
                    shortVerdict: "Лицо отделено от фона, свет читается, композиция стабильна.",
                    supportingText: demoLightingSupportingText(
                        prefix: "Система удерживает лицо несколько кадров подряд и видит рабочее разделение лица и фона.",
                        lighting: subjectLighting
                    ),
                    actionText: nil,
                    actionType: .leaveFrameAsIs,
                    tone: .success,
                    confidence: max(0.78, min(0.93, subject.confidence)),
                    showHint: true
                )
            }
        }

        return demoWaitingRule(for: subject)
    }

    private func prepareCinematicPortraitStepEvidence(lighting: FrameFeatureSnapshot.LightingFeatures.SubjectLightingMetrics) {
        guard demoCinematicPortraitStepEvidence.lighting == nil else {
            return
        }
        demoCinematicPortraitStepEvidence = DemoCinematicPortraitStepEvidence(
            lighting: lighting,
            presentationCount: 0
        )
    }

    private func markCinematicPortraitStepPresented() {
        demoCinematicPortraitStepEvidence.presentationCount += 1
    }

    private func advanceCinematicPortraitStep(to step: DemoCinematicPortraitStep) {
        guard demoCinematicPortraitStep != step else { return }
        demoCinematicPortraitStep = step
        demoCinematicPortraitStepEvidence = .empty
    }

    private func canAdvanceCinematicPortraitStep(with evidence: Bool) -> Bool {
        evidence && demoCinematicPortraitStepEvidence.presentationCount > 0
    }

    private func cinematicPortraitBackgroundReadyForDemo(_ lighting: FrameFeatureSnapshot.LightingFeatures.SubjectLightingMetrics) -> Bool {
        guard let baseline = demoCinematicPortraitStepEvidence.lighting else {
            return false
        }
        let deltaGain = lighting.subjectToBackgroundDelta - baseline.subjectToBackgroundDelta
        let backgroundDrop = baseline.backgroundMeanLuma - lighting.backgroundMeanLuma
        let subjectDrop = baseline.subjectMeanLuma - lighting.subjectMeanLuma
        let relativeSeparationImproved = deltaGain >= 0.05 && lighting.subjectToBackgroundDelta >= 0.06
        let backgroundActuallyDarker = backgroundDrop >= 0.06 && subjectDrop <= 0.04
        return (relativeSeparationImproved || backgroundActuallyDarker) && lighting.backgroundHotspotRatio < 0.24
    }

    private func cinematicPortraitBackgroundRegressedForDemo(_ lighting: FrameFeatureSnapshot.LightingFeatures.SubjectLightingMetrics) -> Bool {
        lighting.subjectToBackgroundDelta < -0.08 || lighting.backgroundHotspotRatio >= 0.34
    }

    private func cinematicPortraitFaceLightReadyForDemo(_ lighting: FrameFeatureSnapshot.LightingFeatures.SubjectLightingMetrics) -> Bool {
        guard let baseline = demoCinematicPortraitStepEvidence.lighting else {
            return false
        }
        let faceLift = lighting.subjectMeanLuma - baseline.subjectMeanLuma
        return lighting.subjectMeanLuma >= 0.54 || (faceLift >= 0.10 && lighting.subjectMeanLuma >= 0.48)
    }

    private func cinematicPortraitFaceLightRegressedForDemo(_ lighting: FrameFeatureSnapshot.LightingFeatures.SubjectLightingMetrics) -> Bool {
        lighting.subjectMeanLuma < 0.36 && lighting.subjectToBackgroundDelta < 0.02
    }

    private func cinematicPortraitFaceLooksOverexposedForDemo(_ lighting: FrameFeatureSnapshot.LightingFeatures.SubjectLightingMetrics) -> Bool {
        lighting.subjectMeanLuma >= 0.72 ||
            lighting.subjectClippedBrightRatio >= 0.05 ||
            (lighting.subjectMeanLuma >= 0.62 && lighting.subjectToBackgroundDelta >= 0.22)
    }

    private func cinematicPortraitOverexposureRecoveredForDemo(_ lighting: FrameFeatureSnapshot.LightingFeatures.SubjectLightingMetrics) -> Bool {
        guard !cinematicPortraitFaceLooksOverexposedForDemo(lighting) else {
            return false
        }
        guard let baseline = demoCinematicPortraitStepEvidence.lighting else {
            return true
        }
        let faceDrop = baseline.subjectMeanLuma - lighting.subjectMeanLuma
        let clipDrop = baseline.subjectClippedBrightRatio - lighting.subjectClippedBrightRatio
        return faceDrop >= 0.04 || clipDrop >= 0.03 || lighting.subjectMeanLuma <= 0.64
    }

    private func logCinematicPortraitRecipe(step: DemoCinematicPortraitStep,
                                            satisfied: Bool,
                                            subject: DemoCoachingSubject,
                                            lighting: FrameFeatureSnapshot.LightingFeatures.SubjectLightingMetrics) {
        let baseline = demoCinematicPortraitStepEvidence.lighting
        let baselineFace = baseline.map { debugDouble($0.subjectMeanLuma) } ?? "nil"
        let baselineBackground = baseline.map { debugDouble($0.backgroundMeanLuma) } ?? "nil"
        let baselineDelta = baseline.map { debugDouble($0.subjectToBackgroundDelta) } ?? "nil"
        print(
            "[CA_DEBUG][DEMO_RECIPE] mode=cinematic_portrait step=\(step.rawValue) " +
            "satisfied=\(satisfied) current=\(demoCinematicPortraitStep.rawValue) " +
            "shown=\(demoCinematicPortraitStepEvidence.presentationCount) " +
            "subject=\(debugRegion(subject.region)) faceLuma=\(debugDouble(lighting.subjectMeanLuma)) " +
            "bgLuma=\(debugDouble(lighting.backgroundMeanLuma)) delta=\(debugDouble(lighting.subjectToBackgroundDelta)) " +
            "faceClip=\(debugDouble(lighting.subjectClippedBrightRatio)) bgHotspot=\(debugDouble(lighting.backgroundHotspotRatio)) " +
            "baselineFace=\(baselineFace) baselineBg=\(baselineBackground) baselineDelta=\(baselineDelta)"
        )
    }

    private func demoWaitingRule(for subject: DemoCoachingSubject) -> DemoCoachingRule {
        DemoCoachingRule(
            id: "subject_waiting",
            text: "Фиксирую \(demoSubjectTextName(subject))…",
            shortVerdict: "Главный субъект найден, ждём стабильности.",
            supportingText: "Система уже видит bbox, но ждёт повторного подтверждения на следующем кадре.",
            actionText: nil,
            actionType: nil,
            tone: .warning,
            confidence: max(0.55, min(0.72, subject.confidence)),
            showHint: true
        )
    }

    private func demoSubjectTextName(_ subject: DemoCoachingSubject) -> String {
        subject.displayLabel.lowercased()
    }

    private func demoLightingSupportingText(prefix: String,
                                            lighting: FrameFeatureSnapshot.LightingFeatures.SubjectLightingMetrics) -> String {
        prefix + " " +
        "Лицо: \(debugDouble(lighting.subjectMeanLuma)), фон: \(debugDouble(lighting.backgroundMeanLuma)), " +
        "дельта: \(debugDouble(lighting.subjectToBackgroundDelta)), пересвет лица: \(debugDouble(lighting.subjectClippedBrightRatio)), " +
        "яркий фон: \(debugDouble(lighting.backgroundHotspotRatio))."
    }

    private func makeDemoLiveHint(frameId: String,
                                  subject: DemoCoachingSubject,
                                  rule: DemoCoachingRule) -> LiveHintPresentation {
        let traceId = "trc_\(frameId)_demo_\(rule.id)"
        let overlayHint = OverlayHint(
            id: "ovh_demo_\(rule.id)_\(quantizedRegionKey(for: subject.region))",
            kind: .regionHighlight,
            targetRegion: subject.region,
            direction: nil
        )
        return LiveHintPresentation(
            id: "lh_demo_\(rule.id)_\(stableDemoSubjectKey(subject))",
            frameId: frameId,
            text: rule.text,
            confidence: rule.confidence,
            actionType: rule.actionType,
            actionId: nil,
            linkedIssueIds: [],
            summaryId: traceId,
            traceRootIds: [traceId],
            targetRegion: subject.region,
            overlayHint: overlayHint,
            isFallback: false,
            expandedVerdict: LiveExpandedVerdictPresentation(
                shortVerdict: rule.shortVerdict,
                supportingText: rule.supportingText,
                actionText: rule.actionText,
                fallbackUsed: false
            )
        )
    }

    private func validDemoRegion(_ region: NormalizedRect?) -> NormalizedRect? {
        guard let region,
              region.x.isFinite,
              region.y.isFinite,
              region.width.isFinite,
              region.height.isFinite,
              !region.isDegenerate,
              region.width * region.height >= 0.002 else {
            return nil
        }
        return region
    }

    private func validDemoObjectRegion(_ region: NormalizedRect?) -> NormalizedRect? {
        guard let region = validDemoRegion(region) else { return nil }
        let area = region.width * region.height
        guard area <= 0.45,
              region.width <= 0.78,
              region.height <= 0.78 else {
            return nil
        }
        return region
    }

    private func portraitFaceFallbackRegion(from region: NormalizedRect) -> NormalizedRect? {
        let aspect = region.width / max(0.001, region.height)
        if region.height <= 0.48 && aspect >= 0.42 && aspect <= 1.35 {
            return region
        }

        let width = min(region.width * 0.72, max(0.12, region.height * 0.46))
        let height = min(region.height * 0.42, max(0.12, width * 1.18))
        let x = clamp01(region.x + (region.width - width) * 0.5)
        let y = clamp01(region.y + region.height * 0.06)
        let clampedWidth = min(width, 1.0 - x)
        let clampedHeight = min(height, 1.0 - y)
        return validDemoRegion(
            NormalizedRect(
                x: x,
                y: y,
                width: clampedWidth,
                height: clampedHeight
            )
        )
    }

    private func stableDemoSubjectKey(_ subject: DemoCoachingSubject) -> String {
        demoSubjectIdentityKey(subject)
    }

    private func isDemoPriorityObjectLabel(_ label: String) -> Bool {
        demoObjectDisplayNames[normalizedDemoObjectLabel(label)] != nil
    }

    private func isDemoBackgroundObjectLabel(_ label: String) -> Bool {
        demoBackgroundObjectLabels.contains(normalizedDemoObjectLabel(label))
    }

    private func demoObjectDisplayName(_ label: String) -> String {
        demoObjectDisplayNames[normalizedDemoObjectLabel(label)] ?? "Объект"
    }

    private var demoObjectDisplayNames: [String: String] {
        [
            "book": "Объект",
            "bottle": "Объект",
            "cell phone": "Объект",
            "cup": "Объект",
            "keyboard": "Объект",
            "laptop": "Объект",
            "potted plant": "Объект",
            "vase": "Объект"
        ]
    }

    private var demoBackgroundObjectLabels: Set<String> {
        [
            "bed",
            "cabinet",
            "ceiling",
            "chair",
            "door",
            "floor",
            "keyboard",
            "paper",
            "screen",
            "sofa",
            "table",
            "tv",
            "wall",
            "window"
        ]
    }

    private func normalizedDemoObjectLabel(_ label: String) -> String {
        let lowercased = label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let base = lowercased.split(separator: "(", maxSplits: 1).first.map(String.init) ?? lowercased
        return base.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isNearDemoCompositionAnchor(x: Double) -> Bool {
        let anchors = [1.0 / 3.0, 0.5, 2.0 / 3.0]
        return anchors.map { abs(x - $0) }.min() ?? 1.0 <= 0.095
    }

    private func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + String(text.dropFirst())
    }

    func clearPausePresentationState() {
        featureQueue.sync {
            pauseAnalysisRevision += 1
        }
        if pauseReasoningTask != nil {
            os_log(
                "reasoning.cancel.pause_exit",
                log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
                type: .debug
            )
        }
        pauseReasoningTask?.cancel()
        pauseReasoningTask = nil
        lastRefinedPauseFrameId = nil
        currentPauseTraceBundle = nil
        DispatchQueue.main.async {
            self.currentPauseCritique = nil
            self.currentOverlayAnnotations = []
        }
    }

    func clearLivePresentationState() {
        DispatchQueue.main.async {
            self.currentLiveHint = nil
            self.liveHintShownAt = .distantPast
            self.liveHintExpiresAt = .distantPast
            self.lastLiveMotionBecameUnstableAt = nil
            self.currentDemoOverlayAnnotations = []
            self.demoSubjectTrack = nil
            self.currentOverlayAnnotations = []
        }
        currentLiveFusionTraceBundle = nil
    }

    // Полный прогон heavy‑модулей на последнем кадре; возвращает legacy suggestions + structured pause critique.
    func runPauseAnalysis(completion: @escaping ([Suggestion], PauseCritiquePresentation?) -> Void) {
        guard let pixelBuffer = lastPixelBuffer else {
            completion([], nil)
            return
        }
        pauseReasoningTask?.cancel()
        pauseReasoningTask = nil
        lastRefinedPauseFrameId = nil
        currentPauseTraceBundle = nil
        let revision = featureQueue.sync { () -> Int in
            pauseAnalysisRevision += 1
            return pauseAnalysisRevision
        }
        let analysisCapturedAt = Date()
        let pauseSourceFrameId = currentSourceFrameId(fallbackDate: analysisCapturedAt)
        let orientation = lastOrientation
        let sendablePixelBuffer = SendablePixelBuffer(value: pixelBuffer)
        let baseAdapterState = currentAdapterState()
        lowQueue.async { [weak self] in
            guard let self else { return }
            let pauseStateQueue = DispatchQueue(label: "AnalysisPipeline.pauseState")
            var localFeatures = baseAdapterState.features
            var localDebugData = baseAdapterState.debugData
            var pauseDetectionsOverride: [DETRDetection]?
            var pauseDetectionsMeasuredAt: Date?
            var pauseAestheticScoreOverride: Double?
            var pauseAestheticMeasuredAt: Date?
            let shouldUpdateLegacySubjectFromDetr = localFeatures.composition.subjectAreaRatio == 0
            let technicalQualitySignal = self.technicalQualityAnalyzer.signal(pixelBuffer: pixelBuffer)

            let group = DispatchGroup()

            // Для pause structured path всегда считаем свежий local DETR, но не мутируем shared live-state.
            if let detector = self.detrDetector {
                group.enter()
                detector.detect(pixelBuffer: pixelBuffer, orientation: orientation) { detections in
                    pauseStateQueue.sync {
                        let measuredAt = Date()
                        pauseDetectionsOverride = detections
                        pauseDetectionsMeasuredAt = measuredAt
                        localDebugData.detrDetections = detections
                        localDebugData.detrMeasuredAt = measuredAt
                        if shouldUpdateLegacySubjectFromDetr,
                           let top = self.compositionPriorityDetections(detections).first {
                            localFeatures.composition = self.compositionFeatures(from: top.boundingBox)
                            localFeatures.composition.subjectAreaRatio = top.boundingBox.width * top.boundingBox.height
                            localFeatures.subject.objectName = top.label
                            localFeatures.subject.isFace = (top.label.lowercased() == "person")
                            localFeatures.subject.isPerson = (top.label.lowercased() == "person")
                            localFeatures.subject.count = detections.count
                        } else if shouldUpdateLegacySubjectFromDetr {
                            localFeatures.subject.objectName = nil
                            localFeatures.subject.isFace = false
                            localFeatures.subject.isPerson = false
                            localFeatures.subject.count = 0
                        }
                    }
                    group.leave()
                }
            }

            // Эстетика (off‑by‑default в live, но в preview считаем)
            group.enter()
            self.aestheticScorer.score(pixelBuffer: pixelBuffer, orientation: orientation) { score in
                pauseStateQueue.sync {
                    if let score {
                        let measuredAt = Date()
                        pauseAestheticScoreOverride = score
                        pauseAestheticMeasuredAt = measuredAt
                        localFeatures.aestheticScore = CGFloat(score)
                    }
                }
                group.leave()
            }

            group.notify(queue: .main) {
                Task { @MainActor [weak self] in
                    guard let self else { return }

                    let isCurrentRevision = self.featureQueue.sync { self.pauseAnalysisRevision == revision }
                    guard isCurrentRevision else { return }

                    let pauseFeatures = pauseStateQueue.sync { localFeatures }
                    let pauseDebugData = pauseStateQueue.sync { localDebugData }
                    let pauseDetections = pauseStateQueue.sync { pauseDetectionsOverride }
                    let pauseDetectionsMeasuredAt = pauseStateQueue.sync { pauseDetectionsMeasuredAt }
                    let pauseAestheticScore = pauseStateQueue.sync { pauseAestheticScoreOverride }
                    let pauseAestheticMeasuredAt = pauseStateQueue.sync { pauseAestheticMeasuredAt }

                    let list = self.suggestionEngine.rankedSuggestions(from: pauseFeatures, topN: 6)
                    let pauseAdapterState = PipelineFeatureSnapshotAdapterState(
                        features: pauseFeatures,
                        debugData: pauseDebugData,
                        vision: baseAdapterState.vision,
                        horizonMeasuredAt: baseAdapterState.horizonMeasuredAt,
                        horizon: baseAdapterState.horizon,
                        lightingMeasuredAt: baseAdapterState.lightingMeasuredAt,
                        lighting: baseAdapterState.lighting,
                        detr: pauseDetections.map {
                            self.makeDetrFeatureSample(from: $0, measuredAt: pauseDetectionsMeasuredAt ?? analysisCapturedAt)
                        } ?? baseAdapterState.detr,
                        aestheticMeasuredAt: pauseAestheticScore.map { _ in pauseAestheticMeasuredAt ?? analysisCapturedAt } ?? baseAdapterState.aestheticMeasuredAt,
                        aesthetic: pauseAestheticScore.map {
                            self.makeAestheticFeatureSample(score10: $0, measuredAt: pauseAestheticMeasuredAt ?? analysisCapturedAt)
                        } ?? baseAdapterState.aesthetic
                    )
                    let snapshot = self.makeFeatureSnapshot(
                        mode: .pause,
                        frameId: pauseSourceFrameId,
                        capturedAt: analysisCapturedAt,
                        adapterState: pauseAdapterState
                    )
                    let semantics = self.sceneSemanticsAnalyzer.analyze(snapshot: snapshot)
                    let deterministicCritique = self.frameCritiqueEngine.analyze(snapshot: snapshot, semantics: semantics)
                    let (fusionOutput, pauseNeuralOutcome) = await self.resolveCritiqueWithHybridFusion(
                        mode: .pause,
                        capturedAt: analysisCapturedAt,
                        pixelBuffer: sendablePixelBuffer.value,
                        orientation: orientation,
                        snapshot: snapshot,
                        semantics: semantics,
                        deterministicCritique: deterministicCritique,
                        forcePauseExecution: true
                    )
                    let stillCurrentRevision = self.featureQueue.sync { self.pauseAnalysisRevision == revision }
                    guard stillCurrentRevision else { return }

                    let critique = fusionOutput.critique
                    let plan = self.recommendationPlanner.makePlan(snapshot: snapshot, critique: critique)
                    let visualEvidenceResult = await self.resolvePauseVisualEvidence(
                        snapshot: snapshot,
                        semantics: semantics,
                        critique: critique,
                        plan: plan,
                        neuralOutcome: pauseNeuralOutcome
                    )
                    let stillCurrentAfterEvidence = self.featureQueue.sync { self.pauseAnalysisRevision == revision }
                    guard stillCurrentAfterEvidence else { return }
                    let validatedVisualEvidence = self.logAndExtractValidatedVisualEvidence(
                        visualEvidenceResult,
                        frameId: snapshot.frameId
                    )
                    let semanticTips = self.semanticTipPlanner.plan(
                        input: SemanticTipPlannerInput(
                            frameId: snapshot.frameId,
                            mode: .pause,
                            critique: critique,
                            recommendationPlan: plan,
                            semantics: semantics,
                            validatedEvidence: validatedVisualEvidence
                        )
                    )
                    let structuredDecision = self.structuredPathDecision(
                        mode: .pause,
                        critique: critique,
                        plan: plan,
                        motionState: snapshot.motion.state
                    )
                    if let technicalPauseIssue = self.technicalPauseIssue(
                        signal: technicalQualitySignal,
                        snapshot: snapshot,
                        semantics: semantics,
                        semanticTips: semanticTips.pauseExpandedTips,
                        structuredAvailable: structuredDecision.isAvailable,
                        structuredVerdict: critique.verdict
                    ),
                       let technicalPauseCritique = self.makeTechnicalPauseCritiquePresentation(
                            frameId: snapshot.frameId,
                            issue: technicalPauseIssue,
                            signal: technicalQualitySignal,
                            snapshot: snapshot,
                            semantics: semantics
                       ) {
                        self.currentPauseTraceBundle = nil
                        self.currentPauseCritique = technicalPauseCritique
                        self.currentOverlayAnnotations = []
                        completion(list, technicalPauseCritique)
                        return
                    }

                    guard structuredDecision.isAvailable else {
                        let fallbackAnnotations = self.makeOverlayAnnotations(
                            frameId: snapshot.frameId,
                            critique: critique,
                            plan: plan,
                            features: pauseFeatures,
                            mode: .pause,
                            legacySuggestions: list,
                            forceLegacyOnly: true
                        )
                        self.currentPauseCritique = nil
                        self.currentOverlayAnnotations = fallbackAnnotations
                        self.currentPauseTraceBundle = nil
                        completion(list, nil)
                        return
                    }

                    let pauseCritique = self.makePauseCritiquePresentation(
                        critique: critique,
                        plan: plan,
                        semanticTips: semanticTips.pauseExpandedTips,
                        semanticFallbackUsed: semanticTips.fallbackUsed,
                        snapshot: snapshot,
                        semantics: semantics,
                        technicalQualitySignal: technicalQualitySignal
                    )
                    let pauseTrace = self.makePauseTraceBundle(
                        critique: critique,
                        plan: plan,
                        neuralSnapshot: self.executedNeuralSnapshot(from: pauseNeuralOutcome),
                        fusionOutput: fusionOutput
                    )
                    self.currentPauseTraceBundle = pauseTrace
                    self.currentPauseCritique = pauseCritique
                    let pauseAnnotations = self.makeOverlayAnnotations(
                        frameId: snapshot.frameId,
                        critique: critique,
                        plan: plan,
                        features: pauseFeatures,
                        mode: .pause,
                        legacySuggestions: list
                    )
                    self.currentOverlayAnnotations = pauseAnnotations
                    completion(list, pauseCritique)

                    let reasoningRequest = self.makePauseReasoningRequest(
                        frameId: snapshot.frameId,
                        critique: critique,
                        plan: plan,
                        pauseDraft: pauseCritique,
                        trace: pauseTrace
                    )
                    self.schedulePauseReasoningRefinement(request: reasoningRequest, revision: revision)
                }
            }
        }
    }

    // Совместимость с legacy API.
    func runPreviewAnalysis(completion: @escaping ([Suggestion]) -> Void) {
        runPauseAnalysis { suggestions, _ in
            completion(suggestions)
        }
    }

    private func makeLiveHintPresentation(frameId: String,
                                          critique: CritiqueReport,
                                          plan: RecommendationPlan,
                                          semanticTip: SemanticTipCandidate?,
                                          semanticFallbackUsed: Bool,
                                          legacySuggestion: Suggestion?,
                                          forceLegacyFallback: Bool,
                                          technicalQualitySignal: TechnicalQualitySignal = .empty,
                                          snapshot: FrameFeatureSnapshot? = nil,
                                          semantics: SceneSemanticsReport? = nil,
                                          allowsAmbiguousTechnicalSilenceLowConfidence: Bool = true) -> LiveHintPresentation? {
        let fallbackUsed = critique.fallbackUsed || semanticFallbackUsed
        if !shouldPreserveCinematicGoodFrameOverTechnicalSignal(
            signal: technicalQualitySignal,
            snapshot: snapshot,
            semantics: semantics,
            structuredVerdict: critique.verdict
        ),
           let technicalHint = makeTechnicalLiveHintPresentation(
            frameId: frameId,
            signal: technicalQualitySignal,
            snapshot: snapshot,
            semantics: semantics,
            allowsAmbiguousTechnicalSilenceLowConfidence: allowsAmbiguousTechnicalSilenceLowConfidence
        ) {
            return technicalHint
        }

        if forceLegacyFallback {
            return makeLegacyLiveHint(
                frameId: frameId,
                critique: critique,
                plan: plan,
                legacySuggestion: legacySuggestion
            )
        }

        if let semanticTip,
           let linkedAction = linkedAction(for: semanticTip, plan: plan),
           isLiveWorthySemanticTip(
                semanticTip,
                linkedAction: linkedAction,
                critique: critique,
                plan: plan,
                snapshot: snapshot,
                semantics: semantics,
                fallbackUsed: fallbackUsed
           ) {
            let targetRegion = linkedAction.targetRegion ?? firstIssueRegion(linkedIssueIds: semanticTip.linkedIssueIds, critique: critique)
            return LiveHintPresentation(
                id: "lh_live_sem_\(semanticTipPlanner.stableKey(for: semanticTip))",
                frameId: frameId,
                text: semanticTip.liveText,
                confidence: liveActionConfidence(for: linkedAction, plan: plan, critique: critique),
                actionType: linkedAction.actionType,
                actionId: linkedAction.id,
                linkedIssueIds: semanticTip.linkedIssueIds,
                summaryId: semanticTip.summaryId ?? critique.summary.id,
                traceRootIds: semanticTip.linkedTraceIds,
                targetRegion: targetRegion,
                overlayHint: linkedAction.overlayHint,
                isFallback: fallbackUsed,
                expandedVerdict: makeLiveExpandedVerdictPresentation(
                    critique: critique,
                    plan: plan,
                    semanticTip: semanticTip,
                    primaryText: semanticTip.liveText,
                    fallbackUsed: fallbackUsed
                )
            )
        }

        if let correction = contextualSemanticCorrection(
            snapshot: snapshot,
            semantics: semantics,
            critique: critique,
            technicalQualitySignal: technicalQualitySignal
        ),
           isLiveWorthyContextualCorrection(correction) {
            return LiveHintPresentation(
                id: "lh_live_contextual_\(correction.idSuffix)",
                frameId: frameId,
                text: correction.liveText,
                confidence: correction.confidence,
                actionType: correction.liveActionType,
                actionId: nil,
                linkedIssueIds: [],
                summaryId: correction.traceId,
                traceRootIds: [correction.traceId],
                targetRegion: nil,
                overlayHint: nil,
                isFallback: fallbackUsed,
                expandedVerdict: LiveExpandedVerdictPresentation(
                    shortVerdict: correction.pauseSummary,
                    supportingText: correction.whyProblematic,
                    actionText: correction.pauseActionText,
                    fallbackUsed: fallbackUsed
                )
            )
        }

        if let semanticTip,
           critique.verdict == .good,
           shouldShowLivePositiveConfirmation(
                critique: critique,
                plan: plan,
                snapshot: snapshot,
                semantics: semantics
           ) {
            return LiveHintPresentation(
                id: "lh_live_sem_\(semanticTipPlanner.stableKey(for: semanticTip))",
                frameId: frameId,
                text: semanticTip.liveText,
                confidence: livePositiveConfidence(plan: plan, critique: critique),
                actionType: .leaveFrameAsIs,
                actionId: nil,
                linkedIssueIds: [],
                summaryId: semanticTip.summaryId ?? critique.summary.id,
                traceRootIds: semanticTip.linkedTraceIds,
                targetRegion: nil,
                overlayHint: nil,
                isFallback: fallbackUsed,
                expandedVerdict: makeLiveExpandedVerdictPresentation(
                    critique: critique,
                    plan: plan,
                    semanticTip: semanticTip,
                    primaryText: semanticTip.liveText,
                    fallbackUsed: fallbackUsed
                )
            )
        }

        if let primaryAction = plan.primaryAction,
           isLiveWorthyPrimaryAction(
                primaryAction,
                critique: critique,
                plan: plan,
                snapshot: snapshot,
                semantics: semantics
           ) {
            let linkedIssueTypes = critique.issues
                .filter { primaryAction.linkedIssueIds.contains($0.id) }
                .map(\.type.rawValue)
                .sorted()
                .joined(separator: "+")
            let issueSignature = linkedIssueTypes.isEmpty ? "none" : linkedIssueTypes
            let targetRegion = primaryAction.targetRegion ?? firstIssueRegion(linkedIssueIds: primaryAction.linkedIssueIds, critique: critique)
            let id = "lh_live_action_\(primaryAction.actionType.rawValue)_\(issueSignature)_\(quantizedRegionKey(for: targetRegion))"
            let text = nonEmpty(primaryAction.expectedOutcome) ?? critique.summary.shortVerdict
            return LiveHintPresentation(
                id: id,
                frameId: frameId,
                text: text,
                confidence: liveActionConfidence(for: primaryAction, plan: plan, critique: critique),
                actionType: primaryAction.actionType,
                actionId: primaryAction.id,
                linkedIssueIds: primaryAction.linkedIssueIds,
                summaryId: critique.summary.id,
                traceRootIds: critique.traceRefs,
                targetRegion: targetRegion,
                overlayHint: primaryAction.overlayHint,
                isFallback: fallbackUsed,
                expandedVerdict: makeLiveExpandedVerdictPresentation(
                    critique: critique,
                    plan: plan,
                    semanticTip: nil,
                    primaryText: text,
                    fallbackUsed: fallbackUsed
                )
            )
        }

        if critique.verdict == .good,
           shouldShowLivePositiveConfirmation(
                critique: critique,
                plan: plan,
                snapshot: snapshot,
                semantics: semantics
           ) {
            let strengthTypes = critique.strengths.prefix(3).map(\.type.rawValue).sorted().joined(separator: "+")
            let normalizedSummary = normalizeSummaryKey(critique.summary.shortVerdict)
            let id = "lh_live_summary_\(normalizedSummary)_\(strengthTypes.isEmpty ? "none" : strengthTypes)"
            let noChangeText = nonEmpty(plan.noChangeRationale) ?? critique.summary.shortVerdict
            return LiveHintPresentation(
                id: id,
                frameId: frameId,
                text: noChangeText,
                confidence: livePositiveConfidence(plan: plan, critique: critique),
                actionType: .leaveFrameAsIs,
                actionId: nil,
                linkedIssueIds: [],
                summaryId: critique.summary.id,
                traceRootIds: critique.traceRefs,
                targetRegion: nil,
                overlayHint: nil,
                isFallback: fallbackUsed,
                expandedVerdict: makeLiveExpandedVerdictPresentation(
                    critique: critique,
                    plan: plan,
                    semanticTip: nil,
                    primaryText: noChangeText,
                    fallbackUsed: fallbackUsed
                )
            )
        }

        return makeLegacyLiveHint(
            frameId: frameId,
            critique: critique,
            plan: plan,
            legacySuggestion: legacySuggestion
        )
    }

    private func isLiveWorthySemanticTip(_ semanticTip: SemanticTipCandidate,
                                         linkedAction: RecommendationAction,
                                         critique: CritiqueReport,
                                         plan: RecommendationPlan,
                                         snapshot: FrameFeatureSnapshot?,
                                         semantics: SceneSemanticsReport?,
                                         fallbackUsed: Bool) -> Bool {
        guard isAllowedDemoLiveSemanticAction(semanticTip.actionType) else { return false }

        switch semanticTip.priorityBand {
        case .primaryCorrective:
            if fallbackUsed && !isStableLiveAction(linkedAction.actionType) {
                return false
            }
            return isLiveWorthyPrimaryAction(
                linkedAction,
                critique: critique,
                plan: plan,
                snapshot: snapshot,
                semantics: semantics
            )
        case .positiveConfirmation:
            return shouldShowLivePositiveConfirmation(
                critique: critique,
                plan: plan,
                snapshot: snapshot,
                semantics: semantics
            )
        case .timingCorrective:
            guard !fallbackUsed,
                  plan.planConfidence >= 0.70,
                  critique.verdictConfidence >= 0.64 else { return false }
            return strongestIssueScore(for: linkedAction, critique: critique) >= 0.70
        case .secondaryCorrective, .contextualCorrective:
            guard !fallbackUsed,
                  plan.planConfidence >= 0.74,
                  critique.verdictConfidence >= 0.66 else { return false }
            return strongestIssueScore(for: linkedAction, critique: critique) >= 0.76
        }
    }

    private func isLiveWorthyPrimaryAction(_ action: RecommendationAction,
                                           critique: CritiqueReport,
                                           plan: RecommendationPlan,
                                           snapshot: FrameFeatureSnapshot? = nil,
                                           semantics: SceneSemanticsReport? = nil) -> Bool {
        if action.actionType == .leaveFrameAsIs {
            return shouldShowLivePositiveConfirmation(
                critique: critique,
                plan: plan,
                snapshot: snapshot,
                semantics: semantics
            )
        }

        guard isAllowedDemoLiveSemanticAction(action.actionType.semanticActionType) else {
            return false
        }

        guard critique.verdict != .good,
              plan.planConfidence >= 0.70,
              critique.verdictConfidence >= 0.64 else {
            return false
        }

        let issueScore = strongestIssueScore(for: action, critique: critique)
        switch action.actionType {
        case .improveFrontLight, .levelHorizon:
            return issueScore >= 0.68
        case .moveFrameLeft, .moveFrameRight, .moveFrameUp, .moveFrameDown:
            return issueScore >= 0.84 && plan.planConfidence >= 0.76
        case .increaseSubjectSize, .reduceBackgroundDistractions, .changeAngle:
            return issueScore >= 0.90 && plan.planConfidence >= 0.82
        case .leaveFrameAsIs:
            return shouldShowLivePositiveConfirmation(
                critique: critique,
                plan: plan,
                snapshot: snapshot,
                semantics: semantics
            )
        }
    }

    private func isStableLiveAction(_ actionType: ActionTypeV1) -> Bool {
        actionType == .improveFrontLight || actionType == .levelHorizon || actionType == .leaveFrameAsIs
    }

    private func isLiveWorthyContextualCorrection(_ correction: ContextualSemanticCorrection) -> Bool {
        guard correction.semanticActionTypes.allSatisfy(isAllowedDemoLiveSemanticAction) else {
            return false
        }
        guard let liveActionType = correction.liveActionType else { return true }
        return isAllowedDemoLiveSemanticAction(liveActionType.semanticActionType)
    }

    private func isAllowedDemoLiveSemanticAction(_ actionType: SemanticActionType) -> Bool {
        Self.demoLiveSemanticActionIds.contains(actionType.rawValue)
    }

    private static let demoLiveSemanticActionIds: Set<String> = [
        SemanticActionType.keepCurrentSetup.rawValue,
        SemanticActionType.simplifyBackground.rawValue,
        SemanticActionType.waitForBackgroundClearance.rawValue,
        SemanticActionType.stepBack.rawValue,
        SemanticActionType.stepCloser.rawValue,
        SemanticActionType.addFrontFillLight.rawValue,
        SemanticActionType.removeBackgroundHotspot.rawValue,
        SemanticActionType.levelHorizon.rawValue,
    ]

    private func strongestIssueScore(for action: RecommendationAction,
                                     critique: CritiqueReport) -> Double {
        let linkedIssues = critique.issues.filter { action.linkedIssueIds.contains($0.id) }
        let scopedIssues = linkedIssues.isEmpty ? critique.issues : linkedIssues
        return scopedIssues
            .map { issue in
                (issue.severity * 0.65) + (issue.confidence * 0.35)
            }
            .max() ?? 0
    }

    private func shouldShowLivePositiveConfirmation(critique: CritiqueReport,
                                                    plan: RecommendationPlan,
                                                    snapshot: FrameFeatureSnapshot? = nil,
                                                    semantics: SceneSemanticsReport? = nil) -> Bool {
        guard critique.verdict == .good,
              critique.verdictConfidence >= 0.76,
              plan.planConfidence >= 0.72 else {
            return false
        }

        guard snapshot != nil || semantics != nil else {
            return true
        }

        let hasGrounding = hasGroundedLiveSubjectEvidence(snapshot: snapshot, semantics: semantics)
        if !hasGrounding {
            let semanticSubject = debugPrimarySubject(semantics?.primarySubject)
            let snapshotRegion = debugRegion(snapshot?.subjectSignals.primaryCandidateRegion)
            let snapshotConfidence = debugDouble(snapshot?.subjectSignals.primaryCandidateConfidence)
            let parts = [
                "[CA_DEBUG][LIVE_POSITIVE_GATE]",
                "blocked=no_grounded_subject",
                "verdict=\(critique.verdict.rawValue)",
                "verdictConf=\(debugDouble(critique.verdictConfidence))",
                "planConf=\(debugDouble(plan.planConfidence))",
                "semanticSubject=\(semanticSubject)",
                "snapshotRegion=\(snapshotRegion)",
                "snapshotConf=\(snapshotConfidence)"
            ]
            print(parts.joined(separator: " "))
        }
        return hasGrounding
    }

    private func hasGroundedLiveSubjectEvidence(snapshot: FrameFeatureSnapshot?,
                                                semantics: SceneSemanticsReport?) -> Bool {
        if let primarySubject = semantics?.primarySubject,
           primarySubject.kind != .unknown,
           primarySubject.confidence >= 0.35,
           let region = primarySubject.region,
           !region.isDegenerate {
            return true
        }

        guard let snapshot else { return false }
        if let region = snapshot.subjectSignals.primaryCandidateRegion,
           !region.isDegenerate,
           (snapshot.subjectSignals.primaryCandidateConfidence ?? 0) >= 0.20 {
            return true
        }

        return false
    }

    private func liveActionConfidence(for action: RecommendationAction,
                                      plan: RecommendationPlan,
                                      critique: CritiqueReport) -> Double {
        min(critique.verdictConfidence, pauseActionConfidence(for: action, plan: plan, critique: critique))
    }

    private func livePositiveConfidence(plan: RecommendationPlan,
                                        critique: CritiqueReport) -> Double {
        min(plan.planConfidence, critique.verdictConfidence)
    }

    @MainActor
    private func logLiveHintDecision(candidate: LiveHintPresentation?,
                                     legacySuggestion: Suggestion?,
                                     semanticTip: SemanticTipCandidate?,
                                     structuredAvailable: Bool,
                                     critique: CritiqueReport,
                                     plan: RecommendationPlan) {
        liveHintDecisionLogCounter += 1
        let candidateKey = candidate?.id ?? "none"
        let legacyKey = legacySuggestion.map { "\($0.type):\($0.text)" } ?? "none"
        let semanticKey = semanticTip.map { semanticTipPlanner.stableKey(for: $0) } ?? "none"
        let primaryActionKey = plan.primaryAction?.actionType.rawValue ?? "none"
        let logKey = [
            candidateKey,
            legacyKey,
            semanticKey,
            primaryActionKey,
            "\(structuredAvailable)"
        ].joined(separator: "|")

        guard logKey != lastLiveHintDecisionLogKey || liveHintDecisionLogCounter % 20 == 0 else { return }
        lastLiveHintDecisionLogKey = logKey

        let parts = [
            "[CA_DEBUG][LIVE_HINT_SELECTED]",
            "selected=\(debugText(candidate?.text))",
            "legacy=\(legacyKey)",
            "semantic=\(semanticKey)",
            "structured=\(structuredAvailable)",
            "verdict=\(critique.verdict.rawValue)",
            "conf=\(debugDouble(critique.verdictConfidence))",
            "plan=\(debugDouble(plan.planConfidence))",
            "action=\(primaryActionKey)"
        ]
        print(parts.joined(separator: " "))

        guard CameraLog.liveHintDecisions else { return }
        os_log(
            "💬 LiveHint decision selected=%{public}@ legacy=%{public}@ semantic=%{public}@ structured=%{public}@ verdict=%{public}@ conf=%.2f plan=%.2f action=%{public}@",
            log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
            type: .info,
            candidate?.text ?? "none",
            legacyKey,
            semanticKey,
            String(structuredAvailable),
            critique.verdict.rawValue,
            critique.verdictConfidence,
            plan.planConfidence,
            primaryActionKey
        )
    }

    private func logHighFrameDebug(context: FrameContext,
                                   sourceFrameId: String,
                                   trackingResult: VisionTrackingResult,
                                   primarySubject: TrackedSubject?,
                                   horizon: (angle: CGFloat, confidence: CGFloat),
                                   saliencyBalance: CGFloat,
                                   visionLatency: TimeInterval,
                                   horizonLatency: TimeInterval) {
        let timestamp = CMTimeGetSeconds(context.timestamp)
        guard timestamp.isFinite else { return }
        guard timestamp - lastHighCameraDebugTimestamp >= 0.5 else { return }
        lastHighCameraDebugTimestamp = timestamp

        let parts = [
            "[CA_DEBUG][PIPE_HIGH]",
            "frame=\(sourceFrameId)",
            "ts=\(debugDouble(timestamp))",
            "image=\(debugPixelBufferSize(context.pixelBuffer))",
            "orientation=\(debugCGOrientationDescription(context.orientation))",
            "stable=\(context.isStable)",
            "motion=\(String(describing: context.motionState))",
            "shake=\(debugDouble(context.shakeLevel))",
            "visionSubjects=\(debugTrackedSubjects(trackingResult.subjects))",
            "faces=\(trackingResult.faceCount)",
            "persons=\(trackingResult.personCount)",
            "primary=\(debugTrackedSubject(primarySubject))",
            "saliency=\(debugPoint(trackingResult.saliencyCenter))",
            "saliencyRegion=\(debugRect(trackingResult.saliencyRegion))",
            "saliencyBalance=\(debugDouble(saliencyBalance))",
            "horizon=\(debugDouble(horizon.angle))",
            "horizonConf=\(debugDouble(horizon.confidence))",
            "visionMs=\(debugDouble(visionLatency * 1000))",
            "horizonMs=\(debugDouble(horizonLatency * 1000))"
        ]
        print(parts.joined(separator: " "))
    }

    @MainActor
    private func printLiveDecisionDebug(candidate: LiveHintPresentation?,
                                        frameId: String,
                                        critique: CritiqueReport,
                                        plan: RecommendationPlan,
                                        snapshot: FrameFeatureSnapshot,
                                        semantics: SceneSemanticsReport,
                                        semanticTip: SemanticTipCandidate?,
                                        legacySuggestion: Suggestion?,
                                        structuredAvailable: Bool,
                                        technicalQualitySignal: TechnicalQualitySignal) {
        let semanticKey = semanticTip.map { semanticTipPlanner.stableKey(for: $0) } ?? "none"
        let candidateId = candidate?.id ?? "none"
        let candidateAction = candidate?.actionType?.rawValue ?? "none"
        let primaryAction = plan.primaryAction?.actionType.rawValue ?? "none"
        let decisionKey = [
            candidateId,
            candidateAction,
            critique.verdict.rawValue,
            primaryAction,
            semanticKey,
            structuredAvailable ? "structured" : "legacy",
            critique.issues.first?.type.rawValue ?? "no_issue"
        ].joined(separator: "|")
        let now = CACurrentMediaTime()
        guard decisionKey != lastLiveDecisionDebugLogKey ||
                now - lastLiveDecisionDebugLogTimestamp >= 1.0 else {
            return
        }
        lastLiveDecisionDebugLogKey = decisionKey
        lastLiveDecisionDebugLogTimestamp = now

        let issueTypes = critique.issues.prefix(4).map(\.type.rawValue).joined(separator: ",")
        let strengthTypes = critique.strengths.prefix(4).map(\.type.rawValue).joined(separator: ",")
        let semanticAction = semanticTip?.actionType.rawValue ?? "none"
        let semanticGrounding = semanticTip?.targetEntityGroundingConfidence.map { debugDouble($0) } ?? "nil"
        let technicalActions = technicalQualitySignal.futureActionIds.joined(separator: ",")
        let candidateText = debugText(candidate?.text)
        let candidateTarget = debugRegion(candidate?.targetRegion)
        let candidateConfidence = debugDouble(candidate?.confidence)
        let legacyKey = legacySuggestion.map { "\($0.type):\($0.text)" } ?? "none"
        let primarySubject = debugPrimarySubject(semantics.primarySubject)
        let snapshotRegion = debugRegion(snapshot.subjectSignals.primaryCandidateRegion)
        let snapshotConfidence = debugDouble(snapshot.subjectSignals.primaryCandidateConfidence)
        let topObject = "\(snapshot.subjectSignals.topObjectLabel ?? "nil"):\(debugDouble(snapshot.subjectSignals.topObjectConfidence))"
        let sourceStatus = debugSources(snapshot.sources)
        let issues = issueTypes.isEmpty ? "none" : issueTypes
        let strengths = strengthTypes.isEmpty ? "none" : strengthTypes
        let technical = technicalActions.isEmpty ? "none" : technicalActions
        let parts = [
            "[CA_DEBUG][LIVE_DECISION]",
            "frame=\(frameId)",
            "shown=\(candidate != nil)",
            "text=\(candidateText)",
            "id=\(candidateId)",
            "action=\(candidateAction)",
            "target=\(candidateTarget)",
            "confidence=\(candidateConfidence)",
            "verdict=\(critique.verdict.rawValue)",
            "verdictConf=\(debugDouble(critique.verdictConfidence))",
            "planConf=\(debugDouble(plan.planConfidence))",
            "primaryAction=\(primaryAction)",
            "structured=\(structuredAvailable)",
            "semantic=\(semanticKey)",
            "semanticAction=\(semanticAction)",
            "semanticGround=\(semanticGrounding)",
            "legacy=\(legacyKey)",
            "subject=\(primarySubject)",
            "scene=\(semantics.sceneType.rawValue)",
            "readable=\(semantics.readability.subjectReadable)",
            "clearFocus=\(semantics.dominance.hasClearFocus)",
            "snapshotRegion=\(snapshotRegion)",
            "snapshotConf=\(snapshotConfidence)",
            "topObject=\(topObject)",
            "objects=\(snapshot.objects.totalCount)",
            "sources=\(sourceStatus)",
            "issues=\(issues)",
            "strengths=\(strengths)",
            "technical=\(technical)"
        ]
        print(parts.joined(separator: " "))
    }

    private func debugTrackedSubjects(_ subjects: [TrackedSubject]) -> String {
        guard !subjects.isEmpty else { return "none" }
        return subjects
            .prefix(5)
            .map { debugTrackedSubject($0) }
            .joined(separator: ";")
    }

    private func debugTrackedSubject(_ subject: TrackedSubject?) -> String {
        guard let subject else { return "nil" }
        let kind = subject.isFace ? "face" : "person"
        return "\(kind):\(debugDouble(Double(subject.confidence)))@\(debugRect(subject.boundingBox))"
    }

    private func debugDetections(_ detections: [DETRDetection], limit: Int = 5) -> String {
        guard !detections.isEmpty else { return "total=0" }
        let rendered = detections
            .sorted { $0.confidence > $1.confidence }
            .prefix(limit)
            .map { debugDetection($0) }
            .joined(separator: ";")
        let suffix = detections.count > limit ? ";..." : ""
        return "total=\(detections.count) top=\(rendered)\(suffix)"
    }

    private func debugDetection(_ detection: DETRDetection?) -> String {
        guard let detection else { return "nil" }
        return "\(detection.label):\(debugDouble(Double(detection.confidence)))@\(debugRect(detection.boundingBox))"
    }

    private func debugPrimarySubject(_ subject: SceneSemanticsReport.PrimarySubject?) -> String {
        guard let subject else { return "nil" }
        let label = subject.label ?? "nil"
        return "\(subject.kind.rawValue):\(label):\(debugDouble(subject.confidence))@\(debugRegion(subject.region))"
    }

    private func debugSources(_ sources: FeatureSourceStatus) -> String {
        [
            "vision=\(debugSourceState(sources.vision))",
            "detr=\(debugSourceState(sources.detr))",
            "horizon=\(debugSourceState(sources.horizon))",
            "lighting=\(debugSourceState(sources.lighting))",
            "aesthetic=\(debugSourceState(sources.aesthetic))"
        ].joined(separator: ",")
    }

    private func debugSourceState(_ state: SourceState) -> String {
        let available = state.available ? "1" : "0"
        let freshness = state.freshnessMs.map { "\($0)ms" } ?? "nil"
        let confidence = debugDouble(state.confidence)
        return "\(available)/\(freshness)/\(confidence)"
    }

    private func debugRect(_ rect: CGRect?) -> String {
        guard let rect else { return "nil" }
        return "[x=\(debugDouble(rect.minX)) y=\(debugDouble(rect.minY)) w=\(debugDouble(rect.width)) h=\(debugDouble(rect.height))]"
    }

    private func debugRegion(_ region: NormalizedRect?) -> String {
        guard let region else { return "nil" }
        return "[x=\(debugDouble(region.x)) y=\(debugDouble(region.y)) w=\(debugDouble(region.width)) h=\(debugDouble(region.height))]"
    }

    private func debugPoint(_ point: CGPoint?) -> String {
        guard let point else { return "nil" }
        return "[x=\(debugDouble(point.x)) y=\(debugDouble(point.y))]"
    }

    private func debugPixelBufferSize(_ pixelBuffer: CVPixelBuffer) -> String {
        "\(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))"
    }

    private func debugCGOrientationDescription(_ orientation: CGImagePropertyOrientation) -> String {
        switch orientation {
        case .up:
            return "up"
        case .upMirrored:
            return "upMirrored"
        case .down:
            return "down"
        case .downMirrored:
            return "downMirrored"
        case .left:
            return "left"
        case .leftMirrored:
            return "leftMirrored"
        case .right:
            return "right"
        case .rightMirrored:
            return "rightMirrored"
        }
    }

    private func debugText(_ value: String?) -> String {
        guard let value else { return "none" }
        return value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }

    private func debugDouble(_ value: Double?) -> String {
        guard let value else { return "nil" }
        return debugDouble(value)
    }

    private func debugDouble(_ value: Double) -> String {
        guard value.isFinite else { return "nan" }
        return String(format: "%.3f", value)
    }

    private func debugDouble(_ value: CGFloat) -> String {
        debugDouble(Double(value))
    }

    private func makeLegacyLiveHint(frameId: String,
                                    critique: CritiqueReport,
                                    plan: RecommendationPlan,
                                    legacySuggestion: Suggestion?) -> LiveHintPresentation? {
        guard let legacySuggestion else { return nil }
        guard isLiveWorthyLegacySuggestion(legacySuggestion, critique: critique) else { return nil }
        let legacyActionType = legacyActionType(for: legacySuggestion, plan: plan)
        return LiveHintPresentation(
            id: "lh_live_legacy_\(legacySuggestion.type.rawValue)",
            frameId: frameId,
            text: legacySuggestion.text,
            confidence: confidenceForSuggestion(legacySuggestion),
            actionType: legacyActionType,
            actionId: legacyActionType.map { "legacy_\($0.rawValue)" },
            linkedIssueIds: [],
            summaryId: critique.summary.id,
            traceRootIds: critique.traceRefs,
            targetRegion: nil,
            overlayHint: nil,
            isFallback: true,
            expandedVerdict: makeLiveExpandedVerdictPresentation(
                critique: critique,
                plan: plan,
                semanticTip: nil,
                primaryText: legacySuggestion.text,
                fallbackUsed: true
            )
        )
    }

    private func isLiveWorthyLegacySuggestion(_ suggestion: Suggestion,
                                              critique: CritiqueReport) -> Bool {
        switch suggestion.type {
        case .horizon:
            return suggestion.priority == .critical &&
                critique.issues.contains {
                    $0.type == .horizonDistracts &&
                        $0.severity >= 0.55 &&
                        $0.confidence >= 0.55
                }
        case .exposure:
            return suggestion.priority == .critical &&
                critique.issues.contains {
                    $0.type == .backlightHidesSubject &&
                        $0.severity >= 0.60 &&
                        $0.confidence >= 0.50
                }
        case .lighting:
            return suggestion.priority != .optional
        case .composition:
            // Live composition advice is owned by the structured semantic path.
            // Legacy bbox heuristics are too noisy for portraits and demo framing.
            return false
        case .lens, .other:
            return false
        }
    }

    private func legacyActionType(for suggestion: Suggestion,
                                  plan: RecommendationPlan) -> ActionTypeV1? {
        switch suggestion.type {
        case .horizon:
            return .levelHorizon
        case .lighting:
            return .improveFrontLight
        case .composition:
            return plan.primaryAction?.actionType
        case .exposure, .lens, .other:
            return nil
        }
    }

    private func makeLiveExpandedVerdictPresentation(critique: CritiqueReport,
                                                     plan: RecommendationPlan,
                                                     semanticTip: SemanticTipCandidate?,
                                                     primaryText: String?,
                                                     fallbackUsed: Bool) -> LiveExpandedVerdictPresentation? {
        guard let shortVerdict = nonEmpty(critique.summary.shortVerdict) else { return nil }
        let primaryText = nonEmpty(primaryText)
        let supportingText: String?
        if critique.verdict == .good {
            supportingText = nonEmpty(critique.summary.whyGood)
                ?? critique.strengths.first.flatMap { nonEmpty($0.rationale) }
        } else {
            supportingText = nonEmpty(critique.summary.whyProblematic)
                ?? critique.issues.first.flatMap { nonEmpty($0.rationale) }
        }

        let actionCandidate: String?
        if let semanticTip {
            actionCandidate = nonEmpty(semanticTip.pauseText)
        } else if critique.verdict == .good {
            actionCandidate = nonEmpty(plan.noChangeRationale)
        } else {
            actionCandidate = plan.primaryAction.flatMap { action in
                guard action.actionType != .leaveFrameAsIs else { return nil }
                return nonEmpty(action.expectedOutcome)
            }
        }

        let actionText: String?
        if let actionCandidate, actionCandidate != primaryText {
            actionText = actionCandidate
        } else {
            actionText = nil
        }

        return LiveExpandedVerdictPresentation(
            shortVerdict: shortVerdict,
            supportingText: supportingText,
            actionText: actionText,
            fallbackUsed: fallbackUsed
        )
    }

    private func technicalQualitySignal(for pixelBuffer: CVPixelBuffer?) -> TechnicalQualitySignal {
        guard let pixelBuffer else { return .empty }
        return technicalQualityAnalyzer.signal(pixelBuffer: pixelBuffer)
    }

    private func dominantTechnicalQualityIssue(from signal: TechnicalQualitySignal) -> TechnicalQualityIssueSignal? {
        let candidates = signal.issues.filter { issue in
            issue.isDominant && max(issue.confidence, issue.severity) >= 0.55
        }
        guard !candidates.isEmpty else { return nil }
        if let dominantOverexposure = candidates.first(where: { issue in
            issue.type == .overexposure && issue.actionType == .reduceExposure
        }) {
            // Large bright regions can look low-texture; keep hotspot fixes from being masked as blur.
            return dominantOverexposure
        }

        let preferredOrder: [TechnicalQualityIssueType] = [
            .defocus,
            .motionBlur,
            .overexposure,
            .underexposure,
            .noise,
            .occlusion,
            .lensSmudge
        ]
        return candidates.sorted { lhs, rhs in
            let lhsScore = technicalQualityConfidence(for: lhs)
            let rhsScore = technicalQualityConfidence(for: rhs)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            let lhsOrder = preferredOrder.firstIndex(of: lhs.type) ?? preferredOrder.count
            let rhsOrder = preferredOrder.firstIndex(of: rhs.type) ?? preferredOrder.count
            return lhsOrder < rhsOrder
        }.first
    }

    private func makeTechnicalLiveHintPresentation(frameId: String,
                                                   signal: TechnicalQualitySignal,
                                                   snapshot: FrameFeatureSnapshot? = nil,
                                                   semantics: SceneSemanticsReport? = nil,
                                                   allowsAmbiguousTechnicalSilenceLowConfidence: Bool = true) -> LiveHintPresentation? {
        guard let issue = dominantTechnicalQualityIssue(from: signal) else { return nil }
        let confidence = technicalLiveConfidence(
            for: issue,
            signal: signal,
            snapshot: snapshot,
            semantics: semantics,
            allowsAmbiguousTechnicalSilenceLowConfidence: allowsAmbiguousTechnicalSilenceLowConfidence
        )
        let liveText = technicalLiveText(for: issue)
        return LiveHintPresentation(
            id: "lh_live_technical_\(issue.type.rawValue)",
            frameId: frameId,
            text: liveText,
            confidence: confidence,
            actionType: nil,
            actionId: nil,
            linkedIssueIds: [],
            summaryId: "technical_quality_\(issue.type.rawValue)",
            traceRootIds: ["technical_quality_\(issue.type.rawValue)"],
            targetRegion: nil,
            overlayHint: nil,
            isFallback: false,
            expandedVerdict: LiveExpandedVerdictPresentation(
                shortVerdict: technicalPauseSummary(for: issue),
                supportingText: technicalPauseWhyProblematic(for: issue),
                actionText: technicalPauseActionText(for: issue),
                fallbackUsed: false
            )
        )
    }

    private func technicalLiveConfidence(for issue: TechnicalQualityIssueSignal,
                                         signal: TechnicalQualitySignal = .empty,
                                         snapshot: FrameFeatureSnapshot? = nil,
                                         semantics: SceneSemanticsReport? = nil,
                                         allowsAmbiguousTechnicalSilenceLowConfidence: Bool = true) -> Double {
        let confidence = technicalQualityConfidence(for: issue)
        if shouldUseLowConfidenceForAmbiguousTechnicalSilence(
            issue: issue,
            signal: signal,
            snapshot: snapshot,
            semantics: semantics,
            isEnabled: allowsAmbiguousTechnicalSilenceLowConfidence
        ) {
            return min(0.44, confidence)
        }
        return issue.type == .underexposure ? min(0.74, confidence) : confidence
    }

    private func makeTechnicalPauseCritiquePresentation(frameId: String,
                                                        issue: TechnicalQualityIssueSignal,
                                                        signal: TechnicalQualitySignal = .empty,
                                                        snapshot: FrameFeatureSnapshot? = nil,
                                                        semantics: SceneSemanticsReport? = nil,
                                                        allowsAmbiguousTechnicalSilenceLowConfidence: Bool = true) -> PauseCritiquePresentation? {
        let traceId = "technical_quality_\(issue.type.rawValue)"
        return PauseCritiquePresentation(
            frameId: frameId,
            verdict: technicalPauseVerdict(for: issue),
            verdictConfidence: technicalPauseConfidence(
                for: issue,
                signal: signal,
                snapshot: snapshot,
                semantics: semantics,
                allowsAmbiguousTechnicalSilenceLowConfidence: allowsAmbiguousTechnicalSilenceLowConfidence
            ),
            summaryId: traceId,
            shortVerdict: technicalPauseSummary(for: issue),
            whyGood: nil,
            whyProblematic: technicalPauseWhyProblematic(for: issue),
            strengths: [],
            issues: [],
            actions: technicalPauseActions(
                for: issue,
                traceId: traceId,
                snapshot: snapshot,
                semantics: semantics
            ),
            noChangeRationale: nil,
            assumptions: [
                "Техническая проверка кадра обнаружила доминирующую проблему качества изображения до семантической оценки композиции."
            ],
            traceRootIds: [traceId],
            fallbackUsed: false
        )
    }

    private func technicalPauseVerdict(for issue: TechnicalQualityIssueSignal) -> FrameVerdict {
        issue.type == .underexposure ? .mixed : .needsFix
    }

    private func technicalPauseConfidence(for issue: TechnicalQualityIssueSignal,
                                          signal: TechnicalQualitySignal = .empty,
                                          snapshot: FrameFeatureSnapshot? = nil,
                                          semantics: SceneSemanticsReport? = nil,
                                          allowsAmbiguousTechnicalSilenceLowConfidence: Bool = true) -> Double {
        let confidence = technicalQualityConfidence(for: issue)
        if shouldUseLowConfidenceForAmbiguousTechnicalSilence(
            issue: issue,
            signal: signal,
            snapshot: snapshot,
            semantics: semantics,
            isEnabled: allowsAmbiguousTechnicalSilenceLowConfidence
        ) {
            return min(0.44, confidence)
        }
        return issue.type == .underexposure ? min(0.74, confidence) : confidence
    }

    private func shouldUseLowConfidenceForAmbiguousTechnicalSilence(issue: TechnicalQualityIssueSignal,
                                                                    signal: TechnicalQualitySignal,
                                                                    snapshot: FrameFeatureSnapshot?,
                                                                    semantics: SceneSemanticsReport?,
                                                                    isEnabled: Bool = true) -> Bool {
        guard isEnabled,
              issue.type == .motionBlur,
              let snapshot,
              let semantics,
              semantics.primarySubject.kind == .unknown,
              !semantics.readability.subjectReadable,
              snapshot.objects.totalCount == 0,
              snapshot.subjectSignals.personCount == 0 else {
            return false
        }

        let hasExposureCorrectionContext =
            signal.futureActionIds.contains(TechnicalQualityActionType.reduceExposure.rawValue) ||
            snapshot.lighting.exposureBiasHint >= 0.25
        return !hasExposureCorrectionContext
    }

    private func technicalPauseIssue(signal: TechnicalQualitySignal,
                                     snapshot: FrameFeatureSnapshot,
                                     semantics: SceneSemanticsReport,
                                     semanticTips: [SemanticTipCandidate],
                                     structuredAvailable: Bool,
                                     structuredVerdict: FrameVerdict) -> TechnicalQualityIssueSignal? {
        let issue = dominantTechnicalQualityIssue(from: signal)
            ?? contextualTechnicalPauseIssue(from: signal, snapshot: snapshot, semantics: semantics)
        guard let issue else { return nil }
        if shouldPreserveGoodFrameSemanticActions(
            snapshot: snapshot,
            semantics: semantics,
            verdict: structuredVerdict,
            technicalQualitySignal: signal,
            allowsMixedVerdict: true
        ) {
            return nil
        }
        if shouldPreserveCinematicGoodFrameOverTechnicalSignal(
            signal: signal,
            issue: issue,
            snapshot: snapshot,
            semantics: semantics,
            structuredVerdict: structuredVerdict
        ) {
            return nil
        }
        if shouldPreserveSemanticGoodVerdictOverTechnicalPauseIssue(
            issue: issue,
            snapshot: snapshot,
            structuredVerdict: structuredVerdict
        ) {
            return nil
        }
        guard structuredAvailable else { return issue }
        if issue.type == .overexposure && issue.actionType == .reduceExposure {
            return issue
        }
        return semanticTips.contains { $0.actionType != .keepCurrentSetup } ? nil : issue
    }

    private func shouldPreserveCinematicGoodFrameOverTechnicalSignal(signal: TechnicalQualitySignal,
                                                                     issue explicitIssue: TechnicalQualityIssueSignal? = nil,
                                                                     snapshot: FrameFeatureSnapshot?,
                                                                     semantics: SceneSemanticsReport?,
                                                                     structuredVerdict: FrameVerdict) -> Bool {
        guard structuredVerdict == .good,
              let snapshot,
              let semantics,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore >= 0.42 else {
            return false
        }

        let issue = explicitIssue ?? dominantTechnicalQualityIssue(from: signal)
        if issue?.type == .overexposure,
           shouldTreatOverexposureAsReadableHotspot(snapshot: snapshot, semantics: semantics) {
            return false
        }
        if shouldForceSemanticCorrectionOverCinematicPreservation(snapshot: snapshot, semantics: semantics) {
            return false
        }

        let isCleanUnknownEstablishing = shouldRespectCleanUnknownEstablishingFrame(
            snapshot: snapshot,
            semantics: semantics
        )

        let futureActions = Set(signal.futureActionIds)
        let hasHeavyReadableTechnicalPressure = futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue)
            && futureActions.contains(TechnicalQualityActionType.refocusSubject.rawValue)
            && futureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue)

        let hasContextualSemanticCorrectionPressure =
            shouldCorrectTightReadableEdge(snapshot: snapshot, semantics: semantics)
            || shouldCorrectReadableSyntheticSmallSubject(snapshot: snapshot, semantics: semantics, futureActions: futureActions)
            || shouldCorrectReadableSyntheticClutter(snapshot: snapshot, semantics: semantics)
            || shouldCorrectReadableSyntheticCrooked(snapshot: snapshot, semantics: semantics, futureActions: futureActions)
            || shouldCorrectReadableSyntheticGlareObject(snapshot: snapshot, semantics: semantics, futureActions: futureActions)
            || shouldCorrectReadableLargeHotspot(snapshot: snapshot, semantics: semantics)
            || shouldCorrectHighKeyReadableWeakSubject(snapshot: snapshot, semantics: semantics)
            || shouldCorrectLargeDetectorWeakSubject(snapshot: snapshot, semantics: semantics, futureActions: futureActions)
            || shouldCorrectReadableNeutralDenseClutter(snapshot: snapshot, semantics: semantics)
            || shouldCorrectReadableSmallForegroundObstruction(snapshot: snapshot, semantics: semantics, futureActions: futureActions)
            || shouldCorrectReadableSmallEdgeCrop(snapshot: snapshot, semantics: semantics, futureActions: futureActions)
            || shouldCorrectTinyReadableUnderexposure(snapshot: snapshot, semantics: semantics)
            || shouldCorrectUnknownHotspot(snapshot: snapshot, semantics: semantics)
            || shouldCorrectUnknownLargeUnderexposedSubject(snapshot: snapshot, semantics: semantics, futureActions: futureActions)
            || shouldCorrectReadableSmallStabilizedClutter(snapshot: snapshot, semantics: semantics, futureActions: futureActions)
            || shouldCorrectUnknownNoSubjectUnderexposure(snapshot: snapshot, semantics: semantics, futureActions: futureActions)
            || shouldCorrectUnknownNoSubjectHotspot(snapshot: snapshot, semantics: semantics, futureActions: futureActions)
            || shouldCorrectUnknownNoSubjectClutterOrOcclusion(snapshot: snapshot, semantics: semantics, futureActions: futureActions)
        if hasContextualSemanticCorrectionPressure {
            return false
        }

        let isReadableCinematicInsert = semantics.readability.subjectReadable
            && snapshot.objects.totalCount <= 2
            && snapshot.composition.subjectAreaRatio < 0.35
            && (snapshot.composition.subjectAreaRatio >= 0.10 || semantics.dominance.hasClearFocus)
            && semantics.dominance.backgroundClutterScore <= 0.28
            && semantics.dominance.focusCompetitionScore <= 0.35
            && semantics.primarySubject.confidence >= 0.55
            && (
                snapshot.lighting.exposureBiasHint < 0.60
                || (
                    semantics.sceneType == .objectInsert
                        && semantics.sceneTypeConfidence >= 0.70
                        && (snapshot.aesthetics.score ?? 0) >= 0.45
                        && snapshot.composition.subjectAreaRatio >= 0.24
                        && snapshot.composition.subjectAreaRatio <= 0.35
                        && semantics.dominance.backgroundClutterScore <= 0.16
                        && semantics.dominance.focusCompetitionScore <= 0.26
                        && semantics.primarySubject.confidence >= 0.60
                        && snapshot.lighting.exposureBiasHint < 0.75
                )
            )
            && !(hasHeavyReadableTechnicalPressure && snapshot.lighting.exposureBiasHint <= -0.75)

        return isCleanUnknownEstablishing || isReadableCinematicInsert
    }

    private func shouldForceSemanticCorrectionOverCinematicPreservation(snapshot: FrameFeatureSnapshot,
                                                                        semantics: SceneSemanticsReport) -> Bool {
        if snapshot.composition.subjectAreaRatio >= 0.82,
           semantics.readability.subjectReadable {
            return true
        }
        if semantics.dominance.backgroundClutterScore >= 0.32,
           snapshot.objects.totalCount >= 2,
           (snapshot.aesthetics.score ?? 1.0) < 0.47 {
            return true
        }
        if snapshot.lighting.exposureBiasHint >= 0.60,
           !shouldRespectReadableObjectInsertPreservation(snapshot: snapshot, semantics: semantics) {
            return true
        }
        if snapshot.composition.subjectAreaRatio < 0.10,
           semantics.primarySubject.confidence < 0.50,
           !shouldRespectCleanUnknownEstablishingFrame(snapshot: snapshot, semantics: semantics),
           (semantics.sceneType == .unknown || semantics.sceneTypeConfidence < 0.65) {
            return true
        }
        return false
    }

    private func shouldPreserveSemanticGoodVerdictOverTechnicalPauseIssue(issue: TechnicalQualityIssueSignal,
                                                                          snapshot: FrameFeatureSnapshot,
                                                                          structuredVerdict: FrameVerdict) -> Bool {
        guard structuredVerdict == .good,
              issue.type == .defocus || issue.type == .motionBlur || issue.type == .overexposure,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore >= 0.40,
              snapshot.composition.subjectAreaRatio >= 0.34,
              snapshot.composition.subjectAreaRatio < 0.55,
              max(
                snapshot.subjectSignals.primaryCandidateConfidence ?? 0,
                snapshot.subjectSignals.topObjectConfidence ?? 0
              ) >= 0.70,
              snapshot.objects.totalCount >= 2 else {
            return false
        }
        return true
    }

    private func contextualTechnicalPauseIssue(from signal: TechnicalQualitySignal,
                                               snapshot: FrameFeatureSnapshot,
                                               semantics: SceneSemanticsReport) -> TechnicalQualityIssueSignal? {
        if let overexposure = signal.issues.first(where: { issue in
            issue.type == .overexposure && issue.confidence >= 0.55
        }),
           shouldTreatOverexposureAsReadableHotspot(snapshot: snapshot, semantics: semantics) {
            return overexposure
        }
        if let aestheticScore = snapshot.aesthetics.score,
           aestheticScore >= 0.42 {
            return nil
        }
        return signal.issues.first { issue in
            issue.type == .overexposure && issue.confidence >= 0.55
        }
    }

    private func shouldTreatOverexposureAsReadableHotspot(snapshot: FrameFeatureSnapshot,
                                                          semantics: SceneSemanticsReport) -> Bool {
        snapshot.lighting.exposureBiasHint >= 0.60
            && semantics.readability.subjectReadable
            && snapshot.objects.totalCount <= 2
            && snapshot.composition.subjectAreaRatio <= 0.22
            && !shouldRespectReadableObjectInsertPreservation(snapshot: snapshot, semantics: semantics)
            && semantics.dominance.backgroundClutterScore <= 0.30
    }

    private func technicalPauseActions(for issue: TechnicalQualityIssueSignal,
                                       traceId: String,
                                       snapshot: FrameFeatureSnapshot? = nil,
                                       semantics: SceneSemanticsReport? = nil) -> [PauseActionRow] {
        switch issue.type {
        case .overexposure:
            var actions = [
                PauseActionRow(
                    actionId: "act_technical_remove_hotspot",
                    actionType: .changeAngle,
                    semanticActionType: .removeBackgroundHotspot,
                    priority: 1,
                    confidence: technicalQualityConfidence(for: issue),
                    linkedIssueIds: [],
                    expectedOutcome: "Яркое пятно перестанет перетягивать внимание с главного объекта.",
                    targetRegion: nil,
                    overlayHintId: nil,
                    traceRefId: traceId
                ),
                PauseActionRow(
                    actionId: "act_technical_change_angle",
                    actionType: .changeAngle,
                    semanticActionType: .changeCameraAngle,
                    priority: 2,
                    confidence: technicalQualityConfidence(for: issue),
                    linkedIssueIds: [],
                    expectedOutcome: "Небольшая смена угла уменьшит пересвет и вернёт детали в ярких областях.",
                    targetRegion: nil,
                    overlayHintId: nil,
                    traceRefId: traceId
                ),
                PauseActionRow(
                    actionId: "act_technical_simplify_background",
                    actionType: .reduceBackgroundDistractions,
                    semanticActionType: .simplifyBackground,
                    priority: 3,
                    confidence: technicalQualityConfidence(for: issue),
                    linkedIssueIds: [],
                    expectedOutcome: "Уберите яркие или шумные детали фона, чтобы они не конкурировали с главным объектом.",
                    targetRegion: nil,
                    overlayHintId: nil,
                    traceRefId: traceId
                )
            ]
            if let snapshot,
               let semantics,
               shouldAddObjectClusterClearance(snapshot: snapshot, semantics: semantics) {
                actions.append(
                    PauseActionRow(
                        actionId: "act_technical_background_clearance",
                        actionType: .reduceBackgroundDistractions,
                        semanticActionType: .waitForBackgroundClearance,
                        priority: actions.count + 1,
                        confidence: technicalQualityConfidence(for: issue),
                        linkedIssueIds: [],
                        expectedOutcome: "Дождитесь более свободного фона, чтобы яркие и шумные детали не спорили с главным объектом.",
                        targetRegion: nil,
                        overlayHintId: nil,
                        traceRefId: traceId
                    )
                )
            }
            if let snapshot,
               let semantics,
               shouldAddLevelHorizonTechnicalAction(snapshot: snapshot, semantics: semantics) {
                actions.append(
                    PauseActionRow(
                        actionId: "act_technical_level_horizon",
                        actionType: .levelHorizon,
                        semanticActionType: .levelHorizon,
                        priority: actions.count + 1,
                        confidence: technicalQualityConfidence(for: issue),
                        linkedIssueIds: [],
                        expectedOutcome: "Выравнивание камеры вернёт сцене устойчивую ориентацию и снизит ощущение случайного кадра.",
                        targetRegion: nil,
                        overlayHintId: nil,
                        traceRefId: traceId
                    )
                )
            }
            return actions
        case .underexposure:
            return [
                PauseActionRow(
                    actionId: "act_technical_add_front_fill",
                    actionType: .improveFrontLight,
                    semanticActionType: .addFrontFillLight,
                    priority: 1,
                    confidence: technicalPauseConfidence(for: issue),
                    linkedIssueIds: [],
                    expectedOutcome: "Мягкий фронтальный или боковой свет сделает главный объект читаемее без сильного пересвета фона.",
                    targetRegion: nil,
                    overlayHintId: nil,
                    traceRefId: traceId
                )
            ]
        default:
            return []
        }
    }

    private func shouldAddObjectClusterClearance(snapshot: FrameFeatureSnapshot,
                                                 semantics: SceneSemanticsReport) -> Bool {
        guard semantics.readability.subjectReadable,
              semantics.primarySubject.kind == .object,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore < 0.42 else {
            return false
        }

        let isClusteredObjectInsert = snapshot.objects.totalCount >= 2
            && semantics.dominance.backgroundClutterScore >= 0.30
        let isLargeObjectDominant = snapshot.composition.subjectAreaRatio >= 0.65
        return isClusteredObjectInsert || isLargeObjectDominant
    }

    private func shouldAddLevelHorizonTechnicalAction(snapshot: FrameFeatureSnapshot,
                                                      semantics: SceneSemanticsReport) -> Bool {
        guard semantics.readability.subjectReadable,
              semantics.primarySubject.kind == .object,
              snapshot.objects.totalCount >= 3,
              snapshot.composition.subjectAreaRatio >= 0.55,
              snapshot.horizon.confidence >= 0.80,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore >= 0.42 else {
            return false
        }
        return true
    }

    private func shouldAddContextualStabilizeFutureAction(snapshot: FrameFeatureSnapshot,
                                                          semantics: SceneSemanticsReport,
                                                          currentFutureActions: [String]) -> Bool {
        guard semantics.readability.subjectReadable,
              semantics.primarySubject.kind == .object,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore < 0.44,
              currentFutureActions.contains(where: {
                  $0 == TechnicalQualityActionType.reduceExposure.rawValue ||
                      $0 == TechnicalQualityActionType.increaseExposure.rawValue
              }) else {
            return false
        }

        let isClusteredObjectInsert = snapshot.objects.totalCount >= 2
            && semantics.dominance.backgroundClutterScore >= 0.30
        let isLargeObjectDominant = snapshot.composition.subjectAreaRatio >= 0.55
        return isClusteredObjectInsert || isLargeObjectDominant
    }

    private func technicalQualityConfidence(for issue: TechnicalQualityIssueSignal) -> Double {
        min(1.0, max(0.0, max(issue.confidence, issue.severity, 0.75)))
    }

    private func technicalLiveText(for issue: TechnicalQualityIssueSignal) -> String {
        switch issue.type {
        case .defocus:
            return "Не хватает резкости — тапни по главному объекту."
        case .motionBlur:
            return "Резкость просела — зафиксируй камеру перед снимком."
        case .overexposure:
            return "Слишком ярко — снизь экспозицию или смени угол."
        case .underexposure:
            return "Слишком темно — добавь свет на объект."
        case .noise:
            return "Кадр шумит — добавь света перед снимком."
        case .occlusion:
            return "Объект перекрыт — убери помеху из кадра."
        case .lensSmudge:
            return "Картинка мутная — проверь чистоту объектива."
        }
    }

    private func technicalPauseSummary(for issue: TechnicalQualityIssueSignal) -> String {
        switch issue.type {
        case .defocus:
            return "Техническая проблема: главный объект выглядит нерезким"
        case .motionBlur:
            return "Техническая проблема: кадр выглядит смазанным"
        case .overexposure:
            return "Техническая проблема: яркие области перетянуты"
        case .underexposure:
            return "Техническая проблема: кадр недоэкспонирован"
        case .noise:
            return "Техническая проблема: заметен цифровой шум"
        case .occlusion:
            return "Техническая проблема: важный объект перекрыт"
        case .lensSmudge:
            return "Техническая проблема: изображение выглядит мутным"
        }
    }

    private func technicalPauseWhyProblematic(for issue: TechnicalQualityIssueSignal) -> String {
        switch issue.type {
        case .defocus:
            return "Система видит слабую локальную детализацию: зрителю сложнее понять, на чём должен быть фокус."
        case .motionBlur:
            return "Система видит признаки смаза: контуры становятся мягкими, и кадр хуже читается даже при нормальной композиции."
        case .overexposure:
            return "Система видит сильные пересвеченные зоны: они забирают внимание и скрывают детали сцены."
        case .underexposure:
            return "Система видит много глубоких теней: объект и детали сцены читаются хуже."
        case .noise:
            return "Система видит мало полезной детализации в тёмных участках: шум начинает конкурировать с объектом."
        case .occlusion:
            return "Система видит перекрытие важной области: зритель получает меньше информации о главном объекте."
        case .lensSmudge:
            return "Система видит глобальную мутность: проблема похожа на грязный объектив или сильную потерю микроконтраста."
        }
    }

    private func technicalPauseActionText(for issue: TechnicalQualityIssueSignal) -> String {
        switch issue.actionType {
        case .stabilizeCamera:
            return "Останови движение камеры, прижми локти или используй опору и пересними."
        case .refocusSubject:
            return "Тапни по главному объекту, дождись фокуса и пересними кадр."
        case .reduceExposure:
            return "Сдвинь экспозицию вниз или поверни камеру так, чтобы яркий источник не доминировал."
        case .increaseExposure:
            return "Добавь фронтальный/боковой свет или подними экспозицию до читаемости объекта."
        case .avoidOcclusion:
            return "Сдвинь камеру или убери предмет, который перекрывает главный объект."
        case .cleanLens:
            return "Протри объектив и повтори кадр."
        case .reduceIsoNoise:
            return "Добавь света и пересними с меньшим ISO/шумом."
        }
    }

    @MainActor
    private func applyLiveHint(candidate: LiveHintPresentation?, now: Date) {
        guard let candidate else {
            if currentLiveHint != nil,
               now.timeIntervalSince(liveHintShownAt) >= minLiveHintHold,
               now >= liveHintExpiresAt {
                currentLiveHint = nil
                liveHintShownAt = now
                liveHintExpiresAt = .distantPast
            } else if currentLiveHint == nil {
                liveHintShownAt = now
                liveHintExpiresAt = .distantPast
            }
            return
        }

        guard let current = currentLiveHint else {
            currentLiveHint = candidate
            liveHintShownAt = now
            liveHintExpiresAt = now.addingTimeInterval(liveHintDuration(for: candidate))
            return
        }

        if current.id.hasPrefix("lh_demo_") || candidate.id.hasPrefix("lh_demo_") {
            currentLiveHint = candidate
            liveHintShownAt = now
            liveHintExpiresAt = now.addingTimeInterval(liveHintDuration(for: candidate))
            return
        }

        let sameActionType = current.actionType == candidate.actionType
        let smallConfidenceDelta = abs(candidate.confidence - current.confidence) < liveHintTextOnlyConfidenceDelta
        if sameActionType, current.actionType != nil, smallConfidenceDelta {
            // Text-only refresh branch: keep stable identity to avoid remount/flash.
            currentLiveHint = LiveHintPresentation(
                id: current.id,
                frameId: candidate.frameId,
                text: candidate.text,
                confidence: candidate.confidence,
                actionType: candidate.actionType,
                actionId: candidate.actionId,
                linkedIssueIds: candidate.linkedIssueIds,
                summaryId: candidate.summaryId,
                traceRootIds: candidate.traceRootIds,
                targetRegion: candidate.targetRegion,
                overlayHint: candidate.overlayHint,
                isFallback: candidate.isFallback,
                expandedVerdict: candidate.expandedVerdict
            )
            liveHintExpiresAt = now.addingTimeInterval(liveHintDuration(for: candidate))
            return
        }

        if current.id == candidate.id {
            currentLiveHint = candidate
            liveHintExpiresAt = now.addingTimeInterval(liveHintDuration(for: candidate))
            return
        }

        if candidate.isFallback && !current.isFallback {
            currentLiveHint = candidate
            liveHintShownAt = now
            liveHintExpiresAt = now.addingTimeInterval(liveHintDuration(for: candidate))
            return
        }

        let holdExpired = now.timeIntervalSince(liveHintShownAt) >= minLiveHintHold
        let confidenceBoost = candidate.confidence - current.confidence
        if holdExpired || confidenceBoost >= liveHintConfidenceDelta {
            currentLiveHint = candidate
            liveHintShownAt = now
            liveHintExpiresAt = now.addingTimeInterval(liveHintDuration(for: candidate))
        }
    }

    private func liveHintDuration(for hint: LiveHintPresentation) -> TimeInterval {
        guard hint.id.hasPrefix("lh_demo_") else { return liveHintDisplayDuration }
        if hint.actionType == nil || hint.actionType == .leaveFrameAsIs {
            return 1.5
        }
        return 3.0
    }

    private func makePauseCritiquePresentation(critique: CritiqueReport,
                                               plan: RecommendationPlan,
                                               semanticTips: [SemanticTipCandidate],
                                               semanticFallbackUsed: Bool,
                                               snapshot: FrameFeatureSnapshot? = nil,
                                               semantics: SceneSemanticsReport? = nil,
                                               technicalQualitySignal: TechnicalQualitySignal = .empty) -> PauseCritiquePresentation {
        let fallbackUsed = critique.fallbackUsed || semanticFallbackUsed
        let preservesGoodFrameActions = shouldPreserveGoodFrameSemanticActions(
            snapshot: snapshot,
            semantics: semantics,
            verdict: critique.verdict,
            technicalQualitySignal: technicalQualitySignal,
            allowsMixedVerdict: true
        )
        let contextualCorrection = preservesGoodFrameActions ? nil : contextualSemanticCorrection(
            snapshot: snapshot,
            semantics: semantics,
            critique: critique,
            technicalQualitySignal: technicalQualitySignal
        )
        let strengths = contextualCorrection == nil ? critique.strengths.prefix(2).map { strength in
            PauseStrengthRow(
                strengthId: strength.id,
                type: strength.type,
                rationale: strength.rationale,
                confidence: strength.confidence,
                supportingRegion: strength.supportingRegion,
                traceRefId: traceRefIdForStrength(strengthId: strength.id, critique: critique)
            )
        } : []
        let issues = critique.issues.prefix(3).map { issue in
            PauseIssueRow(
                issueId: issue.id,
                type: issue.type,
                severity: issue.severity,
                confidence: issue.confidence,
                rationale: issue.rationale,
                affectedRegion: issue.affectedRegion,
                suggestedFixTypes: issue.suggestedFixTypes,
                traceRefId: traceRefIdForIssue(issueId: issue.id, critique: critique)
            )
        }

        let semanticActionRows = semanticTips.prefix(4).enumerated().compactMap { index, tip -> PauseActionRow? in
            guard critique.verdict != .good else { return nil }
            guard let action = linkedAction(for: tip, plan: plan) else { return nil }
            return PauseActionRow(
                actionId: "\(action.id)_semantic_\(semanticTipPlanner.stableKey(for: tip))_\(index)",
                actionType: action.actionType,
                semanticActionType: tip.actionType,
                priority: action.priority,
                confidence: pauseActionConfidence(
                    for: action,
                    plan: plan,
                    critique: critique,
                    linkedIssueIds: tip.linkedIssueIds
                ),
                linkedIssueIds: tip.linkedIssueIds,
                expectedOutcome: tip.pauseText,
                targetRegion: action.targetRegion ?? firstIssueRegion(linkedIssueIds: tip.linkedIssueIds, critique: critique),
                overlayHintId: action.overlayHint?.id,
                traceRefId: tip.linkedTraceIds.first ?? traceRefIdForAction(action: action, critique: critique)
            )
        }
        let actions: [PauseActionRow]
        if preservesGoodFrameActions {
            actions = []
        } else if let contextualCorrection {
            actions = contextualPauseActionRows(for: contextualCorrection)
        } else if semanticActionRows.isEmpty {
            let plannedActions = [plan.primaryAction]
                .compactMap { $0 }
                + Array(plan.secondaryActions.prefix(2))
            actions = plannedActions.prefix(3).map { action in
                PauseActionRow(
                    actionId: action.id,
                    actionType: action.actionType,
                    semanticActionType: action.actionType.semanticActionType,
                    priority: action.priority,
                    confidence: pauseActionConfidence(for: action, plan: plan, critique: critique),
                    linkedIssueIds: action.linkedIssueIds,
                    expectedOutcome: action.expectedOutcome,
                    targetRegion: action.targetRegion ?? firstIssueRegion(linkedIssueIds: action.linkedIssueIds, critique: critique),
                    overlayHintId: action.overlayHint?.id,
                    traceRefId: traceRefIdForAction(action: action, critique: critique)
                )
            }
        } else {
            actions = semanticActionRows
        }

        let effectiveVerdict = preservesGoodFrameActions ? FrameVerdict.good : (contextualCorrection?.verdict ?? critique.verdict)
        let noChangeRationale: String?
        if effectiveVerdict == .good && actions.isEmpty {
            noChangeRationale = nonEmpty(semanticTips.first?.pauseText)
                ?? nonEmpty(plan.noChangeRationale)
                ?? critique.summary.whyGood
                ?? critique.summary.shortVerdict
        } else {
            noChangeRationale = nil
        }

        let assumptions: [String] = {
            var values: [String] = []
            if fallbackUsed {
                values.append("Structured analysis degraded: using reduced-coverage critique output.")
            }
            return values
        }()
        let verdictConfidence = contextualCorrection?.confidence ?? pauseVerdictConfidence(
            verdict: effectiveVerdict,
            baseConfidence: critique.verdictConfidence,
            strengths: strengths,
            actions: actions
        )
        let traceRootIds = preservesGoodFrameActions
            ? ["cinematic_good_frame_action_preservation"] + critique.traceRefs
            : (contextualCorrection.map { [$0.traceId] } ?? critique.traceRefs)

        return PauseCritiquePresentation(
            frameId: critique.frameId,
            verdict: effectiveVerdict,
            verdictConfidence: verdictConfidence,
            summaryId: preservesGoodFrameActions ? "cinematic_good_frame_action_preservation" : (contextualCorrection?.traceId ?? critique.summary.id),
            shortVerdict: preservesGoodFrameActions
                ? (critique.summary.whyGood ?? "Кадр выглядит собранно — сохраняем текущую постановку.")
                : (contextualCorrection?.pauseSummary ?? critique.summary.shortVerdict),
            whyGood: contextualCorrection == nil ? (critique.summary.whyGood ?? noChangeRationale) : nil,
            whyProblematic: contextualCorrection?.whyProblematic ?? critique.summary.whyProblematic,
            strengths: Array(strengths),
            issues: Array(issues),
            actions: actions,
            noChangeRationale: noChangeRationale,
            assumptions: assumptions,
            traceRootIds: traceRootIds,
            fallbackUsed: fallbackUsed
        )
    }

    private func pauseVerdictConfidence(verdict: FrameVerdict,
                                        baseConfidence: Double,
                                        strengths: [PauseStrengthRow],
                                        actions: [PauseActionRow]) -> Double {
        if verdict == .mixed, !actions.isEmpty {
            return min(clamp01(baseConfidence), 0.74)
        }
        guard verdict == .good,
              actions.isEmpty,
              !strengths.isEmpty else {
            return clamp01(baseConfidence)
        }
        return clamp01(max(baseConfidence, 0.75))
    }

    private struct ContextualSemanticCorrection {
        let idSuffix: String
        let traceId: String
        let verdict: FrameVerdict
        let confidence: Double
        let liveText: String
        let pauseSummary: String
        let whyProblematic: String
        let pauseActionText: String
        let liveActionType: ActionTypeV1?
        let semanticActionTypes: [SemanticActionType]
    }

    private func shouldPreserveGoodFrameSemanticActions(snapshot: FrameFeatureSnapshot?,
                                                        semantics: SceneSemanticsReport?,
                                                        verdict: FrameVerdict,
                                                        technicalQualitySignal: TechnicalQualitySignal,
                                                        allowsMixedVerdict: Bool = false) -> Bool {
        guard let snapshot,
              let semantics,
              let aestheticScore = snapshot.aesthetics.score else {
            return false
        }
        guard verdict == .good
                || (allowsMixedVerdict && (verdict == .mixed || verdict == .needsFix)) else {
            return false
        }
        guard snapshot.subjectSignals.personCount == 0 else {
            return false
        }

        let futureActions = Set(technicalQualitySignal.futureActionIds)
        let hasRefocusPressure = futureActions.contains(TechnicalQualityActionType.refocusSubject.rawValue)
        let hasNoiseRecoveryPressure = futureActions.contains(TechnicalQualityActionType.reduceIsoNoise.rawValue)
        let objectCount = snapshot.objects.totalCount
        let subjectArea = snapshot.composition.subjectAreaRatio
        let backgroundClutter = semantics.dominance.backgroundClutterScore
        let focusCompetition = semantics.dominance.focusCompetitionScore
        let exposureBias = snapshot.lighting.exposureBiasHint
        let subjectReadable = semantics.readability.subjectReadable
        let isReadableObjectInsert = subjectReadable
            && semantics.primarySubject.kind == .object
            && semantics.sceneType == .objectInsert

        let isSparseReadableObjectEstablishing = subjectReadable
            && semantics.primarySubject.kind == .object
            && semantics.sceneType == .establishingLikeFrame
            && objectCount <= 1
            && subjectArea > 0
            && subjectArea <= 0.05
            && backgroundClutter <= 0.12
            && focusCompetition <= 0.56
            && semantics.readability.separationScore >= 0.60
            && aestheticScore >= 0.38
            && exposureBias > -0.65
            && exposureBias < 0.25
            && !hasRefocusPressure

        let isSmallReadablePromoInsert = isReadableObjectInsert
            && objectCount <= 2
            && !semantics.dominance.hasClearFocus
            && (0.06...0.08).contains(subjectArea)
            && semantics.sceneTypeConfidence >= 0.65
            && semantics.primarySubject.confidence >= 0.50
            && backgroundClutter <= 0.36
            && focusCompetition <= 0.35
            && semantics.readability.separationScore >= 0.64
            && aestheticScore >= 0.43
            && exposureBias > -1.60
            && exposureBias < 0.25

        let isDenseProductionSetPromoFrame = isReadableObjectInsert
            && objectCount >= 5
            && objectCount <= 8
            && (0.38...0.58).contains(subjectArea)
            && (0.60...0.80).contains(backgroundClutter)
            && focusCompetition <= 0.45
            && semantics.primarySubject.confidence >= 0.70
            && semantics.sceneTypeConfidence >= 0.70
            && semantics.readability.separationScore >= 0.60
            && aestheticScore >= 0.39
            && exposureBias > -1.05
            && exposureBias < 0.35
            && !hasRefocusPressure
            && !hasNoiseRecoveryPressure

        return isSparseReadableObjectEstablishing
            || isSmallReadablePromoInsert
            || isDenseProductionSetPromoFrame
    }

    private func contextualSemanticCorrection(snapshot: FrameFeatureSnapshot?,
                                              semantics: SceneSemanticsReport?,
                                              critique: CritiqueReport,
                                              technicalQualitySignal: TechnicalQualitySignal) -> ContextualSemanticCorrection? {
        guard critique.verdict == .good,
              let snapshot,
              let semantics else {
            return nil
        }
        if shouldPreserveGoodFrameSemanticActions(
            snapshot: snapshot,
            semantics: semantics,
            verdict: critique.verdict,
            technicalQualitySignal: technicalQualitySignal
        ) {
            return nil
        }

        let futureActions = Set(technicalQualitySignal.futureActionIds)
        let hasLowLightTechnicalPressure = futureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue)
            || futureActions.contains(TechnicalQualityActionType.reduceIsoNoise.rawValue)
            || futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue)
        let aestheticScore = snapshot.aesthetics.score ?? 1.0
        let objectCount = snapshot.objects.totalCount
        let subjectArea = snapshot.composition.subjectAreaRatio
        let subjectLabel = semantics.primarySubject.label?.lowercased() ?? ""
        let subjectReadable = semantics.readability.subjectReadable
        let primarySubjectConfidence = semantics.primarySubject.confidence
        let sceneTypeConfidence = semantics.sceneTypeConfidence
        let isUnknownSubject = semantics.primarySubject.kind == .unknown
        let hasStabilizationPressure = futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue)
        let hasRefocusPressure = futureActions.contains(TechnicalQualityActionType.refocusSubject.rawValue)
        let hasLowAestheticSingleObjectPressure = subjectReadable
            && objectCount == 1
            && aestheticScore < 0.37
            && subjectArea < 0.22
        let hasReadableUnderlitObjectPressure = subjectReadable
            && semantics.primarySubject.kind == .object
            && semantics.dominance.hasClearFocus
            && subjectLabel != "light"
            && objectCount == 1
            && (0.30...0.55).contains(subjectArea)
            && aestheticScore < 0.50
            && snapshot.lighting.exposureBiasHint <= -0.90
        let hasLowAestheticObjectClearancePressure = subjectReadable
            && semantics.primarySubject.kind == .object
            && objectCount == 1
            && aestheticScore < 0.42
            && (0.22...0.32).contains(subjectArea)
        let hasUnknownBlurBackgroundPressure = isUnknownSubject
            && !subjectReadable
            && objectCount == 0
            && (0.36..<0.38).contains(aestheticScore)
            && (hasStabilizationPressure || hasRefocusPressure)
        let hasUnknownGroupFramingPressure = isUnknownSubject
            && !subjectReadable
            && objectCount == 0
            && semantics.sceneType == .establishingLikeFrame
            && semantics.dominance.focusCompetitionScore >= 0.45
            && (0.44...0.48).contains(aestheticScore)
            && critique.verdictConfidence >= 0.60
            && snapshot.lighting.exposureBiasHint < -0.05
            && (hasStabilizationPressure || futureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue))
        let hasUnreadableLowLightSingleObjectPressure = isUnknownSubject
            && !subjectReadable
            && objectCount == 1
            && subjectArea == 0
            && aestheticScore < 0.37
            && snapshot.lighting.exposureBiasHint <= -0.80
            && (hasRefocusPressure || futureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue))
        let hasUnknownNoisyLowLightStepBackPressure = isUnknownSubject
            && !subjectReadable
            && objectCount == 0
            && (0.38..<0.40).contains(aestheticScore)
            && hasStabilizationPressure
            && !hasRefocusPressure
            && futureActions.contains(TechnicalQualityActionType.reduceIsoNoise.rawValue)
            && futureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue)
        let hasWideUnknownWeakSubjectStepCloserPressure = isUnknownSubject
            && !subjectReadable
            && objectCount == 1
            && subjectArea == 0
            && aestheticScore < 0.37
            && snapshot.lighting.exposureBiasHint > -0.80
            && semantics.dominance.focusCompetitionScore >= 0.50
            && hasStabilizationPressure
        let hasFlashTightGroupStepBackPressure = subjectReadable
            && semantics.primarySubject.kind == .object
            && subjectLabel == "light"
            && objectCount >= 3
            && (0.20...0.30).contains(subjectArea)
            && semantics.dominance.backgroundClutterScore >= 0.34
            && hasStabilizationPressure
        let hasLargeColorCastObjectPressure = subjectReadable
            && semantics.primarySubject.kind == .object
            && objectCount == 1
            && subjectArea >= 0.85
            && aestheticScore < 0.40
            && (hasStabilizationPressure || hasRefocusPressure)
        let hasLightingFeaturePressure = snapshot.lighting.exposureBiasHint <= -0.90
            || snapshot.lighting.backlightIndex >= 0.18
        let hasTechnicalOnlySoftnessPressure = shouldTreatAsTechnicalOnlySoftness(
            snapshot: snapshot,
            semantics: semantics,
            futureActions: futureActions
        )
        let hasTightReadableEdgePressure = shouldCorrectTightReadableEdge(snapshot: snapshot, semantics: semantics)
        let hasStrongReadableUnderexposurePressure = shouldCorrectStrongReadableUnderexposure(
            snapshot: snapshot,
            semantics: semantics,
            futureActions: futureActions
        )
        let hasWeakReadableSubjectPressure = shouldCorrectWeakReadableSubject(
            snapshot: snapshot,
            semantics: semantics,
            futureActions: futureActions
        )
        let hasReadableBackgroundClutterPressure = shouldCorrectReadableBackgroundClutter(snapshot: snapshot, semantics: semantics)
        let hasReadableHotspotPressure = shouldCorrectReadableHotspot(
            snapshot: snapshot,
            semantics: semantics,
            futureActions: futureActions
        )
        let hasReadableLargeHotspotPressure = shouldCorrectReadableLargeHotspot(snapshot: snapshot, semantics: semantics)
        let hasHighKeyReadableWeakSubjectPressure = shouldCorrectHighKeyReadableWeakSubject(snapshot: snapshot, semantics: semantics)
        let hasLargeDetectorWeakSubjectPressure = shouldCorrectLargeDetectorWeakSubject(
            snapshot: snapshot,
            semantics: semantics,
            futureActions: futureActions
        )
        let hasReadableNeutralDenseClutterPressure = shouldCorrectReadableNeutralDenseClutter(
            snapshot: snapshot,
            semantics: semantics
        )
        let hasReadableSmallForegroundObstructionPressure = shouldCorrectReadableSmallForegroundObstruction(
            snapshot: snapshot,
            semantics: semantics,
            futureActions: futureActions
        )
        let hasReadableSmallEdgeCropPressure = shouldCorrectReadableSmallEdgeCrop(
            snapshot: snapshot,
            semantics: semantics,
            futureActions: futureActions
        )
        let hasTinyReadableUnderexposurePressure = shouldCorrectTinyReadableUnderexposure(
            snapshot: snapshot,
            semantics: semantics
        )
        let hasUnknownHotspotPressure = shouldCorrectUnknownHotspot(snapshot: snapshot, semantics: semantics)
        let hasUnknownLargeUnderexposedSubjectPressure = shouldCorrectUnknownLargeUnderexposedSubject(
            snapshot: snapshot,
            semantics: semantics,
            futureActions: futureActions
        )
        let hasReadableSmallStabilizedClutterPressure = shouldCorrectReadableSmallStabilizedClutter(
            snapshot: snapshot,
            semantics: semantics,
            futureActions: futureActions
        )
        let hasReadableSyntheticSmallSubjectPressure = shouldCorrectReadableSyntheticSmallSubject(
            snapshot: snapshot,
            semantics: semantics,
            futureActions: futureActions
        )
        let hasReadableSyntheticClutterPressure = shouldCorrectReadableSyntheticClutter(snapshot: snapshot, semantics: semantics)
        let hasReadableSyntheticCrookedPressure = shouldCorrectReadableSyntheticCrooked(
            snapshot: snapshot,
            semantics: semantics,
            futureActions: futureActions
        )
        let hasReadableSyntheticGlarePressure = shouldCorrectReadableSyntheticGlareObject(
            snapshot: snapshot,
            semantics: semantics,
            futureActions: futureActions
        )
        let hasUnknownNoSubjectUnderexposurePressure = shouldCorrectUnknownNoSubjectUnderexposure(
            snapshot: snapshot,
            semantics: semantics,
            futureActions: futureActions
        )
        let hasUnknownNoSubjectHotspotPressure = shouldCorrectUnknownNoSubjectHotspot(
            snapshot: snapshot,
            semantics: semantics,
            futureActions: futureActions
        )
        let hasUnknownNoSubjectClutterPressure = shouldCorrectUnknownNoSubjectClutterOrOcclusion(
            snapshot: snapshot,
            semantics: semantics,
            futureActions: futureActions
        )
        if shouldPreserveCinematicGoodFrameOverTechnicalSignal(
            signal: technicalQualitySignal,
            snapshot: snapshot,
            semantics: semantics,
            structuredVerdict: critique.verdict
        ) {
            return nil
        }
        guard hasLowLightTechnicalPressure
                || hasLowAestheticSingleObjectPressure
                || hasReadableUnderlitObjectPressure
                || hasLowAestheticObjectClearancePressure
                || hasUnknownBlurBackgroundPressure
                || hasUnknownGroupFramingPressure
                || hasUnreadableLowLightSingleObjectPressure
                || hasUnknownNoisyLowLightStepBackPressure
                || hasWideUnknownWeakSubjectStepCloserPressure
                || hasFlashTightGroupStepBackPressure
                || hasLargeColorCastObjectPressure
                || hasLightingFeaturePressure
                || hasTechnicalOnlySoftnessPressure
                || hasTightReadableEdgePressure
                || hasStrongReadableUnderexposurePressure
                || hasWeakReadableSubjectPressure
                || hasReadableBackgroundClutterPressure
                || hasReadableHotspotPressure
                || hasReadableLargeHotspotPressure
                || hasHighKeyReadableWeakSubjectPressure
                || hasLargeDetectorWeakSubjectPressure
                || hasReadableNeutralDenseClutterPressure
                || hasReadableSmallForegroundObstructionPressure
                || hasReadableSmallEdgeCropPressure
                || hasTinyReadableUnderexposurePressure
                || hasUnknownHotspotPressure
                || hasUnknownLargeUnderexposedSubjectPressure
                || hasReadableSmallStabilizedClutterPressure
                || hasReadableSyntheticSmallSubjectPressure
                || hasReadableSyntheticClutterPressure
                || hasReadableSyntheticCrookedPressure
                || hasReadableSyntheticGlarePressure
                || hasUnknownNoSubjectUnderexposurePressure
                || hasUnknownNoSubjectHotspotPressure
                || hasUnknownNoSubjectClutterPressure else { return nil }

        if hasTechnicalOnlySoftnessPressure {
            return ContextualSemanticCorrection(
                idSuffix: "readable_softness_technical_only",
                traceId: "contextual_readable_softness_technical_only",
                verdict: .needsFix,
                confidence: 0.70,
                liveText: "Кадр смазан — сначала зафиксируй камеру.",
                pauseSummary: "Проблема техническая: резкость просела, но композиционный совет не подтверждён",
                whyProblematic: "Объект читается, а фон не даёт явного композиционного дефекта; поэтому система не должна советовать менять фон или дистанцию до восстановления резкости.",
                pauseActionText: "Зафиксируй камеру, дождись резкости и пересними кадр.",
                liveActionType: nil,
                semanticActionTypes: []
            )
        }

        if hasReadableHotspotPressure {
            return ContextualSemanticCorrection(
                idSuffix: "readable_hotspot_angle",
                traceId: "contextual_readable_hotspot_angle",
                verdict: .needsFix,
                confidence: 0.80,
                liveText: "Яркое пятно перетягивает взгляд — смени угол или убери источник блика.",
                pauseSummary: "Кадр читается, но пересвеченный участок спорит с главным объектом",
                whyProblematic: "Экспозиция уже требует снижения, а небольшой читаемый объект не перекрывает яркий фоновой акцент; поэтому позитивное подтверждение было бы ложным.",
                pauseActionText: "Смести точку съёмки или убери яркий источник на фоне, чтобы взгляд вернулся к объекту.",
                liveActionType: .changeAngle,
                semanticActionTypes: [.removeBackgroundHotspot, .changeCameraAngle]
            )
        }

        if hasReadableLargeHotspotPressure {
            return ContextualSemanticCorrection(
                idSuffix: "readable_large_hotspot_angle",
                traceId: "contextual_readable_large_hotspot_angle",
                verdict: .needsFix,
                confidence: 0.80,
                liveText: "Яркая зона перетягивает кадр — смени угол и добавь мягкий свет.",
                pauseSummary: "Крупная читаемая область спорит с пересвеченным фоном",
                whyProblematic: "Главный объект занимает много места, но сильный пересвет делает кадр плоским и уводит внимание от формы.",
                pauseActionText: "Смени угол к источнику света и добавь мягкий фронтальный свет, чтобы вернуть детали.",
                liveActionType: .changeAngle,
                semanticActionTypes: [.removeBackgroundHotspot, .changeCameraAngle, .addFrontFillLight]
            )
        }

        if hasUnknownHotspotPressure {
            return ContextualSemanticCorrection(
                idSuffix: "unknown_hotspot_angle",
                traceId: "contextual_unknown_hotspot_angle",
                verdict: .needsFix,
                confidence: 0.78,
                liveText: "Пересвет мешает найти центр — смени угол съёмки.",
                pauseSummary: "Яркое пятно мешает системе выделить главный объект",
                whyProblematic: "Субъект не закреплён, а экспозиционный перекос уже указывает на сильный световой дефект.",
                pauseActionText: "Смести камеру или убери яркий источник из кадра, чтобы вернуть читаемый центр.",
                liveActionType: .changeAngle,
                semanticActionTypes: [.removeBackgroundHotspot, .changeCameraAngle]
            )
        }

        if hasUnknownLargeUnderexposedSubjectPressure {
            return ContextualSemanticCorrection(
                idSuffix: "unknown_large_underexposed_subject",
                traceId: "contextual_unknown_large_underexposed_subject",
                verdict: .needsFix,
                confidence: 0.78,
                liveText: "Крупный объект провален в темноту — добавь мягкий свет и разверни к источнику.",
                pauseSummary: "Система видит большую область, но не может уверенно прочитать субъект из-за света",
                whyProblematic: "Кадр выглядит как крупный план без читаемого центра: большая область занимает полкадра, а экспозиция и шум требуют восстановления света.",
                pauseActionText: "Добавь мягкий фронтальный свет или разверни объект к источнику, чтобы лицо/форма стали читаемыми.",
                liveActionType: .improveFrontLight,
                semanticActionTypes: [.addFrontFillLight, .rotateSubjectTowardLight]
            )
        }

        if hasReadableSmallStabilizedClutterPressure {
            return ContextualSemanticCorrection(
                idSuffix: "small_stabilized_clutter",
                traceId: "contextual_small_stabilized_clutter",
                verdict: .needsFix,
                confidence: 0.76,
                liveText: "Мелкий объект тонет в лишних деталях — убери помехи и упрости фон.",
                pauseSummary: "Главный объект читается, но композицию забивают посторонние элементы",
                whyProblematic: "Субъект слишком мал для уверенного keep, а несколько объектов и сигнал стабилизации показывают случайную перегрузку кадра.",
                pauseActionText: "Убери отвлекающие предметы или дождись чистого фона вокруг объекта.",
                liveActionType: .reduceBackgroundDistractions,
                semanticActionTypes: [.removeDistractingObject, .simplifyBackground]
            )
        }

        if hasReadableSyntheticGlarePressure {
            return ContextualSemanticCorrection(
                idSuffix: "readable_synthetic_glare",
                traceId: "contextual_readable_synthetic_glare",
                verdict: .needsFix,
                confidence: 0.76,
                liveText: "Яркий объект слепит и режет кадр — смени угол и отойди на шаг.",
                pauseSummary: "Световой объект даёт плоский пересвет и тесный crop",
                whyProblematic: "Небольшой яркий объект слишком агрессивно доминирует в кадре: система не должна подтверждать такую композицию как готовую.",
                pauseActionText: "Смести точку съёмки, убери пересвеченный источник из доминирующего положения и дай кадру больше воздуха.",
                liveActionType: .changeAngle,
                semanticActionTypes: [.removeBackgroundHotspot, .changeCameraAngle, .stepBack]
            )
        }

        if hasTinyReadableUnderexposurePressure {
            return ContextualSemanticCorrection(
                idSuffix: "tiny_readable_underexposure_front_fill",
                traceId: "contextual_tiny_readable_underexposure_front_fill",
                verdict: .needsFix,
                confidence: 0.80,
                liveText: "Малый объект провален в темноту — добавь мягкий свет.",
                pauseSummary: "Главный объект найден, но он слишком тёмный для уверенного кадра",
                whyProblematic: "Субъект занимает мало места и сильный минус по экспозиции делает подтверждение кадра ложным.",
                pauseActionText: "Добавь мягкий фронтальный свет или разверни объект к источнику света.",
                liveActionType: .improveFrontLight,
                semanticActionTypes: [.addFrontFillLight, .rotateSubjectTowardLight]
            )
        }

        if hasHighKeyReadableWeakSubjectPressure {
            let semanticActions: [SemanticActionType] = snapshot.composition.subjectAreaRatio < 0.10
                ? [.stepCloser, .shiftFrameDown]
                : [.stepCloser, .simplifyBackground]
            return ContextualSemanticCorrection(
                idSuffix: "high_key_readable_weak_subject",
                traceId: "contextual_high_key_readable_weak_subject",
                verdict: .mixed,
                confidence: 0.78,
                liveText: "Главный объект теряется в светлом кадре — подойди ближе.",
                pauseSummary: "Кадр слишком светлый и главный объект композиционно слабый",
                whyProblematic: "Субъект найден, но светлый фон и слабая доля объекта делают совет «оставить как есть» слишком оптимистичным.",
                pauseActionText: "Подойди ближе и собери кадр вокруг главного объекта, убрав лишнюю пустоту.",
                liveActionType: .increaseSubjectSize,
                semanticActionTypes: semanticActions
            )
        }

        if hasLargeDetectorWeakSubjectPressure {
            return ContextualSemanticCorrection(
                idSuffix: "large_detector_weak_subject_step_closer",
                traceId: "contextual_large_detector_weak_subject_step_closer",
                verdict: .mixed,
                confidence: 0.76,
                liveText: "Система цепляется за фон — подойди ближе к настоящему объекту.",
                pauseSummary: "Детектор нашёл крупную область, но композиционный центр всё ещё слабый",
                whyProblematic: "Большая найденная область при слабой резкости и низкой эстетике похожа на ложный foreground, а не на уверенный главный объект.",
                pauseActionText: "Подойди ближе к настоящему субъекту и пересобери кадр вокруг него.",
                liveActionType: .increaseSubjectSize,
                semanticActionTypes: [.stepCloser]
            )
        }

        if hasReadableNeutralDenseClutterPressure {
            return ContextualSemanticCorrection(
                idSuffix: "neutral_dense_clutter",
                traceId: "contextual_neutral_dense_clutter",
                verdict: .needsFix,
                confidence: 0.78,
                liveText: "Передний план и фон спорят — упрости сцену.",
                pauseSummary: "Кадр перегружен объектами и не выглядит как намеренный low-key стиль",
                whyProblematic: "Несколько объектов, нейтральная экспозиция и низкая устойчивость горизонта указывают на случайный визуальный шум, а не на сохранённую стилизацию.",
                pauseActionText: "Убери отвлекающий объект, упрости фон или немного смени угол съёмки.",
                liveActionType: .reduceBackgroundDistractions,
                semanticActionTypes: [.removeDistractingObject, .simplifyBackground, .waitForBackgroundClearance, .changeCameraAngle]
            )
        }

        if hasReadableSmallForegroundObstructionPressure {
            return ContextualSemanticCorrection(
                idSuffix: "small_foreground_obstruction",
                traceId: "contextual_small_foreground_obstruction",
                verdict: .needsFix,
                confidence: 0.78,
                liveText: "Мелкий объект теряется за помехами — дождись чистого фона.",
                pauseSummary: "Передний план перекрывает слабый композиционный центр",
                whyProblematic: "Субъект занимает слишком мало места, а несколько объектов в кадре мешают системе уверенно выделить главный центр.",
                pauseActionText: "Убери помеху из переднего плана или дождись более свободного фона.",
                liveActionType: .reduceBackgroundDistractions,
                semanticActionTypes: [.removeDistractingObject, .waitForBackgroundClearance, .shiftFrameLeft]
            )
        }

        if hasTightReadableEdgePressure {
            return ContextualSemanticCorrection(
                idSuffix: "tight_readable_edge_step_back",
                traceId: "contextual_tight_readable_edge_step_back",
                verdict: .needsFix,
                confidence: 0.78,
                liveText: "Объект упирается в край — отойди на шаг и смести кадр вправо.",
                pauseSummary: "Главный объект слишком тесно прижат к рамке",
                whyProblematic: "Читаемый объект занимает почти весь кадр: такой crop легко режет важные части и оставляет слишком мало воздуха вокруг формы.",
                pauseActionText: "Отойди назад и немного смести рамку вправо, чтобы вернуть объекту воздух.",
                liveActionType: .changeAngle,
                semanticActionTypes: [.stepBack, .shiftFrameRight]
            )
        }

        if hasReadableSmallEdgeCropPressure {
            var semanticActions: [SemanticActionType] = [.stepBack, .shiftFrameRight, .removeDistractingObject]
            if futureActions.contains(TechnicalQualityActionType.reduceExposure.rawValue)
                || snapshot.lighting.exposureBiasHint > 0.10 {
                semanticActions.append(.removeBackgroundHotspot)
                semanticActions.append(.changeCameraAngle)
            }
            return ContextualSemanticCorrection(
                idSuffix: "small_edge_crop_step_back",
                traceId: "contextual_small_edge_crop_step_back",
                verdict: .needsFix,
                confidence: 0.78,
                liveText: "Объект режется краем — отойди и смести рамку вправо.",
                pauseSummary: "Малый читаемый объект слишком близко к краю кадра",
                whyProblematic: "При небольшой площади субъекта край кадра начинает работать как помеха: объект читается, но композиция выглядит случайно обрезанной.",
                pauseActionText: "Отойди на шаг, смести рамку вправо и убери отвлекающий крайний объект.",
                liveActionType: .changeAngle,
                semanticActionTypes: semanticActions
            )
        }

        if hasStrongReadableUnderexposurePressure {
            return ContextualSemanticCorrection(
                idSuffix: "strong_readable_underexposure_front_fill",
                traceId: "contextual_strong_readable_underexposure_front_fill",
                verdict: .needsFix,
                confidence: 0.78,
                liveText: "Объект тонет в темноте — добавь мягкий свет спереди.",
                pauseSummary: "Главный объект читается, но сильно недосвечен",
                whyProblematic: "Субъект найден, однако сильный минус по экспозиции и запрос на увеличение света означают, что позитивное подтверждение будет ложным.",
                pauseActionText: "Добавь мягкий фронтальный свет или разверни объект к источнику света.",
                liveActionType: .improveFrontLight,
                semanticActionTypes: [.addFrontFillLight, .rotateSubjectTowardLight]
            )
        }

        if hasReadableSyntheticCrookedPressure {
            return ContextualSemanticCorrection(
                idSuffix: "readable_synthetic_crooked_horizon",
                traceId: "contextual_readable_synthetic_crooked_horizon",
                verdict: .mixed,
                confidence: 0.72,
                liveText: "Кадр кажется заваленным — выровняй камеру перед дублем.",
                pauseSummary: "Ориентация кадра выглядит неустойчивой и случайной",
                whyProblematic: "Главный объект найден слишком слабо или слишком мелко для уверенной композиции, поэтому системе нельзя подтверждать текущий наклон кадра.",
                pauseActionText: "Выравни горизонт и пересними без случайного завала камеры.",
                liveActionType: .levelHorizon,
                semanticActionTypes: [.levelHorizon]
            )
        }

        if hasWeakReadableSubjectPressure {
            return ContextualSemanticCorrection(
                idSuffix: "weak_readable_subject_step_closer",
                traceId: "contextual_weak_readable_subject_step_closer",
                verdict: .mixed,
                confidence: 0.74,
                liveText: "Главный объект теряется — подойди ближе.",
                pauseSummary: "Объект найден, но композиционно слишком слабый",
                whyProblematic: "Субъект занимает мало полезной площади, а технические сигналы просят фокус/стабилизацию: лучше собрать кадр ближе к объекту.",
                pauseActionText: "Подойди ближе или кадрируй плотнее вокруг главного объекта.",
                liveActionType: .increaseSubjectSize,
                semanticActionTypes: [.stepCloser]
            )
        }

        if hasReadableSyntheticSmallSubjectPressure {
            return ContextualSemanticCorrection(
                idSuffix: "readable_synthetic_small_subject",
                traceId: "contextual_readable_synthetic_small_subject",
                verdict: .mixed,
                confidence: 0.74,
                liveText: "Главный объект слишком слабый — подойди ближе.",
                pauseSummary: "Субъект найден, но в кадре он всё ещё слишком мелкий",
                whyProblematic: "Даже при найденном объекте сцена тратит слишком много площади на пустоту или второстепенные детали, поэтому позитивное подтверждение будет ложным.",
                pauseActionText: "Подойди ближе или собери более плотное кадрирование вокруг главного объекта.",
                liveActionType: .increaseSubjectSize,
                semanticActionTypes: [.stepCloser]
            )
        }

        if hasReadableBackgroundClutterPressure {
            return ContextualSemanticCorrection(
                idSuffix: "readable_background_clutter",
                traceId: "contextual_readable_background_clutter",
                verdict: .needsFix,
                confidence: 0.78,
                liveText: "Фон спорит с объектом — упрости задний план.",
                pauseSummary: "Фон перегружен и конкурирует с главным объектом",
                whyProblematic: "Объект читается, но несколько фоновых элементов и низкая эстетическая оценка делают текущую композицию слишком шумной.",
                pauseActionText: "Убери лишние детали вокруг объекта или смени точку съёмки на более чистый фон.",
                liveActionType: .reduceBackgroundDistractions,
                semanticActionTypes: [.simplifyBackground, .removeDistractingObject]
            )
        }

        if hasReadableSyntheticClutterPressure {
            return ContextualSemanticCorrection(
                idSuffix: "readable_synthetic_clutter",
                traceId: "contextual_readable_synthetic_clutter",
                verdict: .needsFix,
                confidence: 0.76,
                liveText: "Фон и передний план спорят с объектом — упрости сцену.",
                pauseSummary: "Кадр композиционно шумный: объект зажат фоном и лишними деталями",
                whyProblematic: "Несколько объектов и слабая иерархия внимания делают кадр перегруженным, даже если детектор всё ещё находит главный объект.",
                pauseActionText: "Убери отвлекающие предметы или дождись более чистого момента вокруг объекта.",
                liveActionType: .reduceBackgroundDistractions,
                semanticActionTypes: [.simplifyBackground, .removeDistractingObject]
            )
        }

        if hasUnknownGroupFramingPressure {
            return ContextualSemanticCorrection(
                idSuffix: "unknown_group_framing",
                traceId: "contextual_unknown_group_framing",
                verdict: .mixed,
                confidence: 0.70,
                liveText: "Нет ясного центра — упрости фон и смести кадр вправо.",
                pauseSummary: "Событие читается, но кадру не хватает главного центра",
                whyProblematic: "Система не находит надёжный субъект, а широкий establishing-паттерн и конкуренция фокуса говорят, что нужен более явный центр внимания.",
                pauseActionText: "Упрости фон и смести рамку вправо, чтобы собрать сцену вокруг главного центра.",
                liveActionType: .reduceBackgroundDistractions,
                semanticActionTypes: [.simplifyBackground, .shiftFrameRight]
            )
        }

        if hasUnknownNoisyLowLightStepBackPressure {
            return ContextualSemanticCorrection(
                idSuffix: "unknown_noisy_low_light_step_back",
                traceId: "contextual_unknown_noisy_low_light_step_back",
                verdict: .mixed,
                confidence: 0.70,
                liveText: "Сцена шумит и тесная — отойди на шаг и зафиксируй камеру.",
                pauseSummary: "Кадр читается как тесный low-light момент без надёжного центра",
                whyProblematic: "Шум, слабый свет и отсутствие найденного субъекта делают крупный план ненадёжным: лучше дать сцене больше воздуха и переснять стабильнее.",
                pauseActionText: "Отойди на шаг, стабилизируй камеру и пересними с более читаемой дистанции.",
                liveActionType: .changeAngle,
                semanticActionTypes: [.stepBack]
            )
        }

        if hasWideUnknownWeakSubjectStepCloserPressure {
            return ContextualSemanticCorrection(
                idSuffix: "wide_unknown_weak_subject_step_closer",
                traceId: "contextual_wide_unknown_weak_subject_step_closer",
                verdict: .mixed,
                confidence: 0.74,
                liveText: "Главный объект слишком слабый — подойди ближе перед снимком.",
                pauseSummary: "Сцена слишком широкая для уверенного главного объекта",
                whyProblematic: "Субъект не найден, но есть слабый объектный сигнал и запрос на стабилизацию: композиции нужен более явный центр.",
                pauseActionText: "Подойди ближе к предполагаемому субъекту и пересобери кадр вокруг него.",
                liveActionType: .increaseSubjectSize,
                semanticActionTypes: [.stepCloser]
            )
        }

        if hasUnknownNoSubjectUnderexposurePressure {
            let hasOcclusionPressure = futureActions.contains(TechnicalQualityActionType.avoidOcclusion.rawValue)
            let semanticActions: [SemanticActionType] = hasOcclusionPressure
                ? [.addFrontFillLight, .changeCameraAngle, .removeDistractingObject]
                : [.addFrontFillLight, .changeCameraAngle, .rotateSubjectTowardLight]
            return ContextualSemanticCorrection(
                idSuffix: "unknown_no_subject_underexposure",
                traceId: "contextual_unknown_no_subject_underexposure",
                verdict: .needsFix,
                confidence: 0.76,
                liveText: "Объект тонет в темноте — добавь мягкий свет спереди.",
                pauseSummary: "Система не может уверенно прочитать объект из-за провала по свету",
                whyProblematic: "Когда субъект вообще не закрепляется в сцене, а технические сигналы просят поднять экспозицию, подтверждать композицию нельзя.",
                pauseActionText: "Добавь мягкий фронтальный свет или разверни сцену к более читаемому источнику света.",
                liveActionType: .improveFrontLight,
                semanticActionTypes: semanticActions
            )
        }

        if hasUnknownNoSubjectHotspotPressure {
            return ContextualSemanticCorrection(
                idSuffix: "unknown_no_subject_hotspot",
                traceId: "contextual_unknown_no_subject_hotspot",
                verdict: .needsFix,
                confidence: 0.76,
                liveText: "Яркое пятно ломает кадр — смени угол съёмки.",
                pauseSummary: "Пересвеченный акцент не даёт системе выделить главный объект",
                whyProblematic: "Сцена распадается на яркий фон и слабый субъект, поэтому позитивное подтверждение было бы ложным.",
                pauseActionText: "Смести камеру или убери яркий источник из фона, чтобы кадр снова получил читаемый центр.",
                liveActionType: .changeAngle,
                semanticActionTypes: [.removeBackgroundHotspot, .changeCameraAngle]
            )
        }

        if hasUnknownNoSubjectClutterPressure {
            return ContextualSemanticCorrection(
                idSuffix: "unknown_no_subject_clutter",
                traceId: "contextual_unknown_no_subject_clutter",
                verdict: .needsFix,
                confidence: 0.74,
                liveText: "Сцена без ясного центра — убери помехи из кадра.",
                pauseSummary: "Фон или передний план перекрывают главный центр внимания",
                whyProblematic: "Система не закрепляет субъект, а технические сигналы подтверждают нестабильную читаемость: такой кадр нельзя маркировать как готовый.",
                pauseActionText: "Убери отвлекающий передний план, дождись более чистого фона и пересобери сцену вокруг одного центра.",
                liveActionType: .reduceBackgroundDistractions,
                semanticActionTypes: [.removeDistractingObject, .simplifyBackground, .waitForBackgroundClearance]
            )
        }

        if hasFlashTightGroupStepBackPressure {
            return ContextualSemanticCorrection(
                idSuffix: "flash_tight_group_step_back",
                traceId: "contextual_flash_tight_group_step_back",
                verdict: .needsFix,
                confidence: 0.78,
                liveText: "Слишком тесно и жёсткий свет — отойди на шаг.",
                pauseSummary: "Жёсткий свет и тесная дистанция перегружают кадр",
                whyProblematic: "Крупный световой объект, тесная область субъекта и шумный фон указывают на близкую вспышку/групповой момент, где смена угла не даёт достаточно воздуха.",
                pauseActionText: "Отойди на шаг, зафиксируй камеру и снизь влияние жёсткого света.",
                liveActionType: .changeAngle,
                semanticActionTypes: [.stepBack]
            )
        }

        if hasLargeColorCastObjectPressure {
            return ContextualSemanticCorrection(
                idSuffix: "large_color_cast_object_front_fill",
                traceId: "contextual_large_color_cast_object_front_fill",
                verdict: .mixed,
                confidence: 0.74,
                liveText: "Цветной свет съедает детали — добавь мягкий фронтальный свет.",
                pauseSummary: "Главный объект слишком доминирует, но детали теряются в цветном свете",
                whyProblematic: "Объект занимает почти весь кадр, а слабая эстетическая оценка и технические сигналы говорят, что проблема в читаемости света, а не в фоне.",
                pauseActionText: "Добавь мягкий фронтальный свет или снизь жёсткий цветной источник, сохранив крупность объекта.",
                liveActionType: .improveFrontLight,
                semanticActionTypes: [.addFrontFillLight]
            )
        }

        if isUnknownSubject,
           !subjectReadable,
           aestheticScore < 0.39,
           objectCount == 0,
           hasStabilizationPressure,
           !hasRefocusPressure {
            return ContextualSemanticCorrection(
                idSuffix: "unknown_stabilized_technical_silence",
                traceId: "contextual_unknown_stabilized_technical_silence",
                verdict: .needsFix,
                confidence: 0.70,
                liveText: "Сцена нестабильна — сначала зафиксируй камеру.",
                pauseSummary: "Главный объект не найден, а кадр требует стабилизации",
                whyProblematic: "Когда субъект не читается и технический сигнал просит стабилизацию, позитивное подтверждение будет ложным.",
                pauseActionText: "Стабилизируй камеру и заново выбери главный центр кадра.",
                liveActionType: nil,
                semanticActionTypes: []
            )
        }

        if isUnknownSubject,
           !subjectReadable,
           aestheticScore < 0.39,
           objectCount > 0,
           futureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue) {
            return ContextualSemanticCorrection(
                idSuffix: "unknown_dark_technical_silence",
                traceId: "contextual_unknown_dark_technical_silence",
                verdict: .needsFix,
                confidence: 0.86,
                liveText: "Главный объект не читается — сначала поправь свет или стабилизацию.",
                pauseSummary: "Система не видит надёжный главный объект",
                whyProblematic: "Слабый свет и отсутствие читаемого субъекта делают позитивное подтверждение ложным сигналом.",
                pauseActionText: "Сначала восстанови техническую читаемость кадра, затем оцени композицию заново.",
                liveActionType: nil,
                semanticActionTypes: []
            )
        }

        if hasUnreadableLowLightSingleObjectPressure {
            return ContextualSemanticCorrection(
                idSuffix: "unreadable_low_light_step_closer_fill",
                traceId: "contextual_unreadable_low_light_step_closer_fill",
                verdict: .needsFix,
                confidence: 0.75,
                liveText: "Объект не читается — подойди ближе и добавь мягкий свет.",
                pauseSummary: "Главный объект слишком мал и тёмен для уверенного разбора",
                whyProblematic: "Система не видит надёжный субъект, а низкая экспозиция и запрос на фокус говорят, что кадр нужно пересобрать ближе к объекту.",
                pauseActionText: "Подойди ближе к главному объекту и добавь мягкий фронтальный свет.",
                liveActionType: .increaseSubjectSize,
                semanticActionTypes: [.addFrontFillLight, .stepCloser]
            )
        }

        if hasUnknownBlurBackgroundPressure {
            return ContextualSemanticCorrection(
                idSuffix: "unknown_blur_simplify_background",
                traceId: "contextual_unknown_blur_simplify_background",
                verdict: .needsFix,
                confidence: 0.86,
                liveText: "Сцена смазана и без центра — упрости фон перед повтором.",
                pauseSummary: "Кадр не даёт надёжный главный объект",
                whyProblematic: "Когда субъект не найден, а технический сигнал просит стабилизацию или фокус, фон становится главным источником шума.",
                pauseActionText: "Упрости фон, зафиксируй камеру и заново выбери главный объект.",
                liveActionType: .reduceBackgroundDistractions,
                semanticActionTypes: [.simplifyBackground]
            )
        }

        if subjectReadable,
           primarySubjectConfidence < 0.31,
           (semantics.sceneType == .unknown || sceneTypeConfidence <= 0.05),
           aestheticScore < 0.42 {
            let confidence = shouldUseHighConfidenceForWeakSubjectBackground(
                snapshot: snapshot,
                objectCount: objectCount,
                subjectArea: subjectArea
            ) ? 0.86 : 0.70
            return ContextualSemanticCorrection(
                idSuffix: "weak_subject_background",
                traceId: "contextual_weak_subject_background",
                verdict: .mixed,
                confidence: confidence,
                liveText: "Нет ясного центра — упрости фон и выбери главный объект.",
                pauseSummary: "Сцена читается слабо: фон и объект конкурируют",
                whyProblematic: "Низкая уверенность в субъекте и неизвестный тип сцены означают, что «оставить как есть» будет переоценкой кадра.",
                pauseActionText: "Убери лишние детали вокруг объекта или перестрой кадр вокруг одного центра.",
                liveActionType: .reduceBackgroundDistractions,
                semanticActionTypes: [.simplifyBackground]
            )
        }

        if subjectReadable,
           objectCount >= 3,
           hasStabilizationPressure,
           aestheticScore < 0.42,
           (subjectArea < 0.14 || subjectArea > 0.60) {
            return ContextualSemanticCorrection(
                idSuffix: "motion_like_false_keep",
                traceId: "contextual_motion_like_false_keep",
                verdict: .needsFix,
                confidence: 0.86,
                liveText: "Кадр читается нестабильно — сначала зафиксируй сцену.",
                pauseSummary: "Позитивное подтверждение скрывало техническую нестабильность",
                whyProblematic: "Несколько объектов, слабая эстетическая оценка и запрос на стабилизацию не дают основания говорить, что кадр готов.",
                pauseActionText: "Стабилизируй камеру и проверь резкость перед композиционными советами.",
                liveActionType: nil,
                semanticActionTypes: []
            )
        }

        if aestheticScore < 0.405,
           subjectArea >= 0.50,
           objectCount >= 2 {
            var semanticActions: [SemanticActionType] = [.simplifyBackground]
            if objectCount >= 4 || subjectLabel == "light" || subjectLabel == "chair" {
                semanticActions.append(.waitForBackgroundClearance)
            }
            return ContextualSemanticCorrection(
                idSuffix: "dark_object_cluster",
                traceId: "contextual_dark_object_cluster",
                verdict: .needsFix,
                confidence: 0.78,
                liveText: "Фон перегружен — упрости задний план или дождись просвета.",
                pauseSummary: "Кадр выглядит перегруженным: главный объект конкурирует с тёмным фоном",
                whyProblematic: "Несколько крупных объектов и слабый свет делают сцену шумной: позитивное подтверждение здесь было бы слишком уверенным.",
                pauseActionText: "Убери лишние детали фона или подожди, пока фон станет свободнее.",
                liveActionType: .reduceBackgroundDistractions,
                semanticActionTypes: semanticActions
            )
        }

        if aestheticScore < 0.405,
           snapshot.lighting.exposureBiasHint <= -1.70,
           objectCount >= 3,
           subjectArea >= 0.25,
           !shouldRespectReadableObjectInsertPreservation(snapshot: snapshot, semantics: semantics),
           futureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue) {
            return ContextualSemanticCorrection(
                idSuffix: "underlit_readable_object",
                traceId: "contextual_underlit_readable_object",
                verdict: .mixed,
                confidence: 0.70,
                liveText: "Темновато — добавь мягкий свет на главный объект.",
                pauseSummary: "Кадр читается, но главный объект недосвечен",
                whyProblematic: "Объект уже найден, но сильный минус по экспозиции и низкая общая оценка света делают совет «оставить как есть» ненадёжным.",
                pauseActionText: "Добавь мягкий фронтальный или боковой свет, не меняя композицию резко.",
                liveActionType: .improveFrontLight,
                semanticActionTypes: [.addFrontFillLight]
            )
        }

        if hasReadableUnderlitObjectPressure {
            return ContextualSemanticCorrection(
                idSuffix: "readable_underlit_object_front_fill",
                traceId: "contextual_readable_underlit_object_front_fill",
                verdict: .mixed,
                confidence: 0.74,
                liveText: "Объект читается, но ему нужен мягкий фронтальный свет.",
                pauseSummary: "Главный объект найден, но он недосвечен",
                whyProblematic: "Субъект читается и занимает заметную часть кадра, однако отрицательная экспозиция делает позитивное подтверждение слишком оптимистичным.",
                pauseActionText: "Добавь мягкий фронтальный свет, сохранив текущую композицию.",
                liveActionType: .improveFrontLight,
                semanticActionTypes: [.addFrontFillLight]
            )
        }

        if hasLowAestheticObjectClearancePressure {
            return ContextualSemanticCorrection(
                idSuffix: "low_aesthetic_object_clearance",
                traceId: "contextual_low_aesthetic_object_clearance",
                verdict: .mixed,
                confidence: 0.74,
                liveText: "Объект есть, но фон спорит — упрости сцену или дождись просвета.",
                pauseSummary: "Один объект найден, но кадр всё ещё перегружен фоном",
                whyProblematic: "Низкая эстетическая оценка и средний размер объекта говорят, что проблема не в приближении, а в фоне и моменте.",
                pauseActionText: "Упрости фон или дождись более чистого момента вокруг объекта.",
                liveActionType: .reduceBackgroundDistractions,
                semanticActionTypes: [.simplifyBackground, .waitForBackgroundClearance]
            )
        }

        if subjectReadable,
           semantics.primarySubject.kind == .object,
           aestheticScore < 0.405,
           snapshot.lighting.exposureBiasHint <= -1.45,
           subjectArea < 0.18,
           (hasRefocusPressure || hasStabilizationPressure) {
            if subjectLabel == "light",
               !semantics.dominance.hasClearFocus {
                return ContextualSemanticCorrection(
                    idSuffix: "small_underlit_light_hotspot",
                    traceId: "contextual_small_underlit_light_hotspot",
                    verdict: .needsFix,
                    confidence: 0.86,
                    liveText: "Световое пятно забивает кадр — смени угол и убери hotspot.",
                    pauseSummary: "Кадр тёмный, а яркий источник перетягивает внимание с субъекта",
                    whyProblematic: "Детектор цепляется за небольшой световой объект без уверенного фокуса; в таком случае проблема не только в недосвете, но и в доминирующем блике.",
                    pauseActionText: "Смести камеру от яркого источника, убери hotspot из кадра и при необходимости добавь мягкий фронтальный свет.",
                    liveActionType: .changeAngle,
                    semanticActionTypes: [.removeBackgroundHotspot, .changeCameraAngle, .addFrontFillLight]
                )
            }

            return ContextualSemanticCorrection(
                idSuffix: "small_underlit_light_object",
                traceId: "contextual_small_underlit_light_object",
                verdict: .needsFix,
                confidence: 0.86,
                liveText: "Объект теряется в темноте — добавь мягкий фронтальный свет.",
                pauseSummary: "Главный объект слишком тёмный и малый",
                whyProblematic: "Объект найден, но площадь субъекта мала, экспозиция сильно просела и технические сигналы требуют стабилизации или перефокуса.",
                pauseActionText: "Подсвети главный объект мягким фронтальным светом, не меняя композицию резко.",
                liveActionType: .improveFrontLight,
                semanticActionTypes: [.addFrontFillLight]
            )
        }

        if subjectReadable,
           objectCount == 1,
           aestheticScore < 0.37,
           subjectArea < 0.22 {
            return ContextualSemanticCorrection(
                idSuffix: "low_aesthetic_single_object_crowd",
                traceId: "contextual_low_aesthetic_single_object_crowd",
                verdict: .needsFix,
                confidence: 0.86,
                liveText: "Фон и момент мешают — упрости сцену или дождись чище кадра.",
                pauseSummary: "Один найденный объект не делает кадр композиционно готовым",
                whyProblematic: "Низкая общая оценка кадра и небольшой субъект требуют очистить сцену, а не подтверждать текущую композицию.",
                pauseActionText: "Выбери более чистый момент или освободи фон вокруг объекта.",
                liveActionType: .reduceBackgroundDistractions,
                semanticActionTypes: [.simplifyBackground, .waitForBackgroundClearance]
            )
        }

        return nil
    }

    private func shouldTreatAsTechnicalOnlySoftness(snapshot: FrameFeatureSnapshot,
                                                    semantics: SceneSemanticsReport,
                                                    futureActions: Set<String>) -> Bool {
        guard semantics.readability.subjectReadable,
              snapshot.composition.subjectAreaRatio >= 0.60,
              (snapshot.composition.subjectAreaRatio < 0.90 || snapshot.objects.totalCount >= 2),
              semantics.dominance.backgroundClutterScore < 0.35,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore < 0.40 else {
            return false
        }
        let hasTechnicalFuture = futureActions.contains(where: {
            $0 == TechnicalQualityActionType.stabilizeCamera.rawValue ||
                $0 == TechnicalQualityActionType.reduceIsoNoise.rawValue ||
                $0 == TechnicalQualityActionType.refocusSubject.rawValue
        })
        return hasTechnicalFuture || snapshot.lighting.exposureBiasHint <= -0.70
    }

    private func shouldCorrectTightReadableEdge(snapshot: FrameFeatureSnapshot,
                                                semantics: SceneSemanticsReport) -> Bool {
        guard semantics.readability.subjectReadable,
              snapshot.objects.totalCount >= 1,
              snapshot.composition.subjectAreaRatio >= 0.82,
              semantics.dominance.backgroundClutterScore <= 0.35 else {
            return false
        }
        let aestheticScore = snapshot.aesthetics.score ?? 1.0
        return (snapshot.composition.subjectAreaRatio >= 0.95
            && semantics.dominance.backgroundClutterScore <= 0.18)
            || (
                snapshot.composition.subjectAreaRatio < 0.92
                    && snapshot.objects.totalCount >= 2
                    && snapshot.lighting.exposureBiasHint <= -0.30
                    && semantics.dominance.backgroundClutterScore <= 0.24
                    && aestheticScore < 0.44
            )
    }

    private func shouldCorrectStrongReadableUnderexposure(snapshot: FrameFeatureSnapshot,
                                                          semantics: SceneSemanticsReport,
                                                          futureActions: Set<String>) -> Bool {
        guard semantics.readability.subjectReadable,
              snapshot.objects.totalCount == 1,
              semantics.dominance.backgroundClutterScore <= 0.22,
              (0.22...0.35).contains(snapshot.composition.subjectAreaRatio),
              snapshot.lighting.exposureBiasHint <= -1.35,
              semantics.primarySubject.confidence >= 0.70,
              futureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue) else {
            return false
        }
        let aestheticScore = snapshot.aesthetics.score ?? 1.0
        return snapshot.lighting.exposureBiasHint <= -2.50
            && (aestheticScore < 0.46 || semantics.primarySubject.confidence < 0.60)
    }

    private func shouldCorrectWeakReadableSubject(snapshot: FrameFeatureSnapshot,
                                                  semantics: SceneSemanticsReport,
                                                  futureActions: Set<String>) -> Bool {
        guard semantics.readability.subjectReadable,
              semantics.primarySubject.kind == .object,
              (0.20...0.30).contains(snapshot.composition.subjectAreaRatio),
              snapshot.objects.totalCount >= 2 else {
            return false
        }
        guard semantics.dominance.focusCompetitionScore >= 0.45 else {
            return false
        }
        let hasTechnicalProminencePressure = futureActions.contains(TechnicalQualityActionType.refocusSubject.rawValue)
            || futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue)
            || futureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue)
        let aestheticScore = snapshot.aesthetics.score ?? 1.0
        return (hasTechnicalProminencePressure && aestheticScore < 0.44)
            || semantics.dominance.backgroundClutterScore >= 0.38
    }

    private func shouldCorrectReadableBackgroundClutter(snapshot: FrameFeatureSnapshot,
                                                        semantics: SceneSemanticsReport) -> Bool {
        guard semantics.readability.subjectReadable,
              snapshot.objects.totalCount >= 2,
              semantics.dominance.backgroundClutterScore >= 0.45,
              snapshot.composition.subjectAreaRatio < 0.18,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore < 0.37 else {
            return false
        }
        return !semantics.dominance.hasClearFocus
    }

    private func shouldCorrectReadableHotspot(snapshot: FrameFeatureSnapshot,
                                              semantics: SceneSemanticsReport,
                                              futureActions: Set<String>) -> Bool {
        guard semantics.readability.subjectReadable,
              snapshot.lighting.exposureBiasHint >= 0.35,
              snapshot.composition.subjectAreaRatio <= 0.22,
              snapshot.objects.totalCount <= 2,
              !shouldRespectReadableObjectInsertPreservation(snapshot: snapshot, semantics: semantics),
              semantics.dominance.backgroundClutterScore <= 0.30 else {
            return false
        }
        let hasMeasuredExposurePressure = futureActions.contains(TechnicalQualityActionType.reduceExposure.rawValue)
        return hasMeasuredExposurePressure
            && snapshot.lighting.exposureBiasHint >= 0.60
            && (semantics.primarySubject.confidence >= 0.55 || semantics.dominance.hasClearFocus)
    }

    private func shouldCorrectReadableLargeHotspot(snapshot: FrameFeatureSnapshot,
                                                   semantics: SceneSemanticsReport) -> Bool {
        guard semantics.readability.subjectReadable,
              snapshot.lighting.exposureBiasHint >= 0.50,
              snapshot.composition.subjectAreaRatio >= 0.45,
              snapshot.horizon.confidence >= 0.70,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore < 0.44 else {
            return false
        }
        return true
    }

    private func shouldCorrectUnknownHotspot(snapshot: FrameFeatureSnapshot,
                                             semantics: SceneSemanticsReport) -> Bool {
        guard semantics.primarySubject.kind == .unknown,
              !semantics.readability.subjectReadable,
              snapshot.lighting.exposureBiasHint >= 0.60,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore < 0.43 else {
            return false
        }
        return true
    }

    private func shouldCorrectUnknownLargeUnderexposedSubject(snapshot: FrameFeatureSnapshot,
                                                              semantics: SceneSemanticsReport,
                                                              futureActions: Set<String>) -> Bool {
        guard semantics.primarySubject.kind == .unknown,
              !semantics.readability.subjectReadable,
              snapshot.objects.totalCount == 1,
              snapshot.composition.subjectAreaRatio >= 0.45,
              semantics.sceneType == .unknown,
              semantics.dominance.backgroundClutterScore <= 0.16,
              semantics.dominance.focusCompetitionScore >= 0.50,
              snapshot.lighting.exposureBiasHint <= -2.0,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore >= 0.40,
              aestheticScore < 0.47 else {
            return false
        }

        return futureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue)
            && futureActions.contains(TechnicalQualityActionType.reduceIsoNoise.rawValue)
    }

    private func shouldCorrectReadableSmallStabilizedClutter(snapshot: FrameFeatureSnapshot,
                                                             semantics: SceneSemanticsReport,
                                                             futureActions: Set<String>) -> Bool {
        guard semantics.readability.subjectReadable,
              semantics.primarySubject.kind == .object,
              semantics.sceneType == .objectInsert,
              semantics.dominance.hasClearFocus,
              snapshot.objects.totalCount >= 2,
              snapshot.composition.subjectAreaRatio < 0.07,
              semantics.dominance.backgroundClutterScore >= 0.24,
              semantics.dominance.backgroundClutterScore <= 0.32,
              semantics.dominance.focusCompetitionScore <= 0.30,
              semantics.primarySubject.confidence >= 0.65,
              semantics.sceneTypeConfidence >= 0.75,
              snapshot.lighting.exposureBiasHint > -0.20,
              snapshot.lighting.exposureBiasHint < 0.30,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore >= 0.42,
              aestheticScore < 0.46 else {
            return false
        }

        return futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue)
            && !futureActions.contains(TechnicalQualityActionType.refocusSubject.rawValue)
    }

    private func shouldCorrectHighKeyReadableWeakSubject(snapshot: FrameFeatureSnapshot,
                                                         semantics: SceneSemanticsReport) -> Bool {
        guard semantics.readability.subjectReadable,
              semantics.primarySubject.kind == .object,
              snapshot.lighting.exposureBiasHint >= 0.45,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore >= 0.48 else {
            return false
        }
        let subjectArea = snapshot.composition.subjectAreaRatio
        let isSmallHighKeySubject = snapshot.objects.totalCount >= 2
            && subjectArea < 0.10
        let isMidHighKeySubject = snapshot.objects.totalCount <= 2
            && (0.24...0.34).contains(subjectArea)
            && snapshot.lighting.exposureBiasHint >= 0.65
        return isSmallHighKeySubject || isMidHighKeySubject
    }

    private func shouldCorrectLargeDetectorWeakSubject(snapshot: FrameFeatureSnapshot,
                                                       semantics: SceneSemanticsReport,
                                                       futureActions: Set<String>) -> Bool {
        guard semantics.readability.subjectReadable,
              semantics.primarySubject.kind == .object,
              snapshot.composition.subjectAreaRatio >= 0.95,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore < 0.43 else {
            return false
        }
        return futureActions.contains(TechnicalQualityActionType.refocusSubject.rawValue)
            || futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue)
            || futureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue)
    }

    private func shouldCorrectReadableNeutralDenseClutter(snapshot: FrameFeatureSnapshot,
                                                          semantics: SceneSemanticsReport) -> Bool {
        guard semantics.readability.subjectReadable,
              semantics.primarySubject.kind == .object,
              snapshot.objects.totalCount >= 3,
              semantics.dominance.backgroundClutterScore >= 0.30,
              snapshot.lighting.exposureBiasHint > -0.25,
              snapshot.horizon.confidence <= 0.20,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore < 0.44 else {
            return false
        }
        return true
    }

    private func shouldCorrectReadableSmallForegroundObstruction(snapshot: FrameFeatureSnapshot,
                                                                 semantics: SceneSemanticsReport,
                                                                 futureActions: Set<String>) -> Bool {
        guard semantics.readability.subjectReadable,
              semantics.primarySubject.kind == .object,
              snapshot.objects.totalCount >= 2,
              snapshot.composition.subjectAreaRatio < 0.08,
              snapshot.lighting.exposureBiasHint > -0.05,
              !futureActions.contains(TechnicalQualityActionType.refocusSubject.rawValue),
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore < 0.42 else {
            return false
        }
        return true
    }

    private func shouldCorrectReadableSmallEdgeCrop(snapshot: FrameFeatureSnapshot,
                                                    semantics: SceneSemanticsReport,
                                                    futureActions: Set<String>) -> Bool {
        guard semantics.readability.subjectReadable,
              semantics.primarySubject.kind == .object,
              snapshot.objects.totalCount <= 1,
              snapshot.composition.subjectAreaRatio < 0.09,
              snapshot.horizon.confidence <= 0.20,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore < 0.405 else {
            return false
        }
        let subjectLabel = semantics.primarySubject.label?.lowercased() ?? ""
        return subjectLabel != "light"
    }

    private func shouldCorrectTinyReadableUnderexposure(snapshot: FrameFeatureSnapshot,
                                                        semantics: SceneSemanticsReport) -> Bool {
        guard semantics.readability.subjectReadable,
              semantics.primarySubject.kind == .object,
              snapshot.lighting.exposureBiasHint <= -2.50,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore < 0.42 else {
            return false
        }
        return true
    }

    private func shouldCorrectReadableSyntheticSmallSubject(snapshot: FrameFeatureSnapshot,
                                                            semantics: SceneSemanticsReport,
                                                            futureActions: Set<String>) -> Bool {
        guard semantics.readability.subjectReadable,
              semantics.primarySubject.kind == .object else {
            return false
        }
        let subjectLabel = semantics.primarySubject.label?.lowercased() ?? ""
        guard subjectLabel != "light" else { return false }
        let subjectArea = snapshot.composition.subjectAreaRatio
        let aestheticScore = snapshot.aesthetics.score ?? 1.0
        let hasTechnicalProminencePressure = futureActions.contains(TechnicalQualityActionType.refocusSubject.rawValue)
            || futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue)
            || futureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue)

        if shouldRespectHighAestheticCinematicSmallSubject(snapshot: snapshot, semantics: semantics) {
            return false
        }

        if subjectArea <= 0.26
            && snapshot.objects.totalCount <= 2
            && hasTechnicalProminencePressure
            && aestheticScore >= 0.48
            && aestheticsLooksArtificiallyWide(snapshot: snapshot, semantics: semantics) {
            return true
        }

        return subjectArea >= 0.20
            && subjectArea <= 0.26
            && snapshot.objects.totalCount >= 3
            && semantics.dominance.backgroundClutterScore >= 0.40
            && aestheticScore >= 0.48
    }

    private func shouldRespectHighAestheticCinematicSmallSubject(snapshot: FrameFeatureSnapshot,
                                                                 semantics: SceneSemanticsReport) -> Bool {
        guard semantics.readability.subjectReadable,
              semantics.primarySubject.kind == .object,
              semantics.dominance.hasClearFocus,
              semantics.sceneType == .objectInsert,
              semantics.sceneTypeConfidence >= 0.80,
              semantics.primarySubject.confidence >= 0.70,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore >= 0.54 else {
            return false
        }

        return (0.09...0.13).contains(snapshot.composition.subjectAreaRatio)
            && snapshot.objects.totalCount <= 2
            && semantics.dominance.backgroundClutterScore <= 0.30
            && semantics.dominance.focusCompetitionScore <= 0.25
            && snapshot.lighting.exposureBiasHint >= 0.20
            && snapshot.lighting.exposureBiasHint < 0.50
    }

    private func shouldCorrectReadableSyntheticClutter(snapshot: FrameFeatureSnapshot,
                                                       semantics: SceneSemanticsReport) -> Bool {
        guard semantics.readability.subjectReadable,
              snapshot.objects.totalCount >= 2,
              !shouldRespectReadableObjectInsertPreservation(snapshot: snapshot, semantics: semantics),
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore < 0.46 else {
            return false
        }
        return (0.28...0.40).contains(snapshot.composition.subjectAreaRatio)
            && semantics.dominance.backgroundClutterScore >= 0.30
            && aestheticScore >= 0.43
            && snapshot.lighting.exposureBiasHint <= -1.70
    }

    private func shouldCorrectReadableSyntheticCrooked(snapshot: FrameFeatureSnapshot,
                                                       semantics: SceneSemanticsReport,
                                                       futureActions: Set<String>) -> Bool {
        guard semantics.readability.subjectReadable,
              semantics.primarySubject.kind == .object,
              snapshot.objects.totalCount <= 2,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore <= 0.50 else {
            return false
        }

        if snapshot.composition.subjectAreaRatio < 0.08,
           semantics.primarySubject.confidence < 0.50,
           !semantics.dominance.hasClearFocus,
           ((semantics.sceneType == .unknown
                && snapshot.objects.totalCount == 1
                && aestheticScore >= 0.46)
                || (snapshot.horizon.confidence >= 0.55
                    && snapshot.lighting.exposureBiasHint <= -2.0)) {
            return true
        }

        return snapshot.composition.subjectAreaRatio >= 0.30
            && snapshot.composition.subjectAreaRatio <= 0.42
            && futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue)
            && futureActions.contains(TechnicalQualityActionType.refocusSubject.rawValue)
            && futureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue)
            && snapshot.lighting.exposureBiasHint <= -1.10
            && snapshot.horizon.confidence >= 0.40
            && aestheticScore < 0.44
    }

    private func shouldCorrectReadableSyntheticGlareObject(snapshot: FrameFeatureSnapshot,
                                                           semantics: SceneSemanticsReport,
                                                           futureActions: Set<String>) -> Bool {
        guard semantics.readability.subjectReadable,
              semantics.primarySubject.kind == .object,
              snapshot.objects.totalCount == 1,
              snapshot.composition.subjectAreaRatio < 0.12,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore < 0.40 else {
            return false
        }
        let subjectLabel = semantics.primarySubject.label?.lowercased() ?? ""
        return (subjectLabel == "light"
            || futureActions.contains(TechnicalQualityActionType.reduceExposure.rawValue))
            && snapshot.lighting.exposureBiasHint >= 0.10
            && !futureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue)
    }

    private func shouldCorrectUnknownNoSubjectUnderexposure(snapshot: FrameFeatureSnapshot,
                                                            semantics: SceneSemanticsReport,
                                                            futureActions: Set<String>) -> Bool {
        let resemblesCleanUnknownEstablishing = shouldRespectCleanUnknownEstablishingFrame(
            snapshot: snapshot,
            semantics: semantics
        )
        guard semantics.primarySubject.kind == .unknown,
              !semantics.readability.subjectReadable,
              snapshot.objects.totalCount == 0,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore < 0.56,
              futureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue),
              !futureActions.contains(TechnicalQualityActionType.refocusSubject.rawValue),
              !snapshot.technicalFlags.contains(.highMotion),
              !shouldRespectLowKeyGoodUnknownFrame(snapshot: snapshot, semantics: semantics) else {
            return false
        }
        if resemblesCleanUnknownEstablishing {
            return false
        }
        let hasVisibilityRecoveryPressure = futureActions.contains(TechnicalQualityActionType.reduceIsoNoise.rawValue)
            || futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue)
            || futureActions.contains(TechnicalQualityActionType.avoidOcclusion.rawValue)
        return hasVisibilityRecoveryPressure
            && (aestheticScore < 0.50 || snapshot.lighting.exposureBiasHint <= -1.0)
    }

    private func shouldCorrectUnknownNoSubjectHotspot(snapshot: FrameFeatureSnapshot,
                                                      semantics: SceneSemanticsReport,
                                                      futureActions: Set<String>) -> Bool {
        guard semantics.primarySubject.kind == .unknown,
              !semantics.readability.subjectReadable,
              snapshot.objects.totalCount == 0,
              let aestheticScore = snapshot.aesthetics.score,
              (0.42...0.46).contains(aestheticScore),
              !snapshot.technicalFlags.contains(.highMotion),
              !shouldRespectLowKeyGoodUnknownFrame(snapshot: snapshot, semantics: semantics),
              futureActions.contains(TechnicalQualityActionType.reduceExposure.rawValue) else {
            return false
        }
        return true
    }

    private func shouldCorrectUnknownNoSubjectClutterOrOcclusion(snapshot: FrameFeatureSnapshot,
                                                                 semantics: SceneSemanticsReport,
                                                                 futureActions: Set<String>) -> Bool {
        let resemblesCleanUnknownEstablishing = shouldRespectCleanUnknownEstablishingFrame(
            snapshot: snapshot,
            semantics: semantics
        )
        guard semantics.primarySubject.kind == .unknown,
              !semantics.readability.subjectReadable,
              snapshot.objects.totalCount <= 1,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore >= 0.42,
              aestheticScore < 0.50,
              !snapshot.technicalFlags.contains(.highMotion),
              !shouldRespectLowKeyGoodUnknownFrame(snapshot: snapshot, semantics: semantics) else {
            return false
        }
        let hasOcclusionPressure = futureActions.contains(TechnicalQualityActionType.avoidOcclusion.rawValue)
        let hasTechnicalAmbiguity = futureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue)
            || futureActions.contains(TechnicalQualityActionType.reduceIsoNoise.rawValue)
            || futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue)
            || futureActions.contains(TechnicalQualityActionType.refocusSubject.rawValue)
        if resemblesCleanUnknownEstablishing && !hasOcclusionPressure && !futureActions.contains(TechnicalQualityActionType.refocusSubject.rawValue) {
            return false
        }
        let hasZeroSubjectSyntheticOcclusion = snapshot.objects.totalCount == 0
            && (futureActions.contains(TechnicalQualityActionType.refocusSubject.rawValue)
                || hasOcclusionPressure)
        let hasSingleObjectOcclusion = snapshot.objects.totalCount == 1
        return hasOcclusionPressure
            && hasTechnicalAmbiguity
            && ((hasSingleObjectOcclusion && semantics.dominance.backgroundClutterScore >= 0.14)
                || hasZeroSubjectSyntheticOcclusion)
    }

    private func aestheticsLooksArtificiallyWide(snapshot: FrameFeatureSnapshot,
                                                 semantics: SceneSemanticsReport) -> Bool {
        snapshot.composition.subjectAreaRatio <= 0.26
            && semantics.primarySubject.confidence >= 0.70
            && semantics.dominance.backgroundClutterScore <= 0.30
    }

    private func shouldRespectReadableObjectInsertPreservation(snapshot: FrameFeatureSnapshot,
                                                               semantics: SceneSemanticsReport) -> Bool {
        guard semantics.readability.subjectReadable,
              semantics.primarySubject.kind == .object,
              semantics.sceneType == .objectInsert else {
            return false
        }

        let aestheticScore = snapshot.aesthetics.score ?? 0
        let subjectArea = snapshot.composition.subjectAreaRatio
        let objectCount = snapshot.objects.totalCount
        let backgroundClutter = semantics.dominance.backgroundClutterScore
        let focusCompetition = semantics.dominance.focusCompetitionScore
        let exposureBias = snapshot.lighting.exposureBiasHint
        let hasStrongInsertClassification = semantics.sceneTypeConfidence >= 0.80
            && semantics.primarySubject.confidence >= 0.70
        let hasCleanReadableInsert = semantics.dominance.hasClearFocus
            && semantics.sceneTypeConfidence >= 0.72
            && semantics.primarySubject.confidence >= 0.60
            && aestheticScore >= 0.45
            && objectCount <= 2
            && subjectArea >= 0.24
            && subjectArea <= 0.35
            && backgroundClutter <= 0.16
            && focusCompetition <= 0.26
            && exposureBias < 0.75
        guard hasStrongInsertClassification || hasCleanReadableInsert else {
            return false
        }

        return aestheticScore >= 0.39
            && objectCount <= 3
            && subjectArea >= 0.16
            && subjectArea <= 0.34
            && backgroundClutter <= 0.34
            && focusCompetition <= 0.30
            && exposureBias > -1.95
            && exposureBias < 0.75
    }

    private func shouldRespectLowKeyGoodUnknownFrame(snapshot: FrameFeatureSnapshot,
                                                     semantics: SceneSemanticsReport) -> Bool {
        guard semantics.primarySubject.kind == .unknown,
              !semantics.readability.subjectReadable else {
            return false
        }
        return snapshot.objects.totalCount == 0
            && snapshot.composition.subjectAreaRatio <= 0.001
            && (snapshot.aesthetics.score ?? 0) >= 0.38
            && snapshot.lighting.exposureBiasHint <= -0.70
    }

    private func shouldRespectCleanUnknownEstablishingFrame(snapshot: FrameFeatureSnapshot,
                                                            semantics: SceneSemanticsReport) -> Bool {
        guard semantics.primarySubject.kind == .unknown,
              !semantics.readability.subjectReadable,
              semantics.sceneType == .establishingLikeFrame else {
            return false
        }
        let isNarrativeWideEstablishing = snapshot.objects.totalCount <= 1
            && snapshot.subjectSignals.personCount == 0
            && snapshot.composition.subjectAreaRatio <= 0.02
            && semantics.dominance.backgroundClutterScore <= 0.12
            && semantics.sceneTypeConfidence >= 0.50
            && semantics.dominance.focusCompetitionScore <= 0.56
            && snapshot.lighting.exposureBiasHint > -1.60
            && snapshot.lighting.exposureBiasHint < 0.20
        guard isNarrativeWideEstablishing else {
            return false
        }
        let aestheticScore = snapshot.aesthetics.score ?? 0
        if snapshot.objects.totalCount == 0 {
            return aestheticScore >= 0.42
        }
        return aestheticScore >= 0.42
    }

    private func shouldUseHighConfidenceForWeakSubjectBackground(snapshot: FrameFeatureSnapshot,
                                                                 objectCount: Int,
                                                                 subjectArea: Double) -> Bool {
        objectCount == 1 &&
            subjectArea < 0.10 &&
            snapshot.lighting.exposureBiasHint <= -1.20
    }

    private func contextualPauseActionRows(for correction: ContextualSemanticCorrection) -> [PauseActionRow] {
        correction.semanticActionTypes.enumerated().map { index, semanticAction in
            PauseActionRow(
                actionId: "act_\(correction.idSuffix)_\(semanticAction.rawValue)",
                actionType: actionType(for: semanticAction),
                semanticActionType: semanticAction,
                priority: index + 1,
                confidence: correction.confidence,
                linkedIssueIds: [],
                expectedOutcome: expectedOutcome(for: semanticAction, correction: correction),
                targetRegion: nil,
                overlayHintId: nil,
                traceRefId: correction.traceId
            )
        }
    }

    private func actionType(for semanticAction: SemanticActionType) -> ActionTypeV1 {
        switch semanticAction {
        case .addFrontFillLight:
            return .improveFrontLight
        case .simplifyBackground, .waitForBackgroundClearance, .removeDistractingObject:
            return .reduceBackgroundDistractions
        case .stepCloser:
            return .increaseSubjectSize
        case .stepBack:
            return .changeAngle
        case .shiftFrameLeft:
            return .moveFrameLeft
        case .shiftFrameRight:
            return .moveFrameRight
        case .shiftFrameUp:
            return .moveFrameUp
        case .shiftFrameDown:
            return .moveFrameDown
        case .rotateSubjectTowardLight:
            return .improveFrontLight
        default:
            return .changeAngle
        }
    }

    private func expectedOutcome(for semanticAction: SemanticActionType,
                                 correction: ContextualSemanticCorrection) -> String {
        switch semanticAction {
        case .addFrontFillLight:
            return "Главный объект станет читаемее, а композиция сохранится."
        case .simplifyBackground:
            return "Меньше фоновых деталей будет конкурировать с главным объектом."
        case .waitForBackgroundClearance:
            return "Свободный фон отделит объект от визуального шума."
        case .removeDistractingObject:
            return "Отвлекающий предмет перестанет конкурировать с главным объектом."
        case .stepCloser:
            return "Главный объект станет заметнее и легче читаемым."
        case .stepBack:
            return "В кадре появится больше воздуха, а жёсткий крупный план станет спокойнее."
        case .shiftFrameRight:
            return "Смещение рамки вправо вернёт воздух у края кадра."
        case .shiftFrameLeft:
            return "Смещение рамки влево вернёт воздух у края кадра."
        case .rotateSubjectTowardLight:
            return "Поворот к свету сделает главный объект читаемее."
        default:
            return correction.pauseActionText
        }
    }

    private func pauseActionConfidence(for action: RecommendationAction,
                                       plan: RecommendationPlan,
                                       critique: CritiqueReport,
                                       linkedIssueIds: [String]? = nil) -> Double {
        let issueIds = linkedIssueIds ?? action.linkedIssueIds
        let linkedIssueConfidence = critique.issues
            .filter { issueIds.contains($0.id) }
            .map(\.confidence)
            .max()
        let dependencyConfidence = linkedIssueConfidence ?? critique.verdictConfidence
        return min(1.0, max(0.0, min(plan.planConfidence, dependencyConfidence + 0.10)))
    }

    @MainActor
    private func currentSemanticLiveTipKey() -> String? {
        guard let id = currentLiveHint?.id else { return nil }
        let prefix = "lh_live_sem_"
        guard id.hasPrefix(prefix) else { return nil }
        return String(id.dropFirst(prefix.count))
    }

    private func makePauseReasoningRequest(frameId: String,
                                           critique: CritiqueReport,
                                           plan: RecommendationPlan,
                                           pauseDraft: PauseCritiquePresentation,
                                           trace: ExplainabilityTraceBundle?) -> ReasoningRequest {
        let requestId = "reasoning_\(frameId)_\(Int(Date().timeIntervalSince1970 * 1000))"
        let providerConfigVersion = ProcessInfo.processInfo.environment["CAMERA_REASONING_PROVIDER"] ?? "disabled"
        return ReasoningRequest(
            requestId: requestId,
            frameId: frameId,
            mode: .pause,
            locale: Locale.current.identifier,
            critique: critique,
            plan: plan,
            trace: trace,
            pausePresentationDraft: pauseDraft,
            constraints: .pauseDefault,
            correlation: ReasoningCorrelation(
                pipelineVersion: "camera_analysis_v1",
                contractVersion: "camera_analysis_contracts_v1",
                providerConfigVersion: providerConfigVersion
            )
        )
    }

    private func resolvePauseVisualEvidence(snapshot: FrameFeatureSnapshot,
                                            semantics: SceneSemanticsReport,
                                            critique: CritiqueReport,
                                            plan: RecommendationPlan,
                                            neuralOutcome: NeuralEvidenceRecordedOutcome?) async -> VisualEvidenceCoordinatorResult {
        let request = makePauseVisualEvidenceRequest(
            snapshot: snapshot,
            semantics: semantics,
            critique: critique,
            plan: plan,
            neuralOutcome: neuralOutcome
        )
        return await visualSemanticEvidenceCoordinator.fetchEvidence(request: request)
    }

    private func makePauseVisualEvidenceRequest(snapshot: FrameFeatureSnapshot,
                                                semantics: SceneSemanticsReport,
                                                critique: CritiqueReport,
                                                plan: RecommendationPlan,
                                                neuralOutcome: NeuralEvidenceRecordedOutcome?) -> VLMVisualEvidenceRequest {
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        let requestId = "vlm_evd_\(snapshot.frameId)_\(nowMs)"
        let providerConfigVersion = ProcessInfo.processInfo.environment["CAMERA_VLM_VISUAL_EVIDENCE_PROVIDER"] ?? "disabled"
        let allowRedactedVisual = isEnabledEnvironmentFlag("CAMERA_VLM_VISUAL_EVIDENCE_ALLOW_VISUAL_INPUT")
        let configuredPrivacyTier = ProcessInfo.processInfo.environment["CAMERA_VLM_VISUAL_EVIDENCE_PRIVACY_TIER"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let useRedactedVisual = allowRedactedVisual && configuredPrivacyTier == VLMPrivacyTier.redactedVisual.rawValue
        let privacyTier: VLMPrivacyTier = useRedactedVisual ? .redactedVisual : .structuredOnly
        let visualInput: VLMVisualInput? = useRedactedVisual
            ? VLMVisualInput(
                attachmentKind: .redactedStill,
                mediaRef: "redacted://\(snapshot.frameId)",
                longEdgePx: 768,
                exifStripped: true,
                redactionApplied: true,
                redactionNotes: ["subject_only_redacted_still"]
            )
            : nil
        let trigger: VLMTrigger = useRedactedVisual ? .explicitUserRequest : .ambiguousLocalCase
        let localContext = VLMVisualEvidenceLocalContext(
            frameFeatureSnapshotExcerpt: makeFrameFeatureSnapshotExcerpt(snapshot: snapshot),
            sceneSemantics: semantics,
            critique: critique,
            recommendationPlan: plan,
            semanticTipDrafts: makeSemanticTipDrafts(critique: critique, plan: plan, semantics: semantics),
            groundedEntities: makeGroundedEntities(snapshot: snapshot, semantics: semantics, critique: critique),
            localNeuralEvidenceSummary: makeNeuralEvidenceSummary(from: neuralOutcome)
        )

        return VLMVisualEvidenceRequest(
            schemaVersion: .s1,
            requestId: requestId,
            frameId: snapshot.frameId,
            mode: .pause,
            locale: Locale.current.identifier,
            privacyTier: privacyTier,
            trigger: trigger,
            visualInput: visualInput,
            localContext: localContext,
            allowedCatalog: .prS01,
            constraints: .default,
            correlation: VLMVisualEvidenceCorrelation(
                localCritiqueSummaryId: critique.summary.id,
                localPlanSummaryId: plan.primaryAction?.id,
                semanticCatalogVersion: VLMAllowedSemanticCatalog.prS01.catalogVersion,
                offloadingSchemaVersion: "h12",
                providerConfigVersion: providerConfigVersion,
                sessionEphemeralId: "pause-\(snapshot.frameId)"
            )
        )
    }

    private func makeFrameFeatureSnapshotExcerpt(snapshot: FrameFeatureSnapshot) -> [String: String] {
        [
            "mode": snapshot.mode.rawValue,
            "scene_subject_kind": snapshot.subjectSignals.faceDetected ? "face" : (snapshot.subjectSignals.personDetected ? "person" : "object_or_unknown"),
            "subject_area_ratio": String(format: "%.3f", snapshot.composition.subjectAreaRatio),
            "edge_pressure": String(format: "%.3f", abs(snapshot.composition.horizontalOffset)),
            "backlight_index": String(format: "%.3f", snapshot.lighting.backlightIndex),
            "object_count": "\(snapshot.objects.totalCount)"
        ]
    }

    private func makeSemanticTipDrafts(critique: CritiqueReport,
                                       plan: RecommendationPlan,
                                       semantics: SceneSemanticsReport) -> [SemanticTipDraftContext] {
        let issuesById = Dictionary(uniqueKeysWithValues: critique.issues.map { ($0.id, $0) })
        let actions = [plan.primaryAction].compactMap { $0 } + plan.secondaryActions + plan.deferredActions

        return actions.enumerated().map { index, action in
            let issue = action.linkedIssueIds.first.flatMap { issuesById[$0] }
            let semanticActionType = semanticActionType(for: action.actionType)
            let target = defaultDraftTarget(for: action, issue: issue, semantics: semantics)
            let label = SemanticDisplayLabelPolicy.displayLabel(
                entityKind: target.kind,
                role: target.role,
                groundedLabel: nil,
                confidence: 0.0
            )

            return SemanticTipDraftContext(
                draftId: "draft_\(plan.mode.rawValue)_\(index)_\(semanticActionType.rawValue)",
                tipType: nil,
                actionType: semanticActionType,
                actionFrame: semanticActionFrame(for: semanticActionType),
                targetEntityRef: target.entityRef,
                targetEntityKind: vlmEntityKind(for: target.kind),
                targetEntityDisplayLabel: label,
                linkedIssueIds: action.linkedIssueIds,
                linkedStrengthIds: [],
                linkedActionIds: [action.id],
                priorityBand: nil
            )
        }
    }

    private func defaultDraftTarget(for action: RecommendationAction,
                                    issue: FrameIssue?,
                                    semantics: SceneSemanticsReport) -> (kind: TargetEntityKind, role: TargetEntityRole, entityRef: String?) {
        switch action.actionType {
        case .moveFrameLeft, .moveFrameRight, .moveFrameUp, .moveFrameDown, .changeAngle:
            if issue?.type == .backgroundCompetesWithSubject || issue?.type == .frameVisuallyOverloaded {
                return (.backgroundArea, .backgroundZone, "ent-background")
            }
            return (.frame, .wholeFrame, "ent-frame")
        case .increaseSubjectSize:
            let kind = targetEntityKind(for: semantics.primarySubject.kind)
            return (kind, .primarySubject, "ent-primary-subject")
        case .reduceBackgroundDistractions:
            return (.backgroundArea, .backgroundZone, "ent-background")
        case .improveFrontLight:
            return (.lightSource, .lightTarget, "ent-light")
        case .levelHorizon:
            return (.frame, .wholeFrame, "ent-frame")
        case .leaveFrameAsIs:
            return (.frame, .wholeFrame, "ent-frame")
        }
    }

    private func makeGroundedEntities(snapshot: FrameFeatureSnapshot,
                                      semantics: SceneSemanticsReport,
                                      critique: CritiqueReport) -> [VLMGroundedEntity] {
        var entities: [VLMGroundedEntity] = []

        let subjectKind = targetEntityKind(for: semantics.primarySubject.kind)
        let subjectLabel = SemanticDisplayLabelPolicy.displayLabel(
            entityKind: subjectKind,
            role: .primarySubject,
            groundedLabel: nil,
            confidence: semantics.primarySubject.confidence
        )
        entities.append(
            VLMGroundedEntity(
                entityRef: "ent-primary-subject",
                kind: vlmEntityKind(for: subjectKind),
                role: .primarySubject,
                region: semantics.primarySubject.region,
                detectorLabel: semantics.primarySubject.label,
                detectorConfidence: semantics.primarySubject.confidence,
                displayLabelCandidate: subjectLabel,
                displayLabelConfidence: semantics.primarySubject.confidence
            )
        )

        if let objectLabel = snapshot.subjectSignals.topObjectLabel {
            let groundedLabel = groundedObjectLabelCandidate(from: objectLabel)
            let objectConfidence = snapshot.subjectSignals.topObjectConfidence ?? 0.60
            let displayLabel = SemanticDisplayLabelPolicy.displayLabel(
                entityKind: .object,
                role: .foregroundObject,
                groundedLabel: groundedLabel,
                confidence: objectConfidence
            )

            entities.append(
                VLMGroundedEntity(
                    entityRef: "ent-top-object",
                    kind: .object,
                    role: .foregroundObject,
                    region: nil,
                    detectorLabel: objectLabel,
                    detectorConfidence: objectConfidence,
                    displayLabelCandidate: displayLabel,
                    displayLabelConfidence: objectConfidence
                )
            )
        }

        if critique.issues.contains(where: { $0.type == .backgroundCompetesWithSubject || $0.type == .frameVisuallyOverloaded }) {
            entities.append(
                VLMGroundedEntity(
                    entityRef: "ent-background",
                    kind: .backgroundArea,
                    role: .backgroundZone,
                    region: nil,
                    detectorLabel: "background",
                    detectorConfidence: 0.70,
                    displayLabelCandidate: "фон",
                    displayLabelConfidence: 0.70
                )
            )
        }

        if critique.issues.contains(where: { $0.type == .backlightHidesSubject }) {
            entities.append(
                VLMGroundedEntity(
                    entityRef: "ent-light",
                    kind: .lightSource,
                    role: .lightTarget,
                    region: nil,
                    detectorLabel: "light_source",
                    detectorConfidence: 0.60,
                    displayLabelCandidate: "свет",
                    displayLabelConfidence: 0.60
                )
            )
        }

        var seen: Set<String> = []
        return entities.filter { entity in
            if seen.contains(entity.entityRef) {
                return false
            }
            seen.insert(entity.entityRef)
            return true
        }
    }

    private func makeNeuralEvidenceSummary(from outcome: NeuralEvidenceRecordedOutcome?) -> NeuralEvidenceSummary? {
        guard let snapshot = outcome?.snapshot else { return nil }
        let available = snapshot.headOutputs
            .filter { $0.payload.status == .available }
            .map(\.headId)
        let unavailable = snapshot.headOutputs
            .filter { $0.payload.status == .unavailable }
            .map(\.headId)

        let notableScores = snapshot.headOutputs.compactMap { entry -> NeuralEvidenceScoreSummary? in
            switch entry.payload {
            case let .scalar(payload):
                guard payload.status == .available else { return nil }
                return NeuralEvidenceScoreSummary(
                    headId: payload.headId,
                    score: payload.score,
                    confidence: payload.confidence,
                    status: payload.status
                )
            case let .categorical(payload):
                guard payload.status == .available else { return nil }
                return NeuralEvidenceScoreSummary(
                    headId: payload.headId,
                    score: payload.affinities.map(\.score).max(),
                    confidence: payload.confidence,
                    status: payload.status
                )
            }
        }
        .sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }
            return lhs.headId.rawValue < rhs.headId.rawValue
        }

        return NeuralEvidenceSummary(
            schemaVersion: snapshot.schemaVersion,
            availableHeadIds: available,
            unavailableHeadIds: unavailable,
            notableScores: Array(notableScores.prefix(4))
        )
    }

    private func logAndExtractValidatedVisualEvidence(_ result: VisualEvidenceCoordinatorResult,
                                                      frameId: String) -> VLMEvidenceValidationResult? {
        switch result {
        case let .accepted(validation, diagnostics):
            os_log(
                "visual_evidence.accepted frame=%{public}@ reason=%{public}@",
                log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
                type: .debug,
                frameId,
                diagnostics.fallbackReason ?? "ok"
            )
            return validation
        case let .skipped(reason, diagnostics):
            let event = reason == "provider_unavailable"
                ? "visual_evidence.skipped.unavailable"
                : (reason == "policy_blocked" ? "visual_evidence.skipped.policy_blocked" : "visual_evidence.skipped")
            os_log(
                "%{public}@ frame=%{public}@ reason=%{public}@",
                log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
                type: .debug,
                event,
                frameId,
                diagnostics.fallbackReason ?? reason
            )
            return nil
        case let .failed(reason, diagnostics):
            let event: String
            let logType: OSLogType
            if reason == "timeout" {
                event = "visual_evidence.fail.timeout"
                logType = .error
            } else if reason == "canceled_due_to_state_change" {
                event = "visual_evidence.cancel.pause_exit"
                logType = .debug
            } else {
                event = "visual_evidence.fail.runtime"
                logType = .error
            }
            os_log(
                "%{public}@ frame=%{public}@ reason=%{public}@",
                log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
                type: logType,
                event,
                frameId,
                diagnostics.fallbackReason ?? reason
            )
            return nil
        case let .rejected(violations, diagnostics):
            let event = violations.contains(.modeNotPause)
                ? "visual_evidence.policy_violation.mode_not_pause"
                : "visual_evidence.fail.validation"
            os_log(
                "%{public}@ frame=%{public}@ violations=%{public}@ reason=%{public}@",
                log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
                type: .debug,
                event,
                frameId,
                violations.map(\.rawValue).joined(separator: ","),
                diagnostics.fallbackReason ?? "validation_failed"
            )
            return nil
        }
    }

    private func semanticActionType(for actionType: ActionTypeV1) -> SemanticActionType {
        actionType.semanticActionType
    }

    private func semanticActionFrame(for actionType: SemanticActionType) -> SemanticActionFrame {
        switch actionType {
        case .moveSubjectLeft, .moveSubjectRight, .moveSubjectAwayFromBackground, .rotateSubjectTowardLight:
            return .moveSubject
        case .moveObjectLeft, .moveObjectRight, .moveObjectForward, .moveObjectBack, .removeDistractingObject, .repositionPropForBalance:
            return .moveObject
        case .addFrontFillLight, .addBackgroundLight, .removeBackgroundHotspot:
            return .adjustLight
        case .waitForBackgroundClearance:
            return .wait
        default:
            return .moveCamera
        }
    }

    private func targetEntityKind(for subjectKind: SubjectKind) -> TargetEntityKind {
        switch subjectKind {
        case .face:
            return .face
        case .person, .group:
            return .person
        case .object:
            return .object
        case .unknown:
            return .unknown
        }
    }

    private func vlmEntityKind(for targetKind: TargetEntityKind) -> VLMEntityKind {
        switch targetKind {
        case .person:
            return .person
        case .face:
            return .face
        case .object:
            return .object
        case .prop:
            return .prop
        case .backgroundArea:
            return .backgroundArea
        case .lightSource:
            return .lightSource
        case .frame:
            return .frame
        case .unknown:
            return .unknown
        }
    }

    private func groundedObjectLabelCandidate(from detectorLabel: String) -> String? {
        let normalized = detectorLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("vase") { return "ваза" }
        if normalized.contains("flower") { return "цветок" }
        if normalized.contains("book") { return "книга" }
        if normalized.contains("cup") || normalized.contains("mug") { return "чашка" }
        if normalized.contains("bottle") { return "бутылка" }
        if normalized.contains("lamp") { return "лампа" }
        if normalized.contains("chair") { return "стул" }
        if normalized.contains("phone") { return "телефон" }
        return nil
    }

    private func isEnabledEnvironmentFlag(_ key: String) -> Bool {
        guard let rawValue = ProcessInfo.processInfo.environment[key]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else {
            return false
        }
        return rawValue == "1" || rawValue == "true" || rawValue == "yes" || rawValue == "on"
    }

    private func schedulePauseReasoningRefinement(request: ReasoningRequest, revision: Int) {
        pauseReasoningTask?.cancel()
        pauseReasoningTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            let result = await self.pauseReasoningCoordinator.refine(request: request)
            guard !Task.isCancelled else { return }

            switch result {
            case let .skipped(reason, diagnostics):
                let event = reason == "provider_unavailable" ? "reasoning.skipped.unavailable" : "reasoning.skipped"
                os_log(
                    "%{public}@ (%{public}@)",
                    log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
                    type: .debug,
                    event,
                    diagnostics.fallbackReason ?? reason
                )
                return
            case let .failed(reason, diagnostics):
                let event: String
                let logType: OSLogType
                if reason == "timeout" {
                    event = "reasoning.fail.timeout"
                    logType = .error
                } else if reason == "canceled_due_to_state_change" {
                    event = "reasoning.cancel.pause_exit"
                    logType = .debug
                } else {
                    event = "reasoning.fail.runtime"
                    logType = .error
                }
                os_log(
                    "%{public}@ (%{public}@)",
                    log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
                    type: logType,
                    event,
                    diagnostics.fallbackReason ?? reason
                )
                return
            case let .rejected(violations, diagnostics):
                let event = violations.contains(.modeNotPause)
                    ? "reasoning.policy_violation.mode_not_pause"
                    : "reasoning.fail.validation"
                os_log(
                    "%{public}@ (%{public}@), reason=%{public}@",
                    log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
                    type: .debug,
                    event,
                    violations.map(\.rawValue).joined(separator: ","),
                    diagnostics.fallbackReason ?? "validation_failed"
                )
                return
            case let .refined(presentation, optionalTraceItems, diagnostics):
                let isCurrentRevision = self.featureQueue.sync { self.pauseAnalysisRevision == revision }
                guard isCurrentRevision else { return }

                await MainActor.run {
                    guard self.lastRefinedPauseFrameId != request.frameId else { return }
                    guard let current = self.currentPauseCritique, current.frameId == request.frameId else { return }
                    let merged = self.mergePauseCritiqueRefinement(current: current, refined: presentation)
                    guard merged != current else { return }
                    self.currentPauseCritique = merged
                    if let baseTrace = self.currentPauseTraceBundle ?? request.trace,
                       baseTrace.frameId == request.frameId {
                        self.currentPauseTraceBundle = self.mergeOptionalReasoningTrace(
                            optionalTraceItems,
                            into: baseTrace
                        )
                    }
                    self.lastRefinedPauseFrameId = request.frameId
                    os_log(
                        "Applied pause reasoning refinement for frame=%{public}@ (%{public}@)",
                        log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
                        type: .debug,
                        request.frameId,
                        diagnostics.fallbackReason ?? "ok"
                    )
                }
            }
        }
    }

    private func mergePauseCritiqueRefinement(current: PauseCritiquePresentation,
                                              refined: PauseCritiquePresentation) -> PauseCritiquePresentation {
        let refinedStrengthRationales = Dictionary(uniqueKeysWithValues: refined.strengths.map { ($0.strengthId, $0.rationale) })
        let refinedIssueRationales = Dictionary(uniqueKeysWithValues: refined.issues.map { ($0.issueId, $0.rationale) })
        let refinedActionOutcomes = Dictionary(uniqueKeysWithValues: refined.actions.map { ($0.actionId, $0.expectedOutcome) })

        let mergedStrengths = current.strengths.map { row in
            PauseStrengthRow(
                strengthId: row.strengthId,
                type: row.type,
                rationale: refinedStrengthRationales[row.strengthId] ?? row.rationale,
                confidence: row.confidence,
                supportingRegion: row.supportingRegion,
                traceRefId: row.traceRefId
            )
        }
        let mergedIssues = current.issues.map { row in
            PauseIssueRow(
                issueId: row.issueId,
                type: row.type,
                severity: row.severity,
                confidence: row.confidence,
                rationale: refinedIssueRationales[row.issueId] ?? row.rationale,
                affectedRegion: row.affectedRegion,
                suggestedFixTypes: row.suggestedFixTypes,
                traceRefId: row.traceRefId
            )
        }
        let mergedActions = current.actions.map { row in
            PauseActionRow(
                actionId: row.actionId,
                actionType: row.actionType,
                semanticActionType: row.semanticActionType,
                priority: row.priority,
                confidence: row.confidence,
                linkedIssueIds: row.linkedIssueIds,
                expectedOutcome: refinedActionOutcomes[row.actionId] ?? row.expectedOutcome,
                targetRegion: row.targetRegion,
                overlayHintId: row.overlayHintId,
                traceRefId: row.traceRefId
            )
        }

        return PauseCritiquePresentation(
            frameId: current.frameId,
            verdict: current.verdict,
            verdictConfidence: current.verdictConfidence,
            summaryId: current.summaryId,
            shortVerdict: refined.shortVerdict,
            whyGood: refined.whyGood ?? current.whyGood,
            whyProblematic: refined.whyProblematic ?? current.whyProblematic,
            strengths: mergedStrengths,
            issues: mergedIssues,
            actions: mergedActions,
            noChangeRationale: refined.noChangeRationale ?? current.noChangeRationale,
            assumptions: current.assumptions,
            traceRootIds: current.traceRootIds,
            fallbackUsed: current.fallbackUsed
        )
    }

    private func makePauseTraceBundle(critique: CritiqueReport,
                                      plan: RecommendationPlan,
                                      neuralSnapshot: NeuralEvidenceSnapshot?,
                                      fusionOutput: HybridFusionOutput) -> ExplainabilityTraceBundle {
        let bundle = makeTraceBundle(
            critique: critique,
            plan: plan,
            neuralSnapshot: neuralSnapshot,
            fusionOutput: fusionOutput
        )
        if !bundle.validate(critiqueReport: critique, recommendationPlan: plan).isEmpty {
            os_log(
                "pause trace validation failed for frame=%{public}@",
                log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
                type: .error,
                critique.frameId
            )
        }
        return bundle
    }

    private func makeLiveFusionTraceBundle(critique: CritiqueReport,
                                           plan: RecommendationPlan,
                                           neuralSnapshot: NeuralEvidenceSnapshot,
                                           fusionOutput: HybridFusionOutput) -> ExplainabilityTraceBundle? {
        let bundle = makeTraceBundle(
            critique: critique,
            plan: plan,
            neuralSnapshot: neuralSnapshot,
            fusionOutput: fusionOutput
        )
        let validationErrors = bundle.validate(critiqueReport: critique, recommendationPlan: plan)
        if !validationErrors.isEmpty {
            os_log(
                "live fusion trace validation failed for frame=%{public}@",
                log: OSLog(subsystem: "com.multitool2.pipeline", category: "AnalysisPipeline"),
                type: .error,
                critique.frameId
            )
            return nil
        }
        return bundle
    }

    private func makeTraceBundle(critique: CritiqueReport,
                                 plan: RecommendationPlan,
                                 neuralSnapshot: NeuralEvidenceSnapshot?,
                                 fusionOutput: HybridFusionOutput) -> ExplainabilityTraceBundle {
        let baseTimestamp = Int(Date().timeIntervalSince1970 * 1000)
        let frameId = critique.frameId
        let observationId = "trc_\(frameId)_obs_semantics"
        let appliedDecisionByTargetId = Dictionary(
            uniqueKeysWithValues: fusionOutput.appliedDecisions.map { ($0.targetId, $0) }
        )
        let usedHeadIds = fusionOutput.appliedDecisions
            .flatMap(\.appliedHeadIds)
            .sorted { (EvidenceHeadId.allCases.firstIndex(of: $0) ?? .max) < (EvidenceHeadId.allCases.firstIndex(of: $1) ?? .max) }
            .reduce(into: [EvidenceHeadId]()) { ids, headId in
                if !ids.contains(headId) {
                    ids.append(headId)
                }
            }

        var items: [ExplainabilityTraceItem] = [
            ExplainabilityTraceItem(
                id: observationId,
                frameId: frameId,
                mode: critique.mode,
                stage: .observation,
                sourceKind: .semanticsSignal,
                certainty: .probabilistic,
                confidence: 0.95,
                timestampMs: baseTimestamp,
                statement: "Собраны базовые сигналы композиции и читаемости сцены.",
                evidenceKeys: [],
                dependsOn: [],
                links: [],
                audiences: [.core, .debug]
            )
        ]

        var nextTimestamp = baseTimestamp + 10
        var deterministicInterpretationByIssueId: [String: String] = [:]
        var neuralObservationIdByHeadId: [EvidenceHeadId: String] = [:]

        if let neuralSnapshot, !usedHeadIds.isEmpty {
            for headId in usedHeadIds {
                guard let entry = neuralSnapshot.headOutputs.first(where: { $0.headId == headId }) else { continue }
                let neuralObservationId = "trc_\(frameId)_obs_neural_\(headId.rawValue)"
                neuralObservationIdByHeadId[headId] = neuralObservationId
                items.append(
                    ExplainabilityTraceItem(
                        id: neuralObservationId,
                        frameId: frameId,
                        mode: critique.mode,
                        stage: .observation,
                        sourceKind: .neuralEvidence,
                        certainty: .probabilistic,
                        confidence: neuralHeadConfidence(for: entry),
                        timestampMs: nextTimestamp,
                        statement: neuralObservationStatement(for: entry),
                        evidenceKeys: entry.explainabilityKeys,
                        dependsOn: [observationId],
                        links: [],
                        audiences: [.core, .debug, .eval]
                    )
                )
                nextTimestamp += 10
            }
        }

        let issueTraceRefs = critique.traceRefs.filter { $0.contains("_crit_i") }
        for (index, issue) in critique.issues.enumerated() {
            let traceId: String
            if index < issueTraceRefs.count {
                traceId = issueTraceRefs[index]
            } else {
                traceId = "trc_\(frameId)_crit_i\(index + 1)"
            }
            deterministicInterpretationByIssueId[issue.id] = traceId
            let appliedDecision = appliedDecisionByTargetId[issue.id]
            let dependsOn = [observationId] + (appliedDecision?.appliedHeadIds.compactMap { neuralObservationIdByHeadId[$0] } ?? [])
            items.append(
                ExplainabilityTraceItem(
                    id: traceId,
                    frameId: frameId,
                    mode: critique.mode,
                    stage: .interpretation,
                    sourceKind: .deterministicRule,
                    certainty: .deterministic,
                    confidence: issue.confidence,
                    timestampMs: nextTimestamp,
                    statement: issue.rationale,
                    evidenceKeys: issue.evidence.map(\.key),
                    dependsOn: dependsOn,
                    links: [TraceLink(kind: .issue, refId: issue.id)],
                    audiences: [.core, .debug],
                    metadata: fusionMetadata(for: appliedDecision, deterministicConfidence: deterministicIssueConfidence(issueId: issue.id, fusionOutput: fusionOutput, critique: critique))
                )
            )
            nextTimestamp += 10
        }

        let strengthTraceRefs = critique.traceRefs.filter { $0.contains("_crit_s") }
        for (index, strength) in critique.strengths.enumerated() {
            let traceId: String
            if index < strengthTraceRefs.count {
                traceId = strengthTraceRefs[index]
            } else {
                traceId = "trc_\(frameId)_crit_s\(index + 1)"
            }
            let appliedDecision = appliedDecisionByTargetId[strength.id]
            let dependsOn = [observationId] + (appliedDecision?.appliedHeadIds.compactMap { neuralObservationIdByHeadId[$0] } ?? [])
            items.append(
                ExplainabilityTraceItem(
                    id: traceId,
                    frameId: frameId,
                    mode: critique.mode,
                    stage: .interpretation,
                    sourceKind: .deterministicRule,
                    certainty: .deterministic,
                    confidence: strength.confidence,
                    timestampMs: nextTimestamp,
                    statement: strength.rationale,
                    evidenceKeys: strength.evidence.map(\.key),
                    dependsOn: dependsOn,
                    links: [TraceLink(kind: .strength, refId: strength.id)],
                    audiences: [.core, .debug],
                    metadata: fusionMetadata(for: appliedDecision, deterministicConfidence: deterministicStrengthConfidence(strengthId: strength.id, fusionOutput: fusionOutput, critique: critique))
                )
            )
            nextTimestamp += 10
        }

        let summaryTraceId = critique.traceRefs.first(where: { $0.contains("_crit_summary_") })
            ?? "trc_\(frameId)_crit_summary_main"
        let summaryDependsOn = [observationId] + usedHeadIds.compactMap { neuralObservationIdByHeadId[$0] }
        items.append(
            ExplainabilityTraceItem(
                id: summaryTraceId,
                frameId: frameId,
                mode: critique.mode,
                stage: .interpretation,
                sourceKind: .deterministicRule,
                certainty: .deterministic,
                confidence: critique.verdictConfidence,
                timestampMs: nextTimestamp,
                statement: critique.summary.shortVerdict,
                evidenceKeys: [],
                dependsOn: summaryDependsOn,
                links: [TraceLink(kind: .summary, refId: critique.summary.id)],
                audiences: [.core, .debug]
            )
        )
        nextTimestamp += 10

        for (index, action) in allPlanActions(plan).enumerated() {
            let depId = action.linkedIssueIds
                .lazy
                .compactMap { deterministicInterpretationByIssueId[$0] }
                .first ?? summaryTraceId
            let depConfidence = items.first(where: { $0.id == depId })?.confidence ?? critique.verdictConfidence
            let actionConfidence = min(plan.planConfidence, depConfidence + 0.1)

            var links = [TraceLink(kind: .action, refId: action.id)]
            if let overlayId = action.overlayHint?.id {
                links.append(TraceLink(kind: .overlay, refId: overlayId))
            }

            items.append(
                ExplainabilityTraceItem(
                    id: "trc_\(frameId)_rec_a\(index + 1)",
                    frameId: frameId,
                    mode: critique.mode,
                    stage: .recommendation,
                    sourceKind: .plannerPolicy,
                    certainty: .deterministic,
                    confidence: actionConfidence,
                    timestampMs: nextTimestamp,
                    statement: action.expectedOutcome,
                    evidenceKeys: [],
                    dependsOn: [depId],
                    links: links,
                    audiences: [.core, .debug]
                )
            )
            nextTimestamp += 10
        }

        return ExplainabilityTraceBundle(
            frameId: frameId,
            mode: critique.mode,
            items: items,
            rootSummaryIds: [summaryTraceId]
        )
    }

    private func fusionMetadata(for decision: HybridFusionDecision?,
                                deterministicConfidence: Double?) -> [String: String] {
        guard let decision, decision.applied else { return [:] }
        return [
            "fusionApplied": "true",
            "fusionDelta": String(format: "%.4f", decision.delta),
            "deterministicConfidenceBefore": String(format: "%.4f", deterministicConfidence ?? decision.deterministicConfidenceBefore),
            "fusedConfidenceAfter": String(format: "%.4f", decision.fusedConfidenceAfter),
            "appliedHeadIds": decision.appliedHeadIds.map(\.rawValue).joined(separator: ",")
        ]
    }

    private func deterministicIssueConfidence(issueId: String,
                                              fusionOutput: HybridFusionOutput,
                                              critique: CritiqueReport) -> Double? {
        if let appliedDecision = fusionOutput.appliedDecisions.first(where: { $0.targetId == issueId }) {
            return appliedDecision.deterministicConfidenceBefore
        }
        return critique.issues.first(where: { $0.id == issueId })?.confidence
    }

    private func deterministicStrengthConfidence(strengthId: String,
                                                 fusionOutput: HybridFusionOutput,
                                                 critique: CritiqueReport) -> Double? {
        if let appliedDecision = fusionOutput.appliedDecisions.first(where: { $0.targetId == strengthId }) {
            return appliedDecision.deterministicConfidenceBefore
        }
        return critique.strengths.first(where: { $0.id == strengthId })?.confidence
    }

    private func neuralHeadConfidence(for entry: NeuralEvidenceHeadEntry) -> Double {
        switch entry.payload {
        case let .scalar(payload):
            return payload.confidence
        case let .categorical(payload):
            return payload.confidence
        }
    }

    private func neuralObservationStatement(for entry: NeuralEvidenceHeadEntry) -> String {
        switch entry.payload {
        case let .scalar(payload):
            let score = payload.score.map { String(format: "%.2f", $0) } ?? "n/a"
            return "Neural head \(entry.headId.rawValue) observed score \(score)."
        case let .categorical(payload):
            let topCategory = payload.affinities.max(by: { $0.score < $1.score })?.categoryId.rawValue ?? "unknown"
            return "Neural head \(entry.headId.rawValue) favored \(topCategory)."
        }
    }

    private func mergeOptionalReasoningTrace(_ optionalItems: [ExplainabilityTraceItem],
                                             into base: ExplainabilityTraceBundle) -> ExplainabilityTraceBundle {
        guard !optionalItems.isEmpty else { return base }

        let existingIds = Set(base.items.map(\.id))
        var seenIds: Set<String> = []
        let appendableItems = optionalItems.filter { item in
            guard !existingIds.contains(item.id), !seenIds.contains(item.id) else { return false }
            seenIds.insert(item.id)
            return true
        }
        guard !appendableItems.isEmpty else { return base }

        var rootSummaryIds = base.rootSummaryIds
        var knownRootIds = Set(rootSummaryIds)
        for item in appendableItems where item.links.contains(where: { $0.kind == .summary }) {
            if !knownRootIds.contains(item.id) {
                knownRootIds.insert(item.id)
                rootSummaryIds.append(item.id)
            }
        }

        return ExplainabilityTraceBundle(
            frameId: base.frameId,
            mode: base.mode,
            items: base.items + appendableItems,
            rootSummaryIds: rootSummaryIds
        )
    }

    private func allPlanActions(_ plan: RecommendationPlan) -> [RecommendationAction] {
        [plan.primaryAction].compactMap { $0 } + plan.secondaryActions + plan.deferredActions
    }

    private func makeOverlayAnnotations(frameId: String,
                                        critique: CritiqueReport,
                                        plan: RecommendationPlan,
                                        features: CoachingFeatures,
                                        mode: AnalysisMode,
                                        legacySuggestions: [Suggestion],
                                        forceLegacyOnly: Bool = false,
                                        liveHint: LiveHintPresentation? = nil) -> [OverlayAnnotationPresentation] {
        var annotations: [OverlayAnnotationPresentation] = []

        if mode == .live {
            if !currentDemoOverlayAnnotations.isEmpty {
                return currentDemoOverlayAnnotations
            }
            guard let liveHint else { return [] }
            if let actionId = liveHint.actionId,
               let action = allPlanActions(plan).first(where: { $0.id == actionId }),
               let annotation = makeActionAnnotation(frameId: frameId, action: action, critique: critique, mode: mode) {
                return [annotation]
            }
            if liveHint.isFallback {
                return legacySuggestions.prefix(1).enumerated().compactMap { index, suggestion in
                    makeLegacyAnnotation(
                        frameId: frameId,
                        suggestion: suggestion,
                        index: index,
                        features: features,
                        mode: mode,
                        safeDirectionArrowsOnly: true
                    )
                }
            }
            return []
        }

        if !forceLegacyOnly {
            let actions = [plan.primaryAction].compactMap { $0 } + Array(plan.secondaryActions.prefix(2))
            annotations = actions.compactMap { action in
                makeActionAnnotation(frameId: frameId, action: action, critique: critique, mode: mode)
            }
        }

        if annotations.isEmpty && !forceLegacyOnly {
            annotations = critique.issues.prefix(3).compactMap { issue in
                makeStructuredAnnotation(frameId: frameId, issue: issue, features: features, mode: mode)
            }
        }

        if annotations.isEmpty {
            annotations = legacySuggestions.prefix(2).enumerated().compactMap { index, suggestion in
                makeLegacyAnnotation(
                    frameId: frameId,
                    suggestion: suggestion,
                    index: index,
                    features: features,
                    mode: mode,
                    safeDirectionArrowsOnly: forceLegacyOnly
                )
            }
        }

        let coalesced = Dictionary(grouping: annotations, by: \.id).compactMap { _, grouped -> OverlayAnnotationPresentation? in
            grouped.max(by: { $0.emphasis < $1.emphasis })
        }
        return coalesced.sorted { lhs, rhs in lhs.id < rhs.id }
    }

    private func makeActionAnnotation(frameId: String,
                                      action: RecommendationAction,
                                      critique: CritiqueReport,
                                      mode: AnalysisMode) -> OverlayAnnotationPresentation? {
        if action.actionType == .leaveFrameAsIs {
            return nil
        }

        let fallbackRegion = action.targetRegion ?? firstIssueRegion(linkedIssueIds: action.linkedIssueIds, critique: critique)
        let kind: OverlayKind
        let direction: OverlayDirection?
        let targetRegion: NormalizedRect?

        if let overlayHint = action.overlayHint {
            kind = overlayHint.kind
            direction = overlayHint.direction
            targetRegion = action.targetRegion ?? overlayHint.targetRegion ?? fallbackRegion

            if mode == .pause, let overlayId = nonEmpty(overlayHint.id) {
                return OverlayAnnotationPresentation(
                    id: overlayId,
                    kind: kind,
                    direction: direction,
                    targetRegion: targetRegion,
                    emphasis: 0.85
                )
            }
        } else {
            switch action.actionType {
            case .moveFrameLeft:
                kind = .arrow
                direction = .left
            case .moveFrameRight:
                kind = .arrow
                direction = .right
            case .moveFrameUp:
                kind = .arrow
                direction = .up
            case .moveFrameDown:
                kind = .arrow
                direction = .down
            case .levelHorizon:
                kind = .horizonLine
                direction = nil
            default:
                kind = .regionHighlight
                direction = nil
            }
            targetRegion = fallbackRegion
        }

        return OverlayAnnotationPresentation(
            id: annotationId(
                mode: mode,
                frameId: frameId,
                isLegacy: false,
                kind: kind,
                direction: direction,
                targetRegion: targetRegion,
                actionKey: action.id
            ),
            kind: kind,
            direction: direction,
            targetRegion: targetRegion,
            emphasis: 0.85
        )
    }

    private func makeStructuredAnnotation(frameId: String,
                                          issue: FrameIssue,
                                          features: CoachingFeatures,
                                          mode: AnalysisMode) -> OverlayAnnotationPresentation? {
        let actionKey = "issue_\(issue.type.rawValue)"
        switch issue.type {
        case .horizonDistracts:
            return OverlayAnnotationPresentation(
                id: annotationId(
                    mode: mode,
                    frameId: frameId,
                    isLegacy: false,
                    kind: .horizonLine,
                    direction: nil,
                    targetRegion: nil,
                    actionKey: actionKey
                ),
                kind: .horizonLine,
                direction: nil,
                targetRegion: nil,
                emphasis: max(issue.severity, issue.confidence)
            )
        case .subjectTooCloseToEdge, .insufficientLookSpace:
            let direction = overlayDirectionForComposition(features.composition)
            return OverlayAnnotationPresentation(
                id: annotationId(
                    mode: mode,
                    frameId: frameId,
                    isLegacy: false,
                    kind: .arrow,
                    direction: direction,
                    targetRegion: issue.affectedRegion,
                    actionKey: actionKey
                ),
                kind: .arrow,
                direction: direction,
                targetRegion: issue.affectedRegion,
                emphasis: max(issue.severity, issue.confidence)
            )
        default:
            guard let region = issue.affectedRegion else { return nil }
            return OverlayAnnotationPresentation(
                id: annotationId(
                    mode: mode,
                    frameId: frameId,
                    isLegacy: false,
                    kind: .regionHighlight,
                    direction: nil,
                    targetRegion: region,
                    actionKey: actionKey
                ),
                kind: .regionHighlight,
                direction: nil,
                targetRegion: region,
                emphasis: max(issue.severity, issue.confidence)
            )
        }
    }

    private func makeLegacyAnnotation(frameId: String,
                                      suggestion: Suggestion,
                                      index: Int,
                                      features: CoachingFeatures,
                                      mode: AnalysisMode,
                                      safeDirectionArrowsOnly: Bool = false) -> OverlayAnnotationPresentation? {
        let actionType = actionTypeForSuggestion(suggestion, features: features)
        if actionType == .leaveFrameAsIs {
            return nil
        }
        let kind: OverlayKind
        let direction: OverlayDirection?
        if safeDirectionArrowsOnly {
            switch actionType {
            case .moveFrameLeft:
                kind = .arrow
                direction = .left
            case .moveFrameRight:
                kind = .arrow
                direction = .right
            case .moveFrameUp:
                kind = .arrow
                direction = .up
            case .moveFrameDown:
                kind = .arrow
                direction = .down
            default:
                return nil
            }
        } else {
            switch actionType {
            case .levelHorizon:
                kind = .horizonLine
                direction = nil
            case .moveFrameLeft:
                kind = .arrow
                direction = .left
            case .moveFrameRight:
                kind = .arrow
                direction = .right
            case .moveFrameUp:
                kind = .arrow
                direction = .up
            case .moveFrameDown:
                kind = .arrow
                direction = .down
            default:
                kind = .regionHighlight
                direction = nil
            }
        }

        return OverlayAnnotationPresentation(
            id: annotationId(
                mode: mode,
                frameId: frameId,
                isLegacy: true,
                kind: kind,
                direction: direction,
                targetRegion: nil,
                actionKey: "legacy_\(suggestion.type.rawValue)_\(index)"
            ),
            kind: kind,
            direction: direction,
            targetRegion: nil,
            emphasis: confidenceForSuggestion(suggestion)
        )
    }

    private func annotationId(mode: AnalysisMode,
                              frameId: String,
                              isLegacy: Bool,
                              kind: OverlayKind,
                              direction: OverlayDirection?,
                              targetRegion: NormalizedRect?,
                              actionKey: String) -> String {
        let directionKey = direction?.rawValue ?? "none"
        let regionKey = quantizedRegionKey(for: targetRegion)
        let prefix = isLegacy ? "legacy" : "structured"
        switch mode {
        case .live:
            return "ov_live_\(prefix)_\(kind.rawValue)_\(directionKey)_\(regionKey)_\(actionKey)"
        case .pause:
            return "ov_pause_\(prefix)_\(frameId)_\(actionKey)_\(kind.rawValue)_\(directionKey)_\(regionKey)"
        }
    }

    private struct StructuredPathDecision {
        let isAvailable: Bool
        let liveActionUsable: Bool
    }

    private func structuredPathDecision(mode: AnalysisMode,
                                        critique: CritiqueReport,
                                        plan: RecommendationPlan,
                                        motionState: CameraAnalysisMotionState) -> StructuredPathDecision {
        guard plan.frameId == critique.frameId else {
            return StructuredPathDecision(isAvailable: false, liveActionUsable: false)
        }
        let minimumPlanConfidence = mode == .pause ? 0.15 : 0.45
        let minimumVerdictConfidence = mode == .pause ? 0.15 : 0.40
        guard plan.planConfidence >= minimumPlanConfidence,
              critique.verdictConfidence >= minimumVerdictConfidence else {
            return StructuredPathDecision(isAvailable: false, liveActionUsable: false)
        }
        guard nonEmpty(critique.summary.shortVerdict) != nil else {
            return StructuredPathDecision(isAvailable: false, liveActionUsable: false)
        }
        if let primaryAction = plan.primaryAction, nonEmpty(primaryAction.expectedOutcome) == nil {
            return StructuredPathDecision(isAvailable: false, liveActionUsable: false)
        }
        if mode == .pause,
           critique.verdict == .good,
           plan.primaryAction == nil,
           nonEmpty(plan.noChangeRationale) == nil {
            return StructuredPathDecision(isAvailable: false, liveActionUsable: false)
        }
        if mode == .pause {
            let hasExplainableContent =
                !critique.issues.isEmpty ||
                !critique.strengths.isEmpty ||
                plan.primaryAction != nil ||
                nonEmpty(plan.noChangeRationale) != nil
            guard hasExplainableContent else {
                return StructuredPathDecision(isAvailable: false, liveActionUsable: false)
            }
            return StructuredPathDecision(isAvailable: true, liveActionUsable: true)
        }

        let liveUsable = mode == .live ? liveActionUsable(for: plan, motionState: motionState) : true
        if mode == .live, !liveUsable {
            return StructuredPathDecision(isAvailable: false, liveActionUsable: false)
        }
        return StructuredPathDecision(isAvailable: true, liveActionUsable: liveUsable)
    }

    private func liveActionUsable(for plan: RecommendationPlan,
                                  motionState: CameraAnalysisMotionState) -> Bool {
        guard plan.mode == .live else { return true }

        guard let primaryAction = plan.primaryAction else {
            return plan.inputVerdict == .good && nonEmpty(plan.noChangeRationale) != nil
        }

        if primaryAction.actionType == .leaveFrameAsIs {
            guard plan.inputVerdict == .good else { return false }
            return nonEmpty(plan.noChangeRationale) != nil || nonEmpty(primaryAction.expectedOutcome) != nil
        }

        if primaryAction.linkedIssueIds.isEmpty {
            return false
        }
        if primaryAction.guardrail.minConfidence > plan.planConfidence {
            return false
        }
        if primaryAction.guardrail.requiresStillCamera && motionState != .still {
            return false
        }
        if primaryAction.guardrail.suppressWhenMoving && motionState != .still {
            return false
        }
        return true
    }

    private func firstIssueRegion(linkedIssueIds: [String],
                                  critique: CritiqueReport) -> NormalizedRect? {
        guard !linkedIssueIds.isEmpty else { return nil }
        for issueId in linkedIssueIds {
            if let region = critique.issues.first(where: { $0.id == issueId })?.affectedRegion {
                return region
            }
        }
        return nil
    }

    private func linkedAction(for semanticTip: SemanticTipCandidate,
                              plan: RecommendationPlan) -> RecommendationAction? {
        let actions = [plan.primaryAction].compactMap { $0 } + plan.secondaryActions + plan.deferredActions
        if let primaryActionId = semanticTip.primaryActionId,
           let action = actions.first(where: { $0.id == primaryActionId }) {
            return action
        }
        for linkedActionId in semanticTip.linkedActionIds {
            if let action = actions.first(where: { $0.id == linkedActionId }) {
                return action
            }
        }
        return nil
    }

    private func traceRefIdForIssue(issueId: String,
                                    critique: CritiqueReport) -> String? {
        guard let issueIndex = critique.issues.firstIndex(where: { $0.id == issueId }) else { return nil }
        let issueTraceRefs = critique.traceRefs.filter { $0.contains("_crit_i") }
        guard issueIndex < issueTraceRefs.count else { return nil }
        return issueTraceRefs[issueIndex]
    }

    private func traceRefIdForStrength(strengthId: String,
                                       critique: CritiqueReport) -> String? {
        guard let strengthIndex = critique.strengths.firstIndex(where: { $0.id == strengthId }) else { return nil }
        let strengthTraceRefs = critique.traceRefs.filter { $0.contains("_crit_s") }
        guard strengthIndex < strengthTraceRefs.count else { return nil }
        return strengthTraceRefs[strengthIndex]
    }

    private func traceRefIdForAction(action: RecommendationAction,
                                     critique: CritiqueReport) -> String? {
        for issueId in action.linkedIssueIds {
            if let issueTrace = traceRefIdForIssue(issueId: issueId, critique: critique) {
                return issueTrace
            }
        }
        return critique.traceRefs.first(where: { $0.contains("_crit_summary_") })
    }

    @MainActor
    private func publishOverlayAnnotations(_ annotations: [OverlayAnnotationPresentation], now: Date) {
        if annotations.isEmpty {
            currentOverlayAnnotations = []
            lastOverlayPublishAt = now
            return
        }
        let minInterval = 1.0 / maxOverlayHz
        if now.timeIntervalSince(lastOverlayPublishAt) < minInterval {
            return
        }
        currentOverlayAnnotations = annotations
        lastOverlayPublishAt = now
    }

    private func quantizedRegionKey(for region: NormalizedRect?) -> String {
        guard let region else { return "screen" }
        func q(_ value: Double) -> String {
            let rounded = (value / 0.02).rounded() * 0.02
            return String(format: "%.2f", rounded)
        }
        return "\(q(region.x))_\(q(region.y))_\(q(region.width))_\(q(region.height))"
    }

    private func normalizeSummaryKey(_ value: String) -> String {
        value
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: "_")
    }

    private func makeSourceFrameId(from timestamp: CMTime) -> String {
        guard timestamp.isValid, timestamp.timescale != 0 else {
            return "frame_\(Int(Date().timeIntervalSince1970 * 1000))"
        }
        let ms = Int((Double(timestamp.value) / Double(timestamp.timescale)) * 1000.0)
        return "frame_\(ms)"
    }

    private func currentSourceFrameId(fallbackDate: Date) -> String {
        let fallback = "frame_\(Int(fallbackDate.timeIntervalSince1970 * 1000))"
        return featureQueue.sync {
            let trimmed = lastSourceFrameId.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? fallback : trimmed
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }

    private func confidenceForSuggestion(_ suggestion: Suggestion) -> Double {
        switch suggestion.priority {
        case .critical: return 0.85
        case .important: return 0.70
        case .optional: return 0.55
        }
    }

    private func actionTypeForIssue(_ issueType: IssueTypeV1, features: CoachingFeatures) -> ActionTypeV1 {
        switch issueType {
        case .horizonDistracts:
            return .levelHorizon
        case .backlightHidesSubject:
            return .improveFrontLight
        case .subjectNotProminentEnough:
            return .increaseSubjectSize
        case .subjectTooCloseToEdge, .insufficientLookSpace:
            return actionTypeForComposition(features.composition)
        case .backgroundCompetesWithSubject:
            return .reduceBackgroundDistractions
        case .sceneHasNoClearFocus, .frameVisuallyOverloaded:
            return .changeAngle
        }
    }

    private func actionTypeForSuggestion(_ suggestion: Suggestion, features: CoachingFeatures) -> ActionTypeV1 {
        switch suggestion.type {
        case .horizon:
            return .levelHorizon
        case .exposure, .lighting:
            return .improveFrontLight
        case .composition:
            return actionTypeForComposition(features.composition)
        case .lens:
            return .increaseSubjectSize
        case .other:
            return .changeAngle
        }
    }

    private func actionTypeForComposition(_ composition: CoachingFeatures.Composition) -> ActionTypeV1 {
        if composition.horizontalOffset > 0.15 {
            return .moveFrameLeft
        }
        if composition.horizontalOffset < -0.15 {
            return .moveFrameRight
        }
        if composition.verticalOffset > 0.15 {
            return .moveFrameDown
        }
        if composition.verticalOffset < -0.15 {
            return .moveFrameUp
        }
        return .changeAngle
    }

    private func overlayDirectionForComposition(_ composition: CoachingFeatures.Composition) -> OverlayDirection? {
        let action = actionTypeForComposition(composition)
        switch action {
        case .moveFrameLeft: return .left
        case .moveFrameRight: return .right
        case .moveFrameUp: return .up
        case .moveFrameDown: return .down
        default: return nil
        }
    }

    private func updateFeatures(_ block: (inout CoachingFeatures) -> Void) {
        featureQueue.sync {
            block(&features)
        }
    }

    private func startNeuralEvidenceInferenceIfNeeded(mode: AnalysisMode,
                                                      frameId: String,
                                                      capturedAt: Date,
                                                      pixelBuffer: CVPixelBuffer?,
                                                      orientation: CGImagePropertyOrientation,
                                                      snapshot: FrameFeatureSnapshot,
                                                      semantics: SceneSemanticsReport,
                                                      forcePauseExecution: Bool) {
        guard let neuralEvidenceService,
              let pixelBuffer,
              let request = makeNeuralEvidenceInferenceRequest(
                mode: mode,
                capturedAt: capturedAt,
                pixelBuffer: pixelBuffer,
                orientation: orientation,
                snapshot: snapshot,
                semantics: semantics,
                forcePauseExecution: forcePauseExecution
              ) else { return }

        recordRequestedNeuralFrame(frameId: frameId, mode: mode)

        switch mode {
        case .live:
            liveNeuralInferenceTask?.cancel()
            liveNeuralInferenceTask = Task { [weak self] in
                guard let self else { return }
                let outcome = await neuralEvidenceService.infer(request: request)
                self.recordNeuralOutcomeIfCurrent(outcome, mode: mode, frameId: frameId)
            }
        case .pause:
            pauseNeuralInferenceTask?.cancel()
            pauseNeuralInferenceTask = Task { [weak self] in
                guard let self else { return }
                let outcome = await neuralEvidenceService.infer(request: request)
                self.recordNeuralOutcomeIfCurrent(outcome, mode: mode, frameId: frameId)
            }
        }
    }

    private func makeNeuralEvidenceInferenceRequest(mode: AnalysisMode,
                                                    capturedAt: Date,
                                                    pixelBuffer: CVPixelBuffer,
                                                    orientation: CGImagePropertyOrientation,
                                                    snapshot: FrameFeatureSnapshot,
                                                    semantics: SceneSemanticsReport,
                                                    forcePauseExecution: Bool) -> NeuralEvidenceInferenceRequest? {
        NeuralEvidenceInferenceRequest(
            frameId: snapshot.frameId,
            mode: mode,
            capturedAt: capturedAt,
            pixelBuffer: pixelBuffer,
            orientation: orientation,
            sceneSemantics: semantics,
            primarySubjectRegion: snapshot.subjectSignals.primaryCandidateRegion,
            motionState: snapshot.motion.state,
            shakeLevel: snapshot.motion.shakeLevel,
            isStable: featureQueue.sync { lastFrameWasStable },
            thermalTier: thermalGovernor.currentTier(),
            heavyModelsEnabled: neuralHeavyModelsEnabledProvider(),
            batteryLevel: thermalGovernor.currentBatteryLevel(),
            forcePauseExecution: forcePauseExecution
        )
    }

    private func runNeuralEvidenceInference(mode: AnalysisMode,
                                            capturedAt: Date,
                                            pixelBuffer: CVPixelBuffer,
                                            orientation: CGImagePropertyOrientation,
                                            snapshot: FrameFeatureSnapshot,
                                            semantics: SceneSemanticsReport,
                                            forcePauseExecution: Bool) async -> NeuralEvidenceRecordedOutcome? {
        guard let neuralEvidenceService,
              let request = makeNeuralEvidenceInferenceRequest(
                mode: mode,
                capturedAt: capturedAt,
                pixelBuffer: pixelBuffer,
                orientation: orientation,
                snapshot: snapshot,
                semantics: semantics,
                forcePauseExecution: forcePauseExecution
              ) else { return nil }

        recordRequestedNeuralFrame(frameId: snapshot.frameId, mode: mode)
        let outcome = await neuralEvidenceService.infer(request: request)
        recordNeuralOutcomeIfCurrent(outcome, mode: mode, frameId: snapshot.frameId)
        return NeuralEvidenceRecordedOutcome(outcome)
    }

    private func resolveCritiqueWithHybridFusion(mode: AnalysisMode,
                                                 capturedAt: Date,
                                                 pixelBuffer: CVPixelBuffer?,
                                                 orientation: CGImagePropertyOrientation,
                                                 snapshot: FrameFeatureSnapshot,
                                                 semantics: SceneSemanticsReport,
                                                 deterministicCritique: CritiqueReport,
                                                 forcePauseExecution: Bool) async -> (HybridFusionOutput, NeuralEvidenceRecordedOutcome?) {
        guard let pixelBuffer else {
            return (
                hybridFusionService.fuse(
                    HybridFusionInput(
                        snapshot: snapshot,
                        semantics: semantics,
                        critique: deterministicCritique,
                        neuralSnapshot: nil,
                        neuralMetadata: nil
                    )
                ),
                nil
            )
        }

        let recordedOutcome = await runNeuralEvidenceInference(
            mode: mode,
            capturedAt: capturedAt,
            pixelBuffer: pixelBuffer,
            orientation: orientation,
            snapshot: snapshot,
            semantics: semantics,
            forcePauseExecution: forcePauseExecution
        )
        return (
            hybridFusionService.fuse(
                HybridFusionInput(
                    snapshot: snapshot,
                    semantics: semantics,
                    critique: deterministicCritique,
                    neuralSnapshot: executedNeuralSnapshot(from: recordedOutcome),
                    neuralMetadata: executedNeuralMetadata(from: recordedOutcome)
                )
            ),
            recordedOutcome
        )
    }

    private func executedNeuralSnapshot(from outcome: NeuralEvidenceRecordedOutcome?) -> NeuralEvidenceSnapshot? {
        guard outcome?.kind == .executed else { return nil }
        return outcome?.snapshot
    }

    private func executedNeuralMetadata(from outcome: NeuralEvidenceRecordedOutcome?) -> NeuralEvidenceRuntimeMetadata? {
        guard outcome?.kind == .executed else { return nil }
        return outcome?.metadata
    }

    private func recordRequestedNeuralFrame(frameId: String, mode: AnalysisMode) {
        featureQueue.sync {
            switch mode {
            case .live:
                lastRequestedLiveNeuralFrameId = frameId
            case .pause:
                lastRequestedPauseNeuralFrameId = frameId
            }
        }
    }

    private func recordNeuralOutcomeIfCurrent(_ outcome: NeuralEvidenceInferenceOutcome,
                                              mode: AnalysisMode,
                                              frameId: String) {
        let recorded = NeuralEvidenceRecordedOutcome(outcome)
        featureQueue.sync {
            switch mode {
            case .live:
                guard lastRequestedLiveNeuralFrameId == frameId else { return }
                latestLiveNeuralOutcome = recorded
            case .pause:
                guard lastRequestedPauseNeuralFrameId == frameId else { return }
                latestPauseNeuralOutcome = recorded
            }
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

    private func compositionPriorityDetections(_ detections: [DETRDetection]) -> [DETRDetection] {
        detections
            .filter(isUsableCompositionSubject)
            .stableSorted { lhs, rhs in
                let lhsScore = compositionSubjectScore(lhs)
                let rhsScore = compositionSubjectScore(rhs)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence > rhs.confidence
                }
                let lhsArea = lhs.boundingBox.width * lhs.boundingBox.height
                let rhsArea = rhs.boundingBox.width * rhs.boundingBox.height
                if lhsArea != rhsArea {
                    return lhsArea < rhsArea
                }
                return lhs.label < rhs.label
            }
    }

    private func shouldPreserveVisionSubjectForLiveDetr(_ features: CoachingFeatures) -> Bool {
        guard features.subject.isFace || features.subject.isPerson else { return false }
        return features.subject.count > 0 && features.composition.subjectAreaRatio >= 0.002
    }

    private func isUsableCompositionSubject(_ detection: DETRDetection) -> Bool {
        let label = detection.label.lowercased()
        let area = detection.boundingBox.width * detection.boundingBox.height
        guard detection.confidence >= 0.18 else { return false }
        guard area >= 0.01, area <= 0.72 else { return false }
        guard !backgroundLikeDetrLabels.contains(label) else { return false }
        if label.contains("(other)") || label.hasPrefix("wall") || label.hasPrefix("floor") || label.hasPrefix("window") {
            return false
        }
        return true
    }

    private func compositionSubjectScore(_ detection: DETRDetection) -> Double {
        let area = Double(detection.boundingBox.width * detection.boundingBox.height)
        let preferredAreaPenalty = abs(area - 0.18)
        let labelBonus = foregroundDetrLabels.contains(detection.label.lowercased()) ? 0.25 : 0.0
        return Double(detection.confidence) + labelBonus - preferredAreaPenalty
    }

    private var backgroundLikeDetrLabels: Set<String> {
        [
            "sky (other)",
            "wall (other)",
            "wall (wood)",
            "wall (brick)",
            "wall (stone)",
            "wall (tile)",
            "floor (other)",
            "floor (wood)",
            "ceiling",
            "door",
            "window (other)",
            "window (blind)",
            "table",
            "dining table",
            "fence",
            "pavement",
            "grass",
            "dirt",
            "sea",
            "river",
            "water (other)",
            "mountain",
            "building (other)"
        ]
    }

    private var foregroundDetrLabels: Set<String> {
        [
            "person",
            "laptop",
            "keyboard",
            "cell phone",
            "book",
            "cup",
            "bottle",
            "vase",
            "potted plant",
            "chair",
            "sofa",
            "backpack",
            "handbag",
            "suitcase",
            "bicycle",
            "car",
            "motorcycle",
            "clock",
            "wine glass"
        ]
    }
}

#if DEBUG
extension AnalysisPipeline {
    @MainActor
    func testingReplayStillImageForSemanticEval(recordId: String,
                                                filename: String,
                                                pixelBuffer: CVPixelBuffer,
                                                orientation: CGImagePropertyOrientation = .up,
                                                capturedAt: Date = Date(),
                                                options: SemanticEvalStillImageReplayOptions = .fullRuntime) async -> SemanticEvalStillImageReplayResult {
        let frameId = "semantic_eval_\(recordId)"
        testingResetStillImageReplayState(
            frameId: frameId,
            pixelBuffer: pixelBuffer,
            orientation: orientation
        )
        await testingExtractStillImageReplayFeatures(
            pixelBuffer: pixelBuffer,
            orientation: orientation,
            capturedAt: capturedAt,
            options: options
        )
        let technicalQualitySignal = technicalQualityAnalyzer.signal(pixelBuffer: pixelBuffer)

        let liveRow = await testingMakeLiveSemanticEvalRow(
            recordId: recordId,
            filename: filename,
            frameId: frameId,
            pixelBuffer: pixelBuffer,
            orientation: orientation,
            capturedAt: capturedAt,
            options: options,
            technicalQualitySignal: technicalQualitySignal
        )
        let pauseRow = await testingMakePauseSemanticEvalRow(
            recordId: recordId,
            filename: filename,
            frameId: frameId,
            pixelBuffer: pixelBuffer,
            orientation: orientation,
            capturedAt: capturedAt,
            options: options,
            technicalQualitySignal: technicalQualitySignal
        )

        return SemanticEvalStillImageReplayResult(
            recordId: recordId,
            filename: filename,
            frameId: frameId,
            liveRow: liveRow,
            pauseRow: pauseRow
        )
    }

    @MainActor
    private func testingResetStillImageReplayState(frameId: String,
                                                   pixelBuffer: CVPixelBuffer,
                                                   orientation: CGImagePropertyOrientation) {
        lastPixelBuffer = pixelBuffer
        lastOrientation = orientation
        lastFrameWasStable = true
        suggestionExpiry = .distantPast
        lastAestheticRequest = .distantPast
        lastDETRRequest = .distantPast
        liveHintShownAt = .distantPast
        liveHintExpiresAt = .distantPast
        lastLiveMotionBecameUnstableAt = nil
        currentSuggestion = nil
        currentLiveHint = nil
        currentPauseCritique = nil
        currentOverlayAnnotations = []
        currentPauseTraceBundle = nil
        currentLiveFusionTraceBundle = nil
        pauseReasoningTask?.cancel()
        pauseReasoningTask = nil
        liveNeuralInferenceTask?.cancel()
        liveNeuralInferenceTask = nil
        pauseNeuralInferenceTask?.cancel()
        pauseNeuralInferenceTask = nil
        lastRefinedPauseFrameId = nil

        featureQueue.sync {
            features = CoachingFeatures()
            features.motion.state = .still
            features.motion.shakeLevel = 0
            debugData = DebugData()
            latestVisionSample = nil
            latestHorizonSample = nil
            latestHorizonMeasuredAt = nil
            latestLightingSample = nil
            latestLightingMeasuredAt = nil
            latestDetrSample = nil
            latestAestheticSample = nil
            latestAestheticMeasuredAt = nil
            latestLiveNeuralOutcome = nil
            latestPauseNeuralOutcome = nil
            lastRequestedLiveNeuralFrameId = nil
            lastRequestedPauseNeuralFrameId = nil
            lastSourceFrameId = frameId
        }

        overlayState = OverlayState(
            primaryBoundingBox: nil,
            horizonAngle: 0,
            horizonConfidence: 0,
            saliencyBalance: 0
        )
    }

    @MainActor
    private func testingExtractStillImageReplayFeatures(pixelBuffer: CVPixelBuffer,
                                                        orientation: CGImagePropertyOrientation,
                                                        capturedAt: Date,
                                                        options: SemanticEvalStillImageReplayOptions) async {
        let trackingResult = visionTracking.process(pixelBuffer: pixelBuffer, orientation: orientation)
        let primarySubject = primaryVisionSubject(from: trackingResult)
        let horizon = horizonEstimator.estimate(
            pixelBuffer: pixelBuffer,
            orientation: orientation,
            isStable: true
        )
        let saliencyBalance = computeSaliencyBalance(
            from: primarySubject?.boundingBox ?? .zero,
            saliencyCenter: trackingResult.saliencyCenter
        )

        testingApplyVisionAndHorizonForReplay(
            trackingResult: trackingResult,
            primarySubject: primarySubject,
            horizon: horizon,
            saliencyBalance: saliencyBalance,
            measuredAt: capturedAt
        )

        if let primarySubject {
            testingApplyLightingForReplay(
                pixelBuffer: pixelBuffer,
                subjectBoundingBox: primarySubject.boundingBox,
                measuredAt: capturedAt
            )
        }

        guard options.runHeavyModels else { return }

        let detections = await testingDetectForReplay(
            pixelBuffer: pixelBuffer,
            orientation: orientation
        )
        testingApplyDetrForReplay(
            detections: detections,
            pixelBuffer: pixelBuffer,
            measuredAt: capturedAt
        )

        if let score = await testingScoreAestheticForReplay(
            pixelBuffer: pixelBuffer,
            orientation: orientation
        ) {
            testingApplyAestheticForReplay(score10: score, measuredAt: capturedAt)
        }
    }

    @MainActor
    private func testingApplyVisionAndHorizonForReplay(trackingResult: VisionTrackingResult,
                                                       primarySubject: TrackedSubject?,
                                                       horizon: (angle: CGFloat, confidence: CGFloat),
                                                       saliencyBalance: CGFloat,
                                                       measuredAt: Date) {
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
            features.motion.shakeLevel = 0
            features.motion.state = .still
            self.lastFrameWasStable = true

            if let subject = primarySubject {
                features.composition = self.compositionFeatures(from: subject.boundingBox)
                features.composition.saliencyLeftRightBalance = saliencyBalance
                features.composition.subjectAreaRatio = subject.boundingBox.width * subject.boundingBox.height
                features.lensRecommendation = self.lensRecommendation(for: subject.boundingBox)
                features.subject.objectName = nil
                features.subject.isFace = subject.isFace
                features.subject.isPerson = true
                features.subject.count = max(trackingResult.faceCount, trackingResult.personCount)
            } else if let saliencyCenter = trackingResult.saliencyCenter {
                features.composition = self.compositionFeatures(fromSaliency: saliencyCenter)
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
            self.debugData.visionMeasuredAt = measuredAt
            self.debugData.saliencyCenter = trackingResult.saliencyCenter
            self.debugData.saliencyRegion = trackingResult.saliencyRegion
            self.latestVisionSample = FeatureSample(
                value: FeatureSnapshotVisionPayload(
                    subjects: visionSubjectsPayload,
                    saliencyCenter: trackingResult.saliencyCenter,
                    saliencyRegion: trackingResult.saliencyRegion,
                    faceCount: trackingResult.faceCount,
                    personCount: trackingResult.personCount
                ),
                measuredAt: measuredAt,
                baseConfidence: visionBaseConfidence ?? (trackingResult.saliencyRegion == nil ? nil : 0.48)
            )
            self.latestHorizonSample = FeatureSample(
                value: FeatureSnapshotHorizonPayload(
                    angleDegrees: Double(horizon.angle),
                    confidence: Double(horizon.confidence)
                ),
                measuredAt: measuredAt,
                baseConfidence: Double(horizon.confidence)
            )
            self.latestHorizonMeasuredAt = measuredAt
        }

        overlayState = OverlayState(
            primaryBoundingBox: primarySubject?.boundingBox,
            horizonAngle: horizon.angle,
            horizonConfidence: horizon.confidence,
            saliencyBalance: saliencyBalance
        )
    }

    private func testingApplyLightingForReplay(pixelBuffer: CVPixelBuffer,
                                               subjectBoundingBox: CGRect,
                                               measuredAt: Date) {
        let lighting = lightingEstimator.analyse(
            pixelBuffer: pixelBuffer,
            subjectBoundingBox: subjectBoundingBox
        )
        updateFeatures { features in
            features.lighting.backlightIndex = lighting.backlightIndex
            features.lighting.keyToFillRatio = lighting.keyFillRatio
            features.lighting.exposureBiasHint = lighting.exposureBiasHint
            let subjectLighting = FrameFeatureSnapshot.LightingFeatures.SubjectLightingMetrics(
                subjectMeanLuma: Double(lighting.subjectMeanLuma),
                backgroundMeanLuma: Double(lighting.backgroundMeanLuma),
                subjectToBackgroundDelta: Double(lighting.subjectToBackgroundDelta),
                subjectClippedBrightRatio: Double(lighting.subjectClippedBrightRatio),
                backgroundHotspotRatio: Double(lighting.backgroundHotspotRatio)
            )
            self.latestLightingSample = FeatureSample(
                value: FeatureSnapshotLightingPayload(
                    exposureBiasHint: Double(lighting.exposureBiasHint),
                    backlightIndex: Double(lighting.backlightIndex),
                    keyToFillRatio: Double(lighting.keyFillRatio),
                    subjectLighting: subjectLighting
                ),
                measuredAt: measuredAt,
                baseConfidence: nil
            )
            self.latestLightingMeasuredAt = measuredAt
        }
    }

    @MainActor
    private func testingApplyDetrForReplay(detections: [DETRDetection],
                                           pixelBuffer: CVPixelBuffer,
                                           measuredAt: Date) {
        let priorityDetections = compositionPriorityDetections(detections)
        var updatedPrimaryBoundingBox: CGRect?
        var shouldClearPrimaryBoundingBox = false

        updateFeatures { features in
            self.debugData.detrDetections = detections
            self.debugData.detrMeasuredAt = measuredAt
            self.latestDetrSample = self.makeDetrFeatureSample(
                from: detections,
                measuredAt: measuredAt
            )

            guard !self.shouldPreserveVisionSubjectForLiveDetr(features) else { return }

            if let top = priorityDetections.first {
                features.composition = self.compositionFeatures(from: top.boundingBox)
                features.composition.subjectAreaRatio = top.boundingBox.width * top.boundingBox.height
                features.subject.objectName = top.label
                features.subject.isFace = top.label.lowercased() == "person"
                features.subject.isPerson = top.label.lowercased() == "person"
                features.subject.count = detections.count
                updatedPrimaryBoundingBox = top.boundingBox
            } else {
                if let saliencyCenter = self.debugData.saliencyCenter {
                    features.composition = self.compositionFeatures(fromSaliency: saliencyCenter)
                }
                features.composition.subjectAreaRatio = 0
                features.subject.objectName = nil
                features.subject.isFace = false
                features.subject.isPerson = false
                features.subject.count = 0
                shouldClearPrimaryBoundingBox = true
            }
        }

        if let updatedPrimaryBoundingBox {
            overlayState.primaryBoundingBox = updatedPrimaryBoundingBox
            testingApplyLightingForReplay(
                pixelBuffer: pixelBuffer,
                subjectBoundingBox: updatedPrimaryBoundingBox,
                measuredAt: measuredAt
            )
        } else if shouldClearPrimaryBoundingBox {
            overlayState.primaryBoundingBox = nil
        }
    }

    private func testingApplyAestheticForReplay(score10: Double,
                                                measuredAt: Date) {
        updateFeatures { features in
            features.aestheticScore = CGFloat(score10)
            self.latestAestheticSample = self.makeAestheticFeatureSample(
                score10: score10,
                measuredAt: measuredAt
            )
            self.latestAestheticMeasuredAt = measuredAt
        }
    }

    private func testingDetectForReplay(pixelBuffer: CVPixelBuffer,
                                        orientation: CGImagePropertyOrientation) async -> [DETRDetection] {
        guard let detector = detrDetector else { return [] }
        return await withCheckedContinuation { continuation in
            detector.detect(pixelBuffer: pixelBuffer, orientation: orientation) { detections in
                continuation.resume(returning: detections)
            }
        }
    }

    private func testingScoreAestheticForReplay(pixelBuffer: CVPixelBuffer,
                                                orientation: CGImagePropertyOrientation) async -> Double? {
        await withCheckedContinuation { continuation in
            aestheticScorer.score(pixelBuffer: pixelBuffer, orientation: orientation) { score in
                continuation.resume(returning: score)
            }
        }
    }

    @MainActor
    private func testingMakeLiveSemanticEvalRow(recordId: String,
                                                filename: String,
                                                frameId: String,
                                                pixelBuffer: CVPixelBuffer,
                                                orientation: CGImagePropertyOrientation,
                                                capturedAt: Date,
                                                options: SemanticEvalStillImageReplayOptions,
                                                technicalQualitySignal: TechnicalQualitySignal) async -> SemanticEvalCandidateOutput {
        let snapshot = makeFeatureSnapshot(
            mode: .live,
            frameId: frameId,
            capturedAt: capturedAt
        )
        let semantics = sceneSemanticsAnalyzer.analyze(snapshot: snapshot)
        let deterministicCritique = frameCritiqueEngine.analyze(snapshot: snapshot, semantics: semantics)
        let (fusionOutput, _) = await resolveCritiqueWithHybridFusion(
            mode: .live,
            capturedAt: capturedAt,
            pixelBuffer: options.runNeuralEvidence ? pixelBuffer : nil,
            orientation: orientation,
            snapshot: snapshot,
            semantics: semantics,
            deterministicCritique: deterministicCritique,
            forcePauseExecution: false
        )
        let critique = fusionOutput.critique
        let plan = recommendationPlanner.makePlan(snapshot: snapshot, critique: critique)
        let semanticTips = semanticTipPlanner.plan(
            input: SemanticTipPlannerInput(
                frameId: snapshot.frameId,
                mode: .live,
                critique: critique,
                recommendationPlan: plan,
                semantics: semantics,
                currentLiveTipKey: nil
            )
        )
        let structuredDecision = structuredPathDecision(
            mode: .live,
            critique: critique,
            plan: plan,
            motionState: snapshot.motion.state
        )
        let currentFeatures = featureQueue.sync { features }
        let legacySuggestion = suggestionEngine.rankedSuggestions(
            from: currentFeatures,
            topN: 1,
            timestamp: capturedAt
        ).first
        let hint = makeLiveHintPresentation(
            frameId: snapshot.frameId,
            critique: critique,
            plan: plan,
            semanticTip: semanticTips.livePrimaryTip,
            semanticFallbackUsed: semanticTips.fallbackUsed,
            legacySuggestion: legacySuggestion,
            forceLegacyFallback: !structuredDecision.isAvailable,
            technicalQualitySignal: technicalQualitySignal,
            snapshot: snapshot,
            semantics: semantics,
            allowsAmbiguousTechnicalSilenceLowConfidence: options.runHeavyModels
        )
        return SemanticEvalCandidateOutput.live(
            recordId: recordId,
            filename: filename,
            hint: hint,
            source: options.source,
            runtimeClaim: options.runtimeClaim,
            futureActions: testingSemanticEvalFutureActions(
                snapshot: snapshot,
                semantics: semantics,
                legacySuggestions: legacySuggestion.map { [$0] } ?? [],
                technicalQualitySignal: technicalQualitySignal
            ),
            dominantFutureActions: technicalQualitySignal.dominantFutureActionIds,
            technicalConfidenceFloor: testingSemanticEvalTechnicalConfidenceFloor(
                technicalQualitySignal,
                snapshot: snapshot,
                semantics: semantics,
                allowsAmbiguousTechnicalSilenceLowConfidence: options.runHeavyModels
            ),
            debugNumericFeatures: testingSemanticEvalDebugNumericFeatures(
                snapshot: snapshot,
                semantics: semantics,
                critique: critique,
                pixelBuffer: pixelBuffer
            ),
            debugSemanticLabels: testingSemanticEvalDebugSemanticLabels(
                semantics: semantics,
                critique: critique
            )
        )
    }

    @MainActor
    private func testingMakePauseSemanticEvalRow(recordId: String,
                                                 filename: String,
                                                 frameId: String,
                                                 pixelBuffer: CVPixelBuffer,
                                                 orientation: CGImagePropertyOrientation,
                                                 capturedAt: Date,
                                                 options: SemanticEvalStillImageReplayOptions,
                                                 technicalQualitySignal: TechnicalQualitySignal) async -> SemanticEvalCandidateOutput {
        let snapshot = makeFeatureSnapshot(
            mode: .pause,
            frameId: frameId,
            capturedAt: capturedAt
        )
        let semantics = sceneSemanticsAnalyzer.analyze(snapshot: snapshot)
        let deterministicCritique = frameCritiqueEngine.analyze(snapshot: snapshot, semantics: semantics)
        let legacySuggestions = suggestionEngine.rankedSuggestions(
            from: featureQueue.sync { features },
            topN: 6,
            timestamp: capturedAt
        )
        let futureActions = testingSemanticEvalFutureActions(
            snapshot: snapshot,
            semantics: semantics,
            legacySuggestions: legacySuggestions,
            technicalQualitySignal: technicalQualitySignal
        )
        let (fusionOutput, pauseNeuralOutcome) = await resolveCritiqueWithHybridFusion(
            mode: .pause,
            capturedAt: capturedAt,
            pixelBuffer: options.runNeuralEvidence ? pixelBuffer : nil,
            orientation: orientation,
            snapshot: snapshot,
            semantics: semantics,
            deterministicCritique: deterministicCritique,
            forcePauseExecution: true
        )
        let critique = fusionOutput.critique
        let plan = recommendationPlanner.makePlan(snapshot: snapshot, critique: critique)
        let validatedVisualEvidence: VLMEvidenceValidationResult?
        if options.runVisualEvidence {
            let visualEvidenceResult = await resolvePauseVisualEvidence(
                snapshot: snapshot,
                semantics: semantics,
                critique: critique,
                plan: plan,
                neuralOutcome: pauseNeuralOutcome
            )
            validatedVisualEvidence = logAndExtractValidatedVisualEvidence(
                visualEvidenceResult,
                frameId: snapshot.frameId
            )
        } else {
            validatedVisualEvidence = nil
        }
        let semanticTips = semanticTipPlanner.plan(
            input: SemanticTipPlannerInput(
                frameId: snapshot.frameId,
                mode: .pause,
                critique: critique,
                recommendationPlan: plan,
                semantics: semantics,
                validatedEvidence: validatedVisualEvidence
            )
        )
        let structuredDecision = structuredPathDecision(
            mode: .pause,
            critique: critique,
            plan: plan,
            motionState: snapshot.motion.state
        )
        let contextualCorrection = contextualSemanticCorrection(
            snapshot: snapshot,
            semantics: semantics,
            critique: critique,
            technicalQualitySignal: technicalQualitySignal
        )
        if contextualCorrection == nil,
           let technicalPauseIssue = technicalPauseIssue(
            signal: technicalQualitySignal,
            snapshot: snapshot,
            semantics: semantics,
            semanticTips: semanticTips.pauseExpandedTips,
            structuredAvailable: structuredDecision.isAvailable,
            structuredVerdict: critique.verdict
        ),
           let technicalPauseCritique = makeTechnicalPauseCritiquePresentation(
                frameId: snapshot.frameId,
                issue: technicalPauseIssue,
                signal: technicalQualitySignal,
                snapshot: snapshot,
                semantics: semantics,
                allowsAmbiguousTechnicalSilenceLowConfidence: options.runHeavyModels
           ) {
            return SemanticEvalCandidateOutput.pause(
                recordId: recordId,
                filename: filename,
                critique: technicalPauseCritique,
                source: options.source,
                runtimeClaim: options.runtimeClaim,
                futureActions: futureActions,
                dominantFutureActions: technicalQualitySignal.dominantFutureActionIds,
                technicalConfidenceFloor: testingSemanticEvalTechnicalConfidenceFloor(
                    technicalQualitySignal,
                    snapshot: snapshot,
                    semantics: semantics,
                    allowsAmbiguousTechnicalSilenceLowConfidence: options.runHeavyModels
                ),
                debugNumericFeatures: testingSemanticEvalDebugNumericFeatures(
                    snapshot: snapshot,
                    semantics: semantics,
                    critique: critique,
                    pixelBuffer: pixelBuffer
                ),
                debugSemanticLabels: testingSemanticEvalDebugSemanticLabels(
                    semantics: semantics,
                    critique: critique
                )
            )
        }

        guard structuredDecision.isAvailable else {
            return SemanticEvalCandidateOutput.hidden(
                recordId: recordId,
                filename: filename,
                mode: .pause,
                source: options.source,
                runtimeClaim: options.runtimeClaim,
                futureActions: futureActions,
                traceIds: critique.traceRefs,
                debugNumericFeatures: testingSemanticEvalDebugNumericFeatures(
                    snapshot: snapshot,
                    semantics: semantics,
                    critique: critique,
                    pixelBuffer: pixelBuffer
                ),
                debugSemanticLabels: testingSemanticEvalDebugSemanticLabels(
                    semantics: semantics,
                    critique: critique
                )
            )
        }
        let pauseCritique = makePauseCritiquePresentation(
            critique: critique,
            plan: plan,
            semanticTips: semanticTips.pauseExpandedTips,
            semanticFallbackUsed: semanticTips.fallbackUsed,
            snapshot: snapshot,
            semantics: semantics,
            technicalQualitySignal: technicalQualitySignal
        )
        return SemanticEvalCandidateOutput.pause(
            recordId: recordId,
            filename: filename,
            critique: pauseCritique,
            source: options.source,
            runtimeClaim: options.runtimeClaim,
            futureActions: futureActions,
            dominantFutureActions: technicalQualitySignal.dominantFutureActionIds,
            technicalConfidenceFloor: testingSemanticEvalTechnicalConfidenceFloor(
                technicalQualitySignal,
                snapshot: snapshot,
                semantics: semantics,
                allowsAmbiguousTechnicalSilenceLowConfidence: options.runHeavyModels
            ),
            debugNumericFeatures: testingSemanticEvalDebugNumericFeatures(
                snapshot: snapshot,
                semantics: semantics,
                critique: critique,
                pixelBuffer: pixelBuffer
            ),
            debugSemanticLabels: testingSemanticEvalDebugSemanticLabels(
                semantics: semantics,
                critique: critique
            )
        )
    }

    private func testingSemanticEvalDebugNumericFeatures(snapshot: FrameFeatureSnapshot,
                                                         semantics: SceneSemanticsReport,
                                                         critique: CritiqueReport,
                                                         pixelBuffer: CVPixelBuffer? = nil) -> [String: Double] {
        var features: [String: Double] = [
            "aesthetic_score": snapshot.aesthetics.score ?? -1,
            "aesthetic_confidence": snapshot.aesthetics.scoreConfidence ?? -1,
            "backlight_index": snapshot.lighting.backlightIndex,
            "background_clutter": semantics.dominance.backgroundClutterScore,
            "edge_pressure": semantics.readability.edgePressureScore,
            "exposure_bias": snapshot.lighting.exposureBiasHint,
            "focus_competition": semantics.dominance.focusCompetitionScore,
            "horizon_angle": snapshot.horizon.angleDegrees,
            "horizon_confidence": snapshot.horizon.confidence,
            "object_count": Double(snapshot.objects.totalCount),
            "person_count": Double(snapshot.subjectSignals.personCount),
            "primary_subject_confidence": semantics.primarySubject.confidence,
            "scene_type_confidence": semantics.sceneTypeConfidence,
            "separation_score": semantics.readability.separationScore,
            "subject_area_ratio": snapshot.composition.subjectAreaRatio,
            "verdict_confidence": critique.verdictConfidence
        ]
        if let pixelBuffer {
            features["frame_aspect_ratio"] = testingSemanticEvalFrameAspectRatio(pixelBuffer: pixelBuffer)
        }
        return features
    }

    private func testingSemanticEvalFrameAspectRatio(pixelBuffer: CVPixelBuffer) -> Double {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard height > 0 else { return 0 }
        return Double(width) / Double(height)
    }

    private func testingSemanticEvalDebugSemanticLabels(semantics: SceneSemanticsReport,
                                                        critique: CritiqueReport) -> [String: String] {
        [
            "has_clear_focus": semantics.dominance.hasClearFocus ? "true" : "false",
            "look_space_adequate": semantics.readability.lookSpaceAdequate.map { $0 ? "true" : "false" } ?? "nil",
            "primary_subject_kind": semantics.primarySubject.kind.rawValue,
            "primary_subject_label": semantics.primarySubject.label ?? "",
            "scene_type": semantics.sceneType.rawValue,
            "subject_readable": semantics.readability.subjectReadable ? "true" : "false",
            "verdict": critique.verdict.rawValue
        ]
    }

    private func testingSemanticEvalTechnicalConfidenceFloor(_ signal: TechnicalQualitySignal,
                                                             snapshot: FrameFeatureSnapshot,
                                                             semantics: SceneSemanticsReport,
                                                             allowsAmbiguousTechnicalSilenceLowConfidence: Bool = true) -> Double? {
        if let dominantIssue = dominantTechnicalQualityIssue(from: signal),
           shouldUseLowConfidenceForAmbiguousTechnicalSilence(
                issue: dominantIssue,
                signal: signal,
                snapshot: snapshot,
                semantics: semantics,
                isEnabled: allowsAmbiguousTechnicalSilenceLowConfidence
           ) {
            return nil
        }
        let strongestIssue = signal.issues.max { lhs, rhs in
            max(lhs.confidence, lhs.severity) < max(rhs.confidence, rhs.severity)
        }
        guard let strongestIssue else { return nil }
        if shouldUseLowConfidenceForAmbiguousTechnicalSilence(
            issue: strongestIssue,
            signal: signal,
            snapshot: snapshot,
            semantics: semantics,
            isEnabled: allowsAmbiguousTechnicalSilenceLowConfidence
        ) {
            return nil
        }
        let strongest = max(strongestIssue.confidence, strongestIssue.severity)
        guard strongest >= 0.55 else { return nil }
        if strongestIssue.type == .underexposure {
            return min(0.74, max(0.55, strongest))
        }
        return max(0.75, strongest)
    }

    private func testingSemanticEvalFutureActions(snapshot: FrameFeatureSnapshot,
                                                  semantics: SceneSemanticsReport,
                                                  legacySuggestions: [Suggestion],
                                                  technicalQualitySignal: TechnicalQualitySignal = .empty) -> [String] {
        var actions: [String] = technicalQualitySignal.futureActionIds

        if snapshot.motion.state != .still || snapshot.motion.shakeLevel >= 0.65 {
            actions.append(TechnicalQualityActionType.stabilizeCamera.rawValue)
        }

        if snapshot.lighting.exposureBiasHint >= 0.25 {
            actions.append(TechnicalQualityActionType.reduceExposure.rawValue)
        } else if snapshot.lighting.exposureBiasHint <= -0.25 {
            actions.append(TechnicalQualityActionType.increaseExposure.rawValue)
        }

        for suggestion in legacySuggestions where suggestion.type == .exposure {
            if suggestion.text.localizedCaseInsensitiveContains("светло") {
                actions.append(TechnicalQualityActionType.reduceExposure.rawValue)
            } else if suggestion.text.localizedCaseInsensitiveContains("темно") {
                actions.append(TechnicalQualityActionType.increaseExposure.rawValue)
            }
        }

        if shouldAddContextualStabilizeFutureAction(
            snapshot: snapshot,
            semantics: semantics,
            currentFutureActions: actions
        ) {
            actions.append(TechnicalQualityActionType.stabilizeCamera.rawValue)
        }

        if shouldAddLowAestheticSingleObjectStabilizeFutureAction(
            snapshot: snapshot,
            semantics: semantics,
            currentFutureActions: actions
        ) {
            actions.append(TechnicalQualityActionType.stabilizeCamera.rawValue)
        }

        if shouldAddSmallReadableObjectFocusFutureActions(
            snapshot: snapshot,
            semantics: semantics,
            currentFutureActions: actions
        ) {
            actions.append(TechnicalQualityActionType.stabilizeCamera.rawValue)
            actions.append(TechnicalQualityActionType.refocusSubject.rawValue)
        }

        if shouldAddUnknownLowLightStabilizeFutureAction(
            snapshot: snapshot,
            semantics: semantics,
            currentFutureActions: actions
        ) {
            actions.append(TechnicalQualityActionType.stabilizeCamera.rawValue)
        }

        if shouldAddUnknownOcclusionRefocusFutureActions(
            snapshot: snapshot,
            semantics: semantics,
            currentFutureActions: actions
        ) {
            actions.append(TechnicalQualityActionType.refocusSubject.rawValue)
            actions.append(TechnicalQualityActionType.avoidOcclusion.rawValue)
        }

        if shouldAddLargeColorCastReduceExposureFutureAction(
            snapshot: snapshot,
            semantics: semantics,
            currentFutureActions: actions
        ) {
            actions.append(TechnicalQualityActionType.reduceExposure.rawValue)
        }

        if shouldAddTightReadableEdgeAvoidOcclusionFutureAction(
            snapshot: snapshot,
            semantics: semantics,
            currentFutureActions: actions
        ) {
            actions.append(TechnicalQualityActionType.avoidOcclusion.rawValue)
        }

        if shouldAddExplicitReadableOcclusionFutureAction(
            snapshot: snapshot,
            semantics: semantics,
            currentFutureActions: actions
        ) {
            actions.append(TechnicalQualityActionType.avoidOcclusion.rawValue)
        }

        if shouldAddReadableSoftnessStabilizeFutureAction(
            snapshot: snapshot,
            semantics: semantics,
            currentFutureActions: actions
        ) {
            actions.append(TechnicalQualityActionType.stabilizeCamera.rawValue)
        }

        if shouldAddUnknownSyntheticOcclusionFutureAction(
            snapshot: snapshot,
            semantics: semantics,
            currentFutureActions: actions
        ) {
            actions.append(TechnicalQualityActionType.avoidOcclusion.rawValue)
        }

        if shouldAddUnknownDefocusLowLightRecoveryFutureActions(
            snapshot: snapshot,
            semantics: semantics,
            currentFutureActions: actions
        ) {
            actions.append(TechnicalQualityActionType.increaseExposure.rawValue)
            actions.append(TechnicalQualityActionType.reduceIsoNoise.rawValue)
        }

        return uniqueSemanticEvalActions(actions)
    }

    private func shouldAddLowAestheticSingleObjectStabilizeFutureAction(snapshot: FrameFeatureSnapshot,
                                                                        semantics: SceneSemanticsReport,
                                                                        currentFutureActions: [String]) -> Bool {
        guard !currentFutureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue),
              semantics.readability.subjectReadable,
              semantics.primarySubject.kind == .object,
              snapshot.objects.totalCount == 1,
              snapshot.composition.subjectAreaRatio < 0.22,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore < 0.37 else {
            return false
        }
        return true
    }

    private func shouldAddSmallReadableObjectFocusFutureActions(snapshot: FrameFeatureSnapshot,
                                                                semantics: SceneSemanticsReport,
                                                                currentFutureActions: [String]) -> Bool {
        guard semantics.readability.subjectReadable,
              semantics.primarySubject.kind == .object,
              snapshot.objects.totalCount >= 2,
              snapshot.composition.subjectAreaRatio < 0.22,
              let aestheticScore = snapshot.aesthetics.score,
              (0.40...0.43).contains(aestheticScore),
              snapshot.lighting.exposureBiasHint <= -0.55,
              semantics.dominance.backgroundClutterScore <= 0.25,
              currentFutureActions.contains(TechnicalQualityActionType.reduceExposure.rawValue),
              currentFutureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue) else {
            return false
        }
        return true
    }

    private func shouldAddUnknownLowLightStabilizeFutureAction(snapshot: FrameFeatureSnapshot,
                                                               semantics: SceneSemanticsReport,
                                                               currentFutureActions: [String]) -> Bool {
        guard semantics.primarySubject.kind == .unknown,
              !semantics.readability.subjectReadable,
              snapshot.objects.totalCount == 0,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore < 0.46,
              currentFutureActions.contains(where: {
                  $0 == TechnicalQualityActionType.increaseExposure.rawValue ||
                      $0 == TechnicalQualityActionType.reduceIsoNoise.rawValue
              }) else {
            return false
        }
        return true
    }

    private func shouldAddUnknownOcclusionRefocusFutureActions(snapshot: FrameFeatureSnapshot,
                                                               semantics: SceneSemanticsReport,
                                                               currentFutureActions: [String]) -> Bool {
        guard semantics.primarySubject.kind == .unknown,
              !semantics.readability.subjectReadable,
              snapshot.objects.totalCount == 0,
              let aestheticScore = snapshot.aesthetics.score,
              (0.38..<0.39).contains(aestheticScore),
              currentFutureActions.contains(TechnicalQualityActionType.reduceExposure.rawValue),
              !currentFutureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue),
              !currentFutureActions.contains(TechnicalQualityActionType.reduceIsoNoise.rawValue) else {
            return false
        }
        return true
    }

    private func shouldAddLargeColorCastReduceExposureFutureAction(snapshot: FrameFeatureSnapshot,
                                                                   semantics: SceneSemanticsReport,
                                                                   currentFutureActions: [String]) -> Bool {
        guard semantics.readability.subjectReadable,
              semantics.primarySubject.kind == .object,
              snapshot.objects.totalCount == 1,
              snapshot.composition.subjectAreaRatio >= 0.85,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore < 0.40,
              currentFutureActions.contains(where: {
                  $0 == TechnicalQualityActionType.increaseExposure.rawValue ||
                      $0 == TechnicalQualityActionType.refocusSubject.rawValue ||
                      $0 == TechnicalQualityActionType.reduceIsoNoise.rawValue
              }) else {
            return false
        }
        return true
    }

    private func shouldAddTightReadableEdgeAvoidOcclusionFutureAction(snapshot: FrameFeatureSnapshot,
                                                                      semantics: SceneSemanticsReport,
                                                                      currentFutureActions: [String]) -> Bool {
        guard !currentFutureActions.contains(TechnicalQualityActionType.avoidOcclusion.rawValue),
              shouldCorrectTightReadableEdge(snapshot: snapshot, semantics: semantics) else {
            return false
        }
        return true
    }

    private func shouldAddExplicitReadableOcclusionFutureAction(snapshot: FrameFeatureSnapshot,
                                                                semantics: SceneSemanticsReport,
                                                                currentFutureActions: [String]) -> Bool {
        guard !currentFutureActions.contains(TechnicalQualityActionType.avoidOcclusion.rawValue) else {
            return false
        }
        let futureActionSet = Set(currentFutureActions)
        return shouldCorrectReadableSmallEdgeCrop(
            snapshot: snapshot,
            semantics: semantics,
            futureActions: futureActionSet
        ) || shouldCorrectReadableSmallForegroundObstruction(
            snapshot: snapshot,
            semantics: semantics,
            futureActions: futureActionSet
        ) || shouldCorrectReadableNeutralDenseClutter(snapshot: snapshot, semantics: semantics)
    }

    private func shouldAddReadableSoftnessStabilizeFutureAction(snapshot: FrameFeatureSnapshot,
                                                                semantics: SceneSemanticsReport,
                                                                currentFutureActions: [String]) -> Bool {
        guard !currentFutureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue) else {
            return false
        }
        return shouldTreatAsTechnicalOnlySoftness(
            snapshot: snapshot,
            semantics: semantics,
            futureActions: Set(currentFutureActions + [TechnicalQualityActionType.stabilizeCamera.rawValue])
        )
    }

    private func shouldAddUnknownSyntheticOcclusionFutureAction(snapshot: FrameFeatureSnapshot,
                                                                semantics: SceneSemanticsReport,
                                                                currentFutureActions: [String]) -> Bool {
        guard !currentFutureActions.contains(TechnicalQualityActionType.avoidOcclusion.rawValue),
              semantics.primarySubject.kind == .unknown,
              !semantics.readability.subjectReadable,
              snapshot.objects.totalCount <= 1,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore < 0.50,
              !shouldRespectLowKeyGoodUnknownFrame(snapshot: snapshot, semantics: semantics) else {
            return false
        }
        return currentFutureActions.contains(where: {
            $0 == TechnicalQualityActionType.stabilizeCamera.rawValue ||
                $0 == TechnicalQualityActionType.refocusSubject.rawValue ||
                $0 == TechnicalQualityActionType.increaseExposure.rawValue ||
                $0 == TechnicalQualityActionType.reduceIsoNoise.rawValue
        })
    }

    private func shouldAddUnknownDefocusLowLightRecoveryFutureActions(snapshot: FrameFeatureSnapshot,
                                                                      semantics: SceneSemanticsReport,
                                                                      currentFutureActions: [String]) -> Bool {
        guard semantics.primarySubject.kind == .unknown,
              !semantics.readability.subjectReadable,
              snapshot.objects.totalCount == 0,
              let aestheticScore = snapshot.aesthetics.score,
              aestheticScore < 0.42,
              currentFutureActions.contains(TechnicalQualityActionType.refocusSubject.rawValue),
              currentFutureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue) else {
            return false
        }
        return !currentFutureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue)
            || !currentFutureActions.contains(TechnicalQualityActionType.reduceIsoNoise.rawValue)
    }

    private func uniqueSemanticEvalActions(_ actions: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for action in actions where seen.insert(action).inserted {
            result.append(action)
        }
        return result
    }

    func testingMakeFeatureSnapshot(mode: AnalysisMode,
                                    frameId: String,
                                    capturedAt: Date,
                                    adapterState: PipelineFeatureSnapshotAdapterState) -> FrameFeatureSnapshot {
        makeFeatureSnapshot(
            mode: mode,
            frameId: frameId,
            capturedAt: capturedAt,
            adapterState: adapterState
        )
    }

    @MainActor
    func testingPublishLivePresentation(frameId: String,
                                        critique: CritiqueReport,
                                        plan: RecommendationPlan,
                                        semantics: SceneSemanticsReport? = nil,
                                        legacySuggestion: Suggestion?,
                                        structuredAvailable: Bool,
                                        now: Date = Date()) {
        let resolvedSemantics = semantics ?? SceneSemanticsReport(
            frameId: frameId,
            mode: critique.mode,
            sceneType: .unknown,
            sceneTypeConfidence: 0,
            primarySubject: .init(kind: .unknown, confidence: 0),
            dominance: .init(hasClearFocus: false, focusCompetitionScore: 0, backgroundClutterScore: 0),
            readability: .init(subjectReadable: false, lookSpaceAdequate: nil, edgePressureScore: 0, separationScore: 0),
            ambiguities: [],
            assumptions: []
        )
        let snapshot = makeFeatureSnapshot(
            mode: critique.mode,
            frameId: frameId,
            capturedAt: now
        )
        let semanticTips = semanticTipPlanner.plan(
            input: SemanticTipPlannerInput(
                frameId: frameId,
                mode: critique.mode,
                critique: critique,
                recommendationPlan: plan,
                semantics: resolvedSemantics
            )
        )
        publishLivePresentation(
            frameId: frameId,
            critique: critique,
            plan: plan,
            snapshot: snapshot,
            semantics: resolvedSemantics,
            semanticTips: semanticTips,
            legacySuggestion: legacySuggestion,
            structuredAvailable: structuredAvailable,
            now: now
        )
        if currentLiveHint?.id.hasPrefix("lh_demo_") == true {
            publishOverlayAnnotations(currentDemoOverlayAnnotations, now: now)
        } else if !currentDemoOverlayAnnotations.isEmpty {
            publishOverlayAnnotations(currentDemoOverlayAnnotations, now: now)
        }
    }

    @MainActor
    func testingPublishLivePresentation(frameId: String,
                                        snapshot: FrameFeatureSnapshot,
                                        critique: CritiqueReport,
                                        plan: RecommendationPlan,
                                        semantics: SceneSemanticsReport,
                                        legacySuggestion: Suggestion?,
                                        structuredAvailable: Bool,
                                        now: Date = Date()) {
        let semanticTips = semanticTipPlanner.plan(
            input: SemanticTipPlannerInput(
                frameId: frameId,
                mode: critique.mode,
                critique: critique,
                recommendationPlan: plan,
                semantics: semantics
            )
        )
        publishLivePresentation(
            frameId: frameId,
            critique: critique,
            plan: plan,
            snapshot: snapshot,
            semantics: semantics,
            semanticTips: semanticTips,
            legacySuggestion: legacySuggestion,
            structuredAvailable: structuredAvailable,
            now: now
        )
        if currentLiveHint?.id.hasPrefix("lh_demo_") == true {
            publishOverlayAnnotations(currentDemoOverlayAnnotations, now: now)
        } else if !currentDemoOverlayAnnotations.isEmpty {
            publishOverlayAnnotations(currentDemoOverlayAnnotations, now: now)
        }
    }

    @MainActor
    func testingApplyLiveHintCandidate(_ candidate: LiveHintPresentation?,
                                       now: Date = Date()) {
        applyLiveHint(candidate: candidate, now: now)
    }

    @MainActor
    func testingPreparePauseState(critique: PauseCritiquePresentation,
                                  traceBundle: ExplainabilityTraceBundle,
                                  revision: Int) {
        featureQueue.sync {
            pauseAnalysisRevision = revision
        }
        currentPauseCritique = critique
        currentPauseTraceBundle = traceBundle
        lastRefinedPauseFrameId = nil
    }

    func testingSchedulePauseReasoningRefinement(request: ReasoningRequest, revision: Int) {
        schedulePauseReasoningRefinement(request: request, revision: revision)
    }

    func testingBuildPauseVisualEvidenceRequest(snapshot: FrameFeatureSnapshot,
                                                semantics: SceneSemanticsReport,
                                                critique: CritiqueReport,
                                                plan: RecommendationPlan,
                                                neuralOutcome: NeuralEvidenceRecordedOutcome?) -> VLMVisualEvidenceRequest {
        makePauseVisualEvidenceRequest(
            snapshot: snapshot,
            semantics: semantics,
            critique: critique,
            plan: plan,
            neuralOutcome: neuralOutcome
        )
    }

    func testingResolvePauseVisualEvidence(request: VLMVisualEvidenceRequest) async -> VisualEvidenceCoordinatorResult {
        await visualSemanticEvidenceCoordinator.fetchEvidence(request: request)
    }

    @MainActor
    var testingPauseTraceBundle: ExplainabilityTraceBundle? {
        currentPauseTraceBundle
    }

    @MainActor
    var testingLiveFusionTraceBundle: ExplainabilityTraceBundle? {
        currentLiveFusionTraceBundle
    }

    func testingFuseCritique(snapshot: FrameFeatureSnapshot,
                             semantics: SceneSemanticsReport,
                             critique: CritiqueReport,
                             recordedOutcome: NeuralEvidenceRecordedOutcome?) -> HybridFusionOutput {
        hybridFusionService.fuse(
            HybridFusionInput(
                snapshot: snapshot,
                semantics: semantics,
                critique: critique,
                neuralSnapshot: executedNeuralSnapshot(from: recordedOutcome),
                neuralMetadata: executedNeuralMetadata(from: recordedOutcome)
            )
        )
    }

    func testingResolveCritiqueWithHybridFusion(mode: AnalysisMode,
                                                capturedAt: Date,
                                                pixelBuffer: CVPixelBuffer?,
                                                orientation: CGImagePropertyOrientation,
                                                snapshot: FrameFeatureSnapshot,
                                                semantics: SceneSemanticsReport,
                                                deterministicCritique: CritiqueReport,
                                                forcePauseExecution: Bool) async -> (HybridFusionOutput, NeuralEvidenceRecordedOutcome?) {
        await resolveCritiqueWithHybridFusion(
            mode: mode,
            capturedAt: capturedAt,
            pixelBuffer: pixelBuffer,
            orientation: orientation,
            snapshot: snapshot,
            semantics: semantics,
            deterministicCritique: deterministicCritique,
            forcePauseExecution: forcePauseExecution
        )
    }

    func testingMakePauseTraceBundle(critique: CritiqueReport,
                                     plan: RecommendationPlan,
                                     neuralSnapshot: NeuralEvidenceSnapshot?,
                                     fusionOutput: HybridFusionOutput) -> ExplainabilityTraceBundle {
        makePauseTraceBundle(
            critique: critique,
            plan: plan,
            neuralSnapshot: neuralSnapshot,
            fusionOutput: fusionOutput
        )
    }

    func testingPauseActionConfidence(action: RecommendationAction,
                                      plan: RecommendationPlan,
                                      critique: CritiqueReport,
                                      linkedIssueIds: [String]? = nil) -> Double {
        pauseActionConfidence(for: action, plan: plan, critique: critique, linkedIssueIds: linkedIssueIds)
    }

    func testingMakePauseCritiquePresentation(critique: CritiqueReport,
                                              plan: RecommendationPlan,
                                              semanticTips: [SemanticTipCandidate] = [],
                                              semanticFallbackUsed: Bool = false) -> PauseCritiquePresentation {
        makePauseCritiquePresentation(
            critique: critique,
            plan: plan,
            semanticTips: semanticTips,
            semanticFallbackUsed: semanticFallbackUsed
        )
    }

    func testingLiveActionConfidence(action: RecommendationAction,
                                     plan: RecommendationPlan,
                                     critique: CritiqueReport) -> Double {
        liveActionConfidence(for: action, plan: plan, critique: critique)
    }

    var testingHasPauseReasoningTask: Bool {
        pauseReasoningTask != nil
    }

    func testingIsAllowedDemoLiveSemanticAction(_ actionType: SemanticActionType) -> Bool {
        isAllowedDemoLiveSemanticAction(actionType)
    }

    @MainActor
    func testingRunNeuralEvidenceInference(mode: AnalysisMode,
                                           pixelBuffer: CVPixelBuffer,
                                           orientation: CGImagePropertyOrientation,
                                           snapshot: FrameFeatureSnapshot,
                                           semantics: SceneSemanticsReport,
                                           isStable: Bool,
                                           thermalTier: ThermalBudgetTier,
                                           heavyModelsEnabled: Bool,
                                           batteryLevel: Float?) async -> NeuralEvidenceRecordedOutcome? {
        guard let neuralEvidenceService else { return nil }
        let request = NeuralEvidenceInferenceRequest(
            frameId: snapshot.frameId,
            mode: mode,
            capturedAt: snapshot.capturedAt,
            pixelBuffer: pixelBuffer,
            orientation: orientation,
            sceneSemantics: semantics,
            primarySubjectRegion: snapshot.subjectSignals.primaryCandidateRegion,
            motionState: snapshot.motion.state,
            shakeLevel: snapshot.motion.shakeLevel,
            isStable: isStable,
            thermalTier: thermalTier,
            heavyModelsEnabled: heavyModelsEnabled,
            batteryLevel: batteryLevel,
            forcePauseExecution: mode == .pause
        )
        let outcome = await neuralEvidenceService.infer(request: request)
        let recorded = NeuralEvidenceRecordedOutcome(outcome)
        featureQueue.sync {
            switch mode {
            case .live:
                latestLiveNeuralOutcome = recorded
            case .pause:
                latestPauseNeuralOutcome = recorded
            }
        }
        return recorded
    }

    var testingLatestLiveNeuralOutcome: NeuralEvidenceRecordedOutcome? {
        featureQueue.sync { latestLiveNeuralOutcome }
    }

    var testingLatestPauseNeuralOutcome: NeuralEvidenceRecordedOutcome? {
        featureQueue.sync { latestPauseNeuralOutcome }
    }
}
#endif

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
