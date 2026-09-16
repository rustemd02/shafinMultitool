//
//  UserMovementObserverTests.swift
//  shafinMultitoolTests
//
//  M2-023 VerificationOwner: synthetic feature trajectories for every
//  supported action — relevant/no-op/opposite/uncertain classification and
//  the tracker's streak semantics.
//

import XCTest
import CoreMedia
@testable import shafinMultitool

final class UserMovementObserverTests: XCTestCase {

    private let evidenceTime = Date(timeIntervalSince1970: 1_000)

    private func productionFrame(id: String,
                                 x: Double = 0.2,
                                 y: Double = 0.4,
                                 meanLuma: Double = 0.5,
                                 still: Bool = true,
                                 metrics: UserMovementMetrics = UserMovementMetrics(),
                                 trackID: String? = "subject-1",
                                 orientation: CameraCoachOrientation = .portrait,
                                 capturedAt: Date? = nil,
                                 measuredAt: Date? = nil,
                                 evaluatedAt: Date? = nil,
                                 confidence: Double = 0.9,
                                 bindingConfidence: Double = 0.9,
                                 available: Bool = true,
                                 source: FeatureSourceID = .vision,
                                 calibrated: Bool = true) -> UserMovementFrame {
        let captured = capturedAt ?? evidenceTime
        let measured = measuredAt ?? captured
        let evaluated = evaluatedAt ?? captured
        let region = NormalizedRect(x: x, y: y, width: 0.2, height: 0.4)
        let binding = trackID.flatMap {
            UserMovementSubjectBinding(
                identity: SubjectTrackIdentity(
                    trackID: $0,
                    firstSeenFrameID: "seed",
                    generation: 1
                ),
                frameID: id,
                region: region,
                source: source,
                coordinateSpace: .subjectTarget,
                measuredAt: measured,
                confidence: bindingConfidence
            )
        }
        let families = UserMovementActionFamily.allCases
        let evidence = UserMovementEvidence(
            capturedAt: captured,
            evaluatedAt: evaluated,
            lensGeneration: 1,
            subjectTrackID: trackID,
            subjectBinding: binding,
            orientation: orientation,
            isCalibrated: calibrated,
            featureMeasuredAt: Dictionary(uniqueKeysWithValues: families.map { ($0, measured) }),
            featureConfidence: Dictionary(uniqueKeysWithValues: families.map { ($0, confidence) }),
            sourceAvailability: Dictionary(uniqueKeysWithValues: families.map { ($0, available) })
        )
        return UserMovementFrame(
            frameID: id,
            subjectRegion: region,
            meanLuma: meanLuma,
            motionIsStill: still,
            metrics: metrics,
            evidence: evidence
        )
    }

