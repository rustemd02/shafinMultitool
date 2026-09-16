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
        afterExposureState: ActionVerificationExposureState? = nil,
        scope: ActionVerificationScope = .none,
        absenceEvidence: [ActionVerificationAbsenceEvidence] = [],
        matchedMediaMappingRef: String? = nil,
        beforeIntentRevision: Int? = nil,
        afterIntentRevision: Int? = nil
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
            scope: scope,
            absenceEvidence: absenceEvidence,
            matchedMediaMappingRef: matchedMediaMappingRef,
            beforeIntentRevision: beforeIntentRevision,
            afterIntentRevision: afterIntentRevision,
            safetyRegressions: safetyRegressions
        )
    }

    /// Attaches C04.2 entity observations to a fixture frame without changing
    /// any of the existing provenance values.
    private func entityFrame(
        id: String,
        capturedAt: Date,
        actionID: String,
        x: Double = 0.20,
        entities: [UserMovementEntityObservation],
        metrics: UserMovementMetrics = UserMovementMetrics(),
        still: Bool = true,
        generation: UInt64 = 9
    ) -> UserMovementFrame {
        let base = frame(
            id: id,
            capturedAt: capturedAt,
            actionID: actionID,
            x: x,
            generation: generation,
            metrics: metrics,
            still: still
        )
        guard let evidence = base.evidence else { return base }
        return UserMovementFrame(
            frameID: base.frameID,
            subjectRegion: base.subjectRegion,
            meanLuma: base.meanLuma,
            motionIsStill: base.motionIsStill,
            metrics: base.metrics,
            evidence: evidence,
            entityObservations: entities
        )
    }

    private func entity(
        _ ref: String,
        track: String,
        x: Double,
        y: Double = 0.30,
        width: Double = 0.20,
        height: Double = 0.30
    ) -> UserMovementEntityObservation {
        UserMovementEntityObservation(
            entityRef: ref,
            trackID: track,
            visibility: .visible,
            region: NormalizedRect(x: x, y: y, width: width, height: height)
        )!
    }

    private func absentEntity(_ ref: String, track: String) -> UserMovementEntityObservation {
        UserMovementEntityObservation(
            entityRef: ref,
            trackID: track,
            visibility: .absent,
            region: nil
        )!
    }

    private func decision(_ result: ActionVerificationResult) -> ActionVerificationDecision {
        result.decision
    }

    private func assertFiniteDiagnostics(
        _ result: ActionVerificationResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            result.deltas.allSatisfy {
                $0.before.isFinite
                    && $0.after.isFinite
                    && $0.delta.isFinite
                    && $0.directedDelta.isFinite
                    && $0.deadband.isFinite
                    && $0.deadband >= 0
            },
            "every retained diagnostic delta must be finite",
            file: file,
            line: line
        )
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
        XCTAssertEqual(tokenMismatch.deltas.count, 1)
        assertFiniteDiagnostics(tokenMismatch)

        let orientationMismatch = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: after,
            beforeLifecycle: lifecycle(),
            afterLifecycle: lifecycle(orientation: .landscapeLeft)
        ))
        XCTAssertEqual(decision(orientationMismatch), .incomparable(reason: .orientationMismatch))
        XCTAssertEqual(orientationMismatch.deltas.count, 1)
        assertFiniteDiagnostics(orientationMismatch)

        let lensMismatch = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: after,
            beforeLifecycle: lifecycle(),
            afterLifecycle: lifecycle(lensID: "tele")
        ))
        XCTAssertEqual(decision(lensMismatch), .incomparable(reason: .lensMismatch))
        XCTAssertEqual(lensMismatch.deltas.count, 1)
        assertFiniteDiagnostics(lensMismatch)

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
        // The canonical observer rejects calibration provenance before it can
        // expose a numeric comparison. The verifier must retain any such
        // diagnostics when available, but must not invent one by bypassing the
        // observer's fail-closed validation.
        assertFiniteDiagnostics(calibrationMismatch)
    }

    func testUncalibratedMeasuredImprovementCannotBecomeSuccessfulVerification() {
        let action = SemanticActionType.levelHorizon.rawValue
        let before = frame(id: "uncalibrated-before", capturedAt: startDate, actionID: action,
                           metrics: UserMovementMetrics(horizonAngleDegrees: 12),
                           calibrated: false, calibrationVersion: nil)
        let after = frame(id: "uncalibrated-after", capturedAt: startDate.addingTimeInterval(0.1),
                          actionID: action, metrics: UserMovementMetrics(horizonAngleDegrees: 1),
                          calibrated: false, calibrationVersion: nil)
        XCTAssertEqual(before.metrics.horizonAngleDegrees, 12)
        XCTAssertEqual(after.metrics.horizonAngleDegrees, 1)
        let result = ActionVerifier.verify(input(actionID: action, before: before, after: after))
        XCTAssertEqual(decision(result), .incomparable(reason: .calibrationMismatch))
        XCTAssertTrue(result.deltas.isEmpty,
                      "the verifier must retain its calibration gate rather than invent admissible deltas")
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
        XCTAssertEqual(mismatch.deltas.count, 1)
        assertFiniteDiagnostics(mismatch)

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
        XCTAssertEqual(missingOne.deltas.count, 1)
        assertFiniteDiagnostics(missingOne)

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
        XCTAssertEqual(missingBoth.deltas.count, 1)
        assertFiniteDiagnostics(missingBoth)

        let whitespaceOnly = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: after,
            beforeLifecycle: lifecycle(sceneSignature: " \t\n"),
            afterLifecycle: lifecycle(sceneSignature: "scene-b")
        ))
        XCTAssertEqual(
            decision(whitespaceOnly),
            .incomparable(reason: .sceneProvenanceMissing)
        )
        XCTAssertEqual(whitespaceOnly.deltas.count, 1)
        assertFiniteDiagnostics(whitespaceOnly)

        let nonEmptyWhitespaceIsIdentity = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: after,
            beforeLifecycle: lifecycle(sceneSignature: " scene-a "),
            afterLifecycle: lifecycle(sceneSignature: " scene-a ")
        ))
        XCTAssertEqual(
            decision(nonEmptyWhitespaceIsIdentity),
            .comparable(outcome: .improved),
            "non-empty scene identity is compared exactly; only all-whitespace values are missing"
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
        XCTAssertEqual(changedCrop.deltas.count, 1)
        assertFiniteDiagnostics(changedCrop)

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
        XCTAssertEqual(missingProvenance.deltas.count, 1)
        assertFiniteDiagnostics(missingProvenance)
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
        XCTAssertEqual(result.deltas.count, 1)
        assertFiniteDiagnostics(result)
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
        let missingState = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: after,
            includeExposureEvidence: false
        ))
        XCTAssertEqual(
            decision(missingState),
            .incomparable(reason: .exposureEvidenceMissing)
        )
        XCTAssertEqual(missingState.deltas.count, 1)
        assertFiniteDiagnostics(missingState)

        let adjustingState = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: after,
            beforeExposureState: .adjusting,
            afterExposureState: .stable
        ))
        XCTAssertEqual(
            decision(adjustingState),
            .incomparable(reason: .exposureAdjusting)
        )
        XCTAssertEqual(adjustingState.deltas.count, 1)
        assertFiniteDiagnostics(adjustingState)
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
        XCTAssertEqual(missingLifecycle.deltas.count, 1)
        assertFiniteDiagnostics(missingLifecycle)
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

    // MARK: - C04.2: target scope, expected absence, N7 order

    /// (a) Only the commanded object's change counts. Movement of a different
    /// object (lampB) must not complete the lampA step, even when the primary
    /// subject itself moved.
    func testCommandedTargetScopeRejectsAnotherEntityMovement() {
        let action = SemanticActionType.moveObjectLeft.rawValue
        let scope = ActionVerificationScope(
            targetRefs: ["lampA"],
            protectedRefs: ["person1"],
            allowedChanges: [.targetPosition]
        )
        let person = entity("person1", track: "tp", x: 0.05, y: 0.20, width: 0.25, height: 0.60)

        let before = entityFrame(
            id: "scope-before",
            capturedAt: startDate,
            actionID: action,
            x: 0.50,
            entities: [entity("lampA", track: "ta", x: 0.45), entity("lampB", track: "tb", x: 0.70), person]
        )
        let commandedMoved = entityFrame(
            id: "scope-commanded-moved",
            capturedAt: startDate.addingTimeInterval(0.1),
            actionID: action,
            x: 0.40,
            entities: [entity("lampA", track: "ta", x: 0.36), entity("lampB", track: "tb", x: 0.70), person]
        )
        XCTAssertEqual(
            decision(ActionVerifier.verify(input(
                actionID: action,
                before: before,
                after: commandedMoved,
                scope: scope
            ))),
            .comparable(outcome: .improved),
            "the commanded lampA moving left is the action's effect"
        )

        // The subject and lampB move; lampA (the commanded object) does not.
        let otherMoved = entityFrame(
            id: "scope-other-moved",
            capturedAt: startDate.addingTimeInterval(0.1),
            actionID: action,
            x: 0.30,
            entities: [entity("lampA", track: "ta", x: 0.45), entity("lampB", track: "tb", x: 0.58), person]
        )
        let unrelated = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: otherMoved,
            scope: scope
        ))
        XCTAssertEqual(
            decision(unrelated),
            .comparable(outcome: .unchanged),
            "a sufficient motor delta on another object must not yield improved"
        )
        XCTAssertEqual(unrelated.reasonCode, .noEffect)

        // A protected ref that regresses after a comparable pair is worse.
        let protectedLost = entityFrame(
            id: "scope-protected-lost",
            capturedAt: startDate.addingTimeInterval(0.1),
            actionID: action,
            x: 0.40,
            entities: [
                entity("lampA", track: "ta", x: 0.36),
                entity("lampB", track: "tb", x: 0.70),
                absentEntity("person1", track: "tp")
            ]
        )
        let worse = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: protectedLost,
            scope: scope
        ))
        XCTAssertEqual(decision(worse), .comparable(outcome: .worse))
        XCTAssertEqual(worse.reasonCode, .regression)
        XCTAssertEqual(worse.protectedRegressions.map(\.entityRef), ["person1"])
        XCTAssertEqual(worse.goalSatisfied, false)
    }

    func testPartialTargetRectangleCannotProveDisplacementFromChangingIntersection() throws {
        let action = SemanticActionType.moveObjectLeft.rawValue
        let scope = ActionVerificationScope(targetRefs: ["lampA"], allowedChanges: [.targetPosition])
        let partial = try XCTUnwrap(UserMovementEntityObservation(
            entityRef: "lampA", trackID: "ta", visibility: .partial,
            region: NormalizedRect(x: 0.30, y: 0, width: 0.2, height: 0.2)))
        XCTAssertTrue(partial.isObserved, "Keep the measurement for diagnostics")
        XCTAssertFalse(partial.hasComparableGeometry)
        for partialBefore in [false, true] {
            let before = entityFrame(id: "partial-before", capturedAt: startDate, actionID: action,
                entities: [partialBefore ? partial : entity("lampA", track: "ta", x: 0.45)])
            let after = entityFrame(id: "partial-after", capturedAt: startDate.addingTimeInterval(0.1),
                actionID: action, entities: [partialBefore ? entity("lampA", track: "ta", x: 0.20) : partial])
            let result = ActionVerifier.verify(input(actionID: action, before: before, after: after, scope: scope))
            XCTAssertEqual(decision(result), .incomparable(reason: .targetMissing))
            XCTAssertNil(result.goalSatisfied)
        }
    }

    func testPartialProtectedRectangleCannotCertifyPreservationDuringTargetMove() throws {
        let action = SemanticActionType.moveObjectLeft.rawValue
        let before = entityFrame(id: "protected-before", capturedAt: startDate, actionID: action,
            entities: [entity("lampA", track: "ta", x: 0.45), entity("lampB", track: "tb", x: 0.70)])
        let partial = try XCTUnwrap(UserMovementEntityObservation(
            entityRef: "lampB", trackID: "tb", visibility: .partial,
            region: NormalizedRect(x: 0.7, y: 0, width: 0.2, height: 0.2)))
        let after = entityFrame(id: "protected-after", capturedAt: startDate.addingTimeInterval(0.1),
            actionID: action, entities: [entity("lampA", track: "ta", x: 0.35), partial])
        let result = ActionVerifier.verify(input(actionID: action, before: before, after: after,
            scope: ActionVerificationScope(targetRefs: ["lampA"], protectedRefs: ["lampB"],
                                           allowedChanges: [.targetPosition])))
        XCTAssertEqual(decision(result), .incomparable(reason: .protectedEvidenceMissing))
        XCTAssertNil(result.goalSatisfied)
    }

    func testExplicitAbsenceRetainsItsSeparateProofForInitiallyPartialRectangles() throws {
        let action = SemanticActionType.removeDistractingObject.rawValue
        let target = try XCTUnwrap(UserMovementEntityObservation(
            entityRef: "lampA", trackID: "ta", visibility: .partial,
            region: NormalizedRect(x: 0.4, y: 0, width: 0.2, height: 0.2)))
        let protected = try XCTUnwrap(UserMovementEntityObservation(
            entityRef: "lampB", trackID: "tb", visibility: .partial,
            region: NormalizedRect(x: 0.7, y: 0, width: 0.2, height: 0.2)))
        let before = entityFrame(id: "partial-exit-before", capturedAt: startDate, actionID: action,
            entities: [target, protected])
        let after = entityFrame(id: "partial-exit-after", capturedAt: startDate.addingTimeInterval(0.1),
            actionID: action, entities: [absentEntity("lampA", track: "ta"), protected])
        let scope = ActionVerificationScope(targetRefs: ["lampA"], protectedRefs: ["lampB"],
                                            expectedAbsenceRefs: ["lampA"])
        for confirmed in [false, true] {
            let result = ActionVerifier.verify(input(actionID: action, before: before, after: after,
                scope: scope, absenceEvidence: [ActionVerificationAbsenceEvidence(
                    entityRef: "lampA", observedPresentBefore: true, observedExitFromRegion: confirmed,
                    regionConfirmedFreeAfter: confirmed, associationLossExplained: confirmed)]))
            XCTAssertEqual(decision(result), confirmed
                ? .comparable(outcome: .improved) : .incomparable(reason: .expectedAbsenceUnverified))
            XCTAssertEqual(result.goalSatisfied, confirmed ? true : nil)
        }
    }

    func testScopedObjectAreaCannotUseUnrelatedPrimarySubjectScalar() {
        for action in [SemanticActionType.moveObjectForward.rawValue, SemanticActionType.moveObjectBack.rawValue] {
            let target = entity("lampA", track: "ta", x: 0.45)
            let before = entityFrame(id: "area-before", capturedAt: startDate, actionID: action,
                entities: [target], metrics: UserMovementMetrics(subjectAreaRatio: 0.10))
            let after = entityFrame(id: "area-after", capturedAt: startDate.addingTimeInterval(0.1),
                actionID: action, entities: [target], metrics: UserMovementMetrics(subjectAreaRatio: 0.30))
            let result = ActionVerifier.verify(input(actionID: action, before: before, after: after,
                scope: ActionVerificationScope(targetRefs: ["lampA"])))
            XCTAssertEqual(decision(result), .incomparable(reason: .unsupportedAction))
            XCTAssertTrue(result.deltas.isEmpty)
            XCTAssertNil(result.goalSatisfied)
        }
    }

    func testMultipleDeclaredTargetsCannotUseOnlyTheFirstDisplacement() {
        let action = SemanticActionType.moveObjectLeft.rawValue
        let before = entityFrame(id: "multi-before", capturedAt: startDate, actionID: action,
            entities: [entity("lampA", track: "ta", x: 0.45), entity("lampB", track: "tb", x: 0.70)])
        let after = entityFrame(id: "multi-after", capturedAt: startDate.addingTimeInterval(0.1), actionID: action,
            entities: [entity("lampA", track: "ta", x: 0.35), entity("lampB", track: "tb", x: 0.70)])
        let result = ActionVerifier.verify(input(actionID: action, before: before, after: after,
            scope: ActionVerificationScope(targetRefs: ["lampA", "lampB"], allowedChanges: [.targetPosition])))
        XCTAssertEqual(decision(result), .incomparable(reason: .unsupportedAction))
        XCTAssertNil(result.goalSatisfied)
    }

    /// (b) A vanished bbox is not a confirmed removal: expected absence needs
    /// an observed present baseline, an observed exit, a confirmed free region
    /// and no unexplained association loss.
    func testExpectedAbsenceRequiresConfirmedFreeRegionAndObservedExit() {
        let action = SemanticActionType.removeDistractingObject.rawValue
        let scope = ActionVerificationScope(
            targetRefs: ["lampA"],
            protectedRefs: ["person1"],
            expectedAbsenceRefs: ["lampA"]
        )
        let person = entity("person1", track: "tp", x: 0.05, y: 0.20, width: 0.25, height: 0.60)
        let before = entityFrame(
            id: "absence-before",
            capturedAt: startDate,
            actionID: action,
            entities: [entity("lampA", track: "ta", x: 0.45), person]
        )
        let after = entityFrame(
            id: "absence-after",
            capturedAt: startDate.addingTimeInterval(0.1),
            actionID: action,
            entities: [absentEntity("lampA", track: "ta"), person]
        )
        let confirmed = ActionVerificationAbsenceEvidence(
            entityRef: "lampA",
            observedPresentBefore: true,
            observedExitFromRegion: true,
            regionConfirmedFreeAfter: true,
            associationLossExplained: true
        )

        let removed = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: after,
            scope: scope,
            absenceEvidence: [confirmed]
        ))
        XCTAssertEqual(decision(removed), .comparable(outcome: .improved))
        XCTAssertEqual(removed.reasonCode, .verified)
        XCTAssertEqual(removed.goalSatisfied, true)
        assertFiniteDiagnostics(removed)

        // A missing free-region confirmation is incomparable, not success.
        let unconfirmed = ActionVerifier.verify(input(
            actionID: action,
            before: before,
            after: after,
            scope: scope,
            absenceEvidence: [ActionVerificationAbsenceEvidence(
                entityRef: "lampA",
                observedPresentBefore: true,
                observedExitFromRegion: true,
                regionConfirmedFreeAfter: false,
                associationLossExplained: true
            )]
        ))
        XCTAssertEqual(decision(unconfirmed), .incomparable(reason: .expectedAbsenceUnverified))
        XCTAssertEqual(unconfirmed.reasonCode, .missingEvidence)
        XCTAssertNil(unconfirmed.goalSatisfied)

        // An omitted after observation (a "disappeared bbox") is not an exit.
        let omitted = entityFrame(
            id: "absence-omitted",
            capturedAt: startDate.addingTimeInterval(0.1),
            actionID: action,
            entities: [person]
        )
        XCTAssertEqual(
            decision(ActionVerifier.verify(input(
                actionID: action,
                before: before,
                after: omitted,
                scope: scope,
                absenceEvidence: [confirmed]
            ))),
            .incomparable(reason: .expectedAbsenceUnverified)
        )

        // Still visible after the movement: unchanged, not improved.
        let stillVisible = entityFrame(
            id: "absence-still-visible",
            capturedAt: startDate.addingTimeInterval(0.1),
            actionID: action,
            entities: [entity("lampA", track: "ta", x: 0.45), person]
        )
        XCTAssertEqual(
            decision(ActionVerifier.verify(input(
                actionID: action,
                before: before,
                after: stillVisible,
                scope: scope,
                absenceEvidence: [confirmed]
            ))),
            .comparable(outcome: .unchanged)
        )
    }

    /// (c) An operation without a qualified metric stays unsupported. A
    /// horizon change is not evidence that a background obstruction was fixed.
    func testUnsupportedBackgroundActionNeverBecomesImproved() {
        let action = SemanticActionType.changeCameraAngle.rawValue
        let before = frame(
            id: "angle-before",
            capturedAt: startDate,
            actionID: action,
            metrics: UserMovementMetrics(horizonAngleDegrees: 8)
        )
        let after = frame(
            id: "angle-after",
            capturedAt: startDate.addingTimeInterval(0.1),
            actionID: action,
            x: 0.30,
            metrics: UserMovementMetrics(horizonAngleDegrees: 0)
        )
        let result = ActionVerifier.verify(input(actionID: action, before: before, after: after))
        XCTAssertEqual(decision(result), .incomparable(reason: .unsupportedAction))
        XCTAssertEqual(result.reasonCode, .unsupportedVerifier)
        XCTAssertNil(result.goalSatisfied)
        XCTAssertNil(result.outcome)
    }

    /// (d) `goalSatisfied` is reported independently from the outcome: an
    /// established predicate is `true`, a partial directional improvement is
    /// `false` but present, and an incomparable pair has no value.
    func testGoalSatisfiedIsReportedIndependentlyFromOutcome() {
        let horizonAction = SemanticActionType.levelHorizon.rawValue
        let fixed = ActionVerifier.verify(input(
            actionID: horizonAction,
            before: frame(
                id: "goal-fixed-before",
                capturedAt: startDate,
                actionID: horizonAction,
                metrics: UserMovementMetrics(horizonAngleDegrees: 8)
            ),
            after: frame(
                id: "goal-fixed-after",
                capturedAt: startDate.addingTimeInterval(0.1),
                actionID: horizonAction,
                metrics: UserMovementMetrics(horizonAngleDegrees: 0)
            )
        ))
        XCTAssertEqual(decision(fixed), .comparable(outcome: .fixed))
        XCTAssertEqual(fixed.goalSatisfied, true)

        let directionalAction = SemanticActionType.moveSubjectRight.rawValue
        let partial = ActionVerifier.verify(input(
            actionID: directionalAction,
            before: frame(id: "goal-partial-before", capturedAt: startDate, actionID: directionalAction, x: 0.20),
            after: frame(
                id: "goal-partial-after",
                capturedAt: startDate.addingTimeInterval(0.1),
                actionID: directionalAction,
                x: 0.32
            )
        ))
        XCTAssertEqual(decision(partial), .comparable(outcome: .improved))
        XCTAssertEqual(partial.goalSatisfied, false, "a partial improvement does not assert the goal")

        let unsupported = ActionVerifier.verify(input(
            actionID: SemanticActionType.changeCameraAngle.rawValue,
            before: frame(id: "goal-unknown-before", capturedAt: startDate, actionID: SemanticActionType.changeCameraAngle.rawValue),
            after: frame(
                id: "goal-unknown-after",
                capturedAt: startDate.addingTimeInterval(0.1),
                actionID: SemanticActionType.changeCameraAngle.rawValue,
                x: 0.30
            )
        ))
        XCTAssertNil(unsupported.goalSatisfied)
    }

    /// (e) N7 order: scope/identity violations are incomparable even when the
    /// scalar measurement improved.
    func testN7OrderMakesScopeAndIdentityViolationsIncomparableDespiteScalarGrowth() {
        let horizonAction = SemanticActionType.levelHorizon.rawValue
        let levelBefore = frame(
            id: "n7-horizon-before",
            capturedAt: startDate,
            actionID: horizonAction,
            metrics: UserMovementMetrics(horizonAngleDegrees: 8)
        )
        let levelAfter = frame(
            id: "n7-horizon-after",
            capturedAt: startDate.addingTimeInterval(0.1),
            actionID: horizonAction,
            metrics: UserMovementMetrics(horizonAngleDegrees: 0)
        )
        let generationMismatch = ActionVerifier.verify(input(
            actionID: horizonAction,
            before: levelBefore,
            after: levelAfter,
            afterLifecycle: lifecycle(generation: 10)
        ))
        XCTAssertEqual(decision(generationMismatch), .incomparable(reason: .tokenMismatch))
        XCTAssertEqual(generationMismatch.reasonCode, .identityChanged)
        XCTAssertNil(generationMismatch.goalSatisfied)

        let moveAction = SemanticActionType.moveSubjectRight.rawValue
        let moveBefore = frame(id: "n7-scene-before", capturedAt: startDate, actionID: moveAction, x: 0.20)
        let moveAfter = frame(
            id: "n7-scene-after",
            capturedAt: startDate.addingTimeInterval(0.1),
            actionID: moveAction,
            x: 0.34
        )
        let sceneMismatch = ActionVerifier.verify(input(
            actionID: moveAction,
            before: moveBefore,
            after: moveAfter,
            beforeLifecycle: lifecycle(sceneSignature: "scene-a"),
            afterLifecycle: lifecycle(sceneSignature: "scene-b")
        ))
        XCTAssertEqual(decision(sceneMismatch), .incomparable(reason: .sceneMismatch))
        XCTAssertEqual(sceneMismatch.reasonCode, .sceneChanged)

        // A swapped track binding for the commanded object blocks the favorable
        // scalar (lampA moved left but is a different identity).
        let objectAction = SemanticActionType.moveObjectLeft.rawValue
        let objectScope = ActionVerificationScope(targetRefs: ["lampA"], allowedChanges: [.targetPosition])
        let objectBefore = entityFrame(
            id: "n7-object-before",
            capturedAt: startDate,
            actionID: objectAction,
            entities: [entity("lampA", track: "ta", x: 0.45)]
        )
        let objectAfter = entityFrame(
            id: "n7-object-after",
            capturedAt: startDate.addingTimeInterval(0.1),
            actionID: objectAction,
            entities: [entity("lampA", track: "ta-swapped", x: 0.35)]
        )
        let identitySwap = ActionVerifier.verify(input(
            actionID: objectAction,
            before: objectBefore,
            after: objectAfter,
            scope: objectScope
        ))
        XCTAssertEqual(decision(identitySwap), .incomparable(reason: .subjectIdentityMismatch))
        XCTAssertEqual(identitySwap.reasonCode, .identityChanged)

        // A declared allowed-change set that omits the required class fails
        // closed instead of relying on the hidden legacy path.
        let objectMoved = entityFrame(
            id: "n7-object-moved",
            capturedAt: startDate.addingTimeInterval(0.1),
            actionID: objectAction,
            entities: [entity("lampA", track: "ta", x: 0.35)]
        )
        let undeclared = ActionVerifier.verify(input(
            actionID: objectAction,
            before: objectBefore,
            after: objectMoved,
            scope: ActionVerificationScope(targetRefs: ["lampA"], allowedChanges: [.zoom])
        ))
        XCTAssertEqual(decision(undeclared), .incomparable(reason: .contextChanged))
        XCTAssertEqual(undeclared.reasonCode, .contextChanged)
    }

    /// Item 4: `keep` has no executable action family, so no executive episode
    /// can even be constructed. The same holds for a removal without declared
    /// expected absences (the coordinator requires a verified pair instead).
    func testKeepAndUndeclaredRemovalCannotStartExecutableEpisode() {
        let keepAction = SemanticActionType.keepCurrentSetup.rawValue
        let keepFrame = frame(id: "keep-frame", capturedAt: startDate, actionID: keepAction)
        let keepAdvice = StabilizedAdvice(
            decision: .correct,
            actionID: keepAction,
            frameID: keepFrame.frameID,
            targetX: nil,
            targetY: nil
        )
        XCTAssertNil(
            CoachingEpisodeObservation(
                frame: keepFrame,
                stabilizedAdvice: keepAdvice,
                subjectTrack: nil,
                lifecycle: lifecycle(),
                isStable: true
            ),
            "keep must not create an executive episode"
        )

        let removalAction = SemanticActionType.removeDistractingObject.rawValue
        let removalFrame = frame(id: "removal-frame", capturedAt: startDate, actionID: removalAction)
        let removalAdvice = StabilizedAdvice(
            decision: .correct,
            actionID: removalAction,
            frameID: removalFrame.frameID,
            targetX: nil,
            targetY: nil
        )
        XCTAssertNil(
            CoachingEpisodeObservation(
                frame: removalFrame,
                stabilizedAdvice: removalAdvice,
                subjectTrack: nil,
                lifecycle: lifecycle(),
                isStable: true
            ),
            "an undeclared removal has no honest movement feature and cannot open a live episode"
        )
    }
}
