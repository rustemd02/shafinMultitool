import XCTest
import CryptoKit
@testable import shafinMultitool

private final class AttestTransportURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var responder: ((URLRequest) throws -> (Int, Data))?

    static func install(_ value: ((URLRequest) throws -> (Int, Data))?) {
        lock.lock()
        responder = value
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "attest-transport.example"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let response = Self.responder
        Self.lock.unlock()
        do {
            guard let response else { throw URLError(.unsupportedURL) }
            let (status, data) = try response(request)
            let http = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

final class AppAttestTransportTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AttestTransportURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        AttestTransportURLProtocol.install(nil)
        super.tearDown()
    }

    private func transport() -> URLSessionAppAttestEnrollmentTransport {
        URLSessionAppAttestEnrollmentTransport(
            baseURL: URL(string: "https://attest-transport.example/proxy/v1")!, session: session
        )
    }

    func testChallengeUsesCanonicalAPIRoot() async throws {
        let challenge = Data(repeating: 0x31, count: 32)
        AttestTransportURLProtocol.install { request in
            XCTAssertEqual(request.url?.path, "/proxy/v1/attest/challenge")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (200, try JSONSerialization.data(withJSONObject: [
                "challenge": challenge.base64EncodedString(), "expires_at": "2099-01-02T03:04:05.123456+00:00"
            ]))
        }
        let result = try await transport().requestChallenge()
        XCTAssertEqual(result.challenge, challenge)
        let expected = ISO8601DateFormatter()
        expected.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(result.expiresAt, expected.date(from: "2099-01-02T03:04:05.123456Z"))
    }

    func testChallengeAcceptsWholeSecondsAndRejectsMissingOrMalformedExpiration() async throws {
        let challenge = Data(repeating: 0x31, count: 32).base64EncodedString()
        AttestTransportURLProtocol.install { _ in
            (200, try JSONSerialization.data(withJSONObject: ["challenge": challenge, "expires_at": "2099-01-02T03:04:05Z"]))
        }
        let valid = try await transport().requestChallenge()
        XCTAssertEqual(valid.expiresAt, ISO8601DateFormatter().date(from: "2099-01-02T03:04:05Z"))
        for expiry in [nil, "", "not-a-date", "NaN", "Infinity"] as [String?] {
            AttestTransportURLProtocol.install { _ in
                var body = ["challenge": challenge]
                body["expires_at"] = expiry
                return (200, try JSONSerialization.data(withJSONObject: body))
            }
            do {
                _ = try await transport().requestChallenge()
                XCTFail("Malformed challenge expiration must fail closed")
            } catch {
                XCTAssertEqual(error as? AppAttestEnrollmentError, .malformedChallenge)
            }
        }
    }

    func testEnrollmentUsesCanonicalAPIRootAndBoundProof() async throws {
        let proof = Data(repeating: 0x44, count: 64)
        let key = Data(repeating: 0x22, count: 32)
        let challenge = Data(repeating: 0x33, count: 32)
        let hash = Data(SHA256.hash(data: challenge))
        AttestTransportURLProtocol.install { request in
            XCTAssertEqual(request.url?.path, "/proxy/v1/attest/enroll")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try Self.body(request)
            XCTAssertEqual(body["key_id"], key.base64EncodedString())
            XCTAssertEqual(body["challenge"], challenge.base64EncodedString())
            XCTAssertEqual(body["client_data_hash"], hash.base64EncodedString())
            XCTAssertEqual(body["attestation_object"], proof.base64EncodedString())
            XCTAssertNil(body["assertion_object"])
            return (201, Data(#"{"token":"enrolled-token","token_ttl_seconds":120}"#.utf8))
        }
        let result = try await transport().enroll(keyID: key, clientDataHash: hash,
                                                 challenge: challenge, attestationObject: proof)
        XCTAssertEqual(result.token, "enrolled-token")
        XCTAssertEqual(result.ttlSeconds, 120)
    }

    func testRefreshUsesAssertionAndSameVersionedRoot() async throws {
        let proof = Data(repeating: 0x55, count: 64)
        let key = Data(repeating: 0x22, count: 32)
        let challenge = Data(repeating: 0x33, count: 32)
        let hash = Data(SHA256.hash(data: challenge))
        AttestTransportURLProtocol.install { request in
            XCTAssertEqual(request.url?.path, "/proxy/v1/attest/refresh")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try Self.body(request)
            XCTAssertEqual(body["key_id"], key.base64EncodedString())
            XCTAssertEqual(body["challenge"], challenge.base64EncodedString())
            XCTAssertEqual(body["client_data_hash"], hash.base64EncodedString())
            XCTAssertEqual(body["assertion_object"], proof.base64EncodedString())
            XCTAssertNil(body["attestation_object"])
            return (200, Data(#"{"token":"renewed-token","token_ttl_seconds":120}"#.utf8))
        }
        let result = try await transport().refresh(keyID: key, clientDataHash: hash,
                                                  challenge: challenge, assertionObject: proof)
        XCTAssertEqual(result.token, "renewed-token")
        XCTAssertEqual(result.ttlSeconds, 120)
    }

    func testRefreshRejectsServerFailure() async {
        AttestTransportURLProtocol.install { _ in (401, Data("{}".utf8)) }
        do {
            _ = try await transport().refresh(keyID: Data(), clientDataHash: Data(),
                                             challenge: Data(), assertionObject: Data())
            XCTFail("rejected identity must not obtain a token")
        } catch {
            XCTAssertEqual(error as? AppAttestEnrollmentError, .rejected)
        }
    }

    func testOnlyExplicitMissingInstallationCodePermitsRecovery() async {
        for (payload, expected) in [
            (#"{"detail":"Not Found"}"#, AppAttestEnrollmentError.rejected),
            (#"{"code":"installation_not_enrolled"}"#, AppAttestEnrollmentError.installationNotEnrolled)
        ] {
            AttestTransportURLProtocol.install { _ in (404, Data(payload.utf8)) }
            do {
                _ = try await transport().refresh(keyID: Data(), clientDataHash: Data(),
                                                 challenge: Data(), assertionObject: Data())
                XCTFail("missing installation is not a successful refresh")
            } catch {
                XCTAssertEqual(error as? AppAttestEnrollmentError, expected)
            }
        }
    }

    private static func body(_ request: URLRequest) throws -> [String: String] {
        let data: Data
        if let body = request.httpBody {
            data = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var result = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
                if count == 0 { break }
                result.append(buffer, count: count)
            }
            data = result
        } else {
            throw URLError(.zeroByteResource)
        }
        return try JSONDecoder().decode([String: String].self, from: data)
    }
}
