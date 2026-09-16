import AVFoundation
import CoreVideo
import XCTest
@testable import shafinMultitool

@MainActor
final class CameraCoachRecordingCoordinatorTests: XCTestCase {
    func testDuplicateStartsJoinWriterStartAndDoNotPublishRecordingEarly() async throws {
        let startGate = CoachHeldCallback()
        let fixture = try CoachFixture(startGate: startGate)
        defer { fixture.removeFiles() }
        let first = Task { await fixture.owner.start(audioMode: .disabled) }
        await awaitEntry(startGate)
        let second = Task { await fixture.owner.start(audioMode: .disabled) }
        await Task.yield()
        XCTAssertEqual(fixture.owner.phase, .preparing)
        XCTAssertEqual(fixture.capture.reservations, 1)
        XCTAssertEqual(fixture.recorders.count, 1)
        XCTAssertEqual(fixture.persistence.createdCount, 1)
        startGate.resume.open()
        await first.value
        await second.value
        XCTAssertEqual(fixture.owner.phase, .recording)
        XCTAssertEqual(fixture.recorders.first?.startCount, 1)
        XCTAssertEqual(fixture.recorders.first?.configuration?.audioMode, .disabled)
        _ = await fixture.owner.releaseAndWait()
    }

    func testBackgroundCancelsPermissionBeforeReplyAndLateReplyCannotAffectReplacement() async throws {
        let permissionGate = CoachHeldCallback()
        let fixture = try CoachFixture(cameraRequest: permissionGate)
        defer { fixture.removeFiles() }
        let pending = Task { await fixture.owner.start(audioMode: .disabled) }
        await awaitEntry(permissionGate)
        let backgroundFinished = expectation(description: "Background releases pending OS permission")
        var didFinishBackground = false
        let background = Task {
            await fixture.owner.handleBackground()
            didFinishBackground = true
            backgroundFinished.fulfill()
        }
        await fulfillment(of: [backgroundFinished], timeout: 2)
        if !didFinishBackground { permissionGate.resume.open() }
        await background.value
        await pending.value
        XCTAssertEqual(fixture.recorders.count, 0)
        XCTAssertEqual(fixture.persistence.createdCount, 0)
        XCTAssertEqual(fixture.capture.releases, 1)

        fixture.permissions.authorizeCamera()
        await fixture.owner.start(audioMode: .disabled)
        let replacement = try XCTUnwrap(fixture.capture.activeLease)
        permissionGate.resume.open()
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(fixture.owner.phase, .recording)
        XCTAssertEqual(fixture.capture.activeLease, replacement)
        XCTAssertEqual(fixture.capture.releases, 1)
        XCTAssertEqual(fixture.recorders.count, 1)
        _ = await fixture.owner.releaseAndWait()
    }

    func testDeniedMicrophoneNeverFallsBackAndExplicitSilentTakeDoesNotRequestIt() async throws {
        let fixture = try CoachFixture(microphoneDenied: true)
        defer { fixture.removeFiles() }
        await fixture.owner.start(audioMode: .required)
        XCTAssertEqual(fixture.owner.phase, .failed)
        guard case let .permission(snapshot)? = fixture.owner.issue else {
            return XCTFail("Expected contextual microphone denial")
        }
        XCTAssertEqual(snapshot.permission, .microphone)
        XCTAssertEqual(snapshot.authorization, .denied)
        XCTAssertEqual(fixture.persistence.createdCount, 0)
        XCTAssertEqual(fixture.recorders.count, 0)
        XCTAssertEqual(fixture.platform.activationCount, 0)
        let microphoneChecks = fixture.permissions.microphoneChecks
        await fixture.owner.start(audioMode: .disabled)
        XCTAssertEqual(fixture.owner.phase, .recording)
        XCTAssertEqual(fixture.recorders.first?.configuration?.audioMode, .disabled)
        XCTAssertEqual(fixture.permissions.microphoneChecks, microphoneChecks)
        XCTAssertEqual(fixture.platform.activationCount, 0)
        _ = await fixture.owner.releaseAndWait()
    }

    func testFailedMandatoryPreflightCreatesNoProjectAndReleasesAudioDemand() async throws {
        let fixture = try CoachFixture(preflightFailure: .audioUnavailable)
        defer { fixture.removeFiles() }
        await fixture.owner.start(audioMode: .required)
        XCTAssertEqual(fixture.owner.issue, .recorder(.audioUnavailable))
        XCTAssertEqual(fixture.persistence.createdCount, 0)
        XCTAssertEqual(fixture.recorders.count, 0)
        XCTAssertEqual(fixture.capture.releases, 1)
        let lease = await fixture.audio.currentLease
        XCTAssertNil(lease)
        XCTAssertEqual(fixture.platform.activationCount, 1)
        XCTAssertEqual(fixture.platform.deactivationCount, 1)
        _ = await fixture.owner.releaseAndWait()
    }

