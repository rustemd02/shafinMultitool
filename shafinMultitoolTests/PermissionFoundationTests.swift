import Foundation
import AVFoundation
import AVFAudio
import Photos
import Speech
import XCTest
@testable import shafinMultitool

final class PermissionFoundationTests: XCTestCase {
    func testCameraMappingPreservesAuthorizationWhenHardwareIsUnavailable() async {
        let cases: [(AVAuthorizationStatus, PermissionAuthorization)] = [
            (.notDetermined, .notDetermined),
            (.authorized, .authorized),
            (.denied, .denied),
            (.restricted, .restricted),
            (unknownAVAuthorizationStatus(), .unknown)
        ]

        for (status, authorization) in cases {
            let platform = FakePermissionPlatform(cameraStatus: status,
                                                  cameraHardwareAvailable: false)
            let client = SystemPermissionClient(platform: platform)

            let snapshot = await client.snapshot(for: .camera)

            XCTAssertEqual(snapshot,
                           PermissionSnapshot(permission: .camera,
                                              authorization: authorization,
                                              availability: .unavailable(.cameraHardware)))
        }
    }

    func testMicrophoneMappingPreservesAuthorizationWhenHardwareIsUnavailable() async {
        let cases: [(SystemMicrophoneAuthorizationStatus, PermissionAuthorization)] = [
            (.undetermined, .notDetermined),
            (.granted, .authorized),
            (.denied, .denied),
            (unknownAudioRecordPermission(), .unknown)
        ]

        for (status, authorization) in cases {
            let platform = FakePermissionPlatform(microphoneStatus: status,
                                                  microphoneHardwareAvailable: false)
            let client = SystemPermissionClient(platform: platform)

            let snapshot = await client.snapshot(for: .microphone)

            XCTAssertEqual(snapshot,
                           PermissionSnapshot(permission: .microphone,
                                              authorization: authorization,
                                              availability: .unavailable(.microphoneHardware)))
        }
    }

    func testSpeechMappingPreservesAuthorizationWhenServiceIsUnavailable() async {
        let cases: [(SFSpeechRecognizerAuthorizationStatus, PermissionAuthorization)] = [
            (.notDetermined, .notDetermined),
            (.authorized, .authorized),
            (.denied, .denied),
            (.restricted, .restricted),
            (unknownSpeechAuthorizationStatus(), .unknown)
        ]

        for (status, authorization) in cases {
            let platform = FakePermissionPlatform(speechStatus: status,
                                                  speechServiceAvailable: false)
            let client = SystemPermissionClient(platform: platform)

            let snapshot = await client.snapshot(for: .speechRecognition)

            XCTAssertEqual(snapshot,
                           PermissionSnapshot(permission: .speechRecognition,
                                              authorization: authorization,
                                              availability: .unavailable(.speechService)))
        }
    }

    func testPhotosMappingIncludesLimitedAndAlwaysKeepsAvailabilitySeparate() async {
        let cases: [(PHAuthorizationStatus, PermissionAuthorization)] = [
            (.notDetermined, .notDetermined),
            (.authorized, .authorized),
            (.limited, .limited),
            (.denied, .denied),
            (.restricted, .restricted),
            (unknownPhotosAuthorizationStatus(), .unknown)
        ]

        for (status, authorization) in cases {
            let platform = FakePermissionPlatform(photosStatus: status)
            let client = SystemPermissionClient(platform: platform)

            let snapshot = await client.snapshot(for: .photosAddOnly)

            XCTAssertEqual(snapshot,
                           PermissionSnapshot(permission: .photosAddOnly,
                                              authorization: authorization,
                                              availability: .available))
            XCTAssertEqual(platform.photosStatusAccessLevels, [.addOnly])
        }
    }

