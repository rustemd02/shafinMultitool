import Foundation
import XCTest
@testable import shafinMultitool

@MainActor
final class SETInstallationDeletionPresentationTests: XCTestCase {
    func testConstructionAndOpeningDoNotEnrollOrSendRequests() async {
        let provider = DeletionPresentationProvider(state: .ready)
        let presentation = SETInstallationDeletionPresentation(provider: provider)
        var calls = await provider.calls()
        XCTAssertEqual(calls, .init(reads: 0, begins: 0, resumes: 0))
        XCTAssertTrue(presentation.isLoading)

        await presentation.appear()
        calls = await provider.calls()
        XCTAssertEqual(calls, .init(reads: 1, begins: 0, resumes: 0))
        XCTAssertEqual(presentation.state, .ready)
        XCTAssertTrue(presentation.canRequestDeletion)
        XCTAssertFalse(presentation.isConfirmationPresented)
        XCTAssertFalse(presentation.canCheckStatus)
        presentation.disappear()
    }

    func testOpeningPendingOrFailedOperationNeverPolls() async {
        let initialStates: [SceneInstallationDeletionState] = [
            .working, .pending, .uncertain, .failed(.transport), .failed(.receiptUnavailable)
        ]
        for state in initialStates {
            let provider = DeletionPresentationProvider(state: state)
            let delay = DeletionPresentationDelay()
            let presentation = SETInstallationDeletionPresentation(
                provider: provider, pollDelay: { await delay.wait() }
            )
            await presentation.appear()
            let calls = await provider.calls()
            let delayCalls = await delay.calls
            XCTAssertEqual(calls, .init(reads: 1, begins: 0, resumes: 0))
            XCTAssertEqual(delayCalls, 0)
            XCTAssertFalse(presentation.canRequestDeletion)
            XCTAssertTrue(presentation.canCheckStatus)
            XCTAssertNotEqual(presentation.statusCopyKey, .privacyDeletionComplete)
            presentation.disappear()
        }
    }

    func testDestructiveRequestNeedsConfirmationAndCancelClearsIt() async {
        let provider = DeletionPresentationProvider(state: .ready)
        let presentation = SETInstallationDeletionPresentation(provider: provider, maximumAutomaticChecks: 0)
        await presentation.appear()

        await presentation.confirmDeletion()
        presentation.requestDeletionConfirmation()
        XCTAssertTrue(presentation.isConfirmationPresented)
        presentation.cancelDeletionConfirmation()
        await presentation.confirmDeletion()

        let calls = await provider.calls()
        XCTAssertEqual(calls, .init(reads: 1, begins: 0, resumes: 0))
        XCTAssertEqual(presentation.state, .ready)
        XCTAssertFalse(presentation.isConfirmationPresented)
        presentation.disappear()
    }

    func testAlertBindingDismissalDoesNotDiscardAnExplicitConfirmation() async {
        let provider = DeletionPresentationProvider(state: .ready, beginResult: .complete)
        let presentation = SETInstallationDeletionPresentation(provider: provider, maximumAutomaticChecks: 0)
        await presentation.appear()
        presentation.requestDeletionConfirmation()
        // SwiftUI dismisses the native alert before the async action may run.
        presentation.isConfirmationPresented = false
        await presentation.confirmDeletion()

        let calls = await provider.calls()
        XCTAssertEqual(calls.begins, 1)
        XCTAssertEqual(presentation.state, .complete)
        XCTAssertEqual(presentation.statusCopyKey, .privacyDeletionComplete)
        presentation.disappear()
    }

