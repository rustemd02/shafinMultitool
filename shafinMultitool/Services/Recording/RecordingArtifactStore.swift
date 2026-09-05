import Darwin
import Foundation

enum RecordingArtifactStoreError: Error, Equatable, Sendable {
    case pendingSourceMissing
    case pendingSourceOutsideRoot
    case pendingSourceSymlink
    case pendingSourceNotRegular
    case destinationConflict
    case projectArtifactUnexpectedEntry
    case fileSystemFailure
    case deletionTransactionState
    case deletionIdentityMismatch
    case deletionRollbackFailure
}

/// M7-017: conservative free-space requirement for one planned take. The
/// estimate deliberately over-reserves: it assumes maximum duration at a
/// constant worst-case bitrate and doubles the result so pending and final
/// storage can coexist without ever pressuring existing project media.
struct RecordingDiskBudgetEstimate: Sendable, Equatable {
    /// Bytes that must be free before recording may start.
    let requiredFreeBytes: Int64
    /// Bytes currently free on the recordings volume.
    let availableBytes: Int64

    var isSatisfied: Bool { availableBytes >= requiredFreeBytes }
}

/// M7-017: documented bitrate model constants. Bits per pixel per frame are
/// intentionally conservative upper bounds (a full-quality encode at the
/// selected format, not an observed average).
enum RecordingDiskBudgetModel {
    /// Worst-case encoded bits per pixel per frame by codec.
    static func bitsPerPixel(codec: RecordingQuickTimeCodec) -> Double {
        switch codec {
        case .h264: return 0.12
        case .hevc: return 0.07
        }
    }

    /// Audio keeps the fixed v1 AAC 48 kHz mono format at 128 kbps; the
    /// estimate adds container/fragment overhead on top.
    static let audioBitsPerSecond: Double = 128_000
    /// Pending file plus finalized file must be able to coexist.
    static let duplicationMargin: Double = 2.0
    /// Fixed safety floor (metadata, container, fragmentation headroom).
    static let safetyFloorBytes: Int64 = 50_000_000
    /// Default maximum planned take duration when the caller has no shorter
    /// budget.
    static let defaultDurationLimitSeconds: TimeInterval = 600

    static func requiredFreeBytes(width: Int,
                                  height: Int,
                                  fps: Int,
                                  codec: RecordingQuickTimeCodec,
                                  audioMode: RecordingAudioMode,
                                  durationLimitSeconds: TimeInterval) -> Int64 {
        let clampedWidth = max(0, width)
        let clampedHeight = max(0, height)
        let clampedFPS = max(0, fps)
        let clampedDuration = max(0, durationLimitSeconds)

        let videoBitsPerSecond = Double(clampedWidth)
            * Double(clampedHeight)
            * Double(clampedFPS)
            * bitsPerPixel(codec: codec)
        var bitsPerSecond = videoBitsPerSecond
        if audioMode == .required {
            bitsPerSecond += audioBitsPerSecond
        }
        let estimatedBytes = bitsPerSecond / 8 * clampedDuration
        let reserved = estimatedBytes * duplicationMargin + Double(safetyFloorBytes)
        return Int64(reserved.rounded(.up))
    }
}

/// Owns the only filesystem boundary for recording artifacts. Pending files
/// are never exposed as project media; promotion moves them into a deterministic
/// project directory and references store only a relative path.
final class RecordingArtifactStore: @unchecked Sendable {
    let applicationSupportDirectoryURL: URL
    let recordingsDirectoryURL: URL
    let pendingDirectoryURL: URL
    let projectsDirectoryURL: URL
    /// M7-019: durable pending-artifact journal owner, scoped to this store's
    /// recordings root.
    let journal: PendingRecordingJournal

    var recordingRootURL: URL { recordingsDirectoryURL }

    private let fileManager: FileManager

#if DEBUG
    /// Fault injection is compiled only for the focused persistence tests. It
    /// is deliberately owned by the artifact boundary so tests can exercise a
    /// partial unlink without replacing the real filesystem owner.
    var testArtifactCommitFailureAfterUnlinks: Int?

    /// M7-020/M7-022: deterministic promotion crash points. Each point throws
    /// exactly once (self-clearing) so tests can drive every crash state and
    /// then verify recovery converges.
    enum PromotionFaultPoint: Equatable {
        case beforeJournalWrite
        case afterJournalWrite
        case afterRename
        case afterJournalRemoval
    }

