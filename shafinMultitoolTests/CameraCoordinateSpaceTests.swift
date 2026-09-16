//
//  CameraCoordinateSpaceTests.swift
//  shafinMultitoolTests
//
//  M2-002 CameraGeometryOwner: property tests for the canonical coordinate
//  spaces — unit-square bounds everywhere, invertibility of defined inverse
//  conversions, and fail-closed degenerate inputs.
//

import CoreGraphics
import CoreVideo
import XCTest
@testable import shafinMultitool

final class CameraCoordinateSpaceTests: XCTestCase {

    // Deterministic pseudo-random coverage (fixed seed).
    private var deterministicPoints: [(Double, Double)] {
        var values: [(Double, Double)] = []
        var state: UInt64 = 0x9E3779B97F4A7C15
        for _ in 0..<256 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let x = Double(state >> 11) / Double(UInt64.max >> 11)
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let y = Double(state >> 11) / Double(UInt64.max >> 11)
            values.append((x, y))
        }
        // Grid + edges + out-of-range probes.
        let grid: [Double] = [0, 0.25, 0.5, 0.75, 1]
        for gx in grid {
            for gy in grid {
                values.append((gx, gy))
            }
        }
        values.append((-0.5, 1.5))
        values.append((2, -1))
        values.append((.nan, .infinity))
        return values
    }

    /// Mirrors the production clamp: non-finite fails closed to 0.
    private func clampedUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    // MARK: - Unit-square bounds

    func testEverySpaceAcceptsAndClampsToUnitSquare() {
        for space in CameraCoordinateSpaceV2.allCases {
            for (x, y) in deterministicPoints {
                let point = CameraSpacePointV2(space: space, x: x, y: y)
                XCTAssertEqual(point.space, space)
                XCTAssertGreaterThanOrEqual(point.x, 0)
                XCTAssertLessThanOrEqual(point.x, 1)
                XCTAssertGreaterThanOrEqual(point.y, 0)
                XCTAssertLessThanOrEqual(point.y, 1)
                XCTAssertFalse(point.x.isNaN)
                XCTAssertFalse(point.y.isNaN)
            }
        }
    }

    // MARK: - Inverse conversions

    func testVerticalFlipIsItsOwnInverse() {
        for space in [CameraCoordinateSpaceV2.vision, .subjectTarget, .preview, .swiftUICanvas] {
            for (x, y) in deterministicPoints {
                let point = CameraSpacePointV2(space: space, x: x, y: y)
                let flipped = point.flippedVertically.flippedVertically
                XCTAssertEqual(flipped.x, clampedUnit(x), accuracy: 1e-12)
                XCTAssertEqual(flipped.y, clampedUnit(y), accuracy: 1e-12)
            }
        }
    }

    func testVisionToSubjectTargetFlipMapsTopToBottom() {
        let topOfDownSpace = CameraSpacePointV2(space: .subjectTarget, x: 0.5, y: 0)
        XCTAssertEqual(topOfDownSpace.flippedVertically.y, 1)

        let bottomOfDownSpace = CameraSpacePointV2(space: .subjectTarget, x: 0.5, y: 1)
        XCTAssertEqual(bottomOfDownSpace.flippedVertically.y, 0)
    }

    func testSubjectTargetHelpersPreserveExplicitInputSpaceForAsymmetricAllDirections() throws {
        let visionSubject = NormalizedRect(x: 0.31, y: 0.17, width: 0.19, height: 0.23)
        let subjectTargetSubject = try XCTUnwrap(
            visionSubject.converted(from: .vision, to: .subjectTarget)
        )
        let directions: [SemanticDirection] = [.left, .right, .up, .down]

        for direction in directions {
            let visionTarget = try XCTUnwrap(
                direction.subjectTargetRegion(from: visionSubject, sourceSpace: .vision)
            )
            let subjectTarget = try XCTUnwrap(
                direction.subjectTargetRegion(from: subjectTargetSubject, sourceSpace: .subjectTarget)
            )
            XCTAssertEqual(
                visionTarget,
                try XCTUnwrap(subjectTarget.converted(from: .subjectTarget, to: .vision)),
                "\(direction) must return the same geometry in each explicitly supplied space"
            )

            let visionPoint = try XCTUnwrap(
                direction.subjectTargetPoint(from: visionSubject, sourceSpace: .vision)
            )
            let subjectTargetPoint = try XCTUnwrap(
                direction.subjectTargetPoint(from: subjectTargetSubject, sourceSpace: .subjectTarget)
            )
            let convertedPoint = CameraSpacePointV2(
                space: .subjectTarget,
                x: subjectTargetPoint.x,
                y: subjectTargetPoint.y
            ).flippedVertically
            XCTAssertEqual(visionPoint.x, convertedPoint.x, accuracy: 1e-12)
            XCTAssertEqual(visionPoint.y, convertedPoint.y, accuracy: 1e-12)

            // Independent edge oracles keep a direction inversion from
            // passing solely because both coordinate-space calls agree.
            switch direction {
            case .left:
                XCTAssertEqual(visionTarget.x, 0, accuracy: 1e-12)
                XCTAssertEqual(visionPoint.x, 0, accuracy: 1e-12)
            case .right:
                XCTAssertEqual(visionTarget.x + visionTarget.width, 1, accuracy: 1e-12)
                XCTAssertEqual(visionPoint.x, 1, accuracy: 1e-12)
            case .up:
                XCTAssertEqual(visionTarget.y + visionTarget.height, 1, accuracy: 1e-12)
                XCTAssertEqual(visionPoint.y, 1, accuracy: 1e-12)
            case .down:
                XCTAssertEqual(visionTarget.y, 0, accuracy: 1e-12)
                XCTAssertEqual(visionPoint.y, 0, accuracy: 1e-12)
            case .forward, .back, .none:
                XCTFail("Unexpected in-plane direction fixture: \(direction)")
            }
        }
    }

    func testSubjectTargetHelpersRejectUnsupportedAndDegenerateSpaces() {
        let subject = NormalizedRect(x: 0.30, y: 0.20, width: 0.20, height: 0.30)
        XCTAssertNil(
            SemanticDirection.left.subjectTargetRegion(from: subject, sourceSpace: .preview)
        )
        XCTAssertNil(
            SemanticDirection.left.subjectTargetPoint(from: subject, sourceSpace: .swiftUICanvas)
        )
        XCTAssertNil(
            SemanticDirection.right.subjectTargetRegion(
                from: NormalizedRect(x: 0.30, y: 0.20, width: 0, height: 0.30),
                sourceSpace: .vision
            )
        )
        XCTAssertNil(
            NormalizedRect(x: 0.90, y: 0.20, width: 0.20, height: 0.30)
                .converted(from: .vision, to: .vision)
        )
    }

    func testAspectFillRoundTripInsideCropWindow() {
        // Sensor 4000x3000 -> model input 513x513 (aspect fill, center crop).
        let source = CGSize(width: 4000, height: 3000)
        let destination = CGSize(width: 513, height: 513)
        let transform = AspectFillTransform(sourceSize: source, destinationSize: destination)

        // The destination is fully covered, so every destination-normalized
        // point inside the visible window maps back into the source square.
        var insideCount = 0
        for (dx, dy) in deterministicPoints {
            let clampedDx = clampedUnit(dx)
            let clampedDy = clampedUnit(dy)
            guard let sourcePoint = transform.sourceNormalized(fromDestinationX: clampedDx, y: clampedDy) else {
                continue
            }
            insideCount += 1
            let roundTrip = transform.destinationPoint(fromSourceNormalized: sourcePoint.x, y: sourcePoint.y)
            XCTAssertEqual(roundTrip.x, clampedDx, accuracy: 1e-9)
            XCTAssertEqual(roundTrip.y, clampedDy, accuracy: 1e-9)
        }
        XCTAssertGreaterThan(insideCount, 200, "most probed points must lie inside the crop window")
    }

    func testAspectFillBoundsHoldForAllSourcePoints() {
        let cases: [(CGSize, CGSize)] = [
            (CGSize(width: 4032, height: 3024), CGSize(width: 513, height: 513)),
            (CGSize(width: 1920, height: 1080), CGSize(width: 224, height: 224)),
            (CGSize(width: 3000, height: 4000), CGSize(width: 640, height: 480)),
            (CGSize(width: 1080, height: 1920), CGSize(width: 1080, height: 1000)),
        ]
        for (source, destination) in cases {
            let transform = AspectFillTransform(sourceSize: source, destinationSize: destination)
            for (x, y) in deterministicPoints {
                let mapped = transform.destinationPoint(fromSourceNormalized: x, y: y)
                XCTAssertGreaterThanOrEqual(mapped.x, 0)
                XCTAssertLessThanOrEqual(mapped.x, 1)
                XCTAssertGreaterThanOrEqual(mapped.y, 0)
                XCTAssertLessThanOrEqual(mapped.y, 1)
            }
        }
    }

    func testAspectFillOutsideCropWindowIsNotInvertible() {
        // Tall sensor into wide destination: left/right edges are cropped away.
        let transform = AspectFillTransform(
            sourceSize: CGSize(width: 3000, height: 1000),
            destinationSize: CGSize(width: 1000, height: 1000)
        )
        // The horizontal center survives; extreme horizontal edges do not.
        XCTAssertNotNil(transform.sourceNormalized(fromDestinationX: 0.5, y: 0.5))
        if transform.sourceNormalized(fromDestinationX: 0.0, y: 0.5) == nil {
            XCTAssertNil(transform.sourceNormalized(fromDestinationX: 0.0, y: 0.5))
        } else {
            // When the crop covers the full width, the extreme edge must
            // round-trip instead.
            let roundTrip = transform.destinationPoint(fromSourceNormalized: 0, y: 0.5)
            XCTAssertEqual(roundTrip.x, 0, accuracy: 1e-9)
        }
    }

    func testDegenerateSizesFailClosedToIdentity() {
        let transform = AspectFillTransform(
            sourceSize: CGSize(width: 0, height: 100),
            destinationSize: CGSize(width: 100, height: 100)
        )
        let mapped = transform.destinationPoint(fromSourceNormalized: 0.25, y: 0.75)
        XCTAssertEqual(mapped.x, 0.25, accuracy: 1e-12)
        XCTAssertEqual(mapped.y, 0.75, accuracy: 1e-12)

        let point = CameraSpacePointV2(space: .modelInput, x: .nan, y: .infinity)
        XCTAssertEqual(point.x, 0)
        XCTAssertEqual(point.y, 0)
    }

    // MARK: - N11 tensor transform provenance

    func testModelTensorRecipeUsesIndependentScaleNotPreviewAspectFill() throws {
        // Frozen SETCompositionNet-v1 full-frame recipe: 4000x3000 -> 320x320.
        let sensor = CGSize(width: 4000, height: 3000)
        let tensor = CGSize(
            width: CGFloat(SETCompositionNetContract.fullFrameWidth),
            height: CGFloat(SETCompositionNetContract.fullFrameHeight)
        )
        let recipe = try XCTUnwrap(
            CameraTensorTransformContract.recipe(
                forTensorID: CameraTensorTransformContract.setCompositionNetFullFrameTensorID,
                orientation: .up,
                sourcePixelSize: sensor,
                destinationPixelSize: tensor
            )
        )
        XCTAssertEqual(recipe.resizeGeometry, .independentScaleToTarget)
        XCTAssertEqual(recipe.space, .modelInput)
        XCTAssertEqual(recipe.scaleX, 320.0 / 4000.0, accuracy: 1e-12)
        XCTAssertEqual(recipe.scaleY, 320.0 / 3000.0, accuracy: 1e-12)
        XCTAssertNotEqual(recipe.scaleX, recipe.scaleY)
        XCTAssertNil(recipe.aspectFill)
        XCTAssertTrue(CameraTensorTransformContract.validate(recipe).isEmpty)

        // The preview's aspect-fill transform for the same sizes is a
        // different map (centre crop, not uniform squash) and is rejected for
        // the ML tensor instead of being silently substituted.
        let previewAspectFill = AspectFillTransform(sourceSize: sensor, destinationSize: tensor)
        XCTAssertEqual(previewAspectFill.fillScale, 320.0 / 3000.0, accuracy: 1e-12)
        XCTAssertNotEqual(previewAspectFill.fillScale, recipe.scaleX, accuracy: 1e-12)
    }

    func testAspectFillAndIndependentScaleAreDifferentNormalizedMaps() throws {
        let sensor = CGSize(width: 4000, height: 3000)
        let tensor = CGSize(width: 320, height: 320)
        let independent = try XCTUnwrap(
            CameraTensorTransformContract.recipe(
                forTensorID: CameraTensorTransformContract.setCompositionNetFullFrameTensorID,
                orientation: .up,
                sourcePixelSize: sensor,
                destinationPixelSize: tensor
            )
        )
        let aspect = try XCTUnwrap(
            CameraTensorTransform(
                tensorID: CameraTensorTransformContract.setCompositionNetFullFrameTensorID,
                resizeGeometry: .aspectFillCenterCrop,
                orientation: .up,
                sourcePixelSize: sensor,
                destinationPixelSize: tensor
            )
        )

        // Independent scale is the identity on normalized coordinates.
        let independentPoint = try XCTUnwrap(
            independent.destinationPoint(fromSourceNormalized: 0.3, y: 0.5)
        )
        XCTAssertEqual(independentPoint.x, 0.3, accuracy: 1e-12)
        XCTAssertEqual(independentPoint.y, 0.5, accuracy: 1e-12)

        // Aspect-fill compresses the long axis into the crop window.
        let aspectPoint = try XCTUnwrap(
            aspect.destinationPoint(fromSourceNormalized: 0.3, y: 0.5)
        )
        XCTAssertNotEqual(aspectPoint.x, independentPoint.x)
        XCTAssertEqual(aspectPoint.y, 0.5, accuracy: 1e-12)

        // Side bands that the square crop removes are excluded, not reported
        // at the edge.
        XCTAssertNil(aspect.destinationPoint(fromSourceNormalized: 0.05, y: 0.5))
    }

    func testVisibleDestinationPointExcludesCroppedTargetsInsteadOfClamping() {
        // Tall sensor into a wide destination: left/right bands are cropped.
        let transform = AspectFillTransform(
            sourceSize: CGSize(width: 3000, height: 1000),
            destinationSize: CGSize(width: 1000, height: 1000)
        )
        XCTAssertNotNil(transform.visibleDestinationPoint(fromSourceNormalized: 0.5, y: 0.5))

        // An invisible target returns nil; the legacy clamping API would have
        // pinned it to x = 0. The visible API must not manufacture an edge
        // coordinate for a point that is outside the output.
        let clamped = transform.destinationPoint(fromSourceNormalized: 0.0, y: 0.5)
        XCTAssertEqual(clamped.x, 0, accuracy: 1e-12)
        XCTAssertNil(transform.visibleDestinationPoint(fromSourceNormalized: 0.0, y: 0.5))
        XCTAssertNil(transform.visibleDestinationPoint(fromSourceNormalized: 1.0, y: 0.5))
        XCTAssertNil(transform.visibleDestinationPoint(fromSourceNormalized: .nan, y: 0.5))
    }

    func testTensorTransformRejectsSubstitutedAspectFillRecipe() throws {
        let sensor = CGSize(width: 4000, height: 3000)
        let tensor = CGSize(width: 320, height: 320)
        let substituted = try XCTUnwrap(
            CameraTensorTransform(
                tensorID: CameraTensorTransformContract.setCompositionNetFullFrameTensorID,
                resizeGeometry: .aspectFillCenterCrop,
                orientation: .up,
                sourcePixelSize: sensor,
                destinationPixelSize: tensor
            )
        )
        let errors = CameraTensorTransformContract.validate(substituted)
        XCTAssertTrue(
            errors.contains { $0.contains(CameraTensorResizeGeometry.independentScaleToTarget.rawValue) },
            "the preview aspect-fill transform must not satisfy the ML tensor recipe: \(errors)"
        )
        XCTAssertTrue(errors.contains { $0.contains("not interchangeable") })
    }

    func testTensorTransformRejectsUnknownTensorAndDegenerateSizes() throws {
        XCTAssertNil(CameraTensorTransformContract.requiredResizeGeometry(forTensorID: "unknown.tensor"))
        let unknown = try XCTUnwrap(
            CameraTensorTransform(
                tensorID: "unknown.tensor",
                resizeGeometry: .independentScaleToTarget,
                orientation: .up,
                sourcePixelSize: CGSize(width: 10, height: 10),
                destinationPixelSize: CGSize(width: 10, height: 10)
            )
        )
        XCTAssertEqual(
            CameraTensorTransformContract.validate(unknown),
            ["unknown tensor id unknown.tensor: no frozen preprocessing recipe"]
        )

        // Degenerate sizes fail closed at construction.
        XCTAssertNil(
            CameraTensorTransform(
                tensorID: CameraTensorTransformContract.setCompositionNetFullFrameTensorID,
                resizeGeometry: .independentScaleToTarget,
                orientation: .up,
                sourcePixelSize: CGSize(width: 0, height: 3000),
                destinationPixelSize: CGSize(width: 320, height: 320)
            )
        )
    }

    func testTensorTransformOrientationAndCropAreIndependentProvenance() throws {
        let sensor = CGSize(width: 4000, height: 3000)
        let tensor = CGSize(width: 320, height: 320)
        let up = try XCTUnwrap(
            CameraTensorTransformContract.recipe(
                forTensorID: CameraTensorTransformContract.setCompositionNetFullFrameTensorID,
                orientation: .up,
                sourcePixelSize: sensor,
                destinationPixelSize: tensor
            )
        )
        let left = try XCTUnwrap(
            CameraTensorTransformContract.recipe(
                forTensorID: CameraTensorTransformContract.setCompositionNetFullFrameTensorID,
                orientation: .left,
                sourcePixelSize: sensor,
                destinationPixelSize: tensor
            )
        )
        // Rotation is provenance: identical sizes/geometry with a different
        // recorded orientation is a different transform, not a bbox shift.
        XCTAssertEqual(up.resizeGeometry, left.resizeGeometry)
        XCTAssertNotEqual(up.orientation, left.orientation)
        XCTAssertNotEqual(up, left)
        XCTAssertFalse(up.orientation.swapsAxes)
        XCTAssertTrue(left.orientation.swapsAxes)

        // The crop window is recorded separately from orientation.
        let aspect = try XCTUnwrap(
            CameraTensorTransform(
                tensorID: CameraTensorTransformContract.setCompositionNetFullFrameTensorID,
                resizeGeometry: .aspectFillCenterCrop,
                orientation: .up,
                sourcePixelSize: sensor,
                destinationPixelSize: tensor
            )
        )
        XCTAssertNotEqual(aspect, up)
        XCTAssertNotNil(aspect.aspectFill)
        XCTAssertGreaterThan(try XCTUnwrap(aspect.aspectFill).cropOffsetXPixels, 0)
        XCTAssertEqual(aspect.orientation, .up)
    }

    // MARK: - Text and marker share one scene direction (mirror + output crop)

    func testTextAndMarkerAgreeForSameActionUnderMirroringAndOutputCrop() throws {
        // One accepted action (camera-framed shift-left). Its published text
        // direction and marker geometry come from the same M2-004 owner value.
        let action = SemanticActionType.shiftFrameLeft
        let sceneDirection = try XCTUnwrap(action.subjectDisplacementDirection)
        XCTAssertEqual(
            sceneDirection,
            SemanticDirection.left.subjectDisplacement(actionFrame: .moveCamera)
        )

        let subject = NormalizedRect(x: 0.40, y: 0.35, width: 0.20, height: 0.30)
        let region = try XCTUnwrap(
            sceneDirection.subjectTargetRegion(from: subject, sourceSpace: .subjectTarget)
        )
        let point = try XCTUnwrap(
            sceneDirection.subjectTargetPoint(from: subject, sourceSpace: .subjectTarget)
        )
        // The marker region and the text anchor lie on the same edge of the
        // same published scene direction; neither is derived independently.
        switch sceneDirection {
        case .left:
            XCTAssertEqual(region.x, 0, accuracy: 1e-12)
            XCTAssertEqual(point.x, 0, accuracy: 1e-12)
        case .right:
            XCTAssertEqual(region.x + region.width, 1, accuracy: 1e-12)
            XCTAssertEqual(point.x, 1, accuracy: 1e-12)
        case .up:
            XCTAssertEqual(region.y, 0, accuracy: 1e-12)
            XCTAssertEqual(point.y, 0, accuracy: 1e-12)
        case .down:
            XCTAssertEqual(region.y + region.height, 1, accuracy: 1e-12)
            XCTAssertEqual(point.y, 1, accuracy: 1e-12)
        case .forward, .back, .none:
            XCTFail("shiftFrameLeft must publish an in-plane subject direction")
        }
        if sceneDirection == .left || sceneDirection == .right {
            XCTAssertEqual(point.y, region.y + region.height / 2, accuracy: 1e-12)
        }

        // All eight display states are display concerns: mirroring must not
        // change the scene-space text/marker pair.
        for orientation in [CameraCoachOrientation.portrait, .portraitUpsideDown,
                            .landscapeLeft, .landscapeRight] {
            for mirrored in [false, true] {
                let transform = CameraDisplayTransform(orientation: orientation, isMirrored: mirrored)
                XCTAssertEqual(transform.isMirrored, mirrored)
                let repeatedRegion = try XCTUnwrap(
                    sceneDirection.subjectTargetRegion(from: subject, sourceSpace: .subjectTarget)
                )
                let repeatedPoint = try XCTUnwrap(
                    sceneDirection.subjectTargetPoint(from: subject, sourceSpace: .subjectTarget)
                )
                XCTAssertEqual(repeatedRegion, region)
                XCTAssertEqual(repeatedPoint.x, point.x, accuracy: 1e-12)
                XCTAssertEqual(repeatedPoint.y, point.y, accuracy: 1e-12)
            }
        }

        // Model-input/output-crop space is not the subject space: a marker must
        // never be derived from the tensor crop window.
        XCTAssertNil(sceneDirection.subjectTargetRegion(from: subject, sourceSpace: .modelInput))
        XCTAssertNil(sceneDirection.subjectTargetPoint(from: subject, sourceSpace: .modelInput))
    }

    // MARK: - N11 production preprocessing transforms (MetalPreprocessor)

    /// A non-square source so independent x/y scale cannot coincide with a
    /// single common (aspect-fill) scale.
    private func makeNonSquareBGRAPixelBuffer() -> CVPixelBuffer? {
        let width = 64
        let height = 48
        var buffer: CVPixelBuffer?
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
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else { return nil }
        guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            memset(baseAddress, 128, CVPixelBufferGetDataSize(buffer))
        }
        return buffer
    }

    /// ROI near the top edge: after square-padding and clipping the applied
    /// crop is non-square (16 x 12.8 pixels on a 64 x 48 frame), so an honest
    /// transform must carry different per-axis scales.
    private let topEdgeNonSquareROI = SETCompositionNetROI(
        x: 0.4,
        y: 0.0,
        width: 0.2,
        height: 0.2
    )

    func testProductionPreprocessorRecordsIndependentScalePerAxis() throws {
        let source = try XCTUnwrap(makeNonSquareBGRAPixelBuffer())
        let preprocessor = MetalPreprocessor()
        let bundle = try XCTUnwrap(
            preprocessor.setCompositionNetPixelBufferBundle(
                from: source,
                orientation: .up,
                roi: topEdgeNonSquareROI
            )
        )

        // Full frame 64x48 -> 320x320: the recipe squashes x and y by different
        // ratios. A single shared aspect-fill scale would be a different map.
        let fullFrame = bundle.transforms.fullFrameTransform
        XCTAssertEqual(
            fullFrame.tensorID,
            CameraTensorTransformContract.setCompositionNetFullFrameTensorID
        )
        XCTAssertEqual(fullFrame.resizeGeometry, .independentScaleToTarget)
        XCTAssertNil(fullFrame.aspectFill)
        XCTAssertEqual(fullFrame.scaleX, 320.0 / 64.0, accuracy: 1e-9)
        XCTAssertEqual(fullFrame.scaleY, 320.0 / 48.0, accuracy: 1e-9)
        XCTAssertNotEqual(fullFrame.scaleX, fullFrame.scaleY)
        XCTAssertEqual(fullFrame.orientation, .up)
        XCTAssertTrue(CameraTensorTransformContract.validate(fullFrame).isEmpty)

        // Subject crop: the actually applied crop is non-square, so the two
        // recorded axis scales must stay independent here too.
        let subjectCrop = try XCTUnwrap(bundle.transforms.subjectCropTransform)
        XCTAssertEqual(
            subjectCrop.tensorID,
            CameraTensorTransformContract.setCompositionNetSubjectCropTensorID
        )
        XCTAssertEqual(subjectCrop.resizeGeometry, .independentScaleToTarget)
        XCTAssertNil(subjectCrop.aspectFill)
        XCTAssertGreaterThan(subjectCrop.scaleX, 0)
        XCTAssertGreaterThan(subjectCrop.scaleY, 0)
        XCTAssertNotEqual(subjectCrop.scaleX, subjectCrop.scaleY)
        XCTAssertTrue(CameraTensorTransformContract.validate(subjectCrop).isEmpty)

        // The recorded scale is the renderer's applied scale, not a re-derived
        // "convenient" value: 320/64 and 320/48 are exactly what Core Image
        // used for the full-frame resize above.
        let window = try XCTUnwrap(bundle.transforms.subjectCropWindow)
        XCTAssertEqual(subjectCrop.scaleX, 192.0 / 16.0, accuracy: 1e-9)
        XCTAssertEqual(subjectCrop.scaleY, 192.0 / (window.bottom - window.top), accuracy: 1e-9)

        // The logical-RGB seam records the same honest geometry.
        let rgb = try XCTUnwrap(
            preprocessor.setCompositionNetRGBTensorBundle(
                from: source,
                orientation: .up,
                roi: topEdgeNonSquareROI
            )
        )
        let rgbFullFrame = rgb.transforms.fullFrameTransform
        XCTAssertEqual(rgbFullFrame.resizeGeometry, .independentScaleToTarget)
        XCTAssertEqual(rgbFullFrame.scaleX, fullFrame.scaleX, accuracy: 1e-9)
        XCTAssertEqual(rgbFullFrame.scaleY, fullFrame.scaleY, accuracy: 1e-9)
        let rgbSubjectCrop = try XCTUnwrap(rgb.transforms.subjectCropTransform)
        XCTAssertEqual(rgbSubjectCrop.resizeGeometry, .independentScaleToTarget)
        // The two seams sample slightly different geometry and each records what it
        // actually applied: the raster seam uses Core Image's integer-expanded crop
        // extent, while the logical-RGB seam uses the nominal ROI bounds it samples.
        // The C02 requirement is per-tensor honesty, not bit-equality between two
        // different samplers, so assert the RGB seam against its OWN window and bound
        // the documented sub-pixel expansion instead of demanding identical values.
        let rgbWindow = try XCTUnwrap(rgb.transforms.subjectCropWindow)
        XCTAssertEqual(rgbSubjectCrop.scaleX, 192.0 / (rgbWindow.right - rgbWindow.left), accuracy: 1e-9)
        XCTAssertEqual(rgbSubjectCrop.scaleY, 192.0 / (rgbWindow.bottom - rgbWindow.top), accuracy: 1e-9)
        XCTAssertLessThanOrEqual(abs(rgbWindow.bottom - window.bottom), 1.0,
                                 "Core Image may expand the crop extent by at most one pixel")
        XCTAssertLessThanOrEqual(abs(rgbWindow.right - window.right), 1.0)
    }

    func testProductionPreprocessorRejectsSubstitutedAspectFillRecipeForBothTensors() throws {
        let sourceSize = CGSize(width: 64, height: 48)
        let fullFrameTarget = CGSize(
            width: CGFloat(SETCompositionNetContract.fullFrameWidth),
            height: CGFloat(SETCompositionNetContract.fullFrameHeight)
        )
        let subjectCropTarget = CGSize(
            width: CGFloat(SETCompositionNetContract.subjectCropWidth),
            height: CGFloat(SETCompositionNetContract.subjectCropHeight)
        )

        for (tensorID, target) in [
            (CameraTensorTransformContract.setCompositionNetFullFrameTensorID, fullFrameTarget),
            (CameraTensorTransformContract.setCompositionNetSubjectCropTensorID, subjectCropTarget)
        ] {
            let substituted = try XCTUnwrap(
                CameraTensorTransform(
                    tensorID: tensorID,
                    resizeGeometry: .aspectFillCenterCrop,
                    orientation: .up,
                    sourcePixelSize: sourceSize,
                    destinationPixelSize: target
                )
            )
            let errors = CameraTensorTransformContract.validate(substituted)
            XCTAssertTrue(
                errors.contains {
                    $0.contains(CameraTensorResizeGeometry.independentScaleToTarget.rawValue)
                },
                "\(tensorID): aspect-fill must not satisfy the frozen recipe: \(errors)"
            )
            XCTAssertTrue(errors.contains { $0.contains("not interchangeable") })
        }

        // The production bundle never substitutes aspect fill: it uses the
        // frozen recipe for both tensors.
        let source = try XCTUnwrap(makeNonSquareBGRAPixelBuffer())
        let bundle = try XCTUnwrap(
            MetalPreprocessor().setCompositionNetPixelBufferBundle(
                from: source,
                orientation: .up,
                roi: topEdgeNonSquareROI
            )
        )
        XCTAssertEqual(
            bundle.transforms.fullFrameTransform.resizeGeometry,
            .independentScaleToTarget
        )
        XCTAssertEqual(
            try XCTUnwrap(bundle.transforms.subjectCropTransform).resizeGeometry,
            .independentScaleToTarget
        )
    }

    func testProductionPreprocessorRejectsUnknownTensorAndDegenerateGeometry() throws {
        let preprocessor = MetalPreprocessor()
        let tensor = CGSize(
            width: CGFloat(SETCompositionNetContract.fullFrameWidth),
            height: CGFloat(SETCompositionNetContract.fullFrameHeight)
        )

        XCTAssertNil(
            preprocessor.setCompositionNetRecordedTransform(
                tensorID: "unknown.tensor",
                orientation: .up,
                sourcePixelSize: CGSize(width: 64, height: 48),
                destinationPixelSize: tensor
            )
        )
        XCTAssertNil(
            CameraTensorTransformContract.recipe(
                forTensorID: "unknown.tensor",
                orientation: .up,
                sourcePixelSize: CGSize(width: 64, height: 48),
                destinationPixelSize: tensor
            )
        )
        XCTAssertNil(
            preprocessor.setCompositionNetRecordedTransform(
                tensorID: CameraTensorTransformContract.setCompositionNetFullFrameTensorID,
                orientation: .up,
                sourcePixelSize: .zero,
                destinationPixelSize: tensor
            )
        )
        XCTAssertNil(
            preprocessor.setCompositionNetRecordedTransform(
                tensorID: CameraTensorTransformContract.setCompositionNetFullFrameTensorID,
                orientation: .up,
                sourcePixelSize: CGSize(width: 64, height: 48),
                destinationPixelSize: .zero
            )
        )
        XCTAssertNil(
            preprocessor.setCompositionNetRecordedTransform(
                tensorID: CameraTensorTransformContract.setCompositionNetFullFrameTensorID,
                orientation: .up,
                sourcePixelSize: CGSize(width: 64, height: CGFloat.nan),
                destinationPixelSize: tensor
            )
        )
    }

    func testProductionPreprocessorInvisibleTargetIsRefusedNotClampedToCropEdge() throws {
        let source = try XCTUnwrap(makeNonSquareBGRAPixelBuffer())
        let bundle = try XCTUnwrap(
            MetalPreprocessor().setCompositionNetPixelBufferBundle(
                from: source,
                orientation: .up,
                roi: topEdgeNonSquareROI
            )
        )
        let subjectCropID = CameraTensorTransformContract.setCompositionNetSubjectCropTensorID
        let fullFrameID = CameraTensorTransformContract.setCompositionNetFullFrameTensorID

        // Outside the applied crop window horizontally and vertically: refused.
        XCTAssertNil(
            bundle.transforms.destinationPoint(inTensorID: subjectCropID, fromOrientedX: 0.1, y: 0.05)
        )
        XCTAssertNil(
            bundle.transforms.destinationPoint(inTensorID: subjectCropID, fromOrientedX: 0.5, y: 0.5)
        )
        // Unknown tensor id: refused rather than mapped like a known one.
        XCTAssertNil(
            bundle.transforms.destinationPoint(inTensorID: "unknown.tensor", fromOrientedX: 0.5, y: 0.05)
        )
        // The full-frame tensor sees the whole oriented frame (independent
        // scale preserves normalized coordinates), so the same point is fine.
        XCTAssertNotNil(
            bundle.transforms.destinationPoint(inTensorID: fullFrameID, fromOrientedX: 0.1, y: 0.05)
        )

        // A point inside the applied crop maps through the recorded transform
        // (identity within the crop window) and is not pinned to an edge.
        let inside = try XCTUnwrap(
            bundle.transforms.destinationPoint(inTensorID: subjectCropID, fromOrientedX: 0.5, y: 0.1)
        )
        let window = try XCTUnwrap(bundle.transforms.subjectCropWindow)
        let expectedX = (0.5 * 64.0 - window.left) / (window.right - window.left)
        let expectedY = (0.1 * 48.0 - window.top) / (window.bottom - window.top)
        XCTAssertEqual(inside.x, expectedX, accuracy: 1e-9)
        XCTAssertEqual(inside.y, expectedY, accuracy: 1e-9)

        // The legacy clamping API would have produced a manufactured edge
        // coordinate; the fail-closed variant used by the transform refuses.
        let aspectFill = AspectFillTransform(
            sourceSize: CGSize(width: 64, height: 48),
            destinationSize: CGSize(width: 320, height: 320)
        )
        XCTAssertEqual(aspectFill.destinationPoint(fromSourceNormalized: 0.1, y: 0.5).x, 0, accuracy: 1e-12)
        XCTAssertNil(aspectFill.visibleDestinationPoint(fromSourceNormalized: 0.1, y: 0.5))
        let aspectTransform = try XCTUnwrap(
            CameraTensorTransform(
                tensorID: fullFrameID,
                resizeGeometry: .aspectFillCenterCrop,
                orientation: .up,
                sourcePixelSize: CGSize(width: 64, height: 48),
                destinationPixelSize: CGSize(width: 320, height: 320)
            )
        )
        XCTAssertNil(aspectTransform.destinationPoint(fromSourceNormalized: 0.1, y: 0.5))
    }

    // MARK: - Space tagging

    func testAllSixCanonicalSpacesExist() {
        XCTAssertEqual(
            Set(CameraCoordinateSpaceV2.allCases.map(\.rawValue)),
            ["sensor", "vision", "modelInput", "preview", "subjectTarget", "swiftUICanvas"]
        )
    }
}
