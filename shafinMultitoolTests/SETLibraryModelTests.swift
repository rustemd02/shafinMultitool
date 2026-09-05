import XCTest
@testable import shafinMultitool

@MainActor
final class SETLibraryModelTests: XCTestCase {
    private final class MockProvider: SETLibrarySceneProviding {
        var summaries: [UnifiedSceneProjectSummary] = []
        var createOutcome: SETLibraryCreateOutcome = .created
        var deleteResult = true
        var snapshotsResult: Result<[SETLibrarySceneSnapshot], SETLibraryFailure>?
        var renameResult: Result<SETLibrarySceneSnapshot, SETLibraryFailure>?
        var openResult: Result<Void, SETLibraryFailure> = .success(())
        private(set) var createdNames: [String] = []
        private(set) var deletedNames: [String] = []
        private(set) var openedNames: [String] = []
        private(set) var openRequests: [UUID] = []
        private(set) var snapshotCallCount = 0
        private(set) var renameRequests: [(id: UUID, name: String, expectedUpdatedAt: Date)] = []
        private(set) var deleteRequests: [(id: UUID, expectedUpdatedAt: Date)] = []

        func librarySceneSummaries() -> [UnifiedSceneProjectSummary] {
            summaries
        }

        func libraryCreateScene(named name: String) -> SETLibraryCreateOutcome {
            createdNames.append(name)
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return .invalidName }
            if createOutcome == .created {
                summaries.append(
                    UnifiedSceneProjectSummary(id: UUID(), name: trimmed, updatedAt: Date(timeIntervalSince1970: 1_787_000_000))
                )
            }
            return createOutcome
        }

        func libraryDeleteScene(named name: String, completion: @escaping (Bool) -> Void) {
            deletedNames.append(name)
            if deleteResult {
                summaries.removeAll { $0.name == name }
            }
            completion(deleteResult)
        }

        func libraryOpenScene(named name: String) {
            openedNames.append(name)
        }

        func librarySceneSnapshots() -> Result<[SETLibrarySceneSnapshot], SETLibraryFailure> {
            snapshotCallCount += 1
            if let snapshotsResult { return snapshotsResult }
            return .success(summaries.map {
                SETLibrarySceneSnapshot(id: $0.id, name: $0.name, updatedAt: $0.updatedAt)
            })
        }

        func libraryCreateSceneResult(named name: String) -> Result<SETLibrarySceneSnapshot, SETLibraryFailure> {
            switch libraryCreateScene(named: name) {
            case .created:
                guard let summary = summaries.first(where: { $0.name == name }) else { return .failure(.persistence) }
                return .success(SETLibrarySceneSnapshot(id: summary.id, name: summary.name, updatedAt: summary.updatedAt))
            case .invalidName: return .failure(.invalidName)
            case .duplicateName: return .failure(.duplicateName(name: name, conflictingID: nil))
            case .persistenceFailure: return .failure(.persistence)
            }
        }