    func testStopAndRouteExitShareFinalizationAndCloseFrameAdmissionFirst() async throws {
        let stopGate = CoachHeldCallback()
        let fixture = try CoachFixture(stopGate: stopGate)
        defer { fixture.removeFiles() }
        await fixture.owner.start(audioMode: .disabled)
        let stop = Task { await fixture.owner.stop() }
        await awaitEntry(stopGate)
        let exit = Task { await fixture.owner.releaseAndWait() }
        await Task.yield()
        XCTAssertEqual(fixture.recorders.first?.stopCount, 1)
        let events = fixture.events.values
        let closeIndex = try XCTUnwrap(events.firstIndex(of: "capture.close"))
        let stopIndex = try XCTUnwrap(events.firstIndex(of: "recorder.stop"))
        XCTAssertLessThan(closeIndex, stopIndex)
        stopGate.resume.open()
        let first = await stop.value
        let second = await exit.value
        XCTAssertEqual(first, second)
        XCTAssertEqual(fixture.capture.releases, 1)
        XCTAssertEqual(fixture.persistence.saveCalls.count, 1)
        XCTAssertEqual(fixture.persistence.releasedCount, 1)
        XCTAssertEqual(fixture.owner.phase, .released)
    }

    func testFailedSaveBlocksNextTakeAndExplicitRetryRetainsIdentityWithoutFinalizingAgain() async throws {
        let fixture = try CoachFixture(saveFailures: 1)
        defer { fixture.removeFiles() }
        await fixture.owner.start(audioMode: .disabled)
        _ = await fixture.owner.stop()
        XCTAssertTrue(fixture.owner.hasPendingSave)
        XCTAssertNil(fixture.owner.latestSavedTake)
        XCTAssertEqual(fixture.owner.issue, .persistence(.conflict))
        await fixture.owner.start(audioMode: .disabled)
        XCTAssertEqual(fixture.owner.issue, .pendingSave)
        XCTAssertEqual(fixture.recorders.count, 1)
        await fixture.owner.retryPersistence()
        XCTAssertEqual(fixture.owner.phase, .review)
        XCTAssertFalse(fixture.owner.hasPendingSave)
        let calls = fixture.persistence.saveCalls
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls.map(\.explicitMerge), [false, true])
        XCTAssertEqual(calls.first?.artifact.id, calls.last?.artifact.id)
        XCTAssertEqual(fixture.owner.latestSavedTake?.artifact.id, calls.first?.artifact.id)
        XCTAssertEqual(fixture.recorders.first?.stopCount, 1)
        _ = await fixture.owner.releaseAndWait()
    }

    func testMeterAndRequiredRecordingShareCaptureOwnersLeaseUntilFinalDemandEnds() async throws {
        let fixture = try CoachFixture()
        defer { fixture.removeFiles() }
        await fixture.owner.setMeterEnabled(true)
        let initialLease = await fixture.audio.currentLease
        XCTAssertEqual(initialLease?.ownerID, fixture.capture.sourceOwnerID)
        await fixture.owner.start(audioMode: .required)
        let duringLease = await fixture.audio.currentLease
        XCTAssertEqual(initialLease, duringLease)
        XCTAssertEqual(fixture.platform.activationCount, 1)
        await fixture.owner.setMeterEnabled(false)
        XCTAssertEqual(fixture.owner.issue, .busy)
        XCTAssertTrue(fixture.owner.meterEnabled)
        _ = await fixture.owner.stop()
        let afterTake = await fixture.audio.currentLease
        XCTAssertEqual(initialLease, afterTake)
        XCTAssertEqual(fixture.platform.deactivationCount, 0)
        await fixture.owner.setMeterEnabled(false)
        let finalLease = await fixture.audio.currentLease
        XCTAssertNil(finalLease)
        XCTAssertEqual(fixture.platform.deactivationCount, 1)
        _ = await fixture.owner.releaseAndWait()
    }

    func testExplicitMeterSurvivesSilentTakeWithoutEnablingItsAudioTrack() async throws {
        let fixture = try CoachFixture()
        defer { fixture.removeFiles() }
        await fixture.owner.setMeterEnabled(true)
        let lease = await fixture.audio.currentLease
        await fixture.owner.start(audioMode: .disabled)
        XCTAssertEqual(fixture.recorders.first?.configuration?.audioMode, .disabled)
        _ = await fixture.owner.stop()
        let afterTake = await fixture.audio.currentLease
        XCTAssertEqual(lease, afterTake)
        XCTAssertTrue(fixture.owner.meterEnabled)
        XCTAssertEqual(fixture.platform.activationCount, 1)
        _ = await fixture.owner.releaseAndWait()
        let afterExit = await fixture.audio.currentLease
        XCTAssertNil(afterExit)
        XCTAssertFalse(fixture.owner.meterEnabled)
    }

    func testNativeFailedSnapshotUsesSameStopPathAndPublishesFailure() async throws {
        let fixture = try CoachFixture()
        defer { fixture.removeFiles() }
        await fixture.owner.start(audioMode: .disabled)
        let recorder = try XCTUnwrap(fixture.recorders.first)
        recorder.fail(.audioUnavailable)
        await eventually { fixture.owner.phase == .failed }
        XCTAssertEqual(fixture.owner.issue, .recorder(.audioUnavailable))
        XCTAssertEqual(recorder.stopCount, 1)
        XCTAssertEqual(fixture.capture.releases, 1)
        XCTAssertEqual(fixture.persistence.saveCalls.count, 0)
        XCTAssertFalse(fixture.owner.hasPendingSave)
        _ = await fixture.owner.releaseAndWait()
    }

    func testStaleHealthSnapshotCannotStopAReplacementCapture() async throws {
        let fixture = try CoachFixture()
        defer { fixture.removeFiles() }
        await fixture.owner.start(audioMode: .disabled)
        let oldRecorder = try XCTUnwrap(fixture.recorders.first)
        let gate = CoachHeldCallback()
        oldRecorder.holdNextSnapshot(gate, reportedState: .failed)
        await awaitEntry(gate)
        _ = await fixture.owner.stop()
        await fixture.owner.start(audioMode: .disabled)
        let replacement = try XCTUnwrap(fixture.capture.activeLease)
        let newRecorder = try XCTUnwrap(fixture.recorders.last)
        gate.resume.open()
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(fixture.owner.phase, .recording)
        XCTAssertEqual(fixture.capture.activeLease, replacement)
        XCTAssertEqual(newRecorder.stopCount, 0)
        XCTAssertEqual(fixture.capture.releases, 1)
        _ = await fixture.owner.releaseAndWait()
    }

    func testCancelledPreparationCannotCreateAProjectOrPublishRecordingWhenItsCallbackArrives() async throws {
        let gate = CoachHeldCallback()
        let fixture = try CoachFixture(prepareGate: gate)
        defer { fixture.removeFiles() }
        let start = Task { await fixture.owner.start(audioMode: .disabled) }
        await awaitEntry(gate)
        let stop = Task { await fixture.owner.stop(reason: .background) }
        await Task.yield()
        gate.resume.open()
        await start.value
        _ = await stop.value
        XCTAssertEqual(fixture.persistence.createdCount, 0)
        XCTAssertEqual(fixture.recorders.count, 0)
        XCTAssertEqual(fixture.capture.releases, 1)
        XCTAssertEqual(fixture.owner.phase, .idle)
        _ = await fixture.owner.releaseAndWait()
    }

    func testAudioDemandInterruptionStopsOnceDisablesMeterAndDoesNotResume() async throws {
        let fixture = try CoachFixture()
        defer { fixture.removeFiles() }
        await fixture.owner.setMeterEnabled(true)
        await fixture.owner.start(audioMode: .required)
        await fixture.owner.handleAudioInterruption()
        XCTAssertEqual(fixture.recorders.first?.stopCount, 1)
        XCTAssertFalse(fixture.owner.meterEnabled)
        let lease = await fixture.audio.currentLease
        XCTAssertNil(lease)
        XCTAssertEqual(fixture.owner.phase, .review)
        await Task.yield()
        XCTAssertEqual(fixture.capture.reservations, 1)
        _ = await fixture.owner.releaseAndWait()
    }

    func testAudioEventWithoutMicrophoneDemandDoesNotStopSilentRecording() async throws {
        let fixture = try CoachFixture()
        defer { fixture.removeFiles() }
        await fixture.owner.start(audioMode: .disabled)
        await fixture.owner.handleAudioInterruption()
        XCTAssertEqual(fixture.owner.phase, .recording)
        XCTAssertEqual(fixture.recorders.first?.stopCount, 0)
        _ = await fixture.owner.releaseAndWait()
    }

    func testReleaseRacingHeldWriterStartPreservesItsFinalizedTake() async throws {
        let gate = CoachHeldCallback()
        let fixture = try CoachFixture(startGate: gate)
        defer { fixture.removeFiles() }
        let start = Task { await fixture.owner.start(audioMode: .disabled) }
        await awaitEntry(gate)
        let exit = Task { await fixture.owner.releaseAndWait() }
        await Task.yield()
        gate.resume.open()
        await start.value
        let result = await exit.value
        guard case .finalized? = result else { return XCTFail("Finalized take was lost during exit") }
        XCTAssertEqual(fixture.persistence.saveCalls.count, 1)
        XCTAssertNotNil(fixture.owner.latestSavedTake)
        XCTAssertEqual(fixture.recorders.first?.stopCount, 1)
        XCTAssertEqual(fixture.owner.phase, .released)
    }

    func testPlaybackFencesSilentStartAndMeterUntilExactOwnerReleases() async throws {
        let fixture = try CoachFixture()
        defer { fixture.removeFiles() }
        let ownerID = UUID()
        let lease = try await fixture.owner.acquirePlaybackLease(ownerID: ownerID)
        XCTAssertEqual(lease.purpose, .playback)
        XCTAssertTrue(fixture.owner.isPlaybackActive)
        await fixture.owner.start(audioMode: .disabled)
        XCTAssertEqual(fixture.owner.issue, .busy)
        XCTAssertEqual(fixture.capture.reservations, 0)
        await fixture.owner.setMeterEnabled(true)
        XCTAssertFalse(fixture.owner.meterEnabled)
        await fixture.owner.releasePlaybackLease(ownerID: UUID())
        XCTAssertTrue(fixture.owner.isPlaybackActive)
        await fixture.owner.releasePlaybackLease(ownerID: ownerID)
        XCTAssertFalse(fixture.owner.isPlaybackActive)
        await fixture.owner.start(audioMode: .disabled)
        XCTAssertEqual(fixture.owner.phase, .recording)
        _ = await fixture.owner.releaseAndWait()
    }

    func testBackgroundRetiresPlaybackLeaseAndMeterMustBeExplicitlyDisabledBeforePlayback() async throws {
        let fixture = try CoachFixture()
        defer { fixture.removeFiles() }
        await fixture.owner.setMeterEnabled(true)
        do {
            _ = try await fixture.owner.acquirePlaybackLease(ownerID: UUID())
            XCTFail("Playback unexpectedly stole the explicit microphone meter lease")
        } catch {
            XCTAssertEqual(error as? CameraRecordingPresentationFailure, .busy)
        }
        await fixture.owner.setMeterEnabled(false)
        _ = try await fixture.owner.acquirePlaybackLease(ownerID: UUID())
        await fixture.owner.handleBackground()
        XCTAssertFalse(fixture.owner.isPlaybackActive)
        let lease = await fixture.audio.currentLease
        XCTAssertNil(lease)
        _ = await fixture.owner.releaseAndWait()
    }

    func testScopedAudioNotificationsIgnoreOwnCategoryChangeAndStopOnInterruptionBegan() async throws {
        let fixture = try CoachFixture()
        defer { fixture.removeFiles() }
        await fixture.owner.start(audioMode: .required)
        fixture.notifications.post(
            name: AVAudioSession.routeChangeNotification, object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.categoryChange.rawValue]
        )
        await Task.yield()
        XCTAssertEqual(fixture.owner.phase, .recording)
        fixture.notifications.post(
            name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        )
        await eventually { fixture.owner.phase == .review }
        XCTAssertEqual(fixture.recorders.first?.stopCount, 1)
        XCTAssertEqual(fixture.capture.releases, 1)
        _ = await fixture.owner.releaseAndWait()
    }

    func testDropCountersUseCurrentRecorderSnapshotAndResetForNewTake() async throws {
        let fixture = try CoachFixture()
        defer { fixture.removeFiles() }
        await fixture.owner.start(audioMode: .disabled)
        let first = try XCTUnwrap(fixture.recorders.first)
        first.setDrops(video: 7, audio: 2)
        await eventually { fixture.owner.droppedVideoFrames == 7 && fixture.owner.droppedAudioFrames == 2 }
        _ = await fixture.owner.stop()
        await fixture.owner.start(audioMode: .disabled)
        XCTAssertEqual(fixture.owner.droppedVideoFrames, 0)
        XCTAssertEqual(fixture.owner.droppedAudioFrames, 0)
        _ = await fixture.owner.releaseAndWait()
    }

    func testPlaybackOnlyInterruptionRetiresLeaseAndClosesPublishedPresentation() async throws {
        let fixture = try CoachFixture()
        defer { fixture.removeFiles() }
        _ = try await fixture.owner.acquirePlaybackLease(ownerID: UUID())
        fixture.notifications.post(
            name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        )
        await eventually { !fixture.owner.isPlaybackActive }
        let lease = await fixture.audio.currentLease
        XCTAssertNil(lease)
        XCTAssertEqual(fixture.capture.reservations, 0)
        _ = await fixture.owner.releaseAndWait()
    }

    func testProductionAdapterKeepsUnplayableRecoveryMovieWithoutSavingProjectReference() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CoachUnplayable-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try RecordingArtifactStore(applicationSupportDirectoryURL: root)
        let database = DBService(recordingArtifactStore: store, projectLeases: ProjectLifecycleRegistry())
        let adapter = CameraRecordingDBAdapter(database: database, artifactStore: store)
        let project = try await adapter.createProject(named: "CoachUnplayable-\(UUID().uuidString)")
        do {
            let id = UUID()
            let url = try store.makePendingURL(recordingID: id)
            try Data("unplayable recovery fixture".utf8).write(to: url)
            let artifact = RecordingArtifact(id: RecordingID(rawValue: id), localURL: url, duration: nil, hasAudio: false)
            do {
                _ = try await adapter.save(artifact, project: project, explicitlyMergeLatest: true)
                XCTFail("Unplayable recovery media must not be published as saved")
            } catch {
                XCTAssertEqual(error as? CameraRecordingPersistenceFailure, .mediaUnavailable)
            }
            guard case let .success(opened) = database.loadUnifiedSceneProjectForOpening(id: project.id) else {
                throw CameraRecordingPersistenceFailure.projectUnavailable
            }
            XCTAssertTrue(opened.project.recordingReferences.isEmpty)
            XCTAssertEqual(opened.project.updatedAt, project.updatedAt)
            let receipt = try XCTUnwrap(store.pendingReferenceAcknowledgements().first)
            XCTAssertEqual(receipt.projectID, project.id)
            XCTAssertEqual(receipt.reference.recordingID, id)
            XCTAssertNotNil(store.resolve(receipt.reference, ownedBy: project.id))
            XCTAssertNotNil(try store.journal.entry(for: id))
        } catch {
            await adapter.releaseProject(project)
            database.deleteUnifiedSceneProject(named: project.name) { _ in }
            throw error
        }
        await adapter.releaseProject(project)
        database.deleteUnifiedSceneProject(named: project.name) { _ in }
    }

    func testSuspendCancelsHeldMeterPermissionBeforeGraphStopAndLateReplyCannotEnableAudio() async throws {
        let gate = CoachHeldCallback()
        let fixture = try CoachFixture(microphoneRequest: gate)
        defer { fixture.removeFiles() }
        let meter = Task { await fixture.owner.setMeterEnabled(true) }
        await awaitEntry(gate)
        let finished = expectation(description: "Suspension drains pending meter permission")
        var didFinish = false
        let suspend = Task {
            await fixture.owner.suspendAndWait(reason: .interruption)
            didFinish = true
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)
        if !didFinish { gate.resume.open() }
        await suspend.value
        await meter.value
        XCTAssertFalse(fixture.owner.meterEnabled)
        XCTAssertEqual(fixture.platform.activationCount, 0)
        gate.resume.open()
        await Task.yield()
        await Task.yield()
        XCTAssertFalse(fixture.owner.meterEnabled)
        XCTAssertEqual(fixture.platform.activationCount, 0)
        await fixture.owner.start(audioMode: .disabled)
        XCTAssertEqual(fixture.owner.phase, .recording)
        _ = await fixture.owner.releaseAndWait()
    }

    func testNonterminalSuspendRetiresPlaybackAndAllowsAUserInitiatedTakeAfterward() async throws {
        let fixture = try CoachFixture()
        defer { fixture.removeFiles() }
        _ = try await fixture.owner.acquirePlaybackLease(ownerID: UUID())
        await fixture.owner.suspendAndWait(reason: .interruption)
        XCTAssertFalse(fixture.owner.isPlaybackActive)
        let lease = await fixture.audio.currentLease
        XCTAssertNil(lease)
        await fixture.owner.start(audioMode: .disabled)
        XCTAssertEqual(fixture.owner.phase, .recording)
        _ = await fixture.owner.releaseAndWait()
    }

    private func awaitEntry(_ gate: CoachHeldCallback) async {
        await eventually { gate.entered.isOpen }
        // Let failed regressions drain their tasks instead of hanging the suite.
        if !gate.entered.isOpen { gate.resume.open() }
    }

    private func eventually(
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition(), "Timed out awaiting coordinator state", file: file, line: line)
    }
}

