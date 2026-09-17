import Combine
import Foundation

/// Owns the Privacy sheet's presentation only. The service's identity actor owns
/// durable deletion state, credentials and request recovery.
@MainActor
final class SETInstallationDeletionPresentation: ObservableObject {
    @Published private(set) var state: SceneInstallationDeletionState = .unavailable
    @Published private(set) var isLoading = true
    @Published private(set) var isPerformingAction = false
    @Published var isConfirmationPresented = false

    private let provider: (any SceneInstallationDeletionProviding)?
    private let pollDelay: @Sendable () async throws -> Void
    private let maximumAutomaticChecks: Int
    private var isVisible = false
    private var confirmationRequested = false
    private var localReadID = UUID()
    private var pollID = UUID()
    private var pollingTask: Task<Void, Never>?

    init(
        provider: (any SceneInstallationDeletionProviding)?,
        maximumAutomaticChecks: Int = 5,
        pollDelay: @escaping @Sendable () async throws -> Void = {
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
    ) {
        self.provider = provider
        self.maximumAutomaticChecks = max(0, maximumAutomaticChecks)
        self.pollDelay = pollDelay
    }

    /// A local state read only, including when an earlier request is pending.
    /// Opening Privacy must never start enrollment, deletion or receipt requests.
    func appear() async {
        isVisible = true
        stopPolling()
        cancelDeletionConfirmation()
        guard !isPerformingAction else { return }
        let readID = UUID()
        localReadID = readID
        isLoading = true
        let current = await provider?.installationDeletionState() ?? .unavailable
        guard isVisible, localReadID == readID, !Task.isCancelled else { return }
        state = current
        isLoading = false
    }

    /// Cancels future UI polling only. It does not cancel server deletion,
    /// delete a receipt, reset credentials or assert that an operation completed.
    /// The returned task allows a caller to wait for this view's observer to stop.
    @discardableResult
    func disappear() -> Task<Void, Never>? {
        isVisible = false
        localReadID = UUID()
        isLoading = false
        cancelDeletionConfirmation()
        return stopPolling()
    }

    var canRequestDeletion: Bool {
        isVisible && !isLoading && !isPerformingAction && state == .ready
    }

    var canCheckStatus: Bool {
        guard isVisible, !isLoading, !isPerformingAction, provider != nil else { return false }
        switch state {
        case .working, .pending, .uncertain, .failed:
            return true
        case .unavailable, .noInstallation, .ready, .complete:
            return false
        }
    }

    func requestDeletionConfirmation() {
        guard canRequestDeletion else { return }
        confirmationRequested = true
        isConfirmationPresented = true
    }

    func cancelDeletionConfirmation() {
        confirmationRequested = false
        isConfirmationPresented = false
    }

    func confirmDeletion() async {
        // SwiftUI may reset an alert's binding before its button task executes.
        // The outstanding confirmation request survives that presentation reset.
        guard confirmationRequested, canRequestDeletion, let provider else { return }
        cancelDeletionConfirmation()
        stopPolling()
        localReadID = UUID()
        isPerformingAction = true
        state = .working
        let result = await provider.beginInstallationDeletion()
        isPerformingAction = false
        state = result
        startPollingIfNeeded()
    }

    /// An explicit status check may recover the exact persisted operation.
    /// It never calls beginInstallationDeletion or creates a new installation.
    func checkStatus() async {
        guard canCheckStatus, let provider else { return }
        stopPolling()
        localReadID = UUID()
        isPerformingAction = true
        let result = await provider.resumeInstallationDeletion()
        isPerformingAction = false
        state = result
        startPollingIfNeeded()
    }

    var statusCopyKey: SETCopyKey {
        if isLoading { return .privacyDeletionLoading }
        switch state {
        case .unavailable: return .privacyDeletionUnavailable
        case .noInstallation: return .privacyDeletionNoInstallation
        case .ready: return .privacyDeletionReady
        case .working: return .privacyDeletionWorking
        case .pending: return .privacyDeletionPending
        case .complete: return .privacyDeletionComplete
        case .uncertain: return .privacyDeletionUncertain
        case .failed(let error):
            switch error {
            case .transport: return .privacyDeletionNetworkError
            case .secretStorage: return .privacyDeletionStorageError
            case .policyMismatch: return .privacyDeletionPolicyError
            case .receiptUnavailable: return .privacyDeletionReceiptError
            case .unavailable: return .privacyDeletionUnavailable
            case .noInstallation: return .privacyDeletionNoInstallation
            case .busy: return .privacyDeletionWorking
            case .invalidState, .invalidRequest, .malformedResponse, .rejected:
                return .privacyDeletionFailed
            }
        }
    }

    var statusSymbol: String {
        if isLoading || isPerformingAction { return "clock" }
        switch state {
        case .complete: return "checkmark.circle"
        case .uncertain, .failed: return "exclamationmark.circle"
        case .working, .pending: return "clock"
        case .ready, .noInstallation, .unavailable: return "info.circle"
        }
    }

    private var isAwaitingReceipt: Bool {
        state == .working || state == .pending
    }

    @discardableResult
    private func stopPolling() -> Task<Void, Never>? {
        let previous = pollingTask
        pollID = UUID()
        pollingTask = nil
        previous?.cancel()
        return previous
    }

    private func startPollingIfNeeded() {
        stopPolling()
        guard isVisible, isAwaitingReceipt, maximumAutomaticChecks > 0, let provider else { return }
        let expectedPollID = pollID
        let delay = pollDelay
        let limit = maximumAutomaticChecks
        pollingTask = Task { [weak self] in
            for _ in 0..<limit {
                do { try await delay() } catch { return }
                guard let self, self.isVisible, self.pollID == expectedPollID,
                      !Task.isCancelled, self.isAwaitingReceipt,
                      !self.isLoading, !self.isPerformingAction else { return }
                self.isPerformingAction = true
                let result = await provider.resumeInstallationDeletion()
                self.isPerformingAction = false
                guard self.isVisible, self.pollID == expectedPollID, !Task.isCancelled else { return }
                self.state = result
                guard self.isAwaitingReceipt else { return }
            }
        }
    }
}
