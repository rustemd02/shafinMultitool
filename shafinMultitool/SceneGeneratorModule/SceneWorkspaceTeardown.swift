import Foundation

enum SceneWorkspaceTeardownFailure: Error, Equatable, Sendable {
    case worldMapSnapshotFailed
    case persistenceFailed
    case workspaceOwnerUnavailable
}

enum SceneWorkspaceTeardownResult: Equatable, Sendable {
    case released
    case blocked(SceneWorkspaceTeardownFailure)
}

protocol SceneWorkspaceTeardownProviding: AnyObject {
    @MainActor
    func teardownAndWait() async -> SceneWorkspaceTeardownResult
}

protocol SceneWorkspaceHostingControllerProviding: AnyObject {
    var sceneWorkspaceTeardownProvider: (any SceneWorkspaceTeardownProviding)? { get set }
}

@MainActor
final class SceneWorkspaceTeardownCoordinator: SceneWorkspaceTeardownProviding {
    typealias SynchronousAction = @MainActor () -> Void
    typealias PersistenceAction = @MainActor () async -> Result<Void, SceneWorkspaceTeardownFailure>

    private let stopRecordingIfNeeded: SynchronousAction
    private let stopPlaybackIfNeeded: SynchronousAction
    private let persist: PersistenceAction
    private let pauseAndDetach: SynchronousAction
    private var teardownTask: Task<SceneWorkspaceTeardownResult, Never>?

    init(
        stopRecordingIfNeeded: @escaping SynchronousAction,
        stopPlaybackIfNeeded: @escaping SynchronousAction,
        persist: @escaping PersistenceAction,
        pauseAndDetach: @escaping SynchronousAction
    ) {
        self.stopRecordingIfNeeded = stopRecordingIfNeeded
        self.stopPlaybackIfNeeded = stopPlaybackIfNeeded
        self.persist = persist
        self.pauseAndDetach = pauseAndDetach
    }

    func teardownAndWait() async -> SceneWorkspaceTeardownResult {
        if let teardownTask {
            return await teardownTask.value
        }

        let task = Task<SceneWorkspaceTeardownResult, Never> { @MainActor [weak self] in
            guard let self else {
                return .blocked(.workspaceOwnerUnavailable)
            }

            self.stopRecordingIfNeeded()
            self.stopPlaybackIfNeeded()

            switch await self.persist() {
            case .success:
                self.pauseAndDetach()
                return .released
            case .failure(let failure):
                return .blocked(failure)
            }
        }
        teardownTask = task
        return await task.value
    }
}
