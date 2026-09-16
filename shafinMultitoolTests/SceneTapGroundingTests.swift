//
//  SceneTapGroundingTests.swift
//  shafinMultitool
//
//  CC-O02 wiring contract tests: the tap-naming decision core
//  (SceneTapEvidence.namesTrackedInstance) and the inverse preview-layer
//  point conversion (CameraPreviewRegionMapper.scenePoint). The production
//  gesture itself requires a physical camera and stays a physical gate.
//

import XCTest
import CoreMedia
import CoreVideo
@testable import shafinMultitool

final class SceneTapGroundingTests: XCTestCase {

    private let time = Date(timeIntervalSince1970: 1_800_000_000)

    private func object(_ x: Double, id: String = "object") -> SubjectCandidate {
        SubjectCandidate(
            id: id, kind: .object, label: "lamp",
            region: NormalizedRect(x: x, y: 0.3, width: 0.15, height: 0.2),
            confidence: 0.95
        )
    }

    private func frame(_ tracker: SubjectTracker, id: String = "f1",
                       generation: UInt64 = 7, sequence: UInt64 = 1,
                       candidates: [SubjectCandidate]? = nil,
                       capturedAt: Date? = nil) throws -> ObjectTrackFrame {
        try XCTUnwrap(tracker.acceptObjectFrame(
            candidates: candidates ?? [object(0.1, id: "left"), object(0.7, id: "right")],
            frameID: id, generation: generation, sampleSequence: sequence,
            capturedAt: capturedAt ?? time
        ))
    }

    func testTapBindsExactCurrentObjectAndRejectsSameLabelSibling() throws {
        let current = try frame(SubjectTracker())
        let evidence = try XCTUnwrap(SceneTapEvidence(sceneX: 0.15, sceneY: 0.4, frame: current, now: time))
        let left = try XCTUnwrap(current.currentObjects.first { $0.region?.x == 0.1 })
        let right = try XCTUnwrap(current.currentObjects.first { $0.region?.x == 0.7 })
        XCTAssertTrue(evidence.matches(targetTrackID: left.identity.trackID, in: current, now: time))
        XCTAssertFalse(evidence.matches(targetTrackID: right.identity.trackID, in: current, now: time))
        XCTAssertEqual(evidence.binding.boundAtFrameID, "f1")
    }

    func testTapIsNeverReinterpretedOnNextFrameAtSameCoordinates() throws {
        let tracker = SubjectTracker()
        let first = try frame(tracker)
        let tap = try XCTUnwrap(SceneTapEvidence(sceneX: 0.15, sceneY: 0.4, frame: first, now: time))
        let next = try frame(tracker, id: "f2", sequence: 2)
        XCTAssertFalse(tap.matches(targetTrackID: tap.binding.trackID, in: next, now: time))
        XCTAssertEqual(tap.binding.boundAtFrameID, "f1", "the frozen tap cannot move to f2")
    }

    func testEmptyFrameImmediatelyInvalidatesHitAndOldTap() throws {
        let tracker = SubjectTracker()
        let first = try frame(tracker)
        let tap = try XCTUnwrap(SceneTapEvidence(sceneX: 0.15, sceneY: 0.4, frame: first, now: time))
        let empty = try frame(tracker, id: "f2", sequence: 2, candidates: [])
        XCTAssertTrue(empty.currentObjects.isEmpty)
        XCTAssertNil(SceneTapEvidence(sceneX: 0.15, sceneY: 0.4, frame: empty, now: time))
        XCTAssertFalse(tap.matches(targetTrackID: tap.binding.trackID, in: empty, now: time))
    }

    func testFreshTapCannotRefreshAnOldPresentedFrame() throws {
        let old = try frame(SubjectTracker(), capturedAt: time.addingTimeInterval(-1))
        XCTAssertNil(SceneTapEvidence(sceneX: 0.15, sceneY: 0.4, frame: old, now: time))
    }

