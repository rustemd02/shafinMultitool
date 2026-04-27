//
//  SceneInputSheet.swift
//  shafinMultitool
//
//  Created on 30.11.2025.
//

import SwiftUI

/// Модальное окно для ввода описания сцены
struct SceneInputSheet: View {
    
    @ObservedObject var viewModel: SceneGeneratorViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool
    
    private let panelFill = Color.white.opacity(0.08)
    private let panelBorder = Color.white.opacity(0.14)
    private let secondaryText = Color.white.opacity(0.62)
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                portraitLayout
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                if isTextFieldFocused {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            isTextFieldFocused = false
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Portrait Layout
    
    private var portraitLayout: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection
                    if !viewModel.markedObjects.isEmpty { markedObjectsSection }
                    textInputSection
                    examplesSection
                    if !viewModel.detectedObjects.isEmpty { detectedObjectsSection }
                    Spacer(minLength: 100)
                }
                .padding()
            }
            generateButton
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack {
            Image(systemName: "text.bubble")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
            
            Text("Создание сцены")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Text Input Section
    
    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Описание сцены")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(secondaryText)
            
            ZStack(alignment: .topLeading) {
                // Placeholder
                if viewModel.sceneDescription.isEmpty {
                    Text("Например: 2 актёра идут навстречу друг другу, проходят мимо шкафа...")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                }
                
                // Text editor
                TextEditor(text: $viewModel.sceneDescription)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .padding(.bottom, 36) // место под кнопку Вставить
                    .focused($isTextFieldFocused)
                
                // Кнопка «Вставить» — в правом нижнем углу поля
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
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 11))
                                Text("Вставить")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(panelBorder, lineWidth: 1)
                                    )
                            )
                        }
                        .padding(.trailing, 10)
                        .padding(.bottom, 8)
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 200)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(panelFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                isTextFieldFocused ? Color.white.opacity(0.35) : panelBorder,
                                lineWidth: 1
                            )
                    )
            )
            
        }
    }
    
    // MARK: - Marked Objects Section (User-defined)
    
    private var markedObjectsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.green)
                Text("Мои объекты (реальные)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(secondaryText)
            }
            
            FlowLayout(spacing: 8) {
                ForEach(viewModel.markedObjects) { marker in
                    MarkedObjectChip(
                        marker: marker,
                        isRecognized: viewModel.parsingResult?.diagnostics.matchedMarkedObjects.contains(marker.id) ?? false,
                        onTap: {
                            // Добавляем объект в описание
                            if !viewModel.sceneDescription.isEmpty && !viewModel.sceneDescription.hasSuffix(" ") {
                                viewModel.sceneDescription += " "
                            }
                            viewModel.sceneDescription += marker.name
                        }
                    )
                }
            }
            
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.green.opacity(0.42), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Detected Objects Section
    
    private var detectedObjectsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "eye.fill")
                    .foregroundColor(.white)
                Text("Обнаруженные объекты")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(secondaryText)
            }
            
            FlowLayout(spacing: 8) {
                ForEach(viewModel.detectedObjects.prefix(8)) { object in
                    DetectedObjectChip(
                        label: KeywordsMapping.cocoToRussian[object.label] ?? object.label,
                        onTap: {
                            // Добавляем объект в описание
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
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(panelBorder, lineWidth: 1)
                )
        )
    }
    
    // MARK: - Examples Section
    
    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.white)
                Text("Примеры")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(secondaryText)
            }
            
            VStack(spacing: 8) {
                ForEach(SceneGeneratorViewModel.exampleDescriptions, id: \.title) { example in
                    ExampleButton(
                        title: example.title,
                        description: example.description,
                        onTap: {
                            viewModel.sceneDescription = example.description
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Generate Button
    
    private var generateButton: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)
            
            HStack {
                Button(action: {
                    isTextFieldFocused = false
                    Task {
                        await viewModel.generateScene()
                    }
                }) {
                    HStack(spacing: 12) {
                        if viewModel.isGenerating {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        
                        Text(viewModel.isGenerating ? "Создаю..." : "Создать сцену")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(
                        viewModel.sceneDescription.isEmpty ? Color.white.opacity(0.5) : .black
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                viewModel.sceneDescription.isEmpty
                                ? Color.white.opacity(0.16)
                                : Color.white
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(panelBorder, lineWidth: 1)
                            )
                    )
                }
                .disabled(viewModel.sceneDescription.isEmpty || viewModel.isGenerating)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .background(Color.black.opacity(0.9))
        }
    }
}

// MARK: - Marked Object Chip (User-defined)

struct MarkedObjectChip: View {
    let marker: MarkedObject
    let isRecognized: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: isRecognized ? "checkmark.circle.fill" : "mappin.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(isRecognized ? .white : .green)
                
                Text(marker.name.capitalized)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
                if !isRecognized {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.45))
                    .overlay(
                        Capsule().strokeBorder(
                            isRecognized ? Color.white.opacity(0.28) : Color.green.opacity(0.5),
                            lineWidth: 1
                        )
                    )
            )
        }
    }
}

// MARK: - Detected Object Chip

struct DetectedObjectChip: View {
    let label: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                
                Text(label.capitalized)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.45))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
        }
    }
}

// MARK: - Example Button

struct ExampleButton: View {
    let title: String
    let description: String
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(description)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(isPressed ? 0.55 : 0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PressableButtonStyle(isPressed: $isPressed))
    }
}

// MARK: - Pressable Button Style

struct PressableButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { newValue in
                isPressed = newValue
            }
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
