import Foundation

struct HybridFusionInput: Sendable {
    let snapshot: FrameFeatureSnapshot
    let semantics: SceneSemanticsReport
    let critique: CritiqueReport
    let neuralSnapshot: NeuralEvidenceSnapshot?
    let neuralMetadata: NeuralEvidenceRuntimeMetadata?
}

enum HybridFusionTargetKind: String, Codable, Sendable {
    case issue
    case strength
}

enum HybridFusionDecisionOutcome: String, Codable, Sendable {
    case unchanged
    case reinforced
    case softened
    case ignored
}

struct HybridFusionDecision: Codable, Equatable, Sendable {
    let decisionId: String
    let targetKind: HybridFusionTargetKind
    let targetId: String
    let targetType: String
    let outcome: HybridFusionDecisionOutcome
    let delta: Double
    let deterministicConfidenceBefore: Double
    let fusedConfidenceAfter: Double
    let appliedHeadIds: [EvidenceHeadId]
    let note: String

    var applied: Bool {
        outcome == .reinforced || outcome == .softened
    }
}

struct HybridFusionOutput: Sendable {
    let critique: CritiqueReport
    let decisions: [HybridFusionDecision]

    var appliedDecisions: [HybridFusionDecision] {
        decisions.filter(\.applied)
    }
}

struct HybridFusionService {
    private enum Constants {
        static let liveModeCap = 0.10
        static let pauseModeCap = 0.18
        static let degradedModeCap = 0.08
        static let userFacingDeltaThreshold = 0.03
        static let contextualMaxAbsoluteDelta = 0.05
    }

    private enum HeadRole {
        case primary
        case secondary
        case contextual

        var weight: Double {
            switch self {
            case .primary:
                return 1.0
            case .secondary:
                return 0.60
            case .contextual:
                return 0.35
            }
        }
    }

    private struct Contribution {
        let headId: EvidenceHeadId
        let role: HeadRole
        let supportScore: Double
        let confidence: Double
    }

    private struct FusedIssueResult {
        let issue: FrameIssue
        let deterministicIssue: FrameIssue
        let originalIndex: Int
        let rankingConfidence: Double
        let decision: HybridFusionDecision
    }

    private struct FusedStrengthResult {
        let strength: FrameStrength
        let deterministicStrength: FrameStrength
        let originalIndex: Int
        let rankingConfidence: Double
        let decision: HybridFusionDecision
    }

    private struct HeadIndex {
        let scalarOutputs: [EvidenceHeadId: ScalarEvidenceHeadOutput]
        let shotTypeOutput: CategoricalEvidenceHeadOutput?

        init(snapshot: NeuralEvidenceSnapshot) {
            var scalarOutputs: [EvidenceHeadId: ScalarEvidenceHeadOutput] = [:]
            var shotTypeOutput: CategoricalEvidenceHeadOutput?
            for entry in snapshot.headOutputs {
                switch entry.payload {
                case let .scalar(output):
                    scalarOutputs[entry.headId] = output
                case let .categorical(output):
                    if entry.headId == .shotTypeConfidence {
                        shotTypeOutput = output
                    }
                }
            }
            self.scalarOutputs = scalarOutputs
            self.shotTypeOutput = shotTypeOutput
        }
    }

    private let summaryBuilder = DeterministicCritiqueSummaryBuilder()

