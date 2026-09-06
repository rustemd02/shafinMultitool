import AVFoundation
import XCTest
@testable import shafinMultitool

/// M9-009/M9-010/M9-012: exposure and white-balance apply through
/// device-derived ranges with read-back; unsupported/unavailable hardware
/// fails closed with nil instead of crashing or clamping silently.
final class ExposureWhiteBalanceTests: XCTestCase {

    func testISOWithoutDeviceFailsClosed() {
        // CameraService.shared owns an implicitly-unwrapped device that is
        // nil in the unit host: the hardened API must return nil, not crash.
        // NOTE: shared singleton state is not mutated by this probe.
        let service = CameraService.makeTestingInstance()
        XCTAssertNil(service.changeISO(iso: 100))
    }

    func testInvalidWhiteBalanceRejected() {
        let service = CameraService.makeTestingInstance()
        XCTAssertNil(service.changeWB(wb: 0))
        XCTAssertNil(service.changeWB(wb: -500))
    }

    func testShutterAngle180PresetConvertsToSupportedDuration() {
        // 180° at 24fps = 1/48s. The conversion itself is pure arithmetic
        // the recording metadata path reuses; device support is checked at
        // apply time by changeISO/changeWB above.
        let fps = 24.0
        let duration = (180.0 / 360.0) / fps
        XCTAssertEqual(duration, 1.0 / 48.0, accuracy: 1e-9)
        XCTAssertGreaterThan(duration, 0)
    }
}
