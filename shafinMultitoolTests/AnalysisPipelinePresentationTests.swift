import XCTest
import CoreGraphics
import CoreVideo
import ImageIO
@testable import shafinMultitool

final class AnalysisPipelinePauseSnapshotTests: XCTestCase {
    func testExplicitPauseSnapshotUsesFreshDetrAndAestheticOverridesWithoutMutatingSharedState() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let timestamp = Date(timeIntervalSince1970: 1_768_500_000)
        let pauseState = PipelineFeatureSnapshotAdapterState(
            features: CoachingFeatures(),
            debugData: DebugData(),
            vision: nil,
            horizonMeasuredAt: nil,
            horizon: nil,
            lightingMeasuredAt: nil,
            lighting: nil,
            detr: FeatureSample(
                value: FeatureSnapshotDetrPayload(
                    detections: [
                        FeatureSnapshotDetectedObject(
                            boundingBox: CGRect(x: 0.22, y: 0.18, width: 0.31, height: 0.44),
                            label: "lamp",
                            confidence: 0.91
                        )
                    ]
                ),
                measuredAt: timestamp,
                baseConfidence: 0.91
            ),
            aestheticMeasuredAt: timestamp,
            aesthetic: FeatureSample(
                value: FeatureSnapshotAestheticPayload(score10: 8.2),
                measuredAt: timestamp,
                baseConfidence: nil
            )
        )

        let pauseSnapshot = pipeline.testingMakeFeatureSnapshot(
            mode: .pause,
            frameId: "pause-frame",
            capturedAt: timestamp,
            adapterState: pauseState
        )
        let liveSnapshot = pipeline.makeFeatureSnapshot(
            mode: .live,
            frameId: "live-frame",
            capturedAt: timestamp
        )

        XCTAssertEqual(pauseSnapshot.frameId, "pause-frame")
        XCTAssertEqual(pauseSnapshot.subjectSignals.topObjectLabel, "lamp")
        XCTAssertEqual(pauseSnapshot.objects.totalCount, 1)
        XCTAssertEqual(pauseSnapshot.aesthetics.score ?? 0, 0.82, accuracy: 0.0001)

        XCTAssertNil(liveSnapshot.subjectSignals.topObjectLabel)
        XCTAssertEqual(liveSnapshot.objects.totalCount, 0)
        XCTAssertNil(liveSnapshot.aesthetics.score)
    }

    func testExplicitEmptyDetrSampleSuppressesStaleDebugFallback() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let timestamp = Date(timeIntervalSince1970: 1_768_500_111)
        let staleDebugData = DebugData(
            detrDetections: [
                DETRDetection(
                    boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.25, height: 0.25),
                    label: "person",
                    confidence: 0.77
                )
            ],
            detrMeasuredAt: timestamp,
            visionSubjects: [],
            visionMeasuredAt: nil,
            saliencyCenter: nil
        )
        let overrideState = PipelineFeatureSnapshotAdapterState(
            features: CoachingFeatures(),
            debugData: staleDebugData,
            vision: nil,
            horizonMeasuredAt: nil,
            horizon: nil,
            lightingMeasuredAt: nil,
            lighting: nil,
            detr: FeatureSample(
                value: FeatureSnapshotDetrPayload(detections: []),
                measuredAt: timestamp,
                baseConfidence: 0
            ),
            aestheticMeasuredAt: nil,
            aesthetic: nil
        )

        let snapshot = pipeline.testingMakeFeatureSnapshot(
            mode: .pause,
            frameId: "pause-empty-detr",
            capturedAt: timestamp,
            adapterState: overrideState
        )

        XCTAssertNil(snapshot.subjectSignals.topObjectLabel)
        XCTAssertEqual(snapshot.objects.totalCount, 0)
    }
}