@MainActor
private final class CoachFixture {
    let root: URL
    let owner: CameraCoachRecordingCoordinator
    let capture: CoachCapture
    let permissions: CoachPermissions
    let persistence: CoachPersistence
    let platform: CoachAudioPlatform
    let audio: AudioSessionCoordinator
    let events: CoachEvents
    let notifications: NotificationCenter
    private let registry: CoachRecorderRegistry
    var recorders: [CoachRecorder] { registry.values }

    init(
        startGate: CoachHeldCallback? = nil,
        stopGate: CoachHeldCallback? = nil,
        prepareGate: CoachHeldCallback? = nil,
        cameraRequest: CoachHeldCallback? = nil,
        microphoneRequest: CoachHeldCallback? = nil,
        microphoneDenied: Bool = false,
        preflightFailure: RecorderFailure? = nil,
        saveFailures: Int = 0
    ) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("CoachCoordinator-\(UUID().uuidString)")
        let store = try Self.makeVerifiedStore(root: root)
        let events = CoachEvents()
        let capture = try CoachCapture(events: events, prepareGate: prepareGate)
        let permissions = CoachPermissions(cameraRequest: cameraRequest, microphoneRequest: microphoneRequest,
                                           microphoneDenied: microphoneDenied)
        let persistence = CoachPersistence(failures: saveFailures)
        let platform = CoachAudioPlatform()
        let audio = AudioSessionCoordinator(platform: platform)
        let registry = CoachRecorderRegistry()
        let notifications = NotificationCenter()
        self.capture = capture
        self.permissions = permissions
        self.persistence = persistence
        self.platform = platform
        self.audio = audio
        self.events = events
        self.registry = registry
        self.notifications = notifications
        owner = CameraCoachRecordingCoordinator(
            capture: capture, artifactStore: store, persistence: persistence,
            permissions: permissions, audio: audio, notificationCenter: notifications,
            preflight: CoachPreflight(failure: preflightFailure),
            projectName: { "Camera fixture" }
        ) { prepared, preflight in
            SceneRecordingController(
                artifactStore: store, sourceOwnerID: prepared.lease.ownerID,
                source: .cameraCoach, preflight: preflight
            ) { _ in
                let recorder = CoachRecorder(events: events, startGate: startGate, stopGate: stopGate)
                registry.append(recorder)
                return recorder
            }
        }
    }

    func removeFiles() { try? FileManager.default.removeItem(at: root) }

    private static func makeVerifiedStore(root: URL) throws -> RecordingArtifactStore {
        try RecordingArtifactStore(applicationSupportDirectoryURL: root)
    }
}

