//
//  UserMovementObserver.swift
//  shafinMultitool
//
//  M2-023: classify action-relevant movement from accepted feature evidence.
//  The observer is pure; the tracker only preserves the existing frame-to-
//  frame streak state. Neither uses elapsed time as a success signal.
//

import CoreMedia
import Foundation

/// The action families for which Camera Coach can observe a feature change.
enum UserMovementActionFamily: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case subjectDisplacement = "subject_displacement"
    case scaleDistance = "scale_distance"
    case horizonRotation = "horizon_rotation"
    case lightExposure = "light_exposure"
    case focus
    case stability

    // Compatibility spellings; these do not create additional families.
    static var scale: Self { .scaleDistance }
    static var rotation: Self { .horizonRotation }
    static var light: Self { .lightExposure }
}

/// C04.2/N4 visibility of one commanded or protected entity on one frame.
/// `absent` is an explicit owner statement ("the entity is not in the scene");
/// it is never inferred from a missing optional or from a detector returning
/// no box. The verifier must distinguish "observed leaving" from "not found".
enum UserMovementEntityVisibility: String, Codable, CaseIterable, Equatable, Sendable {
    case visible
    case partial
    case absent
}

/// C04.2/N7 one entity-scoped observation. `entityRef` is the action-local
/// reference; `trackID` is the frozen track binding when the identity owner
/// produced one. A visible/partial observation carries a valid region; an
/// absent observation must not carry one, so a stale rectangle cannot be read
/// as a current sighting.
struct UserMovementEntityObservation: Equatable, Sendable {
    let entityRef: String
    let trackID: String?
    let visibility: UserMovementEntityVisibility
    let region: NormalizedRect?
    /// Present only for a measurement linked to the accepted production pixels.
    /// Legacy fixtures may omit it; the production frame adapter may not.
    let provenance: UserMovementEntityProvenance?

    init?(entityRef: String,
          trackID: String? = nil,
          visibility: UserMovementEntityVisibility,
          region: NormalizedRect? = nil,
          provenance: UserMovementEntityProvenance? = nil) {
        let trimmedRef = entityRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRef.isEmpty else { return nil }
        let trimmedTrack = trackID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let provenance {
            guard provenance.isStructurallyValid,
                  trimmedRef == provenance.observationRef,
                  trimmedTrack == provenance.identity.trackID,
                  visibility == (provenance.clippedEdges == 0 ? .visible : .partial),
                  let measuredRegion = provenance.measuredRegion,
                  region == measuredRegion else { return nil }
        }
        if visibility == .absent {
            guard region == nil else { return nil }
        } else {
            guard let region,
                  region.x.isFinite,
                  region.y.isFinite,
                  region.width.isFinite,
                  region.height.isFinite,
                  !region.isDegenerate,
                  region.x >= 0,
                  region.y >= 0,
                  region.x + region.width <= 1,
                  region.y + region.height <= 1 else {
                return nil
            }
        }
        self.entityRef = trimmedRef
        self.trackID = (trimmedTrack?.isEmpty == false) ? trimmedTrack : nil
        self.visibility = visibility
        self.region = region
        self.provenance = provenance
    }

    var isObserved: Bool {
        visibility != .absent && region != nil
    }

    /// Clipped rectangle centres can move when the visible intersection changes.
    /// They remain observations, but cannot establish an entity displacement.
    var hasComparableGeometry: Bool { visibility == .visible && region != nil }
}

/// The detector's semantic clock and Vision's current geometry clock remain
/// separate. Rectangle visibility is not physical full visibility or motion.
struct UserMovementEntityProvenance: Equatable, Sendable {
    let identity: SubjectTrackIdentity
    let frameID: String
    let sampleSequence: UInt64
    let sessionGeneration: UInt64
    let pipelineGeneration: UInt64
    let orientationRawValue: UInt32
    let samplePresentationTimestamp: CMTime
    let capturedAt: Date
    let semanticSourceFrameID: String
    let semanticSamplePresentationTimestamp: CMTime
    let semanticMeasuredAt: Date
    let geometryMeasuredAt: Date
    let semanticSupport: Double
    let trackingQuality: Float
    /// Internal request association within semanticSourceFrameID, never identity.
    let sourceRequestSlot: Int
    let rawBoundingBox: CGRect
    let visibleImageIntersection: CGRect
    let rectangleClippedFraction: Double
    let clippedEdges: UInt8

    /// A stable observation reference that an accepted action may explicitly
    /// freeze later. Producing the reference does not create a target or scope.
    var observationRef: String { "object:\(identity.generation):\(identity.trackID)" }

    var isStructurallyValid: Bool {
        let captureAge = capturedAt.timeIntervalSince(semanticMeasuredAt)
        let measuredAge = geometryMeasuredAt.timeIntervalSince(semanticMeasuredAt)
        let ptsAge = CMTimeGetSeconds(CMTimeSubtract(samplePresentationTimestamp,
                                                   semanticSamplePresentationTimestamp))
        return identity.isValid && identity.generation != 0 && sampleSequence > 0
            && !frameID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !semanticSourceFrameID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && frameID != semanticSourceFrameID
            && (1...8).contains(orientationRawValue)
            && samplePresentationTimestamp.isNumeric && semanticSamplePresentationTimestamp.isNumeric
            && ptsAge.isFinite && ptsAge > 0 && ptsAge <= VisionTracking.maximumObjectSeedAge
            && capturedAt.timeIntervalSinceReferenceDate.isFinite
            && semanticMeasuredAt.timeIntervalSinceReferenceDate.isFinite
            && geometryMeasuredAt.timeIntervalSinceReferenceDate.isFinite
            && captureAge >= 0 && measuredAge >= captureAge
            && measuredAge <= VisionTracking.maximumObjectSeedAge
            && semanticSupport.isFinite && (0...1).contains(semanticSupport)
            && trackingQuality.isFinite && trackingQuality >= VisionTracking.minimumObjectTrackingQuality
            && trackingQuality <= 1 && measuredRegion != nil
    }

    var measuredRegion: NormalizedRect? {
        guard let geometry = VisionObjectGeometry(seedSlot: sourceRequestSlot, rawBoundingBox: rawBoundingBox),
              geometry.meetsPublicationArea,
              geometry.visibleImageIntersection == visibleImageIntersection,
              geometry.rectangleClippedFraction == rectangleClippedFraction,
              geometry.clippedEdges.rawValue == clippedEdges else { return nil }
        let box = geometry.visibleImageIntersection
        return NormalizedRect(x: Double(box.origin.x), y: Double(box.origin.y),
                              width: Double(box.size.width), height: Double(box.size.height))
            .converted(from: .vision, to: .subjectTarget)
    }

