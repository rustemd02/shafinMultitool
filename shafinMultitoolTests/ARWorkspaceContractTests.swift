import XCTest
@testable import shafinMultitool

final class ARWorkspaceContractTests: XCTestCase {

    func testProjectionIsExactlyTheOrderedSeventeenStates() {
        let contract = ARWorkspaceContract.production

        XCTAssertTrue(contract.validate())
        XCTAssertEqual(contract.states, ARWorkspaceContract.canonicalStates)
        XCTAssertEqual(contract.states.count, 17)
        XCTAssertEqual(contract.states.map(\.id), [
            "ar.preparing",
            "ar.ready",
            "ar.surface-search",
            "ar.placement",
            "ar.playback",
            "ar.marking",
            "ar.live-hints",
            "ar.hint-pause",
            "ar.hint-playback",
            "ar.recording",
            "ar.recording-review",
            "ar.interruption",
            "ar.error",
            "ar.relocalization",
            "ar.reset",
            "ar.world-map-recovery",
            "ar.teardown"
        ])

        for state in contract.states {
            XCTAssertEqual(
                contract.state(state),
                SceneJourneyContract.production.state(state)
            )
        }
        XCTAssertNil(contract.state(.librarySelected))
    }

    func testValidatorRejectsMissingDuplicateExtraAndReorderedStates() {
        let production = ARWorkspaceContract.production

        var missing = production.states
        missing.removeLast()
        XCTAssertFalse(ARWorkspaceContract(states: missing).validate())

        var duplicate = production.states
        duplicate[0] = duplicate[1]
        XCTAssertFalse(ARWorkspaceContract(states: duplicate).validate())

        var extra = production.states
        extra.append(.librarySelected)
        XCTAssertFalse(ARWorkspaceContract(states: extra).validate())

        var reordered = production.states
        reordered.swapAt(0, 1)
        XCTAssertFalse(ARWorkspaceContract(states: reordered).validate())
    }

    func testTransitionQueryFencesOriginToARSubsetAndKeepsCanonicalExits() {
        let contract = ARWorkspaceContract.production

        XCTAssertFalse(contract.allows(.generatorSuccess, .arPreparing))
        XCTAssertFalse(contract.allows(.librarySelected, .arPreparing))
        XCTAssertTrue(contract.allows(.arPreparing, .arReady))
        XCTAssertTrue(contract.allows(.arPlacement, .recordingPreflight))
        XCTAssertTrue(contract.allows(.arTeardown, .librarySelected))
        XCTAssertFalse(contract.allows(.arTeardown, .arReady))
    }

    func testTypedMetadataComesDirectlyFromProductionRows() {
        let contract = ARWorkspaceContract.production

        for state in contract.states {
            guard let row = contract.state(state) else {
                XCTFail("missing production row for \(state.id)")
                continue
            }
            XCTAssertFalse(row.sourceStates.isEmpty)
            XCTAssertFalse(row.entry.isEmpty)
            XCTAssertFalse(row.primaryAction.isEmpty)
            XCTAssertFalse(row.recovery.isEmpty)
            XCTAssertFalse(row.exit.isEmpty)
            XCTAssertFalse(row.artifacts.isEmpty)
            XCTAssertTrue(row.transitions.allSatisfy {
                SceneJourneyContract.production.state($0.to) != nil && !$0.trigger.isEmpty
            })
        }
    }

    func testOwnershipMappingsAreExactAndSessionConformanceIsPending() {
        let contract = ARWorkspaceContract.production

        XCTAssertTrue(contract.ownership.validate())
        XCTAssertEqual(contract.ownership.boundaries.count, ARWorkspaceOwnerRole.allCases.count)
        XCTAssertEqual(contract.ownership.arSessionOwners.count, 1)
        XCTAssertEqual(
            contract.ownership.boundary(for: .arSessionLifecycle)?.owner,
            .arSessionLifecycle
        )
        XCTAssertEqual(contract.ownership.arSessionRuntimeConformance, .pendingM6002)

        var swapped = contract.ownership.boundaries
        let first = swapped[0]
        swapped[0] = ARWorkspaceOwnershipBoundary(
            role: first.role,
            owner: .presentation
        )
        let swappedOwnership = ARWorkspaceOwnershipContract(
            boundaries: swapped,
            arSessionRuntimeConformance: .pendingM6002
        )
        XCTAssertFalse(ARWorkspaceContract(ownership: swappedOwnership).validate())
    }

