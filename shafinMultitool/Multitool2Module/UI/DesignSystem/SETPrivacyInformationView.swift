import SwiftUI
import UIKit

/// Opening this page neither requests a permission nor authorizes a network
/// transfer. Service deletion requires a separate explicit confirmation.
struct SETPrivacyEntryButton: View {
    let accessibilityID: String
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            Label {
                Text(SETCopyKey.privacyTitle.localizedTextKey)
            } icon: {
                Image(systemName: "hand.raised")
                    .accessibilityHidden(true)
            }
                .font(SETTypography.uiBodyFont())
                .padding(.horizontal, SETSpacing.x3)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.setTextSecondary)
        .accessibilityLabel(Text(SETCopyKey.privacyTitle.localizedTextKey))
        .accessibilityIdentifier(accessibilityID)
        .sheet(isPresented: $isPresented) {
            SETPrivacyInformationView()
        }
    }
}

/// A fresh read of the existing parser's configured provider, never an
/// interpretation of deployment keys or a second configuration owner.
struct SETPrivacyRuntimeFacts: Equatable {
    let sceneRemoteConfigured: Bool

    static func current(sceneParser: SceneParserService = .shared) -> Self {
        Self(sceneRemoteConfigured: sceneParser.isRemoteOffloadConfigured)
    }

    var sceneDescription: SETCopyKey {
        sceneRemoteConfigured ? .privacyScenesRemoteBody : .privacyScenesLocalBody
    }
}

