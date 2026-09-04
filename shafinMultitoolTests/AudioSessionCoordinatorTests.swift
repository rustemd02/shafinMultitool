import AVFoundation
import XCTest
@testable import shafinMultitool

final class AudioSessionCoordinatorTests: XCTestCase {

    func testRecordingAndPlaybackPoliciesAreAppliedInOrder() async throws {
        let platform = AudioSessionTestPlatform()
        let coordinator = AudioSessionCoordinator(platform: platform)
        let ownerID = UUID()

        let recordingLease = try await coordinator.acquire(
            ownerID: ownerID,
            purpose: .recording
        )
        XCTAssertEqual(recordingLease.generation, 1)
        try await coordinator.activate(recordingLease, configuration: .recording)
        try await coordinator.deactivate(recordingLease)

        let playbackLease = try await coordinator.acquire(
            ownerID: ownerID,
            purpose: .playback
        )
        XCTAssertEqual(playbackLease.generation, 2)
        try await coordinator.activate(playbackLease, configuration: .playback)
        try await coordinator.deactivate(playbackLease)

        XCTAssertEqual(platform.calls, [
            .category(
                category: AVAudioSession.Category.playAndRecord.rawValue,
                mode: AVAudioSession.Mode.videoRecording.rawValue,
                options: AudioSessionTestPlatform.recordingOptions
            ),
            .active(true, options: 0),
            .active(false, options: AVAudioSession.SetActiveOptions.notifyOthersOnDeactivation.rawValue),
            .category(
                category: AVAudioSession.Category.playback.rawValue,
                mode: AVAudioSession.Mode.moviePlayback.rawValue,
                options: 0
            ),
            .active(true, options: 0),
            .active(false, options: AVAudioSession.SetActiveOptions.notifyOthersOnDeactivation.rawValue)
        ])
    }

    func testSameOwnerAndPurposeAreIdempotentAndOtherOwnersAreBusy() async throws {
        let platform = AudioSessionTestPlatform()
        let coordinator = AudioSessionCoordinator(platform: platform)
        let ownerID = UUID()
        let otherOwnerID = UUID()

        let first = try await coordinator.acquire(ownerID: ownerID, purpose: .recording)
        let repeated = try await coordinator.acquire(ownerID: ownerID, purpose: .recording)
        XCTAssertEqual(repeated, first)

        do {
            _ = try await coordinator.acquire(ownerID: otherOwnerID, purpose: .recording)
            XCTFail("a second owner must be rejected while the first lease is live")
        } catch {
            XCTAssertEqual(
                error as? AudioSessionCoordinatorError,
                .busy(ownerID: ownerID, purpose: .recording)
            )
        }

        try await coordinator.activate(first)
        try await coordinator.activate(first)
        XCTAssertEqual(platform.calls.count, 2, "configure and active must not repeat")
        let activeState = await coordinator.state
        XCTAssertEqual(activeState, .active)

        try await coordinator.deactivate(first)
        try await coordinator.deactivate(first)
        let inactiveState = await coordinator.state
        XCTAssertEqual(inactiveState, .inactive)
    }

    func testStaleDeactivateCannotAffectReplacementLease() async throws {
        let platform = AudioSessionTestPlatform()
        let coordinator = AudioSessionCoordinator(platform: platform)

        let first = try await coordinator.acquire(ownerID: UUID(), purpose: .recording)
        try await coordinator.activate(first)
        try await coordinator.deactivate(first)

        let replacement = try await coordinator.acquire(ownerID: UUID(), purpose: .playback)
        try await coordinator.activate(replacement)
        let callsBeforeStaleRelease = platform.calls

        do {
            try await coordinator.deactivate(first)
            XCTFail("a stale lease must not release a replacement")
        } catch {
            XCTAssertEqual(error as? AudioSessionCoordinatorError, .staleLease)
        }
        XCTAssertEqual(platform.calls, callsBeforeStaleRelease)
        let currentLease = await coordinator.currentLease
        XCTAssertEqual(currentLease, replacement)
        let activeState = await coordinator.state
        XCTAssertEqual(activeState, .active)

        try await coordinator.deactivate(replacement)
    }

