import XCTest
import CoreMedia
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

    func testFeatureSnapshotCarriesDemoObjectRegionAheadOfBackgroundObjects() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let timestamp = Date(timeIntervalSince1970: 1_768_500_222)
        let cupBox = CGRect(x: 0.10, y: 0.30, width: 0.18, height: 0.34)
        let state = PipelineFeatureSnapshotAdapterState(
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
                            boundingBox: CGRect(x: 0.40, y: 0.18, width: 0.42, height: 0.52),
                            label: "chair",
                            confidence: 0.95
                        ),
                        FeatureSnapshotDetectedObject(
                            boundingBox: cupBox,
                            label: "cup",
                            confidence: 0.72
                        )
                    ]
                ),
                measuredAt: timestamp,
                baseConfidence: 0.82
            ),
            aestheticMeasuredAt: nil,
            aesthetic: nil
        )

        let snapshot = pipeline.testingMakeFeatureSnapshot(
            mode: .live,
            frameId: "demo-cup-region",
            capturedAt: timestamp,
            adapterState: state
        )

        XCTAssertEqual(snapshot.subjectSignals.topObjectLabel, "cup")
        XCTAssertEqual(
            snapshot.subjectSignals.topObjectRegion,
            NormalizedRect(x: cupBox.minX, y: cupBox.minY, width: cupBox.width, height: cupBox.height)
        )
        XCTAssertEqual(snapshot.objects.topKLabels.first, "cup")
    }
}

final class AnalysisPipelinePresentationTests: XCTestCase {
    func testSemanticEvalOutputEncodesLiveAndPauseRowsWithClosedCatalogActions() throws {
        let liveHint = LiveHintPresentation(
            id: "lh_runtime_042",
            frameId: "frame-runtime-live",
            text: "Камеру чуть правее.",
            confidence: 0.72,
            actionType: .moveFrameRight,
            actionId: "act_live_right",
            linkedIssueIds: ["iss_edge"],
            summaryId: "summary_live",
            traceRootIds: ["trace_live"],
            targetRegion: nil,
            overlayHint: nil,
            isFallback: false,
            expandedVerdict: nil
        )

        let liveRow = SemanticEvalCandidateOutput.live(
            recordId: "ca_img_042",
            filename: "042.jpg",
            hint: liveHint,
            source: "swift_runtime_projection",
            runtimeClaim: .realRuntimeStillReplay
        )

        XCTAssertEqual(liveRow.recordId, "ca_img_042")
        XCTAssertEqual(liveRow.filename, "042.jpg")
        XCTAssertEqual(liveRow.mode, "live")
        XCTAssertTrue(liveRow.shown)
        XCTAssertEqual(liveRow.liveTip, "Камеру чуть правее.")
        XCTAssertNil(liveRow.pauseSummary)
        XCTAssertEqual(liveRow.semanticActions, ["shift_frame_right"])
        XCTAssertEqual(liveRow.futureActions, [])
        XCTAssertEqual(liveRow.confidence, 0.72, accuracy: 0.0001)
        XCTAssertEqual(liveRow.traceIds, ["trace_live"])

        let pauseCritique = PauseCritiquePresentation(
            frameId: "frame-runtime-pause",
            verdict: .mixed,
            verdictConfidence: 0.74,
            summaryId: "summary_pause",
            shortVerdict: "Кадру нужен мягкий свет и чище фон.",
            whyGood: nil,
            whyProblematic: "Лицо теряется, а фон спорит с субъектом.",
            strengths: [],
            issues: [],
            actions: [
                PauseActionRow(
                    actionId: "act_fill",
                    actionType: .improveFrontLight,
                    semanticActionType: .addFrontFillLight,
                    priority: 1,
                    confidence: 0.81,
                    linkedIssueIds: ["iss_light"],
                    expectedOutcome: "Лицо станет читаемее.",
                    targetRegion: nil,
                    overlayHintId: nil,
                    traceRefId: "trace_fill"
                ),
                PauseActionRow(
                    actionId: "act_bg",
                    actionType: .reduceBackgroundDistractions,
                    semanticActionType: .simplifyBackground,
                    priority: 2,
                    confidence: 0.67,
                    linkedIssueIds: ["iss_background"],
                    expectedOutcome: "Фон перестанет конкурировать.",
                    targetRegion: nil,
                    overlayHintId: nil,
                    traceRefId: "trace_bg"
                )
            ],
            noChangeRationale: nil,
            assumptions: [],
            traceRootIds: ["trace_pause"],
            fallbackUsed: false
        )

        let pauseRow = SemanticEvalCandidateOutput.pause(
            recordId: "ca_img_043",
            filename: "043.jpg",
            critique: pauseCritique,
            source: "swift_runtime_projection",
            runtimeClaim: .realRuntimeStillReplay
        )

        XCTAssertEqual(pauseRow.mode, "pause")
        XCTAssertTrue(pauseRow.shown)
        XCTAssertNil(pauseRow.liveTip)
        XCTAssertEqual(pauseRow.pauseSummary, "Кадру нужен мягкий свет и чище фон.")
        XCTAssertEqual(pauseRow.semanticActions, ["add_front_fill_light", "simplify_background"])
        XCTAssertEqual(pauseRow.confidence, 0.74, accuracy: 0.0001)
        XCTAssertEqual(pauseRow.traceIds, ["trace_pause"])

        let encoded = try String(data: JSONEncoder().encode(liveRow), encoding: .utf8)
        XCTAssertNotNil(encoded)
        XCTAssertTrue(encoded?.contains("\"record_id\":\"ca_img_042\"") == true)
        XCTAssertTrue(encoded?.contains("\"runtime_claim\":\"real_runtime_still_replay\"") == true)
        XCTAssertTrue(encoded?.contains("\"semantic_actions\":[\"shift_frame_right\"]") == true)
    }

    func testSemanticEvalPauseGoodVerdictExportsKeepCurrentSetup() {
        let pauseCritique = PauseCritiquePresentation(
            frameId: "frame-good-pause",
            verdict: .good,
            verdictConfidence: 0.82,
            summaryId: "summary_good",
            shortVerdict: "Кадр читается хорошо.",
            whyGood: "Субъект отделен светом и композицией.",
            whyProblematic: nil,
            strengths: [
                PauseStrengthRow(
                    strengthId: "str_good",
                    type: .clearFocusHierarchy,
                    rationale: "Фокус внимания понятен.",
                    confidence: 0.80,
                    supportingRegion: nil,
                    traceRefId: "trace_strength"
                )
            ],
            issues: [],
            actions: [],
            noChangeRationale: "Оставьте кадр как есть.",
            assumptions: [],
            traceRootIds: ["trace_good"],
            fallbackUsed: false
        )

        let pauseRow = SemanticEvalCandidateOutput.pause(
            recordId: "ca_img_good",
            filename: "good.jpg",
            critique: pauseCritique,
            source: "swift_runtime_projection",
            runtimeClaim: .realRuntimeStillReplay
        )

        XCTAssertTrue(pauseRow.shown)
        XCTAssertEqual(pauseRow.semanticActions, ["keep_current_setup"])
        XCTAssertEqual(pauseRow.confidence, 0.82, accuracy: 0.0001)
    }

    func testSemanticEvalPauseExportsSemanticTipActionInsteadOfCoarseTransportAction() {
        let pauseCritique = PauseCritiquePresentation(
            frameId: "frame-hotspot-pause",
            verdict: .mixed,
            verdictConfidence: 0.71,
            summaryId: "summary_hotspot",
            shortVerdict: "Яркое пятно на фоне спорит с лицом.",
            whyGood: nil,
            whyProblematic: "Фоновый свет перетягивает внимание.",
            strengths: [],
            issues: [],
            actions: [
                PauseActionRow(
                    actionId: "act_hotspot",
                    actionType: .improveFrontLight,
                    semanticActionType: .removeBackgroundHotspot,
                    priority: 1,
                    confidence: 0.73,
                    linkedIssueIds: ["iss_hotspot"],
                    expectedOutcome: "Приглушите яркое пятно за героем.",
                    targetRegion: nil,
                    overlayHintId: nil,
                    traceRefId: "trace_hotspot"
                )
            ],
            noChangeRationale: nil,
            assumptions: [],
            traceRootIds: ["trace_hotspot_root"],
            fallbackUsed: false
        )

        let pauseRow = SemanticEvalCandidateOutput.pause(
            recordId: "ca_img_hotspot",
            filename: "hotspot.jpg",
            critique: pauseCritique,
            source: "swift_runtime_projection",
            runtimeClaim: .realRuntimeStillReplay
        )

        XCTAssertEqual(pauseRow.semanticActions, ["remove_background_hotspot"])
        XCTAssertEqual(pauseRow.debugActionTypes, ["improve_front_light"])
    }

    func testSemanticEvalLiveDropsLeaveAsIsForDominantTechnicalFutureAction() {
        let hint = LiveHintPresentation(
            id: "lh_live_blur_keep",
            frameId: "frame-live-blurry",
            text: "Кадр читается стабильно, критичных проблем не выявлено.",
            confidence: 0.74,
            actionType: .leaveFrameAsIs,
            actionId: "act_live_keep",
            linkedIssueIds: [],
            summaryId: "summary_live_keep",
            traceRootIds: ["trace_live"],
            targetRegion: nil,
            overlayHint: nil,
            isFallback: false,
            expandedVerdict: nil
        )

        let liveRow = SemanticEvalCandidateOutput.live(
            recordId: "ca_img_live_blur",
            filename: "live_blur.jpg",
            hint: hint,
            source: "swift_runtime_projection",
            runtimeClaim: .realRuntimeStillReplay,
            futureActions: ["refocus_subject", "stabilize_camera"]
        )

        XCTAssertTrue(liveRow.shown)
        XCTAssertTrue(liveRow.semanticActions.isEmpty)
        XCTAssertEqual(liveRow.debugActionTypes, ["leave_frame_as_is"])
        XCTAssertEqual(liveRow.futureActions, ["refocus_subject", "stabilize_camera"])
    }

    func testSemanticEvalPauseGoodVerdictDoesNotExportKeepCurrentSetupForDominantTechnicalFutureAction() {
        let pauseCritique = PauseCritiquePresentation(
            frameId: "frame-good-but-blurry-pause",
            verdict: .good,
            verdictConfidence: 0.82,
            summaryId: "summary_good_blurry",
            shortVerdict: "Кадр читается хорошо.",
            whyGood: "Семантическая композиция читается.",
            whyProblematic: nil,
            strengths: [
                PauseStrengthRow(
                    strengthId: "str_good",
                    type: .clearFocusHierarchy,
                    rationale: "Фокус внимания понятен.",
                    confidence: 0.80,
                    supportingRegion: nil,
                    traceRefId: "trace_strength"
                )
            ],
            issues: [],
            actions: [],
            noChangeRationale: "Оставьте кадр как есть.",
            assumptions: [],
            traceRootIds: ["trace_good"],
            fallbackUsed: false
        )

        let pauseRow = SemanticEvalCandidateOutput.pause(
            recordId: "ca_img_blur",
            filename: "blur.jpg",
            critique: pauseCritique,
            source: "swift_runtime_projection",
            runtimeClaim: .realRuntimeStillReplay,
            futureActions: ["refocus_subject"]
        )

        XCTAssertTrue(pauseRow.shown)
        XCTAssertEqual(pauseRow.semanticActions, [])
        XCTAssertEqual(pauseRow.futureActions, ["refocus_subject"])
    }

    func testSemanticEvalPauseKeepsPositiveConfirmationForNonDominantTechnicalFutureAction() {
        let pauseCritique = PauseCritiquePresentation(
            frameId: "frame-good-low-key-pause",
            verdict: .good,
            verdictConfidence: 0.82,
            summaryId: "summary_good_low_key",
            shortVerdict: "Кадр читается хорошо.",
            whyGood: "Низкий свет работает как художественный стиль.",
            whyProblematic: nil,
            strengths: [
                PauseStrengthRow(
                    strengthId: "str_good",
                    type: .goodLightEmphasis,
                    rationale: "Свет выделяет героя без лишней коррекции.",
                    confidence: 0.80,
                    supportingRegion: nil,
                    traceRefId: "trace_strength"
                )
            ],
            issues: [],
            actions: [],
            noChangeRationale: "Оставьте композицию как есть.",
            assumptions: [],
            traceRootIds: ["trace_good"],
            fallbackUsed: false
        )

        let pauseRow = SemanticEvalCandidateOutput.pause(
            recordId: "ca_img_good_low_key",
            filename: "good_low_key.jpg",
            critique: pauseCritique,
            source: "swift_runtime_projection",
            runtimeClaim: .realRuntimeStillReplay,
            futureActions: ["increase_exposure"],
            dominantFutureActions: []
        )

        XCTAssertEqual(pauseRow.semanticActions, ["keep_current_setup"])
        XCTAssertEqual(pauseRow.futureActions, ["increase_exposure"])
    }

    func testSemanticEvalPauseConfidenceUsesTechnicalQualityFloor() {
        let pauseCritique = PauseCritiquePresentation(
            frameId: "frame-technical-overexposure",
            verdict: .mixed,
            verdictConfidence: 0.52,
            summaryId: "summary_technical",
            shortVerdict: "Кадр требует технической коррекции.",
            whyGood: nil,
            whyProblematic: "Семантический слой не уверен, но пиксельный анализ видит пересвет.",
            strengths: [],
            issues: [],
            actions: [],
            noChangeRationale: nil,
            assumptions: [],
            traceRootIds: ["trace_technical"],
            fallbackUsed: false
        )

        let pauseRow = SemanticEvalCandidateOutput.pause(
            recordId: "ca_img_technical",
            filename: "technical.jpg",
            critique: pauseCritique,
            source: "swift_runtime_projection",
            runtimeClaim: .realRuntimeStillReplay,
            futureActions: ["reduce_exposure"],
            technicalConfidenceFloor: 0.79
        )

        XCTAssertEqual(pauseRow.confidence, 0.79, accuracy: 0.0001)
        XCTAssertEqual(pauseRow.futureActions, ["reduce_exposure"])
    }

    func testSemanticEvalPauseMixedCorrectiveConfidenceIsNotRaisedByTechnicalFloor() {
        let pauseCritique = PauseCritiquePresentation(
            frameId: "frame-mixed-background",
            verdict: .mixed,
            verdictConfidence: 0.74,
            summaryId: "summary_mixed_background",
            shortVerdict: "Кадр можно улучшить.",
            whyGood: nil,
            whyProblematic: "Фон спорит с главным объектом.",
            strengths: [],
            issues: [
                PauseIssueRow(
                    issueId: "iss_background",
                    type: .frameVisuallyOverloaded,
                    severity: 0.61,
                    confidence: 0.72,
                    rationale: "Фон отвлекает.",
                    affectedRegion: nil,
                    suggestedFixTypes: [.reframing],
                    traceRefId: "trace_issue"
                )
            ],
            actions: [
                PauseActionRow(
                    actionId: "act_simplify",
                    actionType: .reduceBackgroundDistractions,
                    semanticActionType: .simplifyBackground,
                    priority: 1,
                    confidence: 0.72,
                    linkedIssueIds: ["iss_background"],
                    expectedOutcome: "Упростите фон.",
                    targetRegion: nil,
                    overlayHintId: nil,
                    traceRefId: "trace_action"
                )
            ],
            noChangeRationale: nil,
            assumptions: [],
            traceRootIds: ["trace_mixed"],
            fallbackUsed: false
        )

        let pauseRow = SemanticEvalCandidateOutput.pause(
            recordId: "ca_img_mixed_background",
            filename: "mixed_background.jpg",
            critique: pauseCritique,
            source: "swift_runtime_projection",
            runtimeClaim: .realRuntimeStillReplay,
            futureActions: ["increase_exposure"],
            technicalConfidenceFloor: 0.91
        )

        XCTAssertEqual(pauseRow.semanticActions, ["simplify_background"])
        XCTAssertEqual(pauseRow.confidence, 0.74, accuracy: 0.0001)
    }

    func testSemanticEvalLiveHiddenRowDoesNotExportTechnicalConfidence() {
        let liveRow = SemanticEvalCandidateOutput.live(
            recordId: "ca_img_hidden_live",
            filename: "hidden_live.jpg",
            hint: nil,
            source: "swift_runtime_projection",
            runtimeClaim: .realRuntimeStillReplay,
            futureActions: ["stabilize_camera"],
            technicalConfidenceFloor: 0.91
        )

        XCTAssertFalse(liveRow.shown)
        XCTAssertEqual(liveRow.semanticActions, [])
        XCTAssertEqual(liveRow.futureActions, ["stabilize_camera"])
        XCTAssertEqual(liveRow.confidence, 0, accuracy: 0.0001)
    }

    func testSemanticEvalPauseDropsLeaveAsIsActionForDominantTechnicalFutureAction() {
        let pauseCritique = PauseCritiquePresentation(
            frameId: "frame-good-but-needs-stabilization-pause",
            verdict: .good,
            verdictConfidence: 0.78,
            summaryId: "summary_good_stabilize",
            shortVerdict: "Кадр композиционно читается.",
            whyGood: "Композиция понятна, но технический слой требует проверки.",
            whyProblematic: nil,
            strengths: [
                PauseStrengthRow(
                    strengthId: "str_balance",
                    type: .balancedCompositionForScene,
                    rationale: "Композиция выглядит сбалансированной.",
                    confidence: 0.76,
                    supportingRegion: nil,
                    traceRefId: "trace_strength"
                )
            ],
            issues: [],
            actions: [
                PauseActionRow(
                    actionId: "act_keep",
                    actionType: .leaveFrameAsIs,
                    semanticActionType: .keepCurrentSetup,
                    priority: 1,
                    confidence: 0.72,
                    linkedIssueIds: [],
                    expectedOutcome: "Композицию можно сохранить.",
                    targetRegion: nil,
                    overlayHintId: nil,
                    traceRefId: "trace_keep"
                )
            ],
            noChangeRationale: "Оставьте композицию как есть.",
            assumptions: [],
            traceRootIds: ["trace_good"],
            fallbackUsed: false
        )

        let pauseRow = SemanticEvalCandidateOutput.pause(
            recordId: "ca_img_stabilize",
            filename: "stabilize.jpg",
            critique: pauseCritique,
            source: "swift_runtime_projection",
            runtimeClaim: .realRuntimeStillReplay,
            futureActions: ["stabilize_camera"]
        )

        XCTAssertTrue(pauseRow.shown)
        XCTAssertEqual(pauseRow.semanticActions, [])
        XCTAssertEqual(pauseRow.debugActionTypes, ["leave_frame_as_is"])
        XCTAssertEqual(pauseRow.futureActions, ["stabilize_camera"])
    }

    func testSemanticEvalHiddenRowsCanCarryFutureTechnicalActions() {
        let hiddenRow = SemanticEvalCandidateOutput.hidden(
            recordId: "ca_img_blur",
            filename: "blur.jpg",
            mode: .pause,
            source: "swift_runtime_projection",
            runtimeClaim: .realRuntimeStillReplay,
            futureActions: ["stabilize_camera", "increase_exposure"],
            traceIds: ["trace_hidden"]
        )

        XCTAssertFalse(hiddenRow.shown)
        XCTAssertEqual(hiddenRow.semanticActions, [])
        XCTAssertEqual(hiddenRow.futureActions, ["stabilize_camera", "increase_exposure"])
        XCTAssertEqual(hiddenRow.traceIds, ["trace_hidden"])
    }

    func testSemanticEvalTechnicalQualityProbeDetectsExposureAndFocusActions() {
        let probe = SemanticEvalTechnicalQualityProbe()

        let overexposed = probe.signal(pixelBuffer: makeHotspotPixelBuffer(width: 96, height: 96))
        XCTAssertTrue(overexposed.futureActionIds.contains(TechnicalQualityActionType.reduceExposure.rawValue))

        let softFocus = probe.signal(pixelBuffer: makeSoftFocusPixelBuffer(width: 96, height: 96))
        XCTAssertTrue(softFocus.futureActionIds.contains(TechnicalQualityActionType.refocusSubject.rawValue))
        XCTAssertTrue(softFocus.futureActionIds.contains(TechnicalQualityActionType.stabilizeCamera.rawValue))

        let lowLight = probe.signal(pixelBuffer: makeLowLightPixelBuffer(width: 96, height: 96))
        XCTAssertTrue(lowLight.futureActionIds.contains(TechnicalQualityActionType.increaseExposure.rawValue))
        XCTAssertTrue(lowLight.futureActionIds.contains(TechnicalQualityActionType.reduceIsoNoise.rawValue))
    }

    func testSemanticEvalTechnicalQualityProbeDoesNotTreatLowKeyTextureAsDominantBlur() {
        let probe = SemanticEvalTechnicalQualityProbe()

        let lowKey = probe.signal(pixelBuffer: makeLowKeyCinematicPixelBuffer(width: 96, height: 96))

        XCTAssertTrue(lowKey.futureActionIds.contains(TechnicalQualityActionType.increaseExposure.rawValue))
        XCTAssertTrue(lowKey.futureActionIds.contains(TechnicalQualityActionType.reduceIsoNoise.rawValue))
        XCTAssertFalse(lowKey.dominantFutureActionIds.contains(TechnicalQualityActionType.refocusSubject.rawValue))
        XCTAssertFalse(lowKey.dominantFutureActionIds.contains(TechnicalQualityActionType.stabilizeCamera.rawValue))
    }

    func testSemanticEvalTechnicalQualityProbeKeepsModerateLowLightSoftnessDominant() {
        let probe = SemanticEvalTechnicalQualityProbe()

        let softLowLight = probe.signal(pixelBuffer: makeModerateLowLightSoftPixelBuffer(width: 96, height: 96))

        XCTAssertTrue(softLowLight.dominantFutureActionIds.contains(TechnicalQualityActionType.refocusSubject.rawValue))
        XCTAssertTrue(softLowLight.dominantFutureActionIds.contains(TechnicalQualityActionType.stabilizeCamera.rawValue))
    }

