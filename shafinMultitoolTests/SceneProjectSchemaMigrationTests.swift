//
//  SceneProjectSchemaMigrationTests.swift
//  shafinMultitoolTests
//
//  M5-002: the project envelope is versioned by DBService. Legacy records are
//  read-only until a legitimate save, while malformed and future records stay
//  isolated from healthy projects.
//

import XCTest
@testable import shafinMultitool

final class SceneProjectSchemaMigrationTests: XCTestCase {

    private var dbService: DBService!
    private var ownedProjectURLs: [URL] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbService = DBService()
        ownedProjectURLs = []
    }

    override func tearDownWithError() throws {
        for projectURL in ownedProjectURLs {
            try? FileManager.default.removeItem(at: projectURL)
            try? FileManager.default.removeItem(at: worldMapURL(for: projectURL))
        }
        ownedProjectURLs = []
        dbService = nil
        try super.tearDownWithError()
    }

    func testRawLegacyProjectRemainsByteIdenticalUntilSaveThenMigratesToV1() throws {
        let project = fixtureProject(name: "legacy-raw-" + UUID().uuidString)
        let projectURL = try writeRaw(project)
        let originalBytes = try Data(contentsOf: projectURL)

        XCTAssertEqual(dbService.loadUnifiedSceneProject(named: project.name)?.0, project)
        XCTAssertEqual(try Data(contentsOf: projectURL), originalBytes, "a read must not rewrite v0")

        var updated = project
        updated.sceneDescription = "migrated raw project"
        try dbService.saveUnifiedSceneProject(updated, worldMap: nil)

        let savedObject = try jsonObject(at: projectURL)
        XCTAssertEqual(savedObject["schemaVersion"] as? Int, 1)
        XCTAssertEqual(try jsonData(savedObject["project"]), try jsonData(jsonObject(for: updated)))
        XCTAssertNil(savedObject["id"], "the v1 envelope owns the project payload")
        XCTAssertEqual(dbService.loadUnifiedSceneProject(named: updated.name)?.0, updated)
    }

    func testUnversionedEnvelopeRemainsByteIdenticalUntilSaveThenMigratesToV1() throws {
        let project = fixtureProject(name: "legacy-envelope-" + UUID().uuidString)
        let projectURL = try writeEnvelope(project: project, schemaVersion: nil, includeUnknownField: false)
        let originalBytes = try Data(contentsOf: projectURL)

        XCTAssertEqual(dbService.loadUnifiedSceneProject(named: project.name)?.0, project)
        XCTAssertEqual(try Data(contentsOf: projectURL), originalBytes, "a read must not rewrite v0")

        var updated = project
        updated.sceneDescription = "migrated envelope project"
        try dbService.saveUnifiedSceneProject(updated, worldMap: nil)

        let savedObject = try jsonObject(at: projectURL)
        XCTAssertEqual(savedObject["schemaVersion"] as? Int, 1)
        XCTAssertEqual(try jsonData(savedObject["project"]), try jsonData(jsonObject(for: updated)))
        XCTAssertEqual(dbService.loadUnifiedSceneProject(named: updated.name)?.0, updated)
    }

    func testNewSaveIsV1AndRoundTripsAllSceneAggregateData() throws {
        let project = fixtureProject(name: "current-" + UUID().uuidString)

        try dbService.saveUnifiedSceneProject(project, worldMap: nil)

        let projectURL = try projectURL(for: project.id)
        let savedObject = try jsonObject(at: projectURL)
        XCTAssertEqual(savedObject["schemaVersion"] as? Int, 1)
        XCTAssertEqual(dbService.loadUnifiedSceneProject(named: project.name)?.0, project)
    }

    func testFutureVersionWithUnknownFieldsFailsClosedAndDoesNotMutateHealthyRecords() throws {
        let healthy = fixtureProject(name: "healthy-" + UUID().uuidString)
        try dbService.saveUnifiedSceneProject(healthy, worldMap: nil)

        let future = fixtureProject(name: "future-" + UUID().uuidString)
        let futureURL = try writeEnvelope(project: future, schemaVersion: 2, includeUnknownField: true)
        let originalBytes = try Data(contentsOf: futureURL)

        XCTAssertNil(dbService.loadUnifiedSceneProject(named: future.name))
        XCTAssertFalse(dbService.listUnifiedSceneProjects().contains { $0.id == future.id })
        XCTAssertTrue(dbService.listUnifiedSceneProjects().contains { $0.id == healthy.id })

        var replacement = future
        replacement.sceneDescription = "attempted downgrade"
        XCTAssertThrowsError(try dbService.saveUnifiedSceneProject(replacement, worldMap: nil))
        XCTAssertEqual(try Data(contentsOf: futureURL), originalBytes)

        var deleted: Bool?
        dbService.deleteUnifiedSceneProject(named: future.name) { deleted = $0 }
        XCTAssertEqual(deleted, false)
        XCTAssertEqual(try Data(contentsOf: futureURL), originalBytes)
        XCTAssertEqual(dbService.loadUnifiedSceneProject(named: healthy.name)?.0, healthy)
    }

    func testNegativeMalformedAndVersionedRawRecordsFailClosedWithoutFallback() throws {
        let fixtures: [(label: String, value: Any)] = [
            ("negative", -1),
            ("fractional", 1.5),
            ("string", "1"),
            ("null", NSNull())
        ]

        for fixture in fixtures {
            let project = fixtureProject(name: "invalid-" + fixture.label + "-" + UUID().uuidString)
            let projectURL = try writeEnvelope(project: project, schemaVersionValue: fixture.value)
            let originalBytes = try Data(contentsOf: projectURL)

            XCTAssertNil(dbService.loadUnifiedSceneProject(named: project.name), fixture.label)
            XCTAssertFalse(dbService.listUnifiedSceneProjects().contains { $0.id == project.id }, fixture.label)

            var deleted: Bool?
            dbService.deleteUnifiedSceneProject(named: project.name) { deleted = $0 }
            XCTAssertEqual(deleted, false, fixture.label)
            XCTAssertEqual(try Data(contentsOf: projectURL), originalBytes, fixture.label)
        }

        let rawProject = fixtureProject(name: "versioned-raw-" + UUID().uuidString)
        let rawURL = try writeRaw(rawProject, addingSchemaVersion: 2)
        XCTAssertNil(dbService.loadUnifiedSceneProject(named: rawProject.name))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rawURL.path))
    }

    func testInvalidRecordingReferenceCannotOverwriteExistingV1Bytes() throws {
        let project = fixtureProject(name: "unsafe-reference-" + UUID().uuidString)
        try dbService.saveUnifiedSceneProject(project, worldMap: nil)
        let projectURL = try projectURL(for: project.id)
        let originalBytes = try Data(contentsOf: projectURL)

        var invalid = project
        invalid.recordingReferences = [
            SceneRecordingReference(recordingID: UUID(), relativePath: "Recordings/../outside.mov")
        ]

        XCTAssertThrowsError(try dbService.saveUnifiedSceneProject(invalid, worldMap: nil))
        XCTAssertEqual(try Data(contentsOf: projectURL), originalBytes)
        XCTAssertEqual(dbService.loadUnifiedSceneProject(named: project.name)?.0, project)
    }

    // MARK: - Fixtures

    private func fixtureProject(name: String) -> UnifiedSceneProject {
        let projectID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let marker = MarkedObject(name: "стол", position: Position3D(x: 1, y: 0, z: -2))
        let script = SceneScript(
            sceneHeading: "INT. КОМНАТА",
            locationName: "комната",
            interiorExterior: "INT",
            timeOfDay: "DAY",
            actors: [],
            objects: [],
            beats: [],
            spatialRelations: [],
            originalDescription: "Актёр подходит к столу."
        )
        let plannedScene = PlannedScene(placedActors: [], placedObjects: [])
        let chunkState = SceneChunkState(
            sceneID: projectID.uuidString,
            sceneHeading: "INT. КОМНАТА",
            locationName: "комната",
            knownActors: ["actor_1": "герой"],
            knownObjects: ["object_1": "стол"],
            previousChunkSummary: "вход",
            lastActorPositions: ["actor_1": "у двери"]
        )
        let overlay = SceneVisualOverlay(
            id: "overlay-1",
            kind: .stageNote,
            text: "тише",
            sceneID: projectID.uuidString,
            sourceRange: ScriptOffsetRange(start: 0, end: 3),
            displayOrder: 1,
            beatID: nil
        )
        let recording = SceneRecordingReference(
            recordingID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            relativePath: "Recordings/Projects/" + projectID.uuidString + "/11111111-1111-1111-1111-111111111111.mov",
            duration: 12.5,
            hasAudio: true
        )

        return UnifiedSceneProject(
            id: projectID,
            name: name,
            createdAt: createdAt,
            updatedAt: createdAt.addingTimeInterval(60),
            sceneDescription: "Актёр подходит к столу.",
            markedObjects: [marker],
            parsedScript: script,
            plannedScene: plannedScene,
            sceneChunkState: chunkState,
            visualOverlays: [overlay],
            recordingReferences: [recording]
        )
    }

    private func documentsDirectoryURL() throws -> URL {
        try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
    }

    private func projectsDirectoryURL() throws -> URL {
        try documentsDirectoryURL().appendingPathComponent("UnifiedSceneProjects", isDirectory: true)
    }

    private func projectURL(for id: UUID) throws -> URL {
        try projectsDirectoryURL().appendingPathComponent(id.uuidString + "_project.json")
    }

    private func worldMapURL(for projectURL: URL) -> URL {
        projectURL.deletingLastPathComponent().appendingPathComponent(
            projectURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_project", with: "_worldmap")
        )
    }

    @discardableResult
    private func writeRaw(_ project: UnifiedSceneProject, addingSchemaVersion: Int? = nil) throws -> URL {
        var object = try jsonObject(for: project)
        if let addingSchemaVersion {
            object["schemaVersion"] = addingSchemaVersion
        }
        let url = try projectURL(for: project.id)
        try write(object, to: url)
        ownedProjectURLs.append(url)
        return url
    }

    @discardableResult
    private func writeEnvelope(
        project: UnifiedSceneProject,
        schemaVersion: Int?,
        includeUnknownField: Bool
    ) throws -> URL {
        var object: [String: Any] = [
            "project": try jsonObject(for: project),
            "archivedWorldMap": NSNull()
        ]
        if let schemaVersion {
            object["schemaVersion"] = schemaVersion
        }
        if includeUnknownField {
            object["futureOnlyField"] = ["mustNot": "decode"]
        }
        let url = try projectURL(for: project.id)
        try write(object, to: url)
        ownedProjectURLs.append(url)
        return url
    }

    private func writeEnvelope(project: UnifiedSceneProject, schemaVersionValue: Any) throws -> URL {
        var object: [String: Any] = [
            "project": try jsonObject(for: project),
            "schemaVersion": schemaVersionValue
        ]
        let url = try projectURL(for: project.id)
        try write(object, to: url)
        ownedProjectURLs.append(url)
        return url
    }

    private func write(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url, options: [.atomic])
    }

    private func jsonObject(for project: UnifiedSceneProject) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(project),
                options: []
            ) as? [String: Any]
        )
    }

    private func jsonObject(at url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url), options: []) as? [String: Any])
    }

    private func jsonData(_ object: Any?) throws -> Data {
        let value = try XCTUnwrap(object)
        return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
}
