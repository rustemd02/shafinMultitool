import CoreGraphics
import XCTest
@testable import shafinMultitool

/// C09.3 review-only presentation contract: findings/evidence/uncertainty/
/// alternatives are shown, a user assessment is human input (never objective
/// verification or a gold vote), and a review never opens a live episode.
final class CameraReviewPresentationTests: XCTestCase {

    // (а) No active action, no live episode.
    func testReviewCarriesNoActiveActionAndOpensNoLiveEpisode() {
        let review = CameraReviewPresentation.make(critique: makeCritique(), locale: en)

        XCTAssertNil(review.activeActionID)
        XCTAssertFalse(review.hasActiveAction)
        XCTAssertFalse(review.opensLiveEpisode)
        XCTAssertNil(review.episodeToken)
        XCTAssertNil(review.overlayHint)
        XCTAssertFalse(review.alternativeGroups.isEmpty)
        for group in review.alternativeGroups {
            for option in group.options {
                XCTAssertFalse(option.isExecutableInLive, option.id)
                XCTAssertFalse(option.hasExecutableArrow, option.id)
            }
        }
    }

    // (б) Alternatives with one group are one choice, not a step queue.
    func testAlternativesShareOneGroupAndAreNotASequence() {
        let review = CameraReviewPresentation.make(critique: makeCritique(), locale: en)

        XCTAssertEqual(review.alternativeGroups.count, 2)
        let grouped = review.alternativeGroups.first { $0.groupID == "alt_exposure_t" }
        let independent = review.alternativeGroups.first { $0.groupID != "alt_exposure_t" }

        XCTAssertEqual(grouped?.options.map(\.id), ["act_exposure_a", "act_exposure_b"])
        XCTAssertEqual(grouped?.options.count, 2)
        XCTAssertEqual(independent?.options.map(\.id), ["act_horizon"])
        // A group is one choice: no option has a position a consumer could
        // execute in order.
        for group in review.alternativeGroups {
            XCTAssertNil(group.stepIndex, group.groupID)
            XCTAssertTrue(group.isSingleChoice)
        }
    }

    // (в) A review-only user assessment is human input and never objective.
    func testUserAssessmentIsHumanInputAndNeverObjectiveVerificationOrGold() {
        let assessment = CameraReviewUserAssessment(
            source: .humanInput,
            judgement: .better,
            note: "Мне кажется, так лучше."
        )
        let review = CameraReviewPresentation.make(
            critique: makeCritique(),
            reviewVerification: nil,
            userAssessment: assessment,
            locale: en
        )

        guard let stored = review.userAssessment else {
            return XCTFail("user assessment must be carried by the review")
        }
        XCTAssertEqual(stored.source, .humanInput)
        XCTAssertTrue(stored.isHumanInput)
        XCTAssertFalse(stored.isObjectiveVerification)
        XCTAssertFalse(stored.isLocalVerifier)
        XCTAssertFalse(stored.countsAsGoldVote)
        XCTAssertFalse(stored.replacesObjectiveGoalSatisfied)
        // A user's "better" never becomes an automatic "it got better".
        XCTAssertNil(review.objectiveOutcomeCopyKey)
        XCTAssertEqual(review.status, .unknown)
        XCTAssertFalse(review.showsAssessmentRequest)

        for locale in [Self.en, Self.ru] {
            let label = SETCopyKey.cameraReviewHumanInput.localizedString(locale: locale)
            XCTAssertFalse(label.isEmpty)
            XCTAssertNotEqual(label, SETCopyKey.cameraReviewHumanInput.rawValue)
        }
        XCTAssertNotEqual(
            SETCopyKey.cameraReviewHumanInput.localizedString(locale: Self.en),
            SETCopyKey.cameraReviewHumanInput.localizedString(locale: Self.ru)
        )
    }

