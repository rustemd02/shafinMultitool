import SwiftUI
import AVFoundation
import UIKit

struct OverlayView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: CameraViewModel
    let cameraManager: CameraManager

#if DEBUG
    @State private var uiFPSTimer: Timer?
#endif
    @State private var lifecycleTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            CameraPreview(session: cameraManager.captureSession,
                          cameraManager: cameraManager)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            GeometryReader { proxy in
                let canvasSize = proxy.size
                let presentation = CameraOverlayUXPresentation.make(
                    liveHint: viewModel.liveHint,
                    isPaused: viewModel.isPaused
                )
                let hasZoomControl = !viewModel.availableLenses.isEmpty
                let lowerThirdInset = CameraOverlayUXPresentation.lowerThirdBottomInset(
                    hasZoomControl: hasZoomControl
                )

                ZStack(alignment: .center) {
                    // A guide is allowed only when it is supplied by the
                    // currently active corrective LiveHint. There is no
                    // permanent grid, bounding box, annotation stack, or
                    // legacy arrow fallback on the production surface.
                    if !viewModel.isPaused,
                       let overlayHint = presentation.overlayHint {
                        ActionLinkedGuideView(
                            hint: overlayHint,
                            canvasSize: canvasSize
                        )
                    }

                    if !viewModel.isPaused {
                        if viewModel.liveHint != nil {
                            LiveHintChipView(
                                liveHint: viewModel.liveHint,
                                fallbackSuggestion: nil,
                                boundingBox: nil,
                                canvasSize: canvasSize
                            )
                            .padding(.bottom, lowerThirdInset)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        } else {
                            LiveAnalysisStatusChip(title: presentation.observation)
                                .padding(.horizontal, 16)
                                .padding(.bottom, lowerThirdInset)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        }
                    }

#if DEBUG
                    if viewModel.debugMode {
                        DebugVisualizationOverlay(
                            detrDetections: viewModel.detrDetections,
                            visionSubjects: viewModel.visionSubjects,
                            saliencyCenter: viewModel.saliencyCenter,
                            canvasSize: canvasSize
                        )
                        DebugMetricsView(isVisible: true)
                    }
#endif

                    if !viewModel.isPaused && hasZoomControl {
                        VStack {
                            Spacer()
                            ZoomControlView(
                                availableLenses: viewModel.availableLenses,
                                currentLens: viewModel.currentLens,
                                onLensChange: { lens in
                                    viewModel.switchLens(to: lens)
                                }
                            )
                            .padding(.bottom, 28)
                        }
                    }

                    topControls
                        .zIndex(20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
#if DEBUG
            .onTapGesture(count: 2) {
                viewModel.toggleDebug()
            }
#endif
        }
        .onAppear {
            lifecycleTask?.cancel()
            lifecycleTask = Task { @MainActor in
                await viewModel.startAndWait()
            }
#if DEBUG
            if viewModel.debugMode {
                startUIFPSMonitoring()
            }
#endif
        }
#if DEBUG
        .onChange(of: viewModel.debugMode) { isDebugModeEnabled in
            if isDebugModeEnabled {
                startUIFPSMonitoring()
            } else {
                stopUIFPSMonitoring()
            }
        }
#endif
        .onDisappear {
#if DEBUG
            stopUIFPSMonitoring()
#endif
            lifecycleTask?.cancel()
            lifecycleTask = Task { @MainActor in
                await viewModel.stopAndWait()
            }
        }
    }

    @ViewBuilder
    private var topControls: some View {
        VStack {
            HStack(alignment: .top) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: CameraOverlayUXPresentation.minimumControlDimension,
                               height: CameraOverlayUXPresentation.minimumControlDimension)
                        .foregroundStyle(.primary)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityIdentifier("camera_coach_close")
                .accessibilityLabel("Закрыть камеру")

                Spacer()

                Button(action: { viewModel.togglePause() }) {
                    Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: CameraOverlayUXPresentation.minimumControlDimension,
                               height: CameraOverlayUXPresentation.minimumControlDimension)
                        .foregroundStyle(.primary)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityIdentifier("camera_coach_pause")
                .accessibilityLabel(viewModel.isPaused ? "Продолжить анализ" : "Поставить анализ на паузу")
                .accessibilityValue(viewModel.isPaused ? "Пауза включена" : "Анализ продолжается")
                .accessibilityAddTraits(viewModel.isPaused ? .isSelected : [])
            }
            .padding(.top, 16)
            .padding(.horizontal, 16)

            Spacer()
        }
    }

#if DEBUG
    private func startUIFPSMonitoring() {
        guard uiFPSTimer == nil else { return }
        uiFPSTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            Telemetry.shared.recordUIFrame()
        }
    }

    private func stopUIFPSMonitoring() {
        uiFPSTimer?.invalidate()
        uiFPSTimer = nil
    }
#endif
}

private struct ActionLinkedGuideView: View {
    let hint: OverlayHint
    let canvasSize: CGSize

    var body: some View {
        ZStack {
            if hint.kind == .regionHighlight, let targetRegion = hint.targetRegion {
                BBoxOverlay(
                    boundingBox: CGRect(
                        x: targetRegion.x,
                        y: targetRegion.y,
                        width: targetRegion.width,
                        height: targetRegion.height
                    ),
                    canvasSize: canvasSize
                )
                .stroke(Color.yellow.opacity(0.86), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 4]))
            }

            if hint.kind == .arrow, let direction = hint.direction {
                Image(systemName: arrowSystemName(for: direction))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.yellow)
                    .shadow(color: .black.opacity(0.45), radius: 2)
                    .frame(minWidth: CameraOverlayUXPresentation.minimumControlDimension,
                           minHeight: CameraOverlayUXPresentation.minimumControlDimension)
            }
        }
        .accessibilityHidden(true)
        .transition(.opacity)
    }

    private func arrowSystemName(for direction: OverlayDirection) -> String {
        switch direction {
        case .left:
            return "arrow.left.circle.fill"
        case .right:
            return "arrow.right.circle.fill"
        case .up:
            return "arrow.up.circle.fill"
        case .down:
            return "arrow.down.circle.fill"
        }
    }
}

private struct LiveAnalysisStatusChip: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "viewfinder")
                .font(.subheadline.weight(.semibold))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(CameraOverlayAccessibilityID.seeking)
        .accessibilityLabel(title)
        .accessibilityValue("Ожидание устойчивого совета")
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
              connection.isVideoOrientationSupported,
              let interfaceOrientation = currentInterfaceOrientation(),
              let captureOrientation = AVCaptureVideoOrientation(interfaceOrientation: interfaceOrientation) else {
            return
        }

        guard force || lastOrientation != captureOrientation else { return }

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
        }

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

private extension AVCaptureVideoOrientation {
    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait:
            self = .portrait
        case .portraitUpsideDown:
            self = .portraitUpsideDown
        case .landscapeLeft:
            self = .landscapeLeft
        case .landscapeRight:
            self = .landscapeRight
        case .unknown:
            return nil
        @unknown default:
            return nil
        }
    }
}
