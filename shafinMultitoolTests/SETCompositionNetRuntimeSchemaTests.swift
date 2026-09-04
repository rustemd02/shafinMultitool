//
//  SETCompositionNetRuntimeSchemaTests.swift
//  shafinMultitoolTests
//
//  M2-017 CameraNeuralRuntimeOwner: the typed SETCompositionNet boundary
//  rejects NaN, missing heads, wrong frame/generation, and mismatched ROI;
//  explicit unavailable/failed states carry no scores.
//

import XCTest
import CoreVideo
@testable import shafinMultitool

final class SETCompositionNetRuntimeSchemaTests: XCTestCase {

    private var pixelBuffer: CVPixelBuffer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, 8, 8, kCVPixelFormatType_32BGRA, nil, &buffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        pixelBuffer = buffer
    }

    private func makeRequest(roiStrategy: NeuralEvidenceROIStrategy = .subjectCropOnly,
                             subjectRegion: NormalizedRect? = NormalizedRect(x: 0.3, y: 0.3, width: 0.3, height: 0.4),
                             frameId: String = "frame-1") -> NeuralEvidenceProviderRequest {
        NeuralEvidenceProviderRequest(
            frameId: frameId,
            mode: .live,
            pixelBuffer: pixelBuffer,
            orientation: .up,
            roiStrategy: roiStrategy,
            primarySubjectRegion: subjectRegion,
            thresholdProfile: "live_default"
        )
    }

    private func makeOutput(frameId: String = "frame-1",
                            strategy: NeuralEvidenceROIStrategy = .subjectCropOnly,
                            subjectRegion: NormalizedRect? = NormalizedRect(x: 0.3, y: 0.3, width: 0.3, height: 0.4),
                            scalarScores: [Double]? = nil) -> NeuralEvidenceProviderOutput {
        NeuralEvidenceProviderOutput(
            scalarScores: scalarScores ?? Array(repeating: 0.4, count: NeuralEvidenceProviderOutput.scalarHeadCount),
            scalarConfidences: Array(repeating: 0.6, count: NeuralEvidenceProviderOutput.scalarHeadCount),
            supportingSignalScores: Array(
                repeating: Array(repeating: 0.5, count: NeuralEvidenceProviderOutput.supportingSignalCount),
                count: NeuralEvidenceProviderOutput.scalarHeadCount
            ),
            shotTypeAffinities: Array(repeating: 0.5, count: NeuralEvidenceProviderOutput.shotTypeCount),
            shotTypeConfidence: 0.7,
            actualROIStrategy: strategy
        )
    }

    private func makeAvailableOutput(request: NeuralEvidenceProviderRequest,
                                     generation: UInt64 = 5,
                                     strategy: NeuralEvidenceROIStrategy = .subjectCropOnly,
                                     frameId: String = "frame-1",
                                     output: (NeuralEvidenceProviderOutput)? = nil) -> SETCompositionNetOutput {
        .available(
            request: request,
            generation: generation,
            output: output ?? makeOutput(frameId: frameId, strategy: strategy)
        )
    }

    // MARK: - Valid boundary

    func testAvailableOutputValidatesCleanAgainstMatchingInput() {
        let request = makeRequest()
        let output = makeAvailableOutput(request: request, generation: 5)
        let input = SETCompositionNetInput(request: request, descriptor: descriptor, generation: 5)

        XCTAssertTrue(input.subjectROI != nil)
        let errors = output.validate(request: request, generation: 5)
        XCTAssertTrue(errors.isEmpty, "a consistent boundary must validate cleanly, got: \(errors)")
        XCTAssertEqual(output.frameId, input.frameId)
        XCTAssertEqual(output.generation, input.generation)
    }

    private var descriptor: NeuralEvidenceProviderDescriptor {
        NeuralEvidenceProviderDescriptor(
            providerKind: .coremlLocal,
            inferenceTarget: .onDevice,
            modelFamily: "SETCompositionNet",
            modelVersion: "v1",
            preprocessingVersion: "p1",
            thresholdProfileLive: "live_default",
            thresholdProfilePause: "pause_default",
            bundleVersion: "b1"
        )
    }

    // MARK: - NaN / non-finite rejection

    func testNaNInAnyHeadIsRejected() {
        var scores = Array(repeating: 0.4, count: NeuralEvidenceProviderOutput.scalarHeadCount)
        scores[2] = .nan
        let request = makeRequest()
        let output = SETCompositionNetOutput.available(
            request: request, generation: 5, output: makeOutput(scalarScores: scores)
        )
        let errors = output.validate(request: request, generation: 5)
        XCTAssertFalse(errors.isEmpty, "NaN logits must be rejected")
        XCTAssertTrue(errors.contains { $0.contains("not finite") })
    }

    func testNaNInContinuousTargetsIsRejected() throws {
        let request = makeRequest()
        let valid = makeAvailableOutput(request: request, generation: 5)
        var targets = valid.continuousTargets
        targets[.subjectScale] = .infinity
        let output = try makeCustomOutput(from: valid, continuousTargets: targets)
        XCTAssertFalse(output.validate(request: request, generation: 5).isEmpty)
    }

    func testOutOfRangeScoresAreRejected() throws {
        let request = makeRequest()
        let valid = makeAvailableOutput(request: request, generation: 5)
        let output = try makeCustomOutput(from: valid, riskScore: 1.5, abstentionScore: -0.2, goodFrameScore: .nan)
        let errors = output.validate(request: request, generation: 5)
        XCTAssertGreaterThanOrEqual(errors.count, 3, "all three range violations must be rejected: \(errors)")
        XCTAssertTrue(errors.contains { $0.contains("riskScore") })
        XCTAssertTrue(errors.contains { $0.contains("abstentionScore") })
        XCTAssertTrue(errors.contains { $0.contains("goodFrameScore") })
    }

    // MARK: - Missing heads

    func testMissingRequiredHeadIsRejected() throws {
        let request = makeRequest()
        let valid = makeAvailableOutput(request: request, generation: 5)
        var logits = valid.issueActionLogits
        logits.removeValue(forKey: .lightingQuality)
        let output = try makeCustomOutput(from: valid, issueActionLogits: logits)
        let errors = output.validate(request: request, generation: 5)
        XCTAssertTrue(errors.contains { $0.contains("lighting_quality") },
                      "missing heads must be rejected: \(errors)")
    }

    private func makeCustomOutput(
        from base: SETCompositionNetOutput,
        issueActionLogits: [EvidenceHeadId: Double]? = nil,
        continuousTargets: [SupportingSignalTag: Double]? = nil,
        riskScore: Double? = nil,
        abstentionScore: Double? = nil,
        goodFrameScore: Double? = nil,
        subjectROI: NormalizedRect?? = nil,
        frameId: String? = nil
    ) throws -> SETCompositionNetOutput {
        SETCompositionNetOutput(
            status: base.status,
            frameId: frameId ?? base.frameId,
            generation: base.generation,
            mode: base.mode,
            subjectROI: subjectROI ?? base.subjectROI,
            roiStrategy: base.roiStrategy,
            issueActionLogits: issueActionLogits ?? base.issueActionLogits,
            continuousTargets: continuousTargets ?? base.continuousTargets,
            shotTypeAffinities: base.shotTypeAffinities,
            riskScore: riskScore ?? base.riskScore,
            abstentionScore: abstentionScore ?? base.abstentionScore,
            goodFrameScore: goodFrameScore ?? base.goodFrameScore
        )
    }

    // MARK: - Wrong frame / generation

    func testWrongFrameIdIsRejected() throws {
        // The provider reports its OWN frame id; a corrupted/late response
        // claiming another frame must be rejected by validation.
        let request = makeRequest(frameId: "frame-1")
        let base = makeAvailableOutput(request: request, generation: 5)
        let output = try makeCustomOutput(from: base, frameId: "frame-2")
        XCTAssertTrue(
            output.validate(request: request, generation: 5).contains { $0.contains("frameId") }
        )
    }

    func testWrongGenerationIsRejected() {
        let request = makeRequest()
        let output = makeAvailableOutput(request: request, generation: 5)
        let errors = output.validate(request: request, generation: 6)
        XCTAssertTrue(errors.contains { $0.contains("generation") },
                      "a stale-generation output must be rejected")
    }

    // MARK: - ROI mismatch

    func testMismatchedROIStrategyIsRejected() {
        let request = makeRequest(roiStrategy: .subjectCropOnly)
        let output = makeAvailableOutput(request: request, generation: 5,
                                         strategy: .fullFrameOnly)
        let errors = output.validate(request: request, generation: 5)
        XCTAssertTrue(errors.contains { $0.contains("ROI") },
                      "a returned ROI strategy that mismatches the request must be rejected")
    }

    func testMissingSubjectROIProvenanceIsRejected() throws {
        let request = makeRequest(roiStrategy: .subjectCropOnly, subjectRegion: nil)
        let valid = makeAvailableOutput(request: request, generation: 5)
        let output = try makeCustomOutput(from: valid, subjectROI: nil)
        let errors = output.validate(request: request, generation: 5)
        XCTAssertTrue(errors.contains { $0.contains("ROI") },
                      "a subject-ROI request must produce ROI provenance")
    }

    // MARK: - Explicit unavailable / failed states

    func testUnavailableStateCarriesNoScoresAndValidatesClean() {
        let request = makeRequest()
        let output = SETCompositionNetOutput.unavailable(request: request, generation: 5)
        XCTAssertTrue(output.issueActionLogits.isEmpty)
        XCTAssertTrue(output.validate(request: request, generation: 5).isEmpty,
                      "unavailable is an honest state, not an error")
    }

    func testFailedStateCarriesTheReason() {
        let request = makeRequest()
        let output = SETCompositionNetOutput.failed(
            .runtimeTimeout, request: request, generation: 5
        )
        XCTAssertEqual(output.status, .failed(.runtimeTimeout))
        XCTAssertTrue(output.issueActionLogits.isEmpty)
        XCTAssertTrue(output.validate(request: request, generation: 5).isEmpty)
    }
}
