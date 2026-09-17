import XCTest
@testable import shafinMultitool

final class PauseSemanticEntityGroundingTests: XCTestCase {
    private let frameID = "pause-current"
    private let left = NormalizedRect(x: 0.08, y: 0.17, width: 0.18, height: 0.31)
    private let right = NormalizedRect(x: 0.64, y: 0.53, width: 0.21, height: 0.29)

    func testExactRefSelectsSameLabelSiblingAndPreservesVisionCoordinates() {
        let grounding = context([entity("lamp-left", region: left), entity("lamp-right", region: right)])
        let result = resolve(grounding, ref: "lamp-right")
        XCTAssertTrue(result.allowsAction)
        XCTAssertEqual(result.region, right)
        XCTAssertNotEqual(result.region, left)
        XCTAssertEqual(result.region?.y, 0.53,
                       "This owner retains Vision y-up coordinates; JPEG encoding owns the one vertical flip")
    }

    func testMissingRefCannotBorrowPlannedRegionForPhysicalMovement() {
        let grounding = context([entity("lamp-left", region: left)])
        for ref in [nil, "", "lamp-right"] as [String?] {
            let result = resolve(grounding, ref: ref)
            XCTAssertFalse(result.allowsAction)
            XCTAssertNil(result.region)
        }
    }

    func testDuplicateRefsCannotSilentlyChooseFirstEntity() {
        let grounding = context([entity("lamp", region: left), entity("lamp", region: right)])
        let result = resolve(grounding, ref: "lamp")
        XCTAssertFalse(result.allowsAction)
        XCTAssertNil(result.region)
    }

    func testMismatchedKindCannotAuthorizeObjectMovement() {
        let grounding = context([entity("target", kind: .person, region: left)])
        let result = resolve(grounding, ref: "target")
        XCTAssertFalse(result.allowsAction)
        XCTAssertNil(result.region)
    }

    func testDifferentFrameRejectsGlobalAndObjectActions() {
        let grounding = PauseSemanticEntityGrounding(frameID: "pause-old", entities: [entity("lamp", region: left)])
        XCTAssertFalse(resolve(grounding, ref: "lamp").allowsAction)
        let global = grounding.resolve(targetEntityRef: nil, targetEntityKind: .frame,
                                       actionType: .levelHorizon, actionFrame: .moveCamera,
                                       plannedSubjectRegion: left, expectedFrameID: frameID)
        XCTAssertFalse(global.allowsAction)
        XCTAssertNil(global.region)
    }

    func testDirectionalDecisionCannotBeRetargetedToSiblingWithoutReplanning() {
        let grounding = context([entity("lamp-left", region: left), entity("lamp-right", region: right)])
        for action in [SemanticActionType.moveObjectLeft, .moveObjectRight, .moveObjectForward,
                       .moveObjectBack, .shiftFrameLeft, .stepCloser] {
            let frame: SemanticActionFrame = action == .shiftFrameLeft || action == .stepCloser ? .moveCamera : .moveObject
            let wrongTarget = grounding.resolve(targetEntityRef: "lamp-right", targetEntityKind: .object,
                                                actionType: action, actionFrame: frame,
                                                plannedSubjectRegion: left, expectedFrameID: frameID)
            XCTAssertFalse(wrongTarget.allowsAction, action.rawValue)
            XCTAssertNil(wrongTarget.region, action.rawValue)
            let originalTarget = grounding.resolve(targetEntityRef: "lamp-left", targetEntityKind: .object,
                                                   actionType: action, actionFrame: frame,
                                                   plannedSubjectRegion: left, expectedFrameID: frameID)
            XCTAssertTrue(originalTarget.allowsAction, action.rawValue)
            XCTAssertEqual(originalTarget.region, left, action.rawValue)
        }
    }

    func testGlobalActionWithoutConcreteRefDoesNotInventTargetRegion() {
        let global = context([]).resolve(targetEntityRef: nil, targetEntityKind: .frame,
                                         actionType: .levelHorizon, actionFrame: .moveCamera,
                                         plannedSubjectRegion: left, expectedFrameID: frameID)
        XCTAssertTrue(global.allowsAction)
        XCTAssertNil(global.region)
    }

