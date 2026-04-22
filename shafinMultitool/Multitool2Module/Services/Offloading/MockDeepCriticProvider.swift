import Foundation

actor MockDeepCriticProvider: DeepCriticProvider {
    typealias ReviewHandler = (DeepCriticTransportEnvelope) async throws -> DeepCriticResponse

    nonisolated let providerId: String
    nonisolated let capabilities: DeepCriticCapabilities

    private let reviewHandler: ReviewHandler
    private(set) var reviewCallCount = 0
    private(set) var lastRequest: DeepCriticTransportEnvelope?

    init(providerId: String = "mock_deep_critic_v1",
         capabilities: DeepCriticCapabilities = DeepCriticCapabilities(
            supportsStructuredOnly: true,
            supportsRedactedVisual: true,
            supportsRussian: true,
            maxRequestBytes: 2_000_000,
            maxResponseBytes: 250_000,
            allowsTeacherEvidence: true
         ),
         review: @escaping ReviewHandler) {
        self.providerId = providerId
        self.capabilities = capabilities
        self.reviewHandler = review
    }

    func review(request: DeepCriticTransportEnvelope) async throws -> DeepCriticResponse {
        reviewCallCount += 1
        lastRequest = request
        return try await reviewHandler(request)
    }
}
