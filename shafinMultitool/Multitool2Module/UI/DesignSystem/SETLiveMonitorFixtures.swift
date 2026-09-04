import SwiftUI

/// DEBUG-only fixture composition for the two portrait screens that must be
/// judged against the live-monitor grammar, not against poster layouts.
struct SETCameraFixtureScreen: View {
    let fixtureID: String

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.setReduceTransparencyOverride) private var reduceTransparencyOverride

    private var isTransparencyReduced: Bool {
        reduceTransparencyOverride ?? reduceTransparency
    }

    private var markerKind: SETMarkerKind? {
        switch fixtureID {
        case "camera.corrective": .arrow
        case "camera.keep", "camera.explanation": .outline
        default: nil
        }
    }

    private var markerLabel: SETCopyKey {
        switch fixtureID {
        case "camera.corrective": .cameraCorrectiveAction
        case "camera.keep": .cameraKeep
        case "camera.explanation": .cameraExplanation
        case "camera.fallback": .cameraFallback
        case "camera.interrupted": .cameraInterrupted
        case "camera.failed": .cameraFailed
        case "camera.lens-switching": .cameraLensSwitching
        case "camera.resuming": .cameraResuming
        case "camera.starting": .cameraPreparing
        default: .cameraSeeking
        }
    }

    private var tallyMode: SETTallyMode {
        ["camera.starting", "camera.interrupted", "camera.failed", "camera.resuming", "camera.lens-switching"].contains(fixtureID)
            ? .standby
            : .live
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                SETBundledImage.image(named: "SETCameraFrame")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                if let markerKind {
                    SETMarkerDrawGuide(kind: markerKind, eventID: fixtureID, color: .setWarmWhite)
                        .frame(
                            width: SETLiveMonitorMetric.markerWidth,
                            height: SETLiveMonitorMetric.markerHeight
                        )
                        .position(
                            x: proxy.size.width * SETLiveMonitorMetric.correctiveMarkerCenterX,
                            y: proxy.size.height * SETLiveMonitorMetric.correctiveMarkerCenterY
                        )
                }

                VStack(spacing: 0) {
                    liveHeader
                    Spacer(minLength: 0)
                    liveCommand
                }
            }
            .clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(markerLabel.localizedTextKey))
        }
        .background(.setInk)
        .accessibilityIdentifier(fixtureID)
    }

    private var liveHeader: some View {
        HStack(spacing: SETSpacing.x3) {
            SETTallyBadge(
                mode: tallyMode,
                pulses: false,
                dimmed: fixtureID == "camera.fallback"
            )
            SETTimecodeView(value: "00:03:18:12", showsFrames: true)
            Spacer(minLength: SETSpacing.x2)
            if fixtureID == "camera.eco" {
                SETTallyBadge(mode: .eco)
            }
        }
        .padding(.horizontal, SETSpacing.x4)
        .frame(height: SETLiveMonitorMetric.headerHeight)
        .background(chromeSurface)
    }

    private var liveCommand: some View {
        HStack(alignment: .bottom, spacing: SETSpacing.x4) {
            Text(markerLabel.localizedTextKey)
                    .font(SETTypography.font(.hudMono, size: SETTypographySize.body))
                .foregroundStyle(fixtureID == "camera.corrective" ? .setOrange : .setTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(SETCopyKey.cameraLensCurrent.localizedTextKey)
                .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                .foregroundStyle(.setTextPrimary)
                .accessibilityIdentifier("camera-current-lens")
        }
        .padding(.horizontal, SETSpacing.x4)
        .padding(.top, SETSpacing.x4)
        .padding(.bottom, SETSpacing.x6)
        .background(chromeSurface)
        .overlay(alignment: .topLeading) {
            if fixtureID == "camera.fallback" {
                Rectangle()
                    .fill(.setWarmWhite)
                    .frame(width: SETStroke.standard)
            }
        }
    }

    private var chromeSurface: Color {
        isTransparencyReduced
            ? .setSurfaceSolid
            : .setInk.opacity(SETLiveMonitorMetric.chromeOpacity)
    }
}

