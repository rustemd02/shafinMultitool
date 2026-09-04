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
            var didFinish = false
            let finish: (Double?) -> Void = { score in
                guard !didFinish else { return }
                didFinish = true
                completion(score)
            }

            let request = VNCoreMLRequest(model: model) { request, error in
                guard error == nil else {
                    finish(nil)
                    return
                }
                guard let distribution = (request.results as? [VNCoreMLFeatureValueObservation])?.first?.featureValue.multiArrayValue else {
                    finish(nil)
                    return
                }
                finish(self.expectedScore(from: distribution))
            }
            request.imageCropAndScaleOption = .scaleFill

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                orientation: orientation,
                                                options: [:])
            do {
                try handler.perform([request])
            } catch {
                finish(nil)
            }
        }
    }

    private func expectedScore(from distribution: MLMultiArray) -> Double? {
        let count = distribution.count
        guard count == 10 else { return nil }

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
