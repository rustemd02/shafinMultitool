import SwiftUI
import UIKit

enum CameraCoachEntryCopy {
    static let introTitle = "Снимайте увереннее"
    static let introBody = "Camera Coach подсказывает, что улучшить в кадре. Базовый анализ работает на устройстве."
    static let introAction = "Открыть камеру"

    static let permissionContextTitle = "Разрешите доступ к камере"
    static let permissionContextBody = "Камера нужна, чтобы показать кадр и проверить изменение."
    static let localProcessingSentence = "Базовый анализ работает на устройстве."
    static let permissionContextAction = "Продолжить"

    static let deniedTitle = "Доступ к камере выключен"
    static let restrictedTitle = "Доступ к камере ограничен системой"
    static let unavailableTitle = "Камера недоступна на этом устройстве"
    static let unknownTitle = "Не удалось определить доступ к камере"
    static let blockedBody = "Без доступа к камере локальный Coach не может показать кадр и проверить изменение."
    static let settingsAction = "Открыть Настройки"
    static let recheckAction = "Проверить снова"
    static let settingsFallback = "Откройте Настройки → Конфиденциальность и безопасность → Камера и включите доступ для приложения."
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

    static let openCameraAction = "camera-coach-entry-open-camera"
    static let continueAction = "camera-coach-entry-continue"
    static let openSettingsAction = "camera-coach-entry-open-settings"
    static let recheckAction = "camera-coach-entry-recheck"
}

enum CameraCoachEntryVisualPolicy {
    // Source markers for the focused contract tests: appearance still requires
    // manual screenshot inspection in the real process UI evidence.
    static let sourceMarkers = [
        "neutral-surface",
        "typography-spacing-hierarchy",
        "no-camera-preview",
        "no-card-pill-glass-blur-gradient"
    ]
}

struct CameraCoachEntryView: View {
    let phase: CameraCoachEntryPhase
    let onOpenCamera: () -> Void
    let onContinuePermissionRequest: () -> Void
    let onRecheckCameraAccess: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var showsSettingsFallback = false

