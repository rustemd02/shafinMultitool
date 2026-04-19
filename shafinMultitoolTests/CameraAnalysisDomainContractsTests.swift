import XCTest
import CoreGraphics
@testable import shafinMultitool

final class CameraAnalysisDomainContractsTests: XCTestCase {

    func testFrameFeatureSnapshotClampsNormalizedRanges() {
        let snapshot = makeSnapshot(
            composition: .init(
                horizontalOffset: 2.0,
                verticalOffset: -3.0,
                subjectAreaRatio: 2.5,
                saliencyLeftRightBalance: -5.0,
                saliencyTopBottomBalance: 7.0
            ),
            lighting: .init(exposureBiasHint: -0.2, backlightIndex: 3.0, keyToFillRatio: nil),
            motion: .init(state: .still, shakeLevel: -1.0)
        )

        XCTAssertEqual(snapshot.composition.horizontalOffset, 1.0)
        XCTAssertEqual(snapshot.composition.verticalOffset, -1.0)
        XCTAssertEqual(snapshot.composition.subjectAreaRatio, 1.0)
        XCTAssertEqual(snapshot.composition.saliencyLeftRightBalance, -1.0)
        XCTAssertEqual(snapshot.composition.saliencyTopBottomBalance, 1.0)
        XCTAssertEqual(snapshot.lighting.backlightIndex, 1.0)
        XCTAssertEqual(snapshot.motion.shakeLevel, 0.0)
    }

    func testFrameFeatureSnapshotInvariantsFaceImpliesPerson() {
        let snapshot = makeSnapshot(
            subjectSignals: .init(
                faceDetected: true,
                personDetected: false,
                personCount: 1,
                topObjectLabel: nil,
                topObjectConfidence: nil,
                primaryCandidateRegion: nil,
                primaryCandidateConfidence: nil
            )
        )

        XCTAssertTrue(snapshot.validate().contains("faceDetected implies personDetected"))
    }

    func testFrameFeatureSnapshotAllowsZeroPersonCountWhenFaceDetected() {
        let snapshot = makeSnapshot(
            subjectSignals: .init(
                faceDetected: true,
                personDetected: true,
                personCount: 0,
                topObjectLabel: nil,
                topObjectConfidence: nil,
                primaryCandidateRegion: nil,
                primaryCandidateConfidence: nil
            )
        )

        XCTAssertFalse(snapshot.validate().contains("faceDetected requires personCount > 0"))
    }

    func testFrameFeatureSnapshotSupportsUnavailableSources() {
        let snapshot = FrameFeatureSnapshot(
            frameId: "f-unavailable",
            mode: .live,
            capturedAt: Date(timeIntervalSince1970: 1_768_001_234),
            sources: .init(
                vision: .init(available: true, freshnessMs: 20, confidence: 0.8),
                horizon: .init(available: true, freshnessMs: 30, confidence: 0.7),
                lighting: .init(available: true, freshnessMs: 45, confidence: 0.75),
                detr: .init(available: false),
                aesthetic: .init(available: false)
            ),
            composition: .init(
                horizontalOffset: 0.1,
                verticalOffset: 0.0,
                subjectAreaRatio: 0.0,
                saliencyLeftRightBalance: 0.0,
                saliencyTopBottomBalance: 0.0
            ),
            subjectSignals: .init(
                faceDetected: false,
                personDetected: false,
                personCount: 0
            ),
            horizon: .init(angleDegrees: 0.5, confidence: 0.72),
            lighting: .init(exposureBiasHint: 0.0, backlightIndex: 0.0, keyToFillRatio: nil),
            motion: .init(state: .moving, shakeLevel: 0.3),
            aesthetics: .init(score: nil, scoreConfidence: nil),
            objects: .init(totalCount: 0, topKLabels: []),
            technicalFlags: [.lowSubjectConfidence]
        )

        XCTAssertTrue(snapshot.validate().isEmpty)
    }

    func testSceneSemanticsSupportsUnknownSceneFallback() {
        let semantics = SceneSemanticsReport(
            frameId: "f-unknown",
            mode: .pause,
            sceneType: .unknown,
            sceneTypeConfidence: 0.19,
            primarySubject: .init(kind: .unknown, confidence: 0.1),
            dominance: .init(hasClearFocus: false, focusCompetitionScore: 0.72, backgroundClutterScore: 0.58),
            readability: .init(subjectReadable: false, lookSpaceAdequate: nil, edgePressureScore: 0.4, separationScore: 0.3),
            ambiguities: [],
            assumptions: []
        )

        XCTAssertTrue(semantics.validate(expectedFrameId: "f-unknown").isEmpty)
    }

    func testSceneSemanticsAmbiguityWithCloseCandidates() {
        let semantics = SceneSemanticsReport(
            frameId: "f-amb",
            mode: .pause,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.61,
            primarySubject: .init(
                kind: .person,
                label: "person",
                region: .init(x: 0.34, y: 0.2, width: 0.28, height: 0.5),
                confidence: 0.53,
                competingCandidates: [
                    .init(id: "cand-1", kind: .person, label: "person", region: .init(x: 0.34, y: 0.2, width: 0.28, height: 0.5), confidence: 0.53),
                    .init(id: "cand-2", kind: .object, label: "statue", region: .init(x: 0.62, y: 0.22, width: 0.22, height: 0.45), confidence: 0.51)
                ]
            ),
            dominance: .init(hasClearFocus: false, focusCompetitionScore: 0.66, backgroundClutterScore: 0.47),
            readability: .init(subjectReadable: true, lookSpaceAdequate: nil, edgePressureScore: 0.35, separationScore: 0.52),
            ambiguities: [
                .init(
                    type: .multipleSubjectsSimilarConfidence,
                    note: "Top candidates are close",
                    candidateIds: ["cand-1", "cand-2"]
                )
            ],
            assumptions: []
        )

        XCTAssertEqual(semantics.ambiguities.first?.candidateIds, ["cand-1", "cand-2"])
        XCTAssertTrue(semantics.validate(expectedFrameId: "f-amb").isEmpty)
    }

    func testSceneSemanticsRejectsClearFocusConflict() {
        let semantics = SceneSemanticsReport(
            frameId: "f-1",
            mode: .pause,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.8,
            primarySubject: .init(kind: .person, confidence: 0.9),
            dominance: .init(hasClearFocus: true, focusCompetitionScore: 0.95, backgroundClutterScore: 0.3),
            readability: .init(subjectReadable: true, lookSpaceAdequate: true, edgePressureScore: 0.2, separationScore: 0.8),
            ambiguities: [],
            assumptions: []
        )

        XCTAssertTrue(semantics.validate(expectedFrameId: "f-1").contains("hasClearFocus conflicts with focusCompetitionScore > 0.8"))
    }

