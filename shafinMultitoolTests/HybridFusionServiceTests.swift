import XCTest
@testable import shafinMultitool

final class HybridFusionServiceTests: XCTestCase {
    private let service = HybridFusionService()

    func testPauseFusionReordersStrengthsAndRebuildsSummary() {
        let snapshot = makeSnapshot(mode: .pause, frameId: "fusion-strengths")
        let semantics = makeSemantics(frameId: snapshot.frameId, mode: .pause)
        let critique = CritiqueReport(
            frameId: snapshot.frameId,
            mode: .pause,
            verdict: .good,
            verdictConfidence: 0.78,
            strengths: [
                makeStrength(id: "str_focus", type: .clearFocusHierarchy, confidence: 0.58, rationale: "Иерархия фокуса уже читается."),
                makeStrength(id: "str_isolation", type: .goodSubjectIsolation, confidence: 0.57, rationale: "Объект хорошо отделен от фона.")
            ],
            issues: [],
            summary: CritiqueSummary(
                id: "summary_\(snapshot.frameId)_main",
                shortVerdict: "Кадр читается стабильно, критичных проблем не выявлено.",
                whyGood: "Иерархия фокуса уже читается. Объект хорошо отделен от фона.",
                whyProblematic: nil
            ),
            traceRefs: [
                "trc_\(snapshot.frameId)_crit_s01",
                "trc_\(snapshot.frameId)_crit_s02",
                "trc_\(snapshot.frameId)_crit_summary_main"
            ],
            fallbackUsed: false
        )
        let neuralSnapshot = makeNeuralSnapshot(
            frameId: snapshot.frameId,
            mode: .pause,
            scalarOverrides: [
                .subjectProminence: (0.92, 0.88, .available),
                .backgroundClutter: (0.12, 0.79, .available),
                .balanceConfidence: (0.76, 0.71, .available),
                .depthSeparation: (0.82, 0.74, .available),
                .lightingQuality: (0.70, 0.68, .available),
                .faceSaliency: (0.85, 0.83, .available)
            ]
        )

        let output = service.fuse(
            HybridFusionInput(
                snapshot: snapshot,
                semantics: semantics,
                critique: critique,
                neuralSnapshot: neuralSnapshot,
                neuralMetadata: makeMetadata(frameId: snapshot.frameId, mode: .pause)
            )
        )

        XCTAssertEqual(output.critique.strengths.map(\.id), ["str_isolation", "str_focus"])
        XCTAssertEqual(
            output.critique.summary.whyGood,
            "Объект хорошо отделен от фона. Иерархия фокуса уже читается."
        )
        XCTAssertEqual(
            output.critique.traceRefs,
            ["trc_\(snapshot.frameId)_crit_s01", "trc_\(snapshot.frameId)_crit_s02", "trc_\(snapshot.frameId)_crit_summary_main"]
        )
        XCTAssertTrue(output.appliedDecisions.contains(where: { $0.targetId == "str_isolation" }))
    }

