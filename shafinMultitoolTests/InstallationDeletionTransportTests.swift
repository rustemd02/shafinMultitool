import Foundation
import XCTest
@testable import shafinMultitool

private final class DeletionTransportURLProtocol: URLProtocol, @unchecked Sendable {
    struct Reply {
        let status: Int
        let data: Data
        var contentType = "application/json"
        var contentLength: String? = nil
    }
    private static let lock = NSLock()
    private static var responder: ((URLRequest) throws -> Reply?)?
    private static var stopped: (() -> Void)?
    private static var requests = 0

    static func install(stopped: (() -> Void)? = nil, responder: ((URLRequest) throws -> Reply?)?) {
        lock.lock()
        Self.responder = responder
        Self.stopped = stopped
        requests = 0
        lock.unlock()
    }
    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }
    // Catch every URL in this ephemeral test session, including a routing bug;
    // tests can never escape to DNS or a real service.
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let responder = Self.responder
        Self.requests += 1
        Self.lock.unlock()
        do {
            guard let responder else { throw URLError(.unsupportedURL) }
            guard let reply = try responder(request) else { return }
            var headers = ["Content-Type": reply.contentType]
            if let length = reply.contentLength { headers["Content-Length"] = length }
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                           httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {
        Self.lock.lock()
        let stopped = Self.stopped
        Self.lock.unlock()
        stopped?()
    }
}

