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

    /// M6-010 publication path: the workspace publishes the binding from the
    /// real persisted plan (not just the pure resolver), suppresses it while
    /// tracking is unstable, and re-resolves the exact same entity identity
    /// after recovery. This is the regression guard for the reviewer finding
    /// that the published binding could go stale relative to the plan.
    func testWorkspacePublishesBindingAndSurvivesPostureRecovery() async throws {
        let projectName = "m6-010-binding-\(UUID().uuidString)"
        var project = UnifiedSceneProject(name: projectName)
        project.parsedScript = script()

        let viewModel = SceneGeneratorViewModel(
            projectName: projectName,
            isNewProject: false,
            persistedProject: project
        )
        viewModel.testingWorldMapCaptureOverride = { .success(nil) }
        addTeardownBlock { @MainActor in
            _ = await viewModel.teardownAndWait()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DBService.shared.deleteUnifiedSceneProject(named: projectName) { _ in
                    continuation.resume()
                }
            }
        }

        // Init recomputes from the persisted plan: first beat's real IDs.
        let initial = try XCTUnwrap(viewModel.sceneHintBinding)
        XCTAssertEqual(initial.beatID, "beat_1")
        XCTAssertEqual(initial.actionID, "action_1")
        XCTAssertEqual(initial.actorID, "actor_1")
        XCTAssertEqual(initial.actorName, "МАРА")
        XCTAssertEqual(initial.targetID, "object_marked_deadbeef")

        // Unstable tracking suppresses honestly instead of showing a stale bind.
        viewModel.updateSurfaceTrackingPosture(isLimited: true, reason: .insufficientFeatures)
        XCTAssertNil(viewModel.sceneHintBinding)

        // Recovery re-resolves the identical plan identity.
        viewModel.updateSurfaceTrackingPosture(isLimited: false)
        let recovered = try XCTUnwrap(viewModel.sceneHintBinding)
        XCTAssertEqual(recovered, initial)
    }
}
