import ARKit
import CoreVideo
import XCTest
@testable import shafinMultitool

@MainActor
final class SceneRecordingPublicationTests: XCTestCase {
    private final class FaultingStore: DBService {
        var failuresRemaining = 0
        var attempts: [UnifiedSceneProject] = []

        override func saveUnifiedSceneProject(_ project: UnifiedSceneProject, worldMap: ARWorldMap?, expectedUpdatedAt: Date?) throws {
            attempts.append(project)
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                throw CocoaError(.fileWriteOutOfSpace)
            }
            try super.saveUnifiedSceneProject(project, worldMap: worldMap, expectedUpdatedAt: expectedUpdatedAt)
        }
    }

    private final class CaptureGate {
        let entered: XCTestExpectation
        private var continuation: CheckedContinuation<Result<ARWorldMap?, SceneWorkspaceTeardownFailure>, Never>?
        private var released = false

        init(_ entered: XCTestExpectation) { self.entered = entered }

        func capture() async -> Result<ARWorldMap?, SceneWorkspaceTeardownFailure> {
            if released { return .success(nil) }
            return await withCheckedContinuation {
                continuation = $0
                entered.fulfill()
            }
        }

        func release() {
            released = true
            let pending = continuation
            continuation = nil
            pending?.resume(returning: .success(nil))
        }
    }

    private struct Fixture {
        let model: SceneGeneratorViewModel
        let store: FaultingStore
        let artifacts: RecordingArtifactStore
        let controller: SceneRecordingController
        let recorder: PublicationRecorder
        let project: UnifiedSceneProject
    }

    private func fixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("scene-recording-publication-\(UUID().uuidString)")
        let artifacts = try RecordingArtifactStore(applicationSupportDirectoryURL: directory)
        let leases = ProjectLifecycleRegistry()
        let store = FaultingStore(recordingArtifactStore: artifacts, projectLeases: leases)
        let project = UnifiedSceneProject(name: "recording-publication-\(UUID().uuidString)", plannedScene: PlannedScene(placedActors: [], placedObjects: []))
        try store.saveUnifiedSceneProject(project, worldMap: nil)
        let token = try XCTUnwrap(leases.acquire(projectID: project.id))
        let recorder = PublicationRecorder()
        let controller = SceneRecordingController(artifactStore: artifacts) { _ in recorder }
        let model = SceneGeneratorViewModel(
            projectName: project.name, isNewProject: false, projectStore: store,
            presentationLocale: Locale(identifier: "en"), recordingController: controller,
            persistedProject: project, projectLeaseToken: token, projectLeaseRegistry: leases
        )
        model.isARSessionReady = true
        model.claimRecordingSource(ownerID: UUID(), fps: 30)
        model.setRecordingSoundEnabled(false)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 64, 48, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        controller.enqueueVideo(try XCTUnwrap(buffer), at: 1)
        addTeardownBlock { @MainActor in
            model.testingWorldMapCaptureOverride = nil
            store.failuresRemaining = 0
            _ = await model.teardownAndWait()
            leases.release(projectID: project.id, token: token)
            if let saved = store.listUnifiedSceneProjects().first(where: { $0.id == project.id }) {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    store.deleteUnifiedSceneProject(id: project.id, expectedUpdatedAt: saved.updatedAt) { _ in continuation.resume() }
                }
            }
            try? FileManager.default.removeItem(at: directory)
        }
        store.attempts.removeAll()
        return Fixture(model: model, store: store, artifacts: artifacts, controller: controller, recorder: recorder, project: project)
    }

    private func start(_ fixture: Fixture) async {
        fixture.model.startRecording()
        let started = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in fixture.model.isRecording }, object: nil)
        await fulfillment(of: [started], timeout: 3)
        XCTAssertTrue(fixture.model.isRecording)
        XCTAssertEqual(fixture.recorder.prepareCount, 1)
    }

    /// Joins the actual in-flight snapshot before opening its capture gate.
    private func finishSnapshot(_ model: SceneGeneratorViewModel, gate: CaptureGate) async -> Result<Void, SceneWorkspaceTeardownFailure> {
        let joined = expectation(description: "joined existing snapshot")
        let waiter = Task { @MainActor in
            joined.fulfill()
            return await model.testingPersistProjectSnapshot()
        }
        await fulfillment(of: [joined], timeout: 2)
        gate.release()
        return await waiter.value
    }

    func testFailedSaveKeepsTakePrivateAndRetryPersistsReopenableReferenceWithoutRecordingAgain() async throws {
        let f = try fixture()
        let gate = CaptureGate(expectation(description: "world map capture after promotion"))
        f.model.testingWorldMapCaptureOverride = { await gate.capture() }
        f.store.failuresRemaining = 1
        await start(f)
        f.model.stopRecording()
        await fulfillment(of: [gate.entered], timeout: 3)

        XCTAssertTrue(f.model.hasPendingRecordingSave)
        XCTAssertTrue(f.model.recordingReferences.isEmpty)
        XCTAssertNil(f.model.latestRecordingArtifact)
        XCTAssertFalse(f.model.canStartRecording)
        let acknowledgements = try f.artifacts.pendingReferenceAcknowledgements()
        XCTAssertEqual(acknowledgements.count, 1)
        XCTAssertEqual(acknowledgements.first?.expectedProjectUpdatedAt, f.project.updatedAt)
        XCTAssertNotNil(f.artifacts.resolve(try XCTUnwrap(acknowledgements.first?.reference)))

        let failed = await finishSnapshot(f.model, gate: gate)
        if case .failure(.persistenceFailed) = failed {} else { XCTFail("Expected actual project save failure") }
        XCTAssertTrue(f.model.recordingReferences.isEmpty)
        XCTAssertNil(f.model.latestRecordingArtifact)
        XCTAssertTrue(try XCTUnwrap(f.store.loadUnifiedSceneProject(named: f.project.name)).0.recordingReferences.isEmpty)
        f.model.startRecording()
        XCTAssertEqual(f.recorder.prepareCount, 1)
        XCTAssertFalse(f.model.isRecordingStarting)
        XCTAssertTrue(f.model.isGeneratorErrorBandVisible)

        let retryGate = CaptureGate(expectation(description: "retry capture"))
        f.model.testingWorldMapCaptureOverride = { await retryGate.capture() }
        let retry = Task { await f.model.retryPendingRecordingSave() }
        await fulfillment(of: [retryGate.entered], timeout: 3)
        XCTAssertTrue(f.model.isRecordingSaveRetryInFlight)
        await f.model.retryPendingRecordingSave()
        retryGate.release()
        await retry.value

        XCTAssertFalse(f.model.hasPendingRecordingSave)
        XCTAssertFalse(f.model.isRecordingSaveRetryInFlight)
        XCTAssertNil(f.model.recordingSaveFailure)
        XCTAssertEqual(f.model.recordingReferences.count, 1)
        XCTAssertEqual(f.recorder.prepareCount, 1)
        XCTAssertEqual(f.recorder.stopCount, 1)
        XCTAssertEqual(f.store.attempts.count, 2)
        XCTAssertTrue(try f.artifacts.pendingReferenceAcknowledgements().isEmpty)
        let saved = try XCTUnwrap(f.store.loadUnifiedSceneProject(named: f.project.name)).0
        XCTAssertEqual(saved.recordingReferences, f.model.recordingReferences)
        let reopened = SceneGeneratorViewModel(projectName: saved.name, isNewProject: false, projectStore: f.store,
                                               recordingController: SceneRecordingController(artifactStore: f.artifacts) { _ in PublicationRecorder() }, persistedProject: saved)
        reopened.refreshLatestAvailableRecordingArtifact()
        XCTAssertEqual(reopened.latestRecordingArtifact?.id, f.model.latestRecordingArtifact?.id)
        XCTAssertNotNil(reopened.latestRecordingArtifact)
        _ = await reopened.teardownAndWait()
    }

    func testMetadataSaveCanCommitPendingTakeAndDoesNotLoseItOnNextSnapshot() async throws {
        let f = try fixture()
        let gate = CaptureGate(expectation(description: "capture"))
        f.model.testingWorldMapCaptureOverride = { await gate.capture() }
        f.store.failuresRemaining = 1
        await start(f)
        f.model.stopRecording()
        await fulfillment(of: [gate.entered], timeout: 3)
        _ = await finishSnapshot(f.model, gate: gate)
        f.model.sceneDescription = "A saved scene note"
        XCTAssertFalse(f.model.hasPendingRecordingSave)
        XCTAssertEqual(f.model.recordingReferences.count, 1)
        XCTAssertNotNil(f.model.latestRecordingArtifact)
        _ = await f.model.testingPersistProjectSnapshot()
        XCTAssertEqual(f.store.loadUnifiedSceneProject(named: f.project.name)?.0.recordingReferences, f.model.recordingReferences)
        XCTAssertEqual(f.recorder.stopCount, 1)
    }

    func testConflictingProjectKeepsNewerBytesAndPendingTakeForRecovery() async throws {
        let f = try fixture()
        let gate = CaptureGate(expectation(description: "capture"))
        f.model.testingWorldMapCaptureOverride = { await gate.capture() }
        await start(f)
        f.model.stopRecording()
        await fulfillment(of: [gate.entered], timeout: 3)
        var newer = f.project
        newer.updatedAt = f.project.updatedAt.addingTimeInterval(100)
        newer.sceneDescription = "Newer stored project"
        try f.store.saveUnifiedSceneProject(newer, worldMap: nil, expectedUpdatedAt: f.project.updatedAt)
        _ = await finishSnapshot(f.model, gate: gate)
        await f.model.retryPendingRecordingSave()
        XCTAssertTrue(f.model.hasPendingRecordingSave)
        XCTAssertFalse(f.model.canStartRecording)
        XCTAssertTrue(f.model.recordingReferences.isEmpty)
        XCTAssertNil(f.model.latestRecordingArtifact)
        XCTAssertEqual(f.store.loadUnifiedSceneProject(named: f.project.name)?.0.sceneDescription, newer.sceneDescription)
        XCTAssertEqual(try f.artifacts.pendingReferenceAcknowledgements().count, 1)
        XCTAssertEqual(f.recorder.stopCount, 1)
    }

    func testInterruptionPersistsFinalizedTakeAndOffersSaveRetryAfterFailure() async throws {
        let f = try fixture()
        let gate = CaptureGate(expectation(description: "interruption capture"))
        f.model.testingWorldMapCaptureOverride = { await gate.capture() }
        f.store.failuresRemaining = 1
        await start(f)
        f.model.handleARSessionInterruption()
        await fulfillment(of: [gate.entered], timeout: 3)
        _ = await finishSnapshot(f.model, gate: gate)
        let failedSave = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in f.model.recordingSaveFailure != nil }, object: nil
        )
        await fulfillment(of: [failedSave], timeout: 2)
        XCTAssertTrue(f.model.isARSessionInterrupted)
        XCTAssertTrue(f.model.hasPendingRecordingSave)
        XCTAssertTrue(f.model.isGeneratorErrorBandVisible)
        XCTAssertTrue(f.model.recordingReferences.isEmpty)
        XCTAssertNil(f.model.latestRecordingArtifact)
        await f.model.retryPendingRecordingSave()
        XCTAssertFalse(f.model.hasPendingRecordingSave)
        XCTAssertNil(f.model.recordingSaveFailure)
        XCTAssertEqual(f.model.recordingReferences.count, 1)
        XCTAssertNotNil(f.model.latestRecordingArtifact)
        XCTAssertEqual(f.recorder.prepareCount, 1)
        XCTAssertEqual(f.recorder.stopCount, 1)
        XCTAssertEqual(f.store.loadUnifiedSceneProject(named: f.project.name)?.0.recordingReferences, f.model.recordingReferences)
    }

    func testWorldMapFailureStillPublishesTakeWhenMetadataSaveSucceeded() async throws {
        let f = try fixture()
        let gate = CaptureGate(expectation(description: "capture"))
        f.model.testingWorldMapCaptureOverride = {
            _ = await gate.capture()
            return .failure(.worldMapSnapshotFailed)
        }
        await start(f)
        f.model.stopRecording()
        await fulfillment(of: [gate.entered], timeout: 3)
        let result = await finishSnapshot(f.model, gate: gate)
        if case .failure(.worldMapSnapshotFailed) = result {} else { XCTFail("AR snapshot failure must remain explicit") }
        XCTAssertFalse(f.model.hasPendingRecordingSave)
        XCTAssertNil(f.model.recordingSaveFailure)
        XCTAssertEqual(f.model.recordingReferences.count, 1)
        XCTAssertNotNil(f.model.latestRecordingArtifact)
        XCTAssertEqual(f.store.loadUnifiedSceneProject(named: f.project.name)?.0.recordingReferences, f.model.recordingReferences)
    }
}

