import UIKit

/// M7-015 background policy seam. UIKit's `UIApplication.beginBackgroundTask`
/// cannot be faked directly, so the shell talks to this narrow coordinator
/// and lifecycle tests inject a deterministic fake.
protocol SceneBackgroundTaskCoordinating: AnyObject {
    func begin(withName name: String) -> UIBackgroundTaskIdentifier
    func end(_ identifier: UIBackgroundTaskIdentifier)
}

/// Production coordinator. UIKit calls the expiration handler shortly before
/// the lease is revoked; ending it there keeps the lease bookkeeping honest.
/// The recording finalize itself runs on the serialized owners, which are
/// idempotent, so an expired lease can never produce a second finalize or a
/// hidden second clip.
final class UIKitSceneBackgroundTaskCoordinator: SceneBackgroundTaskCoordinating {
    private var liveIdentifier: UIBackgroundTaskIdentifier = .invalid

    func begin(withName name: String) -> UIBackgroundTaskIdentifier {
        let identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // UIKit invokes this shortly before revoking the lease; end the
            // currently live identifier exactly once.
            guard let self, self.liveIdentifier != .invalid else { return }
            let current = self.liveIdentifier
            self.liveIdentifier = .invalid
            UIApplication.shared.endBackgroundTask(current)
        }
        liveIdentifier = identifier
        return identifier
    }

    func end(_ identifier: UIBackgroundTaskIdentifier) {
        guard identifier != .invalid, liveIdentifier == identifier else { return }
        liveIdentifier = .invalid
        UIApplication.shared.endBackgroundTask(identifier)
    }
}
