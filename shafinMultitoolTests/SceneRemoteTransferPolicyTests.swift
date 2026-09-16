import XCTest
@testable import shafinMultitool

/// Explicitly synthetic policy for local contract fixtures. It is never
/// installed as production bundle configuration or claimed as provider terms.
enum SceneTransferPolicyFixture {
    static func configuration() -> SceneGenerationClientConfiguration {
        var configuration = SceneGenerationClientConfiguration.placeholder
        configuration.baseURL = URL(string: "https://scene.example.test/v1")!
        return configuration
    }

    static func values(for configuration: SceneGenerationClientConfiguration = SceneTransferPolicyFixture.configuration()) -> [String: Any] {
        [
            "SETOSSceneBaseURL": configuration.baseURL.absoluteString,
            "SETOSSceneProviderName": configuration.providerName,
            "SETOSSceneProviderVersion": configuration.providerVersion,
            "SETOSScenePolicyOperatorName": "Local test operator",
            "SETOSScenePolicyProcessingRegion": "Local test region",
            "SETOSScenePolicyContentRetention": "Fixture content retention",
            "SETOSScenePolicyJobMetadataRetention": "Fixture metadata retention",
            "SETOSScenePolicySecurityIdentityRetention": "Fixture identity retention",
            "SETOSScenePolicySpendRecordRetention": "Fixture spend retention",
            "SETOSScenePolicyDeletionProcedure": "Fixture deletion procedure",
            "SETOSScenePolicyProviderRetention": "Fixture provider retention",
            "SETOSScenePolicyVersion": "fixture-policy-v1",
            "SETOSScenePolicyURL": "https://scene.example.test/privacy"
        ]
    }

    static func policy(for configuration: SceneGenerationClientConfiguration = SceneTransferPolicyFixture.configuration()) -> SceneRemoteTransferPolicy? {
        SceneRemoteTransferPolicy.fromPublicConfiguration(
            values(for: configuration), endpoint: configuration.baseURL,
            providerName: configuration.providerName, providerVersion: configuration.providerVersion
        )
    }
}

final class SceneRemoteTransferPolicyTests: XCTestCase {
    private func policy(_ values: [String: Any]) -> SceneRemoteTransferPolicy? {
        let configuration = SceneTransferPolicyFixture.configuration()
        return SceneRemoteTransferPolicy.fromPublicConfiguration(
            values, endpoint: configuration.baseURL,
            providerName: configuration.providerName, providerVersion: configuration.providerVersion
        )
    }

    func testEveryPublicPolicyFieldIsRequiredWithoutInferredDefaults() {
        let valid = SceneTransferPolicyFixture.values()
        XCTAssertNotNil(policy(valid))
        for key in valid.keys {
            var missing = valid
            missing.removeValue(forKey: key)
            XCTAssertNil(policy(missing), key)
        }
    }

    func testPolicyCannotMoveToAnotherEndpointOrProvider() {
        for (key, value) in [
            ("SETOSSceneBaseURL", "https://another.example.test/v1"),
            ("SETOSSceneProviderName", "another-provider"),
            ("SETOSSceneProviderVersion", "another-version")
        ] {
            var values = SceneTransferPolicyFixture.values()
            values[key] = value
            XCTAssertNil(policy(values), key)
        }
    }

    func testEmptyUnresolvedAndNonHttpsDisclosuresAreRejected() {
        for (key, value) in [
            ("SETOSScenePolicyProcessingRegion", ""),
            ("SETOSScenePolicySecurityIdentityRetention", "$(UNSET_POLICY)"),
            ("SETOSScenePolicyProviderRetention", " undecided "),
            ("SETOSScenePolicyOperatorName", "A\nB"),
            ("SETOSScenePolicyURL", "http://scene.example.test/privacy"),
            ("SETOSScenePolicyURL", "https://user:secret@scene.example.test/privacy")
        ] {
            var values = SceneTransferPolicyFixture.values()
            values[key] = value
            XCTAssertNil(policy(values), key)
        }
    }

    func testFingerprintBindsRetentionAndVersionIndependentlyOfDictionaryOrder() throws {
        let original = try XCTUnwrap(policy(SceneTransferPolicyFixture.values()))
        var reordered: [String: Any] = [:]
        for (key, value) in SceneTransferPolicyFixture.values().sorted(by: { $0.key > $1.key }) { reordered[key] = value }
        XCTAssertEqual(original.fingerprint, policy(reordered)?.fingerprint)
        for key in ["SETOSScenePolicyProviderRetention", "SETOSScenePolicySecurityIdentityRetention", "SETOSScenePolicyVersion"] {
            var changed = reordered
            changed[key] = "Changed fixture value"
            XCTAssertNotEqual(original.fingerprint, policy(changed)?.fingerprint, key)
        }
        XCTAssertEqual(original.fingerprint?.count, 64)
    }

    func testApprovalCannotAuthorizeAnotherRequestContentOrPolicy() throws {
        let policy = try XCTUnwrap(SceneTransferPolicyFixture.policy())
        let request = SceneRemoteTransferRequest(
            requestID: UUID(), requestHash: "content-a", scriptText: "Scene A", markedObjectIDs: [],
            policy: policy, policyFingerprint: try XCTUnwrap(policy.fingerprint)
        )
        XCTAssertNotEqual(request.approval, .init(requestID: UUID(), requestHash: request.requestHash, policyFingerprint: request.policyFingerprint))
        XCTAssertNotEqual(request.approval, .init(requestID: request.requestID, requestHash: "content-b", policyFingerprint: request.policyFingerprint))
        XCTAssertNotEqual(request.approval, .init(requestID: request.requestID, requestHash: request.requestHash, policyFingerprint: "different-policy"))
    }
}
