//
//  ARSceneContainer.swift
//  shafinMultitool
//
//  Created on 30.11.2025.
//

import SwiftUI
import ARKit
import RealityKit
import CoreVideo

/// UIViewRepresentable обёртка для ARView в Scene Generator
struct ARSceneContainer: UIViewRepresentable {
    
    @ObservedObject var viewModel: SceneGeneratorViewModel
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Избегаем двойной автоконфигурации ARView (она может увеличивать нагрузку)
        arView.automaticallyConfigureSession = false
        arView.session.delegate = context.coordinator
        context.coordinator.updateSessionState(
            for: arView,
            depthEnabled: viewModel.isMarkingMode,
            isGenerating: viewModel.isGenerating,
            force: true
        )
        
        // Настройки рендеринга
        arView.renderOptions = [.disableMotionBlur]
        
        // Добавляем coaching overlay для помощи пользователю
        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.session = arView.session
        coachingOverlay.goal = .horizontalPlane
        coachingOverlay.activatesAutomatically = true
        coachingOverlay.translatesAutoresizingMaskIntoConstraints = false
        arView.addSubview(coachingOverlay)
        
        NSLayoutConstraint.activate([
            coachingOverlay.topAnchor.constraint(equalTo: arView.topAnchor),
            coachingOverlay.leadingAnchor.constraint(equalTo: arView.leadingAnchor),
            coachingOverlay.trailingAnchor.constraint(equalTo: arView.trailingAnchor),
            coachingOverlay.bottomAnchor.constraint(equalTo: arView.bottomAnchor)
        ])
        
        // Сохраняем ссылку на ARView в ViewModel
        DispatchQueue.main.async {
            viewModel.arView = arView
        }
        
        // Добавляем жест для отладки
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Во время генерации приостанавливаем AR-сессию, чтобы не греть устройство параллельно с LLM.
        context.coordinator.updateSessionState(
            for: uiView,
            depthEnabled: viewModel.isMarkingMode,
            isGenerating: viewModel.isGenerating
        )
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.pause()
        uiView.session.delegate = nil
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, ARSessionDelegate {
        
        let viewModel: SceneGeneratorViewModel
        private var isDepthEnabled: Bool?
        private var isSessionPausedForGeneration = false
        private var lastProcessedFrameTimestamp: TimeInterval = 0
        private let frameProcessingInterval: TimeInterval = 1.0 / 15.0
        
        init(viewModel: SceneGeneratorViewModel) {
            self.viewModel = viewModel
        }

        func updateSessionState(for arView: ARView, depthEnabled: Bool, isGenerating: Bool, force: Bool = false) {
            if isGenerating {
                pauseSessionIfNeeded(for: arView)
                return
            }

            if isSessionPausedForGeneration {
                resumeSessionIfNeeded(for: arView, depthEnabled: depthEnabled)
                return
            }

            configureSessionIfNeeded(for: arView, depthEnabled: depthEnabled, force: force)
        }

        func configureSessionIfNeeded(for arView: ARView, depthEnabled: Bool, force: Bool = false) {
            guard !isSessionPausedForGeneration else { return }

            if !force, isDepthEnabled == depthEnabled {
                return
            }

            let configuration = makeConfiguration(depthEnabled: depthEnabled)
            arView.session.run(configuration)
            isDepthEnabled = depthEnabled
        }

        private func pauseSessionIfNeeded(for arView: ARView) {
            guard !isSessionPausedForGeneration else { return }
            arView.session.pause()
            isSessionPausedForGeneration = true
        }

        private func resumeSessionIfNeeded(for arView: ARView, depthEnabled: Bool) {
            guard isSessionPausedForGeneration else { return }
            let configuration = makeConfiguration(depthEnabled: depthEnabled)
            arView.session.run(configuration)
            isDepthEnabled = depthEnabled
            isSessionPausedForGeneration = false
            lastProcessedFrameTimestamp = 0
        }

        private func makeConfiguration(depthEnabled: Bool) -> ARWorldTrackingConfiguration {
            let configuration = ARWorldTrackingConfiguration()

            // Для Scene Generator достаточно горизонтальных плоскостей — это дешевле по CPU/GPU.
            configuration.planeDetection = [.horizontal]
            configuration.environmentTexturing = .none

            if depthEnabled {
                if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
                    configuration.frameSemantics.insert(.smoothedSceneDepth)
                } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                    configuration.frameSemantics.insert(.sceneDepth)
                }
            }

            return configuration
        }
        
        // MARK: - ARSessionDelegate
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard !isSessionPausedForGeneration else { return }
            guard !viewModel.isGenerating else { return }

            // processARFrame не требует 60 вызовов/сек — ограничиваем до ~15 Гц.
            let timestamp = frame.timestamp
            guard timestamp - lastProcessedFrameTimestamp >= frameProcessingInterval else { return }
            lastProcessedFrameTimestamp = timestamp

            let cameraTransform = frame.camera.transform
            let cameraIntrinsics = frame.camera.intrinsics
            let imageResolution = frame.camera.imageResolution
            let planeAnchors = frame.anchors.compactMap { $0 as? ARPlaneAnchor }
            let depthMap: CVPixelBuffer?
            if viewModel.isMarkingMode {
                depthMap = (frame.smoothedSceneDepth ?? frame.sceneDepth)?.depthMap
            } else {
                depthMap = nil
            }

            Task { @MainActor in
                viewModel.processARFrameSnapshot(
                    cameraTransform: cameraTransform,
                    depthMap: depthMap,
                    intrinsics: cameraIntrinsics,
                    imageResolution: imageResolution,
                    planeAnchors: planeAnchors,
                    timestamp: timestamp
                )
            }
        }
        
        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            // Плоскость обнаружена - обновление происходит через processARFrame
        }
        
        func session(_ session: ARSession, didFailWithError error: Error) {
            Task { @MainActor in
                viewModel.errorMessage = "Ошибка AR: \(error.localizedDescription)"
            }
        }
        
        func sessionWasInterrupted(_ session: ARSession) {
            // Сессия прервана
        }
        
        func sessionInterruptionEnded(_ session: ARSession) {
            // Сессия возобновлена
        }
        
        // MARK: - Gestures
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = gesture.view as? ARView else { return }
            let location = gesture.location(in: arView)
            
            Task { @MainActor in
                // Если включен режим разметки - создаём маркер
                if viewModel.isMarkingMode {
                    viewModel.handleTapForMarker(at: location)
                    return
                }
                
                // Иначе - проверяем попадание по объекту
                if let _ = arView.entity(at: location) {
                    // Можно добавить выделение или другую логику
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ARSceneContainer_Previews: PreviewProvider {
    static var previews: some View {
        ARSceneContainer(viewModel: SceneGeneratorViewModel())
            .ignoresSafeArea()
    }
}
#endif
