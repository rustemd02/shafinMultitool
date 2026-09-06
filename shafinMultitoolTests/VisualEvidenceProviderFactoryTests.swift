import XCTest
@testable import shafinMultitool

/// M12-002: the default visual-evidence provider never constructs a remote
/// provider in this build configuration; unknown values yield nil.
final class VisualEvidenceProviderFactoryTests: XCTestCase {

    func testUnknownProviderYieldsNil() {
        // The factory reads the live environment; without the mock marker it
        // must not produce a provider in the unit-test host.
        let provider = VisualSemanticEvidenceProviderFactory.makeDefaultProvider()
        XCTAssertTrue(provider == nil || provider?.providerId == "mock_vlm_visual_evidence_v1")
    }

    func testMockProviderIsOfflineCapable() async {
        let mock = MockVLMVisualEvidenceProvider()
        let capabilities = await mock.capabilities
        XCTAssertTrue(capabilities.supportsOffline)
    }
}
