import CryptoKit
import DeviceCheck
import XCTest
@testable import shafinMultitool

private let deletionMarker = "appattest.installation_deletion_v1"
private let fixtureKey = Data(repeating: 0x31, count: 32).base64EncodedString()
private let fixturePolicy = String(repeating: "a", count: 64)
private let fixtureEndpoint = URL(string: "https://service.example/proxy/v1")!

private final class DeletionClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 2_000_000_000)
    func now() -> Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date = date.addingTimeInterval(seconds) } }
}

private final class DeletionSecrets: AppAttestSecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var failingKeys: Set<String> = []
    private var failingPhase: String?
    private var failCompletedMarker = false
    private var markerWriteAttempts: [String] = []
    init(enrolled: Bool = true) {
        if enrolled {
            values["appattest.key_id"] = fixtureKey
            values["appattest.enrolled_key_id"] = fixtureKey
            values["appattest.token"] = "expired-bearer"
            values["appattest.token_expiry"] = "1"
            values["appattest.token_refresh_at"] = "1"
        }
    }
    func string(forKey key: String) -> String? { lock.withLock { values[key] } }
    func setString(_ value: String?, forKey key: String) throws {
        try lock.withLock {
            if key == deletionMarker, let value { markerWriteAttempts.append(value) }
            if (key == deletionMarker && failCompletedMarker && value?.contains("\"localCredentialsCleared\":true") == true)
                || failingKeys.contains(key) || (key == deletionMarker && failingPhase.map {
                value?.contains("\"phase\":\"\($0)\"") == true
            } == true) { throw AppAttestEnrollmentError.secretStorage }
            values[key] = value
        }
    }
    func fail(keys: Set<String> = [], phase: String? = nil, completedMarker: Bool = false) {
        lock.withLock { failingKeys = keys; failingPhase = phase; failCompletedMarker = completedMarker }
    }
    func record() throws -> [String: Any] {
        let text = try XCTUnwrap(string(forKey: deletionMarker))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
    func attemptedRecords() throws -> [[String: Any]] {
        let attempts = lock.withLock { markerWriteAttempts }
        return try attempts.map { text in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        }
    }
}

private final class DeletionReceiptSecretFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var generated = 0
    var callCount: Int { lock.withLock { generated } }
    func make() -> Data {
        lock.withLock {
            generated += 1
            return Data(repeating: UInt8(truncatingIfNeeded: generated), count: 32)
        }
    }
}

private final class DeletionReadFaultSecrets: AppAttestSecretStoring, @unchecked Sendable {
    private let base: DeletionSecrets
    private let lock = NSLock()
    private var readsFailing = false
    init(_ base: DeletionSecrets) { self.base = base }
    func failReads(_ fail: Bool) { lock.withLock { readsFailing = fail } }
    func string(forKey key: String) throws -> String? {
        if lock.withLock({ readsFailing }) { throw AppAttestEnrollmentError.secretStorage }
        return base.string(forKey: key)
    }
    func setString(_ value: String?, forKey key: String) throws {
        try base.setString(value, forKey: key)
    }
}

private actor DeletionGate {
    let entered: XCTestExpectation
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    init(_ entered: XCTestExpectation) { self.entered = entered }
    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { pending in continuation = pending; entered.fulfill() }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

private actor DeletionPerformer: AppAttestDevicePerforming {
    nonisolated let isSupported = true
    private(set) var keyCalls = 0
    private(set) var attestCalls = 0
    private(set) var assertions: [(String, Data)] = []
    var assertionGate: DeletionGate?
    var error: Error?
    init(assertionGate: DeletionGate? = nil, error: Error? = nil) {
        self.assertionGate = assertionGate
        self.error = error
    }
    func generateKey() async throws -> String { keyCalls += 1; return fixtureKey }
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        attestCalls += 1
        return Data(repeating: 0x20, count: 64)
    }
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        assertions.append((keyID, clientDataHash))
        if let assertionGate { await assertionGate.wait() }
        if let error { throw error }
        return Data(repeating: UInt8(assertions.count), count: 64)
    }
}

