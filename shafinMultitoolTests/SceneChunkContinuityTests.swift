//
//  SceneChunkContinuityTests.swift
//  shafinMultitoolTests
//
//  M5-028: chunking/stitching continuity fixtures. Multi-chunk scenes
//  must preserve entity IDs, chronology, scene order, references, and
//  clarification context across chunk boundaries — injected
//  interruption at a chunk boundary must not corrupt the stitched
//  state (checkpoint payloads carry the full chunk).
//

import XCTest
@testable import shafinMultitool

final class SceneChunkContinuityTests: XCTestCase {
    private func chunk(
        sceneID: String,
        chunkID: String,
        chunkIndex: Int,
        sourceText: String,
        actors: [ScenePlanIR.Actor] = [],
        objects: [ScenePlanIR.Object] = [],
        beats: [ScenePlanIR.Beat] = [],
        deferredRefs: [SceneDeferredRef] = [],
        reasonCodes: [String] = []
    ) -> SceneChunk {
        SceneChunk(
            sceneID: sceneID,
            chunkID: chunkID,
            chunkIndex: chunkIndex,
            sourceText: sourceText,
            sourceRange: ScriptOffsetRange(start: 0, end: sourceText.utf8.count),
            anchors: .empty,
            registryPatch: SceneChunk.RegistryPatch(
                actors: actors,
                objects: objects,
                actorAliasMap: [:],
                objectAliasMap: [:],
                speakerAliasMap: [:]
            ),
            beatPatch: beats,
            spatialRelationPatch: [],
            stateDelta: .empty,
            deferredRefs: deferredRefs,
            reasonCodes: reasonCodes,
            usedFallbackPlanner: false,
            usedLegacyPlanBridge: false
        )
    }

    func testEntityIDsSurviveAcrossChunkBoundary() {
        let stitcher = SceneStitcher()
        let first = chunk(
            sceneID: "scene_1",
            chunkID: "c1",
            chunkIndex: 0,
            sourceText: "МАРА подходит к столу.",
            actors: [ScenePlanIR.Actor(ref: "actor_1", type: .human, name: "МАРА")],
            objects: [ScenePlanIR.Object(ref: "object_1", type: .table, relativePosition: .center)]
        )
        let second = chunk(
            sceneID: "scene_1",
            chunkID: "c2",
            chunkIndex: 1,
            sourceText: "Олег берёт телефон.",
            actors: [ScenePlanIR.Actor(ref: "actor_2", type: .human, name: "ОЛЕГ")],
            objects: [ScenePlanIR.Object(ref: "object_2", type: .phone, relativePosition: .unknown)]
        )
        var state = stitcher.apply(chunk: first, to: nil)
        state = stitcher.apply(chunk: second, to: state)
        XCTAssertEqual(Set(state.actors.map(\.ref)), ["actor_1", "actor_2"])
        XCTAssertEqual(Set(state.objects.map(\.ref)), ["object_1", "object_2"])
        XCTAssertEqual(state.chunkLedger, ["c1", "c2"])
    }

    func testDuplicateEntityMergeKeepsSingleIdentity() {
        let stitcher = SceneStitcher()
        let first = chunk(
            sceneID: "scene_1",
            chunkID: "c1",
            chunkIndex: 0,
            sourceText: "МАРА стоит.",
            actors: [ScenePlanIR.Actor(ref: "actor_1", type: .human, name: "МАРА")]
        )
        let second = chunk(
            sceneID: "scene_1",
            chunkID: "c2",
            chunkIndex: 1,
            sourceText: "МАРА говорит.",
            actors: [ScenePlanIR.Actor(ref: "actor_1", type: .human, name: "МАРА")]
        )
        var state = stitcher.apply(chunk: first, to: nil)
        state = stitcher.apply(chunk: second, to: state)
        XCTAssertEqual(state.actors.filter { $0.ref == "actor_1" }.count, 1)
    }