    func testIssueRankingChangesOnlyInsideExactSeverityTies() {
        let snapshot = makeSnapshot(mode: .pause, frameId: "fusion-issues")
        let semantics = makeSemantics(frameId: snapshot.frameId, mode: .pause)
        let critique = CritiqueReport(
            frameId: snapshot.frameId,
            mode: .pause,
            verdict: .needsFix,
            verdictConfidence: 0.74,
            strengths: [],
            issues: [
                makeIssue(id: "iss_major", type: .subjectTooCloseToEdge, severity: 0.82, confidence: 0.51, rationale: "Главный объект прижат к краю."),
                makeIssue(id: "iss_tied_a", type: .subjectNotProminentEnough, severity: 0.63, confidence: 0.55, rationale: "Главный объект недостаточно выделен."),
                makeIssue(id: "iss_tied_b", type: .backgroundCompetesWithSubject, severity: 0.63, confidence: 0.54, rationale: "Фон спорит с главным объектом.")
            ],
            summary: CritiqueSummary(
                id: "summary_\(snapshot.frameId)_main",
                shortVerdict: "Главный объект считывается с трудом, сначала исправьте приоритетные дефекты.",
                whyGood: nil,
                whyProblematic: "Главный объект прижат к краю. Главный объект недостаточно выделен."
            ),
            traceRefs: [
                "trc_\(snapshot.frameId)_crit_i01",
                "trc_\(snapshot.frameId)_crit_i02",
                "trc_\(snapshot.frameId)_crit_i03",
                "trc_\(snapshot.frameId)_crit_summary_main"
            ],
            fallbackUsed: false
        )
        let neuralSnapshot = makeNeuralSnapshot(
            frameId: snapshot.frameId,
            mode: .pause,
            scalarOverrides: [
                .subjectProminence: (0.18, 0.92, .available),
                .backgroundClutter: (0.86, 0.90, .available),
                .faceSaliency: (0.61, 0.77, .available),
                .balanceConfidence: (0.66, 0.70, .available),
                .depthSeparation: (0.25, 0.68, .available)
            ]
        )

        let output = service.fuse(
            HybridFusionInput(
                snapshot: snapshot,
                semantics: semantics,
                critique: critique,
                neuralSnapshot: neuralSnapshot,
                neuralMetadata: makeMetadata(frameId: snapshot.frameId, mode: .pause)
            )
        )

        XCTAssertEqual(output.critique.issues.first?.id, "iss_major")
        XCTAssertEqual(output.critique.issues.dropFirst().map(\.id), ["iss_tied_b", "iss_tied_a"])
    }

    func testExactSeverityTieStaysDeterministicWhenFusionDoesNotApply() {
        let snapshot = makeSnapshot(mode: .pause, frameId: "fusion-no-effective-tie")
        let semantics = makeSemantics(frameId: snapshot.frameId, mode: .pause)
        let critique = CritiqueReport(
            frameId: snapshot.frameId,
            mode: .pause,
            verdict: .mixed,
            verdictConfidence: 0.70,
            strengths: [],
            issues: [
                makeIssue(id: "iss_a", type: .backgroundCompetesWithSubject, severity: 0.63, confidence: 0.54, rationale: "Фон спорит с главным объектом."),
                makeIssue(id: "iss_b", type: .subjectNotProminentEnough, severity: 0.63, confidence: 0.55, rationale: "Главный объект недостаточно выделен.")
            ],
            summary: CritiqueSummary(
                id: "summary_\(snapshot.frameId)_main",
                shortVerdict: "Кадр рабочий, но есть зоны для улучшения композиции и читаемости.",
                whyGood: nil,
                whyProblematic: "Фон спорит с главным объектом. Главный объект недостаточно выделен."
            ),
            traceRefs: [
                "trc_\(snapshot.frameId)_crit_i01",
                "trc_\(snapshot.frameId)_crit_i02",
                "trc_\(snapshot.frameId)_crit_summary_main"
            ],
            fallbackUsed: false
        )
        let neuralSnapshot = makeNeuralSnapshot(
            frameId: snapshot.frameId,
            mode: .pause,
            scalarOverrides: [
                .subjectProminence: (0.50, 0.20, .available),
                .backgroundClutter: (0.50, 0.20, .available)
            ]
        )

        let output = service.fuse(
            HybridFusionInput(
                snapshot: snapshot,
                semantics: semantics,
                critique: critique,
                neuralSnapshot: neuralSnapshot,
                neuralMetadata: makeMetadata(frameId: snapshot.frameId, mode: .pause)
            )
        )

        XCTAssertEqual(output.critique.issues.map(\.id), ["iss_a", "iss_b"])
        XCTAssertFalse(output.appliedDecisions.contains(where: \.applied))
    }

    func testMissingNeuralSnapshotPreservesCritiqueExactly() {
        let snapshot = makeSnapshot(mode: .pause, frameId: "fusion-missing")
        let semantics = makeSemantics(frameId: snapshot.frameId, mode: .pause)
        let critique = makeDeterministicCritique(frameId: snapshot.frameId, mode: .pause)

        let output = service.fuse(
            HybridFusionInput(
                snapshot: snapshot,
                semantics: semantics,
                critique: critique,
                neuralSnapshot: nil,
                neuralMetadata: nil
            )
        )

        XCTAssertEqual(output.critique, critique)
        XCTAssertTrue(output.decisions.isEmpty)
    }

