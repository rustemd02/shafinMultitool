import SwiftUI

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

    var body: some View {
        if let suggestion {
            Text(suggestion.text)
                .font(.headline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: CameraOverlayUXPresentation.surfaceWidth(for: canvasSize), alignment: .leading)
                .padding(SETSpacing.x4)
                .foregroundStyle(.setTextPrimary)
                .background(.setSurfaceSolid)
                .overlay { Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline) }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(CameraOverlayAccessibilityID.surface)
                .accessibilityLabel(suggestion.text)
        }
    }

}

struct LiveHintChipView: View {
    let liveHint: LiveHintPresentation?
    let fallbackSuggestion: Suggestion?
    let boundingBox: CGRect?
    let canvasSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

        VStack(alignment: .leading, spacing: SETSpacing.x3) {
            Text(currentPresentation.observation)
                .font(.headline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(CameraOverlayAccessibilityID.observation)

            if let supportingObservation = currentPresentation.supportingObservation,
               currentPresentation.baseState == .keepAsIs {
                Text(supportingObservation)
                    .font(.subheadline)
                    .foregroundStyle(.setTextSecondary)
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
                    Text((isExpanded ? SETCopyKey.cameraHideWhy : SETCopyKey.cameraWhy).localizedTextKey)
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: CameraOverlayUXPresentation.minimumControlDimension,
                               minHeight: CameraOverlayUXPresentation.minimumControlDimension,
                               alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.setOrange)
                .accessibilityIdentifier(CameraOverlayAccessibilityID.why)
                .accessibilityLabel((isExpanded ? SETCopyKey.cameraHideWhy : SETCopyKey.cameraWhy).localizedTextKey)
                .accessibilityValue((isExpanded ? SETCopyKey.cameraWhyValueOpen : SETCopyKey.cameraWhyValueClosed).localizedTextKey)
                .accessibilityHint((isExpanded ? SETCopyKey.cameraHideWhy : SETCopyKey.accessibilityExplainHint).localizedTextKey)
                .accessibilityFocused($whyFocused)
            }

            if isExpanded,
               currentPresentation.state == .explanation,
               let explanation = currentPresentation.explanation {
                VStack(alignment: .leading, spacing: 5) {
                    Text(SETCopyKey.cameraWhyHeader.localizedTextKey)
                        .font(.subheadline.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(explanation)
                        .font(.subheadline)
                        .foregroundStyle(.setTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier(CameraOverlayAccessibilityID.explanation)
                .accessibilityElement(children: .combine)
                .accessibilityFocused($explanationFocused)
            }
        }
        .padding(SETSpacing.x4)
        .frame(width: CameraOverlayUXPresentation.surfaceWidth(for: canvasSize), alignment: .leading)
        .foregroundStyle(.setTextPrimary)
        .background(.setHUDScrim)
        .overlay {
            Rectangle()
                .strokeBorder(.setHairline, lineWidth: SETStroke.hairline)
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