    func matches(envelope: AcceptedFrameEnvelope, pipelineGeneration: UInt64?, asOf: Date) -> Bool {
        let age = asOf.timeIntervalSince(capturedAt)
        let semanticAge = asOf.timeIntervalSince(semanticMeasuredAt)
        return isStructurallyValid && identity.generation == envelope.lensGeneration
            && frameID == envelope.frameID && capturedAt == envelope.capturedAt
            && sessionGeneration == envelope.sessionGeneration
            && self.pipelineGeneration == pipelineGeneration
            && orientationRawValue == envelope.orientation.rawValue
            && envelope.samplePresentationTimestamp.isNumeric
            && CMTimeCompare(samplePresentationTimestamp, envelope.samplePresentationTimestamp) == 0
            && semanticMeasuredAt == envelope.featureSourceTimestamps[.detr]
            && age.isFinite && age >= 0
            && age * 1000 <= Double(LiveCoachQualityGate.maxVisionFreshnessMilliseconds)
            && geometryMeasuredAt >= capturedAt && geometryMeasuredAt <= asOf
            && semanticAge.isFinite && semanticAge >= 0
            && semanticAge <= min(VisionTracking.maximumObjectSeedAge,
                                  FeatureSourceFreshnessWindows.window(for: .detr))
    }

    /// Only current identities with exactly one corresponding current rectangle
    /// can produce an observation. Missing/lost/ambiguous objects produce none;
    /// an empty list never means that an entity is explicitly absent.
    static func observations(frame: ObjectTrackFrame,
                             sample: FeatureSample<FeatureSnapshotDetrPayload>,
                             pipelineGeneration: UInt64) -> [UserMovementEntityObservation] {
        guard sample.hasValidTrackingLinkage, let tracking = sample.value.tracking,
              tracking.current.lifecycleGeneration == pipelineGeneration,
              frame.frameID == tracking.current.frameID,
              frame.generation == tracking.current.captureGeneration,
              frame.capturedAt == tracking.current.capturedAt,
              let sessionGeneration = tracking.current.sessionGeneration else { return [] }
        let objects = frame.currentObjects
        let detections = sample.value.detections
        func matches(_ object: ObjectTrackState, _ detection: FeatureSnapshotDetectedObject) -> Bool {
            // These labels/rectangles were copied unchanged through the existing
            // candidate owner. A label alone, overlap or nearest centre is not a join.
            guard let region = object.region, object.label == detection.label else { return false }
            let box = detection.boundingBox
            return region == NormalizedRect(x: Double(box.origin.x), y: Double(box.origin.y),
                                            width: Double(box.size.width), height: Double(box.size.height))
        }
        return objects.compactMap { object in
            let indices = detections.indices.filter { matches(object, detections[$0]) }
            guard object.identity.isValid, indices.count == 1, let index = indices.first,
                  objects.filter({ matches($0, detections[index]) }).count == 1,
                  objects.filter({ $0.identity.trackID == object.identity.trackID }).count == 1,
                  let region = object.region?.converted(from: .vision, to: .subjectTarget) else { return nil }
            let geometry = tracking.geometries[index]
            let provenance = Self(
                identity: object.identity, frameID: frame.frameID, sampleSequence: frame.sampleSequence,
                sessionGeneration: sessionGeneration, pipelineGeneration: pipelineGeneration,
                orientationRawValue: tracking.current.orientation.rawValue,
                samplePresentationTimestamp: tracking.current.samplePTS, capturedAt: frame.capturedAt,
                semanticSourceFrameID: tracking.source.frameID,
                semanticSamplePresentationTimestamp: tracking.source.samplePTS,
                semanticMeasuredAt: tracking.source.capturedAt, geometryMeasuredAt: tracking.geometryMeasuredAt,
                semanticSupport: detections[index].confidence, trackingQuality: tracking.qualities[index],
                sourceRequestSlot: geometry.seedSlot, rawBoundingBox: geometry.rawBoundingBox,
                visibleImageIntersection: geometry.visibleImageIntersection,
                rectangleClippedFraction: geometry.rectangleClippedFraction,
                clippedEdges: geometry.clippedEdges.rawValue
            )
            return UserMovementEntityObservation(
                entityRef: provenance.observationRef, trackID: object.identity.trackID,
                // `visible` means a current rectangle is observed. It does not
                // certify that the whole physical object is unoccluded.
                visibility: geometry.hasClippedTrackingGeometry ? .partial : .visible,
                region: region, provenance: provenance
            )
        }
    }
}

/// Values copied from the production feature snapshot. Missing values stay
/// missing; the observer never substitutes a timer or an unrelated feature.
struct UserMovementMetrics: Equatable, Sendable {
    let subjectAreaRatio: Double?
    /// Optional depth proxy from a future geometry producer. It remains nil
    /// when the live pipeline has no honest depth measurement.
    let subjectBackgroundDepth: Double?
    let horizonAngleDegrees: Double?
    let exposureBiasHint: Double?
    /// Explicit technical predicate; never inferred from exposureBiasHint.
    let exposureFault: ExposureFaultState?
    let subjectMeanLuma: Double?
    let backgroundMeanLuma: Double?
    let subjectToBackgroundDelta: Double?
    let backgroundHotspotRatio: Double?
    /// Focus evidence is optional until a live focus producer is connected.
    let focusIsDefocused: Bool?
    let focusReadability: Double?
    let stabilityScore: Double?
    let shakeLevel: Double?

    init(subjectAreaRatio: Double? = nil,
         subjectBackgroundDepth: Double? = nil,
         horizonAngleDegrees: Double? = nil,
         exposureBiasHint: Double? = nil,
         exposureFault: ExposureFaultState? = nil,
         subjectMeanLuma: Double? = nil,
         backgroundMeanLuma: Double? = nil,
         subjectToBackgroundDelta: Double? = nil,
         backgroundHotspotRatio: Double? = nil,
         focusIsDefocused: Bool? = nil,
         focusReadability: Double? = nil,
         stabilityScore: Double? = nil,
         shakeLevel: Double? = nil) {
        self.subjectAreaRatio = subjectAreaRatio
        self.subjectBackgroundDepth = subjectBackgroundDepth
        self.horizonAngleDegrees = horizonAngleDegrees
        self.exposureBiasHint = exposureBiasHint
        self.exposureFault = exposureFault
        self.subjectMeanLuma = subjectMeanLuma
        self.backgroundMeanLuma = backgroundMeanLuma
        self.subjectToBackgroundDelta = subjectToBackgroundDelta
        self.backgroundHotspotRatio = backgroundHotspotRatio
        self.focusIsDefocused = focusIsDefocused
        self.focusReadability = focusReadability
        self.stabilityScore = stabilityScore
        self.shakeLevel = shakeLevel
    }
}

    /// Typed binding between a tracked subject and the feature source that
    /// measured its region. A free-form track string is not sufficient evidence:
    /// the binding carries the stable M2-010 identity, frame, source, coordinate
    /// space, timestamp, and confidence together. `identity.generation` is the
    /// shared capture generation passed by SubjectTracker and written by the
    /// pipeline into `AcceptedFrameEnvelope.lensGeneration`.
struct UserMovementSubjectBinding: Sendable {
    let identity: SubjectTrackIdentity
    let frameID: String
    let region: NormalizedRect
    let source: FeatureSourceID
    let coordinateSpace: CameraCoordinateSpaceV2
    let measuredAt: Date
    let confidence: Double