    func testPhotosRequestUsesAddOnlyAndReturnsPostRequestSnapshot() async {
        let platform = FakePermissionPlatform(photosStatus: .notDetermined)
        let client = SystemPermissionClient(platform: platform)
        let requestTask = Task { await client.request(.photosAddOnly) }

        guard await platform.waitForRequest(.photosAddOnly) else {
            XCTFail("Photos request was not issued")
            requestTask.cancel()
            return
        }

        platform.setPhotosStatus(.limited)
        platform.complete(.photosAddOnly)

        let result = await requestTask.value
        XCTAssertEqual(result,
                       PermissionSnapshot(permission: .photosAddOnly,
                                          authorization: .limited,
                                          availability: .available))
        XCTAssertEqual(platform.photosStatusAccessLevels, [.addOnly, .addOnly])
        XCTAssertEqual(platform.photosRequestAccessLevels, [.addOnly])
    }

    func testRequestDoesNotPromptForTerminalOrUnknownStates() async {
        let cameraCases: [AVAuthorizationStatus] = [
            .authorized,
            .denied,
            .restricted,
            unknownAVAuthorizationStatus()
        ]
        for status in cameraCases {
            let platform = FakePermissionPlatform(cameraStatus: status)
            let client = SystemPermissionClient(platform: platform)

            _ = await client.request(.camera)

            XCTAssertEqual(platform.requestCount(for: .camera), 0)
        }

        let microphoneCases: [SystemMicrophoneAuthorizationStatus] = [
            .granted,
            .denied,
            unknownAudioRecordPermission()
        ]
        for status in microphoneCases {
            let platform = FakePermissionPlatform(microphoneStatus: status)
            let client = SystemPermissionClient(platform: platform)

            _ = await client.request(.microphone)

            XCTAssertEqual(platform.requestCount(for: .microphone), 0)
        }

        let speechCases: [SFSpeechRecognizerAuthorizationStatus] = [
            .authorized,
            .denied,
            .restricted,
            unknownSpeechAuthorizationStatus()
        ]
        for status in speechCases {
            let platform = FakePermissionPlatform(speechStatus: status)
            let client = SystemPermissionClient(platform: platform)

            _ = await client.request(.speechRecognition)

            XCTAssertEqual(platform.requestCount(for: .speechRecognition), 0)
        }

        let photosCases: [PHAuthorizationStatus] = [
            .authorized,
            .limited,
            .denied,
            .restricted,
            unknownPhotosAuthorizationStatus()
        ]
        for status in photosCases {
            let platform = FakePermissionPlatform(photosStatus: status)
            let client = SystemPermissionClient(platform: platform)

            _ = await client.request(.photosAddOnly)

            XCTAssertEqual(platform.requestCount(for: .photosAddOnly), 0)
        }
    }

    func testRequestReturnsCurrentPostRequestAuthorizationAndAvailability() async {
        let platform = FakePermissionPlatform(cameraStatus: .notDetermined,
                                              cameraHardwareAvailable: true)
        let client = SystemPermissionClient(platform: platform)
        let requestTask = Task { await client.request(.camera) }

        guard await platform.waitForRequest(.camera) else {
            XCTFail("Camera request was not issued")
            requestTask.cancel()
            return
        }

        platform.setCameraStatus(.authorized)
        platform.setCameraHardwareAvailable(false)
        platform.complete(.camera)

        let result = await requestTask.value
        XCTAssertEqual(result,
                       PermissionSnapshot(permission: .camera,
                                          authorization: .authorized,
                                          availability: .unavailable(.cameraHardware)))
    }

    func testConcurrentRequestsForSamePermissionUseOnePlatformRequest() async {
        let platform = FakePermissionPlatform(cameraStatus: .notDetermined)
        let client = SystemPermissionClient(platform: platform)

        async let first = client.request(.camera)
        async let second = client.request(.camera)

        guard await platform.waitForRequest(.camera) else {
            XCTFail("Camera request was not issued")
            return
        }

        platform.setCameraStatus(.authorized)
        platform.complete(.camera)

        let results = await (first, second)
        XCTAssertEqual(platform.requestCount(for: .camera), 1)
        XCTAssertEqual(results.0, results.1)
        XCTAssertEqual(results.0.authorization, .authorized)
    }

