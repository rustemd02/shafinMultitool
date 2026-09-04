//
//  SceneGeneratorView.swift
//  shafinMultitool
//
//  Created on 30.11.2025.
//

import SwiftUI
import UIKit

struct SceneGeneratorView: View {
    @StateObject private var viewModel: SceneGeneratorViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.setReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.setReduceTransparencyOverride) private var reduceTransparencyOverride

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    private var reduceTransparency: Bool { reduceTransparencyOverride ?? systemReduceTransparency }

    init(projectName: String = "Новая сцена", isNewProject: Bool = true) {
        self.init(
            viewModel: SceneGeneratorViewModel(projectName: projectName, isNewProject: isNewProject)
        )
    }

    init(viewModel: SceneGeneratorViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack(alignment: .top) {
            LegacySceneGeneratorCameraShell(
                viewModel: viewModel,
                presentationLocale: locale,
                reduceMotion: reduceMotion,
                reduceTransparency: reduceTransparency,
                dynamicTypeSize: dynamicTypeSize
            ) {
                Task { @MainActor in
                    guard await viewModel.teardownAndWait() == .released else { return }
                    dismiss()
                }
            }
            .ignoresSafeArea()

            // `generator.error` band replaces the retired system alert; the
            // camera shell keeps running underneath the inline recovery.
            if viewModel.isGeneratorErrorBandVisible {
                GeneratorErrorBand(viewModel: viewModel)
                    .transition(
                        reduceMotion
                            ? AnyTransition.opacity
                            : AnyTransition.move(edge: .top).combined(with: .opacity)
                    )
            }
        }
        .animation(
            reduceMotion
                ? .easeOut(duration: SETMotion.reducedMotionCrossfadeDuration)
                : SETMotion.standardSpring,
            value: viewModel.isGeneratorErrorBandVisible
        )
        .onAppear {
            viewModel.prepareWorkspace()
        }
        .onDisappear {
            Task { @MainActor in
                _ = await viewModel.teardownAndWait()
            }
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .background else { return }
            Task { @MainActor in
                guard await viewModel.teardownAndWait() == .released else { return }
                dismiss()
            }
        }
        .sheet(isPresented: $viewModel.showInputSheet) {
            SceneInputSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showMarkerNameInput) {
            MarkerNameInputSheet(
                onCancel: {
                    viewModel.cancelMarkerCreation()
                },
                onSave: { name in
                    viewModel.createMarker(withName: name)
                },
                shouldCancelOnDisappear: {
                    viewModel.pendingMarkerPosition != nil
                }
            )
                .presentationDetents([.height(190)])
                .presentationDragIndicator(.visible)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Error band (`generator.error`)

/// Compact editorial error band pinned to the top of the generator surface.
/// The detail string is runtime data and is kept verbatim; closing it clears
/// the copy and recovery affordance, never the underlying session state.
private struct GeneratorErrorBand: View {
    @ObservedObject var viewModel: SceneGeneratorViewModel

    var body: some View {
            VStack(alignment: .leading, spacing: SETSpacing.x3) {
                Text(SETCopyKey.generatorErrorTitle.localizedTextKey)
                .font(SETTypography.font(.display, size: SETTypographySize.title))
                .fontWeight(.bold)
                .setDisplayTracking()
                .foregroundStyle(.setTextPrimary)

            Text(viewModel.errorMessage ?? "")
                .font(SETTypography.uiBodyFont())
                .foregroundStyle(.setTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let recovery = viewModel.recordingPermissionRecovery {
                switch recovery {
                case .openSettings:
                    SETDigitalAction(title: .openSettings, action: openSettings)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("generator_microphone_open_settings")
                        .accessibilityLabel(SETCopyKey.openSettings.localizedTextKey)
                case .recheck:
                    SETDigitalAction(title: .checkAgain, action: viewModel.retryRecording)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("generator_microphone_recheck")
                        .accessibilityLabel(SETCopyKey.accessibilityRecheck.localizedTextKey)
                        .accessibilityHint(SETCopyKey.accessibilityRecheck.localizedTextKey)
                }
            }

            ZStack(alignment: .bottom) {
                Button {
                    viewModel.clearGeneratorError()
                } label: {
                    Text(SETCopyKey.commonClose.localizedTextKey)
                        .font(SETTypography.uiBodyFont(weight: .semibold))
                        .foregroundStyle(.setWarmWhite)
                        .underline()
                        .frame(minHeight: SETComponentMetric.minimumHitTarget)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("generator_error_close")
                .accessibilityLabel(SETCopyKey.commonClose.localizedTextKey)

                // One underline annotation on the recovery action.
                GlassMarkGuide(kind: .underline, color: .setOrange)
                    .frame(height: SETSpacing.x2)
                    .padding(.horizontal, SETSpacing.x2)
                    .offset(y: SETSpacing.x1)
            }
        }
        .padding(SETSpacing.x4)
        .background(Color.setSurfaceSolid)
        .overlay(alignment: .bottom) {
            CutSeam(axis: .horizontal)
                .frame(height: SETStroke.standard)
        }
        .overlay {
            Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline)
        }
        // Keep the band as a named container without replacing the child
        // button's stable accessibility identifier in UIKit's AX tree.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("generator_error_band")
    }

    @Environment(\.openURL) private var openURL

    private func openSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(settingsURL)
    }
}

// MARK: - Marker name input (`sheet.marker-name`)

/// Marker-name entry panel in the SET editorial register. Behavior (focus,
/// submit, explicit/implicit dismissal) is unchanged; only the projection
/// was restyled.
struct MarkerNameInputSheet: View {
    let onCancel: () -> Void
    let onSave: (String) -> Void
    let shouldCancelOnDisappear: () -> Bool

    @State private var markerName: String = ""
    @State private var didFinishExplicitly = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x3) {
            Text(SETCopyKey.generatorMarkerTitle.localizedTextKey)
                .font(SETTypography.font(.display, size: SETTypographySize.title))
                .fontWeight(.bold)
                .setDisplayTracking()
                .foregroundStyle(.setTextPrimary)

            ZStack(alignment: .bottom) {
                TextField(
                    "",
                    text: $markerName,
                    prompt: Text(SETCopyKey.generatorMarkerPlaceholder.localizedTextKey)
                        .foregroundStyle(.setTextTertiary)
                )
                .font(SETTypography.font(.screenplay, size: SETTypographySize.body))
                .foregroundStyle(.setTextPrimary)
                .padding(SETSpacing.x3)
                .background(Color.setSurfaceSolid)
                .overlay {
                    Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline)
                }
                .focused($isNameFocused)
                .submitLabel(.done)
                .onSubmit(saveMarkerIfPossible)
                .accessibilityIdentifier("marker_name_field")

                // One underline annotation on the focused field.
                if isNameFocused {
                    GlassMarkGuide(kind: .underline, color: .setOrange)
                        .frame(height: SETSpacing.x2)
                        .padding(.horizontal, SETSpacing.x2)
                }
            }

            HStack(spacing: SETSpacing.x4) {
                SETDigitalAction(title: .generatorMarkerSave, action: saveMarkerIfPossible)
                    .disabled(markerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(markerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                    .accessibilityIdentifier("marker_name_save")

                Button {
                    didFinishExplicitly = true
                    onCancel()
                } label: {
                    Text(SETCopyKey.libraryCancel.localizedTextKey)
                        .font(SETTypography.uiBodyFont(weight: .semibold))
                        .foregroundStyle(.setTextSecondary)
                        .underline()
                        .frame(minHeight: SETComponentMetric.minimumHitTarget)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("marker_name_cancel")
            }
        }
        .padding(SETSpacing.x4)
        .background(Color.setInk.ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            // One registration mark punctuates the entry panel.
            SETRegistrationMarks(corner: .topLeading)
                .frame(width: 28, height: 28)
                .padding(SETSpacing.x3)
        }
        .accessibilityIdentifier("marker_name_sheet")
        .onAppear {
            DispatchQueue.main.async {
                isNameFocused = true
            }
        }
        .onDisappear {
            if !didFinishExplicitly && shouldCancelOnDisappear() {
                onCancel()
            }
        }
    }

    private func saveMarkerIfPossible() {
        let trimmedName = markerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        didFinishExplicitly = true
        onSave(trimmedName)
        markerName = ""
    }
}

#if DEBUG
struct SceneGeneratorView_Previews: PreviewProvider {
    static var previews: some View {
        SceneGeneratorView()
    }
}
#endif
