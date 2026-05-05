//
//  OverlayView.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import SwiftUI
import AVFoundation
import UIKit

struct OverlayView: View {
    @ObservedObject var viewModel: CameraViewModel
    let cameraManager: CameraManager

    var body: some View {
        ZStack {
            CameraPreview(session: cameraManager.captureSession,
                          cameraManager: cameraManager)
                .ignoresSafeArea()

            GeometryReader { proxy in
                let size = proxy.size
                let overlay = viewModel.overlayState

                ZStack(alignment: .center) {
                    // Кнопка паузы/продолжения
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: { viewModel.togglePause() }) {
                                Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                                    .foregroundColor(.black)
                                    .padding(10)
                                    .background(Color.white.opacity(0.9), in: Circle())
                            }
                            .padding(.top, 16)
                            .padding(.trailing, 16)
                        }
                        Spacer()
                    }

                    // Правило третей (тонкие линии)
                    if !viewModel.debugMode {
                        ThirdsGridOverlay()
                            .stroke(style: StrokeStyle(lineWidth: 0.8, dash: [6, 4]))
                            .foregroundColor(Color.white.opacity(0.35))
                    }

                    // Bounding box (только в non-debug режиме)
                    if !viewModel.debugMode, let bbox = overlay.primaryBoundingBox {
                        BBoxOverlay(boundingBox: bbox,
                                    canvasSize: size)
                            .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 4]))
                            .foregroundColor(.yellow)
                    }
                    
                    // Debug: DETR детекции и метрики
                    if viewModel.debugMode {
                        DebugVisualizationOverlay(
                            detrDetections: viewModel.detrDetections,
                            visionSubjects: viewModel.visionSubjects,
                            saliencyCenter: viewModel.saliencyCenter,
                            canvasSize: size
                        )
                    }

                    StructuredOverlayAnnotationsView(
                        annotations: viewModel.overlayAnnotations,
                        overlayState: overlay,
                        canvasSize: size
                    )
                    
                    // Стрелки-помощники
                    if !viewModel.isPaused {
                        let hasStructuredArrow = viewModel.overlayAnnotations.contains(where: { $0.kind == .arrow })
                        if !hasStructuredArrow {
                            let (directions, magnitude) = DirectionArrows.directions(
                                for: viewModel.legacySuggestion,
                                features: viewModel.features
                            )
                            if !directions.isEmpty {
                                DirectionArrows(directions: directions, magnitude: magnitude)
                            }
                        }
                    }
                    
                    // Live hint: новый structured path с fallback на legacy suggestion.
                    if !viewModel.isPaused {
                        LiveHintChipView(liveHint: viewModel.liveHint,
                                         fallbackSuggestion: viewModel.legacySuggestion,
                                         boundingBox: liveHintBoundingBox(
                                            for: viewModel.liveHint,
                                            fallback: overlay.primaryBoundingBox
                                         ),
                                         canvasSize: size)
                    }
                    
                    // Режим предпросмотра: список всех советов
                    if viewModel.isPaused {
                        if let pauseCritique = viewModel.pauseCritique {
                            PauseCritiqueCardView(
                                critique: pauseCritique,
                                legacySuggestions: viewModel.previewSuggestions
                            )
                                .padding(.bottom, 24)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        } else {
                            SuggestionListView(suggestions: viewModel.previewSuggestions)
                                .padding(.bottom, 40)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }

                    // Debug overlay
                    DebugMetricsView(isVisible: viewModel.debugMode)
                    
                    // Zoom control (внизу по центру)
                    if !viewModel.isPaused && !viewModel.debugMode && !viewModel.availableLenses.isEmpty {
                        VStack {
                            Spacer()
                            ZoomControlView(
                                availableLenses: viewModel.availableLenses,
                                currentLens: viewModel.currentLens,
                                onLensChange: { lens in
                                    viewModel.switchLens(to: lens)
                                }
                            )
                            .padding(.bottom, 32)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onTapGesture(count: 2) {
                viewModel.toggleDebug()
            }
        }
        .onAppear {
            viewModel.start()
            startUIFPSMonitoring()
        }
        .onDisappear { viewModel.stop() }
    }

    private func startUIFPSMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
            Telemetry.shared.recordUIFrame()
        }
    }

    private func liveHintBoundingBox(for liveHint: LiveHintPresentation?,
                                     fallback: CGRect?) -> CGRect? {
        if let region = liveHint?.targetRegion {
            return CGRect(x: region.x, y: region.y, width: region.width, height: region.height)
        }
        return fallback
    }
}

private struct StructuredOverlayAnnotationsView: View {
    let annotations: [OverlayAnnotationPresentation]
    let overlayState: OverlayState
    let canvasSize: CGSize

    var body: some View {
        ZStack {
            ForEach(annotations) { annotation in
                switch annotation.kind {
                case .arrow:
                    if let direction = annotation.direction,
                       let arrowDirection = arrowDirection(for: direction) {
                        DirectionArrows(
                            directions: [arrowDirection],
                            magnitude: CGFloat(annotation.emphasis)
                        )
                    }
                case .regionHighlight:
                    if let targetRegion = annotation.targetRegion {
                        BBoxOverlay(
                            boundingBox: rect(from: targetRegion),
                            canvasSize: canvasSize
                        )
                        .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [10, 4]))
                        .foregroundColor(.orange)
                    }
                case .horizonLine:
                    HorizonOverlay(angle: overlayState.horizonAngle, confidence: overlayState.horizonConfidence)
                        .stroke(style: StrokeStyle(lineWidth: 2.0, dash: [6, 4]))
                        .foregroundColor(.cyan.opacity(0.9))
                }
            }
        }
    }

    private func rect(from region: NormalizedRect) -> CGRect {
        CGRect(x: region.x, y: region.y, width: region.width, height: region.height)
    }

    private func arrowDirection(for direction: OverlayDirection) -> ArrowDirection? {
        switch direction {
        case .left: return .left
        case .right: return .right
        case .up: return .up
        case .down: return .down
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let cameraManager: CameraManager

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.cameraManager = cameraManager
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Устанавливаем ориентацию здесь, когда connection точно существует
        uiView.updateOrientation()
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    weak var cameraManager: CameraManager?
    private var lastOrientation: AVCaptureVideoOrientation?

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                self?.updateOrientation(force: true)
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateOrientation()
    }

    func updateOrientation(force: Bool = false) {
        guard let connection = videoPreviewLayer.connection,
              connection.isVideoOrientationSupported else {
            return
        }
        
        guard let interfaceOrientation = currentInterfaceOrientation(),
              let captureOrientation = AVCaptureVideoOrientation(interfaceOrientation: interfaceOrientation) else {
            return
        }
        
        if !force, let lastOrientation, lastOrientation == captureOrientation {
            return
        }
        
        lastOrientation = captureOrientation
        connection.videoOrientation = captureOrientation
        cameraManager?.setVideoOrientation(captureOrientation)
    }

    private func currentInterfaceOrientation() -> UIInterfaceOrientation? {
        if let orientation = window?.windowScene?.interfaceOrientation {
            return orientation
        }
        if Thread.isMainThread {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first(where: { $0.activationState == .foregroundActive })?
                .interfaceOrientation
        } else {
            var orientation: UIInterfaceOrientation?
            DispatchQueue.main.sync {
                orientation = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first(where: { $0.activationState == .foregroundActive })?
                    .interfaceOrientation
            }
            return orientation
        }
    }
}

private extension AVCaptureVideoOrientation {
    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        @unknown default: return nil
        }
    }
}