    func testGenerationChangeAndFutureTimeRejectFrozenSelection() throws {
        let tracker = SubjectTracker()
        let first = try frame(tracker)
        let tap = try XCTUnwrap(SceneTapEvidence(sceneX: 0.15, sceneY: 0.4, frame: first, now: time))
        let replacement = try frame(tracker, id: "f2", generation: 8, sequence: 2)
        XCTAssertFalse(tap.matches(targetTrackID: tap.binding.trackID, in: replacement, now: time))
        XCTAssertFalse(tap.matches(targetTrackID: tap.binding.trackID, in: first, now: time.addingTimeInterval(-0.1)))
        XCTAssertFalse(tap.matches(targetTrackID: tap.binding.trackID, in: first, now: time.addingTimeInterval(0.3)))
    }

    func testEmptyAndInvalidCoordinatesProduceNoTarget() throws {
        let current = try frame(SubjectTracker())
        XCTAssertNil(SceneTapEvidence(sceneX: 0.5, sceneY: 0.5, frame: current, now: time))
        XCTAssertNil(SceneTapEvidence(sceneX: .nan, sceneY: 0.4, frame: current, now: time))
        XCTAssertNil(SceneTapEvidence(sceneX: -0.01, sceneY: 0.4, frame: current, now: time))
        XCTAssertNotNil(SceneTapEvidence(sceneX: 0.08, sceneY: 0.4, frame: current, now: time))
    }

    func testTwoTouchableObjectsAreAmbiguousEvenWithNearestCenter() throws {
        let current = try frame(SubjectTracker(), candidates: [object(0.1), object(0.29)])
        XCTAssertEqual(current.currentObjects.count, 2)
        // Both inflated boxes cover x=0.27. A nearest-center guess cannot name one.
        XCTAssertNil(SceneTapEvidence(sceneX: 0.27, sceneY: 0.4, frame: current, now: time))
    }

    // MARK: - CameraPreviewRegionMapper.scenePoint

    func testScenePointUndoesTheMetadataYFlip() {
        // Identity converter: the layer rect equals the metadata rect, so the
        // only remaining step is the upper-left metadata y-flip.
        let point = CameraPreviewRegionMapper.scenePoint(
            forLayerPoint: CGPoint(x: 100, y: 200),
            using: { $0 }
        )
        XCTAssertEqual(point?.x ?? -1, 100, accuracy: 0.001)
        XCTAssertEqual(point?.y ?? -1, 1.0 - 200, accuracy: 0.001)
    }

