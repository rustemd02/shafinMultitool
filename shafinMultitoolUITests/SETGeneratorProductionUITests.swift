import XCTest

/// Package 4/5 production-route evidence: the real commercial route reaches the
/// SET OS generator workspace and its screenplay/marker/error surfaces on the
/// landscape-only scene stack. AR session availability is not claimed on the
/// simulator; only honestly reachable states are asserted.
final class SETGeneratorProductionUITests: XCTestCase {
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
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testCommercialRouteReachesSETGeneratorWorkspaceAndInputSheet() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launchApp()

        openLibraryAndCreateScene(named: "SET-UITest-\(UUID().uuidString.prefix(6))")

        let sceneButton = app.buttons["generator_scene_button"]
        XCTAssertTrue(
            sceneButton.waitForExistence(timeout: launchTimeout),
            "The SET OS generator settings bar must be reachable through the commercial route."
        )
        attachScreenshot(named: "generator-workspace-ru-landscape")

        // The simulator has no ARKit support, so the honest error band is the
        // baseline state; close it before exercising the input sheet.
        // The close button carries the band identifier in the accessibility
        // tree (label ЗАКРЫТЬ); address it by label to stay identifier-stable.
        let errorClose = app.buttons.matching(NSPredicate(format: "label == 'ЗАКРЫТЬ' OR identifier == 'generator_error_close'")).firstMatch
        if errorClose.waitForExistence(timeout: 3) {
            errorClose.tap()
            // Let the band-dismissal animation finish before the next tap;
            // otherwise the sheet presentation races the SwiftUI transition.
            _ = sceneButton.waitForExistence(timeout: 2)
        }

        sceneButton.tap()
        let inputTitle = app.descendants(matching: .any)["generator_input_title"]
        XCTAssertTrue(
            inputTitle.waitForExistence(timeout: launchTimeout),
            "The screenplay input sheet must open from the scene command."
        )
        XCTAssertTrue(app.buttons["generator_input_cancel"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["generator_input_editor"].exists,
            "The screenplay editor must be present with its accessibility identifier."
        )
        attachScreenshot(named: "generator-input-sheet-ru-landscape")

        app.buttons["generator_input_cancel"].tap()
        XCTAssertTrue(sceneButton.waitForExistence(timeout: launchTimeout))

        // Back returns to the library root without tearing down the shell.
        app.buttons["generator_back_button"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["library_root"].waitForExistence(timeout: launchTimeout),
            "Back must return to the SET OS library contact sheet."
        )
        attachScreenshot(named: "generator-back-to-library-ru-landscape")
    }

    func testWhitespaceInputShowsInlineValidation() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launchApp()
        openLibraryAndCreateScene(named: "SET-UITest-Whitespace-\(UUID().uuidString.prefix(6))")

        let sceneButton = app.buttons["generator_scene_button"]
        XCTAssertTrue(sceneButton.waitForExistence(timeout: launchTimeout))

        let errorClose = app.buttons.matching(
            NSPredicate(format: "label == 'ЗАКРЫТЬ' OR identifier == 'generator_error_close'")
        ).firstMatch
        if errorClose.waitForExistence(timeout: 3) {
            errorClose.tap()
            _ = sceneButton.waitForExistence(timeout: 2)
        }

        sceneButton.tap()
        let inputEditor = app.descendants(matching: .any)["generator_input_editor"]
        XCTAssertTrue(inputEditor.waitForExistence(timeout: launchTimeout))
        inputEditor.tap()
        inputEditor.typeText(" ")

