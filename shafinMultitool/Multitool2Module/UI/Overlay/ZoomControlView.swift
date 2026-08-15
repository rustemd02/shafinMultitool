import SwiftUI
import UIKit

struct ZoomControlView: View {
    let availableLenses: [CameraLens]
    let currentLens: CameraLens
    let onLensChange: (CameraLens) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 8) {
            ForEach(availableLenses, id: \.rawValue) { lens in
                ZoomButton(
                    lens: lens,
                    isSelected: lens == currentLens,
                    reduceMotion: reduceMotion,
                    action: { onLensChange(lens) }
                )
            }
        }
        .padding(8)
        .background(
            reduceTransparency
                ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
                : AnyShapeStyle(.regularMaterial),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.55), lineWidth: 0.7)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera_coach_zoom_control")
        .accessibilityLabel("Выбор масштаба камеры")
    }
}

private struct ZoomButton: View {
    let lens: CameraLens
    let isSelected: Bool
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(lens.displayName)
                .font(.body.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(minWidth: CameraOverlayUXPresentation.minimumControlDimension,
                       minHeight: CameraOverlayUXPresentation.minimumControlDimension)
                .background(
                    isSelected ? Color.accentColor.opacity(0.18) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Масштаб \(lens.displayName)")
        .accessibilityValue(isSelected ? "Выбран" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isSelected)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()

            ZoomControlView(
                availableLenses: [.ultraWide, .wide, .telephoto2x, .telephoto3x],
                currentLens: .wide,
                onLensChange: { _ in }
            )
            .padding(.bottom, 40)
        }
    }
}
