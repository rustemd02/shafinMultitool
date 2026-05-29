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

    func testNormalizedRectSanitizesNonFiniteValues() {
        let rect = NormalizedRect(x: .nan, y: .infinity, width: .infinity, height: -.infinity)
        XCTAssertEqual(rect.x, 0.0)
        XCTAssertEqual(rect.y, 0.0)
        XCTAssertEqual(rect.width, 0.0)
        XCTAssertEqual(rect.height, 0.0)
        XCTAssertTrue(rect.isDegenerate)
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

final class NeuralEvidenceDomainContractTests: XCTestCase {
    func testNeuralEvidenceSnapshotRejectsNonCanonicalHeadOrdering() {
        let reversedSnapshot = makeNeuralSnapshot(headEntries: Array(makeCanonicalHeadEntries(mode: .pause).reversed()))
        let semantics = makeNeuralSemantics(frameId: reversedSnapshot.frameId, mode: reversedSnapshot.mode, primaryKind: .person)

        XCTAssertEqual(reversedSnapshot.headOutputs.map(\.headId), Array(EvidenceHeadId.allCases.reversed()))
        XCTAssertTrue(reversedSnapshot.validate(expectedFrameId: reversedSnapshot.frameId, semanticsReport: semantics)
            .contains("neuralEvidence.headOutputs must use canonical head ordering"))

        let canonicalSnapshot = makeNeuralSnapshot()
        XCTAssertEqual(canonicalSnapshot.headOutputs.map(\.headId), EvidenceHeadId.allCases)
        XCTAssertTrue(canonicalSnapshot.validate(expectedFrameId: canonicalSnapshot.frameId, semanticsReport: semantics).isEmpty)
    }

    func testNeuralEvidenceSnapshotRejectsPauseOnlyHeadInLiveMode() {
        var entries = makeCanonicalHeadEntries(mode: .live)
        entries[headIndex(.balanceConfidence)] = makeScalarEntry(
            headId: .balanceConfidence,
            status: .available,
            score: 0.72,
            confidence: 0.66,
            mode: .live,
            supportingSignals: [.frameBalance]
        )

        let snapshot = makeNeuralSnapshot(mode: .live, headEntries: entries)
        let errors = snapshot.validate(expectedFrameId: snapshot.frameId)

        XCTAssertTrue(errors.contains("balance_confidence must be not_applicable in live mode"))
    }

    func testFaceSaliencyApplicabilityUsesSemanticsPrimarySubjectKind() {
        var personEntries = makeCanonicalHeadEntries(mode: .pause)
        personEntries[headIndex(.faceSaliency)] = makeScalarEntry(
            headId: .faceSaliency,
            status: .notApplicable,
            score: nil,
            confidence: 0.0,
            mode: .pause,
            supportingSignals: []
        )

        let personSnapshot = makeNeuralSnapshot(headEntries: personEntries)
        let personSemantics = makeNeuralSemantics(frameId: personSnapshot.frameId, mode: .pause, primaryKind: .person)
        XCTAssertTrue(personSnapshot.validate(expectedFrameId: personSnapshot.frameId, semanticsReport: personSemantics)
            .contains("face_saliency must not be not_applicable for person-centric semantics"))

        var objectEntries = makeCanonicalHeadEntries(mode: .pause)
        objectEntries[headIndex(.faceSaliency)] = makeScalarEntry(
            headId: .faceSaliency,
            status: .notApplicable,
            score: nil,
            confidence: 0.0,
            mode: .pause,
            supportingSignals: []
        )
        let objectSnapshot = makeNeuralSnapshot(headEntries: objectEntries)
        let objectSemantics = makeNeuralSemantics(frameId: objectSnapshot.frameId, mode: .pause, primaryKind: .object)
        XCTAssertTrue(objectSnapshot.validate(expectedFrameId: objectSnapshot.frameId, semanticsReport: objectSemantics).isEmpty)
    }

    func testFaceSaliencyRequiresUnavailableStatusWhenSemanticsAreMissing() {
        let defaultSnapshot = makeNeuralSnapshot()
        XCTAssertTrue(defaultSnapshot.validate(expectedFrameId: defaultSnapshot.frameId)
            .contains("face_saliency must be unavailable when deterministic semantics are missing"))

        var unavailableEntries = makeCanonicalHeadEntries(mode: .pause)
        unavailableEntries[headIndex(.faceSaliency)] = makeScalarEntry(
            headId: .faceSaliency,
            status: .unavailable,
            score: nil,
            confidence: 0.0,
            mode: .pause,
            supportingSignals: []
        )

        let unavailableSnapshot = makeNeuralSnapshot(headEntries: unavailableEntries)
        XCTAssertTrue(unavailableSnapshot.validate(expectedFrameId: unavailableSnapshot.frameId).isEmpty)
    }

    func testShotTypeConfidenceRequiresCompleteCanonicalAffinities() {
        var entries = makeCanonicalHeadEntries(mode: .pause)
        let brokenAffinities = EvidenceCategoryId.allCases.dropLast().map {
            EvidenceCategoryScore(categoryId: $0, score: 0.4)
        }
        entries[headIndex(.shotTypeConfidence)] = .init(
            headId: .shotTypeConfidence,
            payload: .categorical(
                .init(
                    headId: .shotTypeConfidence,
                    status: .available,
                    affinities: Array(brokenAffinities),
                    confidence: 0.63,
                    mode: .pause,
                    supportingSignals: []
                )
            )
        )

        let snapshot = makeNeuralSnapshot(headEntries: entries)
        let errors = snapshot.validate(expectedFrameId: snapshot.frameId)
        XCTAssertTrue(errors.contains("shot_type_confidence affinities must use complete canonical category ordering"))
    }

    func testSupportingSignalsEnforceCardinalityAndPerHeadVocabulary() {
        var entries = makeCanonicalHeadEntries(mode: .pause)
        entries[headIndex(.subjectProminence)] = makeScalarEntry(
            headId: .subjectProminence,
            status: .available,
            score: 0.72,
            confidence: 0.84,
            mode: .pause,
            supportingSignals: [.subjectScale, .subjectAttentionPull, .subjectReadability]
        )
        entries[headIndex(.lightingQuality)] = makeScalarEntry(
            headId: .lightingQuality,
            status: .available,
            score: 0.68,
            confidence: 0.73,
            mode: .pause,
            supportingSignals: [.subjectScale]
        )

        let snapshot = makeNeuralSnapshot(headEntries: entries)
        let errors = snapshot.validate(expectedFrameId: snapshot.frameId)
        XCTAssertTrue(errors.contains("subject_prominence supportingSignals must contain at most 2 tags"))
        XCTAssertTrue(errors.contains("lighting_quality supportingSignals contain tags outside allowed vocabulary"))
    }

    func testNeuralEvidenceRuntimeMetadataMustAlignWithSnapshotAndVersion() {
        let snapshot = makeNeuralSnapshot()
        let metadata = NeuralEvidenceRuntimeMetadata(
            metadataSchemaVersion: "h2",
            frameId: "other-frame",
            mode: .live,
            providerKind: .coremlLocal,
            inferenceTarget: .onDevice,
            modelFamily: "compact_neural_evidence_net",
            modelVersion: "h05.v1",
            preprocessingVersion: "prep.v2",
            thresholdProfile: "default_pause_v1",
            producedAt: snapshot.capturedAt.addingTimeInterval(-1),
            latencyMs: 42,
            roiStrategy: nil,
            failureReason: nil
        )

        let errors = metadata.validate(against: snapshot)
        XCTAssertTrue(errors.contains("neuralEvidenceRuntimeMetadata must match snapshot frameId+mode"))
        XCTAssertTrue(errors.contains("neuralEvidenceRuntimeMetadata.metadataSchemaVersion must match snapshot.schemaVersion"))
        XCTAssertTrue(errors.contains("neuralEvidenceRuntimeMetadata.producedAt must be >= snapshot.capturedAt"))
    }

    func testNeuralEvidenceRejectsUnsupportedSchemaVersion() {
        let snapshot = NeuralEvidenceSnapshot(
            schemaVersion: "h0",
            frameId: "neural-frame-1",
            mode: .pause,
            capturedAt: isoDate("2026-04-22T10:15:31.482Z"),
            bundleVersion: "hybrid-evidence-bundle.2026-04-22",
            headOutputs: makeCanonicalHeadEntries(mode: .pause)
        )

        XCTAssertTrue(snapshot.validate(expectedFrameId: snapshot.frameId)
            .contains("neuralEvidence.schemaVersion must be \(NeuralEvidenceSnapshot.currentSchemaVersion)"))
    }

    func testHardFailureSnapshotRemainsValidEnvelope() {
        let snapshot = makeHardFailureSnapshot(mode: .pause)
        let metadata = NeuralEvidenceRuntimeMetadata(
            metadataSchemaVersion: NeuralEvidenceSnapshot.currentSchemaVersion,
            frameId: snapshot.frameId,
            mode: snapshot.mode,
            providerKind: .coremlLocal,
            inferenceTarget: .onDevice,
            modelFamily: "compact_neural_evidence_net",
            modelVersion: "h05.v1",
            preprocessingVersion: "prep.v2",
            thresholdProfile: "default_pause_v1",
            producedAt: snapshot.capturedAt.addingTimeInterval(0.051),
            latencyMs: 51,
            roiStrategy: .fullFrameOnly,
            failureReason: .inferenceFailed
        )

        XCTAssertTrue(snapshot.validate(expectedFrameId: snapshot.frameId, runtimeMetadata: metadata).isEmpty)
    }

    func testPolicySkippedRequiresFullyPolicyDegradedLiveSnapshot() {
        let liveSnapshot = makeNeuralSnapshot(mode: .live)
        let metadata = NeuralEvidenceRuntimeMetadata(
            metadataSchemaVersion: NeuralEvidenceSnapshot.currentSchemaVersion,
            frameId: liveSnapshot.frameId,
            mode: liveSnapshot.mode,
            providerKind: .coremlLocal,
            inferenceTarget: .onDevice,
            modelFamily: "compact_neural_evidence_net",
            modelVersion: "h05.v1",
            preprocessingVersion: "prep.v2",
            thresholdProfile: "default_live_v1",
            producedAt: liveSnapshot.capturedAt.addingTimeInterval(0.019),
            latencyMs: 19,
            roiStrategy: .fullFrameOnly,
            failureReason: .policySkipped
        )

        XCTAssertTrue(liveSnapshot.validate(expectedFrameId: liveSnapshot.frameId, runtimeMetadata: metadata)
            .contains("policy_skipped requires a fully policy-degraded neural evidence snapshot"))
    }

    func testNeuralEvidenceExplainabilityKeysMatchScalarAndCategoricalContracts() {
        let entries = makeCanonicalHeadEntries(mode: .pause)
        let scalarKeys = entries[headIndex(.subjectProminence)].explainabilityKeys
        XCTAssertEqual(scalarKeys, [
            "neural.subject_prominence.status",
            "neural.subject_prominence.score",
            "neural.subject_prominence.confidence",
            "neural.subject_prominence.supportingSignals"
        ])

        let categoricalKeys = entries[headIndex(.shotTypeConfidence)].explainabilityKeys
        XCTAssertEqual(categoricalKeys.first, "neural.shot_type_confidence.status")
        XCTAssertEqual(categoricalKeys.dropFirst().first, "neural.shot_type_confidence.confidence")
        XCTAssertFalse(categoricalKeys.contains("neural.shot_type_confidence.score"))
        XCTAssertEqual(Array(categoricalKeys.dropFirst(2)), EvidenceCategoryId.allCases.map {
            "neural.shot_type_confidence.affinities.\($0.rawValue)"
        })
    }

    func testNeuralEvidenceCodableRoundTripUsesIsoDatesAndExplicitNulls() throws {
        var entries = makeCanonicalHeadEntries(mode: .pause)
        entries[headIndex(.faceSaliency)] = makeScalarEntry(
            headId: .faceSaliency,
            status: .unavailable,
            score: nil,
            confidence: 0.0,
            mode: .pause,
            supportingSignals: []
        )

        let snapshot = makeNeuralSnapshot(headEntries: entries)
        let metadata = NeuralEvidenceRuntimeMetadata(
            metadataSchemaVersion: "h1",
            frameId: snapshot.frameId,
            mode: snapshot.mode,
            providerKind: .coremlLocal,
            inferenceTarget: .onDevice,
            modelFamily: "compact_neural_evidence_net",
            modelVersion: "h05.v1",
            preprocessingVersion: "prep.v2",
            thresholdProfile: "default_pause_v1",
            producedAt: snapshot.capturedAt.addingTimeInterval(0.133),
            latencyMs: nil,
            roiStrategy: nil,
            failureReason: nil
        )

        let payload = NeuralEvidenceFixturePayload(snapshot: snapshot, metadata: metadata)
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(NeuralEvidenceFixturePayload.self, from: data)

        XCTAssertEqual(decoded, payload)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let snapshotJSON = try XCTUnwrap(json["snapshot"] as? [String: Any])
        XCTAssertEqual(snapshotJSON["capturedAt"] as? String, "2026-04-22T10:15:31.482Z")

        let headOutputs = try XCTUnwrap(snapshotJSON["headOutputs"] as? [[String: Any]])
        let faceEntry = try XCTUnwrap(headOutputs.first { ($0["headId"] as? String) == EvidenceHeadId.faceSaliency.rawValue })
        let facePayload = try XCTUnwrap(faceEntry["payload"] as? [String: Any])
        XCTAssertTrue(facePayload["score"] is NSNull)

        let metadataJSON = try XCTUnwrap(json["metadata"] as? [String: Any])
        XCTAssertEqual(metadataJSON["producedAt"] as? String, "2026-04-22T10:15:31.615Z")
        XCTAssertTrue(metadataJSON["latencyMs"] is NSNull)
        XCTAssertTrue(metadataJSON["roiStrategy"] is NSNull)
        XCTAssertTrue(metadataJSON["failureReason"] is NSNull)
    }

    func testNeuralEvidenceSnapshotEncodingCanonicalizesArrayOrdering() throws {
        let snapshot = makeNeuralSnapshot(headEntries: Array(makeCanonicalHeadEntries(mode: .pause).reversed()))
        let data = try JSONEncoder().encode(snapshot)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let headOutputs = try XCTUnwrap(json["headOutputs"] as? [[String: Any]])
        XCTAssertEqual(headOutputs.compactMap { $0["headId"] as? String }, EvidenceHeadId.allCases.map(\.rawValue))
    }
}

private struct NeuralEvidenceFixturePayload: Codable, Equatable {
    let snapshot: NeuralEvidenceSnapshot
    let metadata: NeuralEvidenceRuntimeMetadata
}

private extension NeuralEvidenceDomainContractTests {
    func makeNeuralSnapshot(mode: AnalysisMode = .pause,
                            headEntries: [NeuralEvidenceHeadEntry]? = nil) -> NeuralEvidenceSnapshot {
        NeuralEvidenceSnapshot(
            schemaVersion: "h1",
            frameId: "neural-frame-1",
            mode: mode,
            capturedAt: isoDate("2026-04-22T10:15:31.482Z"),
            bundleVersion: "hybrid-evidence-bundle.2026-04-22",
            headOutputs: headEntries ?? makeCanonicalHeadEntries(mode: mode)
        )
    }

    func makeCanonicalHeadEntries(mode: AnalysisMode) -> [NeuralEvidenceHeadEntry] {
        let livePauseOnlyStatuses: [EvidenceHeadId: EvidenceHeadStatus] = [
            .balanceConfidence: .notApplicable,
            .depthSeparation: .notApplicable,
            .cinematicExpressiveness: .notApplicable,
            .shotTypeConfidence: .notApplicable
        ]

        return EvidenceHeadId.allCases.map { headId in
            if headId == .shotTypeConfidence {
                if mode == .live {
                    return .init(
                        headId: headId,
                        payload: .categorical(
                            .init(
                                headId: headId,
                                status: .notApplicable,
                                affinities: [],
                                confidence: 0.0,
                                mode: mode,
                                supportingSignals: []
                            )
                        )
                    )
                }

                return .init(
                    headId: headId,
                    payload: .categorical(
                        .init(
                            headId: headId,
                            status: .available,
                            affinities: EvidenceCategoryId.allCases.map { .init(categoryId: $0, score: $0 == .dialogueCloseupAffinity ? 0.72 : 0.14) },
                            confidence: 0.64,
                            mode: mode,
                            supportingSignals: []
                        )
                    )
                )
            }

            if let forcedStatus = livePauseOnlyStatuses[headId], mode == .live {
                return makeScalarEntry(
                    headId: headId,
                    status: forcedStatus,
                    score: nil,
                    confidence: 0.0,
                    mode: mode,
                    supportingSignals: []
                )
            }

            let defaultSignals: [EvidenceHeadId: [SupportingSignalTag]] = [
                .subjectProminence: [.subjectReadability, .subjectScale],
                .backgroundClutter: [.attentionCompetition],
                .lightingQuality: [.tonalStructure, .subjectExposureReadability],
                .faceSaliency: [.eyeRegionVisibility, .faceAttentionPull],
                .balanceConfidence: [.frameBalance],
                .depthSeparation: [.subjectBackgroundContrast],
                .cinematicExpressiveness: [.visualHarmonyResidual]
            ]

            return makeScalarEntry(
                headId: headId,
                status: .available,
                score: 0.7,
                confidence: 0.75,
                mode: mode,
                supportingSignals: defaultSignals[headId] ?? []
            )
        }
    }

    func makeHardFailureSnapshot(mode: AnalysisMode) -> NeuralEvidenceSnapshot {
        let entries = EvidenceHeadId.allCases.map { headId -> NeuralEvidenceHeadEntry in
            if headId == .shotTypeConfidence {
                return .init(
                    headId: headId,
                    payload: .categorical(
                        .init(
                            headId: headId,
                            status: .unavailable,
                            affinities: [],
                            confidence: 0.0,
                            mode: mode,
                            supportingSignals: []
                        )
                    )
                )
            }

            return makeScalarEntry(
                headId: headId,
                status: .unavailable,
                score: nil,
                confidence: 0.0,
                mode: mode,
                supportingSignals: []
            )
        }

        return makeNeuralSnapshot(mode: mode, headEntries: entries)
    }

    func makeScalarEntry(headId: EvidenceHeadId,
                         status: EvidenceHeadStatus,
                         score: Double?,
                         confidence: Double,
                         mode: AnalysisMode,
                         supportingSignals: [SupportingSignalTag]) -> NeuralEvidenceHeadEntry {
        .init(
            headId: headId,
            payload: .scalar(
                .init(
                    headId: headId,
                    status: status,
                    score: score,
                    confidence: confidence,
                    mode: mode,
                    supportingSignals: supportingSignals
                )
            )
        )
    }

    func makeNeuralSemantics(frameId: String,
                             mode: AnalysisMode,
                             primaryKind: SubjectKind) -> SceneSemanticsReport {
        SceneSemanticsReport(
            frameId: frameId,
            mode: mode,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.78,
            primarySubject: .init(kind: primaryKind, confidence: primaryKind == .unknown ? 0.1 : 0.84),
            dominance: .init(hasClearFocus: true, focusCompetitionScore: 0.2, backgroundClutterScore: 0.3),
            readability: .init(subjectReadable: true, lookSpaceAdequate: true, edgePressureScore: 0.21, separationScore: 0.71),
            ambiguities: [],
            assumptions: []
        )
    }

    func headIndex(_ headId: EvidenceHeadId) -> Int {
        guard let index = EvidenceHeadId.allCases.firstIndex(of: headId) else {
            fatalError("Unknown head id \(headId)")
        }
        return index
    }

    func isoDate(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        guard let date = formatter.date(from: value) else {
            fatalError("Invalid ISO date: \(value)")
        }
        return date
    }
}

final class SemanticTipContractTests: XCTestCase {

    func testSemanticCatalogCoversLegacyIssueAndStrengthAnchors() {
        XCTAssertEqual(Set(SemanticTipCatalog.issueTipCoverage.keys), Set(IssueTypeV1.allCases))
        XCTAssertEqual(Set(SemanticTipCatalog.strengthTipCoverage.keys), Set(StrengthTypeV1.allCases))
        XCTAssertTrue(SemanticTipCatalog.issueTipCoverage.values.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(SemanticTipCatalog.strengthTipCoverage.values.allSatisfy { !$0.isEmpty })
    }

    func testSemanticCatalogDefinitionsCoverClosedTaxonomies() {
        let definitions = SemanticTipCatalog.definitions

        XCTAssertEqual(Set(definitions.map(\.tipType)), Set(SemanticTipType.allCases))
        XCTAssertEqual(Set(definitions.map(\.actionType)), Set(SemanticActionType.allCases))
        XCTAssertEqual(SemanticTipCatalog.v1Actions, Set(SemanticActionType.allCases))
        XCTAssertEqual(SemanticTipCatalog.deferredActions, Set([
            "add_rim_light",
            "add_side_light",
            "turn_subject_for_cleaner_profile"
        ]))

        let coveredProblems = Set(definitions.flatMap(\.problemTypes))
        let coveredStrengths = Set(definitions.flatMap(\.strengthTypes))
        XCTAssertEqual(coveredProblems, Set(VisualProblemType.allCases))
        XCTAssertEqual(coveredStrengths, Set(VisualStrengthType.allCases))
        XCTAssertTrue(definitions.flatMap { $0.validate() }.isEmpty)
    }

    func testSemanticCatalogCoversRequiredActionFramesAndObjectStaging() {
        let frames = Set(SemanticTipCatalog.definitions.map(\.actionFrame))
        XCTAssertTrue(frames.isSuperset(of: [.moveCamera, .moveSubject, .moveObject, .adjustLight, .wait]))

        let objectActions = SemanticTipCatalog.definitions
            .filter { $0.actionFrame == .moveObject }
            .map(\.actionType)

        XCTAssertTrue(objectActions.contains(.moveObjectLeft))
        XCTAssertTrue(objectActions.contains(.moveObjectRight))
        XCTAssertTrue(objectActions.contains(.moveObjectForward))
        XCTAssertTrue(objectActions.contains(.moveObjectBack))
        XCTAssertTrue(objectActions.contains(.removeDistractingObject))
        XCTAssertTrue(objectActions.contains(.repositionPropForBalance))
    }

    func testSafeDisplayLabelPolicyGroundsKnownObjectsAndDegradesUnknownObjects() {
        XCTAssertEqual(
            SemanticDisplayLabelPolicy.displayLabel(
                entityKind: .object,
                role: .foregroundObject,
                groundedLabel: " цветок ",
                confidence: 0.9
            ),
            "цветок"
        )

        XCTAssertEqual(
            SemanticDisplayLabelPolicy.displayLabel(
                entityKind: .object,
                role: .foregroundObject,
                groundedLabel: "дракон",
                confidence: 0.95
            ),
            "предмет"
        )

        XCTAssertEqual(
            SemanticDisplayLabelPolicy.displayLabel(
                entityKind: .object,
                role: .foregroundObject,
                groundedLabel: nil,
                confidence: 0.35,
                direction: .right
            ),
            "объект справа"
        )

        XCTAssertEqual(
            SemanticDisplayLabelPolicy.displayLabel(
                entityKind: .prop,
                role: .faceContourOccluder,
                groundedLabel: nil,
                confidence: 0.4
            ),
            "предмет у лица"
        )

        XCTAssertEqual(
            SemanticDisplayLabelPolicy.displayLabel(
                entityKind: .person,
                role: .primarySubject,
                groundedLabel: "Алексей",
                confidence: 0.99
            ),
            "герой"
        )

        XCTAssertFalse(SemanticDisplayLabelPolicy.isAllowedDisplayLabel("Алексей"))
    }

    func testSemanticTipCandidateValidationAcceptsEntityAwareActionableTip() {
        let candidate = SemanticTipCandidate(
            tipType: .moveObjectOffLeftEdge,
            actionType: .moveObjectRight,
            actionFrame: .moveObject,
            direction: .right,
            problemType: .objectEdgePressure,
            strengthType: nil,
            targetEntityKind: .object,
            targetEntityRole: .foregroundObject,
            targetEntityRef: "object:flower:1",
            targetEntityGroundingConfidence: 0.92,
            targetEntityDisplayLabel: "цветок",
            secondaryEntityRef: nil,
            secondaryEntityGroundingConfidence: nil,
            secondaryEntityDisplayLabel: nil,
            primaryActionId: "action-1",
            linkedActionIds: [],
            linkedIssueIds: ["issue-1"],
            linkedStrengthIds: [],
            linkedTraceIds: ["trace-1"],
            summaryId: nil,
            supportedModes: [.live, .pause],
            priorityBand: .primaryCorrective,
            liveText: "Сдвинь цветок правее.",
            pauseText: "Цветок слишком близко к краю. Сдвинь его правее, чтобы кадр стал спокойнее.",
            fallbackBehavior: .degradeToGenericLabel
        )

        XCTAssertTrue(candidate.validate().isEmpty, candidate.validate().joined(separator: "\n"))
    }

    func testSemanticTipCandidateValidationRejectsUnsafeLabelsAndMismatchedWaitActions() {
        let unsafeLabelCandidate = SemanticTipCandidate(
            tipType: .moveSubjectLeftForBalance,
            actionType: .moveSubjectLeft,
            actionFrame: .moveSubject,
            direction: .left,
            problemType: .backgroundCompetition,
            strengthType: nil,
            targetEntityKind: .person,
            targetEntityRole: .primarySubject,
            targetEntityRef: "person:1",
            targetEntityGroundingConfidence: 0.99,
            targetEntityDisplayLabel: "Алексей",
            secondaryEntityRef: nil,
            secondaryEntityGroundingConfidence: nil,
            secondaryEntityDisplayLabel: nil,
            primaryActionId: "action-1",
            linkedActionIds: [],
            linkedIssueIds: ["issue-1"],
            linkedStrengthIds: [],
            linkedTraceIds: ["trace-1"],
            summaryId: nil,
            supportedModes: [.pause],
            priorityBand: .contextualCorrective,
            liveText: "Смести героя левее.",
            pauseText: "Смести героя левее, чтобы фон меньше спорил с ним.",
            fallbackBehavior: .degradeToGenericActionCopy
        )

        let invalidWaitCandidate = SemanticTipCandidate(
            tipType: .waitForBackgroundClearance,
            actionType: .moveObjectRight,
            actionFrame: .wait,
            direction: SemanticDirection.none,
            problemType: .timingBlockerInFrame,
            strengthType: nil,
            targetEntityKind: .object,
            targetEntityRole: .backgroundObject,
            targetEntityRef: nil,
            targetEntityGroundingConfidence: nil,
            targetEntityDisplayLabel: "яркий объект на фоне",
            secondaryEntityRef: nil,
            secondaryEntityGroundingConfidence: nil,
            secondaryEntityDisplayLabel: nil,
            primaryActionId: "action-2",
            linkedActionIds: [],
            linkedIssueIds: ["issue-2"],
            linkedStrengthIds: [],
            linkedTraceIds: ["trace-2"],
            summaryId: nil,
            supportedModes: [.live],
            priorityBand: .timingCorrective,
            liveText: "Подожди, пока фон очистится.",
            pauseText: "В фоне есть временная помеха. Подожди, пока она уйдет.",
            fallbackBehavior: .degradeToGenericActionCopy
        )

        let personWithObjectLabelCandidate = SemanticTipCandidate(
            tipType: .moveSubjectLeftForBalance,
            actionType: .moveSubjectLeft,
            actionFrame: .moveSubject,
            direction: .left,
            problemType: .backgroundCompetition,
            strengthType: nil,
            targetEntityKind: .person,
            targetEntityRole: .primarySubject,
            targetEntityRef: "person:1",
            targetEntityGroundingConfidence: 0.92,
            targetEntityDisplayLabel: "ваза",
            secondaryEntityRef: nil,
            secondaryEntityGroundingConfidence: nil,
            secondaryEntityDisplayLabel: nil,
            primaryActionId: "action-3",
            linkedActionIds: [],
            linkedIssueIds: ["issue-3"],
            linkedStrengthIds: [],
            linkedTraceIds: ["trace-3"],
            summaryId: nil,
            supportedModes: [.pause],
            priorityBand: .contextualCorrective,
            liveText: "Смести героя левее.",
            pauseText: "Смести героя левее, чтобы фон меньше спорил с ним.",
            fallbackBehavior: .degradeToGenericActionCopy
        )

        XCTAssertTrue(unsafeLabelCandidate.validate().contains("targetEntityDisplayLabel must follow safe label policy"))
        XCTAssertTrue(invalidWaitCandidate.validate().contains("wait actionFrame requires wait_for_background_clearance action"))
        XCTAssertTrue(personWithObjectLabelCandidate.validate().contains("targetEntityDisplayLabel must follow safe label policy"))
    }

    func testSemanticTipCandidateValidationRequiresFaceRelationForContourRemoval() {
        let missingFaceRelationCandidate = SemanticTipCandidate(
            tipType: .removeObjectFromFaceContour,
            actionType: .removeDistractingObject,
            actionFrame: .moveObject,
            direction: SemanticDirection.none,
            problemType: .faceContourOcclusion,
            strengthType: nil,
            targetEntityKind: .prop,
            targetEntityRole: .faceContourOccluder,
            targetEntityRef: "object:vase:1",
            targetEntityGroundingConfidence: 0.91,
            targetEntityDisplayLabel: "ваза",
            secondaryEntityRef: nil,
            secondaryEntityGroundingConfidence: nil,
            secondaryEntityDisplayLabel: nil,
            primaryActionId: "action-3",
            linkedActionIds: [],
            linkedIssueIds: ["issue-3"],
            linkedStrengthIds: [],
            linkedTraceIds: ["trace-3"],
            summaryId: nil,
            supportedModes: [.live, .pause],
            priorityBand: .primaryCorrective,
            liveText: "Убери вазу из-за лица.",
            pauseText: "Ваза заходит на контур лица. Убери ее в сторону, чтобы лицо читалось чище.",
            fallbackBehavior: .degradeToGenericLabel
        )

        let errors = missingFaceRelationCandidate.validate()

        XCTAssertTrue(errors.contains("remove_object_from_face_contour requires secondaryEntityRef"))
        XCTAssertTrue(errors.contains("remove_object_from_face_contour requires secondaryEntityDisplayLabel"))
    }

    func testSemanticTipCandidateValidationRequiresGroundingForSpecificObjectLabels() {
        let ungroundedFlowerCandidate = SemanticTipCandidate(
            tipType: .moveObjectOffLeftEdge,
            actionType: .moveObjectRight,
            actionFrame: .moveObject,
            direction: .right,
            problemType: .objectEdgePressure,
            strengthType: nil,
            targetEntityKind: .object,
            targetEntityRole: .foregroundObject,
            targetEntityRef: nil,
            targetEntityGroundingConfidence: 0.92,
            targetEntityDisplayLabel: "цветок",
            secondaryEntityRef: nil,
            secondaryEntityGroundingConfidence: nil,
            secondaryEntityDisplayLabel: nil,
            primaryActionId: "action-1",
            linkedActionIds: [],
            linkedIssueIds: ["issue-1"],
            linkedStrengthIds: [],
            linkedTraceIds: ["trace-1"],
            summaryId: nil,
            supportedModes: [.live, .pause],
            priorityBand: .primaryCorrective,
            liveText: "Сдвинь цветок правее.",
            pauseText: "Цветок слишком близко к краю. Сдвинь его правее, чтобы кадр стал спокойнее.",
            fallbackBehavior: .degradeToGenericLabel
        )

        let lowConfidenceFlowerCandidate = SemanticTipCandidate(
            tipType: .moveObjectOffLeftEdge,
            actionType: .moveObjectRight,
            actionFrame: .moveObject,
            direction: .right,
            problemType: .objectEdgePressure,
            strengthType: nil,
            targetEntityKind: .object,
            targetEntityRole: .foregroundObject,
            targetEntityRef: "object:flower:1",
            targetEntityGroundingConfidence: 0.62,
            targetEntityDisplayLabel: "цветок",
            secondaryEntityRef: nil,
            secondaryEntityGroundingConfidence: nil,
            secondaryEntityDisplayLabel: nil,
            primaryActionId: "action-1",
            linkedActionIds: [],
            linkedIssueIds: ["issue-1"],
            linkedStrengthIds: [],
            linkedTraceIds: ["trace-1"],
            summaryId: nil,
            supportedModes: [.live, .pause],
            priorityBand: .primaryCorrective,
            liveText: "Сдвинь цветок правее.",
            pauseText: "Цветок слишком близко к краю. Сдвинь его правее, чтобы кадр стал спокойнее.",
            fallbackBehavior: .degradeToGenericLabel
        )

        XCTAssertTrue(ungroundedFlowerCandidate.validate().contains("grounded targetEntityDisplayLabel requires targetEntityRef"))
        XCTAssertTrue(lowConfidenceFlowerCandidate.validate().contains("grounded targetEntityDisplayLabel requires high-confidence grounding"))
    }

    func testSemanticTipCandidateValidationRejectsCatalogDrift() {
        let pauseOnlyTipInLive = SemanticTipCandidate(
            tipType: .addFrontFillOnSubject,
            actionType: .addFrontFillLight,
            actionFrame: .adjustLight,
            direction: SemanticDirection.none,
            problemType: .frontLightDeficit,
            strengthType: nil,
            targetEntityKind: .lightSource,
            targetEntityRole: .lightTarget,
            targetEntityRef: nil,
            targetEntityGroundingConfidence: nil,
            targetEntityDisplayLabel: "свет",
            secondaryEntityRef: nil,
            secondaryEntityGroundingConfidence: nil,
            secondaryEntityDisplayLabel: nil,
            primaryActionId: "action-4",
            linkedActionIds: [],
            linkedIssueIds: ["issue-4"],
            linkedStrengthIds: [],
            linkedTraceIds: ["trace-4"],
            summaryId: nil,
            supportedModes: [.live],
            priorityBand: .secondaryCorrective,
            liveText: "Добавь слабый фронтальный свет.",
            pauseText: "Лицу не хватает фронтального света. Добавь слабую заливку спереди.",
            fallbackBehavior: .degradeToGenericActionCopy
        )

        let catalogDriftCandidate = SemanticTipCandidate(
            tipType: .moveObjectOffLeftEdge,
            actionType: .shiftFrameRight,
            actionFrame: .moveObject,
            direction: .right,
            problemType: .objectEdgePressure,
            strengthType: nil,
            targetEntityKind: .object,
            targetEntityRole: .foregroundObject,
            targetEntityRef: "object:flower:1",
            targetEntityGroundingConfidence: 0.92,
            targetEntityDisplayLabel: "цветок",
            secondaryEntityRef: nil,
            secondaryEntityGroundingConfidence: nil,
            secondaryEntityDisplayLabel: nil,
            primaryActionId: "action-5",
            linkedActionIds: [],
            linkedIssueIds: ["issue-5"],
            linkedStrengthIds: [],
            linkedTraceIds: ["trace-5"],
            summaryId: nil,
            supportedModes: [.live],
            priorityBand: .secondaryCorrective,
            liveText: "Сдвинь цветок правее.",
            pauseText: "Цветок слишком близко к краю. Сдвинь его правее.",
            fallbackBehavior: .degradeToGenericLabel
        )

        XCTAssertTrue(pauseOnlyTipInLive.validate().contains("semantic tip supportedModes must be subset of catalog definition"))
        XCTAssertTrue(catalogDriftCandidate.validate().contains("semantic tip actionType must match catalog definition"))
        XCTAssertTrue(catalogDriftCandidate.validate().contains("semantic tip priorityBand must match catalog definition"))
    }

    func testSemanticTipCandidateCodableRoundTripPreservesEntityFields() throws {
        let candidate = SemanticTipCandidate(
            tipType: .removeObjectFromFaceContour,
            actionType: .removeDistractingObject,
            actionFrame: .moveObject,
            direction: SemanticDirection.none,
            problemType: .faceContourOcclusion,
            strengthType: nil,
            targetEntityKind: .prop,
            targetEntityRole: .faceContourOccluder,
            targetEntityRef: "object:vase:1",
            targetEntityGroundingConfidence: 0.91,
            targetEntityDisplayLabel: "ваза",
            secondaryEntityRef: "face:1",
            secondaryEntityGroundingConfidence: nil,
            secondaryEntityDisplayLabel: "лицо",
            primaryActionId: "action-3",
            linkedActionIds: [],
            linkedIssueIds: ["issue-3"],
            linkedStrengthIds: [],
            linkedTraceIds: ["trace-3"],
            summaryId: nil,
            supportedModes: [.live, .pause],
            priorityBand: .primaryCorrective,
            liveText: "Убери вазу из-за лица.",
            pauseText: "Ваза заходит на контур лица. Убери ее в сторону, чтобы лицо читалось чище.",
            fallbackBehavior: .degradeToGenericLabel
        )

        let data = try JSONEncoder().encode(candidate)
        let decoded = try JSONDecoder().decode(SemanticTipCandidate.self, from: data)

        XCTAssertEqual(decoded, candidate)
        XCTAssertEqual(decoded.targetEntityGroundingConfidence, 0.91)
        XCTAssertNil(decoded.secondaryEntityGroundingConfidence)
    }
}

final class VLMVisualEvidenceContractTests: XCTestCase {

    func testValidProblemFrameResponseAcceptsStructuredEvidenceAndRelation() {
        let request = makeRequest()
        let response = makeProblemResponse()

        let result = response.validate(against: request)

        XCTAssertTrue(result.accepted, result.violations.map(\.rawValue).joined(separator: "\n"))
        XCTAssertEqual(result.fallback, .useValidatedEvidence)
        XCTAssertEqual(result.acceptedObservations.map(\.observationId), ["obs-face-block-1"])
        XCTAssertEqual(result.acceptedRelations.map(\.relationId), ["rel-vase-blocks-face"])
        XCTAssertEqual(result.acceptedSuggestedActionIds, [.removeDistractingObject])
        XCTAssertEqual(result.acceptedPrimaryLabel, "герой")
        XCTAssertEqual(result.acceptedSecondaryLabel, "ваза")
    }

    func testUnknownActionIdFailsClosedAgainstAllowedCatalog() {
        let restrictedCatalog = VLMAllowedSemanticCatalog(
            catalogVersion: VLMAllowedSemanticCatalog.prS01.catalogVersion,
            allowedEvidenceDimensions: VLMAllowedSemanticCatalog.prS01.allowedEvidenceDimensions,
            allowedVisualProblemTypes: VLMAllowedSemanticCatalog.prS01.allowedVisualProblemTypes,
            allowedVisualStrengthTypes: VLMAllowedSemanticCatalog.prS01.allowedVisualStrengthTypes,
            allowedSemanticActionTypes: [.keepCurrentSetup],
            allowedGroundedObjectDisplayLabels: VLMAllowedSemanticCatalog.prS01.allowedGroundedObjectDisplayLabels,
            allowedGenericDisplayLabels: VLMAllowedSemanticCatalog.prS01.allowedGenericDisplayLabels
        )
        let request = makeRequest(allowedCatalog: restrictedCatalog)
        let response = makeProblemResponse()

        let result = response.validate(against: request)

        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.fallback, .deterministicOnly)
        XCTAssertTrue(result.violations.contains(.unknownActionId))
    }

    func testLiveModeFailsClosed() {
        let request = makeRequest(mode: .live)
        let response = makeProblemResponse(mode: .live)

        let result = response.validate(against: request)

        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.fallback, .deterministicOnly)
        XCTAssertTrue(result.violations.contains(.modeNotPause))
    }

    func testStructuredOnlyCannotIntroduceNewSpecificObjectLabel() {
        let request = makeRequest(
            privacyTier: .structuredOnly,
            visualInput: nil,
            groundedEntities: [makePersonEntity()]
        )
        let response = makeProblemResponse(
            privacyTier: .structuredOnly,
            secondaryEntityRef: nil,
            secondaryLabel: "ваза"
        )

        let result = response.validate(against: request)

        XCTAssertTrue(result.accepted, result.violations.map(\.rawValue).joined(separator: "\n"))
        XCTAssertEqual(result.fallback, .deterministicWithGenericLabels)
        XCTAssertEqual(result.acceptedSecondaryLabel, "предмет")
        XCTAssertTrue(result.violations.contains(.labelWithoutGrounding))
    }

    func testRedactedVisualRequiresAppliedRedaction() {
        let request = makeRequest(
            visualInput: VLMVisualInput(
                attachmentKind: .redactedStill,
                mediaRef: "unredacted-frame-1",
                longEdgePx: 768,
                exifStripped: true,
                redactionApplied: false,
                redactionNotes: []
            )
        )
        let response = makeProblemResponse()

        let result = response.validate(against: request)

        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.fallback, .deterministicOnly)
        XCTAssertTrue(result.violations.contains(.privacyTierMismatch))
    }

    func testRestrictedLabelCatalogFallsBackToGenericLabel() {
        let restrictedCatalog = VLMAllowedSemanticCatalog(
            catalogVersion: VLMAllowedSemanticCatalog.prS01.catalogVersion,
            allowedEvidenceDimensions: VLMAllowedSemanticCatalog.prS01.allowedEvidenceDimensions,
            allowedVisualProblemTypes: VLMAllowedSemanticCatalog.prS01.allowedVisualProblemTypes,
            allowedVisualStrengthTypes: VLMAllowedSemanticCatalog.prS01.allowedVisualStrengthTypes,
            allowedSemanticActionTypes: VLMAllowedSemanticCatalog.prS01.allowedSemanticActionTypes,
            allowedGroundedObjectDisplayLabels: [],
            allowedGenericDisplayLabels: VLMAllowedSemanticCatalog.prS01.allowedGenericDisplayLabels
        )
        let request = makeRequest(allowedCatalog: restrictedCatalog)
        let response = makeProblemResponse()

        let result = response.validate(against: request)

        XCTAssertTrue(result.accepted, result.violations.map(\.rawValue).joined(separator: "\n"))
        XCTAssertEqual(result.fallback, .deterministicWithGenericLabels)
        XCTAssertEqual(result.acceptedSecondaryLabel, "предмет")
        XCTAssertTrue(result.violations.contains(.unsafeSpecificLabel))
    }

    func testProviderSafetyPassedDoesNotBypassLocalRelationValidation() {
        let request = makeRequest()
        let response = makeProblemResponse(relationTargetRef: "unknown-entity")

        let result = response.validate(against: request)

        XCTAssertTrue(result.accepted, result.violations.map(\.rawValue).joined(separator: "\n"))
        XCTAssertTrue(result.violations.contains(.unknownEntityRef))
        XCTAssertEqual(result.acceptedRelations, [])
        XCTAssertEqual(result.acceptedObservations.count, 1)
    }

    func testKeepCurrentSetupCannotCoexistWithCorrectiveAction() {
        let request = makeRequest()
        let response = makeProblemResponse(suggestedActionIds: [.keepCurrentSetup, .removeDistractingObject])

        let result = response.validate(against: request)

        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.fallback, .deterministicOnly)
        XCTAssertTrue(result.violations.contains(.contradictoryKeepAndCorrect))
    }

    func testTooManyTopLevelSuggestedActionsFailsClosed() {
        let constraints = VLMVisualEvidenceConstraints(
            maxObservations: VLMVisualEvidenceConstraints.default.maxObservations,
            maxRelations: VLMVisualEvidenceConstraints.default.maxRelations,
            maxSuggestedActionIds: 0,
            maxExplanationChars: VLMVisualEvidenceConstraints.default.maxExplanationChars,
            allowMoodPreservation: VLMVisualEvidenceConstraints.default.allowMoodPreservation,
            requireEntityGroundingForSpecificLabels: VLMVisualEvidenceConstraints.default.requireEntityGroundingForSpecificLabels,
            failClosedOnUnknownIds: VLMVisualEvidenceConstraints.default.failClosedOnUnknownIds
        )
        let request = makeRequest(constraints: constraints)
        let response = makeProblemResponse()

        let result = response.validate(against: request)

        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.acceptedSuggestedActionIds, [])
        XCTAssertEqual(result.fallback, .deterministicOnly)
        XCTAssertTrue(result.violations.contains(.outputTooLong))
    }

    func testVLMVisualEvidenceResponseCodableRoundTripPreservesEntityFields() throws {
        let response = makeProblemResponse()

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(VLMVisualEvidenceResponse.self, from: data)

        XCTAssertEqual(decoded, response)
    }

    private func makeRequest(mode: AnalysisMode = .pause,
                             privacyTier: VLMPrivacyTier = .redactedVisual,
                             visualInput: VLMVisualInput? = VLMVisualInput(
                                attachmentKind: .redactedStill,
                                mediaRef: "redacted-frame-1",
                                longEdgePx: 768,
                                exifStripped: true,
                                redactionApplied: true,
                                redactionNotes: []
                             ),
                             allowedCatalog: VLMAllowedSemanticCatalog = .prS01,
                             constraints: VLMVisualEvidenceConstraints = .default,
                             groundedEntities: [VLMGroundedEntity]? = nil) -> VLMVisualEvidenceRequest {
        let context = makeLocalContext(mode: mode, groundedEntities: groundedEntities ?? [makePersonEntity(), makeVaseEntity()])
        return VLMVisualEvidenceRequest(
            schemaVersion: .s1,
            requestId: "vlm-req-002",
            frameId: "pause-frame-077",
            mode: mode,
            locale: "ru-RU",
            privacyTier: privacyTier,
            trigger: privacyTier == .redactedVisual ? .explicitUserRequest : .ambiguousLocalCase,
            visualInput: visualInput,
            localContext: context,
            allowedCatalog: allowedCatalog,
            constraints: constraints,
            correlation: VLMVisualEvidenceCorrelation(
                localCritiqueSummaryId: "summary-1",
                localPlanSummaryId: "plan-1",
                semanticCatalogVersion: allowedCatalog.catalogVersion,
                offloadingSchemaVersion: "h12",
                providerConfigVersion: "test",
                sessionEphemeralId: "session-ephemeral"
            )
        )
    }

    private func makeProblemResponse(mode: AnalysisMode = .pause,
                                     privacyTier: VLMPrivacyTier = .redactedVisual,
                                     secondaryEntityRef: String? = "ent-vase-1",
                                     secondaryLabel: String = "ваза",
                                     relationTargetRef: String? = "ent-person-1",
                                     suggestedActionIds: [SemanticActionType] = [.removeDistractingObject]) -> VLMVisualEvidenceResponse {
        VLMVisualEvidenceResponse(
            schemaVersion: .s1,
            requestId: "vlm-req-002",
            frameId: "pause-frame-077",
            mode: mode,
            providerId: "mock-vlm-semantic-v1",
            status: .completed,
            primaryEntityRef: "ent-person-1",
            primaryEntityKind: .person,
            primaryEntityDisplayLabelCandidate: "герой",
            primaryEntityLabelConfidence: 0.88,
            secondaryEntityRef: secondaryEntityRef,
            secondaryEntityKind: .prop,
            secondaryEntityDisplayLabelCandidate: secondaryLabel,
            secondaryEntityLabelConfidence: 0.81,
            observations: [
                VLMVisualEvidenceObservation(
                    observationId: "obs-face-block-1",
                    dimension: .faceVisibility,
                    polarity: .supportsProblem,
                    score: 0.74,
                    confidence: 0.79,
                    uncertaintyReasons: [],
                    primaryEntityRef: "ent-person-1",
                    secondaryEntityRef: secondaryEntityRef,
                    visualProblemType: .faceContourOcclusion,
                    visualStrengthType: nil,
                    supportedIssueIds: ["issue-background-competes"],
                    supportedStrengthIds: [],
                    suggestedActionIds: suggestedActionIds.filter { $0 != .keepCurrentSetup },
                    evidenceNote: "Предмет пересекает контур лица и забирает внимание."
                )
            ],
            relations: [
                VLMEntityRelation(
                    relationId: "rel-vase-blocks-face",
                    sourceEntityRef: secondaryEntityRef ?? "ent-vase-1",
                    targetEntityRef: relationTargetRef,
                    relationType: .blocks,
                    dimension: .faceVisibility,
                    score: 0.74,
                    confidence: 0.79,
                    uncertaintyReasons: [],
                    supportedObservationIds: ["obs-face-block-1"]
                )
            ],
            suggestedActionIds: suggestedActionIds,
            explanation: VLMSecondaryExplanation(
                language: "ru-RU",
                summary: "Главная проблема в предмете у лица: он ломает контур героя.",
                caveats: []
            ),
            safety: VLMEvidenceSafetyReport(passed: true, violations: []),
            diagnostics: VLMEvidenceDiagnostics(
                latencyMs: 740,
                providerModelFamily: "mock-vlm",
                providerModelVersion: "s1-dev",
                promptVersion: "vlm-evidence-s1",
                privacyTier: privacyTier,
                fallbackReason: nil
            )
        )
    }

    private func makePersonEntity() -> VLMGroundedEntity {
        VLMGroundedEntity(
            entityRef: "ent-person-1",
            kind: .person,
            role: .primarySubject,
            region: NormalizedRect(x: 0.20, y: 0.15, width: 0.30, height: 0.45),
            detectorLabel: "person",
            detectorConfidence: 0.91,
            displayLabelCandidate: "герой",
            displayLabelConfidence: 0.90
        )
    }

    private func makeVaseEntity() -> VLMGroundedEntity {
        VLMGroundedEntity(
            entityRef: "ent-vase-1",
            kind: .prop,
            role: .faceContourOccluder,
            region: NormalizedRect(x: 0.34, y: 0.18, width: 0.14, height: 0.24),
            detectorLabel: "vase",
            detectorConfidence: 0.82,
            displayLabelCandidate: "ваза",
            displayLabelConfidence: 0.82
        )
    }

    private func makeLocalContext(mode: AnalysisMode, groundedEntities: [VLMGroundedEntity]) -> VLMVisualEvidenceLocalContext {
        VLMVisualEvidenceLocalContext(
            frameFeatureSnapshotExcerpt: ["mode": mode.rawValue],
            sceneSemantics: makeSemantics(mode: mode),
            critique: makeCritique(mode: mode),
            recommendationPlan: makePlan(mode: mode),
            semanticTipDrafts: [
                SemanticTipDraftContext(
                    draftId: "draft-remove-prop",
                    tipType: .removeObjectFromFaceContour,
                    actionType: .removeDistractingObject,
                    actionFrame: .moveObject,
                    targetEntityRef: "ent-vase-1",
                    targetEntityKind: .prop,
                    targetEntityDisplayLabel: "ваза",
                    linkedIssueIds: ["issue-background-competes"],
                    linkedStrengthIds: [],
                    linkedActionIds: ["action-remove"],
                    priorityBand: .primaryCorrective
                )
            ],
            groundedEntities: groundedEntities,
            localNeuralEvidenceSummary: nil
        )
    }

    private func makeSemantics(mode: AnalysisMode) -> SceneSemanticsReport {
        SceneSemanticsReport(
            frameId: "pause-frame-077",
            mode: mode,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.82,
            primarySubject: .init(
                kind: .person,
                label: "person",
                region: NormalizedRect(x: 0.20, y: 0.15, width: 0.30, height: 0.45),
                confidence: 0.89
            ),
            dominance: .init(hasClearFocus: true, focusCompetitionScore: 0.30, backgroundClutterScore: 0.35),
            readability: .init(subjectReadable: true, lookSpaceAdequate: true, edgePressureScore: 0.22, separationScore: 0.70),
            ambiguities: [],
            assumptions: []
        )
    }

    private func makeCritique(mode: AnalysisMode) -> CritiqueReport {
        CritiqueReport(
            frameId: "pause-frame-077",
            mode: mode,
            verdict: .mixed,
            verdictConfidence: 0.72,
            strengths: [
                FrameStrength(
                    id: "strength-good-subject-isolation",
                    type: .goodSubjectIsolation,
                    confidence: 0.68,
                    rationale: "Субъект в целом читается.",
                    evidence: [EvidenceRef(source: .semantics, key: "readability.subjectReadable", value: "true", confidence: 0.8)]
                )
            ],
            issues: [
                FrameIssue(
                    id: "issue-background-competes",
                    type: .backgroundCompetesWithSubject,
                    severity: 0.62,
                    confidence: 0.74,
                    rationale: "Предмет рядом с лицом конкурирует с героем.",
                    evidence: [EvidenceRef(source: .semantics, key: "dominance.focusCompetitionScore", value: "0.30", confidence: 0.74)],
                    affectedRegion: NormalizedRect(x: 0.34, y: 0.18, width: 0.14, height: 0.24),
                    suggestedFixTypes: [.angleAdjustment]
                )
            ],
            summary: CritiqueSummary(id: "summary-1", shortVerdict: "Есть помеха у лица.", whyProblematic: "Предмет ломает контур героя."),
            traceRefs: ["trace-1"],
            fallbackUsed: false
        )
    }

    private func makePlan(mode: AnalysisMode) -> RecommendationPlan {
        RecommendationPlan(
            frameId: "pause-frame-077",
            mode: mode,
            inputVerdict: .mixed,
            primaryAction: RecommendationAction(
                id: "action-remove",
                actionType: .reduceBackgroundDistractions,
                priority: 1,
                targetRegion: NormalizedRect(x: 0.34, y: 0.18, width: 0.14, height: 0.24),
                linkedIssueIds: ["issue-background-competes"],
                expectedOutcome: "Контур лица станет чище.",
                guardrail: ActionGuardrail(requiresStillCamera: false, minConfidence: 0.5, suppressWhenMoving: false),
                overlayHint: nil
            ),
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.74
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

    func testDetrBackgroundSegmentsDoNotInflateObjectSummary() {
        let aggregator = FeatureSnapshotAggregator()
        let capturedAt = Date(timeIntervalSince1970: 1_776_000_260)
        let input = makeInput(
            capturedAt: capturedAt,
            detr: makeDetrSample(
                measuredAt: capturedAt,
                baseConfidence: 1.0,
                detections: [
                    .init(boundingBox: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0), label: "wall (other)", confidence: 1.0),
                    .init(boundingBox: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 0.82), label: "paper", confidence: 1.0),
                    .init(boundingBox: CGRect(x: 0.42, y: 0.40, width: 0.16, height: 0.20), label: "cup", confidence: 0.62)
                ]
            )
        )

        let snapshot = aggregator.makeSnapshot(from: input)

        XCTAssertEqual(snapshot.objects.totalCount, 1)
        XCTAssertEqual(snapshot.objects.topKLabels, ["cup"])
        XCTAssertEqual(snapshot.subjectSignals.topObjectLabel, "cup")
        XCTAssertEqual(snapshot.subjectSignals.primaryCandidateRegion?.x, 0.42)
    }

    func testFullFrameBackgroundOnlyDetrDoesNotBecomePrimarySubject() {
        let aggregator = FeatureSnapshotAggregator()
        let capturedAt = Date(timeIntervalSince1970: 1_776_000_270)
        let input = makeInput(
            capturedAt: capturedAt,
            detr: makeDetrSample(
                measuredAt: capturedAt,
                baseConfidence: 1.0,
                detections: [
                    .init(boundingBox: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0), label: "sky (other)", confidence: 1.0),
                    .init(boundingBox: CGRect(x: 0.0, y: 0.0, width: 0.98, height: 0.74), label: "building (other)", confidence: 0.92)
                ]
            )
        )

        let snapshot = aggregator.makeSnapshot(from: input)

        XCTAssertTrue(snapshot.sources.detr.available)
        XCTAssertNil(snapshot.subjectSignals.topObjectLabel)
        XCTAssertNil(snapshot.subjectSignals.primaryCandidateRegion)
        XCTAssertEqual(snapshot.objects.totalCount, 0)
        XCTAssertTrue(snapshot.technicalFlags.contains(.lowSubjectConfidence))
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
            vision: makeVisionSample(
                measuredAt: capturedAt,
                baseConfidence: 0.1,
                subjects: [],
                saliencyCenter: nil,
                faceCount: 0,
                personCount: 0
            ),
            horizon: makeHorizonSample(measuredAt: capturedAt, angle: 0.1, confidence: 0.1),
            lighting: makeLightingSample(measuredAt: capturedAt, exposure: -0.7, backlight: 0.8, keyFill: 1.0),
            detr: makeDetrSample(measuredAt: capturedAt, baseConfidence: 0.1, detections: [])
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

