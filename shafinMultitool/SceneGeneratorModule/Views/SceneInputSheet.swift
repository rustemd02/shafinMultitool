//
//  SceneInputSheet.swift
//  shafinMultitool
//
//  Created on 30.11.2025.
//

import SwiftUI

/// Screenplay input sheet, SET OS editorial register (`generator.input-*` and
/// `sheet.screenplay-input` rows). Behavior stays with `SceneGeneratorViewModel`;
/// this surface only restyles the projection.
struct SceneInputSheet: View {

    @ObservedObject var viewModel: SceneGeneratorViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        ZStack {
            Color.setInk.ignoresSafeArea()
            portraitLayout
        }
        .overlay(alignment: .topTrailing) {
            SETRegistrationMarks(corner: .topTrailing)
                .frame(width: 28, height: 28)
                .padding(SETSpacing.x3)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Layout

    private var portraitLayout: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: SETSpacing.x4) {
                    headerSection
                    if !viewModel.markedObjects.isEmpty { markedObjectsSection }
                    textInputSection
                    if !viewModel.detectedObjects.isEmpty { detectedObjectsSection }
                    Spacer(minLength: SETSpacing.x12)
                }
                .padding(SETSpacing.x4)
            }
            generateButton
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline, spacing: SETSpacing.x3) {
            Text(SETCopyKey.generatorInputTitle.localizedTextKey)
                .font(SETTypography.font(.display, size: SETTypographySize.displayMedium))
                .fontWeight(.bold)
                .setDisplayTracking()
                .foregroundStyle(.setTextPrimary)
                .accessibilityIdentifier("generator_input_title")

            Spacer(minLength: SETSpacing.x3)

            Button {
                dismiss()
            } label: {
                Text(SETCopyKey.libraryCancel.localizedTextKey)
                    .font(SETTypography.uiBodyFont(weight: .semibold))
                    .foregroundStyle(.setTextSecondary)
                    .underline()
                    .frame(minWidth: SETComponentMetric.minimumHitTarget,
                           minHeight: SETComponentMetric.minimumHitTarget)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("generator_input_cancel")
        }
    }

    // MARK: - Text input

    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x2) {
            Text(SETCopyKey.generatorInputTitle.localizedTextKey)
                .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                .tracking(0.65)
                .foregroundStyle(.setTextSecondary)

            ZStack(alignment: .topLeading) {
                if viewModel.sceneDescription.isEmpty {
                    Text(SETCopyKey.generatorInputPlaceholder.localizedTextKey)
                        .font(SETTypography.font(.screenplay, size: SETTypographySize.body))
                        .foregroundStyle(.setTextTertiary)
                        .padding(.horizontal, SETSpacing.x4)
                        .padding(.vertical, SETSpacing.x3)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $viewModel.sceneDescription)
                    .font(SETTypography.font(.screenplay, size: SETTypographySize.body))
                    .foregroundStyle(.setTextPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, SETSpacing.x3)
                    .padding(.vertical, SETSpacing.x2)
                    .padding(.bottom, SETSpacing.x12)
                    .focused($isTextFieldFocused)
                    .accessibilityIdentifier("generator_input_editor")

                // Paste stays an inline affordance tied to the field.
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            if let clipboardText = UIPasteboard.general.string, !clipboardText.isEmpty {
                                if !viewModel.sceneDescription.isEmpty && !viewModel.sceneDescription.hasSuffix(" ") {
                                    viewModel.sceneDescription += " "
                                }
                                viewModel.sceneDescription += clipboardText
                            }
                        } label: {
                            Text(SETCopyKey.generatorInputPaste.localizedTextKey)
                                .font(SETTypography.font(.hudMono, size: SETTypographySize.micro))
                                .tracking(0.45)
                                .foregroundStyle(.setTextSecondary)
                                .padding(.horizontal, SETSpacing.x3)
                                .padding(.vertical, SETSpacing.x2)
                                .frame(minWidth: SETComponentMetric.minimumHitTarget,
                                       minHeight: SETComponentMetric.minimumHitTarget)
                                .background(Color.setHUDScrim)
                                .overlay {
                                    Capsule().stroke(.setHairline, lineWidth: SETStroke.hairline)
                                }
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, SETSpacing.x3)
                        .padding(.bottom, SETSpacing.x3)
                        .accessibilityIdentifier("generator_input_paste")
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 200)
            .background(Color.setSurfaceSolid)
            .overlay {
                Rectangle().stroke(
                    isTextFieldFocused && viewModel.inputValidationMessage == nil
                        ? Color.setOrange
                        : Color.setHairline,
                    lineWidth: isTextFieldFocused && viewModel.inputValidationMessage == nil
                        ? SETStroke.standard
                        : SETStroke.hairline
                )
            }

            if let inputValidationMessage = viewModel.inputValidationMessage {
                VStack(alignment: .leading, spacing: SETSpacing.x1) {
                    Text(inputValidationMessage)
                        .font(SETTypography.scaledFont(.hudMono, size: SETTypographySize.label, relativeTo: .callout))
                        .foregroundStyle(.setTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("generator_input_validation")
                    Rectangle()
                        .fill(Color.setOrange)
                        .frame(height: SETStroke.standard)
                }
            }
        }
    }

    // MARK: - Marked objects

    private var markedObjectsSection: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x2) {
            Text(SETCopyKey.generatorInputMarked.localizedTextKey)
                .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                .tracking(0.65)
                .foregroundStyle(.setTextSecondary)

            FlowLayout(spacing: SETSpacing.x2) {
                ForEach(viewModel.markedObjects) { marker in
                    SceneObjectChip(
                        label: marker.name,
                        isActive: true,
                        onTap: {
                            if !viewModel.sceneDescription.isEmpty && !viewModel.sceneDescription.hasSuffix(" ") {
                                viewModel.sceneDescription += " "
                            }
                            viewModel.sceneDescription += marker.name
                        }
                    )
                }
            }
        }
        .padding(SETSpacing.x3)
        .background(Color.setSurfaceSolid)
        .overlay {
            Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline)
        }
    }

    // MARK: - Detected objects

    private var detectedObjectsSection: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x2) {
            Text(SETCopyKey.generatorInputDetected.localizedTextKey)
                .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                .tracking(0.65)
                .foregroundStyle(.setTextSecondary)

            FlowLayout(spacing: SETSpacing.x2) {
                ForEach(viewModel.detectedObjects.prefix(8)) { object in
                    SceneObjectChip(
                        label: KeywordsMapping.cocoToRussian[object.label] ?? object.label,
                        isActive: false,
                        onTap: {
                            let objectName = KeywordsMapping.cocoToRussian[object.label] ?? object.label
                            if !viewModel.sceneDescription.isEmpty && !viewModel.sceneDescription.hasSuffix(" ") {
                                viewModel.sceneDescription += " "
                            }
                            viewModel.sceneDescription += objectName
                        }
                    )
                }
            }
        }
        .padding(SETSpacing.x3)
        .background(Color.setSurfaceSolid)
        .overlay {
            Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline)
        }
    }

    // MARK: - Generate command

    private var generateButton: some View {
        VStack(spacing: 0) {
            // Registration is the entry annotation; the focused field or
            // eligible action edge supplies the single cinematic accent.
            // Keep the command boundary neutral so accents never stack.
            Rectangle()
                .fill(.setHairline)
                .frame(height: SETStroke.hairline)

            HStack {
                SETDigitalAction(
                    title: viewModel.isGenerating ? .generatorInputGenerating : .generatorAction,
                    helper: viewModel.isGenerating ? nil : .generatorHelper,
                    showsAccentEdge: shouldShowGenerateAccent,
                    action: {
                        isTextFieldFocused = false
                        Task {
                            await viewModel.generateScene()
                        }
                    }
                )
                .disabled(viewModel.sceneDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isGenerating)
                .opacity(viewModel.sceneDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                .accessibilityIdentifier("generator_input_generate")
            }
            .padding(.horizontal, SETSpacing.x4)
            .padding(.vertical, SETSpacing.x3)
            .background(Color.setInk)
        }
    }

    private var shouldShowGenerateAccent: Bool {
        viewModel.inputValidationMessage == nil
            && !isTextFieldFocused
            && !viewModel.sceneDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.isGenerating
    }
}

