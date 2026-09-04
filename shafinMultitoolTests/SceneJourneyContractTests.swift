import XCTest
@testable import shafinMultitool

final class SceneJourneyContractTests: XCTestCase {
    // Deliberately independent from SceneJourneyState.allCases. This list is
    // the test's frozen 1.0 identity receipt, not a reflection of the enum.
    private let expectedCanonicalStateIDs: Set<String> = [
        "library.empty", "library.contact-sheet", "library.selected", "library.rename-name",
        "library.missing-preview", "library.create-name", "library.duplicate-name", "library.delete-confirmation",
        "library.persistence-failure", "generator.input-empty", "generator.input-editing",
        "generator.input-keyboard", "generator.input-marked-detected", "generator.input-invalid",
        "generator.clarification", "generator.accepted", "generator.leader",
        "generator.progress-reading", "generator.progress-anchors", "generator.progress-frame",
        "generator.background-cancel", "generator.failure-parse", "generator.failure-network",
        "generator.failure-model", "generator.retry", "generator.success", "ar.preparing",
        "ar.ready", "ar.surface-search", "ar.placement", "ar.playback", "ar.marking",
        "ar.live-hints", "ar.hint-pause", "ar.hint-playback", "ar.recording",
        "ar.recording-review", "ar.interruption", "ar.error", "ar.teardown",
        "storyboard.tray-collapsed", "storyboard.tray-expanded", "storyboard.selection-reflow",
        "storyboard.result", "storyboard.inspector", "storyboard.editor-medium",
        "storyboard.editor-large", "storyboard.saving", "storyboard.validation-failure",
        "storyboard.delete-confirmation", "sheet.scene-name", "sheet.marker-name",
        "sheet.screenplay-input", "sheet.decision-trace", "recording.idle", "recording.preparing",
        "recording.ready", "recording.starting", "recording.stopping", "recording.finalizing",
        "recording.promoting", "recording.completed", "recording.failed", "recording.cancelled",
        "recording.released", "recording.exporting", "recording.exported"
    ]

    func testProductionContractIsCompleteAndTyped() {
        let contract = SceneJourneyContract.production

        XCTAssertTrue(contract.validate())
        XCTAssertEqual(Set(contract.states.map(\.id)), expectedCanonicalStateIDs)
        XCTAssertEqual(contract.states.count, expectedCanonicalStateIDs.count)
        XCTAssertEqual(contract.sourceVocabulary, SceneJourneySourceState.allCases)
        XCTAssertTrue(contract.states.allSatisfy {
            !$0.owner.rawValue.isEmpty
                && !$0.persistence.rawValue.isEmpty
                && !$0.sourceStates.isEmpty
                && !$0.artifacts.isEmpty
        })
    }

    func testExpectedOwnerPersistenceAndArtifactMappings() {
        let contract = SceneJourneyContract.production

        XCTAssertEqual(contract.state(.libraryCreateName)?.owner, .libraryPersistence)
        XCTAssertEqual(contract.state(.libraryRenameName)?.owner, .libraryPersistence)
        XCTAssertEqual(contract.state(.libraryMissingPreview)?.artifact(.preview)?.status, .missing)
        XCTAssertEqual(contract.state(.generatorInputKeyboard)?.owner, .keyboard)
        XCTAssertEqual(contract.state(.generatorSuccess)?.persistence, .project)
        XCTAssertEqual(contract.state(.generatorSuccess)?.artifact(.script)?.status, .validated)
        XCTAssertEqual(contract.state(.generatorSuccess)?.artifact(.storyboard)?.status, .pending)
        XCTAssertEqual(contract.state(.librarySelected)?.artifact(.preview)?.status, .optional)
        XCTAssertEqual(contract.state(.recordingInProgress)?.artifact(.recording)?.status, .pending)
        XCTAssertEqual(contract.state(.recordingReview)?.artifact(.recording)?.status, .promoted)
        XCTAssertEqual(contract.state(.recordingExported)?.artifact(.recordingExport)?.status, .promoted)
        XCTAssertEqual(contract.state(.recordingReleased)?.artifact(.recording)?.status, .optional)
        XCTAssertEqual(contract.state(.recordingReleased)?.persistence, .project)
    }

    func testSuccessExportTraceUsesLegalTypedEdges() {
        assertTrace([
            .libraryLoaded, .librarySelected, .generatorInputEmpty, .generatorInputEditing,
            .generatorAccepted, .generatorLeader, .generatorProgressReading,
            .generatorProgressAnchors, .generatorProgressFrame, .generatorSuccess,
            .arPreparing, .arReady, .arSurfaceSearch, .arPlacement, .arPlayback,
            .recordingReady, .recordingStarting, .recordingInProgress, .recordingStopping,
            .recordingFinalizing, .recordingPromoting, .recordingCompleted, .recordingReview,
            .recordingExporting, .recordingExported, .recordingReleased
        ])
        XCTAssertTrue(RecordingLifecycleState.isLegalTransition(from: .stopping, to: .finalizing))
        XCTAssertTrue(RecordingLifecycleState.isLegalTransition(from: .finalizing, to: .promoting))
        XCTAssertTrue(RecordingLifecycleState.isLegalTransition(from: .promoting, to: .completed))
        XCTAssertTrue(RecordingLifecycleState.isLegalTransition(from: .completed, to: .released))
    }

    func testFailureRecoveryAndTeardownTraces() {
        assertTrace([.libraryLoaded, .libraryCreateName, .libraryDuplicateName, .libraryCreateName, .librarySelected])
        assertTrace([.librarySelected, .libraryRenameName, .libraryDuplicateName, .libraryRenameName, .librarySelected])
        assertTrace([.librarySelected, .libraryMissingPreview, .generatorInputEmpty])
        assertTrace([
            .generatorInputEditing, .generatorAccepted, .generatorLeader,
            .generatorProgressReading, .generatorFailureNetwork, .generatorRetry,
            .generatorAccepted
        ])
        assertTrace([.arReady, .arInterruption, .arPreparing, .arError, .arPreparing])
        assertTrace([.arPlacement, .arTeardown, .librarySelected])
        assertTrace([.storyboardEditorMedium, .storyboardValidationFailure, .storyboardEditorLarge])
        assertTrace([.storyboardEditorMedium, .storyboardDeleteConfirmation, .storyboardResult])
        assertTrace([.recordingFinalizing, .recordingFailure, .recordingReady])
        assertTrace([.recordingStarting, .recordingCancelled, .recordingReleased])
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
