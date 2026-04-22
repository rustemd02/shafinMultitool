import XCTest
import CoreVideo
import ImageIO
@testable import shafinMultitool

final class NeuralEvidenceInferenceServiceTests: XCTestCase {
    func testMockProviderExecutesAndBuildsValidPauseSnapshot() async {
        let provider = MockNeuralEvidenceProvider { request in
            self.makeProviderOutput(actualROIStrategy: request.roiStrategy)
        }
        let service = NeuralEvidenceInferenceService(
            configuration: makeEnabledConfiguration(),
            provider: provider
        )

        let outcome = await service.infer(
            request: makeRequest(
                mode: .pause,
                frameId: "pause-exec",
                semantics: makeSemantics(frameId: "pause-exec", mode: .pause, primaryKind: .person),
                primarySubjectRegion: NormalizedRect(x: 0.22, y: 0.12, width: 0.28, height: 0.44)
            )
        )

        XCTAssertEqual(outcome.kind, .executed)
        XCTAssertEqual(provider.prepareCallCount, 1)
        XCTAssertEqual(provider.inferCallCount, 1)
        XCTAssertEqual(outcome.metadata?.roiStrategy, .fullFramePlusSubjectCrop)
        XCTAssertEqual(
            outcome.snapshot?.validate(
                expectedFrameId: "pause-exec",
                semanticsReport: makeSemantics(frameId: "pause-exec", mode: .pause, primaryKind: .person),
                runtimeMetadata: outcome.metadata
            ) ?? ["missing snapshot"],
            []
        )
    }

    func testLiveCadenceSkipsSecondRequestWithinInterval() async {
        let provider = MockNeuralEvidenceProvider { _ in
            self.makeProviderOutput()
        }
        var now = Date(timeIntervalSince1970: 1_771_111_000)
        let service = NeuralEvidenceInferenceService(
            configuration: makeEnabledConfiguration(),
            provider: provider,
            dateProvider: { now }
        )

        let request = makeRequest(
            mode: .live,
            frameId: "live-cadence",
            semantics: makeSemantics(frameId: "live-cadence", mode: .live, primaryKind: .person)
        )

        let first = await service.infer(request: request)
        now = now.addingTimeInterval(1.0)
        let second = await service.infer(request: request)

        XCTAssertEqual(first.kind, .executed)
        XCTAssertEqual(second.kind, .policySkipped)
        XCTAssertEqual(provider.inferCallCount, 1)
        XCTAssertEqual(second.metadata?.failureReason, .policySkipped)
    }

    func testConcurrentLiveRequestsReserveCadenceAtomically() async {
        let provider = MockNeuralEvidenceProvider { _ in
            try await Task.sleep(nanoseconds: 30_000_000)
            return self.makeProviderOutput(actualROIStrategy: .fullFrameOnly)
        }
        let now = Date(timeIntervalSince1970: 1_771_111_000)
        let service = NeuralEvidenceInferenceService(
            configuration: makeEnabledConfiguration(),
            provider: provider,
            dateProvider: { now }
        )

        let request = makeRequest(
            mode: .live,
            frameId: "live-concurrent",
            semantics: makeSemantics(frameId: "live-concurrent", mode: .live, primaryKind: .person)
        )

        async let first = service.infer(request: request)
        async let second = service.infer(request: request)
        let outcomes = await [first, second]

        XCTAssertEqual(outcomes.filter { $0.kind == .executed }.count, 1)
        XCTAssertEqual(outcomes.filter { $0.kind == .policySkipped }.count, 1)
        XCTAssertEqual(provider.inferCallCount, 1)
    }

    func testLiveStabilityGateSkipsWithoutCallingProvider() async {
        let provider = MockNeuralEvidenceProvider { _ in
            self.makeProviderOutput()
        }
        let service = NeuralEvidenceInferenceService(
            configuration: makeEnabledConfiguration(),
            provider: provider
        )

        let outcome = await service.infer(
            request: makeRequest(
                mode: .live,
                frameId: "live-unstable",
                semantics: makeSemantics(frameId: "live-unstable", mode: .live, primaryKind: .person),
                isStable: false
            )
        )

        XCTAssertEqual(outcome.kind, .policySkipped)
        XCTAssertEqual(provider.inferCallCount, 0)
        XCTAssertEqual(outcome.metadata?.failureReason, .policySkipped)
    }

