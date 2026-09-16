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

/// The single source of truth for the 1.0 control surface. Owners were
/// verified by grep against the locked commit; no owner is invented.
enum ProCameraControlContracts {
    static let production: [ProCameraControlContract] = [
        .init(control: .formatResolutionFPS, availability: .available,
              owner: "CameraManager+SettingsValues+ZoomControlView"),
        // Exposure/ISO/WB/focus live in the legacy CameraService path
        // (changeISO/changeWB/changeFPS/focusOnTap/changeResolution) and are
        // NOT yet wired to the production Camera Coach owner. They ship only
        // with that wiring; until then the contract records the gap honestly
        // instead of claiming coverage.
        .init(control: .exposureAuto, availability: .legacyOnly,
              owner: "CameraService.changeISO (legacy; unwired to Coach path)"),
        .init(control: .exposureEV, availability: .legacyOnly,
              owner: "CameraService.changeISO (legacy; unwired to Coach path)"),
        .init(control: .exposureManualShutterAngleISO, availability: .legacyOnly,
              owner: "CameraService.changeISO (legacy; unwired to Coach path)"),
        .init(control: .focusAuto, availability: .legacyOnly,
              owner: "CameraService.focusOnTap (legacy one-shot autoFocus; unwired to Coach path)"),
        // C06: `focusOnTap` sets `.autoFocus` + `.autoExpose`, never
        // `.locked`. There is no focus-lock implementation, so this row must
        // not name a lock owner that does not exist.
        .init(control: .focusTapLock, availability: .legacyOnly,
              owner: "NONE: no focus-lock owner; focusOnTap installs .autoFocus, not .locked (legacy; unwired)"),
        .init(control: .focusManual, availability: .legacyOnly,
              owner: "NONE: no manual-focus owner (legacy; unwired to Coach path)"),
        .init(control: .whiteBalanceAuto, availability: .legacyOnly,
              owner: "CameraService.changeWB (legacy; unwired to Coach path)"),
        .init(control: .whiteBalancePreset, availability: .legacyOnly,
              owner: "CameraService.changeWB (legacy; unwired to Coach path)"),
        .init(control: .whiteBalanceLock, availability: .legacyOnly,
              owner: "CameraService.changeWB (legacy; unwired to Coach path)"),
        .init(control: .whiteBalanceTemperature, availability: .legacyOnly,
              owner: "CameraService.changeWB (legacy; unwired to Coach path)"),
        .init(control: .audioMeter, availability: .available,
              owner: "CameraManager.audioLevel (RMS from audio buffers)"),
        .init(control: .torch, availability: .available,
              owner: "CameraManager.setTorchActive/isTorchActive"),
    ]

    /// Histogram/zebra/peaking have no control case at all — they cannot be
    /// referenced by production code. This list documents the exclusion.
    static let explicitlyExcluded: [String] = ["histogram", "zebra", "peaking"]
}