    init(
        phase: CameraCoachEntryPhase,
        onOpenCamera: @escaping () -> Void,
        onContinuePermissionRequest: @escaping () -> Void,
        onRecheckCameraAccess: @escaping () -> Void
    ) {
        self.phase = phase
        self.onOpenCamera = onOpenCamera
        self.onContinuePermissionRequest = onContinuePermissionRequest
        self.onRecheckCameraAccess = onRecheckCameraAccess
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            content
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier(Self.rootAccessibilityIdentifier(for: phase))
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .resolving:
            Text("Подготовка…")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.62))
                .accessibilityIdentifier(CameraCoachEntryAccessibilityID.resolvingRoot)
                .accessibilityLabel("Подготовка")

        case .ready:
            Text("Подготовка…")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.62))
                .accessibilityIdentifier(CameraCoachEntryAccessibilityID.readyRoot)
                .accessibilityLabel("Камера готова")

        case .intro:
            entryCopy(
                title: CameraCoachEntryCopy.introTitle,
                titleIdentifier: CameraCoachEntryAccessibilityID.introTitle,
                body: CameraCoachEntryCopy.introBody,
                bodyIdentifier: CameraCoachEntryAccessibilityID.introBody,
                primaryTitle: CameraCoachEntryCopy.introAction,
                primaryIdentifier: CameraCoachEntryAccessibilityID.openCameraAction,
                primaryAccessibilityLabel: CameraCoachEntryCopy.introAction,
                primaryAccessibilityHint: "Переходит к объяснению доступа к камере",
                primaryAction: onOpenCamera
            )

        case .permissionContext:
            entryCopy(
                title: CameraCoachEntryCopy.permissionContextTitle,
                titleIdentifier: CameraCoachEntryAccessibilityID.permissionContextTitle,
                body: CameraCoachEntryCopy.permissionContextBody,
                bodyIdentifier: CameraCoachEntryAccessibilityID.permissionContextBody,
                supplemental: CameraCoachEntryCopy.localProcessingSentence,
                supplementalIdentifier: CameraCoachEntryAccessibilityID.permissionContextLocalProcessing,
                primaryTitle: CameraCoachEntryCopy.permissionContextAction,
                primaryIdentifier: CameraCoachEntryAccessibilityID.continueAction,
                primaryAccessibilityLabel: CameraCoachEntryCopy.permissionContextAction,
                primaryAccessibilityHint: "Открывает системный запрос доступа к камере",
                primaryAction: onContinuePermissionRequest
            )

        case .requesting:
            Text("Подготовка…")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.62))
                .accessibilityIdentifier(CameraCoachEntryAccessibilityID.permissionContextRoot)
                .accessibilityLabel("Запрос доступа к камере выполняется")

        case .blocked(let reason):
            blockedCopy(for: reason)
        }
    }

    @ViewBuilder
    private func blockedCopy(for reason: CameraCoachCameraBlockReason) -> some View {
        let presentation = blockedPresentation(for: reason)

        entryCopy(
            title: presentation.title,
            titleIdentifier: CameraCoachEntryAccessibilityID.blockedTitle,
            body: CameraCoachEntryCopy.blockedBody,
            bodyIdentifier: CameraCoachEntryAccessibilityID.blockedBody,
            primaryTitle: presentation.primaryTitle,
            primaryIdentifier: presentation.primaryIdentifier,
            primaryAccessibilityLabel: presentation.primaryTitle,
            primaryAccessibilityHint: reason == .denied
                ? "Открывает настройки доступа к камере"
                : "Повторно проверяет доступ к камере",
            primaryAction: presentation.primaryAction,
            secondaryTitle: reason == .denied ? CameraCoachEntryCopy.recheckAction : nil,
            secondaryIdentifier: reason == .denied ? CameraCoachEntryAccessibilityID.recheckAction : nil,
            secondaryAccessibilityHint: reason == .denied ? "Повторно проверяет доступ к камере" : nil,
            secondaryAction: reason == .denied ? onRecheckCameraAccess : nil,
            footer: showsSettingsFallback ? settingsFallback : nil
        )
    }

    private func blockedPresentation(
        for reason: CameraCoachCameraBlockReason
    ) -> BlockedPresentation {
        switch reason {
        case .denied:
            return BlockedPresentation(
                title: CameraCoachEntryCopy.deniedTitle,
                primaryTitle: CameraCoachEntryCopy.settingsAction,
                primaryIdentifier: CameraCoachEntryAccessibilityID.openSettingsAction,
                primaryAction: openSettings
            )
        case .restricted:
            return BlockedPresentation(
                title: CameraCoachEntryCopy.restrictedTitle,
                primaryTitle: CameraCoachEntryCopy.recheckAction,
                primaryIdentifier: CameraCoachEntryAccessibilityID.recheckAction,
                primaryAction: onRecheckCameraAccess
            )
        case .unavailable:
            return BlockedPresentation(
                title: CameraCoachEntryCopy.unavailableTitle,
                primaryTitle: CameraCoachEntryCopy.recheckAction,
                primaryIdentifier: CameraCoachEntryAccessibilityID.recheckAction,
                primaryAction: onRecheckCameraAccess
            )
        case .unknown:
            return BlockedPresentation(
                title: CameraCoachEntryCopy.unknownTitle,
                primaryTitle: CameraCoachEntryCopy.recheckAction,
                primaryIdentifier: CameraCoachEntryAccessibilityID.recheckAction,
                primaryAction: onRecheckCameraAccess
            )
        }
    }

    private func entryCopy(
        title: String,
        titleIdentifier: String,
        body: String,
        bodyIdentifier: String,
        supplemental: String? = nil,
        supplementalIdentifier: String? = nil,
        primaryTitle: String? = nil,
        primaryIdentifier: String? = nil,
        primaryAccessibilityLabel: String? = nil,
        primaryAccessibilityHint: String? = nil,
        primaryAction: (() -> Void)? = nil,
        secondaryTitle: String? = nil,
        secondaryIdentifier: String? = nil,
        secondaryAccessibilityHint: String? = nil,
        secondaryAction: (() -> Void)? = nil,
        footer: Text? = nil
    ) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 64)

                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(titleIdentifier)

                    Text(body)
                        .font(.body)
                        .foregroundStyle(Color.white.opacity(0.78))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(bodyIdentifier)
                        .padding(.top, 20)

                    if let supplemental, let supplementalIdentifier {
                        Text(supplemental)
                            .font(.footnote)
                            .foregroundStyle(Color.white.opacity(0.62))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(supplementalIdentifier)
                            .padding(.top, 12)
                    }
                }

                if let primaryTitle,
                   let primaryIdentifier,
                   let primaryAccessibilityLabel,
                   let primaryAccessibilityHint,
                   let primaryAction {
                    Button(action: primaryAction) {
                        Text(primaryTitle)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(primaryIdentifier)
                    .accessibilityLabel(primaryAccessibilityLabel)
                    .accessibilityHint(primaryAccessibilityHint)
                    .padding(.top, 36)
                }

                if let secondaryTitle,
                   let secondaryIdentifier,
                   let secondaryAction {
                    Button(action: secondaryAction) {
                        Text(secondaryTitle)
                            .font(.body)
                            .foregroundStyle(Color.white.opacity(0.72))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(secondaryIdentifier)
                    .accessibilityLabel(secondaryTitle)
                    .accessibilityHint(secondaryAccessibilityHint ?? "")
                    .padding(.top, 8)
                }

                if let footer {
                    footer
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(CameraCoachEntryAccessibilityID.settingsFallback)
                        .accessibilityLabel(CameraCoachEntryCopy.settingsFallback)
                        .padding(.top, 20)
                }

                Spacer(minLength: 64)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .scrollIndicators(.hidden)
    }

    private var settingsFallback: Text {
        Text(CameraCoachEntryCopy.settingsFallback)
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

private struct BlockedPresentation {
    let title: String
    let primaryTitle: String
    let primaryIdentifier: String
    let primaryAction: () -> Void
}
