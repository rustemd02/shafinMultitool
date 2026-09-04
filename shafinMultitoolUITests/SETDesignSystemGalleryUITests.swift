import XCTest

final class SETDesignSystemGalleryUITests: XCTestCase {
    private struct ApprovalFixture {
        let id: String
        let locale: String
        let orientation: UIDeviceOrientation
        let reduceMotion: Bool
        let expectedIdentifier: String
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testOwnerApprovalScreenshotMatrix() {
        let fixtures = [
            ApprovalFixture(
                id: "camera.corrective",
                locale: "ru",
                orientation: .portrait,
                reduceMotion: false,
                expectedIdentifier: "camera.corrective"
            ),
            ApprovalFixture(
                id: "camera.pause-success",
                locale: "en",
                orientation: .portrait,
                reduceMotion: false,
                expectedIdentifier: "camera.pause-success"
            ),
            ApprovalFixture(
                id: "camera.corrective",
                locale: "ru",
                orientation: .portrait,
                reduceMotion: true,
                expectedIdentifier: "camera.corrective"
            ),
            ApprovalFixture(
                id: "generator.progress",
                locale: "ru",
                orientation: .landscapeLeft,
                reduceMotion: false,
                expectedIdentifier: "generator.progress"
            ),
            ApprovalFixture(
                id: "library.contact-sheet",
                locale: "ru",
                orientation: .landscapeLeft,
                reduceMotion: false,
                expectedIdentifier: "library.contact-sheet"
            ),
            ApprovalFixture(
                id: "storyboard.result",
                locale: "en",
                orientation: .landscapeLeft,
                reduceMotion: false,
                expectedIdentifier: "storyboard.result"
            ),
            ApprovalFixture(
                id: "generator.progress",
                locale: "ru",
                orientation: .landscapeLeft,
                reduceMotion: true,
                expectedIdentifier: "generator.progress"
            )
        ]

        for fixture in fixtures {
            XCUIDevice.shared.orientation = fixture.orientation

            let app = XCUIApplication()
            app.launchArguments = [
                "-SHAFIN_DESIGN_SYSTEM_GALLERY",
                "-SHAFIN_SET_FIXTURE", fixture.id,
                "-SHAFIN_SET_LOCALE", fixture.locale
            ]
            if fixture.reduceMotion {
                app.launchArguments += ["-SHAFIN_SET_REDUCE_MOTION", "1"]
            }

            app.launch()
            XCTAssertTrue(
                app.otherElements[fixture.expectedIdentifier].waitForExistence(timeout: 4),
                "Missing deterministic gallery root for \(fixture.id)"
            )

            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = [
                "v25",
                fixture.locale,
                fixture.orientation.isLandscape ? "landscape" : "portrait",
                fixture.id.replacingOccurrences(of: ".", with: "-"),
                fixture.reduceMotion ? "reduce-motion" : "default"
            ].joined(separator: "-")
            attachment.lifetime = .keepAlways
            add(attachment)

            app.terminate()
        }

        XCUIDevice.shared.orientation = .portrait
    }
}
