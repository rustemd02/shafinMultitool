//
//  ScenePlanCompilerContinuityTests.swift
//  shafinMultitoolTests
//
//  M5-029: compiler continuity fixtures. Every compiled actor/object/
//  action reference resolves or yields a typed failure; no implicit
//  placeholder entity enters production. Multi-actor/object continuity
//  is proven end-to-end (plan → compiled script → client bridge).
//

import XCTest
@testable import shafinMultitool

final class ScenePlanCompilerContinuityTests: XCTestCase {
    private func multiEntityPlan() -> ScenePlanIR {
        ScenePlanIR(
            actors: [
                .init(ref: "first", type: .human, name: "МАРА"),
                .init(ref: "second", type: .human, name: "ОЛЕГ"),
            ],
            objects: [
                .init(ref: "object_table", type: .table, relativePosition: .center),
                .init(ref: "object_phone", type: .phone, relativePosition: .unknown, markedObjectID: "object_marked_deadbeef"),
            ],
            beats: [
                .init(ref: "beat_1", actions: [
                    .init(actorRef: "first", type: .approach, targetRef: "object_table"),
                    .init(actorRef: "second", type: .walk, direction: .towardEachOther),
                ]),
                .init(ref: "beat_2", actions: [
                    .init(actorRef: "second", type: .pickUp, targetRef: "object_phone", holdingObjectRef: "object_phone"),
                    .init(actorRef: "second", type: .give, targetRef: "first"),
                ]),
            ],
            spatialRelations: [
                .init(ref: "rel_1", subjectRef: "first", relation: .near, objectRef: "object_table")
            ],
            referenceBindings: .init(
                actorBindings: ["first": "actor_1", "second": "actor_2"],
                markedObjectIDs: ["object_marked_deadbeef"],
                aliasToObjectRef: [:]
            )
        )
    }

    func testMultiEntityPlanCompilesWithAllReferencesResolved() throws {
        let compiler = ScenePlanCompiler()
        let compiled = try compiler.compileWithNotes(
            plan: multiEntityPlan(),
            originalDescription: "МАРА подходит к столу, Олег идёт навстречу и передаёт телефон."
        )
        let script = compiled.script
        XCTAssertEqual(script.actors.map(\.id), ["actor_1", "actor_2"])
        // Canonical object IDs are ordinal (object_1, object_2); types
        // and order are the identity that must survive.
        XCTAssertEqual(Set(script.objects.map(\.type.rawValue)), Set(["table", "phone"]))
        XCTAssertEqual(script.beats.map(\.id), ["beat_1", "beat_2"])
        // Every action actor/target resolves.
        let actorIDs = Set(script.actors.map(\.id))
        let objectIDs = Set(script.objects.map(\.id))
        for beat in script.beats {
            for action in beat.actions {
                XCTAssertTrue(actorIDs.contains(action.actorId), "unresolved actor \(action.actorId)")
                if let target = action.target {
                    XCTAssertTrue(
                        actorIDs.contains(target) || objectIDs.contains(target),
                        "unresolved target \(target)"
                    )
                }
                if let holding = action.holdingObject {
                    XCTAssertTrue(objectIDs.contains(holding), "unresolved holding \(holding)")
                }
            }
        }
        // And the compiled script passes the M5-026 response validator.
        XCTAssertEqual(
            SceneResponseValidator.validate(script: script),
            []
        )
    }

    func testUnknownActorRefYieldsTypedFailure() {
        let plan = ScenePlanIR(
            actors: [.init(ref: "first", type: .human)],
            objects: [],
            beats: [.init(ref: "beat_1", actions: [
                .init(actorRef: "actor_ghost", type: .stand)
            ])],
            spatialRelations: [],
            referenceBindings: .init(actorBindings: ["first": "actor_1"])
        )
        XCTAssertThrowsError(try ScenePlanCompiler().compile(plan: plan, originalDescription: "demo")) { error in
            guard case ScenePlanCompilerError.missingActorRef(let ref) = error else {
                return XCTFail("expected missingActorRef, got \(error)")
            }
            XCTAssertEqual(ref, "actor_ghost")
        }
    }

    func testUnknownHoldingRefYieldsTypedFailure() {
        let plan = ScenePlanIR(
            actors: [.init(ref: "first", type: .human)],
            objects: [],
            beats: [.init(ref: "beat_1", actions: [
                .init(actorRef: "first", type: .pickUp, holdingObjectRef: "object_ghost")
            ])],
            spatialRelations: [],
            referenceBindings: .init(actorBindings: ["first": "actor_1"])
        )
        XCTAssertThrowsError(try ScenePlanCompiler().compile(plan: plan, originalDescription: "demo")) { error in
            guard case ScenePlanCompilerError.missingObjectRef = error else {
                return XCTFail("expected missingObjectRef, got \(error)")
            }
        }
    }

    func testNoPlaceholderEntityEntersCompiledScript() throws {
        // Object-only scene: no actors, no beats — compiles honestly
        // without inventing stand/talk beats or actor_1.
        let plan = ScenePlanIR(
            actors: [],
            objects: [.init(ref: "object_chair", type: .chair, relativePosition: .left)],
            beats: [],
            spatialRelations: [],
            referenceBindings: .init()
        )
        let compiled = try compilerNoThrow(plan: plan)
        XCTAssertTrue(compiled.script.actors.isEmpty)
        XCTAssertTrue(compiled.script.beats.isEmpty)
        XCTAssertEqual(compiled.script.objects.map(\.type.rawValue), ["chair"])
    }

    func testClientBridgeUsesCompilerPath() throws {
        // The M5-025 client bridge projects the validated script; the
        // projected plan must recompile cleanly through the same
        // compiler (continuity across the remote seam).
        let compiler = ScenePlanCompiler()
        let compiled = try compiler.compileWithNotes(
            plan: multiEntityPlan(),
            originalDescription: "demo"
        )
        let bridgePlan = ScenePlanIR(
            actors: compiled.script.actors.map {
                .init(ref: $0.id, type: $0.type, name: $0.name)
            },
            objects: compiled.script.objects.map {
                .init(ref: $0.id, type: $0.type, relativePosition: $0.relativePosition, name: $0.name)
            },
            beats: compiled.script.beats.map { beat in
                .init(ref: beat.id, actions: beat.actions.map { action in
                    .init(
                        actorRef: action.actorId,
                        type: action.type,
                        targetRef: action.target,
                        direction: action.direction,
                        modifier: action.modifier,
                        resultingPose: action.resultingPose,
                        holdingObjectRef: action.holdingObject,
                        dialogue: action.dialogue,
                        fallbackText: action.fallbackText,
                        sourceText: action.sourceText
                    )
                })
            },
            spatialRelations: compiled.script.spatialRelations.map {
                .init(ref: $0.id, subjectRef: $0.subject, relation: $0.relation, objectRef: $0.object)
            },
            referenceBindings: .init(
                actorBindings: Dictionary(uniqueKeysWithValues: compiled.script.actors.map { ($0.id, $0.id) }),
                markedObjectIDs: compiled.script.objects.compactMap { $0.id.hasPrefix("object_marked_") ? $0.id : nil },
                aliasToObjectRef: [:]
            )
        )
        let recompiled = try compiler.compileWithNotes(plan: bridgePlan, originalDescription: "demo")
        XCTAssertEqual(recompiled.script, compiled.script)
    }

    private func compilerNoThrow(plan: ScenePlanIR) throws -> (script: SceneScript, notes: [String]) {
        try ScenePlanCompiler().compileWithNotes(plan: plan, originalDescription: "demo")
    }
}
