import XCTest
import CoreMedia
import CoreVideo
@testable import shafinMultitool

final class PauseSceneControlFactsTests: XCTestCase {
    private let frameID = "same-museum-or-controlled-still"
    private let region = NormalizedRect(x: 0.72, y: 0.22, width: 0.20, height: 0.22)

    func testPhysicalControlRequiresMatchingFrameAndIndependentExplicitCategory() {
        let objectOnly = PauseSceneControlFacts(frameID: frameID, objects: .allowed)
        XCTAssertTrue(objectOnly.permits(.moveObjectLeft, forFrameID: frameID))
        XCTAssertFalse(objectOnly.permits(.moveSubjectLeft, forFrameID: frameID))
        XCTAssertFalse(objectOnly.permits(.addFrontFillLight, forFrameID: frameID))
        XCTAssertFalse(objectOnly.permits(.moveObjectLeft, forFrameID: "new-scene"))
        let physical: [SemanticActionType] = [.moveObjectLeft, .moveObjectRight, .moveObjectForward,
            .moveObjectBack, .removeDistractingObject, .repositionPropForBalance,
            .rotateSubjectTowardLight, .moveSubjectLeft, .moveSubjectRight,
            .moveSubjectAwayFromBackground, .addFrontFillLight, .addBackgroundLight]
        for state in [PauseSceneControlFacts.State.unknown, .forbidden] {
            let facts = PauseSceneControlFacts(frameID: frameID, objects: state, participants: state, lighting: state)
            for action in physical { XCTAssertFalse(facts.permits(action, forFrameID: frameID), action.rawValue) }
            for action in [SemanticActionType.changeCameraAngle, .stepCloser, .levelHorizon,
                           .simplifyBackground, .removeBackgroundHotspot, .waitForBackgroundClearance, .keepCurrentSetup] {
                XCTAssertTrue(facts.permits(action, forFrameID: frameID), action.rawValue)
            }
        }
    }

    func testOrdinaryPlannerDoesNotInferObjectControlFromDetectedObject() throws {
        let (critique, plan) = fixture()
        let planner = SemanticTipPlanner()
        let allowed = planner.plan(input: SemanticTipPlannerInput(
            frameId: frameID, mode: .pause, critique: critique, recommendationPlan: plan,
            semantics: semantics(), sceneControlFacts: .init(frameID: frameID, objects: .allowed)))
        XCTAssertTrue(allowed.pauseExpandedTips.contains { $0.actionType == .moveObjectLeft },
                      "Same known geometry must exercise the existing physical object catalog")
        for facts in [PauseSceneControlFacts.unknown,
                      .init(frameID: frameID, objects: .forbidden),
                      .init(frameID: "old-frame", objects: .allowed)] {
            let result = planner.plan(input: SemanticTipPlannerInput(
                frameId: frameID, mode: .pause, critique: critique, recommendationPlan: plan,
                semantics: semantics(), sceneControlFacts: facts))
            XCTAssertFalse(result.pauseExpandedTips.contains { $0.actionType == .moveObjectLeft })
            XCTAssertFalse(result.allRankedCandidates.contains { $0.actionFrame == .moveObject })
            XCTAssertTrue(result.selectionTraceNotes.contains("pause_physical_action_requires_explicit_scene_control"))
        }
    }

    @MainActor
    func testActualOrdinaryPauseUsesSamePixelsWithDifferentExplicitControlFacts() throws {
        let (critique, plan) = fixture()
        let allowed = PauseSceneControlFacts(frameID: frameID, objects: .allowed)
        let tips = SemanticTipPlanner().plan(input: SemanticTipPlannerInput(
            frameId: frameID, mode: .pause, critique: critique, recommendationPlan: plan,
            semantics: semantics(), sceneControlFacts: allowed)).pauseExpandedTips.filter { $0.actionType == .moveObjectLeft }
        XCTAssertTrue(tips.contains { $0.actionType == .moveObjectLeft })
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let controlled = pipeline.testingMakePauseCritiquePresentation(
            critique: critique, plan: plan, semanticTips: tips, sceneControlFacts: allowed)
        XCTAssertTrue(controlled.actions.contains { $0.semanticActionType == .moveObjectLeft })
        for facts in [PauseSceneControlFacts.unknown, .init(frameID: frameID, objects: .forbidden)] {
            let museum = pipeline.testingMakePauseCritiquePresentation(
                critique: critique, plan: plan, semanticTips: tips, sceneControlFacts: facts)
            XCTAssertFalse(museum.actions.contains { $0.semanticActionType == .moveObjectLeft })
            XCTAssertTrue(museum.actions.contains { $0.semanticActionType == .shiftFrameRight },
                          "The existing local camera fallback must remain available")
        }
        let review = CameraReviewPresentation.make(critique: controlled, locale: Locale(identifier: "en"))
        XCTAssertFalse(review.hasActiveAction)
        XCTAssertFalse(review.opensLiveEpisode)
        XCTAssertNil(review.objectiveOutcomeCopyKey)
        XCTAssertTrue(review.alternativeGroups.flatMap(\.options).allSatisfy {
            $0.admissibility == .needsUserInput && !$0.isExecutableInLive && $0.qualificationRef == nil
        }, "Scene control is not measured completion or verifier admission")
    }

