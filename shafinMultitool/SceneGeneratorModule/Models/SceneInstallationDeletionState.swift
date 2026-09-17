import Foundation

/// Local presentation of one installation's deletion. A missing/expired receipt
/// never becomes complete, and opening the presentation does not contact a server.
enum SceneInstallationDeletionState: Equatable, Sendable {
    case unavailable
    case noInstallation
    case ready
    case working
    case pending
    case complete
    case uncertain
    case failed(InstallationDeletionError)
}

protocol SceneInstallationDeletionProviding: Sendable {
    func installationDeletionState() async -> SceneInstallationDeletionState
    func beginInstallationDeletion() async -> SceneInstallationDeletionState
    func resumeInstallationDeletion() async -> SceneInstallationDeletionState
}
