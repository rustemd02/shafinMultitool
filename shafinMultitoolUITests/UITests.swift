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
        launchApp()
        assertCameraCoachRoot()

        XCTAssertFalse(
            element(withIdentifier: "deviceBenchmarkStatusLabel").exists,
            "A normal UI smoke launch must not enter the benchmark root."
        )
    }

    func testScenesTabOpensProductionSceneLibraryAndReturnsToCamera() {
        launchApp()
        assertCameraCoachRoot()

        let tabBar = app.tabBars["commercial-shell-tab-bar"]
        let scenesTab = tabBar.buttons["Scenes"]
        XCTAssertTrue(scenesTab.waitForExistence(timeout: launchTimeout))
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

        let cameraTab = tabBar.buttons["Camera"]
        cameraTab.tap()
        XCTAssertTrue(cameraTab.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(cameraTab.isSelected)
        XCTAssertTrue(element(withIdentifier: "camera_coach_pause").waitForExistence(timeout: launchTimeout))
    }

    func testPortraitLaunchShowsAppRootWithoutClaimingPortraitProductSupport() {
        launchApp(orientation: .portrait)
        assertCameraCoachRoot()
    }

    func testLandscapeLaunchShowsAppRootWithoutCrash() {
        launchApp(orientation: .landscapeLeft)
        assertCameraCoachRoot()
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

        let tabBar = app.tabBars["commercial-shell-tab-bar"]
        XCTAssertTrue(tabBar.waitForExistence(timeout: launchTimeout))

        let cameraTab = tabBar.buttons["Camera"]
        XCTAssertTrue(cameraTab.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(cameraTab.isSelected, "Camera must be the default commercial-shell section.")

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
}
