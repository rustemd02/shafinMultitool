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

}

extension SOInteractor: SOInteractorProtocol {
    func deleteScene(with title: String) {
        DBService.shared.deleteUnifiedSceneProject(named: title) { deleted in
            _ = deleted
            self.presenter?.updateUI()
        }
    }

    func getSceneNames() -> [String] {
        DBService.shared.listUnifiedSceneProjects().map(\.name)
    }

    func getSceneSummaries() -> [UnifiedSceneProjectSummary] {
        DBService.shared.listUnifiedSceneProjects()
    }

    func createScene(named title: String) -> SETLibraryCreateOutcome {
        do {
            _ = try DBService.shared.createUnifiedSceneProject(named: title)
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
        DBService.shared.deleteUnifiedSceneProject(named: title) { deleted in
            completion(deleted)
            self.presenter?.updateUI()
        }
    }

    func getLibrarySceneSnapshots() -> Result<[SETLibrarySceneSnapshot], SETLibraryFailure> {
        DBService.shared.loadLibrarySceneSnapshots()
    }

    func createLibraryScene(named title: String) -> Result<SETLibrarySceneSnapshot, SETLibraryFailure> {
        DBService.shared.createLibraryScene(named: title)
    }

    func renameLibraryScene(
        id: UUID,
        to name: String,
        expectedUpdatedAt: Date
    ) -> Result<SETLibrarySceneSnapshot, SETLibraryFailure> {
        DBService.shared.renameUnifiedSceneProject(id: id, to: name, expectedUpdatedAt: expectedUpdatedAt)
    }

    func deleteLibraryScene(
        id: UUID,
        expectedUpdatedAt: Date,
        completion: @escaping (Result<Void, SETLibraryFailure>) -> Void
    ) {
        DBService.shared.deleteUnifiedSceneProject(id: id, expectedUpdatedAt: expectedUpdatedAt) { result in
            completion(result)
            self.presenter?.updateUI()
        }
    }
}