    var testPromotionFaultPoint: PromotionFaultPoint?
#endif

    fileprivate struct StagedArtifactEntry {
        let name: String
        let device: dev_t
        let inode: ino_t
    }

    /// A reversible deletion staging handle. The source project remains in
    /// place while staging creates same-volume hard links in a private sibling
    /// directory. This keeps rollback O(1) and preserves the original bytes and
    /// inode identity until the final commit.
    final class StagedProjectArtifacts: @unchecked Sendable {
        private enum State {
            case staged
            case committed
            case rolledBack
        }

        private let store: RecordingArtifactStore
        fileprivate let projectID: UUID
        fileprivate let stagingName: String?
        fileprivate let entries: [StagedArtifactEntry]
        private var state: State = .staged

        fileprivate init(
            store: RecordingArtifactStore,
            projectID: UUID,
            stagingName: String?,
            entries: [StagedArtifactEntry]
        ) {
            self.store = store
            self.projectID = projectID
            self.stagingName = stagingName
            self.entries = entries
        }

        func commit() throws {
            try store.commitProjectArtifacts(self)
        }

        func rollback() throws {
            if case .rolledBack = state { return }
            try store.rollbackProjectArtifacts(self)
        }

        fileprivate func requireStaged() throws {
            guard case .staged = state else {
                throw RecordingArtifactStoreError.deletionTransactionState
            }
        }

        fileprivate func markCommitted() {
            state = .committed
        }

        fileprivate func markRolledBack() {
            state = .rolledBack
        }
    }

    init(
        fileManager: FileManager = .default,
        applicationSupportDirectoryURL: URL? = nil
    ) throws {
        self.fileManager = fileManager

        let applicationSupportURL: URL
        if let applicationSupportDirectoryURL {
            applicationSupportURL = applicationSupportDirectoryURL
        } else if let defaultURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            applicationSupportURL = defaultURL
        } else {
            throw CocoaError(.fileNoSuchFile)
        }

        self.applicationSupportDirectoryURL = applicationSupportURL.standardizedFileURL
        recordingsDirectoryURL = self.applicationSupportDirectoryURL
            .appendingPathComponent("Recordings", isDirectory: true)
        pendingDirectoryURL = recordingsDirectoryURL
            .appendingPathComponent("Pending", isDirectory: true)
        projectsDirectoryURL = recordingsDirectoryURL
            .appendingPathComponent("Projects", isDirectory: true)
        journal = PendingRecordingJournal(
            fileManager: fileManager,
            recordingsDirectoryURL: recordingsDirectoryURL
        )

        try fileManager.createDirectory(
            at: pendingDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    func makePendingURL() throws -> URL {
        while true {
            let candidate = pendingDirectoryURL
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
    }

    /// M7-017: free-space check against the conservative budget model. The
    /// query uses the important-usage capacity when the platform exposes it
    /// (it accounts for purgeable behavior honestly) and falls back to the
    /// raw free size. A capacity query failure fails closed.
    func diskBudgetEstimate(width: Int,
                            height: Int,
                            fps: Int,
                            codec: RecordingQuickTimeCodec,
                            audioMode: RecordingAudioMode,
                            durationLimitSeconds: TimeInterval
                                = RecordingDiskBudgetModel.defaultDurationLimitSeconds) throws
        -> RecordingDiskBudgetEstimate {
        let required = RecordingDiskBudgetModel.requiredFreeBytes(
            width: width,
            height: height,
            fps: fps,
            codec: codec,
            audioMode: audioMode,
            durationLimitSeconds: durationLimitSeconds
        )

        let volumeURL = recordingsDirectoryURL
        let available: Int64?
        if let values = try? urlResourceValues(forVolumeAt: volumeURL) {
            available = values.volumeAvailableCapacityForImportantUsage
                ?? values.volumeAvailableCapacity.map(Int64.init)
        } else {
            available = nil
        }
        guard let availableBytes = available, availableBytes >= 0 else {
            throw RecordingArtifactStoreError.fileSystemFailure
        }
        return RecordingDiskBudgetEstimate(requiredFreeBytes: required, availableBytes: availableBytes)
    }

    private func urlResourceValues(forVolumeAt url: URL) throws -> URLResourceValues {
        try url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ])
    }