// MARK: - Object chip

/// One flat object chip: active chips use a heavier warm-white edge while
/// inactive chips stay on the neutral hairline, never introducing another
/// cinematic accent.
struct SceneObjectChip: View {
    let label: String
    var isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label.capitalized)
                .font(SETTypography.uiBodyFont(weight: .semibold))
                .foregroundStyle(isActive ? Color.setTextPrimary : Color.setTextSecondary)
                .padding(.horizontal, SETSpacing.x3)
                .padding(.vertical, SETSpacing.x2)
                .frame(minWidth: SETComponentMetric.minimumHitTarget,
                       minHeight: SETComponentMetric.minimumHitTarget)
                .background(Color.setSurfaceSolid)
                .overlay {
                    Capsule().stroke(
                        isActive ? Color.setWarmWhite : Color.setHairline,
                        lineWidth: isActive ? SETStroke.standard : SETStroke.hairline
                    )
                }
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            if index < result.positions.count {
                let position = result.positions[index]
                subview.place(
                    at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                    proposal: ProposedViewSize(subview.sizeThatFits(.unspecified))
                )
            }
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))

            currentX += size.width + spacing
            maxX = max(maxX, currentX)
            lineHeight = max(lineHeight, size.height)
        }

        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}

// MARK: - Preview

#if DEBUG
struct SceneInputSheet_Previews: PreviewProvider {
    static var previews: some View {
        SceneInputSheet(viewModel: SceneGeneratorViewModel())
    }
}
#endif
