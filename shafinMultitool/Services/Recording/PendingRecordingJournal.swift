import Foundation

/// M7-019: durable pending-artifact journal entry. Exactly one record exists
/// per pending file; every promotion writes it atomically BEFORE moving the
/// file and removes it only after the move committed, so a crash at any point
/// converges (M7-021) to either one valid project reference or a recoverable
/// pending state. Paths are Application-Support-relative; the journal never
/// stores absolute paths or user content.
struct PendingRecordingJournalEntry: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        /// The finalized artifact sits in Pending and is about to be promoted.
        case pending
        /// The atomic move has been started; recovery must resume promotion.
        case promoting
        /// The move committed and the journal record is about to be removed.
        /// Treated the same as a missing record during recovery.
        case promoted
        /// Retry budget exhausted; the pending file is kept for user-visible
        /// recovery and must not be silently deleted.
        case failed
    }

    let recordingID: UUID
    let projectID: UUID
    /// Pending source path relative to Application Support.
    let sourceTempPath: String
    /// Project destination path relative to Application Support.
    let destinationRelativePath: String
    /// Size observed when the entry was written. `nil` when unknown.
    let expectedFileSize: Int64?
    /// Content digest reserved by the v1 schema. Computing it is expensive
    /// for large media, so promotion currently writes `nil` (size-only
    /// integrity) and recovery treats `nil` as "verify regular file + size".
    let expectedSHA256: String?
    let state: State
    let retryCount: Int
    let createdAt: Date
    let updatedAt: Date

    /// Bounded retry budget before recovery marks the entry failed.
    static let maxRetryCount = 3

    func updating(state: State, retryCount: Int? = nil, at date: Date) -> Self {
        PendingRecordingJournalEntry(
            recordingID: recordingID,
            projectID: projectID,
            sourceTempPath: sourceTempPath,
            destinationRelativePath: destinationRelativePath,
            expectedFileSize: expectedFileSize,
            expectedSHA256: expectedSHA256,
            state: state,
            retryCount: retryCount ?? self.retryCount,
            createdAt: createdAt,
            updatedAt: date
        )
    }
}

enum PendingRecordingJournalError: Error, Equatable, Sendable {
    /// The record exists but cannot be decoded — detectable corruption.
    case journalCorrupt(recordingID: UUID)
    case fileSystemFailure
}

/// M7-019: the durable journal owner. Records live in
/// `<Application Support>/Recordings/Journal/<recordingID>.json` and are
/// written atomically (temporary file + rename), so a killed process can
/// never leave a half-written record. Reads fail closed: an undecodable
/// record is a typed corruption, never silently ignored.
final class PendingRecordingJournal: @unchecked Sendable {
    let journalDirectoryURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default,
         recordingsDirectoryURL: URL) {
        self.fileManager = fileManager
        self.journalDirectoryURL = recordingsDirectoryURL
            .appendingPathComponent("Journal", isDirectory: true)
        try? fileManager.createDirectory(
            at: journalDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    /// Atomically creates or replaces the record for the entry's recording.
    func record(_ entry: PendingRecordingJournalEntry) throws {
        let url = try entryURL(for: entry.recordingID)
        let data: Data
        do {
            data = try JSONEncoder().encode(entry)
        } catch {
            throw PendingRecordingJournalError.fileSystemFailure
        }
        // .atomic writes a temporary file and renames it over the target, so
        // the journal never exposes a partial record. If an attacker planted
        // a symlink at the record path the rename replaces the link itself
        // rather than following it.
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw PendingRecordingJournalError.fileSystemFailure
        }
    }

    func entry(for recordingID: UUID) throws -> PendingRecordingJournalEntry? {
        let url = try entryURL(for: recordingID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PendingRecordingJournalError.fileSystemFailure
        }
        do {
            return try JSONDecoder().decode(PendingRecordingJournalEntry.self, from: data)
        } catch {
            throw PendingRecordingJournalError.journalCorrupt(recordingID: recordingID)
        }
    }

    func remove(recordingID: UUID) throws {
        let url = try entryURL(for: recordingID)
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            // A concurrent committed transaction may have removed the record
            // first; that is the same terminal state, not a failure.
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain,
               nsError.code == NSFileNoSuchFileError {
                return
            }
            throw PendingRecordingJournalError.fileSystemFailure
        }
    }

    /// All readable records. A corrupt record is surfaced with its recording
    /// identity so recovery can report it instead of ignoring it.
    func allEntries() throws -> [Result<PendingRecordingJournalEntry, PendingRecordingJournalError>] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: journalDirectoryURL,
            includingPropertiesForKeys: nil
        )) ?? []
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
            guard url.pathExtension == "json",
                  let recordingID = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else {
                return nil
            }
            do {
                let data = try Data(contentsOf: url)
                let entry = try JSONDecoder().decode(
                    PendingRecordingJournalEntry.self,
                    from: data
                )
                return .success(entry)
            } catch {
                return .failure(.journalCorrupt(recordingID: recordingID))
            }
        }
    }

    private func entryURL(for recordingID: UUID) throws -> URL {
        journalDirectoryURL
            .appendingPathComponent(recordingID.uuidString)
            .appendingPathExtension("json")
    }
}
