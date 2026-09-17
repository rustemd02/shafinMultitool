import Foundation

/// Inert application composition. It stores no approval and performs no request.
enum CameraCloudServiceBootstrap {
    private static let storage = Storage()

    static var client: CameraCloudAnalyzing? { storage.read() }

    static func clear() { storage.replace(nil) }

    static func configure(sceneClient: SceneGenerationClient, bundleInfo: [String: Any]) {
        guard let rawRoot = bundleInfo["SETOSSceneBaseURL"] as? String,
              var root = URL(string: rawRoot),
              SceneGenerationClient.isValidEndpoint(root) else {
            clear()
            return
        }
        if root.lastPathComponent != "v1" { root.appendPathComponent("v1") }
        guard let policy = CameraCloudTransferPolicy.fromPublicConfiguration(bundleInfo, endpoint: root) else {
            clear()
            return
        }
        storage.replace(sceneClient.makeCameraCloudClient(policy: policy))
    }

    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var value: CameraCloudAnalyzing?

        func read() -> CameraCloudAnalyzing? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func replace(_ client: CameraCloudAnalyzing?) {
            lock.lock()
            value = client
            lock.unlock()
        }
    }
}