    func testDifferentPermissionsRemainIndependent() async {
        let platform = FakePermissionPlatform(cameraStatus: .notDetermined,
                                              microphoneStatus: .undetermined)
        let client = SystemPermissionClient(platform: platform)

        let cameraTask = Task { await client.request(.camera) }
        let microphoneTask = Task { await client.request(.microphone) }

        guard await platform.waitForRequest(.camera),
              await platform.waitForRequest(.microphone) else {
            XCTFail("Both independent requests were not issued")
            cameraTask.cancel()
            microphoneTask.cancel()
            return
        }

        platform.setCameraStatus(.authorized)
        platform.complete(.camera)
        let cameraResult = await cameraTask.value

        XCTAssertEqual(cameraResult.authorization, .authorized)
        XCTAssertTrue(platform.hasPendingRequest(for: .microphone))
        XCTAssertEqual(platform.requestCount(for: .microphone), 1)

        platform.setMicrophoneStatus(.granted)
        platform.complete(.microphone)
        let microphoneResult = await microphoneTask.value

        XCTAssertEqual(microphoneResult.authorization, .authorized)
        XCTAssertEqual(platform.requestCount(for: .camera), 1)
        XCTAssertEqual(platform.requestCount(for: .microphone), 1)
    }

    func testDuplicateAndLateCallbacksDoNotResumeOrMutateCompletedRequest() async {
        let platform = FakePermissionPlatform(cameraStatus: .notDetermined)
        let client = SystemPermissionClient(platform: platform)
        let requestTask = Task { await client.request(.camera) }

        guard await platform.waitForRequest(.camera) else {
            XCTFail("Camera request was not issued")
            requestTask.cancel()
            return
        }

        platform.setCameraStatus(.authorized)
        platform.complete(.camera, callbackCount: 3)
        let result = await requestTask.value

        platform.setCameraStatus(.denied)
        platform.fireLatestCallback(for: .camera, callbackCount: 2)

        XCTAssertEqual(result.authorization, .authorized)
        let current = await client.snapshot(for: .camera)
        XCTAssertEqual(current.authorization, .denied)
        XCTAssertEqual(platform.requestCount(for: .camera), 1)
    }
}

private final class FakePermissionPlatform: @unchecked Sendable, SystemPermissionPlatform {
    private let lock = NSLock()

    private var cameraStatus: AVAuthorizationStatus
    private var cameraHardwareAvailableValue: Bool
    private var microphoneStatus: SystemMicrophoneAuthorizationStatus
    private var microphoneHardwareAvailableValue: Bool
    private var speechStatus: SFSpeechRecognizerAuthorizationStatus
    private var speechServiceAvailableValue: Bool
    private var photosStatus: PHAuthorizationStatus

    private var requestCounts: [AppPermission: Int] = [:]
    private var pendingCallbacks: [AppPermission: @Sendable () -> Void] = [:]
    private var latestCallbacks: [AppPermission: @Sendable () -> Void] = [:]
    private(set) var photosStatusAccessLevels: [PHAccessLevel] = []
    private(set) var photosRequestAccessLevels: [PHAccessLevel] = []

    init(cameraStatus: AVAuthorizationStatus = .notDetermined,
         cameraHardwareAvailable: Bool = true,
         microphoneStatus: SystemMicrophoneAuthorizationStatus = .undetermined,
         microphoneHardwareAvailable: Bool = true,
         speechStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined,
         speechServiceAvailable: Bool = true,
         photosStatus: PHAuthorizationStatus = .notDetermined) {
        self.cameraStatus = cameraStatus
        self.cameraHardwareAvailableValue = cameraHardwareAvailable
        self.microphoneStatus = microphoneStatus
        self.microphoneHardwareAvailableValue = microphoneHardwareAvailable
        self.speechStatus = speechStatus
        self.speechServiceAvailableValue = speechServiceAvailable
        self.photosStatus = photosStatus
    }

