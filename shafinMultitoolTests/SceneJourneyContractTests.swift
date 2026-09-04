import XCTest
@testable import shafinMultitool

final class SceneJourneyContractTests: XCTestCase {
    // Deliberately independent from SceneJourneyState.allCases. This list is
    // the test's frozen 1.0 identity receipt, not a reflection of the enum.
    private let expectedCanonicalStateIDs: Set<String> = [
        "library.empty", "library.contact-sheet", "library.selected", "library.rename-name",
        "library.rename-duplicate-name", "library.missing-preview", "library.create-name", "library.duplicate-name", "library.delete-confirmation",
        "library.persistence-failure", "generator.input-empty", "generator.input-editing",
        "generator.input-keyboard", "generator.input-marked-detected", "generator.input-invalid",
        "generator.clarification", "generator.validating", "generator.accepted", "generator.queued", "generator.leader",
        "generator.progress-reading", "generator.progress-anchors", "generator.progress-frame",
        "generator.cancelling", "generator.paused", "generator.background-cancel", "generator.failure-parse",
        "generator.failure-quota", "generator.failure-malformed", "generator.failure-persistence", "generator.failure-network",
        "generator.failure-model", "generator.retry", "generator.success", "ar.preparing",
        "ar.ready", "ar.surface-search", "ar.placement", "ar.playback", "ar.marking",
        "ar.live-hints", "ar.hint-pause", "ar.hint-playback", "ar.recording",
        "ar.recording-review", "ar.interruption", "ar.error", "ar.teardown",
        "storyboard.tray-collapsed", "storyboard.tray-expanded", "storyboard.selection-reflow",
        "storyboard.planning", "storyboard.validation", "storyboard.result", "storyboard.inspector", "storyboard.editor-medium",
        "storyboard.editor-large", "storyboard.saving", "storyboard.reorder", "storyboard.validation-failure",
        "storyboard.delete-confirmation", "sheet.scene-name", "sheet.marker-name",
        "sheet.screenplay-input", "sheet.decision-trace", "recording.idle", "recording.preflight", "recording.permission",
        "recording.preparing", "recording.ready", "recording.starting", "recording.stopping", "recording.finalizing",
        "recording.promoting", "recording.completed", "recording.failed", "recording.cancelled",
        "recording.released", "recording.playback", "recording.recovery", "recording.exporting", "recording.exported",
        "recording.export-cancelled", "recording.export-failure"
    ]

    func testProductionContractIsCompleteAndTyped() {
        let contract = SceneJourneyContract.production

        XCTAssertTrue(contract.validate())
        XCTAssertEqual(Set(contract.states.map(\.id)), expectedCanonicalStateIDs)
        XCTAssertEqual(contract.states.count, expectedCanonicalStateIDs.count)
        XCTAssertEqual(contract.sourceVocabulary, SceneJourneySourceState.allCases)
        XCTAssertEqual(contract.entryStates, [.libraryEmpty, .libraryLoaded])
        XCTAssertTrue(contract.states.allSatisfy {
            !$0.owner.rawValue.isEmpty
                && !$0.persistence.rawValue.isEmpty
                && !$0.sourceStates.isEmpty
                && !$0.artifacts.isEmpty
        })
        let expectedReachable = Set(contract.states.filter { $0.availability != .unreachable }.map(\.state))
        XCTAssertEqual(contract.reachableStates(), expectedReachable)
    }

