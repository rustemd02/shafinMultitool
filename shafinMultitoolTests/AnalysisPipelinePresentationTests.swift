import XCTest
import CoreGraphics
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
            XCTAssertEqual(pipeline.testingCurrentLiveExpandedCritique?.frameId, critique.frameId)
            XCTAssertEqual(pipeline.testingCurrentLiveExpandedCritique?.shortVerdict, critique.summary.shortVerdict)
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
            XCTAssertNil(pipeline.testingCurrentLiveExpandedCritique)
            XCTAssertTrue(pipeline.currentLiveHint?.isFallback == true)
            XCTAssertEqual(pipeline.currentLiveHint?.text, fallbackSuggestion.text)
            XCTAssertFalse(pipeline.testingHasPauseReasoningTask)
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
}
