import XCTest

final class CameraCoachProductionUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testCorrectiveRUPortraitUsesProductionMonitorSurface() {
        let app = launch(
            fixture: "camera.corrective",
            locale: "ru",
            orientation: .portrait
        )
        assertRoot("camera.corrective", in: app)
        assertStableCameraIdentifiers(in: app)
        attachScreenshot(app, named: "camera-corrective-ru-portrait")
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testCorrectiveENLandscapeUsesProductionMonitorSurface() {
        let app = launch(
            fixture: "camera.corrective",
            locale: "en",
            orientation: .landscapeLeft
        )
        assertRoot("camera.corrective", in: app)
        assertStableCameraIdentifiers(in: app)
        attachScreenshot(app, named: "camera-corrective-en-landscape")
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testNoisyFrameOcclusionSignalKeepsAdviceOnSafeEdgeInBothOrientations() {
        let cases: [(UIDeviceOrientation, String)] = [
            (.portrait, "camera-noisy-frame-portrait"),
            (.landscapeLeft, "camera-noisy-frame-landscape")
        ]

        for (orientation, attachmentName) in cases {
            let app = launch(
                fixture: "camera.noisy-frame",
                locale: "en",
                orientation: orientation,
                runtimeSignal: "noisy-frame"
            )
            assertRoot("camera.noisy-frame", in: app)
            assertStableCameraIdentifiers(in: app)
            attachScreenshot(app, named: attachmentName)
            app.terminate()
        }

        XCUIDevice.shared.orientation = .portrait
    }

    func testProductionLiveStateMatrix() {
        let fixtures = [
            "camera.seeking",
            "camera.keep",
            "camera.fallback",
            "camera.starting",
            "camera.failed",
            "camera.explanation",
            "camera.resuming",
            "camera.eco"
        ]

        for fixture in fixtures {
            let app = launch(fixture: fixture, locale: "ru", orientation: .portrait)
            assertRoot(fixture, in: app)
            XCTAssertTrue(
                app.otherElements["camera_coach_live_surface"].waitForExistence(timeout: 3),
                "Missing production monitor surface for \(fixture)"
            )
            attachScreenshot(app, named: fixture.replacingOccurrences(of: ".", with: "-"))
            app.terminate()
        }

        XCUIDevice.shared.orientation = .portrait
    }

    func testDecisionAndRecoveryFixturesReachProductionSurfaceInBothOrientations() {
        // These are DEBUG-only launch fixtures for the fixed Camera Coach
        // state families. They intentionally enter the shipped production
        // monitor surface in a separate app process; the owner-chain unit
        // suite proves the underlying planner/episode/verifier transitions.
        let fixtures: [(fixture: String, orientation: UIDeviceOrientation, state: String)] = [
            ("camera.select-subject", .portrait, "select_subject"),
            ("camera.wait", .landscapeLeft, "wait"),
            ("camera.abstain", .portrait, "abstain"),
            ("camera.corrective", .landscapeLeft, "corrective"),
            ("camera.explanation", .portrait, "explanation"),
            ("camera.movement", .landscapeLeft, "movement"),
            ("camera.verification", .portrait, "verification"),
            ("camera.keep", .landscapeLeft, "keep"),
            ("camera.interrupted", .portrait, "interrupted"),
            ("camera.recovery", .landscapeLeft, "recovery")
        ]

        for (fixture, orientation, state) in fixtures {
            let app = launch(fixture: fixture, locale: "en", orientation: orientation)
            assertRoot(fixture, in: app)
            assertStableCameraIdentifiers(in: app)
            XCTAssertTrue(
                app.otherElements["camera_coach_live_surface"].waitForExistence(timeout: 3),
                "Missing production monitor surface for (fixture)"
            )
            assertSemanticFixtureState(fixture, expectedState: state, in: app)
            if fixture == "camera.explanation" {
                XCTAssertTrue(app.descendants(matching: .any)["camera_coach_explanation"].exists)
            }
            attachScreenshot(app, named: "camera-decision-\(fixture.replacingOccurrences(of: ".", with: "-"))")
            app.terminate()
        }

        XCUIDevice.shared.orientation = .portrait
    }

    func testProductionInterruptedFixtureUsesLifecycleCopy() {
        let app = launch(
            fixture: "camera.interrupted",
            locale: "ru",
            orientation: .portrait
        )
        assertRoot("camera.interrupted", in: app)
        assertStableCameraIdentifiers(in: app)
        attachScreenshot(app, named: "camera-interrupted-ru-portrait")
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testPauseLoadingSuccessEmptyFailureMatrix() {
        let fixtures = [
            "camera.pause-loading",
            "camera.pause-success",
            "camera.pause-empty",
            "camera.pause-failure"
        ]

        for fixture in fixtures {
            let locale = fixture == "camera.pause-success" ? "en" : "ru"
            let app = launch(fixture: fixture, locale: locale, orientation: .portrait)
            assertRoot(fixture, in: app)
            XCTAssertTrue(
                app.otherElements["camera_coach_pause_review"].waitForExistence(timeout: 3),
                "Missing production pause review for \(fixture)"
            )
            XCTAssertTrue(app.buttons["camera_coach_pause"].exists)
            attachScreenshot(app, named: fixture.replacingOccurrences(of: ".", with: "-"))
            app.terminate()
        }

        XCUIDevice.shared.orientation = .portrait
    }

    func testProductionPauseTransitionAndResumeRoute() {
        let app = launch(fixture: "camera.corrective", locale: "ru", orientation: .portrait)
        assertRoot("camera.corrective", in: app)

        let pauseButton = app.buttons["camera_coach_pause"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 3))
        pauseButton.tap()

        let pauseReview = app.otherElements["camera_coach_pause_review"]
        XCTAssertTrue(pauseReview.waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "РАЗБОР")).firstMatch.waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.buttons["camera_coach_pause_action"].waitForExistence(timeout: 3),
            "the committed pause review must expose its existing accessible action"
        )

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(
            app.otherElements["camera_coach_pause_review"].waitForExistence(timeout: 3),
            "the committed pause review must survive portrait-to-landscape rotation"
        )
        XCTAssertTrue(app.buttons["camera_coach_pause"].exists)

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "РАЗБОР")).firstMatch.waitForExistence(timeout: 3),
            "the committed pause trace must remain inspectable after rotating back"
        )

        app.buttons["camera_coach_pause"].tap()
        XCTAssertTrue(app.otherElements["camera_coach_live_surface"].waitForExistence(timeout: 3))

        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testLensControlStartsCollapsedAndExpandsFromRealFixtureLenses() {
        let app = launch(fixture: "camera.lens-switching", locale: "en", orientation: .landscapeLeft)
        assertRoot("camera.lens-switching", in: app)

        let zoom = app.otherElements["camera_coach_zoom_control"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["WIDE"].exists)
        attachScreenshot(app, named: "camera-lens-collapsed-en-landscape")

        zoom.buttons.firstMatch.tap()
        XCTAssertGreaterThanOrEqual(zoom.buttons.count, 2)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ULTRA")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "TELE")).firstMatch.exists)
        attachScreenshot(app, named: "camera-lens-expanded-en-landscape")

        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testReduceMotionAndDynamicTypeKeepProductionSurfaceReadable() {
        let reduceMotionApp = launch(
            fixture: "camera.corrective",
            locale: "ru",
            orientation: .portrait,
            reduceMotion: true
        )
        assertRoot("camera.corrective", in: reduceMotionApp)
        assertVisibleTextFitsViewport("Сделай предложенное изменение кадра", in: reduceMotionApp)
        attachScreenshot(reduceMotionApp, named: "camera-corrective-ru-portrait-reduce-motion")
        reduceMotionApp.terminate()

        let dynamicTypeApp = launch(
            fixture: "camera.corrective",
            locale: "en",
            orientation: .landscapeLeft,
            dynamicType: true
        )
        assertRoot("camera.corrective", in: dynamicTypeApp)
        XCTAssertTrue(dynamicTypeApp.buttons["camera_coach_pause"].exists)
        assertVisibleTextFitsViewport("Make the suggested frame adjustment", in: dynamicTypeApp)
        attachScreenshot(dynamicTypeApp, named: "camera-corrective-en-landscape-dynamic-type")
        dynamicTypeApp.terminate()

        XCUIDevice.shared.orientation = .portrait
    }

    private func assertVisibleTextFitsViewport(
        _ label: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let text = app.staticTexts[label].firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 4), file: file, line: line)
        let viewport = app.frame
        XCTAssertGreaterThan(text.frame.width, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(text.frame.minX, viewport.minX, file: file, line: line)
        XCTAssertLessThanOrEqual(text.frame.maxX, viewport.maxX, file: file, line: line)
        XCTAssertGreaterThanOrEqual(text.frame.minY, viewport.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(text.frame.maxY, viewport.maxY, file: file, line: line)
    }

    private func launch(
        fixture: String,
        locale: String,
        orientation: UIDeviceOrientation,
        reduceMotion: Bool = false,
        dynamicType: Bool = false,
        runtimeSignal: String? = nil
    ) -> XCUIApplication {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments = [
            "-SHAFIN_CAMERA_PRODUCTION_FIXTURE", fixture,
            "-SHAFIN_SET_LOCALE", locale
        ]
        if reduceMotion {
            app.launchArguments += ["-SHAFIN_SET_REDUCE_MOTION", "1"]
        }
        if dynamicType {
            app.launchArguments += ["-SHAFIN_SET_DYNAMIC_TYPE", "xxl"]
        }
        if let runtimeSignal {
            app.launchArguments += ["-SHAFIN_CAMERA_RUNTIME_SIGNAL", runtimeSignal]
        }
        app.launch()
        return app
    }

    private func assertRoot(_ fixture: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            app.otherElements[fixture].waitForExistence(timeout: 4),
            "Missing deterministic production fixture \(fixture)",
            file: file,
            line: line
        )
    }

    private func assertStableCameraIdentifiers(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(
            app.buttons["camera_coach_close"].exists,
            "Camera Coach is the CommercialShell root; a close control would be nonfunctional.",
            file: file,
            line: line
        )
        XCTAssertTrue(app.buttons["camera_coach_pause"].exists, file: file, line: line)
        XCTAssertTrue(app.otherElements["camera_coach_live_surface"].exists, file: file, line: line)
    }

    private func assertSemanticFixtureState(
        _ fixtureID: String,
        expectedState: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let matchingElements = app
            .descendants(matching: .any)
            .matching(identifier: fixtureID)
        XCTAssertTrue(
            matchingElements.firstMatch.waitForExistence(timeout: 3),
            "Missing legacy command-band surface for \(fixtureID)",
            file: file,
            line: line
        )
        let matchingValues = (0..<matchingElements.count).compactMap { index in
            matchingElements.element(boundBy: index).value as? String
        }
        XCTAssertEqual(
            matchingValues.contains(expectedState),
            true,
            "Fixture \(fixtureID) must expose semantic state \(expectedState) via accessibilityValue",
            file: file,
            line: line
        )
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "v26-package2-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
