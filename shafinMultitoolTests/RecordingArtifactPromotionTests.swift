//
//  RecordingArtifactPromotionTests.swift
//  shafinMultitoolTests
//
//  M1-014 MediaLifecycleOwner: Pending artifact promotion is one durable
//  transaction keyed by the recording ID. These tests pin the concurrency and
//  interruption invariants that the sequential promotion tests do not cover:
//  concurrent promotion stores exactly one file, an interrupted promotion
//  resumes idempotently, and a conflicting destination fails with the pending
//  source preserved.
//

import XCTest
@testable import shafinMultitool

final class RecordingArtifactPromotionTests: XCTestCase {

    private var applicationSupportURL: URL!
    private var store: RecordingArtifactStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("artifact-promotion-\(UUID().uuidString)", isDirectory: true)
        store = try RecordingArtifactStore(applicationSupportDirectoryURL: applicationSupportURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: applicationSupportURL)
        store = nil
        applicationSupportURL = nil
        try super.tearDownWithError()
    }

    func testConcurrentPromotionOfSameArtifactStoresExactlyOneFileAndReturnsSameReference() throws {
        let artifact = try makePendingArtifact()
        let projectID = UUID()

        let box = ReferenceBox()
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            do {
                let reference = try store.promoteFinalizedArtifact(artifact, projectID: projectID)
                box.append(reference)
            } catch {
                box.appendFailure("\(error)")
            }
        }

        XCTAssertEqual(
            box.failures,
            [],
            "every concurrent promotion must resolve idempotently"
        )
        let references = box.references
        XCTAssertEqual(references.count, 8)
        XCTAssertFalse(references.isEmpty)
        XCTAssertTrue(
            references.allSatisfy { $0 == references[0] },
            "all callers must receive the same reference"
        )
        XCTAssertEqual(references[0].recordingID, artifact.id.rawValue)

        let projectDirectory = store.projectsDirectoryURL
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
        let entries = try FileManager.default.contentsOfDirectory(atPath: projectDirectory.path)
        XCTAssertEqual(entries, ["\(artifact.id.rawValue.uuidString).mov"], "exactly one artifact file may be stored")

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: artifact.localURL.path),
            "the pending source must be consumed by the winning rename"
        )
        XCTAssertNotNil(store.resolve(references[0]))
    }

    func testPromotionAfterInterruptionResumesIdempotentlyWhenDestinationExists() throws {
        let artifact = try makePendingArtifact()
        let projectID = UUID()

        let first = try store.promoteFinalizedArtifact(artifact, projectID: projectID)

        // Simulate a caller that crashed after the atomic rename committed but
        // before it learned the result: the pending source is gone, the
        // destination exists. The retried transaction must report the same
        // reference instead of failing or duplicating.
        let retried = try store.promoteFinalizedArtifact(artifact, projectID: projectID)

        XCTAssertEqual(retried, first)
        XCTAssertEqual(store.resolveArtifact(retried)?.localURL, store.resolve(first))
    }

    func testPromotionWithNonRegularDestinationFailsWithConflictAndKeepsPendingSource() throws {
        let artifact = try makePendingArtifact()
        let projectID = UUID()

        let projectDirectory = store.projectsDirectoryURL
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: projectDirectory.appendingPathComponent("\(artifact.id.rawValue.uuidString).mov"),
            withIntermediateDirectories: true
        )

        XCTAssertThrowsError(try store.promoteFinalizedArtifact(artifact, projectID: projectID)) { error in
            XCTAssertEqual(error as? RecordingArtifactStoreError, .destinationConflict)
        }

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: artifact.localURL.path),
            "a failed promotion must leave the pending source untouched for recovery"
        )
    }

    func testPromotionWithMissingSourceAndMissingDestinationFailsWithType() throws {
        let artifact = try makePendingArtifact()
        try FileManager.default.removeItem(at: artifact.localURL)

        XCTAssertThrowsError(try store.promoteFinalizedArtifact(artifact, projectID: UUID())) { error in
            XCTAssertEqual(error as? RecordingArtifactStoreError, .pendingSourceMissing)
        }
    }

    // MARK: - M7-020 promotion fault matrix (crash-point convergence)

    /// Drives the deterministic crash point, then verifies the state after
    /// the "crash" and that a retried promotion converges to exactly one
    /// valid reference with no duplicate file and a durable unacknowledged journal.
    private func attemptAndRecover(faultPoint: RecordingArtifactStore.PromotionFaultPoint) throws {
        let artifact = try makePendingArtifact()
        let projectID = UUID()

        store.testPromotionFaultPoint = faultPoint
        XCTAssertThrowsError(try store.promoteFinalizedArtifact(artifact, projectID: projectID)) { error in
            XCTAssertTrue(
                error is PendingRecordingJournalError,
                "the injected crash must surface as a typed failure, got \(error)"
            )
        }

        // After every crash point the pending/destination pair is never
        // duplicated: exactly one of them (or the committed destination)
        // holds the bytes, and existing project media is untouched.
        let destinationURL = store.projectsDirectoryURL
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent("\(artifact.id.rawValue.uuidString).mov")

        let reference = try store.promoteFinalizedArtifact(artifact, projectID: projectID)
        XCTAssertEqual(reference.recordingID, artifact.id.rawValue)

        XCTAssertEqual(store.resolve(reference)?.standardizedFileURL, destinationURL.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: artifact.localURL.path),
            "recovery must consume the pending source exactly once"
        )
        XCTAssertEqual(
            try store.journal.entry(for: artifact.id.rawValue)?.state,
            .promoted,
            "a filesystem commit must retain intent until its project reference is durable"
        )
        store.testPromotionFaultPoint = nil
    }

    func testPromotionRecoversFromCrashBeforeJournalWrite() throws {
        try attemptAndRecover(faultPoint: .beforeJournalWrite)
    }

    func testPromotionRecoversFromCrashAfterJournalWrite() throws {
        try attemptAndRecover(faultPoint: .afterJournalWrite)
    }

    func testPromotionRecoversFromCrashAfterRename() throws {
        try attemptAndRecover(faultPoint: .afterRename)
    }

    func testPromotionRecoversFromCrashAfterPromotionMarked() throws {
        try attemptAndRecover(faultPoint: .afterPromotionMarked)
    }

    func testPromotionRecoversFromCrashAfterJournalRemoval() throws {
        // Journal removal now belongs to the persisted-reference acknowledgement
        // phase; retain the existing regression selector for that crash window.
        let artifact = try makePendingArtifact()
        let projectID = UUID()
        let reference = try store.promoteFinalizedArtifact(artifact, projectID: projectID)
        let destination = try XCTUnwrap(store.resolve(reference, ownedBy: projectID))
        let bytes = try Data(contentsOf: destination)

        XCTAssertThrowsError(try store.acknowledgePersistedReference(reference, projectID: UUID()))
        XCTAssertEqual(try store.journal.entry(for: artifact.id.rawValue)?.state, .promoted)

        store.testPromotionFaultPoint = .beforeJournalRemoval
        XCTAssertThrowsError(try store.acknowledgePersistedReference(reference, projectID: projectID))
        XCTAssertEqual(try store.journal.entry(for: artifact.id.rawValue)?.state, .promoted)

        store.testPromotionFaultPoint = .afterJournalRemoval
        XCTAssertThrowsError(try store.acknowledgePersistedReference(reference, projectID: projectID))
        XCTAssertNil(try store.journal.entry(for: artifact.id.rawValue))
        let reopened = try RecordingArtifactStore(applicationSupportDirectoryURL: applicationSupportURL)
        XCTAssertNoThrow(try reopened.acknowledgePersistedReference(reference, projectID: projectID))
        XCTAssertEqual(try Data(contentsOf: destination), bytes)
    }

    // MARK: - Helpers

    private func makePendingArtifact() throws -> RecordingArtifact {
        let pendingURL = try store.makePendingURL()
        let data = Data("promotion-fixture-\(UUID().uuidString)".utf8)
        XCTAssertTrue(FileManager.default.createFile(atPath: pendingURL.path, contents: data))
        return RecordingArtifact(
            id: RecordingID(rawValue: UUID()),
            localURL: pendingURL,
            duration: 1.5,
            hasAudio: false
        )
    }

    private final class ReferenceBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [SceneRecordingReference] = []
        private var failureDescriptions: [String] = []

        func append(_ reference: SceneRecordingReference) {
            lock.lock()
            storage.append(reference)
            lock.unlock()
        }

        func appendFailure(_ description: String) {
            lock.lock()
            failureDescriptions.append(description)
            lock.unlock()
        }

        var references: [SceneRecordingReference] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        var failures: [String] {
            lock.lock()
            defer { lock.unlock() }
            return failureDescriptions
        }
    }
}