private struct CoachPreflight: RecordingStartPreflighting {
    let failure: RecorderFailure?
    func validate(_ context: RecordingStartPreflightContext) async -> RecorderFailure? { failure }
}

private final class CoachEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    var values: [String] { lock.withLock { storage } }
    func append(_ value: String) { lock.withLock { storage.append(value) } }
}

private final class CoachSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var isOpen: Bool { lock.withLock { opened } }
    func wait() async {
        await withCheckedContinuation { continuation in
            let resume = lock.withLock { () -> Bool in
                if opened { return true }
                waiters.append(continuation)
                return false
            }
            if resume { continuation.resume() }
        }
    }
    func open() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            opened = true
            let pending = waiters
            waiters.removeAll()
            return pending
        }
        pending.forEach { $0.resume() }
    }
}

private final class CoachHeldCallback: @unchecked Sendable {
    let entered = CoachSignal()
    let resume = CoachSignal()
    func wait() async { entered.open(); await resume.wait() }
}

private final class CoachPermissions: PermissionClient, @unchecked Sendable {
    private let lock = NSLock()
    private var cameraAuthorized: Bool
    private var microphoneAuthorized: Bool
    private var microphoneChecksStorage = 0
    private let cameraRequest: CoachHeldCallback?
    private let microphoneRequest: CoachHeldCallback?
    private let microphoneDenied: Bool
    init(cameraRequest: CoachHeldCallback?, microphoneRequest: CoachHeldCallback?, microphoneDenied: Bool) {
        self.cameraRequest = cameraRequest
        self.microphoneRequest = microphoneRequest
        cameraAuthorized = cameraRequest == nil
        microphoneAuthorized = microphoneRequest == nil
        self.microphoneDenied = microphoneDenied
    }
    var microphoneChecks: Int { lock.withLock { microphoneChecksStorage } }
    func authorizeCamera() { lock.withLock { cameraAuthorized = true } }
    func snapshot(for permission: AppPermission) async -> PermissionSnapshot {
        lock.withLock {
            if permission == .microphone { microphoneChecksStorage += 1 }
            return PermissionSnapshot(
                permission: permission,
                authorization: permission == .camera && !cameraAuthorized ? .notDetermined :
                    (permission == .microphone && microphoneDenied ? .denied :
                        (permission == .microphone && !microphoneAuthorized ? .notDetermined : .authorized)),
                availability: .available
            )
        }
    }
    func request(_ permission: AppPermission) async -> PermissionSnapshot {
        if permission == .camera, let cameraRequest {
            await cameraRequest.wait()
            authorizeCamera()
        }
        if permission == .microphone, let microphoneRequest {
            await microphoneRequest.wait()
            lock.withLock { microphoneAuthorized = true }
        }
        return await snapshot(for: permission)
    }
}

