enum AppPermission: Equatable, Hashable, Sendable {
    case camera
    case microphone
    case speechRecognition
    case photosAddOnly
}

enum PermissionAuthorization: Equatable, Hashable, Sendable {
    case notDetermined
    case authorized
    case limited
    case denied
    case restricted
    case unknown
}

enum PermissionUnavailability: Equatable, Hashable, Sendable {
    case cameraHardware
    case microphoneHardware
    case speechService
}

enum PermissionAvailability: Equatable, Hashable, Sendable {
    case available
    case unavailable(PermissionUnavailability)
}

struct PermissionSnapshot: Equatable, Hashable, Sendable {
    let permission: AppPermission
    let authorization: PermissionAuthorization
    let availability: PermissionAvailability
}

protocol PermissionClient: Sendable {
    func snapshot(for permission: AppPermission) async -> PermissionSnapshot
    func request(_ permission: AppPermission) async -> PermissionSnapshot
}
