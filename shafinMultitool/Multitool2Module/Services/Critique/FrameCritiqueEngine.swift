import Foundation

struct FrameCritiqueInput: Sendable {
    let snapshot: FrameFeatureSnapshot
    let semantics: SceneSemanticsReport
}

struct FrameCritiqueEngine {
    private enum Constants {
        static let issueRawThreshold = 0.40
        static let issueConfidenceThreshold = 0.30
        static let strengthScoreThreshold = 0.55
        static let strengthConfidenceThreshold = 0.35
        static let degradedVerdictConfidenceCap = 0.55
    }

    private let summaryBuilder = DeterministicCritiqueSummaryBuilder()

    private struct IssueCandidate {
        let type: IssueTypeV1
        let rawScore: Double
        let confidence: Double
        let severity: Double
        let rationaleTemplateKey: String
        let rationale: String
        let evidence: [EvidenceRef]
        let affectedRegion: NormalizedRect?
        let suggestedFixTypes: [FixTypeV1]
    }

    private struct StrengthCandidate {
        let type: StrengthTypeV1
        let score: Double
        let confidence: Double
        let rationaleTemplateKey: String
        let rationale: String
        let evidence: [EvidenceRef]
        let supportingRegion: NormalizedRect?
    }

    func analyze(_ input: FrameCritiqueInput) -> CritiqueReport {
        analyze(snapshot: input.snapshot, semantics: input.semantics)
    }

