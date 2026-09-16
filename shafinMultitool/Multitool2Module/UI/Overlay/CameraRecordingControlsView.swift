import AVKit
import SwiftUI
import UIKit

/// Presentation of the existing Camera recording owner. Capture, persistence,
/// permission and audio-session transitions stay in its coordinator.
struct CameraRecordingControlsView: View {
    @ObservedObject var coordinator: CameraCoachRecordingCoordinator
    let canStart: Bool
    let maxAuxiliaryHeight: CGFloat

    init(coordinator: CameraCoachRecordingCoordinator, canStart: Bool, maxAuxiliaryHeight: CGFloat = 128) {
        self.coordinator = coordinator
        self.canStart = canStart
        self.maxAuxiliaryHeight = max(44, maxAuxiliaryHeight)
    }

    @Environment(\.openURL) private var openURL
    @State private var soundEnabled = true
    @State private var operationTask: Task<Void, Never>?
    @State private var operationID: UUID?
    @State private var presentation: CameraRecordingMediaPresentation?
    @State private var playbackOwnerID: UUID?
    @State private var localMessage: SETCopyKey?
    @State private var visible = false

    private var canBeginTake: Bool {
        canStart && !coordinator.hasPendingSave && !isTransitioning
            && coordinator.phase != .recording && coordinator.phase != .released
            && !coordinator.isPlaybackActive && !coordinator.isPhotosExportInFlight
            && operationTask == nil && presentation == nil
    }

    private var isTransitioning: Bool {
        switch coordinator.phase {
        case .changingMeter, .preparing, .finalizing, .saving: true
        default: false
        }
    }