private actor DeletionEnrollment: AppAttestEnrollmentTransport {
    let clock: DeletionClock
    let refreshGate: DeletionGate?
    let refreshError: AppAttestEnrollmentError?
    private(set) var challengeCalls = 0
    private(set) var enrollCalls = 0
    private(set) var refreshCalls = 0
    init(_ clock: DeletionClock, refreshGate: DeletionGate? = nil, refreshError: AppAttestEnrollmentError? = nil) {
        self.clock = clock; self.refreshGate = refreshGate; self.refreshError = refreshError
    }
    func requestChallenge() async throws -> (challenge: Data, expiresAt: Date?) {
        challengeCalls += 1
        return (Data(repeating: 0x11, count: 32), clock.now().addingTimeInterval(60))
    }
    func enroll(keyID: Data, clientDataHash: Data, challenge: Data, attestationObject: Data) async throws -> (token: String, ttlSeconds: TimeInterval?) {
        enrollCalls += 1
        return ("new-enrollment-token", 3_600)
    }
    func refresh(keyID: Data, clientDataHash: Data, challenge: Data, assertionObject: Data) async throws -> (token: String, ttlSeconds: TimeInterval?) {
        refreshCalls += 1
        if let refreshGate { await refreshGate.wait() }
        if let refreshError { throw refreshError }
        return ("late-refreshed-token", 3_600)
    }
}

private actor DeletionHTTP: InstallationDeletionTransport {
    nonisolated let serviceEndpoint: URL
    let clock: DeletionClock
    let submitGate: DeletionGate?
    let inspectChallenge: (@Sendable (String, String) -> Void)?
    let inspectProof: (@Sendable (InstallationDeletionProof) -> Void)?
    private var submitResults: [Result<String, InstallationDeletionError>]
    private var pollResults: [Result<String, InstallationDeletionError>]
    private var challengeErrors: [InstallationDeletionError]
    private let wrongBinding: Bool
    private(set) var challenges: [(String, String)] = []
    private(set) var proofs: [InstallationDeletionProof] = []
    private(set) var polls: [(String, Data)] = []
    init(_ clock: DeletionClock, endpoint: URL = fixtureEndpoint,
         submits: [Result<String, InstallationDeletionError>] = [.success("complete")],
         polls: [Result<String, InstallationDeletionError>] = [.success("complete")],
         challengeErrors: [InstallationDeletionError] = [], wrongBinding: Bool = false,
         submitGate: DeletionGate? = nil,
         inspectChallenge: (@Sendable (String, String) -> Void)? = nil,
         inspectProof: (@Sendable (InstallationDeletionProof) -> Void)? = nil) {
        self.clock = clock; serviceEndpoint = endpoint; submitResults = submits; pollResults = polls
        self.challengeErrors = challengeErrors; self.wrongBinding = wrongBinding
        self.submitGate = submitGate; self.inspectChallenge = inspectChallenge; self.inspectProof = inspectProof
    }
    func requestChallenge(keyID: Data, operationID: String, policySHA256: String) async throws -> InstallationDeletionChallenge {
        inspectChallenge?(operationID, policySHA256)
        challenges.append((operationID, policySHA256))
        if !challengeErrors.isEmpty { throw challengeErrors.removeFirst() }
        return InstallationDeletionChallenge(challenge: Data(repeating: UInt8(challenges.count), count: 32),
                                             expiresAt: clock.now().addingTimeInterval(60), policySHA256: policySHA256)
    }
    func submit(_ proof: InstallationDeletionProof) async throws -> InstallationDeletionReceipt {
        proofs.append(proof); inspectProof?(proof)
        if let submitGate { await submitGate.wait() }
        let status = try (submitResults.isEmpty ? .success("complete") : submitResults.removeFirst()).get()
        return receiptValue(proof.operationID, policy: proof.policySHA256, status: status)
    }
    func receipt(operationID: String, secret: Data, policySHA256: String) async throws -> InstallationDeletionReceipt {
        polls.append((operationID, secret))
        let status = try (pollResults.isEmpty ? .success("complete") : pollResults.removeFirst()).get()
        return receiptValue(operationID, policy: policySHA256, status: status)
    }
    private func receiptValue(_ operation: String, policy: String, status: String) -> InstallationDeletionReceipt {
        InstallationDeletionReceipt(
            operationID: wrongBinding ? UUID().uuidString.lowercased() : operation,
            status: status, policySHA256: policy, receiptExpiresAt: clock.now().addingTimeInterval(86_400),
            scope: InstallationDeletionReceipt.expectedScope, policyQualification: "not_asserted",
            retainedCategories: Array(InstallationDeletionReceipt.expectedRetainedCategories).sorted()
        )
    }
}

