//
//  CoreMLNeuralEvidenceProvider.swift
//  multitool2
//
//  Created by Codex on 22.04.2026.
//

import CoreML
import CoreVideo
import Foundation
import ImageIO

final class CoreMLNeuralEvidenceProvider: NeuralEvidenceProvider {
    struct ModelResource {
        let name: String
        let bundle: Bundle

        init(name: String = "compact_neural_evidence_net", bundle: Bundle = .main) {
            self.name = name
            self.bundle = bundle
        }

        var url: URL? {
            bundle.url(forResource: name, withExtension: "mlmodelc") ??
            bundle.url(forResource: name, withExtension: "mlpackage")
        }
    }

    let descriptor: NeuralEvidenceProviderDescriptor

    var isModelAvailable: Bool {
        modelResource.url != nil
    }

    private let modelResource: ModelResource
    private let modelStateQueue = DispatchQueue(label: "CoreMLNeuralEvidenceProvider.model")
    private let preprocessor = MetalPreprocessor()
    private let modelConfiguration: MLModelConfiguration
    private var model: MLModel?

    init(modelResource: ModelResource = ModelResource(),
         computeUnits: MLComputeUnits = .cpuAndNeuralEngine,
         descriptor: NeuralEvidenceProviderDescriptor = NeuralEvidenceProviderDescriptor(
            providerKind: .coremlLocal,
            inferenceTarget: .onDevice,
            modelFamily: "compact_neural_evidence_net",
            modelVersion: "h05.v1",
            preprocessingVersion: "prep.v1",
            thresholdProfileLive: "default_live_v1",
            thresholdProfilePause: "default_pause_v1",
            bundleVersion: "compact_neural_evidence_net.bundle.v1"
         )) {
        self.modelResource = modelResource
        self.descriptor = descriptor
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        self.modelConfiguration = configuration
    }

    convenience init(bundle: Bundle = .main) {
        self.init(modelResource: ModelResource(bundle: bundle))
    }

    func prepareIfNeeded() async throws {
        try Task.checkCancellation()
        _ = try loadModelIfNeeded()
        try Task.checkCancellation()
    }

    func infer(request: NeuralEvidenceProviderRequest) async throws -> NeuralEvidenceProviderOutput {
        let model = try loadModelIfNeeded()

        do {
            try Task.checkCancellation()

            let fullFrame = self.preprocessor.resizedPixelBuffer(
                from: request.pixelBuffer,
                orientation: request.orientation,
                targetSize: CGSize(width: 256, height: 256)
            )
            guard let fullFrame else {
                throw NeuralEvidenceProviderError.preprocessingFailed
            }

            let cropRect = self.cropRect(
                for: request.primarySubjectRegion,
                pixelBuffer: request.pixelBuffer,
                orientation: request.orientation,
                roiStrategy: request.roiStrategy
            )
            let cropPixelBuffer: CVPixelBuffer
            let actualROIStrategy: NeuralEvidenceROIStrategy
            if let cropRect,
               let cropped = self.preprocessor.resizedPixelBuffer(
                from: request.pixelBuffer,
                orientation: request.orientation,
                targetSize: CGSize(width: 160, height: 160),
                cropRect: cropRect
               ) {
                cropPixelBuffer = cropped
                actualROIStrategy = .fullFramePlusSubjectCrop
            } else {
                guard let zero = self.makeZeroPixelBuffer(width: 160, height: 160) else {
                    throw NeuralEvidenceProviderError.preprocessingFailed
                }
                cropPixelBuffer = zero
                actualROIStrategy = .fullFrameOnly
            }

            do {
                try Task.checkCancellation()

                let input = try MLDictionaryFeatureProvider(dictionary: [
                    "full_frame_rgb": MLFeatureValue(pixelBuffer: fullFrame),
                    "subject_crop_rgb": MLFeatureValue(pixelBuffer: cropPixelBuffer),
                    "mode_flag_live": MLFeatureValue(double: request.mode == .live ? 1.0 : 0.0),
                    "crop_present_flag": MLFeatureValue(double: actualROIStrategy == .fullFramePlusSubjectCrop ? 1.0 : 0.0)
                ])

                let output = try await model.prediction(from: input)
                return try self.parseOutput(output, actualROIStrategy: actualROIStrategy)
            } catch let error as NeuralEvidenceProviderError {
                throw NeuralEvidenceProviderExecutionError(
                    providerError: error,
                    actualROIStrategy: actualROIStrategy
                )
            } catch {
                throw NeuralEvidenceProviderExecutionError(
                    providerError: .inferenceFailed,
                    actualROIStrategy: actualROIStrategy
                )
            }
        } catch let error as NeuralEvidenceProviderError {
            throw error
        } catch let error as NeuralEvidenceProviderExecutionError {
            throw error
        } catch {
            throw NeuralEvidenceProviderError.inferenceFailed
        }
    }

