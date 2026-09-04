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
    private static let extractionLog = OSLog(subsystem: "com.multitool2.detr", category: "DETRDetector")
    private var detectionCount = 0

    // COCO labels для DETR модели
    private static let labels: [String] = [
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

        if CameraLog.modelLifecycle {
            os_log("✅ DETR: Model found at %{public}@", log: OSLog(subsystem: "com.multitool2.detr", category: "Init"), type: .debug, url.path)
        }

        let coreMLModel = try MLModel(contentsOf: url, configuration: config)
        model = try VNCoreMLModel(for: coreMLModel)

        if CameraLog.modelLifecycle {
            os_log("✅ DETR: Model loaded successfully",
                   log: OSLog(subsystem: "com.multitool2.detr", category: "Init"), type: .debug)
        }
    }

    func detect(pixelBuffer: CVPixelBuffer,
                orientation: CGImagePropertyOrientation,
                completion: @escaping ([DETRDetection]) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }

            self.detectionCount += 1
            if CameraLog.detr {
                os_log("🔍 DETR: Starting detection #%d", log: self.log, type: .debug, self.detectionCount)
            }

            let startTime = CACurrentMediaTime()

            let request = VNCoreMLRequest(model: self.model) { request, error in
                let elapsed = CACurrentMediaTime() - startTime

                if let error = error {
                    os_log("❌ DETR: Detection error: %{private}@", log: self.log, type: .error, error.localizedDescription)
                    completion([])
                    return
                }

                guard let observation = request.results?
                        .compactMap({ $0 as? VNCoreMLFeatureValueObservation })
                        .first(where: { $0.featureName == "semanticPredictions" }),
                      let multiArray = observation.featureValue.multiArrayValue else {
                    if CameraLog.detr {
                        os_log("⚠️ DETR: No semantic predictions in results (%.0fms)",
                               log: self.log, type: .debug, elapsed * 1000)
                    }
                    completion([])
                    return
                }

                if CameraLog.detr {
                    os_log("🎯 DETR: Processing semantic segmentation map (%.0fms)",
                           log: self.log, type: .debug, elapsed * 1000)
                }

                // Обработка semantic segmentation map и извлечение bounding boxes
                let detections = Self.extractDetections(from: multiArray)

                if CameraLog.detr {
                    os_log("✅ DETR: Returning %d detections", log: self.log, type: .debug, detections.count)
                }
                completion(detections)
            }
            request.imageCropAndScaleOption = .scaleFill

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                orientation: orientation,
                                                options: [:])
            do {
                try handler.perform([request])
            } catch {
                os_log("❌ DETR: Handler error: %{private}@", log: self.log, type: .error, error.localizedDescription)
                completion([])
            }
        }
    }

    static func extractDetections(from multiArray: MLMultiArray) -> [DETRDetection] {
        let shape = multiArray.shape.map { $0.intValue }
        guard shape.count == 2,
              shape.allSatisfy({ $0 > 0 }),
              multiArray.dataType == .int32 else {
            os_log("⚠️ DETR: Unexpected semantic predictions array", log: extractionLog, type: .error)
            return []
        }

        let height = shape[0]
        let width = shape[1]
        let strides = multiArray.strides.map { $0.intValue }

        guard strides.count == 2,
              strides.allSatisfy({ $0 > 0 }),
              width <= Int.max / height else {
            os_log("⚠️ DETR: Unexpected semantic predictions strides", log: extractionLog, type: .error)
            return []
        }

        let rowStride = strides[0]
        let columnStride = strides[1]
        let (lastRowOffset, rowOverflow) = (height - 1).multipliedReportingOverflow(by: rowStride)
        let (lastColumnOffset, columnOverflow) = (width - 1).multipliedReportingOverflow(by: columnStride)
        guard !rowOverflow,
              !columnOverflow,
              lastRowOffset <= Int.max - lastColumnOffset else {
            os_log("⚠️ DETR: Semantic predictions strides overflow", log: extractionLog, type: .error)
            return []
        }

        if CameraLog.detr {
            os_log("📊 DETR: Segmentation map size: %dx%d", log: extractionLog, type: .debug, width, height)
        }

        let totalPixels = width * height
        let minPixelThreshold = max(1, totalPixels / 500)
        let pointer = multiArray.dataPointer.assumingMemoryBound(to: Int32.self)
        var classIDs = Array(repeating: -1, count: totalPixels)

        for y in 0..<height {
            for x in 0..<width {
                let classId = Int(pointer[y * rowStride + x * columnStride])

                // Игнорируем фоновые классы (0 = "--") и неизвестные классы
                guard classId > 0 && classId < labels.count && labels[classId] != "--" else {
                    continue
                }

                // Фильтруем "person" - его обрабатывает Vision
                if labels[classId].lowercased() == "person" {
                    continue
                }

                classIDs[y * width + x] = classId
            }
        }

        var components: [(classId: Int, count: Int, minX: Int, minY: Int, maxX: Int, maxY: Int)] = []
        for y in 0..<height {
            for x in 0..<width {
                let startIndex = y * width + x
                let classId = classIDs[startIndex]
                guard classId > 0 else { continue }

                classIDs[startIndex] = -1
                var queue = [startIndex]
                var queueIndex = 0
                var count = 0
                var minX = x
                var minY = y
                var maxX = x
                var maxY = y

                while queueIndex < queue.count {
                    let index = queue[queueIndex]
                    queueIndex += 1
                    let currentY = index / width
                    let currentX = index - currentY * width
                    count += 1
                    minX = min(minX, currentX)
                    minY = min(minY, currentY)
                    maxX = max(maxX, currentX)
                    maxY = max(maxY, currentY)

                    for neighborY in max(0, currentY - 1)...min(height - 1, currentY + 1) {
                        for neighborX in max(0, currentX - 1)...min(width - 1, currentX + 1) {
                            if neighborX == currentX && neighborY == currentY {
                                continue
                            }

                            let neighborIndex = neighborY * width + neighborX
                            guard classIDs[neighborIndex] == classId else { continue }
                            classIDs[neighborIndex] = -1
                            queue.append(neighborIndex)
                        }
                    }
                }

                guard count >= minPixelThreshold else { continue }
                components.append((classId, count, minX, minY, maxX, maxY))
            }
        }

        components.sort {
            if $0.count != $1.count { return $0.count > $1.count }

            let lhsLabel = labels[$0.classId]
            let rhsLabel = labels[$1.classId]
            if lhsLabel != rhsLabel { return lhsLabel < rhsLabel }
            if $0.minX != $1.minX { return $0.minX < $1.minX }
            if $0.minY != $1.minY { return $0.minY < $1.minY }
            if $0.maxX != $1.maxX { return $0.maxX < $1.maxX }
            if $0.maxY != $1.maxY { return $0.maxY < $1.maxY }
            return $0.classId < $1.classId
        }

        return components.map { component in
            let classId = component.classId

            // Конвертируем в нормализованные координаты (0...1)
            let x = CGFloat(component.minX) / CGFloat(width)
            let y = 1 - CGFloat(component.maxY + 1) / CGFloat(height)
            let w = CGFloat(component.maxX - component.minX + 1) / CGFloat(width)
            let h = CGFloat(component.maxY - component.minY + 1) / CGFloat(height)

            // Hard-label segmentation exposes no probability/logits; this geometric support is not calibrated model confidence.
            let confidence = min(1.0, Float(component.count) / Float(totalPixels) * 20.0)

            let detection = DETRDetection(
                boundingBox: CGRect(x: x, y: y, width: w, height: h),
                label: labels[classId],
                confidence: confidence
            )

            #if DEBUG
            if CameraLog.detr {
                os_log("  ✓ %{public}@ pixels=%d conf=%.2f bbox=(%.2f,%.2f,%.2f,%.2f)",
                       log: extractionLog, type: .debug,
                       labels[classId], component.count, confidence, x, y, w, h)
            }
            #endif

            return detection
        }
    }
}
