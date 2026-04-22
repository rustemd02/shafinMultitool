//
//  SceneV8PipelineTests.swift
//  shafinMultitoolTests
//
//  Created on 21.04.2026.
//

import XCTest
@testable import shafinMultitool

final class SceneV8PipelineTests: XCTestCase {
    private final class StubLocalProvider: LocalScenePlanProvider {
        let result: ScenePlanProviderResult?

        init(result: ScenePlanProviderResult?) {
            self.result = result
        }

        func generatePlan(
            description: String,
            markedObjects: [MarkedObject],
            anchors: SourceAnchorBundle,
            state: SceneChunkState?
        ) -> ScenePlanProviderResult? {
            result
        }

        func generatePlanAsync(
            description: String,
            markedObjects: [MarkedObject],
            anchors: SourceAnchorBundle,
            state: SceneChunkState?
        ) async -> ScenePlanProviderResult? {
            result
        }
    }

    private final class StubRemoteProvider: RemoteScenePlanProvider {
        let result: ScenePlanProviderResult?

        init(result: ScenePlanProviderResult?) {
            self.result = result
        }

        func generateRemotePlan(
            description: String,
            markedObjects: [MarkedObject],
            anchors: SourceAnchorBundle,
            state: SceneChunkState?
        ) async -> ScenePlanProviderResult? {
            result
        }
    }

    func testCompilerPreservesMarkedObjectIdentityAndSymbolicActors() throws {
        let compiler = ScenePlanCompiler()
        let plan = ScenePlanIR(
            actors: [
                .init(ref: "first", type: .human),
                .init(ref: "second", type: .human),
            ],
            objects: [
                .init(ref: "object_marked_deadbeef", type: .table, relativePosition: .center, markedObjectID: "object_marked_deadbeef"),
                .init(ref: "object_slot_1", type: .chair, relativePosition: .left),
            ],
            beats: [
                .init(
                    ref: "beat_1",
                    phase: "approach_object",
                    actions: [
                        .init(actorRef: "first", type: .approach, targetRef: "object_marked_deadbeef", resultingPose: .walking),
                        .init(actorRef: "second", type: .stand, targetRef: "object_slot_1", resultingPose: .standing),
                    ]
                )
            ],
            spatialRelations: [],
            referenceBindings: .init(
                actorBindings: ["first": "actor_1", "second": "actor_2"],
                markedObjectIDs: ["object_marked_deadbeef"],
                aliasToObjectRef: ["стол": "object_marked_deadbeef"]
            )
        )

        let script = try compiler.compile(plan: plan, originalDescription: "demo")
        XCTAssertEqual(script.actors.map(\.id), ["actor_1", "actor_2"])
        XCTAssertEqual(script.objects.map(\.id), ["object_marked_deadbeef", "object_1"])
        XCTAssertEqual(script.beats.first?.actions.first?.target, "object_marked_deadbeef")
    }

    func testQualityGateRejectsUnresolvedMarkedObject() {
        let gate = SceneQualityGate()
        let anchors = SourceAnchorBundle(
            actorCountHint: 2,
            ordinalMentions: ["first", "second"],
            mentionedMarkedObjects: ["object_marked_deadbeef"],
            objectSurfaceMentions: ["стол"],
            phaseCues: ["approach_object"],
            unsupportedActionFlags: [],
            sameTypeMarkerConflict: false,
            lowConfidenceFlags: []
        )
        let providerResult = ScenePlanProviderResult(
            plan: ScenePlanIR(
                actors: [.init(ref: "first", type: .human), .init(ref: "second", type: .human)],
                objects: [.init(ref: "object_slot_1", type: .table, relativePosition: .center)],
                beats: [.init(ref: "beat_1", actions: [.init(actorRef: "first", type: .approach, targetRef: "object_slot_1")])],
                spatialRelations: [],
                referenceBindings: .init(actorBindings: ["first": "actor_1", "second": "actor_2"], markedObjectIDs: [], aliasToObjectRef: [:])
            ),
            usedLegacySceneScriptBridge: false
        )

        let trace = gate.decide(anchors: anchors, providerResult: providerResult, compiledScript: nil, remoteEnabled: false)
        XCTAssertEqual(trace.route, .fallbackRuleOnly)
        XCTAssertTrue(trace.reasons.contains("unresolved_marked_object"))
    }

    func testAnchorExtractorFlagsSameTypeMarkerConflict() {
        let extractor = SceneAnchorExtractor()
        let markers = [
            MarkedObject(name: "левый стул", position: .init(x: 0, y: 0, z: 0)),
            MarkedObject(name: "правый стул", position: .init(x: 1, y: 0, z: 0)),
        ]

        let anchors = extractor.extract(
            description: "Первый подходит к левому стулу, второй стоит у правого стула",
            markedObjects: markers
        )

        XCTAssertTrue(anchors.sameTypeMarkerConflict)
        XCTAssertTrue(anchors.ordinalMentions.contains("first"))
        XCTAssertTrue(anchors.ordinalMentions.contains("second"))
    }