    init?(identity: SubjectTrackIdentity,
          frameID: String,
          region: NormalizedRect,
          source: FeatureSourceID,
          coordinateSpace: CameraCoordinateSpaceV2,
          measuredAt: Date,
          confidence: Double) {
        let trimmedFrameID = frameID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard identity.isValid,
              identity.generation != 0,
              !trimmedFrameID.isEmpty,
              region.x.isFinite,
              region.y.isFinite,
              region.width.isFinite,
              region.height.isFinite,
              !region.isDegenerate,
              region.x >= 0,
              region.y >= 0,
              region.x + region.width <= 1,
              region.y + region.height <= 1,
              source == .vision || source == .detr,
              coordinateSpace == .vision || coordinateSpace == .subjectTarget,
              measuredAt.timeIntervalSinceReferenceDate.isFinite,
              confidence.isFinite,
              (0...1).contains(confidence) else {
            return nil
        }
        self.identity = identity
        self.frameID = trimmedFrameID
        self.region = region
        self.source = source
        self.coordinateSpace = coordinateSpace
        self.measuredAt = measuredAt
        self.confidence = confidence
    }

    /// Converts the source rectangle through the existing canonical
    /// Vision-y-up ↔ coaching-y-down conversion. Rotation/mirroring is still
    /// owned by `CameraDisplayTransform`/Vision request orientation.
    var coachingRegion: NormalizedRect? {
        region.converted(from: coordinateSpace, to: .subjectTarget)
    }
}

extension UserMovementSubjectBinding: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identity == rhs.identity
            && lhs.frameID == rhs.frameID
            && lhs.region == rhs.region
            && lhs.source.rawValue == rhs.source.rawValue
            && lhs.coordinateSpace.rawValue == rhs.coordinateSpace.rawValue
            && lhs.measuredAt == rhs.measuredAt
            && lhs.confidence == rhs.confidence
    }
}

/// Provenance for the feature values in one frame. Source timestamps are
/// keyed by family because Vision, horizon, lighting, and motion have
/// different producers and freshness windows in the accepted-frame pipeline.
struct UserMovementEvidence: Equatable, Sendable {
    let capturedAt: Date
    let evaluatedAt: Date
    /// Exact sample presentation time copied from the capture buffer. This is
    /// the ordering source inside one known camera session/capture epoch;
    /// `capturedAt` remains callback-arrival freshness only.
    let samplePresentationTimestamp: CMTime
    /// CameraManager lifecycle/session epoch that produced this sample.
    /// `nil` is retained only for legacy synthetic evidence.
    let sessionGeneration: UInt64?
    /// Shared pipeline capture generation; this is the same generation
    /// SubjectTracker stores in SubjectTrackIdentity.generation.
    let lensGeneration: UInt64
    /// Compatibility metadata only. Action-aware validation uses the typed
    /// binding below, never this arbitrary string.
    let subjectTrackID: String?
    let subjectBinding: UserMovementSubjectBinding?
    let orientation: CameraCoachOrientation
    let isCalibrated: Bool
    let calibrationVersion: String?
    let featureMeasuredAt: [UserMovementActionFamily: Date]
    let featureConfidence: [UserMovementActionFamily: Double]
    let sourceAvailability: [UserMovementActionFamily: Bool]

    init(capturedAt: Date,
         evaluatedAt: Date? = nil,
         samplePresentationTimestamp: CMTime = .invalid,
         sessionGeneration: UInt64? = nil,
         lensGeneration: UInt64,
         subjectTrackID: String?,
         subjectBinding: UserMovementSubjectBinding? = nil,
         orientation: CameraCoachOrientation,
         isCalibrated: Bool,
         calibrationVersion: String? = nil,
         featureMeasuredAt: [UserMovementActionFamily: Date] = [:],
         featureConfidence: [UserMovementActionFamily: Double] = [:],
         sourceAvailability: [UserMovementActionFamily: Bool] = [:]) {
        self.capturedAt = capturedAt
        self.evaluatedAt = evaluatedAt ?? capturedAt
        self.samplePresentationTimestamp = samplePresentationTimestamp
        self.sessionGeneration = sessionGeneration
        self.lensGeneration = lensGeneration
        self.subjectTrackID = subjectTrackID
        self.subjectBinding = subjectBinding
        self.orientation = orientation
        self.isCalibrated = isCalibrated
        self.calibrationVersion = calibrationVersion
        self.featureMeasuredAt = featureMeasuredAt
        self.featureConfidence = featureConfidence
        self.sourceAvailability = sourceAvailability
    }

    /// A production provenance tuple is complete only when all three
    /// ordering components are present. Partial metadata is invalid rather
    /// than silently falling back to callback arrival time.
    var hasKnownSampleProvenance: Bool {
        lensGeneration != 0
            && sessionGeneration != nil
            && samplePresentationTimestamp.isNumeric
    }

    var hasPartialSampleProvenance: Bool {
        sessionGeneration != nil || samplePresentationTimestamp.isNumeric
    }

    var hasValidSampleProvenanceShape: Bool {
        !hasPartialSampleProvenance || hasKnownSampleProvenance
    }
}

/// One accepted-frame observation in canonical normalized coordinates
/// (M2-002/M2-003). The four-argument initializer preserves the original
/// lightweight displacement/luma call sites; action-aware observation needs
/// the production evidence initializer below.
struct UserMovementFrame: Equatable, Sendable {
    let frameID: String
    let subjectRegion: NormalizedRect?
    let meanLuma: Double
    let motionIsStill: Bool
    let metrics: UserMovementMetrics
    let evidence: UserMovementEvidence?
    /// C04.2/N7 entity-scoped observations for the action target and the
    /// protected refs. Empty for legacy frames; the verifier then fails closed
    /// for any declared target/protected scope.
    let entityObservations: [UserMovementEntityObservation]

    init(frameID: String,
         subjectRegion: NormalizedRect?,
         meanLuma: Double,
         motionIsStill: Bool) {
        self.init(frameID: frameID,
                  subjectRegion: subjectRegion,
                  meanLuma: meanLuma,
                  motionIsStill: motionIsStill,
                  metrics: UserMovementMetrics())
    }

    init(frameID: String,
         subjectRegion: NormalizedRect?,
         meanLuma: Double,
         motionIsStill: Bool,
         metrics: UserMovementMetrics,
         evidence: UserMovementEvidence? = nil,
         entityObservations: [UserMovementEntityObservation] = []) {
        self.frameID = frameID
        self.subjectRegion = subjectRegion
        self.meanLuma = meanLuma
        self.motionIsStill = motionIsStill
        self.metrics = metrics
        self.evidence = evidence
        self.entityObservations = entityObservations
    }

    /// Exact-ref lookup. Two observations with the same ref are a producer bug
    /// and are treated as missing so a duplicated ref cannot widen scope.
    func entityObservation(for entityRef: String) -> UserMovementEntityObservation? {
        let matches = entityObservations.filter { $0.entityRef == entityRef }
        return matches.count == 1 ? matches[0] : nil
    }

