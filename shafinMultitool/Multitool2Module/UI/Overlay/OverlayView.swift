import SwiftUI
import AVFoundation
import UIKit
import Combine

/// Runtime owner for the Camera Coach monitor. Presentation is delegated to
/// SETCameraCoachProductionView; this wrapper retains the existing lifecycle
/// and teardown boundary owned by the camera route.
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
            SETCameraCoachProductionView(
                viewModel: viewModel,
                cameraManager: cameraManager,
                onDismiss: { dismiss() }
            )

#if DEBUG
            if viewModel.debugMode {
                GeometryReader { proxy in
                    ZStack {
                        DebugVisualizationOverlay(
                            detrDetections: viewModel.detrDetections,
                            visionSubjects: viewModel.visionSubjects,
                            saliencyCenter: viewModel.saliencyCenter,
                            canvasSize: proxy.size
                        )

                        DebugMetricsView(isVisible: true)
                    }
                    .allowsHitTesting(false)
                }
            }
#endif
        }
#if DEBUG
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            viewModel.toggleDebug()
        }
#endif
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
        .onChange(of: viewModel.debugMode) { _, isDebugModeEnabled in
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

/// Preview-layer-owned conversion seam. Vision uses lower-left normalized
/// coordinates; AVCapture metadata uses upper-left normalized coordinates.
/// The conversion happens exactly once here, before the real preview layer
/// performs aspect-fill/orientation/mirroring conversion.
struct CameraPreviewRegionMapper {
    static func metadataOutputRect(for normalizedRegion: NormalizedRect) -> CGRect? {
        guard !normalizedRegion.isDegenerate else { return nil }
        return CGRect(
            x: CGFloat(normalizedRegion.x),
            y: CGFloat(1.0 - normalizedRegion.y - normalizedRegion.height),
            width: CGFloat(normalizedRegion.width),
            height: CGFloat(normalizedRegion.height)
        )
    }

    static func map(
        _ normalizedRegion: NormalizedRect,
        using converter: (CGRect) -> CGRect,
        bounds: CGRect
    ) -> CGRect? {
        guard let metadataRect = metadataOutputRect(for: normalizedRegion) else { return nil }
        let converted = converter(metadataRect).intersection(bounds)
        guard !converted.isNull, !converted.isEmpty else { return nil }
        return converted
    }
}

final class CameraPreviewTransformStore: ObservableObject {
    @Published private(set) var subjectRegions: [CGRect] = []
    @Published private(set) var targetRegion: CGRect?

    func update(subjectRegions: [CGRect], targetRegion: CGRect?) {
        if self.subjectRegions != subjectRegions {
            self.subjectRegions = subjectRegions
        }
        if self.targetRegion != targetRegion {
            self.targetRegion = targetRegion
        }
    }

    func clear() {
        update(subjectRegions: [], targetRegion: nil)
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let cameraManager: CameraManager
    var subjectRegions: [NormalizedRect] = []
    var correctiveTargetRegion: NormalizedRect?
    var transformStore: CameraPreviewTransformStore?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.cameraManager = cameraManager
        view.subjectRegions = subjectRegions
        view.correctiveTargetRegion = correctiveTargetRegion
        view.transformStore = transformStore
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.subjectRegions = subjectRegions
        uiView.correctiveTargetRegion = correctiveTargetRegion
        uiView.transformStore = transformStore
        uiView.updateOrientation()
        uiView.updateMappedRegions()
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    weak var cameraManager: CameraManager?
    weak var transformStore: CameraPreviewTransformStore?
    var subjectRegions: [NormalizedRect] = [] {
        didSet { setNeedsLayout() }
    }
    var correctiveTargetRegion: NormalizedRect? {
        didSet { setNeedsLayout() }
    }
    private var lastOrientation: AVCaptureVideoOrientation?
    private var orientationObserver: NSObjectProtocol?
    private var isGeneratingOrientationNotifications = false

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            startOrientationObservationIfNeeded()
            scheduleOrientationUpdate()
        } else {
            stopOrientationObservation()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateOrientation()
        updateMappedRegions()
    }

    func updateMappedRegions() {
        let bounds = videoPreviewLayer.bounds
        guard bounds.width > 0, bounds.height > 0 else {
            transformStore?.clear()
            return
        }
        let converter: (CGRect) -> CGRect = { [weak self] metadataRect in
            guard let self else { return .null }
            return self.videoPreviewLayer.layerRectConverted(fromMetadataOutputRect: metadataRect)
        }
        let mappedSubjects = subjectRegions.compactMap {
            CameraPreviewRegionMapper.map($0, using: converter, bounds: bounds)
        }
        let mappedTarget = correctiveTargetRegion.flatMap {
            CameraPreviewRegionMapper.map($0, using: converter, bounds: bounds)
        }
        transformStore?.update(subjectRegions: mappedSubjects, targetRegion: mappedTarget)
    }

    func updateOrientation(force: Bool = false) {
        guard let connection = videoPreviewLayer.connection,
              connection.isVideoOrientationSupported,
              let interfaceOrientation = currentInterfaceOrientation(),
              let coachOrientation = CameraCoachOrientation(interfaceOrientation: interfaceOrientation) else {
            return
        }
        let captureOrientation = coachOrientation.captureOrientation

        guard force || lastOrientation != captureOrientation else { return }

        lastOrientation = captureOrientation
        connection.videoOrientation = captureOrientation
        cameraManager?.setVideoOrientation(captureOrientation)
    }

    private func startOrientationObservationIfNeeded() {
        guard orientationObserver == nil else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        isGeneratingOrientationNotifications = true
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleOrientationUpdate()
        }
    }

    private func stopOrientationObservation() {
        if let orientationObserver {
            NotificationCenter.default.removeObserver(orientationObserver)
            self.orientationObserver = nil
        }
        if isGeneratingOrientationNotifications {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            isGeneratingOrientationNotifications = false
        }
    }

    private func scheduleOrientationUpdate() {
        DispatchQueue.main.async { [weak self] in
            self?.updateOrientation(force: true)
        }
    }

    deinit {
        stopOrientationObservation()
    }

    private func currentInterfaceOrientation() -> UIInterfaceOrientation? {
        if let orientation = window?.windowScene?.interfaceOrientation,
           orientation != .unknown {
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
