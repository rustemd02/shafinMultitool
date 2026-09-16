import XCTest
@testable import shafinMultitool

private struct LiveProductionFixture {
    let snapshot: FrameFeatureSnapshot
    let semantics: SceneSemanticsReport
    let critique: CritiqueReport
    let plan: RecommendationPlan
}

final class SemanticTipPlannerTests: XCTestCase {
    private let planner = SemanticTipPlanner()

    func testLivePlannerBuildsLookSpaceTipFromDeterministicIssue() {
        let critique = makeCritique(
            frameId: "frame-look-space",
            mode: .live,
            verdict: .mixed,
            issues: [
                FrameIssue(
                    id: "issue-look-space",
                    type: .insufficientLookSpace,
                    severity: 0.72,
                    confidence: 0.84,
                    rationale: "По направлению взгляда тесно.",
                    evidence: [EvidenceRef(source: .semantics, key: "readability.lookSpaceAdequate", value: "false", confidence: 0.84)],
                    affectedRegion: NormalizedRect(x: 0.62, y: 0.15, width: 0.24, height: 0.46),
                    suggestedFixTypes: [.reframing]
                )
            ]
        )
        let plan = RecommendationPlan(
            frameId: critique.frameId,
            mode: .live,
            inputVerdict: critique.verdict,
            primaryAction: RecommendationAction(
                id: "action-move-left",
                actionType: .moveFrameLeft,
                priority: 1,
                targetRegion: NormalizedRect(x: 0.62, y: 0.15, width: 0.24, height: 0.46),
                linkedIssueIds: ["issue-look-space"],
                expectedOutcome: "legacy",
                guardrail: ActionGuardrail(requiresStillCamera: false, minConfidence: 0.4, suppressWhenMoving: false),
                overlayHint: nil
            ),
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.82
        )

        let output = planner.plan(
            input: SemanticTipPlannerInput(
                frameId: critique.frameId,
                mode: .live,
                critique: critique,
                recommendationPlan: plan,
                semantics: makeSemantics(frameId: critique.frameId, mode: .live, subjectKind: .person)
            )
        )

        XCTAssertEqual(output.livePrimaryTip?.tipType, .createLookSpaceLeft)
        XCTAssertEqual(output.livePrimaryTip?.actionType, .shiftFrameLeft)
        XCTAssertEqual(output.livePrimaryTip?.liveText, "Смести камеру чуть левее.")
        XCTAssertEqual(output.livePrimaryTip?.linkedIssueIds, ["issue-look-space"])
    }

    /// C05 item 1: the materializer builds the text of the SAME accepted
    /// Action. It may not select an independent advice from raw evidence.
    func testLivePrimaryTipIsBoundToTheAcceptedPlanAction() throws {
        let critique = makeCritique(
            frameId: "frame-single-owner",
            mode: .live,
            verdict: .mixed,
            issues: [
                FrameIssue(
                    id: "issue-look-space",
                    type: .insufficientLookSpace,
                    severity: 0.72,
                    confidence: 0.84,
                    rationale: "По направлению взгляда тесно.",
                    evidence: [EvidenceRef(source: .semantics, key: "readability.lookSpaceAdequate", value: "false", confidence: 0.84)],
                    affectedRegion: NormalizedRect(x: 0.62, y: 0.15, width: 0.24, height: 0.46),
                    suggestedFixTypes: [.reframing]
                )
            ]
        )
        let acceptedActionID = "action-move-left"
        let plan = RecommendationPlan(
            frameId: critique.frameId,
            mode: .live,
            inputVerdict: critique.verdict,
            primaryAction: RecommendationAction(
                id: acceptedActionID,
                actionType: .moveFrameLeft,
                priority: 1,
                targetRegion: NormalizedRect(x: 0.62, y: 0.15, width: 0.24, height: 0.46),
                linkedIssueIds: ["issue-look-space"],
                expectedOutcome: "legacy",
                guardrail: ActionGuardrail(requiresStillCamera: false, minConfidence: 0.4, suppressWhenMoving: false),
                overlayHint: nil
            ),
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.82
        )

        let output = planner.plan(
            input: SemanticTipPlannerInput(
                frameId: critique.frameId,
                mode: .live,
                critique: critique,
                recommendationPlan: plan,
                semantics: makeSemantics(frameId: critique.frameId, mode: .live, subjectKind: .person)
            )
        )

        let tip = try XCTUnwrap(output.livePrimaryTip)
        XCTAssertEqual(tip.primaryActionId, acceptedActionID,
                       "the tip must materialize the accepted action, not a second one")
        XCTAssertEqual(tip.linkedActionIds, [acceptedActionID])
        XCTAssertEqual(output.allRankedCandidates.map(\.primaryActionId).allSatisfy { $0 == nil || $0 == acceptedActionID },
                       true,
                       "no ranked candidate may reference an action outside the accepted plan")
    }

    func testPersonEdgeTipsUsePhysicalCameraDirectionAndVisualCopy() throws {
        let cases: [(action: ActionTypeV1, tip: SemanticTipType, direction: SemanticDirection, liveText: String, pauseText: String)] = [
            (.moveFrameLeft, .moveSubjectOffLeftEdge, .left, "Направь камеру чуть левее, сохранив героя в превью.", "Герой зажат слева. Направь камеру чуть левее, сохранив его в превью."),
            (.moveFrameRight, .moveSubjectOffRightEdge, .right, "Направь камеру чуть правее, сохранив героя в превью.", "Герой зажат справа. Направь камеру чуть правее, сохранив его в превью.")
        ]

        for (index, expected) in cases.enumerated() {
            let frameId = "frame-person-edge-\(index)"
            let issueId = "issue-person-edge-\(index)"
            let critique = makeCritique(
                frameId: frameId,
                mode: .live,
                verdict: .mixed,
                issues: [
                    FrameIssue(
                        id: issueId,
                        type: .subjectTooCloseToEdge,
                        severity: 0.82,
                        confidence: 0.86,
                        rationale: "Герой зажат у края.",
                        evidence: [EvidenceRef(source: .semantics, key: "readability.edgePressureScore", value: "0.82", confidence: 0.86)],
                        affectedRegion: NormalizedRect(x: expected.direction == .left ? 0.01 : 0.72, y: 0.18, width: 0.20, height: 0.44),
                        suggestedFixTypes: [.reframing]
                    )
                ]
            )
            let plan = RecommendationPlan(
                frameId: frameId,
                mode: .live,
                inputVerdict: .mixed,
                primaryAction: RecommendationAction(
                    id: "action-person-edge-\(index)",
                    actionType: expected.action,
                    priority: 1,
                    targetRegion: nil,
                    linkedIssueIds: [issueId],
                    expectedOutcome: "legacy",
                    guardrail: ActionGuardrail(requiresStillCamera: false, minConfidence: 0.4, suppressWhenMoving: false),
                    overlayHint: nil
                ),
                secondaryActions: [],
                deferredActions: [],
                noChangeRationale: nil,
                planConfidence: 0.86
            )

            let output = planner.plan(
                input: SemanticTipPlannerInput(
                    frameId: frameId,
                    mode: .live,
                    critique: critique,
                    recommendationPlan: plan,
                    semantics: makeSemantics(frameId: frameId, mode: .live, subjectKind: .person)
                )
            )
            let candidate = try XCTUnwrap(output.livePrimaryTip)
            XCTAssertEqual(candidate.tipType, expected.tip)
            XCTAssertEqual(candidate.actionType, expected.tip == .moveSubjectOffLeftEdge ? .shiftFrameLeft : .shiftFrameRight)
            XCTAssertEqual(candidate.direction, expected.direction)
            XCTAssertEqual(candidate.liveText, expected.liveText)
            XCTAssertEqual(candidate.pauseText, expected.pauseText)
        }
    }

