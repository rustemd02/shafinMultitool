import CoreGraphics
import CoreMedia
import CoreVideo
import Dispatch
import XCTest
@testable import shafinMultitool

final class LatestFrameEvidenceStoreTests: XCTestCase {

    func testConcurrentPublishAndSnapshotNeverTearsTheEnvelope() {
        let store = LatestFrameEvidenceStore()
        let firstPixelBuffer = makePixelBuffer()
        let secondPixelBuffer = makePixelBuffer()
        let firstPixelBufferId = ObjectIdentifier(firstPixelBuffer as AnyObject)
        let secondPixelBufferId = ObjectIdentifier(secondPixelBuffer as AnyObject)
        let firstCapturedAt = Date(timeIntervalSince1970: 1)
        let secondCapturedAt = Date(timeIntervalSince1970: 2)
        let queue = DispatchQueue(label: "LatestFrameEvidenceStoreTests.concurrent", attributes: .concurrent)
        let group = DispatchGroup()
        let failureLock = NSLock()
        var failures = 0

        for writer in 0..<4 {
            group.enter()
            queue.async {
                defer { group.leave() }
                for iteration in 0..<2_000 {
                    let isFirst = (writer + iteration).isMultiple(of: 2)
                    _ = store.publish(
                        pixelBuffer: isFirst ? firstPixelBuffer : secondPixelBuffer,
                        orientation: isFirst ? .up : .down,
                        sourceFrameId: isFirst ? "frame-a" : "frame-b",
                        capturedAt: isFirst ? firstCapturedAt : secondCapturedAt,
                        isStable: isFirst
                    )
                }
            }
        }

        for _ in 0..<4 {
            group.enter()
            queue.async {
                defer { group.leave() }
                for _ in 0..<10_000 {
                    guard let snapshot = store.snapshot() else { continue }
                    let isFirst = snapshot.sourceFrameId == "frame-a"
                    let isValid = snapshot.sourceFrameId == (isFirst ? "frame-a" : "frame-b")
                        && snapshot.orientation == (isFirst ? .up : .down)
                        && snapshot.capturedAt == (isFirst ? firstCapturedAt : secondCapturedAt)
                        && snapshot.isStable == isFirst
                        && ObjectIdentifier(snapshot.pixelBuffer as AnyObject) == (isFirst ? firstPixelBufferId : secondPixelBufferId)
                    if !isValid {
                        failureLock.lock()
                        failures += 1
                        failureLock.unlock()
                    }
                }
            }
        }

        group.wait()
        XCTAssertEqual(failures, 0)
    }

    func testClearReturnsNilAndReplacementIsVisible() {
        let store = LatestFrameEvidenceStore()
        let firstPixelBuffer = makePixelBuffer()
        let secondPixelBuffer = makePixelBuffer()

        XCTAssertTrue(store.publish(
            pixelBuffer: firstPixelBuffer,
            orientation: .left,
            sourceFrameId: " first-frame ",
            capturedAt: Date(timeIntervalSince1970: 10),
            isStable: true
        ))
        XCTAssertEqual(store.snapshot()?.sourceFrameId, "first-frame")

        store.clear()
        XCTAssertNil(store.snapshot())

        XCTAssertFalse(store.publish(
            pixelBuffer: secondPixelBuffer,
            orientation: .right,
            sourceFrameId: "   ",
            capturedAt: Date(timeIntervalSince1970: 20),
            isStable: false
        ))
        XCTAssertNil(store.snapshot())

        XCTAssertTrue(store.publish(
            pixelBuffer: secondPixelBuffer,
            orientation: .right,
            sourceFrameId: "second-frame",
            capturedAt: Date(timeIntervalSince1970: 20),
            isStable: false
        ))
        let replacement = store.snapshot()
        XCTAssertEqual(replacement?.sourceFrameId, "second-frame")
        XCTAssertEqual(replacement?.orientation, .right)
        XCTAssertEqual(replacement?.capturedAt, Date(timeIntervalSince1970: 20))
        XCTAssertFalse(replacement?.isStable ?? true)
    }

