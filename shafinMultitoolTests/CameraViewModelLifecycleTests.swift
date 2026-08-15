import Foundation
import XCTest
@testable import shafinMultitool

@MainActor
final class CameraViewModelLifecycleTests: XCTestCase {

    func testFailedStartPublishesFailureOnlyAfterRegistrationRollback() async {
        let fixture = makeFixture(startPlans: [
            .init(succeeds: false)
        ])
        let rollbackGate = CameraViewModelTestGate()
        fixture.scheduler.setDrainGateForTesting(rollbackGate.semaphore)
        defer {
            rollbackGate.signal()
            fixture.scheduler.setDrainGateForTesting(nil)
        }

        let start = Task { @MainActor in
            await fixture.viewModel.startAndWait()
        }

        let rollbackStarted = await waitUntil {
            fixture.pipeline.testingReleaseInProgress
        }
        XCTAssertTrue(rollbackStarted)
        XCTAssertEqual(fixture.runner.registrationCountsAtStart, [3])
        XCTAssertFalse(isFailed(fixture.viewModel.lifecycleState))
        XCTAssertNil(fixture.viewModel.lifecycleError)

        rollbackGate.signal()
        await start.value
        fixture.scheduler.setDrainGateForTesting(nil)

        XCTAssertEqual(fixture.viewModel.lifecycleState, .failed(.startFailed))
        XCTAssertEqual(fixture.viewModel.lifecycleError, .startFailed)
        XCTAssertEqual(fixture.scheduler.registrationCountForTesting, 0)

        await fixture.viewModel.releaseAndWait()
    }

    func testRetryStartedDuringFailedStartRollbackWaitsForFreshRegistrationSet() async {
        let fixture = makeFixture(startPlans: [
            .init(succeeds: false),
            .init(succeeds: true)
        ])
        let rollbackGate = CameraViewModelTestGate()
        fixture.scheduler.setDrainGateForTesting(rollbackGate.semaphore)
        defer {
            rollbackGate.signal()
            fixture.scheduler.setDrainGateForTesting(nil)
        }

        let failedStart = Task { @MainActor in
            await fixture.viewModel.startAndWait()
        }
        let rollbackStarted = await waitUntil {
            fixture.pipeline.testingReleaseInProgress
        }
        XCTAssertTrue(rollbackStarted)
        XCTAssertEqual(fixture.runner.registrationCountsAtStart, [3])

        // start() captures the in-flight rollback synchronously and must not reach
        // CameraManager while the pipeline release boundary is held.
        fixture.viewModel.start()
        let secondStartBeforeRollback = await waitUntil(timeout: .milliseconds(100)) {
            fixture.runner.startCount == 2
        }
        XCTAssertFalse(secondStartBeforeRollback)

        rollbackGate.signal()
        await failedStart.value

        let retryRunning = await waitUntil {
            fixture.runner.startCount == 2
                && fixture.scheduler.registrationCountForTesting == 3
                && fixture.viewModel.lifecycleState == .running
        }
        fixture.scheduler.setDrainGateForTesting(nil)

        XCTAssertTrue(retryRunning)
        XCTAssertEqual(fixture.scheduler.registrationCountForTesting, 3)
        XCTAssertEqual(fixture.viewModel.lifecycleState, .running)
        XCTAssertNil(fixture.viewModel.lifecycleError)
        XCTAssertEqual(fixture.runner.registrationCountsAtStart, [3, 3])
        XCTAssertFalse(fixture.runner.didTimeoutWaitingForStartGate)

        await fixture.viewModel.releaseAndWait()
    }

