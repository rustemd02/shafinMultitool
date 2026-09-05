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
        fullFrameRGB: [Double]? = nil,
        subjectCropRGB: [Double]? = nil,
        roiMask: [Double]? = nil,
        scalarFeatures: [Double]? = nil,
        missingFeatureMask: [Double]? = nil
    ) -> SETCompositionNetInputTensors {
        SETCompositionNetInputTensors(
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
            roiMask: roiMask ?? SETCompositionNetContract.roiMask(for: roi),
            scalarFeatures: scalarFeatures ?? Array(
                repeating: 0.25,
                count: SETCompositionNetContract.scalarFeatureCount
            ),
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
        let source = (0..<48).map { Double($0) / 255.0 }
        let full = bilinearResize(source, sourceWidth: 4, sourceHeight: 4, targetWidth: 320, targetHeight: 320)
        let roi = SETCompositionNetROI(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let crop = squareCrop(source, sourceWidth: 4, sourceHeight: 4, roi: roi, targetWidth: 192, targetHeight: 192)
        let scalar = (0..<40).map { Double($0) / 39.0 }
        let missing = (0..<40).map { [5, 17, 31].contains($0) ? 1.0 : 0.0 }

        XCTAssertEqual(
            sha256Float32(full),
            "5ddc2c5c5c2dff60f1a2f3adcaaa9f7ff76ce6c4b140ff316a1edcb5f47a62f0"
        )
        XCTAssertEqual(
            sha256Float32(crop),
            "c95a927a6b5d1d1a902201b29cb37684d5bc02f4edd9f4cf01f3fe40d6b56067"
        )
        XCTAssertEqual(
            sha256Float32(SETCompositionNetContract.roiMask(for: roi)),
            "260802a4865f20a83e157c82bd3f07ab6a0eb13ff759db5c7cac65c54fa3e0bd"
        )
        XCTAssertEqual(
            sha256Float32(scalar),
            "ffdd8c80ebfbc563858d2a9c704701f9038b694f1c3e8ad8fa0457f65eb3c281"
        )
        XCTAssertEqual(
            sha256Float32(missing),
            "f70651d882c736a535bf6daca943049ddf7e824bd6cc6289a6d83066ad03817e"
        )

        XCTAssertEqual(full[(160 * 320 + 160) * 3], 0.0886029411764706, accuracy: 0.000001)
        XCTAssertEqual(crop[(96 * 192 + 96) * 3], 0.0886182598039216, accuracy: 0.000001)
    }

    private func bilinearResize(_ source: [Double],
                                sourceWidth: Int,
                                sourceHeight: Int,
                                targetWidth: Int,
                                targetHeight: Int) -> [Double] {
        var output: [Double] = []
        output.reserveCapacity(targetWidth * targetHeight * 3)
        for targetY in 0..<targetHeight {
            let sourceY = max(
                0.0,
                min(
                    Double(sourceHeight - 1),
                    (Double(targetY) + 0.5) * Double(sourceHeight) / Double(targetHeight) - 0.5
                )
            )
            let y0 = Int(sourceY)
            let y1 = min(y0 + 1, sourceHeight - 1)
            let yWeight = sourceY - Double(y0)
            for targetX in 0..<targetWidth {
                let sourceX = max(
                    0.0,
                    min(
                        Double(sourceWidth - 1),
                        (Double(targetX) + 0.5) * Double(sourceWidth) / Double(targetWidth) - 0.5
                    )
                )
                let x0 = Int(sourceX)
                let x1 = min(x0 + 1, sourceWidth - 1)
                let xWeight = sourceX - Double(x0)
                for channel in 0..<3 {
                    let topLeft = source[(y0 * sourceWidth + x0) * 3 + channel]
                    let topRight = source[(y0 * sourceWidth + x1) * 3 + channel]
                    let bottomLeft = source[(y1 * sourceWidth + x0) * 3 + channel]
                    let bottomRight = source[(y1 * sourceWidth + x1) * 3 + channel]
                    let top = (1.0 - xWeight) * topLeft + xWeight * topRight
                    let bottom = (1.0 - xWeight) * bottomLeft + xWeight * bottomRight
                    output.append((1.0 - yWeight) * top + yWeight * bottom)
                }
            }
        }
        return output
    }

    private func squareCrop(_ source: [Double],
                            sourceWidth: Int,
                            sourceHeight: Int,
                            roi: SETCompositionNetROI,
                            targetWidth: Int,
                            targetHeight: Int) -> [Double] {
        let rawX = roi.x * Double(sourceWidth)
        let rawY = roi.y * Double(sourceHeight)
        let rawWidth = roi.width * Double(sourceWidth)
        let rawHeight = roi.height * Double(sourceHeight)
        let side = max(rawWidth, rawHeight) * 1.25
        let left = max(0.0, rawX + rawWidth / 2.0 - side / 2.0)
        let top = max(0.0, rawY + rawHeight / 2.0 - side / 2.0)
        let right = min(Double(sourceWidth), left + side)
        let bottom = min(Double(sourceHeight), top + side)

        var output: [Double] = []
        output.reserveCapacity(targetWidth * targetHeight * 3)
        for targetY in 0..<targetHeight {
            let sourceY = max(
                0.0,
                min(
                    Double(sourceHeight - 1),
                    top + (Double(targetY) + 0.5) * (bottom - top) / Double(targetHeight) - 0.5
                )
            )
            let y0 = Int(sourceY)
            let y1 = min(y0 + 1, sourceHeight - 1)
            let yWeight = sourceY - Double(y0)
            for targetX in 0..<targetWidth {
                let sourceX = max(
                    0.0,
                    min(
                        Double(sourceWidth - 1),
                        left + (Double(targetX) + 0.5) * (right - left) / Double(targetWidth) - 0.5
                    )
                )
                let x0 = Int(sourceX)
                let x1 = min(x0 + 1, sourceWidth - 1)
                let xWeight = sourceX - Double(x0)
                for channel in 0..<3 {
                    let topLeft = source[(y0 * sourceWidth + x0) * 3 + channel]
                    let topRight = source[(y0 * sourceWidth + x1) * 3 + channel]
                    let bottomLeft = source[(y1 * sourceWidth + x0) * 3 + channel]
                    let bottomRight = source[(y1 * sourceWidth + x1) * 3 + channel]
                    let topValue = (1.0 - xWeight) * topLeft + xWeight * topRight
                    let bottomValue = (1.0 - xWeight) * bottomLeft + xWeight * bottomRight
                    output.append((1.0 - yWeight) * topValue + yWeight * bottomValue)
                }
            }
        }
        return output
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