    func testPausePlannerLocalizesFaceContourConflictWithValidatedVLMEntity() throws {
        let critique = makeCritique(
            frameId: "frame-face-conflict",
            mode: .pause,
            verdict: .mixed,
            issues: [
                FrameIssue(
                    id: "issue-face-conflict",
                    type: .backgroundCompetesWithSubject,
                    severity: 0.68,
                    confidence: 0.79,
                    rationale: "Предмет рядом с лицом конкурирует с героем.",
                    evidence: [EvidenceRef(source: .semantics, key: "dominance.focusCompetitionScore", value: "0.68", confidence: 0.79)],
                    affectedRegion: NormalizedRect(x: 0.36, y: 0.18, width: 0.16, height: 0.26),
                    suggestedFixTypes: [.angleAdjustment]
                )
            ]
        )
        let plan = RecommendationPlan(
            frameId: critique.frameId,
            mode: .pause,
            inputVerdict: critique.verdict,
            primaryAction: RecommendationAction(
                id: "action-remove",
                actionType: .reduceBackgroundDistractions,
                priority: 1,
                targetRegion: NormalizedRect(x: 0.36, y: 0.18, width: 0.16, height: 0.26),
                linkedIssueIds: ["issue-face-conflict"],
                expectedOutcome: "legacy",
                guardrail: ActionGuardrail(requiresStillCamera: false, minConfidence: 0.4, suppressWhenMoving: false),
                overlayHint: nil
            ),
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.78
        )
        let evidence = VLMEvidenceValidationResult(
            requestId: "req-1",
            frameId: critique.frameId,
            accepted: true,
            acceptedPrimaryEntityRef: "ent-person-1",
            acceptedPrimaryEntityKind: .person,
            acceptedSecondaryEntityRef: "ent-vase-1",
            acceptedSecondaryEntityKind: .prop,
            acceptedObservations: [
                VLMVisualEvidenceObservation(
                    observationId: "obs-1",
                    dimension: .faceVisibility,
                    polarity: .supportsProblem,
                    score: 0.76,
                    confidence: 0.82,
                    uncertaintyReasons: [],
                    primaryEntityRef: "ent-person-1",
                    secondaryEntityRef: "ent-vase-1",
                    visualProblemType: .faceContourOcclusion,
                    visualStrengthType: nil,
                    supportedIssueIds: ["issue-face-conflict"],
                    supportedStrengthIds: [],
                    suggestedActionIds: [.removeDistractingObject],
                    evidenceNote: nil
                )
            ],
            acceptedRelations: [
                VLMEntityRelation(
                    relationId: "rel-1",
                    sourceEntityRef: "ent-vase-1",
                    targetEntityRef: "ent-person-1",
                    relationType: .blocks,
                    dimension: .faceVisibility,
                    score: 0.76,
                    confidence: 0.82,
                    uncertaintyReasons: [],
                    supportedObservationIds: ["obs-1"]
                )
            ],
            acceptedSuggestedActionIds: [.removeDistractingObject],
            acceptedPrimaryLabel: "герой",
            acceptedSecondaryLabel: "ваза",
            violations: [],
            fallback: .useValidatedEvidence
        )

        let output = planner.plan(
            input: SemanticTipPlannerInput(
                frameId: critique.frameId,
                mode: .pause,
                critique: critique,
                recommendationPlan: plan,
                semantics: makeSemantics(frameId: critique.frameId, mode: .pause, subjectKind: .person),
                validatedEvidence: evidence
            )
        )

        let primary = try XCTUnwrap(output.pauseExpandedTips.first)
        XCTAssertEqual(primary.tipType, .removeObjectFromFaceContour)
        XCTAssertEqual(primary.targetEntityDisplayLabel, "ваза")
        XCTAssertEqual(primary.targetEntityRef, "ent-vase-1")
        XCTAssertEqual(primary.secondaryEntityRef, "ent-person-1")
        XCTAssertEqual(primary.liveText, "Убери вазу от лица.")
    }

    func testPlannerFallsBackToGenericObjectLabelWithoutGrounding() throws {
        let critique = makeCritique(
            frameId: "frame-object-edge",
            mode: .pause,
            verdict: .mixed,
            issues: [
                FrameIssue(
                    id: "issue-object-edge",
                    type: .subjectTooCloseToEdge,
                    severity: 0.65,
                    confidence: 0.75,
                    rationale: "Главный объект зажат у края.",
                    evidence: [EvidenceRef(source: .semantics, key: "readability.edgePressureScore", value: "0.75", confidence: 0.75)],
                    affectedRegion: NormalizedRect(x: 0.72, y: 0.22, width: 0.20, height: 0.22),
                    suggestedFixTypes: [.reframing]
                )
            ]
        )
        let plan = RecommendationPlan(
            frameId: critique.frameId,
            mode: .pause,
            inputVerdict: critique.verdict,
            primaryAction: RecommendationAction(
                id: "action-edge-right",
                actionType: .moveFrameRight,
                priority: 1,
                targetRegion: NormalizedRect(x: 0.72, y: 0.22, width: 0.20, height: 0.22),
                linkedIssueIds: ["issue-object-edge"],
                expectedOutcome: "Передвинь предмет левее в превью.",
                guardrail: ActionGuardrail(requiresStillCamera: false, minConfidence: 0.4, suppressWhenMoving: false),
                overlayHint: nil
            ),
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.74
        )

        let output = planner.plan(
            input: SemanticTipPlannerInput(
                frameId: critique.frameId,
                mode: .pause,
                critique: critique,
                recommendationPlan: plan,
                semantics: makeSemantics(frameId: critique.frameId, mode: .pause, subjectKind: .object)
            )
        )

        let primary = try XCTUnwrap(output.pauseExpandedTips.first)
        XCTAssertEqual(primary.tipType, .moveObjectOffRightEdge)
        XCTAssertEqual(primary.actionType, .moveObjectLeft)
        XCTAssertEqual(primary.targetEntityDisplayLabel, "предмет")
        XCTAssertEqual(primary.liveText, "Передвинь предмет левее в превью.")
        XCTAssertNil(primary.targetEntityRef)
        XCTAssertTrue(output.fallbackUsed)
    }

