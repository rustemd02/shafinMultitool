import XCTest
@testable import shafinMultitool

/// M10-001: the iPad platform contract — universal binary, full
/// orientations, fullscreen-only windowing, no compatibility mode.
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

    func testFullscreenOnlyWindowing() {
        XCTAssertEqual(info["UIRequiresFullScreen"] as? Bool, true,
                       "multitasking windowing is out of scope and must not be claimed")
    }

    func testMinimumOSVersion() {
        XCTAssertEqual(info["MinimumOSVersion"] as? String, "17.0")
    }
}