    func fuse(_ input: HybridFusionInput) -> HybridFusionOutput {
        guard let neuralSnapshot = eligibleSnapshot(for: input) else {
            return HybridFusionOutput(critique: input.critique, decisions: [])
        }

        let headIndex = HeadIndex(snapshot: neuralSnapshot)
        let degraded = input.critique.fallbackUsed
        let modeCap = degraded ? Constants.degradedModeCap : modeCap(for: input.snapshot.mode)

        let fusedIssues = input.critique.issues.enumerated().map { offset, issue in
            fuseIssue(issue,
                      originalIndex: offset,
                      input: input,
                      headIndex: headIndex,
                      degraded: degraded,
                      modeCap: modeCap)
        }
        let fusedStrengths = input.critique.strengths.enumerated().map { offset, strength in
            fuseStrength(strength,
                         originalIndex: offset,
                         input: input,
                         headIndex: headIndex,
                         degraded: degraded,
                         modeCap: modeCap)
        }

        let sortedIssues = fusedIssues.sorted { lhs, rhs in
            if lhs.issue.severity != rhs.issue.severity {
                return lhs.issue.severity > rhs.issue.severity
            }
            if (lhs.decision.applied || rhs.decision.applied),
               lhs.rankingConfidence != rhs.rankingConfidence {
                return lhs.rankingConfidence > rhs.rankingConfidence
            }
            return lhs.originalIndex < rhs.originalIndex
        }
        let sortedStrengths = fusedStrengths.sorted { lhs, rhs in
            if (lhs.decision.applied || rhs.decision.applied),
               lhs.rankingConfidence != rhs.rankingConfidence {
                return lhs.rankingConfidence > rhs.rankingConfidence
            }
            return lhs.originalIndex < rhs.originalIndex
        }

        let issueValues = sortedIssues.map(\.issue)
        let strengthValues = sortedStrengths.map(\.strength)
        let decisions = (sortedIssues.map(\.decision) + sortedStrengths.map(\.decision))
            .sorted { $0.decisionId < $1.decisionId }

        let hasFindingMutation = sortedIssues.contains(where: issueChanged)
            || sortedStrengths.contains(where: strengthChanged)
        let issueOrderChanged = issueValues.map(\.id) != input.critique.issues.map(\.id)
        let strengthOrderChanged = strengthValues.map(\.id) != input.critique.strengths.map(\.id)

        guard hasFindingMutation || issueOrderChanged || strengthOrderChanged else {
            return HybridFusionOutput(critique: input.critique, decisions: decisions)
        }

        let summary = summaryBuilder.makeSummary(
            summaryId: input.critique.summary.id,
            verdict: input.critique.verdict,
            rankedStrengths: strengthValues,
            rankedIssues: issueValues
        )
        let summaryTraceRef = input.critique.traceRefs.first(where: { $0.contains("_crit_summary_") })
            ?? "trc_\(input.critique.frameId)_crit_summary_main"
        let traceRefs = regeneratedTraceRefs(
            frameId: input.critique.frameId,
            issues: issueValues,
            strengths: strengthValues,
            summaryTraceRef: summaryTraceRef
        )

        let critique = CritiqueReport(
            frameId: input.critique.frameId,
            mode: input.critique.mode,
            verdict: input.critique.verdict,
            verdictConfidence: input.critique.verdictConfidence,
            strengths: strengthValues,
            issues: issueValues,
            summary: summary,
            traceRefs: traceRefs,
            fallbackUsed: input.critique.fallbackUsed
        )
        return HybridFusionOutput(critique: critique, decisions: decisions)
    }

    private func eligibleSnapshot(for input: HybridFusionInput) -> NeuralEvidenceSnapshot? {
        guard let neuralSnapshot = input.neuralSnapshot else { return nil }
        guard neuralSnapshot.frameId == input.critique.frameId,
              neuralSnapshot.mode == input.critique.mode else {
            return nil
        }
        guard input.neuralMetadata?.frameId == input.critique.frameId || input.neuralMetadata == nil else {
            return nil
        }
        return neuralSnapshot
    }

    private func fuseIssue(_ issue: FrameIssue,
                           originalIndex: Int,
                           input: HybridFusionInput,
                           headIndex: HeadIndex,
                           degraded: Bool,
                           modeCap: Double) -> FusedIssueResult {
        let contributions = issueContributions(
            for: issue.type,
            input: input,
            headIndex: headIndex,
            degraded: degraded,
            modeCap: modeCap
        )
        let fusion = fusedConfidence(
            targetKind: .issue,
            targetId: issue.id,
            targetType: issue.type.rawValue,
            originalConfidence: issue.confidence,
            contributions: contributions,
            modeCap: modeCap
        )
        return FusedIssueResult(
            issue: FrameIssue(
                id: issue.id,
                type: issue.type,
                severity: issue.severity,
                confidence: fusion.fusedConfidence,
                rationale: issue.rationale,
                evidence: issue.evidence,
                affectedRegion: issue.affectedRegion,
                suggestedFixTypes: issue.suggestedFixTypes
            ),
            deterministicIssue: issue,
            originalIndex: originalIndex,
            rankingConfidence: fusion.rankingConfidence,
            decision: fusion.decision
        )
    }