    func testPlannerMapsLeftObjectEdgeToMovingObjectRight() throws {
        let critique = makeCritique(
            frameId: "frame-object-edge-left",
            mode: .pause,
            verdict: .mixed,
            issues: [
                FrameIssue(
                    id: "issue-object-edge-left",
                    type: .subjectTooCloseToEdge,
                    severity: 0.65,
                    confidence: 0.75,
                    rationale: "Главный объект зажат у края.",
                    evidence: [EvidenceRef(source: .semantics, key: "readability.edgePressureScore", value: "0.75", confidence: 0.75)],
                    affectedRegion: NormalizedRect(x: 0.02, y: 0.22, width: 0.20, height: 0.22),
                    suggestedFixTypes: [.reframing]
                )
            ]
        )
        let plan = RecommendationPlan(
            frameId: critique.frameId,
            mode: .pause,
            inputVerdict: critique.verdict,
            primaryAction: RecommendationAction(
                id: "action-edge-left",
                actionType: .moveFrameLeft,
                priority: 1,
                targetRegion: NormalizedRect(x: 0.02, y: 0.22, width: 0.20, height: 0.22),
                linkedIssueIds: ["issue-object-edge-left"],
                expectedOutcome: "Передвинь предмет правее в превью.",
                guardrail: ActionGuardrail(requiresStillCamera: false, minConfidence: 0.4, suppressWhenMoving: false),
                overlayHint: nil
            ),
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.74
        )

        let output = planner.plan(
            input: SemanticTipPlannerInput(
                frameId: critique.frameId,
                mode: .pause,
                critique: critique,
                recommendationPlan: plan,
                semantics: makeSemantics(frameId: critique.frameId, mode: .pause, subjectKind: .object)
            )
        )

        let primary = try XCTUnwrap(output.pauseExpandedTips.first)
        XCTAssertEqual(primary.tipType, .moveObjectOffLeftEdge)
        XCTAssertEqual(primary.actionType, .moveObjectRight)
    }

    func testGoodFrameProducesPositiveTip() {
        let critique = CritiqueReport(
            frameId: "frame-good",
            mode: .live,
            verdict: .good,
            verdictConfidence: 0.88,
            strengths: [
                FrameStrength(
                    id: "strength-focus",
                    type: .clearFocusHierarchy,
                    confidence: 0.86,
                    rationale: "Главный объект читается сразу.",
                    evidence: [EvidenceRef(source: .semantics, key: "dominance.hasClearFocus", value: "true", confidence: 0.86)]
                )
            ],
            issues: [],
            summary: CritiqueSummary(
                id: "summary-good",
                shortVerdict: "Кадр уже читается хорошо.",
                whyGood: "Главный объект читается сразу и фон ему не мешает."
            ),
            traceRefs: ["trace-good-summary"],
            fallbackUsed: false
        )
        let plan = RecommendationPlan(
            frameId: critique.frameId,
            mode: .live,
            inputVerdict: .good,
            primaryAction: nil,
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: "Кадр уже читается хорошо.",
            planConfidence: 0.88
        )

        let output = planner.plan(
            input: SemanticTipPlannerInput(
                frameId: critique.frameId,
                mode: .live,
                critique: critique,
                recommendationPlan: plan,
                semantics: makeSemantics(frameId: critique.frameId, mode: .live, subjectKind: .person)
            )
        )

        XCTAssertEqual(output.livePrimaryTip?.tipType, .keepFocusHierarchy)
        XCTAssertEqual(output.livePrimaryTip?.actionType, .keepCurrentSetup)
        XCTAssertEqual(output.livePrimaryTip?.summaryId, critique.summary.id)
    }

    func testWeakNoClearFocusDoesNotInventStepCloserOrSimplifyBackground() {
        let critique = makeCritique(
            frameId: "frame-weak-no-focus",
            mode: .pause,
            verdict: .mixed,
            issues: [
                FrameIssue(
                    id: "issue-weak-no-focus",
                    type: .sceneHasNoClearFocus,
                    severity: 0.52,
                    confidence: 0.58,
                    rationale: "Центр внимания не до конца очевиден.",
                    evidence: [EvidenceRef(source: .semantics, key: "dominance.focusCompetitionScore", value: "0.52", confidence: 0.58)],
                    affectedRegion: nil,
                    suggestedFixTypes: [.reframing]
                )
            ]
        )
        let plan = RecommendationPlan(
            frameId: critique.frameId,
            mode: .pause,
            inputVerdict: critique.verdict,
            primaryAction: RecommendationAction(
                id: "action-weak-no-focus",
                actionType: .increaseSubjectSize,
                priority: 1,
                targetRegion: nil,
                linkedIssueIds: ["issue-weak-no-focus"],
                expectedOutcome: "legacy",
                guardrail: ActionGuardrail(requiresStillCamera: false, minConfidence: 0.4, suppressWhenMoving: false),
                overlayHint: nil
            ),
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.60
        )

        let output = planner.plan(
            input: SemanticTipPlannerInput(
                frameId: critique.frameId,
                mode: .pause,
                critique: critique,
                recommendationPlan: plan,
                semantics: makeSemantics(frameId: critique.frameId, mode: .pause, subjectKind: .person)
            )
        )

        XCTAssertTrue(output.pauseExpandedTips.isEmpty)
    }

    func testStrongNoClearFocusStillProducesCorrectiveTip() {
        let critique = makeCritique(
            frameId: "frame-strong-no-focus",
            mode: .pause,
            verdict: .mixed,
            issues: [
                FrameIssue(
                    id: "issue-strong-no-focus",
                    type: .sceneHasNoClearFocus,
                    severity: 0.74,
                    confidence: 0.78,
                    rationale: "В кадре нет устойчивого центра внимания.",
                    evidence: [EvidenceRef(source: .semantics, key: "dominance.focusCompetitionScore", value: "0.82", confidence: 0.78)],
                    affectedRegion: nil,
                    suggestedFixTypes: [.reframing]
                )
            ]
        )
        let plan = RecommendationPlan(
            frameId: critique.frameId,
            mode: .pause,
            inputVerdict: critique.verdict,
            primaryAction: RecommendationAction(
                id: "action-strong-no-focus",
                actionType: .increaseSubjectSize,
                priority: 1,
                targetRegion: nil,
                linkedIssueIds: ["issue-strong-no-focus"],
                expectedOutcome: "legacy",
                guardrail: ActionGuardrail(requiresStillCamera: false, minConfidence: 0.4, suppressWhenMoving: false),
                overlayHint: nil
            ),
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.78
        )

        let output = planner.plan(
            input: SemanticTipPlannerInput(
                frameId: critique.frameId,
                mode: .pause,
                critique: critique,
                recommendationPlan: plan,
                semantics: makeSemantics(frameId: critique.frameId, mode: .pause, subjectKind: .person)
            )
        )

        XCTAssertEqual(output.pauseExpandedTips.first?.tipType, .clarifyMainSubjectFocus)
    }