    func testPauseDegradedProfileStillExecutesWhenHeavyModelsDisabled() async {
        let provider = MockNeuralEvidenceProvider { request in
            XCTAssertEqual(request.roiStrategy, .fullFrameOnly)
            return self.makeProviderOutput()
        }
        let service = NeuralEvidenceInferenceService(
            configuration: makeEnabledConfiguration(),
            provider: provider
        )

        let outcome = await service.infer(
            request: makeRequest(
                mode: .pause,
                frameId: "pause-degraded",
                semantics: makeSemantics(frameId: "pause-degraded", mode: .pause, primaryKind: .person),
                primarySubjectRegion: NormalizedRect(x: 0.18, y: 0.14, width: 0.22, height: 0.33),
                thermalTier: .critical,
                heavyModelsEnabled: false
            )
        )

        XCTAssertEqual(outcome.kind, .executed)
        XCTAssertEqual(outcome.metadata?.roiStrategy, .fullFrameOnly)
    }

    func testDisabledFeatureReturnsDisabledWithoutSnapshot() async {
        let provider = MockNeuralEvidenceProvider { _ in
            self.makeProviderOutput()
        }
        let service = NeuralEvidenceInferenceService(
            configuration: .disabled,
            provider: provider
        )

        let outcome = await service.infer(
            request: makeRequest(
                mode: .pause,
                frameId: "disabled",
                semantics: makeSemantics(frameId: "disabled", mode: .pause, primaryKind: .person)
            )
        )

        XCTAssertEqual(outcome.kind, .disabled)
        XCTAssertNil(outcome.snapshot)
        XCTAssertNil(outcome.metadata)
        XCTAssertEqual(provider.inferCallCount, 0)
    }

    func testProviderFailureReturnsHardFailureSnapshot() async {
        let provider = MockNeuralEvidenceProvider { _ in
            throw NeuralEvidenceProviderError.inferenceFailed
        }
        let service = NeuralEvidenceInferenceService(
            configuration: makeEnabledConfiguration(),
            provider: provider
        )

        let semantics = makeSemantics(frameId: "pause-failure", mode: .pause, primaryKind: .person)
        let outcome = await service.infer(
            request: makeRequest(
                mode: .pause,
                frameId: "pause-failure",
                semantics: semantics
            )
        )

        XCTAssertEqual(outcome.kind, .failed)
        XCTAssertEqual(outcome.metadata?.failureReason, .inferenceFailed)
        XCTAssertEqual(
            outcome.snapshot?.validate(
                expectedFrameId: "pause-failure",
                semanticsReport: semantics,
                runtimeMetadata: outcome.metadata
            ) ?? ["missing snapshot"],
            []
        )
    }

    func testFaceSaliencyApplicabilityFollowsSemanticsAndMissingSemantics() async {
        let provider = MockNeuralEvidenceProvider { _ in
            self.makeProviderOutput()
        }
        let service = NeuralEvidenceInferenceService(
            configuration: makeEnabledConfiguration(),
            provider: provider
        )

        let objectOutcome = await service.infer(
            request: makeRequest(
                mode: .pause,
                frameId: "pause-object",
                semantics: makeSemantics(frameId: "pause-object", mode: .pause, primaryKind: .object)
            )
        )
        let missingSemanticsOutcome = await service.infer(
            request: makeRequest(
                mode: .pause,
                frameId: "pause-missing",
                semantics: nil
            )
        )

        XCTAssertEqual(faceSaliencyStatus(from: objectOutcome.snapshot), .notApplicable)
        XCTAssertEqual(faceSaliencyStatus(from: missingSemanticsOutcome.snapshot), .unavailable)
    }

    func testLiveModeKeepsPauseOnlyHeadsNotApplicableEvenWhenExecuted() async {
        let provider = MockNeuralEvidenceProvider { _ in
            self.makeProviderOutput()
        }
        let service = NeuralEvidenceInferenceService(
            configuration: makeEnabledConfiguration(),
            provider: provider
        )

        let outcome = await service.infer(
            request: makeRequest(
                mode: .live,
                frameId: "live-exec",
                semantics: makeSemantics(frameId: "live-exec", mode: .live, primaryKind: .person)
            )
        )

        XCTAssertEqual(outcome.kind, .executed)
        XCTAssertEqual(status(of: .balanceConfidence, in: outcome.snapshot), .notApplicable)
        XCTAssertEqual(status(of: .depthSeparation, in: outcome.snapshot), .notApplicable)
        XCTAssertEqual(status(of: .cinematicExpressiveness, in: outcome.snapshot), .notApplicable)
        XCTAssertEqual(status(of: .shotTypeConfidence, in: outcome.snapshot), .notApplicable)
    }

