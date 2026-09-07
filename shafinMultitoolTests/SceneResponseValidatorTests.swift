//
//  SceneResponseValidatorTests.swift
//  shafinMultitoolTests
//
//  M5-026: adversarial invalid-output fixtures. Every corruption shape
//  is rejected with its typed issue; the valid script passes clean.
//

import XCTest
@testable import shafinMultitool

final class SceneResponseValidatorTests: XCTestCase {
    private func validScript() -> SceneScript {
        SceneScript(
            actors: [SceneActor(id: "actor_1", type: .human, name: "MARA")],
            objects: [SceneObject(
                id: "object_marked_deadbeef",
                type: .table,
                relativePosition: .center
            )],
            beats: [SceneBeat(id: "beat_1", actions: [SceneAction(
                id: "action_1",
                actorId: "actor_1",
                type: .approach,
                target: "object_marked_deadbeef"
            )])],
            spatialRelations: [],
            originalDescription: "MARA approaches the marked table."
        )
    }

    func testValidScriptPasses() {
        XCTAssertEqual(
            SceneResponseValidator.validate(
                script: validScript(),
                markedObjectIDs: ["object_marked_deadbeef"],
                mentionedMarkedObjects: ["object_marked_deadbeef"]
            ),
            []
        )
    }

    func testEmptyBeatsRejected() {
        var script = validScript()
        script = SceneScript(
            actors: script.actors,
            objects: script.objects,
            beats: [],
            spatialRelations: [],
            originalDescription: script.originalDescription
        )
        XCTAssertTrue(
            SceneResponseValidator.validate(script: script).contains(.emptyBeats)
        )
    }

    func testEmptyBeatActionsRejected() {
        let script = SceneScript(
            actors: [SceneActor(id: "actor_1", type: .human)],
            objects: [],
            beats: [SceneBeat(id: "beat_1", actions: [])],
            spatialRelations: [],
            originalDescription: "demo"
        )
        XCTAssertTrue(
            SceneResponseValidator.validate(script: script).contains(.emptyBeatActions)
        )
    }

    func testDanglingActorRejected() {
        var script = validScript()
        script = SceneScript(
            actors: [],
            objects: script.objects,
            beats: script.beats,
            spatialRelations: [],
            originalDescription: script.originalDescription
        )
        XCTAssertTrue(
            SceneResponseValidator.validate(script: script).contains(.danglingActorReference)
        )
    }

    func testDanglingTargetRejected() {
        let script = SceneScript(
            actors: [SceneActor(id: "actor_1", type: .human)],
            objects: [],
            beats: [SceneBeat(id: "beat_1", actions: [SceneAction(
                id: "action_1",
                actorId: "actor_1",
                type: .give,
                target: "object_ghost"
            )])],
            spatialRelations: [],
            originalDescription: "demo"
        )
        XCTAssertTrue(
            SceneResponseValidator.validate(script: script).contains(.danglingActionTarget)
        )
    }

    func testDanglingHoldingRejected() {
        let script = SceneScript(
            actors: [SceneActor(id: "actor_1", type: .human)],
            objects: [],
            beats: [SceneBeat(id: "beat_1", actions: [SceneAction(
                id: "action_1",
                actorId: "actor_1",
                type: .pickUp,
                holdingObject: "object_ghost"
            )])],
            spatialRelations: [],
            originalDescription: "demo"
        )
        XCTAssertTrue(
            SceneResponseValidator.validate(script: script).contains(.danglingHoldingReference)
        )
    }

    func testDuplicateIDsRejected() {
        let script = SceneScript(
            actors: [
                SceneActor(id: "actor_1", type: .human),
                SceneActor(id: "actor_1", type: .human)
            ],
            objects: [],
            beats: [SceneBeat(id: "beat_1", actions: [SceneAction(
                id: "action_1",
                actorId: "actor_1",
                type: .stand
            )])],
            spatialRelations: [],
            originalDescription: "demo"
        )
        XCTAssertTrue(
            SceneResponseValidator.validate(script: script).contains(.duplicateEntityID)
        )
    }

    func testUnresolvedMarkedBindingRejected() {
        XCTAssertTrue(
            SceneResponseValidator.validate(
                script: validScript(),
                markedObjectIDs: [],
                mentionedMarkedObjects: ["object_marked_deadbeef"]
            ).contains(.unresolvedMarkedBinding)
        )
    }

    func testBeatOrderViolationRejected() {
        let reversed = SceneScript(
            actors: [SceneActor(id: "actor_1", type: .human)],
            objects: [],
            beats: [
                SceneBeat(id: "beat_2", actions: [SceneAction(
                    id: "action_2", actorId: "actor_1", type: .stand
                )]),
                SceneBeat(id: "beat_1", actions: [SceneAction(
                    id: "action_1", actorId: "actor_1", type: .stand
                )])
            ],
            spatialRelations: [],
            originalDescription: "demo"
        )
        XCTAssertTrue(
            SceneResponseValidator.validate(script: reversed).contains(.beatOrderViolation)
        )
    }

    func testRelationDanglingReferenceRejected() {
        let script = SceneScript(
            actors: [SceneActor(id: "actor_1", type: .human)],
            objects: [],
            beats: [SceneBeat(id: "beat_1", actions: [SceneAction(
                id: "action_1", actorId: "actor_1", type: .stand
            )])],
            spatialRelations: [SpatialRelation(
                id: "rel_1",
                subject: "actor_1",
                relation: .near,
                object: "object_ghost"
            )],
            originalDescription: "demo"
        )
        XCTAssertTrue(
            SceneResponseValidator.validate(script: script).contains(.danglingObjectReference)
        )
    }
}