        func libraryRenameSceneResult(
            id: UUID,
            to name: String,
            expectedUpdatedAt: Date
        ) -> Result<SETLibrarySceneSnapshot, SETLibraryFailure> {
            renameRequests.append((id: id, name: name, expectedUpdatedAt: expectedUpdatedAt))
            if let renameResult { return renameResult }
            guard let index = summaries.firstIndex(where: { $0.id == id }) else { return .failure(.missingProject(id: id)) }
            guard summaries[index].updatedAt == expectedUpdatedAt else {
                return .failure(.staleSnapshot(expectedUpdatedAt: expectedUpdatedAt, storedUpdatedAt: summaries[index].updatedAt))
            }
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failure(.invalidName) }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let duplicate = summaries.first(where: { $0.id != id && $0.name == trimmed }) {
                return .failure(.duplicateName(name: trimmed, conflictingID: duplicate.id))
            }
            let updated = UnifiedSceneProjectSummary(id: id, name: trimmed, updatedAt: Date())
            summaries[index] = updated
            return .success(SETLibrarySceneSnapshot(id: id, name: trimmed, updatedAt: updated.updatedAt))
        }

        func libraryDeleteSceneResult(
            id: UUID,
            expectedUpdatedAt: Date,
            completion: @escaping (Result<Void, SETLibraryFailure>) -> Void
        ) {
            deleteRequests.append((id: id, expectedUpdatedAt: expectedUpdatedAt))
            guard let scene = summaries.first(where: { $0.id == id }) else {
                completion(.failure(.missingProject(id: id)))
                return
            }
            guard scene.updatedAt == expectedUpdatedAt else {
                completion(.failure(.staleSnapshot(expectedUpdatedAt: expectedUpdatedAt, storedUpdatedAt: scene.updatedAt)))
                return
            }
            libraryDeleteScene(named: scene.name) { deleted in
                completion(deleted ? .success(()) : .failure(.persistence))
            }
        }

        func libraryOpenSceneResult(id: UUID) -> Result<Void, SETLibraryFailure> {
            openRequests.append(id)
            guard let scene = summaries.first(where: { $0.id == id }) else { return .failure(.missingProject(id: id)) }
            if case .failure(let failure) = openResult { return .failure(failure) }
            libraryOpenScene(named: scene.name)
            return .success(())
        }
    }

    private func makeSummary(_ name: String, id: UUID = UUID()) -> UnifiedSceneProjectSummary {
        UnifiedSceneProjectSummary(id: id, name: name, updatedAt: Date(timeIntervalSince1970: 1_787_000_000))
    }

    func testReloadProjectsSummariesAndDropsStaleSelection() {
        let provider = MockProvider()
        let model = SETLibraryModel(controlling: provider)

        let keptID = UUID()
        provider.summaries = [makeSummary("А", id: keptID), makeSummary("Б", id: UUID())]
        model.reload()
        model.select(keptID)
        XCTAssertEqual(model.selectedScene?.name, "А")

        provider.summaries = [makeSummary("Б", id: UUID())]
        model.reload()
        XCTAssertNil(model.selectedScene, "A disappeared scene must clear the selection projection.")
    }

    func testTypedLoadFailureIsNotPresentedAsEmptyLibrary() {
        let provider = MockProvider()
        provider.snapshotsResult = .failure(.persistence)
        let model = SETLibraryModel(controlling: provider)

        model.reload()

        XCTAssertTrue(model.scenes.isEmpty)
        XCTAssertEqual(model.flow, .failure(.load(.persistence)))
        XCTAssertFalse(model.shouldShowEmptyState, "Load failure must replace the empty-state hero.")
        XCTAssertNotNil(model.loadFailure)
    }

    func testEmptyStateRequiresSuccessfulZeroProjectLoad() {
        let provider = MockProvider()
        let model = SETLibraryModel(controlling: provider)

        XCTAssertFalse(model.shouldShowEmptyState, "A pre-load empty array is not an empty-store result.")

        provider.snapshotsResult = .success([])
        model.reload()
        XCTAssertTrue(model.shouldShowEmptyState)

        provider.snapshotsResult = .failure(.persistence)
        model.reload()
        XCTAssertFalse(model.shouldShowEmptyState, "A later load failure must hide the empty hero.")
    }

    func testReloadOrdersDuplicateNamesByUpdatedAtThenUUIDAndKeepsMetadata() {
        let provider = MockProvider()
        let olderID = UUID(uuidString: "00000000-0000-4000-8000-000000000010")!
        let firstTieID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let secondTieID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        provider.snapshotsResult = .success([
            SETLibrarySceneSnapshot(
                id: olderID,
                name: "ДУБЛЬ",
                updatedAt: older,
                preview: .unavailable,
                artifactHealth: .missing
            ),
            SETLibrarySceneSnapshot(
                id: secondTieID,
                name: "ДУБЛЬ",
                updatedAt: newer,
                preview: SETLibraryPreviewMetadata(
                    kind: .storyboard,
                    beatCount: 3,
                    actorCount: 2,
                    objectCount: 1,
                    recordingCount: 1
                ),
                artifactHealth: .healthy
            ),
            SETLibrarySceneSnapshot(
                id: firstTieID,
                name: "ТРЕТИЙ",
                updatedAt: newer,
                preview: .unavailable,
                artifactHealth: .none
            )
        ])
        let model = SETLibraryModel(controlling: provider)

        model.reload()

        XCTAssertEqual(model.scenes.map(\.id), [firstTieID, secondTieID, olderID])
        XCTAssertEqual(model.scenes[0].name, "ТРЕТИЙ")
        XCTAssertEqual(model.scenes[1].name, "ДУБЛЬ")
        XCTAssertEqual(model.scenes[1].preview.beatCount, 3)
        XCTAssertEqual(model.scenes[1].artifactHealth, .healthy)
        XCTAssertEqual(model.scenes[2].artifactHealth, .missing)
    }

    func testSelectRequiresIdleFlow() {
        let provider = MockProvider()
        provider.summaries = [makeSummary("А"), makeSummary("Б")]
        let model = SETLibraryModel(controlling: provider)
        model.reload()

        model.beginCreate()
        let otherID = model.scenes[1].id
        model.select(otherID)
        XCTAssertNotEqual(model.selectedSceneID, otherID, "Selection must not change while a flow owns the surface.")
    }

    func testConfirmCreateTrimsDraftAndOpensSceneOnSuccess() {
        let provider = MockProvider()
        provider.summaries = [makeSummary("А")]
        let model = SETLibraryModel(controlling: provider)
        model.reload()
        model.beginCreate()
        model.createDraft = "  ЭКСТ. КРЫША — РАССВЕТ \n"
        model.confirmCreate()

        XCTAssertEqual(provider.createdNames, ["ЭКСТ. КРЫША — РАССВЕТ"])
        XCTAssertEqual(provider.openedNames, ["ЭКСТ. КРЫША — РАССВЕТ"], "A created scene must route into the workspace.")
        XCTAssertEqual(model.flow, .idle)
    }

    func testConfirmCreateReportsInvalidDraft() {
        let provider = MockProvider()
        let model = SETLibraryModel(controlling: provider)
        model.beginCreate()
        model.createDraft = "   "
        model.confirmCreate()

        XCTAssertTrue(provider.createdNames.isEmpty)
        XCTAssertEqual(model.flow, .failure(.create(.invalidName)))
    }

    func testOpenRetrySuccessReturnsToIdleAndClearsRetry() {
        let provider = MockProvider()
        let id = UUID()
        provider.summaries = [makeSummary("СЦЕНА", id: id)]
        let model = SETLibraryModel(controlling: provider)
        model.reload()
        model.select(id)

        provider.openResult = .failure(.persistence)
        model.openSelectedScene()
        XCTAssertEqual(model.flow, .failure(.open(.persistence)))

        provider.openResult = .success(())
        model.retry()
        XCTAssertEqual(model.flow, .idle)
        XCTAssertEqual(provider.openRequests, [id, id])

        model.retry()
        XCTAssertEqual(provider.openRequests, [id, id], "A successful open retry must clear the captured retry operation.")
    }

    func testLocalDuplicateEntersDuplicateFlowWithoutTouchingPersistence() {
        let provider = MockProvider()
        provider.summaries = [makeSummary("ИНТ. КУХНЯ — НОЧЬ")]
        let model = SETLibraryModel(controlling: provider)
        model.reload()
        model.beginCreate()
        model.createDraft = "ИНТ. КУХНЯ — НОЧЬ"
        model.confirmCreate()

        XCTAssertTrue(provider.createdNames.isEmpty, "A local duplicate must short-circuit before persistence.")
        XCTAssertEqual(model.flow, .duplicate(conflictingName: "ИНТ. КУХНЯ — НОЧЬ"))
    }

    func testProviderDuplicateMapsToDuplicateFlow() {
        let provider = MockProvider()
        provider.createOutcome = .duplicateName
        let model = SETLibraryModel(controlling: provider)
        model.beginCreate()
        model.createDraft = "СЦЕНА"
        model.confirmCreate()

        XCTAssertEqual(model.flow, .duplicate(conflictingName: "СЦЕНА"))
    }

    func testCreatePersistenceFailureShowsRecoveryAndRetrySucceeds() {
        let provider = MockProvider()
        provider.createOutcome = .persistenceFailure
        let model = SETLibraryModel(controlling: provider)
        model.beginCreate()
        model.createDraft = "СЦЕНА"
        model.confirmCreate()

        XCTAssertEqual(model.flow, .failure(.create(.persistence)))

        provider.createOutcome = .created
        model.retry()
        XCTAssertEqual(provider.createdNames, ["СЦЕНА", "СЦЕНА"], "Retry must honestly re-run the failed create.")
        XCTAssertEqual(provider.openedNames, ["СЦЕНА"])
        XCTAssertEqual(provider.snapshotCallCount, 0, "Create retry must not perform an unrelated reload.")
        XCTAssertEqual(model.flow, .idle)
    }

    func testReloadDoesNotEraseMutationFailureRecovery() {
        let provider = MockProvider()
        provider.createOutcome = .persistenceFailure
        let model = SETLibraryModel(controlling: provider)
        model.beginCreate()
        model.createDraft = "СЦЕНА"
        model.confirmCreate()

        XCTAssertEqual(model.flow, .failure(.create(.persistence)))
        model.reload()
        XCTAssertEqual(model.flow, .failure(.create(.persistence)))

        provider.createOutcome = .created
        model.retry()
        XCTAssertEqual(model.flow, .idle)
    }

    func testRenameUsesStableIDAndExpectedSnapshot() {
        let provider = MockProvider()
        let id = UUID()
        provider.summaries = [makeSummary("СТАРОЕ", id: id)]
        let model = SETLibraryModel(controlling: provider)
        model.reload()
        model.select(id)
        model.beginRename(sceneID: id)
        model.renameDraft = "  НОВОЕ  "

        model.confirmRename()

        XCTAssertEqual(model.selectedScene?.id, id)
        XCTAssertEqual(model.selectedScene?.name, "НОВОЕ")
        XCTAssertEqual(model.flow, .idle)
    }

    func testRenameDuplicateIsTypedAndDoesNotMutateProvider() {
        let provider = MockProvider()
        let firstID = UUID()
        let secondID = UUID()
        provider.summaries = [makeSummary("А", id: firstID), makeSummary("Б", id: secondID)]
        let model = SETLibraryModel(controlling: provider)
        model.reload()
        model.beginRename(sceneID: firstID)
        model.renameDraft = "Б"

        model.confirmRename()

        XCTAssertEqual(model.flow, .renameDuplicate(conflictingName: "Б"))
        XCTAssertEqual(provider.summaries.map(\.name), ["А", "Б"])
    }

    func testRenameRetryRetainsIDDraftAndExpectedTimestampAfterReload() {
        let provider = MockProvider()
        let id = UUID()
        let expectedUpdatedAt = Date(timeIntervalSince1970: 1_787_000_000)
        provider.summaries = [UnifiedSceneProjectSummary(id: id, name: "СТАРОЕ", updatedAt: expectedUpdatedAt)]
        provider.renameResult = .failure(.persistence)
        let model = SETLibraryModel(controlling: provider)
        model.reload()
        model.beginRename(sceneID: id)
        model.renameDraft = "НОВОЕ"
        model.confirmRename()

        XCTAssertEqual(model.renameDraft, "НОВОЕ")
        provider.summaries = [
            UnifiedSceneProjectSummary(
                id: id,
                name: "ИЗМЕНЕНО СНАРУЖИ",
                updatedAt: expectedUpdatedAt.addingTimeInterval(1)
            )
        ]
        model.reload()
        provider.renameResult = .success(
            SETLibrarySceneSnapshot(id: id, name: "НОВОЕ", updatedAt: expectedUpdatedAt.addingTimeInterval(2))
        )

        model.retry()

        XCTAssertEqual(provider.renameRequests.count, 2)
        XCTAssertEqual(provider.renameRequests[1].id, id)
        XCTAssertEqual(provider.renameRequests[1].name, "НОВОЕ")
        XCTAssertEqual(provider.renameRequests[1].expectedUpdatedAt, expectedUpdatedAt)
        XCTAssertEqual(model.selectedSceneID, id)
        XCTAssertEqual(model.selectedScene?.name, "НОВОЕ")
        XCTAssertEqual(model.flow, .idle)
    }

    func testDeleteConfirmationReloadsOnlyOnSuccess() async {
        let provider = MockProvider()
        let expectedID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        provider.summaries = [makeSummary("А", id: expectedID), makeSummary("Б", id: secondID)]
        let model = SETLibraryModel(controlling: provider)
        model.reload()
        model.select(expectedID)
        model.beginDelete(sceneName: "А")
        let expectedUpdatedAt = provider.summaries[0].updatedAt

        XCTAssertEqual(
            model.flow,
            .deleting(sceneID: expectedID, sceneName: "А", expectedUpdatedAt: expectedUpdatedAt)
        )

        provider.deleteResult = true
        model.confirmDelete()
        await drainMainActor()
        XCTAssertEqual(model.flow, .idle)
        XCTAssertEqual(model.scenes.map(\.name), ["Б"])
    }

    func testDeleteFailureKeepsSceneAndOffersRetry() async {
        let provider = MockProvider()
        provider.summaries = [makeSummary("А")]
        provider.deleteResult = false
        let model = SETLibraryModel(controlling: provider)
        model.reload()
        model.select(model.scenes[0].id)
        model.beginDelete(sceneName: "А")
        let expectedID = model.scenes[0].id
        let expectedUpdatedAt = provider.summaries[0].updatedAt
        model.confirmDelete()
        await drainMainActor()

        XCTAssertEqual(model.flow, .failure(.delete(.persistence)))
        XCTAssertEqual(model.scenes.map(\.name), ["А"], "A failed delete must not lose data.")

        provider.deleteResult = true
        model.retry()
        await drainMainActor()
        XCTAssertEqual(provider.deletedNames, ["А", "А"], "Retry must re-run the failed delete.")
        XCTAssertEqual(provider.deleteRequests.count, 2)
        XCTAssertEqual(provider.deleteRequests[1].id, expectedID)
        XCTAssertEqual(provider.deleteRequests[1].expectedUpdatedAt, expectedUpdatedAt)
        XCTAssertEqual(model.flow, .idle)
    }

    /// Lets the model's main-actor completion hop run before asserting.
    private func drainMainActor() async {
        for _ in 0..<50 {
            await Task.yield()
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        await Task.yield()
    }

    func testCancelFlowsReturnToIdleAndClearDraft() {
        let provider = MockProvider()
        provider.summaries = [makeSummary("А")]
        let model = SETLibraryModel(controlling: provider)
        model.beginCreate()
        model.createDraft = "ЧЕРНОВИК"
        model.cancelCreate()

        XCTAssertEqual(model.flow, .idle)
        XCTAssertEqual(model.createDraft, "")

        model.reload()
        model.beginDelete(sceneName: "А")
        model.cancelDelete()
        XCTAssertEqual(model.flow, .idle)
    }
}

