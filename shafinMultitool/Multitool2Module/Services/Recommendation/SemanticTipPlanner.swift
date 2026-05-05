import Foundation

struct SemanticTipPlannerInput: Sendable {
    let frameId: String
    let mode: AnalysisMode
    let critique: CritiqueReport
    let recommendationPlan: RecommendationPlan
    let semantics: SceneSemanticsReport
    let validatedEvidence: VLMEvidenceValidationResult?
    let currentLiveTipKey: String?

    init(frameId: String,
         mode: AnalysisMode,
         critique: CritiqueReport,
         recommendationPlan: RecommendationPlan,
         semantics: SceneSemanticsReport,
         validatedEvidence: VLMEvidenceValidationResult? = nil,
         currentLiveTipKey: String? = nil) {
        self.frameId = frameId
        self.mode = mode
        self.critique = critique
        self.recommendationPlan = recommendationPlan
        self.semantics = semantics
        self.validatedEvidence = validatedEvidence
        self.currentLiveTipKey = currentLiveTipKey
    }
}

struct SemanticTipPlannerOutput: Sendable {
    let livePrimaryTip: SemanticTipCandidate?
    let pauseExpandedTips: [SemanticTipCandidate]
    let allRankedCandidates: [SemanticTipCandidate]
    let selectionTraceNotes: [String]
    let fallbackUsed: Bool
}

struct SemanticTipPlanner {
    func plan(input: SemanticTipPlannerInput) -> SemanticTipPlannerOutput {
        guard input.frameId == input.critique.frameId,
              input.frameId == input.recommendationPlan.frameId,
              input.frameId == input.semantics.frameId,
              input.mode == input.critique.mode,
              input.mode == input.recommendationPlan.mode,
              input.mode == input.semantics.mode else {
            return SemanticTipPlannerOutput(
                livePrimaryTip: nil,
                pauseExpandedTips: [],
                allRankedCandidates: [],
                selectionTraceNotes: ["frame_or_mode_mismatch"],
                fallbackUsed: true
            )
        }

        let evidence = SemanticPlannerEvidence(validation: input.validatedEvidence)
        var notes: [String] = []
        var usedGenericFallback = false

        let rankedCandidates: [RankedSemanticTipCandidate]
        if input.critique.verdict == .good || input.critique.issues.isEmpty {
            rankedCandidates = makePositiveCandidates(input: input, evidence: evidence, usedGenericFallback: &usedGenericFallback)
        } else {
            rankedCandidates = makeCorrectiveCandidates(input: input, evidence: evidence, notes: &notes, usedGenericFallback: &usedGenericFallback)
        }

        let deduped = deduplicateAndSort(rankedCandidates)
        let allCandidates = deduped.map(\.candidate)

        let livePrimaryTip: SemanticTipCandidate?
        if input.mode == .live {
            livePrimaryTip = allCandidates.first
            if let livePrimaryTip {
                notes.append("live_primary=\(stableKey(for: livePrimaryTip))")
            }
        } else {
            livePrimaryTip = nil
        }

        let pauseExpandedTips: [SemanticTipCandidate]
        if input.mode == .pause {
            pauseExpandedTips = selectPauseTips(from: deduped, verdict: input.critique.verdict)
            if !pauseExpandedTips.isEmpty {
                notes.append("pause_count=\(pauseExpandedTips.count)")
            }
        } else {
            pauseExpandedTips = []
        }

        return SemanticTipPlannerOutput(
            livePrimaryTip: livePrimaryTip,
            pauseExpandedTips: pauseExpandedTips,
            allRankedCandidates: allCandidates,
            selectionTraceNotes: notes,
            fallbackUsed: input.critique.fallbackUsed || usedGenericFallback
        )
    }

    func stableKey(for candidate: SemanticTipCandidate) -> String {
        let anchorKey = candidate.problemType?.rawValue ?? candidate.strengthType?.rawValue ?? "none"
        let targetKey = candidate.targetEntityRef ?? candidate.targetEntityDisplayLabel
        let secondaryKey = candidate.secondaryEntityRef ?? candidate.secondaryEntityDisplayLabel ?? "none"
        return [
            candidate.tipType.rawValue,
            candidate.actionType.rawValue,
            anchorKey,
            targetKey,
            secondaryKey
        ].joined(separator: "|")
    }

