import Foundation
import XCTest
@testable import shafinMultitool

/// Pure public-configuration and disclosure-value controls. No enrollment, provider,
/// transport, actual media decoding or user data is exercised by these fixtures.
final class CameraCloudTransferConsentTests: XCTestCase {
    private let endpoint = URL(string: "https://camera-policy.invalid/proxy/v1")!
    private let requestID = UUID(uuidString: "123e4567-e89b-42d3-a456-426614174000")!

    func testCompletePublicPolicyPreservesEveryDisclosedField() throws {
        let policy = try makePolicy()
        XCTAssertEqual(policy.serviceEndpoint, endpoint)
        XCTAssertEqual(policy.operatorName, "Fixture operator")
        XCTAssertEqual(policy.providerName, "fixture-vision")
        XCTAssertEqual(policy.providerVersion, "fixture-v1")
        XCTAssertEqual(policy.processingRegion, "Fixture region")
        XCTAssertEqual(policy.imageRetention, "Fixture image retention")
        XCTAssertEqual(policy.requestMetadataRetention, "Fixture request retention")
        XCTAssertEqual(policy.securityIdentityRetention, "Fixture security retention")
        XCTAssertEqual(policy.spendRecordRetention, "Fixture spend retention")
        XCTAssertEqual(policy.deletionRequestProcedure, "Fixture deletion procedure")
        XCTAssertEqual(policy.providerRetention, "Fixture provider retention")
        XCTAssertEqual(policy.policyVersion, "fixture-policy-v1")
        XCTAssertEqual(policy.policyURL, URL(string: "https://policy-docs.invalid/camera"))
        let fingerprint = try XCTUnwrap(policy.fingerprint)
        XCTAssertEqual(fingerprint.count, 64)
        XCTAssertEqual(policy.fingerprint, fingerprint)
    }

    func testMissingEveryConfiguredFieldFailsClosed() throws {
        let complete = configuration()
        XCTAssertNotNil(CameraCloudTransferPolicy.fromPublicConfiguration(complete, endpoint: endpoint))
        for key in complete.keys.sorted() {
            var missing = complete
            missing.removeValue(forKey: key)
            XCTAssertNil(CameraCloudTransferPolicy.fromPublicConfiguration(missing, endpoint: endpoint), key)
        }
    }

    func testEmptyPlaceholderWhitespaceAndNonStringPublicFieldsFailClosed() {
        let complete = configuration()
        let malformed: [Any] = ["", "  ", "$(UNRESOLVED_POLICY)", "value\n", 42, NSNull()]
        for key in complete.keys.sorted() {
            for value in malformed {
                var changed = complete
                changed[key] = value
                XCTAssertNil(CameraCloudTransferPolicy.fromPublicConfiguration(changed, endpoint: endpoint), key)
            }
        }
        var overlong = complete
        overlong["SETOSCameraPolicyImageRetention"] = String(repeating: "a", count: 2_049)
        XCTAssertNil(CameraCloudTransferPolicy.fromPublicConfiguration(overlong, endpoint: endpoint))
    }

    func testAPIRootNormalizationPreservesProxyPrefixAndRejectsEndpointMismatch() throws {
        var values = configuration()
        values["SETOSSceneBaseURL"] = "https://camera-policy.invalid/proxy"
        let policy = try XCTUnwrap(CameraCloudTransferPolicy.fromPublicConfiguration(values, endpoint: endpoint))
        XCTAssertEqual(policy.serviceEndpoint, endpoint)
        let mismatches = [
            "https://other-policy.invalid/proxy/v1", "https://camera-policy.invalid/other/v1",
            "https://camera-policy.invalid:8443/proxy/v1", "http://camera-policy.invalid/proxy/v1",
            "https://camera-policy.invalid/proxy/v1?route=other", "https://camera-policy.invalid/proxy/v1#other"
        ]
        for value in mismatches {
            let otherEndpoint = try XCTUnwrap(URL(string: value))
            XCTAssertNil(CameraCloudTransferPolicy.fromPublicConfiguration(values, endpoint: otherEndpoint), value)
        }
    }

    func testPolicyURLMustBePublicHTTPSWithoutCredentialsQueryOrFragment() {
        for value in ["http://policy-docs.invalid/camera", "https://user:pass@policy-docs.invalid/camera",
                      "https://policy-docs.invalid/camera?token=fixture", "https://policy-docs.invalid/camera#section",
                      "/relative-policy"] {
            var values = configuration()
            values["SETOSCameraPolicyURL"] = value
            XCTAssertNil(CameraCloudTransferPolicy.fromPublicConfiguration(values, endpoint: endpoint), value)
        }
    }

    func testEveryDisclosureFieldChangesThePolicyFingerprint() throws {
        let complete = configuration()
        let baseline = try makePolicy()
        let fingerprint = try XCTUnwrap(baseline.fingerprint)
        for key in complete.keys.sorted() {
            var changed = complete
            var changedEndpoint = endpoint
            switch key {
            case "SETOSSceneBaseURL":
                changedEndpoint = URL(string: "https://other-policy.invalid/proxy/v1")!
                changed[key] = changedEndpoint.absoluteString
            case "SETOSCameraPolicyURL":
                changed[key] = "https://policy-docs.invalid/camera-v2"
            default:
                changed[key] = (complete[key] as! String) + " changed"
            }
            let policy = try XCTUnwrap(CameraCloudTransferPolicy.fromPublicConfiguration(changed, endpoint: changedEndpoint), key)
            XCTAssertNotEqual(policy, baseline, key)
            XCTAssertNotEqual(try XCTUnwrap(policy.fingerprint), fingerprint, key)
        }
    }

