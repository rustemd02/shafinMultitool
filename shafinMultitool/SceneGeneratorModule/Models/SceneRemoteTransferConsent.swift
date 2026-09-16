import CryptoKit
import Foundation

/// Public deployment information. No inferred provider terms, endpoint guesses
/// or default retention claims may authorize a transfer.
struct SceneRemoteTransferPolicy: Encodable, Equatable, Sendable {
    let serviceEndpoint: URL
    let operatorName: String
    let providerName: String
    let providerVersion: String
    let processingRegion: String
    let sceneContentRetention: String
    let jobMetadataRetention: String
    let securityIdentityRetention: String
    let spendRecordRetention: String
    let deletionRequestProcedure: String
    let providerRetention: String
    let policyVersion: String
    let policyURL: URL

    init?(
        serviceEndpoint: URL, operatorName: String,
        providerName: String, providerVersion: String, processingRegion: String,
        sceneContentRetention: String, jobMetadataRetention: String,
        securityIdentityRetention: String, spendRecordRetention: String,
        deletionRequestProcedure: String, providerRetention: String,
        policyVersion: String, policyURL: URL
    ) {
        guard SceneGenerationClient.isValidEndpoint(serviceEndpoint),
              Self.isValidPolicyURL(policyURL),
              [operatorName, providerName, providerVersion, processingRegion,
               sceneContentRetention, jobMetadataRetention, securityIdentityRetention,
               spendRecordRetention, deletionRequestProcedure, providerRetention,
               policyVersion].allSatisfy(Self.isValidPublicText) else { return nil }
        self.serviceEndpoint = serviceEndpoint
        self.operatorName = operatorName
        self.providerName = providerName
        self.providerVersion = providerVersion
        self.processingRegion = processingRegion
        self.sceneContentRetention = sceneContentRetention
        self.jobMetadataRetention = jobMetadataRetention
        self.securityIdentityRetention = securityIdentityRetention
        self.spendRecordRetention = spendRecordRetention
        self.deletionRequestProcedure = deletionRequestProcedure
        self.providerRetention = providerRetention
        self.policyVersion = policyVersion
        self.policyURL = policyURL
    }

    static func fromPublicConfiguration(
        _ values: [String: Any], endpoint: URL, providerName: String, providerVersion: String
    ) -> Self? {
        func field(_ suffix: String) -> String? {
            guard let value = values["SETOSScenePolicy" + suffix] as? String,
                  isValidPublicText(value) else { return nil }
            return value
        }
        guard let rawEndpoint = values["SETOSSceneBaseURL"] as? String,
              var declaredEndpoint = URL(string: rawEndpoint),
              SceneGenerationClient.isValidEndpoint(declaredEndpoint) else { return nil }
        if declaredEndpoint.lastPathComponent != "v1" { declaredEndpoint.appendPathComponent("v1") }
        guard declaredEndpoint == endpoint,
              values["SETOSSceneProviderName"] as? String == providerName,
              values["SETOSSceneProviderVersion"] as? String == providerVersion,
              let operatorName = field("OperatorName"),
              let region = field("ProcessingRegion"),
              let content = field("ContentRetention"),
              let metadata = field("JobMetadataRetention"),
              let security = field("SecurityIdentityRetention"),
              let spend = field("SpendRecordRetention"),
              let deletion = field("DeletionProcedure"),
              let provider = field("ProviderRetention"),
              let version = field("Version"),
              let rawURL = field("URL"), let url = URL(string: rawURL) else { return nil }
        return Self(
            serviceEndpoint: endpoint, operatorName: operatorName,
            providerName: providerName, providerVersion: providerVersion,
            processingRegion: region, sceneContentRetention: content,
            jobMetadataRetention: metadata, securityIdentityRetention: security,
            spendRecordRetention: spend, deletionRequestProcedure: deletion,
            providerRetention: provider, policyVersion: version, policyURL: url
        )
    }

    func matches(_ configuration: SceneGenerationClientConfiguration) -> Bool {
        serviceEndpoint == configuration.baseURL
            && providerName == configuration.providerName
            && providerVersion == configuration.providerVersion
    }

    var fingerprint: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func isValidPublicText(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 2_048
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.contains("$(")
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func isValidPolicyURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme?.lowercased() == "https"
            && components.host?.isEmpty == false
            && components.user == nil && components.password == nil
            && components.query == nil && components.fragment == nil
    }
}

struct SceneRemoteTransferRequest: Equatable, Sendable {
    let requestID: UUID
    let requestHash: String
    let scriptText: String
    let markedObjectIDs: [String]
    let policy: SceneRemoteTransferPolicy
    let policyFingerprint: String

    var id: String { "transfer:\(requestID.uuidString.lowercased()):\(policyFingerprint)" }

    var approval: SceneRemoteTransferApproval {
        SceneRemoteTransferApproval(
            requestID: requestID, requestHash: requestHash, policyFingerprint: policyFingerprint
        )
    }
}

/// Returning this value is an explicit response to one request. It is never
/// persisted as a blanket permission or reused for a different job.
struct SceneRemoteTransferApproval: Equatable, Sendable {
    let requestID: UUID
    let requestHash: String
    let policyFingerprint: String
}

typealias SceneRemoteTransferConsentHandler = @MainActor @Sendable (
    SceneRemoteTransferRequest
) async -> SceneRemoteTransferApproval?