    func cameraAuthorizationStatus() -> AVAuthorizationStatus {
        lock.withLock { cameraStatus }
    }

    func cameraHardwareAvailable() -> Bool {
        lock.withLock { cameraHardwareAvailableValue }
    }

    func requestCameraAccess(completion: @escaping @Sendable () -> Void) {
        recordRequest(.camera, completion: completion)
    }

    func microphoneAuthorizationStatus() -> SystemMicrophoneAuthorizationStatus {
        lock.withLock { microphoneStatus }
    }

    func microphoneHardwareAvailable() -> Bool {
        lock.withLock { microphoneHardwareAvailableValue }
    }

    func requestMicrophoneAccess(completion: @escaping @Sendable () -> Void) {
        recordRequest(.microphone, completion: completion)
    }

    func speechAuthorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
        lock.withLock { speechStatus }
    }

    func speechServiceAvailable() -> Bool {
        lock.withLock { speechServiceAvailableValue }
    }

    func requestSpeechAccess(completion: @escaping @Sendable () -> Void) {
        recordRequest(.speechRecognition, completion: completion)
    }

    func photosAuthorizationStatus(for accessLevel: PHAccessLevel) -> PHAuthorizationStatus {
        lock.withLock {
            photosStatusAccessLevels.append(accessLevel)
            return photosStatus
        }
    }

    func requestPhotosAccess(for accessLevel: PHAccessLevel,
                             completion: @escaping @Sendable () -> Void) {
        lock.withLock {
            photosRequestAccessLevels.append(accessLevel)
        }
        recordRequest(.photosAddOnly, completion: completion)
    }

    func setCameraStatus(_ status: AVAuthorizationStatus) {
        lock.withLock { cameraStatus = status }
    }

    func setCameraHardwareAvailable(_ available: Bool) {
        lock.withLock { cameraHardwareAvailableValue = available }
    }

    func setMicrophoneStatus(_ status: SystemMicrophoneAuthorizationStatus) {
        lock.withLock { microphoneStatus = status }
    }

    func setPhotosStatus(_ status: PHAuthorizationStatus) {
        lock.withLock { photosStatus = status }
    }

    func requestCount(for permission: AppPermission) -> Int {
        lock.withLock { requestCounts[permission, default: 0] }
    }

    func hasPendingRequest(for permission: AppPermission) -> Bool {
        lock.withLock { pendingCallbacks[permission] != nil }
    }

    func waitForRequest(_ permission: AppPermission) async -> Bool {
        for _ in 0..<1_000 {
            if requestCount(for: permission) > 0 {
                return true
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }

    func complete(_ permission: AppPermission, callbackCount: Int = 1) {
        let callback = lock.withLock { pendingCallbacks[permission] }
        guard let callback else { return }

        for _ in 0..<callbackCount {
            callback()
        }
    }

    func fireLatestCallback(for permission: AppPermission, callbackCount: Int) {
        let callback = lock.withLock { latestCallbacks[permission] }
        guard let callback else { return }

        for _ in 0..<callbackCount {
            callback()
        }
    }

    private func recordRequest(_ permission: AppPermission,
                               completion: @escaping @Sendable () -> Void) {
        lock.withLock {
            requestCounts[permission, default: 0] += 1
            pendingCallbacks[permission] = completion
            latestCallbacks[permission] = completion
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

private func unknownAVAuthorizationStatus() -> AVAuthorizationStatus {
    AVAuthorizationStatus(rawValue: 99)!
}

private func unknownAudioRecordPermission() -> SystemMicrophoneAuthorizationStatus {
    .unknown
}

private func unknownSpeechAuthorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
    SFSpeechRecognizerAuthorizationStatus(rawValue: 99)!
}

private func unknownPhotosAuthorizationStatus() -> PHAuthorizationStatus {
    PHAuthorizationStatus(rawValue: 99)!
}
