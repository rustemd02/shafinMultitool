import SwiftUI
import UIKit

/// Pause presentation only. The caller owns request eligibility, lifecycle and cancellation.
struct CameraCloudReviewControls: View {
    let state: CameraCloudReviewState
    let canRequest: Bool
    let onRequest: () -> Void
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.setReduceMotionOverride) private var reduceMotionOverride

    var body: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x2) {
            if let statusCopy {
                HStack(alignment: .top, spacing: SETSpacing.x2) {
                    Image(systemName: statusSymbol)
                        .accessibilityHidden(true)
                    Text(statusCopy.localizedTextKey)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(SETTypography.uiBodyFont())
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("camera_cloud_status")
            }

            Button {
                guard canRequest, !state.isBusy else { return }
                onRequest()
            } label: {
                Text(SETCopyKey.cameraCloudAnalyze.localizedTextKey)
                    .font(SETTypography.uiBodyFont(weight: .semibold))
                    .underline()
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(canRequest && !state.isBusy ? Color.setOrange : Color.setTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: SETComponentMetric.minimumHitTarget,
                           alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canRequest || state.isBusy)
            .accessibilityIdentifier("camera_cloud_analyze")

            if state.isBusy {
                Button(role: .cancel, action: onCancel) {
                    Text(SETCopyKey.libraryCancel.localizedTextKey)
                        .font(SETTypography.uiBodyFont(weight: .semibold))
                        .underline()
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: SETComponentMetric.minimumHitTarget,
                               alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("camera_cloud_cancel")
            }
        }
        .foregroundStyle(.setTextPrimary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera_cloud_review_controls")
        .transaction { transaction in
            if reduceMotionOverride ?? reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private var statusCopy: SETCopyKey? {
        switch state {
        case .idle: return nil
        case .preparing: return .cameraCloudPreparing
        case .awaitingConsent: return .cameraCloudAwaitingConsent
        case .analyzing: return .cameraCloudAnalyzing
        case .complete: return .cameraCloudComplete
        case .noAdditionalEvidence: return .cameraCloudNoEvidence
        case .failed(.preparation): return .cameraCloudPreparationError
        case .failed(.authentication): return .cameraCloudAuthenticationError
        case .failed(.network): return .cameraCloudNetworkError
        case .failed(.serviceUnavailable): return .cameraCloudServiceError
        case .failed(.responseInvalid): return .cameraCloudResponseError
        }
    }

    private var statusSymbol: String {
        switch state {
        case .idle, .noAdditionalEvidence: return "info.circle"
        case .preparing, .awaitingConsent, .analyzing: return "hourglass"
        case .complete: return "checkmark.circle"
        case .failed: return "exclamationmark.circle"
        }
    }
}

/// Presents one immutable transfer request. It neither creates an approval automatically
/// nor dismisses/cancels work on disappearance. The presenting owner resolves lifecycle
/// events against the exact pending request, including dismissal after an explicit choice.
struct CameraCloudTransferConsentSheet: View {
    let request: CameraCloudTransferRequest
    let onApprove: (CameraCloudTransferApproval) -> Void
    let onCancel: () -> Void

    private let previewImage: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.setReduceMotionOverride) private var reduceMotionOverride

    init(request: CameraCloudTransferRequest,
         onApprove: @escaping (CameraCloudTransferApproval) -> Void,
         onCancel: @escaping () -> Void) {
        self.request = request
        self.onApprove = onApprove
        self.onCancel = onCancel
        // Decode only the bytes awaiting approval. No current frame, file, URL,
        // second orientation transform, inference or replacement preview is consulted.
        if let decoded = UIImage(data: request.jpegData), decoded.cgImage != nil {
            self.previewImage = decoded
        } else {
            self.previewImage = nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                cancelButton
            }
            .padding(.horizontal, SETSpacing.x4)
            .padding(.vertical, SETSpacing.x1)

            ScrollView {
                VStack(alignment: .leading, spacing: SETSpacing.x4) {
                    Text(SETCopyKey.cameraCloudConsentTitle.localizedTextKey)
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("camera_cloud_consent_title")

                    selectedImage

                    Text(SETCopyKey.cameraCloudConsentScope.localizedTextKey)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("camera_cloud_consent_scope")

                    policyDisclosure
                    approveButton
                }
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(SETSpacing.x4)
            }
            .accessibilityIdentifier("camera_cloud_consent_scroll")
        }
        .font(SETTypography.uiBodyFont())
        .foregroundStyle(.setTextPrimary)
        .background(Color.setInk.ignoresSafeArea())
        .preferredColorScheme(.dark)
        // Explicit Cancel remains visible above the scrolling disclosure. The caller
        // handles route/lifecycle cancellation; no onDisappear can revoke a sent request.
        .interactiveDismissDisabled()
        .accessibilityAction(.escape) { onCancel() }
        // A container identifier propagates to the first Button and ScrollView
        // on this UIKit accessibility bridge, replacing their explicit IDs.
        // Keep identity on the independently accessible controls below.
        .transaction { transaction in
            if reduceMotionOverride ?? reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private var selectedImage: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x2) {
            Text(SETCopyKey.cameraCloudSelectedImage.localizedTextKey)
                .font(SETTypography.uiBodyFont(weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .accessibilityLabel(SETCopyKey.cameraCloudSelectedImage.localizedTextKey)
                    .accessibilityIdentifier("camera_cloud_preview")
            } else {
                Text(SETCopyKey.cameraCloudPreparationError.localizedTextKey)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("camera_cloud_preview_error")
            }
        }
    }

    private var policyDisclosure: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x3) {
            policyField(.generatorTransferOperator, request.policy.operatorName, id: "operator")
            policyField(.generatorTransferService, request.policy.serviceEndpoint.absoluteString, id: "service")
            policyField(.generatorTransferProvider,
                        request.policy.providerName + " · " + request.policy.providerVersion, id: "provider")
            policyField(.generatorTransferRegion, request.policy.processingRegion, id: "region")
            policyField(.cameraCloudImageRetention, request.policy.imageRetention, id: "image_retention")
            policyField(.cameraCloudRequestRetention, request.policy.requestMetadataRetention, id: "request_retention")
            policyField(.generatorTransferSecurityRetention, request.policy.securityIdentityRetention, id: "security_retention")
            policyField(.generatorTransferSpendRetention, request.policy.spendRecordRetention, id: "spend_retention")
            policyField(.generatorTransferProviderRetention, request.policy.providerRetention, id: "provider_retention")
            policyField(.generatorTransferDeletion, request.policy.deletionRequestProcedure, id: "deletion")
            policyField(.generatorTransferVersion, request.policy.policyVersion, id: "version")
            Link(destination: request.policy.policyURL) {
                VStack(alignment: .leading, spacing: SETSpacing.x1) {
                    Text(SETCopyKey.generatorTransferReadPolicy.localizedTextKey)
                        .fontWeight(.semibold)
                        .underline()
                    Text(verbatim: request.policy.policyURL.absoluteString)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: SETComponentMetric.minimumHitTarget,
                       alignment: .leading)
                .contentShape(Rectangle())
            }
            .foregroundStyle(.setOrange)
            .accessibilityIdentifier("camera_cloud_policy")
        }
        .accessibilityIdentifier("camera_cloud_policy_disclosure")
    }

    private func policyField(_ title: SETCopyKey, _ value: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: SETSpacing.x1) {
            Text(title.localizedTextKey)
                .fontWeight(.semibold)
            Text(verbatim: value)
                .textSelection(.enabled)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("camera_cloud_policy_" + id)
    }

    private var approveButton: some View {
        Button {
            guard previewImage != nil else { return }
            onApprove(request.approval)
        } label: {
            Text(SETCopyKey.cameraCloudSend.localizedTextKey)
                .font(SETTypography.uiBodyFont(weight: .semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: SETComponentMetric.minimumHitTarget)
                .padding(.horizontal, SETSpacing.x3)
                .padding(.vertical, SETSpacing.x2)
                .foregroundStyle(previewImage == nil ? Color.setTextSecondary : Color.setInk)
                .background(previewImage == nil ? Color.setSurfaceSolid : Color.setOrange)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(previewImage == nil)
        .accessibilityIdentifier("camera_cloud_send")
    }

    private var cancelButton: some View {
        Button(role: .cancel, action: onCancel) {
            Text(SETCopyKey.libraryCancel.localizedTextKey)
                .font(SETTypography.uiBodyFont(weight: .semibold))
                .underline()
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: SETComponentMetric.minimumHitTarget,
                       minHeight: SETComponentMetric.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("camera_cloud_decline")
    }
}
