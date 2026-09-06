import AVFoundation
import XCTest
@testable import shafinMultitool

/// M9-013: the meter derives from actual audio buffers when authorized and
/// active; without permission or a running owner it reports unavailable;
/// Release contains no fixture animation.
final class CameraAudioMeterTests: XCTestCase {

    func testMeterUnavailableWithoutPermissionOrRunningOwner() {
        let manager = CameraManager(scheduler: RealtimeScheduler(),
                                    thermalGovernor: ThermalGovernor(thermalStateProvider: { .nominal }, batteryLevelProvider: { 1.0 }),
                                    motionGate: MotionGate())
        // The simulator host has no microphone grant for the test host: the
        // meter must report unavailable, never a fabricated level.
        XCTAssertNil(manager.audioLevel)
    }

    func testMeterClearsOnRelease() async throws {
        let manager = CameraManager(scheduler: RealtimeScheduler(),
                                    thermalGovernor: ThermalGovernor(thermalStateProvider: { .nominal }, batteryLevelProvider: { 1.0 }),
                                    motionGate: MotionGate(),
                                    sessionRunner: MeterTestRunner(),
                                    configuration: .ready,
                                    session: AVCaptureSession())
        try await manager.startAndWait()
        await manager.releaseAndWait()
        XCTAssertNil(manager.audioLevel, "release must clear any meter state")
    }

    private final class MeterTestRunner: CameraSessionRunner {
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
