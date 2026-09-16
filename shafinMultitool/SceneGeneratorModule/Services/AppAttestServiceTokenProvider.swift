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
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data
}

/// Secure storage for the key identifier and the enrolled token.
protocol AppAttestSecretStoring: Sendable {
    func string(forKey key: String) throws -> String?
    func setString(_ value: String?, forKey key: String) throws
}

/// Challenge/enroll transport against the trusted service.
protocol AppAttestEnrollmentTransport: Sendable {
    /// Returns the decoded one-time challenge bytes and their server expiration.
    func requestChallenge() async throws -> (challenge: Data, expiresAt: Date?)
    /// Returns the raw installation token and its server-declared lifetime.
    func enroll(keyID: Data, clientDataHash: Data, challenge: Data, attestationObject: Data) async throws -> (token: String, ttlSeconds: TimeInterval?)
    func refresh(keyID: Data, clientDataHash: Data, challenge: Data, assertionObject: Data) async throws -> (token: String, ttlSeconds: TimeInterval?)
}

enum AppAttestEnrollmentError: Error, Equatable {
    case unsupported
    case malformedChallenge
    case installationNotEnrolled
    case rejected
    case transport
    case secretStorage
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

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: clientDataHash)
    }
}

struct KeychainAppAttestSecretStore: AppAttestSecretStoring {
    let service: String

    init(service: String = "com.vigvamcev-media.shafinMultitool.appattest") {
        self.service = service
    }