    /// Adapter at the existing feature/envelope boundary. Subject-dependent
    /// actions may provide a selected/tracked source binding; frame-global
    /// horizon and stability actions may legitimately omit it. A free track ID
    /// cannot attribute a mixed Vision/DETR primary candidate.
    init?(snapshot: FrameFeatureSnapshot,
          envelope: AcceptedFrameEnvelope,
          subjectBinding: UserMovementSubjectBinding?,
          entityObservations: [UserMovementEntityObservation] = [],
          pipelineGeneration: UInt64? = nil,
          evaluatedAt: Date? = nil,
          isCalibrated: Bool,
          calibrationVersion: String? = nil,
          orientation: CameraCoachOrientation) {
        guard envelope.matches(frameID: snapshot.frameId),
              snapshot.capturedAt == envelope.capturedAt,
              orientation.imageOrientation == envelope.orientation,
              !snapshot.frameId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              envelope.isLensGenerationKnown else {
            return nil
        }

        let asOf = evaluatedAt ?? envelope.capturedAt
        guard envelope.capturedAt <= asOf else { return nil }
        guard Set(entityObservations.map(\.entityRef)).count == entityObservations.count,
              entityObservations.allSatisfy({ observation in
                  guard let provenance = observation.provenance,
                        observation.entityRef == provenance.observationRef,
                        observation.trackID == provenance.identity.trackID,
                        observation.isObserved,
                        provenance.matches(envelope: envelope, pipelineGeneration: pipelineGeneration, asOf: asOf)
                  else { return false }
                  return snapshot.sources.detr.available
              }) else { return nil }
        let envelopeAvailability = envelope.sourceAvailability(asOf: asOf)
        let subjectRegion: NormalizedRect?
        let subjectMeasuredAt: Date?
        let subjectConfidence: Double?
        if let subjectBinding {
            guard subjectBinding.coordinateSpace == .vision,
                  subjectBinding.frameID == snapshot.frameId,
                  snapshot.subjectSignals.primaryCandidateRegion == subjectBinding.region,
                  snapshot.subjectSignals.primaryCandidateSource == subjectBinding.source,
                  // SubjectTracker's capture generation is stored in the
                  // accepted envelope under its legacy lensGeneration name.
                  subjectBinding.identity.generation == envelope.lensGeneration,
                  let measuredAt = envelope.featureSourceTimestamps[subjectBinding.source],
                  measuredAt == subjectBinding.measuredAt else {
                return nil
            }

            let sourceAvailable: Bool
            let sourceConfidence: Double?
            switch subjectBinding.source {
            case .vision:
                sourceAvailable = envelopeAvailability[.vision] == true && snapshot.sources.vision.available
                sourceConfidence = snapshot.sources.vision.confidence
            case .detr:
                sourceAvailable = envelopeAvailability[.detr] == true && snapshot.sources.detr.available
                sourceConfidence = snapshot.sources.detr.confidence
            default:
                return nil
            }
            guard sourceAvailable, let coachingRegion = subjectBinding.coachingRegion else { return nil }
            subjectRegion = coachingRegion
            subjectMeasuredAt = measuredAt
            subjectConfidence = sourceConfidence.map { min(subjectBinding.confidence, $0) }
        } else {
            subjectRegion = nil
            subjectMeasuredAt = nil
            subjectConfidence = nil
        }

        let horizonAvailable = envelopeAvailability[.horizon] == true && snapshot.sources.horizon.available
        let lightingAvailable = subjectBinding != nil
            && envelopeAvailability[.lighting] == true
            && snapshot.sources.lighting.available
            && snapshot.sources.lighting.confidence != nil
        let lighting = lightingAvailable ? snapshot.lighting.subjectLighting : nil

        var measuredAt: [UserMovementActionFamily: Date] = [.stability: envelope.capturedAt]
        if let subjectMeasuredAt {
            measuredAt[.subjectDisplacement] = subjectMeasuredAt
            measuredAt[.scaleDistance] = subjectMeasuredAt
        }
        if let date = envelope.featureSourceTimestamps[.horizon] {
            measuredAt[.horizonRotation] = date
        }
        if lightingAvailable, let date = envelope.featureSourceTimestamps[.lighting] {
            measuredAt[.lightExposure] = date
        }

        var confidence: [UserMovementActionFamily: Double] = [.stability: 1.0]
        if let subjectConfidence {
            confidence[.subjectDisplacement] = subjectConfidence
            confidence[.scaleDistance] = subjectConfidence
        }
        if horizonAvailable, let horizonConfidence = snapshot.sources.horizon.confidence {
            confidence[.horizonRotation] = horizonConfidence
        }
        if lightingAvailable, let lightingConfidence = snapshot.sources.lighting.confidence {
            confidence[.lightExposure] = lightingConfidence
        }

        var sourceAvailability: [UserMovementActionFamily: Bool] = [.stability: true]
        if subjectBinding != nil {
            sourceAvailability[.subjectDisplacement] = subjectRegion != nil
            sourceAvailability[.scaleDistance] = subjectRegion != nil
            sourceAvailability[.lightExposure] = lightingAvailable
        }
        sourceAvailability[.horizonRotation] = horizonAvailable

        self.init(
            frameID: snapshot.frameId,
            subjectRegion: subjectRegion,
            // This field is retained for the legacy observer only. Subject
            // light actions read the measured subject metric below.
            meanLuma: lighting?.subjectMeanLuma ?? 0,
            motionIsStill: snapshot.motion.state == .still,
            metrics: UserMovementMetrics(
                subjectAreaRatio: subjectRegion.map { $0.width * $0.height },
                horizonAngleDegrees: horizonAvailable ? snapshot.horizon.angleDegrees : nil,
                exposureBiasHint: lightingAvailable ? snapshot.lighting.exposureBiasHint : nil,
                subjectMeanLuma: lighting?.subjectMeanLuma,
                backgroundMeanLuma: lighting?.backgroundMeanLuma,
                subjectToBackgroundDelta: lighting?.subjectToBackgroundDelta,
                backgroundHotspotRatio: lighting?.backgroundHotspotRatio,
                stabilityScore: 1.0 - snapshot.motion.shakeLevel,
                shakeLevel: snapshot.motion.shakeLevel
            ),
            evidence: UserMovementEvidence(
                capturedAt: envelope.capturedAt,
                evaluatedAt: asOf,
                samplePresentationTimestamp: envelope.samplePresentationTimestamp,
                sessionGeneration: envelope.sessionGeneration,
                lensGeneration: envelope.lensGeneration,
                subjectTrackID: subjectBinding?.identity.trackID,
                subjectBinding: subjectBinding,
                orientation: orientation,
                isCalibrated: isCalibrated,
                calibrationVersion: calibrationVersion,
                featureMeasuredAt: measuredAt,
                featureConfidence: confidence,
                sourceAvailability: sourceAvailability
            ),
            entityObservations: entityObservations
        )
    }
}

enum UserMovementVerdict: Equatable, Sendable {
    case relevant
    case noOp
    case opposite
    case uncertain(reason: String)
}

/// Detailed form of the existing movement comparison. The verifier consumes
/// this instead of maintaining a second action-to-metric switch. For a
/// directional placement action, `beforeValue` is zero and `afterValue` is
/// the projected displacement in the requested direction.
struct UserMovementComparison: Equatable, Sendable {
    let family: UserMovementActionFamily?
    let metric: ActionVerificationMetric?
    let beforeValue: Double?
    let afterValue: Double?
    let delta: Double?
    let directedDelta: Double?
    let deadband: Double?
    let verdict: UserMovementVerdict

    static func uncertain(reason: String,
                          family: UserMovementActionFamily? = nil,
                          metric: ActionVerificationMetric? = nil) -> Self {
        Self(family: family,
             metric: metric,
             beforeValue: nil,
             afterValue: nil,
             delta: nil,
             directedDelta: nil,
             deadband: nil,
             verdict: .uncertain(reason: reason))
    }
}