    func testCritiqueRejectsGoodVerdictWithCriticalIssue() {
        let critique = CritiqueReport(
            frameId: "f-1",
            mode: .pause,
            verdict: .good,
            verdictConfidence: 0.7,
            strengths: [],
            issues: [
                .init(
                    id: "i1",
                    type: .horizonDistracts,
                    severity: 0.92,
                    confidence: 0.8,
                    rationale: "line tilt",
                    evidence: [EvidenceRef(source: .snapshot, key: "horizon.angle", value: "7.1")]
                )
            ],
            summary: .init(id: "summary-f1", shortVerdict: "good", whyGood: nil, whyProblematic: nil),
            traceRefs: ["t1"],
            fallbackUsed: false
        )

        XCTAssertTrue(critique.validate(expectedFrameId: "f-1").contains("good verdict cannot have critical issues"))
    }

    func testRecommendationPlanRejectsConflictsAndUnknownIssueLinks() {
        let actionLeft = RecommendationAction(
            id: "a1",
            actionType: .moveFrameLeft,
            priority: 1,
            targetRegion: nil,
            linkedIssueIds: ["i1"],
            expectedOutcome: "more look space",
            guardrail: .init(requiresStillCamera: true, minConfidence: 0.6, suppressWhenMoving: true),
            overlayHint: nil
        )

        let actionRight = RecommendationAction(
            id: "a2",
            actionType: .moveFrameRight,
            priority: 2,
            targetRegion: nil,
            linkedIssueIds: ["missing-id"],
            expectedOutcome: "counter move",
            guardrail: .init(requiresStillCamera: true, minConfidence: 0.6, suppressWhenMoving: true),
            overlayHint: nil
        )

        let plan = RecommendationPlan(
            frameId: "f-1",
            mode: .pause,
            inputVerdict: .needsFix,
            primaryAction: actionLeft,
            secondaryActions: [actionRight],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.9
        )

        let errors = plan.validate(expectedFrameId: "f-1", availableIssueIds: ["i1"])
        XCTAssertTrue(errors.contains("plan contains conflicting directional actions"))
        XCTAssertTrue(errors.contains(where: { $0.contains("plan links unknown issue IDs") }))
    }

    func testRecommendationPlanAlsoValidatesDeferredActions() {
        let primary = RecommendationAction(
            id: "a1",
            actionType: .moveFrameLeft,
            priority: 1,
            targetRegion: nil,
            linkedIssueIds: ["i1"],
            expectedOutcome: "left",
            guardrail: .init(requiresStillCamera: true, minConfidence: 0.6, suppressWhenMoving: true),
            overlayHint: nil
        )

        let deferred = RecommendationAction(
            id: "d1",
            actionType: .moveFrameRight,
            priority: 1,
            targetRegion: nil,
            linkedIssueIds: [],
            expectedOutcome: "right",
            guardrail: .init(requiresStillCamera: true, minConfidence: 0.6, suppressWhenMoving: true),
            overlayHint: nil
        )

        let plan = RecommendationPlan(
            frameId: "f-1",
            mode: .pause,
            inputVerdict: .needsFix,
            primaryAction: primary,
            secondaryActions: [],
            deferredActions: [deferred],
            noChangeRationale: nil,
            planConfidence: 0.8
        )

        let errors = plan.validate(expectedFrameId: "f-1", availableIssueIds: ["i1"])
        XCTAssertTrue(errors.contains("plan contains conflicting directional actions"))
        XCTAssertTrue(errors.contains("non-leave actions must link at least one issue"))
    }

    func testContractsCodableRoundTrip() throws {
        let snapshot = makeSnapshot()
        let semantics = makeSemantics(frameId: snapshot.frameId)
        let critique = makeCritique(frameId: snapshot.frameId)
        let plan = makePlan(frameId: snapshot.frameId)

        let payload = CameraAnalysisFixturePayload(
            snapshot: snapshot,
            semantics: semantics,
            critique: critique,
            plan: plan
        )

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(CameraAnalysisFixturePayload.self, from: data)

        XCTAssertEqual(decoded, payload)
        XCTAssertTrue(decoded.snapshot.validate().isEmpty)
        XCTAssertTrue(decoded.semantics.validate(expectedFrameId: decoded.snapshot.frameId).isEmpty)
        XCTAssertTrue(decoded.critique.validate(expectedFrameId: decoded.snapshot.frameId).isEmpty)
        XCTAssertTrue(decoded.plan.validate(expectedFrameId: decoded.snapshot.frameId,
                                            availableIssueIds: Set(decoded.critique.issues.map(\.id))).isEmpty)
    }
}

private struct CameraAnalysisFixturePayload: Codable, Equatable {
    let snapshot: FrameFeatureSnapshot
    let semantics: SceneSemanticsReport
    let critique: CritiqueReport
    let plan: RecommendationPlan
}

private extension CameraAnalysisDomainContractsTests {
    func makeSnapshot(
        composition: FrameFeatureSnapshot.CompositionFeatures = .init(
            horizontalOffset: 0.2,
            verticalOffset: -0.1,
            subjectAreaRatio: 0.22,
            saliencyLeftRightBalance: 0.1,
            saliencyTopBottomBalance: -0.05
        ),
        subjectSignals: FrameFeatureSnapshot.SubjectSignals = .init(
            faceDetected: true,
            personDetected: true,
            personCount: 1,
            topObjectLabel: "person",
            topObjectConfidence: 0.88,
            primaryCandidateRegion: .init(x: 0.35, y: 0.18, width: 0.28, height: 0.52),
            primaryCandidateConfidence: 0.9
        ),
        lighting: FrameFeatureSnapshot.LightingFeatures = .init(
            exposureBiasHint: -0.12,
            backlightIndex: 0.33,
            keyToFillRatio: 1.2
        ),
        motion: FrameFeatureSnapshot.MotionFeatures = .init(state: .still, shakeLevel: 0.1)
    ) -> FrameFeatureSnapshot {
        FrameFeatureSnapshot(
            frameId: "fixture-frame-1",
            mode: .pause,
            capturedAt: Date(timeIntervalSince1970: 1_768_000_000),
            sources: .init(
                vision: .init(available: true, freshnessMs: 25, confidence: 0.9),
                horizon: .init(available: true, freshnessMs: 42, confidence: 0.85),
                lighting: .init(available: true, freshnessMs: 55, confidence: 0.8),
                detr: .init(available: true, freshnessMs: 700, confidence: 0.76),
                aesthetic: .init(available: true, freshnessMs: 1600, confidence: 0.72)
            ),
            composition: composition,
            subjectSignals: subjectSignals,
            horizon: .init(angleDegrees: 1.6, confidence: 0.82),
            lighting: lighting,
            motion: motion,
            aesthetics: .init(score: 0.67, scoreConfidence: 0.79),
            objects: .init(totalCount: 3, topKLabels: ["person", "lamp", "chair"]),
            technicalFlags: []
        )
    }