final class InstallationDeletionLifecycleTests: XCTestCase {
    private func provider(_ secrets: DeletionSecrets, _ clock: DeletionClock,
                          performer: DeletionPerformer = DeletionPerformer(),
                          enrollment: DeletionEnrollment? = nil, deletion: DeletionHTTP? = nil,
                          policy: String? = fixturePolicy,
                          makeReceiptSecret: @escaping @Sendable () throws -> Data = { Data(repeating: 0x71, count: 32) }) -> AppAttestServiceTokenProvider {
        AppAttestServiceTokenProvider(
            performer: performer, transport: enrollment ?? DeletionEnrollment(clock), secrets: secrets,
            now: { clock.now() }, deletionTransport: deletion ?? DeletionHTTP(clock),
            deletionPolicyFingerprint: policy, makeReceiptSecret: makeReceiptSecret
        )
    }

    func testNoInstallationDoesNotManufactureIdentity() async {
        let secrets = DeletionSecrets(enrolled: false), clock = DeletionClock()
        let device = DeletionPerformer(), http = DeletionHTTP(clock)
        let client = provider(secrets, clock, performer: device, deletion: http)
        let initial = await client.installationDeletionState()
        let result = await client.beginInstallationDeletion()
        XCTAssertEqual(initial, .noInstallation); XCTAssertEqual(result, .noInstallation)
        let keys = await device.keyCalls, challenges = await http.challenges.count
        XCTAssertEqual(keys, 0); XCTAssertEqual(challenges, 0)
        XCTAssertNil(secrets.string(forKey: deletionMarker))
    }

    func testUnattestedLocalKeyIsNotAServerInstallation() async throws {
        let secrets = DeletionSecrets(enrolled: false), clock = DeletionClock()
        try secrets.setString(fixtureKey, forKey: "appattest.key_id")
        let http = DeletionHTTP(clock)
        let client = provider(secrets, clock, deletion: http)
        let state = await client.beginInstallationDeletion()
        XCTAssertEqual(state, .noInstallation)
        XCTAssertNil(secrets.string(forKey: deletionMarker))
        let calls = await http.challenges.count
        XCTAssertEqual(calls, 0)
    }

    func testExpiredBearerDeletionPersistsProofBeforePostAndRetiresCredentials() async throws {
        let secrets = DeletionSecrets(), clock = DeletionClock(), device = DeletionPerformer()
        let http = DeletionHTTP(clock, inspectProof: { proof in
            guard let text = secrets.string(forKey: deletionMarker),
                  let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                  let stored = json["proof"] as? [String: Any] else {
                XCTFail("POST began without durable opaque proof"); return
            }
            XCTAssertEqual(stored["assertion_object"] as? String, proof.assertionObject)
            XCTAssertEqual(json["phase"] as? String, "proofReady")
            XCTAssertNotNil(json["receiptSecret"])
        })
        let client = provider(secrets, clock, performer: device, deletion: http)
        let result = await client.beginInstallationDeletion()
        XCTAssertEqual(result, .complete)
        for key in ["key_id", "token", "token_expiry", "token_refresh_at", "enrolled_key_id", "attested_key_id"] {
            XCTAssertNil(secrets.string(forKey: "appattest." + key))
        }
        let submitted = await http.proofs
        let proof = try XCTUnwrap(submitted.first)
        let assertions = await device.assertions
        XCTAssertEqual(assertions.count, 1)
        XCTAssertEqual(assertions.first?.0, fixtureKey)
        XCTAssertEqual(assertions.first?.1, Data(SHA256.hash(data: try proof.canonicalClientData())))
        let restored = provider(secrets, clock, performer: device, deletion: http)
        let token = await restored.currentServiceToken(), state = await restored.installationDeletionState()
        XCTAssertNil(token); XCTAssertEqual(state, .complete)
        let keys = await device.keyCalls
        XCTAssertEqual(keys, 0)
    }

    func testLostPostResponseRestoresExactProofWithoutResigningEvenAfterPolicyChange() async throws {
        let secrets = DeletionSecrets(), clock = DeletionClock(), device = DeletionPerformer()
        let http = DeletionHTTP(clock, submits: [.failure(.transport), .success("complete")])
        let first = provider(secrets, clock, performer: device, deletion: http)
        let uncertain = await first.beginInstallationDeletion()
        XCTAssertEqual(uncertain, .uncertain)
        let second = provider(secrets, clock, performer: device, deletion: http, policy: String(repeating: "b", count: 64))
        let result = await second.resumeInstallationDeletion()
        XCTAssertEqual(result, .complete)
        let proofs = await http.proofs, assertions = await device.assertions.count, challenges = await http.challenges.count
        XCTAssertEqual(proofs.count, 2); XCTAssertEqual(proofs[0], proofs[1])
        XCTAssertEqual(try proofs[0].encodedBody(), try proofs[1].encodedBody())
        XCTAssertEqual(assertions, 1); XCTAssertEqual(challenges, 1)
    }