    func testDirectionalCameraActionsAlsoRequireOneValidMatchingTarget() {
        let cases: [(String, String?, [VLMGroundedEntity])] = [
            ("absent ref", nil, [entity("lamp", region: left)]),
            ("unknown ref", "other", [entity("lamp", region: left)]),
            ("duplicate ref", "lamp", [entity("lamp", region: left), entity("lamp", region: right)]),
            ("wrong kind", "lamp", [entity("lamp", kind: .person, region: left)]),
            ("missing region", "lamp", [entity("lamp", region: nil)])
        ]
        for action in [SemanticActionType.shiftFrameLeft, .shiftFrameRight, .shiftFrameUp,
                       .shiftFrameDown, .stepCloser, .stepBack] {
            for (name, ref, entities) in cases {
                let result = context(entities).resolve(
                    targetEntityRef: ref, targetEntityKind: .object,
                    actionType: action, actionFrame: .moveCamera,
                    plannedSubjectRegion: left, expectedFrameID: frameID
                )
                XCTAssertFalse(result.allowsAction, "\(action.rawValue): \(name)")
                XCTAssertNil(result.region, "\(action.rawValue): \(name)")
            }
        }
    }

    func testObjectPropTerminologyDoesNotChangeRegionIdentity() {
        let grounding = context([entity("lamp", region: left)])
        let result = grounding.resolve(targetEntityRef: "lamp", targetEntityKind: .prop,
                                       actionType: .removeDistractingObject, actionFrame: .moveObject,
                                       plannedSubjectRegion: right, expectedFrameID: frameID)
        XCTAssertTrue(result.allowsAction)
        XCTAssertEqual(result.region, left)
    }

    func testMissingAndOutOfBoundsRegionsFailClosed() {
        let regions: [NormalizedRect?] = [nil,
            NormalizedRect(x: 0.2, y: 0.3, width: 0, height: 0.2),
            NormalizedRect(x: 0.9, y: 0.3, width: 0.2, height: 0.2),
            NormalizedRect(x: 0.2, y: 0.9, width: 0.2, height: 0.2)]
        for region in regions {
            let result = resolve(context([entity("lamp", region: region)]), ref: "lamp")
            XCTAssertFalse(result.allowsAction)
            XCTAssertNil(result.region)
        }
    }

    @MainActor
    func testActualPausePresentationKeepsObservedSubjectAndDestinationSeparate() throws {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        for action in [ActionTypeV1.moveFrameLeft, .moveFrameRight] {
            for source in [left, NormalizedRect(x: 0.28, y: 0.37, width: 0.18, height: 0.31)] {
                let fixture = try directionalFixture(action: action, source: source, ref: "person-a")
                XCTAssertNotEqual(source, fixture.goal, "A destination is not the observed subject rectangle")
                let presentation = pipeline.testingMakePauseCritiquePresentation(
                    critique: fixture.critique, plan: fixture.plan, semanticTips: [fixture.tip],
                    semanticEntityGrounding: context([entity("person-a", kind: .person, region: source)])
                )
                let row = try XCTUnwrap(presentation.actions.first)
                XCTAssertEqual(presentation.actions.count, 1)
                XCTAssertNotEqual(row.actionId, fixture.plan.primaryAction?.id,
                                  "The accepted semantic row must execute this integration path")
                XCTAssertEqual(row.semanticActionType, fixture.tip.actionType)
                XCTAssertEqual(row.targetRegion, fixture.goal)
                XCTAssertNotEqual(row.targetRegion, source)
                XCTAssertNil(row.overlayHintId, "An old overlay identity cannot be inherited by the new row")
            }
        }
    }

    @MainActor
    func testActualPausePresentationCannotRetargetDirectionToSameLabelSibling() throws {
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        for action in [ActionTypeV1.moveFrameLeft, .moveFrameRight] {
            let fixture = try directionalFixture(action: action, source: left, ref: "person-b")
            let presentation = pipeline.testingMakePauseCritiquePresentation(
                critique: fixture.critique, plan: fixture.plan, semanticTips: [fixture.tip],
                semanticEntityGrounding: context([entity("person-a", kind: .person, region: left),
                                                   entity("person-b", kind: .person, region: right)])
            )
            XCTAssertFalse(presentation.actions.isEmpty, "The independent local plan may remain available")
            for row in presentation.actions {
                XCTAssertEqual(row.actionId, fixture.plan.primaryAction?.id,
                               "Rejected semantic targeting must not be presented as a selected-sibling correction")
                XCTAssertEqual(row.targetRegion, fixture.goal)
                XCTAssertNotEqual(row.targetRegion, right)
                XCTAssertNotEqual(row.targetRegion,
                                  fixture.tip.actionType.subjectTargetRegion(from: right, sourceSpace: .vision))
            }
        }
    }