final class SceneSemanticsAnalyzerTests: XCTestCase {
    func testDialogueCloseupGoldenCase() {
        let analyzer = SceneSemanticsAnalyzer()
        let snapshot = makeSnapshot(
            frameId: "sem-dialogue",
            composition: .init(
                horizontalOffset: 0.05,
                verticalOffset: 0.0,
                subjectAreaRatio: 0.30,
                saliencyLeftRightBalance: 0.08,
                saliencyTopBottomBalance: 0.02
            ),
            subjectSignals: .init(
                faceDetected: true,
                personDetected: true,
                personCount: 1,
                topObjectLabel: "chair",
                topObjectConfidence: 0.31,
                primaryCandidateRegion: .init(x: 0.30, y: 0.15, width: 0.35, height: 0.55),
                primaryCandidateConfidence: 0.92
            ),
            objects: .init(totalCount: 2, topKLabels: ["chair", "lamp"])
        )

        let report = analyzer.analyze(snapshot: snapshot)

        XCTAssertEqual(report.sceneType, .dialogueCloseup)
        XCTAssertEqual(report.primarySubject.kind, .face)
        XCTAssertTrue(report.dominance.hasClearFocus)
    }

    func testSingleCharacterMediumGoldenCase() {
        let analyzer = SceneSemanticsAnalyzer()
        let snapshot = makeSnapshot(
            frameId: "sem-single",
            composition: .init(
                horizontalOffset: 0.10,
                verticalOffset: 0.02,
                subjectAreaRatio: 0.18,
                saliencyLeftRightBalance: 0.06,
                saliencyTopBottomBalance: 0.01
            ),
            subjectSignals: .init(
                faceDetected: false,
                personDetected: true,
                personCount: 1,
                topObjectLabel: "table",
                topObjectConfidence: 0.22,
                primaryCandidateRegion: .init(x: 0.36, y: 0.2, width: 0.26, height: 0.48),
                primaryCandidateConfidence: 0.88
            )
        )

        let report = analyzer.analyze(snapshot: snapshot)
        XCTAssertEqual(report.sceneType, .singleCharacterMedium)
        XCTAssertEqual(report.readability.lookSpaceAdequate, true)
    }