    /// Moves a finalized Pending artifact into project-owned storage. A
    /// pre-existing valid destination is treated as the same idempotent take;
    /// no existing destination is ever overwritten.
    ///
    /// M7-019/M7-020: the move is journaled atomically BEFORE the rename and
    /// the record is removed only after the move committed, so every crash
    /// point converges on recovery to one valid reference or one recoverable
    /// pending state — never a duplicate reference or an orphan file.
    func promoteFinalizedArtifact(
        _ artifact: RecordingArtifact,
        projectID: UUID
    ) throws -> SceneRecordingReference {
        let reference = SceneRecordingReference(
            recordingID: artifact.id.rawValue,
            relativePath: relativePath(for: artifact.id.rawValue, projectID: projectID),
            duration: artifact.duration,
            hasAudio: artifact.hasAudio
        )
        let sourceURL = artifact.localURL.standardizedFileURL
        let pendingURL = pendingDirectoryURL.standardizedFileURL
        guard sourceURL.deletingLastPathComponent() == pendingURL,
              let sourceName = sourceURL.pathComponents.last,
              !sourceName.isEmpty,
              sourceName != ".",
              sourceName != "..",
              !sourceName.contains("\0"),
              !sourceName.contains("/") else {
            throw RecordingArtifactStoreError.pendingSourceOutsideRoot
        }

        // M7-019: journal the promotion intent before touching anything.
        // A resumable `.promoting` entry from a crashed attempt keeps its
        // retry history; corruption fails closed before any file moves.
        try beginPromotionJournalEntry(
            recordingID: artifact.id.rawValue,
            projectID: projectID,
            sourceName: sourceName,
            destinationRelativePath: reference.relativePath
        )

        let destinationName = "\(artifact.id.rawValue.uuidString).mov"
        let applicationSupportFD = try openDirectory(at: applicationSupportDirectoryURL.path)
        defer { close(applicationSupportFD) }

        let recordingsFD = try openDirectory(at: applicationSupportFD, name: "Recordings")
        defer { close(recordingsFD) }

        let pendingFD = try openDirectory(at: recordingsFD, name: "Pending")
        defer { close(pendingFD) }

        try createDirectory(at: recordingsFD, name: "Projects")
        let projectsFD = try openDirectory(at: recordingsFD, name: "Projects")
        defer { close(projectsFD) }

        try createDirectory(at: projectsFD, name: projectID.uuidString)
        let projectFD = try openDirectory(at: projectsFD, name: projectID.uuidString)
        defer { close(projectFD) }

        let existingDestination = statEntry(at: projectFD, name: destinationName)
        let destinationError = errno
        if let destination = existingDestination {
            guard isRegular(destination) else {
                throw RecordingArtifactStoreError.destinationConflict
            }
            try finishPromotionJournalEntry(recordingID: artifact.id.rawValue)
            return reference
        } else if destinationError != ENOENT {
            throw RecordingArtifactStoreError.fileSystemFailure
        }

        let sourceEntry = statEntry(at: pendingFD, name: sourceName)
        let sourceError = errno
        guard let source = sourceEntry else {
            if sourceError == ENOENT {
                // M1-014: another concurrent transaction may have committed its
                // rename between the destination check above and this source
                // check. A regular destination in that window means this take
                // is already stored exactly once, so report the committed
                // transaction idempotently instead of a transient failure.
                if let committed = statEntry(at: projectFD, name: destinationName),
                   isRegular(committed) {
                    try finishPromotionJournalEntry(recordingID: artifact.id.rawValue)
                    return reference
                }
                throw RecordingArtifactStoreError.pendingSourceMissing
            }
            throw RecordingArtifactStoreError.fileSystemFailure
        }
        let sourceType = source.st_mode & S_IFMT
        guard sourceType != S_IFLNK else {
            throw RecordingArtifactStoreError.pendingSourceSymlink
        }
        guard sourceType == S_IFREG else {
            throw RecordingArtifactStoreError.pendingSourceNotRegular
        }

        let renameResult = renameatx_np(
            pendingFD,
            sourceName,
            projectFD,
            destinationName,
            UInt32(RENAME_EXCL)
        )
        let renameError = errno
        guard renameResult == 0 else {
            if renameError == EEXIST {
                let destinationAfterRace = statEntry(at: projectFD, name: destinationName)
                if let destinationAfterRace, isRegular(destinationAfterRace) {
                    try finishPromotionJournalEntry(recordingID: artifact.id.rawValue)
                    return reference
                }
                throw RecordingArtifactStoreError.destinationConflict
            }
            if renameError == ENOENT {
                // M1-014: a concurrent transaction consumed the source between
                // the source check and this rename. A regular destination in
                // that window is the committed take, so report it idempotently.
                if let committed = statEntry(at: projectFD, name: destinationName),
                   isRegular(committed) {
                    try finishPromotionJournalEntry(recordingID: artifact.id.rawValue)
                    return reference
                }
                throw RecordingArtifactStoreError.pendingSourceMissing
            }
            throw RecordingArtifactStoreError.fileSystemFailure
        }

        guard let destination = statEntry(at: projectFD, name: destinationName),
              isRegular(destination),
              destination.st_dev == source.st_dev,
              destination.st_ino == source.st_ino else {
            _ = renameatx_np(
                projectFD,
                destinationName,
                pendingFD,
                sourceName,
                UInt32(RENAME_EXCL)
            )
            throw RecordingArtifactStoreError.fileSystemFailure
        }

        // The move committed; the journal record is the crash-recovery
        // tombstone and must be removed only now (`.afterRename` fault point
        // lives inside the finish helper).
        try finishPromotionJournalEntry(recordingID: artifact.id.rawValue)
        return reference
    }

