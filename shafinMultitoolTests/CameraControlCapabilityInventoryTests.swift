import AVFoundation
import XCTest
@testable import shafinMultitool

/// C06 slice A (runbook 2026-09-13): factual capability state for the
/// focus/exposure/hold/obstruction control families.
///
/// Production implementation ownership and actual hardware capabilities are
/// separate. These tests check conditional admission; native application
/// and the Coach/recorder combination still require a physical-device gate.
///
/// Hardware ranges, device-availability and confirmed on-device application
/// remain a Q04 device gate. Nothing here claims that gate is passed; the
/// code fails closed instead.
final class CameraControlCapabilityInventoryTests: XCTestCase {

    func testProductionActuatorsStillRequireReportedHardwareCapabilities() {
        let controls: [ProCameraControl] = [
            .exposureAuto, .exposureEV, .exposureManualShutterAngleISO,
            .focusAuto, .focusTapLock, .focusManual,
            .whiteBalanceAuto, .whiteBalancePreset, .whiteBalanceLock,
            .whiteBalanceTemperature,
        ]
        let unavailable = CameraProControlsSnapshot(deviceID: "fixed", captureGeneration: 1,
                                                   capabilities: .init(), readback: .init())
        for control in controls {
            let entry = ProCameraControlContracts.production.first { $0.control == control }
            XCTAssertEqual(entry?.availability, .available)
            XCTAssertTrue(entry?.owner.contains("CameraManager.applyProControl") == true)
            XCTAssertFalse(ProCameraControlContracts.isSupported(control, by: unavailable),
                           "Implementation ownership does not establish support for \(control)")
        }
    }

    func testEVRequiresAutomaticExposureAndManualAngleRequiresFixedFPS() {
        var capabilities = CameraProControlCapabilities()
        capabilities.exposureBiasRange = -3...3
        capabilities.isoRange = 50...1600
        capabilities.exposureDurationRange = 0.0001...1
        var readback = CameraProControlReadback()
        func state() -> CameraProControlsSnapshot {
            .init(deviceID: "back", captureGeneration: 2, capabilities: capabilities, readback: readback)
        }
        XCTAssertFalse(ProCameraControlContracts.isSupported(.exposureEV, by: state()))
        XCTAssertFalse(ProCameraControlContracts.isSupported(.exposureManualShutterAngleISO, by: state()))
        readback.exposureIsAuto = true
        XCTAssertTrue(ProCameraControlContracts.isSupported(.exposureEV, by: state()))
        readback.fixedFPS = 60
        XCTAssertTrue(ProCameraControlContracts.isSupported(.exposureManualShutterAngleISO, by: state()))
        readback.exposureIsAuto = false
        XCTAssertFalse(ProCameraControlContracts.isSupported(.exposureEV, by: state()))
    }

    func testTapFocusCapabilityDoesNotEnableManualLensMovement() {
        var capabilities = CameraProControlCapabilities()
        capabilities.tapFocusLock = true
        let state = CameraProControlsSnapshot(deviceID: "back", captureGeneration: 3,
                                             capabilities: capabilities, readback: .init())
        XCTAssertTrue(ProCameraControlContracts.isSupported(.focusTapLock, by: state))
        XCTAssertFalse(ProCameraControlContracts.isSupported(.focusManual, by: state))
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
