import Combine
import CoreGraphics
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

private extension CameraCoachCameraBlockReason {
    var eventName: String {
        switch self {
        case .denied: "denied"
        case .restricted: "restricted"
        case .unavailable: "unavailable"
        case .unknown: "unknown"
        }
    }
}

private extension CameraCoachEntryPhase {
    var usesEntryMarker: Bool {
        switch self {
        case .intro, .permissionContext, .ready, .blocked(_):
            true
        case .resolving, .requesting:
            false
        }
    }
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
    /// Stable owner-issued event for the currently rendered phase. It changes
    /// only when the domain phase changes, not when SwiftUI recomposes.
    @Published private(set) var presentationEventID: String?
    @Published private(set) var presentationRevision: UInt64 = 0
    @Published private(set) var markerEventID: String?
    @Published private(set) var markerDrawProgress: CGFloat = 1
    @Published private(set) var leaderPhase: SETLeaderPhase?
    @Published private(set) var leaderEventID: String?
    @Published private(set) var leaderPresentationRevision: UInt64 = 0

    private let permissionClient: any PermissionClient
    private let introStore: any CameraCoachIntroStore
    /// The model is the session owner for all Entry one-shot presentation work.
    private(set) var motionEventLedger = SETMotionEventLedger()
    private let routeSessionID = UUID()
    private var didResolveInitialState = false
    private var permissionRequestTask: Task<PermissionSnapshot, Never>?
    private var recheckTask: Task<PermissionSnapshot, Never>?
    private var markerTask: Task<Void, Never>?
    private var leaderTask: Task<Void, Never>?
    private var didAcceptCameraEntry = false
    private var reduceMotion = false

    init(permissionClient: any PermissionClient,
         introStore: any CameraCoachIntroStore) {
        self.permissionClient = permissionClient
        self.introStore = introStore
    }

    /// Foreground recovery is meaningful for a blocked camera state. Intro and
    /// permission-context remain owner-driven so a lifecycle callback cannot
    /// silently skip the first-run explanation.
    var shouldRecheckOnForeground: Bool {
        if case .blocked = phase { return true }
        return false
    }

    func updateAccessibilityPreferences(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
    }

    func resolveInitialState() async {
        guard !didResolveInitialState else { return }
        didResolveInitialState = true

        let snapshot = await permissionClient.snapshot(for: .camera)
        if introStore.hasSeenCameraCoachIntro() {
            transition(to: Self.phase(for: snapshot))
        } else {
            transition(to: .intro)
        }
    }

    func openCameraTapped() async {
        guard phase == .intro else { return }

        if !introStore.hasSeenCameraCoachIntro() {
            introStore.markCameraCoachIntroSeen()
        }
        transition(to: .resolving)

        let snapshot = await permissionClient.snapshot(for: .camera)
        transition(to: Self.phase(for: snapshot))
    }

    func continuePermissionRequest() async {
        if phase == .requesting, let permissionRequestTask {
            let snapshot = await permissionRequestTask.value
            transition(to: Self.phase(for: snapshot))
            return
        }

        guard phase == .permissionContext else { return }

        transition(to: .requesting)
        let permissionClient = self.permissionClient
        let requestTask = Task<PermissionSnapshot, Never> {
            await permissionClient.request(.camera)
        }
        permissionRequestTask = requestTask

        let snapshot = await requestTask.value
        permissionRequestTask = nil
        transition(to: Self.phase(for: snapshot))
    }

    func recheckCameraAccess() async {
        if let recheckTask {
            let snapshot = await recheckTask.value
            transition(to: Self.phase(for: snapshot))
            return
        }

        transition(to: .resolving)
        let permissionClient = self.permissionClient
        let task = Task<PermissionSnapshot, Never> {
            await permissionClient.snapshot(for: .camera)
        }
        recheckTask = task

        let snapshot = await task.value
        recheckTask = nil
        transition(to: Self.phase(for: snapshot))
    }

