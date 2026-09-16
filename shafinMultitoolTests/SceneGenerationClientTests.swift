//
//  SceneGenerationClientTests.swift
//  shafinMultitoolTests
//
//  M5-025: URLProtocol contract tests for the typed generation client.
//  No network, no provider, no live host: a stub protocol owns the wire.
//

import XCTest
@testable import shafinMultitool

final class SceneGenerationClientTests: XCTestCase {
    private var session: URLSession!
    private static let validBaseURL = URL(string: "https://scene.example.test/v1")!

    override func setUp() {
        super.setUp()
        SceneClientStub.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SceneClientStub.self]
        session = URLSession(configuration: configuration)
    }

    private func client(
        maximumPolls: Int = 5,
        baseURL: URL = SceneGenerationClientTests.validBaseURL,
        token: String? = "test-token",
        tokenProvider: SceneServiceTokenProviding? = nil,
        withTransferPolicy: Bool = true
    ) -> SceneGenerationClient {
        var configuration = SceneGenerationClientConfiguration.placeholder
        configuration.baseURL = baseURL
        configuration.pollIntervalSeconds = 0
        configuration.maximumPolls = maximumPolls
        configuration.transferPolicy = withTransferPolicy ? SceneTransferPolicyFixture.policy(for: configuration) : nil
        return SceneGenerationClient(
            configuration: configuration,
            session: session,
            tokenProvider: tokenProvider ?? StaticTokenProvider(token: token)
        )
    }

    private func jobFixture(_ name: String) throws -> Data {
        let thisFile = URL(fileURLWithPath: #filePath)
        let root = thisFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try Data(contentsOf: root
            .appendingPathComponent("backend/schemas/fixtures")
            .appendingPathComponent(name))
    }

    private func jobStatus(_ name: String) throws -> SceneJobStatus {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SceneJobStatus.self, from: try jobFixture(name))
    }

    private func createBody() throws -> SceneCreateJobRequest {
        let pending = try jobStatus("job-valid-pending.json")
        return try SceneCreateJobRequestBuilder.build(
            requestID: pending.requestID,
            clientBuild: "1.0 (1)",
            locale: "en",
            scriptText: "MARA approaches the table.",
            markedObjectIDs: [],
            maximumScenes: 1,
            previousJobID: nil,
            modelVersion: pending.modelVersion,
            promptVersion: pending.promptVersion,
            providerName: pending.providerName,
            providerVersion: pending.providerVersion
        ).get()
    }

    private func clarificationAnswer() -> SceneClarificationAPIPayload {
        SceneClarificationAPIPayload(
            clarificationID: "clarification_demo001",
            requestID: UUID(),
            epoch: 0,
            selectedOptionID: "option_demo001",
            freeText: nil
        )
    }

    private func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else {
            throw URLError(.badServerResponse)
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.badServerResponse) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    private func responseData(
        fixture name: String,
        request: SceneCreateJobRequest? = nil,
        requestID: UUID? = nil,
        idempotencyKey: String? = nil,
        overrides: [String: Any] = [:]
    ) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(
            with: try jobFixture(name)
        ) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        if let request {
            object["request_id"] = request.requestID.uuidString
            object["request_hash"] = request.requestHash
            object["schema_version_backend"] = request.schemaVersionBackend
            object["model_version"] = request.modelVersion
            object["prompt_version"] = request.promptVersion
            object["provider_name"] = request.providerName
            object["provider_version"] = request.providerVersion
        }
        if let requestID {
            object["request_id"] = requestID.uuidString
        }
        if let idempotencyKey {
            object["idempotency_key"] = idempotencyKey
        }
        for (key, value) in overrides {
            object[key] = value
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func decodedCreateRequest(from request: URLRequest) throws -> SceneCreateJobRequest {
        try JSONDecoder().decode(
            SceneCreateJobRequest.self,
            from: try bodyData(from: request)
        )
    }

    private func fixtureMarker() throws -> MarkedObject {
        let marker = MarkedObject(name: "table", position: Position3D(x: 0, y: 0, z: -1))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(marker)) as? [String: Any])
        object["id"] = "deadbeef-0000-0000-0000-000000000001"
        return try JSONDecoder().decode(MarkedObject.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private final class ClarificationProbe {
        var issuedPayload: SceneClarificationPayload?
        var answers: [SceneClarificationAPIPayload] = []
        var deleteCount = 0
        var createCount = 0
    }

    private func installClarificationJob() -> ClarificationProbe {
        let probe = ClarificationProbe()
        var createdRequest: SceneCreateJobRequest?
        var createKey: String?
        SceneClientStub.handler = { request in
            let isCreate = request.httpMethod == "POST" && request.url?.path.hasSuffix("/jobs") == true
            if isCreate {
                probe.createCount += 1
                createdRequest = try self.decodedCreateRequest(from: request)
                createKey = request.value(forHTTPHeaderField: "Idempotency-Key")
            }
            let body = try XCTUnwrap(createdRequest)
            let key = try XCTUnwrap(createKey)
            let question = SceneClarificationPayload(
                id: "question_subject", requestID: body.requestID, epoch: 7,
                prompt: "Who is the main subject?", targetReference: nil,
                options: [.init(id: "first", label: "First subject"), .init(id: "second", label: "Second subject")],
                allowsFreeText: true, maximumFreeTextCharacters: 160,
                observedDiagnostics: [], attempt: 0
            )
            probe.issuedPayload = question
            var fixture: String
            var overrides: [String: Any] = [:]
            if isCreate {
                fixture = "job-valid-pending.json"
            } else if request.httpMethod == "DELETE" {
                probe.deleteCount += 1
                fixture = "job-valid-cancelled.json"
            } else if request.httpMethod == "POST" {
                XCTAssertTrue(request.url?.path.hasSuffix("/clarification-answer") == true)
                probe.answers.append(try JSONDecoder().decode(SceneClarificationAPIPayload.self, from: self.bodyData(from: request)))
                fixture = "job-valid-running.json"
            } else if probe.answers.isEmpty {
                fixture = "job-valid-awaiting-clarification.json"
                overrides["clarification"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(question))
            } else {
                fixture = "job-valid-complete.json"
            }
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try self.responseData(fixture: fixture, request: body, idempotencyKey: key, overrides: overrides)
            )
        }
        return probe
    }

    private func assertRejected(
        expected: SceneGenerationClientError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("expected \(expected.stableDescription)")
        } catch let error as SceneGenerationClientError {
            XCTAssertEqual(error, expected)
            XCTAssertEqual(error.stableDescription, expected.stableDescription)
        } catch {
            XCTFail("expected \(expected.stableDescription), got \(error)")
        }
    }

    func testCreateSendsIdempotencyKeyAndBearerToken() async throws {
        let pending = try jobStatus("job-valid-pending.json")
        let body = try SceneCreateJobRequestBuilder.build(
            requestID: pending.requestID,
            clientBuild: "1.0 (1)",
            locale: "en",
            scriptText: "MARA approaches the table.",
            markedObjectIDs: [],
            maximumScenes: 1,
            previousJobID: nil,
            modelVersion: pending.modelVersion,
            promptVersion: pending.promptVersion,
            providerName: pending.providerName,
            providerVersion: pending.providerVersion
        ).get()
        SceneClientStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "Idempotency-Key"))
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer test-token"
            )
            let data = try self.responseData(
                fixture: "job-valid-pending.json",
                request: body,
                idempotencyKey: "idem.test.001"
            )
            return (HTTPURLResponse(
                url: request.url!,
                statusCode: 201,
                httpVersion: nil,
                headerFields: nil
            )!, data)
        }
        let authed = SceneGenerationClient(
            configuration: {
                var configuration = SceneGenerationClientConfiguration.placeholder
                configuration.baseURL = Self.validBaseURL
                configuration.pollIntervalSeconds = 0
                return configuration
            }(),
            session: session,
            tokenProvider: StaticTokenProvider(token: "test-token")
        )
        let status = try await authed.createJob(body: body, idempotencyKey: "idem.test.001")
        XCTAssertEqual(status.jobID, pending.jobID)
    }

    func testAnswerClarificationSendsAuthenticatedRequest() async throws {
        let pending = try jobStatus("job-valid-pending.json")
        let answer = clarificationAnswer()
        SceneClientStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/jobs/job_demo001/clarification-answer")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "idem.test.answer")
            let decoded = try JSONDecoder().decode(
                SceneClarificationAPIPayload.self,
                from: try self.bodyData(from: request)
            )
            XCTAssertEqual(decoded, answer)
            return (HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!, try self.responseData(
                fixture: "job-valid-pending.json",
                requestID: answer.requestID
            ))
        }
        let status = try await client().answerClarification(
            jobID: "job_demo001",
            answer: answer,
            idempotencyKey: "idem.test.answer"
        )
        XCTAssertEqual(status.jobID, pending.jobID)
    }

    /// Wire-parity pin against the frozen `ClarificationAnswer` OpenAPI
    /// component (scene-api-v1): `additionalProperties: false` with typed,
    /// non-nullable properties, so the encoder must OMIT an unset option or
    /// free text rather than send an explicit null, which the server's
    /// fail-closed admission would reject. The parity relies on synthesized
    /// Codable's `encodeIfPresent` semantics; this test keeps it true if the
    /// payload ever grows a custom encoder.
    func testClarificationAnswerPayloadOmitsUnsetFieldsAndMatchesFrozenSchemaKeys() throws {
        let optionOnly = clarificationAnswer()
        let optionObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(optionOnly))
                as? [String: Any]
        )
        XCTAssertEqual(
            Set(optionObject.keys),
            ["clarification_id", "request_id", "epoch", "selected_option_id"]
        )
        XCTAssertFalse(optionObject.values.contains { $0 is NSNull })
        XCTAssertEqual(optionObject["clarification_id"] as? String, "clarification_demo001")
        XCTAssertEqual(optionObject["selected_option_id"] as? String, "option_demo001")
        XCTAssertEqual(optionObject["epoch"] as? Int, 0)
        XCTAssertNotNil(UUID(uuidString: optionObject["request_id"] as? String ?? ""))

        let freeTextOnly = SceneClarificationAPIPayload(
            clarificationID: "clarification_demo001",
            requestID: UUID(),
            epoch: 1,
            selectedOptionID: nil,
            freeText: "МАРИНА"
        )
        let freeTextObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(freeTextOnly))
                as? [String: Any]
        )
        XCTAssertEqual(
            Set(freeTextObject.keys),
            ["clarification_id", "request_id", "epoch", "free_text"]
        )
        XCTAssertFalse(freeTextObject.values.contains { $0 is NSNull })
    }

    /// The backend worker (store v3) now emits running statuses between
    /// pending and the terminal branches. pollToTerminal must treat running
    /// as non-terminal and keep polling to the complete result.
    func testPollToTerminalTreatsRunningAsNotTerminal() async throws {
        let request = try createBody()
        let idempotencyKey = "idem.test.create"
        let running = try responseData(
            fixture: "job-valid-running.json",
            request: request,
            idempotencyKey: idempotencyKey
        )
        let complete = try responseData(
            fixture: "job-valid-complete.json",
            request: request,
            idempotencyKey: idempotencyKey
        )
        var responses = [running, complete]
        SceneClientStub.handler = { _ in
            (HTTPURLResponse(
                url: URL(string: "https://set-os.local/v1/jobs/job_demo001")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!, responses.isEmpty ? complete : responses.removeFirst())
        }
        let outcome = try await client().pollToTerminal(
            jobID: "job_demo001",
            expectedRequest: request,
            originalCreateIdempotencyKey: idempotencyKey
        )
        guard case .complete(let result) = outcome else {
            return XCTFail("expected complete, got \(outcome)")
        }
        XCTAssertFalse(result.sceneScript.beats.isEmpty)
    }

    func testPollToTerminalCompletes() async throws {
        let request = try createBody()
        let idempotencyKey = "idem.test.create"
        let complete = try responseData(
            fixture: "job-valid-complete.json",
            request: request,
            idempotencyKey: idempotencyKey
        )
        SceneClientStub.handler = { request in
            (HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!, complete)
        }
        let outcome = try await client().pollToTerminal(
            jobID: "job_demo001",
            expectedRequest: request,
            originalCreateIdempotencyKey: idempotencyKey
        )
        guard case .complete(let result) = outcome else {
            return XCTFail("expected complete, got \(outcome)")
        }
        XCTAssertFalse(result.sceneScript.beats.isEmpty)
    }

    func testPollToTerminalSurfacesClarification() async throws {
        let request = try createBody()
        let idempotencyKey = "idem.test.create"
        let awaiting = try responseData(
            fixture: "job-valid-awaiting-clarification.json",
            request: request,
            idempotencyKey: idempotencyKey
        )
        SceneClientStub.handler = { request in
            (HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!, awaiting)
        }
        let outcome = try await client().pollToTerminal(
            jobID: "job_demo001",
            expectedRequest: request,
            originalCreateIdempotencyKey: idempotencyKey
        )
        guard case .awaitingClarification(let payload) = outcome else {
            return XCTFail("expected clarification, got \(outcome)")
        }
        XCTAssertFalse(payload.options.isEmpty)
    }

    func testPollToTerminalSurfacesFailure() async throws {
        let request = try createBody()
        let idempotencyKey = "idem.test.create"
        for code in [SceneJobFailureCode.providerError, .timeout] {
            SceneClientStub.reset()
            let failed = try responseData(
                fixture: "job-valid-failed.json",
                request: request,
                idempotencyKey: idempotencyKey,
                overrides: ["failure": ["code": code.rawValue, "message": "Job failed."]]
            )
            SceneClientStub.handler = { request in
                (HTTPURLResponse(
                    url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: nil
                )!, failed)
            }
            let outcome = try await client().pollToTerminal(
                jobID: "job_demo001", expectedRequest: request,
                originalCreateIdempotencyKey: idempotencyKey
            )
            guard case .failed(let failure) = outcome else {
                return XCTFail("expected failed, got \(outcome)")
            }
            XCTAssertEqual(failure.code, code)
            XCTAssertEqual(SceneClientStub.callCount, 1)
        }
    }

    func testMalformedPayloadThrows() async throws {
        SceneClientStub.handler = { request in
            (HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!, Data("not json".utf8))
        }
        do {
            _ = try await client().pollJob(jobID: "job_demo001")
            XCTFail("expected malformed payload")
        } catch let error as SceneGenerationClientError {
            XCTAssertEqual(error, .malformedPayload)
        }
    }

    func testTypedOperationRejectsMixedTerminalPayload() async throws {
        let invalid = try jobFixture("job-invalid-complete-with-failure.json")
        SceneClientStub.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                invalid
            )
        }
        await assertRejected(expected: .rejected(.missingOrMixedTerminalPayload)) {
            _ = try await client().pollJob(jobID: "job_demo001")
        }
    }

    func testKillSwitchAbortsPoll() async throws {
        SceneClientStub.handler = { request in
            (HTTPURLResponse(
                url: request.url!,
                statusCode: 410,
                httpVersion: nil,
                headerFields: nil
            )!, Data(#"{"code":"kill_switch","message":"Generation is temporarily disabled."}"#.utf8))
        }
        do {
            _ = try await client().pollToTerminal(
                jobID: "job_demo001",
                expectedRequest: try createBody(),
                originalCreateIdempotencyKey: "idem.test.create"
            )
            XCTFail("expected kill-switch abort")
        } catch let error as SceneGenerationClientError {
            XCTAssertEqual(error, .killSwitchEngaged)
        }
    }

    func testExpiredContentIsTypedForAllOwnedJobOperationsWithoutRetry() async throws {
        for operation in 0..<4 {
            SceneClientStub.reset()
            SceneClientStub.handler = { request in
                (HTTPURLResponse(url: request.url!, statusCode: 410, httpVersion: nil, headerFields: nil)!,
                 Data(#"{"code":"content_expired","message":"Job content has expired."}"#.utf8))
            }
            await assertRejected(expected: .contentExpired) {
                let sut = client()
                switch operation {
                case 0: _ = try await sut.createJob(body: createBody(), idempotencyKey: "idem.expired")
                case 1: _ = try await sut.pollJob(jobID: "job_demo001")
                case 2: _ = try await sut.answerClarification(jobID: "job_demo001", answer: clarificationAnswer(), idempotencyKey: "idem.expired.answer")
                default: _ = try await sut.cancelJob(jobID: "job_demo001")
                }
            }
            XCTAssertEqual(SceneClientStub.callCount, 1, "Expiry never authorizes an automatic retry")
        }
    }

    func testUnknownOrMalformedGoneResponseCannotClaimKillSwitch() async throws {
        for body in ["", "{}", #"{"code":"future_code","message":"Gone"}"#, #"{"code":"content_expired"}"#] {
            SceneClientStub.reset()
            SceneClientStub.handler = { request in
                (HTTPURLResponse(url: request.url!, statusCode: 410, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
            }
            await assertRejected(expected: .unexpectedGoneResponse) {
                _ = try await client().pollJob(jobID: "job_demo001")
            }
            XCTAssertEqual(SceneClientStub.callCount, 1)
        }
    }

    func testProductionRemoteOutcomePreservesGoneDecisionWithoutCreatingReplacementJob() async throws {
        for (code, expected) in [
            ("content_expired", SceneRemoteGenerationFailure.contentExpired),
            ("kill_switch", .serviceDisabled),
            ("future_code", .invalidServiceResponse)
        ] {
            SceneClientStub.reset()
            var methods: [String] = []
            SceneClientStub.handler = { request in
                methods.append(request.httpMethod ?? "")
                if request.httpMethod == "POST" {
                    let payload = try self.responseData(
                        fixture: "job-valid-pending.json",
                        request: self.decodedCreateRequest(from: request),
                        idempotencyKey: request.value(forHTTPHeaderField: "Idempotency-Key")
                    )
                    return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, payload)
                }
                let payload = try JSONSerialization.data(withJSONObject: ["code": code, "message": "Gone"])
                return (HTTPURLResponse(url: request.url!, statusCode: 410, httpVersion: nil, headerFields: nil)!, payload)
            }
            let outcome = await client().generateRemotePlanOutcome(
                description: "A person stands still.", markedObjects: [], anchors: .empty,
                state: nil, clarificationHandler: nil, transferConsentHandler: { $0.approval }
            )
            guard case .failed(let failure) = outcome else {
                XCTFail("Terminal remote failure must reach the production request owner")
                continue
            }
            XCTAssertEqual(failure, expected)
            XCTAssertEqual(methods, ["POST", "GET"], "No replacement job, follow-up polling or cleanup replay")
        }
    }

    func testQuotaResponseIsTypedAndNeverAutomaticallyRetried() async throws {
        for (header, expected) in [
            ("3600", 3600), ("86400", 86400), ("0", nil), ("-1", nil),
            ("86401", nil), ("999999999999999999999", nil),
            ("Wed, 21 Oct 2015 07:28:00 GMT", nil), ("", nil)
        ] as [(String, Int?)] {
            SceneClientStub.reset()
            SceneClientStub.handler = { request in
                (HTTPURLResponse(
                    url: request.url!, statusCode: 429, httpVersion: nil,
                    headerFields: header.isEmpty ? nil : ["Retry-After": header]
                )!, Data("untrusted quota body".utf8))
            }
            await assertRejected(expected: .quotaExceeded(retryAfterSeconds: expected)) {
                _ = try await self.client().createJob(
                    body: self.createBody(), idempotencyKey: "quota-key"
                )
            }
            XCTAssertEqual(SceneClientStub.callCount, 1)
        }
        SceneClientStub.reset()
        SceneClientStub.handler = { request in
            (HTTPURLResponse(
                url: request.url!, statusCode: 429, httpVersion: nil,
                headerFields: ["Retry-After": "60"]
            )!, Data())
        }
        await assertRejected(expected: .quotaExceeded(retryAfterSeconds: 60)) {
            _ = try await self.client().pollToTerminal(
                jobID: "job_demo001", expectedRequest: self.createBody(),
                originalCreateIdempotencyKey: "quota-key"
            )
        }
        XCTAssertEqual(SceneClientStub.callCount, 1)
    }

    func testCancelSendsDelete() async throws {
        let cancelled = try jobFixture("job-valid-cancelled.json")
        SceneClientStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            return (HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!, cancelled)
        }
        let status = try await client().cancelJob(jobID: "job_demo001")
        XCTAssertEqual(status.status, .cancelled)
    }

    func testRemotePlanBridgeProjectsValidatedScript() async throws {
        var expectedRequest: SceneCreateJobRequest?
        var createIdempotencyKey: String?
        SceneClientStub.handler = { request in
            let isCreate = request.httpMethod == "POST"
                && request.url?.path.hasSuffix("/jobs") == true
            if isCreate {
                expectedRequest = try self.decodedCreateRequest(from: request)
                createIdempotencyKey = request.value(forHTTPHeaderField: "Idempotency-Key")
            }
            guard let expectedRequest, let createIdempotencyKey else {
                throw URLError(.badServerResponse)
            }
            let payload = try self.responseData(
                fixture: isCreate ? "job-valid-pending.json" : "job-valid-complete.json",
                request: expectedRequest,
                idempotencyKey: createIdempotencyKey
            )
            return (HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!, payload)
        }
        let provider = client()
        let result = await provider.generateConsentedRemotePlan(
            description: "MARA approaches the marked table.",
            markedObjects: [try fixtureMarker()],
            anchors: SourceAnchorBundle.empty,
            state: nil
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.reasonCodes, ["remote_plan_used"])
        XCTAssertEqual(result?.usedLegacySceneScriptBridge, true)
        guard case .remoteService(let receipt)? = result?.generationContributors?.first else {
            return XCTFail("Validated job identity must accompany its accepted plan")
        }
        let submitted = try XCTUnwrap(expectedRequest)
        let complete = try jobStatus("job-valid-complete.json")
        XCTAssertEqual(receipt.jobID, complete.jobID)
        XCTAssertEqual(receipt.requestID, submitted.requestID)
        XCTAssertEqual(receipt.requestHash, submitted.requestHash)
        XCTAssertEqual(receipt.idempotencyKey, createIdempotencyKey)
        XCTAssertEqual(receipt.backendSchemaVersion, submitted.schemaVersionBackend)
        XCTAssertEqual(receipt.scriptSchemaVersion, complete.result?.schemaVersion)
        XCTAssertEqual(receipt.modelVersion, submitted.modelVersion)
        XCTAssertEqual(receipt.promptVersion, submitted.promptVersion)
        XCTAssertEqual(receipt.providerName, submitted.providerName)
        XCTAssertEqual(receipt.providerVersion, submitted.providerVersion)
    }

    @MainActor
    func testRemoteClarificationPostsActualSecondChoiceWithWireIdentity() async throws {
        let probe = installClarificationJob()
        let result = await client().generateConsentedRemotePlan(
            description: "MARA approaches the marked table.",
            markedObjects: [try fixtureMarker()], anchors: .empty, state: nil,
            clarificationHandler: { payload in
                XCTAssertTrue(probe.answers.isEmpty, "No answer may be posted before the user responds")
                XCTAssertEqual(payload.options.map(\.id), ["first", "second"])
                return .choice("second")
            }
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(probe.createCount, 1)
        XCTAssertEqual(probe.answers.count, 1)
        let answer = try XCTUnwrap(probe.answers.first)
        XCTAssertEqual(answer.selectedOptionID, "second")
        XCTAssertNil(answer.freeText)
        XCTAssertEqual(answer.requestID, probe.issuedPayload?.requestID)
        XCTAssertEqual(answer.epoch, 7)
        XCTAssertEqual(answer.clarificationID, "question_subject")
        guard case .remoteService(let receipt)? = result?.generationContributors?.first else {
            return XCTFail("The clarified result must retain the same job receipt")
        }
        XCTAssertEqual(receipt.requestID, answer.requestID)
        XCTAssertEqual(receipt.idempotencyKey, "gen-\(answer.requestID.uuidString)")
    }

    @MainActor
    func testRemoteClarificationPostsFreeTextWithoutInventedOption() async throws {
        let probe = installClarificationJob()
        let result = await client().generateConsentedRemotePlan(
            description: "MARA approaches the marked table.",
            markedObjects: [try fixtureMarker()], anchors: .empty, state: nil,
            clarificationHandler: { _ in .freeText("  The person behind the table  ") }
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(probe.answers.count, 1)
        XCTAssertNil(probe.answers.first?.selectedOptionID)
        XCTAssertEqual(probe.answers.first?.freeText, "The person behind the table")
    }

    func testRemoteClarificationWithoutUserHandlerCancelsJobWithoutAnswer() async {
        let probe = installClarificationJob()
        let result = await client().generateConsentedRemotePlan(
            description: "Someone approaches.", markedObjects: [], anchors: .empty, state: nil
        )
        XCTAssertNil(result)
        XCTAssertTrue(probe.answers.isEmpty)
        XCTAssertEqual(probe.deleteCount, 1)
        XCTAssertEqual(probe.createCount, 1)
    }

    @MainActor
    func testRemoteClarificationRejectsUnknownOptionBeforePost() async {
        let probe = installClarificationJob()
        let result = await client().generateConsentedRemotePlan(
            description: "Someone approaches.", markedObjects: [], anchors: .empty, state: nil,
            clarificationHandler: { _ in .choice("unobserved-choice") }
        )
        XCTAssertNil(result)
        XCTAssertTrue(probe.answers.isEmpty)
        XCTAssertEqual(probe.deleteCount, 1)
    }

    @MainActor
    func testCancelledRemoteQuestionRejectsLateAnswerAndDeletesSameJob() async {
        let probe = installClarificationJob()
        let presented = expectation(description: "question presented")
        var answerContinuation: CheckedContinuation<SceneClarificationAnswer?, Never>?
        let provider = client()
        let task = Task {
            await provider.generateConsentedRemotePlan(
                description: "Someone approaches.", markedObjects: [], anchors: .empty, state: nil,
                clarificationHandler: { _ in
                    await withCheckedContinuation { continuation in
                        answerContinuation = continuation
                        presented.fulfill()
                    }
                }
            )
        }
        await fulfillment(of: [presented], timeout: 3)
        task.cancel()
        answerContinuation?.resume(returning: .choice("second"))
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertTrue(probe.answers.isEmpty)
        XCTAssertEqual(probe.deleteCount, 1)
        XCTAssertEqual(probe.createCount, 1)
    }

    private final class TransferTokenProbe: SceneServiceTokenProviding, @unchecked Sendable {
        private let lock = NSLock()
        private var acquisitions = 0
        var callCount: Int { lock.withLock { acquisitions } }
        func currentServiceToken() async -> String? {
            lock.withLock { acquisitions += 1 }
            return "test-token"
        }
    }

    @MainActor
    func testMissingPolicyStopsBeforeConsentEnrollmentAndContentTransport() async {
        let tokens = TransferTokenProbe()
        var prompts = 0
        let outcome = await client(tokenProvider: tokens, withTransferPolicy: false).generateRemotePlanOutcome(
            description: "Private scene text.", markedObjects: [], anchors: .empty, state: nil,
            clarificationHandler: nil, transferConsentHandler: { request in prompts += 1; return request.approval }
        )
        guard case .failed(.transferPolicyUnavailable) = outcome else { return XCTFail("Incomplete policy must remain a typed failure") }
        XCTAssertEqual(prompts, 0)
        XCTAssertEqual(tokens.callCount, 0)
        XCTAssertEqual(SceneClientStub.callCount, 0)
    }

    @MainActor
    func testNoHandlerDeclineAndMismatchedApprovalNeverAcquireTokenOrSubmitContent() async {
        let tokens = TransferTokenProbe()
        let handlers: [SceneRemoteTransferConsentHandler?] = [
            nil, { _ in nil },
            { request in .init(requestID: UUID(), requestHash: request.requestHash, policyFingerprint: request.policyFingerprint) },
            { request in .init(requestID: request.requestID, requestHash: "different-content", policyFingerprint: request.policyFingerprint) },
            { request in .init(requestID: request.requestID, requestHash: request.requestHash, policyFingerprint: "different-policy") }
        ]
        for handler in handlers {
            let provider: RemoteScenePlanProvider = client(tokenProvider: tokens)
            let outcome = await provider.generateRemotePlanOutcome(
                description: "Private scene text.", markedObjects: [], anchors: .empty, state: nil,
                clarificationHandler: nil, transferConsentHandler: handler
            )
            guard case .failed(.transferDeclined) = outcome else { return XCTFail("No matching agreement must stop the transfer") }
        }
        XCTAssertEqual(tokens.callCount, 0)
        XCTAssertEqual(SceneClientStub.callCount, 0)
    }

    func testLegacyNoninteractiveEntryCannotSilentlyAuthorizeTransfer() async {
        let tokens = TransferTokenProbe()
        let result = await client(tokenProvider: tokens).generateRemotePlan(
            description: "Private scene text.", markedObjects: [], anchors: .empty, state: nil
        )
        XCTAssertNil(result)
        XCTAssertEqual(tokens.callCount, 0)
        XCTAssertEqual(SceneClientStub.callCount, 0)
    }

    @MainActor
    func testCancelledConsentRejectsLateApprovalWithoutEnrollmentOrCleanupRequest() async {
        let tokens = TransferTokenProbe()
        let presented = expectation(description: "transfer consent presented")
        var pending: CheckedContinuation<SceneRemoteTransferApproval?, Never>?
        var shown: SceneRemoteTransferRequest?
        let provider = client(tokenProvider: tokens)
        let task = Task {
            await provider.generateRemotePlanOutcome(
                description: "Private scene text.", markedObjects: [], anchors: .empty, state: nil,
                clarificationHandler: nil, transferConsentHandler: { request in
                    shown = request
                    return await withCheckedContinuation { continuation in
                        pending = continuation
                        presented.fulfill()
                    }
                }
            )
        }
        await fulfillment(of: [presented], timeout: 3)
        XCTAssertEqual(tokens.callCount, 0)
        XCTAssertEqual(SceneClientStub.callCount, 0)
        task.cancel()
        pending?.resume(returning: shown?.approval)
        _ = await task.value
        XCTAssertEqual(tokens.callCount, 0)
        XCTAssertEqual(SceneClientStub.callCount, 0)
    }

    @MainActor
    func testOneConsentCoversPollingAndClarificationOfOnlyItsOriginalJob() async throws {
        let probe = installClarificationJob()
        var consents: [SceneRemoteTransferRequest] = []
        let result = await client().generateRemotePlanOutcome(
            description: "MARA approaches the marked table.", markedObjects: [try fixtureMarker()],
            anchors: .empty, state: nil, clarificationHandler: { _ in .choice("second") },
            transferConsentHandler: { request in
                XCTAssertEqual(probe.createCount, 0)
                consents.append(request)
                return request.approval
            }
        )
        guard case .plan(let plan) = result else { return XCTFail("Explicit approval must reach the existing job pipeline") }
        XCTAssertEqual(consents.count, 1)
        XCTAssertEqual(probe.createCount, 1)
        XCTAssertEqual(probe.answers.count, 1)
        guard case .remoteService(let receipt)? = plan.generationContributors?.first else { return XCTFail("Missing job receipt") }
        XCTAssertEqual(receipt.requestID, consents.first?.requestID)
        XCTAssertEqual(receipt.requestHash, consents.first?.requestHash)
        XCTAssertEqual(consents.first?.scriptText, "MARA approaches the marked table.")
        XCTAssertEqual(consents.first?.markedObjectIDs, [try fixtureMarker().canonicalMarkedObjectID])
    }

    @MainActor
    func testEarlierConsentCannotAuthorizeANewJobEvenWithTheSameText() async {
        let tokens = TransferTokenProbe()
        let provider = client(tokenProvider: tokens)
        var oldApproval: SceneRemoteTransferApproval?
        _ = await provider.generateRemotePlanOutcome(
            description: "Same scene.", markedObjects: [], anchors: .empty, state: nil,
            clarificationHandler: nil, transferConsentHandler: { request in oldApproval = request.approval; return nil }
        )
        let result = await provider.generateRemotePlanOutcome(
            description: "Same scene.", markedObjects: [], anchors: .empty, state: nil,
            clarificationHandler: nil, transferConsentHandler: { _ in oldApproval }
        )
        guard case .failed(.transferDeclined) = result else { return XCTFail("Each new job requires its own approval") }
        XCTAssertEqual(tokens.callCount, 0)
        XCTAssertEqual(SceneClientStub.callCount, 0)
    }

    func testInvalidJobIDsAreRejectedBeforeTransport() async throws {
        let answer = clarificationAnswer()
        let invalidJobIDs = [
            "",
            "Ajob_demo001",
            "job.demo001",
            "job/demo001",
            "job..demo001",
            "job_demo001\n",
            "éjob_demo001",
            String(repeating: "a", count: 129)
        ]

        for jobID in invalidJobIDs {
            SceneClientStub.reset()
            let invalidClient = client()
            await assertRejected(expected: .invalidJobID) {
                _ = try await invalidClient.pollJob(jobID: jobID)
            }
            XCTAssertEqual(SceneClientStub.callCount, 0)
            await assertRejected(expected: .invalidJobID) {
                _ = try await invalidClient.answerClarification(
                    jobID: jobID,
                    answer: answer,
                    idempotencyKey: "idem.answer"
                )
            }
            XCTAssertEqual(SceneClientStub.callCount, 0)
            await assertRejected(expected: .invalidJobID) {
                _ = try await invalidClient.cancelJob(jobID: jobID)
            }
            XCTAssertEqual(SceneClientStub.callCount, 0)
        }
    }

    func testInvalidIdempotencyKeysAreRejectedBeforeTransport() async throws {
        let body = try createBody()
        let answer = clarificationAnswer()
        let invalidKeys = [
            "",
            "bad key",
            "bad/key",
            "bad\nkey",
            "токен",
            String(repeating: "a", count: 129)
        ]

        for idempotencyKey in invalidKeys {
            SceneClientStub.reset()
            let invalidClient = client()
            await assertRejected(expected: .invalidIdempotencyKey) {
                _ = try await invalidClient.createJob(
                    body: body,
                    idempotencyKey: idempotencyKey
                )
            }
            XCTAssertEqual(SceneClientStub.callCount, 0)
            await assertRejected(expected: .invalidIdempotencyKey) {
                _ = try await invalidClient.answerClarification(
                    jobID: "job_demo001",
                    answer: answer,
                    idempotencyKey: idempotencyKey
                )
            }
            XCTAssertEqual(SceneClientStub.callCount, 0)
        }
    }

    func testCreateBindingMismatchIsRejectedWithoutReturningStatus() async throws {
        let body = try createBody()
        let mismatches: [(String, Any, SceneGenerationClientError)] = [
            ("request_id", UUID().uuidString, .responseBindingMismatch),
            ("request_hash", String(repeating: "b", count: 64), .responseBindingMismatch),
            ("schema_version_backend", "scene-api-v2", .rejected(.unknownBackendSchemaVersion)),
            ("model_version", "scene-model-v2", .responseBindingMismatch),
            ("prompt_version", "scene-prompt-v2", .responseBindingMismatch),
            ("provider_name", "other-provider", .responseBindingMismatch),
            ("provider_version", "2026-09-02", .responseBindingMismatch),
            ("idempotency_key", "idem.other", .responseBindingMismatch)
        ]

        for (field, value, expectedError) in mismatches {
            SceneClientStub.reset()
            SceneClientStub.handler = { request in
                (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 201,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    try self.responseData(
                        fixture: "job-valid-pending.json",
                        request: body,
                        idempotencyKey: "idem.create",
                        overrides: [field: value]
                    )
                )
            }
            await assertRejected(expected: expectedError) {
                _ = try await client().createJob(body: body, idempotencyKey: "idem.create")
            }
            XCTAssertEqual(SceneClientStub.callCount, 1)
        }
    }

    func testPollBindingMismatchStopsBeforeFollowupPoll() async throws {
        let body = try createBody()
        let idempotencyKey = "idem.create"
        let mismatches: [(String, Any)] = [
            ("job_id", "job_other001"),
            ("request_id", UUID().uuidString),
            ("request_hash", String(repeating: "b", count: 64)),
            ("model_version", "scene-model-v2"),
            ("provider_name", "other-provider"),
            ("idempotency_key", "idem.other")
        ]

        for (field, value) in mismatches {
            SceneClientStub.reset()
            let response = try responseData(
                fixture: "job-valid-pending.json",
                request: body,
                idempotencyKey: idempotencyKey,
                overrides: [field: value]
            )
            SceneClientStub.handler = { request in
                (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    response
                )
            }
            await assertRejected(expected: .responseBindingMismatch) {
                _ = try await client(maximumPolls: 2).pollToTerminal(
                    jobID: "job_demo001",
                    expectedRequest: body,
                    originalCreateIdempotencyKey: idempotencyKey
                )
            }
            XCTAssertEqual(SceneClientStub.callCount, 1)
        }
    }

    func testAnswerAndCancelBindingMismatchesAreRejected() async throws {
        let answer = clarificationAnswer()
        let wrongJobResponse = try responseData(
            fixture: "job-valid-pending.json",
            requestID: answer.requestID,
            overrides: ["job_id": "job_other001"]
        )
        SceneClientStub.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                wrongJobResponse
            )
        }
        await assertRejected(expected: .responseBindingMismatch) {
            _ = try await client().answerClarification(
                jobID: "job_demo001",
                answer: answer,
                idempotencyKey: "idem.answer"
            )
        }
        XCTAssertEqual(SceneClientStub.callCount, 1)

        SceneClientStub.reset()
        let wrongAnswerRequestResponse = try responseData(
            fixture: "job-valid-pending.json"
        )
        SceneClientStub.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                wrongAnswerRequestResponse
            )
        }
        await assertRejected(expected: .responseBindingMismatch) {
            _ = try await client().answerClarification(
                jobID: "job_demo001",
                answer: answer,
                idempotencyKey: "idem.answer"
            )
        }
        XCTAssertEqual(SceneClientStub.callCount, 1)

        SceneClientStub.reset()
        let wrongCancelJobResponse = try responseData(
            fixture: "job-valid-cancelled.json",
            overrides: ["job_id": "job_other001"]
        )
        SceneClientStub.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                wrongCancelJobResponse
            )
        }
        await assertRejected(expected: .responseBindingMismatch) {
            _ = try await client().cancelJob(jobID: "job_demo001")
        }
        XCTAssertEqual(SceneClientStub.callCount, 1)
    }

    func testAdmissionRejectsInvalidEndpointAndAuthBeforeTransport() async throws {
        let body = try createBody()
        let answer = clarificationAnswer()
        let invalidEndpoints: [URL] = [
            SceneGenerationClientConfiguration.placeholder.baseURL,
            URL(string: "https://scene-generation.set-os.local/other")!,
            URL(string: "https://scene-generation.set-os.local./v1")!,
            URL(string: "http://scene.example.test/v1")!,
            URL(string: "/v1")!,
            URL(string: "https://user:pass@scene.example.test/v1")!,
            URL(string: "https://scene.example.test/v1?mode=test")!,
            URL(string: "https://scene.example.test/v1#fragment")!
        ]

        for endpoint in invalidEndpoints {
            SceneClientStub.reset()
            let invalidClient = client(baseURL: endpoint)
            await assertRejected(expected: .invalidEndpoint) {
                _ = try await invalidClient.createJob(body: body, idempotencyKey: "idem.invalid")
            }
            XCTAssertEqual(SceneClientStub.callCount, 0)
            await assertRejected(expected: .invalidEndpoint) {
                _ = try await invalidClient.pollJob(jobID: "job_demo001")
            }
            XCTAssertEqual(SceneClientStub.callCount, 0)
            await assertRejected(expected: .invalidEndpoint) {
                _ = try await invalidClient.answerClarification(
                    jobID: "job_demo001",
                    answer: answer,
                    idempotencyKey: "idem.invalid"
                )
            }
            XCTAssertEqual(SceneClientStub.callCount, 0)
            await assertRejected(expected: .invalidEndpoint) {
                _ = try await invalidClient.cancelJob(jobID: "job_demo001")
            }
            XCTAssertEqual(SceneClientStub.callCount, 0)
        }

        for (token, expected) in [
            (nil, SceneGenerationClientError.missingServiceToken),
            ("", .invalidServiceToken),
            ("bad token", .invalidServiceToken),
            ("abc=def", .invalidServiceToken),
            ("тoken", .invalidServiceToken)
        ] as [(String?, SceneGenerationClientError)] {
            SceneClientStub.reset()
            let invalidClient = client(token: token)
            await assertRejected(expected: expected) {
                _ = try await invalidClient.createJob(body: body, idempotencyKey: "idem.invalid")
            }
            XCTAssertEqual(SceneClientStub.callCount, 0)
            await assertRejected(expected: expected) {
                _ = try await invalidClient.pollJob(jobID: "job_demo001")
            }
            XCTAssertEqual(SceneClientStub.callCount, 0)
            await assertRejected(expected: expected) {
                _ = try await invalidClient.answerClarification(
                    jobID: "job_demo001",
                    answer: answer,
                    idempotencyKey: "idem.invalid"
                )
            }
            XCTAssertEqual(SceneClientStub.callCount, 0)
            await assertRejected(expected: expected) {
                _ = try await invalidClient.cancelJob(jobID: "job_demo001")
            }
            XCTAssertEqual(SceneClientStub.callCount, 0)
        }
    }

    func testUnauthorizedCreateRetriesSamePayloadAndIdempotencyAfterTokenRotation() async throws {
        let body = try createBody()
        let idempotencyKey = "idem.rotation.create"
        let response = try responseData(fixture: "job-valid-pending.json", request: body, idempotencyKey: idempotencyKey)
        let tokens = RenewalTokenProvider(replacement: "renewed-token")
        var payloads: [Data] = []
        var keys: [String?] = []
        var authorizations: [String?] = []
        SceneClientStub.handler = { request in
            payloads.append(try self.bodyData(from: request))
            keys.append(request.value(forHTTPHeaderField: "Idempotency-Key"))
            authorizations.append(request.value(forHTTPHeaderField: "Authorization"))
            let rejected = request.value(forHTTPHeaderField: "Authorization") == "Bearer initial-token"
            return (HTTPURLResponse(url: request.url!, statusCode: rejected ? 401 : 201,
                                    httpVersion: nil, headerFields: nil)!, rejected ? Data("{}".utf8) : response)
        }
        let status = try await client(tokenProvider: tokens).createJob(body: body, idempotencyKey: idempotencyKey)
        XCTAssertEqual(status.requestID, body.requestID)
        XCTAssertEqual(SceneClientStub.callCount, 2)
        XCTAssertEqual(payloads.count, 2)
        XCTAssertEqual(payloads.first, payloads.last)
        XCTAssertEqual(keys, [idempotencyKey, idempotencyKey])
        XCTAssertEqual(authorizations, ["Bearer initial-token", "Bearer renewed-token"])
        let rejected = await tokens.rejections
        XCTAssertEqual(rejected, ["initial-token"])
    }

    func testUnauthorizedExistingJobOperationsKeepJobAndAnswerOnRetry() async throws {
        let pending = try jobStatus("job-valid-pending.json")
        let answer = SceneClarificationAPIPayload(clarificationID: "clarification_demo001",
                                                 requestID: pending.requestID, epoch: 0,
                                                 selectedOptionID: "option_demo001", freeText: nil)
        for operation in 0..<3 {
            SceneClientStub.reset()
            let tokens = RenewalTokenProvider(replacement: "renewed-token")
            let response = try responseData(fixture: operation == 2 ? "job-valid-cancelled.json" : "job-valid-pending.json")
            var paths: [String?] = []
            var payloads: [Data] = []
            SceneClientStub.handler = { request in
                paths.append(request.url?.path)
                if operation == 1 { payloads.append(try self.bodyData(from: request)) }
                let rejected = request.value(forHTTPHeaderField: "Authorization") == "Bearer initial-token"
                return (HTTPURLResponse(url: request.url!, statusCode: rejected ? 401 : 200,
                                        httpVersion: nil, headerFields: nil)!, rejected ? Data("{}".utf8) : response)
            }
            let sut = client(tokenProvider: tokens)
            switch operation {
            case 0: _ = try await sut.pollJob(jobID: pending.jobID)
            case 1: _ = try await sut.answerClarification(jobID: pending.jobID, answer: answer, idempotencyKey: "idem.answer")
            default: _ = try await sut.cancelJob(jobID: pending.jobID)
            }
            XCTAssertEqual(SceneClientStub.callCount, 2)
            XCTAssertEqual(paths.first, paths.last)
            if operation == 1 {
                XCTAssertEqual(payloads.count, 2)
                XCTAssertEqual(payloads.first, payloads.last)
            }
        }
    }

    func testAuthenticationRecoveryIsBoundedAndNeverReusesRejectedToken() async throws {
        for replacement in [nil, "initial-token", "invalid token", "renewed-token"] as [String?] {
            SceneClientStub.reset()
            let tokens = RenewalTokenProvider(replacement: replacement)
            SceneClientStub.handler = { request in
                (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
            }
            await assertRejected(expected: .jobFailed(.providerError)) {
                _ = try await client(tokenProvider: tokens).pollJob(jobID: "job_demo001")
            }
            XCTAssertEqual(SceneClientStub.callCount, replacement == "renewed-token" ? 2 : 1)
            let rejected = await tokens.rejections
            XCTAssertEqual(rejected.count, 1)
        }
    }
}