    func testPipelineLivePresentationSuppressesNonWhitelistedSemanticTip() async {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let critique = makeCritique(
            frameId: "pipeline-live",
            mode: .live,
            verdict: .mixed,
            issues: [
                FrameIssue(
                    id: "issue-look-space",
                    type: .insufficientLookSpace,
                    severity: 0.90,
                    confidence: 0.88,
                    rationale: "По направлению взгляда тесно.",
                    evidence: [EvidenceRef(source: .semantics, key: "readability.lookSpaceAdequate", value: "false", confidence: 0.83)],
                    affectedRegion: NormalizedRect(x: 0.62, y: 0.18, width: 0.24, height: 0.44),
                    suggestedFixTypes: [.reframing]
                )
            ]
        )
        let plan = RecommendationPlan(
            frameId: critique.frameId,
            mode: .live,
            inputVerdict: critique.verdict,
            primaryAction: RecommendationAction(
                id: "action-right",
                actionType: .moveFrameRight,
                priority: 1,
                targetRegion: NormalizedRect(x: 0.62, y: 0.18, width: 0.24, height: 0.44),
                linkedIssueIds: ["issue-look-space"],
                expectedOutcome: "legacy",
                guardrail: ActionGuardrail(requiresStillCamera: false, minConfidence: 0.4, suppressWhenMoving: false),
                overlayHint: nil
            ),
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.88
        )
        let semantics = makeSemantics(frameId: critique.frameId, mode: .live, subjectKind: .person)
        let semanticOutput = planner.plan(
            input: SemanticTipPlannerInput(
                frameId: critique.frameId,
                mode: .live,
                critique: critique,
                recommendationPlan: plan,
                semantics: semantics
            )
        )

        XCTAssertEqual(semanticOutput.livePrimaryTip?.tipType, .createLookSpaceRight)
        XCTAssertEqual(semanticOutput.livePrimaryTip?.actionType, .shiftFrameRight)
        XCTAssertEqual(semanticOutput.livePrimaryTip?.liveText, "Смести камеру чуть правее.")

        await MainActor.run {
            pipeline.testingPublishLivePresentation(
                frameId: critique.frameId,
                critique: critique,
                plan: plan,
                semantics: semantics,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: Date(timeIntervalSince1970: 1_772_000_100)
            )
        }

        await MainActor.run {
            XCTAssertNil(pipeline.currentLiveHint)
        }
    }

    func testPipelineLivePresentationSuppressesGenericObjectSemanticFallback() async {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let critique = makeCritique(
            frameId: "pipeline-object-fallback",
            mode: .live,
            verdict: .mixed,
            issues: [
                FrameIssue(
                    id: "issue-object-edge",
                    type: .subjectTooCloseToEdge,
                    severity: 0.90,
                    confidence: 0.88,
                    rationale: "Главный объект зажат у края.",
                    evidence: [EvidenceRef(source: .semantics, key: "readability.edgePressureScore", value: "0.75", confidence: 0.75)],
                    affectedRegion: NormalizedRect(x: 0.72, y: 0.22, width: 0.20, height: 0.22),
                    suggestedFixTypes: [.reframing]
                )
            ]
        )
        let plan = RecommendationPlan(
            frameId: critique.frameId,
            mode: .live,
            inputVerdict: critique.verdict,
            primaryAction: RecommendationAction(
                id: "action-edge-right",
                actionType: .moveFrameRight,
                priority: 1,
                targetRegion: NormalizedRect(x: 0.72, y: 0.22, width: 0.20, height: 0.22),
                linkedIssueIds: ["issue-object-edge"],
                expectedOutcome: "Передвинь предмет левее в превью.",
                guardrail: ActionGuardrail(requiresStillCamera: false, minConfidence: 0.4, suppressWhenMoving: false),
                overlayHint: nil
            ),
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.88
        )
        let semantics = makeSemantics(frameId: critique.frameId, mode: .live, subjectKind: .object)
        let semanticOutput = planner.plan(
            input: SemanticTipPlannerInput(
                frameId: critique.frameId,
                mode: .live,
                critique: critique,
                recommendationPlan: plan,
                semantics: semantics
            )
        )

        XCTAssertEqual(semanticOutput.livePrimaryTip?.tipType, .moveObjectOffRightEdge)
        XCTAssertEqual(semanticOutput.livePrimaryTip?.actionType, .moveObjectLeft)
        XCTAssertEqual(semanticOutput.livePrimaryTip?.liveText, "Передвинь предмет левее в превью.")
        XCTAssertTrue(semanticOutput.fallbackUsed)

        await MainActor.run {
            pipeline.testingPublishLivePresentation(
                frameId: critique.frameId,
                critique: critique,
                plan: plan,
                semantics: semantics,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: Date(timeIntervalSince1970: 1_772_000_200)
            )
        }

        await MainActor.run {
            XCTAssertNil(pipeline.currentLiveHint)
        }
    }

    func testLiveCoachQualityGateAcceptsFreshGroundedSingleSubject() {
        let fixture = makeLiveProductionFixture()

        XCTAssertTrue(LiveCoachQualityGate.allows(
            action: .moveFrameLeft,
            mode: .live,
            snapshot: fixture.snapshot,
            semantics: fixture.semantics
        ))
        XCTAssertTrue(LiveCoachQualityGate.allows(
            action: .increaseSubjectSize,
            mode: .live,
            snapshot: fixture.snapshot,
            semantics: fixture.semantics
        ))
    }

    func testLiveCoachQualityGateRejectsStaleOrUnavailableVision() {
        let semantics = makeLiveCoachSemantics()
        let staleSnapshot = makeLiveCoachSnapshot(
            vision: .init(
                available: true,
                freshnessMs: LiveCoachQualityGate.maxVisionFreshnessMilliseconds + 1,
                confidence: 0.90
            )
        )
        let unavailableSnapshot = makeLiveCoachSnapshot(vision: .init(available: false))

        XCTAssertFalse(LiveCoachQualityGate.allows(
            action: .moveFrameRight,
            mode: .live,
            snapshot: staleSnapshot,
            semantics: semantics
        ))
        XCTAssertFalse(LiveCoachQualityGate.allows(
            action: .moveFrameRight,
            mode: .live,
            snapshot: unavailableSnapshot,
            semantics: semantics
        ))
    }

    func testLiveCoachQualityGateRejectsAmbiguousOrUngroundedSubject() {
        let snapshot = makeLiveCoachSnapshot()
        let ambiguousSemantics = makeLiveCoachSemantics(ambiguities: [
            .init(
                type: .multipleSubjectsSimilarConfidence,
                note: "competing subjects",
                candidateIds: ["subject-a", "subject-b"]
            )
        ])
        let unknownSemantics = makeLiveCoachSemantics(
            primaryKind: .unknown,
            primaryRegion: nil,
            primaryConfidence: 0
        )

        XCTAssertFalse(LiveCoachQualityGate.allows(
            action: .moveFrameDown,
            mode: .live,
            snapshot: snapshot,
            semantics: ambiguousSemantics
        ))
        XCTAssertFalse(LiveCoachQualityGate.allows(
            action: .moveFrameDown,
            mode: .live,
            snapshot: snapshot,
            semantics: unknownSemantics
        ))
    }

    func testLiveCoachQualityGateRejectsAnySemanticAmbiguityForSpatialAction() {
        let snapshot = makeLiveCoachSnapshot()
        let sceneTypeTieSemantics = makeLiveCoachSemantics(ambiguities: [
            .init(type: .sceneTypeTie, note: "scene tie", candidateIds: ["scene-a", "scene-b"])
        ])
        let weakSignalSemantics = makeLiveCoachSemantics(ambiguities: [
            .init(type: .weakSignal, note: "weak signal", candidateIds: [])
        ])

        XCTAssertFalse(LiveCoachQualityGate.allows(
            action: .moveFrameLeft,
            mode: .live,
            snapshot: snapshot,
            semantics: sceneTypeTieSemantics
        ))
        XCTAssertFalse(LiveCoachQualityGate.allows(
            action: .moveFrameLeft,
            mode: .live,
            snapshot: snapshot,
            semantics: weakSignalSemantics
        ))
    }