    private func fuseStrength(_ strength: FrameStrength,
                              originalIndex: Int,
                              input: HybridFusionInput,
                              headIndex: HeadIndex,
                              degraded: Bool,
                              modeCap: Double) -> FusedStrengthResult {
        let contributions = strengthContributions(
            for: strength.type,
            input: input,
            headIndex: headIndex,
            degraded: degraded,
            modeCap: modeCap
        )
        let fusion = fusedConfidence(
            targetKind: .strength,
            targetId: strength.id,
            targetType: strength.type.rawValue,
            originalConfidence: strength.confidence,
            contributions: contributions,
            modeCap: modeCap
        )
        return FusedStrengthResult(
            strength: FrameStrength(
                id: strength.id,
                type: strength.type,
                confidence: fusion.fusedConfidence,
                rationale: strength.rationale,
                evidence: strength.evidence,
                supportingRegion: strength.supportingRegion
            ),
            deterministicStrength: strength,
            originalIndex: originalIndex,
            rankingConfidence: fusion.rankingConfidence,
            decision: fusion.decision
        )
    }

    private func fusedConfidence(targetKind: HybridFusionTargetKind,
                                 targetId: String,
                                 targetType: String,
                                 originalConfidence: Double,
                                 contributions: [Contribution],
                                 modeCap: Double) -> (fusedConfidence: Double, rankingConfidence: Double, decision: HybridFusionDecision) {
        let decisionId = "fusion_\(targetKind.rawValue)_\(targetId)"
        guard !contributions.isEmpty else {
            return (
                originalConfidence,
                originalConfidence,
                HybridFusionDecision(
                    decisionId: decisionId,
                    targetKind: targetKind,
                    targetId: targetId,
                    targetType: targetType,
                    outcome: .ignored,
                    delta: 0,
                    deterministicConfidenceBefore: originalConfidence,
                    fusedConfidenceAfter: originalConfidence,
                    appliedHeadIds: [],
                    note: "No eligible neural heads."
                )
            )
        }

        let denominator = max(1.0, contributions.reduce(0.0) { $0 + abs($1.role.weight) })
        let weightedSum = contributions.reduce(0.0) { partial, contribution in
            let centered = (contribution.supportScore - 0.5) * 2.0
            return partial + (centered * contribution.role.weight * contribution.confidence)
        }
        let normalized = clamp(weightedSum / denominator, min: -1.0, max: 1.0)
        let delta = denominator == 0 ? 0 : (modeCap * normalized)
        let absoluteDelta = abs(delta)
        let appliedHeadIds = contributions.map(\.headId)

        if absoluteDelta < Constants.userFacingDeltaThreshold {
            return (
                originalConfidence,
                originalConfidence,
                HybridFusionDecision(
                    decisionId: decisionId,
                    targetKind: targetKind,
                    targetId: targetId,
                    targetType: targetType,
                    outcome: .unchanged,
                    delta: delta,
                    deterministicConfidenceBefore: originalConfidence,
                    fusedConfidenceAfter: originalConfidence,
                    appliedHeadIds: appliedHeadIds,
                    note: "Fusion delta stayed below the user-facing threshold."
                )
            )
        }

        let fusedConfidence = clamp01(originalConfidence + delta)
        let outcome: HybridFusionDecisionOutcome = delta >= 0 ? .reinforced : .softened
        return (
            fusedConfidence,
            fusedConfidence,
            HybridFusionDecision(
                decisionId: decisionId,
                targetKind: targetKind,
                targetId: targetId,
                targetType: targetType,
                outcome: outcome,
                delta: delta,
                deterministicConfidenceBefore: originalConfidence,
                fusedConfidenceAfter: fusedConfidence,
                appliedHeadIds: appliedHeadIds,
                note: outcome == .reinforced ? "Bounded neural evidence reinforced the existing finding." : "Bounded neural evidence softened the existing finding."
            )
        )
    }