    func testDegradedFusionIgnoresPauseOnlyHeadsForHorizonIssue() {
        let snapshot = makeSnapshot(mode: .pause, frameId: "fusion-degraded")
        let semantics = makeSemantics(frameId: snapshot.frameId, mode: .pause)
        let critique = CritiqueReport(
            frameId: snapshot.frameId,
            mode: .pause,
            verdict: .mixed,
            verdictConfidence: 0.49,
            strengths: [],
            issues: [
                makeIssue(id: "iss_horizon", type: .horizonDistracts, severity: 0.46, confidence: 0.43, rationale: "Линия горизонта отвлекает."),
                makeIssue(id: "iss_subject", type: .subjectNotProminentEnough, severity: 0.44, confidence: 0.42, rationale: "Главный объект недостаточно выделен.")
            ],
            summary: CritiqueSummary(
                id: "summary_\(snapshot.frameId)_main",
                shortVerdict: "Кадр рабочий, но есть зоны для улучшения композиции и читаемости.",
                whyGood: nil,
                whyProblematic: "Линия горизонта отвлекает. Главный объект недостаточно выделен."
            ),
            traceRefs: [
                "trc_\(snapshot.frameId)_crit_i01",
                "trc_\(snapshot.frameId)_crit_i02",
                "trc_\(snapshot.frameId)_crit_summary_main"
            ],
            fallbackUsed: true
        )
        let neuralSnapshot = makeNeuralSnapshot(
            frameId: snapshot.frameId,
            mode: .pause,
            scalarOverrides: [
                .balanceConfidence: (0.91, 0.88, .available),
                .depthSeparation: (0.83, 0.74, .available),
                .subjectProminence: (0.33, 0.70, .available),
                .backgroundClutter: (0.52, 0.71, .available)
            ]
        )

        let output = service.fuse(
            HybridFusionInput(
                snapshot: snapshot,
                semantics: semantics,
                critique: critique,
                neuralSnapshot: neuralSnapshot,
                neuralMetadata: makeMetadata(frameId: snapshot.frameId, mode: .pause)
            )
        )

        let horizonIssue = output.critique.issues.first(where: { $0.id == "iss_horizon" })
        XCTAssertEqual(horizonIssue?.confidence ?? 0, 0.43, accuracy: 0.0001)
        XCTAssertEqual(output.critique.strengths, [])
    }

    func testPauseTraceBundleIncludesNeuralObservationsAndFusionMetadata() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let snapshot = makeSnapshot(mode: .pause, frameId: "fusion-trace")
        let semantics = makeSemantics(frameId: snapshot.frameId, mode: .pause)
        let critique = CritiqueReport(
            frameId: snapshot.frameId,
            mode: .pause,
            verdict: .mixed,
            verdictConfidence: 0.71,
            strengths: [],
            issues: [
                makeIssue(id: "iss_prominence", type: .subjectNotProminentEnough, severity: 0.63, confidence: 0.56, rationale: "Главный объект недостаточно выделен.")
            ],
            summary: CritiqueSummary(
                id: "summary_\(snapshot.frameId)_main",
                shortVerdict: "Кадр рабочий, но есть зоны для улучшения композиции и читаемости.",
                whyGood: nil,
                whyProblematic: "Главный объект недостаточно выделен."
            ),
            traceRefs: [
                "trc_\(snapshot.frameId)_crit_i01",
                "trc_\(snapshot.frameId)_crit_summary_main"
            ],
            fallbackUsed: false
        )
        let plan = RecommendationPlan(
            frameId: snapshot.frameId,
            mode: .pause,
            inputVerdict: .mixed,
            primaryAction: RecommendationAction(
                id: "act_1",
                actionType: .increaseSubjectSize,
                priority: 1,
                targetRegion: NormalizedRect(x: 0.3, y: 0.2, width: 0.3, height: 0.4),
                linkedIssueIds: ["iss_prominence"],
                expectedOutcome: "Подойдите ближе к главному объекту.",
                guardrail: ActionGuardrail(requiresStillCamera: false, minConfidence: 0.45, suppressWhenMoving: false),
                overlayHint: nil
            ),
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.79
        )
        let neuralSnapshot = makeNeuralSnapshot(
            frameId: snapshot.frameId,
            mode: .pause,
            scalarOverrides: [
                .subjectProminence: (0.19, 0.91, .available),
                .backgroundClutter: (0.84, 0.83, .available),
                .faceSaliency: (0.25, 0.75, .available),
                .depthSeparation: (0.21, 0.69, .available)
            ]
        )
        let recorded = NeuralEvidenceRecordedOutcome(
            .executed(snapshot: neuralSnapshot, metadata: makeMetadata(frameId: snapshot.frameId, mode: .pause))
        )