/// Pure action-aware movement classifier. Evidence age is a validity gate,
/// not a completion heuristic; completion remains the tracker's frame streak.
enum UserMovementObserver {
    static let movementDeadband = 0.03
    static let lumaChangeThreshold = 0.12
    static let scaleDeadband = 0.03
    static let rotationDeadbandDegrees = 1.0
    static let scalarDeadband = 0.05
    static let minimumEvidenceConfidence = 0.5

    /// Source-compatible displacement/luma observer.
    static func observe(previous: UserMovementFrame,
                        current: UserMovementFrame,
                        desiredDisplacement: (dx: Double, dy: Double),
                        displayTransform: CameraDisplayTransform? = nil) -> UserMovementVerdict {
        guard current.motionIsStill else { return .uncertain(reason: "camera_motion") }
        guard let previousRegion = previous.subjectRegion,
              let currentRegion = current.subjectRegion,
              !previousRegion.isDegenerate,
              !currentRegion.isDegenerate else {
            return .uncertain(reason: "subject_missing")
        }

        let previousCenter = center(of: previousRegion, transform: displayTransform)
        let currentCenter = center(of: currentRegion, transform: displayTransform)
        let dx = currentCenter.x - previousCenter.x
        let dy = currentCenter.y - previousCenter.y
        if desiredDisplacement.dx == 0, desiredDisplacement.dy == 0 {
            let delta = current.meanLuma - previous.meanLuma
            return abs(delta) >= lumaChangeThreshold ? .relevant : .noOp
        }
        return directionalVerdict(dx: dx, dy: dy, desired: desiredDisplacement, deadband: movementDeadband)
    }

    static func observe(previous: UserMovementFrame,
                        current: UserMovementFrame,
                        action: SemanticActionType,
                        asOf: Date? = nil) -> UserMovementVerdict {
        observe(previous: previous, current: current, actionID: action.rawValue, asOf: asOf)
    }

    static func observe(previous: UserMovementFrame,
                        current: UserMovementFrame,
                        action: TechnicalQualityActionType,
                        asOf: Date? = nil) -> UserMovementVerdict {
        observe(previous: previous, current: current, actionID: action.rawValue, asOf: asOf)
    }

    static func observe(previous: UserMovementFrame,
                        current: UserMovementFrame,
                        actionID: String,
                        targetRefs: [String] = [],
                        asOf: Date? = nil) -> UserMovementVerdict {
        compare(previous: previous,
                current: current,
                actionID: actionID,
                targetRefs: targetRefs,
                asOf: asOf).verdict
    }

    /// Returns the existing action-aware comparison plus the finite metric
    /// used to classify it. The action mapping and deadbands remain owned by
    /// this observer; M2-025 only consumes the extracted detail.
    ///
    /// C04.2: `targetRefs` scopes a displacement/scale comparison to the
    /// commanded entity instead of the primary subject. Movement of a
    /// different object (for example `lampB` when `lampA` was commanded) must
    /// not be read as the commanded change. An empty list preserves the legacy
    /// subject-region behaviour.
    static func compare(previous: UserMovementFrame,
                        current: UserMovementFrame,
                        actionID: String,
                        targetRefs: [String] = [],
                        asOf: Date? = nil) -> UserMovementComparison {
        guard let intent = intent(for: actionID) else {
            return .uncertain(reason: "unsupported_action")
        }
        if let reason = evidenceFailure(previous: previous,
                                        current: current,
                                        family: intent.family,
                                        asOf: asOf) {
            return .uncertain(reason: reason, family: intent.family, metric: metricID(for: intent.metric, displacement: intent.displacement))
        }
        return evaluate(previous: previous,
                        current: current,
                        intent: intent,
                        targetRefs: targetRefs)
    }

    /// Compares a coordinator baseline and final frame without re-aging the
    /// baseline against the final callback. Each accepted frame is validated
    /// against its own evaluation time; this keeps the observer's freshness
    /// policy intact while allowing a bounded episode to span several frames.
    static func compareAtOwnEvaluationTimes(previous: UserMovementFrame,
                                            current: UserMovementFrame,
                                            actionID: String,
                                            targetRefs: [String] = []) -> UserMovementComparison {
        guard let intent = intent(for: actionID) else {
            return .uncertain(reason: "unsupported_action")
        }
        if let reason = evidenceFailureAtOwnEvaluationTimes(
            previous: previous,
            current: current,
            family: intent.family
        ) {
            return .uncertain(
                reason: reason,
                family: intent.family,
                metric: metricID(for: intent.metric, displacement: intent.displacement)
            )
        }
        return evaluate(previous: previous,
                        current: current,
                        intent: intent,
                        targetRefs: targetRefs)
    }

    /// Descriptive alias for callers that want to make the before/after
    /// boundary explicit at the call site.
    static func detailedComparison(previous: UserMovementFrame,
                                  current: UserMovementFrame,
                                  actionID: String,
                                  targetRefs: [String] = [],
                                  asOf: Date? = nil) -> UserMovementComparison {
        compare(previous: previous,
                current: current,
                actionID: actionID,
                targetRefs: targetRefs,
                asOf: asOf)
    }

    static func actionFamily(for actionID: String) -> UserMovementActionFamily? {
        intent(for: actionID)?.family
    }

    static func actionFamily(for action: SemanticActionType) -> UserMovementActionFamily? {
        actionFamily(for: action.rawValue)
    }

    static func actionFamily(for action: TechnicalQualityActionType) -> UserMovementActionFamily? {
        actionFamily(for: action.rawValue)
    }

    private enum Relation { case increase, decrease, absoluteChange }
    private enum Metric: Equatable {
        case area, depth, horizon, exposure, subjectLuma, backgroundLuma
        case separation, hotspot, focus, stability
    }
    private struct ActionIntent {
        let family: UserMovementActionFamily
        let displacement: (dx: Double, dy: Double)?
        let metric: Metric?
        let relation: Relation?
    }

