//
//  VisionTracking.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import Vision
import os.log
import CoreMedia

/// Camera pixels and lifecycle that a rectangle measurement actually belongs to.
/// Slot indices below are internal Vision requests, never SubjectTracker identities.
struct VisionObjectFrame: Equatable {
    let frameID: String
    let captureGeneration: UInt64
    let sessionGeneration: UInt64?
    let lifecycleGeneration: UInt64
    let orientation: CGImagePropertyOrientation
    let samplePTS: CMTime
    let capturedAt: Date

    var isKnown: Bool {
        !frameID.isEmpty && captureGeneration != 0 && sessionGeneration != nil
            && samplePTS.isNumeric && capturedAt.timeIntervalSince1970.isFinite
    }

    func sharesEpoch(with other: Self) -> Bool {
        captureGeneration == other.captureGeneration
            && sessionGeneration == other.sessionGeneration
            && lifecycleGeneration == other.lifecycleGeneration
            && orientation == other.orientation
    }
}

struct VisionObjectSeed {
    let frame: VisionObjectFrame
    let pixelBuffer: CVPixelBuffer
    let detections: [DETRDetection]
    let sourceCandidateCount: Int

    init(frame: VisionObjectFrame, pixelBuffer: CVPixelBuffer,
         detections: [DETRDetection], sourceCandidateCount: Int? = nil) {
        self.frame = frame
        self.pixelBuffer = pixelBuffer
        self.detections = detections
        self.sourceCandidateCount = max(detections.count, sourceCandidateCount ?? detections.count)
    }
}

/// Geometry of the image-relative tracking rectangle, not visibility of a segmented
/// entity. An unclipped estimate can still describe a physically occluded object.
struct VisionObjectGeometry: Equatable {
    struct ClippedEdges: OptionSet, Equatable {
        let rawValue: UInt8
        static let left = Self(rawValue: 1 << 0)
        static let bottom = Self(rawValue: 1 << 1)
        static let right = Self(rawValue: 1 << 2)
        static let top = Self(rawValue: 1 << 3)
    }

    /// Existing foreground publication floor, shared with the snapshot aggregator.
    static let minimumPublishedArea: Double = 0.003
    /// Association within source.frameID only; never a SubjectTracker identity.
    let seedSlot: Int
    let rawBoundingBox: CGRect
    let visibleImageIntersection: CGRect
    /// 1 - intersection rectangle area / raw rectangle area; not an entity mask fraction.
    let rectangleClippedFraction: Double
    let clippedEdges: ClippedEdges

    var hasClippedTrackingGeometry: Bool { !clippedEdges.isEmpty }
    var meetsPublicationArea: Bool {
        Double(visibleImageIntersection.width * visibleImageIntersection.height) >= Self.minimumPublishedArea
    }

    init?(seedSlot: Int, rawBoundingBox raw: CGRect) {
        // Use stored sizes: CGRect's standardized accessors must not repair inverted input.
        guard (0..<4).contains(seedSlot),
              [raw.origin.x, raw.origin.y, raw.size.width, raw.size.height].allSatisfy(\.isFinite),
              raw.size.width > 0, raw.size.height > 0 else { return nil }
        let right = raw.origin.x + raw.size.width
        let top = raw.origin.y + raw.size.height
        let rawArea = raw.size.width * raw.size.height
        guard right.isFinite, top.isFinite, rawArea.isFinite, rawArea > 0 else { return nil }
        let left = max(0, raw.origin.x), bottom = max(0, raw.origin.y)
        let width = min(1, right) - left, height = min(1, top) - bottom
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        let visible = CGRect(x: left, y: bottom, width: width, height: height)
        var edges: ClippedEdges = []
        if raw.origin.x < 0 { edges.insert(.left) }
        if raw.origin.y < 0 { edges.insert(.bottom) }
        if right > 1 { edges.insert(.right) }
        if top > 1 { edges.insert(.top) }
        self.seedSlot = seedSlot
        rawBoundingBox = raw
        visibleImageIntersection = edges.isEmpty ? raw : visible
        rectangleClippedFraction = edges.isEmpty ? 0 : min(1, max(0, 1 - Double(width * height / rawArea)))
        clippedEdges = edges
    }
}

