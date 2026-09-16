import AVFoundation
import Combine
import CoreGraphics
import Foundation
import XCTest
@testable import shafinMultitool

final class CameraProControlRuntimeTests: XCTestCase {
    func testExposureDurationRespectsAngleHardwareMinimumAndFramePeriod() throws {
        XCTAssertEqual(
            try CameraProControlPolicy.exposureDuration(angle: 180, fps: 24, supported: 0.0001...1),
            1 / 48.0, accuracy: 0.0000001
        )
        XCTAssertEqual(
            try CameraProControlPolicy.exposureDuration(angle: 360, fps: 60, supported: 0.0001...1),
            1 / 60.0, accuracy: 0.0000001
        )
        XCTAssertEqual(
            try CameraProControlPolicy.exposureDuration(angle: 0.01, fps: 60, supported: 0.001...1),
            0.001, accuracy: 0.0000001
        )
        XCTAssertThrowsError(
            try CameraProControlPolicy.exposureDuration(angle: 180, fps: 60, supported: 0.03...1)
        ) { XCTAssertEqual($0 as? CameraProControlError, .unsupported) }
    }

    func testInvalidExposureAndNonfiniteControlValuesAreRejectedBeforeNativeSetters() {
        for angle in [Double.nan, .infinity, -.infinity, -1, 0, 360.01] {
            XCTAssertThrowsError(
                try CameraProControlPolicy.exposureDuration(angle: angle, fps: 30, supported: 0.0001...1)
            ) { XCTAssertEqual($0 as? CameraProControlError, .invalidValue) }
        }
        for fps in [Double.nan, .infinity, -30, 0] {
            XCTAssertThrowsError(
                try CameraProControlPolicy.exposureDuration(angle: 180, fps: fps, supported: 0.0001...1)
            ) { XCTAssertEqual($0 as? CameraProControlError, .invalidValue) }
        }
        for value: Float in [.nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try CameraProControlPolicy.clamp(value, to: -2...2)) {
                XCTAssertEqual($0 as? CameraProControlError, .invalidValue)
            }
        }
    }

    func testExposureBiasClampsToReportedDeviceRange() throws {
        XCTAssertEqual(try CameraProControlPolicy.clamp(-3, to: -2...1.5), -2)
        XCTAssertEqual(try CameraProControlPolicy.clamp(3, to: -2...1.5), 1.5)
        XCTAssertEqual(try CameraProControlPolicy.clamp(0.75, to: -2...1.5), 0.75)
        XCTAssertThrowsError(try CameraProControlPolicy.clamp(1, to: 0...Float.infinity)) {
            XCTAssertEqual($0 as? CameraProControlError, .invalidValue)
        }
    }

    func testWhiteBalanceGainsPreserveRatiosUntilHardwareLimit() throws {
        XCTAssertEqual(try CameraProControlPolicy.normalizedGains([4, 8, 12], maximum: 8), [1, 2, 3])
        XCTAssertEqual(try CameraProControlPolicy.normalizedGains([0.5, 1, 4], maximum: 4), [1, 2, 4])
        for gains: [Float] in [[], [1, 2], [0, 1, 2], [-1, 1, 2], [.nan, 1, 2], [1, .infinity, 2]] {
            XCTAssertThrowsError(try CameraProControlPolicy.normalizedGains(gains, maximum: 4)) {
                XCTAssertEqual($0 as? CameraProControlError, .invalidValue)
            }
        }
        for maximum: Float in [0.5, .nan, .infinity] {
            XCTAssertThrowsError(try CameraProControlPolicy.normalizedGains([1, 2, 3], maximum: maximum)) {
                XCTAssertEqual($0 as? CameraProControlError, .invalidValue)
            }
        }
    }

    func testFocusPointUsesBoundedDeviceCoordinatesAndAngleNeedsMeasuredFPS() {
        XCTAssertTrue(CameraProControlPolicy.validDevicePoint(CGPoint(x: 0, y: 1)))
        XCTAssertTrue(CameraProControlPolicy.validDevicePoint(CGPoint(x: 0.5, y: 0.5)))
        for point in [
            CGPoint(x: -0.01, y: 0.5), CGPoint(x: 0.5, y: 1.01),
            CGPoint(x: CGFloat.nan, y: 0.5), CGPoint(x: 0.5, y: CGFloat.infinity)
        ] {
            XCTAssertFalse(CameraProControlPolicy.validDevicePoint(point))
        }
        var readback = ProControlGateDevice.initialReadback
        XCTAssertEqual(readback.shutterAngle, 180)
        readback.fixedFPS = nil
        XCTAssertNil(readback.shutterAngle, "Variable or unknown FPS cannot establish a shutter angle")
        readback.fixedFPS = 30
        readback.exposureDuration = .infinity
        XCTAssertNil(readback.shutterAngle)
    }

    func testPendingNativeValueIsNotPublishedUntilAcknowledgedReadback() async throws {
        try await withRunningManager { manager, device, _ in
            let initial = try await self.snapshot(manager)
            let observations = ProControlLocked<[CameraProControlsSnapshot?]>([])
            let subscription = manager.proControlsPublisher.sink { value in
                observations.withValue { $0.append(value) }
            }
            defer { subscription.cancel() }

            let operation = await self.begin(.focusManual(0.75), on: manager, device: device, from: initial)
            var speculative = initial.readback
            speculative.focusIsAuto = false
            speculative.focusIsLocked = true
            speculative.lensPosition = 0.75
            device.setReadback(speculative)

            let pending = await manager.proControlsSnapshotAndWait()
            XCTAssertEqual(pending, initial)
            XCTAssertFalse(manager.frameDeliveryEnabledForTesting)
            XCTAssertEqual(observations.withValue { $0.compactMap { $0 }.map(\.readback) }, [initial.readback])

            // The device acknowledges a different settled position. The result
            // must report this observation, not echo the requested slider value.
            var settled = speculative
            settled.lensPosition = 0.70
            XCTAssertTrue(device.complete(0, with: .success(()), readback: settled))
            let result = await operation.value
            guard case .success(let acknowledged) = result else {
                return XCTFail("Expected acknowledged hardware readback, received \(result)")
            }
            XCTAssertEqual(acknowledged.readback, settled)
            XCTAssertGreaterThan(acknowledged.captureGeneration, initial.captureGeneration)
            XCTAssertTrue(manager.frameDeliveryEnabledForTesting)
            XCTAssertEqual(observations.withValue { $0.compactMap { $0 }.last }, acknowledged)
        }
    }

    func testOverlappingActionIsBusyWithoutSecondNativeApply() async throws {
        try await withRunningManager { manager, device, _ in
            let initial = try await self.snapshot(manager)
            let first = await self.begin(.focusManual(0.75), on: manager, device: device, from: initial)
            let second = await manager.applyProControl(
                .whiteBalanceTemperature(4500),
                expectedDeviceID: initial.deviceID,
                expectedCaptureGeneration: initial.captureGeneration
            )
            self.assertFailure(second, .busy)
            XCTAssertEqual(device.commands, [.focusManual(0.75)])
            XCTAssertFalse(manager.frameDeliveryEnabledForTesting)
            XCTAssertTrue(device.complete(0, with: .success(())))
            guard case .success = await first.value else { return XCTFail("First action must retain ownership") }
            XCTAssertTrue(manager.frameDeliveryEnabledForTesting)
        }
    }

    func testNativeRejectionRestoresActualUnchangedReadbackAndDelivery() async throws {
        try await withRunningManager { manager, device, _ in
            let initial = try await self.snapshot(manager)
            let operation = await self.begin(.focusManual(0.8), on: manager, device: device, from: initial)
            XCTAssertTrue(device.complete(0, with: .failure(.configurationFailed)))
            self.assertFailure(await operation.value, .configurationFailed)
            let after = try await self.snapshot(manager)
            XCTAssertEqual(after.readback, initial.readback)
            XCTAssertGreaterThan(after.captureGeneration, initial.captureGeneration)
            XCTAssertEqual(after.deviceID, initial.deviceID)
            XCTAssertTrue(manager.frameDeliveryEnabledForTesting)
            XCTAssertEqual(manager.lifecycleState, .running)
        }
    }

    func testStaleDeviceAndGenerationAreRefusedWithoutTouchingCapture() async throws {
        try await withRunningManager { manager, device, _ in
            let current = try await self.snapshot(manager)
            let wrongDevice = await manager.applyProControl(
                .focusManual(0.8),
                expectedDeviceID: "a-replaced-camera",
                expectedCaptureGeneration: current.captureGeneration
            )
            let wrongGeneration = await manager.applyProControl(
                .focusManual(0.8),
                expectedDeviceID: current.deviceID,
                expectedCaptureGeneration: current.captureGeneration + 1
            )
            self.assertFailure(wrongDevice, .stale)
            self.assertFailure(wrongGeneration, .stale)
            XCTAssertTrue(device.commands.isEmpty)
            XCTAssertEqual(manager.captureGenerationForTesting, current.captureGeneration)
            XCTAssertTrue(manager.frameDeliveryEnabledForTesting)
            let after = try await self.snapshot(manager)
            XCTAssertEqual(after, current)
        }
    }

    func testRepeatedStartCannotReopenDeliveryWhileHardwareChangeIsPending() async throws {
        try await withRunningManager { manager, device, runner in
            let initial = try await self.snapshot(manager)
            let operation = await self.begin(.focusManual(0.75), on: manager, device: device, from: initial)
            try await manager.startAndWait()
            XCTAssertEqual(runner.startCount, 1)
            XCTAssertFalse(manager.frameDeliveryEnabledForTesting,
                           "Idempotent start must preserve the pending hardware acknowledgement boundary")
            let pending = await manager.proControlsSnapshotAndWait()
            XCTAssertEqual(pending, initial)
            XCTAssertTrue(device.complete(0, with: .success(())))
            guard case .success = await operation.value else { return XCTFail("The original operation must finish") }
            XCTAssertTrue(manager.frameDeliveryEnabledForTesting)
        }
    }

    func testStopAndReleaseFencePendingActionsAndIgnoreLateCallbacks() async throws {
        for shouldRelease in [false, true] {
            try await withRunningManager { manager, device, runner in
                let initial = try await self.snapshot(manager)
                let operation = await self.begin(.focusManual(0.75), on: manager, device: device, from: initial)
                if shouldRelease { await manager.releaseAndWait() }
                else { await manager.stopAndWait() }
                self.assertFailure(await operation.value, .stale)
                XCTAssertFalse(manager.frameDeliveryEnabledForTesting)
                XCTAssertFalse(runner.isRunning)
                XCTAssertEqual(manager.lifecycleState, .idle)
                XCTAssertGreaterThan(device.cancelCount, 0)
                let stoppedGeneration = manager.captureGenerationForTesting

                // Native completion is deliberately retained by the fake even
                // after cancelPending, just like an already-dispatched callback.
                XCTAssertTrue(device.complete(0, with: .success(())))
                let stopped = await manager.proControlsSnapshotAndWait()
                XCTAssertNil(stopped)
                XCTAssertEqual(manager.captureGenerationForTesting, stoppedGeneration)
                XCTAssertFalse(manager.frameDeliveryEnabledForTesting)
                XCTAssertFalse(runner.isRunning)
                XCTAssertEqual(runner.startCount, 1)

                let rejected = await manager.applyProControl(
                    .focusAuto,
                    expectedDeviceID: initial.deviceID,
                    expectedCaptureGeneration: initial.captureGeneration
                )
                self.assertFailure(rejected, .unavailable)
                XCTAssertEqual(device.commands.count, 1)
            }
        }
    }

    func testLateOldCallbackCannotCompleteNewActionAfterRestart() async throws {
        try await withRunningManager { manager, device, _ in
            let firstSnapshot = try await self.snapshot(manager)
            let old = await self.begin(.focusManual(0.75), on: manager, device: device, from: firstSnapshot)
            await manager.stopAndWait()
            self.assertFailure(await old.value, .stale)
            try await manager.startAndWait()
            let restarted = try await self.snapshot(manager)
            XCTAssertGreaterThan(restarted.captureGeneration, firstSnapshot.captureGeneration)
            let fresh = await self.begin(.focusManual(0.30), on: manager, device: device, from: restarted)

            XCTAssertTrue(device.complete(0, with: .success(())))
            let stillPending = await manager.proControlsSnapshotAndWait()
            XCTAssertEqual(stillPending, restarted)
            XCTAssertFalse(manager.frameDeliveryEnabledForTesting)
            let overlap = await manager.applyProControl(
                .focusAuto,
                expectedDeviceID: restarted.deviceID,
                expectedCaptureGeneration: restarted.captureGeneration
            )
            self.assertFailure(overlap, .busy)

            var settled = restarted.readback
            settled.focusIsAuto = false
            settled.focusIsLocked = true
            settled.lensPosition = 0.30
            XCTAssertTrue(device.complete(1, with: .success(()), readback: settled))
            guard case .success(let accepted) = await fresh.value else {
                return XCTFail("Only the new operation's callback may complete it")
            }
            XCTAssertEqual(accepted.readback, settled)
            XCTAssertTrue(manager.frameDeliveryEnabledForTesting)
        }
    }

    @MainActor
    func testViewModelRepeatedStartPreservesPendingControlUntilAcknowledged() async {
        let device = ProControlGateDevice()
        let runner = ProControlSessionRunner()
        let governor = ThermalGovernor(thermalStateProvider: { .nominal }, batteryLevelProvider: { 1 })
        let manager = CameraManager(
            scheduler: RealtimeScheduler(), thermalGovernor: governor,
            motionGate: MotionGate(startMotionUpdates: false), sessionRunner: runner,
            configuration: .ready, notificationCenter: NotificationCenter(), proControlDevice: device
        )
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil, visualEvidenceProvider: nil, neuralEvidenceService: nil,
            episodeConfidenceCalibrator: CameraEpisodeCalibrationFixture.calibrator,
            thermalGovernor: governor, neuralHeavyModelsEnabledProvider: { false },
            liveHybridFusionEnabled: false, demoLiveCoachEnabled: false
        )
        let viewModel = CameraViewModel(cameraManager: manager, analysisPipeline: pipeline)
        let ready = expectation(description: "Device readback reaches the ViewModel")
        let initialSubscription = viewModel.$proControlsSnapshot.compactMap { $0 }.prefix(1)
            .sink { _ in ready.fulfill() }
        await viewModel.startAndWait()
        await fulfillment(of: [ready], timeout: 2)
        initialSubscription.cancel()

        let applying = expectation(description: "Native focus request is held")
        device.onNextApply { applying.fulfill() }
        viewModel.applyProControl(.focusManual(0.75))
        await fulfillment(of: [applying], timeout: 2)
        XCTAssertTrue(viewModel.isApplyingProControl)
        XCTAssertFalse(manager.frameDeliveryEnabledForTesting)

        // Exercise both public start forms and an additional call while the
        // first duplicate start waiter has only just entered .starting.
        viewModel.start()
        await viewModel.startAndWait()
        XCTAssertEqual(runner.startCount, 1)
        XCTAssertTrue(viewModel.isApplyingProControl,
                      "An idempotent start must not abandon the pending device acknowledgement")
        XCTAssertFalse(viewModel.canApplyProControl)
        XCTAssertFalse(manager.frameDeliveryEnabledForTesting)
        XCTAssertNil(viewModel.proControlError)

        let acknowledged = expectation(description: "Original waiter publishes settled readback")
        let completionSubscription = viewModel.$isApplyingProControl.filter { !$0 }.prefix(1)
            .sink { _ in acknowledged.fulfill() }
        var settled = ProControlGateDevice.initialReadback
        settled.focusIsAuto = false
        settled.focusIsLocked = true
        settled.lensPosition = 0.70
        XCTAssertTrue(device.complete(0, with: .success(()), readback: settled))
        await fulfillment(of: [acknowledged], timeout: 2)
        completionSubscription.cancel()
        XCTAssertEqual(viewModel.proControlsSnapshot?.readback.lensPosition, 0.70)
        XCTAssertFalse(viewModel.isApplyingProControl)
        XCTAssertTrue(viewModel.canApplyProControl)
        XCTAssertNil(viewModel.proControlError)
        XCTAssertTrue(manager.frameDeliveryEnabledForTesting)
        await viewModel.releaseAndWait()
    }

    private func begin(
        _ command: CameraProControlCommand,
        on manager: CameraManager,
        device: ProControlGateDevice,
        from snapshot: CameraProControlsSnapshot
    ) async -> Task<Result<CameraProControlsSnapshot, CameraProControlError>, Never> {
        let entered = expectation(description: "Native Pro control apply entered")
        device.onNextApply { entered.fulfill() }
        let operation = Task {
            await manager.applyProControl(command,
                                          expectedDeviceID: snapshot.deviceID,
                                          expectedCaptureGeneration: snapshot.captureGeneration)
        }
        await fulfillment(of: [entered], timeout: 2)
        return operation
    }

    func testRecordingReservationRejectsFormatAndLensWithoutMutatingNativeDevice() async throws {
        try await withRunningManager { manager, device, _ in
            let before = try await self.snapshot(manager)
            let lease = try await manager.reserveRecordingCapture()
            XCTAssertEqual(lease.ownerID, manager.sourceOwnerID)
            let format = await manager.applyProControl(.format("another-format"),
                expectedDeviceID: before.deviceID, expectedCaptureGeneration: before.captureGeneration)
            self.assertFailure(format, .busy)
            let lens = await manager.switchLensAndWait(to: .telephoto)
            guard case .failure(_, _, let reason) = lens else { return XCTFail("A take must freeze its physical input") }
            XCTAssertEqual(reason, .recordingInProgress)
            XCTAssertTrue(device.commands.isEmpty)
            XCTAssertEqual(manager.captureGenerationForTesting, before.captureGeneration)
            XCTAssertTrue(manager.frameDeliveryEnabledForTesting)
            await manager.releaseRecordingCapture(lease)
        }
    }

    func testReleasedOldRecordingLeaseCannotCloseOrReleaseNewReservation() async throws {
        try await withRunningManager { manager, _, _ in
            let old = try await manager.reserveRecordingCapture()
            await manager.releaseRecordingCapture(old)
            let current = try await manager.reserveRecordingCapture()
            XCTAssertNotEqual(old, current)
            await manager.closeRecordingFrameAdmission(old)
            await manager.releaseRecordingCapture(old)
            do {
                _ = try await manager.reserveRecordingCapture()
                XCTFail("The current take must still own its reservation")
            } catch {
                XCTAssertEqual(error as? CameraRecordingCaptureError, .recordingInProgress)
            }
            await manager.releaseRecordingCapture(current)
            let fresh = try await manager.reserveRecordingCapture()
            XCTAssertNotEqual(fresh, current)
            await manager.releaseRecordingCapture(fresh)
        }
    }

    func testPendingNativeControlRejectsRecordingReservationUntilAcknowledged() async throws {
        try await withRunningManager { manager, device, _ in
            let before = try await self.snapshot(manager)
            let apply = await self.begin(.focusManual(0.7), on: manager, device: device, from: before)
            do {
                _ = try await manager.reserveRecordingCapture()
                XCTFail("An unacknowledged hardware operation cannot define a take format")
            } catch {
                XCTAssertEqual(error as? CameraRecordingCaptureError, .proControlPending)
            }
            XCTAssertTrue(device.complete(0, with: .success(())))
            guard case .success = await apply.value else { return XCTFail("Original control must finish") }
            let lease = try await manager.reserveRecordingCapture()
            await manager.releaseRecordingCapture(lease)
        }
    }

    func testStoppedRecordingLeaseCannotAttachIntoRestartedCaptureGeneration() async throws {
        try await withRunningManager { manager, _, _ in
            let old = try await manager.reserveRecordingCapture()
            await manager.stopAndWait()
            try await manager.startAndWait()
            do {
                _ = try await manager.prepareRecordingCapture(lease: old, audioMode: .disabled)
                XCTFail("The interrupted take must not acquire a restarted capture graph")
            } catch {
                XCTAssertEqual(error as? CameraRecordingCaptureError, .staleLease)
            }
            await manager.releaseRecordingCapture(old)
            let fresh = try await manager.reserveRecordingCapture()
            await manager.releaseRecordingCapture(fresh)
        }
    }

    private func snapshot(_ manager: CameraManager) async throws -> CameraProControlsSnapshot {
        let value = await manager.proControlsSnapshotAndWait()
        return try XCTUnwrap(value)
    }

    private func assertFailure(
        _ result: Result<CameraProControlsSnapshot, CameraProControlError>,
        _ expected: CameraProControlError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(let actual) = result else {
            return XCTFail("Expected \(expected), received \(result)", file: file, line: line)
        }
        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    private func withRunningManager(
        _ body: (CameraManager, ProControlGateDevice, ProControlSessionRunner) async throws -> Void
    ) async throws {
        let device = ProControlGateDevice()
        let runner = ProControlSessionRunner()
        let manager = CameraManager(
            scheduler: RealtimeScheduler(),
            thermalGovernor: ThermalGovernor(thermalStateProvider: { .nominal }, batteryLevelProvider: { 1 }),
            motionGate: MotionGate(startMotionUpdates: false),
            sessionRunner: runner,
            configuration: .ready,
            notificationCenter: NotificationCenter(),
            proControlDevice: device
        )
        do {
            try await manager.startAndWait()
            try await body(manager, device, runner)
            await manager.releaseAndWait()
        } catch {
            await manager.releaseAndWait()
            throw error
        }
    }
}