    @MainActor
    func testActualFallbackCannotReintroduceUnownedLightAndKeepsCameraAlternative() {
        let (critique, plan) = fixture(primary: .improveFrontLight, secondary: .changeAngle)
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let unknown = pipeline.testingMakePauseCritiquePresentation(critique: critique, plan: plan)
        XCTAssertEqual(unknown.actions.map(\.semanticActionType), [.changeCameraAngle])
        let allowed = pipeline.testingMakePauseCritiquePresentation(
            critique: critique, plan: plan,
            sceneControlFacts: .init(frameID: frameID, lighting: .allowed))
        XCTAssertTrue(allowed.actions.contains { $0.semanticActionType == .addFrontFillLight })
        XCTAssertTrue(allowed.actions.contains { $0.semanticActionType == .changeCameraAngle })
    }

    @MainActor
    func testActualContextualPauseCannotReintroducePhysicalObjectCommand() {
        let (critique, plan) = fixture(verdict: .good)
        let snapshot = clutterSnapshot()
        let signal = TechnicalQualitySignal(issues: [
            .init(type: .motionBlur, actionType: .stabilizeCamera, confidence: 0.9, severity: 0.9, isDominant: true)
        ])
        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        let controlled = pipeline.testingMakePauseCritiquePresentation(
            critique: critique, plan: plan, snapshot: snapshot, semantics: semantics(),
            technicalQualitySignal: signal,
            sceneControlFacts: .init(frameID: frameID, objects: .allowed))
        XCTAssertTrue(controlled.summaryId.hasPrefix("contextual_"),
                       "Exercise the real contextual branch, not a helper that repeats the policy")
        XCTAssertTrue(controlled.actions.contains { $0.semanticActionType == .removeDistractingObject })
        let museum = pipeline.testingMakePauseCritiquePresentation(
            critique: critique, plan: plan, snapshot: snapshot, semantics: semantics(), technicalQualitySignal: signal)
        XCTAssertEqual(museum.summaryId, controlled.summaryId)
        XCTAssertFalse(museum.actions.contains { $0.semanticActionType == .removeDistractingObject })
        // Existing contextual planning also offers timing and camera-angle
        // alternatives. Scene-control filtering must preserve those options.
        for action in [SemanticActionType.simplifyBackground, .waitForBackgroundClearance, .changeCameraAngle] {
            XCTAssertTrue(museum.actions.contains { $0.semanticActionType == action }, action.rawValue)
        }
    }

    @MainActor
    func testContextualTightEdgeUsesObservedSideAndAbstainsForBothMargins() {
        let left = NormalizedRect(x: 0.01, y: 0.015, width: 0.88, height: 0.97)
        let right = NormalizedRect(x: 1 - left.x - left.width, y: left.y,
                                   width: left.width, height: left.height)
        let cases: [(NormalizedRect, SemanticActionType?)] = [
            (left, .shiftFrameLeft),
            (right, .shiftFrameRight),
            (NormalizedRect(x: 0.06, y: left.y, width: left.width, height: left.height), nil)
        ]
        for (bounds, direction) in cases {
            let presentation = edgePresentation(region: bounds)
            XCTAssertEqual(presentation.summaryId, "contextual_tight_readable_edge_step_back")
            XCTAssertEqual(presentation.actions.map(\.semanticActionType),
                           [.stepBack] + (direction.map { [$0] } ?? []))
            XCTAssertTrue(presentation.actions.allSatisfy { $0.targetRegion == nil },
                          "A direction must not fabricate a destination or physical distance")
        }
        XCTAssertEqual(SemanticActionType.shiftFrameLeft.subjectDisplacementDirection, .right)
        XCTAssertEqual(SemanticActionType.shiftFrameRight.subjectDisplacementDirection, .left)
    }

