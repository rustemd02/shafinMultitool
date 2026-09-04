import SwiftUI

/// `sheet.decision-trace` as a flat editorial цех surface. The hero is the
/// traced decision itself: evidence rows, the chosen action and the trace
/// IDs. Hierarchy is carried by exactly one annotation motif — a hand
/// underline on the evidence the chosen action is linked to — and one
/// accent — a single warm-white hairline section rule. Confidence reads as
/// neutral mono copy, never a colored badge.
struct DecisionTraceView: View {
    @Environment(\.dismiss) private var dismiss
    let trace: DecisionTracePresentation

    /// The first evidence row linked by the highest-priority (chosen) action.
    /// The sheet deliberately renders no more than one underline annotation.
    private var chosenActionEvidenceId: String? {
        // The SET sheet has one annotation motif. If a semantic action links
        // to several evidence rows, choose the first canonical link rather
        // than drawing multiple underlines that dilute the selection signal.
        trace.actionRows.lazy.compactMap { $0.linkedEvidenceIds.first }.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SETSpacing.x6) {
                titleRow

                // The one accent: a single warm-white hairline between the
                // sheet chrome and the traced decision below it.
                DecisionTraceRule(isAccent: true)

                summaryPanel

                if !trace.evidenceRows.isEmpty {
                    DecisionTraceRule()
                    DecisionTraceSection(
                        label: Text(SETCopyKey.traceEvidence.localizedTextKey),
                        identifier: "trace_evidence_section"
                    ) {
                        DecisionTracePanel {
                            ForEach(Array(trace.evidenceRows.enumerated()), id: \.element.id) { index, row in
                                if index > 0 {
                                    DecisionTraceRule()
                                }
                                DecisionTraceEvidenceRow(
                                    row: row,
                                    isChosenEvidence: row.sourceId == chosenActionEvidenceId
                                )
                            }
                        }
                    }
                }

                if !trace.actionRows.isEmpty {
                    DecisionTraceRule()
                    DecisionTraceSection(
                        label: Text(SETCopyKey.traceChosen.localizedTextKey),
                        identifier: "trace_chosen_section"
                    ) {
                        DecisionTracePanel {
                            ForEach(Array(trace.actionRows.enumerated()), id: \.element.id) { index, row in
                                if index > 0 {
                                    DecisionTraceRule()
                                }
                                DecisionTraceActionRow(row: row)
                            }
                        }
                    }
                }

                if !trace.traceIds.isEmpty {
                    DecisionTraceRule()
                    DecisionTraceSection(
                        label: Text(SETCopyKey.traceIds.localizedTextKey),
                        identifier: "trace_traceids_section"
                    ) {
                        DecisionTraceTokenList(tokens: trace.traceIds)
                    }
                }

                if !trace.signalRows.isEmpty {
                    DecisionTraceRule()
                    DecisionTraceSection(
                        label: Text(SETCopyKey.traceSignals.localizedTextKey),
                        identifier: "trace_signals_section"
                    ) {
                        VStack(alignment: .leading, spacing: SETSpacing.x2) {
                            ForEach(trace.signalRows) { row in
                                DecisionTraceSignalRow(row: row)
                            }
                        }
                    }
                }

                if !trace.limitationRows.isEmpty {
                    DecisionTraceRule()
                    DecisionTraceSection(
                        label: Text(SETCopyKey.traceLimitations.localizedTextKey),
                        identifier: "trace_limitations_section"
                    ) {
                        VStack(alignment: .leading, spacing: SETSpacing.x2) {
                            ForEach(trace.limitationRows) { row in
                                Text(row.text)
                                    .font(SETTypography.uiBodyFont())
                                    .foregroundStyle(.setTextSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, SETSpacing.x4)
            .padding(.vertical, SETSpacing.x6)
        }
        .background(Color.setInk.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("decision_trace_sheet")
    }

    private var titleRow: some View {
        HStack(alignment: .top, spacing: SETSpacing.x4) {
            Text(SETCopyKey.traceTitle.localizedTextKey)
                .font(SETTypography.font(.display, size: SETTypographySize.title))
                .fontWeight(.bold)
                .setDisplayTracking()
                .foregroundStyle(.setTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: SETSpacing.x4)

            Button {
                dismiss()
            } label: {
                Text(SETCopyKey.commonDone.localizedTextKey)
                    .font(SETTypography.uiBodyFont(weight: .semibold))
                    .foregroundStyle(.setWarmWhite)
                    .underline()
                    .frame(minHeight: SETComponentMetric.minimumHitTarget)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trace_done_button")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("trace_title_row")
    }

    private var summaryPanel: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x3) {
            Text(trace.modeLabel)
                .font(SETTypography.font(.hudMono, size: SETTypographySize.micro))
                .tracking(0.35)
                .monospacedDigit()
                .foregroundStyle(.setTextSecondary)

            Text(trace.verdictLabel)
                .font(SETTypography.uiBodyFont(weight: .bold))
                .foregroundStyle(.setTextPrimary)

            Text(trace.headline)
                .font(SETTypography.uiBodyFont())
                .foregroundStyle(.setTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            DecisionTraceConfidenceText(confidence: trace.confidence)

            ForEach(trace.reasonLines) { line in
                DecisionTraceTextRow(title: line.title, text: line.text)
            }

            Text(SETCopyKey.traceExplanation.localizedTextKey)
                .font(SETTypography.uiBodyFont())
                .foregroundStyle(.setTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SETSpacing.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.setSurfaceSolid)
        .overlay {
            Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trace_summary_panel")
    }
}

// MARK: - Shared pieces

/// Section rule. Every boundary uses the hairline token; the one accent rule
/// is warm-white so the sheet carries exactly a single accent.
private struct DecisionTraceRule: View {
    var isAccent = false

    var body: some View {
        Rectangle()
            .fill(isAccent ? Color.setWarmWhite : Color.setHairline)
            .frame(height: SETStroke.hairline)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

/// One mono section label above editorial content. Sections are separated by
/// hairline rules at the owner level; no card wall of per-row panels.
private struct DecisionTraceSection<Content: View>: View {
    let label: Text
    let identifier: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x3) {
            label
                .font(SETTypography.font(.hudMono, size: SETTypographySize.micro))
                .tracking(0.35)
                .foregroundStyle(.setTextSecondary)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// A single square-cornered surface panel. Rows inside carry their own
/// padding and are divided by hairline rules, never by nested cards.
private struct DecisionTracePanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.setSurfaceSolid)
            .overlay {
                Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline)
            }
    }
}

private struct DecisionTraceTextRow: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x1) {
            Text(title)
                .font(SETTypography.uiBodyFont(weight: .semibold))
                .foregroundStyle(.setTextSecondary)
            Text(text)
                .font(SETTypography.uiBodyFont())
                .foregroundStyle(.setTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Neutral mono confidence read-out. The tone keys carry no color semantics;
/// the original spoken label stays as the accessibility string.
private struct DecisionTraceConfidenceText: View {
    let confidence: ConfidencePresentation
    @Environment(\.locale) private var locale

    private var key: SETCopyKey {
        switch confidence.tone {
        case .high:
            return .traceConfidenceHigh
        case .medium:
            return .traceConfidenceMedium
        case .low:
            return .traceConfidenceLow
        }
    }

    var body: some View {
        (Text(key.localizedTextKey) + Text(verbatim: " · \(confidence.percent)%"))
            .font(SETTypography.font(.hudMono, size: SETTypographySize.micro))
            .tracking(0.35)
            .monospacedDigit()
            .foregroundStyle(.setTextSecondary)
            .accessibilityLabel(Text(verbatim: localizedConfidenceText(confidence, locale: locale)))
    }
}

private func localizedConfidenceText(_ confidence: ConfidencePresentation, locale: Locale) -> String {
    let key: SETCopyKey
    switch confidence.tone {
    case .high:
        key = .traceConfidenceHigh
    case .medium:
        key = .traceConfidenceMedium
    case .low:
        key = .traceConfidenceLow
    }
    return "\(key.localizedString(locale: locale)) · \(confidence.percent)%"
}

private struct DecisionTraceEvidenceRow: View {
    let row: DecisionTracePresentation.EvidenceRow
    let isChosenEvidence: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x2) {
            Text(row.kindLabel)
                .font(SETTypography.font(.hudMono, size: SETTypographySize.micro))
                .tracking(0.35)
                .monospacedDigit()
                .foregroundStyle(.setTextSecondary)

            ZStack(alignment: .bottom) {
                Text(row.title)
                    .font(SETTypography.uiBodyFont(weight: .semibold))
                    .foregroundStyle(.setTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                // The single annotation motif: a hand underline on the
                // evidence the chosen action is linked to.
                if isChosenEvidence {
                    GlassMarkGuide(kind: .underline, color: .setWarmWhite)
                        .frame(height: SETSpacing.x2)
                        .padding(.horizontal, SETSpacing.x2)
                }
            }

            DecisionTraceConfidenceText(confidence: row.confidence)

            Text(row.text)
                .font(SETTypography.uiBodyFont())
                .foregroundStyle(.setTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            metadataLine
        }
        .padding(.horizontal, SETSpacing.x4)
        .padding(.vertical, SETSpacing.x3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("trace_evidence_row_\(row.id)")
    }

    private var metadataLine: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x1) {
            metadataValue(.traceMetadataID, row.sourceId)
            if let severity = row.severity {
                metadataValue(.traceMetadataSeverity, localizedConfidenceText(severity, locale: locale))
            }
            if let regionDescription = row.regionDescription {
                metadataValue(.traceMetadataRegion, regionDescription)
            }
            if let traceId = row.traceId {
                metadataValue(.traceMetadataTrace, traceId)
            }
        }
        .font(SETTypography.font(.hudMono, size: SETTypographySize.micro))
        .tracking(0.35)
        .monospacedDigit()
        .foregroundStyle(.setTextSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metadataValue(_ key: SETCopyKey, _ value: String) -> some View {
        Text(key.localizedTextKey) + Text(verbatim: ": \(value)")
    }
}

private struct DecisionTraceActionRow: View {
    let row: DecisionTracePresentation.ActionRow

    var body: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x2) {
            Text(row.title)
                .font(SETTypography.uiBodyFont(weight: .bold))
                .foregroundStyle(.setTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(row.semanticActionId)
                .font(SETTypography.font(.hudMono, size: SETTypographySize.micro))
                .tracking(0.35)
                .monospacedDigit()
                .foregroundStyle(.setTextSecondary)

            DecisionTraceConfidenceText(confidence: row.confidence)

            Text(row.detail)
                .font(SETTypography.uiBodyFont())
                .foregroundStyle(.setTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            metadataLine
        }
        .padding(.horizontal, SETSpacing.x4)
        .padding(.vertical, SETSpacing.x3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("trace_action_row_\(row.id)")
    }

    private var metadataLine: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x1) {
            if let coarseActionId = row.coarseActionId {
                metadataValue(.traceMetadataCoarse, coarseActionId)
            }
            if !row.linkedEvidenceIds.isEmpty {
                metadataValue(.traceMetadataLinkedEvidence, row.linkedEvidenceIds.joined(separator: ", "))
            }
            if let targetDescription = row.targetDescription {
                metadataValue(.traceMetadataTarget, targetDescription)
            }
            if let overlayHintId = row.overlayHintId {
                metadataValue(.traceMetadataOverlay, overlayHintId)
            }
            if let traceId = row.traceId {
                metadataValue(.traceMetadataTrace, traceId)
            }
        }
        .font(SETTypography.font(.hudMono, size: SETTypographySize.micro))
        .tracking(0.35)
        .monospacedDigit()
        .foregroundStyle(.setTextSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metadataValue(_ key: SETCopyKey, _ value: String) -> some View {
        Text(key.localizedTextKey) + Text(verbatim: ": \(value)")
    }
}

private struct DecisionTraceSignalRow: View {
    let row: DecisionTracePresentation.SignalRow

    var body: some View {
        HStack(alignment: .top, spacing: SETSpacing.x3) {
            VStack(alignment: .leading, spacing: SETSpacing.x1) {
                Text(row.title)
                    .font(SETTypography.uiBodyFont(weight: .semibold))
                    .foregroundStyle(.setTextPrimary)
                if let detail = row.detail {
                    Text(detail)
                        .font(SETTypography.uiBodyFont())
                        .foregroundStyle(.setTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.value)
                .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                .tracking(0.35)
                .monospacedDigit()
                .foregroundStyle(.setTextPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trace_signal_row_\(row.id)")
    }
}

/// Trace IDs as a quiet mono ledger, one line per id; no chip cloud.
private struct DecisionTraceTokenList: View {
    let tokens: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x1) {
            ForEach(tokens, id: \.self) { token in
                Text(token)
                    .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                    .tracking(0.35)
                    .monospacedDigit()
                    .foregroundStyle(.setTextPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trace_token_list")
    }
}

#if DEBUG
struct SETDecisionTraceFixtureConfiguration: Equatable {
    let fixtureID: String
    let locale: Locale
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let dynamicTypeSize: DynamicTypeSize
}

/// DEBUG root for the real DecisionTraceView. The presentation payload still
/// comes from `DecisionTracePresentation`, including locale-specific copy.
struct SETDecisionTraceFixtureRoot: View {
    let configuration: SETDecisionTraceFixtureConfiguration

    var body: some View {
        DecisionTraceView(trace: DecisionTracePresentation.debugFixture(locale: configuration.locale))
            .environment(\.locale, configuration.locale)
            .environment(\.dynamicTypeSize, configuration.dynamicTypeSize)
            .environment(\.setReduceMotionOverride, configuration.reduceMotion)
            .environment(\.setReduceTransparencyOverride, configuration.reduceTransparency)
            .background(Color.setInk.ignoresSafeArea())
    }
}
#endif

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
