import CoreGraphics
import Foundation

/// C09.3 review-only surface. A review is a read of already selected material
/// (N6.2 `ReviewReport`): it carries findings, evidence, uncertainty and
/// alternative groups, but it has no executable active action and never opens
/// a live coaching episode. Every user-facing string is catalog-owned; no
/// provider prose is interpolated here.
enum CameraReviewCoverage: String, Equatable, Sendable {
    case selectedFrame = "selected_frame"
    case singleFrame = "single_frame"
}

/// Comparability of the reviewed material. Kept distinct from an outcome so a
/// user assessment can never be shown as "it got better": `comparable` only
/// means a local verifier actually produced a measured pair.
enum CameraReviewVerificationStatus: String, CaseIterable, Equatable, Sendable {
    case comparable
    case incomparable
    case unknown

    var copyKey: SETCopyKey {
        switch self {
        case .comparable: return .cameraStatusComparable
        case .incomparable: return .cameraVerificationIncomparable
        case .unknown: return .cameraStatusUnknown
        }
    }

    func label(locale: Locale) -> String {
        copyKey.localizedString(locale: locale)
    }

    /// A missing verifier is honestly `unknown`; it is never promoted to a
    /// comparable pair just because a review exists.
    static func from(_ decision: ActionVerificationDecision?) -> Self {
        switch decision {
        case .some(.comparable): return .comparable
        case .some(.incomparable): return .incomparable
        case .none: return .unknown
        }
    }
}

/// A review finding is a claim about a named area of the reviewed material.
/// `area`/`referenceID` are the observable location and provenance link; the
/// title comes from the catalog and never from raw provider text.
struct CameraReviewFinding: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case issue
        case strength
    }

    let id: String
    let kind: Kind
    let area: NormalizedRect?
    let referenceID: String?
    let title: String
}

/// One piece of typed evidence that supports a finding. `refs` keeps the
/// observed evidence keys so the "why" chain is finding -> observation ->
/// evidence rather than free prose.
struct CameraReviewEvidence: Equatable, Sendable {
    let findingRef: String
    let summary: String
    let refs: [String]
}

/// What the review does not know, and why. `detail(locale:)` resolves a
/// catalog reason, so an uncertainty row can never render as an empty string.
struct CameraReviewUncertainty: Equatable, Sendable {
    enum Reason: String, CaseIterable, Equatable, Sendable {
        case noAutomaticVerifier
        case notComparable
        case limitedToAvailableSignals
        case detailedReviewUnavailable

        var copyKey: SETCopyKey {
            switch self {
            case .noAutomaticVerifier, .detailedReviewUnavailable:
                return .cameraStatusUnknown
            case .notComparable:
                return .cameraVerificationIncomparable
            case .limitedToAvailableSignals:
                return .traceLimitScope
            }
        }
    }

    let reason: Reason

    func detail(locale: Locale) -> String {
        reason.copyKey.localizedString(locale: locale)
    }

    var isPresent: Bool { true }
}

/// N6.2 admissibility of a review proposal. Before admission a proposal is a
/// hypothesis with conditional text and no executable arrow.
enum CameraReviewAdmissibility: String, CaseIterable, Equatable, Sendable {
    case qualified
    case needsUserInput = "needs_user_input"
    case unsupported
}

/// N6.2 scope: review proposals target the next capture, except selecting the
/// already reviewed moment.
enum CameraReviewScope: String, Equatable, Sendable {
    case nextCapture = "next_capture"
    case now
}

/// A single review suggestion. It keeps the Action fields a review needs, but
/// it is presentation-only: it has no live episode token and no arrow.
struct CameraReviewProposal: Equatable, Sendable {
    let id: String
    let copyKey: SETCopyKey
    let admissibility: CameraReviewAdmissibility
    let reasonCodes: [String]
    let targetRegion: NormalizedRect?
    /// Required only for `qualified`; absent otherwise (N6.2/N6.1).
    let qualificationRef: String?
    let scope: CameraReviewScope

    /// N6.2: qualificationRef exists exactly when the proposal is qualified.
    var isWellFormed: Bool {
        (qualificationRef != nil) == (admissibility == .qualified)
    }

    /// Hard review invariant: a review proposal never carries an executable
    /// arrow or active action, even when it is qualified.
    var isExecutableInLive: Bool { false }
    var hasExecutableArrow: Bool { false }

    func title(locale: Locale) -> String {
        copyKey.localizedString(locale: locale)
    }
}

