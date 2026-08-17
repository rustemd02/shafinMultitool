import UIKit
import XCTest

final class CameraCoachEntryFlowUITests: XCTestCase {
    private let launchTimeout: TimeInterval = 15
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testNewUserIntroShowsOnePrimaryActionAndReachesPermissionContext() {
        launch(permission: "notDetermined", intro: "notSeen", orientation: .portrait)

        let introRoot = element(withIdentifier: "camera-coach-entry-intro")
        XCTAssertTrue(introRoot.waitForExistence(timeout: launchTimeout))

        let openCamera = element(withIdentifier: "camera-coach-entry-open-camera")
        XCTAssertTrue(openCamera.waitForExistence(timeout: launchTimeout))
        XCTAssertEqual(openCamera.label, "Открыть камеру")
        XCTAssertTrue(openCamera.isHittable)
        XCTAssertFalse(element(withIdentifier: "camera_coach_pause").exists)
        XCTAssertFalse(app.staticTexts["Deep Review"].exists)
        capturePortraitScreenshot(named: "CC-008 S01 intro portrait")

        openCamera.tap()

        let permissionRoot = element(withIdentifier: "camera-coach-entry-permission-context")
        XCTAssertTrue(permissionRoot.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(element(withIdentifier: "camera-coach-entry-continue").waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(element(withIdentifier: "camera_coach_pause").exists)
        capturePortraitScreenshot(named: "CC-008 S02 permission context portrait")
    }

    func testAuthorizedReturningUserReachesExistingCameraCoachRoot() {
        launch(permission: "authorized", intro: "seen", orientation: .portrait)

        XCTAssertTrue(element(withIdentifier: "commercial-shell").waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(element(withIdentifier: "camera_coach_pause").waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(element(withIdentifier: "camera_coach_seeking_status").waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(element(withIdentifier: "camera-coach-entry-intro").exists)
        capturePortraitScreenshot(named: "CC-008 live ready portrait")
    }

    func testDeniedStateShowsDistinctRecoveryWithoutLiveControls() {
        launch(permission: "denied", intro: "seen", orientation: .portrait)

        XCTAssertTrue(element(withIdentifier: "camera-coach-entry-blocked-denied").waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(app.staticTexts["Доступ к камере выключен"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(element(withIdentifier: "camera-coach-entry-open-settings").waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(element(withIdentifier: "camera-coach-entry-recheck").waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(element(withIdentifier: "camera_coach_pause").exists)
        XCTAssertFalse(app.staticTexts["Deep Review"].exists)
        capturePortraitScreenshot(named: "CC-008 S03 denied portrait")
    }

    func testRestrictedStateUsesOnlyRecheckRecovery() {
        launch(permission: "restricted", intro: "seen", orientation: .portrait)

        XCTAssertTrue(element(withIdentifier: "camera-coach-entry-blocked-restricted").waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(app.staticTexts["Доступ к камере ограничен системой"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(element(withIdentifier: "camera-coach-entry-recheck").waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(element(withIdentifier: "camera-coach-entry-open-settings").exists)
        XCTAssertFalse(element(withIdentifier: "camera_coach_pause").exists)
    }

    func testUnavailableStateShowsTruthfulDeviceRecovery() {
        launch(permission: "unavailable", intro: "seen", orientation: .portrait)

        XCTAssertTrue(element(withIdentifier: "camera-coach-entry-blocked-unavailable").waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(app.staticTexts["Камера недоступна на этом устройстве"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(element(withIdentifier: "camera-coach-entry-recheck").waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(element(withIdentifier: "camera-coach-entry-open-settings").exists)
        XCTAssertFalse(element(withIdentifier: "camera_coach_pause").exists)
    }

    func testLandscapeCaptureIsRecordedOnlyAsHostEvidenceWhenShapeIsNotUpright() {
        launch(permission: "denied", intro: "seen", orientation: .landscapeLeft)

        XCTAssertTrue(element(withIdentifier: "camera-coach-entry-blocked-denied").waitForExistence(timeout: launchTimeout))
        let screenshot = app.screenshot()
        guard let image = UIImage(data: screenshot.pngRepresentation),
              let cgImage = image.cgImage else {
            XCTFail("Could not decode landscape host screenshot")
            return
        }

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "CC-008 landscape host evidence (manual review required)"
        attachment.lifetime = .keepAlways
        add(attachment)

        if cgImage.width <= cgImage.height {
            XCTSkip("Blocked: iOS 26.5 host capture is not physically landscape; attachment is evidence only.")
        }
    }

    private func launch(
        permission: String,
        intro: String,
        orientation: UIDeviceOrientation
    ) {
        if orientation.isLandscape {
            XCUIDevice.shared.orientation = .portrait
        }
        XCUIDevice.shared.orientation = orientation

        app.launchArguments = [
            "-ApplePersistenceIgnoreState",
            "YES",
            "-SHAFIN_CAMERA_PERMISSION_STATE",
            permission,
            "-SHAFIN_CAMERA_INTRO_STATE",
            intro
        ]
        app.launchEnvironment = [
            "SHAFIN_UI_TESTING": "1",
            "DEVICE_BENCHMARK_CONFIG_BASE64": ""
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
    }

    private func element(withIdentifier identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func capturePortraitScreenshot(named name: String) {
        let screenshot = app.screenshot()
        guard let image = UIImage(data: screenshot.pngRepresentation),
              let cgImage = image.cgImage else {
            XCTFail("Could not decode portrait screenshot \(name)")
            return
        }

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertGreaterThan(cgImage.height, cgImage.width, "\(name) must be physically portrait.")
    }
}
