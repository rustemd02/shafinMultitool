import simd
import XCTest
@testable import shafinMultitool

@MainActor
final class GenerationSuccessProvenanceTests: XCTestCase {
    private final class MissingLocalProvider: LocalScenePlanProvider {
        func generatePlan(description: String, markedObjects: [MarkedObject], anchors: SourceAnchorBundle, state: SceneChunkState?) -> ScenePlanProviderResult? { nil }
        func generatePlanAsync(description: String, markedObjects: [MarkedObject], anchors: SourceAnchorBundle, state: SceneChunkState?) async -> ScenePlanProviderResult? { nil }
    }

    func testSuccessfulGenerationPersistsActualRuleOrigin() async throws {
        let projectName = "provenance-\(UUID().uuidString)"
        let parser = SceneParserService(localProvider: MissingLocalProvider())
        let viewModel = SceneGeneratorViewModel(projectName: projectName, parserService: parser)
        addTeardownBlock { @MainActor in
            _ = await viewModel.teardownAndWait()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DBService.shared.deleteUnifiedSceneProject(named: projectName) { _ in continuation.resume() }
            }
        }
        var cameraTransform = matrix_identity_float4x4
        cameraTransform.columns.3 = SIMD4<Float>(0, 1.5, 0, 1)
        viewModel.testingSetPlanningContext(
            cameraTransform: cameraTransform,
            planes: [ScenePlaneSnapshot(alignment: .horizontal, y: 0)]
        )
        viewModel.sceneDescription = "Марина стоит."
        viewModel.updateGenerationMotionPreferences(reduceMotion: true)
        await viewModel.generateScene()
        XCTAssertEqual(viewModel.generationRequestState.phase, .success)
        let provenance = try XCTUnwrap(viewModel.plannedScene?.provenance)
        XCTAssertEqual(provenance.formatVersion, 2)
        XCTAssertNil(provenance.modelContractVersion)
        XCTAssertEqual(provenance.schemaVersion, SceneAPIVersion.scriptSchemaVersion)
        XCTAssertTrue(provenance.acceptedContributors.contains(.deterministicRules(componentVersion: "scene-rule-parser-v1")))
        XCTAssertEqual(DBService.shared.loadUnifiedSceneProject(named: projectName)?.0.plannedScene?.provenance, provenance)
    }

    func testLegacyProjectsDoNotAcquireInventedSceneOrigin() throws {
        let noOrigin = Data(#"{"placedActors":[],"placedObjects":[]}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(PlannedScene.self, from: noOrigin).provenance)
        let oldStamp = Data(#"{"generatorVersion":"scene-generator-v1","modelContractVersion":"historical-camera-contract","schemaVersion":"scene-annotation-v1"}"#.utf8)
        let decoded = try JSONDecoder().decode(GenerationProvenance.self, from: oldStamp)
        XCTAssertEqual(decoded.formatVersion, 1)
        XCTAssertEqual(decoded.modelContractVersion, "historical-camera-contract")
        XCTAssertNil(decoded.chunks)
        XCTAssertNil(decoded.directContributors)
        XCTAssertEqual(decoded.acceptedContributors, [.unknown(stage: .unrecordedSource)])
        let roundTrip = try JSONDecoder().decode(GenerationProvenance.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(roundTrip, decoded)
        let edited = decoded.recordingUserModification(.scriptEdit, at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(edited.formatVersion, 1)
        XCTAssertEqual(edited.modelContractVersion, decoded.modelContractVersion)
        XCTAssertNil(edited.chunks)
    }

    func testActiveSceneKeepsMixedChunkIdentityAndReusedReceipt() throws {
        let remote = SceneGenerationContributor.remoteService(SceneRemoteGenerationReceipt(
            jobID: "job-fixture", requestID: UUID(), requestHash: String(repeating: "a", count: 64),
            idempotencyKey: "fixture-generation", backendSchemaVersion: SceneAPIVersion.backendSchemaVersion,
            scriptSchemaVersion: SceneAPIVersion.scriptSchemaVersion, modelVersion: "declared-model",
            promptVersion: "declared-prompt", providerName: "declared-provider", providerVersion: "declared-version"
        ))
        let first = chunk(scene: "active", id: "original-chunk", index: 0, contributors: [remote])
        let second = chunk(scene: "active", id: "appended-chunk", index: 1, contributors: [.deterministicRules(componentVersion: "rules-fixture")])
        let other = chunk(scene: "other", id: "other-scene-chunk", index: 0, contributors: [.unknown(stage: .planIR)])
        let provenance = GenerationProvenance.activeScene(
            sceneID: "active", sourceText: "First. Second.", chunks: [other, second, first]
        )
        XCTAssertEqual(provenance.chunks?.map(\.chunkID), ["original-chunk", "appended-chunk"])
        XCTAssertEqual(provenance.chunks?.first, first.generationProvenance)
        XCTAssertEqual(provenance.acceptedContributors, [remote, .deterministicRules(componentVersion: "rules-fixture")])
        XCTAssertNil(provenance.modelContractVersion)
        let encoded = try JSONEncoder().encode(provenance)
        XCTAssertNil((try JSONSerialization.jsonObject(with: encoded) as? [String: Any])?["modelContractVersion"])
        XCTAssertEqual(try JSONDecoder().decode(GenerationProvenance.self, from: encoded), provenance)
    }

    func testLegacyChunkWithoutReceiptRemainsExplicitlyUnknown() throws {
        var oldChunk = chunk(scene: "scene", id: "legacy-chunk", index: 0, contributors: nil)
        oldChunk.generationProvenance = nil
        let encoded = try JSONEncoder().encode(oldChunk)
        let decoded = try JSONDecoder().decode(SceneChunk.self, from: encoded)
        XCTAssertNil(decoded.generationProvenance)
        let provenance = GenerationProvenance.activeScene(sceneID: "scene", sourceText: "Text", chunks: [decoded])
        XCTAssertEqual(provenance.acceptedContributors, [.unknown(stage: .legacyChunk)])
        XCTAssertNil(provenance.chunks?.first?.runtimeMode)
        XCTAssertNil(provenance.chunks?.first?.providerRoute)
    }

    func testActualArtifactBytesDetermineIdentityWithoutInventedWeightVersion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("scene-artifact-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("same-name.gguf")
        try Data("first artifact".utf8).write(to: url)
        let first = try SceneLocalModelArtifact.identify(at: url)
        try Data("second artifact with different bytes".utf8).write(to: url)
        let second = try SceneLocalModelArtifact.identify(at: url)
        XCTAssertEqual(first.filename, second.filename)
        XCTAssertEqual(first.sha256, GenerationProvenance.sha256("first artifact"))
        XCTAssertNotEqual(first.sha256, second.sha256)
        XCTAssertEqual(second.byteCount, UInt64(Data("second artifact with different bytes".utf8).count))
        XCTAssertThrowsError(try SceneLocalModelArtifact.identify(at: directory.appendingPathComponent("missing.gguf")))
    }

    private func chunk(scene: String, id: String, index: Int, contributors: [SceneGenerationContributor]?) -> SceneChunk {
        let text = "Text \(index)"
        let range = ScriptOffsetRange(start: index * 10, end: index * 10 + text.count)
        return SceneChunk(
            sceneID: scene, chunkID: id, chunkIndex: index, sourceText: text, sourceRange: range,
            anchors: .empty, registryPatch: .empty, beatPatch: [], spatialRelationPatch: [],
            stateDelta: .empty, deferredRefs: [], reasonCodes: [],
            usedFallbackPlanner: false, usedLegacyPlanBridge: false,
            generationProvenance: SceneChunkGenerationProvenance(
                sceneID: scene, chunkID: id, chunkIndex: index, sourceRange: range, sourceText: text,
                runtimeMode: "v9_full", contributors: contributors ?? [.unknown(stage: .unrecordedSource)]
            )
        )
    }
}