    func testSemanticEvalTechnicalQualityProbeMarksModerateBrightHotspotAsDominant() {
        let probe = SemanticEvalTechnicalQualityProbe()

        let signal = probe.signal(pixelBuffer: makeModerateHotspotPixelBuffer(width: 96, height: 96))

        XCTAssertTrue(signal.futureActionIds.contains(TechnicalQualityActionType.reduceExposure.rawValue))
        XCTAssertTrue(signal.dominantFutureActionIds.contains(TechnicalQualityActionType.reduceExposure.rawValue))
    }

    @MainActor
    func testStillImageReplayPresentsDominantTechnicalQualityProblem() async {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_soft_focus_runtime",
            filename: "soft_focus_runtime.jpg",
            pixelBuffer: makeSoftFocusPixelBuffer(width: 96, height: 96),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_000),
            options: .lightweightTest
        )

        XCTAssertTrue(result.liveRow.shown)
        XCTAssertTrue(result.liveRow.semanticActions.isEmpty)
        XCTAssertTrue(result.liveRow.futureActions.contains(TechnicalQualityActionType.refocusSubject.rawValue))
        XCTAssertTrue(result.liveRow.futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue))
        XCTAssertTrue(
            SETCameraCopy.technicalActionKey(for: .defocus)
                .localizedString(locale: .current) == result.liveRow.liveTip
                || SETCameraCopy.technicalActionKey(for: .motionBlur)
                    .localizedString(locale: .current) == result.liveRow.liveTip
        )

        XCTAssertTrue(result.pauseRow.shown)
        XCTAssertTrue(result.pauseRow.semanticActions.isEmpty)
        XCTAssertTrue(result.pauseRow.futureActions.contains(TechnicalQualityActionType.refocusSubject.rawValue))
        XCTAssertTrue(result.pauseRow.futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue))
        XCTAssertGreaterThanOrEqual(result.pauseRow.confidence, 0.75)
        XCTAssertTrue(result.pauseRow.pauseSummary?.localizedCaseInsensitiveContains("техничес") == true)
    }

    @MainActor
    func testStillImageReplayKeepsNoSubjectMotionBlurSilenceLowConfidence() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_038",
            filename: "038.jpg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "038.jpg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_202),
            options: .fullRuntime
        )

        XCTAssertTrue(result.liveRow.shown)
        XCTAssertTrue(result.pauseRow.shown)
        XCTAssertTrue(result.liveRow.semanticActions.isEmpty)
        XCTAssertTrue(result.pauseRow.semanticActions.isEmpty)
        XCTAssertTrue(result.pauseRow.futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue))
        XCTAssertTrue(result.pauseRow.futureActions.contains(TechnicalQualityActionType.refocusSubject.rawValue))
        XCTAssertLessThan(result.liveRow.confidence, 0.45)
        XCTAssertLessThan(result.pauseRow.confidence, 0.45)
    }

    @MainActor
    func testStillImageReplayKeepsNoSubjectMotionBlurHighConfidenceWhenExposureCorrectionIsPresent() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_061",
            filename: "061.jpg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "061.jpg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_203),
            options: .fullRuntime
        )

        XCTAssertTrue(result.liveRow.shown)
        XCTAssertTrue(result.pauseRow.shown)
        XCTAssertTrue(result.pauseRow.futureActions.contains(TechnicalQualityActionType.reduceExposure.rawValue))
        XCTAssertGreaterThanOrEqual(result.liveRow.confidence, 0.75)
        XCTAssertGreaterThanOrEqual(result.pauseRow.confidence, 0.75)
    }

    @MainActor
    func testStillImageReplayMapsDominantHotspotToSemanticAction() async {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_hotspot_runtime",
            filename: "hotspot_runtime.jpg",
            pixelBuffer: makeModerateHotspotPixelBuffer(width: 96, height: 96),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_100),
            options: .lightweightTest
        )

        XCTAssertTrue(result.pauseRow.shown)
        XCTAssertTrue(result.pauseRow.futureActions.contains(TechnicalQualityActionType.reduceExposure.rawValue))
        XCTAssertTrue(
            result.pauseRow.semanticActions.contains(SemanticActionType.removeBackgroundHotspot.rawValue),
            "semanticActions=\(result.pauseRow.semanticActions) debugActionTypes=\(result.pauseRow.debugActionTypes) futureActions=\(result.pauseRow.futureActions) summary=\(result.pauseRow.pauseSummary ?? "")"
        )
        XCTAssertTrue(
            result.pauseRow.semanticActions.contains(SemanticActionType.changeCameraAngle.rawValue),
            "semanticActions=\(result.pauseRow.semanticActions) debugActionTypes=\(result.pauseRow.debugActionTypes) futureActions=\(result.pauseRow.futureActions) summary=\(result.pauseRow.pauseSummary ?? "")"
        )
        // C05: the generic simplify_background label is no longer an
        // independent executable command for this cause; the hotspot and the
        // camera reposition are alternatives of ONE card.
        XCTAssertFalse(
            result.pauseRow.semanticActions.contains(SemanticActionType.simplifyBackground.rawValue),
            "semanticActions=\(result.pauseRow.semanticActions) debugActionTypes=\(result.pauseRow.debugActionTypes) futureActions=\(result.pauseRow.futureActions) summary=\(result.pauseRow.pauseSummary ?? "")"
        )
        XCTAssertFalse(result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue))
    }

    @MainActor
    func testStillImageReplayMapsUnderlitReadablePortraitToFrontFill() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_006",
            filename: "006.jpg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "006.jpg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_200),
            options: .fullRuntime
        )

        XCTAssertTrue(result.pauseRow.shown)
        XCTAssertTrue(result.liveRow.shown)
        XCTAssertLessThan(result.liveRow.confidence, 0.75)
        XCTAssertTrue(result.pauseRow.futureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue))
        XCTAssertTrue(
            result.pauseRow.semanticActions.contains(SemanticActionType.addFrontFillLight.rawValue),
            "semanticActions=\(result.pauseRow.semanticActions) futureActions=\(result.pauseRow.futureActions) summary=\(result.pauseRow.pauseSummary ?? "") debugLabels=\(result.pauseRow.debugSemanticLabels)"
        )
        XCTAssertFalse(result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue))
        XCTAssertLessThan(result.pauseRow.confidence, 0.75)
    }

    @MainActor
    func testStillImageReplayDoesNotOvercorrectGoodLowKeyBookWithFrontFill() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_036",
            filename: "036.jpg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "036.jpg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_201),
            options: .fullRuntime
        )

        XCTAssertTrue(result.pauseRow.shown)
        XCTAssertFalse(
            result.pauseRow.semanticActions.contains(SemanticActionType.addFrontFillLight.rawValue),
            "semanticActions=\(result.pauseRow.semanticActions) futureActions=\(result.pauseRow.futureActions) summary=\(result.pauseRow.pauseSummary ?? "") debugLabels=\(result.pauseRow.debugSemanticLabels)"
        )
    }

    @MainActor
    func testStillImageReplayMapsDarkObjectClusterToBackgroundClearance() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_104",
            filename: "104.jpg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "104.jpg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_204),
            options: .fullRuntime
        )

        XCTAssertTrue(result.liveRow.shown)
        XCTAssertTrue(result.pauseRow.shown)
        XCTAssertTrue(
            result.pauseRow.semanticActions.contains(SemanticActionType.simplifyBackground.rawValue),
            "semanticActions=\(result.pauseRow.semanticActions) futureActions=\(result.pauseRow.futureActions) summary=\(result.pauseRow.pauseSummary ?? "") debugLabels=\(result.pauseRow.debugSemanticLabels)"
        )
        XCTAssertTrue(
            result.pauseRow.semanticActions.contains(SemanticActionType.waitForBackgroundClearance.rawValue),
            "semanticActions=\(result.pauseRow.semanticActions) futureActions=\(result.pauseRow.futureActions) summary=\(result.pauseRow.pauseSummary ?? "") debugLabels=\(result.pauseRow.debugSemanticLabels)"
        )
        XCTAssertFalse(result.liveRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue))
        XCTAssertFalse(result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue))
    }

    @MainActor
    func testStillImageReplayMapsStrongUnderexposedObjectToMediumFrontFill() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_035",
            filename: "035.jpg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "035.jpg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_205),
            options: .fullRuntime
        )

        XCTAssertTrue(result.liveRow.shown)
        XCTAssertTrue(result.pauseRow.shown)
        XCTAssertTrue(
            result.pauseRow.semanticActions.contains(SemanticActionType.addFrontFillLight.rawValue),
            "semanticActions=\(result.pauseRow.semanticActions) futureActions=\(result.pauseRow.futureActions) summary=\(result.pauseRow.pauseSummary ?? "") debugLabels=\(result.pauseRow.debugSemanticLabels)"
        )
        XCTAssertFalse(result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue))
        XCTAssertLessThan(result.pauseRow.confidence, 0.75)
    }

    @MainActor
    func testStillImageReplaySuppressesKeepForUnknownDarkTechnicalFrame() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_068",
            filename: "068.bmp",
            pixelBuffer: try makeDatasetPixelBuffer(named: "068.bmp"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_206),
            options: .fullRuntime
        )

        XCTAssertTrue(result.liveRow.shown)
        XCTAssertTrue(result.pauseRow.shown)
        XCTAssertFalse(result.liveRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue))
        XCTAssertFalse(result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue))
        XCTAssertTrue(result.pauseRow.semanticActions.isEmpty)
        XCTAssertGreaterThanOrEqual(result.pauseRow.confidence, 0.75)
    }

    @MainActor
    func testStillImageReplaySuppressesKeepForMotionLikeFalsePositiveObjects() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        for (recordId, filename) in [("ca_img_070", "070.bmp"), ("ca_img_071", "071.jpg")] {
            let result = await pipeline.testingReplayStillImageForSemanticEval(
                recordId: recordId,
                filename: filename,
                pixelBuffer: try makeDatasetPixelBuffer(named: filename),
                orientation: .up,
                capturedAt: Date(timeIntervalSince1970: 1_768_500_207),
                options: .fullRuntime
            )

            XCTAssertTrue(result.pauseRow.shown, "recordId=\(recordId)")
            XCTAssertFalse(
                result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue),
                "recordId=\(recordId) semanticActions=\(result.pauseRow.semanticActions) futureActions=\(result.pauseRow.futureActions) debugLabels=\(result.pauseRow.debugSemanticLabels)"
            )
            XCTAssertTrue(result.pauseRow.semanticActions.isEmpty, "recordId=\(recordId)")
            XCTAssertGreaterThanOrEqual(result.pauseRow.confidence, 0.75, "recordId=\(recordId)")
        }
    }

    @MainActor
    func testStillImageReplayMapsWeakSubjectBacklightToSimplifyBackground() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        for (recordId, filename) in [("ca_img_077", "077.jpg"), ("ca_img_085", "085.bmp")] {
            let result = await pipeline.testingReplayStillImageForSemanticEval(
                recordId: recordId,
                filename: filename,
                pixelBuffer: try makeDatasetPixelBuffer(named: filename),
                orientation: .up,
                capturedAt: Date(timeIntervalSince1970: 1_768_500_208),
                options: .fullRuntime
            )

            XCTAssertTrue(result.pauseRow.shown, "recordId=\(recordId)")
            XCTAssertTrue(
                result.pauseRow.semanticActions.contains(SemanticActionType.simplifyBackground.rawValue),
                "recordId=\(recordId) semanticActions=\(result.pauseRow.semanticActions) futureActions=\(result.pauseRow.futureActions) debugLabels=\(result.pauseRow.debugSemanticLabels)"
            )
            XCTAssertFalse(result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue))
            if recordId == "ca_img_077" {
                XCTAssertGreaterThanOrEqual(
                    result.pauseRow.confidence,
                    0.75,
                    "recordId=\(recordId) confidence=\(result.pauseRow.confidence) debug=\(result.pauseRow.debugNumericFeatures)"
                )
            } else {
                XCTAssertLessThan(
                    result.pauseRow.confidence,
                    0.75,
                    "recordId=\(recordId) confidence=\(result.pauseRow.confidence) debug=\(result.pauseRow.debugNumericFeatures)"
                )
            }
        }
    }

    @MainActor
    func testStillImageReplayMapsSmallUnderlitLightObjectToFrontFill() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_083",
            filename: "083.bmp",
            pixelBuffer: try makeDatasetPixelBuffer(named: "083.bmp"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_209),
            options: .fullRuntime
        )

        XCTAssertTrue(result.pauseRow.shown)
        XCTAssertTrue(
            result.pauseRow.semanticActions.contains(SemanticActionType.addFrontFillLight.rawValue),
            "semanticActions=\(result.pauseRow.semanticActions) futureActions=\(result.pauseRow.futureActions) summary=\(result.pauseRow.pauseSummary ?? "") debugLabels=\(result.pauseRow.debugSemanticLabels)"
        )
        XCTAssertFalse(result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue))
        XCTAssertGreaterThanOrEqual(result.pauseRow.confidence, 0.75)
    }

    @MainActor
    func testStillImageReplayMapsLowAestheticSingleObjectToBackgroundClearance() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_097",
            filename: "097.bmp",
            pixelBuffer: try makeDatasetPixelBuffer(named: "097.bmp"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_210),
            options: .fullRuntime
        )

        XCTAssertTrue(result.pauseRow.shown)
        XCTAssertTrue(result.pauseRow.semanticActions.contains(SemanticActionType.simplifyBackground.rawValue))
        XCTAssertTrue(result.pauseRow.semanticActions.contains(SemanticActionType.waitForBackgroundClearance.rawValue))
        XCTAssertTrue(
            result.pauseRow.futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue),
            "futureActions=\(result.pauseRow.futureActions) debug=\(result.pauseRow.debugNumericFeatures)"
        )
        XCTAssertFalse(result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue))
    }

    @MainActor
    func testStillImageReplayMapsUnknownGroupNoFocusToFramingActions() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_013",
            filename: "013.jpeg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "013.jpeg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_231),
            options: .fullRuntime
        )

        XCTAssertTrue(result.pauseRow.shown)
        XCTAssertTrue(
            result.pauseRow.semanticActions.contains(SemanticActionType.simplifyBackground.rawValue),
            "semanticActions=\(result.pauseRow.semanticActions) futureActions=\(result.pauseRow.futureActions) debug=\(result.pauseRow.debugSemanticLabels)"
        )
        XCTAssertTrue(
            result.pauseRow.semanticActions.contains(SemanticActionType.shiftFrameRight.rawValue),
            "semanticActions=\(result.pauseRow.semanticActions) futureActions=\(result.pauseRow.futureActions) debug=\(result.pauseRow.debugNumericFeatures)"
        )
        XCTAssertFalse(result.pauseRow.semanticActions.contains(SemanticActionType.levelHorizon.rawValue))
        XCTAssertLessThan(result.pauseRow.confidence, 0.75)
    }

    @MainActor
    func testStillImageReplayCapsMediumOverexposureBackgroundCorrectionConfidence() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_002",
            filename: "002.jpg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "002.jpg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_233),
            options: .fullRuntime
        )

        XCTAssertTrue(result.pauseRow.semanticActions.contains(SemanticActionType.simplifyBackground.rawValue))
        XCTAssertTrue(result.pauseRow.futureActions.contains(TechnicalQualityActionType.reduceExposure.rawValue))
        XCTAssertTrue(result.pauseRow.futureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue))
        XCTAssertLessThan(
            result.pauseRow.confidence,
            0.75,
            "confidence=\(result.pauseRow.confidence) futureActions=\(result.pauseRow.futureActions) debug=\(result.pauseRow.debugNumericFeatures)"
        )
    }

    @MainActor
    func testStillImageReplayKeepsEmptyUnknownTechnicalSilenceLowConfidence() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_024",
            filename: "024.jpg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "024.jpg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_234),
            options: .fullRuntime
        )

        XCTAssertTrue(result.pauseRow.shown)
        XCTAssertTrue(result.pauseRow.semanticActions.isEmpty)
        XCTAssertTrue(result.pauseRow.futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue))
        XCTAssertTrue(result.pauseRow.futureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue))
        XCTAssertLessThan(
            result.pauseRow.confidence,
            0.45,
            "confidence=\(result.pauseRow.confidence) futureActions=\(result.pauseRow.futureActions) debug=\(result.pauseRow.debugNumericFeatures)"
        )
    }

    @MainActor
    func testStillImageReplayRecoversHorizonAndStreetBlurFutureActions() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let horizonResult = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_074",
            filename: "074.bmp",
            pixelBuffer: try makeDatasetPixelBuffer(named: "074.bmp"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_232),
            options: .fullRuntime
        )

        XCTAssertTrue(
            horizonResult.pauseRow.semanticActions.contains(SemanticActionType.levelHorizon.rawValue),
            "semanticActions=\(horizonResult.pauseRow.semanticActions) futureActions=\(horizonResult.pauseRow.futureActions) debug=\(horizonResult.pauseRow.debugNumericFeatures)"
        )
        XCTAssertTrue(horizonResult.pauseRow.futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue))
        XCTAssertFalse(horizonResult.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue))

        let streetResult = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_098",
            filename: "098.bmp",
            pixelBuffer: try makeDatasetPixelBuffer(named: "098.bmp"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_233),
            options: .fullRuntime
        )

        XCTAssertTrue(streetResult.pauseRow.semanticActions.contains(SemanticActionType.simplifyBackground.rawValue))
        XCTAssertTrue(
            streetResult.pauseRow.futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue),
            "futureActions=\(streetResult.pauseRow.futureActions) debug=\(streetResult.pauseRow.debugNumericFeatures)"
        )
        XCTAssertTrue(
            streetResult.pauseRow.futureActions.contains(TechnicalQualityActionType.refocusSubject.rawValue),
            "futureActions=\(streetResult.pauseRow.futureActions) debug=\(streetResult.pauseRow.debugSemanticLabels)"
        )
        XCTAssertLessThan(
            streetResult.pauseRow.confidence,
            0.75,
            "confidence=\(streetResult.pauseRow.confidence) futureActions=\(streetResult.pauseRow.futureActions) debug=\(streetResult.pauseRow.debugNumericFeatures)"
        )
    }

    @MainActor
    func testStillImageReplayDoesNotMapExtremeTechnicalObjectFailureToFrontFill() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_081",
            filename: "081.jpg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "081.jpg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_211),
            options: .fullRuntime
        )

        XCTAssertTrue(result.pauseRow.shown)
        XCTAssertFalse(
            result.pauseRow.semanticActions.contains(SemanticActionType.addFrontFillLight.rawValue),
            "semanticActions=\(result.pauseRow.semanticActions) futureActions=\(result.pauseRow.futureActions) summary=\(result.pauseRow.pauseSummary ?? "") debugLabels=\(result.pauseRow.debugSemanticLabels)"
        )
    }

    @MainActor
    func testStillImageReplayCapsTechnicalFloorForMediumEvidenceKeepCurrentSetup() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        for (recordId, filename) in [
            ("ca_img_027", "027.jpg"),
            ("ca_img_029", "029.jpg"),
            ("ca_img_036", "036.jpg"),
            ("ca_img_037", "037.jpg"),
            ("ca_img_043", "043.jpg"),
            ("ca_img_044", "044.jpg"),
            ("ca_img_050", "050.jpg"),
            ("ca_img_052", "052.jpg"),
            ("ca_img_053", "053.jpg"),
            ("ca_img_057", "057.jpg")
        ] {
            let result = await pipeline.testingReplayStillImageForSemanticEval(
                recordId: recordId,
                filename: filename,
                pixelBuffer: try makeDatasetPixelBuffer(named: filename),
                orientation: .up,
                capturedAt: Date(timeIntervalSince1970: 1_768_500_212),
                options: .fullRuntime
            )

            XCTAssertTrue(result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue), "recordId=\(recordId)")
            XCTAssertLessThan(
                result.pauseRow.confidence,
                0.75,
                "recordId=\(recordId) confidence=\(result.pauseRow.confidence) futureActions=\(result.pauseRow.futureActions) debug=\(result.pauseRow.debugNumericFeatures)"
            )
        }
    }

    @MainActor
    func testStillImageReplayKeepsHighConfidenceWhenKeepEvidenceIsStrong() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        for (recordId, filename) in [
            ("ca_img_017", "017.jpeg"),
            ("ca_img_019", "019.jpg"),
            ("ca_img_030", "030.jpg"),
            ("ca_img_059", "059.bmp")
        ] {
            let result = await pipeline.testingReplayStillImageForSemanticEval(
                recordId: recordId,
                filename: filename,
                pixelBuffer: try makeDatasetPixelBuffer(named: filename),
                orientation: .up,
                capturedAt: Date(timeIntervalSince1970: 1_768_500_213),
                options: .fullRuntime
            )

            XCTAssertTrue(result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue), "recordId=\(recordId)")
            XCTAssertGreaterThanOrEqual(
                result.pauseRow.confidence,
                0.75,
                "recordId=\(recordId) confidence=\(result.pauseRow.confidence) futureActions=\(result.pauseRow.futureActions) debug=\(result.pauseRow.debugNumericFeatures)"
            )
        }
    }

    @MainActor
    func testStillImageReplayCalibratesResidualR20ConfidenceBands() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let mediumFrontFill = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_022",
            filename: "022.jpg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "022.jpg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_217),
            options: .fullRuntime
        )
        XCTAssertTrue(mediumFrontFill.pauseRow.semanticActions.contains(SemanticActionType.addFrontFillLight.rawValue))
        XCTAssertLessThan(
            mediumFrontFill.pauseRow.confidence,
            0.75,
            "confidence=\(mediumFrontFill.pauseRow.confidence) debug=\(mediumFrontFill.pauseRow.debugNumericFeatures)"
        )

        let highMotionBlur = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_078",
            filename: "078.bmp",
            pixelBuffer: try makeDatasetPixelBuffer(named: "078.bmp"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_218),
            options: .fullRuntime
        )
        XCTAssertTrue(highMotionBlur.pauseRow.futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue))
        XCTAssertGreaterThanOrEqual(
            highMotionBlur.pauseRow.confidence,
            0.75,
            "confidence=\(highMotionBlur.pauseRow.confidence) debug=\(highMotionBlur.pauseRow.debugNumericFeatures)"
        )

        let mediumUnknownBlur = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_082",
            filename: "082.bmp",
            pixelBuffer: try makeDatasetPixelBuffer(named: "082.bmp"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_219),
            options: .fullRuntime
        )
        XCTAssertTrue(mediumUnknownBlur.pauseRow.semanticActions.contains(SemanticActionType.simplifyBackground.rawValue))
        XCTAssertLessThan(
            mediumUnknownBlur.pauseRow.confidence,
            0.75,
            "confidence=\(mediumUnknownBlur.pauseRow.confidence) debug=\(mediumUnknownBlur.pauseRow.debugNumericFeatures)"
        )

        let mediumTechnicalSilence = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_090",
            filename: "090.jpg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "090.jpg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_220),
            options: .fullRuntime
        )
        XCTAssertTrue(mediumTechnicalSilence.pauseRow.semanticActions.isEmpty)
        XCTAssertLessThan(
            mediumTechnicalSilence.pauseRow.confidence,
            0.75,
            "confidence=\(mediumTechnicalSilence.pauseRow.confidence) debug=\(mediumTechnicalSilence.pauseRow.debugNumericFeatures)"
        )

        let highUnknownBlur = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_061",
            filename: "061.jpg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "061.jpg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_221),
            options: .fullRuntime
        )
        XCTAssertTrue(highUnknownBlur.pauseRow.semanticActions.contains(SemanticActionType.simplifyBackground.rawValue))
        XCTAssertGreaterThanOrEqual(
            highUnknownBlur.pauseRow.confidence,
            0.75,
            "confidence=\(highUnknownBlur.pauseRow.confidence) debug=\(highUnknownBlur.pauseRow.debugNumericFeatures)"
        )
    }

    @MainActor
    func testStillImageReplayPromotesWideUnknownGoodEstablishingConfidence() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let wideEstablishing = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_010",
            filename: "010.jpg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "010.jpg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_222),
            options: .fullRuntime
        )
        XCTAssertTrue(wideEstablishing.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue))
        XCTAssertGreaterThanOrEqual(
            wideEstablishing.pauseRow.debugNumericFeatures["frame_aspect_ratio"] ?? 0,
            1.76,
            "debug=\(wideEstablishing.pauseRow.debugNumericFeatures)"
        )
        XCTAssertGreaterThanOrEqual(
            wideEstablishing.pauseRow.confidence,
            0.75,
            "confidence=\(wideEstablishing.pauseRow.confidence) debug=\(wideEstablishing.pauseRow.debugNumericFeatures)"
        )

        let eventGroup = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_016",
            filename: "016.jpeg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "016.jpeg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_223),
            options: .fullRuntime
        )
        XCTAssertTrue(eventGroup.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue))
        XCTAssertLessThan(
            eventGroup.pauseRow.debugNumericFeatures["frame_aspect_ratio"] ?? 0,
            1.76,
            "debug=\(eventGroup.pauseRow.debugNumericFeatures)"
        )
        XCTAssertLessThan(
            eventGroup.pauseRow.confidence,
            0.75,
            "confidence=\(eventGroup.pauseRow.confidence) debug=\(eventGroup.pauseRow.debugNumericFeatures)"
        )
    }

    @MainActor
    func testStillImageReplayMapsUnknownNoisyLowLightFrameToStepBack() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_095",
            filename: "095.bmp",
            pixelBuffer: try makeDatasetPixelBuffer(named: "095.bmp"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_214),
            options: .fullRuntime
        )

        XCTAssertTrue(result.pauseRow.shown)
        XCTAssertFalse(result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue))
        XCTAssertTrue(result.pauseRow.semanticActions.contains(SemanticActionType.stepBack.rawValue))
        XCTAssertLessThan(result.liveRow.confidence, 0.75)
        XCTAssertLessThan(result.pauseRow.confidence, 0.75)
    }

    @MainActor
    func testStillImageReplayMapsReadableUnderlitObjectToFrontFill() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_007",
            filename: "007.jpg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "007.jpg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_215),
            options: .fullRuntime
        )

        XCTAssertTrue(result.pauseRow.semanticActions.contains(SemanticActionType.addFrontFillLight.rawValue))
        XCTAssertFalse(result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue))
        XCTAssertLessThan(result.liveRow.confidence, 0.75)
        XCTAssertLessThan(result.pauseRow.confidence, 0.75)
    }

    @MainActor
    func testStillImageReplayDoesNotMapLightObjectKeepFrameToFrontFill() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_050",
            filename: "050.jpg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "050.jpg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_216),
            options: .fullRuntime
        )

        XCTAssertFalse(result.pauseRow.semanticActions.contains(SemanticActionType.addFrontFillLight.rawValue))
        XCTAssertTrue(result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue))
    }

    @MainActor
    func testStillImageReplayMapsLowAestheticObjectToBackgroundClearance() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_014",
            filename: "014.jpeg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "014.jpeg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_217),
            options: .fullRuntime
        )

        XCTAssertTrue(result.pauseRow.semanticActions.contains(SemanticActionType.simplifyBackground.rawValue))
        XCTAssertTrue(result.pauseRow.semanticActions.contains(SemanticActionType.waitForBackgroundClearance.rawValue))
        XCTAssertFalse(result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue))
        XCTAssertLessThan(result.pauseRow.confidence, 0.75)
    }

    @MainActor
    func testStillImageReplayAddsClusterClearanceAndStabilization() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        for (recordId, filename) in [("ca_img_076", "076.bmp"), ("ca_img_084", "084.jpg")] {
            let result = await pipeline.testingReplayStillImageForSemanticEval(
                recordId: recordId,
                filename: filename,
                pixelBuffer: try makeDatasetPixelBuffer(named: filename),
                orientation: .up,
                capturedAt: Date(timeIntervalSince1970: 1_768_500_218),
                options: .fullRuntime
            )

            XCTAssertTrue(
                result.pauseRow.semanticActions.contains(SemanticActionType.waitForBackgroundClearance.rawValue),
                "recordId=\(recordId) semanticActions=\(result.pauseRow.semanticActions)"
            )
            XCTAssertTrue(
                result.pauseRow.futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue),
                "recordId=\(recordId) futureActions=\(result.pauseRow.futureActions)"
            )
            XCTAssertFalse(result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue))
        }
    }

    @MainActor
    func testStillImageReplayMapsUnreadableLowLightObjectToCloserFill() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_093",
            filename: "093.bmp",
            pixelBuffer: try makeDatasetPixelBuffer(named: "093.bmp"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_219),
            options: .fullRuntime
        )

        XCTAssertTrue(result.pauseRow.semanticActions.contains(SemanticActionType.addFrontFillLight.rawValue))
        XCTAssertTrue(result.pauseRow.semanticActions.contains(SemanticActionType.stepCloser.rawValue))
        XCTAssertFalse(result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue))
        XCTAssertGreaterThanOrEqual(result.pauseRow.confidence, 0.75)
    }

    @MainActor
    func testStillImageReplayMapsUnknownBlurToSimplifyBackground() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_082",
            filename: "082.bmp",
            pixelBuffer: try makeDatasetPixelBuffer(named: "082.bmp"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_220),
            options: .fullRuntime
        )

        XCTAssertTrue(result.pauseRow.semanticActions.contains(SemanticActionType.simplifyBackground.rawValue))
        XCTAssertTrue(result.pauseRow.futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue))
        XCTAssertFalse(result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue))
    }

    @MainActor
    func testStillImageReplayPreservesGoodReadableKeepDespiteTechnicalSignal() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        for (recordId, filename) in [("ca_img_009", "009.jpg"), ("ca_img_020", "020.jpg")] {
            let result = await pipeline.testingReplayStillImageForSemanticEval(
                recordId: recordId,
                filename: filename,
                pixelBuffer: try makeDatasetPixelBuffer(named: filename),
                orientation: .up,
                capturedAt: Date(timeIntervalSince1970: 1_768_500_221),
                options: .fullRuntime
            )

            XCTAssertTrue(
                result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue),
                "recordId=\(recordId) semanticActions=\(result.pauseRow.semanticActions) trace=\(result.pauseRow.traceIds)"
            )
            XCTAssertGreaterThanOrEqual(
                result.pauseRow.confidence,
                0.75,
                "recordId=\(recordId) confidence=\(result.pauseRow.confidence)"
            )
        }
    }

    @MainActor
    func testStillImageReplaySuppressesFalseKeepForBadTechnicalFrames() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        for (recordId, filename) in [
            ("ca_img_086", "086.jpg"),
            ("ca_img_090", "090.jpg"),
            ("ca_img_211", "211.jpg"),
            ("ca_img_224", "224.jpg"),
            ("ca_img_232", "232.jpg")
        ] {
            let result = await pipeline.testingReplayStillImageForSemanticEval(
                recordId: recordId,
                filename: filename,
                pixelBuffer: try makeDatasetPixelBuffer(named: filename),
                orientation: .up,
                capturedAt: Date(timeIntervalSince1970: 1_768_500_222),
                options: .fullRuntime
            )

            XCTAssertFalse(
                result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue),
                "recordId=\(recordId) semanticActions=\(result.pauseRow.semanticActions) trace=\(result.pauseRow.traceIds)"
            )
            XCTAssertFalse(
                result.liveRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue),
                "recordId=\(recordId) liveActions=\(result.liveRow.semanticActions) future=\(result.liveRow.futureActions)"
            )
            if recordId == "ca_img_086" {
                XCTAssertTrue(
                    result.pauseRow.semanticActions.isEmpty,
                    "recordId=\(recordId) semanticActions=\(result.pauseRow.semanticActions) trace=\(result.pauseRow.traceIds)"
                )
            }
        }
    }

    @MainActor
    func testStillImageReplayPreservesLowKeyMoodKeepDespiteTechnicalFuture() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        for (recordId, filename) in [("ca_img_023", "023.jpg"), ("ca_img_039", "039.jpg")] {
            let result = await pipeline.testingReplayStillImageForSemanticEval(
                recordId: recordId,
                filename: filename,
                pixelBuffer: try makeDatasetPixelBuffer(named: filename),
                orientation: .up,
                capturedAt: Date(timeIntervalSince1970: 1_768_500_224),
                options: .fullRuntime
            )

            XCTAssertTrue(
                result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue),
                "recordId=\(recordId) semanticActions=\(result.pauseRow.semanticActions) future=\(result.pauseRow.futureActions) trace=\(result.pauseRow.traceIds)"
            )
            XCTAssertLessThan(
                result.pauseRow.confidence,
                0.75,
                "recordId=\(recordId) confidence=\(result.pauseRow.confidence)"
            )
        }
    }

    @MainActor
    func testStillImageReplayPreservesCinematicEstablishingDespiteTechnicalFuture() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        for (recordId, filename) in [
            ("ca_img_045", "045.jpg"),
            ("ca_img_054", "054.jpg"),
            ("ca_img_116", "116.jpg"),
            ("ca_img_112", "112.jpg"),
            ("ca_img_127", "127.jpg"),
            ("ca_img_128", "128.jpg"),
            ("ca_img_137", "137.jpg"),
            ("ca_img_145", "145.jpg"),
            ("ca_img_147", "147.jpg"),
            ("ca_img_156", "156.jpg")
        ] {
            let result = await pipeline.testingReplayStillImageForSemanticEval(
                recordId: recordId,
                filename: filename,
                pixelBuffer: try makeDatasetPixelBuffer(named: filename),
                orientation: .up,
                capturedAt: Date(timeIntervalSince1970: 1_768_500_225),
                options: .fullRuntime
            )

            XCTAssertTrue(
                result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue),
                "recordId=\(recordId) semanticActions=\(result.pauseRow.semanticActions) future=\(result.pauseRow.futureActions) trace=\(result.pauseRow.traceIds)"
            )
            XCTAssertFalse(
                result.pauseRow.semanticActions.contains(SemanticActionType.simplifyBackground.rawValue),
                "recordId=\(recordId) semanticActions=\(result.pauseRow.semanticActions)"
            )
            XCTAssertFalse(
                result.pauseRow.semanticActions.contains(SemanticActionType.removeBackgroundHotspot.rawValue),
                "recordId=\(recordId) semanticActions=\(result.pauseRow.semanticActions)"
            )
            XCTAssertFalse(
                result.pauseRow.semanticActions.contains(SemanticActionType.stepCloser.rawValue),
                "recordId=\(recordId) semanticActions=\(result.pauseRow.semanticActions)"
            )
        }
    }

    @MainActor
    func testStillImageReplayPreservesReadableObjectInsertDespiteWindowHotspot() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_130",
            filename: "130.jpg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "130.jpg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_225),
            options: .fullRuntime
        )

        XCTAssertTrue(
            result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue),
            "semanticActions=\(result.pauseRow.semanticActions) future=\(result.pauseRow.futureActions) trace=\(result.pauseRow.traceIds) debug=\(result.pauseRow.debugNumericFeatures)"
        )
        XCTAssertFalse(
            result.pauseRow.semanticActions.contains(SemanticActionType.removeBackgroundHotspot.rawValue),
            "semanticActions=\(result.pauseRow.semanticActions) future=\(result.pauseRow.futureActions) trace=\(result.pauseRow.traceIds) debug=\(result.pauseRow.debugNumericFeatures)"
        )
        XCTAssertFalse(
            result.pauseRow.semanticActions.contains(SemanticActionType.simplifyBackground.rawValue),
            "semanticActions=\(result.pauseRow.semanticActions) future=\(result.pauseRow.futureActions) trace=\(result.pauseRow.traceIds) debug=\(result.pauseRow.debugNumericFeatures)"
        )
    }

    @MainActor
    func testStillImageReplayMapsRegeneratedBadFramesToSemanticCorrections() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let cases: [(recordId: String, filename: String, requiredActions: [SemanticActionType], requiredFuture: [TechnicalQualityActionType])] = [
            ("ca_img_208", "208.jpg", [.removeDistractingObject, .simplifyBackground], [.avoidOcclusion]),
            ("ca_img_209", "209.jpg", [.stepBack, .removeDistractingObject], [.avoidOcclusion]),
            ("ca_img_210", "210.jpg", [.removeBackgroundHotspot, .changeCameraAngle], []),
            ("ca_img_223", "223.jpg", [.removeBackgroundHotspot, .changeCameraAngle], []),
            ("ca_img_224", "224.jpg", [.addFrontFillLight, .rotateSubjectTowardLight], []),
            ("ca_img_227", "227.jpg", [.removeDistractingObject, .simplifyBackground], []),
            ("ca_img_220", "220.jpg", [.stepCloser], []),
            ("ca_img_228", "228.jpg", [.stepCloser], []),
            ("ca_img_238", "238.jpg", [.addFrontFillLight, .rotateSubjectTowardLight], [])
        ]

        for testCase in cases {
            let result = await pipeline.testingReplayStillImageForSemanticEval(
                recordId: testCase.recordId,
                filename: testCase.filename,
                pixelBuffer: try makeDatasetPixelBuffer(named: testCase.filename),
                orientation: .up,
                capturedAt: Date(timeIntervalSince1970: 1_768_500_229),
                options: .fullRuntime
            )

            for action in testCase.requiredActions {
                XCTAssertTrue(
                    result.pauseRow.semanticActions.contains(action.rawValue),
                    "recordId=\(testCase.recordId) required=\(action.rawValue) semanticActions=\(result.pauseRow.semanticActions) future=\(result.pauseRow.futureActions) debug=\(result.pauseRow.debugNumericFeatures)"
                )
            }
            for futureAction in testCase.requiredFuture {
                XCTAssertTrue(
                    result.pauseRow.futureActions.contains(futureAction.rawValue),
                    "recordId=\(testCase.recordId) requiredFuture=\(futureAction.rawValue) semanticActions=\(result.pauseRow.semanticActions) future=\(result.pauseRow.futureActions)"
                )
            }
            XCTAssertFalse(
                result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue),
                "recordId=\(testCase.recordId) semanticActions=\(result.pauseRow.semanticActions)"
            )
        }
    }

    @MainActor
    func testStillImageReplayMapsSyntheticHotspotToCorrectiveSemanticActions() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_179",
            filename: "179.jpg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "179.jpg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_226),
            options: .fullRuntime
        )

        XCTAssertTrue(
            result.pauseRow.semanticActions.contains(SemanticActionType.removeBackgroundHotspot.rawValue),
            "semanticActions=\(result.pauseRow.semanticActions) future=\(result.pauseRow.futureActions) trace=\(result.pauseRow.traceIds) debug=\(result.pauseRow.debugNumericFeatures)"
        )
        XCTAssertTrue(
            result.pauseRow.semanticActions.contains(SemanticActionType.changeCameraAngle.rawValue),
            "semanticActions=\(result.pauseRow.semanticActions) future=\(result.pauseRow.futureActions) trace=\(result.pauseRow.traceIds) debug=\(result.pauseRow.debugNumericFeatures)"
        )
        XCTAssertTrue(
            result.pauseRow.futureActions.contains(TechnicalQualityActionType.reduceExposure.rawValue),
            "semanticActions=\(result.pauseRow.semanticActions) future=\(result.pauseRow.futureActions) trace=\(result.pauseRow.traceIds) debug=\(result.pauseRow.debugNumericFeatures)"
        )
        XCTAssertFalse(
            result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue),
            "semanticActions=\(result.pauseRow.semanticActions) future=\(result.pauseRow.futureActions) trace=\(result.pauseRow.traceIds) debug=\(result.pauseRow.debugNumericFeatures)"
        )
    }

    @MainActor
    func testStillImageReplayMapsSyntheticEdgeCutoffToStepBackAndOcclusionFuture() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_184",
            filename: "184.jpg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "184.jpg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_227),
            options: .fullRuntime
        )

        XCTAssertTrue(result.pauseRow.semanticActions.contains(SemanticActionType.stepBack.rawValue))
        XCTAssertTrue(result.pauseRow.semanticActions.contains(SemanticActionType.shiftFrameRight.rawValue))
        XCTAssertTrue(result.pauseRow.futureActions.contains(TechnicalQualityActionType.avoidOcclusion.rawValue))
        XCTAssertFalse(result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue))
    }

    @MainActor
    func testStillImageReplayMapsSyntheticUnderexposureToFrontFillAndSubjectRotation() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_180",
            filename: "180.jpg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "180.jpg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_228),
            options: .fullRuntime
        )

        XCTAssertTrue(result.pauseRow.futureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue))
        XCTAssertFalse(result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue))
    }

    @MainActor
    func testStillImageReplayMapsUnknownSyntheticUnderexposureAndOcclusionToLightingAndCleanup() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_168",
            filename: "168.jpg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "168.jpg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_228),
            options: .fullRuntime
        )

        XCTAssertTrue(
            result.pauseRow.semanticActions.contains(SemanticActionType.addFrontFillLight.rawValue),
            "semanticActions=\(result.pauseRow.semanticActions) future=\(result.pauseRow.futureActions) trace=\(result.pauseRow.traceIds) debug=\(result.pauseRow.debugNumericFeatures)"
        )
        XCTAssertTrue(
            result.pauseRow.semanticActions.contains(SemanticActionType.changeCameraAngle.rawValue),
            "semanticActions=\(result.pauseRow.semanticActions) future=\(result.pauseRow.futureActions) trace=\(result.pauseRow.traceIds) debug=\(result.pauseRow.debugNumericFeatures)"
        )
        XCTAssertFalse(
            result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue),
            "semanticActions=\(result.pauseRow.semanticActions) future=\(result.pauseRow.futureActions) trace=\(result.pauseRow.traceIds) debug=\(result.pauseRow.debugNumericFeatures)"
        )
    }

    @MainActor
    func testStillImageReplayKeepsSyntheticMotionBlurTechnicalOnly() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        for (recordId, filename) in [("ca_img_181", "181.jpg"), ("ca_img_189", "189.jpg")] {
            let result = await pipeline.testingReplayStillImageForSemanticEval(
                recordId: recordId,
                filename: filename,
                pixelBuffer: try makeDatasetPixelBuffer(named: filename),
                orientation: .up,
                capturedAt: Date(timeIntervalSince1970: 1_768_500_229),
                options: .fullRuntime
            )

            XCTAssertTrue(result.pauseRow.futureActions.contains(TechnicalQualityActionType.stabilizeCamera.rawValue), "recordId=\(recordId)")
            XCTAssertTrue(result.pauseRow.semanticActions.isEmpty, "recordId=\(recordId) semanticActions=\(result.pauseRow.semanticActions)")
            XCTAssertFalse(result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue), "recordId=\(recordId)")
        }
    }

    @MainActor
    func testStillImageReplayMapsSyntheticSmallSubjectToStepCloser() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        for (recordId, filename) in [("ca_img_182", "182.jpg"), ("ca_img_206", "206.jpg")] {
            let result = await pipeline.testingReplayStillImageForSemanticEval(
                recordId: recordId,
                filename: filename,
                pixelBuffer: try makeDatasetPixelBuffer(named: filename),
                orientation: .up,
                capturedAt: Date(timeIntervalSince1970: 1_768_500_230),
                options: .fullRuntime
            )

            XCTAssertTrue(
                result.pauseRow.semanticActions.contains(SemanticActionType.stepCloser.rawValue),
                "recordId=\(recordId) semanticActions=\(result.pauseRow.semanticActions) future=\(result.pauseRow.futureActions) debug=\(result.pauseRow.debugNumericFeatures)"
            )
            XCTAssertFalse(
                result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue),
                "recordId=\(recordId) semanticActions=\(result.pauseRow.semanticActions)"
            )
        }
    }

    @MainActor
    func testStillImageReplaySuppressesPreservationForReadableSyntheticSmallSubject() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_190",
            filename: "190.jpg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "190.jpg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_230),
            options: .fullRuntime
        )

        XCTAssertTrue(
            result.pauseRow.semanticActions.contains(SemanticActionType.stepCloser.rawValue),
            "semanticActions=\(result.pauseRow.semanticActions) future=\(result.pauseRow.futureActions) trace=\(result.pauseRow.traceIds) debug=\(result.pauseRow.debugNumericFeatures)"
        )
        XCTAssertFalse(
            result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue),
            "semanticActions=\(result.pauseRow.semanticActions) future=\(result.pauseRow.futureActions) trace=\(result.pauseRow.traceIds) debug=\(result.pauseRow.debugNumericFeatures)"
        )
    }

    @MainActor
    func testStillImageReplayMapsSyntheticClutterToSemanticCleanup() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        for (recordId, filename) in [("ca_img_183", "183.jpg")] {
            let result = await pipeline.testingReplayStillImageForSemanticEval(
                recordId: recordId,
                filename: filename,
                pixelBuffer: try makeDatasetPixelBuffer(named: filename),
                orientation: .up,
                capturedAt: Date(timeIntervalSince1970: 1_768_500_231),
                options: .fullRuntime
            )

            XCTAssertTrue(
                result.pauseRow.semanticActions.contains(SemanticActionType.simplifyBackground.rawValue) ||
                    result.pauseRow.semanticActions.contains(SemanticActionType.removeDistractingObject.rawValue),
                "recordId=\(recordId) semanticActions=\(result.pauseRow.semanticActions) future=\(result.pauseRow.futureActions) debug=\(result.pauseRow.debugNumericFeatures)"
            )
            XCTAssertFalse(
                result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue),
                "recordId=\(recordId) semanticActions=\(result.pauseRow.semanticActions)"
            )
        }
    }

    @MainActor
    func testStillImageReplayMapsSyntheticCrookedFramesToLevelHorizon() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        for (recordId, filename) in [("ca_img_194", "194.jpg"), ("ca_img_202", "202.jpg")] {
            let result = await pipeline.testingReplayStillImageForSemanticEval(
                recordId: recordId,
                filename: filename,
                pixelBuffer: try makeDatasetPixelBuffer(named: filename),
                orientation: .up,
                capturedAt: Date(timeIntervalSince1970: 1_768_500_232),
                options: .fullRuntime
            )

            XCTAssertTrue(
                result.pauseRow.semanticActions.contains(SemanticActionType.levelHorizon.rawValue),
                "recordId=\(recordId) semanticActions=\(result.pauseRow.semanticActions) future=\(result.pauseRow.futureActions) debug=\(result.pauseRow.debugNumericFeatures)"
            )
            XCTAssertFalse(
                result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue),
                "recordId=\(recordId) semanticActions=\(result.pauseRow.semanticActions)"
            )
        }
    }

    @MainActor
    func testStillImageReplayMapsUnknownSyntheticUnderexposureToLightingAdvice() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        for (recordId, filename) in [("ca_img_188", "188.jpg"), ("ca_img_204", "204.jpg")] {
            let result = await pipeline.testingReplayStillImageForSemanticEval(
                recordId: recordId,
                filename: filename,
                pixelBuffer: try makeDatasetPixelBuffer(named: filename),
                orientation: .up,
                capturedAt: Date(timeIntervalSince1970: 1_768_500_233),
                options: .fullRuntime
            )

            XCTAssertTrue(
                result.pauseRow.semanticActions.contains(SemanticActionType.addFrontFillLight.rawValue),
                "recordId=\(recordId) semanticActions=\(result.pauseRow.semanticActions) future=\(result.pauseRow.futureActions) debug=\(result.pauseRow.debugNumericFeatures)"
            )
            XCTAssertTrue(
                result.pauseRow.semanticActions.contains(SemanticActionType.rotateSubjectTowardLight.rawValue),
                "recordId=\(recordId) semanticActions=\(result.pauseRow.semanticActions) future=\(result.pauseRow.futureActions) debug=\(result.pauseRow.debugNumericFeatures)"
            )
            XCTAssertFalse(
                result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue),
                "recordId=\(recordId) semanticActions=\(result.pauseRow.semanticActions)"
            )
        }
    }

    @MainActor
    func testStillImageReplayPreservesNarrativeEstablishingFramesWithKeepCurrentSetup() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        for (recordId, filename) in [
            ("ca_img_003", "003.jpg"),
            ("ca_img_015", "015.jpeg"),
            ("ca_img_125", "125.jpg"),
            ("ca_img_127", "127.jpg"),
            ("ca_img_132", "132.jpg")
        ] {
            let result = await pipeline.testingReplayStillImageForSemanticEval(
                recordId: recordId,
                filename: filename,
                pixelBuffer: try makeDatasetPixelBuffer(named: filename),
                orientation: .up,
                capturedAt: Date(timeIntervalSince1970: 1_768_500_234),
                options: .fullRuntime
            )

            XCTAssertTrue(
                result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue),
                "recordId=\(recordId) semanticActions=\(result.pauseRow.semanticActions) future=\(result.pauseRow.futureActions) debug=\(result.pauseRow.debugNumericFeatures)"
            )
            XCTAssertGreaterThanOrEqual(result.pauseRow.confidence, 0.75, "recordId=\(recordId)")
        }
    }

    @MainActor
    func testStillImageReplayDoesNotOvercorrectCinematicGoodObjectInsertFrames() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        for (recordId, filename) in [
            ("ca_img_035", "035.jpg"),
            ("ca_img_109", "109.jpg"),
            ("ca_img_123", "123.jpg"),
            ("ca_img_131", "131.jpg"),
            ("ca_img_135", "135.jpg")
        ] {
            let result = await pipeline.testingReplayStillImageForSemanticEval(
                recordId: recordId,
                filename: filename,
                pixelBuffer: try makeDatasetPixelBuffer(named: filename),
                orientation: .up,
                capturedAt: Date(timeIntervalSince1970: 1_768_500_235),
                options: .fullRuntime
            )

            XCTAssertTrue(
                result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue),
                "recordId=\(recordId) semanticActions=\(result.pauseRow.semanticActions) future=\(result.pauseRow.futureActions) debug=\(result.pauseRow.debugNumericFeatures)"
            )
            XCTAssertFalse(
                result.pauseRow.semanticActions.contains(SemanticActionType.removeBackgroundHotspot.rawValue) ||
                    result.pauseRow.semanticActions.contains(SemanticActionType.simplifyBackground.rawValue) ||
                    result.pauseRow.semanticActions.contains(SemanticActionType.stepBack.rawValue) ||
                    result.pauseRow.semanticActions.contains(SemanticActionType.stepCloser.rawValue),
                "recordId=\(recordId) semanticActions=\(result.pauseRow.semanticActions)"
            )
        }
    }

    @MainActor
    func testStillImageReplayMapsDistanceAndColorCastSemanticFailures() async throws {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        let stepBackCases = [("ca_img_092", "092.bmp"), ("ca_img_095", "095.bmp")]
        for (recordId, filename) in stepBackCases {
            let result = await pipeline.testingReplayStillImageForSemanticEval(
                recordId: recordId,
                filename: filename,
                pixelBuffer: try makeDatasetPixelBuffer(named: filename),
                orientation: .up,
                capturedAt: Date(timeIntervalSince1970: 1_768_500_223),
                options: .fullRuntime
            )

            XCTAssertTrue(
                result.pauseRow.semanticActions.contains(SemanticActionType.stepBack.rawValue),
                "recordId=\(recordId) semanticActions=\(result.pauseRow.semanticActions) trace=\(result.pauseRow.traceIds)"
            )
            XCTAssertFalse(result.pauseRow.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue))
        }

        let stepCloserResult = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_096",
            filename: "096.bmp",
            pixelBuffer: try makeDatasetPixelBuffer(named: "096.bmp"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_224),
            options: .fullRuntime
        )
        XCTAssertTrue(stepCloserResult.pauseRow.semanticActions.contains(SemanticActionType.stepCloser.rawValue))

        let colorCastResult = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_101",
            filename: "101.jpg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "101.jpg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_225),
            options: .fullRuntime
        )
        XCTAssertTrue(colorCastResult.pauseRow.semanticActions.contains(SemanticActionType.addFrontFillLight.rawValue))
        XCTAssertTrue(colorCastResult.pauseRow.futureActions.contains(TechnicalQualityActionType.reduceExposure.rawValue))
        XCTAssertLessThan(colorCastResult.pauseRow.confidence, 0.75)

        let occludedBlurResult = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_072",
            filename: "072.jpg",
            pixelBuffer: try makeDatasetPixelBuffer(named: "072.jpg"),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_226),
            options: .fullRuntime
        )
        XCTAssertTrue(occludedBlurResult.pauseRow.futureActions.contains(TechnicalQualityActionType.refocusSubject.rawValue))
        XCTAssertTrue(occludedBlurResult.pauseRow.futureActions.contains(TechnicalQualityActionType.avoidOcclusion.rawValue))
    }

    @MainActor
    func testSemanticDemoScenarioPackReplaysExpectedPresentationActions() async throws {
        let scenarios = try loadSemanticDemoScenarios()

        XCTAssertGreaterThanOrEqual(scenarios.count, 5)
        let coveredActions = Set(scenarios.flatMap(\.expectedPauseSemanticActions))
        XCTAssertTrue(coveredActions.contains(SemanticActionType.keepCurrentSetup.rawValue))
        XCTAssertTrue(coveredActions.contains(SemanticActionType.shiftFrameRight.rawValue))
        XCTAssertTrue(coveredActions.contains(SemanticActionType.stepBack.rawValue))
        XCTAssertTrue(coveredActions.contains(SemanticActionType.stepCloser.rawValue))
        XCTAssertTrue(coveredActions.contains(SemanticActionType.addFrontFillLight.rawValue))
        XCTAssertTrue(coveredActions.contains(SemanticActionType.simplifyBackground.rawValue))

        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )

        for scenario in scenarios {
            let result = await pipeline.testingReplayStillImageForSemanticEval(
                recordId: scenario.recordId,
                filename: scenario.filename,
                pixelBuffer: try makeDatasetPixelBuffer(named: scenario.filename),
                orientation: .up,
                capturedAt: Date(timeIntervalSince1970: 1_768_501_000),
                options: .fullRuntime
            )

            XCTAssertTrue(
                result.pauseRow.shown,
                "scenario=\(scenario.id) recordId=\(scenario.recordId)"
            )
            XCTAssertEqual(
                result.pauseRow.runtimeClaim,
                .realRuntimeStillReplay,
                "scenario=\(scenario.id) recordId=\(scenario.recordId)"
            )

            for expectedAction in scenario.expectedPauseSemanticActions {
                XCTAssertTrue(
                    result.pauseRow.semanticActions.contains(expectedAction),
                    "scenario=\(scenario.id) recordId=\(scenario.recordId) expected=\(expectedAction) actual=\(result.pauseRow.semanticActions) trace=\(result.pauseRow.traceIds)"
                )
            }

            for forbiddenAction in scenario.forbiddenPauseSemanticActions {
                XCTAssertFalse(
                    result.pauseRow.semanticActions.contains(forbiddenAction),
                    "scenario=\(scenario.id) recordId=\(scenario.recordId) forbidden=\(forbiddenAction) actual=\(result.pauseRow.semanticActions)"
                )
            }

            for expectedFutureAction in scenario.expectedFutureActions {
                XCTAssertTrue(
                    result.pauseRow.futureActions.contains(expectedFutureAction),
                    "scenario=\(scenario.id) recordId=\(scenario.recordId) expectedFuture=\(expectedFutureAction) actual=\(result.pauseRow.futureActions)"
                )
            }

            if let minimumPauseConfidence = scenario.minimumPauseConfidence {
                XCTAssertGreaterThanOrEqual(
                    result.pauseRow.confidence,
                    minimumPauseConfidence,
                    "scenario=\(scenario.id) recordId=\(scenario.recordId) confidence=\(result.pauseRow.confidence)"
                )
            }

            if let maximumPauseConfidence = scenario.maximumPauseConfidence {
                XCTAssertLessThan(
                    result.pauseRow.confidence,
                    maximumPauseConfidence,
                    "scenario=\(scenario.id) recordId=\(scenario.recordId) confidence=\(result.pauseRow.confidence)"
                )
            }

            if let expectedLiveShown = scenario.expectedLiveShown {
                XCTAssertEqual(
                    result.liveRow.shown,
                    expectedLiveShown,
                    "scenario=\(scenario.id) recordId=\(scenario.recordId) liveTip=\(result.liveRow.liveTip ?? "nil")"
                )
            }

            let liveTip = result.liveRow.liveTip ?? ""
            for fragment in scenario.expectedLiveTextFragments {
                XCTAssertTrue(
                    liveTip.contains(fragment),
                    "scenario=\(scenario.id) recordId=\(scenario.recordId) fragment=\(fragment) liveTip=\(liveTip)"
                )
            }

            let pauseSummary = result.pauseRow.pauseSummary ?? ""
            for fragment in scenario.expectedPauseSummaryFragments {
                XCTAssertTrue(
                    pauseSummary.contains(fragment),
                    "scenario=\(scenario.id) recordId=\(scenario.recordId) fragment=\(fragment) pauseSummary=\(pauseSummary)"
                )
            }
        }
    }

    func testStillImageReplayOptionsOnlyClaimRealRuntimeForHeavyModelPath() {
        XCTAssertEqual(SemanticEvalStillImageReplayOptions.fullRuntime.runtimeClaim, .realRuntimeStillReplay)
        XCTAssertEqual(SemanticEvalStillImageReplayOptions.lightweightTest.runtimeClaim, .testFixture)
    }

    @MainActor
    func testStillImageReplayExportsRowsWithoutClaimingRealRuntimeWhenHeavyModelsAreDisabled() async {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil
        )
        let result = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "ca_img_test",
            filename: "test.jpg",
            pixelBuffer: makePixelBuffer(width: 32, height: 32),
            orientation: .up,
            capturedAt: Date(timeIntervalSince1970: 1_768_500_000),
            options: .lightweightTest
        )

        XCTAssertEqual(result.recordId, "ca_img_test")
        XCTAssertEqual(result.filename, "test.jpg")
        XCTAssertEqual(result.frameId, "semantic_eval_ca_img_test")
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.liveRow.recordId, "ca_img_test")
        XCTAssertEqual(result.liveRow.filename, "test.jpg")
        XCTAssertEqual(result.liveRow.mode, "live")
        XCTAssertEqual(result.liveRow.source, "swift_still_image_replay_lightweight_test")
        XCTAssertEqual(result.liveRow.runtimeClaim, .testFixture)
        XCTAssertEqual(result.pauseRow.recordId, "ca_img_test")
        XCTAssertEqual(result.pauseRow.filename, "test.jpg")
        XCTAssertEqual(result.pauseRow.mode, "pause")
        XCTAssertEqual(result.pauseRow.source, "swift_still_image_replay_lightweight_test")
        XCTAssertEqual(result.pauseRow.runtimeClaim, .testFixture)
    }

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

    func testGoodPauseVerdictWithExplicitStrengthUsesHighConfidenceFloor() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let critique = makeGoodPauseCritique(
            frameId: "pause-good-strength-confidence",
            verdictConfidence: 0.64,
            strengths: [
                FrameStrength(
                    id: "str_good_light",
                    type: .goodLightEmphasis,
                    confidence: 0.62,
                    rationale: "Свет помогает читать героя.",
                    evidence: [EvidenceRef(source: .snapshot, key: "strength.goodLightEmphasis", value: "true")]
                )
            ]
        )
        let plan = makeNoChangePlan(for: critique)

        let presentation = pipeline.testingMakePauseCritiquePresentation(
            critique: critique,
            plan: plan
        )

        XCTAssertEqual(presentation.verdictConfidence, 0.75, accuracy: 0.0001)
        XCTAssertEqual(presentation.noChangeRationale, "Сохраните текущую композицию.")
    }

    func testGoodPauseVerdictWithoutStrengthKeepsConservativeConfidence() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let critique = makeGoodPauseCritique(
            frameId: "pause-good-no-strength-confidence",
            verdictConfidence: 0.64,
            strengths: []
        )
        let plan = makeNoChangePlan(for: critique)

        let presentation = pipeline.testingMakePauseCritiquePresentation(
            critique: critique,
            plan: plan
        )

        XCTAssertEqual(presentation.verdictConfidence, 0.64, accuracy: 0.0001)
    }

    func testMixedPauseCorrectiveVerdictConfidenceIsCappedToMedium() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let critique = makeMixedPauseCritique(
            frameId: "pause-mixed-corrective-confidence",
            verdictConfidence: 0.86
        )
        let action = RecommendationAction(
            id: "act_simplify_background",
            actionType: .reduceBackgroundDistractions,
            priority: 1,
            targetRegion: nil,
            linkedIssueIds: ["iss_background"],
            expectedOutcome: "Упростите фон, чтобы главный объект читался лучше.",
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
            planConfidence: 0.86
        )

        let presentation = pipeline.testingMakePauseCritiquePresentation(
            critique: critique,
            plan: plan
        )

        XCTAssertEqual(presentation.verdictConfidence, 0.74, accuracy: 0.0001)
        XCTAssertEqual(presentation.actions.first?.semanticActionType, .simplifyBackground)
    }

    func testPausePresentationKeepsActionIssueAndTraceOnOneFrameProjection() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let frameID = "pause-linked-projection"
        let critique = makeMixedPauseCritique(
            frameId: frameID,
            verdictConfidence: 0.82
        )
        let action = RecommendationAction(
            id: "act_simplify_background",
            actionType: .reduceBackgroundDistractions,
            priority: 1,
            targetRegion: nil,
            linkedIssueIds: ["iss_background"],
            expectedOutcome: "Упростите фон.",
            guardrail: ActionGuardrail(
                requiresStillCamera: true,
                minConfidence: 0.4,
                suppressWhenMoving: true
            ),
            overlayHint: nil
        )
        let plan = RecommendationPlan(
            frameId: frameID,
            mode: .pause,
            inputVerdict: critique.verdict,
            primaryAction: action,
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.82
        )

        let presentation = pipeline.testingMakePauseCritiquePresentation(
            critique: critique,
            plan: plan
        )

        guard let projection = presentation.linkedEvidence else {
            return XCTFail("observed issue evidence must produce a pause projection")
        }
        XCTAssertEqual(projection.frameID, frameID)
        XCTAssertEqual(projection.actionID, presentation.actions.first?.actionId)
        XCTAssertEqual(projection.actionID, action.id)
        XCTAssertEqual(projection.issueID, "iss_background")
        XCTAssertEqual(projection.issueType, .frameVisuallyOverloaded)

        let trace = DecisionTracePresentation.pause(critique: presentation)
        XCTAssertEqual(
            trace.reasonLines.map(\.text),
            [SETCopyKey.traceIssueOverloaded.localizedString(locale: Locale(identifier: "ru"))]
        )
        XCTAssertEqual(trace.evidenceRows.map(\.sourceId), ["iss_background"])
        XCTAssertEqual(trace.actionRows.first?.linkedEvidenceIds, ["iss_background"])
    }

    func testPauseProjectionUsesDecisionTraceOrderWhenSemanticRankConflictsWithPriority() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let frameID = "pause-action-order"
        let critique = makeCritiqueWithTwoIssues(frameId: frameID)
        let semanticRankFirst = RecommendationAction(
            id: "semantic_rank_first",
            actionType: .moveFrameLeft,
            priority: 2,
            targetRegion: nil,
            linkedIssueIds: ["iss_high"],
            expectedOutcome: "Сместите камеру левее.",
            guardrail: ActionGuardrail(
                requiresStillCamera: true,
                minConfidence: 0.4,
                suppressWhenMoving: true
            ),
            overlayHint: nil
        )
        let priorityFirst = RecommendationAction(
            id: "priority_first",
            actionType: .reduceBackgroundDistractions,
            priority: 1,
            targetRegion: nil,
            linkedIssueIds: ["iss_low"],
            expectedOutcome: "Упростите фон.",
            guardrail: ActionGuardrail(
                requiresStillCamera: true,
                minConfidence: 0.4,
                suppressWhenMoving: true
            ),
            overlayHint: nil
        )
        let plan = RecommendationPlan(
            frameId: frameID,
            mode: .pause,
            inputVerdict: critique.verdict,
            primaryAction: semanticRankFirst,
            secondaryActions: [priorityFirst],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.82
        )

        let presentation = pipeline.testingMakePauseCritiquePresentation(
            critique: critique,
            plan: plan
        )

        XCTAssertEqual(presentation.actions.map(\.actionId), ["priority_first", "semantic_rank_first"])
        XCTAssertEqual(presentation.linkedEvidence?.actionID, "priority_first")
        XCTAssertEqual(presentation.linkedEvidence?.issueID, "iss_low")

        let trace = DecisionTracePresentation.pause(critique: presentation)
        XCTAssertEqual(trace.actionRows.first?.id, "priority_first")
        XCTAssertEqual(trace.actionRows.first?.linkedEvidenceIds, ["iss_low"])
        XCTAssertEqual(trace.evidenceRows.map(\.sourceId), ["iss_low"])
    }

    func testPauseProjectionFailsClosedWhenOnlySecondaryActionHasObservedEvidence() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let frameID = "pause-primary-provenance"
        let critique = CritiqueReport(
            frameId: frameID,
            mode: .pause,
            verdict: .mixed,
            verdictConfidence: 0.81,
            strengths: [],
            issues: [
                FrameIssue(
                    id: "iss_primary_neural_only",
                    type: .subjectTooCloseToEdge,
                    severity: 0.81,
                    confidence: 0.83,
                    rationale: "Первичный совет не подтверждён наблюдаемым источником.",
                    evidence: [
                        EvidenceRef(
                            source: .neuralEvidence,
                            key: "neural.edge_probability",
                            value: "0.91"
                        )
                    ],
                    affectedRegion: NormalizedRect(x: 0.05, y: 0.20, width: 0.24, height: 0.42),
                    suggestedFixTypes: [.reframing]
                ),
                FrameIssue(
                    id: "iss_secondary_observed",
                    type: .backgroundCompetesWithSubject,
                    severity: 0.62,
                    confidence: 0.71,
                    rationale: "Вторичный совет подтверждён наблюдаемым источником.",
                    evidence: [
                        EvidenceRef(
                            source: .snapshot,
                            key: "background.clutter",
                            value: "medium"
                        )
                    ],
                    affectedRegion: NormalizedRect(x: 0.58, y: 0.18, width: 0.28, height: 0.40),
                    suggestedFixTypes: [.reframing]
                )
            ],
            summary: CritiqueSummary(
                id: "summary_(frameID)",
                shortVerdict: "Проверка кадра требует осторожности.",
                whyGood: nil,
                whyProblematic: "Только один из советов имеет наблюдаемое подтверждение."
            ),
            traceRefs: ["trace_(frameID)"],
            fallbackUsed: false
        )
        let primaryAction = RecommendationAction(
            id: "act_primary",
            actionType: .moveFrameLeft,
            priority: 1,
            targetRegion: critique.issues[0].affectedRegion,
            linkedIssueIds: ["iss_primary_neural_only"],
            expectedOutcome: "Сместите камеру влево.",
            guardrail: ActionGuardrail(
                requiresStillCamera: true,
                minConfidence: 0.4,
                suppressWhenMoving: true
            ),
            overlayHint: nil
        )
        let secondaryAction = RecommendationAction(
            id: "act_secondary",
            actionType: .reduceBackgroundDistractions,
            priority: 2,
            targetRegion: critique.issues[1].affectedRegion,
            linkedIssueIds: ["iss_secondary_observed"],
            expectedOutcome: "Упростите фон.",
            guardrail: ActionGuardrail(
                requiresStillCamera: true,
                minConfidence: 0.4,
                suppressWhenMoving: true
            ),
            overlayHint: nil
        )
        let plan = RecommendationPlan(
            frameId: frameID,
            mode: .pause,
            inputVerdict: critique.verdict,
            primaryAction: primaryAction,
            secondaryActions: [secondaryAction],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.81
        )

        let presentation = pipeline.testingMakePauseCritiquePresentation(
            critique: critique,
            plan: plan
        )

        XCTAssertEqual(presentation.actions.map(\.actionId), ["act_primary", "act_secondary"])
        XCTAssertNil(presentation.linkedEvidence)
        let trace = DecisionTracePresentation.pause(critique: presentation)
        XCTAssertTrue(trace.reasonLines.isEmpty)
        XCTAssertTrue(trace.evidenceRows.isEmpty)
        XCTAssertTrue(trace.actionRows.allSatisfy { $0.linkedEvidenceIds.isEmpty })
    }

    func testCommittedPauseRotationReprojectsMarkerWithoutChangingProvenance() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let frameID = "pause-rotation-identity"
        let critique = makeMixedPauseCritique(
            frameId: frameID,
            verdictConfidence: 0.82
        )
        let targetRegion = NormalizedRect(x: 0.58, y: 0.18, width: 0.28, height: 0.40)
        let action = RecommendationAction(
            id: "act_rotation",
            actionType: .reduceBackgroundDistractions,
            priority: 1,
            targetRegion: targetRegion,
            linkedIssueIds: ["iss_background"],
            expectedOutcome: "Упростите фон.",
            guardrail: ActionGuardrail(
                requiresStillCamera: true,
                minConfidence: 0.4,
                suppressWhenMoving: true
            ),
            overlayHint: nil
        )
        let plan = RecommendationPlan(
            frameId: frameID,
            mode: .pause,
            inputVerdict: critique.verdict,
            primaryAction: action,
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.82
        )
        let presentation = pipeline.testingMakePauseCritiquePresentation(
            critique: critique,
            plan: plan
        )

        guard let projection = presentation.linkedEvidence,
              let pauseAction = presentation.actions.first,
              let pauseTargetRegion = pauseAction.targetRegion else {
            return XCTFail("a committed observed pause must retain its marker projection")
        }
        let store = LatestFrameEvidenceStore()
        XCTAssertTrue(store.publish(
            pixelBuffer: makePixelBuffer(width: 4, height: 2),
            orientation: .right,
            sourceFrameId: frameID,
            capturedAt: Date(timeIntervalSince1970: 90),
            isStable: true
        ))
        guard let accepted = store.acceptCurrentSnapshot(),
              let rendered = store.renderDisplayImage(for: accepted) else {
            return XCTFail("the accepted pause frame must render before rotation")
        }

        XCTAssertEqual(accepted.snapshotID, frameID)
        XCTAssertEqual(rendered.snapshotID, frameID)
        XCTAssertEqual(rendered.sourcePixelSize, accepted.sourcePixelSize)
        XCTAssertEqual(rendered.orientation, accepted.orientation)
        XCTAssertEqual(projection.frameID, frameID)
        XCTAssertEqual(projection.actionID, pauseAction.actionId)
        XCTAssertEqual(projection.actionID, action.id)
        XCTAssertEqual(projection.issueID, pauseAction.linkedIssueIds.first)

        let portraitMarker = SETAcceptedFrameRegionMapper.map(
            pauseTargetRegion,
            sourcePixelSize: rendered.sourcePixelSize,
            orientation: rendered.orientation,
            canvasSize: CGSize(width: 390, height: 844)
        )
        let landscapeMarker = SETAcceptedFrameRegionMapper.map(
            pauseTargetRegion,
            sourcePixelSize: rendered.sourcePixelSize,
            orientation: rendered.orientation,
            canvasSize: CGSize(width: 844, height: 390)
        )
        XCTAssertNotNil(portraitMarker)
        XCTAssertNotNil(landscapeMarker)
        XCTAssertNotEqual(portraitMarker, landscapeMarker)
        XCTAssertTrue(portraitMarker.map(CGRect(origin: .zero, size: CGSize(width: 390, height: 844)).contains) == true)
        XCTAssertTrue(landscapeMarker.map(CGRect(origin: .zero, size: CGSize(width: 844, height: 390)).contains) == true)

        let portraitTrace = DecisionTracePresentation.pause(critique: presentation)
        let landscapeTrace = DecisionTracePresentation.pause(critique: presentation)
        XCTAssertEqual(portraitTrace, landscapeTrace)
        XCTAssertEqual(portraitTrace.evidenceRows.map(\.sourceId), [projection.issueID])
        XCTAssertEqual(portraitTrace.actionRows.first?.linkedEvidenceIds, [projection.issueID])
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
        let subjectRegion = NormalizedRect(x: 0.34, y: 0.18, width: 0.28, height: 0.50)
        let snapshot = makeDemoLiveSnapshot(
            frameId: critique.frameId,
            subjectSignals: .init(
                faceDetected: true,
                personDetected: true,
                personCount: 1,
                topObjectLabel: "person",
                topObjectConfidence: 0.88,
                topObjectRegion: subjectRegion,
                primaryCandidateRegion: subjectRegion,
                primaryCandidateConfidence: 0.90
            ),
            objects: .init(totalCount: 1, topKLabels: ["person"])
        )
        let semantics = makeDemoSemantics(
            frameId: critique.frameId,
            primarySubject: .init(kind: .face, region: subjectRegion, confidence: 0.90),
            sceneType: .singleCharacterMedium
        )
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
                snapshot: snapshot,
                critique: critique,
                plan: plan,
                semantics: semantics,
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

    func testLiveCompositionFallbackClearsPreviousHintWithoutPublishingReserveCard() async {
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
                now: Date(timeIntervalSince1970: 1_768_500_310)
            )
        }

        await MainActor.run {
            XCTAssertNil(pipeline.currentLiveHint)
            XCTAssertFalse(pipeline.testingHasPauseReasoningTask)
        }
    }

    func testCriticalHorizonLegacyFallbackStillPublishesLiveHint() async {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let critique = makeHorizonCritique(frameId: "live-horizon-fallback")
        let plan = RecommendationPlan(
            frameId: critique.frameId,
            mode: .live,
            inputVerdict: critique.verdict,
            primaryAction: nil,
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.48
        )
        let fallbackSuggestion = Suggestion(
            text: "Выровняйте горизонт.",
            priority: .critical,
            type: .horizon,
            ttl: 4.0,
            createdAt: Date(timeIntervalSince1970: 1_768_500_320)
        )

        await MainActor.run {
            pipeline.testingPublishLivePresentation(
                frameId: critique.frameId,
                critique: critique,
                plan: plan,
                legacySuggestion: fallbackSuggestion,
                structuredAvailable: false,
                now: Date(timeIntervalSince1970: 1_768_500_320)
            )
        }

        await MainActor.run {
            XCTAssertTrue(pipeline.currentLiveHint?.isFallback == true)
            XCTAssertEqual(
                pipeline.currentLiveHint?.text,
                SETCameraCopy.actionKey(for: ActionTypeV1.levelHorizon).localizedString(locale: .current)
            )
            XCTAssertEqual(pipeline.currentLiveHint?.actionType, .levelHorizon)
            XCTAssertEqual(pipeline.currentLiveHint?.expandedVerdict?.shortVerdict, critique.summary.shortVerdict)
            XCTAssertFalse(pipeline.testingHasPauseReasoningTask)
        }
    }

    func testDemoLiveSemanticActionWhitelistKeepsAmbiguousCompositionOutOfLive() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let allowedActions: [SemanticActionType] = [
            .keepCurrentSetup,
            .simplifyBackground,
            .waitForBackgroundClearance,
            .stepBack,
            .stepCloser,
            .addFrontFillLight,
            .removeBackgroundHotspot,
            .levelHorizon,
        ]
        let forbiddenActions: [SemanticActionType] = [
            .lowerCamera,
            .raiseCamera,
            .changeCameraAngle,
            .rotateSubjectTowardLight,
            .moveSubjectLeft,
            .moveSubjectRight,
            .removeDistractingObject,
            .repositionPropForBalance,
        ]

        for action in allowedActions {
            XCTAssertTrue(pipeline.testingIsAllowedDemoLiveSemanticAction(action), "\(action.rawValue) should be allowed in demo live hints.")
        }
        for action in forbiddenActions {
            XCTAssertFalse(pipeline.testingIsAllowedDemoLiveSemanticAction(action), "\(action.rawValue) should stay out of live hints.")
        }
    }

    func testLivePositiveConfirmationWaitsForGroundedSubjectEvidence() async {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let frameId = "frame-good-unknown-subject"
        let critique = CritiqueReport(
            frameId: frameId,
            mode: .live,
            verdict: .good,
            verdictConfidence: 0.92,
            strengths: [],
            issues: [],
            summary: CritiqueSummary(
                id: "summary_\(frameId)",
                shortVerdict: "Кадр работает.",
                whyGood: "Кадр читается стабильно.",
                whyProblematic: nil
            ),
            traceRefs: ["trace_\(frameId)"],
            fallbackUsed: false
        )
        let plan = RecommendationPlan(
            frameId: frameId,
            mode: .live,
            inputVerdict: .good,
            primaryAction: nil,
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: "Кадр читается стабильно, критичных проблем не выявлено.",
            planConfidence: 0.88
        )

        await MainActor.run {
            pipeline.testingPublishLivePresentation(
                frameId: frameId,
                critique: critique,
                plan: plan,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: Date(timeIntervalSince1970: 1_768_500_320)
            )
        }

        await MainActor.run {
            XCTAssertNil(pipeline.currentLiveHint)
        }
    }

    func testDemoObjectModePublishesCupBoundingBoxAndCorrectionInsteadOfFalseGood() async {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, demoLiveCoachEnabled: true)
        let frameId = "demo-cup-edge"
        let cupRegion = NormalizedRect(x: 0.02, y: 0.32, width: 0.18, height: 0.36)
        let snapshot = makeDemoLiveSnapshot(
            frameId: frameId,
            subjectSignals: .init(
                faceDetected: false,
                personDetected: false,
                personCount: 0,
                topObjectLabel: "cup",
                topObjectConfidence: 0.83,
                topObjectRegion: cupRegion,
                primaryCandidateRegion: cupRegion,
                primaryCandidateConfidence: 0.83
            ),
            objects: .init(totalCount: 2, topKLabels: ["cup", "chair"])
        )
        let semantics = makeDemoSemantics(
            frameId: frameId,
            primarySubject: .init(kind: .unknown, confidence: 0.18),
            sceneType: .objectInsert
        )

        await MainActor.run {
            pipeline.setCameraDemoSceneMode(.object)
            pipeline.testingPublishLivePresentation(
                frameId: frameId,
                snapshot: snapshot,
                critique: makeCritique(frameId: frameId, verdict: .good),
                plan: makeDemoNoChangePlan(frameId: frameId),
                semantics: semantics,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: Date(timeIntervalSince1970: 1_768_500_330)
            )
        }

        await MainActor.run {
            XCTAssertEqual(pipeline.currentLiveHint?.targetRegion, cupRegion)
            XCTAssertTrue(
                objectDemoCatalogInstructions.contains(pipeline.currentLiveHint?.text ?? "")
            )
            XCTAssertFalse(pipeline.currentLiveHint?.text.contains("стаканчик") == true)
            XCTAssertNotEqual(pipeline.currentLiveHint?.actionType, .leaveFrameAsIs)
            XCTAssertEqual(pipeline.currentOverlayAnnotations.first?.targetRegion, cupRegion)
            XCTAssertEqual(pipeline.currentOverlayAnnotations.first?.label, "Объект")
            XCTAssertEqual(pipeline.currentOverlayAnnotations.first?.tone, .danger)
            XCTAssertTrue(pipeline.currentLiveHint?.expandedVerdict?.supportingText?.contains("cup") == true)
        }
    }

    func testDemoAutoModeKeepsFaceAheadOfBackgroundObjectLabels() async {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, demoLiveCoachEnabled: true)
        let frameId = "demo-face-background"
        let faceRegion = NormalizedRect(x: 0.18, y: 0.20, width: 0.30, height: 0.44)
        let tvRegion = NormalizedRect(x: 0.58, y: 0.08, width: 0.34, height: 0.28)
        let snapshot = makeDemoLiveSnapshot(
            frameId: frameId,
            subjectSignals: .init(
                faceDetected: true,
                personDetected: true,
                personCount: 1,
                topObjectLabel: "tv",
                topObjectConfidence: 0.91,
                topObjectRegion: tvRegion,
                primaryCandidateRegion: faceRegion,
                primaryCandidateConfidence: 0.86
            ),
            lighting: .init(exposureBiasHint: -0.62, backlightIndex: 0.08, keyToFillRatio: nil),
            objects: .init(totalCount: 3, topKLabels: ["tv", "paper", "chair"])
        )
        let semantics = makeDemoSemantics(
            frameId: frameId,
            primarySubject: .init(kind: .face, region: faceRegion, confidence: 0.86),
            sceneType: .singleCharacterMedium
        )

        await MainActor.run {
            pipeline.setCameraDemoSceneMode(.auto)
            pipeline.testingPublishLivePresentation(
                frameId: frameId,
                snapshot: snapshot,
                critique: makeCritique(frameId: frameId, verdict: .good),
                plan: makeDemoNoChangePlan(frameId: frameId),
                semantics: semantics,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: Date(timeIntervalSince1970: 1_768_500_340)
            )
        }

        await MainActor.run {
            XCTAssertEqual(pipeline.currentOverlayAnnotations.first?.targetRegion, faceRegion)
            XCTAssertEqual(pipeline.currentOverlayAnnotations.first?.label, "Лицо")
            XCTAssertEqual(pipeline.currentOverlayAnnotations.first?.tone, .danger)
            XCTAssertTrue(
                portraitDemoCatalogInstructions.contains(pipeline.currentLiveHint?.text ?? "")
            )
        }
    }

    func testDemoPortraitPrefersFaceRegionOverBodySemanticRegion() async {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, demoLiveCoachEnabled: true)
        let frameId = "demo-face-region-not-body"
        let faceRegion = NormalizedRect(x: 0.18, y: 0.18, width: 0.18, height: 0.24)
        let bodyRegion = NormalizedRect(x: 0.10, y: 0.30, width: 0.26, height: 0.50)
        let snapshot = makeDemoLiveSnapshot(
            frameId: frameId,
            subjectSignals: .init(
                faceDetected: true,
                personDetected: true,
                personCount: 1,
                faceRegion: faceRegion,
                primaryCandidateRegion: bodyRegion,
                primaryCandidateConfidence: 0.90
            ),
            objects: .init(totalCount: 2, topKLabels: ["person", "screen"])
        )
        let semantics = makeDemoSemantics(
            frameId: frameId,
            primarySubject: .init(kind: .person, region: bodyRegion, confidence: 0.90),
            sceneType: .singleCharacterMedium
        )

        await MainActor.run {
            pipeline.setCameraDemoSceneMode(.portrait)
            pipeline.testingPublishLivePresentation(
                frameId: frameId,
                snapshot: snapshot,
                critique: makeCritique(frameId: frameId, verdict: .good),
                plan: makeDemoNoChangePlan(frameId: frameId),
                semantics: semantics,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: Date(timeIntervalSince1970: 1_768_500_345)
            )
        }

        await MainActor.run {
            XCTAssertEqual(pipeline.currentOverlayAnnotations.first?.targetRegion, faceRegion)
            XCTAssertEqual(pipeline.currentOverlayAnnotations.first?.label, "Лицо")
            XCTAssertNotEqual(pipeline.currentOverlayAnnotations.first?.targetRegion, bodyRegion)
        }
    }

    func testDemoObjectModeFallsBackToPrimaryCandidateWhenDetectorLabelMissing() async {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, demoLiveCoachEnabled: true)
        let frameId = "demo-object-primary-fallback"
        let objectRegion = NormalizedRect(x: 0.39, y: 0.30, width: 0.20, height: 0.34)
        let snapshot = makeDemoLiveSnapshot(
            frameId: frameId,
            subjectSignals: .init(
                faceDetected: false,
                personDetected: false,
                personCount: 0,
                primaryCandidateRegion: objectRegion,
                primaryCandidateConfidence: 0.62
            ),
            objects: .init(totalCount: 1, topKLabels: [])
        )
        let semantics = makeDemoSemantics(
            frameId: frameId,
            primarySubject: .init(kind: .unknown, confidence: 0.20),
            sceneType: .objectInsert
        )

        await MainActor.run {
            pipeline.setCameraDemoSceneMode(.object)
            pipeline.testingPublishLivePresentation(
                frameId: frameId,
                snapshot: snapshot,
                critique: makeCritique(frameId: frameId, verdict: .good),
                plan: makeDemoNoChangePlan(frameId: frameId),
                semantics: semantics,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: Date(timeIntervalSince1970: 1_768_500_346)
            )
        }

        await MainActor.run {
            XCTAssertEqual(pipeline.currentOverlayAnnotations.first?.targetRegion, objectRegion)
            XCTAssertEqual(pipeline.currentOverlayAnnotations.first?.label, "Объект")
            XCTAssertEqual(
                pipeline.currentLiveHint?.text,
                SETCopyKey.cameraSeeking.localizedString(locale: .current)
            )
        }
    }

    func testDemoObjectModeRejectsOversizedPrimaryCandidateFallback() async {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, demoLiveCoachEnabled: true)
        let frameId = "demo-object-oversized-fallback"
        let oversizedRegion = NormalizedRect(x: 0.00, y: 0.22, width: 1.00, height: 0.77)
        let snapshot = makeDemoLiveSnapshot(
            frameId: frameId,
            subjectSignals: .init(
                faceDetected: false,
                personDetected: false,
                personCount: 0,
                primaryCandidateRegion: oversizedRegion,
                primaryCandidateConfidence: 0.48
            ),
            objects: .init(totalCount: 0, topKLabels: [])
        )
        let semantics = makeDemoSemantics(
            frameId: frameId,
            primarySubject: .init(kind: .unknown, confidence: 0.12),
            sceneType: .objectInsert
        )

        await MainActor.run {
            pipeline.setCameraDemoSceneMode(.object)
            pipeline.testingPublishLivePresentation(
                frameId: frameId,
                snapshot: snapshot,
                critique: makeCritique(frameId: frameId, verdict: .good),
                plan: makeDemoNoChangePlan(frameId: frameId),
                semantics: semantics,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: Date(timeIntervalSince1970: 1_768_500_347)
            )
        }

        await MainActor.run {
            XCTAssertTrue(pipeline.currentOverlayAnnotations.isEmpty)
            XCTAssertNotEqual(pipeline.currentLiveHint?.targetRegion, oversizedRegion)
        }
    }

    func testDemoGoodFrameTurnsCheckOnlyAfterThreeStableFrames() async {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, demoLiveCoachEnabled: true)
        let cupRegion = NormalizedRect(x: 0.40, y: 0.30, width: 0.20, height: 0.34)
        let firstFrame = "demo-cup-stable-1"
        let secondFrame = "demo-cup-stable-2"
        let thirdFrame = "demo-cup-stable-3"
        let snapshot1 = makeDemoLiveSnapshot(
            frameId: firstFrame,
            subjectSignals: .init(
                faceDetected: false,
                personDetected: false,
                personCount: 0,
                topObjectLabel: "cup",
                topObjectConfidence: 0.86,
                topObjectRegion: cupRegion,
                primaryCandidateRegion: cupRegion,
                primaryCandidateConfidence: 0.86
            ),
            objects: .init(totalCount: 1, topKLabels: ["cup"])
        )
        let snapshot2 = makeDemoLiveSnapshot(
            frameId: secondFrame,
            subjectSignals: snapshot1.subjectSignals,
            objects: snapshot1.objects
        )
        let snapshot3 = makeDemoLiveSnapshot(
            frameId: thirdFrame,
            subjectSignals: snapshot1.subjectSignals,
            objects: snapshot1.objects
        )
        let semantics1 = makeDemoSemantics(
            frameId: firstFrame,
            primarySubject: .init(kind: .object, label: "cup", region: cupRegion, confidence: 0.86),
            sceneType: .objectInsert
        )
        let semantics2 = makeDemoSemantics(
            frameId: secondFrame,
            primarySubject: .init(kind: .object, label: "cup", region: cupRegion, confidence: 0.86),
            sceneType: .objectInsert
        )
        let semantics3 = makeDemoSemantics(
            frameId: thirdFrame,
            primarySubject: .init(kind: .object, label: "cup", region: cupRegion, confidence: 0.86),
            sceneType: .objectInsert
        )

        await MainActor.run {
            pipeline.setCameraDemoSceneMode(.object)
            pipeline.testingPublishLivePresentation(
                frameId: firstFrame,
                snapshot: snapshot1,
                critique: makeCritique(frameId: firstFrame, verdict: .good),
                plan: makeDemoNoChangePlan(frameId: firstFrame),
                semantics: semantics1,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: Date(timeIntervalSince1970: 1_768_500_350)
            )
        }

        await MainActor.run {
            XCTAssertEqual(pipeline.currentOverlayAnnotations.first?.tone, .warning)
            XCTAssertEqual(
                pipeline.currentLiveHint?.text,
                SETCopyKey.cameraSeeking.localizedString(locale: .current)
            )
        }

        await MainActor.run {
            pipeline.testingPublishLivePresentation(
                frameId: secondFrame,
                snapshot: snapshot2,
                critique: makeCritique(frameId: secondFrame, verdict: .good),
                plan: makeDemoNoChangePlan(frameId: secondFrame),
                semantics: semantics2,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: Date(timeIntervalSince1970: 1_768_500_351)
            )
        }

        await MainActor.run {
            XCTAssertEqual(pipeline.currentOverlayAnnotations.first?.tone, .warning)
            XCTAssertEqual(
                pipeline.currentLiveHint?.text,
                SETCopyKey.cameraSeeking.localizedString(locale: .current)
            )
        }

        await MainActor.run {
            pipeline.testingPublishLivePresentation(
                frameId: thirdFrame,
                snapshot: snapshot3,
                critique: makeCritique(frameId: thirdFrame, verdict: .good),
                plan: makeDemoNoChangePlan(frameId: thirdFrame),
                semantics: semantics3,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: Date(timeIntervalSince1970: 1_768_500_352)
            )
        }

        await MainActor.run {
            XCTAssertTrue(pipeline.currentOverlayAnnotations.isEmpty)
            XCTAssertEqual(pipeline.currentLiveHint?.actionType, .leaveFrameAsIs)
            XCTAssertEqual(
                pipeline.currentLiveHint?.text,
                SETCameraCopy.actionKey(for: .leaveFrameAsIs).localizedString(locale: .current)
            )
        }
    }

    func testDemoObjectJitterStillReachesCheckOnlyGoodState() async {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, demoLiveCoachEnabled: true)
        let regions = [
            NormalizedRect(x: 0.23, y: 0.30, width: 0.20, height: 0.34),
            NormalizedRect(x: 0.245, y: 0.305, width: 0.20, height: 0.34),
            NormalizedRect(x: 0.255, y: 0.295, width: 0.20, height: 0.34)
        ]

        await MainActor.run {
            pipeline.setCameraDemoSceneMode(.object)
        }

        for (index, region) in regions.enumerated() {
            let frameId = "demo-cup-jitter-\(index + 1)"
            let snapshot = makeDemoLiveSnapshot(
                frameId: frameId,
                subjectSignals: .init(
                    faceDetected: false,
                    personDetected: false,
                    personCount: 0,
                    topObjectLabel: "cup",
                    topObjectConfidence: 0.86,
                    topObjectRegion: region,
                    primaryCandidateRegion: region,
                    primaryCandidateConfidence: 0.86
                ),
                objects: .init(totalCount: 1, topKLabels: ["cup"])
            )
            let semantics = makeDemoSemantics(
                frameId: frameId,
                primarySubject: .init(kind: .object, label: "cup", region: region, confidence: 0.86),
                sceneType: .objectInsert
            )
            await MainActor.run {
                pipeline.testingPublishLivePresentation(
                    frameId: frameId,
                    snapshot: snapshot,
                    critique: makeCritique(frameId: frameId, verdict: .good),
                    plan: makeDemoNoChangePlan(frameId: frameId),
                    semantics: semantics,
                    legacySuggestion: nil,
                    structuredAvailable: true,
                    now: Date(timeIntervalSince1970: 1_768_500_360 + Double(index))
                )
            }
        }

        await MainActor.run {
            XCTAssertTrue(pipeline.currentOverlayAnnotations.isEmpty)
            XCTAssertEqual(pipeline.currentLiveHint?.actionType, .leaveFrameAsIs)
            XCTAssertEqual(
                pipeline.currentLiveHint?.text,
                SETCameraCopy.actionKey(for: .leaveFrameAsIs).localizedString(locale: .current)
            )
        }
    }

    func testDemoSubjectHoldKeepsLastBoundingBoxAcrossShortMiss() async {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, demoLiveCoachEnabled: true)
        let cupRegion = NormalizedRect(x: 0.03, y: 0.30, width: 0.18, height: 0.34)
        let firstFrame = "demo-cup-hold-1"
        let missFrame = "demo-cup-hold-2"
        let snapshot = makeDemoLiveSnapshot(
            frameId: firstFrame,
            subjectSignals: .init(
                faceDetected: false,
                personDetected: false,
                personCount: 0,
                topObjectLabel: "cup",
                topObjectConfidence: 0.86,
                topObjectRegion: cupRegion,
                primaryCandidateRegion: cupRegion,
                primaryCandidateConfidence: 0.86
            ),
            objects: .init(totalCount: 1, topKLabels: ["cup"])
        )
        let missSnapshot = makeDemoLiveSnapshot(
            frameId: missFrame,
            subjectSignals: .init(
                faceDetected: false,
                personDetected: false,
                personCount: 0
            ),
            objects: .init(totalCount: 0, topKLabels: [])
        )

        await MainActor.run {
            pipeline.setCameraDemoSceneMode(.object)
            pipeline.testingPublishLivePresentation(
                frameId: firstFrame,
                snapshot: snapshot,
                critique: makeCritique(frameId: firstFrame, verdict: .mixed),
                plan: makeDemoNoChangePlan(frameId: firstFrame),
                semantics: makeDemoSemantics(
                    frameId: firstFrame,
                    primarySubject: .init(kind: .object, label: "cup", region: cupRegion, confidence: 0.86),
                    sceneType: .objectInsert
                ),
                legacySuggestion: nil,
                structuredAvailable: true,
                now: Date(timeIntervalSince1970: 1_768_500_370)
            )
            pipeline.testingPublishLivePresentation(
                frameId: missFrame,
                snapshot: missSnapshot,
                critique: makeCritique(frameId: missFrame, verdict: .good),
                plan: makeDemoNoChangePlan(frameId: missFrame),
                semantics: makeDemoSemantics(
                    frameId: missFrame,
                    primarySubject: .init(kind: .unknown, confidence: 0.1),
                    sceneType: .objectInsert
                ),
                legacySuggestion: nil,
                structuredAvailable: true,
                now: Date(timeIntervalSince1970: 1_768_500_370.4)
            )
        }

        await MainActor.run {
            XCTAssertEqual(pipeline.currentOverlayAnnotations.first?.targetRegion, cupRegion)
            XCTAssertEqual(pipeline.currentOverlayAnnotations.first?.label, "Объект")
            XCTAssertEqual(
                pipeline.currentLiveHint?.text,
                SETCopyKey.cameraSeeking.localizedString(locale: .current)
            )
        }
    }

    func testDemoPortraitUsesSubjectLightingForBrightBackground() async {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, demoLiveCoachEnabled: true)
        let faceRegion = NormalizedRect(x: 0.25, y: 0.20, width: 0.30, height: 0.44)
        let frameId = "demo-face-bright-background"
        let snapshot = makeDemoLiveSnapshot(
            frameId: frameId,
            subjectSignals: .init(
                faceDetected: true,
                personDetected: true,
                personCount: 1,
                primaryCandidateRegion: faceRegion,
                primaryCandidateConfidence: 0.88
            ),
            lighting: .init(
                exposureBiasHint: 0.0,
                backlightIndex: 0.0,
                keyToFillRatio: nil,
                subjectLighting: .init(
                    subjectMeanLuma: 0.30,
                    backgroundMeanLuma: 0.66,
                    subjectToBackgroundDelta: -0.36,
                    subjectClippedBrightRatio: 0.02,
                    backgroundHotspotRatio: 0.22
                )
            ),
            objects: .init(totalCount: 2, topKLabels: ["person", "window"])
        )

        await MainActor.run {
            pipeline.setCameraDemoSceneMode(.portrait)
            pipeline.testingPublishLivePresentation(
                frameId: frameId,
                snapshot: snapshot,
                critique: makeCritique(frameId: frameId, verdict: .good),
                plan: makeDemoNoChangePlan(frameId: frameId),
                semantics: makeDemoSemantics(
                    frameId: frameId,
                    primarySubject: .init(kind: .face, region: faceRegion, confidence: 0.88),
                    sceneType: .singleCharacterMedium
                ),
                legacySuggestion: nil,
                structuredAvailable: true,
                now: Date(timeIntervalSince1970: 1_768_500_380)
            )
        }

        await MainActor.run {
            XCTAssertEqual(pipeline.currentOverlayAnnotations.first?.label, "Лицо")
            XCTAssertEqual(pipeline.currentOverlayAnnotations.first?.tone, .danger)
            XCTAssertEqual(
                pipeline.currentLiveHint?.text,
                SETCameraCopy.actionKey(for: .improveFrontLight).localizedString(locale: .current)
            )
            XCTAssertNotEqual(pipeline.currentLiveHint?.actionType, .leaveFrameAsIs)
        }
    }

    func testDemoPortraitUsesSubjectLightingForOverexposedFace() async {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, demoLiveCoachEnabled: true)
        let faceRegion = NormalizedRect(x: 0.32, y: 0.18, width: 0.24, height: 0.42)
        let frameId = "demo-face-overexposed"
        let snapshot = makeDemoLiveSnapshot(
            frameId: frameId,
            subjectSignals: .init(
                faceDetected: true,
                personDetected: true,
                personCount: 1,
                primaryCandidateRegion: faceRegion,
                primaryCandidateConfidence: 0.90
            ),
            lighting: .init(
                exposureBiasHint: 0.0,
                backlightIndex: 0.0,
                keyToFillRatio: nil,
                subjectLighting: .init(
                    subjectMeanLuma: 0.84,
                    backgroundMeanLuma: 0.42,
                    subjectToBackgroundDelta: 0.42,
                    subjectClippedBrightRatio: 0.14,
                    backgroundHotspotRatio: 0.05
                )
            ),
            objects: .init(totalCount: 1, topKLabels: ["person"])
        )

        await MainActor.run {
            pipeline.setCameraDemoSceneMode(.portrait)
            pipeline.testingPublishLivePresentation(
                frameId: frameId,
                snapshot: snapshot,
                critique: makeCritique(frameId: frameId, verdict: .good),
                plan: makeDemoNoChangePlan(frameId: frameId),
                semantics: makeDemoSemantics(
                    frameId: frameId,
                    primarySubject: .init(kind: .face, region: faceRegion, confidence: 0.90),
                    sceneType: .singleCharacterMedium
                ),
                legacySuggestion: nil,
                structuredAvailable: true,
                now: Date(timeIntervalSince1970: 1_768_500_390)
            )
        }

        await MainActor.run {
            XCTAssertEqual(pipeline.currentOverlayAnnotations.first?.label, "Лицо")
            XCTAssertEqual(pipeline.currentOverlayAnnotations.first?.tone, .danger)
            XCTAssertEqual(
                pipeline.currentLiveHint?.text,
                SETCameraCopy.actionKey(for: .improveFrontLight).localizedString(locale: .current)
            )
        }
    }

    func testCinematicPortraitModeStartsWithDarkerBackgroundAdvice() async {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, demoLiveCoachEnabled: true)
        let faceRegion = NormalizedRect(x: 0.24, y: 0.18, width: 0.24, height: 0.42)
        let frameId = "demo-cinematic-flat-light"
        let snapshot = makeDemoLiveSnapshot(
            frameId: frameId,
            subjectSignals: .init(
                faceDetected: true,
                personDetected: true,
                personCount: 1,
                faceRegion: faceRegion,
                primaryCandidateRegion: faceRegion,
                primaryCandidateConfidence: 0.90
            ),
            lighting: .init(
                exposureBiasHint: 0.0,
                backlightIndex: 0.0,
                keyToFillRatio: nil,
                subjectLighting: .init(
                    subjectMeanLuma: 0.52,
                    backgroundMeanLuma: 0.51,
                    subjectToBackgroundDelta: 0.01,
                    subjectClippedBrightRatio: 0.02,
                    backgroundHotspotRatio: 0.04
                )
            ),
            objects: .init(totalCount: 1, topKLabels: ["person"])
        )

        await MainActor.run {
            pipeline.setCameraDemoSceneMode(.cinematicPortrait)
        }
        await publishDemoFrame(
            pipeline: pipeline,
            frameId: frameId,
            snapshot: snapshot,
            semantics: makeDemoSemantics(
                frameId: frameId,
                primarySubject: .init(kind: .face, region: faceRegion, confidence: 0.90),
                sceneType: .singleCharacterMedium
            ),
            now: 1_768_500_500
        )

        await MainActor.run {
            XCTAssertEqual(pipeline.currentOverlayAnnotations.first?.label, "Лицо")
            XCTAssertEqual(pipeline.currentOverlayAnnotations.first?.tone, .danger)
            XCTAssertEqual(pipeline.currentLiveHint?.actionType, .reduceBackgroundDistractions)
            XCTAssertEqual(
                pipeline.currentLiveHint?.text,
                SETCameraCopy.actionKey(for: .reduceBackgroundDistractions).localizedString(locale: .current)
            )
            XCTAssertTrue(pipeline.currentLiveHint?.expandedVerdict?.supportingText?.contains("Лицо: 0.52") == true)
        }
    }

    func testCinematicPortraitModeAdvancesThroughThreeLightingStages() async {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, demoLiveCoachEnabled: true)
        let faceRegion = NormalizedRect(x: 0.24, y: 0.18, width: 0.24, height: 0.42)
        let semantics = makeDemoSemantics(
            frameId: "demo-cinematic-sequence",
            primarySubject: .init(kind: .face, region: faceRegion, confidence: 0.90),
            sceneType: .singleCharacterMedium
        )

        await MainActor.run {
            pipeline.setCameraDemoSceneMode(.cinematicPortrait)
        }

        let flatLightSnapshot = makeDemoLiveSnapshot(
            frameId: "demo-cinematic-flat-start",
            subjectSignals: .init(
                faceDetected: true,
                personDetected: true,
                personCount: 1,
                faceRegion: faceRegion,
                primaryCandidateRegion: faceRegion,
                primaryCandidateConfidence: 0.90
            ),
            lighting: .init(
                exposureBiasHint: 0.0,
                backlightIndex: 0.0,
                keyToFillRatio: nil,
                subjectLighting: .init(
                    subjectMeanLuma: 0.52,
                    backgroundMeanLuma: 0.51,
                    subjectToBackgroundDelta: 0.01,
                    subjectClippedBrightRatio: 0.02,
                    backgroundHotspotRatio: 0.04
                )
            ),
            objects: .init(totalCount: 1, topKLabels: ["person"])
        )
        await publishDemoFrame(
            pipeline: pipeline,
            frameId: "demo-cinematic-flat-start",
            snapshot: flatLightSnapshot,
            semantics: semantics,
            now: 1_768_500_506
        )

        await MainActor.run {
            XCTAssertEqual(pipeline.currentLiveHint?.actionType, .reduceBackgroundDistractions)
            XCTAssertEqual(
                pipeline.currentLiveHint?.text,
                SETCameraCopy.actionKey(for: .reduceBackgroundDistractions).localizedString(locale: .current)
            )
        }

        let darkFaceSnapshot = makeDemoLiveSnapshot(
            frameId: "demo-cinematic-dark-face",
            subjectSignals: .init(
                faceDetected: true,
                personDetected: true,
                personCount: 1,
                faceRegion: faceRegion,
                primaryCandidateRegion: faceRegion,
                primaryCandidateConfidence: 0.90
            ),
            lighting: .init(
                exposureBiasHint: -0.2,
                backlightIndex: 0.0,
                keyToFillRatio: nil,
                subjectLighting: .init(
                    subjectMeanLuma: 0.40,
                    backgroundMeanLuma: 0.28,
                    subjectToBackgroundDelta: 0.12,
                    subjectClippedBrightRatio: 0.01,
                    backgroundHotspotRatio: 0.04
                )
            ),
            objects: .init(totalCount: 1, topKLabels: ["person"])
        )
        await publishDemoFrame(
            pipeline: pipeline,
            frameId: "demo-cinematic-dark-face",
            snapshot: darkFaceSnapshot,
            semantics: semantics,
            now: 1_768_500_510
        )

        await MainActor.run {
            XCTAssertEqual(pipeline.currentLiveHint?.actionType, .improveFrontLight)
            XCTAssertEqual(
                pipeline.currentLiveHint?.text,
                SETCameraCopy.actionKey(for: .improveFrontLight).localizedString(locale: .current)
            )
        }

        let overlitSnapshot = makeDemoLiveSnapshot(
            frameId: "demo-cinematic-overlit-face",
            subjectSignals: darkFaceSnapshot.subjectSignals,
            lighting: .init(
                exposureBiasHint: 0.2,
                backlightIndex: 0.0,
                keyToFillRatio: nil,
                subjectLighting: .init(
                    subjectMeanLuma: 0.70,
                    backgroundMeanLuma: 0.32,
                    subjectToBackgroundDelta: 0.38,
                    subjectClippedBrightRatio: 0.02,
                    backgroundHotspotRatio: 0.04
                )
            ),
            objects: .init(totalCount: 1, topKLabels: ["person"])
        )
        await publishDemoFrame(
            pipeline: pipeline,
            frameId: "demo-cinematic-overlit-face",
            snapshot: overlitSnapshot,
            semantics: semantics,
            now: 1_768_500_514
        )

        await MainActor.run {
            XCTAssertEqual(pipeline.currentLiveHint?.actionType, .improveFrontLight)
            XCTAssertEqual(
                pipeline.currentLiveHint?.text,
                SETCameraCopy.actionKey(for: .improveFrontLight).localizedString(locale: .current)
            )
        }

        let correctedLightSnapshot = makeDemoLiveSnapshot(
            frameId: "demo-cinematic-light-corrected",
            subjectSignals: darkFaceSnapshot.subjectSignals,
            lighting: .init(
                exposureBiasHint: 0.0,
                backlightIndex: 0.0,
                keyToFillRatio: nil,
                subjectLighting: .init(
                    subjectMeanLuma: 0.56,
                    backgroundMeanLuma: 0.34,
                    subjectToBackgroundDelta: 0.22,
                    subjectClippedBrightRatio: 0.02,
                    backgroundHotspotRatio: 0.04
                )
            ),
            objects: .init(totalCount: 1, topKLabels: ["person"])
        )
        await publishDemoFrame(
            pipeline: pipeline,
            frameId: "demo-cinematic-light-corrected",
            snapshot: correctedLightSnapshot,
            semantics: semantics,
            now: 1_768_500_518
        )

        await MainActor.run {
            XCTAssertEqual(pipeline.currentLiveHint?.actionType, .leaveFrameAsIs)
            XCTAssertEqual(
                pipeline.currentLiveHint?.text,
                SETCameraCopy.actionKey(for: .leaveFrameAsIs).localizedString(locale: .current)
            )
            XCTAssertNil(pipeline.currentOverlayAnnotations.first?.targetRegion)
        }
    }

    func testCinematicPortraitScreenDemoDoesNotSkipFirstAdviceWhenExposureLooksSeparated() async {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, demoLiveCoachEnabled: true)
        let faceRegion = NormalizedRect(x: 0.24, y: 0.18, width: 0.24, height: 0.42)
        let semantics = makeDemoSemantics(
            frameId: "demo-cinematic-screen-sequence",
            primarySubject: .init(kind: .face, region: faceRegion, confidence: 0.90),
            sceneType: .singleCharacterMedium
        )

        await MainActor.run {
            pipeline.setCameraDemoSceneMode(.cinematicPortrait)
        }

        let screenNormalizedSnapshot = makeDemoLiveSnapshot(
            frameId: "demo-cinematic-screen-normalized",
            subjectSignals: .init(
                faceDetected: true,
                personDetected: true,
                personCount: 1,
                faceRegion: faceRegion,
                primaryCandidateRegion: faceRegion,
                primaryCandidateConfidence: 0.90
            ),
            lighting: .init(
                exposureBiasHint: 0.0,
                backlightIndex: 0.0,
                keyToFillRatio: nil,
                subjectLighting: .init(
                    subjectMeanLuma: 0.60,
                    backgroundMeanLuma: 0.48,
                    subjectToBackgroundDelta: 0.12,
                    subjectClippedBrightRatio: 0.02,
                    backgroundHotspotRatio: 0.05
                )
            ),
            objects: .init(totalCount: 1, topKLabels: ["person"])
        )
        await publishDemoFrame(
            pipeline: pipeline,
            frameId: "demo-cinematic-screen-normalized",
            snapshot: screenNormalizedSnapshot,
            semantics: semantics,
            now: 1_768_500_540
        )

        await MainActor.run {
            XCTAssertEqual(pipeline.currentLiveHint?.actionType, .reduceBackgroundDistractions)
            XCTAssertEqual(
                pipeline.currentLiveHint?.text,
                SETCameraCopy.actionKey(for: .reduceBackgroundDistractions).localizedString(locale: .current)
            )
        }

        let darkerBackgroundSnapshot = makeDemoLiveSnapshot(
            frameId: "demo-cinematic-screen-bg-darker",
            subjectSignals: screenNormalizedSnapshot.subjectSignals,
            lighting: .init(
                exposureBiasHint: 0.0,
                backlightIndex: 0.0,
                keyToFillRatio: nil,
                subjectLighting: .init(
                    subjectMeanLuma: 0.58,
                    backgroundMeanLuma: 0.36,
                    subjectToBackgroundDelta: 0.22,
                    subjectClippedBrightRatio: 0.02,
                    backgroundHotspotRatio: 0.05
                )
            ),
            objects: .init(totalCount: 1, topKLabels: ["person"])
        )
        await publishDemoFrame(
            pipeline: pipeline,
            frameId: "demo-cinematic-screen-bg-darker",
            snapshot: darkerBackgroundSnapshot,
            semantics: semantics,
            now: 1_768_500_544
        )

        await MainActor.run {
            XCTAssertEqual(pipeline.currentLiveHint?.actionType, .improveFrontLight)
            XCTAssertEqual(
                pipeline.currentLiveHint?.text,
                SETCameraCopy.actionKey(for: .improveFrontLight).localizedString(locale: .current)
            )
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

    func testSpatialLiveHintsRequireThreeFramesForProductionAndDemo() async {
        let region = NormalizedRect(x: 0.22, y: 0.18, width: 0.30, height: 0.48)
        let base = Date(timeIntervalSince1970: 1_768_500_600)
        let pipeline = AnalysisPipeline(reasoningProvider: nil)

        for index in 0..<3 {
            let frameId = "temporal-production-\(index + 1)"
            let capturedAt = base.addingTimeInterval(Double(index) * 0.10)
            await publishTemporalFrame(
                pipeline: pipeline,
                frameId: frameId,
                capturedAt: capturedAt,
                snapshot: makeDemoLiveSnapshot(
                    frameId: frameId,
                    capturedAt: capturedAt,
                    subjectSignals: .init(
                        faceDetected: true,
                        personDetected: true,
                        personCount: 1,
                        faceRegion: region,
                        primaryCandidateRegion: region,
                        primaryCandidateConfidence: 0.90
                    ),
                    objects: .init(totalCount: 1, topKLabels: ["person"])
                ),
                semantics: makeDemoSemantics(
                    frameId: frameId,
                    primarySubject: .init(kind: .face, region: region, confidence: 0.90),
                    sceneType: .singleCharacterMedium
                ),
                actionType: .moveFrameRight
            )
            await MainActor.run {
                if index < 2 {
                    XCTAssertNil(pipeline.currentLiveHint)
                } else {
                    XCTAssertEqual(pipeline.currentLiveHint?.actionType, .moveFrameRight)
                }
            }
        }

        let demoPipeline = AnalysisPipeline(reasoningProvider: nil, demoLiveCoachEnabled: true)
        await MainActor.run { demoPipeline.setCameraDemoSceneMode(.object) }
        let objectRegion = NormalizedRect(x: 0.01, y: 0.20, width: 0.20, height: 0.40)
        for index in 0..<3 {
            let frameId = "temporal-demo-\(index + 1)"
            let capturedAt = base.addingTimeInterval(1 + Double(index) * 0.10)
            await publishTemporalFrame(
                pipeline: demoPipeline,
                frameId: frameId,
                capturedAt: capturedAt,
                snapshot: makeDemoLiveSnapshot(
                    frameId: frameId,
                    capturedAt: capturedAt,
                    subjectSignals: .init(
                        faceDetected: false,
                        personDetected: false,
                        personCount: 0,
                        topObjectLabel: "cup",
                        topObjectConfidence: 0.90,
                        topObjectRegion: objectRegion,
                        primaryCandidateRegion: objectRegion,
                        primaryCandidateConfidence: 0.90
                    ),
                    objects: .init(totalCount: 1, topKLabels: ["cup"])
                ),
                semantics: makeDemoSemantics(
                    frameId: frameId,
                    primarySubject: .init(kind: .object, label: "cup", region: objectRegion, confidence: 0.90),
                    sceneType: .objectInsert
                ),
                actionType: .moveFrameRight
            )
            await MainActor.run {
                if index < 2 {
                    XCTAssertNil(demoPipeline.currentLiveHint)
                } else {
                    XCTAssertEqual(demoPipeline.currentLiveHint?.actionType, .moveFrameRight)
                }
            }
        }
    }

    func testSpatialConfirmationResetsOnDuplicateDecreasingTimestampAndLargeGap() async {
        let region = NormalizedRect(x: 0.22, y: 0.18, width: 0.30, height: 0.48)
        let base = Date(timeIntervalSince1970: 1_768_500_610)

        let duplicatePipeline = AnalysisPipeline(reasoningProvider: nil)
        await publishTemporalSpatialFrame(pipeline: duplicatePipeline, frameId: "duplicate-1", capturedAt: base, region: region)
        await publishTemporalSpatialFrame(pipeline: duplicatePipeline, frameId: "duplicate-2", capturedAt: base, region: region)
        await publishTemporalSpatialFrame(pipeline: duplicatePipeline, frameId: "duplicate-3", capturedAt: base.addingTimeInterval(0.10), region: region)
        await MainActor.run { XCTAssertNil(duplicatePipeline.currentLiveHint) }
        await publishTemporalSpatialFrame(pipeline: duplicatePipeline, frameId: "duplicate-4", capturedAt: base.addingTimeInterval(0.20), region: region)
        await MainActor.run { XCTAssertEqual(duplicatePipeline.currentLiveHint?.actionType, .moveFrameRight) }

        let decreasingPipeline = AnalysisPipeline(reasoningProvider: nil)
        await publishTemporalSpatialFrame(pipeline: decreasingPipeline, frameId: "decreasing-1", capturedAt: base, region: region)
        await publishTemporalSpatialFrame(pipeline: decreasingPipeline, frameId: "decreasing-2", capturedAt: base.addingTimeInterval(0.10), region: region)
        await publishTemporalSpatialFrame(pipeline: decreasingPipeline, frameId: "decreasing-3", capturedAt: base.addingTimeInterval(0.05), region: region)
        await publishTemporalSpatialFrame(pipeline: decreasingPipeline, frameId: "decreasing-4", capturedAt: base.addingTimeInterval(0.15), region: region)
        await MainActor.run { XCTAssertNil(decreasingPipeline.currentLiveHint) }
        await publishTemporalSpatialFrame(pipeline: decreasingPipeline, frameId: "decreasing-5", capturedAt: base.addingTimeInterval(0.25), region: region)
        await MainActor.run { XCTAssertEqual(decreasingPipeline.currentLiveHint?.actionType, .moveFrameRight) }

        let gapPipeline = AnalysisPipeline(reasoningProvider: nil)
        await publishTemporalSpatialFrame(pipeline: gapPipeline, frameId: "gap-1", capturedAt: base, region: region)
        await publishTemporalSpatialFrame(pipeline: gapPipeline, frameId: "gap-2", capturedAt: base.addingTimeInterval(0.30), region: region)
        await publishTemporalSpatialFrame(pipeline: gapPipeline, frameId: "gap-3", capturedAt: base.addingTimeInterval(0.40), region: region)
        await MainActor.run { XCTAssertNil(gapPipeline.currentLiveHint) }
        await publishTemporalSpatialFrame(pipeline: gapPipeline, frameId: "gap-4", capturedAt: base.addingTimeInterval(0.50), region: region)
        await MainActor.run { XCTAssertEqual(gapPipeline.currentLiveHint?.actionType, .moveFrameRight) }
    }

    func testSpatialConfirmationResetsAcrossLifecycleGeneration() async {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let region = NormalizedRect(x: 0.22, y: 0.18, width: 0.30, height: 0.48)
        let base = Date(timeIntervalSince1970: 1_768_500_620)
        await publishTemporalSpatialFrame(pipeline: pipeline, frameId: "lifecycle-1", capturedAt: base, region: region)
        await publishTemporalSpatialFrame(pipeline: pipeline, frameId: "lifecycle-2", capturedAt: base.addingTimeInterval(0.10), region: region)

        await pipeline.releaseAndWait()

        await publishTemporalSpatialFrame(pipeline: pipeline, frameId: "lifecycle-3", capturedAt: base.addingTimeInterval(0.20), region: region)
        await publishTemporalSpatialFrame(pipeline: pipeline, frameId: "lifecycle-4", capturedAt: base.addingTimeInterval(0.30), region: region)
        await MainActor.run { XCTAssertNil(pipeline.currentLiveHint) }
        await publishTemporalSpatialFrame(pipeline: pipeline, frameId: "lifecycle-5", capturedAt: base.addingTimeInterval(0.40), region: region)
        await MainActor.run { XCTAssertEqual(pipeline.currentLiveHint?.actionType, .moveFrameRight) }
    }

    func testTwoUnconfirmedSpatialEvaluationsPreserveExistingNonspatialHint() async {
        let region = NormalizedRect(x: 0.22, y: 0.18, width: 0.30, height: 0.48)
        let base = Date(timeIntervalSince1970: 1_768_500_630)
        let frameId = "temporal-nonspatial"
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let snapshot = makeDemoLiveSnapshot(
            frameId: frameId,
            capturedAt: base,
            subjectSignals: .init(
                faceDetected: true,
                personDetected: true,
                personCount: 1,
                faceRegion: region,
                primaryCandidateRegion: region,
                primaryCandidateConfidence: 0.90
            ),
            objects: .init(totalCount: 1, topKLabels: ["person"])
        )
        let semantics = makeDemoSemantics(
            frameId: frameId,
            primarySubject: .init(kind: .face, region: region, confidence: 0.90),
            sceneType: .singleCharacterMedium
        )
        await MainActor.run {
            pipeline.testingPublishLivePresentation(
                frameId: frameId,
                snapshot: snapshot,
                critique: makeCritique(frameId: frameId, verdict: .mixed),
                plan: makeDemoNoChangePlan(frameId: frameId),
                semantics: semantics,
                legacySuggestion: Suggestion(
                    text: "Добавь мягкий свет спереди.",
                    priority: .important,
                    type: .lighting,
                    ttl: 4,
                    createdAt: base
                ),
                structuredAvailable: false,
                now: base
            )
            XCTAssertEqual(pipeline.currentLiveHint?.actionType, .improveFrontLight)
        }

        await publishTemporalSpatialFrame(pipeline: pipeline, frameId: "temporal-spatial-1", capturedAt: base.addingTimeInterval(0.10), region: region)
        await publishTemporalSpatialFrame(pipeline: pipeline, frameId: "temporal-spatial-2", capturedAt: base.addingTimeInterval(0.20), region: region)
        await MainActor.run { XCTAssertEqual(pipeline.currentLiveHint?.actionType, .improveFrontLight) }
    }

    func testTechnicalLiveHintsRequireThreeQualifiedStillFramesAndResetOnIssueOrActionChange() async {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let base = Date(timeIntervalSince1970: 1_768_500_640)

        for index in 0..<2 {
            let frameId = "technical-confirmation-\(index + 1)"
            let capturedAt = base.addingTimeInterval(Double(index) * 0.10)
            await applyTechnicalHint(
                pipeline: pipeline,
                frameId: frameId,
                capturedAt: capturedAt,
                issue: "overexposure",
                actionId: "reduce_exposure"
            )
            await MainActor.run { XCTAssertNil(pipeline.currentLiveHint) }
        }

        await applyTechnicalHint(
            pipeline: pipeline,
            frameId: "technical-action-change",
            capturedAt: base.addingTimeInterval(0.20),
            issue: "overexposure",
            actionId: "increase_exposure"
        )
        await MainActor.run { XCTAssertNil(pipeline.currentLiveHint) }

        await applyTechnicalHint(
            pipeline: pipeline,
            frameId: "technical-action-2",
            capturedAt: base.addingTimeInterval(0.30),
            issue: "overexposure",
            actionId: "increase_exposure"
        )
        await MainActor.run { XCTAssertNil(pipeline.currentLiveHint) }

        await applyTechnicalHint(
            pipeline: pipeline,
            frameId: "technical-action-3",
            capturedAt: base.addingTimeInterval(0.40),
            issue: "overexposure",
            actionId: "increase_exposure"
        )
        await MainActor.run {
            XCTAssertEqual(pipeline.currentLiveHint?.id, "lh_live_technical_overexposure")
        }

        let issuePipeline = AnalysisPipeline(reasoningProvider: nil)
        for index in 0..<2 {
            await applyTechnicalHint(
                pipeline: issuePipeline,
                frameId: "technical-issue-seed-\(index + 1)",
                capturedAt: base.addingTimeInterval(Double(index) * 0.10),
                issue: "overexposure"
            )
        }
        for index in 0..<3 {
            await applyTechnicalHint(
                pipeline: issuePipeline,
                frameId: "technical-issue-change-\(index + 1)",
                capturedAt: base.addingTimeInterval(0.20 + Double(index) * 0.10),
                issue: "underexposure"
            )
            await MainActor.run {
                if index < 2 {
                    XCTAssertNil(issuePipeline.currentLiveHint)
                } else {
                    XCTAssertEqual(issuePipeline.currentLiveHint?.id, "lh_live_technical_underexposure")
                }
            }
        }
    }

    func testTechnicalLiveHintsSuppressMovingStaleAndUnqualifiedFrames() async {
        let base = Date(timeIntervalSince1970: 1_768_500_650)
        let movingPipeline = AnalysisPipeline(reasoningProvider: nil)

        await applyTechnicalHint(
            pipeline: movingPipeline,
            frameId: "technical-moving-seed",
            capturedAt: base,
            issue: "lens_smudge"
        )
        await applyTechnicalHint(
            pipeline: movingPipeline,
            frameId: "technical-moving",
            capturedAt: base.addingTimeInterval(0.10),
            issue: "lens_smudge",
            motionState: .moving
        )
        for index in 2...3 {
            await applyTechnicalHint(
                pipeline: movingPipeline,
                frameId: "technical-after-moving-\(index)",
                capturedAt: base.addingTimeInterval(Double(index) * 0.10),
                issue: "lens_smudge"
            )
            await MainActor.run { XCTAssertNil(movingPipeline.currentLiveHint) }
        }
        await applyTechnicalHint(
            pipeline: movingPipeline,
            frameId: "technical-after-moving-4",
            capturedAt: base.addingTimeInterval(0.40),
            issue: "lens_smudge"
        )
        await MainActor.run { XCTAssertNotNil(movingPipeline.currentLiveHint) }

        let stalePipeline = AnalysisPipeline(reasoningProvider: nil)
        await applyTechnicalHint(
            pipeline: stalePipeline,
            frameId: "technical-stale",
            capturedAt: base,
            issue: "defocus",
            visionAvailable: false
        )
        await MainActor.run { XCTAssertNil(stalePipeline.currentLiveHint) }
        for index in 1...3 {
            await applyTechnicalHint(
                pipeline: stalePipeline,
                frameId: "technical-fresh-\(index)",
                capturedAt: base.addingTimeInterval(0.30 + Double(index) * 0.10),
                issue: "defocus",
                visionAvailable: false
            )
            await MainActor.run {
                if index < 3 {
                    XCTAssertNil(stalePipeline.currentLiveHint)
                } else {
                    XCTAssertNotNil(stalePipeline.currentLiveHint)
                }
            }
        }
    }

    func testTechnicalLiveHintsResetWhenProductionMotionStarts() async {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil,
            liveHybridFusionEnabled: false
        )
        let base = Date(timeIntervalSince1970: 1_768_500_660)

        // Warm the real high-frame path before sending the moving frame so the
        // evidence freshness guard does not include first-use model startup.
        pipeline.ingestHigh(
            context: makeProductionFrameContext(
                timestamp: 1,
                motionState: .still,
                capturedAt: Date()
            )
        )
        await pipeline.testingDrainHighQueue()
        await MainActor.run { }

        for index in 0..<2 {
            await applyTechnicalHint(
                pipeline: pipeline,
                frameId: "production-motion-seed-\(index + 1)",
                capturedAt: base.addingTimeInterval(Double(index) * 0.10),
                issue: "defocus"
            )
        }

        pipeline.ingestHigh(
            context: makeProductionFrameContext(
                timestamp: 2,
                motionState: .moving,
                isStable: false,
                shakeLevel: 0.90,
                capturedAt: Date()
            )
        )
        await pipeline.testingDrainHighQueue()
        await MainActor.run { }

        await applyTechnicalHint(
            pipeline: pipeline,
            frameId: "production-motion-after-1",
            capturedAt: base.addingTimeInterval(0.20),
            issue: "defocus"
        )
        await MainActor.run { XCTAssertNil(pipeline.currentLiveHint) }
        await applyTechnicalHint(
            pipeline: pipeline,
            frameId: "production-motion-after-2",
            capturedAt: base.addingTimeInterval(0.30),
            issue: "defocus"
        )
        await MainActor.run { XCTAssertNil(pipeline.currentLiveHint) }
        await applyTechnicalHint(
            pipeline: pipeline,
            frameId: "production-motion-after-3",
            capturedAt: base.addingTimeInterval(0.40),
            issue: "defocus"
        )
        await MainActor.run {
            XCTAssertEqual(pipeline.currentLiveHint?.id, "lh_live_technical_defocus")
        }
    }

    func testTechnicalLiveHintsResetWhenLivePresentationClears() async {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let base = Date(timeIntervalSince1970: 1_768_500_670)

        for index in 0..<2 {
            await applyTechnicalHint(
                pipeline: pipeline,
                frameId: "clear-seed-\(index + 1)",
                capturedAt: base.addingTimeInterval(Double(index) * 0.10),
                issue: "lens_smudge"
            )
        }

        await MainActor.run {
            pipeline.clearLivePresentationState()
        }

        for index in 0..<3 {
            await applyTechnicalHint(
                pipeline: pipeline,
                frameId: "clear-after-\(index + 1)",
                capturedAt: base.addingTimeInterval(0.20 + Double(index) * 0.10),
                issue: "lens_smudge"
            )
            await MainActor.run {
                if index < 2 {
                    XCTAssertNil(pipeline.currentLiveHint)
                } else {
                    XCTAssertEqual(pipeline.currentLiveHint?.id, "lh_live_technical_lens_smudge")
                }
            }
        }
    }

    private func publishTemporalSpatialFrame(pipeline: AnalysisPipeline,
                                             frameId: String,
                                             capturedAt: Date,
                                             region: NormalizedRect) async {
        await publishTemporalFrame(
            pipeline: pipeline,
            frameId: frameId,
            capturedAt: capturedAt,
            snapshot: makeDemoLiveSnapshot(
                frameId: frameId,
                capturedAt: capturedAt,
                subjectSignals: .init(
                    faceDetected: true,
                    personDetected: true,
                    personCount: 1,
                    faceRegion: region,
                    primaryCandidateRegion: region,
                    primaryCandidateConfidence: 0.90
                ),
                objects: .init(totalCount: 1, topKLabels: ["person"])
            ),
            semantics: makeDemoSemantics(
                frameId: frameId,
                primarySubject: .init(kind: .face, region: region, confidence: 0.90),
                sceneType: .singleCharacterMedium
            ),
            actionType: .moveFrameRight
        )
    }

    private func publishTemporalFrame(pipeline: AnalysisPipeline,
                                      frameId: String,
                                      capturedAt: Date,
                                      snapshot: FrameFeatureSnapshot,
                                      semantics: SceneSemanticsReport,
                                      actionType: ActionTypeV1) async {
        let (critique, plan) = makeTemporalCritiqueAndPlan(frameId: frameId, actionType: actionType, region: semantics.primarySubject.region)
        await MainActor.run {
            pipeline.testingPublishLivePresentation(
                frameId: frameId,
                snapshot: snapshot,
                critique: critique,
                plan: plan,
                semantics: semantics,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: capturedAt
            )
        }
    }

    private func applyTechnicalHint(pipeline: AnalysisPipeline,
                                    frameId: String,
                                    capturedAt: Date,
                                    issue: String,
                                    actionId: String? = nil,
                                    motionState: CameraAnalysisMotionState = .still,
                                    visionAvailable: Bool = true) async {
        let region = NormalizedRect(x: 0.24, y: 0.18, width: 0.28, height: 0.46)
        let snapshot = makeDemoLiveSnapshot(
            frameId: frameId,
            capturedAt: capturedAt,
            subjectSignals: .init(
                faceDetected: true,
                personDetected: true,
                personCount: 1,
                faceRegion: region,
                primaryCandidateRegion: region,
                primaryCandidateConfidence: 0.90
            ),
            objects: .init(totalCount: 1, topKLabels: ["person"]),
            motionState: motionState,
            visionAvailable: visionAvailable
        )
        let semantics = makeDemoSemantics(
            frameId: frameId,
            primarySubject: .init(kind: .face, region: region, confidence: 0.90),
            sceneType: .singleCharacterMedium
        )
        let candidate = LiveHintPresentation(
            id: "lh_live_technical_\(issue)",
            frameId: frameId,
            text: "Техническая подсказка.",
            confidence: 0.90,
            actionType: nil,
            actionId: actionId,
            linkedIssueIds: [],
            summaryId: "technical_quality_\(issue)",
            traceRootIds: ["technical_quality_\(issue)"],
            targetRegion: nil,
            overlayHint: nil,
            isFallback: false,
            expandedVerdict: nil
        )
        await MainActor.run {
            pipeline.testingApplyLiveHintCandidate(
                candidate,
                snapshot: snapshot,
                semantics: semantics,
                now: capturedAt
            )
        }
    }

    private func makeProductionFrameContext(timestamp: Double,
                                            motionState: MotionState,
                                            isStable: Bool = true,
                                            shakeLevel: Double = 0.05,
                                            capturedAt: Date) -> FrameContext {
        let pixelBuffer = makeFilledPixelBuffer(width: 96, height: 96) { x, y in
            let value = UInt8((x * 31 + y * 17) % 251)
            return (value, value, value)
        }
        return FrameContext(
            pixelBuffer: pixelBuffer,
            timestamp: CMTimeMakeWithSeconds(timestamp, preferredTimescale: 600),
            orientation: .up,
            isStable: isStable,
            shakeLevel: shakeLevel,
            motionState: motionState,
            capturedAt: capturedAt
        )
    }

    private func makeTemporalCritiqueAndPlan(frameId: String,
                                             actionType: ActionTypeV1,
                                             region: NormalizedRect?) -> (CritiqueReport, RecommendationPlan) {
        let issueId = "temporal_issue_\(frameId)"
        let issue = FrameIssue(
            id: issueId,
            type: .insufficientLookSpace,
            severity: 0.96,
            confidence: 0.96,
            rationale: "Временная проверка композиционной рекомендации.",
            evidence: [EvidenceRef(source: .semantics, key: "temporal", value: "eligible", confidence: 0.96)],
            affectedRegion: region,
            suggestedFixTypes: [.reframing]
        )
        let critique = CritiqueReport(
            frameId: frameId,
            mode: .live,
            verdict: .needsFix,
            verdictConfidence: 0.96,
            strengths: [],
            issues: [issue],
            summary: .init(
                id: "temporal_summary_\(frameId)",
                shortVerdict: "Кадр требует проверки.",
                whyGood: nil,
                whyProblematic: issue.rationale
            ),
            traceRefs: ["temporal_trace_\(frameId)"],
            fallbackUsed: false
        )
        let action = RecommendationAction(
            id: "temporal_action_\(frameId)",
            actionType: actionType,
            priority: 1,
            targetRegion: region,
            linkedIssueIds: [issueId],
            expectedOutcome: "Временная проверка.",
            guardrail: .init(requiresStillCamera: true, minConfidence: 0.90, suppressWhenMoving: true),
            overlayHint: nil
        )
        let plan = RecommendationPlan(
            frameId: frameId,
            mode: .live,
            inputVerdict: .needsFix,
            primaryAction: action,
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.96
        )
        return (critique, plan)
    }

    private func publishDemoFrame(pipeline: AnalysisPipeline,
                                  frameId: String,
                                  snapshot: FrameFeatureSnapshot,
                                  semantics: SceneSemanticsReport,
                                  now: TimeInterval) async {
        await MainActor.run {
            pipeline.testingPublishLivePresentation(
                frameId: frameId,
                snapshot: snapshot,
                critique: makeCritique(frameId: frameId, verdict: .good),
                plan: makeDemoNoChangePlan(frameId: frameId),
                semantics: semantics,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: Date(timeIntervalSince1970: now)
            )
        }
    }

    /// C07: the simulated coaching path publishes the catalog instruction of
    /// the accepted action, exactly like the overlay. Demo recipes therefore
    /// resolve to one of the catalog entries below, never to an authored line.
    private var portraitDemoCatalogInstructions: Set<String> {
        Set([
            ActionTypeV1.improveFrontLight,
            .reduceBackgroundDistractions,
            .moveFrameLeft,
            .moveFrameRight,
        ].map { SETCameraCopy.actionKey(for: $0).localizedString(locale: .current) })
    }

    private var objectDemoCatalogInstructions: Set<String> {
        Set([
            ActionTypeV1.improveFrontLight,
            .reduceBackgroundDistractions,
            .moveFrameLeft,
            .moveFrameRight,
            .increaseSubjectSize,
        ].map { SETCameraCopy.actionKey(for: $0).localizedString(locale: .current) })
    }

    private func makeDemoLiveSnapshot(frameId: String,
                                      capturedAt: Date = Date(timeIntervalSince1970: 1_768_500_000),
                                      subjectSignals: FrameFeatureSnapshot.SubjectSignals,
                                      lighting: FrameFeatureSnapshot.LightingFeatures = .init(
                                          exposureBiasHint: -0.05,
                                          backlightIndex: 0.05,
                                          keyToFillRatio: nil
                                      ),
                                      objects: FrameFeatureSnapshot.ObjectDetectionsSummary,
                                      motionState: CameraAnalysisMotionState = .still,
                                      visionAvailable: Bool = true) -> FrameFeatureSnapshot {
        FrameFeatureSnapshot(
            frameId: frameId,
            mode: .live,
            capturedAt: capturedAt,
            sources: .init(
                vision: .init(available: visionAvailable, freshnessMs: visionAvailable ? 40 : nil, confidence: visionAvailable ? 0.86 : nil),
                horizon: .init(available: true, freshnessMs: 45, confidence: 0.76),
                lighting: .init(available: true, freshnessMs: 48, confidence: 0.78),
                detr: .init(available: true, freshnessMs: 280, confidence: 0.80),
                aesthetic: .init(available: false)
            ),
            composition: .init(
                horizontalOffset: 0,
                verticalOffset: 0,
                subjectAreaRatio: subjectSignals.primaryCandidateRegion.map { $0.width * $0.height } ?? 0,
                saliencyLeftRightBalance: 0,
                saliencyTopBottomBalance: 0
            ),
            subjectSignals: subjectSignals,
            horizon: .init(angleDegrees: 0.4, confidence: 0.74),
            lighting: lighting,
            motion: .init(state: motionState, shakeLevel: motionState == .still ? 0.03 : 0.90),
            aesthetics: .init(score: 0.78, scoreConfidence: 0.70),
            objects: objects,
            technicalFlags: []
        )
    }

    private func makeDemoSemantics(frameId: String,
                                   primarySubject: SceneSemanticsReport.PrimarySubject,
                                   sceneType: SceneTypeV1,
                                   hasClearFocus: Bool = true) -> SceneSemanticsReport {
        SceneSemanticsReport(
            frameId: frameId,
            mode: .live,
            sceneType: sceneType,
            sceneTypeConfidence: 0.82,
            primarySubject: primarySubject,
            dominance: .init(
                hasClearFocus: hasClearFocus,
                focusCompetitionScore: hasClearFocus ? 0.18 : 0.62,
                backgroundClutterScore: hasClearFocus ? 0.22 : 0.70
            ),
            readability: .init(
                subjectReadable: true,
                lookSpaceAdequate: true,
                edgePressureScore: 0.12,
                separationScore: 0.72
            ),
            ambiguities: [],
            assumptions: []
        )
    }

    private func makeDemoNoChangePlan(frameId: String) -> RecommendationPlan {
        RecommendationPlan(
            frameId: frameId,
            mode: .live,
            inputVerdict: .good,
            primaryAction: nil,
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: "Кадр читается стабильно, критичных проблем не выявлено.",
            planConfidence: 0.88
        )
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

    private func makeHorizonCritique(frameId: String) -> CritiqueReport {
        CritiqueReport(
            frameId: frameId,
            mode: .live,
            verdict: .needsFix,
            verdictConfidence: 0.84,
            strengths: [],
            issues: [
                FrameIssue(
                    id: "iss_horizon",
                    type: .horizonDistracts,
                    severity: 0.72,
                    confidence: 0.70,
                    rationale: "Горизонт заметно завален и тянет внимание.",
                    evidence: [EvidenceRef(source: .snapshot, key: "composition.horizonTiltDegrees", value: "8.2")],
                    affectedRegion: nil,
                    suggestedFixTypes: [.horizonCorrection]
                )
            ],
            summary: CritiqueSummary(
                id: "summary_\(frameId)",
                shortVerdict: "Горизонт мешает кадру.",
                whyGood: nil,
                whyProblematic: "Заваленная линия горизонта делает сцену менее устойчивой."
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
                    suggestedFixTypes: [.angleAdjustment]
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

    private func makeGoodPauseCritique(frameId: String,
                                       verdictConfidence: Double,
                                       strengths: [FrameStrength]) -> CritiqueReport {
        CritiqueReport(
            frameId: frameId,
            mode: .pause,
            verdict: .good,
            verdictConfidence: verdictConfidence,
            strengths: strengths,
            issues: [],
            summary: CritiqueSummary(
                id: "summary_\(frameId)",
                shortVerdict: "Кадр работает.",
                whyGood: "Сцена читается без обязательной правки.",
                whyProblematic: nil
            ),
            traceRefs: ["trace_\(frameId)"],
            fallbackUsed: false
        )
    }

    private func makeMixedPauseCritique(frameId: String,
                                        verdictConfidence: Double) -> CritiqueReport {
        CritiqueReport(
            frameId: frameId,
            mode: .pause,
            verdict: .mixed,
            verdictConfidence: verdictConfidence,
            strengths: [],
            issues: [
                FrameIssue(
                    id: "iss_background",
                    type: .frameVisuallyOverloaded,
                    severity: 0.61,
                    confidence: 0.72,
                    rationale: "Фон спорит с главным объектом.",
                    evidence: [EvidenceRef(source: .snapshot, key: "background.clutter", value: "medium")],
                    affectedRegion: nil,
                    suggestedFixTypes: [.reframing]
                )
            ],
            summary: CritiqueSummary(
                id: "summary_\(frameId)",
                shortVerdict: "Кадр можно улучшить.",
                whyGood: nil,
                whyProblematic: "Есть заметное, но не критическое отвлечение в фоне."
            ),
            traceRefs: ["trace_\(frameId)"],
            fallbackUsed: false
        )
    }

    private func makeNoChangePlan(for critique: CritiqueReport) -> RecommendationPlan {
        RecommendationPlan(
            frameId: critique.frameId,
            mode: .pause,
            inputVerdict: critique.verdict,
            primaryAction: nil,
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: "Сохраните текущую композицию.",
            planConfidence: critique.verdictConfidence
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

    private func makeHotspotPixelBuffer(width: Int, height: Int) -> CVPixelBuffer {
        makeFilledPixelBuffer(width: width, height: height) { x, y in
            let inHotspot = x > (width * 2 / 3) && y < (height / 3)
            return inHotspot ? (255, 255, 255) : (120, 120, 120)
        }
    }

    private func makeModerateHotspotPixelBuffer(width: Int, height: Int) -> CVPixelBuffer {
        makeFilledPixelBuffer(width: width, height: height) { x, y in
            let inHotspot = x > (width * 7 / 10) && y < (height * 4 / 10)
            return inHotspot ? (230, 230, 230) : (115, 115, 115)
        }
    }

    private func makeSoftFocusPixelBuffer(width: Int, height: Int) -> CVPixelBuffer {
        makeFilledPixelBuffer(width: width, height: height) { x, _ in
            let value: UInt8 = x < (width / 2) ? 118 : 124
            return (value, value, value)
        }
    }

    private func makeLowLightPixelBuffer(width: Int, height: Int) -> CVPixelBuffer {
        makeFilledPixelBuffer(width: width, height: height) { x, y in
            let stripe = (x + y) % 5 == 0
            let value: UInt8 = stripe ? 42 : 14
            return (value, value, value)
        }
    }

    private func makeLowKeyCinematicPixelBuffer(width: Int, height: Int) -> CVPixelBuffer {
        makeFilledPixelBuffer(width: width, height: height) { x, y in
            let softRim = x > (width * 3 / 5) && y < (height / 2)
            let value: UInt8 = softRim ? 32 : 18
            return (value, value, value)
        }
    }

    private func makeModerateLowLightSoftPixelBuffer(width: Int, height: Int) -> CVPixelBuffer {
        makeFilledPixelBuffer(width: width, height: height) { x, _ in
            let value: UInt8 = x < (width / 2) ? 34 : 42
            return (value, value, value)
        }
    }

    private func makeDatasetPixelBuffer(named filename: String) throws -> CVPixelBuffer {
        let imageURL = bundledCameraBenchmarkPackURL()
            .appendingPathComponent("images")
            .appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            // CC-002 excluded some benchmark images from the checkout. Tests
            // referencing missing images are skipped rather than failed —
            // the failure would be a file-not-found, not a behavior bug.
            throw XCTSkip("benchmark image not in checkout: \(filename)")
        }
        return try makePixelBuffer(from: imageURL)
    }

    private func bundledCameraBenchmarkPackURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1")
    }

    private func loadSemanticDemoScenarios() throws -> [SemanticDemoScenario] {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scenarioURL = repoRoot
            .appendingPathComponent("docs/cameraanalysis/demo/semantic_demo_scenarios.json")
        let data = try Data(contentsOf: scenarioURL)
        return try JSONDecoder().decode([SemanticDemoScenario].self, from: data)
    }

    private func makePixelBuffer(from imageURL: URL) throws -> CVPixelBuffer {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(
                domain: "AnalysisPipelinePresentationTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not load image at \(imageURL.path)"]
            )
        }

        let width = image.width
        let height = image.height
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
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
            throw NSError(
                domain: "AnalysisPipelinePresentationTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not allocate pixel buffer for \(imageURL.path)"]
            )
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw NSError(
                domain: "AnalysisPipelinePresentationTests",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Could not create CGContext for \(imageURL.path)"]
            )
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }

    private func makeFilledPixelBuffer(width: Int,
                                       height: Int,
                                       pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CVPixelBuffer {
        let pixelBuffer = makePixelBuffer(width: width, height: height)
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            fatalError("Missing pixel buffer base address")
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        for y in 0..<height {
            let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let offset = x * 4
                let (red, green, blue) = pixel(x, y)
                row[offset] = blue
                row[offset + 1] = green
                row[offset + 2] = red
                row[offset + 3] = 255
            }
        }
        return pixelBuffer
    }

    private struct SemanticDemoScenario: Decodable {
        let id: String
        let recordId: String
        let filename: String
        let expectedPauseSemanticActions: [String]
        let forbiddenPauseSemanticActions: [String]
        let expectedFutureActions: [String]
        let expectedLiveShown: Bool?
        let expectedLiveTextFragments: [String]
        let expectedPauseSummaryFragments: [String]
        let minimumPauseConfidence: Double?
        let maximumPauseConfidence: Double?

        private enum CodingKeys: String, CodingKey {
            case id
            case recordId = "record_id"
            case filename
            case expectedPauseSemanticActions = "expected_pause_semantic_actions"
            case forbiddenPauseSemanticActions = "forbidden_pause_semantic_actions"
            case expectedFutureActions = "expected_future_actions"
            case expectedLiveShown = "expected_live_shown"
            case expectedLiveTextFragments = "expected_live_text_fragments"
            case expectedPauseSummaryFragments = "expected_pause_summary_fragments"
            case minimumPauseConfidence = "minimum_pause_confidence"
            case maximumPauseConfidence = "maximum_pause_confidence"
        }
    }
}

