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

        let sceneLibraryTitle = app.staticTexts["Выберите сцену:"]
        XCTAssertTrue(
            sceneLibraryTitle.waitForExistence(timeout: launchTimeout),
            "Scenes must open the existing Scene library root."
        )
        XCTAssertTrue(
            app.collectionViews.firstMatch.waitForExistence(timeout: launchTimeout),
            "The existing Scene library collection must be reachable."
        )

        let returnCameraControl = element(withIdentifier: "commercial-shell-return-camera")
        XCTAssertTrue(returnCameraControl.waitForExistence(timeout: launchTimeout))
        XCTAssertEqual(returnCameraControl.label, "Камера")
        XCTAssertTrue(returnCameraControl.isHittable)
        XCTAssertFalse(element(withIdentifier: "commercial-shell-open-scenes").exists)
        captureScreenshot(named: "CC-007C Scene library landscape", expectedShape: .landscape)

        returnCameraControl.tap()
        XCTAssertTrue(element(withIdentifier: "camera_coach_pause").waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(element(withIdentifier: "commercial-shell-open-scenes").waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(element(withIdentifier: "commercial-shell-return-camera").exists)
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

        let openScenesControl = element(withIdentifier: "commercial-shell-open-scenes")
        XCTAssertTrue(openScenesControl.waitForExistence(timeout: launchTimeout))
        XCTAssertEqual(openScenesControl.label, "Сцены")
        XCTAssertTrue(openScenesControl.isHittable, "The compact mode control must be hittable.")
        XCTAssertGreaterThanOrEqual(openScenesControl.frame.width, 44)
        XCTAssertGreaterThanOrEqual(openScenesControl.frame.height, 44)
        XCTAssertLessThan(
            abs(openScenesControl.frame.midX - app.frame.midX),
            24,
            "The Camera mode control must remain top-centred."
        )
        XCTAssertFalse(element(withIdentifier: "commercial-shell-return-camera").exists)
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
