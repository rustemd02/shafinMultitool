//
//  AppAttestServiceTokenProviderTests.swift
//  shafinMultitool
//
//  Contract tests for the App Attest enrollment client: capability gating,
//  one-time enrollment with token caching, key reuse, expiry-driven refresh,
//  and fail-closed degradation to nil.
//

import CryptoKit
import DeviceCheck
import XCTest
@testable import shafinMultitool

private final class FakePerformer: AppAttestDevicePerforming, @unchecked Sendable {
    var isSupported = true
    var generatedKey = Data(repeating: 0x11, count: 32).base64EncodedString()
    var generateKeyCalls = 0
    var attestCalls = 0
    var assertionCalls = 0
    var lastAssertedHash: Data?
    var lastAttestedHash: Data?
    var attestError: Error?
    var assertionError: Error?
    var assertedKeys: [String] = []
    var attestedKeys: [String] = []

    func generateKey() async throws -> String {
        generateKeyCalls += 1
        return generatedKey
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        attestCalls += 1
        attestedKeys.append(keyID)
        lastAttestedHash = clientDataHash
        if let attestError { throw attestError }
        return Data(repeating: 0x22, count: 64)
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        assertionCalls += 1
        assertedKeys.append(keyID)
        lastAssertedHash = clientDataHash
        if let assertionError { throw assertionError }
        return Data(repeating: 0x55, count: 64)
    }
}

private final class FakeTransport: AppAttestEnrollmentTransport, @unchecked Sendable {
    var challenge = Data(repeating: 0x33, count: 32)
    var challengeExpiresAt: Date?
    var ttlSeconds: TimeInterval? = 120
    var challengeCalls = 0
    var enrollCalls = 0
    var refreshCalls = 0
    var refreshError: Error?
    var lastKeyID: Data?
    var lastClientDataHash: Data?
    var lastChallenge: Data?
    var challengeError: Error?
    var enrollError: Error?
    var tokenOverride: String?
    var beforeTokenResponse: (() -> Void)?

    func requestChallenge() async throws -> (challenge: Data, expiresAt: Date?) {
        challengeCalls += 1
        await Task.yield()
        if let challengeError { throw challengeError }
        return (challenge, challengeExpiresAt)
    }

    func enroll(keyID: Data, clientDataHash: Data, challenge: Data, attestationObject: Data) async throws -> (token: String, ttlSeconds: TimeInterval?) {
        enrollCalls += 1
        lastKeyID = keyID
        lastClientDataHash = clientDataHash
        lastChallenge = challenge
        if let enrollError { throw enrollError }
        beforeTokenResponse?()
        return (tokenOverride ?? "service-token-\(enrollCalls)", ttlSeconds)
    }

    func refresh(keyID: Data, clientDataHash: Data, challenge: Data, assertionObject: Data) async throws -> (token: String, ttlSeconds: TimeInterval?) {
        refreshCalls += 1
        lastKeyID = keyID
        lastClientDataHash = clientDataHash
        lastChallenge = challenge
        if let refreshError { throw refreshError }
        beforeTokenResponse?()
        return (tokenOverride ?? "refreshed-token-\(refreshCalls)", ttlSeconds)
    }
}

private final class MemorySecrets: AppAttestSecretStoring, @unchecked Sendable {
    var storage: [String: String] = [:]
    func string(forKey key: String) -> String? { storage[key] }
    func setString(_ value: String?, forKey key: String) {
        if let value { storage[key] = value } else { storage.removeValue(forKey: key) }
    }
}

private final class FailingSecrets: AppAttestSecretStoring, @unchecked Sendable {
    let memory = MemorySecrets()
    var failingReads: Set<String> = []
    var failingWrites: Set<String> = []
    func string(forKey key: String) throws -> String? {
        if failingReads.contains(key) { throw AppAttestEnrollmentError.secretStorage }
        return memory.string(forKey: key)
    }
    func setString(_ value: String?, forKey key: String) throws {
        if failingWrites.contains(key) { throw AppAttestEnrollmentError.secretStorage }
        memory.setString(value, forKey: key)
    }
}