    private func makeCorrectiveCandidates(input: SemanticTipPlannerInput,
                                          evidence: SemanticPlannerEvidence,
                                          notes: inout [String],
                                          usedGenericFallback: inout Bool) -> [RankedSemanticTipCandidate] {
        var ranked: [RankedSemanticTipCandidate] = []
        let allActions = orderedActions(plan: input.recommendationPlan)

        for action in allActions {
            guard let issue = primaryIssue(for: action, critique: input.critique) else { continue }
            let definitions = preferredDefinitions(
                for: issue,
                action: action,
                semantics: input.semantics,
                evidence: evidence,
                mode: input.mode
            )

            for (index, definition) in definitions.enumerated() {
                guard definition.supportedModes.contains(input.mode) else { continue }
                guard shouldInclude(definition: definition, issue: issue, evidence: evidence) else { continue }

                let anchors = materializeAnchors(
                    for: definition,
                    issue: issue,
                    action: action,
                    semantics: input.semantics,
                    evidence: evidence,
                    usedGenericFallback: &usedGenericFallback
                )
                let copy = copyTemplate(
                    for: definition.tipType,
                    target: anchors.targetDisplayLabel,
                    secondary: anchors.secondaryDisplayLabel
                )

                let candidate = SemanticTipCandidate(
                    tipType: definition.tipType,
                    actionType: definition.actionType,
                    actionFrame: definition.actionFrame,
                    direction: definition.direction,
                    problemType: resolvedProblemType(for: definition, issue: issue, evidence: evidence),
                    strengthType: nil,
                    targetEntityKind: definition.targetEntityKind,
                    targetEntityRole: definition.targetEntityRole,
                    targetEntityRef: anchors.targetEntityRef,
                    targetEntityGroundingConfidence: anchors.targetGroundingConfidence,
                    targetEntityDisplayLabel: anchors.targetDisplayLabel,
                    secondaryEntityRef: anchors.secondaryEntityRef,
                    secondaryEntityGroundingConfidence: anchors.secondaryGroundingConfidence,
                    secondaryEntityDisplayLabel: anchors.secondaryDisplayLabel,
                    primaryActionId: action.id,
                    linkedActionIds: [action.id],
                    linkedIssueIds: [issue.id],
                    linkedStrengthIds: [],
                    linkedTraceIds: linkedTraceIds(issue: issue, action: action, critique: input.critique),
                    summaryId: nil,
                    supportedModes: [input.mode],
                    priorityBand: definition.priorityBand,
                    liveText: copy.live,
                    pauseText: copy.pause,
                    fallbackBehavior: definition.fallbackBehavior
                )

                guard candidate.validate().isEmpty else { continue }

                let baseScore = score(
                    candidate: candidate,
                    issue: issue,
                    action: action,
                    evidence: evidence,
                    stickyLiveKey: input.currentLiveTipKey
                ) - (Double(index) * 0.05)

                ranked.append(
                    RankedSemanticTipCandidate(
                        candidate: candidate,
                        score: baseScore,
                        issueSeverity: issue.severity,
                        actionPriority: action.priority,
                        groundingConfidence: anchors.targetGroundingConfidence ?? 0
                    )
                )
            }
        }

        if ranked.isEmpty {
            notes.append("deterministic_only_fallback")
        }

        return ranked
    }

    private func makePositiveCandidates(input: SemanticTipPlannerInput,
                                        evidence: SemanticPlannerEvidence,
                                        usedGenericFallback: inout Bool) -> [RankedSemanticTipCandidate] {
        let strengthAnchors = input.critique.strengths.isEmpty ? [FrameStrength(
            id: "synthetic_frame_ready",
            type: .balancedCompositionForScene,
            confidence: input.critique.verdictConfidence,
            rationale: input.critique.summary.whyGood ?? input.critique.summary.shortVerdict,
            evidence: [EvidenceRef(source: .derivedRule, key: "summary.shortVerdict", value: input.critique.summary.shortVerdict)]
        )] : input.critique.strengths

        return strengthAnchors.enumerated().compactMap { index, strength in
            guard let definition = preferredPositiveDefinition(for: strength) else { return nil }
            let target = SemanticDisplayLabelPolicy.displayLabel(
                entityKind: definition.targetEntityKind,
                role: definition.targetEntityRole,
                groundedLabel: nil,
                confidence: 0
            )
            let copy = positiveCopyTemplate(
                for: definition.tipType,
                target: target,
                summary: input.critique.summary
            )
            let candidate = SemanticTipCandidate(
                tipType: definition.tipType,
                actionType: definition.actionType,
                actionFrame: definition.actionFrame,
                direction: definition.direction,
                problemType: nil,
                strengthType: resolvedStrengthType(for: definition, strength: strength),
                targetEntityKind: definition.targetEntityKind,
                targetEntityRole: definition.targetEntityRole,
                targetEntityRef: nil,
                targetEntityGroundingConfidence: nil,
                targetEntityDisplayLabel: target,
                secondaryEntityRef: nil,
                secondaryEntityGroundingConfidence: nil,
                secondaryEntityDisplayLabel: nil,
                primaryActionId: nil,
                linkedActionIds: [],
                linkedIssueIds: [],
                linkedStrengthIds: [strength.id],
                linkedTraceIds: input.critique.traceRefs.isEmpty ? [input.critique.summary.id] : input.critique.traceRefs,
                summaryId: input.critique.summary.id,
                supportedModes: [input.mode],
                priorityBand: definition.priorityBand,
                liveText: copy.live,
                pauseText: copy.pause,
                fallbackBehavior: definition.fallbackBehavior
            )

            guard candidate.validate().isEmpty else { return nil }
            return RankedSemanticTipCandidate(
                candidate: candidate,
                score: priorityWeight(definition.priorityBand) + strength.confidence + (evidence.hasAcceptedEvidence ? 0.02 : 0.0) - (Double(index) * 0.03),
                issueSeverity: 0,
                actionPriority: 0,
                groundingConfidence: 0
            )
        }
    }

    private func orderedActions(plan: RecommendationPlan) -> [RecommendationAction] {
        [plan.primaryAction].compactMap { $0 } + plan.secondaryActions + plan.deferredActions
    }

    private func primaryIssue(for action: RecommendationAction, critique: CritiqueReport) -> FrameIssue? {
        for issueId in action.linkedIssueIds {
            if let issue = critique.issues.first(where: { $0.id == issueId }) {
                return issue
            }
        }
        return critique.issues.first
    }

