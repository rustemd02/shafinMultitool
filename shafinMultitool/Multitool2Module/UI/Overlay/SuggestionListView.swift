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

            if !critique.strengths.isEmpty {
                sectionTitle("Почему кадр работает")
                ForEach(Array(critique.strengths.prefix(2).enumerated()), id: \.offset) { _, item in
                    Text("• \(item.rationale)")
                        .font(.subheadline)
                }
            }

            if !critique.issues.isEmpty {
                sectionTitle("Что мешает")
                ForEach(Array(critique.issues.prefix(3).enumerated()), id: \.offset) { _, item in
                    Text("• \(item.rationale)")
                        .font(.subheadline)
                }
            }

            if !critique.actions.isEmpty {
                sectionTitle("Что делать")
                ForEach(Array(critique.actions.prefix(3).enumerated()), id: \.offset) { _, item in
                    Text("• \(item.expectedOutcome)")
                        .font(.subheadline.weight(.medium))
                }
            } else if let noChangeRationale = critique.noChangeRationale, !noChangeRationale.isEmpty {
                sectionTitle("Что делать")
                Text("• \(noChangeRationale)")
                    .font(.subheadline.weight(.medium))
            }

            if critique.fallbackUsed {
                Text("Structured analysis degraded: используется legacy backup.")
                    .font(.caption)
                    .foregroundColor(.yellow)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ViewBuilder
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(.white.opacity(0.85))
            .padding(.top, 2)
    }
}