    private var canReview: Bool {
        coordinator.latestSavedTake != nil && !isTransitioning
            && coordinator.phase != .recording && coordinator.phase != .released
            && !coordinator.hasPendingSave && !coordinator.isPlaybackActive && !coordinator.isPhotosExportInFlight
            && operationTask == nil && presentation == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x2) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: SETSpacing.x3) { captureActions }
                VStack(alignment: .leading, spacing: SETSpacing.x2) { captureActions }
            }

            if hasAuxiliaryContent {
                ViewThatFits(in: .vertical) {
                    auxiliaryContent
                    ScrollView(.vertical) { auxiliaryContent }
                        .scrollBounceBehavior(.basedOnSize)
                        .accessibilityIdentifier("camera_recording_details_scroll")
                }
                .frame(maxHeight: maxAuxiliaryHeight, alignment: .topLeading)
            }
        }
        .padding(SETSpacing.x3)
        .foregroundStyle(.setTextPrimary)
        .background(.setHUDScrim)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera_recording_controls")
        .sheet(item: $presentation, onDismiss: releasePlayback) { item in
            mediaSheet(item)
        }
        .onAppear { visible = true }
        .onChange(of: coordinator.isPlaybackActive) { _, isActive in
            if !isActive, presentation?.kind == .playback {
                presentation = nil
                playbackOwnerID = nil
            }
        }
        .onChange(of: coordinator.phase) { _, phase in
            if phase == .released {
                operationTask?.cancel()
                presentation = nil
                releasePlayback()
            }
        }
        .onDisappear {
            visible = false
            operationTask?.cancel()
            operationTask = nil
            operationID = nil
            presentation = nil
            releasePlayback()
        }
    }

    private var hasAuxiliaryContent: Bool {
        statusCopy != nil || coordinator.hasPendingSave || localMessage != nil
            || issueCopy != nil || coordinator.droppedVideoFrames > 0
            || coordinator.droppedAudioFrames > 0 || coordinator.latestSavedTake != nil
    }

    private var auxiliaryContent: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x2) {
            if let status = statusCopy {
                HStack(spacing: SETSpacing.x2) {
                    if isTransitioning { ProgressView().controlSize(.small) }
                    Text(status.localizedTextKey)
                        .font(SETTypography.uiBodyFont())
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("camera_recording_status")
            }

            if coordinator.hasPendingSave && coordinator.phase != .saving && coordinator.phase != .finalizing {
                control(.cameraRecordingRetrySave, image: "arrow.clockwise", identifier: "camera_recording_retry_save") {
                    localMessage = nil
                    runOperation { await coordinator.retryPersistence() }
                }
                .disabled(operationTask != nil || coordinator.phase == .released)
            }

            if let message = localMessage ?? issueCopy {
                Text(message.localizedTextKey)
                    .font(SETTypography.uiBodyFont())
                    .foregroundStyle(.setTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("camera_recording_message")
            }

            if coordinator.droppedVideoFrames > 0 || coordinator.droppedAudioFrames > 0 {
                Text(SETCopyKey.cameraRecordingMissingSamples.localizedTextKey)
                    .font(SETTypography.uiBodyFont())
                    .foregroundStyle(.setTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("camera_recording_missing_samples")
            }

            if shouldOfferSettings {
                control(.openSettings, image: "gearshape", identifier: "camera_recording_settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
            }

            if coordinator.latestSavedTake != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: SETSpacing.x2) { reviewActions }
                    VStack(alignment: .leading, spacing: SETSpacing.x2) { reviewActions }
                }
                .disabled(!canReview)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func mediaSheet(_ item: CameraRecordingMediaPresentation) -> some View {
            switch item.kind {
            case .playback:
                NavigationStack {
                    CameraRecordingPlayerSheet(url: item.artifact.localURL)
                        .ignoresSafeArea(edges: .bottom)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button { presentation = nil } label: {
                                    Text(SETCopyKey.commonClose.localizedTextKey)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityIdentifier("camera_recording_player_close")
                            }
                        }
                }
            case .share:
                CameraRecordingShareSheet(url: item.artifact.localURL) { completed, failed in
                    guard visible else { return }
                    localMessage = failed ? .cameraRecordingShareFailed : (completed ? .cameraRecordingShared : nil)
                    presentation = nil
                }
            }
    }

    private var captureActions: some View {
        Group {
            Toggle(isOn: $soundEnabled) {
                Label(
                    (soundEnabled ? SETCopyKey.cameraRecordingSoundOn : .cameraRecordingSoundOff).localizedTextKey,
                    systemImage: soundEnabled ? "mic.fill" : "mic.slash.fill"
                )
                .frame(minWidth: 44, minHeight: 44)
            }
            .toggleStyle(.button)
            .disabled(!canBeginTake)
            .accessibilityIdentifier("camera_recording_sound")

            if coordinator.phase == .recording || coordinator.phase == .preparing {
                control(
                    coordinator.phase == .preparing ? .cameraRecordingCancel : .cameraRecordingStop,
                    image: "stop.fill", identifier: "camera_recording_stop"
                ) {
                    // Stop owns cancellation even while start awaits an OS
                    // permission response; it cannot queue behind UI start.
                    operationTask?.cancel()
                    operationTask = nil
                    operationID = nil
                    runOperation { _ = await coordinator.stop(reason: .user) }
                }
            } else {
                control(.cameraRecordingStart, image: "record.circle", identifier: "camera_recording_start") {
                    localMessage = nil
                    let mode: RecordingAudioMode = soundEnabled ? .required : .disabled
                    runOperation { await coordinator.start(audioMode: mode) }
                }
                .disabled(!canBeginTake)
            }
        }
    }

    private var reviewActions: some View {
        Group {
            control(coordinator.meterEnabled ? .cameraRecordingPlayWithoutMeter : .cameraRecordingPlay,
                    image: "play.fill", identifier: "camera_recording_play") { presentSavedTake(.playback) }
            control(.cameraRecordingShare, image: "square.and.arrow.up", identifier: "camera_recording_share") { presentSavedTake(.share) }
            control(.cameraRecordingPhotos, image: "photo.on.rectangle", identifier: "camera_recording_photos") {
                localMessage = nil
                runOperation {
                    let outcome = await coordinator.exportToPhotos()
                    guard visible, !Task.isCancelled else { return }
                    localMessage = switch outcome {
                    case .exported: .cameraRecordingExported
                    case .denied: .cameraRecordingPhotosDenied
                    case .restricted: .cameraRecordingPhotosRestricted
                    case .alreadyInFlight: .cameraRecordingExporting
                    case .failed: .cameraRecordingExportFailed
                    }
                }
            }
        }
    }

    private func control(_ title: SETCopyKey, image: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title.localizedTextKey, systemImage: image)
                .font(SETTypography.uiBodyFont(weight: .semibold))
                .padding(.horizontal, SETSpacing.x2)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func runOperation(_ operation: @escaping @MainActor () async -> Void) {
        guard operationTask == nil else { return }
        let id = UUID()
        operationID = id
        operationTask = Task { @MainActor in
            await operation()
            if operationID == id {
                operationID = nil
                operationTask = nil
            }
        }
    }

    private func presentSavedTake(_ kind: CameraRecordingMediaPresentation.Kind) {
        localMessage = nil
        runOperation {
            guard let artifact = await coordinator.resolvedSavedArtifact(),
                  await AVURLAssetPlaybackProbe().isPlayableMovie(at: artifact.localURL) else {
                if visible { localMessage = .cameraRecordingMediaUnavailable }
                return
            }
            guard visible, !Task.isCancelled else { return }
            if kind == .playback {
                if coordinator.meterEnabled {
                    // The button explicitly tells the user this action stops
                    // the meter; only its existing owner changes the session.
                    await coordinator.setMeterEnabled(false)
                    guard visible, !Task.isCancelled else { return }
                }
                let owner = UUID()
                playbackOwnerID = owner
                do {
                    _ = try await coordinator.acquirePlaybackLease(ownerID: owner)
                } catch {
                    if playbackOwnerID == owner { playbackOwnerID = nil }
                    if visible { localMessage = .cameraRecordingPlaybackUnavailable }
                    return
                }
                guard visible, !Task.isCancelled else {
                    await coordinator.releasePlaybackLease(ownerID: owner)
                    if playbackOwnerID == owner { playbackOwnerID = nil }
                    return
                }
            }
            presentation = CameraRecordingMediaPresentation(artifact: artifact, kind: kind)
        }
    }

    private func releasePlayback() {
        guard let owner = playbackOwnerID else { return }
        playbackOwnerID = nil
        Task { await coordinator.releasePlaybackLease(ownerID: owner) }
    }

    private var statusCopy: SETCopyKey? {
        switch coordinator.phase {
        case .idle: nil
        case .changingMeter, .preparing: .cameraRecordingPreparing
        case .recording: .cameraRecordingRecording
        case .finalizing: .cameraRecordingFinalizing
        case .saving: .cameraRecordingSaving
        case .review: .cameraRecordingSaved
        case .failed: coordinator.hasPendingSave ? .cameraRecordingPendingSave : nil
        case .released: .cameraRecordingUnavailable
        }
    }

    private var shouldOfferSettings: Bool {
        if localMessage == .cameraRecordingPhotosDenied { return true }
        if case let .permission(snapshot) = coordinator.issue { return snapshot.authorization == .denied }
        return false
    }

    private var issueCopy: SETCopyKey? {
        guard let issue = coordinator.issue else { return nil }
        switch issue {
        case .busy: return .cameraRecordingBusy
        case .pendingSave: return .cameraRecordingPendingSave
        case .released: return .cameraRecordingUnavailable
        case let .permission(snapshot):
            if snapshot.authorization == .restricted { return .cameraRecordingPermissionRestricted }
            if snapshot.authorization == .denied {
                return snapshot.permission == .microphone ? .cameraRecordingMicrophoneDenied : .cameraRecordingCameraDenied
            }
            return snapshot.permission == .microphone ? .cameraRecordingMicrophoneUnavailable : .cameraRecordingUnavailable
        case .capture(.microphoneDenied), .recorder(.microphoneDenied):
            return .cameraRecordingMicrophoneDenied
        case .capture(.audioUnavailable), .recorder(.audioUnavailable), .recorder(.audioStartFailed), .recorder(.audioSessionUnavailable):
            return .cameraRecordingMicrophoneUnavailable
        case .recorder(.insufficientStorage): return .cameraRecordingStorageFull
        case .persistence(.mediaUnavailable): return .cameraRecordingMediaUnavailable
        case .persistence: return .cameraRecordingSaveFailed
        case .audioSession: return .cameraRecordingAudioUnavailable
        case .capture, .recorder: return .cameraRecordingCaptureFailed
        }
    }
}

/// A failed storage bootstrap remains actionable without constructing another
/// capture owner. The ViewModel retries its existing injected factory.
struct CameraRecordingUnavailableControls: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x2) {
            Text(SETCopyKey.cameraRecordingStorageUnavailable.localizedTextKey)
                .font(SETTypography.uiBodyFont())
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onRetry) {
                Label(SETCopyKey.cameraRecordingRetryPreparation.localizedTextKey,
                      systemImage: "arrow.clockwise")
                    .font(SETTypography.uiBodyFont(weight: .semibold))
                    .padding(.horizontal, SETSpacing.x2)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("camera_recording_retry_preparation")
        }
        .padding(SETSpacing.x3)
        .foregroundStyle(.setTextPrimary)
        .background(.setHUDScrim)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera_recording_unavailable_controls")
    }
}

