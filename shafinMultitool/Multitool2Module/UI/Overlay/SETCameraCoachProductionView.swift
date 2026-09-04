import SwiftUI
import ImageIO

/// Deterministic input for the DEBUG production-route fixture. The fixture
/// selects projection payloads only; the runtime route remains owned by
/// CameraViewModel, CameraManager and CameraOverlayUXPresentation.
struct SETCameraCoachFixtureConfiguration {
    let fixtureID: String
    let locale: Locale
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let dynamicTypeSize: DynamicTypeSize
    let availableLenses: [CameraLens]
    let motionEventLedger: SETMotionEventLedger
    /// Fixture-only deterministic metadata. Runtime takes are owned by
    /// CameraViewModel and never use this default.
    let takeNumber: Int
    let snapshotID: String?

    init(
        fixtureID: String,
        localeIdentifier: String = "ru",
        reduceMotion: Bool = false,
        reduceTransparency: Bool = false,
        dynamicTypeSize: DynamicTypeSize = .large,
        availableLenses: [CameraLens] = [.ultraWide, .wide, .telephoto],
        motionEventLedger: SETMotionEventLedger = SETMotionEventLedger(),
        takeNumber: Int = 3,
        snapshotID: String? = nil
    ) {
        self.fixtureID = fixtureID
        self.locale = Locale(identifier: localeIdentifier)
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.dynamicTypeSize = dynamicTypeSize
        self.availableLenses = availableLenses.reduce(into: []) { lenses, lens in
            if !lenses.contains(lens) {
                lenses.append(lens)
            }
        }
        self.motionEventLedger = motionEventLedger
        self.takeNumber = max(1, takeNumber)
        self.snapshotID = snapshotID
    }
}

/// Production Camera Coach surface. Runtime and deterministic DEBUG routes
/// share this presentation owner so UI tests exercise the same monitor grammar
/// that the injected production ContentView uses.
struct SETCameraCoachProductionView: View {
    private enum Source {
        case runtime(CameraViewModel, CameraManager)
        case fixture(SETCameraCoachFixtureConfiguration)
    }

    private let source: Source
    private let onDismiss: () -> Void

    init(
        viewModel: CameraViewModel,
        cameraManager: CameraManager,
        onDismiss: @escaping () -> Void = {}
    ) {
        source = .runtime(viewModel, cameraManager)
        self.onDismiss = onDismiss
    }

    init(fixtureConfiguration: SETCameraCoachFixtureConfiguration) {
        source = .fixture(fixtureConfiguration)
        onDismiss = {}
    }