/// Incompatible suggestions of one cause share a group and are one choice.
/// They are compared side by side; the group is never a step queue, so there
/// is no positional index a consumer could execute in order.
struct CameraReviewAlternativeGroup: Equatable, Sendable {
    let groupID: String
    let options: [CameraReviewProposal]

    var isSingleChoice: Bool { !options.isEmpty }
    var stepIndex: Int? { nil }
}

/// A review-only user assessment. Marked as human input: it is not an
/// objective verification, not a new gold vote, and it never replaces the
/// verifier's `goalSatisfied`.
struct CameraReviewUserAssessment: Equatable, Sendable {
    enum Source: String, Equatable, Sendable {
        case humanInput = "human_input"
    }

    /// Review-only vocabulary. Deliberately not `ActionVerificationOutcome`:
    /// a user can express a preference, but cannot assert `fixed`/`improved`
    /// as a measured result.
    enum Judgement: String, CaseIterable, Equatable, Sendable {
        case better
        case same
        case worse
        case undetermined
    }

    let source: Source
    let judgement: Judgement
    let note: String?

    var isHumanInput: Bool { source == .humanInput }
    var isObjectiveVerification: Bool { false }
    var isLocalVerifier: Bool { false }
    var countsAsGoldVote: Bool { false }
    var replacesObjectiveGoalSatisfied: Bool { false }
}

/// The complete review projection. `objectiveOutcomeCopyKey` is populated only
/// when a local verifier produced a comparable measured pair; a user
/// assessment can never populate it.
struct CameraReviewPresentation: Equatable, Sendable {
    let coverage: CameraReviewCoverage
    let findings: [CameraReviewFinding]
    let evidence: [CameraReviewEvidence]
    let uncertainties: [CameraReviewUncertainty]
    let alternativeGroups: [CameraReviewAlternativeGroup]
    let status: CameraReviewVerificationStatus
    let userAssessment: CameraReviewUserAssessment?
    let objectiveOutcomeCopyKey: SETCopyKey?

    // MARK: C09.3 review invariants

    /// A review never carries decision.activeAction.
    var activeActionID: String? { nil }
    var hasActiveAction: Bool { false }

    /// A review view does not create or own a live coaching episode.
    var opensLiveEpisode: Bool { false }
    var episodeToken: CoachingEpisodeToken? { nil }
    var overlayHint: OverlayHint? { nil }

    /// When no verifier ran and the user has not answered yet, the review asks
    /// for a human assessment instead of claiming an automatic result.
    var showsAssessmentRequest: Bool {
        userAssessment == nil && objectiveOutcomeCopyKey == nil
    }

    static var none: CameraReviewPresentation {
        CameraReviewPresentation(
            coverage: .selectedFrame,
            findings: [],
            evidence: [],
            uncertainties: [CameraReviewUncertainty(reason: .noAutomaticVerifier)],
            alternativeGroups: [],
            status: .unknown,
            userAssessment: nil,
            objectiveOutcomeCopyKey: nil
        )
    }
}

// MARK: - Owner output -> review projection

extension CameraReviewPresentation {
    /// Pure projection from existing owner outputs. `critique` supplies
    /// findings/evidence/alternatives; `reviewVerification` may only come from
    /// a local verifier, never from `userAssessment`.
    static func make(
        critique: PauseCritiquePresentation?,
        reviewVerification: ActionVerificationDecision? = nil,
        userAssessment: CameraReviewUserAssessment? = nil,
        coverage: CameraReviewCoverage = .selectedFrame,
        locale: Locale
    ) -> CameraReviewPresentation {
        let status = CameraReviewVerificationStatus.from(reviewVerification)
        let objectiveOutcomeCopyKey = outcomeCopyKey(for: reviewVerification)

        let findings = (critique?.issues.map { finding(from: $0, locale: locale) } ?? [])
            + (critique?.strengths.map { finding(from: $0, locale: locale) } ?? [])

        let evidence = evidenceRows(from: critique, locale: locale)
        let groups = alternativeGroups(from: critique?.actions ?? [])
        let uncertainties = uncertaintyRows(
            critique: critique,
            status: status,
            objectiveOutcomeCopyKey: objectiveOutcomeCopyKey
        )

        return CameraReviewPresentation(
            coverage: coverage,
            findings: findings,
            evidence: evidence,
            uncertainties: uncertainties,
            alternativeGroups: groups,
            status: status,
            userAssessment: userAssessment,
            objectiveOutcomeCopyKey: objectiveOutcomeCopyKey
        )
    }

    private static func finding(from issue: PauseIssueRow, locale: Locale) -> CameraReviewFinding {
        CameraReviewFinding(
            id: issue.issueId,
            kind: .issue,
            area: issue.affectedRegion,
            referenceID: issue.traceRefId,
            title: issueCopyKey(issue.type).localizedString(locale: locale)
        )
    }

