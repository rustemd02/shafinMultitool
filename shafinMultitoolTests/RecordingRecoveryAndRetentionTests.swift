import XCTest
@testable import shafinMultitool

/// M7-021/022/023/024/029: cold-launch recovery classification, kill-point
/// convergence, clock-controlled retention, attack-safe orphan cleanup, and
/// the transient-storage file policy — all against the real artifact store
/// owner on a temp filesystem.
final class RecordingRecoveryAndRetentionTests: XCTestCase {

    private var applicationSupportURL: URL!
    private var store: RecordingArtifactStore!
    private var projectID: UUID!

    override func setUpWithError() throws {
        try super.setUpWithError()
        applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-recovery-\(UUID().uuidString)", isDirectory: true)
        store = try RecordingArtifactStore(applicationSupportDirectoryURL: applicationSupportURL)
        projectID = UUID()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: applicationSupportURL)
        store = nil
        applicationSupportURL = nil
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    @discardableResult
    private func makePendingFile(recordingID: UUID = UUID(),
                                 bytes: Int = 128) -> URL {
        let url = store.pendingDirectoryURL
            .appendingPathComponent(recordingID.uuidString)
            .appendingPathExtension("mov")
        FileManager.default.createFile(
            atPath: url.path,
            contents: Data(repeating: 0xAB, count: bytes)
        )
        return url
    }

