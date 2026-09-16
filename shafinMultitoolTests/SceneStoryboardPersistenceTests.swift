import XCTest
import ARKit
import simd
@testable import shafinMultitool

final class SceneStoryboardPersistenceTests: XCTestCase {
    private final class FaultingProjectStore: DBService {
        struct Attempt {
            let project: UnifiedSceneProject
            let expectedUpdatedAt: Date?
        }
        var remainingFailures = 0
        var attempts: [Attempt] = []

        override func saveUnifiedSceneProject(_ project: UnifiedSceneProject, worldMap: ARWorldMap?, expectedUpdatedAt: Date?) throws {
            attempts.append(Attempt(project: project, expectedUpdatedAt: expectedUpdatedAt))
            if remainingFailures > 0 {
                remainingFailures -= 1
                throw CocoaError(.fileWriteOutOfSpace)
            }
            try super.saveUnifiedSceneProject(project, worldMap: worldMap, expectedUpdatedAt: expectedUpdatedAt)
        }
    }

    @MainActor
    private final class SnapshotGate {
        let entered: XCTestExpectation
        private var continuation: CheckedContinuation<Result<ARWorldMap?, SceneWorkspaceTeardownFailure>, Never>?
        private var isReleased = false

        init(entered: XCTestExpectation) { self.entered = entered }

        func capture() async -> Result<ARWorldMap?, SceneWorkspaceTeardownFailure> {
            if isReleased { return .success(nil) }
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                entered.fulfill()
            }
        }