final class SemanticEvalStillImageBatchReplayTests: XCTestCase {
    private struct SemanticEvalReplayConfig: Decodable {
        let labelsPath: String
        let imagesRootPath: String
        let outputPath: String
        let runtime: String?
        let limit: Int?
        let deleteAfterRead: Bool

        private enum CodingKeys: String, CodingKey {
            case labelsPath = "labels_path"
            case imagesRootPath = "images_root_path"
            case outputPath = "output_path"
            case runtime
            case limit
            case deleteAfterRead = "delete_after_read"
        }

        private enum LegacyCodingKeys: String, CodingKey {
            case labelsPath
            case imagesRootPath
            case outputPath
            case runtime
            case limit
            case deleteAfterRead
        }

        init(labelsPath: String,
             imagesRootPath: String,
             outputPath: String,
             runtime: String?,
             limit: Int?,
             deleteAfterRead: Bool = true) {
            self.labelsPath = labelsPath
            self.imagesRootPath = imagesRootPath
            self.outputPath = outputPath
            self.runtime = runtime
            self.limit = limit
            self.deleteAfterRead = deleteAfterRead
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
            labelsPath = try container.decodeIfPresent(String.self, forKey: .labelsPath)
                ?? legacyContainer.decode(String.self, forKey: .labelsPath)
            imagesRootPath = try container.decodeIfPresent(String.self, forKey: .imagesRootPath)
                ?? legacyContainer.decode(String.self, forKey: .imagesRootPath)
            outputPath = try container.decodeIfPresent(String.self, forKey: .outputPath)
                ?? legacyContainer.decode(String.self, forKey: .outputPath)
            runtime = try container.decodeIfPresent(String.self, forKey: .runtime)
                ?? legacyContainer.decodeIfPresent(String.self, forKey: .runtime)
            limit = try container.decodeIfPresent(Int.self, forKey: .limit)
                ?? legacyContainer.decodeIfPresent(Int.self, forKey: .limit)
            deleteAfterRead = try container.decodeIfPresent(Bool.self, forKey: .deleteAfterRead)
                ?? legacyContainer.decodeIfPresent(Bool.self, forKey: .deleteAfterRead)
                ?? true
        }
    }