    private func preferredDefinitions(for issue: FrameIssue,
                                      action: RecommendationAction,
                                      semantics: SceneSemanticsReport,
                                      evidence: SemanticPlannerEvidence,
                                      mode: AnalysisMode) -> [SemanticTipDefinition] {
        switch issue.type {
        case .insufficientLookSpace:
            return [definition(for: horizontalLookSpaceTip(action: action, semantics: semantics))].compactMap { $0 }
        case .subjectTooCloseToEdge:
            if isObjectSubject(semantics: semantics, evidence: evidence) {
                return [definition(for: objectEdgeTip(action: action, semantics: semantics))].compactMap { $0 }
            }
            if action.actionType == .moveFrameUp {
                return [definition(for: .addHeadroom)].compactMap { $0 }
            }
            if action.actionType == .moveFrameDown && mode == .pause {
                return [definition(for: .showMoreLowerFrame), definition(for: .addHeadroom)].compactMap { $0 }
            }
            return [definition(for: subjectEdgeTip(action: action, semantics: semantics)),
                    definition(for: .stepBackForBreathingRoom)].compactMap { $0 }
        case .subjectNotProminentEnough:
            if isObjectSubject(semantics: semantics, evidence: evidence) {
                return [definition(for: .stepCloserForObjectProminence)].compactMap { $0 }
            }
            var tips: [SemanticTipType] = [.stepCloserForSubjectProminence]
            if mode == .pause && semantics.readability.separationScore < 0.55 {
                tips.append(.addDepthByMovingSubjectFromBackground)
            }
            if mode == .pause && evidence.supportsLightingSeparation {
                tips.append(.addBackgroundLightForSeparation)
            }
            return tips.compactMap { definition(for: $0) }
        case .backgroundCompetesWithSubject:
            if evidence.hasFaceContourConflict {
                return [definition(for: .removeObjectFromFaceContour),
                        definition(for: .changeAngleForCleanerBackground)].compactMap { $0 }
            }
            if evidence.hasGroundedDistractingObject {
                return [definition(for: .removeDistractingProp),
                        definition(for: .changeAngleForCleanerBackground)].compactMap { $0 }
            }
            if mode == .pause {
                return [definition(for: .moveObjectBackForBalance),
                        definition(for: .changeAngleForCleanerBackground)].compactMap { $0 }
            }
            return [definition(for: .changeAngleForCleanerBackground)].compactMap { $0 }
        case .backlightHidesSubject:
            var tips: [SemanticTipType] = []
            if evidence.hasBrightBackgroundConflict {
                tips.append(.removeBrightSpotBehindSubject)
            }
            tips.append(.turnSubjectTowardLight)
            if mode == .pause && issue.confidence >= 0.45 {
                if evidence.supportsLightingSeparation {
                    tips.append(.addBackgroundLightForSeparation)
                } else {
                    tips.append(.addFrontFillOnSubject)
                }
            }
            return uniqueDefinitions(tips)
        case .sceneHasNoClearFocus:
            var tips: [SemanticTipType] = [.clarifyMainSubjectFocus]
            if mode == .pause {
                tips.append(evidence.hasGroundedDistractingObject ? .removeDistractingProp : .simplifyBusyBackground)
            }
            return uniqueDefinitions(tips)
        case .frameVisuallyOverloaded:
            var tips: [SemanticTipType] = []
            if evidence.hasTimingBlocker {
                tips.append(.waitForBackgroundClearance)
            }
            tips.append(evidence.hasGroundedDistractingObject ? .removeDistractingProp : .simplifyBusyBackground)
            return uniqueDefinitions(tips)
        case .horizonDistracts:
            return [definition(for: .levelHorizonForStability)].compactMap { $0 }
        }
    }

    private func preferredPositiveDefinition(for strength: FrameStrength) -> SemanticTipDefinition? {
        switch strength.type {
        case .goodSubjectIsolation:
            return definition(for: .keepSubjectSeparation)
        case .goodLightEmphasis:
            return definition(for: .keepLightDirection)
        case .clearFocusHierarchy:
            return definition(for: .keepFocusHierarchy)
        case .stableHorizonSupportsScene:
            return definition(for: .keepHorizonStability)
        case .balancedCompositionForScene:
            return definition(for: .keepFrameAsIs)
        }
    }

    private func shouldInclude(definition: SemanticTipDefinition,
                               issue: FrameIssue,
                               evidence: SemanticPlannerEvidence) -> Bool {
        let isLightingTip = definition.actionFrame == .adjustLight || definition.tipType == .turnSubjectTowardLight
        if isLightingTip && issue.confidence < 0.45 {
            return false
        }
        if definition.tipType == .removeObjectFromFaceContour && !evidence.hasFaceContourConflict {
            return false
        }
        return true
    }