    func testPendingRelaunchUsesReceiptOnlyAnd404RemainsUncertain() async throws {
        let secrets = DeletionSecrets(), clock = DeletionClock(), device = DeletionPerformer()
        let http = DeletionHTTP(clock, submits: [.success("deleting")], polls: [.failure(.receiptUnavailable)])
        let first = provider(secrets, clock, performer: device, deletion: http)
        let pending = await first.beginInstallationDeletion()
        XCTAssertEqual(pending, .pending)
        let restored = provider(secrets, clock, performer: device, deletion: http)
        let uncertain = await restored.resumeInstallationDeletion()
        XCTAssertEqual(uncertain, .uncertain)
        let proofs = await http.proofs.count, polls = await http.polls, assertions = await device.assertions.count
        XCTAssertEqual(proofs, 1); XCTAssertEqual(polls.count, 1); XCTAssertEqual(assertions, 1)
        XCTAssertEqual(polls.first?.1, Data(repeating: 0x71, count: 32))
        XCTAssertEqual(secrets.string(forKey: "appattest.key_id"), fixtureKey)
        let token = await restored.currentServiceToken()
        XCTAssertNil(token)
    }

    func testExpiredReceiptNeverMeansCompleteAndMakesNoPoll() async {
        let secrets = DeletionSecrets(), clock = DeletionClock()
        let http = DeletionHTTP(clock, submits: [.success("deleting")])
        let client = provider(secrets, clock, deletion: http)
        let pending = await client.beginInstallationDeletion()
        XCTAssertEqual(pending, .pending)
        clock.advance(86_401)
        let state = await client.resumeInstallationDeletion()
        XCTAssertEqual(state, .uncertain)
        let calls = await http.polls.count
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(secrets.string(forKey: "appattest.key_id"), fixtureKey)
    }

    func testReceiptForAnotherOperationCannotClearCredentials() async {
        let secrets = DeletionSecrets(), clock = DeletionClock()
        let http = DeletionHTTP(clock, wrongBinding: true)
        let client = provider(secrets, clock, deletion: http)
        let result = await client.beginInstallationDeletion()
        XCTAssertEqual(result, .failed(.malformedResponse))
        XCTAssertEqual(secrets.string(forKey: "appattest.key_id"), fixtureKey)
        let token = await client.currentServiceToken()
        XCTAssertNil(token)
    }

    func testInitialIntentStorageFailureStopsNetworkAndCachedToken() async throws {
        let secrets = DeletionSecrets(), clock = DeletionClock(), device = DeletionPerformer()
        try secrets.setString("cached-token", forKey: "appattest.token")
        try secrets.setString(String(clock.now().addingTimeInterval(600).timeIntervalSince1970), forKey: "appattest.token_expiry")
        try secrets.setString(String(clock.now().addingTimeInterval(500).timeIntervalSince1970), forKey: "appattest.token_refresh_at")
        secrets.fail(keys: [deletionMarker])
        let http = DeletionHTTP(clock)
        let client = provider(secrets, clock, performer: device, deletion: http)
        let result = await client.beginInstallationDeletion(), token = await client.currentServiceToken()
        XCTAssertEqual(result, .failed(.secretStorage)); XCTAssertNil(token)
        let calls = await http.challenges.count, assertions = await device.assertions.count
        XCTAssertEqual(calls, 0); XCTAssertEqual(assertions, 0)
        secrets.fail()
        let retry = await client.resumeInstallationDeletion()
        XCTAssertEqual(retry, .complete)
    }

