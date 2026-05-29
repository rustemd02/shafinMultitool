import SwiftUI

struct DecisionTraceView: View {
    @Environment(\.dismiss) private var dismiss
    let trace: DecisionTracePresentation

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if !trace.reasonLines.isEmpty {
                        DecisionTraceSection(title: "Почему") {
                            ForEach(trace.reasonLines) { row in
                                DecisionTraceTextRow(title: row.title, text: row.text)
                            }
                        }
                    }

                    if !trace.evidenceRows.isEmpty {
                        DecisionTraceSection(title: "Доказательства") {
                            ForEach(trace.evidenceRows) { row in
                                DecisionTraceEvidenceRow(row: row)
                            }
                        }
                    }

                    if !trace.actionRows.isEmpty {
                        DecisionTraceSection(title: "Что выбрано") {
                            ForEach(trace.actionRows) { row in
                                DecisionTraceActionRow(row: row)
                            }
                        }
                    }

                    if !trace.signalRows.isEmpty {
                        DecisionTraceSection(title: "Сигналы пайплайна") {
                            ForEach(trace.signalRows) { row in
                                DecisionTraceSignalRow(row: row)
                            }
                        }
                    }

                    if !trace.traceIds.isEmpty {
                        DecisionTraceSection(title: "Trace IDs") {
                            DecisionTraceTokenCloud(tokens: trace.traceIds)
                        }
                    }

                    if !trace.limitationRows.isEmpty {
                        DecisionTraceSection(title: "Ограничения") {
                            ForEach(trace.limitationRows) { row in
                                Text(row.text)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Почему?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("decision_trace_sheet")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(trace.modeLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    Text(trace.verdictLabel)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(trace.headline)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                DecisionTraceConfidenceBadge(confidence: trace.confidence)
            }

            Text("Панель показывает, какие признаки, issue/strength строки и semantic action привели к текущей подсказке.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DecisionTraceSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct DecisionTraceTextRow: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DecisionTraceEvidenceRow: View {
    let row: DecisionTracePresentation.EvidenceRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.kindLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(row.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                DecisionTraceConfidenceBadge(confidence: row.confidence)
            }

            Text(row.text)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            metadataLine
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var metadataLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("id: \(row.sourceId)")
            if let severity = row.severity {
                Text("severity: \(severity.shortText)")
            }
            if let regionDescription = row.regionDescription {
                Text("region: \(regionDescription)")
            }
            if let traceId = row.traceId {
                Text("trace: \(traceId)")
            }
        }
        .font(.caption2.monospaced())
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DecisionTraceActionRow: View {
    let row: DecisionTracePresentation.ActionRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(row.semanticActionId)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                DecisionTraceConfidenceBadge(confidence: row.confidence)
            }

            Text(row.detail)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                if let coarseActionId = row.coarseActionId {
                    Text("coarse: \(coarseActionId)")
                }
                if !row.linkedEvidenceIds.isEmpty {
                    Text("linked evidence: \(row.linkedEvidenceIds.joined(separator: ", "))")
                }
                if let targetDescription = row.targetDescription {
                    Text("target: \(targetDescription)")
                }
                if let overlayHintId = row.overlayHintId {
                    Text("overlay: \(overlayHintId)")
                }
                if let traceId = row.traceId {
                    Text("trace: \(traceId)")
                }
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct DecisionTraceSignalRow: View {
    let row: DecisionTracePresentation.SignalRow

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let detail = row.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.value)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
        }
    }
}

private struct DecisionTraceTokenCloud: View {
    let tokens: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(tokens, id: \.self) { token in
                Text(token)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DecisionTraceConfidenceBadge: View {
    let confidence: ConfidencePresentation

    var body: some View {
        Text(confidence.shortText)
            .font(.caption2.weight(.bold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(toneColor.opacity(0.86), in: Capsule())
            .accessibilityLabel(confidence.accessibilityText)
    }

    private var toneColor: Color {
        switch confidence.tone {
        case .high:
            return .green
        case .medium:
            return .orange
        case .low:
            return .yellow
        }
    }

    private var foregroundColor: Color {
        switch confidence.tone {
        case .low:
            return .black.opacity(0.82)
        case .high, .medium:
            return .white.opacity(0.96)
        }
    }
}

#Preview {
    DecisionTraceView(
        trace: DecisionTracePresentation(
            id: "preview",
            modeLabel: "Пауза",
            verdictLabel: "Можно улучшить",
            headline: "Фон спорит с главным объектом.",
            confidence: .make(0.74),
            reasonLines: [
                .init(id: "why", title: "Что мешает", text: "Фон забирает внимание у субъекта.")
            ],
            evidenceRows: [],
            actionRows: [],
            signalRows: [
                .init(id: "detr", title: "DETR objects", value: "2", detail: "Объекты, найденные детектором.")
            ],
            limitationRows: [
                .init(id: "scope", text: "Панель объясняет текущую presentation-цепочку.")
            ],
            traceIds: ["trace_preview"]
        )
    )
}