    @MainActor
    func testContextualSmallEdgeMirrorsDirectionWithoutGrantingObjectControl() {
        let left = NormalizedRect(x: 0.02, y: 0.30, width: 0.15, height: 0.40)
        let right = NormalizedRect(x: 1 - left.x - left.width, y: left.y,
                                   width: left.width, height: left.height)
        for (bounds, direction) in [(left, SemanticActionType.shiftFrameLeft), (right, .shiftFrameRight)] {
            for allowObjects in [false, true] {
                let facts = PauseSceneControlFacts(frameID: frameID, objects: allowObjects ? .allowed : .unknown)
                let presentation = edgePresentation(region: bounds, small: true, facts: facts)
                XCTAssertEqual(presentation.summaryId, "contextual_small_edge_crop_step_back")
                XCTAssertEqual(presentation.actions.map(\.semanticActionType),
                               [.stepBack, direction] + (allowObjects ? [.removeDistractingObject] : []))
            }
        }
        let centered = edgePresentation(
            region: NormalizedRect(x: 0.425, y: 0.30, width: 0.15, height: 0.40), small: true
        )
        XCTAssertEqual(centered.summaryId, "contextual_small_edge_crop_step_back")
        XCTAssertEqual(centered.actions.map(\.semanticActionType), [.stepBack],
                       "A centered small object supplies no horizontal edge evidence")
    }

    @MainActor
    func testContextualEdgeWithholdsDirectionForMissingInvalidOrAmbiguousObservation() {
        let valid = NormalizedRect(x: 0.01, y: 0.015, width: 0.88, height: 0.97)
        let cases: [(String, NormalizedRect?, SubjectKind, AmbiguityType?, String?, Bool)] = [
            ("missing", nil, .object, nil, nil, true),
            ("outside-frame", .init(x: 0.90, y: 0.015, width: 0.88, height: 0.97), .object, nil, nil, true),
            ("degenerate", .init(x: 0.01, y: 0.015, width: 0, height: 0.97), .object, nil, nil, true),
            ("unknown-subject", valid, .unknown, nil, nil, true),
            ("competing-subjects", valid, .object, .multipleSubjectsSimilarConfidence, nil, true),
            ("weak-subject-evidence", valid, .object, .weakSignal, nil, true),
            ("other-frame", valid, .object, nil, "earlier-frame", true),
            ("source-unavailable", valid, .object, nil, nil, false)
        ]
        for (name, bounds, kind, ambiguity, semanticsFrameID, sourceAvailable) in cases {
            let presentation = edgePresentation(
                region: bounds, kind: kind, ambiguity: ambiguity,
                semanticsFrameID: semanticsFrameID, sourceAvailable: sourceAvailable
            )
            XCTAssertEqual(presentation.summaryId, "contextual_tight_readable_edge_step_back", name)
            XCTAssertEqual(presentation.actions.map(\.semanticActionType), [.stepBack], name)
        }
    }

    @MainActor
    func testContextualEdgeDirectionDoesNotOverrideEarlierTechnicalOnlyPriority() {
        let presentation = edgePresentation(
            region: NormalizedRect(x: 0.01, y: 0.015, width: 0.88, height: 0.97),
            technicalOnly: true
        )
        XCTAssertEqual(presentation.summaryId, "contextual_readable_softness_technical_only")
        XCTAssertTrue(presentation.actions.isEmpty)
        XCTAssertEqual(presentation.technicalQualityMeasurement.signal?.futureActionIds,
                       [TechnicalQualityActionType.stabilizeCamera.rawValue])
    }

