import CoreGraphics
import XCTest
@testable import shafinMultitool

final class CameraPauseMarkerPresentationTests: XCTestCase {
    private let frameID = "accepted-lamps"
    private let observed = NormalizedRect(x: 0.10, y: 0.30, width: 0.12, height: 0.25)
    private let destination = NormalizedRect(x: 0.45, y: 0.30, width: 0.12, height: 0.25)
    private let sibling = NormalizedRect(x: 0.75, y: 0.30, width: 0.12, height: 0.25)

    func testMarkerUsesLinkedObservationInsteadOfDestinationOrSameTypeSibling() {
        let review = critique(
            issues: [issue(id: "other-lamp", region: sibling), issue(region: observed)],
            actions: [action(target: destination)],
            projection: projection()
        )
        XCTAssertEqual(resolve(review), observed)
        XCTAssertNotEqual(resolve(review), destination)
        XCTAssertNotEqual(resolve(review), sibling)
        XCTAssertEqual(review.actions.first?.targetRegion, destination)
    }

    func testWrongAcceptedFrameAndStaleProjectionHideMarker() {
        XCTAssertNil(CameraPauseMarkerPresentation.observedRegion(
            in: critique(projection: projection()),
            acceptedSnapshotID: "next-frame", locale: Locale(identifier: "en")
        ))
        XCTAssertNil(resolve(critique(frame: "old-frame", projection: projection())))
        XCTAssertNil(resolve(critique(projection: projection(frame: "old-frame"))))
    }

    func testMultipleLinksDuplicateIDsAndUnprovenFirstActionHideMarker() {
        XCTAssertNil(resolve(critique(
            actions: [action(links: ["lamp-issue", "other-lamp"])], projection: projection()
        )))
        XCTAssertNil(resolve(critique(
            issues: [issue(region: observed), issue(region: sibling)], projection: projection()
        )))
        XCTAssertNil(resolve(critique(
            actions: [action(), action()], projection: projection()
        )))
        XCTAssertNil(resolve(critique(
            actions: [action(id: "unproven-first"), action()], projection: projection()
        )))
    }

    func testMismatchedTypedProjectionCannotBorrowAnotherIssueOrAction() {
        XCTAssertNil(resolve(critique(projection: projection(issueID: "other-lamp"))))
        XCTAssertNil(resolve(critique(projection: projection(issueType: .frameVisuallyOverloaded))))
        XCTAssertNil(resolve(critique(projection: projection(actionType: .moveFrameRight))))
        XCTAssertNil(resolve(critique(projection: projection(semanticType: .shiftFrameRight))))
    }

    func testUnknownObservedRegionDoesNotFallBackToDestinationOrSibling() {
        XCTAssertNil(resolve(critique(
            issues: [issue(region: nil), issue(id: "other-lamp", region: sibling)],
            actions: [action(target: destination)], projection: projection()
        )))
        XCTAssertNil(resolve(critique(projection: nil)))
    }

    func testNeuralOnlyOrSummaryOnlyProjectionCannotAuthorizeMarker() {
        for evidence in [
            EvidenceRef(source: .neuralEvidence, key: "subject.region", value: "observed"),
            EvidenceRef(source: .snapshot, key: "summary.subject", value: "observed")
        ] {
            XCTAssertNil(resolve(critique(projection: projection(evidence: [evidence]))))
        }
    }

    func testDegenerateAndOutOfBoundsObservedRegionsAreRejected() {
        for region in [
            NormalizedRect(x: 0.2, y: 0.3, width: 0, height: 0.2),
            NormalizedRect(x: 0.95, y: 0.3, width: 0.2, height: 0.2),
            NormalizedRect(x: 0.2, y: 0.95, width: 0.2, height: 0.2)
        ] {
            XCTAssertNil(resolve(critique(issues: [issue(region: region)], projection: projection())))
            XCTAssertNil(map(region))
        }
    }

    func testSmallEdgeObjectKeepsItsActualBoundsAndDoesNotEncloseNeighbour() throws {
        let frame = try XCTUnwrap(map(NormalizedRect(x: 0.01, y: 0.4, width: 0.04, height: 0.2)))
        XCTAssertEqual(frame.minX, 4, accuracy: 0.001)
        XCTAssertEqual(frame.minY, 320, accuracy: 0.001)
        XCTAssertEqual(frame.width, 16, accuracy: 0.001)
        XCTAssertEqual(frame.height, 160, accuracy: 0.001)
        XCTAssertFalse(frame.contains(CGPoint(x: 80, y: 400)))
    }

    func testOccludedObservationIsHiddenWithoutMovingOrShrinkingIt() {
        let region = NormalizedRect(x: 0.2, y: 0.8, width: 0.1, height: 0.1)
        XCTAssertNotNil(map(region))
        XCTAssertNil(map(region, area: CGRect(x: 0, y: 100, width: 400, height: 600)))
        XCTAssertNil(map(region, area: .zero))
    }

