import XCTest
@testable import shafinMultitool

@MainActor
final class CameraCoachEntryFlowModelTests: XCTestCase {
    func testFirstLaunchShowsIntroRegardlessOfCameraSnapshot() async {
        let client = MockPermissionClient(
            snapshot: cameraSnapshot(authorization: .authorized),
            queuedSnapshots: [],
            requestResult: cameraSnapshot(authorization: .authorized)
        )
        let introStore = InMemoryCameraCoachIntroStore()
        let model = CameraCoachEntryFlowModel(
            permissionClient: client,
            introStore: introStore
        )

        await model.resolveInitialState()

        XCTAssertEqual(model.phase, .intro)
        XCTAssertFalse(introStore.hasSeenCameraCoachIntro())
        let snapshotCount = await client.snapshotCount(for: .camera)
        let requestCount = await client.requestCount(for: .camera)
        XCTAssertEqual(snapshotCount, 1)
        XCTAssertEqual(requestCount, 0)
    }

    func testReturningUserMapsEveryCameraStateWithoutImplicitRequest() async {
        let cases: [(PermissionSnapshot, CameraCoachEntryPhase)] = [
            (cameraSnapshot(authorization: .authorized), .ready),
            (cameraSnapshot(authorization: .notDetermined), .permissionContext),
            (cameraSnapshot(authorization: .denied), .blocked(.denied)),
            (cameraSnapshot(authorization: .restricted), .blocked(.restricted)),
            (cameraSnapshot(authorization: .unknown), .blocked(.unknown)),
            (cameraSnapshot(authorization: .authorized, available: false), .blocked(.unavailable))
        ]

        for (snapshot, expectedPhase) in cases {
            let client = MockPermissionClient(
                snapshot: snapshot,
                queuedSnapshots: [],
                requestResult: snapshot
            )
            let model = CameraCoachEntryFlowModel(
                permissionClient: client,
                introStore: InMemoryCameraCoachIntroStore(seen: true)
            )

            await model.resolveInitialState()

            XCTAssertEqual(model.phase, expectedPhase)
            let requestCount = await client.requestCount(for: .camera)
            XCTAssertEqual(requestCount, 0)
        }
    }

    func testOpenCameraMarksIntroOnceAndMapsFreshSnapshotWithoutRequesting() async {
        let initialSnapshot = cameraSnapshot(authorization: .authorized)
        let freshSnapshot = cameraSnapshot(authorization: .notDetermined)
        let client = MockPermissionClient(
            snapshot: freshSnapshot,
            queuedSnapshots: [initialSnapshot, freshSnapshot],
            requestResult: freshSnapshot
        )
        let introStore = InMemoryCameraCoachIntroStore()
        let model = CameraCoachEntryFlowModel(
            permissionClient: client,
            introStore: introStore
        )

        await model.resolveInitialState()
        await model.openCameraTapped()
        await model.openCameraTapped()

        XCTAssertEqual(model.phase, .permissionContext)
        XCTAssertTrue(introStore.hasSeenCameraCoachIntro())
        XCTAssertEqual(introStore.markCount, 1)
        let snapshotCount = await client.snapshotCount(for: .camera)
        let requestCount = await client.requestCount(for: .camera)
        XCTAssertEqual(snapshotCount, 2)
        XCTAssertEqual(requestCount, 0)
    }

    func testContinueRequestsCameraExactlyOnceAfterExplicitTap() async {
        let notDetermined = cameraSnapshot(authorization: .notDetermined)
        let client = MockPermissionClient(
            snapshot: notDetermined,
            queuedSnapshots: [notDetermined],
            requestResult: cameraSnapshot(authorization: .authorized)
        )
        let model = CameraCoachEntryFlowModel(
            permissionClient: client,
            introStore: InMemoryCameraCoachIntroStore()
        )

        await model.resolveInitialState()
        await model.openCameraTapped()
        XCTAssertEqual(model.phase, .permissionContext)

        await model.continuePermissionRequest()

        XCTAssertEqual(model.phase, .ready)
        let requestCount = await client.requestCount(for: .camera)
        XCTAssertEqual(requestCount, 1)
        let requestedPermissions = await client.requestedPermissions()
        XCTAssertEqual(requestedPermissions, [.camera])
    }

    func testConcurrentContinueTapsShareOneRequest() async {
        let notDetermined = cameraSnapshot(authorization: .notDetermined)
        let authorized = cameraSnapshot(authorization: .authorized)
        let client = MockPermissionClient(
            snapshot: notDetermined,
            queuedSnapshots: [notDetermined],
            requestResult: authorized,
            holdsRequest: true
        )
        let model = CameraCoachEntryFlowModel(
            permissionClient: client,
            introStore: InMemoryCameraCoachIntroStore()
        )

        await model.resolveInitialState()
        await model.openCameraTapped()

        let firstTap = Task { @MainActor in
            await model.continuePermissionRequest()
        }
        let requestIssued = await client.waitUntilRequestIssued()
        XCTAssertTrue(requestIssued)
        let secondTap = Task { @MainActor in
            await model.continuePermissionRequest()
        }

        await Task.yield()
        let requestCountBeforeCompletion = await client.requestCount(for: .camera)
        XCTAssertEqual(requestCountBeforeCompletion, 1)

        await client.completeRequest()
        await firstTap.value
        await secondTap.value

        XCTAssertEqual(model.phase, .ready)
        let requestCount = await client.requestCount(for: .camera)
        XCTAssertEqual(requestCount, 1)
    }