    // (г) Uncertainty is shown with a reason, not an empty row.
    func testUncertaintyRowsCarryLocalizedReasons() {
        let review = CameraReviewPresentation.make(critique: makeCritique(), locale: en)

        XCTAssertFalse(review.uncertainties.isEmpty)
        XCTAssertTrue(review.uncertainties.contains { $0.reason == .noAutomaticVerifier })
        XCTAssertTrue(review.uncertainties.contains { $0.reason == .limitedToAvailableSignals })
        for uncertainty in review.uncertainties {
            for locale in [Self.en, Self.ru] {
                let detail = uncertainty.detail(locale: locale)
                XCTAssertFalse(detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertNotEqual(detail, uncertainty.reason.rawValue)
            }
            XCTAssertNotEqual(
                uncertainty.detail(locale: Self.en),
                uncertainty.detail(locale: Self.ru)
            )
        }

        // An empty critique still explains why the detailed review is limited.
        let empty = CameraReviewPresentation.make(critique: nil, locale: en)
        XCTAssertTrue(empty.uncertainties.contains { $0.reason == .detailedReviewUnavailable })
        for uncertainty in empty.uncertainties {
            XCTAssertFalse(uncertainty.detail(locale: Self.en).isEmpty)
        }
    }

    // (д) Status distinguishes comparable / incomparable / unknown.
    func testStatusDistinguishesComparableIncomparableUnknown() {
        let unknown = CameraReviewPresentation.make(critique: makeCritique(), locale: en)
        let incomparable = CameraReviewPresentation.make(
            critique: makeCritique(),
            reviewVerification: .incomparable(reason: .evidenceMissing),
            locale: en
        )
        let comparable = CameraReviewPresentation.make(
            critique: makeCritique(),
            reviewVerification: .comparable(outcome: .improved),
            locale: en
        )

        XCTAssertEqual(unknown.status, .unknown)
        XCTAssertEqual(incomparable.status, .incomparable)
        XCTAssertEqual(comparable.status, .comparable)

        XCTAssertNil(unknown.objectiveOutcomeCopyKey)
        XCTAssertNil(incomparable.objectiveOutcomeCopyKey)
        XCTAssertEqual(comparable.objectiveOutcomeCopyKey, .cameraVerificationImproved)
        XCTAssertTrue(incomparable.uncertainties.contains { $0.reason == .notComparable })

        let locales = [Self.en, Self.ru]
        for status in CameraReviewVerificationStatus.allCases {
            for locale in locales {
                XCTAssertFalse(status.label(locale: locale).isEmpty, status.rawValue)
                XCTAssertNotEqual(status.label(locale: locale), status.rawValue)
            }
        }
        for locale in locales {
            let labels = Set(CameraReviewVerificationStatus.allCases.map { $0.label(locale: locale) })
            XCTAssertEqual(labels.count, CameraReviewVerificationStatus.allCases.count)
        }
    }

    // (д) Findings and evidence are backed by catalog copy and named areas.
    func testFindingsAndEvidenceExposeAreasAndCatalogCopy() {
        let review = CameraReviewPresentation.make(critique: makeCritique(), locale: en)

        let issue = review.findings.first { $0.kind == .issue }
        XCTAssertEqual(issue?.id, "iss_background")
        XCTAssertNotNil(issue?.area)
        XCTAssertEqual(issue?.referenceID, "trace_issue_background")
        XCTAssertEqual(
            issue?.title,
            SETCopyKey.traceIssueBackgroundCompetes.localizedString(locale: en)
        )
        XCTAssertFalse(review.findings.filter { $0.kind == .strength }.isEmpty)

        XCTAssertFalse(review.evidence.isEmpty)
        XCTAssertFalse(review.evidence[0].summary.isEmpty)
    }

    // MARK: - Helpers

    private static let en = Locale(identifier: "en")
    private static let ru = Locale(identifier: "ru")
    private var en: Locale { Self.en }

    private func makeCritique() -> PauseCritiquePresentation {
        let evidence = [EvidenceRef(source: .snapshot, key: "background.clutter", value: "observed")]
        return PauseCritiquePresentation(
            frameId: "frame_review",
            verdict: .mixed,
            verdictConfidence: 0.74,
            summaryId: "summary_review",
            shortVerdict: "Кадр можно улучшить.",
            whyGood: "Субъект читается уверенно.",
            whyProblematic: "Фон конкурирует с главным объектом.",
            strengths: [
                PauseStrengthRow(
                    strengthId: "str_focus",
                    type: .clearFocusHierarchy,
                    rationale: "Главный объект остаётся центром внимания.",
                    confidence: 0.68,
                    supportingRegion: NormalizedRect(x: 0.30, y: 0.25, width: 0.35, height: 0.5),
                    traceRefId: "trace_strength_focus"
                )
            ],
            issues: [
                PauseIssueRow(
                    issueId: "iss_background",
                    type: .backgroundCompetesWithSubject,
                    severity: 0.63,
                    confidence: 0.79,
                    rationale: "Контрастный фон слишком близко к субъекту.",
                    affectedRegion: NormalizedRect(x: 0.55, y: 0.20, width: 0.30, height: 0.50),
                    suggestedFixTypes: [.reframing],
                    traceRefId: "trace_issue_background"
                )
            ],
            actions: [
                PauseActionRow(
                    actionId: "act_exposure_b",
                    actionType: .reduceBackgroundDistractions,
                    semanticActionType: .removeBackgroundHotspot,
                    priority: 2,
                    confidence: 0.74,
                    linkedIssueIds: ["iss_background"],
                    expectedOutcome: "Убрать пересвет.",
                    targetRegion: NormalizedRect(x: 0.60, y: 0.18, width: 0.22, height: 0.30),
                    overlayHintId: nil,
                    traceRefId: "trace_action_exposure_b",
                    alternativeGroupID: "alt_exposure_t"
                ),
                PauseActionRow(
                    actionId: "act_exposure_a",
                    actionType: .reduceBackgroundDistractions,
                    semanticActionType: .changeCameraAngle,
                    priority: 1,
                    confidence: 0.81,
                    linkedIssueIds: ["iss_background"],
                    expectedOutcome: "Сместиться к чистой точке.",
                    targetRegion: nil,
                    overlayHintId: nil,
                    traceRefId: "trace_action_exposure_a",
                    alternativeGroupID: "alt_exposure_t"
                ),
                PauseActionRow(
                    actionId: "act_horizon",
                    actionType: .levelHorizon,
                    semanticActionType: .levelHorizon,
                    priority: 3,
                    confidence: 0.70,
                    linkedIssueIds: ["iss_background"],
                    expectedOutcome: "Выровнять горизонт.",
                    targetRegion: nil,
                    overlayHintId: nil,
                    traceRefId: "trace_action_horizon"
                )
            ],
            noChangeRationale: nil,
            assumptions: ["Субъект считается главным объектом кадра."],
            traceRootIds: ["trace_root_review"],
            fallbackUsed: true,
            linkedEvidence: CameraLinkedEvidenceProjection(
                frameID: "frame_review",
                actionID: "act_exposure_a",
                actionType: .changeAngle,
                semanticActionType: .changeCameraAngle,
                issueID: "iss_background",
                issueType: .backgroundCompetesWithSubject,
                evidence: evidence
            )
        )
    }
}