    private struct SemanticEvalLabelRecord: Decodable {
        let recordId: String
        let filename: String

        private enum CodingKeys: String, CodingKey {
            case recordId = "record_id"
            case filename
        }
    }

    @MainActor
    func testExportSemanticEvalCandidateOutputsFromStillImages() async throws {
        guard let config = try loadReplayConfig() else {
            throw XCTSkip("Set env config or write /private/tmp/semantic_eval_replay_config.json to export semantic still-image replay rows.")
        }
        print("Semantic eval replay config output path: \(config.outputPath)")

        let labels = try loadLabels(path: config.labelsPath)
        let limit = config.limit
        let selectedLabels = limit.map { Array(labels.prefix($0)) } ?? labels
        let options: SemanticEvalStillImageReplayOptions = config.runtime == "lightweight"
            ? .lightweightTest
            : .fullRuntime
        let imagesRoot = URL(fileURLWithPath: config.imagesRootPath, isDirectory: true)
        let outputURL = URL(fileURLWithPath: config.outputPath)

        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        var rows: [SemanticEvalCandidateOutput] = []
        rows.reserveCapacity(selectedLabels.count * 2)

        for label in selectedLabels {
            let imageURL = imagesRoot.appendingPathComponent(label.filename)
            let pixelBuffer = try makePixelBuffer(from: imageURL)
            let replay = await pipeline.testingReplayStillImageForSemanticEval(
                recordId: label.recordId,
                filename: label.filename,
                pixelBuffer: pixelBuffer,
                orientation: .up,
                capturedAt: Date(timeIntervalSince1970: 1_768_500_000),
                options: options
            )
            rows.append(contentsOf: replay.rows)
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writeRows(rows, to: outputURL)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outputURL.path),
            "Expected semantic eval export at \(outputURL.path)"
        )
        print("Semantic eval replay exported \(rows.count) rows to \(outputURL.path)")