    func testLiveCoachQualityGateRejectsContextualSpatialIntentHiddenByNonSpatialAction() {
        let semantics = makeLiveCoachSemantics()
        let staleSnapshot = makeLiveCoachSnapshot(
            vision: .init(
                available: true,
                freshnessMs: LiveCoachQualityGate.maxVisionFreshnessMilliseconds + 1,
                confidence: 0.90
            )
        )

        XCTAssertFalse(LiveCoachQualityGate.allows(
            action: .changeAngle,
            semanticActionTypes: [.shiftFrameLeft],
            mode: .live,
            snapshot: staleSnapshot,
            semantics: semantics
        ))
        XCTAssertFalse(LiveCoachQualityGate.allows(
            action: .reduceBackgroundDistractions,
            semanticActionTypes: [.stepCloser],
            mode: .live,
            snapshot: staleSnapshot,
            semantics: semantics
        ))
    }

    func testLiveCoachQualityGateRejectsSceneObjectMoveWithoutGroundedLiveEvidence() {
        let semantics = makeLiveCoachSemantics()
        let staleSnapshot = makeLiveCoachSnapshot(
            vision: .init(
                available: true,
                freshnessMs: LiveCoachQualityGate.maxVisionFreshnessMilliseconds + 1,
                confidence: 0.90
            ),
            objectCount: 1,
            objectLabels: ["lamp"]
        )
        let unavailableSnapshot = makeLiveCoachSnapshot(
            vision: .init(available: false),
            objectCount: 1,
            objectLabels: ["lamp"]
        )

        XCTAssertFalse(LiveCoachQualityGate.allows(
            action: .reduceBackgroundDistractions,
            semanticActionTypes: [.moveObjectLeft],
            mode: .live,
            snapshot: staleSnapshot,
            semantics: semantics, objectTrackingGeometryStatus: .unclipped
        ))
        XCTAssertFalse(LiveCoachQualityGate.allows(
            action: .reduceBackgroundDistractions,
            semanticActionTypes: [.repositionPropForBalance],
            mode: .live,
            snapshot: unavailableSnapshot,
            semantics: semantics, objectTrackingGeometryStatus: .unclipped
        ))
    }

    func testLiveCoachQualityGateRejectsObjectMoveWithoutDetectedObjectButKeepsSubjectMove() {
        let semantics = makeLiveCoachSemantics()
        let groundedSnapshotWithoutObjects = makeLiveCoachSnapshot()

        XCTAssertFalse(LiveCoachQualityGate.allows(
            action: .reduceBackgroundDistractions,
            semanticActionTypes: [.moveObjectRight],
            mode: .live,
            snapshot: groundedSnapshotWithoutObjects,
            semantics: semantics, objectTrackingGeometryStatus: .unclipped
        ))
        XCTAssertFalse(LiveCoachQualityGate.allows(
            action: .reduceBackgroundDistractions,
            semanticActionTypes: [.removeDistractingObject],
            mode: .live,
            snapshot: groundedSnapshotWithoutObjects,
            semantics: semantics, objectTrackingGeometryStatus: .unclipped
        ))
        XCTAssertTrue(LiveCoachQualityGate.allows(
            action: .reduceBackgroundDistractions,
            semanticActionTypes: [.moveObjectRight],
            mode: .live,
            snapshot: makeLiveCoachSnapshot(objectCount: 2, objectLabels: ["lamp", "vase"]),
            semantics: semantics, objectTrackingGeometryStatus: .unclipped
        ))
    }

    /// CC-O02/O05: two tracked instances whose regions overlap make an
    /// object-targeted move ambiguous — the advice cannot ground itself to one
    /// of the two lamps. The gate must withhold the object-scoped correction
    /// while frame-global corrections stay actionable.
    /// A selected object is not automatically the semantic action's target;
    /// overlap remains withheld until that exact typed binding exists.
    func testLiveCoachQualityGateKeepsOverlapFenceAfterAValidObjectTap() throws {
        let semantics = makeLiveCoachSemantics()
        let groundedSnapshot = makeLiveCoachSnapshot(objectCount: 2, objectLabels: ["lamp", "lamp"])
        let now = Date()
        let tracker = SubjectTracker()
        let frame = try XCTUnwrap(tracker.acceptObjectFrame(
            candidates: [SubjectCandidate(
                id: "lamp", kind: .object, label: "lamp",
                region: NormalizedRect(x: 0.1, y: 0.2, width: 0.2, height: 0.3),
                confidence: 0.95
            )],
            frameID: groundedSnapshot.frameId, generation: 7, sampleSequence: 1, capturedAt: now
        ))
        XCTAssertNotNil(SceneTapEvidence(sceneX: 0.2, sceneY: 0.3, frame: frame, now: now))
        // Selection alone carries no binding to the evaluated semantic action.
        XCTAssertFalse(LiveCoachQualityGate.allows(
            action: .reduceBackgroundDistractions, semanticActionTypes: [.moveObjectRight],
            mode: .live, snapshot: groundedSnapshot, semantics: semantics,
            overlappingInstancePairCount: 1, objectTrackingGeometryStatus: .unclipped
        ))
        // The equivalent eligible object move remains useful without overlap.
        XCTAssertTrue(LiveCoachQualityGate.allows(
            action: .reduceBackgroundDistractions, semanticActionTypes: [.moveObjectRight],
            mode: .live, snapshot: groundedSnapshot, semantics: semantics,
            overlappingInstancePairCount: 0, objectTrackingGeometryStatus: .unclipped
        ))
        XCTAssertTrue(LiveCoachQualityGate.allows(
            action: .changeAngle, mode: .live, snapshot: groundedSnapshot,
            semantics: semantics, overlappingInstancePairCount: 1
        ))
    }

    func testRegistryTapAccessorResolvesNearestTrackedInstance() {
        var registry = SubjectIdentityRegistry(generation: 7)
        let observations = [
            SubjectIdentityObservation(
                region: NormalizedRect(x: 0.05, y: 0.05, width: 0.10, height: 0.10),
                confidence: 0.9,
                label: "lamp"
            ),
            SubjectIdentityObservation(
                region: NormalizedRect(x: 0.75, y: 0.60, width: 0.12, height: 0.14),
                confidence: 0.9,
                label: "vase"
            ),
        ]
        let events = registry.observe(detections: observations, frameId: "frame-tap-1")

        // Tap inside the second instance's region resolves to a tracked
        // instance whose region contains the tap.
        let hit = registry.instance(atSceneX: 0.80, y: 0.66, frameId: "frame-tap-1", generation: 7)
        XCTAssertNotNil(hit)
        if let hit {
            XCTAssertTrue(hit.region.x <= 0.80 && 0.80 <= hit.region.x + hit.region.width)
            XCTAssertTrue(hit.region.y <= 0.66 && 0.66 <= hit.region.y + hit.region.height)
        }

        // Tap far from every instance resolves to nothing.
        XCTAssertNil(registry.instance(atSceneX: 0.45, y: 0.45, frameId: "frame-tap-1", generation: 7))
    }