    func testTwoCharacterFrameAndAmbiguityGoldenCase() {
        let analyzer = SceneSemanticsAnalyzer()
        let snapshot = makeSnapshot(
            frameId: "sem-two",
            composition: .init(
                horizontalOffset: 0.18,
                verticalOffset: 0.0,
                subjectAreaRatio: 0.17,
                saliencyLeftRightBalance: 0.20,
                saliencyTopBottomBalance: 0.0
            ),
            subjectSignals: .init(
                faceDetected: false,
                personDetected: true,
                personCount: 2,
                topObjectLabel: "cup",
                topObjectConfidence: 0.95,
                primaryCandidateRegion: .init(x: 0.1, y: 0.2, width: 0.22, height: 0.38),
                primaryCandidateConfidence: 0.83
            ),
            objects: .init(totalCount: 3, topKLabels: ["cup", "book", "bottle"])
        )

        let report = analyzer.analyze(snapshot: snapshot)
        XCTAssertEqual(report.sceneType, .twoCharacterFrame)
        XCTAssertTrue(report.ambiguities.contains { $0.type == .multipleSubjectsSimilarConfidence })
    }

    func testObjectInsertGoldenCase() {
        let analyzer = SceneSemanticsAnalyzer()
        let snapshot = makeSnapshot(
            frameId: "sem-object",
            composition: .init(
                horizontalOffset: 0.04,
                verticalOffset: 0.0,
                subjectAreaRatio: 0.14,
                saliencyLeftRightBalance: 0.05,
                saliencyTopBottomBalance: 0.0
            ),
            subjectSignals: .init(
                faceDetected: false,
                personDetected: false,
                personCount: 0,
                topObjectLabel: "watch",
                topObjectConfidence: 0.92,
                primaryCandidateRegion: nil,
                primaryCandidateConfidence: nil
            ),
            objects: .init(totalCount: 1, topKLabels: ["watch"])
        )

        let report = analyzer.analyze(snapshot: snapshot)
        XCTAssertEqual(report.sceneType, .objectInsert)
        XCTAssertEqual(report.primarySubject.kind, .object)
        XCTAssertNil(report.readability.lookSpaceAdequate)
    }

