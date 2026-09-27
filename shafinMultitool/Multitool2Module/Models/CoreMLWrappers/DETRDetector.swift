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

enum DETRDetectionFailure: String, Error, Codable, Sendable {
    case modelUnavailable
    case inferenceFailed
    case missingOutput
    case invalidOutput
}

/// Success includes a valid empty segmentation result. Failure is unknown evidence.
typealias DETRDetectionResult = Result<[DETRDetection], DETRDetectionFailure>

final class DETRDetector {
    private let model: VNCoreMLModel
    private let queue = DispatchQueue(label: "DETRDetector")
    private let log = OSLog(subsystem: "com.multitool2.detr", category: "DETRDetector")
    private static let extractionLog = OSLog(subsystem: "com.multitool2.detr", category: "DETRDetector")
    private var detectionCount = 0
    /// Guarded by `queue`: one warm-up attempt per instance is enough to pay the
    /// cold-start cost before frame timing depends on it.
    private var warmUpCompleted = false

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

    /// Pays the heavy cold-start cost (Core ML graph/ANE scheduling + first
    /// inference) before live frames need the detector.
    ///
    /// CAM-002 root cause (2026-09-27): the first real inference occasionally
    /// took 1676–2192 ms against 607–656 ms in steady state, and the production
    /// high-priority path shed frames during that window, starving timing
    /// sensitive analysis windows. Warming once per instance at setup — when no
    /// frame timing depends on it — moves that cost out of the live path.
    ///
    /// - `waitUntilDone: false` (production route setup): returns immediately;
    ///   the warm-up runs on the detector queue before any queued `detect` work.
    /// - `waitUntilDone: true` (shared test harness): blocks the caller (bounded)
    ///   until the warm-up attempt finishes, so frame windows are deterministic.
    ///
    /// Idempotent and single-flight on the detector queue.
    func warmUp(waitUntilDone: Bool) {
        let done = waitUntilDone ? DispatchSemaphore(value: 0) : nil
        queue.async { [self] in
            defer { done?.signal() }
            guard !self.warmUpCompleted else { return }
            let startTime = CACurrentMediaTime()
            let warmed = self.performWarmUpInference()
            self.warmUpCompleted = warmed
            if CameraLog.modelLifecycle {
                os_log("DETR warm-up %{public}@ in %.0fms", log: self.log, type: .debug,
                       warmed ? "completed" : "failed",
                       (CACurrentMediaTime() - startTime) * 1000)
            }
        }
        if let done {
            _ = done.wait(timeout: .now() + 30)
        }
    }

    /// One throwaway inference on a tiny synthetic buffer; results are discarded.
    private func performWarmUpInference() -> Bool {
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        var pixelBufferOut: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA,
                                  attributes as CFDictionary, &pixelBufferOut) == kCVReturnSuccess,
              let pixelBuffer = pixelBufferOut else {
            os_log("DETR warm-up could not create a synthetic buffer", log: self.log, type: .error)
            return false
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(base, 0, CVPixelBufferGetDataSize(pixelBuffer))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        let request = VNCoreMLRequest(model: self.model)
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
            return true
        } catch {
            os_log("DETR warm-up inference failed: %{public}@", log: self.log, type: .error,
                   String(describing: error))
            return false
        }
    }

    func detect(pixelBuffer: CVPixelBuffer,
                orientation: CGImagePropertyOrientation,
                completion: @escaping (DETRDetectionResult) -> Void) {
        queue.async { [self] in
            self.detectionCount += 1
            if CameraLog.detr {
                os_log("🔍 DETR: Starting detection #%d", log: self.log, type: .debug, self.detectionCount)
            }

            let startTime = CACurrentMediaTime()

            let request = VNCoreMLRequest(model: self.model)
            request.imageCropAndScaleOption = .scaleFill
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                orientation: orientation,
                                                options: [:])
            // One synchronous request execution and one completion. Missing/invalid
            // output cannot be mistaken for a successfully observed empty frame.
            let result = Self.resolveDetection {
                try handler.perform([request])
                return request.results?
                    .compactMap { $0 as? VNCoreMLFeatureValueObservation }
                    .first { $0.featureName == "semanticPredictions" }?
                    .featureValue.multiArrayValue
            }
            if case .failure(let failure) = result {
                os_log("DETR unavailable: %{public}@", log: self.log, type: .error, failure.rawValue)
            } else if CameraLog.detr {
                os_log("DETR completed in %.0fms", log: self.log, type: .debug,
                       (CACurrentMediaTime() - startTime) * 1000)
            }
            completion(result)
        }
    }

    /// Shared by the real request path and bounded no-inference contract controls.
    static func resolveDetection(perform: () throws -> MLMultiArray?) -> DETRDetectionResult {
        let output: MLMultiArray?
        do { output = try perform() }
        catch { return .failure(.inferenceFailed) }
        guard let output else { return .failure(.missingOutput) }
        do { return .success(try extractDetections(from: output)) }
        catch { return .failure(.invalidOutput) }
    }

    static func extractDetections(from multiArray: MLMultiArray) throws -> [DETRDetection] {
        let shape = multiArray.shape.map { $0.intValue }
        guard shape.count == 2,
              shape.allSatisfy({ $0 > 0 }),
              multiArray.dataType == .int32 else {
            os_log("⚠️ DETR: Unexpected semantic predictions array", log: extractionLog, type: .error)
            throw DETRDetectionFailure.invalidOutput
        }

        let height = shape[0]
        let width = shape[1]
        let strides = multiArray.strides.map { $0.intValue }

        guard strides.count == 2,
              strides.allSatisfy({ $0 > 0 }),
              width <= Int.max / height else {
            os_log("⚠️ DETR: Unexpected semantic predictions strides", log: extractionLog, type: .error)
            throw DETRDetectionFailure.invalidOutput
        }

        let rowStride = strides[0]
        let columnStride = strides[1]
        let (lastRowOffset, rowOverflow) = (height - 1).multipliedReportingOverflow(by: rowStride)
        let (lastColumnOffset, columnOverflow) = (width - 1).multipliedReportingOverflow(by: columnStride)
        guard !rowOverflow,
              !columnOverflow,
              lastRowOffset <= Int.max - lastColumnOffset else {
            os_log("⚠️ DETR: Semantic predictions strides overflow", log: extractionLog, type: .error)
            throw DETRDetectionFailure.invalidOutput
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
