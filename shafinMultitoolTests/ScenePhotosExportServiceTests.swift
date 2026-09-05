import Photos
import XCTest
@testable import shafinMultitool

/// M7-028: transactional Photos export outcome matrix against a deterministic
/// library fake — contextual authorization, typed denials, in-flight guard,
/// and success only after the Photos change commits.
final class ScenePhotosExportServiceTests: XCTestCase {

    private final class FakePhotosLibrary: PhotosLibraryExporting, @unchecked Sendable {
        var authorization: PHAuthorizationStatus = .authorized
        var performError: Error?
        private let lock = NSLock()
        private(set) var requestCount = 0
        private(set) var performCount = 0
        /// Set while `performVideoExport` is running so the in-flight guard
        /// can be exercised deterministically.
        var onPerformStarted: (() -> Void)?
        /// Guards `onPerformStarted` so reentrant probes cannot double-fulfill.
        private var performStartedSignaled = false
        /// When set, `performVideoExport` blocks until released, so tests can
        /// hold the first export open while probing the in-flight guard.
        var performGate: DispatchSemaphore?

        func requestAddOnlyAuthorization() async -> PHAuthorizationStatus {
            lock.lock()
            requestCount += 1
            lock.unlock()
            return authorization
        }

        func performVideoExport(at url: URL) async throws {
            lock.lock()
            performCount += 1
            let shouldSignal = !performStartedSignaled
            performStartedSignaled = true
            lock.unlock()
            if shouldSignal {
                onPerformStarted?()
            }
            if let performGate {
                _ = performGate.wait(timeout: .now() + 5)
            }
            if let performError {
                throw performError
            }
        }
    }

    func testAuthorizedExportSucceedsOnlyAfterPhotosChangeCommits() async {
        let library = FakePhotosLibrary()
        let service = ScenePhotosExportService(library: library)

        let outcome = await service.exportMovie(at: URL(fileURLWithPath: "/tmp/nonexistent-export.mov"))

        XCTAssertEqual(outcome, .exported)
        XCTAssertEqual(library.requestCount, 1)
        XCTAssertEqual(library.performCount, 1)
    }

    func testDeniedAuthorizationNeverTouchesTheLibrary() async {
        let library = FakePhotosLibrary()
        library.authorization = .denied
        let service = ScenePhotosExportService(library: library)

        let outcome = await service.exportMovie(at: URL(fileURLWithPath: "/tmp/any.mov"))

        XCTAssertEqual(outcome, .denied)
        XCTAssertEqual(library.performCount, 0)
    }

    func testRestrictedAuthorizationMapsToRestricted() async {
        let library = FakePhotosLibrary()
        library.authorization = .restricted
        let service = ScenePhotosExportService(library: library)

        let outcome = await service.exportMovie(at: URL(fileURLWithPath: "/tmp/any.mov"))

        XCTAssertEqual(outcome, .restricted)
    }

    func testPhotosFailureMapsToFailedOutcome() async {
        let library = FakePhotosLibrary()
        library.performError = CocoaError(.fileWriteUnknown)
        let service = ScenePhotosExportService(library: library)

        let outcome = await service.exportMovie(at: URL(fileURLWithPath: "/tmp/any.mov"))

        XCTAssertEqual(outcome, .failed)
    }

    func testConcurrentExportReportsAlreadyInFlightWithoutDuplicatePerform() async {
        let library = FakePhotosLibrary()
        let performStarted = expectation(description: "perform started")
        library.onPerformStarted = { performStarted.fulfill() }
        let service = ScenePhotosExportService(library: library)

        let gate = DispatchSemaphore(value: 0)
        library.performGate = gate
        let first = Task { await service.exportMovie(at: URL(fileURLWithPath: "/tmp/first.mov")) }
        await fulfillment(of: [performStarted], timeout: 2.0)

        let secondOutcome = await service.exportMovie(at: URL(fileURLWithPath: "/tmp/second.mov"))
        XCTAssertEqual(secondOutcome, .alreadyInFlight)

        gate.signal()
        let firstOutcome = await first.value
        XCTAssertEqual(firstOutcome, .exported)
        XCTAssertEqual(library.performCount, 1, "no duplicate asset creation")
    }
}
