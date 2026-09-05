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
        launch(
            permission: "notDetermined",
            intro: "notSeen",
            orientation: .portrait,
            contentSizeCategory: "UICTContentSizeCategoryL"
        )

        let introRoot = element(withIdentifier: "camera-coach-entry-intro")
        XCTAssertTrue(introRoot.waitForExistence(timeout: launchTimeout))

        let openCamera = element(withIdentifier: "camera-coach-entry-open-camera")
        XCTAssertTrue(openCamera.waitForExistence(timeout: launchTimeout))
        XCTAssertEqual(openCamera.label, "Открыть камеру")
        XCTAssertTrue(openCamera.isHittable)
        XCTAssertFalse(element(withIdentifier: "commercial-shell-open-scenes").exists)
        XCTAssertFalse(element(withIdentifier: "camera_coach_pause").exists)
        XCTAssertFalse(app.staticTexts["Deep Review"].exists)
        capturePortraitScreenshot(named: "CC-008 S01 intro portrait")

        openCamera.tap()

        let permissionRoot = element(withIdentifier: "camera-coach-entry-permission-context")
        XCTAssertTrue(permissionRoot.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(element(withIdentifier: "camera-coach-entry-continue").waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(element(withIdentifier: "commercial-shell-open-scenes").exists)
        XCTAssertFalse(element(withIdentifier: "camera_coach_pause").exists)
        capturePortraitScreenshot(named: "CC-008 S02 permission context portrait")
    }

    func testAuthorizedReturningUserReachesExistingCameraCoachRoot() {
        launch(permission: "authorized", intro: "seen", orientation: .portrait)

        XCTAssertTrue(element(withIdentifier: "commercial-shell").waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(element(withIdentifier: "camera_coach_pause").waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(element(withIdentifier: "camera_coach_live_surface").waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(element(withIdentifier: "camera_coach_close").exists)
        XCTAssertFalse(element(withIdentifier: "camera-coach-entry-intro").exists)
        capturePortraitScreenshot(named: "CC-008 live ready portrait")
    }

    func testDeniedStateShowsDistinctRecoveryWithoutLiveControls() {
        launch(permission: "denied", intro: "seen", orientation: .portrait)

        XCTAssertTrue(element(withIdentifier: "camera-coach-entry-blocked-denied").waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(app.staticTexts["ДОСТУП К КАМЕРЕ ВЫКЛЮЧЕН"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(element(withIdentifier: "camera-coach-entry-open-settings").waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(element(withIdentifier: "camera-coach-entry-recheck").waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(element(withIdentifier: "commercial-shell-open-scenes").exists)
        XCTAssertFalse(element(withIdentifier: "camera_coach_pause").exists)
        XCTAssertFalse(app.staticTexts["Deep Review"].exists)
        capturePortraitScreenshot(named: "CC-008 S03 denied portrait")
    }

    func testDeniedStateRechecksOnForegroundAndReachesExistingCameraCoachRoot() {
        launch(permission: "denied", intro: "seen", orientation: .portrait)

        XCTAssertTrue(element(withIdentifier: "camera-coach-entry-blocked-denied").waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(element(withIdentifier: "commercial-shell-open-scenes").exists)

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: launchTimeout))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))

        XCTAssertTrue(element(withIdentifier: "commercial-shell-open-scenes").waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(element(withIdentifier: "camera_coach_pause").waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(element(withIdentifier: "camera-coach-entry-blocked-denied").exists)
    }

    func testRestrictedStateUsesOnlyRecheckRecovery() {
        launch(permission: "restricted", intro: "seen", orientation: .portrait)

        XCTAssertTrue(element(withIdentifier: "camera-coach-entry-blocked-restricted").waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(app.staticTexts["КАМЕРА ОГРАНИЧЕНА СИСТЕМОЙ"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(element(withIdentifier: "camera-coach-entry-recheck").waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(element(withIdentifier: "commercial-shell-open-scenes").exists)
        XCTAssertFalse(element(withIdentifier: "camera-coach-entry-open-settings").exists)
        XCTAssertFalse(element(withIdentifier: "camera_coach_pause").exists)
        capturePortraitScreenshot(named: "CC-008 restricted portrait")
    }

    func testUnavailableStateShowsTruthfulDeviceRecovery() {
        launch(permission: "unavailable", intro: "seen", orientation: .portrait)

        XCTAssertTrue(element(withIdentifier: "camera-coach-entry-blocked-unavailable").waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(app.staticTexts["КАМЕРА НЕДОСТУПНА"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(element(withIdentifier: "camera-coach-entry-recheck").waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(element(withIdentifier: "commercial-shell-open-scenes").exists)
        XCTAssertFalse(element(withIdentifier: "camera-coach-entry-open-settings").exists)
        XCTAssertFalse(element(withIdentifier: "camera_coach_pause").exists)
        capturePortraitScreenshot(named: "CC-008 unavailable portrait")
    }

    func testUnknownStateUsesTruthfulRecheckOnlyRecovery() {
        launch(permission: "unknown", intro: "seen", orientation: .portrait)

        XCTAssertTrue(element(withIdentifier: "camera-coach-entry-blocked-unknown").waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(app.staticTexts["СТАТУС КАМЕРЫ НЕИЗВЕСТЕН"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(element(withIdentifier: "camera-coach-entry-recheck").waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(element(withIdentifier: "camera-coach-entry-open-settings").exists)
        XCTAssertFalse(element(withIdentifier: "camera-coach-entry-settings-fallback").exists)
        XCTAssertFalse(element(withIdentifier: "commercial-shell-open-scenes").exists)
        XCTAssertFalse(element(withIdentifier: "camera_coach_pause").exists)
        XCTAssertFalse(app.staticTexts["Deep Review"].exists)
        capturePortraitScreenshot(named: "CC-008 unknown portrait")
    }

    func testDeniedStateLandscapeUsesSplitLayoutAfterActiveRotation() {
        // Launch in portrait, then rotate the already-running process. iOS
        // 26.5 can capture a prelaunch landscape request as a rotated portrait.
        launch(permission: "denied", intro: "seen", orientation: .portrait)

        XCTAssertTrue(element(withIdentifier: "camera-coach-entry-blocked-denied").waitForExistence(timeout: launchTimeout))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))

        let posterRail = element(withIdentifier: "camera-coach-entry-poster-rail")
        let phaseColumn = element(withIdentifier: "camera-coach-entry-phase-column")
        XCTAssertTrue(posterRail.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(phaseColumn.waitForExistence(timeout: launchTimeout))
        XCTAssertGreaterThan(posterRail.frame.width, 0)
        XCTAssertGreaterThan(phaseColumn.frame.width, 0)
        XCTAssertGreaterThan(
            phaseColumn.frame.minX,
            posterRail.frame.maxX,
            "Landscape entry must place the phase column beside the poster rail."
        )

        let screenshot = app.screenshot()
        guard let image = UIImage(data: screenshot.pngRepresentation),
              let cgImage = image.cgImage else {
            XCTFail("Could not decode active-rotation landscape screenshot")
            return
        }

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "CC-008 S03 denied landscape active rotation"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertGreaterThan(cgImage.width, cgImage.height, "Active-rotation landscape capture must be physically landscape.")
    }

    func testDeniedStateLandscapeAccessibilityXXXLContentRemainsReachableAfterScroll() {
        launch(
            permission: "denied",
            intro: "seen",
            orientation: .portrait,
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL"
        )

        let root = element(withIdentifier: "camera-coach-entry-blocked-denied")
        XCTAssertTrue(root.waitForExistence(timeout: launchTimeout))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))

        let title = element(withIdentifier: "camera-coach-entry-blocked-title")
        let body = element(withIdentifier: "camera-coach-entry-blocked-body")
        let openSettings = element(withIdentifier: "camera-coach-entry-open-settings")
        let recheck = element(withIdentifier: "camera-coach-entry-recheck")
        XCTAssertTrue(title.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(body.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(openSettings.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(recheck.waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(title.label.isEmpty)
        XCTAssertFalse(body.label.isEmpty)
        XCTAssertGreaterThan(title.frame.width, 0)
        XCTAssertGreaterThan(body.frame.width, 0)

        let topScreenshot = app.screenshot()
        let topAttachment = XCTAttachment(screenshot: topScreenshot)
        topAttachment.name = "CC-008 S04 denied landscape AX XXXL top"
        topAttachment.lifetime = .keepAlways
        add(topAttachment)

        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: launchTimeout))
        scrollView.swipeUp()

        XCTAssertTrue(openSettings.isHittable, "AX XXXL primary recovery must remain reachable after scrolling.")
        XCTAssertTrue(recheck.isHittable, "AX XXXL secondary recovery must remain reachable after scrolling.")
        XCTAssertGreaterThan(openSettings.frame.height, 0)
        XCTAssertGreaterThan(recheck.frame.height, 0)

        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "CC-008 S04 denied landscape AX XXXL after recovery scroll"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(
        permission: String,
        intro: String,
        orientation: UIDeviceOrientation,
        contentSizeCategory: String? = nil
    ) {
        // Always establish the process in portrait. A landscape orientation
        // is applied only after launch by the caller-facing branch below.
        XCUIDevice.shared.orientation = .portrait

        var launchArguments = [
            "-ApplePersistenceIgnoreState",
            "YES",
            "-SHAFIN_CAMERA_PERMISSION_STATE",
            permission,
            "-SHAFIN_CAMERA_INTRO_STATE",
            intro
        ]
        if let contentSizeCategory {
            launchArguments += ["-UIPreferredContentSizeCategoryName", contentSizeCategory]
        }
        app.launchArguments = launchArguments
        app.launchEnvironment = [
            "SHAFIN_UI_TESTING": "1",
            "DEVICE_BENCHMARK_CONFIG_BASE64": ""
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))

        if orientation != .portrait {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        }
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