@MainActor
final class SETLibraryInteractorOutcomeTests: XCTestCase {
    private func uniqueSceneName() -> String {
        "SETLibraryTests-\(UUID().uuidString.prefix(8))"
    }

    func testCreateSceneMapsDBServiceOutcomes() {
        let interactor = SOInteractor()
        let name = uniqueSceneName()
        defer {
            let deleted = expectation(description: "delete")
            DBService.shared.deleteUnifiedSceneProject(named: name) { _ in deleted.fulfill() }
            wait(for: [deleted], timeout: 5)
        }

        XCTAssertEqual(interactor.createScene(named: "  "), .invalidName)
        XCTAssertEqual(interactor.createScene(named: name), .created)
        XCTAssertEqual(interactor.createScene(named: name), .duplicateName, "DBService code 2 must surface as duplicateName.")
        XCTAssertEqual(interactor.getSceneSummaries().contains { $0.name == name }, true)
    }

    func testDeleteSceneCompletionReportsMissingProject() {
        let interactor = SOInteractor()
        let missing = expectation(description: "missing delete reports false")
        interactor.deleteScene(with: uniqueSceneName()) { deleted in
            XCTAssertFalse(deleted)
            missing.fulfill()
        }
        wait(for: [missing], timeout: 5)
    }
}
