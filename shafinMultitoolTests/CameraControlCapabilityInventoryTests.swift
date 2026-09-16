import AVFoundation
import XCTest
@testable import shafinMultitool

/// C06 slice A (runbook 2026-09-13): factual capability state for the
/// focus/exposure/hold/obstruction control families.
///
/// These tests pin only what the current code can guarantee without a
/// physical device: the Coach path owns no focus/exposure/WB actuator, the
/// legacy tap-to-focus performs one-shot automatic focus/exposure and is NOT
/// a focus lock, control entry points never mutate the recorder lifecycle,
/// and unsupported effect families stay explicitly unsupported.
///
/// Hardware ranges, device-availability and confirmed on-device application
/// remain a Q04 device gate. Nothing here claims that gate is passed; the
/// code fails closed instead.
final class CameraControlCapabilityInventoryTests: XCTestCase {

    // MARK: Focus / exposure / white balance are not production controls

    func testFocusExposureAndWhiteBalanceControlsRemainLegacyOnly() {
        let legacyControls: [ProCameraControl] = [
            .exposureAuto, .exposureEV, .exposureManualShutterAngleISO,
            .focusAuto, .focusTapLock, .focusManual,
            .whiteBalanceAuto, .whiteBalancePreset, .whiteBalanceLock,
            .whiteBalanceTemperature,
        ]
        for control in legacyControls {
            let entry = ProCameraControlContracts.production.first { $0.control == control }
            XCTAssertEqual(entry?.availability, .legacyOnly,
                           "\(control) has no Coach-path owner and must stay legacyOnly")
        }
    }

    func testFocusLockContractNamesNoLockOwner() {
        // C06: `autoFocus` + `autoExpose` is not a focus lock. The lock row
        // must not attribute a lock to the non-locking tap path.
        let lockRow = ProCameraControlContracts.production.first { $0.control == .focusTapLock }
        XCTAssertEqual(lockRow?.availability, .legacyOnly)
        let owner = (lockRow?.owner ?? "").lowercased()
        XCTAssertTrue(owner.contains("no focus-lock owner"),
                      "focusTapLock must declare that no lock owner exists")
        XCTAssertFalse(owner.contains("cameraService.focusOnTap"),
                       "the non-locking tap path must not be named as a lock owner")
    }

    // MARK: Tap focus is auto, never a lock

    func testTapFocusIsAutoFocusAndAutoExposeNotALock() {
        XCTAssertEqual(CameraService.tapFocusMode, .autoFocus)
        XCTAssertEqual(CameraService.tapExposureMode, .autoExpose)
        XCTAssertNotEqual(CameraService.tapFocusMode, .locked,
                          "tap focus must never be presented as a completed focus lock")
        XCTAssertNotEqual(CameraService.tapExposureMode, .locked)
    }

    func testTapFocusWithoutBoundDeviceFailsClosed() {
        // No capture device is bound in the unit host, so the hardened entry
        // point must report an unapplied request instead of silently
        // succeeding (which would read as an installed focus/lock).
        let service = CameraService.makeTestingInstance()
        XCTAssertFalse(service.focusOnTap(focusPoint: CGPoint(x: 0.5, y: 0.5)))
        XCTAssertFalse(service.isCaptureDeviceAvailable)
    }

    // MARK: Controls do not disturb the recorder lifecycle

    func testControlEntryPointsDoNotMutateRecorderLifecycle() {
        let service = CameraService.makeTestingInstance()
        let stateBefore = service.recorderState
        XCTAssertNil(service.changeISO(iso: 3200))
        XCTAssertNil(service.changeWB(wb: 4200))
        XCTAssertFalse(service.focusOnTap(focusPoint: CGPoint(x: 0.5, y: 0.5)))
        XCTAssertEqual(service.recorderState, stateBefore,
                       "a rejected control must not open/close/fail a recording")
        XCTAssertNil(service.recordingSourceToken)
        XCTAssertFalse(service.isRecorderPrepared)
    }

    // MARK: Unsupported effect families stay explicitly unsupported

    func testObstructionAndNoiseEffectsHaveNoQualifiedVerifier() {
        // Point 4: an unsupported effect/control keeps its case
        // conditional/unavailable. avoid_occlusion / clean_lens /
        // reduce_iso_noise have no movement family and therefore fail closed
        // as unsupported_action in ActionVerifier; no "try something" action.
        for action in [TechnicalQualityActionType.avoidOcclusion,
                       .cleanLens,
                       .reduceIsoNoise] {
            XCTAssertNil(UserMovementObserver.actionFamily(for: action),
                         "\(action.rawValue) must stay unsupported, not gain a fabricated verifier")
        }
    }
}