private actor SuspendedAttestTransport: AppAttestEnrollmentTransport {
    let entered: XCTestExpectation
    private var challengeContinuation: CheckedContinuation<(challenge: Data, expiresAt: Date?), Never>?
    private(set) var challengeCalls = 0
    private(set) var enrollCalls = 0

    init(entered: XCTestExpectation) { self.entered = entered }

    func requestChallenge() async throws -> (challenge: Data, expiresAt: Date?) {
        challengeCalls += 1
        return await withCheckedContinuation { continuation in
            challengeContinuation = continuation
            entered.fulfill()
        }
    }

    func releaseChallenge() {
        let pending = challengeContinuation
        challengeContinuation = nil
        pending?.resume(returning: (Data(repeating: 0x31, count: 32), nil))
    }

    func enroll(keyID: Data, clientDataHash: Data, challenge: Data, attestationObject: Data) async throws -> (token: String, ttlSeconds: TimeInterval?) {
        enrollCalls += 1
        return ("shared-service-token", 120)
    }

    func refresh(keyID: Data, clientDataHash: Data, challenge: Data, assertionObject: Data) async throws -> (token: String, ttlSeconds: TimeInterval?) {
        ("shared-renewed-token", 120)
    }
}

private final class CancelledAttestRequestProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var count = 0
    static func reset() { lock.lock(); count = 0; lock.unlock() }
    static var requestCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.count += 1; Self.lock.unlock()
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }
    override func stopLoading() {}
}

final class AppAttestServiceTokenProviderTests: XCTestCase {

