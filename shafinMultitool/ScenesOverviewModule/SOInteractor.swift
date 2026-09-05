//
//  SOInteractor.swift
//  shafinMultitool
//
//  Created by Рустем on 07.11.2023.
//

import Foundation

protocol SOInteractorProtocol: AnyObject {
    func deleteScene(with title: String)
    func getSceneNames() -> [String]
    func getSceneSummaries() -> [UnifiedSceneProjectSummary]
    func createScene(named title: String) -> SETLibraryCreateOutcome
    func deleteScene(with title: String, completion: @escaping (Bool) -> Void)

    func getLibrarySceneSnapshots() -> Result<[SETLibrarySceneSnapshot], SETLibraryFailure>
    func createLibraryScene(named title: String) -> Result<SETLibrarySceneSnapshot, SETLibraryFailure>
    func renameLibraryScene(
        id: UUID,
        to name: String,
        expectedUpdatedAt: Date
    ) -> Result<SETLibrarySceneSnapshot, SETLibraryFailure>
    func deleteLibraryScene(
        id: UUID,
        expectedUpdatedAt: Date,
        completion: @escaping (Result<Void, SETLibraryFailure>) -> Void
    )
}

class SOInteractor {
    weak var presenter: SOPresenterProtocol?
    private var sceneNames: [String] = []
    private let projectStore: DBService

    init(projectStore: DBService = .shared) {
        self.projectStore = projectStore
    }

}

extension SOInteractor: SOInteractorProtocol {
    func deleteScene(with title: String) {
        projectStore.deleteUnifiedSceneProject(named: title) { deleted in
            _ = deleted
            self.presenter?.updateUI()
        }
    }

    func getSceneNames() -> [String] {
        projectStore.listUnifiedSceneProjects().map(\.name)
    }

    func getSceneSummaries() -> [UnifiedSceneProjectSummary] {
        projectStore.listUnifiedSceneProjects()
    }

    func createScene(named title: String) -> SETLibraryCreateOutcome {
        do {
            _ = try projectStore.createUnifiedSceneProject(named: title)
            return .created
        } catch let error as NSError where error.domain == "DBService" {
            switch error.code {
            case 1: return .invalidName
            case 2: return .duplicateName
            default: return .persistenceFailure
            }
        } catch {
            return .persistenceFailure
        }
    }

    func deleteScene(with title: String, completion: @escaping (Bool) -> Void) {
        projectStore.deleteUnifiedSceneProject(named: title) { deleted in
            completion(deleted)
            self.presenter?.updateUI()
        }
    }

    func getLibrarySceneSnapshots() -> Result<[SETLibrarySceneSnapshot], SETLibraryFailure> {
        projectStore.loadLibrarySceneSnapshots()
    }

    func createLibraryScene(named title: String) -> Result<SETLibrarySceneSnapshot, SETLibraryFailure> {
        projectStore.createLibraryScene(named: title)
    }

    func renameLibraryScene(
        id: UUID,
        to name: String,
        expectedUpdatedAt: Date
    ) -> Result<SETLibrarySceneSnapshot, SETLibraryFailure> {
        projectStore.renameUnifiedSceneProject(id: id, to: name, expectedUpdatedAt: expectedUpdatedAt)
    }

    func deleteLibraryScene(
        id: UUID,
        expectedUpdatedAt: Date,
        completion: @escaping (Result<Void, SETLibraryFailure>) -> Void
    ) {
        projectStore.deleteUnifiedSceneProject(id: id, expectedUpdatedAt: expectedUpdatedAt) { result in
            completion(result)
            self.presenter?.updateUI()
        }
    }
}