    func testLiveCoachQualityGateRejectsObjectMoveWhenTrackedInstancesOverlap() {
        let semantics = makeLiveCoachSemantics()
        let groundedSnapshot = makeLiveCoachSnapshot(objectCount: 2, objectLabels: ["lamp", "lamp"])

        XCTAssertTrue(LiveCoachQualityGate.allows(
            action: .reduceBackgroundDistractions,
            semanticActionTypes: [.moveObjectRight],
            mode: .live,
            snapshot: groundedSnapshot,
            semantics: semantics, objectTrackingGeometryStatus: .unclipped
        ))

        XCTAssertFalse(LiveCoachQualityGate.allows(
            action: .reduceBackgroundDistractions,
            semanticActionTypes: [.moveObjectRight],
            mode: .live,
            snapshot: groundedSnapshot,
            semantics: semantics,
            overlappingInstancePairCount: 1, objectTrackingGeometryStatus: .unclipped
        ))
        XCTAssertFalse(LiveCoachQualityGate.allows(
            action: .reduceBackgroundDistractions,
            semanticActionTypes: [.removeDistractingObject],
            mode: .live,
            snapshot: groundedSnapshot,
            semantics: semantics,
            overlappingInstancePairCount: 2, objectTrackingGeometryStatus: .unclipped
        ))

        // Frame-global corrections remain actionable: the ambiguity is about
        // which instance, not about the frame.
        XCTAssertTrue(LiveCoachQualityGate.allows(
            action: .changeAngle,
            mode: .live,
            snapshot: groundedSnapshot,
            semantics: semantics,
            overlappingInstancePairCount: 1
        ))

        // No evidence yet (nil) must not suppress: absence of evidence is not
        // evidence of overlap.
        XCTAssertTrue(LiveCoachQualityGate.allows(
            action: .reduceBackgroundDistractions,
            semanticActionTypes: [.moveObjectRight],
            mode: .live,
            snapshot: groundedSnapshot,
            semantics: semantics,
            overlappingInstancePairCount: nil, objectTrackingGeometryStatus: .unclipped
        ))
    }

    func testLiveCoachObjectMovesRequireCompleteObservationCoverageEvenWithoutOverlap() {
        let semantics = makeLiveCoachSemantics()
        let snapshot = makeLiveCoachSnapshot(objectCount: 2, objectLabels: ["lamp", "vase"])
        let objectMoves: [SemanticActionType] = [
            .moveObjectLeft, .moveObjectRight, .moveObjectForward, .moveObjectBack,
            .removeDistractingObject, .repositionPropForBalance
        ]
        let coverageCases: [(ObjectObservationCoverage, Bool)] = [
            (.complete, true), (.partial, false), (.unavailable, false)
        ]

        // Every case has fresh, matching, strong evidence and zero overlapping
        // pairs. Only coverage changes; the complete positive proves the
        // object action is otherwise eligible under the existing gate.
        for move in objectMoves {
            for (coverage, expected) in coverageCases {
                XCTAssertEqual(LiveCoachQualityGate.allows(
                    action: .reduceBackgroundDistractions,
                    semanticActionTypes: [move], mode: .live,
                    snapshot: snapshot, semantics: semantics,
                    overlappingInstancePairCount: 0,
                    objectObservationCoverage: coverage, objectTrackingGeometryStatus: .unclipped
                ), expected, "\(move) with \(coverage) observation coverage")
            }
        }
    }

    func testLiveCoachFrameGlobalSpatialAdviceKeepsExistingGroundingAcrossCoverageStates() {
        let semantics = makeLiveCoachSemantics()
        let snapshot = makeLiveCoachSnapshot(objectCount: 2, objectLabels: ["lamp", "vase"])
        let staleSnapshot = makeLiveCoachSnapshot(
            vision: .init(available: true,
                          freshnessMs: LiveCoachQualityGate.maxVisionFreshnessMilliseconds + 1,
                          confidence: 0.88),
            objectCount: 2, objectLabels: ["lamp", "vase"]
        )
        let coverageStates: [ObjectObservationCoverage] = [.complete, .partial, .unavailable]
        for coverage in coverageStates {
            XCTAssertTrue(LiveCoachQualityGate.allows(
                action: .moveFrameLeft, semanticActionTypes: [.shiftFrameLeft], mode: .live,
                snapshot: snapshot, semantics: semantics,
                overlappingInstancePairCount: 0, objectObservationCoverage: coverage
            ), "Frame-wide correction remains eligible with \(coverage) object coverage")
            XCTAssertFalse(LiveCoachQualityGate.allows(
                action: .moveFrameLeft, semanticActionTypes: [.shiftFrameLeft], mode: .live,
                snapshot: staleSnapshot, semantics: semantics,
                overlappingInstancePairCount: 0, objectObservationCoverage: coverage
            ), "Coverage must not bypass the existing fresh-evidence requirement")
        }
    }

    func testClippedGeometryBlocksObjectMovesSeparatelyFromCoverageButKeepsFramingEligible() {
        let semantics = makeLiveCoachSemantics()
        let snapshot = makeLiveCoachSnapshot(objectCount: 1, objectLabels: ["lamp"])
        let moves: [SemanticActionType] = [.moveObjectLeft, .moveObjectRight, .moveObjectForward,
            .moveObjectBack, .removeDistractingObject, .repositionPropForBalance]
        for status in [ObjectTrackingGeometryStatus.unclipped, .clipped, .unavailable] {
            for move in moves {
                XCTAssertEqual(LiveCoachQualityGate.allows(action: .reduceBackgroundDistractions,
                    semanticActionTypes: [move], mode: .live, snapshot: snapshot, semantics: semantics,
                    overlappingInstancePairCount: 0, objectObservationCoverage: .complete,
                    objectTrackingGeometryStatus: status), status == .unclipped)
            }
            XCTAssertTrue(LiveCoachQualityGate.allows(action: .moveFrameLeft,
                semanticActionTypes: [.shiftFrameLeft], mode: .live, snapshot: snapshot, semantics: semantics,
                overlappingInstancePairCount: 0, objectObservationCoverage: .complete,
                objectTrackingGeometryStatus: status))
        }
        XCTAssertFalse(LiveCoachQualityGate.allows(action: .reduceBackgroundDistractions,
            semanticActionTypes: [.moveObjectLeft], mode: .live, snapshot: snapshot, semantics: semantics,
            overlappingInstancePairCount: 0, objectObservationCoverage: .complete),
            "Omitted geometry metadata must not default to unclipped")
    }

    func testLiveCoachQualityGateKeepsSubjectMoveGroundedWithoutObjectPresenceRequirement() {
        let semantics = makeLiveCoachSemantics()
        let staleSnapshot = makeLiveCoachSnapshot(
            vision: .init(
                available: true,
                freshnessMs: LiveCoachQualityGate.maxVisionFreshnessMilliseconds + 1,
                confidence: 0.90
            )
        )
        let groundedSnapshotWithoutObjects = makeLiveCoachSnapshot()

        XCTAssertFalse(LiveCoachQualityGate.allows(
            action: .reduceBackgroundDistractions,
            semanticActionTypes: [.moveSubjectLeft],
            mode: .live,
            snapshot: staleSnapshot,
            semantics: semantics
        ))
        XCTAssertTrue(LiveCoachQualityGate.allows(
            action: .reduceBackgroundDistractions,
            semanticActionTypes: [.moveSubjectLeft],
            mode: .live,
            snapshot: groundedSnapshotWithoutObjects,
            semantics: semantics
        ))
    }