    func testEstablishingLikeFrameGoldenCase() {
        let analyzer = SceneSemanticsAnalyzer()
        let snapshot = makeSnapshot(
            frameId: "sem-establishing",
            composition: .init(
                horizontalOffset: 0.0,
                verticalOffset: 0.0,
                subjectAreaRatio: 0.03,
                saliencyLeftRightBalance: 0.0,
                saliencyTopBottomBalance: 0.0
            ),
            subjectSignals: .init(
                faceDetected: false,
                personDetected: false,
                personCount: 0,
                topObjectLabel: "tree",
                topObjectConfidence: 0.35,
                primaryCandidateRegion: nil,
                primaryCandidateConfidence: nil
            ),
            objects: .init(totalCount: 6, topKLabels: ["tree", "house", "road"])
        )

        let report = analyzer.analyze(snapshot: snapshot)
        XCTAssertEqual(report.sceneType, .establishingLikeFrame)
    }

    func testMoodyBacklitSubjectGoldenCase() {
        let analyzer = SceneSemanticsAnalyzer()
        let snapshot = makeSnapshot(
            frameId: "sem-moody",
            composition: .init(
                horizontalOffset: -0.1,
                verticalOffset: 0.0,
                subjectAreaRatio: 0.30,
                saliencyLeftRightBalance: -0.08,
                saliencyTopBottomBalance: 0.05
            ),
            subjectSignals: .init(
                faceDetected: false,
                personDetected: true,
                personCount: 1,
                topObjectLabel: "window",
                topObjectConfidence: 0.40,
                primaryCandidateRegion: .init(x: 0.35, y: 0.18, width: 0.22, height: 0.44),
                primaryCandidateConfidence: 0.72
            ),
            lighting: .init(exposureBiasHint: -0.03, backlightIndex: 0.82, keyToFillRatio: 1.6)
        )

        let report = analyzer.analyze(snapshot: snapshot)
        XCTAssertEqual(report.sceneType, .moodyBacklitSubject)
        XCTAssertLessThan(report.readability.separationScore, 0.60)
    }