    private func makePixelBuffer() -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, 4, 4, kCVPixelFormatType_32BGRA, nil, &buffer
        )
        precondition(status == kCVReturnSuccess, "fixture pixel buffer creation failed")
        return buffer!
    }

    private func adapterEnvelope(
        frameID: String,
        capturedAt: Date = Date(timeIntervalSince1970: 1_000),
        orientation: CGImagePropertyOrientation = .up,
        lensGeneration: UInt64 = 7,
        timestamps: [FeatureSourceID: Date]? = nil
    ) -> AcceptedFrameEnvelope {
        let sourceTimestamps = timestamps ?? [
            .vision: capturedAt,
            .horizon: capturedAt,
            .lighting: capturedAt,
            .detr: capturedAt,
            .aesthetic: capturedAt
        ]
        return AcceptedFrameEnvelope(
            frameID: frameID,
            capturedAt: capturedAt,
            orientation: orientation,
            lensGeneration: lensGeneration,
            pixelBuffer: makePixelBuffer(),
            featureSourceTimestamps: sourceTimestamps
        )
    }

    private func adapterSnapshot(
        frameID: String,
        capturedAt: Date = Date(timeIntervalSince1970: 1_000),
        primaryRegion: NormalizedRect,
        visionAvailable: Bool = true,
        visionConfidence: Double? = 0.9,
        detrAvailable: Bool = false,
        detrConfidence: Double? = nil,
        primaryCandidateSource: FeatureSourceID? = .vision,
        horizonAvailable: Bool = true,
        horizonConfidence: Double? = 0.9,
        lightingAvailable: Bool = true,
        lightingConfidence: Double? = 0.9,
        horizonAngle: Double = 0,
        exposureBias: Double = 0,
        subjectLighting: FrameFeatureSnapshot.LightingFeatures.SubjectLightingMetrics? = nil,
        motionState: CameraAnalysisMotionState = .still,
        shakeLevel: Double = 0.1
    ) -> FrameFeatureSnapshot {
        FrameFeatureSnapshot(
            frameId: frameID,
            mode: .live,
            capturedAt: capturedAt,
            sources: .init(
                vision: .init(available: visionAvailable,
                              freshnessMs: visionAvailable ? 40 : nil,
                              confidence: visionConfidence),
                horizon: .init(available: horizonAvailable,
                               freshnessMs: horizonAvailable ? 40 : nil,
                               confidence: horizonConfidence),
                lighting: .init(available: lightingAvailable,
                                freshnessMs: lightingAvailable ? 40 : nil,
                                confidence: lightingConfidence),
                detr: .init(available: detrAvailable,
                            freshnessMs: detrAvailable ? 40 : nil,
                            confidence: detrConfidence),
                aesthetic: .init(available: false)
            ),
            composition: .init(
                horizontalOffset: 0,
                verticalOffset: 0,
                subjectAreaRatio: primaryRegion.width * primaryRegion.height,
                saliencyLeftRightBalance: 0,
                saliencyTopBottomBalance: 0
            ),
            subjectSignals: .init(
                faceDetected: false,
                personDetected: false,
                personCount: 0,
                primaryCandidateRegion: primaryRegion,
                primaryCandidateConfidence: 0.9,
                primaryCandidateSource: primaryCandidateSource
            ),
            horizon: .init(angleDegrees: horizonAngle, confidence: horizonConfidence ?? 0),
            lighting: .init(
                exposureBiasHint: exposureBias,
                backlightIndex: 0,
                keyToFillRatio: nil,
                subjectLighting: subjectLighting
            ),
            motion: .init(state: motionState, shakeLevel: shakeLevel),
            aesthetics: .init(),
            objects: .init(totalCount: 0, topKLabels: []),
            technicalFlags: []
        )
    }

    private func adapterBinding(
        frameID: String,
        region: NormalizedRect,
        source: FeatureSourceID = .vision,
        coordinateSpace: CameraCoordinateSpaceV2 = .vision,
        measuredAt: Date = Date(timeIntervalSince1970: 1_000),
        confidence: Double = 0.9,
        trackID: String = "subject-1",
        generation: UInt64 = 7
    ) -> UserMovementSubjectBinding {
        guard let binding = UserMovementSubjectBinding(
            identity: SubjectTrackIdentity(
                trackID: trackID,
                firstSeenFrameID: "seed",
                generation: generation
            ),
            frameID: frameID,
            region: region,
            source: source,
            coordinateSpace: coordinateSpace,
            measuredAt: measuredAt,
            confidence: confidence
        ) else {
            fatalError("invalid movement binding fixture")
        }
        return binding
    }

    private func adapterFrame(
        snapshot: FrameFeatureSnapshot,
        envelope: AcceptedFrameEnvelope,
        binding: UserMovementSubjectBinding?,
        evaluatedAt: Date? = nil,
        calibrated: Bool = true,
        orientation: CameraCoachOrientation = .landscapeRight
    ) -> UserMovementFrame? {
        UserMovementFrame(
            snapshot: snapshot,
            envelope: envelope,
            subjectBinding: binding,
            evaluatedAt: evaluatedAt,
            isCalibrated: calibrated,
            orientation: orientation
        )
    }

    private func unboundFrame(id: String,
                              metrics: UserMovementMetrics,
                              still: Bool = true) -> UserMovementFrame {
        let source = productionFrame(id: id,
                                     still: still,
                                     metrics: metrics,
                                     trackID: nil)
        return UserMovementFrame(
            frameID: source.frameID,
            subjectRegion: nil,
            meanLuma: source.meanLuma,
            motionIsStill: source.motionIsStill,
            metrics: source.metrics,
            evidence: source.evidence
        )
    }

    private func frame(x: Double, luma: Double = 0.5,
                       still: Bool = true,
                       id: String = "f") -> UserMovementFrame {
        UserMovementFrame(
            frameID: id,
            subjectRegion: NormalizedRect(x: x, y: 0.4, width: 0.2, height: 0.4),
            meanLuma: luma,
            motionIsStill: still
        )
    }

    // MARK: - Directional movement

    func testRelevantDisplacementDetected() {
        // Advice: move subject right (+x). Subject moves right by 0.08.
        let verdict = UserMovementObserver.observe(
            previous: frame(x: 0.2, id: "a"),
            current: frame(x: 0.28, id: "b"),
            desiredDisplacement: (dx: 1, dy: 0)
        )
        XCTAssertEqual(verdict, .relevant)
    }

    func testOppositeDisplacementDetected() {
        // Advice: move right; subject moves left.
        let verdict = UserMovementObserver.observe(
            previous: frame(x: 0.28, id: "a"),
            current: frame(x: 0.2, id: "b"),
            desiredDisplacement: (dx: 1, dy: 0)
        )
        XCTAssertEqual(verdict, .opposite)
    }

    func testNoOpBelowDeadband() {
        // 0.01 displacement: below the 0.03 deadband.
        let verdict = UserMovementObserver.observe(
            previous: frame(x: 0.2, id: "a"),
            current: frame(x: 0.21, id: "b"),
            desiredDisplacement: (dx: 1, dy: 0)
        )
        XCTAssertEqual(verdict, .noOp)
    }

    func testVerticalDisplacementJudgedAgainstVerticalAdvice() {
        let verdict = UserMovementObserver.observe(
            previous: frame(x: 0.2, id: "a"),
            current: frame(x: 0.2, id: "b"),
            desiredDisplacement: (dx: 0, dy: 1)
        )
        // Same x, same y → no vertical movement.
        XCTAssertEqual(verdict, .noOp)
    }

    func testVerticalRelevantMovement() {
        // Advice: move subject down (+y). Frame y moves 0.4 → 0.5.
        let previous = UserMovementFrame(
            frameID: "a",
            subjectRegion: NormalizedRect(x: 0.4, y: 0.2, width: 0.2, height: 0.4),
            meanLuma: 0.5, motionIsStill: true
        )
        let current = UserMovementFrame(
            frameID: "b",
            subjectRegion: NormalizedRect(x: 0.4, y: 0.35, width: 0.2, height: 0.4),
            meanLuma: 0.5, motionIsStill: true
        )
        let verdict = UserMovementObserver.observe(
            previous: previous,
            current: current,
            desiredDisplacement: (dx: 0, dy: 1)
        )
        XCTAssertEqual(verdict, .relevant)
    }

    // MARK: - Lighting-relevant actions

    func testLumaChangeCountsAsRelevantForLightActions() {
        let verdict = UserMovementObserver.observe(
            previous: frame(x: 0.2, luma: 0.3, id: "a"),
            current: frame(x: 0.2, luma: 0.6, id: "b"),
            desiredDisplacement: (dx: 0, dy: 0) // zero vector = lighting/depth family
        )
        XCTAssertEqual(verdict, .relevant)
    }

    func testSmallLumaChangeIsNoOp() {
        let verdict = UserMovementObserver.observe(
            previous: frame(x: 0.2, luma: 0.5, id: "a"),
            current: frame(x: 0.2, luma: 0.55, id: "b"),
            desiredDisplacement: (dx: 0, dy: 0)
        )
        XCTAssertEqual(verdict, .noOp)
    }

    // MARK: - WAIT semantics: camera motion

    func testCameraMotionMakesMovementUncertain() {
        let verdict = UserMovementObserver.observe(
            previous: frame(x: 0.2, id: "a"),
            current: frame(x: 0.35, still: false, id: "b"),
            desiredDisplacement: (dx: 1, dy: 0)
        )
        guard case let .uncertain(reason) = verdict else {
            return XCTFail("expected uncertain, got \(verdict)")
        }
        XCTAssertEqual(reason, "camera_motion")
    }

    func testMissingSubjectIsUncertain() {
        let previous = UserMovementFrame(
            frameID: "a",
            subjectRegion: NormalizedRect(x: 0.2, y: 0.4, width: 0.2, height: 0.4),
            meanLuma: 0.5, motionIsStill: true
        )
        let current = UserMovementFrame(
            frameID: "b", subjectRegion: nil, meanLuma: 0.5, motionIsStill: true
        )
        let verdict = UserMovementObserver.observe(
            previous: previous, current: current,
            desiredDisplacement: (dx: 1, dy: 0)
        )
        guard case .uncertain(reason: "subject_missing") = verdict else {
            return XCTFail("expected subject_missing, got \(verdict)")
        }
    }

    // MARK: - Action-aware production trajectories

    func testActionAwareTrajectoriesCoverAllSupportedFamilies() {
        assertTrajectory(
            actionID: SemanticActionType.moveSubjectRight.rawValue,
            previous: productionFrame(id: "subject-a", x: 0.2),
            relevant: productionFrame(id: "subject-b", x: 0.28),
            opposite: productionFrame(id: "subject-c", x: 0.12),
            noOp: productionFrame(id: "subject-d", x: 0.21)
        )
        assertTrajectory(
            actionID: SemanticActionType.stepCloser.rawValue,
            previous: productionFrame(id: "scale-a", metrics: UserMovementMetrics(subjectAreaRatio: 0.10)),
            relevant: productionFrame(id: "scale-b", metrics: UserMovementMetrics(subjectAreaRatio: 0.16)),
            opposite: productionFrame(id: "scale-c", metrics: UserMovementMetrics(subjectAreaRatio: 0.04)),
            noOp: productionFrame(id: "scale-d", metrics: UserMovementMetrics(subjectAreaRatio: 0.12))
        )
        assertTrajectory(
            actionID: SemanticActionType.levelHorizon.rawValue,
            previous: productionFrame(id: "horizon-a", metrics: UserMovementMetrics(horizonAngleDegrees: 8)),
            relevant: productionFrame(id: "horizon-b", metrics: UserMovementMetrics(horizonAngleDegrees: 5)),
            opposite: productionFrame(id: "horizon-c", metrics: UserMovementMetrics(horizonAngleDegrees: 12)),
            noOp: productionFrame(id: "horizon-d", metrics: UserMovementMetrics(horizonAngleDegrees: 7.5))
        )
        assertTrajectory(
            actionID: SemanticActionType.addFrontFillLight.rawValue,
            previous: productionFrame(id: "light-a", metrics: UserMovementMetrics(subjectMeanLuma: 0.30)),
            relevant: productionFrame(id: "light-b", metrics: UserMovementMetrics(subjectMeanLuma: 0.40)),
            opposite: productionFrame(id: "light-c", metrics: UserMovementMetrics(subjectMeanLuma: 0.20)),
            noOp: productionFrame(id: "light-d", metrics: UserMovementMetrics(subjectMeanLuma: 0.32))
        )
        assertUnavailable(
            actionID: TechnicalQualityActionType.refocusSubject.rawValue,
            previous: productionFrame(id: "focus-a"),
            current: productionFrame(id: "focus-b"),
            reason: "focus_missing"
        )
        assertTrajectory(
            actionID: TechnicalQualityActionType.stabilizeCamera.rawValue,
            previous: productionFrame(id: "stability-a", still: false, metrics: UserMovementMetrics(shakeLevel: 0.60)),
            relevant: productionFrame(id: "stability-b", metrics: UserMovementMetrics(shakeLevel: 0.30)),
            opposite: productionFrame(id: "stability-c", still: false, metrics: UserMovementMetrics(shakeLevel: 0.90)),
            noOp: productionFrame(id: "stability-d", still: false, metrics: UserMovementMetrics(shakeLevel: 0.62))
        )
    }

    func testActionFamilyMappingCoversEveryKnownActionID() {
        let expectedSemantic: [String: UserMovementActionFamily] = [
            SemanticActionType.shiftFrameLeft.rawValue: .subjectDisplacement,
            SemanticActionType.shiftFrameRight.rawValue: .subjectDisplacement,
            SemanticActionType.shiftFrameUp.rawValue: .subjectDisplacement,
            SemanticActionType.shiftFrameDown.rawValue: .subjectDisplacement,
            SemanticActionType.stepBack.rawValue: .scaleDistance,
            SemanticActionType.stepCloser.rawValue: .scaleDistance,
            SemanticActionType.lowerCamera.rawValue: .subjectDisplacement,
            SemanticActionType.raiseCamera.rawValue: .subjectDisplacement,
            SemanticActionType.levelHorizon.rawValue: .horizonRotation,
            SemanticActionType.rotateSubjectTowardLight.rawValue: .lightExposure,
            SemanticActionType.moveSubjectLeft.rawValue: .subjectDisplacement,
            SemanticActionType.moveSubjectRight.rawValue: .subjectDisplacement,
            SemanticActionType.moveSubjectAwayFromBackground.rawValue: .scaleDistance,
            SemanticActionType.moveObjectLeft.rawValue: .subjectDisplacement,
            SemanticActionType.moveObjectRight.rawValue: .subjectDisplacement,
            SemanticActionType.moveObjectForward.rawValue: .scaleDistance,
            SemanticActionType.moveObjectBack.rawValue: .scaleDistance,
            SemanticActionType.addFrontFillLight.rawValue: .lightExposure,
            SemanticActionType.addBackgroundLight.rawValue: .lightExposure,
            SemanticActionType.removeBackgroundHotspot.rawValue: .lightExposure
        ]
        XCTAssertEqual(Set(expectedSemantic.keys),
                       Set(SemanticActionType.allCases.compactMap { action in
                           expectedSemantic[action.rawValue] == nil ? nil : action.rawValue
                       }),
                       "every mapped semantic action is declared exactly once")
        for action in SemanticActionType.allCases {
            XCTAssertEqual(UserMovementObserver.actionFamily(for: action),
                           expectedSemantic[action.rawValue],
                           action.rawValue)
        }

        let unsupportedSemantic: [SemanticActionType] = [
            // C04.1: prescribed for background/merger cleanup, but horizon
            // rotation is not evidence the obstruction was fixed; no qualified
            // contour metric exists yet, so the honest verdict is unsupported.
            .changeCameraAngle,
            .removeDistractingObject,
            .repositionPropForBalance,
            .simplifyBackground,
            .waitForBackgroundClearance,
            .keepCurrentSetup
        ]
        for action in unsupportedSemantic {
            XCTAssertNil(UserMovementObserver.actionFamily(for: action), action.rawValue)
        }

        let expectedTechnical: [String: UserMovementActionFamily] = [
            TechnicalQualityActionType.stabilizeCamera.rawValue: .stability,
            TechnicalQualityActionType.refocusSubject.rawValue: .focus,
            TechnicalQualityActionType.reduceExposure.rawValue: .lightExposure,
            TechnicalQualityActionType.increaseExposure.rawValue: .lightExposure
        ]
        let allTechnical: [TechnicalQualityActionType] = [
            .stabilizeCamera,
            .refocusSubject,
            .reduceExposure,
            .increaseExposure,
            .avoidOcclusion,
            .cleanLens,
            .reduceIsoNoise
        ]
        for action in allTechnical {
            XCTAssertEqual(UserMovementObserver.actionFamily(for: action),
                           expectedTechnical[action.rawValue],
                           action.rawValue)
        }
        for action in [TechnicalQualityActionType.avoidOcclusion,
                       .cleanLens,
                       .reduceIsoNoise] {
            XCTAssertNil(UserMovementObserver.actionFamily(for: action), action.rawValue)
        }
    }

    func testActionAwareTrajectoriesCoverEveryMappedDirectionalAndScalarAction() {
        let directional: [(String, Double, Double)] = [
            (SemanticActionType.shiftFrameLeft.rawValue, 1, 0),
            (SemanticActionType.shiftFrameRight.rawValue, -1, 0),
            (SemanticActionType.shiftFrameUp.rawValue, 0, 1),
            (SemanticActionType.shiftFrameDown.rawValue, 0, -1),
            (SemanticActionType.lowerCamera.rawValue, 0, -1),
            (SemanticActionType.raiseCamera.rawValue, 0, 1),
            (SemanticActionType.moveSubjectLeft.rawValue, -1, 0),
            (SemanticActionType.moveSubjectRight.rawValue, 1, 0),
            (SemanticActionType.moveObjectLeft.rawValue, -1, 0),
            (SemanticActionType.moveObjectRight.rawValue, 1, 0)
        ]
        for (index, action) in directional.enumerated() {
            let previous = productionFrame(id: "direction-(index)-previous", x: 0.30, y: 0.30)
            let relevant = productionFrame(id: "direction-(index)-relevant",
                                            x: 0.30 + action.1 * 0.08,
                                            y: 0.30 + action.2 * 0.08)
            let opposite = productionFrame(id: "direction-(index)-opposite",
                                            x: 0.30 - action.1 * 0.08,
                                            y: 0.30 - action.2 * 0.08)
            let noOp = productionFrame(id: "direction-(index)-noop",
                                       x: 0.30 + action.1 * 0.01,
                                       y: 0.30 + action.2 * 0.01)
            assertTrajectory(actionID: action.0,
                             previous: previous,
                             relevant: relevant,
                             opposite: opposite,
                             noOp: noOp)
        }

        let areaActions: [(String, Bool)] = [
            (SemanticActionType.stepCloser.rawValue, true),
            (SemanticActionType.moveObjectForward.rawValue, true),
            (SemanticActionType.stepBack.rawValue, false),
            (SemanticActionType.moveObjectBack.rawValue, false)
        ]
        for (index, action) in areaActions.enumerated() {
            let before = 0.20
            let relevantValue = action.1 ? 0.30 : 0.10
            let oppositeValue = action.1 ? 0.10 : 0.30
            let noOpValue = 0.21
            assertTrajectory(actionID: action.0,
                             previous: productionFrame(id: "area-(index)-previous",
                                                        metrics: UserMovementMetrics(subjectAreaRatio: before)),
                             relevant: productionFrame(id: "area-(index)-relevant",
                                                       metrics: UserMovementMetrics(subjectAreaRatio: relevantValue)),
                             opposite: productionFrame(id: "area-(index)-opposite",
                                                       metrics: UserMovementMetrics(subjectAreaRatio: oppositeValue)),
                             noOp: productionFrame(id: "area-(index)-noop",
                                                   metrics: UserMovementMetrics(subjectAreaRatio: noOpValue)))
        }

        assertTrajectory(
            actionID: SemanticActionType.levelHorizon.rawValue,
            previous: productionFrame(id: "level-previous", metrics: UserMovementMetrics(horizonAngleDegrees: 8)),
            relevant: productionFrame(id: "level-relevant", metrics: UserMovementMetrics(horizonAngleDegrees: 5)),
            opposite: productionFrame(id: "level-opposite", metrics: UserMovementMetrics(horizonAngleDegrees: 12)),
            noOp: productionFrame(id: "level-noop", metrics: UserMovementMetrics(horizonAngleDegrees: 7.5))
        )
        // C04.1: a horizon rotation must NOT be read as fixing a background
        // obstruction. Until a contour/occlusion metric exists the action is
        // unsupported, whatever the horizon does.
        XCTAssertEqual(
            UserMovementObserver.observe(
                previous: productionFrame(id: "angle-previous", metrics: UserMovementMetrics(horizonAngleDegrees: 8)),
                current: productionFrame(id: "angle-relevant", metrics: UserMovementMetrics(horizonAngleDegrees: 11)),
                action: .changeCameraAngle
            ),
            .uncertain(reason: "unsupported_action")
        )

        XCTAssertEqual(
            UserMovementObserver.observe(
                previous: productionFrame(id: "angle-cross-zero-previous",
                                          metrics: UserMovementMetrics(horizonAngleDegrees: 8)),
                current: productionFrame(id: "angle-cross-zero-current",
                                         metrics: UserMovementMetrics(horizonAngleDegrees: -8)),
                action: .changeCameraAngle
            ),
            .uncertain(reason: "unsupported_action")
        )
        XCTAssertEqual(
            UserMovementObserver.observe(
                previous: productionFrame(id: "level-cross-zero-previous",
                                          metrics: UserMovementMetrics(horizonAngleDegrees: 8)),
                current: productionFrame(id: "level-cross-zero-current",
                                         metrics: UserMovementMetrics(horizonAngleDegrees: -8)),
                action: .levelHorizon
            ),
            .noOp
        )

        let lightTrajectories: [(String, UserMovementMetrics, UserMovementMetrics, UserMovementMetrics, UserMovementMetrics)] = [
            (
                SemanticActionType.rotateSubjectTowardLight.rawValue,
                UserMovementMetrics(subjectToBackgroundDelta: 0.10),
                UserMovementMetrics(subjectToBackgroundDelta: 0.40),
                UserMovementMetrics(subjectToBackgroundDelta: -0.20),
                UserMovementMetrics(subjectToBackgroundDelta: 0.12)
            ),
            (
                SemanticActionType.addFrontFillLight.rawValue,
                UserMovementMetrics(subjectMeanLuma: 0.30),
                UserMovementMetrics(subjectMeanLuma: 0.50),
                UserMovementMetrics(subjectMeanLuma: 0.10),
                UserMovementMetrics(subjectMeanLuma: 0.32)
            ),
            (
                SemanticActionType.addBackgroundLight.rawValue,
                UserMovementMetrics(backgroundMeanLuma: 0.30),
                UserMovementMetrics(backgroundMeanLuma: 0.50),
                UserMovementMetrics(backgroundMeanLuma: 0.10),
                UserMovementMetrics(backgroundMeanLuma: 0.32)
            ),
            (
                SemanticActionType.removeBackgroundHotspot.rawValue,
                UserMovementMetrics(backgroundHotspotRatio: 0.40),
                UserMovementMetrics(backgroundHotspotRatio: 0.10),
                UserMovementMetrics(backgroundHotspotRatio: 0.70),
                UserMovementMetrics(backgroundHotspotRatio: 0.38)
            ),
            (
                TechnicalQualityActionType.reduceExposure.rawValue,
                UserMovementMetrics(exposureBiasHint: 0),
                UserMovementMetrics(exposureBiasHint: -0.20),
                UserMovementMetrics(exposureBiasHint: 0.20),
                UserMovementMetrics(exposureBiasHint: -0.02)
            ),
            (
                TechnicalQualityActionType.increaseExposure.rawValue,
                UserMovementMetrics(exposureBiasHint: 0),
                UserMovementMetrics(exposureBiasHint: 0.20),
                UserMovementMetrics(exposureBiasHint: -0.20),
                UserMovementMetrics(exposureBiasHint: 0.02)
            )
        ]
        for (index, trajectory) in lightTrajectories.enumerated() {
            assertTrajectory(actionID: trajectory.0,
                             previous: productionFrame(id: "light-(index)-previous", metrics: trajectory.1),
                             relevant: productionFrame(id: "light-(index)-relevant", metrics: trajectory.2),
                             opposite: productionFrame(id: "light-(index)-opposite", metrics: trajectory.3),
                             noOp: productionFrame(id: "light-(index)-noop", metrics: trajectory.4))
        }

        assertTrajectory(
            actionID: TechnicalQualityActionType.stabilizeCamera.rawValue,
            previous: productionFrame(id: "stability-all-previous", still: false,
                                      metrics: UserMovementMetrics(shakeLevel: 0.60)),
            relevant: productionFrame(id: "stability-all-relevant", still: false,
                                      metrics: UserMovementMetrics(shakeLevel: 0.20)),
            opposite: productionFrame(id: "stability-all-opposite", still: false,
                                      metrics: UserMovementMetrics(shakeLevel: 0.90)),
            noOp: productionFrame(id: "stability-all-noop", still: false,
                                  metrics: UserMovementMetrics(shakeLevel: 0.62))
        )

        assertUnavailable(
            actionID: SemanticActionType.moveSubjectAwayFromBackground.rawValue,
            previous: productionFrame(id: "depth-all-previous"),
            current: productionFrame(id: "depth-all-current"),
            reason: "scale_missing"
        )
        assertUnavailable(
            actionID: TechnicalQualityActionType.refocusSubject.rawValue,
            previous: productionFrame(id: "focus-all-previous"),
            current: productionFrame(id: "focus-all-current"),
            reason: "focus_missing"
        )
    }

    private func assertTrajectory(actionID: String,
                                  previous: UserMovementFrame,
                                  relevant: UserMovementFrame,
                                  opposite: UserMovementFrame,
                                  noOp: UserMovementFrame,
                                  file: StaticString = #filePath,
                                  line: UInt = #line) {
        XCTAssertEqual(UserMovementObserver.observe(previous: previous, current: relevant, actionID: actionID),
                       .relevant,
                       file: file,
                       line: line)
        XCTAssertEqual(UserMovementObserver.observe(previous: previous, current: opposite, actionID: actionID),
                       .opposite,
                       file: file,
                       line: line)
        XCTAssertEqual(UserMovementObserver.observe(previous: previous, current: noOp, actionID: actionID),
                       .noOp,
                       file: file,
                       line: line)
    }

    private func assertRelevantAndNoOp(actionID: String,
                                       previous: UserMovementFrame,
                                       relevant: UserMovementFrame,
                                       noOp: UserMovementFrame,
                                       file: StaticString = #filePath,
                                       line: UInt = #line) {
        XCTAssertEqual(UserMovementObserver.observe(previous: previous, current: relevant, actionID: actionID),
                       .relevant,
                       file: file,
                       line: line)
        XCTAssertEqual(UserMovementObserver.observe(previous: previous, current: noOp, actionID: actionID),
                       .noOp,
                       file: file,
                       line: line)
    }

    private func assertUnavailable(actionID: String,
                                   previous: UserMovementFrame,
                                   current: UserMovementFrame,
                                   reason: String,
                                   file: StaticString = #filePath,
                                   line: UInt = #line) {
        XCTAssertEqual(UserMovementObserver.observe(previous: previous,
                                                    current: current,
                                                    actionID: actionID),
                       .uncertain(reason: reason),
                       file: file,
                       line: line)
    }

    func testActionAwareExposureAndDepthUseTheirOwnFeatureSignals() {
        let exposureBefore = productionFrame(
            id: "exposure-a",
            metrics: UserMovementMetrics(exposureBiasHint: -0.60)
        )
        let exposureAfter = productionFrame(
            id: "exposure-b",
            metrics: UserMovementMetrics(exposureBiasHint: -0.40)
        )
        XCTAssertEqual(
            UserMovementObserver.observe(previous: exposureBefore,
                                         current: exposureAfter,
                                         action: .increaseExposure),
            .relevant
        )

        assertUnavailable(
            actionID: SemanticActionType.moveSubjectAwayFromBackground.rawValue,
            previous: productionFrame(id: "depth-a"),
            current: productionFrame(id: "depth-b"),
            reason: "scale_missing"
        )
    }

    // MARK: - Production snapshot/envelope adapter

    func testProductionAdapterConvertsVisionYUpCoordinatesAndRetainsProvenance() {
        let capturedAt = evidenceTime
        let rawRegion = NormalizedRect(x: 0.20, y: 0.10, width: 0.20, height: 0.30)
        let snapshot = adapterSnapshot(frameID: "vision-frame",
                                       capturedAt: capturedAt,
                                       primaryRegion: rawRegion)
        let envelope = adapterEnvelope(frameID: "vision-frame",
                                        capturedAt: capturedAt,
                                        orientation: .right,
                                        timestamps: [
                                            .vision: capturedAt,
                                            .horizon: capturedAt,
                                            .lighting: capturedAt
                                        ])
        let binding = adapterBinding(frameID: "vision-frame",
                                     region: rawRegion,
                                     source: .vision,
                                     measuredAt: capturedAt)

        guard let frame = adapterFrame(snapshot: snapshot,
                                       envelope: envelope,
                                       binding: binding,
                                       orientation: .portrait) else {
            return XCTFail("matching Vision evidence should adapt")
        }
        XCTAssertEqual(snapshot.subjectSignals.primaryCandidateSource, .vision)
        XCTAssertEqual(frame.subjectRegion?.x ?? -1, 0.20, accuracy: 1e-9)
        XCTAssertEqual(frame.subjectRegion?.y ?? -1, 0.60, accuracy: 1e-9,
                       "Vision y-up region must become coaching y-down")
        XCTAssertEqual(frame.subjectRegion?.width ?? -1, 0.20, accuracy: 1e-9)
        XCTAssertEqual(frame.subjectRegion?.height ?? -1, 0.30, accuracy: 1e-9)
        XCTAssertEqual(frame.evidence?.subjectBinding?.source.rawValue, FeatureSourceID.vision.rawValue)
        XCTAssertEqual(frame.evidence?.subjectBinding?.coordinateSpace.rawValue,
                       CameraCoordinateSpaceV2.vision.rawValue)
        XCTAssertEqual(frame.evidence?.featureMeasuredAt[.subjectDisplacement], capturedAt)
        XCTAssertEqual(frame.evidence?.featureConfidence[.subjectDisplacement], 0.9)
        XCTAssertEqual(frame.evidence?.sourceAvailability[.subjectDisplacement], true)
        XCTAssertEqual(frame.evidence?.orientation, .portrait)
    }

    func testProductionAdapterUsesDETRTimestampAndConfidenceForDETRBinding() {
        let capturedAt = evidenceTime
        let rawRegion = NormalizedRect(x: 0.25, y: 0.20, width: 0.25, height: 0.25)
        let snapshot = adapterSnapshot(frameID: "detr-frame",
                                       capturedAt: capturedAt,
                                       primaryRegion: rawRegion,
                                       visionAvailable: false,
                                       visionConfidence: nil,
                                       detrAvailable: true,
                                       detrConfidence: 0.83,
                                       primaryCandidateSource: .detr)
        let envelope = adapterEnvelope(frameID: "detr-frame",
                                        capturedAt: capturedAt,
                                        timestamps: [
                                            .vision: capturedAt.addingTimeInterval(-1.0),
                                            .detr: capturedAt
                                        ])
        let binding = adapterBinding(frameID: "detr-frame",
                                     region: rawRegion,
                                     source: .detr,
                                     measuredAt: capturedAt,
                                     confidence: 0.88)

        guard let frame = adapterFrame(snapshot: snapshot,
                                       envelope: envelope,
                                       binding: binding) else {
            return XCTFail("matching DETR evidence should adapt")
        }
        XCTAssertEqual(snapshot.subjectSignals.primaryCandidateSource, .detr)
        XCTAssertEqual(frame.evidence?.subjectBinding?.source.rawValue, FeatureSourceID.detr.rawValue)
        XCTAssertEqual(frame.evidence?.featureMeasuredAt[.subjectDisplacement], capturedAt)
        XCTAssertEqual(frame.evidence?.featureConfidence[.subjectDisplacement], 0.83)
        XCTAssertEqual(frame.evidence?.sourceAvailability[.subjectDisplacement], true)
    }

    func testProductionAdapterRejectsMixedSelectedSourceAndBinding() {
        let capturedAt = evidenceTime
        let rawRegion = NormalizedRect(x: 0.25, y: 0.20, width: 0.25, height: 0.25)
        let snapshot = adapterSnapshot(frameID: "mixed-source-frame",
                                       capturedAt: capturedAt,
                                       primaryRegion: rawRegion,
                                       detrAvailable: true,
                                       detrConfidence: 0.83,
                                       primaryCandidateSource: .vision)
        let envelope = adapterEnvelope(frameID: "mixed-source-frame", capturedAt: capturedAt)
        let binding = adapterBinding(frameID: "mixed-source-frame",
                                     region: rawRegion,
                                     source: .detr,
                                     measuredAt: capturedAt)

        XCTAssertNil(adapterFrame(snapshot: snapshot, envelope: envelope, binding: binding),
                     "the selected candidate source must match the binding source")
    }

    func testProductionAdapterMarksLightingUnavailableWithoutProducerConfidence() {
        let capturedAt = evidenceTime
        let rawRegion = NormalizedRect(x: 0.20, y: 0.20, width: 0.20, height: 0.30)
        let subjectLighting = FrameFeatureSnapshot.LightingFeatures.SubjectLightingMetrics(
            subjectMeanLuma: 0.8,
            backgroundMeanLuma: 0.2,
            subjectToBackgroundDelta: 0.6,
            subjectClippedBrightRatio: 0.1,
            backgroundHotspotRatio: 0.1
        )
        let snapshot = adapterSnapshot(frameID: "lighting-confidence-missing",
                                       capturedAt: capturedAt,
                                       primaryRegion: rawRegion,
                                       lightingConfidence: nil,
                                       subjectLighting: subjectLighting)
        let envelope = adapterEnvelope(frameID: "lighting-confidence-missing", capturedAt: capturedAt)
        let binding = adapterBinding(frameID: "lighting-confidence-missing",
                                     region: rawRegion,
                                     measuredAt: capturedAt)

        guard let frame = adapterFrame(snapshot: snapshot, envelope: envelope, binding: binding) else {
            return XCTFail("subject evidence should still adapt when lighting confidence is absent")
        }
        XCTAssertEqual(frame.evidence?.sourceAvailability[.lightExposure], false)
        XCTAssertNil(frame.evidence?.featureMeasuredAt[.lightExposure])
        XCTAssertNil(frame.evidence?.featureConfidence[.lightExposure])
        XCTAssertNil(frame.metrics.subjectMeanLuma)
    }

    func testProductionAdapterRejectsUnboundOrMismatchedEvidence() {
        let capturedAt = evidenceTime
        let rawRegion = NormalizedRect(x: 0.20, y: 0.20, width: 0.20, height: 0.30)
        let snapshot = adapterSnapshot(frameID: "gate-frame",
                                       capturedAt: capturedAt,
                                       primaryRegion: rawRegion)
        let envelope = adapterEnvelope(frameID: "gate-frame", capturedAt: capturedAt)
        let binding = adapterBinding(frameID: "gate-frame", region: rawRegion)

        guard let unbound = adapterFrame(snapshot: snapshot, envelope: envelope, binding: nil) else {
            return XCTFail("frame-global evidence should adapt without a subject binding")
        }
        XCTAssertNil(unbound.subjectRegion)
        XCTAssertNil(unbound.metrics.subjectAreaRatio)
        XCTAssertNil(unbound.evidence?.featureMeasuredAt[.subjectDisplacement])
        XCTAssertNil(unbound.evidence?.featureConfidence[.subjectDisplacement])
        XCTAssertNil(unbound.evidence?.sourceAvailability[.subjectDisplacement])
        XCTAssertEqual(unbound.evidence?.sourceAvailability[.horizonRotation], true)
        XCTAssertNil(adapterFrame(snapshot: snapshot,
                                  envelope: envelope,
                                  binding: adapterBinding(frameID: "other-frame", region: rawRegion)),
                     "binding frame identity must match the snapshot")
        XCTAssertNil(adapterFrame(snapshot: snapshot,
                                  envelope: envelope,
                                  binding: adapterBinding(frameID: "gate-frame",
                                                          region: NormalizedRect(x: 0.30,
                                                                                 y: 0.20,
                                                                                 width: 0.20,
                                                                                 height: 0.30))),
                     "binding region must be the measured primary candidate")
        XCTAssertNil(adapterFrame(snapshot: snapshot,
                                  envelope: envelope,
                                  binding: adapterBinding(frameID: "gate-frame",
                                                          region: rawRegion,
                                                          coordinateSpace: .subjectTarget)),
                     "production adapter requires source coordinates")
        XCTAssertNil(adapterFrame(snapshot: snapshot,
                                  envelope: adapterEnvelope(frameID: "gate-frame",
                                                             capturedAt: capturedAt,
                                                             lensGeneration: 0),
                                  binding: binding),
                     "unknown lens generation must fail closed")
        XCTAssertNil(adapterFrame(snapshot: snapshot,
                                  envelope: envelope,
                                  binding: adapterBinding(frameID: "gate-frame",
                                                          region: rawRegion,
                                                          generation: 8)),
                     "binding generation must match the accepted envelope")
        XCTAssertNil(adapterFrame(snapshot: snapshot,
                                  envelope: adapterEnvelope(frameID: "gate-frame",
                                                             capturedAt: capturedAt,
                                                             orientation: .right),
                                  binding: binding),
                     "coach orientation must match the accepted envelope")
        XCTAssertNil(adapterFrame(snapshot: adapterSnapshot(frameID: "gate-frame",
                                                            capturedAt: capturedAt.addingTimeInterval(1),
                                                            primaryRegion: rawRegion),
                                  envelope: envelope,
                                  binding: binding),
                     "snapshot capture time must match the accepted envelope")
        XCTAssertNil(adapterFrame(snapshot: snapshot,
                                  envelope: adapterEnvelope(frameID: "gate-frame",
                                                             capturedAt: capturedAt,
                                                             timestamps: [
                                                                 .vision: capturedAt.addingTimeInterval(-1)
                                                             ]),
                                  binding: adapterBinding(frameID: "gate-frame",
                                                          region: rawRegion,
                                                          measuredAt: capturedAt.addingTimeInterval(-1))),
                     "stale subject source must be unavailable")
    }

    func testFrameGlobalHorizonAndStabilityObserveWithoutSubjectBinding() {
        assertTrajectory(
            actionID: SemanticActionType.levelHorizon.rawValue,
            previous: unboundFrame(id: "global-horizon-previous",
                                   metrics: UserMovementMetrics(horizonAngleDegrees: 8)),
            relevant: unboundFrame(id: "global-horizon-relevant",
                                   metrics: UserMovementMetrics(horizonAngleDegrees: 5)),
            opposite: unboundFrame(id: "global-horizon-opposite",
                                   metrics: UserMovementMetrics(horizonAngleDegrees: 12)),
            noOp: unboundFrame(id: "global-horizon-noop",
                               metrics: UserMovementMetrics(horizonAngleDegrees: 7.5))
        )
        assertTrajectory(
            actionID: TechnicalQualityActionType.stabilizeCamera.rawValue,
            previous: unboundFrame(id: "global-stability-previous",
                                   metrics: UserMovementMetrics(shakeLevel: 0.60),
                                   still: false),
            relevant: unboundFrame(id: "global-stability-relevant",
                                   metrics: UserMovementMetrics(shakeLevel: 0.20),
                                   still: false),
            opposite: unboundFrame(id: "global-stability-opposite",
                                   metrics: UserMovementMetrics(shakeLevel: 0.90),
                                   still: false),
            noOp: unboundFrame(id: "global-stability-noop",
                               metrics: UserMovementMetrics(shakeLevel: 0.62),
                               still: false)
        )

        XCTAssertEqual(UserMovementObserver.observe(
            previous: unboundFrame(id: "global-subject-previous", metrics: UserMovementMetrics()),
            current: unboundFrame(id: "global-subject-current", metrics: UserMovementMetrics()),
            action: .moveSubjectRight
        ), .uncertain(reason: "subject_identity"))
    }

    func testProductionAdapterPreservesSharedCaptureGenerationInvariant() {
        let generation: UInt64 = 7
        let capturedAt = evidenceTime
        let rawRegion = NormalizedRect(x: 0.20, y: 0.20, width: 0.20, height: 0.30)
        let snapshot = adapterSnapshot(frameID: "generation-frame",
                                       capturedAt: capturedAt,
                                       primaryRegion: rawRegion)
        let envelope = adapterEnvelope(frameID: "generation-frame",
                                        capturedAt: capturedAt,
                                        lensGeneration: generation)
        let binding = adapterBinding(frameID: "generation-frame",
                                     region: rawRegion,
                                     generation: generation)

        XCTAssertEqual(binding.identity.generation, generation)
        XCTAssertEqual(envelope.lensGeneration, generation)
        guard let frame = adapterFrame(snapshot: snapshot,
                                       envelope: envelope,
                                       binding: binding) else {
            return XCTFail("shared pipeline generation should adapt")
        }
        XCTAssertEqual(frame.evidence?.lensGeneration, generation)
        XCTAssertEqual(frame.evidence?.subjectBinding?.identity.generation, generation)
    }

    func testActionAwareEvidenceRejectsOrientationChangesAndFreeTrackMetadata() {
        let previous = productionFrame(id: "orientation-previous", orientation: .portrait)
        let changed = productionFrame(id: "orientation-current", x: 0.28, orientation: .landscapeRight)
        XCTAssertEqual(UserMovementObserver.observe(previous: previous,
                                                     current: changed,
                                                     action: .moveSubjectRight),
                       .uncertain(reason: "orientation_changed"))

        let families = UserMovementActionFamily.allCases
        let freeTrackEvidence = UserMovementEvidence(
            capturedAt: evidenceTime,
            lensGeneration: 1,
            subjectTrackID: "free-track-only",
            orientation: .portrait,
            isCalibrated: true,
            featureMeasuredAt: Dictionary(uniqueKeysWithValues: families.map { ($0, evidenceTime) }),
            featureConfidence: Dictionary(uniqueKeysWithValues: families.map { ($0, 0.9) }),
            sourceAvailability: Dictionary(uniqueKeysWithValues: families.map { ($0, true) })
        )
        let freeTrackFrame = UserMovementFrame(
            frameID: "free-track-current",
            subjectRegion: NormalizedRect(x: 0.28, y: 0.4, width: 0.2, height: 0.4),
            meanLuma: 0.5,
            motionIsStill: true,
            metrics: UserMovementMetrics(),
            evidence: freeTrackEvidence
        )
        XCTAssertEqual(UserMovementObserver.observe(previous: previous,
                                                     current: freeTrackFrame,
                                                     action: .moveSubjectRight),
                       .uncertain(reason: "subject_identity"))
    }

    func testProductionAdapterDoesNotUseWholeFrameLumaAndLeavesFocusDepthUnavailable() {
        let firstCapture = evidenceTime
        let secondCapture = evidenceTime.addingTimeInterval(0.1)
        let rawRegion = NormalizedRect(x: 0.20, y: 0.20, width: 0.20, height: 0.30)
        let firstSnapshot = adapterSnapshot(frameID: "light-adapter-previous",
                                            capturedAt: firstCapture,
                                            primaryRegion: rawRegion,
                                            subjectLighting: nil)
        let secondSnapshot = adapterSnapshot(frameID: "light-adapter-current",
                                             capturedAt: secondCapture,
                                             primaryRegion: rawRegion,
                                             subjectLighting: nil)
        let firstEnvelope = adapterEnvelope(frameID: "light-adapter-previous",
                                             capturedAt: firstCapture)
        let secondEnvelope = adapterEnvelope(frameID: "light-adapter-current",
                                              capturedAt: secondCapture)
        let firstBinding = adapterBinding(frameID: "light-adapter-previous",
                                          region: rawRegion,
                                          measuredAt: firstCapture)
        let secondBinding = adapterBinding(frameID: "light-adapter-current",
                                           region: rawRegion,
                                           measuredAt: secondCapture)
        guard let previous = adapterFrame(snapshot: firstSnapshot,
                                          envelope: firstEnvelope,
                                          binding: firstBinding),
              let adaptedCurrent = adapterFrame(snapshot: secondSnapshot,
                                                envelope: secondEnvelope,
                                                binding: secondBinding) else {
            return XCTFail("fresh adapter fixtures should adapt")
        }
        XCTAssertNil(previous.metrics.subjectMeanLuma)
        XCTAssertNil(adaptedCurrent.metrics.subjectMeanLuma)

        // A changed legacy meanLuma must not masquerade as a subject-light
        // measurement when the typed subject-light payload is absent.
        let wholeFrameOnlyCurrent = UserMovementFrame(
            frameID: adaptedCurrent.frameID,
            subjectRegion: adaptedCurrent.subjectRegion,
            meanLuma: 0.99,
            motionIsStill: adaptedCurrent.motionIsStill,
            metrics: UserMovementMetrics(),
            evidence: adaptedCurrent.evidence
        )
        XCTAssertEqual(UserMovementObserver.observe(previous: previous,
                                                     current: wholeFrameOnlyCurrent,
                                                     action: .addFrontFillLight),
                       .uncertain(reason: "light_missing"))
        XCTAssertEqual(UserMovementObserver.observe(previous: previous,
                                                     current: adaptedCurrent,
                                                     action: .refocusSubject),
                       .uncertain(reason: "feature_missing"))
        XCTAssertEqual(UserMovementObserver.observe(previous: previous,
                                                     current: adaptedCurrent,
                                                     action: .moveSubjectAwayFromBackground),
                       .uncertain(reason: "scale_missing"))
    }

    func testObserverUsesCanonicalPerSourceFreshnessWindows() {
        let now = evidenceTime
        let visionWindow = FeatureSourceFreshnessWindows.window(for: .vision)
        let detrWindow = FeatureSourceFreshnessWindows.window(for: .detr)
        let horizonWindow = FeatureSourceFreshnessWindows.window(for: .horizon)
        let lightingWindow = FeatureSourceFreshnessWindows.window(for: .lighting)

        let visionAge = visionWindow - 0.01
        XCTAssertEqual(
            UserMovementObserver.observe(
                previous: productionFrame(id: "fresh-vision-a",
                                          measuredAt: now.addingTimeInterval(-visionAge),
                                          evaluatedAt: now,
                                          source: .vision),
                current: productionFrame(id: "fresh-vision-b",
                                         x: 0.28,
                                         measuredAt: now.addingTimeInterval(-visionAge),
                                         evaluatedAt: now,
                                         source: .vision),
                action: .moveSubjectRight
            ),
            .relevant
        )

        // DETR has its own wider window; this age would be stale if the
        // observer still applied the old blanket Vision-sized bound.
        let detrAge = visionWindow + 0.05
        XCTAssertLessThan(detrAge, detrWindow)
        XCTAssertEqual(
            UserMovementObserver.observe(
                previous: productionFrame(id: "fresh-detr-a",
                                          measuredAt: now.addingTimeInterval(-detrAge),
                                          evaluatedAt: now,
                                          source: .detr),
                current: productionFrame(id: "fresh-detr-b",
                                         x: 0.28,
                                         measuredAt: now.addingTimeInterval(-detrAge),
                                         evaluatedAt: now,
                                         source: .detr),
                action: .moveSubjectRight
            ),
            .relevant
        )

        let staleHorizonAge = horizonWindow + 0.01
        XCTAssertEqual(
            UserMovementObserver.observe(
                previous: productionFrame(id: "stale-horizon-a",
                                          metrics: UserMovementMetrics(horizonAngleDegrees: 8),
                                          measuredAt: now.addingTimeInterval(-staleHorizonAge),
                                          evaluatedAt: now),
                current: productionFrame(id: "stale-horizon-b",
                                         metrics: UserMovementMetrics(horizonAngleDegrees: 5),
                                         measuredAt: now.addingTimeInterval(-staleHorizonAge),
                                         evaluatedAt: now),
                action: .levelHorizon
            ),
            .uncertain(reason: "stale_evidence")
        )

        let staleLightingAge = lightingWindow + 0.01
        XCTAssertEqual(
            UserMovementObserver.observe(
                previous: productionFrame(id: "stale-light-a",
                                          metrics: UserMovementMetrics(subjectMeanLuma: 0.30),
                                          measuredAt: now.addingTimeInterval(-staleLightingAge),
                                          evaluatedAt: now),
                current: productionFrame(id: "stale-light-b",
                                         metrics: UserMovementMetrics(subjectMeanLuma: 0.50),
                                         measuredAt: now.addingTimeInterval(-staleLightingAge),
                                         evaluatedAt: now),
                action: .addFrontFillLight
            ),
            .uncertain(reason: "stale_evidence")
        )

        let staleMotionAge = visionWindow + 0.01
        XCTAssertEqual(
            UserMovementObserver.observe(
                previous: productionFrame(id: "stale-motion-a",
                                          still: false,
                                          metrics: UserMovementMetrics(shakeLevel: 0.60),
                                          trackID: nil,
                                          capturedAt: now.addingTimeInterval(-staleMotionAge),
                                          evaluatedAt: now),
                current: productionFrame(id: "stale-motion-b",
                                         still: false,
                                         metrics: UserMovementMetrics(shakeLevel: 0.20),
                                         trackID: nil,
                                         capturedAt: now.addingTimeInterval(-staleMotionAge),
                                         evaluatedAt: now),
                action: .stabilizeCamera
            ),
            .uncertain(reason: "stale_evidence")
        )
    }

    func testProductionAdapterLowConfidenceAndUncalibratedEvidenceStayUncertain() {
        let firstCapture = evidenceTime
        let secondCapture = evidenceTime.addingTimeInterval(0.1)
        let rawRegion = NormalizedRect(x: 0.20, y: 0.20, width: 0.20, height: 0.30)
        let firstSnapshot = adapterSnapshot(frameID: "confidence-previous",
                                            capturedAt: firstCapture,
                                            primaryRegion: rawRegion)
        let firstEnvelope = adapterEnvelope(frameID: "confidence-previous",
                                             capturedAt: firstCapture)
        let firstBinding = adapterBinding(frameID: "confidence-previous",
                                          region: rawRegion,
                                          measuredAt: firstCapture)
        let lowSnapshot = adapterSnapshot(frameID: "confidence-low",
                                          capturedAt: secondCapture,
                                          primaryRegion: rawRegion,
                                          visionConfidence: 0.2)
        let lowEnvelope = adapterEnvelope(frameID: "confidence-low",
                                           capturedAt: secondCapture)
        let lowBinding = adapterBinding(frameID: "confidence-low",
                                        region: rawRegion,
                                        measuredAt: secondCapture)
        let uncalibratedSnapshot = adapterSnapshot(frameID: "confidence-uncalibrated",
                                                   capturedAt: secondCapture,
                                                   primaryRegion: rawRegion)
        let uncalibratedEnvelope = adapterEnvelope(frameID: "confidence-uncalibrated",
                                                    capturedAt: secondCapture)
        let uncalibratedBinding = adapterBinding(frameID: "confidence-uncalibrated",
                                                 region: rawRegion,
                                                 measuredAt: secondCapture)
        guard let previous = adapterFrame(snapshot: firstSnapshot,
                                          envelope: firstEnvelope,
                                          binding: firstBinding),
              let low = adapterFrame(snapshot: lowSnapshot,
                                     envelope: lowEnvelope,
                                     binding: lowBinding),
              let uncalibrated = adapterFrame(snapshot: uncalibratedSnapshot,
                                              envelope: uncalibratedEnvelope,
                                              binding: uncalibratedBinding,
                                              calibrated: false) else {
            return XCTFail("fresh adapter fixtures should adapt")
        }
        XCTAssertEqual(UserMovementObserver.observe(previous: previous,
                                                     current: low,
                                                     action: .moveSubjectRight),
                       .uncertain(reason: "feature_confidence"))
        XCTAssertEqual(UserMovementObserver.observe(previous: previous,
                                                     current: uncalibrated,
                                                     action: .moveSubjectRight),
                       .uncertain(reason: "uncalibrated"))
        XCTAssertEqual(uncalibrated.subjectRegion, uncalibratedBinding.coachingRegion)
        XCTAssertEqual(uncalibrated.metrics.subjectAreaRatio ?? .nan,
                       rawRegion.width * rawRegion.height, accuracy: 1e-12)
        XCTAssertEqual(uncalibrated.evidence?.featureMeasuredAt[.subjectDisplacement], secondCapture)
        XCTAssertEqual(uncalibrated.evidence?.sourceAvailability[.subjectDisplacement], true,
                       "missing calibration must not erase separately measured geometry")
    }

    func testActionAwareObservationFailsClosedForInvalidEvidence() {
        let previous = productionFrame(id: "evidence-a")
        let noEvidence = frame(x: 0.28, id: "evidence-b")
        XCTAssertEqual(
            UserMovementObserver.observe(previous: previous,
                                         current: noEvidence,
                                         action: .moveSubjectRight),
            .uncertain(reason: "evidence_missing")
        )

        let stale = productionFrame(id: "evidence-c",
                                    measuredAt: evidenceTime.addingTimeInterval(-2))
        XCTAssertEqual(
            UserMovementObserver.observe(previous: previous,
                                         current: stale,
                                         action: .moveSubjectRight),
            .uncertain(reason: "stale_evidence")
        )

        let wrongTrack = productionFrame(id: "evidence-d", trackID: "subject-2")
        XCTAssertEqual(
            UserMovementObserver.observe(previous: previous,
                                         current: wrongTrack,
                                         action: .moveSubjectRight),
            .uncertain(reason: "subject_identity")
        )

        let lowConfidence = productionFrame(id: "evidence-e", confidence: 0.2)
        XCTAssertEqual(
            UserMovementObserver.observe(previous: previous,
                                         current: lowConfidence,
                                         action: .moveSubjectRight),
            .uncertain(reason: "feature_confidence")
        )

        let uncalibrated = productionFrame(id: "evidence-f", calibrated: false)
        XCTAssertEqual(
            UserMovementObserver.observe(previous: previous,
                                         current: uncalibrated,
                                         action: .moveSubjectRight),
            .uncertain(reason: "uncalibrated")
        )

        let moving = productionFrame(id: "evidence-g", x: 0.28, still: false)
        XCTAssertEqual(
            UserMovementObserver.observe(previous: previous,
                                         current: moving,
                                         action: .moveSubjectRight),
            .uncertain(reason: "camera_motion")
        )
    }

    func testActionAwareTrackerDoesNotCompleteFromElapsedTime() {
        var tracker = UserMovementTracker(action: .stepCloser, requiredRelevantFrames: 1)
        let start = evidenceTime
        _ = tracker.observe(productionFrame(
            id: "timer-a",
            metrics: UserMovementMetrics(subjectAreaRatio: 0.20),
            capturedAt: start,
            measuredAt: start,
            evaluatedAt: start
        ))
        XCTAssertFalse(tracker.movementGoalReached)

        let muchLater = start.addingTimeInterval(120)
        _ = tracker.observe(productionFrame(
            id: "timer-b",
            metrics: UserMovementMetrics(subjectAreaRatio: 0.20),
            capturedAt: muchLater,
            measuredAt: muchLater,
            evaluatedAt: muchLater
        ))
        XCTAssertFalse(tracker.movementGoalReached)
        XCTAssertEqual(tracker.lastVerdict, .uncertain(reason: "stale_evidence"))
    }

    // MARK: - Tracker streak semantics

    func testTrackerRequiresConsecutiveRelevantFrames() {
        var tracker = UserMovementTracker(desiredDisplacement: (dx: 1, dy: 0), requiredRelevantFrames: 2)
        XCTAssertFalse(tracker.movementGoalReached)

        // First frame: no previous → uncertain.
        _ = tracker.observe(frame(x: 0.2, id: "f0"))
        XCTAssertFalse(tracker.movementGoalReached)

        // Relevant movement once.
        _ = tracker.observe(frame(x: 0.28, id: "f1"))
        XCTAssertFalse(tracker.movementGoalReached, "one relevant frame < 2 required")

        // Relevant movement twice → goal reached.
        _ = tracker.observe(frame(x: 0.36, id: "f2"))
        XCTAssertTrue(tracker.movementGoalReached)

        // Opposite movement resets the streak.
        _ = tracker.observe(frame(x: 0.28, id: "f3"))
        XCTAssertFalse(tracker.movementGoalReached)
        XCTAssertEqual(tracker.lastVerdict, .opposite)
    }

    func testUncertainFramesResetTheStreak() {
        var tracker = UserMovementTracker(desiredDisplacement: (dx: 1, dy: 0), requiredRelevantFrames: 2)
        _ = tracker.observe(frame(x: 0.2, id: "f0"))
        _ = tracker.observe(frame(x: 0.28, id: "f1"))
        XCTAssertEqual(tracker.consecutiveRelevant, 1)

        // Camera moves: uncertainty invalidates the prior relevant streak.
        _ = tracker.observe(frame(x: 0.35, still: false, id: "f2"))
        XCTAssertEqual(tracker.consecutiveRelevant, 0, "uncertain frames reset the streak")

        // Still again, one new relevant frame is not enough to complete.
        _ = tracker.observe(frame(x: 0.42, still: true, id: "f3"))
        XCTAssertEqual(tracker.consecutiveRelevant, 1)
        XCTAssertFalse(tracker.movementGoalReached)
    }

    func testNonPositiveRequiredRelevantFramesAreClamped() {
        var zeroTracker = UserMovementTracker(desiredDisplacement: (dx: 1, dy: 0), requiredRelevantFrames: 0)
        XCTAssertEqual(zeroTracker.requiredRelevantFrames, 1)
        _ = zeroTracker.observe(frame(x: 0.2, id: "zero-a"))
        XCTAssertFalse(zeroTracker.movementGoalReached)
        _ = zeroTracker.observe(frame(x: 0.28, id: "zero-b"))
        XCTAssertTrue(zeroTracker.movementGoalReached)

        var negativeTracker = UserMovementTracker(actionID: SemanticActionType.moveSubjectRight.rawValue,
                                                   requiredRelevantFrames: -1)
        XCTAssertEqual(negativeTracker.requiredRelevantFrames, 1)
        XCTAssertFalse(negativeTracker.movementGoalReached)
    }

    func testResetClearsTracking() {
        var tracker = UserMovementTracker(desiredDisplacement: (dx: 1, dy: 0), requiredRelevantFrames: 1)
        _ = tracker.observe(frame(x: 0.2, id: "f0"))
        _ = tracker.observe(frame(x: 0.28, id: "f1"))
        XCTAssertTrue(tracker.movementGoalReached)
        tracker.reset()
        XCTAssertFalse(tracker.movementGoalReached)
        XCTAssertNil(tracker.lastVerdict)
        XCTAssertEqual(tracker.totalObservations, 0)
    }

    // MARK: - C04.2 target scope

    private func entityFrame(id: String,
                             subjectX: Double,
                             lampAX: Double,
                             lampBX: Double,
                             capturedAt: Date) -> UserMovementFrame {
        let base = productionFrame(id: id, x: subjectX, capturedAt: capturedAt)
        guard let evidence = base.evidence else { return base }
        let lampA = UserMovementEntityObservation(
            entityRef: "lampA",
            trackID: "ta",
            visibility: .visible,
            region: NormalizedRect(x: lampAX, y: 0.2, width: 0.15, height: 0.2)
        )!
        let lampB = UserMovementEntityObservation(
            entityRef: "lampB",
            trackID: "tb",
            visibility: .visible,
            region: NormalizedRect(x: lampBX, y: 0.2, width: 0.15, height: 0.2)
        )!
        return UserMovementFrame(
            frameID: base.frameID,
            subjectRegion: base.subjectRegion,
            meanLuma: base.meanLuma,
            motionIsStill: base.motionIsStill,
            metrics: base.metrics,
            evidence: evidence,
            entityObservations: [lampA, lampB]
        )
    }

    /// N10 "two lamps": movement of `lampB` must not complete the `lampA` step.
    func testTargetScopedTrackerIgnoresAnotherObjectMovement() {
        var tracker = UserMovementTracker(
            actionID: SemanticActionType.moveObjectLeft.rawValue,
            targetRefs: ["lampA"],
            requiredRelevantFrames: 1
        )
        let t0 = evidenceTime
        _ = tracker.observe(entityFrame(
            id: "target-scope-0",
            subjectX: 0.50,
            lampAX: 0.45,
            lampBX: 0.70,
            capturedAt: t0
        ))
        // The subject and lampB move; the commanded lampA does not.
        let otherMoved = tracker.observe(entityFrame(
            id: "target-scope-1",
            subjectX: 0.30,
            lampAX: 0.45,
            lampBX: 0.58,
            capturedAt: t0.addingTimeInterval(0.05)
        ))
        XCTAssertEqual(otherMoved, .noOp)
        XCTAssertFalse(
            tracker.movementGoalReached,
            "movement of another object must not complete the commanded step"
        )

        // Now the commanded lampA moves left.
        let commandedMoved = tracker.observe(entityFrame(
            id: "target-scope-2",
            subjectX: 0.30,
            lampAX: 0.35,
            lampBX: 0.58,
            capturedAt: t0.addingTimeInterval(0.10)
        ))
        XCTAssertEqual(commandedMoved, .relevant)
        XCTAssertTrue(tracker.movementGoalReached)
    }
}