    func testAcceptedSnapshotCopiesPixelsAndKeepsTheAnalysisBufferImmutable() {
        let store = LatestFrameEvidenceStore()
        let source = makePixelBuffer(width: 4, height: 2)
        writeFirstPixel([11, 22, 33, 255], to: source)

        XCTAssertTrue(store.publish(
            pixelBuffer: source,
            orientation: .up,
            sourceFrameId: "accepted-frame",
            capturedAt: Date(timeIntervalSince1970: 30),
            isStable: true
        ))

        let accepted = store.acceptCurrentSnapshot()
        XCTAssertNotNil(accepted)
        XCTAssertNotEqual(
            ObjectIdentifier(accepted!.evidence.pixelBuffer as AnyObject),
            ObjectIdentifier(source as AnyObject),
            "the accepted evidence must not alias AVCapture's reusable buffer"
        )
        XCTAssertEqual(readFirstPixel(from: accepted!.evidence.pixelBuffer), [11, 22, 33, 255])

        writeFirstPixel([201, 202, 203, 255], to: source)
        XCTAssertEqual(
            readFirstPixel(from: accepted!.evidence.pixelBuffer),
            [11, 22, 33, 255],
            "the pipeline's accepted input must remain the same pixels rendered for review"
        )
        XCTAssertNil(accepted?.displayImage, "display rendering must not run in the synchronous acceptance path")
        let rendered = store.renderDisplayImage(for: accepted!)
        XCTAssertEqual(rendered?.displayImage?.width, 4)
        XCTAssertEqual(rendered?.displayImage?.height, 2)
        XCTAssertEqual(accepted?.snapshotID, accepted?.evidence.sourceFrameId)
    }

    func testAcceptedSnapshotRendersPortraitAndLandscapeOrientationExactlyOnce() {
        let store = LatestFrameEvidenceStore()
        let landscape = makePixelBuffer(width: 4, height: 2)
        XCTAssertTrue(store.publish(
            pixelBuffer: landscape,
            orientation: .up,
            sourceFrameId: "landscape-frame",
            capturedAt: Date(),
            isStable: true
        ))
        let acceptedLandscape = store.acceptCurrentSnapshot()
        let renderedLandscape = store.renderDisplayImage(for: acceptedLandscape!)
        XCTAssertEqual(renderedLandscape?.displayImage?.width, 4)
        XCTAssertEqual(renderedLandscape?.displayImage?.height, 2)

        let portrait = makePixelBuffer(width: 4, height: 2)
        XCTAssertTrue(store.publish(
            pixelBuffer: portrait,
            orientation: .right,
            sourceFrameId: "portrait-frame",
            capturedAt: Date(),
            isStable: true
        ))
        let acceptedPortrait = store.acceptCurrentSnapshot()
        XCTAssertEqual(acceptedPortrait?.orientation, .right)
        XCTAssertEqual(acceptedPortrait?.sourcePixelSize, CGSize(width: 4, height: 2))
        let renderedPortrait = store.renderDisplayImage(for: acceptedPortrait!)
        XCTAssertEqual(renderedPortrait?.displayImage?.width, 2)
        XCTAssertEqual(renderedPortrait?.displayImage?.height, 4)
    }

