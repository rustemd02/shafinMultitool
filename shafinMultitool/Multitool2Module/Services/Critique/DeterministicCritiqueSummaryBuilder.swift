import Foundation

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

    /// Resolves the only explanation copy allowed on the Camera Coach
    /// surface. The explanation is intentionally a catalog sentence: the
    /// linked evidence and typed action decide whether it can exist, while
    /// model-provided prose is never interpolated into it.
    func makeExplanation(action: SemanticActionType?,
                         linkedIssueIDs: [String],
                         technicalIssue: TechnicalQualityIssueType? = nil,
                         evidencePayloadAvailable: Bool,
                         locale: Locale) -> String? {
        guard evidencePayloadAvailable,
              linkedIssueIDs.contains(where: isUsableIdentifier) || technicalIssue != nil,
              action != .keepCurrentSetup,
              action != nil || technicalIssue != nil else {
            return nil
        }
        return SETCopyKey.cameraExplanation.localizedString(locale: locale)
    }

    /// Produces an explanation only when the selected planner action points at
    /// a real issue carrying observed structured evidence.
    /// This overload keeps the full domain linkage available to callers that
    /// still hold the RecommendationPlan/CritiqueReport pair.
    func makeExplanation(for action: RecommendationAction,
                         critique: CritiqueReport,
                         locale: Locale) -> String? {
        guard action.actionType != .leaveFrameAsIs,
              let issue = critique.issues.first(where: { issue in
                  action.linkedIssueIds.contains(issue.id) && isUsableIdentifier(issue.id)
              }),
              issue.evidence.contains(where: hasObservedEvidence) else {
            return nil
        }

        guard makeExplanation(
            action: action.actionType.semanticActionType,
            linkedIssueIDs: action.linkedIssueIds,
            evidencePayloadAvailable: true,
            locale: locale
        ) != nil else {
            return nil
        }
        return SETCopyKey.cameraExplanation.localizedString(locale: locale)
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
}
