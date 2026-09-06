import AVFoundation
import XCTest
@testable import shafinMultitool

/// M9-007: capture configuration ownership is singular — the manager
/// serializes session and device configuration on its session queue with
/// generation fencing; UI state reads back from the device; failed values
/// surface typed instead of clamping silently.
final class CaptureConfigurationTests: XCTestCase {

    func testFailedLensSwitchSurfacesTypedReason() async {
        // An unavailable lens reports its failure reason instead of clamping
        // to a neighboring lens.
        let manager = CameraManager(scheduler: RealtimeScheduler(),
                                    thermalGovernor: ThermalGovernor(thermalStateProvider: { .nominal }, batteryLevelProvider: { 1.0 }),
                                    motionGate: MotionGate())
        let result = await manager.switchLensAndWait(to: .telephoto)
        switch result {
        case .success, .noOp:
            break // simulator may expose the lens; both are honest outcomes
        case let .failure(requestedLens, _, reason):
            XCTAssertEqual(requestedLens, .telephoto)
            XCTAssertNotEqual(reason, .rollbackFailed, "a clean unavailability must not report rollback failure")
        }
        await manager.releaseAndWait()
    }

    func testUIStateReadsBackFromDeviceAfterStart() async throws {
        let session = AVCaptureSession()
        let manager = CameraManager(scheduler: RealtimeScheduler(),
                                    thermalGovernor: ThermalGovernor(thermalStateProvider: { .nominal }, batteryLevelProvider: { 1.0 }),
                                    motionGate: MotionGate(),
                                    sessionRunner: TorchTestSessionRunner(),
                                    configuration: .ready,
                                    session: session)
        try await manager.startAndWait()
        // Read-back: the manager reports the session's actual input lens,
        // never a guessed default.
        XCTAssertNotNil(manager.activeLens)
        XCTAssertFalse(manager.availableLenses.isEmpty)
        await manager.releaseAndWait()
    }

    private final class TorchTestSessionRunner: CameraSessionRunner {
        private let lock = NSLock()
        private var running = false
        var isRunning: Bool {
            lock.lock(); defer { lock.unlock() }
            return running
        }
        func startRunning() {
            lock.lock(); defer { lock.unlock() }
            running = true
        }
        func stopRunning() {
            lock.lock(); defer { lock.unlock() }
            running = false
        }
    }
}