    func testSceneTypeTieCreatesAmbiguity() {
        let analyzer = SceneSemanticsAnalyzer()
        let snapshot = makeSnapshot(
            frameId: "sem-tie",
            composition: .init(
                horizontalOffset: 1.0,
                verticalOffset: 0.0,
                subjectAreaRatio: 0.30,
                saliencyLeftRightBalance: -1.0,
                saliencyTopBottomBalance: 0.0
            ),
            subjectSignals: .init(
                faceDetected: true,
                personDetected: true,
                personCount: 2,
                topObjectLabel: "book",
                topObjectConfidence: 0.42,
                primaryCandidateRegion: .init(x: 0.28, y: 0.18, width: 0.28, height: 0.48),
                primaryCandidateConfidence: 0.74
            ),
            objects: .init(totalCount: 3, topKLabels: ["book", "cup", "chair"])
        )

        let report = analyzer.analyze(snapshot: snapshot)
        XCTAssertTrue(report.ambiguities.contains { $0.type == .sceneTypeTie })
    }

    func testWeakSignalFallbackWithNoSources() {
        let analyzer = SceneSemanticsAnalyzer()
        let snapshot = makeSnapshot(
            frameId: "sem-weak",
            sources: .init(
                vision: .init(available: false),
                horizon: .init(available: false),
                lighting: .init(available: false),
                detr: .init(available: false),
                aesthetic: .init(available: false)
            ),
            subjectSignals: .init(
                faceDetected: false,
                personDetected: false,
                personCount: 0,
                topObjectLabel: nil,
                topObjectConfidence: nil,
                primaryCandidateRegion: nil,
                primaryCandidateConfidence: nil
            )
        )

        let report = analyzer.analyze(snapshot: snapshot)
        XCTAssertEqual(report.sceneType, .unknown)
        XCTAssertEqual(report.sceneTypeConfidence, 0)
        XCTAssertEqual(report.primarySubject.kind, .unknown)
        XCTAssertTrue(report.ambiguities.contains { $0.type == .weakSignal })
    }

