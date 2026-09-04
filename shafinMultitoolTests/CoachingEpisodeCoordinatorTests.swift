//
//  CoachingEpisodeCoordinatorTests.swift
//  shafinMultitoolTests
//
//  M2-024 VerificationOwner: deterministic episode state-machine coverage.
//  The fixtures carry one typed subject binding and one capture provenance per
//  frame; no test uses elapsed time as a success signal.
//

import XCTest
@testable import shafinMultitool

final class CoachingEpisodeCoordinatorTests: XCTestCase {

    private let startDate = Date(timeIntervalSince1970: 10_000)
    private let identity = SubjectTrackIdentity(
        trackID: "track-subject-1",
        firstSeenFrameID: "f0",
        generation: 7
    )

    private func observation(
        id: String,
        x: Double = 0.20,
        capturedAt: Date,
        measuredAt: Date? = nil,
        evaluatedAt: Date? = nil,
        actionID: String = SemanticActionType.moveSubjectRight.rawValue,
        subjectIdentity: SubjectTrackIdentity? = nil,
        phase: SubjectTrackPhase = .active,
        generation: UInt64 = 7,
        orientation: CameraCoachOrientation = .portrait,
        lensID: String? = "wide",
        routeActive: Bool = true,
        backgrounded: Bool = false,
        sceneSignature: String? = "scene-a",
        stable: Bool = true,
        still: Bool = true,
        source: FeatureSourceID = .vision,
        metrics: UserMovementMetrics = UserMovementMetrics(),
        featureConfidence: Double = 0.92
    ) -> CoachingEpisodeObservation {
        let subjectIdentity = subjectIdentity ?? identity
        let region = NormalizedRect(x: x, y: 0.30, width: 0.20, height: 0.40)
        let measured = measuredAt ?? capturedAt
        let evaluated = evaluatedAt ?? capturedAt
        let binding = UserMovementSubjectBinding(
            identity: subjectIdentity,
            frameID: id,
            region: region,
            source: source,
            coordinateSpace: .subjectTarget,
            measuredAt: measured,
            confidence: 0.92
        )!
        let families = UserMovementActionFamily.allCases
        let evidence = UserMovementEvidence(
            capturedAt: capturedAt,
            evaluatedAt: evaluated,
            lensGeneration: generation,
            subjectTrackID: subjectIdentity.trackID,
            subjectBinding: binding,
            orientation: orientation,
            isCalibrated: true,
            calibrationVersion: "cal1",
            featureMeasuredAt: Dictionary(uniqueKeysWithValues: families.map { ($0, measured) }),
            featureConfidence: Dictionary(uniqueKeysWithValues: families.map { ($0, featureConfidence) }),
            sourceAvailability: Dictionary(uniqueKeysWithValues: families.map { ($0, true) })
        )
        let frame = UserMovementFrame(
            frameID: id,
            subjectRegion: region,
            meanLuma: 0.5,
            motionIsStill: still,
            metrics: metrics,
            evidence: evidence
        )
        let track = SubjectTrackState(
            identity: subjectIdentity,
            phase: phase,
            lastRegion: region,
            lastSeenFrameID: id,
            lostSinceFrameID: phase == .lost ? id : nil,
            missedFrames: phase == .lost ? 1 : 0,
            reconciliations: 0,
            redetectionDue: false
        )
        let lifecycle = SubjectTrackLifecycleContext(
            generation: generation,
            orientation: orientation,
            lensID: lensID,
            routeActive: routeActive,
            isAppBackgrounded: backgrounded,
            sceneSignature: sceneSignature
        )
        let advice = StabilizedAdvice(
            decision: .correct,
            actionID: actionID,
            frameID: id,
            targetX: 0.5,
            targetY: 0.5
        )
        return CoachingEpisodeObservation(
            frame: frame,
            stabilizedAdvice: advice,
            subjectTrack: track,
            lifecycle: lifecycle,
            isStable: stable
        )!
    }

    private func baselineObservation() -> CoachingEpisodeObservation {
        observation(id: "f0", capturedAt: startDate)
    }

    private func startedCoordinator(
        configuration: CoachingEpisodeConfiguration = .init()
    ) -> CoachingEpisodeCoordinator {
        var coordinator = CoachingEpisodeCoordinator(configuration: configuration)
        XCTAssertEqual(coordinator.begin(with: baselineObservation()).phase, .awaitingMovement)
        return coordinator
    }

