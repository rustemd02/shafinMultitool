//
//  ActionVerifierTests.swift
//  shafinMultitoolTests
//
//  M2-025 VerificationOwner: paired fixture matrix for the pure verifier.
//

import XCTest
@testable import shafinMultitool

final class ActionVerifierTests: XCTestCase {

    private let startDate = Date(timeIntervalSince1970: 20_000)
    private let identity = SubjectTrackIdentity(
        trackID: "track-verifier-subject",
        firstSeenFrameID: "before",
        generation: 9
    )

    private func lifecycle(
        generation: UInt64 = 9,
        orientation: CameraCoachOrientation = .portrait,
        lensID: String? = "wide",
        routeActive: Bool = true,
        backgrounded: Bool = false,
        sceneSignature: String? = "scene-a"
    ) -> SubjectTrackLifecycleContext {
        SubjectTrackLifecycleContext(
            generation: generation,
            orientation: orientation,
            lensID: lensID,
            routeActive: routeActive,
            isAppBackgrounded: backgrounded,
            sceneSignature: sceneSignature
        )
    }

    private func frame(
        id: String,
        capturedAt: Date,
        actionID: String,
        x: Double = 0.20,
        generation: UInt64 = 9,
        orientation: CameraCoachOrientation = .portrait,
        source: FeatureSourceID = .vision,
        bindSubject: Bool? = nil,
        metrics: UserMovementMetrics = UserMovementMetrics(),
        still: Bool = true,
        calibrated: Bool = true,
        calibrationVersion: String? = "cal1",
        measuredAt: Date? = nil,
        sceneSignature: String? = "scene-a"
    ) -> UserMovementFrame {
        let family = UserMovementObserver.actionFamily(for: actionID)
        let needsSubject = family?.requiresSubjectBinding == true
        let shouldBind = bindSubject ?? needsSubject
        let region = NormalizedRect(x: x, y: 0.25, width: 0.20, height: 0.40)
        let measured = measuredAt ?? capturedAt
        let binding: UserMovementSubjectBinding? = shouldBind
            ? UserMovementSubjectBinding(
                identity: identity,
                frameID: id,
                region: region,
                source: source,
                coordinateSpace: .subjectTarget,
                measuredAt: measured,
                confidence: 0.92
            )
            : nil
        let evidence = UserMovementEvidence(
            capturedAt: capturedAt,
            evaluatedAt: capturedAt,
            lensGeneration: generation,
            subjectTrackID: binding?.identity.trackID,
            subjectBinding: binding,
            orientation: orientation,
            isCalibrated: calibrated,
            calibrationVersion: calibrationVersion,
            featureMeasuredAt: Dictionary(uniqueKeysWithValues: UserMovementActionFamily.allCases.map { ($0, measured) }),
            featureConfidence: Dictionary(uniqueKeysWithValues: UserMovementActionFamily.allCases.map { ($0, 0.92) }),
            sourceAvailability: Dictionary(uniqueKeysWithValues: UserMovementActionFamily.allCases.map { ($0, true) })
        )
        _ = sceneSignature
        return UserMovementFrame(
            frameID: id,
            subjectRegion: shouldBind ? region : nil,
            meanLuma: 0.5,
            motionIsStill: still,
            metrics: metrics,
            evidence: evidence
        )
    }

    private func geometry(
        frameID: String,
        orientation: CameraCoachOrientation = .portrait,
        sourceSize: CGSize = CGSize(width: 1920, height: 1080),
        destinationSize: CGSize = CGSize(width: 390, height: 844),
        mirrored: Bool = false
    ) -> ActionVerificationGeometryContext {
        ActionVerificationGeometryContext(
            frameID: frameID,
            displayTransform: CameraDisplayTransform(
                orientation: orientation,
                isMirrored: mirrored
            ),
            aspectFillTransform: AspectFillTransform(
                sourceSize: sourceSize,
                destinationSize: destinationSize
            )
        )
    }