    func string(forKey key: String) throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        query[kSecUseDataProtectionKeychain as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw AppAttestEnrollmentError.secretStorage
        }
        return value
    }

    func setString(_ value: String?, forKey key: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let value, let data = value.data(using: .utf8) {
            let attributes: [String: Any] = [kSecValueData as String: data]
            let status = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                var insert = base
                insert[kSecValueData as String] = data
                insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
                    throw AppAttestEnrollmentError.secretStorage
                }
            } else if status != errSecSuccess {
                throw AppAttestEnrollmentError.secretStorage
            }
        } else {
            let status = SecItemDelete(base as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw AppAttestEnrollmentError.secretStorage
            }
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
        let expires_at: String
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

    private struct RefreshRequest: Encodable {
        let key_id: String
        let client_data_hash: String
        let challenge: String
        let assertion_object: String
    }

    private struct RejectionResponse: Decodable {
        let code: String
    }

    func requestChallenge() async throws -> (challenge: Data, expiresAt: Date?) {
        var request = URLRequest(url: baseURL.appendingPathComponent("attest/challenge"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = Data("{}".utf8)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw AppAttestEnrollmentError.rejected
            }
            let decoded = try JSONDecoder().decode(ChallengeResponse.self, from: data)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let expiresAt = fractional.date(from: decoded.expires_at)
                ?? ISO8601DateFormatter().date(from: decoded.expires_at)
            guard let challenge = Data(base64Encoded: decoded.challenge), challenge.count == 32,
                  let expiresAt, expiresAt.timeIntervalSince1970.isFinite else {
                throw AppAttestEnrollmentError.malformedChallenge
            }
            return (challenge, expiresAt)
        } catch let error as AppAttestEnrollmentError {
            throw error
        } catch is DecodingError {
            throw AppAttestEnrollmentError.malformedChallenge
        } catch {
            throw AppAttestEnrollmentError.transport
        }
    }

    func enroll(keyID: Data, clientDataHash: Data, challenge: Data, attestationObject: Data) async throws -> (token: String, ttlSeconds: TimeInterval?) {
        var request = URLRequest(url: baseURL.appendingPathComponent("attest/enroll"))
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
    func refresh(keyID: Data, clientDataHash: Data, challenge: Data, assertionObject: Data) async throws -> (token: String, ttlSeconds: TimeInterval?) {
        var request = URLRequest(url: baseURL.appendingPathComponent("attest/refresh"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(
            RefreshRequest(
                key_id: keyID.base64EncodedString(),
                client_data_hash: clientDataHash.base64EncodedString(),
                challenge: challenge.base64EncodedString(),
                assertion_object: assertionObject.base64EncodedString()
            )
        )
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 404,
               let rejection = try? JSONDecoder().decode(RejectionResponse.self, from: data),
               rejection.code == "installation_not_enrolled" {
                throw AppAttestEnrollmentError.installationNotEnrolled
            }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
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
actor AppAttestServiceTokenProvider: SceneServiceTokenProviding {
    private let performer: AppAttestDevicePerforming
    private let transport: AppAttestEnrollmentTransport
    private let secrets: AppAttestSecretStoring
    private let now: @Sendable () -> Date
    private let keyIDKey = "appattest.key_id"
    private let tokenKey = "appattest.token"
    private let expiryKey = "appattest.token_expiry"
    private let refreshAtKey = "appattest.token_refresh_at"
    private let enrolledKeyIDKey = "appattest.enrolled_key_id"
    private let attestedKeyIDKey = "appattest.attested_key_id"
    private var tokenTask: Task<Void, Never>?
    private var tokenWaiters: [UUID: CheckedContinuation<String?, Never>] = [:]
    private struct PendingAttestationChallenge {
        let keyID: String
        let challenge: Data
        let expiresAt: Date
    }
    private var pendingAttestationChallenge: PendingAttestationChallenge?

#if DEBUG
    var testingPendingTokenWaiterCount: Int { tokenWaiters.count }
#endif

    init(performer: AppAttestDevicePerforming,
         transport: AppAttestEnrollmentTransport,
         secrets: AppAttestSecretStoring,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.performer = performer
        self.transport = transport
        self.secrets = secrets
        self.now = now
    }

    func currentServiceToken() async -> String? {
        guard !Task.isCancelled, performer.isSupported else { return nil }
        do {
            if let cached = try cachedToken() { return cached }
        } catch {
            // A locked or failed keychain is not an absent installation.
            return nil
        }
        let waiterID = UUID()
        let token: String? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // Cancellation can arrive before the continuation is installed.
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }
                tokenWaiters[waiterID] = continuation
                guard tokenTask == nil else { return }
                // One acquisition owns DeviceCheck counters. Cancelling a
                // caller removes only that waiter; other callers keep waiting.
                tokenTask = Task {
                    let acquired = try? await self.enrollOrRefresh()
                    self.completeTokenAcquisition(acquired)
                }
            }
        } onCancel: {
            Task { await self.cancelTokenWaiter(waiterID) }
        }
        return Task.isCancelled ? nil : token
    }

    private func cancelTokenWaiter(_ id: UUID) {
        tokenWaiters.removeValue(forKey: id)?.resume(returning: nil)
    }

    private func completeTokenAcquisition(_ token: String?) {
        tokenTask = nil
        let waiters = Array(tokenWaiters.values)
        tokenWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: token) }
    }

    private func cachedToken() throws -> String? {
        guard let token = try secrets.string(forKey: tokenKey), !token.isEmpty,
              let expiryText = try secrets.string(forKey: expiryKey),
              let expiry = TimeInterval(expiryText), expiry.isFinite,
              now().timeIntervalSince1970 < expiry else { return nil }
        let refreshAt = try secrets.string(forKey: refreshAtKey).flatMap(TimeInterval.init)
        guard let refreshAt, refreshAt.isFinite,
              now().timeIntervalSince1970 < min(refreshAt, expiry) else { return nil }
        return token
    }

    func replacementServiceToken(afterRejecting token: String) async -> String? {
        // A slow request may reject the predecessor of an already renewed
        // token. Never invalidate that newer token or rotate its identity.
        do {
            if try secrets.string(forKey: tokenKey) == token {
                try secrets.setString(nil, forKey: expiryKey)
                try secrets.setString(nil, forKey: refreshAtKey)
            }
        } catch {
            return nil
        }
        return await currentServiceToken()
    }

    private func enrollOrRefresh(canReplaceIdentity: Bool = true) async throws -> String {
        let keyIDString: String
        let hadStoredKey: Bool
        if let stored = try secrets.string(forKey: keyIDKey), !stored.isEmpty {
            keyIDString = stored
            hadStoredKey = true
        } else {
            keyIDString = try await performer.generateKey()
            try secrets.setString(keyIDString, forKey: keyIDKey)
            hadStoredKey = false
        }
        guard let keyID = Data(base64Encoded: keyIDString), keyID.count == 32 else {
            // A malformed persisted key cannot be repaired without a fresh key.
            try secrets.setString(nil, forKey: keyIDKey)
            throw AppAttestEnrollmentError.rejected
        }

        let enrolledKey = try secrets.string(forKey: enrolledKeyIDKey)
        let attestedKey = try secrets.string(forKey: attestedKeyIDKey)
        let previousToken = try secrets.string(forKey: tokenKey)
        let previouslyEnrolled = hadStoredKey && (
            enrolledKey == keyIDString || attestedKey == keyIDString || previousToken?.isEmpty == false
        )
        let challengeResponse: (challenge: Data, expiresAt: Date?)
        if !previouslyEnrolled, let pending = pendingAttestationChallenge,
           pending.keyID == keyIDString, pending.expiresAt.timeIntervalSince1970.isFinite,
           pending.expiresAt > now() {
            challengeResponse = (pending.challenge, pending.expiresAt)
        } else {
            pendingAttestationChallenge = nil
            challengeResponse = try await transport.requestChallenge()
        }
        let challenge = challengeResponse.challenge
        guard challenge.count == 32,
              challengeResponse.expiresAt.map({ $0.timeIntervalSince1970.isFinite && $0 > now() }) ?? true else {
            throw AppAttestEnrollmentError.malformedChallenge
        }
        let clientDataHash = Data(SHA256.hash(data: challenge))
        let enrollment: (token: String, ttlSeconds: TimeInterval?)
        let tokenRequestStartedAt: Date
        if previouslyEnrolled {
            let assertion: Data
            do {
                assertion = try await performer.generateAssertion(keyIDString, clientDataHash: clientDataHash)
            } catch {
                if hadStoredKey, canReplaceIdentity, Self.deviceCheckCode(error) == .invalidKey {
                    // A restored/reinstalled app can retain a Keychain id after
                    // DeviceCheck has discarded its key. This typed local proof
                    // failure permits exactly one fresh acquisition.
                    try discardInstallationCredentials()
                    return try await enrollOrRefresh(canReplaceIdentity: false)
                }
                throw error
            }
            tokenRequestStartedAt = now()
            do {
                enrollment = try await transport.refresh(
                    keyID: keyID, clientDataHash: clientDataHash,
                    challenge: challenge, assertionObject: assertion
                )
            } catch AppAttestEnrollmentError.installationNotEnrolled where canReplaceIdentity {
                // Only an explicit absence response from the trusted backend
                // permits a fresh identity. Revocation, bad proof and network
                // errors preserve the original key and remain failures.
                try discardInstallationCredentials()
                return try await enrollOrRefresh(canReplaceIdentity: false)
            }
        } else {
            if let expiresAt = challengeResponse.expiresAt {
                pendingAttestationChallenge = PendingAttestationChallenge(
                    keyID: keyIDString, challenge: challenge, expiresAt: expiresAt
                )
            }
            let attestationObject: Data
            do {
                attestationObject = try await performer.attestKey(keyIDString, clientDataHash: clientDataHash)
            } catch {
                if let code = Self.deviceCheckCode(error) {
                    if code != .serverUnavailable {
                        // Apple requires a new key on the next acquisition for
                        // other DeviceCheck attestation errors. Do not loop here.
                        try discardInstallationCredentials()
                    }
                } else {
                    pendingAttestationChallenge = nil
                }
                throw error
            }
            pendingAttestationChallenge = nil
            // If the server accepts enrollment but its response is lost, the
            // next attempt proves possession with an assertion on this key.
            try secrets.setString(keyIDString, forKey: attestedKeyIDKey)
            tokenRequestStartedAt = now()
            enrollment = try await transport.enroll(
                keyID: keyID, clientDataHash: clientDataHash,
                challenge: challenge, attestationObject: attestationObject
            )
        }
        guard !enrollment.token.isEmpty,
              enrollment.token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let lifetime = enrollment.ttlSeconds, lifetime.isFinite, lifetime > 0 else {
            throw AppAttestEnrollmentError.rejected
        }
        // The server lifetime starts before the response reaches us. Network
        // delay or suspension must not extend it in the device cache.
        let expiry = tokenRequestStartedAt.addingTimeInterval(lifetime).timeIntervalSince1970
        let refreshAt = expiry - min(60, lifetime * 0.1)
        guard expiry.isFinite, now().timeIntervalSince1970 < refreshAt else {
            throw AppAttestEnrollmentError.rejected
        }
        try secrets.setString(keyIDString, forKey: enrolledKeyIDKey)
        try secrets.setString(enrollment.token, forKey: tokenKey)
        try secrets.setString(String(expiry), forKey: expiryKey)
        try secrets.setString(String(refreshAt), forKey: refreshAtKey)
        return enrollment.token
    }

    private static func deviceCheckCode(_ error: Error) -> DCError.Code? {
        let nsError = error as NSError
        guard nsError.domain == DCError.errorDomain else { return nil }
        return DCError.Code(rawValue: nsError.code)
    }

    private func discardInstallationCredentials() throws {
        pendingAttestationChallenge = nil
        // Keep the key identifier until every credential has been invalidated.
        // A partial Keychain write must not look like a missing installation.
        for key in [expiryKey, refreshAtKey, tokenKey, enrolledKeyIDKey, attestedKeyIDKey, keyIDKey] {
            try secrets.setString(nil, forKey: key)
        }
    }
}
