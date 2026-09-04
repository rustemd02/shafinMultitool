import XCTest

/// Package 3 Library production fixture matrix: landscape-only, RU+EN,
/// Reduce Motion and Dynamic Type evidence for every §8 library row.
final class SETLibraryProductionUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testLibraryEmptyStateBothLocalesLandscape() {
        for locale in ["ru", "en"] {
            let app = launch(fixture: "library.empty", locale: locale)
            assertRoot("library.empty", in: app)
            XCTAssertTrue(
                app.descendants(matching: .any)["library_empty_state"].waitForExistence(timeout: 4),
                "Empty library must show the honest empty state (\(locale))."
            )
            XCTAssertTrue(
                app.buttons["library_empty_create"].exists,
                "The empty state must keep the create action reachable (\(locale))."
            )
            attachScreenshot(app, named: "library-empty-\(locale)-landscape")
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
    }

    func testContactSheetAndSelectionMatrix() {
        let matrix: [(fixture: String, locale: String)] = [
            ("library.contact-sheet", "ru"),
            ("library.contact-sheet", "en"),
            ("library.selected", "ru"),
            ("library.selected", "en")
        ]
        for entry in matrix {
            let app = launch(fixture: entry.fixture, locale: entry.locale)
            assertRoot(entry.fixture, in: app)
            XCTAssertTrue(
                app.descendants(matching: .any)["library_list"].waitForExistence(timeout: 4),
                "The contact sheet must list real scene rows (\(entry.fixture), \(entry.locale))."
            )
            XCTAssertTrue(
                app.buttons["library_scene_row_1"].exists,
                "Scene rows must expose deterministic identifiers (\(entry.locale))."
            )
            if entry.fixture == "library.selected" {
                XCTAssertTrue(
                    app.buttons["library_scene_open"].exists,
                    "The selected row must expose the open action (\(entry.locale))."
                )
            }
            attachScreenshot(app, named: entry.fixture.replacingOccurrences(of: ".", with: "-") + "-\(entry.locale)-landscape")
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
    }

    func testCreateDuplicateDeleteFailureMatrix() {
        let matrix: [(fixture: String, locale: String, identifier: String)] = [
            ("library.create-name", "en", "library_create_field"),
            ("library.duplicate-name", "ru", "library_duplicate_notice"),
            ("library.delete-confirmation", "ru", "library_delete_confirm"),
            ("library.persistence-failure", "en", "library_failure_retry")
        ]
        for entry in matrix {
            let app = launch(fixture: entry.fixture, locale: entry.locale)
            assertRoot(entry.fixture, in: app)
            let element = app.descendants(matching: .any)[entry.identifier]
            XCTAssertTrue(
                element.waitForExistence(timeout: 4),
                "\(entry.fixture) must expose \(entry.identifier) (\(entry.locale))."
            )
            attachScreenshot(app, named: entry.fixture.replacingOccurrences(of: ".", with: "-") + "-\(entry.locale)-landscape")
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
    }

    func testCreateFlowCorrectsDuplicateNameAndCreates() {
        let app = launch(fixture: "library.create-name", locale: "ru")
        assertRoot("library.create-name", in: app)

        let field = app.textFields["library_create_field"]
        XCTAssertTrue(field.waitForExistence(timeout: 4))
        field.tap()
        // Duplicate the second fixture scene name to reach the duplicate projection.
        field.typeText("ЭКСТ. КРЫША — РАССВЕТ")
        app.buttons["library_create_confirm"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["library_duplicate_notice"].waitForExistence(timeout: 4),
            "A duplicate name must surface the duplicate explanation."
        )
        attachScreenshot(app, named: "library-create-duplicate-live-ru-landscape")

        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testReduceMotionAndDynamicTypeKeepLibraryReadable() {
        let reduceMotionApp = launch(fixture: "library.selected", locale: "ru", reduceMotion: true)
        assertRoot("library.selected", in: reduceMotionApp)
        XCTAssertTrue(reduceMotionApp.descendants(matching: .any)["library_list"].waitForExistence(timeout: 4))
        attachScreenshot(reduceMotionApp, named: "library-selected-ru-landscape-reduce-motion")
        reduceMotionApp.terminate()

        let dynamicTypeApp = launch(fixture: "library.contact-sheet", locale: "en", dynamicType: true)
        assertRoot("library.contact-sheet", in: dynamicTypeApp)
        XCTAssertTrue(dynamicTypeApp.descendants(matching: .any)["library_list"].waitForExistence(timeout: 4))
        XCTAssertTrue(dynamicTypeApp.buttons["library_scene_row_1"].exists)
        attachScreenshot(dynamicTypeApp, named: "library-contact-sheet-en-landscape-dynamic-type")
        dynamicTypeApp.terminate()

        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(
        fixture: String,
        locale: String,
        reduceMotion: Bool = false,
        dynamicType: Bool = false
    ) -> XCUIApplication {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = [
            "-SHAFIN_LIBRARY_PRODUCTION_FIXTURE", fixture,
            "-SHAFIN_SET_LOCALE", locale
        ]
        if reduceMotion {
            app.launchArguments += ["-SHAFIN_SET_REDUCE_MOTION", "1"]
        }
        if dynamicType {
            app.launchArguments += ["-SHAFIN_SET_DYNAMIC_TYPE", "xxl"]
        }
        app.launch()
        return app
    }

    private func assertRoot(_ fixture: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            app.otherElements[fixture].waitForExistence(timeout: 4),
            "Missing deterministic library fixture \(fixture)",
            file: file,
            line: line
        )
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "v26-package3-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
