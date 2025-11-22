//
//  DETRDetector.swift
//  multitool2
//
//  Created by Claude on 15.11.2025.
//

import CoreML
import Vision
import os.log
import QuartzCore
import Accelerate

struct DETRDetection: Identifiable {
    let id = UUID()
    let boundingBox: CGRect
    let label: String
    let confidence: Float
}

final class DETRDetector {
    private let model: VNCoreMLModel
    private let queue = DispatchQueue(label: "DETRDetector")
    private let log = OSLog(subsystem: "com.multitool2.detr", category: "DETRDetector")
    private var detectionCount = 0

    // COCO labels для DETR модели
    private let labels: [String] = [
        "--", "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
        "traffic light", "fire hydrant", "--", "stop sign", "parking meter", "bench", "bird", "cat", "dog", "horse",
        "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "--", "backpack", "umbrella", "--",
        "--", "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball", "kite", "baseball bat",
        "baseball glove", "skateboard", "surfboard", "tennis racket", "bottle", "--", "wine glass", "cup", "fork", "knife",
        "spoon", "bowl", "banana", "apple", "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza",
        "donut", "cake", "chair", "couch", "potted plant", "bed", "--", "dining table", "--", "--",
        "toilet", "--", "tv", "laptop", "mouse", "remote", "keyboard", "cell phone", "microwave", "oven",
        "toaster", "sink", "refrigerator", "--", "book", "clock", "vase", "scissors", "teddy bear", "hair drier",
        "toothbrush", "--", "banner", "blanket", "--", "bridge", "--", "--", "--", "--",
        "cardboard", "--", "--", "--", "--", "--", "--", "counter", "--", "curtain",
        "--", "--", "door", "--", "--", "--", "--", "--", "floor (wood)", "flower",
        "--", "--", "fruit", "--", "--", "gravel", "--", "--", "house", "--",
        "light", "--", "--", "mirror", "--", "--", "--", "--", "net", "--",
        "--", "pillow", "--", "--", "platform", "playingfield", "--", "railroad", "river", "road",
        "--", "roof", "--", "--", "sand", "sea", "shelf", "--", "--", "snow",
        "--", "stairs", "--", "--", "--", "--", "tent", "--", "towel", "--",
        "--", "wall (brick)", "--", "--", "--", "wall (stone)", "wall (tile)", "wall (wood)", "water (other)", "--",
        "window (blind)", "window (other)", "--", "--", "tree", "fence", "ceiling", "sky (other)", "cabinet", "table",
        "floor (other)", "pavement", "mountain", "grass", "dirt", "paper", "food (other)", "building (other)", "rock", "wall (other)",
        "rug"
    ]

    init() throws {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine

        let bundle = Bundle.main
        guard let url = bundle.url(forResource: "DETRResnet50SemanticSegmentationF16P8", withExtension: "mlmodelc") ??
                bundle.url(forResource: "DETRResnet50SemanticSegmentationF16P8", withExtension: "mlpackage") else {
            os_log("❌ DETR: Model file not found in bundle", log: OSLog(subsystem: "com.multitool2.detr", category: "Init"), type: .error)
            throw NSError(domain: "DETRDetector", code: 1, userInfo: [NSLocalizedDescriptionKey: "DETR model not found in bundle"])
        }

        os_log("✅ DETR: Model found at %{public}@", log: OSLog(subsystem: "com.multitool2.detr", category: "Init"), type: .info, url.path)

        let coreMLModel = try MLModel(contentsOf: url, configuration: config)
        model = try VNCoreMLModel(for: coreMLModel)

        os_log("✅ DETR: Model loaded successfully",
               log: OSLog(subsystem: "com.multitool2.detr", category: "Init"), type: .info)
    }

    func detect(pixelBuffer: CVPixelBuffer,
                orientation: CGImagePropertyOrientation,
                completion: @escaping ([DETRDetection]) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }

            self.detectionCount += 1
            os_log("🔍 DETR: Starting detection #%d", log: self.log, type: .info, self.detectionCount)

            let startTime = CACurrentMediaTime()

