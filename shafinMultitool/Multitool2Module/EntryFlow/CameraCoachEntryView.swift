import SwiftUI
import UIKit

enum CameraCoachEntryCopy {
    static let introTitleKey = SETCopyKey.entryPoster
    static let introBodyKey = SETCopyKey.entryBody
    static let introActionKey = SETCopyKey.actionMain
    static let permissionContextTitleKey = SETCopyKey.permissionTitle
    static let permissionContextBodyKey = SETCopyKey.permissionBody
    static let localProcessingKey = SETCopyKey.entryLocalProcessing
    static let permissionContextActionKey = SETCopyKey.permissionContinue
    static let blockedBodyKey = SETCopyKey.entryBlockedBody
    static let settingsActionKey = SETCopyKey.openSettings
    static let recheckActionKey = SETCopyKey.checkAgain
    static let settingsFallbackKey = SETCopyKey.entrySettingsFallback

    // String accessors preserve the existing test-facing API while resolving
    // visible copy through the String Catalog at render time.
    static var introTitle: String { introTitleKey.localizedString }
    static var introBody: String { introBodyKey.localizedString }
    static var introAction: String { introActionKey.localizedString }
    static var permissionContextTitle: String { permissionContextTitleKey.localizedString }
    static var permissionContextBody: String { permissionContextBodyKey.localizedString }
    static var localProcessingSentence: String { localProcessingKey.localizedString }
    static var permissionContextAction: String { permissionContextActionKey.localizedString }
    static var deniedTitle: String { SETCopyKey.blockedDenied.localizedString }
    static var restrictedTitle: String { SETCopyKey.blockedRestricted.localizedString }
    static var unavailableTitle: String { SETCopyKey.blockedUnavailable.localizedString }
    static var unknownTitle: String { SETCopyKey.blockedUnknown.localizedString }
    static var blockedBody: String { blockedBodyKey.localizedString }
    static var settingsAction: String { settingsActionKey.localizedString }
    static var recheckAction: String { recheckActionKey.localizedString }
    static var settingsFallback: String { settingsFallbackKey.localizedString }
}

enum CameraCoachEntryAccessibilityID {
    static let resolvingRoot = "camera-coach-entry-resolving"
    static let introRoot = "camera-coach-entry-intro"
    static let permissionContextRoot = "camera-coach-entry-permission-context"
    static let requestingRoot = "camera-coach-entry-requesting"
    static let readyRoot = "camera-coach-entry-ready"
    static let deniedRoot = "camera-coach-entry-blocked-denied"
    static let restrictedRoot = "camera-coach-entry-blocked-restricted"
    static let unavailableRoot = "camera-coach-entry-blocked-unavailable"
    static let unknownRoot = "camera-coach-entry-blocked-unknown"

    static let introTitle = "camera-coach-entry-intro-title"
    static let introBody = "camera-coach-entry-intro-body"
    static let permissionContextTitle = "camera-coach-entry-permission-context-title"
    static let permissionContextBody = "camera-coach-entry-permission-context-body"
    static let permissionContextLocalProcessing = "camera-coach-entry-local-processing"
    static let blockedTitle = "camera-coach-entry-blocked-title"
    static let blockedBody = "camera-coach-entry-blocked-body"
    static let settingsFallback = "camera-coach-entry-settings-fallback"
    static let posterRail = "camera-coach-entry-poster-rail"
    static let phaseColumn = "camera-coach-entry-phase-column"

    static let openCameraAction = "camera-coach-entry-open-camera"
    static let continueAction = "camera-coach-entry-continue"
    static let openSettingsAction = "camera-coach-entry-open-settings"
    static let recheckAction = "camera-coach-entry-recheck"
}

enum CameraCoachEntryVisualPolicy {
    static let sourceMarkers = [
        "set-os-two-registers",
        "poster-typography-bilingual",
        "single-orange-accent-wcag",
        "mono-hud",
        "glass-mark-annotation",
        "leader-countdown",
        "state-table-camera-coach",
        "motion-respects-reduce-motion"
    ]
}

private enum EntryMarkerPlacement: Equatable {
    case action
    case title
}

