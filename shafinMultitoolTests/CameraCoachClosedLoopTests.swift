//
//  CameraCoachClosedLoopTests.swift
//  shafinMultitoolTests
//
//  M2-035: the closed-loop seam exercises the production owners in order:
//  immutable feature evidence -> semantic subject resolution -> deterministic
//  critique/planner -> safety gate/stabilizer -> CameraViewModel projection.
//  The final planner/verifier are never replaced by a test event publisher.
//

import AVFoundation
import CoreVideo
import Darwin
import Foundation
import XCTest
@testable import shafinMultitool

@MainActor
final class CameraCoachClosedLoopTests: XCTestCase {

    func testProductionOwnersAdvanceSubjectSelectionThroughStabilizedEpisode() async {
        await exerciseProductionEpisode(freshReplanning: false)
    }

    func testFreshReplanningPreservesEpisodeThroughVerification() async {
        await exerciseProductionEpisode(freshReplanning: true)
    }

    private func exerciseProductionEpisode(freshReplanning: Bool) async {
        let thermal = ThermalGovernor(
            thermalStateProvider: { .nominal },
            batteryLevelProvider: { 1.0 }
        )
        let manager = CameraManager(
            scheduler: RealtimeScheduler(),
            thermalGovernor: thermal,
            motionGate: MotionGate(startMotionUpdates: false),
            sessionRunner: ClosedLoopSessionRunner(),
            configuration: .ready,
            notificationCenter: NotificationCenter()
        )
        let neuralService = NeuralEvidenceInferenceService(
            configuration: makeNeuralConfiguration(),
            provider: ClosedLoopNeuralEvidenceProvider()
        )
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: neuralService,
            episodeConfidenceCalibrator: CameraEpisodeCalibrationFixture.calibrator,
            thermalGovernor: thermal,
            neuralHeavyModelsEnabledProvider: { true },
            liveHybridFusionEnabled: true,
            demoLiveCoachEnabled: false
        )
        let viewModel = CameraViewModel(cameraManager: manager, analysisPipeline: pipeline)
        defer {
            Task { @MainActor in
                await viewModel.releaseAndWait()
            }
        }

        await viewModel.startAndWait()

        let baseline = makeFrame(pipeline: pipeline, id: "closed-loop-neural-0", x: 0.80, seconds: 1)
        let baselineFrames = [
            baseline,
            makeFrame(pipeline: pipeline, id: "closed-loop-baseline-1", x: 0.80, seconds: 1.04),
            makeFrame(pipeline: pipeline, id: "closed-loop-baseline-2", x: 0.80, seconds: 1.08),
            // The live presentation owns a three-frame spatial confirmation
            // before a marker becomes visible. Keep two warm-up samples ahead
            // of the three samples consumed by AdviceStabilizer so the
            // episode baseline can only start from an actually visible hint.
            makeFrame(pipeline: pipeline, id: "closed-loop-baseline-3", x: 0.80, seconds: 1.12),
            makeFrame(pipeline: pipeline, id: "closed-loop-baseline-4", x: 0.80, seconds: 1.16)
        ]
        let semantics = SceneSemanticsAnalyzer().analyze(snapshot: baseline.snapshot)
        XCTAssertEqual(semantics.primarySubject.kind, .face)
        XCTAssertEqual(baseline.snapshot.subjectSignals.primaryCandidateSource, .vision)
        if let region = baseline.snapshot.subjectSignals.primaryCandidateRegion {
            XCTAssertGreaterThanOrEqual(region.x, 0.0)
            XCTAssertGreaterThanOrEqual(region.y, 0.0)
            XCTAssertLessThanOrEqual(
                region.x + region.width,
                1.0,
                "the neural subject fixture must stay inside the normalized frame"
            )
            XCTAssertLessThanOrEqual(
                region.y + region.height,
                1.0,
                "the neural subject fixture must stay inside the normalized frame"
            )
        } else {
            XCTFail("the closed-loop fixture must publish a bounded subject region")
        }

        var neuralLinkedBaselineFrameIDs = Set<String>()
        var acceptedBaselineFrameID: String?
        var acceptedSubjectIdentity: SubjectTrackIdentity?
        var acceptedSubjectRegion: NormalizedRect?
        var acceptedBaselinePlan: RecommendationPlan?

        // Every stabilizer input is independently produced by the real neural
        // provider + hybrid fusion owner. The accepted baseline cannot be
        // justified by the first pre-stabilization sample alone.
        for (index, frame) in baselineFrames.enumerated() {
            let frameSemantics = SceneSemanticsAnalyzer().analyze(snapshot: frame.snapshot)
            let deterministicCritique = FrameCritiqueEngine().analyze(
                snapshot: frame.snapshot,
                semantics: frameSemantics
            )
            let (fusionOutput, neuralOutcome) = await pipeline.testingResolveCritiqueWithHybridFusion(
                mode: .live,
                capturedAt: frame.date,
                pixelBuffer: frame.evidence.pixelBuffer,
                orientation: frame.evidence.orientation,
                snapshot: frame.snapshot,
                semantics: frameSemantics,
                deterministicCritique: deterministicCritique,
                forcePauseExecution: false
            )
            XCTAssertEqual(
                neuralOutcome?.kind,
                .executed,
                "neural metadata failure=\(String(describing: neuralOutcome?.metadata?.failureReason))"
            )
            let neuralValidationErrors = neuralOutcome?.snapshot?.validate(
                expectedFrameId: frame.snapshot.frameId,
                semanticsReport: frameSemantics,
                runtimeMetadata: neuralOutcome?.metadata
            ) ?? ["missing neural outcome"]
            XCTAssertEqual(neuralValidationErrors, [], "neural validation errors: \(neuralValidationErrors)")
            XCTAssertEqual(neuralOutcome?.snapshot?.frameId, frame.snapshot.frameId)
            XCTAssertEqual(pipeline.testingLatestLiveNeuralOutcome?.snapshot?.frameId, frame.snapshot.frameId)
            XCTAssertFalse(
                fusionOutput.appliedDecisions.isEmpty,
                "neural evidence must mutate or rank a deterministic finding before planning"
            )

            let plan = RecommendationPlanner().makePlan(
                snapshot: frame.snapshot,
                critique: fusionOutput.critique
            )
            XCTAssertEqual(plan.primaryAction?.actionType, .moveFrameRight)
            let fusedTargetIDs = Set(fusionOutput.appliedDecisions.map { $0.targetId })
            let neuralHeadSummary = neuralOutcome?.snapshot?.headOutputs.map { entry -> String in
                switch entry.payload {
                case let .scalar(output):
                    return "\(entry.headId.rawValue):\(output.status.rawValue):score=\(String(describing: output.score)):confidence=\(output.confidence)"
                case let .categorical(output):
                    return "\(entry.headId.rawValue):\(output.status.rawValue):confidence=\(output.confidence)"
                }
            } ?? []
            XCTAssertTrue(
                plan.primaryAction?.linkedIssueIds.contains(
                    where: { fusedTargetIDs.contains($0) }
                ) == true,
                "the bounded planner must consume the fused neural finding; " +
                    "decisions=\(fusionOutput.decisions.map { "\($0.targetId):\($0.outcome.rawValue):\($0.delta)" }) " +
                    "linkedIssues=\(String(describing: plan.primaryAction?.linkedIssueIds)) " +
                    "fallback=\(fusionOutput.critique.fallbackUsed) heads=\(neuralHeadSummary)"
            )
            neuralLinkedBaselineFrameIDs.insert(frame.snapshot.frameId)

            pipeline.testingPublishLiveProductionFrame(
                snapshot: frame.snapshot,
                semantics: frameSemantics,
                critique: fusionOutput.critique,
                plan: plan,
                frameEvidence: frame.evidence,
                evaluatedAt: frame.date,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: frame.date
            )

            if index == baselineFrames.count - 1 {
                guard let visibleHint = pipeline.currentLiveHint else {
                    XCTFail("production presentation must admit the corrective marker before the episode baseline")
                    continue
                }
                XCTAssertEqual(visibleHint.frameId, frame.snapshot.frameId)
                XCTAssertEqual(visibleHint.actionType, .moveFrameRight)
                guard case let .baseline(observation) = pipeline.currentCoachingEpisodeEvent else {
                    XCTFail("stabilized production input must publish a baseline event, got \(String(describing: pipeline.currentCoachingEpisodeEvent))")
                    continue
                }
                let expectedCalibration = CameraEpisodeCalibrationFixture.calibrator.calibratedEvidence(
                    rawScore: plan.planConfidence,
                    actionID: SemanticActionType.shiftFrameRight.rawValue,
                    inputVersion: .boundedPlanConfidenceV1
                )
                XCTAssertNotNil(expectedCalibration)
                XCTAssertEqual(observation.frame.evidence?.calibrationVersion,
                               expectedCalibration?.calibrationReference)
                guard let baselineBinding = observation.frame.evidence?.subjectBinding else {
                    XCTFail("subject-dependent baseline must retain its validated binding")
                    continue
                }
                XCTAssertEqual(visibleHint.subjectIdentity, baselineBinding.identity)
                XCTAssertEqual(visibleHint.observedSourceRegion, baselineBinding.region)
                acceptedSubjectIdentity = baselineBinding.identity
                acceptedSubjectRegion = baselineBinding.region
                acceptedBaselinePlan = plan
                XCTAssertEqual(observation.frame.frameID, frame.snapshot.frameId)
                XCTAssertEqual(
                    observation.stabilizedAdvice.actionID,
                    SemanticActionType.shiftFrameRight.rawValue
                )
                guard let geometry = observation.geometryContext else {
                    XCTFail("live verification must carry captured preview geometry")
                    continue
                }
                XCTAssertFalse(
                    geometry.displayTransform.isMirrored,
                    "live verification must preserve the captured preview mirror state"
                )
                XCTAssertEqual(
                    geometry.aspectFillTransform.destinationPixelWidth,
                    390,
                    accuracy: 0.0001,
                    "live verification must use actual preview destination geometry"
                )
                XCTAssertEqual(
                    geometry.aspectFillTransform.destinationPixelHeight,
                    844,
                    accuracy: 0.0001,
                    "live verification must use actual preview destination geometry"
                )
                acceptedBaselineFrameID = observation.frame.frameID
                let baselineConsumedByViewModel = await waitUntil {
                    viewModel.coachingEpisodeState.phase == .awaitingMovement
                        && viewModel.coachingEpisodeState.lastFrameID == observation.frame.frameID
                }
                XCTAssertTrue(baselineConsumedByViewModel)
            }
        }

        XCTAssertEqual(
            neuralLinkedBaselineFrameIDs,
            Set(baselineFrames.map { $0.snapshot.frameId })
        )
        XCTAssertTrue(
            acceptedBaselineFrameID.map { neuralLinkedBaselineFrameIDs.contains($0) } == true,
            "accepted baseline must be one of the neural-linked stabilizer frames"
        )

        if let acceptedSubjectIdentity, let acceptedSubjectRegion {
            let refreshedFrame = makeFrame(
                pipeline: pipeline,
                id: "closed-loop-same-track-refresh",
                x: 0.79,
                seconds: 1.20
            )
            let refreshedSemantics = SceneSemanticsAnalyzer().analyze(snapshot: refreshedFrame.snapshot)
            let refreshedDeterministicCritique = FrameCritiqueEngine().analyze(
                snapshot: refreshedFrame.snapshot,
                semantics: refreshedSemantics
            )
            let (refreshedFusion, _) = await pipeline.testingResolveCritiqueWithHybridFusion(
                mode: .live,
                capturedAt: refreshedFrame.date,
                pixelBuffer: refreshedFrame.evidence.pixelBuffer,
                orientation: refreshedFrame.evidence.orientation,
                snapshot: refreshedFrame.snapshot,
                semantics: refreshedSemantics,
                deterministicCritique: refreshedDeterministicCritique,
                forcePauseExecution: false
            )
            let refreshedPlan = RecommendationPlanner().makePlan(
                snapshot: refreshedFrame.snapshot,
                critique: refreshedFusion.critique
            )
            XCTAssertEqual(refreshedPlan.primaryAction?.actionType, .moveFrameRight)
            pipeline.testingPublishLiveProductionFrame(
                snapshot: refreshedFrame.snapshot,
                semantics: refreshedSemantics,
                critique: refreshedFusion.critique,
                plan: refreshedPlan,
                frameEvidence: refreshedFrame.evidence,
                evaluatedAt: refreshedFrame.date,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: refreshedFrame.date
            )
            XCTAssertEqual(
                pipeline.currentLiveHint?.subjectIdentity,
                acceptedSubjectIdentity,
                "ordinary region motion must retain the selected track identity"
            )
            XCTAssertNotEqual(
                pipeline.currentLiveHint?.observedSourceRegion,
                acceptedSubjectRegion,
                "ordinary region motion must refresh the visible source region"
            )
            XCTAssertEqual(
                pipeline.currentLiveHint?.observedSourceRegion,
                refreshedFrame.snapshot.subjectSignals.primaryCandidateRegion
            )
        }
        XCTAssertEqual(
            viewModel.coachingEpisodeState.baseline?.actionID,
            SemanticActionType.shiftFrameRight.rawValue
        )
        XCTAssertEqual(viewModel.coachingEpisodeState.baseline?.lensID, CameraLens.wide.rawValue)