    func testQualityGatePrefersClarificationForAmbiguity() {
        let gate = SceneQualityGate()
        let anchors = SourceAnchorBundle(
            actorCountHint: 1,
            ordinalMentions: ["first", "second"],
            mentionedMarkedObjects: [],
            objectSurfaceMentions: ["стул"],
            phaseCues: [],
            unsupportedActionFlags: [],
            sameTypeMarkerConflict: true,
            lowConfidenceFlags: ["ordinal_actor_count_mismatch"]
        )
        let providerResult = ScenePlanProviderResult(
            plan: ScenePlanIR(
                actors: [.init(ref: "first", type: .human)],
                objects: [.init(ref: "object_slot_1", type: .chair, relativePosition: .left)],
                beats: [.init(ref: "beat_1", actions: [.init(actorRef: "first", type: .stand, targetRef: "object_slot_1")])],
                spatialRelations: [],
                referenceBindings: .init(actorBindings: ["first": "actor_1"])
            ),
            usedLegacySceneScriptBridge: false
        )

        let trace = gate.decide(anchors: anchors, providerResult: providerResult, compiledScript: nil, remoteEnabled: false)
        XCTAssertEqual(trace.route, .needsClarification)
        XCTAssertNotNil(trace.clarificationMessage)
    }

    func testCoordinatorPropagatesClarificationTraceIntoDiagnostics() {
        let compiler = ScenePlanCompiler()
        let coordinator = SceneParseCoordinator(
            anchorExtractor: SceneAnchorExtractor(),
            metadataExtractor: SceneMetadataExtractor(),
            localProvider: StubLocalProvider(
                result: ScenePlanProviderResult(
                    plan: ScenePlanIR(
                        actors: [.init(ref: "first", type: .human)],
                        objects: [.init(ref: "object_slot_1", type: .chair, relativePosition: .left)],
                        beats: [.init(ref: "beat_1", actions: [.init(actorRef: "first", type: .stand, targetRef: "object_slot_1")])],
                        spatialRelations: [],
                        referenceBindings: .init(actorBindings: ["first": "actor_1"])
                    ),
                    usedLegacySceneScriptBridge: false
                )
            ),
            compiler: compiler,
            qualityGate: SceneQualityGate(),
            diagnosticsCalculator: DiagnosticsCalculator()
        )

        let result = coordinator.parse(
            description: "Второй стоит у правого стула",
            markedObjects: [
                MarkedObject(name: "левый стул", position: .init(x: 0, y: 0, z: 0)),
                MarkedObject(name: "правый стул", position: .init(x: 1, y: 0, z: 0)),
            ]
        ) {
            ParsingResult(
                script: SceneScript(
                    actors: [.init(id: "actor_1", type: .human)],
                    objects: [.init(id: "object_1", type: .chair, relativePosition: .left)],
                    beats: [.init(id: "beat_1", actions: [.init(id: "action_1", actorId: "actor_1", type: .stand)])],
                    spatialRelations: [],
                    originalDescription: "fallback"
                ),
                diagnostics: .empty
            )
        }

        XCTAssertEqual(result.trace.route, .needsClarification)
        XCTAssertTrue(result.result.diagnostics.notes.contains(where: { $0.contains("router=needs_clarification") }))
    }

    func testMetadataExtractorParsesHeadingLocationAndTimeOfDay() {
        let extractor = SceneMetadataExtractor()
        let metadata = extractor.extract(description: "INT. KITCHEN - EVENING\nПервый подходит к столу")

        XCTAssertEqual(metadata.interiorExterior, "interior")
        XCTAssertEqual(metadata.locationName, "KITCHEN")
        XCTAssertEqual(metadata.timeOfDay, "evening")
        XCTAssertEqual(metadata.sceneHeading, "INT. KITCHEN - EVENING")
    }

    func testCoordinatorUsesRemotePlanWhenOffloadEnabled() async {
        let localResult = ScenePlanProviderResult(
            plan: ScenePlanIR(
                actors: [.init(ref: "first", type: .human)],
                objects: [],
                beats: [],
                spatialRelations: [],
                referenceBindings: .init(actorBindings: ["first": "actor_1"])
            ),
            usedLegacySceneScriptBridge: false
        )
        let remoteResult = ScenePlanProviderResult(
            plan: ScenePlanIR(
                actors: [.init(ref: "first", type: .human)],
                objects: [.init(ref: "object_slot_1", type: .table, relativePosition: .center)],
                beats: [.init(ref: "beat_1", actions: [.init(actorRef: "first", type: .approach, targetRef: "object_slot_1")])],
                spatialRelations: [],
                referenceBindings: .init(actorBindings: ["first": "actor_1"])
            ),
            usedLegacySceneScriptBridge: false
        )
        let coordinator = SceneParseCoordinator(
            anchorExtractor: SceneAnchorExtractor(),
            metadataExtractor: SceneMetadataExtractor(),
            localProvider: StubLocalProvider(result: localResult),
            remoteProvider: StubRemoteProvider(result: remoteResult),
            compiler: ScenePlanCompiler(),
            qualityGate: SceneQualityGate(),
            diagnosticsCalculator: DiagnosticsCalculator(),
            remoteOffloadEnabled: true
        )

        let output = await coordinator.parseAsync(
            description: "Человек подходит к столу",
            markedObjects: []
        ) {
            ParsingResult(
                script: SceneScript(actors: [], objects: [], beats: [], spatialRelations: [], originalDescription: "fallback"),
                diagnostics: .empty
            )
        }

        XCTAssertEqual(output.trace.route, .offloadRemote)
        XCTAssertTrue(output.trace.reasons.contains("remote_plan_used"))
        XCTAssertEqual(output.result.script.beats.count, 1)
        XCTAssertEqual(output.result.script.objects.count, 1)
    }
}
