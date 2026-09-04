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
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scene-db-future-artifact-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupportURL) }
        let artifactStore = try RecordingArtifactStore(
            applicationSupportDirectoryURL: applicationSupportURL
        )
        let service = DBService(recordingArtifactStore: artifactStore)

        let healthy = fixtureProject(name: "healthy-" + UUID().uuidString)
        try service.saveUnifiedSceneProject(healthy, worldMap: nil)

        var future = fixtureProject(name: "future-" + UUID().uuidString)
        let recordingID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let pendingURL = try artifactStore.makePendingURL()
        let artifactBytes = Data("future-recording".utf8)
        XCTAssertTrue(FileManager.default.createFile(atPath: pendingURL.path, contents: artifactBytes))
        let artifact = RecordingArtifact(
            id: RecordingID(rawValue: recordingID),
            localURL: pendingURL,
            duration: 9.5,
            hasAudio: true
        )
        let reference = try artifactStore.promoteFinalizedArtifact(artifact, projectID: future.id)
        future.recordingReferences = [reference]
        let artifactURL = try XCTUnwrap(artifactStore.resolve(reference))
        XCTAssertEqual(try Data(contentsOf: artifactURL), artifactBytes)

        let futureURL = try writeEnvelope(project: future, schemaVersion: 2, includeUnknownField: true)
        let originalBytes = try Data(contentsOf: futureURL)

        XCTAssertNil(service.loadUnifiedSceneProject(named: future.name))
        XCTAssertFalse(service.listUnifiedSceneProjects().contains { $0.id == future.id })
        XCTAssertTrue(service.listUnifiedSceneProjects().contains { $0.id == healthy.id })

        var replacement = future
        replacement.sceneDescription = "attempted downgrade"
        XCTAssertThrowsError(try service.saveUnifiedSceneProject(replacement, worldMap: nil))
        XCTAssertEqual(try Data(contentsOf: futureURL), originalBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactURL.path))
        XCTAssertEqual(try Data(contentsOf: artifactURL), artifactBytes)

        var deleted: Bool?
        service.deleteUnifiedSceneProject(named: future.name) { deleted = $0 }
        XCTAssertEqual(deleted, false)
        XCTAssertEqual(try Data(contentsOf: futureURL), originalBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactURL.path))
        XCTAssertEqual(try Data(contentsOf: artifactURL), artifactBytes)
        XCTAssertEqual(service.loadUnifiedSceneProject(named: healthy.name)?.0, healthy)
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

    func testUnsafeRecordingReferenceInPersistedProjectFailsClosedWithoutRewriting() throws {
        let project = fixtureProject(name: "corrupt-reference-" + UUID().uuidString)
        var object = try jsonObject(for: project)
        var references = try XCTUnwrap(object["recordingReferences"] as? [[String: Any]])
        references[0]["relativePath"] = "Recordings/../outside.mov"
        object["recordingReferences"] = references

        let projectURL = try projectURL(for: project.id)
        try write(object, to: projectURL)
        ownedProjectURLs.append(projectURL)
        let originalBytes = try Data(contentsOf: projectURL)

        XCTAssertNil(dbService.loadUnifiedSceneProject(named: project.name))
        XCTAssertFalse(dbService.listUnifiedSceneProjects().contains { $0.id == project.id })

        var deleted: Bool?
        dbService.deleteUnifiedSceneProject(named: project.name) { deleted = $0 }
        XCTAssertEqual(deleted, false)
        XCTAssertEqual(try Data(contentsOf: projectURL), originalBytes)
    }

    func testManuallyAuthoredV0GraphPreservesNestedDataThroughRawAndEnvelopeMigration() throws {
        let rawData = Data(manuallyAuthoredV0ProjectJSON.utf8)
        let expected = try JSONDecoder().decode(UnifiedSceneProject.self, from: rawData)

        XCTAssertEqual(expected.markedObjects.map(\.name), ["стол"])
        XCTAssertEqual(expected.parsedScript?.actors.map(\.id), ["actor_hero", "actor_friend"])
        XCTAssertEqual(expected.parsedScript?.objects.map(\.id), ["obj_table", "obj_window"])
        XCTAssertEqual(expected.parsedScript?.beats.map(\.id), ["beat_1", "beat_2"])
        XCTAssertEqual(expected.parsedScript?.spatialRelations.map(\.id), ["relation_1", "relation_2"])
        XCTAssertEqual(expected.plannedScene?.placedActors.first?.pathBeatIDs, ["beat_1", "beat_2"])
        XCTAssertEqual(expected.plannedScene?.placedActors.first?.path.count, 2)
        XCTAssertEqual(expected.plannedScene?.placedObjects.map(\.id), ["placed_obj_table"])
        XCTAssertEqual(expected.visualOverlays.map(\.id), ["overlay_1"])
        XCTAssertEqual(expected.sceneChunkState?.openBeatContext, "beat_2")
        XCTAssertEqual(expected.recordingReferences.map(\.recordingID.uuidString), ["DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD"])

        for envelope in [false, true] {
            let projectURL = try projectURL(for: expected.id)
            let fileData: Data
            if envelope {
                let projectObject = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: rawData, options: []) as? [String: Any]
                )
                fileData = try JSONSerialization.data(
                    withJSONObject: ["project": projectObject, "archivedWorldMap": NSNull()],
                    options: [.sortedKeys]
                )
            } else {
                fileData = rawData
            }
            try write(fileData, to: projectURL)
            ownedProjectURLs.append(projectURL)
            let originalBytes = try Data(contentsOf: projectURL)

            XCTAssertEqual(dbService.loadUnifiedSceneProject(named: expected.name)?.0, expected)
            XCTAssertEqual(try Data(contentsOf: projectURL), originalBytes)

            var updated = expected
            updated.sceneDescription = envelope ? "envelope migrated" : "raw migrated"
            try dbService.saveUnifiedSceneProject(updated, worldMap: nil)
            XCTAssertEqual(try jsonObject(at: projectURL)["schemaVersion"] as? Int, 1)
            XCTAssertEqual(dbService.loadUnifiedSceneProject(named: expected.name)?.0, updated)

            try? FileManager.default.removeItem(at: projectURL)
        }
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

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic])
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

    private let manuallyAuthoredV0ProjectJSON = """
    {
      "id": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
      "name": "manual-v0-scene",
      "createdAt": 0,
      "updatedAt": 60,
      "sceneDescription": "Герой идёт к столу и говорит с другом.",
      "markedObjects": [
        {
          "id": "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
          "name": "стол",
          "type": "table",
          "worldPosition": { "x": 1, "y": 0, "z": -2 },
          "anchorID": "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC",
          "createdAt": 1
        }
      ],
      "parsedScript": {
        "sceneHeading": "INT. КОМНАТА",
        "locationName": "комната",
        "interiorExterior": "INT",
        "timeOfDay": "DAY",
        "actors": [
          { "id": "actor_hero", "type": "human", "name": "Герой" },
          { "id": "actor_friend", "type": "human", "name": "Друг" }
        ],
        "objects": [
          {
            "id": "obj_table",
            "type": "table",
            "name": "стол",
            "detectedPosition": { "x": 1, "y": 0, "z": -2 },
            "relativePosition": "foreground"
          },
          {
            "id": "obj_window",
            "type": "window",
            "name": "окно",
            "detectedPosition": null,
            "relativePosition": "background"
          }
        ],
        "beats": [
          {
            "id": "beat_1",
            "actions": [
              {
                "id": "action_1",
                "actorId": "actor_hero",
                "type": "walk",
                "target": "obj_table",
                "direction": "forward",
                "modifier": "slowly",
                "resultingPose": "walking",
                "holdingObject": null,
                "dialogue": null,
                "fallbackText": null,
                "sourceText": "идёт к столу"
              }
            ],
            "camera": { "shotType": "wide", "movement": "tracking", "target": "actor_hero" },
            "minDuration": 2.5
          },
          {
            "id": "beat_2",
            "actions": [
              {
                "id": "action_2",
                "actorId": "actor_hero",
                "type": "talk",
                "target": "actor_friend",
                "direction": null,
                "modifier": null,
                "resultingPose": "standing",
                "holdingObject": null,
                "dialogue": "Смотри.",
                "fallbackText": null,
                "sourceText": "говорит"
              }
            ],
            "camera": { "shotType": "close_up", "movement": null, "target": "actor_hero" },
            "minDuration": 1.25
          }
        ],
        "spatialRelations": [
          { "id": "relation_1", "subject": "actor_hero", "relation": "near", "object": "obj_table" },
          { "id": "relation_2", "subject": "obj_window", "relation": "behind", "object": "actor_hero" }
        ],
        "originalDescription": "Герой идёт к столу и говорит с другом."
      },
      "plannedScene": {
        "placedActors": [
          {
            "id": "placed_actor_hero",
            "actorId": "actor_hero",
            "type": "human",
            "name": "Герой",
            "initialPosition": { "x": 0, "y": 0, "z": -1 },
            "initialRotation": 0.25,
            "path": [
              { "x": 0, "y": 0, "z": -1 },
              { "x": 1, "y": 0, "z": -2 }
            ],
            "pathDurations": [1.5],
            "pathPoses": ["standing", "walking"],
            "pathCameras": [
              { "shotType": "wide", "movement": "tracking", "target": "actor_hero" },
              null
            ],
            "pathAnnotations": [
              { "kind": "action", "text": "идёт" },
              null
            ],
            "pathBeatIDs": ["beat_1", "beat_2"]
          }
        ],
        "placedObjects": [
          {
            "id": "placed_obj_table",
            "objectId": "obj_table",
            "type": "table",
            "position": { "x": 1, "y": 0, "z": -2 },
            "rotation": 0.1,
            "isDetected": true,
            "placementSource": "detected"
          }
        ]
      },
      "sceneChunkState": {
        "sceneID": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
        "sceneHeading": "INT. КОМНАТА",
        "locationName": "комната",
        "knownActors": { "actor_hero": "Герой" },
        "knownObjects": { "obj_table": "стол" },
        "actorAliases": { "герой": "actor_hero" },
        "objectAliases": { "стол": "obj_table" },
        "speakerAliasMap": { "герой": "actor_hero" },
        "actorPoses": { "actor_hero": "walking" },
        "heldObjects": {},
        "lastResolvedSpeaker": "actor_hero",
        "previousChunkSummary": "вошёл",
        "openBeatContext": "beat_2",
        "lastActorPositions": { "actor_hero": "у стола" }
      },
      "visualOverlays": [
        {
          "id": "overlay_1",
          "kind": "stage_note",
          "text": "ТИШЕ",
          "sceneID": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
          "sourceRange": { "start": 0, "end": 4 },
          "displayOrder": 0,
          "beatID": "beat_2"
        }
      ],
      "recordingReferences": [
        {
          "recordingID": "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD",
          "relativePath": "Recordings/Projects/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA/DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD.mov",
          "duration": 12.5,
          "hasAudio": true
        }
      ]
    }
    """
}