    var body: some View {
        Group {
            switch source {
            case .runtime(let viewModel, let cameraManager):
                SETCameraCoachRuntimeSurface(
                    viewModel: viewModel,
                    cameraManager: cameraManager,
                    onDismiss: onDismiss
                )
            case .fixture(let configuration):
                SETCameraCoachFixtureSurface(configuration: configuration)
                    .environment(\.locale, configuration.locale)
                    .environment(\.dynamicTypeSize, configuration.dynamicTypeSize)
                    .environment(\.setReduceMotionOverride, configuration.reduceMotion)
                    .environment(\.setReduceTransparencyOverride, configuration.reduceTransparency)
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct SETCameraCoachRuntimeSurface: View {
    @ObservedObject var viewModel: CameraViewModel
    let cameraManager: CameraManager
    let onDismiss: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @StateObject private var previewTransformStore = CameraPreviewTransformStore()

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = proxy.size
            ZStack {
                if viewModel.isPauseProjectionReady,
                   let acceptedSnapshot = viewModel.acceptedPauseSnapshot {
                    SETPauseSnapshotFrame(snapshot: acceptedSnapshot)
                        .ignoresSafeArea()
                    SETPauseReviewOverlay(
                        mode: pauseMode,
                        timecode: viewModel.nominalTimecode,
                        critique: pauseCritique,
                        eventLedger: viewModel.motionEventLedger,
                        reduceMotion: reduceMotion,
                        markerRegion: pauseMarkerRegion,
                        acceptedFramePixelSize: acceptedSnapshot.sourcePixelSize,
                        acceptedFrameOrientation: acceptedSnapshot.orientation,
                        acceptedFrameIsMirrored: false,
                        snapshotID: pausePresentation.snapshotID ?? "pause",
                        takeNumber: viewModel.takeNumber,
                        cutMarkController: viewModel.pauseCutMarkController,
                        onResume: { viewModel.togglePause() }
                    )
                } else {
                    // Keep a non-black fallback under the live preview while
                    // an accepted pause buffer is being rendered or when that
                    // render reports an owned failure.
                    (viewModel.isPaused ? Color.setWarmWhite : Color.setInk)
                        .ignoresSafeArea()
                    CameraPreview(
                        session: cameraManager.captureSession,
                        cameraManager: cameraManager,
                        subjectRegions: viewModel.subjectRegions,
                        correctiveTargetRegion: validatedCorrectiveTargetRegion,
                        transformStore: previewTransformStore
                    )
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                    if viewModel.pauseFailureReason != nil {
                        SETPauseReviewOverlay(
                            mode: .failure,
                            timecode: viewModel.nominalTimecode,
                            critique: nil,
                            eventLedger: viewModel.motionEventLedger,
                            reduceMotion: reduceMotion,
                            markerRegion: nil,
                            failureReason: viewModel.pauseFailureReason,
                            snapshotID: pausePresentation.snapshotID ?? "pause",
                            takeNumber: viewModel.takeNumber,
                            cutMarkController: viewModel.pauseCutMarkController,
                            onResume: { viewModel.togglePause() }
                        )
                    } else if viewModel.isPauseCapturePending {
                        SETCameraStatusOverlay(
                            canvasSize: canvasSize,
                            title: .pauseLoading,
                            action: nil,
                            tallyMode: .standby,
                            timecode: viewModel.nominalTimecode,
                            onAction: {}
                        )
                    } else if case .resuming = viewModel.pausePresentationState {
                        SETCameraStatusOverlay(
                            canvasSize: canvasSize,
                            title: .cameraResuming,
                            action: nil,
                            tallyMode: .standby,
                            timecode: viewModel.nominalTimecode,
                            onAction: {}
                        )
                    } else if scenePhase != .active,
                              viewModel.lifecycleState == .running {
                        SETCameraStatusOverlay(
                            canvasSize: canvasSize,
                            title: .cameraInterrupted,
                            action: nil,
                            tallyMode: .standby,
                            timecode: viewModel.nominalTimecode,
                            onAction: {}
                        )
                    } else {
                        switch viewModel.lifecycleState {
                        case .starting, .idle:
                            SETCameraStatusOverlay(
                                canvasSize: canvasSize,
                                title: .cameraPreparing,
                                action: nil,
                                tallyMode: .standby,
                                timecode: viewModel.nominalTimecode,
                                onAction: {}
                            )
                        case .failed(let error):
                            SETCameraStatusOverlay(
                                canvasSize: canvasSize,
                                title: error == .sessionInterrupted ? .cameraInterrupted : .cameraFailed,
                                action: error == .sessionInterrupted ? .cameraResume : .retry,
                                tallyMode: .standby,
                                timecode: viewModel.nominalTimecode,
                                onAction: { viewModel.start() }
                            )
                        case .stopping:
                            SETCameraStatusOverlay(
                                canvasSize: canvasSize,
                                title: .cameraInterrupted,
                                action: nil,
                                tallyMode: .standby,
                                timecode: viewModel.nominalTimecode,
                                onAction: {}
                            )
                        case .running:
                            SETCameraLiveOverlay(
                                viewModel: viewModel,
                                canvasSize: canvasSize,
                                reduceMotion: reduceMotion,
                                subjectRegions: previewTransformStore.subjectRegions,
                                correctiveTargetRegion: previewTransformStore.targetRegion,
                                lensDescriptors: cameraManager.availableLensDescriptors
                            )
                        }
                    }
                }

                SETCameraTopChrome(
                    isPaused: viewModel.isPaused,
                    onDismiss: onDismiss,
                    onTogglePause: { viewModel.togglePause() }
                )

                SETAccessibilityIdentifierProbe(identifier: CameraOverlayAccessibilityID.surface)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.setInk)
        .accessibilityElement(children: .contain)
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            viewModel.reportSceneInactive()
        }
    }

    private var pausePresentation: CameraPausePresentationState {
        viewModel.pausePresentationState
    }

    private var pauseMode: SETPauseReviewMode {
        switch pausePresentation {
        case .loading:
            return .loading
        case .success:
            return .success
        case .empty:
            return .empty
        case .failure:
            return .failure
        case .idle, .resuming:
            return viewModel.pauseCritique == nil ? .loading : .success
        }
    }

    private var pauseCritique: PauseCritiquePresentation? {
        if case .success(_, let critique) = pausePresentation { return critique }
        return viewModel.pauseCritique
    }

    private var pauseMarkerRegion: NormalizedRect? {
        pauseCritique?.actions.first?.targetRegion ?? pauseCritique?.issues.first?.affectedRegion
    }

    private var validatedCorrectiveTargetRegion: NormalizedRect? {
        guard let liveHint = viewModel.liveHint,
              let overlayHint = liveHint.overlayHint,
              overlayHint.kind == .arrow,
              let targetRegion = liveHint.targetRegion,
              !targetRegion.isDegenerate else { return nil }
        return targetRegion
    }
}

private struct SETCameraCoachFixtureSurface: View {
    let configuration: SETCameraCoachFixtureConfiguration
    @State private var fixtureIsPaused: Bool
    @State private var fixturePauseMode: SETPauseReviewMode

    init(configuration: SETCameraCoachFixtureConfiguration) {
        self.configuration = configuration
        _fixtureIsPaused = State(initialValue: configuration.fixtureID.hasPrefix("camera.pause-"))
        _fixturePauseMode = State(initialValue: Self.initialPauseMode(for: configuration.fixtureID))
    }

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = proxy.size
            ZStack {
                SETBundledImage.image(named: "SETCameraFrame")
                    .resizable()
                    .scaledToFill()
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .clipped()

                if fixtureIsPaused {
                    SETPauseReviewOverlay(
                        mode: fixturePauseMode,
                        timecode: SETLiveMonitorFixtureMetric.timecode,
                        critique: nil,
                        eventLedger: configuration.motionEventLedger,
                        reduceMotion: configuration.reduceMotion,
                        markerRegion: fixturePauseMarkerRegion,
                        snapshotID: configuration.snapshotID ?? configuration.fixtureID,
                        takeNumber: configuration.takeNumber,
                        onResume: resumeFixture
                    )
                } else {
                    SETCameraFixtureLiveOverlay(
                        fixtureID: configuration.fixtureID,
                        canvasSize: canvasSize,
                        availableLenses: configuration.availableLenses,
                        reduceMotion: configuration.reduceMotion,
                        eventLedger: configuration.motionEventLedger
                    )
                }

                SETCameraTopChrome(
                    isPaused: fixtureIsPaused,
                    onDismiss: {},
                    onTogglePause: toggleFixturePause
                )

                SETAccessibilityIdentifierProbe(identifier: configuration.fixtureID)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.setInk)
        .accessibilityElement(children: .contain)
        .task(id: fixturePauseMode) {
            guard fixtureIsPaused,
                  !isStaticPauseFixture,
                  fixturePauseMode == .loading else { return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            fixturePauseMode = .success
        }
    }

    private var isStaticPauseFixture: Bool {
        configuration.fixtureID.hasPrefix("camera.pause-")
    }

    private var fixturePauseMarkerRegion: NormalizedRect? {
        guard fixturePauseMode == .success else { return nil }
        return NormalizedRect(x: 0.58, y: 0.36, width: 0.20, height: 0.34)
    }

    private func toggleFixturePause() {
        if fixtureIsPaused {
            resumeFixture()
        } else {
            fixturePauseMode = .loading
            fixtureIsPaused = true
        }
    }

    private func resumeFixture() {
        fixtureIsPaused = false
    }

    private static func initialPauseMode(for fixtureID: String) -> SETPauseReviewMode {
        switch fixtureID {
        case "camera.pause-loading": return .loading
        case "camera.pause-empty": return .empty
        case "camera.pause-failure": return .failure
        default: return .success
        }
    }
}

private struct SETCameraTopChrome: View {
    let isPaused: Bool
    let onDismiss: () -> Void
    let onTogglePause: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: SETSpacing.x3) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.setTextPrimary)
                    .frame(width: SETComponentMetric.minimumHitTarget,
                           height: SETComponentMetric.minimumHitTarget)
                    .background(.setHUDScrim)
                    .overlay { Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline) }
            }
            .accessibilityIdentifier("camera_coach_close")
            .accessibilityLabel(Text(SETCopyKey.cameraClose.localizedTextKey))

            Spacer(minLength: SETSpacing.x2)

            Button(action: onTogglePause) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.setTextPrimary)
                    .frame(width: SETComponentMetric.minimumHitTarget,
                           height: SETComponentMetric.minimumHitTarget)
                    .background(.setHUDScrim)
                    .overlay { Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline) }
            }
            .accessibilityIdentifier("camera_coach_pause")
            .accessibilityLabel(Text(
                (isPaused ? SETCopyKey.cameraResume : SETCopyKey.cameraPause).localizedTextKey
            ))
            .accessibilityValue(Text(
                (isPaused ? SETCopyKey.cameraWhyValueOpen : SETCopyKey.cameraWhyValueClosed).localizedTextKey
            ))
            .accessibilityAddTraits(isPaused ? .isSelected : [])
        }
        .padding(.top, SETCameraCoachMetric.topControlTopInset)
        .padding(.horizontal, SETSpacing.x4)
        .frame(maxWidth: .infinity)
        .frame(height: SETCameraCoachMetric.topControlRowHeight, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(true)
    }
}