        let fusionOutput = pipeline.testingFuseCritique(
            snapshot: snapshot,
            semantics: semantics,
            critique: critique,
            recordedOutcome: recorded
        )
        let trace = pipeline.testingMakePauseTraceBundle(
            critique: fusionOutput.critique,
            plan: plan,
            neuralSnapshot: neuralSnapshot,
            fusionOutput: fusionOutput
        )

        let neuralItems = trace.items.filter { $0.sourceKind == .neuralEvidence }
        XCTAssertFalse(neuralItems.isEmpty)

        let issueItem = trace.items.first(where: {
            $0.links.contains(where: { $0.kind == .issue && $0.refId == "iss_prominence" })
        })
        XCTAssertEqual(issueItem?.metadata["fusionApplied"], "true")
        XCTAssertNotNil(issueItem?.metadata["fusionDelta"])
        XCTAssertTrue(issueItem?.dependsOn.contains(where: { depId in
            neuralItems.contains(where: { $0.id == depId })
        }) == true)

        let recommendationItem = trace.items.first(where: { $0.stage == .recommendation })
        XCTAssertNotNil(recommendationItem)
        XCTAssertFalse(recommendationItem?.dependsOn.contains(where: { depId in
            neuralItems.contains(where: { $0.id == depId })
        }) ?? true)
    }

    func testTraceMetadataUsesOriginalDeterministicConfidenceAtClampBoundary() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let snapshot = makeSnapshot(mode: .pause, frameId: "fusion-trace-clamp")
        let semantics = makeSemantics(frameId: snapshot.frameId, mode: .pause)
        let critique = CritiqueReport(
            frameId: snapshot.frameId,
            mode: .pause,
            verdict: .good,
            verdictConfidence: 0.83,
            strengths: [
                makeStrength(id: "str_clamped", type: .goodSubjectIsolation, confidence: 0.97, rationale: "Объект уже хорошо отделен от фона.")
            ],
            issues: [],
            summary: CritiqueSummary(
                id: "summary_\(snapshot.frameId)_main",
                shortVerdict: "Кадр читается стабильно, критичных проблем не выявлено.",
                whyGood: "Объект уже хорошо отделен от фона.",
                whyProblematic: nil
            ),
            traceRefs: [
                "trc_\(snapshot.frameId)_crit_s01",
                "trc_\(snapshot.frameId)_crit_summary_main"
            ],
            fallbackUsed: false
        )
        let plan = RecommendationPlan(
            frameId: snapshot.frameId,
            mode: .pause,
            inputVerdict: .good,
            primaryAction: nil,
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: "Кадр работает.",
            planConfidence: 0.82
        )
        let neuralSnapshot = makeNeuralSnapshot(
            frameId: snapshot.frameId,
            mode: .pause,
            scalarOverrides: [
                .subjectProminence: (0.98, 0.95, .available),
                .backgroundClutter: (0.01, 0.93, .available),
                .depthSeparation: (0.95, 0.88, .available)
            ]
        )

        let fusionOutput = service.fuse(
            HybridFusionInput(
                snapshot: snapshot,
                semantics: semantics,
                critique: critique,
                neuralSnapshot: neuralSnapshot,
                neuralMetadata: makeMetadata(frameId: snapshot.frameId, mode: .pause)
            )
        )
        let trace = pipeline.testingMakePauseTraceBundle(
            critique: fusionOutput.critique,
            plan: plan,
            neuralSnapshot: neuralSnapshot,
            fusionOutput: fusionOutput
        )

        let strengthItem = trace.items.first(where: {
            $0.links.contains(where: { $0.kind == .strength && $0.refId == "str_clamped" })
        })
        XCTAssertEqual(strengthItem?.metadata["deterministicConfidenceBefore"], "0.9700")
        XCTAssertEqual(strengthItem?.metadata["fusedConfidenceAfter"], "1.0000")
    }
}

