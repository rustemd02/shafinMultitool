import XCTest
@testable import shafinMultitool

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
                id: "action-edge-left",
                actionType: .moveFrameLeft,
                priority: 1,
                targetRegion: NormalizedRect(x: 0.72, y: 0.22, width: 0.20, height: 0.22),
                linkedIssueIds: ["issue-object-edge"],
                expectedOutcome: "Сдвинь предмет левее.",
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
        XCTAssertEqual(primary.targetEntityDisplayLabel, "предмет")
        XCTAssertNil(primary.targetEntityRef)
        XCTAssertTrue(output.fallbackUsed)
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

    func testPipelineLivePresentationUsesSemanticTipCopy() async {
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
                id: "action-left",
                actionType: .moveFrameLeft,
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

        await MainActor.run {
            pipeline.testingPublishLivePresentation(
                frameId: critique.frameId,
                critique: critique,
                plan: plan,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: Date(timeIntervalSince1970: 1_772_000_100)
            )
        }

        await MainActor.run {
            XCTAssertEqual(pipeline.currentLiveHint?.text, "Смести камеру чуть левее.")
            XCTAssertEqual(pipeline.currentLiveHint?.actionType, .moveFrameLeft)
        }
    }

    func testPipelineLivePresentationMarksSemanticFallbackForGenericObjectTip() async {
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
                id: "action-edge-left",
                actionType: .moveFrameLeft,
                priority: 1,
                targetRegion: NormalizedRect(x: 0.72, y: 0.22, width: 0.20, height: 0.22),
                linkedIssueIds: ["issue-object-edge"],
                expectedOutcome: "Сдвинь предмет левее.",
                guardrail: ActionGuardrail(requiresStillCamera: false, minConfidence: 0.4, suppressWhenMoving: false),
                overlayHint: nil
            ),
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.88
        )

        await MainActor.run {
            pipeline.testingPublishLivePresentation(
                frameId: critique.frameId,
                critique: critique,
                plan: plan,
                semantics: makeSemantics(frameId: critique.frameId, mode: .live, subjectKind: .object),
                legacySuggestion: nil,
                structuredAvailable: true,
                now: Date(timeIntervalSince1970: 1_772_000_200)
            )
        }

        await MainActor.run {
            XCTAssertEqual(pipeline.currentLiveHint?.text, "Сдвинь предмет левее.")
            XCTAssertEqual(pipeline.currentLiveHint?.actionType, .moveFrameLeft)
            XCTAssertEqual(pipeline.currentLiveHint?.isFallback, true)
            XCTAssertEqual(pipeline.currentLiveHint?.expandedVerdict?.fallbackUsed, true)
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
}