    private func resolvedProblemType(for definition: SemanticTipDefinition,
                                     issue: FrameIssue,
                                     evidence: SemanticPlannerEvidence) -> VisualProblemType {
        switch issue.type {
        case .subjectTooCloseToEdge:
            if definition.problemTypes.contains(.objectEdgePressure),
               (definition.targetEntityKind == .object || definition.targetEntityKind == .prop) {
                return .objectEdgePressure
            }
            if definition.problemTypes.contains(.tightFraming), definition.tipType == .addHeadroom || definition.tipType == .showMoreLowerFrame || definition.tipType == .stepBackForBreathingRoom {
                return .tightFraming
            }
            return .subjectEdgePressure
        case .subjectNotProminentEnough:
            if definition.problemTypes.contains(.weakObjectProminence), definition.targetEntityKind == .object {
                return .weakObjectProminence
            }
            if definition.problemTypes.contains(.weakSubjectBackgroundSeparation), evidence.supportsLightingSeparation || definition.tipType == .addDepthByMovingSubjectFromBackground {
                return .weakSubjectBackgroundSeparation
            }
            if definition.problemTypes.contains(.subjectBlendsIntoDarkBackground), evidence.supportsLightingSeparation && definition.tipType == .addBackgroundLightForSeparation {
                return .subjectBlendsIntoDarkBackground
            }
            return .weakSubjectProminence
        case .backgroundCompetesWithSubject:
            if definition.problemTypes.contains(.faceContourOcclusion), evidence.hasFaceContourConflict {
                return .faceContourOcclusion
            }
            if definition.problemTypes.contains(.objectConflictsWithSubject), evidence.hasGroundedDistractingObject {
                return .objectConflictsWithSubject
            }
            if definition.problemTypes.contains(.propBreaksBalance), definition.tipType == .moveObjectBackForBalance {
                return .propBreaksBalance
            }
            return .backgroundCompetition
        case .insufficientLookSpace:
            return .insufficientLookSpace
        case .backlightHidesSubject:
            if definition.problemTypes.contains(.brightBackgroundPull), evidence.hasBrightBackgroundConflict {
                return .brightBackgroundPull
            }
            if definition.problemTypes.contains(.subjectBlendsIntoDarkBackground), evidence.supportsLightingSeparation && definition.tipType == .addBackgroundLightForSeparation {
                return .subjectBlendsIntoDarkBackground
            }
            return .frontLightDeficit
        case .sceneHasNoClearFocus:
            if definition.problemTypes.contains(.backgroundClutter), definition.tipType == .simplifyBusyBackground {
                return .backgroundClutter
            }
            if definition.problemTypes.contains(.objectConflictsWithSubject), definition.tipType == .removeDistractingProp {
                return .objectConflictsWithSubject
            }
            return .unclearFocusHierarchy
        case .frameVisuallyOverloaded:
            if definition.problemTypes.contains(.timingBlockerInFrame), evidence.hasTimingBlocker {
                return .timingBlockerInFrame
            }
            if definition.problemTypes.contains(.objectConflictsWithSubject), definition.tipType == .removeDistractingProp {
                return .objectConflictsWithSubject
            }
            return .backgroundClutter
        case .horizonDistracts:
            return .tiltedHorizon
        }
    }

    private func resolvedStrengthType(for definition: SemanticTipDefinition,
                                      strength: FrameStrength) -> VisualStrengthType {
        switch strength.type {
        case .goodSubjectIsolation:
            return definition.strengthTypes.contains(.cleanSubjectSeparation) ? .cleanSubjectSeparation : .readableDepthLayers
        case .goodLightEmphasis:
            return .flatteringLightDirection
        case .clearFocusHierarchy:
            return definition.strengthTypes.contains(.clearFocusHierarchy) ? .clearFocusHierarchy : .readableDepthLayers
        case .stableHorizonSupportsScene:
            return .stableHorizon
        case .balancedCompositionForScene:
            return definition.strengthTypes.contains(.balancedSceneComposition) ? .balancedSceneComposition : .frameReady
        }
    }

    private func materializeAnchors(for definition: SemanticTipDefinition,
                                    issue: FrameIssue,
                                    action: RecommendationAction,
                                    semantics: SceneSemanticsReport,
                                    evidence: SemanticPlannerEvidence,
                                    usedGenericFallback: inout Bool) -> CandidateAnchors {
        switch definition.targetEntityKind {
        case .person:
            return CandidateAnchors(
                targetEntityRef: evidence.primaryEntityRefIfPerson,
                targetGroundingConfidence: evidence.confidence(forEntityRef: evidence.primaryEntityRefIfPerson),
                targetDisplayLabel: SemanticDisplayLabelPolicy.displayLabel(
                    entityKind: .person,
                    role: definition.targetEntityRole,
                    groundedLabel: evidence.primaryLabelIfPerson,
                    confidence: evidence.confidence(forEntityRef: evidence.primaryEntityRefIfPerson) ?? semantics.primarySubject.confidence,
                    direction: definition.direction
                ),
                secondaryEntityRef: nil,
                secondaryGroundingConfidence: nil,
                secondaryDisplayLabel: nil
            )
        case .object, .prop:
            let targetEntityRef = preferredObjectEntityRef(definition: definition, evidence: evidence)
            let targetConfidence = evidence.confidence(forEntityRef: targetEntityRef)
            let targetLabel = SemanticDisplayLabelPolicy.displayLabel(
                entityKind: definition.targetEntityKind,
                role: definition.targetEntityRole,
                groundedLabel: preferredObjectLabel(definition: definition, evidence: evidence),
                confidence: targetConfidence ?? 0,
                direction: definition.direction
            )
            if !SemanticDisplayLabelPolicy.isGroundedObjectDisplayLabel(targetLabel) {
                usedGenericFallback = true
            }

            let secondaryRef: String?
            let secondaryConfidence: Double?
            let secondaryLabel: String?
            if definition.tipType == .removeObjectFromFaceContour {
                secondaryRef = evidence.primaryEntityRefIfPerson
                secondaryConfidence = evidence.confidence(forEntityRef: secondaryRef)
                secondaryLabel = evidence.primaryLabelIfPerson ?? "герой"
            } else {
                secondaryRef = nil
                secondaryConfidence = nil
                secondaryLabel = nil
            }

            return CandidateAnchors(
                targetEntityRef: targetEntityRef,
                targetGroundingConfidence: targetConfidence,
                targetDisplayLabel: targetLabel,
                secondaryEntityRef: secondaryRef,
                secondaryGroundingConfidence: secondaryConfidence,
                secondaryDisplayLabel: secondaryLabel
            )
        case .backgroundArea, .lightSource, .frame, .face, .unknown:
            if definition.targetEntityKind == .backgroundArea && evidence.hasGroundedDistractingObject {
                usedGenericFallback = true
            }
            return CandidateAnchors(
                targetEntityRef: nil,
                targetGroundingConfidence: nil,
                targetDisplayLabel: SemanticDisplayLabelPolicy.displayLabel(
                    entityKind: definition.targetEntityKind,
                    role: definition.targetEntityRole,
                    groundedLabel: nil,
                    confidence: 0,
                    direction: definition.direction
                ),
                secondaryEntityRef: nil,
                secondaryGroundingConfidence: nil,
                secondaryDisplayLabel: nil
            )
        }
    }