    func testWeakSignalFallbackWhenVisionAndDetrAreUnavailableOnly() {
        let analyzer = SceneSemanticsAnalyzer()
        let snapshot = makeSnapshot(
            frameId: "sem-weak-vd",
            sources: .init(
                vision: .init(available: false),
                horizon: .init(available: true, freshnessMs: 10, confidence: 0.9),
                lighting: .init(available: true, freshnessMs: 10, confidence: 0.8),
                detr: .init(available: false),
                aesthetic: .init(available: true, freshnessMs: 20, confidence: 0.7)
            ),
            subjectSignals: .init(
                faceDetected: false,
                personDetected: false,
                personCount: 0,
                topObjectLabel: nil,
                topObjectConfidence: nil,
                primaryCandidateRegion: nil,
                primaryCandidateConfidence: nil
            )
        )

        let report = analyzer.analyze(snapshot: snapshot)
        XCTAssertEqual(report.sceneType, .unknown)
        XCTAssertEqual(report.sceneTypeConfidence, 0)
        XCTAssertTrue(report.ambiguities.contains { $0.type == .weakSignal })
    }

    func testEmptyFrameIdTriggersWeakSignalFallback() {
        let analyzer = SceneSemanticsAnalyzer()
        let snapshot = makeSnapshot(frameId: "")

        let report = analyzer.analyze(snapshot: snapshot)
        XCTAssertEqual(report.frameId, "unknown-frame")
        XCTAssertEqual(report.sceneType, .unknown)
        XCTAssertEqual(report.sceneTypeConfidence, 0)
        XCTAssertEqual(report.primarySubject.kind, .unknown)
        XCTAssertTrue(report.ambiguities.contains { $0.type == .weakSignal })
    }