private final class CoachCapture: CameraRecordingCaptureSource, @unchecked Sendable {
    let sourceOwnerID = UUID()
    private let lock = NSLock()
    private let events: CoachEvents
    private let prepareGate: CoachHeldCallback?
    private let pixelBuffer: CVPixelBuffer
    private var leaseStorage: CameraRecordingCaptureLease?
    private var reservationsStorage = 0
    private var releasesStorage = 0
    var activeLease: CameraRecordingCaptureLease? { lock.withLock { leaseStorage } }
    var reservations: Int { lock.withLock { reservationsStorage } }
    var releases: Int { lock.withLock { releasesStorage } }
    init(events: CoachEvents, prepareGate: CoachHeldCallback?) throws {
        self.events = events
        self.prepareGate = prepareGate
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess,
              let buffer else { throw CameraRecordingCaptureError.noFrames }
        pixelBuffer = buffer
    }
    func reserveRecordingCapture() async throws -> CameraRecordingCaptureLease {
        try lock.withLock {
            guard leaseStorage == nil else { throw CameraRecordingCaptureError.recordingInProgress }
            let lease = CameraRecordingCaptureLease(id: UUID(), ownerID: sourceOwnerID)
            leaseStorage = lease
            reservationsStorage += 1
            return lease
        }
    }
    func prepareRecordingCapture(lease: CameraRecordingCaptureLease, audioMode: RecordingAudioMode) async throws -> PreparedCameraRecordingCapture {
        if let prepareGate { await prepareGate.wait() }
        guard activeLease == lease else { throw CameraRecordingCaptureError.staleLease }
        return PreparedCameraRecordingCapture(
            lease: lease, pixelBuffer: pixelBuffer, timestamp: 10, fps: 30,
            trackTransform: RecordingTrackTransformMetadata(
                captureOrientation: .portrait, isMirrored: false, strategy: .preferredTransformMetadata
            ),
            audioDriverFactory: nil
        )
    }
    func attachRecordingController(_ controller: SceneRecordingController, lease: CameraRecordingCaptureLease) async throws {
        guard activeLease == lease else { throw CameraRecordingCaptureError.staleLease }
        events.append("capture.attach")
    }
    func closeRecordingFrameAdmission(_ lease: CameraRecordingCaptureLease) async {
        guard activeLease == lease else { return }
        events.append("capture.close")
    }
    func releaseRecordingCapture(_ lease: CameraRecordingCaptureLease) async {
        lock.withLock {
            guard leaseStorage == lease else { return }
            leaseStorage = nil
            releasesStorage += 1
            events.append("capture.release")
        }
    }
    func setRecordingAudioMeterEnabled(_ enabled: Bool) async throws {
        events.append(enabled ? "meter.on" : "meter.off")
    }
}

