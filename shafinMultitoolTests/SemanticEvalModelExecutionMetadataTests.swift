import Foundation
import XCTest
@testable import shafinMultitool

#if DEBUG
final class SemanticEvalModelExecutionMetadataTests: XCTestCase {
    private let frameId = "export-frame"
    private let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)

    func testCompactPreservesReturnedOutcomesAndActualMetadata() {
        for kind in [NeuralEvidenceInferenceOutcomeKind.executed, .failed, .policySkipped, .disabled] {
            let outcome = makeOutcome(kind: kind)
            let actual = project(outcome)
            XCTAssertEqual(actual.status.rawValue, kind.rawValue)
            XCTAssertEqual(actual.metadata, outcome.metadata)
            XCTAssertEqual(actual.metadata?.failureReason, outcome.metadata?.failureReason)
            if kind == .disabled {
                XCTAssertNil(actual.headStatuses)
            } else {
                XCTAssertEqual(actual.headStatuses?.count, EvidenceHeadId.allCases.count)
            }
        }
    }

    func testCompactExecutionSurvivesNoAvailableHeadsAndZeroLatency() throws {
        let outcome = makeOutcome(kind: .executed)
        XCTAssertEqual(outcome.snapshot?.validate(runtimeMetadata: outcome.metadata), [])
        let actual = project(outcome)
        XCTAssertEqual(actual.status, .executed)
        XCTAssertEqual(actual.metadata?.latencyMs, 0)
        XCTAssertEqual(actual.metadata?.providerKind, .mock)
        XCTAssertTrue(try XCTUnwrap(actual.headStatuses).values.allSatisfy { $0 != .available })
        // These are synthetic callback fixtures; an executed outcome does not require a primary output.
        XCTAssertEqual(actual.headStatuses?["subject_prominence"], .unavailable)
        let skipped = project(makeOutcome(kind: .policySkipped))
        XCTAssertNil(skipped.metadata?.latencyMs)
        XCTAssertNil(skipped.metadata?.roiStrategy)
        XCTAssertEqual(skipped.metadata?.failureReason, .policySkipped)
    }

    func testCompactRejectsSnapshotAndMetadataIdentityIndependently() {
        let mismatches = [
            makeOutcome(snapshotFrame: "previous-frame"),
            makeOutcome(snapshotMode: .pause),
            makeOutcome(metadataFrame: "previous-frame"),
            makeOutcome(metadataMode: .pause),
            makeOutcome(snapshotDate: capturedAt.addingTimeInterval(-1))
        ]
        for mismatch in mismatches {
            let actual = project(mismatch)
            XCTAssertEqual(actual.status, .identityMismatch)
            XCTAssertNil(actual.metadata)
            XCTAssertNil(actual.headStatuses)
        }
    }

    func testNoRequestOrNoOutcomeDoesNotInventDisabledOrExecution() {
        let previous = makeOutcome()
        XCTAssertEqual(project(previous, requested: false).status, .notRequested)
        XCTAssertNil(project(previous, requested: false).metadata)
        XCTAssertEqual(project(nil).status, .unknown)
        XCTAssertNil(project(nil).headStatuses)
        XCTAssertEqual(project(makeOutcome(kind: .disabled)).status, .disabled)
        XCTAssertEqual(SemanticEvalCompactModelExecution.project(
            requested: true, frameId: " ", mode: .live, capturedAt: capturedAt,
            outcome: makeOutcome(kind: .disabled)).status, .identityMismatch)
    }

    func testDetrTypedResultPreservesEmptyFailureAndObservedCount() throws {
        let empty = SemanticEvalLegacyModelExecution.detrResult(.success([]))
        XCTAssertEqual(empty.invocation, .callbackReceived)
        XCTAssertEqual(empty.modelLoaded, true)
        XCTAssertEqual(empty.detectionCount, 0)
        XCTAssertEqual(empty.outputEvidence, .available)
        XCTAssertNil(empty.failureReason)
        let missing = SemanticEvalLegacyModelExecution.detrResult(.failure(.modelUnavailable))
        XCTAssertEqual(missing.invocation, .modelUnavailable)
        XCTAssertEqual(missing.modelLoaded, false)
        XCTAssertNil(missing.detectionCount)
        XCTAssertEqual(missing.outputEvidence, .unknown)
        XCTAssertEqual(missing.failureReason, .modelUnavailable)
        for reason in [DETRDetectionFailure.inferenceFailed, .missingOutput, .invalidOutput] {
            let failure = SemanticEvalLegacyModelExecution.detrResult(.failure(reason))
            XCTAssertEqual(failure.invocation, .callbackReceived)
            XCTAssertEqual(failure.modelLoaded, true)
            XCTAssertEqual(failure.outputEvidence, .unknown)
            XCTAssertNil(failure.detectionCount, "A failed request has no measured zero count")
            XCTAssertEqual(failure.failureReason, reason)
            XCTAssertEqual(try JSONDecoder().decode(SemanticEvalLegacyModelExecution.self,
                                                   from: JSONEncoder().encode(failure)), failure)
        }
        let detection = DETRDetection(boundingBox: .init(x: 0.2, y: 0.2, width: 0.3, height: 0.3),
                                      label: "chair", confidence: 0.5)
        let nonempty = SemanticEvalLegacyModelExecution.detrResult(.success([detection, detection]))
        XCTAssertEqual(nonempty.detectionCount, 2)
        XCTAssertEqual(nonempty.outputEvidence, .available)
        let historical = Data(#"{"invocation":"callback_received","modelLoaded":true,"outputEvidence":"unknown","detectionCount":0}"#.utf8)
        let decoded = try JSONDecoder().decode(SemanticEvalLegacyModelExecution.self, from: historical)
        XCTAssertEqual(decoded.outputEvidence, .unknown, "Old ambiguous rows retain their original meaning")
        XCTAssertNil(decoded.failureReason)
    }

    func testNimaNilAndNonfiniteRemainUnknownButZeroIsAnObservedNumericOutput() throws {
        for score in [nil, Double.nan, Double.infinity, -Double.infinity] as [Double?] {
            let actual = SemanticEvalLegacyModelExecution.nimaCallback(score10: score)
            XCTAssertEqual(actual.invocation, .callbackReceived)
            XCTAssertNil(actual.score10)
            XCTAssertNil(actual.modelLoaded)
            XCTAssertEqual(actual.outputEvidence, .unknown)
            XCTAssertNoThrow(try JSONEncoder().encode(actual))
        }
        for score in [0.0, 5.25] {
            let actual = SemanticEvalLegacyModelExecution.nimaCallback(score10: score)
            XCTAssertEqual(actual.score10, score)
            XCTAssertEqual(actual.modelLoaded, true)
            XCTAssertEqual(actual.outputEvidence, .available)
        }
    }

    func testSharedStillObservationRequiresExactCaptureAndDoesNotClaimCompositionInvocation() {
        let observations = makeStill()
        for mode in [AnalysisMode.live, .pause] {
            let actual = makeMetadata(mode: mode, still: observations)
            XCTAssertEqual(actual.mode, mode)
            XCTAssertTrue(actual.stillFeatureIdentityMatches)
            XCTAssertEqual(actual.stillFeatures, observations)
            XCTAssertEqual(actual.composition.invocation, .notInvoked)
            XCTAssertEqual(actual.composition.outputEvidence, .unknown)
            XCTAssertNil(actual.composition.modelLoaded)
            XCTAssertNil(actual.composition.score10)
        }
        for stale in [makeStill(frame: "old"), makeStill(date: capturedAt.addingTimeInterval(-1))] {
            let actual = makeMetadata(still: stale)
            XCTAssertFalse(actual.stillFeatureIdentityMatches)
            XCTAssertNil(actual.stillFeatures)
        }
    }

    func testLightweightObservationDoesNotFabricateCallbacks() {
        let still = SemanticEvalStillModelExecution.notRequested(frameId: frameId, capturedAt: capturedAt)
        let actual = SemanticEvalModelExecutionMetadata(
            frameId: frameId, mode: .live, capturedAt: capturedAt,
            neuralRequested: false, neuralOutcome: nil, stillFeatures: still
        )
        XCTAssertEqual(actual.compactNeural.status, .notRequested)
        XCTAssertEqual(actual.stillFeatures?.detr.invocation, .notRequested)
        XCTAssertEqual(actual.stillFeatures?.nima.invocation, .notRequested)
        XCTAssertNil(actual.stillFeatures?.detr.detectionCount)
        XCTAssertNil(actual.stillFeatures?.nima.score10)
    }

    func testAddingMetadataPreservesEveryExistingRowFieldAndOldJSONDecodes() throws {
        let original = SemanticEvalCandidateOutput(
            recordId: "record", filename: "frame.jpg", mode: "live", shown: false,
            liveTip: nil, pauseSummary: nil, semanticActions: [], futureActions: ["fix_focus"],
            confidence: 0.37, source: "fixture", runtimeClaim: .testFixture,
            traceIds: ["trace"], debugIssueTypes: ["blur"], debugStrengthTypes: [],
            debugActionTypes: [], debugNumericFeatures: ["object_count": 0],
            debugSemanticLabels: ["verdict": "mixed"]
        )
        let encoder = JSONEncoder()
        let oldData = try encoder.encode(original)
        let oldJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: oldData) as? [String: Any])
        XCTAssertNil(oldJSON["debug_model_execution"])
        XCTAssertEqual(try JSONDecoder().decode(SemanticEvalCandidateOutput.self, from: oldData), original)

        let decorated = original.withModelExecution(makeMetadata(still: makeStill()))
        XCTAssertEqual(decorated.runtimeClaim, .testFixture)
        let newData = try encoder.encode(decorated)
        var newJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: newData) as? [String: Any])
        XCTAssertNotNil(newJSON.removeValue(forKey: "debug_model_execution"))
        XCTAssertTrue(NSDictionary(dictionary: newJSON).isEqual(to: oldJSON))
        XCTAssertEqual(try JSONDecoder().decode(SemanticEvalCandidateOutput.self, from: newData), decorated)
        XCTAssertNil(original.debugModelExecution)
    }

    func testTechnicalMeasurementDistinguishesEmptyUnavailableAndIdentityMismatch() throws {
        let snapshot = makeTechnicalSnapshot()
        let measured = SemanticEvalTechnicalMeasurementMetadata(
            evidence: .init(frameID: frameId, capturedAt: capturedAt, measurement: .measured(.empty)),
            snapshot: snapshot)
        XCTAssertEqual(measured.status, .measured)
        XCTAssertEqual(measured.signal, .empty)
        XCTAssertTrue(measured.frameIdentityMatches)
        XCTAssertNil(measured.unavailableReason)
        XCTAssertNil(measured.pixelDiagnostics, "Supplied signals are not a raw-pixel diagnostic capture")
        XCTAssertEqual(measured.numericFeatures, [
            "technical_issue_count": 0, "technical_dominant_count": 0,
            "technical_max_severity": 0, "technical_max_confidence": 0
        ])
        let reasons: [TechnicalQualityUnavailableReason] = [
            .notMeasured, .frameMismatch, .missingPixelBuffer, .unsupportedPixelFormat,
            .pixelBufferLockFailed, .invalidBufferLayout, .baseAddressUnavailable
        ]
        for reason in reasons {
            let unavailable = SemanticEvalTechnicalMeasurementMetadata(
                evidence: .init(frameID: frameId, capturedAt: capturedAt,
                                measurement: .unavailable(reason)), snapshot: snapshot)
            XCTAssertEqual(unavailable.status, .unavailable)
            XCTAssertTrue(unavailable.frameIdentityMatches)
            XCTAssertEqual(unavailable.unavailableReason, reason.rawValue)
            XCTAssertNil(unavailable.signal)
            XCTAssertTrue(unavailable.numericFeatures.isEmpty, "Unavailable has no observed zero")
            XCTAssertEqual(try JSONDecoder().decode(SemanticEvalTechnicalMeasurementMetadata.self,
                from: JSONEncoder().encode(unavailable)), unavailable)
        }
        for evidence in [
            FrameTechnicalQualityEvidence(frameID: "previous", capturedAt: capturedAt, measurement: .measured(.empty)),
            .init(frameID: " ", capturedAt: capturedAt, measurement: .measured(.empty)),
            .init(frameID: frameId, capturedAt: capturedAt.addingTimeInterval(-1), measurement: .measured(.empty)),
            .init(frameID: frameId, capturedAt: Date(timeIntervalSinceReferenceDate: .nan), measurement: .measured(.empty))
        ] {
            let rejected = SemanticEvalTechnicalMeasurementMetadata(evidence: evidence, snapshot: snapshot)
            XCTAssertFalse(rejected.frameIdentityMatches)
            XCTAssertEqual(rejected.status, .unavailable)
            XCTAssertEqual(rejected.unavailableReason, TechnicalQualityUnavailableReason.frameMismatch.rawValue)
            XCTAssertNil(rejected.signal)
            XCTAssertTrue(rejected.numericFeatures.isEmpty)
            XCTAssertNoThrow(try JSONEncoder().encode(rejected), "Rejected nonfinite identity cannot drop the row")
            if !evidence.capturedAt.timeIntervalSinceReferenceDate.isFinite {
                XCTAssertNil(rejected.sourceCapturedAt)
            }
        }
        let measuredJSON = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(measured)) as? [String: Any])
        let signalJSON = try XCTUnwrap(measuredJSON["signal"] as? [String: Any])
        XCTAssertEqual((signalJSON["issues"] as? [Any])?.count, 0)
    }

    func testPartialTechnicalMetadataRetainsObservationAndUnknownCoverage() throws {
        let detail = TechnicalImageDetailObservation(
            sampleWidth: 96, sampleHeight: 96, meanLuma: 0.5,
            gradientMean: 0, gradientVariance: 0)
        let partial = TechnicalQualityMeasurement.partial(.empty,
            reason: .sharpnessCauseUnobservable, detail: detail)
        let metadata = SemanticEvalTechnicalMeasurementMetadata(
            evidence: .init(frameID: frameId, capturedAt: capturedAt, measurement: partial),
            snapshot: makeTechnicalSnapshot())
        XCTAssertEqual(metadata.status, .partial)
        XCTAssertEqual(metadata.signal, .empty)
        XCTAssertEqual(metadata.unavailableReason, "sharpnessCauseUnobservable")
        XCTAssertEqual(metadata.imageDetail, detail)
        XCTAssertFalse(partial.supportsPositiveConfirmation)
        XCTAssertEqual(try JSONDecoder().decode(SemanticEvalTechnicalMeasurementMetadata.self,
            from: JSONEncoder().encode(metadata)), metadata)
        let oldMeasured = SemanticEvalTechnicalMeasurementMetadata(
            evidence: .init(frameID: frameId, capturedAt: capturedAt, measurement: .measured(.empty)),
            snapshot: makeTechnicalSnapshot())
        XCTAssertNil(oldMeasured.imageDetail)
        XCTAssertNil(oldMeasured.pixelDiagnostics)
        XCTAssertEqual(try JSONDecoder().decode(SemanticEvalTechnicalMeasurementMetadata.self,
            from: JSONEncoder().encode(oldMeasured)), oldMeasured)
        XCTAssertNil(try JSONDecoder().decode(SemanticEvalTechnicalMeasurementMetadata.self,
            from: JSONEncoder().encode(metadata)).pixelDiagnostics,
            "Historical partial metadata must not acquire invented raw metrics")
    }

    func testTechnicalMeasurementMetadataPreservesScoringFieldsAndHistoricalJSON() throws {
        let original = SemanticEvalCandidateOutput(
            recordId: "record", filename: "generated.bgra", mode: "pause", shown: true,
            liveTip: nil, pauseSummary: "Existing presentation", semanticActions: ["keep_current_setup"],
            futureActions: ["increase_exposure"], confidence: 0.37, source: "fixture", runtimeClaim: .testFixture,
            traceIds: ["trace"], debugIssueTypes: [], debugStrengthTypes: [], debugActionTypes: [],
            debugNumericFeatures: ["technical_issue_count": 0], debugSemanticLabels: ["verdict": "good"])
        let technical = SemanticEvalTechnicalMeasurementMetadata(
            evidence: .init(frameID: frameId, capturedAt: capturedAt, measurement: .unavailable(.notMeasured)),
            snapshot: makeTechnicalSnapshot())
        let model = makeMetadata(mode: .pause, still: makeStill())
        let decorated = original.withModelExecution(model).withTechnicalMeasurement(technical)
        XCTAssertEqual(decorated, original.withTechnicalMeasurement(technical).withModelExecution(model))
        let encoder = JSONEncoder()
        let oldData = try encoder.encode(original)
        let oldJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: oldData) as? [String: Any])
        XCTAssertNil(oldJSON["debug_technical_measurement"])
        let historical = try JSONDecoder().decode(SemanticEvalCandidateOutput.self, from: oldData)
        XCTAssertEqual(historical, original)
        XCTAssertNil(historical.debugTechnicalMeasurement,
                     "A historical numeric zero does not prove a measured-empty result")
        let newData = try encoder.encode(decorated)
        var newJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: newData) as? [String: Any])
        XCTAssertNotNil(newJSON.removeValue(forKey: "debug_technical_measurement"))
        XCTAssertNotNil(newJSON.removeValue(forKey: "debug_model_execution"))
        XCTAssertTrue(NSDictionary(dictionary: newJSON).isEqual(to: oldJSON))
        XCTAssertEqual(try JSONDecoder().decode(SemanticEvalCandidateOutput.self, from: newData), decorated)
    }

    private func makeTechnicalSnapshot(mode: AnalysisMode = .pause) -> FrameFeatureSnapshot {
        FrameFeatureSnapshot(
            frameId: frameId, mode: mode, capturedAt: capturedAt,
            sources: .init(vision: .init(available: false), horizon: .init(available: false),
                           lighting: .init(available: false), detr: .init(available: false),
                           aesthetic: .init(available: false)),
            composition: .init(horizontalOffset: 0, verticalOffset: 0, subjectAreaRatio: 0,
                               saliencyLeftRightBalance: 0, saliencyTopBottomBalance: 0),
            subjectSignals: .init(faceDetected: false, personDetected: false, personCount: 0,
                                  topObjectLabel: nil, topObjectConfidence: nil),
            horizon: .init(angleDegrees: 0, confidence: 0),
            lighting: .init(exposureBiasHint: 0, backlightIndex: 0, keyToFillRatio: 1),
            motion: .init(state: .still, shakeLevel: 0),
            aesthetics: .init(score: nil, scoreConfidence: nil),
            objects: .init(totalCount: 0, topKLabels: []), technicalFlags: [])
    }

    private func project(_ outcome: NeuralEvidenceRecordedOutcome?, requested: Bool = true) -> SemanticEvalCompactModelExecution {
        .project(requested: requested, frameId: frameId, mode: .live,
                 capturedAt: capturedAt, outcome: outcome)
    }

    private func makeStill(frame: String? = nil, date: Date? = nil) -> SemanticEvalStillModelExecution {
        .init(frameId: frame ?? frameId, capturedAt: date ?? capturedAt,
              detr: .detrResult(.success([])),
              nima: .nimaCallback(score10: nil))
    }

    private func makeMetadata(mode: AnalysisMode = .live, still: SemanticEvalStillModelExecution) -> SemanticEvalModelExecutionMetadata {
        .init(frameId: frameId, mode: mode, capturedAt: capturedAt,
              neuralRequested: true,
              neuralOutcome: makeOutcome(snapshotMode: mode, metadataMode: mode),
              stillFeatures: still)
    }

    private func makeOutcome(kind: NeuralEvidenceInferenceOutcomeKind = .executed,
                             snapshotFrame: String? = nil, snapshotMode: AnalysisMode = .live,
                             metadataFrame: String? = nil, metadataMode: AnalysisMode = .live,
                             snapshotDate: Date? = nil) -> NeuralEvidenceRecordedOutcome {
        if kind == .disabled { return NeuralEvidenceRecordedOutcome(.disabled) }
        let heads = EvidenceHeadId.allCases.map { id in
            let pauseOnly: Set<EvidenceHeadId> = [.balanceConfidence, .depthSeparation, .cinematicExpressiveness, .shotTypeConfidence]
            let status: EvidenceHeadStatus = snapshotMode == .live && pauseOnly.contains(id) ? .notApplicable : .unavailable
            let payload: NeuralEvidenceHeadPayload
            if id == .shotTypeConfidence {
                payload = .categorical(.init(headId: id, status: status,
                    affinities: [], confidence: 0, mode: snapshotMode, supportingSignals: []))
            } else {
                payload = .scalar(.init(headId: id, status: status,
                    score: nil, confidence: 0, mode: snapshotMode, supportingSignals: []))
            }
            return NeuralEvidenceHeadEntry(headId: id, payload: payload)
        }
        let snapshot = NeuralEvidenceSnapshot(schemaVersion: NeuralEvidenceSnapshot.currentSchemaVersion,
            frameId: snapshotFrame ?? frameId, mode: snapshotMode,
            capturedAt: snapshotDate ?? capturedAt, bundleVersion: "fixture", headOutputs: heads)
        let metadata = NeuralEvidenceRuntimeMetadata(
            metadataSchemaVersion: NeuralEvidenceSnapshot.currentSchemaVersion, frameId: metadataFrame ?? frameId, mode: metadataMode,
            providerKind: .mock, inferenceTarget: .onDevice, modelFamily: "fixture",
            modelVersion: "fixture-v1", preprocessingVersion: "fixture", thresholdProfile: "fixture",
            producedAt: capturedAt.addingTimeInterval(1), latencyMs: kind == .policySkipped ? nil : 0,
            roiStrategy: kind == .executed ? .fullFrameOnly : nil,
            failureReason: kind == .failed ? .inferenceFailed : (kind == .policySkipped ? .policySkipped : nil))
        switch kind {
        case .executed: return NeuralEvidenceRecordedOutcome(.executed(snapshot: snapshot, metadata: metadata))
        case .failed: return NeuralEvidenceRecordedOutcome(.failed(snapshot: snapshot, metadata: metadata))
        case .policySkipped: return NeuralEvidenceRecordedOutcome(.policySkipped(snapshot: snapshot, metadata: metadata))
        case .disabled: return NeuralEvidenceRecordedOutcome(.disabled)
        }
    }
}
#endif