    func testRelevantMovementThenFreshStableFramesReachesVerification() {
        var coordinator = startedCoordinator()

        XCTAssertEqual(
            coordinator.observe(observation(
                id: "f1",
                x: 0.26,
                capturedAt: startDate.addingTimeInterval(0.10)
            )).phase,
            .awaitingMovement
        )
        XCTAssertEqual(coordinator.state.movementFrames, 1)

        XCTAssertEqual(
            coordinator.observe(observation(
                id: "f2",
                x: 0.32,
                capturedAt: startDate.addingTimeInterval(0.20)
            )).phase,
            .collectingStableAfterFrames
        )
        XCTAssertEqual(coordinator.state.stableAfterFrames, 0,
                       "the movement frame is not also an after-frame")

        XCTAssertEqual(
            coordinator.observe(observation(
                id: "f3",
                x: 0.32,
                capturedAt: startDate.addingTimeInterval(0.30)
            )).phase,
            .collectingStableAfterFrames
        )
        XCTAssertEqual(coordinator.state.stableAfterFrames, 1)

        XCTAssertEqual(
            coordinator.observe(observation(
                id: "f4",
                x: 0.32,
                capturedAt: startDate.addingTimeInterval(0.40)
            )).phase,
            .readyForVerification
        )
        XCTAssertTrue(coordinator.isReadyForVerification)
        XCTAssertEqual(coordinator.state.baseline?.frameID, "f0")
        XCTAssertEqual(coordinator.state.baseline?.actionID, SemanticActionType.moveSubjectRight.rawValue)
        XCTAssertEqual(coordinator.state.baseline?.subjectIdentity, identity)
    }

    func testMismatchedTrackGeometryIsRejected() {
        let baseline = baselineObservation()
        let mismatchedTrack = SubjectTrackState(
            identity: baseline.subjectTrack.identity,
            phase: .active,
            lastRegion: NormalizedRect(x: 0.72, y: 0.30, width: 0.20, height: 0.40),
            lastSeenFrameID: baseline.frame.frameID,
            lostSinceFrameID: nil,
            missedFrames: 0,
            reconciliations: 0,
            redetectionDue: false
        )

        XCTAssertNil(
            CoachingEpisodeObservation(
                frame: baseline.frame,
                stabilizedAdvice: baseline.stabilizedAdvice,
                subjectTrack: mismatchedTrack,
                lifecycle: baseline.lifecycle,
                isStable: true
            ),
            "a track identity cannot be rebound to a different same-frame region"
        )
    }

    func testPersonAndDetrObjectBindingsRemainSourceSpecific() {
        let person = baselineObservation()
        XCTAssertEqual(person.frame.evidence?.subjectBinding?.source, .vision)
        var personCoordinator = CoachingEpisodeCoordinator()
        XCTAssertEqual(personCoordinator.begin(with: person).phase, .awaitingMovement)

        let objectAction = SemanticActionType.stepCloser.rawValue
        let initialArea = UserMovementMetrics(subjectAreaRatio: 0.10)
        let closerArea = UserMovementMetrics(subjectAreaRatio: 0.17)
        var objectCoordinator = CoachingEpisodeCoordinator()
        XCTAssertEqual(
            objectCoordinator.begin(with: observation(
                id: "object-0",
                capturedAt: startDate,
                actionID: objectAction,
                source: .detr,
                metrics: initialArea
            )).phase,
            .awaitingMovement
        )
        XCTAssertEqual(
            objectCoordinator.observe(observation(
                id: "object-1",
                capturedAt: startDate.addingTimeInterval(0.1),
                actionID: objectAction,
                source: .detr,
                metrics: closerArea
            )).movementFrames,
            1
        )
        XCTAssertEqual(
            objectCoordinator.observe(observation(
                id: "object-2",
                capturedAt: startDate.addingTimeInterval(0.2),
                actionID: objectAction,
                source: .detr,
                metrics: UserMovementMetrics(subjectAreaRatio: 0.24)
            )).phase,
            .collectingStableAfterFrames
        )
        XCTAssertEqual(
            objectCoordinator.observe(observation(
                id: "object-3",
                capturedAt: startDate.addingTimeInterval(0.3),
                actionID: objectAction,
                source: .detr,
                metrics: UserMovementMetrics(subjectAreaRatio: 0.24)
            )).phase,
            .collectingStableAfterFrames
        )
        XCTAssertEqual(
            objectCoordinator.observe(observation(
                id: "object-4",
                capturedAt: startDate.addingTimeInterval(0.4),
                actionID: objectAction,
                source: .detr,
                metrics: UserMovementMetrics(subjectAreaRatio: 0.24)
            )).phase,
            .readyForVerification
        )
        XCTAssertEqual(
            objectCoordinator.state.baseline?.subjectIdentity,
            identity
        )

        var mixedCoordinator = startedCoordinator()
        XCTAssertEqual(
            mixedCoordinator.observe(observation(
                id: "mixed-source",
                x: 0.26,
                capturedAt: startDate.addingTimeInterval(0.1),
                source: .detr
            )).cancellationReason,
            .subjectChanged,
            "a Vision baseline cannot accept a DETR frame even when identity and geometry look compatible"
        )
    }

