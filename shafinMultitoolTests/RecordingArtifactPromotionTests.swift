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