    func testAcceptedFrameKeepsPixelsAndAdapterSeedFromFrameAAfterFrameBPublishes() {
        let store = LatestFrameEvidenceStore()
        let frameA = makePixelBuffer(width: 2, height: 2)
        let frameB = makePixelBuffer(width: 2, height: 2)
        writeFirstPixel([11, 12, 13, 255], to: frameA)
        writeFirstPixel([201, 202, 203, 255], to: frameB)

        XCTAssertTrue(store.publish(
            pixelBuffer: frameA,
            orientation: .up,
            sourceFrameId: "frame-a",
            capturedAt: Date(timeIntervalSince1970: 41),
            isStable: true,
            adapterState: makeAdapterState(marker: 41)
        ))
        let acceptedA = store.acceptCurrentSnapshot()
        XCTAssertNotNil(acceptedA)

        XCTAssertTrue(store.publish(
            pixelBuffer: frameB,
            orientation: .right,
            sourceFrameId: "frame-b",
            capturedAt: Date(timeIntervalSince1970: 42),
            isStable: false,
            adapterState: makeAdapterState(marker: 42)
        ))

        XCTAssertEqual(acceptedA?.sourceFrameId, "frame-a")
        XCTAssertEqual(readFirstPixel(from: acceptedA!.pixelBuffer), [11, 12, 13, 255])
        XCTAssertEqual(acceptedA?.adapterState?.features.lensRecommendation, 41)
        XCTAssertEqual(store.snapshot()?.adapterState?.features.lensRecommendation, 42)
        XCTAssertEqual(acceptedA?.orientation, .up)
        XCTAssertTrue(acceptedA?.isStable ?? false)
    }

    func testAcceptedFrameKeepsFrameBoundLensAndPreviewGeometryAfterLensChanges() {
        let store = LatestFrameEvidenceStore()
        let geometry = CameraPreviewGeometry(
            destinationSize: CGSize(width: 390, height: 844),
            imageOrientation: .right,
            isMirrored: true
        )!

        XCTAssertTrue(store.publish(
            pixelBuffer: makePixelBuffer(width: 1920, height: 1080),
            orientation: .right,
            sourceFrameId: "lens-a-frame",
            capturedAt: Date(timeIntervalSince1970: 60),
            isStable: true,
            lensID: CameraLens.wide.rawValue,
            previewGeometry: geometry,
            lensGeneration: 8
        ))
        let acceptedA = store.acceptCurrentSnapshot()

        XCTAssertTrue(store.publish(
            pixelBuffer: makePixelBuffer(width: 1920, height: 1080),
            orientation: .right,
            sourceFrameId: "lens-b-frame",
            capturedAt: Date(timeIntervalSince1970: 61),
            isStable: true,
            lensID: CameraLens.telephoto.rawValue,
            previewGeometry: geometry,
            lensGeneration: 9
        ))

        XCTAssertEqual(acceptedA?.evidence.lensID, CameraLens.wide.rawValue)
        XCTAssertEqual(acceptedA?.evidence.previewGeometry, geometry)
        XCTAssertEqual(acceptedA?.evidence.makeEnvelope().lensID, CameraLens.wide.rawValue)
        XCTAssertEqual(acceptedA?.evidence.makeEnvelope().previewGeometry, geometry)
        XCTAssertEqual(store.snapshot()?.lensID, CameraLens.telephoto.rawValue)
    }

    func testKnownSamplePTSAndSessionGenerationRejectLateOlderEvidence() {
        let store = LatestFrameEvidenceStore()
        let currentPTS = CMTime(value: 10, timescale: 10)
        let olderPTS = CMTime(value: 9, timescale: 10)

        XCTAssertTrue(store.publish(
            pixelBuffer: makePixelBuffer(),
            orientation: .right,
            sourceFrameId: "pts-current",
            capturedAt: Date(timeIntervalSince1970: 100),
            isStable: true,
            lensGeneration: 4,
            samplePresentationTimestamp: currentPTS,
            sessionGeneration: 7
        ))

        // A delayed callback can arrive later in wall-clock time, but its
        // older sample PTS must not replace the current frame.
        XCTAssertFalse(store.publish(
            pixelBuffer: makePixelBuffer(),
            orientation: .right,
            sourceFrameId: "pts-late-old",
            capturedAt: Date(timeIntervalSince1970: 101),
            isStable: true,
            lensGeneration: 4,
            samplePresentationTimestamp: olderPTS,
            sessionGeneration: 7
        ))
        XCTAssertEqual(store.snapshot()?.sourceFrameId, "pts-current")
        XCTAssertEqual(store.snapshot()?.sessionGeneration, 7)
        XCTAssertEqual(CMTimeCompare(store.snapshot()!.samplePresentationTimestamp, currentPTS), 0)

        // A newer camera session starts a new ordering domain even when its
        // first PTS is lower; a delayed sample from the old session is then
        // rejected regardless of its callback arrival time.
        XCTAssertTrue(store.publish(
            pixelBuffer: makePixelBuffer(),
            orientation: .right,
            sourceFrameId: "new-session-first",
            capturedAt: Date(timeIntervalSince1970: 102),
            isStable: true,
            lensGeneration: 1,
            samplePresentationTimestamp: olderPTS,
            sessionGeneration: 8
        ))
        XCTAssertFalse(store.publish(
            pixelBuffer: makePixelBuffer(),
            orientation: .right,
            sourceFrameId: "old-session-late",
            capturedAt: Date(timeIntervalSince1970: 103),
            isStable: true,
            lensGeneration: 4,
            samplePresentationTimestamp: currentPTS,
            sessionGeneration: 7
        ))
        XCTAssertEqual(store.snapshot()?.sourceFrameId, "new-session-first")
        XCTAssertEqual(store.snapshot()?.sessionGeneration, 8)
    }