        func release() {
            isReleased = true
            let pending = continuation
            continuation = nil
            pending?.resume(returning: .success(nil))
        }
    }

    @MainActor
    private func fixture(actorMovement: Bool = false) throws -> (viewModel: SceneGeneratorViewModel, store: FaultingProjectStore, project: UnifiedSceneProject) {
        let leases = ProjectLifecycleRegistry()
        let store = FaultingProjectStore(projectLeases: leases)
        let script = SceneScript(
            actors: [.init(id: "actor_1", type: .human, name: "Mara")], objects: [],
            beats: [
                .init(id: "beat_1", actions: [.init(id: "action_1", actorId: "actor_1", type: actorMovement ? .walk : .stand,
                                                  direction: actorMovement ? .right : nil)]),
                .init(id: "beat_2", actions: [.init(id: "action_2", actorId: "actor_1", type: .talk, dialogue: "Original line")])
            ],
            spatialRelations: [], originalDescription: "Mara stands and speaks."
        )
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4<Float>(0, 1.5, 0, 1)
        var plan = SpatialPlannerService.shared.planScene(
            script: script, cameraTransform: transform, detectedObjects: [],
            availablePlanes: [.init(alignment: .horizontal, y: 0)], markedObjects: []
        )
        plan.provenance = .direct(
            sourceText: script.originalDescription,
            contributors: [.deterministicRules(componentVersion: "fixture-original-v1")]
        )
        let project = UnifiedSceneProject(
            name: "storyboard-persistence-test-\(UUID().uuidString)",
            sceneDescription: script.originalDescription, parsedScript: script, plannedScene: plan
        )
        try store.saveUnifiedSceneProject(project, worldMap: nil)
        let token = try XCTUnwrap(leases.acquire(projectID: project.id))
        let viewModel = SceneGeneratorViewModel(
            projectName: project.name, isNewProject: false, projectStore: store,
            presentationLocale: Locale(identifier: "en"), persistedProject: project,
            projectLeaseToken: token, projectLeaseRegistry: leases
        )
        viewModel.testingSetPlanningContext(cameraTransform: transform, planes: [.init(alignment: .horizontal, y: 0)])
        viewModel.refreshStoryboardBeatItems()
        viewModel.openStoryboardEditor(for: "beat_1")
        addTeardownBlock { @MainActor in
            store.remainingFailures = 0
            viewModel.testingWorldMapCaptureOverride = nil
            viewModel.testingProjectSnapshotWaiterReturnOverride = nil
            _ = await viewModel.teardownAndWait()
            // A deliberately conflicting stored fixture can leave teardown
            // blocked. This test owns the lease and releases only its token.
            leases.release(projectID: project.id, token: token)
            if let stored = store.listUnifiedSceneProjects().first(where: { $0.id == project.id }) {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    store.deleteUnifiedSceneProject(id: project.id, expectedUpdatedAt: stored.updatedAt) { _ in continuation.resume() }
                }
            }
        }
        store.attempts.removeAll()
        return (viewModel, store, project)
    }

    @MainActor
    private func editedDraft(_ viewModel: SceneGeneratorViewModel) throws -> StoryboardBeatEditDraft {
        var draft = try XCTUnwrap(viewModel.activeStoryboardEditDraft)
        draft.actions[0].type = .talk
        draft.actions[0].text = "A deliberately edited line"
        return draft
    }

    @MainActor
    private func waitForMutation(_ viewModel: SceneGeneratorViewModel) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !viewModel.isStoryboardMutationInFlight && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(viewModel.isStoryboardMutationInFlight)
    }

    private func generatedResult(description: String) -> ParsingResult {
        ParsingResult(
            script: SceneScript(
                actors: [.init(id: "actor_1", type: .human, name: "Generated Mara")], objects: [],
                beats: [.init(id: "beat_1", actions: [.init(id: "generated_action_1", actorId: "actor_1", type: .stand)])],
                spatialRelations: [], originalDescription: description
            ),
            diagnostics: .empty,
            generationProvenance: .direct(
                sourceText: description,
                contributors: [.deterministicRules(componentVersion: "fixture-generated-v1")]
            )
        )
    }

    @MainActor
    func testSaveFailurePreservesSceneAndEditorThenRetryPersistsOnce() async throws {
        let (viewModel, store, project) = try fixture()
        let draft = try editedDraft(viewModel)
        let originalEditor = viewModel.activeStoryboardEditDraft
        let originalTimeline = viewModel.beatTimelineItems
        store.remainingFailures = 1

        let failed = await viewModel.applyStoryboardBeatEdit(draft)
        XCTAssertFalse(failed)
        XCTAssertEqual(viewModel.parsedScript, project.parsedScript)
        XCTAssertEqual(viewModel.plannedScene, project.plannedScene)
        XCTAssertEqual(viewModel.beatTimelineItems, originalTimeline)
        XCTAssertEqual(viewModel.activeStoryboardEditDraft, originalEditor)
        XCTAssertEqual(viewModel.errorMessage, viewModel.localizedCopy(.storyboardErrorSave))
        XCTAssertEqual(store.loadUnifiedSceneProject(named: project.name)?.0, project)

        let retried = await viewModel.applyStoryboardBeatEdit(draft)
        XCTAssertTrue(retried)
        XCTAssertNil(viewModel.activeStoryboardEditDraft)
        XCTAssertEqual(viewModel.parsedScript?.beats.first?.actions.first?.type, .talk)
        let saved = try XCTUnwrap(store.loadUnifiedSceneProject(named: project.name)?.0)
        XCTAssertEqual(saved.parsedScript, viewModel.parsedScript)
        XCTAssertEqual(saved.plannedScene, viewModel.plannedScene)
        XCTAssertEqual(saved.plannedScene?.provenance?.acceptedContributors, project.plannedScene?.provenance?.acceptedContributors)
        XCTAssertEqual(saved.plannedScene?.provenance?.lastUserModification?.kind, .scriptEdit)
        XCTAssertEqual(store.attempts.count, 2)
        XCTAssertTrue(store.attempts.allSatisfy { $0.expectedUpdatedAt == project.updatedAt })
    }

    @MainActor
    func testEditWaitsForSnapshotThenUsesItsSuccessfulStoredVersion() async throws {
        let (viewModel, store, project) = try fixture()
        let draft = try editedDraft(viewModel)
        let captured = expectation(description: "snapshot awaiting AR result")
        let gate = SnapshotGate(entered: captured)
        defer { gate.release() }
        viewModel.testingWorldMapCaptureOverride = { await gate.capture() }
        let snapshot = Task { await viewModel.testingPersistProjectSnapshot() }
        await fulfillment(of: [captured], timeout: 3)
        let edit = Task { await viewModel.applyStoryboardBeatEdit(draft) }
        try await waitForMutation(viewModel)
        XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertEqual(viewModel.parsedScript, project.parsedScript)
        XCTAssertNotNil(viewModel.activeStoryboardEditDraft)
        gate.release()
        let snapshotResult = await snapshot.value
        if case .failure(let failure) = snapshotResult { XCTFail("snapshot failed: \(failure)") }
        let edited = await edit.value
        XCTAssertTrue(edited)
        XCTAssertEqual(store.attempts.count, 2)
        let firstWrite = try XCTUnwrap(store.attempts.first)
        let lastWrite = try XCTUnwrap(store.attempts.last)
        XCTAssertEqual(firstWrite.project.parsedScript, project.parsedScript)
        XCTAssertEqual(lastWrite.expectedUpdatedAt, firstWrite.project.updatedAt)
        XCTAssertEqual(store.loadUnifiedSceneProject(named: project.name)?.0.parsedScript, viewModel.parsedScript)
    }

    @MainActor
    func testSourceChangeWhileSnapshotPendingRejectsStaleEdit() async throws {
        let (viewModel, store, project) = try fixture()
        let draft = try editedDraft(viewModel)
        let captured = expectation(description: "snapshot awaiting AR result")
        let gate = SnapshotGate(entered: captured)
        defer { gate.release() }
        viewModel.testingWorldMapCaptureOverride = { await gate.capture() }
        let snapshot = Task { await viewModel.testingPersistProjectSnapshot() }
        await fulfillment(of: [captured], timeout: 3)
        let edit = Task { await viewModel.applyStoryboardBeatEdit(draft) }
        try await waitForMutation(viewModel)
        viewModel.sceneDescription = "A different current scene description."
        gate.release()
        _ = await snapshot.value
        let edited = await edit.value
        XCTAssertFalse(edited)
        XCTAssertEqual(viewModel.parsedScript, project.parsedScript)
        XCTAssertNotNil(viewModel.activeStoryboardEditDraft)
        XCTAssertEqual(viewModel.errorMessage, viewModel.localizedCopy(.storyboardErrorSaveConflict))
        XCTAssertEqual(store.attempts.count, 1, "Only the current snapshot may write")
        XCTAssertEqual(store.loadUnifiedSceneProject(named: project.name)?.0.sceneDescription, viewModel.sceneDescription)
    }

    @MainActor
    func testCancellingEditorWhileSnapshotPendingCannotSaveDismissedDraft() async throws {
        let (viewModel, store, project) = try fixture()
        let draft = try editedDraft(viewModel)
        let captured = expectation(description: "snapshot awaiting AR result")
        let gate = SnapshotGate(entered: captured)
        defer { gate.release() }
        viewModel.testingWorldMapCaptureOverride = { await gate.capture() }
        let snapshot = Task { await viewModel.testingPersistProjectSnapshot() }
        await fulfillment(of: [captured], timeout: 3)
        let edit = Task { await viewModel.applyStoryboardBeatEdit(draft) }
        try await waitForMutation(viewModel)
        viewModel.cancelStoryboardEditor()
        gate.release()
        _ = await snapshot.value
        let edited = await edit.value
        XCTAssertFalse(edited)
        XCTAssertNil(viewModel.activeStoryboardEditDraft)
        XCTAssertEqual(viewModel.parsedScript, project.parsedScript)
        XCTAssertEqual(store.attempts.count, 1)
    }

    @MainActor
    func testStoredVersionConflictPreservesNewerProjectAndOpenEditor() async throws {
        let (viewModel, store, project) = try fixture()
        let draft = try editedDraft(viewModel)
        var newer = project
        newer.updatedAt = project.updatedAt.addingTimeInterval(10)
        newer.sceneDescription = "A newer saved version."
        try store.saveUnifiedSceneProject(newer, worldMap: nil)
        let saved = await viewModel.applyStoryboardBeatEdit(draft)
        XCTAssertFalse(saved)
        XCTAssertEqual(store.loadUnifiedSceneProject(named: project.name)?.0, newer)
        XCTAssertEqual(viewModel.parsedScript, project.parsedScript)
        XCTAssertNotNil(viewModel.activeStoryboardEditDraft)
        XCTAssertEqual(viewModel.errorMessage, viewModel.localizedCopy(.storyboardErrorSaveConflict))
    }

    @MainActor
    func testMetadataFailureDoesNotPoisonNextVersionAndAutosaveUsesPublishedValues() throws {
        let (viewModel, store, project) = try fixture()
        store.remainingFailures = 1
        viewModel.sceneDescription = "First edit cannot be written."
        XCTAssertEqual(store.loadUnifiedSceneProject(named: project.name)?.0.sceneDescription, project.sceneDescription)
        viewModel.sceneDescription = "The second edit is saved exactly."
        XCTAssertEqual(store.loadUnifiedSceneProject(named: project.name)?.0.sceneDescription, viewModel.sceneDescription)
        XCTAssertEqual(store.attempts.count, 2)
        XCTAssertEqual(store.attempts.last?.expectedUpdatedAt, project.updatedAt)
        let marker = MarkedObject(name: "table", position: Position3D(x: 1, y: 0, z: -1))
        viewModel.markedObjects = [marker]
        XCTAssertEqual(store.loadUnifiedSceneProject(named: project.name)?.0.markedObjects, [marker])
        XCTAssertEqual(store.loadUnifiedSceneProject(named: project.name)?.0.sceneDescription, viewModel.sceneDescription)
    }

    @MainActor
    func testSnapshotFailureCanRetryAgainstUnchangedStoredVersion() async throws {
        let (viewModel, store, project) = try fixture()
        viewModel.sceneDescription = "A snapshot of the edited description."
        let editedProject = try XCTUnwrap(store.loadUnifiedSceneProject(named: project.name)?.0)
        store.attempts.removeAll()
        store.remainingFailures = 1
        let failed = await viewModel.testingPersistProjectSnapshot()
        if case .failure(let failure) = failed { XCTAssertEqual(failure, .persistenceFailed) }
        else { XCTFail("Injected write failure must keep snapshot unsuccessful") }
        let retried = await viewModel.testingPersistProjectSnapshot()
        if case .failure(let failure) = retried { XCTFail("Retry failed: \(failure)") }
        XCTAssertEqual(store.attempts.count, 2)
        XCTAssertTrue(store.attempts.allSatisfy { $0.expectedUpdatedAt == editedProject.updatedAt })
        XCTAssertEqual(store.loadUnifiedSceneProject(named: project.name)?.0.sceneDescription, viewModel.sceneDescription)
    }

    @MainActor
    func testGenerationPersistenceFailureKeepsSceneAndRetrySavesWithoutAnotherParse() async throws {
        let (viewModel, store, project) = try fixture()
        viewModel.updateGenerationMotionPreferences(reduceMotion: true)
        var parserCalls = 0
        viewModel.testingSetParserResultOverride { description, _ in
            parserCalls += 1
            return self.generatedResult(description: description)
        }
        let originalEditor = viewModel.activeStoryboardEditDraft
        store.remainingFailures = 1
        await viewModel.generateScene()
        XCTAssertEqual(viewModel.generationRequestState.phase, .retryableFailure)
        XCTAssertEqual(viewModel.generationRequestState.failure, .persistence)
        XCTAssertEqual(viewModel.testingGenerationCommitCount, 0)
        XCTAssertEqual(viewModel.parsedScript, project.parsedScript)
        XCTAssertEqual(viewModel.plannedScene, project.plannedScene)
        XCTAssertEqual(viewModel.activeStoryboardEditDraft, originalEditor)
        XCTAssertEqual(viewModel.sceneDescription, project.sceneDescription)
        XCTAssertEqual(store.loadUnifiedSceneProject(named: project.name)?.0, project)
        XCTAssertTrue(viewModel.canRetryGenerationPersistence)
        let requestID = viewModel.generationRequestState.requestID
        let epoch = viewModel.generationRequestState.epoch

        await viewModel.generateScene()
        XCTAssertEqual(parserCalls, 1, "A disk retry must not call the model again")
        XCTAssertEqual(viewModel.testingGenerationOwnerCount, 1)
        XCTAssertEqual(viewModel.testingGenerationCommitCount, 1)
        XCTAssertEqual(viewModel.generationRequestState.phase, .success)
        XCTAssertEqual(viewModel.generationRequestState.requestID, requestID)
        XCTAssertEqual(viewModel.generationRequestState.epoch, epoch)
        XCTAssertFalse(viewModel.canRetryGenerationPersistence)
        let generated = try XCTUnwrap(viewModel.parsedScript)
        XCTAssertEqual(generated.actors.first?.name, "Generated Mara")
        let origin = try XCTUnwrap(viewModel.plannedScene?.provenance)
        XCTAssertEqual(origin.acceptedContributors, [.deterministicRules(componentVersion: "fixture-generated-v1")])
        XCTAssertNil(origin.lastUserModification)
        XCTAssertTrue(store.attempts.allSatisfy { $0.project.plannedScene?.provenance == origin })
        XCTAssertEqual(store.loadUnifiedSceneProject(named: project.name)?.0.parsedScript, generated)
        XCTAssertEqual(store.attempts.count, 2)
        XCTAssertTrue(store.attempts.allSatisfy { $0.expectedUpdatedAt == project.updatedAt })

        _ = await viewModel.teardownAndWait()
        let reopened = SceneGeneratorViewModel(
            projectName: project.name, isNewProject: false, projectStore: store,
            projectLeaseRegistry: store.projectLeaseRegistry
        )
        XCTAssertEqual(reopened.parsedScript, generated)
        XCTAssertEqual(reopened.plannedScene, viewModel.plannedScene)
        XCTAssertEqual(reopened.projectID, project.id)
        _ = await reopened.teardownAndWait()
    }

    @MainActor
    func testChangingDraftAfterSaveFailureInvalidatesPreparedGeneration() async throws {
        let (viewModel, store, _) = try fixture()
        viewModel.updateGenerationMotionPreferences(reduceMotion: true)
        var parserCalls = 0
        viewModel.testingSetParserResultOverride { description, _ in
            parserCalls += 1
            return self.generatedResult(description: description)
        }
        store.remainingFailures = 1
        await viewModel.generateScene()
        let oldRequestID = viewModel.generationRequestState.requestID
        XCTAssertTrue(viewModel.canRetryGenerationPersistence)
        viewModel.sceneDescription = "A newly requested scene."
        XCTAssertFalse(viewModel.canRetryGenerationPersistence)
        await viewModel.generateScene()
        XCTAssertEqual(parserCalls, 2)
        XCTAssertNotEqual(viewModel.generationRequestState.requestID, oldRequestID)
        XCTAssertEqual(viewModel.generationRequestState.phase, .success)
        XCTAssertEqual(viewModel.parsedScript?.originalDescription, viewModel.sceneDescription)
    }

    @MainActor
    func testSceneEditedDuringParseCannotBeOverwrittenByLateGeneration() async throws {
        let (viewModel, store, project) = try fixture()
        viewModel.updateGenerationMotionPreferences(reduceMotion: true)
        let parserEntered = expectation(description: "generation awaiting parser")
        let result = generatedResult(description: project.sceneDescription)
        var pendingParse: CheckedContinuation<ParsingResult, Never>?
        var parserReleased = false
        viewModel.testingSetParserResultOverride { _, _ in
            if parserReleased { return result }
            return await withCheckedContinuation { continuation in
                pendingParse = continuation
                parserEntered.fulfill()
            }
        }
        defer {
            parserReleased = true
            pendingParse?.resume(returning: result)
        }
        let generation = Task { await viewModel.generateScene() }
        await fulfillment(of: [parserEntered], timeout: 3)
        let draft = try editedDraft(viewModel)
        let edited = await viewModel.applyStoryboardBeatEdit(draft)
        XCTAssertTrue(edited)
        let editedScript = viewModel.parsedScript
        let editedPlan = viewModel.plannedScene
        parserReleased = true
        let continuation = pendingParse
        pendingParse = nil
        continuation?.resume(returning: result)
        await generation.value

        XCTAssertEqual(viewModel.testingGenerationCommitCount, 0)
        XCTAssertEqual(viewModel.generationRequestState.failure, .cancelled)
        XCTAssertEqual(viewModel.parsedScript, editedScript)
        XCTAssertEqual(viewModel.plannedScene, editedPlan)
        XCTAssertEqual(store.attempts.count, 1, "The user edit is the only persisted replacement")
        XCTAssertEqual(store.loadUnifiedSceneProject(named: project.name)?.0.parsedScript, editedScript)
    }

    @MainActor
    func testCancellingGenerationWhileSnapshotPendingCannotPersistOrCommitCandidate() async throws {
        let (viewModel, store, project) = try fixture()
        viewModel.updateGenerationMotionPreferences(reduceMotion: true)
        viewModel.testingSetParserResultOverride { description, _ in self.generatedResult(description: description) }
        let captured = expectation(description: "snapshot awaiting AR result")
        let gate = SnapshotGate(entered: captured)
        defer { gate.release() }
        viewModel.testingWorldMapCaptureOverride = { await gate.capture() }
        let snapshot = Task { await viewModel.testingPersistProjectSnapshot() }
        await fulfillment(of: [captured], timeout: 3)
        let generation = Task { await viewModel.generateScene() }
        var deadline = Date().addingTimeInterval(3)
        while viewModel.generationRequestState.stage != .placing && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(viewModel.generationRequestState.stage, .placing)
        XCTAssertTrue(store.attempts.isEmpty)
        let cancellation = Task { await viewModel.cancelGeneration() }
        deadline = Date().addingTimeInterval(3)
        while viewModel.generationRequestState.phase != .cancelling && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(viewModel.generationRequestState.phase, .cancelling)
        gate.release()
        _ = await snapshot.value
        await cancellation.value
        await generation.value
        XCTAssertEqual(viewModel.testingGenerationCommitCount, 0)
        XCTAssertEqual(viewModel.generationRequestState.phase, .input)
        XCTAssertEqual(viewModel.parsedScript, project.parsedScript)
        XCTAssertFalse(viewModel.canRetryGenerationPersistence)
        XCTAssertEqual(store.attempts.count, 1, "Only the original snapshot is saved")
        XCTAssertEqual(store.loadUnifiedSceneProject(named: project.name)?.0.parsedScript, project.parsedScript)
    }

    @MainActor
    func testActorBeatAndTrackDragFailurePreservesPlanThenRetryReopensSavedPosition() async throws {
        for wholeTrack in [false, true] {
            let (viewModel, store, project) = try fixture(actorMovement: true)
            let actor = try XCTUnwrap(viewModel.plannedScene?.placedActors.first)
            XCTAssertTrue(actor.pathBeatIDs.contains("beat_1"), "Real planner must provide a beat-owned path")
            let originalTimeline = viewModel.beatTimelineItems
            let originalEditor = viewModel.activeStoryboardEditDraft
            let position = Position3D(x: actor.initialPosition.x + 0.4, y: 99, z: actor.initialPosition.z - 0.2)
            store.remainingFailures = 1
            let failed: Bool
            if wholeTrack {
                failed = await viewModel.commitStoryboardActorTrackDrag(actorID: actor.actorId, from: actor.initialPosition.simdVector, to: position)
            } else {
                failed = await viewModel.commitStoryboardActorDrag(actorID: actor.actorId, beatID: "beat_1", to: position)
            }
            XCTAssertFalse(failed)
            XCTAssertEqual(viewModel.plannedScene, project.plannedScene)
            XCTAssertEqual(viewModel.beatTimelineItems, originalTimeline)
            XCTAssertEqual(viewModel.activeStoryboardEditDraft, originalEditor)
            XCTAssertEqual(viewModel.storyboardDragFeedback, viewModel.localizedCopy(.storyboardErrorSave))
            XCTAssertEqual(store.loadUnifiedSceneProject(named: project.name)?.0, project)

            let retried: Bool
            if wholeTrack {
                retried = await viewModel.commitStoryboardActorTrackDrag(actorID: actor.actorId, from: actor.initialPosition.simdVector, to: position)
            } else {
                retried = await viewModel.commitStoryboardActorDrag(actorID: actor.actorId, beatID: "beat_1", to: position)
            }
            XCTAssertTrue(retried)
            let movedPlan = try XCTUnwrap(viewModel.plannedScene)
            XCTAssertNotEqual(movedPlan, project.plannedScene)
            XCTAssertEqual(movedPlan.provenance?.acceptedContributors, project.plannedScene?.provenance?.acceptedContributors)
            XCTAssertEqual(movedPlan.provenance?.lastUserModification?.kind, wholeTrack ? .actorTrackPosition : .actorBeatPosition)
            let movedActor = try XCTUnwrap(movedPlan.placedActors.first)
            XCTAssertEqual(movedActor.initialPosition.y, actor.initialPosition.y)
            XCTAssertEqual(movedActor.path.map(\.y), actor.path.map(\.y))
            XCTAssertEqual(store.attempts.count, 2)
            XCTAssertTrue(store.attempts.allSatisfy { $0.expectedUpdatedAt == project.updatedAt })
            XCTAssertEqual(store.loadUnifiedSceneProject(named: project.name)?.0.plannedScene, movedPlan)
            _ = await viewModel.teardownAndWait()
            let reopened = SceneGeneratorViewModel(projectName: project.name, isNewProject: false, projectStore: store,
                                                   projectLeaseRegistry: store.projectLeaseRegistry)
            XCTAssertEqual(reopened.plannedScene, movedPlan)
            _ = await reopened.teardownAndWait()
        }
    }

    @MainActor
    func testActorDragWaitsForSnapshotBeforeSavingAgainstItsVersion() async throws {
        let (viewModel, store, project) = try fixture(actorMovement: true)
        let actor = try XCTUnwrap(viewModel.plannedScene?.placedActors.first)
        let captured = expectation(description: "actor drag waits for snapshot")
        let gate = SnapshotGate(entered: captured)
        defer { gate.release() }
        viewModel.testingWorldMapCaptureOverride = { await gate.capture() }
        let snapshot = Task { await viewModel.testingPersistProjectSnapshot() }
        await fulfillment(of: [captured], timeout: 3)
        let drag = Task {
            await viewModel.commitStoryboardActorDrag(actorID: actor.actorId, beatID: "beat_1", to: .init(x: 0.4, y: 0, z: -0.5))
        }
        try await waitForMutation(viewModel)
        XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertEqual(viewModel.plannedScene, project.plannedScene)
        gate.release()
        _ = await snapshot.value
        let committed = await drag.value
        XCTAssertTrue(committed)
        XCTAssertEqual(store.attempts.count, 2)
        XCTAssertEqual(store.attempts.last?.expectedUpdatedAt, store.attempts.first?.project.updatedAt)
        XCTAssertEqual(store.loadUnifiedSceneProject(named: project.name)?.0.plannedScene, viewModel.plannedScene)
    }

    @MainActor
    func testPendingActorDragCannotSaveAfterEditorCancellationOrSourceEdit() async throws {
        for cancelsEditor in [false, true] {
            let (viewModel, store, project) = try fixture(actorMovement: true)
            let actor = try XCTUnwrap(viewModel.plannedScene?.placedActors.first)
            let captured = expectation(description: "pending actor drag source fence")
            let gate = SnapshotGate(entered: captured)
            defer { gate.release() }
            viewModel.testingWorldMapCaptureOverride = { await gate.capture() }
            let snapshot = Task { await viewModel.testingPersistProjectSnapshot() }
            await fulfillment(of: [captured], timeout: 3)
            let drag = Task {
                await viewModel.commitStoryboardActorDrag(actorID: actor.actorId, beatID: "beat_1", to: .init(x: 0.4, y: 0, z: -0.5))
            }
            try await waitForMutation(viewModel)
            if cancelsEditor { viewModel.cancelStoryboardEditor() }
            else { viewModel.sceneDescription = "The user revised this scene while the drag was waiting." }
            gate.release()
            _ = await snapshot.value
            let committed = await drag.value
            XCTAssertFalse(committed)
            XCTAssertEqual(viewModel.plannedScene, project.plannedScene)
            XCTAssertEqual(store.attempts.count, 1)
            XCTAssertEqual(store.loadUnifiedSceneProject(named: project.name)?.0.plannedScene, project.plannedScene)
        }
    }

    @MainActor
    func testActorTrackDragCannotOverwriteNewerStoredProject() async throws {
        let (viewModel, store, project) = try fixture(actorMovement: true)
        let actor = try XCTUnwrap(viewModel.plannedScene?.placedActors.first)
        var newer = project
        newer.updatedAt = project.updatedAt.addingTimeInterval(10)
        newer.sceneDescription = "Another writer saved this project."
        try store.saveUnifiedSceneProject(newer, worldMap: nil)
        let committed = await viewModel.commitStoryboardActorTrackDrag(
            actorID: actor.actorId, from: actor.initialPosition.simdVector, to: .init(x: 0.4, y: 0, z: -0.5)
        )
        XCTAssertFalse(committed)
        XCTAssertEqual(viewModel.plannedScene, project.plannedScene)
        XCTAssertEqual(store.loadUnifiedSceneProject(named: project.name)?.0, newer)
        XCTAssertEqual(viewModel.storyboardDragFeedback, viewModel.localizedCopy(.storyboardErrorSaveConflict))
    }

    @MainActor
    func testCompletedSnapshotWaiterCannotSuppressMetadataOrRetireNextWriter() async throws {
        let (viewModel, store, project) = try fixture()
        let firstWritten = expectation(description: "first snapshot saved before waiter returns")
        let firstReturnGate = SnapshotGate(entered: firstWritten)
        defer { firstReturnGate.release() }
        viewModel.testingProjectSnapshotWaiterReturnOverride = { _ = await firstReturnGate.capture() }
        let firstSnapshot = Task { await viewModel.testingPersistProjectSnapshot() }
        await fulfillment(of: [firstWritten], timeout: 3)
        XCTAssertEqual(store.attempts.count, 1)
        viewModel.sceneDescription = "This edit arrives after the first writer completed."
        XCTAssertEqual(store.attempts.count, 2)
        XCTAssertEqual(store.loadUnifiedSceneProject(named: project.name)?.0.sceneDescription, viewModel.sceneDescription)

        viewModel.testingProjectSnapshotWaiterReturnOverride = nil
        let secondCaptured = expectation(description: "second snapshot owns active writer")
        let secondGate = SnapshotGate(entered: secondCaptured)
        defer { secondGate.release() }
        viewModel.testingWorldMapCaptureOverride = { await secondGate.capture() }
        let secondSnapshot = Task { await viewModel.testingPersistProjectSnapshot() }
        await fulfillment(of: [secondCaptured], timeout: 3)
        firstReturnGate.release()
        _ = await firstSnapshot.value
        viewModel.sceneDescription = "This edit belongs to the active second snapshot."
        XCTAssertEqual(store.attempts.count, 2, "The old waiter must not clear the active second writer")
        secondGate.release()
        _ = await secondSnapshot.value
        XCTAssertEqual(store.attempts.count, 3)
        XCTAssertEqual(store.loadUnifiedSceneProject(named: project.name)?.0.sceneDescription, viewModel.sceneDescription)
    }
}
