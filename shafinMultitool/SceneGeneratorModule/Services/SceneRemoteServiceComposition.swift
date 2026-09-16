//
//  SceneRemoteServiceComposition.swift
//  shafinMultitool
//
//  Deployment-side composition for the remote Scene provider.
//
//  Fail-closed: returns nil unless a real, validated https endpoint is
//  configured AND the device can obtain an authenticated service token
//  (App Attest supported). With no configuration the app keeps its existing
//  local-only behavior — no live host is ever guessed.
//

import CryptoKit
import Foundation

enum SceneRemoteServiceComposition {

    /// Environment key a deployment may set to opt in. Absent by default.
    static let baseURLEnvironmentKey = "SETOS_SCENE_BASE_URL"
    static let baseURLInfoKey = "SETOSSceneBaseURL"

    /// Builds the remote provider, or nil when the deployment is not
    /// configured or the device cannot authenticate.
    ///
    /// - Parameters:
    ///   - environment: deployment environment (injectable for tests).
    ///   - configuration: explicit configuration; overrides the environment.
    ///   - performer: App Attest device seam.
    ///   - transportFactory: enrollment transport seam.
    ///   - secrets: token/key storage seam.
    ///   - session: URLSession used by the Scene client.
    ///   - tokenProviderOverride: test seam; when provided, no App Attest
    ///     provider is constructed.
    static func makeRemoteProvider(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleInfo: [String: Any] = Bundle.main.infoDictionary ?? [:],
        configuration: SceneGenerationClientConfiguration? = nil,
        performer: AppAttestDevicePerforming = SystemAppAttestDevicePerformer(),
        transportFactory: ((URL) -> AppAttestEnrollmentTransport)? = nil,
        secrets: AppAttestSecretStoring? = nil,
        session: URLSession = .shared,
        tokenProviderOverride: SceneServiceTokenProviding? = nil
    ) -> SceneGenerationClient? {
        let resolved = configuration ?? configurationFromEnvironment(environment) ?? configurationFromBundle(bundleInfo)
        guard var resolved else { return nil }
        guard SceneGenerationClient.isValidEndpoint(resolved.baseURL) else { return nil }
        // One API root is shared by jobs and enrollment. Accept a deployment
        // origin as convenience, while preserving an explicit proxy prefix.
        if resolved.baseURL.lastPathComponent != "v1" {
            resolved.baseURL.appendPathComponent("v1")
        }

        // Public disclosure is bound to the actual normalized deployment
        // endpoint and provider identity. Missing values stay absent; creating
        // the inert client is allowed, but its transfer entry fails closed.
        if resolved.transferPolicy == nil {
            resolved.transferPolicy = SceneRemoteTransferPolicy.fromPublicConfiguration(
                bundleInfo, endpoint: resolved.baseURL,
                providerName: resolved.providerName, providerVersion: resolved.providerVersion
            )
        }

        let tokenProvider: SceneServiceTokenProviding
        if let tokenProviderOverride {
            tokenProvider = tokenProviderOverride
        } else {
            guard performer.isSupported else { return nil }
            tokenProvider = AppAttestServiceTokenProvider(
                performer: performer,
                transport: transportFactory?(resolved.baseURL)
                    ?? URLSessionAppAttestEnrollmentTransport(baseURL: resolved.baseURL, session: session),
                secrets: secrets ?? KeychainAppAttestSecretStore(
                    service: credentialNamespace(for: resolved.baseURL)
                )
            )
        }

        return SceneGenerationClient(
            configuration: resolved,
            session: session,
            tokenProvider: tokenProvider
        )
    }

    static func credentialNamespace(for baseURL: URL) -> String {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.port == 443 { components.port = nil }
        while components.path.hasSuffix("/") { components.path.removeLast() }
        let digest = SHA256.hash(data: Data(components.string!.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return "com.vigvamcev-media.shafinMultitool.appattest.\(digest)"
    }

    /// Reads the opt-in base URL from the environment, keeping every other
    /// client field at its deployment placeholder default.
    static func configurationFromEnvironment(
        _ environment: [String: String]
    ) -> SceneGenerationClientConfiguration? {
        guard let rawURL = environment[baseURLEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawURL.isEmpty,
              let url = URL(string: rawURL) else {
            return nil
        }
        var configuration = SceneGenerationClientConfiguration.placeholder
        configuration.baseURL = url
        return configuration
    }

    /// Archive configuration is carried by the built application; launching
    /// a Release build does not require development environment variables.
    static func configurationFromBundle(_ info: [String: Any]) -> SceneGenerationClientConfiguration? {
        guard let rawURL = info[baseURLInfoKey] as? String,
              let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              SceneGenerationClient.isValidEndpoint(url) else { return nil }
        var configuration = SceneGenerationClientConfiguration.placeholder
        configuration.baseURL = url
        let versionFields: [(String, WritableKeyPath<SceneGenerationClientConfiguration, String>)] = [
            ("SETOSSceneModelVersion", \SceneGenerationClientConfiguration.modelVersion),
            ("SETOSScenePromptVersion", \SceneGenerationClientConfiguration.promptVersion),
            ("SETOSSceneProviderName", \SceneGenerationClientConfiguration.providerName),
            ("SETOSSceneProviderVersion", \SceneGenerationClientConfiguration.providerVersion)
        ]
        for (key, path) in versionFields {
            if let value = info[key] as? String {
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty, !normalized.contains("$(") else { return nil }
                configuration[keyPath: path] = normalized
            }
        }
        return configuration
    }
}

/// Opt-in runtime bootstrap. Touches the shared parser service only when the
/// deployment actually enabled a remote provider, so the default launch path
/// keeps its existing local-only behavior and startup cost.
enum SceneRemoteServiceBootstrap {
    @discardableResult
    static func configureIfEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleInfo: [String: Any] = Bundle.main.infoDictionary ?? [:],
        performer: AppAttestDevicePerforming = SystemAppAttestDevicePerformer(),
        tokenProviderOverride: SceneServiceTokenProviding? = nil
    ) -> Bool {
        guard let provider = SceneRemoteServiceComposition.makeRemoteProvider(
            environment: environment,
            bundleInfo: bundleInfo,
            performer: performer,
            tokenProviderOverride: tokenProviderOverride
        ) else {
            return false
        }
        SceneParserService.shared.configureRemoteOffload(enabled: true, provider: provider)
        return true
    }
}