private final class ProControlLocked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

private final class ProControlGateDevice: CameraProControlDevice, @unchecked Sendable {
    let deviceID = "test-wide-camera"
    private struct State {
        var readback = ProControlGateDevice.initialReadback
        var commands: [CameraProControlCommand] = []
        var callbacks: [(Result<Void, CameraProControlError>) -> Void] = []
        var nextApply: (() -> Void)?
        var cancelCount = 0
    }
    private let state = ProControlLocked(State())

    static var initialReadback: CameraProControlReadback {
        var value = CameraProControlReadback()
        value.width = 1920
        value.height = 1080
        value.fixedFPS = 30
        value.exposureIsAuto = true
        value.iso = 100
        value.exposureDuration = 1 / 60.0
        value.exposureBias = 0
        value.focusIsAuto = true
        value.lensPosition = 0.25
        value.whiteBalanceIsAuto = true
        value.temperature = 5600
        value.torchActive = false
        return value
    }

    var commands: [CameraProControlCommand] { state.withValue { $0.commands } }
    var cancelCount: Int { state.withValue { $0.cancelCount } }

    func onNextApply(_ callback: @escaping () -> Void) {
        state.withValue { $0.nextApply = callback }
    }

    func setReadback(_ readback: CameraProControlReadback) {
        state.withValue { $0.readback = readback }
    }

