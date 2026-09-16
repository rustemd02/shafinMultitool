//
//  SceneRemoteServiceCompositionTests.swift
//  shafinMultitool
//
//  Deployment composition contract: no remote provider without an explicit,
//  validated endpoint and an authenticated token source.
//

import XCTest
@testable import shafinMultitool

private final class CompositionFakePerformer: AppAttestDevicePerforming, @unchecked Sendable {
    var isSupported = true
    func generateKey() async throws -> String { Data(repeating: 1, count: 32).base64EncodedString() }
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data { Data(repeating: 2, count: 64) }
}

private struct CompositionFakeTokenProvider: SceneServiceTokenProviding {
    let token: String?
    func currentServiceToken() async -> String? { token }
}

final class SceneRemoteServiceCompositionTests: XCTestCase {

    private let liveURL = "https://scene.example.com"

    private func configuration(baseURL: String) -> SceneGenerationClientConfiguration {
        var configuration = SceneGenerationClientConfiguration.placeholder
        configuration.baseURL = URL(string: baseURL)!
        return configuration
    }

    func testNoConfigurationMeansNoRemoteProvider() {
        let provider = SceneRemoteServiceComposition.makeRemoteProvider(
            environment: [:],
            performer: CompositionFakePerformer(),
            tokenProviderOverride: CompositionFakeTokenProvider(token: "t")
        )
        XCTAssertNil(provider, "the app must stay local-only without an explicit endpoint")
    }

    func testPlaceholderAndInsecureEndpointsAreRejected() {
        let performer = CompositionFakePerformer()
        let override = CompositionFakeTokenProvider(token: "t")
        for candidate in [
            SceneAPIVersion.placeholderHost,
            "http://scene.example.com",
            "https://",
            "https://user:pass@scene.example.com",
            "https://scene.example.com?debug=1",
        ] {
            let provider = SceneRemoteServiceComposition.makeRemoteProvider(
                environment: [SceneRemoteServiceComposition.baseURLEnvironmentKey: candidate],
                performer: performer,
                tokenProviderOverride: override
            )
            XCTAssertNil(provider, "endpoint \(candidate) must not compose a remote provider")
        }
    }

    func testEnvironmentOptInComposesProviderWithValidatedEndpoint() {
        let provider = SceneRemoteServiceComposition.makeRemoteProvider(
            environment: [SceneRemoteServiceComposition.baseURLEnvironmentKey: liveURL],
            performer: CompositionFakePerformer(),
            tokenProviderOverride: CompositionFakeTokenProvider(token: "t")
        )
        XCTAssertNotNil(provider)
    }

    func testUnsupportedAppAttestWithoutOverrideStaysLocal() {
        let performer = CompositionFakePerformer()
        performer.isSupported = false
        let provider = SceneRemoteServiceComposition.makeRemoteProvider(
            environment: [SceneRemoteServiceComposition.baseURLEnvironmentKey: liveURL],
            performer: performer
        )
        XCTAssertNil(provider, "a device that cannot attest must not compose an authenticated client")
    }

    func testExplicitConfigurationOverridesEnvironment() {
        let provider = SceneRemoteServiceComposition.makeRemoteProvider(
            environment: [SceneRemoteServiceComposition.baseURLEnvironmentKey: "https://env.example.com"],
            configuration: configuration(baseURL: liveURL),
            performer: CompositionFakePerformer(),
            tokenProviderOverride: CompositionFakeTokenProvider(token: "t")
        )
        XCTAssertNotNil(provider)

        let rejected = SceneRemoteServiceComposition.makeRemoteProvider(
            environment: [SceneRemoteServiceComposition.baseURLEnvironmentKey: liveURL],
            configuration: configuration(baseURL: "http://insecure.example.com"),
            performer: CompositionFakePerformer(),
            tokenProviderOverride: CompositionFakeTokenProvider(token: "t")
        )
        XCTAssertNil(rejected, "explicit configuration must still pass endpoint validation")
    }

    func testBootstrapStaysOffWithoutConfigurationAndOnUnsupportedDevices() {
        // empty environment: nothing configured, the service is left untouched
        XCTAssertFalse(SceneRemoteServiceBootstrap.configureIfEnabled(environment: [:]))
        XCTAssertFalse(SceneParserService.shared.isRemoteOffloadConfigured)

        // configured endpoint but a device that cannot attest: still local-only
        let unsupported = CompositionFakePerformer()
        unsupported.isSupported = false
        XCTAssertFalse(
            SceneRemoteServiceBootstrap.configureIfEnabled(
                environment: [SceneRemoteServiceComposition.baseURLEnvironmentKey: liveURL],
                performer: unsupported
            )
        )
        XCTAssertFalse(SceneParserService.shared.isRemoteOffloadConfigured)
    }

    func testBootstrapWiresTheSharedServiceWhenEnabled() {
        XCTAssertTrue(
            SceneRemoteServiceBootstrap.configureIfEnabled(
                environment: [SceneRemoteServiceComposition.baseURLEnvironmentKey: liveURL],
                performer: CompositionFakePerformer(),
                tokenProviderOverride: CompositionFakeTokenProvider(token: "t")
            )
        )
        XCTAssertTrue(SceneParserService.shared.isRemoteOffloadConfigured)
        // restore the default local-only disposition for other tests
        SceneParserService.shared.configureRemoteOffload(enabled: false, provider: nil)
        XCTAssertFalse(SceneParserService.shared.isRemoteOffloadConfigured)
    }

    func testEnvironmentConfigurationParsing() {
        XCTAssertNil(SceneRemoteServiceComposition.configurationFromEnvironment([:]))
        XCTAssertNil(SceneRemoteServiceComposition.configurationFromEnvironment(
            [SceneRemoteServiceComposition.baseURLEnvironmentKey: "   "]
        ))
        let parsed = SceneRemoteServiceComposition.configurationFromEnvironment(
            [SceneRemoteServiceComposition.baseURLEnvironmentKey: " https://scene.example.com "]
        )
        XCTAssertEqual(parsed?.baseURL.absoluteString, liveURL)
    }
}
