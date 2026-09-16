import CryptoKit
import Foundation
import XCTest
@testable import shafinMultitool

final class SETPrivacyInformationTests: XCTestCase {
    func testSceneDisclosureFollowsWiredRuntimeProviderRatherThanEnableFlag() {
        let parser = SceneParserService()
        XCTAssertEqual(SETPrivacyRuntimeFacts.current(sceneParser: parser).sceneDescription, .privacyScenesLocalBody)

        parser.configureRemoteOffload(enabled: true, provider: nil)
        XCTAssertEqual(SETPrivacyRuntimeFacts.current(sceneParser: parser).sceneDescription, .privacyScenesLocalBody)

        // Construction is inert: no token acquisition or network request. This
        // is the actual production provider type, wired through its owner.
        let provider = SceneGenerationClient()
        parser.configureRemoteOffload(enabled: true, provider: provider)
        XCTAssertEqual(SETPrivacyRuntimeFacts.current(sceneParser: parser).sceneDescription, .privacyScenesRemoteBody)

        parser.configureRemoteOffload(enabled: false, provider: provider)
        XCTAssertEqual(SETPrivacyRuntimeFacts.current(sceneParser: parser).sceneDescription, .privacyScenesLocalBody)
    }

    func testAllDisplayedNoticesMatchPreservedSourceBytesInBuiltApplication() throws {
        let expected: [String: String] = [
            "snapkit": "7c0d21cf5314759fd35a22e42a52099d9cad2570db55a78e4eda26c82493b96b",
            "llama_cpp": "94f29bbed6a22c35b992c5c6ebf0e7c92f13b836b90f36f461c9cf2f0f1d010d",
            "bebas_neue": "72082f6cb4d04be2ecf7cc7d9e1e7d73787f0af8a5a278a47cade70c16b78341",
            "caveat": "1f9d81d094273d82f3898a1ee8b598a717d050ecbf5ff7bede105b704880157b",
            "jetbrains_mono": "b2fe5e8987594e9ffd1d2ca52a2f5d73eb8335243893c5d6254b5ad69269591d",
            "oswald": "0fd731a904b729a4e02eaf5e8ebd06783edd9abe400e8882760160230675b652",
            "pt_mono": "511125dc85198375795fdbc109d088654d3b7f9dbd3ccb7bf93d844aef0b153c"
        ]
        XCTAssertEqual(Set(SETBundledLicenseNotice.all.map(\.id)), Set(expected.keys))
        let bundle = Bundle(for: SceneParserService.self)
        for notice in SETBundledLicenseNotice.all {
            let bytes = try XCTUnwrap(notice.data(in: bundle), "Missing bundled notice: \(notice.id)")
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, expected[notice.id], "The complete, unmodified source notice must ship: \(notice.id)")
            XCTAssertNotNil(notice.text(in: bundle), "Notice must be readable as UTF-8: \(notice.id)")
        }
    }
}
