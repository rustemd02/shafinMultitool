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
}