    func testApprovalSeparatelyBindsRequestIdentityBodyHashAndPublicPolicy() throws {
        let policy = try makePolicy()
        let bodyA = Data("synthetic canonical request A".utf8)
        let bodyB = Data("synthetic canonical request B".utf8)
        let hashA = CameraCloudTransferPolicy.sha256(bodyA)
        let hashB = CameraCloudTransferPolicy.sha256(bodyB)
        let baseline = try disclosure(requestHash: hashA, policy: policy)
        XCTAssertEqual(baseline.approval.requestID, requestID)
        XCTAssertEqual(baseline.approval.requestHash, hashA)
        XCTAssertEqual(baseline.approval.policyFingerprint, policy.fingerprint)
        XCTAssertEqual(baseline.approval, try disclosure(requestHash: hashA, policy: policy).approval)

        let nextRequest = try disclosure(
            requestID: UUID(uuidString: "123e4567-e89b-42d3-a456-426614174001")!,
            requestHash: hashA, policy: policy
        )
        XCTAssertNotEqual(nextRequest.approval, baseline.approval)
        XCTAssertNotEqual(nextRequest.id, baseline.id)

        let changedBody = try disclosure(requestHash: hashB, policy: policy)
        XCTAssertNotEqual(changedBody.approval, baseline.approval)
        XCTAssertNotEqual(changedBody.id, baseline.id)

        var changedValues = configuration()
        changedValues["SETOSCameraPolicySecurityIdentityRetention"] = "Changed fixture security retention"
        let changedPolicy = try XCTUnwrap(CameraCloudTransferPolicy.fromPublicConfiguration(changedValues, endpoint: endpoint))
        let changedDisclosure = try disclosure(requestHash: hashA, policy: changedPolicy)
        XCTAssertNotEqual(changedDisclosure.approval, baseline.approval)
        // This is a value-level binding check. It does not assert that the DTO itself
        // calculates a transport's canonical body hash or authorizes a send.
    }

    func testDisclosureRetainsExactProvidedBytesAndImageFactsWithoutReencoding() throws {
        // Opaque synthetic bytes deliberately exercise storage identity only. JPEG
        // decoding, metadata removal and actual dimensions belong to encoder tests.
        var bytes = Data([0x11, 0x22, 0x33, 0x44])
        let original = bytes
        let policy = try makePolicy()
        let disclosure = try disclosure(bytes: bytes, requestHash: String(repeating: "c", count: 64), policy: policy)
        bytes[0] = 0xff
        XCTAssertEqual(disclosure.jpegData, original)
        XCTAssertNotEqual(disclosure.jpegData, bytes)
        XCTAssertEqual(disclosure.byteCount, original.count)
        XCTAssertEqual(disclosure.mediaSHA256, CameraCloudTransferPolicy.sha256(original))
        XCTAssertEqual(disclosure.snapshotID, "selected-snapshot-A")
        XCTAssertEqual(disclosure.pixelWidth, 640)
        XCTAssertEqual(disclosure.pixelHeight, 480)
        XCTAssertEqual(disclosure.policy, policy)
        XCTAssertEqual(disclosure.policyFingerprint, policy.fingerprint)
    }

    private func configuration() -> [String: Any] {
        [
            "SETOSSceneBaseURL": endpoint.absoluteString,
            "SETOSCameraPolicyOperatorName": "Fixture operator",
            "SETOSCameraProviderName": "fixture-vision",
            "SETOSCameraProviderVersion": "fixture-v1",
            "SETOSCameraPolicyProcessingRegion": "Fixture region",
            "SETOSCameraPolicyImageRetention": "Fixture image retention",
            "SETOSCameraPolicyRequestMetadataRetention": "Fixture request retention",
            "SETOSCameraPolicySecurityIdentityRetention": "Fixture security retention",
            "SETOSCameraPolicySpendRecordRetention": "Fixture spend retention",
            "SETOSCameraPolicyDeletionProcedure": "Fixture deletion procedure",
            "SETOSCameraPolicyProviderRetention": "Fixture provider retention",
            "SETOSCameraPolicyVersion": "fixture-policy-v1",
            "SETOSCameraPolicyURL": "https://policy-docs.invalid/camera"
        ]
    }

    private func makePolicy() throws -> CameraCloudTransferPolicy {
        try XCTUnwrap(CameraCloudTransferPolicy.fromPublicConfiguration(configuration(), endpoint: endpoint))
    }

    private func disclosure(requestID: UUID? = nil, bytes: Data = Data([0x11, 0x22, 0x33, 0x44]),
                             requestHash: String, policy: CameraCloudTransferPolicy) throws -> CameraCloudTransferRequest {
        CameraCloudTransferRequest(
            requestID: requestID ?? self.requestID, requestHash: requestHash,
            snapshotID: "selected-snapshot-A", mediaSHA256: CameraCloudTransferPolicy.sha256(bytes),
            jpegData: bytes, pixelWidth: 640, pixelHeight: 480, byteCount: bytes.count,
            policy: policy, policyFingerprint: try XCTUnwrap(policy.fingerprint)
        )
    }
}
