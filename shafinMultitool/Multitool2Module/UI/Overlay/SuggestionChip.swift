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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(radius: 6)
                    .padding(placementInsets)
                    .frame(maxWidth: .infinity, alignment: chipAlignment)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: suggestion?.id)
    }

    private var chipAlignment: Alignment {
        guard let boundingBox else { return .top }
        return boundingBox.midX > 0.5 ? .topLeading : .topTrailing
    }

    private var placementInsets: EdgeInsets {
        guard let boundingBox else { return EdgeInsets(top: 24, leading: 24, bottom: 0, trailing: 24) }
        let converted = convert(boundingBox: boundingBox)
        let top = max(24, converted.minY - 48)
        let leading = max(24, converted.minX)
        let trailing = max(24, canvasSize.width - converted.maxX)
        return EdgeInsets(top: top, leading: leading, bottom: 0, trailing: trailing)
    }

    private func convert(boundingBox: CGRect) -> CGRect {
        let width = boundingBox.width * canvasSize.width
        let height = boundingBox.height * canvasSize.height
        let x = boundingBox.minX * canvasSize.width
        let y = (1 - boundingBox.maxY) * canvasSize.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

struct LiveHintChipView: View {
    let liveHint: LiveHintPresentation?
    let fallbackSuggestion: Suggestion?
    let boundingBox: CGRect?
    let canvasSize: CGSize

    private var displayText: String? {
        liveHint?.text ?? fallbackSuggestion?.text
    }

    private var hintIdentity: String {
        if let liveHint {
            return liveHint.id
        }
        if let fallbackSuggestion {
            return fallbackSuggestion.id.uuidString
        }
        return "no_hint"
    }

    var body: some View {
        VStack {
            if let displayText {
                Text(displayText)
                    .font(.headline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(alignment: .topTrailing) {
                        if liveHint?.isFallback == true {
                            Text("fallback")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.yellow.opacity(0.9), in: Capsule())
                                .offset(x: 6, y: -10)
                        }
                    }
                    .shadow(radius: 6)
                    .padding(placementInsets)
                    .frame(maxWidth: .infinity, alignment: chipAlignment)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: hintIdentity)
    }

    private var chipAlignment: Alignment {
        guard let boundingBox else { return .top }
        return boundingBox.midX > 0.5 ? .topLeading : .topTrailing
    }

    private var placementInsets: EdgeInsets {
        guard let boundingBox else { return EdgeInsets(top: 24, leading: 24, bottom: 0, trailing: 24) }
        let converted = convert(boundingBox: boundingBox)
        let top = max(24, converted.minY - 48)
        let leading = max(24, converted.minX)
        let trailing = max(24, canvasSize.width - converted.maxX)
        return EdgeInsets(top: top, leading: leading, bottom: 0, trailing: trailing)
    }

    private func convert(boundingBox: CGRect) -> CGRect {
        let width = boundingBox.width * canvasSize.width
        let height = boundingBox.height * canvasSize.height
        let x = boundingBox.minX * canvasSize.width
        let y = (1 - boundingBox.maxY) * canvasSize.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}