private struct SETCameraLiveOverlay: View {
    @ObservedObject var viewModel: CameraViewModel
    let canvasSize: CGSize
    let reduceMotion: Bool
    let subjectRegions: [CGRect]
    let correctiveTargetRegion: CGRect?
    let lensDescriptors: [CameraLensDescriptor]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    var body: some View {
        let presentation = CameraOverlayUXPresentation.make(
            liveHint: viewModel.liveHint,
            isExpanded: isExpanded,
            isPaused: false,
            locale: locale
        )
        let railHeight = commandRailHeight
        let railWidth = commandRailWidth

        ZStack {
            SETCameraRuntimeHUDHeader(
                tallyMode: .live,
                dimmed: presentation.isFallback,
                timecodePublisher: viewModel.nominalTimecodePublisher,
                showsECO: false
            )

            if !viewModel.availableLenses.isEmpty {
                SETCameraLensEdgeRail(
                    canvasSize: canvasSize,
                    availableLenses: viewModel.availableLenses,
                    lensDescriptors: lensDescriptors,
                    currentLens: viewModel.currentLens,
                    subjectRegions: subjectRegions,
                    commandRailFrame: commandRailFrame,
                    reservedFrames: lensStatus == nil ? [] : lensStatusReservedFrames,
                    isInteractionLocked: viewModel.lensSwitchPresentationState.isSwitching,
                    onLensChange: { viewModel.switchLens(to: $0) }
                )
            }

            if let lensStatus = lensStatus {
                SETCameraLensStatus(
                    status: lensStatus,
                    currentLens: viewModel.currentLens,
                    requestedLens: viewModel.lensSwitchRequestedLens,
                    canvasSize: canvasSize,
                    subjectRegions: subjectRegions,
                    commandRailFrame: commandRailFrame,
                    reservedFrames: lensRailReservedFrames,
                    reduceMotion: reduceMotion
                )
            }

            if let geometry = correctiveArrowGeometry,
               let markerEventID = presentation.liveHintID {
                SETCorrectiveArrowDrawGuide(
                    geometry: geometry,
                    eventID: markerEventID,
                    color: markerColor,
                    eventLedger: viewModel.motionEventLedger
                )
                .frame(width: canvasSize.width, height: canvasSize.height)
                .accessibilityHidden(true)
            } else if let markerKind, let markerEventID = presentation.liveHintID {
                SETMarkerDrawGuide(
                    kind: markerKind,
                    eventID: markerEventID,
                    color: markerColor,
                    eventLedger: viewModel.motionEventLedger
                )
                .frame(width: markerFrameSize.width, height: markerFrameSize.height)
                .position(markerPosition)
                .accessibilityHidden(true)
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                HStack(spacing: 0) {
                    SETCameraCommandBand(
                        state: presentationState,
                        actionKey: actionKey,
                        actionInstruction: presentation.actionInstruction,
                        explanation: presentation.explanation,
                        showsWhy: presentation.showsWhy,
                        isExpanded: isExpanded,
                        railHeight: railHeight,
                        onWhy: toggleExplanation
                    )
                    .frame(width: railWidth, height: railHeight)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, SETCameraCoachMetric.liveRailHorizontalInset)
                .padding(.bottom, SETCameraCoachMetric.liveRailBottomInset)
            }

            SETAccessibilityIdentifierProbe(identifier: CameraOverlayAccessibilityID.surface)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CameraOverlayAccessibilityID.surface)
        .onChange(of: viewModel.liveHint?.id) { _, _ in
            isExpanded = false
        }
    }

    @State private var isExpanded = false

    private var presentation: CameraOverlayUXPresentation {
        CameraOverlayUXPresentation.make(
            liveHint: viewModel.liveHint,
            isExpanded: isExpanded,
            locale: locale
        )
    }

    private var presentationState: SETCameraPresentationState {
        if presentation.isFallback { return .fallback }
        switch presentation.state {
        case .keepAsIs: return .keep
        case .explanation: return .explanation
        case .stableTip: return .corrective
        case .liveSeeking: return .seeking
        }
    }

    private var markerKind: SETMarkerKind? {
        switch presentationState {
        case .corrective: return correctiveArrowGeometry == nil ? nil : .arrow
        case .keep, .explanation: return presentation.targetRegion == nil ? nil : .underline
        case .seeking, .fallback: return nil
        }
    }

    private var markerColor: Color {
        presentationState == .corrective ? .setWarmWhite : .setWarmWhite
    }

    private var lensStatus: CameraLensStatusKind? {
        switch viewModel.lensSwitchPresentationState {
        case .idle:
            return nil
        case .switching:
            return .switching
        case .failed:
            return .failed
        }
    }

    private var markerFrameSize: CGSize {
        CGSize(width: SETCameraCoachMetric.markerWidth, height: SETCameraCoachMetric.markerHeight)
    }

    private var commandRailHeight: CGFloat {
        SETCameraCoachMetric.liveRailHeight(
            canvasSize: canvasSize,
            isAccessibilityType: dynamicTypeSize.isAccessibilitySize,
            isExpanded: isExpanded
        )
    }

    private var commandRailWidth: CGFloat {
        SETCameraCoachMetric.liveRailWidth(
            canvasSize: canvasSize,
            isAccessibilityType: dynamicTypeSize.isAccessibilitySize
        )
    }

    private var markerPosition: CGPoint {
        let target = viewModel.liveHint?.targetRegion
        let targetX = target.map { ($0.x + $0.width * 0.5) * canvasSize.width } ?? canvasSize.width * 0.68
        let targetY = target.map { ($0.y + $0.height * 0.5) * canvasSize.height } ?? canvasSize.height * 0.64
        let halfWidth = markerFrameSize.width * 0.5
        let halfHeight = markerFrameSize.height * 0.5
        let minimumY = halfHeight + SETCameraCoachMetric.markerTargetInset
        let railTop = canvasSize.height
            - commandRailHeight
            - SETCameraCoachMetric.liveRailBottomInset
        let maximumY = max(
            minimumY,
            railTop - SETCameraCoachMetric.liveRailMarkerClearance - halfHeight
        )
        return CGPoint(
            x: min(max(targetX, halfWidth + SETCameraCoachMetric.markerTargetInset),
                   max(halfWidth + SETCameraCoachMetric.markerTargetInset, canvasSize.width - halfWidth - SETCameraCoachMetric.markerTargetInset)),
            y: min(max(targetY, minimumY), maximumY)
        )
    }

    private var commandRailFrame: CGRect {
        CGRect(
            x: SETCameraCoachMetric.liveRailHorizontalInset,
            y: canvasSize.height - commandRailHeight - SETCameraCoachMetric.liveRailBottomInset,
            width: commandRailWidth,
            height: commandRailHeight
        )
    }

    private var correctiveArrowGeometry: SETCorrectiveArrowGeometry? {
        guard presentationState == .corrective,
              presentation.overlayHint?.kind == .arrow,
              let targetRect = correctiveTargetRegion,
              !targetRect.isNull,
              !targetRect.isEmpty else { return nil }
        return SETCorrectiveArrowGeometry.resolveValidated(
            canvasSize: canvasSize,
            targetRect: targetRect,
            commandRailFrame: commandRailFrame
        )
    }

    private var lensRailReservedFrames: [CGRect] {
        let statusSize = CGSize(
            width: SETCameraCoachMetric.lensStatusWidth,
            height: SETCameraCoachMetric.lensStatusHeight
        )
        return SETSubjectSafeControlPlacement.resolve(
            canvasSize: canvasSize,
            controlSize: statusSize,
            safeInsets: SETSafeInsets(
                top: SETCameraCoachMetric.lensRailTopInset + SETCameraCoachMetric.lensStatusHeight + SETSpacing.x2,
                leading: SETSpacing.x2,
                bottom: SETSpacing.x2,
                trailing: SETSpacing.x2
            ),
            subjectRegions: subjectRegions,
            commandRailFrame: commandRailFrame
        ).map { [$0.frame] } ?? []
    }