    private func makeProvider(now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_800_000_000) })
        -> (AppAttestServiceTokenProvider, FakePerformer, FakeTransport, MemorySecrets) {
        let performer = FakePerformer()
        let transport = FakeTransport()
        let secrets = MemorySecrets()
        let provider = AppAttestServiceTokenProvider(
            performer: performer,
            transport: transport,
            secrets: secrets,
            now: now
        )
        return (provider, performer, transport, secrets)
    }

    func testUnsupportedDeviceDegradesToNilWithoutNetwork() async {
        let (provider, performer, transport, secrets) = makeProvider()
        performer.isSupported = false
        let token = await provider.currentServiceToken()
        XCTAssertNil(token, "unsupported App Attest must not fabricate a token")
        XCTAssertEqual(transport.challengeCalls, 0)
        XCTAssertEqual(transport.enrollCalls, 0)
        XCTAssertEqual(performer.generateKeyCalls, 0)
        XCTAssertTrue(secrets.storage.isEmpty)
    }

    func testEnrollmentBindsChallengeAndCachesToken() async {
        let (provider, performer, transport, secrets) = makeProvider()
        let token = await provider.currentServiceToken()
        XCTAssertEqual(token, "service-token-1")
        XCTAssertEqual(transport.challengeCalls, 1)
        XCTAssertEqual(transport.enrollCalls, 1)
        XCTAssertEqual(performer.attestCalls, 1)
        XCTAssertEqual(performer.generateKeyCalls, 1, "a fresh key is generated once")
        XCTAssertEqual(performer.lastAttestedHash, Data(SHA256.hash(data: transport.challenge)))
        XCTAssertEqual(transport.lastClientDataHash, performer.lastAttestedHash)
        XCTAssertEqual(transport.lastChallenge, transport.challenge)
        XCTAssertEqual(transport.lastKeyID, Data(base64Encoded: performer.generatedKey))
        XCTAssertEqual(secrets.string(forKey: "appattest.token"), "service-token-1")

        // A second call returns the cached token without new network traffic.
        let second = await provider.currentServiceToken()
        XCTAssertEqual(second, "service-token-1")
        XCTAssertEqual(transport.challengeCalls, 1)
        XCTAssertEqual(transport.enrollCalls, 1)
        XCTAssertEqual(performer.attestCalls, 1)
    }

    func testExpiredCachedTokenTriggersFreshEnrollment() async {
        let clock = TestClock()
        let (provider, _, transport, secrets) = makeProvider(now: { clock.now })
        secrets.setString("stale-token", forKey: "appattest.token")
        secrets.setString(String(clock.now.timeIntervalSince1970 - 1), forKey: "appattest.token_expiry")

        let token = await provider.currentServiceToken()
        XCTAssertEqual(token, "service-token-1", "an expired token must be replaced")
        XCTAssertEqual(transport.enrollCalls, 1)
    }

    func testPersistedKeyIsReusedAcrossEnrollments() async {
        let clock = TestClock()
        let (provider, performer, transport, secrets) = makeProvider(now: { clock.now })
        let persistedKey = Data(repeating: 0x44, count: 32).base64EncodedString()
        secrets.setString(persistedKey, forKey: "appattest.key_id")

        let token = await provider.currentServiceToken()
        XCTAssertNotNil(token)
        XCTAssertEqual(performer.generateKeyCalls, 0, "the persisted key must be reused")
        XCTAssertEqual(transport.lastKeyID, Data(base64Encoded: persistedKey))
    }

    func testChallengeAndEnrollmentFailuresDegradeToNil() async {
        do {
            let (provider, _, transport, _) = makeProvider()
            transport.challengeError = AppAttestEnrollmentError.malformedChallenge
            let token = await provider.currentServiceToken()
            XCTAssertNil(token)
        }
        do {
            let (provider, _, transport, _) = makeProvider()
            transport.enrollError = AppAttestEnrollmentError.rejected
            let token = await provider.currentServiceToken()
            XCTAssertNil(token)
        }
        do {
            let (provider, performer, _, _) = makeProvider()
            performer.attestError = AppAttestEnrollmentError.transport
            let token = await provider.currentServiceToken()
            XCTAssertNil(token)
        }
    }

    func testMalformedPersistedKeyIsDiscardedAndNotAttested() async {
        let (provider, performer, transport, secrets) = makeProvider()
        secrets.setString("not-a-32-byte-key", forKey: "appattest.key_id")
        let token = await provider.currentServiceToken()
        XCTAssertNil(token)
        XCTAssertNil(secrets.string(forKey: "appattest.key_id"), "an unusable key must be cleared")
        XCTAssertEqual(performer.attestCalls, 0)
        XCTAssertEqual(transport.challengeCalls, 0)
    }

    func testEmptyServerTokenIsRejectedAndNotCached() async {
        let (provider, _, transport, secrets) = makeProvider()
        transport.tokenOverride = ""
        let token = await provider.currentServiceToken()
        XCTAssertNil(token, "an empty server token must not be used")
        XCTAssertNil(secrets.string(forKey: "appattest.token"))
    }

    func testExpiryRefreshesSameInstallationWithAssertionWithoutReattesting() async {
        let clock = TestClock()
        let (provider, performer, transport, _) = makeProvider(now: { clock.now })
        let first = await provider.currentServiceToken()
        XCTAssertEqual(first, "service-token-1")
        clock.advance(121)

        let refreshed = await provider.currentServiceToken()
        XCTAssertEqual(refreshed, "refreshed-token-1")
        XCTAssertEqual(transport.refreshCalls, 1)
        XCTAssertEqual(transport.enrollCalls, 1)
        XCTAssertEqual(performer.generateKeyCalls, 1)
        XCTAssertEqual(performer.attestCalls, 1)
        XCTAssertEqual(performer.assertionCalls, 1)
        XCTAssertEqual(performer.lastAssertedHash, Data(SHA256.hash(data: transport.challenge)))
        XCTAssertEqual(transport.lastKeyID, Data(base64Encoded: performer.generatedKey))
    }

    func testConcurrentCallersShareEnrollmentAndRefresh() async {
        let clock = TestClock()
        let (provider, performer, transport, _) = makeProvider(now: { clock.now })
        for expected in ["service-token-1", "refreshed-token-1"] {
            let tokens = await withTaskGroup(of: String?.self, returning: [String?].self) { group in
                for _ in 0..<20 {
                    group.addTask { await provider.currentServiceToken() }
                }
                var tokens: [String?] = []
                for await token in group { tokens.append(token) }
                return tokens
            }
            XCTAssertEqual(tokens.count, 20)
            XCTAssertTrue(tokens.allSatisfy { $0 == expected })
            clock.advance(121)
        }
        XCTAssertEqual(transport.enrollCalls, 1)
        XCTAssertEqual(transport.refreshCalls, 1)
        XCTAssertEqual(performer.generateKeyCalls, 1)
        XCTAssertEqual(performer.attestCalls, 1)
    }

    func testFailedRefreshPreservesIdentityAndNeverReturnsExpiredToken() async {
        let clock = TestClock()
        let (provider, performer, transport, secrets) = makeProvider(now: { clock.now })
        _ = await provider.currentServiceToken()
        clock.advance(121)
        transport.refreshError = AppAttestEnrollmentError.rejected
        let rejected = await provider.currentServiceToken()
        XCTAssertNil(rejected)
        XCTAssertEqual(secrets.string(forKey: "appattest.key_id"), performer.generatedKey)
        XCTAssertEqual(performer.attestCalls, 1)
        XCTAssertEqual(performer.generateKeyCalls, 1)
        transport.refreshError = nil
        let retry = await provider.currentServiceToken()
        XCTAssertEqual(retry, "refreshed-token-2")
    }

    func testMissingOrInvalidCachedExpiryRequiresRefresh() async {
        for expiry in [nil, "nan", "inf", "not-a-time"] as [String?] {
            let (provider, _, transport, secrets) = makeProvider()
            _ = await provider.currentServiceToken()
            secrets.setString(expiry, forKey: "appattest.token_expiry")
            let token = await provider.currentServiceToken()
            XCTAssertEqual(token, "refreshed-token-1")
            XCTAssertEqual(transport.refreshCalls, 1)
        }
    }

    func testMissingOrInvalidServerLifetimeIsNotCached() async {
        for lifetime in [nil, 0, -1, .infinity, .nan] as [TimeInterval?] {
            let (provider, _, transport, secrets) = makeProvider()
            transport.ttlSeconds = lifetime
            let token = await provider.currentServiceToken()
            XCTAssertNil(token)
            XCTAssertNil(secrets.string(forKey: "appattest.token"))
        }
    }

    func testShortServerLifetimeCanStillBeCached() async {
        let (provider, _, transport, _) = makeProvider()
        transport.ttlSeconds = 30
        let first = await provider.currentServiceToken()
        let second = await provider.currentServiceToken()
        XCTAssertEqual(first, second)
        XCTAssertEqual(transport.challengeCalls, 1)
    }

    func testLostEnrollmentResponseRecoversUsingSameAttestedKey() async {
        let (provider, performer, transport, _) = makeProvider()
        transport.enrollError = AppAttestEnrollmentError.transport
        let lost = await provider.currentServiceToken()
        XCTAssertNil(lost)
        transport.enrollError = nil
        let recovered = await provider.currentServiceToken()
        XCTAssertEqual(recovered, "refreshed-token-1")
        XCTAssertEqual(performer.generateKeyCalls, 1)
        XCTAssertEqual(performer.attestCalls, 1)
        XCTAssertEqual(performer.assertionCalls, 1)
        XCTAssertEqual(transport.enrollCalls, 1)
    }

    func testExplicitMissingInstallationAllowsOneFreshEnrollment() async {
        let (provider, performer, transport, _) = makeProvider()
        transport.enrollError = AppAttestEnrollmentError.transport
        _ = await provider.currentServiceToken()
        transport.enrollError = nil
        transport.refreshError = AppAttestEnrollmentError.installationNotEnrolled
        performer.generatedKey = Data(repeating: 0x66, count: 32).base64EncodedString()
        let recovered = await provider.currentServiceToken()
        XCTAssertEqual(recovered, "service-token-2")
        XCTAssertEqual(performer.generateKeyCalls, 2)
        XCTAssertEqual(performer.attestCalls, 2)
        XCTAssertEqual(transport.refreshCalls, 1)
        XCTAssertEqual(transport.lastKeyID, Data(base64Encoded: performer.generatedKey))
    }

    func testResponseDelayCannotExtendServerTokenLifetime() async {
        let clock = TestClock()
        let (provider, _, transport, secrets) = makeProvider(now: { clock.now })
        let requestStart = clock.now.timeIntervalSince1970
        transport.ttlSeconds = 60
        transport.beforeTokenResponse = { clock.advance(7) }
        let first = await provider.currentServiceToken()
        XCTAssertEqual(first, "service-token-1")
        XCTAssertEqual(secrets.string(forKey: "appattest.token_expiry"), String(requestStart + 60))
        clock.advance(53.5)
        transport.beforeTokenResponse = nil
        let next = await provider.currentServiceToken()
        XCTAssertEqual(next, "refreshed-token-1")
        XCTAssertEqual(transport.refreshCalls, 1)
    }

    func testExpiredInFlightEnrollmentOrRefreshIsNeverReturned() async {
        let clock = TestClock()
        let (provider, _, transport, secrets) = makeProvider(now: { clock.now })
        transport.ttlSeconds = 60
        transport.beforeTokenResponse = { clock.advance(61) }
        let expiredEnrollment = await provider.currentServiceToken()
        XCTAssertNil(expiredEnrollment)
        XCTAssertNil(secrets.string(forKey: "appattest.token"))
        let expiredRefresh = await provider.currentServiceToken()
        XCTAssertNil(expiredRefresh)
        XCTAssertEqual(transport.refreshCalls, 1)
        XCTAssertNil(secrets.string(forKey: "appattest.token"))
        transport.beforeTokenResponse = nil
        let recovered = await provider.currentServiceToken()
        XCTAssertEqual(recovered, "refreshed-token-2")
    }

    func testRejectedPredecessorDoesNotInvalidateAlreadyRenewedToken() async {
        let clock = TestClock()
        let (provider, performer, transport, _) = makeProvider(now: { clock.now })
        _ = await provider.currentServiceToken()
        clock.advance(121)
        let renewed = await provider.currentServiceToken()
        let recovered = await provider.replacementServiceToken(afterRejecting: "service-token-1")
        XCTAssertEqual(recovered, renewed)
        XCTAssertEqual(transport.refreshCalls, 1)
        XCTAssertEqual(performer.generateKeyCalls, 1)
    }

    func testRejectedCurrentTokenRefreshesSameIdentityAndRevocationFailsClosed() async {
        let (provider, performer, transport, _) = makeProvider()
        _ = await provider.currentServiceToken()
        let renewed = await provider.replacementServiceToken(afterRejecting: "service-token-1")
        XCTAssertEqual(renewed, "refreshed-token-1")
        transport.refreshError = AppAttestEnrollmentError.rejected
        let revoked = await provider.replacementServiceToken(afterRejecting: "refreshed-token-1")
        XCTAssertNil(revoked)
        XCTAssertEqual(performer.generateKeyCalls, 1)
        XCTAssertEqual(performer.attestCalls, 1)
    }

    func testUnavailableKeychainDoesNotCreateAReplacementInstallation() async {
        for unavailableKey in ["appattest.token", "appattest.key_id"] {
            let secrets = FailingSecrets()
            let performer = FakePerformer()
            let transport = FakeTransport()
            secrets.memory.storage["appattest.key_id"] = performer.generatedKey
            secrets.failingReads = [unavailableKey]
            let provider = AppAttestServiceTokenProvider(performer: performer, transport: transport, secrets: secrets)
            let token = await provider.currentServiceToken()
            XCTAssertNil(token)
            XCTAssertEqual(performer.generateKeyCalls, 0)
            XCTAssertEqual(performer.attestCalls, 0)
            XCTAssertEqual(transport.challengeCalls, 0)
            XCTAssertEqual(secrets.memory.storage["appattest.key_id"], performer.generatedKey)
        }
    }

    func testKeyPersistenceFailurePreventsAttestationAndEnrollment() async {
        let secrets = FailingSecrets()
        secrets.failingWrites = ["appattest.key_id"]
        let performer = FakePerformer()
        let transport = FakeTransport()
        let provider = AppAttestServiceTokenProvider(performer: performer, transport: transport, secrets: secrets)
        let token = await provider.currentServiceToken()
        XCTAssertNil(token)
        XCTAssertEqual(performer.generateKeyCalls, 1)
        XCTAssertEqual(performer.attestCalls, 0)
        XCTAssertEqual(transport.challengeCalls, 0)
        XCTAssertEqual(transport.enrollCalls, 0)
    }

    func testPartialTokenWriteIsNotReturnedAndRecoveryKeepsInstallation() async {
        let secrets = FailingSecrets()
        secrets.failingWrites = ["appattest.token_expiry"]
        let performer = FakePerformer()
        let transport = FakeTransport()
        let provider = AppAttestServiceTokenProvider(performer: performer, transport: transport, secrets: secrets)
        let failed = await provider.currentServiceToken()
        XCTAssertNil(failed)
        XCTAssertEqual(transport.enrollCalls, 1)
        secrets.failingWrites = []
        let recovered = await provider.currentServiceToken()
        XCTAssertEqual(recovered, "refreshed-token-1")
        XCTAssertEqual(performer.generateKeyCalls, 1)
        XCTAssertEqual(performer.attestCalls, 1)
        XCTAssertEqual(performer.assertionCalls, 1)
    }

    func testReinstalledStoredKeyRecoversOnceFromTypedInvalidKey() async {
        let (provider, performer, transport, secrets) = makeProvider()
        let oldKey = Data(repeating: 0x77, count: 32).base64EncodedString()
        secrets.setString(oldKey, forKey: "appattest.key_id")
        secrets.setString(oldKey, forKey: "appattest.enrolled_key_id")
        performer.assertionError = NSError(domain: DCError.errorDomain, code: DCError.Code.invalidKey.rawValue)
        let recovered = await provider.currentServiceToken()
        XCTAssertEqual(recovered, "service-token-1")
        XCTAssertEqual(performer.assertedKeys, [oldKey])
        XCTAssertEqual(performer.generateKeyCalls, 1)
        XCTAssertEqual(performer.attestedKeys, [performer.generatedKey])
        XCTAssertEqual(transport.enrollCalls, 1)
        XCTAssertEqual(transport.refreshCalls, 0)
        XCTAssertEqual(secrets.string(forKey: "appattest.key_id"), performer.generatedKey)
    }

    func testAssertionErrorsOtherThanTypedInvalidKeyPreserveStoredIdentity() async {
        let errors: [Error] = [
            NSError(domain: DCError.errorDomain, code: DCError.Code.serverUnavailable.rawValue),
            NSError(domain: DCError.errorDomain, code: DCError.Code.featureUnsupported.rawValue),
            NSError(domain: "another-domain", code: DCError.Code.invalidKey.rawValue),
            AppAttestEnrollmentError.rejected, URLError(.notConnectedToInternet)
        ]
        for error in errors {
            let (provider, performer, transport, secrets) = makeProvider()
            secrets.setString(performer.generatedKey, forKey: "appattest.key_id")
            secrets.setString(performer.generatedKey, forKey: "appattest.enrolled_key_id")
            performer.assertionError = error
            let token = await provider.currentServiceToken()
            XCTAssertNil(token)
            XCTAssertEqual(performer.generateKeyCalls, 0)
            XCTAssertEqual(transport.enrollCalls, 0)
            XCTAssertEqual(secrets.string(forKey: "appattest.key_id"), performer.generatedKey)
        }
    }

    func testInvalidReplacementKeyCannotTriggerAnotherIdentityInSameAcquisition() async {
        let (provider, performer, transport, secrets) = makeProvider()
        let oldKey = Data(repeating: 0x77, count: 32).base64EncodedString()
        secrets.setString(oldKey, forKey: "appattest.key_id")
        secrets.setString(oldKey, forKey: "appattest.enrolled_key_id")
        let invalidKey = NSError(domain: DCError.errorDomain, code: DCError.Code.invalidKey.rawValue)
        performer.assertionError = invalidKey
        performer.attestError = invalidKey
        let token = await provider.currentServiceToken()
        XCTAssertNil(token)
        XCTAssertEqual(performer.assertionCalls, 1)
        XCTAssertEqual(performer.generateKeyCalls, 1)
        XCTAssertEqual(performer.attestCalls, 1)
        XCTAssertEqual(transport.challengeCalls, 2)
        XCTAssertEqual(transport.enrollCalls, 0)
    }

    func testFailedCredentialCleanupCannotCreateAReplacementIdentity() async {
        let secrets = FailingSecrets()
        let performer = FakePerformer()
        let transport = FakeTransport()
        let oldKey = Data(repeating: 0x77, count: 32).base64EncodedString()
        secrets.memory.setString(oldKey, forKey: "appattest.key_id")
        secrets.memory.setString(oldKey, forKey: "appattest.enrolled_key_id")
        secrets.failingWrites = ["appattest.enrolled_key_id"]
        performer.assertionError = NSError(domain: DCError.errorDomain, code: DCError.Code.invalidKey.rawValue)
        let provider = AppAttestServiceTokenProvider(performer: performer, transport: transport, secrets: secrets)
        let token = await provider.currentServiceToken()
        XCTAssertNil(token)
        XCTAssertEqual(performer.generateKeyCalls, 0)
        XCTAssertEqual(transport.enrollCalls, 0)
        XCTAssertEqual(secrets.memory.string(forKey: "appattest.key_id"), oldKey)
    }

    func testInvalidFreshAttestationIsDiscardedWithoutAnAcquisitionLoop() async {
        let (provider, performer, transport, secrets) = makeProvider()
        performer.attestError = NSError(domain: DCError.errorDomain, code: DCError.Code.invalidKey.rawValue)
        let failed = await provider.currentServiceToken()
        XCTAssertNil(failed)
        XCTAssertEqual(performer.generateKeyCalls, 1)
        XCTAssertEqual(performer.attestCalls, 1)
        XCTAssertEqual(transport.enrollCalls, 0)
        XCTAssertNil(secrets.string(forKey: "appattest.key_id"))
        performer.attestError = nil
        let retried = await provider.currentServiceToken()
        XCTAssertEqual(retried, "service-token-1")
        XCTAssertEqual(performer.generateKeyCalls, 2)
    }

    func testAttestationKeyDispositionDependsOnDeviceCheckErrorDomainAndCode() async {
        let cases: [(Error, Bool)] = [
            (NSError(domain: DCError.errorDomain, code: DCError.Code.invalidInput.rawValue), true),
            (NSError(domain: DCError.errorDomain, code: DCError.Code.serverUnavailable.rawValue), false),
            (NSError(domain: "another-domain", code: DCError.Code.invalidInput.rawValue), false),
            (URLError(.notConnectedToInternet), false)
        ]
        for (error, shouldDiscard) in cases {
            let (provider, performer, transport, secrets) = makeProvider()
            performer.attestError = error
            let token = await provider.currentServiceToken()
            XCTAssertNil(token)
            XCTAssertEqual(secrets.string(forKey: "appattest.key_id") == nil, shouldDiscard)
            XCTAssertEqual(performer.generateKeyCalls, 1)
            XCTAssertEqual(transport.enrollCalls, 0)
        }
    }

    func testServerUnavailableReusesUnexpiredAttestationChallengeAndHash() async {
        let clock = TestClock()
        let (provider, performer, transport, _) = makeProvider(now: { clock.now })
        transport.challengeExpiresAt = clock.now.addingTimeInterval(60)
        performer.attestError = NSError(domain: DCError.errorDomain, code: DCError.Code.serverUnavailable.rawValue)
        _ = await provider.currentServiceToken()
        let originalHash = performer.lastAttestedHash
        let originalChallenge = transport.challenge
        transport.challenge = Data(repeating: 0x99, count: 32)
        performer.attestError = nil
        let retried = await provider.currentServiceToken()
        XCTAssertEqual(retried, "service-token-1")
        XCTAssertEqual(transport.challengeCalls, 1)
        XCTAssertEqual(performer.generateKeyCalls, 1)
        XCTAssertEqual(performer.lastAttestedHash, originalHash)
        XCTAssertEqual(transport.lastChallenge, originalChallenge)
    }

    func testExpiredOrUnknownAttestationChallengeIsNeverReused() async {
        for knownExpiry in [true, false] {
            let clock = TestClock()
            let (provider, performer, transport, _) = makeProvider(now: { clock.now })
            transport.challengeExpiresAt = knownExpiry ? clock.now.addingTimeInterval(10) : nil
            performer.attestError = NSError(domain: DCError.errorDomain, code: DCError.Code.serverUnavailable.rawValue)
            _ = await provider.currentServiceToken()
            clock.advance(11)
            transport.challenge = Data(repeating: 0x99, count: 32)
            transport.challengeExpiresAt = clock.now.addingTimeInterval(60)
            performer.attestError = nil
            let retried = await provider.currentServiceToken()
            XCTAssertEqual(retried, "service-token-1")
            XCTAssertEqual(transport.challengeCalls, 2)
            XCTAssertEqual(transport.lastChallenge, transport.challenge)
        }
    }

    func testExpiredOrNonfiniteChallengeDoesNotReachDeviceAttestation() async {
        let clock = TestClock()
        for expiry in [clock.now, clock.now.addingTimeInterval(-1), Date(timeIntervalSince1970: .infinity)] {
            let (provider, performer, transport, _) = makeProvider(now: { clock.now })
            transport.challengeExpiresAt = expiry
            let token = await provider.currentServiceToken()
            XCTAssertNil(token)
            XCTAssertEqual(performer.attestCalls, 0)
        }
    }

    func testCancellationBeforeWaiterRegistrationDoesNotStartAcquisition() async {
        let (provider, performer, transport, _) = makeProvider()
        let caller = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await provider.currentServiceToken()
        }
        let token = await caller.value
        let waiters = await provider.testingPendingTokenWaiterCount
        XCTAssertNil(token)
        XCTAssertEqual(waiters, 0)
        XCTAssertEqual(performer.generateKeyCalls, 0)
        XCTAssertEqual(transport.challengeCalls, 0)
    }

    func testCancellingOneWaiterReturnsImmediatelyAndOtherCallerKeepsAcquisition() async {
        let entered = expectation(description: "shared challenge pending")
        let cancelled = expectation(description: "cancelled waiter returned before shared challenge")
        let transport = SuspendedAttestTransport(entered: entered)
        let performer = FakePerformer()
        let provider = AppAttestServiceTokenProvider(performer: performer, transport: transport, secrets: MemorySecrets())
        let first = Task {
            let result = await provider.currentServiceToken()
            cancelled.fulfill()
            return result
        }
        await fulfillment(of: [entered], timeout: 2)
        let second = Task { await provider.currentServiceToken() }
        first.cancel()
        await fulfillment(of: [cancelled], timeout: 2)
        await transport.releaseChallenge()
        let firstToken = await first.value
        let secondToken = await second.value
        let waiters = await provider.testingPendingTokenWaiterCount
        let challengeCalls = await transport.challengeCalls
        let enrollCalls = await transport.enrollCalls
        XCTAssertNil(firstToken)
        XCTAssertEqual(secondToken, "shared-service-token")
        XCTAssertEqual(waiters, 0)
        XCTAssertEqual(challengeCalls, 1)
        XCTAssertEqual(enrollCalls, 1)
        XCTAssertEqual(performer.generateKeyCalls, 1)
    }

    func testCancelledSceneClientDoesNotWaitForAuthOrSendAJobRequest() async {
        let entered = expectation(description: "client waiting for shared auth")
        let cancelled = expectation(description: "client cancellation returned before auth")
        let transport = SuspendedAttestTransport(entered: entered)
        let provider = AppAttestServiceTokenProvider(performer: FakePerformer(), transport: transport, secrets: MemorySecrets())
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [CancelledAttestRequestProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }
        CancelledAttestRequestProtocol.reset()
        var configuration = SceneGenerationClientConfiguration.placeholder
        configuration.baseURL = URL(string: "https://cancelled-auth.example/v1")!
        let client = SceneGenerationClient(configuration: configuration, session: session, tokenProvider: provider)
        let caller = Task {
            defer { cancelled.fulfill() }
            do {
                _ = try await client.pollJob(jobID: "job-pending-auth")
                XCTFail("Cancelled auth cannot issue a job request")
            } catch {}
        }
        await fulfillment(of: [entered], timeout: 2)
        caller.cancel()
        await fulfillment(of: [cancelled], timeout: 2)
        XCTAssertEqual(CancelledAttestRequestProtocol.requestCount, 0)
        await transport.releaseChallenge()
        await caller.value
        let token = await provider.currentServiceToken()
        let waiters = await provider.testingPendingTokenWaiterCount
        XCTAssertEqual(token, "shared-service-token")
        XCTAssertEqual(waiters, 0)
        XCTAssertEqual(CancelledAttestRequestProtocol.requestCount, 0)
    }
}

/// Deterministic clock for expiry tests.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(start: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        value = start
    }
    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return value
    }
    func advance(_ seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        value = value.addingTimeInterval(seconds)
    }
}