    private func directionalFixture(action: ActionTypeV1, source: NormalizedRect, ref: String) throws
        -> (critique: CritiqueReport, plan: RecommendationPlan, tip: SemanticTipCandidate, goal: NormalizedRect) {
        let semantic: SemanticActionType = action == .moveFrameLeft ? .shiftFrameLeft : .shiftFrameRight
        let goal = try XCTUnwrap(semantic.subjectTargetRegion(from: source, sourceSpace: .vision))
        let traceID = "fixture-source-region-\(action.rawValue)"
        let issue = FrameIssue(id: "edge", type: .subjectTooCloseToEdge, severity: 0.8, confidence: 0.9,
                               rationale: "Measured subject edge pressure.",
                               evidence: [EvidenceRef(source: .snapshot, key: "subjectSignals.primaryCandidateRegion", value: "measured")],
                               affectedRegion: source, suggestedFixTypes: [.reframing])
        let critique = CritiqueReport(frameId: frameID, mode: .pause, verdict: .needsFix,
                                      verdictConfidence: 0.9, strengths: [], issues: [issue],
                                      summary: CritiqueSummary(id: "summary", shortVerdict: "Subject needs space."),
                                      traceRefs: [traceID], fallbackUsed: false)
        let recommendation = RecommendationAction(
            id: "local-camera-direction", actionType: action, priority: 1, targetRegion: goal,
            linkedIssueIds: [issue.id], expectedOutcome: "Reframe measured subject.",
            guardrail: ActionGuardrail(requiresStillCamera: true, minConfidence: 0.75, suppressWhenMoving: true),
            overlayHint: OverlayHint(id: "local-goal-overlay", kind: .arrow, targetRegion: goal,
                                     direction: action == .moveFrameLeft ? .left : .right)
        )
        let plan = RecommendationPlan(frameId: frameID, mode: .pause, inputVerdict: .needsFix,
                                       primaryAction: recommendation, secondaryActions: [], deferredActions: [],
                                       noChangeRationale: nil, planConfidence: 0.9)
        let tip = SemanticTipCandidate(
            tipType: action == .moveFrameLeft ? .moveSubjectOffLeftEdge : .moveSubjectOffRightEdge,
            actionType: semantic, actionFrame: .moveCamera,
            direction: action == .moveFrameLeft ? .left : .right,
            problemType: .subjectEdgePressure, strengthType: nil,
            targetEntityKind: .person, targetEntityRole: .primarySubject,
            targetEntityRef: ref, targetEntityGroundingConfidence: 0.9, targetEntityDisplayLabel: "герой",
            secondaryEntityRef: nil, secondaryEntityGroundingConfidence: nil, secondaryEntityDisplayLabel: nil,
            primaryActionId: recommendation.id, linkedActionIds: [recommendation.id], linkedIssueIds: [issue.id],
            linkedStrengthIds: [], linkedTraceIds: [traceID], summaryId: nil, supportedModes: [.pause],
            priorityBand: .primaryCorrective, liveText: "Reframe the subject.", pauseText: "Reframe the subject.",
            fallbackBehavior: .degradeToGenericActionCopy
        )
        XCTAssertTrue(tip.validate().isEmpty, tip.validate().joined(separator: "; "))
        return (critique, plan, tip, goal)
    }

    private func context(_ entities: [VLMGroundedEntity]) -> PauseSemanticEntityGrounding {
        PauseSemanticEntityGrounding(frameID: frameID, entities: entities)
    }

    private func resolve(_ grounding: PauseSemanticEntityGrounding, ref: String?) -> PauseSemanticEntityGrounding.Resolution {
        grounding.resolve(targetEntityRef: ref, targetEntityKind: .object,
                          actionType: .removeDistractingObject, actionFrame: .moveObject,
                          plannedSubjectRegion: left, expectedFrameID: frameID)
    }

    private func entity(_ ref: String, kind: VLMEntityKind = .object, region: NormalizedRect?) -> VLMGroundedEntity {
        VLMGroundedEntity(entityRef: ref, kind: kind, role: .foregroundObject,
                          region: region, detectorLabel: "light", detectorConfidence: nil,
                          displayLabelCandidate: "объект", displayLabelConfidence: 0)
    }
}
