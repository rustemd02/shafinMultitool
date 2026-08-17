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

    func testNormalLaunchShowsCommercialShellWithCameraCoachSelected() {
        launchApp(orientation: .portrait)
        assertCameraCoachRoot()
        attachScreenshot(named: "CC-007B Camera portrait")

        XCTAssertFalse(
            element(withIdentifier: "deviceBenchmarkStatusLabel").exists,
            "A normal UI smoke launch must not enter the benchmark root."
        )
    }

    func testScenesTabOpensProductionSceneLibraryAndReturnsToCamera() {
        launchApp(orientation: .landscapeLeft)
        assertCameraCoachRoot()

        let scenesTab = element(withIdentifier: "commercial-shell-section-scenes")
        XCTAssertTrue(scenesTab.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(scenesTab.isHittable)
        scenesTab.tap()

        let sceneLibraryTitle = app.staticTexts["Выберите сцену:"]
        XCTAssertTrue(
            sceneLibraryTitle.waitForExistence(timeout: launchTimeout),
            "Scenes must open the existing Scene library root."
        )
        XCTAssertTrue(
            app.collectionViews.firstMatch.waitForExistence(timeout: launchTimeout),
            "The existing Scene library collection must be reachable."
        )
        attachScreenshot(named: "CC-007B Scene library landscape")

        let cameraTab = element(withIdentifier: "commercial-shell-section-camera")
        cameraTab.tap()
        XCTAssertTrue(cameraTab.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(cameraTab.isSelected)
        XCTAssertTrue(element(withIdentifier: "camera_coach_pause").waitForExistence(timeout: launchTimeout))
    }

    func testHistoryShowsHonestEmptyStateAndReturnsToCamera() {
        launchApp(orientation: .portrait)
        assertCameraCoachRoot()

        let historyButton = element(withIdentifier: "commercial-shell-section-history")
        XCTAssertTrue(historyButton.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(historyButton.isHittable)
        historyButton.tap()

        let historyView = element(withIdentifier: "commercial-history-empty")
        XCTAssertTrue(historyView.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(app.staticTexts["История"].waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(
            app.staticTexts["Завершённые разборы этой сессии появятся здесь."]
                .waitForExistence(timeout: launchTimeout)
        )
        XCTAssertEqual(historyView.buttons.count, 0)
        attachScreenshot(named: "CC-007B History empty portrait")

        let cameraButton = element(withIdentifier: "commercial-shell-section-camera")
        cameraButton.tap()
        XCTAssertTrue(cameraButton.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(cameraButton.isSelected)
        XCTAssertTrue(element(withIdentifier: "camera_coach_pause").waitForExistence(timeout: launchTimeout))
    }

    func testPortraitLaunchShowsAppRootWithoutClaimingPortraitProductSupport() {
        launchApp(orientation: .portrait)
        assertCameraCoachRoot()
    }

    func testLandscapeLaunchShowsAppRootWithoutCrash() {
        launchApp(orientation: .landscapeLeft)
        assertCameraCoachRoot()
        attachScreenshot(named: "CC-007B Camera landscape")
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
    }

    private func launchApp(orientation: UIDeviceOrientation? = nil) {
        if let orientation {
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

        let cameraTab = element(withIdentifier: "commercial-shell-section-camera")
        XCTAssertTrue(cameraTab.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(cameraTab.isSelected, "Camera must be the default commercial-shell section.")

        for identifier in [
            "commercial-shell-section-camera",
            "commercial-shell-section-scenes",
            "commercial-shell-section-history"
        ] {
            let sectionButton = element(withIdentifier: identifier)
            XCTAssertTrue(sectionButton.waitForExistence(timeout: launchTimeout))
            XCTAssertTrue(sectionButton.isHittable, "Section control \(identifier) must be hittable.")
        }

        XCTAssertTrue(
            element(withIdentifier: "camera_coach_pause").waitForExistence(timeout: launchTimeout),
            "The production Camera Coach surface must be reachable."
        )
        XCTAssertTrue(
            element(withIdentifier: "camera_coach_seeking_status").waitForExistence(timeout: launchTimeout),
            "The UI smoke must observe the normal seeking state, not a completed analysis."
        )
    }

    private func element(withIdentifier identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