    private func makeProjectFile(recordingID: UUID) throws -> URL {
        let projectDirectory = store.projectsDirectoryURL
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        let url = projectDirectory
            .appendingPathComponent(recordingID.uuidString)
            .appendingPathExtension("mov")
        FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 0xCD, count: 64))
        return url
    }

    private func journalEntry(recordingID: UUID,
                              projectID: UUID,
                              state: PendingRecordingJournalEntry.State,
                              retryCount: Int = 0) throws {
        let entry = PendingRecordingJournalEntry(
            recordingID: recordingID,
            projectID: projectID,
            sourceTempPath: "Recordings/Pending/\(recordingID.uuidString).mov",
            destinationRelativePath: "Recordings/Projects/\(projectID.uuidString)/\(recordingID.uuidString).mov",
            expectedFileSize: 128,
            expectedSHA256: nil,
            state: state,
            retryCount: retryCount,
            createdAt: Date(),
            updatedAt: Date()
        )
        try store.journal.record(entry)
    }

    private func recordingID(of url: URL) -> UUID {
        UUID(uuidString: url.deletingPathExtension().lastPathComponent)!
    }

    // MARK: - M7-021 cold-launch recovery

    func testResumablePromotionCompletesWithRealMetadataAndConsumesPending() throws {
        let recordingID = UUID()
        makePendingFile(recordingID: recordingID)
        try journalEntry(recordingID: recordingID, projectID: projectID, state: .promoting)

        let outcomes = try store.recoverPendingRecordings(
            mediaMetadata: { _ in (duration: 12.5, hasAudio: true) }
        )

        XCTAssertEqual(outcomes, [.completed(SceneRecordingReference(
            recordingID: recordingID,
            relativePath: "Recordings/Projects/\(projectID.uuidString)/\(recordingID.uuidString).mov",
            duration: 12.5,
            hasAudio: true
        ))])
        let destination = store.projectsDirectoryURL
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent("\(recordingID.uuidString).mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try store.journal.entry(for: recordingID)?.state, .promoted)
    }

    func testCrashAfterCommitConvergesToAlreadyPromotedWithoutTouchingDestination() throws {
        let recordingID = UUID()
        let destination = try makeProjectFile(recordingID: recordingID)
        let destinationBytes = try Data(contentsOf: destination)
        try journalEntry(recordingID: recordingID, projectID: projectID, state: .promoting)

        let outcomes = try store.recoverPendingRecordings(mediaMetadata: { _ in (nil, false) })

        XCTAssertEqual(outcomes, [.alreadyPromoted(recordingID: recordingID)])
        XCTAssertEqual(try Data(contentsOf: destination), destinationBytes)
        XCTAssertEqual(try store.journal.entry(for: recordingID)?.state, .promoted)
    }

    func testCorruptRecordIsReportedAndPreservedForHonestDiagnosis() throws {
        let recordingID = UUID()
        try journalEntry(recordingID: recordingID, projectID: projectID, state: .pending)
        let recordURL = store.journal.journalDirectoryURL
            .appendingPathComponent(recordingID.uuidString)
            .appendingPathExtension("json")
        try Data("garbage".utf8).write(to: recordURL)

        let outcomes = try store.recoverPendingRecordings(mediaMetadata: { _ in (nil, false) })

        XCTAssertEqual(outcomes, [.corruptRecord(recordingID: recordingID)])
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordURL.path))
    }

    func testMissingSourceAndDestinationConvergesToMissingArtifact() throws {
        let recordingID = UUID()
        try journalEntry(recordingID: recordingID, projectID: projectID, state: .pending)

        let outcomes = try store.recoverPendingRecordings(mediaMetadata: { _ in (nil, false) })

        XCTAssertEqual(outcomes, [.missingArtifact(recordingID: recordingID)])
        XCTAssertNil(try store.journal.entry(for: recordingID))
    }

    func testRetryBudgetExhaustionKeepsPendingAndMarksEntryFailed() throws {
        let recordingID = UUID()
        let pendingURL = makePendingFile(recordingID: recordingID)
        try journalEntry(
            recordingID: recordingID,
            projectID: projectID,
            state: .promoting,
            retryCount: PendingRecordingJournalEntry.maxRetryCount
        )

        let outcomes = try store.recoverPendingRecordings(
            maxRetryCount: PendingRecordingJournalEntry.maxRetryCount,
            mediaMetadata: { _ in (nil, false) }
        )

        XCTAssertEqual(outcomes, [.failedEntry(recordingID: recordingID)])
        XCTAssertTrue(FileManager.default.fileExists(atPath: pendingURL.path))
        XCTAssertEqual(try store.journal.entry(for: recordingID)?.state, .failed)
    }

    func testFailedEntryIsSurfacedAndPendingIsPreserved() throws {
        let recordingID = UUID()
        let pendingURL = makePendingFile(recordingID: recordingID)
        try journalEntry(recordingID: recordingID, projectID: projectID, state: .failed)

        let outcomes = try store.recoverPendingRecordings(mediaMetadata: { _ in (nil, false) })

        XCTAssertEqual(outcomes, [.failedEntry(recordingID: recordingID)])
        XCTAssertTrue(FileManager.default.fileExists(atPath: pendingURL.path))
    }

    func testRecoveryNeverTouchesSiblingProjectMedia() throws {
        let siblingRecordingID = UUID()
        let siblingURL = try makeProjectFile(recordingID: siblingRecordingID)
        let siblingBytes = try Data(contentsOf: siblingURL)

        _ = try store.recoverPendingRecordings(mediaMetadata: { _ in (nil, false) })

        XCTAssertEqual(try Data(contentsOf: siblingURL), siblingBytes)
    }

    // MARK: - M7-022 kill-point convergence fixture

    /// K1: a kill during recording/finalization leaves a pending file with no
    /// journal record. At cold launch that file is an orphan; the cleanup
    /// path converges it to "gone" while project media survives. Kill points
    /// K2–K4 (journal written / renamed / tombstone removed) are covered by
    /// the M7-020 promotion fault matrix.
    func testKillBeforeJournalWriteConvergesThroughOrphanCleanup() throws {
        let recordingID = UUID()
        let pendingURL = makePendingFile(recordingID: recordingID)
        let protectedProjectFile = try makeProjectFile(recordingID: UUID())

        let inventory = try store.orphanInventory()
        XCTAssertTrue(inventory.contains { candidate in
            candidate.recordingID == recordingID && candidate.classification == .orphan
        })

        let removed = try store.removeOrphans(inventory)
        XCTAssertEqual(removed, [recordingID])
        XCTAssertFalse(FileManager.default.fileExists(atPath: pendingURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: protectedProjectFile.path))
    }

    // MARK: - M7-023 retention policy

    func testRetentionIsClockControlledAndNeverTouchesLiveOrProjectMedia() throws {
        let now = Date()
        let maxAge: TimeInterval = 7 * 24 * 3600

        let youngPending = makePendingFile()
        let oldPending = makePendingFile()
        let oldFailed = makePendingFile()
        let oldLiveJournal = makePendingFile()
        let projectFile = try makeProjectFile(recordingID: UUID())

        let agedDate = now.addingTimeInterval(-8 * 24 * 3600)
        for url in [oldPending, oldFailed, oldLiveJournal] {
            try FileManager.default.setAttributes(
                [.modificationDate: agedDate],
                ofItemAtPath: url.path
            )
        }
        try journalEntry(
            recordingID: recordingID(of: oldFailed),
            projectID: projectID,
            state: .failed
        )
        try journalEntry(
            recordingID: recordingID(of: oldLiveJournal),
            projectID: projectID,
            state: .promoting
        )

        let candidates = try store.retentionInventory(now: now, pendingMaxAge: maxAge)
        let candidateIDs = Set(candidates.map(\.recordingID))

        XCTAssertTrue(candidateIDs.contains(recordingID(of: oldPending)))
        XCTAssertTrue(candidateIDs.contains(recordingID(of: oldFailed)))
        XCTAssertFalse(candidateIDs.contains(recordingID(of: youngPending)))
        XCTAssertFalse(candidateIDs.contains(recordingID(of: oldLiveJournal)),
                       "a live promotion intent is never retention-deleted")

        let removed = try store.applyRetention(removing: candidates)
        XCTAssertTrue(removed.contains(recordingID(of: oldPending)))
        XCTAssertTrue(removed.contains(recordingID(of: oldFailed)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldPending.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFailed.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: youngPending.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldLiveJournal.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectFile.path))
        // The failed tombstone is removed together with its expired file.
        XCTAssertNil(try store.journal.entry(for: recordingID(of: oldFailed)))
    }

    // MARK: - M7-024 orphan cleanup security

    func testOrphanCleanupIsAttackSafeAndDryRunFirst() throws {
        let orphanID = UUID()
        let journaledID = UUID()
        makePendingFile(recordingID: orphanID)
        makePendingFile(recordingID: journaledID)
        try journalEntry(recordingID: journaledID, projectID: projectID, state: .promoting)
        FileManager.default.createFile(
            atPath: store.pendingDirectoryURL.appendingPathComponent("notes.txt").path,
            contents: Data("foreign".utf8)
        )
        let symlinkURL = store.pendingDirectoryURL
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        let symlinkTarget = applicationSupportURL.appendingPathComponent("symlink-target.bin")
        FileManager.default.createFile(atPath: symlinkTarget.path, contents: Data([0x01]))
        try FileManager.default.createSymbolicLink(
            at: symlinkURL,
            withDestinationURL: symlinkTarget
        )

        // Dry run: the inventory precedes any delete and classifies reasons.
        let inventory = try store.orphanInventory()
        var classifications: [String: String] = [:]
        for candidate in inventory {
            classifications[candidate.name] = candidate.classification.reasonKey
        }
        XCTAssertEqual(classifications[orphanID.uuidString + ".mov"], "orphan")
        XCTAssertEqual(classifications[journaledID.uuidString + ".mov"], "journalReference")
        XCTAssertEqual(classifications["notes.txt"], "foreignName")
        XCTAssertEqual(classifications[symlinkURL.lastPathComponent], "symlink")

        let removed = try store.removeOrphans(inventory)
        XCTAssertEqual(removed, [orphanID])
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanURL(of: orphanID).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: symlinkTarget.path),
                      "a symlink must never be followed or deleted")
        XCTAssertTrue(FileManager.default.fileExists(atPath: symlinkURL.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: store.pendingDirectoryURL.appendingPathComponent("notes.txt").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: orphanURL(of: journaledID).path
        ))
    }

    private func orphanURL(of recordingID: UUID) -> URL {
        store.pendingDirectoryURL
            .appendingPathComponent(recordingID.uuidString)
            .appendingPathExtension("mov")
    }

    // MARK: - M7-021/M7-023 cold-launch maintenance entry point

    func testColdLaunchMaintenanceConvergesJournalAndSweepsOnlyExpiredPending() throws {
        let resumableID = UUID()
        makePendingFile(recordingID: resumableID)
        try journalEntry(recordingID: resumableID, projectID: projectID, state: .promoting)

        let expiredID = UUID()
        let expiredURL = makePendingFile(recordingID: expiredID)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-8 * 24 * 3600)],
            ofItemAtPath: expiredURL.path
        )

        let projectFile = try makeProjectFile(recordingID: UUID())

        let (outcomes, removedCount) = store.performColdLaunchMaintenance(
            mediaMetadata: { _ in (duration: 12.5, hasAudio: true) }
        )

        XCTAssertTrue(outcomes.contains { $0 == .completed(SceneRecordingReference(
            recordingID: resumableID,
            relativePath: "Recordings/Projects/\(projectID.uuidString)/\(resumableID.uuidString).mov",
            duration: 12.5,
            hasAudio: true
        )) })
        XCTAssertEqual(removedCount, 1)
        XCTAssertEqual(try store.journal.entry(for: resumableID)?.state, .promoted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: expiredURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectFile.path))
    }

    // MARK: - M7-025 project media deletion with journal cleanup

    func testProjectDeletionRemovesOwnedMediaAndLeftoverJournalRecords() async throws {
        let dbService = DBService(
            recordingArtifactStore: store,
            projectLeases: ProjectLifecycleRegistry()
        )
        let project = try dbService.createUnifiedSceneProject(named: "deletion-journal-test")

        // A leftover failed promotion record from a crashed take, bound to
        // the project that is about to be deleted, plus its pending file.
        let recordingID = UUID()
        makePendingFile(recordingID: recordingID)
        try journalEntry(recordingID: recordingID, projectID: project.id, state: .failed)
        let promotedSibling = try makeProjectFile(recordingID: UUID())

        let deletion = expectation(description: "project deleted")
        var deletionResult: Result<Void, SETLibraryFailure>?
        dbService.deleteUnifiedSceneProject(
            id: project.id,
            expectedUpdatedAt: project.updatedAt
        ) { result in
            deletionResult = result
            deletion.fulfill()
        }
        await fulfillment(of: [deletion], timeout: 5)

        guard case .success = deletionResult else {
            XCTFail("Deletion must succeed: \(String(describing: deletionResult))")
            return
        }
        // The failed tombstone for the deleted project cannot recover and is
        // removed with the project; its pending file is deliberately NOT
        // deleted here — it is not project-owned media, and retention (M7-023)
        // owns its expiry so a deletion bug can never destroy a recoverable
        // take.
        XCTAssertNil(try store.journal.entry(for: recordingID))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: orphanURL(of: recordingID).path
        ))
        // Sibling project media of other projects stays untouched.
        XCTAssertTrue(FileManager.default.fileExists(atPath: promotedSibling.path))
    }

    func testLegacySourceIdentityProtectsLiveJournalAcrossAllPendingDeletionPaths() throws {
        let pendingID = UUID()
        let recordingID = UUID()
        let pendingURL = makePendingFile(recordingID: pendingID)
        let now = Date()
        let age: TimeInterval = 7 * 24 * 3600
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-age - 60)],
            ofItemAtPath: pendingURL.path
        )
        // Inventories made before the promotion intent became live are stale.
        let staleRetention = try store.retentionInventory(now: now, pendingMaxAge: age)
        let staleOrphans = try store.orphanInventory()
        let entry = PendingRecordingJournalEntry(
            recordingID: recordingID,
            projectID: projectID,
            sourceTempPath: "Recordings/Pending/\(pendingID.uuidString).mov",
            destinationRelativePath: "Recordings/Projects/\(projectID.uuidString)/\(recordingID.uuidString).mov",
            expectedFileSize: 128, expectedSHA256: nil, state: .promoting,
            retryCount: 0, createdAt: now, updatedAt: now
        )
        try store.journal.record(entry)

        XCTAssertTrue(try store.retentionInventory(now: now, pendingMaxAge: age).isEmpty)
        XCTAssertEqual(try store.orphanInventory().first?.classification, .skipped(reason: "journalReference"))
        XCTAssertTrue(try store.applyRetention(removing: staleRetention).isEmpty)
        XCTAssertTrue(try store.removeOrphans(staleOrphans).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: pendingURL.path))

        try store.journal.record(entry.updating(state: .failed, at: now))
        let expired = try store.retentionInventory(now: now, pendingMaxAge: age)
        XCTAssertEqual(expired.first?.reason, .expiredFailedEntry)
        XCTAssertEqual(try store.applyRetention(removing: expired), [pendingID])
        XCTAssertFalse(FileManager.default.fileExists(atPath: pendingURL.path))
        XCTAssertNil(try store.journal.entry(for: recordingID), "remove the owning journal, not the filename UUID")
    }

    func testDestructivePendingOperationsFailClosedForUnreadableAndAmbiguousJournal() throws {
        let pendingID = UUID()
        let pendingURL = makePendingFile(recordingID: pendingID)
        let now = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-8 * 24 * 3600)],
            ofItemAtPath: pendingURL.path
        )
        let retention = try store.retentionInventory(now: now, pendingMaxAge: 7 * 24 * 3600)
        let orphans = try store.orphanInventory()
        let corruptID = UUID()
        let corruptURL = store.journal.journalDirectoryURL.appendingPathComponent("\(corruptID.uuidString).json")
        try Data("not-json".utf8).write(to: corruptURL)

        func assertProtected(file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertThrowsError(try store.retentionInventory(now: now, pendingMaxAge: 7 * 24 * 3600), file: file, line: line)
            XCTAssertThrowsError(try store.orphanInventory(), file: file, line: line)
            XCTAssertThrowsError(try store.applyRetention(removing: retention), file: file, line: line)
            XCTAssertThrowsError(try store.removeOrphans(orphans), file: file, line: line)
            XCTAssertTrue(FileManager.default.fileExists(atPath: pendingURL.path), file: file, line: line)
        }
        assertProtected()
        try FileManager.default.removeItem(at: corruptURL)

        for recordingID in [UUID(), UUID()] {
            try store.journal.record(PendingRecordingJournalEntry(
                recordingID: recordingID, projectID: projectID,
                sourceTempPath: "Recordings/Pending/\(pendingID.uuidString).mov",
                destinationRelativePath: "Recordings/Projects/\(projectID.uuidString)/\(recordingID.uuidString).mov",
                expectedFileSize: 128, expectedSHA256: nil, state: .promoting,
                retryCount: 0, createdAt: now, updatedAt: now
            ))
        }
        assertProtected()

        let journalRoot = store.journal.journalDirectoryURL
        let parkedJournal = journalRoot.appendingPathExtension("parked")
        try FileManager.default.moveItem(at: journalRoot, to: parkedJournal)
        defer { try? FileManager.default.moveItem(at: parkedJournal, to: journalRoot) }
        assertProtected()
    }

    // MARK: - M7-029 file protection / backup policy

    func testTransientRootsAndPendingFilesAreExcludedFromBackup() throws {
        let pendingValues = try? store.pendingDirectoryURL.resourceValues(
            forKeys: [.isExcludedFromBackupKey]
        )
        XCTAssertEqual(pendingValues?.isExcludedFromBackup, true)

        let journalValues = try? store.journal.journalDirectoryURL.resourceValues(
            forKeys: [.isExcludedFromBackupKey]
        )
        XCTAssertEqual(journalValues?.isExcludedFromBackup, true)

        let pendingFile = makePendingFile()
        store.applyPendingArtifactPolicy(to: pendingFile)
        let fileValues = try? pendingFile.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(fileValues?.isExcludedFromBackup, true)

        // Project media is user data: the pending policy must not touch it.
        let projectFile = try makeProjectFile(recordingID: UUID())
        store.applyPendingArtifactPolicy(to: projectFile)
        let projectValues = try? projectFile.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertTrue(projectValues?.isExcludedFromBackup == false
            || projectValues?.isExcludedFromBackup == nil)
    }
}

private extension RecordingArtifactStore.RecordingOrphanCandidate.Classification {
    var reasonKey: String {
        switch self {
        case .orphan: return "orphan"
        case let .skipped(reason): return reason
        }
    }
}