    private func preferredObjectEntityRef(definition: SemanticTipDefinition, evidence: SemanticPlannerEvidence) -> String? {
        if definition.tipType == .removeObjectFromFaceContour || definition.tipType == .removeDistractingProp || definition.tipType == .rebalancePropLayout {
            return evidence.secondaryEntityRefIfObject ?? evidence.primaryEntityRefIfObject
        }
        return evidence.primaryEntityRefIfObject ?? evidence.secondaryEntityRefIfObject
    }

    private func preferredObjectLabel(definition: SemanticTipDefinition, evidence: SemanticPlannerEvidence) -> String? {
        if definition.tipType == .removeObjectFromFaceContour || definition.tipType == .removeDistractingProp || definition.tipType == .rebalancePropLayout {
            return evidence.secondaryLabelIfObject ?? evidence.primaryLabelIfObject
        }
        return evidence.primaryLabelIfObject ?? evidence.secondaryLabelIfObject
    }

    private func score(candidate: SemanticTipCandidate,
                       issue: FrameIssue,
                       action: RecommendationAction,
                       evidence: SemanticPlannerEvidence,
                       stickyLiveKey: String?) -> Double {
        var score = priorityWeight(candidate.priorityBand)
        score += issue.severity * 0.35
        score += issue.confidence * 0.25
        score += actionPriorityWeight(action.priority)
        score += min(candidate.targetEntityGroundingConfidence ?? 0, 1.0) * 0.08
        score += evidenceAdjustment(for: candidate, evidence: evidence)
        if stickyLiveKey == stableKey(for: candidate) {
            score += 0.02
        }
        return score
    }

    private func evidenceAdjustment(for candidate: SemanticTipCandidate,
                                    evidence: SemanticPlannerEvidence) -> Double {
        guard evidence.hasAcceptedEvidence else { return 0 }
        var delta = 0.0

        if evidence.suggestedActionIds.contains(candidate.actionType) {
            delta += evidence.modeCap
        }

        if let problemType = candidate.problemType,
           let confidence = evidence.problemConfidence(problemType) {
            delta += min(confidence * 0.05, evidence.modeCap)
        }

        if let strengthType = candidate.strengthType,
           let confidence = evidence.strengthConfidence(strengthType) {
            delta += min(confidence * 0.04, evidence.modeCap)
        }

        if candidate.tipType == .removeObjectFromFaceContour && evidence.hasFaceContourConflict {
            delta += 0.04
        }

        if candidate.tipType == .waitForBackgroundClearance && evidence.hasTimingBlocker {
            delta += 0.05
        }

        return delta
    }

    private func deduplicateAndSort(_ ranked: [RankedSemanticTipCandidate]) -> [RankedSemanticTipCandidate] {
        var deduped: [String: RankedSemanticTipCandidate] = [:]
        for entry in ranked {
            let key = duplicateKey(for: entry.candidate)
            if let current = deduped[key] {
                if compare(entry, current) == .orderedAscending {
                    deduped[key] = entry
                }
            } else {
                deduped[key] = entry
            }
        }

        return deduped.values.sorted { lhs, rhs in
            compare(lhs, rhs) == .orderedAscending
        }
    }

    private func duplicateKey(for candidate: SemanticTipCandidate) -> String {
        let issueKey = candidate.linkedIssueIds.sorted().joined(separator: "+")
        let targetKey = candidate.targetEntityRef ?? candidate.targetEntityDisplayLabel
        return [candidate.actionType.rawValue, targetKey, issueKey].joined(separator: "|")
    }