    /// Writes (or resumes) the atomic `.promoting` record before the move.
    private func beginPromotionJournalEntry(recordingID: UUID,
                                            projectID: UUID,
                                            sourceName: String,
                                            destinationRelativePath: String) throws {
#if DEBUG
        try consumePromotionFault(.beforeJournalWrite)
#endif
        let now = Date()
        let sourceTempPath = "Recordings/Pending/\(sourceName)"
        let entry: PendingRecordingJournalEntry
        if let existing = try journal.entry(for: recordingID) {
            guard existing.recordingID == recordingID,
                  existing.projectID == projectID,
                  existing.destinationRelativePath == destinationRelativePath else {
                // A different transaction owns this record identity; never
                // overwrite another take's journal entry.
                throw PendingRecordingJournalError.journalCorrupt(recordingID: recordingID)
            }
            // Same transaction re-entry (concurrent idempotent callers or an
            // in-process retry). The bounded retry budget is owned by cold
            // recovery (M7-021), not by the hot promotion path, so concurrent
            // promotions of one take cannot exhaust it.
            entry = existing.updating(state: .promoting, at: now)
        } else {
            let sourceURL = pendingDirectoryURL
                .appendingPathComponent(sourceName, isDirectory: false)
            let expectedSize: Int64?
            if let attributes = try? fileManager.attributesOfItem(atPath: sourceURL.path),
               let size = attributes[.size] as? NSNumber {
                expectedSize = size.int64Value
            } else {
                expectedSize = nil
            }
            entry = PendingRecordingJournalEntry(
                recordingID: recordingID,
                projectID: projectID,
                sourceTempPath: sourceTempPath,
                destinationRelativePath: destinationRelativePath,
                expectedFileSize: expectedSize,
                expectedSHA256: nil,
                state: .promoting,
                retryCount: 0,
                createdAt: now,
                updatedAt: now
            )
        }
        try journal.record(entry)
#if DEBUG
        try consumePromotionFault(.afterJournalWrite)
#endif
    }

    /// Removes the promotion record after a committed (or already committed)
    /// move. A removal failure leaves the record with a regular committed
    /// destination — recovery (M7-021) converges without duplicating.
    private func finishPromotionJournalEntry(recordingID: UUID) throws {
#if DEBUG
        try consumePromotionFault(.afterRename)
#endif
        try journal.remove(recordingID: recordingID)
#if DEBUG
        try consumePromotionFault(.afterJournalRemoval)
#endif
    }

#if DEBUG
    /// Throws once at the configured fault point, then clears so subsequent
    /// calls (the recovery pass) run the real code.
    private func consumePromotionFault(_ point: PromotionFaultPoint) throws {
        guard testPromotionFaultPoint == point else { return }
        testPromotionFaultPoint = nil
        throw PendingRecordingJournalError.fileSystemFailure
    }
#endif

    /// Resolves only references whose path remains below Recordings and whose
    /// final filesystem object is a regular, non-symlink file.
    func resolve(_ reference: SceneRecordingReference) -> URL? {
        guard let url = safeURL(for: reference.relativePath),
              !containsSymlink(in: url, relativeTo: recordingsDirectoryURL),
              isRegular(url) else {
            return nil
        }
        return url
    }

