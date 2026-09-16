//
//  AppAttestServiceTokenProvider.swift
//  shafinMultitool
//
//  App Attest enrollment client: obtains the short-lived service token that
//  `SceneGenerationClient` sends as a bearer. Capability-gated and
//  fail-closed: when App Attest is unsupported, enrollment fails, or no
//  challenge is available, the provider returns nil and the Scene client
//  reports a missing/invalid service token instead of sending an
//  unauthenticated request.
//
//  DeviceCheck, Keychain, and URLSession are wrapped behind seams so the
//  enrollment state machine is unit-testable without the real framework.
//

import CryptoKit
import DeviceCheck
import Foundation
import Security

// MARK: - Seams

/// Device-level App Attest operations.
protocol AppAttestDevicePerforming: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data
}

/// Secure storage for the key identifier and the enrolled token.
protocol AppAttestSecretStoring: Sendable {
    func string(forKey key: String) -> String?
    func setString(_ value: String?, forKey key: String)
}

/// Challenge/enroll transport against the trusted service.
protocol AppAttestEnrollmentTransport: Sendable {
    /// Returns the decoded one-time challenge bytes and the token lifetime.
    func requestChallenge() async throws -> (challenge: Data, expiresAt: Date?)
    /// Returns the raw installation token and its server-declared lifetime.
    func enroll(keyID: Data, clientDataHash: Data, challenge: Data, attestationObject: Data) async throws -> (token: String, ttlSeconds: TimeInterval?)
}

enum AppAttestEnrollmentError: Error, Equatable {
    case unsupported
    case malformedChallenge
    case rejected
    case transport
}

// MARK: - System adapters

struct SystemAppAttestDevicePerformer: AppAttestDevicePerforming {
    var isSupported: Bool { DCAppAttestService.shared.isSupported }

    func generateKey() async throws -> String {
        try await DCAppAttestService.shared.generateKey()
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.attestKey(keyID, clientDataHash: clientDataHash)
    }
}

struct KeychainAppAttestSecretStore: AppAttestSecretStoring {
    let service: String

    init(service: String = "com.vigvamcev-media.shafinMultitool.appattest") {
        self.service = service
    }

    func string(forKey key: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        query[kSecUseDataProtectionKeychain as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    func setString(_ value: String?, forKey key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let value, let data = value.data(using: .utf8) {
            let attributes: [String: Any] = [kSecValueData as String: data]
            let status = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                var insert = base
                insert[kSecValueData as String] = data
                insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                SecItemAdd(insert as CFDictionary, nil)
            }
        } else {
            SecItemDelete(base as CFDictionary)
        }
    }
}

/// URLSession transport for the opt-in `/v1/attest/*` endpoints.
struct URLSessionAppAttestEnrollmentTransport: AppAttestEnrollmentTransport {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    private struct ChallengeResponse: Decodable {
        let challenge: String
    }

    private struct EnrollRequest: Encodable {
        let key_id: String
        let client_data_hash: String
        let challenge: String
        let attestation_object: String
    }

    private struct EnrollResponse: Decodable {
        let token: String
        let token_ttl_seconds: TimeInterval?
    }

    func requestChallenge() async throws -> (challenge: Data, expiresAt: Date?) {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/attest/challenge"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = Data("{}".utf8)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw AppAttestEnrollmentError.rejected
            }
            let decoded = try JSONDecoder().decode(ChallengeResponse.self, from: data)
            guard let challenge = Data(base64Encoded: decoded.challenge), challenge.count == 32 else {
                throw AppAttestEnrollmentError.malformedChallenge
            }
            return (challenge, nil)
        } catch let error as AppAttestEnrollmentError {
            throw error
        } catch {
            throw AppAttestEnrollmentError.transport
        }
    }

    func enroll(keyID: Data, clientDataHash: Data, challenge: Data, attestationObject: Data) async throws -> (token: String, ttlSeconds: TimeInterval?) {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/attest/enroll"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(
            EnrollRequest(
                key_id: keyID.base64EncodedString(),
                client_data_hash: clientDataHash.base64EncodedString(),
                challenge: challenge.base64EncodedString(),
                attestation_object: attestationObject.base64EncodedString()
            )
        )
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
                throw AppAttestEnrollmentError.rejected
            }
            let decoded = try JSONDecoder().decode(EnrollResponse.self, from: data)
            return (decoded.token, decoded.token_ttl_seconds)
        } catch let error as AppAttestEnrollmentError {
            throw error
        } catch {
            throw AppAttestEnrollmentError.transport
        }
    }
}

// MARK: - Provider

/// Enrolls once, caches the token with its lifetime, and degrades to `nil`
/// whenever App Attest cannot produce a trustworthy token.
final class AppAttestServiceTokenProvider: SceneServiceTokenProviding, @unchecked Sendable {
    private let performer: AppAttestDevicePerforming
    private let transport: AppAttestEnrollmentTransport
    private let secrets: AppAttestSecretStoring
    private let now: @Sendable () -> Date
    private let defaultTokenLifetimeSeconds: TimeInterval
    private let keyIDKey = "appattest.key_id"
    private let tokenKey = "appattest.token"
    private let expiryKey = "appattest.token_expiry"
    private let lock = NSLock()

    init(performer: AppAttestDevicePerforming,
         transport: AppAttestEnrollmentTransport,
         secrets: AppAttestSecretStoring,
         defaultTokenLifetimeSeconds: TimeInterval = 3600,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.performer = performer
        self.transport = transport
        self.secrets = secrets
        self.defaultTokenLifetimeSeconds = defaultTokenLifetimeSeconds
        self.now = now
    }

    func currentServiceToken() async -> String? {
        if let cached = cachedToken() {
            return cached
        }
        guard performer.isSupported else { return nil }
        do {
            return try await enroll()
        } catch {
            return nil
        }
    }

    private func cachedToken() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let token = secrets.string(forKey: tokenKey), !token.isEmpty else { return nil }
        if let expiryText = secrets.string(forKey: expiryKey),
           let expiry = TimeInterval(expiryText) {
            // refresh a minute early so a request is never sent with a token
            // that expires in flight
            if now().timeIntervalSince1970 >= expiry - 60 {
                return nil
            }
        }
        return token
    }

    private func enroll() async throws -> String {
        let keyIDString: String
        if let stored = secrets.string(forKey: keyIDKey), !stored.isEmpty {
            keyIDString = stored
        } else {
            keyIDString = try await performer.generateKey()
            secrets.setString(keyIDString, forKey: keyIDKey)
        }
        guard let keyID = Data(base64Encoded: keyIDString), keyID.count == 32 else {
            // A malformed persisted key cannot be repaired without a fresh key.
            secrets.setString(nil, forKey: keyIDKey)
            throw AppAttestEnrollmentError.rejected
        }

        let challenge = try await transport.requestChallenge().challenge
        let clientDataHash = Data(SHA256.hash(data: challenge))
        let attestationObject = try await performer.attestKey(keyIDString, clientDataHash: clientDataHash)
        let enrollment = try await transport.enroll(
            keyID: keyID,
            clientDataHash: clientDataHash,
            challenge: challenge,
            attestationObject: attestationObject
        )
        guard !enrollment.token.isEmpty else { throw AppAttestEnrollmentError.rejected }
        let lifetime = enrollment.ttlSeconds ?? defaultTokenLifetimeSeconds
        lock.lock()
        secrets.setString(enrollment.token, forKey: tokenKey)
        secrets.setString(String(now().addingTimeInterval(lifetime).timeIntervalSince1970), forKey: expiryKey)
        lock.unlock()
        return enrollment.token
    }
}
