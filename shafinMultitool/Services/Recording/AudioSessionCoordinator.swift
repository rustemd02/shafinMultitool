import AVFoundation
import Foundation

private extension UUID {
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}

/// The two audio-session users in the app.  A lease has one purpose for its
/// entire lifetime; recording and recorded-take playback can never overlap.
enum AudioSessionPurpose: String, CaseIterable, Sendable, Equatable {
    case recording
    case playback
}

enum AudioSessionState: String, CaseIterable, Sendable, Equatable {
    case inactive
    case active
    case interrupted
}

/// The exact AVAudioSession policy for one purpose.  Options are deliberately
/// data, so tests can inspect the selected policy without touching AVFoundation.
struct AudioSessionConfiguration: @unchecked Sendable, Equatable {
    let purpose: AudioSessionPurpose
    let category: AVAudioSession.Category
    let mode: AVAudioSession.Mode
    let options: AVAudioSession.CategoryOptions

    static let recording = AudioSessionConfiguration(
        purpose: .recording,
        category: .playAndRecord,
        mode: .videoRecording,
        options: [.allowBluetoothHFP, .defaultToSpeaker]
    )

    static let playback = AudioSessionConfiguration(
        purpose: .playback,
        category: .playback,
        mode: .moviePlayback,
        options: []
    )

    static func forPurpose(_ purpose: AudioSessionPurpose) -> Self {
        switch purpose {
        case .recording: return .recording
        case .playback: return .playback
        }
    }
}

typealias AudioSessionPolicy = AudioSessionConfiguration

/// A lease is valid only when every identity component matches the
/// coordinator's current lease.  `generation` is never zero for a lease
/// created by `AudioSessionCoordinator`.
struct AudioSessionLease: Hashable, Sendable, Equatable {
    let id: UUID
    let ownerID: UUID
    let purpose: AudioSessionPurpose
    let generation: UInt64

    init(id: UUID = UUID(),
         ownerID: UUID,
         purpose: AudioSessionPurpose,
         generation: UInt64) {
        self.id = id
        self.ownerID = ownerID
        self.purpose = purpose
        self.generation = generation
    }

    var isValid: Bool {
        id != UUID.zero && ownerID != UUID.zero && generation > 0
    }
}

enum AudioSessionCoordinatorError: Error, Sendable, Equatable {
    case invalidLease
    case busy(ownerID: UUID, purpose: AudioSessionPurpose)
    case staleLease
    case configurationFailed
    case activationFailed
    case deactivationFailed
    case interrupted
}

enum AudioSessionInterruption: Sendable, Equatable {
    case began
    case ended(shouldResume: Bool)
}

enum AudioSessionRouteChangeReason: String, CaseIterable, Sendable, Equatable {
    case newDeviceAvailable
    case oldDeviceUnavailable
    case categoryChange
    case override
    case wakeFromSleep
    case noSuitableRouteForCategory
    case configurationChange
    case unknown

    init(rawValue: UInt) {
        switch rawValue {
        case AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue:
            self = .newDeviceAvailable
        case AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue:
            self = .oldDeviceUnavailable
        case AVAudioSession.RouteChangeReason.categoryChange.rawValue:
            self = .categoryChange
        case AVAudioSession.RouteChangeReason.override.rawValue:
            self = .override
        case AVAudioSession.RouteChangeReason.wakeFromSleep.rawValue:
            self = .wakeFromSleep
        case AVAudioSession.RouteChangeReason.noSuitableRouteForCategory.rawValue:
            self = .noSuitableRouteForCategory
        case AVAudioSession.RouteChangeReason.routeConfigurationChange.rawValue:
            self = .configurationChange
        default:
            self = .unknown
        }
    }
}

enum AudioSessionEvent: Sendable, Equatable {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case routeChanged(AudioSessionRouteChangeReason)
    case mediaServicesWereReset
}

/// Small platform seam.  Only `LiveAudioSessionPlatform` below calls the
/// AVAudioSession mutators; tests inject a recording fake here.
protocol AudioSessionPlatform: Sendable {
    func setCategory(_ category: AVAudioSession.Category,
                     mode: AVAudioSession.Mode,
                     options: AVAudioSession.CategoryOptions) throws
    func setActive(_ active: Bool,
                   options: AVAudioSession.SetActiveOptions) throws
}

typealias AudioSessionPlatformAdapter = AudioSessionPlatform

