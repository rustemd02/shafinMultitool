import Foundation
import CoreVideo
import XCTest
@testable import shafinMultitool

@MainActor
private final class LensHapticRecorder: SETHapticPerforming {
    private(set) var events: [SETHapticEvent] = []

    func perform(_ event: SETHapticEvent) {
        events.append(event)
    }
}

@MainActor
final class CameraViewModelLensSwitchTests: XCTestCase {

    func testProductionPipelineStreamReachesVerificationAfterRecommendationDisappears() async {
        await exerciseVerificationResultRetention(incomparable: false)
    }

    func testIncomparableResultDoesNotTearDownCaptureEpisode() async {
        await exerciseVerificationResultRetention(incomparable: true)
    }

    private func exerciseVerificationResultRetention(incomparable: Bool) async {
        let fixture = makeFixture { _ in
            .noOp(activeLens: .wide)
        }
        let base = Date(timeIntervalSince1970: 10_000)

        fixture.pipeline.publishCoachingEpisodeEvent(
            .baseline(makeEpisodeObservation(id: "episode-f0", x: 0.20, capturedAt: base))
        )
        let baselinePublished = await waitUntil {
            fixture.viewModel.coachingEpisodeState.phase == .awaitingMovement
        }
        XCTAssertTrue(baselinePublished)

        let movement1 = makeEpisodeObservation(
            id: "episode-f1",
            x: 0.26,
            capturedAt: base.addingTimeInterval(0.05)
        )
        let movement2 = makeEpisodeObservation(
            id: "episode-f2",
            x: 0.32,
            capturedAt: base.addingTimeInterval(0.10)
        )
        let stable1 = makeEpisodeObservation(
            id: "episode-f3",
            x: 0.32,
            capturedAt: base.addingTimeInterval(0.15)
        )
        let stable2 = makeEpisodeObservation(
            id: "episode-f4",
            x: 0.32,
            capturedAt: base.addingTimeInterval(0.20)
        )

        fixture.pipeline.publishCoachingEpisodeEvent(
            .frame(movement1.asFrameEvidence(currentActionID: SemanticActionType.moveSubjectRight.rawValue)!)
        )
        fixture.pipeline.publishCoachingEpisodeEvent(
            .frame(movement2.asFrameEvidence(currentActionID: SemanticActionType.moveSubjectRight.rawValue)!)
        )
        // The recommendation has disappeared, but the frozen baseline still
        // owns the episode and these are valid fresh after-frames.
        fixture.pipeline.publishCoachingEpisodeEvent(
            .frame(stable1.asFrameEvidence(currentActionID: nil)!)
        )
        fixture.pipeline.publishCoachingEpisodeEvent(
            .frame(stable2.asFrameEvidence(currentActionID: nil)!)
        )

        let ready = await waitUntil {
            fixture.viewModel.coachingEpisodeState.phase == .readyForVerification
        }
        XCTAssertTrue(ready)
        XCTAssertEqual(fixture.viewModel.coachingEpisodeState.baseline?.frameID, "episode-f0")
        XCTAssertEqual(fixture.viewModel.coachingEpisodeState.movementFrames, 2)
        XCTAssertEqual(fixture.viewModel.coachingEpisodeState.stableAfterFrames, 2)

        if incomparable {
            guard let verified = fixture.viewModel.verificationResult else {
                return XCTFail("the ready transition must first produce an owner result")
            }
            // A focused consumer-boundary check, not an injected full-loop
            // success: incomparable must not masquerade as route teardown.
            let result = ActionVerificationResult(
                token: verified.token,
                actionID: verified.actionID,
                beforeFrameID: verified.beforeFrameID,
                afterFrameID: verified.afterFrameID,
                decision: .incomparable(reason: .unsupportedAction),
                deltas: [],
                safetyRegressions: []
            )
            let event = fixture.pipeline.currentCoachingEpisodeEvent
            XCTAssertTrue(fixture.viewModel.applyVerificationResult(result))
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.async { continuation.resume() }
            }
            XCTAssertEqual(fixture.pipeline.currentCoachingEpisodeEvent, event)
            XCTAssertEqual(fixture.viewModel.verificationResult, result)
            XCTAssertEqual(fixture.viewModel.coachingEpisodeState.phase, .readyForVerification)
        }

