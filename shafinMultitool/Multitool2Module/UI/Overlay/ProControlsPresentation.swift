//
//  ProControlsPresentation.swift
//  shafinMultitool
//
//  M9-016: contract-driven Pro Controls presentation. Rows are built
//  ONLY from the frozen M9-006 contract; a live value appears only
//  for controls whose production owner exposes a read-back (M9-007/
//  M9-013/M9-005). legacyOnly controls show their tier honestly and
//  carry no value — nothing is inferred from a requested label.
//

import Foundation

/// One Pro Controls row: capability tier first, value only when real.
struct ProControlRow: Equatable, Identifiable {
    let id: String
    let nameKey: SETCopyKey
    let availability: ProControlAvailability
    /// Read-back value from the production owner, or nil when the
    /// control is unsupported/unwired (rendered as an honest dash).
    let valueText: String?
    let owner: String

    var accessibilityValueText: String {
        switch availability {
        case .available:
            return valueText ?? ""
        case .legacyOnly, .post10:
            return SETCopyKey.proControlTierLegacy.localizedString(locale: .current)
        }
    }
}

enum ProControlsPresentation {
    /// Localized tier caption per row.
    static func tierText(_ availability: ProControlAvailability) -> String {
        switch availability {
        case .available:
            return SETCopyKey.proControlTierAvailable.localizedString(locale: .current)
        case .legacyOnly:
            return SETCopyKey.proControlTierLegacy.localizedString(locale: .current)
        case .post10:
            return SETCopyKey.proControlTierPost10.localizedString(locale: .current)
        }
    }

    /// Builds the 13 contract rows. `torchActive`, `meterLevel` and
    /// `formatText` come from the runtime owners; nil renders a dash.
    static func rows(
        torchActive: Bool?,
        meterLevel: Float?,
        formatText: String?
    ) -> [ProControlRow] {
        ProCameraControlContracts.production.map { contract in
            let value: String?
            switch contract.control {
            case .torch:
                value = contract.availability == .available
                    ? torchActive.map { $0
                        ? SETCopyKey.proControlValueOn.localizedString(locale: .current)
                        : SETCopyKey.proControlValueOff.localizedString(locale: .current) }
                    : nil
            case .audioMeter:
                value = contract.availability == .available
                    ? meterLevel.map { String(format: "%.0f dB", 20 * log10(max($0, 0.0001))) }
                    : nil
            case .formatResolutionFPS:
                value = contract.availability == .available ? formatText : nil
            default:
                value = nil
            }
            return ProControlRow(
                id: contract.control.rawValue,
                nameKey: nameKey(for: contract.control),
                availability: contract.availability,
                valueText: value,
                owner: contract.owner
            )
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