    func testExpectedOwnerPersistenceAndArtifactMappings() {
        let contract = SceneJourneyContract.production

        XCTAssertEqual(contract.state(.libraryCreateName)?.owner, .libraryPersistence)
        XCTAssertEqual(contract.state(.libraryRenameName)?.owner, .libraryPersistence)
        XCTAssertEqual(contract.state(.libraryRenameDuplicateName)?.artifact(.project)?.status, .validated)
        XCTAssertEqual(contract.state(.libraryDuplicateName)?.artifact(.project)?.status, .missing)
        XCTAssertEqual(contract.state(.libraryMissingPreview)?.artifact(.preview)?.status, .missing)
        XCTAssertEqual(contract.state(.generatorInputKeyboard)?.owner, .keyboard)
        XCTAssertEqual(contract.state(.generatorValidating)?.owner, .generatorExecution)
        XCTAssertEqual(contract.state(.generatorQueued)?.owner, .generatorExecution)
        XCTAssertEqual(contract.state(.generatorFailureQuota)?.sourceStates, [.generationQuotaFailure])
        XCTAssertEqual(contract.state(.generatorFailureMalformed)?.sourceStates, [.generationMalformedFailure])
        XCTAssertEqual(contract.state(.generatorFailurePersistence)?.owner, .generatorPersistence)
        XCTAssertEqual(contract.state(.generatorSuccess)?.persistence, .project)
        XCTAssertEqual(contract.state(.generatorSuccess)?.artifact(.script)?.status, .validated)
        XCTAssertEqual(contract.state(.generatorSuccess)?.artifact(.storyboard)?.status, .pending)
        XCTAssertEqual(contract.state(.librarySelected)?.artifact(.preview)?.status, .optional)
        XCTAssertEqual(contract.state(.recordingInProgress)?.artifact(.recording)?.status, .pending)
        XCTAssertEqual(contract.state(.recordingReview)?.artifact(.recording)?.status, .promoted)
        XCTAssertEqual(contract.state(.recordingPreflight)?.owner, .recording)
        XCTAssertEqual(contract.state(.recordingPermission)?.owner, .recording)
        XCTAssertEqual(contract.state(.recordingPlayback)?.owner, .recordingPlayback)
        XCTAssertEqual(contract.state(.recordingRecovery)?.owner, .recording)
        XCTAssertEqual(contract.state(.recordingExported)?.artifact(.recordingExport)?.status, .promoted)
        XCTAssertEqual(contract.state(.recordingExportCancelled)?.artifact(.recording)?.status, .promoted)
        XCTAssertEqual(contract.state(.recordingExportFailure)?.artifact(.recording)?.status, .promoted)
        XCTAssertEqual(contract.state(.recordingExporting)?.owner, .export)
        XCTAssertTrue(contract.state(.recordingExporting)?.owner.rawValue.contains("LegacySceneGeneratorCameraShell") == true)
        XCTAssertFalse(contract.state(.recordingExporting)?.owner.rawValue.contains("RecordingArtifactStore") == true)
        XCTAssertEqual(contract.state(.recordingReleased)?.artifact(.recording)?.status, .optional)
        XCTAssertEqual(contract.state(.recordingReleased)?.persistence, .project)
    }

    func testSuccessExportTraceUsesLegalTypedEdges() {
        assertTrace([
            .libraryLoaded, .librarySelected, .generatorInputEmpty, .generatorInputEditing,
            .generatorValidating, .generatorAccepted, .generatorQueued, .generatorLeader,
            .generatorProgressReading,
            .generatorProgressAnchors, .generatorProgressFrame, .generatorSuccess,
            .arPreparing, .arReady, .arSurfaceSearch, .arPlacement,
            .arPlayback, .recordingPreflight, .recordingPermission, .recordingIdle,
            .recordingPreparing, .recordingReady, .recordingStarting, .recordingInProgress, .recordingStopping,
            .recordingFinalizing, .recordingPromoting, .recordingCompleted, .recordingReview,
            .recordingExporting, .recordingExported, .recordingReleased
        ])
        assertTrace([.generatorSuccess, .storyboardPlanning, .storyboardValidation, .storyboardResult])
        assertTrace([.arPreparing, .arReady, .arSurfaceSearch, .arPlacement, .arLiveHints, .arHintPause, .arHintPlayback, .arLiveHints, .arPlacement])
        XCTAssertTrue(RecordingLifecycleState.isLegalTransition(from: .stopping, to: .finalizing))
        XCTAssertTrue(RecordingLifecycleState.isLegalTransition(from: .finalizing, to: .promoting))
        XCTAssertTrue(RecordingLifecycleState.isLegalTransition(from: .promoting, to: .completed))
        XCTAssertTrue(RecordingLifecycleState.isLegalTransition(from: .completed, to: .released))
        XCTAssertFalse(SceneJourneyContract.production.allows(.recordingPromoting, .recordingReleased))
        XCTAssertFalse(SceneJourneyContract.production.allows(.recordingFailure, .recordingReady))
    }