    func testDoubleConfirmationAndStatusTapDoNotDuplicateAnInFlightRequest() async {
        let provider = DeletionPresentationProvider(state: .ready, holdBegin: true)
        let presentation = SETInstallationDeletionPresentation(provider: provider, maximumAutomaticChecks: 0)
        await presentation.appear()
        presentation.requestDeletionConfirmation()
        let first = Task { await presentation.confirmDeletion() }
        await provider.waitForBegin()
        XCTAssertTrue(presentation.isPerformingAction)
        XCTAssertFalse(presentation.canRequestDeletion)
        XCTAssertFalse(presentation.canCheckStatus)
        await presentation.confirmDeletion()
        await presentation.checkStatus()
        var calls = await provider.calls()
        XCTAssertEqual(calls.begins, 1)
        XCTAssertEqual(calls.resumes, 0)

        await provider.finishBegin(.pending)
        await first.value
        calls = await provider.calls()
        XCTAssertEqual(calls.begins, 1)
        XCTAssertEqual(presentation.state, .pending)
        XCTAssertTrue(presentation.canCheckStatus)
        presentation.disappear()
    }

    func testExplicitResumeUsesExistingOperationWithoutBeginningAnother() async {
        let provider = DeletionPresentationProvider(state: .uncertain, resumeResult: .complete)
        let presentation = SETInstallationDeletionPresentation(provider: provider, maximumAutomaticChecks: 0)
        await presentation.appear()
        await presentation.checkStatus()
        let calls = await provider.calls()
        XCTAssertEqual(calls, .init(reads: 1, begins: 0, resumes: 1))
        XCTAssertEqual(presentation.state, .complete)
        XCTAssertFalse(presentation.canCheckStatus)
        XCTAssertFalse(presentation.canRequestDeletion)
        presentation.disappear()
    }

    func testClosingStopsFuturePollingAndReopeningOnlyReadsPersistedState() async {
        let provider = DeletionPresentationProvider(state: .ready, beginResult: .pending)
        let delay = DeletionPresentationDelay()
        let presentation = SETInstallationDeletionPresentation(
            provider: provider, pollDelay: { await delay.wait() }
        )
        await presentation.appear()
        presentation.requestDeletionConfirmation()
        await presentation.confirmDeletion()
        await delay.waitUntilCalled(1)

        let stoppedTask = presentation.disappear()
        await delay.release()
        await stoppedTask?.value
        var calls = await provider.calls()
        XCTAssertEqual(calls.begins, 1)
        XCTAssertEqual(calls.resumes, 0)
        XCTAssertEqual(presentation.state, .pending)
        XCTAssertFalse(presentation.canCheckStatus)

        await presentation.appear()
        calls = await provider.calls()
        XCTAssertEqual(calls, .init(reads: 2, begins: 1, resumes: 0))
        XCTAssertEqual(presentation.state, .pending)
        XCTAssertTrue(presentation.canCheckStatus)
        presentation.disappear()
    }

    func testClosingDuringReceiptCheckIgnoresLateReplyAndReopensFromLocalState() async {
        let provider = DeletionPresentationProvider(
            state: .ready, beginResult: .pending, holdResume: true
        )
        let delay = DeletionPresentationDelay()
        let presentation = SETInstallationDeletionPresentation(
            provider: provider, pollDelay: { await delay.wait() }
        )
        await presentation.appear()
        presentation.requestDeletionConfirmation()
        await presentation.confirmDeletion()
        await delay.waitUntilCalled(1)
        await delay.release()
        await provider.waitForResumeCount(1)
        let observer = presentation.disappear()
        await provider.finishResume(.complete)
        await observer?.value

        XCTAssertEqual(presentation.state, .pending, "A hidden observer must not publish a late reply.")
        await presentation.appear()
        let calls = await provider.calls()
        XCTAssertEqual(calls, .init(reads: 2, begins: 1, resumes: 1))
        XCTAssertEqual(presentation.state, .complete, "Reopening reads the durable owner's latest state.")
        presentation.disappear()
    }

    func testClosingDuringBeginDoesNotClaimCancellationOrClearOperation() async {
        let provider = DeletionPresentationProvider(state: .ready, holdBegin: true)
        let presentation = SETInstallationDeletionPresentation(provider: provider)
        await presentation.appear()
        presentation.requestDeletionConfirmation()
        let action = Task { await presentation.confirmDeletion() }
        await provider.waitForBegin()
        presentation.disappear()
        await provider.finishBegin(.pending)
        await action.value

        let calls = await provider.calls()
        XCTAssertEqual(calls, .init(reads: 1, begins: 1, resumes: 0))
        XCTAssertEqual(presentation.state, .pending)
        XCTAssertNotEqual(presentation.statusCopyKey, .privacyDeletionComplete)
        XCTAssertFalse(presentation.canCheckStatus)
    }

