import XCTest
@testable import shafinMultitool

final class ARWorkspaceContractTests: XCTestCase {

    func testProjectionIsExactlyTheCanonicalSeventeenJourneyStates() {
        let contract = ARWorkspaceContract.production

        XCTAssertTrue(contract.validate())
        XCTAssertEqual(contract.states, ARWorkspaceContract.canonicalStates)
        XCTAssertEqual(contract.states.count, 17)
        XCTAssertEqual(Set(contract.stateIDs).count, 17)
        XCTAssertEqual(contract.stateIDs, ARWorkspaceContract.canonicalStateIDs)
        XCTAssertEqual(
            contract.state(.arReady),
            SceneJourneyContract.production.state(.arReady)
        )
        XCTAssertNil(contract.state(.librarySelected))
    }

    func testEveryEvidenceRowUsesTypedProductionMetadata() {
        let contract = ARWorkspaceContract.production

        XCTAssertEqual(contract.evidenceRows.count, 17)
        XCTAssertEqual(
            Set(contract.evidenceRows.map(\.state)),
            Set(ARWorkspaceContract.canonicalStates)
        )
        for row in contract.evidenceRows {
            let source = SceneJourneyContract.production.state(row.state)
            XCTAssertEqual(row.currentAvailability, source?.availability)
            XCTAssertEqual(row.behaviorOwner, source?.owner)
            XCTAssertEqual(row.typedInputs, source?.sourceStates)
            XCTAssertEqual(row.artifacts, source?.artifacts)
            XCTAssertEqual(row.persistence, source?.persistence)
            XCTAssertEqual(row.allowedTransitions, source?.transitions)
            XCTAssertFalse(row.typedInputs.isEmpty)
            XCTAssertFalse(row.artifacts.isEmpty)
            XCTAssertTrue(row.identityFence.isComplete)
            XCTAssertTrue(row.supportedDeviceOrientations.validate())
            XCTAssertEqual(row.runtimeConformance, .pendingM6002)
            XCTAssertEqual(row.physicalEvidenceStatus, .notRun)
        }
    }

    func testPreparationSearchPlacementHintPlaybackAndRecordingPathsAreLegal() {
        let contract = ARWorkspaceContract.production

        assertTrace([
            .arPreparing,
            .arReady,
            .arSurfaceSearch,
            .arPlacement,
            .arLiveHints,
            .arHintPause,
            .arHintPlayback,
            .arLiveHints,
            .arPlacement,
            .arPlayback
        ])
        assertTrace([
            .arPlacement,
            .recordingPreflight,
            .recordingPermission,
            .recordingIdle,
            .recordingPreparing,
            .recordingReady,
            .recordingStarting,
            .recordingInProgress,
            .recordingStopping,
            .recordingFinalizing,
            .recordingPromoting,
            .recordingCompleted,
            .recordingReview
        ])
        XCTAssertEqual(contract.state(.arPlacement)?.artifact(.arBindings)?.status, .validated)
        XCTAssertEqual(contract.state(.arPlayback)?.artifact(.plannedScene)?.status, .validated)
        XCTAssertEqual(contract.state(.recordingInProgress)?.artifact(.recording)?.status, .pending)
        XCTAssertEqual(contract.state(.recordingReview)?.artifact(.recording)?.status, .promoted)
    }

    func testRecoverySetAndTeardownTraceAreClosed() {
        let contract = ARWorkspaceContract.production

        XCTAssertEqual(contract.recoveryStates, ARWorkspaceContract.canonicalRecoveryStates)
        assertTrace([.arReady, .arInterruption, .arRelocalization, .arWorldMapRecovery, .arReset, .arPreparing])
        assertTrace([.arReady, .arReset, .arWorldMapRecovery, .arReady])
        assertTrace([.arPlacement, .arTeardown, .librarySelected])
        XCTAssertEqual(contract.teardown.order, [
            .stopRecording,
            .stopPlayback,
            .persist,
            .releaseRecording,
            .pauseAndDetach
        ])
        XCTAssertTrue(contract.teardown.awaitsTerminalBeforeNavigation)
        XCTAssertEqual(contract.teardown.terminalState, .arTeardown)
        XCTAssertEqual(contract.teardown.terminalDestination, .librarySelected)
    }

    func testActiveRecordingCannotBypassSafeStop() {
        let contract = ARWorkspaceContract.production

        XCTAssertTrue(contract.allows(.recordingInProgress, .recordingStopping))
        XCTAssertFalse(contract.allows(.recordingInProgress, .arInterruption))
        XCTAssertFalse(contract.allows(.recordingInProgress, .arTeardown))
        XCTAssertTrue(
            contract.state(.recordingInProgress)?.transitions.contains {
                $0.to == .recordingStopping
                    && $0.trigger.localizedCaseInsensitiveContains("safe stop")
            } == true
        )
    }