    func testPauseTimeoutReturnsRuntimeTimeoutFailure() async {
        let provider = MockNeuralEvidenceProvider { _ in
            try await Task.sleep(nanoseconds: 80_000_000)
            return self.makeProviderOutput()
        }
        var configuration = makeEnabledConfiguration()
        configuration.pauseTimeout = 0.01
        let service = NeuralEvidenceInferenceService(
            configuration: configuration,
            provider: provider
        )

        let outcome = await service.infer(
            request: makeRequest(
                mode: .pause,
                frameId: "pause-timeout",
                semantics: makeSemantics(frameId: "pause-timeout", mode: .pause, primaryKind: .person)
            )
        )

        XCTAssertEqual(outcome.kind, .failed)
        XCTAssertEqual(outcome.metadata?.failureReason, .runtimeTimeout)
    }

    func testExecutedMetadataUsesActualRoiStrategyFromProvider() async {
        let provider = MockNeuralEvidenceProvider { request in
            XCTAssertEqual(request.roiStrategy, .fullFramePlusSubjectCrop)
            return self.makeProviderOutput(actualROIStrategy: .fullFrameOnly)
        }
        let service = NeuralEvidenceInferenceService(
            configuration: makeEnabledConfiguration(),
            provider: provider
        )

        let outcome = await service.infer(
            request: makeRequest(
                mode: .pause,
                frameId: "pause-roi-fallback",
                semantics: makeSemantics(frameId: "pause-roi-fallback", mode: .pause, primaryKind: .person),
                primarySubjectRegion: NormalizedRect(x: 0.22, y: 0.12, width: 0.28, height: 0.44)
            )
        )

        XCTAssertEqual(outcome.kind, .executed)
        XCTAssertEqual(outcome.metadata?.roiStrategy, .fullFrameOnly)
    }

    func testExecutedOutcomeUsesThresholdProfileFromProviderDescriptor() async {
        let descriptor = makeDescriptor(
            thresholdProfileLive: "live_rollout_v2",
            thresholdProfilePause: "pause_rollout_v3"
        )
        let provider = MockNeuralEvidenceProvider(descriptor: descriptor) { _ in
            self.makeProviderOutput()
        }
        let service = NeuralEvidenceInferenceService(
            configuration: makeEnabledConfiguration(),
            provider: provider
        )

        let outcome = await service.infer(
            request: makeRequest(
                mode: .live,
                frameId: "live-threshold-profile",
                semantics: makeSemantics(frameId: "live-threshold-profile", mode: .live, primaryKind: .person)
            )
        )

        XCTAssertEqual(outcome.kind, .executed)
        XCTAssertEqual(outcome.metadata?.thresholdProfile, "live_rollout_v2")
    }

    func testFailureMetadataUsesActualRoiStrategyFromExecutionError() async {
        let provider = MockNeuralEvidenceProvider { _ in
            throw NeuralEvidenceProviderExecutionError(
                providerError: .postprocessingFailed,
                actualROIStrategy: .fullFrameOnly
            )
        }
        let service = NeuralEvidenceInferenceService(
            configuration: makeEnabledConfiguration(),
            provider: provider
        )

        let outcome = await service.infer(
            request: makeRequest(
                mode: .pause,
                frameId: "pause-failure-roi-fallback",
                semantics: makeSemantics(frameId: "pause-failure-roi-fallback", mode: .pause, primaryKind: .person),
                primarySubjectRegion: NormalizedRect(x: 0.22, y: 0.12, width: 0.28, height: 0.44)
            )
        )

        XCTAssertEqual(outcome.kind, .failed)
        XCTAssertEqual(outcome.metadata?.roiStrategy, .fullFrameOnly)
        XCTAssertEqual(outcome.metadata?.failureReason, .postprocessingFailed)
    }
}