    @MainActor
    private func edgePresentation(
        region: NormalizedRect?,
        small: Bool = false,
        kind: SubjectKind = .object,
        ambiguity: AmbiguityType? = nil,
        semanticsFrameID: String? = nil,
        sourceAvailable: Bool = true,
        technicalOnly: Bool = false,
        facts: PauseSceneControlFacts = .unknown
    ) -> PauseCritiquePresentation {
        let capturedAt = Date(timeIntervalSince1970: 200)
        let source = SourceState(available: sourceAvailable, freshnessMs: sourceAvailable ? 0 : nil,
                                 confidence: sourceAvailable ? 0.9 : nil)
        // Hold the scalar branch inputs fixed while negative controls vary only
        // the resolved bounds/source. No detector or model is executed here.
        let snapshot = FrameFeatureSnapshot(
            frameId: frameID, mode: .pause, capturedAt: capturedAt,
            sources: .init(vision: source, horizon: .init(available: true),
                           lighting: .init(available: true), detr: source, aesthetic: .init(available: true)),
            composition: .init(horizontalOffset: 0, verticalOffset: 0,
                               subjectAreaRatio: small ? 0.06 : 0.8536,
                               saliencyLeftRightBalance: 0, saliencyTopBottomBalance: 0),
            subjectSignals: .init(faceDetected: false, personDetected: false, personCount: 0,
                                  topObjectLabel: "chair", topObjectConfidence: 0.9, topObjectRegion: region,
                                  primaryCandidateRegion: region, primaryCandidateConfidence: 0.9),
            horizon: .init(angleDegrees: 0, confidence: 0.10),
            lighting: .init(exposureBiasHint: small ? 0 : -0.35, backlightIndex: 0, keyToFillRatio: nil),
            motion: .init(state: .still, shakeLevel: 0),
            aesthetics: .init(score: technicalOnly ? 0.39 : 0.40),
            objects: .init(totalCount: small ? 1 : 2, topKLabels: ["chair"]), technicalFlags: []
        )
        let semantics = SceneSemanticsReport(
            frameId: semanticsFrameID ?? frameID, mode: .pause, sceneType: .unknown, sceneTypeConfidence: 0,
            primarySubject: .init(kind: kind, label: "chair", region: region, confidence: 0.9),
            dominance: .init(hasClearFocus: true, focusCompetitionScore: 0.10, backgroundClutterScore: 0.10),
            readability: .init(subjectReadable: true, lookSpaceAdequate: nil,
                               edgePressureScore: 0.5, separationScore: 0.8),
            ambiguities: ambiguity.map { [.init(type: $0, note: "Explicit uncertainty control.", candidateIds: [])] } ?? [],
            assumptions: []
        )
        let signal = TechnicalQualitySignal(issues: [
            .init(type: technicalOnly ? .motionBlur : .underexposure,
                  actionType: technicalOnly ? .stabilizeCamera : .increaseExposure,
                  confidence: 0.9, severity: 0.9, isDominant: true)
        ])
        let critique = CritiqueReport(
            frameId: frameID, mode: .pause, verdict: .good, verdictConfidence: 0.8,
            strengths: [], issues: [], summary: .init(id: "direction-control", shortVerdict: "Control input."),
            traceRefs: [], fallbackUsed: false
        )
        let plan = RecommendationPlan(
            frameId: frameID, mode: .pause, inputVerdict: .good, primaryAction: nil,
            secondaryActions: [], deferredActions: [], noChangeRationale: nil, planConfidence: 0.8
        )
        let pipeline = AnalysisPipeline(reasoningProvider: nil, visualEvidenceProvider: nil, neuralEvidenceService: nil)
        let presentation = pipeline.testingMakePauseCritiquePresentation(
            critique: critique, plan: plan, snapshot: snapshot, semantics: semantics,
            technicalQualitySignal: signal,
            technicalEvidence: .init(frameID: frameID, capturedAt: capturedAt, measurement: .measured(signal)),
            sceneControlFacts: facts
        )
        XCTAssertEqual(presentation.technicalQualityMeasurement, .measured(signal),
                       "The directional repair must preserve the exact current technical measurement")
        return presentation
    }

    @MainActor
    func testPreparedReplayMatchesProductionTechnicalPriorityOverContextualTightEdge() throws {
        let result = try assembledPauseParity(dominant: true)
        XCTAssertEqual(result.direct.summaryId, "contextual_tight_readable_edge_step_back",
                       "The lower semantic stage must expose the competing contextual correction")
        XCTAssertEqual(result.production.summaryId, "technical_quality_underexposure")
        XCTAssertEqual(result.production.verdict, .mixed)
        XCTAssertTrue(result.production.actions.isEmpty,
                      "Unknown lighting control cannot admit the proposed physical fill-light action")
        XCTAssertEqual(result.replay.summaryId, result.production.summaryId,
                       "The old replay-only contextual gate incorrectly bypasses this technical priority")
        XCTAssertEqual(result.replay.verdict, result.production.verdict)
        XCTAssertEqual(result.replay.actions.map(\.semanticActionType),
                       result.production.actions.map(\.semanticActionType))
    }

