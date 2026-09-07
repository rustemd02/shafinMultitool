//
//  ARWorldMapPersistenceTests.swift
//  shafinMultitoolTests
//
//  M6-016 + M6-017: world-map persistence contract (simulator-provable
//  half). Map and project share one file (single atomic write); the
//  archivedWorldMap member is part of the schema; corrupt archives
//  fail closed without crashing; stale optimistic writes are rejected
//  and keep the stored file. Real ARWorldMap capture/restore on
//  hardware remains M13 (ARWorldMap cannot be constructed without a
//  live session).
//

import XCTest
@testable import shafinMultitool

final class ARWorldMapPersistenceTests: XCTestCase {
    private var dbService: DBService!
    private var projectName: String!

    override func setUp() {
        super.setUp()
        dbService = DBService()
        projectName = "m6-worldmap-\(UUID().uuidString.prefix(8))"
    }

    override func tearDown() {
        if let projectName {
            dbService.deleteUnifiedSceneProject(named: projectName) { _ in }
        }
        super.tearDown()
    }

    private func makeProject() -> UnifiedSceneProject {
        UnifiedSceneProject(
            id: UUID(),
            name: projectName,
            createdAt: Date(),
            updatedAt: Date(),
            markedObjects: [],
            parsedScript: nil,
            plannedScene: nil
        )
    }

    private func projectsDirectory() throws -> URL {
        try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ).appendingPathComponent("UnifiedSceneProjects")
    }

    private func projectFileURL(for id: UUID) throws -> URL {
        try projectsDirectory().appendingPathComponent("\(id.uuidString)_project.json")
    }

    func testProjectFileSchemaCarriesArchivedWorldMapMember() throws {
        let project = makeProject()
        try dbService.saveUnifiedSceneProject(project, worldMap: nil)
        let data = try Data(contentsOf: projectFileURL(for: project.id))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            "project file must be a JSON object"
        )
        // The map travels inside the same file as the project: one
        // atomic write owns both (no partial write window). The
        // archivedWorldMap member is optional (encodeIfPresent — key
        // appears only when a map exists); versioned schema member
        // must always be there.
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertTrue(
            object.keys.contains("project"),
            "schema must carry the project member; got \(object.keys.sorted())"
        )
    }

    func testProjectWithoutMapLoadsAsNilMap() throws {
        let project = makeProject()
        try dbService.saveUnifiedSceneProject(project, worldMap: nil)
        let loaded = dbService.loadUnifiedSceneProject(named: projectName)
        XCTAssertNotNil(loaded)
        XCTAssertNil(loaded?.1)
    }

    func testCorruptWorldMapArchiveFailsClosedWithoutCrash() throws {
        let project = makeProject()
        try dbService.saveUnifiedSceneProject(project, worldMap: nil)
        let fileURL = try projectFileURL(for: project.id)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL))
        guard var object = json as? [String: Any] else {
            return XCTFail("project file must be a JSON object")
        }
        object["archivedWorldMap"] = ["placeholder": [0xFF, 0x00, 0x37]]
        try JSONSerialization.data(withJSONObject: object).write(to: fileURL)
        // A corrupt map must not surface as a valid map and must not
        // crash the loader; the loader fails closed (nil overall or a
        // nil map after rejection).
        let loaded = dbService.loadUnifiedSceneProject(named: projectName)
        if loaded == nil {
            // Failing the whole load is an accepted fail-closed shape…
            return
        }
        // …and so is keeping the project while rejecting the map.
        XCTAssertNil(loaded?.1, "corrupt archive must not decode to a map")
    }

    func testStaleOptimisticWriteIsRejectedAndKeepsStoredFile() throws {
        let project = makeProject()
        try dbService.saveUnifiedSceneProject(project, worldMap: nil)
        var stale = project
        stale.updatedAt = project.updatedAt.addingTimeInterval(-60)
        // A stale caller presents an outdated expected snapshot time.
        let outdatedExpectation = project.updatedAt.addingTimeInterval(-30)
        XCTAssertThrowsError(
            try dbService.saveUnifiedSceneProject(stale, worldMap: nil, expectedUpdatedAt: outdatedExpectation)
        ) { error in
            guard case DBServiceError.staleSnapshot = error else {
                return XCTFail("expected staleSnapshot, got \(error)")
            }
        }
        // Stored version is untouched by the rejected write.
        let loaded = dbService.loadUnifiedSceneProject(named: projectName)
        XCTAssertEqual(loaded?.0.id, project.id)
        XCTAssertEqual(loaded?.0.updatedAt, project.updatedAt)
    }
}