    /// Resolves a reference only when its persisted path is the canonical
    /// project/recording binding produced by promotion. The regular `resolve`
    /// method still protects the recordings root; this extra binding prevents
    /// a reference from borrowing another project's or Pending's movie.
    func resolve(_ reference: SceneRecordingReference, ownedBy projectID: UUID) -> URL? {
        guard reference.relativePath == relativePath(for: reference.recordingID, projectID: projectID) else {
            return nil
        }
        return resolve(reference)
    }

    func resolveArtifact(_ reference: SceneRecordingReference) -> RecordingArtifact? {
        guard let localURL = resolve(reference) else { return nil }
        return RecordingArtifact(
            id: RecordingID(rawValue: reference.recordingID),
            localURL: localURL,
            duration: reference.duration,
            hasAudio: reference.hasAudio
        )
    }

    /// Stages one project's finalized artifacts for a reversible deletion.
    /// Pending artifacts and sibling projects are intentionally untouched.
    /// The source directory is not changed until `commit()`.
    func stageProjectArtifacts(projectID: UUID) throws -> StagedProjectArtifacts {
        guard let applicationSupportFD = try openOptionalDirectory(at: applicationSupportDirectoryURL.path) else {
            return StagedProjectArtifacts(store: self, projectID: projectID, stagingName: nil, entries: [])
        }
        defer { close(applicationSupportFD) }

        guard let recordingsFD = try openOptionalDirectory(at: applicationSupportFD, name: "Recordings") else {
            return StagedProjectArtifacts(store: self, projectID: projectID, stagingName: nil, entries: [])
        }
        defer { close(recordingsFD) }

        guard let projectsFD = try openOptionalDirectory(at: recordingsFD, name: "Projects") else {
            return StagedProjectArtifacts(store: self, projectID: projectID, stagingName: nil, entries: [])
        }
        defer { close(projectsFD) }

        guard let projectFD = try openOptionalDirectory(at: projectsFD, name: projectID.uuidString) else {
            return StagedProjectArtifacts(store: self, projectID: projectID, stagingName: nil, entries: [])
        }
        defer { close(projectFD) }

        let entries = try projectEntries(in: projectFD)
        guard entries.allSatisfy({ isRegular($0.information) && isProjectArtifactName($0.name) }) else {
            throw RecordingArtifactStoreError.projectArtifactUnexpectedEntry
        }

        let stagedEntries = entries.map {
            StagedArtifactEntry(name: $0.name, device: $0.information.st_dev, inode: $0.information.st_ino)
        }
        let stagingName = ".set-delete-\(projectID.uuidString)-\(UUID().uuidString)"
        try createDirectory(at: projectsFD, name: stagingName)
        guard let stagingFD = try openOptionalDirectory(at: projectsFD, name: stagingName) else {
            throw RecordingArtifactStoreError.fileSystemFailure
        }
        defer { close(stagingFD) }

        var linkedEntries: [StagedArtifactEntry] = []
        do {
            for entry in entries {
                guard let current = statEntry(at: projectFD, name: entry.name),
                      isRegular(current),
                      current.st_dev == entry.information.st_dev,
                      current.st_ino == entry.information.st_ino else {
                    throw RecordingArtifactStoreError.deletionIdentityMismatch
                }

                let result = entry.name.withCString { namePointer in
                    linkat(projectFD, namePointer, stagingFD, namePointer, 0)
                }
                guard result == 0 else {
                    throw RecordingArtifactStoreError.fileSystemFailure
                }
                linkedEntries.append(
                    StagedArtifactEntry(
                        name: entry.name,
                        device: entry.information.st_dev,
                        inode: entry.information.st_ino
                    )
                )
            }
        } catch {
            do {
                try removeStagingDirectory(
                    projectsFD: projectsFD,
                    stagingFD: stagingFD,
                    stagingName: stagingName,
                    expectedEntries: linkedEntries
                )
            } catch {
                throw RecordingArtifactStoreError.deletionRollbackFailure
            }
            throw error
        }

        return StagedProjectArtifacts(
            store: self,
            projectID: projectID,
            stagingName: stagingName,
            entries: stagedEntries
        )
    }

    /// Removes one project's finalized artifacts through the reversible
    /// staging seam. A partial unlink restores every artifact before the
    /// failure escapes.
    func removeProjectArtifacts(projectID: UUID) throws {
        let staged = try stageProjectArtifacts(projectID: projectID)
        try staged.commit()
    }

