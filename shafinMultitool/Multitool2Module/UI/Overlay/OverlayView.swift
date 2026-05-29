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
    @State private var decisionTrace: DecisionTracePresentation?

    var body: some View {
        ZStack {
            CameraPreview(session: cameraManager.captureSession,
                          cameraManager: cameraManager)
                .ignoresSafeArea()

            GeometryReader { proxy in
                let size = proxy.size
                let overlay = viewModel.overlayState
                let ux = CameraOverlayUXPresentation.make(
                    isPaused: viewModel.isPaused,
                    liveHint: viewModel.liveHint,
                    pauseCritique: viewModel.pauseCritique,
                    previewSuggestions: viewModel.previewSuggestions
                )

                ZStack(alignment: .center) {
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
                    if !viewModel.isPaused, viewModel.liveHint?.isFallback == true {
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
                    
                    // Live hint: показываем только стабилизированный structured/fallback-кандидат из pipeline.
                    if !viewModel.isPaused, let liveHint = viewModel.liveHint {
                        LiveHintChipView(liveHint: liveHint,
                                         fallbackSuggestion: nil,
                                         boundingBox: liveHintBoundingBox(
                                            for: liveHint,
                                            fallback: overlay.primaryBoundingBox
                                         ),
                                         canvasSize: size)
                    }

                    if !viewModel.isPaused, ux.showsLiveWaitingHint {
                        LiveAnalysisStatusChip(
                            title: ux.liveWaitingTitle ?? "Анализ кадра активен",
                            message: ux.liveWaitingBody ?? "Подсказка появится при уверенном сигнале."
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, viewModel.availableLenses.isEmpty ? 32 : 86)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                    
                    // Режим предпросмотра: список всех советов
                    if viewModel.isPaused {
                        if let pauseCritique = viewModel.pauseCritique {
                            PauseCritiqueCardView(
                                critique: pauseCritique,
                                legacySuggestions: viewModel.previewSuggestions,
                                maxHeight: pausePanelMaxHeight(for: size),
                                onContinue: resumeFromPause,
                                onExplain: ux.canShowDecisionTrace ? showDecisionTrace : nil
                            )
                                .padding(.bottom, 24)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        } else {
                            PauseStatusPanelView(
                                title: ux.pausePanelTitle ?? "Анализирую кадр",
                                message: ux.pausePanelBody ?? "Можно продолжить и попробовать другой ракурс.",
                                suggestions: viewModel.previewSuggestions,
                                maxHeight: pausePanelMaxHeight(for: size),
                                onContinue: resumeFromPause
                            )
                                .padding(.bottom, 24)
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

                    topControls(ux: ux)
                        .zIndex(20)
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
        .sheet(item: $decisionTrace) { trace in
            DecisionTraceView(trace: trace)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var canShowDecisionTrace: Bool {
        CameraOverlayUXPresentation.make(
            isPaused: viewModel.isPaused,
            liveHint: viewModel.liveHint,
            pauseCritique: viewModel.pauseCritique,
            previewSuggestions: viewModel.previewSuggestions
        ).canShowDecisionTrace
    }

    @ViewBuilder
    private func topControls(ux: CameraOverlayUXPresentation) -> some View {
        VStack {
            HStack(alignment: .top) {
                if ux.canShowDecisionTrace {
                    Button(action: showDecisionTrace) {
                        Label("Почему?", systemImage: "questionmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black.opacity(0.88))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Color.white.opacity(0.92), in: Capsule())
                    }
                    .accessibilityLabel("Показать почему приложение приняло решение")
                }

                Spacer()

                Button(action: { viewModel.togglePause() }) {
                    Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                        .foregroundColor(.black.opacity(0.88))
                        .padding(10)
                        .background(Color.white.opacity(0.92), in: Circle())
                }
                .accessibilityLabel(viewModel.isPaused ? "Продолжить анализировать кадр" : "Поставить кадр на паузу для разбора")
            }
            .padding(.top, 16)
            .padding(.horizontal, 16)

            Spacer()
        }
    }

    private func resumeFromPause() {
        guard viewModel.isPaused else { return }
        decisionTrace = nil
        viewModel.togglePause()
    }

    private func pausePanelMaxHeight(for size: CGSize) -> CGFloat {
        max(260, size.height * 0.58)
    }

    private func showDecisionTrace() {
        decisionTrace = DecisionTracePresentation.current(
            liveHint: viewModel.liveHint,
            pauseCritique: viewModel.pauseCritique,
            isPaused: viewModel.isPaused,
            overlayAnnotations: viewModel.overlayAnnotations,
            debugSignals: DecisionTraceDebugSignals.make(
                features: viewModel.features,
                detrDetections: viewModel.detrDetections,
                visionSubjects: viewModel.visionSubjects,
                saliencyCenter: viewModel.saliencyCenter
            )
        )
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

private struct LiveAnalysisStatusChip: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.96))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(message)
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
