//
//  VisionTracking.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import Vision
import os.log

struct TrackedSubject {
    let boundingBox: CGRect
    let confidence: VNConfidence
    let isFace: Bool
}

struct VisionTrackingResult {
    let subjects: [TrackedSubject]
    let saliencyCenter: CGPoint?
    let faceCount: Int
    let personCount: Int
}

final class VisionTracking {
    private let humanRequest = VNDetectHumanRectanglesRequest()
    private let faceRequest = VNDetectFaceRectanglesRequest()
    private let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
    private var lastObservation: VNDetectedObjectObservation?
    // EMA для центра saliency, чтобы подавить дрожание
    private var saliencyEMA: CGPoint?
    private let saliencyAlpha: CGFloat = 0.25
    private let saliencyDeadband: CGFloat = 0.015 // в нормированных координатах (от 0 до 1)
    
    private let log = OSLog(subsystem: "com.multitool2.vision", category: "VisionTracking")
    private var frameCount = 0

    func process(pixelBuffer: CVPixelBuffer,
                 orientation: CGImagePropertyOrientation) -> VisionTrackingResult {
        var results: [TrackedSubject] = []
        var saliencyCenter: CGPoint?
        
        frameCount += 1
        let shouldLog = frameCount % 30 == 0 // Логируем каждые 30 кадров (~2 сек при 15 FPS)

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: orientation,
                                            options: [:])
        do {
            try handler.perform([faceRequest, humanRequest, saliencyRequest])

            if let faces = faceRequest.results as? [VNFaceObservation] {
                if shouldLog {
                    os_log("👤 Vision: %d faces found", log: log, type: .info, faces.count)
                    for (i, face) in faces.enumerated() {
                        os_log("  Face %d: bbox=(%.2f,%.2f,%.2f,%.2f) conf=%.2f", 
                               log: log, type: .info, i,
                               face.boundingBox.origin.x, face.boundingBox.origin.y,
                               face.boundingBox.size.width, face.boundingBox.size.height,
                               face.confidence)
                    }
                }
                results += faces.map { obs in
                    TrackedSubject(boundingBox: obs.boundingBox,
                                   confidence: obs.confidence,
                                   isFace: true)
                }
                lastObservation = faces.first
            } else if shouldLog {
                os_log("👤 Vision: No faces detected", log: log, type: .info)
            }

            if let humans = humanRequest.results as? [VNDetectedObjectObservation] {
                let filtered = humans.filter { human in
                    !results.contains { $0.boundingBox.intersects(human.boundingBox) }
                }
                if shouldLog {
                    os_log("🚶 Vision: %d humans (filtered: %d)", log: log, type: .info, humans.count, filtered.count)
                }
                results += filtered.map { obs in
                    TrackedSubject(boundingBox: obs.boundingBox,
                                   confidence: obs.confidence,
                                   isFace: false)
                }
                if lastObservation == nil {
                    lastObservation = filtered.first
                }
            }
            
            if let saliency = saliencyRequest.results?.first as? VNSaliencyImageObservation,
               let top = saliency.salientObjects?.max(by: { ($0.confidence) < ($1.confidence) }) {
                let rawCenter = CGPoint(x: top.boundingBox.midX, y: top.boundingBox.midY)
                if let prev = saliencyEMA {
                    let dx = rawCenter.x - prev.x
                    let dy = rawCenter.y - prev.y
                    let distance = sqrt(dx*dx + dy*dy)
                    if distance < saliencyDeadband {
                        saliencyCenter = prev
                        if shouldLog {
                            os_log("🎯 Saliency: within deadband, keeping prev (%.3f,%.3f)", 
                                   log: log, type: .info, prev.x, prev.y)
                        }
                    } else {
                        let newX = prev.x * (1 - saliencyAlpha) + rawCenter.x * saliencyAlpha
                        let newY = prev.y * (1 - saliencyAlpha) + rawCenter.y * saliencyAlpha
                        let smoothed = CGPoint(x: newX, y: newY)
                        saliencyEMA = smoothed
                        saliencyCenter = smoothed
                        if shouldLog {
                            os_log("🎯 Saliency: raw=(%.3f,%.3f) smoothed=(%.3f,%.3f) dist=%.4f", 
                                   log: log, type: .info,
                                   rawCenter.x, rawCenter.y, smoothed.x, smoothed.y, distance)
                        }
                    }
                } else {
                    saliencyEMA = rawCenter
                    saliencyCenter = rawCenter
                    if shouldLog {
                        os_log("🎯 Saliency: initial center (%.3f,%.3f)", 
                               log: log, type: .info, rawCenter.x, rawCenter.y)
                    }
                }
            } else if shouldLog {
                os_log("🎯 Saliency: No salient objects found", log: log, type: .info)
            }
        } catch {
            os_log("❌ Vision error: %{public}@", log: log, type: .error, error.localizedDescription)
            return VisionTrackingResult(subjects: results, saliencyCenter: nil, faceCount: 0, personCount: 0)
        }

        let faces = results.filter { $0.isFace }.count
        let persons = results.count
        return VisionTrackingResult(subjects: results, saliencyCenter: saliencyCenter, faceCount: faces, personCount: persons)
    }
}


