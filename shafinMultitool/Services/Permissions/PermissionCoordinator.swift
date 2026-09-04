import Foundation

/// M1-005 PermissionOwner: one coordinator through which production callers
/// reach the permission system. Concurrent `request` calls for the same
/// permission coalesce into a single client request, and every joined caller
/// receives the same completed snapshot exactly once. A cancelled waiter
/// cannot publish or drop another caller's in-flight request; snapshots are
/// always live and bypass the request fence.
actor PermissionCoordinator: PermissionClient {
    private let client: any PermissionClient
    private var inFlightRequests: [AppPermission: Task<PermissionSnapshot, Never>] = [:]

    init(client: any PermissionClient) {
        self.client = client
    }

    func snapshot(for permission: AppPermission) async -> PermissionSnapshot {
        await client.snapshot(for: permission)
    }

    func request(_ permission: AppPermission) async -> PermissionSnapshot {
        if let existing = inFlightRequests[permission] {
            return await existing.value
        }

        let task = Task { [client] in
            await client.request(permission)
        }
        inFlightRequests[permission] = task
        let snapshot = await task.value
        // Safe to clear unconditionally: the actor fence means any caller that
        // arrived before this resume joined `task`, and a caller arriving after
        // this clear starts a fresh request. A cancelled initiator still
        // resumes here, so it cannot drop or publish anyone else's state.
        if inFlightRequests[permission] != nil {
            inFlightRequests[permission] = nil
        }
        return snapshot
    }
}