private extension HybridFusionServiceTests {
    func makeSnapshot(mode: AnalysisMode, frameId: String) -> FrameFeatureSnapshot {
        FrameFeatureSnapshot(
            frameId: frameId,
            mode: mode,
            capturedAt: Date(timeIntervalSince1970: 1_776_000_000),
            sources: FeatureSourceStatus(
                vision: SourceState(available: true, freshnessMs: 30, confidence: 0.88),
                horizon: SourceState(available: true, freshnessMs: 30, confidence: 0.81),
                lighting: SourceState(available: true, freshnessMs: 30, confidence: 0.83),
                detr: SourceState(available: true, freshnessMs: 30, confidence: 0.79),
                aesthetic: SourceState(available: true, freshnessMs: 30, confidence: 0.70)
            ),
            composition: .init(
                horizontalOffset: 0.14,
                verticalOffset: 0.0,
                subjectAreaRatio: 0.16,
                saliencyLeftRightBalance: 0.08,
                saliencyTopBottomBalance: 0.0
            ),
            subjectSignals: .init(
                faceDetected: true,
                personDetected: true,
                personCount: 1,
                topObjectLabel: "person",
                topObjectConfidence: 0.86,
                primaryCandidateRegion: NormalizedRect(x: 0.32, y: 0.18, width: 0.26, height: 0.48),
                primaryCandidateConfidence: 0.83
            ),
            horizon: .init(angleDegrees: 1.0, confidence: 0.84),
            lighting: .init(exposureBiasHint: -0.04, backlightIndex: 0.30, keyToFillRatio: 1.1),
            motion: .init(state: .still, shakeLevel: 0.06),
            aesthetics: .init(score: 0.74, scoreConfidence: 0.68),
            objects: .init(totalCount: 3, topKLabels: ["person", "lamp", "wall"]),
            technicalFlags: []
        )
    }

    func makeSemantics(frameId: String, mode: AnalysisMode) -> SceneSemanticsReport {
        SceneSemanticsReport(
            frameId: frameId,
            mode: mode,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.82,
            primarySubject: .init(
                kind: .person,
                label: "person",
                region: NormalizedRect(x: 0.32, y: 0.18, width: 0.26, height: 0.48),
                confidence: 0.84
            ),
            dominance: .init(hasClearFocus: true, focusCompetitionScore: 0.28, backgroundClutterScore: 0.30),
            readability: .init(subjectReadable: true, lookSpaceAdequate: true, edgePressureScore: 0.18, separationScore: 0.71),
            ambiguities: [],
            assumptions: []
        )
    }

    func makeStrength(id: String,
                      type: StrengthTypeV1,
                      confidence: Double,
                      rationale: String) -> FrameStrength {
        FrameStrength(
            id: id,
            type: type,
            confidence: confidence,
            rationale: rationale,
            evidence: [EvidenceRef(source: .snapshot, key: "snapshot.\(type.rawValue)", value: "1")]
        )
    }

    func makeIssue(id: String,
                   type: IssueTypeV1,
                   severity: Double,
                   confidence: Double,
                   rationale: String) -> FrameIssue {
        FrameIssue(
            id: id,
            type: type,
            severity: severity,
            confidence: confidence,
            rationale: rationale,
            evidence: [EvidenceRef(source: .semantics, key: "semantics.\(type.rawValue)", value: "1")],
            affectedRegion: NormalizedRect(x: 0.3, y: 0.2, width: 0.25, height: 0.40),
            suggestedFixTypes: [.reframing]
        )
    }

