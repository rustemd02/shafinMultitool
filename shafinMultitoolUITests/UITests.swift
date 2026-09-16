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
        captureScreenshot(named: "CC-007C Camera portrait en", expectedShape: .portrait)

        XCTAssertFalse(
            element(withIdentifier: "deviceBenchmarkStatusLabel").exists,
            "A normal UI smoke launch must not enter the benchmark root."
        )
    }

    func testCameraLandscapeLeftHasPhysicalLandscapeGeometryAndReadableUprightUI() {
        launchApp(orientation: .landscapeLeft)
        assertCameraCoachRoot()
        captureScreenshot(named: "CC-007C Camera landscape left en", expectedShape: .landscape)
    }

    func testCameraLandscapeRightHasPhysicalLandscapeGeometryAndReadableUprightUI() {
        launchApp(orientation: .landscapeRight)
        assertCameraCoachRoot()
        captureScreenshot(named: "CC-007C Camera landscape right en", expectedShape: .landscape)
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
        captureScreenshot(named: "CC-007C Scene library landscape en", expectedShape: .landscape)

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

    func testProControlsRemainReachableInPortraitAndLandscapeSceneReturnWithoutCaptureDevice() {
        for (orientation, language, captureName) in [
            (UIDeviceOrientation.portrait, "ru", "pro-controls-ru-portrait"),
            (.landscapeLeft, "en", "pro-controls-en-landscape-accessibility")
        ] {
            launchApp(orientation: orientation, language: language,
                      accessibilityText: language == "en",
                      enterLandscapeThroughScenes: orientation.isLandscape)
            let toggle = element(withIdentifier: "pro_controls_toggle")
            XCTAssertTrue(toggle.waitForExistence(timeout: launchTimeout))
            XCTAssertTrue(toggle.isHittable)
            toggle.tap()

            let panel = app.descendants(matching: .any).matching(identifier: "pro_controls_panel").firstMatch
            XCTAssertTrue(panel.waitForExistence(timeout: launchTimeout))
            XCTAssertGreaterThanOrEqual(panel.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(panel.frame.maxX, app.frame.maxX)
            XCTAssertFalse(toggle.isHittable, "The camera chrome must not intercept touches while Pro Controls is presented.")
            let format = app.buttons["pro_control_formatResolutionFPS"]
            XCTAssertTrue(format.waitForExistence(timeout: launchTimeout))
            XCTAssertFalse(format.isEnabled, "The UI capture seam has no device or supported formats.")
            attachProControlsDeviceEvidence(named: captureName + "-top")
            captureScreenshot(named: captureName + "-top",
                              expectedShape: orientation.isLandscape ? .landscape : .portrait)

            let scrollView = app.scrollViews["pro_controls_scroll"]
            XCTAssertTrue(scrollView.exists)
            let microphone = app.buttons["pro_control_microphone_enable"]
            for _ in 0..<8 where !microphone.isHittable { scrollView.swipeUp() }
            XCTAssertTrue(microphone.isHittable, "The microphone control must be reachable at the bottom of Pro Controls.")
            XCTAssertFalse(microphone.isEnabled, "No capture owner is available for microphone metering in this seam.")
            attachProControlsDeviceEvidence(named: captureName + "-bottom")
            captureScreenshot(named: captureName + "-bottom",
                              expectedShape: orientation.isLandscape ? .landscape : .portrait)

            let close = app.buttons["pro_controls_close"]
            XCTAssertTrue(close.isHittable, "Close must stay reachable while the settings are scrolled.")
            XCTAssertGreaterThanOrEqual(close.frame.width, 44)
            XCTAssertGreaterThanOrEqual(close.frame.height, 44)
            close.tap()
            XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
            XCTAssertTrue(toggle.isHittable)
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
    }

    func testCameraRecordingControlsRemainVisibleWithoutInventingCaptureAvailability() {
        for language in ["ru", "en"] {
            launchApp(orientation: .portrait, language: language, accessibilityText: language == "en")
            let controls = element(withIdentifier: "camera_recording_controls")
            XCTAssertTrue(controls.waitForExistence(timeout: launchTimeout), "The real Camera factory must present recording controls.")
            XCTAssertFalse(element(withIdentifier: "camera_recording_unavailable_controls").exists)
            attachProControlsDeviceEvidence(named: "camera-recording-\(language)-portrait")
            let viewport = app.windows.firstMatch.frame
            for identifier in ["camera_recording_sound", "camera_recording_start"] {
                let control = identifier == "camera_recording_sound" ? app.switches[identifier] : app.buttons[identifier]
                XCTAssertTrue(control.exists, "\(identifier) must keep its native accessible control type.")
                XCTAssertGreaterThanOrEqual(control.frame.width, 44)
                XCTAssertGreaterThanOrEqual(control.frame.height, 44)
                XCTAssertGreaterThanOrEqual(control.frame.minX, viewport.minX)
                XCTAssertGreaterThanOrEqual(control.frame.minY, viewport.minY)
                XCTAssertLessThanOrEqual(control.frame.maxX, viewport.maxX)
                XCTAssertLessThanOrEqual(control.frame.maxY, viewport.maxY)
                XCTAssertFalse(control.isEnabled, "The UI seam has no actual capture formats; it must not offer a successful take.")
            }
            XCTAssertFalse(app.buttons["camera_recording_stop"].exists)
            XCTAssertFalse(app.buttons["camera_recording_play"].exists)
            for identifier in ["camera_coach_pause", "pro_controls_toggle"] {
                let control = app.buttons[identifier]
                XCTAssertTrue(control.isHittable, "Recording must leave the existing Camera controls reachable.")
                XCTAssertLessThanOrEqual(control.frame.maxY, controls.frame.minY)
            }
            app.terminate()
        }
    }

    private enum ScreenshotShape {
        case portrait
        case landscape
    }

    private func attachProControlsDeviceEvidence(named name: String) {
        // Keep a device screenshot beside the app crop. Their pixel bounds and
        // orientation metadata can differ on a rotated simulator presentation.
        let device = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        device.name = name + "-device"
        device.lifetime = .keepAlways
        add(device)
        let hierarchy = XCTAttachment(string: "deviceOrientation=\(XCUIDevice.shared.orientation.rawValue)\n" + app.debugDescription)
        hierarchy.name = name + "-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    private func launchApp(orientation: UIDeviceOrientation? = nil,
                           language: String? = nil,
                           accessibilityText: Bool = false,
                           enterLandscapeThroughScenes: Bool = false) {
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
        if let language {
            app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", language,
                                    "-SHAFIN_SET_LOCALE", language]
        }
        if accessibilityText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launchEnvironment = [
            "SHAFIN_UI_TESTING": "1",
            // An empty value is the app-owned no-benchmark state; no benchmark
            // configuration or benchmark work is supplied to this UI lane.
            "DEVICE_BENCHMARK_CONFIG_BASE64": ""
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        if let orientation {
            XCTAssertTrue(element(withIdentifier: "commercial-shell").waitForExistence(timeout: launchTimeout))
            if enterLandscapeThroughScenes && orientation.isLandscape {
                // Exercise a real user path for landscape layout. This lane
                // does not qualify direct device rotation: the isolated iOS
                // simulator currently reports UIDevice.orientation == unknown
                // inside Camera despite the XCUIDevice orientation event.
                app.buttons["commercial-shell-open-scenes"].tap()
                XCTAssertTrue(element(withIdentifier: "library_root").waitForExistence(timeout: launchTimeout))
                let landscape = NSPredicate { [weak self] _, _ in
                    guard let self else { return false }
                    let frame = self.app.windows.firstMatch.frame
                    return frame.width > frame.height
                }
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landscape, object: app)], timeout: 8), .completed,
                               "The Scene route must actually finish its landscape transition before returning to Camera.")
                app.buttons["commercial-shell-return-camera"].tap()
                XCTAssertTrue(app.buttons["camera_coach_pause"].waitForExistence(timeout: launchTimeout))
            } else {
                if orientation.isLandscape { XCUIDevice.shared.orientation = .portrait }
                XCUIDevice.shared.orientation = orientation
            }
            let predicate = NSPredicate { [weak self] _, _ in
                guard let self, self.app.windows.firstMatch.exists else { return false }
                let frame = self.app.windows.firstMatch.frame
                return orientation.isLandscape ? frame.width > frame.height : frame.height > frame.width
            }
            let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: app)], timeout: 8)
            if result != .completed {
                attachProControlsDeviceEvidence(named: "requested-orientation-\(orientation.rawValue)-not-adopted")
                let probe = element(withIdentifier: "camera_coach_lifecycle_diagnostic")
                let diagnostic = XCTAttachment(string: probe.exists ? String(describing: probe.value) : "Lifecycle probe missing")
                diagnostic.name = "Live UIKit orientation state before interaction"
                diagnostic.lifetime = .keepAlways
                add(diagnostic)
            }
            XCTAssertEqual(result, .completed, "The actual application window must adopt the requested device orientation before interaction.")
        }
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
        let isSeeking = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Ищу главное в кадре…"))
            .firstMatch.waitForExistence(timeout: launchTimeout)
        let diagnostic = element(withIdentifier: "camera_coach_lifecycle_diagnostic")
        if diagnostic.exists || !isSeeking {
            let value = diagnostic.exists ? diagnostic.value as? String ?? "Missing diagnostic value" : "No lifecycle diagnostic available"
            let attachment = XCTAttachment(string: value + (isSeeking ? "" : "\n" + app.debugDescription))
            attachment.name = "Camera startup lifecycle and UI hierarchy"
            attachment.lifetime = .keepAlways
            add(attachment)
            if isSeeking && diagnostic.exists {
                XCTAssertTrue(value.contains("viewModel=running;"))
                XCTAssertTrue(value.contains("manager=running;"))
                XCTAssertTrue(value.contains("uiWindowScene=foregroundActive;"))
            }
        }
        XCTAssertTrue(isSeeking, "The UI smoke must observe the normal seeking state, not a completed analysis.")
    }

    private func element(withIdentifier identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func captureScreenshot(named name: String, expectedShape: ScreenshotShape) {
        // The application crop can use stale rotated bounds in the simulator.
        // Capture the full display and assert the actual UIKit window geometry;
        // PNG/EXIF pixel storage orientation is recorded, not treated as layout.
        let screenshot = XCUIScreen.main.screenshot()
        guard let image = UIImage(data: screenshot.pngRepresentation),
              let cgImage = image.cgImage else {
            XCTFail("Could not decode XCTest screenshot \(name)")
            return
        }

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let frame = app.windows.firstMatch.frame
        let geometry = XCTAttachment(string: "window=\(frame);storedPixels=\(cgImage.width)x\(cgImage.height);imageOrientation=\(image.imageOrientation.rawValue)")
        geometry.name = name + "-geometry"
        geometry.lifetime = .keepAlways
        add(geometry)

        switch expectedShape {
        case .portrait:
            XCTAssertGreaterThan(frame.height, frame.width, "\(name) must have a portrait application window.")
        case .landscape:
            XCTAssertGreaterThan(frame.width, frame.height, "\(name) must have a landscape application window.")
        }
    }
}