    func testAcceptedAspectFillOrientationAndMirrorUseExistingMapper() throws {
        let region = NormalizedRect(x: 0.18, y: 0.25, width: 0.22, height: 0.30)
        let portrait = try XCTUnwrap(CameraPauseMarkerPresentation.mappedFrame(
            for: region, sourcePixelSize: CGSize(width: 2, height: 4),
            orientation: .up, canvasSize: CGSize(width: 400, height: 900),
            isMirrored: false, unobscuredArea: CGRect(x: 0, y: 0, width: 400, height: 900)
        ))
        XCTAssertEqual(portrait.minX, 56, accuracy: 0.001)
        XCTAssertEqual(portrait.minY, 405, accuracy: 0.001)
        XCTAssertEqual(portrait.width, 99, accuracy: 0.001)
        XCTAssertEqual(portrait.height, 270, accuracy: 0.001)
        let landscape = try XCTUnwrap(CameraPauseMarkerPresentation.mappedFrame(
            for: region, sourcePixelSize: CGSize(width: 2, height: 4),
            orientation: .right, canvasSize: CGSize(width: 900, height: 400),
            isMirrored: true, unobscuredArea: CGRect(x: 0, y: 0, width: 900, height: 400)
        ))
        XCTAssertEqual(landscape.minX, 540, accuracy: 0.001)
        XCTAssertEqual(landscape.minY, 177.5, accuracy: 0.001)
        XCTAssertEqual(landscape.width, 198, accuracy: 0.001)
        XCTAssertEqual(landscape.height, 135, accuracy: 0.001)
    }

    private func map(_ region: NormalizedRect, area: CGRect? = nil) -> CGRect? {
        CameraPauseMarkerPresentation.mappedFrame(
            for: region, sourcePixelSize: CGSize(width: 400, height: 800),
            orientation: .up, canvasSize: CGSize(width: 400, height: 800),
            isMirrored: false, unobscuredArea: area ?? CGRect(x: 0, y: 0, width: 400, height: 800)
        )
    }

    private func resolve(_ review: PauseCritiquePresentation) -> NormalizedRect? {
        CameraPauseMarkerPresentation.observedRegion(
            in: review, acceptedSnapshotID: frameID, locale: Locale(identifier: "en")
        )
    }

    private func issue(id: String = "lamp-issue", region: NormalizedRect?) -> PauseIssueRow {
        PauseIssueRow(
            issueId: id, type: .subjectTooCloseToEdge, severity: 0.7, confidence: 0.8,
            rationale: "Observed edge pressure", affectedRegion: region,
            suggestedFixTypes: [.reframing], traceRefId: "trace-\(id)"
        )
    }

    private func action(
        id: String = "move-camera", links: [String] = ["lamp-issue"], target: NormalizedRect? = nil
    ) -> PauseActionRow {
        PauseActionRow(
            actionId: id, actionType: .moveFrameLeft, semanticActionType: .shiftFrameLeft,
            priority: 1, confidence: 0.8, linkedIssueIds: links, expectedOutcome: "Reframe",
            targetRegion: target, overlayHintId: nil, traceRefId: "trace-action"
        )
    }

    private func projection(
        frame: String = "accepted-lamps", issueID: String = "lamp-issue",
        issueType: IssueTypeV1 = .subjectTooCloseToEdge,
        actionType: ActionTypeV1 = .moveFrameLeft,
        semanticType: SemanticActionType = .shiftFrameLeft,
        evidence: [EvidenceRef] = [EvidenceRef(source: .snapshot, key: "subject.region", value: "observed")]
    ) -> CameraLinkedEvidenceProjection {
        CameraLinkedEvidenceProjection(
            frameID: frame, actionID: "move-camera", actionType: actionType,
            semanticActionType: semanticType, issueID: issueID, issueType: issueType, evidence: evidence
        )
    }

    private func critique(
        frame: String = "accepted-lamps", issues: [PauseIssueRow]? = nil,
        actions: [PauseActionRow]? = nil, projection: CameraLinkedEvidenceProjection?
    ) -> PauseCritiquePresentation {
        PauseCritiquePresentation(
            frameId: frame, verdict: .mixed, verdictConfidence: 0.8, summaryId: "summary-lamps",
            shortVerdict: "Reframe", whyGood: nil, whyProblematic: "Edge pressure", strengths: [],
            issues: issues ?? [issue(region: observed)], actions: actions ?? [action(target: destination)],
            noChangeRationale: nil, assumptions: [], traceRootIds: ["trace-lamps"], fallbackUsed: false,
            linkedEvidence: projection
        )
    }
}