    func makeSemantics(frameId: String) -> SceneSemanticsReport {
        SceneSemanticsReport(
            frameId: frameId,
            mode: .pause,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.81,
            primarySubject: .init(
                kind: .person,
                label: "person",
                region: .init(x: 0.35, y: 0.18, width: 0.28, height: 0.52),
                confidence: 0.88,
                competingCandidates: [
                    .init(id: "c2", kind: .object, label: "lamp", region: .init(x: 0.74, y: 0.2, width: 0.12, height: 0.35), confidence: 0.31)
                ]
            ),
            dominance: .init(hasClearFocus: true, focusCompetitionScore: 0.18, backgroundClutterScore: 0.35),
            readability: .init(subjectReadable: true, lookSpaceAdequate: true, edgePressureScore: 0.24, separationScore: 0.74),
            ambiguities: [],
            assumptions: [.init(id: "asm-1", text: "single-subject intent", confidence: 0.78)]
        )
    }

    func makeCritique(frameId: String) -> CritiqueReport {
        CritiqueReport(
            frameId: frameId,
            mode: .pause,
            verdict: .mixed,
            verdictConfidence: 0.77,
            strengths: [
                .init(
                    id: "s1",
                    type: .clearFocusHierarchy,
                    confidence: 0.81,
                    rationale: "subject dominates visual center",
                    evidence: [EvidenceRef(source: .semantics, key: "dominance.focusCompetitionScore", value: "0.18")],
                    supportingRegion: .init(x: 0.35, y: 0.18, width: 0.28, height: 0.52)
                )
            ],
            issues: [
                .init(
                    id: "i1",
                    type: .subjectTooCloseToEdge,
                    severity: 0.52,
                    confidence: 0.73,
                    rationale: "subject drifts toward right third boundary",
                    evidence: [EvidenceRef(source: .snapshot, key: "composition.horizontalOffset", value: "0.62")],
                    affectedRegion: .init(x: 0.67, y: 0.16, width: 0.3, height: 0.6),
                    suggestedFixTypes: [.reframing]
                )
            ],
            summary: .init(id: "summary-fixture-1", shortVerdict: "mixed", whyGood: "clear focus", whyProblematic: "edge pressure"),
            traceRefs: ["trace-1", "trace-2"],
            fallbackUsed: false
        )
    }

    func makePlan(frameId: String) -> RecommendationPlan {
        RecommendationPlan(
            frameId: frameId,
            mode: .pause,
            inputVerdict: .mixed,
            primaryAction: .init(
                id: "a1",
                actionType: .moveFrameLeft,
                priority: 1,
                targetRegion: .init(x: 0.67, y: 0.16, width: 0.3, height: 0.6),
                linkedIssueIds: ["i1"],
                expectedOutcome: "reduce right-edge pressure",
                guardrail: .init(requiresStillCamera: true, minConfidence: 0.65, suppressWhenMoving: true),
                overlayHint: .init(id: "ov-a1-left", kind: .arrow, targetRegion: nil, direction: .left)
            ),
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.79
        )
    }
}

final class CameraAnalysisExplainabilityContractTests: XCTestCase {

    func testExplainabilityTraceBundleValidatesDeterministicChain() {
        let critique = makeCritique()
        let plan = makePlan()
        let bundle = makeBundle()

        let errors = bundle.validate(critiqueReport: critique, recommendationPlan: plan)
        XCTAssertTrue(errors.isEmpty, "Expected no validation errors, got: \(errors)")
    }

    func testExplainabilityTraceRejectsRecommendationDependencyOnOptionalReasoning() {
        let critique = makeCritique()
        let plan = makePlan()
        let bundle = makeBundle(recommendationDependsOnOptionalReasoning: true)

        let errors = bundle.validate(critiqueReport: critique, recommendationPlan: plan)
        XCTAssertTrue(errors.contains("recommendation item r1 must depend on deterministic interpretation items"))
    }

    func testExplainabilityTraceRejectsRootSummaryWithoutSummaryLink() {
        let critique = makeCritique()
        let plan = makePlan()
        let bundle = makeBundle(includeSummaryOnRoot: false)

        let errors = bundle.validate(critiqueReport: critique, recommendationPlan: plan)
        XCTAssertTrue(errors.contains("rootSummaryId r1 must include a summary link"))
    }

    func testExplainabilityTraceEnforcesFrameAndModeScoping() {
        let critique = makeCritique(mode: .pause)
        let plan = makePlan(mode: .pause)
        let bundle = makeBundle(mode: .live)

        let errors = bundle.validate(critiqueReport: critique, recommendationPlan: plan)
        XCTAssertTrue(errors.contains("traceBundle must match critiqueReport.frameId+mode"))
        XCTAssertTrue(errors.contains("traceBundle must match recommendationPlan.frameId+mode"))
    }

    func testExplainabilityTraceEnforcesIssueStrengthActionCoverage() {
        let critique = makeCritique()
        let plan = makePlan()
        let bundle = makeCoverageBrokenBundle()

        let errors = bundle.validate(critiqueReport: critique, recommendationPlan: plan)
        XCTAssertTrue(errors.contains("strength s1 must be linked from interpretation trace item"))
        XCTAssertTrue(errors.contains("action a1 must be linked from recommendation trace item"))
    }

    func testExplainabilityTraceRejectsDuplicateItemIDsWithoutCrashing() {
        let critique = makeCritique()
        let plan = makePlan()
        let bundle = makeBundle()

        let duplicated = copyItem(item("o1", in: bundle), id: "o2")
        let mutated = bundleReplacingItem(bundle, id: "o1", with: duplicated)

        let errors = mutated.validate(critiqueReport: critique, recommendationPlan: plan)
        XCTAssertTrue(errors.contains(where: { $0.contains("trace item IDs must be non-empty and unique") }))
    }

    func testExplainabilityTraceRejectsMissingCoreAudience() {
        let critique = makeCritique()
        let plan = makePlan()
        let bundle = makeBundle()

        let noCoreAudience = copyItem(item("i3", in: bundle), audiences: [.debug, .eval])
        let mutated = bundleReplacingItem(bundle, id: "i3", with: noCoreAudience)

        let errors = mutated.validate(critiqueReport: critique, recommendationPlan: plan)
        XCTAssertTrue(errors.contains("trace item i3 must include core audience"))
    }

    func testExplainabilityTraceRejectsRootSummaryWithWrongSummaryID() {
        let critique = makeCritique()
        let plan = makePlan()
        let bundle = makeBundle()

        let wrongSummaryLinks = [
            TraceLink(kind: .action, refId: "a1"),
            TraceLink(kind: .summary, refId: "sum-wrong")
        ]
        let wrongRootSummary = copyItem(item("r1", in: bundle), links: wrongSummaryLinks)
        let mutated = bundleReplacingItem(bundle, id: "r1", with: wrongRootSummary)

        let errors = mutated.validate(critiqueReport: critique, recommendationPlan: plan)
        XCTAssertTrue(errors.contains("rootSummaryId r1 must link critique summary id sum-1"))
    }

    func testExplainabilityTraceResolvesIssueLinksWhenOnlyCritiqueProvided() {
        let critique = makeCritique()
        let bundle = makeBundle()

        let badIssueLink = copyItem(item("i1", in: bundle), links: [.init(kind: .issue, refId: "missing-issue")])
        let mutated = bundleReplacingItem(bundle, id: "i1", with: badIssueLink)

        let errors = mutated.validate(critiqueReport: critique, recommendationPlan: nil)
        XCTAssertTrue(errors.contains("trace item i1 links unknown issue id missing-issue"))
    }