    func testAutomaticChecksAreBoundedAfterExplicitAction() async {
        let provider = DeletionPresentationProvider(
            state: .ready, beginResult: .pending, resumeResult: .pending
        )
        let delay = DeletionPresentationDelay()
        let presentation = SETInstallationDeletionPresentation(
            provider: provider, maximumAutomaticChecks: 2, pollDelay: { await delay.wait() }
        )
        await presentation.appear()
        presentation.requestDeletionConfirmation()
        await presentation.confirmDeletion()
        await delay.waitUntilCalled(1)
        await delay.release()
        await delay.waitUntilCalled(2)
        await delay.release()
        await provider.waitForResumeCount(2)
        // Joining the observer also verifies no background loop survives closure.
        let observer = presentation.disappear()
        await observer?.value

        let calls = await provider.calls()
        let delayCalls = await delay.calls
        XCTAssertEqual(calls, .init(reads: 1, begins: 1, resumes: 2))
        XCTAssertEqual(delayCalls, 2)
        XCTAssertNotEqual(presentation.statusCopyKey, .privacyDeletionComplete)
    }

    func testUnavailableAndMissingInstallationNeverOfferDeletion() async {
        let unavailable = SETInstallationDeletionPresentation(provider: nil)
        await unavailable.appear()
        XCTAssertEqual(unavailable.state, .unavailable)
        XCTAssertFalse(unavailable.canRequestDeletion)
        XCTAssertFalse(unavailable.canCheckStatus)
        unavailable.requestDeletionConfirmation()
        XCTAssertFalse(unavailable.isConfirmationPresented)
        unavailable.disappear()

        let provider = DeletionPresentationProvider(state: .noInstallation)
        let absent = SETInstallationDeletionPresentation(provider: provider)
        await absent.appear()
        XCTAssertEqual(absent.statusCopyKey, .privacyDeletionNoInstallation)
        XCTAssertFalse(absent.canRequestDeletion)
        XCTAssertFalse(absent.canCheckStatus)
        XCTAssertNotEqual(absent.statusCopyKey, .privacyDeletionComplete)
        absent.disappear()
    }

    func testMissingReceiptAndTransportErrorRemainUnconfirmed() async {
        let failures: [(InstallationDeletionError, SETCopyKey)] = [
            (.receiptUnavailable, .privacyDeletionReceiptError),
            (.transport, .privacyDeletionNetworkError),
            (.policyMismatch, .privacyDeletionPolicyError),
            (.secretStorage, .privacyDeletionStorageError),
            (.invalidState, .privacyDeletionFailed),
            (.invalidRequest, .privacyDeletionFailed),
            (.malformedResponse, .privacyDeletionFailed),
            (.rejected, .privacyDeletionFailed)
        ]
        for (error, expectedCopy) in failures {
            let provider = DeletionPresentationProvider(state: .failed(error))
            let presentation = SETInstallationDeletionPresentation(provider: provider)
            await presentation.appear()
            XCTAssertEqual(presentation.statusCopyKey, expectedCopy)
            XCTAssertNotEqual(presentation.state, .complete)
            XCTAssertFalse(presentation.canRequestDeletion)
            XCTAssertTrue(presentation.canCheckStatus)
            presentation.disappear()
        }
    }