/// A take review keeps the frozen frame as the hero and compresses the
/// decision into a lower band. It deliberately has no poster-sized headline.
struct SETPauseFixtureScreen: View {
    let fixtureID: String

    private var title: SETCopyKey {
        switch fixtureID {
        case "camera.pause-loading": .pauseLoading
        case "camera.pause-empty": .pauseEmpty
        case "camera.pause-failure": .pauseFailure
        default: .pauseTitle
        }
    }

    private var isReviewReady: Bool {
        fixtureID == "camera.pause-success"
    }

    var body: some View {
        GeometryReader { proxy in
            let previewHeight = proxy.size.height * SETPauseReviewMetric.previewFraction
            VStack(spacing: 0) {
                reviewFrame(width: proxy.size.width, height: previewHeight)
                reviewBand
                    .frame(height: max(0, proxy.size.height - previewHeight))
            }
        }
        .background(.setInk)
        .accessibilityIdentifier(fixtureID)
    }

    private func reviewFrame(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            SETBundledImage.image(named: "SETCameraFrame")
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipped()

            HStack {
                Text(SETCopyKey.takeCounter.localizedTextKey)
                    .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                    .foregroundStyle(.setTextPrimary)
                Spacer()
                Text(SETCopyKey.pauseCutMark.localizedTextKey)
                    .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                    .foregroundStyle(.setOrange)
            }
            .padding(SETSpacing.x4)
            .background(Color.setInk.opacity(SETPauseReviewMetric.headerOpacity))

            if isReviewReady {
                SETMarkerDrawGuide(kind: .outline, eventID: fixtureID, color: .setWarmWhite)
                    .frame(
                        width: SETPauseReviewMetric.markerWidth,
                        height: SETPauseReviewMetric.markerHeight
                    )
                    .position(
                        x: width * SETPauseReviewMetric.markerCenterX,
                        y: height * SETPauseReviewMetric.markerCenterY
                    )
            }
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(isReviewReady ? SETCopyKey.pauseMarker.localizedTextKey : title.localizedTextKey))
    }

    private var reviewBand: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x2) {
            HStack(alignment: .firstTextBaseline, spacing: SETSpacing.x3) {
                Text(title.localizedTextKey)
                    .font(SETTypography.font(.hudMono, size: SETTypographySize.body))
                    .fontWeight(.bold)
                    .foregroundStyle(.setTextPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: SETSpacing.x2)
            }

            if isReviewReady {
                Text(SETCopyKey.pauseNote.localizedTextKey)
                    .font(SETTypography.uiBodyFont())
                    .foregroundStyle(.setTextSecondary)
                    .lineLimit(2)
            }

            SETDigitalAction(title: fixtureID == "camera.pause-failure" ? .pauseFailureRecovery : .actionMoreTake)
        }
        .padding(SETSpacing.x4)
        .background(.setInk)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.setHairline)
                .frame(height: SETStroke.hairline)
        }
    }
}

private enum SETLiveMonitorMetric {
    static let headerHeight: CGFloat = 56
    static let chromeOpacity = 0.66
    static let registrationInset: CGFloat = 12
    static let registrationOpacity = 0.72
    static let markerWidth: CGFloat = 102
    static let markerHeight: CGFloat = 62
    // The tail starts alongside the compact lower command; the head points at
    // the region the operator should reframe. It never points into empty space.
    static let correctiveMarkerCenterX: CGFloat = 0.62
    static let correctiveMarkerCenterY: CGFloat = 0.66
}

private enum SETPauseReviewMetric {
    // The lower band contains a title, one editorial note and one decision —
    // no spare poster field. The frozen take gets the remaining 78%.
    static let previewFraction: CGFloat = 0.78
    static let headerOpacity = 0.56
    static let registrationOpacity = 0.56
    static let markerWidth: CGFloat = 142
    static let markerHeight: CGFloat = 176
    static let markerCenterX: CGFloat = 0.76
    static let markerCenterY: CGFloat = 0.58
}
