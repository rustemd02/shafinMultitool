//
//  AestheticScorer.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import CoreML
import Vision

final class AestheticScorer {
    private let model: VNCoreMLModel?
    private let queue = DispatchQueue(label: "AestheticScorer")

    init() {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        if let url = Bundle.main.url(forResource: "aesthetic_nima_mobilenet_fp16", withExtension: "mlmodelc") ??
            Bundle.main.url(forResource: "aesthetic_nima_mobilenet_fp16", withExtension: "mlpackage"),
           let coreMLModel = try? MLModel(contentsOf: url, configuration: config) {
            self.model = try? VNCoreMLModel(for: coreMLModel)
        } else {
            self.model = nil
        }
    }

    func score(pixelBuffer: CVPixelBuffer,
               orientation: CGImagePropertyOrientation,
               completion: @escaping (Double?) -> Void) {
        guard let model else {
            completion(nil)
            return
        }

        queue.async {
            let request = VNCoreMLRequest(model: model) { request, _ in
                if let distribution = (request.results as? [VNCoreMLFeatureValueObservation])?.first?.featureValue.multiArrayValue {
                    let expected = self.expectedScore(from: distribution)
                    completion(expected)
                } else if let scores = request.results as? [VNClassificationObservation],
                          let best = scores.first {
                    completion(Double(best.confidence) * 10.0)
                } else {
                    completion(nil)
                }
            }
            request.imageCropAndScaleOption = .scaleFill

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                orientation: orientation,
                                                options: [:])
            try? handler.perform([request])
        }
    }

    private func expectedScore(from distribution: MLMultiArray) -> Double {
        let count = distribution.count
        guard count == 10 else { return 0 }

        var expected: Double = 0
        switch distribution.dataType {
        case .float32:
            let pointer = distribution.dataPointer.bindMemory(to: Float32.self, capacity: count)
            for index in 0..<count {
                expected += Double(pointer[index]) * Double(index + 1)
            }
        case .float16:
            let pointer = distribution.dataPointer.bindMemory(to: UInt16.self, capacity: count)
            for index in 0..<count {
                let value = Double(Float16(bitPattern: pointer[index]))
                expected += value * Double(index + 1)
            }
        default:
            for index in 0..<count {
                let value = distribution[index].doubleValue
                expected += value * Double(index + 1)
            }
        }
        return expected
    }
}