    private var lensStatusReservedFrames: [CGRect] {
        let railSize = SETCameraCoachMetric.lensRailControlSize(for: viewModel.availableLenses.count)
        return SETSubjectSafeControlPlacement.resolve(
            canvasSize: canvasSize,
            controlSize: railSize,
            safeInsets: SETSafeInsets(
                top: SETCameraCoachMetric.lensRailTopInset,
                leading: SETSpacing.x2,
                bottom: SETSpacing.x2,
                trailing: SETSpacing.x2
            ),
            subjectRegions: subjectRegions,
            commandRailFrame: commandRailFrame
        ).map { [$0.frame] } ?? []
    }

    private var actionKey: SETCopyKey {
        switch presentationState {
        case .seeking: return .cameraSeeking
        case .keep: return .cameraKeep
        case .fallback: return .cameraFallback
        case .corrective, .explanation: return .cameraCorrectiveAction
        }
    }

    private func toggleExplanation() {
        if reduceMotion {
            isExpanded.toggle()
        } else {
            withAnimation(.easeOut(duration: SETMotion.reducedMotionCrossfadeDuration)) {
                isExpanded.toggle()
            }
        }
    }
}

private struct SETCameraFixtureLiveOverlay: View {
    let fixtureID: String
    let canvasSize: CGSize
    let availableLenses: [CameraLens]
    let reduceMotion: Bool
    let eventLedger: SETMotionEventLedger

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let railHeight = commandRailHeight
        let railWidth = commandRailWidth

        ZStack {
            SETCameraHUDHeader(
                tallyMode: tallyMode,
                dimmed: fixtureID == "camera.fallback",
                timecode: SETLiveMonitorFixtureMetric.timecode,
                showsECO: fixtureID == "camera.eco"
            )

            if fixtureID == "camera.lens-switching" {
                SETCameraLensEdgeRail(
                    canvasSize: canvasSize,
                    availableLenses: availableLenses,
                    currentLens: .wide,
                    subjectRegions: [],
                    commandRailFrame: commandRailFrame,
                    reservedFrames: [],
                    isInteractionLocked: false,
                    onLensChange: { _ in }
                )

                SETCameraLensStatus(
                    status: .switching,
                    currentLens: .wide,
                    requestedLens: availableLenses.last ?? .wide,
                    canvasSize: canvasSize,
                    subjectRegions: [],
                    commandRailFrame: commandRailFrame,
                    reservedFrames: [],
                    reduceMotion: reduceMotion
                )
            }

            if fixtureID == "camera.corrective" {
                SETCorrectiveArrowDrawGuide(
                    geometry: correctiveArrowGeometry,
                    eventID: fixtureID,
                    color: .setWarmWhite,
                    eventLedger: eventLedger
                )
                .frame(width: canvasSize.width, height: canvasSize.height)
                .accessibilityHidden(true)
            } else if let markerKind {
                SETMarkerDrawGuide(
                    kind: markerKind,
                    eventID: fixtureID,
                    color: .setWarmWhite,
                    eventLedger: eventLedger
                )
                .frame(width: SETCameraCoachMetric.markerWidth,
                       height: SETCameraCoachMetric.markerHeight)
                .position(markerPosition)
                .accessibilityHidden(true)
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                HStack(spacing: 0) {
                    SETCameraFixtureCommandBand(
                        fixtureID: fixtureID,
                        currentLens: .wide,
                        railHeight: fixtureID == "camera.lens-switching"
                            ? SETCameraCoachMetric.lensStatusHeight
                            : railHeight,
                        isCompactStatus: fixtureID == "camera.lens-switching"
                    )
                    .frame(
                        width: fixtureID == "camera.lens-switching"
                            ? SETCameraCoachMetric.lensStatusWidth
                            : railWidth,
                        height: fixtureID == "camera.lens-switching"
                            ? SETCameraCoachMetric.lensStatusHeight
                            : railHeight
                    )

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, SETCameraCoachMetric.liveRailHorizontalInset)
                .padding(.bottom, SETCameraCoachMetric.liveRailBottomInset)
            }

            SETAccessibilityIdentifierProbe(identifier: CameraOverlayAccessibilityID.surface)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(fixtureID)
    }

    private var markerKind: SETMarkerKind? {
        switch fixtureID {
        case "camera.corrective": return .arrow
        case "camera.keep", "camera.explanation": return .underline
        default: return nil
        }
    }

    private var tallyMode: SETTallyMode {
        switch fixtureID {
        case "camera.starting", "camera.interrupted", "camera.failed", "camera.resuming", "camera.lens-switching":
            return .standby
        default:
            return .live
        }
    }

    private var commandRailHeight: CGFloat {
        SETCameraCoachMetric.liveRailHeight(
            canvasSize: canvasSize,
            isAccessibilityType: dynamicTypeSize.isAccessibilitySize,
            isExpanded: false
        )
    }

    private var commandRailWidth: CGFloat {
        SETCameraCoachMetric.liveRailWidth(
            canvasSize: canvasSize,
            isAccessibilityType: dynamicTypeSize.isAccessibilitySize
        )
    }

    private var commandRailFrame: CGRect {
        CGRect(
            x: SETCameraCoachMetric.liveRailHorizontalInset,
            y: canvasSize.height - commandRailHeight - SETCameraCoachMetric.liveRailBottomInset,
            width: fixtureID == "camera.lens-switching"
                ? SETCameraCoachMetric.lensStatusWidth
                : commandRailWidth,
            height: fixtureID == "camera.lens-switching"
                ? SETCameraCoachMetric.lensStatusHeight
                : commandRailHeight
        )
    }

    private var correctiveArrowGeometry: SETCorrectiveArrowGeometry {
        SETCorrectiveArrowGeometry.resolve(
            canvasSize: canvasSize,
            targetRegion: NormalizedRect(x: 0.58, y: 0.36, width: 0.20, height: 0.34),
            commandRailFrame: commandRailFrame
        )
    }

    private var markerPosition: CGPoint {
        let markerWidth = SETCameraCoachMetric.markerWidth
        let markerHeight = SETCameraCoachMetric.markerHeight
        let halfWidth = markerWidth * 0.5
        let halfHeight = markerHeight * 0.5
        let minimumY = halfHeight + SETCameraCoachMetric.markerTargetInset
        let railTop = canvasSize.height
            - commandRailHeight
            - SETCameraCoachMetric.liveRailBottomInset
        let maximumY = max(
            minimumY,
            railTop - SETCameraCoachMetric.liveRailMarkerClearance - halfHeight
        )
        let targetY = canvasSize.height * SETLiveMonitorFixtureMetric.markerCenterY

        return CGPoint(
            x: min(
                max(canvasSize.width * SETLiveMonitorFixtureMetric.markerCenterX,
                    halfWidth + SETCameraCoachMetric.markerTargetInset),
                max(halfWidth + SETCameraCoachMetric.markerTargetInset,
                    canvasSize.width - halfWidth - SETCameraCoachMetric.markerTargetInset)
            ),
            y: min(max(targetY, minimumY), maximumY)
        )
    }
}