    private func commitProjectArtifacts(_ transaction: StagedProjectArtifacts) throws {
        try transaction.requireStaged()
        guard let stagingName = transaction.stagingName else {
            transaction.markCommitted()
            return
        }

        do {
            let applicationSupportFD = try openDirectory(at: applicationSupportDirectoryURL.path)
            defer { close(applicationSupportFD) }
            let recordingsFD = try openDirectory(at: applicationSupportFD, name: "Recordings")
            defer { close(recordingsFD) }
            let projectsFD = try openDirectory(at: recordingsFD, name: "Projects")
            defer { close(projectsFD) }
            guard let projectFD = try openOptionalDirectory(at: projectsFD, name: transaction.projectID.uuidString),
                  let stagingFD = try openOptionalDirectory(at: projectsFD, name: stagingName) else {
                throw RecordingArtifactStoreError.deletionIdentityMismatch
            }
            defer {
                close(projectFD)
                close(stagingFD)
            }

            try validateStagedProjectArtifacts(transaction, projectFD: projectFD, stagingFD: stagingFD)
            for entry in transaction.entries {
#if DEBUG
                if let remaining = testArtifactCommitFailureAfterUnlinks {
                    if remaining == 0 {
                        testArtifactCommitFailureAfterUnlinks = nil
                        throw RecordingArtifactStoreError.fileSystemFailure
                    }
                    testArtifactCommitFailureAfterUnlinks = remaining - 1
                }
#endif
                let result = entry.name.withCString { namePointer in
                    unlinkat(projectFD, namePointer, 0)
                }
                guard result == 0 else {
                    if errno == ENOENT {
                        throw RecordingArtifactStoreError.deletionIdentityMismatch
                    }
                    throw RecordingArtifactStoreError.fileSystemFailure
                }
            }

            let removeProjectResult = transaction.projectID.uuidString.withCString { namePointer in
                unlinkat(projectsFD, namePointer, AT_REMOVEDIR)
            }
            guard removeProjectResult == 0 else {
                throw RecordingArtifactStoreError.fileSystemFailure
            }

            // The artifact paths are now irreversibly gone. Cleanup is a
            // post-commit tombstone removal; if it is interrupted, retaining
            // the hidden staging directory is safer than reporting a rollback
            // failure after the source project has already been removed.
            do {
                try removeStagingDirectory(
                    projectsFD: projectsFD,
                    stagingFD: stagingFD,
                    stagingName: stagingName,
                    expectedEntries: transaction.entries
                )
            } catch {
                print("Recording artifact deletion tombstone cleanup deferred: \(error)")
            }
            transaction.markCommitted()
        } catch {
            do {
                try rollbackProjectArtifacts(transaction)
                transaction.markRolledBack()
            } catch {
                throw RecordingArtifactStoreError.deletionRollbackFailure
            }
            throw error
        }
    }

    private func rollbackProjectArtifacts(_ transaction: StagedProjectArtifacts) throws {
        try transaction.requireStaged()
        guard let stagingName = transaction.stagingName else {
            transaction.markRolledBack()
            return
        }

        let applicationSupportFD = try openDirectory(at: applicationSupportDirectoryURL.path)
        defer { close(applicationSupportFD) }
        let recordingsFD = try openDirectory(at: applicationSupportFD, name: "Recordings")
        defer { close(recordingsFD) }
        let projectsFD = try openDirectory(at: recordingsFD, name: "Projects")
        defer { close(projectsFD) }
        guard let stagingFD = try openOptionalDirectory(at: projectsFD, name: stagingName) else {
            throw RecordingArtifactStoreError.deletionRollbackFailure
        }
        defer { close(stagingFD) }

        let projectFD: Int32
        if let existingProjectFD = try openOptionalDirectory(at: projectsFD, name: transaction.projectID.uuidString) {
            projectFD = existingProjectFD
        } else {
            try createDirectory(at: projectsFD, name: transaction.projectID.uuidString)
            projectFD = try openDirectory(at: projectsFD, name: transaction.projectID.uuidString)
        }
        defer { close(projectFD) }

        try validateStagingDirectory(transaction, stagingFD: stagingFD)
        let currentEntries = try projectEntries(in: projectFD)
        let expectedNames = Set(transaction.entries.map(\.name))
        guard currentEntries.allSatisfy({ expectedNames.contains($0.name) }) else {
            throw RecordingArtifactStoreError.deletionIdentityMismatch
        }
        for entry in transaction.entries {
            if let current = statEntry(at: projectFD, name: entry.name) {
                guard isRegular(current),
                      current.st_dev == entry.device,
                      current.st_ino == entry.inode else {
                    throw RecordingArtifactStoreError.deletionIdentityMismatch
                }
                continue
            }

            let result = entry.name.withCString { namePointer in
                linkat(stagingFD, namePointer, projectFD, namePointer, 0)
            }
            guard result == 0 else {
                throw RecordingArtifactStoreError.deletionRollbackFailure
            }
        }

        try removeStagingDirectory(
            projectsFD: projectsFD,
            stagingFD: stagingFD,
            stagingName: stagingName,
            expectedEntries: transaction.entries
        )
    }

