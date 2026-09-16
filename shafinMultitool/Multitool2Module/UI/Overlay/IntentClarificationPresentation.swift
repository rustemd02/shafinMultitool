//
//  IntentClarificationPresentation.swift
//  shafinMultitool
//
//  CC-I05 presentation: one yes/no question about a detected style cue.
//  Pure projection of the policy's prompt into localized copy plus stable
//  accessibility identifiers; it holds no state and does not decide anything.
//

import Foundation

struct IntentClarificationPresentation: Equatable, Sendable {
    let cue: CameraStyleCue
    let question: String
    let confirmTitle: String
    let denyTitle: String
    let confirmAccessibilityIdentifier: String
    let denyAccessibilityIdentifier: String

    static func make(cue: CameraStyleCue, locale: Locale) -> IntentClarificationPresentation {
        IntentClarificationPresentation(
            cue: cue,
            question: questionKey(for: cue).localizedString(locale: locale),
            confirmTitle: SETCopyKey.cameraIntentConfirm.localizedString(locale: locale),
            denyTitle: SETCopyKey.cameraIntentDeny.localizedString(locale: locale),
            confirmAccessibilityIdentifier: SETCopyKey.accessibilityIntentConfirm.rawValue,
            denyAccessibilityIdentifier: SETCopyKey.accessibilityIntentDeny.rawValue
        )
    }

    static func questionKey(for cue: CameraStyleCue) -> SETCopyKey {
        switch cue {
        case .lowKey: return .cameraIntentLowKey
        case .silhouette: return .cameraIntentSilhouette
        case .symmetry: return .cameraIntentSymmetry
        case .tilt: return .cameraIntentTilt
        case .motionBlur: return .cameraIntentMotionBlur
        case .negativeSpace: return .cameraIntentNegativeSpace
        }
    }
}