    func testLiveCoachQualityGateRejectsUngroundedOrStaleContextualStepBack() {
        let groundedSemantics = makeLiveCoachSemantics()
        let staleSnapshot = makeLiveCoachSnapshot(
            vision: .init(
                available: true,
                freshnessMs: LiveCoachQualityGate.maxVisionFreshnessMilliseconds + 1,
                confidence: 0.90
            )
        )
        XCTAssertFalse(LiveCoachQualityGate.allows(
            action: .changeAngle,
            semanticActionTypes: [.stepBack],
            mode: .live,
            snapshot: staleSnapshot,
            semantics: groundedSemantics
        ))

        let ungroundedSemantics = makeLiveCoachSemantics(
            primaryKind: .unknown,
            primaryRegion: nil,
            primaryConfidence: 0
        )
        XCTAssertFalse(LiveCoachQualityGate.allows(
            action: .changeAngle,
            semanticActionTypes: [.stepBack],
            mode: .live,
            snapshot: makeLiveCoachSnapshot(),
            semantics: ungroundedSemantics
        ))

        XCTAssertTrue(LiveCoachQualityGate.allows(
            action: .changeAngle,
            semanticActionTypes: [.stepBack],
            mode: .live,
            snapshot: makeLiveCoachSnapshot(),
            semantics: groundedSemantics
        ))
    }

    func testLiveCoachQualityGateRejectsMismatchedPrimaryRegions() {
        let snapshot = makeLiveCoachSnapshot(
            primaryRegion: .init(x: 0.70, y: 0.16, width: 0.20, height: 0.30)
        )
        let semantics = makeLiveCoachSemantics(
            primaryRegion: .init(x: 0.05, y: 0.16, width: 0.20, height: 0.30)
        )

        XCTAssertFalse(LiveCoachQualityGate.allows(
            action: .moveFrameLeft,
            mode: .live,
            snapshot: snapshot,
            semantics: semantics
        ))
    }

    func testPipelineLivePresentationEmitsOnlyFreshGroundedDirectionalAction() async {
        let fixture = makeLiveProductionFixture()
        let frameId = fixture.snapshot.frameId
        let firstFreshSnapshot = fixture.snapshot
        let secondFreshSnapshot = makeLiveProductionFixture(
            capturedAt: fixture.snapshot.capturedAt.addingTimeInterval(0.1)
        ).snapshot
        let thirdFreshSnapshot = makeLiveProductionFixture(
            capturedAt: fixture.snapshot.capturedAt.addingTimeInterval(0.2)
        ).snapshot

        let freshPipeline = AnalysisPipeline(reasoningProvider: nil)
        await MainActor.run {
            freshPipeline.testingPublishLivePresentation(
                frameId: frameId,
                snapshot: firstFreshSnapshot,
                critique: fixture.critique,
                plan: fixture.plan,
                semantics: fixture.semantics,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: Date(timeIntervalSince1970: 1_772_000_300)
            )
            XCTAssertNil(freshPipeline.currentLiveHint)
            freshPipeline.testingPublishLivePresentation(
                frameId: frameId,
                snapshot: secondFreshSnapshot,
                critique: fixture.critique,
                plan: fixture.plan,
                semantics: fixture.semantics,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: Date(timeIntervalSince1970: 1_772_000_300.1)
            )
            XCTAssertNil(freshPipeline.currentLiveHint)
            freshPipeline.testingPublishLivePresentation(
                frameId: frameId,
                snapshot: thirdFreshSnapshot,
                critique: fixture.critique,
                plan: fixture.plan,
                semantics: fixture.semantics,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: Date(timeIntervalSince1970: 1_772_000_300.2)
            )
            XCTAssertEqual(freshPipeline.currentLiveHint?.actionType, .moveFrameLeft)
        }

        let stalePipeline = AnalysisPipeline(reasoningProvider: nil)
        let staleSnapshot = makeLiveCoachSnapshot(
            vision: .init(
                available: true,
                freshnessMs: LiveCoachQualityGate.maxVisionFreshnessMilliseconds + 1,
                confidence: 0.90
            )
        )
        await MainActor.run {
            stalePipeline.testingPublishLivePresentation(
                frameId: frameId,
                snapshot: staleSnapshot,
                critique: fixture.critique,
                plan: fixture.plan,
                semantics: fixture.semantics,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: Date(timeIntervalSince1970: 1_772_000_300)
            )
            XCTAssertNil(stalePipeline.currentLiveHint)
        }

        let ambiguousPipeline = AnalysisPipeline(reasoningProvider: nil)
        let ambiguousSemantics = makeLiveCoachSemantics(ambiguities: [
            .init(
                type: .multipleSubjectsSimilarConfidence,
                note: "competing subjects",
                candidateIds: ["subject-a", "subject-b"]
            )
        ])
        await MainActor.run {
            ambiguousPipeline.testingPublishLivePresentation(
                frameId: frameId,
                snapshot: firstFreshSnapshot,
                critique: fixture.critique,
                plan: fixture.plan,
                semantics: ambiguousSemantics,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: Date(timeIntervalSince1970: 1_772_000_300)
            )
            XCTAssertNil(ambiguousPipeline.currentLiveHint)
        }
    }

    func testPipelineRejectsStaleOrMismatchedSecondarySpatialSemanticTip() async {
        let fixture = makeLiveProductionFixture()
        let frameId = fixture.snapshot.frameId
        let semanticTip = planner.plan(
            input: SemanticTipPlannerInput(
                frameId: frameId,
                mode: .live,
                critique: fixture.critique,
                recommendationPlan: fixture.plan,
                semantics: fixture.semantics
            )
        ).livePrimaryTip
        XCTAssertNotNil(semanticTip)

        let staleSnapshot = makeLiveCoachSnapshot(
            vision: .init(
                available: true,
                freshnessMs: LiveCoachQualityGate.maxVisionFreshnessMilliseconds + 1,
                confidence: 0.90
            )
        )
        let stalePipeline = AnalysisPipeline(reasoningProvider: nil)
        await MainActor.run {
            stalePipeline.testingPublishLivePresentation(
                frameId: frameId,
                snapshot: staleSnapshot,
                critique: fixture.critique,
                plan: fixture.plan,
                semantics: fixture.semantics,
                legacySuggestion: nil,
                structuredAvailable: true
            )
            XCTAssertNil(stalePipeline.currentLiveHint)
        }

        let mismatchedSnapshot = makeLiveCoachSnapshot(
            primaryRegion: .init(x: 0.70, y: 0.16, width: 0.20, height: 0.30)
        )
        let mismatchedPipeline = AnalysisPipeline(reasoningProvider: nil)
        await MainActor.run {
            mismatchedPipeline.testingPublishLivePresentation(
                frameId: frameId,
                snapshot: mismatchedSnapshot,
                critique: fixture.critique,
                plan: fixture.plan,
                semantics: fixture.semantics,
                legacySuggestion: nil,
                structuredAvailable: true
            )
            XCTAssertNil(mismatchedPipeline.currentLiveHint)
        }
    }