    func testDegeneratePrimaryRegionAddsWeakSignalAmbiguity() {
        let analyzer = SceneSemanticsAnalyzer()
        let snapshot = makeSnapshot(
            frameId: "sem-degenerate",
            subjectSignals: .init(
                faceDetected: false,
                personDetected: false,
                personCount: 0,
                topObjectLabel: "watch",
                topObjectConfidence: 0.95,
                primaryCandidateRegion: .init(x: 0.5, y: 0.5, width: 0, height: 0.2),
                primaryCandidateConfidence: 0.9
            )
        )

        let report = analyzer.analyze(snapshot: snapshot)
        XCTAssertEqual(report.primarySubject.kind, .object)
        XCTAssertTrue(report.ambiguities.contains { $0.type == .weakSignal })
    }

    func testNonFinitePrimaryRegionAddsWeakSignalAmbiguity() {
        let analyzer = SceneSemanticsAnalyzer()
        let snapshot = makeSnapshot(
            frameId: "sem-nonfinite",
            subjectSignals: .init(
                faceDetected: false,
                personDetected: false,
                personCount: 0,
                topObjectLabel: "watch",
                topObjectConfidence: 0.95,
                primaryCandidateRegion: .init(x: .nan, y: 0.1, width: .infinity, height: 0.2),
                primaryCandidateConfidence: 0.9
            )
        )

        let report = analyzer.analyze(snapshot: snapshot)
        XCTAssertEqual(report.primarySubject.kind, .object)
        XCTAssertTrue(report.ambiguities.contains { $0.type == .weakSignal })
    }

