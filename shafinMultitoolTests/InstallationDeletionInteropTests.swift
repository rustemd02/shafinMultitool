import CryptoKit
import Foundation
import XCTest
@testable import shafinMultitool

final class InstallationDeletionInteropTests: XCTestCase {
    // Produced by the actual backend canonical_deletion_data function.
    // This opaque assertion is a synthetic wire fixture, never a device proof.
    private func proof(version: Int = 1, operationID: String = "123e4567-e89b-42d3-a456-426614174000",
                       keyID: String = "//////////////////////////////////////////8=",
                       challenge: String = "ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8=",
                       policy: String = "34fea8fbebf2b28df7be1ec76de7ef69e6f8caaf7961d14164eb9510c366efa8",
                       receiptHash: String = "ca2a4fe727faaecf16ecd130a86e0885c5540c05375340445071c0657555fd42",
                       assertion: String = "U1lOVEhFVElDLUFTU0VSVElPTi1OT1QtQS1ERVZJQ0UtUFJPT0Y=") -> InstallationDeletionProof {
        InstallationDeletionProof(version: version, operationID: operationID, keyID: keyID,
                                  challenge: challenge, policySHA256: policy,
                                  receiptSecretSHA256: receiptHash, assertionObject: assertion)
    }

    func testCanonicalProofBytesAndHashMatchActualPythonBackend() throws {
        let expected = #"{"challenge":"ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8=","key_id":"//////////////////////////////////////////8=","method":"POST","operation_id":"123e4567-e89b-42d3-a456-426614174000","path":"/v1/attest/deletions","policy_sha256":"34fea8fbebf2b28df7be1ec76de7ef69e6f8caaf7961d14164eb9510c366efa8","purpose":"installation_delete","receipt_secret_sha256":"ca2a4fe727faaecf16ecd130a86e0885c5540c05375340445071c0657555fd42","version":1}"#
        let data = try proof().canonicalClientData()
        XCTAssertEqual(data, Data(expected.utf8))
        XCTAssertEqual(data.count, 434)
        XCTAssertTrue(data.allSatisfy { $0 < 128 })
        XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                       "a6a55bd4fd2dbcdd3795025eeb7e7fb9a1262aaf713d690716cab28df8cb04a0")
    }

    func testProofCanBeHashedBeforeSigningButUnsignedBodyCannotBeSubmitted() throws {
        XCTAssertEqual(try proof(assertion: "").canonicalClientData(), try proof().canonicalClientData())
        XCTAssertThrowsError(try proof(assertion: "").encodedBody()) { error in
            XCTAssertEqual(error as? InstallationDeletionError, .invalidRequest)
        }
    }

    func testPersistedProofRoundtripPreservesExactReplayBodyAndNoExtraWireFields() throws {
        let original = proof()
        let persisted = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(InstallationDeletionProof.self, from: persisted)
        XCTAssertEqual(restored, original)
        XCTAssertEqual(try restored.encodedBody(), try original.encodedBody())
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: original.encodedBody()) as? [String: Any])
        XCTAssertEqual(Set(fields.keys), ["version", "operation_id", "key_id", "challenge",
                                          "policy_sha256", "receipt_secret_sha256", "assertion_object"])
        XCTAssertEqual(fields["assertion_object"] as? String, original.assertionObject)
        XCTAssertNil(fields["client_data_hash"])
        XCTAssertNil(fields["purpose"])
        XCTAssertNil(fields["receipt_secret"])
    }

    func testSignedFieldsRejectNoncanonicalUUIDSHAAndBase64() throws {
        let cases = [
            proof(version: 2),
            proof(operationID: "123E4567-E89B-42D3-A456-426614174000"),
            proof(operationID: "123e4567e89b42d3a456426614174000"),
            proof(keyID: "//////////////////////////////////////////8"),
            proof(keyID: "//////////////////////////////////////////9="),
            proof(keyID: "//////////////////////////////////////////8=\n"),
            proof(keyID: Data(repeating: 1, count: 31).base64EncodedString()),
            proof(challenge: Data(repeating: 1, count: 33).base64EncodedString()),
            proof(policy: String(repeating: "A", count: 64)),
            proof(receiptHash: String(repeating: "g", count: 64))
        ]
        for (index, item) in cases.enumerated() {
            XCTAssertThrowsError(try item.canonicalClientData(), "fixture \(index)") { error in
                XCTAssertEqual(error as? InstallationDeletionError, .invalidRequest)
            }
        }
    }

    func testEncodedBodyBoundsOpaqueAssertionAndRequiresCanonicalBase64() throws {
        for assertion in ["", "YQ", "YR==", "YQ==\n", Data(repeating: 1, count: 4_097).base64EncodedString()] {
            XCTAssertThrowsError(try proof(assertion: assertion).encodedBody()) { error in
                XCTAssertEqual(error as? InstallationDeletionError, .invalidRequest)
            }
        }
        XCTAssertNoThrow(try proof(assertion: Data(repeating: 1, count: 4_096).base64EncodedString()).encodedBody())
    }
}
