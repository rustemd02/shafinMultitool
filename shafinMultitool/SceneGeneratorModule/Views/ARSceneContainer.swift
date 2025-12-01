//
//  ARSceneContainer.swift
//  shafinMultitool
//
//  Created on 30.11.2025.
//

import SwiftUI
import ARKit
import RealityKit

/// UIViewRepresentable обёртка для ARView в Scene Generator
struct ARSceneContainer: UIViewRepresentable {
    
    @ObservedObject var viewModel: SceneGeneratorViewModel
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // Конфигурация AR сессии
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        
        // Включаем LiDAR depth если доступно (для точного определения расстояния)
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        
        // Включаем smoothed scene depth для более стабильных измерений
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        }
        
        // Включаем people occlusion если доступно
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            configuration.frameSemantics.insert(.personSegmentationWithDepth)
        }
        
        arView.session.run(configuration)
        arView.session.delegate = context.coordinator
        
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
        // Обновления не требуются - всё управляется через ViewModel
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, ARSessionDelegate {
        
        let viewModel: SceneGeneratorViewModel
        
        init(viewModel: SceneGeneratorViewModel) {
            self.viewModel = viewModel
        }
        
        // MARK: - ARSessionDelegate
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // Передаём frame в ViewModel для обработки
            Task { @MainActor in
                viewModel.processARFrame(frame)
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