    func testOwnershipOrientationAndIdentityPoliciesAreExact() {
        let contract = ARWorkspaceContract.production

        XCTAssertTrue(contract.ownership.validate())
        XCTAssertEqual(contract.ownership.arSessionOwners.count, 1)
        XCTAssertEqual(
            contract.ownership.boundary(for: .arSessionLifecycle)?.runtimeConformance,
            .pendingM6002
        )
        XCTAssertEqual(
            contract.orientationMatrix.supportedOrientations(for: .iPhone),
            [.landscapeLeft, .landscapeRight]
        )
        XCTAssertEqual(
            contract.orientationMatrix.supportedOrientations(for: .iPad),
            [.landscapeLeft, .landscapeRight]
        )
        for device in ARWorkspaceDeviceClass.allCases {
            XCTAssertFalse(contract.orientationMatrix.supports(.portrait, on: device))
            XCTAssertFalse(contract.orientationMatrix.supports(.portraitUpsideDown, on: device))
        }
        XCTAssertTrue(contract.identity.validate())
        XCTAssertTrue(contract.identity.summary.staleGenerationRejected)
        XCTAssertTrue(contract.identity.summary.anchorIdentityBoundToSessionGeneration)
        XCTAssertTrue(contract.identity.summary.interruptionInvalidatesLiveIdentities)
        XCTAssertTrue(contract.identity.summary.resetInvalidatesLiveIdentities)
        XCTAssertTrue(contract.identity.summary.mapRestoreRevalidatesAnchors)
    }

    func testValidatorFailsClosedForMissingStateOrientationOwnerIdentityAndTeardown() {
        let production = ARWorkspaceContract.production

        var missingState = production.states
        missingState.removeLast()
        XCTAssertFalse(ARWorkspaceContract(states: missingState).validate())

        var duplicateState = production.states
        duplicateState[0] = duplicateState[1]
        XCTAssertFalse(ARWorkspaceContract(states: duplicateState).validate())

        let portraitMatrix = ARWorkspaceOrientationMatrix(entries: [
            ARWorkspaceOrientationSupport(
                device: .iPhone,
                supported: [.portrait],
                unsupported: [.landscapeLeft, .landscapeRight, .portraitUpsideDown]
            ),
            ARWorkspaceOrientationSupport(
                device: .iPad,
                supported: [.landscapeLeft, .landscapeRight],
                unsupported: [.portrait, .portraitUpsideDown]
            )
        ])
        XCTAssertFalse(
            ARWorkspaceContract(orientationMatrix: portraitMatrix).validate()
        )

        var owners = production.ownership.boundaries
        owners.append(owners[1])
        XCTAssertFalse(
            ARWorkspaceContract(
                ownership: ARWorkspaceOwnershipContract(boundaries: owners)
            ).validate()
        )

        var fences = production.identity.fences
        fences.removeAll { $0.identity == .sessionGeneration }
        XCTAssertFalse(
            ARWorkspaceContract(
                identity: ARWorkspaceIdentityContract(fences: fences)
            ).validate()
        )

        let badTeardown = ARWorkspaceTeardownContract(
            order: [.stopRecording, .stopPlayback, .releaseRecording, .persist, .pauseAndDetach],
            terminalState: .arTeardown,
            terminalDestination: .librarySelected,
            awaitsTerminalBeforeNavigation: false,
            recordingStopState: .recordingStopping
        )
        XCTAssertFalse(ARWorkspaceContract(teardown: badTeardown).validate())
    }

    func testValidatorRejectsSourceGraphDriftAndHardwareClaims() {
        let production = SceneJourneyContract.production
        var sourceStates = production.states
        let arReadyIndex = sourceStates.firstIndex { $0.state == .arReady }!
        let arReady = sourceStates[arReadyIndex]
        sourceStates[arReadyIndex] = SceneJourneyStateContract(
            state: arReady.state,
            availability: arReady.availability,
            owner: arReady.owner,
            sourceStates: arReady.sourceStates,
            entry: "",
            primaryAction: arReady.primaryAction,
            recovery: arReady.recovery,
            exit: arReady.exit,
            persistence: arReady.persistence,
            artifacts: arReady.artifacts,
            transitions: arReady.transitions
        )
        let malformedJourney = SceneJourneyContract(
            sourceVocabulary: production.sourceVocabulary,
            states: sourceStates,
            entryStates: production.entryStates
        )
        XCTAssertFalse(
            ARWorkspaceContract(sourceContract: malformedJourney).validate()
        )
        XCTAssertFalse(
            ARWorkspaceContract(physicalEvidenceStatus: .claimed).validate()
        )
    }

    private func assertTrace(
        _ trace: [SceneJourneyState],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for pair in zip(trace, trace.dropFirst()) {
            XCTAssertTrue(
                ARWorkspaceContract.production.allows(pair.0, pair.1),
                "illegal AR journey edge \(pair.0.id) → \(pair.1.id)",
                file: file,
                line: line
            )
        }
    }
}
