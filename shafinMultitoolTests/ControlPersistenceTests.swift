import XCTest
@testable import shafinMultitool

/// M9-014: preferences restore only when supported; unsupported stored
/// values fall back explicitly; settings never start capture.
final class ControlPersistenceTests: XCTestCase {
    typealias Interactor = CameraScreenInteractor

    func testZeroValuesMapToDocumentedDefaults() {
        let restored = Interactor.restoredCaptureSettings(
            storedWidth: 0, storedHeight: 0, storedFPS: 0,
            isSupported: { _, _, _ in true })
        XCTAssertEqual(restored.width, 3840)
        XCTAssertEqual(restored.height, 2160)
        XCTAssertEqual(restored.fps, 25)
    }

    func testSupportedStoredValuesApply() {
        let restored = Interactor.restoredCaptureSettings(
            storedWidth: 1920, storedHeight: 1080, storedFPS: 30,
            isSupported: { _, _, _ in true })
        XCTAssertEqual(restored.width, 1920)
        XCTAssertEqual(restored.height, 1080)
        XCTAssertEqual(restored.fps, 30)
    }

    func testUnsupportedStoredValuesFallBackExplicitly() {
        let restored = Interactor.restoredCaptureSettings(
            storedWidth: 7680, storedHeight: 4320, storedFPS: 240,
            isSupported: { _, _, _ in false })
        XCTAssertEqual(restored.width, Interactor.defaultCaptureWidth)
        XCTAssertEqual(restored.height, Interactor.defaultCaptureHeight)
        XCTAssertEqual(restored.fps, Interactor.defaultCaptureFPS)
    }
}