        XCTAssertEqual(rows.count, selectedLabels.count * 2)
        if options.runtimeClaim == .realRuntimeStillReplay {
            XCTAssertTrue(rows.allSatisfy { $0.runtimeClaim == .realRuntimeStillReplay })
        } else {
            XCTAssertTrue(rows.allSatisfy { $0.runtimeClaim == .testFixture })
        }
    }

    private func loadReplayConfig() throws -> SemanticEvalReplayConfig? {
        let env = ProcessInfo.processInfo.environment
        if let labelsPath = env["SEMANTIC_EVAL_LABELS"],
           let imagesRootPath = env["SEMANTIC_EVAL_IMAGES_ROOT"],
           let outputPath = env["SEMANTIC_EVAL_OUTPUT"] {
            return SemanticEvalReplayConfig(
                labelsPath: labelsPath,
                imagesRootPath: imagesRootPath,
                outputPath: outputPath,
                runtime: env["SEMANTIC_EVAL_RUNTIME"],
                limit: env["SEMANTIC_EVAL_LIMIT"].flatMap(Int.init),
                deleteAfterRead: false
            )
        }

        let fileManager = FileManager.default
        let bundledPackURL = bundledCameraBenchmarkPackURL()
        let bundledFallbackConfig = SemanticEvalReplayConfig(
            labelsPath: bundledPackURL.appendingPathComponent("camera_quick_labels.jsonl").path,
            imagesRootPath: bundledPackURL.appendingPathComponent("images").path,
            outputPath: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("semantic_eval_replay_candidate_outputs.jsonl")
                .path,
            runtime: "lightweight",
            limit: nil,
            deleteAfterRead: false
        )
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let repositoryConfigPath = repositoryRoot
            .appendingPathComponent("docs/cameraanalysis/eval/semantic_eval_replay_config.json")
            .path
        let configCandidates: [String] = [
            env["SEMANTIC_EVAL_CONFIG"],
            fileManager.currentDirectoryPath + "/docs/cameraanalysis/eval/semantic_eval_replay_config.json",
            repositoryConfigPath,
            "/private/tmp/semantic_eval_replay_config.json"
        ].compactMap { $0 }
        guard let configPath = configCandidates.first(where: { fileManager.fileExists(atPath: $0) }) else {
            return bundledFallbackConfig
        }
        let configURL = URL(fileURLWithPath: configPath)
        print("Semantic eval replay config path: \(configURL.path)")
        let config = try JSONDecoder().decode(
            SemanticEvalReplayConfig.self,
            from: Data(contentsOf: configURL)
        )
        if config.deleteAfterRead {
            try? FileManager.default.removeItem(at: configURL)
        }
        guard fileManager.fileExists(atPath: config.labelsPath),
              fileManager.fileExists(atPath: config.imagesRootPath) else {
            print("Semantic eval replay falling back to bundled camera benchmark pack: \(bundledPackURL.path)")
            return bundledFallbackConfig
        }
        return config
    }

    private func bundledCameraBenchmarkPackURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1")
    }

    private func loadLabels(path: String) throws -> [SemanticEvalLabelRecord] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let decoder = JSONDecoder()
        return try lines.map { line in
            try decoder.decode(SemanticEvalLabelRecord.self, from: Data(line.utf8))
        }
    }

    private func writeRows(_ rows: [SemanticEvalCandidateOutput], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let lines = try rows.map { row -> String in
            let data = try encoder.encode(row)
            return String(decoding: data, as: UTF8.self)
        }
        try lines.joined(separator: "\n")
            .appending("\n")
            .write(to: url, atomically: true, encoding: .utf8)
    }

    private func makePixelBuffer(from imageURL: URL) throws -> CVPixelBuffer {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(
                domain: "SemanticEvalStillImageBatchReplayTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not load image at \(imageURL.path)"]
            )
        }

        let width = image.width
        let height = image.height
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
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
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw NSError(
                domain: "SemanticEvalStillImageBatchReplayTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not create pixel buffer for \(imageURL.lastPathComponent)"]
            )
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw NSError(
                domain: "SemanticEvalStillImageBatchReplayTests",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Could not create bitmap context for \(imageURL.lastPathComponent)"]
            )
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }
}
