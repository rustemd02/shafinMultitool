import CoreGraphics
import Foundation

/// Production-facing mapping from the pipeline's stable live hint to the
/// small set of Camera Coach states that this surface can truthfully render.
struct CameraOverlayUXPresentation: Equatable, Sendable {
    enum State: String, Equatable, Sendable {
        case liveSeeking = "S04"
        case stableTip = "S06"
        case explanation = "S07"
        case keepAsIs = "S10c"
    }

    static var seekingLine: String {
        SETCopyKey.cameraSeeking.localizedString(locale: .current)
    }
    static var safeFallbackLine: String {
        SETCopyKey.cameraFallback.localizedString(locale: .current)
    }
    static let surfaceMaxWidth: CGFloat = 420
    static let surfaceHorizontalInset: CGFloat = 16
    static let minimumControlDimension: CGFloat = 44

    let state: State
    let baseState: State
    let observation: String
    let actionInstruction: String?
    let explanation: String?
    let supportingObservation: String?
    let showsWhy: Bool
    let isFallback: Bool
    let liveHintID: String?
    let targetRegion: NormalizedRect?
    let overlayHint: OverlayHint?

    var mode: State { state }
    var phase: State { state }
    var visibleText: String { observation }
    var actionText: String? { actionInstruction }
    var whyText: String? { explanation }
    var isSafeFallback: Bool { isFallback }

    /// Copy currently exposed to the user or VoiceOver, kept useful for
    /// focused tests without exposing pipeline metadata in the UI contract.
    var visibleCopy: [String] {
        [observation, supportingObservation, actionInstruction, explanation]
            .compactMap { $0 }
    }

    var accessibilityLabel: String {
        visibleCopy.joined(separator: ". ")
    }

    static var safeFallbackPresentation: CameraOverlayUXPresentation {
        fallback(locale: .current)
    }

    static func surfaceWidth(for canvasSize: CGSize) -> CGFloat {
        max(0, min(surfaceMaxWidth, canvasSize.width - surfaceHorizontalInset * 2))
    }

    static func lowerThirdBottomInset(hasZoomControl: Bool) -> CGFloat {
        hasZoomControl ? 104 : 28
    }

    /// Maps only live seeking, a stable actionable tip, an inline explanation,
    /// or keep-as-is. Invalid payloads never leak their raw copy.
    static func make(liveHint: LiveHintPresentation?,
                     isExpanded: Bool = false,
                     isPaused _: Bool = false,
                     locale: Locale = .current) -> CameraOverlayUXPresentation {
        guard let liveHint else { return seeking(locale: locale) }
        guard let mapped = map(liveHint: liveHint, isExpanded: isExpanded, locale: locale) else {
            return fallback(locale: locale)
        }

        let mappedOverlayHint: OverlayHint?
        if mapped.baseState == .stableTip, liveHint.actionType != nil {
            mappedOverlayHint = safeOverlayHint(from: liveHint.overlayHint)
        } else {
            mappedOverlayHint = nil
        }

        return CameraOverlayUXPresentation(
            state: mapped.state,
            baseState: mapped.baseState,
            observation: mapped.observation,
            actionInstruction: mapped.actionInstruction,
            explanation: mapped.explanation,
            supportingObservation: mapped.supportingObservation,
            showsWhy: mapped.showsWhy,
            isFallback: liveHint.isFallback,
            liveHintID: liveHint.id,
            targetRegion: mappedOverlayHint?.targetRegion,
            overlayHint: mappedOverlayHint
        )
    }

    private struct MappedCopy {
        let state: State
        let baseState: State
        let observation: String
        let actionInstruction: String?
        let explanation: String?
        let supportingObservation: String?
        let showsWhy: Bool
    }

    private static func seeking(locale: Locale) -> CameraOverlayUXPresentation {
        CameraOverlayUXPresentation(
            state: .liveSeeking,
            baseState: .liveSeeking,
            observation: SETCopyKey.cameraSeeking.localizedString(locale: locale),
            actionInstruction: nil,
            explanation: nil,
            supportingObservation: nil,
            showsWhy: false,
            isFallback: false,
            liveHintID: nil,
            targetRegion: nil,
            overlayHint: nil
        )
    }

