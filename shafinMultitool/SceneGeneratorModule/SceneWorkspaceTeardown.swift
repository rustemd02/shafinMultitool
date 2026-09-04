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
    typealias AsyncAction = @MainActor () async -> Void
    typealias PersistenceAction = @MainActor () async -> Result<Void, SceneWorkspaceTeardownFailure>

    private let stopRecordingIfNeeded: AsyncAction
    private let releaseRecordingIfNeeded: AsyncAction
    private let stopPlaybackIfNeeded: SynchronousAction
    private let persist: PersistenceAction
    private let pauseAndDetach: SynchronousAction
    private var teardownTask: Task<SceneWorkspaceTeardownResult, Never>?

    init(
        stopRecordingIfNeeded: @escaping AsyncAction,
        stopPlaybackIfNeeded: @escaping SynchronousAction,
        persist: @escaping PersistenceAction,
        pauseAndDetach: @escaping SynchronousAction,
        releaseRecordingIfNeeded: @escaping AsyncAction = {}
    ) {
        self.stopRecordingIfNeeded = stopRecordingIfNeeded
        self.releaseRecordingIfNeeded = releaseRecordingIfNeeded
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

            await self.stopRecordingIfNeeded()
            self.stopPlaybackIfNeeded()

            switch await self.persist() {
            case .success:
                await self.releaseRecordingIfNeeded()
                self.pauseAndDetach()
                return .released
            case .failure(let failure):
                self.teardownTask = nil
                return .blocked(failure)
            }
        }
        teardownTask = task
        return await task.value
    }
}