    private static func finding(from strength: PauseStrengthRow, locale: Locale) -> CameraReviewFinding {
        CameraReviewFinding(
            id: strength.strengthId,
            kind: .strength,
            area: strength.supportingRegion,
            referenceID: strength.traceRefId,
            title: strengthCopyKey(strength.type).localizedString(locale: locale)
        )
    }

    private static func evidenceRows(from critique: PauseCritiquePresentation?,
                                     locale: Locale) -> [CameraReviewEvidence] {
        guard let projection = critique?.linkedEvidence,
              let summary = DeterministicCritiqueSummaryBuilder().makeExplanation(
                  for: projection,
                  locale: locale
              ),
              !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        let refs = projection.evidence.map { "\($0.source.rawValue):\($0.key)" }
        return [CameraReviewEvidence(findingRef: projection.issueID, summary: summary, refs: refs)]
    }

    /// One group per cause. Rows without an explicit `alternativeGroupID` are
    /// independent single options; rows sharing an id are compared together.
    private static func alternativeGroups(from actions: [PauseActionRow]) -> [CameraReviewAlternativeGroup] {
        var order: [String] = []
        var grouped: [String: [CameraReviewProposal]] = [:]
        for action in actions.sorted(by: PauseActionRow.canonicalOrder) {
            let groupID = action.alternativeGroupID ?? "solo-\(action.actionId)"
            if grouped[groupID] == nil { order.append(groupID) }
            grouped[groupID, default: []].append(
                CameraReviewProposal(
                    id: action.actionId,
                    copyKey: SETCameraCopy.actionKey(for: action.semanticActionType),
                    admissibility: .needsUserInput,
                    reasonCodes: [],
                    targetRegion: action.targetRegion,
                    qualificationRef: nil,
                    scope: .nextCapture
                )
            )
        }
        return order.compactMap { groupID in
            grouped[groupID].map { CameraReviewAlternativeGroup(groupID: groupID, options: $0) }
        }
    }

    private static func uncertaintyRows(critique: PauseCritiquePresentation?,
                                        status: CameraReviewVerificationStatus,
                                        objectiveOutcomeCopyKey: SETCopyKey?) -> [CameraReviewUncertainty] {
        var rows: [CameraReviewUncertainty] = []
        if status == .incomparable {
            rows.append(CameraReviewUncertainty(reason: .notComparable))
        }
        if objectiveOutcomeCopyKey == nil {
            rows.append(CameraReviewUncertainty(reason: .noAutomaticVerifier))
        }
        if critique == nil {
            rows.append(CameraReviewUncertainty(reason: .detailedReviewUnavailable))
        } else if critique?.fallbackUsed == true {
            rows.append(CameraReviewUncertainty(reason: .limitedToAvailableSignals))
        }
        return rows
    }

    /// Only a comparable local verification exposes outcome copy. `nil` means
    /// no automatic result may be shown.
    private static func outcomeCopyKey(for decision: ActionVerificationDecision?) -> SETCopyKey? {
        guard case .comparable(let outcome) = decision else { return nil }
        switch outcome {
        case .fixed: return .cameraVerificationFixed
        case .improved: return .cameraVerificationImproved
        case .unchanged: return .cameraVerificationUnchanged
        case .worse: return .cameraVerificationWorse
        }
    }

    private static func issueCopyKey(_ issue: IssueTypeV1) -> SETCopyKey {
        switch issue {
        case .subjectTooCloseToEdge: return .traceIssueSubjectEdge
        case .subjectNotProminentEnough: return .traceIssueSubjectProminence
        case .backgroundCompetesWithSubject: return .traceIssueBackgroundCompetes
        case .insufficientLookSpace: return .traceIssueLookSpace
        case .backlightHidesSubject: return .traceIssueBacklight
        case .sceneHasNoClearFocus: return .traceIssueFocus
        case .frameVisuallyOverloaded: return .traceIssueOverloaded
        case .horizonDistracts: return .traceIssueHorizon
        }
    }

    private static func strengthCopyKey(_ strength: StrengthTypeV1) -> SETCopyKey {
        switch strength {
        case .goodSubjectIsolation: return .traceStrengthIsolation
        case .goodLightEmphasis: return .traceStrengthLight
        case .clearFocusHierarchy: return .traceStrengthFocus
        case .stableHorizonSupportsScene: return .traceStrengthHorizon
        case .balancedCompositionForScene: return .traceStrengthComposition
        }
    }
}
