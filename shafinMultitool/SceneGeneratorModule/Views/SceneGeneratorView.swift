//
//  SceneGeneratorView.swift
//  shafinMultitool
//
//  Created on 30.11.2025.
//

import SwiftUI

/// Главный экран генератора сцен
struct SceneGeneratorView: View {
    
    @StateObject private var viewModel = SceneGeneratorViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // AR Camera View
            ARSceneContainer(viewModel: viewModel)
                .ignoresSafeArea()
            
            // Overlay UI
            VStack {
                // Top bar
                topBar
                
                Spacer()
                
                // Marked objects badges (user-defined)
                if !viewModel.markedObjects.isEmpty {
                    markedObjectsBadges
                }
                
                // Detected objects badges
                if !viewModel.detectedObjects.isEmpty {
                    detectedObjectsBadges
                }
                
                // Status message
                statusBar
                
                // Bottom controls
                bottomControls
            }
            .padding()
            
            // Marking mode overlay
            if viewModel.isMarkingMode {
                markingModeOverlay
            }
            
            // Loading overlay
            if viewModel.isGenerating {
                loadingOverlay
            }
        }
        .sheet(isPresented: $viewModel.showInputSheet) {
            SceneInputSheet(viewModel: viewModel)
        }
        .alert("Ошибка", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $viewModel.showMarkerNameInput) {
            MarkerNameInputSheet(viewModel: viewModel)
                .presentationDetents([.height(220)])
                .presentationDragIndicator(.visible)
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack {
            // Back button
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.8))
            }
            
            Spacer()
            
            // Title
            VStack(alignment: .center, spacing: 2) {
                Text("Scene Generator")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                if viewModel.parsedScript != nil {
                    Text("\(viewModel.parsedScript?.actors.count ?? 0) актёров")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            Spacer()
            
            // Reset button
            Button(action: { viewModel.resetScene() }) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .opacity(viewModel.plannedScene != nil ? 1 : 0.3)
            .disabled(viewModel.plannedScene == nil)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.6), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    // MARK: - Detected Objects Badges
    
    private var detectedObjectsBadges: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.detectedObjects.prefix(5)) { object in
                    DetectedObjectBadge(
                        label: KeywordsMapping.cocoToRussian[object.label] ?? object.label,
                        confidence: object.confidence,
                        isMatched: viewModel.parsedScript?.objects.contains { 
                            $0.type.cocoLabels.contains(object.label) 
                        } ?? false
                    )
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 36)
    }
    
    // MARK: - Marked Objects Badges
    
    private var markedObjectsBadges: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Заголовок
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.green)
                    Text("Мои объекты:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                ForEach(viewModel.markedObjects) { marker in
                    MarkedObjectBadge(
                        marker: marker,
                        onRemove: {
                            viewModel.removeMarker(marker)
                        }
                    )
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 36)
    }
    
    // MARK: - Status Bar
    
    private var statusBar: some View {
        HStack {
            // AR status indicator
            Circle()
                .fill(viewModel.isARSessionReady ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            
            Text(viewModel.statusMessage)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.5))
        )
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    // MARK: - Bottom Controls
    
    private var bottomControls: some View {
        HStack(spacing: 16) {
            // Marking mode button
            Button(action: { viewModel.toggleMarkingMode() }) {
                ZStack {
                    Circle()
                        .fill(viewModel.isMarkingMode ? Color.green : Color.white.opacity(0.2))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 20))
                        .foregroundColor(viewModel.isMarkingMode ? .white : .white.opacity(0.8))
                }
            }
            .shadow(color: viewModel.isMarkingMode ? Color.green.opacity(0.5) : .clear, radius: 8)
            
            // Scene info (if generated)
            if let script = viewModel.parsedScript {
                sceneInfoButton(script: script)
            }
            
            Spacer()
            
            // Play/Stop button
            if viewModel.plannedScene != nil {
                Button(action: {
                    if viewModel.isPlaying {
                        viewModel.stopScene()
                    } else {
                        viewModel.playScene()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(viewModel.isPlaying ? Color.red : Color.green)
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: viewModel.isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }
                }
                .shadow(color: (viewModel.isPlaying ? Color.red : Color.green).opacity(0.5), radius: 10)
            }
            
            Spacer()
            
            // Add scene button
            Button(action: { viewModel.showInput() }) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 70, height: 70)
                    
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .shadow(color: Color.purple.opacity(0.5), radius: 15)
            .disabled(!viewModel.isARSessionReady || viewModel.isGenerating || viewModel.isMarkingMode)
            .opacity(viewModel.isARSessionReady && !viewModel.isMarkingMode ? 1 : 0.5)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
    
    private func sceneInfoButton(script: SceneScript) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 12))
                Text("\(script.actors.count)")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            
            if !script.objects.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "cube.fill")
                        .font(.system(size: 12))
                    Text("\(script.objects.count)")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.5))
        )
    }
    
    // MARK: - Loading Overlay
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                
                Text(viewModel.statusMessage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.8))
            )
        }
    }
    
    // MARK: - Marking Mode Overlay
    
    private var markingModeOverlay: some View {
        VStack {
            // Top hint
            HStack {
                Spacer()
                
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill")
                        .foregroundColor(.green)
                    Text("Тапните на объект для разметки")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.3))
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.green.opacity(0.5), lineWidth: 1)
                        )
                )
                
                Spacer()
            }
            .padding(.top, 80)
            
            Spacer()
            
            // Cancel button
            Button(action: { viewModel.toggleMarkingMode() }) {
                Text("Отмена")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.red.opacity(0.8))
                    )
            }
            .padding(.bottom, 100)
        }
    }
}

// MARK: - Detected Object Badge

struct DetectedObjectBadge: View {
    let label: String
    let confidence: Float
    let isMatched: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isMatched ? Color.green : Color.blue)
                .frame(width: 6, height: 6)
            
            Text(label.capitalized)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
            
            Text("\(Int(confidence * 100))%")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.5))
                .overlay(
                    Capsule()
                        .strokeBorder(isMatched ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        )
    }
}

// MARK: - Marked Object Badge

struct MarkedObjectBadge: View {
    let marker: MarkedObject
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "mappin.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 12))
            
            Text(marker.name.capitalized)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.green.opacity(0.2))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.green.opacity(0.5), lineWidth: 1)
                )
        )
    }
}

// MARK: - Marker Name Input Sheet

struct MarkerNameInputSheet: View {
    @ObservedObject var viewModel: SceneGeneratorViewModel
    @State private var markerName: String = ""
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Как назвать объект?")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("Например: шкаф, стол, телевизор. Название помогает распознавать объект в описании.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                
                TextField("Шкаф", text: $markerName)
                    .textFieldStyle(.roundedBorder)
                
                Spacer()
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.08, blue: 0.15), Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Новый объект")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        viewModel.cancelMarkerCreation()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
                        viewModel.createMarker(withName: markerName)
                        markerName = ""
                    }
                    .disabled(markerName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onDisappear {
            if viewModel.pendingMarkerPosition != nil {
                viewModel.cancelMarkerCreation()
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SceneGeneratorView_Previews: PreviewProvider {
    static var previews: some View {
        SceneGeneratorView()
    }
}
#endif

