import CryptoKit
import Foundation

/// Public, deployment-specific disclosure for sending one selected camera still.
/// Construction is inert. Missing policy information cannot authorize enrollment or upload.
struct CameraCloudTransferPolicy: Encodable, Equatable, Sendable {
    let serviceEndpoint: URL
    let operatorName: String
    let providerName: String
    let providerVersion: String
    let processingRegion: String
    let imageRetention: String
    let requestMetadataRetention: String
    let securityIdentityRetention: String
    let spendRecordRetention: String
    let deletionRequestProcedure: String
    let providerRetention: String
    let policyVersion: String
    let policyURL: URL

    init?(
        serviceEndpoint: URL, operatorName: String, providerName: String,
        providerVersion: String, processingRegion: String, imageRetention: String,
        requestMetadataRetention: String, securityIdentityRetention: String,
        spendRecordRetention: String, deletionRequestProcedure: String,
        providerRetention: String, policyVersion: String, policyURL: URL
    ) {
        guard SceneGenerationClient.isValidEndpoint(serviceEndpoint),
              serviceEndpoint.lastPathComponent == "v1",
              Self.validPolicyURL(policyURL),
              [operatorName, providerName, providerVersion, processingRegion,
               imageRetention, requestMetadataRetention, securityIdentityRetention,
               spendRecordRetention, deletionRequestProcedure, providerRetention,
               policyVersion].allSatisfy(Self.validText) else { return nil }
        self.serviceEndpoint = serviceEndpoint
        self.operatorName = operatorName
        self.providerName = providerName
        self.providerVersion = providerVersion
        self.processingRegion = processingRegion
        self.imageRetention = imageRetention
        self.requestMetadataRetention = requestMetadataRetention
        self.securityIdentityRetention = securityIdentityRetention
        self.spendRecordRetention = spendRecordRetention
        self.deletionRequestProcedure = deletionRequestProcedure
        self.providerRetention = providerRetention
        self.policyVersion = policyVersion
        self.policyURL = policyURL
    }

    static func fromPublicConfiguration(_ values: [String: Any], endpoint: URL) -> Self? {
        func field(_ key: String) -> String? {
            guard let value = values[key] as? String, validText(value) else { return nil }
            return value
        }
        // A Camera deployment must share the installation's actual Scene API root.
        // Environment configuration never overrides a different disclosed operator.
        guard let rawRoot = field("SETOSSceneBaseURL"),
              var declaredRoot = URL(string: rawRoot),
              SceneGenerationClient.isValidEndpoint(declaredRoot) else { return nil }
        if declaredRoot.lastPathComponent != "v1" { declaredRoot.appendPathComponent("v1") }
        guard declaredRoot == endpoint,
              let operatorName = field("SETOSCameraPolicyOperatorName"),
              let providerName = field("SETOSCameraProviderName"),
              let providerVersion = field("SETOSCameraProviderVersion"),
              let region = field("SETOSCameraPolicyProcessingRegion"),
              let image = field("SETOSCameraPolicyImageRetention"),
              let metadata = field("SETOSCameraPolicyRequestMetadataRetention"),
              let security = field("SETOSCameraPolicySecurityIdentityRetention"),
              let spend = field("SETOSCameraPolicySpendRecordRetention"),
              let deletion = field("SETOSCameraPolicyDeletionProcedure"),
              let provider = field("SETOSCameraPolicyProviderRetention"),
              let version = field("SETOSCameraPolicyVersion"),
              let rawPolicyURL = field("SETOSCameraPolicyURL"),
              let policyURL = URL(string: rawPolicyURL) else { return nil }
        return Self(
            serviceEndpoint: endpoint, operatorName: operatorName,
            providerName: providerName, providerVersion: providerVersion,
            processingRegion: region, imageRetention: image,
            requestMetadataRetention: metadata, securityIdentityRetention: security,
            spendRecordRetention: spend, deletionRequestProcedure: deletion,
            providerRetention: provider, policyVersion: version, policyURL: policyURL
        )
    }

    var fingerprint: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return nil }
        return Self.sha256(data)
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func validText(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 2_048
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.contains("$(")
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func validPolicyURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme?.lowercased() == "https"
            && components.host?.isEmpty == false
            && components.user == nil && components.password == nil
            && components.query == nil && components.fragment == nil
    }
}

/// Exact bytes and image facts displayed before approval. Resizing/metadata removal
/// are disclosed separately from the fact that faces, text and objects remain visible.
struct CameraCloudTransferRequest: Equatable, Identifiable, Sendable {
    let requestID: UUID
    let requestHash: String
    let snapshotID: String
    let mediaSHA256: String
    let jpegData: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let byteCount: Int
    let policy: CameraCloudTransferPolicy
    let policyFingerprint: String

    var id: String { "camera-transfer:\(requestID.uuidString.lowercased()):\(requestHash)" }

    var approval: CameraCloudTransferApproval {
        CameraCloudTransferApproval(requestID: requestID, requestHash: requestHash,
                                    policyFingerprint: policyFingerprint)
    }
}

/// Ephemeral response to one visible disclosure. Never stored as blanket consent.
struct CameraCloudTransferApproval: Equatable, Sendable {
    let requestID: UUID
    let requestHash: String
    let policyFingerprint: String
}