@MainActor
struct SETPrivacyInformationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var facts = SETPrivacyRuntimeFacts.current()
    @State private var settingsUnavailable = false
    @State private var expandedNotices: Set<String> = []
    @StateObject private var installationDeletion: SETInstallationDeletionPresentation

    init(
        installationDeletionProvider: (any SceneInstallationDeletionProviding)? =
            SceneParserService.shared.installationDeletionProvider
    ) {
        _installationDeletion = StateObject(wrappedValue: SETInstallationDeletionPresentation(
            provider: installationDeletionProvider
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            pageHeader
            ScrollView {
                VStack(alignment: .leading, spacing: SETSpacing.x6) {
                    Text(SETCopyKey.privacyIntroduction.localizedTextKey)
                        .font(SETTypography.uiBodyFont())
                        .fixedSize(horizontal: false, vertical: true)

                    section(.privacyAccountTitle, body: .privacyAccountBody, id: "privacy_account")
                    section(.privacyCameraTitle, body: .privacyCameraBody, id: "privacy_camera")
                    section(.privacyScenesTitle, body: facts.sceneDescription, id: "privacy_scene_processing")
                    if facts.sceneRemoteConfigured {
                        section(.privacyInstallationTitle, body: .privacyInstallationBody, id: "privacy_installation")
                        section(.privacyServerStorageTitle, body: .privacyServerStorageBody, id: "privacy_server_storage")
                    }
                    deletionSection
                    section(.privacyMicrophoneTitle, body: .privacyMicrophoneBody, id: "privacy_microphone")
                    section(.privacySpeechTitle, body: .privacySpeechBody, id: "privacy_speech")
                    section(.privacyLocalStorageTitle, body: .privacyLocalStorageBody, id: "privacy_local_storage")

                    VStack(alignment: .leading, spacing: SETSpacing.x2) {
                        section(.privacyPermissionsTitle, body: .privacyPermissionsBody, id: "privacy_permissions")
                        Button {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                                settingsUnavailable = true
                                return
                            }
                            openURL(url) { settingsUnavailable = !$0 }
                        } label: {
                            Text(SETCopyKey.openSettings.localizedTextKey)
                                .font(SETTypography.uiBodyFont(weight: .semibold))
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("privacy_open_settings")
                        if settingsUnavailable {
                            Text(SETCopyKey.privacySettingsUnavailable.localizedTextKey)
                                .font(SETTypography.uiBodyFont())
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: SETSpacing.x3) {
                        section(.privacyNoticesTitle, body: .privacyNoticesBody, id: "privacy_notices")
                        ForEach(SETBundledLicenseNotice.all) { notice in
                            Button {
                                if expandedNotices.contains(notice.id) {
                                    expandedNotices.remove(notice.id)
                                } else {
                                    expandedNotices.insert(notice.id)
                                }
                            } label: {
                                HStack {
                                    Text(verbatim: notice.title)
                                        .font(SETTypography.uiBodyFont(weight: .semibold))
                                    Spacer(minLength: SETSpacing.x2)
                                    Image(systemName: expandedNotices.contains(notice.id) ? "chevron.up" : "chevron.down")
                                        .accessibilityHidden(true)
                                }
                                .frame(minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("privacy_notice_" + notice.id)
                            .accessibilityValue(Text((expandedNotices.contains(notice.id) ? SETCopyKey.privacyNoticeExpanded : .privacyNoticeCollapsed).localizedTextKey))
                            if expandedNotices.contains(notice.id) {
                                if let text = notice.text(in: .main) {
                                    Text(verbatim: text)
                                        .font(SETTypography.uiBodyFont())
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .accessibilityIdentifier("privacy_notice_text_" + notice.id)
                                } else {
                                    Text(SETCopyKey.privacyNoticeUnavailable.localizedTextKey)
                                        .font(SETTypography.uiBodyFont())
                                        .fixedSize(horizontal: false, vertical: true)
                                        .accessibilityIdentifier("privacy_notice_unavailable_" + notice.id)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: SETComponentMetric.gallerySectionMaxWidth, alignment: .leading)
                .padding(SETSpacing.x4)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(.setInk)
            .foregroundStyle(.setTextPrimary)
            .accessibilityIdentifier("privacy_document")
        }
        .background(.setInk)
        .preferredColorScheme(.dark)
        .task { await installationDeletion.appear() }
        .onDisappear { installationDeletion.disappear() }
        .alert(
            Text(SETCopyKey.privacyDeletionConfirmTitle.localizedTextKey),
            isPresented: $installationDeletion.isConfirmationPresented
        ) {
            Button(role: .destructive) {
                Task { await installationDeletion.confirmDeletion() }
            } label: {
                Text(SETCopyKey.privacyDeletionAction.localizedTextKey)
            }
            .accessibilityIdentifier("privacy_deletion_confirm")
            Button(role: .cancel) {
                installationDeletion.cancelDeletionConfirmation()
            } label: {
                Text(SETCopyKey.privacyDeletionCancel.localizedTextKey)
            }
            .accessibilityIdentifier("privacy_deletion_cancel")
        } message: {
            Text(SETCopyKey.privacyDeletionConfirmBody.localizedTextKey)
        }
    }

    private var deletionSection: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x3) {
            section(.privacyDeletionTitle, body: .privacyDeletionScope, id: "privacy_deletion_scope")
            Text(SETCopyKey.privacyDeletionRetained.localizedTextKey)
                .font(SETTypography.uiBodyFont())
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityIdentifier("privacy_deletion_retained")
            HStack(alignment: .top, spacing: SETSpacing.x2) {
                Image(systemName: installationDeletion.statusSymbol)
                    .accessibilityHidden(true)
                Text(installationDeletion.statusCopyKey.localizedTextKey)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(SETTypography.uiBodyFont())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("privacy_deletion_status")
            if installationDeletion.canRequestDeletion {
                Button(role: .destructive) {
                    installationDeletion.requestDeletionConfirmation()
                } label: {
                    Text(SETCopyKey.privacyDeletionAction.localizedTextKey)
                        .font(SETTypography.uiBodyFont(weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("privacy_deletion_request")
            } else if installationDeletion.canCheckStatus {
                Button {
                    Task { await installationDeletion.checkStatus() }
                } label: {
                    Text(SETCopyKey.privacyDeletionCheck.localizedTextKey)
                        .font(SETTypography.uiBodyFont(weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("privacy_deletion_check")
            }
        }
    }

    private var pageHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: SETSpacing.x3) {
                headerTitle.fixedSize()
                Spacer(minLength: SETSpacing.x3)
                closeButton
            }
            VStack(alignment: .leading, spacing: SETSpacing.x2) {
                headerTitle.fixedSize(horizontal: false, vertical: true)
                closeButton.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, SETSpacing.x4)
        .padding(.vertical, SETSpacing.x2)
        .frame(maxWidth: .infinity)
        .background(.setInk)
    }

    private var headerTitle: some View {
        Text(SETCopyKey.privacyTitle.localizedTextKey)
            .font(SETTypography.uiBodyFont(weight: .semibold))
            .foregroundStyle(.setTextPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Text(SETCopyKey.commonClose.localizedTextKey)
                .font(SETTypography.uiBodyFont(weight: .semibold))
                .foregroundStyle(.setTextPrimary)
                .underline()
                .padding(.horizontal, SETSpacing.x2)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityIdentifier("privacy_close")
    }

    private func section(_ title: SETCopyKey, body: SETCopyKey, id: String) -> some View {
        VStack(alignment: .leading, spacing: SETSpacing.x2) {
            Text(title.localizedTextKey)
                .font(SETTypography.uiBodyFont(weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(body.localizedTextKey)
                .font(SETTypography.uiBodyFont())
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityIdentifier(id)
        }
    }
}

struct SETBundledLicenseNotice: Identifiable {
    let id: String
    let title: String
    let resource: String

    static let all: [Self] = [
        .init(id: "snapkit", title: "SnapKit · MIT", resource: "SnapKit-LICENSE"),
        .init(id: "llama_cpp", title: "llama.cpp · MIT", resource: "llama-cpp-LICENSE"),
        .init(id: "bebas_neue", title: "Bebas Neue · OFL 1.1", resource: "OFL-BebasNeue"),
        .init(id: "caveat", title: "Caveat · OFL 1.1", resource: "OFL-Caveat"),
        .init(id: "jetbrains_mono", title: "JetBrains Mono · OFL 1.1", resource: "OFL-JetBrainsMono"),
        .init(id: "oswald", title: "Oswald · OFL 1.1", resource: "OFL-Oswald"),
        .init(id: "pt_mono", title: "PT Mono · OFL 1.1", resource: "OFL-PTMono")
    ]

    func data(in bundle: Bundle) -> Data? {
        // Xcode may flatten copied resource groups or preserve their folder.
        for folder in [nil, "Legal", "Fonts"] as [String?] {
            if let url = bundle.url(forResource: resource, withExtension: "txt", subdirectory: folder),
               let data = try? Data(contentsOf: url), !data.isEmpty {
                return data
            }
        }
        return nil
    }

    func text(in bundle: Bundle) -> String? {
        data(in: bundle).flatMap { String(data: $0, encoding: .utf8) }
    }
}