    private static func intent(for actionID: String) -> ActionIntent? {
        switch actionID {
        case SemanticActionType.shiftFrameLeft.rawValue:
            return move((1, 0))
        case SemanticActionType.shiftFrameRight.rawValue:
            return move((-1, 0))
        case SemanticActionType.shiftFrameUp.rawValue:
            return move((0, 1))
        case SemanticActionType.shiftFrameDown.rawValue:
            return move((0, -1))
        case SemanticActionType.moveSubjectLeft.rawValue,
             SemanticActionType.moveObjectLeft.rawValue:
            return move((-1, 0))
        case SemanticActionType.moveSubjectRight.rawValue,
             SemanticActionType.moveObjectRight.rawValue:
            return move((1, 0))
        case SemanticActionType.lowerCamera.rawValue:
            return move((0, -1))
        case SemanticActionType.raiseCamera.rawValue:
            return move((0, 1))
        case SemanticActionType.stepCloser.rawValue,
             SemanticActionType.moveObjectForward.rawValue:
            return scalar(.scaleDistance, .area, .increase)
        case SemanticActionType.stepBack.rawValue,
             SemanticActionType.moveObjectBack.rawValue:
            return scalar(.scaleDistance, .area, .decrease)
        case SemanticActionType.moveSubjectAwayFromBackground.rawValue:
            return scalar(.scaleDistance, .depth, .increase)
        case SemanticActionType.levelHorizon.rawValue:
            return scalar(.horizonRotation, .horizon, .decrease)
        // C04.1 (runbook 2026-09-13): changeCameraAngle is prescribed for
        // background/merger cleanup, but an absolute horizon rotation is not
        // evidence that the obstruction was fixed — a lateral move with a level
        // horizon changes nothing here, while a tilt changes this metric
        // without cleaning the background. No qualified contour/occlusion
        // signal exists yet, so the action resolves to
        // `.uncertain(reason: "unsupported_action")` instead of a fabricated
        // improvement. Re-point this at a contour metric when C04/C05 land one.
        case SemanticActionType.rotateSubjectTowardLight.rawValue:
            return scalar(.lightExposure, .separation, .increase)
        case SemanticActionType.addFrontFillLight.rawValue:
            return scalar(.lightExposure, .subjectLuma, .increase)
        case SemanticActionType.addBackgroundLight.rawValue:
            return scalar(.lightExposure, .backgroundLuma, .increase)
        case SemanticActionType.removeBackgroundHotspot.rawValue:
            return scalar(.lightExposure, .hotspot, .decrease)
        case TechnicalQualityActionType.reduceExposure.rawValue:
            return scalar(.lightExposure, .exposure, .decrease)
        case TechnicalQualityActionType.increaseExposure.rawValue:
            return scalar(.lightExposure, .exposure, .increase)
        case TechnicalQualityActionType.refocusSubject.rawValue:
            return scalar(.focus, .focus, .increase)
        case TechnicalQualityActionType.stabilizeCamera.rawValue:
            return scalar(.stability, .stability, .increase)
        default:
            // Removal, simplification, waiting, and keep-current actions do
            // not have an honest movement feature in the current domain.
            return nil
        }
    }

    private static func move(_ displacement: (dx: Double, dy: Double)) -> ActionIntent {
        ActionIntent(family: .subjectDisplacement,
                     displacement: displacement,
                     metric: nil,
                     relation: nil)
    }

    private static func scalar(_ family: UserMovementActionFamily,
                               _ metric: Metric,
                               _ relation: Relation) -> ActionIntent {
        ActionIntent(family: family,
                     displacement: nil,
                     metric: metric,
                     relation: relation)
    }

    private static func evidenceFailure(previous: UserMovementFrame,
                                        current: UserMovementFrame,
                                        family: UserMovementActionFamily,
                                        asOf: Date?) -> String? {
        let observedAt = asOf ?? current.evidence?.evaluatedAt
        return evidenceFailure(
            previous: previous,
            current: current,
            family: family,
            previousAsOf: observedAt,
            currentAsOf: observedAt
        )
    }

    private static func evidenceFailureAtOwnEvaluationTimes(
        previous: UserMovementFrame,
        current: UserMovementFrame,
        family: UserMovementActionFamily
    ) -> String? {
        evidenceFailure(
            previous: previous,
            current: current,
            family: family,
            previousAsOf: previous.evidence?.evaluatedAt,
            currentAsOf: current.evidence?.evaluatedAt
        )
    }

    private static func evidenceFailure(previous: UserMovementFrame,
                                        current: UserMovementFrame,
                                        family: UserMovementActionFamily,
                                        previousAsOf: Date?,
                                        currentAsOf: Date?) -> String? {
        guard let previousEvidence = previous.evidence,
              let currentEvidence = current.evidence else {
            return "evidence_missing"
        }
        guard !previous.frameID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !current.frameID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              previous.frameID != current.frameID else {
            return "frame_identity"
        }
        guard previousEvidence.lensGeneration != 0,
              currentEvidence.lensGeneration != 0,
              previousEvidence.lensGeneration == currentEvidence.lensGeneration else {
            return "lens_generation"
        }
        guard previousEvidence.hasValidSampleProvenanceShape,
              currentEvidence.hasValidSampleProvenanceShape else {
            return "provenance_missing"
        }
        if previousEvidence.hasKnownSampleProvenance || currentEvidence.hasKnownSampleProvenance {
            guard previousEvidence.hasKnownSampleProvenance,
                  currentEvidence.hasKnownSampleProvenance,
                  previousEvidence.sessionGeneration == currentEvidence.sessionGeneration else {
                return "session_generation"
            }
            guard CMTimeCompare(
                currentEvidence.samplePresentationTimestamp,
                previousEvidence.samplePresentationTimestamp
            ) > 0 else {
                return "sample_pts"
            }
        }
        let requiresSubjectBinding = family == .subjectDisplacement
            || family == .scaleDistance
            || family == .lightExposure
            || family == .focus
        if requiresSubjectBinding {
            guard let previousBinding = previousEvidence.subjectBinding,
                  let currentBinding = currentEvidence.subjectBinding,
                  previousBinding.frameID == previous.frameID,
                  currentBinding.frameID == current.frameID,
                  // Both values are the shared pipeline capture generation;
                  // they are not independent counters.
                  previousBinding.identity.generation == previousEvidence.lensGeneration,
                  currentBinding.identity.generation == currentEvidence.lensGeneration,
                  previousBinding.identity == currentBinding.identity,
                  previousBinding.source == currentBinding.source,
                  previousBinding.coachingRegion == previous.subjectRegion,
                  currentBinding.coachingRegion == current.subjectRegion,
                  previousBinding.confidence.isFinite,
                  currentBinding.confidence.isFinite,
                  previousBinding.confidence >= minimumEvidenceConfidence,
                  currentBinding.confidence >= minimumEvidenceConfidence else {
                return "subject_identity"
            }
        }
        guard previousEvidence.isCalibrated, currentEvidence.isCalibrated else {
            return "uncalibrated"
        }
        guard previousEvidence.orientation == currentEvidence.orientation else {
            return "orientation_changed"
        }
        if let previousVersion = previousEvidence.calibrationVersion,
           let currentVersion = currentEvidence.calibrationVersion,
           previousVersion != currentVersion {
            return "calibration_changed"
        }
        guard previousEvidence.capturedAt.timeIntervalSinceReferenceDate.isFinite,
              currentEvidence.capturedAt.timeIntervalSinceReferenceDate.isFinite,
              (previousEvidence.hasKnownSampleProvenance
                  || previousEvidence.capturedAt <= currentEvidence.capturedAt) else {
            return "evidence_time"
        }

        guard let previousObservedAt = previousAsOf,
              let currentObservedAt = currentAsOf,
              previousObservedAt.timeIntervalSinceReferenceDate.isFinite,
              currentObservedAt.timeIntervalSinceReferenceDate.isFinite,
              previousEvidence.capturedAt <= previousObservedAt,
              currentEvidence.capturedAt <= currentObservedAt,
              currentEvidence.evaluatedAt.timeIntervalSinceReferenceDate.isFinite,
              previousEvidence.evaluatedAt.timeIntervalSinceReferenceDate.isFinite,
              previousEvidence.capturedAt <= previousEvidence.evaluatedAt,
              currentEvidence.capturedAt <= currentEvidence.evaluatedAt,
              let previousMeasuredAt = previousEvidence.featureMeasuredAt[family],
              let currentMeasuredAt = currentEvidence.featureMeasuredAt[family],
              previousEvidence.sourceAvailability[family] == true,
              currentEvidence.sourceAvailability[family] == true else {
            return "feature_missing"
        }
        guard previousEvidence.featureConfidence[family].map({ $0.isFinite && $0 >= minimumEvidenceConfidence }) == true,
              currentEvidence.featureConfidence[family].map({ $0.isFinite && $0 >= minimumEvidenceConfidence }) == true else {
            return "feature_confidence"
        }
        guard previousMeasuredAt.timeIntervalSinceReferenceDate.isFinite,
              currentMeasuredAt.timeIntervalSinceReferenceDate.isFinite,
              previousMeasuredAt <= previousObservedAt,
              currentMeasuredAt <= currentObservedAt else {
            return "stale_evidence"
        }
        let previousFreshnessWindow = freshnessWindow(for: family, evidence: previousEvidence)
        let currentFreshnessWindow = freshnessWindow(for: family, evidence: currentEvidence)
        let previousBindingFreshnessWindow = subjectBindingFreshnessWindow(for: previousEvidence)
        let currentBindingFreshnessWindow = subjectBindingFreshnessWindow(for: currentEvidence)
        if let previousFreshnessWindow,
           let currentFreshnessWindow {
            guard previousObservedAt.timeIntervalSince(previousMeasuredAt) <= previousFreshnessWindow,
                  currentObservedAt.timeIntervalSince(currentMeasuredAt) <= currentFreshnessWindow else {
                return "stale_evidence"
            }
        }
        if requiresSubjectBinding {
            guard let previousBinding = previousEvidence.subjectBinding,
                  let currentBinding = currentEvidence.subjectBinding,
                  previousBinding.measuredAt.timeIntervalSinceReferenceDate.isFinite,
                  currentBinding.measuredAt.timeIntervalSinceReferenceDate.isFinite,
                  previousBinding.measuredAt <= previousObservedAt,
                  currentBinding.measuredAt <= currentObservedAt else {
                return "stale_evidence"
            }
            if let previousBindingFreshnessWindow,
               let currentBindingFreshnessWindow {
                guard previousObservedAt.timeIntervalSince(previousBinding.measuredAt) <= previousBindingFreshnessWindow,
                      currentObservedAt.timeIntervalSince(currentBinding.measuredAt) <= currentBindingFreshnessWindow else {
                    return "stale_evidence"
                }
            }
        }
        if family == .subjectDisplacement || family == .scaleDistance {
            guard let previousBinding = previousEvidence.subjectBinding,
                  let currentBinding = currentEvidence.subjectBinding,
                  previousBinding.measuredAt == previousMeasuredAt,
                  currentBinding.measuredAt == currentMeasuredAt else {
                return "subject_identity"
            }
        }
        return nil
    }