    private static func fallback(locale: Locale) -> CameraOverlayUXPresentation {
        CameraOverlayUXPresentation(
            state: .liveSeeking,
            baseState: .liveSeeking,
            observation: SETCopyKey.cameraFallback.localizedString(locale: locale),
            actionInstruction: nil,
            explanation: nil,
            supportingObservation: nil,
            showsWhy: false,
            isFallback: true,
            liveHintID: nil,
            targetRegion: nil,
            overlayHint: nil
        )
    }

    private static func map(liveHint: LiveHintPresentation,
                            isExpanded: Bool,
                            locale: Locale) -> MappedCopy? {
        guard isValidIdentity(liveHint),
              liveHint.confidence.isFinite,
              (0...1).contains(liveHint.confidence),
              safeText(liveHint.text) != nil else {
            return nil
        }

        if let expandedVerdict = liveHint.expandedVerdict {
            guard safeText(expandedVerdict.shortVerdict) != nil,
                  expandedVerdict.supportingText == nil || safeText(expandedVerdict.supportingText) != nil,
                  expandedVerdict.actionText == nil || safeText(expandedVerdict.actionText) != nil else {
                return nil
            }
        }

        if liveHint.actionType == .leaveFrameAsIs {
            return MappedCopy(
                state: .keepAsIs,
                baseState: .keepAsIs,
                observation: SETCopyKey.cameraKeep.localizedString(locale: locale),
                actionInstruction: SETCopyKey.actionMain.localizedString(locale: locale),
                explanation: nil,
                supportingObservation: nil,
                showsWhy: false
            )
        }

        guard let expandedVerdict = liveHint.expandedVerdict,
              let observation = safeText(expandedVerdict.shortVerdict) else {
            return nil
        }

        let actionKey: SETCopyKey
        if let semanticActionType = liveHint.semanticActionType {
            actionKey = SETCameraCopy.actionKey(for: semanticActionType)
        } else if let technicalIssueType = liveHint.technicalIssueType {
            actionKey = SETCameraCopy.technicalActionKey(for: technicalIssueType)
        } else if let actionType = liveHint.actionType {
            actionKey = SETCameraCopy.actionKey(for: actionType)
        } else {
            return nil
        }

        let hasExplanation = safeText(expandedVerdict.supportingText) != nil
            || safeText(expandedVerdict.actionText) != nil
        let explanation = hasExplanation
            ? SETCopyKey.cameraExplanation.localizedString(locale: locale)
            : nil
        return MappedCopy(
            state: isExpanded && explanation != nil ? .explanation : .stableTip,
            baseState: .stableTip,
            observation: SETCopyKey.cameraCorrectiveObservation.localizedString(locale: locale),
            actionInstruction: actionKey.localizedString(locale: locale),
            explanation: explanation,
            supportingObservation: nil,
            showsWhy: hasExplanation
        )
    }

    private static func isValidIdentity(_ liveHint: LiveHintPresentation) -> Bool {
        isUsableIdentifier(liveHint.id) && isUsableIdentifier(liveHint.frameId)
    }

    private static func isUsableIdentifier(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    private static func safeText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 240 else { return nil }
        guard !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }

        let lowered = text.lowercased()
        let forbiddenFragments = [
            "%", "trace", "semantic", "reserve", "confidence", "pipeline", "good", "review",
            "трейс", "семантик", "резерв", "уверенност", "пайплайн", "ревью", "доверител"
        ]
        guard !forbiddenFragments.contains(where: { lowered.contains($0) }) else { return nil }
        return text
    }

    private static func safeOverlayHint(from hint: OverlayHint?) -> OverlayHint? {
        guard let hint, isUsableIdentifier(hint.id) else { return nil }
        let targetRegion = safeRegion(from: hint.targetRegion)

        switch hint.kind {
        case .arrow:
            // Runtime corrective geometry is valid only when the pipeline has
            // supplied both an arrow direction and a non-degenerate target.
            // Regionless/horizon advice remains text-only.
            guard hint.direction != nil, targetRegion != nil else { return nil }
        case .regionHighlight:
            guard targetRegion != nil else { return nil }
        case .horizonLine:
            // The current contract has no angle for a horizon guide, so do not
            // render an ungrounded line.
            return nil
        }

        return OverlayHint(
            id: hint.id,
            kind: hint.kind,
            targetRegion: targetRegion,
            direction: hint.direction
        )
    }

    private static func safeRegion(from region: NormalizedRect?) -> NormalizedRect? {
        guard let region, !region.isDegenerate else { return nil }
        return region
    }

}