    private func validateStagedProjectArtifacts(
        _ transaction: StagedProjectArtifacts,
        projectFD: Int32,
        stagingFD: Int32
    ) throws {
        let currentEntries = try projectEntries(in: projectFD)
        let expectedNames = Set(transaction.entries.map(\.name))
        guard currentEntries.count == transaction.entries.count,
              currentEntries.allSatisfy({ expectedNames.contains($0.name) }) else {
            throw RecordingArtifactStoreError.deletionIdentityMismatch
        }
        try validateStagingDirectory(transaction, stagingFD: stagingFD)
        for entry in transaction.entries {
            guard let current = statEntry(at: projectFD, name: entry.name),
                  isRegular(current),
                  current.st_dev == entry.device,
                  current.st_ino == entry.inode else {
                throw RecordingArtifactStoreError.deletionIdentityMismatch
            }
        }
    }

    private func validateStagingDirectory(
        _ transaction: StagedProjectArtifacts,
        stagingFD: Int32
    ) throws {
        let stagedEntries = try projectEntries(in: stagingFD)
        let expectedNames = Set(transaction.entries.map(\.name))
        guard stagedEntries.count == transaction.entries.count,
              stagedEntries.allSatisfy({ expectedNames.contains($0.name) }) else {
            throw RecordingArtifactStoreError.deletionIdentityMismatch
        }
        for entry in transaction.entries {
            guard let staged = statEntry(at: stagingFD, name: entry.name),
                  isRegular(staged),
                  staged.st_dev == entry.device,
                  staged.st_ino == entry.inode else {
                throw RecordingArtifactStoreError.deletionIdentityMismatch
            }
        }
    }

    private func removeStagingDirectory(
        projectsFD: Int32,
        stagingFD: Int32,
        stagingName: String,
        expectedEntries: [StagedArtifactEntry]
    ) throws {
        let currentEntries = try projectEntries(in: stagingFD)
        let expectedNames = Set(expectedEntries.map(\.name))
        guard currentEntries.allSatisfy({ expectedNames.contains($0.name) }) else {
            throw RecordingArtifactStoreError.deletionIdentityMismatch
        }
        for entry in expectedEntries {
            guard let current = statEntry(at: stagingFD, name: entry.name),
                  isRegular(current),
                  current.st_dev == entry.device,
                  current.st_ino == entry.inode else {
                throw RecordingArtifactStoreError.deletionIdentityMismatch
            }
            let result = entry.name.withCString { namePointer in
                unlinkat(stagingFD, namePointer, 0)
            }
            guard result == 0 || errno == ENOENT else {
                throw RecordingArtifactStoreError.fileSystemFailure
            }
        }
        let result = stagingName.withCString { namePointer in
            unlinkat(projectsFD, namePointer, AT_REMOVEDIR)
        }
        guard result == 0 || errno == ENOENT else {
            throw RecordingArtifactStoreError.fileSystemFailure
        }
    }

    private func relativePath(for recordingID: UUID, projectID: UUID) -> String {
        "Recordings/Projects/\(projectID.uuidString)/\(recordingID.uuidString).mov"
    }