    func testRecheckReadsSnapshotAndRecoversAfterSettingsWithoutRequest() async {
        let denied = cameraSnapshot(authorization: .denied)
        let authorized = cameraSnapshot(authorization: .authorized)
        let client = MockPermissionClient(
            snapshot: denied,
            queuedSnapshots: [],
            requestResult: authorized
        )
        let model = CameraCoachEntryFlowModel(
            permissionClient: client,
            introStore: InMemoryCameraCoachIntroStore(seen: true)
        )

        await model.resolveInitialState()
        XCTAssertEqual(model.phase, .blocked(.denied))

        await client.setSnapshot(authorized)
        await model.recheckCameraAccess()

        XCTAssertEqual(model.phase, .ready)
        let requestCount = await client.requestCount(for: .camera)
        XCTAssertEqual(requestCount, 0)
        let snapshotCount = await client.snapshotCount(for: .camera)
        XCTAssertEqual(snapshotCount, 2)
    }

    func testEntryFlowNeverRequestsMicrophoneSpeechOrPhotos() async {
        let notDetermined = cameraSnapshot(authorization: .notDetermined)
        let client = MockPermissionClient(
            snapshot: notDetermined,
            queuedSnapshots: [notDetermined],
            requestResult: cameraSnapshot(authorization: .authorized)
        )
        let model = CameraCoachEntryFlowModel(
            permissionClient: client,
            introStore: InMemoryCameraCoachIntroStore()
        )

        await model.resolveInitialState()
        await model.openCameraTapped()
        await model.continuePermissionRequest()

        let requestedPermissions = await client.requestedPermissions()
        XCTAssertFalse(requestedPermissions.contains(.microphone))
        XCTAssertFalse(requestedPermissions.contains(.speechRecognition))
        XCTAssertFalse(requestedPermissions.contains(.photosAddOnly))
    }

    private func cameraSnapshot(authorization: PermissionAuthorization,
                                available: Bool = true) -> PermissionSnapshot {
        PermissionSnapshot(
            permission: .camera,
            authorization: authorization,
            availability: available ? .available : .unavailable(.cameraHardware)
        )
    }
}

private final class InMemoryCameraCoachIntroStore: CameraCoachIntroStore {
    private(set) var seen: Bool
    private(set) var markCount = 0

    init(seen: Bool = false) {
        self.seen = seen
    }

    func hasSeenCameraCoachIntro() -> Bool {
        seen
    }

    func markCameraCoachIntroSeen() {
        markCount += 1
        seen = true
    }
}

private actor MockPermissionClient: PermissionClient {
    private var currentSnapshot: PermissionSnapshot
    private var queuedSnapshots: [PermissionSnapshot]
    private let requestResult: PermissionSnapshot
    private let holdsRequest: Bool
    private var snapshotCounts: [AppPermission: Int] = [:]
    private var requestCounts: [AppPermission: Int] = [:]
    private var requestContinuations: [CheckedContinuation<PermissionSnapshot, Never>] = []
    private var requestedPermissionList: [AppPermission] = []

    init(snapshot: PermissionSnapshot,
         queuedSnapshots: [PermissionSnapshot],
         requestResult: PermissionSnapshot,
         holdsRequest: Bool = false) {
        self.currentSnapshot = snapshot
        self.queuedSnapshots = queuedSnapshots
        self.requestResult = requestResult
        self.holdsRequest = holdsRequest
    }

    func snapshot(for permission: AppPermission) async -> PermissionSnapshot {
        snapshotCounts[permission, default: 0] += 1
        if !queuedSnapshots.isEmpty {
            return queuedSnapshots.removeFirst()
        }
        return currentSnapshot
    }

    func request(_ permission: AppPermission) async -> PermissionSnapshot {
        requestCounts[permission, default: 0] += 1
        requestedPermissionList.append(permission)
        guard holdsRequest else { return requestResult }

        return await withCheckedContinuation { continuation in
            requestContinuations.append(continuation)
        }
    }

    func setSnapshot(_ snapshot: PermissionSnapshot) {
        currentSnapshot = snapshot
    }

    func completeRequest() {
        let continuations = requestContinuations
        requestContinuations.removeAll()
        continuations.forEach { $0.resume(returning: requestResult) }
    }

    func snapshotCount(for permission: AppPermission) -> Int {
        snapshotCounts[permission, default: 0]
    }

    func requestCount(for permission: AppPermission) -> Int {
        requestCounts[permission, default: 0]
    }

    func requestedPermissions() -> [AppPermission] {
        requestedPermissionList
    }

    func waitUntilRequestIssued() async -> Bool {
        for _ in 0..<1_000 {
            if requestCounts[.camera, default: 0] > 0 {
                return true
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }
}
