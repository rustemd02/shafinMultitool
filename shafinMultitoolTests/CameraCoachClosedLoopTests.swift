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

            pipeline.testingPublishLivePresentation(
                frameId: frame.snapshot.frameId,
                snapshot: frame.snapshot,
                critique: fusionOutput.critique,
                plan: plan,
                semantics: frameSemantics,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: frame.date
            )
            pipeline.testingPublishLiveCoachingEpisodeObservation(
                snapshot: frame.snapshot,
                semantics: frameSemantics,
                plan: plan,
                frameEvidence: frame.evidence,
                evaluatedAt: frame.date
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
        XCTAssertEqual(
            viewModel.coachingEpisodeState.baseline?.actionID,
            SemanticActionType.shiftFrameRight.rawValue
        )
        XCTAssertEqual(viewModel.coachingEpisodeState.baseline?.lensID, CameraLens.wide.rawValue)

        let noActionPlan: (ClosedLoopFrame) -> RecommendationPlan = { frame in
            RecommendationPlan(
                frameId: frame.snapshot.frameId,
                mode: .live,
                inputVerdict: .good,
                primaryAction: nil,
                secondaryActions: [],
                deferredActions: [],
                noChangeRationale: "The frozen production action is being verified.",
                planConfidence: 0.86
            )
        }
        for (id, x, seconds, expectedPhase) in [
            // Vision evidence has a 250 ms freshness window. Keep adjacent
            // fixture frames inside that production cadence; a one-second
            // jump would legitimately make the frozen baseline stale when
            // the coordinator evaluates it at the current frame's `asOf`.
            ("closed-loop-movement-1", 0.76, 1.20, CoachingEpisodePhase.awaitingMovement),
            ("closed-loop-movement-2", 0.72, 1.24, CoachingEpisodePhase.collectingStableAfterFrames),
            ("closed-loop-stable-1", 0.72, 1.28, CoachingEpisodePhase.collectingStableAfterFrames),
            ("closed-loop-stable-2", 0.72, 1.32, CoachingEpisodePhase.readyForVerification)
        ] {
            let frame = makeFrame(pipeline: pipeline, id: id, x: x, seconds: seconds)
            let frameSemantics = SceneSemanticsAnalyzer().analyze(snapshot: frame.snapshot)
            pipeline.testingPublishLiveCoachingEpisodeObservation(
                snapshot: frame.snapshot,
                semantics: frameSemantics,
                plan: noActionPlan(frame),
                frameEvidence: frame.evidence,
                evaluatedAt: frame.date
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
        XCTAssertTrue(viewModel.applyVerificationResult(verification))
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
            .stableTip,
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

        await viewModel.releaseAndWait()
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

    func testProductionSceneCutFlowsThroughViewModelAndRetriesWithinSameCapture() async {
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
            pipeline.testingPublishLivePresentation(
                frameId: frame.snapshot.frameId,
                snapshot: frame.snapshot,
                critique: fusionOutput.critique,
                plan: plan,
                semantics: semantics,
                legacySuggestion: nil,
                structuredAvailable: true,
                now: frame.date
            )
            pipeline.testingPublishLiveCoachingEpisodeObservation(
                snapshot: frame.snapshot,
                semantics: semantics,
                plan: plan,
                frameEvidence: frame.evidence,
                evaluatedAt: frame.date
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
        XCTAssertTrue(baselineAccepted)
        guard case let .baseline(baselineObservation) = pipeline.currentCoachingEpisodeEvent else {
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
        XCTAssertTrue(sceneCutConsumed)

        let terminalState = viewModel.coachingEpisodeState
        let staleFrame = makeFrame(
            pipeline: pipeline,
            id: "production-scene-late-pre-cut",
            x: 0.80,
            seconds: 0.05,
            baseDate: baseDate,
            lumaValues: baseLuma
        )
        guard let staleEvidence = makeProductionFrameEvidence(
            frame: staleFrame,
            baseline: baselineObservation
        ) else {
            return XCTFail("the late pre-cut fixture must form valid production frame evidence")
        }
        pipeline.publishCoachingEpisodeEvent(.frame(staleEvidence))
        guard case let .frame(publishedStaleEvidence) = pipeline.currentCoachingEpisodeEvent else {
            return XCTFail("pipeline must publish the late pre-cut frame through its typed stream")
        }
        XCTAssertEqual(publishedStaleEvidence.frame.frameID, staleFrame.snapshot.frameId)
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
                && viewModel.coachingEpisodeState.baseline?.frameID == freshBaselineFrames[2].snapshot.frameId
        }
        XCTAssertTrue(retryAccepted)
        XCTAssertNotEqual(viewModel.coachingEpisodeState.token, firstToken)
        XCTAssertEqual(viewModel.coachingEpisodeState.cancellationReason, nil)

        await viewModel.releaseAndWait()
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
            XCTAssertEqual(
                routed.state,
                fixture.expected == .fixed ? .keepAsIs : .stableTip,
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
        XCTAssertEqual(fixedPresentation.state, .keepAsIs)

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

    private func makeFrame(
        pipeline: AnalysisPipeline,
        id: String,
        x: Double,
        seconds: TimeInterval,
        baseDate: Date? = nil,
        lumaValues: [UInt8]? = nil
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
        let vision = FeatureSample(
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
        let horizon = FeatureSample(
            value: FeatureSnapshotHorizonPayload(angleDegrees: 0.2, confidence: 0.86),
            measuredAt: date,
            baseConfidence: 0.86,
            provenance: provenance
        )
        let lighting = FeatureSample(
            value: FeatureSnapshotLightingPayload(
                exposureBiasHint: 0.0,
                backlightIndex: 0.10,
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
            detr: nil,
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

    private func makeProductionFrameEvidence(
        frame: ClosedLoopFrame,
        baseline: CoachingEpisodeObservation
    ) -> CoachingEpisodeFrameEvidence? {
        guard let baselineBinding = baseline.frame.evidence?.subjectBinding,
              let source = frame.snapshot.subjectSignals.primaryCandidateSource,
              let region = frame.snapshot.subjectSignals.primaryCandidateRegion,
              let measuredAt = frame.evidence.featureSourceTimestamps[source],
              let binding = UserMovementSubjectBinding(
                  identity: baselineBinding.identity,
                  frameID: frame.snapshot.frameId,
                  region: region,
                  source: source,
                  coordinateSpace: .vision,
                  measuredAt: measuredAt,
                  confidence: frame.snapshot.subjectSignals.primaryCandidateConfidence ?? 0
              ),
              let userFrame = UserMovementFrame(
                  snapshot: frame.snapshot,
                  envelope: frame.evidence.makeEnvelope(),
                  subjectBinding: binding,
                  evaluatedAt: frame.date,
                  isCalibrated: true,
                  calibrationVersion: "bounded-plan-v1",
                  orientation: .portrait
              ) else {
            return nil
        }

        let lifecycle = SubjectTrackLifecycleContext(
            generation: frame.evidence.lensGeneration,
            orientation: .portrait,
            lensID: frame.evidence.lensID,
            routeActive: true,
            isAppBackgrounded: false,
            sceneSignature: baseline.lifecycle.sceneSignature
        )
        let subjectTrack = SubjectTrackState(
            identity: baselineBinding.identity,
            phase: .active,
            lastRegion: binding.region,
            lastSeenFrameID: frame.snapshot.frameId,
            lostSinceFrameID: nil,
            missedFrames: 0,
            reconciliations: 0,
            redetectionDue: false
        )
        return CoachingEpisodeFrameEvidence(
            frame: userFrame,
            subjectTrack: subjectTrack,
            lifecycle: lifecycle,
            isStable: frame.evidence.isStable,
            currentActionID: baseline.stabilizedAdvice.actionID,
            geometryContext: makeVerificationGeometry(frameID: frame.snapshot.frameId)
        )
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
            targetY: frame.subjectRegion.map { $0.y + ($0.height / 2) }
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
        still: Bool = true
    ) -> UserMovementFrame {
        let generation: UInt64 = 11
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