private extension NeuralEvidenceInferenceServiceTests {
    func makeEnabledConfiguration() -> NeuralEvidenceInferenceConfiguration {
        var configuration = NeuralEvidenceInferenceConfiguration.disabled
        configuration.featureEnabled = true
        configuration.liveModeEnabled = true
        configuration.pauseModeEnabled = true
        return configuration
    }

    func makeDescriptor(thresholdProfileLive: String = "default_live_v1",
                        thresholdProfilePause: String = "default_pause_v1") -> NeuralEvidenceProviderDescriptor {
        NeuralEvidenceProviderDescriptor(
            providerKind: .mock,
            inferenceTarget: .onDevice,
            modelFamily: "mock_neural_evidence",
            modelVersion: "test.v1",
            preprocessingVersion: "prep.test",
            thresholdProfileLive: thresholdProfileLive,
            thresholdProfilePause: thresholdProfilePause,
            bundleVersion: "mock.bundle.v1"
        )
    }

    func makeRequest(mode: AnalysisMode,
                     frameId: String,
                     semantics: SceneSemanticsReport?,
                     primarySubjectRegion: NormalizedRect? = nil,
                     isStable: Bool = true,
                     thermalTier: ThermalBudgetTier = .unrestricted,
                     heavyModelsEnabled: Bool = true,
                     batteryLevel: Float? = 1.0) -> NeuralEvidenceInferenceRequest {
        NeuralEvidenceInferenceRequest(
            frameId: frameId,
            mode: mode,
            capturedAt: Date(timeIntervalSince1970: 1_771_111_100),
            pixelBuffer: makePixelBuffer(width: 32, height: 32),
            orientation: .up,
            sceneSemantics: semantics,
            primarySubjectRegion: primarySubjectRegion,
            motionState: .still,
            shakeLevel: 0.08,
            isStable: isStable,
            thermalTier: thermalTier,
            heavyModelsEnabled: heavyModelsEnabled,
            batteryLevel: batteryLevel,
            forcePauseExecution: mode == .pause
        )
    }

    func makeProviderOutput(actualROIStrategy: NeuralEvidenceROIStrategy = .fullFrameOnly) -> NeuralEvidenceProviderOutput {
        let row: [Double] = [
            0.82, 0.73, 0.68, 0.12, 0.11, 0.05, 0.04,
            0.74, 0.21, 0.66, 0.71, 0.65, 0.51, 0.16,
            0.55, 0.59, 0.63, 0.48, 0.31, 0.58, 0.77
        ]
        return NeuralEvidenceProviderOutput(
            scalarScores: [0.72, 0.34, 0.66, 0.81, 0.62, 0.57, 0.54],
            scalarConfidences: [0.83, 0.78, 0.74, 0.79, 0.69, 0.67, 0.61],
            supportingSignalScores: Array(repeating: row, count: 7),
            shotTypeAffinities: [0.74, 0.28, 0.19, 0.12, 0.09, 0.22, 0.18],
            shotTypeConfidence: 0.63,
            actualROIStrategy: actualROIStrategy
        )
    }

    func makeSemantics(frameId: String,
                       mode: AnalysisMode,
                       primaryKind: SubjectKind) -> SceneSemanticsReport {
        SceneSemanticsReport(
            frameId: frameId,
            mode: mode,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.79,
            primarySubject: .init(kind: primaryKind, confidence: primaryKind == .unknown ? 0.2 : 0.84),
            dominance: .init(hasClearFocus: true, focusCompetitionScore: 0.19, backgroundClutterScore: 0.24),
            readability: .init(subjectReadable: true, lookSpaceAdequate: true, edgePressureScore: 0.18, separationScore: 0.71),
            ambiguities: [],
            assumptions: []
        )
    }

    func status(of headId: EvidenceHeadId, in snapshot: NeuralEvidenceSnapshot?) -> EvidenceHeadStatus? {
        guard let entry = snapshot?.headOutputs.first(where: { $0.headId == headId }) else {
            return nil
        }
        return entry.payload.status
    }

    func faceSaliencyStatus(from snapshot: NeuralEvidenceSnapshot?) -> EvidenceHeadStatus? {
        status(of: .faceSaliency, in: snapshot)
    }

    func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer {
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