struct VisionObjectMeasurement {
    let boundingBox: CGRect
    /// Raw Vision tracking quality; never a semantic/calibrated probability.
    let quality: Float
}

protocol VisionObjectSequence: AnyObject {
    func measure(pixelBuffer: CVPixelBuffer,
                 orientation: CGImagePropertyOrientation) throws -> [VisionObjectMeasurement?]
}

private final class AppleVisionObjectSequence: VisionObjectSequence {
    private let handler = VNSequenceRequestHandler()
    private let requests: [VNTrackObjectRequest]

    init(boxes: [CGRect]) {
        requests = boxes.map {
            let request = VNTrackObjectRequest(detectedObjectObservation:
                VNDetectedObjectObservation(boundingBox: $0))
            request.trackingLevel = .accurate
            return request
        }
    }

    func measure(pixelBuffer: CVPixelBuffer,
                 orientation: CGImagePropertyOrientation) throws -> [VisionObjectMeasurement?] {
        try handler.perform(requests, on: pixelBuffer, orientation: orientation)
        return requests.map { request in
            guard let observation = request.results?.first as? VNDetectedObjectObservation else { return nil }
            request.inputObservation = observation
            return VisionObjectMeasurement(boundingBox: observation.boundingBox,
                                           quality: observation.confidence)
        }
    }
}

struct VisionObjectTrackingBatch {
    let source: VisionObjectFrame
    let current: VisionObjectFrame
    let detections: [DETRDetection]
    let qualities: [Float]
    let geometries: [VisionObjectGeometry]
    let sourceCandidateCount: Int
}


struct TrackedSubject {
    let boundingBox: CGRect
    let confidence: VNConfidence
    let isFace: Bool
}

struct VisionTrackingResult {
    let subjects: [TrackedSubject]
    let saliencyCenter: CGPoint?
    let saliencyRegion: CGRect?
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


    // These members are confined to AnalysisPipeline.highQueue. The independent
    // face/saliency process() path (including still-image replay) never touches them.
    static let maximumObjectSeedAge: TimeInterval = 1.2
    static let minimumObjectTrackingQuality: Float = 0.75
    private var makeObjectSequence: ([CGRect]) -> VisionObjectSequence
    private var latestObjectFrame: VisionObjectFrame?
    private var newestObjectSeedFrame: VisionObjectFrame?
    private var pendingObjectSeed: VisionObjectSeed?
    private struct ActiveObjectSequence {
        let source: VisionObjectFrame
        let detections: [DETRDetection]
        let sequence: VisionObjectSequence
        let sourceCandidateCount: Int
        var liveSlots: Set<Int>
    }
    private var activeObjectSequence: ActiveObjectSequence?

    init(makeObjectSequence: (([CGRect]) -> VisionObjectSequence)? = nil) {
        self.makeObjectSequence = makeObjectSequence ?? { AppleVisionObjectSequence(boxes: $0) }
    }

#if DEBUG
    func setObjectSequenceFactoryForTesting(_ factory: @escaping ([CGRect]) -> VisionObjectSequence) {
        resetObjectTracking()
        makeObjectSequence = factory
    }
#endif

    func resetObjectTracking() {
        latestObjectFrame = nil
        newestObjectSeedFrame = nil
        pendingObjectSeed = nil
        activeObjectSequence = nil
    }

    /// Called on the high lane after checking the callback's pipeline lifecycle.
    /// A newer empty batch is an ordering barrier just like a positive batch.
    @discardableResult
    func offerObjectSeed(_ seed: VisionObjectSeed) -> Bool {
        guard seed.frame.isKnown else { return false }
        if let current = latestObjectFrame, !seed.frame.sharesEpoch(with: current) { return false }
        if let newest = newestObjectSeedFrame {
            guard seed.frame.sharesEpoch(with: newest),
                  CMTimeCompare(seed.frame.samplePTS, newest.samplePTS) > 0 else { return false }
        }
        newestObjectSeedFrame = seed.frame
        pendingObjectSeed = VisionObjectSeed(
            frame: seed.frame, pixelBuffer: seed.pixelBuffer,
            detections: Array(seed.detections.filter {
                Self.validObjectBox($0.boundingBox) && $0.confidence.isFinite
            }.prefix(4)),
            sourceCandidateCount: seed.sourceCandidateCount
        )
        activeObjectSequence = nil
        return true
    }