    func testEqualKnownPTSRejectsConflictingEvidenceWithoutMutation() {
        let store = LatestFrameEvidenceStore()
        let currentPixelBuffer = makePixelBuffer()
        let conflictingPixelBuffer = makePixelBuffer()
        let timestamp = CMTime(value: 25, timescale: 10)

        XCTAssertTrue(store.publish(
            pixelBuffer: currentPixelBuffer,
            orientation: .right,
            sourceFrameId: "equal-pts-frame",
            capturedAt: Date(timeIntervalSince1970: 125),
            isStable: true,
            lensID: CameraLens.wide.rawValue,
            lensGeneration: 3,
            samplePresentationTimestamp: timestamp,
            sessionGeneration: 9
        ))

        // Same session/capture/PTS is not enough to establish identity. A
        // different buffer must be rejected even when its callback arrives
        // later, and the accepted envelope must remain byte-source stable.
        XCTAssertFalse(store.publish(
            pixelBuffer: conflictingPixelBuffer,
            orientation: .right,
            sourceFrameId: "equal-pts-frame",
            capturedAt: Date(timeIntervalSince1970: 126),
            isStable: true,
            lensID: CameraLens.wide.rawValue,
            lensGeneration: 3,
            samplePresentationTimestamp: timestamp,
            sessionGeneration: 9
        ))

        let snapshot = store.snapshot()
        XCTAssertEqual(snapshot?.sourceFrameId, "equal-pts-frame")
        XCTAssertEqual(snapshot?.capturedAt, Date(timeIntervalSince1970: 125))
        XCTAssertEqual(snapshot?.sessionGeneration, 9)
        XCTAssertEqual(snapshot?.lensGeneration, 3)
        XCTAssertEqual(
            ObjectIdentifier(snapshot!.pixelBuffer as AnyObject),
            ObjectIdentifier(currentPixelBuffer as AnyObject)
        )
        XCTAssertNotEqual(
            ObjectIdentifier(snapshot!.pixelBuffer as AnyObject),
            ObjectIdentifier(conflictingPixelBuffer as AnyObject)
        )
    }

