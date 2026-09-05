import Foundation

/// The smallest typed handoff from a planner action and its critique to a
/// production explanation surface. It is created only after the issue,
/// evidence source and frame identity have been checked together.
struct CameraLinkedEvidenceProjection: Equatable, Sendable {
    let frameID: String
    let actionID: String
    let actionType: ActionTypeV1
    let semanticActionType: SemanticActionType
    let issueID: String
    let issueType: IssueTypeV1
    let evidence: [EvidenceRef]
}

struct DeterministicCritiqueSummaryBuilder {
    func makeSummary(summaryId: String,
                     verdict: FrameVerdict,
                     rankedStrengths: [FrameStrength],
                     rankedIssues: [FrameIssue]) -> CritiqueSummary {
        let shortVerdict: String
        switch verdict {
        case .good:
            shortVerdict = "Кадр читается стабильно, критичных проблем не выявлено."
        case .mixed:
            shortVerdict = "Кадр рабочий, но есть зоны для улучшения композиции и читаемости."
        case .needsFix:
            shortVerdict = "Главный объект считывается с трудом, сначала исправьте приоритетные дефекты."
        }

        let whyGood = rankedStrengths
            .prefix(2)
            .map(\.rationale)
            .joined(separator: " ")
        let whyProblematic = rankedIssues
            .prefix(2)
            .map(\.rationale)
            .joined(separator: " ")

        return CritiqueSummary(
            id: summaryId,
            shortVerdict: shortVerdict,
            whyGood: whyGood.isEmpty ? nil : whyGood,
            whyProblematic: whyProblematic.isEmpty ? nil : whyProblematic
        )
    }

    /// Creates a typed, same-frame evidence handoff for the active action.
    /// Opaque IDs, summary text and neural-only evidence never become a
    /// production explanation source.
    func makeEvidenceProjection(
        frameID: String,
        action: RecommendationAction,
        semanticActionType: SemanticActionType? = nil,
        critique: CritiqueReport
    ) -> CameraLinkedEvidenceProjection? {
        guard isUsableIdentifier(frameID),
              critique.frameId == frameID,
              action.actionType != .leaveFrameAsIs,
              isUsableIdentifier(action.id),
              action.linkedIssueIds.count == 1,
              let issueID = action.linkedIssueIds.first,
              isUsableIdentifier(issueID),
              let issue = critique.issues.first(where: { $0.id == issueID }),
              issue.evidence.contains(where: hasObservedEvidence) else {
            return nil
        }

        let semanticActionType = semanticActionType ?? action.actionType.semanticActionType
        guard semanticActionType != .keepCurrentSetup else {
            return nil
        }

        return CameraLinkedEvidenceProjection(
            frameID: frameID,
            actionID: action.id,
            actionType: action.actionType,
            semanticActionType: semanticActionType,
            issueID: issue.id,
            issueType: issue.type,
            evidence: issue.evidence
        )
    }

    /// Produces deterministic localized copy only from a validated typed
    /// projection. The issue type selects a catalog key; no model prose is
    /// interpolated into the returned string.
    func makeExplanation(for projection: CameraLinkedEvidenceProjection,
                         locale: Locale) -> String? {
        guard isUsableIdentifier(projection.frameID),
              isUsableIdentifier(projection.actionID),
              isUsableIdentifier(projection.issueID),
              projection.actionType != .leaveFrameAsIs,
              projection.semanticActionType != .keepCurrentSetup,
              projection.evidence.contains(where: hasObservedEvidence) else {
            return nil
        }
        return issueCopyKey(projection.issueType).localizedString(locale: locale)
    }

    /// Keeps the domain-level caller convenient while routing through the
    /// same validated projection used by the production presentation path.
    func makeExplanation(for action: RecommendationAction,
                         critique: CritiqueReport,
                         locale: Locale) -> String? {
        guard let projection = makeEvidenceProjection(
            frameID: critique.frameId,
            action: action,
            critique: critique
        ) else {
            return nil
        }
        return makeExplanation(for: projection, locale: locale)
    }

    private func hasObservedEvidence(_ evidence: EvidenceRef) -> Bool {
        guard evidence.source != .neuralEvidence else { return false }
        let key = evidence.key.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = evidence.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !value.isEmpty, value.lowercased() != "nil" else {
            return false
        }
        return !key.lowercased().hasPrefix("summary.")
    }

    private func isUsableIdentifier(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    private func issueCopyKey(_ issue: IssueTypeV1) -> SETCopyKey {
        switch issue {
        case .subjectTooCloseToEdge:
            return .traceIssueSubjectEdge
        case .subjectNotProminentEnough:
            return .traceIssueSubjectProminence
        case .backgroundCompetesWithSubject:
            return .traceIssueBackgroundCompetes
        case .insufficientLookSpace:
            return .traceIssueLookSpace
        case .backlightHidesSubject:
            return .traceIssueBacklight
        case .sceneHasNoClearFocus:
            return .traceIssueFocus
        case .frameVisuallyOverloaded:
            return .traceIssueOverloaded
        case .horizonDistracts:
            return .traceIssueHorizon
        }
    }
}
