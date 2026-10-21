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

    func testCancelDeleteDoesNotMutateSelectionOrInvokeProvider() {
        let provider = MockProvider()
        let id = UUID()
        provider.summaries = [makeSummary("СЦЕНА", id: id)]
        let model = SETLibraryModel(controlling: provider)
        model.reload()
        model.select(id)
        let before = model.scenes

        model.beginDelete(sceneID: id)
        model.cancelDelete()

        XCTAssertEqual(model.flow, .idle)
        XCTAssertEqual(model.selectedSceneID, id)
        XCTAssertEqual(model.scenes, before)
        XCTAssertTrue(provider.deleteRequests.isEmpty, "Cancel must not call the deletion owner.")
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

    // MARK: - UI-011 zone G focused coverage

    /// G2/G3: the empty hero (and its create CTA) exists only after a
    /// successful zero-project load; a pre-load surface is the loading state,
    /// never a fabricated empty story.
    func testEmptyStateCTAExistsOnlyForSuccessfulZeroProjectLoad() {
        let provider = MockProvider()
        let model = SETLibraryModel(controlling: provider)

        XCTAssertFalse(model.shouldShowEmptyState, "Pre-load must stay on the loading surface (G3).")

        provider.snapshotsResult = .success([])
        model.reload()
        XCTAssertTrue(model.shouldShowEmptyState, "A successful zero-project load is the only honest empty state.")

        // The empty CTA action must exist and be reachable from the idle flow.
        model.beginCreate()
        XCTAssertEqual(model.flow, .creating)

        model.cancelCreate()
        XCTAssertEqual(model.flow, .idle)
        XCTAssertTrue(model.shouldShowEmptyState, "Cancel returns to the same honest empty state.")
    }

    /// UI-011: a CTA is allowed to render only while its action exists. While
    /// a flow owns the surface the competing entries must stay inert, and the
    /// presented rename panel must always offer a working escape.
    func testLibraryCTAsAreInertOutsideIdleFlowAndCancelAlwaysEscapes() {
        let provider = MockProvider()
        let firstID = UUID()
        let secondID = UUID()
        provider.summaries = [makeSummary("А", id: firstID), makeSummary("Б", id: secondID)]
        let model = SETLibraryModel(controlling: provider)
        model.reload()

        model.beginCreate()
        XCTAssertEqual(model.flow, .creating)
        model.beginDelete(sceneID: firstID)
        model.beginRename(sceneID: secondID)
        model.select(secondID)
        XCTAssertEqual(model.flow, .creating, "Competing CTAs must stay inert while a flow owns the surface.")
        XCTAssertTrue(provider.deleteRequests.isEmpty)
        XCTAssertTrue(provider.renameRequests.isEmpty)
        model.cancelCreate()
        XCTAssertEqual(model.flow, .idle)

        model.beginRename(sceneID: firstID)
        XCTAssertEqual(model.flow, .renaming(sceneID: firstID, sceneName: "А"))
        model.select(secondID)
        model.beginCreate()
        model.beginDelete(sceneID: secondID)
        model.beginRename(sceneID: secondID)
        XCTAssertEqual(model.selectedSceneID, firstID)
        XCTAssertEqual(model.flow, .renaming(sceneID: firstID, sceneName: "А"))

        model.cancelRename()
        XCTAssertEqual(model.flow, .idle)
        XCTAssertEqual(model.renameDraft, "", "Cancel must clear the rename draft.")
        XCTAssertEqual(model.selectedSceneID, firstID, "Cancel keeps the row selection made before the flow.")
    }

    /// G6: the rename duplicate state is now presented, so an edited draft
    /// must confirm against the same target without touching persistence on
    /// the conflicting attempt.
    func testRenameDuplicatePanelStateEditsOrCancelsDeterministically() {
        let provider = MockProvider()
        let firstID = UUID()
        let secondID = UUID()
        provider.summaries = [makeSummary("А", id: firstID), makeSummary("Б", id: secondID)]
        let model = SETLibraryModel(controlling: provider)
        model.reload()

        model.beginRename(sceneID: firstID)
        XCTAssertEqual(model.renameDraft, "А", "The rename field must open pre-filled with the current name.")
        model.renameDraft = "Б"
        model.confirmRename()

        XCTAssertEqual(model.flow, .renameDuplicate(conflictingName: "Б"))
        XCTAssertTrue(provider.renameRequests.isEmpty, "A local rename duplicate must short-circuit before persistence.")

        model.renameDraft = "В"
        model.confirmRename()
        XCTAssertEqual(model.flow, .idle)
        XCTAssertEqual(model.selectedScene?.name, "В", "An edited non-conflicting draft must commit from the duplicate state.")
    }

    /// G9: a row whose owned recording is gone keeps its honest health state
    /// and localized copy; the presentation never converts it into an empty
    /// story or a fabricated preview.
    func testMissingAssetRowProjectsHonestHealthAndLocalizedCopy() {
        let provider = MockProvider()
        let id = UUID()
        provider.snapshotsResult = .success([
            SETLibrarySceneSnapshot(
                id: id,
                name: "БРОШЕННАЯ ЗАПИСЬ",
                updatedAt: Date(timeIntervalSince1970: 100),
                preview: SETLibraryPreviewMetadata(
                    kind: .metadataOnly,
                    beatCount: 2,
                    actorCount: 0,
                    objectCount: 0,
                    recordingCount: 1,
                    recordingReference: SceneRecordingReference(
                        recordingID: UUID(),
                        relativePath: "Projects/gone.mov"
                    )
                ),
                artifactHealth: .missing
            )
        ])
        let model = SETLibraryModel(controlling: provider)
        model.reload()

        XCTAssertFalse(model.shouldShowEmptyState, "A missing-asset row must never be masked as an empty library.")
        XCTAssertEqual(model.scenes.count, 1)
        XCTAssertEqual(model.scenes[0].artifactHealth, .missing)
        XCTAssertEqual(
            SETLibraryLocalizedCopy.artifactStatus(.missing),
            .libraryArtifactMissing,
            "The missing artifact state must resolve to the localized MEDIA MISSING copy."
        )
        XCTAssertEqual(
            SETLibraryLocalizedCopy.previewStatus(model.scenes[0].preview),
            .libraryPreviewRecording,
            "A dangling-but-owned reference still announces the recording kind; the health copy carries the missing state."
        )
    }

    /// G9: every artifact health state resolves to exactly one localized key.
    func testArtifactHealthCopyMappingCoversEveryState() {
        XCTAssertEqual(SETLibraryLocalizedCopy.artifactStatus(.none), .libraryArtifactNone)
        XCTAssertEqual(SETLibraryLocalizedCopy.artifactStatus(.healthy), .libraryArtifactHealthy)
        XCTAssertEqual(SETLibraryLocalizedCopy.artifactStatus(.missing), .libraryArtifactMissing)
        XCTAssertEqual(SETLibraryLocalizedCopy.artifactStatus(.corrupt), .libraryArtifactCorrupt)
        XCTAssertEqual(SETLibraryLocalizedCopy.artifactStatus(.unavailable), .libraryArtifactUnavailable)
        XCTAssertEqual(
            SETLibraryLocalizedCopy.previewStatus(SETLibraryPreviewMetadata.unavailable),
            .libraryPreviewMetadataPlaceholder,
            "No owned recording means the honest metadata placeholder."
        )
    }

    /// G9: the poster loader guard deterministically discards a missing or
    /// empty artifact to "no resolvable media" instead of fabricating a frame.
    func testMissingRecordingArtifactDeterministicallyDiscardsPosterURL() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ui011-artifact-\(UUID().uuidString)", isDirectory: true)
        let store = try RecordingArtifactStore(applicationSupportDirectoryURL: root)
        defer { try? FileManager.default.removeItem(at: root) }

        // A reference whose file never existed discards to no URL. Store
        // references resolve below Application Support and must stay inside
        // the Recordings root (production uses "Recordings/Projects/...").
        let dangling = SceneRecordingReference(recordingID: UUID(), relativePath: "Recordings/Projects/missing.mov")
        XCTAssertNil(SETLibraryPosterArtifactGuard.resolvableMediaURL(for: dangling, store: store))

        // A zero-byte artifact is damaged, not presentable.
        let emptyURL = store.recordingsDirectoryURL.appendingPathComponent("Projects/empty.mov")
        try FileManager.default.createDirectory(
            at: emptyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: emptyURL.path, contents: Data())
        let emptyReference = SceneRecordingReference(recordingID: UUID(), relativePath: "Recordings/Projects/empty.mov")
        XCTAssertNil(SETLibraryPosterArtifactGuard.resolvableMediaURL(for: emptyReference, store: store))

        // A present, non-empty artifact resolves to its URL.
        let goodURL = store.recordingsDirectoryURL.appendingPathComponent("Projects/good.mov")
        FileManager.default.createFile(atPath: goodURL.path, contents: Data([0x01]))
        let goodReference = SceneRecordingReference(recordingID: UUID(), relativePath: "Recordings/Projects/good.mov")
        XCTAssertEqual(
            SETLibraryPosterArtifactGuard.resolvableMediaURL(for: goodReference, store: store)?.standardizedFileURL,
            goodURL.standardizedFileURL
        )
    }

    /// The DEBUG fixture provider must keep serving the deterministic rename
    /// outcomes the `library.rename-name` / `library.rename-duplicate-name`
    /// fixture routes present.
    func testFixtureProviderRenameStaysDeterministicForPresentation() {
        let firstID = SETLibraryFixtureData.ids[0]
        let secondID = SETLibraryFixtureData.ids[1]
        let provider = SETLibraryFixtureProvider(scenes: SETLibraryFixtureData.summaries(locale: Locale(identifier: "ru")))

        let renamed = provider.libraryRenameSceneResult(
            id: firstID,
            to: "НОВОЕ ИМЯ",
            expectedUpdatedAt: SETLibraryFixtureData.dates[0]
        )
        guard case .success(let snapshot) = renamed else {
            return XCTFail("A valid rename against the fixture provider must succeed.")
        }
        XCTAssertEqual(snapshot.id, firstID)
        XCTAssertEqual(snapshot.name, "НОВОЕ ИМЯ")

        let conflicting = provider.libraryRenameSceneResult(
            id: firstID,
            to: SETLibraryLocalizedCopy.string(.librarySceneTwo, locale: Locale(identifier: "ru")),
            expectedUpdatedAt: snapshot.updatedAt
        )
        guard case .failure(.duplicateName(let conflictingName, let conflictingID)) = conflicting else {
            return XCTFail("A conflicting rename must surface the typed duplicate failure.")
        }
        XCTAssertEqual(conflictingID, secondID)
        XCTAssertEqual(conflictingName, SETLibraryLocalizedCopy.string(.librarySceneTwo, locale: Locale(identifier: "ru")))
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