    private static func freshnessWindow(for family: UserMovementActionFamily,
                                        evidence: UserMovementEvidence) -> TimeInterval? {
        switch family {
        case .subjectDisplacement, .scaleDistance:
            guard let source = evidence.subjectBinding?.source else { return nil }
            return FeatureSourceFreshnessWindows.window(for: source)
        case .horizonRotation:
            return FeatureSourceFreshnessWindows.window(for: .horizon)
        case .lightExposure:
            return FeatureSourceFreshnessWindows.window(for: .lighting)
        case .stability:
            // Motion is frame-global and has no independent source window.
            // Bound its capture age by the narrowest declared source window.
            return FeatureSourceID.allCases
                .map(FeatureSourceFreshnessWindows.window(for:))
                .min()
        case .focus:
            return nil
        }
    }

    private static func subjectBindingFreshnessWindow(for evidence: UserMovementEvidence) -> TimeInterval? {
        evidence.subjectBinding.map { FeatureSourceFreshnessWindows.window(for: $0.source) }
    }

    private static func evaluate(previous: UserMovementFrame,
                                 current: UserMovementFrame,
                                 intent: ActionIntent,
                                 targetRefs: [String] = []) -> UserMovementComparison {
        // Only a single entity displacement currently reads its declared
        // target's geometry. Scalar metrics still belong to the primary subject,
        // and cannot establish a different object's area/light/focus change.
        if !targetRefs.isEmpty && (targetRefs.count != 1 || intent.displacement == nil) {
            return .uncertain(reason: "unsupported_action", family: intent.family,
                              metric: metricID(for: intent.metric, displacement: intent.displacement))
        }
        if intent.family != .stability, !current.motionIsStill {
            return .uncertain(
                reason: "camera_motion",
                family: intent.family,
                metric: metricID(for: intent.metric, displacement: intent.displacement)
            )
        }

        if let desired = intent.displacement {
            // C04.2: a commanded target is measured, not the primary subject.
            // A frame that does not observe the commanded entity cannot prove
            // the action; it is `target_missing`, never a zero-delta noOp.
            let before: NormalizedRect?
            let after: NormalizedRect?
            if let targetRef = targetRefs.first {
                guard let beforeObservation = previous.entityObservation(for: targetRef),
                      beforeObservation.hasComparableGeometry,
                      let beforeRegion = beforeObservation.region,
                      let afterObservation = current.entityObservation(for: targetRef),
                      afterObservation.hasComparableGeometry,
                      let afterRegion = afterObservation.region else {
                    return .uncertain(
                        reason: "target_missing",
                        family: intent.family,
                        metric: .placement
                    )
                }
                before = beforeRegion
                after = afterRegion
            } else {
                before = previous.subjectRegion
                after = current.subjectRegion
            }
            guard let before,
                  let after,
                  !before.isDegenerate,
                  !after.isDegenerate else {
                return .uncertain(
                    reason: "subject_missing",
                    family: intent.family,
                    metric: .placement
                )
            }
            let p = center(of: after)
            let q = center(of: before)
            let dx = p.x - q.x
            let dy = p.y - q.y
            let desiredLength = (desired.dx * desired.dx + desired.dy * desired.dy).squareRoot()
            guard desiredLength.isFinite, desiredLength > 0 else {
                return .uncertain(reason: "unsupported_action", family: intent.family, metric: .placement)
            }
            let projection = (dx * desired.dx + dy * desired.dy) / desiredLength
            let verdict = directionalVerdict(
                dx: dx,
                dy: dy,
                desired: desired,
                deadband: movementDeadband
            )
            return UserMovementComparison(
                family: intent.family,
                metric: .placement,
                beforeValue: 0,
                afterValue: projection,
                delta: projection,
                directedDelta: projection,
                deadband: movementDeadband,
                verdict: verdict
            )
        }

        guard let metric = intent.metric,
              let before = value(for: metric, frame: previous),
              let after = value(for: metric, frame: current),
              let relation = intent.relation else {
            return .uncertain(
                reason: missingReason(for: intent.metric),
                family: intent.family,
                metric: metricID(for: intent.metric, displacement: intent.displacement)
            )
        }
        let classifierDelta: Double
        let deadband: Double
        if metric == .horizon {
            switch relation {
            case .absoluteChange:
                classifierDelta = abs(after - before)
            case .increase, .decrease:
                classifierDelta = abs(after) - abs(before)
            }
            deadband = rotationDeadbandDegrees
        } else if metric == .area {
            classifierDelta = after - before
            deadband = scaleDeadband
        } else {
            classifierDelta = after - before
            deadband = scalarDeadband
        }
        let rawDelta = after - before
        let directedDelta: Double
        switch relation {
        case .increase:
            directedDelta = rawDelta
        case .decrease:
            directedDelta = metric == .horizon
                ? abs(before) - abs(after)
                : -rawDelta
        case .absoluteChange:
            directedDelta = abs(rawDelta)
        }
        return UserMovementComparison(
            family: intent.family,
            metric: metricID(for: metric, displacement: nil),
            beforeValue: before,
            afterValue: after,
            delta: rawDelta,
            directedDelta: directedDelta,
            deadband: deadband,
            verdict: scalarVerdict(
                delta: classifierDelta,
                relation: relation,
                deadband: deadband
            )
        )
    }