    func testFailureRecoveryAndTeardownTraces() {
        assertTrace([.libraryLoaded, .libraryCreateName, .libraryDuplicateName, .libraryCreateName, .librarySelected])
        assertTrace([.librarySelected, .libraryRenameName, .libraryRenameDuplicateName, .libraryRenameName, .librarySelected])
        XCTAssertEqual(SceneJourneyContract.production.state(.libraryRenameDuplicateName)?.artifact(.project)?.status, .validated)
        assertTrace([.librarySelected, .libraryMissingPreview, .generatorInputEmpty])
        assertTrace([
            .generatorInputEditing, .generatorValidating, .generatorAccepted, .generatorQueued,
            .generatorPaused, .generatorQueued, .generatorLeader,
            .generatorProgressReading, .generatorFailureNetwork, .generatorRetry,
            .generatorAccepted, .generatorQueued, .generatorCancelling, .generatorInputEditing
        ])
        assertTrace([.generatorValidating, .generatorFailureMalformed, .generatorRetry, .generatorAccepted])
        assertTrace([.generatorValidating, .generatorFailureQuota, .generatorRetry, .generatorAccepted])
        assertTrace([.generatorValidating, .generatorFailurePersistence, .generatorRetry, .generatorAccepted])
        assertTrace([.arReady, .arInterruption, .arPreparing, .arError, .arPreparing])
        assertTrace([.arPlacement, .arTeardown, .librarySelected])
        assertTrace([.storyboardEditorMedium, .storyboardValidationFailure, .storyboardEditorLarge])
        assertTrace([.storyboardEditorMedium, .storyboardDeleteConfirmation, .storyboardResult])
        assertTrace([.recordingFinalizing, .recordingFailure, .recordingRecovery, .recordingPreflight, .recordingPermission, .recordingIdle, .recordingPreparing, .recordingReady])
        assertTrace([.recordingStarting, .recordingCancelled, .recordingReleased])
        assertTrace([.recordingCompleted, .recordingReview, .recordingPlayback, .recordingReview])
        assertTrace([.recordingReview, .recordingExporting, .recordingExportCancelled, .recordingExporting, .recordingExportFailure, .recordingReview])
    }

    func testRecordingTransitionsAreExhaustiveAndTyped() {
        let contract = SceneJourneyContract.production

        XCTAssertTrue(contract.recordingLifecycleTransitionsAreConsistent())
        for state in contract.states {
            for transition in state.transitions {
                let fromLifecycle = state.state.recordingLifecycleState
                let toLifecycle = transition.to.recordingLifecycleState
                guard fromLifecycle != nil || toLifecycle != nil else { continue }
                if transition.kind == .outerNavigation {
                    continue
                }
                XCTAssertNotNil(fromLifecycle, "lifecycle edge must have a lifecycle source or outer classification")
                XCTAssertNotNil(toLifecycle, "lifecycle edge must have a lifecycle destination or outer classification")
                if let fromLifecycle, let toLifecycle {
                    XCTAssertTrue(
                        RecordingLifecycleState.isLegalTransition(from: fromLifecycle, to: toLifecycle),
                        "illegal lifecycle edge \(state.id) → \(transition.to.id)"
                    )
                }
            }
        }
    }

    func testCustomContractValidationFailsClosed() {
        let contract = SceneJourneyContract.production

        var truncatedStates = contract.states
        truncatedStates.removeLast()
        XCTAssertFalse(
            SceneJourneyContract(sourceVocabulary: contract.sourceVocabulary, states: truncatedStates).validate()
        )

        var malformedStates = contract.states
        let first = malformedStates[0]
        malformedStates[0] = SceneJourneyStateContract(
            state: first.state,
            availability: first.availability,
            owner: first.owner,
            sourceStates: first.sourceStates,
            entry: "",
            primaryAction: first.primaryAction,
            recovery: first.recovery,
            exit: first.exit,
            persistence: first.persistence,
            artifacts: first.artifacts,
            transitions: first.transitions
        )
        XCTAssertFalse(
            SceneJourneyContract(sourceVocabulary: contract.sourceVocabulary, states: malformedStates).validate()
        )

        XCTAssertTrue(contract.allows(.recordingCompleted, .recordingReleased))
        XCTAssertEqual(contract.state(.recordingReleased)?.artifact(.recording)?.status, .optional)

        malformedStates[0] = SceneJourneyStateContract(
            state: first.state,
            availability: first.availability,
            owner: first.owner,
            sourceStates: first.sourceStates,
            entry: first.entry,
            primaryAction: first.primaryAction,
            recovery: first.recovery,
            exit: first.exit,
            persistence: first.persistence,
            artifacts: first.artifacts,
            transitions: [SceneJourneyTransition(to: first.state, kind: .advance, trigger: "invalid self-loop")]
        )
        XCTAssertFalse(
            SceneJourneyContract(sourceVocabulary: contract.sourceVocabulary, states: malformedStates).validate()
        )
    }

    private func assertTrace(_ trace: [SceneJourneyState], file: StaticString = #filePath, line: UInt = #line) {
        for pair in zip(trace, trace.dropFirst()) {
            XCTAssertTrue(
                SceneJourneyContract.production.allows(pair.0, pair.1),
                "illegal journey edge \(pair.0.id) → \(pair.1.id)",
                file: file,
                line: line
            )
        }
    }
}