    func analyze(snapshot: FrameFeatureSnapshot, semantics: SceneSemanticsReport) -> CritiqueReport {
        let alignedSemantics = alignedSemantics(snapshot: snapshot, semantics: semantics)
        let normalizedSemantics = normalizedSemantics(alignedSemantics)
        let degraded = isDegraded(snapshot: snapshot)

        var issues = buildIssueCandidates(snapshot: snapshot, semantics: normalizedSemantics)
            .map { applyIssuePenalties(candidate: $0, snapshot: snapshot, semantics: normalizedSemantics) }
            .filter { $0.rawScore >= Constants.issueRawThreshold && $0.confidence >= Constants.issueConfidenceThreshold }

        if degraded {
            let allowedTypes: Set<IssueTypeV1> = [
                .horizonDistracts,
                .backlightHidesSubject,
                .subjectNotProminentEnough
            ]
            issues = issues.filter { allowedTypes.contains($0.type) }
        }

        var strengths = buildStrengthCandidates(snapshot: snapshot, semantics: normalizedSemantics)
            .map { applyStrengthPenalties(candidate: $0, snapshot: snapshot, semantics: normalizedSemantics) }
            .filter { $0.score >= Constants.strengthScoreThreshold && $0.confidence >= Constants.strengthConfidenceThreshold }

        issues = deduplicatedIssues(issues)
        strengths = deduplicatedStrengths(strengths)
        (issues, strengths) = resolveContradictoryFindings(issues: issues, strengths: strengths)

        let sortedIssueCandidates = issues.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return lhs.type.rawValue < rhs.type.rawValue
        }
        let sortedStrengthCandidates = strengths.sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
            return lhs.type.rawValue < rhs.type.rawValue
        }

        let issueEntries = sortedIssueCandidates.enumerated().map { offset, candidate in
            makeIssue(index: offset + 1, frameId: snapshot.frameId, candidate: candidate)
        }
        var strengthEntries = sortedStrengthCandidates.enumerated().map { offset, candidate in
            makeStrength(index: offset + 1, frameId: snapshot.frameId, candidate: candidate)
        }

        var verdict = makeVerdict(issues: issueEntries.map(\.issue), strengths: strengthEntries.map(\.strength))
        var verdictConfidence = makeVerdictConfidence(snapshot: snapshot,
                                                      semantics: normalizedSemantics,
                                                      issues: issueEntries.map(\.issue),
                                                      strengths: strengthEntries.map(\.strength))

        if degraded {
            strengthEntries = []
            if verdict == .good {
                verdict = .mixed
            }
            verdictConfidence = min(verdictConfidence, Constants.degradedVerdictConfidenceCap)
        }

        let summaryId = "summary_\(snapshot.frameId)_main"
        let summary = summaryBuilder.makeSummary(
            summaryId: summaryId,
            verdict: verdict,
            rankedStrengths: strengthEntries.map(\.strength),
            rankedIssues: issueEntries.map(\.issue)
        )

        let traceRefs = issueEntries.map(\.seedId)
            + strengthEntries.map(\.seedId)
            + ["trc_\(snapshot.frameId)_crit_summary_main"]

        return CritiqueReport(
            frameId: snapshot.frameId,
            mode: snapshot.mode,
            verdict: verdict,
            verdictConfidence: verdictConfidence,
            strengths: strengthEntries.map(\.strength),
            issues: issueEntries.map(\.issue),
            summary: summary,
            traceRefs: traceRefs,
            fallbackUsed: degraded
        )
    }

    func rawIssueScoreForTesting(type: IssueTypeV1,
                                 snapshot: FrameFeatureSnapshot,
                                 semantics: SceneSemanticsReport) -> Double? {
        let alignedSemantics = alignedSemantics(snapshot: snapshot, semantics: semantics)
        let normalizedSemantics = normalizedSemantics(alignedSemantics)
        return buildIssueCandidates(snapshot: snapshot, semantics: normalizedSemantics)
            .first(where: { $0.type == type })?
            .rawScore
    }

    // MARK: - Issue Rules

    private func buildIssueCandidates(snapshot: FrameFeatureSnapshot,
                                      semantics: SceneSemanticsReport) -> [IssueCandidate] {
        [
            issueSubjectTooCloseToEdge(snapshot: snapshot, semantics: semantics),
            issueSubjectNotProminentEnough(snapshot: snapshot, semantics: semantics),
            issueBackgroundCompetesWithSubject(snapshot: snapshot, semantics: semantics),
            issueInsufficientLookSpace(snapshot: snapshot, semantics: semantics),
            issueBacklightHidesSubject(snapshot: snapshot, semantics: semantics),
            issueSceneHasNoClearFocus(snapshot: snapshot, semantics: semantics),
            issueFrameVisuallyOverloaded(snapshot: snapshot, semantics: semantics),
            issueHorizonDistracts(snapshot: snapshot, semantics: semantics)
        ]
    }

    private func issueSubjectTooCloseToEdge(snapshot: FrameFeatureSnapshot,
                                            semantics: SceneSemanticsReport) -> IssueCandidate {
        let raw = clamp01((0.70 * semantics.readability.edgePressureScore)
                          + (0.30 * abs(snapshot.composition.horizontalOffset)))
        let confidence = clamp01((0.60 * semantics.primarySubject.confidence)
                                 + (0.40 * (snapshot.sources.vision.confidence ?? 0.0)))
        let evidence = [
            evidence(.semantics, "semantics.readability.edgePressureScore", semantics.readability.edgePressureScore),
            evidence(.snapshot, "snapshot.composition.horizontalOffset", snapshot.composition.horizontalOffset)
        ]
        let region = validRegion(semantics.primarySubject.region) ?? validRegion(snapshot.subjectSignals.primaryCandidateRegion)
        return IssueCandidate(
            type: .subjectTooCloseToEdge,
            rawScore: raw,
            confidence: confidence,
            severity: issueSeverity(rawScore: raw, type: .subjectTooCloseToEdge, snapshot: snapshot),
            rationaleTemplateKey: "issue.edge_pressure",
            rationale: "Главный объект прижат к краю кадра, из-за чего теряется визуальный баланс.",
            evidence: evidence,
            affectedRegion: region,
            suggestedFixTypes: [.reframing]
        )
    }

    private func issueSubjectNotProminentEnough(snapshot: FrameFeatureSnapshot,
                                                semantics: SceneSemanticsReport) -> IssueCandidate {
        let areaPenalty = clamp01((0.10 - snapshot.composition.subjectAreaRatio) / 0.10)
        let sepPenalty = clamp01(1.0 - semantics.readability.separationScore)
        let raw = clamp01((0.45 * areaPenalty) + (0.35 * sepPenalty) + (0.20 * (1.0 - semantics.primarySubject.confidence)))
        let confidence = clamp01((0.50 * semantics.primarySubject.confidence)
                                 + (0.30 * (snapshot.sources.vision.confidence ?? 0.0))
                                 + (0.20 * (snapshot.sources.detr.confidence ?? 0.0)))
        let evidence = [
            evidence(.snapshot, "snapshot.composition.subjectAreaRatio", snapshot.composition.subjectAreaRatio),
            evidence(.semantics, "semantics.readability.separationScore", semantics.readability.separationScore),
            evidence(.semantics, "semantics.primarySubject.confidence", semantics.primarySubject.confidence)
        ]
        return IssueCandidate(
            type: .subjectNotProminentEnough,
            rawScore: raw,
            confidence: confidence,
            severity: issueSeverity(rawScore: raw, type: .subjectNotProminentEnough, snapshot: snapshot),
            rationaleTemplateKey: "issue.subject_prominence",
            rationale: "Главный объект недостаточно выражен относительно фона и масштаба кадра.",
            evidence: evidence,
            affectedRegion: validRegion(semantics.primarySubject.region),
            suggestedFixTypes: [.reframing, .angleAdjustment]
        )
    }

    private func issueBackgroundCompetesWithSubject(snapshot: FrameFeatureSnapshot,
                                                    semantics: SceneSemanticsReport) -> IssueCandidate {
        let focusPenalty = semantics.dominance.hasClearFocus ? 0.0 : 0.20
        let raw = clamp01((0.55 * semantics.dominance.focusCompetitionScore)
                          + (0.35 * semantics.dominance.backgroundClutterScore)
                          + (0.10 * focusPenalty))
        let confidence = clamp01((0.55 * semantics.sceneTypeConfidence)
                                 + (0.45 * (snapshot.sources.detr.confidence ?? 0.0)))
        let evidence = [
            evidence(.semantics, "semantics.dominance.focusCompetitionScore", semantics.dominance.focusCompetitionScore),
            evidence(.semantics, "semantics.dominance.backgroundClutterScore", semantics.dominance.backgroundClutterScore)
        ]
        return IssueCandidate(
            type: .backgroundCompetesWithSubject,
            rawScore: raw,
            confidence: confidence,
            severity: issueSeverity(rawScore: raw, type: .backgroundCompetesWithSubject, snapshot: snapshot),
            rationaleTemplateKey: "issue.background_competition",
            rationale: "Фон конкурирует с главным объектом и снижает читаемость акцента.",
            evidence: evidence,
            affectedRegion: nil,
            suggestedFixTypes: [.angleAdjustment, .reframing]
        )
    }

    private func issueInsufficientLookSpace(snapshot: FrameFeatureSnapshot,
                                            semantics: SceneSemanticsReport) -> IssueCandidate {
        let subjectKind = semantics.primarySubject.kind
        let isApplicableSubject = subjectKind == .face || subjectKind == .person || subjectKind == .group
        let raw: Double
        let confidence: Double

        if !isApplicableSubject {
            raw = 0
            confidence = 0
        } else if semantics.readability.lookSpaceAdequate == nil {
            raw = 0
            confidence = 0
        } else if semantics.readability.lookSpaceAdequate == true {
            raw = 0
            confidence = clamp01((0.60 * semantics.primarySubject.confidence) + (0.40 * semantics.sceneTypeConfidence))
        } else {
            raw = clamp01(0.60 + (0.40 * abs(snapshot.composition.horizontalOffset)))
            confidence = clamp01((0.60 * semantics.primarySubject.confidence) + (0.40 * semantics.sceneTypeConfidence))
        }

        let evidence = [
            evidence(.semantics, "semantics.readability.lookSpaceAdequate", semantics.readability.lookSpaceAdequate),
            evidence(.snapshot, "snapshot.composition.horizontalOffset", snapshot.composition.horizontalOffset)
        ]
        return IssueCandidate(
            type: .insufficientLookSpace,
            rawScore: raw,
            confidence: confidence,
            severity: issueSeverity(rawScore: raw, type: .insufficientLookSpace, snapshot: snapshot),
            rationaleTemplateKey: "issue.look_space",
            rationale: "По направлению взгляда или движения не хватает свободного пространства.",
            evidence: evidence,
            affectedRegion: validRegion(semantics.primarySubject.region),
            suggestedFixTypes: [.reframing]
        )
    }

    private func issueBacklightHidesSubject(snapshot: FrameFeatureSnapshot,
                                            semantics: SceneSemanticsReport) -> IssueCandidate {
        let backlightScore = clamp01((snapshot.lighting.backlightIndex - 0.45) / 0.55)
        let exposurePenalty = snapshot.lighting.exposureBiasHint < 0 ? clamp01(abs(snapshot.lighting.exposureBiasHint) / 0.40) : 0.0
        let sepPenalty = clamp01(1.0 - semantics.readability.separationScore)
        let personBoost = (semantics.primarySubject.kind == .face || semantics.primarySubject.kind == .person) ? 0.08 : 0.0
        let raw = clamp01((0.45 * backlightScore) + (0.30 * exposurePenalty) + (0.25 * sepPenalty) + personBoost)
        let confidence = clamp01((0.65 * (snapshot.sources.lighting.confidence ?? 0.0))
                                 + (0.35 * semantics.primarySubject.confidence))
        let evidence = [
            evidence(.snapshot, "snapshot.lighting.backlightIndex", snapshot.lighting.backlightIndex),
            evidence(.snapshot, "snapshot.lighting.exposureBiasHint", snapshot.lighting.exposureBiasHint),
            evidence(.semantics, "semantics.readability.separationScore", semantics.readability.separationScore)
        ]
        return IssueCandidate(
            type: .backlightHidesSubject,
            rawScore: raw,
            confidence: confidence,
            severity: issueSeverity(rawScore: raw, type: .backlightHidesSubject, snapshot: snapshot),
            rationaleTemplateKey: "issue.backlight",
            rationale: "Контровой свет снижает читаемость главного объекта.",
            evidence: evidence,
            affectedRegion: validRegion(semantics.primarySubject.region),
            suggestedFixTypes: [.lightingAdjustment, .angleAdjustment]
        )
    }

    private func issueSceneHasNoClearFocus(snapshot: FrameFeatureSnapshot,
                                           semantics: SceneSemanticsReport) -> IssueCandidate {
        let ambiguityBoost = hasAmbiguity(.multipleSubjectsSimilarConfidence, in: semantics.ambiguities) ? 0.15 : 0.0
        let raw: Double
        if semantics.dominance.hasClearFocus {
            raw = 0
        } else {
            raw = clamp01((0.60 * semantics.dominance.focusCompetitionScore)
                          + (0.30 * (1.0 - semantics.primarySubject.confidence))
                          + ambiguityBoost)
        }
        let confidence = clamp01((0.55 * semantics.sceneTypeConfidence)
                                 + (0.45 * semantics.primarySubject.confidence))
        let evidence = [
            evidence(.semantics, "semantics.dominance.hasClearFocus", semantics.dominance.hasClearFocus),
            evidence(.semantics, "semantics.dominance.focusCompetitionScore", semantics.dominance.focusCompetitionScore),
            evidence(.semantics, "semantics.primarySubject.confidence", semantics.primarySubject.confidence)
        ]
        return IssueCandidate(
            type: .sceneHasNoClearFocus,
            rawScore: raw,
            confidence: confidence,
            severity: issueSeverity(rawScore: raw, type: .sceneHasNoClearFocus, snapshot: snapshot),
            rationaleTemplateKey: "issue.no_clear_focus",
            rationale: "В кадре нет устойчивого центра внимания.",
            evidence: evidence,
            affectedRegion: nil,
            suggestedFixTypes: [.reframing, .angleAdjustment]
        )
    }

    private func issueFrameVisuallyOverloaded(snapshot: FrameFeatureSnapshot,
                                              semantics: SceneSemanticsReport) -> IssueCandidate {
        let densityScore = clamp01(Double(snapshot.objects.totalCount) / 8.0)
        let clutterCore = clamp01((0.65 * semantics.dominance.backgroundClutterScore) + (0.35 * densityScore))
        let scenePenalty = semantics.sceneType == .establishingLikeFrame ? 0.15 : 0.0
        let raw = clamp01(clutterCore - scenePenalty)
        let confidence = clamp01((0.50 * semantics.sceneTypeConfidence)
                                 + (0.50 * (snapshot.sources.detr.confidence ?? 0.0)))
        let evidence = [
            evidence(.semantics, "semantics.dominance.backgroundClutterScore", semantics.dominance.backgroundClutterScore),
            evidence(.snapshot, "snapshot.objects.totalCount", snapshot.objects.totalCount),
            evidence(.semantics, "semantics.sceneType", semantics.sceneType.rawValue)
        ]
        return IssueCandidate(
            type: .frameVisuallyOverloaded,
            rawScore: raw,
            confidence: confidence,
            severity: issueSeverity(rawScore: raw, type: .frameVisuallyOverloaded, snapshot: snapshot),
            rationaleTemplateKey: "issue.visual_overload",
            rationale: "Кадр визуально перегружен и отвлекает от основного объекта.",
            evidence: evidence,
            affectedRegion: nil,
            suggestedFixTypes: [.angleAdjustment, .reframing]
        )
    }

    private func issueHorizonDistracts(snapshot: FrameFeatureSnapshot,
                                       semantics: SceneSemanticsReport) -> IssueCandidate {
        let tilt = abs(snapshot.horizon.angleDegrees)
        let sceneSensitivity: Double =
            (semantics.sceneType == .dialogueCloseup || semantics.sceneType == .singleCharacterMedium) ? 1.0 : 0.75
        var raw = clamp01((tilt / 8.0) * sceneSensitivity)
        if snapshot.horizon.confidence < 0.45 {
            raw = 0
        }
        let confidence = clamp01(snapshot.horizon.confidence)
        let evidence = [
            evidence(.snapshot, "snapshot.horizon.angleDegrees", snapshot.horizon.angleDegrees),
            evidence(.snapshot, "snapshot.horizon.confidence", snapshot.horizon.confidence),
            evidence(.semantics, "semantics.sceneType", semantics.sceneType.rawValue)
        ]
        return IssueCandidate(
            type: .horizonDistracts,
            rawScore: raw,
            confidence: confidence,
            severity: issueSeverity(rawScore: raw, type: .horizonDistracts, snapshot: snapshot),
            rationaleTemplateKey: "issue.horizon_tilt",
            rationale: "Наклон горизонта отвлекает от восприятия сцены.",
            evidence: evidence,
            affectedRegion: nil,
            suggestedFixTypes: [.horizonCorrection, .angleAdjustment]
        )
    }

    // MARK: - Strength Rules

    private func buildStrengthCandidates(snapshot: FrameFeatureSnapshot,
                                         semantics: SceneSemanticsReport) -> [StrengthCandidate] {
        [
            strengthGoodSubjectIsolation(snapshot: snapshot, semantics: semantics),
            strengthGoodLightEmphasis(snapshot: snapshot, semantics: semantics),
            strengthClearFocusHierarchy(snapshot: snapshot, semantics: semantics),
            strengthStableHorizon(snapshot: snapshot, semantics: semantics),
            strengthBalancedComposition(snapshot: snapshot, semantics: semantics)
        ]
    }

    private func strengthGoodSubjectIsolation(snapshot: FrameFeatureSnapshot,
                                              semantics: SceneSemanticsReport) -> StrengthCandidate {
        let score = clamp01((0.60 * semantics.readability.separationScore) + (0.40 * (1.0 - semantics.dominance.backgroundClutterScore)))
        let confidence = clamp01((0.60 * semantics.primarySubject.confidence) + (0.40 * semantics.sceneTypeConfidence))
        let evidence = [
            evidence(.semantics, "semantics.readability.separationScore", semantics.readability.separationScore),
            evidence(.semantics, "semantics.dominance.backgroundClutterScore", semantics.dominance.backgroundClutterScore)
        ]
        return StrengthCandidate(
            type: .goodSubjectIsolation,
            score: score,
            confidence: confidence,
            rationaleTemplateKey: "strength.subject_isolation",
            rationale: "Главный объект хорошо отделен от фона.",
            evidence: evidence,
            supportingRegion: validRegion(semantics.primarySubject.region)
        )
    }

    private func strengthGoodLightEmphasis(snapshot: FrameFeatureSnapshot,
                                           semantics: SceneSemanticsReport) -> StrengthCandidate {
        let score = clamp01((0.55 * (1.0 - snapshot.lighting.backlightIndex)) + (0.45 * semantics.readability.separationScore))
        let confidence = clamp01((0.70 * (snapshot.sources.lighting.confidence ?? 0.0)) + (0.30 * semantics.sceneTypeConfidence))
        let evidence = [
            evidence(.snapshot, "snapshot.lighting.backlightIndex", snapshot.lighting.backlightIndex),
            evidence(.semantics, "semantics.readability.separationScore", semantics.readability.separationScore)
        ]
        return StrengthCandidate(
            type: .goodLightEmphasis,
            score: score,
            confidence: confidence,
            rationaleTemplateKey: "strength.light_emphasis",
            rationale: "Свет поддерживает акцент на главном объекте.",
            evidence: evidence,
            supportingRegion: validRegion(semantics.primarySubject.region)
        )
    }

    private func strengthClearFocusHierarchy(snapshot: FrameFeatureSnapshot,
                                             semantics: SceneSemanticsReport) -> StrengthCandidate {
        let score = clamp01((0.65 * (semantics.dominance.hasClearFocus ? 1.0 : 0.0))
                            + (0.35 * (1.0 - semantics.dominance.focusCompetitionScore)))
        let confidence = clamp01((0.60 * semantics.primarySubject.confidence) + (0.40 * semantics.sceneTypeConfidence))
        let evidence = [
            evidence(.semantics, "semantics.dominance.hasClearFocus", semantics.dominance.hasClearFocus),
            evidence(.semantics, "semantics.dominance.focusCompetitionScore", semantics.dominance.focusCompetitionScore)
        ]
        return StrengthCandidate(
            type: .clearFocusHierarchy,
            score: score,
            confidence: confidence,
            rationaleTemplateKey: "strength.clear_focus",
            rationale: "Иерархия внимания в кадре читается ясно.",
            evidence: evidence,
            supportingRegion: validRegion(semantics.primarySubject.region)
        )
    }

    private func strengthStableHorizon(snapshot: FrameFeatureSnapshot,
                                       semantics: SceneSemanticsReport) -> StrengthCandidate {
        let score = clamp01(1.0 - (abs(snapshot.horizon.angleDegrees) / 6.0))
        let confidence = clamp01(snapshot.horizon.confidence)
        let evidence = [
            evidence(.snapshot, "snapshot.horizon.angleDegrees", snapshot.horizon.angleDegrees),
            evidence(.snapshot, "snapshot.horizon.confidence", snapshot.horizon.confidence)
        ]
        return StrengthCandidate(
            type: .stableHorizonSupportsScene,
            score: score,
            confidence: confidence,
            rationaleTemplateKey: "strength.stable_horizon",
            rationale: "Горизонт стабилен и не отвлекает от сцены.",
            evidence: evidence,
            supportingRegion: nil
        )
    }

    private func strengthBalancedComposition(snapshot: FrameFeatureSnapshot,
                                             semantics: SceneSemanticsReport) -> StrengthCandidate {
        let centerPenalty = abs(snapshot.composition.horizontalOffset)
        let sceneTolerance = semantics.sceneType == .establishingLikeFrame ? 0.35 : 0.20
        let score = clamp01(1.0 - max(0.0, centerPenalty - sceneTolerance) / (1.0 - sceneTolerance))
        let confidence = clamp01((0.50 * semantics.primarySubject.confidence) + (0.50 * semantics.sceneTypeConfidence))
        let evidence = [
            evidence(.snapshot, "snapshot.composition.horizontalOffset", snapshot.composition.horizontalOffset),
            evidence(.semantics, "semantics.sceneType", semantics.sceneType.rawValue),
            evidence(.semantics, "semantics.sceneTypeConfidence", semantics.sceneTypeConfidence)
        ]
        return StrengthCandidate(
            type: .balancedCompositionForScene,
            score: score,
            confidence: confidence,
            rationaleTemplateKey: "strength.balanced_composition",
            rationale: "Композиция сбалансирована для текущего типа сцены.",
            evidence: evidence,
            supportingRegion: validRegion(semantics.primarySubject.region)
        )
    }

    // MARK: - Penalties & Helpers

    private func applyIssuePenalties(candidate: IssueCandidate,
                                     snapshot: FrameFeatureSnapshot,
                                     semantics: SceneSemanticsReport) -> IssueCandidate {
        var confidence = candidate.confidence
        if hasAmbiguity(.sceneTypeTie, in: semantics.ambiguities), isSceneDependentIssue(candidate.type) {
            confidence *= 0.90
        }
        if snapshot.technicalFlags.contains(.lowSceneConfidence), isSceneDependentIssue(candidate.type) {
            confidence *= 0.85
        }
        if semantics.primarySubject.kind == .unknown && candidate.type == .subjectTooCloseToEdge {
            confidence *= 0.80
        }
        confidence = clamp01(confidence)
        return IssueCandidate(
            type: candidate.type,
            rawScore: candidate.rawScore,
            confidence: confidence,
            severity: candidate.severity,
            rationaleTemplateKey: candidate.rationaleTemplateKey,
            rationale: candidate.rationale,
            evidence: candidate.evidence,
            affectedRegion: candidate.affectedRegion,
            suggestedFixTypes: candidate.suggestedFixTypes
        )
    }

    private func applyStrengthPenalties(candidate: StrengthCandidate,
                                        snapshot: FrameFeatureSnapshot,
                                        semantics: SceneSemanticsReport) -> StrengthCandidate {
        var confidence = candidate.confidence
        if hasAmbiguity(.sceneTypeTie, in: semantics.ambiguities), isSceneDependentStrength(candidate.type) {
            confidence *= 0.90
        }
        if snapshot.technicalFlags.contains(.lowSceneConfidence), isSceneDependentStrength(candidate.type) {
            confidence *= 0.85
        }
        confidence = clamp01(confidence)
        return StrengthCandidate(
            type: candidate.type,
            score: candidate.score,
            confidence: confidence,
            rationaleTemplateKey: candidate.rationaleTemplateKey,
            rationale: candidate.rationale,
            evidence: candidate.evidence,
            supportingRegion: candidate.supportingRegion
        )
    }

    private func isSceneDependentIssue(_ type: IssueTypeV1) -> Bool {
        switch type {
        case .subjectNotProminentEnough,
             .backgroundCompetesWithSubject,
             .insufficientLookSpace,
             .sceneHasNoClearFocus,
             .frameVisuallyOverloaded:
            return true
        default:
            return false
        }
    }

    private func isSceneDependentStrength(_ type: StrengthTypeV1) -> Bool {
        switch type {
        case .goodSubjectIsolation,
             .goodLightEmphasis,
             .clearFocusHierarchy,
             .balancedCompositionForScene:
            return true
        default:
            return false
        }
    }

    private func deduplicatedIssues(_ candidates: [IssueCandidate]) -> [IssueCandidate] {
        var byType: [IssueTypeV1: IssueCandidate] = [:]
        for candidate in candidates {
            if let current = byType[candidate.type] {
                if candidate.severity > current.severity {
                    byType[candidate.type] = candidate
                }
            } else {
                byType[candidate.type] = candidate
            }
        }
        return Array(byType.values)
    }

    private func deduplicatedStrengths(_ candidates: [StrengthCandidate]) -> [StrengthCandidate] {
        var byType: [StrengthTypeV1: StrengthCandidate] = [:]
        for candidate in candidates {
            if let current = byType[candidate.type] {
                if candidate.confidence > current.confidence {
                    byType[candidate.type] = candidate
                }
            } else {
                byType[candidate.type] = candidate
            }
        }
        return Array(byType.values)
    }

    private func resolveContradictoryFindings(issues: [IssueCandidate],
                                              strengths: [StrengthCandidate]) -> ([IssueCandidate], [StrengthCandidate]) {
        var filteredStrengths = strengths
        if issues.contains(where: { $0.type == .backlightHidesSubject }) {
            filteredStrengths.removeAll { $0.type == .goodLightEmphasis }
        }
        return (issues, filteredStrengths)
    }

    private func issueSeverity(rawScore: Double, type: IssueTypeV1, snapshot: FrameFeatureSnapshot) -> Double {
        let modeMultiplier = snapshot.mode == .pause ? 1.0 : 0.92
        let criticalBoost: Double = (type == .backlightHidesSubject || type == .sceneHasNoClearFocus) ? 0.06 : 0.0
        var severity = clamp01((rawScore * modeMultiplier) + criticalBoost)
        if snapshot.mode == .live, snapshot.technicalFlags.contains(.highMotion), isCompositionRelatedIssue(type) {
            severity = clamp01(severity * 0.92)
        }
        return severity
    }

    private func isCompositionRelatedIssue(_ type: IssueTypeV1) -> Bool {
        type == .subjectTooCloseToEdge || type == .insufficientLookSpace
    }

    private func isDegraded(snapshot: FrameFeatureSnapshot) -> Bool {
        snapshot.technicalFlags.contains(.lowSceneConfidence)
    }

    private func alignedSemantics(snapshot: FrameFeatureSnapshot,
                                  semantics: SceneSemanticsReport) -> SceneSemanticsReport {
        guard semantics.frameId == snapshot.frameId, semantics.mode == snapshot.mode else {
            return SceneSemanticsReport(
                frameId: snapshot.frameId,
                mode: snapshot.mode,
                sceneType: semantics.sceneType,
                sceneTypeConfidence: semantics.sceneTypeConfidence,
                primarySubject: semantics.primarySubject,
                dominance: semantics.dominance,
                readability: semantics.readability,
                ambiguities: semantics.ambiguities,
                assumptions: semantics.assumptions
            )
        }
        return semantics
    }

    private func normalizedSemantics(_ semantics: SceneSemanticsReport) -> SceneSemanticsReport {
        guard semantics.dominance.hasClearFocus && semantics.dominance.backgroundClutterScore > 0.55 else {
            return semantics
        }
        return SceneSemanticsReport(
            frameId: semantics.frameId,
            mode: semantics.mode,
            sceneType: semantics.sceneType,
            sceneTypeConfidence: semantics.sceneTypeConfidence,
            primarySubject: semantics.primarySubject,
            dominance: .init(
                hasClearFocus: false,
                focusCompetitionScore: semantics.dominance.focusCompetitionScore,
                backgroundClutterScore: semantics.dominance.backgroundClutterScore
            ),
            readability: semantics.readability,
            ambiguities: semantics.ambiguities,
            assumptions: semantics.assumptions
        )
    }

    private func makeVerdict(issues: [FrameIssue], strengths: [FrameStrength]) -> FrameVerdict {
        let maxIssueSeverity = issues.map(\.severity).max() ?? 0
        let highIssueCount = issues.filter { $0.severity >= CritiqueReport.criticalIssueThreshold }.count
        let strongStrengthCount = strengths.filter { $0.confidence >= 0.70 }.count

        if maxIssueSeverity >= 0.72 || highIssueCount >= 2 {
            return .needsFix
        }
        if issues.isEmpty || (maxIssueSeverity < 0.45 && strongStrengthCount >= 2) {
            return .good
        }
        return .mixed
    }

    private func makeVerdictConfidence(snapshot: FrameFeatureSnapshot,
                                       semantics: SceneSemanticsReport,
                                       issues: [FrameIssue],
                                       strengths: [FrameStrength]) -> Double {
        let signalSupport = clamp01(
            (0.40 * (snapshot.sources.vision.confidence ?? 0.0))
            + (0.30 * (snapshot.sources.lighting.confidence ?? 0.0))
            + (0.30 * semantics.sceneTypeConfidence)
        )
        let consistency = clamp01(1.0 - (Double(abs(strengths.count - issues.count)) / 6.0))
        return clamp01((0.65 * signalSupport) + (0.35 * consistency))
    }

    private func makeIssue(index: Int,
                           frameId: String,
                           candidate: IssueCandidate) -> (issue: FrameIssue, seedId: String) {
        let nn = String(format: "%02d", index)
        let issueId = "iss_\(frameId)_\(nn)"
        let seedId = "trc_\(frameId)_crit_i\(nn)"
        let issue = FrameIssue(
            id: issueId,
            type: candidate.type,
            severity: candidate.severity,
            confidence: candidate.confidence,
            rationale: candidate.rationale,
            evidence: candidate.evidence,
            affectedRegion: validRegion(candidate.affectedRegion),
            suggestedFixTypes: candidate.suggestedFixTypes
        )
        return (issue: issue, seedId: seedId)
    }

    private func makeStrength(index: Int,
                              frameId: String,
                              candidate: StrengthCandidate) -> (strength: FrameStrength, seedId: String) {
        let nn = String(format: "%02d", index)
        let strengthId = "str_\(frameId)_\(nn)"
        let seedId = "trc_\(frameId)_crit_s\(nn)"
        let strength = FrameStrength(
            id: strengthId,
            type: candidate.type,
            confidence: candidate.confidence,
            rationale: candidate.rationale,
            evidence: candidate.evidence,
            supportingRegion: validRegion(candidate.supportingRegion)
        )
        return (strength: strength, seedId: seedId)
    }

    private func evidence(_ source: EvidenceSource,
                          _ key: String,
                          _ value: Any?) -> EvidenceRef {
        let rendered: String
        if let boolValue = value as? Bool {
            rendered = boolValue ? "true" : "false"
        } else if let number = value as? Double {
            rendered = format(number)
        } else if let number = value as? Int {
            rendered = String(number)
        } else if let value {
            rendered = String(describing: value)
        } else {
            rendered = "nil"
        }
        return EvidenceRef(source: source, key: key, value: rendered)
    }

    private func validRegion(_ region: NormalizedRect?) -> NormalizedRect? {
        guard let region, !region.isDegenerate else { return nil }
        return region
    }

    private func hasAmbiguity(_ type: AmbiguityType, in ambiguities: [SemanticsAmbiguity]) -> Bool {
        ambiguities.contains { $0.type == type }
    }

    private func format(_ value: Double) -> String {
        guard value.isFinite else { return "0.000" }
        return String(format: "%.3f", value)
    }

    private func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}
