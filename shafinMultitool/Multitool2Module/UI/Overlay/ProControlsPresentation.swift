//
//  ProControlsPresentation.swift
//  shafinMultitool
//
//  Actual device capabilities and acknowledged readback drive the controls.
//

import Foundation

/// One Pro Controls row: capability tier first, value only when real.
struct ProControlRow: Equatable, Identifiable {
    let id: String
    let nameKey: SETCopyKey
    let availability: ProControlAvailability
    let isSupported: Bool
    /// Read-back value from the production owner, or nil when the
    /// control is unsupported/unwired (rendered as an honest dash).
    let valueText: String?
    let owner: String

    func accessibilityValueText(locale: Locale) -> String {
        guard isSupported else { return SETCopyKey.proControlUnsupported.localizedString(locale: locale) }
        switch availability {
        case .available:
            return valueText ?? ""
        case .legacyOnly, .post10:
            return SETCopyKey.proControlTierLegacy.localizedString(locale: locale)
        }
    }
}

enum ProControlsPresentation {
    /// Localized tier caption per row.
    static func tierText(_ availability: ProControlAvailability, locale: Locale) -> String {
        switch availability {
        case .available:
            return SETCopyKey.proControlTierAvailable.localizedString(locale: locale)
        case .legacyOnly:
            return SETCopyKey.proControlTierLegacy.localizedString(locale: locale)
        case .post10:
            return SETCopyKey.proControlTierPost10.localizedString(locale: locale)
        }
    }

    /// Unknown readback remains unknown; a control's implementation status
    /// never manufactures support or a measured value on this device.
    static func rows(
        snapshot: CameraProControlsSnapshot?,
        meterLevel: Float?,
        locale: Locale
    ) -> [ProControlRow] {
        ProCameraControlContracts.production.map { contract in
            return ProControlRow(
                id: contract.control.rawValue,
                nameKey: nameKey(for: contract.control),
                availability: contract.availability,
                isSupported: ProCameraControlContracts.isSupported(contract.control, by: snapshot),
                valueText: valueText(for: contract.control, readback: snapshot?.readback, meterLevel: meterLevel, locale: locale),
                owner: contract.owner
            )
        }
    }

    static func valueText(for control: ProCameraControl, readback: CameraProControlReadback?,
                          meterLevel: Float? = nil, locale: Locale) -> String? {
        guard let readback else { return nil }
        func onOff(_ value: Bool) -> String {
            (value ? SETCopyKey.proControlValueOn : .proControlValueOff).localizedString(locale: locale)
        }
        switch control {
        case .formatResolutionFPS:
            guard readback.width > 0, readback.height > 0 else { return nil }
            let rate = readback.fixedFPS.map { String(format: "%.0f FPS", $0) }
                ?? SETCopyKey.proControlVariableFPS.localizedString(locale: locale)
            return "\(readback.width)×\(readback.height) · \(rate)"
        case .exposureAuto: return onOff(readback.exposureIsAuto)
        case .exposureEV:
            return readback.exposureBias.flatMap { $0.isFinite ? String(format: "%+.1f EV", $0) : nil }
        case .exposureManualShutterAngleISO:
            guard let angle = readback.shutterAngle, let iso = readback.iso, iso.isFinite else { return nil }
            return String(format: "%.0f° · ISO %.0f", angle, iso)
        case .focusAuto: return onOff(readback.focusIsAuto)
        case .focusTapLock: return onOff(readback.focusIsLocked)
        case .focusManual:
            return readback.lensPosition.flatMap { $0.isFinite ? String(format: "%.2f", $0) : nil }
        case .whiteBalanceAuto: return onOff(readback.whiteBalanceIsAuto)
        case .whiteBalanceLock: return onOff(readback.whiteBalanceIsLocked)
        case .whiteBalancePreset, .whiteBalanceTemperature:
            return readback.temperature.flatMap { $0.isFinite ? String(format: "%.0f K", $0) : nil }
        case .audioMeter:
            guard let meterLevel, meterLevel.isFinite, (0...1).contains(meterLevel) else { return nil }
            return String(format: "%.0f dBFS", 20 * log10(max(meterLevel, 0.0001)))
        case .torch: return readback.torchActive.map(onOff)
        }
    }

    static func errorKey(_ error: CameraProControlError) -> SETCopyKey {
        switch error {
        case .unavailable: return .proControlUnavailable
        case .unsupported: return .proControlUnsupported
        case .invalidValue: return .proControlInvalidValue
        case .configurationFailed: return .proControlApplyFailed
        case .stale: return .proControlStale
        case .busy: return .proControlApplying
        case .focusTimeout: return .proControlFocusTimeout
        case .applicationTimeout: return .proControlApplyTimeout
        case .microphoneDenied: return .proControlMicrophoneDenied
        }
    }

    static func nameKey(for control: ProCameraControl) -> SETCopyKey {
        switch control {
        case .formatResolutionFPS: return .proControlFormat
        case .exposureAuto: return .proControlExposureAuto
        case .exposureEV: return .proControlExposureEV
        case .exposureManualShutterAngleISO: return .proControlExposureManual
        case .focusAuto: return .proControlFocusAuto
        case .focusTapLock: return .proControlFocusTapLock
        case .focusManual: return .proControlFocusManual
        case .whiteBalanceAuto: return .proControlWBAuto
        case .whiteBalancePreset: return .proControlWBPreset
        case .whiteBalanceLock: return .proControlWBLock
        case .whiteBalanceTemperature: return .proControlWBTemperature
        case .audioMeter: return .proControlAudioMeter
        case .torch: return .proControlTorch
        }
    }
}
