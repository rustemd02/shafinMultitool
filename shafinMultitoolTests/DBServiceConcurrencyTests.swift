//
//  DBServiceConcurrencyTests.swift
//  shafinMultitoolTests
//
//  M1-015 PersistenceOwner: file persistence is serialized on one queue and
//  optimistic conflicts (stale snapshots) produce a typed recoverable error
//  without overwriting the stored write.
//

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

    // MARK: - Helpers

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