final class AnalysisPipelinePresentationTests: XCTestCase {
    func testConfidencePresentationMapsUserFacingBands() {
        XCTAssertEqual(ConfidencePresentation.make(0.91).label, "высокая")
        XCTAssertEqual(ConfidencePresentation.make(0.91).percent, 91)
        XCTAssertEqual(ConfidencePresentation.make(0.64).label, "средняя")
        XCTAssertEqual(ConfidencePresentation.make(0.31).label, "низкая")
        XCTAssertEqual(ConfidencePresentation.make(1.42).percent, 100)
        XCTAssertEqual(ConfidencePresentation.make(-0.4).percent, 0)
    }

    func testPauseActionConfidenceIsCappedByPlanAndLinkedIssue() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let critique = makeCritique(frameId: "pause-confidence", verdict: .mixed)
        let action = RecommendationAction(
            id: "act_1",
            actionType: .moveFrameLeft,
            priority: 1,
            targetRegion: nil,
            linkedIssueIds: ["iss_1"],
            expectedOutcome: "Сместите камеру левее.",
            guardrail: ActionGuardrail(requiresStillCamera: true, minConfidence: 0.4, suppressWhenMoving: true),
            overlayHint: nil
        )
        let plan = RecommendationPlan(
            frameId: critique.frameId,
            mode: .live,
            inputVerdict: critique.verdict,
            primaryAction: action,
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.80
        )

        let confidence = pipeline.testingPauseActionConfidence(action: action, plan: plan, critique: critique)

