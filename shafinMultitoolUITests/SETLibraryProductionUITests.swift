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
            XCTAssertFalse(
                app.descendants(matching: .any)["library_list"].exists,
                "An empty store must not expose a fabricated scene list (\(locale))."
            )
            assertMinimumHitTarget(
                app.buttons["library_empty_create"],
                "The empty create action must remain reachable (\(locale))."
            )
            attachScreenshot(app, named: "m5-library-empty-\(locale)-landscape")
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
            let firstRow = app.descendants(matching: .any)["library_scene_row_1"]
            XCTAssertTrue(
                firstRow.exists,
                "Scene rows must expose deterministic identifiers (\(entry.locale))."
            )
            XCTAssertTrue(
                app.descendants(matching: .any)["library_count"].exists,
                "A loaded library must expose its persisted row count (\(entry.locale))."
            )
            assertMinimumHitTarget(firstRow, "Scene rows must remain reachable (\(entry.locale)).")
            let firstRowValue = String(describing: firstRow.value ?? "")
            XCTAssertTrue(
                firstRowValue.contains("00000000-0000-4000-8000-000000000003"),
                "The row accessibility value must retain persisted UUID identity (\(entry.locale))."
            )
            XCTAssertTrue(
                firstRowValue.contains(entry.locale == "ru" ? "МЕДИА" : "MEDIA"),
                "The row accessibility value must announce artifact health without color-only meaning (\(entry.locale))."
            )
            if entry.fixture == "library.selected" {
                let open = app.buttons["library_scene_open"]
                let rename = app.buttons["library_scene_rename"]
                let delete = app.buttons["library_scene_delete"]
                let preview = app.descendants(matching: .any)["library_scene_preview"]
                XCTAssertTrue(open.exists, "The selected row must expose the open action (\(entry.locale)).")
                XCTAssertTrue(rename.exists, "The selected row must expose the rename action (\(entry.locale)).")
                XCTAssertTrue(delete.exists, "The selected row must expose the delete action (\(entry.locale)).")
                XCTAssertTrue(preview.exists, "The selected row must expose a truthful preview surface (\(entry.locale)).")
                XCTAssertEqual(
                    preview.label,
                    entry.locale == "ru" ? "МЕТАДАННЫЕ — ЗАПОЛНИТЕЛЬ" : "METADATA PLACEHOLDER",
                    "The fallback preview must expose its explicit metadata label (\(entry.locale))."
                )
                assertMinimumHitTarget(open, "The open action must remain reachable (\(entry.locale)).")
                assertMinimumHitTarget(rename, "The rename action must remain reachable (\(entry.locale)).")
                assertMinimumHitTarget(delete, "The delete action must remain reachable (\(entry.locale)).")
            }
            let attachmentName = entry.fixture == "library.contact-sheet"
                ? "m5-library-contact-sheet-\(entry.locale)-landscape"
                : "m5-library-selected-\(entry.locale)-landscape"
            attachScreenshot(app, named: attachmentName)
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
    }

    func testCreateDuplicateDeleteFailureMatrix() {
        let matrix: [(fixture: String, locale: String, identifier: String, reduceMotion: Bool, attachment: String)] = [
            ("library.create-name", "en", "library_create_field", false, "m5-library-create-name-en-landscape"),
            ("library.duplicate-name", "ru", "library_duplicate_notice", false, "m5-library-duplicate-name-ru-landscape"),
            ("library.delete-confirmation", "ru", "library_delete_confirm", false, "m5-library-delete-confirmation-ru-landscape"),
            ("library.persistence-failure", "ru", "library_failure_retry", false, "m5-library-persistence-failure-ru-landscape"),
            ("library.persistence-failure", "en", "library_failure_retry", false, "m5-library-persistence-failure-en-landscape"),
            ("library.persistence-failure", "en", "library_failure_retry", true, "m5-library-persistence-failure-en-landscape-reduce-motion")
        ]
        for entry in matrix {
            let app = launch(fixture: entry.fixture, locale: entry.locale, reduceMotion: entry.reduceMotion)
            assertRoot(entry.fixture, in: app)
            let element = app.descendants(matching: .any)[entry.identifier]
            XCTAssertTrue(
                element.waitForExistence(timeout: 4),
                "\(entry.fixture) must expose \(entry.identifier) (\(entry.locale))."
            )
            if entry.fixture == "library.persistence-failure" {
                let title = app.descendants(matching: .any)["library_failure_title"]
                let detail = app.descendants(matching: .any)["library_failure_detail"]
                let retry = app.buttons["library_failure_retry"]
                XCTAssertTrue(title.exists)
                XCTAssertTrue(detail.exists)
                XCTAssertTrue(retry.exists)
                XCTAssertLessThan(title.frame.minY, detail.frame.minY)
                XCTAssertLessThan(detail.frame.minY, retry.frame.minY)
                assertMinimumHitTarget(retry, "The retry action must remain reachable (\(entry.locale)).")
                XCTAssertTrue(
                    app.descendants(matching: .any)["library_list"].exists,
                    "A mutation failure may retain the loaded rows (\(entry.locale))."
                )
                XCTAssertFalse(app.descendants(matching: .any)["library_empty_state"].exists)
            }
            if entry.fixture == "library.create-name" {
                assertMinimumHitTarget(
                    app.buttons["library_create_confirm"],
                    "The create confirmation action must remain reachable (\(entry.locale))."
                )
                assertMinimumHitTarget(
                    app.buttons["library_create_cancel"],
                    "The create cancel action must remain reachable (\(entry.locale))."
                )
            }
            if entry.fixture == "library.delete-confirmation" {
                let detail = app.descendants(matching: .any)["library_delete_detail"]
                assertMinimumHitTarget(
                    app.buttons["library_delete_confirm"],
                    "The delete confirmation action must remain reachable (\(entry.locale))."
                )
                assertMinimumHitTarget(
                    app.buttons["library_delete_cancel"],
                    "The delete cancel action must remain reachable (\(entry.locale))."
                )
                XCTAssertTrue(detail.exists, "The destructive confirmation must expose the named scene (\(entry.locale)).")
                let detailText = detail.label + " " + String(describing: detail.value ?? "")
                let expectedScene = entry.locale == "ru"
                    ? "ИНТ. МАСТЕРСКАЯ — НОЧЬ"
                    : "INT. WORKSHOP — NIGHT"
                XCTAssertTrue(
                    detailText.contains(expectedScene),
                    "The destructive confirmation must name the scene (\(entry.locale))."
                )
            }
            attachScreenshot(app, named: entry.attachment)
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
    }

    func testSelectedActionHitRegionsDoNotOverlapAndKeepOrder() {
        let app = launch(fixture: "library.selected", locale: "en")
        assertRoot("library.selected", in: app)

        let sceneRow = app.descendants(matching: .any)["library_scene_row_2"]
        let open = app.buttons["library_scene_open"]
        let rename = app.buttons["library_scene_rename"]
        let delete = app.buttons["library_scene_delete"]
        XCTAssertTrue(sceneRow.waitForExistence(timeout: 4))
        XCTAssertTrue(open.waitForExistence(timeout: 4))
        XCTAssertTrue(rename.waitForExistence(timeout: 4))
        XCTAssertTrue(delete.waitForExistence(timeout: 4))

        let actions = [open, rename, delete]
        for index in actions.indices {
            for otherIndex in actions.indices where otherIndex > index {
                XCTAssertFalse(
                    actions[index].frame.intersects(actions[otherIndex].frame),
                    "Sibling Library action hit regions must not overlap."
                )
            }
        }
        XCTAssertGreaterThan(open.frame.minY, sceneRow.frame.minY)
        XCTAssertTrue(
            open.label.localizedCaseInsensitiveContains("open") || open.label.localizedCaseInsensitiveContains("открыть")
        )
        XCTAssertTrue(
            rename.label.localizedCaseInsensitiveContains("rename") || rename.label.localizedCaseInsensitiveContains("переименовать")
        )
        XCTAssertTrue(
            delete.label.localizedCaseInsensitiveContains("delete") || delete.label.localizedCaseInsensitiveContains("удалить")
        )
        attachScreenshot(app, named: "m5-library-selected-en-landscape-actions")
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testDeleteCancelLeavesNamedSceneAndRowsVisible() {
        let app = launch(fixture: "library.delete-confirmation", locale: "en")
        assertRoot("library.delete-confirmation", in: app)

        let detail = app.descendants(matching: .any)["library_delete_detail"]
        let cancel = app.buttons["library_delete_cancel"]
        let selectedRow = app.descendants(matching: .any)["library_scene_row_1"]
        XCTAssertTrue(detail.waitForExistence(timeout: 4))
        XCTAssertTrue(cancel.waitForExistence(timeout: 4))
        XCTAssertTrue(selectedRow.exists)
        let namedScene = detail.label + " " + String(describing: detail.value ?? "")
        XCTAssertTrue(namedScene.contains("INT. WORKSHOP — NIGHT"))

        cancel.tap()

        XCTAssertFalse(app.buttons["library_delete_confirm"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["library_list"].exists)
        XCTAssertTrue(selectedRow.exists, "Cancel must leave the persisted scene row visible.")
        attachScreenshot(app, named: "m5-library-delete-cancel-en-landscape")
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testDuplicateCreateStateIsTypedAndReachable() {
        // The DEBUG projection enters the typed duplicate state directly; the
        // persistence provider remains untouched and no off-screen tap is needed.
        let app = launch(fixture: "library.duplicate-name", locale: "ru")
        assertRoot("library.duplicate-name", in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["library_duplicate_notice"].waitForExistence(timeout: 4),
            "A duplicate name must surface the duplicate explanation."
        )
        attachScreenshot(app, named: "m5-library-create-duplicate-live-ru-landscape")

        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testReduceMotionAndDynamicTypeKeepLibraryReadable() {
        let reduceMotionApp = launch(fixture: "library.selected", locale: "ru", reduceMotion: true)
        assertRoot("library.selected", in: reduceMotionApp)
        XCTAssertTrue(reduceMotionApp.descendants(matching: .any)["library_list"].waitForExistence(timeout: 4))
        attachScreenshot(reduceMotionApp, named: "m5-library-selected-ru-landscape-reduce-motion")
        reduceMotionApp.terminate()

        let dynamicTypeApp = launch(fixture: "library.contact-sheet", locale: "en", dynamicType: true)
        assertRoot("library.contact-sheet", in: dynamicTypeApp)
        XCTAssertTrue(dynamicTypeApp.descendants(matching: .any)["library_list"].waitForExistence(timeout: 4))
        XCTAssertTrue(dynamicTypeApp.descendants(matching: .any)["library_scene_row_1"].exists)
        attachScreenshot(dynamicTypeApp, named: "m5-library-contact-sheet-en-landscape-xxl")
        dynamicTypeApp.terminate()

        let reduceTransparencyApp = launch(
            fixture: "library.contact-sheet",
            locale: "ru",
            reduceTransparency: true
        )
        assertRoot("library.contact-sheet", in: reduceTransparencyApp)
        XCTAssertTrue(
            reduceTransparencyApp.descendants(matching: .any)["library_list"].waitForExistence(timeout: 4)
        )
        attachScreenshot(
            reduceTransparencyApp,
            named: "m5-library-contact-sheet-ru-landscape-reduce-transparency"
        )
        reduceTransparencyApp.terminate()

        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(
        fixture: String,
        locale: String,
        reduceMotion: Bool = false,
        dynamicType: Bool = false,
        reduceTransparency: Bool = false
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
        if reduceTransparency {
            app.launchArguments += ["-SHAFIN_SET_REDUCE_TRANSPARENCY", "1"]
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
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertMinimumHitTarget(
        _ element: XCUIElement,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // SwiftUI's exactly-44pt frame can be reported one floating-point ulp
        // below 44 by XCTest; keep the assertion strict to the measured frame
        // while allowing that representation error only.
        XCTAssertGreaterThanOrEqual(element.frame.width + 0.0001, 44, "\(message) width", file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height + 0.0001, 44, message, file: file, line: line)
    }
}