    func testEqualKnownPTSAcceptsOnlyIdempotentRetransmissionWithoutReplacement() {
        let store = LatestFrameEvidenceStore()
        let pixelBuffer = makePixelBuffer()
        let timestamp = CMTime(value: 35, timescale: 10)

        XCTAssertTrue(store.publish(
            pixelBuffer: pixelBuffer,
            orientation: .right,
            sourceFrameId: "equal-pts-identical",
            capturedAt: Date(timeIntervalSince1970: 135),
            isStable: true,
            lensID: CameraLens.wide.rawValue,
            lensGeneration: 3,
            samplePresentationTimestamp: timestamp,
            sessionGeneration: 9
        ))

        // The exact same buffer and provenance are an idempotent retry. It is
        // accepted as a no-op, so callback Date cannot refresh the envelope.
        XCTAssertTrue(store.publish(
            pixelBuffer: pixelBuffer,
            orientation: .right,
            sourceFrameId: "equal-pts-identical",
            capturedAt: Date(timeIntervalSince1970: 136),
            isStable: true,
            lensID: CameraLens.wide.rawValue,
            lensGeneration: 3,
            samplePresentationTimestamp: timestamp,
            sessionGeneration: 9
        ))

        let snapshot = store.snapshot()
        XCTAssertEqual(snapshot?.sourceFrameId, "equal-pts-identical")
        XCTAssertEqual(snapshot?.capturedAt, Date(timeIntervalSince1970: 135))
        XCTAssertEqual(snapshot?.sessionGeneration, 9)
        XCTAssertEqual(snapshot?.lensGeneration, 3)
        XCTAssertEqual(
            ObjectIdentifier(snapshot!.pixelBuffer as AnyObject),
            ObjectIdentifier(pixelBuffer as AnyObject)
        )
        XCTAssertEqual(CMTimeCompare(snapshot!.samplePresentationTimestamp, timestamp), 0)
    }

    func testMismatchedPreviewGeometryIsUnavailableAtImmutableBoundary() {
        let geometry = CameraPreviewGeometry(
            destinationSize: CGSize(width: 390, height: 844),
            imageOrientation: .up,
            isMirrored: false
        )!
        let snapshot = LatestFrameEvidenceStore.Snapshot(
            pixelBuffer: makePixelBuffer(),
            orientation: .right,
            sourceFrameId: "mismatched-geometry",
            capturedAt: Date(timeIntervalSince1970: 70),
            isStable: true,
            lensID: CameraLens.wide.rawValue,
            previewGeometry: geometry,
            lensGeneration: 10
        )

        XCTAssertNil(snapshot?.previewGeometry)
        XCTAssertNil(snapshot?.makeEnvelope().previewGeometry)
    }

    func testDetrProvenanceMustMatchFrameGenerationAndOrientation() {
        let measuredAt = Date(timeIntervalSince1970: 50)
        let samplePTS = CMTime(value: 1, timescale: 30)
        let provenance = FeatureSampleProvenance(
            frameID: "frame-a",
            captureGeneration: 7,
            orientation: .up,
            samplePresentationTimestamp: samplePTS,
            sessionGeneration: 4
        )
        let state = makeDetrAdapterState(measuredAt: measuredAt, provenance: provenance)
        let cases: [(String, UInt64, CGImagePropertyOrientation, CMTime, UInt64, Bool)] = [
            ("frame-a", 7, .up, samplePTS, 4, true),
            ("frame-a", 7, .up, CMTime(value: 2, timescale: 30), 4, false),
            ("frame-a", 7, .up, samplePTS, 5, false),
            ("frame-b", 7, .up, samplePTS, 4, false),
            ("frame-a", 8, .up, samplePTS, 4, false),
            ("frame-a", 7, .right, samplePTS, 4, false)
        ]

        for (frameID, generation, orientation, timestamp, sessionGeneration, shouldKeepDetr) in cases {
            let snapshot = LatestFrameEvidenceStore.Snapshot(
                pixelBuffer: makePixelBuffer(),
                orientation: orientation,
                sourceFrameId: frameID,
                capturedAt: measuredAt,
                isStable: true,
                adapterState: state,
                lensGeneration: generation,
                samplePresentationTimestamp: timestamp,
                sessionGeneration: sessionGeneration
            )

            XCTAssertEqual(
                snapshot?.adapterState?.detr != nil,
                shouldKeepDetr,
                "DETR must require frame/lens/orientation/PTS/session provenance to match"
            )
            XCTAssertEqual(
                snapshot?.adapterState?.debugData.detrDetections.isEmpty,
                !shouldKeepDetr,
                "a mismatched DETR sample must fail closed without legacy fallback"
            )
        }
    }


