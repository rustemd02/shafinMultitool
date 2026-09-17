import UIKit

/// One lease per background dispatch; all callbacks use the originating lease.
@MainActor
protocol SceneBackgroundTaskCoordinating: AnyObject {
    func begin(withName name: String) -> UIBackgroundTaskIdentifier
    func end(_ identifier: UIBackgroundTaskIdentifier)
}

/// Tests exercise the production lease owner while replacing only UIKit calls.
@MainActor
protocol SceneBackgroundTaskPlatform: AnyObject {
    func begin(withName name: String, expirationHandler: @escaping () -> Void) -> UIBackgroundTaskIdentifier
    func end(_ identifier: UIBackgroundTaskIdentifier)
}

@MainActor
private final class UIApplicationBackgroundTaskPlatform: SceneBackgroundTaskPlatform {
    func begin(withName name: String, expirationHandler: @escaping () -> Void) -> UIBackgroundTaskIdentifier {
        UIApplication.shared.beginBackgroundTask(withName: name, expirationHandler: expirationHandler)
    }

    func end(_ identifier: UIBackgroundTaskIdentifier) {
        UIApplication.shared.endBackgroundTask(identifier)
    }
}

@MainActor
final class UIKitSceneBackgroundTaskCoordinator: SceneBackgroundTaskCoordinating {
    private final class Lease {
        let key = UUID()
        var identifier: UIBackgroundTaskIdentifier = .invalid
        var ended = false
    }

    private let platform: any SceneBackgroundTaskPlatform
    private var leases: [UUID: Lease] = [:]

    init(platform: any SceneBackgroundTaskPlatform) {
        self.platform = platform
    }

    convenience init() {
        self.init(platform: UIApplicationBackgroundTaskPlatform())
    }

    func begin(withName name: String) -> UIBackgroundTaskIdentifier {
        let lease = Lease()
        leases[lease.key] = lease
        let identifier = platform.begin(withName: name) { [weak self, weak lease] in
            guard let self, let lease else { return }
            self.finish(lease)
        }
        lease.identifier = identifier
        if identifier == .invalid {
            lease.ended = true
            leases.removeValue(forKey: lease.key)
        } else if lease.ended {
            // Also handle a platform expiration delivered before begin returns.
            platform.end(identifier)
        }
        return identifier
    }

    func end(_ identifier: UIBackgroundTaskIdentifier) {
        guard identifier != .invalid,
              let lease = leases.values.first(where: { $0.identifier == identifier }) else { return }
        finish(lease)
    }

    private func finish(_ lease: Lease) {
        guard !lease.ended else { return }
        lease.ended = true
        leases.removeValue(forKey: lease.key)
        guard lease.identifier != .invalid else { return }
        platform.end(lease.identifier)
    }
}
