import Foundation
import XCTest
@testable import shafinMultitool

/// Synthetic *.invalid interop fixture only; no deployment or provider terms.
/// Shared Swift/Python wire fixture, executed in the actual iOS app module.
final class SceneRemoteTransferPolicyInteropTests: XCTestCase {
    private func values() throws -> [String: String] {
        // ASCII JSON escapes preserve NFC/NFD distinctions in source editors.
        let input = #"""
        {
          "serviceEndpoint": "https://scene-policy-interop.invalid/\u0442\u0435\u0441\u0442/Caf\u00e9/Cafe\u0301/v1",
          "operatorName": "FIXTURE ONLY \u2014 \u0422\u0435\u0441\u0442\u043e\u0432\u044b\u0439 \u043e\u043f\u0435\u0440\u0430\u0442\u043e\u0440 / Caf\u00e9",
          "providerName": "FIXTURE ONLY / \u041f\u043e\u0441\u0442\u0430\u0432\u0449\u0438\u043a Cafe\u0301",
          "providerVersion": "fixture-provider/v1.0/\u03b2",
          "processingRegion": "FIXTURE ONLY \u2014 \u0440\u0435\u0433\u0438\u043e\u043d \u00ab\u0421\u0435\u0432\u0435\u0440/\u042e\u0433\u00bb",
          "sceneContentRetention": "FIXTURE ONLY \u2014 \u0441\u0440\u043e\u043a \u0441\u043e\u0434\u0435\u0440\u0436\u0438\u043c\u043e\u0433\u043e / \u043d\u0435 \u0443\u0441\u043b\u043e\u0432\u0438\u044f \u0441\u0435\u0440\u0432\u0438\u0441\u0430",
          "jobMetadataRetention": "FIXTURE ONLY \u2014 \u043c\u0435\u0442\u0430\u0434\u0430\u043d\u043d\u044b\u0435 / \u0443\u0447\u0435\u0431\u043d\u044b\u0439 \u0442\u0435\u043a\u0441\u0442",
          "securityIdentityRetention": "FIXTURE ONLY \u2014 \u0438\u0434\u0435\u043d\u0442\u0438\u0444\u0438\u043a\u0430\u0442\u043e\u0440/\u043f\u043e\u0432\u0442\u043e\u0440\u044b: \u0442\u0435\u0441\u0442",
          "spendRecordRetention": "FIXTURE ONLY \u2014 \u0440\u0430\u0441\u0445\u043e\u0434\u044b / \u043f\u0440\u0438\u043c\u0435\u0440 \u00ab\u20ac\u00bb",
          "deletionRequestProcedure": "FIXTURE ONLY \u2014 /\u043f\u0440\u0438\u043c\u0435\u0440/\u0437\u0430\u044f\u0432\u043a\u0430; \u043f\u043e\u043b\u0435 \"\u0442\u0435\u0441\u0442\"; \u0440\u0430\u0437\u0434\u0435\u043b\u0438\u0442\u0435\u043b\u044c \\",
          "providerRetention": "FIXTURE ONLY \u2014 \u0434\u0430\u043d\u043d\u044b\u0435 \u043f\u0440\u043e\u0432\u0430\u0439\u0434\u0435\u0440\u0430 / Caf\u00e9 / Cafe\u0301",
          "policyVersion": "fixture-policy/v1-\u00e9-e\u0301",
          "policyURL": "https://policy-interop.invalid/\u043f\u043e\u043b\u0438\u0442\u0438\u043a\u0430/\u043f\u0443\u0442\u044c \u0441 \u043f\u0440\u043e\u0431\u0435\u043b\u043e\u043c/Caf\u00e9/Cafe\u0301"
        }
        """#
        return try JSONDecoder().decode([String: String].self, from: Data(input.utf8))
    }

    private func policy(_ values: [String: String]) throws -> SceneRemoteTransferPolicy {
        try XCTUnwrap(SceneRemoteTransferPolicy(
            serviceEndpoint: try XCTUnwrap(URL(string: values["serviceEndpoint"]!)),
            operatorName: values["operatorName"]!,
            providerName: values["providerName"]!,
            providerVersion: values["providerVersion"]!,
            processingRegion: values["processingRegion"]!,
            sceneContentRetention: values["sceneContentRetention"]!,
            jobMetadataRetention: values["jobMetadataRetention"]!,
            securityIdentityRetention: values["securityIdentityRetention"]!,
            spendRecordRetention: values["spendRecordRetention"]!,
            deletionRequestProcedure: values["deletionRequestProcedure"]!,
            providerRetention: values["providerRetention"]!,
            policyVersion: values["policyVersion"]!,
            policyURL: try XCTUnwrap(URL(string: values["policyURL"]!))
        ))
    }

    func testSyntheticPolicyCanonicalBytesMatchSharedSwiftPythonFixture() throws {
        let policy = try policy(values())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(policy)
        let expectedHex = [
            "7b2264656c6574696f6e5265717565737450726f636564757265223a2246495854555245204f4e4c5920e28094202fd0",
            "bfd180d0b8d0bcd0b5d1802fd0b7d0b0d18fd0b2d0bad0b03b20d0bfd0bed0bbd0b5205c22d182d0b5d181d1825c223b",
            "20d180d0b0d0b7d0b4d0b5d0bbd0b8d182d0b5d0bbd18c205c5c222c226a6f624d65746164617461526574656e74696f",
            "6e223a2246495854555245204f4e4c5920e2809420d0bcd0b5d182d0b0d0b4d0b0d0bdd0bdd18bd0b5202f20d183d187",
            "d0b5d0b1d0bdd18bd0b920d182d0b5d0bad181d182222c226f70657261746f724e616d65223a2246495854555245204f",
            "4e4c5920e2809420d0a2d0b5d181d182d0bed0b2d18bd0b920d0bed0bfd0b5d180d0b0d182d0bed180202f20436166c3",
            "a9222c22706f6c69637955524c223a2268747470733a2f2f706f6c6963792d696e7465726f702e696e76616c69642f25",
            "44302542462544302542452544302542422544302542382544312538322544302542382544302542412544302542302f",
            "254430254246254431253833254431253832254431253843253230254431253831253230254430254246254431253830",
            "2544302542452544302542312544302542352544302542422544302542452544302542432f4361662543332541392f43",
            "616665254343253831222c22706f6c69637956657273696f6e223a22666978747572652d706f6c6963792f76312dc3a9",
            "2d65cc81222c2270726f63657373696e67526567696f6e223a2246495854555245204f4e4c5920e2809420d180d0b5d0",
            "b3d0b8d0bed0bd20c2abd0a1d0b5d0b2d0b5d1802fd0aed0b3c2bb222c2270726f76696465724e616d65223a22464958",
            "54555245204f4e4c59202f20d09fd0bed181d182d0b0d0b2d189d0b8d0ba2043616665cc81222c2270726f7669646572",
            "526574656e74696f6e223a2246495854555245204f4e4c5920e2809420d0b4d0b0d0bdd0bdd18bd0b520d0bfd180d0be",
            "d0b2d0b0d0b9d0b4d0b5d180d0b0202f20436166c3a9202f2043616665cc81222c2270726f766964657256657273696f",
            "6e223a22666978747572652d70726f76696465722f76312e302fceb2222c227363656e65436f6e74656e74526574656e",
            "74696f6e223a2246495854555245204f4e4c5920e2809420d181d180d0bed0ba20d181d0bed0b4d0b5d180d0b6d0b8d0",
            "bcd0bed0b3d0be202f20d0bdd0b520d183d181d0bbd0bed0b2d0b8d18f20d181d0b5d180d0b2d0b8d181d0b0222c2273",
            "656375726974794964656e74697479526574656e74696f6e223a2246495854555245204f4e4c5920e2809420d0b8d0b4",
            "d0b5d0bdd182d0b8d184d0b8d0bad0b0d182d0bed1802fd0bfd0bed0b2d182d0bed180d18b3a20d182d0b5d181d18222",
            "2c2273657276696365456e64706f696e74223a2268747470733a2f2f7363656e652d706f6c6963792d696e7465726f70",
            "2e696e76616c69642f2544312538322544302542352544312538312544312538322f4361662543332541392f43616665",
            "2543432538312f7631222c227370656e645265636f7264526574656e74696f6e223a2246495854555245204f4e4c5920",
            "e2809420d180d0b0d181d185d0bed0b4d18b202f20d0bfd180d0b8d0bcd0b5d18020c2abe282acc2bb227d",
        ].joined()
        XCTAssertEqual(bytes.count, 1195)
        XCTAssertEqual(bytes.map { String(format: "%02x", $0) }.joined(), expectedHex)
        XCTAssertEqual(policy.fingerprint, "5d0cf8345e02370b5f736cc5c61d792b1ad254d7983c351f7838d1c217be7893")
        XCTAssertEqual(policy.serviceEndpoint.absoluteString, "https://scene-policy-interop.invalid/%D1%82%D0%B5%D1%81%D1%82/Caf%C3%A9/Cafe%CC%81/v1")
        XCTAssertEqual(policy.policyURL.absoluteString, "https://policy-interop.invalid/%D0%BF%D0%BE%D0%BB%D0%B8%D1%82%D0%B8%D0%BA%D0%B0/%D0%BF%D1%83%D1%82%D1%8C%20%D1%81%20%D0%BF%D1%80%D0%BE%D0%B1%D0%B5%D0%BB%D0%BE%D0%BC/Caf%C3%A9/Cafe%CC%81")
    }

    func testCanonicallyEquivalentUnicodeKeepsDistinctConsentFingerprints() throws {
        var input = try values()
        let original = try policy(input)
        input["providerName"] = input["providerName"]!.precomposedStringWithCanonicalMapping
        let normalized = try policy(input)
        XCTAssertEqual(original.providerName, normalized.providerName)
        XCTAssertNotEqual(Array(original.providerName.utf8), Array(normalized.providerName.utf8))
        XCTAssertNotEqual(original.fingerprint, normalized.fingerprint)
        XCTAssertEqual(normalized.fingerprint, "c93732ce2310bcb7e03e0628757dcdd72119c1897e23c7b920f24d9a1df1ccd5")
    }
}