    func testTrackedDetrKeepsSourceClockAndValidatesLinkageAtBothSnapshotBoundaries() {
        let sourceDate = Date(timeIntervalSince1970: 100)
        func frame(_ id: String, pts: Int64, generation: UInt64 = 7,
                   session: UInt64? = 4, lifecycle: UInt64 = 9,
                   orientation: CGImagePropertyOrientation = .up) -> VisionObjectFrame {
            VisionObjectFrame(frameID: id, captureGeneration: generation, sessionGeneration: session,
                              lifecycleGeneration: lifecycle, orientation: orientation,
                              samplePTS: CMTime(value: pts, timescale: 10),
                              capturedAt: sourceDate.addingTimeInterval(Double(pts - 10) / 10))
        }
        let source = frame("source", pts: 10)
        let current = frame("current", pts: 12)
        let detection = FeatureSnapshotDetectedObject(
            boundingBox: CGRect(x: 0.4, y: 0.3, width: 0.2, height: 0.2),
            label: "chair", confidence: 0.24)
        let cases: [(String, VisionObjectFrame, VisionObjectFrame, Date, Date, [Float], Bool)] = [
            ("valid", source, current, sourceDate, current.capturedAt, [0.99], true),
            ("renewed source clock", source, current, current.capturedAt, current.capturedAt, [0.99], false),
            ("capture mismatch", frame("source", pts: 10, generation: 6), current, sourceDate, current.capturedAt, [0.99], false),
            ("session mismatch", frame("source", pts: 10, session: 3), current, sourceDate, current.capturedAt, [0.99], false),
            ("lifecycle mismatch", frame("source", pts: 10, lifecycle: 8), current, sourceDate, current.capturedAt, [0.99], false),
            ("orientation mismatch", frame("source", pts: 10, orientation: .right), current, sourceDate, current.capturedAt, [0.99], false),
            ("future source", frame("source", pts: 13), current, sourceDate.addingTimeInterval(0.3), current.capturedAt, [0.99], false),
            ("old source at completion", source, current, sourceDate, sourceDate.addingTimeInterval(1.21), [0.99], false),
            ("low raw tracking quality", source, current, sourceDate, current.capturedAt, [0.74], false),
            ("missing per-object quality", source, current, sourceDate, current.capturedAt, [], false),
            ("forged current frame", source, frame("different", pts: 12), sourceDate, current.capturedAt, [0.99], false)
        ]
        for (name, sourceContext, currentContext, measuredAt, geometryMeasuredAt, quality, expected) in cases {
            let sample = FeatureSample(
                value: FeatureSnapshotDetrPayload(detections: [detection],
                    tracking: FeatureSnapshotDetrTracking(source: sourceContext, current: currentContext,
                        geometryMeasuredAt: geometryMeasuredAt, qualities: quality,
                        geometries: [VisionObjectGeometry(seedSlot: 0, rawBoundingBox: detection.boundingBox)!])),
                measuredAt: measuredAt, baseConfidence: 0.24, provenance: current.featureProvenance)
            let state = PipelineFeatureSnapshotAdapterState(
                features: CoachingFeatures(),
                debugData: DebugData(detrDetections: [DETRDetection(
                    boundingBox: detection.boundingBox, label: detection.label, confidence: 0.24)],
                    detrMeasuredAt: measuredAt),
                vision: nil, horizonMeasuredAt: nil, horizon: nil,
                lightingMeasuredAt: nil, lighting: nil, detr: sample,
                aestheticMeasuredAt: nil, aesthetic: nil)
            let snapshot = LatestFrameEvidenceStore.Snapshot(
                pixelBuffer: makePixelBuffer(), orientation: .up, sourceFrameId: current.frameID,
                capturedAt: current.capturedAt, isStable: true, adapterState: state,
                lensGeneration: 7, samplePresentationTimestamp: current.samplePTS, sessionGeneration: 4)
            XCTAssertEqual(snapshot?.adapterState?.detr != nil, expected, name)
            XCTAssertEqual(snapshot?.adapterState?.debugData.detrDetections.isEmpty, !expected, name)
            let input = PipelineFeatureSnapshotAdapter().makeInput(
                frameId: current.frameID, mode: .live, capturedAt: current.capturedAt,
                expectedDetrProvenance: current.featureProvenance, state: state)
            XCTAssertEqual(input.detr != nil, expected, name)
            if expected {
                XCTAssertEqual(input.detr?.measuredAt, sourceDate)
                XCTAssertEqual(input.detr?.value.detections.first?.confidence, 0.24)
                XCTAssertEqual(input.detr?.value.tracking?.source.frameID, "source")
                XCTAssertEqual(input.detr?.provenance?.frameID, "current")
            }
        }
    }