    func testScenePointUsesTheConvertedRectCenter() {
        // A converter that maps every probe to a fixed metadata rect: the
        // scene point must be that rect's center, y-flipped.
        let point = CameraPreviewRegionMapper.scenePoint(
            forLayerPoint: CGPoint(x: 42, y: 17),
            using: { _ in CGRect(x: 0.2, y: 0.3, width: 0.1, height: 0.2) }
        )
        XCTAssertEqual(point?.x ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(point?.y ?? -1, 1.0 - 0.4, accuracy: 0.0001)
    }

    func testScenePointRejectsDegenerateConversion() {
        let point = CameraPreviewRegionMapper.scenePoint(
            forLayerPoint: CGPoint(x: 10, y: 10),
            using: { _ in .null }
        )
        XCTAssertNil(point)
    }

    func testScenePointRoundTripsThroughTheRegionMapping() {
        // A scene region mapped to metadata with the production y-flip, then
        // its center tapped and inverted, must return the region center.
        let region = NormalizedRect(x: 0.3, y: 0.4, width: 0.2, height: 0.2)
        let metadata = CameraPreviewRegionMapper.metadataOutputRect(for: region)
        XCTAssertNotNil(metadata)
        // Pretend the layer coordinates equal metadata coordinates.
        let point = CameraPreviewRegionMapper.scenePoint(
            forLayerPoint: CGPoint(x: metadata!.midX, y: metadata!.midY),
            using: { $0 }
        )
        XCTAssertEqual(point?.x ?? -1, region.x + region.width / 2, accuracy: 0.0001)
        XCTAssertEqual(point?.y ?? -1, region.y + region.height / 2, accuracy: 0.0001)
    }
}


/// Integration through the production capture-store + object observation seam.
/// No detector, planner probability, physical camera or paid provider is needed.
@MainActor
final class AnalysisPipelineObjectBindingTests: XCTestCase {
    private func evidence(id: String, pts: Int64, generation: UInt64 = 7,
                          capturedAt: Date, objects: Bool,
                          moving: Bool = false, trackingMetadata: Bool = true) throws -> LatestFrameEvidenceStore.Snapshot {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(
            kCFAllocatorDefault, 8, 8, kCVPixelFormatType_32BGRA, nil, &buffer
        ), kCVReturnSuccess)
        let timestamp = CMTime(value: pts, timescale: 30)
        let provenance = FeatureSampleProvenance(
            frameID: id, captureGeneration: generation, orientation: .up,
            samplePresentationTimestamp: timestamp, sessionGeneration: 1
        )
        let sourceDate = capturedAt.addingTimeInterval(-1.0 / 30.0)
        let rawBox = CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.3)
        let current = VisionObjectFrame(frameID: id, captureGeneration: generation, sessionGeneration: 1,
            lifecycleGeneration: 0, orientation: .up, samplePTS: timestamp, capturedAt: capturedAt)
        let source = VisionObjectFrame(frameID: id + "-seed", captureGeneration: generation, sessionGeneration: 1,
            lifecycleGeneration: 0, orientation: .up, samplePTS: CMTime(value: pts - 1, timescale: 30), capturedAt: sourceDate)
        let tracking = objects && trackingMetadata ? FeatureSnapshotDetrTracking(
            source: source, current: current, geometryMeasuredAt: capturedAt, qualities: [0.95],
            geometries: [try XCTUnwrap(VisionObjectGeometry(seedSlot: 0, rawBoundingBox: rawBox))]) : nil
        var features = CoachingFeatures()
        features.motion.state = moving ? .moving : .still
        let state = PipelineFeatureSnapshotAdapterState(
            features: features, debugData: DebugData(), vision: nil,
            horizonMeasuredAt: nil, horizon: nil, lightingMeasuredAt: nil, lighting: nil,
            detr: FeatureSample(
                value: FeatureSnapshotDetrPayload(detections: objects ? [
                    FeatureSnapshotDetectedObject(
                        boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.3),
                        label: "lamp", confidence: 0.95
                    )
                ] : [], tracking: tracking),
                measuredAt: tracking == nil ? capturedAt : sourceDate, baseConfidence: objects ? 0.95 : 0,
                provenance: provenance
            ),
            aestheticMeasuredAt: nil, aesthetic: nil
        )
        return try XCTUnwrap(LatestFrameEvidenceStore.Snapshot(
            pixelBuffer: XCTUnwrap(buffer), orientation: .up,
            sourceFrameId: id, capturedAt: capturedAt, isStable: !moving,
            lensID: "test-lens", adapterState: state, lensGeneration: generation,
            samplePresentationTimestamp: timestamp, sessionGeneration: 1
        ))
    }

    func testLegacyCurrentBoxesWithoutTrackingGeometryCannotClaimUniqueTap() throws {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let now = Date()
        XCTAssertTrue(pipeline.testingAcceptLiveObjectFrame(
            try evidence(id: "legacy", pts: 1, capturedAt: now, objects: true, trackingMetadata: false)))
        let frame = try XCTUnwrap(pipeline.testingPresentedObjectFrame)
        XCTAssertFalse(frame.currentObjects.isEmpty)
        XCTAssertNotNil(SceneTapEvidence(sceneX: 0.2, sceneY: 0.3, frame: frame, now: now))
        pipeline.handleSceneTap(normalizedX: 0.2, normalizedY: 0.3, now: now)
        XCTAssertNil(pipeline.testingSceneTapEvidence)
    }

    func testEmptyMovingFrameAgesObservationAndClearsTapWithoutAdvice() throws {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let now = Date()
        XCTAssertTrue(pipeline.testingAcceptLiveObjectFrame(
            try evidence(id: "f1", pts: 1, capturedAt: now, objects: true)
        ))
        pipeline.handleSceneTap(normalizedX: 0.2, normalizedY: 0.3, now: now)
        XCTAssertNotNil(pipeline.testingSceneTapEvidence)
        XCTAssertTrue(pipeline.testingAcceptLiveObjectFrame(
            try evidence(id: "f2", pts: 2, capturedAt: now, objects: false, moving: true)
        ))
        XCTAssertEqual(pipeline.testingSubjectIdentityRegistry?.identities.first?.consecutiveMisses, 1)
        XCTAssertTrue(try XCTUnwrap(pipeline.testingPresentedObjectFrame).currentObjects.isEmpty)
        XCTAssertNil(pipeline.testingSceneTapEvidence)
        pipeline.handleSceneTap(normalizedX: 0.2, normalizedY: 0.3, now: now)
        XCTAssertNil(pipeline.testingSceneTapEvidence)
        XCTAssertNil(pipeline.currentLiveHint, "empty observations do not manufacture good-frame/advice")
    }

    func testDuplicateAndOutOfOrderCaptureDoNotAgeTwiceOrReviveTarget() throws {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let now = Date()
        let first = try evidence(id: "f1", pts: 1, capturedAt: now, objects: true)
        let empty = try evidence(id: "f2", pts: 2, capturedAt: now, objects: false)
        XCTAssertTrue(pipeline.testingAcceptLiveObjectFrame(first))
        XCTAssertTrue(pipeline.testingAcceptLiveObjectFrame(empty))
        let acceptedSequence = pipeline.testingPresentedObjectFrame?.sampleSequence
        XCTAssertFalse(pipeline.testingAcceptLiveObjectFrame(empty))
        XCTAssertFalse(pipeline.testingAcceptLiveObjectFrame(first))
        XCTAssertEqual(pipeline.testingPresentedObjectFrame?.sampleSequence, acceptedSequence)
        XCTAssertEqual(pipeline.testingSubjectIdentityRegistry?.identities.first?.consecutiveMisses, 1)
        XCTAssertEqual(pipeline.testingSubjectIdentityRegistry?.lastObservedFrameID, "f2")
        XCTAssertTrue(try XCTUnwrap(pipeline.testingPresentedObjectFrame).currentObjects.isEmpty)
    }

    func testCaptureGenerationAndLifecycleCancellationRetireTapContext() throws {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let now = Date()
        XCTAssertTrue(pipeline.testingAcceptLiveObjectFrame(
            try evidence(id: "f1", pts: 1, capturedAt: now, objects: true)
        ))
        pipeline.handleSceneTap(normalizedX: 0.2, normalizedY: 0.3, now: now)
        let first = try XCTUnwrap(pipeline.testingSceneTapEvidence)
        XCTAssertTrue(pipeline.testingAcceptLiveObjectFrame(
            try evidence(id: "f2", pts: 1, generation: 8, capturedAt: now, objects: true)
        ))
        XCTAssertNil(pipeline.testingSceneTapEvidence)
        let replacement = try XCTUnwrap(pipeline.testingPresentedObjectFrame)
        XCTAssertFalse(first.matches(targetTrackID: first.binding.trackID, in: replacement, now: now))
        pipeline.handleSceneTap(normalizedX: 0.2, normalizedY: 0.3, now: now)
        XCTAssertNotNil(pipeline.testingSceneTapEvidence)
        pipeline.cancelCoachingEpisode(reason: .lensChange)
        XCTAssertNil(pipeline.testingSceneTapEvidence)
        XCTAssertNil(pipeline.testingPresentedObjectFrame)
    }
}