    func testRepeatedResumeAfterInitialStorageFailureKeepsSameIntentUntilPersistenceSucceeds() async throws {
        let secrets = DeletionSecrets(), clock = DeletionClock(), device = DeletionPerformer()
        let factory = DeletionReceiptSecretFactory(), enrollment = DeletionEnrollment(clock)
        secrets.fail(keys: [deletionMarker])
        let http = DeletionHTTP(clock, inspectChallenge: { operationID, policy in
            do {
                let stored = try secrets.record()
                let original = try XCTUnwrap(secrets.attemptedRecords().first)
                XCTAssertEqual(stored["phase"] as? String, "preparing")
                XCTAssertEqual(stored["operationID"] as? String, operationID)
                XCTAssertEqual(stored["policySHA256"] as? String, policy)
                XCTAssertEqual(stored["operationID"] as? String, original["operationID"] as? String)
                XCTAssertEqual(stored["receiptSecret"] as? String, original["receiptSecret"] as? String)
            } catch {
                XCTFail("Deletion challenge began without the original durable intent: \(error)")
            }
        }, inspectProof: { proof in
            do {
                let stored = try secrets.record()
                let original = try XCTUnwrap(secrets.attemptedRecords().first)
                let rawSecret = try XCTUnwrap(original["receiptSecret"] as? String)
                let secret = try XCTUnwrap(Data(base64Encoded: rawSecret))
                let expectedHash = SHA256.hash(data: secret).map { String(format: "%02x", $0) }.joined()
                XCTAssertEqual(stored["phase"] as? String, "proofReady")
                XCTAssertEqual(proof.operationID, original["operationID"] as? String)
                XCTAssertEqual(proof.receiptSecretSHA256, expectedHash)
            } catch {
                XCTFail("Deletion POST began without the original durable proof: \(error)")
            }
        })
        let client = provider(secrets, clock, performer: device, enrollment: enrollment,
                              deletion: http, makeReceiptSecret: { factory.make() })
        let initial = await client.beginInstallationDeletion()
        XCTAssertEqual(initial, .failed(.secretStorage))
        for _ in 0..<2 {
            clock.advance(1)
            let retry = await client.resumeInstallationDeletion()
            XCTAssertEqual(retry, .failed(.secretStorage))
            XCTAssertNil(secrets.string(forKey: deletionMarker))
            let token = await client.currentServiceToken()
            XCTAssertNil(token)
        }
        let failedAttempts = try secrets.attemptedRecords()
        XCTAssertEqual(failedAttempts.count, 3)
        let original = try XCTUnwrap(failedAttempts.first)
        let originalOperation = try XCTUnwrap(original["operationID"] as? String)
        let originalSecret = try XCTUnwrap(original["receiptSecret"] as? String)
        XCTAssertEqual(UUID(uuidString: originalOperation)?.uuidString.lowercased(), originalOperation)
        XCTAssertEqual(Data(base64Encoded: originalSecret)?.count, 32)
        XCTAssertEqual(factory.callCount, 1)
        for attempt in failedAttempts {
            XCTAssertEqual(attempt["operationID"] as? String, originalOperation)
            XCTAssertEqual(attempt["receiptSecret"] as? String, originalSecret)
            XCTAssertEqual(attempt["phase"] as? String, "preparing")
            XCTAssertNil(attempt["proof"])
        }
        let keysBefore = await device.keyCalls, attestsBefore = await device.attestCalls
        let assertionsBefore = await device.assertions.count
        let enrollmentChallenges = await enrollment.challengeCalls, enrollsBefore = await enrollment.enrollCalls
        let refreshesBefore = await enrollment.refreshCalls
        let challengesBefore = await http.challenges.count, postsBefore = await http.proofs.count
        XCTAssertEqual(keysBefore, 0); XCTAssertEqual(attestsBefore, 0); XCTAssertEqual(assertionsBefore, 0)
        XCTAssertEqual(enrollmentChallenges, 0); XCTAssertEqual(enrollsBefore, 0); XCTAssertEqual(refreshesBefore, 0)
        XCTAssertEqual(challengesBefore, 0); XCTAssertEqual(postsBefore, 0)

        secrets.fail()
        clock.advance(1)
        let completed = await client.resumeInstallationDeletion()
        XCTAssertEqual(completed, .complete)
        let persisted = try secrets.record()
        XCTAssertEqual(persisted["operationID"] as? String, originalOperation)
        XCTAssertEqual(persisted["receiptSecret"] as? String, originalSecret)
        XCTAssertEqual(factory.callCount, 1)
        let challengesAfter = await http.challenges.count, postsAfter = await http.proofs.count
        let assertionsAfter = await device.assertions.count, keysAfter = await device.keyCalls
        XCTAssertEqual(challengesAfter, 1); XCTAssertEqual(postsAfter, 1)
        XCTAssertEqual(assertionsAfter, 1); XCTAssertEqual(keysAfter, 0)
    }