private struct SETCameraHUDHeader: View {
    let tallyMode: SETTallyMode
    let dimmed: Bool
    let timecode: String
    let showsECO: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The top chrome owns this row. Keeping it explicit leaves a full
            // 44pt control plus SET spacing clear on both sides of the HUD.
            Color.clear
                .frame(height: SETCameraCoachMetric.topControlRowHeight)

            HStack(alignment: .center, spacing: SETSpacing.x3) {
                SETTallyBadge(mode: tallyMode, pulses: tallyMode == .live, dimmed: dimmed)
                    .accessibilityIdentifier(tallyMode == .live ? CameraOverlayAccessibilityID.seeking : "camera-coach-standby")

                SETTimecodeView(value: timecode, showsFrames: true)
                    .accessibilityIdentifier("camera-coach-timecode")

                if showsECO {
                    SETTallyBadge(mode: .eco)
                        .accessibilityIdentifier("camera-coach-eco")
                }
            }
            .padding(.horizontal, SETSpacing.x3)
            .frame(height: SETCameraCoachMetric.headerHeight)
            .background(.setHUDScrim)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, SETCameraCoachMetric.headerControlHorizontalInset)
    }
}

private struct SETCameraRuntimeHUDHeader: View {
    let tallyMode: SETTallyMode
    let dimmed: Bool
    @ObservedObject var timecodePublisher: CameraNominalTimecodePublisher
    let showsECO: Bool

    var body: some View {
        SETCameraHUDHeader(
            tallyMode: tallyMode,
            dimmed: dimmed,
            timecode: timecodePublisher.value,
            showsECO: showsECO
        )
    }
}

private enum CameraLensStatusKind: Equatable {
    case switching
    case failed
}

private struct SETCameraLensStatus: View {
    let status: CameraLensStatusKind
    let currentLens: CameraLens
    let requestedLens: CameraLens?
    let canvasSize: CGSize
    let subjectRegions: [CGRect]
    let commandRailFrame: CGRect
    let reservedFrames: [CGRect]
    let reduceMotion: Bool

    @Environment(\.locale) private var locale

    var body: some View {
        let placement = SETSubjectSafeControlPlacement.resolve(
            canvasSize: canvasSize,
            controlSize: CGSize(
                width: SETCameraCoachMetric.lensStatusWidth,
                height: SETCameraCoachMetric.lensStatusHeight
            ),
            safeInsets: SETSafeInsets(
                top: SETCameraCoachMetric.lensRailTopInset + SETCameraCoachMetric.lensStatusHeight + SETSpacing.x2,
                leading: SETSpacing.x2,
                bottom: SETSpacing.x2,
                trailing: SETSpacing.x2
            ),
            subjectRegions: subjectRegions,
            commandRailFrame: commandRailFrame,
            reservedFrames: reservedFrames
        )

        Group {
            if let placement {
                Text(statusText)
            .font(SETTypography.font(.hudMono, size: SETTypographySize.micro))
            .fontWeight(.semibold)
            .foregroundStyle(.setTextPrimary)
            .lineLimit(2)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, SETSpacing.x3)
            .frame(width: SETCameraCoachMetric.lensStatusWidth,
                   height: SETCameraCoachMetric.lensStatusHeight,
                   alignment: .leading)
            .background(.setHUDScrim)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(status == .failed ? Color.setWarmWhite : Color.setOrange)
                    .frame(width: SETStroke.standard)
            }
            .overlay { Rectangle().stroke(.setHairline, lineWidth: SETStroke.hairline) }
                    .position(x: placement.frame.midX, y: placement.frame.midY)
            .opacity(1)
            .transition(
                .opacity.animation(
                    reduceMotion
                        ? .easeOut(duration: SETMotion.reducedMotionCrossfadeDuration)
                        : SETMotion.standardSpring
                )
            )
            .animation(
                reduceMotion
                    ? .easeOut(duration: SETMotion.reducedMotionCrossfadeDuration)
                    : SETMotion.standardSpring,
                value: statusText
            )
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("camera_coach_lens_status")
                    .accessibilityLabel(Text(statusText))
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("camera_coach_lens_status")
                    .accessibilityLabel(Text(statusText))
            }
        }
    }

    private var statusText: String {
        let requested = requestedLens ?? currentLens
        let key = status == .switching
            ? "set.camera.lens.switching_to"
            : "set.camera.lens.failed"
        let format = String(localized: String.LocalizationValue(key), locale: locale)
        return String(
            format: format,
            locale: locale,
            arguments: [requested.displayName, currentLens.displayName]
        )
    }
}

/// Lens switching is a secondary edge affordance. It sits below the compact
/// left HUD strip so the expanded real-lens row never crosses the subject.
private struct SETCameraLensEdgeRail: View {
    let canvasSize: CGSize
    let availableLenses: [CameraLens]
    var lensDescriptors: [CameraLensDescriptor] = []
    let currentLens: CameraLens
    let subjectRegions: [CGRect]
    let commandRailFrame: CGRect
    let reservedFrames: [CGRect]
    let isInteractionLocked: Bool
    let onLensChange: (CameraLens) -> Void

    var body: some View {
        let controlSize = SETCameraCoachMetric.lensRailControlSize(for: availableLenses.count)
        let placement = SETSubjectSafeControlPlacement.resolve(
            canvasSize: canvasSize,
            controlSize: controlSize,
            safeInsets: SETSafeInsets(
                top: SETCameraCoachMetric.lensRailTopInset,
                leading: SETSpacing.x2,
                bottom: SETSpacing.x2,
                trailing: SETSpacing.x2
            ),
            subjectRegions: subjectRegions,
            commandRailFrame: commandRailFrame,
            reservedFrames: reservedFrames
        )

        Group {
            if let placement {
                ZoomControlView(
                    availableLenses: availableLenses,
                    currentLens: currentLens,
                    lensDescriptors: lensDescriptors.isEmpty
                        ? availableLenses.map(\.descriptor)
                        : lensDescriptors,
                    isInteractionLocked: isInteractionLocked,
                    onLensChange: onLensChange
                )
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: placement.frame.width,
                       height: placement.frame.height,
                       alignment: .topLeading)
                .position(x: placement.frame.midX, y: placement.frame.midY)
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(SETCopyKey.cameraZoom.localizedTextKey))
            }
        }
    }
}

private enum SETCameraPresentationState: Equatable {
    case seeking
    case keep
    case corrective
    case fallback
    case explanation
}

enum SETCameraCopy {
    static func actionKey(for actionType: ActionTypeV1) -> SETCopyKey {
        switch actionType {
        case .moveFrameLeft: return .cameraCorrectiveMoveLeft
        case .moveFrameRight: return .cameraCorrectiveMoveRight
        case .moveFrameUp: return .cameraCorrectiveMoveUp
        case .moveFrameDown: return .cameraCorrectiveMoveDown
        case .increaseSubjectSize: return .cameraCorrectiveIncreaseSubject
        case .reduceBackgroundDistractions: return .cameraCorrectiveReduceDistractions
        case .changeAngle: return .cameraCorrectiveChangeAngle
        case .improveFrontLight: return .cameraCorrectiveImproveLight
        case .levelHorizon: return .cameraCorrectiveLevelHorizon
        case .leaveFrameAsIs: return .cameraKeep
        }
    }

