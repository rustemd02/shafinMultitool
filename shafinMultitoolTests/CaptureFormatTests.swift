import AVFoundation
import XCTest
@testable import shafinMultitool

/// M9-008: the format list is device-derived; unsupported choices are
/// rejected before any writer input exists; selection applies atomically.
final class CaptureFormatTests: XCTestCase {

    func testZeroDimensionsAndFPSAreRejected() {
        XCTAssertFalse(CameraService.isFormatSupported(width: 0, height: 1080, fps: 30))
        XCTAssertFalse(CameraService.isFormatSupported(width: 1920, height: 0, fps: 30))
        XCTAssertFalse(CameraService.isFormatSupported(width: 1920, height: 1080, fps: 0))
        XCTAssertFalse(CameraService.isFormatSupported(width: -1, height: 1080, fps: 30))
    }

    func testAbsurdFormatIsRejected() {
        // No physical device supports 8K at 240fps; the gate must reject
        // without consulting a preference store.
        XCTAssertFalse(CameraService.isFormatSupported(width: 7680, height: 4320, fps: 240))
    }

    func testCommonFormatAcceptedWhenDevicePresent() {
        // On hardware with a back camera, 1080p30 is universally supported.
        // On the simulator (no camera device) the gate fails closed — both
        // outcomes are honest; the test pins fail-closed, not acceptance.
        let supported = CameraService.isFormatSupported(width: 1920, height: 1080, fps: 30)
        if AVCaptureDevice.default(for: .video) == nil {
            XCTAssertFalse(supported, "without a device the gate must fail closed")
        } else {
            XCTAssertTrue(supported)
        }
    }
}