    private func issueContributions(for type: IssueTypeV1,
                                    input: HybridFusionInput,
                                    headIndex: HeadIndex,
                                    degraded: Bool,
                                    modeCap: Double) -> [Contribution] {
        if degraded {
            switch type {
            case .backlightHidesSubject:
                return [
                    scalarContribution(headId: .lightingQuality, role: .primary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { 1.0 - $0 }),
                    scalarContribution(headId: .faceSaliency, role: .secondary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { 1.0 - $0 })
                ].compactMap { $0 }
            case .subjectNotProminentEnough:
                return [
                    scalarContribution(headId: .subjectProminence, role: .primary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { 1.0 - $0 }),
                    scalarContribution(headId: .backgroundClutter, role: .secondary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { $0 }),
                    scalarContribution(headId: .faceSaliency, role: .secondary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { 1.0 - $0 })
                ].compactMap { $0 }
            default:
                return []
            }
        }

        switch type {
        case .subjectTooCloseToEdge:
            return [
                scalarContribution(headId: .faceSaliency, role: .primary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { 1.0 - $0 }),
                scalarContribution(headId: .subjectProminence, role: .secondary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { 1.0 - $0 }),
                scalarContribution(headId: .balanceConfidence, role: .contextual, input: input, headIndex: headIndex, modeCap: modeCap, transform: { 1.0 - $0 }),
                shotTypeContribution(kind: .edgePressure, role: .contextual, input: input, headIndex: headIndex, modeCap: modeCap)
            ].compactMap { $0 }
        case .subjectNotProminentEnough:
            return [
                scalarContribution(headId: .subjectProminence, role: .primary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { 1.0 - $0 }),
                scalarContribution(headId: .backgroundClutter, role: .secondary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { $0 }),
                scalarContribution(headId: .faceSaliency, role: .secondary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { 1.0 - $0 }),
                scalarContribution(headId: .depthSeparation, role: .contextual, input: input, headIndex: headIndex, modeCap: modeCap, transform: { 1.0 - $0 })
            ].compactMap { $0 }
        case .backgroundCompetesWithSubject:
            return [
                scalarContribution(headId: .backgroundClutter, role: .primary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { $0 }),
                scalarContribution(headId: .subjectProminence, role: .secondary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { 1.0 - $0 }),
                scalarContribution(headId: .depthSeparation, role: .contextual, input: input, headIndex: headIndex, modeCap: modeCap, transform: { 1.0 - $0 })
            ].compactMap { $0 }
        case .insufficientLookSpace:
            return [
                scalarContribution(headId: .faceSaliency, role: .primary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { 1.0 - $0 }),
                scalarContribution(headId: .subjectProminence, role: .secondary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { 1.0 - $0 }),
                scalarContribution(headId: .balanceConfidence, role: .contextual, input: input, headIndex: headIndex, modeCap: modeCap, transform: { 1.0 - $0 }),
                shotTypeContribution(kind: .lookSpace, role: .contextual, input: input, headIndex: headIndex, modeCap: modeCap)
            ].compactMap { $0 }
        case .backlightHidesSubject:
            return [
                scalarContribution(headId: .lightingQuality, role: .primary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { 1.0 - $0 }),
                scalarContribution(headId: .faceSaliency, role: .secondary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { 1.0 - $0 }),
                scalarContribution(headId: .depthSeparation, role: .contextual, input: input, headIndex: headIndex, modeCap: modeCap, transform: { 1.0 - $0 }),
                shotTypeContribution(kind: .moodyBacklight, role: .contextual, input: input, headIndex: headIndex, modeCap: modeCap)
            ].compactMap { $0 }
        case .sceneHasNoClearFocus:
            return [
                scalarContribution(headId: .subjectProminence, role: .primary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { 1.0 - $0 }),
                scalarContribution(headId: .backgroundClutter, role: .primary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { $0 }),
                scalarContribution(headId: .balanceConfidence, role: .contextual, input: input, headIndex: headIndex, modeCap: modeCap, transform: { 1.0 - $0 })
            ].compactMap { $0 }
        case .frameVisuallyOverloaded:
            return [
                scalarContribution(headId: .backgroundClutter, role: .primary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { $0 }),
                scalarContribution(headId: .subjectProminence, role: .secondary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { 1.0 - $0 }),
                scalarContribution(headId: .balanceConfidence, role: .contextual, input: input, headIndex: headIndex, modeCap: modeCap, transform: { 1.0 - $0 })
            ].compactMap { $0 }
        case .horizonDistracts:
            return [
                scalarContribution(headId: .balanceConfidence, role: .contextual, input: input, headIndex: headIndex, modeCap: modeCap, transform: { 1.0 - $0 })
            ].compactMap { $0 }
        }
    }