        var sawFreshKeepDuringEpisode = false
        for (id, x, seconds, expectedPhase) in [
            // Vision evidence has a 250 ms freshness window. Keep adjacent
            // fixture frames inside that production cadence; a one-second
            // jump would legitimately make the frozen baseline stale when
            // the coordinator evaluates it at the current frame's `asOf`.
            ("closed-loop-movement-1", 0.76, 1.24, CoachingEpisodePhase.awaitingMovement),
            ("closed-loop-movement-2", 0.72, 1.28, CoachingEpisodePhase.collectingStableAfterFrames),
            ("closed-loop-stable-1", 0.72, 1.32, CoachingEpisodePhase.collectingStableAfterFrames),
            ("closed-loop-stable-2", 0.72, 1.36, CoachingEpisodePhase.readyForVerification)
        ] {
            let frame = makeFrame(pipeline: pipeline, id: id, x: x, seconds: seconds)
            let frameSemantics = SceneSemanticsAnalyzer().analyze(snapshot: frame.snapshot)
            let frameCritique = FrameCritiqueEngine().analyze(
                snapshot: frame.snapshot,
                semantics: frameSemantics
            )
            guard let acceptedBaselinePlan else {
                return XCTFail("the accepted production baseline must retain its typed plan")
            }
            let retainedPlan = RecommendationPlan(
                frameId: frame.snapshot.frameId,
                mode: acceptedBaselinePlan.mode,
                inputVerdict: acceptedBaselinePlan.inputVerdict,
                primaryAction: acceptedBaselinePlan.primaryAction,
                secondaryActions: acceptedBaselinePlan.secondaryActions,
                deferredActions: acceptedBaselinePlan.deferredActions,
                noChangeRationale: acceptedBaselinePlan.noChangeRationale,
                planConfidence: acceptedBaselinePlan.planConfidence
            )
            let continuationCritique: CritiqueReport
            let continuationPlan: RecommendationPlan
            if freshReplanning {
                let (fusion, neuralOutcome) = await pipeline.testingResolveCritiqueWithHybridFusion(
                    mode: .live,
                    capturedAt: frame.date,
                    pixelBuffer: frame.evidence.pixelBuffer,
                    orientation: frame.evidence.orientation,
                    snapshot: frame.snapshot,
                    semantics: frameSemantics,
                    deterministicCritique: frameCritique,
                    forcePauseExecution: false
                )
                XCTAssertEqual(neuralOutcome?.kind, .executed)
                continuationCritique = fusion.critique
                continuationPlan = RecommendationPlanner().makePlan(
                    snapshot: frame.snapshot,
                    critique: fusion.critique
                )
            } else {
                continuationCritique = frameCritique
                continuationPlan = retainedPlan
            }
            pipeline.testingPublishLiveProductionFrame(
                snapshot: frame.snapshot,
                semantics: frameSemantics,
                critique: continuationCritique,
                plan: continuationPlan,
                frameEvidence: frame.evidence,
                evaluatedAt: frame.date,
                legacySuggestion: nil,
                // Exercise both unavailable replacement (retained hint) and
                // a genuinely fresh structured plan on every after-frame.
                structuredAvailable: freshReplanning,
                now: frame.date
            )
            guard case let .frame(frameEvidence) = pipeline.currentCoachingEpisodeEvent else {
                XCTFail("production pipeline emitted \(String(describing: pipeline.currentCoachingEpisodeEvent)) instead of a frame event for \(id)")
                continue
            }
            XCTAssertEqual(frameEvidence.frame.frameID, id)
            let evidenceConsumedByViewModel = await waitUntil {
                viewModel.coachingEpisodeState.lastFrameID == id
                    && viewModel.coachingEpisodeState.phase == expectedPhase
            }
            XCTAssertTrue(
                evidenceConsumedByViewModel,
                "CameraViewModel did not consume \(id): phase=\(viewModel.coachingEpisodeState.phase.rawValue) " +
                    "lastFrameID=\(String(describing: viewModel.coachingEpisodeState.lastFrameID)) " +
                    "cancellation=\(String(describing: viewModel.coachingEpisodeState.cancellationReason?.rawValue))"
            )
            XCTAssertEqual(
                viewModel.coachingEpisodeState.baseline?.frameID,
                acceptedBaselineFrameID,
                "fresh recommendations must not replace the accepted episode baseline"
            )
            sawFreshKeepDuringEpisode = sawFreshKeepDuringEpisode || viewModel.plannerDecision == .keep
        }

        if freshReplanning {
            XCTAssertTrue(
                sawFreshKeepDuringEpisode,
                "fresh-replanning fixture must actually exercise a frame-local KEEP during the accepted episode"
            )
        }

        let finalEvidenceConsumedByViewModel = await waitUntil {
            viewModel.coachingEpisodeState.phase == .readyForVerification
                && viewModel.coachingEpisodeState.lastFrameID == "closed-loop-stable-2"
        }
        XCTAssertTrue(finalEvidenceConsumedByViewModel)
        guard let verificationInput = viewModel.testingVerificationInput else {
            return XCTFail("CameraViewModel must expose the same production-owned immutable pair")
        }
        let verification = ActionVerifier.verify(verificationInput)
        XCTAssertEqual(verification.decision, .comparable(outcome: .improved))
        XCTAssertEqual(
            viewModel.verificationResult,
            verification,
            "ready transition must automatically verify the immutable pair; no manual result injection"
        )
        let routedPresentation = CameraOverlayUXPresentation.make(
            liveHint: viewModel.liveHint,
            context: CameraOverlayUXContext(
                decision: viewModel.plannerDecision,
                episodeState: viewModel.coachingEpisodeState,
                verificationResult: viewModel.verificationResult,
                performance: viewModel.effectivePerformance,
                analysisStatus: viewModel.analysisStatus
            ),
            locale: Locale(identifier: "en")
        )
        XCTAssertEqual(
            routedPresentation.state,
            .verificationImproved,
            "final presentation: liveHint=\(String(describing: viewModel.liveHint?.id)) " +
                "planner=\(String(describing: viewModel.plannerDecision)) " +
                "episode=\(viewModel.coachingEpisodeState.phase.rawValue) " +
                "verification=\(String(describing: viewModel.verificationResult?.decision))"
        )
        XCTAssertEqual(
            routedPresentation.eventID,
            verification.token.rawValue.uuidString,
            "final marker event: presentation=\(String(describing: routedPresentation.eventID)) " +
                "token=\(verification.token.rawValue.uuidString)"
        )

        XCTAssertTrue(viewModel.continueCoaching(after: verification.token))
        XCTAssertEqual(viewModel.coachingEpisodeState.phase, .idle)
        XCTAssertNil(viewModel.verificationResult)
        XCTAssertNil(pipeline.currentLiveHint)
        for index in 0..<5 {
            let frame = makeFrame(
                pipeline: pipeline,
                id: "closed-loop-next-\(index)",
                x: 0.80,
                seconds: 1.40 + Double(index) * 0.04
            )
            let semantics = SceneSemanticsAnalyzer().analyze(snapshot: frame.snapshot)
            let critique = FrameCritiqueEngine().analyze(snapshot: frame.snapshot, semantics: semantics)
            let (fusion, _) = await pipeline.testingResolveCritiqueWithHybridFusion(
                mode: .live,
                capturedAt: frame.date,
                pixelBuffer: frame.evidence.pixelBuffer,
                orientation: frame.evidence.orientation,
                snapshot: frame.snapshot,
                semantics: semantics,
                deterministicCritique: critique,
                forcePauseExecution: false
            )
            let plan = RecommendationPlanner().makePlan(snapshot: frame.snapshot, critique: fusion.critique)
            pipeline.testingPublishLiveProductionFrame(
                snapshot: frame.snapshot,
                semantics: semantics,
                critique: fusion.critique,
                plan: plan,
                frameEvidence: frame.evidence,
                evaluatedAt: frame.date,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: frame.date
            )
        }
        let nextEpisode = await waitUntil {
            viewModel.coachingEpisodeState.phase == .awaitingMovement
                && viewModel.coachingEpisodeState.baseline?.frameID == "closed-loop-next-4"
        }
        XCTAssertTrue(nextEpisode, "explicit continuation must permit a fresh production baseline")
        XCTAssertNotEqual(viewModel.coachingEpisodeState.token, verification.token)
        let nextState = viewModel.coachingEpisodeState
        XCTAssertFalse(viewModel.continueCoaching(after: verification.token))
        XCTAssertEqual(viewModel.coachingEpisodeState, nextState, "a stale result button cannot erase the next episode")