final class InstallationDeletionTransportTests: XCTestCase {
    private var session: URLSession!
    private let operation = "123e4567-e89b-42d3-a456-426614174000"
    private let policy = String(repeating: "a", count: 64)
    private let key = Data(repeating: 0x22, count: 32)
    private let challenge = Data(repeating: 0x33, count: 32)

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeletionTransportURLProtocol.self]
        session = URLSession(configuration: configuration)
    }
    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        DeletionTransportURLProtocol.install(responder: nil)
        super.tearDown()
    }
    private func transport(baseURL: String = "https://deletion-transport.invalid/proxy/v1") -> URLSessionInstallationDeletionTransport {
        URLSessionInstallationDeletionTransport(baseURL: URL(string: baseURL)!, session: session)
    }
    private func proof() -> InstallationDeletionProof {
        InstallationDeletionProof(operationID: operation, keyID: key.base64EncodedString(),
                                  challenge: challenge.base64EncodedString(), policySHA256: policy,
                                  receiptSecretSHA256: String(repeating: "b", count: 64),
                                  assertionObject: Data("FIXTURE-ASSERTION".utf8).base64EncodedString())
    }
    private func receiptDocument(status: String = "deleting") -> [String: Any] {
        ["operation_id": operation, "status": status, "policy_sha256": policy,
         "receipt_expires_at": "2099-01-02T03:04:05Z",
         "scope": "local_scene_content_and_auth_material", "policy_qualification": "not_asserted",
         "retained_categories": ["security_identity_and_replay_state", "job_quota_idempotency_metadata", "provider_spend_records"]]
    }
    private func challengeDocument() -> [String: Any] {
        ["challenge": challenge.base64EncodedString(), "expires_at": "2099-01-02T03:04:05.123456+00:00",
         "policy_sha256": policy, "policy_qualification": "not_asserted"]
    }
    private func data(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
    private static func body(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            output.append(buffer, count: count)
        }
        return output
    }
    private func expect(_ expected: InstallationDeletionError,
                        operation: () async throws -> Void,
                        file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected \(expected)", file: file, line: line) }
        catch { XCTAssertEqual(error as? InstallationDeletionError, expected, file: file, line: line) }
    }

    func testChallengeBindsExistingKeyAndPreservesVersionedProxyPrefixWithoutBearer() async throws {
        let document = try data(challengeDocument())
        DeletionTransportURLProtocol.install { request in
            XCTAssertEqual(request.url?.path, "/proxy/v1/attest/deletion-challenge")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(request.timeoutInterval, 15)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: Self.body(request)) as? [String: String])
            XCTAssertEqual(fields, ["key_id": self.key.base64EncodedString(), "operation_id": self.operation, "policy_sha256": self.policy])
            return .init(status: 200, data: document)
        }
        let result = try await transport().requestChallenge(keyID: key, operationID: operation, policySHA256: policy)
        XCTAssertEqual(result.challenge, challenge)
        XCTAssertEqual(result.policySHA256, policy)
        XCTAssertGreaterThan(result.expiresAt, Date())
        XCTAssertEqual(DeletionTransportURLProtocol.requestCount, 1)
    }

    func testSubmitTransmitsExactPersistedProofAndNoServiceCredential() async throws {
        let proof = proof()
        let expected = try proof.encodedBody()
        let document = try data(receiptDocument())
        DeletionTransportURLProtocol.install { request in
            XCTAssertEqual(request.url?.path, "/proxy/v1/attest/deletions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(try Self.body(request), expected)
            return .init(status: 202, data: document)
        }
        let result = try await transport().submit(proof)
        XCTAssertEqual(result.status, "deleting")
        XCTAssertEqual(result.operationID, operation)
        XCTAssertEqual(DeletionTransportURLProtocol.requestCount, 1)
    }

    func testExactReplayMayReturn200WhileDeletionIsStillPending() async throws {
        let document = try data(receiptDocument())
        DeletionTransportURLProtocol.install { _ in .init(status: 200, data: document) }
        let result = try await transport().submit(proof())
        XCTAssertEqual(result.status, "deleting")
    }

    func testReceiptUsesOnlyScopedReceiptCapability() async throws {
        let secret = Data(repeating: 0x66, count: 32)
        let document = try data(receiptDocument(status: "complete"))
        DeletionTransportURLProtocol.install { request in
            XCTAssertEqual(request.url?.path, "/proxy/v1/attest/deletions/" + self.operation)
            XCTAssertNil(request.url?.query)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.httpBody)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "DeletionReceipt " + secret.base64EncodedString())
            return .init(status: 200, data: document)
        }
        let result = try await transport().receipt(operationID: operation, secret: secret, policySHA256: policy)
        XCTAssertEqual(result.status, "complete")
        XCTAssertEqual(result.retainedCategories.count, 3)
    }

    func testMissingOrExpiredReceiptIsNeverReportedAsSuccessfulDeletion() async throws {
        let secret = Data(repeating: 0x66, count: 32)
        DeletionTransportURLProtocol.install { _ in .init(status: 404, data: Data("{}".utf8)) }
        await expect(.receiptUnavailable) { _ = try await self.transport().receipt(operationID: self.operation, secret: secret, policySHA256: self.policy) }
        var expired = receiptDocument(status: "complete")
        expired["receipt_expires_at"] = "2000-01-02T03:04:05Z"
        let bytes = try data(expired)
        DeletionTransportURLProtocol.install { _ in .init(status: 200, data: bytes) }
        await expect(.receiptUnavailable) { _ = try await self.transport().receipt(operationID: self.operation, secret: secret, policySHA256: self.policy) }
    }

    func testReceiptRejectsMismatchedBindingScopeStatusCategoriesAndUnknownFields() async throws {
        let changes: [(String, Any?)] = [
            ("operation_id", "123e4567-e89b-42d3-a456-426614174001"),
            ("policy_sha256", String(repeating: "b", count: 64)), ("status", "unknown"),
            ("scope", "all_data_erased"), ("policy_qualification", "passed"),
            ("retained_categories", []),
            ("retained_categories", ["security_identity_and_replay_state", "security_identity_and_replay_state", "provider_spend_records"]),
            ("receipt_expires_at", "not-a-date"), ("extra", true), ("scope", nil)
        ]
        for (field, value) in changes {
            var document = receiptDocument()
            document[field] = value
            let bytes = try data(document)
            DeletionTransportURLProtocol.install { _ in .init(status: 200, data: bytes) }
            await expect(.malformedResponse) { _ = try await self.transport().submit(self.proof()) }
        }
    }

    func testChallengeRejectsNoncanonicalBase64ExpiryAndPolicy() async throws {
        let changes: [(String, Any?)] = [
            ("challenge", String(challenge.base64EncodedString().dropLast(2)) + "N="),
            ("challenge", challenge.base64EncodedString() + "\n"),
            ("challenge", Data(repeating: 1, count: 31).base64EncodedString()),
            ("expires_at", nil), ("expires_at", "2000-01-02T03:04:05Z"),
            ("policy_sha256", String(repeating: "b", count: 64)),
            ("policy_qualification", "passed"), ("extra", true)
        ]
        for (field, value) in changes {
            var document = challengeDocument()
            document[field] = value
            let bytes = try data(document)
            DeletionTransportURLProtocol.install { _ in .init(status: 200, data: bytes) }
            await expect(.malformedResponse) { _ = try await self.transport().requestChallenge(keyID: self.key, operationID: self.operation, policySHA256: self.policy) }
        }
    }

    func testInvalidRequestDoesNotContactAnyEndpoint() async {
        DeletionTransportURLProtocol.install { _ in XCTFail("Invalid input reached transport"); return nil }
        await expect(.invalidRequest) { _ = try await self.transport().requestChallenge(keyID: Data(), operationID: self.operation, policySHA256: self.policy) }
        await expect(.invalidRequest) { _ = try await self.transport().receipt(operationID: self.operation.uppercased(), secret: self.key, policySHA256: self.policy) }
        await expect(.invalidRequest) { _ = try await self.transport().receipt(operationID: self.operation, secret: Data(), policySHA256: self.policy) }
        for url in ["http://deletion-transport.invalid/v1", "https://user:pass@deletion-transport.invalid/v1", "https://deletion-transport.invalid/v1?x=1", "https://deletion-transport.invalid/unversioned"] {
            await expect(.invalidRequest) { _ = try await self.transport(baseURL: url).submit(self.proof()) }
        }
        XCTAssertEqual(DeletionTransportURLProtocol.requestCount, 0)
    }

    func testRejectionsNeverRetryAndPolicyMismatchIsSpecific() async throws {
        let cases: [(Int, String, InstallationDeletionError)] = [
            (400, "invalid_request", .invalidRequest), (401, "unauthorized", .rejected),
            (403, "unauthorized", .rejected), (302, "redirect", .rejected),
            (409, "policy_mismatch", .policyMismatch), (409, "other_conflict", .rejected),
            (429, "rate_limit", .transport), (503, "deletion_unavailable", .transport)
        ]
        for (status, code, expected) in cases {
            let bytes = try data(["code": code])
            DeletionTransportURLProtocol.install { _ in .init(status: status, data: bytes) }
            await expect(expected) { _ = try await self.transport().submit(self.proof()) }
            XCTAssertEqual(DeletionTransportURLProtocol.requestCount, 1)
        }
    }

    func testOversizedDeclaredAndStreamedResponsesAreRejected() async {
        for reply in [DeletionTransportURLProtocol.Reply(status: 200, data: Data(repeating: 32, count: 16_385)),
                      .init(status: 200, data: Data("{}".utf8), contentLength: "999999999")] {
            DeletionTransportURLProtocol.install { _ in reply }
            await expect(.malformedResponse) { _ = try await self.transport().submit(self.proof()) }
        }
    }

    func testSuccessRequiresJSONAnd202CannotClaimCompletion() async throws {
        let bytes = try data(receiptDocument(status: "complete"))
        DeletionTransportURLProtocol.install { _ in .init(status: 200, data: bytes, contentType: "text/html") }
        await expect(.malformedResponse) { _ = try await self.transport().submit(self.proof()) }
        DeletionTransportURLProtocol.install { _ in .init(status: 202, data: bytes) }
        await expect(.malformedResponse) { _ = try await self.transport().submit(self.proof()) }
    }

    func testCancellationStopsOwnedRequestWithoutRetry() async throws {
        let entered = expectation(description: "request started")
        let stopped = expectation(description: "request cancelled")
        stopped.assertForOverFulfill = false
        DeletionTransportURLProtocol.install(stopped: { stopped.fulfill() }) { _ in
            entered.fulfill()
            return nil
        }
        let transport = transport()
        let proof = proof()
        let task = Task { try await transport.submit(proof) }
        await fulfillment(of: [entered], timeout: 1)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation unexpectedly returned a receipt") }
        catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [stopped], timeout: 1)
        XCTAssertEqual(DeletionTransportURLProtocol.requestCount, 1)
    }
}