    private func strengthContributions(for type: StrengthTypeV1,
                                       input: HybridFusionInput,
                                       headIndex: HeadIndex,
                                       degraded: Bool,
                                       modeCap: Double) -> [Contribution] {
        guard !degraded else { return [] }

        switch type {
        case .goodSubjectIsolation:
            return [
                scalarContribution(headId: .subjectProminence, role: .primary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { $0 }),
                scalarContribution(headId: .backgroundClutter, role: .secondary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { 1.0 - $0 }),
                scalarContribution(headId: .depthSeparation, role: .contextual, input: input, headIndex: headIndex, modeCap: modeCap, transform: { $0 })
            ].compactMap { $0 }
        case .goodLightEmphasis:
            return [
                scalarContribution(headId: .lightingQuality, role: .primary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { $0 }),
                scalarContribution(headId: .faceSaliency, role: .secondary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { $0 }),
                scalarContribution(headId: .depthSeparation, role: .contextual, input: input, headIndex: headIndex, modeCap: modeCap, transform: { $0 })
            ].compactMap { $0 }
        case .clearFocusHierarchy:
            return [
                scalarContribution(headId: .subjectProminence, role: .primary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { $0 }),
                scalarContribution(headId: .backgroundClutter, role: .secondary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { 1.0 - $0 }),
                scalarContribution(headId: .balanceConfidence, role: .contextual, input: input, headIndex: headIndex, modeCap: modeCap, transform: { $0 })
            ].compactMap { $0 }
        case .stableHorizonSupportsScene:
            return [
                scalarContribution(headId: .balanceConfidence, role: .contextual, input: input, headIndex: headIndex, modeCap: modeCap, transform: { $0 })
            ].compactMap { $0 }
        case .balancedCompositionForScene:
            return [
                scalarContribution(headId: .balanceConfidence, role: .primary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { $0 }),
                scalarContribution(headId: .faceSaliency, role: .secondary, input: input, headIndex: headIndex, modeCap: modeCap, transform: { $0 }),
                shotTypeContribution(kind: .sceneBalance(sceneType: input.semantics.sceneType), role: .contextual, input: input, headIndex: headIndex, modeCap: modeCap)
            ].compactMap { $0 }
        }
    }

    private enum ShotTypeContributionKind {
        case edgePressure
        case lookSpace
        case moodyBacklight
        case sceneBalance(sceneType: SceneTypeV1)
    }

    private func scalarContribution(headId: EvidenceHeadId,
                                    role: HeadRole,
                                    input: HybridFusionInput,
                                    headIndex: HeadIndex,
                                    modeCap: Double,
                                    transform: (Double) -> Double) -> Contribution? {
        guard isHeadAllowed(headId, mode: input.snapshot.mode, degraded: input.critique.fallbackUsed) else {
            return nil
        }
        guard let output = headIndex.scalarOutputs[headId],
              output.status == .available,
              let score = output.score,
              let multiplier = confidenceMultiplier(for: output.confidence, mode: input.snapshot.mode) else {
            return nil
        }
        if headId == .faceSaliency {
            let personCentricKinds: Set<SubjectKind> = [.face, .person, .group]
            guard personCentricKinds.contains(input.semantics.primarySubject.kind) else {
                return nil
            }
        }

        let supportScore = clamp01(transform(score))
        let confidence = output.confidence * multiplier
        return cappedContribution(
            headId: headId,
            role: role,
            supportScore: supportScore,
            confidence: confidence,
            modeCap: modeCap
        )
    }

    private func shotTypeContribution(kind: ShotTypeContributionKind,
                                      role: HeadRole,
                                      input: HybridFusionInput,
                                      headIndex: HeadIndex,
                                      modeCap: Double) -> Contribution? {
        guard isHeadAllowed(.shotTypeConfidence, mode: input.snapshot.mode, degraded: input.critique.fallbackUsed) else {
            return nil
        }
        guard let output = headIndex.shotTypeOutput,
              output.status == .available,
              let multiplier = confidenceMultiplier(for: output.confidence, mode: input.snapshot.mode) else {
            return nil
        }

        let supportScore: Double
        switch kind {
        case .edgePressure:
            let softening = max(
                affinity(.twoCharacterFrameAffinity, in: output),
                affinity(.establishingLikeFrameAffinity, in: output)
            )
            supportScore = clamp01(0.5 - (0.20 * softening))
        case .lookSpace:
            let personCentric = average([
                affinity(.dialogueCloseupAffinity, in: output),
                affinity(.singleCharacterMediumAffinity, in: output),
                affinity(.twoCharacterFrameAffinity, in: output)
            ])
            let objectCentric = average([
                affinity(.objectInsertAffinity, in: output),
                affinity(.establishingLikeFrameAffinity, in: output)
            ])
            supportScore = clamp01(0.5 + (0.20 * personCentric) - (0.20 * objectCentric))
        case .moodyBacklight:
            supportScore = clamp01(0.5 - (0.20 * affinity(.moodyBacklitSubjectAffinity, in: output)))
        case let .sceneBalance(sceneType):
            guard let category = affinityCategory(for: sceneType) else { return nil }
            supportScore = clamp01(0.5 + (0.20 * affinity(category, in: output)))
        }

        let confidence = output.confidence * multiplier
        return cappedContribution(
            headId: .shotTypeConfidence,
            role: role,
            supportScore: supportScore,
            confidence: confidence,
            modeCap: modeCap
        )
    }

