//
//  PermissionCoordinatorTests.swift
//  shafinMultitoolTests
//
//  M1-005 PermissionOwner: concurrent requests coalesce into one client
//  request, completion is delivered once per caller, and every authorization
//  state is delivered verbatim. Delayed fake clients make the interleavings
//  deterministic.
//

import XCTest
@testable import shafinMultitool

final class PermissionCoordinatorTests: XCTestCase {

    private func makeSnapshot(
        _ permission: AppPermission,
        authorization: PermissionAuthorization
    ) -> PermissionSnapshot {
        PermissionSnapshot(
            permission: permission,
            authorization: authorization,
            availability: .available
        )
    }

    func testConcurrentRequestsCoalesceIntoOneClientRequestAndDeliverOnce() async {
        let client = DelayedPermissionClient(
            responses: [.camera: makeSnapshot(.camera, authorization: .authorized)],
            delayNanoseconds: 50_000_000
        )
        let coordinator = PermissionCoordinator(client: client)

        let snapshots = await withTaskGroup(of: PermissionSnapshot.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    await coordinator.request(.camera)
                }
            }
            var collected: [PermissionSnapshot] = []
            for await snapshot in group {
                collected.append(snapshot)
            }
            return collected
        }

        XCTAssertEqual(snapshots.count, 8)
        XCTAssertTrue(
            snapshots.allSatisfy { $0 == snapshots[0] },
            "every joined caller must receive the same snapshot"
        )
        XCTAssertEqual(snapshots[0].authorization, .authorized)
        XCTAssertEqual(client.requestCounts[.camera], 1, "concurrent requests must coalesce into one client request")
    }

    func testSequentialRequestsAfterCompletionIssueNewClientRequests() async {
        let client = DelayedPermissionClient(
            responses: [.microphone: makeSnapshot(.microphone, authorization: .notDetermined)],
            delayNanoseconds: 0
        )
        let coordinator = PermissionCoordinator(client: client)

        _ = await coordinator.request(.microphone)
        _ = await coordinator.request(.microphone)

        XCTAssertEqual(client.requestCounts[.microphone], 2, "a completed fence must not swallow later requests")
    }

    func testDifferentPermissionsDoNotCoalesceWithEachOther() async {
        let client = DelayedPermissionClient(
            responses: [
                .camera: makeSnapshot(.camera, authorization: .authorized),
                .microphone: makeSnapshot(.microphone, authorization: .denied),
            ],
            delayNanoseconds: 30_000_000
        )
        let coordinator = PermissionCoordinator(client: client)

        async let camera = coordinator.request(.camera)
        async let microphone = coordinator.request(.microphone)
        let (cameraSnapshot, microphoneSnapshot) = await (camera, microphone)

        XCTAssertEqual(client.requestCounts[.camera], 1)
        XCTAssertEqual(client.requestCounts[.microphone], 1)
        XCTAssertEqual(cameraSnapshot.authorization, .authorized)
        XCTAssertEqual(microphoneSnapshot.authorization, .denied)
    }

    func testSnapshotAlwaysBypassesTheRequestFence() async {
        let client = DelayedPermissionClient(
            responses: [.camera: makeSnapshot(.camera, authorization: .authorized)],
            delayNanoseconds: 50_000_000
        )
        let coordinator = PermissionCoordinator(client: client)

        async let requestResult = coordinator.request(.camera)
        let liveSnapshot = await coordinator.snapshot(for: .camera)
        _ = await requestResult

        XCTAssertEqual(client.snapshotCounts[.camera], 1, "snapshots must stay live during an in-flight request")
        XCTAssertEqual(liveSnapshot.permission, .camera)
    }

    func testEveryAuthorizationStateIsDeliveredVerbatim() async {
        let states: [PermissionAuthorization] = [
            .notDetermined, .authorized, .limited, .denied, .restricted, .unknown,
        ]

        for state in states {
            let client = DelayedPermissionClient(
                responses: [.speechRecognition: makeSnapshot(.speechRecognition, authorization: state)],
                delayNanoseconds: 10_000_000
            )
            let coordinator = PermissionCoordinator(client: client)

            let snapshot = await coordinator.request(.speechRecognition)
            XCTAssertEqual(snapshot.authorization, state, "state \(state) must be delivered verbatim")
        }
    }

    func testCancelledWaiterDoesNotAffectJoinedCallers() async {
        let client = DelayedPermissionClient(
            responses: [.photosAddOnly: makeSnapshot(.photosAddOnly, authorization: .limited)],
            delayNanoseconds: 50_000_000
        )
        let coordinator = PermissionCoordinator(client: client)

        let cancelledCaller = Task {
            try? await Task.sleep(nanoseconds: 5_000_000)
            return await coordinator.request(.photosAddOnly)
        }
        let joinedCaller = Task {
            await coordinator.request(.photosAddOnly)
        }
        cancelledCaller.cancel()

        let joined = await joinedCaller.value
        XCTAssertEqual(joined.authorization, .limited)
        XCTAssertEqual(client.requestCounts[.photosAddOnly], 1)
        _ = await cancelledCaller.value
    }
}

/// Deterministic fake client: records per-permission call counts and delays
/// every response by a fixed amount so concurrent interleavings are stable.
private final class DelayedPermissionClient: PermissionClient, @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequestCounts: [AppPermission: Int] = [:]
    private var storedSnapshotCounts: [AppPermission: Int] = [:]
    private let responses: [AppPermission: PermissionSnapshot]
    private let delayNanoseconds: UInt64

    init(responses: [AppPermission: PermissionSnapshot], delayNanoseconds: UInt64) {
        self.responses = responses
        self.delayNanoseconds = delayNanoseconds
    }

    var requestCounts: [AppPermission: Int] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequestCounts
    }

    var snapshotCounts: [AppPermission: Int] {
        lock.lock()
        defer { lock.unlock() }
        return storedSnapshotCounts
    }

    func snapshot(for permission: AppPermission) async -> PermissionSnapshot {
        lock.lock()
        storedSnapshotCounts[permission, default: 0] += 1
        lock.unlock()
        return fallback(for: permission)
    }

    func request(_ permission: AppPermission) async -> PermissionSnapshot {
        lock.lock()
        storedRequestCounts[permission, default: 0] += 1
        lock.unlock()
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return fallback(for: permission)
    }

    private func fallback(for permission: AppPermission) -> PermissionSnapshot {
        responses[permission] ?? PermissionSnapshot(
            permission: permission,
            authorization: .unknown,
            availability: .available
        )
    }
}
