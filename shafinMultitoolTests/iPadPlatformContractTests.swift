import XCTest
@testable import shafinMultitool

/// M10-001: the iPad platform contract — universal binary, full
/// orientations and native resizable windows. Full-screen compatibility mode
/// scales controls below their intended hit size on iPadOS 26.
/// Assertions read the built product's Info.plist (the artifact that ships),
/// not the repository working directory.
final class iPadPlatformContractTests: XCTestCase {

    private var info: [String: Any] {
        Bundle.main.infoDictionary ?? [:]
    }

    func testAppIsUniversalBinary() {
        let families = info["UIDeviceFamily"] as? [Int] ?? []
        XCTAssertTrue(families.contains(1) && families.contains(2),
                      "universal binary required (families 1+2): no iPad compatibility mode, got \(families)")
    }

    func testAllFourOrientationsDeclared() {
        let orientations = info["UISupportedInterfaceOrientations"] as? [String] ?? []
        for orientation in ["UIInterfaceOrientationPortrait",
                            "UIInterfaceOrientationPortraitUpsideDown",
                            "UIInterfaceOrientationLandscapeLeft",
                            "UIInterfaceOrientationLandscapeRight"] {
            XCTAssertTrue(orientations.contains(orientation), "missing orientation \(orientation)")
        }
    }

    func testWindowingDoesNotUseScaledFullScreenCompatibilityMode() {
        XCTAssertEqual(info["UIRequiresFullScreen"] as? Bool, false,
                       "master plan §3.8 requires resizable iPad layouts with native control sizes")
    }

    func testMinimumOSVersion() {
        XCTAssertEqual(info["MinimumOSVersion"] as? String, "17.0")
    }
}