private actor RenewalTokenProvider: SceneServiceTokenProviding {
    let replacement: String?
    private(set) var rejections: [String] = []
    init(replacement: String?) { self.replacement = replacement }
    func currentServiceToken() async -> String? { "initial-token" }
    func replacementServiceToken(afterRejecting token: String) async -> String? {
        rejections.append(token)
        return replacement
    }
}

private struct StaticTokenProvider: SceneServiceTokenProviding {
    let token: String?
    func currentServiceToken() async -> String? { token }
}

private final class SceneClientStub: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)
    static var handler: Handler?
    nonisolated(unsafe) static var callCount = 0

    static func reset() {
        handler = nil
        callCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.callCount += 1
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension SceneGenerationClient {
    func generateConsentedRemotePlan(
        description: String, markedObjects: [MarkedObject], anchors: SourceAnchorBundle,
        state: SceneChunkState?, clarificationHandler: SceneRemoteClarificationHandler? = nil
    ) async -> ScenePlanProviderResult? {
        guard case .plan(let plan) = await generateRemotePlanOutcome(
            description: description, markedObjects: markedObjects, anchors: anchors,
            state: state, clarificationHandler: clarificationHandler,
            transferConsentHandler: { $0.approval }
        ) else { return nil }
        return plan
    }
}