        await fixture.viewModel.releaseAndWait()
    }

    func testProductionTerminalCancellationResetsPipelineBeforeFreshBaseline() async {
        let fixture = makeFixture { _ in
            .noOp(activeLens: .wide)
        }
        let base = Date(timeIntervalSince1970: 30_000)

        fixture.pipeline.publishCoachingEpisodeEvent(
            .baseline(makeEpisodeObservation(id: "cancel-f0", x: 0.20, capturedAt: base))
        )
        let baselinePublished = await waitUntil {
            fixture.viewModel.coachingEpisodeState.phase == .awaitingMovement
        }
        XCTAssertTrue(baselinePublished)
        let oldToken = fixture.viewModel.coachingEpisodeState.token

        fixture.pipeline.publishCoachingEpisodeEvent(
            .frame(makeEpisodeObservation(
                id: "cancel-f1",
                x: 0.20,
                capturedAt: base.addingTimeInterval(0.05)
            ).asFrameEvidence(currentActionID: SemanticActionType.moveSubjectLeft.rawValue)!)
        )
        let cancelled = await waitUntil {
            fixture.viewModel.coachingEpisodeState.phase == .cancelled
                && fixture.viewModel.coachingEpisodeState.cancellationReason == .actionChanged
        }
        XCTAssertTrue(cancelled)

        // No manual coordinator reset: the terminal callback must clear the
        // pipeline owner so this baseline is publishable and gets a new token.
        fixture.pipeline.publishCoachingEpisodeEvent(
            .baseline(makeEpisodeObservation(
                id: "cancel-fresh",
                x: 0.20,
                capturedAt: base.addingTimeInterval(0.10)
            ))
        )
        let recovered = await waitUntil {
            fixture.viewModel.coachingEpisodeState.phase == .awaitingMovement
                && fixture.viewModel.coachingEpisodeState.baseline?.frameID == "cancel-fresh"
        }
        XCTAssertTrue(recovered)
        XCTAssertNotEqual(fixture.viewModel.coachingEpisodeState.token, oldToken)

        await fixture.viewModel.releaseAndWait()
    }

    func testProductionSubjectChangeResetsOwnerBeforeFreshResolutionBaseline() async {
        let fixture = makeFixture { _ in
            .noOp(activeLens: .wide)
        }
        let base = Date(timeIntervalSince1970: 35_000)

        for index in 0..<3 {
            let frame = makeProductionEpisodeFrame(
                pipeline: fixture.pipeline,
                id: "subject-old-f\(index)",
                region: CGRect(x: 0.20, y: 0.30, width: 0.20, height: 0.40),
                capturedAt: base.addingTimeInterval(Double(index) * 0.05),
                subjectDetected: true
            )
            fixture.pipeline.testingPublishLiveCoachingEpisodeObservation(
                snapshot: frame.snapshot,
                semantics: frame.semantics,
                plan: frame.plan,
                frameEvidence: frame.evidence,
                evaluatedAt: frame.capturedAt
            )
        }
        let baselinePublished = await waitUntil {
            fixture.viewModel.coachingEpisodeState.phase == .awaitingMovement
                && fixture.viewModel.coachingEpisodeState.baseline?.frameID == "subject-old-f2"
        }
        XCTAssertTrue(baselinePublished)
        let oldToken = fixture.viewModel.coachingEpisodeState.token
        let oldIdentity = fixture.viewModel.coachingEpisodeState.baseline?.subjectIdentity
        XCTAssertNotNil(oldIdentity)

        // Produce a real same-action frame with no candidate. The production
        // adapter calls updateLiveSubjectTracker, marks the old identity lost,
        // and publishes the typed subjectChanged terminal itself.
        let lostFrame = makeProductionEpisodeFrame(
            pipeline: fixture.pipeline,
            id: "subject-lost-f3",
            region: nil,
            capturedAt: base.addingTimeInterval(0.20),
            subjectDetected: false
        )
        fixture.pipeline.testingPublishLiveCoachingEpisodeObservation(
            snapshot: lostFrame.snapshot,
            semantics: lostFrame.semantics,
            plan: lostFrame.plan,
            frameEvidence: lostFrame.evidence,
            evaluatedAt: lostFrame.capturedAt
        )
        let cancelled = await waitUntil {
            fixture.viewModel.coachingEpisodeState.phase == .cancelled
                && fixture.viewModel.coachingEpisodeState.cancellationReason == .subjectChanged
        }
        XCTAssertTrue(cancelled)

        for index in 0..<3 {
            let frame = makeProductionEpisodeFrame(
                pipeline: fixture.pipeline,
                id: "subject-fresh-f\(index)",
                region: CGRect(x: 0.52, y: 0.30, width: 0.20, height: 0.40),
                capturedAt: base.addingTimeInterval(0.25 + Double(index) * 0.05),
                subjectDetected: true
            )
            fixture.pipeline.testingPublishLiveCoachingEpisodeObservation(
                snapshot: frame.snapshot,
                semantics: frame.semantics,
                plan: frame.plan,
                frameEvidence: frame.evidence,
                evaluatedAt: frame.capturedAt
            )
        }
        let recovered = await waitUntil {
            fixture.viewModel.coachingEpisodeState.phase == .awaitingMovement
                && fixture.viewModel.coachingEpisodeState.baseline?.frameID == "subject-fresh-f2"
        }
        XCTAssertTrue(recovered)
        XCTAssertNotEqual(fixture.viewModel.coachingEpisodeState.token, oldToken)
        XCTAssertNotEqual(fixture.viewModel.coachingEpisodeState.baseline?.subjectIdentity, oldIdentity)

        await fixture.viewModel.releaseAndWait()
    }

    func testProductionExpiryResetsPipelineBeforeFreshBaseline() async {
        let fixture = makeFixture { _ in
            .noOp(activeLens: .wide)
        }
        let base = Date(timeIntervalSince1970: 40_000)

        fixture.pipeline.publishCoachingEpisodeEvent(
            .baseline(makeEpisodeObservation(id: "expire-f0", x: 0.20, capturedAt: base))
        )
        let baselinePublished = await waitUntil {
            fixture.viewModel.coachingEpisodeState.phase == .awaitingMovement
        }
        XCTAssertTrue(baselinePublished)
        let oldToken = fixture.viewModel.coachingEpisodeState.token

        fixture.pipeline.publishCoachingEpisodeEvent(
            .frame(makeEpisodeObservation(
                id: "expire-f1",
                x: 0.20,
                capturedAt: base.addingTimeInterval(13)
            ).asFrameEvidence(currentActionID: nil)!)
        )
        let expired = await waitUntil {
            fixture.viewModel.coachingEpisodeState.phase == .expired
                && fixture.viewModel.coachingEpisodeState.cancellationReason == .expired
        }
        XCTAssertTrue(expired)

        fixture.pipeline.publishCoachingEpisodeEvent(
            .baseline(makeEpisodeObservation(
                id: "expire-fresh",
                x: 0.20,
                capturedAt: base.addingTimeInterval(13.05)
            ))
        )
        let recovered = await waitUntil {
            fixture.viewModel.coachingEpisodeState.phase == .awaitingMovement
                && fixture.viewModel.coachingEpisodeState.baseline?.frameID == "expire-fresh"
        }
        XCTAssertTrue(recovered)
        XCTAssertNotEqual(fixture.viewModel.coachingEpisodeState.token, oldToken)

        await fixture.viewModel.releaseAndWait()
    }

    func testNoOpLensRequestCancelsPipelineStreamAndAllowsFreshBaselineToken() async {
        let gate = LensSwitchTestGate()
        let fixture = makeFixture { lens in
            await gate.wait(for: lens)
        }
        fixture.viewModel.availableLenses = [.wide, .telephoto]
        let base = Date(timeIntervalSince1970: 20_000)

        fixture.pipeline.publishCoachingEpisodeEvent(
            .baseline(makeEpisodeObservation(id: "lens-f0", x: 0.20, capturedAt: base))
        )
        let baselinePublished = await waitUntil {
            fixture.viewModel.coachingEpisodeState.phase == .awaitingMovement
        }
        XCTAssertTrue(baselinePublished)
        let oldToken = fixture.viewModel.coachingEpisodeState.token
        XCTAssertNotNil(oldToken)

        fixture.viewModel.switchLens(to: .telephoto)
        XCTAssertEqual(fixture.pipeline.currentCoachingEpisodeEvent, .cancel(.lensChange))
        let cancellationPublished = await waitUntil {
            fixture.viewModel.coachingEpisodeState.cancellationReason == .lensChange
        }
        XCTAssertTrue(cancellationPublished)

        guard let request = await request(from: gate, count: 1) else {
            await fixture.viewModel.releaseAndWait()
            return
        }
        await gate.resolve(request.id, with: .noOp(activeLens: .wide))
        let noOpCompleted = await completed(request, on: gate)
        XCTAssertTrue(noOpCompleted)

        fixture.pipeline.publishCoachingEpisodeEvent(
            .baseline(makeEpisodeObservation(
                id: "lens-fresh",
                x: 0.20,
                capturedAt: base.addingTimeInterval(0.10)
            ))
        )
        let recovered = await waitUntil {
            fixture.viewModel.coachingEpisodeState.phase == .awaitingMovement
                && fixture.viewModel.coachingEpisodeState.baseline?.frameID == "lens-fresh"
        }
        XCTAssertTrue(recovered)
        XCTAssertNotEqual(fixture.viewModel.coachingEpisodeState.token, oldToken)

        await fixture.viewModel.releaseAndWait()
    }

    func testLensSelectionHapticOnlyFiresAfterSuccessfulPhysicalChange() async {
        let gate = LensSwitchTestGate()
        let haptic = LensHapticRecorder()
        let fixture = makeFixture(
            lensSwitchOperation: { lens in await gate.wait(for: lens) },
            lensSelectionHaptic: haptic
        )
        fixture.viewModel.availableLenses = [.wide, .telephoto]

        fixture.viewModel.switchLens(to: .telephoto)
        guard let successRequest = await request(from: gate, count: 1) else {
            await fixture.viewModel.releaseAndWait()
            return
        }
        await gate.resolve(successRequest.id, with: .success(activeLens: .telephoto))
        let successCompleted = await completed(successRequest, on: gate)
        XCTAssertTrue(successCompleted)
        XCTAssertEqual(haptic.events, [.selection])

        fixture.viewModel.switchLens(to: .telephoto)
        guard let noOpRequest = await request(from: gate, count: 2) else {
            await fixture.viewModel.releaseAndWait()
            return
        }
        await gate.resolve(noOpRequest.id, with: .noOp(activeLens: .telephoto))
        let noOpCompleted = await completed(noOpRequest, on: gate)
        XCTAssertTrue(noOpCompleted)
        XCTAssertEqual(haptic.events, [.selection])

        fixture.viewModel.switchLens(to: .wide)
        guard let failureRequest = await request(from: gate, count: 3) else {
            await fixture.viewModel.releaseAndWait()
            return
        }
        await gate.resolve(
            failureRequest.id,
            with: .failure(requestedLens: .wide,
                           lastKnownActiveLens: .telephoto,
                           reason: .replacementRejected)
        )
        let failureCompleted = await completed(failureRequest, on: gate)
        XCTAssertTrue(failureCompleted)
        XCTAssertEqual(haptic.events, [.selection])

        await fixture.viewModel.releaseAndWait()
    }

    func testRequestedLensWaitsForConfirmedSuccess() async {
        let gate = LensSwitchTestGate()
        let fixture = makeFixture { lens in
            await gate.wait(for: lens)
        }
        fixture.viewModel.availableLenses = [.wide, .telephoto]

        fixture.viewModel.switchLens(to: .telephoto)
        XCTAssertEqual(fixture.viewModel.currentLens, .wide)

        guard let request = await request(from: gate, count: 1) else {
            await fixture.viewModel.releaseAndWait()
            return
        }
        XCTAssertEqual(request.lens, .telephoto)
        XCTAssertEqual(fixture.viewModel.currentLens, .wide)

        await gate.resolve(request.id, with: .success(activeLens: .telephoto))
        let didComplete = await completed(request, on: gate)
        XCTAssertTrue(didComplete)
        let didPublish = await waitUntil { fixture.viewModel.currentLens == .telephoto }
        XCTAssertTrue(didPublish)

        await fixture.viewModel.releaseAndWait()
    }

    func testUnavailableAndReplacementRejectedKeepReportedActiveLens() async {
        let gate = LensSwitchTestGate()
        let fixture = makeFixture { lens in
            await gate.wait(for: lens)
        }
        fixture.viewModel.availableLenses = [.wide, .telephoto]

        fixture.viewModel.switchLens(to: .telephoto)
        guard let unavailableRequest = await request(from: gate, count: 1) else {
            await fixture.viewModel.releaseAndWait()
            return
        }
        await gate.resolve(
            unavailableRequest.id,
            with: .failure(requestedLens: .telephoto,
                           lastKnownActiveLens: .wide,
                           reason: .unavailable)
        )
        let unavailableCompleted = await completed(unavailableRequest, on: gate)
        XCTAssertTrue(unavailableCompleted)
        let unavailablePublished = await waitUntil { fixture.viewModel.currentLens == .wide }
        XCTAssertTrue(unavailablePublished)

        fixture.viewModel.switchLens(to: .telephoto)
        guard let rejectedRequest = await request(from: gate, count: 2) else {
            await fixture.viewModel.releaseAndWait()
            return
        }
        await gate.resolve(
            rejectedRequest.id,
            with: .failure(requestedLens: .telephoto,
                           lastKnownActiveLens: .wide,
                           reason: .replacementRejected)
        )
        let rejectedCompleted = await completed(rejectedRequest, on: gate)
        XCTAssertTrue(rejectedCompleted)
        let rejectedPublished = await waitUntil { fixture.viewModel.currentLens == .wide }
        XCTAssertTrue(rejectedPublished)
        XCTAssertNotEqual(fixture.viewModel.currentLens, .telephoto)

        await fixture.viewModel.releaseAndWait()
    }

    func testNewestConfirmedLensWinsWhenOlderCompletionArrivesLate() async {
        let gate = LensSwitchTestGate()
        let fixture = makeFixture { lens in
            await gate.wait(for: lens)
        }
        fixture.viewModel.availableLenses = [.wide, .ultraWide, .telephoto]

        fixture.viewModel.switchLens(to: .telephoto)
        guard let olderRequest = await request(from: gate, count: 1) else {
            await fixture.viewModel.releaseAndWait()
            return
        }

        fixture.viewModel.switchLens(to: .ultraWide)
        guard let newerRequest = await request(from: gate, count: 2) else {
            await gate.resolveAll(with: .failure(requestedLens: .wide,
                                                 lastKnownActiveLens: nil,
                                                 reason: .notConfigured))
            await fixture.viewModel.releaseAndWait()
            return
        }
        XCTAssertEqual(olderRequest.lens, .telephoto)
        XCTAssertEqual(newerRequest.lens, .ultraWide)

        await gate.resolve(newerRequest.id, with: .success(activeLens: .ultraWide))
        let newerCompleted = await completed(newerRequest, on: gate)
        XCTAssertTrue(newerCompleted)
        let newerPublished = await waitUntil { fixture.viewModel.currentLens == .ultraWide }
        XCTAssertTrue(newerPublished)

        await gate.resolve(olderRequest.id, with: .success(activeLens: .telephoto))
        let olderCompleted = await completed(olderRequest, on: gate)
        XCTAssertTrue(olderCompleted)
        let staleIgnored = await waitUntil { fixture.viewModel.currentLens == .ultraWide }
        XCTAssertTrue(staleIgnored)

        await fixture.viewModel.releaseAndWait()
    }

    func testReleaseResetsLensPresentationAndFencesLateCompletion() async {
        let gate = LensSwitchTestGate()
        let fixture = makeFixture { lens in
            await gate.wait(for: lens)
        }

        await fixture.viewModel.startAndWait()
        XCTAssertEqual(fixture.viewModel.currentLens, .wide)
        XCTAssertEqual(fixture.viewModel.availableLenses, [.wide])

        fixture.viewModel.switchLens(to: .telephoto)
        guard let request = await request(from: gate, count: 1) else {
            await fixture.viewModel.releaseAndWait()
            return
        }

        await fixture.viewModel.releaseAndWait()
        XCTAssertEqual(fixture.viewModel.currentLens, .wide)
        XCTAssertTrue(fixture.viewModel.availableLenses.isEmpty)
        XCTAssertEqual(fixture.viewModel.lifecycleState, .idle)

        await gate.resolve(request.id, with: .success(activeLens: .telephoto))
        let didComplete = await completed(request, on: gate)
        XCTAssertTrue(didComplete)
        let lateResultIgnored = await waitUntil {
            fixture.viewModel.currentLens == .wide
                && fixture.viewModel.availableLenses.isEmpty
                && fixture.viewModel.lifecycleState == .idle
        }
        XCTAssertTrue(lateResultIgnored)
        XCTAssertNotEqual(fixture.viewModel.currentLens, .telephoto)
    }

    func testNoOpPublishesReportedActiveLens() async {
        let gate = LensSwitchTestGate()
        let fixture = makeFixture { lens in
            await gate.wait(for: lens)
        }
        fixture.viewModel.currentLens = .telephoto
        fixture.viewModel.availableLenses = [.wide, .telephoto]

        fixture.viewModel.switchLens(to: .wide)
        guard let request = await request(from: gate, count: 1) else {
            await fixture.viewModel.releaseAndWait()
            return
        }

        await gate.resolve(request.id, with: .noOp(activeLens: .telephoto))
        let didComplete = await completed(request, on: gate)
        XCTAssertTrue(didComplete)
        let didPublish = await waitUntil { fixture.viewModel.currentLens == .telephoto }
        XCTAssertTrue(didPublish)

        await fixture.viewModel.releaseAndWait()
    }

    func testRollbackFailureClearsPresentationAndSynchronizesManagerLifecycle() async {
        let manager = Self.makeManager()
        let fixture = makeFixture(manager: manager) { [manager] lens in
            await manager.releaseAndWait()
            return .failure(requestedLens: lens,
                            lastKnownActiveLens: nil,
                            reason: .rollbackFailed)
        }
        fixture.viewModel.currentLens = .telephoto
        fixture.viewModel.availableLenses = [.wide, .telephoto]

        fixture.viewModel.switchLens(to: .wide)
        let mapped = await waitUntil {
            fixture.viewModel.currentLens == .wide
                && fixture.viewModel.availableLenses.isEmpty
                && fixture.viewModel.lifecycleState == manager.lifecycleState
                && fixture.viewModel.lifecycleError == manager.lifecycleError
        }

        XCTAssertTrue(mapped)
        XCTAssertEqual(manager.lifecycleState, .idle)
        XCTAssertNil(manager.lifecycleError)
        XCTAssertEqual(fixture.viewModel.lifecycleState, .idle)
        XCTAssertNil(fixture.viewModel.lifecycleError)
        XCTAssertTrue(fixture.viewModel.availableLenses.isEmpty)

        await fixture.viewModel.releaseAndWait()
    }

    private func makeFixture(
        lensSwitchOperation: @escaping @Sendable (CameraLens) async -> CameraLensSwitchResult,
        lensSelectionHaptic: SETHapticPerforming? = nil
    ) -> CameraViewModelLensSwitchFixture {
        makeFixture(
            manager: Self.makeManager(),
            lensSwitchOperation: lensSwitchOperation,
            lensSelectionHaptic: lensSelectionHaptic
        )
    }

    private func makeFixture(
        manager: CameraManager,
        lensSwitchOperation: @escaping @Sendable (CameraLens) async -> CameraLensSwitchResult,
        lensSelectionHaptic: SETHapticPerforming? = nil
    ) -> CameraViewModelLensSwitchFixture {
        let thermalGovernor = ThermalGovernor(thermalStateProvider: { .nominal },
                                               batteryLevelProvider: { 1.0 })
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil,
            thermalGovernor: thermalGovernor,
            neuralHeavyModelsEnabledProvider: { true },
            liveHybridFusionEnabled: false,
            demoLiveCoachEnabled: false
        )
        let viewModel = CameraViewModel(cameraManager: manager,
                                        analysisPipeline: pipeline,
                                        lensSwitchOperation: lensSwitchOperation,
                                        lensSelectionHaptic: lensSelectionHaptic)
        return CameraViewModelLensSwitchFixture(manager: manager,
                                                 pipeline: pipeline,
                                                 viewModel: viewModel)
    }

    private func makeEpisodeObservation(
        id: String,
        x: Double,
        capturedAt: Date,
        actionID: String = SemanticActionType.moveSubjectRight.rawValue
    ) -> CoachingEpisodeObservation {
        let identity = SubjectTrackIdentity(
            trackID: "episode-subject",
            firstSeenFrameID: "episode-f0",
            generation: 7
        )
        let region = NormalizedRect(x: x, y: 0.30, width: 0.20, height: 0.40)
        let binding = UserMovementSubjectBinding(
            identity: identity,
            frameID: id,
            region: region,
            source: .vision,
            coordinateSpace: .subjectTarget,
            measuredAt: capturedAt,
            confidence: 0.92
        )!
        let families = UserMovementActionFamily.allCases
        let evidence = UserMovementEvidence(
            capturedAt: capturedAt,
            evaluatedAt: capturedAt,
            lensGeneration: 7,
            subjectTrackID: identity.trackID,
            subjectBinding: binding,
            orientation: .portrait,
            isCalibrated: true,
            calibrationVersion: "cal1",
            featureMeasuredAt: Dictionary(uniqueKeysWithValues: families.map { ($0, capturedAt) }),
            featureConfidence: Dictionary(uniqueKeysWithValues: families.map { ($0, 0.92) }),
            sourceAvailability: Dictionary(uniqueKeysWithValues: families.map { ($0, true) })
        )
        let frame = UserMovementFrame(
            frameID: id,
            subjectRegion: region,
            meanLuma: 0.5,
            motionIsStill: true,
            metrics: UserMovementMetrics(),
            evidence: evidence
        )
        let track = SubjectTrackState(
            identity: identity,
            phase: .active,
            lastRegion: region,
            lastSeenFrameID: id,
            lostSinceFrameID: nil,
            missedFrames: 0,
            reconciliations: 0,
            redetectionDue: false
        )
        let lifecycle = SubjectTrackLifecycleContext(
            generation: 7,
            orientation: .portrait,
            lensID: "wide",
            routeActive: true,
            isAppBackgrounded: false,
            sceneSignature: "episode-scene"
        )
        let advice = StabilizedAdvice(
            decision: .correct,
            actionID: actionID,
            frameID: id,
            targetX: 0.5,
            targetY: 0.5,
            targetIdentity: identity
        )
        return CoachingEpisodeObservation(
            frame: frame,
            stabilizedAdvice: advice,
            subjectTrack: track,
            lifecycle: lifecycle,
            isStable: true
        )!
    }

    private func makeProductionEpisodeFrame(
        pipeline: AnalysisPipeline,
        id: String,
        region: CGRect?,
        capturedAt: Date,
        subjectDetected: Bool
    ) -> ProductionEpisodeFrameFixture {
        let normalizedRegion = region.map {
            NormalizedRect(
                x: Double($0.minX),
                y: Double($0.minY),
                width: Double($0.width),
                height: Double($0.height)
            )
        }
        let visionSubjects = subjectDetected
            ? [FeatureSnapshotVisionSubject(
                boundingBox: region!,
                confidence: 0.94,
                isFace: false
            )]
            : []
        let adapterState = PipelineFeatureSnapshotAdapterState(
            features: CoachingFeatures(),
            debugData: DebugData(),
            vision: FeatureSample(
                value: FeatureSnapshotVisionPayload(
                    subjects: visionSubjects,
                    saliencyCenter: nil,
                    saliencyRegion: nil,
                    faceCount: 0,
                    personCount: subjectDetected ? 1 : 0
                ),
                measuredAt: capturedAt,
                baseConfidence: subjectDetected ? 0.94 : 0,
                // The production live handoff binds advice to the subject
                // source, which the snapshot derives from sample provenance;
                // a sample without provenance admits no baseline. Match the
                // evidence lens generation below.
                provenance: FeatureSampleProvenance(
                    frameID: id,
                    captureGeneration: 7,
                    orientation: .up
                )
            ),
            horizonMeasuredAt: nil,
            horizon: nil,
            lightingMeasuredAt: nil,
            lighting: nil,
            detr: nil,
            aestheticMeasuredAt: nil,
            aesthetic: nil
        )
        let snapshot = pipeline.testingMakeFeatureSnapshot(
            mode: .live,
            frameId: id,
            capturedAt: capturedAt,
            adapterState: adapterState
        )
        let semantics = SceneSemanticsReport(
            frameId: id,
            mode: .live,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: subjectDetected ? 0.92 : 0,
            primarySubject: .init(
                kind: subjectDetected ? .person : .unknown,
                region: normalizedRegion,
                confidence: subjectDetected ? 0.94 : 0
            ),
            dominance: .init(
                hasClearFocus: subjectDetected,
                focusCompetitionScore: subjectDetected ? 0.16 : 0,
                backgroundClutterScore: subjectDetected ? 0.18 : 0
            ),
            readability: .init(
                subjectReadable: subjectDetected,
                lookSpaceAdequate: subjectDetected,
                edgePressureScore: 0.10,
                separationScore: subjectDetected ? 0.80 : 0
            ),
            ambiguities: [],
            assumptions: []
        )
        let issueID = "production_subject_issue_\(id)"
        let issue = FrameIssue(
            id: issueID,
            type: .subjectTooCloseToEdge,
            severity: 0.96,
            confidence: 0.96,
            rationale: "Production episode fixture requires a bounded composition correction.",
            evidence: [EvidenceRef(
                source: .snapshot,
                key: "subject.primary",
                value: subjectDetected ? "resolved" : "unresolved",
                confidence: 0.96
            )],
            affectedRegion: normalizedRegion,
            suggestedFixTypes: [.reframing]
        )
        let action = RecommendationAction(
            id: "production_subject_move_right",
            actionType: .moveFrameRight,
            priority: 1,
            targetRegion: normalizedRegion,
            linkedIssueIds: [issueID],
            expectedOutcome: "Move the frame right.",
            guardrail: ActionGuardrail(
                requiresStillCamera: true,
                minConfidence: 0.90,
                suppressWhenMoving: true
            ),
            overlayHint: nil
        )
        let plan = RecommendationPlan(
            frameId: id,
            mode: .live,
            inputVerdict: .needsFix,
            primaryAction: action,
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.96
        )
        let evidence = LatestFrameEvidenceStore.Snapshot(
            pixelBuffer: makeProductionEpisodePixelBuffer(),
            orientation: .up,
            sourceFrameId: id,
            capturedAt: capturedAt,
            isStable: true,
            adapterState: adapterState,
            lensGeneration: 7
        )!
        return ProductionEpisodeFrameFixture(
            snapshot: snapshot,
            semantics: semantics,
            plan: plan,
            evidence: evidence,
            capturedAt: capturedAt
        )
    }

    private func makeProductionEpisodePixelBuffer() -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            64,
            64,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        return pixelBuffer!
    }

    private static func makeManager() -> CameraManager {
        let scheduler = RealtimeScheduler()
        let thermalGovernor = ThermalGovernor(thermalStateProvider: { .nominal },
                                               batteryLevelProvider: { 1.0 })
        return CameraManager(
            scheduler: scheduler,
            thermalGovernor: thermalGovernor,
            motionGate: MotionGate(startMotionUpdates: false),
            sessionRunner: LensSwitchTestSessionRunner(),
            configuration: .ready
        )
    }

    private func request(
        from gate: LensSwitchTestGate,
        count: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> LensSwitchTestGate.Request? {
        let didAppear = await waitUntil {
            await gate.requestCount >= count
        }
        guard didAppear else {
            XCTFail("Timed out waiting for lens switch request \(count)",
                    file: file,
                    line: line)
            await gate.resolveAll(with: .failure(requestedLens: .wide,
                                                 lastKnownActiveLens: nil,
                                                 reason: .notConfigured))
            return nil
        }
        let requests = await gate.requests
        return requests[count - 1]
    }

    private func completed(
        _ request: LensSwitchTestGate.Request,
        on gate: LensSwitchTestGate,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> Bool {
        let didComplete = await waitUntil {
            await gate.hasCompleted(request.id)
        }
        if !didComplete {
            XCTFail("Timed out waiting for lens switch completion \(request.id)",
                    file: file,
                    line: line)
        }
        return didComplete
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @escaping () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if await condition() {
                return true
            }
            do {
                try await Task.sleep(nanoseconds: 1_000_000)
            } catch {
                return false
            }
        }
        return await condition()
    }
}