    func testResumeAfterInitialKeychainReadFailureReturnsToConfirmationWithoutStartingDeletion() async {
        let base = DeletionSecrets(), clock = DeletionClock(), device = DeletionPerformer()
        let secrets = DeletionReadFaultSecrets(base), factory = DeletionReceiptSecretFactory()
        let http = DeletionHTTP(clock), enrollment = DeletionEnrollment(clock)
        secrets.failReads(true)
        let client = AppAttestServiceTokenProvider(
            performer: device, transport: enrollment, secrets: secrets,
            now: { clock.now() }, deletionTransport: http,
            deletionPolicyFingerprint: fixturePolicy, makeReceiptSecret: { factory.make() }
        )
        let failed = await client.beginInstallationDeletion()
        XCTAssertEqual(failed, .failed(.secretStorage))
        XCTAssertNil(base.string(forKey: deletionMarker))
        secrets.failReads(false)
        let resumed = await client.resumeInstallationDeletion()
        XCTAssertEqual(resumed, .ready)
        let presented = await client.installationDeletionState()
        XCTAssertEqual(presented, .ready)
        XCTAssertNil(base.string(forKey: deletionMarker))
        XCTAssertEqual(base.string(forKey: "appattest.key_id"), fixtureKey)
        XCTAssertEqual(factory.callCount, 0)
        let challenges = await http.challenges.count, posts = await http.proofs.count
        let assertions = await device.assertions.count, keys = await device.keyCalls
        let attestations = await device.attestCalls, enrolls = await enrollment.enrollCalls
        let enrollmentChallenges = await enrollment.challengeCalls, refreshes = await enrollment.refreshCalls
        XCTAssertEqual(challenges, 0); XCTAssertEqual(posts, 0)
        XCTAssertEqual(assertions, 0); XCTAssertEqual(keys, 0); XCTAssertEqual(attestations, 0)
        XCTAssertEqual(enrolls, 0); XCTAssertEqual(enrollmentChallenges, 0); XCTAssertEqual(refreshes, 0)
    }

    func testOpaqueProofStorageFailureNeverPostsAndCanRetryUnsubmittedPreparation() async {
        let secrets = DeletionSecrets(), clock = DeletionClock(), device = DeletionPerformer()
        secrets.fail(phase: "proofReady")
        let http = DeletionHTTP(clock)
        let first = provider(secrets, clock, performer: device, deletion: http)
        let failed = await first.beginInstallationDeletion()
        XCTAssertEqual(failed, .failed(.secretStorage))
        let posted = await http.proofs.count
        XCTAssertEqual(posted, 0)
        secrets.fail()
        let restored = provider(secrets, clock, performer: device, deletion: http)
        let result = await restored.resumeInstallationDeletion()
        XCTAssertEqual(result, .complete)
        let challenges = await http.challenges, proofs = await http.proofs.count
        XCTAssertEqual(challenges.count, 2); XCTAssertEqual(challenges[0].0, challenges[1].0)
        XCTAssertEqual(proofs, 1)
    }

    func testCompletedReceiptCleanupFailureRetriesLocallyWithoutSecondPost() async {
        let secrets = DeletionSecrets(), clock = DeletionClock()
        secrets.fail(keys: ["appattest.enrolled_key_id"])
        let http = DeletionHTTP(clock)
        let first = provider(secrets, clock, deletion: http)
        let failed = await first.beginInstallationDeletion()
        XCTAssertEqual(failed, .failed(.secretStorage))
        XCTAssertNil(secrets.string(forKey: "appattest.token"))
        XCTAssertEqual(secrets.string(forKey: "appattest.key_id"), fixtureKey)
        secrets.fail()
        let restored = provider(secrets, clock, deletion: http)
        let result = await restored.resumeInstallationDeletion()
        XCTAssertEqual(result, .complete)
        let polls = await http.polls.count, posts = await http.proofs.count
        XCTAssertEqual(polls, 0); XCTAssertEqual(posts, 1)
        XCTAssertNil(secrets.string(forKey: "appattest.key_id"))
    }