    func snapshot(generation: UInt64) -> CameraProControlsSnapshot {
        var capabilities = CameraProControlCapabilities()
        capabilities.manualFocus = true
        capabilities.autoFocus = true
        capabilities.autoExposure = true
        capabilities.exposureBiasRange = -2...2
        capabilities.isoRange = 25...1600
        capabilities.exposureDurationRange = 0.0001...1
        capabilities.customWhiteBalance = true
        return CameraProControlsSnapshot(deviceID: deviceID, captureGeneration: generation,
                                         capabilities: capabilities, readback: state.withValue { $0.readback })
    }

    func apply(_ command: CameraProControlCommand, completion: @escaping (Result<Void, CameraProControlError>) -> Void) {
        let notify = state.withValue { value -> (() -> Void)? in
            value.commands.append(command)
            value.callbacks.append(completion)
            let callback = value.nextApply
            value.nextApply = nil
            return callback
        }
        notify?()
    }

    func complete(
        _ index: Int,
        with result: Result<Void, CameraProControlError>,
        readback: CameraProControlReadback? = nil
    ) -> Bool {
        let callback = state.withValue { value -> ((Result<Void, CameraProControlError>) -> Void)? in
            guard value.callbacks.indices.contains(index) else { return nil }
            if let readback { value.readback = readback }
            return value.callbacks[index]
        }
        guard let callback else { return false }
        callback(result)
        return true
    }

    func cancelPending() {
        state.withValue { $0.cancelCount += 1 }
        // Intentionally preserve callbacks to exercise the manager's token
        // fence against native completion arriving after cancellation.
    }
}

private final class ProControlSessionRunner: CameraSessionRunner, @unchecked Sendable {
    private struct State { var running = false; var starts = 0 }
    private let state = ProControlLocked(State())
    var isRunning: Bool { state.withValue { $0.running } }
    var startCount: Int { state.withValue { $0.starts } }
    func startRunning() { state.withValue { $0.running = true; $0.starts += 1 } }
    func stopRunning() { state.withValue { $0.running = false } }
}
