import CoreGraphics
import ImageIO
import XCTest
@testable import shafinMultitool

final class PauseImagePlacementTests: XCTestCase {
    private func goal(x: Double = 0.1, ref: String = "region-a") -> CaptureImagePlacementGoal {
        .init(snapshotID: "accepted-a", frameID: "frame-a", entityRef: ref,
              observedRegion: .init(x: x, y: 0.2, width: 0.2, height: 0.4), source: .observedRegion)
    }

    private func presentation(technical: Bool = false, displaysTechnical: Bool = true,
                              intentionalStylePreserved: Bool = false) -> PauseCritiquePresentation {
        let identity = technical && displaysTechnical ? "technical_quality_underexposure" : "good-fixture"
        let measurement: TechnicalQualityMeasurement = technical ? .measured(.init(issues: [
            .init(type: .underexposure, actionType: .increaseExposure, confidence: 0.9,
                  severity: 0.9, isDominant: true)
        ])) : .unavailable(.notMeasured)
        return .init(
            frameId: "frame-a", verdict: technical ? .mixed : .good, verdictConfidence: 0.8,
            summaryId: identity, shortVerdict: "Synthetic accepted presentation",
            whyGood: nil, whyProblematic: nil, strengths: [], issues: [], actions: [],
            noChangeRationale: nil, assumptions: [], traceRootIds: technical ? [identity] : [],
            fallbackUsed: false, technicalQualityMeasurement: measurement,
            intentionalStylePreserved: intentionalStylePreserved
        )
    }

    func testExplicitCenterGoalPreservesFrozenStyleEncodingAndRevision() throws {
        let original = CaptureIntent.unknown().withStyles([.symmetry])
        let selected = original.withImagePlacementGoal(goal())
        XCTAssertEqual(selected.intentRevision, original.intentRevision + 1)
        XCTAssertEqual(selected.selection, .user)
        XCTAssertEqual(selected.subjectRefs, ["region-a"])
        XCTAssertEqual(try selected.intentFeatures(), try original.intentFeatures())
        XCTAssertEqual(selected.withImagePlacementGoal(goal()), selected)
        XCTAssertEqual(selected.withImagePlacementGoal(goal(ref: "region-b")).intentRevision,
                       selected.intentRevision + 1)
        XCTAssertNil(selected.withImagePlacementGoal(nil).imagePlacementGoal)
        XCTAssertTrue(selected.validate().isEmpty)
        XCTAssertEqual(selected.withStyles([.silhouette]).imagePlacementGoal, goal())
    }

    func testObservedSourceAndCenteredDestinationHaveDifferentMeaning() throws {
        let left = goal()
        XCTAssertNotEqual(left.observedRegion, left.destinationRegion)
        XCTAssertEqual(left.destinationRegion.x, 0.4, accuracy: 1e-12)
        XCTAssertEqual(left.destinationRegion.y, 0.3, accuracy: 1e-12)
        XCTAssertEqual(left.displacementX, 0.3, accuracy: 1e-12)
        XCTAssertEqual(left.displacementY, 0.1, accuracy: 1e-12)
        XCTAssertLessThan(goal(x: 0.7).displacementX, 0)
        let intent = CaptureIntent.unknown().withImagePlacementGoal(left)
        let planner = RecommendationPlanner()
        let proposal = try XCTUnwrap(planner.makeImagePlacementProposal(
            intent: intent, snapshotID: "accepted-a", frameID: "frame-a", presentation: presentation()
        ))
        XCTAssertEqual(proposal.goal, left)
        XCTAssertTrue(proposal.isActiveReviewSuggestion)
        XCTAssertFalse(try XCTUnwrap(planner.makeImagePlacementProposal(
            intent: intent, snapshotID: "accepted-a", frameID: "frame-a", presentation: presentation(technical: true)
        )).isActiveReviewSuggestion)
        XCTAssertTrue(try XCTUnwrap(planner.makeImagePlacementProposal(
            intent: intent, snapshotID: "accepted-a", frameID: "frame-a",
            presentation: presentation(technical: true, displaysTechnical: false)
        )).isActiveReviewSuggestion, "An undisplayed signal does not reserve command priority")
        XCTAssertTrue(try XCTUnwrap(planner.makeImagePlacementProposal(
            intent: intent, snapshotID: "accepted-a", frameID: "frame-a",
            presentation: presentation(technical: true, intentionalStylePreserved: true)
        )).isActiveReviewSuggestion, "Explicitly retained style is not displayed as a technical correction")
        XCTAssertNil(planner.makeImagePlacementProposal(
            intent: intent, snapshotID: "accepted-b", frameID: "frame-a", presentation: presentation()
        ))
        let centered = CaptureImagePlacementGoal(
            snapshotID: "accepted-a", frameID: "frame-a", entityRef: "region-a",
            observedRegion: .init(x: 0.4, y: 0.4, width: 0.2, height: 0.2), source: .observedRegion
        )
        XCTAssertTrue(centered.isNumericallyCentered)
        XCTAssertFalse(try XCTUnwrap(planner.makeImagePlacementProposal(
            intent: .unknown().withImagePlacementGoal(centered), snapshotID: "accepted-a",
            frameID: "frame-a", presentation: presentation()
        )).isActiveReviewSuggestion, "Decimal roundoff cannot create a reframing instruction")
        let beyondRoundoff = CaptureImagePlacementGoal(
            snapshotID: "accepted-a", frameID: "frame-a", entityRef: "region-a",
            observedRegion: .init(x: 0.400000001, y: 0.4, width: 0.2, height: 0.2), source: .observedRegion
        )
        XCTAssertFalse(beyondRoundoff.isNumericallyCentered,
                       "Roundoff tolerance is not a fitted visual success threshold")
    }