    /// Prime on original detector pixels, then measure on current pixels.
    /// No successful current measurement means no current-frame rectangle.
    func trackObjects(pixelBuffer: CVPixelBuffer,
                      frame: VisionObjectFrame,
                      evaluatedAt: Date = Date()) -> VisionObjectTrackingBatch? {
        guard frame.isKnown else {
            resetObjectTracking()
            return nil
        }
        if let previous = latestObjectFrame {
            if !previous.sharesEpoch(with: frame) {
                resetObjectTracking()
            } else if previous.frameID == frame.frameID
                        || CMTimeCompare(frame.samplePTS, previous.samplePTS) <= 0 {
                return nil
            }
        }
        if let seedFrame = newestObjectSeedFrame, !seedFrame.sharesEpoch(with: frame) {
            resetObjectTracking()
        }
        latestObjectFrame = frame
        if let pending = pendingObjectSeed {
            guard pending.frame.sharesEpoch(with: frame) else {
                pendingObjectSeed = nil
                activeObjectSequence = nil
                return nil
            }
            // Do not consume future/equal source pixels as a new measurement.
            guard CMTimeCompare(pending.frame.samplePTS, frame.samplePTS) < 0 else { return nil }
            pendingObjectSeed = nil
            guard !pending.detections.isEmpty,
                  Self.seedIsFresh(pending.frame, current: frame, evaluatedAt: evaluatedAt) else {
                activeObjectSequence = nil
                return nil
            }
            let sequence = makeObjectSequence(pending.detections.map(\.boundingBox))
            do {
                let prime = try sequence.measure(pixelBuffer: pending.pixelBuffer,
                                                 orientation: pending.frame.orientation)
                let validSlots = Set(pending.detections.indices.filter {
                    prime.indices.contains($0) && Self.objectGeometry(prime[$0], seedSlot: $0) != nil
                })
                guard !validSlots.isEmpty else { return nil }
                activeObjectSequence = ActiveObjectSequence(
                    source: pending.frame, detections: pending.detections,
                    sequence: sequence, sourceCandidateCount: pending.sourceCandidateCount,
                    liveSlots: validSlots)
            } catch {
                activeObjectSequence = nil
                return nil
            }
        }
        guard var active = activeObjectSequence,
              active.source.sharesEpoch(with: frame),
              CMTimeCompare(active.source.samplePTS, frame.samplePTS) < 0,
              Self.seedIsFresh(active.source, current: frame, evaluatedAt: evaluatedAt) else {
            activeObjectSequence = nil
            return nil
        }
        do {
            let measurements = try active.sequence.measure(pixelBuffer: pixelBuffer,
                                                          orientation: frame.orientation)
            var detections: [DETRDetection] = []
            var qualities: [Float] = []
            var geometries: [VisionObjectGeometry] = []
            for slot in active.liveSlots.sorted() {
                guard measurements.indices.contains(slot),
                      let measurement = measurements[slot],
                      let geometry = Self.objectGeometry(measurement, seedSlot: slot) else {
                    active.liveSlots.remove(slot)
                    continue
                }
                let original = active.detections[slot]
                detections.append(DETRDetection(boundingBox: geometry.visibleImageIntersection,
                                                label: original.label,
                                                confidence: original.confidence))
                qualities.append(measurement.quality)
                geometries.append(geometry)
            }
            activeObjectSequence = active.liveSlots.isEmpty ? nil : active
            guard !detections.isEmpty else { return nil }
            return VisionObjectTrackingBatch(source: active.source, current: frame,
                                             detections: detections, qualities: qualities,
                                             geometries: geometries,
                                             sourceCandidateCount: active.sourceCandidateCount)
        } catch {
            activeObjectSequence = nil
            return nil
        }
    }

    private static func seedIsFresh(_ source: VisionObjectFrame,
                                    current: VisionObjectFrame,
                                    evaluatedAt: Date) -> Bool {
        let captureAge = current.capturedAt.timeIntervalSince(source.capturedAt)
        let evaluationAge = evaluatedAt.timeIntervalSince(source.capturedAt)
        let ptsAge = CMTimeGetSeconds(CMTimeSubtract(current.samplePTS, source.samplePTS))
        return captureAge >= 0 && evaluationAge >= captureAge
            && evaluationAge <= maximumObjectSeedAge
            && ptsAge > 0 && ptsAge <= maximumObjectSeedAge
    }