    func testSupersededStaleFailureCannotReleaseNewRunningRegistrationSet() async {
        let firstStartGate = CameraViewModelTestGate()
        defer { firstStartGate.signal() }
        let fixture = makeFixture(startPlans: [
            .init(succeeds: false, gate: firstStartGate),
            .init(succeeds: true)
        ])

        fixture.viewModel.start()
        let firstStartEntered = await waitUntil {
            fixture.runner.startCount == 1
        }
        XCTAssertTrue(firstStartEntered)

        // This supersedes the blocked start before its failure is observed by the
        // view model. The replacement reuses the current registration set.
        fixture.viewModel.start()
        firstStartGate.signal()

        let replacementRunning = await waitUntil {
            fixture.runner.startCount == 2
                && fixture.scheduler.registrationCountForTesting == 3
                && fixture.viewModel.lifecycleState == .running
        }

        XCTAssertTrue(replacementRunning)
        XCTAssertEqual(fixture.scheduler.registrationCountForTesting, 3)
        XCTAssertEqual(fixture.viewModel.lifecycleState, .running)
        XCTAssertNil(fixture.viewModel.lifecycleError)
        XCTAssertEqual(fixture.runner.registrationCountsAtStart, [3, 3])
        XCTAssertFalse(fixture.runner.didTimeoutWaitingForStartGate)

        await fixture.viewModel.releaseAndWait()
    }

    func testReleaseAndWaitSharesFailedStartRollbackBoundary() async {
        let fixture = makeFixture(startPlans: [
            .init(succeeds: false)
        ])
        let rollbackGate = CameraViewModelTestGate()
        fixture.scheduler.setDrainGateForTesting(rollbackGate.semaphore)
        defer {
            rollbackGate.signal()
            fixture.scheduler.setDrainGateForTesting(nil)
        }

        let failedStart = Task { @MainActor in
            await fixture.viewModel.startAndWait()
        }
        let rollbackStarted = await waitUntil {
            fixture.pipeline.testingReleaseInProgress
        }
        XCTAssertTrue(rollbackStarted)

        let releaseCompletion = CompletionProbe()
        let release = Task { @MainActor in
            await fixture.viewModel.releaseAndWait()
            releaseCompletion.markCompleted()
        }

        let releaseStarted = await waitUntil {
            fixture.viewModel.lifecycleState == .stopping
        }
        XCTAssertTrue(releaseStarted)

        let releaseFinishedBeforeRollback = await waitUntil(timeout: .milliseconds(100)) {
            releaseCompletion.isCompleted
        }
        XCTAssertFalse(releaseFinishedBeforeRollback)
        XCTAssertEqual(fixture.runner.stopCount, 0)

        rollbackGate.signal()
        await failedStart.value
        await release.value
        fixture.scheduler.setDrainGateForTesting(nil)

        XCTAssertTrue(releaseCompletion.isCompleted)
        XCTAssertEqual(fixture.viewModel.lifecycleState, .idle)
        XCTAssertNil(fixture.viewModel.lifecycleError)
        XCTAssertEqual(fixture.scheduler.registrationCountForTesting, 0)
        XCTAssertEqual(fixture.manager.configurationState, .unconfigured)
        XCTAssertEqual(fixture.runner.registrationCountsAtStart, [3])
    }

    func testSuccessfulStartRemainsRunningWithExactlyThreeRegistrations() async {
        let fixture = makeFixture(startPlans: [
            .init(succeeds: true)
        ])

        await fixture.viewModel.startAndWait()

        XCTAssertEqual(fixture.viewModel.lifecycleState, .running)
        XCTAssertNil(fixture.viewModel.lifecycleError)
        XCTAssertEqual(fixture.scheduler.registrationCountForTesting, 3)

        await fixture.viewModel.releaseAndWait()
    }