    func testTrackedGeometryCannotLoseOrCrossWireItsRawMeasurementAtSnapshotBoundary() throws {
        let date = Date(timeIntervalSince1970: 200)
        let source = VisionObjectFrame(frameID: "source", captureGeneration: 7, sessionGeneration: 4,
            lifecycleGeneration: 9, orientation: .up, samplePTS: CMTime(value: 10, timescale: 10), capturedAt: date)
        let current = VisionObjectFrame(frameID: "current", captureGeneration: 7, sessionGeneration: 4,
            lifecycleGeneration: 9, orientation: .up, samplePTS: CMTime(value: 11, timescale: 10),
            capturedAt: date.addingTimeInterval(0.1))
        let left = try XCTUnwrap(VisionObjectGeometry(seedSlot: 0,
            rawBoundingBox: CGRect(x: 0.1, y: -0.01, width: 0.2, height: 0.3)))
        let right = try XCTUnwrap(VisionObjectGeometry(seedSlot: 1,
            rawBoundingBox: CGRect(x: 0.6, y: 0.2, width: 0.2, height: 0.3)))
        let duplicate = try XCTUnwrap(VisionObjectGeometry(seedSlot: 0, rawBoundingBox: right.rawBoundingBox))
        let detections = [left, right].map {
            FeatureSnapshotDetectedObject(boundingBox: $0.visibleImageIntersection, label: "chair", confidence: 0.9)
        }
        for (geometries, expected) in [([left, right], true), ([], false), ([left], false),
                                        ([right, left], false), ([left, duplicate], false)] {
            let tracking = FeatureSnapshotDetrTracking(source: source, current: current,
                geometryMeasuredAt: current.capturedAt, qualities: [0.95, 0.95], geometries: geometries)
            let sample = FeatureSample(value: FeatureSnapshotDetrPayload(detections: detections, tracking: tracking),
                measuredAt: date, baseConfidence: 0.9, provenance: current.featureProvenance)
            XCTAssertEqual(sample.hasValidTrackingLinkage, expected)
            let state = PipelineFeatureSnapshotAdapterState(features: CoachingFeatures(), debugData: DebugData(),
                vision: nil, horizonMeasuredAt: nil, horizon: nil, lightingMeasuredAt: nil, lighting: nil,
                detr: sample, aestheticMeasuredAt: nil, aesthetic: nil)
            let frozen = LatestFrameEvidenceStore.Snapshot(pixelBuffer: makePixelBuffer(), orientation: .up,
                sourceFrameId: "current", capturedAt: current.capturedAt, isStable: true, adapterState: state,
                lensGeneration: 7, samplePresentationTimestamp: current.samplePTS, sessionGeneration: 4)
            XCTAssertEqual(frozen?.adapterState?.detr != nil, expected)
            if expected {
                XCTAssertEqual(frozen?.adapterState?.detr?.value.tracking?.geometries, [left, right])
                XCTAssertEqual(tracking.objectObservationCoverage, .complete,
                               "Retained inventory and clipped image geometry describe different facts")
                XCTAssertEqual(tracking.trackingGeometryStatus, .clipped)
            }
        }
    }