    static func actionKey(for semanticActionType: SemanticActionType) -> SETCopyKey {
        switch semanticActionType {
        case .shiftFrameLeft: return .traceActionShiftLeft
        case .shiftFrameRight: return .traceActionShiftRight
        case .shiftFrameUp: return .traceActionShiftUp
        case .shiftFrameDown: return .traceActionShiftDown
        case .stepBack: return .traceActionStepBack
        case .stepCloser: return .traceActionStepCloser
        case .lowerCamera: return .traceActionLowerCamera
        case .raiseCamera: return .traceActionRaiseCamera
        case .changeCameraAngle: return .traceActionChangeAngle
        case .levelHorizon: return .traceActionLevelHorizon
        case .rotateSubjectTowardLight: return .traceActionRotateSubject
        case .moveSubjectLeft: return .traceActionMoveSubjectLeft
        case .moveSubjectRight: return .traceActionMoveSubjectRight
        case .moveSubjectAwayFromBackground: return .traceActionMoveSubjectAway
        case .moveObjectLeft: return .traceActionMoveObjectLeft
        case .moveObjectRight: return .traceActionMoveObjectRight
        case .moveObjectForward: return .traceActionMoveObjectForward
        case .moveObjectBack: return .traceActionMoveObjectBack
        case .removeDistractingObject: return .traceActionRemoveDistractingObject
        case .repositionPropForBalance: return .traceActionRepositionProp
        case .addFrontFillLight: return .traceActionAddFrontFill
        case .addBackgroundLight: return .traceActionAddBackgroundLight
        case .removeBackgroundHotspot: return .traceActionRemoveHotspot
        case .simplifyBackground: return .traceActionSimplifyBackground
        case .waitForBackgroundClearance: return .traceActionWaitClearance
        case .keepCurrentSetup: return .traceActionKeepSetup
        }
    }

    static func technicalActionKey(for issueType: TechnicalQualityIssueType) -> SETCopyKey {
        switch issueType {
        case .motionBlur: return .cameraTechnicalStabilizeCamera
        case .defocus: return .cameraTechnicalRefocusSubject
        case .overexposure: return .cameraTechnicalReduceExposure
        case .underexposure: return .cameraTechnicalIncreaseExposure
        case .noise: return .cameraTechnicalReduceNoise
        case .occlusion: return .cameraTechnicalAvoidOcclusion
        case .lensSmudge: return .cameraTechnicalCleanLens
        }
    }
}

private struct SETCameraCommandBand: View {
    let state: SETCameraPresentationState
    let actionKey: SETCopyKey
    let actionInstruction: String?
    let explanation: String?
    let showsWhy: Bool
    let isExpanded: Bool
    let railHeight: CGFloat
    let onWhy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x2) {
            HStack(alignment: .bottom, spacing: SETSpacing.x3) {
                commandText
                    .accessibilityIdentifier(CameraOverlayAccessibilityID.observation)

                if showsWhy {
                    Button(action: onWhy) {
                        Text((isExpanded ? SETCopyKey.cameraHideWhy : SETCopyKey.cameraWhy).localizedTextKey)
                            .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                            .fontWeight(.semibold)
                            .foregroundStyle(.setOrange)
                            .frame(minWidth: SETComponentMetric.minimumHitTarget,
                                   minHeight: SETComponentMetric.minimumHitTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(CameraOverlayAccessibilityID.why)
                    .accessibilityLabel(Text(
                        (isExpanded ? SETCopyKey.cameraHideWhy : SETCopyKey.cameraWhy).localizedTextKey
                    ))
                    .accessibilityValue(Text(
                        (isExpanded ? SETCopyKey.cameraWhyValueOpen : SETCopyKey.cameraWhyValueClosed).localizedTextKey
                    ))
                }
            }

            if isExpanded, let explanation {
                Text(verbatim: explanation)
                    .font(SETTypography.uiBodyFont())
                    .foregroundStyle(.setTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    // Reduce Motion keeps this interaction to a local
                    // opacity fade; the command rail itself never travels,
                    // scales, or springs as the explanation is revealed.
                    .transition(.opacity)
                    .animation(
                        .easeOut(duration: SETMotion.reducedMotionCrossfadeDuration),
                        value: isExpanded
                    )
                    .accessibilityIdentifier(CameraOverlayAccessibilityID.explanation)
            }
        }
        .padding(.horizontal, SETCameraCoachMetric.commandHorizontalInset)
        .padding(.vertical, SETCameraCoachMetric.commandVerticalInset)
        .frame(height: railHeight, alignment: .topLeading)
        .background(.setHUDScrim)
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(state == .fallback ? Color.setWarmWhite : Color.setOrange)
                .frame(width: SETStroke.standard)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CameraOverlayAccessibilityID.surface)
    }

    @ViewBuilder
    private var commandText: some View {
        switch state {
        case .corrective, .explanation:
            if let actionInstruction {
                Text(verbatim: actionInstruction)
                    .font(SETTypography.font(.display, size: SETTypographySize.command))
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(state == .corrective ? .setOrange : .setTextPrimary)
                    .accessibilityIdentifier(CameraOverlayAccessibilityID.action)
            }
        case .seeking, .keep, .fallback:
            Text(actionKey.localizedTextKey)
                .font(SETTypography.font(.hudMono, size: SETTypographySize.body))
                .foregroundStyle(state == .fallback ? .setTextPrimary : .setTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(CameraOverlayAccessibilityID.action)
        }
    }
}

private struct SETCameraFixtureCommandBand: View {
    let fixtureID: String
    let currentLens: CameraLens
    let railHeight: CGFloat
    let isCompactStatus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isCompactStatus ? 0 : SETSpacing.x2) {
            HStack(alignment: .bottom, spacing: isCompactStatus ? SETSpacing.x2 : SETSpacing.x3) {
                Text(commandKey.localizedTextKey)
                    .font(SETTypography.font(
                        .hudMono,
                        size: isCompactStatus ? SETTypographySize.label : SETTypographySize.body
                    ))
                    .foregroundStyle(fixtureID == "camera.corrective" ? .setOrange : .setTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: !isCompactStatus, vertical: true)
                    .accessibilityIdentifier(CameraOverlayAccessibilityID.observation)

                if isCompactStatus {
                    Text(currentLens.displayName)
                        .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                        .foregroundStyle(.setTextPrimary)
                        .accessibilityIdentifier("camera-current-lens")
                }
            }

            if fixtureID == "camera.explanation" && !isCompactStatus {
                Text(SETCopyKey.cameraExplanation.localizedTextKey)
                    .font(SETTypography.uiBodyFont())
                    .foregroundStyle(.setTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(CameraOverlayAccessibilityID.explanation)
            }
        }
        .padding(.horizontal, SETCameraCoachMetric.commandHorizontalInset)
        .padding(.vertical, SETCameraCoachMetric.commandVerticalInset)
        .frame(height: railHeight, alignment: .topLeading)
        .background(.setHUDScrim)
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(fixtureID == "camera.fallback" ? Color.setWarmWhite : Color.setOrange)
                .frame(width: SETStroke.standard)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(fixtureID)
    }

    private var commandKey: SETCopyKey {
        switch fixtureID {
        case "camera.starting": return .cameraPreparing
        case "camera.interrupted": return .cameraInterrupted
        case "camera.failed": return .cameraFailed
        case "camera.seeking": return .cameraSeeking
        case "camera.keep": return .cameraKeep
        case "camera.corrective": return .cameraCorrectiveAction
        case "camera.fallback": return .cameraFallback
        case "camera.explanation": return .cameraCorrectiveAction
        case "camera.lens-switching": return .cameraLensSwitching
        case "camera.resuming": return .cameraResuming
        case "camera.eco": return .cameraEco
        default: return .cameraSeeking
        }
    }
}

