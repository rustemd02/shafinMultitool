import SwiftUI

/// A collapsed lens control keeps the live frame primary. The expanded menu is
/// populated only from the camera manager's reported physical lenses; it never
/// invents a focal-length rail.
struct ZoomControlView: View {
    let availableLenses: [CameraLens]
    let currentLens: CameraLens
    var lensDescriptors: [CameraLensDescriptor] = []
    var isInteractionLocked = false
    let onLensChange: (CameraLens) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isExpanded = false

    var body: some View {
        Group {
            if isExpanded {
                expandedControl.transition(
                    reduceMotion
                        ? .opacity.animation(.easeOut(duration: SETMotion.reducedMotionCrossfadeDuration))
                        : .opacity
                )
            } else {
                collapsedControl.transition(
                    reduceMotion
                        ? .opacity.animation(.easeOut(duration: SETMotion.reducedMotionCrossfadeDuration))
                        : .opacity
                )
            }
        }
        .padding(SETSpacing.x1)
        .background(reduceTransparency ? Color.setSurfaceSolid : Color.setHUDScrim)
        .overlay {
            Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CameraOverlayAccessibilityID.zoom)
        .accessibilityLabel(Text(SETCopyKey.cameraZoom.localizedTextKey))
        .animation(
            reduceMotion ? nil : SETMotion.standardSpring,
            value: isExpanded
        )
        .onChange(of: availableLenses) { _, lenses in
            if lenses.isEmpty { isExpanded = false }
        }
    }

    private var collapsedControl: some View {
        Button {
            guard !availableLenses.isEmpty else { return }
            if reduceMotion {
                isExpanded = true
            } else {
                withAnimation(SETMotion.standardSpring) {
                    isExpanded = true
                }
            }
        } label: {
            HStack(spacing: SETCameraCoachMetric.compactControlSpacing) {
                Text(label(for: currentLens))
                    .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(.setTextPrimary)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.setTextSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, SETSpacing.x3)
            .frame(minWidth: SETComponentMetric.minimumHitTarget,
                   minHeight: SETComponentMetric.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(label(for: currentLens)))
        .accessibilityHint(Text(SETCopyKey.cameraLensExpand.localizedTextKey))
    }

    private var expandedControl: some View {
        HStack(spacing: SETSpacing.x1) {
            ForEach(availableLenses, id: \.rawValue) { lens in
                Button {
                    guard !isInteractionLocked else { return }
                    onLensChange(lens)
                    if reduceMotion {
                        isExpanded = false
                    } else {
                        withAnimation(SETMotion.standardSpring) {
                            isExpanded = false
                        }
                    }
                } label: {
                    Text(label(for: lens))
                        .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                        .fontWeight(lens == currentLens ? .semibold : .regular)
                        .monospacedDigit()
                        .foregroundStyle(lens == currentLens ? .setTextPrimary : .setTextSecondary)
                        .frame(minWidth: SETComponentMetric.minimumHitTarget,
                               minHeight: SETComponentMetric.minimumHitTarget)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(lens == currentLens ? Color.setOrange : Color.clear)
                                .frame(height: SETStroke.standard)
                        }
                }
                .buttonStyle(.plain)
                .disabled(isInteractionLocked)
                .accessibilityLabel(Text(
                    String(format: SETCopyKey.cameraLensOption.localizedString, label(for: lens))
                ))
                .accessibilityValue(Text(
                    lens == currentLens ? SETCopyKey.cameraLensSelected.localizedTextKey : ""
                ))
                .accessibilityAddTraits(lens == currentLens ? .isSelected : [])
            }

            Button {
                if reduceMotion {
                    isExpanded = false
                } else {
                    withAnimation(SETMotion.standardSpring) {
                        isExpanded = false
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.setTextSecondary)
                    .accessibilityHidden(true)
                    .frame(minWidth: SETComponentMetric.minimumHitTarget,
                           minHeight: SETComponentMetric.minimumHitTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(SETCopyKey.cameraLensCollapse.localizedTextKey))
        }
    }

    private func label(for lens: CameraLens) -> String {
        lensDescriptors.first(where: { $0.lens == lens })?.displayLabel
            ?? lens.descriptor.displayLabel
    }
}

#Preview {
    ZStack {
        Color.setInk.ignoresSafeArea()

        VStack {
            Spacer()

            ZoomControlView(
                availableLenses: [.ultraWide, .wide, .telephoto],
                currentLens: .wide,
                onLensChange: { _ in }
            )
            .padding(.bottom, SETSpacing.x8)
        }
    }
}