    func testSimilarRegionsRequireExactUniqueChoiceAndNeverNearestSibling() {
        let a = PauseImagePlacementCandidate(id: "a", region: goal().observedRegion)
        let b = PauseImagePlacementCandidate(id: "b", region: goal(x: 0.7).observedRegion)
        XCTAssertEqual(PauseImagePlacementCandidate.uniqueHit(x: 0.2, y: 0.4, in: [b, a]), a)
        XCTAssertEqual(PauseImagePlacementCandidate.uniqueHit(x: 0.8, y: 0.4, in: [a, b]), b)
        XCTAssertNil(PauseImagePlacementCandidate.uniqueHit(x: 0.5, y: 0.4, in: [a, b]))
        let overlapping = PauseImagePlacementCandidate(id: "c", region: a.region)
        XCTAssertNil(PauseImagePlacementCandidate.uniqueHit(x: 0.2, y: 0.4, in: [a, overlapping]))
        XCTAssertNil(PauseImagePlacementCandidate.uniqueHit(x: .nan, y: 0.4, in: [a]))
    }

    func testDuplicateReferencesAreRejectedWhileSameLabelsRemainDistinctRegions() {
        func entity(_ id: String, x: Double) -> VLMGroundedEntity {
            .init(entityRef: id, kind: .object, role: .foregroundObject,
                  region: goal(x: x).observedRegion, detectorLabel: "lamp", detectorConfidence: nil,
                  displayLabelCandidate: "object", displayLabelConfidence: 0)
        }
        let left = entity("left", x: 0.1)
        let right = entity("right", x: 0.7)
        XCTAssertEqual(PauseImagePlacementCandidate.admitted(from: [right, left]).map(\.id), ["right", "left"])
        XCTAssertEqual(PauseImagePlacementCandidate.admitted(from: [left, left, right]).map(\.id), ["right"])
    }

    func testAcceptedImageFitRoundTripsOrientationMirrorAndLetterboxing() throws {
        let source = CGSize(width: 1920, height: 1080)
        for orientation in [CGImagePropertyOrientation.up, .right, .down, .left] {
            for canvas in [CGSize(width: 390, height: 260), CGSize(width: 760, height: 260)] {
                for mirrored in [false, true] {
                    let region = goal().observedRegion
                    let rect = try XCTUnwrap(SETAcceptedFrameRegionMapper.map(
                        region, sourcePixelSize: source, orientation: orientation,
                        canvasSize: canvas, isMirrored: mirrored, contentMode: .fit
                    ))
                    let recovered = try XCTUnwrap(SETAcceptedFrameRegionMapper.unmap(
                        rect, sourcePixelSize: source, orientation: orientation,
                        canvasSize: canvas, isMirrored: mirrored, contentMode: .fit
                    ))
                    XCTAssertEqual(recovered.x, region.x, accuracy: 1e-12)
                    XCTAssertEqual(recovered.y, region.y, accuracy: 1e-12)
                    XCTAssertEqual(recovered.width, region.width, accuracy: 1e-12)
                    XCTAssertEqual(recovered.height, region.height, accuracy: 1e-12)
                }
            }
        }
        XCTAssertNil(SETAcceptedFrameRegionMapper.unmap(
            CGRect(x: 10, y: 1, width: 10, height: 10), sourcePixelSize: source, orientation: .up,
            canvasSize: CGSize(width: 390, height: 260), contentMode: .fit
        ))
        XCTAssertNil(SETAcceptedFrameRegionMapper.unmap(
            CGRect(x: -1, y: 30, width: 20, height: 20), sourcePixelSize: source, orientation: .up,
            canvasSize: CGSize(width: 390, height: 260), contentMode: .fit
        ))
        XCTAssertFalse(CaptureImagePlacementGoal(
            snapshotID: "a", frameID: "b", entityRef: "c",
            observedRegion: .init(x: 0.9, y: 0, width: 0.2, height: 0.2), source: .userRegion
        ).isValid)
    }

    func testAcceptedImageInverseRetainsExactTouchingEdgesWithoutClampingOutside() throws {
        let source = CGSize(width: 1920, height: 1080)
        let canvas = CGSize(width: 390, height: 260)
        let frame = try XCTUnwrap(SETAcceptedFrameRegionMapper.imageFrame(
            sourcePixelSize: source, orientation: .up, canvasSize: canvas, contentMode: .fit
        ))
        for mirrored in [false, true] {
            let rect = CGRect(x: frame.maxX - frame.width * 0.2,
                              y: frame.maxY - frame.height * 0.2,
                              width: frame.width * 0.2, height: frame.height * 0.2)
            let recovered = try XCTUnwrap(SETAcceptedFrameRegionMapper.unmap(
                rect, sourcePixelSize: source, orientation: .up,
                canvasSize: canvas, isMirrored: mirrored, contentMode: .fit
            ))
            XCTAssertEqual(recovered.y, 0)
            XCTAssertEqual(recovered.x, mirrored ? 0 : 0.8, accuracy: 1e-12)
            XCTAssertEqual(recovered.width, 0.2, accuracy: 1e-12)
            XCTAssertEqual(recovered.height, 0.2, accuracy: 1e-12)
            XCTAssertNil(SETAcceptedFrameRegionMapper.unmap(
                rect.offsetBy(dx: 0, dy: 0.000001), sourcePixelSize: source, orientation: .up,
                canvasSize: canvas, isMirrored: mirrored, contentMode: .fit
            ), "A real selection beyond the image edge still must fail")
        }
    }
}