    private func input(
        actionID: String,
        before: UserMovementFrame,
        after: UserMovementFrame,
        generation: UInt64 = 9,
        beforeLifecycle: SubjectTrackLifecycleContext? = nil,
        afterLifecycle: SubjectTrackLifecycleContext? = nil,
        subjectIdentity: SubjectTrackIdentity? = nil,
        includeExpectedSubjectIdentity: Bool = true,
        safetyRegressions: [ActionVerificationSafetyRegression] = [],
        includeGeometry: Bool = true,
        beforeGeometry: ActionVerificationGeometryContext? = nil,
        afterGeometry: ActionVerificationGeometryContext? = nil,
        includeExposureEvidence: Bool = true,
        beforeExposureState: ActionVerificationExposureState? = nil,
        afterExposureState: ActionVerificationExposureState? = nil
    ) -> ActionVerificationInput {
        let resolvedBeforeLifecycle = beforeLifecycle ?? lifecycle(generation: generation)
        let resolvedAfterLifecycle = afterLifecycle ?? lifecycle(generation: generation)
        let family = UserMovementObserver.actionFamily(for: actionID)
        let expectedSubjectIdentity = includeExpectedSubjectIdentity
            ? (subjectIdentity ?? (UserMovementObserver.actionFamily(for: actionID)?.requiresSubjectBinding == true ? identity : nil))
            : nil
        let defaultGeometry: (ActionVerificationGeometryContext?, ActionVerificationGeometryContext?)
        if includeGeometry, family?.requiresSubjectBinding == true {
            defaultGeometry = (
                geometry(
                    frameID: before.frameID,
                    orientation: resolvedBeforeLifecycle.orientation
                ),
                geometry(
                    frameID: after.frameID,
                    orientation: resolvedAfterLifecycle.orientation
                )
            )
        } else {
            defaultGeometry = (nil, nil)
        }
        let defaultExposureState: (ActionVerificationExposureState?, ActionVerificationExposureState?)
        if includeExposureEvidence, family == .lightExposure {
            defaultExposureState = (.stable, .stable)
        } else {
            defaultExposureState = (nil, nil)
        }
        return ActionVerificationInput(
            token: CoachingEpisodeToken(rawValue: UUID(), generation: generation),
            actionID: actionID,
            before: before,
            after: after,
            beforeLifecycle: resolvedBeforeLifecycle,
            afterLifecycle: resolvedAfterLifecycle,
            beforeGeometry: beforeGeometry ?? defaultGeometry.0,
            afterGeometry: afterGeometry ?? defaultGeometry.1,
            beforeExposureState: beforeExposureState ?? defaultExposureState.0,
            afterExposureState: afterExposureState ?? defaultExposureState.1,
            subjectIdentity: expectedSubjectIdentity,
            safetyRegressions: safetyRegressions
        )
    }

    private func decision(_ result: ActionVerificationResult) -> ActionVerificationDecision {
        result.decision
    }