    func testExplainabilityTraceResolvesActionLinksWhenOnlyPlanProvided() {
        let plan = makePlan()
        let bundle = makeBundle()

        let badActionLinks = [
            TraceLink(kind: .action, refId: "missing-action"),
            TraceLink(kind: .summary, refId: "sum-1")
        ]
        let badAction = copyItem(item("r1", in: bundle), links: badActionLinks)
        let mutated = bundleReplacingItem(bundle, id: "r1", with: badAction)

        let errors = mutated.validate(critiqueReport: nil, recommendationPlan: plan)
        XCTAssertTrue(errors.contains("trace item r1 links unknown action id missing-action"))
    }

    func testExplainabilityTraceRejectsCyclicDependencies() {
        let critique = makeCritique()
        let plan = makePlan()
        let bundle = makeBundle()

        let cyclicObservation = copyItem(item("o1", in: bundle), dependsOn: ["r1"])
        let mutated = bundleReplacingItem(bundle, id: "o1", with: cyclicObservation)

        let errors = mutated.validate(critiqueReport: critique, recommendationPlan: plan)
        XCTAssertTrue(errors.contains("trace dependency graph must be acyclic"))
    }

    func testExplainabilityTraceRejectsNonMonotonicDependencyTimestamps() {
        let critique = makeCritique()
        let plan = makePlan()
        let bundle = makeBundle()

        let earlyInterpretation = copyItem(item("i1", in: bundle), timestampMs: 90)
        let mutated = bundleReplacingItem(bundle, id: "i1", with: earlyInterpretation)

        let errors = mutated.validate(critiqueReport: critique, recommendationPlan: plan)
        XCTAssertTrue(errors.contains("trace dependency o1 must have timestamp < i1"))
    }

    func testExplainabilityTraceRejectsInvalidStageSourcePair() {
        let critique = makeCritique()
        let plan = makePlan()
        let bundle = makeBundle()

        let invalidPair = copyItem(item("r1", in: bundle), sourceKind: .optionalReasoning)
        let mutated = bundleReplacingItem(bundle, id: "r1", with: invalidPair)

        let errors = mutated.validate(critiqueReport: critique, recommendationPlan: plan)
        XCTAssertTrue(errors.contains("trace item r1 has invalid stage/sourceKind pair"))
    }

    func testExplainabilityTraceRejectsOptionalReasoningActionLink() {
        let critique = makeCritique()
        let plan = makePlan()
        let bundle = makeBundle()

        let optionalWithAction = copyItem(
            item("i3", in: bundle),
            links: [
                .init(kind: .summary, refId: "sum-1"),
                .init(kind: .action, refId: "a1")
            ]
        )
        let mutated = bundleReplacingItem(bundle, id: "i3", with: optionalWithAction)

        let errors = mutated.validate(critiqueReport: critique, recommendationPlan: plan)
        XCTAssertTrue(errors.contains("optional_reasoning item i3 cannot link actions"))
    }

    func testExplainabilityTraceRejectsUnknownLinksForAllKinds() {
        let critique = makeCritique()
        let plan = makePlan()
        var bundle = makeBundle()

        let issueItem = copyItem(item("i1", in: bundle), links: [.init(kind: .issue, refId: "missing-issue")])
        bundle = bundleReplacingItem(bundle, id: "i1", with: issueItem)

        let strengthItem = copyItem(item("i2", in: bundle), links: [.init(kind: .strength, refId: "missing-strength")])
        bundle = bundleReplacingItem(bundle, id: "i2", with: strengthItem)

        let summaryItem = copyItem(item("i3", in: bundle), links: [.init(kind: .summary, refId: "missing-summary")])
        bundle = bundleReplacingItem(bundle, id: "i3", with: summaryItem)

        let recommendationLinks = [
            TraceLink(kind: .action, refId: "missing-action"),
            TraceLink(kind: .overlay, refId: "missing-overlay"),
            TraceLink(kind: .summary, refId: "sum-1")
        ]
        let actionItem = copyItem(item("r1", in: bundle), links: recommendationLinks)
        bundle = bundleReplacingItem(bundle, id: "r1", with: actionItem)

        let errors = bundle.validate(critiqueReport: critique, recommendationPlan: plan)
        XCTAssertTrue(errors.contains("trace item i1 links unknown issue id missing-issue"))
        XCTAssertTrue(errors.contains("trace item i2 links unknown strength id missing-strength"))
        XCTAssertTrue(errors.contains("trace item i3 links unknown summary id missing-summary"))
        XCTAssertTrue(errors.contains("trace item r1 links unknown action id missing-action"))
        XCTAssertTrue(errors.contains("trace item r1 links unknown overlay id missing-overlay"))
    }

    func testExplainabilityTraceRejectsConfidenceCapViolation() {
        let critique = makeCritique()
        let plan = makePlan()
        var bundle = makeBundle()

        let lowConfidenceObservation1 = copyItem(item("o1", in: bundle), confidence: 0.4)
        bundle = bundleReplacingItem(bundle, id: "o1", with: lowConfidenceObservation1)
        let lowConfidenceObservation2 = copyItem(item("o2", in: bundle), confidence: 0.45)
        bundle = bundleReplacingItem(bundle, id: "o2", with: lowConfidenceObservation2)

        let errors = bundle.validate(critiqueReport: critique, recommendationPlan: plan)
        XCTAssertTrue(errors.contains("trace item i1 confidence must not exceed max dependency confidence + 0.1"))
    }

    func testExplainabilityTraceRejectsSpeculativeDeterministicRule() {
        let critique = makeCritique()
        let plan = makePlan()
        let bundle = makeBundle()

        let speculativeRule = copyItem(item("i1", in: bundle), certainty: .speculative)
        let mutated = bundleReplacingItem(bundle, id: "i1", with: speculativeRule)

        let errors = mutated.validate(critiqueReport: critique, recommendationPlan: plan)
        XCTAssertTrue(errors.contains("trace item i1 cannot use speculative certainty with deterministic_rule"))
    }

    func testExplainabilityTraceRejectsTooManyItemsInLiveMode() {
        let base = makeBundle(mode: .live)
        var expandedItems = base.items

        for index in 0..<7 {
            expandedItems.append(
                .init(
                    id: "live-extra-\(index)",
                    frameId: frameId,
                    mode: .live,
                    stage: .observation,
                    sourceKind: .snapshotSignal,
                    certainty: .deterministic,
                    confidence: 0.6,
                    timestampMs: 20 + index,
                    statement: "live compactness probe \(index)",
                    evidenceKeys: ["snapshot.liveProbe.\(index)"],
                    dependsOn: [],
                    links: [],
                    audiences: [.core]
                )
            )
        }

        let expanded = ExplainabilityTraceBundle(
            frameId: frameId,
            mode: .live,
            items: expandedItems,
            rootSummaryIds: base.rootSummaryIds
        )

        let errors = expanded.validate()
        XCTAssertTrue(errors.contains("live mode trace bundle should not exceed 12 items"))
    }