    private func openDirectory(at path: String) throws -> Int32 {
        let descriptor = path.withCString { pathPointer in
            open(pathPointer, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            if errno == ELOOP || errno == ENOTDIR {
                throw RecordingArtifactStoreError.destinationConflict
            }
            throw RecordingArtifactStoreError.fileSystemFailure
        }
        return descriptor
    }

    private func openOptionalDirectory(at path: String) throws -> Int32? {
        let descriptor = path.withCString { pathPointer in
            open(pathPointer, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            if errno == ELOOP || errno == ENOTDIR {
                throw RecordingArtifactStoreError.destinationConflict
            }
            throw RecordingArtifactStoreError.fileSystemFailure
        }
        return descriptor
    }

    private func openOptionalDirectory(at parent: Int32, name: String) throws -> Int32? {
        let descriptor = name.withCString { namePointer in
            openat(parent, namePointer, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            if errno == ELOOP || errno == ENOTDIR {
                throw RecordingArtifactStoreError.destinationConflict
            }
            throw RecordingArtifactStoreError.fileSystemFailure
        }
        return descriptor
    }

    private func openDirectory(at parent: Int32, name: String) throws -> Int32 {
        let descriptor = name.withCString { namePointer in
            openat(parent, namePointer, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            if errno == ELOOP || errno == ENOTDIR {
                throw RecordingArtifactStoreError.destinationConflict
            }
            throw RecordingArtifactStoreError.fileSystemFailure
        }
        return descriptor
    }

    private func createDirectory(at parent: Int32, name: String) throws {
        let result = name.withCString { namePointer in
            mkdirat(parent, namePointer, mode_t(0o700))
        }
        guard result == 0 || errno == EEXIST else {
            throw RecordingArtifactStoreError.fileSystemFailure
        }
    }

    private func statEntry(at directory: Int32, name: String) -> stat? {
        var information = stat()
        let result = name.withCString { namePointer in
            fstatat(directory, namePointer, &information, AT_SYMLINK_NOFOLLOW)
        }
        guard result == 0 else { return nil }
        return information
    }

    private struct ProjectEntry {
        let name: String
        let information: stat
    }

    private func projectEntries(in directory: Int32) throws -> [ProjectEntry] {
        let streamFD = dup(directory)
        guard streamFD >= 0 else {
            throw RecordingArtifactStoreError.fileSystemFailure
        }
        guard let stream = fdopendir(streamFD) else {
            close(streamFD)
            throw RecordingArtifactStoreError.fileSystemFailure
        }
        defer { closedir(stream) }

        errno = 0
        var entries: [ProjectEntry] = []
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                    String(cString: $0)
                }
            }
            guard name != ".", name != ".." else { continue }
            guard let information = statEntry(at: directory, name: name) else {
                throw RecordingArtifactStoreError.fileSystemFailure
            }
            entries.append(ProjectEntry(name: name, information: information))
        }
        guard errno == 0 else {
            throw RecordingArtifactStoreError.fileSystemFailure
        }
        return entries
    }

    private func isProjectArtifactName(_ name: String) -> Bool {
        guard name.hasSuffix(".mov") else { return false }
        let uuidString = String(name.dropLast(4))
        guard let uuid = UUID(uuidString: uuidString) else { return false }
        return uuid.uuidString == uuidString
    }

    private func safeURL(for relativePath: String) -> URL? {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.contains("\0") else {
            return nil
        }

        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              !components.contains(where: { $0 == "." || $0 == ".." || $0.isEmpty }) else {
            return nil
        }

        let url = applicationSupportDirectoryURL
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        return isInside(url, root: recordingsDirectoryURL) ? url : nil
    }

    private func isInside(_ candidate: URL, root: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        guard candidateComponents.count > rootComponents.count else { return false }
        return candidateComponents.prefix(rootComponents.count).elementsEqual(rootComponents)
    }

    private func containsSymlink(in url: URL, relativeTo root: URL) -> Bool {
        let rootURL = root.standardizedFileURL
        let candidateURL = url.standardizedFileURL
        guard isInside(candidateURL, root: rootURL) else { return true }
        guard fileType(at: rootURL) != S_IFLNK else { return true }

        var current = rootURL
        let relativeComponents = candidateURL.pathComponents.dropFirst(rootURL.pathComponents.count)
        for component in relativeComponents {
            current.appendPathComponent(component)
            if fileType(at: current) == S_IFLNK {
                return true
            }
        }
        return false
    }

    private func isRegular(_ url: URL) -> Bool {
        fileType(at: url) == S_IFREG
    }

    private func isRegular(_ information: stat) -> Bool {
        information.st_mode & S_IFMT == S_IFREG
    }

    private func fileType(at url: URL) -> UInt16? {
        var information = stat()
        guard lstat(url.path, &information) == 0 else { return nil }
        return information.st_mode & S_IFMT
    }
}