    private func compare(_ lhs: RankedSemanticTipCandidate, _ rhs: RankedSemanticTipCandidate) -> ComparisonResult {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score ? .orderedAscending : .orderedDescending
        }
        let lhsPriority = priorityWeight(lhs.candidate.priorityBand)
        let rhsPriority = priorityWeight(rhs.candidate.priorityBand)
        if lhsPriority != rhsPriority {
            return lhsPriority > rhsPriority ? .orderedAscending : .orderedDescending
        }
        if lhs.issueSeverity != rhs.issueSeverity {
            return lhs.issueSeverity > rhs.issueSeverity ? .orderedAscending : .orderedDescending
        }
        if lhs.actionPriority != rhs.actionPriority {
            return lhs.actionPriority < rhs.actionPriority ? .orderedAscending : .orderedDescending
        }
        if lhs.groundingConfidence != rhs.groundingConfidence {
            return lhs.groundingConfidence > rhs.groundingConfidence ? .orderedAscending : .orderedDescending
        }
        let lhsTip = lhs.candidate.tipType.rawValue
        let rhsTip = rhs.candidate.tipType.rawValue
        if lhsTip != rhsTip {
            return lhsTip < rhsTip ? .orderedAscending : .orderedDescending
        }
        let lhsAction = lhs.candidate.primaryActionId ?? ""
        let rhsAction = rhs.candidate.primaryActionId ?? ""
        return lhsAction < rhsAction ? .orderedAscending : .orderedDescending
    }

    private func selectPauseTips(from ranked: [RankedSemanticTipCandidate],
                                 verdict: FrameVerdict) -> [SemanticTipCandidate] {
        if verdict == .good {
            return Array(ranked.prefix(2).map(\.candidate))
        }

        var selected: [SemanticTipCandidate] = []
        var timingCount = 0
        var positiveCount = 0

        for candidate in ranked.map(\.candidate) {
            if candidate.priorityBand == .timingCorrective {
                guard timingCount == 0 else { continue }
                timingCount += 1
            }
            if candidate.priorityBand == .positiveConfirmation {
                guard positiveCount == 0 else { continue }
                positiveCount += 1
            }
            selected.append(candidate)
            if selected.count == 4 {
                break
            }
        }

        return selected
    }

    private func linkedTraceIds(issue: FrameIssue,
                                action: RecommendationAction,
                                critique: CritiqueReport) -> [String] {
        let issueSpecific = critique.traceRefs.filter { $0.contains(issue.id) || $0.contains("_crit_") }
        if !issueSpecific.isEmpty {
            return issueSpecific
        }
        return critique.traceRefs.isEmpty ? [action.id] : critique.traceRefs
    }

    private func definition(for tipType: SemanticTipType) -> SemanticTipDefinition? {
        SemanticTipCatalog.definition(for: tipType)
    }

    private func uniqueDefinitions(_ tipTypes: [SemanticTipType]) -> [SemanticTipDefinition] {
        var seen: Set<SemanticTipType> = []
        return tipTypes.compactMap { tipType in
            guard !seen.contains(tipType) else { return nil }
            seen.insert(tipType)
            return definition(for: tipType)
        }
    }

    private func horizontalLookSpaceTip(action: RecommendationAction,
                                        semantics: SceneSemanticsReport) -> SemanticTipType {
        switch action.actionType {
        case .moveFrameLeft:
            return .createLookSpaceLeft
        case .moveFrameRight:
            return .createLookSpaceRight
        default:
            return semantics.primarySubject.region.map { $0.x > 0.5 ? .createLookSpaceLeft : .createLookSpaceRight } ?? .createLookSpaceLeft
        }
    }

    private func subjectEdgeTip(action: RecommendationAction,
                                semantics: SceneSemanticsReport) -> SemanticTipType {
        switch action.actionType {
        case .moveFrameLeft:
            return .moveSubjectOffRightEdge
        case .moveFrameRight:
            return .moveSubjectOffLeftEdge
        default:
            return semantics.primarySubject.region.map { $0.x > 0.5 ? .moveSubjectOffRightEdge : .moveSubjectOffLeftEdge } ?? .moveSubjectOffRightEdge
        }
    }

    private func objectEdgeTip(action: RecommendationAction,
                               semantics: SceneSemanticsReport) -> SemanticTipType {
        switch action.actionType {
        case .moveFrameLeft:
            return .moveObjectOffRightEdge
        case .moveFrameRight:
            return .moveObjectOffLeftEdge
        default:
            return semantics.primarySubject.region.map { $0.x > 0.5 ? .moveObjectOffRightEdge : .moveObjectOffLeftEdge } ?? .moveObjectOffRightEdge
        }
    }

    private func isObjectSubject(semantics: SceneSemanticsReport,
                                 evidence: SemanticPlannerEvidence) -> Bool {
        semantics.primarySubject.kind == .object || evidence.primaryEntityKindIsObject
    }

    private func priorityWeight(_ band: SemanticTipPriorityBand) -> Double {
        switch band {
        case .primaryCorrective:
            return 1.0
        case .secondaryCorrective:
            return 0.8
        case .contextualCorrective:
            return 0.6
        case .timingCorrective:
            return 0.5
        case .positiveConfirmation:
            return 0.4
        }
    }

    private func actionPriorityWeight(_ priority: Int) -> Double {
        switch priority {
        case 1:
            return 0.20
        case 2:
            return 0.10
        default:
            return 0.0
        }
    }

    private func copyTemplate(for tipType: SemanticTipType,
                              target: String,
                              secondary: String?) -> (live: String, pause: String) {
        switch tipType {
        case .createLookSpaceLeft:
            return ("Смести камеру чуть левее.", "Слева не хватает воздуха. Смести камеру чуть левее.")
        case .createLookSpaceRight:
            return ("Смести камеру чуть правее.", "Справа не хватает воздуха. Смести камеру чуть правее.")
        case .moveSubjectOffLeftEdge:
            return ("Смести героя чуть правее.", "Герой зажат слева. Смести его чуть правее.")
        case .moveSubjectOffRightEdge:
            return ("Смести героя чуть левее.", "Герой зажат справа. Смести его чуть левее.")
        case .moveObjectOffLeftEdge:
            return ("Сдвинь \(target) правее.", "\(target.capitalized) слишком близко к левому краю. Сдвинь \(target) правее.")
        case .moveObjectOffRightEdge:
            return ("Сдвинь \(target) левее.", "\(target.capitalized) слишком близко к правому краю. Сдвинь \(target) левее.")
        case .addHeadroom:
            return ("Подними камеру чуть выше.", "Сверху тесно. Подними камеру чуть выше.")
        case .showMoreLowerFrame:
            return ("Опусти камеру чуть ниже.", "Снизу не хватает пространства. Опусти камеру чуть ниже.")
        case .stepBackForBreathingRoom:
            return ("Отойди на полшага назад.", "Кадру не хватает воздуха. Отойди на полшага назад.")
        case .stepCloserForSubjectProminence:
            return ("Подойди чуть ближе к герою.", "Герой читается слабо. Подойди чуть ближе к нему.")
        case .stepCloserForObjectProminence:
            return ("Подойди чуть ближе к \(target).", "\(target.capitalized) теряется в кадре. Подойди чуть ближе к \(target).")
        case .lowerCameraForSubject:
            return ("Опусти камеру чуть ниже.", "Высота камеры спорит с героем. Опусти камеру чуть ниже.")
        case .raiseCameraForSubject:
            return ("Подними камеру чуть выше.", "Высота камеры спорит с героем. Подними камеру чуть выше.")
        case .changeAngleForCleanerBackground:
            return ("Смени угол камеры.", "Фон спорит с главным объектом. Смени угол камеры, чтобы фон стал чище.")
        case .addDepthByMovingSubjectFromBackground:
            return ("Отодвинь героя от фона.", "Герой сливается с фоном. Отодвинь его от фона.")
        case .addDepthByMovingObjectForward:
            return ("Сдвинь \(target) чуть вперед.", "\(target.capitalized) теряется по глубине. Сдвинь \(target) чуть вперед.")
        case .moveObjectBackForBalance:
            return ("Сдвинь \(target) чуть назад.", "\(target.capitalized) спорит с героем. Сдвинь \(target) чуть назад.")
        case .moveSubjectLeftForBalance:
            return ("Смести героя чуть левее.", "Смести героя чуть левее, чтобы баланс кадра стал спокойнее.")
        case .moveSubjectRightForBalance:
            return ("Смести героя чуть правее.", "Смести героя чуть правее, чтобы баланс кадра стал спокойнее.")
        case .moveObjectLeftForBalance:
            return ("Сдвинь \(target) левее.", "\(target.capitalized) перегружает правую часть кадра. Сдвинь \(target) левее.")
        case .moveObjectRightForBalance:
            return ("Сдвинь \(target) правее.", "\(target.capitalized) перегружает левую часть кадра. Сдвинь \(target) правее.")
        case .removeObjectFromFaceContour:
            return ("Убери \(target) от лица.", "\(target.capitalized) заходит на контур лица. Убери \(target) в сторону.")
        case .removeDistractingProp:
            return ("Убери \(target) из кадра.", "\(target.capitalized) спорит с главным объектом. Убери \(target) из кадра.")
        case .rebalancePropLayout:
            return ("Переставь \(target).", "Положение \(target) ломает баланс кадра. Переставь \(target).")
        case .turnSubjectTowardLight:
            return ("Поверни героя к свету.", "Свет сейчас прячет героя. Поверни его к источнику света.")
        case .addFrontFillOnSubject:
            return ("Добавь мягкий фронтальный свет.", "Лицу не хватает света спереди. Добавь мягкий фронтальный свет.")
        case .addBackgroundLightForSeparation:
            return ("Добавь слабый свет на фон.", "Фон сливается с главным объектом. Добавь слабый свет на фон.")
        case .removeBrightSpotBehindSubject:
            return ("Убери яркое пятно за героем.", "Яркое пятно за героем перетягивает внимание. Убери его.")
        case .clarifyMainSubjectFocus:
            return ("Подойди чуть ближе к герою.", "В кадре нет явного центра внимания. Подойди чуть ближе к герою.")
        case .simplifyBusyBackground:
            return ("Упрости фон.", "Фон перегружен и спорит с главным объектом. Упрости фон.")
        case .waitForBackgroundClearance:
            return ("Подожди, пока фон очистится.", "В фоне есть временная помеха. Подожди, пока она уйдет.")
        case .levelHorizonForStability:
            return ("Выровняй горизонт.", "Горизонт завален и отвлекает. Выровняй его.")
        case .keepSubjectSeparation, .keepLightDirection, .keepFocusHierarchy, .keepHorizonStability, .keepDepthReadability, .keepObjectBalance, .keepFrameAsIs:
            return positiveCopyTemplate(for: tipType, target: target, summary: .init(id: "", shortVerdict: "Кадр уже читается хорошо."))
        }
    }

    private func positiveCopyTemplate(for tipType: SemanticTipType,
                                      target: String,
                                      summary: CritiqueSummary) -> (live: String, pause: String) {
        switch tipType {
        case .keepSubjectSeparation:
            return ("Кадр уже читается хорошо.", "Кадр уже читается хорошо: герой отделен от фона.")
        case .keepLightDirection:
            return ("Свет уже работает хорошо.", "Свет уже работает хорошо: лицо читается мягко и уверенно.")
        case .keepFocusHierarchy:
            return ("Фокус в кадре уже держится.", "Фокус в кадре уже держится: главный объект читается первым.")
        case .keepHorizonStability:
            return ("Горизонт уже держится ровно.", "Горизонт уже держится ровно и не отвлекает.")
        case .keepDepthReadability:
            return ("Глубина кадра уже читается.", "Глубина кадра уже читается: планы не спорят между собой.")
        case .keepObjectBalance:
            return ("Баланс предметов уже хороший.", "Баланс предметов уже хороший: \(target) не перегружает кадр.")
        case .keepFrameAsIs:
            let live = summary.shortVerdict.isEmpty ? "Кадр уже читается хорошо." : summary.shortVerdict
            let pause = summary.whyGood ?? "Кадр уже читается хорошо: композиция и фокус держатся уверенно."
            return (live, pause)
        default:
            return ("Кадр уже читается хорошо.", "Кадр уже читается хорошо.")
        }
    }
}

