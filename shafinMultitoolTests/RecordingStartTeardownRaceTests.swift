//
//  RecordingStartTeardownRaceTests.swift
//  shafinMultitoolTests
//
//  M1-011 RecordingOwner: a recording start must not complete after teardown
//  begins. The deterministic barrier parks the start task inside the
//  microphone permission request while teardown completes; the resumed start
//  must abort on the owner-token guards instead of arming a take on a released
//  workspace.
//

import XCTest
@testable import shafinMultitool

@MainActor
final class RecordingStartTeardownRaceTests: XCTestCase {

    func testTeardownDuringMicrophoneAwaitAbortsRecordingStartOnReleasedWorkspace() async throws {
        let client = GatedMicrophonePermissionClient()
        let projectName = "m1-011-\(UUID().uuidString)"
        let viewModel = SceneGeneratorViewModel(
            projectName: projectName,
            isNewProject: true,
            permissionClient: client
        )
        defer {
            DBService.shared.resetUnifiedSceneProjectsForUITesting()
        }
        // Recording start requires an armed workspace: a planned scene, a ready
        // AR session, and a positive recording source FPS.
        viewModel.plannedScene = PlannedScene(placedActors: [], placedObjects: [])
        viewModel.isARSessionReady = true
        viewModel.claimRecordingSource(ownerID: UUID(), fps: 60)

        viewModel.startRecording()

        // Barrier: the start task is parked inside the microphone request.
        await client.waitUntilRequestEntered()
        XCTAssertFalse(viewModel.isRecording)

        // Teardown completes while the start task is parked.
        let teardownResult = await viewModel.teardownAndWait()
        XCTAssertEqual(teardownResult, .released)
        XCTAssertTrue(viewModel.isWorkspaceReleased)

        // Release the parked permission request; the resumed start task must
        // hit the post-await owner guards and abort without arming a take.
        client.releaseGate()
        for _ in 0..<20 {
            await Task.yield()
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(viewModel.isRecording, "a released workspace must never report an armed take")
        XCTAssertFalse(viewModel.isRecordingStarting)
        XCTAssertNil(viewModel.recordingPermissionRecovery)
    }

    func testStartAbortsWhenTeardownCompletesBeforePermissionRequest() async throws {
        let client = GatedMicrophonePermissionClient()
        let projectName = "m1-011b-\(UUID().uuidString)"
        let viewModel = SceneGeneratorViewModel(
            projectName: projectName,
            isNewProject: true,
            permissionClient: client
        )
        defer {
            DBService.shared.resetUnifiedSceneProjectsForUITesting()
        }
        // Recording start requires an armed workspace: a planned scene, a ready
        // AR session, and a positive recording source FPS.
        viewModel.plannedScene = PlannedScene(placedActors: [], placedObjects: [])
        viewModel.isARSessionReady = true
        viewModel.claimRecordingSource(ownerID: UUID(), fps: 60)

        // Complete teardown first; the workspace is released.
        let teardownResult = await viewModel.teardownAndWait()
        XCTAssertEqual(teardownResult, .released)

        // A start request on the released workspace must never reach the
        // permission client.
        viewModel.startRecording()
        for _ in 0..<20 {
            await Task.yield()
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(client.totalRequestCount, 0, "no permission request may start on a released workspace")
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertFalse(viewModel.isRecordingStarting)
    }
}

/// Permission fake whose microphone request parks on a gate so the test
/// controls exactly when the start task resumes.
private final class GatedMicrophonePermissionClient: PermissionClient, @unchecked Sendable {
    private let lock = NSLock()
    private var entered = false
    private var gated: [CheckedContinuation<Void, Never>] = []
    private var requests = 0
    private var cancelledWhileParked = false

    /// Returns once request(.microphone) has been entered (short poll: the
    /// entry flag is set before the request parks on the gate).
    func waitUntilRequestEntered() async {
        while true {
            lock.lock()
            let hasEntered = entered
            lock.unlock()
            if hasEntered { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    var totalRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func releaseGate() {
        lock.lock()
        let waiters = gated
        gated.removeAll()
        lock.unlock()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func snapshot(for permission: AppPermission) async -> PermissionSnapshot {
        PermissionSnapshot(
            permission: permission,
            authorization: permission == .microphone ? .notDetermined : .authorized,
            availability: .available
        )
    }

    func request(_ permission: AppPermission) async -> PermissionSnapshot {
        lock.lock()
        requests += 1
        entered = true
        if Task.isCancelled {
            cancelledWhileParked = true
        }
        lock.unlock()
        // Park until the test opens the gate. A cancelled waiter (the
        // production stop path cancels the start task) resumes immediately and
        // re-checks Task.isCancelled before publishing anything.
        let snapshot = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                if cancelledWhileParked {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                gated.append(continuation)
                lock.unlock()
            }
        } onCancel: {
            markCancelledAndRelease()
        }
        return PermissionSnapshot(
            permission: permission,
            authorization: .authorized,
            availability: .available
        )
    }

    private func markCancelledAndRelease() {
        lock.lock()
        cancelledWhileParked = true
        let waiters = gated
        gated.removeAll()
        lock.unlock()
        for waiter in waiters {
            waiter.resume()
        }
    }
}
