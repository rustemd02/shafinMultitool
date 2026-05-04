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
    
    private let panelFill = Color.black.opacity(0.55)
    private let panelStroke = Color.white.opacity(0.14)
    private let panelStrongFill = Color.black.opacity(0.72)
    private let primaryControlFill = Color.white.opacity(0.2)
    private let secondaryTextColor = Color.white.opacity(0.74)
    
    var body: some View {
        ZStack {
            // AR Camera View
            ARSceneContainer(viewModel: viewModel)
                .ignoresSafeArea()
            
            // Overlay UI
            VStack {
                // Top bar
                if viewModel.isPlaying {
                    playbackTimeline
                    if let screenText = viewModel.activeScreenTextCaption {
                        playbackScreenTextOverlay(screenText)
                    }
                } else {
                    topBar
                }
                
                Spacer()

                if let actionCaption = viewModel.activeActionCaption {
                    playbackActionCaption(actionCaption)
                }

                if let dialogueCaption = viewModel.activeDialogueCaption {
                    playbackDialogueCaption(dialogueCaption)
                }

                if viewModel.isPlaying {
                    playbackStopControl
                } else {
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

    private var playbackTimeline: some View {
        HStack(spacing: 6) {
            ForEach(viewModel.beatTimelineItems) { item in
                beatTimelineSegment(item)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.46))
                .overlay(
                    Capsule()
                        .stroke(panelStroke, lineWidth: 1)
                )
        )
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    private func beatTimelineSegment(_ item: BeatPlaybackTimelineItem) -> some View {
        let isPast = item.index < viewModel.activeBeatIndex
        let isActive = item.index == viewModel.activeBeatIndex
        let progress = isPast ? 1 : (isActive ? viewModel.beatProgress : 0)

        return VStack(spacing: 4) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(isActive ? 0.22 : 0.12))

                GeometryReader { proxy in
                    Capsule()
                        .fill(isActive ? Color.green : Color.white.opacity(0.72))
                        .frame(width: max(0, proxy.size.width * progress))
                }
                .clipShape(Capsule())
            }
            .frame(width: isActive ? 72 : 28, height: isActive ? 7 : 5)
            .animation(.easeInOut(duration: 0.2), value: isActive)

            HStack(spacing: 3) {
                if item.hasDialogueCaption {
                    Image(systemName: "bubble.left.fill")
                }
                if item.hasActionCaption {
                    Image(systemName: "sparkles")
                }
            }
            .font(.system(size: 7, weight: .bold))
            .foregroundColor(.white.opacity(isActive ? 0.95 : 0.45))
            .frame(height: 8)
        }
        .accessibilityLabel("Beat \(item.index + 1)")
    }

    private func playbackScreenTextOverlay(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.58))
                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
            )
            .padding(.top, 6)
            .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func playbackDialogueCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(panelStrongFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(panelStroke, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func playbackActionCaption(_ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))

            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .foregroundColor(.white.opacity(0.94))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 310)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.56))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
        )
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(primaryControlFill)
                            .overlay(
                                Circle().stroke(panelStroke, lineWidth: 1)
                            )
                    )
            }
            
            Spacer()
            
            VStack(alignment: .center, spacing: 2) {
                Text("Генератор сцен")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                
                if viewModel.parsedScript != nil {
                    Text("\(viewModel.parsedScript?.actors.count ?? 0) актёров")
                    .font(.system(size: 12))
                        .foregroundColor(secondaryTextColor)
                }
            }
            
            Spacer()
            
            Button(action: { viewModel.resetScene() }) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(primaryControlFill)
                            .overlay(
                                Circle().stroke(panelStroke, lineWidth: 1)
                            )
                    )
            }
            .opacity(viewModel.plannedScene != nil ? 1 : 0.3)
            .disabled(viewModel.plannedScene == nil)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(panelFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(panelStroke, lineWidth: 1)
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
                        .foregroundColor(.green.opacity(0.85))
                    Text("Мои объекты:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(secondaryTextColor)
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
                .foregroundColor(.white)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 13)
                .fill(panelFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(panelStroke, lineWidth: 1)
                )
        )
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    // MARK: - Bottom Controls

    private var playbackStopControl: some View {
        Button(action: { viewModel.stopScene() }) {
            HStack(spacing: 8) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 13, weight: .bold))
                Text("Стоп")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(panelFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.red.opacity(0.45), lineWidth: 1)
                    )
            )
        }
        .padding(.bottom, 16)
    }
    
    private var bottomControls: some View {
        HStack(spacing: 16) {
            Button(action: { viewModel.toggleMarkingMode() }) {
                ZStack {
                    Circle()
                        .fill(viewModel.isMarkingMode ? Color.green : primaryControlFill)
                        .frame(width: 54, height: 54)
                        .overlay(
                            Circle().stroke(panelStroke, lineWidth: 1)
                        )
                    
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            
            if let script = viewModel.parsedScript {
                sceneInfoButton(script: script)
            }
            
            Spacer()
            
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
                            .fill(viewModel.isPlaying ? Color.red : Color.white)
                            .frame(width: 62, height: 62)
                            .overlay(
                                Circle().stroke(panelStroke, lineWidth: 1)
                            )
                        
                        Image(systemName: viewModel.isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(viewModel.isPlaying ? .white : .black)
                    }
                }
            }
            
            Spacer()
            
            Button(action: { viewModel.showInput() }) {
                ZStack {
                    Circle()
                        .fill(viewModel.isARSessionReady && !viewModel.isMarkingMode ? Color.white : Color.gray.opacity(0.5))
                        .frame(width: 66, height: 66)
                        .overlay(
                            Circle().stroke(panelStroke, lineWidth: 1)
                        )
                    
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.black)
                }
            }
            .disabled(!viewModel.isARSessionReady || viewModel.isGenerating || viewModel.isMarkingMode)
            .opacity(viewModel.isARSessionReady && !viewModel.isMarkingMode ? 1 : 0.5)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
    
    private func sceneInfoButton(script: SceneScript) -> some View {
        return VStack(alignment: .leading, spacing: 4) {
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
                .fill(panelFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(panelStroke, lineWidth: 1)
                )
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
                    .fill(panelStrongFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(panelStroke, lineWidth: 1)
                    )
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
                        .foregroundColor(.green.opacity(0.9))
                    Text("Тапните на объект для разметки")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(panelFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.green.opacity(0.55), lineWidth: 1)
                        )
                )
                
                Spacer()
            }
            .padding(.top, 80)
            
            Spacer()
            
            // Cancel button
            Button(action: { viewModel.toggleMarkingMode() }) {
                Text("Отмена")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white)
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
                .fill(isMatched ? Color.green : Color.white.opacity(0.7))
                .frame(width: 6, height: 6)
            
            Text(label.capitalized)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
            
            Text("\(Int(confidence * 100))%")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.62))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.45))
                .overlay(
                    Capsule()
                        .strokeBorder(isMatched ? Color.green.opacity(0.5) : Color.white.opacity(0.14), lineWidth: 1)
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
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.45))
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
                Color.black.ignoresSafeArea()
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
