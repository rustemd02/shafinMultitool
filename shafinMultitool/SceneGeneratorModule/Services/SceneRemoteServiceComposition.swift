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

import Foundation

enum SceneRemoteServiceComposition {

    /// Environment key a deployment may set to opt in. Absent by default.
    static let baseURLEnvironmentKey = "SETOS_SCENE_BASE_URL"

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
        configuration: SceneGenerationClientConfiguration? = nil,
        performer: AppAttestDevicePerforming = SystemAppAttestDevicePerformer(),
        transportFactory: (URL) -> AppAttestEnrollmentTransport = { URLSessionAppAttestEnrollmentTransport(baseURL: $0) },
        secrets: AppAttestSecretStoring = KeychainAppAttestSecretStore(),
        session: URLSession = .shared,
        tokenProviderOverride: SceneServiceTokenProviding? = nil
    ) -> SceneGenerationClient? {
        let resolved = configuration ?? configurationFromEnvironment(environment)
        guard let resolved else { return nil }
        guard SceneGenerationClient.isValidEndpoint(resolved.baseURL) else { return nil }

        let tokenProvider: SceneServiceTokenProviding
        if let tokenProviderOverride {
            tokenProvider = tokenProviderOverride
        } else {
            guard performer.isSupported else { return nil }
            tokenProvider = AppAttestServiceTokenProvider(
                performer: performer,
                transport: transportFactory(resolved.baseURL),
                secrets: secrets
            )
        }

        return SceneGenerationClient(
            configuration: resolved,
            session: session,
            tokenProvider: tokenProvider
        )
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
}

/// Opt-in runtime bootstrap. Touches the shared parser service only when the
/// deployment actually enabled a remote provider, so the default launch path
/// keeps its existing local-only behavior and startup cost.
enum SceneRemoteServiceBootstrap {
    @discardableResult
    static func configureIfEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        performer: AppAttestDevicePerforming = SystemAppAttestDevicePerformer(),
        tokenProviderOverride: SceneServiceTokenProviding? = nil
    ) -> Bool {
        guard let provider = SceneRemoteServiceComposition.makeRemoteProvider(
            environment: environment,
            performer: performer,
            tokenProviderOverride: tokenProviderOverride
        ) else {
            return false
        }
        SceneParserService.shared.configureRemoteOffload(enabled: true, provider: provider)
        return true
    }
}