    func testFinalCompletionMarkerFailureRecoversWithoutReenrollmentOrRemoteRequest() async {
        let secrets = DeletionSecrets(), clock = DeletionClock(), device = DeletionPerformer()
        secrets.fail(completedMarker: true)
        let http = DeletionHTTP(clock)
        let first = provider(secrets, clock, performer: device, deletion: http)
        let failed = await first.beginInstallationDeletion()
        XCTAssertEqual(failed, .failed(.secretStorage))
        XCTAssertNil(secrets.string(forKey: "appattest.key_id"))
        XCTAssertNil(secrets.string(forKey: "appattest.token"))
        secrets.fail()
        let restored = provider(secrets, clock, performer: device, deletion: http)
        let token = await restored.currentServiceToken(), state = await restored.resumeInstallationDeletion()
        XCTAssertNil(token); XCTAssertEqual(state, .complete)
        let keys = await device.keyCalls, proofs = await http.proofs.count, polls = await http.polls.count
        XCTAssertEqual(keys, 0); XCTAssertEqual(proofs, 1); XCTAssertEqual(polls, 0)
    }

    func testDeletionDrainsLateRefreshBeforeSigningAndCannotCacheReturnedToken() async {
        let entered = expectation(description: "refresh in flight"), gate = DeletionGate(entered)
        let secrets = DeletionSecrets(), clock = DeletionClock(), device = DeletionPerformer()
        let enrollment = DeletionEnrollment(clock, refreshGate: gate), http = DeletionHTTP(clock)
        let client = provider(secrets, clock, performer: device, enrollment: enrollment, deletion: http)
        let acquisition = Task { await client.currentServiceToken() }
        await fulfillment(of: [entered], timeout: 2)
        let deletion = Task { await client.beginInstallationDeletion() }
        for _ in 0..<100 where secrets.string(forKey: deletionMarker) == nil { await Task.yield() }
        XCTAssertNotNil(secrets.string(forKey: deletionMarker))
        let token = await acquisition.value, blocked = await client.currentServiceToken()
        XCTAssertNil(token); XCTAssertNil(blocked)
        let premature = await http.challenges.count
        XCTAssertEqual(premature, 0)
        await gate.release()
        let state = await deletion.value
        XCTAssertEqual(state, .complete)
        let assertions = await device.assertions.count, keys = await device.keyCalls
        XCTAssertEqual(assertions, 2); XCTAssertEqual(keys, 0)
        XCTAssertNil(secrets.string(forKey: "appattest.token"))
    }

    func testLateRefreshTypedAbsenceCannotCreateAnotherInstallationDuringDeletion() async {
        let entered = expectation(description: "refresh in flight"), gate = DeletionGate(entered)
        let secrets = DeletionSecrets(), clock = DeletionClock(), device = DeletionPerformer()
        let enrollment = DeletionEnrollment(clock, refreshGate: gate, refreshError: .installationNotEnrolled)
        let client = provider(secrets, clock, performer: device, enrollment: enrollment)
        let acquisition = Task { await client.currentServiceToken() }
        await fulfillment(of: [entered], timeout: 2)
        let deletion = Task { await client.beginInstallationDeletion() }
        for _ in 0..<100 where secrets.string(forKey: deletionMarker) == nil { await Task.yield() }
        await gate.release()
        let state = await deletion.value, token = await acquisition.value
        XCTAssertEqual(state, .complete); XCTAssertNil(token)
        let generated = await device.keyCalls, enrolled = await enrollment.enrollCalls
        XCTAssertEqual(generated, 0); XCTAssertEqual(enrolled, 0)
    }

    func testConcurrentBeginsShareOneProofAndWaiterCancellationDoesNotUndoDeletion() async {
        let entered = expectation(description: "POST in flight"), gate = DeletionGate(entered)
        let secrets = DeletionSecrets(), clock = DeletionClock(), device = DeletionPerformer()
        let http = DeletionHTTP(clock, submitGate: gate)
        let client = provider(secrets, clock, performer: device, deletion: http)
        let first = Task { await client.beginInstallationDeletion() }
        await fulfillment(of: [entered], timeout: 2)
        let second = Task { await client.beginInstallationDeletion() }
        first.cancel()
        await gate.release()
        let a = await first.value, b = await second.value
        XCTAssertEqual(a, .complete); XCTAssertEqual(b, .complete)
        let proofs = await http.proofs.count, assertions = await device.assertions.count
        XCTAssertEqual(proofs, 1); XCTAssertEqual(assertions, 1)
    }

    func testCorruptIntentNeverBecomesMissingInstallationOrFreshEnrollment() async throws {
        let secrets = DeletionSecrets(), clock = DeletionClock(), device = DeletionPerformer()
        try secrets.setString("{truncated", forKey: deletionMarker)
        let client = provider(secrets, clock, performer: device)
        let state = await client.resumeInstallationDeletion(), token = await client.currentServiceToken()
        XCTAssertEqual(state, .failed(.invalidState)); XCTAssertNil(token)
        let generated = await device.keyCalls
        XCTAssertEqual(generated, 0)
    }

