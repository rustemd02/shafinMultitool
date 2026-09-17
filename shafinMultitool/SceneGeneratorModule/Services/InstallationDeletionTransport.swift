import Foundation

enum InstallationDeletionError: Error, Equatable {
    case unavailable
    case noInstallation
    case busy
    case secretStorage
    case invalidState
    case invalidRequest
    case malformedResponse
    case rejected
    case policyMismatch
    case receiptUnavailable
    case transport
}

struct InstallationDeletionChallenge: Equatable, Sendable {
    let challenge: Data
    let expiresAt: Date
    let policySHA256: String
}

struct InstallationDeletionProof: Codable, Equatable, Sendable {
    let version: Int
    let operationID: String
    let keyID: String
    let challenge: String
    let policySHA256: String
    let receiptSecretSHA256: String
    var assertionObject: String

    init(version: Int = 1, operationID: String, keyID: String, challenge: String,
         policySHA256: String, receiptSecretSHA256: String, assertionObject: String) {
        self.version = version
        self.operationID = operationID
        self.keyID = keyID
        self.challenge = challenge
        self.policySHA256 = policySHA256
        self.receiptSecretSHA256 = receiptSecretSHA256
        self.assertionObject = assertionObject
    }

    enum CodingKeys: String, CodingKey {
        case version
        case operationID = "operation_id"
        case keyID = "key_id"
        case challenge
        case policySHA256 = "policy_sha256"
        case receiptSecretSHA256 = "receipt_secret_sha256"
        case assertionObject = "assertion_object"
    }

