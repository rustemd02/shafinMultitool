import XCTest
@testable import shafinMultitool

/// Synthetic accepted presentations exercise UI projection and canonical priority.
/// They do not qualify perception, model confidence, or later-frame tracking.
final class PauseImagePlacementReviewProjectionTests: XCTestCase {
    func testProjectionUsesExactCurrentRegionAndRejectsCenteredStaleOrMissingInputs() throws {
        let critique = presentation()
        let selected = goal()
        let projected = try XCTUnwrap(project(proposal(selected), critique: critique))
        XCTAssertEqual(projected.goal, selected)
        XCTAssertEqual(projected.observedRegion, selected.observedRegion)
        XCTAssertNotEqual(projected.observedRegion, selected.destinationRegion,
                          "The marker describes the selected pixels, not an invented observed destination")
        XCTAssertEqual(projected.instructionKey, .cameraPlacementReframe)
        XCTAssertEqual(projected.labelKey, .cameraPlacementGoal)

        let edited = goal(
            ref: "user-roi-00000000-0000-4000-8000-000000000002",
            region: .init(x: 0.65, y: 0.1, width: 0.15, height: 0.3),
            source: .userRegion
        )
        let editedProjection = try XCTUnwrap(project(proposal(edited), critique: critique))
        XCTAssertEqual(editedProjection.goal, edited)
        XCTAssertEqual(editedProjection.observedRegion, edited.observedRegion)
        XCTAssertNotEqual(editedProjection, projected)

        let rejectedGoals = [
            goal(region: .init(x: 0.4, y: 0.4, width: 0.2, height: 0.2)),
            goal(snapshotID: "older-snapshot"),
            goal(frameID: "older-frame"),
            goal(ref: ""),
            goal(region: .init(x: 0.95, y: 0.2, width: 0.2, height: 0.4))
        ]
        for rejected in rejectedGoals {
            XCTAssertNil(project(proposal(rejected), critique: critique),
                         "Centered, stale, or invalid selections cannot create review guidance")
        }
        XCTAssertNil(project(nil, critique: critique))
        XCTAssertNil(project(proposal(selected), critique: nil))
        XCTAssertNil(project(proposal(selected, active: false), critique: critique))
        XCTAssertNil(project(proposal(selected), snapshotID: "replacement-snapshot", critique: critique))
        XCTAssertNil(project(proposal(selected), frameID: "replacement-frame", critique: critique))
        XCTAssertNil(project(proposal(selected), critique: presentation(frameID: "different-critique-frame")))
        XCTAssertEqual(critique.technicalQualityMeasurement, .unavailable(.notMeasured),
                       "A composition preference does not turn missing measurement into technical evidence")
    }

    func testStaleActiveProposalCannotDisplaceCurrentTechnicalOrActionPriority() throws {
        let selected = goal()
        let staleActive = proposal(selected)
        XCTAssertNotNil(project(staleActive, critique: presentation()))

        let technicalMeasurement = TechnicalQualityMeasurement.measured(.init(issues: [
            .init(type: .underexposure, actionType: .increaseExposure, confidence: 0.9,
                  severity: 0.9, isDominant: true)
        ]))
        let displayedTechnical = presentation(
            verdict: .mixed,
            summaryID: "technical_quality_underexposure",
            traceRootIDs: ["technical_quality_underexposure"],
            measurement: technicalMeasurement
        )
        XCTAssertTrue(displayedTechnical.actions.isEmpty,
                      "Displayed dominant technical advice reserves priority even without an executable row")
        let existingAction = PauseActionRow(
            actionId: "existing-camera-correction", actionType: .moveFrameLeft,
            semanticActionType: .shiftFrameLeft, priority: 1, confidence: 0.8,
            linkedIssueIds: ["existing-edge-issue"], expectedOutcome: "Reframe",
            targetRegion: selected.observedRegion, overlayHintId: nil, traceRefId: "existing-action-trace"
        )
        let actionable = presentation(
            verdict: .mixed, actions: [existingAction], measurement: .measured(.empty)
        )

        for accepted in [displayedTechnical, actionable] {
            XCTAssertTrue(staleActive.isActiveReviewSuggestion)
            XCTAssertNil(project(staleActive, critique: accepted),
                         "Current canonical priority must override the stale active flag")
        }
    }

    private func goal(
        snapshotID: String = "accepted-a",
        frameID: String = "frame-a",
        ref: String = "region-a",
        region: NormalizedRect = .init(x: 0.1, y: 0.2, width: 0.2, height: 0.4),
        source: CaptureImagePlacementGoal.Source = .observedRegion
    ) -> CaptureImagePlacementGoal {
        .init(snapshotID: snapshotID, frameID: frameID, entityRef: ref,
              observedRegion: region, source: source)
    }

    private func proposal(
        _ goal: CaptureImagePlacementGoal, active: Bool = true
    ) -> PauseImagePlacementProposal {
        // The active flag is deliberately caller-supplied to exercise stale
        // proposal rejection independently of the current canonical recheck.
        .init(goal: goal, intentRevision: 7, isActiveReviewSuggestion: active)
    }

    private func presentation(
        frameID: String = "frame-a",
        verdict: FrameVerdict = .good,
        summaryID: String = "good-fixture",
        actions: [PauseActionRow] = [],
        traceRootIDs: [String] = [],
        measurement: TechnicalQualityMeasurement = .unavailable(.notMeasured)
    ) -> PauseCritiquePresentation {
        .init(
            frameId: frameID, verdict: verdict, verdictConfidence: 0.8,
            summaryId: summaryID, shortVerdict: "Synthetic accepted presentation",
            whyGood: nil, whyProblematic: nil, strengths: [], issues: [], actions: actions,
            noChangeRationale: nil, assumptions: [], traceRootIds: traceRootIDs,
            fallbackUsed: false, technicalQualityMeasurement: measurement
        )
    }

    private func project(
        _ proposal: PauseImagePlacementProposal?,
        snapshotID: String = "accepted-a",
        frameID: String = "frame-a",
        critique: PauseCritiquePresentation?
    ) -> PauseImagePlacementReviewProjection? {
        .make(proposal: proposal, snapshotID: snapshotID, frameID: frameID, critique: critique)
    }
}