    func testPlacementReturnsImprovedUnchangedAndWorse() {
        let action = SemanticActionType.moveSubjectRight.rawValue
        let before = frame(id: "placement-before", capturedAt: startDate, actionID: action)

        let improved = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: frame(
                id: "placement-improved",
                capturedAt: startDate.addingTimeInterval(0.1),
                actionID: action,
                x: 0.28
            )
        ))
        XCTAssertEqual(decision(improved), .comparable(outcome: .improved))
        XCTAssertEqual(improved.deltas.first?.metric, .placement)
        XCTAssertEqual(improved.deltas.first?.directedDelta ?? .nan, 0.08, accuracy: 0.0001)

        let unchanged = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: frame(
                id: "placement-unchanged",
                capturedAt: startDate.addingTimeInterval(0.2),
                actionID: action,
                x: 0.21
            )
        ))
        XCTAssertEqual(decision(unchanged), .comparable(outcome: .unchanged))

        let worse = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: frame(
                id: "placement-worse",
                // Keep the baseline inside the canonical Vision freshness
                // window; outcome direction, not elapsed time, is under test.
                capturedAt: startDate.addingTimeInterval(0.2),
                actionID: action,
                x: 0.10
            )
        ))
        XCTAssertEqual(decision(worse), .comparable(outcome: .worse))
    }

    func testScaleAndDepthUseExistingObserverDeadbands() {
        let scaleAction = SemanticActionType.stepCloser.rawValue
        let scaleBefore = frame(
            id: "scale-before",
            capturedAt: startDate,
            actionID: scaleAction,
            metrics: UserMovementMetrics(subjectAreaRatio: 0.10)
        )
        let scaleAfter = frame(
            id: "scale-after",
            capturedAt: startDate.addingTimeInterval(0.1),
            actionID: scaleAction,
            metrics: UserMovementMetrics(subjectAreaRatio: 0.16)
        )
        let scaleResult = ActionVerifier.verify(input(
            actionID: scaleAction,
            before: scaleBefore,
            after: scaleAfter
        ))
        XCTAssertEqual(decision(scaleResult), .comparable(outcome: .improved))
        XCTAssertEqual(scaleResult.deltas.first?.metric, .scale)

        let depthAction = SemanticActionType.moveSubjectAwayFromBackground.rawValue
        let depthResult = ActionVerifier.verify(input(
            actionID: depthAction,
            before: frame(
                id: "depth-before",
                capturedAt: startDate,
                actionID: depthAction,
                metrics: UserMovementMetrics(subjectBackgroundDepth: 0.20)
            ),
            after: frame(
                id: "depth-after",
                capturedAt: startDate.addingTimeInterval(0.1),
                actionID: depthAction,
                metrics: UserMovementMetrics(subjectBackgroundDepth: 0.30)
            )
        ))
        XCTAssertEqual(decision(depthResult), .comparable(outcome: .improved))
        XCTAssertEqual(depthResult.deltas.first?.metric, .depth)
    }

    func testHorizonAndStabilityUseObjectiveFixedPredicates() {
        let horizonAction = SemanticActionType.levelHorizon.rawValue
        let horizon = ActionVerifier.verify(input(
            actionID: horizonAction,
            before: frame(
                id: "horizon-before",
                capturedAt: startDate,
                actionID: horizonAction,
                bindSubject: false,
                metrics: UserMovementMetrics(horizonAngleDegrees: 5)
            ),
            after: frame(
                id: "horizon-after",
                capturedAt: startDate.addingTimeInterval(0.1),
                actionID: horizonAction,
                bindSubject: false,
                metrics: UserMovementMetrics(horizonAngleDegrees: 0.5)
            )
        ))
        XCTAssertEqual(decision(horizon), .comparable(outcome: .fixed))

        let stabilityAction = TechnicalQualityActionType.stabilizeCamera.rawValue
        let stability = ActionVerifier.verify(input(
            actionID: stabilityAction,
            before: frame(
                id: "stability-before",
                capturedAt: startDate,
                actionID: stabilityAction,
                bindSubject: false,
                metrics: UserMovementMetrics(stabilityScore: 0.20, shakeLevel: 0.80),
                still: false
            ),
            after: frame(
                id: "stability-after",
                capturedAt: startDate.addingTimeInterval(0.1),
                actionID: stabilityAction,
                bindSubject: false,
                metrics: UserMovementMetrics(stabilityScore: 0.80, shakeLevel: 0.20),
                still: true
            )
        ))
        XCTAssertEqual(decision(stability), .comparable(outcome: .fixed))
    }

    func testExposureFaultAndFocusPredicatesCanReturnFixed() {
        let exposureAction = TechnicalQualityActionType.reduceExposure.rawValue
        let exposure = ActionVerifier.verify(input(
            actionID: exposureAction,
            before: frame(
                id: "exposure-before",
                capturedAt: startDate,
                actionID: exposureAction,
                metrics: UserMovementMetrics(
                    exposureBiasHint: 0.20,
                    exposureFault: .overexposed
                )
            ),
            after: frame(
                id: "exposure-after",
                capturedAt: startDate.addingTimeInterval(0.1),
                actionID: exposureAction,
                metrics: UserMovementMetrics(
                    exposureBiasHint: 0.10,
                    exposureFault: .clear
                )
            )
        ))
        XCTAssertEqual(decision(exposure), .comparable(outcome: .fixed))
        XCTAssertEqual(exposure.deltas.first?.metric, .exposure)

        let focusAction = TechnicalQualityActionType.refocusSubject.rawValue
        let focus = ActionVerifier.verify(input(
            actionID: focusAction,
            before: frame(
                id: "focus-before",
                capturedAt: startDate,
                actionID: focusAction,
                metrics: UserMovementMetrics(
                    focusIsDefocused: true,
                    focusReadability: 0.20
                )
            ),
            after: frame(
                id: "focus-after",
                capturedAt: startDate.addingTimeInterval(0.1),
                actionID: focusAction,
                metrics: UserMovementMetrics(
                    focusIsDefocused: false,
                    focusReadability: 0.80
                )
            )
        ))
        XCTAssertEqual(decision(focus), .comparable(outcome: .fixed))
        XCTAssertEqual(focus.deltas.first?.metric, .focus)
    }

    func testFocusWithoutLiveProvenanceIsIncomparable() {
        let action = TechnicalQualityActionType.refocusSubject.rawValue
        var before = frame(
            id: "focus-no-source-before",
            capturedAt: startDate,
            actionID: action,
            metrics: UserMovementMetrics(focusIsDefocused: true, focusReadability: 0.20)
        )
        var after = frame(
            id: "focus-no-source-after",
            capturedAt: startDate.addingTimeInterval(0.1),
            actionID: action,
            metrics: UserMovementMetrics(focusIsDefocused: false, focusReadability: 0.80)
        )
        before = withSourceAvailability(before, family: .focus, available: false)
        after = withSourceAvailability(after, family: .focus, available: false)

        let result = ActionVerifier.verify(input(actionID: action, before: before, after: after))
        XCTAssertEqual(decision(result), .incomparable(reason: .focusProvenanceMissing))
        XCTAssertTrue(result.deltas.isEmpty)
    }

    func testSubjectIdentitySourceAndCoordinateSpaceMustContinue() {
        let action = SemanticActionType.moveSubjectRight.rawValue
        let before = frame(id: "subject-before", capturedAt: startDate, actionID: action)
        let sameSubjectAfter = frame(
            id: "same-subject-after",
            capturedAt: startDate.addingTimeInterval(0.1),
            actionID: action,
            x: 0.30
        )

        XCTAssertEqual(
            decision(ActionVerifier.verify(input(
                actionID: action,
                before: before,
                after: sameSubjectAfter,
                includeExpectedSubjectIdentity: false
            ))),
            .incomparable(reason: .subjectBindingMissing)
        )
        let wrongExpectedIdentity = SubjectTrackIdentity(
            trackID: "expected-but-not-observed",
            firstSeenFrameID: "subject-before",
            generation: 9
        )
        XCTAssertEqual(
            decision(ActionVerifier.verify(input(
                actionID: action,
                before: before,
                after: sameSubjectAfter,
                subjectIdentity: wrongExpectedIdentity
            ))),
            .incomparable(reason: .subjectIdentityMismatch)
        )

        var after = frame(
            id: "subject-after",
            capturedAt: startDate.addingTimeInterval(0.1),
            actionID: action,
            x: 0.30
        )

        let changedIdentity = SubjectTrackIdentity(
            trackID: "other-subject",
            firstSeenFrameID: "subject-after",
            generation: 9
        )
        after = replacingBinding(after, identity: changedIdentity)
        XCTAssertEqual(
            decision(ActionVerifier.verify(input(actionID: action, before: before, after: after))),
            .incomparable(reason: .subjectIdentityMismatch)
        )

        let sourceChanged = replacingBinding(
            frame(id: "source-after", capturedAt: startDate.addingTimeInterval(0.1), actionID: action, x: 0.30),
            source: .detr
        )
        XCTAssertEqual(
            decision(ActionVerifier.verify(input(actionID: action, before: before, after: sourceChanged))),
            .incomparable(reason: .subjectSourceMismatch)
        )

        let spaceChanged = replacingBinding(
            frame(id: "space-after", capturedAt: startDate.addingTimeInterval(0.1), actionID: action, x: 0.30),
            coordinateSpace: .vision
        )
        XCTAssertEqual(
            decision(ActionVerifier.verify(input(actionID: action, before: before, after: spaceChanged))),
            .incomparable(reason: .subjectSpaceMismatch)
        )
    }

    func testTokenGenerationOrientationLensAndCalibrationMismatchFailClosed() {
        let action = SemanticActionType.moveSubjectRight.rawValue
        let before = frame(id: "context-before", capturedAt: startDate, actionID: action)
        let after = frame(
            id: "context-after",
            capturedAt: startDate.addingTimeInterval(0.1),
            actionID: action,
            x: 0.30
        )

        let tokenMismatch = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: after,
            generation: 8
        ))
        XCTAssertEqual(decision(tokenMismatch), .incomparable(reason: .tokenMismatch))

        let orientationMismatch = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: after,
            beforeLifecycle: lifecycle(),
            afterLifecycle: lifecycle(orientation: .landscapeLeft)
        ))
        XCTAssertEqual(decision(orientationMismatch), .incomparable(reason: .orientationMismatch))

        let lensMismatch = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: after,
            beforeLifecycle: lifecycle(),
            afterLifecycle: lifecycle(lensID: "tele")
        ))
        XCTAssertEqual(decision(lensMismatch), .incomparable(reason: .lensMismatch))

        let calibrationMismatch = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: frame(
                id: "calibration-after",
                capturedAt: startDate.addingTimeInterval(0.1),
                actionID: action,
                x: 0.30,
                calibrationVersion: "cal2"
            )
        ))
        XCTAssertEqual(decision(calibrationMismatch), .incomparable(reason: .calibrationMismatch))
    }

    func testSceneMismatchAndMissingProvenanceFailClosed() {
        let action = SemanticActionType.levelHorizon.rawValue
        let before = frame(
            id: "scene-before",
            capturedAt: startDate,
            actionID: action,
            bindSubject: false,
            metrics: UserMovementMetrics(horizonAngleDegrees: 5)
        )
        let after = frame(
            id: "scene-after",
            capturedAt: startDate.addingTimeInterval(0.1),
            actionID: action,
            bindSubject: false,
            metrics: UserMovementMetrics(horizonAngleDegrees: 2)
        )

        let mismatch = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: after,
            beforeLifecycle: lifecycle(sceneSignature: "scene-a"),
            afterLifecycle: lifecycle(sceneSignature: "scene-b")
        ))
        XCTAssertEqual(decision(mismatch), .incomparable(reason: .sceneMismatch))

        let missingOne = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: after,
            beforeLifecycle: lifecycle(sceneSignature: nil),
            afterLifecycle: lifecycle(sceneSignature: "scene-b")
        ))
        XCTAssertEqual(
            decision(missingOne),
            .incomparable(reason: .sceneProvenanceMissing)
        )

        let missingBoth = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: after,
            beforeLifecycle: lifecycle(sceneSignature: nil),
            afterLifecycle: lifecycle(sceneSignature: nil)
        ))
        XCTAssertEqual(
            decision(missingBoth),
            .incomparable(reason: .sceneProvenanceMissing)
        )
    }

    func testFramingProvenanceBlocksCropChangeAndAllowsSameContext() {
        let action = SemanticActionType.moveSubjectRight.rawValue
        let before = frame(
            id: "geometry-before",
            capturedAt: startDate,
            actionID: action
        )
        let after = frame(
            id: "geometry-after",
            capturedAt: startDate.addingTimeInterval(0.1),
            actionID: action,
            x: 0.30
        )

        let unchangedFraming = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: after
        ))
        XCTAssertEqual(
            decision(unchangedFraming),
            .comparable(outcome: .improved),
            "a matching immutable transform/crop keeps the observer's directional result"
        )

        let changedCrop = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: after,
            beforeGeometry: geometry(
                frameID: before.frameID,
                destinationSize: CGSize(width: 390, height: 844)
            ),
            afterGeometry: geometry(
                frameID: after.frameID,
                destinationSize: CGSize(width: 844, height: 390)
            )
        ))
        XCTAssertEqual(
            decision(changedCrop),
            .incomparable(reason: .geometryMismatch),
            "a favorable box change cannot be credited across an aspect-fill crop change"
        )

        let missingProvenance = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: after,
            includeGeometry: false
        ))
        XCTAssertEqual(
            decision(missingProvenance),
            .incomparable(reason: .geometryProvenanceMissing)
        )
    }

    func testInvalidFramingProvenanceFailsClosed() {
        let action = SemanticActionType.moveSubjectRight.rawValue
        let before = frame(id: "invalid-geometry-before", capturedAt: startDate, actionID: action)
        let after = frame(
            id: "invalid-geometry-after",
            capturedAt: startDate.addingTimeInterval(0.1),
            actionID: action,
            x: 0.30
        )
        let invalidTransform = CameraDisplayTransform(
            matrix: (.nan, 1, 0, -1, 0, 1),
            orientation: .portrait,
            isMirrored: false
        )
        let result = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: after,
            beforeGeometry: ActionVerificationGeometryContext(
                frameID: before.frameID,
                displayTransform: invalidTransform,
                aspectFillTransform: AspectFillTransform(
                    sourceSize: CGSize(width: 1920, height: 1080),
                    destinationSize: CGSize(width: 390, height: 844)
                )
            )
        ))
        XCTAssertEqual(decision(result), .incomparable(reason: .geometryInvalid))
    }

    func testExposureAdjustmentEvidenceIsRequiredForLightActions() {
        let action = TechnicalQualityActionType.reduceExposure.rawValue
        let before = frame(
            id: "exposure-state-before",
            capturedAt: startDate,
            actionID: action,
            metrics: UserMovementMetrics(
                exposureBiasHint: 0.20,
                exposureFault: .overexposed
            )
        )
        let after = frame(
            id: "exposure-state-after",
            capturedAt: startDate.addingTimeInterval(0.1),
            actionID: action,
            metrics: UserMovementMetrics(
                exposureBiasHint: 0.10,
                exposureFault: .clear
            )
        )

        XCTAssertEqual(
            decision(ActionVerifier.verify(input(
                actionID: action,
                before: before,
                after: after
            ))),
            .comparable(outcome: .fixed),
            "an explicit stable/not-adjusting pair retains the objective fixed predicate"
        )
        XCTAssertEqual(
            decision(ActionVerifier.verify(input(
                actionID: action,
                before: before,
                after: after,
                includeExposureEvidence: false
            ))),
            .incomparable(reason: .exposureEvidenceMissing)
        )
        XCTAssertEqual(
            decision(ActionVerifier.verify(input(
                actionID: action,
                before: before,
                after: after,
                beforeExposureState: .adjusting,
                afterExposureState: .stable
            ))),
            .incomparable(reason: .exposureAdjusting)
        )
    }

    func testSafetyRegressionBlocksPositiveAndKeepsMeasuredDelta() {
        let action = SemanticActionType.moveSubjectRight.rawValue
        let result = ActionVerifier.verify(input(
            actionID: action,
            before: frame(id: "safety-before", capturedAt: startDate, actionID: action),
            after: frame(
                id: "safety-after",
                capturedAt: startDate.addingTimeInterval(0.1),
                actionID: action,
                x: 0.30
            ),
            safetyRegressions: [.confidenceDropped]
        ))

        XCTAssertEqual(decision(result), .incomparable(reason: .safetyRegression))
        XCTAssertEqual(result.safetyRegressions, [.confidenceDropped])
        XCTAssertEqual(result.deltas.count, 1)
    }

    func testDuplicateOutOfOrderAndTimeOnlyChangeNeverBecomePositive() {
        let action = SemanticActionType.moveSubjectRight.rawValue
        let before = frame(id: "ordering-before", capturedAt: startDate, actionID: action)
        let duplicate = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: before
        ))
        XCTAssertEqual(decision(duplicate), .incomparable(reason: .duplicateFrame))

        let outOfOrder = ActionVerifier.verify(input(
            actionID: action,
            before: frame(id: "later", capturedAt: startDate.addingTimeInterval(1), actionID: action),
            after: frame(id: "earlier", capturedAt: startDate.addingTimeInterval(0.5), actionID: action, x: 0.40)
        ))
        XCTAssertEqual(decision(outOfOrder), .incomparable(reason: .outOfOrder))

        let timeOnly = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: frame(
                id: "time-only",
                capturedAt: startDate.addingTimeInterval(0.2),
                actionID: action,
                x: 0.20
            )
        ))
        XCTAssertEqual(decision(timeOnly), .comparable(outcome: .unchanged))
    }

    func testNonFiniteMetricAndMissingLifecycleAreIncomparable() {
        let action = SemanticActionType.stepCloser.rawValue
        let nanResult = ActionVerifier.verify(input(
            actionID: action,
            before: frame(
                id: "nan-before",
                capturedAt: startDate,
                actionID: action,
                metrics: UserMovementMetrics(subjectAreaRatio: .nan)
            ),
            after: frame(
                id: "nan-after",
                capturedAt: startDate.addingTimeInterval(0.1),
                actionID: action,
                metrics: UserMovementMetrics(subjectAreaRatio: 0.20)
            )
        ))
        XCTAssertEqual(decision(nanResult), .incomparable(reason: .nonFiniteMetric))

        let missingLifecycle = ActionVerifier.verify(ActionVerificationInput(
            token: CoachingEpisodeToken(rawValue: UUID(), generation: 9),
            actionID: action,
            before: frame(id: "lifecycle-before", capturedAt: startDate, actionID: action),
            after: frame(id: "lifecycle-after", capturedAt: startDate.addingTimeInterval(0.1), actionID: action, x: 0.30)
        ))
        XCTAssertEqual(decision(missingLifecycle), .incomparable(reason: .lifecycleUnavailable))
    }

    func testStaleAtEachFramesOwnEvaluationTimeRemainsIncomparable() {
        let action = SemanticActionType.moveSubjectRight.rawValue
        let result = ActionVerifier.verify(input(
            actionID: action,
            before: frame(
                id: "stale-before",
                capturedAt: startDate,
                actionID: action,
                measuredAt: startDate.addingTimeInterval(-1.0)
            ),
            after: frame(
                id: "fresh-after",
                capturedAt: startDate.addingTimeInterval(0.4),
                actionID: action,
                x: 0.30
            )
        ))

        XCTAssertEqual(decision(result), .incomparable(reason: .evidenceStale))
    }

    func testUnsupportedAndEmptyActionsDoNotProduceDeltas() {
        let before = frame(id: "unsupported-before", capturedAt: startDate, actionID: SemanticActionType.moveSubjectRight.rawValue)
        let after = frame(id: "unsupported-after", capturedAt: startDate.addingTimeInterval(0.1), actionID: SemanticActionType.moveSubjectRight.rawValue, x: 0.30)

        let empty = ActionVerifier.verify(input(actionID: "   ", before: before, after: after))
        XCTAssertEqual(decision(empty), .incomparable(reason: .emptyAction))

        let unsupported = ActionVerifier.verify(input(actionID: "invented_action", before: before, after: after))
        XCTAssertEqual(decision(unsupported), .incomparable(reason: .unsupportedAction))
    }

    private func withSourceAvailability(
        _ frame: UserMovementFrame,
        family: UserMovementActionFamily,
        available: Bool
    ) -> UserMovementFrame {
        guard let evidence = frame.evidence else { return frame }
        var sourceAvailability = evidence.sourceAvailability
        sourceAvailability[family] = available
        let replacementEvidence = UserMovementEvidence(
            capturedAt: evidence.capturedAt,
            evaluatedAt: evidence.evaluatedAt,
            lensGeneration: evidence.lensGeneration,
            subjectTrackID: evidence.subjectTrackID,
            subjectBinding: evidence.subjectBinding,
            orientation: evidence.orientation,
            isCalibrated: evidence.isCalibrated,
            calibrationVersion: evidence.calibrationVersion,
            featureMeasuredAt: evidence.featureMeasuredAt,
            featureConfidence: evidence.featureConfidence,
            sourceAvailability: sourceAvailability
        )
        return UserMovementFrame(
            frameID: frame.frameID,
            subjectRegion: frame.subjectRegion,
            meanLuma: frame.meanLuma,
            motionIsStill: frame.motionIsStill,
            metrics: frame.metrics,
            evidence: replacementEvidence
        )
    }

    private func replacingBinding(
        _ frame: UserMovementFrame,
        identity: SubjectTrackIdentity? = nil,
        source: FeatureSourceID? = nil,
        coordinateSpace: CameraCoordinateSpaceV2? = nil
    ) -> UserMovementFrame {
        guard let evidence = frame.evidence,
              let binding = evidence.subjectBinding,
              let replacement = UserMovementSubjectBinding(
                identity: identity ?? binding.identity,
                frameID: binding.frameID,
                region: binding.region,
                source: source ?? binding.source,
                coordinateSpace: coordinateSpace ?? binding.coordinateSpace,
                measuredAt: binding.measuredAt,
                confidence: binding.confidence
              ) else {
            return frame
        }
        let replacementEvidence = UserMovementEvidence(
            capturedAt: evidence.capturedAt,
            evaluatedAt: evidence.evaluatedAt,
            lensGeneration: evidence.lensGeneration,
            subjectTrackID: replacement.identity.trackID,
            subjectBinding: replacement,
            orientation: evidence.orientation,
            isCalibrated: evidence.isCalibrated,
            calibrationVersion: evidence.calibrationVersion,
            featureMeasuredAt: evidence.featureMeasuredAt,
            featureConfidence: evidence.featureConfidence,
            sourceAvailability: evidence.sourceAvailability
        )
        return UserMovementFrame(
            frameID: frame.frameID,
            subjectRegion: frame.subjectRegion,
            meanLuma: frame.meanLuma,
            motionIsStill: frame.motionIsStill,
            metrics: frame.metrics,
            evidence: replacementEvidence
        )
    }
}
