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
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil,
            thermalGovernor: thermal,
            neuralHeavyModelsEnabledProvider: { true },
            liveHybridFusionEnabled: false,
            demoLiveCoachEnabled: false
        )
        let viewModel = CameraViewModel(cameraManager: manager, analysisPipeline: pipeline)
        defer {
            Task { @MainActor in
                await viewModel.releaseAndWait()
            }
        }

        await viewModel.startAndWait()

        let baseline = makeFrame(pipeline: pipeline, id: "closed-loop-0", x: 0.86, seconds: 1)
        let semantics = SceneSemanticsAnalyzer().analyze(snapshot: baseline.snapshot)
        XCTAssertEqual(semantics.primarySubject.kind, .face)
        XCTAssertEqual(baseline.snapshot.subjectSignals.primaryCandidateSource, .vision)

        let critique = FrameCritiqueEngine().analyze(snapshot: baseline.snapshot, semantics: semantics)
        let plan = RecommendationPlanner().makePlan(snapshot: baseline.snapshot, critique: critique)
        XCTAssertNotNil(
            plan.primaryAction,
            "verdict=\(critique.verdict) issueCount=\(critique.issues.count) rawEdge=\(FrameCritiqueEngine().rawIssueScoreForTesting(type: .subjectTooCloseToEdge, snapshot: baseline.snapshot, semantics: semantics) ?? -1) horizontal=\(baseline.snapshot.composition.horizontalOffset) edge=\(semantics.readability.edgePressureScore) readable=\(semantics.readability.subjectReadable)"
        )
        XCTAssertEqual(plan.primaryAction?.actionType, .moveFrameRight)

        for index in 0..<3 {
            let frame = makeFrame(
                pipeline: pipeline,
                id: "closed-loop-\(index)",
                x: 0.86,
                seconds: Double(index + 1)
            )
            pipeline.testingPublishLivePresentation(
                frameId: frame.snapshot.frameId,
                snapshot: frame.snapshot,
                critique: critiqueFor(frame.snapshot),
                plan: RecommendationPlanner().makePlan(
                    snapshot: frame.snapshot,
                    critique: critiqueFor(frame.snapshot)
                ),
                semantics: SceneSemanticsAnalyzer().analyze(snapshot: frame.snapshot),
                legacySuggestion: nil,
                structuredAvailable: true,
                now: frame.date
            )
            pipeline.testingPublishLiveCoachingEpisodeObservation(
                snapshot: frame.snapshot,
                semantics: SceneSemanticsAnalyzer().analyze(snapshot: frame.snapshot),
                plan: RecommendationPlanner().makePlan(
                    snapshot: frame.snapshot,
                    critique: critiqueFor(frame.snapshot)
                ),
                frameEvidence: frame.evidence,
                evaluatedAt: frame.date
            )
            await Task.yield()
        }

        let baselinePublished = await waitUntil {
            viewModel.coachingEpisodeState.phase == .awaitingMovement
        }
        XCTAssertTrue(baselinePublished)
        XCTAssertNotNil(viewModel.coachingEpisodeState.token)
        XCTAssertNotNil(viewModel.coachingEpisodeState.baseline?.subjectIdentity)
        XCTAssertEqual(viewModel.coachingEpisodeState.baseline?.actionID, SemanticActionType.shiftFrameRight.rawValue)

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
            liveHybridFusionEnabled: false,
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

        let neuralOutcome = await pipeline.testingRunNeuralEvidenceInference(
            mode: .live,
            pixelBuffer: makePixelBuffer(),
            orientation: .right,
            snapshot: frame.snapshot,
            semantics: semantics,
            isStable: true,
            thermalTier: .unrestricted,
            heavyModelsEnabled: true,
            batteryLevel: 1.0
        )
        XCTAssertEqual(neuralOutcome?.kind, .executed)
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
        let before = makeVerificationFrame(
            id: "owner-before",
            capturedAt: movementBase,
            actionID: actionID,
            x: 0.20
        )
        let improvedAfter = makeVerificationFrame(
            id: "owner-improved",
            capturedAt: movementBase.addingTimeInterval(0.01),
            actionID: actionID,
            x: 0.28
        )
        let unchangedAfter = makeVerificationFrame(
            id: "owner-unchanged",
            capturedAt: movementBase.addingTimeInterval(0.02),
            actionID: actionID,
            x: 0.21
        )
        let worseAfter = makeVerificationFrame(
            id: "owner-worse",
            capturedAt: movementBase.addingTimeInterval(0.03),
            actionID: actionID,
            x: 0.10
        )

        XCTAssertEqual(
            UserMovementObserver.observe(
                previous: before,
                current: improvedAfter,
                actionID: actionID,
                asOf: improvedAfter.evidence!.evaluatedAt
            ),
            .relevant
        )
        XCTAssertEqual(
            UserMovementObserver.observe(
                previous: before,
                current: unchangedAfter,
                actionID: actionID,
                asOf: unchangedAfter.evidence!.evaluatedAt
            ),
            .noOp
        )
        XCTAssertEqual(
            UserMovementObserver.observe(
                previous: before,
                current: worseAfter,
                actionID: actionID,
                asOf: worseAfter.evidence!.evaluatedAt
            ),
            .opposite
        )
        XCTAssertEqual(
            ActionVerifier.verify(makeVerificationInput(actionID: actionID, before: before, after: improvedAfter)).decision,
            .comparable(outcome: .improved)
        )
        XCTAssertEqual(
            ActionVerifier.verify(makeVerificationInput(actionID: actionID, before: before, after: unchangedAfter)).decision,
            .comparable(outcome: .unchanged)
        )
        XCTAssertEqual(
            ActionVerifier.verify(makeVerificationInput(actionID: actionID, before: before, after: worseAfter)).decision,
            .comparable(outcome: .worse)
        )

        let stabilityAction = TechnicalQualityActionType.stabilizeCamera.rawValue
        let stabilityBefore = makeVerificationFrame(
            id: "owner-stability-before",
            capturedAt: movementBase.addingTimeInterval(0.04),
            actionID: stabilityAction,
            bindSubject: false,
            metrics: UserMovementMetrics(stabilityScore: 0.20, shakeLevel: 0.80),
            still: false
        )
        let stabilityAfter = makeVerificationFrame(
            id: "owner-stability-after",
            capturedAt: movementBase.addingTimeInterval(0.05),
            actionID: stabilityAction,
            bindSubject: false,
            metrics: UserMovementMetrics(stabilityScore: 0.80, shakeLevel: 0.20),
            still: true
        )
        XCTAssertEqual(
            ActionVerifier.verify(makeVerificationInput(
                actionID: stabilityAction,
                before: stabilityBefore,
                after: stabilityAfter
            )).decision,
            .comparable(outcome: .fixed)
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
        baseDate: Date? = nil
    ) -> ClosedLoopFrame {
        let date = (baseDate ?? Date(timeIntervalSince1970: 1_800_000_000)).addingTimeInterval(seconds)
        let orientation: CGImagePropertyOrientation = .right
        let region = CGRect(x: x, y: 0.24, width: 0.12, height: 0.36)
        var features = CoachingFeatures()
        features.subject.isFace = true
        features.subject.isPerson = true
        features.subject.count = 1
        features.composition.horizontalOffset = 0.6
        features.composition.subjectAreaRatio = 0.0576
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
            pixelBuffer: makePixelBuffer(),
            orientation: orientation,
            sourceFrameId: id,
            capturedAt: date,
            isStable: true,
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
        return buffer!
    }

    private func makeNeuralConfiguration() -> NeuralEvidenceInferenceConfiguration {
        var configuration = NeuralEvidenceInferenceConfiguration.disabled
        configuration.featureEnabled = true
        configuration.liveModeEnabled = true
        configuration.pauseModeEnabled = true
        return configuration
    }

    private func makeVerificationInput(
        actionID: String,
        before: UserMovementFrame,
        after: UserMovementFrame
    ) -> ActionVerificationInput {
        let generation: UInt64 = 11
        let lifecycle = SubjectTrackLifecycleContext(
            generation: generation,
            orientation: .portrait,
            lensID: "wide",
            routeActive: true,
            isAppBackgrounded: false,
            sceneSignature: "owner-chain-scene"
        )
        let family = UserMovementObserver.actionFamily(for: actionID)
        let identity = before.evidence?.subjectBinding?.identity
        let beforeGeometry: ActionVerificationGeometryContext?
        let afterGeometry: ActionVerificationGeometryContext?
        if family?.requiresSubjectBinding == true {
            beforeGeometry = makeVerificationGeometry(frameID: before.frameID)
            afterGeometry = makeVerificationGeometry(frameID: after.frameID)
        } else {
            beforeGeometry = nil
            afterGeometry = nil
        }
        return ActionVerificationInput(
            token: CoachingEpisodeToken(rawValue: UUID(), generation: generation),
            actionID: actionID,
            before: before,
            after: after,
            beforeLifecycle: lifecycle,
            afterLifecycle: lifecycle,
            beforeGeometry: beforeGeometry,
            afterGeometry: afterGeometry,
            subjectIdentity: identity
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
            scalarScores: [0.72, 0.34, 0.66, 0.81, 0.62, 0.57, 0.54],
            scalarConfidences: [0.83, 0.78, 0.74, 0.79, 0.69, 0.67, 0.61],
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
