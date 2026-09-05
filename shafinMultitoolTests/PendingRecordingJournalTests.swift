import XCTest
@testable import shafinMultitool

/// M7-019: durable pending-artifact journal contract — atomic replace,
/// missing/known/corrupt classification, idempotent removal.
final class PendingRecordingJournalTests: XCTestCase {
    private var recordingsDirectoryURL: URL!
    private var journal: PendingRecordingJournal!

    override func setUpWithError() throws {
        try super.setUpWithError()
        recordingsDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("journal-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(
            at: recordingsDirectoryURL,
            withIntermediateDirectories: true
        )
        journal = PendingRecordingJournal(recordingsDirectoryURL: recordingsDirectoryURL)
    }

    override func tearDownWithError() throws {
        if let recordingsDirectoryURL {
            try? FileManager.default.removeItem(at: recordingsDirectoryURL.deletingLastPathComponent())
        }
        try super.tearDownWithError()
    }

    private func makeEntry(recordingID: UUID = UUID(),
                           state: PendingRecordingJournalEntry.State = .promoting,
                           retryCount: Int = 0) -> PendingRecordingJournalEntry {
        PendingRecordingJournalEntry(
            recordingID: recordingID,
            projectID: UUID(),
            sourceTempPath: "Recordings/Pending/\(recordingID.uuidString).mov",
            destinationRelativePath: "Recordings/Projects/\(UUID().uuidString)/\(recordingID.uuidString).mov",
            expectedFileSize: 4096,
            expectedSHA256: nil,
            state: state,
            retryCount: retryCount,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
    }

    func testRecordAndReadBackIsLossless() throws {
        let entry = makeEntry()

        try journal.record(entry)
        let stored = try journal.entry(for: entry.recordingID)

        XCTAssertEqual(stored, entry)
    }

    func testAtomicReplaceKeepsExactlyOneRecordPerRecording() throws {
        let entry = makeEntry()
        try journal.record(entry)
        let updated = entry.updating(state: .pending, retryCount: 2, at: Date(timeIntervalSince1970: 300))
        try journal.record(updated)

        let files = try FileManager.default.contentsOfDirectory(
            at: journal.journalDirectoryURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(try journal.entry(for: entry.recordingID), updated)
    }

    func testMissingRecordReadsAsNilNotAnError() throws {
        let stored = try journal.entry(for: UUID())
        XCTAssertNil(stored)
    }

    func testCorruptRecordIsATypedDetectableFailure() throws {
        let entry = makeEntry()
        try journal.record(entry)
        let url = journal.journalDirectoryURL
            .appendingPathComponent(entry.recordingID.uuidString)
            .appendingPathExtension("json")
        try Data("not json".utf8).write(to: url)

        XCTAssertThrowsError(try journal.entry(for: entry.recordingID)) { error in
            XCTAssertEqual(
                error as? PendingRecordingJournalError,
                .journalCorrupt(recordingID: entry.recordingID)
            )
        }
        let all = try journal.allEntries()
        XCTAssertEqual(all.count, 1)
        guard case let .failure(failure) = all[0] else {
            XCTFail("A corrupt record must surface as a typed failure")
            return
        }
        XCTAssertEqual(failure, .journalCorrupt(recordingID: entry.recordingID))
    }

    func testRemoveIsIdempotentAndAllEntriesClassifiesStates() throws {
        let pending = makeEntry(state: .pending)
        let promoting = makeEntry(state: .promoting)
        try journal.record(pending)
        try journal.record(promoting)

        try journal.remove(recordingID: pending.recordingID)
        try journal.remove(recordingID: pending.recordingID)
        XCTAssertNil(try journal.entry(for: pending.recordingID))

        let remaining = try journal.allEntries()
        XCTAssertEqual(remaining.count, 1)
        guard case let .success(entry) = remaining[0] else {
            XCTFail("The surviving record must decode")
            return
        }
        XCTAssertEqual(entry.recordingID, promoting.recordingID)
        XCTAssertEqual(entry.state, .promoting)
    }
}