private struct RankedSemanticTipCandidate {
    let candidate: SemanticTipCandidate
    let score: Double
    let issueSeverity: Double
    let actionPriority: Int
    let groundingConfidence: Double
}

private struct CandidateAnchors {
    let targetEntityRef: String?
    let targetGroundingConfidence: Double?
    let targetDisplayLabel: String
    let secondaryEntityRef: String?
    let secondaryGroundingConfidence: Double?
    let secondaryDisplayLabel: String?
}

private struct SemanticPlannerEvidence {
    let validation: VLMEvidenceValidationResult?

    var hasAcceptedEvidence: Bool {
        validation?.accepted == true
    }

    var modeCap: Double {
        validation?.accepted == true ? 0.06 : 0.0
    }

    var suggestedActionIds: Set<SemanticActionType> {
        Set(validation?.acceptedSuggestedActionIds ?? [])
    }

    var hasGroundedDistractingObject: Bool {
        secondaryEntityRefIfObject != nil || primaryEntityRefIfObject != nil
    }

    var hasFaceContourConflict: Bool {
        validation?.acceptedObservations.contains(where: { $0.visualProblemType == .faceContourOcclusion }) == true
            || validation?.acceptedRelations.contains(where: { $0.relationType == .blocks }) == true
    }

    var hasBrightBackgroundConflict: Bool {
        validation?.acceptedObservations.contains(where: { $0.visualProblemType == .brightBackgroundPull }) == true
    }