/// Produces owned nonempty fixture bytes; these tests cover project publication,
/// not codec validity or physical camera capture.
private final class PublicationRecorder: MediaRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var configuration: RecordingConfiguration?
    private var token: RecordingOwnerToken?
    private var currentState: RecorderState = .idle
    private var result: RecordingStopResult?
    private var prepares = 0
    private var stops = 0
    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }; return try body()
    }
    var prepareCount: Int { locked { prepares } }
    var stopCount: Int { locked { stops } }
    var state: RecorderState { get async { locked { currentState } } }
    func stateSnapshot() async -> RecorderStateSnapshot {
        locked { .init(state: currentState, recordingID: configuration?.id, generation: token?.generation ?? 0, ownerToken: token) }
    }
    func claimRecordingSource(_ ownerToken: RecordingOwnerToken) async -> Bool { locked { token = ownerToken; return true } }
    func releaseRecordingSource(_ ownerToken: RecordingOwnerToken) async -> Bool { locked { guard token == ownerToken else { return false }; token = nil; return true } }
    func prepare(_ configuration: RecordingConfiguration) async throws {
        try locked {
            try Data("finalized publication fixture".utf8).write(to: configuration.outputURL)
            self.configuration = configuration; prepares += 1; currentState = .prepared
        }
    }
    func start() async throws { locked { currentState = .recording } }
    func stop(reason: RecordingStopReason) async -> RecordingStopResult {
        locked {
            if let result { return result }
            stops += 1; currentState = .finished
            guard let configuration else { return .failed(.invalidTransition, recoverableArtifact: nil) }
            let finalized = RecordingStopResult.finalized(.init(id: configuration.id, localURL: configuration.outputURL, duration: 1, hasAudio: false))
            result = finalized; return finalized
        }
    }
    func releaseAndWait() async -> RecordingStopResult? { locked { currentState = .released; return result } }
    func enqueueVideo(_ frame: RecordingVideoFrame) {}
    func enqueueAudio(_ frame: RecordingAudioFrame) {}
}
