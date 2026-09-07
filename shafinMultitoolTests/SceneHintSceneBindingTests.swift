//
//  SceneHintSceneBindingTests.swift
//  shafinMultitoolTests
//
//  M6-010: planned-action hint binding. Bindings reference only real
//  parsed-script entity IDs; dangling references and unstable tracking
//  suppress (nil), never fabricate.
//

import XCTest
@testable import shafinMultitool

@MainActor
final class SceneHintSceneBindingTests: XCTestCase {
    private func script() -> SceneScript {
        SceneScript(
            actors: [
                SceneActor(id: "actor_1", type: .human, name: "МАРА"),
                SceneActor(id: "actor_2", type: .human, name: "ОЛЕГ"),
            ],
            objects: [
                SceneObject(id: "object_marked_deadbeef", type: .table, relativePosition: .center)
            ],
            beats: [
                SceneBeat(id: "beat_1", actions: [SceneAction(
                    id: "action_1", actorId: "actor_1", type: .approach, target: "object_marked_deadbeef"
                )]),
                SceneBeat(id: "beat_2", actions: [SceneAction(
                    id: "action_2", actorId: "actor_2", type: .give, target: "actor_1"
                )]),
            ],
            spatialRelations: [],
            originalDescription: "demo"
        )
    }

    func testBindingResolvesPlannedActionWithRealIDs() {
        let binding = SceneHintSceneBinding.resolve(
            script: script(),
            requestedBeatID: "beat_1",
            postureStable: true
        )
        XCTAssertEqual(binding?.beatID, "beat_1")
        XCTAssertEqual(binding?.actionID, "action_1")
        XCTAssertEqual(binding?.actorID, "actor_1")
        XCTAssertEqual(binding?.actorName, "МАРА")
        XCTAssertEqual(binding?.targetID, "object_marked_deadbeef")
    }

    func testTargetActorResolvesToName() {
        let binding = SceneHintSceneBinding.resolve(
            script: script(),
            requestedBeatID: "beat_2",
            postureStable: true
        )
        XCTAssertEqual(binding?.targetID, "actor_1")
        XCTAssertEqual(binding?.targetName, "МАРА")
    }

    func testUnstableTrackingSuppresses() {
        XCTAssertNil(
            SceneHintSceneBinding.resolve(
                script: script(),
                requestedBeatID: "beat_1",
                postureStable: false
            )
        )
    }

    func testNoScriptSuppresses() {
        XCTAssertNil(
            SceneHintSceneBinding.resolve(script: nil, requestedBeatID: nil, postureStable: true)
        )
    }

    func testUnknownRequestedBeatSuppresses() {
        XCTAssertNil(
            SceneHintSceneBinding.resolve(
                script: script(),
                requestedBeatID: "beat_ghost",
                postureStable: true
            ),
            "unknown requested beat is a state mismatch: suppress, never substitute another beat"
        )
    }

    func testDanglingTargetSuppressesInsteadOfGuessing() {
        var dangling = script()
        dangling = SceneScript(
            actors: dangling.actors,
            objects: dangling.objects,
            beats: [SceneBeat(id: "beat_1", actions: [SceneAction(
                id: "action_1", actorId: "actor_1", type: .give, target: "object_ghost"
            )])],
            spatialRelations: [],
            originalDescription: "demo"
        )
        XCTAssertNil(
            SceneHintSceneBinding.resolve(script: dangling, requestedBeatID: "beat_1", postureStable: true),
            "dangling target must suppress, never fabricate a name"
        )
    }

    func testDanglingActorSuppresses() {
        let dangling = SceneScript(
            actors: [],
            objects: script().objects,
            beats: script().beats,
            spatialRelations: [],
            originalDescription: "demo"
        )
        XCTAssertNil(
            SceneHintSceneBinding.resolve(script: dangling, requestedBeatID: "beat_1", postureStable: true)
        )
    }
}
