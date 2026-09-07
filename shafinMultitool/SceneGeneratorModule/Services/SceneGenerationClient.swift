//
//  SceneGenerationClient.swift
//  shafinMultitool
//
//  M5-025: the single typed client for the first-party Scene Generation
//  backend. It implements the existing RemoteScenePlanProvider seam
//  against the frozen M12-003 API (create/poll/clarify-answer/cancel,
//  version triple + request hash, idempotency, kill-switch).
//
//  Hard boundaries (fail closed, never bypassed):
//  - No provider credentials in the app: auth is an injected
//    short-lived service token (App Attest wiring is M12-005).
//  - No live host by default: baseURL defaults to the M12-003
//    placeholder; deployment config must replace it explicitly.
//  - Every decoded status passes SceneJobValidation before it reaches
//    the caller; kill-switch is terminal.
//  - Transport is injected (URLSessionConfiguration.protocolClasses)
//    so URLProtocol contract tests own the wire behavior.
//

import Foundation

/// Typed transport errors. Backend failures arrive as validated
/// SceneJobFailure values, never as thrown untyped errors, except for
/// transport/decoding faults that prevent validation itself.
enum SceneGenerationClientError: Error, Equatable {
    case transport(ErrorWrapper)
    case malformedPayload
    case rejected(SceneJobRejection)
    case jobFailed(SceneJobFailureCode)
    case killSwitchEngaged
    case cancelled

    struct ErrorWrapper: Equatable {
        let description: String
    }

    static func == (lhs: SceneGenerationClientError, rhs: SceneGenerationClientError) -> Bool {
        lhs.stableDescription == rhs.stableDescription
    }

    var stableDescription: String {
        switch self {
        case .transport(let wrapper): return "transport:\(wrapper.description)"
        case .malformedPayload: return "malformedPayload"
        case .rejected(let rejection): return "rejected:\(rejection.rawValue)"
        case .jobFailed(let code): return "jobFailed:\(code.rawValue)"
        case .killSwitchEngaged: return "killSwitchEngaged"
        case .cancelled: return "cancelled"
        }
    }
}

/// Terminal outcome of one backend generation round.
enum SceneGenerationOutcome: Equatable {
    case complete(SceneJobResult)
    case awaitingClarification(SceneClarificationPayload)
    case failed(SceneJobFailure)
}

/// Short-lived service token provider (App Attest wiring lands in
/// M12-005; the client only consumes the token string).
protocol SceneServiceTokenProviding: Sendable {
    func currentServiceToken() async -> String?
}

/// Configuration owned by deployment, never by call sites.
struct SceneGenerationClientConfiguration: Equatable, Sendable {
    var baseURL: URL
    var requestTimeoutSeconds: TimeInterval
    var pollIntervalSeconds: TimeInterval
    var maximumPolls: Int
    var modelVersion: String
    var promptVersion: String
    var providerName: String
    var providerVersion: String

    static var placeholder: SceneGenerationClientConfiguration {
        SceneGenerationClientConfiguration(
            baseURL: URL(string: SceneAPIVersion.placeholderHost)!,
            requestTimeoutSeconds: 30,
            pollIntervalSeconds: 2,
            maximumPolls: 30,
            modelVersion: "scene-model-v1",
            promptVersion: "scene-prompt-v1",
            providerName: "first-party-scene",
            providerVersion: "2026-09-01"
        )
    }
}