    func testContractVersionMismatchFallbackAddsAssumption() {
        let analyzer = SceneSemanticsAnalyzer()
        let snapshot = makeSnapshot(
            frameId: "sem-contract-mismatch",
            subjectSignals: .init(
                faceDetected: true,
                personDetected: false,
                personCount: 1,
                topObjectLabel: nil,
                topObjectConfidence: nil,
                primaryCandidateRegion: .init(x: 0.2, y: 0.2, width: 0.3, height: 0.3),
                primaryCandidateConfidence: 0.9
            )
        )

        let report = analyzer.analyze(snapshot: snapshot)
        XCTAssertEqual(report.sceneType, .unknown)
        XCTAssertEqual(report.sceneTypeConfidence, 0.0)
        XCTAssertTrue(report.assumptions.contains { $0.id == "contract_version_mismatch" })
        XCTAssertTrue(report.ambiguities.contains { $0.type == .weakSignal })
    }

    func testHighMotionGuardKeepsReadableWhenSeparationIsNotLow() {
        let analyzer = SceneSemanticsAnalyzer()
        let snapshot = makeSnapshot(
            frameId: "sem-high-motion",
            composition: .init(
                horizontalOffset: 0.9,
                verticalOffset: 0.0,
                subjectAreaRatio: 0.22,
                saliencyLeftRightBalance: 0.1,
                saliencyTopBottomBalance: 0.0
            ),
            subjectSignals: .init(
                faceDetected: false,
                personDetected: true,
                personCount: 1,
                topObjectLabel: "chair",
                topObjectConfidence: 0.4,
                primaryCandidateRegion: .init(x: 0.95, y: 0.2, width: 0.04, height: 0.4),
                primaryCandidateConfidence: 0.85
            ),
            technicalFlags: [.highMotion]
        )

        let report = analyzer.analyze(snapshot: snapshot)
        XCTAssertGreaterThanOrEqual(report.readability.separationScore, 0.40)
        XCTAssertTrue(report.readability.subjectReadable)
    }

    func testGroupCandidatePolicyWhenMultiplePeopleAndNoPrimaryRegion() {
        let analyzer = SceneSemanticsAnalyzer()
        let snapshot = makeSnapshot(
            frameId: "sem-group",
            subjectSignals: .init(
                faceDetected: false,
                personDetected: true,
                personCount: 3,
                topObjectLabel: nil,
                topObjectConfidence: nil,
                primaryCandidateRegion: nil,
                primaryCandidateConfidence: nil
            )
        )

        let report = analyzer.analyze(snapshot: snapshot)
        XCTAssertEqual(report.primarySubject.kind, .group)
        XCTAssertGreaterThan(report.primarySubject.confidence, 0.2)
    }

    func testGroupCandidatePolicyWhenMultiplePeopleAndMalformedPrimaryRegion() {
        let analyzer = SceneSemanticsAnalyzer()
        let snapshot = makeSnapshot(
            frameId: "sem-group-malformed",
            subjectSignals: .init(
                faceDetected: false,
                personDetected: true,
                personCount: 3,
                topObjectLabel: nil,
                topObjectConfidence: nil,
                primaryCandidateRegion: .init(x: .nan, y: 0.2, width: .infinity, height: 0.3),
                primaryCandidateConfidence: 0.8
            )
        )

        let report = analyzer.analyze(snapshot: snapshot)
        XCTAssertEqual(report.primarySubject.kind, .group)
        XCTAssertTrue(report.ambiguities.contains { $0.type == .weakSignal })
    }

    func testDeterministicReplayForSameSnapshot() {
        let analyzer = SceneSemanticsAnalyzer()
        let snapshot = makeSnapshot(frameId: "sem-determinism")

        let first = analyzer.analyze(snapshot: snapshot)
        let second = analyzer.analyze(snapshot: snapshot)

        XCTAssertEqual(first, second)
    }

    func testLowSubjectConfidenceInvariantsProduceUnknownPrimarySubject() {
        let analyzer = SceneSemanticsAnalyzer()
        let snapshot = makeSnapshot(
            frameId: "sem-invariant",
            subjectSignals: .init(
                faceDetected: false,
                personDetected: false,
                personCount: 0,
                topObjectLabel: "cup",
                topObjectConfidence: 0.05,
                primaryCandidateRegion: nil,
                primaryCandidateConfidence: nil
            ),
            technicalFlags: [.lowSubjectConfidence, .lowSceneConfidence]
        )

        let report = analyzer.analyze(snapshot: snapshot)
        XCTAssertEqual(report.primarySubject.kind, .unknown)
        XCTAssertLessThan(report.primarySubject.confidence, 0.2)
        XCTAssertTrue(report.validate(expectedFrameId: snapshot.frameId).isEmpty)
    }
}

private extension SceneSemanticsAnalyzerTests {
    func makeSnapshot(frameId: String,
                      sources: FeatureSourceStatus = .init(
                        vision: .init(available: true, freshnessMs: 20, confidence: 0.9),
                        horizon: .init(available: true, freshnessMs: 22, confidence: 0.8),
                        lighting: .init(available: true, freshnessMs: 40, confidence: 0.7),
                        detr: .init(available: true, freshnessMs: 60, confidence: 0.85),
                        aesthetic: .init(available: true, freshnessMs: 120, confidence: 0.65)
                      ),
                      composition: FrameFeatureSnapshot.CompositionFeatures = .init(
                        horizontalOffset: 0,
                        verticalOffset: 0,
                        subjectAreaRatio: 0.15,
                        saliencyLeftRightBalance: 0,
                        saliencyTopBottomBalance: 0
                      ),
                      subjectSignals: FrameFeatureSnapshot.SubjectSignals = .init(
                        faceDetected: false,
                        personDetected: true,
                        personCount: 1,
                        topObjectLabel: "chair",
                        topObjectConfidence: 0.3,
                        primaryCandidateRegion: .init(x: 0.34, y: 0.18, width: 0.26, height: 0.5),
                        primaryCandidateConfidence: 0.85
                      ),
                      horizon: FrameFeatureSnapshot.HorizonFeatures = .init(angleDegrees: 0.5, confidence: 0.8),
                      lighting: FrameFeatureSnapshot.LightingFeatures = .init(exposureBiasHint: 0, backlightIndex: 0.2, keyToFillRatio: 1.1),
                      motion: FrameFeatureSnapshot.MotionFeatures = .init(state: .still, shakeLevel: 0.08),
                      aesthetics: FrameFeatureSnapshot.AestheticFeatures = .init(score: 0.62, scoreConfidence: 0.7),
                      objects: FrameFeatureSnapshot.ObjectDetectionsSummary = .init(totalCount: 2, topKLabels: ["chair", "table"]),
                      technicalFlags: [TechnicalFlag] = []) -> FrameFeatureSnapshot {
        FrameFeatureSnapshot(
            frameId: frameId,
            mode: .pause,
            capturedAt: Date(timeIntervalSince1970: 1_776_010_000),
            sources: sources,
            composition: composition,
            subjectSignals: subjectSignals,
            horizon: horizon,
            lighting: lighting,
            motion: motion,
            aesthetics: aesthetics,
            objects: objects,
            technicalFlags: technicalFlags
        )
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