private final class CoachAudioPlatform: AudioSessionPlatform, @unchecked Sendable {
    private let lock = NSLock()
    private var activations = 0
    private var deactivations = 0
    var activationCount: Int { lock.withLock { activations } }
    var deactivationCount: Int { lock.withLock { deactivations } }
    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws {}
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        lock.withLock { if active { activations += 1 } else { deactivations += 1 } }
    }
}

private final class CoachPersistence: CameraRecordingPersisting, @unchecked Sendable {
    struct SaveCall: Sendable {
        let artifact: RecordingArtifact
        let explicitMerge: Bool
    }
    private let lock = NSLock()
    private var failures: Int
    private var createdStorage = 0
    private var releasedStorage = 0
    private var calls: [SaveCall] = []
    private var saved: CameraRecordingSavedTake?
    var createdCount: Int { lock.withLock { createdStorage } }
    var releasedCount: Int { lock.withLock { releasedStorage } }
    var saveCalls: [SaveCall] { lock.withLock { calls } }
    init(failures: Int) { self.failures = failures }
    func createProject(named name: String) async throws -> CameraRecordingProjectHandle {
        lock.withLock {
            createdStorage += 1
            return CameraRecordingProjectHandle(id: UUID(), name: name, updatedAt: Date(), leaseToken: UUID())
        }
    }
    func save(_ artifact: RecordingArtifact, project: CameraRecordingProjectHandle, explicitlyMergeLatest: Bool) async throws -> CameraRecordingSavedTake {
        try lock.withLock {
            calls.append(SaveCall(artifact: artifact, explicitMerge: explicitlyMergeLatest))
            if failures > 0 { failures -= 1; throw CameraRecordingPersistenceFailure.conflict }
            let reference = makeVerifiedReference(artifact)
            let updated = CameraRecordingProjectHandle(
                id: project.id, name: project.name,
                updatedAt: project.updatedAt.addingTimeInterval(1), leaseToken: project.leaseToken
            )
            let take = CameraRecordingSavedTake(project: updated, reference: reference, artifact: artifact)
            saved = take
            return take
        }
    }
    func releaseProject(_ project: CameraRecordingProjectHandle) async { lock.withLock { releasedStorage += 1 } }
    func resolve(_ reference: SceneRecordingReference, projectID: UUID) async -> RecordingArtifact? {
        lock.withLock { saved?.project.id == projectID && saved?.reference == reference ? saved?.artifact : nil }
    }
    private func makeVerifiedReference(_ artifact: RecordingArtifact) -> SceneRecordingReference {
        SceneRecordingReference(
            recordingID: artifact.id.rawValue,
            relativePath: "recordings/\(artifact.id.rawValue.uuidString).mov",
            duration: artifact.duration, hasAudio: artifact.hasAudio
        )
    }
}