private struct CameraViewModelLensSwitchFixture {
    let manager: CameraManager
    let pipeline: AnalysisPipeline
    let viewModel: CameraViewModel
}

private struct ProductionEpisodeFrameFixture {
    let snapshot: FrameFeatureSnapshot
    let semantics: SceneSemanticsReport
    let plan: RecommendationPlan
    let evidence: LatestFrameEvidenceStore.Snapshot
    let capturedAt: Date
}

private actor LensSwitchTestGate {
    struct Request: Equatable, Sendable {
        let id: Int
        let lens: CameraLens
    }

    private var nextID = 0
    private var requestsStorage: [Request] = []
    private var pending: [Int: CheckedContinuation<CameraLensSwitchResult, Never>] = [:]
    private var completedIDs = Set<Int>()

    var requestCount: Int {
        requestsStorage.count
    }

    var requests: [Request] {
        requestsStorage
    }

    func wait(for lens: CameraLens) async -> CameraLensSwitchResult {
        let id = nextID
        nextID += 1
        requestsStorage.append(Request(id: id, lens: lens))

        let result = await withCheckedContinuation {
            (continuation: CheckedContinuation<CameraLensSwitchResult, Never>) in
            pending[id] = continuation
        }
        completedIDs.insert(id)
        return result
    }

    func hasCompleted(_ id: Int) -> Bool {
        completedIDs.contains(id)
    }

    func resolve(_ id: Int, with result: CameraLensSwitchResult) {
        pending.removeValue(forKey: id)?.resume(returning: result)
    }

    func resolveAll(with result: CameraLensSwitchResult) {
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations {
            continuation.resume(returning: result)
        }
    }
}

private final class LensSwitchTestSessionRunner: CameraSessionRunner {
    private let lock = NSLock()
    private var running = false

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    func startRunning() {
        lock.lock()
        running = true
        lock.unlock()
    }

    func stopRunning() {
        lock.lock()
        running = false
        lock.unlock()
    }
}