    /// Accepts the first ready handoff for this route session. The leader is a
    /// production event, so its event ID is consumed by this model rather than
    /// by the transient overlay view.
    func acceptCameraEntry(reduceMotion: Bool? = nil) {
        guard phase == .ready, !didAcceptCameraEntry else { return }
        didAcceptCameraEntry = true
        if let reduceMotion {
            self.reduceMotion = reduceMotion
        }

        let eventID = "camera-coach.leader.\(routeSessionID.uuidString)"
        guard motionEventLedger.consume(eventID: eventID) else { return }
        leaderEventID = eventID
        leaderTask?.cancel()

        if self.reduceMotion {
            setLeaderPhase(.action)
            scheduleLeaderCompletion(eventID: eventID)
            return
        }

        setLeaderPhase(.three)
        leaderTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard await self.waitForLeaderStep(eventID: eventID, next: .two) else { return }
            guard await self.waitForLeaderStep(eventID: eventID, next: .one) else { return }
            guard await self.waitForLeaderStep(eventID: eventID, next: .action) else { return }
            self.scheduleLeaderCompletion(eventID: eventID)
        }
    }

    /// A small test seam for asserting that a domain event is owner-consumed.
    @discardableResult
    func consumePresentationEvent(_ eventID: String) -> Bool {
        motionEventLedger.consume(eventID: eventID)
    }

    private func transition(to nextPhase: CameraCoachEntryPhase) {
        guard phase != nextPhase else { return }

        markerTask?.cancel()
        phase = nextPhase
        presentationRevision &+= 1
        let phaseID = phaseEventName(nextPhase)
        let eventID = "camera-coach.entry.\(phaseID).\(presentationRevision)"
        presentationEventID = eventID
        _ = motionEventLedger.consume(eventID: eventID)

        guard nextPhase.usesEntryMarker else {
            markerEventID = nil
            markerDrawProgress = 1
            return
        }

        let markerID = "\(eventID).marker"
        markerEventID = markerID
        markerDrawProgress = 0
        guard motionEventLedger.consume(eventID: markerID) else {
            markerDrawProgress = 1
            return
        }

        guard !reduceMotion else {
            markerDrawProgress = 1
            return
        }

        markerTask = Task { @MainActor [weak self] in
            // Publish the initial geometry first, then yield once. SwiftUI
            // animates this single 0 → 1 change over the exact shared draw
            // duration; the View never consumes the event ID.
            await Task.yield()
            guard let self,
                  !Task.isCancelled,
                  self.phase == nextPhase,
                  self.markerEventID == markerID else { return }
            self.markerDrawProgress = 1
        }
    }

    private func waitForLeaderStep(
        eventID: String,
        next: SETLeaderPhase
    ) async -> Bool {
        try? await Task.sleep(nanoseconds: UInt64(SETMotion.leaderStepDuration * 1_000_000_000))
        guard !Task.isCancelled,
              leaderEventID == eventID,
              leaderPhase != nil else { return false }
        setLeaderPhase(next)
        return true
    }

    private func scheduleLeaderCompletion(eventID: String) {
        leaderTask?.cancel()
        leaderTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(SETMotion.leaderActionDuration * 1_000_000_000))
            guard let self,
                  !Task.isCancelled,
                  self.leaderEventID == eventID else { return }
            self.leaderPhase = nil
            self.leaderPresentationRevision &+= 1
        }
    }

    private func setLeaderPhase(_ phase: SETLeaderPhase) {
        leaderPhase = phase
        leaderPresentationRevision &+= 1
    }

    private func phaseEventName(_ phase: CameraCoachEntryPhase) -> String {
        switch phase {
        case .resolving: "resolving"
        case .intro: "intro"
        case .permissionContext: "permission-context"
        case .requesting: "requesting"
        case .ready: "ready"
        case .blocked(let reason): "blocked-\(reason.eventName)"
        }
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