private final class LiveAudioSessionPlatform: AudioSessionPlatform, @unchecked Sendable {
    private let session: AVAudioSession

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    func setCategory(_ category: AVAudioSession.Category,
                     mode: AVAudioSession.Mode,
                     options: AVAudioSession.CategoryOptions) throws {
        try session.setCategory(category, mode: mode, options: options)
    }

    func setActive(_ active: Bool,
                   options: AVAudioSession.SetActiveOptions) throws {
        try session.setActive(active, options: options)
    }
}

/// Single serialized owner for recording and recorded-take playback audio.
/// The actor intentionally does not resume after interruptions: the owning
/// route must make a new explicit activation decision.
actor AudioSessionCoordinator {
    static let shared: AudioSessionCoordinator = {
        let coordinator = AudioSessionCoordinator(platform: LiveAudioSessionPlatform())
        Task { await coordinator.startObservingNotifications() }
        return coordinator
    }()

    private let platform: any AudioSessionPlatform
    private var leaseStorage: AudioSessionLease?
    private var stateStorage: AudioSessionState = .inactive
    private var configurationStorage: AudioSessionConfiguration?
    private var generationStorage: UInt64 = 0
    private var lastReleasedLease: AudioSessionLease?
    private var notificationTokens: [NSObjectProtocol] = []

    init(platform: any AudioSessionPlatform = LiveAudioSessionPlatform()) {
        self.platform = platform
    }

    var state: AudioSessionState { stateStorage }
    var currentLease: AudioSessionLease? { leaseStorage }
    var generation: UInt64 { generationStorage }

    func startObservingNotifications() {
        guard notificationTokens.isEmpty else { return }
        installNotificationObservers()
    }

    /// Same owner and purpose are idempotent. Any other live owner is busy.
    func acquire(ownerID: UUID, purpose: AudioSessionPurpose) throws -> AudioSessionLease {
        guard ownerID != UUID.zero else { throw AudioSessionCoordinatorError.invalidLease }

        if let leaseStorage {
            guard leaseStorage.isValid else {
                clearLease(bestEffortDeactivate: true)
                throw AudioSessionCoordinatorError.invalidLease
            }
            if leaseStorage.ownerID == ownerID, leaseStorage.purpose == purpose {
                return leaseStorage
            }
            throw AudioSessionCoordinatorError.busy(
                ownerID: leaseStorage.ownerID,
                purpose: leaseStorage.purpose
            )
        }

        generationStorage = nextGeneration(generationStorage)
        lastReleasedLease = nil
        let lease = AudioSessionLease(
            id: UUID(),
            ownerID: ownerID,
            purpose: purpose,
            generation: generationStorage
        )
        leaseStorage = lease
        stateStorage = .inactive
        configurationStorage = nil
        return lease
    }

    func acquire(purpose: AudioSessionPurpose, ownerID: UUID) throws -> AudioSessionLease {
        try acquire(ownerID: ownerID, purpose: purpose)
    }

    func acquireLease(ownerID: UUID, purpose: AudioSessionPurpose) throws -> AudioSessionLease {
        try acquire(ownerID: ownerID, purpose: purpose)
    }

    /// Applies category/mode/options without activating. Repeated application
    /// of the same lease/configuration is idempotent.
    func configure(_ lease: AudioSessionLease,
                   configuration: AudioSessionConfiguration? = nil) throws {
        try validate(lease)
        guard stateStorage != .interrupted else {
            throw AudioSessionCoordinatorError.interrupted
        }
        let selected = configuration ?? .forPurpose(lease.purpose)
        guard selected.purpose == lease.purpose else {
            throw AudioSessionCoordinatorError.configurationFailed
        }
        if configurationStorage == selected {
            return
        }
        do {
            try platform.setCategory(
                selected.category,
                mode: selected.mode,
                options: selected.options
            )
            configurationStorage = selected
        } catch {
            clearLease(bestEffortDeactivate: true)
            throw AudioSessionCoordinatorError.configurationFailed
        }
    }

    func activate(_ lease: AudioSessionLease,
                  configuration: AudioSessionConfiguration? = nil) throws {
        try validate(lease)
        guard stateStorage != .interrupted else {
            throw AudioSessionCoordinatorError.interrupted
        }
        let selected = configuration ?? .forPurpose(lease.purpose)
        guard selected.purpose == lease.purpose else {
            throw AudioSessionCoordinatorError.configurationFailed
        }
        if stateStorage == .active, configurationStorage == selected {
            return
        }

        do {
            try configure(lease, configuration: selected)
            try platform.setActive(true, options: [])
            stateStorage = .active
        } catch let error as AudioSessionCoordinatorError {
            if error == .configurationFailed {
                throw error
            }
            clearLease(bestEffortDeactivate: true)
            throw AudioSessionCoordinatorError.activationFailed
        } catch {
            clearLease(bestEffortDeactivate: true)
            throw AudioSessionCoordinatorError.activationFailed
        }
    }

    func activate(_ lease: AudioSessionLease) throws {
        try activate(lease, configuration: nil)
    }

    /// A matching inactive lease can be deactivated idempotently. Stale
    /// leases never touch the platform and therefore cannot mute a replacement.
    func deactivate(_ lease: AudioSessionLease) throws {
        guard lease.isValid else { throw AudioSessionCoordinatorError.invalidLease }
        guard let currentLease = leaseStorage else {
            if lastReleasedLease == lease { return }
            throw AudioSessionCoordinatorError.staleLease
        }
        guard currentLease == lease else {
            throw AudioSessionCoordinatorError.staleLease
        }
        var failure = false
        if stateStorage == .active || configurationStorage != nil {
            do {
                try platform.setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                failure = true
            }
        }
        lastReleasedLease = lease
        leaseStorage = nil
        configurationStorage = nil
        stateStorage = .inactive
        if failure {
            throw AudioSessionCoordinatorError.deactivationFailed
        }
    }

    func release(_ lease: AudioSessionLease) throws {
        try deactivate(lease)
    }

    func handleInterruptionBegan() -> AudioSessionInterruption {
        guard leaseStorage != nil else { return .began }
        stateStorage = .interrupted
        return .began
    }

    @discardableResult
    func handleInterruptionEnded(shouldResume: Bool) -> AudioSessionInterruption {
        guard stateStorage == .interrupted else {
            return .ended(shouldResume: shouldResume)
        }
        // Deliberately inactive: shouldResume is reported, never acted upon.
        stateStorage = .inactive
        return .ended(shouldResume: shouldResume)
    }

    @discardableResult
    func handleRouteChange(reason: AudioSessionRouteChangeReason) -> AudioSessionRouteChangeReason {
        reason
    }

    func handleMediaServicesWereReset() {
        clearLease(bestEffortDeactivate: true)
        generationStorage = nextGeneration(generationStorage)
    }

    func handle(_ event: AudioSessionEvent) {
        switch event {
        case .interruptionBegan:
            _ = handleInterruptionBegan()
        case .interruptionEnded(let shouldResume):
            _ = handleInterruptionEnded(shouldResume: shouldResume)
        case .routeChanged(let reason):
            _ = handleRouteChange(reason: reason)
        case .mediaServicesWereReset:
            handleMediaServicesWereReset()
        }
    }

    private func validate(_ lease: AudioSessionLease) throws {
        guard lease.isValid else { throw AudioSessionCoordinatorError.invalidLease }
        guard leaseStorage == lease else {
            throw AudioSessionCoordinatorError.staleLease
        }
    }

    private func clearLease(bestEffortDeactivate: Bool) {
        if bestEffortDeactivate,
           stateStorage == .active || configurationStorage != nil {
            try? platform.setActive(false, options: .notifyOthersOnDeactivation)
        }
        leaseStorage = nil
        configurationStorage = nil
        stateStorage = .inactive
    }

    private func nextGeneration(_ value: UInt64) -> UInt64 {
        let next = value &+ 1
        return next == 0 ? 1 : next
    }

    private func installNotificationObservers() {
        let center = NotificationCenter.default
        notificationTokens.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                    ?? AVAudioSession.InterruptionType.ended.rawValue
                let shouldResume = ((notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                    ?? 0) & AVAudioSession.InterruptionOptions.shouldResume.rawValue != 0
                Task {
                    if type == AVAudioSession.InterruptionType.began.rawValue {
                        await self?.handle(.interruptionBegan)
                    } else {
                        await self?.handle(.interruptionEnded(shouldResume: shouldResume))
                    }
                }
            }
        )
        notificationTokens.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                let rawReason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
                Task {
                    await self?.handle(.routeChanged(AudioSessionRouteChangeReason(rawValue: rawReason)))
                }
            }
        )
        notificationTokens.append(
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { await self?.handle(.mediaServicesWereReset) }
            }
        )
    }
}