private struct CameraRecordingMediaPresentation: Identifiable {
    enum Kind: Equatable { case playback, share }
    let id = UUID()
    let artifact: RecordingArtifact
    let kind: Kind
}

private struct CameraRecordingPlayerSheet: UIViewControllerRepresentable {
    let url: URL
    final class PlayerController: UIViewController {
        let mediaController = AVPlayerViewController()
        override func viewDidLoad() {
            super.viewDidLoad()
            addChild(mediaController)
            mediaController.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(mediaController.view)
            NSLayoutConstraint.activate([
                mediaController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                mediaController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                mediaController.view.topAnchor.constraint(equalTo: view.topAnchor),
                mediaController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            mediaController.didMove(toParent: self)
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            mediaController.player?.play()
        }
        override func viewWillDisappear(_ animated: Bool) {
            mediaController.player?.pause()
            super.viewWillDisappear(animated)
        }
    }
    func makeUIViewController(context: Context) -> PlayerController {
        let controller = PlayerController()
        controller.mediaController.player = AVPlayer(url: url)
        return controller
    }
    func updateUIViewController(_ controller: PlayerController, context: Context) {}
    static func dismantleUIViewController(_ controller: PlayerController, coordinator: ()) {
        controller.mediaController.player?.pause()
        controller.mediaController.player = nil
    }
}

private struct CameraRecordingShareSheet: UIViewControllerRepresentable {
    let url: URL
    let completion: (Bool, Bool) -> Void
    final class HostController: UIViewController {
        var activity: UIActivityViewController?
        private var hasPresentedActivity = false
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !hasPresentedActivity, let activity, presentedViewController == nil else { return }
            hasPresentedActivity = true
            // The host is laid out before presentation; iPad always receives
            // an actual in-window source and a nonempty popover anchor.
            activity.popoverPresentationController?.sourceView = view
            activity.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            activity.popoverPresentationController?.permittedArrowDirections = []
            present(activity, animated: true)
        }
    }
    func makeUIViewController(context: Context) -> HostController {
        let host = HostController()
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.completionWithItemsHandler = { _, completed, _, error in
            Task { @MainActor in completion(completed, error != nil) }
        }
        host.activity = activity
        return host
    }
    func updateUIViewController(_ controller: HostController, context: Context) {}
    static func dismantleUIViewController(_ controller: HostController, coordinator: ()) {
        controller.activity?.completionWithItemsHandler = nil
        controller.activity?.dismiss(animated: false)
        controller.activity = nil
    }
}
