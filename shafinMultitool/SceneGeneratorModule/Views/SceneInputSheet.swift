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
    
    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            
            NavigationView {
                ZStack {
                    // Background
                    LinearGradient(
                        colors: [
                            Color(red: 0.05, green: 0.05, blue: 0.12),
                            Color.black
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                    
                    if isLandscape {
                        landscapeLayout
                    } else {
                        portraitLayout
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Отмена") {
                            dismiss()
                        }
                        .foregroundColor(.white.opacity(0.8))
                    }
                    
                    // Кнопка скрытия клавиатуры — появляется только когда клавиатура открыта
                    if isTextFieldFocused {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                isTextFieldFocused = false
                            } label: {
                                Image(systemName: "keyboard.chevron.compact.down")
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
    
    // MARK: - Portrait Layout
    
    private var portraitLayout: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    textInputSection
                    if !viewModel.markedObjects.isEmpty { markedObjectsSection }
                    if !viewModel.detectedObjects.isEmpty { detectedObjectsSection }
                    examplesSection
                    if let result = viewModel.parsingResult { diagnosticsSection(result: result) }
                    Spacer(minLength: 100)
                }
                .padding()
            }
            generateButton
        }
    }
    
    // MARK: - Landscape Layout
    
    private var landscapeLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            // Левая колонка: ввод + кнопка генерации
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerSection
                        textInputSection
                        Spacer(minLength: 80)
                    }
                    .padding()
                }
                generateButton
            }
            .frame(maxWidth: .infinity)
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Правая колонка: объекты + примеры
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !viewModel.markedObjects.isEmpty { markedObjectsSection }
                    if !viewModel.detectedObjects.isEmpty { detectedObjectsSection }
                    examplesSection
                    if let result = viewModel.parsingResult { diagnosticsSection(result: result) }
                    Spacer(minLength: 16)
                }
                .padding()
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Создание сцены")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Text("Опишите сцену текстом, и она будет создана в AR")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.7))
        }
    }
    
    // MARK: - Text Input Section
    
    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Описание сцены")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            
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
                            .foregroundColor(.blue.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.blue.opacity(0.15))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
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
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                isTextFieldFocused ? Color.blue.opacity(0.5) : Color.white.opacity(0.1),
                                lineWidth: 1
                            )
                    )
            )
            
            // Character count
            HStack {
                Spacer()
                Text("\(viewModel.sceneDescription.count) символов")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
            }
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
                    .foregroundColor(.white.opacity(0.6))
                
                Spacer()
                
                Text("Высший приоритет")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.green.opacity(0.2))
                    )
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
            
            Text("Эти объекты привязаны к реальным позициям в пространстве")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.green.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.green.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Detected Objects Section
    
    private var detectedObjectsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "eye.fill")
                    .foregroundColor(.blue)
                Text("Обнаруженные объекты")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
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
            
            Text("Нажмите на объект, чтобы добавить в описание")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.blue.opacity(0.1))
        )
    }
    
    // MARK: - Diagnostics Section
    
    private func diagnosticsSection(result: ParsingResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: result.diagnostics.confidence >= 0.6 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(result.diagnostics.confidence >= 0.6 ? .green : .orange)
                Text("Качество парсинга")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                
                Spacer()
                
                Text("\(Int(result.diagnostics.confidence * 100))%")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(result.diagnostics.confidence >= 0.6 ? .green : .orange)
            }
            
            // Покрытие текста
            if result.diagnostics.coverage > 0 {
                HStack {
                    Text("Покрытие текста:")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    Text("\(Int(result.diagnostics.coverage * 100))%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            // Распознанные размеченные объекты
            if !result.diagnostics.matchedMarkedObjects.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 10))
                    Text("Распознано размеченных объектов: \(result.diagnostics.matchedMarkedObjects.count)")
                        .font(.system(size: 12))
                        .foregroundColor(.green.opacity(0.8))
                }
            }
            
            // Предупреждения
            if !result.diagnostics.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(result.diagnostics.notes, id: \.self) { note in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 10))
                            Text(note)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(result.diagnostics.confidence >= 0.6 
                      ? Color.green.opacity(0.1)
                      : Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            result.diagnostics.confidence >= 0.6 
                            ? Color.green.opacity(0.3) 
                            : Color.orange.opacity(0.3),
                            lineWidth: 1
                        )
                )
        )
    }
    
    // MARK: - Examples Section
    
    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Примеры")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
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
            // Gradient fade
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)
            
            // Button container
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
                                .tint(.white)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        
                        Text(viewModel.isGenerating ? "Создаю..." : "Создать сцену")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: viewModel.sceneDescription.isEmpty 
                                ? [Color.gray.opacity(0.5), Color.gray.opacity(0.3)]
                                : [Color.blue, Color.purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(
                        color: viewModel.sceneDescription.isEmpty ? .clear : Color.purple.opacity(0.4),
                        radius: 15,
                        y: 5
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
                    .foregroundColor(isRecognized ? .blue : .green)
                
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
                    .fill(isRecognized ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
                    .overlay(
                        Capsule()
                            .strokeBorder(isRecognized ? Color.blue.opacity(0.5) : Color.green.opacity(0.5), lineWidth: 1)
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
                    .foregroundColor(.blue)
                
                Text(label.capitalized)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
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
                    .fill(Color.white.opacity(isPressed ? 0.15 : 0.05))
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

