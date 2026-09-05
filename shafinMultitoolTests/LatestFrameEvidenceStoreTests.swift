import CoreGraphics
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
        let provenance = FeatureSampleProvenance(
            frameID: "frame-a",
            captureGeneration: 7,
            orientation: .up
        )
        let state = makeDetrAdapterState(measuredAt: measuredAt, provenance: provenance)
        let cases: [(String, UInt64, CGImagePropertyOrientation, Bool)] = [
            ("frame-a", 7, .up, true),
            ("frame-b", 7, .up, false),
            ("frame-a", 8, .up, false),
            ("frame-a", 7, .right, false)
        ]

        for (frameID, generation, orientation, shouldKeepDetr) in cases {
            let snapshot = LatestFrameEvidenceStore.Snapshot(
                pixelBuffer: makePixelBuffer(),
                orientation: orientation,
                sourceFrameId: frameID,
                capturedAt: measuredAt,
                isStable: true,
                adapterState: state,
                lensGeneration: generation
            )

            XCTAssertEqual(snapshot?.adapterState?.detr != nil, shouldKeepDetr)
            XCTAssertEqual(snapshot?.adapterState?.debugData.detrDetections.isEmpty, !shouldKeepDetr)
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