    func testActivationFailureClearsLeaseAndBestEffortDeactivates() async throws {
        let platform = AudioSessionTestPlatform(failActivation: true)
        let coordinator = AudioSessionCoordinator(platform: platform)
        let lease = try await coordinator.acquire(ownerID: UUID(), purpose: .recording)

        do {
            try await coordinator.activate(lease)
            XCTFail("activation failure must be surfaced")
        } catch {
            XCTAssertEqual(error as? AudioSessionCoordinatorError, .activationFailed)
        }
        let currentLease = await coordinator.currentLease
        XCTAssertNil(currentLease)
        let inactiveState = await coordinator.state
        XCTAssertEqual(inactiveState, .inactive)
        XCTAssertEqual(platform.calls, [
            .category(
                category: AVAudioSession.Category.playAndRecord.rawValue,
                mode: AVAudioSession.Mode.videoRecording.rawValue,
                options: AudioSessionTestPlatform.recordingOptions
            ),
            .active(true, options: 0),
            .active(false, options: AVAudioSession.SetActiveOptions.notifyOthersOnDeactivation.rawValue)
        ])
    }

    func testInterruptionAndRouteEventsAreTypedWithoutAutoResume() async throws {
        let platform = AudioSessionTestPlatform()
        let coordinator = AudioSessionCoordinator(platform: platform)
        let lease = try await coordinator.acquire(ownerID: UUID(), purpose: .playback)
        try await coordinator.activate(lease)

        let interruptionBegan = await coordinator.handleInterruptionBegan()
        XCTAssertEqual(interruptionBegan, .began)
        let interruptedState = await coordinator.state
        XCTAssertEqual(interruptedState, .interrupted)
        do {
            try await coordinator.activate(lease)
            XCTFail("interrupted sessions must require an explicit recovery decision")
        } catch {
            XCTAssertEqual(error as? AudioSessionCoordinatorError, .interrupted)
        }

        let interruptionEnded = await coordinator.handleInterruptionEnded(shouldResume: true)
        XCTAssertEqual(interruptionEnded, .ended(shouldResume: true))
        let inactiveState = await coordinator.state
        XCTAssertEqual(inactiveState, .inactive)
        XCTAssertEqual(
            platform.calls.filter { call in
                if case .active(true, _) = call { return true }
                return false
            }.count,
            1,
            "an interruption end reports shouldResume but never resumes"
        )

        let routeReason = await coordinator.handleRouteChange(reason: .newDeviceAvailable)
        XCTAssertEqual(routeReason, .newDeviceAvailable)
        XCTAssertEqual(
            AudioSessionRouteChangeReason(rawValue: AVAudioSession.RouteChangeReason.routeConfigurationChange.rawValue),
            .configurationChange
        )
        XCTAssertEqual(AudioSessionRouteChangeReason(rawValue: 999), .unknown)
    }

    func testMediaServicesResetInvalidatesLeaseAndAdvancesGeneration() async throws {
        let platform = AudioSessionTestPlatform()
        let coordinator = AudioSessionCoordinator(platform: platform)
        let lease = try await coordinator.acquire(ownerID: UUID(), purpose: .recording)
        try await coordinator.activate(lease)
        let generationBeforeReset = await coordinator.generation

        await coordinator.handleMediaServicesWereReset()

        let currentLease = await coordinator.currentLease
        XCTAssertNil(currentLease)
        let inactiveState = await coordinator.state
        XCTAssertEqual(inactiveState, .inactive)
        let generationAfterReset = await coordinator.generation
        XCTAssertGreaterThan(generationAfterReset, generationBeforeReset)
        do {
            try await coordinator.deactivate(lease)
            XCTFail("a reset lease must be stale")
        } catch {
            XCTAssertEqual(error as? AudioSessionCoordinatorError, .staleLease)
        }
    }
}

private final class AudioSessionTestPlatform: AudioSessionPlatform, @unchecked Sendable {
    enum Call: Equatable {
        case category(category: String, mode: String, options: UInt)
        case active(Bool, options: UInt)
    }

    static let recordingOptions =
        AVAudioSession.CategoryOptions.allowBluetoothHFP.rawValue
        | AVAudioSession.CategoryOptions.defaultToSpeaker.rawValue

    private let lock = NSLock()
    private var callsStorage: [Call] = []
    private let failActivation: Bool

    init(failActivation: Bool = false) {
        self.failActivation = failActivation
    }

    var calls: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return callsStorage
    }

    func setCategory(
        _ category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    ) throws {
        lock.lock()
        callsStorage.append(.category(
            category: category.rawValue,
            mode: mode.rawValue,
            options: options.rawValue
        ))
        lock.unlock()
    }

    func setActive(
        _ active: Bool,
        options: AVAudioSession.SetActiveOptions
    ) throws {
        lock.lock()
        callsStorage.append(.active(active, options: options.rawValue))
        lock.unlock()
        if active, failActivation {
            throw NSError(domain: "AudioSessionTestPlatform", code: 1)
        }
    }
}
