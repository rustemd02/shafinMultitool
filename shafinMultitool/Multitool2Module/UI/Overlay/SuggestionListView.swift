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