    func testIdentityFencesAreExactAndGenerationSafe() {
        let contract = ARWorkspaceContract.production

        XCTAssertTrue(contract.identity.validate())
        XCTAssertEqual(
            Set(contract.identity.fences.map(\.identity)),
            Set(ARWorkspaceIdentityKind.allCases)
        )

        var missing = contract.identity.fences
        missing.removeLast()
        XCTAssertFalse(
            ARWorkspaceContract(
                identity: ARWorkspaceIdentityContract(fences: missing)
            ).validate()
        )

        var missingAnchorRule = contract.identity.fences
        let anchorIndex = missingAnchorRule.firstIndex { $0.identity == .anchor }!
        let anchor = missingAnchorRule[anchorIndex]
        var rules = anchor.rules
        rules.remove(.revalidatedAfterMapRestore)
        missingAnchorRule[anchorIndex] = ARWorkspaceIdentityFence(
            identity: anchor.identity,
            rules: rules
        )
        XCTAssertFalse(
            ARWorkspaceContract(
                identity: ARWorkspaceIdentityContract(fences: missingAnchorRule)
            ).validate()
        )
    }

    func testOrientationMatrixIsExactlyLandscapeForIPhoneAndIPad() {
        let contract = ARWorkspaceContract.production

        XCTAssertTrue(contract.orientationMatrix.validate())
        for device in ARWorkspaceDeviceClass.allCases {
            XCTAssertEqual(
                contract.orientationMatrix.supportedOrientations(for: device),
                [.landscapeLeft, .landscapeRight]
            )
            XCTAssertFalse(contract.orientationMatrix.supports(.portrait, on: device))
            XCTAssertFalse(contract.orientationMatrix.supports(.portraitUpsideDown, on: device))
        }

        let portraitMatrix = ARWorkspaceOrientationMatrix(supported: [
            .iPhone: [.portrait, .landscapeLeft],
            .iPad: [.landscapeLeft, .landscapeRight]
        ])
        XCTAssertFalse(
            ARWorkspaceContract(orientationMatrix: portraitMatrix).validate()
        )
    }

    func testTeardownOrderAndAwaitedTerminalAreExact() {
        let contract = ARWorkspaceContract.production

        XCTAssertTrue(contract.teardown.validate())
        XCTAssertEqual(contract.teardown.order, [
            .stopRecording,
            .stopPlayback,
            .persist,
            .releaseRecording,
            .pauseAndDetach
        ])
        XCTAssertEqual(contract.teardown.terminalState, .arTeardown)
        XCTAssertEqual(contract.teardown.terminalDestination, .librarySelected)
        XCTAssertTrue(contract.teardown.awaitsTerminalBeforeNavigation)

        let badOrder = ARWorkspaceTeardownContract(
            order: [.stopRecording, .stopPlayback, .releaseRecording, .persist, .pauseAndDetach],
            terminalState: .arTeardown,
            terminalDestination: .librarySelected,
            awaitsTerminalBeforeNavigation: true
        )
        XCTAssertFalse(ARWorkspaceContract(teardown: badOrder).validate())

        let nonAwaited = ARWorkspaceTeardownContract(
            order: contract.teardown.order,
            terminalState: .arTeardown,
            terminalDestination: .librarySelected,
            awaitsTerminalBeforeNavigation: false
        )
        XCTAssertFalse(ARWorkspaceContract(teardown: nonAwaited).validate())
    }

    func testActiveRecordingCannotBypassCanonicalSafeStop() {
        let contract = ARWorkspaceContract.production
        let active = contract.state(.recordingInProgress)

        XCTAssertTrue(contract.allows(.recordingInProgress, .recordingStopping))
        XCTAssertFalse(contract.allows(.recordingInProgress, .arInterruption))
        XCTAssertFalse(contract.allows(.recordingInProgress, .arTeardown))
        XCTAssertTrue(active?.transitions.contains {
            $0.to == .recordingStopping
                && $0.kind == .recover
                && $0.trigger.localizedCaseInsensitiveContains("safe stop")
        } == true)
    }
}
