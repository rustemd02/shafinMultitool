import Foundation

/// M9-006: the locked 1.0 Pro Controls contract. Each control declares its
/// availability tier with its real production owner; anything not listed
/// here does not ship. Histogram, zebra, and peaking are explicitly
/// POST_1_0 — no partial implementation may enter production under another
/// name.
enum ProCameraControl: String, CaseIterable, Sendable {
    case formatResolutionFPS
    case exposureAuto
    case exposureEV
    case exposureManualShutterAngleISO
    case focusAuto
    case focusTapLock
    case focusManual
    case whiteBalanceAuto
    case whiteBalancePreset
    case whiteBalanceLock
    case whiteBalanceTemperature
    case audioMeter
    case torch
}

enum ProControlAvailability: String, Equatable, Sendable {
    /// Ships in 1.0 and is bound to the production owner named alongside.
    case available
    /// Control surface exists in legacy code but is not wired to the
    /// production Camera Coach path; ships only when the wiring lands.
    case legacyOnly
    /// Explicitly deferred; the control surface must not exist.
    case post10
}

struct ProCameraControlContract: Equatable, Sendable {
    let control: ProCameraControl
    let availability: ProControlAvailability
    /// Real production owner, or the exact gap when not available.
    let owner: String
}

/// Implementation ownership. Actual device support is resolved separately
/// from the active device's capabilities, never from this inventory alone.
enum ProCameraControlContracts {
    static let production: [ProCameraControlContract] = ProCameraControl.allCases.map { control in
        .init(control: control, availability: .available, owner: control == .audioMeter
            ? "CameraCoachRecordingCoordinator.setMeterEnabled + CameraAudioMeterMeasurement"
            : "CameraManager.applyProControl + AVCaptureProControlDevice")
    }

    static func isSupported(_ control: ProCameraControl, by state: CameraProControlsSnapshot?) -> Bool {
        guard let state else { return false }
        let capabilities = state.capabilities
        switch control {
        case .formatResolutionFPS: return !capabilities.formats.isEmpty
        case .exposureAuto: return capabilities.autoExposure
        case .exposureEV: return capabilities.exposureBiasRange != nil && state.readback.exposureIsAuto
        case .exposureManualShutterAngleISO:
            return capabilities.isoRange != nil && capabilities.exposureDurationRange != nil
                && state.readback.fixedFPS != nil
        case .focusAuto: return capabilities.autoFocus
        case .focusTapLock: return capabilities.tapFocusLock
        case .focusManual: return capabilities.manualFocus
        case .whiteBalanceAuto: return capabilities.autoWhiteBalance
        case .whiteBalanceLock: return capabilities.whiteBalanceLock
        case .whiteBalancePreset, .whiteBalanceTemperature: return capabilities.customWhiteBalance
        case .torch: return capabilities.torch
        case .audioMeter: return true // Permission and an attached input are checked on explicit enable.
        }
    }

    /// Histogram/zebra/peaking have no control case at all — they cannot be
    /// referenced by production code. This list documents the exclusion.
    static let explicitlyExcluded: [String] = ["histogram", "zebra", "peaking"]
}