            let request = VNCoreMLRequest(model: self.model) { request, error in
                let elapsed = CACurrentMediaTime() - startTime

                if let error = error {
                    os_log("❌ DETR: Detection error: %{public}@", log: self.log, type: .error, error.localizedDescription)
                    completion([])
                    return
                }

                guard let results = request.results,
                      let observation = results.first as? VNCoreMLFeatureValueObservation,
                      let multiArray = observation.featureValue.multiArrayValue else {
                    os_log("⚠️ DETR: No semantic predictions in results (%.0fms)",
                           log: self.log, type: .info, elapsed * 1000)
                    completion([])
                    return
                }

                os_log("🎯 DETR: Processing semantic segmentation map (%.0fms)",
                       log: self.log, type: .info, elapsed * 1000)

                // Обработка semantic segmentation map и извлечение bounding boxes
                let detections = self.extractDetections(from: multiArray)

                os_log("✅ DETR: Returning %d detections", log: self.log, type: .info, detections.count)
                completion(detections)
            }
            request.imageCropAndScaleOption = .scaleFill

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                orientation: orientation,
                                                options: [:])
            do {
                try handler.perform([request])
            } catch {
                os_log("❌ DETR: Handler error: %{public}@", log: self.log, type: .error, error.localizedDescription)
                completion([])
            }
        }
    }

    private func extractDetections(from multiArray: MLMultiArray) -> [DETRDetection] {
        let shape = multiArray.shape.map { $0.intValue }
        guard shape.count >= 2 else {
            os_log("⚠️ DETR: Unexpected array shape", log: self.log, type: .error)
            return []
        }

        let height = shape[0]
        let width = shape[1]

        os_log("📊 DETR: Segmentation map size: %dx%d", log: self.log, type: .info, width, height)

        // Подсчет пикселей для каждого класса
        var classCounts: [Int: Int] = [:]
        var classMinMax: [Int: (minX: Int, minY: Int, maxX: Int, maxY: Int)] = [:]

        // Читаем данные из multiArray
        let pointer = multiArray.dataPointer.assumingMemoryBound(to: Int32.self)

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let classId = Int(pointer[index])

                // Игнорируем фоновые классы (0 = "--") и неизвестные классы
                guard classId > 0 && classId < labels.count && labels[classId] != "--" else {
                    continue
                }

                // Фильтруем "person" - его обрабатывает Vision
                if labels[classId].lowercased() == "person" {
                    continue
                }

                // Подсчитываем пиксели
                classCounts[classId, default: 0] += 1

                // Обновляем bounding box
                if let existing = classMinMax[classId] {
                    classMinMax[classId] = (
                        minX: min(existing.minX, x),
                        minY: min(existing.minY, y),
                        maxX: max(existing.maxX, x),
                        maxY: max(existing.maxY, y)
                    )
                } else {
                    classMinMax[classId] = (minX: x, minY: y, maxX: x, maxY: y)
                }
            }
        }

        // Конвертируем в детекции
        var detections: [DETRDetection] = []
        let totalPixels = width * height
        let minPixelThreshold = totalPixels / 500 // Минимум 0.2% от изображения

        for (classId, count) in classCounts {
            // Фильтруем слишком маленькие объекты
            guard count >= minPixelThreshold else { continue }

            guard let bounds = classMinMax[classId] else { continue }

            // Конвертируем в нормализованные координаты (0...1)
            let x = CGFloat(bounds.minX) / CGFloat(width)
            let y = CGFloat(bounds.minY) / CGFloat(height)
            let w = CGFloat(bounds.maxX - bounds.minX + 1) / CGFloat(width)
            let h = CGFloat(bounds.maxY - bounds.minY + 1) / CGFloat(height)

            // Confidence на основе количества пикселей
            let confidence = min(1.0, Float(count) / Float(totalPixels) * 20.0)

            let detection = DETRDetection(
                boundingBox: CGRect(x: x, y: y, width: w, height: h),
                label: labels[classId],
                confidence: confidence
            )

            detections.append(detection)

            os_log("  ✓ %{public}@ pixels=%d conf=%.2f bbox=(%.2f,%.2f,%.2f,%.2f)",
                   log: self.log, type: .info,
                   labels[classId], count, confidence, x, y, w, h)
        }

        // Сортируем по confidence
        return detections.sorted { $0.confidence > $1.confidence }
    }
}