        await viewModel.releaseAndWait()
    }

    func testRetryableTerminalResetCannotClearNewProductionBaseline() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let firstFrame = makeVerificationFrame(
            id: "terminal-fence-a",
            capturedAt: Date(timeIntervalSince1970: 1_771_500_000),
            actionID: SemanticActionType.shiftFrameRight.rawValue,
            x: 0.80
        )
        let secondFrame = makeVerificationFrame(
            id: "terminal-fence-b",
            capturedAt: Date(timeIntervalSince1970: 1_771_500_000.1),
            actionID: SemanticActionType.shiftFrameRight.rawValue,
            x: 0.80
        )
        let thirdFrame = makeVerificationFrame(
            id: "terminal-fence-c",
            capturedAt: Date(timeIntervalSince1970: 1_771_500_000.2),
            actionID: SemanticActionType.shiftFrameRight.rawValue,
            x: 0.80
        )
        guard let firstObservation = makeEpisodeObservation(
            frame: firstFrame,
            actionID: SemanticActionType.shiftFrameRight.rawValue
        ), let secondObservation = makeEpisodeObservation(
            frame: secondFrame,
            actionID: SemanticActionType.shiftFrameRight.rawValue
        ), let thirdObservation = makeEpisodeObservation(
            frame: thirdFrame,
            actionID: SemanticActionType.shiftFrameRight.rawValue
        ) else {
            return XCTFail("the fence fixture must form valid episode baselines")
        }

        pipeline.publishCoachingEpisodeEvent(.baseline(firstObservation))
        XCTAssertTrue(pipeline.resetCoachingEpisodeAfterTerminal(
            expectedBaselineFrameID: firstFrame.frameID,
            expectedCaptureGeneration: firstFrame.evidence?.lensGeneration ?? 0
        ))
        pipeline.publishCoachingEpisodeEvent(.baseline(secondObservation))
        XCTAssertFalse(pipeline.resetCoachingEpisodeAfterTerminal(
            expectedBaselineFrameID: firstFrame.frameID,
            expectedCaptureGeneration: firstFrame.evidence?.lensGeneration ?? 0
        ))
        pipeline.publishCoachingEpisodeEvent(.baseline(thirdObservation))

        guard case let .baseline(currentBaseline) = pipeline.currentCoachingEpisodeEvent else {
            return XCTFail("a stale terminal callback must not clear the newer baseline event")
        }
        XCTAssertEqual(currentBaseline.frame.frameID, secondFrame.frameID)
        pipeline.resetCoachingEpisodeAfterTerminal(
            expectedBaselineFrameID: secondFrame.frameID,
            expectedCaptureGeneration: secondFrame.evidence?.lensGeneration ?? 0
        )
        pipeline.publishCoachingEpisodeEvent(.baseline(thirdObservation))
        guard case let .baseline(acceptedBaseline) = pipeline.currentCoachingEpisodeEvent else {
            return XCTFail("matching terminal reset must release the previous transaction")
        }
        XCTAssertEqual(acceptedBaseline.frame.frameID, thirdFrame.frameID)

        let generationFencePipeline = AnalysisPipeline(reasoningProvider: nil)
        let reusedFrameID = "terminal-fence-reused"
        let generationA = makeVerificationFrame(
            id: reusedFrameID,
            capturedAt: Date(timeIntervalSince1970: 1_771_500_000.3),
            actionID: SemanticActionType.shiftFrameRight.rawValue,
            x: 0.80,
            generation: 11
        )
        let generationB = makeVerificationFrame(
            id: reusedFrameID,
            capturedAt: Date(timeIntervalSince1970: 1_771_500_000.4),
            actionID: SemanticActionType.shiftFrameRight.rawValue,
            x: 0.80,
            generation: 12
        )
        guard let generationAObservation = makeEpisodeObservation(
            frame: generationA,
            actionID: SemanticActionType.shiftFrameRight.rawValue
        ), let generationBObservation = makeEpisodeObservation(
            frame: generationB,
            actionID: SemanticActionType.shiftFrameRight.rawValue
        ) else {
            return XCTFail("the generation fence fixture must form valid episode baselines")
        }
        generationFencePipeline.publishCoachingEpisodeEvent(.baseline(generationAObservation))
        generationFencePipeline.resetCoachingEpisodeAfterTerminal(
            expectedBaselineFrameID: reusedFrameID,
            expectedCaptureGeneration: generationB.evidence?.lensGeneration ?? 0
        )
        generationFencePipeline.publishCoachingEpisodeEvent(.baseline(generationBObservation))
        guard case let .baseline(generationBaselineAfterMismatch) = generationFencePipeline.currentCoachingEpisodeEvent else {
            return XCTFail("a same-ID baseline from another capture generation must not pass the terminal fence")
        }
        XCTAssertEqual(generationBaselineAfterMismatch.lifecycle.generation, generationA.evidence?.lensGeneration)

        generationFencePipeline.resetCoachingEpisodeAfterTerminal(
            expectedBaselineFrameID: reusedFrameID,
            expectedCaptureGeneration: generationA.evidence?.lensGeneration ?? 0
        )
        generationFencePipeline.publishCoachingEpisodeEvent(.baseline(generationBObservation))
        guard case let .baseline(generationBaselineAfterMatch) = generationFencePipeline.currentCoachingEpisodeEvent else {
            return XCTFail("the matching frame ID and generation must release the terminal transaction")
        }
        XCTAssertEqual(generationBaselineAfterMatch.lifecycle.generation, generationB.evidence?.lensGeneration)
    }

    func testProductionSubjectSourceTimestampGateRejectsStaleAndFutureEvidence() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil,
                                        episodeConfidenceCalibrator: CameraEpisodeCalibrationFixture.calibrator)
        let baseDate = Date(timeIntervalSince1970: 1_771_500_100)

        func publish(_ frame: ClosedLoopFrame, evaluatedAt: Date) {
            let semantics = SceneSemanticsAnalyzer().analyze(snapshot: frame.snapshot)
            let critique = FrameCritiqueEngine().analyze(
                snapshot: frame.snapshot,
                semantics: semantics
            )
            let plan = RecommendationPlanner().makePlan(
                snapshot: frame.snapshot,
                critique: critique
            )
            pipeline.testingPublishLiveProductionFrame(
                snapshot: frame.snapshot,
                semantics: semantics,
                critique: critique,
                plan: plan,
                frameEvidence: frame.evidence,
                evaluatedAt: evaluatedAt,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: evaluatedAt
            )
        }

        var latestFrame: ClosedLoopFrame?
        for index in 0..<5 {
            let frame = makeFrame(
                pipeline: pipeline,
                id: "source-gate-valid-\(index)",
                x: 0.80,
                seconds: 1.00 + Double(index) * 0.04,
                baseDate: baseDate
            )
            latestFrame = frame
            publish(frame, evaluatedAt: frame.date)
        }

        guard let latestFrame else {
            return XCTFail("the source-gate fixture must produce an accepted frame")
        }
        XCTAssertEqual(
            latestFrame.evidence.featureSourceTimestamps[.vision],
            latestFrame.date,
            "the regression must exercise the immutable Vision source timestamp"
        )

        publish(
            latestFrame,
            evaluatedAt: latestFrame.date.addingTimeInterval(1.0)
        )
        XCTAssertNil(pipeline.currentLiveHint)
        XCTAssertTrue(pipeline.currentOverlayAnnotations.isEmpty)
        guard case let .cancel(staleReason) = pipeline.currentCoachingEpisodeEvent else {
            return XCTFail("stale source evidence must publish a typed cancellation")
        }
        XCTAssertEqual(staleReason, .subjectChanged)

        let futureFrame = makeFrame(
            pipeline: pipeline,
            id: "source-gate-future",
            x: 0.80,
            seconds: 1.24,
            baseDate: baseDate
        )
        publish(
            futureFrame,
            evaluatedAt: futureFrame.date.addingTimeInterval(-0.10)
        )
        XCTAssertNil(pipeline.currentLiveHint)
        XCTAssertTrue(pipeline.currentOverlayAnnotations.isEmpty)
        guard case let .cancel(futureReason) = pipeline.currentCoachingEpisodeEvent else {
            return XCTFail("future source evidence must publish a typed cancellation")
        }
        XCTAssertEqual(futureReason, .subjectChanged)
    }

    func testProductionFrameGlobalHintSurvivesSubjectLossWithoutIdentity() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil,
                                        episodeConfidenceCalibrator: CameraEpisodeCalibrationFixture.calibrator)
        let baseDate = Date(timeIntervalSince1970: 1_771_500_200)
        let technicalSignal = TechnicalQualitySignal(issues: [
            TechnicalQualityIssueSignal(
                type: .motionBlur,
                actionType: .stabilizeCamera,
                confidence: 0.92,
                severity: 0.92,
                isDominant: true
            )
        ])

        func makeNoActionPlan(for frame: ClosedLoopFrame) -> RecommendationPlan {
            RecommendationPlan(
                frameId: frame.snapshot.frameId,
                mode: .live,
                inputVerdict: .needsFix,
                primaryAction: nil,
                secondaryActions: [],
                deferredActions: [],
                noChangeRationale: nil,
                planConfidence: 0.92
            )
        }

        func publish(_ frame: ClosedLoopFrame) {
            let semantics = SceneSemanticsAnalyzer().analyze(snapshot: frame.snapshot)
            let critique = FrameCritiqueEngine().analyze(
                snapshot: frame.snapshot,
                semantics: semantics
            )
            pipeline.testingPublishLiveProductionFrame(
                snapshot: frame.snapshot,
                semantics: semantics,
                critique: critique,
                plan: makeNoActionPlan(for: frame),
                frameEvidence: frame.evidence,
                evaluatedAt: frame.date,
                legacySuggestion: nil,
                structuredAvailable: true,
                technicalQualitySignal: technicalSignal,
                allowStabilityWhileMoving: true,
                now: frame.date
            )
        }

        for index in 0..<3 {
            publish(
                makeFrame(
                    pipeline: pipeline,
                    id: "global-with-subject-\(index)",
                    x: 0.80,
                    seconds: 1.00 + Double(index) * 0.04,
                    baseDate: baseDate
                )
            )
        }

        XCTAssertEqual(
            pipeline.currentLiveHint?.technicalActionType,
            .stabilizeCamera,
            "typed frame-global advice must be visible before subject loss"
        )
        XCTAssertNil(pipeline.currentLiveHint?.subjectIdentity)
        guard case .baseline = pipeline.currentCoachingEpisodeEvent else {
            return XCTFail("frame-global technical advice must establish a baseline without a subject binding")
        }

        let subjectFrame = makeFrame(
            pipeline: pipeline,
            id: "global-subject-loss",
            x: 0.80,
            seconds: 1.12,
            baseDate: baseDate
        )
        guard let adapterState = subjectFrame.evidence.adapterState else {
            return XCTFail("the subject-loss fixture must retain immutable adapter state")
        }
        var subjectlessFeatures = adapterState.features
        subjectlessFeatures.subject = .init()
        let subjectlessState = PipelineFeatureSnapshotAdapterState(
            features: subjectlessFeatures,
            debugData: DebugData(),
            vision: nil,
            horizonMeasuredAt: adapterState.horizonMeasuredAt,
            horizon: adapterState.horizon,
            lightingMeasuredAt: adapterState.lightingMeasuredAt,
            lighting: adapterState.lighting,
            detr: adapterState.detr,
            aestheticMeasuredAt: adapterState.aestheticMeasuredAt,
            aesthetic: adapterState.aesthetic
        )
        let subjectlessSnapshot = pipeline.testingMakeFeatureSnapshot(
            mode: .live,
            frameId: subjectFrame.snapshot.frameId,
            capturedAt: subjectFrame.date,
            adapterState: subjectlessState
        )
        guard let subjectlessEvidence = LatestFrameEvidenceStore.Snapshot(
            pixelBuffer: subjectFrame.evidence.pixelBuffer,
            orientation: subjectFrame.evidence.orientation,
            sourceFrameId: subjectFrame.evidence.sourceFrameId,
            capturedAt: subjectFrame.evidence.capturedAt,
            isStable: subjectFrame.evidence.isStable,
            lensID: subjectFrame.evidence.lensID,
            previewGeometry: subjectFrame.evidence.previewGeometry,
            adapterState: subjectlessState,
            lensGeneration: subjectFrame.evidence.lensGeneration
        ) else {
            return XCTFail("the subject-loss fixture must retain immutable evidence")
        }
        let subjectlessFrame = ClosedLoopFrame(
            snapshot: subjectlessSnapshot,
            evidence: subjectlessEvidence,
            date: subjectFrame.date
        )
        publish(subjectlessFrame)

        XCTAssertEqual(
            pipeline.currentLiveHint?.technicalActionType,
            .stabilizeCamera,
            "subject loss must not clear a valid frame-global hint"
        )
        XCTAssertNil(pipeline.currentLiveHint?.subjectIdentity)
        guard case let .frame(frameEvidence) = pipeline.currentCoachingEpisodeEvent else {
            return XCTFail("subject loss must continue the frame-global episode instead of cancelling it")
        }
        XCTAssertNil(frameEvidence.frame.evidence?.subjectBinding)
        XCTAssertTrue(
            pipeline.currentOverlayAnnotations.allSatisfy { $0.targetRegion == nil },
            "subject loss must not retain a subject-targeted overlay"
        )
    }

    func testProductionDemoRegionMismatchClearsSubjectHintAndOverlay() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, demoLiveCoachEnabled: true)
        pipeline.setCameraDemoSceneMode(.portrait)
        let baseDate = Date(timeIntervalSince1970: 1_771_500_300)

        func publish(_ frame: ClosedLoopFrame) {
            let semantics = SceneSemanticsAnalyzer().analyze(snapshot: frame.snapshot)
            let critique = FrameCritiqueEngine().analyze(
                snapshot: frame.snapshot,
                semantics: semantics
            )
            pipeline.testingPublishLiveProductionFrame(
                snapshot: frame.snapshot,
                semantics: semantics,
                critique: critique,
                plan: RecommendationPlan(
                    frameId: frame.snapshot.frameId,
                    mode: .live,
                    inputVerdict: .good,
                    primaryAction: nil,
                    secondaryActions: [],
                    deferredActions: [],
                    noChangeRationale: "demo binding regression",
                    planConfidence: 0.90
                ),
                frameEvidence: frame.evidence,
                evaluatedAt: frame.date,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: frame.date
            )
        }

        for index in 0..<3 {
            publish(
                makeFrame(
                    pipeline: pipeline,
                    id: "demo-binding-\(index)",
                    x: 0.80,
                    // Keep each accepted marker beyond the existing 8 Hz
                    // overlay publication interval while staying inside the
                    // 250 ms spatial-evidence freshness window.
                    seconds: 1.00 + Double(index) * 0.15,
                    baseDate: baseDate
                )
            )
        }
        XCTAssertFalse(
            pipeline.currentOverlayAnnotations.isEmpty,
            "the production demo ingress must publish its accepted overlay before mismatch"
        )
        XCTAssertEqual(pipeline.currentLiveHint?.actionType, .moveFrameLeft)
        XCTAssertNotNil(pipeline.currentLiveHint?.subjectIdentity)
        XCTAssertEqual(
            pipeline.currentLiveHint?.observedSourceRegion,
            pipeline.currentLiveHint?.targetRegion
        )

        publish(
            makeFrame(
                pipeline: pipeline,
                id: "demo-binding-refresh",
                x: 0.80,
                seconds: 1.45,
                baseDate: baseDate
            )
        )
        XCTAssertEqual(pipeline.currentLiveHint?.frameId, "demo-binding-refresh")
        XCTAssertFalse(
            pipeline.currentOverlayAnnotations.isEmpty,
            "a same-identity confirmed demo candidate must retain its exact overlay"
        )

        let mismatchedFrame = makeFrame(
            pipeline: pipeline,
            id: "demo-binding-mismatch",
            x: 0.80,
            seconds: 1.60,
            baseDate: baseDate
        )
        let wrongRegion = NormalizedRect(x: 0.16, y: 0.20, width: 0.20, height: 0.40)
        let candidate = LiveHintPresentation(
            id: "lh_demo_region_mismatch",
            frameId: mismatchedFrame.snapshot.frameId,
            text: "Смести объект вправо.",
            confidence: 0.90,
            actionType: .moveFrameRight,
            actionId: nil,
            linkedIssueIds: [],
            summaryId: "demo_region_mismatch",
            traceRootIds: [],
            targetRegion: wrongRegion,
            overlayHint: OverlayHint(
                id: "ovh_demo_region_mismatch",
                kind: .arrow,
                targetRegion: wrongRegion,
                direction: .right
            ),
            isFallback: false,
            expandedVerdict: nil
        )
        let semantics = SceneSemanticsAnalyzer().analyze(snapshot: mismatchedFrame.snapshot)
        pipeline.testingAdmitLiveHintCandidate(
            candidate,
            snapshot: mismatchedFrame.snapshot,
            semantics: semantics,
            frameEvidence: mismatchedFrame.evidence,
            evaluatedAt: mismatchedFrame.date,
            now: mismatchedFrame.date
        )

        XCTAssertNil(pipeline.currentLiveHint)
        XCTAssertTrue(
            pipeline.currentOverlayAnnotations.isEmpty,
            "a demo box that disagrees with the observed source region must flush the old overlay"
        )
    }

    func testProductionDemoBackgroundActionUsesTypedAdmission() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, demoLiveCoachEnabled: true)
        pipeline.setCameraDemoSceneMode(.portrait)
        let detections = [
            FeatureSnapshotDetectedObject(
                boundingBox: CGRect(x: 0.05, y: 0.06, width: 0.14, height: 0.18),
                label: "cup",
                confidence: 0.90
            ),
            FeatureSnapshotDetectedObject(
                boundingBox: CGRect(x: 0.30, y: 0.08, width: 0.16, height: 0.20),
                label: "book",
                confidence: 0.88
            ),
            FeatureSnapshotDetectedObject(
                boundingBox: CGRect(x: 0.58, y: 0.10, width: 0.16, height: 0.18),
                label: "bottle",
                confidence: 0.86
            ),
            FeatureSnapshotDetectedObject(
                boundingBox: CGRect(x: 0.78, y: 0.16, width: 0.14, height: 0.18),
                label: "plant",
                confidence: 0.84
            )
        ]
        let firstFrame = makeFrame(
            pipeline: pipeline,
            id: "demo-background-unsupported-0",
            x: 0.40,
            seconds: 1.20,
            detrDetections: detections
        )
        guard let subjectRegion = firstFrame.snapshot.subjectSignals.primaryCandidateRegion else {
            return XCTFail("demo portrait fixture must retain a primary region")
        }
        let firstSemantics = makeProductionDemoSemantics(
            frameId: firstFrame.snapshot.frameId,
            kind: .face,
            region: subjectRegion,
            hasClearFocus: false
        )
        let formattingPipeline = AnalysisPipeline(reasoningProvider: nil, demoLiveCoachEnabled: true)
        formattingPipeline.setCameraDemoSceneMode(.portrait)
        formattingPipeline.testingPublishLivePresentation(
            frameId: firstFrame.snapshot.frameId,
            snapshot: firstFrame.snapshot,
            critique: FrameCritiqueEngine().analyze(snapshot: firstFrame.snapshot, semantics: firstSemantics),
            plan: makeNoActionPlan(frameId: firstFrame.snapshot.frameId),
            semantics: firstSemantics,
            legacySuggestion: nil,
            structuredAvailable: true,
            now: firstFrame.date
        )
        XCTAssertEqual(
            formattingPipeline.currentLiveHint?.actionType,
            .reduceBackgroundDistractions,
            "the fixture must exercise the busy-background demo action before production admission"
        )

        for index in 0..<3 {
            let frame = makeFrame(
                pipeline: pipeline,
                id: "demo-background-unsupported-\(index)",
                x: 0.40,
                seconds: 1.20 + (Double(index) * 0.04),
                detrDetections: detections
            )
            guard let subjectRegion = frame.snapshot.subjectSignals.primaryCandidateRegion else {
                return XCTFail("demo portrait fixture must retain a primary region")
            }
            let semantics = makeProductionDemoSemantics(
                frameId: frame.snapshot.frameId,
                kind: .face,
                region: subjectRegion,
                hasClearFocus: false
            )
            pipeline.testingPublishLiveProductionFrame(
                snapshot: frame.snapshot,
                semantics: semantics,
                critique: FrameCritiqueEngine().analyze(snapshot: frame.snapshot, semantics: semantics),
                plan: makeNoActionPlan(frameId: frame.snapshot.frameId),
                frameEvidence: frame.evidence,
                evaluatedAt: frame.date,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: frame.date
            )
        }

        XCTAssertNil(pipeline.currentLiveHint)
        XCTAssertTrue(
            pipeline.currentOverlayAnnotations.isEmpty,
            "unsupported demo background manipulation must not publish a subject box"
        )
    }

    func testProductionDemoQualityRejectionDoesNotLeakAnnotationsThroughGlobalFallback() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, demoLiveCoachEnabled: true)
        pipeline.setCameraDemoSceneMode(.object)
        let baseDate = Date(timeIntervalSince1970: 1_771_500_350)
        let technicalSignal = TechnicalQualitySignal(issues: [
            TechnicalQualityIssueSignal(
                type: .motionBlur,
                actionType: .stabilizeCamera,
                confidence: 0.92,
                severity: 0.92,
                isDominant: true
            )
        ])

        for index in 0..<3 {
            let frame = makeFrame(
                pipeline: pipeline,
                id: "demo-quality-fallback-\(index)",
                x: 0.20,
                seconds: 1.20 + (Double(index) * 0.04),
                baseDate: baseDate,
                visionEnabled: false,
                detrDetections: [
                    FeatureSnapshotDetectedObject(
                        boundingBox: CGRect(x: 0.02, y: 0.30, width: 0.18, height: 0.36),
                        label: "cup",
                        confidence: 0.90
                    )
                ]
            )
            guard let subjectRegion = frame.snapshot.subjectSignals.primaryCandidateRegion else {
                return XCTFail("demo object fixture must retain a primary region")
            }
            let semantics = makeProductionDemoSemantics(
                frameId: frame.snapshot.frameId,
                kind: .object,
                region: subjectRegion,
                hasClearFocus: true
            )
            pipeline.testingPublishLiveProductionFrame(
                snapshot: frame.snapshot,
                semantics: semantics,
                critique: FrameCritiqueEngine().analyze(snapshot: frame.snapshot, semantics: semantics),
                plan: makeNoActionPlan(frameId: frame.snapshot.frameId),
                frameEvidence: frame.evidence,
                evaluatedAt: frame.date,
                legacySuggestion: nil,
                structuredAvailable: true,
                technicalQualitySignal: technicalSignal,
                allowStabilityWhileMoving: true,
                now: frame.date
            )
        }

        XCTAssertEqual(pipeline.currentLiveHint?.technicalActionType, .stabilizeCamera)
        XCTAssertNil(pipeline.currentLiveHint?.subjectIdentity)
        XCTAssertTrue(
            pipeline.currentOverlayAnnotations.isEmpty,
            "a quality-rejected demo candidate must not leak its annotation through a global fallback"
        )
    }

    func testProductionDemoDetectionOnlyKeepDoesNotBecomeGlobalAdvice() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, demoLiveCoachEnabled: true)
        pipeline.setCameraDemoSceneMode(.object)
        let detection = FeatureSnapshotDetectedObject(
            boundingBox: CGRect(x: 0.40, y: 0.30, width: 0.20, height: 0.34),
            label: "cup",
            confidence: 0.90
        )
        let formattingPipeline = AnalysisPipeline(reasoningProvider: nil, demoLiveCoachEnabled: true)
        formattingPipeline.setCameraDemoSceneMode(.object)
        for index in 0..<3 {
            let frame = makeFrame(
                pipeline: formattingPipeline,
                id: "demo-detection-only-format-\(index)",
                x: 0.20,
                seconds: 1.20 + (Double(index) * 0.04),
                visionEnabled: false,
                detrDetections: [detection]
            )
            guard let region = frame.snapshot.subjectSignals.primaryCandidateRegion else {
                return XCTFail("demo object fixture must retain a primary region")
            }
            let semantics = makeProductionDemoSemantics(
                frameId: frame.snapshot.frameId,
                kind: .object,
                region: region,
                hasClearFocus: true
            )
            formattingPipeline.testingPublishLivePresentation(
                frameId: frame.snapshot.frameId,
                snapshot: frame.snapshot,
                critique: FrameCritiqueEngine().analyze(snapshot: frame.snapshot, semantics: semantics),
                plan: makeNoActionPlan(frameId: frame.snapshot.frameId),
                semantics: semantics,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: frame.date
            )
        }
        XCTAssertEqual(
            formattingPipeline.currentLiveHint?.actionType,
            .leaveFrameAsIs,
            "the fixture must reach the detection-only KEEP candidate before production admission"
        )
        XCTAssertNotNil(formattingPipeline.currentLiveHint?.targetRegion)
        XCTAssertNotNil(formattingPipeline.currentLiveHint?.overlayHint?.targetRegion)

        for index in 0..<3 {
            let frame = makeFrame(
                pipeline: pipeline,
                id: "demo-detection-only-keep-\(index)",
                x: 0.20,
                seconds: 1.20 + (Double(index) * 0.04),
                visionEnabled: false,
                detrDetections: [detection]
            )
            guard let subjectRegion = frame.snapshot.subjectSignals.primaryCandidateRegion else {
                return XCTFail("demo object fixture must retain a primary region")
            }
            let semantics = makeProductionDemoSemantics(
                frameId: frame.snapshot.frameId,
                kind: .object,
                region: subjectRegion,
                hasClearFocus: true
            )
            pipeline.testingPublishLiveProductionFrame(
                snapshot: frame.snapshot,
                semantics: semantics,
                critique: FrameCritiqueEngine().analyze(snapshot: frame.snapshot, semantics: semantics),
                plan: makeNoActionPlan(frameId: frame.snapshot.frameId),
                frameEvidence: frame.evidence,
                evaluatedAt: frame.date,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: frame.date
            )
        }

        XCTAssertNil(pipeline.currentLiveHint)
        XCTAssertTrue(pipeline.currentOverlayAnnotations.isEmpty)
    }

    func testProductionDemoSupportedActionPublishesExactBoundOverlay() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, demoLiveCoachEnabled: true)
        pipeline.setCameraDemoSceneMode(.portrait)
        let frame = makeFrame(
            pipeline: pipeline,
            id: "demo-supported-action",
            x: 0.40,
            seconds: 1.20,
            backlightIndex: 0.30
        )
        guard let subjectRegion = frame.snapshot.subjectSignals.primaryCandidateRegion else {
            return XCTFail("demo portrait fixture must retain a primary region")
        }
        let semantics = makeProductionDemoSemantics(
            frameId: frame.snapshot.frameId,
            kind: .face,
            region: subjectRegion,
            hasClearFocus: true
        )

        pipeline.testingPublishLiveProductionFrame(
            snapshot: frame.snapshot,
            semantics: semantics,
            critique: FrameCritiqueEngine().analyze(snapshot: frame.snapshot, semantics: semantics),
            plan: makeNoActionPlan(frameId: frame.snapshot.frameId),
            frameEvidence: frame.evidence,
            evaluatedAt: frame.date,
            legacySuggestion: nil,
            structuredAvailable: true,
            now: frame.date
        )

        XCTAssertEqual(pipeline.currentLiveHint?.actionType, .improveFrontLight)
        XCTAssertNotNil(pipeline.currentLiveHint?.subjectIdentity)
        XCTAssertEqual(pipeline.currentLiveHint?.observedSourceRegion, subjectRegion)
        XCTAssertEqual(pipeline.currentOverlayAnnotations.count, 1)
        XCTAssertEqual(pipeline.currentOverlayAnnotations.first?.targetRegion, subjectRegion)
    }

    func testProductionSceneIdentityIgnoresNoiseAndLocalMotionButRotatesOnMaterialCut() {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let baseLuma: [UInt8] = [
            32, 96, 160, 224,
            64, 128, 192, 240,
            48, 112, 176, 208,
            80, 144, 200, 232
        ]
        let noiseLuma = baseLuma.enumerated().map { index, value in
            value &+ (index.isMultiple(of: 2) ? 4 : 0)
        }
        var localMotionLuma = baseLuma
        localMotionLuma[0] = 220
        localMotionLuma[5] = 20
        let materialCutLuma: [UInt8] = [
            232, 176, 112, 48,
            208, 144, 80, 24,
            240, 184, 120, 56,
            216, 152, 88, 40
        ]

        pipeline.testingResetLiveSceneIdentity()
        guard let baseIdentity = pipeline.testingLiveSceneIdentity(
            for: makePixelBuffer(lumaValues: baseLuma)
        ) else {
            return XCTFail("production scene identity must be readable for BGRA capture")
        }
        XCTAssertEqual(
            pipeline.testingLiveSceneIdentity(for: makePixelBuffer(lumaValues: noiseLuma)),
            baseIdentity,
            "small sensor luminance noise must not rotate the episode identity"
        )
        XCTAssertEqual(
            pipeline.testingLiveSceneIdentity(for: makePixelBuffer(lumaValues: localMotionLuma)),
            baseIdentity,
            "a local subject displacement must not be treated as a material scene cut"
        )
        guard let materialCutIdentity = pipeline.testingLiveSceneIdentity(
            for: makePixelBuffer(lumaValues: materialCutLuma)
        ) else {
            return XCTFail("material cut fixture must remain readable")
        }
        XCTAssertNotEqual(
            materialCutIdentity,
            baseIdentity,
            "a material composition change must rotate the production episode identity"
        )
    }

    func testTypedSceneCutCoordinatorFixtureRetainsTerminalState() async {
        let thermal = ThermalGovernor(
            thermalStateProvider: { .nominal },
            batteryLevelProvider: { 1.0 }
        )
        let manager = CameraManager(
            scheduler: RealtimeScheduler(),
            thermalGovernor: thermal,
            motionGate: MotionGate(startMotionUpdates: false),
            sessionRunner: ClosedLoopSessionRunner(),
            configuration: .ready,
            notificationCenter: NotificationCenter()
        )
        let neuralService = NeuralEvidenceInferenceService(
            configuration: makeNeuralConfiguration(),
            provider: ClosedLoopNeuralEvidenceProvider()
        )
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: neuralService,
            episodeConfidenceCalibrator: CameraEpisodeCalibrationFixture.calibrator,
            thermalGovernor: thermal,
            neuralHeavyModelsEnabledProvider: { true },
            liveHybridFusionEnabled: true,
            demoLiveCoachEnabled: false
        )
        let viewModel = CameraViewModel(cameraManager: manager, analysisPipeline: pipeline)
        defer {
            Task { @MainActor in
                await viewModel.releaseAndWait()
            }
        }

        await viewModel.startAndWait()

        let baseDate = Date(timeIntervalSince1970: 1_771_111_100)
        let baseLuma = [UInt8](repeating: 0, count: 16)
        let cutLuma: [UInt8] = [
            232, 176, 112, 48,
            208, 144, 80, 24,
            240, 184, 120, 56,
            216, 152, 88, 40
        ]
        func publish(_ frame: ClosedLoopFrame) async {
            let semantics = SceneSemanticsAnalyzer().analyze(snapshot: frame.snapshot)
            let deterministicCritique = FrameCritiqueEngine().analyze(
                snapshot: frame.snapshot,
                semantics: semantics
            )
            let (fusionOutput, neuralOutcome) = await pipeline.testingResolveCritiqueWithHybridFusion(
                mode: .live,
                capturedAt: frame.date,
                pixelBuffer: frame.evidence.pixelBuffer,
                orientation: frame.evidence.orientation,
                snapshot: frame.snapshot,
                semantics: semantics,
                deterministicCritique: deterministicCritique,
                forcePauseExecution: false
            )
            XCTAssertEqual(neuralOutcome?.kind, .executed)
            let plan = RecommendationPlanner().makePlan(
                snapshot: frame.snapshot,
                critique: fusionOutput.critique
            )
            XCTAssertEqual(plan.primaryAction?.actionType, .moveFrameRight)
            pipeline.testingPublishLiveProductionFrame(
                snapshot: frame.snapshot,
                semantics: semantics,
                critique: fusionOutput.critique,
                plan: plan,
                frameEvidence: frame.evidence,
                evaluatedAt: frame.date,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: frame.date
            )
        }

        let baselineFrames = (0..<5).map { index in
            makeFrame(
                pipeline: pipeline,
                id: index == 0
                    ? "production-scene-baseline"
                    : "production-scene-baseline-\(index)",
                x: 0.80,
                seconds: Double(index) * 0.01,
                baseDate: baseDate,
                lumaValues: baseLuma
            )
        }
        for frame in baselineFrames {
            await publish(frame)
        }
        let baselineAccepted = await waitUntil {
            viewModel.coachingEpisodeState.phase == .awaitingMovement
                && viewModel.coachingEpisodeState.baseline?.frameID == baselineFrames.last?.snapshot.frameId
        }
        XCTAssertTrue(
            baselineAccepted,
            "the production scene-cut fixture must establish its initial baseline"
        )
        guard case .baseline = pipeline.currentCoachingEpisodeEvent else {
            return XCTFail("production pipeline must retain the accepted baseline event")
        }
        let firstToken = viewModel.coachingEpisodeState.token

        let cutFrame = makeFrame(
            pipeline: pipeline,
            id: "production-scene-cut",
            x: 0.80,
            seconds: 0.06,
            baseDate: baseDate,
            lumaValues: cutLuma
        )
        await publish(cutFrame)

        let sceneCutConsumed = await waitUntil {
            viewModel.coachingEpisodeState.phase == .cancelled
                && viewModel.coachingEpisodeState.cancellationReason == .sceneCut
        }
        XCTAssertTrue(
            sceneCutConsumed,
            "the production scene-cut fixture must enter the cancelled phase"
        )

        let terminalState = viewModel.coachingEpisodeState
        let staleFrame = makeFrame(
            pipeline: pipeline,
            id: "production-scene-late-pre-cut",
            x: 0.80,
            seconds: 0.05,
            baseDate: baseDate,
            lumaValues: baseLuma
        )
        await publish(staleFrame)
        XCTAssertEqual(
            pipeline.testingLatestFrameEvidence?.sourceFrameId,
            cutFrame.snapshot.frameId,
            "capture admission must reject late pixels before they can rotate scene identity"
        )
        guard case .cancel = pipeline.currentCoachingEpisodeEvent else {
            return XCTFail("the stale pre-cut frame must not replace the cancelled production stream")
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(viewModel.coachingEpisodeState.phase, terminalState.phase)
        XCTAssertEqual(viewModel.coachingEpisodeState.token, terminalState.token)
        XCTAssertEqual(viewModel.coachingEpisodeState.baseline, terminalState.baseline)
        XCTAssertEqual(viewModel.coachingEpisodeState.lastFrameID, terminalState.lastFrameID)
        XCTAssertEqual(viewModel.coachingEpisodeState.movementFrames, terminalState.movementFrames)
        XCTAssertEqual(viewModel.coachingEpisodeState.stableAfterFrames, terminalState.stableAfterFrames)
        XCTAssertEqual(
            viewModel.coachingEpisodeState.cancellationReason,
            terminalState.cancellationReason
        )

        let freshBaselineFrames = (0..<5).map { index in
            makeFrame(
                pipeline: pipeline,
                id: index == 0
                    ? "production-scene-fresh-baseline"
                    : "production-scene-fresh-baseline-\(index)",
                x: 0.80,
                seconds: 0.08 + (Double(index) * 0.01),
                baseDate: baseDate,
                lumaValues: cutLuma
            )
        }
        for frame in freshBaselineFrames {
            await publish(frame)
        }

        let retryAccepted = await waitUntil {
            viewModel.coachingEpisodeState.phase == .awaitingMovement
                && viewModel.coachingEpisodeState.baseline?.frameID == freshBaselineFrames.last?.snapshot.frameId
        }
        XCTAssertTrue(
            retryAccepted,
            "the production scene-cut fixture must establish a fresh baseline after retry: " +
                "phase=\(viewModel.coachingEpisodeState.phase.rawValue), " +
                "baseline=\(String(describing: viewModel.coachingEpisodeState.baseline?.frameID)), " +
                "lastFrame=\(String(describing: viewModel.coachingEpisodeState.lastFrameID)), " +
                "cancellation=\(String(describing: viewModel.coachingEpisodeState.cancellationReason)), " +
                "hint=\(String(describing: viewModel.liveHint?.actionType))"
        )
        XCTAssertNotEqual(viewModel.coachingEpisodeState.token, firstToken)
        XCTAssertEqual(viewModel.coachingEpisodeState.cancellationReason, nil)

        await viewModel.releaseAndWait()
    }

    func testProductionCapturePathPublishesCorrectiveAndHonestAbstention() async throws {
        let corrective = makeCapturePathHarness(visionResult: { _, _ in
            Self.supportedCaptureVisionResult
        }, neuralEnabled: false, episodeConfidenceCalibrator: CameraEpisodeCalibrationFixture.calibrator)
        await corrective.viewModel.startAndWait()
        corrective.manager.updatePreviewGeometry(Self.capturePreviewGeometry)

        for index in 0..<10 {
            let timestamp = CMTime(value: Int64(1_000 + index * 100), timescale: 1_000)
            try await deliverCaptureSample(
                through: corrective,
                timestamp: timestamp,
                lumaValues: Self.supportedCaptureLuma
            )
            let published = await waitUntil {
                guard let evidence = corrective.pipeline.testingLatestFrameEvidence else {
                    return false
                }
                return CMTimeCompare(evidence.samplePresentationTimestamp, timestamp) == 0
            }
            XCTAssertTrue(
                published,
                "the real CameraManager.captureOutput boundary must publish sample index=\(index) with PTS=\(timestamp.seconds)"
            )
        }

        let correctiveBaselinePublished = await waitUntil {
            corrective.viewModel.coachingEpisodeState.phase == .awaitingMovement
                && corrective.viewModel.coachingEpisodeState.baseline != nil
        }
        XCTAssertTrue(correctiveBaselinePublished,
                      "CameraManager.captureOutput -> RealtimeScheduler -> AnalysisPipeline -> CameraViewModel must publish a corrective baseline")
        let baseline = try XCTUnwrap(corrective.viewModel.coachingEpisodeState.baseline,
                                     "CameraViewModel must retain the production baseline after later frame evidence")
        XCTAssertEqual(baseline.advice.actionID, SemanticActionType.shiftFrameRight.rawValue)
        XCTAssertEqual(corrective.viewModel.coachingEpisodeState.phase, .awaitingMovement)
        XCTAssertEqual(corrective.viewModel.coachingEpisodeState.baseline?.frameID, baseline.frame.frameID)
        XCTAssertEqual(corrective.pipeline.testingDirectFrameAcceptanceCount, 0)
        XCTAssertEqual(corrective.pipeline.testingLatestFrameEvidence?.sessionGeneration,
                       corrective.manager.sessionGenerationForTesting)

        await corrective.viewModel.releaseAndWait()

        let abstention = makeCapturePathHarness(visionResult: { _, _ in
            Self.emptyCaptureVisionResult
        }, neuralEnabled: false)
        await abstention.viewModel.startAndWait()
        abstention.manager.updatePreviewGeometry(Self.capturePreviewGeometry)
        try await deliverCaptureSample(
            through: abstention,
            timestamp: CMTime(value: 3_000, timescale: 1_000),
            lumaValues: [128, 128, 128, 128, 128, 128, 128, 128,
                         128, 128, 128, 128, 128, 128, 128, 128]
        )

        XCTAssertNotNil(abstention.pipeline.testingLatestFrameEvidence)
        XCTAssertNil(abstention.pipeline.currentLiveHint,
                     "a frame with no supported subject/evidence must remain an honest abstention")
        XCTAssertNil(abstention.pipeline.currentCoachingEpisodeEvent)
        XCTAssertNil(abstention.viewModel.liveHint)
        XCTAssertNil(abstention.viewModel.plannerDecision)
        XCTAssertEqual(abstention.viewModel.coachingEpisodeState.phase, .idle)
        XCTAssertEqual(abstention.pipeline.testingDirectFrameAcceptanceCount, 0)

        await abstention.viewModel.releaseAndWait()
    }

    func testProductionCaptureWithoutCalibrationCannotVerifySubjectMovement() async throws {
        let visionSequence = CaptureVisionSequence()
        let harness = makeCapturePathHarness(visionResult: { _, _ in
            visionSequence.nextResult()
        }, neuralEnabled: false)
        await harness.viewModel.startAndWait()
        harness.manager.updatePreviewGeometry(Self.capturePreviewGeometry)
        defer { Task { @MainActor in await harness.viewModel.releaseAndWait() } }

        // Use the same samples as the calibrated positive owner-chain test.
        // Only its explicitly synthetic calibration dependency is absent.
        for index in 0..<10 {
            try await deliverCaptureSample(
                through: harness,
                timestamp: CMTime(value: Int64(1_000 + index * 100), timescale: 1_000),
                lumaValues: Self.supportedCaptureLuma
            )
        }
        let advicePublished = await waitUntil { harness.viewModel.liveHint != nil }
        XCTAssertTrue(advicePublished, "missing episode calibration must retain useful local live advice")
        XCTAssertNotNil(harness.pipeline.currentLiveHint?.observedSourceRegion,
                        "the existing measured subject geometry must remain available")
        guard case .cancel(.calibrationUnavailable) = harness.pipeline.currentCoachingEpisodeEvent else {
            return XCTFail("an uncalibrated production candidate must report its missing evidence explicitly")
        }
        XCTAssertNil(harness.viewModel.coachingEpisodeState.baseline)
        XCTAssertNil(harness.viewModel.verificationResult)

        for index in 10..<14 {
            try await deliverCaptureSample(
                through: harness,
                timestamp: CMTime(value: Int64(1_000 + index * 100), timescale: 1_000),
                lumaValues: Self.supportedCaptureLuma
            )
            XCTAssertNil(harness.viewModel.coachingEpisodeState.baseline)
            XCTAssertNil(harness.viewModel.verificationResult,
                         "movement and stable after-frames cannot manufacture calibrated evidence")
        }
        XCTAssertEqual(harness.viewModel.coachingEpisodeState.phase, .idle)
        XCTAssertEqual(harness.pipeline.testingDirectFrameAcceptanceCount, 0)
        await harness.viewModel.releaseAndWait()
    }

    func testProductionCapturePathAutomaticallyVerifiesCorrectiveEpisode() async throws {
        let visionSequence = CaptureVisionSequence()
        let harness = makeCapturePathHarness(visionResult: { _, _ in
            visionSequence.nextResult()
        }, neuralEnabled: false, episodeConfidenceCalibrator: CameraEpisodeCalibrationFixture.calibrator)
        await harness.viewModel.startAndWait()
        harness.manager.updatePreviewGeometry(Self.capturePreviewGeometry)

        // Ten identical capture samples establish the visible corrective
        // marker/baseline through the real CameraManager callback and
        // RealtimeScheduler cadence. The following two samples move the
        // tracked subject left (the requested shift_frame_right action), and
        // the last two are stable after-frames.
        for index in 0..<14 {
            try await deliverCaptureSample(
                through: harness,
                timestamp: CMTime(value: Int64(1_000 + index * 100), timescale: 1_000),
                lumaValues: Self.supportedCaptureLuma
            )
        }

        let verified = await waitUntil {
            harness.viewModel.coachingEpisodeState.phase == .readyForVerification
                && harness.viewModel.verificationResult != nil
        }
        XCTAssertTrue(
            verified,
            "the ready episode must invoke ActionVerifier from CameraViewModel without a manual seam"
        )
        let result = try XCTUnwrap(
            harness.viewModel.verificationResult,
            "the production owner must retain the automatic verification result"
        )
        let baseline = try XCTUnwrap(
            harness.viewModel.coachingEpisodeState.baseline,
            "automatic verification must retain the immutable production baseline"
        )
        let baselineEvidence = try XCTUnwrap(baseline.frame.evidence)
        XCTAssertTrue(
            baseline.samplePresentationTimestamp.isNumeric,
            "the baseline must retain the synthetic CMSampleBuffer PTS"
        )
        XCTAssertEqual(
            CMTimeCompare(
                baseline.samplePresentationTimestamp,
                baselineEvidence.samplePresentationTimestamp
            ),
            0,
            "baseline metadata and its frame evidence must carry the same sample PTS"
        )
        XCTAssertEqual(
            baseline.sessionGeneration,
            harness.manager.sessionGenerationForTesting,
            "the baseline must retain CameraManager's capture session generation"
        )
        XCTAssertEqual(
            baselineEvidence.sessionGeneration,
            harness.manager.sessionGenerationForTesting,
            "the accepted frame evidence must retain CameraManager's session generation"
        )
        XCTAssertEqual(result.decision, .comparable(outcome: .improved))
        XCTAssertEqual(result.token, harness.viewModel.coachingEpisodeState.token)
        let presentation = CameraOverlayUXPresentation.make(
            liveHint: harness.viewModel.liveHint,
            context: CameraOverlayUXContext(
                decision: harness.viewModel.plannerDecision,
                episodeState: harness.viewModel.coachingEpisodeState,
                verificationResult: result,
                performance: harness.viewModel.effectivePerformance,
                analysisStatus: harness.viewModel.analysisStatus
            ),
            locale: Locale(identifier: "en")
        )
        XCTAssertEqual(presentation.state, .verificationImproved)
        XCTAssertEqual(presentation.observation, SETCopyKey.cameraVerificationImproved.localizedString(locale: Locale(identifier: "en")))
        XCTAssertEqual(
            result.afterFrameID,
            harness.viewModel.coachingEpisodeState.lastFrameID,
            "the result must belong to the same immutable ready pair"
        )

        // A later unrelated live frame may update the live pipeline, but it
        // cannot erase feedback owned by this completed episode token.
        try await deliverCaptureSample(
            through: harness,
            timestamp: CMTime(value: 2_500, timescale: 1_000),
            lumaValues: Self.supportedCaptureLuma
        )
        let unrelatedEvidence = try XCTUnwrap(harness.pipeline.testingLatestFrameEvidence)
        XCTAssertEqual(
            CMTimeCompare(
                unrelatedEvidence.samplePresentationTimestamp,
                CMTime(value: 2_500, timescale: 1_000)
            ),
            0,
            "the final real capture callback must retain its exact sample PTS"
        )
        XCTAssertEqual(
            unrelatedEvidence.sessionGeneration,
            harness.manager.sessionGenerationForTesting,
            "the final accepted frame must retain the active CameraManager session"
        )
        XCTAssertEqual(harness.viewModel.verificationResult, result)
        XCTAssertEqual(harness.viewModel.coachingEpisodeState.phase, .readyForVerification)

        await harness.viewModel.releaseAndWait()
    }

    func testSubjectIdentityLaneMaintainsStableIdentityAcrossLiveFrames() async throws {
        let harness = makeCapturePathHarness(visionResult: { _, _ in
            Self.supportedCaptureVisionResult
        }, neuralEnabled: false)
        await harness.viewModel.startAndWait()
        harness.manager.updatePreviewGeometry(Self.capturePreviewGeometry)

        for index in 0..<10 {
            try await deliverCaptureSample(
                through: harness,
                timestamp: CMTime(value: Int64(1_000 + index * 100), timescale: 1_000),
                lumaValues: Self.supportedCaptureLuma
            )
        }

        let identities = await MainActor.run {
            harness.pipeline.testingSubjectIdentityRegistry?.identities ?? []
        }
        XCTAssertEqual(identities.count, 1,
                       "the stable primary candidate must register exactly one identity")
        let summary = await MainActor.run { harness.pipeline.testingSubjectMultiObjectSummary }
        XCTAssertEqual(summary?.identityCount, 1,
                       "the O02/O05 summary must mirror the registry")
        XCTAssertEqual(identities.first?.consecutiveMisses, 0,
                       "a continuously seen subject must not age")
        XCTAssertGreaterThanOrEqual(identities.first?.lifetimeFrames ?? 0, 2,
                                    "the identity must be re-associated across frames")
    }

    func testProductionCapturePathSceneCutRejectsLatePreCutSampleAndRetries() async throws {
        let harness = makeCapturePathHarness(visionResult: { _, _ in
            Self.supportedCaptureVisionResult
        }, neuralEnabled: false, episodeConfidenceCalibrator: CameraEpisodeCalibrationFixture.calibrator)
        await harness.viewModel.startAndWait()
        harness.manager.updatePreviewGeometry(Self.capturePreviewGeometry)

        let baseLuma = Self.supportedCaptureLuma
        let cutLuma: [UInt8] = [
            208, 48, 208, 48,
            48, 208, 48, 208,
            208, 48, 208, 48,
            48, 208, 48, 208
        ]
        for index in 0..<10 {
            try await deliverCaptureSample(
                through: harness,
                timestamp: CMTime(value: Int64(1_000 + index * 100), timescale: 1_000),
                lumaValues: Self.supportedCaptureLuma
            )
        }

        let baselineAccepted = await waitUntil {
            harness.viewModel.coachingEpisodeState.phase == .awaitingMovement
                && harness.viewModel.coachingEpisodeState.baseline != nil
        }
        XCTAssertTrue(baselineAccepted,
                      "captureOutput -> scheduler -> pipeline must publish the initial baseline")
        let firstToken = harness.viewModel.coachingEpisodeState.token
        let baselineSceneIdentity = harness.viewModel.coachingEpisodeState.baseline?.lifecycle.sceneSignature

        try await deliverCaptureSample(
            through: harness,
            timestamp: CMTime(value: 2_000, timescale: 1_000),
            lumaValues: cutLuma
        )
        let sceneCutPublished = await waitUntil {
            harness.viewModel.coachingEpisodeState.phase == .cancelled
                && harness.viewModel.coachingEpisodeState.cancellationReason == .sceneCut
        }
        XCTAssertTrue(sceneCutPublished,
                      "captureOutput -> ViewModel must consume the scene-cut cancellation")

        let terminalState = harness.viewModel.coachingEpisodeState
        let terminalEvent = harness.pipeline.currentCoachingEpisodeEvent
        let terminalEvidence = try XCTUnwrap(harness.pipeline.testingLatestFrameEvidence)
        let terminalLiveHint = harness.pipeline.currentLiveHint
        let terminalPlannerDecision = harness.viewModel.plannerDecision
        let terminalPipelineTrace = harness.pipeline.testingLiveFusionTraceBundle
        let terminalPipelineGeneration = harness.pipeline.testingLifecycleGeneration
        let terminalCaptureGeneration = terminalEvidence.lensGeneration
        let terminalSessionGeneration = terminalEvidence.sessionGeneration
        let terminalSceneIdentity = terminalState.baseline?.lifecycle.sceneSignature

        // This is a real late CMSampleBuffer after the scene-cut cancellation.
        // Its callback arrives now, but its pre-cut sample PTS is older than the
        // accepted cut frame, so it must stop at the pipeline provenance gate.
        try await deliverCaptureSample(
            through: harness,
            timestamp: CMTime(value: 1_400, timescale: 1_000),
            lumaValues: baseLuma
        )

        let stateAfterStale = harness.viewModel.coachingEpisodeState
        XCTAssertEqual(stateAfterStale.phase, terminalState.phase)
        XCTAssertEqual(stateAfterStale.token, terminalState.token)
        XCTAssertEqual(stateAfterStale.baseline, terminalState.baseline)
        XCTAssertEqual(stateAfterStale.lastFrameID, terminalState.lastFrameID)
        XCTAssertEqual(stateAfterStale.movementFrames, terminalState.movementFrames)
        XCTAssertEqual(stateAfterStale.stableAfterFrames, terminalState.stableAfterFrames)
        XCTAssertEqual(stateAfterStale.cancellationReason, terminalState.cancellationReason)
        XCTAssertEqual(harness.pipeline.currentCoachingEpisodeEvent, terminalEvent)
        XCTAssertEqual(harness.pipeline.currentLiveHint, terminalLiveHint)
        XCTAssertEqual(harness.viewModel.plannerDecision, terminalPlannerDecision)
        XCTAssertEqual(harness.pipeline.testingLiveFusionTraceBundle, terminalPipelineTrace)
        XCTAssertEqual(harness.pipeline.testingLifecycleGeneration, terminalPipelineGeneration)
        XCTAssertEqual(harness.pipeline.testingLatestFrameEvidence?.sourceFrameId, terminalEvidence.sourceFrameId)
        XCTAssertEqual(
            CMTimeCompare(
                harness.pipeline.testingLatestFrameEvidence!.samplePresentationTimestamp,
                terminalEvidence.samplePresentationTimestamp
            ),
            0
        )
        XCTAssertEqual(harness.pipeline.testingLatestFrameEvidence?.lensGeneration, terminalCaptureGeneration)
        XCTAssertEqual(harness.pipeline.testingLatestFrameEvidence?.sessionGeneration, terminalSessionGeneration)
        XCTAssertEqual(stateAfterStale.baseline?.lifecycle.sceneSignature, terminalSceneIdentity)
        XCTAssertEqual(stateAfterStale.baseline?.lifecycle.sceneSignature, baselineSceneIdentity)

        for index in 0..<10 {
            try await deliverCaptureSample(
                through: harness,
                timestamp: CMTime(value: Int64(2_100 + index * 100), timescale: 1_000),
                lumaValues: cutLuma
            )
        }

        let retryAccepted = await waitUntil {
            harness.viewModel.coachingEpisodeState.phase == .awaitingMovement
                && harness.viewModel.coachingEpisodeState.baseline?.frameID
                    != terminalState.baseline?.frameID
        }
        XCTAssertTrue(retryAccepted,
                      "fresh post-cut capture samples must establish a new baseline")
        XCTAssertNotEqual(harness.viewModel.coachingEpisodeState.token, firstToken,
                          "scene-cut retry must issue a fresh episode token")
        XCTAssertNil(harness.viewModel.coachingEpisodeState.cancellationReason)
        XCTAssertEqual(harness.pipeline.testingLatestFrameEvidence?.sessionGeneration,
                       terminalSessionGeneration)
        XCTAssertEqual(harness.pipeline.testingLatestFrameEvidence?.lensGeneration,
                       terminalCaptureGeneration)

        await harness.viewModel.releaseAndWait()
    }

    func testProtectedProductionOwnerDecisionsRemainFailClosed() {
        let valid = CameraAdviceSafetyInput(
            lensGenerationKnown: true,
            subjectTrackLost: false,
            subjectAmbiguous: false,
            motionStateIsStill: true,
            exposureContradictionFree: true,
            refocusAdviceAdmitted: true,
            horizonAvailable: true,
            calibratedProbability: 0.9,
            minimumConfidence: CameraAdviceSafetyGate.defaultMinimumConfidence
        )

        XCTAssertEqual(
            CameraAdviceSafetyGate.evaluate(
                actionFamily: .composition,
                input: CameraAdviceSafetyInput(
                    lensGenerationKnown: true,
                    subjectTrackLost: nil,
                    subjectAmbiguous: false,
                    motionStateIsStill: true,
                    exposureContradictionFree: true,
                    refocusAdviceAdmitted: true,
                    horizonAvailable: true,
                    calibratedProbability: 0.9,
                    minimumConfidence: 0.5
                )
            ),
            .selectSubject(reason: .subjectAmbiguous)
        )
        XCTAssertEqual(
            CameraAdviceSafetyGate.evaluate(
                actionFamily: .composition,
                input: CameraAdviceSafetyInput(
                    lensGenerationKnown: true,
                    subjectTrackLost: true,
                    subjectAmbiguous: false,
                    motionStateIsStill: true,
                    exposureContradictionFree: true,
                    refocusAdviceAdmitted: true,
                    horizonAvailable: true,
                    calibratedProbability: 0.9,
                    minimumConfidence: 0.5
                )
            ),
            .abstain(reason: .subjectIdentityLost)
        )
        XCTAssertEqual(
            CameraAdviceSafetyGate.evaluate(
                actionFamily: .composition,
                input: CameraAdviceSafetyInput(
                    lensGenerationKnown: true,
                    subjectTrackLost: false,
                    subjectAmbiguous: false,
                    motionStateIsStill: false,
                    exposureContradictionFree: true,
                    refocusAdviceAdmitted: true,
                    horizonAvailable: true,
                    calibratedProbability: 0.9,
                    minimumConfidence: 0.5
                )
            ),
            .wait(reason: .motionNotStill)
        )
        XCTAssertEqual(
            CameraAdviceSafetyGate.evaluate(actionFamily: .composition, input: valid),
            .allow
        )
    }

    func testNeuralEvidenceMovementAndVerificationRemainProductionOwned() async {
        let neuralService = NeuralEvidenceInferenceService(
            configuration: makeNeuralConfiguration(),
            provider: ClosedLoopNeuralEvidenceProvider()
        )
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: neuralService,
            thermalGovernor: ThermalGovernor(
                thermalStateProvider: { .nominal },
                batteryLevelProvider: { 1.0 }
            ),
            neuralHeavyModelsEnabledProvider: { true },
            liveHybridFusionEnabled: true,
            demoLiveCoachEnabled: false
        )
        let frame = makeFrame(
            pipeline: pipeline,
            id: "owner-chain-neural",
            x: 0.86,
            seconds: 0,
            baseDate: Date(timeIntervalSinceNow: -1)
        )
        let semantics = SceneSemanticsAnalyzer().analyze(snapshot: frame.snapshot)

        let deterministicCritique = FrameCritiqueEngine().analyze(
            snapshot: frame.snapshot,
            semantics: semantics
        )
        let (fusionOutput, neuralOutcome) = await pipeline.testingResolveCritiqueWithHybridFusion(
            mode: .live,
            capturedAt: frame.date,
            pixelBuffer: frame.evidence.pixelBuffer,
            orientation: frame.evidence.orientation,
            snapshot: frame.snapshot,
            semantics: semantics,
            deterministicCritique: deterministicCritique,
            forcePauseExecution: false
        )
        XCTAssertEqual(
            neuralOutcome?.kind,
            .executed,
            "neural metadata failure=\(String(describing: neuralOutcome?.metadata?.failureReason))"
        )
        XCTAssertFalse(fusionOutput.appliedDecisions.isEmpty)
        XCTAssertEqual(pipeline.testingLatestLiveNeuralOutcome?.snapshot?.frameId, frame.snapshot.frameId)
        XCTAssertEqual(
            neuralOutcome?.snapshot?.validate(
                expectedFrameId: frame.snapshot.frameId,
                semanticsReport: semantics,
                runtimeMetadata: neuralOutcome?.metadata
            ) ?? ["missing neural snapshot"],
            []
        )

        let actionID = SemanticActionType.moveSubjectRight.rawValue
        let movementBase = Date(timeIntervalSinceNow: -10)
        let subjectFixtures: [(label: String,
                               configuration: CoachingEpisodeConfiguration,
                               movement: [Double],
                               stable: [Double],
                               expected: ActionVerificationOutcome)] = [
            ("improved", .init(), [0.26, 0.32], [0.32, 0.32], .improved),
            ("unchanged", .init(), [0.24, 0.28], [0.252, 0.224], .unchanged),
            // Each stable step stays inside the observer deadband. The
            // deliberately longer production dwell lets the subject drift
            // back across the frozen baseline, so the verifier—not the test—
            // classifies the immutable pair as worse.
            ("worse", .init(requiredMovementFrames: 2, requiredStableAfterFrames: 6), [0.60, 0.64], [0.611, 0.582, 0.553, 0.524, 0.495, 0.466], .worse)
        ]

        let notReadyCoordinator = CoachingEpisodeCoordinator()
        XCTAssertNil(notReadyCoordinator.verificationInput)
        for fixture in subjectFixtures {
            let before = makeVerificationFrame(
                id: "owner-\(fixture.label)-before",
                capturedAt: movementBase,
                actionID: actionID,
                x: fixture.label == "worse" ? 0.50 : 0.20
            )
            let movement = fixture.movement.enumerated().map { index, x in
                makeVerificationFrame(
                    id: "owner-\(fixture.label)-movement-\(index)",
                    capturedAt: movementBase.addingTimeInterval(Double(index + 1) * 0.10),
                    actionID: actionID,
                    x: x
                )
            }
            let stable = fixture.stable.enumerated().map { index, x in
                makeVerificationFrame(
                    id: "owner-\(fixture.label)-stable-\(index)",
                    capturedAt: movementBase.addingTimeInterval(Double(index + fixture.movement.count + 1) * 0.10),
                    actionID: actionID,
                    x: x
                )
            }

            guard let episode = productionEpisode(
                actionID: actionID,
                configuration: fixture.configuration,
                baseline: before,
                movement: movement,
                stable: stable
            ) else {
                return XCTFail("production episode could not accept \(fixture.label) fixture")
            }
            XCTAssertEqual(
                episode.state.phase,
                .readyForVerification,
                "\(fixture.label) phase=\(episode.state.phase.rawValue) movement=\(episode.state.movementFrames) stable=\(episode.state.stableAfterFrames) last=\(String(describing: episode.state.lastFrameID)) cancellation=\(String(describing: episode.state.cancellationReason))"
            )
            guard let input = episode.input else {
                return XCTFail("ready episode must hand its immutable pair to ActionVerifier: \(fixture.label)")
            }
            let result = ActionVerifier.verify(input)
            XCTAssertEqual(result.decision, .comparable(outcome: fixture.expected), fixture.label)
            XCTAssertEqual(result.beforeFrameID, before.frameID, fixture.label)
            XCTAssertEqual(result.afterFrameID, stable.last?.frameID, fixture.label)

            let routed = CameraOverlayUXPresentation.make(
                liveHint: makeOwnerChainLiveHint(frameID: input.after.frameID, label: fixture.label),
                context: CameraOverlayUXContext(
                    decision: .correct,
                    episodeState: episode.state,
                    verificationResult: result
                ),
                locale: Locale(identifier: "en")
            )
            // The verification surface routes outcomes through the production
            // presentation owner into the S10a/S10b verification states:
            // fixed/improved affirm the advice, unchanged/worse decline it.
            let expectedRoutedState: CameraOverlayUXPresentation.State =
                fixture.expected == .fixed || fixture.expected == .improved
                    ? .verificationImproved
                    : .verificationNotImproved
            XCTAssertEqual(
                routed.state,
                expectedRoutedState,
                "verification outcome must return through the production presentation owner: \(fixture.label)"
            )
        }

        let stabilityAction = TechnicalQualityActionType.stabilizeCamera.rawValue
        let stabilityBefore = makeVerificationFrame(
            id: "owner-fixed-before",
            capturedAt: movementBase,
            actionID: stabilityAction,
            bindSubject: false,
            metrics: UserMovementMetrics(stabilityScore: 0.20, shakeLevel: 0.80),
            still: false
        )
        let stabilityMovement = [0.40, 0.60].enumerated().map { index, score in
            makeVerificationFrame(
                id: "owner-fixed-movement-\(index)",
                capturedAt: movementBase.addingTimeInterval(Double(index + 1) * 0.10),
                actionID: stabilityAction,
                bindSubject: false,
                metrics: UserMovementMetrics(stabilityScore: score, shakeLevel: 1.0 - score),
                still: false
            )
        }
        let stabilityStable = [0.60, 0.60].enumerated().map { index, score in
            makeVerificationFrame(
                id: "owner-fixed-stable-\(index)",
                capturedAt: movementBase.addingTimeInterval(Double(index + 3) * 0.10),
                actionID: stabilityAction,
                bindSubject: false,
                metrics: UserMovementMetrics(stabilityScore: score, shakeLevel: 1.0 - score),
                still: true
            )
        }
        guard let fixedEpisode = productionEpisode(
            actionID: stabilityAction,
            configuration: .init(),
            baseline: stabilityBefore,
            movement: stabilityMovement,
            stable: stabilityStable
        ),
        let fixedInput = fixedEpisode.input else {
            return XCTFail("frame-global stability must also use the production episode handoff")
        }
        let fixedResult = ActionVerifier.verify(fixedInput)
        XCTAssertEqual(fixedResult.decision, .comparable(outcome: .fixed))
        let fixedPresentation = CameraOverlayUXPresentation.make(
            liveHint: makeOwnerChainLiveHint(frameID: fixedInput.after.frameID, label: "fixed"),
            context: CameraOverlayUXContext(
                decision: .correct,
                episodeState: fixedEpisode.state,
                verificationResult: fixedResult
            ),
            locale: Locale(identifier: "en")
        )
        XCTAssertEqual(fixedPresentation.state, .verificationImproved)

        // A missing subject binding cannot enter the coordinator and therefore
        // cannot reach ActionVerifier as a positive comparison.
        let broken = makeVerificationFrame(
            id: "owner-broken",
            capturedAt: movementBase,
            actionID: actionID,
            bindSubject: false
        )
        XCTAssertNil(
            makeEpisodeObservation(frame: broken, actionID: actionID),
            "a broken subject handoff must fail before the verifier"
        )
    }

    private struct ClosedLoopFrame {
        let snapshot: FrameFeatureSnapshot
        let evidence: LatestFrameEvidenceStore.Snapshot
        let date: Date
    }

    private struct CapturePathHarness {
        let manager: CameraManager
        let pipeline: AnalysisPipeline
        let viewModel: CameraViewModel
    }

    private final class CaptureVisionSequence {
        private let lock = NSLock()
        private var sampleIndex = 0

        func nextResult() -> VisionTrackingResult {
            lock.lock()
            sampleIndex += 1
            let index = sampleIndex
            lock.unlock()

            let subjectX: CGFloat
            switch index {
            case 1...10:
                subjectX = 0.60
            case 11:
                subjectX = 0.50
            default:
                subjectX = 0.40
            }
            return CameraCoachClosedLoopTests.captureVisionResult(subjectX: subjectX)
        }
    }

    private static let capturePreviewGeometry = CameraPreviewGeometry(
        destinationSize: CGSize(width: 390, height: 844),
        imageOrientation: .down,
        isMirrored: false
    )!

    private static let neutralLuma = [UInt8](repeating: 0, count: 16)

    private static let supportedCaptureLuma: [UInt8] = [
        48, 208, 48, 208,
        208, 48, 208, 48,
        48, 208, 48, 208,
        208, 48, 208, 48
    ]

    private nonisolated static func captureVisionResult(subjectX: CGFloat) -> VisionTrackingResult {
        VisionTrackingResult(
        subjects: [
            TrackedSubject(
                boundingBox: CGRect(x: subjectX, y: 0.20, width: 0.40, height: 0.40),
                confidence: 1.0,
                isFace: true
            )
        ],
        saliencyCenter: CGPoint(x: subjectX + 0.20, y: 0.50),
        saliencyRegion: CGRect(x: subjectX, y: 0.20, width: 0.40, height: 0.40),
        faceCount: 1,
        personCount: 1
        )
    }

    private static let supportedCaptureVisionResult = captureVisionResult(subjectX: 0.60)

    private static let emptyCaptureVisionResult = VisionTrackingResult(
        subjects: [],
        saliencyCenter: nil,
        saliencyRegion: nil,
        faceCount: 0,
        personCount: 0
    )

    private func makeCapturePathHarness(
        visionResult: @escaping (CVPixelBuffer, CGImagePropertyOrientation) -> VisionTrackingResult,
        neuralEnabled: Bool,
        episodeConfidenceCalibrator: CameraConfidenceCalibrator = .unavailable
    ) -> CapturePathHarness {
        let thermal = ThermalGovernor(
            thermalStateProvider: { .nominal },
            batteryLevelProvider: { 1.0 }
        )
        let manager = CameraManager(
            scheduler: RealtimeScheduler(),
            thermalGovernor: thermal,
            motionGate: MotionGate(startMotionUpdates: false),
            sessionRunner: ClosedLoopSessionRunner(),
            configuration: .ready,
            notificationCenter: NotificationCenter()
        )
        let neuralService: NeuralEvidenceInferenceService? = neuralEnabled
            ? NeuralEvidenceInferenceService(
                configuration: makeNeuralConfiguration(),
                provider: ClosedLoopNeuralEvidenceProvider()
            )
            : nil
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: neuralService,
            episodeConfidenceCalibrator: episodeConfidenceCalibrator,
            thermalGovernor: thermal,
            neuralHeavyModelsEnabledProvider: { true },
            liveHybridFusionEnabled: neuralEnabled,
            demoLiveCoachEnabled: false,
            visionResultProviderForTesting: visionResult
        )
        let viewModel = CameraViewModel(cameraManager: manager, analysisPipeline: pipeline)
        return CapturePathHarness(manager: manager, pipeline: pipeline, viewModel: viewModel)
    }

    private func deliverCaptureSample(
        through harness: CapturePathHarness,
        timestamp: CMTime,
        lumaValues: [UInt8]
    ) async throws {
        let output = AVCaptureVideoDataOutput()
        let connection = AVCaptureConnection(inputPorts: [], output: output)
        let sampleBuffer = try makeVideoSampleBuffer(
            pixelBuffer: makePixelBuffer(lumaValues: lumaValues),
            timestamp: timestamp
        )
        harness.manager.captureOutput(output, didOutput: sampleBuffer, from: connection)
        await harness.manager.drainSchedulerAndWait()
        await harness.pipeline.testingDrainHighQueue()
        // RealtimeScheduler retains the production thermal budget's nominal
        // high-priority cadence (6 Hz in this fixture). Leave one full
        // interval before the next synthetic callback so every sample
        // exercises the real scheduler dispatch rather than a direct
        // pipeline ingest seam.
        try? await Task.sleep(nanoseconds: 180_000_000)
    }

    private func makeVideoSampleBuffer(
        pixelBuffer: CVPixelBuffer,
        timestamp: CMTime
    ) throws -> CMSampleBuffer {
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: timestamp,
            decodeTimeStamp: .invalid
        )
        var formatDescription: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            throw NSError(domain: "CameraCoachClosedLoopTests", code: Int(formatStatus))
        }
        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else {
            throw NSError(domain: "CameraCoachClosedLoopTests", code: Int(status))
        }
        return sampleBuffer
    }

    private func makeNoActionPlan(frameId: String) -> RecommendationPlan {
        RecommendationPlan(
            frameId: frameId,
            mode: .live,
            inputVerdict: .good,
            primaryAction: nil,
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: "demo admission regression",
            planConfidence: 0.90
        )
    }

    private func makeProductionDemoSemantics(
        frameId: String,
        kind: SubjectKind,
        region: NormalizedRect,
        hasClearFocus: Bool
    ) -> SceneSemanticsReport {
        SceneSemanticsReport(
            frameId: frameId,
            mode: .live,
            sceneType: kind == .object ? .objectInsert : .singleCharacterMedium,
            sceneTypeConfidence: 0.82,
            primarySubject: .init(
                kind: kind,
                region: region,
                confidence: 0.90
            ),
            dominance: .init(
                hasClearFocus: hasClearFocus,
                focusCompetitionScore: hasClearFocus ? 0.18 : 0.70,
                backgroundClutterScore: hasClearFocus ? 0.22 : 0.72
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

    private func makeFrame(
        pipeline: AnalysisPipeline,
        id: String,
        x: Double,
        seconds: TimeInterval,
        baseDate: Date? = nil,
        lumaValues: [UInt8]? = nil,
        visionEnabled: Bool = true,
        detrDetections: [FeatureSnapshotDetectedObject] = [],
        backlightIndex: Double = 0.10
    ) -> ClosedLoopFrame {
        let date = (baseDate ?? Date(timeIntervalSince1970: 1_771_111_100)).addingTimeInterval(seconds)
        let orientation: CGImagePropertyOrientation = .right
        // The subject remains a compact, edge-adjacent portrait detection;
        // the neural fixture supplies the additional high-confidence
        // composition evidence needed for the visible corrective marker.
        let region = CGRect(x: x, y: 0.20, width: 0.20, height: 0.40)
        var features = CoachingFeatures()
        features.subject.isFace = true
        features.subject.isPerson = true
        features.subject.count = 1
        features.composition.horizontalOffset = 0.6
        features.composition.subjectAreaRatio = 0.08
        features.motion.state = .still
        features.motion.shakeLevel = 0.02

        let provenance = FeatureSampleProvenance(
            frameID: id,
            captureGeneration: 1,
            orientation: orientation
        )
        let vision: FeatureSample<FeatureSnapshotVisionPayload>? = visionEnabled
            ? FeatureSample(
                value: FeatureSnapshotVisionPayload(
                    subjects: [
                        FeatureSnapshotVisionSubject(
                            boundingBox: region,
                            confidence: 0.94,
                            isFace: true
                        )
                    ],
                    saliencyCenter: CGPoint(x: 0.92, y: 0.42),
                    faceCount: 1,
                    personCount: 1
                ),
                measuredAt: date,
                baseConfidence: 0.94,
                provenance: provenance
            )
            : nil
        let detr: FeatureSample<FeatureSnapshotDetrPayload>? = detrDetections.isEmpty
            ? nil
            : FeatureSample(
                value: FeatureSnapshotDetrPayload(detections: detrDetections),
                measuredAt: date,
                baseConfidence: detrDetections.map(\.confidence).max() ?? 0,
                provenance: provenance
            )
        let horizon = FeatureSample(
            value: FeatureSnapshotHorizonPayload(angleDegrees: 0.2, confidence: 0.86),
            measuredAt: date,
            baseConfidence: 0.86,
            provenance: provenance
        )
        let lighting = FeatureSample(
            value: FeatureSnapshotLightingPayload(
                exposureBiasHint: 0.0,
                backlightIndex: backlightIndex,
                keyToFillRatio: 0.85
            ),
            measuredAt: date,
            baseConfidence: 0.80,
            provenance: provenance
        )
        let aesthetic = FeatureSample(
            value: FeatureSnapshotAestheticPayload(score10: 8.0),
            measuredAt: date,
            baseConfidence: 0.80,
            provenance: provenance
        )
        let state = PipelineFeatureSnapshotAdapterState(
            features: features,
            debugData: DebugData(),
            vision: vision,
            horizonMeasuredAt: date,
            horizon: horizon,
            lightingMeasuredAt: date,
            lighting: lighting,
            detr: detr,
            aestheticMeasuredAt: date,
            aesthetic: aesthetic
        )
        let snapshot = pipeline.testingMakeFeatureSnapshot(
            mode: .live,
            frameId: id,
            capturedAt: date,
            adapterState: state
        )
        let evidence = LatestFrameEvidenceStore.Snapshot(
            pixelBuffer: lumaValues.map { makePixelBuffer(lumaValues: $0) } ?? makePixelBuffer(),
            orientation: orientation,
            sourceFrameId: id,
            capturedAt: date,
            isStable: true,
            lensID: CameraLens.wide.rawValue,
            previewGeometry: CameraPreviewGeometry(
                destinationSize: CGSize(width: 390, height: 844),
                imageOrientation: orientation,
                isMirrored: false
            ),
            adapterState: state,
            lensGeneration: 1
        )!
        return ClosedLoopFrame(snapshot: snapshot, evidence: evidence, date: date)
    }

    private func critiqueFor(_ snapshot: FrameFeatureSnapshot) -> CritiqueReport {
        let semantics = SceneSemanticsAnalyzer().analyze(snapshot: snapshot)
        return FrameCritiqueEngine().analyze(snapshot: snapshot, semantics: semantics)
    }

    private func makePixelBuffer() -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            16,
            16,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary,
            &buffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        if let buffer {
            XCTAssertEqual(CVPixelBufferLockBaseAddress(buffer, []), kCVReturnSuccess)
            if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
                memset(baseAddress, 0, CVPixelBufferGetDataSize(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
        }
        return buffer!
    }

    private func makePixelBuffer(lumaValues: [UInt8]) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            16,
            16,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary,
            &buffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        XCTAssertEqual(lumaValues.count, 16)
        guard let buffer else { return makePixelBuffer() }

        XCTAssertEqual(CVPixelBufferLockBaseAddress(buffer, []), kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            XCTFail("BGRA fixture must expose a base address")
            return buffer
        }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        for row in 0..<16 {
            for column in 0..<16 {
                let luma = lumaValues[(row / 4) * 4 + (column / 4)]
                let offset = row * rowBytes + column * 4
                bytes[offset] = luma
                bytes[offset + 1] = luma
                bytes[offset + 2] = luma
                bytes[offset + 3] = 255
            }
        }
        return buffer
    }

    private func makeNeuralConfiguration() -> NeuralEvidenceInferenceConfiguration {
        var configuration = NeuralEvidenceInferenceConfiguration.disabled
        configuration.featureEnabled = true
        configuration.liveModeEnabled = true
        configuration.pauseModeEnabled = true
        // The closed-loop fixture uses an explicit sub-250 ms capture cadence
        // for spatial confirmation. Remove only the wall-clock cadence gate so
        // every baseline input proves a fresh neural -> fusion -> planner
        // handoff; production retains its normal live cadence.
        configuration.liveMinIntervalUnrestricted = 0
        configuration.liveMinIntervalConstrained = 0
        return configuration
    }

    private func productionEpisode(
        actionID: String,
        configuration: CoachingEpisodeConfiguration,
        baseline: UserMovementFrame,
        movement: [UserMovementFrame],
        stable: [UserMovementFrame]
    ) -> (state: CoachingEpisodeState, input: ActionVerificationInput?)? {
        guard let baselineObservation = makeEpisodeObservation(
            frame: baseline,
            actionID: actionID
        ) else {
            XCTFail("production baseline observation was rejected for (actionID)")
            return nil
        }

        var coordinator = CoachingEpisodeCoordinator(configuration: configuration)
        guard coordinator.consume(.baseline(baselineObservation)).phase == .awaitingMovement else {
            XCTFail("production episode did not enter awaiting_movement for (actionID)")
            return nil
        }

        for frame in movement + stable {
            guard let frameEvidence = makeEpisodeFrameEvidence(frame: frame) else {
                XCTFail("production frame handoff was rejected for (frame.frameID)")
                return nil
            }
            coordinator.consume(.frame(frameEvidence))
        }
        return (coordinator.state, coordinator.verificationInput)
    }

    private func makeEpisodeObservation(
        frame: UserMovementFrame,
        actionID: String,
        sceneSignature: String = "owner-chain-scene"
    ) -> CoachingEpisodeObservation? {
        guard let evidence = frame.evidence,
              let family = UserMovementObserver.actionFamily(for: actionID) else {
            return nil
        }
        let lifecycle = SubjectTrackLifecycleContext(
            generation: evidence.lensGeneration,
            orientation: .portrait,
            lensID: "wide",
            routeActive: true,
            isAppBackgrounded: false,
            sceneSignature: sceneSignature
        )
        let track = makeEpisodeTrack(for: frame)
        let advice = StabilizedAdvice(
            decision: .correct,
            actionID: actionID,
            frameID: frame.frameID,
            targetX: frame.subjectRegion.map { $0.x + ($0.width / 2) },
            targetY: frame.subjectRegion.map { $0.y + ($0.height / 2) },
            targetIdentity: family.requiresSubjectBinding ? track?.identity : nil
        )
        return CoachingEpisodeObservation(
            frame: frame,
            stabilizedAdvice: advice,
            subjectTrack: family.requiresSubjectBinding ? track : nil,
            lifecycle: lifecycle,
            isStable: frame.motionIsStill,
            geometryContext: makeVerificationGeometry(frameID: frame.frameID),
            exposureState: family == .lightExposure ? .stable : nil
        )
    }

    private func makeEpisodeFrameEvidence(
        frame: UserMovementFrame,
        sceneSignature: String = "owner-chain-scene"
    ) -> CoachingEpisodeFrameEvidence? {
        guard let evidence = frame.evidence else { return nil }
        let lifecycle = SubjectTrackLifecycleContext(
            generation: evidence.lensGeneration,
            orientation: .portrait,
            lensID: "wide",
            routeActive: true,
            isAppBackgrounded: false,
            sceneSignature: sceneSignature
        )
        return CoachingEpisodeFrameEvidence(
            frame: frame,
            subjectTrack: makeEpisodeTrack(for: frame),
            lifecycle: lifecycle,
            isStable: frame.motionIsStill,
            currentActionID: nil,
            geometryContext: makeVerificationGeometry(frameID: frame.frameID)
        )
    }

    private func makeEpisodeTrack(for frame: UserMovementFrame) -> SubjectTrackState? {
        guard let binding = frame.evidence?.subjectBinding,
              frame.subjectRegion != nil else {
            return nil
        }
        return SubjectTrackState(
            identity: binding.identity,
            phase: .active,
            lastRegion: binding.region,
            lastSeenFrameID: frame.frameID,
            lostSinceFrameID: nil,
            missedFrames: 0,
            reconciliations: 0,
            redetectionDue: false
        )
    }

    private func makeOwnerChainLiveHint(frameID: String, label: String) -> LiveHintPresentation {
        let actionType = ActionTypeV1.moveFrameRight
        let actionID = "owner-route-action-(label)"
        let issueID = "owner-route-issue-(label)"
        let projection = CameraLinkedEvidenceProjection(
            frameID: frameID,
            actionID: actionID,
            actionType: actionType,
            semanticActionType: actionType.semanticActionType,
            issueID: issueID,
            issueType: .subjectTooCloseToEdge,
            evidence: [
                EvidenceRef(source: .snapshot, key: "subject.edge", value: "observed")
            ]
        )
        return LiveHintPresentation(
            id: "owner-route-hint-(label)",
            frameId: frameID,
            text: "The subject is close to the edge.",
            confidence: 0.9,
            actionType: actionType,
            actionId: actionID,
            linkedIssueIds: [issueID],
            summaryId: nil,
            traceRootIds: [],
            targetRegion: NormalizedRect(x: 0.24, y: 0.25, width: 0.20, height: 0.40),
            overlayHint: OverlayHint(
                id: "owner-route-overlay-(label)",
                kind: .arrow,
                targetRegion: NormalizedRect(x: 0.24, y: 0.25, width: 0.20, height: 0.40),
                direction: .right
            ),
            isFallback: false,
            expandedVerdict: LiveExpandedVerdictPresentation(
                shortVerdict: "The subject is close to the edge.",
                supportingText: nil,
                actionText: "Move the subject right.",
                fallbackUsed: false
            ),
            semanticActionType: actionType.semanticActionType,
            linkedEvidence: projection
        )
    }

    private func makeVerificationGeometry(frameID: String) -> ActionVerificationGeometryContext {
        ActionVerificationGeometryContext(
            frameID: frameID,
            displayTransform: CameraDisplayTransform(
                orientation: .portrait,
                isMirrored: false
            ),
            aspectFillTransform: AspectFillTransform(
                sourceSize: CGSize(width: 1920, height: 1080),
                destinationSize: CGSize(width: 390, height: 844)
            )
        )
    }

    private func makeVerificationFrame(
        id: String,
        capturedAt: Date,
        actionID: String,
        x: Double = 0.20,
        bindSubject: Bool? = nil,
        metrics: UserMovementMetrics = UserMovementMetrics(),
        still: Bool = true,
        generation: UInt64 = 11
    ) -> UserMovementFrame {
        let needsSubject = UserMovementObserver.actionFamily(for: actionID)?.requiresSubjectBinding == true
        let shouldBind = bindSubject ?? needsSubject
        let region = NormalizedRect(x: x, y: 0.25, width: 0.20, height: 0.40)
        let identity = SubjectTrackIdentity(
            trackID: "owner-chain-subject",
            firstSeenFrameID: "owner-before",
            generation: generation
        )
        let binding = shouldBind
            ? UserMovementSubjectBinding(
                identity: identity,
                frameID: id,
                region: region,
                source: .vision,
                coordinateSpace: .subjectTarget,
                measuredAt: capturedAt,
                confidence: 0.92
            )
            : nil
        let evidence = UserMovementEvidence(
            capturedAt: capturedAt,
            evaluatedAt: capturedAt,
            lensGeneration: generation,
            subjectTrackID: binding?.identity.trackID,
            subjectBinding: binding,
            orientation: .portrait,
            isCalibrated: true,
            calibrationVersion: "owner-chain-v1",
            featureMeasuredAt: Dictionary(uniqueKeysWithValues: UserMovementActionFamily.allCases.map { ($0, capturedAt) }),
            featureConfidence: Dictionary(uniqueKeysWithValues: UserMovementActionFamily.allCases.map { ($0, 0.92) }),
            sourceAvailability: Dictionary(uniqueKeysWithValues: UserMovementActionFamily.allCases.map { ($0, true) })
        )
        return UserMovementFrame(
            frameID: id,
            subjectRegion: shouldBind ? region : nil,
            meanLuma: 0.5,
            motionIsStill: still,
            metrics: metrics,
            evidence: evidence
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @escaping () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return true }
            do {
                try await Task.sleep(nanoseconds: 1_000_000)
            } catch {
                return false
            }
        }
        return condition()
    }
}

private final class ClosedLoopSessionRunner: CameraSessionRunner {
    private(set) var isRunning = false

    func startRunning() {
        isRunning = true
    }

    func stopRunning() {
        isRunning = false
    }
}

private final class ClosedLoopNeuralEvidenceProvider: NeuralEvidenceProvider {
    let descriptor = NeuralEvidenceProviderDescriptor(
        providerKind: .mock,
        inferenceTarget: .onDevice,
        modelFamily: "closed_loop_neural_evidence",
        modelVersion: "test.v1",
        preprocessingVersion: "prep.test",
        thresholdProfileLive: "closed_loop_live_v1",
        thresholdProfilePause: "closed_loop_pause_v1",
        bundleVersion: "closed_loop.bundle.v1"
    )

    func prepareIfNeeded() async throws {}

    func infer(request: NeuralEvidenceProviderRequest) async throws -> NeuralEvidenceProviderOutput {
        let supportingRow = Array(repeating: 0.72, count: NeuralEvidenceProviderOutput.supportingSignalCount)
        return NeuralEvidenceProviderOutput(
            // Keep subject prominence high while making the model's
            // face-saliency and balance heads independently support the
            // deterministic edge-pressure finding. These are deliberately
            // high-confidence outputs so the real hybrid fusion owner, not a
            // test-only hint, admits the corrective action.
            scalarScores: [0.90, 0.34, 0.66, 0.00, 0.10, 0.57, 0.54],
            scalarConfidences: [0.94, 0.78, 0.74, 0.96, 0.96, 0.67, 0.61],
            supportingSignalScores: Array(
                repeating: supportingRow,
                count: NeuralEvidenceProviderOutput.scalarHeadCount
            ),
            shotTypeAffinities: [0.74, 0.28, 0.19, 0.12, 0.09, 0.22, 0.18],
            shotTypeConfidence: 0.63,
            actualROIStrategy: request.roiStrategy
        )
    }
}
