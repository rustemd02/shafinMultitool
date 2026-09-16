import AVFoundation
import XCTest
@testable import shafinMultitool

/// M9-005: torch truthfulness. Unsupported configurations report nil (the UI
/// hides/disables truthfully); state resets on owner release because the
/// device handle detaches with the input.
final class CameraTorchTests: XCTestCase {

    private final class TorchTestRunner: CameraSessionRunner {
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

    private func makeManager() -> CameraManager {
        CameraManager(scheduler: RealtimeScheduler(),
                      thermalGovernor: ThermalGovernor(thermalStateProvider: { .nominal }, batteryLevelProvider: { 1.0 }),
                      motionGate: MotionGate(),
                      sessionRunner: TorchTestRunner(),
                      configuration: .ready,
                      session: AVCaptureSession())
    }

    func testTorchUnsupportedWithoutConfiguredInput() async {
        let manager = makeManager()
        let snapshot = await manager.proControlsSnapshotAndWait()
        XCTAssertNil(snapshot, "no input means unsupported, not off")
        let result = await manager.applyProControl(.torch(true), expectedDeviceID: "missing", expectedCaptureGeneration: 0)
        XCTAssertEqual(result, .failure(.unavailable), "setting torch without a device must fail closed")
    }

    func testTorchStateResetsOnRelease() async throws {
        let manager = makeManager()
        try await manager.startAndWait()
        // The simulator has no torch hardware; the contract under test is
        // that whatever state existed cannot survive release.
        let result = await manager.applyProControl(.torch(false), expectedDeviceID: "missing", expectedCaptureGeneration: 0)
        XCTAssertEqual(result, .failure(.stale))
        await manager.releaseAndWait()
        let snapshot = await manager.proControlsSnapshotAndWait()
        XCTAssertNil(snapshot, "release detaches the device: no stale torch state may survive")
    }
}