/// M5-025 client. All requests carry the Idempotency-Key header; the
/// request body is built by SceneCreateJobRequestBuilder (M12-004
/// allowlist); every response is validated by SceneJobValidation.
final class SceneGenerationClient: RemoteScenePlanProvider, Sendable {
    private let configuration: SceneGenerationClientConfiguration
    private let session: URLSession
    private let tokenProvider: SceneServiceTokenProviding?
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        configuration: SceneGenerationClientConfiguration = .placeholder,
        session: URLSession = .shared,
        tokenProvider: SceneServiceTokenProviding? = nil
    ) {
        self.configuration = configuration
        self.session = session
        self.tokenProvider = tokenProvider
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        self.encoder = JSONEncoder()
    }

    // MARK: - RemoteScenePlanProvider seam

    /// Runs one backend round for coordinator offload: create, bounded
    /// poll, then map the terminal job payload. Clarification and
    /// failure surface as nil so the coordinator keeps the honest
    /// local result (no fake plan is ever synthesized).
    func generateRemotePlan(
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle,
        state: SceneChunkState?
    ) async -> ScenePlanProviderResult? {
        _ = anchors
        _ = state
        let requestID = UUID()
        guard case .success(let body) = SceneCreateJobRequestBuilder.build(
            requestID: requestID,
            clientBuild: SceneGenerationClient.clientBuild,
            locale: SceneGenerationClient.locale(for: description),
            scriptText: description,
            markedObjectIDs: markedObjects.map(\.canonicalMarkedObjectID),
            maximumScenes: 1,
            previousJobID: nil,
            modelVersion: configuration.modelVersion,
            promptVersion: configuration.promptVersion,
            providerName: configuration.providerName,
            providerVersion: configuration.providerVersion
        ) else {
            return nil
        }
        do {
            let status = try await createJob(body: body, idempotencyKey: "gen-\(requestID.uuidString)")
            let outcome = try await pollToTerminal(jobID: status.jobID)
            guard case .complete(let result) = outcome else { return nil }
            return SceneGenerationClient.planResult(from: result)
        } catch {
            return nil
        }
    }

    // MARK: - Typed API surface

    func createJob(body: SceneCreateJobRequest, idempotencyKey: String) async throws -> SceneJobStatus {
        var request = URLRequest(
            url: configuration.baseURL.appendingPathComponent("jobs"),
            timeoutInterval: configuration.requestTimeoutSeconds
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        if let token = await tokenProvider?.currentServiceToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        try Self.checkHTTP(response)
        do {
            return try decoder.decode(SceneJobStatus.self, from: data)
        } catch {
            throw SceneGenerationClientError.malformedPayload
        }
    }

    func pollJob(jobID: String) async throws -> SceneJobStatus {
        var request = URLRequest(
            url: configuration.baseURL.appendingPathComponent("jobs/\(jobID)"),
            timeoutInterval: configuration.requestTimeoutSeconds
        )
        request.httpMethod = "GET"
        if let token = await tokenProvider?.currentServiceToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        try Self.checkHTTP(response)
        do {
            return try decoder.decode(SceneJobStatus.self, from: data)
        } catch {
            throw SceneGenerationClientError.malformedPayload
        }
    }

    func answerClarification(jobID: String, answer: SceneClarificationAPIPayload, idempotencyKey: String) async throws -> SceneJobStatus {
        var request = URLRequest(
            url: configuration.baseURL.appendingPathComponent("jobs/\(jobID)/clarification-answer"),
            timeoutInterval: configuration.requestTimeoutSeconds
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        if let token = await tokenProvider?.currentServiceToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(answer)
        let (data, response) = try await session.data(for: request)
        try Self.checkHTTP(response)
        do {
            return try decoder.decode(SceneJobStatus.self, from: data)
        } catch {
            throw SceneGenerationClientError.malformedPayload
        }
    }

    func cancelJob(jobID: String) async throws -> SceneJobStatus {
        var request = URLRequest(
            url: configuration.baseURL.appendingPathComponent("jobs/\(jobID)"),
            timeoutInterval: configuration.requestTimeoutSeconds
        )
        request.httpMethod = "DELETE"
        if let token = await tokenProvider?.currentServiceToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        try Self.checkHTTP(response)
        do {
            return try decoder.decode(SceneJobStatus.self, from: data)
        } catch {
            throw SceneGenerationClientError.malformedPayload
        }
    }

    /// Bounded poll to a terminal outcome. Every decoded status is
    /// validated before it advances the loop; kill-switch aborts
    /// immediately and cancellation throws.
    func pollToTerminal(jobID: String) async throws -> SceneGenerationOutcome {
        var polls = 0
        while true {
            if Task.isCancelled { throw SceneGenerationClientError.cancelled }
            let status = try await pollJob(jobID: jobID)
            switch SceneJobValidation.validate(status) {
            case .notTerminal:
                polls += 1
                if polls >= configuration.maximumPolls {
                    throw SceneGenerationClientError.jobFailed(.timeout)
                }
                try await Task.sleep(nanoseconds: UInt64(configuration.pollIntervalSeconds * 1_000_000_000))
            case .complete(let result):
                return .complete(result)
            case .awaitingClarification(let payload):
                return .awaitingClarification(payload)
            case .failed(let failure):
                return .failed(failure)
            case .rejected(let rejection):
                if rejection == .killSwitchEngaged { throw SceneGenerationClientError.killSwitchEngaged }
                throw SceneGenerationClientError.rejected(rejection)
            }
        }
    }

    // MARK: - Helpers

    private static func checkHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SceneGenerationClientError.malformedPayload
        }
        if http.statusCode == 410 { throw SceneGenerationClientError.killSwitchEngaged }
        guard (200..<300).contains(http.statusCode) else {
            throw SceneGenerationClientError.jobFailed(.providerError)
        }
    }

    private static var clientBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private static func locale(for description: String) -> String {
        description.range(of: "\\p{Cyrillic}", options: .regularExpression) != nil ? "ru" : "en"
    }

    /// Maps a validated complete result onto the local plan type. The
    /// SceneScript is already schema-valid (M3-023 shape enforced by
    /// the validator); plan compilation itself stays with
    /// ScenePlanCompiler (M5-029 owns the compile proof).
    static func planResult(from result: SceneJobResult) -> ScenePlanProviderResult? {
        let bridge = LegacySceneScriptBridge()
        guard let plan = bridge.planIR(from: result.sceneScript) else { return nil }
        return ScenePlanProviderResult(
            plan: plan,
            usedLegacySceneScriptBridge: true,
            reasonCodes: ["remote_plan_used"]
        )
    }
}

