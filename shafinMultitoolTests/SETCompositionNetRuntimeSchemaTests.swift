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
import CryptoKit
import Foundation
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

    // MARK: - Frozen M4 v1 input/output contract

    private var v1Descriptor: NeuralEvidenceProviderDescriptor {
        NeuralEvidenceProviderDescriptor(
            providerKind: .coremlLocal,
            inferenceTarget: .onDevice,
            modelFamily: "SETCompositionNet",
            modelVersion: "v1",
            preprocessingVersion: SETCompositionNetContract.preprocessingVersion,
            thresholdProfileLive: "live_default",
            thresholdProfilePause: "pause_default",
            bundleVersion: "setcompositionnet.bundle.v1"
        )
    }

    private func makeV1Tensors(
        roi: SETCompositionNetROI = SETCompositionNetROI(x: 0.3, y: 0.3, width: 0.3, height: 0.4),
        inputContractVersion: String = SETCompositionNetContract.inputContractVersion,
        preprocessingVersion: String = SETCompositionNetContract.preprocessingVersion,
        featureVersion: String = SETCompositionNetContract.featureVersion,
        fullFrameRGB: [Double]? = nil,
        subjectCropRGB: [Double]? = nil,
        roiMask: [Double]? = nil,
        scalarFeatures: [Double]? = nil,
        missingFeatureMask: [Double]? = nil
    ) -> SETCompositionNetInputTensors {
        let defaultROI = SETCompositionNetContract.roiMask(for: roi)
        var defaultScalars = Array(
            repeating: 0.25,
            count: SETCompositionNetContract.scalarFeatureCount
        )
        let scalarIndexes = Dictionary(
            uniqueKeysWithValues: SETCompositionNetContract.featureNames.enumerated().map { ($1, $0) }
        )
        defaultScalars[scalarIndexes["roi_present"]!] = roi.present ? 1.0 : 0.0
        defaultScalars[scalarIndexes["roi_area_ratio"]!] = roi.present ? roi.width * roi.height : 0.0
        defaultScalars[scalarIndexes["roi_mask_coverage"]!] = roi.present
            ? defaultROI.reduce(0.0, +) / Double(defaultROI.count)
            : 0.0
        defaultScalars[scalarIndexes["orientation_category"]!] = 0.0
        defaultScalars[scalarIndexes["lens_category"]!] = 0.5

        return SETCompositionNetInputTensors(
            inputContractVersion: inputContractVersion,
            preprocessingVersion: preprocessingVersion,
            featureVersion: featureVersion,
            fullFrameRGB: fullFrameRGB ?? Array(
                repeating: 0.25,
                count: SETCompositionNetContract.fullFrameWidth
                    * SETCompositionNetContract.fullFrameHeight * 3
            ),
            subjectCropRGB: subjectCropRGB ?? Array(
                repeating: 0.25,
                count: SETCompositionNetContract.subjectCropWidth
                    * SETCompositionNetContract.subjectCropHeight * 3
            ),
            roi: roi,
            roiMask: roiMask ?? defaultROI,
            scalarFeatures: scalarFeatures ?? defaultScalars,
            missingFeatureMask: missingFeatureMask ?? Array(
                repeating: 0,
                count: SETCompositionNetContract.scalarFeatureCount
            )
        )
    }

    private func makeV1Heads(
        tensors: [String: [Double]]? = nil,
        version: String = SETCompositionNetContract.outputContractVersion
    ) -> SETCompositionNetOutputHeads {
        let defaultTensors = Dictionary(uniqueKeysWithValues:
            SETCompositionNetContract.outputHeadNames.map { name in
                (name, Array(
                    repeating: name.contains("probability") ? 0.25 : 0.1,
                    count: SETCompositionNetContract.outputHeadShapes[name] ?? 0
                ))
            }
        )
        return SETCompositionNetOutputHeads(
            outputContractVersion: version,
            tensors: tensors ?? defaultTensors
        )
    }

    func testV1InputAndAllOutputHeadsValidateAgainstFrozenShapes() {
        let request = makeRequest()
        let tensors = makeV1Tensors()
        let input = SETCompositionNetInput(
            request: request,
            descriptor: v1Descriptor,
            generation: 5,
            tensors: tensors
        )
        XCTAssertTrue(input.validate().isEmpty, "valid v1 input must validate: \(input.validate())")

        let heads = makeV1Heads()
        let output = SETCompositionNetOutput.availableV1(
            request: request,
            generation: 5,
            heads: heads
        )
        XCTAssertTrue(
            output.validate(request: request, generation: 5).isEmpty,
            "valid v1 output must validate: \(output.validate(request: request, generation: 5))"
        )
        XCTAssertEqual(heads.tensors.count, 9)
        XCTAssertEqual(
            SETCompositionNetContract.actionUtilityNames,
            SemanticActionType.allCases.map(\.rawValue)
        )
        XCTAssertFalse(SETCompositionNetContract.actionUtilityNames.contains { $0.hasPrefix("move_frame_") })
        XCTAssertFalse(SETCompositionNetContract.actionUtilityNames.contains("change_angle"))
        XCTAssertFalse(heads.tensors.keys.contains("generated_text"))
        XCTAssertFalse(heads.tensors.keys.contains("arbitrary_object_name"))
    }

    func testV1InputRejectsWrongSizedNonFiniteAndMismatchedROIMask() {
        let request = makeRequest()
        let invalid = makeV1Tensors(
            roi: SETCompositionNetROI(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            fullFrameRGB: [0.2],
            roiMask: [1.0],
            scalarFeatures: [Double.nan]
        )
        let input = SETCompositionNetInput(
            request: request,
            descriptor: v1Descriptor,
            generation: 5,
            tensors: invalid
        )
        let errors = input.validate()
        XCTAssertTrue(errors.contains { $0.contains("fullFrameRGB") })
        XCTAssertTrue(errors.contains { $0.contains("roiMask") })
        XCTAssertTrue(errors.contains { $0.contains("scalarFeatures") })
        XCTAssertTrue(errors.contains { $0.contains("finite") })
    }

    func testV1InputRejectsVersionMismatches() {
        let request = makeRequest()
        let staleTensors = makeV1Tensors(
            inputContractVersion: "setcompositionnet.input.v0",
            preprocessingVersion: "setcompositionnet.preprocessing.v0",
            featureVersion: "setcompositionnet.features.v0"
        )
        let input = SETCompositionNetInput(
            request: request,
            descriptor: v1Descriptor,
            generation: 5,
            tensors: staleTensors
        )
        let errors = input.validate()
        XCTAssertTrue(errors.contains { $0.contains("inputContractVersion") })
        XCTAssertTrue(errors.contains { $0.contains("preprocessingVersion") })
        XCTAssertTrue(errors.contains { $0.contains("featureVersion") })
    }

    func testV1InputRejectsInvalidROIAndNonZeroMissingMask() {
        let request = makeRequest()
        let invalidROI = makeV1Tensors(
            roi: SETCompositionNetROI(x: .nan, y: 0.1, width: 0.2, height: 0.2)
        )
        let input = SETCompositionNetInput(
            request: request,
            descriptor: v1Descriptor,
            generation: 5,
            tensors: invalidROI
        )
        XCTAssertTrue(input.validate().contains { $0.contains("roi") })

        let missingROI = SETCompositionNetROI(x: 0, y: 0, width: 0, height: 0, present: false)
        let invalidMask = makeV1Tensors(
            roi: missingROI,
            roiMask: [1.0] + Array(
                repeating: 0.0,
                count: SETCompositionNetContract.roiMaskWidth
                    * SETCompositionNetContract.roiMaskHeight - 1
            )
        )
        let missingInput = SETCompositionNetInput(
            request: request,
            descriptor: v1Descriptor,
            generation: 5,
            tensors: invalidMask
        )
        XCTAssertTrue(missingInput.validate().contains { $0.contains("roiMask") })

        let nonZeroMissingCrop = makeV1Tensors(
            roi: missingROI,
            subjectCropRGB: [1.0] + Array(
                repeating: 0.0,
                count: SETCompositionNetContract.subjectCropWidth
                    * SETCompositionNetContract.subjectCropHeight * 3 - 1
            )
        )
        let missingCropInput = SETCompositionNetInput(
            request: request,
            descriptor: v1Descriptor,
            generation: 5,
            tensors: nonZeroMissingCrop
        )
        XCTAssertTrue(missingCropInput.validate().contains { $0.contains("zero-filled") })
    }

    func testV1InputRejectsFeatureRangeMissingFillAndROIScalarDrift() {
        let request = makeRequest()
        let roi = SETCompositionNetROI(x: 0.25, y: 0.25, width: 0.5, height: 0.5)

        var outOfRangeScalars = makeV1Tensors(roi: roi).scalarFeatures
        outOfRangeScalars[15] = 2.0 // signed saliency balance is bounded [-1, 1]
        let outOfRange = SETCompositionNetInput(
            request: request,
            descriptor: v1Descriptor,
            generation: 5,
            tensors: makeV1Tensors(roi: roi, scalarFeatures: outOfRangeScalars)
        )
        XCTAssertTrue(outOfRange.validate().contains { $0.contains("saliency_left_right_balance") })

        var nonZeroMissingScalars = makeV1Tensors(roi: roi).scalarFeatures
        var missingMask = Array(repeating: 0.0, count: SETCompositionNetContract.scalarFeatureCount)
        missingMask[4] = 1.0
        nonZeroMissingScalars[4] = 0.25
        let nonZeroMissing = SETCompositionNetInput(
            request: request,
            descriptor: v1Descriptor,
            generation: 5,
            tensors: makeV1Tensors(
                roi: roi,
                scalarFeatures: nonZeroMissingScalars,
                missingFeatureMask: missingMask
            )
        )
        XCTAssertTrue(nonZeroMissing.validate().contains { $0.contains("fill value") })

        var invalidCategoricalScalars = makeV1Tensors(roi: roi).scalarFeatures
        invalidCategoricalScalars[31] = 0.25
        invalidCategoricalScalars[33] = 0.8461538461538461
        let invalidCategorical = SETCompositionNetInput(
            request: request,
            descriptor: v1Descriptor,
            generation: 5,
            tensors: makeV1Tensors(roi: roi, scalarFeatures: invalidCategoricalScalars)
        )
        let categoricalErrors = invalidCategorical.validate()
        XCTAssertTrue(categoricalErrors.contains { $0.contains("orientation_category") && $0.contains("unsupported") })
        XCTAssertTrue(categoricalErrors.contains { $0.contains("lens_category") && $0.contains("unsupported") })

        var driftedScalars = makeV1Tensors(roi: roi).scalarFeatures
        driftedScalars[36] = 0.1
        let roiDrift = SETCompositionNetInput(
            request: request,
            descriptor: v1Descriptor,
            generation: 5,
            tensors: makeV1Tensors(roi: roi, scalarFeatures: driftedScalars)
        )
        XCTAssertTrue(roiDrift.validate().contains { $0.contains("roi_area_ratio") })
    }

    func testV1OutputRejectsMissingWrongSizedNonFiniteUnsupportedAndVersionedHeads() {
        let request = makeRequest()
        var raw = makeV1Heads().tensors
        raw.removeValue(forKey: "issue_logits")
        raw["embedding"] = [Double](repeating: .infinity, count: 2)
        raw["continuous_target_deltas"] = [2.0, 0.0, 0.0, 0.0, 0.0]
        raw["unsupported_head"] = [0.1]
        let staleHeads = makeV1Heads(tensors: raw, version: "setcompositionnet.output.v0")
        let output = SETCompositionNetOutput.availableV1(
            request: request,
            generation: 5,
            heads: staleHeads
        )
        let errors = output.validate(request: request, generation: 5)
        XCTAssertTrue(errors.contains { $0.contains("missing heads") })
        XCTAssertTrue(errors.contains { $0.contains("unsupported heads") })
        XCTAssertTrue(errors.contains { $0.contains("embedding") && $0.contains("128 values") })
        XCTAssertTrue(errors.contains { $0.contains("finite") })
        XCTAssertTrue(errors.contains { $0.contains("outputContractVersion") })
        XCTAssertTrue(errors.contains { $0.contains("continuous_target_deltas") && $0.contains("[-1, 1]") })
    }

    func testV1OutputRejectsEmbedding64AndRisk99Mutations() {
        let request = makeRequest()
        var raw = makeV1Heads().tensors
        raw["embedding"] = Array(repeating: 0.1, count: 64)
        raw["risk_probability"] = [99.0]
        let output = SETCompositionNetOutput.availableV1(
            request: request,
            generation: 5,
            heads: makeV1Heads(tensors: raw)
        )
        let errors = output.validate(request: request, generation: 5)
        XCTAssertTrue(errors.contains { $0.contains("embedding") && $0.contains("128 values") })
        XCTAssertTrue(errors.contains { $0.contains("risk_probability") && $0.contains("[0, 1]") })
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

final class SETCompositionNetParityTests: XCTestCase {
    func testMetalContractPreprocessorDimensionsAndRGBOrder() {
        var sourceBuffer: CVPixelBuffer?
        XCTAssertEqual(
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                4,
                4,
                kCVPixelFormatType_32BGRA,
                nil,
                &sourceBuffer
            ),
            kCVReturnSuccess
        )
        guard let sourceBuffer else {
            return XCTFail("synthetic source buffer must be created")
        }
        XCTAssertEqual(CVPixelBufferLockBaseAddress(sourceBuffer, []), kCVReturnSuccess)
        if let baseAddress = CVPixelBufferGetBaseAddress(sourceBuffer) {
            let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
            for row in 0..<4 {
                for column in 0..<4 {
                    let index = row * CVPixelBufferGetBytesPerRow(sourceBuffer) + column * 4
                    bytes[index] = 2       // B
                    bytes[index + 1] = 1   // G
                    bytes[index + 2] = 0   // R
                    bytes[index + 3] = 255 // alpha, discarded
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(sourceBuffer, [])

        let roi = SETCompositionNetROI(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let preprocessor = MetalPreprocessor()
        guard let tensors = preprocessor.setCompositionNetPixelBuffers(
            from: sourceBuffer,
            orientation: .up,
            roi: roi
        ) else {
            return XCTFail("contract preprocessor must produce both tensors")
        }
        XCTAssertEqual(CVPixelBufferGetWidth(tensors.fullFrame), SETCompositionNetContract.fullFrameWidth)
        XCTAssertEqual(CVPixelBufferGetHeight(tensors.fullFrame), SETCompositionNetContract.fullFrameHeight)
        XCTAssertEqual(CVPixelBufferGetWidth(tensors.subjectCrop), SETCompositionNetContract.subjectCropWidth)
        XCTAssertEqual(CVPixelBufferGetHeight(tensors.subjectCrop), SETCompositionNetContract.subjectCropHeight)
        guard let fullRGB = preprocessor.setCompositionNetRGBValues(from: tensors.fullFrame) else {
            return XCTFail("contract preprocessor must expose logical RGB values")
        }
        XCTAssertEqual(Array(fullRGB.prefix(3)), [0.0, 1.0 / 255.0, 2.0 / 255.0])
    }

    func testSyntheticPythonSwiftParityFixtureHashes() {
        guard let sourceBuffer = makeSyntheticSourceBuffer() else {
            return XCTFail("synthetic source buffer must be created")
        }
        let roi = SETCompositionNetROI(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let preprocessor = MetalPreprocessor()
        guard let tensors = preprocessor.setCompositionNetRGBTensors(
            from: sourceBuffer,
            orientation: .up,
            roi: roi
        ) else {
            return XCTFail("SETCompositionNet production tensors must be created")
        }
        var scalar = (0..<40).map { Double($0) / 39.0 }
        scalar[5] = 0.0
        scalar[17] = 0.0
        scalar[31] = 0.0
        scalar[33] = 0.5
        scalar[35] = 1.0
        scalar[36] = 0.25
        scalar[37] = 0.25
        let missing = (0..<40).map { [5, 17, 31].contains($0) ? 1.0 : 0.0 }

        XCTAssertEqual(
            sha256Float32(tensors.fullFrameRGB),
            "5ddc2c5c5c2dff60f1a2f3adcaaa9f7ff76ce6c4b140ff316a1edcb5f47a62f0"
        )
        XCTAssertEqual(
            sha256Float32(tensors.subjectCropRGB),
            "c95a927a6b5d1d1a902201b29cb37684d5bc02f4edd9f4cf01f3fe40d6b56067"
        )
        XCTAssertEqual(
            sha256Float32(SETCompositionNetContract.roiMask(for: roi)),
            "260802a4865f20a83e157c82bd3f07ab6a0eb13ff759db5c7cac65c54fa3e0bd"
        )
        XCTAssertEqual(
            sha256Float32(scalar),
            "d1106f1b49650a56e647a0e0a9ed83784e6c39483991dc12d1f20c6e7cd29d02"
        )
        XCTAssertEqual(
            sha256Float32(missing),
            "f70651d882c736a535bf6daca943049ddf7e824bd6cc6289a6d83066ad03817e"
        )

        XCTAssertEqual(tensors.fullFrameRGB.count, 320 * 320 * 3)
        XCTAssertEqual(tensors.subjectCropRGB.count, 192 * 192 * 3)
        XCTAssertEqual(tensors.fullFrameRGB[(160 * 320 + 160) * 3], 0.0886029411764706, accuracy: 0.000001)
        XCTAssertEqual(tensors.subjectCropRGB[(96 * 192 + 96) * 3], 0.0886182598039216, accuracy: 0.000001)

        let edgeCases: [(String, SETCompositionNetROI, String)] = [
            (
                "top_left_padded_square_clip",
                SETCompositionNetROI(x: 0.0, y: 0.0, width: 0.2, height: 0.2),
                "6d5ffae613c0ae9afe15391c69ce7eb536176de741e206afb16d3c0d22e1f793"
            ),
            (
                "bottom_right_padded_square_clip",
                SETCompositionNetROI(x: 0.8, y: 0.8, width: 0.2, height: 0.2),
                "4e48b33dabbe3c774bfaeb08687293c30d617e09ad14314523bc0606e79d804f"
            )
        ]
        for (fixtureID, edgeROI, expectedHash) in edgeCases {
            guard let edgeTensors = preprocessor.setCompositionNetRGBTensors(
                from: sourceBuffer,
                orientation: .up,
                roi: edgeROI
            ) else {
                return XCTFail("SETCompositionNet production edge fixture must be created: \(fixtureID)")
            }
            XCTAssertEqual(sha256Float32(edgeTensors.subjectCropRGB), expectedHash, fixtureID)
        }

        let absentROI = SETCompositionNetROI(x: 0.0, y: 0.0, width: 0.0, height: 0.0, present: false)
        guard let absentTensors = preprocessor.setCompositionNetRGBTensors(
            from: sourceBuffer,
            orientation: .up,
            roi: absentROI
        ) else {
            return XCTFail("SETCompositionNet production absent-ROI tensors must be created")
        }
        XCTAssertTrue(absentTensors.subjectCropRGB.allSatisfy { $0 == 0.0 })
        XCTAssertEqual(
            sha256Float32(absentTensors.subjectCropRGB),
            "ecdd54e7af52d8ca757fa4f6b58884c0d8b5c487abeebdf23a4008a3b1b810bf"
        )
        XCTAssertEqual(
            sha256Float32(SETCompositionNetContract.roiMask(for: absentROI)),
            "d58201a30b35a60612306667b083ca4dfaf9efa107386fff36188e42c34c3c19"
        )
        guard let absentBuffers = preprocessor.setCompositionNetPixelBuffers(
            from: sourceBuffer,
            orientation: .up,
            roi: absentROI
        ), let absentCropRGB = preprocessor.setCompositionNetRGBValues(from: absentBuffers.subjectCrop) else {
            return XCTFail("SETCompositionNet production absent-ROI pixel buffers must be created")
        }
        XCTAssertTrue(absentCropRGB.allSatisfy { $0 == 0.0 })
    }

    private func makeSyntheticSourceBuffer() -> CVPixelBuffer? {
        var sourceBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            4,
            4,
            kCVPixelFormatType_32BGRA,
            nil,
            &sourceBuffer
        ) == kCVReturnSuccess,
        let sourceBuffer,
        CVPixelBufferLockBaseAddress(sourceBuffer, []) == kCVReturnSuccess else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(sourceBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(sourceBuffer) else {
            return nil
        }
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(sourceBuffer)
        for row in 0..<4 {
            for column in 0..<4 {
                let pixel = row * bytesPerRow + column * 4
                let sourceOffset = (row * 4 + column) * 3
                bytes[pixel] = UInt8(sourceOffset + 2)       // B
                bytes[pixel + 1] = UInt8(sourceOffset + 1)   // G
                bytes[pixel + 2] = UInt8(sourceOffset)       // R
                bytes[pixel + 3] = 255                       // alpha, discarded
            }
        }
        return sourceBuffer
    }

    private func sha256Float32(_ values: [Double]) -> String {
        var data = Data()
        data.reserveCapacity(values.count * MemoryLayout<Float>.size)
        for value in values {
            var bits = Float(value).bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
