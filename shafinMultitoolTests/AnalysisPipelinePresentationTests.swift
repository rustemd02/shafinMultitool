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
        XCTAssertTrue(result.liveRow.liveTip?.localizedCaseInsensitiveContains("резк") == true)

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
        XCTAssertTrue(
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
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let imageURL = repoRoot
            .appendingPathComponent("docs/cameraanalysis/dataset/inbox/images")
            .appendingPathComponent(filename)
        return try makePixelBuffer(from: imageURL)
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
            return nil
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
        return config
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