    func testExplainabilityTraceCodableRoundTrip() throws {
        let payload = ExplainabilityFixturePayload(
            critique: makeCritique(),
            plan: makePlan(),
            trace: makeBundle()
        )

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(ExplainabilityFixturePayload.self, from: data)

        XCTAssertEqual(decoded, payload)
        XCTAssertTrue(decoded.trace.validate(critiqueReport: decoded.critique, recommendationPlan: decoded.plan).isEmpty)
    }
}

private struct ExplainabilityFixturePayload: Codable, Equatable {
    let critique: CritiqueReport
    let plan: RecommendationPlan
    let trace: ExplainabilityTraceBundle
}

private extension CameraAnalysisExplainabilityContractTests {
    var frameId: String { "trace-frame-1" }

    func makeCritique(mode: AnalysisMode = .pause, verdict: FrameVerdict = .mixed) -> CritiqueReport {
        CritiqueReport(
            frameId: frameId,
            mode: mode,
            verdict: verdict,
            verdictConfidence: 0.82,
            strengths: [
                .init(
                    id: "s1",
                    type: .clearFocusHierarchy,
                    confidence: 0.78,
                    rationale: "subject remains dominant",
                    evidence: [.init(source: .semantics, key: "dominance.focusCompetitionScore", value: "0.2")]
                )
            ],
            issues: [
                .init(
                    id: "i1",
                    type: .subjectTooCloseToEdge,
                    severity: 0.58,
                    confidence: 0.74,
                    rationale: "subject drifts toward edge",
                    evidence: [.init(source: .snapshot, key: "composition.horizontalOffset", value: "0.64")]
                )
            ],
            summary: .init(id: "sum-1", shortVerdict: verdict.rawValue, whyGood: nil, whyProblematic: "edge pressure"),
            traceRefs: ["o1", "o2", "i1", "i2", "i3", "r1"],
            fallbackUsed: false
        )
    }

    func makePlan(mode: AnalysisMode = .pause) -> RecommendationPlan {
        RecommendationPlan(
            frameId: frameId,
            mode: mode,
            inputVerdict: .mixed,
            primaryAction: .init(
                id: "a1",
                actionType: .moveFrameLeft,
                priority: 1,
                targetRegion: .init(x: 0.62, y: 0.12, width: 0.31, height: 0.62),
                linkedIssueIds: ["i1"],
                expectedOutcome: "reduce edge pressure",
                guardrail: .init(requiresStillCamera: true, minConfidence: 0.6, suppressWhenMoving: true),
                overlayHint: .init(id: "ov-a1-left", kind: .arrow, direction: .left)
            ),
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.8
        )
    }

    func makeBundle(mode: AnalysisMode = .pause,
                    includeSummaryOnRoot: Bool = true,
                    recommendationDependsOnOptionalReasoning: Bool = false) -> ExplainabilityTraceBundle {
        var recommendationLinks: [TraceLink] = [.init(kind: .action, refId: "a1")]
        if includeSummaryOnRoot {
            recommendationLinks.append(.init(kind: .summary, refId: "sum-1"))
        }

        let recommendationDependsOn = recommendationDependsOnOptionalReasoning ? ["i3"] : ["i1"]

        let items: [ExplainabilityTraceItem] = [
            .init(
                id: "o1",
                frameId: frameId,
                mode: mode,
                stage: .observation,
                sourceKind: .snapshotSignal,
                certainty: .deterministic,
                confidence: 0.9,
                timestampMs: 100,
                statement: "snapshot.composition.horizontalOffset=0.64",
                evidenceKeys: ["snapshot.composition.horizontalOffset"],
                dependsOn: [],
                links: [],
                audiences: [.core, .debug]
            ),
            .init(
                id: "o2",
                frameId: frameId,
                mode: mode,
                stage: .observation,
                sourceKind: .semanticsSignal,
                certainty: .probabilistic,
                confidence: 0.83,
                timestampMs: 120,
                statement: "semantics.readability.edgePressureScore=0.61",
                evidenceKeys: ["semantics.readability.edgePressureScore"],
                dependsOn: [],
                links: [],
                audiences: [.core]
            ),
            .init(
                id: "i1",
                frameId: frameId,
                mode: mode,
                stage: .interpretation,
                sourceKind: .deterministicRule,
                certainty: .deterministic,
                confidence: 0.79,
                timestampMs: 200,
                statement: "subject is too close to edge",
                evidenceKeys: ["rule.subject_edge_pressure"],
                dependsOn: ["o1", "o2"],
                links: [.init(kind: .issue, refId: "i1")],
                audiences: [.core, .ui]
            ),
            .init(
                id: "i2",
                frameId: frameId,
                mode: mode,
                stage: .interpretation,
                sourceKind: .deterministicRule,
                certainty: .probabilistic,
                confidence: 0.72,
                timestampMs: 220,
                statement: "clear focus hierarchy remains a strength",
                evidenceKeys: ["rule.focus_hierarchy"],
                dependsOn: ["o2"],
                links: [.init(kind: .strength, refId: "s1")],
                audiences: [.core]
            ),
            .init(
                id: "i3",
                frameId: frameId,
                mode: mode,
                stage: .interpretation,
                sourceKind: .optionalReasoning,
                certainty: .speculative,
                confidence: 0.68,
                timestampMs: 240,
                statement: "likely nearest subject should stay primary",
                evidenceKeys: ["llm.optional_reasoning"],
                dependsOn: ["o2"],
                links: [.init(kind: .summary, refId: "sum-1")],
                audiences: [.core, .debug, .eval]
            ),
            .init(
                id: "r1",
                frameId: frameId,
                mode: mode,
                stage: .recommendation,
                sourceKind: .plannerPolicy,
                certainty: .deterministic,
                confidence: 0.78,
                timestampMs: 300,
                statement: "move frame left",
                evidenceKeys: ["planner.primary_action"],
                dependsOn: recommendationDependsOn,
                links: recommendationLinks,
                audiences: [.core, .ui]
            )
        ]

        return ExplainabilityTraceBundle(
            frameId: frameId,
            mode: mode,
            items: items,
            rootSummaryIds: ["r1"]
        )
    }

    func item(_ id: String, in bundle: ExplainabilityTraceBundle) -> ExplainabilityTraceItem {
        guard let item = bundle.items.first(where: { $0.id == id }) else {
            XCTFail("Missing fixture item with id \(id)")
            fatalError("Missing fixture item with id \(id)")
        }
        return item
    }

    func bundleReplacingItem(_ bundle: ExplainabilityTraceBundle,
                             id: String,
                             with newItem: ExplainabilityTraceItem) -> ExplainabilityTraceBundle {
        let replaced = bundle.items.map { $0.id == id ? newItem : $0 }
        return ExplainabilityTraceBundle(
            frameId: bundle.frameId,
            mode: bundle.mode,
            items: replaced,
            rootSummaryIds: bundle.rootSummaryIds
        )
    }

