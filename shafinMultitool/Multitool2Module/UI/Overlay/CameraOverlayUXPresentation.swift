import CoreGraphics
import Foundation

/// Presentation-only health of the live analysis stream. The value is kept
/// separate from thermal reasons and model metadata so no raw diagnostic can
/// reach the Camera Coach surface.
enum CameraOverlayAnalysisStatus: String, Equatable, Sendable {
    case healthy
    case limited
    case failed

}

/// Inputs consumed by the one existing presentation projection. These are
/// all owner outputs: lifecycle/pause/lens state, planner decision, episode
/// boundary, verifier result and the effective governor/scheduler snapshot.
/// No reducer or second state machine is introduced here.
struct CameraOverlayUXContext: Equatable, Sendable {
    let lifecycleState: CameraLifecycleState
    let decision: CameraCoachDecisionV2?
    let episodeState: CoachingEpisodeState
    let verificationResult: ActionVerificationResult?
    let pauseState: CameraPausePresentationState
    let lensState: CameraLensSwitchPresentationState
    let performance: CameraRuntimePerformanceSnapshot
    let analysisStatus: CameraOverlayAnalysisStatus
    let hasSpatialEvidence: Bool

    init(
        lifecycleState: CameraLifecycleState = .running,
        decision: CameraCoachDecisionV2? = nil,
        episodeState: CoachingEpisodeState = .idle,
        verificationResult: ActionVerificationResult? = nil,
        pauseState: CameraPausePresentationState = .idle,
        lensState: CameraLensSwitchPresentationState = .idle,
        performance: CameraRuntimePerformanceSnapshot = .nominal,
        analysisStatus: CameraOverlayAnalysisStatus = .healthy,
        hasSpatialEvidence: Bool = true
    ) {
        self.lifecycleState = lifecycleState
        self.decision = decision
        self.episodeState = episodeState
        self.verificationResult = verificationResult
        self.pauseState = pauseState
        self.lensState = lensState
        self.performance = performance
        self.analysisStatus = analysisStatus
        self.hasSpatialEvidence = hasSpatialEvidence
    }
}

/// Production-facing mapping from the pipeline's stable live hint to the
/// small set of Camera Coach states that this surface can truthfully render.
struct CameraOverlayUXPresentation: Equatable, Sendable {
    typealias Context = CameraOverlayUXContext

    enum State: String, CaseIterable, Equatable, Sendable {
        case starting = "S01"
        case interrupted = "S02"
        case failed = "S03"
        case liveSeeking = "S04"
        case stableTip = "S06"
        case explanation = "S07"
        case keepAsIs = "S10c"
        case lensSwitching = "L01"
        case pauseLoading = "P01"
        case pauseSuccess = "P02"
        case pauseEmpty = "P03"
        case pauseFailure = "P04"
        case resuming = "P05"
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
    let eventID: String?
    let effectivePerformanceMode: CameraEffectivePerformanceMode
    let analysisStatus: CameraOverlayAnalysisStatus

    var mode: State { state }
    var phase: State { state }
    var visibleText: String { observation }
    var actionText: String? { actionInstruction }
    var whyText: String? { explanation }
    var isSafeFallback: Bool { isFallback }
    var markerEventID: String? { eventID }
    var showsECO: Bool { effectivePerformanceMode == .eco }
    var isLimited: Bool { analysisStatus == .limited || showsECO }

    /// Stable action slots for accessibility and transition audits. The
    /// presentation owner supplies a primary copy where one exists; recovery
    /// remains a localized owner action and exit is always the existing close.
    var primaryAction: String? { actionInstruction }

    var recoveryAction: String? {
        switch state {
        case .failed:
            return SETCopyKey.retry.localizedString(locale: .current)
        case .interrupted:
            return SETCopyKey.cameraResume.localizedString(locale: .current)
        case .pauseLoading, .pauseSuccess, .pauseEmpty, .pauseFailure, .resuming:
            return SETCopyKey.cameraResume.localizedString(locale: .current)
        case .starting, .liveSeeking, .stableTip, .explanation, .keepAsIs, .lensSwitching:
            return nil
        }
    }

    var exitAction: String {
        SETCopyKey.cameraClose.localizedString(locale: .current)
    }

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
        make(
            liveHint: liveHint,
            context: CameraOverlayUXContext(),
            isExpanded: isExpanded,
            locale: locale
        )
    }

