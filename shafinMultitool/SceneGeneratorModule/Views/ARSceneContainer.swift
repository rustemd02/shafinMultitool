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
import UIKit

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
            configuration: viewModel.makeSessionConfiguration(depthEnabled: viewModel.isDepthMarkingEnabled),
            depthEnabled: viewModel.isDepthMarkingEnabled,
            isGenerating: viewModel.isGenerating,
            shouldForwardCapturedImage: viewModel.isRecording || viewModel.isHintsEnabled,
            isSceneGenerated: viewModel.plannedScene != nil,
            isARSessionReady: viewModel.isARSessionReady,
            force: true
        )
        
        // Настройки рендеринга
        arView.renderOptions = [
            .disableMotionBlur,
            .disableDepthOfField,
            .disableCameraGrain,
            .disablePersonOcclusion,
            .disableGroundingShadows,
            .disableHDR
        ]
        
        // Добавляем coaching overlay для помощи пользователю
        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.session = arView.session
        coachingOverlay.goal = .horizontalPlane
        coachingOverlay.activatesAutomatically = true
        coachingOverlay.translatesAutoresizingMaskIntoConstraints = false
        context.coordinator.coachingOverlay = coachingOverlay
        arView.addSubview(coachingOverlay)
        
        NSLayoutConstraint.activate([
            coachingOverlay.topAnchor.constraint(equalTo: arView.topAnchor),
            coachingOverlay.leadingAnchor.constraint(equalTo: arView.leadingAnchor),
            coachingOverlay.trailingAnchor.constraint(equalTo: arView.trailingAnchor),
            coachingOverlay.bottomAnchor.constraint(equalTo: arView.bottomAnchor)
        ])
        
        // Сохраняем ссылку на ARView в ViewModel
        DispatchQueue.main.async {
            viewModel.attachARView(arView)
        }
        
        // Добавляем жест для отладки
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)

        let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.35
        arView.addGestureRecognizer(longPressGesture)
        
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        MainActor.assumeIsolated {
            guard !viewModel.isWorkspaceReleased else {
                uiView.session.pause()
                uiView.session.delegate = nil
                return
            }
            context.coordinator.updateSessionState(
                for: uiView,
                configuration: viewModel.makeSessionConfiguration(depthEnabled: viewModel.isDepthMarkingEnabled),
                depthEnabled: viewModel.isDepthMarkingEnabled,
                isGenerating: viewModel.isGenerating,
                shouldForwardCapturedImage: viewModel.isRecording || viewModel.isHintsEnabled,
                isSceneGenerated: viewModel.plannedScene != nil,
                isARSessionReady: viewModel.isARSessionReady
            )
        }
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
        weak var coachingOverlay: ARCoachingOverlayView?
        private var isDepthEnabled = false
        private var isGenerationActive = false
        private var isSceneGenerated = false
        private var isSessionPausedForGeneration = false
        private var lastProcessedFrameTimestamp: TimeInterval = 0
        private var shouldForwardCapturedImage = false
        private let frameTaskLock = NSLock()
        private var frameTaskInFlight = false
        private var skippedFramesSinceLog = 0
        private var processedFramesSinceLog = 0
        private var lastFrameMetricsLogTimestamp: TimeInterval = 0
        private var lastTrackingStateDescription: String?
        private weak var arView: ARView?
        private var viewportSize: CGSize = .zero
        private var interfaceOrientation: UIInterfaceOrientation = .portrait
        private var lastCameraAnalysisGeometryLogTimestamp: TimeInterval = 0
        private var orientationObserver: NSObjectProtocol?
        private var isGeneratingOrientationNotifications = false
        private var frameProcessingInterval: TimeInterval {
            switch ProcessInfo.processInfo.thermalState {
            case .serious, .critical:
                return 1.0 / 5.0
            case .fair:
                return shouldForwardCapturedImage ? 1.0 / 12.0 : 1.0 / 8.0
            case .nominal:
                return shouldForwardCapturedImage ? 1.0 / 15.0 : (isSceneGenerated ? 1.0 / 8.0 : 1.0 / 10.0)
            @unknown default:
                return 1.0 / 8.0
            }
        }
        
        init(viewModel: SceneGeneratorViewModel) {
            self.viewModel = viewModel
            super.init()
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            isGeneratingOrientationNotifications = true
            orientationObserver = NotificationCenter.default.addObserver(
                forName: UIDevice.orientationDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleOrientationRefresh()
            }
        }

        deinit {
            if let orientationObserver {
                NotificationCenter.default.removeObserver(orientationObserver)
            }
            if isGeneratingOrientationNotifications {
                UIDevice.current.endGeneratingDeviceOrientationNotifications()
            }
        }

        func updateSessionState(for arView: ARView,
                                configuration: ARWorldTrackingConfiguration,
                                depthEnabled: Bool,
                                isGenerating: Bool,
                                shouldForwardCapturedImage: Bool,
                                isSceneGenerated: Bool,
                                isARSessionReady: Bool,
                                force: Bool = false) {
            self.arView = arView
            refreshOrientation(for: arView)
            self.shouldForwardCapturedImage = shouldForwardCapturedImage && !isGenerating
            self.isSceneGenerated = isSceneGenerated
            updateCoachingOverlay(isSceneGenerated: isSceneGenerated, isARSessionReady: isARSessionReady)
            if isGenerating {
                pauseSessionIfNeeded(for: arView)
                return
            }

            if isSessionPausedForGeneration {
                resumeSessionIfNeeded(for: arView, configuration: configuration, depthEnabled: depthEnabled)
                return
            }

            isGenerationActive = false
            configureSessionIfNeeded(for: arView, configuration: configuration, depthEnabled: depthEnabled, force: force)
        }

        private func scheduleOrientationRefresh() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let arView = self.arView else { return }
                self.refreshOrientation(for: arView)
            }
        }

        /// Refreshes only cached presentation geometry. Rotation never reruns
        /// or pauses the AR session, so world tracking and project state stay
        /// continuous while the display transform follows the new viewport.
        private func refreshOrientation(for arView: ARView) {
            viewportSize = arView.bounds.size
            if let orientation = Self.currentInterfaceOrientation(for: arView),
               orientation != .unknown {
                interfaceOrientation = orientation
            }
        }

        func configureSessionIfNeeded(for arView: ARView,
                                      configuration: ARWorldTrackingConfiguration,
                                      depthEnabled: Bool,
                                      force: Bool = false) {
            if !force, isDepthEnabled == depthEnabled {
                return
            }

            arView.session.run(configuration)
            isDepthEnabled = depthEnabled
        }

        private func pauseSessionIfNeeded(for arView: ARView) {
            isGenerationActive = true
            shouldForwardCapturedImage = false
            guard !isSessionPausedForGeneration else { return }
            arView.session.pause()
            isSessionPausedForGeneration = true
            SceneGeneratorDiagnosticsLogger.shared.log("[AR] session paused for generation")
        }

        private func resumeSessionIfNeeded(for arView: ARView,
                                           configuration: ARWorldTrackingConfiguration,
                                           depthEnabled: Bool) {
            guard isSessionPausedForGeneration else { return }
            isGenerationActive = false
            arView.session.run(configuration)
            isDepthEnabled = depthEnabled
            isSessionPausedForGeneration = false
            lastProcessedFrameTimestamp = 0
            lastTrackingStateDescription = nil
            SceneGeneratorDiagnosticsLogger.shared.log("[AR] session resumed after generation depthEnabled=\(depthEnabled)")
        }
        
        // MARK: - ARSessionDelegate
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard !isGenerationActive else { return }
            logTrackingStateIfNeeded(frame.camera.trackingState)

            let timestamp = frame.timestamp
            let cameraTransform = frame.camera.transform
            Task { @MainActor [weak viewModel, cameraTransform, timestamp] in
                viewModel?.updateARPresentationFrame(cameraTransform: cameraTransform, timestamp: timestamp)
            }

            // processARFrame не требует 60 вызовов/сек: в storyboard-only режиме держим AR легче.
            guard timestamp - lastProcessedFrameTimestamp >= frameProcessingInterval else { return }
            lastProcessedFrameTimestamp = timestamp
            guard beginFrameTaskIfPossible(timestamp: timestamp) else { return }

            let planeSnapshots = frame.anchors.compactMap { ($0 as? ARPlaneAnchor).map(ScenePlaneSnapshot.init(anchor:)) }
            let capturedImage: CVPixelBuffer? = shouldForwardCapturedImage ? frame.capturedImage : nil
            let displayTransform = frame.displayTransform(
                for: interfaceOrientation,
                viewportSize: viewportSize == .zero ? CGSize(width: 1, height: 1) : viewportSize
            )
            let currentInterfaceOrientation = interfaceOrientation
            logCameraAnalysisGeometryIfNeeded(
                frame: frame,
                timestamp: timestamp,
                capturedImage: capturedImage,
                displayTransform: displayTransform
            )

            Task { @MainActor [weak self, cameraTransform, planeSnapshots, timestamp, capturedImage, currentInterfaceOrientation, displayTransform] in
                guard let self else { return }
                viewModel.processARFrameSnapshot(
                    cameraTransform: cameraTransform,
                    planeSnapshots: planeSnapshots,
                    timestamp: timestamp,
                    capturedImage: capturedImage,
                    interfaceOrientation: currentInterfaceOrientation,
                    displayTransform: displayTransform
                )
                self.completeFrameTask(timestamp: timestamp)
            }
        }
        
        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            // Плоскость обнаружена - обновление происходит через processARFrame
        }
        
        func session(_ session: ARSession, didFailWithError error: Error) {
            SceneGeneratorDiagnosticsLogger.shared.log("[AR] session failed: \(error.localizedDescription)")
            Task { @MainActor in
                viewModel.errorMessage = "Ошибка AR: \(error.localizedDescription)"
            }
        }
        
        func sessionWasInterrupted(_ session: ARSession) {
            SceneGeneratorDiagnosticsLogger.shared.log("[AR] session interrupted")
        }
        
        func sessionInterruptionEnded(_ session: ARSession) {
            SceneGeneratorDiagnosticsLogger.shared.log("[AR] session interruption ended")
        }

        private func updateCoachingOverlay(isSceneGenerated: Bool, isARSessionReady: Bool) {
            let shouldHide = isSceneGenerated || isARSessionReady
            coachingOverlay?.activatesAutomatically = !shouldHide
            coachingOverlay?.isHidden = shouldHide
            if shouldHide, coachingOverlay?.isActive == true {
                coachingOverlay?.setActive(false, animated: true)
            }
        }

        private func beginFrameTaskIfPossible(timestamp: TimeInterval) -> Bool {
            frameTaskLock.lock()
            defer { frameTaskLock.unlock() }
            guard !frameTaskInFlight else {
                skippedFramesSinceLog += 1
                if skippedFramesSinceLog % 30 == 0 {
                    SceneGeneratorDiagnosticsLogger.shared.log("[AR] skipped frames because MainActor frame task is still in flight: skipped=\(skippedFramesSinceLog)")
                }
                return false
            }
            frameTaskInFlight = true
            return true
        }

        private func completeFrameTask(timestamp: TimeInterval) {
            frameTaskLock.lock()
            frameTaskInFlight = false
            processedFramesSinceLog += 1
            let skipped = skippedFramesSinceLog
            if lastFrameMetricsLogTimestamp == 0 {
                lastFrameMetricsLogTimestamp = timestamp
            }
            let elapsed = timestamp - lastFrameMetricsLogTimestamp
            let shouldLog = elapsed >= 5
            let processed = processedFramesSinceLog
            if shouldLog {
                skippedFramesSinceLog = 0
                processedFramesSinceLog = 0
                lastFrameMetricsLogTimestamp = timestamp
            }
            frameTaskLock.unlock()

            if shouldLog {
                let fps = elapsed > 0 ? Double(processed) / elapsed : 0
                let thermalState = ProcessInfo.processInfo.thermalState
                let memory = SceneGeneratorExecutionSupport.memoryUsageMB().map { String(format: "%.0f", $0) } ?? "nil"
                SceneGeneratorDiagnosticsLogger.shared.log("[AR] processed fps sample=\(String(format: "%.1f", fps)), skipped=\(skipped), thermal=\(thermalState), memoryMB=\(memory)")
            }
        }

        private func logTrackingStateIfNeeded(_ trackingState: ARCamera.TrackingState) {
            let description = trackingStateDescription(trackingState)
            guard description != lastTrackingStateDescription else { return }
            lastTrackingStateDescription = description
            SceneGeneratorDiagnosticsLogger.shared.log("[AR] trackingState=\(description)")
        }

        private func trackingStateDescription(_ trackingState: ARCamera.TrackingState) -> String {
            switch trackingState {
            case .normal:
                return "normal"
            case .notAvailable:
                return "not_available"
            case .limited(let reason):
                return "limited(\(trackingReasonDescription(reason)))"
            }
        }

        private func trackingReasonDescription(_ reason: ARCamera.TrackingState.Reason) -> String {
            switch reason {
            case .excessiveMotion:
                return "excessive_motion"
            case .insufficientFeatures:
                return "insufficient_features"
            case .initializing:
                return "initializing"
            case .relocalizing:
                return "relocalizing"
            @unknown default:
                return "unknown"
            }
        }

        private func logCameraAnalysisGeometryIfNeeded(frame: ARFrame,
                                                       timestamp: TimeInterval,
                                                       capturedImage: CVPixelBuffer?,
                                                       displayTransform: CGAffineTransform) {
            guard capturedImage != nil,
                  timestamp - lastCameraAnalysisGeometryLogTimestamp >= 1.0 else { return }
            lastCameraAnalysisGeometryLogTimestamp = timestamp
            let imageSize = capturedImage.map(Self.pixelBufferSizeDescription) ?? "nil"
            print(
                "[CA_DEBUG][AR_FRAME] ts=\(Self.format(timestamp)) forwardCaptured=\(capturedImage != nil) " +
                "interface=\(Self.interfaceOrientationDescription(interfaceOrientation)) " +
                "viewport=\(Self.sizeDescription(viewportSize)) image=\(imageSize) " +
                "displayTransform=\(Self.transformDescription(displayTransform)) " +
                "tracking=\(trackingStateDescription(frame.camera.trackingState))"
            )
        }

        private static func pixelBufferSizeDescription(_ pixelBuffer: CVPixelBuffer) -> String {
            "\(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))"
        }

        private static func sizeDescription(_ size: CGSize) -> String {
            "\(format(Double(size.width)))x\(format(Double(size.height)))"
        }

        private static func transformDescription(_ transform: CGAffineTransform) -> String {
            "[a=\(format(Double(transform.a))) b=\(format(Double(transform.b))) c=\(format(Double(transform.c))) d=\(format(Double(transform.d))) tx=\(format(Double(transform.tx))) ty=\(format(Double(transform.ty)))]"
        }

        private static func interfaceOrientationDescription(_ orientation: UIInterfaceOrientation) -> String {
            switch orientation {
            case .portrait:
                return "portrait"
            case .portraitUpsideDown:
                return "portraitUpsideDown"
            case .landscapeLeft:
                return "landscapeLeft"
            case .landscapeRight:
                return "landscapeRight"
            case .unknown:
                return "unknown"
            @unknown default:
                return "unknownFuture"
            }
        }

        private static func format(_ value: Double) -> String {
            String(format: "%.3f", value)
        }

        private static func currentInterfaceOrientation(for arView: ARView) -> UIInterfaceOrientation? {
            if let orientation = arView.window?.windowScene?.interfaceOrientation,
               orientation != .unknown {
                return orientation
            }

            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .map(\.interfaceOrientation)
                .first { $0 != .unknown }
        }
        
        // MARK: - Gestures
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = gesture.view as? ARView else { return }
            let location = gesture.location(in: arView)
            
            Task { @MainActor in
                SceneGeneratorDiagnosticsLogger.shared.log(
                    "[TOUCH_TRACE] arView tap state=\(Self.gestureStateDescription(gesture.state)) point=(\(Self.format(Double(location.x))), \(Self.format(Double(location.y)))), marking=\(viewModel.isMarkingMode), activeEditor=\(viewModel.activeStoryboardEditDraft?.beatID ?? "nil")"
                )
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

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let arView = gesture.view as? ARView else { return }
            let location = gesture.location(in: arView)
            if Self.shouldLogLongPressState(gesture.state) {
                SceneGeneratorDiagnosticsLogger.shared.log(
                    "[AR_GESTURE] longPress state=\(Self.gestureStateDescription(gesture.state)) point=(\(Self.format(Double(location.x))), \(Self.format(Double(location.y))))"
                )
            }

            Task { @MainActor in
                if Self.shouldLogLongPressState(gesture.state) {
                    SceneGeneratorDiagnosticsLogger.shared.log(
                        "[TOUCH_TRACE] arView longPress routed state=\(Self.gestureStateDescription(gesture.state)) point=(\(Self.format(Double(location.x))), \(Self.format(Double(location.y)))), marking=\(viewModel.isMarkingMode), activeEditor=\(viewModel.activeStoryboardEditDraft?.beatID ?? "nil")"
                    )
                }
                viewModel.handleStoryboardActorDragGesture(state: gesture.state, at: location)
            }
        }

        private static func shouldLogLongPressState(_ state: UIGestureRecognizer.State) -> Bool {
            switch state {
            case .began, .ended, .cancelled, .failed:
                return true
            default:
                return false
            }
        }

        private static func gestureStateDescription(_ state: UIGestureRecognizer.State) -> String {
            switch state {
            case .possible:
                return "possible"
            case .began:
                return "began"
            case .changed:
                return "changed"
            case .ended:
                return "ended"
            case .cancelled:
                return "cancelled"
            case .failed:
                return "failed"
            @unknown default:
                return "unknown"
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