    func copyItem(_ item: ExplainabilityTraceItem,
                  id: String? = nil,
                  stage: TraceStage? = nil,
                  sourceKind: TraceSourceKind? = nil,
                  certainty: TraceCertainty? = nil,
                  confidence: Double? = nil,
                  timestampMs: Int? = nil,
                  dependsOn: [String]? = nil,
                  links: [TraceLink]? = nil,
                  audiences: [TraceAudience]? = nil) -> ExplainabilityTraceItem {
        ExplainabilityTraceItem(
            id: id ?? item.id,
            frameId: item.frameId,
            mode: item.mode,
            stage: stage ?? item.stage,
            sourceKind: sourceKind ?? item.sourceKind,
            certainty: certainty ?? item.certainty,
            confidence: confidence ?? item.confidence,
            timestampMs: timestampMs ?? item.timestampMs,
            statement: item.statement,
            evidenceKeys: item.evidenceKeys,
            dependsOn: dependsOn ?? item.dependsOn,
            links: links ?? item.links,
            audiences: audiences ?? item.audiences,
            metadata: item.metadata
        )
    }

    func makeCoverageBrokenBundle() -> ExplainabilityTraceBundle {
        let items: [ExplainabilityTraceItem] = [
            .init(
                id: "o1",
                frameId: frameId,
                mode: .pause,
                stage: .observation,
                sourceKind: .snapshotSignal,
                certainty: .deterministic,
                confidence: 0.9,
                timestampMs: 100,
                statement: "snapshot evidence",
                evidenceKeys: ["snapshot.composition.horizontalOffset"],
                dependsOn: [],
                links: [],
                audiences: [.core]
            ),
            .init(
                id: "i1",
                frameId: frameId,
                mode: .pause,
                stage: .interpretation,
                sourceKind: .deterministicRule,
                certainty: .deterministic,
                confidence: 0.79,
                timestampMs: 200,
                statement: "issue interpretation",
                evidenceKeys: ["rule.subject_edge_pressure"],
                dependsOn: ["o1"],
                links: [.init(kind: .issue, refId: "i1")],
                audiences: [.core]
            ),
            .init(
                id: "r1",
                frameId: frameId,
                mode: .pause,
                stage: .recommendation,
                sourceKind: .plannerPolicy,
                certainty: .deterministic,
                confidence: 0.75,
                timestampMs: 300,
                statement: "move frame left",
                evidenceKeys: ["planner.primary_action"],
                dependsOn: ["i1"],
                links: [.init(kind: .summary, refId: "sum-1")],
                audiences: [.core, .ui]
            )
        ]

        return ExplainabilityTraceBundle(
            frameId: frameId,
            mode: .pause,
            items: items,
            rootSummaryIds: ["r1"]
        )
    }
}

final class FeatureSnapshotAggregatorTests: XCTestCase {
    func testAggregatorIsDeterministicForSameInput() {
        let aggregator = FeatureSnapshotAggregator()
        let capturedAt = Date(timeIntervalSince1970: 1_776_000_000)
        let input = makeInput(
            capturedAt: capturedAt,
            motionState: .still,
            shakeLevel: 0.2,
            vision: makeVisionSample(
                measuredAt: capturedAt.addingTimeInterval(-0.05),
                baseConfidence: 0.92,
                subjects: [
                    .init(boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.5), confidence: 0.88, isFace: true)
                ],
                saliencyCenter: CGPoint(x: 0.42, y: 0.48),
                faceCount: 1,
                personCount: 1
            ),
            horizon: makeHorizonSample(measuredAt: capturedAt.addingTimeInterval(-0.02), angle: 1.2, confidence: 0.77),
            lighting: makeLightingSample(measuredAt: capturedAt.addingTimeInterval(-0.07), exposure: -0.12, backlight: 0.24, keyFill: 1.1),
            detr: makeDetrSample(
                measuredAt: capturedAt.addingTimeInterval(-0.1),
                baseConfidence: 0.72,
                detections: [
                    .init(boundingBox: CGRect(x: 0.62, y: 0.24, width: 0.2, height: 0.25), label: "lamp", confidence: 0.72)
                ]
            ),
            aesthetic: makeAestheticSample(measuredAt: capturedAt.addingTimeInterval(-0.3), score10: 7.4)
        )

        let first = aggregator.makeSnapshot(from: input)
        let second = aggregator.makeSnapshot(from: input)