#if DEBUG && os(iOS)
import CoreGraphics
import CoreVideo
import ImageIO

extension SemanticEvalModelExecutionMetadataTests {
    func testPixelDiagnosticsRejectMismatchedFrameTimeAndConsumedMeasurement() throws {
        let capture = TechnicalQualityAnalyzer().debugMeasurement(
            pixelBuffer: try makeIntegrationPixelBuffer(gray: 0),
            frameID: frameId, capturedAt: capturedAt)
        let matching = SemanticEvalTechnicalMeasurementMetadata(
            evidence: capture.evidence, snapshot: makeTechnicalSnapshot(), debugCapture: capture)
        XCTAssertNotNil(matching.pixelDiagnostics)
        XCTAssertEqual(matching.status, .partial)
        let mismatches: [FrameTechnicalQualityEvidence] = [
            .init(frameID: "old", capturedAt: capturedAt, measurement: capture.evidence.measurement),
            .init(frameID: frameId, capturedAt: capturedAt.addingTimeInterval(-1),
                  measurement: capture.evidence.measurement),
            .init(frameID: frameId, capturedAt: capturedAt, measurement: .measured(.empty)),
            .init(frameID: frameId, capturedAt: capturedAt, measurement: .unavailable(.notMeasured))
        ]
        for consumed in mismatches {
            let rejected = SemanticEvalTechnicalMeasurementMetadata(
                evidence: consumed, snapshot: makeTechnicalSnapshot(), debugCapture: capture)
            XCTAssertNil(rejected.pixelDiagnostics)
            let encoded = try XCTUnwrap(JSONSerialization.jsonObject(
                with: JSONEncoder().encode(rejected)) as? [String: Any])
            XCTAssertNil(encoded["pixelDiagnostics"], "Unknown diagnostics must remain absent")
        }
        let supplied = SemanticEvalTechnicalMeasurementMetadata(
            evidence: capture.evidence, snapshot: makeTechnicalSnapshot())
        XCTAssertNil(supplied.pixelDiagnostics, "Same measurement without capture has no raw diagnostics")
        XCTAssertEqual(supplied.signal, matching.signal)
        XCTAssertEqual(supplied.numericFeatures, matching.numericFeatures)
        var decoratedJSON = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(matching)) as? [String: Any])
        XCTAssertNotNil(decoratedJSON.removeValue(forKey: "pixelDiagnostics"))
        let previousJSON = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(supplied)) as? [String: Any])
        XCTAssertTrue(NSDictionary(dictionary: decoratedJSON).isEqual(to: previousJSON),
                      "Diagnostic decoration must preserve all prior metadata")
        XCTAssertNil(try JSONDecoder().decode(SemanticEvalTechnicalMeasurementMetadata.self,
            from: JSONSerialization.data(withJSONObject: previousJSON)).pixelDiagnostics)
    }

    func testCapturedPixelDiagnosticsSurviveMutationOfOriginalPixels() throws {
        let pixels = try makeIntegrationPixelBuffer(gray: 0)
        let analyzer = TechnicalQualityAnalyzer()
        let capture = analyzer.debugMeasurement(pixelBuffer: pixels, frameID: frameId, capturedAt: capturedAt)
        XCTAssertEqual(capture.diagnostics?.metrics.meanLuma, 0)
        XCTAssertEqual(CVPixelBufferLockBaseAddress(pixels, []), kCVReturnSuccess)
        do {
            defer { CVPixelBufferUnlockBaseAddress(pixels, []) }
            let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels))
            base.initializeMemory(as: UInt8.self, repeating: 255,
                                  count: CVPixelBufferGetBytesPerRow(pixels) * CVPixelBufferGetHeight(pixels))
        }
        let changed = analyzer.debugMeasurement(pixelBuffer: pixels, frameID: frameId, capturedAt: capturedAt)
        XCTAssertEqual(try XCTUnwrap(changed.diagnostics).metrics.meanLuma, 1, accuracy: 1e-12)
        XCTAssertNotEqual(changed.evidence.measurement, capture.evidence.measurement)
        for mode in [AnalysisMode.live, .pause] {
            let retained = SemanticEvalTechnicalMeasurementMetadata(
                evidence: capture.evidence, snapshot: makeTechnicalSnapshot(mode: mode), debugCapture: capture)
            XCTAssertEqual(retained.pixelDiagnostics, capture.diagnostics)
            XCTAssertEqual(retained.pixelDiagnostics?.metrics.meanLuma, 0)
            XCTAssertEqual(retained.signal, capture.evidence.measurement.signal)
            let wrongCapture = SemanticEvalTechnicalMeasurementMetadata(
                evidence: capture.evidence, snapshot: makeTechnicalSnapshot(mode: mode), debugCapture: changed)
            XCTAssertNil(wrongCapture.pixelDiagnostics,
                         "Same frame/time must not attach diagnostics for another consumed measurement")
        }
    }

    @MainActor
    func testTechnicalNumericExportUsesConsumedEvidenceInsteadOfRescanningPixels() async throws {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, visualEvidenceProvider: nil,
                                        neuralEvidenceService: nil, liveHybridFusionEnabled: false,
                                        demoLiveCoachEnabled: false)
        let pixels = try makeIntegrationPixelBuffer(gray: 1)
        let rescanned = try XCTUnwrap(TechnicalQualityAnalyzer().measurement(pixelBuffer: pixels).signal)
        XCTAssertTrue(rescanned.issues.contains { $0.type == .overexposure && $0.isDominant },
                      "The alternate pixels must differ causally from the supplied measurement")
        let supplied = TechnicalQualitySignal(issues: [
            .init(type: .underexposure, actionType: .increaseExposure,
                  confidence: 0.42, severity: 0.7, isDominant: false)
        ])
        for mode in [AnalysisMode.live, .pause] {
            let snapshot = makeTechnicalSnapshot(mode: mode)
            for measurement in [TechnicalQualityMeasurement.measured(.empty),
                                .measured(supplied),
                                .partial(supplied, reason: .sharpnessCauseUnobservable, detail: .init(
                                    sampleWidth: 96, sampleHeight: 96, meanLuma: 0.2,
                                    gradientMean: 0, gradientVariance: 0)),
                                .unavailable(.pixelBufferLockFailed)] {
                let evidence = FrameTechnicalQualityEvidence(
                    frameID: frameId, capturedAt: capturedAt, measurement: measurement)
                let actual = pipeline.testingTechnicalMeasurementExport(
                    snapshot: snapshot, evidence: evidence, pixelBuffer: pixels)
                XCTAssertEqual(actual.metadata.signal, measurement.signal)
                XCTAssertEqual(actual.metadata.sourceFrameId, frameId)
                XCTAssertEqual(actual.metadata.sourceCapturedAt, capturedAt)
                let technicalNumbers = actual.numericFeatures.filter { $0.key.hasPrefix("technical_") }
                XCTAssertEqual(technicalNumbers, actual.metadata.numericFeatures)
                switch measurement {
                case .measured(let signal):
                    XCTAssertEqual(actual.metadata.status, .measured)
                    XCTAssertEqual(technicalNumbers["technical_issue_count"], Double(signal.issues.count))
                    XCTAssertEqual(technicalNumbers["technical_dominant_count"], 0)
                    XCTAssertEqual(technicalNumbers["technical_max_severity"], signal.issues.first?.severity ?? 0)
                    XCTAssertEqual(technicalNumbers["technical_max_confidence"], signal.issues.first?.confidence ?? 0)
                case .unavailable:
                    XCTAssertEqual(actual.metadata.status, .unavailable)
                    XCTAssertEqual(actual.metadata.unavailableReason,
                                   TechnicalQualityUnavailableReason.pixelBufferLockFailed.rawValue)
                    XCTAssertTrue(technicalNumbers.isEmpty, "A fresh rescan cannot turn unavailable into measured")
                case .partial(let signal, let reason, let detail):
                    XCTAssertEqual(actual.metadata.status, .partial)
                    XCTAssertEqual(actual.metadata.unavailableReason, reason.rawValue)
                    XCTAssertEqual(actual.metadata.imageDetail, detail)
                    XCTAssertEqual(technicalNumbers["technical_issue_count"], Double(signal.issues.count))
                    XCTAssertEqual(technicalNumbers["technical_max_severity"], 0.7)
                    XCTAssertEqual(technicalNumbers["technical_max_confidence"], 0.42)
                }
            }
        }
        await pipeline.releaseAndWait()
    }

    @MainActor
    func testLightweightReplayExportsMatchingMetadataForBothRows() async throws {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, visualEvidenceProvider: nil)
        let capture = Date(timeIntervalSince1970: 1_768_500_601)
        let replay = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "metadata-lightweight", filename: "metadata-lightweight.bgra",
            pixelBuffer: try makeIntegrationPixelBuffer(), orientation: .up,
            capturedAt: capture, options: .lightweightTest
        )

        XCTAssertEqual(replay.frameId, "semantic_eval_metadata-lightweight")
        XCTAssertEqual(replay.rows.map(\.mode), ["live", "pause"])
        for row in replay.rows {
            let metadata = try assertIntegrationIdentity(row, replay: replay, capturedAt: capture)
            XCTAssertEqual(row.runtimeClaim, .testFixture)
            XCTAssertEqual(metadata.compactNeural.status, .notRequested)
            XCTAssertNil(metadata.compactNeural.metadata)
            XCTAssertNil(metadata.compactNeural.headStatuses)
            let still = try XCTUnwrap(metadata.stillFeatures)
            XCTAssertEqual(still.detr.invocation, .notRequested)
            XCTAssertEqual(still.nima.invocation, .notRequested)
            XCTAssertNil(still.detr.detectionCount)
            XCTAssertNil(still.detr.modelLoaded)
            XCTAssertNil(still.nima.score10)
            XCTAssertNil(still.nima.modelLoaded)
        }
        XCTAssertEqual(replay.liveRow.debugModelExecution?.stillFeatures,
                       replay.pauseRow.debugModelExecution?.stillFeatures)
        let livePixels = try XCTUnwrap(replay.liveRow.debugTechnicalMeasurement?.pixelDiagnostics)
        XCTAssertEqual(livePixels.metrics.sourceWidth, 96)
        XCTAssertEqual(livePixels.metrics.sourceHeight, 96)
        XCTAssertEqual(replay.pauseRow.debugTechnicalMeasurement?.pixelDiagnostics, livePixels,
                       "Both real row builders must consume the one captured pixel observation")
        try attachIntegrationReplay(replay, name: "lightweight-model-execution")
    }

    @MainActor
    func testDarkPixelReplayPreservesExposureAndPartialCoverageWithoutNoiseAdvice() async throws {
        let pipeline = AnalysisPipeline(reasoningProvider: nil, visualEvidenceProvider: nil,
                                        neuralEvidenceService: nil, liveHybridFusionEnabled: false,
                                        demoLiveCoachEnabled: false)
        for gray in [CGFloat(0), CGFloat(34.0 / 255.0)] {
            let capture = Date(timeIntervalSince1970: 1_768_500_603)
            let replay = await pipeline.testingReplayStillImageForSemanticEval(
                recordId: "noise-unsupported-\(gray)", filename: "controlled-dark.bgra",
                pixelBuffer: try makeIntegrationPixelBuffer(gray: gray), orientation: .up,
                capturedAt: capture, options: .lightweightTest
            )
            for row in replay.rows {
                let models = try assertIntegrationIdentity(row, replay: replay, capturedAt: capture)
                XCTAssertEqual(models.compactNeural.status, .notRequested)
                XCTAssertEqual(models.stillFeatures?.detr.invocation, .notRequested)
                XCTAssertEqual(models.stillFeatures?.nima.invocation, .notRequested)
                let technical = try XCTUnwrap(row.debugTechnicalMeasurement)
                XCTAssertEqual(technical.status, .partial)
                XCTAssertEqual(technical.unavailableReason, "sharpnessCauseUnobservable")
                let signal = try XCTUnwrap(technical.signal)
                XCTAssertEqual(signal.issues.count, 1)
                XCTAssertEqual(signal.issues.first?.type, .underexposure)
                XCTAssertFalse(signal.issues.contains { $0.type == .noise })
                XCTAssertEqual(row.debugNumericFeatures["technical_issue_count"], 1)
                XCTAssertEqual(row.debugNumericFeatures["technical_dominant_count"], 0)
                XCTAssertTrue(row.futureActions.contains(TechnicalQualityActionType.increaseExposure.rawValue))
                XCTAssertFalse(row.futureActions.contains(TechnicalQualityActionType.reduceIsoNoise.rawValue))
                XCTAssertFalse(row.semanticActions.contains(SemanticActionType.keepCurrentSetup.rawValue))
                XCTAssertNotEqual(row.debugSemanticLabels["verdict"], FrameVerdict.good.rawValue)
                let metrics = try XCTUnwrap(technical.pixelDiagnostics?.metrics)
                XCTAssertEqual(metrics.meanLuma, Double(gray), accuracy: 1.0 / 255.0)
                XCTAssertEqual(metrics.gradientMean, 0, accuracy: 1e-12)
                XCTAssertEqual(metrics.gradientVariance, 0, accuracy: 1e-12)
            }
            XCTAssertEqual(replay.liveRow.debugTechnicalMeasurement?.pixelDiagnostics,
                           replay.pauseRow.debugTechnicalMeasurement?.pixelDiagnostics)
            try attachIntegrationReplay(replay, name: "dark-pixel-noise-unobserved-\(gray)")
        }
        await pipeline.releaseAndWait()
    }

    @MainActor
    func testBundledFullReplayExportsActualModelObservationsForBothRows() async throws {
        let store = DeviceBenchmarkArtifactStore(runId: "model-metadata-input-\(UUID().uuidString)")
        let pack = try store.resourcePackURL(packId: "camera_device_benchmark_pack_v1")
        // This integration input must come from the app's production resource resolver.
        // Do not substitute a repository path or an existing user cache.
        guard pack.standardizedFileURL.path.hasPrefix(Bundle.main.bundleURL.standardizedFileURL.path + "/") else {
            XCTFail("Expected the benchmark input pack in the app bundle.")
            return
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.rootURL.path))
        let imageURL = pack.appendingPathComponent("images/001.jpg")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                                  "Required bundled benchmark image is unavailable.")
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))

        // Retain real default compact Core ML, DETR, NIMA and Vision implementations.
        // Explicit nil reasoning/visual providers prevent environment-selected VLM/network calls.
        let pipeline = AnalysisPipeline(reasoningProvider: nil, visualEvidenceProvider: nil)
        let capture = Date(timeIntervalSince1970: 1_768_500_602)
        let replay = await pipeline.testingReplayStillImageForSemanticEval(
            recordId: "metadata-bundled-001", filename: imageURL.lastPathComponent,
            pixelBuffer: try makeIntegrationPixelBuffer(image: image), orientation: .up,
            capturedAt: capture, options: .fullRuntime
        )

        XCTAssertEqual(replay.frameId, "semantic_eval_metadata-bundled-001")
        XCTAssertEqual(replay.rows.map(\.mode), ["live", "pause"])
        for row in replay.rows {
            let metadata = try assertIntegrationIdentity(row, replay: replay, capturedAt: capture)
            // This identifies the path; it is not an assertion that a model succeeded.
            XCTAssertEqual(row.runtimeClaim, .realRuntimeStillReplay)
            switch metadata.compactNeural.status {
            case .disabled:
                XCTAssertNil(metadata.compactNeural.metadata)
                XCTAssertNil(metadata.compactNeural.headStatuses)
            case .executed, .failed, .policySkipped:
                let runtime = try XCTUnwrap(metadata.compactNeural.metadata)
                XCTAssertEqual(runtime.frameId, replay.frameId)
                XCTAssertEqual(runtime.mode.rawValue, row.mode)
                XCTAssertEqual(runtime.providerKind, .coremlLocal)
                XCTAssertEqual(runtime.inferenceTarget, .onDevice)
                XCTAssertNotNil(metadata.compactNeural.headStatuses)
            case .notRequested, .unknown, .identityMismatch:
                XCTFail("Full replay must export its actual returned compact outcome: \(metadata.compactNeural.status)")
            }
            let still = try XCTUnwrap(metadata.stillFeatures)
            switch still.detr.invocation {
            case .callbackReceived:
                XCTAssertEqual(still.detr.modelLoaded, true)
                if let failure = still.detr.failureReason {
                    XCTAssertNotEqual(failure, .modelUnavailable)
                    XCTAssertNil(still.detr.detectionCount)
                    XCTAssertEqual(still.detr.outputEvidence, .unknown)
                } else {
                    let count = try XCTUnwrap(still.detr.detectionCount)
                    XCTAssertGreaterThanOrEqual(count, 0)
                    XCTAssertEqual(still.detr.outputEvidence, .available,
                                   "A successfully measured empty result is still available")
                }
            case .modelUnavailable:
                XCTAssertEqual(still.detr.modelLoaded, false)
                XCTAssertNil(still.detr.detectionCount)
                XCTAssertEqual(still.detr.outputEvidence, .unknown)
                XCTAssertEqual(still.detr.failureReason, .modelUnavailable)
            case .notRequested, .notInvoked:
                XCTFail("Full replay must retain the real detector availability/callback observation.")
            }
            XCTAssertEqual(still.nima.invocation, .callbackReceived)
            if let score = still.nima.score10 {
                XCTAssertTrue(score.isFinite)
                XCTAssertEqual(still.nima.modelLoaded, true)
                XCTAssertEqual(still.nima.outputEvidence, .available)
            } else {
                XCTAssertNil(still.nima.modelLoaded)
                XCTAssertEqual(still.nima.outputEvidence, .unknown)
            }
            XCTAssertNoThrow(try JSONEncoder().encode(metadata))
        }
        XCTAssertEqual(replay.liveRow.debugModelExecution?.stillFeatures,
                       replay.pauseRow.debugModelExecution?.stillFeatures)
        try attachIntegrationReplay(replay, name: "bundled-model-execution")
    }

    private func attachIntegrationReplay(_ replay: SemanticEvalStillImageReplayResult,
                                         name: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(replay.rows),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertIntegrationIdentity(_ row: SemanticEvalCandidateOutput,
                                           replay: SemanticEvalStillImageReplayResult,
                                           capturedAt: Date,
                                           file: StaticString = #filePath,
                                           line: UInt = #line) throws -> SemanticEvalModelExecutionMetadata {
        let metadata = try XCTUnwrap(row.debugModelExecution, file: file, line: line)
        XCTAssertEqual(row.recordId, replay.recordId, file: file, line: line)
        XCTAssertEqual(row.filename, replay.filename, file: file, line: line)
        XCTAssertEqual(metadata.frameId, replay.frameId, file: file, line: line)
        XCTAssertEqual(metadata.mode.rawValue, row.mode, file: file, line: line)
        XCTAssertEqual(metadata.capturedAt, capturedAt, file: file, line: line)
        XCTAssertTrue(metadata.stillFeatureIdentityMatches, file: file, line: line)
        let still = try XCTUnwrap(metadata.stillFeatures, file: file, line: line)
        XCTAssertEqual(still.frameId, replay.frameId, file: file, line: line)
        XCTAssertEqual(still.capturedAt, capturedAt, file: file, line: line)
        XCTAssertEqual(metadata.composition.invocation, .notInvoked, file: file, line: line)
        XCTAssertEqual(metadata.composition.outputEvidence, .unknown, file: file, line: line)
        XCTAssertNil(metadata.composition.modelLoaded, file: file, line: line)
        let technical = try XCTUnwrap(row.debugTechnicalMeasurement, file: file, line: line)
        XCTAssertEqual(technical.frameId, replay.frameId, file: file, line: line)
        XCTAssertEqual(technical.capturedAt, capturedAt, file: file, line: line)
        XCTAssertEqual(technical.sourceFrameId, replay.frameId, file: file, line: line)
        XCTAssertEqual(technical.sourceCapturedAt, capturedAt, file: file, line: line)
        XCTAssertTrue(technical.frameIdentityMatches, file: file, line: line)
        let expectedNumbers: [String: Double]
        switch technical.status {
        case .measured, .partial:
            let signal = try XCTUnwrap(technical.signal, file: file, line: line)
            if technical.status == .measured {
                XCTAssertNil(technical.unavailableReason, file: file, line: line)
                XCTAssertNil(technical.imageDetail, file: file, line: line)
            } else {
                XCTAssertEqual(technical.unavailableReason, "sharpnessCauseUnobservable", file: file, line: line)
                XCTAssertNotNil(technical.imageDetail, file: file, line: line)
            }
            expectedNumbers = [
                "technical_issue_count": Double(signal.issues.count),
                "technical_dominant_count": Double(signal.issues.filter(\.isDominant).count),
                "technical_max_severity": signal.issues.map(\.severity).max() ?? 0,
                "technical_max_confidence": signal.issues.map(\.confidence).max() ?? 0
            ]
        case .unavailable:
            XCTAssertNil(technical.signal, file: file, line: line)
            XCTAssertNotNil(technical.unavailableReason, file: file, line: line)
            expectedNumbers = [:]
        }
        XCTAssertEqual(row.debugNumericFeatures.filter { $0.key.hasPrefix("technical_") },
                       expectedNumbers, file: file, line: line)
        return metadata
    }

    private func makeIntegrationPixelBuffer(image: CGImage? = nil, gray: CGFloat = 0.5) throws -> CVPixelBuffer {
        let width = image?.width ?? 96
        let height = image?.height ?? 96
        var allocated: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                        kCVPixelFormatType_32BGRA, attributes as CFDictionary, &allocated)
        XCTAssertEqual(status, kCVReturnSuccess)
        let buffer = try XCTUnwrap(allocated)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let context = try XCTUnwrap(CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ))
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        if let image {
            context.draw(image, in: bounds)
        } else {
            context.setFillColor(gray: gray, alpha: 1)
            context.fill(bounds)
        }
        return buffer
    }
}
#endif