    func testOnlyStabilitySafetyFamilyCanBeAdmittedWhileMoving() {
        let movingInput = CameraAdviceSafetyInput(
            lensGenerationKnown: true,
            subjectTrackLost: false,
            subjectAmbiguous: false,
            motionStateIsStill: false,
            exposureContradictionFree: false,
            refocusAdviceAdmitted: false,
            horizonAvailable: false,
            calibratedProbability: 0.8,
            minimumConfidence: CameraAdviceSafetyGate.defaultMinimumConfidence
        )

        XCTAssertEqual(
            CameraAdviceSafetyGate.evaluate(actionFamily: .stability, input: movingInput),
            .allow
        )
        XCTAssertEqual(
            CameraAdviceSafetyGate.evaluate(actionFamily: .composition, input: movingInput),
            .wait(reason: .motionNotStill)
        )
    }

    func testStabilityEpisodeCanBaselineWhileCameraIsUnstable() {
        let stabilityAction = TechnicalQualityActionType.stabilizeCamera.rawValue
        let lowStability = UserMovementMetrics(stabilityScore: 0.20, shakeLevel: 0.80)
        let improvingStability = UserMovementMetrics(stabilityScore: 0.80, shakeLevel: 0.20)
        let stable = UserMovementMetrics(stabilityScore: 0.90, shakeLevel: 0.10)
        var coordinator = CoachingEpisodeCoordinator()

        XCTAssertEqual(
            coordinator.begin(with: observation(
                id: "stability-0",
                capturedAt: startDate,
                actionID: stabilityAction,
                stable: false,
                still: false,
                metrics: lowStability
            )).phase,
            .awaitingMovement
        )
        _ = coordinator.observe(observation(
            id: "stability-1",
            capturedAt: startDate.addingTimeInterval(0.1),
            actionID: stabilityAction,
            stable: false,
            still: false,
            metrics: improvingStability
        ))
        XCTAssertEqual(coordinator.state.movementFrames, 1)
        XCTAssertEqual(
            coordinator.observe(observation(
                id: "stability-2",
                capturedAt: startDate.addingTimeInterval(0.2),
                actionID: stabilityAction,
                stable: false,
                still: false,
                metrics: stable
            )).phase,
            .collectingStableAfterFrames
        )
        XCTAssertEqual(
            coordinator.observe(observation(
                id: "stability-3",
                capturedAt: startDate.addingTimeInterval(0.3),
                actionID: stabilityAction,
                metrics: stable
            )).phase,
            .collectingStableAfterFrames
        )
        XCTAssertEqual(
            coordinator.observe(observation(
                id: "stability-4",
                capturedAt: startDate.addingTimeInterval(0.4),
                actionID: stabilityAction,
                metrics: stable
            )).phase,
            .readyForVerification
        )
    }

    func testNoOpOppositeUncertainAndStaleEvidenceNeverReady() {
        var noOp = startedCoordinator()
        for index in 1...4 {
            _ = noOp.observe(observation(
                id: "n\(index)",
                capturedAt: startDate.addingTimeInterval(Double(index) * 0.1)
            ))
        }
        XCTAssertNotEqual(noOp.phase, .readyForVerification)

        var opposite = startedCoordinator()
        _ = opposite.observe(observation(id: "o1", x: 0.14, capturedAt: startDate.addingTimeInterval(0.1)))
        _ = opposite.observe(observation(id: "o2", x: 0.08, capturedAt: startDate.addingTimeInterval(0.2)))
        XCTAssertNotEqual(opposite.phase, .readyForVerification)
        XCTAssertEqual(opposite.state.movementFrames, 0)

        var uncertain = startedCoordinator()
        _ = uncertain.observe(observation(
            id: "u1",
            x: 0.26,
            capturedAt: startDate.addingTimeInterval(0.1),
            featureConfidence: 0.3
        ))
        _ = uncertain.observe(observation(id: "u2", x: 0.32, capturedAt: startDate.addingTimeInterval(0.2)))
        XCTAssertNotEqual(uncertain.phase, .readyForVerification)

        var stale = startedCoordinator()
        _ = stale.observe(observation(
            id: "s1",
            x: 0.26,
            capturedAt: startDate.addingTimeInterval(1.0),
            measuredAt: startDate.addingTimeInterval(-1.0)
        ))
        _ = stale.observe(observation(
            id: "s2",
            x: 0.32,
            capturedAt: startDate.addingTimeInterval(1.1)
        ))
        XCTAssertNotEqual(stale.phase, .readyForVerification)
        XCTAssertEqual(stale.state.movementFrames, 0)

        var timeOnly = startedCoordinator(configuration: .init(
            requiredMovementFrames: 1,
            requiredStableAfterFrames: 1,
            maxDuration: 2
        ))
        XCTAssertEqual(
            timeOnly.expire(at: startDate.addingTimeInterval(2)).phase,
            .expired
        )
        XCTAssertNotEqual(timeOnly.phase, .readyForVerification)
    }