    @MainActor
    func testPreparedReplayPreservesGoodWhenTechnicalIssueIsNotDominant() throws {
        let result = try assembledPauseParity(dominant: false)
        XCTAssertEqual(result.production.verdict, .good)
        XCTAssertEqual(result.production.summaryId, "replay-production-parity-summary")
        XCTAssertTrue(result.production.actions.isEmpty)
        XCTAssertFalse(result.production.noChangeRationale?.isEmpty ?? true)
        XCTAssertEqual(result.production.noChangeRationale, result.direct.noChangeRationale)
        XCTAssertEqual(result.replay.summaryId, result.production.summaryId)
        XCTAssertEqual(result.replay.verdict, result.production.verdict)
        XCTAssertEqual(result.replay.noChangeRationale, result.production.noChangeRationale)
        XCTAssertTrue(result.replay.actions.isEmpty,
                      "The existing good/no-dominant policy suppresses raw contextual correction")
    }

    @MainActor
    func testPreparedReplayPreservesPlannedEdgeAdviceWithoutDominantTechnicalIssue() throws {
        let result = try assembledPauseParity(dominant: false, hasSemanticEdgeIssue: true)
        XCTAssertEqual(result.production.verdict, .needsFix)
        XCTAssertEqual(result.production.summaryId, "replay-production-parity-summary")
        XCTAssertFalse(result.production.actions.isEmpty)
        XCTAssertFalse(result.production.actions.contains { $0.semanticActionType == .keepCurrentSetup })
        XCTAssertEqual(result.replay.summaryId, result.production.summaryId)
        XCTAssertEqual(result.replay.verdict, result.production.verdict)
        XCTAssertEqual(result.replay.actions.map(\.semanticActionType),
                       result.production.actions.map(\.semanticActionType))
        XCTAssertEqual(result.replay.actions.map(\.semanticActionType),
                       result.direct.actions.map(\.semanticActionType),
                       "An ineligible technical issue must retain the existing semantic presentation")
    }