        XCTAssertEqual(confidence, 0.80, accuracy: 0.0001)
    }

    func testPauseActionConfidenceCanUseSemanticTipIssueScope() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let critique = makeCritiqueWithTwoIssues(frameId: "pause-semantic-confidence")
        let action = RecommendationAction(
            id: "act_1",
            actionType: .moveFrameLeft,
            priority: 1,
            targetRegion: nil,
            linkedIssueIds: ["iss_high"],
            expectedOutcome: "Сместите камеру левее.",
            guardrail: ActionGuardrail(requiresStillCamera: true, minConfidence: 0.4, suppressWhenMoving: true),
            overlayHint: nil
        )
        let plan = RecommendationPlan(
            frameId: critique.frameId,
            mode: .pause,
            inputVerdict: critique.verdict,
            primaryAction: action,
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.90
        )

        let confidence = pipeline.testingPauseActionConfidence(
            action: action,
            plan: plan,
            critique: critique,
            linkedIssueIds: ["iss_low"]
        )

        XCTAssertEqual(confidence, 0.50, accuracy: 0.0001)
    }

    func testLiveActionConfidenceDoesNotUseOptimisticMaximum() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let critique = makeCritique(frameId: "live-confidence", verdict: .mixed)
        let action = RecommendationAction(
            id: "act_1",
            actionType: .moveFrameLeft,
            priority: 1,
            targetRegion: nil,
            linkedIssueIds: ["iss_1"],
            expectedOutcome: "Сместите камеру левее.",
            guardrail: ActionGuardrail(requiresStillCamera: true, minConfidence: 0.4, suppressWhenMoving: true),
            overlayHint: nil
        )
        let plan = RecommendationPlan(
            frameId: critique.frameId,
            mode: .live,
            inputVerdict: critique.verdict,
            primaryAction: action,
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.95
        )

        let confidence = pipeline.testingLiveActionConfidence(action: action, plan: plan, critique: critique)

        XCTAssertEqual(confidence, critique.verdictConfidence, accuracy: 0.0001)
        XCTAssertLessThan(confidence, plan.planConfidence)
    }

    func testPipelineStoresRecordedNeuralEvidenceOutcome() async {
        let service = NeuralEvidenceInferenceService(
            configuration: makeEnabledNeuralConfiguration(),
            provider: MockNeuralEvidenceProvider { _ in
                self.makeNeuralProviderOutput()
            }
        )
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            neuralEvidenceService: service,
            thermalGovernor: ThermalGovernor(
                thermalStateProvider: { .nominal },
                batteryLevelProvider: { 1.0 }
            ),
            neuralHeavyModelsEnabledProvider: { true }
        )
        let timestamp = Date(timeIntervalSince1970: 1_771_200_000)
        let snapshot = pipeline.testingMakeFeatureSnapshot(
            mode: .live,
            frameId: "neural-live-frame",
            capturedAt: timestamp,
            adapterState: PipelineFeatureSnapshotAdapterState(
                features: CoachingFeatures(),
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
        let semantics = SceneSemanticsReport(
            frameId: snapshot.frameId,
            mode: .live,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.8,
            primarySubject: .init(kind: .person, confidence: 0.81),
            dominance: .init(hasClearFocus: true, focusCompetitionScore: 0.2, backgroundClutterScore: 0.25),
            readability: .init(subjectReadable: true, lookSpaceAdequate: true, edgePressureScore: 0.18, separationScore: 0.66),
            ambiguities: [],
            assumptions: []
        )

        let recorded = await pipeline.testingRunNeuralEvidenceInference(
            mode: .live,
            pixelBuffer: self.makePixelBuffer(width: 32, height: 32),
            orientation: .up,
            snapshot: snapshot,
            semantics: semantics,
            isStable: true,
            thermalTier: .unrestricted,
            heavyModelsEnabled: true,
            batteryLevel: 1.0
        )

        XCTAssertEqual(recorded?.kind, .executed)
        XCTAssertEqual(pipeline.testingLatestLiveNeuralOutcome?.kind, .executed)
        XCTAssertEqual(pipeline.testingLatestLiveNeuralOutcome?.snapshot?.frameId, snapshot.frameId)
    }

    func testLiveHybridFusionAwaitsCurrentFrameNeuralOutcome() async {
        let service = NeuralEvidenceInferenceService(
            configuration: makeEnabledNeuralConfiguration(),
            provider: MockNeuralEvidenceProvider { _ in
                self.makeLiveFusionProviderOutput()
            }
        )
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            neuralEvidenceService: service,
            thermalGovernor: ThermalGovernor(
                thermalStateProvider: { .nominal },
                batteryLevelProvider: { 1.0 }
            ),
            neuralHeavyModelsEnabledProvider: { true }
        )
        let timestamp = Date(timeIntervalSince1970: 1_771_200_100)
        let snapshot = pipeline.testingMakeFeatureSnapshot(
            mode: .live,
            frameId: "neural-live-fused-frame",
            capturedAt: timestamp,
            adapterState: PipelineFeatureSnapshotAdapterState(
                features: CoachingFeatures(),
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
        let semantics = SceneSemanticsReport(
            frameId: snapshot.frameId,
            mode: .live,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.8,
            primarySubject: .init(kind: .person, confidence: 0.81),
            dominance: .init(hasClearFocus: true, focusCompetitionScore: 0.2, backgroundClutterScore: 0.25),
            readability: .init(subjectReadable: true, lookSpaceAdequate: true, edgePressureScore: 0.18, separationScore: 0.66),
            ambiguities: [],
            assumptions: []
        )
        let deterministicCritique = CritiqueReport(
            frameId: snapshot.frameId,
            mode: .live,
            verdict: .mixed,
            verdictConfidence: 0.73,
            strengths: [],
            issues: [
                FrameIssue(
                    id: "iss_live_prominence",
                    type: .subjectNotProminentEnough,
                    severity: 0.58,
                    confidence: 0.55,
                    rationale: "Главный объект недостаточно выделен.",
                    evidence: [EvidenceRef(source: .semantics, key: "semantics.readability.separationScore", value: "0.66")],
                    affectedRegion: NormalizedRect(x: 0.3, y: 0.2, width: 0.3, height: 0.4),
                    suggestedFixTypes: [.reframing]
                )
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

        let (fusionOutput, recordedOutcome) = await pipeline.testingResolveCritiqueWithHybridFusion(
            mode: .live,
            capturedAt: timestamp,
            pixelBuffer: makePixelBuffer(width: 32, height: 32),
            orientation: .up,
            snapshot: snapshot,
            semantics: semantics,
            deterministicCritique: deterministicCritique,
            forcePauseExecution: false
        )

        XCTAssertNotNil(recordedOutcome)
        XCTAssertEqual(recordedOutcome?.snapshot?.frameId, snapshot.frameId)
        XCTAssertTrue(
            fusionOutput.appliedDecisions.contains(where: { $0.targetId == "iss_live_prominence" })
                || recordedOutcome?.kind == .policySkipped
        )
        XCTAssertGreaterThanOrEqual(
            fusionOutput.critique.issues.first(where: { $0.id == "iss_live_prominence" })?.confidence ?? 0,
            deterministicCritique.issues[0].confidence
        )
    }

    func testLiveStructuredPathPublishesMatchingHintAndExpandedCritique() async {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let critique = makeCritique(frameId: "live-structured", verdict: .good)
        let plan = RecommendationPlan(
            frameId: critique.frameId,
            mode: .live,
            inputVerdict: critique.verdict,
            primaryAction: nil,
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: "Кадр выглядит уверенно.",
            planConfidence: 0.84
        )

        await MainActor.run {
            pipeline.testingPublishLivePresentation(
                frameId: critique.frameId,
                critique: critique,
                plan: plan,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: Date(timeIntervalSince1970: 1_768_500_200)
            )
        }

        await MainActor.run {
            XCTAssertEqual(pipeline.currentLiveHint?.frameId, critique.frameId)
            XCTAssertEqual(pipeline.currentLiveHint?.expandedVerdict?.shortVerdict, critique.summary.shortVerdict)
            XCTAssertFalse(pipeline.testingHasPauseReasoningTask)
        }
    }

    func testLiveFallbackClearsExpandedCritique() async {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let critique = makeCritique(frameId: "live-fallback", verdict: .mixed)
        let plan = RecommendationPlan(
            frameId: critique.frameId,
            mode: .live,
            inputVerdict: critique.verdict,
            primaryAction: nil,
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.42
        )
        let fallbackSuggestion = Suggestion(
            text: "Сместите кадр чуть левее.",
            priority: .important,
            type: .composition,
            ttl: 4.0,
            createdAt: Date(timeIntervalSince1970: 1_768_500_310)
        )

        await MainActor.run {
            pipeline.testingPublishLivePresentation(
                frameId: critique.frameId,
                critique: makeCritique(frameId: critique.frameId, verdict: .good),
                plan: RecommendationPlan(
                    frameId: critique.frameId,
                    mode: .live,
                    inputVerdict: .good,
                    primaryAction: nil,
                    secondaryActions: [],
                    deferredActions: [],
                    noChangeRationale: "Кадр работает.",
                    planConfidence: 0.8
                ),
                legacySuggestion: nil,
                structuredAvailable: true,
                now: Date(timeIntervalSince1970: 1_768_500_300)
            )
            pipeline.testingPublishLivePresentation(
                frameId: critique.frameId,
                critique: critique,
                plan: plan,
                legacySuggestion: fallbackSuggestion,
                structuredAvailable: false,
                now: Date(timeIntervalSince1970: 1_768_500_302)
            )
        }

        await MainActor.run {
            XCTAssertTrue(pipeline.currentLiveHint?.isFallback == true)
            XCTAssertEqual(pipeline.currentLiveHint?.text, fallbackSuggestion.text)
            XCTAssertEqual(pipeline.currentLiveHint?.expandedVerdict?.shortVerdict, critique.summary.shortVerdict)
            XCTAssertFalse(pipeline.testingHasPauseReasoningTask)
        }
    }

    func testTextOnlyLiveRefreshKeepsStableIdentityButUpdatesCurrentPayload() async {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let initial = LiveHintPresentation(
            id: "lh_live_action_moveFrameLeft_subjectTooCloseToEdge_0.62_0.16_0.24_0.48",
            frameId: "frame-1",
            text: "Сместите кадр чуть левее.",
            confidence: 0.61,
            actionType: .moveFrameLeft,
            actionId: "act_frame_1",
            linkedIssueIds: ["iss_1"],
            summaryId: "summary_frame_1",
            traceRootIds: ["trace_frame_1"],
            targetRegion: NormalizedRect(x: 0.68, y: 0.16, width: 0.24, height: 0.48),
            overlayHint: OverlayHint(id: "ovh_frame_1", kind: .arrow, targetRegion: nil, direction: .left),
            isFallback: false,
            expandedVerdict: LiveExpandedVerdictPresentation(
                shortVerdict: "Кадр требует правки.",
                supportingText: "Главный объект упирается в край.",
                actionText: "Сместите кадр чуть левее.",
                fallbackUsed: false
            )
        )
        let refreshed = LiveHintPresentation(
            id: "lh_live_action_moveFrameLeft_subjectTooCloseToEdge_0.22_0.16_0.22_0.44",
            frameId: "frame-2",
            text: "Сместите героя чуть левее.",
            confidence: 0.66,
            actionType: .moveFrameLeft,
            actionId: "act_frame_2",
            linkedIssueIds: ["iss_2"],
            summaryId: "summary_frame_2",
            traceRootIds: ["trace_frame_2"],
            targetRegion: NormalizedRect(x: 0.22, y: 0.16, width: 0.22, height: 0.44),
            overlayHint: OverlayHint(id: "ovh_frame_2", kind: .arrow, targetRegion: nil, direction: .left),
            isFallback: false,
            expandedVerdict: LiveExpandedVerdictPresentation(
                shortVerdict: "Кадр требует правки.",
                supportingText: "Герой потерял воздух слева.",
                actionText: "Сместите героя чуть левее.",
                fallbackUsed: false
            )
        )

        await MainActor.run {
            pipeline.testingApplyLiveHintCandidate(
                initial,
                now: Date(timeIntervalSince1970: 1_768_500_400)
            )
            pipeline.testingApplyLiveHintCandidate(
                refreshed,
                now: Date(timeIntervalSince1970: 1_768_500_700)
            )
        }

        await MainActor.run {
            XCTAssertEqual(pipeline.currentLiveHint?.id, initial.id)
            XCTAssertEqual(pipeline.currentLiveHint?.frameId, refreshed.frameId)
            XCTAssertEqual(pipeline.currentLiveHint?.actionId, refreshed.actionId)
            XCTAssertEqual(pipeline.currentLiveHint?.linkedIssueIds, refreshed.linkedIssueIds)
            XCTAssertEqual(pipeline.currentLiveHint?.targetRegion, refreshed.targetRegion)
            XCTAssertEqual(pipeline.currentLiveHint?.overlayHint?.id, refreshed.overlayHint?.id)
            XCTAssertEqual(pipeline.currentLiveHint?.text, refreshed.text)
        }
    }

    private func makeCritique(frameId: String, verdict: FrameVerdict) -> CritiqueReport {
        CritiqueReport(
            frameId: frameId,
            mode: .live,
            verdict: verdict,
            verdictConfidence: 0.82,
            strengths: verdict == .good ? [
                FrameStrength(
                    id: "str_1",
                    type: .clearFocusHierarchy,
                    confidence: 0.85,
                    rationale: "Главный субъект читается сразу.",
                    evidence: [EvidenceRef(source: .snapshot, key: "subject.primary", value: "dominant")]
                )
            ] : [],
            issues: verdict == .good ? [] : [
                FrameIssue(
                    id: "iss_1",
                    type: .subjectTooCloseToEdge,
                    severity: 0.71,
                    confidence: 0.78,
                    rationale: "Субъект прижат к краю и теряет баланс.",
                    evidence: [EvidenceRef(source: .snapshot, key: "composition.horizontalOffset", value: "0.86")],
                    affectedRegion: NormalizedRect(x: 0.68, y: 0.16, width: 0.24, height: 0.48),
                    suggestedFixTypes: [.reframing]
                )
            ],
            summary: CritiqueSummary(
                id: "summary_\(frameId)",
                shortVerdict: verdict == .good ? "Кадр работает." : "Кадр требует правки.",
                whyGood: verdict == .good ? "Фокус и баланс читаются уверенно." : nil,
                whyProblematic: verdict == .good ? nil : "Баланс нарушен, главный объект тесно прижат к краю."
            ),
            traceRefs: ["trace_\(frameId)"],
            fallbackUsed: false
        )
    }

    private func makeCritiqueWithTwoIssues(frameId: String) -> CritiqueReport {
        CritiqueReport(
            frameId: frameId,
            mode: .pause,
            verdict: .mixed,
            verdictConfidence: 0.88,
            strengths: [],
            issues: [
                FrameIssue(
                    id: "iss_high",
                    type: .subjectTooCloseToEdge,
                    severity: 0.80,
                    confidence: 0.95,
                    rationale: "Сильная проблема композиции.",
                    evidence: [EvidenceRef(source: .snapshot, key: "composition.edge", value: "high")],
                    affectedRegion: nil,
                    suggestedFixTypes: [.reframing]
                ),
                FrameIssue(
                    id: "iss_low",
                    type: .backgroundCompetesWithSubject,
                    severity: 0.60,
                    confidence: 0.40,
                    rationale: "Фон может спорить с субъектом.",
                    evidence: [EvidenceRef(source: .snapshot, key: "background.competition", value: "medium")],
                    affectedRegion: nil,
                    suggestedFixTypes: [.declutter]
                )
            ],
            summary: CritiqueSummary(
                id: "summary_\(frameId)",
                shortVerdict: "Кадр требует проверки.",
                whyGood: nil,
                whyProblematic: "Есть несколько проблем разной уверенности."
            ),
            traceRefs: ["trace_\(frameId)"],
            fallbackUsed: false
        )
    }

    private func makeEnabledNeuralConfiguration() -> NeuralEvidenceInferenceConfiguration {
        var configuration = NeuralEvidenceInferenceConfiguration.disabled
        configuration.featureEnabled = true
        configuration.liveModeEnabled = true
        configuration.pauseModeEnabled = true
        return configuration
    }

    private func makeNeuralProviderOutput() -> NeuralEvidenceProviderOutput {
        let row: [Double] = [
            0.81, 0.74, 0.68, 0.15, 0.11, 0.07, 0.06,
            0.76, 0.24, 0.67, 0.69, 0.63, 0.53, 0.21,
            0.57, 0.61, 0.64, 0.44, 0.28, 0.56, 0.73
        ]
        return NeuralEvidenceProviderOutput(
            scalarScores: [0.71, 0.33, 0.64, 0.77, 0.58, 0.55, 0.51],
            scalarConfidences: [0.81, 0.74, 0.71, 0.76, 0.66, 0.63, 0.60],
            supportingSignalScores: Array(repeating: row, count: 7),
            shotTypeAffinities: [0.71, 0.29, 0.16, 0.14, 0.11, 0.19, 0.18],
            shotTypeConfidence: 0.61,
            actualROIStrategy: .fullFrameOnly
        )
    }

    private func makeLiveFusionProviderOutput() -> NeuralEvidenceProviderOutput {
        let row: [Double] = Array(repeating: 0.7, count: 21)
        return NeuralEvidenceProviderOutput(
            scalarScores: [0.12, 0.84, 0.62, 0.24, 0.0, 0.0, 0.0],
            scalarConfidences: [0.90, 0.88, 0.82, 0.79, 0.0, 0.0, 0.0],
            supportingSignalScores: Array(repeating: row, count: 7),
            shotTypeAffinities: [0, 0, 0, 0, 0, 0, 0],
            shotTypeConfidence: 0.0,
            actualROIStrategy: .fullFrameOnly
        )
    }

    private func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        guard let pixelBuffer else {
            fatalError("Failed to create test pixel buffer")
        }
        return pixelBuffer
    }
}