    private func cappedContribution(headId: EvidenceHeadId,
                                    role: HeadRole,
                                    supportScore: Double,
                                    confidence: Double,
                                    modeCap: Double) -> Contribution {
        guard role == .contextual else {
            return Contribution(headId: headId, role: role, supportScore: supportScore, confidence: confidence)
        }

        let centered = (supportScore - 0.5) * 2.0
        let weighted = centered * role.weight * confidence
        let cappedWeighted = clamp(weighted, min: -(Constants.contextualMaxAbsoluteDelta / modeCap), max: (Constants.contextualMaxAbsoluteDelta / modeCap))
        let cappedSupportScore = clamp01((cappedWeighted / max(0.0001, role.weight * confidence) + 1.0) * 0.5)
        return Contribution(headId: headId, role: role, supportScore: cappedSupportScore, confidence: confidence)
    }

    private func isHeadAllowed(_ headId: EvidenceHeadId,
                               mode: AnalysisMode,
                               degraded: Bool) -> Bool {
        if degraded {
            let degradedAllowed: Set<EvidenceHeadId> = [
                .subjectProminence,
                .backgroundClutter,
                .lightingQuality,
                .faceSaliency
            ]
            return degradedAllowed.contains(headId)
        }

        switch mode {
        case .live:
            let allowed: Set<EvidenceHeadId> = [
                .subjectProminence,
                .backgroundClutter,
                .lightingQuality,
                .faceSaliency
            ]
            return allowed.contains(headId)
        case .pause:
            return headId != .cinematicExpressiveness
        }
    }

    private func confidenceMultiplier(for confidence: Double,
                                      mode: AnalysisMode) -> Double? {
        let clamped = clamp01(confidence)
        switch mode {
        case .live:
            guard clamped >= 0.65 else { return nil }
            return 1.0
        case .pause:
            switch clamped {
            case ..<0.25:
                return nil
            case ..<0.45:
                return 0.35
            case ..<0.65:
                return 0.70
            default:
                return 1.0
            }
        }
    }

    private func modeCap(for mode: AnalysisMode) -> Double {
        switch mode {
        case .live:
            return Constants.liveModeCap
        case .pause:
            return Constants.pauseModeCap
        }
    }

    private func affinity(_ category: EvidenceCategoryId,
                          in output: CategoricalEvidenceHeadOutput) -> Double {
        output.affinities.first(where: { $0.categoryId == category })?.score ?? 0.0
    }

    private func affinityCategory(for sceneType: SceneTypeV1) -> EvidenceCategoryId? {
        switch sceneType {
        case .dialogueCloseup:
            return .dialogueCloseupAffinity
        case .singleCharacterMedium:
            return .singleCharacterMediumAffinity
        case .twoCharacterFrame:
            return .twoCharacterFrameAffinity
        case .objectInsert:
            return .objectInsertAffinity
        case .establishingLikeFrame:
            return .establishingLikeFrameAffinity
        case .moodyBacklitSubject:
            return .moodyBacklitSubjectAffinity
        case .unknown:
            return nil
        }
    }

    private func regeneratedTraceRefs(frameId: String,
                                      issues: [FrameIssue],
                                      strengths: [FrameStrength],
                                      summaryTraceRef: String) -> [String] {
        let issueRefs = issues.enumerated().map { index, _ in
            "trc_\(frameId)_crit_i\(String(format: "%02d", index + 1))"
        }
        let strengthRefs = strengths.enumerated().map { index, _ in
            "trc_\(frameId)_crit_s\(String(format: "%02d", index + 1))"
        }
        return issueRefs + strengthRefs + [summaryTraceRef]
    }

    private func issueChanged(_ result: FusedIssueResult) -> Bool {
        result.issue != result.deterministicIssue
    }

    private func strengthChanged(_ result: FusedStrengthResult) -> Bool {
        result.strength != result.deterministicStrength
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0.0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func clamp01(_ value: Double) -> Double {
        clamp(value, min: 0.0, max: 1.0)
    }

    private func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.min(maxValue, Swift.max(minValue, value))
    }
}
