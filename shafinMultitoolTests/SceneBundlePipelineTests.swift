//
//  SceneBundlePipelineTests.swift
//  shafinMultitoolTests
//
//  Created on 22.04.2026.
//

import XCTest
import ARKit
import simd
import CoreGraphics
import CoreVideo
import ImageIO
import UIKit
@testable import shafinMultitool

final class SceneBundlePipelineTests: XCTestCase {
    private final class StubLocalProvider: LocalScenePlanProvider {
        let result: ScenePlanProviderResult?
        let eventProvider: ((String, [MarkedObject], SourceAnchorBundle, SceneChunkState?, SceneV9SlotCatalog) -> SceneV9EventProviderResult?)?
        private var asyncResults: [ScenePlanProviderResult?]
        private(set) var generatePlanCallCount = 0
        private(set) var generatePlanAsyncCallCount = 0
        private(set) var generateEventTableCallCount = 0
        private(set) var generateEventTableAsyncCallCount = 0

        init(
            result: ScenePlanProviderResult?,
            asyncResults: [ScenePlanProviderResult?] = [],
            eventProvider: ((String, [MarkedObject], SourceAnchorBundle, SceneChunkState?, SceneV9SlotCatalog) -> SceneV9EventProviderResult?)? = nil
        ) {
            self.result = result
            self.asyncResults = asyncResults
            self.eventProvider = eventProvider
        }

        func generatePlan(
            description: String,
            markedObjects: [MarkedObject],
            anchors: SourceAnchorBundle,
            state: SceneChunkState?
        ) -> ScenePlanProviderResult? {
            generatePlanCallCount += 1
            return result
        }

        func generatePlanAsync(
            description: String,
            markedObjects: [MarkedObject],
            anchors: SourceAnchorBundle,
            state: SceneChunkState?
        ) async -> ScenePlanProviderResult? {
            generatePlanAsyncCallCount += 1
            if !asyncResults.isEmpty {
                return asyncResults.removeFirst()
            }
            return result
        }

        func generateEventTable(
            description: String,
            markedObjects: [MarkedObject],
            anchors: SourceAnchorBundle,
            state: SceneChunkState?,
            slotCatalog: SceneV9SlotCatalog
        ) -> SceneV9EventProviderResult? {
            generateEventTableCallCount += 1
            return eventProvider?(description, markedObjects, anchors, state, slotCatalog)
                ?? makeEventProviderResultFromPlan()
        }

        func generateEventTableAsync(
            description: String,
            markedObjects: [MarkedObject],
            anchors: SourceAnchorBundle,
            state: SceneChunkState?,
            slotCatalog: SceneV9SlotCatalog
        ) async -> SceneV9EventProviderResult? {
            generateEventTableAsyncCallCount += 1
            return eventProvider?(description, markedObjects, anchors, state, slotCatalog)
                ?? makeEventProviderResultFromPlan()
        }

        private func makeEventProviderResultFromPlan() -> SceneV9EventProviderResult? {
            guard let result else { return nil }
            let service = SceneEventTableV9Service()
            let slotCatalog = service.buildSlotCatalog(from: result.plan)
            return SceneV9EventProviderResult(
                slotCatalog: slotCatalog,
                eventTable: service.buildEventTable(from: result.plan, slotCatalog: slotCatalog),
                reasonCodes: result.reasonCodes + ["test.stub_event_table_from_plan"]
            )
        }
    }

    private final class ExecutionSupportProbe {
        private var snapshots: [SceneExecutionResourceSnapshot]
        private let fallbackSnapshot: SceneExecutionResourceSnapshot
        private(set) var sleepCalls: [Int] = []
        private(set) var checkpoints: [String: Data] = [:]

        init(snapshots: [SceneExecutionResourceSnapshot]) {
            self.snapshots = snapshots
            self.fallbackSnapshot = snapshots.last ?? SceneExecutionResourceSnapshot(
                timestamp: Date(),
                thermalState: .nominal,
                batteryLevel: 1.0,
                memoryMB: 128
            )
        }

        func makeSupport() -> SceneGeneratorExecutionSupport {
            SceneGeneratorExecutionSupport(
                makeSnapshot: { [self] in
                    if snapshots.isEmpty {
                        return fallbackSnapshot
                    }
                    return snapshots.removeFirst()
                },
                sleep: { [self] milliseconds in
                    sleepCalls.append(milliseconds)
                },
                writeCheckpoint: { [self] fileName, data in
                    checkpoints[fileName] = data
                },
                now: { Date() }
            )
        }
    }

    private var parser: SceneParserService!
    private let runtimeModeKey = "scene_generator_v9_runtime_mode"

    override func setUpWithError() throws {
        try super.setUpWithError()
        parser = SceneParserService.shared
        parser.resetRuntimeContext()
    }

    override func tearDownWithError() throws {
        parser?.resetRuntimeContext()
        parser = nil
        try super.tearDownWithError()
    }

    private func setRuntimeMode(_ rawValue: String) -> () -> Void {
        let defaults = UserDefaults.standard
        let oldValue = defaults.object(forKey: runtimeModeKey)
        defaults.set(rawValue, forKey: runtimeModeKey)
        return {
            if let oldValue {
                defaults.set(oldValue, forKey: self.runtimeModeKey)
            } else {
                defaults.removeObject(forKey: self.runtimeModeKey)
            }
        }
    }

    private func makeBundlePipeline(result: ScenePlanProviderResult?) -> SceneBundlePipeline {
        SceneBundlePipeline(
            anchorExtractor: SceneAnchorExtractor(),
            metadataExtractor: SceneMetadataExtractor(),
            localProvider: StubLocalProvider(result: result),
            planCompiler: ScenePlanCompiler()
        )
    }

    private func makeBundlePipeline(
        result: ScenePlanProviderResult?,
        eventProvider: @escaping (String, [MarkedObject], SourceAnchorBundle, SceneChunkState?, SceneV9SlotCatalog) -> SceneV9EventProviderResult?
    ) -> SceneBundlePipeline {
        SceneBundlePipeline(
            anchorExtractor: SceneAnchorExtractor(),
            metadataExtractor: SceneMetadataExtractor(),
            localProvider: StubLocalProvider(result: result, eventProvider: eventProvider),
            planCompiler: ScenePlanCompiler()
        )
    }

    private func simpleProviderResult() -> ScenePlanProviderResult {
        ScenePlanProviderResult(
            plan: ScenePlanIR(
                actors: [.init(ref: "first", type: .human)],
                objects: [.init(ref: "object_box", type: .generic, relativePosition: .center, name: "коробка")],
                beats: [
                    .init(
                        ref: "beat_1",
                        actions: [
                            .init(
                                actorRef: "first",
                                type: .pickUp,
                                targetRef: "object_box",
                                resultingPose: .standing,
                                holdingObjectRef: "object_box",
                                sourceText: "актёр берёт коробку"
                            ),
                        ]
                    ),
                ],
                spatialRelations: [],
                referenceBindings: .init(actorBindings: ["first": "actor_1"])
            ),
            usedLegacySceneScriptBridge: false
        )
    }

