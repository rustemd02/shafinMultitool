import Foundation

/// M1-016 ProjectLifecycleOwner: process-wide lease registry for open scene
/// projects. A workspace holds one lease per open project for the whole time
/// it can mutate project state; deletion consults the registry and is rejected
/// while a lease is active ("deletion is rejected while ownership cannot be
/// safely released"). Lock-guarded: callers span the persistence queue and the
/// main actor.
final class ProjectLifecycleRegistry: @unchecked Sendable {
    static let shared = ProjectLifecycleRegistry()

    private let lock = NSLock()
    private var leases: [UUID: UUID] = [:]

    init() {}

    /// Acquires the workspace lease. Returns the owner token, or nil when
    /// another owner already holds the lease.
    func acquire(projectID: UUID) -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        guard leases[projectID] == nil else { return nil }
        let token = UUID()
        leases[projectID] = token
        return token
    }

    /// Releases the lease only when the token still matches the active owner,
    /// so a stale owner cannot drop a newer lease.
    func release(projectID: UUID, token: UUID) {
        lock.lock()
        defer { lock.unlock() }
        if leases[projectID] == token {
            leases.removeValue(forKey: projectID)
        }
    }

    func isLeased(projectID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return leases[projectID] != nil
    }
}
