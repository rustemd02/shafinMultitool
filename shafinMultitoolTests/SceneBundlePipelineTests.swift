//
//  SceneBundlePipelineTests.swift
//  shafinMultitoolTests
//
//  Created on 22.04.2026.
//

import XCTest
import simd
@testable import shafinMultitool

final class SceneBundlePipelineTests: XCTestCase {
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

    private var parser: SceneParserService!

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

    private func makeBundlePipeline(result: ScenePlanProviderResult?) -> SceneBundlePipeline {
        SceneBundlePipeline(
            anchorExtractor: SceneAnchorExtractor(),
            metadataExtractor: SceneMetadataExtractor(),
            localProvider: StubLocalProvider(result: result),
            planCompiler: ScenePlanCompiler()
        )
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
        XCTAssertEqual(result.bundleScript.activeSceneIndex, 1)
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
        XCTAssertEqual(script.actors.count, 2)
        XCTAssertEqual(script.beats.count, 2)
        XCTAssertFalse(result.chunkDiagnostics.contains { $0.usedFallbackPlanner })

        let talkAction = script.beats.flatMap { $0.actions }.first(where: { $0.type == SceneAction.ActionType.talk })
        XCTAssertEqual(talkAction?.dialogue, "Положи коробку сюда, потом разберём")

        let putDownAction = try XCTUnwrap(script.beats.flatMap { $0.actions }.first(where: { $0.type == SceneAction.ActionType.putDown }))
        XCTAssertNotNil(putDownAction.target)
        XCTAssertNotNil(putDownAction.holdingObject)
        XCTAssertEqual(script.objects.count, 2)
    }

    func testBundlePipelinePreservesDialoguePickUpGiveToThirdPattern() async throws {
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
        XCTAssertEqual(script.actors.count, 3)
        XCTAssertEqual(script.beats.count, 3)
        XCTAssertFalse(result.chunkDiagnostics.contains { $0.usedFallbackPlanner })

        let talkActions = script.beats.flatMap { $0.actions }.filter { $0.type == SceneAction.ActionType.talk }
        XCTAssertEqual(talkActions.count, 2)

        let pickUpAction = try XCTUnwrap(script.beats.flatMap { $0.actions }.first(where: { $0.type == SceneAction.ActionType.pickUp }))
        XCTAssertEqual(pickUpAction.holdingObject, script.objects.first?.id)

        let giveAction = try XCTUnwrap(script.beats.flatMap { $0.actions }.first(where: { $0.type == SceneAction.ActionType.give }))
        XCTAssertNotNil(giveAction.target)
        XCTAssertEqual(giveAction.holdingObject, script.objects.first?.id)
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
        XCTAssertEqual(script.actors.count, 2)

        let walkActions = script.beats.flatMap(\.actions).filter { $0.type == .walk }
        XCTAssertEqual(walkActions.count, 2)
        XCTAssertEqual(Set(walkActions.compactMap(\.target)), Set(["actor_1", "actor_2"]))

        let stopActions = script.beats.flatMap(\.actions).filter { $0.type == .stop }
        XCTAssertEqual(stopActions.count, 2)
        XCTAssertTrue(stopActions.allSatisfy { $0.target == marker.canonicalMarkedObjectID })

        let describedAction = try XCTUnwrap(script.beats.flatMap(\.actions).first(where: { $0.type == .describedAction }))
        XCTAssertEqual(describedAction.actorId, "actor_2")
        XCTAssertTrue(describedAction.fallbackText?.contains("поправляет воротник") ?? false)
        XCTAssertTrue(result.chunkDiagnostics.flatMap(\.reasonCodes).contains("v1.unsupported_action_described"))
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
}