    private func loadModelIfNeeded() throws -> MLModel {
        try modelStateQueue.sync {
            if let model {
                return model
            }
            guard let url = modelResource.url else {
                throw NeuralEvidenceProviderError.modelNotLoaded
            }
            do {
                let loadedModel = try MLModel(contentsOf: url, configuration: modelConfiguration)
                model = loadedModel
                return loadedModel
            } catch {
                throw NeuralEvidenceProviderError.modelNotLoaded
            }
        }
    }

    private func parseOutput(_ provider: MLFeatureProvider,
                             actualROIStrategy: NeuralEvidenceROIStrategy) throws -> NeuralEvidenceProviderOutput {
        guard
            let scalarScoreLogits = provider.featureValue(for: "scalar_score_logits")?.multiArrayValue,
            let scalarConfidenceLogits = provider.featureValue(for: "scalar_confidence_logits")?.multiArrayValue,
            let supportingSignalLogits = provider.featureValue(for: "supporting_signal_logits")?.multiArrayValue,
            let shotTypeAffinityLogits = provider.featureValue(for: "shot_type_affinity_logits")?.multiArrayValue,
            let shotTypeConfidenceLogit = provider.featureValue(for: "shot_type_confidence_logit")?.multiArrayValue
        else {
            throw NeuralEvidenceProviderError.postprocessingFailed
        }

        let scalarScores = try values(from: scalarScoreLogits, expectedShape: [7]).map(Self.sigmoid)
        let scalarConfidences = try values(from: scalarConfidenceLogits, expectedShape: [7]).map(Self.sigmoid)
        let supportingSignals = try matrixValues(from: supportingSignalLogits, expectedRows: 7, columns: 21).map { row in
            row.map(Self.sigmoid)
        }
        let shotTypeAffinities = try values(from: shotTypeAffinityLogits, expectedShape: [7]).map(Self.sigmoid)
        let shotTypeConfidence = try values(from: shotTypeConfidenceLogit, expectedShape: [1]).first.map(Self.sigmoid)

        guard let shotTypeConfidence else {
            throw NeuralEvidenceProviderError.postprocessingFailed
        }

        return NeuralEvidenceProviderOutput(
            scalarScores: scalarScores,
            scalarConfidences: scalarConfidences,
            supportingSignalScores: supportingSignals,
            shotTypeAffinities: shotTypeAffinities,
            shotTypeConfidence: shotTypeConfidence,
            actualROIStrategy: actualROIStrategy
        )
    }

    private func values(from array: MLMultiArray, expectedShape: [Int]) throws -> [Double] {
        let shape = array.shape.map(\.intValue)
        guard shape == expectedShape else {
            throw NeuralEvidenceProviderError.postprocessingFailed
        }
        let count = expectedShape.reduce(1, *)
        return (0..<count).map { array[$0].doubleValue }
    }

    private func matrixValues(from array: MLMultiArray, expectedRows: Int, columns: Int) throws -> [[Double]] {
        let shape = array.shape.map(\.intValue)
        guard shape == [expectedRows, columns] else {
            throw NeuralEvidenceProviderError.postprocessingFailed
        }

        return (0..<expectedRows).map { row in
            (0..<columns).map { column in
                array[[NSNumber(value: row), NSNumber(value: column)]].doubleValue
            }
        }
    }

    private func cropRect(for region: NormalizedRect?,
                          pixelBuffer: CVPixelBuffer,
                          orientation: CGImagePropertyOrientation,
                          roiStrategy: NeuralEvidenceROIStrategy) -> CGRect? {
        guard roiStrategy == .fullFramePlusSubjectCrop else {
            return nil
        }
        guard let region, !region.isDegenerate else {
            return nil
        }

        let orientedSize = orientedPixelBufferSize(for: pixelBuffer, orientation: orientation)
        let pixelWidth = orientedSize.width
        let pixelHeight = orientedSize.height
        let rawRect = CGRect(
            x: CGFloat(region.x) * pixelWidth,
            y: CGFloat(region.y) * pixelHeight,
            width: CGFloat(region.width) * pixelWidth,
            height: CGFloat(region.height) * pixelHeight
        )
        let squareSide = max(rawRect.width, rawRect.height) * 1.25
        let squareRect = CGRect(
            x: rawRect.midX - squareSide / 2,
            y: rawRect.midY - squareSide / 2,
            width: squareSide,
            height: squareSide
        )

        let bounds = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        let clipped = squareRect.intersection(bounds)
        guard !clipped.isNull, !clipped.isEmpty else {
            return nil
        }
        return clipped
    }

    private func orientedPixelBufferSize(for pixelBuffer: CVPixelBuffer,
                                         orientation: CGImagePropertyOrientation) -> CGSize {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: height, height: width)
        case .up, .upMirrored, .down, .downMirrored:
            return CGSize(width: width, height: height)
        @unknown default:
            return CGSize(width: width, height: height)
        }
    }

    private func makeZeroPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
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
        guard status == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(baseAddress, 0, CVPixelBufferGetDataSize(pixelBuffer))
        }
        return pixelBuffer
    }

    private static func sigmoid(_ value: Double) -> Double {
        1.0 / (1.0 + exp(-value))
    }
}
