import XCTest
@testable import shafinMultitool

@MainActor
final class SETLibraryModelTests: XCTestCase {
    private final class MockProvider: SETLibrarySceneProviding {
        var summaries: [UnifiedSceneProjectSummary] = []
        var createOutcome: SETLibraryCreateOutcome = .created
        var deleteResult = true
        private(set) var createdNames: [String] = []
        private(set) var deletedNames: [String] = []
        private(set) var openedNames: [String] = []

        func librarySceneSummaries() -> [UnifiedSceneProjectSummary] {
            summaries
        }

        func libraryCreateScene(named name: String) -> SETLibraryCreateOutcome {
            createdNames.append(name)
            return createOutcome
        }

        func libraryDeleteScene(named name: String, completion: @escaping (Bool) -> Void) {
            deletedNames.append(name)
            completion(deleteResult)
        }

        func libraryOpenScene(named name: String) {
            openedNames.append(name)
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

    func testConfirmCreateIgnoresEmptyDraft() {
        let provider = MockProvider()
        let model = SETLibraryModel(controlling: provider)
        model.beginCreate()
        model.createDraft = "   "
        model.confirmCreate()

        XCTAssertTrue(provider.createdNames.isEmpty)
        XCTAssertEqual(model.flow, .creating)
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

        XCTAssertEqual(model.flow, .failure(.create))

        provider.createOutcome = .created
        model.retry()
        XCTAssertEqual(provider.createdNames, ["СЦЕНА", "СЦЕНА"], "Retry must honestly re-run the failed create.")
        XCTAssertEqual(provider.openedNames, ["СЦЕНА"])
        XCTAssertEqual(model.flow, .idle)
    }

    func testDeleteConfirmationReloadsOnlyOnSuccess() async {
        let provider = MockProvider()
        provider.summaries = [makeSummary("А"), makeSummary("Б")]
        let model = SETLibraryModel(controlling: provider)
        model.reload()
        model.select(model.scenes[0].id)
        model.beginDelete(sceneName: "А")

        XCTAssertEqual(model.flow, .deleting(sceneName: "А"))

        provider.deleteResult = true
        provider.summaries = [makeSummary("Б")]
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
        model.confirmDelete()
        await drainMainActor()

        XCTAssertEqual(model.flow, .failure(.delete))
        XCTAssertEqual(model.scenes.map(\.name), ["А"], "A failed delete must not lose data.")

        provider.deleteResult = true
        provider.summaries = []
        model.retry()
        await drainMainActor()
        XCTAssertEqual(provider.deletedNames, ["А", "А"], "Retry must re-run the failed delete.")
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
        let model = SETLibraryModel(controlling: provider)
        model.beginCreate()
        model.createDraft = "ЧЕРНОВИК"
        model.cancelCreate()

        XCTAssertEqual(model.flow, .idle)
        XCTAssertEqual(model.createDraft, "")

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