    static func validObjectBox(_ box: CGRect) -> Bool {
        [box.minX, box.minY, box.width, box.height, box.maxX, box.maxY].allSatisfy(\.isFinite)
            && box.width > 0 && box.height > 0
            && box.minX >= 0 && box.minY >= 0 && box.maxX <= 1 && box.maxY <= 1
    }

    private static func objectGeometry(_ value: VisionObjectMeasurement?, seedSlot: Int) -> VisionObjectGeometry? {
        guard let value, value.quality.isFinite,
              value.quality >= minimumObjectTrackingQuality, value.quality <= 1,
              let geometry = VisionObjectGeometry(seedSlot: seedSlot, rawBoundingBox: value.boundingBox),
              geometry.meetsPublicationArea else { return nil }
        return geometry
    }

    func process(pixelBuffer: CVPixelBuffer,
                 orientation: CGImagePropertyOrientation) -> VisionTrackingResult {
        var results: [TrackedSubject] = []
        var saliencyCenter: CGPoint?
        var saliencyRegion: CGRect?
        
        frameCount += 1
        let shouldLog = CameraLog.vision && frameCount % 30 == 0

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: orientation,
                                            options: [:])
        do {
            try handler.perform([faceRequest, humanRequest, saliencyRequest])

            if let faces = faceRequest.results as? [VNFaceObservation] {
                if shouldLog {
                    os_log("👤 Vision: %d faces found", log: log, type: .debug, faces.count)
                    for (i, face) in faces.enumerated() {
                        os_log("  Face %d: bbox=(%.2f,%.2f,%.2f,%.2f) conf=%.2f", 
                               log: log, type: .debug, i,
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
                os_log("👤 Vision: No faces detected", log: log, type: .debug)
            }

            if let humans = humanRequest.results as? [VNDetectedObjectObservation] {
                let filtered = humans.filter { human in
                    !results.contains { $0.boundingBox.intersects(human.boundingBox) }
                }
                if shouldLog {
                    os_log("🚶 Vision: %d humans (filtered: %d)", log: log, type: .debug, humans.count, filtered.count)
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
                saliencyRegion = top.boundingBox
                if let prev = saliencyEMA {
                    let dx = rawCenter.x - prev.x
                    let dy = rawCenter.y - prev.y
                    let distance = sqrt(dx*dx + dy*dy)
                    if distance < saliencyDeadband {
                        saliencyCenter = prev
                        if shouldLog {
                            os_log("🎯 Saliency: within deadband, keeping prev (%.3f,%.3f)", 
                                   log: log, type: .debug, prev.x, prev.y)
                        }
                    } else {
                        let newX = prev.x * (1 - saliencyAlpha) + rawCenter.x * saliencyAlpha
                        let newY = prev.y * (1 - saliencyAlpha) + rawCenter.y * saliencyAlpha
                        let smoothed = CGPoint(x: newX, y: newY)
                        saliencyEMA = smoothed
                        saliencyCenter = smoothed
                        if shouldLog {
                            os_log("🎯 Saliency: raw=(%.3f,%.3f) smoothed=(%.3f,%.3f) dist=%.4f", 
                                   log: log, type: .debug,
                                   rawCenter.x, rawCenter.y, smoothed.x, smoothed.y, distance)
                        }
                    }
                } else {
                    saliencyEMA = rawCenter
                    saliencyCenter = rawCenter
                    if shouldLog {
                        os_log("🎯 Saliency: initial center (%.3f,%.3f)", 
                               log: log, type: .debug, rawCenter.x, rawCenter.y)
                    }
                }
            } else if shouldLog {
                os_log("🎯 Saliency: No salient objects found", log: log, type: .debug)
            }
        } catch {
            os_log("❌ Vision error: %{private}@", log: log, type: .error, error.localizedDescription)
            return VisionTrackingResult(subjects: results, saliencyCenter: nil, saliencyRegion: nil, faceCount: 0, personCount: 0)
        }

        let faces = results.filter { $0.isFace }.count
        let persons = results.count
        return VisionTrackingResult(subjects: results, saliencyCenter: saliencyCenter, saliencyRegion: saliencyRegion, faceCount: faces, personCount: persons)
    }
}