    func testBeatChronologyPreservedInApplyOrder() {
        let stitcher = SceneStitcher()
        var state = stitcher.apply(chunk: chunk(
            sceneID: "scene_1",
            chunkID: "c1",
            chunkIndex: 0,
            sourceText: "Первая сцена.",
            actors: [ScenePlanIR.Actor(ref: "actor_1", type: .human, name: "МАРА")],
            beats: [ScenePlanIR.Beat(ref: "beat_1", actions: [
                ScenePlanIR.Action(actorRef: "actor_1", type: .stand)
            ])]
        ), to: nil)
        state = stitcher.apply(chunk: chunk(
            sceneID: "scene_1",
            chunkID: "c2",
            chunkIndex: 1,
            sourceText: "Вторая сцена.",
            beats: [ScenePlanIR.Beat(ref: "beat_2", actions: [
                ScenePlanIR.Action(actorRef: "actor_1", type: .walk)
            ])]
        ), to: state)
        XCTAssertEqual(state.beats.map(\.ref), ["beat_1", "beat_2"])
        let finalized = stitcher.finalize(state: state)
        XCTAssertEqual(finalized.beats.map(\.ref), ["beat_1", "beat_2"])
    }

    func testFinalizeResolvesDeferredReferences() {
        let stitcher = SceneStitcher()
        var state = stitcher.apply(chunk: chunk(
            sceneID: "scene_1",
            chunkID: "c1",
            chunkIndex: 0,
            sourceText: "Кто-то поднимает предмет.",
            beats: [ScenePlanIR.Beat(ref: "beat_1", actions: [
                ScenePlanIR.Action(actorRef: "actor_local", type: .pickUp, targetRef: "object_local")
            ])],
            deferredRefs: [
                SceneDeferredRef(id: "deferred_actor_1", localRef: "actor_local", kind: .actor, alias: "кто-то", sourceText: "кто-то")
            ]
        ), to: nil)
        // The deferred actor never resolves in a later chunk.
        state = stitcher.apply(chunk: chunk(
            sceneID: "scene_1",
            chunkID: "c2",
            chunkIndex: 1,
            sourceText: "Сцена продолжается."
        ), to: state)
        let finalized = stitcher.finalize(state: state)
        XCTAssertTrue(finalized.actors.isEmpty, "deferred actor must not materialize")
        XCTAssertTrue(finalized.beats.isEmpty, "beat whose only action referenced an unresolved actor must drop")
    }

    func testContinuityDiagnosticsCarryChunkReasons() {
        let stitcher = SceneStitcher()
        var state = stitcher.apply(chunk: chunk(
            sceneID: "scene_1",
            chunkID: "c1",
            chunkIndex: 0,
            sourceText: "a",
            reasonCodes: ["v9.event_provider_path_used"]
        ), to: nil)
        state = stitcher.apply(chunk: chunk(
            sceneID: "scene_1",
            chunkID: "c2",
            chunkIndex: 1,
            sourceText: "b",
            reasonCodes: ["v9.event_provider_path_used", "v9.give_recipient_repaired"]
        ), to: state)
        XCTAssertEqual(
            Set(state.continuityDiagnostics),
            ["v9.event_provider_path_used", "v9.give_recipient_repaired"]
        )
    }

    func testChunkCheckpointPayloadRoundTrips() throws {
        // Injected interruption at a chunk boundary: the checkpoint must
        // carry the full chunk so recovery restores it byte-exact.
        let original = chunk(
            sceneID: "scene_1",
            chunkID: "c1",
            chunkIndex: 0,
            sourceText: "МАРА подходит к столу.",
            actors: [ScenePlanIR.Actor(ref: "actor_1", type: .human, name: "МАРА")],
            beats: [ScenePlanIR.Beat(ref: "beat_1", actions: [
                ScenePlanIR.Action(actorRef: "actor_1", type: .approach, targetRef: "object_1")
            ])]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(SceneChunk.self, from: data)
        XCTAssertEqual(restored, original)
    }

}