    private static func metricID(
        for metric: Metric?,
        displacement: (dx: Double, dy: Double)?
    ) -> ActionVerificationMetric? {
        if displacement != nil { return .placement }
        switch metric {
        case .area: return .scale
        case .depth: return .depth
        case .horizon: return .horizon
        case .exposure: return .exposure
        case .subjectLuma: return .subjectLuma
        case .backgroundLuma: return .backgroundLuma
        case .separation: return .separation
        case .hotspot: return .hotspot
        case .focus: return .focus
        case .stability: return .stability
        case nil: return nil
        }
    }

    private static func missingReason(for metric: Metric?) -> String {
        switch metric {
        case .area, .depth: return "scale_missing"
        case .horizon: return "horizon_missing"
        case .exposure, .subjectLuma, .backgroundLuma, .separation, .hotspot:
            return "light_missing"
        case .focus: return "focus_missing"
        case .stability: return "stability_missing"
        case nil: return "feature_missing"
        }
    }

    private static func value(for metric: Metric, frame: UserMovementFrame) -> Double? {
        switch metric {
        case .area:
            return frame.metrics.subjectAreaRatio
                ?? frame.subjectRegion.map { $0.width * $0.height }
        case .depth:
            return frame.metrics.subjectBackgroundDepth
        case .horizon:
            return frame.metrics.horizonAngleDegrees
        case .exposure:
            return frame.metrics.exposureBiasHint
        case .subjectLuma:
            return frame.metrics.subjectMeanLuma
        case .backgroundLuma:
            return frame.metrics.backgroundMeanLuma
        case .separation:
            return frame.metrics.subjectToBackgroundDelta
        case .hotspot:
            return frame.metrics.backgroundHotspotRatio
        case .focus:
            if let readability = frame.metrics.focusReadability {
                return readability
            }
            return frame.metrics.focusIsDefocused.map { $0 ? 0 : 1 }
        case .stability:
            if let score = frame.metrics.stabilityScore { return score }
            if let shake = frame.metrics.shakeLevel { return 1.0 - shake }
            return frame.motionIsStill ? 1.0 : 0.0
        }
    }

    private static func directionalVerdict(dx: Double,
                                           dy: Double,
                                           desired: (dx: Double, dy: Double),
                                           deadband: Double) -> UserMovementVerdict {
        let magnitude = (dx * dx + dy * dy).squareRoot()
        guard magnitude >= deadband else { return .noOp }
        let length = (desired.dx * desired.dx + desired.dy * desired.dy).squareRoot()
        guard length > 0 else { return .noOp }
        let projection = (dx * desired.dx + dy * desired.dy) / length
        if projection >= deadband { return .relevant }
        if projection <= -deadband { return .opposite }
        return .noOp
    }

    private static func scalarVerdict(delta: Double,
                                      relation: Relation,
                                      deadband: Double) -> UserMovementVerdict {
        guard delta.isFinite else { return .uncertain(reason: "feature_invalid") }
        let signedDelta: Double
        switch relation {
        case .increase: signedDelta = delta
        case .decrease: signedDelta = -delta
        case .absoluteChange: signedDelta = abs(delta)
        }
        if signedDelta >= deadband { return .relevant }
        if signedDelta <= -deadband { return .opposite }
        return .noOp
    }

    private static func center(of region: NormalizedRect,
                               transform: CameraDisplayTransform? = nil) -> (x: Double, y: Double) {
        let point = (x: region.x + region.width / 2,
                     y: region.y + region.height / 2)
        return transform?.apply(x: point.x, y: point.y) ?? point
    }
}

/// Existing frame-streak state. It counts accepted observations, not seconds;
/// episode orchestration and final verification remain outside this owner.
struct UserMovementTracker {
    private(set) var previousFrame: UserMovementFrame?
    private(set) var consecutiveRelevant = 0
    private(set) var totalObservations = 0
    private(set) var lastVerdict: UserMovementVerdict?

    let desiredDisplacement: (dx: Double, dy: Double)
    let requiredRelevantFrames: Int
    private let actionID: String?
    /// C04.2: the commanded entity refs for a target-scoped action. Empty for
    /// frame-global / legacy trackers.
    let targetRefs: [String]

    init(desiredDisplacement: (dx: Double, dy: Double), requiredRelevantFrames: Int = 2) {
        self.desiredDisplacement = desiredDisplacement
        self.requiredRelevantFrames = max(1, requiredRelevantFrames)
        self.actionID = nil
        self.targetRefs = []
    }

    init(action: SemanticActionType, requiredRelevantFrames: Int = 2) {
        self.init(actionID: action.rawValue, requiredRelevantFrames: requiredRelevantFrames)
    }

    init(action: TechnicalQualityActionType, requiredRelevantFrames: Int = 2) {
        self.init(actionID: action.rawValue, requiredRelevantFrames: requiredRelevantFrames)
    }

    init(actionID: String, targetRefs: [String] = [], requiredRelevantFrames: Int = 2) {
        self.desiredDisplacement = (0, 0)
        self.requiredRelevantFrames = max(1, requiredRelevantFrames)
        self.actionID = actionID
        self.targetRefs = targetRefs
    }

    @discardableResult
    mutating func observe(_ frame: UserMovementFrame,
                          asOf: Date? = nil) -> UserMovementVerdict {
        totalObservations += 1
        let verdict: UserMovementVerdict
        if let previous = previousFrame {
            if let actionID {
                verdict = UserMovementObserver.observe(previous: previous,
                                                       current: frame,
                                                       actionID: actionID,
                                                       targetRefs: targetRefs,
                                                       asOf: asOf)
            } else {
                verdict = UserMovementObserver.observe(previous: previous,
                                                       current: frame,
                                                       desiredDisplacement: desiredDisplacement)
            }
        } else {
            verdict = .uncertain(reason: "first_frame")
        }
        previousFrame = frame

        switch verdict {
        case .relevant:
            consecutiveRelevant += 1
        case .noOp, .opposite:
            consecutiveRelevant = 0
        case .uncertain:
            consecutiveRelevant = 0
        }
        lastVerdict = verdict
        return verdict
    }

    var movementGoalReached: Bool {
        consecutiveRelevant >= requiredRelevantFrames
    }

    mutating func reset() {
        previousFrame = nil
        consecutiveRelevant = 0
        totalObservations = 0
        lastVerdict = nil
    }
}