        XCTAssertEqual(first, second)
    }

    func testStaleVisionFallsBackToDetrPrimaryCandidate() {
        let aggregator = FeatureSnapshotAggregator()
        let capturedAt = Date(timeIntervalSince1970: 1_776_000_100)

        let input = makeInput(
            capturedAt: capturedAt,
            motionState: .still,
            shakeLevel: 0.05,
            vision: makeVisionSample(
                measuredAt: capturedAt.addingTimeInterval(-0.8), // stale for 250ms budget
                baseConfidence: 0.9,
                subjects: [
                    .init(boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.6), confidence: 0.9, isFace: true)
                ],
                saliencyCenter: CGPoint(x: 0.3, y: 0.3),
                faceCount: 1,
                personCount: 1
            ),
            detr: makeDetrSample(
                measuredAt: capturedAt.addingTimeInterval(-0.1),
                baseConfidence: 0.7,
                detections: [
                    .init(boundingBox: CGRect(x: 0.55, y: 0.2, width: 0.25, height: 0.35), label: "cup", confidence: 0.7)
                ]
            )
        )

        let snapshot = aggregator.makeSnapshot(from: input)

        XCTAssertFalse(snapshot.sources.vision.available)
        XCTAssertTrue(snapshot.sources.detr.available)
        XCTAssertEqual(snapshot.subjectSignals.topObjectLabel, "cup")
        XCTAssertEqual(snapshot.subjectSignals.personCount, 0)
        XCTAssertNotNil(snapshot.subjectSignals.primaryCandidateRegion)
        XCTAssertEqual(snapshot.subjectSignals.primaryCandidateRegion?.x, 0.55)
    }

    func testTieInEffectiveConfidencePrefersVisionCandidate() {
        let aggregator = FeatureSnapshotAggregator()
        let capturedAt = Date(timeIntervalSince1970: 1_776_000_200)
        let visionRegion = CGRect(x: 0.18, y: 0.22, width: 0.28, height: 0.42)
        let detrRegion = CGRect(x: 0.68, y: 0.22, width: 0.18, height: 0.32)

        let input = makeInput(
            capturedAt: capturedAt,
            motionState: .still,
            shakeLevel: 0,
            vision: makeVisionSample(
                measuredAt: capturedAt,
                baseConfidence: 1.0,
                subjects: [.init(boundingBox: visionRegion, confidence: 0.500, isFace: true)],
                saliencyCenter: nil,
                faceCount: 1,
                personCount: 1
            ),
            detr: makeDetrSample(
                measuredAt: capturedAt,
                baseConfidence: 1.0,
                detections: [.init(boundingBox: detrRegion, label: "book", confidence: 0.505)]
            )
        )

        let snapshot = aggregator.makeSnapshot(from: input)
        XCTAssertEqual(snapshot.subjectSignals.primaryCandidateRegion?.x, 0.18)
        XCTAssertEqual(snapshot.subjectSignals.personCount, 1)
    }

    func testDetrTieBreakIsDeterministicAcrossInputOrder() {
        let aggregator = FeatureSnapshotAggregator()
        let capturedAt = Date(timeIntervalSince1970: 1_776_000_250)
        let detA = FeatureSnapshotDetectedObject(
            boundingBox: CGRect(x: 0.61, y: 0.25, width: 0.2, height: 0.2),
            label: "book",
            confidence: 0.7
        )
        let detB = FeatureSnapshotDetectedObject(
            boundingBox: CGRect(x: 0.31, y: 0.25, width: 0.2, height: 0.2),
            label: "book",
            confidence: 0.7
        )

        let first = makeInput(
            capturedAt: capturedAt,
            detr: makeDetrSample(measuredAt: capturedAt, baseConfidence: 1.0, detections: [detA, detB])
        )
        let second = makeInput(
            capturedAt: capturedAt,
            detr: makeDetrSample(measuredAt: capturedAt, baseConfidence: 1.0, detections: [detB, detA])
        )

        let s1 = aggregator.makeSnapshot(from: first)
        let s2 = aggregator.makeSnapshot(from: second)

        XCTAssertEqual(s1.subjectSignals.primaryCandidateRegion, s2.subjectSignals.primaryCandidateRegion)
        XCTAssertEqual(s1.objects.topKLabels, s2.objects.topKLabels)
    }

    func testEmptyInputUsesDefaultsAndComputesDeterministicFlags() {
        let aggregator = FeatureSnapshotAggregator()
        let capturedAt = Date(timeIntervalSince1970: 1_776_000_300)
        let input = makeInput(capturedAt: capturedAt)

        let snapshot = aggregator.makeSnapshot(from: input)

        XCTAssertFalse(snapshot.sources.vision.available)
        XCTAssertFalse(snapshot.sources.horizon.available)
        XCTAssertFalse(snapshot.sources.lighting.available)
        XCTAssertFalse(snapshot.sources.detr.available)
        XCTAssertFalse(snapshot.sources.aesthetic.available)

        XCTAssertEqual(snapshot.composition.horizontalOffset, 0)
        XCTAssertEqual(snapshot.composition.verticalOffset, 0)
        XCTAssertEqual(snapshot.subjectSignals.personCount, 0)
        XCTAssertEqual(snapshot.horizon.angleDegrees, 0)
        XCTAssertEqual(snapshot.lighting.backlightIndex, 0)
        XCTAssertNil(snapshot.aesthetics.score)
        XCTAssertEqual(snapshot.objects.totalCount, 0)
        XCTAssertEqual(snapshot.technicalFlags, [.lowSceneConfidence, .lowSubjectConfidence])
    }

    func testFreshnessConfidenceMonotonicAndStaleEviction() {
        let aggregator = FeatureSnapshotAggregator()
        let capturedAt = Date(timeIntervalSince1970: 1_776_000_400)

        let newer = makeInput(
            capturedAt: capturedAt,
            horizon: makeHorizonSample(measuredAt: capturedAt.addingTimeInterval(-0.1), angle: 2.0, confidence: 0.8)
        )
        let older = makeInput(
            capturedAt: capturedAt,
            horizon: makeHorizonSample(measuredAt: capturedAt.addingTimeInterval(-0.2), angle: 2.0, confidence: 0.8)
        )
        let stale = makeInput(
            capturedAt: capturedAt,
            horizon: makeHorizonSample(measuredAt: capturedAt.addingTimeInterval(-1.0), angle: 2.0, confidence: 0.8)
        )

        let newerSnapshot = aggregator.makeSnapshot(from: newer)
        let olderSnapshot = aggregator.makeSnapshot(from: older)
        let staleSnapshot = aggregator.makeSnapshot(from: stale)

        XCTAssertGreaterThan(newerSnapshot.sources.horizon.confidence ?? 0, olderSnapshot.sources.horizon.confidence ?? 0)
        XCTAssertFalse(staleSnapshot.sources.horizon.available)
        XCTAssertEqual(staleSnapshot.horizon.angleDegrees, 0)
        XCTAssertEqual(staleSnapshot.horizon.confidence, 0)
    }

    func testNormalizationAndVisionPersonCountOwnership() {
        let aggregator = FeatureSnapshotAggregator()
        let capturedAt = Date(timeIntervalSince1970: 1_776_000_500)

        let input = makeInput(
            capturedAt: capturedAt,
            motionState: .moving,
            shakeLevel: 1.7,
            vision: makeVisionSample(
                measuredAt: capturedAt,
                baseConfidence: 0.9,
                subjects: [
                    .init(boundingBox: CGRect(x: -0.2, y: 1.1, width: 1.4, height: 0.3), confidence: 0.8, isFace: true)
                ],
                saliencyCenter: CGPoint(x: 0.2, y: 0.9),
                faceCount: 1,
                personCount: 2
            ),
            horizon: makeHorizonSample(measuredAt: capturedAt, angle: 0.3, confidence: 0.9),
            lighting: makeLightingSample(measuredAt: capturedAt, exposure: -0.5, backlight: 0.7, keyFill: 1.3),
            detr: makeDetrSample(
                measuredAt: capturedAt,
                baseConfidence: 0.7,
                detections: [
                    .init(boundingBox: CGRect(x: 0.6, y: 0.2, width: 0.2, height: 0.2), label: "vase", confidence: 0.7),
                    .init(boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2), label: "book", confidence: 0.7)
                ]
            ),
            aesthetic: makeAestheticSample(measuredAt: capturedAt, score10: 12.0)
        )

        let snapshot = aggregator.makeSnapshot(from: input)

        XCTAssertEqual(snapshot.motion.shakeLevel, 1.0)
        XCTAssertEqual(snapshot.aesthetics.score, 1.0)
        XCTAssertEqual(snapshot.subjectSignals.personCount, 2) // from Vision only
        XCTAssertEqual(snapshot.objects.totalCount, 2)
        XCTAssertTrue(snapshot.technicalFlags.contains(.highMotion))
        XCTAssertTrue(snapshot.technicalFlags.contains(.lowLight))

        XCTAssertEqual(snapshot.subjectSignals.primaryCandidateRegion?.x, 0.0)
        XCTAssertEqual(snapshot.subjectSignals.primaryCandidateRegion?.y, 1.0)
        XCTAssertEqual(snapshot.subjectSignals.primaryCandidateRegion?.width, 1.0)
        XCTAssertEqual(snapshot.subjectSignals.primaryCandidateRegion?.height, 0.3)
    }

    func testTechnicalFlagsPositiveAndNegativeMatrix() {
        let aggregator = FeatureSnapshotAggregator()
        let capturedAt = Date(timeIntervalSince1970: 1_776_000_520)

        let allFlagsInput = makeInput(
            capturedAt: capturedAt,
            motionState: .moving,
            shakeLevel: 0.9,
            horizon: makeHorizonSample(measuredAt: capturedAt, angle: 0.1, confidence: 0.1),
            lighting: makeLightingSample(measuredAt: capturedAt, exposure: -0.7, backlight: 0.8, keyFill: 1.0),
            detr: makeDetrSample(measuredAt: capturedAt, baseConfidence: 0.1, detections: []),
            vision: makeVisionSample(
                measuredAt: capturedAt,
                baseConfidence: 0.1,
                subjects: [],
                saliencyCenter: nil,
                faceCount: 0,
                personCount: 0
            )
        )
        let allFlags = aggregator.makeSnapshot(from: allFlagsInput).technicalFlags
        XCTAssertEqual(allFlags, [.highMotion, .lowLight, .lowSceneConfidence, .lowSubjectConfidence])

        let noFlagsInput = makeInput(
            capturedAt: capturedAt,
            motionState: .still,
            shakeLevel: 0.05,
            vision: makeVisionSample(
                measuredAt: capturedAt,
                baseConfidence: 0.95,
                subjects: [.init(boundingBox: CGRect(x: 0.4, y: 0.2, width: 0.25, height: 0.45), confidence: 0.95, isFace: true)],
                saliencyCenter: CGPoint(x: 0.52, y: 0.5),
                faceCount: 1,
                personCount: 1
            ),
            horizon: makeHorizonSample(measuredAt: capturedAt, angle: 0.2, confidence: 0.9),
            lighting: makeLightingSample(measuredAt: capturedAt, exposure: 0.1, backlight: 0.1, keyFill: 1.0),
            detr: makeDetrSample(
                measuredAt: capturedAt,
                baseConfidence: 0.9,
                detections: [.init(boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2), label: "cup", confidence: 0.9)]
            ),
            aesthetic: makeAestheticSample(measuredAt: capturedAt, score10: 7.0)
        )
        let noFlags = aggregator.makeSnapshot(from: noFlagsInput).technicalFlags
        XCTAssertEqual(noFlags, [])
    }

    func testFaceDetectionForcesPersonDetectedInvariant() {
        let aggregator = FeatureSnapshotAggregator()
        let capturedAt = Date(timeIntervalSince1970: 1_776_000_550)
        let input = makeInput(
            capturedAt: capturedAt,
            vision: makeVisionSample(
                measuredAt: capturedAt,
                baseConfidence: 0.8,
                subjects: [],
                saliencyCenter: nil,
                faceCount: 1,
                personCount: 0
            )
        )

        let snapshot = aggregator.makeSnapshot(from: input)
        XCTAssertTrue(snapshot.subjectSignals.faceDetected)
        XCTAssertTrue(snapshot.subjectSignals.personDetected)
        XCTAssertTrue(snapshot.validate().isEmpty)
    }
}