    func testMissingPublicPolicyPreventsNewDeletionWithoutMutatingIdentity() async {
        let secrets = DeletionSecrets(), clock = DeletionClock(), http = DeletionHTTP(DeletionClock())
        let client = provider(secrets, clock, deletion: http, policy: nil)
        let state = await client.beginInstallationDeletion()
        XCTAssertEqual(state, .unavailable)
        XCTAssertNil(secrets.string(forKey: deletionMarker))
        XCTAssertEqual(secrets.string(forKey: "appattest.key_id"), fixtureKey)
        let calls = await http.challenges.count
        XCTAssertEqual(calls, 0)
    }

    func testInterruptedPreparationKeepsSameOperationAndSecretAcrossRestart() async throws {
        let secrets = DeletionSecrets(), clock = DeletionClock(), device = DeletionPerformer()
        let http = DeletionHTTP(clock, challengeErrors: [.transport])
        let first = provider(secrets, clock, performer: device, deletion: http)
        let failed = await first.beginInstallationDeletion()
        XCTAssertEqual(failed, .failed(.transport))
        let before = try secrets.record()
        XCTAssertNil(before["proof"])
        let restored = provider(secrets, clock, performer: device, deletion: http)
        let state = await restored.resumeInstallationDeletion()
        XCTAssertEqual(state, .complete)
        let after = try secrets.record(), challenges = await http.challenges
        XCTAssertEqual(before["operationID"] as? String, after["operationID"] as? String)
        XCTAssertEqual(before["receiptSecret"] as? String, after["receiptSecret"] as? String)
        XCTAssertEqual(challenges.count, 2); XCTAssertEqual(challenges[0].0, challenges[1].0)
    }

    func testExpiredChallengeDuringDeviceSigningNeverSubmits() async {
        let entered = expectation(description: "signing"), gate = DeletionGate(entered)
        let secrets = DeletionSecrets(), clock = DeletionClock(), device = DeletionPerformer(assertionGate: gate)
        let http = DeletionHTTP(clock)
        let client = provider(secrets, clock, performer: device, deletion: http)
        let deletion = Task { await client.beginInstallationDeletion() }
        await fulfillment(of: [entered], timeout: 2)
        clock.advance(61); await gate.release()
        let state = await deletion.value
        XCTAssertEqual(state, .failed(.invalidState))
        let posts = await http.proofs.count
        XCTAssertEqual(posts, 0)
    }

    func testPersistedOperationCannotMoveToAnotherEndpoint() async {
        let secrets = DeletionSecrets(), clock = DeletionClock()
        let oldHTTP = DeletionHTTP(clock, submits: [.failure(.transport)])
        let original = provider(secrets, clock, deletion: oldHTTP)
        let uncertain = await original.beginInstallationDeletion()
        XCTAssertEqual(uncertain, .uncertain)
        let newHTTP = DeletionHTTP(clock, endpoint: URL(string: "https://different.example/v1")!)
        let restored = provider(secrets, clock, deletion: newHTTP)
        let state = await restored.resumeInstallationDeletion(), token = await restored.currentServiceToken()
        XCTAssertEqual(state, .failed(.invalidState)); XCTAssertNil(token)
        let posts = await newHTTP.proofs.count, calls = await newHTTP.challenges.count
        XCTAssertEqual(posts, 0); XCTAssertEqual(calls, 0)
    }

    func testMalformedResponseKeepsOpaqueProofForExactRetry() async {
        let secrets = DeletionSecrets(), clock = DeletionClock(), device = DeletionPerformer()
        let http = DeletionHTTP(clock, submits: [.failure(.malformedResponse), .success("complete")])
        let client = provider(secrets, clock, performer: device, deletion: http)
        let failure = await client.beginInstallationDeletion()
        XCTAssertEqual(failure, .failed(.malformedResponse))
        let restored = provider(secrets, clock, performer: device, deletion: http)
        let result = await restored.resumeInstallationDeletion()
        XCTAssertEqual(result, .complete)
        let proofs = await http.proofs, assertions = await device.assertions.count
        XCTAssertEqual(proofs.count, 2); XCTAssertEqual(proofs[0], proofs[1]); XCTAssertEqual(assertions, 1)
    }
}
