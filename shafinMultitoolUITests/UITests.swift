import UIKit
import XCTest

final class CameraCoachLaunchUITests: XCTestCase {
    private let launchTimeout: TimeInterval = 15
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    func testCameraPortraitShowsFullscreenFrameAndCompactScenesControl() {
        launchApp(orientation: .portrait)
        assertCameraCoachRoot()
        captureScreenshot(named: "CC-007C Camera portrait", expectedShape: .portrait)

        XCTAssertFalse(
            element(withIdentifier: "deviceBenchmarkStatusLabel").exists,
            "A normal UI smoke launch must not enter the benchmark root."
        )
    }

    func testCameraLandscapeLeftHasPhysicalLandscapeGeometryAndReadableUprightUI() {
        launchApp(orientation: .landscapeLeft)
        assertCameraCoachRoot()
        captureScreenshot(named: "CC-007C Camera landscape left", expectedShape: .landscape)
    }

    func testCameraLandscapeRightHasPhysicalLandscapeGeometryAndReadableUprightUI() {
        launchApp(orientation: .landscapeRight)
        assertCameraCoachRoot()
        captureScreenshot(named: "CC-007C Camera landscape right", expectedShape: .landscape)
    }

    func testSceneLibraryLandscapeHasPhysicalLandscapeGeometryAndReturnsToCamera() {
        launchApp(orientation: .landscapeLeft)
        assertCameraCoachRoot()

        let openScenesControl = element(withIdentifier: "commercial-shell-open-scenes")
        XCTAssertTrue(openScenesControl.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(openScenesControl.isHittable)
        openScenesControl.tap()

        let libraryRoot = element(withIdentifier: "library_root")
        XCTAssertTrue(
            libraryRoot.waitForExistence(timeout: launchTimeout),
            "Scenes must open the SET OS library root."
        )
        XCTAssertTrue(
            element(withIdentifier: "library_title").waitForExistence(timeout: launchTimeout),
            "The library contact-sheet title must be reachable."
        )
        let libraryContentExists = element(withIdentifier: "library_list").waitForExistence(timeout: launchTimeout)
            || element(withIdentifier: "library_empty_state").waitForExistence(timeout: launchTimeout)
        XCTAssertTrue(
            libraryContentExists,
            "The library must show either the contact sheet or the honest empty state."
        )

        let returnCameraControl = element(withIdentifier: "commercial-shell-return-camera")
        XCTAssertTrue(returnCameraControl.waitForExistence(timeout: launchTimeout))
        XCTAssertEqual(returnCameraControl.label, "Камера")
        XCTAssertTrue(returnCameraControl.isHittable)
        XCTAssertTrue(openScenesControl.waitForExistence(timeout: launchTimeout))
        XCTAssertEqual(openScenesControl.label, "Сцены")
        XCTAssertTrue(openScenesControl.isHittable)
        captureScreenshot(named: "CC-007C Scene library landscape", expectedShape: .landscape)

        returnCameraControl.tap()
        XCTAssertTrue(element(withIdentifier: "camera_coach_pause").waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(element(withIdentifier: "commercial-shell-open-scenes").waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(returnCameraControl.waitForExistence(timeout: launchTimeout))
        XCTAssertEqual(returnCameraControl.label, "Камера")
        XCTAssertTrue(returnCameraControl.isHittable)
    }

    func testCameraCoachSurfaceSurvivesPortraitLandscapeRotation() {
        launchApp(orientation: .landscapeLeft)
        assertCameraCoachRoot()

        let pauseControl = element(withIdentifier: "camera_coach_pause")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(pauseControl.waitForExistence(timeout: launchTimeout))

        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertTrue(pauseControl.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(pauseControl.isHittable)
        XCTAssertTrue(element(withIdentifier: "commercial-shell-open-scenes").isHittable)
    }

    private enum ScreenshotShape {
        case portrait
        case landscape
    }

    private func launchApp(orientation: UIDeviceOrientation? = nil) {
        if let orientation {
            if orientation.isLandscape {
                // Force a real device-orientation transition for repeated runs;
                // a no-op assignment does not notify the scene on iOS 26.
                XCUIDevice.shared.orientation = .portrait
            }
            XCUIDevice.shared.orientation = orientation
        }

        app.launchArguments = [
            "-ApplePersistenceIgnoreState",
            "YES"
        ]
        app.launchEnvironment = [
            "SHAFIN_UI_TESTING": "1",
            // An empty value is the app-owned no-benchmark state; no benchmark
            // configuration or benchmark work is supplied to this UI lane.
            "DEVICE_BENCHMARK_CONFIG_BASE64": ""
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
    }

    private func assertCameraCoachRoot() {
        XCTAssertTrue(element(withIdentifier: "commercial-shell").waitForExistence(timeout: launchTimeout))

        let modeControl = element(withIdentifier: "commercial-shell-mode-control")
        XCTAssertTrue(modeControl.waitForExistence(timeout: launchTimeout))
        XCTAssertGreaterThanOrEqual(
            modeControl.frame.height,
            60,
            "The published A/B ROLL control must expose its complete title and two-segment capsule."
        )
        let capsule = element(withIdentifier: "commercial-shell-mode-capsule")
        XCTAssertTrue(capsule.waitForExistence(timeout: launchTimeout))
        XCTAssertGreaterThanOrEqual(capsule.frame.height, 44)

        let openScenesControl = element(withIdentifier: "commercial-shell-open-scenes")
        XCTAssertTrue(openScenesControl.waitForExistence(timeout: launchTimeout))
        XCTAssertEqual(openScenesControl.label, "Сцены")
        XCTAssertTrue(openScenesControl.isHittable, "The compact mode control must be hittable.")
        XCTAssertGreaterThanOrEqual(openScenesControl.frame.width, 44)
        XCTAssertGreaterThanOrEqual(openScenesControl.frame.height, 44)
        XCTAssertLessThan(
            abs(modeControl.frame.midX - app.frame.midX),
            24,
            "The whole A/B ROLL mode control must remain top-centred."
        )
        let returnCameraControl = element(withIdentifier: "commercial-shell-return-camera")
        XCTAssertTrue(returnCameraControl.waitForExistence(timeout: launchTimeout))
        XCTAssertEqual(returnCameraControl.label, "Камера")
        XCTAssertTrue(returnCameraControl.isHittable)
        XCTAssertFalse(app.buttons["История"].exists)

        let pauseControl = element(withIdentifier: "camera_coach_pause")
        XCTAssertTrue(
            pauseControl.waitForExistence(timeout: launchTimeout),
            "The production Camera Coach surface must be reachable."
        )
        XCTAssertTrue(pauseControl.isHittable, "Camera Coach controls must remain readable and usable.")
        XCTAssertTrue(
            element(withIdentifier: "camera_coach_seeking_status").waitForExistence(timeout: launchTimeout),
            "The UI smoke must observe the normal seeking state, not a completed analysis."
        )
    }

    private func element(withIdentifier identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func captureScreenshot(named name: String, expectedShape: ScreenshotShape) {
        let screenshot = app.screenshot()
        guard let image = UIImage(data: screenshot.pngRepresentation),
              let cgImage = image.cgImage else {
            XCTFail("Could not decode XCTest screenshot \(name)")
            return
        }

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        switch expectedShape {
        case .portrait:
            XCTAssertGreaterThan(cgImage.height, cgImage.width, "\(name) must be physically portrait.")
        case .landscape:
            XCTAssertGreaterThan(cgImage.width, cgImage.height, "\(name) must be physically landscape.")
        }
    }
}
