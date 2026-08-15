import Foundation
import AVFoundation
import AVFAudio
import Photos
import Speech

/// The platform seam is deliberately internal: production owns the live adapter,
/// while focused tests can provide statuses, availability and callbacks without
/// touching a device or presenting a system prompt.
protocol SystemPermissionPlatform: Sendable {
    func cameraAuthorizationStatus() -> AVAuthorizationStatus
    func cameraHardwareAvailable() -> Bool
    func requestCameraAccess(completion: @escaping @Sendable () -> Void)

    func microphoneAuthorizationStatus() -> SystemMicrophoneAuthorizationStatus
    func microphoneHardwareAvailable() -> Bool
    func requestMicrophoneAccess(completion: @escaping @Sendable () -> Void)

    func speechAuthorizationStatus() -> SFSpeechRecognizerAuthorizationStatus
    func speechServiceAvailable() -> Bool
    func requestSpeechAccess(completion: @escaping @Sendable () -> Void)

    func photosAuthorizationStatus(for accessLevel: PHAccessLevel) -> PHAuthorizationStatus
    func requestPhotosAccess(for accessLevel: PHAccessLevel,
                             completion: @escaping @Sendable () -> Void)
}

enum SystemMicrophoneAuthorizationStatus: Equatable, Sendable {
    case undetermined
    case granted
    case denied
    case unknown
}

private struct LiveSystemPermissionPlatform: SystemPermissionPlatform {
    func cameraAuthorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    func cameraHardwareAvailable() -> Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    func requestCameraAccess(completion: @escaping @Sendable () -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { _ in
            completion()
        }
    }

    func microphoneAuthorizationStatus() -> SystemMicrophoneAuthorizationStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined:
            return .undetermined
        case .granted:
            return .granted
        case .denied:
            return .denied
        @unknown default:
            return .unknown
        }
    }

    func microphoneHardwareAvailable() -> Bool {
        AVCaptureDevice.default(for: .audio) != nil
    }

    func requestMicrophoneAccess(completion: @escaping @Sendable () -> Void) {
        AVAudioApplication.requestRecordPermission { _ in
            completion()
        }
    }

    func speechAuthorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    func speechServiceAvailable() -> Bool {
        SFSpeechRecognizer(locale: Locale.current)?.isAvailable ?? false
    }

    func requestSpeechAccess(completion: @escaping @Sendable () -> Void) {
        SFSpeechRecognizer.requestAuthorization { _ in
            completion()
        }
    }

    func photosAuthorizationStatus(for accessLevel: PHAccessLevel) -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: accessLevel)
    }

    func requestPhotosAccess(for accessLevel: PHAccessLevel,
                             completion: @escaping @Sendable () -> Void) {
        PHPhotoLibrary.requestAuthorization(for: accessLevel) { _ in
            completion()
        }
    }
}

actor SystemPermissionClient: PermissionClient {
    private struct InFlightRequest {
        let id: UUID
        let task: Task<PermissionSnapshot, Never>
    }

    private let platform: any SystemPermissionPlatform
    private var inFlightRequests: [AppPermission: InFlightRequest] = [:]

    init(platform: any SystemPermissionPlatform = LiveSystemPermissionPlatform()) {
        self.platform = platform
    }

    func snapshot(for permission: AppPermission) async -> PermissionSnapshot {
        Self.snapshot(for: permission, using: platform)
    }

    func request(_ permission: AppPermission) async -> PermissionSnapshot {
        if let inFlightRequest = inFlightRequests[permission] {
            return await inFlightRequest.task.value
        }

        let current = Self.snapshot(for: permission, using: platform)
        guard current.authorization == .notDetermined else {
            return current
        }

        let requestID = UUID()
        let platform = self.platform
        let task = Task {
            await Self.requestSnapshot(for: permission, using: platform)
        }
        inFlightRequests[permission] = InFlightRequest(id: requestID, task: task)

        let result = await task.value
        if inFlightRequests[permission]?.id == requestID {
            inFlightRequests[permission] = nil
        }
        return result
    }

    private static func snapshot(for permission: AppPermission,
                                 using platform: any SystemPermissionPlatform) -> PermissionSnapshot {
        switch permission {
        case .camera:
            return PermissionSnapshot(
                permission: permission,
                authorization: mapCameraAuthorization(platform.cameraAuthorizationStatus()),
                availability: platform.cameraHardwareAvailable()
                    ? .available
                    : .unavailable(.cameraHardware)
            )
        case .microphone:
            return PermissionSnapshot(
                permission: permission,
                authorization: mapMicrophoneAuthorization(platform.microphoneAuthorizationStatus()),
                availability: platform.microphoneHardwareAvailable()
                    ? .available
                    : .unavailable(.microphoneHardware)
            )
        case .speechRecognition:
            return PermissionSnapshot(
                permission: permission,
                authorization: mapSpeechAuthorization(platform.speechAuthorizationStatus()),
                availability: platform.speechServiceAvailable()
                    ? .available
                    : .unavailable(.speechService)
            )
        case .photosAddOnly:
            return PermissionSnapshot(
                permission: permission,
                authorization: mapPhotosAuthorization(
                    platform.photosAuthorizationStatus(for: .addOnly)
                ),
                availability: .available
            )
        }
    }

    private static func requestSnapshot(for permission: AppPermission,
                                        using platform: any SystemPermissionPlatform) async
        -> PermissionSnapshot {
        await withCheckedContinuation { (continuation: CheckedContinuation<PermissionSnapshot, Never>) in
            let completionGate = CompletionGate()
            let complete: @Sendable () -> Void = {
                completionGate.run {
                    continuation.resume(returning: snapshot(for: permission, using: platform))
                }
            }

            switch permission {
            case .camera:
                platform.requestCameraAccess(completion: complete)
            case .microphone:
                platform.requestMicrophoneAccess(completion: complete)
            case .speechRecognition:
                platform.requestSpeechAccess(completion: complete)
            case .photosAddOnly:
                platform.requestPhotosAccess(for: .addOnly, completion: complete)
            }
        }
    }

    private static func mapCameraAuthorization(_ status: AVAuthorizationStatus)
        -> PermissionAuthorization {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unknown
        }
    }

    private static func mapMicrophoneAuthorization(
        _ status: SystemMicrophoneAuthorizationStatus
    ) -> PermissionAuthorization {
        switch status {
        case .undetermined:
            return .notDetermined
        case .granted:
            return .authorized
        case .denied:
            return .denied
        case .unknown:
            return .unknown
        }
    }

    private static func mapSpeechAuthorization(
        _ status: SFSpeechRecognizerAuthorizationStatus
    ) -> PermissionAuthorization {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unknown
        }
    }

    private static func mapPhotosAuthorization(_ status: PHAuthorizationStatus)
        -> PermissionAuthorization {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .limited:
            return .limited
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unknown
        }
    }
}

private final class CompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var hasCompleted = false

    func run(_ action: @escaping @Sendable () -> Void) {
        lock.lock()
        guard !hasCompleted else {
            lock.unlock()
            return
        }
        hasCompleted = true
        lock.unlock()

        action()
    }
}