    func testMonolithicExecutionWritesOnlyFinalCheckpoint() async throws {
        let pipeline = makeBundlePipeline(result: simpleProviderResult())
        let supportProbe = ExecutionSupportProbe(
            snapshots: Array(
                repeating: SceneExecutionResourceSnapshot(
                    timestamp: Date(),
                    thermalState: .nominal,
                    batteryLevel: 0.9,
                    memoryMB: 128
                ),
                count: 8
            )
        )
        let description = """
        Первый актёр берёт коробку.
        Затем он держит коробку.
        Потом он ставит коробку на стол.
        """

        let result = await pipeline.parse(
            description: description,
            markedObjects: [],
            mode: .full,
            previousState: nil,
            executionPolicy: SceneGeneratorMobileExecutionPolicy(
                mode: .monolithic,
                cooldownOnSeriousMs: 25,
                cooldownOnCriticalMs: 40,
                maxChunkAttempts: 1,
                checkpointEnabled: true
            ),
            executionSupport: supportProbe.makeSupport()
        ) { text, _, _ in
            ParsingResult(
                script: SceneScript(actors: [], objects: [], beats: [], spatialRelations: [], originalDescription: text),
                diagnostics: .empty
            )
        }

        XCTAssertNotNil(result.activeSceneScript)
        XCTAssertEqual(result.executionTrace?.executionMode.rawValue, SceneGeneratorExecutionMode.monolithic.rawValue)
        XCTAssertTrue(supportProbe.checkpoints.keys.contains("scene_monolithic_result.json"))
        XCTAssertFalse(supportProbe.checkpoints.keys.contains { $0.hasPrefix("chunk_") })
        let finalPayload = try XCTUnwrap(supportProbe.checkpoints["scene_monolithic_result.json"])
        let finalObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: finalPayload) as? [String: Any]
        )
        XCTAssertEqual(finalObject["checkpointCount"] as? Int, 1)
        XCTAssertNotNil(finalObject["activeSceneScript"])
        XCTAssertNotNil(finalObject["bundleScript"])
    }

    func testChunkedThermalAwareWritesChunkCheckpointsAndSleepsOnSerious() async throws {
        let pipeline = makeBundlePipeline(result: simpleProviderResult())
        let supportProbe = ExecutionSupportProbe(
            snapshots: [
                SceneExecutionResourceSnapshot(timestamp: Date(), thermalState: .serious, batteryLevel: 0.8, memoryMB: 150),
                SceneExecutionResourceSnapshot(timestamp: Date(), thermalState: .nominal, batteryLevel: 0.8, memoryMB: 149),
                SceneExecutionResourceSnapshot(timestamp: Date(), thermalState: .nominal, batteryLevel: 0.8, memoryMB: 149),
                SceneExecutionResourceSnapshot(timestamp: Date(), thermalState: .nominal, batteryLevel: 0.8, memoryMB: 149),
                SceneExecutionResourceSnapshot(timestamp: Date(), thermalState: .nominal, batteryLevel: 0.8, memoryMB: 149),
                SceneExecutionResourceSnapshot(timestamp: Date(), thermalState: .nominal, batteryLevel: 0.8, memoryMB: 149),
                SceneExecutionResourceSnapshot(timestamp: Date(), thermalState: .nominal, batteryLevel: 0.8, memoryMB: 149),
                SceneExecutionResourceSnapshot(timestamp: Date(), thermalState: .nominal, batteryLevel: 0.8, memoryMB: 149),
            ]
        )
        let description = """
        Первый актёр берёт коробку.

        Затем он держит коробку рядом со столом.
        Потом он ставит коробку на стол.
        """

        let result = await pipeline.parse(
            description: description,
            markedObjects: [],
            mode: .full,
            previousState: nil,
            executionPolicy: SceneGeneratorMobileExecutionPolicy(
                mode: .chunkedThermalAware,
                cooldownOnSeriousMs: 25,
                cooldownOnCriticalMs: 40,
                maxChunkAttempts: 1,
                checkpointEnabled: true
            ),
            executionSupport: supportProbe.makeSupport()
        ) { text, _, _ in
            ParsingResult(
                script: SceneScript(actors: [], objects: [], beats: [], spatialRelations: [], originalDescription: text),
                diagnostics: .empty
            )
        }

        XCTAssertNotNil(result.activeSceneScript)
        XCTAssertEqual(supportProbe.sleepCalls, [25])
        XCTAssertEqual(result.executionTrace?.events.filter { $0.kind == .thermalCooldownStarted }.count ?? 0, 1)
        XCTAssertEqual(result.executionTrace?.events.filter { $0.kind == .thermalCooldownFinished }.count ?? 0, 1)
        XCTAssertEqual(result.executionTrace?.checkpoints.count ?? 0, result.chunkDiagnostics.count + 1)
        XCTAssertTrue(supportProbe.checkpoints.keys.contains("scene_chunked_result.json"))
        XCTAssertTrue(supportProbe.checkpoints.keys.contains { $0.hasPrefix("chunk_") })
        let chunkPayload = try XCTUnwrap(supportProbe.checkpoints.first(where: { $0.key.hasPrefix("chunk_") })?.value)
        let chunkObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: chunkPayload) as? [String: Any]
        )
        XCTAssertNotNil(chunkObject["chunk"])
        XCTAssertNotNil(chunkObject["diagnostics"])
        let finalPayload = try XCTUnwrap(supportProbe.checkpoints["scene_chunked_result.json"])
        let finalObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: finalPayload) as? [String: Any]
        )
        XCTAssertEqual(finalObject["checkpointCount"] as? Int, result.chunkDiagnostics.count + 1)
        XCTAssertNotNil(finalObject["chunkDiagnostics"])
    }

    func testChunkedThermalAwareRecordsCriticalAsTelemetryOnly() async throws {
        let pipeline = makeBundlePipeline(result: simpleProviderResult())
        let supportProbe = ExecutionSupportProbe(
            snapshots: Array(
                repeating: SceneExecutionResourceSnapshot(
                    timestamp: Date(),
                    thermalState: .critical,
                    batteryLevel: 0.7,
                    memoryMB: 160
                ),
                count: 6
            )
        )

        let result = await pipeline.parse(
            description: "Первый актёр берёт коробку.",
            markedObjects: [],
            mode: .full,
            previousState: nil,
            executionPolicy: SceneGeneratorMobileExecutionPolicy(
                mode: .chunkedThermalAware,
                cooldownOnSeriousMs: 25,
                cooldownOnCriticalMs: 40,
                maxChunkAttempts: 1,
                checkpointEnabled: false
            ),
            executionSupport: supportProbe.makeSupport()
        ) { text, _, _ in
            ParsingResult(
                script: SceneScript(actors: [], objects: [], beats: [], spatialRelations: [], originalDescription: text),
                diagnostics: .empty
            )
        }

        XCTAssertNotNil(result.activeSceneScript)
        XCTAssertTrue(supportProbe.sleepCalls.isEmpty)
        XCTAssertEqual(result.executionTrace?.events.filter { $0.kind == .criticalTelemetryObserved }.count ?? 0, 1)
        XCTAssertTrue(result.executionTrace?.events.contains(where: { $0.note == "critical_is_telemetry_only" }) ?? false)
    }

    func testParseBundleReturnsMultipleScenesForHeadings() async throws {
        let description = """
        INT. OFFICE - NIGHT
        Человек подходит к столу.

        EXT. STREET - DAY
        Женщина идёт к двери.
        """

        let result = await parser.parseBundle(description, markedObjects: [])

        XCTAssertEqual(result.bundleScript.scenes.count, 2)
        XCTAssertEqual(result.documentState.sceneCandidates.count, 2)
        XCTAssertEqual(result.bundleScript.activeSceneIndex, 0)
        XCTAssertEqual(result.bundleScript.scenes.first?.locationName, "OFFICE")
        XCTAssertEqual(result.bundleScript.scenes.last?.locationName, "STREET")
        XCTAssertFalse(result.sceneChunks.isEmpty)
    }

    func testParseCompatibilityReturnsActiveSceneFromBundle() async throws {
        let description = """
        INT. OFFICE - NIGHT
        Человек подходит к столу.

        EXT. STREET - DAY
        Женщина идёт к двери.
        """

        let compatibility = await parser.parse(description, markedObjects: [])
        let bundle = try XCTUnwrap(parser.lastBundleResult)
        let activeScene = try XCTUnwrap(bundle.activeSceneScript)

        XCTAssertEqual(compatibility.script.locationName, activeScene.locationName)
        XCTAssertEqual(compatibility.script.beats.count, activeScene.beats.count)
        XCTAssertEqual(parser.lastDocumentState?.bundleScript.scenes.count, 2)
    }

    func testParseBundleProducesCanonicalStableRefsInChunks() async throws {
        let description = "Человек подходит к столу, затем садится на стул."

        let result = await parser.parseBundle(description, markedObjects: [])
        let stitchState = try XCTUnwrap(result.documentState.stitchStates.last)
        let actorRefs = stitchState.actors.map(\.ref)
        let objectRefs = stitchState.objects.map(\.ref)

        XCTAssertFalse(actorRefs.isEmpty)
        XCTAssertTrue(actorRefs.allSatisfy { $0.hasPrefix("actor_scene") || ["first", "second", "third"].contains($0) })
        XCTAssertTrue(objectRefs.allSatisfy { $0.hasPrefix("object_scene") || $0.hasPrefix("object_marked_") || $0.hasPrefix("object_slot_") })
        XCTAssertFalse(result.sceneChunks.isEmpty)
    }

    func testParseBundleAppendModeExtendsTailSceneWithoutChangingSceneCount() async throws {
        let initialDescription = "Человек подходит к столу."
        let initial = await parser.parseBundle(initialDescription, markedObjects: [])
        let appendedDescription = initialDescription + "\nПотом он садится на стул."

        let appended = await parser.parseBundle(
            appendedDescription,
            markedObjects: [],
            mode: .append,
            previousState: initial.documentState
        )

        XCTAssertEqual(initial.bundleScript.scenes.count, 1)
        XCTAssertEqual(appended.bundleScript.scenes.count, 1)
        XCTAssertEqual(appended.documentState.sceneCandidates.count, 1)
        XCTAssertTrue(appended.bundleScript.activeSceneScript?.originalDescription.contains("садится на стул") ?? false)

        let initialActorRefs = Set(initial.documentState.stitchStates.last?.actors.map(\.ref) ?? [])
        let appendedActorRefs = Set(appended.documentState.stitchStates.last?.actors.map(\.ref) ?? [])
        XCTAssertEqual(initialActorRefs, appendedActorRefs)
    }

    func testParseBundleAppendModeCreatesNewSceneForNewHeading() async throws {
        let initialDescription = "Человек подходит к столу."
        let initial = await parser.parseBundle(initialDescription, markedObjects: [])
        let appendedDescription = """
        \(initialDescription)

        EXT. STREET - DAY
        Женщина идёт к двери.
        """

        let appended = await parser.parseBundle(
            appendedDescription,
            markedObjects: [],
            mode: .append,
            previousState: initial.documentState
        )

        XCTAssertEqual(initial.bundleScript.scenes.count, 1)
        XCTAssertEqual(appended.bundleScript.scenes.count, 2)
        XCTAssertEqual(appended.documentState.sceneCandidates.count, 2)
        XCTAssertEqual(appended.bundleScript.scenes.last?.locationName, "STREET")
    }

    func testParseBundleSupportsNatHeadingAndGenericLocationDashTimeHeading() async throws {
        let natDescription = """
        НАТ. ПЛЯЖ - ВЕЧЕР
        Человек идёт к воде.
        """
        let genericDescription = """
        KITCHEN - NIGHT
        Женщина открывает дверь.
        """

        let natResult = await parser.parseBundle(natDescription, markedObjects: [])
        let genericResult = await parser.parseBundle(genericDescription, markedObjects: [])

        XCTAssertEqual(natResult.bundleScript.scenes.first?.interiorExterior, "exterior")
        XCTAssertEqual(natResult.bundleScript.scenes.first?.timeOfDay, "evening")
        XCTAssertEqual(genericResult.documentState.sceneCandidates.count, 1)
        XCTAssertEqual(genericResult.documentState.sceneCandidates.first?.metadata.locationName, "KITCHEN")
        XCTAssertEqual(genericResult.documentState.sceneCandidates.first?.metadata.timeOfDay, "night")
    }

    func testParseBundlePreservesSplitHeadingPrefixLines() async throws {
        let description = """
        ПЛАН НА:
        ЭКСТ.
        ЛА ДИСПЕНСАРИА — РАССВЕТ
        Щелкает затвор, сделана фотография.
        """

        let result = await parser.parseBundle(description, markedObjects: [])

        XCTAssertEqual(result.documentState.sceneCandidates.count, 1)
        XCTAssertEqual(result.documentState.sceneCandidates.first?.metadata.interiorExterior, "exterior")
        XCTAssertEqual(result.documentState.sceneCandidates.first?.metadata.timeOfDay, "morning")
        XCTAssertTrue(result.documentState.sceneCandidates.first?.sourceText.hasPrefix("ЭКСТ.\nЛА ДИСПЕНСАРИА — РАССВЕТ") ?? false)
    }

    func testParseBundleFullModeReusesUnchangedScenesFromPreviousState() async throws {
        let initialDescription = """
        INT. OFFICE - NIGHT
        Человек подходит к столу.

        EXT. STREET - DAY
        Женщина идёт к двери.
        """
        let initial = await parser.parseBundle(initialDescription, markedObjects: [])
        let changedDescription = """
        INT. OFFICE - NIGHT
        Человек подходит к столу.

        EXT. STREET - DAY
        Женщина быстро идёт к двери.
        """

        let changed = await parser.parseBundle(
            changedDescription,
            markedObjects: [],
            mode: .full,
            previousState: initial.documentState
        )

        XCTAssertEqual(initial.bundleScript.scenes.count, 2)
        XCTAssertEqual(changed.bundleScript.scenes.count, 2)
        XCTAssertEqual(
            initial.documentState.stitchStates.first?.chunkLedger,
            changed.documentState.stitchStates.first?.chunkLedger
        )
        XCTAssertNotEqual(
            initial.documentState.stitchStates.last?.sourceText,
            changed.documentState.stitchStates.last?.sourceText
        )
    }

    func testBundlePipelinePreservesDialogueThenPutDownPattern() async throws {
        let restoreRuntimeMode = setRuntimeMode("v8_hotfix")
        defer { restoreRuntimeMode() }

        let description = "Первый актёр говорит: «Положи коробку сюда, потом разберём», после чего второй кладёт коробку на стойку."
        let pipeline = makeBundlePipeline(
            result: ScenePlanProviderResult(
                plan: ScenePlanIR(
                    actors: [
                        .init(ref: "first", type: .human),
                        .init(ref: "second", type: .human),
                    ],
                    objects: [
                        .init(ref: "object_box", type: .generic, relativePosition: .center, name: "коробка"),
                        .init(ref: "object_counter", type: .shelf, relativePosition: .right, name: "стойка"),
                    ],
                    beats: [
                        .init(
                            ref: "beat_1",
                            actions: [
                                .init(
                                    actorRef: "first",
                                    type: .talk,
                                    resultingPose: .standing,
                                    dialogue: "Положи коробку сюда, потом разберём"
                                ),
                            ]
                        ),
                        .init(
                            ref: "beat_2",
                            actions: [
                                .init(
                                    actorRef: "second",
                                    type: .putDown,
                                    targetRef: "object_counter",
                                    resultingPose: .standing,
                                    holdingObjectRef: "object_box",
                                    sourceText: "второй кладёт коробку на стойку"
                                ),
                            ]
                        ),
                    ],
                    spatialRelations: [],
                    referenceBindings: .init(actorBindings: ["first": "actor_1", "second": "actor_2"])
                ),
                usedLegacySceneScriptBridge: false
            )
        )

        let result = await pipeline.parse(
            description: description,
            markedObjects: [],
            mode: SceneBundleParseMode.full,
            previousState: nil as ScriptDocumentState?
        ) { text, _, _ in
            ParsingResult(
                script: SceneScript(actors: [], objects: [], beats: [], spatialRelations: [], originalDescription: text),
                diagnostics: .empty
            )
        }

        let script = try XCTUnwrap(result.activeSceneScript)
        let putDownDebug = script.beats.enumerated().map { index, beat in
            "\(index):" + beat.actions.map {
                "\($0.type.rawValue)|\($0.actorId)|\($0.target ?? "nil")|\($0.dialogue ?? $0.sourceText ?? "nil")"
            }.joined(separator: "+")
        }.joined(separator: " / ") + " || " + result.chunkDiagnostics.flatMap(\.reasonCodes).joined(separator: ",")
        XCTAssertEqual(script.actors.count, 2)
        XCTAssertEqual(script.beats.count, 2, putDownDebug)
        XCTAssertFalse(result.chunkDiagnostics.contains { $0.usedFallbackPlanner })

        let talkAction = script.beats.flatMap { $0.actions }.first(where: { $0.type == SceneAction.ActionType.talk })
        XCTAssertEqual(talkAction?.dialogue, "Положи коробку сюда, потом разберём", putDownDebug)

        let putDownAction = try XCTUnwrap(script.beats.flatMap { $0.actions }.first(where: { $0.type == SceneAction.ActionType.putDown }))
        XCTAssertNotNil(putDownAction.target)
        XCTAssertNotNil(putDownAction.holdingObject)
        XCTAssertEqual(script.objects.count, 2)
    }

    func testBundlePipelinePreservesDialoguePickUpGiveToThirdPattern() async throws {
        let restoreRuntimeMode = setRuntimeMode("v8_hotfix")
        defer { restoreRuntimeMode() }

        let description = "Таня говорит: «Передай конверт третьему». Рома отвечает: «Сейчас передам». Затем второй берёт письмо и передаёт его Яне, после чего письмо получает третий."
        let pipeline = makeBundlePipeline(
            result: ScenePlanProviderResult(
                plan: ScenePlanIR(
                    actors: [
                        .init(ref: "first", type: .human, name: "таня"),
                        .init(ref: "second", type: .human, name: "рома"),
                        .init(ref: "third", type: .human, name: "яна"),
                    ],
                    objects: [
                        .init(ref: "object_letter", type: .generic, relativePosition: .center, name: "письмо"),
                    ],
                    beats: [
                        .init(
                            ref: "beat_1",
                            actions: [
                                .init(actorRef: "first", type: .talk, resultingPose: .standing, dialogue: "Передай конверт третьему"),
                                .init(actorRef: "second", type: .talk, resultingPose: .standing, dialogue: "Сейчас передам"),
                            ]
                        ),
                        .init(
                            ref: "beat_2",
                            actions: [
                                .init(actorRef: "second", type: .pickUp, targetRef: "object_letter", resultingPose: .standing, holdingObjectRef: "object_letter"),
                            ]
                        ),
                        .init(
                            ref: "beat_3",
                            actions: [
                                .init(actorRef: "second", type: .give, targetRef: "third", resultingPose: .standing, holdingObjectRef: "object_letter"),
                            ]
                        ),
                    ],
                    spatialRelations: [],
                    referenceBindings: .init(actorBindings: ["first": "actor_1", "second": "actor_2", "third": "actor_3"])
                ),
                usedLegacySceneScriptBridge: false
            )
        )

        let result = await pipeline.parse(
            description: description,
            markedObjects: [],
            mode: SceneBundleParseMode.full,
            previousState: nil as ScriptDocumentState?
        ) { text, _, _ in
            ParsingResult(
                script: SceneScript(actors: [], objects: [], beats: [], spatialRelations: [], originalDescription: text),
                diagnostics: .empty
            )
        }

        let script = try XCTUnwrap(result.activeSceneScript)
        let transferDebug = script.beats.enumerated().map { index, beat in
            "\(index):" + beat.actions.map {
                "\($0.type.rawValue)|\($0.actorId)|\($0.target ?? "nil")|\($0.dialogue ?? $0.sourceText ?? "nil")"
            }.joined(separator: "+")
        }.joined(separator: " / ") + " || " + result.chunkDiagnostics.flatMap(\.reasonCodes).joined(separator: ",")
        XCTAssertEqual(script.actors.count, 3)
        XCTAssertEqual(script.beats.count, 3, transferDebug)
        XCTAssertFalse(result.chunkDiagnostics.contains { $0.usedFallbackPlanner })

        let talkActions = script.beats.flatMap { $0.actions }.filter { $0.type == SceneAction.ActionType.talk }
        XCTAssertEqual(talkActions.count, 2, transferDebug)

        let pickUpAction = try XCTUnwrap(script.beats.flatMap { $0.actions }.first(where: { $0.type == SceneAction.ActionType.pickUp }))
        XCTAssertEqual(pickUpAction.holdingObject, script.objects.first?.id)

        let giveAction = try XCTUnwrap(script.beats.flatMap { $0.actions }.first(where: { $0.type == SceneAction.ActionType.give }))
        XCTAssertNotNil(giveAction.target)
        XCTAssertEqual(giveAction.holdingObject, script.objects.first?.id)
    }

    func testDemoScenarioMaterializesNamedDialogueLookAtAndPhoneTransfer() async throws {
        let modeKey = "scene_generator_v9_runtime_mode"
        let defaults = UserDefaults.standard
        let oldMode = defaults.string(forKey: modeKey)
        defaults.set("v8_hotfix", forKey: modeKey)
        defer {
            if let oldMode {
                defaults.set(oldMode, forKey: modeKey)
            } else {
                defaults.removeObject(forKey: modeKey)
            }
        }

        let description = """
        МАРИНА и ОЛЕГ идут навстречу друг другу в тихом офисе. Марина останавливается у стола; на столе лежит телефон. Олег смотрит на телефон.

        МАРИНА: Он опять звонил?
        ОЛЕГ: Три раза. Я не стал брать.
        МАРИНА: Тогда дай сюда, я сама всё решу.

        Олег берёт телефон со стола и передаёт его Марине.
        """
        let pipeline = makeBundlePipeline(result: nil)

        let result = await pipeline.parse(
            description: description,
            markedObjects: [],
            mode: SceneBundleParseMode.full,
            previousState: nil as ScriptDocumentState?,
            executionPolicy: .monolithicDefault
        ) { text, _, _ in
            ParsingResult(
                script: SceneScript(actors: [], objects: [], beats: [], spatialRelations: [], originalDescription: text),
                diagnostics: .empty
            )
        }

        let reasonCodes = result.chunkDiagnostics.flatMap(\.reasonCodes)
        let script = try XCTUnwrap(result.activeSceneScript)
        let debugBeatSummary = script.beats.enumerated().map { index, beat in
            "\(index):" + beat.actions.map {
                "\($0.type.rawValue)|\($0.actorId)|\($0.target ?? "nil")|\($0.sourceText ?? $0.dialogue ?? $0.fallbackText ?? "nil")"
            }.joined(separator: "+")
        }.joined(separator: " / ")
        let planBeatSummary = result.documentState.bundlePlan.scenes.flatMap(\.plan.beats).enumerated().map { index, beat in
            "\(index):" + beat.actions.map {
                "\($0.type.rawValue)|\($0.actorRef)|\($0.targetRef ?? "nil")|\($0.sourceText ?? $0.dialogue ?? $0.fallbackText ?? "nil")"
            }.joined(separator: "+")
        }.joined(separator: " / ")
        let chunkBeatSummary = result.sceneChunks.flatMap(\.beatPatch).enumerated().map { index, beat in
            "\(index):" + beat.actions.map {
                "\($0.type.rawValue)|\($0.actorRef)|\($0.targetRef ?? "nil")|\($0.sourceText ?? $0.dialogue ?? $0.fallbackText ?? "nil")"
            }.joined(separator: "+")
        }.joined(separator: " / ")
        let sourceSummary = result.documentState.bundlePlan.scenes.map(\.sourceText)
            .joined(separator: " || ")
            .replacingOccurrences(of: "\n", with: "\\n")
        let debugSummary = "\(debugBeatSummary) || source=\(sourceSummary) || plan=\(planBeatSummary) || chunks=\(chunkBeatSummary)"
        XCTAssertTrue(reasonCodes.contains("v9.collective_motion_materialized"), debugSummary)
        XCTAssertTrue(reasonCodes.contains("v9.dialogue_event_materialized"), debugSummary)
        XCTAssertTrue(reasonCodes.contains("v9.look_at_action_materialized"), debugSummary)
        XCTAssertTrue(reasonCodes.contains("v9.transfer_action_materialized"), debugSummary)
        let marina = try XCTUnwrap(script.actors.first { $0.name == "Марина" })
        let oleg = try XCTUnwrap(script.actors.first { $0.name == "Олег" })
        let phone = try XCTUnwrap(script.objects.first { $0.type == .phone })

        XCTAssertEqual(script.actors.count, 2)

        let talkActions = script.actions.filter { $0.type == .talk }
        XCTAssertEqual(talkActions.count, 3)
        XCTAssertEqual(talkActions.map { $0.dialogue ?? "" }, [
            "Он опять звонил?",
            "Три раза. Я не стал брать.",
            "Тогда дай сюда, я сама всё решу.",
        ])
        XCTAssertEqual(talkActions.map(\.actorId), [marina.id, oleg.id, marina.id])

        let firstTalkBeatIndex = try XCTUnwrap(script.beats.firstIndex { beat in
            beat.actions.contains { $0.type == .talk }
        }, debugSummary)
        let walkBeatIndex = try XCTUnwrap(script.beats.firstIndex { beat in
            beat.actions.contains { $0.type == .walk }
        }, debugSummary)
        let lookAtBeatIndex = try XCTUnwrap(script.beats.firstIndex { beat in
            beat.actions.contains { $0.type == .lookAt }
        }, debugSummary)
        let transferBeatIndex = try XCTUnwrap(script.beats.firstIndex { beat in
            beat.actions.contains { $0.type == .pickUp || $0.type == .give }
        }, debugSummary)
        XCTAssertLessThan(walkBeatIndex, firstTalkBeatIndex, debugSummary)
        XCTAssertLessThan(lookAtBeatIndex, firstTalkBeatIndex, debugSummary)
        XCTAssertLessThan(firstTalkBeatIndex, transferBeatIndex, debugSummary)

        let lookAtAction = try XCTUnwrap(script.actions.first { $0.type == .lookAt })
        XCTAssertEqual(lookAtAction.actorId, oleg.id)
        XCTAssertEqual(lookAtAction.target, phone.id)

        let pickUpAction = try XCTUnwrap(script.actions.first { $0.type == .pickUp })
        XCTAssertEqual(pickUpAction.actorId, oleg.id)
        XCTAssertEqual(pickUpAction.target, phone.id)
        XCTAssertEqual(pickUpAction.holdingObject, phone.id)

        let giveAction = try XCTUnwrap(script.actions.first { $0.type == .give })
        XCTAssertEqual(giveAction.actorId, oleg.id)
        XCTAssertEqual(giveAction.target, marina.id)
        XCTAssertEqual(giveAction.holdingObject, phone.id)
        XCTAssertNotEqual(giveAction.actorId, giveAction.target)
    }

    func testDemoScenarioProviderPathRepairsTransferObjectsAndSourceOrder() async throws {
        let modeKey = "scene_generator_v9_runtime_mode"
        let defaults = UserDefaults.standard
        let oldMode = defaults.string(forKey: modeKey)
        defaults.set("v9_full", forKey: modeKey)
        defer {
            if let oldMode {
                defaults.set(oldMode, forKey: modeKey)
            } else {
                defaults.removeObject(forKey: modeKey)
            }
        }

        let description = """
        МАРИНА и ОЛЕГ идут навстречу друг другу в тихом офисе. Марина останавливается у стола; на столе лежит телефон. Олег смотрит на телефон.

        МАРИНА: Он опять звонил?
        ОЛЕГ: Три раза. Я не стал брать.
        МАРИНА: Тогда дай сюда, я сама всё решу.

        Олег берёт телефон со стола и передаёт его Марине.
        """

        let slotCatalog = SceneV9SlotCatalog(
            contractVersion: "sg_v9_slot_catalog_v1",
            actorSlots: [
                .init(slotID: "actor_slot_1", ref: "first", type: .human, name: "Марина"),
                .init(slotID: "actor_slot_2", ref: "second", type: .human, name: "Олег"),
            ],
            objectSlots: [
                .init(slotID: "object_slot_1", ref: "object_provider_phone_1", type: .phone, relativePosition: .unknown, markedObjectID: nil, name: nil),
                .init(slotID: "object_slot_2", ref: "object_provider_phone_2", type: .phone, relativePosition: .center, markedObjectID: nil, name: "телефон"),
            ],
            markedObjectSlots: [],
            beatSlots: [
                .init(slotID: "beat_slot_1", beatRef: "provider_beat_dialogue", phaseHint: "talk", order: 1, minDuration: 0.5),
                .init(slotID: "beat_slot_2", beatRef: "provider_beat_walk", phaseHint: "toward_each_other", order: 2, minDuration: nil),
                .init(slotID: "beat_slot_3", beatRef: "provider_beat_stand", phaseHint: "stand", order: 3, minDuration: 0.5),
                .init(slotID: "beat_slot_4", beatRef: "provider_beat_look", phaseHint: "look_at_object", order: 4, minDuration: 0.5),
                .init(slotID: "beat_slot_5", beatRef: "provider_beat_described", phaseHint: "described_action", order: 5, minDuration: 0.5),
                .init(slotID: "beat_slot_6", beatRef: "provider_beat_pick_up", phaseHint: "object_transfer", order: 6, minDuration: 0.5),
                .init(slotID: "beat_slot_7", beatRef: "provider_beat_give", phaseHint: "object_transfer", order: 7, minDuration: 0.5),
            ],
            actionTypes: SceneAction.ActionType.allCases,
            relationHints: []
        )
        let pipeline = makeBundlePipeline(
            result: nil,
            eventProvider: { _, _, _, _, _ in
                SceneV9EventProviderResult(
                    slotCatalog: slotCatalog,
                    eventTable: SceneV9EventTable(
                        contractVersion: "sg_v9_event_table_v1",
                        rows: [
                            .init(rowID: "row_1", beatSlot: "beat_slot_1", actorSlot: "actor_slot_1", actionType: .talk, dialogueText: "Он опять звонил?", sourceSpan: "МАРИНА: Он опять звонил?", confidence: 0.9),
                            .init(rowID: "row_2", beatSlot: "beat_slot_1", actorSlot: "actor_slot_2", actionType: .talk, dialogueText: "Три раза. Я не стал брать.", sourceSpan: "ОЛЕГ: Три раза. Я не стал брать.", confidence: 0.9),
                            .init(rowID: "row_3", beatSlot: "beat_slot_1", actorSlot: "actor_slot_1", actionType: .talk, dialogueText: "Тогда дай сюда, я сама всё решу.", sourceSpan: "МАРИНА: Тогда дай сюда, я сама всё решу.", confidence: 0.9),
                            .init(rowID: "row_4", beatSlot: "beat_slot_2", actorSlot: "actor_slot_2", actionType: .walk, targetSlot: "actor_slot_1", sourceSpan: "идут навстречу друг другу", confidence: 0.8),
                            .init(rowID: "row_5", beatSlot: "beat_slot_3", actorSlot: "actor_slot_1", actionType: .stand, confidence: 0.7),
                            .init(rowID: "row_6", beatSlot: "beat_slot_4", actorSlot: "actor_slot_2", actionType: .lookAt, targetSlot: "object_slot_2", sourceSpan: "Олег смотрит на телефон", confidence: 0.9),
                            .init(rowID: "row_7", beatSlot: "beat_slot_5", actorSlot: "actor_slot_1", actionType: .describedAction, describedActionText: "Марина: Олег смотрит на телефон", sourceSpan: "Марина: Олег смотрит на телефон", confidence: 0.5),
                            .init(rowID: "row_8", beatSlot: "beat_slot_6", actorSlot: "actor_slot_2", actionType: .pickUp, targetSlot: "object_slot_1", holdingObjectSlot: "object_slot_1", sourceSpan: "Олег берёт телефон со стола и передаёт его Марине", confidence: 0.9),
                            .init(rowID: "row_9", beatSlot: "beat_slot_7", actorSlot: "actor_slot_2", actionType: .give, targetSlot: "object_slot_2", confidence: 0.6),
                        ]
                    ),
                    reasonCodes: ["v9.event_provider_test_payload"]
                )
            }
        )

        let result = await pipeline.parse(
            description: description,
            markedObjects: [],
            mode: SceneBundleParseMode.full,
            previousState: nil as ScriptDocumentState?,
            executionPolicy: .monolithicDefault
        ) { text, _, _ in
            ParsingResult(
                script: SceneScript(actors: [], objects: [], beats: [], spatialRelations: [], originalDescription: text),
                diagnostics: .empty
            )
        }

        let reasonCodes = result.chunkDiagnostics.flatMap(\.reasonCodes)
        XCTAssertTrue(
            reasonCodes.contains("v9.event_provider_path_used") ||
                reasonCodes.contains("provider:v9.event_provider_path_used")
        )
        XCTAssertTrue(reasonCodes.contains("v9.give_recipient_repaired"))
        XCTAssertTrue(reasonCodes.contains("v9.redundant_described_action_dropped"))

        let script = try XCTUnwrap(result.activeSceneScript)
        let debugBeatSummary = script.beats.enumerated().map { index, beat in
            "\(index):" + beat.actions.map {
                "\($0.type.rawValue)|\($0.actorId)|\($0.target ?? "nil")|\($0.sourceText ?? $0.dialogue ?? $0.fallbackText ?? "nil")"
            }.joined(separator: "+")
        }.joined(separator: " / ")
        let planBeatSummary = result.documentState.bundlePlan.scenes.flatMap(\.plan.beats).enumerated().map { index, beat in
            "\(index):" + beat.actions.map {
                "\($0.type.rawValue)|\($0.actorRef)|\($0.targetRef ?? "nil")|\($0.sourceText ?? $0.dialogue ?? $0.fallbackText ?? "nil")"
            }.joined(separator: "+")
        }.joined(separator: " / ")
        let chunkBeatSummary = result.sceneChunks.flatMap(\.beatPatch).enumerated().map { index, beat in
            "\(index):" + beat.actions.map {
                "\($0.type.rawValue)|\($0.actorRef)|\($0.targetRef ?? "nil")|\($0.sourceText ?? $0.dialogue ?? $0.fallbackText ?? "nil")"
            }.joined(separator: "+")
        }.joined(separator: " / ")
        let sourceSummary = result.documentState.bundlePlan.scenes.map(\.sourceText)
            .joined(separator: " || ")
            .replacingOccurrences(of: "\n", with: "\\n")
        let debugSummary = "\(debugBeatSummary) || source=\(sourceSummary) || plan=\(planBeatSummary) || chunks=\(chunkBeatSummary)"
        let marina = try XCTUnwrap(script.actors.first { $0.name == "Марина" })
        let oleg = try XCTUnwrap(script.actors.first { $0.name == "Олег" })
        let phone = try XCTUnwrap(script.objects.first { $0.type == .phone })

        XCTAssertEqual(script.objects.filter { $0.type == .phone }.count, 1)
        XCTAssertTrue(script.objects.contains { $0.type == .table })
        XCTAssertFalse(script.actions.contains { $0.type == .describedAction })

        let walkActions = script.actions.filter { $0.type == .walk }
        XCTAssertEqual(Set(walkActions.map(\.actorId)), Set([marina.id, oleg.id]))

        let firstTalkBeatIndex = try XCTUnwrap(script.beats.firstIndex { $0.actions.contains { $0.type == .talk } })
        let walkBeatIndex = try XCTUnwrap(script.beats.firstIndex { $0.actions.contains { $0.type == .walk } })
        let lookAtBeatIndex = try XCTUnwrap(script.beats.firstIndex { $0.actions.contains { $0.type == .lookAt } })
        let transferBeatIndex = try XCTUnwrap(script.beats.firstIndex { $0.actions.contains { $0.type == .pickUp || $0.type == .give } })
        if !(lookAtBeatIndex < firstTalkBeatIndex) {
            XCTFail("debugSummary=\(debugSummary)")
        }
        XCTAssertLessThan(walkBeatIndex, firstTalkBeatIndex, debugSummary)
        XCTAssertLessThan(lookAtBeatIndex, firstTalkBeatIndex, debugSummary)
        XCTAssertLessThan(firstTalkBeatIndex, transferBeatIndex, debugSummary)

        let giveActions = script.actions.filter { $0.type == .give }
        XCTAssertEqual(giveActions.count, 1)
        let giveAction = try XCTUnwrap(giveActions.first)
        XCTAssertEqual(giveAction.actorId, oleg.id)
        XCTAssertEqual(giveAction.target, marina.id)
        XCTAssertEqual(giveAction.holdingObject, phone.id)
    }

    func testPartialProviderDialogueIsRecoveredFromSpeakerCues() async throws {
        let modeKey = "scene_generator_v9_runtime_mode"
        let defaults = UserDefaults.standard
        let oldMode = defaults.string(forKey: modeKey)
        defaults.set("v8_hotfix", forKey: modeKey)
        defer {
            if let oldMode {
                defaults.set(oldMode, forKey: modeKey)
            } else {
                defaults.removeObject(forKey: modeKey)
            }
        }

        let description = """
        МАРИНА: Он опять звонил?
        ОЛЕГ: Три раза. Я не стал брать.
        МАРИНА: Тогда дай сюда, я сама всё решу.
        """
        let partialPlan = ScenePlanIR(
            actors: [
                .init(ref: "first", type: .human, name: "Марина"),
                .init(ref: "second", type: .human, name: "Олег"),
            ],
            objects: [],
            beats: [
                .init(
                    ref: "beat_partial_dialogue",
                    actions: [
                        .init(
                            actorRef: "second",
                            type: .talk,
                            resultingPose: .standing,
                            dialogue: "Три раза. Я не стал брать.",
                            sourceText: "ОЛЕГ: Три раза. Я не стал брать."
                        ),
                    ]
                ),
            ],
            spatialRelations: [],
            referenceBindings: .init(actorBindings: ["first": "actor_1", "second": "actor_2"])
        )
        let pipeline = makeBundlePipeline(
            result: ScenePlanProviderResult(plan: partialPlan, usedLegacySceneScriptBridge: false)
        )

        let result = await pipeline.parse(
            description: description,
            markedObjects: [],
            mode: SceneBundleParseMode.full,
            previousState: nil as ScriptDocumentState?,
            executionPolicy: .monolithicDefault
        ) { text, _, _ in
            ParsingResult(
                script: SceneScript(actors: [], objects: [], beats: [], spatialRelations: [], originalDescription: text),
                diagnostics: .empty
            )
        }

        let script = try XCTUnwrap(result.activeSceneScript)
        let talkActions = script.actions.filter { $0.type == .talk }
        XCTAssertEqual(talkActions.map { $0.dialogue ?? "" }, [
            "Он опять звонил?",
            "Три раза. Я не стал брать.",
            "Тогда дай сюда, я сама всё решу.",
        ])
    }

    func testRuleFallbackKeepsTwoActorMotionAndUnsupportedTextActionAcrossChunks() async throws {
        let marker = MarkedObject(name: "компьютер", position: .zero)
        let description = """
        Первый актёр говорит второму актёру: «Встречаемся у рабочего компьютера».
        После этого первый актёр и второй актёр идут навстречу друг другу.
        Затем оба останавливаются рядом с рабочим компьютером.
        В конце второй актёр поправляет воротник и внимательно смотрит на экран.
        """
        let pipeline = makeBundlePipeline(result: nil)

        let result = await pipeline.parse(
            description: description,
            markedObjects: [marker],
            mode: SceneBundleParseMode.full,
            previousState: nil as ScriptDocumentState?
        ) { text, _, _ in
            let lowercased = text.lowercased()
            let actors = lowercased.contains("говорит")
                ? [
                    SceneActor(id: "actor_1", type: .human),
                    SceneActor(id: "actor_2", type: .human),
                ]
                : [
                    SceneActor(id: "actor_1", type: .human),
                ]
            let objects = lowercased.contains("компьютер")
                ? [
                    SceneObject(
                        id: marker.canonicalMarkedObjectID,
                        type: .generic,
                        name: "компьютер",
                        relativePosition: .center
                    ),
                ]
                : []
            let action: SceneAction
            if lowercased.contains("говорит") {
                action = SceneAction(
                    id: "action_1",
                    actorId: "actor_1",
                    type: .talk,
                    target: "actor_2",
                    resultingPose: .standing,
                    dialogue: "Встречаемся у рабочего компьютера"
                )
            } else if lowercased.contains("навстреч") {
                action = SceneAction(
                    id: "action_1",
                    actorId: "actor_1",
                    type: .walk,
                    resultingPose: .walking
                )
            } else {
                action = SceneAction(
                    id: "action_1",
                    actorId: "actor_1",
                    type: .stand,
                    resultingPose: .standing
                )
            }

            return ParsingResult(
                script: SceneScript(
                    actors: actors,
                    objects: objects,
                    beats: [SceneBeat(id: "beat_1", actions: [action])],
                    spatialRelations: [],
                    originalDescription: text
                ),
                diagnostics: .empty
            )
        }

        let script = try XCTUnwrap(result.activeSceneScript)
        let ruleDebug = script.beats.enumerated().map { index, beat in
            "\(index):" + beat.actions.map {
                "\($0.type.rawValue)|\($0.actorId)|\($0.target ?? "nil")|\($0.fallbackText ?? $0.sourceText ?? $0.dialogue ?? "nil")"
            }.joined(separator: "+")
        }.joined(separator: " / ") + " || actors=\(script.actors.map { "\($0.id):\($0.name ?? "nil")" }) || " + result.chunkDiagnostics.flatMap(\.reasonCodes).joined(separator: ",")
        XCTAssertEqual(script.actors.count, 2, ruleDebug)

        let walkActions = script.beats.flatMap(\.actions).filter { $0.type == .walk }
        XCTAssertGreaterThanOrEqual(walkActions.count, 2, ruleDebug)
        XCTAssertTrue(Set(walkActions.compactMap(\.target)).isSuperset(of: Set(["actor_1", "actor_2"])), ruleDebug)

        let stopActions = script.beats.flatMap(\.actions).filter { $0.type == .stop }
        XCTAssertEqual(stopActions.count, 2, ruleDebug)
        XCTAssertTrue(stopActions.allSatisfy { $0.target == marker.canonicalMarkedObjectID })

        let describedAction = try XCTUnwrap(script.beats.flatMap(\.actions).first(where: { $0.type == .describedAction }), ruleDebug)
        XCTAssertEqual(describedAction.actorId, "actor_2")
        XCTAssertTrue(describedAction.fallbackText?.contains("поправляет воротник") ?? false)
        XCTAssertTrue(result.chunkDiagnostics.flatMap(\.reasonCodes).contains("v1.unsupported_action_described"))
    }

    func testRuleFallbackMaterializesActiveSceneForDialogueOnlyInput() async throws {
        let description = "Кирилл: Я уже переслал отчёт. Таня: Тогда посмотри отчёт."
        let pipeline = makeBundlePipeline(result: nil)

        let result = await pipeline.parse(
            description: description,
            markedObjects: [],
            mode: SceneBundleParseMode.full,
            previousState: nil as ScriptDocumentState?
        ) { text, _, _ in
            ParsingResult(
                script: SceneScript(actors: [], objects: [], beats: [], spatialRelations: [], originalDescription: text),
                diagnostics: .empty
            )
        }

        let active = try XCTUnwrap(result.activeSceneScript)
        XCTAssertFalse(active.beats.isEmpty)
        XCTAssertFalse(active.actors.isEmpty)
    }

    func testCollectivePassByGetsExpandedForBothActors() async throws {
        let restoreRuntimeMode = setRuntimeMode("v8_hotfix")
        defer { restoreRuntimeMode() }

        let description = "Сначала первый актёр и второй актёр идут навстречу друг другу, затем оба проходят мимо монитора."
        let pipeline = makeBundlePipeline(
            result: ScenePlanProviderResult(
                plan: ScenePlanIR(
                    actors: [
                        .init(ref: "first", type: .human),
                        .init(ref: "second", type: .human),
                    ],
                    objects: [
                        .init(ref: "object_monitor", type: .generic, relativePosition: .center, name: "монитор"),
                    ],
                    beats: [
                        .init(
                            ref: "beat_1",
                            actions: [
                                .init(actorRef: "first", type: .walk, targetRef: "second", resultingPose: .walking, sourceText: "идут навстречу"),
                                .init(actorRef: "second", type: .walk, targetRef: "first", resultingPose: .walking, sourceText: "идут навстречу"),
                            ]
                        ),
                        .init(
                            ref: "beat_2",
                            actions: [
                                .init(actorRef: "first", type: .walk, resultingPose: .walking, sourceText: "оба проходят мимо монитора"),
                            ]
                        ),
                    ],
                    spatialRelations: [],
                    referenceBindings: .init(actorBindings: ["first": "actor_1", "second": "actor_2"])
                ),
                usedLegacySceneScriptBridge: false
            )
        )

        let result = await pipeline.parse(
            description: description,
            markedObjects: [],
            mode: SceneBundleParseMode.full,
            previousState: nil as ScriptDocumentState?
        ) { text, _, _ in
            ParsingResult(
                script: SceneScript(actors: [], objects: [], beats: [], spatialRelations: [], originalDescription: text),
                diagnostics: .empty
            )
        }

        let script = try XCTUnwrap(result.activeSceneScript)
        let passByActions = script.beats.flatMap(\.actions).filter { $0.type == .passBy }
        let debugSummary = script.beats.enumerated().map { index, beat in
            "\(index):" + beat.actions.map {
                "\($0.type.rawValue)|\($0.actorId)|\($0.target ?? "nil")|\($0.sourceText ?? "nil")"
            }.joined(separator: "+")
        }.joined(separator: " / ")
        let reasonSummary = result.chunkDiagnostics.flatMap(\.reasonCodes).joined(separator: ",")
        XCTAssertGreaterThanOrEqual(passByActions.count, 2, debugSummary + " || " + reasonSummary)
        XCTAssertTrue(passByActions.allSatisfy { $0.target != nil }, debugSummary + " || " + reasonSummary)
        XCTAssertTrue(result.chunkDiagnostics.flatMap(\.reasonCodes).contains("v9.collective_pass_by_expanded"), debugSummary + " || " + reasonSummary)
    }

    func testPlannerPreservesDialogueAndDescribedActionAsPlaybackAnnotations() throws {
        let marker = MarkedObject(name: "компьютер", position: .zero)
        let script = SceneScript(
            actors: [
                SceneActor(id: "actor_1", type: .human),
                SceneActor(id: "actor_2", type: .human),
            ],
            objects: [
                SceneObject(
                    id: marker.canonicalMarkedObjectID,
                    type: .generic,
                    name: "компьютер",
                    relativePosition: .center
                ),
            ],
            beats: [
                SceneBeat(
                    id: "beat_talk",
                    actions: [
                        SceneAction(
                            id: "action_talk",
                            actorId: "actor_1",
                            type: .talk,
                            target: "actor_2",
                            resultingPose: .standing,
                            sourceText: "Встречаемся у рабочего компьютера"
                        ),
                        SceneAction(
                            id: "action_stand",
                            actorId: "actor_2",
                            type: .stand,
                            resultingPose: .standing
                        ),
                    ],
                    minDuration: 0.5
                ),
                SceneBeat(
                    id: "beat_described",
                    actions: [
                        SceneAction(
                            id: "action_described",
                            actorId: "actor_2",
                            type: .describedAction,
                            target: marker.canonicalMarkedObjectID,
                            resultingPose: .standing,
                            fallbackText: "поправляет воротник и внимательно смотрит на экран"
                        ),
                    ],
                    minDuration: 0.5
                ),
            ],
            spatialRelations: [],
            originalDescription: "Два актёра говорят и выполняют текстовое действие у компьютера."
        )

        let planned = SpatialPlannerService.shared.planScene(
            script: script,
            cameraTransform: matrix_identity_float4x4,
            detectedObjects: [],
            availablePlanes: [],
            markedObjects: [marker]
        )

        let firstActor = try XCTUnwrap(planned.placedActors.first { $0.actorId == "actor_1" })
        let secondActor = try XCTUnwrap(planned.placedActors.first { $0.actorId == "actor_2" })

        XCTAssertEqual(firstActor.pathAnnotations.count, firstActor.path.count)
        XCTAssertEqual(secondActor.pathAnnotations.count, secondActor.path.count)
        XCTAssertEqual(firstActor.pathBeatIDs.count, firstActor.path.count)
        XCTAssertEqual(secondActor.pathBeatIDs.count, secondActor.path.count)

        let firstAnnotations = firstActor.pathAnnotations.compactMap { $0 }
        let secondAnnotations = secondActor.pathAnnotations.compactMap { $0 }
        XCTAssertTrue(firstAnnotations.contains(PlaybackPathAnnotation(kind: .dialogue, text: "Встречаемся у рабочего компьютера")))
        XCTAssertTrue(secondAnnotations.contains(PlaybackPathAnnotation(kind: .action, text: "поправляет воротник и внимательно смотрит на экран")))
        XCTAssertFalse(secondAnnotations.map(\.text).contains("stand"))
        XCTAssertTrue(firstActor.pathBeatIDs.compactMap { $0 }.contains("beat_talk"))
        XCTAssertTrue(secondActor.pathBeatIDs.compactMap { $0 }.contains("beat_described"))
    }

    @MainActor
    func testBeatTimelineBuildsSegmentsProgressAndCaptionFlags() throws {
        let marker = MarkedObject(name: "компьютер", position: .zero)
        let script = SceneScript(
            actors: [
                SceneActor(id: "actor_1", type: .human),
                SceneActor(id: "actor_2", type: .human),
            ],
            objects: [
                SceneObject(
                    id: marker.canonicalMarkedObjectID,
                    type: .generic,
                    name: "компьютер",
                    relativePosition: .center
                ),
            ],
            beats: [
                SceneBeat(
                    id: "beat_dialogue",
                    actions: [
                        SceneAction(
                            id: "action_talk",
                            actorId: "actor_1",
                            type: .talk,
                            sourceText: "Встречаемся у рабочего компьютера"
                        ),
                        SceneAction(
                            id: "action_stand",
                            actorId: "actor_2",
                            type: .stand
                        ),
                    ],
                    minDuration: 0.5
                ),
                SceneBeat(
                    id: "beat_motion",
                    actions: [
                        SceneAction(
                            id: "action_walk_1",
                            actorId: "actor_1",
                            type: .walk,
                            target: "actor_2",
                            direction: .toTarget,
                            resultingPose: .walking
                        ),
                        SceneAction(
                            id: "action_walk_2",
                            actorId: "actor_2",
                            type: .walk,
                            target: "actor_1",
                            direction: .toTarget,
                            resultingPose: .walking
                        ),
                    ],
                    minDuration: 0.5
                ),
                SceneBeat(
                    id: "beat_empty_stand",
                    actions: [
                        SceneAction(
                            id: "action_empty_stand",
                            actorId: "actor_2",
                            type: .stand
                        ),
                    ],
                    minDuration: 0.5
                ),
                SceneBeat(
                    id: "beat_action",
                    actions: [
                        SceneAction(
                            id: "action_described",
                            actorId: "actor_2",
                            type: .describedAction,
                            fallbackText: "поправляет воротник и внимательно смотрит на экран"
                        ),
                    ],
                    minDuration: 0.5
                ),
            ],
            spatialRelations: [],
            originalDescription: "Диалог, движение и действие."
        )

        let planned = SpatialPlannerService.shared.planScene(
            script: script,
            cameraTransform: matrix_identity_float4x4,
            detectedObjects: [],
            availablePlanes: [],
            markedObjects: [marker]
        )

        let viewModel = SceneGeneratorViewModel()
        let timeline = viewModel.buildBeatTimelineItems(for: planned, script: script)

        XCTAssertEqual(timeline.count, 3)
        XCTAssertFalse(timeline.map(\.beatID).contains("beat_empty_stand"))
        XCTAssertTrue(timeline[0].hasDialogueCaption)
        XCTAssertFalse(timeline[0].hasActionCaption)
        XCTAssertFalse(timeline[1].hasDialogueCaption)
        XCTAssertFalse(timeline[1].hasActionCaption)
        XCTAssertFalse(timeline[2].hasDialogueCaption)
        XCTAssertTrue(timeline[2].hasActionCaption)

        let middleOfSecondBeat = timeline[1].startTime + timeline[1].duration / 2
        let progress = viewModel.playbackProgressState(at: middleOfSecondBeat, items: timeline)
        XCTAssertEqual(progress.activeBeatIndex, 1)
        XCTAssertEqual(progress.beatProgress, 0.5, accuracy: 0.05)
    }

    @MainActor
    func testBeatTimelineKeepsHiddenNoOpDurationForPlaybackSync() throws {
        let script = SceneScript(
            actors: [
                SceneActor(id: "actor_1", type: .human, name: "Марина"),
            ],
            objects: [],
            beats: [
                SceneBeat(
                    id: "beat_visible_1",
                    actions: [
                        SceneAction(id: "action_1", actorId: "actor_1", type: .describedAction, fallbackText: "Марина входит")
                    ],
                    minDuration: 1
                ),
                SceneBeat(
                    id: "beat_hidden_wait",
                    actions: [
                        SceneAction(id: "action_wait", actorId: "actor_1", type: .stand)
                    ],
                    minDuration: 2
                ),
                SceneBeat(
                    id: "beat_visible_2",
                    actions: [
                        SceneAction(id: "action_2", actorId: "actor_1", type: .talk, dialogue: "Готово.")
                    ],
                    minDuration: 1
                ),
            ],
            spatialRelations: [],
            originalDescription: "Марина входит, ждёт и говорит."
        )
        let point = Position3D(x: 0, y: 0, z: -1)
        let planned = PlannedScene(
            placedActors: [
                PlannedScene.PlacedActor(
                    id: "placed_actor_1",
                    actorId: "actor_1",
                    type: .human,
                    name: "Марина",
                    initialPosition: point,
                    initialRotation: 0,
                    path: [point, point, point, point],
                    pathDurations: [1, 2, 1],
                    pathPoses: [.standing, .standing, .standing, .standing],
                    pathCameras: [nil, nil, nil, nil],
                    pathAnnotations: [
                        nil,
                        PlaybackPathAnnotation(kind: .action, text: "Марина входит"),
                        nil,
                        PlaybackPathAnnotation(kind: .dialogue, text: "Готово."),
                    ],
                    pathBeatIDs: [nil, "beat_visible_1", "beat_hidden_wait", "beat_visible_2"]
                ),
            ],
            placedObjects: []
        )

        let viewModel = SceneGeneratorViewModel()
        let timeline = viewModel.buildBeatTimelineItems(for: planned, script: script)

        XCTAssertEqual(timeline.map(\.beatID), ["beat_visible_1", "beat_visible_2"])
        XCTAssertEqual(timeline[0].startTime, 0, accuracy: 0.01)
        XCTAssertEqual(timeline[1].startTime, 3, accuracy: 0.01)

        let hiddenWaitState = viewModel.playbackProgressState(at: 1.5, items: timeline)
        XCTAssertEqual(hiddenWaitState.activeBeatIndex, 0)
        XCTAssertEqual(hiddenWaitState.beatProgress, 1, accuracy: 0.01)

        let secondBeatState = viewModel.playbackProgressState(at: 3.5, items: timeline)
        XCTAssertEqual(secondBeatState.activeBeatIndex, 1)
        XCTAssertEqual(secondBeatState.beatProgress, 0.5, accuracy: 0.05)
    }

    @MainActor
    func testActorRenderStylesAreDeterministicAndDistinctForHumans() throws {
        let script = SceneScript(
            actors: [
                SceneActor(id: "actor_1", type: .human, name: "Марина"),
                SceneActor(id: "actor_2", type: .human, name: "Олег"),
            ],
            objects: [],
            beats: [
                SceneBeat(
                    id: "beat_1",
                    actions: [
                        SceneAction(id: "action_1", actorId: "actor_1", type: .stand, sourceText: "Марина ждёт"),
                        SceneAction(id: "action_2", actorId: "actor_2", type: .stand, sourceText: "Олег ждёт"),
                    ]
                ),
            ],
            spatialRelations: [],
            originalDescription: "Марина и Олег ждут."
        )

        let planned = SpatialPlannerService.shared.planScene(
            script: script,
            cameraTransform: matrix_identity_float4x4,
            detectedObjects: [],
            availablePlanes: [],
            markedObjects: []
        )

        let marina = try XCTUnwrap(planned.placedActors.first { $0.actorId == "actor_1" })
        let oleg = try XCTUnwrap(planned.placedActors.first { $0.actorId == "actor_2" })
        let marinaStyle = SceneGeneratorViewModel.actorRenderStyle(for: marina, at: 0)
        let olegStyle = SceneGeneratorViewModel.actorRenderStyle(for: oleg, at: 1)

        XCTAssertNotEqual(marinaStyle.color, olegStyle.color)
        XCTAssertEqual(marinaStyle, SceneGeneratorViewModel.actorRenderStyle(for: marina, at: 0))
        XCTAssertEqual(olegStyle, SceneGeneratorViewModel.actorRenderStyle(for: oleg, at: 1))
    }

    @MainActor
    func testDialogueBeatSerializesSpeakerTurnsForPlayback() throws {
        let script = SceneScript(
            actors: [
                SceneActor(id: "actor_1", type: .human, name: "Марина"),
                SceneActor(id: "actor_2", type: .human, name: "Олег"),
            ],
            objects: [],
            beats: [
                SceneBeat(
                    id: "beat_dialogue",
                    actions: [
                        SceneAction(id: "talk_1", actorId: "actor_1", type: .talk, dialogue: "Он опять звонил?"),
                        SceneAction(id: "talk_2", actorId: "actor_2", type: .talk, dialogue: "Три раза. Я не стал брать."),
                        SceneAction(id: "talk_3", actorId: "actor_1", type: .talk, dialogue: "Тогда дай сюда, я сама всё решу."),
                    ],
                    minDuration: 0.5
                ),
            ],
            spatialRelations: [],
            originalDescription: "Марина и Олег разговаривают."
        )

        let planned = SpatialPlannerService.shared.planScene(
            script: script,
            cameraTransform: matrix_identity_float4x4,
            detectedObjects: [],
            availablePlanes: [],
            markedObjects: []
        )

        func dialogueStarts(for actor: PlannedScene.PlacedActor) -> [(text: String, start: TimeInterval)] {
            var elapsed: TimeInterval = 0
            var starts: [(String, TimeInterval)] = []
            for segmentIndex in 0..<actor.pathDurations.count {
                let annotationIndex = segmentIndex + 1
                if actor.pathAnnotations.indices.contains(annotationIndex),
                   let annotation = actor.pathAnnotations[annotationIndex],
                   annotation.kind == .dialogue {
                    starts.append((annotation.text, elapsed))
                }
                elapsed += actor.pathDurations[segmentIndex]
            }
            return starts
        }

        let marina = try XCTUnwrap(planned.placedActors.first { $0.actorId == "actor_1" })
        let oleg = try XCTUnwrap(planned.placedActors.first { $0.actorId == "actor_2" })
        let serializedTurns = (dialogueStarts(for: marina) + dialogueStarts(for: oleg))
            .sorted { lhs, rhs in lhs.start < rhs.start }
        XCTAssertEqual(
            serializedTurns.map(\.text),
            [
                "Он опять звонил?",
                "Три раза. Я не стал брать.",
                "Тогда дай сюда, я сама всё решу.",
            ]
        )
        XCTAssertEqual(serializedTurns.count, 3)
        for pair in zip(serializedTurns, serializedTurns.dropFirst()) {
            XCTAssertLessThan(pair.0.start, pair.1.start)
        }

        let marinaDuration = marina.pathDurations.reduce(0, +)
        let olegDuration = oleg.pathDurations.reduce(0, +)
        XCTAssertEqual(marinaDuration, olegDuration, accuracy: 0.01)
        XCTAssertTrue((marina.pathDurations + oleg.pathDurations).allSatisfy { $0 > 0 })

        let viewModel = SceneGeneratorViewModel()
        let timeline = viewModel.buildBeatTimelineItems(for: planned, script: script)
        XCTAssertEqual(timeline.count, 1)
        XCTAssertEqual(timeline[0].duration, marinaDuration, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(timeline[0].duration, script.beats[0].minDuration ?? 0)
    }

    @MainActor
    func testCombinedPickUpGiveCaptionsAreActionSpecific() throws {
        let sourceText = "Олег берёт телефон со стола и передаёт его Марине"
        let script = SceneScript(
            actors: [
                SceneActor(id: "actor_1", type: .human, name: "Марина"),
                SceneActor(id: "actor_2", type: .human, name: "Олег"),
            ],
            objects: [
                SceneObject(id: "object_phone", type: .phone, name: "телефон", relativePosition: .unknown),
            ],
            beats: [
                SceneBeat(
                    id: "beat_transfer",
                    actions: [
                        SceneAction(id: "pick_1", actorId: "actor_2", type: .pickUp, target: "object_phone", holdingObject: "object_phone", sourceText: sourceText),
                        SceneAction(id: "give_1", actorId: "actor_2", type: .give, target: "actor_1", holdingObject: "object_phone", sourceText: sourceText),
                    ],
                    minDuration: 0.5
                ),
            ],
            spatialRelations: [],
            originalDescription: sourceText
        )

        let planned = SpatialPlannerService.shared.planScene(
            script: script,
            cameraTransform: matrix_identity_float4x4,
            detectedObjects: [],
            availablePlanes: [ScenePlaneSnapshot(alignment: .horizontal, y: -1.0)],
            markedObjects: []
        )

        let oleg = try XCTUnwrap(planned.placedActors.first { $0.actorId == "actor_2" })
        let actionCaptions = oleg.pathAnnotations.compactMap { annotation -> String? in
            guard annotation?.kind == .action else { return nil }
            return annotation?.text
        }

        XCTAssertEqual(actionCaptions.count, 2)
        XCTAssertEqual(actionCaptions[0], "Олег берёт телефон со стола")
        XCTAssertEqual(actionCaptions[1], "Олег передаёт его Марине")
        XCTAssertNotEqual(actionCaptions[0], actionCaptions[1])
    }

    @MainActor
    func testPlannerDoesNotExposeRawInternalActionCaption() throws {
        let script = SceneScript(
            actors: [
                SceneActor(id: "actor_1", type: .human, name: "Марина"),
            ],
            objects: [],
            beats: [
                SceneBeat(
                    id: "beat_described",
                    actions: [
                        SceneAction(
                            id: "action_described",
                            actorId: "actor_1",
                            type: .describedAction,
                            sourceText: "described_action"
                        ),
                    ],
                    minDuration: 0.5
                ),
            ],
            spatialRelations: [],
            originalDescription: "Марина действует без точной анимации."
        )

        let planned = SpatialPlannerService.shared.planScene(
            script: script,
            cameraTransform: matrix_identity_float4x4,
            detectedObjects: [],
            availablePlanes: [ScenePlaneSnapshot(alignment: .horizontal, y: -1.0)],
            markedObjects: []
        )

        let actor = try XCTUnwrap(planned.placedActors.first)
        let captions = actor.pathAnnotations.compactMap { $0?.text }
        XCTAssertFalse(captions.contains("described_action"))
        XCTAssertFalse(captions.contains("Описанное действие"))
    }

    func testV9RawDescribedActionRecoversHumanSourceSentence() async throws {
        let restoreRuntimeMode = setRuntimeMode("v9_full")
        defer { restoreRuntimeMode() }

        let description = """
        МАРИНА и ОЛЕГ идут навстречу друг другу в офисе. Марина останавливается у стола; на столе лежит телефон. Олег подходит с другой стороны стола и смотрит на телефон.

        МАРИНА: Он опять звонил?
        ОЛЕГ: Три раза. Я не стал брать.
        МАРИНА: Дай сюда, я сама всё решу.

        Марина на секунду задерживает взгляд на Олеге.
        Олег берёт телефон со стола и передаёт его Марине.
        """

        let slotCatalog = SceneV9SlotCatalog(
            contractVersion: "sg_v9_slot_catalog_v1",
            actorSlots: [
                .init(slotID: "actor_slot_1", ref: "first", type: .human, name: "Марина"),
                .init(slotID: "actor_slot_2", ref: "second", type: .human, name: "Олег"),
            ],
            objectSlots: [
                .init(slotID: "object_slot_1", ref: "object_table", type: .table, relativePosition: .unknown, markedObjectID: nil, name: "стол"),
                .init(slotID: "object_slot_2", ref: "object_phone", type: .phone, relativePosition: .unknown, markedObjectID: nil, name: "телефон"),
            ],
            markedObjectSlots: [],
            beatSlots: [
                .init(slotID: "beat_slot_1", beatRef: "beat_walk", phaseHint: "toward_each_other", order: 1, minDuration: 0.5),
                .init(slotID: "beat_slot_2", beatRef: "beat_look", phaseHint: "look_at_object", order: 2, minDuration: 0.5),
                .init(slotID: "beat_slot_3", beatRef: "beat_described", phaseHint: "described_action", order: 3, minDuration: 0.5),
            ],
            actionTypes: SceneAction.ActionType.allCases,
            relationHints: []
        )
        let pipeline = makeBundlePipeline(result: nil) { _, _, _, _, _ in
            SceneV9EventProviderResult(
                slotCatalog: slotCatalog,
                eventTable: SceneV9EventTable(
                    contractVersion: "sg_v9_event_table_v1",
                    rows: [
                        .init(rowID: "row_1", beatSlot: "beat_slot_1", actorSlot: "actor_slot_1", actionType: .walk, targetSlot: "actor_slot_2", sourceSpan: "МАРИНА и ОЛЕГ идут навстречу друг другу в офисе", confidence: 0.9),
                        .init(rowID: "row_2", beatSlot: "beat_slot_1", actorSlot: "actor_slot_2", actionType: .walk, targetSlot: "actor_slot_1", sourceSpan: "МАРИНА и ОЛЕГ идут навстречу друг другу в офисе", confidence: 0.9),
                        .init(rowID: "row_3", beatSlot: "beat_slot_2", actorSlot: "actor_slot_2", actionType: .lookAt, targetSlot: "object_slot_2", sourceSpan: "Олег подходит с другой стороны стола и смотрит на телефон", confidence: 0.9),
                        .init(rowID: "row_4", beatSlot: "beat_slot_3", actorSlot: "actor_slot_1", actionType: .describedAction, targetSlot: "object_slot_1", describedActionText: "described_action", sourceSpan: "described_action", confidence: 0.5),
                    ]
                ),
                reasonCodes: ["test.raw_described_payload"]
            )
        }

        let result = await pipeline.parse(
            description: description,
            markedObjects: [],
            mode: .full,
            previousState: nil as ScriptDocumentState?,
            executionPolicy: .monolithicDefault
        ) { text, _, _ in
            ParsingResult(
                script: SceneScript(
                    actors: [
                        SceneActor(id: "actor_1", type: .human, name: "Марина"),
                        SceneActor(id: "actor_2", type: .human, name: "Олег"),
                    ],
                    objects: [
                        SceneObject(id: "object_table", type: .table, name: "стол", relativePosition: .unknown),
                        SceneObject(id: "object_phone", type: .phone, name: "телефон", relativePosition: .unknown),
                    ],
                    beats: [],
                    spatialRelations: [],
                    originalDescription: text
                ),
                diagnostics: .empty
            )
        }

        let script = try XCTUnwrap(result.activeSceneScript)
        let described = try XCTUnwrap(script.actions.first { action in
            action.type == SceneAction.ActionType.describedAction
        })
        XCTAssertEqual(described.fallbackText, "Марина на секунду задерживает взгляд на Олеге")
        XCTAssertEqual(described.sourceText, "Марина на секунду задерживает взгляд на Олеге")
        XCTAssertFalse(script.actions.contains { $0.fallbackText == "described_action" || $0.sourceText == "described_action" })
        let reasonCodes = result.chunkDiagnostics.flatMap { $0.reasonCodes }
        XCTAssertTrue(reasonCodes.contains("v9.described_action_text_recovered"))
    }

    @MainActor
    func testDemoActionBeatsAreVisibleAndPhoneSitsOnTable() throws {
        let script = SceneScript(
            actors: [
                SceneActor(id: "actor_1", type: .human, name: "Марина"),
                SceneActor(id: "actor_2", type: .human, name: "Олег"),
            ],
            objects: [
                SceneObject(id: "object_1", type: .table, name: "стол", relativePosition: .unknown),
                SceneObject(id: "object_2", type: .phone, name: "телефон", relativePosition: .unknown),
            ],
            beats: [
                SceneBeat(
                    id: "beat_walk",
                    actions: [
                        SceneAction(id: "walk_1", actorId: "actor_1", type: .walk, target: "actor_2", direction: .towardEachOther),
                        SceneAction(id: "walk_2", actorId: "actor_2", type: .walk, target: "actor_1", direction: .towardEachOther),
                    ]
                ),
                SceneBeat(
                    id: "beat_look",
                    actions: [
                        SceneAction(id: "look_1", actorId: "actor_2", type: .lookAt, target: "object_2", sourceText: "Олег смотрит на телефон"),
                    ],
                    minDuration: 0.5
                ),
                SceneBeat(
                    id: "beat_pick",
                    actions: [
                        SceneAction(id: "pick_1", actorId: "actor_2", type: .pickUp, target: "object_2", holdingObject: "object_2", sourceText: "Олег берёт телефон со стола"),
                    ],
                    minDuration: 0.5
                ),
                SceneBeat(
                    id: "beat_give",
                    actions: [
                        SceneAction(id: "give_1", actorId: "actor_2", type: .give, target: "actor_1", holdingObject: "object_2", sourceText: "Олег передаёт телефон Марине"),
                    ],
                    minDuration: 0.5
                ),
            ],
            spatialRelations: [],
            originalDescription: "Марина и Олег идут навстречу. На столе лежит телефон. Олег смотрит, берёт и передаёт телефон."
        )

        let planned = SpatialPlannerService.shared.planScene(
            script: script,
            cameraTransform: matrix_identity_float4x4,
            detectedObjects: [],
            availablePlanes: [ScenePlaneSnapshot(alignment: .horizontal, y: -1.0)],
            markedObjects: []
        )

        let table = try XCTUnwrap(planned.placedObjects.first { $0.type == .table })
        let phone = try XCTUnwrap(planned.placedObjects.first { $0.type == .phone })
        let phoneTableOffset = simd_distance(
            SIMD2<Float>(phone.position.x, phone.position.z),
            SIMD2<Float>(table.position.x, table.position.z)
        )
        XCTAssertGreaterThan(phoneTableOffset, 0.04)
        XCTAssertLessThan(phoneTableOffset, 0.09)
        XCTAssertGreaterThan(phone.position.y, table.position.y + table.size.y / 2)

        let viewModel = SceneGeneratorViewModel()
        let timeline = viewModel.buildBeatTimelineItems(for: planned, script: script)
        let actionBeatIDs = Set(timeline.filter { $0.hasActionCaption }.map(\.beatID))
        XCTAssertTrue(actionBeatIDs.contains("beat_look"))
        XCTAssertTrue(actionBeatIDs.contains("beat_pick"))
        XCTAssertTrue(actionBeatIDs.contains("beat_give"))

        let oleg = try XCTUnwrap(planned.placedActors.first { $0.name == "Олег" })
        let actionAnnotations = oleg.pathAnnotations.compactMap { $0?.text }.joined(separator: " ")
        XCTAssertTrue(actionAnnotations.contains("смотрит"))
        XCTAssertTrue(actionAnnotations.contains("берёт"))
        XCTAssertTrue(actionAnnotations.contains("передаёт"))
    }

    func testEnterWithoutTargetCreatesVisibleInitialStep() throws {
        let script = SceneScript(
            actors: [
                SceneActor(id: "actor_1", type: .human, name: "Марина"),
                SceneActor(id: "actor_2", type: .human, name: "Олег"),
            ],
            objects: [],
            beats: [
                SceneBeat(
                    id: "beat_enter",
                    actions: [
                        SceneAction(id: "enter_1", actorId: "actor_2", type: .enter),
                    ],
                    minDuration: 0.5
                ),
            ],
            spatialRelations: [],
            originalDescription: "Олег входит сбоку."
        )

        let planned = SpatialPlannerService.shared.planScene(
            script: script,
            cameraTransform: matrix_identity_float4x4,
            detectedObjects: [],
            availablePlanes: [ScenePlaneSnapshot(alignment: .horizontal, y: -1.0)],
            markedObjects: []
        )

        let oleg = try XCTUnwrap(planned.placedActors.first { $0.actorId == "actor_2" })
        let enterIndex = try XCTUnwrap(oleg.pathBeatIDs.firstIndex(of: "beat_enter"))
        XCTAssertGreaterThan(enterIndex, 0)

        let before = oleg.path[enterIndex - 1]
        let after = oleg.path[enterIndex]
        let distance = simd_distance(
            SIMD3<Float>(before.x, before.y, before.z),
            SIMD3<Float>(after.x, after.y, after.z)
        )
        XCTAssertGreaterThan(distance, 0.35)
        XCTAssertGreaterThan(oleg.pathDurations[enterIndex - 1], 0.4)
    }

    func testOppositeSideTableCueMovesActorAcrossSupportObject() throws {
        let script = SceneScript(
            actors: [
                SceneActor(id: "actor_1", type: .human, name: "Марина"),
                SceneActor(id: "actor_2", type: .human, name: "Олег"),
            ],
            objects: [
                SceneObject(id: "object_table", type: .table, name: "стол", relativePosition: .unknown),
                SceneObject(id: "object_phone", type: .phone, name: "телефон", relativePosition: .unknown),
            ],
            beats: [
                SceneBeat(
                    id: "beat_walk",
                    actions: [
                        SceneAction(id: "walk_1", actorId: "actor_1", type: .walk, target: "actor_2", direction: .towardEachOther),
                        SceneAction(id: "walk_2", actorId: "actor_2", type: .walk, target: "actor_1", direction: .towardEachOther),
                    ]
                ),
                SceneBeat(
                    id: "beat_look",
                    actions: [
                        SceneAction(
                            id: "look_1",
                            actorId: "actor_2",
                            type: .lookAt,
                            target: "object_phone",
                            sourceText: "Олег обходит стол с другой стороны и смотрит на телефон"
                        ),
                    ],
                    minDuration: 0.5
                ),
            ],
            spatialRelations: [],
            originalDescription: "Олег обходит стол с другой стороны и смотрит на телефон."
        )

        let planned = SpatialPlannerService.shared.planScene(
            script: script,
            cameraTransform: matrix_identity_float4x4,
            detectedObjects: [],
            availablePlanes: [ScenePlaneSnapshot(alignment: .horizontal, y: -1.0)],
            markedObjects: []
        )

        let table = try XCTUnwrap(planned.placedObjects.first { $0.type == .table })
        let oleg = try XCTUnwrap(planned.placedActors.first { $0.actorId == "actor_2" })
        let lookIndex = try XCTUnwrap(oleg.pathBeatIDs.firstIndex(of: "beat_look"))
        XCTAssertGreaterThan(lookIndex, 0)

        let before = oleg.path[lookIndex - 1]
        let after = oleg.path[lookIndex]
        let beforeVector = SIMD2<Float>(before.x - table.position.x, before.z - table.position.z)
        let afterVector = SIMD2<Float>(after.x - table.position.x, after.z - table.position.z)
        XCTAssertLessThan(simd_dot(simd_normalize(beforeVector), simd_normalize(afterVector)), -0.25)
        XCTAssertGreaterThan(oleg.pathDurations[lookIndex - 1], 1.1)
    }

    func testPhoneOnMarkedTableUsesRaycastSurfaceY() throws {
        let tableMarker = MarkedObject(
            name: "стол",
            position: Position3D(x: -0.4, y: -0.2, z: -1.25)
        )
        let script = SceneScript(
            actors: [
                SceneActor(id: "actor_1", type: .human, name: "Олег"),
            ],
            objects: [
                SceneObject(id: tableMarker.canonicalMarkedObjectID, type: .table, name: "стол", relativePosition: .unknown),
                SceneObject(id: "object_phone", type: .phone, name: "телефон", relativePosition: .unknown),
            ],
            beats: [
                SceneBeat(
                    id: "beat_1",
                    actions: [
                        SceneAction(id: "action_1", actorId: "actor_1", type: .lookAt, target: "object_phone", sourceText: "Олег смотрит на телефон"),
                    ]
                ),
            ],
            spatialRelations: [],
            originalDescription: "На столе лежит телефон."
        )

        let planned = SpatialPlannerService.shared.planScene(
            script: script,
            cameraTransform: matrix_identity_float4x4,
            detectedObjects: [],
            availablePlanes: [ScenePlaneSnapshot(alignment: .horizontal, y: -1.0)],
            markedObjects: [tableMarker]
        )

        let table = try XCTUnwrap(planned.placedObjects.first { $0.type == .table })
        let phone = try XCTUnwrap(planned.placedObjects.first { $0.type == .phone })

        XCTAssertEqual(table.position.y, tableMarker.worldPosition.y, accuracy: 0.001)
        let phoneMarkerOffset = simd_distance(
            SIMD2<Float>(phone.position.x, phone.position.z),
            SIMD2<Float>(tableMarker.worldPosition.x, tableMarker.worldPosition.z)
        )
        XCTAssertGreaterThan(phoneMarkerOffset, 0.04)
        XCTAssertLessThan(phoneMarkerOffset, 0.09)
        XCTAssertGreaterThan(phone.position.y, tableMarker.worldPosition.y)
        XCTAssertLessThan(phone.position.y, tableMarker.worldPosition.y + 0.08)
    }

    func testSpatialPlannerUsesLightweightPlaneSnapshots() throws {
        let script = SceneScript(
            actors: [
                SceneActor(id: "actor_1", type: .human, name: "Марина"),
            ],
            objects: [],
            beats: [
                SceneBeat(
                    id: "beat_1",
                    actions: [
                        SceneAction(id: "action_1", actorId: "actor_1", type: .stand),
                    ]
                ),
            ],
            spatialRelations: [],
            originalDescription: "Марина стоит."
        )

        let planned = SpatialPlannerService.shared.planScene(
            script: script,
            cameraTransform: matrix_identity_float4x4,
            detectedObjects: [],
            availablePlanes: [ScenePlaneSnapshot(alignment: .horizontal, y: -0.42)],
            markedObjects: []
        )

        let actor = try XCTUnwrap(planned.placedActors.first)
        XCTAssertEqual(actor.initialPosition.y, -0.42, accuracy: 0.001)
    }

    @MainActor
    func testSceneGeneratorDoesNotAutoOpenScenarioEditorOnAppear() throws {
        let viewModel = SceneGeneratorViewModel(projectName: "no-auto-editor-\(UUID().uuidString)")

        viewModel.prepareWorkspace()

        XCTAssertFalse(viewModel.showInputSheet)
    }

    @MainActor
    func testSceneGeneratorInputValidationIsScopedAndWhitespaceAware() async {
        let viewModel = SceneGeneratorViewModel(projectName: "input-validation-\(UUID().uuidString)")

        viewModel.sceneDescription = " \n\t"
        XCTAssertEqual(viewModel.generationRequestState.phase, .input)
        XCTAssertEqual(viewModel.inputValidationMessage, viewModel.localizedCopy(.generatorInputInvalid))
        await viewModel.generateScene()

        XCTAssertEqual(viewModel.generationRequestState.phase, .terminalFailure)
        XCTAssertEqual(viewModel.generationRequestState.failure, .emptyInput)
        XCTAssertEqual(viewModel.inputValidationMessage, viewModel.localizedCopy(.generatorInputInvalid))
        XCTAssertEqual(viewModel.errorMessage, viewModel.localizedCopy(.generatorInputInvalid))

        viewModel.showInput()
        XCTAssertNil(viewModel.inputValidationMessage)

        viewModel.sceneDescription = "Актёр входит в кадр"
        await viewModel.generateScene()

        let firstRequestID = viewModel.generationRequestState.requestID
        let firstEpoch = viewModel.generationRequestState.epoch
        XCTAssertEqual(viewModel.generationRequestState.phase, .retryableFailure)
        XCTAssertEqual(viewModel.generationRequestState.failure, .arNotReady)
        XCTAssertNil(viewModel.inputValidationMessage)
        XCTAssertEqual(viewModel.errorMessage, viewModel.localizedCopy(.generatorErrorARNotReady))

        viewModel.showInput()
        viewModel.sceneDescription = "Второй актёр входит в кадр"
        await viewModel.generateScene()

        XCTAssertEqual(viewModel.generationRequestState.phase, .retryableFailure)
        XCTAssertEqual(viewModel.generationRequestState.failure, .arNotReady)
        XCTAssertNotEqual(viewModel.generationRequestState.requestID, firstRequestID)
        XCTAssertNotEqual(viewModel.generationRequestState.epoch, firstEpoch)
        XCTAssertTrue(viewModel.testingGenerationStateTrace.contains { $0.phase == .terminalFailure })
    }

    @MainActor
    func testSceneGeneratorDraftSurvivesSheetDismissalAndProjectReload() async throws {
        let projectName = "screenplay-draft-\(UUID().uuidString)"
        let viewModel = SceneGeneratorViewModel(projectName: projectName)
        defer {
            DBService.shared.deleteUnifiedSceneProject(named: projectName) { _ in }
        }

        let draft = "INT. ТИХАЯ КОМНАТА — ДЕНЬ\nМАРА: Привет 👋"
        viewModel.showInput()
        viewModel.sceneDescription = draft
        viewModel.showInputSheet = false
        viewModel.showInput()

        XCTAssertEqual(viewModel.sceneDescription, draft)
        XCTAssertTrue(viewModel.showInputSheet)
        XCTAssertNil(viewModel.inputValidationMessage)

        // `persistWorkspaceState` is the same owner-side path used by the
        // generator's background lifecycle. Awaiting the existing DEBUG seam
        // below coalesces with it and makes the reload assertion deterministic.
        viewModel.persistWorkspaceState()
        let saveResult = await viewModel.testingPersistProjectSnapshot()
        if case .failure(let failure) = saveResult {
            XCTFail("Draft snapshot failed: \(failure)")
        }

        let reloaded = SceneGeneratorViewModel(projectName: projectName, isNewProject: false)
        XCTAssertEqual(reloaded.sceneDescription, draft)
        XCTAssertNil(reloaded.inputValidationMessage)
    }

    @MainActor
    func testSceneGeneratorInputValidationUsesCharacterBoundaryAndRejectsInvalidText() {
        let viewModel = SceneGeneratorViewModel(projectName: "screenplay-input-contract-\(UUID().uuidString)")
        let maximum = SceneGeneratorViewModel.maximumSceneDescriptionCharacters

        viewModel.sceneDescription = " \n\t"
        XCTAssertEqual(viewModel.sceneDescriptionValidationIssue, .empty)
        XCTAssertFalse(viewModel.canSubmitScene)
        XCTAssertNotNil(viewModel.inputValidationMessage)

        viewModel.sceneDescription = String(repeating: "🙂", count: maximum)
        XCTAssertEqual(viewModel.sceneDescription.count, maximum)
        XCTAssertNil(viewModel.sceneDescriptionValidationIssue)
        XCTAssertTrue(viewModel.canSubmitScene)

        viewModel.sceneDescription = String(repeating: "🙂", count: maximum + 1)
        XCTAssertEqual(viewModel.sceneDescriptionValidationIssue, .tooLong(maximum: maximum))
        XCTAssertFalse(viewModel.canSubmitScene)
        XCTAssertEqual(viewModel.inputValidationMessage, "Используй не более 5\u{00A0}000 символов")

        viewModel.setPresentationLocale(Locale(identifier: "en"))
        viewModel.sceneDescription = String(repeating: "🙂", count: maximum + 1)
        XCTAssertEqual(viewModel.sceneDescriptionValidationIssue, .tooLong(maximum: maximum))
        XCTAssertEqual(viewModel.inputValidationMessage, "Use 5,000 characters or fewer")

        for invalid in [
            "Сцена\u{0001}",
            "Сцена\u{0000}",
            "Сцена\(String(UnicodeScalar(0xFDD0)!))"
        ] {
            viewModel.sceneDescription = invalid
            XCTAssertEqual(viewModel.sceneDescriptionValidationIssue, .invalidText, "Rejected input should be explicit")
            XCTAssertFalse(viewModel.canSubmitScene)
            XCTAssertEqual(
                viewModel.inputValidationMessage,
                "Remove unsupported hidden or control characters and invalid Unicode characters"
            )
        }

        viewModel.setPresentationLocale(Locale(identifier: "ru"))
        viewModel.sceneDescription = "Сцена\u{0001}"
        XCTAssertEqual(
            viewModel.inputValidationMessage,
            "Удали неподдерживаемые скрытые или управляющие символы и недопустимые Unicode-символы"
        )

        viewModel.sceneDescription = "INT. ROOM — DAY\nМАРА: Привет 👋"
        XCTAssertNil(viewModel.sceneDescriptionValidationIssue)
        XCTAssertNil(viewModel.inputValidationMessage)
        XCTAssertTrue(viewModel.canSubmitScene)
    }

    @MainActor
    func testSceneGeneratorRapidDoubleSubmitUsesOneRequestOwner() async {
        let viewModel = SceneGeneratorViewModel(projectName: "screenplay-single-submit-\(UUID().uuidString)")
        var cameraTransform = matrix_identity_float4x4
        cameraTransform.columns.3 = SIMD4<Float>(0, 1.5, 0, 1)
        viewModel.testingSetPlanningContext(
            cameraTransform: cameraTransform,
            planes: [ScenePlaneSnapshot(alignment: .horizontal, y: 0)]
        )
        viewModel.sceneDescription = "Марина стоит."
        viewModel.testingSetGenerationDelay(0.05)
        viewModel.testingResetGenerationStateTrace()

        let first = Task { @MainActor in
            await viewModel.generateScene()
        }
        for _ in 0..<100 where viewModel.generationStage != .reading {
            await Task.yield()
        }
        let second = Task { @MainActor in
            await viewModel.generateScene()
        }

        await first.value
        await second.value

        XCTAssertEqual(viewModel.testingGenerationOwnerCount, 1)
        XCTAssertEqual(viewModel.generationRequestState.phase, .success)
        XCTAssertEqual(
            viewModel.testingGenerationStateTrace.filter { $0.phase == .validating }.count,
            1
        )
    }

    @MainActor
    func testSceneGeneratorLeaderConsumesOneRequestEventAndCannotReplay() async {
        let viewModel = SceneGeneratorViewModel(projectName: "leader-event-\(UUID().uuidString)")
        viewModel.testingResetGenerationStateTrace()
        viewModel.testingStartGenerationLeaderFixture()

        let eventID = try! XCTUnwrap(viewModel.generationLeaderEventID)

        XCTAssertEqual(
            viewModel.testingGenerationStateTrace.map(\.phase),
            [.idle, .input, .validating, .accepted, .queued, .leader]
        )
        XCTAssertEqual(viewModel.generationLeaderEventID, eventID)
        XCTAssertEqual(viewModel.generationLeaderPhase, .three)
        XCTAssertTrue(viewModel.generationMotionEventLedger.hasConsumed(eventID))
        let revision = viewModel.generationLeaderPresentationRevision
        let requestID = try! XCTUnwrap(viewModel.generationRequestState.requestID)
        let epoch = try! XCTUnwrap(viewModel.generationRequestState.epoch)

        // The clarification continuation reuses UUID+epoch. Its accepted
        // edge therefore cannot replay or replace the active projection after
        // the real input→validating→accepted→queued→leader path.
        XCTAssertFalse(viewModel.testingBeginGenerationLeader(requestID: requestID, epoch: epoch))
        XCTAssertEqual(viewModel.generationLeaderPresentationRevision, revision)
        XCTAssertEqual(viewModel.generationLeaderPhase, .three)

        viewModel.testingClearGenerationLeader()
        XCTAssertNil(viewModel.generationLeaderPhase)
    }

    @MainActor
    func testSceneGeneratorLeaderReduceMotionStartsAtActionWithoutTravel() {
        let viewModel = SceneGeneratorViewModel(projectName: "leader-reduce-motion-\(UUID().uuidString)")
        viewModel.updateGenerationMotionPreferences(reduceMotion: true)
        viewModel.testingResetGenerationStateTrace()
        viewModel.testingStartGenerationLeaderFixture()

        XCTAssertEqual(
            viewModel.testingGenerationStateTrace.map(\.phase),
            [.idle, .input, .validating, .accepted, .queued, .leader]
        )
        XCTAssertEqual(viewModel.generationLeaderPhase, .action)
        let eventID = try! XCTUnwrap(viewModel.generationLeaderEventID)
        let requestID = try! XCTUnwrap(viewModel.generationRequestState.requestID)
        let epoch = try! XCTUnwrap(viewModel.generationRequestState.epoch)
        let revision = viewModel.generationLeaderPresentationRevision
        // The same accepted fixture request cannot consume its event again,
        // even when its owner is using the immediate Reduce Motion path.
        XCTAssertFalse(viewModel.testingBeginGenerationLeader(requestID: requestID, epoch: epoch))
        XCTAssertTrue(viewModel.generationMotionEventLedger.hasConsumed(eventID))
        XCTAssertEqual(viewModel.generationLeaderPresentationRevision, revision)
        XCTAssertEqual(viewModel.generationLeaderPhase, .action)
        viewModel.testingClearGenerationLeader()
    }

    func testSceneGenerationRequestStateTransitionMatrixIsExhaustive() throws {
        let requestID = UUID()
        let epoch: UInt = 17
        let states: [SceneGenerationRequestState.Phase: SceneGenerationRequestState] = [
            .idle: .idle,
            .input: .input(),
            .validating: .validating(requestID: requestID, epoch: epoch),
            .clarification: .clarification(requestID: requestID, epoch: epoch, message: "Уточните объект."),
            .accepted: .accepted(requestID: requestID, epoch: epoch),
            .leader: .leader(requestID: requestID, epoch: epoch),
            .queued: .queued(requestID: requestID, epoch: epoch),
            .generating: .generating(requestID: requestID, epoch: epoch, stage: .reading),
            .cancelling: .cancelling(requestID: requestID, epoch: epoch),
            .paused: .paused(requestID: requestID, epoch: epoch),
            .backgrounded: .backgrounded(requestID: requestID, epoch: epoch),
            .retryableFailure: .retryableFailure(requestID: requestID, epoch: epoch, failure: .arNotReady),
            .terminalFailure: .terminalFailure(requestID: requestID, epoch: epoch, failure: .parse),
            .success: .success(requestID: requestID, epoch: epoch),
        ]
        let phases = SceneGenerationRequestState.Phase.allCases
        let expectedTransitions: [SceneGenerationRequestState.Phase: Set<SceneGenerationRequestState.Phase>] = [
            .idle: [.input],
            .input: [.validating, .terminalFailure, .idle],
            .validating: [.clarification, .accepted, .cancelling, .retryableFailure, .terminalFailure],
            .clarification: [.input, .accepted, .validating, .idle],
            .accepted: [.queued, .cancelling, .retryableFailure],
            .leader: [.generating, .paused, .backgrounded, .cancelling, .retryableFailure, .terminalFailure],
            .queued: [.leader, .paused, .backgrounded, .cancelling, .retryableFailure, .terminalFailure],
            .generating: [.clarification, .paused, .backgrounded, .cancelling, .retryableFailure, .terminalFailure, .success],
            .cancelling: [.input, .idle, .backgrounded, .terminalFailure],
            .paused: [.queued, .generating, .backgrounded, .cancelling, .retryableFailure, .terminalFailure],
            .backgrounded: [.accepted, .queued, .generating, .paused, .cancelling, .retryableFailure, .terminalFailure, .input, .idle],
            .retryableFailure: [.validating, .input, .idle],
            .terminalFailure: [.input, .idle],
            .success: [.input, .idle],
        ]

        XCTAssertEqual(Set(states.keys), Set(phases))
        XCTAssertEqual(Set(expectedTransitions.keys), Set(phases))
        XCTAssertEqual(SceneGenerationRequestState.transitionTable, expectedTransitions)

        let wellFormedStates: [SceneGenerationRequestState.Phase: [SceneGenerationRequestState]] = [
            .idle: [.idle],
            .input: [.input()],
            .validating: [.validating(requestID: requestID, epoch: epoch)],
            .clarification: [.clarification(requestID: requestID, epoch: epoch, message: "Уточните объект.")],
            .accepted: [.accepted(requestID: requestID, epoch: epoch)],
            .leader: [.leader(requestID: requestID, epoch: epoch)],
            .queued: [.queued(requestID: requestID, epoch: epoch)],
            .generating: [
                .generating(requestID: requestID, epoch: epoch, stage: .reading),
                .generating(requestID: requestID, epoch: epoch, stage: .planning),
                .generating(requestID: requestID, epoch: epoch, stage: .placing),
            ],
            .cancelling: [.cancelling(requestID: requestID, epoch: epoch)],
            .paused: [.paused(requestID: requestID, epoch: epoch)],
            .backgrounded: [.backgrounded(requestID: requestID, epoch: epoch)],
            .retryableFailure: [
                .retryableFailure(requestID: requestID, epoch: epoch, failure: .arNotReady),
                .retryableFailure(requestID: requestID, epoch: epoch, failure: .network),
            ],
            .terminalFailure: [
                .emptyInputFailure(),
                .terminalFailure(requestID: requestID, epoch: epoch, failure: .parse),
                .terminalFailure(requestID: requestID, epoch: epoch, failure: .malformed),
                .terminalFailure(requestID: requestID, epoch: epoch, failure: .cancelled),
            ],
            .success: [.success(requestID: requestID, epoch: epoch)],
        ]

        func representativeState(
            for phase: SceneGenerationRequestState.Phase
        ) -> SceneGenerationRequestState {
            if phase == .terminalFailure {
                return .terminalFailure(requestID: requestID, epoch: epoch, failure: .parse)
            }
            return wellFormedStates[phase]!.first!
        }

        func validTarget(
            from fromPhase: SceneGenerationRequestState.Phase,
            to toPhase: SceneGenerationRequestState.Phase
        ) -> SceneGenerationRequestState {
            switch toPhase {
            case .idle:
                return .idle
            case .input:
                return .input()
            case .validating:
                return .validating(requestID: requestID, epoch: epoch)
            case .clarification:
                return .clarification(requestID: requestID, epoch: epoch, message: "Уточните объект.")
            case .accepted:
                return .accepted(requestID: requestID, epoch: epoch)
            case .leader:
                return .leader(requestID: requestID, epoch: epoch)
            case .queued:
                return .queued(requestID: requestID, epoch: epoch)
            case .generating:
                return .generating(requestID: requestID, epoch: epoch, stage: .reading)
            case .cancelling:
                return .cancelling(requestID: requestID, epoch: epoch)
            case .paused:
                return .paused(requestID: requestID, epoch: epoch)
            case .backgrounded:
                return .backgrounded(requestID: requestID, epoch: epoch)
            case .retryableFailure:
                return .retryableFailure(requestID: requestID, epoch: epoch, failure: .arNotReady)
            case .terminalFailure:
                if fromPhase == .input {
                    return .emptyInputFailure()
                }
                return .terminalFailure(requestID: requestID, epoch: epoch, failure: .parse)
            case .success:
                return .success(requestID: requestID, epoch: epoch)
            }
        }

        func stageRank(_ stage: SceneGenerationStage) -> Int {
            switch stage {
            case .reading: return 0
            case .planning: return 1
            case .placing: return 2
            }
        }

        // Every literal graph edge gets a concrete, well-formed payload pair.
        // This prevents an identity mask from making an impossible edge look
        // accepted merely because its phase bit is listed.
        for fromPhase in phases {
            for toPhase in expectedTransitions[fromPhase] ?? [] {
                let from = representativeState(for: fromPhase)
                let to = validTarget(from: fromPhase, to: toPhase)
                XCTAssertTrue(
                    SceneGenerationRequestState.canTransition(from: from, to: to),
                    "Listed edge is not realizable: \(fromPhase.rawValue) -> \(toPhase.rawValue)"
                )
            }
        }

        // Distinct unlisted phase pairs must reject every well-formed payload
        // variant, including stage and identityless empty-input variants.
        for fromPhase in phases {
            for toPhase in phases where fromPhase != toPhase {
                guard expectedTransitions[fromPhase]?.contains(toPhase) != true else { continue }
                for from in try XCTUnwrap(wellFormedStates[fromPhase]) {
                    for to in try XCTUnwrap(wellFormedStates[toPhase]) {
                        XCTAssertFalse(
                            SceneGenerationRequestState.canTransition(from: from, to: to),
                            "Unlisted edge admitted: \(fromPhase.rawValue) -> \(toPhase.rawValue)"
                        )
                    }
                }
            }
        }

        // Same-state updates are intentionally outside the phase graph.
        for phase in phases {
            for from in try XCTUnwrap(wellFormedStates[phase]) {
                for to in try XCTUnwrap(wellFormedStates[phase]) {
                    let expected: Bool
                    switch phase {
                    case .input, .cancelling:
                        expected = true
                    case .generating:
                        let fromRank = stageRank(try XCTUnwrap(from.stage))
                        let toRank = stageRank(try XCTUnwrap(to.stage))
                        expected = toRank >= fromRank
                    default:
                        expected = false
                    }
                    XCTAssertEqual(
                        SceneGenerationRequestState.canTransition(from: from, to: to),
                        expected,
                        "Unexpected same-state update for \(phase.rawValue)"
                    )
                }
            }
        }

        let reading = states[.generating]!
        let planning: SceneGenerationRequestState = .generating(
            requestID: requestID,
            epoch: epoch,
            stage: .planning
        )
        let placing: SceneGenerationRequestState = .generating(
            requestID: requestID,
            epoch: epoch,
            stage: .placing
        )
        XCTAssertTrue(SceneGenerationRequestState.canTransition(from: reading, to: planning))
        XCTAssertTrue(SceneGenerationRequestState.canTransition(from: planning, to: placing))
        XCTAssertFalse(SceneGenerationRequestState.canTransition(from: planning, to: reading))
        XCTAssertTrue(
            SceneGenerationRequestState.canTransition(
                from: states[.input]!,
                to: .emptyInputFailure()
            )
        )
        XCTAssertTrue(
            SceneGenerationRequestState.canTransition(
                from: states[.validating]!,
                to: .retryableFailure(requestID: requestID, epoch: epoch, failure: .arNotReady)
            )
        )
        XCTAssertTrue(
            SceneGenerationRequestState.canTransition(
                from: states[.validating]!,
                to: .terminalFailure(requestID: requestID, epoch: epoch, failure: .parse)
            )
        )
        XCTAssertTrue(
            SceneGenerationRequestState.canTransition(
                from: states[.validating]!,
                to: .cancelling(requestID: requestID, epoch: epoch)
            )
        )
        for phase in phases where states[phase]!.isExecutionInFlight && phase != .cancelling {
            XCTAssertTrue(
                SceneGenerationRequestState.canTransition(
                    from: states[phase]!,
                    to: .cancelling(requestID: requestID, epoch: epoch)
                ),
                "Teardown cannot cancel in-flight phase \(phase.rawValue)"
            )
        }
        XCTAssertTrue(
            SceneGenerationRequestState.canTransition(
                from: states[.cancelling]!,
                to: states[.cancelling]!
            )
        )

        for state in states.values {
            let encoded = try JSONEncoder().encode(state)
            XCTAssertEqual(try JSONDecoder().decode(SceneGenerationRequestState.self, from: encoded), state)
        }
    }

    func testSceneGenerationRequestStateRejectsInvalidAndStaleIdentityTransitions() {
        let requestID = UUID()
        let staleRequestID = UUID()
        let epoch: UInt = 23
        let current = SceneGenerationRequestState.generating(
            requestID: requestID,
            epoch: epoch,
            stage: .planning
        )
        let staleRequest = SceneGenerationRequestState.generating(
            requestID: staleRequestID,
            epoch: epoch,
            stage: .placing
        )
        let staleEpoch = SceneGenerationRequestState.generating(
            requestID: requestID,
            epoch: epoch + 1,
            stage: .placing
        )
        let malformedFailure = SceneGenerationRequestState(
            phase: .terminalFailure,
            requestID: requestID,
            epoch: epoch,
            failure: nil
        )
        let identitylessRetryableFailure = SceneGenerationRequestState(
            phase: .retryableFailure,
            failure: .arNotReady
        )
        let postSubmitRetryableFailure = SceneGenerationRequestState.retryableFailure(
            requestID: requestID,
            epoch: epoch,
            failure: .arNotReady
        )
        let identitylessParseFailure = SceneGenerationRequestState(
            phase: .terminalFailure,
            failure: .parse
        )
        let identityBearingEmptyInput = SceneGenerationRequestState(
            phase: .terminalFailure,
            requestID: requestID,
            epoch: epoch,
            failure: .emptyInput
        )
        let mismatchedIdentity = SceneGenerationRequestState(
            phase: .generating,
            requestID: requestID,
            stage: .placing
        )
        let identityBearingInput = SceneGenerationRequestState(
            phase: .input,
            requestID: requestID,
            epoch: epoch
        )
        let preRequestInput = SceneGenerationRequestState.input()

        XCTAssertFalse(SceneGenerationRequestState.canTransition(from: current, to: staleRequest))
        XCTAssertFalse(SceneGenerationRequestState.canTransition(from: current, to: staleEpoch))
        XCTAssertFalse(SceneGenerationRequestState.canTransition(from: current, to: malformedFailure))
        XCTAssertFalse(SceneGenerationRequestState.canTransition(from: current, to: identitylessRetryableFailure))
        XCTAssertFalse(SceneGenerationRequestState.canTransition(from: preRequestInput, to: postSubmitRetryableFailure))
        XCTAssertFalse(SceneGenerationRequestState.canTransition(from: current, to: identitylessParseFailure))
        XCTAssertFalse(SceneGenerationRequestState.canTransition(from: current, to: identityBearingEmptyInput))
        XCTAssertFalse(SceneGenerationRequestState.canTransition(from: current, to: mismatchedIdentity))
        XCTAssertFalse(SceneGenerationRequestState.canTransition(from: preRequestInput, to: identityBearingInput))
        XCTAssertNil(SceneGenerationRequestState.transition(from: current, to: staleRequest))
        XCTAssertEqual(current.phase, .generating)
        XCTAssertEqual(current.requestID, requestID)
        XCTAssertEqual(current.epoch, epoch)
    }

    @MainActor
    func testSceneGeneratorPublishesReadingPlanningPlacingAndSuccessTrace() async throws {
        let projectName = "generation-success-state-\(UUID().uuidString)"
        let viewModel = SceneGeneratorViewModel(projectName: projectName)
        addTeardownBlock { @MainActor in
            _ = await viewModel.teardownAndWait()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DBService.shared.deleteUnifiedSceneProject(named: projectName) { _ in
                    continuation.resume()
                }
            }
        }

        var cameraTransform = matrix_identity_float4x4
        cameraTransform.columns.3 = SIMD4<Float>(0, 1.5, 0, 1)
        viewModel.testingSetPlanningContext(
            cameraTransform: cameraTransform,
            planes: [ScenePlaneSnapshot(alignment: .horizontal, y: 0)]
        )
        viewModel.sceneDescription = "Марина стоит."
        viewModel.testingResetGenerationStateTrace()

        await viewModel.generateScene()

        XCTAssertEqual(viewModel.generationRequestState.phase, .success)
        XCTAssertNotNil(viewModel.generationRequestState.requestID)
        XCTAssertNotNil(viewModel.generationRequestState.epoch)
        XCTAssertFalse(viewModel.isGenerating)
        XCTAssertNil(viewModel.generationStage)
        XCTAssertNotNil(viewModel.plannedScene)

        let trace = viewModel.testingGenerationStateTrace
        let traceSignature = trace.map { state in
            "\(state.phase.rawValue):\(state.stage?.rawValue ?? "-")"
        }
        XCTAssertEqual(
            traceSignature,
            [
                "input:-",
                "input:-",
                "validating:-",
                "accepted:-",
                "queued:-",
                "leader:-",
                "generating:reading",
                "generating:reading",
                "generating:reading",
                "generating:planning",
                "generating:placing",
                "success:-",
            ]
        )
    }

    @MainActor
    func testSceneGeneratorMapsMissingCameraTransformToRetryableState() async {
        let viewModel = SceneGeneratorViewModel(projectName: "camera-position-state-\(UUID().uuidString)")
        viewModel.testingMarkARSessionReady()
        viewModel.sceneDescription = "Марина входит в кадр."
        viewModel.testingResetGenerationStateTrace()

        await viewModel.generateScene()

        XCTAssertEqual(viewModel.generationRequestState.phase, .retryableFailure)
        XCTAssertEqual(viewModel.generationRequestState.failure, .cameraPosition)
        XCTAssertFalse(viewModel.isGenerating)
        XCTAssertTrue(viewModel.testingGenerationStateTrace.contains { $0.phase == .validating })
    }

    @MainActor
    func testSceneGeneratorClarificationTraceIsTypedAndNotTerminalError() async {
        let viewModel = SceneGeneratorViewModel(projectName: "clarification-state-\(UUID().uuidString)")
        var cameraTransform = matrix_identity_float4x4
        cameraTransform.columns.3 = SIMD4<Float>(0, 1.5, 0, 1)
        viewModel.testingSetPlanningContext(
            cameraTransform: cameraTransform,
            planes: [ScenePlaneSnapshot(alignment: .horizontal, y: 0)]
        )
        viewModel.sceneDescription = "Марина подходит к одному из стульев."
        viewModel.testingSetGenerationDelay(60)
        viewModel.testingResetGenerationStateTrace()

        let generation = Task { @MainActor in
            await viewModel.generateScene()
        }
        for _ in 0..<100 where viewModel.generationStage != .reading {
            await Task.yield()
        }
        XCTAssertEqual(viewModel.generationStage, .reading)

        XCTAssertTrue(
            viewModel.testingPublishParserClarification(
                message: "Уточните, какой стул имеется в виду."
            )
        )
        XCTAssertEqual(viewModel.generationRequestState.phase, .clarification)
        XCTAssertNotNil(viewModel.generationRequestState.clarificationMessage)
        XCTAssertNil(viewModel.generationRequestState.failure)
        XCTAssertFalse(viewModel.testingGenerationStateTrace.contains { $0.phase == .terminalFailure })

        _ = await viewModel.teardownAndWait()
        await generation.value
        XCTAssertTrue(viewModel.testingGenerationStateTrace.contains { $0.phase == .clarification })
        XCTAssertFalse(viewModel.testingGenerationStateTrace.contains { $0.phase == .success })
    }

    @MainActor
    func testARFailureMessageUsesContainerPresentationLocale() async {
        let viewModel = SceneGeneratorViewModel()
        let container = ARSceneContainer(
            viewModel: viewModel,
            presentationLocale: Locale(identifier: "en")
        )
        viewModel.setPresentationLocale(Locale(identifier: "en"))
        let coordinator = container.makeCoordinator()
        let error = NSError(
            domain: "ARSession",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unsupported configuration."]
        )

        coordinator.session(ARSession(), didFailWithError: error)
        await Task.yield()

        XCTAssertEqual(viewModel.errorMessage, "AR ERROR: Unsupported configuration.")
    }

    @MainActor
    func testSceneGeneratorOverlayPassesTouchesDuringMarkingButKeepsStoryboardEditorInteractive() throws {
        XCTAssertTrue(
            SceneGeneratorViewModel.shouldPassTouchesThroughSwiftUIOverlay(
                isMarkingMode: true,
                hasActiveStoryboardEditor: false
            )
        )
        XCTAssertFalse(
            SceneGeneratorViewModel.shouldPassTouchesThroughSwiftUIOverlay(
                isMarkingMode: false,
                hasActiveStoryboardEditor: true
            )
        )
        XCTAssertFalse(
            SceneGeneratorViewModel.shouldPassTouchesThroughSwiftUIOverlay(
                isMarkingMode: false,
                hasActiveStoryboardEditor: false
            )
        )
    }

    @MainActor
    func testSceneGeneratorViewModelProcessesLightweightFrameSnapshotInDemoMode() throws {
        let defaults = UserDefaults.standard
        let depthKey = "scene_generator_lidar_marking_enabled"
        let oldDepth = defaults.object(forKey: depthKey)
        defer {
            if let oldDepth {
                defaults.set(oldDepth, forKey: depthKey)
            } else {
                defaults.removeObject(forKey: depthKey)
            }
        }
        defaults.removeObject(forKey: depthKey)

        let viewModel = SceneGeneratorViewModel()
        viewModel.toggleMarkingMode()
        XCTAssertFalse(viewModel.isDepthMarkingEnabled)

        viewModel.processARFrameSnapshot(
            cameraTransform: matrix_identity_float4x4,
            planeSnapshots: [ScenePlaneSnapshot(alignment: .horizontal, y: -1.0)],
            timestamp: 1,
            capturedImage: nil
        )

        XCTAssertTrue(viewModel.isARSessionReady)
    }

    @MainActor
    func testSceneGeneratorARInterruptionRecoveryRequiresPostInterruptionGenerationAndPlane() throws {
        let viewModel = SceneGeneratorViewModel()
        let plane = ScenePlaneSnapshot(alignment: .horizontal, y: -1.0)

        viewModel.processARFrameSnapshot(
            cameraTransform: matrix_identity_float4x4,
            planeSnapshots: [plane],
            timestamp: 1
        )
        XCTAssertTrue(viewModel.isARSessionReady)

        viewModel.handleARSessionInterruption(generation: 1)
        XCTAssertTrue(viewModel.isARSessionInterrupted)
        XCTAssertFalse(viewModel.isARSessionReady)
        XCTAssertEqual(viewModel.statusMessage, "КАМЕРА ПРИОСТАНОВЛЕНА")

        viewModel.handleARSessionInterruptionEnded(generation: 2)
        XCTAssertFalse(viewModel.isARSessionInterrupted)
        XCTAssertTrue(viewModel.isARSessionRecovering)
        XCTAssertFalse(viewModel.isARSessionReady)
        XCTAssertEqual(viewModel.statusMessage, "ВОЗВРАЩАЮСЬ В КАДР…")

        // A pre-ended frame may still be queued on MainActor; its generation
        // must not complete recovery after the interruption-ended callback.
        viewModel.processARFrameSnapshot(
            cameraTransform: matrix_identity_float4x4,
            planeSnapshots: [plane],
            timestamp: 2,
            generation: 1
        )
        XCTAssertTrue(viewModel.isARSessionRecovering)
        XCTAssertFalse(viewModel.isARSessionReady)

        viewModel.processARFrameSnapshot(
            cameraTransform: matrix_identity_float4x4,
            planeSnapshots: [plane],
            timestamp: 3,
            generation: 2
        )
        XCTAssertFalse(viewModel.isARSessionRecovering)
        XCTAssertTrue(viewModel.isARSessionReady)
    }

    @MainActor
    func testSceneGeneratorCameraHintsMapARInterfaceOrientationLikeCameraManager() throws {
        let viewModel = SceneGeneratorViewModel()

        XCTAssertEqual(viewModel.testingARCameraAnalysisOrientation, .right)

        viewModel.testingSetARInterfaceOrientation(.landscapeLeft)
        XCTAssertEqual(viewModel.testingARCameraAnalysisOrientation, .down)

        viewModel.testingSetARInterfaceOrientation(.landscapeRight)
        XCTAssertEqual(viewModel.testingARCameraAnalysisOrientation, .up)

        viewModel.processARFrameSnapshot(
            cameraTransform: matrix_identity_float4x4,
            planeSnapshots: [],
            timestamp: 1,
            capturedImage: nil,
            interfaceOrientation: .portraitUpsideDown,
            displayTransform: CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0.1, ty: 0.2)
        )

        XCTAssertEqual(viewModel.testingARCameraAnalysisOrientation, .left)
        XCTAssertEqual(viewModel.hintDisplayTransform, CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0.1, ty: 0.2))
    }

    @MainActor
    func testSceneGeneratorHintPauseLifecycleStopsAndResumesLiveAnalysis() throws {
        let viewModel = SceneGeneratorViewModel()

        viewModel.toggleHintsEnabled()
        viewModel.startHintPauseAnalysis()

        XCTAssertTrue(viewModel.isHintsEnabled)
        XCTAssertTrue(viewModel.isHintPauseAnalysisActive)
        XCTAssertNil(viewModel.acceptedHintPauseSnapshot)
        XCTAssertEqual(viewModel.hintPauseFailureReason, .noAcceptedEvidence)
        guard case .failure(let snapshotID) = viewModel.hintPausePresentationState else {
            return XCTFail("an unavailable accepted frame must be an explicit pause failure")
        }
        XCTAssertFalse(snapshotID.isEmpty)
        XCTAssertNil(viewModel.liveHint)

        viewModel.resumeHintLiveAnalysis()

        XCTAssertTrue(viewModel.isHintsEnabled)
        XCTAssertFalse(viewModel.isHintPauseAnalysisActive)
        XCTAssertNil(viewModel.acceptedHintPauseSnapshot)
        XCTAssertEqual(viewModel.hintPausePresentationState, .idle)
        XCTAssertNil(viewModel.hintPauseFailureReason)
        XCTAssertNil(viewModel.hintPauseCritique)
        XCTAssertTrue(viewModel.hintPreviewSuggestions.isEmpty)
    }

    @MainActor
    func testSceneGeneratorHintPauseUsesOneAcceptedFrameForDisplayAndAnalysis() async throws {
        let viewModel = SceneGeneratorViewModel()
        viewModel.toggleHintsEnabled()
        let pixelBuffer = try makeDeterministicHintPixelBuffer()

        viewModel.processARFrameSnapshot(
            cameraTransform: matrix_identity_float4x4,
            planeSnapshots: [ScenePlaneSnapshot(alignment: .horizontal, y: -1.0)],
            timestamp: 7.0,
            capturedImage: pixelBuffer,
            interfaceOrientation: .portraitUpsideDown,
            displayTransform: CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0.1, ty: 0.2)
        )
        await viewModel.testingDrainHintAnalysis()
        viewModel.startHintPauseAnalysis()
        defer { viewModel.resumeHintLiveAnalysis() }

        guard let acceptedSnapshot = viewModel.acceptedHintPauseSnapshot else {
            return XCTFail("the current AR frame must be accepted synchronously")
        }
        XCTAssertEqual(acceptedSnapshot.sourceFrameId, "frame_7000")
        XCTAssertEqual(acceptedSnapshot.orientation, .left)
        XCTAssertNil(acceptedSnapshot.displayImage)

        var displayReady = false
        for _ in 0..<1_000 {
            if viewModel.acceptedHintPauseSnapshot?.displayImage != nil {
                displayReady = true
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(displayReady)

        guard let displayedSnapshot = viewModel.acceptedHintPauseSnapshot else {
            return XCTFail("the rendered pause frame must remain owned by the view model")
        }
        XCTAssertNotNil(displayedSnapshot.displayImage)
        XCTAssertEqual(displayedSnapshot.snapshotID, acceptedSnapshot.snapshotID)
        XCTAssertEqual(displayedSnapshot.sourceFrameId, acceptedSnapshot.sourceFrameId)

        var analysisTerminal = false
        for _ in 0..<1_000 {
            if viewModel.hintPausePresentationState != .loading(snapshotID: acceptedSnapshot.snapshotID) {
                analysisTerminal = true
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(analysisTerminal)
        XCTAssertEqual(viewModel.hintPausePresentationState.snapshotID, acceptedSnapshot.snapshotID)
        if case .success(let snapshotID, let critique) = viewModel.hintPausePresentationState {
            XCTAssertEqual(snapshotID, acceptedSnapshot.snapshotID)
            XCTAssertEqual(critique.frameId, acceptedSnapshot.snapshotID)
        }

        viewModel.resumeHintLiveAnalysis()
        XCTAssertFalse(viewModel.isHintPauseAnalysisActive)
        XCTAssertNil(viewModel.acceptedHintPauseSnapshot)
        XCTAssertNil(viewModel.hintPauseCritique)
        XCTAssertTrue(viewModel.hintPreviewSuggestions.isEmpty)
    }

    private func makeDeterministicHintPixelBuffer() throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: 64,
            kCVPixelBufferHeightKey as String: 48,
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            64,
            48,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        return try XCTUnwrap(pixelBuffer)
    }

    func testLLMReleaseModelResourcesIsIdempotent() throws {
        let service = LLMParserService.shared
        service.releaseModelResources(reason: "unit_test")
        XCTAssertEqual(service.loadingState, .notLoaded)
    }

    func testV9FullSkipsLegacyPlanProviderAndUsesEventTableProvider() async throws {
        let modeKey = "scene_generator_v9_runtime_mode"
        let defaults = UserDefaults.standard
        let oldMode = defaults.object(forKey: modeKey)
        defer {
            if let oldMode {
                defaults.set(oldMode, forKey: modeKey)
            } else {
                defaults.removeObject(forKey: modeKey)
            }
        }
        defaults.set("v9_full", forKey: modeKey)

        let provider = StubLocalProvider(result: simpleProviderResult()) { _, _, _, _, slotCatalog in
            SceneV9EventProviderResult(
                slotCatalog: slotCatalog,
                eventTable: SceneV9EventTable(contractVersion: "sg_v9_event_table_v1", rows: []),
                reasonCodes: ["test_event_provider"]
            )
        }
        let pipeline = SceneBundlePipeline(
            anchorExtractor: SceneAnchorExtractor(),
            metadataExtractor: SceneMetadataExtractor(),
            localProvider: provider,
            planCompiler: ScenePlanCompiler()
        )

        _ = await pipeline.parseAsync(
            description: "Марина стоит у стола.",
            markedObjects: [],
            mode: .full,
            previousState: nil as ScriptDocumentState?
        ) { text, _, _ in
            ParsingResult(
                script: SceneScript(
                    actors: [SceneActor(id: "actor_1", type: .human, name: "Марина")],
                    objects: [],
                    beats: [
                        SceneBeat(
                            id: "beat_1",
                            actions: [SceneAction(id: "action_1", actorId: "actor_1", type: .stand)]
                        ),
                    ],
                    spatialRelations: [],
                    originalDescription: text
                ),
                diagnostics: .empty
            )
        }

        XCTAssertEqual(provider.generatePlanAsyncCallCount, 0)
        XCTAssertEqual(provider.generatePlanCallCount, 0)
        XCTAssertEqual(provider.generateEventTableAsyncCallCount, 1)
    }

    @MainActor
    func testSceneParserRuntimeModeAPIBackCompatRoundtrip() throws {
        let modeKey = "scene_generator_v9_runtime_mode"
        let enabledKey = "scene_generator_v9_enabled"
        let defaults = UserDefaults.standard
        let oldMode = defaults.object(forKey: modeKey)
        let oldEnabled = defaults.object(forKey: enabledKey)
        defer {
            if let oldMode {
                defaults.set(oldMode, forKey: modeKey)
            } else {
                defaults.removeObject(forKey: modeKey)
            }
            if let oldEnabled {
                defaults.set(oldEnabled, forKey: enabledKey)
            } else {
                defaults.removeObject(forKey: enabledKey)
            }
        }

        parser.setV9RuntimeMode(.v8Hotfix)
        XCTAssertEqual(parser.getV9RuntimeMode(), .v8Hotfix)

        parser.setV9RuntimeMode(.v9Bridge)
        XCTAssertEqual(parser.getV9RuntimeMode(), .v9Bridge)

        parser.setV9RuntimeMode(.v9Full)
        XCTAssertEqual(parser.getV9RuntimeMode(), .v9Full)
    }

    func testV9FullBudgetKeepsSuccessfulProviderResultAndEmitsReasonCode() async throws {
        let modeKey = "scene_generator_v9_runtime_mode"
        let budgetKey = "scene_generator_v9_chunk_budget_ms"
        let defaults = UserDefaults.standard
        let oldMode = defaults.string(forKey: modeKey)
        let oldBudgetObj = defaults.object(forKey: budgetKey)
        defaults.set("v9_full", forKey: modeKey)
        defaults.set(10.0, forKey: budgetKey)
        defer {
            if let oldMode {
                defaults.set(oldMode, forKey: modeKey)
            } else {
                defaults.removeObject(forKey: modeKey)
            }
            if let oldBudgetObj {
                defaults.set(oldBudgetObj, forKey: budgetKey)
            } else {
                defaults.removeObject(forKey: budgetKey)
            }
        }

        let sourcePlan = ScenePlanIR(
            actors: [
                .init(ref: "first", type: .human),
                .init(ref: "second", type: .human),
            ],
            objects: [],
            beats: [
                .init(
                    ref: "beat_1",
                    actions: [
                        .init(actorRef: "first", type: .walk, targetRef: "second", resultingPose: .walking),
                        .init(actorRef: "second", type: .walk, targetRef: "first", resultingPose: .walking),
                    ]
                ),
            ],
            spatialRelations: [],
            referenceBindings: .init(actorBindings: ["first": "actor_1", "second": "actor_2"])
        )
        let pipeline = makeBundlePipeline(
            result: ScenePlanProviderResult(plan: sourcePlan, usedLegacySceneScriptBridge: false),
            eventProvider: { _, _, _, _, slotCatalog in
                Thread.sleep(forTimeInterval: 0.05)
                return SceneV9EventProviderResult(
                    slotCatalog: slotCatalog,
                    eventTable: SceneV9EventTable(
                        contractVersion: "sg_v9_event_table_v1",
                        rows: [
                            .init(
                                rowID: "row_1",
                                beatSlot: slotCatalog.beatSlots.first?.slotID ?? "beat_slot_1",
                                actorSlot: slotCatalog.actorSlots.first?.slotID ?? "actor_slot_1",
                                actionType: .walk,
                                targetSlot: slotCatalog.actorSlots.dropFirst().first?.slotID,
                                holdingObjectSlot: nil,
                                dialogueText: nil,
                                describedActionText: nil,
                                sourceSpan: "идут навстречу друг другу",
                                confidence: 0.9
                            ),
                        ]
                    ),
                    patchOps: nil,
                    reasonCodes: ["v9.event_provider_test_payload"]
                )
            }
        )

        let result = await pipeline.parse(
            description: "Первый и второй актер идут навстречу друг другу.",
            markedObjects: [],
            mode: .full,
            previousState: nil as ScriptDocumentState?
        ) { text, _, _ in
            let fallbackScript = SceneScript(
                actors: [
                    SceneActor(id: "actor_1", type: .human),
                    SceneActor(id: "actor_2", type: .human),
                ],
                objects: [],
                beats: [
                    SceneBeat(
                        id: "beat_1",
                        actions: [
                            SceneAction(
                                id: "action_1",
                                actorId: "actor_1",
                                type: .walk,
                                target: "actor_2",
                                resultingPose: .walking
                            ),
                        ]
                    ),
                ],
                spatialRelations: [],
                originalDescription: text
            )
            return ParsingResult(
                script: fallbackScript,
                diagnostics: .empty
            )
        }

        let reasons = Set(result.chunkDiagnostics.flatMap(\.reasonCodes))
        XCTAssertTrue(reasons.contains("v9.runtime_budget_exceeded_fallback_v8"))
        XCTAssertTrue(reasons.contains("runtime_guardrail:v9.runtime_budget_exceeded_fallback_v8"))
        let script = try XCTUnwrap(result.activeSceneScript)
        let walkActions = script.actions.filter { $0.type == .walk }
        XCTAssertEqual(walkActions.count, 2)
        XCTAssertTrue(reasons.contains("provider:v9.event_provider_test_payload"))
    }

    func testV9FixableVerifierIssuePolicy() {
        let service = SceneEventTableV9Service()
        XCTAssertTrue(service.containsFixableVerifierIssues(["v9.targetless_event_repaired"]))
        XCTAssertTrue(service.containsFixableVerifierIssues(["v9.holding_slot_repaired", "other"]))
        XCTAssertTrue(service.containsFixableVerifierIssues(["v9.missing_event_for_beat:beat_slot_2"]))
        XCTAssertFalse(service.containsFixableVerifierIssues(["v9.unknown_slot_blocked"]))
        XCTAssertFalse(service.containsFixableVerifierIssues([]))
    }

    func testScriptNormalizerSplitsInlineDialogueStageNotesAndScreenText() throws {
        let normalizer = ScriptNormalizer()
        let units = normalizer.normalize(description: """
        На экране появляются надписи:
        Великое Древо, 2048
        20 лет после разрушения Земли

        Ведущий: Спасибо тебе. *речь затухает*
        """)

        XCTAssertTrue(units.contains { $0.kind == .speakerCue && $0.text == "Ведущий" })
        XCTAssertTrue(units.contains { $0.kind == .dialogue && $0.text.contains("Спасибо тебе") })
        XCTAssertFalse(units.contains { $0.kind == .dialogue && $0.text.contains("речь затухает") })
        XCTAssertTrue(units.contains { $0.kind == .stageNote && $0.text.contains("речь затухает") })
        XCTAssertEqual(units.filter { $0.kind == .screenText }.map(\.text), ["Великое Древо, 2048", "20 лет после разрушения Земли"])
    }

    func testScreenplayFragmentKeepsMontageOverlaysAndImplicitRustamShot() async throws {
        let plan = ScenePlanIR(
            actors: [.init(ref: "first", type: .human)],
            objects: [],
            beats: [
                .init(ref: "beat_1", actions: [.init(actorRef: "first", type: .talk, dialogue: "тест")]),
            ],
            spatialRelations: [],
            referenceBindings: .init(actorBindings: ["first": "actor_1"])
        )
        let pipeline = makeBundlePipeline(result: ScenePlanProviderResult(plan: plan, usedLegacySceneScriptBridge: false))
        let fragment = """
        Кадр из космоса, показано Великое Древо. На экране появляются надписи:
        Великое Древо, 2048
        20 лет после разрушения Земли

        ИНТ. Телестудия
        Ведущий: 19 лет эта кошмарная эпидемия держала нас в страхе. Что вы об этом думаете?
        Лейла: Наконец-то. Вместе мы прошли через большие трудности. Каждый день люди продолжают двигаться вперёд.
        Ведущий: Согласен. *речь затухает* На этом у нас всё.

        Рустам сидит поникший, смотрит на коробочку с надписью Жизнь с пришельцем.
        """

        let result = await pipeline.parse(
            description: fragment,
            markedObjects: [],
            mode: .full,
            previousState: nil as ScriptDocumentState?
        ) { text, _, _ in
            ParsingResult(
                script: SceneScript(actors: [], objects: [], beats: [], spatialRelations: [], originalDescription: text),
                diagnostics: .empty
            )
        }

        XCTAssertTrue(result.documentState.sceneCandidates.first?.isMontage == true)
        XCTAssertTrue(result.visualOverlays.contains { $0.kind == .screenText && $0.text.contains("2048") })
        XCTAssertTrue(result.visualOverlays.contains { $0.kind == .stageNote && $0.text.contains("речь затухает") })
        let sceneDebug = result.documentState.sceneCandidates.map {
            "\($0.id)|implicit=\($0.isImplicit)|montage=\($0.isMontage)|\($0.sourceText.replacingOccurrences(of: "\n", with: "\\n"))"
        }.joined(separator: " / ")
        XCTAssertTrue(result.documentState.sceneCandidates.contains { $0.isImplicit && $0.sourceText.contains("Рустам сидит") }, sceneDebug)
        XCTAssertEqual(result.bundleScript.activeSceneIndex, 0)
        XCTAssertEqual(result.activeSceneScript?.locationName, "Телестудия")
    }

    func testV9CoverageVerifierEmitsSemanticIssues() {
        let service = SceneEventTableV9Service()
        let slotCatalog = SceneV9SlotCatalog(
            contractVersion: "sg_v9_slot_catalog_v1",
            actorSlots: [
                .init(slotID: "actor_slot_1", ref: "first", type: .human, name: nil),
                .init(slotID: "actor_slot_2", ref: "second", type: .human, name: nil),
            ],
            objectSlots: [],
            markedObjectSlots: [],
            beatSlots: [
                .init(slotID: "beat_slot_1", beatRef: "beat_1", phaseHint: nil, order: 1, minDuration: nil),
                .init(slotID: "beat_slot_2", beatRef: "beat_2", phaseHint: nil, order: 2, minDuration: nil),
            ],
            actionTypes: SceneAction.ActionType.allCases,
            relationHints: []
        )
        let eventTable = SceneV9EventTable(
            contractVersion: "sg_v9_event_table_v1",
            rows: [
                .init(
                    rowID: "row_1",
                    beatSlot: "beat_slot_1",
                    actorSlot: "actor_slot_1",
                    actionType: .stand,
                    targetSlot: nil,
                    holdingObjectSlot: nil,
                    dialogueText: nil,
                    describedActionText: nil,
                    sourceSpan: nil,
                    confidence: 1.0
                ),
            ]
        )

        let issues = service.coverageIssueCodes(
            eventTable: eventTable,
            slotCatalog: slotCatalog,
            sourceText: "Первый говорит: «идём». Затем оба идут навстречу друг другу.",
            anchors: .empty
        )

        XCTAssertTrue(issues.contains("v9.missing_event_for_beat:beat_slot_2"))
        XCTAssertTrue(issues.contains("v9.dialogue_action_collapsed"))
        XCTAssertTrue(issues.contains { $0.hasPrefix("v9.collective_action_not_expanded") })
    }

    func testV9CoverageVerifierFlagsMissingTargetForPutPickAndCollectiveStopNear() {
        let service = SceneEventTableV9Service()
        let slotCatalog = SceneV9SlotCatalog(
            contractVersion: "sg_v9_slot_catalog_v1",
            actorSlots: [
                .init(slotID: "actor_slot_1", ref: "first", type: .human, name: nil),
                .init(slotID: "actor_slot_2", ref: "second", type: .human, name: nil),
            ],
            objectSlots: [
                .init(
                    slotID: "object_slot_1",
                    ref: "object_marked_1",
                    type: .generic,
                    relativePosition: .center,
                    markedObjectID: "object_marked_1",
                    name: "компьютер"
                ),
            ],
            markedObjectSlots: ["object_slot_1"],
            beatSlots: [
                .init(slotID: "beat_slot_1", beatRef: "beat_1", phaseHint: nil, order: 1, minDuration: nil),
            ],
            actionTypes: SceneAction.ActionType.allCases,
            relationHints: []
        )
        let eventTable = SceneV9EventTable(
            contractVersion: "sg_v9_event_table_v1",
            rows: [
                .init(
                    rowID: "row_1",
                    beatSlot: "beat_slot_1",
                    actorSlot: "actor_slot_1",
                    actionType: .putDown,
                    targetSlot: nil,
                    holdingObjectSlot: nil,
                    dialogueText: nil,
                    describedActionText: nil,
                    sourceSpan: nil,
                    confidence: 1.0
                ),
                .init(
                    rowID: "row_2",
                    beatSlot: "beat_slot_1",
                    actorSlot: "actor_slot_1",
                    actionType: .stop,
                    targetSlot: "object_slot_1",
                    holdingObjectSlot: nil,
                    dialogueText: nil,
                    describedActionText: nil,
                    sourceSpan: nil,
                    confidence: 1.0
                ),
            ]
        )

        let issues = service.coverageIssueCodes(
            eventTable: eventTable,
            slotCatalog: slotCatalog,
            sourceText: "Оба останавливаются рядом с компьютером, потом первый кладет папку.",
            anchors: .empty
        )

        XCTAssertTrue(issues.contains("v9.missing_target_for_object_action"))
        XCTAssertTrue(issues.contains("v9.collective_stop_near_not_expanded"))
    }

    func testV9CoverageVerifierFlagsDialogueActionCollapsedWhenNoSeparateActionRow() {
        let service = SceneEventTableV9Service()
        let slotCatalog = SceneV9SlotCatalog(
            contractVersion: "sg_v9_slot_catalog_v1",
            actorSlots: [
                .init(slotID: "actor_slot_1", ref: "first", type: .human, name: nil),
            ],
            objectSlots: [],
            markedObjectSlots: [],
            beatSlots: [
                .init(slotID: "beat_slot_1", beatRef: "beat_1", phaseHint: nil, order: 1, minDuration: nil),
            ],
            actionTypes: SceneAction.ActionType.allCases,
            relationHints: []
        )
        let eventTable = SceneV9EventTable(
            contractVersion: "sg_v9_event_table_v1",
            rows: [
                .init(
                    rowID: "row_1",
                    beatSlot: "beat_slot_1",
                    actorSlot: "actor_slot_1",
                    actionType: .talk,
                    targetSlot: nil,
                    holdingObjectSlot: nil,
                    dialogueText: "Идем к компьютеру",
                    describedActionText: nil,
                    sourceSpan: nil,
                    confidence: 1.0
                ),
            ]
        )

        let issues = service.coverageIssueCodes(
            eventTable: eventTable,
            slotCatalog: slotCatalog,
            sourceText: "Первый говорит: «Идем к компьютеру», затем идет вперед.",
            anchors: .empty
        )

        XCTAssertTrue(issues.contains("v9.dialogue_action_collapsed"))
    }

    func testV9ContractsAcceptRowIdAndLegacyRowID() throws {
        let eventRowPayloadRowId = """
        {"contractVersion":"sg_v9_event_table_v1","rows":[{"rowId":"row_1","beatSlot":"beat_slot_1","actorSlot":"actor_slot_1","actionType":"stand"}]}
        """
        let eventRowPayloadLegacy = """
        {"contractVersion":"sg_v9_event_table_v1","rows":[{"rowID":"row_2","beatSlot":"beat_slot_1","actorSlot":"actor_slot_1","actionType":"walk"}]}
        """

        let decodedRowId = try JSONDecoder().decode(SceneV9EventTable.self, from: Data(eventRowPayloadRowId.utf8))
        let decodedLegacy = try JSONDecoder().decode(SceneV9EventTable.self, from: Data(eventRowPayloadLegacy.utf8))
        XCTAssertEqual(decodedRowId.rows.first?.rowID, "row_1")
        XCTAssertEqual(decodedLegacy.rows.first?.rowID, "row_2")

        let patchPayloadRowId = """
        {"contractVersion":"sg_v9_patch_ops_v1","ops":[{"op":"replace","rowId":"row_1","field":"actionType","value":"stand"}]}
        """
        let patchPayloadLegacy = """
        {"contractVersion":"sg_v9_patch_ops_v1","ops":[{"op":"delete","rowID":"row_2"}]}
        """

        let decodedPatchRowId = try JSONDecoder().decode(SceneV9PatchOps.self, from: Data(patchPayloadRowId.utf8))
        let decodedPatchLegacy = try JSONDecoder().decode(SceneV9PatchOps.self, from: Data(patchPayloadLegacy.utf8))
        XCTAssertEqual(decodedPatchRowId.ops.first?.rowID, "row_1")
        XCTAssertEqual(decodedPatchLegacy.ops.first?.rowID, "row_2")
    }

    @MainActor
    func testStoryboardPhoneRenderStyleAndYawHelpers() throws {
        let phoneStyle = SceneGeneratorViewModel.objectRenderStyle(for: .phone)
        let tableStyle = SceneGeneratorViewModel.objectRenderStyle(for: .table)

        XCTAssertEqual(phoneStyle.kind, .phoneProxy)
        XCTAssertGreaterThan(phoneStyle.targetCueRadius, tableStyle.targetCueRadius)

        let yaw = SceneGeneratorViewModel.yawAngle(
            from: SIMD3<Float>(0, 0, 0),
            toward: SIMD3<Float>(1, 0, 0)
        )
        XCTAssertEqual(yaw ?? 0, Float.pi / 2, accuracy: 0.001)
        XCTAssertNil(SceneGeneratorViewModel.yawAngle(from: .zero, toward: .zero))

        let overlappingLabels = [
            ARObjectLabelPresentation(
                id: "phone",
                text: "Телефон",
                x: 220,
                y: 320,
                tint: SIMD3<Float>(0.2, 0.9, 1.0),
                priority: 0
            ),
            ARObjectLabelPresentation(
                id: "table",
                text: "Стол",
                x: 224,
                y: 322,
                tint: SIMD3<Float>(0.0, 0.8, 0.4),
                priority: 1
            ),
        ]
        let arranged = SceneGeneratorViewModel.layoutObjectLabels(
            overlappingLabels,
            canvasSize: CGSize(width: 430, height: 760),
            minVerticalSpacing: 28
        )
        let phone = try XCTUnwrap(arranged.first { $0.id == "phone" })
        let table = try XCTUnwrap(arranged.first { $0.id == "table" })
        XCTAssertGreaterThanOrEqual(abs(phone.y - table.y), 28)
    }

    @MainActor
    func testStoryboardPresentationBuildsVisibleSummaries() {
        let script = makeStoryboardDemoScript()
        let viewModel = SceneGeneratorViewModel(projectName: "storyboard-presentation-\(UUID().uuidString)")
        let items = viewModel.buildStoryboardBeatPresentationItems(for: script)

        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items[1].kindTitle, "диалог")
        XCTAssertTrue(items[1].summary.contains("Марина"))
        XCTAssertTrue(items[1].hasDialogueCaption)
        XCTAssertTrue(items[2].summary.contains("телефон"))
        XCTAssertTrue(items[3].hasActionCaption)
    }

    @MainActor
    func testStoryboardBeatInspectorShowsActorsTargetsAndDuration() throws {
        let viewModel = makeStoryboardViewModel()
        viewModel.openStoryboardEditor(for: "beat_3")
        let draft = try XCTUnwrap(viewModel.activeStoryboardEditDraft)

        let inspector = viewModel.buildStoryboardBeatInspector(for: draft)

        XCTAssertEqual(inspector.kindTitle, "действие")
        XCTAssertTrue(inspector.summary.contains("телефон"))
        XCTAssertTrue(inspector.actorLabels.contains("Олег"))
        XCTAssertTrue(inspector.targetLabels.contains("телефон"))
        XCTAssertNotEqual(inspector.durationText, "0.00s")
        XCTAssertTrue(inspector.warnings.isEmpty)
    }

    @MainActor
    func testStoryboardBeatInspectorWarnsAboutMissingTargetAndEmptyText() throws {
        let viewModel = makeStoryboardViewModel()
        viewModel.openStoryboardEditor(for: "beat_3")
        var draft = try XCTUnwrap(viewModel.activeStoryboardEditDraft)
        draft.actions[0].target = nil
        draft.actions[0].text = ""

        let inspector = viewModel.buildStoryboardBeatInspector(for: draft)

        XCTAssertTrue(inspector.warnings.contains { $0.contains("нет цели") })
    }

    @MainActor
    func testStoryboardActorDragCommitChangesOnlySelectedBeatPoints() throws {
        let viewModel = makeStoryboardViewModel()
        viewModel.openStoryboardEditor(for: "beat_3")
        let oldActor = try XCTUnwrap(viewModel.plannedScene?.placedActors.first { $0.actorId == "actor_2" })
        let newPosition = Position3D(x: 1.35, y: 0, z: -0.75)

        let committed = viewModel.commitStoryboardActorDrag(actorID: "actor_2", beatID: "beat_3", to: newPosition)

        XCTAssertTrue(committed)
        let updatedActor = try XCTUnwrap(viewModel.plannedScene?.placedActors.first { $0.actorId == "actor_2" })
        for index in updatedActor.path.indices {
            let isEditedBeat = updatedActor.pathBeatIDs.indices.contains(index) && updatedActor.pathBeatIDs[index] == "beat_3"
            if isEditedBeat {
                XCTAssertEqual(updatedActor.path[index].x, newPosition.x, accuracy: 0.001)
                XCTAssertEqual(updatedActor.path[index].z, newPosition.z, accuracy: 0.001)
            } else {
                XCTAssertEqual(updatedActor.path[index], oldActor.path[index])
            }
        }
    }

    @MainActor
    func testStoryboardActorTrackDragWithoutActiveBeatMovesWholeActorPath() throws {
        let viewModel = makeStoryboardViewModel()
        let oldScene = try XCTUnwrap(viewModel.plannedScene)
        let oldActor = try XCTUnwrap(oldScene.placedActors.first { $0.actorId == "actor_2" })
        let oldOtherActor = try XCTUnwrap(oldScene.placedActors.first { $0.actorId == "actor_1" })
        let newPosition = Position3D(
            x: oldActor.initialPosition.x + 0.45,
            y: oldActor.initialPosition.y,
            z: oldActor.initialPosition.z - 0.25
        )

        let committed = viewModel.commitStoryboardActorTrackDrag(
            actorID: "actor_2",
            from: oldActor.initialPosition.simdVector,
            to: newPosition
        )

        XCTAssertTrue(committed)
        let updatedScene = try XCTUnwrap(viewModel.plannedScene)
        let updatedActor = try XCTUnwrap(updatedScene.placedActors.first { $0.actorId == "actor_2" })
        let updatedOtherActor = try XCTUnwrap(updatedScene.placedActors.first { $0.actorId == "actor_1" })

        XCTAssertEqual(updatedActor.initialPosition.x, oldActor.initialPosition.x + 0.45, accuracy: 0.001)
        XCTAssertEqual(updatedActor.initialPosition.z, oldActor.initialPosition.z - 0.25, accuracy: 0.001)
        for index in oldActor.path.indices {
            XCTAssertEqual(updatedActor.path[index].x, oldActor.path[index].x + 0.45, accuracy: 0.001)
            XCTAssertEqual(updatedActor.path[index].z, oldActor.path[index].z - 0.25, accuracy: 0.001)
            XCTAssertEqual(updatedActor.path[index].y, oldActor.path[index].y, accuracy: 0.001)
        }
        XCTAssertEqual(updatedOtherActor.initialPosition, oldOtherActor.initialPosition)
        XCTAssertEqual(updatedOtherActor.path, oldOtherActor.path)
    }

    @MainActor
    func testStoryboardActorDragRequiresActiveBeatAndBeatParticipation() throws {
        let viewModel = makeStoryboardViewModel()
        let oldScene = viewModel.plannedScene
        let rejectedWithoutSheet = viewModel.commitStoryboardActorDrag(
            actorID: "actor_2",
            beatID: "beat_3",
            to: Position3D(x: 2, y: 0, z: 2)
        )

        XCTAssertFalse(rejectedWithoutSheet)
        XCTAssertEqual(viewModel.plannedScene, oldScene)

        var script = makeStoryboardDemoScript()
        var beats = script.beats
        beats.append(
            SceneBeat(
                id: "beat_empty_stand",
                actions: [SceneAction(id: "action_empty", actorId: "actor_1", type: .stand)],
                minDuration: 0.5
            )
        )
        script = SceneScript(
            actors: script.actors,
            objects: script.objects,
            beats: beats,
            spatialRelations: script.spatialRelations,
            originalDescription: script.originalDescription
        )

        viewModel.parsedScript = script
        viewModel.plannedScene = SpatialPlannerService.shared.planScene(
            script: script,
            cameraTransform: matrix_identity_float4x4,
            detectedObjects: [],
            availablePlanes: [ScenePlaneSnapshot(alignment: .horizontal, y: 0)],
            markedObjects: []
        )
        viewModel.openStoryboardEditor(for: "beat_empty_stand")
        let sceneBeforeEmptyBeatDrag = viewModel.plannedScene
        let rejectedWithoutBeatPoint = viewModel.commitStoryboardActorDrag(
            actorID: "actor_1",
            beatID: "beat_empty_stand",
            to: Position3D(x: 3, y: 0, z: 3)
        )

        XCTAssertFalse(rejectedWithoutBeatPoint)
        XCTAssertEqual(viewModel.plannedScene, sceneBeforeEmptyBeatDrag)
        XCTAssertTrue(viewModel.storyboardDragFeedback?.contains("не участвует") == true)
    }

    @MainActor
    func testStoryboardManualEditChangesActionAndReplans() async throws {
        let viewModel = makeStoryboardViewModel()
        let originalPlacedObjects = viewModel.plannedScene?.placedObjects
        viewModel.openStoryboardEditor(for: "beat_3")
        var draft = try XCTUnwrap(viewModel.activeStoryboardEditDraft)

        XCTAssertEqual(draft.actions.first?.type, .lookAt)
        draft.actions[0].type = .give
        draft.actions[0].target = "actor_1"
        draft.actions[0].text = "Олег передаёт телефон Марине"

        let saved = await viewModel.applyStoryboardBeatEdit(draft)

        XCTAssertTrue(saved)
        let editedAction = try XCTUnwrap(viewModel.parsedScript?.beats.first(where: { $0.id == "beat_3" })?.actions.first)
        XCTAssertEqual(editedAction.type, .give)
        XCTAssertEqual(editedAction.actorId, "actor_2")
        XCTAssertEqual(editedAction.target, "actor_1")
        XCTAssertEqual(editedAction.sourceText, "Олег передаёт телефон Марине")
        XCTAssertNotNil(viewModel.plannedScene)
        XCTAssertFalse(viewModel.storyboardBeatItems.isEmpty)
        XCTAssertEqual(viewModel.plannedScene?.placedObjects, originalPlacedObjects)
    }

    @MainActor
    func testStoryboardBeatEditFailsBeforeMutationWhenObjectIdentityIsUnavailable() async throws {
        let viewModel = makeStoryboardViewModel()
        let originalPlannedScene = try XCTUnwrap(viewModel.plannedScene)
        let originalScript = try XCTUnwrap(viewModel.parsedScript)
        let invalidScript = SceneScript(
            sceneHeading: originalScript.sceneHeading,
            locationName: originalScript.locationName,
            interiorExterior: originalScript.interiorExterior,
            timeOfDay: originalScript.timeOfDay,
            actors: originalScript.actors,
            objects: originalScript.objects + [
                SceneObject(
                    id: "object_unbound",
                    type: .chair,
                    name: "стул",
                    relativePosition: .center
                )
            ],
            beats: originalScript.beats,
            spatialRelations: originalScript.spatialRelations,
            originalDescription: originalScript.originalDescription
        )
        viewModel.parsedScript = invalidScript
        let originalTimeline = viewModel.beatTimelineItems
        viewModel.openStoryboardEditor(for: "beat_1")
        let draft = try XCTUnwrap(viewModel.activeStoryboardEditDraft)

        let saved = await viewModel.applyStoryboardBeatEdit(draft)

        XCTAssertFalse(saved)
        XCTAssertEqual(viewModel.parsedScript, invalidScript)
        XCTAssertEqual(viewModel.plannedScene, originalPlannedScene)
        XCTAssertEqual(viewModel.beatTimelineItems, originalTimeline)
        XCTAssertFalse(viewModel.isPlaying)
        XCTAssertNotNil(viewModel.storyboardValidationMessage)
    }

    @MainActor
    func testStoryboardManualEditRejectsSelfGive() async throws {
        let viewModel = makeStoryboardViewModel()
        viewModel.openStoryboardEditor(for: "beat_4")
        var draft = try XCTUnwrap(viewModel.activeStoryboardEditDraft)

        draft.actions[0].type = .give
        draft.actions[0].actorId = "actor_2"
        draft.actions[0].target = "actor_2"

        let saved = await viewModel.applyStoryboardBeatEdit(draft)

        XCTAssertFalse(saved)
        XCTAssertEqual(viewModel.parsedScript?.beats.first(where: { $0.id == "beat_4" })?.actions.first?.target, "actor_1")
        XCTAssertEqual(viewModel.errorMessage, "Нельзя передать объект самому себе")
        XCTAssertEqual(
            viewModel.storyboardValidationField,
            .target(actionID: draft.actions[0].id)
        )
    }

    @MainActor
    func testStoryboardSelectionOwnerCancelsAndConsumesOneStableEvent() async throws {
        let viewModel = makeStoryboardViewModel()

        viewModel.selectStoryboardBeat(beatID: "beat_1", reduceMotion: false)
        let cancelledEventID = try XCTUnwrap(viewModel.storyboardSelectionEventID)
        viewModel.selectStoryboardBeat(beatID: "beat_2", reduceMotion: false)
        let selectedEventID = try XCTUnwrap(viewModel.storyboardSelectionEventID)
        XCTAssertNotEqual(cancelledEventID, selectedEventID)
        XCTAssertEqual(viewModel.selectedStoryboardBeatID, "beat_2")

        try await Task.sleep(nanoseconds: 380_000_000)

        XCTAssertNil(viewModel.pendingStoryboardBeatID)
        XCTAssertEqual(viewModel.storyboardEditorHandoffEventID, selectedEventID)
        XCTAssertEqual(viewModel.activeStoryboardEditDraft?.beatID, "beat_2")

        viewModel.refreshStoryboardBeatItems()
        XCTAssertEqual(viewModel.storyboardEditorHandoffEventID, selectedEventID)
    }

    @MainActor
    func testStoryboardMutationOwnerRejectsDuplicateSubmits() async throws {
        let viewModel = makeStoryboardViewModel()
        viewModel.openStoryboardEditor(for: "beat_1")
        let draft = try XCTUnwrap(viewModel.activeStoryboardEditDraft)
        viewModel.testingSetStoryboardMutationDelay(0.25)

        let firstMutation = Task { @MainActor in
            await viewModel.applyStoryboardBeatEdit(draft)
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(viewModel.isStoryboardMutationInFlight)

        let duplicateSave = await viewModel.applyStoryboardBeatEdit(draft)
        let duplicateDelete = await viewModel.deleteStoryboardBeat(beatID: "beat_1")
        let duplicateMove = await viewModel.moveStoryboardBeat(beatID: "beat_1", offset: 1)
        XCTAssertFalse(duplicateSave)
        XCTAssertFalse(duplicateDelete)
        XCTAssertFalse(duplicateMove)

        let firstResult = await firstMutation.value
        XCTAssertTrue(firstResult)
        XCTAssertFalse(viewModel.isStoryboardMutationInFlight)
    }

    @MainActor
    func testStoryboardMoveAddAndDeleteReplans() async throws {
        let viewModel = makeStoryboardViewModel()

        let moved = await viewModel.moveStoryboardBeat(beatID: "beat_1", offset: 1)
        XCTAssertTrue(moved)
        XCTAssertEqual(Array(viewModel.parsedScript?.beats.map(\.id).prefix(2) ?? []), ["beat_2", "beat_1"])

        viewModel.openStoryboardEditor(for: "beat_1")
        var draft = try XCTUnwrap(viewModel.activeStoryboardEditDraft)
        draft.actions.append(
            StoryboardActionEditDraft(
                id: "manual_action_test",
                actorId: "actor_1",
                type: .describedAction,
                target: nil,
                text: "Марина задерживается у стола",
                isDeleted: false,
                isNew: true
            )
        )
        let saved = await viewModel.applyStoryboardBeatEdit(draft)
        XCTAssertTrue(saved)
        XCTAssertTrue(
            viewModel.parsedScript?.beats
                .first(where: { $0.id == "beat_1" })?
                .actions
                .contains { $0.id == "manual_action_test" && $0.sourceText == "Марина задерживается у стола" } == true
        )

        let deleted = await viewModel.deleteStoryboardBeat(beatID: "beat_2")
        XCTAssertTrue(deleted)
        XCTAssertFalse(viewModel.parsedScript?.beats.contains { $0.id == "beat_2" } == true)
        XCTAssertNotNil(viewModel.plannedScene)
        XCTAssertFalse(viewModel.storyboardBeatItems.contains { $0.beatID == "beat_2" })
    }

    @MainActor
    private func makeStoryboardViewModel() -> SceneGeneratorViewModel {
        let script = makeStoryboardDemoScript()
        let viewModel = SceneGeneratorViewModel(projectName: "storyboard-edit-\(UUID().uuidString)")
        var cameraTransform = matrix_identity_float4x4
        cameraTransform.columns.3 = SIMD4<Float>(0, 1.5, 0, 1)
        let planes = [ScenePlaneSnapshot(alignment: .horizontal, y: 0)]
        viewModel.testingSetPlanningContext(cameraTransform: cameraTransform, planes: planes)
        viewModel.parsedScript = script
        viewModel.plannedScene = SpatialPlannerService.shared.planScene(
            script: script,
            cameraTransform: cameraTransform,
            detectedObjects: [],
            availablePlanes: planes,
            markedObjects: []
        )
        viewModel.refreshStoryboardBeatItems()
        return viewModel
    }

    private func makeStoryboardDemoScript() -> SceneScript {
        SceneScript(
            actors: [
                SceneActor(id: "actor_1", type: .human, name: "Марина"),
                SceneActor(id: "actor_2", type: .human, name: "Олег"),
            ],
            objects: [
                SceneObject(id: "object_table", type: .table, name: "стол", relativePosition: .center),
                SceneObject(id: "object_phone", type: .phone, name: "телефон", relativePosition: .center),
            ],
            beats: [
                SceneBeat(
                    id: "beat_1",
                    actions: [
                        SceneAction(
                            id: "action_walk_1",
                            actorId: "actor_1",
                            type: .walk,
                            target: "actor_2",
                            direction: .towardEachOther,
                            sourceText: "Марина и Олег идут навстречу друг другу"
                        ),
                    ],
                    minDuration: 0.8
                ),
                SceneBeat(
                    id: "beat_2",
                    actions: [
                        SceneAction(
                            id: "action_talk_1",
                            actorId: "actor_1",
                            type: .talk,
                            dialogue: "Он опять звонил?"
                        ),
                    ],
                    minDuration: 0.8
                ),
                SceneBeat(
                    id: "beat_3",
                    actions: [
                        SceneAction(
                            id: "action_look_1",
                            actorId: "actor_2",
                            type: .lookAt,
                            target: "object_phone",
                            sourceText: "Олег смотрит на телефон"
                        ),
                    ],
                    minDuration: 0.8
                ),
                SceneBeat(
                    id: "beat_4",
                    actions: [
                        SceneAction(
                            id: "action_give_1",
                            actorId: "actor_2",
                            type: .give,
                            target: "actor_1",
                            holdingObject: "object_phone",
                            sourceText: "Олег передаёт телефон Марине"
                        ),
                    ],
                    minDuration: 0.8
                ),
            ],
            spatialRelations: [
                SpatialRelation(id: "relation_phone_table", subject: "object_phone", relation: .near, object: "object_table"),
            ],
            originalDescription: "Марина и Олег идут навстречу друг другу. Олег смотрит на телефон и передаёт его Марине."
        )
    }

    func testObjectBindingMatrixUsesExplicitIdentityAndTypedFailures() {
        let marker = makeMarkedObject(
            idSeed: "00000001-0000-0000-0000-000000000101",
            name: "стол",
            type: .table,
            position: Position3D(x: 1, y: 0, z: -1)
        )
        let detection = makeDetectedObject(
            idSeed: "00000000-0000-0000-0000-000000000201",
            label: "chair",
            confidence: 0.82,
            box: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
            position: Position3D(x: -1, y: 0, z: -2)
        )
        let resolver = SceneAnchorExtractor()
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        let manualResult = resolveBindings(
            resolver: resolver,
            requestID: requestID,
            description: "актёр подходит к столу",
            markers: [marker],
            detections: [],
            objects: [
                SceneObject(
                    id: marker.canonicalMarkedObjectID,
                    type: .table,
                    relativePosition: .center
                ),
            ]
        )
        let manual = manualResult.resolution(for: marker.canonicalMarkedObjectID)
        XCTAssertEqual(manual?.state, .bound)
        XCTAssertEqual(manual?.binding?.canonicalID, marker.canonicalMarkedObjectID)
        XCTAssertEqual(manual?.binding?.source, .marked)
        XCTAssertEqual(manual?.binding?.confidence, 1)
        XCTAssertEqual(manual?.binding?.name, "стол")

        let detectedReference = "object_chair_slot"
        let detectedResult = resolveBindings(
            resolver: resolver,
            requestID: requestID,
            description: "актёр садится на стул",
            markers: [],
            detections: [detection],
            objects: [
                SceneObject(
                    id: detectedReference,
                    type: .chair,
                    name: "стул",
                    relativePosition: .center
                ),
            ]
        )
        let detected = detectedResult.resolution(for: detectedReference)
        XCTAssertEqual(detected?.state, .bound)
        XCTAssertEqual(detected?.binding?.canonicalID, detectedReference)
        XCTAssertEqual(detected?.binding?.source, .detected)
        XCTAssertEqual(detected?.binding?.detectionID, detection.id)
        XCTAssertEqual(detected?.binding?.confidence, 0.82)
        XCTAssertEqual(detected?.binding?.name, "стул")

        let parserAliasResult = resolveBindings(
            resolver: resolver,
            requestID: requestID,
            description: "актёр садится на chair",
            markers: [],
            detections: [detection],
            aliasToObjectRef: ["chair": "object_scene1_chair_1"],
            objects: [
                SceneObject(
                    id: detectedReference,
                    type: .chair,
                    name: "chair",
                    relativePosition: .center
                ),
            ]
        )
        XCTAssertEqual(parserAliasResult.resolution(for: detectedReference)?.state, .bound)
        XCTAssertEqual(parserAliasResult.resolution(for: detectedReference)?.binding?.source, .detected)

        let conflictingAliasResult = resolveBindings(
            resolver: resolver,
            requestID: requestID,
            description: "актёр садится на chair",
            markers: [],
            detections: [detection],
            aliasToObjectRef: [
                "chair": "object_scene1_chair_1",
                "CHAIR": "object_scene1_other_chair",
            ],
            objects: [
                SceneObject(
                    id: detectedReference,
                    type: .chair,
                    name: "chair",
                    relativePosition: .center
                ),
            ]
        )
        XCTAssertEqual(conflictingAliasResult.resolution(for: detectedReference)?.state, .ambiguous)
        XCTAssertTrue(conflictingAliasResult.diagnostics.contains("ambiguous_alias:chair"))

        let aliasResult = resolveBindings(
            resolver: resolver,
            requestID: requestID,
            description: "актёр подходит к столу",
            markers: [marker],
            detections: [],
            objects: [
                SceneObject(
                    id: "object_table_alias",
                    type: .table,
                    name: "TABLE",
                    relativePosition: .center
                ),
            ]
        )
        XCTAssertEqual(
            aliasResult.resolution(for: "object_table_alias")?.binding?.canonicalID,
            marker.canonicalMarkedObjectID
        )

        let repeatedDetections = [
            detection,
            makeDetectedObject(
                idSeed: "00000002-0000-0000-0000-000000000202",
                label: "chair",
                confidence: 0.81,
                box: CGRect(x: 0.5, y: 0.2, width: 0.3, height: 0.4),
                position: Position3D(x: 1, y: 0, z: -2)
            ),
        ]
        let repeatedReference = "object_repeated_chair"
        let repeatedResult = resolveBindings(
            resolver: resolver,
            requestID: requestID,
            description: "два стула",
            markers: [],
            detections: repeatedDetections,
            objects: [
                SceneObject(id: repeatedReference, type: .chair, relativePosition: .center),
            ]
        )
        XCTAssertEqual(repeatedResult.resolution(for: repeatedReference)?.state, .ambiguous)
        XCTAssertEqual(repeatedResult.resolution(for: repeatedReference)?.candidateIDs.count, 2)

        let numberedMarkers = [
            makeMarkedObject(
                idSeed: "00000031-0000-0000-0000-000000000301",
                name: "стол_1",
                type: .table,
                position: Position3D(x: -1, y: 0, z: -1)
            ),
            makeMarkedObject(
                idSeed: "00000032-0000-0000-0000-000000000302",
                name: "стол_2",
                type: .table,
                position: Position3D(x: 1, y: 0, z: -1)
            ),
        ]
        let numberedObjects = numberedMarkers.map { marker in
            SceneObject(
                id: "object_\(marker.name)",
                type: .table,
                name: marker.name,
                relativePosition: .center
            )
        }
        let numberedForward = resolveBindings(
            resolver: resolver,
            requestID: requestID,
            description: "использовать стол_1 и стол_2",
            markers: numberedMarkers,
            detections: [],
            objects: numberedObjects
        )
        let numberedReverse = resolveBindings(
            resolver: resolver,
            requestID: requestID,
            description: "использовать стол_1 и стол_2",
            markers: numberedMarkers.reversed(),
            detections: [],
            objects: numberedObjects.reversed()
        )
        XCTAssertEqual(numberedForward, numberedReverse)
        for marker in numberedMarkers {
            XCTAssertEqual(
                numberedForward.resolution(for: "object_\(marker.name)")?.binding?.canonicalID,
                marker.canonicalMarkedObjectID
            )
        }

        let missingReference = "object_marked_ffffffff"
        let missingResult = resolveBindings(
            resolver: resolver,
            requestID: requestID,
            description: "актёр подходит к столу",
            markers: [],
            detections: [],
            objects: [
                SceneObject(id: missingReference, type: .table, relativePosition: .center),
            ]
        )
        XCTAssertEqual(missingResult.resolution(for: missingReference)?.state, .missing)

        let ambiguousMarkers = [
            makeMarkedObject(
                idSeed: "00000041-0000-0000-0000-000000000401",
                name: "стул",
                type: .chair,
                position: Position3D(x: -1, y: 0, z: -1)
            ),
            makeMarkedObject(
                idSeed: "00000042-0000-0000-0000-000000000402",
                name: "стул",
                type: .chair,
                position: Position3D(x: 1, y: 0, z: -1)
            ),
        ]
        let ambiguousReference = "object_ambiguous_chair"
        let ambiguousResult = resolveBindings(
            resolver: resolver,
            requestID: requestID,
            description: "актёр подходит к стулу",
            markers: ambiguousMarkers,
            detections: [],
            objects: [
                SceneObject(
                    id: ambiguousReference,
                    type: .chair,
                    name: "стул",
                    relativePosition: .center
                ),
            ]
        )
        XCTAssertEqual(ambiguousResult.resolution(for: ambiguousReference)?.state, .ambiguous)

        let duplicateDetection = makeDetectedObject(
            idSeed: "00000000-0000-0000-0000-000000000203",
            label: "dining table",
            confidence: 0.77,
            box: CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.3),
            position: marker.worldPosition
        )
        let convergedReference = "object_table_converged"
        let convergedResult = resolveBindings(
            resolver: resolver,
            requestID: requestID,
            description: "актёр подходит к столу",
            markers: [marker],
            detections: [duplicateDetection],
            objects: [
                SceneObject(
                    id: convergedReference,
                    type: .table,
                    name: "table",
                    relativePosition: .center
                ),
            ]
        )
        XCTAssertEqual(convergedResult.resolution(for: convergedReference)?.state, .bound)
        XCTAssertEqual(
            convergedResult.resolution(for: convergedReference)?.binding?.canonicalID,
            marker.canonicalMarkedObjectID
        )
        XCTAssertEqual(convergedResult.resolution(for: convergedReference)?.binding?.source, .marked)
        XCTAssertEqual(
            convergedResult.resolution(for: convergedReference)?.binding?.detectionID,
            duplicateDetection.id
        )
        XCTAssertEqual(
            Set(convergedResult.request.candidates.map(\.canonicalID)).count,
            convergedResult.request.candidates.count
        )
    }

    func testObjectBindingDoesNotConvergeSpatiallyDistinctOrUnpositionedObservations() {
        let marker = makeMarkedObject(
            idSeed: "00000071-0000-0000-0000-000000000701",
            name: "стул",
            type: .chair,
            position: Position3D(x: 0, y: 0, z: -1)
        )
        let resolver = SceneAnchorExtractor()
        let object = SceneObject(
            id: "object_chair_candidate",
            type: .chair,
            name: "стул",
            relativePosition: .center
        )

        let distinctDetection = makeDetectedObject(
            idSeed: "00000072-0000-0000-0000-000000000702",
            label: "chair",
            confidence: 0.9,
            box: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            position: Position3D(x: 1, y: 0, z: -1)
        )
        let distinct = resolveBindings(
            resolver: resolver,
            requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000072")!,
            description: "стул",
            markers: [marker],
            detections: [distinctDetection],
            objects: [object]
        )
        XCTAssertEqual(distinct.resolution(for: object.id)?.state, .ambiguous)
        XCTAssertEqual(
            distinct.resolution(for: object.id)?.diagnostic,
            "marked_detected_not_colocated"
        )

        var unpositionedDetection = distinctDetection
        unpositionedDetection.worldPosition = nil
        let unpositioned = resolveBindings(
            resolver: resolver,
            requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000073")!,
            description: "стул",
            markers: [marker],
            detections: [unpositionedDetection],
            objects: [object]
        )
        XCTAssertEqual(unpositioned.resolution(for: object.id)?.state, .ambiguous)
    }

    func testObjectBindingRejectsTypeMismatchedExplicitAndAliasCandidates() {
        let tableMarker = makeMarkedObject(
            idSeed: "00000081-0000-0000-0000-000000000801",
            name: "стул",
            type: .table,
            position: Position3D(x: 0, y: 0, z: -1)
        )
        let resolver = SceneAnchorExtractor()
        let explicit = resolveBindings(
            resolver: resolver,
            requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000081")!,
            description: "стул",
            markers: [tableMarker],
            detections: [],
            objects: [
                SceneObject(
                    id: tableMarker.canonicalMarkedObjectID,
                    type: .chair,
                    name: "стул",
                    relativePosition: .center
                )
            ]
        )
        XCTAssertEqual(explicit.resolution(for: tableMarker.canonicalMarkedObjectID)?.state, .missing)
        XCTAssertEqual(
            explicit.resolution(for: tableMarker.canonicalMarkedObjectID)?.diagnostic,
            "type_mismatch"
        )

        let alias = resolveBindings(
            resolver: resolver,
            requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000082")!,
            description: "стул",
            markers: [tableMarker],
            detections: [],
            aliasToObjectRef: ["стул": tableMarker.canonicalMarkedObjectID],
            objects: [
                SceneObject(
                    id: "object_chair_alias",
                    type: .chair,
                    name: "стул",
                    relativePosition: .center
                )
            ]
        )
        XCTAssertEqual(alias.resolution(for: "object_chair_alias")?.state, .missing)
        XCTAssertEqual(alias.resolution(for: "object_chair_alias")?.diagnostic, "type_mismatch")
    }

    func testObjectBindingAliasesRemainScopedToSubmittedRequestSnapshot() {
        let firstMarker = makeMarkedObject(
            idSeed: "00000091-0000-0000-0000-000000000901",
            name: "стол",
            type: .table,
            position: Position3D(x: -1, y: 0, z: -1)
        )
        let secondMarker = makeMarkedObject(
            idSeed: "00000092-0000-0000-0000-000000000902",
            name: "стол",
            type: .table,
            position: Position3D(x: 1, y: 0, z: -1)
        )
        let resolver = SceneAnchorExtractor()
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000091")!
        let firstRequest = resolver.makeObjectBindingRequestSnapshot(
            requestID: requestID,
            epoch: 1,
            description: "выбранный объект",
            markedObjects: [firstMarker],
            detectedObjects: [],
            aliasToObjectRef: ["выбранный объект": firstMarker.canonicalMarkedObjectID]
        )
        let secondRequest = resolver.makeObjectBindingRequestSnapshot(
            requestID: requestID,
            epoch: 2,
            description: "выбранный объект",
            markedObjects: [secondMarker],
            detectedObjects: [],
            aliasToObjectRef: ["выбранный объект": secondMarker.canonicalMarkedObjectID]
        )
        let object = SceneObject(
            id: "object_request_owned_alias",
            type: .table,
            name: "выбранный объект",
            relativePosition: .center
        )

        let firstResult = resolver.resolveObjectBindings(scriptObjects: [object], request: firstRequest)
        let secondResult = resolver.resolveObjectBindings(scriptObjects: [object], request: secondRequest)
        XCTAssertEqual(
            firstResult.resolution(for: object.id)?.binding?.canonicalID,
            firstMarker.canonicalMarkedObjectID
        )
        XCTAssertEqual(
            secondResult.resolution(for: object.id)?.binding?.canonicalID,
            secondMarker.canonicalMarkedObjectID
        )
    }

    func testObjectBindingRejectsInvalidDetectionGeometryAndNormalizesSignedZero() {
        let baseID = UUID(uuidString: "00000000-0000-0000-0000-000000000091")!
        let positiveZero = makeDetectedObject(
            idSeed: baseID.uuidString,
            label: "chair",
            confidence: 0.8,
            box: CGRect(x: 0, y: 0, width: 0.2, height: 0.2),
            position: Position3D(x: 0, y: 0, z: -1)
        )
        let negativeZero = makeDetectedObject(
            idSeed: "00000000-0000-0000-0000-000000000092",
            label: "chair",
            confidence: 0.8,
            box: CGRect(x: -0.0, y: -0.0, width: 0.2, height: 0.2),
            position: Position3D(x: -0.0, y: 0, z: -1)
        )
        let positiveSnapshot = SceneAnchorExtractor().makeObjectBindingRequestSnapshot(
            requestID: baseID,
            epoch: 1,
            description: "стул",
            markedObjects: [],
            detectedObjects: [positiveZero]
        )
        let negativeSnapshot = SceneAnchorExtractor().makeObjectBindingRequestSnapshot(
            requestID: baseID,
            epoch: 1,
            description: "стул",
            markedObjects: [],
            detectedObjects: [negativeZero]
        )
        XCTAssertEqual(positiveSnapshot.candidates.map(\.canonicalID), negativeSnapshot.candidates.map(\.canonicalID))

        let invalidDetections: [DetectedObject] = [
            makeDetectedObject(
                idSeed: "00000000-0000-0000-0000-000000000093",
                label: "chair",
                confidence: 0.8,
                box: CGRect(x: .nan, y: 0, width: 0.2, height: 0.2),
                position: Position3D(x: 0, y: 0, z: -1)
            ),
            makeDetectedObject(
                idSeed: "00000000-0000-0000-0000-000000000094",
                label: "chair",
                confidence: 0.8,
                box: CGRect(x: .infinity, y: 0, width: 0.2, height: 0.2),
                position: Position3D(x: 0, y: 0, z: -1)
            ),
            makeDetectedObject(
                idSeed: "00000000-0000-0000-0000-000000000095",
                label: "chair",
                confidence: 0.8,
                box: CGRect(x: 0.9, y: 0, width: 0.2, height: 0.2),
                position: Position3D(x: 0, y: 0, z: -1)
            ),
            makeDetectedObject(
                idSeed: "00000000-0000-0000-0000-000000000096",
                label: "chair",
                confidence: 0.8,
                box: CGRect(x: 0, y: 0, width: 0, height: 0.2),
                position: Position3D(x: 0, y: 0, z: -1)
            ),
            makeDetectedObject(
                idSeed: "00000000-0000-0000-0000-000000000097",
                label: "chair",
                confidence: 0.8,
                box: CGRect(x: 0, y: 0, width: -0.2, height: 0.2),
                position: Position3D(x: 0, y: 0, z: -1)
            ),
            makeDetectedObject(
                idSeed: "00000000-0000-0000-0000-000000000098",
                label: "chair",
                confidence: 0.8,
                box: CGRect(x: 0, y: 0, width: 0.2, height: 0.2),
                position: Position3D(x: .nan, y: 0, z: -1)
            ),
            makeDetectedObject(
                idSeed: "00000000-0000-0000-0000-000000000099",
                label: "chair",
                confidence: 0.8,
                box: CGRect(x: 0, y: 0, width: 0.2, height: 0.2),
                position: Position3D(x: 0, y: .infinity, z: -1)
            ),
        ]
        let invalidSnapshot = SceneAnchorExtractor().makeObjectBindingRequestSnapshot(
            requestID: baseID,
            epoch: 1,
            description: "стул",
            markedObjects: [],
            detectedObjects: invalidDetections
        )
        XCTAssertTrue(invalidSnapshot.candidates.isEmpty)
    }

    func testObjectBindingCanonicalIDsSurviveDetectionReloadRepresentation() {
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let resolver = SceneAnchorExtractor()
        let firstDetection = makeDetectedObject(
            idSeed: "00000000-0000-0000-0000-000000000501",
            label: "chair",
            confidence: 0.8,
            box: CGRect(x: 0.12, y: 0.24, width: 0.32, height: 0.38),
            position: Position3D(x: 0, y: 0, z: -2)
        )
        let reloadedDetection = makeDetectedObject(
            idSeed: "00000000-0000-0000-0000-000000000599",
            label: "chair",
            confidence: 0.8,
            box: CGRect(x: 0.12, y: 0.24, width: 0.32, height: 0.38),
            position: Position3D(x: 0, y: 0, z: -2)
        )
        let object = SceneObject(
            id: "object_stable_chair",
            type: .chair,
            name: "стул",
            relativePosition: .center
        )
        let first = resolveBindings(
            resolver: resolver,
            requestID: requestID,
            description: "стул",
            markers: [],
            detections: [firstDetection],
            objects: [object]
        )
        let reloaded = resolveBindings(
            resolver: resolver,
            requestID: requestID,
            description: "стул",
            markers: [],
            detections: [reloadedDetection],
            objects: [object]
        )
        XCTAssertEqual(first.request.candidates.map(\.canonicalID), reloaded.request.candidates.map(\.canonicalID))
        XCTAssertEqual(
            first.resolution(for: object.id)?.binding?.canonicalID,
            reloaded.resolution(for: object.id)?.binding?.canonicalID
        )
        XCTAssertNotEqual(first.resolution(for: object.id)?.binding?.detectionID, reloaded.resolution(for: object.id)?.binding?.detectionID)
    }

    func testObjectBindingRejectsReuseOfDetectionProvenanceAcrossReferences() throws {
        let marker = makeMarkedObject(
            idSeed: "000000a1-0000-0000-0000-000000000a01",
            name: "стул",
            type: .chair,
            position: Position3D(x: 0, y: 0, z: -1)
        )
        let detection = makeDetectedObject(
            idSeed: "000000a2-0000-0000-0000-000000000a02",
            label: "chair",
            confidence: 0.9,
            box: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3),
            position: marker.worldPosition
        )
        let resolver = SceneAnchorExtractor()
        let request = resolver.makeObjectBindingRequestSnapshot(
            requestID: UUID(uuidString: "000000a0-0000-0000-0000-000000000a00")!,
            epoch: 1,
            description: "стул",
            markedObjects: [marker],
            detectedObjects: [detection]
        )
        let detectedCandidate = try XCTUnwrap(request.candidates.first(where: { $0.source == .detected }))
        let explicitDetectionObject = SceneObject(
            id: detectedCandidate.canonicalID,
            type: .chair,
            name: "chair",
            relativePosition: .center
        )
        let aliasObject = SceneObject(
            id: "object_alias_detection_reuse",
            type: .chair,
            name: "chair",
            relativePosition: .center
        )

        let result = resolver.resolveObjectBindings(
            scriptObjects: [explicitDetectionObject, aliasObject],
            request: request
        )

        XCTAssertEqual(result.resolution(for: explicitDetectionObject.id)?.state, .ambiguous)
        XCTAssertEqual(result.resolution(for: aliasObject.id)?.state, .ambiguous)
        XCTAssertTrue(result.diagnostics.contains {
            $0.contains("candidate_already_bound")
        })
    }

    func testChunkCanonicalizerPreservesRepeatedNonMarkedProviderObjects() throws {
        let canonicalizer = ChunkCanonicalizer()
        let firstRef = "provider_chair_1"
        let secondRef = "provider_chair_2"
        let draft = SceneChunkDraft(
            sceneID: "scene_1",
            chunkID: "scene_1_chunk_1",
            chunkIndex: 0,
            sourceText: "Человек подходит к стулу и стулу.",
            sourceRange: .init(start: 0, end: 34),
            anchors: .empty,
            registrySnapshot: .empty,
            plan: ScenePlanIR(
                actors: [.init(ref: "first", type: .human)],
                objects: [
                    .init(ref: firstRef, type: .chair, relativePosition: .center, name: "стул"),
                    .init(ref: secondRef, type: .chair, relativePosition: .center, name: "стул"),
                ],
                beats: [
                    .init(
                        ref: "beat_1",
                        actions: [
                            .init(actorRef: "first", type: .walk, targetRef: firstRef),
                            .init(actorRef: "first", type: .lookAt, targetRef: secondRef),
                        ]
                    ),
                ],
                spatialRelations: [],
                referenceBindings: .init()
            ),
            usedFallbackPlanner: false,
            usedLegacyPlanBridge: false,
            confidence: 0.9,
            unresolvedMentions: [],
            reasonCodes: []
        )

        let chunk = canonicalizer.canonicalize(draft: draft, stitchState: nil)
        let canonicalRefs = chunk.registryPatch.objects.map(\.ref)

        XCTAssertEqual(canonicalRefs.count, 2)
        XCTAssertEqual(Set(canonicalRefs).count, 2)
        XCTAssertNil(chunk.registryPatch.objectAliasMap["стул"])
        XCTAssertTrue(chunk.reasonCodes.contains("v9.ambiguous_object_alias"))
        let targetRefs = Set(chunk.beatPatch.flatMap(\.actions).compactMap(\.targetRef))
        XCTAssertEqual(targetRefs, Set(canonicalRefs))
    }

    @MainActor
    func testUnresolvedObjectBindingStopsBeforeSceneCommitOrSuccess() async {
        let projectName = "binding-clarification-\(UUID().uuidString)"
        let viewModel = SceneGeneratorViewModel(projectName: projectName)
        addTeardownBlock { @MainActor in
            _ = await viewModel.teardownAndWait()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DBService.shared.deleteUnifiedSceneProject(named: projectName) { _ in
                    continuation.resume()
                }
            }
        }

        var cameraTransform = matrix_identity_float4x4
        cameraTransform.columns.3 = SIMD4<Float>(0, 1.5, 0, 1)
        viewModel.testingSetPlanningContext(
            cameraTransform: cameraTransform,
            planes: [ScenePlaneSnapshot(alignment: .horizontal, y: 0)]
        )
        viewModel.sceneDescription = "актёр подходит к одному из стульев"
        viewModel.testingSetGenerationDelay(60)
        viewModel.testingResetGenerationStateTrace()

        let generation = Task { @MainActor in
            await viewModel.generateScene()
        }
        for _ in 0..<100 where viewModel.generationStage != .reading {
            await Task.yield()
        }
        XCTAssertEqual(viewModel.generationStage, .reading)
        let requestID = try! XCTUnwrap(viewModel.generationRequestState.requestID)
        let epoch = try! XCTUnwrap(viewModel.generationRequestState.epoch)
        let markerA = makeMarkedObject(
            idSeed: "00000061-0000-0000-0000-000000000601",
            name: "стул",
            type: .chair,
            position: Position3D(x: -1, y: 0, z: -1)
        )
        let markerB = makeMarkedObject(
            idSeed: "00000062-0000-0000-0000-000000000602",
            name: "стул",
            type: .chair,
            position: Position3D(x: 1, y: 0, z: -1)
        )
        let unresolved = resolveBindings(
            resolver: SceneAnchorExtractor(),
            requestID: requestID,
            epoch: epoch,
            description: "актёр подходит к одному из стульев",
            markers: [markerA, markerB],
            detections: [],
            objects: [
                SceneObject(
                    id: "object_ambiguous_chair",
                    type: .chair,
                    name: "стул",
                    relativePosition: .center
                ),
            ]
        )
        let stale = resolveBindings(
            resolver: SceneAnchorExtractor(),
            requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
            epoch: epoch,
            description: "актёр подходит к одному из стульев",
            markers: [markerA, markerB],
            detections: [],
            objects: [
                SceneObject(
                    id: "object_ambiguous_chair",
                    type: .chair,
                    name: "стул",
                    relativePosition: .center
                ),
            ]
        )

        XCTAssertFalse(viewModel.testingPublishObjectBindingResult(stale))
        XCTAssertEqual(viewModel.generationRequestState.phase, .generating)
        XCTAssertNil(viewModel.objectBindingResult)

        XCTAssertTrue(viewModel.testingPublishObjectBindingResult(unresolved))
        XCTAssertEqual(viewModel.generationRequestState.phase, .clarification)
        XCTAssertEqual(viewModel.objectBindingResult, unresolved)
        XCTAssertNil(viewModel.parsedScript)
        XCTAssertNil(viewModel.parsingResult)
        XCTAssertNil(viewModel.plannedScene)
        XCTAssertFalse(viewModel.testingGenerationStateTrace.contains { $0.phase == .success })

        _ = await viewModel.teardownAndWait()
        await generation.value
        XCTAssertFalse(viewModel.testingGenerationStateTrace.contains { $0.phase == .success })
    }

    @MainActor
    func testRealGenerationPathStopsBeforeCommitForUnresolvedObjectBinding() async throws {
        let projectName = "binding-production-gate-\(UUID().uuidString)"
        let viewModel = SceneGeneratorViewModel(projectName: projectName)
        addTeardownBlock { @MainActor in
            _ = await viewModel.teardownAndWait()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DBService.shared.deleteUnifiedSceneProject(named: projectName) { _ in
                    continuation.resume()
                }
            }
        }

        var cameraTransform = matrix_identity_float4x4
        cameraTransform.columns.3 = SIMD4<Float>(0, 1.5, 0, 1)
        viewModel.testingSetPlanningContext(
            cameraTransform: cameraTransform,
            planes: [ScenePlaneSnapshot(alignment: .horizontal, y: 0)]
        )
        let markerA = makeMarkedObject(
            idSeed: "000000a1-0000-0000-0000-000000000a01",
            name: "стул",
            type: .chair,
            position: Position3D(x: -1, y: 0, z: -1)
        )
        let markerB = makeMarkedObject(
            idSeed: "000000a2-0000-0000-0000-000000000a02",
            name: "стул",
            type: .chair,
            position: Position3D(x: 1, y: 0, z: -1)
        )
        viewModel.markedObjects = [markerA, markerB]
        viewModel.sceneDescription = "Человек подходит к одному из стульев."
        let script = SceneScript(
            actors: [SceneActor(id: "actor_1", type: .human, name: "Человек")],
            objects: [
                SceneObject(
                    id: "object_ambiguous_chair",
                    type: .chair,
                    name: "стул",
                    relativePosition: .center
                )
            ],
            beats: [
                SceneBeat(
                    id: "beat_1",
                    actions: [
                        SceneAction(
                            id: "action_1",
                            actorId: "actor_1",
                            type: .stand
                        )
                    ]
                )
            ],
            spatialRelations: [],
            originalDescription: viewModel.sceneDescription
        )
        viewModel.testingSetParserResultOverride { _, _ in
            ParsingResult(script: script, diagnostics: .empty)
        }
        viewModel.testingResetGenerationStateTrace()
        let before = DBService.shared.loadUnifiedSceneProject(named: projectName)?.0

        await viewModel.generateScene()

        XCTAssertEqual(viewModel.generationRequestState.phase, .clarification)
        XCTAssertEqual(
            viewModel.objectBindingResult?.resolution(for: "object_ambiguous_chair")?.state,
            .ambiguous
        )
        XCTAssertNil(viewModel.parsedScript)
        XCTAssertNil(viewModel.plannedScene)
        XCTAssertFalse(viewModel.testingGenerationStateTrace.contains { $0.phase == .success })
        XCTAssertEqual(viewModel.testingProjectSnapshotSaveCount, 0)

        let after = DBService.shared.loadUnifiedSceneProject(named: projectName)?.0
        XCTAssertEqual(after?.parsedScript, before?.parsedScript)
        XCTAssertEqual(after?.plannedScene, before?.plannedScene)
    }

    @MainActor
    func testRealGenerationPathUsesNaturalLanguageMarkerAmbiguityGateWithoutOverride() async throws {
        let projectName = "binding-natural-language-gate-\(UUID().uuidString)"
        let viewModel = SceneGeneratorViewModel(projectName: projectName)
        addTeardownBlock { @MainActor in
            _ = await viewModel.teardownAndWait()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DBService.shared.deleteUnifiedSceneProject(named: projectName) { _ in
                    continuation.resume()
                }
            }
        }

        var cameraTransform = matrix_identity_float4x4
        cameraTransform.columns.3 = SIMD4<Float>(0, 1.5, 0, 1)
        viewModel.testingSetPlanningContext(
            cameraTransform: cameraTransform,
            planes: [ScenePlaneSnapshot(alignment: .horizontal, y: 0)]
        )
        viewModel.markedObjects = [
            makeMarkedObject(
                idSeed: "000000b1-0000-0000-0000-000000000b01",
                name: "стул",
                type: .chair,
                position: Position3D(x: -1, y: 0, z: -1)
            ),
            makeMarkedObject(
                idSeed: "000000b2-0000-0000-0000-000000000b02",
                name: "стул",
                type: .chair,
                position: Position3D(x: 1, y: 0, z: -1)
            ),
        ]
        viewModel.sceneDescription = "Человек подходит к одному из стульев."
        viewModel.testingResetGenerationStateTrace()
        let before = DBService.shared.loadUnifiedSceneProject(named: projectName)?.0

        await viewModel.generateScene()

        XCTAssertEqual(viewModel.generationRequestState.phase, .clarification)
        XCTAssertNil(viewModel.parsedScript)
        XCTAssertNil(viewModel.plannedScene)
        XCTAssertTrue(viewModel.showInputSheet)
        XCTAssertFalse(viewModel.canSubmitScene)
        XCTAssertEqual(viewModel.clarificationRequest?.requestID, viewModel.generationRequestState.requestID)
        XCTAssertEqual(viewModel.clarificationRequest?.epoch, viewModel.generationRequestState.epoch)
        XCTAssertEqual(viewModel.clarificationRequest?.options.count, 2)
        XCTAssertTrue(viewModel.clarificationRequest?.options.allSatisfy { !$0.id.isEmpty } == true)
        XCTAssertFalse(viewModel.testingGenerationStateTrace.contains { $0.phase == .success })
        XCTAssertEqual(viewModel.testingGenerationCommitCount, 0)
        XCTAssertEqual(viewModel.testingProjectSnapshotSaveCount, 0)
        let after = DBService.shared.loadUnifiedSceneProject(named: projectName)?.0
        XCTAssertEqual(after?.parsedScript, before?.parsedScript)
        XCTAssertEqual(after?.plannedScene, before?.plannedScene)

        let clarification = try XCTUnwrap(viewModel.clarificationRequest)
        let requestID = try XCTUnwrap(viewModel.generationRequestState.requestID)
        let epoch = try XCTUnwrap(viewModel.generationRequestState.epoch)
        let answer = await viewModel.submitClarificationAnswer(
            .choice(clarification.options[0].id),
            for: clarification
        )

        XCTAssertEqual(answer, .accepted)
        XCTAssertEqual(viewModel.generationRequestState.phase, .success)
        XCTAssertEqual(viewModel.generationRequestState.requestID, requestID)
        XCTAssertEqual(viewModel.generationRequestState.epoch, epoch)
        XCTAssertNotNil(viewModel.parsedScript)
        XCTAssertNotNil(viewModel.plannedScene)
        XCTAssertEqual(viewModel.testingGenerationCommitCount, 1)
        XCTAssertEqual(viewModel.testingGenerationStateTrace.filter { $0.phase == .success }.count, 1)
    }

    @MainActor
    func testClarificationAnswerResumesSameRequestOnceAndCommits() async throws {
        let projectName = "binding-clarification-answer-\(UUID().uuidString)"
        let viewModel = SceneGeneratorViewModel(projectName: projectName)
        addTeardownBlock { @MainActor in
            _ = await viewModel.teardownAndWait()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DBService.shared.deleteUnifiedSceneProject(named: projectName) { _ in
                    continuation.resume()
                }
            }
        }

        var cameraTransform = matrix_identity_float4x4
        cameraTransform.columns.3 = SIMD4<Float>(0, 1.5, 0, 1)
        viewModel.testingSetPlanningContext(
            cameraTransform: cameraTransform,
            planes: [ScenePlaneSnapshot(alignment: .horizontal, y: 0)]
        )
        let markers = [
            makeMarkedObject(
                idSeed: "000000c1-0000-0000-0000-000000000c01",
                name: "стул",
                type: .chair,
                position: Position3D(x: -1, y: 0, z: -1)
            ),
            makeMarkedObject(
                idSeed: "000000c2-0000-0000-0000-000000000c02",
                name: "стул",
                type: .chair,
                position: Position3D(x: 1, y: 0, z: -1)
            ),
        ]
        viewModel.markedObjects = markers
        viewModel.sceneDescription = "Человек подходит к одному из стульев."
        let script = SceneScript(
            actors: [SceneActor(id: "actor_1", type: .human, name: "Человек")],
            objects: [
                SceneObject(
                    id: "object_chair",
                    type: .chair,
                    name: "стул",
                    relativePosition: .center
                )
            ],
            beats: [
                SceneBeat(
                    id: "beat_1",
                    actions: [
                        SceneAction(
                            id: "action_1",
                            actorId: "actor_1",
                            type: .stand
                        )
                    ]
                )
            ],
            spatialRelations: [],
            originalDescription: viewModel.sceneDescription
        )
        var parserCallCount = 0
        viewModel.testingSetParserResultOverride { _, _ in
            parserCallCount += 1
            return ParsingResult(script: script, diagnostics: .empty)
        }

        await viewModel.generateScene()

        let clarification = try XCTUnwrap(viewModel.clarificationRequest)
        let requestID = try XCTUnwrap(viewModel.generationRequestState.requestID)
        let epoch = try XCTUnwrap(viewModel.generationRequestState.epoch)
        XCTAssertEqual(parserCallCount, 1)
        XCTAssertEqual(viewModel.testingGenerationOwnerCount, 1)

        let answer = await viewModel.submitClarificationAnswer(
            .choice(clarification.options[0].id),
            for: clarification
        )

        XCTAssertEqual(answer, .accepted)
        XCTAssertEqual(parserCallCount, 2)
        XCTAssertEqual(viewModel.testingGenerationOwnerCount, 1)
        XCTAssertEqual(viewModel.generationRequestState.phase, .success)
        XCTAssertEqual(viewModel.generationRequestState.requestID, requestID)
        XCTAssertEqual(viewModel.generationRequestState.epoch, epoch)
        XCTAssertNil(viewModel.clarificationRequest)
        XCTAssertNotNil(viewModel.plannedScene)
        XCTAssertEqual(viewModel.testingGenerationStateTrace.filter { $0.phase == .validating }.count, 2)
    }

    @MainActor
    func testClarificationCancelReturnsDraftAndClearsRequest() async throws {
        let projectName = "binding-clarification-cancel-\(UUID().uuidString)"
        let viewModel = SceneGeneratorViewModel(projectName: projectName)
        addTeardownBlock { @MainActor in
            _ = await viewModel.teardownAndWait()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DBService.shared.deleteUnifiedSceneProject(named: projectName) { _ in
                    continuation.resume()
                }
            }
        }

        var cameraTransform = matrix_identity_float4x4
        cameraTransform.columns.3 = SIMD4<Float>(0, 1.5, 0, 1)
        viewModel.testingSetPlanningContext(
            cameraTransform: cameraTransform,
            planes: [ScenePlaneSnapshot(alignment: .horizontal, y: 0)]
        )
        viewModel.markedObjects = [
            makeMarkedObject(
                idSeed: "000000d1-0000-0000-0000-000000000d01",
                name: "стул",
                type: .chair,
                position: Position3D(x: -1, y: 0, z: -1)
            ),
            makeMarkedObject(
                idSeed: "000000d2-0000-0000-0000-000000000d02",
                name: "стул",
                type: .chair,
                position: Position3D(x: 1, y: 0, z: -1)
            ),
        ]
        viewModel.sceneDescription = "Человек подходит к одному из стульев."
        viewModel.testingSetParserResultOverride { _, _ in
            ParsingResult(
                script: SceneScript(
                    actors: [SceneActor(id: "actor_1", type: .human, name: "Человек")],
                    objects: [SceneObject(id: "object_chair", type: .chair, name: "стул", relativePosition: .center)],
                    beats: [],
                    spatialRelations: [],
                    originalDescription: "Человек подходит к одному из стульев."
                ),
                diagnostics: .empty
            )
        }

        await viewModel.generateScene()
        XCTAssertNotNil(viewModel.clarificationRequest)
        let draft = viewModel.sceneDescription

        await viewModel.cancelGeneration()

        XCTAssertEqual(viewModel.sceneDescription, draft)
        XCTAssertEqual(viewModel.generationRequestState.phase, .input)
        XCTAssertNil(viewModel.clarificationRequest)
        XCTAssertNil(viewModel.clarificationFeedback)
        XCTAssertNil(viewModel.objectBindingResult)
        XCTAssertFalse(viewModel.isGenerating)

        // A second request proves teardown retires an active clarification,
        // not just an already-cancelled draft.
        await viewModel.generateScene()
        XCTAssertEqual(viewModel.generationRequestState.phase, .clarification)
        XCTAssertNotNil(viewModel.clarificationRequest)
        _ = await viewModel.teardownAndWait()
        XCTAssertEqual(viewModel.generationRequestState.phase, .idle)
        XCTAssertNil(viewModel.clarificationRequest)
    }

    @MainActor
    func testClarificationRejectsStaleRepeatedAndBoundedInvalidAnswers() async throws {
        let projectName = "binding-clarification-rejections-\(UUID().uuidString)"
        let viewModel = SceneGeneratorViewModel(projectName: projectName)
        addTeardownBlock { @MainActor in
            _ = await viewModel.teardownAndWait()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DBService.shared.deleteUnifiedSceneProject(named: projectName) { _ in
                    continuation.resume()
                }
            }
        }

        var cameraTransform = matrix_identity_float4x4
        cameraTransform.columns.3 = SIMD4<Float>(0, 1.5, 0, 1)
        viewModel.testingSetPlanningContext(
            cameraTransform: cameraTransform,
            planes: [ScenePlaneSnapshot(alignment: .horizontal, y: 0)]
        )
        viewModel.markedObjects = [
            makeMarkedObject(
                idSeed: "000000e1-0000-0000-0000-000000000e01",
                name: "стул",
                type: .chair,
                position: Position3D(x: -1, y: 0, z: -1)
            ),
            makeMarkedObject(
                idSeed: "000000e2-0000-0000-0000-000000000e02",
                name: "стул",
                type: .chair,
                position: Position3D(x: 1, y: 0, z: -1)
            ),
        ]
        viewModel.sceneDescription = "Человек подходит к одному из стульев."
        var parserCallCount = 0
        viewModel.testingSetParserResultOverride { _, _ in
            parserCallCount += 1
            return ParsingResult(
                script: SceneScript(
                    actors: [],
                    objects: [SceneObject(id: "object_chair", type: .chair, name: "стул", relativePosition: .center)],
                    beats: [],
                    spatialRelations: [],
                    originalDescription: "Человек подходит к одному из стульев."
                ),
                diagnostics: .empty
            )
        }

        await viewModel.generateScene()
        let clarification = try XCTUnwrap(viewModel.clarificationRequest)
        let requestID = try XCTUnwrap(clarification.requestID)
        let epoch = clarification.epoch
        let staleRequest = await viewModel.submitClarificationAnswer(
            .choice(clarification.options[0].id),
            requestID: UUID(),
            epoch: epoch,
            clarificationID: clarification.id
        )
        XCTAssertEqual(staleRequest, .rejected(.staleRequest))
        XCTAssertEqual(viewModel.generationRequestState.phase, .clarification)
        XCTAssertEqual(parserCallCount, 1)

        let staleEpoch = await viewModel.submitClarificationAnswer(
            .choice(clarification.options[0].id),
            requestID: requestID,
            epoch: epoch &+ 1,
            clarificationID: clarification.id
        )
        XCTAssertEqual(staleEpoch, .rejected(.staleRequest))

        let invalid = await viewModel.submitClarificationAnswer(
            .choice("not-an-observed-candidate"),
            for: clarification
        )
        XCTAssertEqual(invalid, .rejected(.invalidAnswer))
        let currentClarification = try XCTUnwrap(viewModel.clarificationRequest)
        XCTAssertNotEqual(currentClarification.id, clarification.id)
        let previousAttempt = await viewModel.submitClarificationAnswer(
            .choice(clarification.options[0].id),
            requestID: requestID,
            epoch: epoch,
            clarificationID: clarification.id
        )
        XCTAssertEqual(previousAttempt, .rejected(.staleRequest))
        let repeated = await viewModel.submitClarificationAnswer(
            .choice("not-an-observed-candidate"),
            requestID: requestID,
            epoch: epoch,
            clarificationID: currentClarification.id
        )
        XCTAssertEqual(repeated, .rejected(.repeatedAnswer))
        let invalidTwoPayload = try XCTUnwrap(viewModel.clarificationRequest)
        _ = await viewModel.submitClarificationAnswer(
            .choice("invalid-two"),
            for: invalidTwoPayload
        )
        let invalidThreePayload = try XCTUnwrap(viewModel.clarificationRequest)
        _ = await viewModel.submitClarificationAnswer(
            .choice("invalid-three"),
            for: invalidThreePayload
        )
        let exhaustedPayload = try XCTUnwrap(viewModel.clarificationRequest)
        let exhausted = await viewModel.submitClarificationAnswer(
            .choice("invalid-four"),
            for: exhaustedPayload
        )

        XCTAssertEqual(exhausted, .rejected(.retryLimitReached))
        XCTAssertEqual(viewModel.clarificationAttemptsRemaining, 0)
        XCTAssertEqual(viewModel.generationRequestState.phase, .clarification)
        XCTAssertEqual(parserCallCount, 1)

        viewModel.sceneDescription += " Новая попытка."
        await viewModel.generateScene()
        let newClarification = try XCTUnwrap(viewModel.clarificationRequest)
        XCTAssertNotEqual(newClarification.requestID, clarification.requestID)
        let staleAfterNewRequest = await viewModel.submitClarificationAnswer(
            .choice(clarification.options[0].id),
            for: clarification
        )
        XCTAssertEqual(staleAfterNewRequest, .rejected(.staleRequest))
        XCTAssertEqual(viewModel.generationRequestState.phase, .clarification)
        XCTAssertEqual(parserCallCount, 2)
    }

    private func resolveBindings(
        resolver: SceneAnchorExtractor,
        requestID: UUID,
        epoch: UInt = 9,
        description: String,
        markers: [MarkedObject],
        detections: [DetectedObject],
        aliasToObjectRef: [String: String] = [:],
        objects: [SceneObject]
    ) -> SceneObjectBindingResult {
        let request = resolver.makeObjectBindingRequestSnapshot(
            requestID: requestID,
            epoch: epoch,
            description: description,
            markedObjects: Array(markers),
            detectedObjects: Array(detections),
            aliasToObjectRef: aliasToObjectRef
        )
        return resolver.resolveObjectBindings(scriptObjects: Array(objects), request: request)
    }

    private func makeMarkedObject(
        idSeed: String,
        name: String,
        type: SceneObject.ObjectType,
        position: Position3D
    ) -> MarkedObject {
        var payload = try! JSONSerialization.jsonObject(
            with: JSONEncoder().encode(MarkedObject(name: name, position: position))
        ) as! [String: Any]
        payload["id"] = idSeed
        payload["type"] = type.rawValue
        return try! JSONDecoder().decode(
            MarkedObject.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )
    }

    private func makeDetectedObject(
        idSeed: String,
        label: String,
        confidence: Float,
        box: CGRect,
        position: Position3D
    ) -> DetectedObject {
        DetectedObject(
            id: UUID(uuidString: idSeed)!,
            label: label,
            confidence: confidence,
            boundingBox: box,
            worldPosition: position
        )
    }
}
