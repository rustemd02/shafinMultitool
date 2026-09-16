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
        token: String? = "test-token"
    ) -> SceneGenerationClient {
        var configuration = SceneGenerationClientConfiguration.placeholder
        configuration.baseURL = baseURL
        configuration.pollIntervalSeconds = 0
        configuration.maximumPolls = maximumPolls
        return SceneGenerationClient(
            configuration: configuration,
            session: session,
            tokenProvider: StaticTokenProvider(token: token)
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
            )!, Data())
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
        let result = await provider.generateRemotePlan(
            description: "MARA approaches the marked table.",
            markedObjects: [],
            anchors: SourceAnchorBundle.empty,
            state: nil
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.reasonCodes, ["remote_plan_used"])
        XCTAssertEqual(result?.usedLegacySceneScriptBridge, true)
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