    func testDeletionCopyHasEnglishAndRussianTranslations() {
        let keys: [SETCopyKey] = [
            .privacyDeletionTitle,
            .privacyDeletionScope,
            .privacyDeletionRetained,
            .privacyDeletionConfirmTitle,
            .privacyDeletionConfirmBody,
            .privacyDeletionAction,
            .privacyDeletionCancel,
            .privacyDeletionCheck,
            .privacyDeletionLoading,
            .privacyDeletionUnavailable,
            .privacyDeletionNoInstallation,
            .privacyDeletionReady,
            .privacyDeletionWorking,
            .privacyDeletionPending,
            .privacyDeletionComplete,
            .privacyDeletionUncertain,
            .privacyDeletionNetworkError,
            .privacyDeletionStorageError,
            .privacyDeletionPolicyError,
            .privacyDeletionReceiptError,
            .privacyDeletionFailed
        ]
        for key in keys {
            for language in ["en", "ru"] {
                let text = key.localizedString(locale: Locale(identifier: language))
                XCTAssertFalse(text.isEmpty, key.rawValue)
                XCTAssertNotEqual(text, key.rawValue, "Missing \(language): \(key.rawValue)")
            }
        }
    }
}

private actor DeletionPresentationProvider: SceneInstallationDeletionProviding {
    struct Calls: Equatable {
        let reads: Int
        let begins: Int
        let resumes: Int
    }

    private var state: SceneInstallationDeletionState
    private let beginResult: SceneInstallationDeletionState
    private let resumeResult: SceneInstallationDeletionState
    private let holdBegin: Bool
    private let holdResume: Bool
    private var reads = 0
    private var begins = 0
    private var resumes = 0
    private var beginContinuation: CheckedContinuation<SceneInstallationDeletionState, Never>?
    private var resumeContinuation: CheckedContinuation<SceneInstallationDeletionState, Never>?
    private var beginWaiters: [CheckedContinuation<Void, Never>] = []
    private var resumeWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(
        state: SceneInstallationDeletionState,
        beginResult: SceneInstallationDeletionState = .pending,
        resumeResult: SceneInstallationDeletionState = .pending,
        holdBegin: Bool = false,
        holdResume: Bool = false
    ) {
        self.state = state
        self.beginResult = beginResult
        self.resumeResult = resumeResult
        self.holdBegin = holdBegin
        self.holdResume = holdResume
    }

    func installationDeletionState() async -> SceneInstallationDeletionState {
        reads += 1
        return state
    }

    func beginInstallationDeletion() async -> SceneInstallationDeletionState {
        begins += 1
        for waiter in beginWaiters { waiter.resume() }
        beginWaiters.removeAll()
        let result: SceneInstallationDeletionState
        if holdBegin {
            result = await withCheckedContinuation { beginContinuation = $0 }
        } else {
            result = beginResult
        }
        state = result
        return result
    }

    func resumeInstallationDeletion() async -> SceneInstallationDeletionState {
        resumes += 1
        let satisfied = resumeWaiters.filter { resumes >= $0.0 }
        resumeWaiters.removeAll { resumes >= $0.0 }
        for (_, waiter) in satisfied { waiter.resume() }
        if holdResume {
            state = await withCheckedContinuation { resumeContinuation = $0 }
        } else {
            state = resumeResult
        }
        return state
    }

    func calls() -> Calls { .init(reads: reads, begins: begins, resumes: resumes) }

    func waitForBegin() async {
        if begins > 0 { return }
        await withCheckedContinuation { beginWaiters.append($0) }
    }

    func finishBegin(_ result: SceneInstallationDeletionState) {
        beginContinuation?.resume(returning: result)
        beginContinuation = nil
    }

    func finishResume(_ result: SceneInstallationDeletionState) {
        resumeContinuation?.resume(returning: result)
        resumeContinuation = nil
    }

    func waitForResumeCount(_ count: Int) async {
        if resumes >= count { return }
        await withCheckedContinuation { resumeWaiters.append((count, $0)) }
    }
}

/// This delay deliberately ignores cancellation until released, so the tests
/// prove the presentation checks cancellation before its next server request.
private actor DeletionPresentationDelay {
    private(set) var calls = 0
    private var pending: CheckedContinuation<Void, Never>?
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func wait() async {
        calls += 1
        let satisfied = waiters.filter { calls >= $0.0 }
        waiters.removeAll { calls >= $0.0 }
        for (_, waiter) in satisfied { waiter.resume() }
        await withCheckedContinuation { pending = $0 }
    }

    func waitUntilCalled(_ count: Int) async {
        if calls >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func release() {
        pending?.resume()
        pending = nil
    }
}
