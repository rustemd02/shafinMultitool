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

    override func setUp() {
        super.setUp()
        SceneClientStub.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SceneClientStub.self]
        session = URLSession(configuration: configuration)
    }

    private func client(maximumPolls: Int = 5) -> SceneGenerationClient {
        var configuration = SceneGenerationClientConfiguration.placeholder
        configuration.pollIntervalSeconds = 0
        configuration.maximumPolls = maximumPolls
        return SceneGenerationClient(configuration: configuration, session: session)
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

    func testCreateSendsIdempotencyKeyAndBearerToken() async throws {
        let pending = try jobStatus("job-valid-pending.json")
        SceneClientStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "Idempotency-Key"))
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer test-token"
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(pending)
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
                configuration.pollIntervalSeconds = 0
                return configuration
            }(),
            session: session,
            tokenProvider: StaticTokenProvider(token: "test-token")
        )
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
        let status = try await authed.createJob(body: body, idempotencyKey: "idem.test.001")
        XCTAssertEqual(status.jobID, pending.jobID)
    }

    func testPollToTerminalCompletes() async throws {
        let complete = try jobFixture("job-valid-complete.json")
        SceneClientStub.handler = { request in
            (HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!, complete)
        }
        let outcome = try await client().pollToTerminal(jobID: "job_demo001")
        guard case .complete(let result) = outcome else {
            return XCTFail("expected complete, got \(outcome)")
        }
        XCTAssertFalse(result.sceneScript.beats.isEmpty)
    }

    func testPollToTerminalSurfacesClarification() async throws {
        let awaiting = try jobFixture("job-valid-awaiting-clarification.json")
        SceneClientStub.handler = { request in
            (HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!, awaiting)
        }
        let outcome = try await client().pollToTerminal(jobID: "job_demo001")
        guard case .awaitingClarification(let payload) = outcome else {
            return XCTFail("expected clarification, got \(outcome)")
        }
        XCTAssertFalse(payload.options.isEmpty)
    }

    func testPollToTerminalSurfacesFailure() async throws {
        let failed = try jobFixture("job-valid-failed.json")
        SceneClientStub.handler = { request in
            (HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!, failed)
        }
        let outcome = try await client().pollToTerminal(jobID: "job_demo001")
        guard case .failed(let failure) = outcome else {
            return XCTFail("expected failed, got \(outcome)")
        }
        XCTAssertEqual(failure.code, .providerError)
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
            _ = try await client().pollToTerminal(jobID: "job_demo001")
            XCTFail("expected kill-switch abort")
        } catch let error as SceneGenerationClientError {
            XCTAssertEqual(error, .killSwitchEngaged)
        }
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
        let complete = try jobStatus("job-valid-complete.json")
        let pending = try jobStatus("job-valid-pending.json")
        SceneClientStub.handler = { request in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let isCreate = request.httpMethod == "POST"
                && request.url?.path.hasSuffix("/jobs") == true
            let payload = isCreate ? pending : complete
            return (HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!, try encoder.encode(payload))
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
}

private struct StaticTokenProvider: SceneServiceTokenProviding {
    let token: String
    func currentServiceToken() async -> String? { token }
}

private final class SceneClientStub: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)
    static var handler: Handler?
    nonisolated(unsafe) private static var callCount = 0

    static func reset() {
        handler = nil
        callCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
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
