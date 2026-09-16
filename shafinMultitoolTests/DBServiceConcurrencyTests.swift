//
//  DBServiceConcurrencyTests.swift
//  shafinMultitoolTests
//
//  M1-015 PersistenceOwner: file persistence is serialized on one queue and
//  optimistic conflicts (stale snapshots) produce a typed recoverable error
//  without overwriting the stored write.
//

import AVFoundation
import CoreVideo
import XCTest
@testable import shafinMultitool

final class DBServiceConcurrencyTests: XCTestCase {

    private var dbService: DBService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbService = DBService()
        dbService.resetUnifiedSceneProjectsForUITesting()
        // The legacy cleanup API completes synchronously to its caller after
        // the serialized operation, so this setup needs no expectations.
        for title in dbService.getAllARWorldMapTitles() ?? [] {
            dbService.deleteMap(with: title) { _ in }
        }
    }

    override func tearDownWithError() throws {
        dbService.resetUnifiedSceneProjectsForUITesting()
        dbService = nil
        try super.tearDownWithError()
    }

    // MARK: - Creation serialization

    func testTypedEmptyLoadIsARealZeroProjectResult() {
        XCTAssertEqual(dbService.loadLibrarySceneSnapshots(), .success([]))
    }

    func testMalformedProjectLoadFailsInsteadOfMasqueradingAsEmpty() throws {
        let directory = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ).appendingPathComponent("UnifiedSceneProjects", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        let fileURL = directory.appendingPathComponent("\(id.uuidString)_project.json")
        try Data("{\"schemaVersion\": 99}".utf8).write(to: fileURL, options: [.atomic])

        guard case .failure(.persistence) = dbService.loadLibrarySceneSnapshots() else {
            return XCTFail("A malformed persisted project must be a typed load failure.")
        }
    }

    func testTypedLoadPreservesDuplicateNamesAndOrdersTimestampTiesByUUID() throws {
        let firstID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        let updatedAt = Date(timeIntervalSince1970: 1_787_000_000)
        try dbService.saveUnifiedSceneProject(
            UnifiedSceneProject(id: secondID, name: "ОДНО ИМЯ", updatedAt: updatedAt),
            worldMap: nil
        )
        try dbService.saveUnifiedSceneProject(
            UnifiedSceneProject(id: firstID, name: "ОДНО ИМЯ", updatedAt: updatedAt),
            worldMap: nil
        )

        let snapshots = try XCTUnwrap(dbService.loadLibrarySceneSnapshots().successValue)
        XCTAssertEqual(snapshots.map(\.id), [firstID, secondID])
        XCTAssertEqual(snapshots.map(\.name), ["ОДНО ИМЯ", "ОДНО ИМЯ"])
        XCTAssertEqual(snapshots.map(\.updatedAt), [updatedAt, updatedAt])
    }

    func testConcurrentCreatesWithSameNameCreateExactlyOneProject() {
        let results = concurrentPerform(8) { _ in
            try? self.dbService.createUnifiedSceneProject(named: "dup-project")
        }

        let successes = results.compactMap { $0 }
        XCTAssertEqual(successes.count, 1, "exactly one concurrent create must win")
        XCTAssertEqual(Set(successes.map(\.name)), ["dup-project"])
        XCTAssertEqual(dbService.listUnifiedSceneProjects().count, 1)
    }

    func testTypedConcurrentCreatesReturnOneSnapshotAndTypedDuplicates() {
        let name = "typed-dup-\(UUID().uuidString)"
        let results = concurrentPerform(8) { _ in
            self.dbService.createLibraryScene(named: name)
        }

        XCTAssertEqual(results.filter { if case .success = $0 { return true }; return false }.count, 1)
        XCTAssertEqual(
            results.filter {
                if case .failure(.duplicateName(name: name, conflictingID: _)) = $0 { return true }
                return false
            }.count,
            7
        )
        XCTAssertEqual(
            dbService.loadLibrarySceneSnapshots().map { $0.filter { $0.name == name }.count },
            .success(1)
        )
    }

    func testLibrarySnapshotReportsMetadataAndNoArtifactsTruthfully() throws {
        let name = "typed-snapshot-\(UUID().uuidString)"
        let created = try XCTUnwrap(dbService.createLibraryScene(named: name).successValue)
        XCTAssertEqual(created.preview.kind, .unavailable)
        XCTAssertEqual(created.artifactHealth, .none)

        var project = try XCTUnwrap(dbService.loadUnifiedSceneProject(named: name)?.0)
        project.sceneDescription = "A marked room with a window."
        try dbService.saveUnifiedSceneProject(project, worldMap: nil)

        let loaded = try XCTUnwrap(dbService.loadLibrarySceneSnapshots().successValue)
        let snapshot = try XCTUnwrap(loaded.first { $0.id == project.id })
        XCTAssertEqual(snapshot.preview.kind, .metadataOnly)
        XCTAssertEqual(snapshot.preview.recordingCount, 0)
        XCTAssertEqual(snapshot.artifactHealth, .none)
    }

    func testLibrarySnapshotUsesOnlyOwnedRecordingForPreviewSource() async throws {
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scene-library-preview-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupportURL) }

        let store = try RecordingArtifactStore(applicationSupportDirectoryURL: applicationSupportURL)
        let service = DBService(recordingArtifactStore: store)
        let project = try service.createUnifiedSceneProject(named: "preview-source-\(UUID().uuidString)")
        defer { service.deleteUnifiedSceneProject(named: project.name) { _ in } }

        let recordingID = UUID()
        let reference = SceneRecordingReference(
            recordingID: recordingID,
            relativePath: "Recordings/Projects/\(project.id.uuidString)/\(recordingID.uuidString).mov"
        )
        var enriched = project
        enriched.recordingReferences = [reference]
        try service.saveUnifiedSceneProject(enriched, worldMap: nil)

        let projectArtifactsURL = store.projectsDirectoryURL
            .appendingPathComponent(project.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectArtifactsURL, withIntermediateDirectories: true)
        let artifactURL = projectArtifactsURL.appendingPathComponent("\(recordingID.uuidString).mov")
        try await makeValidMovie(at: artifactURL, recordingID: recordingID)

        let valid = try XCTUnwrap(service.loadLibrarySceneSnapshots().successValue?.first)
        XCTAssertEqual(valid.preview.recordingReference, reference)
        XCTAssertEqual(valid.preview.kind, .metadataOnly, "A valid recording is a preview source even without other metadata.")
        XCTAssertEqual(valid.artifactHealth, .healthy)

        try FileManager.default.removeItem(at: artifactURL)
        let deleted = try XCTUnwrap(service.loadLibrarySceneSnapshots().successValue?.first)
        XCTAssertNil(deleted.preview.recordingReference, "Deleted media must use the metadata fallback.")
        XCTAssertEqual(deleted.artifactHealth, .missing)

        XCTAssertTrue(FileManager.default.createFile(atPath: artifactURL.path, contents: Data("not a movie".utf8)))
        let corrupt = try XCTUnwrap(service.loadLibrarySceneSnapshots().successValue?.first)
        XCTAssertNil(corrupt.preview.recordingReference, "Non-decodable media must not enter preview rendering.")
        XCTAssertEqual(corrupt.artifactHealth, .corrupt)
    }

    func testLibrarySnapshotRejectsValidMediaOutsideCanonicalProjectPath() async throws {
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scene-library-preview-ownership-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupportURL) }

        let store = try RecordingArtifactStore(applicationSupportDirectoryURL: applicationSupportURL)
        let service = DBService(recordingArtifactStore: store)
        let project = try service.createUnifiedSceneProject(named: "preview-ownership-\(UUID().uuidString)")
        defer { service.deleteUnifiedSceneProject(named: project.name) { _ in } }

        let recordingID = UUID()
        let projectDirectory = store.projectsDirectoryURL
            .appendingPathComponent(project.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        let ownedURL = projectDirectory.appendingPathComponent("\(recordingID.uuidString).mov")
        try await makeValidMovie(at: ownedURL, recordingID: recordingID)

        let foreignProjectID = UUID()
        let foreignDirectory = store.projectsDirectoryURL
            .appendingPathComponent(foreignProjectID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: foreignDirectory, withIntermediateDirectories: true)
        let foreignURL = foreignDirectory.appendingPathComponent("\(recordingID.uuidString).mov")
        try FileManager.default.copyItem(at: ownedURL, to: foreignURL)

        let pendingURL = store.pendingDirectoryURL.appendingPathComponent("\(recordingID.uuidString).mov")
        try FileManager.default.copyItem(at: ownedURL, to: pendingURL)

        let paths = [
            "Recordings/Projects/\(foreignProjectID.uuidString)/\(recordingID.uuidString).mov",
            "Recordings/Pending/\(recordingID.uuidString).mov"
        ]
        for path in paths {
            var enriched = project
            enriched.recordingReferences = [SceneRecordingReference(
                recordingID: recordingID,
                relativePath: path
            )]
            try service.saveUnifiedSceneProject(enriched, worldMap: nil)

            let snapshot = try XCTUnwrap(service.loadLibrarySceneSnapshots().successValue?.first)
            XCTAssertNil(snapshot.preview.recordingReference, "A valid movie outside the project binding must not become a preview source.")
            XCTAssertEqual(snapshot.artifactHealth, .missing, "An unowned reference must be unavailable, not healthy.")
        }
    }

    // MARK: - Optimistic conflict behavior

    func testStaleExpectedUpdatedAtThrowsRecoverableConflictAndKeepsStoredWrite() throws {
        let project = try dbService.createUnifiedSceneProject(named: "conflict-project")

        var first = project
        first.sceneDescription = "first write"
        first.updatedAt = Date(timeIntervalSince1970: 1_000)
        try dbService.saveUnifiedSceneProject(first, worldMap: nil)

        var second = first
        second.sceneDescription = "second write"
        second.updatedAt = Date(timeIntervalSince1970: 2_000)
        try dbService.saveUnifiedSceneProject(second, worldMap: nil)

        // A writer based on the first version must not clobber the second.
        var stale = first
        stale.sceneDescription = "stale overwrite"
        XCTAssertThrowsError(
            try dbService.saveUnifiedSceneProject(stale, worldMap: nil, expectedUpdatedAt: first.updatedAt)
        ) { error in
            XCTAssertEqual(
                error as? DBServiceError,
                .staleSnapshot(storedUpdatedAt: second.updatedAt)
            )
        }

        let stored = try XCTUnwrap(dbService.loadUnifiedSceneProject(named: "conflict-project"))
        XCTAssertEqual(stored.0.sceneDescription, "second write", "stale write must not land")

        // The up-to-date writer proceeds; the file stays readable throughout.
        var third = second
        third.sceneDescription = "third write"
        try dbService.saveUnifiedSceneProject(third, worldMap: nil, expectedUpdatedAt: second.updatedAt)
        let reloaded = try XCTUnwrap(dbService.loadUnifiedSceneProject(named: "conflict-project"))
        XCTAssertEqual(reloaded.0.sceneDescription, "third write")
    }

    func testTypedRenamePreservesAggregateAndReturnsNewSnapshot() throws {
        let project = try dbService.createUnifiedSceneProject(named: "rename-source-\(UUID().uuidString)")
        let targetName = "rename-target-\(UUID().uuidString)"
        let recordingID = UUID()
        let reference = SceneRecordingReference(
            recordingID: recordingID,
            relativePath: "Recordings/Projects/\(project.id.uuidString)/\(recordingID.uuidString).mov",
            duration: 12.5,
            hasAudio: true
        )
        var enriched = project
        enriched.sceneDescription = "A room, a window, a marked chair."
        enriched.recordingReferences = [reference]
        try dbService.saveUnifiedSceneProject(enriched, worldMap: nil)

        let result = dbService.renameUnifiedSceneProject(
            id: enriched.id,
            to: targetName,
            expectedUpdatedAt: enriched.updatedAt
        )
        let snapshot = try XCTUnwrap(result.successValue)
        XCTAssertEqual(snapshot.id, enriched.id)
        XCTAssertEqual(snapshot.name, targetName)
        XCTAssertEqual(snapshot.preview.recordingCount, 1)
        XCTAssertEqual(snapshot.artifactHealth, .missing, "a reference is not evidence of a healthy artifact")

        let renamed = try XCTUnwrap(dbService.loadUnifiedSceneProject(named: snapshot.name)?.0)
        XCTAssertEqual(renamed.id, enriched.id)
        XCTAssertEqual(renamed.createdAt, enriched.createdAt)
        XCTAssertEqual(renamed.sceneDescription, enriched.sceneDescription)
        XCTAssertEqual(renamed.markedObjects, enriched.markedObjects)
        XCTAssertEqual(renamed.parsedScript, enriched.parsedScript)
        XCTAssertEqual(renamed.plannedScene, enriched.plannedScene)
        XCTAssertEqual(renamed.sceneChunkState, enriched.sceneChunkState)
        XCTAssertEqual(renamed.visualOverlays, enriched.visualOverlays)
        XCTAssertEqual(renamed.recordingReferences, enriched.recordingReferences)
        XCTAssertEqual(renamed.updatedAt, snapshot.updatedAt)
        XCTAssertGreaterThan(renamed.updatedAt, enriched.updatedAt)
        XCTAssertNil(dbService.loadUnifiedSceneProject(named: enriched.name))
    }

    func testTypedRenameRejectsStaleSnapshotWithoutMutation() throws {
        let project = try dbService.createUnifiedSceneProject(named: "rename-stale-\(UUID().uuidString)")
        let staleDate = project.updatedAt.addingTimeInterval(-1)

        let result = dbService.renameUnifiedSceneProject(
            id: project.id,
            to: "must-not-land",
            expectedUpdatedAt: staleDate
        )
        guard case .failure(.staleSnapshot(let expected, let stored)) = result else {
            return XCTFail("expected typed stale snapshot, got \(result)")
        }
        XCTAssertEqual(expected, staleDate)
        XCTAssertEqual(stored, project.updatedAt)
        let unchanged = try XCTUnwrap(dbService.loadUnifiedSceneProject(named: project.name)?.0)
        XCTAssertEqual(unchanged, project)
    }

    func testTypedDeletePreservesProjectWhenArtifactCleanupFails() throws {
        let project = try dbService.createUnifiedSceneProject(named: "delete-artifact-failure-\(UUID().uuidString)")
        let recordingID = UUID()
        let reference = SceneRecordingReference(
            recordingID: recordingID,
            relativePath: "Recordings/Projects/\(project.id.uuidString)/\(recordingID.uuidString).mov"
        )
        var withRecording = project
        withRecording.recordingReferences = [reference]
        try dbService.saveUnifiedSceneProject(withRecording, worldMap: nil)

        let store = try RecordingArtifactStore()
        let projectArtifactsURL = store.projectsDirectoryURL.appendingPathComponent(project.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectArtifactsURL, withIntermediateDirectories: true)
        let unexpectedEntry = projectArtifactsURL.appendingPathComponent("unexpected.txt")
        try Data("not a movie".utf8).write(to: unexpectedEntry)
        defer { try? FileManager.default.removeItem(at: projectArtifactsURL) }

        var result: Result<Void, SETLibraryFailure>?
        dbService.deleteUnifiedSceneProject(id: project.id, expectedUpdatedAt: withRecording.updatedAt) {
            result = $0
        }

        guard case .failure(.artifactCleanup) = result else {
            return XCTFail("expected typed artifact cleanup failure, got \(String(describing: result))")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: unexpectedEntry.path))
        XCTAssertEqual(dbService.loadUnifiedSceneProject(named: project.name)?.0, withRecording)
    }

    func testTypedDeleteRemovesOnlyProjectAndOwnedArtifacts() throws {
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scene-library-delete-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupportURL) }

        let store = try RecordingArtifactStore(applicationSupportDirectoryURL: applicationSupportURL)
        let service = DBService(recordingArtifactStore: store)
        let first = try service.createUnifiedSceneProject(named: "delete-owned-one-\(UUID().uuidString)")
        let second = try service.createUnifiedSceneProject(named: "delete-owned-two-\(UUID().uuidString)")

        let firstRecordingID = UUID()
        let secondRecordingID = UUID()
        var firstWithRecording = first
        firstWithRecording.recordingReferences = [SceneRecordingReference(
            recordingID: firstRecordingID,
            relativePath: "Recordings/Projects/\(first.id.uuidString)/\(firstRecordingID.uuidString).mov"
        )]
        var secondWithRecording = second
        secondWithRecording.recordingReferences = [SceneRecordingReference(
            recordingID: secondRecordingID,
            relativePath: "Recordings/Projects/\(second.id.uuidString)/\(secondRecordingID.uuidString).mov"
        )]
        try service.saveUnifiedSceneProject(firstWithRecording, worldMap: nil)
        try service.saveUnifiedSceneProject(secondWithRecording, worldMap: nil)

        let firstDirectory = store.projectsDirectoryURL.appendingPathComponent(first.id.uuidString, isDirectory: true)
        let secondDirectory = store.projectsDirectoryURL.appendingPathComponent(second.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        let firstArtifact = firstDirectory.appendingPathComponent("\(firstRecordingID.uuidString).mov")
        let secondArtifact = secondDirectory.appendingPathComponent("\(secondRecordingID.uuidString).mov")
        XCTAssertTrue(FileManager.default.createFile(atPath: firstArtifact.path, contents: Data("owned one".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: secondArtifact.path, contents: Data("owned two".utf8)))

        var result: Result<Void, SETLibraryFailure>?
        service.deleteUnifiedSceneProject(id: first.id, expectedUpdatedAt: firstWithRecording.updatedAt) {
            result = $0
        }

        guard case .success = result else {
            return XCTFail("expected successful project and artifact deletion, got \(String(describing: result))")
        }
        XCTAssertNil(service.loadUnifiedSceneProject(named: firstWithRecording.name))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondArtifact.path), "A sibling project's artifact must remain.")
        XCTAssertEqual(try Data(contentsOf: secondArtifact), Data("owned two".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstArtifact.path), "The deleted project's artifact must be removed.")
        XCTAssertNotNil(service.loadUnifiedSceneProject(named: secondWithRecording.name))
    }

    func testTypedDeleteRemovesPromotedArtifactsWhenReferencesAreNotPersisted() throws {
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scene-library-delete-promoted-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupportURL) }

        let store = try RecordingArtifactStore(applicationSupportDirectoryURL: applicationSupportURL)
        let service = DBService(recordingArtifactStore: store)
        let project = try service.createUnifiedSceneProject(named: "delete-promoted-\(UUID().uuidString)")

        let projectDirectory = store.projectsDirectoryURL
            .appendingPathComponent(project.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        let promotedRecordingID = UUID()
        let promotedArtifact = projectDirectory.appendingPathComponent("\(promotedRecordingID.uuidString).mov")
        let promotedData = Data("promoted before metadata".utf8)
        XCTAssertTrue(FileManager.default.createFile(atPath: promotedArtifact.path, contents: promotedData))

        let siblingProjectID = UUID()
        let siblingDirectory = store.projectsDirectoryURL
            .appendingPathComponent(siblingProjectID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: siblingDirectory, withIntermediateDirectories: true)
        let siblingArtifact = siblingDirectory.appendingPathComponent("\(UUID().uuidString).mov")
        let siblingData = Data("sibling must remain".utf8)
        XCTAssertTrue(FileManager.default.createFile(atPath: siblingArtifact.path, contents: siblingData))
        let pendingArtifact = store.pendingDirectoryURL.appendingPathComponent("pending-promoted.mov")
        let pendingData = Data("pending must remain".utf8)
        XCTAssertTrue(FileManager.default.createFile(atPath: pendingArtifact.path, contents: pendingData))

        var result: Result<Void, SETLibraryFailure>?
        service.deleteUnifiedSceneProject(id: project.id, expectedUpdatedAt: project.updatedAt) {
            result = $0
        }

        guard case .success = result else {
            return XCTFail("expected promoted artifact cleanup to succeed, got \(String(describing: result))")
        }
        XCTAssertNil(service.loadUnifiedSceneProject(named: project.name))
        XCTAssertFalse(FileManager.default.fileExists(atPath: promotedArtifact.path))
        XCTAssertEqual(try Data(contentsOf: siblingArtifact), siblingData)
        XCTAssertEqual(try Data(contentsOf: pendingArtifact), pendingData)
    }

    func testTypedDeleteRollsBackPromotedArtifactWhenCommitFailsWithoutReference() throws {
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scene-library-delete-promoted-rollback-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupportURL) }

        let store = try RecordingArtifactStore(applicationSupportDirectoryURL: applicationSupportURL)
        let service = DBService(recordingArtifactStore: store)
        let project = try service.createUnifiedSceneProject(named: "delete-promoted-rollback-\(UUID().uuidString)")

        let projectDirectory = store.projectsDirectoryURL
            .appendingPathComponent(project.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        let promotedRecordingID = UUID()
        let promotedArtifact = projectDirectory.appendingPathComponent("\(promotedRecordingID.uuidString).mov")
        let promotedData = Data("promoted rollback bytes".utf8)
        XCTAssertTrue(FileManager.default.createFile(atPath: promotedArtifact.path, contents: promotedData))

        let siblingProjectID = UUID()
        let siblingDirectory = store.projectsDirectoryURL
            .appendingPathComponent(siblingProjectID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: siblingDirectory, withIntermediateDirectories: true)
        let siblingArtifact = siblingDirectory.appendingPathComponent("\(UUID().uuidString).mov")
        let siblingData = Data("sibling rollback bytes".utf8)
        XCTAssertTrue(FileManager.default.createFile(atPath: siblingArtifact.path, contents: siblingData))
        let pendingArtifact = store.pendingDirectoryURL.appendingPathComponent("pending-promoted-rollback.mov")
        let pendingData = Data("pending rollback bytes".utf8)
        XCTAssertTrue(FileManager.default.createFile(atPath: pendingArtifact.path, contents: pendingData))

        // Promotion may have succeeded before the project reference was
        // persisted. A later artifact failure must restore both ownership
        // metadata and that promoted file, while leaving unrelated media alone.
        store.testArtifactCommitFailureAfterUnlinks = 0
        var result: Result<Void, SETLibraryFailure>?
        service.deleteUnifiedSceneProject(id: project.id, expectedUpdatedAt: project.updatedAt) {
            result = $0
        }

        guard case .failure(.artifactCleanup) = result else {
            return XCTFail("expected promoted artifact rollback failure, got \(String(describing: result))")
        }
        XCTAssertEqual(service.loadUnifiedSceneProject(named: project.name)?.0, project)
        XCTAssertEqual(try Data(contentsOf: promotedArtifact), promotedData)
        XCTAssertEqual(try Data(contentsOf: siblingArtifact), siblingData)
        XCTAssertEqual(try Data(contentsOf: pendingArtifact), pendingData)
    }

    func testTypedDeleteRollsBackMetadataWhenArtifactCommitFailsPartway() throws {
        let store = try RecordingArtifactStore()
        let service = DBService(recordingArtifactStore: store)
        let project = try service.createUnifiedSceneProject(named: "delete-partial-artifact-\(UUID().uuidString)")
        let recordingIDs = [UUID(), UUID()]
        let references = recordingIDs.map { recordingID in
            SceneRecordingReference(
                recordingID: recordingID,
                relativePath: "Recordings/Projects/\(project.id.uuidString)/\(recordingID.uuidString).mov"
            )
        }
        var enriched = project
        enriched.sceneDescription = "partial artifact rollback"
        enriched.recordingReferences = references
        try service.saveUnifiedSceneProject(enriched, worldMap: nil)

        let projectArtifactsURL = store.projectsDirectoryURL
            .appendingPathComponent(project.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectArtifactsURL, withIntermediateDirectories: true)
        let artifactData = [Data("first partial artifact".utf8), Data("second partial artifact".utf8)]
        let artifactURLs = zip(recordingIDs, artifactData).map { recordingID, data in
            let url = projectArtifactsURL.appendingPathComponent("\(recordingID.uuidString).mov")
            XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: data))
            return url
        }

        let documentsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let mapURL = documentsURL
            .appendingPathComponent("UnifiedSceneProjects", isDirectory: true)
            .appendingPathComponent("\(project.id.uuidString)_worldmap")
        let projectURL = documentsURL
            .appendingPathComponent("UnifiedSceneProjects", isDirectory: true)
            .appendingPathComponent("\(project.id.uuidString)_project.json")
        let mapData = Data("partial rollback world map".utf8)
        try mapData.write(to: mapURL, options: [.atomic])
        defer {
            try? FileManager.default.removeItem(at: projectURL)
            try? FileManager.default.removeItem(at: mapURL)
            try? FileManager.default.removeItem(at: projectArtifactsURL)
        }

        store.testArtifactCommitFailureAfterUnlinks = 1
        var result: Result<Void, SETLibraryFailure>?
        service.deleteUnifiedSceneProject(id: project.id, expectedUpdatedAt: enriched.updatedAt) {
            result = $0
        }

        guard case .failure(.artifactCleanup) = result else {
            return XCTFail("expected typed artifact cleanup failure, got \(String(describing: result))")
        }
        XCTAssertEqual(service.loadUnifiedSceneProject(named: project.name)?.0, enriched)
        XCTAssertEqual(try Data(contentsOf: mapURL), mapData)
        for (url, data) in zip(artifactURLs, artifactData) {
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }

    func testTypedDeleteCompletionCanSynchronouslyReloadWithoutDeadlock() throws {
        let name = "delete-reentrant-\(UUID().uuidString)"
        let project = try dbService.createUnifiedSceneProject(named: name)
        let completion = expectation(description: "delete completion")
        var result: Result<Void, SETLibraryFailure>?

        dbService.deleteUnifiedSceneProject(id: project.id, expectedUpdatedAt: project.updatedAt) {
            result = $0
            // This was a queue re-entrancy deadlock before the completion was
            // moved outside persistenceQueue.sync.
            _ = self.dbService.loadLibrarySceneSnapshots()
            completion.fulfill()
        }

        wait(for: [completion], timeout: 2)
        guard case .success = result else {
            return XCTFail("expected successful typed delete, got \(String(describing: result))")
        }
        XCTAssertNil(dbService.loadUnifiedSceneProject(named: name))
    }

    func testStagedDeleteRollsBackAfterWorldMapFailure() throws {
        try assertStagedDeleteRollsBack(after: .afterWorldMapRemoval)
    }

    func testStagedDeleteRollsBackAfterProjectFailure() throws {
        try assertStagedDeleteRollsBack(after: .afterProjectRemoval)
    }

    func testMissingStoredFileIsAnInitialWriteNotAConflict() throws {
        let project = UnifiedSceneProject(name: "fresh-project")

        try dbService.saveUnifiedSceneProject(
            project,
            worldMap: nil,
            expectedUpdatedAt: project.updatedAt
        )

        let stored = try XCTUnwrap(dbService.loadUnifiedSceneProject(named: "fresh-project"))
        XCTAssertEqual(stored.0.id, project.id)
    }

    // MARK: - Serialization invariants under overlapping saves

    func testOverlappingSavesAlwaysLeaveOneDecodableProject() throws {
        let project = try dbService.createUnifiedSceneProject(named: "overlap-project")

        let submitted = concurrentPerform(16) { index in
            var snapshot = project
            snapshot.sceneDescription = "write-\(index)"
            snapshot.updatedAt = Date(timeIntervalSince1970: Double(10_000 + index))
            try? self.dbService.saveUnifiedSceneProject(snapshot, worldMap: nil)
            return snapshot
        }

        let stored = try XCTUnwrap(dbService.loadUnifiedSceneProject(named: "overlap-project"))
        XCTAssertTrue(
            submitted.contains { $0.updatedAt == stored.0.updatedAt && $0.sceneDescription == stored.0.sceneDescription },
            "stored project must be exactly one of the submitted snapshots, got \(stored.0.sceneDescription)"
        )
        XCTAssertEqual(dbService.listUnifiedSceneProjects().count, 1)
    }

    // MARK: - Legacy path smoke under the shared queue

    func testLegacySceneSaveAndLoadStayConsistentUnderConcurrency() throws {
        concurrentPerform(2) { index in
            let scene = SceneData(name: "legacy-\(index)", actors: nil, script: "")
            try? self.dbService.saveLegacyScene(mapData: Data("map".utf8), sceneData: scene)
        }

        for index in 0..<2 {
            let loaded = dbService.loadSceneData(sceneName: "legacy-\(index)")
            XCTAssertNotNil(loaded, "legacy scene \(index) must survive concurrent writes")
        }
    }

    func testColdRecoverySavesRenamedMovieReferenceWithoutChangingProjectOrMapPayload() async throws {
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-reference-cold-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupportURL) }
        let store = try RecordingArtifactStore(applicationSupportDirectoryURL: applicationSupportURL)
        let service = DBService(recordingArtifactStore: store, projectLeases: ProjectLifecycleRegistry())
        var project = try service.createUnifiedSceneProject(named: "camera-cold-\(UUID().uuidString)")
        defer { service.deleteUnifiedSceneProject(named: project.name) { _ in } }
        project.sceneDescription = "latest scene description must survive recovery"
        project.updatedAt = Date(timeIntervalSince1970: 4_000)
        let projectURL = try unifiedProjectURL(projectID: project.id)
        let mapBytes = Data("opaque archived world-map bytes must remain byte-identical".utf8)
        let projectObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(project))
        try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "project": projectObject,
            "archivedWorldMap": mapBytes.base64EncodedString()
        ]).write(to: projectURL, options: [.atomic])

        let recordingID = UUID()
        let pendingURL = try store.makePendingURL(recordingID: recordingID)
        try await makeValidMovie(at: pendingURL, recordingID: recordingID)
        let movieBytes = try Data(contentsOf: pendingURL)
        let artifact = RecordingArtifact(
            id: RecordingID(rawValue: recordingID), localURL: pendingURL,
            duration: 0.1, hasAudio: false
        )
        store.testPromotionFaultPoint = .afterRename
        XCTAssertThrowsError(try store.promoteFinalizedArtifact(
            artifact, projectID: project.id, expectedProjectUpdatedAt: project.updatedAt
        ))
        XCTAssertEqual(try store.journal.entry(for: recordingID)?.state, .promoting)

        let siblingID = UUID()
        let siblingURL = try store.makePendingURL(recordingID: siblingID)
        try await makeValidMovie(at: siblingURL, recordingID: siblingID)
        _ = try store.promoteFinalizedArtifact(RecordingArtifact(
            id: RecordingID(rawValue: siblingID), localURL: siblingURL,
            duration: 0.1, hasAudio: false
        ), projectID: project.id, expectedProjectUpdatedAt: project.updatedAt)

        // No in-memory descriptor/reference is passed into the new owners.
        let reopenedStore = try RecordingArtifactStore(applicationSupportDirectoryURL: applicationSupportURL)
        let reopenedDB = DBService(recordingArtifactStore: reopenedStore, projectLeases: ProjectLifecycleRegistry())
        reopenedDB.performRecordingMaintenance()
        let savedBytes = try Data(contentsOf: projectURL)
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: savedBytes) as? [String: Any])
        let savedProjectObject = try XCTUnwrap(envelope["project"])
        let recovered = try JSONDecoder().decode(
            UnifiedSceneProject.self,
            from: JSONSerialization.data(withJSONObject: savedProjectObject)
        )
        XCTAssertEqual(recovered.id, project.id)
        XCTAssertEqual(recovered.name, project.name)
        XCTAssertEqual(recovered.sceneDescription, project.sceneDescription)
        XCTAssertEqual(envelope["archivedWorldMap"] as? String, mapBytes.base64EncodedString())
        XCTAssertEqual(recovered.recordingReferences.count, 2, "same-generation takes must commit in one recovery snapshot")
        let reference = try XCTUnwrap(recovered.recordingReferences.first(where: { $0.recordingID == recordingID }))
        XCTAssertEqual(reference.recordingID, recordingID)
        let destination = try XCTUnwrap(reopenedStore.resolve(reference, ownedBy: project.id))
        XCTAssertEqual(try Data(contentsOf: destination), movieBytes)
        XCTAssertNil(try reopenedStore.journal.entry(for: recordingID))
        XCTAssertNil(try reopenedStore.journal.entry(for: siblingID))
        XCTAssertEqual(
            reopenedDB.loadLibrarySceneSnapshots().successValue?.first(where: { $0.id == project.id })?.artifactHealth,
            .healthy
        )

        reopenedDB.performRecordingMaintenance()
        XCTAssertEqual(try Data(contentsOf: projectURL), savedBytes, "an acknowledged take must not append or reorder again")
    }

    func testSnapshotConflictKeepsPromotionAndAcknowledgementRetryKeepsCommittedSnapshot() async throws {
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-reference-conflict-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupportURL) }
        let store = try RecordingArtifactStore(applicationSupportDirectoryURL: applicationSupportURL)
        let service = DBService(recordingArtifactStore: store, projectLeases: ProjectLifecycleRegistry())
        let project = try service.createUnifiedSceneProject(named: "camera-conflict-\(UUID().uuidString)")
        defer { service.deleteUnifiedSceneProject(named: project.name) { _ in } }
        let recordingID = UUID()
        let pendingURL = try store.makePendingURL(recordingID: recordingID)
        try await makeValidMovie(at: pendingURL, recordingID: recordingID)
        let reference = try store.promoteFinalizedArtifact(RecordingArtifact(
            id: RecordingID(rawValue: recordingID), localURL: pendingURL,
            duration: 0.1, hasAudio: false
        ), projectID: project.id)
        var latest = project
        latest.sceneDescription = "newer user edit"
        latest.updatedAt = project.updatedAt.addingTimeInterval(10)
        try service.saveUnifiedSceneProject(latest, worldMap: nil, expectedUpdatedAt: project.updatedAt)

        var stale = project
        stale.recordingReferences = [reference]
        stale.updatedAt = latest.updatedAt.addingTimeInterval(10)
        XCTAssertThrowsError(try service.saveUnifiedSceneProject(stale, worldMap: nil, expectedUpdatedAt: project.updatedAt)) { error in
            XCTAssertEqual(error as? DBServiceError, .staleSnapshot(storedUpdatedAt: latest.updatedAt))
        }
        XCTAssertEqual(try store.journal.entry(for: recordingID)?.state, .promoted)
        XCTAssertEqual(service.loadUnifiedSceneProject(named: project.name)?.0, latest)

        // Retry with the current aggregate. A journal unlink failure happens
        // after JSON commit and must not turn that successful save into failure.
        latest.recordingReferences = [reference]
        let expectedUpdatedAt = latest.updatedAt
        latest.updatedAt = latest.updatedAt.addingTimeInterval(20)
        store.testPromotionFaultPoint = .beforeJournalRemoval
        XCTAssertNoThrow(try service.saveUnifiedSceneProject(latest, worldMap: nil, expectedUpdatedAt: expectedUpdatedAt))
        XCTAssertEqual(try store.journal.entry(for: recordingID)?.state, .promoted)
        let projectURL = try unifiedProjectURL(projectID: project.id)
        let committedBytes = try Data(contentsOf: projectURL)

        let reopenedStore = try RecordingArtifactStore(applicationSupportDirectoryURL: applicationSupportURL)
        let reopenedDB = DBService(recordingArtifactStore: reopenedStore, projectLeases: ProjectLifecycleRegistry())
        reopenedDB.performRecordingMaintenance()
        XCTAssertNil(try reopenedStore.journal.entry(for: recordingID))
        XCTAssertEqual(try Data(contentsOf: projectURL), committedBytes, "acknowledgement-only recovery must not mutate the aggregate")
        XCTAssertEqual(reopenedDB.loadUnifiedSceneProject(named: project.name)?.0, latest)
    }

    func testColdRecoveryDoesNotReattachIntentionallyDetachedReference() async throws {
        let fixture = try await makeVersionBoundRecoveryFixture()
        defer { cleanupRecoveryFixture(fixture) }
        var attached = fixture.project
        attached.recordingReferences = [fixture.reference]
        attached.updatedAt = fixture.project.updatedAt.addingTimeInterval(10)
        fixture.store.testPromotionFaultPoint = .beforeJournalRemoval
        try fixture.service.saveUnifiedSceneProject(attached, worldMap: nil, expectedUpdatedAt: fixture.project.updatedAt)
        XCTAssertNotNil(try fixture.store.journal.entry(for: fixture.reference.recordingID))

        var detached = attached
        detached.recordingReferences = []
        detached.updatedAt = attached.updatedAt.addingTimeInterval(10)
        try fixture.service.saveUnifiedSceneProject(detached, worldMap: nil, expectedUpdatedAt: attached.updatedAt)
        let projectURL = try unifiedProjectURL(projectID: detached.id)
        let bytesBeforeRecovery = try Data(contentsOf: projectURL)
        fixture.service.performRecordingMaintenance()

        XCTAssertEqual(try Data(contentsOf: projectURL), bytesBeforeRecovery)
        XCTAssertEqual(fixture.service.loadUnifiedSceneProject(named: detached.name)?.0.recordingReferences, [])
        XCTAssertEqual(try fixture.store.journal.entry(for: fixture.reference.recordingID)?.state, .promoted)
        XCTAssertNotNil(fixture.store.resolve(fixture.reference, ownedBy: detached.id))
    }

    func testColdRecoveryDefersWhenProjectGenerationWasModifiedAfterPromotion() async throws {
        let fixture = try await makeVersionBoundRecoveryFixture()
        defer { cleanupRecoveryFixture(fixture) }
        var modified = fixture.project
        modified.sceneDescription = "a later user edit"
        modified.updatedAt = fixture.project.updatedAt.addingTimeInterval(10)
        try fixture.service.saveUnifiedSceneProject(modified, worldMap: nil, expectedUpdatedAt: fixture.project.updatedAt)
        let projectURL = try unifiedProjectURL(projectID: modified.id)
        let bytesBeforeRecovery = try Data(contentsOf: projectURL)
        fixture.service.performRecordingMaintenance()

        XCTAssertEqual(try Data(contentsOf: projectURL), bytesBeforeRecovery)
        XCTAssertEqual(fixture.service.loadUnifiedSceneProject(named: modified.name)?.0, modified)
        XCTAssertEqual(try fixture.store.journal.entry(for: fixture.reference.recordingID)?.expectedProjectUpdatedAt, fixture.project.updatedAt)
        XCTAssertNotNil(fixture.store.resolve(fixture.reference, ownedBy: modified.id))
    }

    func testColdRecoveryKeepsLegacyUnversionedIntentUntilExplicitReferenceSave() async throws {
        let fixture = try await makeVersionBoundRecoveryFixture(bindGeneration: false)
        defer { cleanupRecoveryFixture(fixture) }
        let journalURL = fixture.store.journal.journalDirectoryURL
            .appendingPathComponent("\(fixture.reference.recordingID.uuidString).json")
        let legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: journalURL)) as? [String: Any])
        XCTAssertNil(legacyObject["expectedProjectUpdatedAt"], "old journal bytes have no generation field")
        let projectURL = try unifiedProjectURL(projectID: fixture.project.id)
        let bytesBeforeRecovery = try Data(contentsOf: projectURL)
        fixture.service.performRecordingMaintenance()
        XCTAssertEqual(try Data(contentsOf: projectURL), bytesBeforeRecovery)
        XCTAssertNotNil(try fixture.store.journal.entry(for: fixture.reference.recordingID))
        XCTAssertNotNil(fixture.store.resolve(fixture.reference, ownedBy: fixture.project.id))

        // A live owner's explicit save is authority to attach this user-held
        // take; automatic cold recovery must not invent that decision.
        var explicit = fixture.project
        explicit.recordingReferences = [fixture.reference]
        explicit.updatedAt = explicit.updatedAt.addingTimeInterval(10)
        try fixture.service.saveUnifiedSceneProject(explicit, worldMap: nil, expectedUpdatedAt: fixture.project.updatedAt)
        XCTAssertNil(try fixture.store.journal.entry(for: fixture.reference.recordingID))
    }

    func testColdRecoveryDoesNotRecreateDeletedProjectFromRetainedIntent() async throws {
        let fixture = try await makeVersionBoundRecoveryFixture()
        defer { cleanupRecoveryFixture(fixture) }
        let projectURL = try unifiedProjectURL(projectID: fixture.project.id)
        let movieURL = try XCTUnwrap(fixture.store.resolve(fixture.reference, ownedBy: fixture.project.id))
        let movieBytes = try Data(contentsOf: movieURL)
        // Represents a stale promotion intent after authoritative metadata was
        // removed; recovery is not allowed to infer a replacement project.
        try FileManager.default.removeItem(at: projectURL)
        fixture.service.performRecordingMaintenance()
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectURL.path))
        XCTAssertFalse(fixture.service.listUnifiedSceneProjects().contains(where: { $0.id == fixture.project.id }))
        XCTAssertNotNil(try fixture.store.journal.entry(for: fixture.reference.recordingID))
        XCTAssertEqual(try Data(contentsOf: movieURL), movieBytes)
    }

    // MARK: - Helpers

    private struct RecoveryFixture {
        let root: URL
        let store: RecordingArtifactStore
        let service: DBService
        let project: UnifiedSceneProject
        let reference: SceneRecordingReference
    }

    private func makeVersionBoundRecoveryFixture(bindGeneration: Bool = true) async throws -> RecoveryFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-generation-\(UUID().uuidString)", isDirectory: true)
        let store = try RecordingArtifactStore(applicationSupportDirectoryURL: root)
        let service = DBService(recordingArtifactStore: store, projectLeases: ProjectLifecycleRegistry())
        let project = try service.createUnifiedSceneProject(named: "recording-generation-\(UUID().uuidString)")
        let recordingID = UUID()
        let url = try store.makePendingURL(recordingID: recordingID)
        try await makeValidMovie(at: url, recordingID: recordingID)
        let reference = try store.promoteFinalizedArtifact(RecordingArtifact(
            id: RecordingID(rawValue: recordingID), localURL: url, duration: 0.1, hasAudio: false
        ), projectID: project.id, expectedProjectUpdatedAt: bindGeneration ? project.updatedAt : nil)
        return RecoveryFixture(root: root, store: store, service: service, project: project, reference: reference)
    }

    private func cleanupRecoveryFixture(_ fixture: RecoveryFixture) {
        fixture.service.deleteUnifiedSceneProject(named: fixture.project.name) { _ in }
        try? FileManager.default.removeItem(at: fixture.root)
    }

    private func unifiedProjectURL(projectID: UUID) throws -> URL {
        try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        ).appendingPathComponent("UnifiedSceneProjects", isDirectory: true)
            .appendingPathComponent("\(projectID.uuidString)_project.json")
    }

    private func makeValidMovie(at outputURL: URL, recordingID: UUID) async throws {
        let configuration = RecordingConfiguration(
            id: RecordingID(rawValue: recordingID),
            outputURL: outputURL,
            width: 320,
            height: 240,
            fps: 30,
            audioMode: .disabled
        )
        let writer = try AVAssetWriterRecordingWriterFactory().makeWriter(for: configuration)
        guard writer.start() else {
            throw NSError(domain: "DBServiceConcurrencyTests", code: 1)
        }
        for index in 0..<3 {
            let pixelBuffer = try makePixelBuffer(width: configuration.width, height: configuration.height)
            let disposition = writer.appendVideo(RecordingVideoFrame(
                recordingID: configuration.id,
                generation: 1,
                timestamp: 10.0 + (Double(index) / Double(configuration.fps)),
                payload: AppleRecordingVideoFramePayload(pixelBuffer: pixelBuffer)
            ))
            guard disposition == .appended else {
                writer.discard()
                throw NSError(domain: "DBServiceConcurrencyTests", code: 2)
            }
        }

        let finishExpectation = expectation(description: "valid movie finished")
        var finishResult: Result<RecordingWriterFinish, RecordingWriterError>?
        writer.finishWriting { result in
            finishResult = result
            finishExpectation.fulfill()
        }
        await fulfillment(of: [finishExpectation], timeout: 10)
        guard case .success = finishResult else {
            throw NSError(domain: "DBServiceConcurrencyTests", code: 3)
        }
    }

    private func makePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw NSError(domain: "DBServiceConcurrencyTests", code: Int(status))
        }
        return pixelBuffer
    }

    private func assertStagedDeleteRollsBack(
        after failurePoint: DBService.TestDeletionFailurePoint
    ) throws {
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scene-db-rollback-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupportURL) }

        let store = try RecordingArtifactStore(
            applicationSupportDirectoryURL: applicationSupportURL
        )
        let service = DBService(recordingArtifactStore: store)
        let name = "rollback-\(UUID().uuidString)"
        let project = try service.createUnifiedSceneProject(named: name)
        let recordingID = UUID()
        let reference = SceneRecordingReference(
            recordingID: recordingID,
            relativePath: "Recordings/Projects/\(project.id.uuidString)/\(recordingID.uuidString).mov"
        )
        var enriched = project
        enriched.sceneDescription = "rollback aggregate"
        enriched.recordingReferences = [reference]
        try service.saveUnifiedSceneProject(enriched, worldMap: nil)

        let projectArtifactsURL = store.projectsDirectoryURL
            .appendingPathComponent(project.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: projectArtifactsURL, withIntermediateDirectories: true)
        let artifactURL = projectArtifactsURL.appendingPathComponent("\(recordingID.uuidString).mov")
        let artifactData = Data("rollback artifact".utf8)
        XCTAssertTrue(FileManager.default.createFile(atPath: artifactURL.path, contents: artifactData))

        let documentsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let mapURL = documentsURL
            .appendingPathComponent("UnifiedSceneProjects", isDirectory: true)
            .appendingPathComponent("\(project.id.uuidString)_worldmap")
        let projectURL = documentsURL
            .appendingPathComponent("UnifiedSceneProjects", isDirectory: true)
            .appendingPathComponent("\(project.id.uuidString)_project.json")
        defer {
            try? FileManager.default.removeItem(at: projectURL)
            try? FileManager.default.removeItem(at: mapURL)
        }
        let mapData = Data("rollback world map".utf8)
        try mapData.write(to: mapURL, options: [.atomic])

        service.testDeletionFailurePoint = failurePoint
        var result: Result<Void, SETLibraryFailure>?
        service.deleteUnifiedSceneProject(id: project.id, expectedUpdatedAt: enriched.updatedAt) {
            result = $0
        }

        guard case .failure(.persistence) = result else {
            return XCTFail("expected persistence failure, got \(String(describing: result))")
        }
        XCTAssertEqual(service.loadUnifiedSceneProject(named: name)?.0, enriched)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactURL.path))
        XCTAssertEqual(try Data(contentsOf: artifactURL), artifactData)
        XCTAssertEqual(try Data(contentsOf: mapURL), mapData)
    }

    /// Runs `body` on `iterations` parallel threads and collects the returned
    /// values (lock-guarded: concurrent Array writes are not data-race-free).
    private final class ResultBox<T> {
        private let lock = NSLock()
        private var storage: [T?] = []

        init(count: Int) {
            storage = [T?](repeating: nil, count: count)
        }

        func set(_ value: T?, at index: Int) {
            lock.lock()
            storage[index] = value
            lock.unlock()
        }

        var values: [T] {
            lock.lock()
            defer { lock.unlock() }
            return storage.compactMap { $0 }
        }
    }

    private func concurrentPerform<T>(_ iterations: Int, _ body: @escaping (Int) -> T) -> [T] {
        let box = ResultBox<T>(count: iterations)
        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            box.set(body(index), at: index)
        }
        return box.values
    }
}

private extension Result {
    var successValue: Success? {
        guard case .success(let value) = self else { return nil }
        return value
    }
}