struct CameraCoachEntryView: View {
    let phase: CameraCoachEntryPhase
    let onOpenCamera: () -> Void
    let onContinuePermissionRequest: () -> Void
    let onRecheckCameraAccess: () -> Void
    let markerEventID: String?
    let markerDrawProgress: CGFloat

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle)
    private var entryDisplayLargeSize: CGFloat = SETTypographySize.displayLarge
    @ScaledMetric(relativeTo: .title)
    private var entryDisplayCompactSize: CGFloat = SETTypographySize.displayMedium
    @State private var showsSettingsFallback = false

    init(
        phase: CameraCoachEntryPhase,
        onOpenCamera: @escaping () -> Void,
        onContinuePermissionRequest: @escaping () -> Void,
        onRecheckCameraAccess: @escaping () -> Void,
        markerEventID: String? = nil,
        markerDrawProgress: CGFloat = 1
    ) {
        self.phase = phase
        self.onOpenCamera = onOpenCamera
        self.onContinuePermissionRequest = onContinuePermissionRequest
        self.onRecheckCameraAccess = onRecheckCameraAccess
        self.markerEventID = markerEventID
        self.markerDrawProgress = markerDrawProgress
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    Color.setInk
                        .ignoresSafeArea()

                    editorialContent(in: proxy)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    SETRegistrationMarks(color: .setWarmWhite, corner: .topLeading)
                        .padding(.horizontal, proxy.safeAreaInsets.leading + SETSpacing.x4)
                        .padding(.vertical, proxy.safeAreaInsets.top + SETSpacing.x4)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(Self.rootAccessibilityIdentifier(for: phase))

            SETPrivacyEntryButton(accessibilityID: "camera_entry_privacy")
                .frame(maxWidth: .infinity)
                .background(.setInk)
        }
        .background(.setInk)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func editorialContent(in proxy: GeometryProxy) -> some View {
        let availableSize = CGSize(
            width: max(0, proxy.size.width - proxy.safeAreaInsets.leading - proxy.safeAreaInsets.trailing),
            height: max(0, proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom)
        )
        let layout = SETEntryLayout.resolve(
            container: availableSize,
            accessibilityType: dynamicTypeSize.isAccessibilitySize
        )
        let horizontalPadding = layout.contentPadding
        let sectionWidth = min(
            SETComponentMetric.gallerySectionMaxWidth,
            max(0, availableSize.width - horizontalPadding * 2)
        )
        let splitRailWidth = min(
            sectionWidth * layout.landscapeRailFraction,
            max(0, sectionWidth - layout.columnSpacing - SETComponentMetric.entryLandscapeMinimumPhaseWidth)
        )
        let splitPhaseWidth = max(0, sectionWidth - splitRailWidth - layout.columnSpacing)

        ScrollView(.vertical) {
            Group {
                if layout.isSplit {
                    HStack(alignment: .top, spacing: layout.columnSpacing) {
                        posterColumn
                            .frame(width: splitRailWidth, alignment: .leading)
                        phaseColumnContainer(for: layout)
                            .frame(width: splitPhaseWidth, alignment: .leading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: layout.columnSpacing) {
                        posterColumn
                        phaseColumnContainer(for: layout)
                    }
                }
            }
            .frame(width: sectionWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, layout.contentPadding)
        }
        .scrollIndicators(.hidden)
    }

    private var posterColumn: some View {
        HStack(alignment: .center, spacing: SETSpacing.x3) {
            Text(SETCopyKey.modeCamera.localizedTextKey)
                .font(SETTypography.font(.hudMono, size: SETTypographySize.label))
                .tracking(SETTypographySize.label * 0.05)
                .foregroundStyle(.setTextSecondary)

            Rectangle()
                .fill(.setHairline)
                .frame(maxWidth: .infinity, minHeight: SETStroke.hairline, maxHeight: SETStroke.hairline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(SETCopyKey.modeCamera.localizedTextKey))
        .accessibilityIdentifier(CameraCoachEntryAccessibilityID.posterRail)
    }

    @ViewBuilder
    private func phaseColumn(for layout: SETEntryLayout) -> some View {
        switch phase {
        case .resolving:
            statusPanel(
                title: .entryResolving,
                rootIdentifier: CameraCoachEntryAccessibilityID.resolvingRoot,
                accessibilityLabel: .entryResolving,
                markerKind: nil,
                layout: layout
            )
        case .requesting:
            statusPanel(
                title: .entryRequesting,
                rootIdentifier: CameraCoachEntryAccessibilityID.requestingRoot,
                accessibilityLabel: .entryRequesting,
                markerKind: nil,
                layout: layout
            )
        case .ready:
            statusPanel(
                title: .entryReady,
                rootIdentifier: CameraCoachEntryAccessibilityID.readyRoot,
                accessibilityLabel: .entryReady,
                markerKind: .bracket,
                layout: layout
            )
        case .intro:
            entryPanel(
                title: CameraCoachEntryCopy.introTitleKey,
                titleIdentifier: CameraCoachEntryAccessibilityID.introTitle,
                body: CameraCoachEntryCopy.introBodyKey,
                bodyIdentifier: CameraCoachEntryAccessibilityID.introBody,
                markerKind: .underline,
                actionTitle: CameraCoachEntryCopy.introActionKey,
                actionIdentifier: CameraCoachEntryAccessibilityID.openCameraAction,
                actionLabel: .accessibilityOpenCamera,
                actionHint: .entryHelper,
                action: onOpenCamera,
                layout: layout
            )
        case .permissionContext:
            entryPanel(
                title: CameraCoachEntryCopy.permissionContextTitleKey,
                titleIdentifier: CameraCoachEntryAccessibilityID.permissionContextTitle,
                body: CameraCoachEntryCopy.permissionContextBodyKey,
                bodyIdentifier: CameraCoachEntryAccessibilityID.permissionContextBody,
                supplemental: CameraCoachEntryCopy.localProcessingKey,
                supplementalIdentifier: CameraCoachEntryAccessibilityID.permissionContextLocalProcessing,
                markerKind: .underline,
                actionTitle: CameraCoachEntryCopy.permissionContextActionKey,
                actionIdentifier: CameraCoachEntryAccessibilityID.continueAction,
                actionLabel: .accessibilityContinue,
                actionHint: .permissionTitle,
                action: onContinuePermissionRequest,
                layout: layout
            )
        case .blocked(let reason):
            blockedPanel(for: reason, layout: layout)
        }
    }

    private func phaseColumnContainer(for layout: SETEntryLayout) -> some View {
        phaseColumn(for: layout)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(CameraCoachEntryAccessibilityID.phaseColumn)
    }

    private func statusPanel(
        title: SETCopyKey,
        rootIdentifier: String,
        accessibilityLabel: SETCopyKey,
        markerKind: SETMarkerKind?,
        layout: SETEntryLayout
    ) -> some View {
        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            Text(title.localizedTextKey)
                .font(SETTypography.uiBodyFont(weight: .semibold))
                .foregroundStyle(.setTextPrimary)
                .accessibilityLabel(Text(accessibilityLabel.localizedTextKey))

            if let markerKind {
                markerRail(kind: markerKind)
            }
        }
        .accessibilityIdentifier(rootIdentifier)
    }

    @ViewBuilder
    private func entryPanel(
        title: SETCopyKey,
        titleIdentifier: String,
        body: SETCopyKey,
        bodyIdentifier: String,
        supplemental: SETCopyKey? = nil,
        supplementalIdentifier: String? = nil,
        markerKind: SETMarkerKind,
        markerPlacement: EntryMarkerPlacement = .action,
        actionTitle: SETCopyKey,
        actionIdentifier: String,
        actionLabel: SETCopyKey,
        actionHint: SETCopyKey,
        action: @escaping () -> Void,
        secondaryAction: (() -> Void)? = nil,
        secondaryTitle: SETCopyKey? = nil,
        secondaryIdentifier: String? = nil,
        footer: SETCopyKey? = nil,
        layout: SETEntryLayout
    ) -> some View {
        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            if markerPlacement == .title {
                entryTitle(
                    title,
                    identifier: titleIdentifier,
                    markerKind: markerKind,
                    layout: layout
                )
            } else {
                entryTitle(title, identifier: titleIdentifier, layout: layout)
            }

            Text(body.localizedTextKey)
                .font(SETTypography.uiBodyFont())
                .foregroundStyle(.setTextSecondary)
                .lineSpacing(SETSpacing.x1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(bodyIdentifier)

            if let supplemental, let supplementalIdentifier {
                Text(supplemental.localizedTextKey)
                    .font(SETTypography.uiLabelFont())
                    .foregroundStyle(.setTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(supplementalIdentifier)
            }

            VStack(alignment: .leading, spacing: SETSpacing.x2) {
                SETDigitalAction(title: actionTitle, helper: .entryHelper, action: action)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(actionIdentifier)
                    .accessibilityLabel(Text(actionLabel.localizedTextKey))
                    .accessibilityHint(Text(actionHint.localizedTextKey))

                if markerPlacement == .action {
                    markerRail(kind: markerKind)
                }
            }

            if let secondaryAction,
               let secondaryTitle,
               let secondaryIdentifier {
                Button(action: secondaryAction) {
                    SETCommandLabel(key: secondaryTitle, color: .setTextSecondary)
                        .frame(minHeight: SETComponentMetric.minimumHitTarget, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(secondaryIdentifier)
                .accessibilityLabel(Text(secondaryTitle.localizedTextKey))
                .accessibilityHint(Text(SETCopyKey.accessibilityRecheck.localizedTextKey))
            }

            if let footer {
                Text(footer.localizedTextKey)
                    .font(SETTypography.uiLabelFont())
                    .foregroundStyle(.setTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(CameraCoachEntryAccessibilityID.settingsFallback)
                    .accessibilityLabel(Text(footer.localizedTextKey))
            }
        }
    }

    @ViewBuilder
    private func entryTitle(
        _ title: SETCopyKey,
        identifier: String,
        markerKind: SETMarkerKind? = nil,
        layout: SETEntryLayout
    ) -> some View {
        let titleText = Text(title.localizedTextKey)
            .font(
                SETTypography.font(
                    .display,
                    size: layout.isCompactHeight ? entryDisplayCompactSize : entryDisplayLargeSize
                )
            )
            .fontWeight(.bold)
            .minimumScaleFactor(0.60)
            .foregroundStyle(.setTextPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifier)

        if let markerKind {
            VStack(alignment: .leading, spacing: SETSpacing.x2) {
                titleText
                // Keep the single orange punctuation in its own rail. This
                // reserves space below the glyphs, so a marker can never
                // become an outline that clips a localized title.
                markerRail(kind: markerKind)
            }
        } else { titleText }
    }

    private func markerRail(kind: SETMarkerKind) -> some View {
        GlassMarkGuide(kind: kind, color: .setOrange, drawProgress: markerDrawProgress)
        .frame(
            maxWidth: .infinity,
            minHeight: SETComponentMetric.entryMarkerRailHeight,
            maxHeight: SETComponentMetric.entryMarkerRailHeight,
            alignment: .leading
        )
        .animation(
            reduceMotion
                ? .easeOut(duration: SETMotion.reducedMotionCrossfadeDuration)
                : .linear(duration: SETMotion.markerDrawDuration),
            value: markerDrawProgress
        )
    }

    @ViewBuilder
    private func blockedPanel(
        for reason: CameraCoachCameraBlockReason,
        layout: SETEntryLayout
    ) -> some View {
        let presentation = blockedPresentation(for: reason)
        entryPanel(
            title: presentation.title,
            titleIdentifier: CameraCoachEntryAccessibilityID.blockedTitle,
            body: CameraCoachEntryCopy.blockedBodyKey,
            bodyIdentifier: CameraCoachEntryAccessibilityID.blockedBody,
            markerKind: .underline,
            markerPlacement: .title,
            actionTitle: presentation.primaryTitle,
            actionIdentifier: presentation.primaryIdentifier,
            actionLabel: presentation.primaryLabel,
            actionHint: presentation.primaryHint,
            action: presentation.primaryAction,
            secondaryAction: reason == .denied ? onRecheckCameraAccess : nil,
            secondaryTitle: reason == .denied ? CameraCoachEntryCopy.recheckActionKey : nil,
            secondaryIdentifier: reason == .denied ? CameraCoachEntryAccessibilityID.recheckAction : nil,
            footer: showsSettingsFallback ? CameraCoachEntryCopy.settingsFallbackKey : nil,
            layout: layout
        )
    }

    private func blockedPresentation(
        for reason: CameraCoachCameraBlockReason
    ) -> BlockedPresentation {
        switch reason {
        case .denied:
            return BlockedPresentation(
                title: .blockedDenied,
                primaryTitle: .openSettings,
                primaryIdentifier: CameraCoachEntryAccessibilityID.openSettingsAction,
                primaryLabel: .accessibilityOpenSettings,
                primaryHint: .accessibilityOpenSettings,
                primaryAction: openSettings
            )
        case .restricted:
            return BlockedPresentation(
                title: .blockedRestricted,
                primaryTitle: .checkAgain,
                primaryIdentifier: CameraCoachEntryAccessibilityID.recheckAction,
                primaryLabel: .accessibilityRecheck,
                primaryHint: .accessibilityRecheck,
                primaryAction: onRecheckCameraAccess
            )
        case .unavailable:
            return BlockedPresentation(
                title: .blockedUnavailable,
                primaryTitle: .checkAgain,
                primaryIdentifier: CameraCoachEntryAccessibilityID.recheckAction,
                primaryLabel: .accessibilityRecheck,
                primaryHint: .accessibilityRecheck,
                primaryAction: onRecheckCameraAccess
            )
        case .unknown:
            return BlockedPresentation(
                title: .blockedUnknown,
                primaryTitle: .checkAgain,
                primaryIdentifier: CameraCoachEntryAccessibilityID.recheckAction,
                primaryLabel: .accessibilityRecheck,
                primaryHint: .accessibilityRecheck,
                primaryAction: onRecheckCameraAccess
            )
        }
    }

    private func openSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            showsSettingsFallback = true
            return
        }

        openURL(settingsURL) { accepted in
            if !accepted {
                showsSettingsFallback = true
            }
        }
    }

    static func rootAccessibilityIdentifier(for phase: CameraCoachEntryPhase) -> String {
        switch phase {
        case .resolving:
            return CameraCoachEntryAccessibilityID.resolvingRoot
        case .requesting:
            return CameraCoachEntryAccessibilityID.requestingRoot
        case .ready:
            return CameraCoachEntryAccessibilityID.readyRoot
        case .intro:
            return CameraCoachEntryAccessibilityID.introRoot
        case .permissionContext:
            return CameraCoachEntryAccessibilityID.permissionContextRoot
        case .blocked(let reason):
            switch reason {
            case .denied:
                return CameraCoachEntryAccessibilityID.deniedRoot
            case .restricted:
                return CameraCoachEntryAccessibilityID.restrictedRoot
            case .unavailable:
                return CameraCoachEntryAccessibilityID.unavailableRoot
            case .unknown:
                return CameraCoachEntryAccessibilityID.unknownRoot
            }
        }
    }

    static func primaryActionIdentifier(for phase: CameraCoachEntryPhase) -> String? {
        switch phase {
        case .intro:
            return CameraCoachEntryAccessibilityID.openCameraAction
        case .permissionContext:
            return CameraCoachEntryAccessibilityID.continueAction
        case .blocked(.denied):
            return CameraCoachEntryAccessibilityID.openSettingsAction
        case .blocked(.restricted), .blocked(.unavailable), .blocked(.unknown):
            return CameraCoachEntryAccessibilityID.recheckAction
        case .resolving, .requesting, .ready:
            return nil
        }
    }
}

struct CameraCoachEntryLeaderOverlay: View {
    let phase: SETLeaderPhase

    var body: some View {
        SETLeaderCountdown(phase: phase)
            .frame(maxWidth: SETComponentMetric.entryLeaderMaximumDimension)
            .padding(SETSpacing.x6)
            .accessibilityIdentifier("camera-coach-entry-leader")
            .transition(.opacity)
            .animation(
                .easeOut(duration: SETMotion.reducedMotionCrossfadeDuration),
                value: phase
            )
            .allowsHitTesting(false)
    }
}

private struct BlockedPresentation {
    let title: SETCopyKey
    let primaryTitle: SETCopyKey
    let primaryIdentifier: String
    let primaryLabel: SETCopyKey
    let primaryHint: SETCopyKey
    let primaryAction: () -> Void
}