    private func makeFixture(startPlans: [CameraViewModelStartPlan]) -> CameraViewModelFixture {
        let scheduler = RealtimeScheduler()
        let thermalGovernor = ThermalGovernor(thermalStateProvider: { .nominal },
                                               batteryLevelProvider: { 1.0 })
        let runner = CameraViewModelTestSessionRunner(
            startPlans: startPlans,
            registrationCountProvider: { scheduler.registrationCountForTesting }
        )
        let manager = CameraManager(scheduler: scheduler,
                                    thermalGovernor: thermalGovernor,
                                    motionGate: MotionGate(startMotionUpdates: false),
                                    sessionRunner: runner,
                                    configuration: .ready)
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: nil,
            neuralEvidenceService: nil,
            thermalGovernor: thermalGovernor,
            neuralHeavyModelsEnabledProvider: { true },
            liveHybridFusionEnabled: false,
            demoLiveCoachEnabled: false
        )
        let viewModel = CameraViewModel(cameraManager: manager, analysisPipeline: pipeline)
        return CameraViewModelFixture(scheduler: scheduler,
                                      runner: runner,
                                      manager: manager,
                                      pipeline: pipeline,
                                      viewModel: viewModel)
    }

    private func waitUntil(timeout: Duration = .seconds(2),
                           _ condition: @escaping () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if condition() {
                return true
            }
            do {
                try await Task.sleep(nanoseconds: 1_000_000)
            } catch {
                return false
            }
        }
        return condition()
    }

    private func isFailed(_ state: CameraLifecycleState) -> Bool {
        if case .failed = state {
            return true
        }
        return false
    }
}

private struct CameraViewModelStartPlan {
    let succeeds: Bool
    let gate: CameraViewModelTestGate?

    init(succeeds: Bool, gate: CameraViewModelTestGate? = nil) {
        self.succeeds = succeeds
        self.gate = gate
    }
}

private struct CameraViewModelFixture {
    let scheduler: RealtimeScheduler
    let runner: CameraViewModelTestSessionRunner
    let manager: CameraManager
    let pipeline: AnalysisPipeline
    let viewModel: CameraViewModel
}

private final class CompletionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    var isCompleted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }

    func markCompleted() {
        lock.lock()
        completed = true
        lock.unlock()
    }
}

private final class CameraViewModelTestSessionRunner: CameraSessionRunner {
    private let lock = NSLock()
    private var startPlans: [CameraViewModelStartPlan]
    private var starts = 0
    private var stops = 0
    private var running = false
    private var registrationCountsAtStartStorage: [Int] = []
    private var didTimeoutWaitingForStartGateStorage = false
    private let registrationCountProvider: () -> Int

    init(startPlans: [CameraViewModelStartPlan],
         registrationCountProvider: @escaping () -> Int) {
        self.startPlans = startPlans
        self.registrationCountProvider = registrationCountProvider
    }

    var startCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return starts
    }

    var stopCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return stops
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    var registrationCountsAtStart: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return registrationCountsAtStartStorage
    }

    var didTimeoutWaitingForStartGate: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didTimeoutWaitingForStartGateStorage
    }

    func startRunning() {
        lock.lock()
        let plan = startPlans.isEmpty
            ? CameraViewModelStartPlan(succeeds: true)
            : startPlans.removeFirst()
        let registrationCountProvider = self.registrationCountProvider
        lock.unlock()

        let registrationCount = registrationCountProvider()

        lock.lock()
        starts += 1
        registrationCountsAtStartStorage.append(registrationCount)
        lock.unlock()

        let didOpenGate = plan.gate?.wait() ?? true

        lock.lock()
        if !didOpenGate {
            didTimeoutWaitingForStartGateStorage = true
        }
        running = plan.succeeds
        lock.unlock()
    }

    func stopRunning() {
        lock.lock()
        stops += 1
        running = false
        lock.unlock()
    }
}

private final class CameraViewModelTestGate: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var didSignal = false

    func signal() {
        lock.lock()
        guard !didSignal else {
            lock.unlock()
            return
        }
        didSignal = true
        lock.unlock()
        semaphore.signal()
    }

    @discardableResult
    func wait() -> Bool {
        semaphore.wait(timeout: .now() + .seconds(2)) == .success
    }

    deinit {
        signal()
    }
}