private final class CoachRecorderRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [CoachRecorder] = []
    var values: [CoachRecorder] { lock.withLock { storage } }
    func append(_ recorder: CoachRecorder) { lock.withLock { storage.append(recorder) } }
}

private final class CoachRecorder: MediaRecording, @unchecked Sendable {
    private let lock = NSLock()
    private let events: CoachEvents
    private let startGate: CoachHeldCallback?
    private let stopGate: CoachHeldCallback?
    private var stateStorage: RecorderState = .idle
    private var owner: RecordingOwnerToken?
    private var configurationStorage: RecordingConfiguration?
    private var result: RecordingStopResult?
    private var failure: RecorderFailure?
    private var starts = 0
    private var stops = 0
    private var nextSnapshot: (CoachHeldCallback, RecorderState)?
    private var videoDrops = 0
    private var audioDrops = 0
    var state: RecorderState { get async { lock.withLock { stateStorage } } }
    var configuration: RecordingConfiguration? { lock.withLock { configurationStorage } }
    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }
    init(events: CoachEvents, startGate: CoachHeldCallback?, stopGate: CoachHeldCallback?) {
        self.events = events
        self.startGate = startGate
        self.stopGate = stopGate
    }
    func holdNextSnapshot(_ gate: CoachHeldCallback, reportedState: RecorderState) {
        lock.withLock { nextSnapshot = (gate, reportedState) }
    }
    func fail(_ failure: RecorderFailure) { lock.withLock { self.failure = failure; stateStorage = .failed } }
    func setDrops(video: Int, audio: Int) { lock.withLock { videoDrops = video; audioDrops = audio } }
    func stateSnapshot() async -> RecorderStateSnapshot {
        let (snapshot, gate) = lock.withLock { () -> (RecorderStateSnapshot, CoachHeldCallback?) in
            let held = nextSnapshot
            nextSnapshot = nil
            return (RecorderStateSnapshot(
                state: held?.1 ?? stateStorage, recordingID: configurationStorage?.id,
                generation: owner?.generation ?? 0, ownerToken: owner,
                droppedVideoCount: videoDrops, droppedAudioCount: audioDrops
            ), held?.0)
        }
        if let gate { await gate.wait() }
        return snapshot
    }
    func claimRecordingSource(_ token: RecordingOwnerToken) async -> Bool {
        lock.withLock {
            guard token.source == .cameraCoach, token.isValid, owner == nil || owner == token else { return false }
            owner = token
            return true
        }
    }
    func releaseRecordingSource(_ token: RecordingOwnerToken) async -> Bool {
        lock.withLock { guard owner == token else { return false }; owner = nil; return true }
    }
    func prepare(_ configuration: RecordingConfiguration) async throws {
        lock.withLock { configurationStorage = configuration; stateStorage = .prepared }
    }
    func start() async throws {
        lock.withLock { starts += 1 }
        if let startGate { await startGate.wait() }
        lock.withLock { stateStorage = .recording }
    }
    func stop(reason: RecordingStopReason) async -> RecordingStopResult {
        events.append("recorder.stop")
        let output = lock.withLock { () -> RecordingStopResult in
            stops += 1
            if let result { return result }
            let value: RecordingStopResult
            if let failure {
                value = .failed(failure, recoverableArtifact: nil)
            } else {
                let configuration = configurationStorage!
                value = .finalized(RecordingArtifact(
                    id: configuration.id, localURL: configuration.outputURL,
                    duration: 1, hasAudio: configuration.audioMode == .required
                ))
            }
            result = value
            stateStorage = .finishing
            return value
        }
        if let stopGate { await stopGate.wait() }
        lock.withLock { stateStorage = failure == nil ? .finished : .failed }
        return output
    }
    func releaseAndWait() async -> RecordingStopResult? {
        lock.withLock { stateStorage = .released; return result }
    }
    func enqueueVideo(_ frame: RecordingVideoFrame) { events.append("recorder.video") }
    func enqueueAudio(_ frame: RecordingAudioFrame) {}
}
