//
//  SuggestionListView.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import SwiftUI

struct SuggestionListView: View {
    let suggestions: [Suggestion]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(suggestions) { s in
                HStack(spacing: 8) {
                    Text(icon(for: s.type))
                    Text(s.text)
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Резервная подсказка")
                .accessibilityValue(s.text)
            }
        }
        .padding(.horizontal, 16)
        .transition(.opacity)
    }

    private func icon(for type: SuggestionType) -> String {
        switch type {
        case .horizon: return "📐"
        case .exposure: return "🔆"
        case .composition: return "🎯"
        case .lighting: return "💡"
        case .lens: return "🔭"
        case .other: return "💬"
        }
    }
}

struct PauseCritiqueCardView: View {
    let critique: PauseCritiquePresentation
    let legacySuggestions: [Suggestion]

    fileprivate struct PauseTipRow: Identifiable {
        let id: String
        let title: String
        let reason: String
        let action: String?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(critique.shortVerdict)
                    .font(.headline.weight(.semibold))
                Spacer()
                Text(critique.verdict == .good ? "GOOD" : "REVIEW")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.2), in: Capsule())
            }
            .accessibilityElement(children: .combine)

            if let summaryText {
                Text(summaryText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Объяснение")
                    .accessibilityValue(summaryText)
            }

            if !tipRows.isEmpty {
                sectionTitle(critique.verdict == .good ? "Что сохранить" : "Семантические советы")
                ForEach(tipRows) { row in
                    PauseTipRowView(row: row)
                }
            }

            if !critique.strengths.isEmpty {
                sectionTitle("Почему кадр работает")
                ForEach(Array(critique.strengths.prefix(2)), id: \.strengthId) { item in
                    Text("• \(item.rationale)")
                        .font(.subheadline)
                        .accessibilityElement(children: .combine)
                }
            }

            if !critique.issues.isEmpty, critique.verdict != .good {
                sectionTitle("Что мешает")
                ForEach(Array(critique.issues.prefix(3)), id: \.issueId) { item in
                    Text("• \(item.rationale)")
                        .font(.subheadline)
                        .accessibilityElement(children: .combine)
                }
            }

            if !critique.actions.isEmpty, tipRows.isEmpty {
                sectionTitle("Что делать")
                ForEach(Array(critique.actions.prefix(3)), id: \.actionId) { item in
                    Text("• \(item.expectedOutcome)")
                        .font(.subheadline.weight(.medium))
                        .accessibilityElement(children: .combine)
                }
            } else if let noChangeRationale, tipRows.isEmpty {
                sectionTitle("Что делать")
                Text("• \(noChangeRationale)")
                    .font(.subheadline.weight(.medium))
                    .accessibilityElement(children: .combine)
            }

            if showEmptyState {
                sectionTitle("Состояние кадра")
                Text("Пока нет новых рекомендаций. Попробуй слегка изменить ракурс и остановить кадр снова.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Нет новых рекомендаций")
                    .accessibilityValue("Измени ракурс и попробуй еще раз.")
            }

            if critique.fallbackUsed {
                fallbackBanner
            }

            if critique.fallbackUsed, !legacySuggestions.isEmpty {
                sectionTitle("Резервные подсказки")
                SuggestionListView(suggestions: Array(legacySuggestions.prefix(3)))
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(.white.opacity(0.85))
            .padding(.top, 2)
    }

    private var summaryText: String? {
        if critique.verdict == .good {
            return nonEmpty(critique.whyGood)
        }
        return nonEmpty(critique.whyProblematic)
    }

    private var noChangeRationale: String? {
        nonEmpty(critique.noChangeRationale)
    }

    private var showEmptyState: Bool {
        tipRows.isEmpty
            && critique.actions.isEmpty
            && critique.issues.isEmpty
            && critique.strengths.isEmpty
            && noChangeRationale == nil
    }

    private var tipRows: [PauseTipRow] {
        if critique.verdict == .good {
            let strengthRows = critique.strengths.prefix(2).map { strength in
                PauseTipRow(
                    id: "strength_\(strength.strengthId)",
                    title: "Сильная сторона",
                    reason: strength.rationale,
                    action: noChangeRationale
                )
            }
            if !strengthRows.isEmpty {
                return Array(strengthRows)
            }
            if let noChangeRationale {
                return [
                    PauseTipRow(
                        id: "good_frame",
                        title: "Кадр готов",
                        reason: nonEmpty(critique.whyGood) ?? critique.shortVerdict,
                        action: noChangeRationale
                    )
                ]
            }
            return []
        }

        return critique.actions.prefix(4).map { action in
            PauseTipRow(
                id: action.actionId,
                title: "Совет \(action.priority)",
                reason: reasonText(for: action),
                action: nonEmpty(action.expectedOutcome)
            )
        }
    }

    private var fallbackBanner: some View {
        Text("Расширенный разбор частично ограничен — сохраняем структурные советы и показываем резервный список.")
            .font(.caption.weight(.semibold))
            .foregroundColor(.yellow)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Ограниченный разбор")
            .accessibilityValue("Показаны структурные советы и резервные подсказки.")
    }

    private func reasonText(for action: PauseActionRow) -> String {
        if let issue = critique.issues.first(where: { action.linkedIssueIds.contains($0.issueId) }),
           let reason = nonEmpty(issue.rationale) {
            return reason
        }
        return nonEmpty(critique.whyProblematic) ?? critique.shortVerdict
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct PauseTipRowView: View {
    let row: PauseCritiqueCardView.PauseTipRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))

            Text(row.reason)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            if let action = row.action {
                Text(action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.96))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