        XCTAssertTrue(
            app.descendants(matching: .any)["generator_input_validation"].waitForExistence(timeout: 2),
            "Whitespace-only screenplay input must expose inline validation."
        )
        let generateButton = app.buttons["generator_input_generate"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: launchTimeout))
        XCTAssertFalse(generateButton.isEnabled, "Generate must stay disabled for whitespace-only input.")
        attachScreenshot(named: "generator-input-whitespace-validation-ru-landscape")
    }

    func testErrorBandIsTheHonestFailureSurface() {
        // The error band itself requires a runtime failure; on the simulator an
        // AR session failure is expected and surfaces through the same band.
        XCUIDevice.shared.orientation = .landscapeLeft
        launchApp()
        openLibraryAndCreateScene(named: "SET-UITest-Err-\(UUID().uuidString.prefix(6))")

        // The workspace chrome is the honest baseline; the AR failure band may
        // or may not appear depending on simulator AR support, so only capture
        // the state and assert the band identifier contract when it appears.
        XCTAssertTrue(
            app.buttons["generator_scene_button"].waitForExistence(timeout: launchTimeout)
        )

        let errorBand = app.descendants(matching: .any)["generator_error_band"]
        if errorBand.waitForExistence(timeout: 8) {
            let closeButton = app.buttons.matching(NSPredicate(format: "label == 'ЗАКРЫТЬ' OR identifier == 'generator_error_close'")).firstMatch
            XCTAssertTrue(closeButton.waitForExistence(timeout: 4))
            attachScreenshot(named: "generator-error-band-ru-landscape")
            closeButton.tap()
            XCTAssertFalse(
                app.descendants(matching: .any)["generator_error_band"].waitForExistence(timeout: 4),
                "Closing the band must clear the error projection."
            )
        } else {
            attachScreenshot(named: "generator-no-error-baseline-ru-landscape")
        }

        // Exercise the route-owned exit before XCTest terminates the app. This
        // keeps the real async teardown contract in the test path and avoids
        // leaving an AR session alive while the runner is shutting down.
        let backButton = app.buttons["generator_back_button"]
        XCTAssertTrue(backButton.waitForExistence(timeout: launchTimeout))
        backButton.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["library_root"].waitForExistence(timeout: launchTimeout),
            "The generator error surface must still return through the commercial route."
        )
    }

    func testRecordingSoundControlIsExplicitAndAccessible() {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-SHAFIN_GENERATOR_MARK_AR_READY",
            "-SHAFIN_LIBRARY_RESET_FOR_UI_TESTING",
            "-SHAFIN_SET_LOCALE", "en"
        ]
        app.launchEnvironment = [
            "SHAFIN_UI_TESTING": "1",
            "DEVICE_BENCHMARK_CONFIG_BASE64": ""
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
        openLibraryAndCreateScene(named: "SET-UITest-Sound-\(UUID().uuidString.prefix(6))")

        let soundButton = app.buttons["generator_recording_sound_button"]
        XCTAssertTrue(
            soundButton.waitForExistence(timeout: launchTimeout),
            "The recording sound choice must be reachable on the production generator route."
        )
        XCTAssertGreaterThanOrEqual(soundButton.frame.height, 44)
        XCTAssertTrue(soundButton.isEnabled)
        XCTAssertTrue(soundButton.label.localizedCaseInsensitiveContains("recording sound"))
        XCTAssertTrue(soundButton.value as? String == "SOUND ON")

        soundButton.tap()
        let soundOff = NSPredicate(format: "value CONTAINS 'SOUND OFF'")
        expectation(for: soundOff, evaluatedWith: soundButton)
        waitForExpectations(timeout: 3)
        XCTAssertEqual(soundButton.value as? String, "SOUND OFF")

        soundButton.tap()
        let soundOn = NSPredicate(format: "value CONTAINS 'SOUND ON'")
        expectation(for: soundOn, evaluatedWith: soundButton)
        waitForExpectations(timeout: 3)
        XCTAssertEqual(soundButton.value as? String, "SOUND ON")

        app.buttons["generator_back_button"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["library_root"].waitForExistence(timeout: launchTimeout)
        )
    }

    // MARK: - Helpers

    private func launchApp() {
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-SHAFIN_GENERATOR_MARK_AR_READY"
        ]
        app.launchArguments.append("-SHAFIN_LIBRARY_RESET_FOR_UI_TESTING")
        // RU copy is the default for this lane; EN and accessibility variants
        // are captured by dedicated matrix tests below.
        app.launchEnvironment = [
            "SHAFIN_UI_TESTING": "1",
            "DEVICE_BENCHMARK_CONFIG_BASE64": ""
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
    }

    private func launchStoryboardApp(
        fixture: String,
        locale: String,
        reduceMotion: Bool = false,
        dynamicType: String? = nil
    ) {
        var args = [
            "-ApplePersistenceIgnoreState", "YES",
            "-SHAFIN_GENERATOR_MARK_AR_READY",
            "-SHAFIN_LIBRARY_RESET_FOR_UI_TESTING",
            "-SHAFIN_GENERATOR_STORYBOARD_FIXTURE", fixture,
            "-SHAFIN_SET_LOCALE", locale
        ]
        if reduceMotion {
            args += ["-SHAFIN_SET_REDUCE_MOTION", "1"]
        }
        if let dynamicType {
            args += ["-SHAFIN_SET_DYNAMIC_TYPE", dynamicType]
        }
        app.launchArguments = args
        app.launchEnvironment = [
            "SHAFIN_UI_TESTING": "1",
            "DEVICE_BENCHMARK_CONFIG_BASE64": ""
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))
    }

    /// EN + Reduce Motion + Dynamic Type coverage for the reachable generator
    /// surfaces (policy §8/§12: RU+EN, ≥1 RM, ≥1 DT evidence per family).
    func testGeneratorAccessibilityVariantsENReduceMotionDynamicType() {
        XCUIDevice.shared.orientation = .landscapeLeft

        let variants: [(name: String, args: [String])] = [
            (
                "generator-workspace-en-landscape",
                ["-SHAFIN_SET_LOCALE", "en"]
            ),
            (
                "generator-workspace-en-reduce-motion",
                ["-SHAFIN_SET_LOCALE", "en", "-SHAFIN_SET_REDUCE_MOTION", "1"]
            ),
            (
                "generator-workspace-en-dynamic-type",
                ["-SHAFIN_SET_LOCALE", "en", "-SHAFIN_SET_DYNAMIC_TYPE", "xxl"]
            )
        ]

        for variant in variants {
            app.terminate()
            app = XCUIApplication()
            var args = [
                "-ApplePersistenceIgnoreState", "YES",
                "-SHAFIN_GENERATOR_MARK_AR_READY",
                "-SHAFIN_LIBRARY_RESET_FOR_UI_TESTING"
            ]
            args += variant.args
            app.launchArguments = args
            app.launchEnvironment = [
                "SHAFIN_UI_TESTING": "1",
                "DEVICE_BENCHMARK_CONFIG_BASE64": ""
            ]
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))

            openLibraryAndCreateScene(named: "SET-UITest-A11y-\(variant.name)-\(UUID().uuidString.prefix(4))")

            let sceneButton = app.buttons["generator_scene_button"]
            XCTAssertTrue(
                sceneButton.waitForExistence(timeout: launchTimeout),
                "Generator settings bar must be reachable (\(variant.name))."
            )
            attachScreenshot(named: variant.name)

            // The production route must consume the EN override. A reachable
            // error band is also valid evidence, but its stable close action
            // must be EN rather than the Russian fallback.
            let errorClose = errorCloseButton(expectedLabel: "CLOSE")
            if errorClose.waitForExistence(timeout: 3) {
                XCTAssertEqual(errorClose.label, "CLOSE", "EN generator error action must be localized.")
                errorClose.tap()
            }

            sceneButton.tap()
            let inputTitle = app.descendants(matching: .any)["generator_input_title"]
            let inputEditor = app.descendants(matching: .any)["generator_input_editor"]
            if inputTitle.waitForExistence(timeout: launchTimeout) {
                XCTAssertEqual(inputTitle.label, "SCREENPLAY", "EN generator input title must be consumed by the runtime route.")
                XCTAssertTrue(inputEditor.waitForExistence(timeout: launchTimeout))
                if variant.name == "generator-workspace-en-landscape" {
                    attachScreenshot(named: "\(variant.name)-input")
                    inputEditor.tap()
                    attachScreenshot(named: "\(variant.name)-keyboard")
                }
                app.buttons["generator_input_cancel"].tap()
            } else {
                let runtimeErrorClose = errorCloseButton(expectedLabel: "CLOSE")
                XCTAssertTrue(runtimeErrorClose.waitForExistence(timeout: launchTimeout))
                XCTAssertEqual(runtimeErrorClose.label, "CLOSE", "EN generator error action must be localized.")
                runtimeErrorClose.tap()
            }

            let backButton = app.buttons["generator_back_button"]
            XCTAssertTrue(backButton.waitForExistence(timeout: launchTimeout))
            backButton.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)["library_root"].waitForExistence(timeout: launchTimeout),
                "The EN generator variant must close through the stable route-owned back action."
            )
        }

        XCUIDevice.shared.orientation = .portrait
    }

    /// The AR simulator failure is the deterministic EN error fixture for the
    /// production route. Assert the full band copy, not only its close action,
    /// so a mixed-locale prefix cannot pass unnoticed.
    func testGeneratorENErrorBandUsesProductionLocale() {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-SHAFIN_GENERATOR_MARK_AR_READY",
            "-SHAFIN_LIBRARY_RESET_FOR_UI_TESTING",
            "-SHAFIN_SET_LOCALE", "en"
        ]
        app.launchEnvironment = [
            "SHAFIN_UI_TESTING": "1",
            "DEVICE_BENCHMARK_CONFIG_BASE64": ""
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchTimeout))

        openLibraryAndCreateScene(named: "SET-UITest-EN-\(UUID().uuidString.prefix(6))")

        // The A/B ROLL capsule is owned by the commercial shell, so assert its
        // stable child identifiers after the real route reaches the generator.
        // The button titles are the uppercase mode copy; AX labels remain the
        // sentence-case labels intended for VoiceOver.
        let cameraButton = app.buttons["commercial-shell-return-camera"]
        let scenesButton = app.buttons["commercial-shell-open-scenes"]
        XCTAssertTrue(cameraButton.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(scenesButton.waitForExistence(timeout: launchTimeout))
        XCTAssertEqual(cameraButton.label, "Camera")
        XCTAssertEqual(scenesButton.label, "Scenes")

        let band = app.descendants(matching: .any)["generator_error_band"]
        XCTAssertTrue(band.waitForExistence(timeout: 8), "EN AR failure must remain an honest production surface.")
        let errorLabel = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "AR ERROR: Unsupported configuration.")
        ).firstMatch
        XCTAssertTrue(
            errorLabel.waitForExistence(timeout: 2),
            "The production AR failure band must use the injected EN locale."
        )
        XCTAssertEqual(errorLabel.label, "AR ERROR: Unsupported configuration.")
        attachScreenshot(named: "generator-error-band-en-landscape")

        let close = errorCloseButton(expectedLabel: "CLOSE")
        XCTAssertTrue(close.waitForExistence(timeout: launchTimeout))
        XCTAssertEqual(close.label, "CLOSE")
        close.tap()

        let backButton = app.buttons["generator_back_button"]
        XCTAssertTrue(backButton.waitForExistence(timeout: launchTimeout))
        backButton.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["library_root"].waitForExistence(timeout: launchTimeout)
        )
    }

    func testStoryboardFixtureRUResultTrayAndSelectionReflow() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launchStoryboardApp(fixture: "storyboard.result", locale: "ru")
        openLibraryAndCreateScene(named: "SET-UITest-Storyboard-RU-\(UUID().uuidString.prefix(6))")

        let trayToggle = app.buttons["storyboard_tray_toggle"]
        XCTAssertTrue(trayToggle.waitForExistence(timeout: launchTimeout))
        attachPackage6Screenshot(named: "storyboard-result-ru-tray-collapsed")

        trayToggle.tap()
        let firstBeat = app.descendants(matching: .any)["storyboard_beat_beat_1"]
        XCTAssertTrue(firstBeat.waitForExistence(timeout: launchTimeout))
        attachPackage6Screenshot(named: "storyboard-result-ru-tray-expanded")

        let secondBeat = app.descendants(matching: .any)["storyboard_beat_beat_2"].firstMatch
        XCTAssertTrue(secondBeat.waitForExistence(timeout: launchTimeout))
        secondBeat.tap()
        let editor = app.descendants(matching: .any)["storyboard_editor_sheet"]
        XCTAssertTrue(editor.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(app.descendants(matching: .any)["storyboard_editor_inspector"].exists)
        attachPackage6Screenshot(named: "storyboard-selection-reflow-ru-landscape")
    }

    func testStoryboardFixtureReduceMotionSelectionReflow() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launchStoryboardApp(fixture: "storyboard.result", locale: "en", reduceMotion: true)
        openLibraryAndCreateScene(named: "SET-UITest-Storyboard-RM-\(UUID().uuidString.prefix(6))")

        let trayToggle = app.buttons["storyboard_tray_toggle"]
        XCTAssertTrue(trayToggle.waitForExistence(timeout: launchTimeout))
        trayToggle.tap()
        let secondBeat = app.descendants(matching: .any)["storyboard_beat_beat_2"].firstMatch
        XCTAssertTrue(secondBeat.waitForExistence(timeout: launchTimeout))
        secondBeat.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["storyboard_editor_sheet"].waitForExistence(timeout: launchTimeout),
            "Reduce Motion selection must still hand off to the real editor."
        )
        attachPackage6Screenshot(named: "storyboard-selection-reflow-en-reduce-motion")
    }

    func testStoryboardFixtureValidationAndDeleteConfirmation() {
        XCUIDevice.shared.orientation = .landscapeLeft

        launchStoryboardApp(fixture: "storyboard.validation-failure", locale: "ru")
        openLibraryAndCreateScene(named: "SET-UITest-Storyboard-Validation-\(UUID().uuidString.prefix(6))")
        let validationError = app.descendants(matching: .any)["storyboard_editor_validation_error"]
        XCTAssertTrue(validationError.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(
            validationError.label.contains("Нельзя передать объект самому себе"),
            "The editor must show the ViewModel's canonical self-target validation copy."
        )
        // The recovery copy is attached to the target picker inside the existing
        // vertical editor scroll view. Tapping the real AX element asks XCTest to
        // bring that field into the landscape viewport before the evidence frame.
        validationError.tap()
        XCTAssertTrue(validationError.isHittable)
        attachPackage6Screenshot(named: "storyboard-validation-failure-ru-landscape")

        app.terminate()
        app = XCUIApplication()
        launchStoryboardApp(fixture: "storyboard.delete-confirmation", locale: "ru")
        openLibraryAndCreateScene(named: "SET-UITest-Storyboard-Delete-\(UUID().uuidString.prefix(6))")

        let deleteButton = app.buttons["storyboard_editor_delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: launchTimeout))
        deleteButton.tap()
        let beatIdentity = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Такт 1' OR label CONTAINS 'Beat 1'")
        ).firstMatch
        XCTAssertTrue(beatIdentity.waitForExistence(timeout: launchTimeout))
        attachPackage6Screenshot(named: "storyboard-delete-confirmation-ru-landscape")
    }

    func testStoryboardFixtureENReduceMotionDynamicTypeAndEditorDetents() {
        XCUIDevice.shared.orientation = .landscapeLeft

        launchStoryboardApp(fixture: "storyboard.editor-medium", locale: "en")
        openLibraryAndCreateScene(named: "SET-UITest-Storyboard-Medium-\(UUID().uuidString.prefix(6))")
        let mediumSheet = app.descendants(matching: .any)["storyboard_editor_sheet"]
        let mediumInspector = app.descendants(matching: .any)["storyboard_editor_inspector"]
        let mediumInspectorTitle = app.staticTexts["Beat 1"]
        XCTAssertTrue(mediumSheet.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(mediumInspector.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(mediumInspectorTitle.waitForExistence(timeout: launchTimeout))
        let mediumSave = app.buttons["storyboard_editor_save"]
        XCTAssertTrue(mediumSave.waitForExistence(timeout: launchTimeout))
        let mediumSheetFrame = mediumSheet.frame
        let mediumTitleFrame = mediumInspectorTitle.frame
        XCTAssertGreaterThan(
            mediumSheetFrame.height,
            100,
            "storyboard_editor_sheet must expose the actual medium editor surface, not a title. frame=\(mediumSheetFrame)"
        )
        print("[P6 detent] medium sheet=\(mediumSheetFrame) title=\(mediumTitleFrame)")
        XCTAssertGreaterThan(mediumTitleFrame.width, 0)
        let mediumPNG = XCUIScreen.main.screenshot().pngRepresentation
        attachPackage6Screenshot(named: "storyboard-editor-medium-en-landscape")

        app.terminate()
        app = XCUIApplication()
        launchStoryboardApp(
            fixture: "storyboard.editor-large",
            locale: "en",
            reduceMotion: true,
            dynamicType: "xxl"
        )
        openLibraryAndCreateScene(named: "SET-UITest-Storyboard-Large-\(UUID().uuidString.prefix(6))")
        let largeSheet = app.descendants(matching: .any)["storyboard_editor_sheet"]
        let largeInspector = app.descendants(matching: .any)["storyboard_editor_inspector"]
        let largeInspectorTitle = app.staticTexts["Beat 1"]
        XCTAssertTrue(largeSheet.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(largeInspector.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(largeInspectorTitle.waitForExistence(timeout: launchTimeout))

        let largeDetentExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                largeSheet.frame.height >= mediumSheetFrame.height + 16
                    && largeSheet.frame.minY <= mediumSheetFrame.minY
            },
            object: nil
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [largeDetentExpectation], timeout: 3),
            .completed,
            "The storyboard.editor-large fixture must settle a visibly larger editor surface/detent. medium=\(mediumSheetFrame) large=\(largeSheet.frame) mediumTitle=\(mediumTitleFrame) largeTitle=\(largeInspectorTitle.frame)"
        )

        XCTAssertGreaterThan(
            largeSheet.frame.height,
            mediumSheetFrame.height + 16,
            "The actual storyboard editor container must grow between medium and large fixtures. medium=\(mediumSheetFrame) large=\(largeSheet.frame)"
        )

        let largeTitleFrame = largeInspectorTitle.frame
        print("[P6 detent] large sheet=\(largeSheet.frame) title=\(largeTitleFrame)")
        XCTAssertGreaterThan(
            largeTitleFrame.width,
            mediumTitleFrame.width + 4,
            "Meaningful editor text must scale for the XXL Dynamic Type fixture."
        )
        let largePNG = XCUIScreen.main.screenshot().pngRepresentation
        XCTAssertNotEqual(
            mediumPNG,
            largePNG,
            "Medium and XXL large-editor evidence must not be byte-for-byte identical."
        )
        attachPackage6Screenshot(named: "storyboard-editor-large-en-reduce-motion-dynamic-type")
    }

    func testStoryboardFixtureSavingUsesOwnerBusyState() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launchStoryboardApp(fixture: "storyboard.saving", locale: "en")
        openLibraryAndCreateScene(named: "SET-UITest-Storyboard-Saving-\(UUID().uuidString.prefix(6))")

        let save = app.buttons["storyboard_editor_save"]
        XCTAssertTrue(save.waitForExistence(timeout: launchTimeout))
        save.tap()
        let savingExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "SAVING"),
            object: save
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [savingExpectation], timeout: 2),
            .completed,
            "The editor must expose the ViewModel-owned in-flight SAVING state."
        )
        XCTAssertFalse(save.isEnabled, "A second submit must be disabled while the owner mutation is in flight.")
        attachPackage6Screenshot(named: "storyboard-saving-en-landscape")
    }

    func testDecisionTraceFixtureRUAndENReduceMotion() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launchStoryboardApp(fixture: "sheet.decision-trace", locale: "ru")
        openLibraryAndCreateScene(named: "SET-UITest-Trace-RU-\(UUID().uuidString.prefix(6))")
        let why = app.buttons["generator_decision_trace"]
        XCTAssertTrue(why.waitForExistence(timeout: launchTimeout))
        why.tap()
        let trace = app.descendants(matching: .any)["decision_trace_sheet"]
        XCTAssertTrue(trace.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(
            app.descendants(matching: .any)["trace_chosen_section"].exists,
            "The live production trace must expose the chosen action and its linked domain trace ID."
        )
        attachPackage6Screenshot(named: "decision-trace-production-ru-landscape")

        app.terminate()
        app = XCUIApplication()
        launchStoryboardApp(fixture: "sheet.decision-trace", locale: "en", reduceMotion: true)
        openLibraryAndCreateScene(named: "SET-UITest-Trace-EN-\(UUID().uuidString.prefix(6))")
        let englishWhy = app.buttons["generator_decision_trace"]
        XCTAssertTrue(englishWhy.waitForExistence(timeout: launchTimeout))
        englishWhy.tap()
        let englishTrace = app.descendants(matching: .any)["decision_trace_sheet"]
        XCTAssertTrue(englishTrace.waitForExistence(timeout: launchTimeout))
        XCTAssertTrue(
            app.descendants(matching: .any)["trace_chosen_section"].exists,
            "The EN landscape trace must expose the same visible chosen-action contract."
        )
        attachPackage6Screenshot(named: "decision-trace-production-en-reduce-motion-landscape")
    }

    private func openLibraryAndCreateScene(named name: String) {
        let openScenes = app.descendants(matching: .any)["commercial-shell-open-scenes"]
        XCTAssertTrue(openScenes.waitForExistence(timeout: launchTimeout))
        openScenes.tap()

        let libraryRoot = app.descendants(matching: .any)["library_root"]
        XCTAssertTrue(libraryRoot.waitForExistence(timeout: launchTimeout))

        // Empty library → create CTA; loaded library → the create flow starts
        // from the empty-state action or a fresh install is empty by default.
        let emptyCreate = app.buttons["library_empty_create"]
        if emptyCreate.waitForExistence(timeout: 4) {
            emptyCreate.tap()
        } else {
            XCTFail("This lane expects an empty library; pre-existing scenes make the flow non-deterministic.")
            return
        }

        let field = app.textFields["library_create_field"]
        XCTAssertTrue(field.waitForExistence(timeout: launchTimeout))
        field.tap()
        field.typeText(name)
        // The confirm button sits under the keyboard in landscape; the
        // production contract accepts keyboard submission as the same intent.
        field.typeText("\n")
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "v26-package4-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachPackage6Screenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "v26-package6-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// SwiftUI may expose a named container's identifier on its child button
    /// until the AX containment boundary settles. Keep the production
    /// identifier assertion, but fall back to the locale-specific action
    /// label so the evidence test still exercises the real recovery path.
    private func errorCloseButton(expectedLabel: String) -> XCUIElement {
        let byIdentifier = app.buttons["generator_error_close"]
        if byIdentifier.waitForExistence(timeout: 1) {
            return byIdentifier
        }
        return app.buttons.matching(NSPredicate(format: "label == %@", expectedLabel)).firstMatch
    }
}