    /// Full owner projection used by the runtime surface. Lifecycle and pause
    /// boundaries are evaluated before live copy; a limited/failed analysis
    /// stream can therefore never leave stale corrective text or a marker on
    /// screen.
    static func make(liveHint: LiveHintPresentation?,
                     context: CameraOverlayUXContext,
                     isExpanded: Bool = false,
                     locale: Locale = .current) -> CameraOverlayUXPresentation {
        if let boundary = boundaryPresentation(for: context, locale: locale) {
            return boundary
        }

        guard let liveHint else {
            return seeking(
                locale: locale,
                effectivePerformanceMode: context.performance.mode,
                analysisStatus: context.analysisStatus
            )
        }
        guard let mapped = map(liveHint: liveHint, isExpanded: isExpanded, locale: locale) else {
            return fallback(
                locale: locale,
                effectivePerformanceMode: context.performance.mode,
                analysisStatus: context.analysisStatus
            )
        }

        let shouldShowSpatialAdvice = mapped.baseState == .stableTip
            && context.analysisStatus == .healthy
            && !context.performance.isLimited
            && context.hasSpatialEvidence
        if mapped.baseState == .stableTip && !shouldShowSpatialAdvice {
            return seeking(
                locale: locale,
                effectivePerformanceMode: context.performance.mode,
                analysisStatus: context.analysisStatus
            )
        }

        let mappedOverlayHint: OverlayHint?
        if shouldShowSpatialAdvice, liveHint.actionType != nil {
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
            overlayHint: mappedOverlayHint,
            eventID: liveHint.id,
            effectivePerformanceMode: context.performance.mode,
            analysisStatus: context.analysisStatus
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

    private static func boundaryPresentation(
        for context: CameraOverlayUXContext,
        locale: Locale
    ) -> CameraOverlayUXPresentation? {
        switch context.lifecycleState {
        case .starting, .idle:
            return status(
                state: .starting,
                copy: .cameraPreparing,
                locale: locale,
                context: context
            )
        case .stopping:
            return status(
                state: .interrupted,
                copy: .cameraInterrupted,
                locale: locale,
                context: context
            )
        case .failed(let error):
            return status(
                state: error == .sessionInterrupted ? .interrupted : .failed,
                copy: error == .sessionInterrupted ? .cameraInterrupted : .cameraFailed,
                locale: locale,
                context: context
            )
        case .running:
            break
        }

        switch context.pauseState {
        case .idle:
            break
        case .loading:
            return status(state: .pauseLoading, copy: .cameraPause, locale: locale, context: context)
        case .success:
            return status(state: .pauseSuccess, copy: .cameraPause, locale: locale, context: context)
        case .empty:
            return status(state: .pauseEmpty, copy: .cameraPause, locale: locale, context: context)
        case .failure:
            return status(state: .pauseFailure, copy: .cameraFailed, locale: locale, context: context)
        case .resuming:
            return status(state: .resuming, copy: .cameraResuming, locale: locale, context: context)
        }

        switch context.lensState {
        case .idle:
            break
        case .switching, .failed:
            return status(state: .lensSwitching, copy: .cameraLensSwitching, locale: locale, context: context)
        }

        if context.analysisStatus == .failed {
            return status(
                state: .failed,
                copy: .cameraFailed,
                locale: locale,
                context: context
            )
        }

        if context.episodeState.phase == .cancelled || context.episodeState.phase == .expired {
            return fallback(
                locale: locale,
                effectivePerformanceMode: context.performance.mode,
                analysisStatus: context.analysisStatus
            )
        }

        if let verificationResult = context.verificationResult {
            switch verificationResult.decision {
            case .incomparable:
                return fallback(
                    locale: locale,
                    effectivePerformanceMode: context.performance.mode,
                    analysisStatus: context.analysisStatus
                )
            case .comparable(let outcome):
                if outcome == .fixed {
                    return status(state: .keepAsIs, copy: .cameraKeep, locale: locale, context: context)
                }
            }
        }

        switch context.decision {
        case .wait?, .abstain?, .selectSubject?:
            return seeking(
                locale: locale,
                effectivePerformanceMode: context.performance.mode,
                analysisStatus: context.analysisStatus
            )
        case .keep?:
            return status(state: .keepAsIs, copy: .cameraKeep, locale: locale, context: context)
        case .correct?, nil:
            return nil
        }
    }

    private static func status(
        state: State,
        copy: SETCopyKey,
        locale: Locale,
        context: CameraOverlayUXContext
    ) -> CameraOverlayUXPresentation {
        CameraOverlayUXPresentation(
            state: state,
            baseState: state,
            observation: copy.localizedString(locale: locale),
            actionInstruction: nil,
            explanation: nil,
            supportingObservation: nil,
            showsWhy: false,
            isFallback: false,
            liveHintID: nil,
            targetRegion: nil,
            overlayHint: nil,
            eventID: nil,
            effectivePerformanceMode: context.performance.mode,
            analysisStatus: context.analysisStatus
        )
    }

    private static func seeking(
        locale: Locale,
        effectivePerformanceMode: CameraEffectivePerformanceMode = .nominal,
        analysisStatus: CameraOverlayAnalysisStatus = .healthy
    ) -> CameraOverlayUXPresentation {
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
            overlayHint: nil,
            eventID: nil,
            effectivePerformanceMode: effectivePerformanceMode,
            analysisStatus: analysisStatus
        )
    }

    private static func fallback(
        locale: Locale,
        effectivePerformanceMode: CameraEffectivePerformanceMode = .nominal,
        analysisStatus: CameraOverlayAnalysisStatus = .healthy
    ) -> CameraOverlayUXPresentation {
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
            overlayHint: nil,
            eventID: nil,
            effectivePerformanceMode: effectivePerformanceMode,
            analysisStatus: analysisStatus
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
              safeText(expandedVerdict.shortVerdict) != nil else {
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

/// Uses the existing pure edge-placement primitive for the command band. The
/// only extra policy here is a compact edge fallback when all regular corners
/// are protected by subject/target evidence.
enum CameraOcclusionSolver {
    static let fallbackMaxWidth: CGFloat = 360
    static let fallbackMaxHeight: CGFloat = 96

    static func resolve(
        viewport: CGRect,
        safeRect: CGRect? = nil,
        subjectRect: CGRect? = nil,
        targetRect: CGRect? = nil,
        contentSize: CGSize,
        preferredAnchor: SETSubjectSafeControlEdge = .bottomLeading,
        reservedRects: [CGRect] = []
    ) -> SETSubjectSafeControlPlacement? {
        let safe = (safeRect ?? viewport).intersection(viewport)
        guard safe.width > 0, safe.height > 0,
              contentSize.width > 0, contentSize.height > 0 else { return nil }

        let safeInsets = SETSafeInsets(
            top: safe.minY - viewport.minY,
            leading: safe.minX - viewport.minX,
            bottom: viewport.maxY - safe.maxY,
            trailing: viewport.maxX - safe.maxX
        )
        let protected = [subjectRect, targetRect].compactMap { $0 } + reservedRects
        let regular = SETSubjectSafeControlPlacement.resolve(
            canvasSize: viewport.size,
            controlSize: contentSize,
            safeInsets: safeInsets,
            subjectRegions: protected
        )
        if let regular { return regular }

        let compact = CGSize(
            width: min(contentSize.width, fallbackMaxWidth, safe.width),
            height: min(contentSize.height, fallbackMaxHeight, safe.height)
        )
        let candidates: [(SETSubjectSafeControlEdge, CGRect)] = [
            (.topLeading, CGRect(x: safe.minX, y: safe.minY, width: compact.width, height: compact.height)),
            (.topTrailing, CGRect(x: safe.maxX - compact.width, y: safe.minY, width: compact.width, height: compact.height)),
            (.bottomLeading, CGRect(x: safe.minX, y: safe.maxY - compact.height, width: compact.width, height: compact.height)),
            (.bottomTrailing, CGRect(x: safe.maxX - compact.width, y: safe.maxY - compact.height, width: compact.width, height: compact.height))
        ]
        let selected = candidates.enumerated().min { lhs, rhs in
            let leftOverlap = overlap(lhs.element.1, protected)
            let rightOverlap = overlap(rhs.element.1, protected)
            if abs(leftOverlap - rightOverlap) > 0.001 { return leftOverlap < rightOverlap }
            if lhs.element.0 == preferredAnchor { return true }
            if rhs.element.0 == preferredAnchor { return false }
            return lhs.offset < rhs.offset
        }
        guard let selected else { return nil }
        return SETSubjectSafeControlPlacement(edge: selected.element.0, frame: selected.element.1)
    }

    private static func overlap(_ frame: CGRect, _ protected: [CGRect]) -> CGFloat {
        protected.reduce(0) {
            let intersection = frame.intersection($1)
            return $0 + max(0, intersection.width) * max(0, intersection.height)
        }
    }
}