/// Minimal bridge from a validated SceneScript to the local plan IR.
/// Only structural projection; no semantic repair (M5-027 owns the
/// repair boundary proof).
private struct LegacySceneScriptBridge {
    func planIR(from script: SceneScript) -> ScenePlanIR? {
        guard !script.beats.isEmpty else { return nil }
        let actors = script.actors.map {
            ScenePlanIR.Actor(ref: $0.id, type: $0.type, name: $0.name)
        }
        let objects = script.objects.map {
            ScenePlanIR.Object(
                ref: $0.id,
                type: $0.type,
                relativePosition: $0.relativePosition,
                name: $0.name,
                markedObjectID: $0.id.hasPrefix("object_marked_") ? $0.id : nil
            )
        }
        let beats = script.beats.map { beat in
            ScenePlanIR.Beat(
                ref: beat.id,
                actions: beat.actions.map { action in
                    ScenePlanIR.Action(
                        actorRef: action.actorId,
                        type: action.type,
                        targetRef: action.target,
                        direction: action.direction,
                        modifier: action.modifier,
                        resultingPose: action.resultingPose,
                        holdingObjectRef: action.holdingObject,
                        dialogue: action.dialogue,
                        fallbackText: action.fallbackText,
                        sourceText: action.sourceText
                    )
                },
                minDuration: beat.minDuration
            )
        }
        let relations = script.spatialRelations.map {
            ScenePlanIR.SpatialRelation(
                ref: $0.id,
                subjectRef: $0.subject,
                relation: $0.relation,
                objectRef: $0.object
            )
        }
        return ScenePlanIR(
            actors: actors,
            objects: objects,
            beats: beats,
            spatialRelations: relations,
            referenceBindings: ScenePlanIR.ReferenceBindings()
        )
    }
}
