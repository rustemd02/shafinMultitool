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
    case invalidEndpoint
    case missingServiceToken
    case invalidServiceToken
    case invalidJobID
    case invalidIdempotencyKey
    case responseBindingMismatch
    case transport(ErrorWrapper)
    case malformedPayload
    case rejected(SceneJobRejection)
    case jobFailed(SceneJobFailureCode)
    case quotaExceeded(retryAfterSeconds: Int?)
    case killSwitchEngaged
    case contentExpired
    case unexpectedGoneResponse
    case cancelled

    struct ErrorWrapper: Equatable {
        let description: String
    }

    static func == (lhs: SceneGenerationClientError, rhs: SceneGenerationClientError) -> Bool {
        lhs.stableDescription == rhs.stableDescription
    }

    var stableDescription: String {
        switch self {
        case .invalidEndpoint: return "invalidEndpoint"
        case .missingServiceToken: return "missingServiceToken"
        case .invalidServiceToken: return "invalidServiceToken"
        case .invalidJobID: return "invalidJobID"
        case .invalidIdempotencyKey: return "invalidIdempotencyKey"
        case .responseBindingMismatch: return "responseBindingMismatch"
        case .transport(let wrapper): return "transport:\(wrapper.description)"
        case .malformedPayload: return "malformedPayload"
        case .rejected(let rejection): return "rejected:\(rejection.rawValue)"
        case .jobFailed(let code): return "jobFailed:\(code.rawValue)"
        case .quotaExceeded(let seconds): return "quotaExceeded:\(seconds.map { String($0) } ?? "unknown")"
        case .killSwitchEngaged: return "killSwitchEngaged"
        case .contentExpired: return "contentExpired"
        case .unexpectedGoneResponse: return "unexpectedGoneResponse"
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
    func replacementServiceToken(afterRejecting token: String) async -> String?
}

extension SceneServiceTokenProviding {
    /// Providers without a renewal protocol must not replay an unauthorized
    /// request using the same credential or invent a new installation.
    func replacementServiceToken(afterRejecting token: String) async -> String? { nil }
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
    var transferPolicy: SceneRemoteTransferPolicy? = nil

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

    /// Noninteractive callers cannot answer a question on the user's behalf.
    func generateRemotePlan(
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle,
        state: SceneChunkState?
    ) async -> ScenePlanProviderResult? {
        await generateRemotePlan(
            description: description,
            markedObjects: markedObjects,
            anchors: anchors,
            state: state,
            clarificationHandler: nil
        )
    }

    /// Creates one job and resumes that exact job only after an explicit
    /// answer. There is no paid create retry and no inferred first option.
    func generateRemotePlan(
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle,
        state: SceneChunkState?,
        clarificationHandler: SceneRemoteClarificationHandler?
    ) async -> ScenePlanProviderResult? {
        guard case .plan(let result) = await generateRemotePlanOutcome(
            description: description, markedObjects: markedObjects,
            anchors: anchors, state: state, clarificationHandler: clarificationHandler
        ) else { return nil }
        return result
    }

    func generateRemotePlanOutcome(
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle,
        state: SceneChunkState?,
        clarificationHandler: SceneRemoteClarificationHandler?
    ) async -> SceneRemotePlanOutcome {
        await generateRemotePlanOutcome(
            description: description, markedObjects: markedObjects, anchors: anchors,
            state: state, clarificationHandler: clarificationHandler, transferConsentHandler: nil
        )
    }

    func generateRemotePlanOutcome(
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle,
        state: SceneChunkState?,
        clarificationHandler: SceneRemoteClarificationHandler?,
        transferConsentHandler: SceneRemoteTransferConsentHandler?
    ) async -> SceneRemotePlanOutcome {
        _ = state
        guard !Task.isCancelled else { return .unavailable }
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
            return .unavailable
        }
        guard let policy = configuration.transferPolicy,
              policy.matches(configuration), let fingerprint = policy.fingerprint else {
            return .failed(.transferPolicyUnavailable)
        }
        let transfer = SceneRemoteTransferRequest(
            requestID: requestID, requestHash: body.requestHash,
            scriptText: body.scriptText, markedObjectIDs: body.markedObjectIDs,
            policy: policy, policyFingerprint: fingerprint
        )
        // Enrollment can also disclose an installation identity. Do not even
        // acquire a service token until this exact content/policy is accepted.
        guard let transferConsentHandler,
              let approval = await transferConsentHandler(transfer),
              approval == transfer.approval, !Task.isCancelled else {
            return .failed(.transferDeclined)
        }
        var activeJobID: String?
        do {
            let idempotencyKey = "gen-\(requestID.uuidString)"
            let status = try await createJob(body: body, idempotencyKey: idempotencyKey)
            activeJobID = status.jobID
            var outcome = try await pollToTerminal(
                jobID: status.jobID,
                expectedRequest: body,
                originalCreateIdempotencyKey: idempotencyKey
            )
            var answeredQuestions = Set<String>()
            while case .awaitingClarification(let clarificationPayload) = outcome {
                let questionKey = "\(clarificationPayload.id)|\(clarificationPayload.epoch)"
                guard answeredQuestions.count < 3,
                      !answeredQuestions.contains(questionKey),
                      let clarificationHandler,
                      let userAnswer = await clarificationHandler(clarificationPayload),
                      !Task.isCancelled else {
                    throw SceneGenerationClientError.cancelled
                }
                let text = userAnswer.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if userAnswer.isFreeText {
                    guard clarificationPayload.allowsFreeText,
                          !text.isEmpty,
                          text.count <= clarificationPayload.maximumFreeTextCharacters else {
                        throw SceneGenerationClientError.malformedPayload
                    }
                } else {
                    guard clarificationPayload.options.contains(where: { $0.id == userAnswer.rawValue }) else {
                        throw SceneGenerationClientError.malformedPayload
                    }
                }
                let answer = SceneClarificationAPIPayload(
                    clarificationID: clarificationPayload.id,
                    requestID: clarificationPayload.requestID,
                    epoch: clarificationPayload.epoch,
                    selectedOptionID: userAnswer.isFreeText ? nil : userAnswer.rawValue,
                    freeText: userAnswer.isFreeText ? text : nil
                )
                let resumedStatus = try await answerClarification(
                    jobID: status.jobID,
                    answer: answer,
                    idempotencyKey: idempotencyKey + "-clar-\(answeredQuestions.count)"
                )
                guard Self.matches(resumedStatus, expectedRequest: body, idempotencyKey: idempotencyKey) else {
                    throw SceneGenerationClientError.responseBindingMismatch
                }
                answeredQuestions.insert(questionKey)
                outcome = try await pollToTerminal(
                    jobID: status.jobID,
                    expectedRequest: body,
                    originalCreateIdempotencyKey: idempotencyKey
                )
            }
            guard !Task.isCancelled,
                  case .complete(let result) = outcome,
                  SceneResponseValidator.validate(
                    script: result.sceneScript,
                    markedObjectIDs: Set(markedObjects.map(\.canonicalMarkedObjectID)),
                    mentionedMarkedObjects: Set(anchors.mentionedMarkedObjects)
                  ).isEmpty else { return .unavailable }
            let receipt = SceneRemoteGenerationReceipt(
                jobID: status.jobID,
                requestID: status.requestID,
                requestHash: status.requestHash,
                idempotencyKey: status.idempotencyKey,
                backendSchemaVersion: status.schemaVersionBackend,
                scriptSchemaVersion: result.schemaVersion,
                modelVersion: status.modelVersion,
                promptVersion: status.promptVersion,
                providerName: status.providerName,
                providerVersion: status.providerVersion
            )
            guard let plan = SceneGenerationClient.planResult(from: result, receipt: receipt) else {
                return .unavailable
            }
            return .plan(plan)
        } catch {
            // The server has made a terminal decision. Preserve it for the
            // request owner; do not create a replacement job or a local scene.
            if !Task.isCancelled, let error = error as? SceneGenerationClientError {
                switch error {
                case .contentExpired: return .failed(.contentExpired)
                case .killSwitchEngaged: return .failed(.serviceDisabled)
                case .unexpectedGoneResponse: return .failed(.invalidServiceResponse)
                default: break
                }
            }
            if let activeJobID {
                // A cancelled task cannot reliably send DELETE through its
                // cancelled URLSession operation. Join one bounded cleanup
                // request, never another generation or provider request.
                await Task.detached { [self] in
                    _ = try? await cancelJob(jobID: activeJobID)
                }.value
            }
            return .unavailable
        }
    }

    // MARK: - Typed API surface

    func createJob(body: SceneCreateJobRequest, idempotencyKey: String) async throws -> SceneJobStatus {
        try Self.requireValidIdempotencyKey(idempotencyKey)
        let request = try await authenticatedRequest(
            path: "jobs",
            method: "POST",
            body: try encoder.encode(body),
            contentType: "application/json",
            idempotencyKey: idempotencyKey
        )
        let (data, response) = try await authenticatedData(for: request)
        try Self.checkHTTP(response, data: data)
        let status = try decodeAndValidateStatus(data)
        guard Self.matches(status, expectedRequest: body, idempotencyKey: idempotencyKey) else {
            throw SceneGenerationClientError.responseBindingMismatch
        }
        return status
    }

    func pollJob(jobID: String) async throws -> SceneJobStatus {
        try Self.requireValidJobID(jobID)
        let request = try await authenticatedRequest(path: "jobs/\(jobID)", method: "GET")
        let (data, response) = try await authenticatedData(for: request)
        try Self.checkHTTP(response, data: data)
        let status = try decodeAndValidateStatus(data)
        guard status.jobID == jobID else {
            throw SceneGenerationClientError.responseBindingMismatch
        }
        return status
    }

    func answerClarification(jobID: String, answer: SceneClarificationAPIPayload, idempotencyKey: String) async throws -> SceneJobStatus {
        try Self.requireValidJobID(jobID)
        try Self.requireValidIdempotencyKey(idempotencyKey)
        let request = try await authenticatedRequest(
            path: "jobs/\(jobID)/clarification-answer",
            method: "POST",
            body: try encoder.encode(answer),
            contentType: "application/json",
            idempotencyKey: idempotencyKey
        )
        let (data, response) = try await authenticatedData(for: request)
        try Self.checkHTTP(response, data: data)
        let status = try decodeAndValidateStatus(data)
        guard status.jobID == jobID,
              status.requestID == answer.requestID else {
            throw SceneGenerationClientError.responseBindingMismatch
        }
        return status
    }

    func cancelJob(jobID: String) async throws -> SceneJobStatus {
        try Self.requireValidJobID(jobID)
        let request = try await authenticatedRequest(path: "jobs/\(jobID)", method: "DELETE")
        let (data, response) = try await authenticatedData(for: request)
        try Self.checkHTTP(response, data: data)
        let status = try decodeAndValidateStatus(data)
        guard status.jobID == jobID else {
            throw SceneGenerationClientError.responseBindingMismatch
        }
        return status
    }

    /// Bounded poll to a terminal outcome. Every decoded status is
    /// validated before it advances the loop; kill-switch aborts
    /// immediately and cancellation throws.
    func pollToTerminal(
        jobID: String,
        expectedRequest: SceneCreateJobRequest,
        originalCreateIdempotencyKey: String
    ) async throws -> SceneGenerationOutcome {
        try Self.requireValidJobID(jobID)
        try Self.requireValidIdempotencyKey(originalCreateIdempotencyKey)
        var polls = 0
        while true {
            if Task.isCancelled { throw SceneGenerationClientError.cancelled }
            let status = try await pollJob(jobID: jobID)
            guard Self.matches(status, expectedRequest: expectedRequest, idempotencyKey: originalCreateIdempotencyKey) else {
                throw SceneGenerationClientError.responseBindingMismatch
            }
            switch try Self.outcome(from: status) {
            case .notTerminal:
                polls += 1
                if polls >= configuration.maximumPolls {
                    throw SceneGenerationClientError.jobFailed(.timeout)
                }
                try await Task.sleep(nanoseconds: UInt64(configuration.pollIntervalSeconds * 1_000_000_000))
            case .complete(let result): return .complete(result)
            case .awaitingClarification(let payload): return .awaitingClarification(payload)
            case .failed(let failure): return .failed(failure)
            case .rejected(let rejection): throw Self.error(for: rejection)
            }
        }
    }

    // MARK: - Helpers

    private func authenticatedData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        let original = try await session.data(for: request)
        guard (original.1 as? HTTPURLResponse)?.statusCode == 401,
              let authorization = request.value(forHTTPHeaderField: "Authorization"),
              authorization.hasPrefix("Bearer ") else { return original }
        try Task.checkCancellation()
        let rejectedToken = String(authorization.dropFirst("Bearer ".count))
        guard let replacement = await tokenProvider?.replacementServiceToken(afterRejecting: rejectedToken),
              replacement != rejectedToken,
              Self.isValidServiceToken(replacement) else { return original }
        try Task.checkCancellation()
        // Only the credential changes. The original job, payload and
        // idempotency key survive token rotation; there is at most one retry.
        var retry = request
        retry.setValue("Bearer \(replacement)", forHTTPHeaderField: "Authorization")
        return try await session.data(for: retry)
    }

    private func decodeAndValidateStatus(_ data: Data) throws -> SceneJobStatus {
        let status: SceneJobStatus
        do {
            status = try decoder.decode(SceneJobStatus.self, from: data)
        } catch {
            throw SceneGenerationClientError.malformedPayload
        }
        guard Self.isValidJobID(status.jobID) else {
            throw SceneGenerationClientError.invalidJobID
        }
        switch SceneJobValidation.validate(status) {
        case .rejected(let rejection):
            throw Self.error(for: rejection)
        case .notTerminal, .complete, .awaitingClarification, .failed:
            return status
        }
    }

    private static func outcome(from status: SceneJobStatus) throws -> SceneJobValidationResult {
        switch SceneJobValidation.validate(status) {
        case .rejected(let rejection): throw error(for: rejection)
        case .notTerminal: return .notTerminal
        case .complete(let result): return .complete(result)
        case .awaitingClarification(let payload): return .awaitingClarification(payload)
        case .failed(let failure): return .failed(failure)
        }
    }

    private static func error(for rejection: SceneJobRejection) -> SceneGenerationClientError {
        rejection == .killSwitchEngaged
            ? .killSwitchEngaged
            : .rejected(rejection)
    }

    private static func matches(
        _ status: SceneJobStatus,
        expectedRequest: SceneCreateJobRequest,
        idempotencyKey: String
    ) -> Bool {
        status.requestID == expectedRequest.requestID
            && status.requestHash == expectedRequest.requestHash
            && status.schemaVersionBackend == expectedRequest.schemaVersionBackend
            && status.modelVersion == expectedRequest.modelVersion
            && status.promptVersion == expectedRequest.promptVersion
            && status.providerName == expectedRequest.providerName
            && status.providerVersion == expectedRequest.providerVersion
            && status.idempotencyKey == idempotencyKey
    }

    private static func requireValidJobID(_ value: String) throws {
        guard isValidJobID(value) else { throw SceneGenerationClientError.invalidJobID }
    }

    private static func requireValidIdempotencyKey(_ value: String) throws {
        guard isValidIdempotencyKey(value) else {
            throw SceneGenerationClientError.invalidIdempotencyKey
        }
    }

    private static func isValidJobID(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard (1...128).contains(bytes.count),
              let first = bytes.first,
              (97...122).contains(first) else {
            return false
        }
        return bytes.dropFirst().allSatisfy {
            (97...122).contains($0)
                || (48...57).contains($0)
                || $0 == 95
                || $0 == 45
        }
    }

    private static func isValidIdempotencyKey(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard (1...128).contains(bytes.count) else { return false }
        return bytes.allSatisfy {
            (97...122).contains($0)
                || (65...90).contains($0)
                || (48...57).contains($0)
                || $0 == 46
                || $0 == 95
                || $0 == 45
        }
    }

    private func authenticatedRequest(
        path: String,
        method: String,
        body: Data? = nil,
        contentType: String? = nil,
        idempotencyKey: String? = nil
    ) async throws -> URLRequest {
        guard Self.isValidEndpoint(configuration.baseURL) else {
            throw SceneGenerationClientError.invalidEndpoint
        }
        guard let token = await tokenProvider?.currentServiceToken() else {
            throw SceneGenerationClientError.missingServiceToken
        }
        guard Self.isValidServiceToken(token) else {
            throw SceneGenerationClientError.invalidServiceToken
        }

        var request = URLRequest(
            url: configuration.baseURL.appendingPathComponent(path),
            timeoutInterval: configuration.requestTimeoutSeconds
        )
        request.httpMethod = method
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        return request
    }

    /// Deployment composition reuses this rule so the factory fails closed
    /// exactly like request-time admission does.
    static func isValidEndpoint(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              let placeholderHost = URL(string: SceneAPIVersion.placeholderHost)?.host,
              (host.hasSuffix(".") ? String(host.dropLast()) : host)
                  .caseInsensitiveCompare(placeholderHost.hasSuffix(".") ? String(placeholderHost.dropLast()) : placeholderHost) != .orderedSame else {
            return false
        }
        return true
    }

    private static func isValidServiceToken(_ token: String) -> Bool {
        let bytes = Array(token.utf8)
        guard !bytes.isEmpty else { return false }

        var hasTokenCharacter = false
        var hasPadding = false
        for byte in bytes {
            if byte == 61 {
                hasPadding = true
                continue
            }
            guard !hasPadding,
                  (byte == 45 || byte == 46 || byte == 47 || byte == 95 || byte == 126 ||
                   byte == 43 || (48...57).contains(byte) || (65...90).contains(byte) ||
                   (97...122).contains(byte)) else {
                return false
            }
            hasTokenCharacter = true
        }
        return hasTokenCharacter
    }

    private struct APIErrorEnvelope: Decodable {
        let code: String
        let message: String
    }

    private static func checkHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SceneGenerationClientError.malformedPayload
        }
        if http.statusCode == 410 {
            guard let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) else {
                throw SceneGenerationClientError.unexpectedGoneResponse
            }
            switch envelope.code {
            case "content_expired": throw SceneGenerationClientError.contentExpired
            case "kill_switch": throw SceneGenerationClientError.killSwitchEngaged
            default: throw SceneGenerationClientError.unexpectedGoneResponse
            }
        }
        if http.statusCode == 429 {
            // This is a server delay hint, never authority to replay a paid job.
            let raw = http.value(forHTTPHeaderField: "Retry-After") ?? ""
            let seconds = !raw.isEmpty && raw.utf8.allSatisfy({ (48...57).contains($0) })
                ? Int(raw) : nil
            throw SceneGenerationClientError.quotaExceeded(
                retryAfterSeconds: seconds.flatMap { (1...86_400).contains($0) ? $0 : nil }
            )
        }
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
    static func planResult(
        from result: SceneJobResult, receipt: SceneRemoteGenerationReceipt? = nil
    ) -> ScenePlanProviderResult? {
        let bridge = LegacySceneScriptBridge()
        guard let plan = bridge.planIR(from: result.sceneScript) else { return nil }
        return ScenePlanProviderResult(
            plan: plan,
            usedLegacySceneScriptBridge: true,
            reasonCodes: ["remote_plan_used"],
            generationContributors: receipt.map { [.remoteService($0)] }
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
