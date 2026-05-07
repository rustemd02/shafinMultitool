//
//  SuggestionChip.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import SwiftUI

struct SuggestionChipView: View {
    let suggestion: Suggestion?
    let boundingBox: CGRect?
    let canvasSize: CGSize

    var body: some View {
        VStack {
            if let suggestion {
                Text(suggestion.text)
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(width: chipWidth, alignment: .leading)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(radius: 6)
                    .padding(.top, 24)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: suggestion?.id)
    }

    private var chipWidth: CGFloat {
        min(360, max(160, canvasSize.width - 48))
    }
}

struct LiveHintChipView: View {
    let liveHint: LiveHintPresentation?
    let fallbackSuggestion: Suggestion?
    let boundingBox: CGRect?
    let canvasSize: CGSize
    @State private var isExpanded: Bool = false

    private var displayText: String? {
        liveHint?.text ?? fallbackSuggestion?.text
    }

    private var expandedVerdict: LiveExpandedVerdictPresentation? {
        liveHint?.expandedVerdict
    }

    private var canExpand: Bool {
        expandedVerdict != nil
    }

    var body: some View {
        VStack {
            if let displayText {
                hintBody(text: displayText)
            }
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
    }

    @ViewBuilder
    private func hintBody(text: String) -> some View {
        let content = VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(text)
                    .font(.headline.weight(.semibold))
                    .lineLimit(isExpanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if canExpand {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.top, 1)
                }
            }

            if isExpanded, let expandedVerdict {
                LiveExpandedVerdictContent(expandedVerdict: expandedVerdict)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: chipWidth, alignment: .leading)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: isExpanded ? 18 : 28, style: .continuous)
        )
        .overlay(alignment: .topTrailing) {
            if liveHint?.isFallback == true {
                Text("резерв")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.yellow.opacity(0.9), in: Capsule())
                    .offset(x: 6, y: -10)
            }
        }
        .shadow(radius: 6)
        .contentShape(Rectangle())
        .transition(.opacity)

        if canExpand {
            Button(action: { isExpanded.toggle() }) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityLabel(displayText ?? "Подсказка кадра")
            .accessibilityHint(isExpanded ? "Свернуть подробное объяснение." : "Открыть подробное объяснение.")
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel(displayText ?? "Подсказка кадра")
        }
    }

    private var chipWidth: CGFloat {
        if isExpanded {
            return min(420, max(180, canvasSize.width - 32))
        }
        return min(360, max(160, canvasSize.width - 48))
    }
}

private struct LiveExpandedVerdictContent: View {
    let expandedVerdict: LiveExpandedVerdictPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(expandedVerdict.shortVerdict)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            if let supportingText = expandedVerdict.supportingText {
                Text(supportingText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionText = expandedVerdict.actionText {
                Text(actionText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if expandedVerdict.fallbackUsed {
                Text("Структурный разбор ограничен")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.yellow.opacity(0.95))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