private struct SETCameraStatusOverlay: View {
    let canvasSize: CGSize
    let title: SETCopyKey
    let action: SETCopyKey?
    let tallyMode: SETTallyMode
    let timecode: String
    let onAction: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let railHeight = SETCameraCoachMetric.liveRailHeight(
            canvasSize: canvasSize,
            isAccessibilityType: dynamicTypeSize.isAccessibilitySize,
            isExpanded: false
        )
        let railWidth = SETCameraCoachMetric.liveRailWidth(
            canvasSize: canvasSize,
            isAccessibilityType: dynamicTypeSize.isAccessibilitySize
        )

        VStack(spacing: 0) {
            SETCameraHUDHeader(
                tallyMode: tallyMode,
                dimmed: true,
                timecode: timecode,
                showsECO: false
            )

            Spacer()

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: SETSpacing.x2) {
                    Text(title.localizedTextKey)
                        .font(SETTypography.font(.hudMono, size: SETTypographySize.body))
                        .foregroundStyle(.setTextPrimary)
                        .accessibilityIdentifier(CameraOverlayAccessibilityID.observation)

                    if let action {
                        Button(action: onAction) {
                            Text(action.localizedTextKey)
                                .font(SETTypography.font(.display, size: SETTypographySize.title))
                                .fontWeight(.bold)
                                .foregroundStyle(.setTextPrimary)
                                .frame(minWidth: SETComponentMetric.minimumHitTarget,
                                       minHeight: SETComponentMetric.minimumHitTarget,
                                       alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(CameraOverlayAccessibilityID.action)
                    }
                }
                .padding(.horizontal, SETCameraCoachMetric.commandHorizontalInset)
                .padding(.vertical, SETCameraCoachMetric.commandVerticalInset)
                .frame(width: railWidth, height: railHeight, alignment: .topLeading)
                .background(.setHUDScrim)
                .overlay(alignment: .topLeading) {
                    Rectangle().fill(.setOrange).frame(width: SETStroke.standard)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, SETCameraCoachMetric.liveRailHorizontalInset)
            .padding(.bottom, SETCameraCoachMetric.liveRailBottomInset)
        }
        .accessibilityIdentifier(CameraOverlayAccessibilityID.surface)
    }
}

private enum SETPauseReviewMode: Equatable {
    case loading
    case success
    case empty
    case failure
}

struct SETPauseSnapshotFrame: View {
    let snapshot: LatestFrameEvidenceStore.AcceptedSnapshot

    var body: some View {
        Group {
            if let displayImage = snapshot.displayImage {
                Image(decorative: displayImage,
                      scale: 1,
                      // LatestFrameEvidenceStore renders the accepted buffer
                      // with its EXIF orientation exactly once.
                      orientation: .up)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                Color.setWarmWhite
            }
        }
        .accessibilityHidden(true)
    }
}

private enum SETLocalizedCopy {
    fileprivate static func resolvedBundle(for locale: Locale) -> Bundle {
        let languageCode = locale.language.languageCode?.identifier ?? "en"
        for candidate in [languageCode, locale.identifier] {
            if let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return .main
    }

    static func string(_ key: SETCopyKey, locale: Locale) -> String {
        resolvedBundle(for: locale).localizedString(forKey: key.rawValue, value: key.rawValue, table: nil)
    }
}

enum SETLocalizedPauseCopy {
    static func take(number: Int, locale: Locale) -> String {
        formatted(key: "set.take.counter.dynamic", number: number, locale: locale)
    }

    static func title(number: Int, locale: Locale) -> String {
        formatted(key: "set.pause.title.dynamic", number: number, locale: locale)
    }

    static func summary(for critique: PauseCritiquePresentation?, locale: Locale) -> String {
        guard let critique else {
            return SETLocalizedCopy.string(.pauseNote, locale: locale)
        }
        if let action = critique.actions.first {
            return SETLocalizedCopy.string(
                SETCameraCopy.actionKey(for: action.semanticActionType),
                locale: locale
            )
        }
        let fallbackKey: SETCopyKey = switch critique.verdict {
        case .good: .cameraKeep
        case .mixed, .needsFix: .pauseNoAction
        }
        return SETLocalizedCopy.string(fallbackKey, locale: locale)
    }

    private static func formatted(key: String, number: Int, locale: Locale) -> String {
        let bundle = SETLocalizedCopy.resolvedBundle(for: locale)
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        return String(format: format, locale: locale, arguments: [number])
    }
}

private struct SETPauseReviewOverlay: View {
    let mode: SETPauseReviewMode
    let timecode: String
    let critique: PauseCritiquePresentation?
    let eventLedger: SETMotionEventLedger
    let reduceMotion: Bool
    let markerRegion: NormalizedRect?
    let acceptedFramePixelSize: CGSize?
    let acceptedFrameOrientation: CGImagePropertyOrientation
    let acceptedFrameIsMirrored: Bool
    let failureReason: CameraPauseFailureReason?
    let snapshotID: String
    let takeNumber: Int
    var cutMarkController: SETPauseCutMarkController? = nil
    var onCutMark: (() -> Void)? = nil
    let onResume: () -> Void

    @Environment(\.locale) private var locale

    init(
        mode: SETPauseReviewMode,
        timecode: String,
        critique: PauseCritiquePresentation?,
        eventLedger: SETMotionEventLedger,
        reduceMotion: Bool,
        markerRegion: NormalizedRect?,
        acceptedFramePixelSize: CGSize? = nil,
        acceptedFrameOrientation: CGImagePropertyOrientation = .up,
        acceptedFrameIsMirrored: Bool = false,
        failureReason: CameraPauseFailureReason? = nil,
        snapshotID: String,
        takeNumber: Int,
        cutMarkController: SETPauseCutMarkController? = nil,
        onCutMark: (() -> Void)? = nil,
        onResume: @escaping () -> Void
    ) {
        self.mode = mode
        self.timecode = timecode
        self.critique = critique
        self.eventLedger = eventLedger
        self.reduceMotion = reduceMotion
        self.markerRegion = markerRegion
        self.acceptedFramePixelSize = acceptedFramePixelSize
        self.acceptedFrameOrientation = acceptedFrameOrientation
        self.acceptedFrameIsMirrored = acceptedFrameIsMirrored
        self.failureReason = failureReason
        self.snapshotID = snapshotID
        self.takeNumber = takeNumber
        self.cutMarkController = cutMarkController
        self.onCutMark = onCutMark
        self.onResume = onResume
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: SETCameraCoachMetric.topControlRowHeight)