    func testPipelineDoesNotPublishStaleSpatialDemoHint() async {
        let frameId = "live-quality"
        let edgeRegion = NormalizedRect(x: 0.01, y: 0.16, width: 0.34, height: 0.48)
        let snapshot = makeLiveCoachSnapshot(
            vision: .init(
                available: true,
                freshnessMs: LiveCoachQualityGate.maxVisionFreshnessMilliseconds + 1,
                confidence: 0.90
            ),
            primaryRegion: edgeRegion
        )
        let semantics = makeLiveCoachSemantics(primaryRegion: edgeRegion)
        let critique = makeCritique(frameId: frameId, mode: .live, verdict: .mixed, issues: [])
        let plan = RecommendationPlan(
            frameId: frameId,
            mode: .live,
            inputVerdict: .mixed,
            primaryAction: nil,
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0
        )
        let pipeline = AnalysisPipeline(reasoningProvider: nil, demoLiveCoachEnabled: true)
        await MainActor.run {
            pipeline.setCameraDemoSceneMode(.portrait)
            pipeline.testingPublishLivePresentation(
                frameId: frameId,
                snapshot: snapshot,
                critique: critique,
                plan: plan,
                semantics: semantics,
                legacySuggestion: nil,
                structuredAvailable: true
            )
            XCTAssertNil(pipeline.currentLiveHint)
        }
    }

    private func makeCritique(frameId: String,
                              mode: AnalysisMode,
                              verdict: FrameVerdict,
                              issues: [FrameIssue]) -> CritiqueReport {
        CritiqueReport(
            frameId: frameId,
            mode: mode,
            verdict: verdict,
            verdictConfidence: 0.82,
            strengths: [],
            issues: issues,
            summary: CritiqueSummary(
                id: "summary-\(frameId)",
                shortVerdict: verdict == .good ? "Кадр уже читается хорошо." : "Кадр требует правки.",
                whyGood: verdict == .good ? "Кадр выглядит устойчиво." : nil,
                whyProblematic: verdict == .good ? nil : issues.first?.rationale
            ),
            traceRefs: ["trace-\(frameId)-summary", "trace-\(frameId)-issue"],
            fallbackUsed: false
        )
    }

    private func makeSemantics(frameId: String,
                               mode: AnalysisMode,
                               subjectKind: SubjectKind) -> SceneSemanticsReport {
        SceneSemanticsReport(
            frameId: frameId,
            mode: mode,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.82,
            primarySubject: .init(
                kind: subjectKind,
                label: subjectKind == .object ? "object" : "person",
                region: NormalizedRect(x: 0.24, y: 0.16, width: 0.30, height: 0.44),
                confidence: 0.88
            ),
            dominance: .init(hasClearFocus: false, focusCompetitionScore: 0.58, backgroundClutterScore: 0.52),
            readability: .init(subjectReadable: true, lookSpaceAdequate: false, edgePressureScore: 0.71, separationScore: 0.48),
            ambiguities: [],
            assumptions: []
        )
    }

    private func makeLiveCoachSnapshot(
        vision: SourceState = .init(available: true, freshnessMs: 80, confidence: 0.88),
        primaryRegion: NormalizedRect? = .init(x: 0.22, y: 0.16, width: 0.34, height: 0.48),
        primaryConfidence: Double? = 0.86,
        capturedAt: Date = Date(timeIntervalSince1970: 1_772_000_300),
        objectCount: Int = 0,
        objectLabels: [String] = []
    ) -> FrameFeatureSnapshot {
        FrameFeatureSnapshot(
            frameId: "live-quality",
            mode: .live,
            capturedAt: capturedAt,
            sources: .init(
                vision: vision,
                horizon: .init(available: false),
                lighting: .init(available: false),
                detr: .init(available: false),
                aesthetic: .init(available: false)
            ),
            composition: .init(
                horizontalOffset: 0,
                verticalOffset: 0,
                subjectAreaRatio: 0.16,
                saliencyLeftRightBalance: 0,
                saliencyTopBottomBalance: 0
            ),
            subjectSignals: .init(
                faceDetected: false,
                personDetected: true,
                personCount: 1,
                primaryCandidateRegion: primaryRegion,
                primaryCandidateConfidence: primaryConfidence
            ),
            horizon: .init(angleDegrees: 0, confidence: 0),
            lighting: .init(exposureBiasHint: 0, backlightIndex: 0, keyToFillRatio: nil),
            motion: .init(state: .still, shakeLevel: 0),
            aesthetics: .init(),
            objects: .init(totalCount: objectCount, topKLabels: objectLabels),
            technicalFlags: []
        )
    }

    private func makeLiveCoachSemantics(
        primaryKind: SubjectKind = .person,
        primaryRegion: NormalizedRect? = .init(x: 0.22, y: 0.16, width: 0.34, height: 0.48),
        primaryConfidence: Double = 0.86,
        ambiguities: [SemanticsAmbiguity] = []
    ) -> SceneSemanticsReport {
        SceneSemanticsReport(
            frameId: "live-quality",
            mode: .live,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.88,
            primarySubject: .init(
                kind: primaryKind,
                label: primaryKind == .unknown ? nil : "person",
                region: primaryRegion,
                confidence: primaryConfidence
            ),
            dominance: .init(hasClearFocus: true, focusCompetitionScore: 0.12, backgroundClutterScore: 0.10),
            readability: .init(subjectReadable: true, lookSpaceAdequate: true, edgePressureScore: 0.10, separationScore: 0.82),
            ambiguities: ambiguities,
            assumptions: []
        )
    }

    private func makeLiveProductionFixture(
        capturedAt: Date = Date(timeIntervalSince1970: 1_772_000_300)
    ) -> LiveProductionFixture {
        let region = CGRect(x: 0.0, y: 0.20, width: 0.20, height: 0.45)
        let vision = FeatureSample(
            value: FeatureSnapshotVisionPayload(
                subjects: [
                    .init(boundingBox: region, confidence: 0.92, isFace: true)
                ],
                saliencyCenter: CGPoint(x: region.midX, y: region.midY),
                faceCount: 1,
                personCount: 1
            ),
            measuredAt: capturedAt,
            baseConfidence: 0.92
        )
        let input = FeatureAggregationInput(
            frameId: "live-quality",
            mode: .live,
            capturedAt: capturedAt,
            evaluatedAt: capturedAt,
            motionState: .still,
            shakeLevel: 0,
            vision: vision,
            horizon: FeatureSample(
                value: .init(angleDegrees: 0.2, confidence: 0.90),
                measuredAt: capturedAt,
                baseConfidence: 0.90
            ),
            lighting: FeatureSample(
                value: .init(exposureBiasHint: 0.1, backlightIndex: 0.1, keyToFillRatio: 1.0),
                measuredAt: capturedAt,
                baseConfidence: 0.90
            ),
            detr: nil,
            aesthetic: FeatureSample(
                value: .init(score10: 7.0),
                measuredAt: capturedAt,
                baseConfidence: 0.90
            )
        )
        let snapshot = FeatureSnapshotAggregator().makeSnapshot(from: input)
        let semantics = SceneSemanticsAnalyzer().analyze(snapshot: snapshot)
        let critique = FrameCritiqueEngine().analyze(snapshot: snapshot, semantics: semantics)
        let plan = RecommendationPlanner().makePlan(snapshot: snapshot, critique: critique)
        return LiveProductionFixture(
            snapshot: snapshot,
            semantics: semantics,
            critique: critique,
            plan: plan
        )
    }
}
