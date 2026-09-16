import XCTest

final class SETPrivacyUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testPrivacyCanOpenBeforeCameraPermissionInBothLanguages() {
        for (locale, permission, intro, root) in [
            ("ru", "notDetermined", "notSeen", "camera-coach-entry-intro"),
            ("en", "denied", "seen", "camera-coach-entry-blocked-denied")
        ] {
            let app = XCUIApplication()
            app.launchEnvironment["SHAFIN_UI_TESTING"] = "1"
            app.launchArguments = [
                "-AppleLanguages", "(\(locale))", "-AppleLocale", locale,
                "-SHAFIN_CAMERA_PERMISSION_STATE", permission,
                "-SHAFIN_CAMERA_INTRO_STATE", intro,
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
            ]
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)[root].waitForExistence(timeout: 15))
            let entry = app.buttons["camera_entry_privacy"]
            assertTarget(entry, in: app)
            let primaryAction = app.buttons[intro == "notSeen"
                ? "camera-coach-entry-open-camera" : "camera-coach-entry-open-settings"]
            for _ in 0..<12 {
                if primaryAction.exists && primaryAction.isHittable
                    && primaryAction.frame.maxY <= entry.frame.minY { break }
                app.scrollViews.firstMatch.swipeUp()
            }
            assertTarget(primaryAction, in: app)
            if primaryAction.frame.maxY > entry.frame.minY {
                attach(app, name: "privacy-entry-overlap")
            }
            XCTAssertLessThanOrEqual(primaryAction.frame.maxY, entry.frame.minY,
                                     "Privacy footer must not cover the main entry action")
            entry.tap()
            let close = app.buttons["privacy_close"]
            assertTarget(close, in: app)
            XCTAssertTrue(app.staticTexts["privacy_account"].exists)
            XCTAssertFalse(app.buttons["camera_coach_pause"].exists)
            attach(app, name: "privacy-\(locale)-permission-\(permission)-AXXXL")
            close.tap()
            XCTAssertTrue(app.descendants(matching: .any)[root].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["commercial-shell-open-scenes"].exists)
            app.terminate()
        }
    }

    func testLibraryPrivacyContainsFullLicenseAndReturnsToLibrary() {
        let app = XCUIApplication()
        app.launchEnvironment["SHAFIN_UI_TESTING"] = "1"
        app.launchArguments = [
            "-AppleLanguages", "(en)", "-AppleLocale", "en",
            "-SHAFIN_CAMERA_PERMISSION_STATE", "authorized",
            "-SHAFIN_CAMERA_INTRO_STATE", "seen"
        ]
        app.launch()
        let scenes = app.buttons["commercial-shell-open-scenes"]
        XCTAssertTrue(scenes.waitForExistence(timeout: 15))
        scenes.tap()
        let entry = app.buttons["library_privacy"]
        assertTarget(entry, in: app)
        entry.tap()
        assertTarget(app.buttons["privacy_close"], in: app)
        let license = app.buttons["privacy_notice_snapkit"]
        let scroll = app.scrollViews["privacy_document"]
        XCTAssertTrue(scroll.exists)
        for _ in 0..<20 {
            let viewport = scroll.frame.intersection(app.windows.firstMatch.frame)
            if license.exists && license.isHittable && viewport.contains(license.frame) { break }
            // A partly exposed row is hittable. Bring its complete hit area
            // into the document viewport before asserting or tapping it.
            let targetAbove = license.exists && license.frame.minY < viewport.minY
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: targetAbove ? 0.35 : 0.75))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: targetAbove ? 0.75 : 0.35))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        assertTarget(license, in: app)
        XCTAssertTrue(scroll.frame.intersection(app.windows.firstMatch.frame).contains(license.frame))
        license.tap()
        let text = app.staticTexts["privacy_notice_text_snapkit"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertTrue(text.label.contains("Permission is hereby granted"))
        XCTAssertTrue(text.label.contains("THE SOFTWARE IS PROVIDED"))
        XCTAssertFalse(app.staticTexts["privacy_notice_unavailable_snapkit"].exists)
        attach(app, name: "privacy-library-full-notice")
        app.buttons["privacy_close"].tap()
        assertTarget(entry, in: app)
        app.terminate()
    }

    private func assertTarget(_ target: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        guard target.waitForExistence(timeout: 15) else {
            attach(app, name: "privacy-target-missing")
            XCTFail("The expected privacy Button does not exist", file: file, line: line)
            return
        }
        let ready = NSPredicate { _, _ in
            // AX converts scrolled rectangles between coordinate spaces.
            // A measured 44-point row can arrive as 43.999999999999886.
            // Ignore only arithmetic noise, far below one screen pixel.
            let arithmeticTolerance: CGFloat = 1e-9
            return target.exists && target.isHittable
                && target.frame.width + arithmeticTolerance >= 44
                && target.frame.height + arithmeticTolerance >= 44
                && app.windows.firstMatch.frame.contains(target.frame)
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 5)
        let frame = target.frame
        let geometry = "id=\(target.identifier) exists=\(target.exists) hittable=\(target.isHittable) width=\(String(format: "%.17g", Double(frame.width))) height=\(String(format: "%.17g", Double(frame.height))) frame=\(frame) window=\(app.windows.firstMatch.frame) contained=\(app.windows.firstMatch.frame.contains(frame))"
        if result != .completed {
            attach(app, name: "privacy-target-geometry")
            let detail = XCTAttachment(string: geometry)
            detail.name = "privacy-target-exact-geometry"
            detail.lifetime = .keepAlways
            add(detail)
        }
        XCTAssertEqual(result, .completed, "Privacy Button must be hittable, at least 44×44 and inside the window: " + geometry, file: file, line: line)
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + "-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