                    pauseHeader
                        .frame(height: SETCameraCoachMetric.pauseHeaderHeight)

                    Spacer(minLength: 0)

                    reviewBand
                        .frame(minHeight: SETCameraCoachMetric.pauseBandMinimumHeight,
                               maxHeight: SETCameraCoachMetric.pauseBandMaximumHeight)
                }

                if mode == .success,
                   let markerFrame = markerFrame(in: proxy.size) {
                    SETMarkerDrawGuide(
                        kind: .outline,
                        eventID: "\(snapshotID).pause-marker",
                        color: .setWarmWhite,
                        eventLedger: eventLedger
                    )
                    .frame(width: markerFrame.width,
                           height: markerFrame.height)
                    .position(x: markerFrame.midX, y: markerFrame.midY)
                    .accessibilityHidden(true)
                }

                SETAccessibilityIdentifierProbe(identifier: "camera_coach_pause_review")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var pauseHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: SETSpacing.x3) {
                SETTallyBadge(mode: .standby)
                SETTimecodeView(value: timecode, showsFrames: true)
                Spacer(minLength: SETSpacing.x2)
                if takeNumber > 0 {
                    Text(takeLabel)
                        .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                        .foregroundStyle(.setTextPrimary)
                }
                SETPauseCutMark(
                    eventID: cutMarkEventID,
                    eventLedger: eventLedger,
                    reduceMotion: reduceMotion,
                    controller: cutMarkController,
                    onTrigger: onCutMark
                )
            }

            VStack(alignment: .leading, spacing: SETSpacing.x1) {
                HStack(spacing: SETSpacing.x3) {
                    SETTallyBadge(mode: .standby)
                    SETTimecodeView(value: timecode, showsFrames: true)
                }

                HStack(spacing: SETSpacing.x3) {
                    Spacer(minLength: 0)
                    if takeNumber > 0 {
                        Text(takeLabel)
                            .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                            .foregroundStyle(.setTextPrimary)
                    }
                    SETPauseCutMark(
                        eventID: cutMarkEventID,
                        eventLedger: eventLedger,
                        reduceMotion: reduceMotion,
                        controller: cutMarkController,
                        onTrigger: onCutMark
                    )
                }
            }
        }
        .padding(.horizontal, SETCameraCoachMetric.headerControlHorizontalInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(.setInk.opacity(SETProductionPauseReviewMetric.headerOpacity))
    }

    private var reviewBand: some View {
        SETPauseReviewBand(
            title: titleText,
            detail: detailText,
            isLoading: mode == .loading,
            actionTitle: mode == .failure ? failureActionKey : .actionMoreTake,
            loadingEventID: "\(snapshotID).pause-loading",
            eventLedger: eventLedger,
            reduceMotion: reduceMotion,
            actionAccessibilityIdentifier: "camera_coach_pause_action",
            onAction: onResume
        )
    }

    private var titleKey: SETCopyKey {
        switch mode {
        case .loading: return .pauseLoading
        case .success: return .pauseTitle
        case .empty: return .pauseEmpty
        case .failure: return failureTitleKey
        }
    }

    private var titleText: String {
        guard mode == .success else {
            return SETLocalizedCopy.string(titleKey, locale: locale)
        }
        return SETLocalizedPauseCopy.title(number: takeNumber, locale: locale)
    }

    private var detailText: String? {
        switch mode {
        case .loading:
            return nil
        case .success:
            return SETLocalizedPauseCopy.summary(for: critique, locale: locale)
        case .empty:
            return nil
        case .failure:
            return SETLocalizedCopy.string(failureDetailKey, locale: locale)
        }
    }

    private var takeLabel: String {
        SETLocalizedPauseCopy.take(number: takeNumber, locale: locale)
    }

    private var cutMarkEventID: String {
        "\(snapshotID).take-\(takeNumber).cut"
    }

    private var failureTitleKey: SETCopyKey {
        switch failureReason {
        case .noAcceptedEvidence: return .pauseFailureNoEvidenceTitle
        case .displayRenderFailed: return .pauseFailureRenderTitle
        case .pipelineUnavailable: return .pauseFailurePipelineTitle
        case .timeout: return .pauseFailureTimeoutTitle
        case nil: return .pauseFailure
        }
    }

    private var failureDetailKey: SETCopyKey {
        switch failureReason {
        case .noAcceptedEvidence: return .pauseFailureNoEvidenceDetail
        case .displayRenderFailed: return .pauseFailureRenderDetail
        case .pipelineUnavailable: return .pauseFailurePipelineDetail
        case .timeout: return .pauseFailureTimeoutDetail
        case nil: return .pauseFailureRecovery
        }
    }

    private var failureActionKey: SETCopyKey {
        .pauseFailureRecovery
    }

    private func markerFrame(in canvasSize: CGSize) -> CGRect? {
        guard let region = markerRegion else { return nil }
        if let acceptedFramePixelSize {
            guard let mapped = SETAcceptedFrameRegionMapper.map(
                region,
                sourcePixelSize: acceptedFramePixelSize,
                orientation: acceptedFrameOrientation,
                canvasSize: canvasSize,
                isMirrored: acceptedFrameIsMirrored
            ) else { return nil }
            return centeredMarkerFrame(at: mapped.midX, y: mapped.midY, in: canvasSize)
        }

        // Deterministic DEBUG fixtures have no accepted image envelope. Keep
        // their explicit normalized geometry isolated from the runtime path.
        let centerX = (region.x + region.width * 0.5) * canvasSize.width
        let centerY = (region.y + region.height * 0.5) * canvasSize.height
        return centeredMarkerFrame(at: centerX, y: centerY, in: canvasSize)
    }

    private func centeredMarkerFrame(at centerX: CGFloat,
                                     y centerY: CGFloat,
                                     in canvasSize: CGSize) -> CGRect {
        let halfWidth = SETCameraCoachMetric.pauseMarkerWidth * 0.5
        let halfHeight = SETCameraCoachMetric.pauseMarkerHeight * 0.5
        let clampedCenter = CGPoint(
            x: min(max(centerX, halfWidth), max(halfWidth, canvasSize.width - halfWidth)),
            y: min(max(centerY, halfHeight), max(halfHeight, canvasSize.height - halfHeight))
        )
        return CGRect(
            x: clampedCenter.x - halfWidth,
            y: clampedCenter.y - halfHeight,
            width: SETCameraCoachMetric.pauseMarkerWidth,
            height: SETCameraCoachMetric.pauseMarkerHeight
        )
    }
}

private struct SETAccessibilityIdentifierProbe: View {
    let identifier: String

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(identifier)
            .allowsHitTesting(false)
    }
}

private enum SETLiveMonitorFixtureMetric {
    static let timecode = "00:03:18:12"
    static let markerCenterX: CGFloat = 0.64
    static let markerCenterY: CGFloat = 0.62
}

private enum SETProductionPauseReviewMetric {
    static let headerOpacity = 0.62
}