final class PipelineFeatureSnapshotAdapterTests: XCTestCase {
    func testAdapterDoesNotCreateFallbackSamplesWithoutMeasuredAt() {
        var features = CoachingFeatures()
        features.horizon.angle = 4.0
        features.horizon.confidence = 0.8
        features.lighting.backlightIndex = 0.6
        features.aestheticScore = 7.0

        let adapter = PipelineFeatureSnapshotAdapter()
        let input = adapter.makeInput(
            frameId: "f-adapter",
            mode: .live,
            capturedAt: Date(timeIntervalSince1970: 1_776_000_900),
            state: PipelineFeatureSnapshotAdapterState(
                features: features,
                debugData: DebugData(),
                vision: nil,
                horizonMeasuredAt: nil,
                horizon: nil,
                lightingMeasuredAt: nil,
                lighting: nil,
                detr: nil,
                aestheticMeasuredAt: nil,
                aesthetic: nil
            )
        )

        XCTAssertNil(input.vision)
        XCTAssertNil(input.horizon)
        XCTAssertNil(input.lighting)
        XCTAssertNil(input.detr)
        XCTAssertNil(input.aesthetic)
    }
}

private extension FeatureSnapshotAggregatorTests {
    func makeInput(capturedAt: Date,
                   motionState: CameraAnalysisMotionState = .still,
                   shakeLevel: Double = 0,
                   vision: FeatureSample<FeatureSnapshotVisionPayload>? = nil,
                   horizon: FeatureSample<FeatureSnapshotHorizonPayload>? = nil,
                   lighting: FeatureSample<FeatureSnapshotLightingPayload>? = nil,
                   detr: FeatureSample<FeatureSnapshotDetrPayload>? = nil,
                   aesthetic: FeatureSample<FeatureSnapshotAestheticPayload>? = nil) -> FeatureAggregationInput {
        FeatureAggregationInput(
            frameId: "frame-test",
            mode: .live,
            capturedAt: capturedAt,
            motionState: motionState,
            shakeLevel: shakeLevel,
            vision: vision,
            horizon: horizon,
            lighting: lighting,
            detr: detr,
            aesthetic: aesthetic
        )
    }

    func makeVisionSample(measuredAt: Date,
                          baseConfidence: Double?,
                          subjects: [FeatureSnapshotVisionSubject],
                          saliencyCenter: CGPoint?,
                          faceCount: Int,
                          personCount: Int) -> FeatureSample<FeatureSnapshotVisionPayload> {
        FeatureSample(
            value: FeatureSnapshotVisionPayload(
                subjects: subjects,
                saliencyCenter: saliencyCenter,
                faceCount: faceCount,
                personCount: personCount
            ),
            measuredAt: measuredAt,
            baseConfidence: baseConfidence
        )
    }

    func makeHorizonSample(measuredAt: Date,
                           angle: Double,
                           confidence: Double) -> FeatureSample<FeatureSnapshotHorizonPayload> {
        FeatureSample(
            value: FeatureSnapshotHorizonPayload(angleDegrees: angle, confidence: confidence),
            measuredAt: measuredAt,
            baseConfidence: confidence
        )
    }

    func makeLightingSample(measuredAt: Date,
                            exposure: Double,
                            backlight: Double,
                            keyFill: Double?) -> FeatureSample<FeatureSnapshotLightingPayload> {
        FeatureSample(
            value: FeatureSnapshotLightingPayload(
                exposureBiasHint: exposure,
                backlightIndex: backlight,
                keyToFillRatio: keyFill
            ),
            measuredAt: measuredAt,
            baseConfidence: nil
        )
    }

    func makeDetrSample(measuredAt: Date,
                        baseConfidence: Double?,
                        detections: [FeatureSnapshotDetectedObject]) -> FeatureSample<FeatureSnapshotDetrPayload> {
        FeatureSample(
            value: FeatureSnapshotDetrPayload(detections: detections),
            measuredAt: measuredAt,
            baseConfidence: baseConfidence
        )
    }

    func makeAestheticSample(measuredAt: Date,
                             score10: Double) -> FeatureSample<FeatureSnapshotAestheticPayload> {
        FeatureSample(
            value: FeatureSnapshotAestheticPayload(score10: score10),
            measuredAt: measuredAt,
            baseConfidence: nil
        )
    }
}
