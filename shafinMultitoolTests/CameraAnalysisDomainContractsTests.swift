import XCTest
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
            summary: .init(shortVerdict: "good", whyGood: nil, whyProblematic: nil),
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
            summary: .init(shortVerdict: "mixed", whyGood: "clear focus", whyProblematic: "edge pressure"),
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
                overlayHint: .init(kind: .arrow, targetRegion: nil, direction: .left)
            ),
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.79
        )
    }
}