// MARK: - Accepted current-object measurement adapter

extension UserMovementObserverTests {
    private struct EntityMeasurementFixture {
        let frame: ObjectTrackFrame
        let sample: FeatureSample<FeatureSnapshotDetrPayload>
        var observations: [UserMovementEntityObservation] {
            UserMovementEntityProvenance.observations(frame: frame, sample: sample, pipelineGeneration: 0)
        }
    }

    /// The real identity owner receives the exact measured rectangles. Reverse
    /// detector order deliberately differs from the tracker's spatial ordering.
    private func entityMeasurementFixture(rawBoxes: [CGRect]? = nil) throws -> EntityMeasurementFixture {
        let boxes = rawBoxes ?? [
            CGRect(x: 0.65, y: 0.2, width: 0.2, height: 0.3),
            CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.3)
        ]
        let geometries = try boxes.enumerated().map {
            try XCTUnwrap(VisionObjectGeometry(seedSlot: $0.offset, rawBoundingBox: $0.element))
        }
        let source = VisionObjectFrame(
            frameID: "entity-source", captureGeneration: 7, sessionGeneration: 3,
            lifecycleGeneration: 0, orientation: .up,
            samplePTS: CMTime(value: 900, timescale: 1_000),
            capturedAt: evidenceTime.addingTimeInterval(-0.1))
        let current = VisionObjectFrame(
            frameID: "entity-current", captureGeneration: 7, sessionGeneration: 3,
            lifecycleGeneration: 0, orientation: .up,
            samplePTS: CMTime(value: 1_000, timescale: 1_000), capturedAt: evidenceTime)
        let detections = geometries.enumerated().map { index, geometry in
            FeatureSnapshotDetectedObject(
                boundingBox: geometry.visibleImageIntersection, label: "chair",
                confidence: index == 0 ? 0.81 : 0.61)
        }
        let sample = FeatureSample(
            value: FeatureSnapshotDetrPayload(
                detections: detections,
                tracking: FeatureSnapshotDetrTracking(
                    source: source, current: current,
                    geometryMeasuredAt: evidenceTime.addingTimeInterval(0.005),
                    qualities: geometries.indices.map { $0 == 0 ? Float(0.92) : Float(0.83) },
                    geometries: geometries)),
            measuredAt: source.capturedAt, baseConfidence: 0.81, provenance: current.featureProvenance)
        XCTAssertTrue(sample.hasValidTrackingLinkage)
        let tracker = SubjectTracker()
        let objects = detections.enumerated().map { index, detection in
            let b = detection.boundingBox
            return SubjectCandidate(
                id: "detector-local-\(index)", kind: .object, label: detection.label,
                region: NormalizedRect(x: Double(b.origin.x), y: Double(b.origin.y),
                                       width: Double(b.size.width), height: Double(b.size.height)),
                confidence: detection.confidence)
        }
        let frame = try XCTUnwrap(tracker.acceptObjectFrame(
            candidates: objects, frameID: current.frameID, generation: 7,
            sampleSequence: 5, capturedAt: current.capturedAt))
        return EntityMeasurementFixture(frame: frame, sample: sample)
    }

    private func entityEnvelope(_ fixture: EntityMeasurementFixture,
                                frameID: String? = nil, generation: UInt64 = 7,
                                session: UInt64? = 3, pts: CMTime = CMTime(value: 1, timescale: 1),
                                orientation: CGImagePropertyOrientation = .up,
                                capturedAt: Date? = nil, sourceDate: Date? = nil) -> AcceptedFrameEnvelope {
        AcceptedFrameEnvelope(
            frameID: frameID ?? fixture.frame.frameID, capturedAt: capturedAt ?? fixture.frame.capturedAt,
            orientation: orientation, lensGeneration: generation, pixelBuffer: makePixelBuffer(),
            featureSourceTimestamps: [.detr: sourceDate ?? fixture.sample.measuredAt],
            samplePresentationTimestamp: pts, sessionGeneration: session)
    }

    private func entityAdapterFrame(_ fixture: EntityMeasurementFixture,
                                    observations: [UserMovementEntityObservation]? = nil,
                                    envelope: AcceptedFrameEnvelope? = nil,
                                    pipelineGeneration: UInt64? = 0,
                                    evaluatedAt: Date? = nil, detrAvailable: Bool = true,
                                    isCalibrated: Bool = false) -> UserMovementFrame? {
        let accepted = envelope ?? entityEnvelope(fixture)
        let snapshot = adapterSnapshot(
            frameID: fixture.frame.frameID, capturedAt: fixture.frame.capturedAt,
            primaryRegion: NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.3),
            detrAvailable: detrAvailable, detrConfidence: 0.81, primaryCandidateSource: .detr)
        return UserMovementFrame(
            snapshot: snapshot, envelope: accepted, subjectBinding: nil,
            entityObservations: observations ?? fixture.observations,
            pipelineGeneration: pipelineGeneration,
            evaluatedAt: evaluatedAt ?? evidenceTime.addingTimeInterval(0.02),
            isCalibrated: isCalibrated, calibrationVersion: nil, orientation: .landscapeRight)
    }

    private func changedEntityProvenance(
        _ p: UserMovementEntityProvenance, frameID: String? = nil,
        sequence: UInt64? = nil, orientationRaw: UInt32? = nil,
        sourceID: String? = nil, sourcePTS: CMTime? = nil,
        sourceDate: Date? = nil, geometryDate: Date? = nil,
        support: Double? = nil, quality: Float? = nil,
        slot: Int? = nil, rawBox: CGRect? = nil, visibleBox: CGRect? = nil,
        clippedFraction: Double? = nil, clippedEdges: UInt8? = nil
    ) -> UserMovementEntityProvenance {
        UserMovementEntityProvenance(
            identity: p.identity, frameID: frameID ?? p.frameID,
            sampleSequence: sequence ?? p.sampleSequence, sessionGeneration: p.sessionGeneration,
            pipelineGeneration: p.pipelineGeneration, orientationRawValue: orientationRaw ?? p.orientationRawValue,
            samplePresentationTimestamp: p.samplePresentationTimestamp, capturedAt: p.capturedAt,
            semanticSourceFrameID: sourceID ?? p.semanticSourceFrameID,
            semanticSamplePresentationTimestamp: sourcePTS ?? p.semanticSamplePresentationTimestamp,
            semanticMeasuredAt: sourceDate ?? p.semanticMeasuredAt,
            geometryMeasuredAt: geometryDate ?? p.geometryMeasuredAt,
            semanticSupport: support ?? p.semanticSupport, trackingQuality: quality ?? p.trackingQuality,
            sourceRequestSlot: slot ?? p.sourceRequestSlot, rawBoundingBox: rawBox ?? p.rawBoundingBox,
            visibleImageIntersection: visibleBox ?? p.visibleImageIntersection,
            rectangleClippedFraction: clippedFraction ?? p.rectangleClippedFraction,
            clippedEdges: clippedEdges ?? p.clippedEdges)
    }

    func testEntityFactoryBindsSameLabelObjectsByExactCurrentIdentityAndMeasurement() throws {
        let fixture = try entityMeasurementFixture()
        let observations = fixture.observations
        XCTAssertEqual(observations.count, 2)
        XCTAssertEqual(Set(observations.map(\.entityRef)).count, 2)
        for object in fixture.frame.currentObjects {
            let observation = try XCTUnwrap(observations.first { $0.trackID == object.identity.trackID })
            let p = try XCTUnwrap(observation.provenance)
            let sourceSlot = object.region!.x < 0.5 ? 1 : 0
            XCTAssertEqual(p.identity, object.identity)
            XCTAssertEqual(p.sourceRequestSlot, sourceSlot, "Detector order is not identity order")
            XCTAssertEqual(p.semanticSupport, sourceSlot == 0 ? 0.81 : 0.61)
            XCTAssertEqual(p.trackingQuality, sourceSlot == 0 ? Float(0.92) : Float(0.83))
            XCTAssertEqual(p.semanticSourceFrameID, "entity-source")
            XCTAssertEqual(p.frameID, "entity-current")
            XCTAssertEqual(p.semanticMeasuredAt, evidenceTime.addingTimeInterval(-0.1))
            XCTAssertEqual(p.capturedAt, evidenceTime)
            XCTAssertEqual(p.geometryMeasuredAt, evidenceTime.addingTimeInterval(0.005))
            XCTAssertEqual(CMTimeCompare(p.semanticSamplePresentationTimestamp, CMTime(value: 9, timescale: 10)), 0)
            XCTAssertEqual(CMTimeCompare(p.samplePresentationTimestamp, CMTime(value: 1, timescale: 1)), 0)
            XCTAssertEqual(p.sampleSequence, 5)
            XCTAssertEqual(p.pipelineGeneration, 0, "Initial pipeline generation zero is valid")
            XCTAssertEqual(observation.region?.x, object.region?.x)
            XCTAssertEqual(try XCTUnwrap(observation.region).y,
                           1 - object.region!.y - object.region!.height, accuracy: 1e-12)
            XCTAssertEqual(try XCTUnwrap(observation.region).width, object.region!.width, accuracy: 1e-12)
            XCTAssertEqual(observation.visibility, .visible)
            XCTAssertTrue(observation.hasComparableGeometry)
        }
        let adapted = try XCTUnwrap(entityAdapterFrame(fixture))
        XCTAssertEqual(adapted.entityObservations, observations)
        XCTAssertEqual(adapted.evidence?.isCalibrated, false)
        XCTAssertNil(adapted.evidence?.calibrationVersion)
        XCTAssertNil(adapted.evidence?.subjectBinding, "Entity measurements do not select a primary subject")
    }

    func testClippedEntityRemainsPartialAndLossDoesNotManufactureAbsence() throws {
        let fixture = try entityMeasurementFixture(rawBoxes: [
            CGRect(x: 0.65, y: -0.01, width: 0.2, height: 0.3)
        ])
        let observation = try XCTUnwrap(fixture.observations.first)
        XCTAssertEqual(observation.visibility, .partial)
        XCTAssertTrue(observation.isObserved)
        XCTAssertFalse(observation.hasComparableGeometry)
        XCTAssertEqual(observation.provenance?.rawBoundingBox.origin.y, -0.01)
        XCTAssertEqual(observation.provenance?.visibleImageIntersection.origin.y, 0)
        XCTAssertGreaterThan(try XCTUnwrap(observation.provenance).rectangleClippedFraction, 0)
        XCTAssertEqual(entityAdapterFrame(fixture)?.entityObservations, [observation])
        let lost = fixture.frame.objects.map {
            ObjectTrackState(identity: $0.identity, label: $0.label,
                lastObservedRegion: $0.lastObservedRegion, lastObservedFrameID: $0.lastObservedFrameID,
                lastObservedSampleSequence: $0.lastObservedSampleSequence, phase: .lost,
                frameID: $0.frameID, sampleSequence: $0.sampleSequence)
        }
        let frame = ObjectTrackFrame(frameID: fixture.frame.frameID, generation: 7,
            sampleSequence: 5, capturedAt: evidenceTime, objects: lost)
        let result = UserMovementEntityProvenance.observations(
            frame: frame, sample: fixture.sample, pipelineGeneration: 0)
        XCTAssertTrue(result.isEmpty)
        XCTAssertFalse(result.contains { $0.visibility == .absent })
        XCTAssertTrue(entityAdapterFrame(fixture, observations: [])?.entityObservations.isEmpty == true)
    }

    func testEntityFactoryRejectsDuplicateMeasurementsAndDuplicateIdentities() throws {
        let box = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.3)
        let duplicateDetections = try entityMeasurementFixture(rawBoxes: [box, box])
        XCTAssertEqual(duplicateDetections.frame.currentObjects.count, 1,
                       "The actual tracker deduplicates identical same-label rectangles")
        XCTAssertTrue(duplicateDetections.observations.isEmpty,
                      "One identity must not arbitrarily choose among two measurement slots")
        let fixture = try entityMeasurementFixture()
        let objects = fixture.frame.currentObjects
        let repeatedIdentity = objects.map {
            ObjectTrackState(identity: objects[0].identity, label: $0.label,
                lastObservedRegion: $0.lastObservedRegion, lastObservedFrameID: $0.lastObservedFrameID,
                lastObservedSampleSequence: $0.lastObservedSampleSequence, phase: .active,
                frameID: $0.frameID, sampleSequence: $0.sampleSequence)
        }
        for invalid in [repeatedIdentity, [objects[0], objects[0]]] {
            let frame = ObjectTrackFrame(frameID: fixture.frame.frameID, generation: 7,
                sampleSequence: 5, capturedAt: evidenceTime, objects: invalid)
            XCTAssertTrue(UserMovementEntityProvenance.observations(
                frame: frame, sample: fixture.sample, pipelineGeneration: 0).isEmpty)
        }
    }

    func testEntityFactoryRejectsDifferentFrameCaptureSequenceAndPipeline() throws {
        let fixture = try entityMeasurementFixture()
        let frames = [
            ObjectTrackFrame(frameID: "stale", generation: 7, sampleSequence: 5,
                             capturedAt: evidenceTime, objects: fixture.frame.objects),
            ObjectTrackFrame(frameID: fixture.frame.frameID, generation: 8, sampleSequence: 5,
                             capturedAt: evidenceTime, objects: fixture.frame.objects),
            ObjectTrackFrame(frameID: fixture.frame.frameID, generation: 7, sampleSequence: 6,
                             capturedAt: evidenceTime, objects: fixture.frame.objects),
            ObjectTrackFrame(frameID: fixture.frame.frameID, generation: 7, sampleSequence: 5,
                             capturedAt: evidenceTime.addingTimeInterval(0.01), objects: fixture.frame.objects)
        ]
        for frame in frames {
            XCTAssertTrue(UserMovementEntityProvenance.observations(
                frame: frame, sample: fixture.sample, pipelineGeneration: 0).isEmpty)
        }
        XCTAssertTrue(UserMovementEntityProvenance.observations(
            frame: fixture.frame, sample: fixture.sample, pipelineGeneration: 1).isEmpty)
    }

    func testEntityAdapterRequiresExactEnvelopeEpochClockAndFreshness() throws {
        let fixture = try entityMeasurementFixture()
        XCTAssertNotNil(entityAdapterFrame(fixture))
        let invalid = [
            entityEnvelope(fixture, frameID: "different"),
            entityEnvelope(fixture, generation: 8),
            entityEnvelope(fixture, session: 4),
            entityEnvelope(fixture, session: nil),
            entityEnvelope(fixture, pts: .invalid),
            entityEnvelope(fixture, pts: CMTime(value: 1001, timescale: 1000)),
            entityEnvelope(fixture, orientation: .right),
            entityEnvelope(fixture, capturedAt: evidenceTime.addingTimeInterval(0.01)),
            entityEnvelope(fixture, sourceDate: fixture.sample.measuredAt.addingTimeInterval(0.01))
        ]
        for envelope in invalid { XCTAssertNil(entityAdapterFrame(fixture, envelope: envelope)) }
        XCTAssertNil(entityAdapterFrame(fixture, pipelineGeneration: nil))
        XCTAssertNil(entityAdapterFrame(fixture, pipelineGeneration: 1))
        XCTAssertNil(entityAdapterFrame(fixture, evaluatedAt: evidenceTime.addingTimeInterval(0.004)),
                     "The pixel measurement has not completed yet")
        XCTAssertNotNil(entityAdapterFrame(fixture, evaluatedAt: evidenceTime.addingTimeInterval(0.25)))
        XCTAssertNil(entityAdapterFrame(fixture, evaluatedAt: evidenceTime.addingTimeInterval(0.251)))
        XCTAssertNil(entityAdapterFrame(fixture, detrAvailable: false))
    }

    func testEntitySemanticFreshnessDoesNotRenewAtCurrentGeometryTime() throws {
        let fixture = try entityMeasurementFixture()
        let observation = try XCTUnwrap(fixture.observations.first)
        let original = try XCTUnwrap(observation.provenance)
        for (age, expected) in [(0.79, true), (0.81, false)] {
            let sourceDate = evidenceTime.addingTimeInterval(-age)
            let p = changedEntityProvenance(original,
                sourcePTS: CMTime(seconds: 1 - age, preferredTimescale: 1000), sourceDate: sourceDate)
            let value = try XCTUnwrap(UserMovementEntityObservation(
                entityRef: p.observationRef, trackID: p.identity.trackID,
                visibility: .visible, region: p.measuredRegion, provenance: p))
            let result = entityAdapterFrame(fixture, observations: [value],
                envelope: entityEnvelope(fixture, sourceDate: sourceDate), evaluatedAt: evidenceTime.addingTimeInterval(0.005))
            XCTAssertEqual(result != nil, expected,
                           "Movement retains its .8s semantic window despite 1.2s tracking and fresh geometry")
        }
    }

    func testEntityObservationRejectsAlteredReferenceTrackRegionAndGeometry() throws {
        let fixture = try entityMeasurementFixture()
        let good = try XCTUnwrap(fixture.observations.first)
        let p = try XCTUnwrap(good.provenance)
        XCTAssertNil(UserMovementEntityObservation(entityRef: "other", trackID: good.trackID,
            visibility: good.visibility, region: good.region, provenance: p))
        XCTAssertNil(UserMovementEntityObservation(entityRef: good.entityRef, trackID: "other",
            visibility: good.visibility, region: good.region, provenance: p))
        XCTAssertNil(UserMovementEntityObservation(entityRef: good.entityRef, trackID: good.trackID,
            visibility: good.visibility, region: NormalizedRect(x: 0.4, y: 0.1, width: 0.2, height: 0.3), provenance: p))
        XCTAssertNil(UserMovementEntityObservation(entityRef: good.entityRef, trackID: good.trackID,
            visibility: .absent, region: nil, provenance: p))
        let corrupt = [
            changedEntityProvenance(p, visibleBox: CGRect(x: 0.4, y: 0.1, width: 0.2, height: 0.3)),
            changedEntityProvenance(p, clippedFraction: .nan),
            changedEntityProvenance(p, clippedFraction: 0.5),
            changedEntityProvenance(p, clippedEdges: 1),
            changedEntityProvenance(p, slot: 4),
            changedEntityProvenance(p, rawBox: CGRect(x: 0.1, y: 0.1, width: -0.2, height: 0.3))
        ]
        for value in corrupt {
            XCTAssertNil(UserMovementEntityObservation(entityRef: good.entityRef, trackID: good.trackID,
                visibility: good.visibility, region: good.region, provenance: value))
        }
    }

    func testEntityObservationRejectsCorruptSourceProvenanceAndAdapterRejectsLegacyRows() throws {
        let fixture = try entityMeasurementFixture()
        let good = try XCTUnwrap(fixture.observations.first)
        let p = try XCTUnwrap(good.provenance)
        let corrupt = [
            changedEntityProvenance(p, frameID: ""),
            changedEntityProvenance(p, sequence: 0),
            changedEntityProvenance(p, orientationRaw: 0),
            changedEntityProvenance(p, sourceID: ""),
            changedEntityProvenance(p, sourceID: p.frameID),
            changedEntityProvenance(p, sourcePTS: .invalid),
            changedEntityProvenance(p, sourcePTS: p.samplePresentationTimestamp),
            changedEntityProvenance(p, sourcePTS: CMTime(value: 2, timescale: 1)),
            changedEntityProvenance(p, sourceDate: evidenceTime.addingTimeInterval(0.001)),
            changedEntityProvenance(p, geometryDate: evidenceTime.addingTimeInterval(-0.001)),
            changedEntityProvenance(p, support: .nan),
            changedEntityProvenance(p, support: -0.01),
            changedEntityProvenance(p, quality: .nan),
            changedEntityProvenance(p, quality: 0.749),
            changedEntityProvenance(p, quality: 1.01)
        ]
        for value in corrupt {
            XCTAssertNil(UserMovementEntityObservation(entityRef: good.entityRef, trackID: good.trackID,
                visibility: good.visibility, region: good.region, provenance: value))
        }
        let legacy = try XCTUnwrap(UserMovementEntityObservation(
            entityRef: good.entityRef, trackID: good.trackID, visibility: good.visibility, region: good.region))
        XCTAssertNil(entityAdapterFrame(fixture, observations: [legacy]))
        XCTAssertNil(entityAdapterFrame(fixture, observations: [good, good]))
        XCTAssertNotNil(entityAdapterFrame(fixture, observations: []),
                        "No entity measurements does not invalidate independent frame-global evidence")
    }
}