    func makeDeterministicCritique(frameId: String, mode: AnalysisMode) -> CritiqueReport {
        CritiqueReport(
            frameId: frameId,
            mode: mode,
            verdict: .mixed,
            verdictConfidence: 0.68,
            strengths: [
                makeStrength(id: "str_1", type: .clearFocusHierarchy, confidence: 0.61, rationale: "Иерархия фокуса понятна.")
            ],
            issues: [
                makeIssue(id: "iss_1", type: .subjectNotProminentEnough, severity: 0.59, confidence: 0.55, rationale: "Главный объект недостаточно выделен.")
            ],
            summary: CritiqueSummary(
                id: "summary_\(frameId)_main",
                shortVerdict: "Кадр рабочий, но есть зоны для улучшения композиции и читаемости.",
                whyGood: "Иерархия фокуса понятна.",
                whyProblematic: "Главный объект недостаточно выделен."
            ),
            traceRefs: [
                "trc_\(frameId)_crit_i01",
                "trc_\(frameId)_crit_s01",
                "trc_\(frameId)_crit_summary_main"
            ],
            fallbackUsed: false
        )
    }

    func makeNeuralSnapshot(frameId: String,
                            mode: AnalysisMode,
                            scalarOverrides: [EvidenceHeadId: (Double, Double, EvidenceHeadStatus)],
                            shotTypeConfidence: Double = 0.0,
                            shotTypeStatus: EvidenceHeadStatus? = nil,
                            shotTypeAffinities: [EvidenceCategoryId: Double] = [:]) -> NeuralEvidenceSnapshot {
        let scalarHeadIds = EvidenceHeadId.allCases.filter { $0 != .shotTypeConfidence }
        let headOutputs = scalarHeadIds.map { headId -> NeuralEvidenceHeadEntry in
            let override = scalarOverrides[headId]
            let defaultStatus: EvidenceHeadStatus
            switch (mode, headId) {
            case (.live, .balanceConfidence), (.live, .depthSeparation), (.live, .cinematicExpressiveness):
                defaultStatus = .notApplicable
            case (.pause, _):
                defaultStatus = headId == .cinematicExpressiveness ? .unavailable : .unavailable
            case (.live, .faceSaliency):
                defaultStatus = .available
            default:
                defaultStatus = .available
            }

            let status = override?.2 ?? defaultStatus
            let score: Double? = status == .available ? (override?.0 ?? 0.50) : nil
            let confidence = status == .available ? (override?.1 ?? 0.60) : 0.0
            return NeuralEvidenceHeadEntry(
                headId: headId,
                payload: .scalar(
                    ScalarEvidenceHeadOutput(
                        headId: headId,
                        status: status,
                        score: score,
                        confidence: confidence,
                        mode: mode,
                        supportingSignals: []
                    )
                )
            )
        } + [
            NeuralEvidenceHeadEntry(
                headId: .shotTypeConfidence,
                payload: .categorical(
                    CategoricalEvidenceHeadOutput(
                        headId: .shotTypeConfidence,
                        status: shotTypeStatus ?? (mode == .live ? .notApplicable : .available),
                        affinities: (shotTypeStatus ?? (mode == .live ? .notApplicable : .available)) == .available
                            ? EvidenceCategoryId.allCases.map {
                                EvidenceCategoryScore(categoryId: $0, score: shotTypeAffinities[$0] ?? 0.0)
                            }
                            : [],
                        confidence: (shotTypeStatus ?? (mode == .live ? .notApplicable : .available)) == .available ? shotTypeConfidence : 0.0,
                        mode: mode,
                        supportingSignals: []
                    )
                )
            )
        ]

        return NeuralEvidenceSnapshot(
            schemaVersion: NeuralEvidenceSnapshot.currentSchemaVersion,
            frameId: frameId,
            mode: mode,
            capturedAt: Date(timeIntervalSince1970: 1_776_000_000),
            bundleVersion: "test-bundle",
            headOutputs: headOutputs
        )
    }

    func makeMetadata(frameId: String, mode: AnalysisMode) -> NeuralEvidenceRuntimeMetadata {
        NeuralEvidenceRuntimeMetadata(
            metadataSchemaVersion: NeuralEvidenceSnapshot.currentSchemaVersion,
            frameId: frameId,
            mode: mode,
            providerKind: .mock,
            inferenceTarget: .onDevice,
            modelFamily: "test",
            modelVersion: "1",
            preprocessingVersion: "1",
            thresholdProfile: mode == .live ? "live" : "pause",
            producedAt: Date(timeIntervalSince1970: 1_776_000_001),
            latencyMs: 12,
            roiStrategy: mode == .pause ? .fullFramePlusSubjectCrop : .fullFrameOnly,
            failureReason: nil
        )
    }
}