    func testInvalidatingLifecycleChangesCancelTheEpisode() {
        let cases: [(CoachingEpisodeCancellationReason, CoachingEpisodeObservation)] = [
            (
                .cameraGenerationChange,
                observation(
                    id: "g1",
                    capturedAt: startDate.addingTimeInterval(0.1),
                    subjectIdentity: SubjectTrackIdentity(
                        trackID: "track-new-generation",
                        firstSeenFrameID: "g1",
                        generation: 8
                    ),
                    generation: 8
                )
            ),
            (
                .lensChange,
                observation(id: "l1", capturedAt: startDate.addingTimeInterval(0.1), lensID: "tele")
            ),
            (
                .orientationChange,
                observation(
                    id: "r1",
                    capturedAt: startDate.addingTimeInterval(0.1),
                    orientation: .landscapeLeft
                )
            ),
            (
                .routeExit,
                observation(
                    id: "q1",
                    capturedAt: startDate.addingTimeInterval(0.1),
                    routeActive: false
                )
            ),
            (
                .background,
                observation(
                    id: "b1",
                    capturedAt: startDate.addingTimeInterval(0.1),
                    backgrounded: true
                )
            ),
            (
                .sceneCut,
                observation(
                    id: "c1",
                    capturedAt: startDate.addingTimeInterval(0.1),
                    sceneSignature: "scene-b"
                )
            )
        ]

        for (expectedReason, nextObservation) in cases {
            var coordinator = startedCoordinator()
            let state = coordinator.observe(nextObservation)
            XCTAssertEqual(state.phase, .cancelled, "(expectedReason) must cancel")
            XCTAssertEqual(state.cancellationReason, expectedReason)
            XCTAssertFalse(coordinator.isReadyForVerification)
        }
    }

    func testActionAndSubjectIdentityChangesCancelTheEpisode() {
        var actionChanged = startedCoordinator()
        XCTAssertEqual(
            actionChanged.observe(observation(
                id: "a1",
                capturedAt: startDate.addingTimeInterval(0.1),
                actionID: SemanticActionType.moveSubjectLeft.rawValue
            )).cancellationReason,
            .actionChanged
        )

        var subjectChanged = startedCoordinator()
        XCTAssertEqual(
            subjectChanged.observe(observation(
                id: "s1",
                capturedAt: startDate.addingTimeInterval(0.1),
                subjectIdentity: SubjectTrackIdentity(
                    trackID: "track-subject-2",
                    firstSeenFrameID: "s1",
                    generation: 7
                )
            )).cancellationReason,
            .subjectChanged
        )
    }

    func testDuplicateDoesNotAdvanceAndOutOfOrderCancels() {
        var duplicate = startedCoordinator()
        _ = duplicate.observe(observation(
            id: "d1",
            x: 0.26,
            capturedAt: startDate.addingTimeInterval(0.1)
        ))
        let beforeDuplicate = duplicate.state
        XCTAssertEqual(duplicate.observe(observation(
            id: "d1",
            x: 0.32,
            capturedAt: startDate.addingTimeInterval(0.2)
        )), beforeDuplicate)

        var outOfOrder = startedCoordinator()
        _ = outOfOrder.observe(observation(
            id: "o1",
            x: 0.26,
            capturedAt: startDate.addingTimeInterval(0.4)
        ))
        XCTAssertEqual(
            outOfOrder.observe(observation(
                id: "o0",
                x: 0.32,
                capturedAt: startDate.addingTimeInterval(0.3)
            )).cancellationReason,
            .outOfOrder
        )
        XCTAssertNotEqual(outOfOrder.phase, .readyForVerification)
    }

    func testExpiryRetryRequiresFreshBaselineAndToken() {
        var coordinator = startedCoordinator(configuration: .init(
            requiredMovementFrames: 1,
            requiredStableAfterFrames: 1,
            maxDuration: 1
        ))
        let firstToken = coordinator.episodeToken
        XCTAssertEqual(coordinator.expire(at: startDate.addingTimeInterval(1)).phase, .expired)

        coordinator.resetForRetry()
        XCTAssertEqual(coordinator.phase, .idle)
        _ = coordinator.begin(with: observation(
            id: "fresh-baseline",
            capturedAt: startDate.addingTimeInterval(2)
        ))
        XCTAssertNotEqual(coordinator.episodeToken, firstToken)
        XCTAssertEqual(coordinator.state.baseline?.frameID, "fresh-baseline")
        XCTAssertFalse(coordinator.isReadyForVerification)
    }
}
