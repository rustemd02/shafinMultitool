import SwiftUI
import UIKit

enum CameraOverlayAccessibilityID {
    static let surface = "camera_coach_live_surface"
    static let observation = "camera_coach_observation"
    static let action = "camera_coach_action"
    static let why = "camera_coach_why"
    static let explanation = "camera_coach_explanation"
    static let seeking = "camera_coach_seeking_status"
    static let zoom = "camera_coach_zoom_control"
}

/// Compatibility view for legacy callers. The live Camera Coach uses
/// `LiveHintChipView` and never renders an arbitrary legacy suggestion.
struct SuggestionChipView: View {
    let suggestion: Suggestion?
    let boundingBox: CGRect?
    let canvasSize: CGSize

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if let suggestion {
            Text(suggestion.text)
                .font(.headline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: CameraOverlayUXPresentation.surfaceWidth(for: canvasSize), alignment: .leading)
                .padding(16)
                .foregroundStyle(.primary)
                .background(surfaceBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(CameraOverlayAccessibilityID.surface)
                .accessibilityLabel(suggestion.text)
        }
    }

    private var surfaceBackground: AnyShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
            : AnyShapeStyle(.regularMaterial)
    }
}

struct LiveHintChipView: View {
    let liveHint: LiveHintPresentation?
    let fallbackSuggestion: Suggestion?
    let boundingBox: CGRect?
    let canvasSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AccessibilityFocusState private var whyFocused: Bool
    @AccessibilityFocusState private var explanationFocused: Bool
    @State private var isExpanded = false

    private var presentation: CameraOverlayUXPresentation {
        if let liveHint {
            return CameraOverlayUXPresentation.make(liveHint: liveHint, isExpanded: isExpanded)
        }
        if fallbackSuggestion != nil {
            return CameraOverlayUXPresentation.safeFallbackPresentation
        }
        return CameraOverlayUXPresentation.make(liveHint: nil)
    }

    var body: some View {
        let currentPresentation = presentation

        VStack(alignment: .leading, spacing: 10) {
            Text(currentPresentation.observation)
                .font(.headline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(CameraOverlayAccessibilityID.observation)

            if let supportingObservation = currentPresentation.supportingObservation,
               currentPresentation.baseState == .keepAsIs {
                Text(supportingObservation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(CameraOverlayAccessibilityID.observation)_basis")
            }

            if let actionInstruction = currentPresentation.actionInstruction {
                Text(actionInstruction)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(CameraOverlayAccessibilityID.action)
            }

            if currentPresentation.showsWhy {
                Button(action: toggleExplanation) {
                    Text(isExpanded ? "Скрыть объяснение" : "Почему?")
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: CameraOverlayUXPresentation.minimumControlDimension,
                               minHeight: CameraOverlayUXPresentation.minimumControlDimension,
                               alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityIdentifier(CameraOverlayAccessibilityID.why)
                .accessibilityLabel(isExpanded ? "Скрыть объяснение" : "Почему?")
                .accessibilityValue(isExpanded ? "Объяснение открыто" : "Объяснение скрыто")
                .accessibilityHint(isExpanded
                    ? "Свернуть объяснение совета."
                    : "Открыть краткое объяснение совета.")
                .accessibilityFocused($whyFocused)
            }

            if isExpanded,
               currentPresentation.state == .explanation,
               let explanation = currentPresentation.explanation {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Почему это помогает")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(explanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier(CameraOverlayAccessibilityID.explanation)
                .accessibilityElement(children: .combine)
                .accessibilityFocused($explanationFocused)
            }
        }
        .padding(16)
        .frame(width: CameraOverlayUXPresentation.surfaceWidth(for: canvasSize), alignment: .leading)
        .foregroundStyle(.primary)
        .background(surfaceBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(reduceTransparency ? 0.75 : 0.45), lineWidth: 0.7)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CameraOverlayAccessibilityID.surface)
        .accessibilityLabel(currentPresentation.accessibilityLabel)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isExpanded)
        .onChange(of: liveHint?.id) { _ in
            isExpanded = false
            whyFocused = false
            explanationFocused = false
        }
    }

    private var surfaceBackground: AnyShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
            : AnyShapeStyle(.regularMaterial)
    }

    private func toggleExplanation() {
        let shouldExpand = !isExpanded
        if reduceMotion {
            isExpanded = shouldExpand
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded = shouldExpand
            }
        }

        whyFocused = !shouldExpand
        explanationFocused = shouldExpand
    }
}
