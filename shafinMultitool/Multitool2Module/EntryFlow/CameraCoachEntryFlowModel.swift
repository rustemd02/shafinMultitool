import Combine
import Foundation

enum CameraCoachCameraBlockReason: Equatable, Sendable {
    case denied
    case restricted
    case unavailable
    case unknown
}

enum CameraCoachEntryPhase: Equatable, Sendable {
    case resolving
    case intro
    case permissionContext
    case requesting
    case ready
    case blocked(CameraCoachCameraBlockReason)
}

protocol CameraCoachIntroStore {
    func hasSeenCameraCoachIntro() -> Bool
    func markCameraCoachIntroSeen()
}

struct UserDefaultsCameraCoachIntroStore: CameraCoachIntroStore {
    private static let introSeenKey = "com.vigvamcev-media.shafinMultitool.cameraCoach.entry.introSeen"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hasSeenCameraCoachIntro() -> Bool {
        defaults.bool(forKey: Self.introSeenKey)
    }

    func markCameraCoachIntroSeen() {
        defaults.set(true, forKey: Self.introSeenKey)
    }
}

@MainActor
final class CameraCoachEntryFlowModel: ObservableObject {
    @Published private(set) var phase: CameraCoachEntryPhase = .resolving

    private let permissionClient: any PermissionClient
    private let introStore: any CameraCoachIntroStore
    private var didResolveInitialState = false
    private var permissionRequestTask: Task<PermissionSnapshot, Never>?

    init(permissionClient: any PermissionClient,
         introStore: any CameraCoachIntroStore) {
        self.permissionClient = permissionClient
        self.introStore = introStore
    }

    func resolveInitialState() async {
        guard !didResolveInitialState else { return }
        didResolveInitialState = true

        let snapshot = await permissionClient.snapshot(for: .camera)
        if introStore.hasSeenCameraCoachIntro() {
            phase = Self.phase(for: snapshot)
        } else {
            phase = .intro
        }
    }

    func openCameraTapped() async {
        guard phase == .intro else { return }

        if !introStore.hasSeenCameraCoachIntro() {
            introStore.markCameraCoachIntroSeen()
        }
        phase = .resolving

        let snapshot = await permissionClient.snapshot(for: .camera)
        phase = Self.phase(for: snapshot)
    }

    func continuePermissionRequest() async {
        if phase == .requesting, let permissionRequestTask {
            let snapshot = await permissionRequestTask.value
            phase = Self.phase(for: snapshot)
            return
        }

        guard phase == .permissionContext else { return }

        phase = .requesting
        let permissionClient = self.permissionClient
        let requestTask = Task<PermissionSnapshot, Never> {
            await permissionClient.request(.camera)
        }
        permissionRequestTask = requestTask

        let snapshot = await requestTask.value
        permissionRequestTask = nil
        phase = Self.phase(for: snapshot)
    }

    func recheckCameraAccess() async {
        phase = .resolving
        let snapshot = await permissionClient.snapshot(for: .camera)
        phase = Self.phase(for: snapshot)
    }

    private static func phase(for snapshot: PermissionSnapshot) -> CameraCoachEntryPhase {
        guard snapshot.availability == .available else {
            return .blocked(.unavailable)
        }

        switch snapshot.authorization {
        case .notDetermined:
            return .permissionContext
        case .authorized:
            return .ready
        case .denied:
            return .blocked(.denied)
        case .restricted:
            return .blocked(.restricted)
        case .limited, .unknown:
            return .blocked(.unknown)
        }
    }
}