    /// Reuses the tight-edge values above at a completed-analysis boundary.
    /// Generated pixels establish accepted-frame identity only; no perception runs.
    @MainActor
    private func assembledPauseParity(
        dominant: Bool, hasSemanticEdgeIssue: Bool = false
    ) throws -> (direct: PauseCritiquePresentation, replay: PauseCritiquePresentation,
                 production: PauseCritiquePresentation) {
        let capturedAt = Date(timeIntervalSince1970: 200)
        let bounds = NormalizedRect(x: 0.01, y: 0.015, width: 0.88, height: 0.97)
        let source = SourceState(available: true, freshnessMs: 0, confidence: 0.9)
        let snapshot = FrameFeatureSnapshot(
            frameId: frameID, mode: .pause, capturedAt: capturedAt,
            sources: .init(vision: source, horizon: .init(available: true),
                           lighting: .init(available: true), detr: source, aesthetic: .init(available: true)),
            composition: .init(horizontalOffset: 0, verticalOffset: 0, subjectAreaRatio: 0.8536,
                               saliencyLeftRightBalance: 0, saliencyTopBottomBalance: 0),
            subjectSignals: .init(faceDetected: false, personDetected: false, personCount: 0,
                                  topObjectLabel: "chair", topObjectConfidence: 0.9, topObjectRegion: bounds,
                                  primaryCandidateRegion: bounds, primaryCandidateConfidence: 0.9),
            horizon: .init(angleDegrees: 0, confidence: 0.10),
            lighting: .init(exposureBiasHint: -0.35, backlightIndex: 0, keyToFillRatio: nil),
            motion: .init(state: .still, shakeLevel: 0), aesthetics: .init(score: 0.40),
            objects: .init(totalCount: 2, topKLabels: ["chair"]), technicalFlags: []
        )
        let semantics = SceneSemanticsReport(
            frameId: frameID, mode: .pause, sceneType: .unknown, sceneTypeConfidence: 0,
            primarySubject: .init(kind: .object, label: "chair", region: bounds, confidence: 0.9),
            dominance: .init(hasClearFocus: true, focusCompetitionScore: 0.10, backgroundClutterScore: 0.10),
            readability: .init(subjectReadable: true, lookSpaceAdequate: nil,
                               edgePressureScore: 0.5, separationScore: 0.8),
            ambiguities: [], assumptions: []
        )
        let signal = TechnicalQualitySignal(issues: [
            .init(type: .underexposure, actionType: .increaseExposure,
                  confidence: 0.9, severity: 0.9, isDominant: dominant)
        ])
        let issue = FrameIssue(
            id: "parity-observed-edge", type: .subjectTooCloseToEdge, severity: 0.8, confidence: 0.9,
            rationale: "Controlled edge evidence.", evidence: [], affectedRegion: bounds,
            suggestedFixTypes: [.reframing]
        )
        let critique = CritiqueReport(
            frameId: frameID, mode: .pause, verdict: hasSemanticEdgeIssue ? .needsFix : .good,
            verdictConfidence: 0.8, strengths: [], issues: hasSemanticEdgeIssue ? [issue] : [],
            summary: .init(id: "replay-production-parity-summary", shortVerdict: "Control input."),
            traceRefs: [], fallbackUsed: false
        )
        let evidence = FrameTechnicalQualityEvidence(
            frameID: frameID, capturedAt: capturedAt, measurement: .measured(signal)
        )
        let plan = RecommendationPlanner().makePlan(snapshot: snapshot, critique: critique)
        if hasSemanticEdgeIssue {
            XCTAssertEqual(plan.primaryAction?.actionType, .changeAngle)
        } else {
            XCTAssertEqual(plan.noChangeRationale, "Control input.",
                           "Use the real planner's admissible good plan, not a handwritten actionless plan")
        }
        let pipeline = AnalysisPipeline(reasoningProvider: nil, visualEvidenceProvider: nil, neuralEvidenceService: nil)
        let tips = SemanticTipPlanner().plan(input: .init(
            frameId: frameID, mode: .pause, critique: critique, recommendationPlan: plan, semantics: semantics
        ))
        let direct = pipeline.testingMakePauseCritiquePresentation(
            critique: critique, plan: plan, semanticTips: tips.pauseExpandedTips,
            semanticFallbackUsed: tips.fallbackUsed, snapshot: snapshot, semantics: semantics,
            technicalQualitySignal: signal, technicalEvidence: evidence
        )
        let replay = try XCTUnwrap(pipeline.testingMakePreparedPauseReplayPresentation(
            snapshot: snapshot, semantics: semantics, critique: critique, technicalEvidence: evidence
        ))
        let store = LatestFrameEvidenceStore()
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32BGRA,
                                          nil, &buffer), kCVReturnSuccess)
        let pixels = try XCTUnwrap(buffer)
        XCTAssertEqual(CVPixelBufferLockBaseAddress(pixels, []), kCVReturnSuccess)
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels))
        memset(base, 128, CVPixelBufferGetBytesPerRow(pixels) * CVPixelBufferGetHeight(pixels))
        CVPixelBufferUnlockBaseAddress(pixels, [])
        XCTAssertTrue(store.publish(
            pixelBuffer: pixels, orientation: .up, sourceFrameId: frameID,
            capturedAt: capturedAt, isStable: true, lensID: "test-wide", lensGeneration: 3,
            samplePresentationTimestamp: CMTime(value: 1001, timescale: 600), sessionGeneration: 0
        ))
        let accepted = try XCTUnwrap(store.acceptCurrentSnapshot())
        pipeline.testingInstallCloudPauseReview(
            acceptedSnapshot: accepted, snapshot: snapshot, semantics: semantics, critique: critique, plan: plan,
            technicalSignal: signal, technicalEvidence: evidence
        )
        // Changing a local control fact forces the real accepted-pause refresh.
        // Initial fixture installation alone deliberately bypasses technical arbitration.
        let production = try XCTUnwrap(pipeline.updatePauseSceneControl(
            .init(frameID: frameID, objects: .forbidden), acceptedSnapshot: accepted
        ))
        for presentation in [direct, replay, production] {
            XCTAssertEqual(presentation.frameId, frameID)
            XCTAssertEqual(presentation.technicalQualityMeasurement, .measured(signal))
            XCTAssertFalse(presentation.actions.contains { $0.semanticActionType == .addFrontFillLight })
        }
        let record: [String: Any] = [
            "schema": "setos.prepared-pause-replay-parity.v1",
            "scope": "supplied_completed_analysis_no_perception",
            "frame_id": frameID, "technical_dominant": dominant,
            "semantic_edge_issue": hasSemanticEdgeIssue,
            "direct_summary": direct.summaryId, "replay_summary": replay.summaryId,
            "production_summary": production.summaryId,
            "replay_verdict": replay.verdict.rawValue, "production_verdict": production.verdict.rawValue,
            "replay_actions": replay.actions.map { $0.semanticActionType.rawValue },
            "production_actions": production.actions.map { $0.semanticActionType.rawValue }
        ]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "prepared-pause-parity-\(dominant)-\(hasSemanticEdgeIssue)"
        attachment.lifetime = .keepAlways
        add(attachment)
        return (direct, replay, production)
    }


    private func fixture(primary: ActionTypeV1 = .moveFrameRight, secondary: ActionTypeV1? = nil,
                         verdict: FrameVerdict = .needsFix) -> (CritiqueReport, RecommendationPlan) {
        let issue = FrameIssue(id: "observed-edge", type: .subjectTooCloseToEdge, severity: 0.8, confidence: 0.9,
            rationale: "Measured edge pressure.", evidence: [], affectedRegion: region, suggestedFixTypes: [.reframing])
        let critique = CritiqueReport(frameId: frameID, mode: .pause, verdict: verdict,
            verdictConfidence: 0.9, strengths: [], issues: [issue],
            summary: .init(id: "ordinary-pause", shortVerdict: "Measured composition."), traceRefs: [], fallbackUsed: false)
        func action(_ type: ActionTypeV1, priority: Int) -> RecommendationAction {
            .init(id: "plan-\(type.rawValue)", actionType: type, priority: priority,
                  targetRegion: region, linkedIssueIds: [issue.id], expectedOutcome: "Existing plan action.",
                  guardrail: .init(requiresStillCamera: true, minConfidence: 0.75, suppressWhenMoving: true), overlayHint: nil)
        }
        return (critique, .init(frameId: frameID, mode: .pause, inputVerdict: verdict,
            primaryAction: action(primary, priority: 1), secondaryActions: secondary.map { [action($0, priority: 2)] } ?? [],
            deferredActions: [], noChangeRationale: nil, planConfidence: 0.9))
    }

    private func semantics() -> SceneSemanticsReport {
        .init(frameId: frameID, mode: .pause, sceneType: .objectInsert, sceneTypeConfidence: 0.82,
              primarySubject: .init(kind: .object, label: "chair", region: region, confidence: 0.88),
              dominance: .init(hasClearFocus: false, focusCompetitionScore: 0.58, backgroundClutterScore: 0.52),
              readability: .init(subjectReadable: true, lookSpaceAdequate: true, edgePressureScore: 0.71, separationScore: 0.48),
              ambiguities: [], assumptions: [])
    }

    private func clutterSnapshot() -> FrameFeatureSnapshot {
        .init(frameId: frameID, mode: .pause, capturedAt: Date(timeIntervalSince1970: 100),
              sources: .init(vision: .init(available: true, freshnessMs: 0, confidence: 0.88),
                             horizon: .init(available: false), lighting: .init(available: true),
                             detr: .init(available: true), aesthetic: .init(available: true)),
              composition: .init(horizontalOffset: 0, verticalOffset: 0, subjectAreaRatio: 0.1,
                                 saliencyLeftRightBalance: 0, saliencyTopBottomBalance: 0),
              subjectSignals: .init(faceDetected: false, personDetected: false, personCount: 0,
                                    primaryCandidateRegion: region, primaryCandidateConfidence: 0.88),
              horizon: .init(angleDegrees: 0, confidence: 0),
              lighting: .init(exposureBiasHint: 0, backlightIndex: 0, keyToFillRatio: nil),
              motion: .init(state: .still, shakeLevel: 0), aesthetics: .init(score: 0.3),
              objects: .init(totalCount: 3, topKLabels: ["chair", "light", "plant"]), technicalFlags: [])
    }
}
