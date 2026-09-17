import Foundation

/// Cancelling an owner must not wait for an OS prompt to be answered. The
/// shared PermissionClient request may finish later, but its stale result can
/// only complete this one-shot value; it cannot resume the cancelled owner.
final class PermissionRequestWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<PermissionSnapshot, Error>?
    private var continuation: CheckedContinuation<PermissionSnapshot, Error>?

    static func value(
        _ operation: @escaping @Sendable () async -> PermissionSnapshot
    ) async throws -> PermissionSnapshot {
        try Task.checkCancellation()
        let waiter = PermissionRequestWaiter()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiter.install(continuation)
                Task { waiter.finish(.success(await operation())) }
            }
        } onCancel: {
            waiter.finish(.failure(CancellationError()))
        }
    }

    private func install(_ continuation: CheckedContinuation<PermissionSnapshot, Error>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    private func finish(_ result: Result<PermissionSnapshot, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