    func testTrackingRequestSlotMustExistWithinItsOriginalSourceCandidateCount() throws {
        let date = Date(timeIntervalSince1970: 200)
        let source = VisionObjectFrame(frameID: "source", captureGeneration: 7, sessionGeneration: 4,
            lifecycleGeneration: 9, orientation: .up, samplePTS: CMTime(value: 10, timescale: 10), capturedAt: date)
        let current = VisionObjectFrame(frameID: "current", captureGeneration: 7, sessionGeneration: 4,
            lifecycleGeneration: 9, orientation: .up, samplePTS: CMTime(value: 11, timescale: 10),
            capturedAt: date.addingTimeInterval(0.1))
        let box = CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3)
        for (slot, count, expected) in [(3, 1, false), (2, 3, true), (3, 4, true)] {
            let tracking = FeatureSnapshotDetrTracking(source: source, current: current,
                geometryMeasuredAt: current.capturedAt, qualities: [0.95],
                geometries: [try XCTUnwrap(VisionObjectGeometry(seedSlot: slot, rawBoundingBox: box))],
                sourceCandidateCount: count)
            let sample = FeatureSample(value: FeatureSnapshotDetrPayload(detections: [
                FeatureSnapshotDetectedObject(boundingBox: box, label: "chair", confidence: 0.9)], tracking: tracking),
                measuredAt: date, baseConfidence: 0.9, provenance: current.featureProvenance)
            XCTAssertEqual(sample.hasValidTrackingLinkage, expected)
        }
    }

    private func makeAdapterState(marker: Int) -> PipelineFeatureSnapshotAdapterState {
        var features = CoachingFeatures()
        features.lensRecommendation = marker
        return PipelineFeatureSnapshotAdapterState(
            features: features,
            debugData: DebugData(),
            vision: nil,
            horizonMeasuredAt: nil,
            horizon: nil,
            lightingMeasuredAt: nil,
            lighting: nil,
            detr: nil,
            aestheticMeasuredAt: nil,
            aesthetic: nil
        )
    }

    private func makeDetrAdapterState(
        measuredAt: Date,
        provenance: FeatureSampleProvenance
    ) -> PipelineFeatureSnapshotAdapterState {
        let detection = DETRDetection(
            boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.4),
            label: "person",
            confidence: 0.9
        )
        return PipelineFeatureSnapshotAdapterState(
            features: CoachingFeatures(),
            debugData: DebugData(detrDetections: [detection], detrMeasuredAt: measuredAt),
            vision: nil,
            horizonMeasuredAt: nil,
            horizon: nil,
            lightingMeasuredAt: nil,
            lighting: nil,
            detr: FeatureSample(
                value: FeatureSnapshotDetrPayload(detections: [
                    FeatureSnapshotDetectedObject(
                        boundingBox: detection.boundingBox,
                        label: detection.label,
                        confidence: Double(detection.confidence)
                    )
                ]),
                measuredAt: measuredAt,
                baseConfidence: Double(detection.confidence),
                provenance: provenance
            ),
            aestheticMeasuredAt: nil,
            aesthetic: nil
        )
    }

    private func makePixelBuffer(width: Int = 4, height: Int = 4) -> CVPixelBuffer {
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
        XCTAssertEqual(status, kCVReturnSuccess)
        return pixelBuffer!
    }

    private func writeFirstPixel(_ bytes: [UInt8], to pixelBuffer: CVPixelBuffer) {
        XCTAssertEqual(bytes.count, 4)
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            XCTFail("pixel buffer has no base address")
            return
        }
        for (offset, byte) in bytes.enumerated() {
            baseAddress.storeBytes(of: byte, toByteOffset: offset, as: UInt8.self)
        }
    }

    private func readFirstPixel(from pixelBuffer: CVPixelBuffer) -> [UInt8] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return [] }
        return (0..<4).map { baseAddress.load(fromByteOffset: $0, as: UInt8.self) }
    }
}