    var hasTimingBlocker: Bool {
        validation?.acceptedObservations.contains(where: { $0.visualProblemType == .timingBlockerInFrame }) == true
            || suggestedActionIds.contains(.waitForBackgroundClearance)
    }

    var supportsLightingSeparation: Bool {
        validation?.acceptedObservations.contains(where: {
            $0.dimension == .lightingRelation
                && ($0.visualProblemType == .subjectBlendsIntoDarkBackground
                    || $0.visualProblemType == .weakSubjectBackgroundSeparation
                    || $0.visualProblemType == .frontLightDeficit)
        }) == true
    }

    var primaryEntityKindIsObject: Bool {
        guard let kind = validation?.acceptedPrimaryEntityKind else { return false }
        return kind == .object || kind == .prop
    }

    var primaryEntityRefIfPerson: String? {
        guard let validation, validation.accepted else { return nil }
        guard let kind = validation.acceptedPrimaryEntityKind, kind == .person || kind == .face else { return nil }
        return validation.acceptedPrimaryEntityRef
    }

    var primaryLabelIfPerson: String? {
        primaryEntityRefIfPerson == nil ? nil : validation?.acceptedPrimaryLabel
    }

    var primaryEntityRefIfObject: String? {
        guard let validation, validation.accepted else { return nil }
        guard let kind = validation.acceptedPrimaryEntityKind, kind == .object || kind == .prop else { return nil }
        return validation.acceptedPrimaryEntityRef
    }

    var primaryLabelIfObject: String? {
        primaryEntityRefIfObject == nil ? nil : validation?.acceptedPrimaryLabel
    }

    var secondaryEntityRefIfObject: String? {
        guard let validation, validation.accepted else { return nil }
        guard let kind = validation.acceptedSecondaryEntityKind, kind == .object || kind == .prop else { return nil }
        return validation.acceptedSecondaryEntityRef
    }

    var secondaryLabelIfObject: String? {
        secondaryEntityRefIfObject == nil ? nil : validation?.acceptedSecondaryLabel
    }

    func confidence(forEntityRef entityRef: String?) -> Double? {
        guard let entityRef else { return nil }
        let observationConfidence = validation?.acceptedObservations
            .filter { $0.primaryEntityRef == entityRef || $0.secondaryEntityRef == entityRef }
            .map(\.confidence)
            .max()
        let relationConfidence = validation?.acceptedRelations
            .filter { $0.sourceEntityRef == entityRef || $0.targetEntityRef == entityRef }
            .map(\.confidence)
            .max()
        return [observationConfidence, relationConfidence].compactMap { $0 }.max()
    }

    func problemConfidence(_ problemType: VisualProblemType) -> Double? {
        validation?.acceptedObservations
            .filter { $0.visualProblemType == problemType }
            .map(\.confidence)
            .max()
    }

    func strengthConfidence(_ strengthType: VisualStrengthType) -> Double? {
        validation?.acceptedObservations
            .filter { $0.visualStrengthType == strengthType }
            .map(\.confidence)
            .max()
    }
}
