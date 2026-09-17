#if DEBUG
import SwiftUI
import UIKit

/// Exercises the actual disclosure component with generated pixels. There is no
/// client, token provider, camera, network call or persistent approval in this host.
@MainActor
struct SETCameraCloudConsentFixtureRoot: View {
    let configuration: SETGalleryLaunchConfiguration
    private let request: CameraCloudTransferRequest?
    @State private var pendingRequest: CameraCloudTransferRequest?
    @State private var outcome = "not-presented"

    init(configuration: SETGalleryLaunchConfiguration) {
        self.configuration = configuration
        self.request = Self.makeRequest()
    }

    var body: some View {
        VStack(spacing: SETSpacing.x4) {
            Text("Consent component fixture")
                .font(.headline)
            Text(outcome)
                .accessibilityIdentifier("camera_cloud_fixture_state")
            if request != nil {
                Button {
                    outcome = "presented"
                    pendingRequest = request
                } label: {
                    Text("Open disclosure")
                        .frame(minWidth: SETComponentMetric.minimumHitTarget,
                               minHeight: SETComponentMetric.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("camera_cloud_fixture_open")
            } else {
                Text("Fixture image preparation failed")
                    .accessibilityIdentifier("camera_cloud_fixture_error")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.setInk)
        .foregroundStyle(.setTextPrimary)
        .background(alignment: .topLeading) {
            CameraCloudWindowDiagnosticProbe()
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
        }
        .environment(\.locale, configuration.locale.locale)
        .environment(\.dynamicTypeSize, configuration.dynamicTypeSize)
        .environment(\.setReduceMotionOverride, configuration.reduceMotion)
        .environment(\.setReduceTransparencyOverride, configuration.reduceTransparency)
        .sheet(item: $pendingRequest) { disclosed in
            CameraCloudTransferConsentSheet(
                request: disclosed,
                onApprove: { approval in
                    guard pendingRequest?.id == disclosed.id,
                          approval == disclosed.approval else { return }
                    // Observe only the component callback. No transport is constructed.
                    outcome = "approval-callback-received"
                    pendingRequest = nil
                },
                onCancel: {
                    guard pendingRequest?.id == disclosed.id else { return }
                    outcome = "cancelled"
                    pendingRequest = nil
                }
            )
            .environment(\.locale, configuration.locale.locale)
            .environment(\.dynamicTypeSize, configuration.dynamicTypeSize)
            .environment(\.setReduceMotionOverride, configuration.reduceMotion)
            .environment(\.setReduceTransparencyOverride, configuration.reduceTransparency)
            // The real sheet includes a policy Link. Keep even an accidental
            // navigation inside this fixture; never launch Safari or a URL request.
            .environment(\.openURL, OpenURLAction { _ in .handled })
        }
    }

    private static func makeRequest() -> CameraCloudTransferRequest? {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 240), format: format)
        let image = renderer.image { context in
            UIColor(red: 0.12, green: 0.16, blue: 0.20, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
            UIColor(red: 0.86, green: 0.45, blue: 0.16, alpha: 1).setFill()
            context.fill(CGRect(x: 30, y: 145, width: 260, height: 28))
            UIColor(red: 0.97, green: 0.82, blue: 0.38, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 38, y: 38, width: 64, height: 64))
            UIColor(red: 0.25, green: 0.75, blue: 0.71, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 224, y: 62, width: 42, height: 42))
        }
        guard let encoded = image.jpegData(compressionQuality: 0.85),
              let jpeg = try? CameraCloudFramePreprocessor.removingJPEGMetadata(encoded),
              let endpoint = URL(string: "https://camera-fixture.invalid/v1"),
              let policyURL = URL(string: "https://camera-fixture.invalid/privacy"),
              let policy = CameraCloudTransferPolicy(
                serviceEndpoint: endpoint, operatorName: "SET OS UI fixture",
                providerName: "No provider connected", providerVersion: "fixture-only",
                processingRegion: "Local Simulator; no transfer",
                imageRetention: "Generated image held in this view only.",
                requestMetadataRetention: "No request is dispatched or persisted.",
                securityIdentityRetention: "No enrollment or device identity is created.",
                spendRecordRetention: "No spend record or paid request is created.",
                deletionRequestProcedure: "Dismiss this fixture to discard its in-memory state.",
                providerRetention: "No provider receives an image or context.",
                policyVersion: "ui-fixture-1", policyURL: policyURL
              ),
              let fingerprint = policy.fingerprint else { return nil }
        let digest = CameraCloudTransferPolicy.sha256(jpeg)
        return CameraCloudTransferRequest(
            requestID: UUID(), requestHash: digest,
            snapshotID: "synthetic-consent-ui-frame", mediaSHA256: digest,
            jpegData: jpeg, pixelWidth: 320, pixelHeight: 240, byteCount: jpeg.count,
            policy: policy, policyFingerprint: fingerprint
        )
    }
}

/// Reuses the actual UIKit window/controller observer without constructing
/// camera dependencies, changing orientation, or dispatching any work.
private struct CameraCloudWindowDiagnosticProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> CameraLifecycleDiagnosticView {
        CameraLifecycleDiagnosticView()
    }

    func updateUIView(_ view: CameraLifecycleDiagnosticView, context: Context) {
        view.swiftUIScenePhase = "cloud-consent-fixture"
    }
}
#endif
