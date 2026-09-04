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
        // Completion callbacks run synchronously inside the persistence queue,
        // so this cleanup needs no expectations.
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
