//
//  AppAttestServiceTokenProviderTests.swift
//  shafinMultitool
//
//  Contract tests for the App Attest enrollment client: capability gating,
//  one-time enrollment with token caching, key reuse, expiry-driven refresh,
//  and fail-closed degradation to nil.
//

import CryptoKit
import XCTest
@testable import shafinMultitool

private final class FakePerformer: AppAttestDevicePerforming, @unchecked Sendable {
    var isSupported = true
    var generatedKey = Data(repeating: 0x11, count: 32).base64EncodedString()
    var generateKeyCalls = 0
    var attestCalls = 0
    var lastAttestedHash: Data?
    var attestError: Error?

    func generateKey() async throws -> String {
        generateKeyCalls += 1
        return generatedKey
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        attestCalls += 1
        lastAttestedHash = clientDataHash
        if let attestError { throw attestError }
        return Data(repeating: 0x22, count: 64)
    }
}

private final class FakeTransport: AppAttestEnrollmentTransport, @unchecked Sendable {
    var challenge = Data(repeating: 0x33, count: 32)
    var ttlSeconds: TimeInterval? = 120
    var challengeCalls = 0
    var enrollCalls = 0
    var lastKeyID: Data?
    var lastClientDataHash: Data?
    var lastChallenge: Data?
    var challengeError: Error?
    var enrollError: Error?
    var tokenOverride: String?

    func requestChallenge() async throws -> (challenge: Data, expiresAt: Date?) {
        challengeCalls += 1
        if let challengeError { throw challengeError }
        return (challenge, nil)
    }

    func enroll(keyID: Data, clientDataHash: Data, challenge: Data, attestationObject: Data) async throws -> (token: String, ttlSeconds: TimeInterval?) {
        enrollCalls += 1
        lastKeyID = keyID
        lastClientDataHash = clientDataHash
        lastChallenge = challenge
        if let enrollError { throw enrollError }
        return (tokenOverride ?? "service-token-\(enrollCalls)", ttlSeconds)
    }
}

private final class MemorySecrets: AppAttestSecretStoring, @unchecked Sendable {
    var storage: [String: String] = [:]
    func string(forKey key: String) -> String? { storage[key] }
    func setString(_ value: String?, forKey key: String) {
        if let value { storage[key] = value } else { storage.removeValue(forKey: key) }
    }
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
            defaultTokenLifetimeSeconds: 3600,
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