    /// Matches app_attest_enrollment.canonical_deletion_data exactly. The
    /// assertion is deliberately excluded so this can be hashed before signing.
    func canonicalClientData() throws -> Data {
        guard version == 1,
              InstallationDeletionWire.isOperationID(operationID),
              InstallationDeletionWire.isSHA256(policySHA256),
              InstallationDeletionWire.isSHA256(receiptSecretSHA256),
              InstallationDeletionWire.base64(keyID, count: 32) != nil,
              InstallationDeletionWire.base64(challenge, count: 32) != nil else {
            throw InstallationDeletionError.invalidRequest
        }
        // Every value in this object is ASCII. No locale, slash escaping,
        // whitespace, URL normalization or Unicode transformation is applied.
        let value: [String: Any] = [
            "version": version,
            "purpose": "installation_delete",
            "method": "POST",
            "path": "/v1/attest/deletions",
            "operation_id": operationID,
            "key_id": keyID,
            "challenge": challenge,
            "policy_sha256": policySHA256,
            "receipt_secret_sha256": receiptSecretSHA256
        ]
        return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    func encodedBody() throws -> Data {
        _ = try canonicalClientData()
        guard let assertion = Data(base64Encoded: assertionObject),
              (1...4_096).contains(assertion.count),
              assertion.base64EncodedString() == assertionObject else {
            throw InstallationDeletionError.invalidRequest
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

struct InstallationDeletionReceipt: Codable, Equatable, Sendable {
    let operationID: String
    let status: String
    let policySHA256: String
    let receiptExpiresAt: Date
    let scope: String
    let policyQualification: String
    let retainedCategories: [String]

    static let expectedScope = "local_scene_content_and_auth_material"
    static let expectedRetainedCategories: Set<String> = [
        "security_identity_and_replay_state",
        "job_quota_idempotency_metadata",
        "provider_spend_records"
    ]

    enum CodingKeys: String, CodingKey {
        case operationID = "operation_id"
        case status
        case policySHA256 = "policy_sha256"
        case receiptExpiresAt = "receipt_expires_at"
        case scope
        case policyQualification = "policy_qualification"
        case retainedCategories = "retained_categories"
    }

    /// Structural validation also applies to persisted receipts. Expiration is
    /// checked separately for a fresh server response; it never proves erasure.
    func validate(operationID: String, policySHA256: String) throws {
        guard InstallationDeletionWire.isOperationID(operationID),
              InstallationDeletionWire.isSHA256(policySHA256),
              self.operationID == operationID, self.policySHA256 == policySHA256,
              status == "deleting" || status == "complete",
              receiptExpiresAt.timeIntervalSince1970.isFinite,
              scope == Self.expectedScope,
              policyQualification == "not_asserted",
              retainedCategories.count == Self.expectedRetainedCategories.count,
              Set(retainedCategories) == Self.expectedRetainedCategories else {
            throw InstallationDeletionError.malformedResponse
        }
    }
}

protocol InstallationDeletionTransport: Sendable {
    var serviceEndpoint: URL { get }
    func requestChallenge(keyID: Data, operationID: String, policySHA256: String) async throws -> InstallationDeletionChallenge
    func submit(_ proof: InstallationDeletionProof) async throws -> InstallationDeletionReceipt
    func receipt(operationID: String, secret: Data, policySHA256: String) async throws -> InstallationDeletionReceipt
}

struct URLSessionInstallationDeletionTransport: InstallationDeletionTransport {
    let serviceEndpoint: URL
    private let session: URLSession
    private static let maximumResponseBytes = 16_384
    private static let timeoutSeconds: TimeInterval = 15

    init(baseURL: URL, session: URLSession = .shared) {
        self.serviceEndpoint = baseURL
        self.session = session
    }

    func requestChallenge(keyID: Data, operationID: String, policySHA256: String) async throws -> InstallationDeletionChallenge {
        guard keyID.count == 32, InstallationDeletionWire.isOperationID(operationID),
              InstallationDeletionWire.isSHA256(policySHA256) else {
            throw InstallationDeletionError.invalidRequest
        }
        var request = try makeRequest(path: "attest/deletion-challenge", method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "key_id": keyID.base64EncodedString(), "operation_id": operationID, "policy_sha256": policySHA256
        ], options: [.sortedKeys, .withoutEscapingSlashes])
        let response = try await send(request)
        try requireStatus(response, allowed: [200])
        let fields = try InstallationDeletionWire.object(response.data, keys: [
            "challenge", "expires_at", "policy_sha256", "policy_qualification"
        ])
        guard let raw = fields["challenge"] as? String,
              let challenge = InstallationDeletionWire.base64(raw, count: 32),
              let rawExpiration = fields["expires_at"] as? String,
              let expiration = InstallationDeletionWire.date(rawExpiration), expiration > Date(),
              fields["policy_sha256"] as? String == policySHA256,
              fields["policy_qualification"] as? String == "not_asserted" else {
            throw InstallationDeletionError.malformedResponse
        }
        return InstallationDeletionChallenge(challenge: challenge, expiresAt: expiration, policySHA256: policySHA256)
    }

    func submit(_ proof: InstallationDeletionProof) async throws -> InstallationDeletionReceipt {
        var request = try makeRequest(path: "attest/deletions", method: "POST")
        request.httpBody = try proof.encodedBody()
        let response = try await send(request)
        try requireStatus(response, allowed: [200, 202])
        let receipt = try decodeReceipt(response.data, operationID: proof.operationID, policySHA256: proof.policySHA256)
        guard response.statusCode != 202 || receipt.status == "deleting" else {
            throw InstallationDeletionError.malformedResponse
        }
        return receipt
    }

    func receipt(operationID: String, secret: Data, policySHA256: String) async throws -> InstallationDeletionReceipt {
        guard InstallationDeletionWire.isOperationID(operationID), secret.count == 32,
              InstallationDeletionWire.isSHA256(policySHA256) else {
            throw InstallationDeletionError.invalidRequest
        }
        var request = try makeRequest(path: "attest/deletions/" + operationID, method: "GET")
        request.setValue("DeletionReceipt " + secret.base64EncodedString(), forHTTPHeaderField: "Authorization")
        let response = try await send(request)
        if response.statusCode == 404 { throw InstallationDeletionError.receiptUnavailable }
        try requireStatus(response, allowed: [200])
        return try decodeReceipt(response.data, operationID: operationID, policySHA256: policySHA256)
    }

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        guard let components = URLComponents(url: serviceEndpoint, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https", components.host?.isEmpty == false,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              serviceEndpoint.lastPathComponent == "v1",
              components.port.map({ (1...65_535).contains($0) }) ?? true else {
            throw InstallationDeletionError.invalidRequest
        }
        var request = URLRequest(url: serviceEndpoint.appendingPathComponent(path),
                                 cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: Self.timeoutSeconds)
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if method == "POST" { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }

    private struct HTTPResponse: Sendable {
        let data: Data
        let statusCode: Int
    }

    private func send(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            let (data, response) = try await BoundedServiceHTTPTransport.send(
                request, session: session, maximumResponseBytes: Self.maximumResponseBytes,
                timeoutSeconds: Self.timeoutSeconds
            )
            return HTTPResponse(data: data, statusCode: response.statusCode)
        } catch is CancellationError {
            throw CancellationError()
        } catch BoundedServiceHTTPError.invalidRequest {
            throw InstallationDeletionError.invalidRequest
        } catch BoundedServiceHTTPError.malformedResponse {
            throw InstallationDeletionError.malformedResponse
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw InstallationDeletionError.transport
        }
    }

    private func requireStatus(_ response: HTTPResponse, allowed: Set<Int>) throws {
        guard !allowed.contains(response.statusCode) else { return }
        if response.statusCode == 409,
           let object = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
           object["code"] as? String == "policy_mismatch" {
            throw InstallationDeletionError.policyMismatch
        }
        if response.statusCode == 400 { throw InstallationDeletionError.invalidRequest }
        if response.statusCode == 408 || response.statusCode == 429 || response.statusCode >= 500 {
            throw InstallationDeletionError.transport
        }
        throw InstallationDeletionError.rejected
    }

    private func decodeReceipt(_ data: Data, operationID: String, policySHA256: String) throws -> InstallationDeletionReceipt {
        _ = try InstallationDeletionWire.object(data, keys: [
            "operation_id", "status", "policy_sha256", "receipt_expires_at", "scope", "policy_qualification", "retained_categories"
        ])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = InstallationDeletionWire.date(raw) else { throw InstallationDeletionError.malformedResponse }
            return date
        }
        let receipt: InstallationDeletionReceipt
        do { receipt = try decoder.decode(InstallationDeletionReceipt.self, from: data) }
        catch { throw InstallationDeletionError.malformedResponse }
        try receipt.validate(operationID: operationID, policySHA256: policySHA256)
        guard receipt.receiptExpiresAt > Date() else { throw InstallationDeletionError.receiptUnavailable }
        return receipt
    }
}

private enum InstallationDeletionWire {
    static func isOperationID(_ value: String) -> Bool {
        UUID(uuidString: value)?.uuidString.lowercased() == value
    }

    static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func base64(_ value: String, count: Int) -> Data? {
        guard let data = Data(base64Encoded: value), data.count == count,
              data.base64EncodedString() == value else { return nil }
        return data
    }

    static func date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let result = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        guard let result, result.timeIntervalSince1970.isFinite else { return nil }
        return result
    }

    static func object(_ data: Data, keys: Set<String>) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == keys else { throw InstallationDeletionError.malformedResponse }
        return object
    }
}
